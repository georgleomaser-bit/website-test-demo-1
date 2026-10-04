-- Lässt die Map bauen (MapBuilder) und verwaltet die Basen:
-- Zuweisung, Meteore/Aliens anzeigen, Collect-Pad + Slot-Anker, Lock-Pad, Schutz gegen Eindringlinge.
-- Basen sind OFFEN (niedriger Rand): Slots sind unsichtbare Anker-Teile (plot.Slots, 18 Stück in
-- Slot-Reihenfolge), Basen können rechteckig sein (plot.HalfSizeX = halbe Breite, plot.HalfSizeZ =
-- halbe Tiefe, lokal; Eingang = lokales -Z).
-- BASE-SCHILD (Produkt): plot.ShieldUntil (Serverzeit) sperrt die Base zusätzlich zum Lock –
-- auch während des Meteoritenschauers. Setzen über PlotService.AddShield/SetShield
-- (wer plot.ShieldUntil direkt ändert: wird innerhalb von 0,25 s übernommen).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))
local MeteorFactory = require(script.Parent:WaitForChild("MeteorFactory"))
local AlienFactory = require(script.Parent:WaitForChild("AlienFactory"))
local MapBuilder = require(script.Parent:WaitForChild("MapBuilder"))

local PlotService = {}
PlotService.Plots = {} :: { any } -- Liste aller Basen (Felder siehe MapBuilder)
PlotService.ByPlayer = {} :: { [Player]: any }
PlotService.MapFolder = nil :: Folder?
-- Alien-Parade: { Folder, Path, RoadWidth, Start } (siehe MapBuilder.ParadeInfo)
PlotService.Parade = nil :: any
PlotService.FreeZone = { Center = Vector3.new(0, 0.2, -264), Radius = 20 }
PlotService.LobbySpawn = CFrame.new(0, 4, -300)
PlotService.LeaderboardCFrame = CFrame.new(0, 13, -190)
PlotService.TreadmillsFolder = nil :: Folder?
PlotService.TreadmillSpawn = CFrame.new(0, 4, -330)
PlotService.MaxSlots = Config.BaseSlots + Config.ExtraSlotsAmount

local Services

local LOCK_NOTIFY_COOLDOWN = 2 -- Lock-Pad im Schauer: Hinweis höchstens alle 2 s (Touched feuert sehr oft)

local lockNotifyAt: { [Player]: number } = {}

-- -------------------------------------------------------------------
-- ABFRAGEN
-- -------------------------------------------------------------------
function PlotService.GetPlot(player: Player)
	return PlotService.ByPlayer[player]
end

-- Halbe Breite (lokales X) und halbe Tiefe (lokales Z) einer Base
function PlotService.HalfExtents(plot): (number, number)
	local half = tonumber(plot.HalfSize) or 36
	return tonumber(plot.HalfSizeX) or half, tonumber(plot.HalfSizeZ) or half
end

-- Rechteck der Base in Weltkoordinaten (waagrecht, aus den 4 Ecken): minX, maxX, minZ, maxZ
function PlotService.WorldRect(plot): (number, number, number, number)
	local hx, hz = PlotService.HalfExtents(plot)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, corner in ipairs({
		Vector3.new(-hx, 0, -hz),
		Vector3.new(hx, 0, -hz),
		Vector3.new(hx, 0, hz),
		Vector3.new(-hx, 0, hz),
	}) do
		local p = plot.CFrame:PointToWorldSpace(corner)
		minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
		minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
	end
	return minX, maxX, minZ, maxZ
end

function PlotService.IsInside(plot, position: Vector3): boolean
	local hx, hz = PlotService.HalfExtents(plot)
	local localPos = plot.CFrame:PointToObjectSpace(position)
	return math.abs(localPos.X) <= hx and math.abs(localPos.Z) <= hz and localPos.Y > -6 and localPos.Y < 40
end

-- Gesperrt = Lock (Lock-Pad) ODER Base-Schild aktiv
function PlotService.IsLocked(plot): boolean
	local now = workspace:GetServerTimeNow()
	return plot.LockedUntil > now or (tonumber(plot.ShieldUntil) or 0) > now
end

