--[[
	InventoryService (ModuleScript)
	Location: ServerScriptService/Services/InventoryService
	Depends on: Shared/Config/{Items,GameConfig}, Shared/Formulas, Core/DataOps, Core/Net,
	            Core/Guard, EconomyService, StatsService, SyncService, QuestService

	Equip / unequip / favourite / sell. Items stack by id (inventory is a map
	itemId -> count), so even a huge collection is a small table and every
	operation is O(unique items).

	Actions:
	  Equip { Id }            Unequip { Id }        EquipBest {}
	  Favorite { Id, State }  Sell { Id, Amount }   SellDuplicates { MaxRarity }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Config.Items)
local GameConfig = require(Shared.Config.GameConfig)
local Formulas = require(Shared.Formulas)
local Core = script.Parent.Parent.Core
local DataOps = require(Core.DataOps)
local Net = require(Core.Net)
local Guard = require(Core.Guard)

local InventoryService = { Name = "InventoryService" }

-- Relative value of each stat when choosing "Equip Best".
local STAT_WEIGHT = {
	sparks = 1.2,
	click = 1.0,
	passive = 0.6,
	crit = 3.0,
	luck = 0.5,
	golden = 0.4,
	xp = 0.3,
	gems = 0.3,
}

function InventoryService:Init(services)
	self.Services = services
	local rate = { Capacity = 12, Refill = 6 }
	Net.registerAction("Equip", {
		Rate = rate,
		Handler = function(profile, payload)
			return self:Equip(profile, payload.Id)
		end,
	})
	Net.registerAction("Unequip", {
		Rate = rate,
		Handler = function(profile, payload)
			return self:Unequip(profile, payload.Id)
		end,
	})
	Net.registerAction("EquipBest", {
		Rate = { Capacity = 3, Refill = 1 },
		Handler = function(profile)
			return self:EquipBest(profile)
		end,
	})
	Net.registerAction("Favorite", {
		Rate = rate,
		Handler = function(profile, payload)
			return self:Favorite(profile, payload.Id, payload.State)
		end,
	})
	Net.registerAction("Sell", {
		Rate = rate,
		Handler = function(profile, payload)
			return self:Sell(profile, payload.Id, payload.Amount)
		end,
	})
	Net.registerAction("SellDuplicates", {
		Rate = { Capacity = 3, Refill = 1 },
		Handler = function(profile, payload)
			return self:SellDuplicates(profile, payload.MaxRarity)
		end,
	})
end

local function changed(self, profile, statsChanged: boolean)
	if statsChanged then
		self.Services.StatsService:Invalidate(profile)
	end
	self.Services.SyncService:MarkDirty(profile, "Inventory", "Equipped", "Favorites", "Currencies", "Stats")
end

local function isEquipped(data, itemId: string): boolean
	return table.find(data.Equipped, itemId) ~= nil
end

function InventoryService:Equip(profile, rawId: any)
	local id = Guard.id(rawId, Items.ById)
	local data = profile.Data
	if not id or (data.Inventory[id] or 0) < 1 then
		return Net.fail("You don't own that item.")
	end
	if isEquipped(data, id) then
		return Net.fail("Already equipped.")
	end
	local stats = self.Services.StatsService:Get(profile)
	if #data.Equipped >= stats.equipSlots then
		return Net.fail("All equip slots are full. Unequip something first.")
	end
	table.insert(data.Equipped, id)
	changed(self, profile, true)
	self.Services.QuestService:Refresh(profile)
	return Net.ok({ Equipped = data.Equipped })
end

function InventoryService:Unequip(profile, rawId: any)
	local id = Guard.id(rawId, Items.ById)
	local data = profile.Data
	local index = id and table.find(data.Equipped, id)
	if not index then
		return Net.fail("That item is not equipped.")
	end
	table.remove(data.Equipped, index)
	changed(self, profile, true)
	return Net.ok({ Equipped = data.Equipped })
end

function InventoryService:Score(itemId: string, count: number): number
	local item = Items.ById[itemId]
	return Formulas.itemPower(item, count) * (STAT_WEIGHT[item.Stat] or 0.5)
end

function InventoryService:EquipBest(profile)
	local data = profile.Data
	local stats = self.Services.StatsService:Get(profile)
	local owned = {}
	for id, count in pairs(data.Inventory) do
		if count > 0 and Items.ById[id] then
			table.insert(owned, { Id = id, Score = self:Score(id, count) })
		end
	end
	table.sort(owned, function(a, b)
		if a.Score == b.Score then
			return a.Id < b.Id
		end
		return a.Score > b.Score
	end)
	table.clear(data.Equipped)
	for i = 1, math.min(stats.equipSlots, #owned) do
		table.insert(data.Equipped, owned[i].Id)
	end
	changed(self, profile, true)
	self.Services.QuestService:Refresh(profile)
	return Net.ok({ Equipped = data.Equipped })
end

function InventoryService:Favorite(profile, rawId: any, rawState: any)
	local id = Guard.id(rawId, Items.ById)
	local state = Guard.boolean(rawState)
	local data = profile.Data
	if not id or state == nil or (data.Inventory[id] or 0) < 1 then
		return Net.fail("You don't own that item.")
	end
	data.Favorites[id] = if state then true else nil
	changed(self, profile, false)
	return Net.ok({ Id = id, State = state })
end

function InventoryService:_sell(profile, id: string, amount: number): number
	local data = profile.Data
	local item = Items.ById[id]
	local stats = self.Services.StatsService:Get(profile)
	local removed = DataOps.removeItem(data, id, amount)
	if removed <= 0 then
		return 0
	end
	local gems = Formulas.sellValue(item, removed, stats.gemMultiplier)
	self.Services.EconomyService:Add(profile, "Gems", gems, "sell")
	data.Stats.ItemsSold += removed
	self.Services.QuestService:Progress(profile, "ItemsSold", removed)
	return gems
end

function InventoryService:Sell(profile, rawId: any, rawAmount: any)
	local id = Guard.id(rawId, Items.ById)
	local data = profile.Data
	local owned = if id then data.Inventory[id] or 0 else 0
	if not id or owned < 1 then
		return Net.fail("You don't own that item.")
	end
	local amount = Guard.integer(rawAmount, 1, owned)
	if not amount then
		return Net.fail("Invalid amount.")
	end
	if data.Favorites[id] then
		return Net.fail("Unfavorite the item before selling it.")
	end
	local wasEquipped = isEquipped(data, id)
	local gems = self:_sell(profile, id, amount)
	changed(self, profile, wasEquipped)
	return Net.ok({ Id = id, Sold = amount, Gems = gems, Remaining = data.Inventory[id] or 0 })
end

-- Sells every copy beyond the first for non-favourite items up to a rarity.
function InventoryService:SellDuplicates(profile, rawMax: any)
	local maxRarity = Guard.integer(rawMax, 1, 7)
	if not maxRarity then
		return Net.fail("Invalid rarity.")
	end
	local data = profile.Data
	local totalGems, totalItems = 0, 0
	local touchedEquipped = false
	for id, count in pairs(table.clone(data.Inventory)) do
		local item = Items.ById[id]
		if item and count > 1 and item.RarityIndex <= maxRarity and not data.Favorites[id] then
			if isEquipped(data, id) then
				touchedEquipped = true
			end
			totalGems += self:_sell(profile, id, count - 1)
			totalItems += count - 1
		end
	end
	if totalItems == 0 then
		return Net.fail("No duplicates to sell.")
	end
	changed(self, profile, touchedEquipped)
	return Net.ok({ Sold = totalItems, Gems = totalGems })
end

InventoryService.MaxSlots = GameConfig.Equip.MaxSlots

return InventoryService
