--[[
	EventService (ModuleScript)
	Location: ServerScriptService/Services/EventService
	Depends on: Shared/Config/GameConfig, Shared/Remotes, StatsService, Net

	Server-wide boost events (Spark Surge, Lucky Hour, ...). Started by admins
	or by the automatic scheduler. Active events are replicated through
	attributes on ReplicatedStorage/ServerState ("Event_<id>" = end time as a
	unix timestamp) so every client can show banners and timers. Event effects
	are applied by Formulas through StatsService.

	Events only affect THIS server; they are labelled "server event" in the UI.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Remotes)

local EVENTS = GameConfig.Events

local EventService = {
	Name = "EventService",
	Active = {} :: { [string]: { EndsAt: number, StartedBy: string } },
}

local activeList: { string } = {}
local nextAutoAt = 0

local function rebuildList()
	table.clear(activeList)
	for _, id in ipairs(EVENTS.Order) do
		if EventService.Active[id] then
			table.insert(activeList, id)
		end
	end
end

function EventService:Init(services)
	self.Services = services
end

function EventService:Start()
	nextAutoAt = os.time() + EVENTS.AutoSchedule.Interval
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.time()
			for id, info in pairs(self.Active) do
				if now >= info.EndsAt then
					self:StopEvent(id, "expired")
				end
			end
			local auto = EVENTS.AutoSchedule
			if auto.Enabled and now >= nextAutoAt then
				nextAutoAt = now + auto.Interval
				if next(self.Active) == nil and #auto.Pool > 0 then
					local id = auto.Pool[math.random(1, #auto.Pool)]
					self:StartEvent(id, auto.Duration, "Automatic")
				end
			end
		end
	end)
end

function EventService:ActiveList(): { string }
	return activeList
end

function EventService:GetActive()
	local out = {}
	for id, info in pairs(self.Active) do
		out[id] = { EndsAt = info.EndsAt, StartedBy = info.StartedBy }
	end
	return out
end

-- Starts (or extends) an event. Returns ok, message.
function EventService:StartEvent(id: string, duration: number, startedBy: string): (boolean, string)
	local def = EVENTS.Definitions[id]
	if not def then
		return false, "Unknown event."
	end
	local seconds = math.clamp(math.floor(duration), EVENTS.MinDuration, EVENTS.MaxDuration)
	local endsAt = os.time() + seconds
	self.Active[id] = { EndsAt = endsAt, StartedBy = startedBy }
	rebuildList()
	Remotes.serverState():SetAttribute("Event_" .. id, endsAt)
	self.Services.StatsService:InvalidateAll()
	self.Services.Net.notifyAll("Event", { Id = id, Started = true, EndsAt = endsAt })
	return true, `{def.Name} is active for {seconds} seconds.`
end

function EventService:StopEvent(id: string, _stoppedBy: string?): (boolean, string)
	if not self.Active[id] then
		return false, "That event is not running."
	end
	self.Active[id] = nil
	rebuildList()
	Remotes.serverState():SetAttribute("Event_" .. id, nil)
	self.Services.StatsService:InvalidateAll()
	self.Services.Net.notifyAll("Event", { Id = id, Started = false })
	return true, "Event stopped."
end

return EventService
