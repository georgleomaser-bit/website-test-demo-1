-- Bases: assigns a plot to each player, shows their pen animals, treadmills, nests with
-- incubating eggs and the base lock. Also hatches eggs.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Animals = require(Shared.Config.Animals)
local Treadmills = require(Shared.Config.Treadmills)
local Zones = require(Shared.Config.Zones)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)
local AnimalModel = require(Shared.AnimalModel)
local EggModel = require(Shared.EggModel)
local Remotes = require(Shared.Remotes)

local PlotService = {}

local S
local World
local owners = {} -- [plotIndex] = player
local plotOf = {} -- [player] = plotIndex
local penModels = {} -- [player] = { [uid] = model }
local eggModels = {} -- [player] = { [nestIndex] = model }
local rng = Random.new()

local function rarityHex(rarity: number): string
	local c = Game.Rarities[rarity].Color
	if rarity == 7 then
		c = Color3.fromRGB(255, 255, 255)
	end
	return string.format("#%02X%02X%02X", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end
PlotService.rarityHex = rarityHex

function PlotService.Init(services)
	S = services
	World = services.WorldBuilder.World
end

function PlotService.plotIndex(player: Player): number?
	return plotOf[player]
end

function PlotService.plot(player: Player)
	local index = plotOf[player]
	return index and World.Plots[index] or nil
end

function PlotService.ownerOf(index: number): Player?
	return owners[index]
end

-- Is a world position inside this player's base?
function PlotService.isInside(player: Player, position: Vector3): boolean
	local plot = PlotService.plot(player)
	if not plot then
		return false
	end
	local localPos = plot.Region.CFrame:PointToObjectSpace(position)
	local half = plot.Region.Size / 2
	return math.abs(localPos.X) <= half.X and math.abs(localPos.Z) <= half.Z and localPos.Y <= half.Y + 20
end

function PlotService.isLocked(player: Player): boolean
	local rt = S.PlayerService.get(player)
	return rt ~= nil and rt.LockedUntil > os.time()
end

local function animalLabel(model: Model, record, ownerName: string?)
	local def = Animals.ById[record.Species]
	local root = model.PrimaryPart
	local height = model:GetAttribute("Height") or 6
	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag"
	gui.Size = UDim2.fromOffset(220, 86)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height + 2.5, 0)
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	gui.Adornee = root
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.RichText = true
	label.TextColor3 = Color3.new(1, 1, 1)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(20, 20, 30)
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = root
	local mutation = Game.Mutations[record.Mutation or 1]
	local aura = Game.Auras[record.Aura or 1]
	local prefix = ""
	if (record.Mutation or 1) > 1 then
		prefix = mutation.Name .. " "
	end
	local auraText = (record.Aura or 1) > 1 and (" <font color=\"#" .. aura.Color:ToHex() .. "\">[" .. aura.Name .. "]</font>") or ""
	label:SetAttribute("Head", string.format('<font color="%s">%s%s</font>%s', rarityHex(def.Rarity), prefix, def.Id, auraText))
	label:SetAttribute("Weight", Format.number(record.Weight) .. "kg")
	label:SetAttribute("Owner", ownerName or "")
	return label
end

local function setLabelIncome(label: TextLabel, income: number)
	label.Text = string.format('%s\n<font color="#7CFF6B">$%s/s</font>\n<font size="14">%s</font>',
		label:GetAttribute("Head"), Format.number(income), label:GetAttribute("Weight"))
end

local function penSlotsInUse(player: Player)
	local data = S.DataService.get(player)
	local list = {}
	for _, animal in ipairs(data.Animals) do
		if animal.InPen then
			table.insert(list, animal)
		end
	end
	return list
end

