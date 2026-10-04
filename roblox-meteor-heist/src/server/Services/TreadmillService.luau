-- SPEED FARM: Laufbänder (Treadmills) in der Laufband-Zone am Spawn-Platz.
-- Wer auf einem GEKAUFTEN Laufband läuft, bekommt alle Config.TreadmillTick Sekunden
-- Schritte 👟 (+ fliegende Zahl beim Client). Mehr Schritte = schneller laufen (Config.StepsSpeed).
-- Laufbänder kauft man mit Cash (Config.Treadmills -> Price, Request "BuyTreadmill"), der Reihe nach.
-- Besitz: data.Treadmills = { [Id] = true } – bleibt bei Rebirth. Gratis-Laufbänder (Holz) hat jeder.
--
-- Erkennung "läuft auf dem Band" (bewusst großzügig – lieber etwas AFK tolerieren als dass es nicht geht):
--   1. HumanoidRootPart über der Lauffläche (mit etwas Spielraum, egal ob R6/R15/skaliert)
--   2. Humanoid.MoveDirection zeigt Laufen an  ODER  die Physik zeigt es: der Spieler ist deutlich anders
--      schnell als das Band (wer stillsteht, fährt mit dem Band mit; wer läuft, nicht).
-- Steht man auf einem Band und bekommt KEINE Schritte, gibt es einen kurzen Hinweis mit dem Grund (gedrosselt).
-- Schritte gibt es nur hier im Server-Tick – kein Remote kann Schritte auslösen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))

local TreadmillService = {}
local Services

type Treadmill = {
	Def: any,
	Belt: BasePart,
	CFrame: CFrame,
	HalfX: number,
	HalfZ: number,
	TopY: number,
	Velocity: Vector3, -- so schnell soll das Band schieben (Welt)
}

-- aufsteigend nach Preis
local treadmills: { Treadmill } = {}
local zoneCenter = Vector3.zero
local zoneRadius = 0
local lastHint: { [Player]: number } = {}
local idleSince: { [Player]: number } = {}

local MAX_HEIGHT = 10 -- HumanoidRootPart höchstens so hoch über der Lauffläche (Springen, große Avatare)
local MIN_HEIGHT = -0.5
-- Spielraum um die Lauffläche (Füße ragen über die Hüfte hinaus; Seitenrahmen innen beginnt direkt am Band)
local MARGIN_X = 0.5
local MARGIN_Z = 1
local MIN_MOVE = 0.05 -- Humanoid.MoveDirection mindestens so lang = Spieler drückt eine Lauf-Taste
-- Physik-Prüfung: so viel anders schnell als das Band (Studs/s) = läuft. Wer stillsteht, fährt mit (≈ 0).
local MIN_RELATIVE_SPEED = 3
local HINT_COOLDOWN = 5 -- Hinweise ("Lauf los", "gehört dir nicht", "lädt") höchstens so oft
local IDLE_HINT_AFTER = 1.5 -- erst nach so langem Stillstehen auf dem Band "Lauf los!" zeigen
local RESCAN_INTERVAL = 5

local function treadmillsFolder(): Instance?
	local plotService = Services and Services.PlotService
	local folder = plotService and plotService.TreadmillsFolder
	if folder and folder.Parent then
		return folder
	end
	-- Ersatz: direkt in der Map suchen (z.B. wenn PlotService den Ordner nicht weitergereicht hat)
	local map = workspace:FindFirstChild("MeteorHeistMap")
	return map and map:FindFirstChild("Treadmills")
end

-- Soll-Geschwindigkeit des Bandes (Attribute von MapBuilder, sonst Config)
local function beltVelocity(belt: BasePart): Vector3
	local dir = belt:GetAttribute("BeltDir")
	local speed = tonumber(belt:GetAttribute("BeltSpeed")) or tonumber(Config.TreadmillPush) or 6
	local worldDir: Vector3 = if typeof(dir) == "Vector3" and dir.Magnitude > 0.001
		then dir.Unit
		else -belt.CFrame.LookVector
	return worldDir * speed
end

