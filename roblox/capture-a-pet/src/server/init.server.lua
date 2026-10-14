-- Capture a Pet: server entry point. Every service gets Init(services) first, then Start().
-- DataService starts last so all "player loaded" callbacks are registered before anyone loads.

local Services = script:WaitForChild("Services")

local order = {
	"WorldBuilder",
	"Router",
	"PlayerService",
	"PlotService",
	"ShopService",
	"CarryService",
	"TrainingService",
	"WildService",
	"NestService",
	"LairService",
	"StealService",
	"MountService",
	"RewardService",
	"MonetizationService",
	"LeaderboardService",
	"AdminService",
	"DataService",
}

local services = {}
for _, name in ipairs(order) do
	services[name] = require(Services:WaitForChild(name))
end

for _, name in ipairs(order) do
	local service = services[name]
	if service.Init then
		service.Init(services)
	end
end

for _, name in ipairs(order) do
	local service = services[name]
	if service.Start then
		local ok, err = pcall(service.Start)
		if not ok then
			warn("[Capture a Pet] " .. name .. " failed to start: " .. tostring(err))
		end
	end
end

print("[Capture a Pet] server ready")
