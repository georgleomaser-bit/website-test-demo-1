--[[
	🍋 ZITRONEN-FABRIK TYCOON – Server-Start
	Baut die Welt und startet alle Services in der richtigen Reihenfolge.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
Remotes.Init()

local WorldBuilder = require(script.Parent.World.WorldBuilder)
local world = WorldBuilder.Build(workspace, Lighting)
WorldBuilder.SetupLighting(Lighting)
task.spawn(function()
	local ok, err = pcall(WorldBuilder.SetupTerrain, workspace.Terrain)
	if not ok then
		warn("[ZitronenFabrik] Wasser konnte nicht erstellt werden: " .. tostring(err))
	end
end)

local Services = script.Parent.Services
local ORDER = {
	"Core",
	"DataService",
	"PlotService",
	"ProductionService",
	"ShopService",
	"PrestigeService",
	"EventService",
	"SecretService",
	"RewardService",
	"LeaderboardService",
	"MonetizationService",
	"AdminService",
	"PlayerService",
}

local modules = {}
for _, name in ipairs(ORDER) do
	modules[name] = require(Services:WaitForChild(name))
end
for _, name in ipairs(ORDER) do
	local module = modules[name]
	if module.Init then
		module.Init(world)
	end
end
for _, name in ipairs(ORDER) do
	local module = modules[name]
	if module.Start then
		task.spawn(module.Start)
	end
end

print("🍋 Zitronen-Fabrik Tycoon gestartet!")
