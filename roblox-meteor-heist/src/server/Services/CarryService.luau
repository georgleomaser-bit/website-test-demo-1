-- Tragen & Klauen:
--  * Gekaufte Meteore muss man in die eigene Base tragen.
--  * Fremde Meteore kann man klauen (wenn die Base nicht gesperrt ist).
--  * Wer gebonkt wird oder stirbt, verliert den Meteor:
--      geklaut   -> fliegt zurück zum Besitzer
--      gekauft   -> fällt auf den Boden und ist GRATIS für alle
--  * Bonk-Schläger zum Verteidigen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MeteorFactory = require(script.Parent:WaitForChild("MeteorFactory"))

local CarryService = {}
local Services

local carrying: { [Player]: any } = {}
local stealing: { [any]: { [number]: Player } } = {} -- [plot][slot] = Dieb
local lastBonk: { [Player]: number } = {}

function CarryService.IsCarrying(player: Player): boolean
	return carrying[player] ~= nil
end

function CarryService.IsSlotBeingStolen(plot, slot: number): boolean
	local map = stealing[plot]
	return map ~= nil and map[slot] ~= nil
end

local function clearStealMark(info)
	if info.Source == "Plot" and stealing[info.VictimPlot] then
		stealing[info.VictimPlot][info.Slot] = nil
	end
end

local function cleanup(player: Player, info)
	carrying[player] = nil
	if info.Visual then
		info.Visual:Destroy()
		info.Visual = nil
	end
	Services.EconomyService.ApplySpeed(player)
	Services.EconomyService.MarkDirty(player)
end

