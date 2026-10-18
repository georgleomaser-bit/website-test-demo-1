--[[
	SyncService (ModuleScript)
	Location: ServerScriptService/Services/SyncService
	Depends on: Shared/Remotes, StatsService

	Replicates a player's OWN data to their client. Services mark sections
	dirty; a loop sends only the dirty sections as a patch every
	GameConfig.Sync.Interval seconds. The client never sends data back — it
	only reads this mirror to render the UI.

	Sections: every key in DataSchema.Sections plus "Progress" (level, XP,
	skill points, ascensions) and "Derived" (computed stats).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Formulas = require(Shared.Formulas)
local DataSchema = require(script.Parent.Parent.Core.DataSchema)

local SyncService = { Name = "SyncService" }

local ALL_SECTIONS = table.clone(DataSchema.Sections)
table.insert(ALL_SECTIONS, "Derived")

function SyncService:Init(services)
	self.Services = services
end

function SyncService:Start()
	task.spawn(function()
		while true do
			task.wait(GameConfig.Sync.Interval)
			for _, profile in pairs(self.Services.DataService.Profiles) do
				if next(profile.Dirty) ~= nil then
					self:_flush(profile)
				end
			end
		end
	end)
end

function SyncService:MarkDirty(profile, ...: string)
	for i = 1, select("#", ...) do
		profile.Dirty[select(i, ...)] = true
	end
end

function SyncService:BuildSection(profile, name: string)
	local data = profile.Data
	if name == "Progress" then
		return {
			Level = data.Level,
			XP = data.XP,
			SkillPoints = data.SkillPoints,
			Rebirths = data.Rebirths,
			XPRequired = Formulas.xpForLevel(data.Level),
		}
	elseif name == "Derived" then
		return self.Services.StatsService:BuildDerived(profile)
	end
	return data[name]
end

function SyncService:_flush(profile)
	local patch = {}
	for name in pairs(profile.Dirty) do
		patch[name] = self:BuildSection(profile, name)
	end
	table.clear(profile.Dirty)
	self.Services.Net.fire(profile.Player, "StateSync", "patch", patch)
end

function SyncService:SendFull(profile)
	local snapshot = {}
	for _, name in ipairs(ALL_SECTIONS) do
		snapshot[name] = self:BuildSection(profile, name)
	end
	table.clear(profile.Dirty)
	self.Services.Net.fire(profile.Player, "StateSync", "full", snapshot)
end

return SyncService
