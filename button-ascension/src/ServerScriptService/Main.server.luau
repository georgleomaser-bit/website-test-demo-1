--[[
	Main (Script)
	Location: ServerScriptService/Main

	Server entry point. Creates the remotes, loads every service, then calls
	Init (wire up, register actions) and Start (begin loops) in a fixed order.
	Services reach each other through the shared `services` table instead of
	requiring each other, which keeps the module graph free of cycles.

	Dependencies: ServerScriptService/Core/*, ServerScriptService/Services/*,
	ServerScriptService/Admin/AdminService, ReplicatedStorage/Shared/Remotes
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
Remotes.init()

local Services = ServerScriptService:WaitForChild("Services")
local Admin = ServerScriptService:WaitForChild("Admin")
local Net = require(ServerScriptService:WaitForChild("Core"):WaitForChild("Net"))

local ORDER = {
	"SecurityService",
	"DataService",
	"EventService",
	"StatsService",
	"SyncService",
	"EconomyService",
	"QuestService",
	"AchievementService",
	"ClickService",
	"UpgradeService",
	"ChestService",
	"InventoryService",
	"ProgressionService",
	"OrbService",
	"SettingsService",
	"LeaderboardService",
	"WorldService",
	"AdminService",
}

local services = { Order = ORDER, Net = Net }

for _, name in ipairs(ORDER) do
	local module = Services:FindFirstChild(name) or Admin:FindFirstChild(name)
	assert(module, "Missing service module: " .. name)
	services[name] = require(module)
end

Net.init(services)

for _, name in ipairs(ORDER) do
	local service = services[name]
	if service.Init then
		service:Init(services)
	end
end

for _, name in ipairs(ORDER) do
	local service = services[name]
	if service.Start then
		local ok, err = pcall(service.Start, service)
		if not ok then
			warn(`[Main] {name}.Start failed: {err}`)
		end
	end
end

print(`[Main] Click a Button server started with {#ORDER} services.`)