local function createVisual(player: Player, entry): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not root then
		return nil
	end
	local visual = MeteorFactory.Create(entry, "Base")
	visual.Name = "CarriedMeteor"
	visual.Anchored = false
	visual.Massless = true
	visual.CanCollide = false
	visual.CanQuery = false
	visual.CFrame = root.CFrame * CFrame.new(0, 2.5 + visual.Size.Y / 2, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = visual
	weld.Parent = visual
	visual.Parent = character
	return visual
end

-- info: { Source = "Ground" } oder { Source = "Plot", VictimPlot, VictimPlayer, Slot, EntryRef }
function CarryService.StartCarry(player: Player, entry, info)
	info.Entry = entry
	info.Started = os.clock()
	info.Visual = createVisual(player, entry)
	carrying[player] = info
	Services.EconomyService.ApplySpeed(player)
	Services.EconomyService.MarkDirty(player)
	Services.EconomyService.Notify(player, "🏃 Bring den Meteor in deine Base!", "Info")
end

local function succeed(player: Player)
	local info = carrying[player]
	if not info then
		return
	end
	local data = Services.DataService.Get(player)
	local plot = Services.PlotService.GetPlot(player)
	local slot = Services.PlotService.FreeSlot(player)
	local def = Config.MeteorsById[info.Entry.Id]

	if info.Source == "Plot" then
		local victim = info.VictimPlayer
		local victimData = victim and victim.Parent and Services.DataService.Get(victim)
		local key = tostring(info.Slot)
		if not data or not plot or not slot or not victimData or victimData.Meteors[key] ~= info.EntryRef then
			CarryService.Fail(player, "invalid")
			return
		end
		victimData.Meteors[key] = nil
		data.Meteors[tostring(slot)] = info.EntryRef
		data.Stats.Stolen += 1
		victimData.Stats.Robbed += 1
		clearStealMark(info)
		cleanup(player, info)
		Services.EconomyService.Discover(player, info.Entry.Id)
		Services.PlotService.RenderSlot(plot, slot)
		Services.PlotService.RenderSlot(info.VictimPlot, info.Slot)
		Services.EconomyService.MarkDirty(victim)
		Services.EconomyService.Notify(player, "😈 Geklaut: " .. def.Name .. "!", "Success")
		Services.EconomyService.Notify(
			victim,
			"💔 " .. player.DisplayName .. " hat deinen " .. def.Name .. " geklaut!",
			"Error"
		)
		Services.EconomyService.Effect(player, "Confetti", 1)
		return
	end

	-- Gekaufter / geschnappter Meteor
	if not data or not plot or not slot then
		CarryService.Fail(player, "full")
		return
	end
	data.Meteors[tostring(slot)] = info.Entry
	cleanup(player, info)
	Services.EconomyService.Discover(player, info.Entry.Id)
	Services.PlotService.RenderSlot(plot, slot)
	Services.EconomyService.Notify(player, "✅ " .. def.Name .. " ist in deiner Base!", "Success")
	Services.EconomyService.Effect(player, "Confetti", 0.5)
end

function CarryService.Fail(player: Player, reason: string)
	local info = carrying[player]
	if not info then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local position = (info.Visual and info.Visual.Position) or (root and root.Position) or Vector3.zero
	clearStealMark(info)
	cleanup(player, info)
	local def = Config.MeteorsById[info.Entry.Id]

	if info.Source == "Plot" then
		-- zurück zum Besitzer
		if info.VictimPlot.Owner == info.VictimPlayer then
			Services.PlotService.RenderSlot(info.VictimPlot, info.Slot)
			if reason ~= "victimLeft" then
				Services.EconomyService.Notify(
					info.VictimPlayer,
					"🛡️ Dein " .. def.Name .. " ist zurück!",
					"Success"
				)
			end
		end
		if reason == "bonked" then
			Services.EconomyService.Notify(player, "💥 Gebonkt! Der Meteor fliegt zurück.", "Error")
		elseif reason == "timeout" then
			Services.EconomyService.Notify(player, "⏰ Zu langsam! Der Meteor fliegt zurück.", "Error")
		end
	else
		-- gekaufter Meteor fällt auf den Boden -> gratis für alle
		Services.MeteorService.DropMeteor(info.Entry, position)
		if reason == "bonked" then
			Services.EconomyService.Notify(player, "💥 Gebonkt! Du hast den Meteor fallen lassen!", "Error")
		elseif reason == "timeout" then
			Services.EconomyService.Notify(player, "⏰ Zu langsam! Der Meteor ist runtergefallen.", "Error")
		elseif reason == "full" then
			Services.EconomyService.Notify(player, "Deine Base ist voll – Meteor fallen gelassen!", "Error")
		end
	end
end

function CarryService.TrySteal(thief: Player, plot, slot: number)
	local owner = plot.Owner
	if not owner or owner == thief then
		return
	end
	local thiefData = Services.DataService.Get(thief)
	local ownerData = Services.DataService.Get(owner)
	if not thiefData or not ownerData then
		return
	end
	if Services.PlotService.IsLocked(plot) then
		Services.EconomyService.Notify(thief, "🔒 Diese Base ist gesperrt!", "Error")
		return
	end
	if CarryService.IsSlotBeingStolen(plot, slot) or carrying[thief] then
		return
	end
	local entry = ownerData.Meteors[tostring(slot)]
	if not entry then
		return
	end
	if not Services.PlotService.GetPlot(thief) then
		Services.EconomyService.Notify(thief, "Du hast keine Base auf diesem Server.", "Error")
		return
	end
	if not Services.PlotService.FreeSlot(thief) then
		Services.EconomyService.Notify(thief, "Deine Base ist voll! Verkaufe erst einen Meteor.", "Error")
		return
	end
	local character = thief.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local meteor = plot.MeteorParts[slot]
	if not root or not humanoid or humanoid.Health <= 0 or not meteor then
		return
	end
	if (root.Position - meteor.Position).Magnitude > meteor.Size.X / 2 + 14 then
		return -- zu weit weg
	end

	stealing[plot] = stealing[plot] or {}
	stealing[plot][slot] = thief
	Services.PlotService.RenderSlot(plot, slot) -- macht den Meteor in der Base unsichtbar
	CarryService.StartCarry(thief, entry, {
		Source = "Plot",
		VictimPlot = plot,
		VictimPlayer = owner,
		Slot = slot,
		EntryRef = entry,
	})
	local def = Config.MeteorsById[entry.Id]
	Services.EconomyService.Notify(
		owner,
		"🚨 " .. thief.DisplayName .. " klaut deinen " .. def.Name .. "! BONK IHN!",
		"Alarm"
	)
	Services.EconomyService.Effect(owner, "Alarm", 1)
end

-- Alle laufenden Diebstähle aus einer Base abbrechen (Rebirth, Reset, Verlassen)
function CarryService.CancelStealsFromPlot(plot, reason: string?)
	for thief, info in pairs(carrying) do
		if info.Source == "Plot" and info.VictimPlot == plot then
			CarryService.Fail(thief, reason or "cancelled")
		end
	end
end

-- -------------------------------------------------------------------
-- BONK-SCHLÄGER
-- -------------------------------------------------------------------
local function bonk(player: Player, tool: Tool)
	local t = os.clock()
	if t - (lastBonk[player] or 0) < Config.BonkCooldown then
		return
	end
	lastBonk[player] = t

	-- Schlag-Animation über das Standard-Animate-Skript
	local anim = Instance.new("StringValue")
	anim.Name = "toolanim"
	anim.Value = "Slash"
	anim.Parent = tool
	Debris:AddItem(anim, 1)

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local best, bestDist = nil, Config.BonkRange
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local otherHum = other.Character and other.Character:FindFirstChildOfClass("Humanoid")
			if otherRoot and otherHum and otherHum.Health > 0 then
				local offset = otherRoot.Position - root.Position
				local dist = offset.Magnitude
				local facing = dist < 3 or root.CFrame.LookVector:Dot(offset.Unit) > 0.1
				if dist <= bestDist and facing then
					best, bestDist = other, dist
				end
			end
		end
	end
	if not best then
		return
	end
	local targetRoot = best.Character and best.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not targetRoot then
		return
	end
	local direction = targetRoot.Position - root.Position
	direction = Vector3.new(direction.X, 0, direction.Z)
	direction = direction.Magnitude > 0.01 and direction.Unit or root.CFrame.LookVector

	-- Rückstoß (läuft beim getroffenen Spieler, weil der seine Physik besitzt)
	local attachment = Instance.new("Attachment")
	attachment.Parent = targetRoot
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.MaxForce = 1e6
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VectorVelocity = direction * Config.BonkForce + Vector3.new(0, 30, 0)
	velocity.Parent = targetRoot
	Debris:AddItem(velocity, 0.18)
	Debris:AddItem(attachment, 0.18)

	Services.EconomyService.Effect(best, "Shake", 0.6)
	if carrying[best] then
		CarryService.Fail(best, "bonked")
		Services.EconomyService.Notify(
			player,
			"💥 Treffer! " .. best.DisplayName .. " hat den Meteor verloren!",
			"Success"
		)
	end
end

local function createBonkTool(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Bonk"
	tool.ToolTip = "Klick = Bonk! Diebe verlieren ihren Meteor."
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.Grip = CFrame.new(0, 0, -1.6) * CFrame.Angles(math.rad(-90), 0, 0)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.6, 0.6, 4.2)
	handle.Color = Color3.fromRGB(255, 170, 60)
	handle.Material = Enum.Material.SmoothPlastic
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.6, 1.6, 1.6)
	head.Color = Color3.fromRGB(255, 90, 60)
	head.Material = Enum.Material.SmoothPlastic
	head.CanCollide = false
	head.Massless = true
	head.CFrame = handle.CFrame * CFrame.new(0, 0, -2.2)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = head
	weld.Parent = head
	head.Parent = tool
	return tool
