--[[
	Loot (ModuleScript)
	Location: ReplicatedStorage/Shared/Loot
	Depends on: Shared/Config/Rarities, Shared/Config/Items

	Pure crate-roll maths. The SERVER performs every real roll with its own
	Random object; the client only calls effectiveWeights() to display odds.

	Luck: weight' = weight * (1 + luck) ^ LuckPower(rarity). Common has
	LuckPower 0, so luck shifts probability from Common toward rarer tiers.

	Pity: pityState[rarityId] counts openings since the last drop of that
	rarity or better. When the next opening would reach the threshold, the
	roll is restricted to that rarity or better.
]]

local Config = script.Parent.Config
local Rarities = require(Config.Rarities)
local Items = require(Config.Items)

export type WeightEntry = { Rarity: string, Index: number, Weight: number, Chance: number }

local Loot = {}

function Loot.effectiveWeights(chest, luck: number): { WeightEntry }
	local entries = {}
	local total = 0
	local factor = 1 + math.max(0, luck)
	for _, rarityId in ipairs(Rarities.Order) do
		local base = chest.Weights[rarityId]
		if base and base > 0 then
			local rarity = Rarities.ById[rarityId]
			local weight = base * factor ^ rarity.LuckPower
			total += weight
			table.insert(entries, { Rarity = rarityId, Index = rarity.Index, Weight = weight, Chance = 0 })
		end
	end
	for _, entry in ipairs(entries) do
		entry.Chance = entry.Weight / total
	end
	return entries
end

local function pickRarity(rng: Random, entries: { WeightEntry }, minIndex: number): string
	local total = 0
	for _, entry in ipairs(entries) do
		if entry.Index >= minIndex then
			total += entry.Weight
		end
	end
	if total <= 0 then
		-- No rarity at or above the pity floor exists in this crate; fall back to the rarest.
		return entries[#entries].Rarity
	end
	local roll = rng:NextNumber() * total
	local last = entries[#entries].Rarity
	for _, entry in ipairs(entries) do
		if entry.Index >= minIndex then
			roll -= entry.Weight
			last = entry.Rarity
			if roll <= 0 then
				return entry.Rarity
			end
		end
	end
	return last
end

function Loot.pickItem(rng: Random, chestId: string, rarityId: string): string?
	local pool = Items.PoolByChest[chestId]
	local list = pool and pool[rarityId]
	if not list or #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

--[[
	Performs one roll. Mutates pityState (a table keyed by rarity id).
	pityThresholds: { [rarityId] = openings } already adjusted for skills.
	Returns itemId, rarityId, pityTriggered.
]]
function Loot.roll(rng: Random, chest, luck: number, pityState: { [string]: number }, pityThresholds: { [string]: number })
	local entries = Loot.effectiveWeights(chest, luck)
	local minIndex = 0
	local pityTriggered = false
	for rarityId, threshold in pairs(pityThresholds) do
		local count = pityState[rarityId] or 0
		if count + 1 >= threshold then
			local idx = Rarities.index(rarityId)
			if idx > minIndex then
				minIndex = idx
				pityTriggered = true
			end
		end
	end

	local rarityId = pickRarity(rng, entries, minIndex)
	local rolledIndex = Rarities.index(rarityId)
	for pityRarity in pairs(pityThresholds) do
		if rolledIndex >= Rarities.index(pityRarity) then
			pityState[pityRarity] = 0
		else
			pityState[pityRarity] = (pityState[pityRarity] or 0) + 1
		end
	end

	local itemId = Loot.pickItem(rng, chest.Id, rarityId)
	return itemId, rarityId, pityTriggered
end

--[[
	Robux crates: the rarity comes from the crate's own weights (with luck),
	the item from `pool` ({ [rarityId] = { itemId } }, built by the server from
	the crates the player has unlocked). Rarities missing from the pool are
	skipped. Returns itemId, rarityId (nil when the pool is empty).
]]
function Loot.rollFromPool(rng: Random, chest, luck: number, pool: { [string]: { string } }): (string?, string?)
	local entries = {}
	for _, entry in ipairs(Loot.effectiveWeights(chest, luck)) do
		local list = pool[entry.Rarity]
		if list and #list > 0 then
			table.insert(entries, entry)
		end
	end
	if #entries == 0 then
		return nil, nil
	end
	local rarityId = pickRarity(rng, entries, 0)
	local list = pool[rarityId]
	return list[rng:NextInteger(1, #list)], rarityId
end

-- Admin testing: one item of an exact rarity from a crate's pool. Never touches pity.
function Loot.rollForcedRarity(rng: Random, chest, rarityId: string): string?
	return Loot.pickItem(rng, chest.Id, rarityId)
end

--[[
	Admin testing: simulates `count` openings with a private pity state and
	returns { [rarityId] = drops }. Uses exactly the production roll function,
	so the result reflects real odds without changing anyone's data.
]]
function Loot.simulate(rng: Random, chest, luck: number, count: number, pityThresholds: { [string]: number }?)
	local results = {}
	local pity = {}
	for _, rarityId in ipairs(Rarities.Order) do
		results[rarityId] = 0
	end
	for _ = 1, count do
		local _, rarityId = Loot.roll(rng, chest, luck, pity, pityThresholds or {})
		results[rarityId] += 1
	end
	return results
end

return Loot
