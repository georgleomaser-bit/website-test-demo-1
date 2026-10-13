-- =====================================================================
--  AKYTEX TYCOON – Server-Start (Server/Main)
--  Besitzer: WP1 (Kern & Plattform). Vertrag: DESIGN.md §C3 (CC-Lader 1:1, Präfix "[AKYTEX Tycoon] ").
--  Lädt alle Services in der richtigen Reihenfolge. Hier musst du nichts ändern.
--    Remotes zuerst (Clients warten darauf)
--    Phase 1: alle require (xpcall, FindFirstChild – kein Warten)
--    Vorladen: gesetzte Mesh-Asset-Plätze (§C14.3) nach ReplicatedStorage.AssetCache (nur wenn Ids ≠ 0, ≤ 12 s)
--    Phase 2: Init(Services) in Reihenfolge (Welt bauen, Provide/Handle registrieren)
--    Phase 3: Start() für alle außer DataService (Events, Scheduler-Jobs)
--    Phase 4: DataService.Start() ZULETZT (alle "Spielstand geladen"-Callbacks sind dann registriert)
--    danach Config.Validate()-Warnungen (max. 25) und "Server gestartet ✅"
--  Ein Fehler in einem Service -> warn("[AKYTEX Tycoon] …"), der Rest läuft weiter.
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServicesFolder = script.Parent:WaitForChild("Services")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local PREFIX = "[AKYTEX Tycoon] "
local MAX_CONFIG_WARNINGS = 25

local order = {
	"DataService", -- Spielstände (Session-Lock); Start läuft zuletzt
	"MonetizationService", -- Gamepässe, Käufe, PolicyService
	"PlayerStateService", -- Request-Verteiler, State an die Clients, Ready-Gate, Leaderstats
	"ShopService", -- einziger CR-Gutschreiber/-Abzieher, Gewährungen
	"GraphicsService", -- Future-Licht-Objekte (einmal)
	"CityService", -- Stadt, Bezirke, Anker
	"PlotService", -- 10 Plots am Skyline-Ring
	"MarketService", -- Markt-Engine, GlobalBus, Kerzen, Frames
	"OrderService", -- Orders, Depot, Bots (einziger Depot-Schreiber)
	"TowerService", -- Turm-Ökonomie, Tresor, Offline
	"TowerVisualService", -- Hüllen, Interiors, Plot-Attribute
	"VehicleService", -- Kollisionsgruppen, Autos
	"LifestyleService", -- Uhren, Accessoires, Deko-Lager
	"EventService", -- Welt-Events, Live-Ops-Kalender
	"ProgressionService", -- XP, Lizenzen, Know-how, Ruf, Börsengang
	"RewardService", -- Quests, Login, Saison, Codes
	"CommunityService", -- Ansagen, Freunde, Respekt
	"AntiCheatService", -- Bewegung, Verdachtspunkte, Honeypot
	"AdminService", -- nur der Besitzer
	"LeaderboardService", -- Bestenlisten, Hall of Fame
	"MetricsService", -- Analytics
	"SelfTestService", -- Studio: "[SelfTest] n/n PASS"
}

-- Remotes zuerst anlegen (Clients warten darauf), auch wenn ein Service fehlt
do
	local remotesModule = ServicesFolder:FindFirstChild("Remotes")
	if remotesModule and remotesModule:IsA("ModuleScript") then
		local ok, err = xpcall(require, debug.traceback, remotesModule)
		if not ok then
			warn(PREFIX .. "Fehler beim Anlegen der Remotes: " .. tostring(err))
		end
	else
		warn(PREFIX .. "Services/Remotes fehlt")
	end
end

-- Phase 1: alle Module laden
local Services: { [string]: any } = {}
local loaded: { string } = {}
for _, name in ipairs(order) do
	-- Auf dem Server sind alle Skripte des Orts beim Start schon da -> kein Warten
	local module = ServicesFolder:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		warn(PREFIX .. "Service fehlt: " .. name)
		continue
	end
	local ok, result = xpcall(require, debug.traceback, module)
	if ok and type(result) == "table" then
		Services[name] = result
		table.insert(loaded, name)
	else
		warn(PREFIX .. "Fehler beim Laden von " .. name .. ": " .. tostring(result))
	end
end

-- Fehler in einem Service sollen nicht das ganze Spiel stoppen -> klar im Output melden
local function run(name: string, phase: string, fn: (...any) -> ...any, ...: any)
	local ok, err = xpcall(fn, debug.traceback, ...)
	if not ok then
		warn(PREFIX .. "Fehler in " .. name .. "." .. phase .. ": " .. tostring(err))
	end
end

-- Vorladen der Hybrid-Assets (§C14.3): nur gesetzte Mesh-Plätze (Id ≠ 0), damit Init-Bauer schon Vorlagen klonen.
-- Ohne gesetzte Ids (Standard) kehrt das sofort zurück.
do
	local okConfig, Config = pcall(require, Shared:WaitForChild("Config"))
	local assetModule = Shared:FindFirstChild("AssetSlot")
	if okConfig and type(Config) == "table" and assetModule and assetModule:IsA("ModuleScript") then
		local okAsset, AssetSlot = pcall(require, assetModule)
		if okAsset and type(AssetSlot) == "table" then
			run("AssetSlot", "PreloadServer", function()
				AssetSlot.PreloadServer(AssetSlot.CollectFromConfig(Config))
			end)
		end
	end
end

-- Phase 2: Init (Welt bauen, Verweise setzen – keine Spieler-Logik)
for _, name in ipairs(loaded) do
	local service = Services[name]
	if type(service.Init) == "function" then
		run(name, "Init", service.Init, Services)
	end
end

-- Phase 3: Start (Events, Remote-Handler, Takte). DataService NICHT hier ...
for _, name in ipairs(loaded) do
	local service = Services[name]
	if name ~= "DataService" and type(service.Start) == "function" then
		run(name, "Start", service.Start)
	end
end

-- Phase 4: ... sondern zuletzt, damit alle "Spielstand geladen"-Callbacks schon registriert sind
if Services.DataService and type(Services.DataService.Start) == "function" then
	run("DataService", "Start", Services.DataService.Start)
end

-- Boot-Prüfung der Einstellungen (dieselbe Liste wie im SelfTest)
do
	local okConfig, Config = pcall(require, Shared:WaitForChild("Config"))
	if okConfig and type(Config) == "table" and type(Config.Validate) == "function" then
		local okValidate, errors = pcall(Config.Validate)
		if not okValidate then
			warn(PREFIX .. "Config.Validate fehlgeschlagen: " .. tostring(errors))
		elseif type(errors) == "table" and #errors > 0 then
			warn(PREFIX .. ("Config hat %d Problem(e):"):format(#errors))
			for i = 1, math.min(#errors, MAX_CONFIG_WARNINGS) do
				warn("  - " .. tostring(errors[i]))
			end
			if #errors > MAX_CONFIG_WARNINGS then
				warn(("  … und %d weitere"):format(#errors - MAX_CONFIG_WARNINGS))
			end
		end
		print(PREFIX .. "Server gestartet ✅ (Version " .. tostring(Config.Version) .. ", " .. #loaded .. " Services)")
	else
		warn(PREFIX .. "Config konnte nicht geladen werden: " .. tostring(Config))
		print(PREFIX .. "Server gestartet (ohne Config?)")
	end
end
