-- =====================================================================
--  CLUTCH CLASH – Luau-CLI-Test für Shared/Odds + Config/Shop (WP9)
--  Start im Projektordner:  <scratchpad>/luau-build/luau tests/odds.test.luau
--  Prüft: Kisten-Gewichte = 10000, Anzeige = Server-Tabelle = genau 100.00 %, Rundung (größte Reste),
--  Garantie-Tabelle (250/250/100), Wurf-Grenzen + Verteilung, Garantie-Wurf nur Legendary/Mythic,
--  Validate erkennt kaputte Kisten, Preis-/Paket-Regeln, Saison-Fallback, Rampenlicht deterministisch,
--  kein Robux-Produkt mit Münzen/Schlüsseln/Splittern/Waffen.
--  Ein Fehler beendet das Skript mit Exit-Code 1.
-- =====================================================================

local Odds = require("../src/shared/Odds")
local Shop = require("../src/shared/Config/Shop")

local passed, failed = 0, 0

local function check(name: string, condition: boolean, detail: string?)
	if condition then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. (if detail then " – " .. detail else ""))
	end
end

local function eq(name: string, actual: any, expected: any)
	check(name, actual == expected, ("erwartet %s, bekommen %s"):format(tostring(expected), tostring(actual)))
end

-- Künstlicher Zufall: liefert der Reihe nach feste Werte (oder einen LCG)
local function fixedRng(values: { number })
	local i = 0
	return {
		NextInteger = function(_self: any, lo: number, hi: number): number
			i += 1
			local v = values[((i - 1) % #values) + 1]
			return math.clamp(v, lo, hi)
		end,
	}
end

local function lcgRng(seed: number)
	local state = seed
	return {
		NextInteger = function(_self: any, lo: number, hi: number): number
			state = (state * 48271) % 2147483647
			return lo + (state % (hi - lo + 1))
		end,
	}
end

local S1 = Shop.Crates.S1

-- ---------------------------------------------------------------------
-- 1) Gewichte & Validate
-- ---------------------------------------------------------------------
local ok, err = Odds.Validate(S1)
check("S1 Validate", ok, err)
eq("S1 Anzahl Items", #S1.Items, 24)
local total = 0
for _, item in ipairs(S1.Items) do
	total += item.Weight
end
eq("S1 Summe Gewichte", total, 10000)
eq("Odds.TOTAL", Odds.TOTAL, 10000)
eq("S1 PityAfter", S1.PityAfter, 29)
eq("S1 GemPrice", S1.GemPrice, 120)

-- ---------------------------------------------------------------------
-- 2) Anzeige-Tabelle = Gewicht / 100, Summe exakt 100.00
-- ---------------------------------------------------------------------
local rows = Odds.Table(S1)
eq("Table Zeilen", #rows, 24)
local sum = 0
local exact = true
for i, row in ipairs(rows) do
	sum += row.Hundredths
	if row.Hundredths ~= S1.Items[i].Weight or row.Id ~= S1.Items[i].Id then
		exact = false
	end
	if math.abs(row.Percent - S1.Items[i].Weight / 100) > 1e-9 then
		exact = false
	end
end
eq("Table Summe Hundertstel", sum, 10000)
check("Table = Gewicht/100 je Item (gleiche Reihenfolge)", exact)

-- Seltenheiten 50 / 30 / 14 / 5 / 1
local expectedRarity = { Common = 5000, Rare = 3000, Epic = 1400, Legendary = 500, Mythic = 100 }
local expectedCount = { Common = 10, Rare = 6, Epic = 5, Legendary = 2, Mythic = 1 }
local raritySum = 0
for _, row in ipairs(Odds.RarityTable(S1)) do
	eq("Rarity " .. row.Rarity, row.Hundredths, expectedRarity[row.Rarity])
	eq("Rarity-Anzahl " .. row.Rarity, row.Count, expectedCount[row.Rarity])
	raritySum += row.Hundredths
end
eq("RarityTable Summe", raritySum, 10000)

-- ---------------------------------------------------------------------
-- 3) Garantie-Tabelle: 250/250/100 -> 41.67 / 41.67 / 16.66 (Summe genau 100.00)
-- ---------------------------------------------------------------------
local pity = Odds.PityTable(S1)
eq("PityTable Zeilen", #pity, 3)
local pitySum = 0
for _, row in ipairs(pity) do
	pitySum += row.Hundredths
	check("Pity nur Legendary/Mythic: " .. row.Id, row.Rarity == "Legendary" or row.Rarity == "Mythic")
end
eq("PityTable Summe", pitySum, 10000)
eq("Pity PoolNoodle", pity[1].Hundredths, 4167)
eq("Pity GoldStatue", pity[2].Hundredths, 4167)
eq("Pity RubberDuck", pity[3].Hundredths, 1666)
local pityRarity = Odds.RarityTable(S1, true)
eq("Pity-Seltenheiten", #pityRarity, 2)

-- Rundung: drei gleiche Gewichte -> 33.34 / 33.33 / 33.33
local thirds = Odds.Table({ Items = { { Id = "A", Weight = 1 }, { Id = "B", Weight = 1 }, { Id = "C", Weight = 1 } } })
eq("Drittel Summe", thirds[1].Hundredths + thirds[2].Hundredths + thirds[3].Hundredths, 10000)
eq("Drittel A", thirds[1].Hundredths, 3334)
eq("Drittel B", thirds[2].Hundredths, 3333)
-- 7 gleiche Gewichte: Summe trotzdem genau 10000
local seven = {}
for i = 1, 7 do
	table.insert(seven, { Id = "X" .. i, Weight = 3 })
end
local sevenSum = 0
for _, row in ipairs(Odds.Table({ Items = seven })) do
	sevenSum += row.Hundredths
end
eq("Siebtel Summe", sevenSum, 10000)

-- Anzeige-Format
eq("FormatPercent 500", Odds.FormatPercent(500), "5.00")
eq("FormatPercent 4167 de", Odds.FormatPercent(4167, ","), "41,67")
eq("FormatPercent 10000", Odds.FormatPercent(10000), "100.00")
eq("FormatPercent 7", Odds.FormatPercent(7), "0.07")
eq("FormatPercent NaN", Odds.FormatPercent(0 / 0), "0.00")

-- ---------------------------------------------------------------------
-- 4) Wurf
-- ---------------------------------------------------------------------
eq("Roll 1 = erstes Item", Odds.Roll(S1, fixedRng({ 1 }) :: any, false), "W_Mint")
eq("Roll 500 = erstes Item", Odds.Roll(S1, fixedRng({ 500 }) :: any, false), "W_Mint")
eq("Roll 501 = zweites Item", Odds.Roll(S1, fixedRng({ 501 }) :: any, false), "W_Sky")
eq("Roll 10000 = letztes Item", Odds.Roll(S1, fixedRng({ 10000 }) :: any, false), "S_PopGrenade_RubberDuck")
eq("Roll 9900 = Legendary", Odds.Roll(S1, fixedRng({ 9900 }) :: any, false), "F_GoldStatue")
eq("Roll Überlauf geklemmt", Odds.Roll(S1, fixedRng({ 99999 }) :: any, false), "S_PopGrenade_RubberDuck")
-- Garantie: Wurf 1..600 nur unter Legendary + Mythic
eq("Pity-Roll 1", Odds.Roll(S1, fixedRng({ 1 }) :: any, true), "S_Longshot_PoolNoodle")
eq("Pity-Roll 251", Odds.Roll(S1, fixedRng({ 251 }) :: any, true), "F_GoldStatue")
eq("Pity-Roll 600", Odds.Roll(S1, fixedRng({ 600 }) :: any, true), "S_PopGrenade_RubberDuck")

local rarityOf = {}
for _, item in ipairs(S1.Items) do
	rarityOf[item.Id] = item.Rarity
end
local rng = lcgRng(12345)
local allPity = true
for _ = 1, 2000 do
	local id = Odds.Roll(S1, rng :: any, true)
	if rarityOf[id] ~= "Legendary" and rarityOf[id] ~= "Mythic" then
		allPity = false
	end
end
check("Pity 2000× nur Legendary/Mythic", allPity)

-- Verteilung (200.000 Würfe, ±0,4 Prozentpunkte je Seltenheit)
local counts = { Common = 0, Rare = 0, Epic = 0, Legendary = 0, Mythic = 0 }
local N = 200000
local dist = lcgRng(987654)
for _ = 1, N do
	local id = Odds.Roll(S1, dist :: any, false)
	counts[rarityOf[id]] += 1
end
for rarity, hundredths in pairs(expectedRarity) do
	local share = counts[rarity] / N * 10000
	check(("Verteilung %s ≈ %d"):format(rarity, hundredths), math.abs(share - hundredths) < 40, tostring(share))
end

-- ---------------------------------------------------------------------
-- 5) Validate erkennt kaputte Kisten
-- ---------------------------------------------------------------------
local function crateWith(mutator: (items: { any }) -> ())
	local items = {}
	for _, item in ipairs(S1.Items) do
		table.insert(items, { Id = item.Id, Weight = item.Weight, Rarity = item.Rarity })
	end
	mutator(items)
	return { Items = items, PityAfter = 29, PityRarities = { "Legendary", "Mythic" } }
end
check("Validate: Summe 9999", not Odds.Validate(crateWith(function(items)
	items[1].Weight = 499
end)))
check("Validate: Gewicht 0", not Odds.Validate(crateWith(function(items)
	items[1].Weight = 0
	items[2].Weight = 1000
end)))
check("Validate: Bruch-Gewicht", not Odds.Validate(crateWith(function(items)
	items[1].Weight = 499.5
	items[2].Weight = 500.5
end)))
check("Validate: doppelte Id", not Odds.Validate(crateWith(function(items)
	items[2].Id = items[1].Id
end)))
check("Validate: leer", not Odds.Validate({ Items = {} }))
check("Validate: Garantie ohne Legendary", not Odds.Validate(crateWith(function(items)
	for _, item in ipairs(items) do
		if item.Rarity == "Legendary" or item.Rarity == "Mythic" then
			item.Rarity = "Epic"
		end
	end
end)))

-- ---------------------------------------------------------------------
-- 6) Shop-Regeln (B20.1, B22, B23)
-- ---------------------------------------------------------------------
local packs = {}
for _, n in ipairs(Shop.GemPacks) do
	packs[n] = true