-- Läuft ein gekauftes Base-Schild?
function PlotService.IsShielded(plot): boolean
	return (tonumber(plot.ShieldUntil) or 0) > workspace:GetServerTimeNow()
end

function PlotService.SlotCount(player: Player): number
	local extra = Services.MonetizationService.HasPass(player, "ExtraSlots") and Config.ExtraSlotsAmount or 0
	return math.min(Config.BaseSlots + extra, PlotService.MaxSlots)
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

-- Schlüpf-Tempo (Sekunden pro Sekunde): 2 mit dem Gamepass "2x Schlüpfen & Wachsen"
function PlotService.HatchSpeed(player: Player?): number
	if player and Services.MonetizationService.HasPass(player, "FastCharge") then
		return 2
	end
	return 1
end

-- Standpunkt eines Slots (Bodenhöhe, Drehung des Ankers) – hier steht der Meteor bzw. das Alien.
-- Der unsichtbare Anker ist ein Kasten, der AUF dem Boden steht -> seine Unterkante = Boden.
function PlotService.SlotTopCFrame(plot, slot: number): CFrame
	local slotPart = plot.Slots[slot]
	if not slotPart then
		return plot.CFrame
	end
	return slotPart.CFrame * CFrame.new(0, -slotPart.Size.Y / 2, 0)
end

-- Weltposition eines angezeigten Meteors (Part) oder Aliens (Model)
function PlotService.ObjectPosition(object: Instance?): Vector3?
	if not object then
		return nil
	end
	if object:IsA("BasePart") then
		return object.Position
	elseif object:IsA("Model") then
		return object:GetPivot().Position
	end
	return nil
end

-- Halbe Breite eines angezeigten Objekts (für Reichweiten)
function PlotService.ObjectRadius(object: Instance?): number
	if not object then
		return 2
	end
	if object:IsA("BasePart") then
		return object.Size.X / 2
	elseif object:IsA("Model") then
		local size = object:GetExtentsSize()
		return math.max(size.X, size.Z) / 2
	end
	return 2
end

-- -------------------------------------------------------------------
-- METEORE / ALIENS IN DER BASE ANZEIGEN
-- -------------------------------------------------------------------
-- Foto-Deko (Admin-Panel → 📸 Foto-Modus): Ordner im Plot-Model, Teile heißen "Slot<n>"
local PHOTO_FOLDER = "PhotoShowcase"

local function removePhotoDeco(plot, slot: number)
	local folder = plot.Model:FindFirstChild(PHOTO_FOLDER)
	local deco = folder and folder:FindFirstChild("Slot" .. slot)
	if deco then
		deco:Destroy()
	end
end

-- Baut die Optik für einen Eintrag: Alien (geschlüpft) oder Meteor (schlüpft noch).
-- Gibt (Objekt, Teil für Prompts) zurück. Klappt das Alien nicht, wird ein Meteor gezeigt.
local function buildVisual(plot, slot: number, entry, mode: string): (Instance, BasePart)
	local top = PlotService.SlotTopCFrame(plot, slot)
	if entry.Alien ~= nil then
		local ok, result = pcall(AlienFactory.Create, entry, mode)
		if ok and typeof(result) == "Instance" and result:IsA("Model") then
			local model = result :: Model
			model:PivotTo(top)
			local body = model.PrimaryPart or model:FindFirstChild("Body")
			if body and body:IsA("BasePart") then
				return model, body
			end
			model:Destroy()
		else
			warn("[PlotService] Alien konnte nicht gebaut werden: " .. tostring(result))
		end
	end
	local meteor = MeteorFactory.Create(entry, "Base")
	meteor.CFrame = top * CFrame.new(0, meteor.Size.Y / 2, 0)
	return meteor, meteor
end

-- Setzt das Attribut HatchAt (Serverzeit, wann der Meteor schlüpft) – der Client zählt damit herunter
local function setHatchAt(plot, object: Instance, entry)
	if entry.Alien == nil and object:IsA("BasePart") then
		local remaining = math.max(0, tonumber(entry.Hatch) or 0)
		object:SetAttribute("HatchAt", workspace:GetServerTimeNow() + remaining / PlotService.HatchSpeed(plot.Owner))
	else
		object:SetAttribute("HatchAt", nil)
	end
end