end

local bonkTemplate: Tool

local function giveTool(player: Player)
	local backpack = player:WaitForChild("Backpack", 10)
	if not backpack or backpack:FindFirstChild("Bonk") then
		return
	end
	local tool = bonkTemplate:Clone()
	tool.Activated:Connect(function()
		bonk(player, tool)
	end)
	tool.Parent = backpack
end

function CarryService.Init(services)
	Services = services
	bonkTemplate = createBonkTool()
end

function CarryService.Start()
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			-- neuer Charakter -> alter Meteor ist weg
			if carrying[player] then
				CarryService.Fail(player, "died")
			end
			local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
			if humanoid then
				humanoid.Died:Connect(function()
					CarryService.Fail(player, "died")
				end)
			end
			giveTool(player)
			Services.EconomyService.ApplySpeed(player)
		end)
		if player.Character then
			task.spawn(giveTool, player)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayer, player)
	end

	-- Beim Verlassen (vor dem Speichern): Diebstähle sauber beenden.
	-- Kann zweimal aufgerufen werden (PlayerRemoving + Speichern) – ist harmlos.
	local function onLeaving(player: Player)
		lastBonk[player] = nil
		local info = carrying[player]
		local data = Services.DataService.Get(player)
		if info and info.Source == "Ground" and data then
			-- gekaufter Meteor geht beim Verlassen nicht verloren
			local slot = Services.PlotService.FreeSlot(player)
			if slot then
				data.Meteors[tostring(slot)] = info.Entry
				cleanup(player, info)
			end
		end
		if carrying[player] then
			CarryService.Fail(player, "left")
		end
	end
	Services.DataService.OnProfileReleasing(onLeaving)
	Players.PlayerRemoving:Connect(onLeaving)

	-- Prüfen: angekommen? gestorben? zu langsam?
	task.spawn(function()
		while true do
			task.wait(0.15)
			for player, info in pairs(carrying) do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local plot = Services.PlotService.GetPlot(player)
				local teleported = false
				if root then
					-- Anti-Teleport: wer mit Beute unmöglich schnell vorankommt, verliert sie
					local now = os.clock()
					if info.LastPos then
						local dist = (root.Position - info.LastPos).Magnitude
						local dt = math.max(now - info.LastTime, 0.05)
						local limit = math.max(humanoid and humanoid.WalkSpeed * 2.5 or 0, 70)
						teleported = dist > 25 and dist / dt > limit
					end
					info.LastPos = root.Position
					info.LastTime = now
				end
				if not root or not humanoid or humanoid.Health <= 0 or not info.Visual or not info.Visual.Parent then
					CarryService.Fail(player, "died")
				elseif teleported then
					CarryService.Fail(player, "teleport")
				elseif os.clock() - info.Started > Config.CarryTimeout then
					CarryService.Fail(player, "timeout")
				elseif plot and Services.PlotService.IsInside(plot, root.Position) then
					succeed(player)
				end
			end
		end
	end)
end

return CarryService
