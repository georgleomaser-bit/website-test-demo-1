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
	================================================================

	Reward kinds (one per product):
	  Gems = n                         adds n Gems (not affected by Gem boosts)
	  Boost = { Seconds, Stat, Mult }  a timed boost; buying again adds time.
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
	Gems: number?,
	Boost: { Seconds: number, Stat: string, Mult: number }?,
	Crates: number?,
	Crate: string?,
	Op: boolean?,
	SuggestedPrice: number,
	ProductId: number,
	Order: number?, -- set from the list position below
}

local DevProducts = {}

DevProducts.List = {
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
	return type(product.ProductId) == "number" and product.ProductId > 0
end

-- The configured product with this Roblox ID (read live, like GamePasses).
function DevProducts.byProductId(id: any): Product?
	if type(id) ~= "number" or id <= 0 then
		return nil
	end
	for _, product in ipairs(DevProducts.List) do
		if product.ProductId == id then
			return product
		end
	end
	return nil
end

return DevProducts