end
for rarity, price in pairs(Shop.CatalogPrices) do
	check("Katalogpreis = Gem-Paket " .. rarity, packs[price] == true)
end
eq("Kistenpreis = Paket", packs[S1.GemPrice], true)
eq("DupeShards Common", Shop.DupeShards.Common, 20)
eq("DupeShards Mythic", Shop.DupeShards.Mythic, 800)
eq("ShardPrices Legendary", Shop.ShardPrices.Legendary, 1500)
eq("ShardPrices Mythic", Shop.ShardPrices.Mythic, 3000)
eq("Max. 1 Angebot pro Sitzung", Shop.MaxOffersPerSession, 1)
eq("16 Produkte", #Shop.Products, 16)
eq("4 Gamepässe", #Shop.GamePasses, 4)

local forbiddenOk = true
for _, product in ipairs(Shop.Products) do
	for _, grant in ipairs({ product.Grant or {}, product.Fallback or {} }) do
		for _, field in ipairs({ "Coins", "Keys", "Shards", "Weapons", "FreeWeaponPicks" }) do
			if grant[field] ~= nil then
				forbiddenOk = false
				print("  verboten: " .. product.Key .. "." .. field)
			end
		end
	end
	check("Produkt nicht zufällig: " .. product.Key, product.Random == false)
	eq("Produkt-Id 0 (noch nicht eingerichtet): " .. product.Key, product.Id, 0)
end
check("Kein Robux-Produkt gibt Münzen/Schlüssel/Splitter/Waffen", forbiddenOk)
eq("PassPremium Ersatz 500 Gems", Shop.ProductsByKey.PassPremium.Fallback.Gems, 500)
eq("StarterPack Ersatz 120 Gems", Shop.ProductsByKey.StarterPack.Fallback.Gems, 120)
eq("ProductsById leer bei Id 0", next(Shop.ProductsById), nil)
check("CrateItem findet W_Mint", Shop.CrateItem("S1", "W_Mint") ~= nil)
check("IsCrateItem T_Gold", Shop.IsCrateItem("T_Gold"))
check("IsCrateItem nicht C_Ghost", not Shop.IsCrateItem("C_Ghost"))

-- ---------------------------------------------------------------------
-- 7) Saison-Fallback (B21.2) und Datum
-- ---------------------------------------------------------------------
local s1Start = Shop.ParseUtc("2026-10-15T00:00:00Z")
eq("ParseUtc 1970", Shop.ParseUtc("1970-01-01T00:00:00Z"), 0)
eq("ParseUtc 2026-10-15", s1Start, 1792022400)
eq("ParseUtc kaputt", Shop.ParseUtc("2026-13-01T00:00:00Z"), nil)
local seasons = {
	{ Id = 1, StartUtc = "2026-10-15T00:00:00Z", EndUtc = "2026-12-10T00:00:00Z" },
	{ Id = 2, StartUtc = "2026-12-10T00:00:00Z", EndUtc = "2027-02-04T00:00:00Z" },
}
eq("Saison vor allen -> 1", Shop.SeasonIdAt(seasons, (s1Start :: number) - 86400), 1)
eq("Saison im Fenster 1", Shop.SeasonIdAt(seasons, (s1Start :: number) + 86400), 1)
eq("Saison im Fenster 2", Shop.SeasonIdAt(seasons, Shop.ParseUtc("2027-01-01T00:00:00Z") :: number), 2)
eq("Saison nach allen -> jüngste", Shop.SeasonIdAt(seasons, Shop.ParseUtc("2028-01-01T00:00:00Z") :: number), 2)
eq("Saison ohne Liste -> 1", Shop.SeasonIdAt({}, 0), 1)

-- ---------------------------------------------------------------------
-- 8) Preise & Rampenlicht mit einer Mini-Kosmetik-Tabelle (ohne Roblox-Typen)
-- ---------------------------------------------------------------------
local fakeCosmetics = {
	ById = {
		W_Mint = { Kind = "Wrap", Rarity = "Common", Source = "Coins", Price = { Coins = 1500 } },
		W_Peach = { Kind = "Wrap", Rarity = "Rare", Source = "Catalog" },
		C_Ghost = { Kind = "Charm", Rarity = "Rare", Source = "Pass" },
		W_MBronze = { Kind = "Wrap", Rarity = "Rare", Source = "Mastery" },
		TT_VIP = { Kind = "Title", Source = "VIP" },
		F_IceCube = { Kind = "Finisher", Rarity = "Epic", Source = "Catalog" },
	},
	IsExclusive = function(id: string, seasonId: number): boolean
		return id == "C_Ghost" and seasonId <= 1
	end,
}
eq("Preis Münz-Wrap Coins", Shop.PriceOf(fakeCosmetics, "W_Mint", "Coins", 1), 1500)
eq("Preis Münz-Wrap Gems (Kisten-Item)", Shop.PriceOf(fakeCosmetics, "W_Mint", "Gems", 1), 120)
eq("Preis Münz-Wrap Splitter", Shop.PriceOf(fakeCosmetics, "W_Mint", "Shards", 1), 100)
eq("Preis Katalog Rare", Shop.PriceOf(fakeCosmetics, "W_Peach", "Gems", 1), 250)
eq("Preis Katalog Rare −20 %", Shop.PriceOf(fakeCosmetics, "W_Peach", "Gems", 1, true), 200)
eq("Katalog Rare nicht für Splitter (kein Kisten-Item)", Shop.PriceOf(fakeCosmetics, "W_Peach", "Shards", 1), nil)
eq("Pass-Item in Saison 1 nicht kaufbar", Shop.PriceOf(fakeCosmetics, "C_Ghost", "Gems", 1), nil)
eq("Pass-Item ab Saison 2 im Katalog", Shop.PriceOf(fakeCosmetics, "C_Ghost", "Gems", 2), 250)
eq("Meisterschaft nie kaufbar", Shop.PriceOf(fakeCosmetics, "W_MBronze", "Gems", 1), nil)
eq("Titel nie kaufbar", Shop.PriceOf(fakeCosmetics, "TT_VIP", "Gems", 1), nil)
eq("Kisten-Epic Splitter", Shop.PriceOf(fakeCosmetics, "F_IceCube", "Shards", 1), 600)

