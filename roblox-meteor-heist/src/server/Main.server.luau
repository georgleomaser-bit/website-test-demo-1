-- =====================================================================
--  METEOR HEIST – Server-Start
--  Lädt alle Services in der richtigen Reihenfolge. Hier musst du nichts ändern.
-- =====================================================================

local Players = game:GetService("Players")
local ServicesFolder = script.Parent:WaitForChild("Services")

local order = {
	"DataService",
	"MonetizationService",
	"GraphicsService", -- Licht & Himmel (vor der Map)
	"PlotService", -- baut die Map (MapBuilder) + Basen
	"MeteorService", -- Alien-Parade mit Eiern, Gratis-Zone, Eier am Boden, Schauer, Egg Rush
	"CarryService", -- Klauen & Tragen, Bonk
	"GadgetService", -- Speed Coil, Falle, Super-Bonk, Umhang
	"EconomyService",
	"RewardService", -- Spielzeit-Geschenke, Glücksrad, Tagesaufgaben
	"TreadmillService", -- Laufbänder: Schritte farmen
	"RunService", -- ☄️ Meteor-Run: Lauf-Parcours mit Gratis-Ei als Belohnung
	"AdminService",
	"LeaderboardService",
}

local Services = {}
local loaded = {}
for _, name in ipairs(order) do
	local module = ServicesFolder:WaitForChild(name, 10)
	if not module or not module:IsA("ModuleScript") then
		warn("[Meteor Heist] Service fehlt: " .. name)
		continue
	end
	local ok, result = xpcall(require, debug.traceback, module)
	if ok and type(result) == "table" then
		Services[name] = result
		table.insert(loaded, name)
	else
		warn("[Meteor Heist] Fehler beim Laden von " .. name .. ": " .. tostring(result))
	end
end

-- Fehler in einem Service sollen nicht das ganze Spiel stoppen -> klar im Output melden
local function run(name: string, phase: string, fn: (...any) -> ...any, ...: any)
	local ok, err = xpcall(fn, debug.traceback, ...)
	if not ok then
		warn("[Meteor Heist] Fehler in " .. name .. "." .. phase .. ": " .. tostring(err))
	end
end

-- Phase 1: Init (Map bauen, Verweise setzen)
for _, name in ipairs(loaded) do
	local service = Services[name]
	if service.Init then
		run(name, "Init", service.Init, Services)
	end
end

-- Phase 2: Start (Schleifen + Events). DataService zuletzt, damit alle
-- "Spielstand geladen"-Callbacks schon registriert sind.
for _, name in ipairs(loaded) do
	local service = Services[name]
	if name ~= "DataService" and service.Start then
		run(name, "Start", service.Start)
	end
end
if Services.DataService then
	run("DataService", "Start", Services.DataService.Start)
end

Players.CharacterAutoLoads = true
print("[Meteor Heist] Server gestartet ✅")
