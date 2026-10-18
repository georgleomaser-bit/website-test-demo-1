--[[
	UpgradeService (ModuleScript)
	Location: ServerScriptService/Services/UpgradeService
	Depends on: Shared/Config/Upgrades, Shared/Formulas, Core/Net, Core/Guard,
	            EconomyService, StatsService, SyncService, QuestService, AchievementService

	Shop upgrades bought with Sparks. Prices, requirements and maximum levels
	come from config; the client only sends which upgrade and how many.

	Action: BuyUpgrade { Id: string, Amount: 1 | 10 | "max" }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Upgrades = require(Shared.Config.Upgrades)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)
local Core = script.Parent.Parent.Core
local Net = require(Core.Net)
local Guard = require(Core.Guard)

local UpgradeService = { Name = "UpgradeService" }

function UpgradeService:Init(services)
	self.Services = services
	Net.registerAction("BuyUpgrade", {
		Rate = { Capacity = 15, Refill = 8 },
		Handler = function(profile, payload)
			return self:Buy(profile, payload.Id, payload.Amount)
		end,
	})
end

function UpgradeService:Buy(profile, rawId: any, rawAmount: any)
	local id = Guard.id(rawId, Upgrades.ById)
	if not id then
		return Net.fail("Unknown upgrade.")
	end
	local amount = if rawAmount == "max" then "max" else Guard.oneOf(rawAmount, { 1, 10 })
	if amount == nil then
		return Net.fail("Invalid amount.")
	end
	local def = Upgrades.ById[id]
	local data = profile.Data
	if not Formulas.upgradeUnlocked(def, data) then
		return Net.fail(Formulas.requirementText(Upgrades.Tiers[def.Tier].Requirement) .. ".")
	end
	local level = data.Upgrades[id] or 0
	if level >= def.MaxLevel then
		return Net.fail("Already at max level.")
	end

	local count, cost
	local balance = data.Currencies[def.Currency] or 0
	if amount == "max" then
		count, cost = Formulas.maxAffordable(def, level, balance)
		if count == 0 then
			return Net.fail(`Not enough {def.Currency}. Need {Format.short(Formulas.upgradeLevelCost(def, level))}.`)
		end
	else
		count = math.min(amount, def.MaxLevel - level)
		cost = Formulas.upgradeCost(def, level, count)
	end

	if not self.Services.EconomyService:Spend(profile, def.Currency, cost) then
		return Net.fail(`Not enough {def.Currency}. Need {Format.short(cost)}.`)
	end

	data.Upgrades[id] = level + count
	data.Stats.UpgradesPurchased += count
	self.Services.StatsService:Invalidate(profile)
	self.Services.SyncService:MarkDirty(profile, "Upgrades", "Stats")
	self.Services.QuestService:Progress(profile, "UpgradesBought", count)
	self.Services.AchievementService:MarkDirty(profile)
	return Net.ok({ Id = id, Level = level + count, Count = count, Cost = cost })
end

return UpgradeService
