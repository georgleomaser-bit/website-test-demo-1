-- Meteor-Regen im Krater: Einschläge, Kaufen/Schnappen, fallengelassene Gratis-Meteore,
-- Meteoritenschauer-Event und Server-Glück.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))
local MeteorFactory = require(script.Parent:WaitForChild("MeteorFactory"))

local MeteorService = {}
local Services

local rng = Random.new()
local groundMeteors = {} -- Liste von Records
local folder: Folder

local serverLuckMult = 1
local serverLuckUntil = 0
local showerUntil = 0
local nextShowerAt = 0

-- -------------------------------------------------------------------
-- GLÜCK & EVENTS
-- -------------------------------------------------------------------
local function now(): number
	return workspace:GetServerTimeNow()
end

local function publishAttributes()
	ReplicatedStorage:SetAttribute("LuckMult", serverLuckMult)
	ReplicatedStorage:SetAttribute("LuckUntil", serverLuckUntil)
	ReplicatedStorage:SetAttribute("ShowerUntil", showerUntil)
	ReplicatedStorage:SetAttribute("NextShowerAt", nextShowerAt)
end

function MeteorService.IsShowerActive(): boolean
	return showerUntil > now()
end

function MeteorService.GetLuck(): number
	local luck = 1
	if serverLuckUntil > now() then
		luck *= serverLuckMult
	end
	if MeteorService.IsShowerActive() then
		luck *= Config.ShowerLuck
	end
	return luck
end

-- Verlängert laufendes Glück, statt es zu überschreiben
function MeteorService.AddServerLuck(mult: number, seconds: number)
	local t = now()
	if serverLuckUntil > t and mult <= serverLuckMult then
		serverLuckUntil += seconds
	else
		serverLuckMult = mult
		serverLuckUntil = math.max(serverLuckUntil, t) + seconds
	end
	publishAttributes()
end

function MeteorService.SetServerLuck(mult: number, untilTime: number)
	serverLuckMult = mult
	serverLuckUntil = untilTime
	publishAttributes()
end

function MeteorService.StartShower(duration: number?)
	local t = now()
	showerUntil = math.max(showerUntil, t) + (duration or Config.ShowerDuration)
	nextShowerAt = showerUntil + Config.ShowerInterval
	publishAttributes()
	-- Im Schauer gibt es keine Locks!
	for _, plot in ipairs(Services.PlotService.Plots) do
		Services.PlotService.SetLocked(plot, 0)
	end
	Services.EconomyService.NotifyAll(
		"🌠 METEORITENSCHAUER! Keine Locks, " .. Config.ShowerLuck .. "x Glück!",
		"Event"
	)
end

-- -------------------------------------------------------------------
-- ZUFALL
-- -------------------------------------------------------------------
function MeteorService.RollRarity(luck: number)
	return Util.WeightedPick(Config.Rarities, function(rarity)
		local index = Config.RarityIndex[rarity.Name]
		if #Config.MeteorsByRarity[rarity.Name] == 0 then
			return 0
		end
		return index >= 3 and rarity.Weight * luck or rarity.Weight
	end, rng)
end

function MeteorService.RollMutation(luck: number): string
	local mut = Util.WeightedPick(Config.Mutations, function(m)
		return m.Name == "Normal" and m.Weight or m.Weight * luck
	end, rng)
	return mut.Name
end

function MeteorService.RandomOfRarity(rarityName: string)
	local list = Config.MeteorsByRarity[rarityName]
	if not list or #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

function MeteorService.RollEntry(luck: number?)
	luck = luck or MeteorService.GetLuck()
	local rarity = MeteorService.RollRarity(luck :: number)
	local def = MeteorService.RandomOfRarity(rarity.Name) or Config.Meteors[1]
	return { Id = def.Id, Mut = MeteorService.RollMutation(luck :: number), Lv = 1, Xp = 0 }
end

-- -------------------------------------------------------------------
-- METEORE AM BODEN
-- -------------------------------------------------------------------
local function removeRecord(record)
	local index = table.find(groundMeteors, record)
	if index then
		table.remove(groundMeteors, index)
	end
	if record.Part then
		record.Part:Destroy()
		record.Part = nil
	end
end

local function randomLandingSpot(): Vector3
	local center = Services.PlotService.CraterCenter
	local radius = Services.PlotService.CraterRadius - 7
	local best = center
	for _ = 1, 10 do
		local angle = rng:NextNumber() * math.pi * 2
		local dist = math.sqrt(rng:NextNumber()) * radius
		local pos = center + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
		local free = true
		for _, record in ipairs(groundMeteors) do
			if record.Part and (record.Part.Position - pos).Magnitude < 7 then
				free = false
				break
			end
		end
		best = pos
		if free then
			break
		end
	end
	return best
