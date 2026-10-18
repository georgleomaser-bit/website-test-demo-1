--[[
	ProgressionService (ModuleScript)
	Location: ServerScriptService/Services/ProgressionService
	Depends on: Shared/Config/{Skills,Ascension,Rewards,Items,GameConfig}, Shared/Formulas,
	            Shared/Util, Core/Net, Core/Guard, EconomyService, StatsService, SyncService,
	            QuestService, AchievementService, ClickService, DataService

	Long-term progression:
	  * Skill tree   UnlockSkill { Id }, ResetSkills {}
	  * Ascension    Rebirth {}, BuyAscension { Id }
	  * Collection   ClaimCollection { Id }
	  * Daily login  ClaimDaily {}

	What ascending (rebirth) RESETS:
	    Sparks (set to the Head Start amount), all Shop upgrade levels (Auto-Presser
	    is kept with the "Loyal Robots" perk), Sparks earned this run, current combo.
	What ascending KEEPS:
	    Gems, Prisms, Ascension perks, skill tree and Skill Points, level and XP,
	    inventory, equipped items, favourites, collection/discoveries, owned crates,
	    pity counters, achievements, quests, daily streak, statistics, settings.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Skills = require(Shared.Config.Skills)
local Ascension = require(Shared.Config.Ascension)
local Rewards = require(Shared.Config.Rewards)
local Items = require(Shared.Config.Items)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)
local Util = require(Shared.Util)
local Core = script.Parent.Parent.Core
local Net = require(Core.Net)
local Guard = require(Core.Guard)
local DataOps = require(Core.DataOps)

local ProgressionService = { Name = "ProgressionService" }

function ProgressionService:Init(services)
	self.Services = services
	Net.registerAction("UnlockSkill", {
		Rate = { Capacity = 10, Refill = 5 },
		Handler = function(profile, payload)
			return self:UnlockSkill(profile, payload.Id)
		end,
	})
	Net.registerAction("ResetSkills", {
		Rate = { Capacity = 2, Refill = 0.2 },
		Handler = function(profile)
			return self:ResetSkills(profile, false)
		end,
	})
	Net.registerAction("Rebirth", {
		Rate = { Capacity = 2, Refill = 0.2 },
		Handler = function(profile)
			return self:Rebirth(profile)
		end,
	})
	Net.registerAction("BuyAscension", {
		Rate = { Capacity = 10, Refill = 5 },
		Handler = function(profile, payload)
			return self:BuyAscension(profile, payload.Id)
		end,
	})
	Net.registerAction("ClaimCollection", {
		Rate = { Capacity = 5, Refill = 1 },
		Handler = function(profile, payload)
			return self:ClaimCollection(profile, payload.Id)
		end,
	})
	Net.registerAction("ClaimDaily", {
		Rate = { Capacity = 3, Refill = 0.5 },
		Handler = function(profile)
			return self:ClaimDaily(profile)
		end,
	})
end

-- Skills ------------------------------------------------------------------------

function ProgressionService:UnlockSkill(profile, rawId: any)
	local id = Guard.id(rawId, Skills.ById)
	if not id then
		return Net.fail("Unknown skill.")
	end
	local node = Skills.ById[id]
	local data = profile.Data
	local rank = data.Skills[id] or 0
	if rank >= node.MaxRank then
		return Net.fail("Skill already maxed.")
	end
	if not Skills.prerequisitesMet(node, data.Skills) then
		return Net.fail("Unlock a connected skill first.")
	end
	local cost = Skills.costFor(node, rank)
	if data.SkillPoints < cost then
		return Net.fail(`Not enough Skill Points. Need {cost}.`)
	end
	data.SkillPoints -= cost
	data.Skills[id] = rank + 1
	self.Services.StatsService:Invalidate(profile)
	self.Services.SyncService:MarkDirty(profile, "Skills", "Progress")
	self.Services.QuestService:Refresh(profile)
	self.Services.AchievementService:MarkDirty(profile)
	return Net.ok({ Id = id, Rank = rank + 1 })
end

-- free = true is used by admin tools (no Gem cost).
function ProgressionService:ResetSkills(profile, free: boolean)
	local data = profile.Data
	local refund = Formulas.skillPointsSpent(data)
	if refund <= 0 then
		return Net.fail("No skills to reset.")
	end
	local cost = GameConfig.Skills.RespecGemCost
	if not free and not self.Services.EconomyService:Spend(profile, "Gems", cost) then
		return Net.fail(`Resetting skills costs {cost} Gems.`)
	end
	table.clear(data.Skills)
	data.SkillPoints += refund
	self.Services.StatsService:Invalidate(profile)
	self.Services.SyncService:MarkDirty(profile, "Skills", "Progress", "Equipped")
	return Net.ok({ Refunded = refund })
end

-- Ascension ------------------------------------------------------------------------

function ProgressionService:PreviewRebirth(profile)
	local data = profile.Data
	local stats = self.Services.StatsService:Get(profile)
	local requirement = Formulas.rebirthRequirement(data.Rebirths)
	return {
		Requirement = requirement,
		Progress = data.Stats.SparksThisRun,
		Prisms = Formulas.rebirthPrisms(data.Stats.SparksThisRun, data.Rebirths, stats.prismMultiplier),
	}
end

--[[
	Applies an ascension. force = true (admin) skips the requirement and
	grants the given number of prisms instead of the computed amount.
]]
function ProgressionService:ApplyRebirth(profile, prisms: number)
	local data = profile.Data
	local stageBefore = Formulas.stageFor(data.Rebirths).Id
	local stats = self.Services.StatsService:Get(profile)

	local keptAuto = if stats.keepAuto then data.Upgrades.auto_presser else nil
	table.clear(data.Upgrades)
	if keptAuto then
		data.Upgrades.auto_presser = keptAuto
	end
	DataOps.setCurrency(data, "Sparks", 0)
	data.Stats.SparksThisRun = 0
	data.Rebirths += 1
	if prisms > 0 then
		self.Services.EconomyService:Add(profile, "Prisms", prisms, "rebirth")
	end
	self.Services.ClickService:ResetCombo(profile)
	self.Services.StatsService:Invalidate(profile)

	-- Head Start: computed after the reset so it reflects the perk level.
	local fresh = self.Services.StatsService:Get(profile)
	if fresh.startSparks > 0 then
		DataOps.setCurrency(data, "Sparks", fresh.startSparks)
	end

	self.Services.SyncService:MarkDirty(profile, "Currencies", "Upgrades", "Stats", "Progress")
	self.Services.QuestService:Refresh(profile)
	self.Services.AchievementService:MarkDirty(profile)

	local stageAfter = Formulas.stageFor(data.Rebirths).Id
	if stageAfter > stageBefore then
		self.Services.Net.notify(profile.Player, "Stage", { Stage = stageAfter })
	end
	task.spawn(function()
		self.Services.DataService:SaveNow(profile)
	end)
	return stageAfter
end

function ProgressionService:Rebirth(profile)
	local preview = self:PreviewRebirth(profile)
	if preview.Progress < preview.Requirement then
		return Net.fail(`Earn {Format.short(preview.Requirement)} Sparks this run to ascend.`)
	end
	local stage = self:ApplyRebirth(profile, preview.Prisms)
	return Net.ok({ Prisms = preview.Prisms, Rebirths = profile.Data.Rebirths, Stage = stage })
end

function ProgressionService:BuyAscension(profile, rawId: any)
	local id = Guard.id(rawId, Ascension.ById)
	if not id then
		return Net.fail("Unknown perk.")
	end
	local def = Ascension.ById[id]
	local data = profile.Data
	local level = data.Ascension[id] or 0
	if level >= def.MaxLevel then
		return Net.fail("Already at max level.")
	end
	local cost = Formulas.ascensionCost(def, level)
	if not self.Services.EconomyService:Spend(profile, "Prisms", cost) then
		return Net.fail(`Not enough Prisms. Need {Format.short(cost)}.`)
	end
	data.Ascension[id] = level + 1
	self.Services.StatsService:Invalidate(profile)
	self.Services.SyncService:MarkDirty(profile, "Ascension")
	return Net.ok({ Id = id, Level = level + 1, Cost = cost })
end

-- Collection book -------------------------------------------------------------------

function ProgressionService:ClaimCollection(profile, rawId: any)
	local id = Guard.id(rawId, Rewards.CollectionById)
	if not id then
		return Net.fail("Unknown milestone.")
	end
	local data = profile.Data
	if data.CollectionClaimed[id] then
		return Net.fail("Already claimed.")
	end
	local milestone = Rewards.CollectionById[id]
	local need = if milestone.Count < 0 then Items.Count else milestone.Count
	if Formulas.discoveredCount(data) < need then
		return Net.fail(`Discover {need} items to claim this.`)
	end
	data.CollectionClaimed[id] = true
	local granted = self.Services.EconomyService:GrantReward(profile, milestone.Reward, "collection")
	self.Services.SyncService:MarkDirty(profile, "CollectionClaimed")
	return Net.ok({ Reward = granted })
end

-- Daily login rewards ------------------------------------------------------------------

function ProgressionService:ClaimDaily(profile)
	local data = profile.Data
	local today = Util.dayNumber(os.time())
	local daily = data.Daily
	if daily.LastClaimDay == today then
		return Net.fail(`Come back in {Format.time(Util.secondsUntilNextDay(os.time()))}.`)
	end
	if daily.LastClaimDay == today - 1 then
		daily.Streak += 1
	else
		daily.Streak = 1
	end
	daily.LastClaimDay = today
	if daily.Streak > data.Stats.BestDailyStreak then
		data.Stats.BestDailyStreak = daily.Streak
	end
	local entry = Rewards.Daily[((daily.Streak - 1) % #Rewards.Daily) + 1]
	local granted = self.Services.EconomyService:GrantReward(profile, entry.Reward, "daily")
	self.Services.SyncService:MarkDirty(profile, "Daily", "Stats")
	return Net.ok({ Day = entry.Day, Streak = daily.Streak, Reward = granted })
end

return ProgressionService
