-- SPEED FARM: Laufbänder (Treadmills) in der Laufband-Zone am Spawn-Platz.
-- Wer auf einem freigeschalteten Laufband läuft, bekommt alle Config.TreadmillTick Sekunden
-- Schritte 👟 (+ fliegende Zahl beim Client). Mehr Schritte = schneller laufen (Config.StepsSpeed).
-- Höhere Laufbänder werden durch genug Schritte freigeschaltet (Config.Treadmills -> Required).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))

local TreadmillService = {}
local Services

-- { Def, Belt, CFrame, HalfX, HalfZ, TopY } – aufsteigend nach Required
local treadmills = {}
local zoneCenter = Vector3.zero
local zoneRadius = 0
local lastLockedNotify: { [Player]: number } = {}

local EDGE_TOLERANCE = 0.75 -- etwas Spielraum am Rand der Lauffläche
local MAX_HEIGHT = 8 -- HumanoidRootPart höchstens so hoch über der Lauffläche (Springen zählt mit)
local LOCKED_NOTIFY_COOLDOWN = 3
local MIN_MOVE = 0.1 -- Humanoid.MoveDirection muss mindestens so lang sein (= Spieler läuft)
-- Zweite Prüfung über die Physik: Wer stillsteht, fährt mit dem Band mit (gleiches Tempo wie das Band).
-- Wer läuft (oder vorne gegen die Konsole läuft), ist deutlich langsamer/schneller als das Band.
local MIN_RELATIVE_SPEED = 4
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
					HalfX = belt.Size.X / 2 + EDGE_TOLERANCE,
					HalfZ = belt.Size.Z / 2 + EDGE_TOLERANCE,
					TopY = belt.Size.Y / 2,
				})
				sum += belt.Position
			end
		end
	end
	table.sort(treadmills, function(a, b)
		return a.Def.Required < b.Def.Required
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

local function tickPlayer(player: Player)
	local data = Services.DataService.Get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not data or not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	local treadmill = TreadmillService.FindTreadmill(root.Position)
	if not treadmill then
		return
	end
	-- nur wer läuft, sammelt Schritte
	local walking = humanoid.MoveDirection.Magnitude > MIN_MOVE
	if not walking then
		local relative = root.AssemblyLinearVelocity - treadmill.Belt.AssemblyLinearVelocity
		walking = Vector3.new(relative.X, 0, relative.Z).Magnitude > MIN_RELATIVE_SPEED
	end
	if not walking then
		return
	end
	local def = treadmill.Def
	if data.Steps < def.Required then
		local t = os.clock()
		if t - (lastLockedNotify[player] or 0) >= LOCKED_NOTIFY_COOLDOWN then
			lastLockedNotify[player] = t
			Services.EconomyService.Notify(
				player,
				"🔒 " .. def.Name .. " braucht " .. Util.FormatNumber(def.Required) .. " 👟",
				"Error"
			)
		end
		return
	end
	local gain = def.Rate * Services.EconomyService.GetStepsMult(player)
	Services.EconomyService.AddSteps(player, gain) -- passt die Laufgeschwindigkeit an + MarkDirty
	Remotes.Effect:FireClient(player, "Steps", gain)
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
