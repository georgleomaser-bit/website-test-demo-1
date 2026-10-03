-- =====================================================================
--  METEOR HEIST – Server-Start
--  Lädt alle Services in der richtigen Reihenfolge. Hier musst du nichts ändern.
-- =====================================================================

local Players = game:GetService("Players")
local ServicesFolder = script.Parent:WaitForChild("Services")

local order = {
	"DataService",
	"MonetizationService",
	"PlotService",
	"MeteorService",
	"CarryService",
	"EconomyService",
	"AdminService",
	"LeaderboardService",
}

local Services = {}
for _, name in ipairs(order) do
	Services[name] = require(ServicesFolder:WaitForChild(name))
end

-- Phase 1: Init (Map bauen, Verweise setzen)
for _, name in ipairs(order) do
	local service = Services[name]
	if service.Init then
		service.Init(Services)
	end
end

-- Phase 2: Start (Schleifen + Events). DataService zuletzt, damit alle
-- "Spielstand geladen"-Callbacks schon registriert sind.
for _, name in ipairs(order) do
	local service = Services[name]
	if name ~= "DataService" and service.Start then
		service.Start()
	end
end
Services.DataService.Start()

Players.CharacterAutoLoads = true
print("[Meteor Heist] Server gestartet ✅")
