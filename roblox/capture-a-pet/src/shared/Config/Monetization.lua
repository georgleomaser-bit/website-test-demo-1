-- Game passes and developer products.
-- Replace every Id = 0 with the real id from the Creator Dashboard
-- (Creations > your experience > Monetization > Passes / Developer Products).
-- Items with Id = 0 are shown as "coming soon" and can't be bought.

local Monetization = {}

Monetization.GamePasses = {
	{ Key = "DoubleCash", Id = 0, Name = "2x Cash", Price = 199, Description = "Double cash from all your animals, forever." },
	{ Key = "DoubleTraining", Id = 0, Name = "2x Training", Price = 149, Description = "Double Speed from every treadmill, forever." },
	{ Key = "FastHatch", Id = 0, Name = "Fast Hatch", Price = 129, Description = "Eggs hatch 3x faster." },
	{ Key = "VIP", Id = 0, Name = "VIP", Price = 299, Description = "x1.5 cash and training, VIP treadmill (3x your best), +2 pen slots, +1 incubator, longer base lock and a VIP chat tag." },
	{ Key = "Lucky", Id = 0, Name = "Lucky", Price = 249, Description = "x2 luck for rarer animals and eggs, forever." },
	{ Key = "BaitBag", Id = 0, Name = "Bait Bag", Price = 99, Description = "Start every day with 10 free Glow Baits and hold up to 99." },
}

-- Kind decides what ProcessReceipt grants. Amounts for cash packs scale with your income.
Monetization.Products = {
	{ Key = "CashSmall", Id = 0, Name = "Cash Pile", Price = 25, Kind = "Cash", IncomeSeconds = 600, Min = 5000 },
	{ Key = "CashMedium", Id = 0, Name = "Cash Stack", Price = 99, Kind = "Cash", IncomeSeconds = 3600, Min = 50000 },
	{ Key = "CashLarge", Id = 0, Name = "Cash Vault", Price = 399, Kind = "Cash", IncomeSeconds = 6 * 3600, Min = 500000 },
	{ Key = "Boost2xTraining", Id = 0, Name = "x2 Speed (15 min)", Price = 39, Kind = "Boost", Boost = "Training", Seconds = 900 },
	{ Key = "Boost2xCash", Id = 0, Name = "x2 Cash (15 min)", Price = 49, Kind = "Boost", Boost = "Cash", Seconds = 900 },
	{ Key = "Boost2xLuck", Id = 0, Name = "x2 Luck (15 min)", Price = 49, Kind = "Boost", Boost = "Luck", Seconds = 900 },
	{ Key = "ServerLuck", Id = 0, Name = "Server Luck x2 (10 min)", Price = 99, Kind = "ServerLuck", Seconds = 600 },
	{ Key = "Bait5", Id = 0, Name = "5 Glow Baits", Price = 19, Kind = "Bait", Amount = 5 },
	{ Key = "InstantHatch", Id = 0, Name = "Hatch All Now", Price = 29, Kind = "InstantHatch" },
}

Monetization.PassByKey = {}
Monetization.PassById = {}
for _, pass in ipairs(Monetization.GamePasses) do
	Monetization.PassByKey[pass.Key] = pass
	if pass.Id ~= 0 then
		Monetization.PassById[pass.Id] = pass
	end
end

Monetization.ProductByKey = {}
Monetization.ProductById = {}
for _, product in ipairs(Monetization.Products) do
	Monetization.ProductByKey[product.Key] = product
	if product.Id ~= 0 then
		Monetization.ProductById[product.Id] = product
	end
end

return Monetization