-- Laufbänder aus der Map einlesen (MapBuilder baut je Eintrag in Config.Treadmills ein Model)
local function collect()
	table.clear(treadmills)
	local folder = treadmillsFolder()
	if not folder then
		return
	end
	local sum = Vector3.zero
	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") then
			local id = model:GetAttribute("TreadmillId") or model.Name
			local def = type(id) == "string" and Config.TreadmillsById[id] or nil
			local belt = model.PrimaryPart or model:FindFirstChild("Belt")
			if def and belt and belt:IsA("BasePart") then
				table.insert(treadmills, {
					Def = def,
					Belt = belt,
					CFrame = belt.CFrame,
					HalfX = belt.Size.X / 2,
					HalfZ = belt.Size.Z / 2,
					TopY = belt.Size.Y / 2,
					Velocity = beltVelocity(belt),
				})
				sum += belt.Position
			end
		end
	end
	table.sort(treadmills, function(a, b)
		return a.Def.Price < b.Def.Price
	end)
	if #treadmills > 0 then
		-- grobe Vorab-Prüfung: Kreis um alle Laufbänder (spart Rechnen, wenn niemand dort ist)
		zoneCenter = sum / #treadmills
		zoneRadius = 0
		for _, treadmill in ipairs(treadmills) do
			local reach = (treadmill.CFrame.Position - zoneCenter).Magnitude
				+ math.sqrt((treadmill.HalfX + MARGIN_X) ^ 2 + (treadmill.HalfZ + MARGIN_Z) ^ 2)
			zoneRadius = math.max(zoneRadius, reach + MAX_HEIGHT)
		end
	end
end

-- Auf welchem Laufband steht diese Position (HumanoidRootPart)?
function TreadmillService.FindTreadmill(position: Vector3): Treadmill?
	if #treadmills == 0 or (position - zoneCenter).Magnitude > zoneRadius then
		return nil
	end
	for _, treadmill in ipairs(treadmills) do
		local localPos = treadmill.CFrame:PointToObjectSpace(position)
		local height = localPos.Y - treadmill.TopY
		if
			math.abs(localPos.X) <= treadmill.HalfX + MARGIN_X
			and math.abs(localPos.Z) <= treadmill.HalfZ + MARGIN_Z
			and height > MIN_HEIGHT
			and height < MAX_HEIGHT
		then
			return treadmill
		end
	end
	return nil
end

-- Steht der Spieler wirklich AUF der Lauffläche? Strahl von der Hüfte nach unten muss das Band treffen
-- (nicht Seitenrahmen, Rampe oder Konsole). Unabhängig von R6/R15, HipHeight und Avatar-Größe.
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
local function standsOnBelt(treadmill: Treadmill, root: BasePart, character: Model): boolean
	rayParams.FilterDescendantsInstances = { character }
	local result = workspace:Raycast(root.Position, Vector3.new(0, -(MAX_HEIGHT + 2), 0), rayParams)
	return result ~= nil and result.Instance == treadmill.Belt
end

-- Physik: ist der Spieler (waagerecht) deutlich anders schnell als das Band? Stillstehen = mitfahren = nein.
-- Funktioniert auch, wenn Humanoid.MoveDirection beim Server nicht ankommt.
local function walkingByPhysics(treadmill: Treadmill, root: BasePart, character: Model): boolean
	local relative = root.AssemblyLinearVelocity - treadmill.Velocity
	relative -= Vector3.yAxis * relative.Y
	return relative.Magnitude > MIN_RELATIVE_SPEED and standsOnBelt(treadmill, root, character)
end

local function hint(player: Player, text: string, kind: string?)
	local t = os.clock()
	if t - (lastHint[player] or -math.huge) >= HINT_COOLDOWN then
		lastHint[player] = t
		Services.EconomyService.Notify(player, text, kind or "Info")
	end
end

-- Ein Tick für einen Spieler. Gibt den Grund zurück (für Tests/Fehlersuche):
-- "steps", "none" (nicht auf einem Band), "dead", "loading", "idle", "locked"
function TreadmillService.TickPlayer(player: Player): string
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		idleSince[player] = nil
		return "none"
	end
	local treadmill = TreadmillService.FindTreadmill(root.Position)
	if not treadmill then
		idleSince[player] = nil
		return "none"
	end
	if humanoid.Health <= 0 then
		return "dead"
	end
	-- Nur der Spielstand muss da sein (nicht die ganze Einrichtung) – Schritte gehen so ab der ersten Sekunde
	local data = Services.DataService.Get(player)
	if not data then
		hint(player, "⏳ Dein Spielstand lädt noch – gleich gibt's Schritte!")
		return "loading"
	end
	local walking = humanoid.MoveDirection.Magnitude > MIN_MOVE or walkingByPhysics(treadmill, root, character :: Model)
	if not walking then
		local now = os.clock()
		local since = idleSince[player]
		if not since then
			idleSince[player] = now
		elseif now - since >= IDLE_HINT_AFTER then
			hint(player, "👟 Lauf los! Halte W gedrückt (nach vorne zur Konsole) – nur Laufen gibt Schritte.")
		end
		return "idle"
	end
	idleSince[player] = nil
	local def = treadmill.Def
	if not Config.OwnsTreadmill(data.Treadmills, def.Id) then
		hint(player, "🔒 Kaufe dieses Laufband im Laufbänder-Menü (" .. Util.FormatCash(def.Price) .. ")", "Error")
		return "locked"
	end
	local gain = def.Rate * Services.EconomyService.GetStepsMult(player)
	Services.EconomyService.AddSteps(player, gain) -- passt die Laufgeschwindigkeit an + MarkDirty
	Remotes.Effect:FireClient(player, "Steps", gain)
	-- Tagesaufgabe "Lauf X Schritte" (ein Fehler dort darf das Schritte-Sammeln nicht stoppen)
	local rewards = Services.RewardService
	if rewards and rewards.Track then
		local ok, err = pcall(rewards.Track, player, "Steps", gain)
		if not ok then
			warn("[TreadmillService] RewardService.Track fehlgeschlagen: " .. tostring(err))
		end
	end
	return "steps"
