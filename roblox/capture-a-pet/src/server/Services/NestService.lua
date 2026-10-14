-- Guarded nests on the lane. Grab a wild egg and run home: the nest guard chases you.
-- The longer you stay ahead of a guard, the stronger the egg's wild aura gets.
-- Glow Bait lures guards away for a few seconds. Delivering eggs from all four zones
-- completes an expedition. The Dragon Lair reuses the egg and guard logic.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Animals = require(Shared.Config.Animals)
local Zones = require(Shared.Config.Zones)
local Map = require(Shared.Config.Map)
local Formulas = require(Shared.Formulas)
local EggModel = require(Shared.EggModel)

local NestService = {}

local S
local rng = Random.new()
local nests = {} -- list of nest tables
local guards = {} -- list of guard tables
local eggFolder
local guardFolder
local baitCooldown = {}

function NestService.Init(services)
	S = services
	eggFolder = Instance.new("Folder")
	eggFolder.Name = "WildEggs"
	eggFolder.Parent = Workspace
	guardFolder = Instance.new("Folder")
	guardFolder.Name = "Guards"
	guardFolder.Parent = Workspace
end

-- Blocky golem guard.
local function buildGolem(color: Color3, scale: number): Model
	local model = Instance.new("Model")
	model.Name = "Guard"
	local function b(name, size, pos, col, mat)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size * scale
		p.CFrame = CFrame.new(pos * scale)
		p.Color = col
		p.Material = mat or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Parent = model
		return p
	end
	local root = b("Root", Vector3.new(1, 1, 1), Vector3.new(0, 0.5, 0), color)
	root.Transparency = 1
	model.PrimaryPart = root
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.35)
	b("LegL", Vector3.new(1.4, 2.4, 1.4), Vector3.new(-0.9, 1.2, 0), dark)
	b("LegR", Vector3.new(1.4, 2.4, 1.4), Vector3.new(0.9, 1.2, 0), dark)
	b("Body", Vector3.new(3.6, 3.2, 2.4), Vector3.new(0, 4, 0), color)
	b("Belt", Vector3.new(3.7, 0.5, 2.5), Vector3.new(0, 2.7, 0), dark)
	b("ArmL", Vector3.new(1.2, 3.2, 1.2), Vector3.new(-2.5, 3.8, 0), dark)
	b("ArmR", Vector3.new(1.2, 3.2, 1.2), Vector3.new(2.5, 3.8, 0), dark)
	b("Head", Vector3.new(2.2, 1.9, 2.0), Vector3.new(0, 6.5, -0.1), color)
	b("EyeL", Vector3.new(0.5, 0.35, 0.1), Vector3.new(-0.5, 6.7, -1.12), Color3.fromRGB(255, 60, 40), Enum.Material.Neon)
	b("EyeR", Vector3.new(0.5, 0.35, 0.1), Vector3.new(0.5, 6.7, -1.12), Color3.fromRGB(255, 60, 40), Enum.Material.Neon)
	b("Brow", Vector3.new(2.3, 0.35, 0.3), Vector3.new(0, 7.1, -1.05), dark)
	model.WorldPivot = CFrame.new(0, 0, 0)
	return model
end

function NestService.addGuard(model: Model, home: Vector3, speed: number, options)
	options = options or {}
	model:PivotTo(CFrame.new(home))
	model.Parent = guardFolder
	local guard = {
		Model = model,
		Home = home,
		Pos = home,
		Speed = speed,
		AggroRadius = options.AggroRadius or Game.GuardAggroRadius,
		Leash = options.Leash or Game.GuardLeashRadius,
		CatchDistance = options.CatchDistance or Game.GuardCatchDistance,
		State = "Idle",
		Target = nil,
		ChaseStarted = 0,
		BaitUntil = 0,
		BaitPos = nil,
		Nest = options.Nest,
	}
	table.insert(guards, guard)
	return guard
end

function NestService.removeGuard(guard)
	local i = table.find(guards, guard)
	if i then
		table.remove(guards, i)
	end
	if guard.Model then
		guard.Model:Destroy()
	end
end

local function rarityHex(r: number): string
	return S.PlotService.rarityHex(r)
end

