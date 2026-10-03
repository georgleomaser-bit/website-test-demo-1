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
	"MeteorService", -- Laufband mit Meteoren, Gratis-Zone, Schauer
	"CarryService",
	"EconomyService",
	"TreadmillService", -- Laufbänder: Schritte farmen
	"AdminService",
	"LeaderboardService",
}

local Services = {}
for _, name in ipairs(order) do
	Services[name] = require(ServicesFolder:WaitForChild(name))
end

-- Fehler in einem Service sollen nicht das ganze Spiel stoppen -> klar im Output melden
local function run(name: string, phase: string, fn: (...any) -> ...any, ...: any)
	local ok, err = xpcall(fn, debug.traceback, ...)
	if not ok then
		warn("[Meteor Heist] Fehler in " .. name .. "." .. phase .. ": " .. tostring(err))
	end
end

-- Phase 1: Init (Map bauen, Verweise setzen)
for _, name in ipairs(order) do
	local service = Services[name]
	if service.Init then
		run(name, "Init", service.Init, Services)
	end
end

-- Phase 2: Start (Schleifen + Events). DataService zuletzt, damit alle
-- "Spielstand geladen"-Callbacks schon registriert sind.
for _, name in ipairs(order) do
	local service = Services[name]
	if name ~= "DataService" and service.Start then
		run(name, "Start", service.Start)
	end
end
run("DataService", "Start", Services.DataService.Start)

Players.CharacterAutoLoads = true
print("[Meteor Heist] Server gestartet ✅")