end

-- Band-Geschwindigkeit sicherstellen: verankerte Teile schieben nur mit gesetzter AssemblyLinearVelocity.
-- Falls sie irgendwo zurückgesetzt wurde (oder nie ankam), hier wieder setzen.
local function keepBeltsMoving()
	for _, treadmill in ipairs(treadmills) do
		local belt = treadmill.Belt
		if belt.Parent and (belt.AssemblyLinearVelocity - treadmill.Velocity).Magnitude > 0.05 then
			belt.AssemblyLinearVelocity = treadmill.Velocity
		end
	end
end

-- Laufband mit Cash kaufen (Request "BuyTreadmill"). Gibt (Erfolg, Nachricht) zurück.
-- Regeln: gibt es, noch nicht gekauft, das vorige Laufband schon gekauft, genug Cash.
function TreadmillService.Buy(player: Player, id: any): (boolean, string)
	if type(id) ~= "string" or #id > 40 then
		return false, "Unbekanntes Laufband"
	end
	local def = Config.TreadmillsById[id]
	local data = Services.DataService.Get(player)
	if not def then
		return false, "Unbekanntes Laufband"
	end
	if not data or not Services.EconomyService.IsReady(player) then
		return false, "Lädt noch..."
	end
	if type(data.Treadmills) ~= "table" then
		data.Treadmills = {}
	end
	if Config.OwnsTreadmill(data.Treadmills, def.Id) then
		return false, def.Name .. " hast du schon"
	end
	local index = table.find(Config.Treadmills, def)
	local previous = index and index > 1 and Config.Treadmills[index - 1] or nil
	if previous and not Config.OwnsTreadmill(data.Treadmills, previous.Id) then
		return false, "Kaufe zuerst das " .. previous.Name
	end
	local cash = tonumber(data.Cash) or 0
	if cash ~= cash or cash < def.Price then
		return false, "Du brauchst " .. Util.FormatCash(def.Price) .. " für das " .. def.Name
	end
	data.Cash = cash - def.Price
	data.Treadmills[def.Id] = true
	Services.EconomyService.MarkDirty(player)
	task.spawn(Services.DataService.Save, player) -- teurer Kauf -> gleich sichern
	Services.EconomyService.Effect(player, "Confetti", 1)
	return true, def.Name .. " gekauft! Lauf drauf los."
end

function TreadmillService.Init(services)
	Services = services
end

-- Ein Durchlauf der Schleife (für Tests einzeln aufrufbar)
local lastScan = -math.huge
function TreadmillService.Step()
	if #treadmills == 0 and os.clock() - lastScan >= RESCAN_INTERVAL then
		lastScan = os.clock()
		collect()
	end
	if #treadmills == 0 then
		return
	end
	keepBeltsMoving()
	for _, player in ipairs(Players:GetPlayers()) do
		local ok, err = pcall(TreadmillService.TickPlayer, player)
		if not ok then
			warn("[TreadmillService] Fehler bei " .. player.Name .. ": " .. tostring(err))
		end
	end
end

function TreadmillService.Start()
	lastScan = os.clock()
	collect()
	if #treadmills == 0 then
		warn("[TreadmillService] Keine Laufbänder gefunden – suche weiter...")
	end

	Players.PlayerRemoving:Connect(function(player)
		lastHint[player] = nil
		idleSince[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(Config.TreadmillTick)
			local ok, err = pcall(TreadmillService.Step)
			if not ok then
				warn("[TreadmillService] Tick-Fehler: " .. tostring(err))
			end
		end
	end)
end

return TreadmillService