local function sellText(entry): string
	return "Verkaufen " .. Util.FormatCash(Config.MeteorValue(entry) * Config.SellRatio)
end

function PlotService.RenderSlot(plot, slot: number)
	local existing = plot.MeteorParts[slot]
	if existing then
		existing:Destroy()
		plot.MeteorParts[slot] = nil
	end
	if not plot.Owner or not plot.Slots[slot] then
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
	removePhotoDeco(plot, slot) -- echter Meteor/Alien ersetzt die Foto-Deko

	local object, promptPart = buildVisual(plot, slot, entry, "Base")
	object:SetAttribute("PlotIndex", plot.Index)
	object:SetAttribute("Slot", slot)
	object:SetAttribute("OwnerUserId", plot.Owner.UserId)
	setHatchAt(plot, object, entry)

	local reach = math.max(10, PlotService.ObjectRadius(object) + 7)
	local name = Config.EntryName(entry)
	local stealPrompt = MeteorFactory.AddPrompt(
		promptPart,
		"StealPrompt",
		"Klauen",
		name,
		Config.StealHoldDuration,
		Enum.KeyCode.E,
		reach
	)
	local sellPrompt =
		MeteorFactory.AddPrompt(promptPart, "SellPrompt", sellText(entry), name, 1, Enum.KeyCode.F, reach)
	-- Klauen: der Server prüft, ob wirklich Config.StealHoldDuration lang gehalten wurde
	MeteorFactory.OnHeldTrigger(stealPrompt, function(player)
		Services.CarryService.TrySteal(player, plot, slot)
	end)
	sellPrompt.Triggered:Connect(function(player)
		Services.EconomyService.Sell(player, plot, slot)
	end)
	object.Parent = plot.MeteorFolder
	plot.MeteorParts[slot] = object
end

-- Nach Level-Up nur Größe/Schild anpassen statt neu bauen
function PlotService.RefreshSlot(plot, slot: number)
	local object = plot.MeteorParts[slot]
	local data = plot.Owner and Services.DataService.Get(plot.Owner)
	local entry = data and data.Meteors[tostring(slot)]
	if not object or not entry then
		return
	end
	local isAlienModel = object:IsA("Model")
	if (entry.Alien ~= nil) ~= isAlienModel then
		-- z.B. gerade geschlüpft -> komplett neu bauen
		PlotService.RenderSlot(plot, slot)
		return
	end
	local promptPart: BasePart? = nil
	if isAlienModel then
		local model = object :: Model
		local ok, err = pcall(AlienFactory.Refresh, model, entry)
		if not ok then
			warn("[PlotService] Alien-Refresh fehlgeschlagen: " .. tostring(err))
		end
		local body = model.PrimaryPart or model:FindFirstChild("Body")
		promptPart = body and body:IsA("BasePart") and body or nil
	elseif object:IsA("BasePart") then
		MeteorFactory.Refresh(object, entry, "Base")
		setHatchAt(plot, object, entry)
		promptPart = object
	end
	local sellPrompt = promptPart and promptPart:FindFirstChild("SellPrompt")
	if sellPrompt and sellPrompt:IsA("ProximityPrompt") then
		sellPrompt.ActionText = sellText(entry)
	end
end

-- Schlüpf-Zeitpunkte neu berechnen (z.B. nach Kauf von "2x Schlüpfen")
function PlotService.UpdateHatchTimes(plot)
	local data = plot.Owner and Services.DataService.Get(plot.Owner)
	if not data then
		return
	end
	for slot, object in pairs(plot.MeteorParts) do
		local entry = data.Meteors[tostring(slot)]
		if entry and object.Parent then
			setHatchAt(plot, object, entry)
		end
	end
end

function PlotService.RenderAll(plot)
	for slot = 1, #plot.Slots do
		PlotService.RenderSlot(plot, slot)
	end
	PlotService.UpdateSlotColors(plot)
end

-- Früher: Slot-Pads einfärben (frei / gesperrt / Foto-Modus). Die Slots sind jetzt unsichtbare
-- Anker ohne Optik – gesperrte Slots (ohne Gamepass) zeigen einfach nichts. Bleibt als Einstieg
-- erhalten (MonetizationService, AdminService, Foto-Modus rufen es auf) und hält die Anker unsichtbar.
function PlotService.UpdateSlotColors(plot)
	for _, slotPart in ipairs(plot.Slots) do
		if slotPart.Transparency ~= 1 then
			slotPart.Transparency = 1
		end
	end
