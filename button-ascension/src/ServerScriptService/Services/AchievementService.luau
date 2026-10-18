--[[
	AchievementService (ModuleScript)
	Location: ServerScriptService/Services/AchievementService
	Depends on: Shared/Config/Achievements, Shared/Formulas, EconomyService, SyncService, Net

	Unlocks achievements when tracked values reach their targets and grants
	their rewards. Services call MarkDirty(profile) after changing stats; a
	loop checks dirty profiles once per second, so bursts of clicks never
	cause repeated scans.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Achievements = require(Shared.Config.Achievements)
local Formulas = require(Shared.Formulas)

local AchievementService = { Name = "AchievementService" }

function AchievementService:Init(services)
	self.Services = services
end

function AchievementService:Start()
	task.spawn(function()
		while true do
			task.wait(1)
			for _, profile in pairs(self.Services.DataService.Profiles) do
				if profile.Runtime.AchievementsDirty then
					profile.Runtime.AchievementsDirty = false
					self:Check(profile)
				end
			end
		end
	end)
end

function AchievementService:OnProfileLoaded(profile)
	self:MarkDirty(profile)
end

function AchievementService:MarkDirty(profile)
	profile.Runtime.AchievementsDirty = true
end

function AchievementService:GetValue(profile, stat: string): number
	local data = profile.Data
	if stat == "Rebirths" then
		return data.Rebirths
	elseif stat == "Level" then
		return data.Level
	elseif stat == "ItemsDiscovered" then
		return Formulas.discoveredCount(data)
	elseif stat == "SkillRanks" then
		return Formulas.skillPointsSpent(data)
	end
	return data.Stats[stat] or 0
end

function AchievementService:Check(profile)
	local data = profile.Data
	local unlocked = false
	for _, def in ipairs(Achievements.List) do
		if not data.Achievements[def.Id] and self:GetValue(profile, def.Stat) >= def.Target then
			data.Achievements[def.Id] = os.time()
			unlocked = true
			local granted = self.Services.EconomyService:GrantReward(profile, def.Reward, "achievement")
			self.Services.Net.notify(profile.Player, "Achievement", { Id = def.Id, Reward = granted })
		end
	end
	if unlocked then
		self.Services.SyncService:MarkDirty(profile, "Achievements")
		-- Rewards can unlock further achievements (e.g. skill points); check again soon.
		self:MarkDirty(profile)
	end
end

return AchievementService
