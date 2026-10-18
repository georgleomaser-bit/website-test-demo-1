--[[
	Chests (ModuleScript)
	Location: ReplicatedStorage/Shared/Config/Chests

	Crate tiers. Weights are relative (they do not need to sum to anything in
	particular); Loot.effectiveWeights applies luck and normalises them.
	Pity: after N openings of the same crate without a drop of at least the
	given rarity, the next drop is guaranteed to be that rarity or better.

	Gem-priced crates (Prism Cache) never get crate discounts or bonus drops,
	and their items use a small SellFactor, so Gems cannot be farmed by
	buying caches and selling what drops (see docs/GAME_DESIGN.md).

	Item pools are built in Items (each item declares its Chest), so this module
	has no dependency on Items.
]]

export type Chest = {
	Id: string,
	Name: string,
	Icon: string,
	Order: number,
	Tier: number,
	TierFactor: number,
	SellFactor: number?,
	Currency: string,
	Price: number,
	Stage: number,
	Color: Color3,
	Description: string,
	Weights: { [string]: number },
	Pity: { [string]: number },
	MaxOpen: number,
}

local Chests = {}

Chests.List = {
	{
		Id = "starter",
		Name = "Spark Crate",
		Icon = "📦",
		Order = 1,
		Tier = 1,
		TierFactor = 1,
		Currency = "Sparks",
		Price = 250,
		Stage = 1,
		Color = Color3.fromRGB(255, 200, 70),
		Description = "A humble crate humming with static. Everyone starts here.",
		Weights = { Common = 62000, Uncommon = 25000, Rare = 9000, Epic = 3000, Legendary = 800, Mythic = 180, Secret = 20 },
		Pity = { Legendary = 80, Mythic = 500 },
		MaxOpen = 10,
	},
	{
		Id = "neon",
		Name = "Neon Crate",
		Icon = "🎁",
		Order = 2,
		Tier = 2,
		TierFactor = 1.5,
		Currency = "Sparks",
		Price = 8000,
		Stage = 1,
		Color = Color3.fromRGB(255, 70, 160),
		Description = "Glows in the dark. Packed with arcade relics.",
		Weights = { Common = 55000, Uncommon = 27000, Rare = 11500, Epic = 4600, Legendary = 1500, Mythic = 360, Secret = 40 },
		Pity = { Legendary = 70, Mythic = 450 },
		MaxOpen = 10,
	},
	{
		Id = "plasma",
		Name = "Plasma Crate",
		Icon = "🧰",
		Order = 3,
		Tier = 3,
		TierFactor = 2.5,
		Currency = "Sparks",
		Price = 1.5e6,
		Stage = 2,
		Color = Color3.fromRGB(255, 140, 50),
		Description = "Superheated lab equipment. Handle with gloves.",
		Weights = { Common = 50000, Uncommon = 28000, Rare = 13500, Epic = 6000, Legendary = 2000, Mythic = 450, Secret = 50 },
		Pity = { Legendary = 65, Mythic = 400 },
		MaxOpen = 10,
	},
	{
		Id = "void",
		Name = "Void Crate",
		Icon = "🗃️",
		Order = 4,
		Tier = 4,
		TierFactor = 4,
		Currency = "Sparks",
		Price = 6e7,
		Stage = 3,
		Color = Color3.fromRGB(140, 90, 255),
		Description = "Contents may not obey the laws of physics.",
		Weights = { Common = 46000, Uncommon = 29000, Rare = 15000, Epic = 7000, Legendary = 2350, Mythic = 580, Secret = 70 },
		Pity = { Legendary = 60, Mythic = 380 },
		MaxOpen = 10,
	},
	{
		Id = "celestial",
		Name = "Celestial Crate",
		Icon = "🌠",
		Order = 5,
		Tier = 5,
		TierFactor = 6.5,
		Currency = "Sparks",
		Price = 1.5e10,
		Stage = 4,
		Color = Color3.fromRGB(70, 200, 255),
		Description = "Fell from the sky. Still warm.",
		Weights = { Common = 42000, Uncommon = 30000, Rare = 16500, Epic = 8000, Legendary = 2700, Mythic = 700, Secret = 100 },
		Pity = { Legendary = 55, Mythic = 350 },
		MaxOpen = 10,
	},
	{
		Id = "singularity",
		Name = "Singularity Core",
		Icon = "🌌",
		Order = 6,
		Tier = 6,
		TierFactor = 10,
		Currency = "Sparks",
		Price = 8e12,
		Stage = 5,
		Color = Color3.fromRGB(235, 235, 255),
		Description = "Infinitely dense. Infinitely valuable.",
		Weights = { Common = 38000, Uncommon = 31000, Rare = 18000, Epic = 9000, Legendary = 3000, Mythic = 850, Secret = 150 },
		Pity = { Legendary = 50, Mythic = 320 },
		MaxOpen = 10,
	},
	{
		Id = "prism",
		Name = "Prism Cache",
		Icon = "💠",
		Order = 7,
		Tier = 3,
		TierFactor = 3,
		-- Items from a Gem-priced crate sell for far less than their equip power
		-- suggests, so buying caches and selling the drops can never create Gems.
		SellFactor = 0.1,
		Currency = "Gems",
		Price = 120,
		Stage = 1,
		Color = Color3.fromRGB(77, 225, 255),
		Description = "Paid for in Gems. Only Rare or better inside.",
		Weights = { Rare = 60000, Epic = 28000, Legendary = 9500, Mythic = 2300, Secret = 200 },
		Pity = { Legendary = 25, Mythic = 150 },
		MaxOpen = 10,
	},
}