end

local function tryClaim(player: Player, record)
	if record.Claimed or not record.Landed then
		return
	end
	local data = Services.DataService.Get(player)
	if not data then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 or not record.Part then
		return
	end
	if (root.Position - record.Part.Position).Magnitude > record.Part.Size.X / 2 + 14 then
		return -- zu weit weg (Schutz gegen Exploits)
	end
	if not Services.PlotService.GetPlot(player) then
		Services.EconomyService.Notify(player, "Du hast keine Base auf diesem Server.", "Error")
		return
	end
	if Services.CarryService.IsCarrying(player) then
		Services.EconomyService.Notify(player, "Du trägst schon einen Meteor!", "Error")
		return
	end
	if not Services.PlotService.FreeSlot(player) then
		Services.EconomyService.Notify(player, "Deine Base ist voll! Verkaufe einen Meteor (F).", "Error")
		return
	end
	local def = Config.MeteorsById[record.Entry.Id]
	if record.Price > 0 then
		local rarity = Config.RaritiesByName[def.Rarity]
		local required = rarity.RequiredRebirths or 0
		if data.Rebirths < required then
			Services.EconomyService.Notify(
				player,
				def.Rarity .. " braucht " .. required .. " Rebirth(s) zum Kaufen – aber klauen geht! 😈",
				"Error"
			)
			return
		end
		if data.Cash < record.Price then
			Services.EconomyService.Notify(
				player,
				"Nicht genug Cash! Du brauchst " .. Util.FormatCash(record.Price),
				"Error"
			)
			return
		end
		data.Cash -= record.Price
		data.Stats.Bought += 1
	end
	record.Claimed = true
	local entry = record.Entry
	removeRecord(record)
	Services.EconomyService.MarkDirty(player)
	Services.CarryService.StartCarry(player, entry, { Source = "Ground" })
end

local function attachClaimPrompt(record)
	local def = Config.MeteorsById[record.Entry.Id]
	local action = record.Price > 0 and ("Kaufen " .. Util.FormatCash(record.Price)) or "Schnappen (GRATIS)"
	local prompt = MeteorFactory.AddPrompt(record.Part, "BuyPrompt", action, def.Name, Config.GrabHoldDuration)
	prompt.Enabled = record.Landed
	prompt.Triggered:Connect(function(player)
		tryClaim(player, record)
	end)
	return prompt
end

local function impactEffect(position: Vector3, size: number)
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = 0
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Visible = true
	explosion.Parent = workspace
	if size >= 4 then
		for _, player in ipairs(Players:GetPlayers()) do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - position).Magnitude < 80 then
				Services.EconomyService.Effect(player, "Shake", size / 8)
			end
		end
	end
end

