--[[
	DataOps (ModuleScript)
	Location: ServerScriptService/Core/DataOps
	Depends on: ReplicatedStorage/Shared/Config/*

	Pure, non-yielding mutations of a player data table. Used by the online
	services AND by DataService:UpdateOffline (inside UpdateAsync transform
	functions, which must not yield). Every function clamps its inputs so a
	caller can never push data out of range.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local GameConfig = require(Config.GameConfig)
local Items = require(Config.Items)
local Chests = require(Config.Chests)

local DataOps = {}

local function finite(v: number): boolean
	return v == v and v ~= math.huge and v ~= -math.huge
end

-- Adds (or subtracts, when negative) currency. Returns the new balance.
function DataOps.addCurrency(data, currency: string, amount: number): number
	assert(GameConfig.Currencies[currency], "Unknown currency " .. tostring(currency))
	assert(type(amount) == "number" and finite(amount), "Invalid amount")
	local current = data.Currencies[currency] or 0
	local value = math.clamp(current + amount, 0, GameConfig.CurrencyCap)
	data.Currencies[currency] = value
	return value
end

function DataOps.setCurrency(data, currency: string, value: number): number
	assert(GameConfig.Currencies[currency], "Unknown currency " .. tostring(currency))
	assert(type(value) == "number" and finite(value), "Invalid amount")
	local v = math.clamp(value, 0, GameConfig.CurrencyCap)
	data.Currencies[currency] = v
	return v
end

-- Adds copies of an item. Returns true when the item was newly discovered.
function DataOps.addItem(data, itemId: string, count: number, timestamp: number?): boolean
	assert(Items.ById[itemId], "Unknown item " .. tostring(itemId))
	assert(count >= 1 and count == math.floor(count), "Invalid item count")
	local current = data.Inventory[itemId] or 0
	data.Inventory[itemId] = math.min(GameConfig.Inventory.MaxStack, current + count)
	local isNew = data.Discovered[itemId] == nil
	if isNew then
		data.Discovered[itemId] = timestamp or os.time()
	end
	return isNew
end

-- Removes up to `count` copies. Unequips/unfavourites when none remain.
-- Returns the number actually removed.
function DataOps.removeItem(data, itemId: string, count: number): number
	local current = data.Inventory[itemId] or 0
	local removed = math.clamp(math.floor(count), 0, current)
	local remaining = current - removed
	if remaining <= 0 then
		data.Inventory[itemId] = nil
		data.Favorites[itemId] = nil
		for i = #data.Equipped, 1, -1 do
			if data.Equipped[i] == itemId then
				table.remove(data.Equipped, i)
			end
		end
	else
		data.Inventory[itemId] = remaining
	end
	return removed
end

function DataOps.addChest(data, chestId: string, count: number): number
	assert(Chests.ById[chestId], "Unknown crate " .. tostring(chestId))
	assert(count >= 1 and count == math.floor(count), "Invalid crate count")
	local value = math.min(1e9, (data.Chests[chestId] or 0) + count)
	data.Chests[chestId] = value
	return value
end

function DataOps.removeChest(data, chestId: string, count: number): number
	local current = data.Chests[chestId] or 0
	local removed = math.clamp(math.floor(count), 0, current)
	local remaining = current - removed
	data.Chests[chestId] = if remaining > 0 then remaining else nil
	return removed
end

-- Drops equipped items beyond the allowed slot count.
function DataOps.trimEquipped(data, slots: number)
	while #data.Equipped > slots do
		table.remove(data.Equipped)
	end
end

return DataOps