end

-- -------------------------------------------------------------------
-- FOTO-DEKO (nur Optik für Thumbnails: keine Spieldaten, keine Prompts)
-- -------------------------------------------------------------------
-- Füllt ALLE Slots ohne echten Meteor (auch die gesperrten) mit Deko-Aliens.
-- makeEntry() liefert { Id, Alien, Mut, Lv }. Gibt die Anzahl der Deko-Objekte zurück.
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
			local object = buildVisual(plot, slot, entry, "Photo")
			object.Name = "Slot" .. slot
			object.Parent = folder
			count += 1
		end
	end
	PlotService.UpdateSlotColors(plot)
	return count
end

-- Entfernt nur die Deko
function PlotService.ClearPhotoShowcase(plot)
	local folder = plot.Model:FindFirstChild(PHOTO_FOLDER)
	if folder then
		folder:Destroy()
	end
end

-- -------------------------------------------------------------------
-- LOCK
-- -------------------------------------------------------------------
local function setText(label: TextLabel, text: string)
	if label.Text ~= text then
		label.Text = text
	end
end

local LOCK_BARRIER_COLOR = Color3.fromRGB(255, 40, 40)
local SHIELD_BARRIER_COLOR = Color3.fromRGB(60, 170, 255)

local function setColor(part: BasePart, color: Color3)
	if part.Color ~= color then
		part.Color = color
	end
end

function PlotService.UpdateLockVisual(plot)
	local now = workspace:GetServerTimeNow()
	local showerActive = Services.MeteorService and Services.MeteorService.IsShowerActive()
	local shieldUntil = tonumber(plot.ShieldUntil) or 0
	if shieldUntil > now then
		plot.Barrier.Transparency = 0.25
		setColor(plot.Barrier, SHIELD_BARRIER_COLOR)
		setText(plot.LockLabel, "🛡️ SCHILD " .. Util.FormatTime(math.ceil(shieldUntil - now)))
		setColor(plot.LockPad, Color3.fromRGB(70, 130, 200))
	elseif plot.LockedUntil > now then
		plot.Barrier.Transparency = 0.35
		setColor(plot.Barrier, LOCK_BARRIER_COLOR)
		setText(plot.LockLabel, "🔒 " .. math.ceil(plot.LockedUntil - now) .. "s")
		setColor(plot.LockPad, Color3.fromRGB(90, 90, 90))
	else
		plot.Barrier.Transparency = 1
		setColor(plot.Barrier, LOCK_BARRIER_COLOR)
		setText(plot.LockLabel, showerActive and "🌠 KEIN LOCK IM SCHAUER" or "🔒 LOCK")
		setColor(plot.LockPad, Color3.fromRGB(230, 60, 60))
	end
end

-- Attribute fürs Model (der Client liest sie): LockedUntil = Ende der Sperre (Lock ODER Schild),
-- ShieldUntil = Ende des Base-Schilds
local function publishLock(plot)
	local shieldUntil = tonumber(plot.ShieldUntil) or 0
	plot.PublishedShield = shieldUntil
	local effective = math.max(plot.LockedUntil, shieldUntil)
	if plot.Model:GetAttribute("LockedUntil") ~= effective then
		plot.Model:SetAttribute("LockedUntil", effective)
	end
	if plot.Model:GetAttribute("ShieldUntil") ~= shieldUntil then
		plot.Model:SetAttribute("ShieldUntil", shieldUntil)
	end
	PlotService.UpdateLockVisual(plot)
end

function PlotService.SetLocked(plot, untilTime: number)
	plot.LockedUntil = untilTime
	publishLock(plot)
end

-- Base-Schild bis zu dieser Serverzeit (0 = aus)
function PlotService.SetShield(plot, untilTime: number)
	plot.ShieldUntil = math.max(0, tonumber(untilTime) or 0)
	publishLock(plot)
end

-- Base-Schild um "seconds" verlängern (läuft schon eins, wird es länger)
function PlotService.AddShield(plot, seconds: number)
	local now = workspace:GetServerTimeNow()
	PlotService.SetShield(plot, math.max(tonumber(plot.ShieldUntil) or 0, now) + math.max(0, seconds))
