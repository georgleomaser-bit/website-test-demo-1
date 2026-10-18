--[[
	EconomyService (ModuleScript)
	Location: ServerScriptService/Services/EconomyService
	Depends on: Core/DataOps, Shared/Formulas, Shared/Config/*, StatsService, SyncService,
	            QuestService, AchievementService, Net

	The only place currencies, XP and generic rewards are granted or spent.
	All amounts are computed server-side; nothing here accepts client values.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Chests = require(Shared.Config.Chests)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)
local DataOps = require(script.Parent.Parent.Core.DataOps)

local EconomyService = { Name = "EconomyService" }

local function finitePositive(v: any): boolean
	return type(v) == "number" and v == v and v > 0 and v ~= math.huge
end

function EconomyService:Init(services)
	self.Services = services
end

-- Sparks earned through gameplay (counts toward lifetime and run totals).
function EconomyService:AddSparks(profile, amount: number, _source: string?)
	if not finitePositive(amount) then
		return
	end
	local data = profile.Data
	DataOps.addCurrency(data, "Sparks", amount)
	local stats = data.Stats
	stats.LifetimeSparks = math.min(GameConfig.CurrencyCap, stats.LifetimeSparks + amount)
	stats.SparksThisRun = math.min(GameConfig.CurrencyCap, stats.SparksThisRun + amount)
	if stats.SparksThisRun > stats.BestRunSparks then
		stats.BestRunSparks = stats.SparksThisRun
	end
	self.Services.QuestService:Progress(profile, "SparksEarned", amount)
	self.Services.SyncService:MarkDirty(profile, "Currencies", "Stats")
	self.Services.AchievementService:MarkDirty(profile)
end

-- Gems or Prisms earned through gameplay. Callers apply multipliers.
function EconomyService:Add(profile, currency: string, amount: number, _source: string?)
	if currency == "Sparks" then
		self:AddSparks(profile, amount, _source)
		return
	end
	if not finitePositive(amount) then
		return
	end
	local data = profile.Data
	DataOps.addCurrency(data, currency, amount)
	if currency == "Gems" then
		data.Stats.GemsEarned += amount
	elseif currency == "Prisms" then
		data.Stats.PrismsEarned += amount
	end
	self.Services.SyncService:MarkDirty(profile, "Currencies", "Stats")
end

function EconomyService:Has(profile, currency: string, amount: number): boolean
	return (profile.Data.Currencies[currency] or 0) >= amount
end

-- Spends currency if affordable. Returns true on success.
function EconomyService:Spend(profile, currency: string, amount: number): boolean
	if type(amount) ~= "number" or amount ~= amount or amount < 0 or amount == math.huge then
		return false
	end
	if not self:Has(profile, currency, amount) then
		return false
	end
	DataOps.addCurrency(profile.Data, currency, -amount)
	self.Services.SyncService:MarkDirty(profile, "Currencies")
	return true
end

-- XP and levels ----------------------------------------------------------------

function EconomyService:AddXP(profile, amount: number)
	if not finitePositive(amount) then
		return
	end
	local data = profile.Data
	local maxLevel = GameConfig.Levels.MaxLevel
	data.XP = math.min(GameConfig.CurrencyCap, data.XP + amount)
	local levelsGained = 0
	local spGained = 0
	local chestsGained = {}
	local guard = 0
	while data.Level < maxLevel and guard < 200 do
		local need = Formulas.xpForLevel(data.Level)
		if data.XP < need then
			break
		end
		guard += 1
		data.XP -= need
		data.Level += 1
		levelsGained += 1
		local sp = Formulas.skillPointsForLevel(data.Level)
		data.SkillPoints += sp
		spGained += sp
		if data.Level % GameConfig.Levels.ChestEvery == 0 then
			local stage = Formulas.stageFor(data.Rebirths).Id
			local chestId = Chests.bestSparksChestForStage(stage)
			DataOps.addChest(data, chestId, 1)
			chestsGained[chestId] = (chestsGained[chestId] or 0) + 1
		end
	end
	if data.Level >= maxLevel then
		data.XP = 0
	end
	self.Services.SyncService:MarkDirty(profile, "Progress")
	if levelsGained > 0 then
		self.Services.SyncService:MarkDirty(profile, "Chests")
		self.Services.Net.notify(profile.Player, "LevelUp", {
			Level = data.Level,
			SkillPoints = spGained,
			Chests = chestsGained,
		})
		self.Services.AchievementService:MarkDirty(profile)
		self.Services.QuestService:Refresh(profile)
	end
end

-- Generic rewards ---------------------------------------------------------------------

function EconomyService:DescribeReward(reward): string
	local parts = {}
	if reward.Sparks then
		table.insert(parts, Format.short(reward.Sparks) .. " Sparks")
	end
	if reward.Gems then
		table.insert(parts, Format.short(reward.Gems) .. " Gems")
	end
	if reward.Prisms then
		table.insert(parts, Format.short(reward.Prisms) .. " Prisms")
	end
	if reward.SkillPoints then
		table.insert(parts, reward.SkillPoints .. " Skill Point" .. (if reward.SkillPoints == 1 then "" else "s"))
	end
	if reward.Chests then
		for _, chestId in ipairs(Chests.Order) do
			local n = reward.Chests[chestId]
			if n then
				table.insert(parts, n .. "× " .. Chests.ById[chestId].Name)
			end
		end
	end
	if reward.XP then
		table.insert(parts, Format.short(reward.XP) .. " XP")
	end
	return table.concat(parts, ", ")
end

--[[
	Grants a reward table { Sparks, Gems, Prisms, SkillPoints, Chests, XP }.
	Gem rewards from gameplay are multiplied by the player's gem multiplier.
	Returns the reward actually granted (after multipliers).
]]
function EconomyService:GrantReward(profile, reward, source: string?)
	local data = profile.Data
	local granted = {}
	local applyMultipliers = source ~= "admin"
	local stats = self.Services.StatsService:Get(profile)

	if reward.Sparks and reward.Sparks > 0 then
		self:AddSparks(profile, reward.Sparks, source)
		granted.Sparks = reward.Sparks
	end
	if reward.Gems and reward.Gems > 0 then
		local gems = if applyMultipliers then math.floor(reward.Gems * stats.gemMultiplier) else reward.Gems
		self:Add(profile, "Gems", gems, source)
		granted.Gems = gems
	end
	if reward.Prisms and reward.Prisms > 0 then
		self:Add(profile, "Prisms", reward.Prisms, source)
		granted.Prisms = reward.Prisms
	end
	if reward.SkillPoints and reward.SkillPoints > 0 then
		data.SkillPoints += math.floor(reward.SkillPoints)
		granted.SkillPoints = math.floor(reward.SkillPoints)
		self.Services.SyncService:MarkDirty(profile, "Progress")
	end
	if reward.Chests then
		granted.Chests = {}
		for chestId, count in pairs(reward.Chests) do
			if Chests.ById[chestId] and count >= 1 then
				DataOps.addChest(data, chestId, math.floor(count))
				granted.Chests[chestId] = math.floor(count)
			end
		end
		self.Services.SyncService:MarkDirty(profile, "Chests")
	end
	if reward.XP and reward.XP > 0 then
		self:AddXP(profile, reward.XP)
		granted.XP = reward.XP
	end
	return granted
end

return EconomyService
