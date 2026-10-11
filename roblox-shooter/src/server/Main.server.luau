-- =====================================================================
--  CLUTCH CLASH – Server-Start (Server/Main)
--  Besitzer: WP1 (Core & Plattform). Vertrag: DESIGN.md C3 (Meteor-Heist-Lader 1:1).
--  Lädt alle Services in der richtigen Reihenfolge. Hier musst du nichts ändern.
--    Phase 1: alle require (xpcall)   Phase 2: Init(Services) in Reihenfolge
--    Phase 3: Start() für alle außer DataService   Phase 4: DataService.Start() ZULETZT
--  Ein Fehler in einem Service -> warn("[Clutch Clash] …"), der Rest läuft weiter.
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServicesFolder = script.Parent:WaitForChild("Services")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local PREFIX = "[Clutch Clash] "
local MAX_CONFIG_WARNINGS = 25

local order = {
	"DataService", -- Spielstände (Session-Lock); Start läuft zuletzt
	"MonetizationService", -- Gamepässe, Käufe, PolicyService
	"PlayerStateService", -- Request-Verteiler, State an die Clients, Ready-Gate
	"GraphicsService", -- Lobby-Licht (einmal)
	"ArenaService", -- Kollisionsgruppen + Arena-Vorlagen (VOR der Lobby)
	"LobbyBuilder", -- Clutch Plaza, Pads, Range, Crown Ring
	"HistoryService", -- Positions-Verlauf fürs Rückspulen
	"CombatService", -- HP, Schaden, Pops
	"CharacterService", -- Figuren, Vault, Waffen in der Hand
	"ProjectileService", -- Raketen, Granaten, Rauch
	"WeaponService", -- Schüsse prüfen
	"ReplicationService", -- Look/LookBatch/FX
	"AntiCheatService", -- Bewegung, Verdachtspunkte, Honeypot
	"BotService", -- ehrliche [BOT]s
	"RangeService", -- Schießstand
	"MatchService", -- Matches, Runden, Crown
	"QueueService", -- Pads + Warteschlangen
	"ProgressionService", -- XP, Level, MMR, Meisterschaft
	"RewardService", -- Quests, Login, Glücksrad
	"CommunityService", -- GG, Loben, Kopfgeld, Ansagen
	"ShopService", -- Währung, Waffen, Kosmetik, Kisten
	"BalanceService", -- Live-Balancing
	"AdminService", -- nur der Besitzer
	"LeaderboardService", -- globale Bestenlisten
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
	-- (MH wartete 10 s je Name; ein fehlender Service würde den Start sonst lange aufhalten)
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
