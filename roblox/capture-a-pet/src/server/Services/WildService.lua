-- Wild animals roaming the four zones of the lane. Hold E to capture one, then bring it
-- home: it walks behind you and joins your pen when you enter your base.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Animals = require(Shared.Config.Animals)
local Zones = require(Shared.Config.Zones)
local Map = require(Shared.Config.Map)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)
local AnimalModel = require(Shared.AnimalModel)

local WildService = {}

local S
local rng = Random.new()
local wild = {} -- [zone] = { [model] = info }
local wildFolder

function WildService.Init(services)
	S = services
	wildFolder = Instance.new("Folder")
	wildFolder.Name = "WildAnimals"
	wildFolder.Parent = Workspace
	for zone = 1, #Zones do
		wild[zone] = {}
	end
end

local function countZone(zone: number): number
	local n = 0
	for _ in pairs(wild[zone]) do
		n += 1
	end
	return n
end

local function randomPoint(zone: number): Vector3
	local z0 = Map.zoneStartZ(zone)
	local len = Map.Lane.ZoneLength
	local half = Map.Lane.Width / 2 - 14
	for _ = 1, 20 do
		local p = Vector3.new(rng:NextNumber(-half, half), 0, rng:NextNumber(z0 + 40, z0 + len - 30))
		local ok = true
		for _, nest in ipairs(S.WorldBuilder.World.Nests[zone]) do
			if (nest.Position - p).Magnitude < 30 then
				ok = false
				break
			end
		end
		if ok then
			return p
		end
	end
	return Vector3.new(0, 0, z0 + len / 2)
end

-- Someone in the server "spawns" each animal; their luck is used for the roll.
local function pickSpawner(): Player?
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if S.DataService.isLoaded(player) then
			table.insert(list, player)
		end
	end
	if #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

local function zoneHex(zone: number): string
	return "#" .. Zones[zone].Accent:ToHex()
end
WildService.zoneHex = zoneHex

local function tagText(def, record): string
	local mutation = Game.Mutations[record.Mutation]
	local prefix = record.Mutation > 1 and (mutation.Name .. " ") or ""
	return string.format('<font color="%s">%s%s</font>\n<font color="#7CFF6B">$%s/s</font>\n<font size="14">%skg · %s</font>',
		S.PlotService.rarityHex(def.Rarity), prefix, def.Id,
		Format.number(Formulas.animalBaseIncome(record)), Format.number(record.Weight), Game.Rarities[def.Rarity].Name)
end

function WildService.spawn(zone: number, forcedSpecies: string?, spawner: Player?)
	spawner = spawner or pickSpawner()
	local luck = 1
	if spawner then
		local ctx = S.PlayerService.ctx(spawner)
		if ctx then
			luck = Formulas.luckMult(ctx)
		end
	elseif S.PlayerService.ServerLuckUntil > os.time() then
		luck = 2
	end
	local def = forcedSpecies and Animals.ById[forcedSpecies] or Animals.rollWild(zone, luck, rng)
	local record = {
		Species = def.Id,
		Weight = S.PlayerService.rollWeight(def),
		Mutation = S.PlayerService.rollMutation(luck),
		Aura = 1,
	}
	local model = AnimalModel.build(def.Id, { Mutation = record.Mutation })
	local pos = randomPoint(zone)
	model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	CollectionService:AddTag(model, "WildAnimal")

	local root = model.PrimaryPart
	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag"
	gui.Size = UDim2.fromOffset(220, 80)
	gui.StudsOffsetWorldSpace = Vector3.new(0, (model:GetAttribute("Height") or 6) + 2.5, 0)
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	gui.Adornee = root
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.RichText = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = tagText(def, record)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = root

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CapturePrompt"
	prompt.ActionText = "Capture"
	prompt.ObjectText = def.Id
	prompt.HoldDuration = Game.TameHoldSeconds[def.Rarity]
	prompt.MaxActivationDistance = 10 + def.Scale * 3
	prompt.RequiresLineOfSight = false
	prompt.Parent = root

	local info = { Model = model, Record = record, Def = def, Zone = zone, SpawnedAt = os.clock() }
	wild[zone][model] = info
	prompt.Triggered:Connect(function(player)
		WildService.capture(player, info)
	end)
	model.Parent = wildFolder

	if def.Rarity >= 5 or record.Mutation >= 3 then
		local who = spawner and spawner.DisplayName or "Someone"
		local mutation = record.Mutation > 1 and (Game.Mutations[record.Mutation].Name .. " ") or ""
		S.PlayerService.announce({
			{ { Text = who, Color = "#4FB4FF", Verified = true }, { Text = " spawned a " }, { Text = Game.Rarities[def.Rarity].Name:upper() .. "!", Color = "#FFD84A" } },
			{ { Text = mutation .. def.Id, Color = S.PlotService.rarityHex(def.Rarity) }, { Text = " spawned in " }, { Text = Zones[zone].Name, Color = zoneHex(zone) } },
		})
	end
	return info
