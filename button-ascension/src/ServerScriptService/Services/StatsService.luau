--[[
	StatsService (ModuleScript)
	Location: ServerScriptService/Services/StatsService
	Depends on: Shared/Formulas, DataService, SyncService, EventService

	Caches each player's computed Stats (see Shared/Formulas.computeStats) and
	recomputes them only when something relevant changes (Invalidate). Also
	owns personal timed boosts ("Frenzy") from golden presses and orbs.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared.Formulas)
local DataOps = require(script.Parent.Parent.Core.DataOps)

local StatsService = { Name = "StatsService" }

function StatsService:Init(services)
	self.Services = services
end

function StatsService:Start()
	task.spawn(function()
		while true do
			task.wait(0.5)
			local now = workspace:GetServerTimeNow()
			for _, profile in pairs(self.Services.DataService.Profiles) do
				local rt = profile.Runtime
				if rt.FrenzyEndsAt and now >= rt.FrenzyEndsAt then
					rt.FrenzyEndsAt = nil
					rt.FrenzyMultiplier = nil
					self:Invalidate(profile)
				end
			end
		end
	end)
end

function StatsService:Context(profile)
	local rt = profile.Runtime
	return {
		Events = self.Services.EventService:ActiveList(),
		FrenzyMultiplier = rt.FrenzyMultiplier,
	}
end

function StatsService:Get(profile): Formulas.Stats
	if profile.Stats == nil or profile.StatsDirty then
		profile.Stats = Formulas.computeStats(profile.Data, self:Context(profile))
		profile.StatsDirty = false
		-- Losing slots (e.g. after a respec) must never leave extra items equipped.
		if #profile.Data.Equipped > profile.Stats.equipSlots then
			DataOps.trimEquipped(profile.Data, profile.Stats.equipSlots)
			self.Services.SyncService:MarkDirty(profile, "Equipped")
			profile.Stats = Formulas.computeStats(profile.Data, self:Context(profile))
		end
	end
	return profile.Stats
end

-- Stats without temporary boosts (used for offline earnings).
function StatsService:GetBase(profile): Formulas.Stats
	return Formulas.computeStats(profile.Data, { Events = {} })
end

function StatsService:Invalidate(profile)
	profile.StatsDirty = true
	self.Services.SyncService:MarkDirty(profile, "Derived")
end

function StatsService:InvalidateAll()
	for _, profile in pairs(self.Services.DataService.Profiles) do
		self:Invalidate(profile)
	end
end

function StatsService:StartFrenzy(profile, multiplier: number, duration: number)
	local rt = profile.Runtime
	local now = workspace:GetServerTimeNow()
	local current = rt.FrenzyEndsAt or now
	-- Stacking extends the duration; the multiplier keeps the strongest value.
	rt.FrenzyEndsAt = math.max(current, now) + duration
	rt.FrenzyMultiplier = math.max(rt.FrenzyMultiplier or 1, multiplier)
	self:Invalidate(profile)
end

function StatsService:BuildDerived(profile)
	local stats = self:Get(profile)
	local data = profile.Data
	local rt = profile.Runtime
	return {
		Stats = stats,
		RebirthRequirement = Formulas.rebirthRequirement(data.Rebirths),
		FrenzyEndsAt = rt.FrenzyEndsAt,
		FrenzyMultiplier = rt.FrenzyMultiplier,
		Persistent = not profile.Temporary,
	}
end

function StatsService:OnProfileLoaded(profile)
	self:Get(profile)
end

return StatsService