-- Rebuilds pen models so they match the save data (only changed animals are rebuilt).
function PlotService.refresh(player: Player)
	local plot = PlotService.plot(player)
	local data = S.DataService.get(player)
	local rt = S.PlayerService.get(player)
	if not plot or not data or not rt then
		return
	end
	local models = penModels[player]
	if not models then
		models = {}
		penModels[player] = models
	end
	local wanted = {}
	local slot = 0
	local ctx = S.PlayerService.ctx(player)
	for _, animal in ipairs(penSlotsInUse(player)) do
		slot += 1
		if slot > #plot.PenSlots then
			break
		end
		local shown = not rt.InTransit[animal.Uid] and data.Mount ~= animal.Uid
		if shown then
			wanted[animal.Uid] = true
			local model = models[animal.Uid]
			if model and model:GetAttribute("Slot") ~= slot then
				model:PivotTo(plot.PenSlots[slot] * CFrame.Angles(0, math.rad(rng:NextNumber(-15, 15)), 0))
				model:SetAttribute("Slot", slot)
			end
			if not model then
				model = AnimalModel.build(animal.Species, { Mutation = animal.Mutation, Aura = animal.Aura })
				model.Name = animal.Uid
				model:SetAttribute("Slot", slot)
				model:SetAttribute("OwnerUserId", player.UserId)
				model:SetAttribute("Uid", animal.Uid)
				model:PivotTo(plot.PenSlots[slot] * CFrame.Angles(0, math.rad(rng:NextNumber(-15, 15)), 0))
				local label = animalLabel(model, animal)
				setLabelIncome(label, Formulas.animalIncome(ctx, animal))
				model:SetAttribute("Income", Formulas.animalIncome(ctx, animal))

				local def = Animals.ById[animal.Species]
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "StealPrompt"
				prompt.ActionText = "Steal"
				prompt.ObjectText = def.Id
				prompt.HoldDuration = Game.StealHoldSeconds
				prompt.MaxActivationDistance = 10 + def.Scale * 3
				prompt.RequiresLineOfSight = false
				prompt.KeyboardKeyCode = Enum.KeyCode.E
				prompt.Style = Enum.ProximityPromptStyle.Default
				prompt.Parent = model.PrimaryPart
				local owner = player
				local uid = animal.Uid
				prompt.Triggered:Connect(function(thief)
					S.StealService.tryStart(thief, owner, uid)
				end)

				local penFolder = plot.Model:FindFirstChild("PenAnimals")
				if not penFolder then
					penFolder = Instance.new("Folder")
					penFolder.Name = "PenAnimals"
					penFolder.Parent = plot.Model
				end
				model.Parent = penFolder
				models[animal.Uid] = model
			end
		end
	end
	for uid, model in pairs(models) do
		if not wanted[uid] then
			model:Destroy()
			models[uid] = nil
		end
	end
end

-- Updates the "$X/s" tags after multipliers change.
function PlotService.refreshIncome(player: Player)
	local models = penModels[player]
	local ctx = S.PlayerService.ctx(player)
	if not models or not ctx then
		return
	end
	for uid, model in pairs(models) do
		local record = S.PlayerService.findAnimal(player, uid)
		if record then
			local income = Formulas.animalIncome(ctx, record)
			if model:GetAttribute("Income") ~= income then
				model:SetAttribute("Income", income)
				local tag = model.PrimaryPart and model.PrimaryPart:FindFirstChild("Tag")
				local label = tag and tag:FindFirstChild("Label")
				if label then
					setLabelIncome(label, income)
				end
			end
		end
	end
end

function PlotService.refreshTreadmills(player: Player?)
	for index, plot in ipairs(World.Plots) do
		local owner = owners[index]
		if player == nil or owner == player then
			local data = owner and S.DataService.get(owner)
			local ctx = owner and S.PlayerService.ctx(owner)
			for tier, tm in pairs(plot.Treadmills) do
				local prompt = tm.Console:FindFirstChild("BuyPrompt")
				if not data or not ctx then
					tm.Label.Text = tm.Name
					if prompt then
						prompt.Enabled = false
					end
				elseif tier == 0 then
					if ctx.Passes.VIP then
						tm.Label.Text = string.format('<font color="#FFD84A">VIP Treadmill</font>\n+%s Speed/s', Format.number(Formulas.treadmillGain(ctx, 0)))
					else
						tm.Label.Text = '<font color="#FFD84A">VIP Treadmill</font>\nVIP Pass only'
					end
					if prompt then
						prompt.Enabled = not ctx.Passes.VIP
						prompt.ActionText = "Get VIP"
					end
				elseif tier <= data.Treadmill then
					tm.Label.Text = string.format("%s\n<font color=\"#7CFF6B\">+%s Speed/s</font>", tm.Name, Format.number(Formulas.treadmillGain(ctx, tier)))
					if prompt then
						prompt.Enabled = false
					end
				else
					local cost = Treadmills[tier].Cost
					local color = tier == data.Treadmill + 1 and "#FFE45C" or "#AAAAAA"
					tm.Label.Text = string.format("%s\n<font color=\"%s\">LOCKED $%s</font>", tm.Name, color, Format.number(cost))
					if prompt then
						prompt.Enabled = tier == data.Treadmill + 1
						prompt.ActionText = "Buy $" .. Format.number(cost)
					end
				end
			end
		end
	end