local pool = Shop.FeaturedPool(fakeCosmetics, 1)
eq("Rampenlicht-Pool Saison 1", table.concat(pool, ","), "F_IceCube,W_Mint,W_Peach")
local bigPool = {}
for i = 1, 30 do
	table.insert(bigPool, ("ID%02d"):format(i))
end
local dayA = Shop.PickFeatured(bigPool, 20737)
local dayA2 = Shop.PickFeatured(bigPool, 20737)
local dayB = Shop.PickFeatured(bigPool, 20738)
eq("Rampenlicht 6 Items", #dayA, 6)
eq("Rampenlicht deterministisch", table.concat(dayA, ","), table.concat(dayA2, ","))
check("Rampenlicht wechselt täglich", table.concat(dayA, ",") ~= table.concat(dayB, ","))
local seen, unique = {}, true
for _, id in ipairs(dayA) do
	if seen[id] then
		unique = false
	end
	seen[id] = true
end
check("Rampenlicht ohne Doppelte", unique)
eq("Rampenlicht kleiner Pool", #Shop.PickFeatured({ "A", "B" }, 5), 2)

-- ---------------------------------------------------------------------
print(("[odds.test] %d/%d PASS"):format(passed, passed + failed))
if failed > 0 then
	error(("%d Test(s) fehlgeschlagen"):format(failed))
end
