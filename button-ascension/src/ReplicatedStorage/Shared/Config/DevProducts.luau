--[[
	DevProducts (ModuleScript)
	Location: ReplicatedStorage/Shared/Config/DevProducts

	Developer Products: Robux purchases that can be bought again and again
	(Gem packs, a timed Sparks boost, a crate bundle). Rewards are granted only
	by the server in MarketplaceService.ProcessReceipt (ProductService), saved
	right away, and every receipt is granted exactly once.

	================================================================
	HOW TO SET UP A PRODUCT (once per product)
	================================================================
	1. Publish the game (File → Publish to Roblox).
	2. Open create.roblox.com → Creations → your experience →
	   Monetization → Developer Products → "Create a Developer Product".
	3. Enter the name and description from the list below, upload an image
	   (optional), set the price (SuggestedPrice below) and save.
	4. Copy the product ID (shown in the list, or via "Copy Asset ID") and paste
	   it as ProductId below, e.g.  ProductId = 123456789,
	5. Publish again. Products with ProductId = 0 are "not set up": they are
	   hidden in live games and can't be bought.

	The same rewards can also be sold as a one-time GAME PASS: put the pass
	ID into GamePassId instead. Its reward is then granted once per player
	(recorded in data.PassRewards), on purchase or on the next join.
	With HubName (the exact Creator Hub name) the server checks with Roblox
	which kind the ID really is, so it works either way (Shared/RobuxSale).
	================================================================

	Rewards (a product may combine several; they are granted in this order):
	  Sparks = n                       adds exactly n Sparks (no multipliers; does
	                                   not count toward quests or the run total)
	  Gems = n                         adds n Gems (not affected by Gem boosts)
	  Boost = { Seconds, Stat, Mult }  a timed boost; buying again adds time.
	  Boost = { Seconds, Stat, Add }   (Add for additive stats such as luck)
	                                   The timer only runs while you play.
	  Crates = n                       n of the best Spark crate you have unlocked
	  Crate = "id"                     opens a Robux crate (Config/Chests RobuxList)
	                                   right away and plays the opening animation
]]

export type Product = {
	Key: string,
	Name: string,
	Icon: string,
	Color: Color3,
	Description: string,
	Sparks: number?,
	Gems: number?,
	Boost: { Seconds: number, Stat: string, Mult: number?, Add: number? }?,
	Crates: number?,
	Crate: string?,
	Op: boolean?,
	SuggestedPrice: number,
	ProductId: number,
	GamePassId: number?,
	HubName: string?,
	Order: number?, -- set from the list position below
}

local RobuxSale = require(script.Parent.Parent.RobuxSale)

local DevProducts = {}