end

local function nestLabel(model: Model): TextLabel
	local tag = model.PrimaryPart:FindFirstChild("Tag")
	return tag and tag:FindFirstChild("Label")
end

function PlotService.refreshEggs(player: Player)
	local plot = PlotService.plot(player)
	local data = S.DataService.get(player)
	local ctx = S.PlayerService.ctx(player)
	if not plot or not data or not ctx then
		return
	end
	local models = eggModels[player]
	if not models then
		models = {}
		eggModels[player] = models
	end
	local slots = Formulas.incubators(ctx)
	for i, inc in ipairs(plot.Incubators) do
		inc.Model:SetAttribute("Unlocked", i <= slots)
		for _, p in ipairs(inc.Model:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Transparency = i <= slots and 0 or 0.7
			end
		end
		local egg = data.Eggs[i]
		local model = models[i]
		if model and (not egg or model:GetAttribute("Key") ~= egg.Key) then
			model:Destroy()
			models[i] = nil
			model = nil
		end
		if egg and not model then
			model = EggModel.build({ Species = egg.Species, Rarity = egg.Rarity, Aura = egg.Aura, Scale = 1.4 })
			model:SetAttribute("Key", egg.Key)
			model:PivotTo(inc.CFrame * CFrame.new(0, 0.9, 0))
			local gui = Instance.new("BillboardGui")
			gui.Name = "Tag"
			gui.Size = UDim2.fromOffset(220, 70)
			gui.StudsOffsetWorldSpace = Vector3.new(0, (model:GetAttribute("Height") or 5) + 2, 0)
			gui.MaxDistance = 90
			gui.LightInfluence = 0
			gui.Adornee = model.PrimaryPart
			local label = Instance.new("TextLabel")
			label.Name = "Label"
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.FredokaOne
			label.TextScaled = true
			label.RichText = true
			label.TextColor3 = Color3.new(1, 1, 1)
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 2.5
			stroke.Parent = label
			label.Parent = gui
			gui.Parent = model.PrimaryPart
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "HatchPrompt"
			prompt.ActionText = "Hatch"
			prompt.ObjectText = EggModel.displayName(egg.Species, egg.Rarity)
			prompt.HoldDuration = 0.3
			prompt.RequiresLineOfSight = false
			prompt.MaxActivationDistance = 12
			prompt.Enabled = false
			prompt.Parent = model.PrimaryPart
			local slotIndex = i
			local owner = player
			prompt.Triggered:Connect(function(who)
				if who == owner then
					PlotService.hatch(owner, slotIndex)
				end
			end)
			model:SetAttribute("OwnerUserId", player.UserId)
			model.Parent = inc.Model
			models[i] = model
		end
	end
	PlotService.tickEggLabels(player)
end

function PlotService.tickEggLabels(player: Player)
	local data = S.DataService.get(player)
	local models = eggModels[player]
	if not data or not models then
		return
	end
	local now = os.time()
	for i, model in pairs(models) do
		local egg = data.Eggs[i]
		local label = nestLabel(model)
		if egg and label then
			local left = egg.ReadyAt - now
			local name = string.format('<font color="%s">%s</font>', rarityHex(egg.Rarity), EggModel.displayName(egg.Species, egg.Rarity))
			if left > 0 then
				label.Text = name .. "\n" .. Format.time(left)
			else
				label.Text = name .. '\n<font color="#7CFF6B">READY! Hatch</font>'
			end
			local prompt = model.PrimaryPart:FindFirstChild("HatchPrompt")
			if prompt then
				prompt.Enabled = left <= 0
			end
		end
	end
end

-- Puts a delivered egg in the first free unlocked nest. egg = { Species, Rarity, Aura, Mutation, Zone }
function PlotService.addEgg(player: Player, egg): boolean
	local data = S.DataService.get(player)
	local ctx = S.PlayerService.ctx(player)
	if not data or not ctx then
		return false
	end
	local slots = Formulas.incubators(ctx)
	for i = 1, slots do
		if data.Eggs[i] == nil or data.Eggs[i] == false then
			local zone = Zones[egg.Zone] or Zones[1]
			local seconds = zone.EggHatchSeconds * (1 + (egg.Rarity - 1) * 0.25) / Formulas.hatchMult(ctx)
			data.Eggs[i] = {
				Key = tostring(data.NextUid) .. "_" .. tostring(os.time()),
				Species = egg.Species,
				Rarity = egg.Rarity,
				Aura = egg.Aura or 1,
				Mutation = egg.Mutation or 1,
				Zone = egg.Zone,
				ReadyAt = os.time() + math.max(1, math.floor(seconds)),
			}
			data.NextUid += 1
			PlotService.refreshEggs(player)
			S.PlayerService.markState(player)
			return true
		end
	end
	return false
end

function PlotService.freeNest(player: Player): boolean
	local data = S.DataService.get(player)
	local ctx = S.PlayerService.ctx(player)
	if not data or not ctx then
		return false
	end
	for i = 1, Formulas.incubators(ctx) do
		if data.Eggs[i] == nil or data.Eggs[i] == false then
			return true
		end
	end
	return false
end

function PlotService.hatch(player: Player, slot: number): (boolean, string?)
	local data = S.DataService.get(player)
	if not data then
		return false, "Not loaded"
	end
	local egg = data.Eggs[slot]
	if type(egg) ~= "table" then
		return false, "No egg here"
	end
	if egg.ReadyAt > os.time() then
		return false, "Not ready yet"
	end
	if not S.PlayerService.canReceiveAnimal(player) then
		return false, "Storage full"
	end
	data.Eggs[slot] = false
	local record = S.PlayerService.giveAnimal(player, {
		Species = egg.Species,
		Mutation = egg.Mutation,
		Aura = egg.Aura,
	})
	if not record then
		data.Eggs[slot] = egg
		return false, "Could not hatch"
	end
	data.Stats.Hatched += 1
	S.RewardService.progress(player, "Hatch", 1)
	Remotes.Hatched:FireClient(player, record)
	local def = Animals.ById[record.Species]
	if def.Rarity >= 6 or (record.Mutation or 1) >= 3 then
		S.PlayerService.announce({
			{ { Text = player.DisplayName, Color = "#4FB4FF" }, { Text = " hatched a " }, { Text = Game.Rarities[def.Rarity].Name:upper() .. " " .. def.Id .. "!", Color = rarityHex(def.Rarity) } },
		})
	end
	PlotService.refreshEggs(player)
	S.PlayerService.markState(player)
	return true
end

function PlotService.hatchAllNow(player: Player): number
	local data = S.DataService.get(player)
	local count = 0
	for _, egg in pairs(data.Eggs) do
		if type(egg) == "table" then
			egg.ReadyAt = os.time()
			count += 1
		end
	end
	PlotService.refreshEggs(player)
	return count
end

local function setOwnerSign(index: number, player: Player?)
	local plot = World.Plots[index]
	plot.OwnerLabel.Text = player and (player.DisplayName .. "'s Base") or "Empty Base"
end

local function setBarrier(plot, visible: boolean)
	for _, p in ipairs(plot.Barrier:GetChildren()) do
		if p:IsA("BasePart") then
			p.Transparency = visible and 0.45 or 1
		end
	end
end

function PlotService.toggleLock(player: Player): (boolean, string?)
	local rt = S.PlayerService.get(player)
	local plot = PlotService.plot(player)
	if not rt or not plot then
		return false, "No base"
	end
	local now = os.time()
	if rt.LockedUntil > now then
		return false, "Base is already locked"
	end
	if rt.LockCooldownUntil > now then
		return false, "Lock ready in " .. Format.time(rt.LockCooldownUntil - now)
	end
	local duration = rt.Passes.VIP and Game.BaseLockSecondsVIP or Game.BaseLockSeconds
	rt.LockedUntil = now + duration
	rt.LockCooldownUntil = rt.LockedUntil + Game.BaseLockCooldownSeconds
	setBarrier(plot, true)
	S.PlayerService.markState(player)
	S.PlayerService.notify(player, "Base locked for " .. duration .. "s!", "success")
	return true
end

local function placeCharacter(player: Player, character: Model)
	local plot = PlotService.plot(player)
	if not plot then
		return
	end
	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if hrp then
		task.wait()
		character:PivotTo(plot.Spawn)
	end
end

function PlotService.assign(player: Player)
	if plotOf[player] then
		return
	end
	for index = 1, #World.Plots do
		if not owners[index] then
			owners[index] = player
			plotOf[player] = index
			setOwnerSign(index, player)
			local rt = S.PlayerService.get(player)
			if rt then
				rt.Plot = index
			end
			player:SetAttribute("Plot", index)
			PlotService.refresh(player)
			PlotService.refreshTreadmills(player)
			PlotService.refreshEggs(player)
			if player.Character then
				task.spawn(placeCharacter, player, player.Character)
			end
			player.CharacterAdded:Connect(function(character)
				placeCharacter(player, character)
			end)
			return
		end
	end
	warn("[PlotService] no free plot for", player.Name, "- set Max Players to", #World.Plots)
end

function PlotService.release(player: Player)
	local index = plotOf[player]
	if not index then
		return
	end
	if penModels[player] then
		for _, model in pairs(penModels[player]) do
			model:Destroy()
		end
	end
	if eggModels[player] then
		for _, model in pairs(eggModels[player]) do
			model:Destroy()
		end
	end
	penModels[player] = nil
	eggModels[player] = nil
	owners[index] = nil
	plotOf[player] = nil
	setOwnerSign(index, nil)
	setBarrier(World.Plots[index], false)
	PlotService.refreshTreadmills()
end

function PlotService.Start()
	-- treadmill buy prompts
	for index, plot in ipairs(World.Plots) do
		for tier, tm in pairs(plot.Treadmills) do
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "BuyPrompt"
			prompt.ActionText = "Buy"
			prompt.ObjectText = tm.Name
			prompt.HoldDuration = 0.2
			prompt.RequiresLineOfSight = false
			prompt.MaxActivationDistance = 12
			prompt.Enabled = false
			prompt.Parent = tm.Console
			prompt.Triggered:Connect(function(player)
				if owners[index] ~= player then
					return
				end
				if tier == 0 then
					S.MonetizationService.promptPass(player, "VIP")
				else
					local ok, msg = S.ShopService.buyTreadmill(player, tier)
					if not ok and msg then
						S.PlayerService.notify(player, msg, "error")
					end
				end
			end)
		end
		local lockPrompt = Instance.new("ProximityPrompt")
		lockPrompt.Name = "LockPrompt"
		lockPrompt.ActionText = "Lock Base"
		lockPrompt.HoldDuration = 0.3
		lockPrompt.RequiresLineOfSight = false
		lockPrompt.MaxActivationDistance = 10
		lockPrompt.Parent = plot.LockButton
		lockPrompt.Triggered:Connect(function(player)
			if owners[index] ~= player then
				return
			end
			local ok, msg = PlotService.toggleLock(player)
			if not ok and msg then
				S.PlayerService.notify(player, msg, "error")
			end
		end)
	end

	S.DataService.onReleasing(function(player)
		PlotService.release(player)
	end)

	S.Router.register("Hatch", function(player, slot)
		if type(slot) ~= "number" then
			return false, "Bad slot"
		end
		return PlotService.hatch(player, math.floor(slot))
	end)
	S.Router.register("LockBase", function(player)
		return PlotService.toggleLock(player)
	end)

	-- labels: egg countdowns and base lock state
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.time()
			for player, index in pairs(plotOf) do
				PlotService.tickEggLabels(player)
				local rt = S.PlayerService.get(player)
				local plot = World.Plots[index]
				if rt then
					if rt.LockedUntil > now then
						plot.LockLabel.Text = '<font color="#FF6B6B">LOCKED ' .. (rt.LockedUntil - now) .. "s</font>"
					elseif rt.LockCooldownUntil > now then
						setBarrier(plot, false)
						plot.LockLabel.Text = "LOCK READY IN " .. (rt.LockCooldownUntil - now) .. "s"
					else
						setBarrier(plot, false)
						plot.LockLabel.Text = "LOCK BASE"
					end
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		-- safety net if data never loaded
		if plotOf[player] then
			PlotService.release(player)
		end
	end)
end

return PlotService