Chests.ById = {}
Chests.Order = {}
for _, chest in ipairs(Chests.List) do
	Chests.ById[chest.Id] = chest
	table.insert(Chests.Order, chest.Id)
end
table.sort(Chests.Order, function(a, b)
	return Chests.ById[a].Order < Chests.ById[b].Order
end)

-- Allowed multi-open amounts shown in the UI. The server accepts any integer 1..MaxOpen.
Chests.OpenAmounts = { 1, 5, 10 }

--[[
	Robux crates ("OP crates"). Bought only as Developer Products
	(Config/DevProducts) and opened by the server the moment the purchase is
	processed, so they are kept out of Chests.List / Chests.ById: the
	OpenChest action, owned-crate counts, pity and the collection book never
	see them.
	Weights contain only the guaranteed rarity and better (Luck still shifts
	them upward). The item comes from the combined pools of every crate the
	player has already unlocked, so no item from a locked stage is handed out
	early, and the crates have no items of their own.
]]
Chests.RobuxList = {
	{
		Id = "op_crate",
		Name = "OP Crate",
		Icon = "🔥",
		Order = 101,
		Tier = 4,
		Currency = "Robux",
		Color = Color3.fromRGB(176, 92, 255),
		Description = "Epic or better guaranteed!",
		Weights = { Epic = 7000, Legendary = 2400, Mythic = 550, Secret = 50 },
	},
	{
		Id = "mega_op_crate",
		Name = "Mega OP Crate",
		Icon = "💥",
		Order = 102,
		Tier = 6,
		Currency = "Robux",
		Color = Color3.fromRGB(255, 180, 40),
		Description = "Legendary or better guaranteed!",
		Weights = { Legendary = 8000, Mythic = 1800, Secret = 200 },
	},
	{
		Id = "ultra_op_crate",
		Name = "Ultra OP Crate",
		Icon = "🌌",
		Order = 103,
		Tier = 8,
		Currency = "Robux",
		Color = Color3.fromRGB(255, 64, 112),
		Description = "Mythic or better guaranteed, 8% Secret!",
		Weights = { Mythic = 9200, Secret = 800 },
	},
}
Chests.RobuxById = {}
for _, chest in ipairs(Chests.RobuxList) do
	Chests.RobuxById[chest.Id] = chest
end

function Chests.get(id: string): Chest?
	return Chests.ById[id]
end

-- Highest-tier Sparks crate that a player with the given stage can access.
function Chests.bestSparksChestForStage(stage: number): string
	local best = "starter"
	local bestOrder = 0
	for _, chest in ipairs(Chests.List) do
		if chest.Currency == "Sparks" and chest.Stage <= stage and chest.Order > bestOrder then
			best = chest.Id
			bestOrder = chest.Order
		end
	end
	return best
end

return Chests
