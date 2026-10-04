-- SPEED FARM: Laufbänder (Treadmills) in der Laufband-Zone am Spawn-Platz.
-- Wer auf einem GEKAUFTEN Laufband läuft, bekommt alle Config.TreadmillTick Sekunden
-- Schritte 👟 (+ fliegende Zahl beim Client). Mehr Schritte = schneller laufen (Config.StepsSpeed).
-- Laufbänder kauft man mit Cash (Config.Treadmills -> Price, Request "BuyTreadmill"), der Reihe nach.
-- Besitz: data.Treadmills = { [Id] = true } – bleibt bei Rebirth.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))

local TreadmillService = {}
local Services

-- { Def, Belt, CFrame, HalfX, HalfZ, TopY } – aufsteigend nach Preis
local treadmills = {}
local zoneCenter = Vector3.zero
local zoneRadius = 0
local lastLockedNotify: { [Player]: number } = {}
-- true = beim Server kommt Humanoid.MoveDirection an (schon einmal gesehen) -> keine Ersatz-Prüfung nötig
local moveDirectionWorks: { [Player]: boolean } = {}

local MAX_HEIGHT = 8 -- HumanoidRootPart höchstens so hoch über der Lauffläche (Springen zählt mit)
local LOCKED_NOTIFY_COOLDOWN = 3
local MIN_MOVE = 0.1 -- Humanoid.MoveDirection muss mindestens so lang sein (= Spieler läuft)
-- Ersatz-Prüfung über die Physik (nur falls MoveDirection beim Server nie ankommt):
-- Wer stillsteht, fährt mit dem Band mit (gleiches Tempo wie das Band). Wer läuft (oder vorne gegen
-- die Konsole läuft), ist entlang der Bandrichtung deutlich langsamer/schneller als das Band.
local MIN_RELATIVE_SPEED = 4
-- ...und nur, wenn man wirklich AUF dem Band steht: Hüfte in normaler Stehhöhe über der Lauffläche.
-- Auf dem Seitenrahmen (0,7 höher) oder der Konsole steht man höher -> zählt nicht.
local STAND_TOLERANCE = 0.45
local RESCAN_INTERVAL = 5

-- Laufbänder aus der Map einlesen (MapBuilder baut je Eintrag in Config.Treadmills ein Model)
local function collect()
	table.clear(treadmills)
	local folder = Services.PlotService.TreadmillsFolder
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
					-- Lauffläche OHNE Spielraum: direkt daneben stehen Seitenrahmen, Konsole und Chassis.
					-- Wer dort stillsteht, darf nicht als "läuft auf dem Band" zählen.
					HalfX = belt.Size.X / 2,
					HalfZ = belt.Size.Z / 2,
					TopY = belt.Size.Y / 2,
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
				+ math.sqrt(treadmill.HalfX ^ 2 + treadmill.HalfZ ^ 2)
			zoneRadius = math.max(zoneRadius, reach + MAX_HEIGHT)
		end
	end
end

-- Auf welchem Laufband steht diese Position? (lokale Koordinaten zur Lauffläche)
function TreadmillService.FindTreadmill(position: Vector3)
	if #treadmills == 0 or (position - zoneCenter).Magnitude > zoneRadius then
		return nil
	end
	for _, treadmill in ipairs(treadmills) do
		local localPos = treadmill.CFrame:PointToObjectSpace(position)
		local height = localPos.Y - treadmill.TopY
		if
			math.abs(localPos.X) <= treadmill.HalfX
			and math.abs(localPos.Z) <= treadmill.HalfZ
			and height > -0.5
			and height < MAX_HEIGHT
		then
			return treadmill
		end
	end
	return nil
end

-- Normale Höhe des HumanoidRootPart über dem Boden, wenn man steht (R15 bzw. R6)
local function standHeight(humanoid: Humanoid, root: BasePart): number
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	return root.Size.Y / 2 + 2 -- R6: Beine sind 2 Studs lang
end

-- Ersatz-Prüfung über die Physik: steht der Spieler auf DIESEM Band und ist er entlang der
-- Bandrichtung deutlich anders schnell als das Band (= er läuft dagegen an)?
local function walkingByPhysics(treadmill, humanoid: Humanoid, root: BasePart): boolean
	local belt: BasePart = treadmill.Belt
	local localPos = treadmill.CFrame:PointToObjectSpace(root.Position)
	local height = localPos.Y - treadmill.TopY
	if math.abs(height - standHeight(humanoid, root)) > STAND_TOLERANCE then
		return false -- springt, oder steht auf Seitenrahmen/Konsole statt auf dem Band
	end
	local beltVelocity = belt.AssemblyLinearVelocity
	local beltSpeed = beltVelocity.Magnitude
	if beltSpeed < 0.01 then
		return false
	end
	local along = beltVelocity / beltSpeed
	local relative = beltSpeed - root.AssemblyLinearVelocity:Dot(along)
	return math.abs(relative) > MIN_RELATIVE_SPEED
end

local function tickPlayer(player: Player)
	local data = Services.DataService.Get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not data or not root or not humanoid or humanoid.Health <= 0 or not Services.EconomyService.IsReady(player) then
		return
	end
	-- nur wer läuft, sammelt Schritte
	local walking = humanoid.MoveDirection.Magnitude > MIN_MOVE
	if walking then
		moveDirectionWorks[player] = true
	end
	local treadmill = TreadmillService.FindTreadmill(root.Position)
	if not treadmill then
		return
	end
	if not walking and not moveDirectionWorks[player] then
		walking = walkingByPhysics(treadmill, humanoid, root)
	end
	if not walking then
		return
	end
	local def = treadmill.Def
	if not Config.OwnsTreadmill(data.Treadmills, def.Id) then
		local t = os.clock()
		if t - (lastLockedNotify[player] or 0) >= LOCKED_NOTIFY_COOLDOWN then
			lastLockedNotify[player] = t
			Services.EconomyService.Notify(
				player,
				"🔒 Kaufe dieses Laufband im Laufbänder-Menü (" .. Util.FormatCash(def.Price) .. ")",
				"Error"
			)
		end
		return
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
	if data.Cash < def.Price then
		return false, "Du brauchst " .. Util.FormatCash(def.Price) .. " für das " .. def.Name
	end
	data.Cash -= def.Price
	data.Treadmills[def.Id] = true
	Services.EconomyService.MarkDirty(player)
	task.spawn(Services.DataService.Save, player) -- teurer Kauf -> gleich sichern
	Services.EconomyService.Effect(player, "Confetti", 1)
	return true, def.Name .. " gekauft! Lauf drauf los."
end

function TreadmillService.Init(services)
	Services = services
end

function TreadmillService.Start()
	collect()
	if #treadmills == 0 then
		warn("[TreadmillService] Keine Laufbänder gefunden – suche weiter...")
	end

	Players.PlayerRemoving:Connect(function(player)
		lastLockedNotify[player] = nil
		moveDirectionWorks[player] = nil
	end)

	task.spawn(function()
		local lastScan = os.clock()
		while true do
			task.wait(Config.TreadmillTick)
			if #treadmills == 0 and os.clock() - lastScan >= RESCAN_INTERVAL then
				lastScan = os.clock()
				collect()
			end
			if #treadmills > 0 then
				for _, player in ipairs(Players:GetPlayers()) do
					local ok, err = pcall(tickPlayer, player)
					if not ok then
						warn("[TreadmillService] Fehler bei " .. player.Name .. ": " .. tostring(err))
					end
				end
			end
		end
	end)
end

return TreadmillService