-- Creates the egg model on the ground with a grab prompt.
-- egg = { Species, Rarity, Zone, Mutation, Source = "Lane" | "Lair" }
function NestService.placeEgg(egg, cf: CFrame, onGrab)
	local model = EggModel.build({ Species = egg.Species, Rarity = egg.Rarity, Scale = 1.3 })
	model:PivotTo(cf)
	local root = model.PrimaryPart
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GrabPrompt"
	prompt.ActionText = "Steal Egg"
	prompt.ObjectText = EggModel.displayName(egg.Species, egg.Rarity)
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag"
	gui.Size = UDim2.fromOffset(220, 50)
	gui.StudsOffsetWorldSpace = Vector3.new(0, (model:GetAttribute("Height") or 5) + 2, 0)
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	gui.Adornee = root
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.RichText = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = string.format('<font color="%s">%s</font>', rarityHex(egg.Rarity), EggModel.displayName(egg.Species, egg.Rarity))
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = root
	prompt.Triggered:Connect(function(player)
		onGrab(player, model)
	end)
	model.Parent = eggFolder
	return model
end

local function auraFor(seconds: number): number
	local index = 1
	for i, aura in ipairs(Game.Auras) do
		if seconds >= aura.ChaseSeconds then
			index = i
		end
	end
	return index
end

-- Starts carrying an egg. Returns true if the player picked it up.
function NestService.carryEgg(player: Player, egg, onReturn): boolean
	if S.CarryService.isCarrying(player) then
		S.PlayerService.notify(player, "You are already carrying something!", "error")
		return false
	end
	local model = EggModel.build({ Species = egg.Species, Rarity = egg.Rarity, Scale = 0.9 })
	local name = EggModel.displayName(egg.Species, egg.Rarity)
	local item
	item = {
		Kind = "Egg",
		Model = model,
		DisplayName = name,
		Egg = egg,
		ChaseTime = 0,
		Aura = 1,
		GlowColor = egg.Rarity >= Game.EggAuraMinRarity and Game.Rarities[egg.Rarity].Color or nil,
		OnDeliver = function(p)
			if not S.PlotService.freeNest(p) then
				S.CarryService.failNotify(p, item, "All your nests are full! Hatch an egg or buy Incubators.")
				return false
			end
			S.PlotService.addEgg(p, {
				Species = egg.Species,
				Rarity = egg.Rarity,
				Aura = item.Aura,
				Mutation = egg.Mutation,
				Zone = egg.Zone,
			})
			local data = S.DataService.get(p)
			data.Stats.EggsDelivered += 1
			S.RewardService.progress(p, "DeliverEgg", 1)
			if item.Aura > 1 then
				S.RewardService.progress(p, "Aura", 1)
			end
			if egg.Source == "Lane" then
				S.RewardService.expeditionProgress(p, egg.Zone)
			end
			local auraText = item.Aura > 1 and (" with " .. Game.Auras[item.Aura].Name .. " aura") or ""
			S.PlayerService.notify(p, name .. auraText .. " is in your nest!", "success")
			return true
		end,
		OnDrop = function(p, reason)
			if onReturn then
				onReturn(reason)
			end
			if reason == "caught" and p.Parent then
				S.PlayerService.notify(p, "The guard caught you! The egg went back to its nest.", "error")
			end
		end,
	}
	if not S.CarryService.start(player, item) then
		return false
	end
	S.PlayerService.notify(player, "Run home with the " .. name .. "!", "info")
	return true
end

local function respawnNestEgg(nest)
	if nest.EggModel then
		nest.EggModel:Destroy()
		nest.EggModel = nil
	end
	local egg = nest.KeptEgg
	nest.KeptEgg = nil
	if not egg then
		-- roll a new egg with the luck of a random player
		local list = {}
		for _, player in ipairs(Players:GetPlayers()) do
			if S.DataService.isLoaded(player) then
				table.insert(list, player)
			end
		end
		local spawner = #list > 0 and list[rng:NextInteger(1, #list)] or nil
		local luck = 1
		local ctx = spawner and S.PlayerService.ctx(spawner)
		if ctx then
			luck = Formulas.luckMult(ctx)
		end
		local rarity = Animals.rollEggRarity(Animals.EggWeight, luck, rng)
		local def = Animals.pickSpecies(nest.Zone, rarity, rng)
		egg = {
			Species = def.Id,
			Rarity = def.Rarity,
			Zone = nest.Zone,
			Mutation = S.PlayerService.rollMutation(luck),
			Source = "Lane",
		}
		if def.Rarity >= 5 then
			local zone = Zones[nest.Zone]
			S.PlayerService.announce({
				{ { Text = spawner and spawner.DisplayName or "Someone", Color = "#4FB4FF", Verified = true }, { Text = " spawned a " }, { Text = "RARE EGG!", Color = "#FFD84A" } },
				{ { Text = EggModel.displayName(def.Id, def.Rarity), Color = rarityHex(def.Rarity) }, { Text = " spawned in " }, { Text = zone.Name, Color = "#" .. zone.Accent:ToHex() } },
			})
		end
	end
	nest.Egg = egg
	nest.EggModel = NestService.placeEgg(egg, nest.CFrame * CFrame.new(0, 1, 0), function(player, model)
		if nest.EggModel ~= model or nest.Taken then
			return
		end
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp or (hrp.Position - nest.CFrame.Position).Magnitude > 30 then
			return
		end
		local picked = NestService.carryEgg(player, egg, function()
			-- egg goes back into the nest
			nest.Taken = false
			nest.KeptEgg = egg
			respawnNestEgg(nest)
		end)
		if picked then
			nest.Taken = true
			model:Destroy()
			nest.EggModel = nil
			nest.TakenAt = os.clock()
			nest.Carrier = player
			-- the guard notices right away
			local guard = nest.Guard
			if guard and guard.State ~= "Bait" then
				guard.State = "Chase"
				guard.Target = player
				guard.ChaseStarted = os.clock()
			end
		end
	end)
