-- Baut die komplette Map per Code (Krater, 8 Basen, Lobby) und verwaltet die Basen:
-- Zuweisung, Meteore anzeigen, Collect-Pad, Lock-Pad, Schutz gegen Eindringlinge.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))
local MeteorFactory = require(script.Parent:WaitForChild("MeteorFactory"))

local PlotService = {}
PlotService.Plots = {} -- Liste aller Basen
PlotService.ByPlayer = {} :: { [Player]: any }
PlotService.MapFolder = nil :: Folder?
PlotService.CraterCenter = Vector3.new(0, 0, 0)
PlotService.CraterRadius = 45
PlotService.LobbySpawn = CFrame.new(0, 4, -150)

local Services
local PLOT_SIZE = 56
local HALF = PLOT_SIZE / 2
local PLOT_X = 90
local PLOT_Z = { -96, -32, 32, 96 }
local PLOT_COLORS = {
	Color3.fromRGB(255, 99, 99),
	Color3.fromRGB(255, 170, 60),
	Color3.fromRGB(255, 230, 80),
	Color3.fromRGB(110, 220, 110),
	Color3.fromRGB(80, 200, 255),
	Color3.fromRGB(110, 120, 255),
	Color3.fromRGB(200, 110, 255),
	Color3.fromRGB(255, 120, 200),
}
local SLOT_COLS = { -20, -10, 0, 10, 20 }
local SLOT_ROWS = { -4, 8, 20 }

local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		if k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end

local function billboard(parent: Instance, size: UDim2, offset: Vector3, maxDistance: number): (BillboardGui, TextLabel)
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.StudsOffset = offset
	gui.MaxDistance = maxDistance
	gui.LightInfluence = 0
	gui.Parent = parent
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = label
	label.Parent = gui
	return gui, label
end