-- opts: { Id?, Mut?, Rarity?, Position?, Free?, Instant?, Announce? }
function MeteorService.SpawnMeteor(opts)
	opts = opts or {}
	local entry
	if opts.Id and Config.MeteorsById[opts.Id] then
		entry = { Id = opts.Id, Mut = opts.Mut or MeteorService.RollMutation(MeteorService.GetLuck()), Lv = 1, Xp = 0 }
	elseif opts.Rarity and Config.RaritiesByName[opts.Rarity] then
		local def = MeteorService.RandomOfRarity(opts.Rarity)
		if not def then
			return nil
		end
		entry = { Id = def.Id, Mut = opts.Mut or MeteorService.RollMutation(MeteorService.GetLuck()), Lv = 1, Xp = 0 }
	else
		entry = MeteorService.RollEntry()
	end
	if not Config.MutationsByName[entry.Mut] then
		entry.Mut = "Normal"
	end

	-- Platz schaffen: ältesten entfernen, wenn zu viele daliegen
	while #groundMeteors >= Config.MaxGroundMeteors + 10 do
		removeRecord(groundMeteors[1])
	end

	local price = opts.Free and 0 or math.floor(Config.MeteorValue(entry))
	local part = MeteorFactory.Create(entry, "Ground", price)
	local size = part.Size.Y
	local landing = opts.Position or randomLandingSpot()
	local landCF = CFrame.new(landing.X, 0.4 + size / 2, landing.Z)

	local record = {
		Entry = entry,
		Part = part,
		Price = price,
		Landed = false,
		Claimed = false,
		Expires = os.clock() + (opts.Free and Config.DroppedLifetime or Config.GroundLifetime),
	}
	table.insert(groundMeteors, record)
	attachClaimPrompt(record)

	local def = Config.MeteorsById[entry.Id]
	local rarityIndex = Config.RarityIndex[def.Rarity]
	if opts.Announce ~= false and rarityIndex >= 5 then
		local mut = entry.Mut ~= "Normal" and (entry.Mut .. " ") or ""
		Services.EconomyService.NotifyAll(
			"☄️ Ein " .. def.Rarity .. " " .. mut .. def.Name .. " schlägt ein!",
			"Event"
		)
	end

	if opts.Instant then
		part.CFrame = landCF
		part.Parent = folder
		record.Landed = true
		local prompt = part:FindFirstChild("BuyPrompt") :: ProximityPrompt?
		if prompt then
			prompt.Enabled = true
		end
		return record
	end

	-- Fall-Animation: schräg vom Himmel mit Feuerschweif
	local trail = Instance.new("Fire")
	trail.Name = "FallFire"
	trail.Size = size * 1.5
	trail.Heat = 20
	trail.Color = Color3.fromRGB(255, 140, 40)
	trail.SecondaryColor = Color3.fromRGB(255, 60, 20)
	trail.Parent = part
	part.CFrame = landCF + Vector3.new(rng:NextNumber(-60, 60), 260, rng:NextNumber(-60, 60))
	part.Parent = folder
	local tween = TweenService:Create(
		part,
		TweenInfo.new(1.4 + size * 0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ CFrame = landCF }
	)
	tween:Play()
	tween.Completed:Connect(function()
		if record.Part ~= part then
			return
		end
		trail:Destroy()
		record.Landed = true
		local prompt = part:FindFirstChild("BuyPrompt") :: ProximityPrompt?
		if prompt then
			prompt.Enabled = true
		end
		impactEffect(landCF.Position, size)
	end)
	return record
end

-- Ein Spieler lässt einen gekauften Meteor fallen (gebonkt/gestorben) -> gratis für alle!
function MeteorService.DropMeteor(entry, position: Vector3)
	local map = Services.PlotService
	local pos = Vector3.new(position.X, 0, position.Z)
	if pos.Magnitude > 200 then
		pos = map.CraterCenter
	end
	-- Nicht in einer fremden Base ablegen
	for _, plot in ipairs(map.Plots) do
		if map.IsInside(plot, pos) then
			pos = plot.EntranceCFrame.Position * Vector3.new(1, 0, 1)
			break
		end
	end
	return MeteorService.SpawnMeteor({
		Id = entry.Id,
		Mut = entry.Mut,
		Position = pos,
		Free = true,
		Instant = true,
		Announce = false,
	})
end

function MeteorService.ClearGround()
	for i = #groundMeteors, 1, -1 do
		removeRecord(groundMeteors[i])
	end
end

function MeteorService.Init(services)
	Services = services
	folder = Instance.new("Folder")
	folder.Name = "GroundMeteors"
	folder.Parent = Services.PlotService.MapFolder
end

function MeteorService.Start()
	nextShowerAt = now() + Config.ShowerInterval
	publishAttributes()

	-- Spawn-Schleife
	task.spawn(function()
		while true do
			local interval = MeteorService.IsShowerActive() and Config.ShowerSpawnInterval or Config.SpawnInterval
			task.wait(interval)
			local landedCount = 0
			for _, record in ipairs(groundMeteors) do
				if record.Price > 0 then
					landedCount += 1
				end
			end
			local limit = MeteorService.IsShowerActive() and Config.MaxGroundMeteors * 2 or Config.MaxGroundMeteors
			if #Players:GetPlayers() > 0 and landedCount < limit then
				local ok, err = pcall(MeteorService.SpawnMeteor, {})
				if not ok then
					warn("[MeteorService] Spawn-Fehler: " .. tostring(err))
				end
			end
		end
	end)

	-- Zerbröseln + Event-Timer
	task.spawn(function()
		local wasShower = false
		while true do
			task.wait(1)
			local clock = os.clock()
			for i = #groundMeteors, 1, -1 do
				local record = groundMeteors[i]
				if not record.Claimed and clock > record.Expires then
					removeRecord(record)
				end
			end
			local t = now()
			if not MeteorService.IsShowerActive() and t >= nextShowerAt then
				MeteorService.StartShower()
			end
			local active = MeteorService.IsShowerActive()
			if wasShower and not active then
				Services.EconomyService.NotifyAll("Der Meteoritenschauer ist vorbei. Locks gehen wieder!", "Info")
			end
			wasShower = active
		end
	end)
end

return MeteorService