end

-- Spawns a fresh egg into an empty nest (admin / respawn helper).
function NestService.refillNest(nest, egg)
	nest.Taken = false
	nest.KeptEgg = egg
	respawnNestEgg(nest)
end

function NestService.nests()
	return nests
end

local function hrpOf(player: Player): BasePart?
	local character = player and player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if hrp and humanoid and humanoid.Health > 0 then
		return hrp :: BasePart
	end
	return nil
end

local function carriesEgg(player: Player)
	local item = S.CarryService.get(player)
	return item and item.Kind == "Egg" and item or nil
end

local function moveGuard(guard, target: Vector3, dt: number, speedMult: number)
	local flat = Vector3.new(target.X, guard.Home.Y, target.Z)
	local delta = flat - guard.Pos
	local dist = delta.Magnitude
	if dist < 0.5 then
		return dist
	end
	local step = math.min(dist, guard.Speed * speedMult * dt)
	guard.Pos += delta.Unit * step
	guard.Model:PivotTo(CFrame.lookAt(guard.Pos, guard.Pos + delta.Unit))
	return dist - step
end

local function stepGuard(guard, dt: number)
	local now = os.clock()
	if guard.State == "Bait" then
		if now > guard.BaitUntil then
			guard.State = "Return"
		else
			moveGuard(guard, guard.BaitPos, dt, 1.2)
			return
		end
	end
	if guard.State == "Chase" then
		local target = guard.Target
		local hrp = target and target.Parent and hrpOf(target)
		local item = target and carriesEgg(target)
		local tooFar = hrp and (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(guard.Home.X, 0, guard.Home.Z)).Magnitude > guard.Leash
		local escaped = hrp and (S.PlotService.isInside(target, hrp.Position) or (guard.LaneOnly and hrp.Position.Z < Map.Lane.StartZ))
		if not hrp or not item or tooFar or escaped or now - guard.ChaseStarted > Game.GuardMaxChaseSeconds then
			if item and (tooFar or now - guard.ChaseStarted > Game.GuardMaxChaseSeconds) and target.Parent then
				S.PlayerService.notify(target, "You escaped the guard!", "success")
			end
			guard.State = "Return"
			guard.Target = nil
		else
			-- escaping upgrades the aura
			item.ChaseTime += dt
			local aura = auraFor(item.ChaseTime)
			if aura > item.Aura then
				item.Aura = aura
				local auraDef = Game.Auras[aura]
				S.PlayerService.effect(target, "AuraUp", { Aura = aura })
				S.PlayerService.notify(target, "Wild aura: " .. auraDef.Name .. "! (x" .. auraDef.IncomeMult .. " income)", "rare")
				S.PlayerService.markState(target)
				local root = item.Model and item.Model.PrimaryPart
				if root then
					local sparkles = root:FindFirstChild("AuraSparkles") or Instance.new("Sparkles")
					sparkles.Name = "AuraSparkles"
					sparkles.SparkleColor = auraDef.Color
					sparkles.Parent = root
				end
			end
			local remaining = moveGuard(guard, hrp.Position, dt, 1)
			if remaining <= guard.CatchDistance then
				S.CarryService.drop(target, "caught")
				target:SetAttribute("StunnedUntil", os.clock() + Game.GuardStunSeconds)
				S.PlayerService.effect(target, "Caught", {})
				guard.State = "Return"
				guard.Target = nil
			end
			return
		end
	end
	if guard.State == "Return" then
		if moveGuard(guard, guard.Home, dt, 0.8) < 1 then
			guard.State = "Idle"
		end
		return
	end
	-- Idle: chase egg carriers that come close to the nest
	for _, player in ipairs(Players:GetPlayers()) do
		local item = carriesEgg(player)
		local hrp = item and hrpOf(player)
		if hrp and (hrp.Position - guard.Home).Magnitude < guard.AggroRadius then
			guard.State = "Chase"
			guard.Target = player
			guard.ChaseStarted = now
			return
		end
	end