DevProducts.List = {
	-- The owner's items from the Creator Hub (created as game passes; the server
	-- confirms the kind with Roblox through HubName and sells them accordingly).
	{
		Key = "starter_pack",
		Name = "Starter Pack",
		Icon = "🎁",
		Color = Color3.fromRGB(255, 200, 70),
		Description = "25,000 Sparks, 150 Gems and 3 crates",
		Sparks = 25000,
		Gems = 150,
		Crates = 3,
		SuggestedPrice = 49,
		ProductId = 0,
		GamePassId = 2037646106,
		HubName = "Starter Pack",
	},
	{
		Key = "sparks_30k",
		Name = "Sparks 30,000",
		Icon = "⚡",
		Color = Color3.fromRGB(255, 214, 74),
		Description = "+30,000 Sparks",
		Sparks = 30000,
		SuggestedPrice = 49,
		ProductId = 0,
		GamePassId = 2037322132,
		HubName = "Spark 30000",
	},
	{
		Key = "sparks_60k",
		Name = "Sparks 60,000",
		Icon = "⚡",
		Color = Color3.fromRGB(255, 214, 74),
		Description = "+60,000 Sparks",
		Sparks = 60000,
		SuggestedPrice = 99,
		ProductId = 0,
		GamePassId = 2036914125,
		HubName = "Spark 60000",
	},
	{
		Key = "op_sparks_200k",
		Name = "OP Sparks 200,000",
		Icon = "⚡",
		Color = Color3.fromRGB(255, 160, 40),
		Description = "+200,000 Sparks",
		Sparks = 200000,
		Op = true,
		SuggestedPrice = 199,
		ProductId = 0,
		GamePassId = 2039811962,
		HubName = "OP Sparks 200000",
	},
	{
		Key = "gems_120",
		Name = "Gems 120",
		Icon = "💎",
		Color = Color3.fromRGB(77, 225, 255),
		Description = "+120 Gems",
		Gems = 120,
		SuggestedPrice = 49,
		ProductId = 0,
		GamePassId = 2039541981,
		HubName = "Gems 120",
	},
	{
		Key = "gems_600",
		Name = "Gems 600",
		Icon = "💎",
		Color = Color3.fromRGB(77, 225, 255),
		Description = "+600 Gems",
		Gems = 600,
		SuggestedPrice = 199,
		ProductId = 0,
		GamePassId = 2039937934,
		HubName = "Gems 600",
	},
	{
		Key = "op_gems_15k",
		Name = "OP Gems 15,000",
		Icon = "💠",
		Color = Color3.fromRGB(176, 92, 255),
		Description = "+15,000 Gems",
		Gems = 15000,
		Op = true,
		SuggestedPrice = 999,
		ProductId = 0,
		GamePassId = 2036932058,
		HubName = "OP Gems 15000",
	},
	{
		Key = "boost_lucky_hour",
		Name = "Lucky Hour Boost",
		Icon = "🍀",
		Color = Color3.fromRGB(74, 222, 128),
		Description = "+100% Luck for 1 hour of play",
		Boost = { Seconds = 60 * 60, Stat = "luck", Add = 1 },
		SuggestedPrice = 99,
		ProductId = 0,
		GamePassId = 2039895926,
		HubName = "Boost Lucky Hour",
	},
	{
		Key = "boost_spark_surge",
		Name = "Spark Surge Boost",
		Icon = "🔥",
		Color = Color3.fromRGB(255, 160, 40),
		Description = "×2 Sparks for 1 hour of play",
		Boost = { Seconds = 60 * 60, Stat = "sparksMult", Mult = 2 },
		SuggestedPrice = 99,
		ProductId = 0,
		GamePassId = 2038198094,
		HubName = "Boost spark search",
	},
	{
		Key = "gems_small",
		Name = "Pouch of Gems",
		Icon = "💎",
		Color = Color3.fromRGB(77, 225, 255),
		Description = "+100 Gems",
		Gems = 100,
		SuggestedPrice = 49,
		ProductId = 0,
	},
	{
		Key = "gems_medium",
		Name = "Sack of Gems",
		Icon = "💎",
		Color = Color3.fromRGB(77, 225, 255),
		Description = "+550 Gems",
		Gems = 550,
		SuggestedPrice = 199,
		ProductId = 0,
	},
	{
		Key = "gems_large",
		Name = "Vault of Gems",
		Icon = "💠",
		Color = Color3.fromRGB(176, 92, 255),
		Description = "+1,200 Gems",
		Gems = 1200,
		SuggestedPrice = 399,
		ProductId = 0,
	},
	{
		Key = "sparks_rush",
		Name = "Sparks Rush",
		Icon = "🔥",
		Color = Color3.fromRGB(255, 160, 40),
		Description = "×3 Sparks for 15 minutes of play. Buy more to add time.",
		Boost = { Seconds = 15 * 60, Stat = "sparksMult", Mult = 3 },
		SuggestedPrice = 99,
		ProductId = 0,
	},
	{
		Key = "op_crate",
		Name = "OP Crate",
		Icon = "🔥",
		Color = Color3.fromRGB(176, 92, 255),
		Description = "Epic or better guaranteed!",
		Crate = "op_crate",
		Op = true,
		SuggestedPrice = 99,
		ProductId = 0,
	},
	{
		Key = "mega_op_crate",
		Name = "Mega OP Crate",
		Icon = "💥",
		Color = Color3.fromRGB(255, 180, 40),
		Description = "Legendary or better guaranteed!",
		Crate = "mega_op_crate",
		Op = true,
		SuggestedPrice = 199,
		ProductId = 0,
	},
	{
		Key = "ultra_op_crate",
		Name = "Ultra OP Crate",
		Icon = "🌌",
		Color = Color3.fromRGB(255, 64, 112),
		Description = "Mythic or better guaranteed, 8% Secret!",
		Crate = "ultra_op_crate",
		Op = true,
		SuggestedPrice = 299,
		ProductId = 0,
	},
	{
		Key = "rainbow_chest",
		Name = "Rainbow Chest",
		Icon = "🌈",
		Color = Color3.fromRGB(255, 120, 220),
		Description = "A guaranteed Rainbow item, Epic or better!",
		Crate = "rainbow_chest",
		Op = true,
		SuggestedPrice = 449,
		ProductId = 0,
	},
	{
		Key = "crate_bundle",
		Name = "Crate Bundle",
		Icon = "🎁",
		Color = Color3.fromRGB(255, 200, 70),
		Description = "5 of the best Spark crate you have unlocked.",
		Crates = 5,
		SuggestedPrice = 149,
		ProductId = 0,
	},
} :: { Product }

-- Stacked boost time is capped so a long purchase streak can't overflow.
DevProducts.MaxBoostSeconds = 24 * 60 * 60

-- How many processed receipt IDs each player keeps (for duplicate protection).
DevProducts.ReceiptHistory = 100

DevProducts.ByKey = {} :: { [string]: Product }
for index, product in ipairs(DevProducts.List) do
	product.Order = index
	DevProducts.ByKey[product.Key] = product
end

function DevProducts.isConfigured(product: Product): boolean
	return (RobuxSale.of(product)) ~= nil
end

local function bySale(kind: string, id: any): Product?
	if type(id) ~= "number" or id <= 0 then
		return nil
	end
	for _, product in ipairs(DevProducts.List) do
		local saleKind, saleId = RobuxSale.of(product)
		if saleKind == kind and saleId == id then
			return product
		end
	end
	return nil
end

-- The entry sold as this developer product (read live, like GamePasses).
function DevProducts.byProductId(id: any): Product?
	return bySale("product", id)
end

-- The entry sold as this one-time game pass.
function DevProducts.byGamePassId(id: any): Product?
	return bySale("pass", id)
end

return DevProducts