end

function WildService.capture(player: Player, info)
	local zoneList = wild[info.Zone]
	if not zoneList[info.Model] then
		return
	end
	if S.CarryService.isCarrying(player) then
		S.PlayerService.notify(player, "You are already carrying something!", "error")
		return
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp or (hrp.Position - info.Model:GetPivot().Position).Magnitude > 30 + info.Def.Scale * 4 then
		return
	end
	if not S.PlayerService.canReceiveAnimal(player) then
		S.PlayerService.notify(player, "Your storage is full! Sell some animals first.", "error")
		return
	end
	zoneList[info.Model] = nil
	local model = info.Model
	CollectionService:RemoveTag(model, "WildAnimal")
	local prompt = model.PrimaryPart:FindFirstChild("CapturePrompt")
	if prompt then
		prompt:Destroy()
	end
	local def = info.Def
	local record = info.Record
	local started = S.CarryService.start(player, {
		Kind = "Animal",
		Model = model,
		DisplayName = def.Id,
		OnDeliver = function(p)
			local given = S.PlayerService.giveAnimal(p, record)
			if not given then
				return true -- storage full message was shown; let it go
			end
			local data = S.DataService.get(p)
			data.Stats.Tamed += 1
			S.RewardService.progress(p, "Tame", 1)
			if def.Rarity >= 3 then
				S.RewardService.progress(p, "TameRare", 1)
			end
			S.PlayerService.notify(p, "Captured " .. def.Id .. "!", "success")
			S.PlayerService.effect(p, "Captured", { Species = def.Id })
			return true
		end,
		OnDrop = function(p, reason)
			if reason ~= "left" and p.Parent then
				S.PlayerService.notify(p, "The " .. def.Id .. " ran away!", "error")
			end
		end,
	})
	if started then
		S.PlayerService.notify(player, "Bring the " .. def.Id .. " back to your base!", "info")
	end
end

function WildService.Start()
	-- keep every zone populated, despawn old animals
	task.spawn(function()
		while true do
			task.wait(Game.WildRespawnSeconds)
			if #Players:GetPlayers() > 0 then
				local now = os.clock()
				for zone = 1, #Zones do
					for model, info in pairs(wild[zone]) do
						if now - info.SpawnedAt > Game.WildLifetimeSeconds then
							wild[zone][model] = nil
							model:Destroy()
						end
					end
					local missing = Game.WildAnimalsPerZone - countZone(zone)
					for _ = 1, math.min(missing, 2) do
						WildService.spawn(zone)
					end
				end
			end
		end
	end)
	-- slowly turn the animals so they look alive
	task.spawn(function()
		while true do
			task.wait(2.5)
			for zone = 1, #Zones do
				for model in pairs(wild[zone]) do
					if rng:NextNumber() < 0.35 and model.Parent then
						model:PivotTo(model:GetPivot() * CFrame.Angles(0, rng:NextNumber(-0.9, 0.9), 0))
					end
				end
			end
		end
	end)
end

return WildService