end

local function tryLock(player: Player, plot)
	if plot.Owner ~= player or PlotService.IsLocked(plot) then
		return -- schon gesperrt (Lock oder Base-Schild)
	end
	if Services.MeteorService.IsShowerActive() then
		local t = os.clock()
		if t - (lockNotifyAt[player] or -math.huge) >= LOCK_NOTIFY_COOLDOWN then
			lockNotifyAt[player] = t
			Services.EconomyService.Notify(player, "🌠 Während des Meteoritenschauers gibt es keine Locks!", "Error")
		end
		return
	end
	local duration = Services.MonetizationService.HasPass(player, "VIP") and Config.LockDurationVIP
		or Config.LockDuration
	PlotService.SetLocked(plot, workspace:GetServerTimeNow() + duration)
	Services.EconomyService.Notify(player, "🔒 Base für " .. duration .. " Sekunden gesperrt!", "Success")
end

-- Geld-Anzeige über dem Collect-Pad (nur schreiben, wenn sich etwas ändert)
function PlotService.SetCollectText(plot, pending: number)
	setText(plot.CollectLabel, "💰 " .. Util.FormatCash(pending))
end

-- -------------------------------------------------------------------
-- ZUWEISUNG & TELEPORT
-- -------------------------------------------------------------------
local function teleportToPlot(player: Player)
	local character = player.Character
	local plot = PlotService.ByPlayer[player]
	if not character then
		return
	end
	local target = plot and plot.SpawnCFrame or PlotService.LobbySpawn
	character:PivotTo(target)
	Services.CarryService.NoteTeleport(player, target.Position)
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
			plot.ShieldUntil = 0
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
	PlotService.SetCollectText(plot, 0)
	plot.ShieldUntil = 0
	PlotService.SetLocked(plot, 0)
	-- Fallen (Gadget) gehören dem alten Besitzer -> weg
	local traps = plot.Model:FindFirstChild("Traps")
	if traps then
		traps:Destroy()
	end
	for slot, object in pairs(plot.MeteorParts) do
		object:Destroy()
		plot.MeteorParts[slot] = nil
	end
	PlotService.ClearPhotoShowcase(plot)
	PlotService.UpdateSlotColors(plot)
end

function PlotService.TeleportHome(player: Player)
	teleportToPlot(player)
end

-- AUF das beste gekaufte Laufband (hinteres Drittel der Lauffläche, Blick zur Konsole).
-- Neulinge landen so auf dem Holz-Laufband, nicht vor Gold. Lauffläche: lokales -Z (LookVector) = Laufrichtung.
local function treadmillTarget(player: Player): CFrame
	local data = Services.DataService.Get(player)
	local best = Config.BestTreadmill(data and data.Treadmills)
	local folder = PlotService.TreadmillsFolder
	if best and folder then
		for _, model in ipairs(folder:GetChildren()) do
			local belt = model:IsA("Model") and model:GetAttribute("TreadmillId") == best.Id and model.PrimaryPart
			if belt and belt:IsA("BasePart") then
				local look = belt.CFrame.LookVector
				local top = belt.Position + belt.CFrame.UpVector * (belt.Size.Y / 2)
				local spot = top - look * math.max(0, belt.Size.Z / 2 - 4) + Vector3.new(0, 3.5, 0)
				return CFrame.lookAt(spot, spot + Vector3.new(look.X, 0, look.Z))
			end
		end
	end
	return PlotService.TreadmillSpawn
end