-- -------------------------------------------------------------------
-- MAP BAUEN
-- -------------------------------------------------------------------
local function buildMap()
	-- Alte Standard-Objekte aus dem Baseplate-Template entfernen
	for _, child in ipairs(workspace:GetChildren()) do
		if child.Name == "Baseplate" or child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end
	local old = workspace:FindFirstChild("MeteorHeistMap")
	if old then
		old:Destroy()
	end

	local map = Instance.new("Folder")
	map.Name = "MeteorHeistMap"
	map.Parent = workspace
	PlotService.MapFolder = map

	-- Licht: Abendhimmel mit Sternen, aber hell genug zum Spielen
	Lighting.ClockTime = 18.6
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(110, 100, 130)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 140, 170)
	Lighting.GlobalShadows = true

	part({
		Name = "Ground",
		Size = Vector3.new(440, 1, 440),
		Position = Vector3.new(0, -0.5, 0),
		Material = Enum.Material.Ground,
		Color = Color3.fromRGB(70, 62, 85),
		Parent = map,
	})

	-- Krater in der Mitte
	part({
		Name = "CraterRim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, PlotService.CraterRadius * 2 + 10, PlotService.CraterRadius * 2 + 10),
		CFrame = CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Rock,
		Color = Color3.fromRGB(95, 75, 65),
		CanCollide = false,
		Parent = map,
	})
	part({
		Name = "Crater",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, PlotService.CraterRadius * 2, PlotService.CraterRadius * 2),
		CFrame = CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.CrackedLava,
		Color = Color3.fromRGB(45, 35, 40),
		CanCollide = false,
		Parent = map,
	})
	local craterSign = part({
		Name = "CraterSign",
		Size = Vector3.new(1, 1, 1),
		Position = Vector3.new(0, 30, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = map,
	})
	local _, craterLabel = billboard(craterSign, UDim2.new(0, 400, 0, 60), Vector3.zero, 400)
	craterLabel.Text = "☄️ METEOR-KRATER ☄️"
	craterLabel.TextColor3 = Color3.fromRGB(255, 170, 60)
	PlotService.CraterLabel = craterLabel

	-- Unsichtbare Wände am Map-Rand
	local edge = 215
	for _, data in ipairs({
		{ Vector3.new(edge, 40, 0), Vector3.new(2, 80, edge * 2) },
		{ Vector3.new(-edge, 40, 0), Vector3.new(2, 80, edge * 2) },
		{ Vector3.new(0, 40, edge), Vector3.new(edge * 2, 80, 2) },
		{ Vector3.new(0, 40, -edge), Vector3.new(edge * 2, 80, 2) },
	}) do
		part({ Name = "Boundary", Position = data[1], Size = data[2], Transparency = 1, Parent = map })
	end

	-- Lobby-Spawn (für Spieler ohne Base, z.B. wenn der Server voll ist)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = Vector3.new(0, 0.5, -150)
	spawn.Material = Enum.Material.Neon
	spawn.Color = Color3.fromRGB(255, 170, 60)
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = map

	-- Basen
	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = map

	local index = 0
	for _, side in ipairs({ -1, 1 }) do
		for _, z in ipairs(PLOT_Z) do
			index += 1
			if index > Config.MaxPlots then
				break
			end
			local center = Vector3.new(side * PLOT_X, 0, z)
			-- Eingang zeigt zur Map-Mitte (lokales -Z = vorne)
			local cf = CFrame.lookAt(center, center + Vector3.new(-side, 0, 0))
			local color = PLOT_COLORS[index]

			local model = Instance.new("Model")
			model.Name = "Plot" .. index
			model:SetAttribute("PlotIndex", index)
			model:SetAttribute("OwnerUserId", 0)
			model:SetAttribute("LockedUntil", 0)
			model.Parent = plotsFolder

			part({
				Name = "Floor",
				Size = Vector3.new(PLOT_SIZE, 1, PLOT_SIZE),
				CFrame = cf * CFrame.new(0, 0.5, 0),
				Material = Enum.Material.Concrete,
				Color = color:Lerp(Color3.fromRGB(40, 40, 50), 0.7),
				Parent = model,
			})
			part({
				Name = "BackWall",
				Size = Vector3.new(PLOT_SIZE, 8, 1),
				CFrame = cf * CFrame.new(0, 5, HALF - 0.5),
				Material = Enum.Material.SmoothPlastic,
				Color = color,
				Parent = model,
			})
			for _, sx in ipairs({ -1, 1 }) do
				part({
					Name = "SideWall",
					Size = Vector3.new(1, 8, PLOT_SIZE),
					CFrame = cf * CFrame.new(sx * (HALF - 0.5), 5, 0),
					Material = Enum.Material.SmoothPlastic,
					Color = color,
					Parent = model,
				})
				part({
					Name = "Post",
					Size = Vector3.new(2, 10, 2),
					CFrame = cf * CFrame.new(sx * (HALF - 1), 5, -HALF + 1),
					Material = Enum.Material.Metal,
					Color = Color3.fromRGB(60, 60, 70),
					Parent = model,
				})
			end
			local barrier = part({
				Name = "Barrier",
				Size = Vector3.new(PLOT_SIZE - 4, 8, 0.4),
				CFrame = cf * CFrame.new(0, 5, -HALF + 1),
				Material = Enum.Material.ForceField,
				Color = Color3.fromRGB(255, 40, 40),
				Transparency = 1,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				Parent = model,
			})

			local slots = {}
			local slotNumber = 0
			for _, row in ipairs(SLOT_ROWS) do
				for _, col in ipairs(SLOT_COLS) do
					slotNumber += 1
					local slotPart = part({
						Name = "Slot" .. slotNumber,
						Size = Vector3.new(7, 0.3, 7),
						CFrame = cf * CFrame.new(col, 1.15, row),
						Material = Enum.Material.SmoothPlastic,
						Color = Color3.fromRGB(35, 35, 45),
						CanCollide = false,
						Parent = model,
					})
					slots[slotNumber] = slotPart
				end
			end

			local collectPad = part({
				Name = "CollectPad",
				Size = Vector3.new(10, 0.3, 6),
				CFrame = cf * CFrame.new(-16, 1.15, -18),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(60, 220, 90),
				CanCollide = false,
				Parent = model,
			})
			local _, collectLabel = billboard(collectPad, UDim2.new(0, 200, 0, 50), Vector3.new(0, 4, 0), 80)
			collectLabel.Text = "💰 $0"

			local lockPad = part({
				Name = "LockPad",
				Size = Vector3.new(8, 0.3, 6),
				CFrame = cf * CFrame.new(16, 1.15, -18),
				Material = Enum.Material.Neon,
				Color = Color3.fromRGB(230, 60, 60),
				CanCollide = false,
				Parent = model,
			})
			local _, lockLabel = billboard(lockPad, UDim2.new(0, 200, 0, 50), Vector3.new(0, 4, 0), 80)
			lockLabel.Text = "🔒 LOCK"

			local signPart = part({
				Name = "Sign",
				Size = Vector3.new(1, 1, 1),
				CFrame = cf * CFrame.new(0, 14, HALF - 0.5),
				Transparency = 1,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				Parent = model,
			})
			local _, signLabel = billboard(signPart, UDim2.new(0, 320, 0, 60), Vector3.zero, 300)
			signLabel.Text = "Freie Base"
			signLabel.TextColor3 = color

			local meteorFolder = Instance.new("Folder")
			meteorFolder.Name = "Meteors"
			meteorFolder.Parent = model

			table.insert(PlotService.Plots, {
				Index = index,
				Model = model,
				CFrame = cf,
				Color = color,
				Owner = nil :: Player?,
				Slots = slots,
				MeteorParts = {} :: { [number]: BasePart },
				MeteorFolder = meteorFolder,
				CollectPad = collectPad,
				CollectLabel = collectLabel,
				LockPad = lockPad,
				LockLabel = lockLabel,
				Barrier = barrier,
				SignLabel = signLabel,
				LockedUntil = 0,
				SpawnCFrame = cf * CFrame.new(0, 4, -10),
				EntranceCFrame = cf * CFrame.new(0, 4, -HALF - 8),
			})
		end
	end
end

-- -------------------------------------------------------------------
-- ABFRAGEN
-- -------------------------------------------------------------------
function PlotService.GetPlot(player: Player)
	return PlotService.ByPlayer[player]
end

function PlotService.IsInside(plot, position: Vector3): boolean
	local localPos = plot.CFrame:PointToObjectSpace(position)
	return math.abs(localPos.X) <= HALF and math.abs(localPos.Z) <= HALF and localPos.Y > -6 and localPos.Y < 40
end

function PlotService.IsLocked(plot): boolean
	return plot.LockedUntil > workspace:GetServerTimeNow()
end

function PlotService.SlotCount(player: Player): number
	local extra = Services.MonetizationService.HasPass(player, "ExtraSlots") and Config.ExtraSlotsAmount or 0
	return math.min(Config.BaseSlots + extra, #SLOT_COLS * #SLOT_ROWS)
end

function PlotService.FreeSlot(player: Player): number?
	local data = Services.DataService.Get(player)
	if not data then
		return nil
	end
	for slot = 1, PlotService.SlotCount(player) do
		if data.Meteors[tostring(slot)] == nil then
			return slot
		end
	end
	return nil
end

function PlotService.UsedSlots(player: Player): number
	local data = Services.DataService.Get(player)
	local count = 0
	if data then
		for _ in pairs(data.Meteors) do
			count += 1
		end
	end
	return count
end

-- -------------------------------------------------------------------
-- METEORE IN DER BASE ANZEIGEN
-- -------------------------------------------------------------------
-- Foto-Deko (Admin-Panel → 📸 Foto-Modus): Ordner im Plot-Model, Teile heißen "Slot<n>"
local PHOTO_FOLDER = "PhotoShowcase"

-- Stellt einen Meteor mittig auf das Slot-Pad
local function placeOnSlot(plot, slot: number, meteor: BasePart)
	local slotPart = plot.Slots[slot]
	meteor.CFrame = slotPart.CFrame * CFrame.new(0, slotPart.Size.Y / 2 + meteor.Size.Y / 2, 0)
end

local function removePhotoDeco(plot, slot: number)
	local folder = plot.Model:FindFirstChild(PHOTO_FOLDER)
	local deco = folder and folder:FindFirstChild("Slot" .. slot)
	if deco then
		deco:Destroy()
	end
end

function PlotService.RenderSlot(plot, slot: number)
	local existing = plot.MeteorParts[slot]
	if existing then
		existing:Destroy()
		plot.MeteorParts[slot] = nil
	end
	if not plot.Owner then
		return
	end
	local data = Services.DataService.Get(plot.Owner)
	local entry = data and data.Meteors[tostring(slot)]
	if not entry or not Config.MeteorsById[entry.Id] then
		return
	end
	if Services.CarryService.IsSlotBeingStolen(plot, slot) then
		return -- wird gerade geklaut -> unsichtbar in der Base
	end
	removePhotoDeco(plot, slot) -- echter Meteor ersetzt die Foto-Deko
	local meteor = MeteorFactory.Create(entry, "Base")
	placeOnSlot(plot, slot, meteor)
	meteor:SetAttribute("PlotIndex", plot.Index)
	meteor:SetAttribute("Slot", slot)
	local def = Config.MeteorsById[entry.Id]
	local stealPrompt =
		MeteorFactory.AddPrompt(meteor, "StealPrompt", "Klauen", def.Name, Config.StealHoldDuration, Enum.KeyCode.E)
	local sellPrompt = MeteorFactory.AddPrompt(
		meteor,
		"SellPrompt",
		"Verkaufen " .. Util.FormatCash(Config.MeteorValue(entry) * Config.SellRatio),
		def.Name,
		1,
		Enum.KeyCode.F
	)
	stealPrompt.Triggered:Connect(function(player)
		Services.CarryService.TrySteal(player, plot, slot)
	end)
	sellPrompt.Triggered:Connect(function(player)
		Services.EconomyService.Sell(player, plot, slot)
	end)
	meteor.Parent = plot.MeteorFolder
	plot.MeteorParts[slot] = meteor
end

-- Nach Level-Up nur Größe/Schild anpassen statt neu bauen
function PlotService.RefreshSlot(plot, slot: number)
	local meteor = plot.MeteorParts[slot]
	local data = plot.Owner and Services.DataService.Get(plot.Owner)
	local entry = data and data.Meteors[tostring(slot)]
	if not meteor or not entry then
		return
	end
	MeteorFactory.Refresh(meteor, entry, "Base")
	local sellPrompt = meteor:FindFirstChild("SellPrompt")
	if sellPrompt then
		(sellPrompt :: ProximityPrompt).ActionText = "Verkaufen "
			.. Util.FormatCash(Config.MeteorValue(entry) * Config.SellRatio)
	end
end

function PlotService.RenderAll(plot)
	for slot = 1, #plot.Slots do
		PlotService.RenderSlot(plot, slot)
	end
	PlotService.UpdateSlotColors(plot)
end

function PlotService.UpdateSlotColors(plot)
	local count = plot.Owner and PlotService.SlotCount(plot.Owner) or 0
	-- Foto-Deko aktiv -> alle Pads in der Plot-Farbe (volle Base sieht auf dem Foto besser aus)
	local photo = plot.Model:FindFirstChild(PHOTO_FOLDER) ~= nil
	for slot, slotPart in ipairs(plot.Slots) do
		if slot <= count or photo then
			slotPart.Color = plot.Color:Lerp(Color3.new(1, 1, 1), 0.3)
			slotPart.Transparency = 0
		else
			slotPart.Color = Color3.fromRGB(35, 35, 45)
			slotPart.Transparency = 0.5
		end
	end
end

-- -------------------------------------------------------------------
-- FOTO-DEKO (nur Optik für Thumbnails: keine Spieldaten, keine Prompts)
-- -------------------------------------------------------------------
-- Füllt ALLE Slots ohne echten Meteor (auch die gesperrten 11-15) mit Deko-Meteoren.
-- makeEntry() liefert { Id, Mut, Lv }. Gibt die Anzahl der Deko-Meteore zurück.
function PlotService.FillPhotoShowcase(plot, makeEntry: () -> any): number
	local folder = plot.Model:FindFirstChild(PHOTO_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = PHOTO_FOLDER
		folder.Parent = plot.Model
	end
	local count = 0
	for slot = 1, #plot.Slots do
		removePhotoDeco(plot, slot) -- nochmal drücken = neu würfeln
		local entry = plot.MeteorParts[slot] == nil and makeEntry() or nil
		if entry and Config.MeteorsById[entry.Id] then
			local meteor = MeteorFactory.Create(entry, "Base")
			meteor.Name = "Slot" .. slot
			placeOnSlot(plot, slot, meteor)
			meteor.Parent = folder
			count += 1
		end
	end
	PlotService.UpdateSlotColors(plot)
	return count
end

-- Entfernt nur die Deko (Slot-Farben danach mit UpdateSlotColors zurücksetzen)
function PlotService.ClearPhotoShowcase(plot)
	local folder = plot.Model:FindFirstChild(PHOTO_FOLDER)
	if folder then
		folder:Destroy()
	end
end

-- -------------------------------------------------------------------
-- LOCK
-- -------------------------------------------------------------------
function PlotService.UpdateLockVisual(plot)
	local now = workspace:GetServerTimeNow()
	local showerActive = Services.MeteorService and Services.MeteorService.IsShowerActive()
	if plot.LockedUntil > now then
		plot.Barrier.Transparency = 0.35
		plot.LockLabel.Text = "🔒 " .. math.ceil(plot.LockedUntil - now) .. "s"
		plot.LockPad.Color = Color3.fromRGB(90, 90, 90)
	else
		plot.Barrier.Transparency = 1
		plot.LockLabel.Text = showerActive and "🌠 KEIN LOCK IM SCHAUER" or "🔒 LOCK"
		plot.LockPad.Color = Color3.fromRGB(230, 60, 60)
	end
end

function PlotService.SetLocked(plot, untilTime: number)
	plot.LockedUntil = untilTime
	plot.Model:SetAttribute("LockedUntil", untilTime)
	PlotService.UpdateLockVisual(plot)
end

local function tryLock(player: Player, plot)
	if plot.Owner ~= player or PlotService.IsLocked(plot) then
		return
	end
	if Services.MeteorService.IsShowerActive() then
		Services.EconomyService.Notify(player, "🌠 Während des Meteoritenschauers gibt es keine Locks!", "Error")
		return
	end
	local duration = Services.MonetizationService.HasPass(player, "VIP") and Config.LockDurationVIP
		or Config.LockDuration
	PlotService.SetLocked(plot, workspace:GetServerTimeNow() + duration)
	Services.EconomyService.Notify(player, "🔒 Base für " .. duration .. " Sekunden gesperrt!", "Success")
end

-- -------------------------------------------------------------------
-- ZUWEISUNG
-- -------------------------------------------------------------------
local function teleportToPlot(player: Player)
	local character = player.Character
	local plot = PlotService.ByPlayer[player]
	if not character then
		return
	end
	local target = plot and plot.SpawnCFrame or PlotService.LobbySpawn
	character:PivotTo(target)
end

function PlotService.AssignPlot(player: Player)
	if PlotService.ByPlayer[player] then
		return PlotService.ByPlayer[player]
	end
	for _, plot in ipairs(PlotService.Plots) do
		if plot.Owner == nil then
			plot.Owner = player
			plot.Model:SetAttribute("OwnerUserId", player.UserId)
			plot.SignLabel.Text = player.DisplayName .. "s Base"
			PlotService.ByPlayer[player] = plot
			PlotService.SetLocked(plot, 0)
			PlotService.UpdateSlotColors(plot)
			return plot
		end
	end
	return nil
end

function PlotService.ReleasePlot(player: Player)
	local plot = PlotService.ByPlayer[player]
	if not plot then
		return
	end
	PlotService.ByPlayer[player] = nil
	plot.Owner = nil
	plot.Model:SetAttribute("OwnerUserId", 0)
	plot.SignLabel.Text = "Freie Base"
	plot.CollectLabel.Text = "💰 $0"
	PlotService.SetLocked(plot, 0)
	for slot, meteor in pairs(plot.MeteorParts) do
		meteor:Destroy()
		plot.MeteorParts[slot] = nil
	end
	PlotService.ClearPhotoShowcase(plot)
	PlotService.UpdateSlotColors(plot)
end

function PlotService.TeleportHome(player: Player)
	teleportToPlot(player)
end

function PlotService.Init(services)
	Services = services
	buildMap()
end

function PlotService.Start()
	local function onCharacter(player: Player, character: Model)
		character:WaitForChild("HumanoidRootPart", 10)
		task.wait(0.1)
		if character.Parent and player.Character == character then
			teleportToPlot(player)
		end
	end

	local function onPlayer(player: Player)
		local plot = PlotService.AssignPlot(player)
		if not plot then
			task.delay(3, function()
				if player.Parent then
					Services.EconomyService.Notify(
						player,
						"Server voll – keine Base frei. Wechsle den Server!",
						"Error"
					)
				end
			end)
		end
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayer, player)
	end

	-- Pads: Collect + Lock (Touched mit Entprellung)
	local debounce: { [Player]: number } = {}
	for _, plot in ipairs(PlotService.Plots) do
		plot.CollectPad.CanTouch = true
		plot.LockPad.CanTouch = true
		plot.CollectPad.Touched:Connect(function(hit)
			local player = Players:GetPlayerFromCharacter(hit.Parent)
			if player and player == plot.Owner and os.clock() - (debounce[player] or 0) > 0.5 then
				debounce[player] = os.clock()
				Services.EconomyService.Collect(player)
			end
		end)
		plot.LockPad.Touched:Connect(function(hit)
			local player = Players:GetPlayerFromCharacter(hit.Parent)
			if player and player == plot.Owner then
				tryLock(player, plot)
			end
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		debounce[player] = nil
		local plot = PlotService.ByPlayer[player]
		if plot then
			-- laufende Diebstähle aus dieser Base abbrechen, dann Base freigeben
			Services.CarryService.CancelStealsFromPlot(plot, "victimLeft")
		end
		PlotService.ReleasePlot(player)
	end)

	-- Eindringlinge aus gesperrten Basen werfen + Lock-Anzeige aktualisieren
	task.spawn(function()
		local tick = 0
		while true do
			task.wait(0.25)
			tick += 1
			for _, plot in ipairs(PlotService.Plots) do
				if plot.Owner and PlotService.IsLocked(plot) then
					for _, other in ipairs(Players:GetPlayers()) do
						local character = other.Character
						local root = character and character:FindFirstChild("HumanoidRootPart")
						if other ~= plot.Owner and root and PlotService.IsInside(plot, root.Position) then
							character:PivotTo(plot.EntranceCFrame)
							Services.EconomyService.Notify(other, "🔒 Diese Base ist gesperrt!", "Error")
						end
					end
				end
				if tick % 4 == 0 then
					PlotService.UpdateLockVisual(plot)
				end
			end
		end
	end)
end

return PlotService
