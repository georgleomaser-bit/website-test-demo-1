--[[
	QuestService (ModuleScript)
	Location: ServerScriptService/Services/QuestService
	Depends on: Shared/Config/Quests, Shared/Formulas, Shared/Util, EconomyService,
	            StatsService, SyncService, AchievementService, Net

	Daily quests (new set every UTC day, deterministic per player) and the
	Starter Path tutorial chain. Progress is reported by gameplay services via
	Progress(profile, kind, amount); rewards are claimed through actions and
	validated here.

	Actions: ClaimQuest { Index }, ClaimQuestBonus {}, ClaimStarter {}
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Quests = require(Shared.Config.Quests)
local Formulas = require(Shared.Formulas)
local Util = require(Shared.Util)
local Core = script.Parent.Parent.Core
local Net = require(Core.Net)
local Guard = require(Core.Guard)

local QuestService = { Name = "QuestService" }

-- Current values for starter-path "check" kinds.
local STARTER_CHECKS = {
	ReachLevel = function(data)
		return data.Level
	end,
	RunSparks = function(data)
		return data.Stats.SparksThisRun
	end,
	Equip = function(data)
		return #data.Equipped
	end,
	SkillUnlocked = function(data)
		return Formulas.skillRanks(data)
	end,
	Rebirth = function(data)
		return data.Rebirths
	end,
}

function QuestService:Init(services)
	self.Services = services

	Net.registerAction("ClaimQuest", {
		Rate = { Capacity = 6, Refill = 2 },
		Handler = function(profile, payload)
			return self:_claimDaily(profile, payload)
		end,
	})
	Net.registerAction("ClaimQuestBonus", {
		Rate = { Capacity = 3, Refill = 1 },
		Handler = function(profile)
			return self:_claimBonus(profile)
		end,
	})
	Net.registerAction("ClaimStarter", {
		Rate = { Capacity = 4, Refill = 1 },
		Handler = function(profile)
			return self:_claimStarter(profile)
		end,
	})
end

function QuestService:Start()
	task.spawn(function()
		local elapsed = 0
		while true do
			task.wait(5)
			elapsed += 5
			for _, profile in pairs(self.Services.DataService.Profiles) do
				self:EnsureDaily(profile)
				self:Refresh(profile)
				local rt = profile.Runtime
				rt.QuestPlaySeconds = (rt.QuestPlaySeconds or 0) + 5
				if rt.QuestPlaySeconds >= 60 then
					rt.QuestPlaySeconds -= 60
					self:Progress(profile, "PlayMinutes", 1)
				end
			end
		end
	end)
end

function QuestService:OnProfileLoaded(profile)
	self:EnsureDaily(profile)
	self:Refresh(profile)
end

-- Generates today's quests if the stored set is from another day.
function QuestService:EnsureDaily(profile)
	local data = profile.Data
	local day = Util.dayNumber(os.time())
	if data.Quests.Day == day and #data.Quests.Daily > 0 then
		return
	end
	local rng = Random.new(profile.UserId * 1000003 + day)
	local pool = table.clone(Quests.Daily)
	local stats = self.Services.StatsService:Get(profile)
	local list = {}
	for _ = 1, math.min(Quests.DailyCount, #pool) do
		local index = rng:NextInteger(1, #pool)
		local template = table.remove(pool, index)
		table.insert(list, {
			Id = template.Id,
			Target = Formulas.questTarget(template, data.Rebirths, stats.clickValue),
			Progress = 0,
			Claimed = false,
		})
	end
	data.Quests.Day = day
	data.Quests.Daily = list
	data.Quests.BonusClaimed = false
	self.Services.SyncService:MarkDirty(profile, "Quests")
end

function QuestService:Progress(profile, kind: string, amount: number)
	local data = profile.Data
	local changed = false
	local isMax = Quests.MaxKinds[kind] == true

	for _, q in ipairs(data.Quests.Daily) do
		local def = Quests.DailyById[q.Id]
		if def and def.Kind == kind and not q.Claimed and q.Progress < q.Target then
			local value = if isMax then math.max(q.Progress, amount) else q.Progress + amount
			q.Progress = math.min(q.Target, value)
			changed = true
		end
	end

	local step = Quests.Starter[data.Quests.StarterIndex]
	if step and step.Kind == kind and not Quests.CheckKinds[kind] and data.Quests.StarterProgress < step.Target then
		local value = if isMax then math.max(data.Quests.StarterProgress, amount) else data.Quests.StarterProgress + amount
		data.Quests.StarterProgress = math.min(step.Target, value)
		changed = true
	end

	if changed then
		self.Services.SyncService:MarkDirty(profile, "Quests")
	end
end

-- Re-evaluates check-based starter steps.
function QuestService:Refresh(profile)
	local data = profile.Data
	local step = Quests.Starter[data.Quests.StarterIndex]
	if not step then
		return
	end
	local check = STARTER_CHECKS[step.Kind]
	if check then
		local value = math.min(step.Target, check(data))
		if value ~= data.Quests.StarterProgress then
			data.Quests.StarterProgress = value
			self.Services.SyncService:MarkDirty(profile, "Quests")
		end
	end
end

function QuestService:_claimDaily(profile, payload)
	local index = Guard.integer(payload.Index, 1, Quests.DailyCount)
	if not index then
		return Net.fail("Invalid quest.")
	end
	self:EnsureDaily(profile)
	local data = profile.Data
	local q = data.Quests.Daily[index]
	if not q then
		return Net.fail("Invalid quest.")
	end
	if q.Claimed then
		return Net.fail("Already claimed.")
	end
	if q.Progress < q.Target then
		return Net.fail("Quest not complete yet.")
	end
	local def = Quests.DailyById[q.Id]
	q.Claimed = true
	data.Stats.QuestsCompleted += 1
	local granted = self.Services.EconomyService:GrantReward(profile, def.Reward, "quest")
	self.Services.SyncService:MarkDirty(profile, "Quests", "Stats")
	self.Services.AchievementService:MarkDirty(profile)
	return Net.ok({ Reward = granted })
end

function QuestService:_claimBonus(profile)
	local data = profile.Data
	if data.Quests.BonusClaimed then
		return Net.fail("Bonus already claimed today.")
	end
	if #data.Quests.Daily == 0 then
		return Net.fail("No quests today.")
	end
	for _, q in ipairs(data.Quests.Daily) do
		if not q.Claimed then
			return Net.fail("Claim every daily quest first.")
		end
	end
	data.Quests.BonusClaimed = true
	local granted = self.Services.EconomyService:GrantReward(profile, Quests.DailyBonus, "quest")
	self.Services.SyncService:MarkDirty(profile, "Quests")
	return Net.ok({ Reward = granted })
end

function QuestService:_claimStarter(profile)
	local data = profile.Data
	self:Refresh(profile)
	local step = Quests.Starter[data.Quests.StarterIndex]
	if not step then
		return Net.fail("Starter path complete.")
	end
	if data.Quests.StarterProgress < step.Target then
		return Net.fail("Step not complete yet.")
	end
	data.Quests.StarterIndex += 1
	data.Quests.StarterProgress = 0
	local granted = self.Services.EconomyService:GrantReward(profile, step.Reward, "quest")
	self:Refresh(profile)
	self.Services.SyncService:MarkDirty(profile, "Quests")
	return Net.ok({ Reward = granted })
end

return QuestService