function PlotService.TeleportToTreadmills(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end
	local target = treadmillTarget(player)
	character:PivotTo(target)
	Services.CarryService.NoteTeleport(player, target.Position)
	return true
end

-- Teleport-Ziel der Laufband-Zone: von MapBuilder, sonst aus den Laufbändern berechnet
local function findTreadmillSpawn(map: any): CFrame
	if typeof(map.TreadmillSpawn) == "CFrame" then
		return map.TreadmillSpawn
	end
	local folder = map.TreadmillsFolder
	if not folder then
		return PlotService.LobbySpawn
	end
	local fromAttribute = folder:GetAttribute("SpawnCFrame")
	if typeof(fromAttribute) == "CFrame" then
		return fromAttribute
	end
	local sum, count = Vector3.zero, 0
	local look, halfLength = Vector3.new(0, 0, -1), 10
	for _, model in ipairs(folder:GetChildren()) do
		local belt = model:IsA("Model") and model.PrimaryPart
		if belt then
			sum += belt.Position
			count += 1
			look = belt.CFrame.LookVector
			halfLength = belt.Size.Z / 2
		end
	end
	if count == 0 then
		return PlotService.LobbySpawn
	end
	local center = sum / count + Vector3.new(0, 3.5, 0)
	-- Einstieg von hinten (gegen die Laufrichtung), Blick auf die Laufbänder
	local spot = center - look * (halfLength + 7)
	return CFrame.lookAt(spot, center)
end

function PlotService.Init(services)
	Services = services
	local map = MapBuilder.Build() :: any
	PlotService.MapFolder = map.MapFolder
	PlotService.Plots = map.Plots or {}
	PlotService.Parade = map.Parade
	if map.FreeZone then
		PlotService.FreeZone = map.FreeZone
	end
	if typeof(map.LobbySpawn) == "CFrame" then
		PlotService.LobbySpawn = map.LobbySpawn
	end
	if typeof(map.LeaderboardCFrame) == "CFrame" then
		PlotService.LeaderboardCFrame = map.LeaderboardCFrame
	end
	PlotService.TreadmillsFolder = map.TreadmillsFolder
	PlotService.TreadmillSpawn = findTreadmillSpawn(map)

	local maxSlots = Config.BaseSlots + Config.ExtraSlotsAmount
	for _, plot in ipairs(PlotService.Plots) do
		plot.MeteorParts = plot.MeteorParts or {}
		plot.LockedUntil = plot.LockedUntil or 0
		plot.ShieldUntil = plot.ShieldUntil or 0
		plot.PublishedShield = plot.ShieldUntil
		maxSlots = math.min(maxSlots, #plot.Slots)
	end
	PlotService.MaxSlots = maxSlots
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
						"😢 Server voll – keine Base frei. Wechsle den Server!",
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

	-- Pads: Collect-Pad + ALLE eigenen Slot-Anker (durchlaufen) sammeln Geld ein, Lock-Pad sperrt
	-- (Touched mit Entprellung)
	local debounce: { [Player]: number } = {}
	local function onCollectTouch(plot, hit: BasePart)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if player and player == plot.Owner and os.clock() - (debounce[player] or 0) > 0.5 then
			debounce[player] = os.clock()
			Services.EconomyService.Collect(player)
		end
	end
	for _, plot in ipairs(PlotService.Plots) do
		plot.CollectPad.CanTouch = true
		plot.LockPad.CanTouch = true
		plot.CollectPad.Touched:Connect(function(hit)
			onCollectTouch(plot, hit)
		end)
		for _, slotPart in ipairs(plot.Slots) do
			slotPart.CanTouch = true
			slotPart.Touched:Connect(function(hit)
				onCollectTouch(plot, hit)
			end)
		end
		plot.LockPad.Touched:Connect(function(hit)
			local player = Players:GetPlayerFromCharacter(hit.Parent)
			if player and player == plot.Owner then
				tryLock(player, plot)
			end
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		debounce[player] = nil
		lockNotifyAt[player] = nil
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
				-- plot.ShieldUntil direkt geändert (z.B. vom Produkt)? -> Attribute + Anzeige nachziehen
				if (tonumber(plot.ShieldUntil) or 0) ~= plot.PublishedShield then
					publishLock(plot)
				end
				if plot.Owner and PlotService.IsLocked(plot) then
					for _, other in ipairs(Players:GetPlayers()) do
						local character = other.Character
						local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
						if other ~= plot.Owner and character and root and PlotService.IsInside(plot, root.Position) then
							if Services.CarryService.IsCarrying(other) then
								-- Dieb noch drin, als gesperrt wurde -> Beute zurück (eigener Hinweis statt "Teleport")
								Services.CarryService.Fail(other, "locked")
							end
							character:PivotTo(plot.EntranceCFrame)
							Services.CarryService.NoteTeleport(other, plot.EntranceCFrame.Position)
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