end

function NestService.throwBait(player: Player, target): (boolean, string?)
	local data = S.DataService.get(player)
	if typeof(target) ~= "Vector3" or target.Magnitude ~= target.Magnitude or target.Magnitude == math.huge then
		return false, "Bad target"
	end
	if data.Bait <= 0 then
		return false, "No Glow Bait left! Buy more in the shop."
	end
	local now = os.clock()
	if baitCooldown[player] and now - baitCooldown[player] < Game.BaitCooldownSeconds then
		return false
	end
	local hrp = hrpOf(player)
	if not hrp then
		return false
	end
	local offset = target - hrp.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude > Game.BaitThrowRange then
		flat = flat.Unit * Game.BaitThrowRange
	end
	local pos = Vector3.new(hrp.Position.X + flat.X, 0, hrp.Position.Z + flat.Z)
	baitCooldown[player] = now
	data.Bait -= 1
	S.PlayerService.markState(player)

	local orb = Instance.new("Part")
	orb.Name = "GlowBait"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(2.2, 2.2, 2.2)
	orb.CFrame = CFrame.new(pos + Vector3.new(0, 1.2, 0))
	orb.Color = Color3.fromRGB(120, 255, 200)
	orb.Material = Enum.Material.Neon
	orb.Anchored = true
	orb.CanCollide = false
	orb.CanQuery = false
	orb.CanTouch = false
	local light = Instance.new("PointLight")
	light.Color = orb.Color
	light.Range = 24
	light.Brightness = 4
	light.Parent = orb
	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = orb.Color
	sparkles.Parent = orb
	orb.Parent = Workspace
	Debris:AddItem(orb, Game.BaitDurationSeconds)
	S.PlayerService.effect(nil, "Bait", { Position = pos, Duration = Game.BaitDurationSeconds })

	local lured = 0
	for _, guard in ipairs(guards) do
		if (guard.Pos - pos).Magnitude <= Game.BaitRadius + 30 then
			guard.State = "Bait"
			guard.BaitPos = pos
			guard.BaitUntil = os.clock() + Game.BaitDurationSeconds
			guard.Target = nil
			lured += 1
		end
	end
	if lured > 0 then
		S.RewardService.progress(player, "Bait", 1)
		return true, "Lured " .. lured .. (lured == 1 and " guard!" or " guards!")
	end
	return true, "No guard nearby"
end

function NestService.Start()
	local world = S.WorldBuilder.World
	for zone, list in ipairs(world.Nests) do
		for _, cf in ipairs(list) do
			local nest = { Zone = zone, CFrame = cf, Taken = false }
			table.insert(nests, nest)
			local guardModel = buildGolem(Zones[zone].GuardColor, 1.6 + zone * 0.25)
			local home = (cf * CFrame.new(cf.Position.X < 0 and 12 or -12, 0, 0)).Position
			local guard = NestService.addGuard(guardModel, home, Zones[zone].GuardSpeed, { Nest = nest })
			guard.LaneOnly = true
			nest.Guard = guard
			respawnNestEgg(nest)
		end
	end

	-- a new egg grows back once the taken one has been delivered
	task.spawn(function()
		while true do
			task.wait(2)
			for _, nest in ipairs(nests) do
				if nest.Taken and not nest.EggModel and os.clock() - (nest.TakenAt or 0) > Game.EggRespawnSeconds then
					local carrier = nest.Carrier
					local item = carrier and carrier.Parent and S.CarryService.get(carrier)
					if not (item and item.Egg == nest.Egg) then
						nest.Taken = false
						nest.Carrier = nil
						local ok, err = pcall(respawnNestEgg, nest)
						if not ok then
							warn("[NestService] egg respawn failed", err)
						end
					end
				end
			end
		end
	end)

	S.Router.register("ThrowBait", function(player, target)
		return NestService.throwBait(player, target)
	end)

	RunService.Heartbeat:Connect(function(dt)
		for _, guard in ipairs(guards) do
			local ok, err = pcall(stepGuard, guard, dt)
			if not ok then
				warn("[NestService] guard error", err)
				guard.State = "Return"
				guard.Target = nil
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		baitCooldown[player] = nil
	end)
end

return NestService
