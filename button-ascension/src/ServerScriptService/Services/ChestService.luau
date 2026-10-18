--[[
	ChestService (ModuleScript)
	Location: ServerScriptService/Services/ChestService
	Depends on: Shared/Loot, Shared/Formulas, Shared/Config/{Chests,Items,Rarities,GameConfig},
	            Core/DataOps, Core/Net, Core/Guard, EconomyService, StatsService, SyncService,
	            QuestService, AchievementService

	Crate purchasing and opening. Prices, odds, luck, pity and the item pool
	are all evaluated here with a server-side Random; the client only sends
	which crate, how many, and whether to use owned crates or buy them.
	Results are applied to the player's data BEFORE they are returned, so the
	opening animation on the client is purely cosmetic.

	Action: OpenChest { Id: string, Amount: integer 1..MaxOpen, Mode: "owned" | "buy" }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Chests = require(Shared.Config.Chests)
local Items = require(Shared.Config.Items)
local GameConfig = require(Shared.Config.GameConfig)
local Loot = require(Shared.Loot)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)
local Core = script.Parent.Parent.Core
local DataOps = require(Core.DataOps)
local Net = require(Core.Net)
local Guard = require(Core.Guard)

local ChestService = { Name = "ChestService" }

local rng = Random.new()

function ChestService:Init(services)
	self.Services = services
	Net.registerAction("OpenChest", {
		Rate = { Capacity = 6, Refill = 2 },
		Handler = function(profile, payload)
			return self:Open(profile, payload.Id, payload.Amount, payload.Mode)
		end,
	})
end

function ChestService:PityThresholds(chest, stats)
	local thresholds = {}
	for rarityId in pairs(chest.Pity or {}) do
		thresholds[rarityId] = Formulas.pityThreshold(chest, rarityId, stats.pityMultiplier)
	end
	return thresholds
end

--[[
	Adds one item to the player and returns the result entry.
	flags: { Pity = bool?, Bonus = bool?, Test = bool? }
]]
function ChestService:Award(profile, itemId: string, flags)
	local data = profile.Data
	local item = Items.ById[itemId]
	local isNew = DataOps.addItem(data, itemId, 1)
	local stats = data.Stats
	if item.RarityIndex >= 5 then
		stats.LegendariesFound += 1
	end
	if item.RarityIndex >= 6 then
		stats.MythicsFound += 1
	end
	if item.RarityIndex >= 7 then
		stats.SecretsFound += 1
	end

	local result = {
		Item = itemId,
		Rarity = item.Rarity,
		New = isNew,
		Pity = flags.Pity == true or nil,
		Bonus = flags.Bonus == true or nil,
		Test = flags.Test == true or nil,
	}

	local autoSell = data.Settings.AutoSell or 0
	if not isNew
		and not flags.Test
		and autoSell > 0
		and item.RarityIndex <= math.min(autoSell, GameConfig.Inventory.AutoSellMaxIndex)
		and not data.Favorites[itemId]
	then
		DataOps.removeItem(data, itemId, 1)
		local playerStats = self.Services.StatsService:Get(profile)
		local gems = Formulas.sellValue(item, 1, playerStats.gemMultiplier)
		self.Services.EconomyService:Add(profile, "Gems", gems, "autosell")
		stats.ItemsSold += 1
		self.Services.QuestService:Progress(profile, "ItemsSold", 1)
		result.AutoSold = gems
	end

	result.Count = data.Inventory[itemId] or 0
	if isNew then
		self.Services.Net.notify(profile.Player, "Discovery", { Item = itemId })
	end
	if item.RarityIndex >= 6 and not flags.Test then
		self.Services.Net.notifyAll("Rare", { Player = profile.Player.DisplayName, Item = itemId })
	end
	return result
end

function ChestService:_afterAward(profile)
	self.Services.StatsService:Invalidate(profile)
	self.Services.SyncService:MarkDirty(profile, "Inventory", "Discovered", "Chests", "Pity", "Stats", "Equipped", "Favorites")
	self.Services.AchievementService:MarkDirty(profile)
end

function ChestService:RollMany(profile, chest, amount: number)
	local data = profile.Data
	local stats = self.Services.StatsService:Get(profile)
	local pity = data.Pity[chest.Id]
	if not pity then
		pity = {}
		data.Pity[chest.Id] = pity
	end
	local thresholds = self:PityThresholds(chest, stats)
	local results = {}
	for _ = 1, amount do
		local itemId, _, pityTriggered = Loot.roll(rng, chest, stats.luck, pity, thresholds)
		if itemId then
			table.insert(results, self:Award(profile, itemId, { Pity = pityTriggered }))
		end
		local bonusChance = Formulas.chestBonusChance(chest, stats.chestBonus)
		if bonusChance > 0 and rng:NextNumber() < bonusChance then
			-- Bonus drops use the same odds but never advance or consume pity.
			local bonusId = Loot.roll(rng, chest, stats.luck, {}, {})
			if bonusId then
				table.insert(results, self:Award(profile, bonusId, { Bonus = true }))
			end
		end
	end
	return results
end

function ChestService:Open(profile, rawId: any, rawAmount: any, rawMode: any)
	local chestId = Guard.id(rawId, Chests.ById)
	if not chestId then
		return Net.fail("Unknown crate.")
	end
	local chest = Chests.ById[chestId]
	local amount = Guard.integer(rawAmount, 1, chest.MaxOpen)
	if not amount then
		return Net.fail("Invalid amount.")
	end
	local mode = Guard.oneOf(rawMode, { "owned", "buy" })
	if not mode then
		return Net.fail("Invalid request.")
	end
	local data = profile.Data
	if not Formulas.chestUnlocked(chest, data) then
		local stage = GameConfig.Stages[chest.Stage]
		return Net.fail(`Unlocks at {stage.Name} ({stage.Rebirths} Ascensions).`)
	end

	local stats = self.Services.StatsService:Get(profile)
	local spent = 0
	if mode == "owned" then
		if (data.Chests[chestId] or 0) < amount then
			return Net.fail("You don't have enough of those crates.")
		end
		DataOps.removeChest(data, chestId, amount)
	else
		local price = Formulas.chestPrice(chest, stats.chestDiscount) * amount
		if not self.Services.EconomyService:Spend(profile, chest.Currency, price) then
			return Net.fail(`Not enough {chest.Currency}. Need {Format.short(price)}.`)
		end
		spent = price
	end

	local results = self:RollMany(profile, chest, amount)
	data.Stats.ChestsOpened += amount
	self.Services.EconomyService:AddXP(profile, GameConfig.Levels.ChestXP * chest.Tier * amount * stats.xpMultiplier)
	self.Services.QuestService:Progress(profile, "ChestsOpened", amount)
	self:_afterAward(profile)
	return Net.ok({ Chest = chestId, Mode = mode, Spent = spent, Results = results })
end

-- Admin testing helpers -------------------------------------------------------------

-- Grants one item of an exact rarity from a crate's pool (does not touch pity).
function ChestService:GrantForcedRarity(profile, chestId: string, rarityId: string)
	local chest = Chests.ById[chestId]
	if not chest then
		return nil, "Unknown crate."
	end
	local itemId = Loot.rollForcedRarity(rng, chest, rarityId)
	if not itemId then
		return nil, `{chest.Name} has no {rarityId} items.`
	end
	local result = self:Award(profile, itemId, { Test = true })
	self:_afterAward(profile)
	return result
end

-- Simulates openings with production odds and a private pity state.
function ChestService:Simulate(chestId: string, count: number, luck: number, withPity: boolean)
	local chest = Chests.ById[chestId]
	local thresholds = {}
	if withPity then
		for rarityId in pairs(chest.Pity or {}) do
			thresholds[rarityId] = Formulas.pityThreshold(chest, rarityId, 1)
		end
	end
	return Loot.simulate(Random.new(), chest, luck, count, thresholds)
end

return ChestService
