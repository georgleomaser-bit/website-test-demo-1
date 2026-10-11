-- =====================================================================
--  CLUTCH CLASH – SHOP, ROBUX & KISTE (Shared/Config/Shop)
--  Besitzer: WP9 (Wirtschaft, Monetarisierung, Kosmetik). Vertrag: DESIGN.md B18–B23 + C15.
--
--  GAMEPASSES & PRODUKTE: "Id = 0" heißt "noch nicht eingerichtet" -> der Shop zeigt
--  "Bald verfügbar". Wenn du sie im Creator Dashboard angelegt hast, trag hier die Ids ein.
--
--  HARTE REGEL (kein Pay-to-Win): Robux kaufen NIE Münzen, Waffen, Schlüssel, Splitter.
--  Config.Shop.Validate meldet jeden Verstoß, und der Server streicht solche Felder beim Kauf.
--
--  Reines Daten-Modul (keine Roblox-Typen beim Laden) -> mit der Luau-CLI testbar (tests/odds.test.luau).
--  Öffentliche Helfer:
--    Shop.ProductsByKey[key], Shop.ProductsById[id] (nur Id ~= 0), Shop.PassesByKey[key], Shop.PassesById[id]
--    Shop.CrateItem(crate, id): item?          Eintrag { Id, Weight, Rarity } einer Kiste
--    Shop.IsCrateItem(id): boolean             liegt in irgendeiner Kiste
--    Shop.ParseUtc("2026-10-15T00:00:00Z"): number?   Sekunden seit 1970 (UTC)
--    Shop.SeasonIdAt(seasons, now): number     aktive Saison (Fallback-Regel B21.2)
--    Shop.PriceOf(cosmetics, id, currency, seasonId, featured?): number?   EINE Preisregel für Server + Shop-UI
--    Shop.FeaturedPool(cosmetics, seasonId): { string }   Rampenlicht-Kandidaten (alphabetisch)
--    Shop.PickFeatured(pool, utcDay, count?): { string }  6 Items des Tages, deterministisch (überall gleich)
--    Shop.Validate(Config): { string }
-- =====================================================================

local Shop = {}

-- ---------------------------------------------------------------------
-- 1) GAMEPASSES (dauerhaft, B22.1)
-- ---------------------------------------------------------------------
Shop.GamePasses = {
	{
		Key = "VIP",
		Id = 0,
		Price = 349,
		Icon = "👑",
		Name = { de = "VIP", en = "VIP" },
		Desc = {
			de = "+20 % XP & Pass-XP (keine Münzen), goldener Chat-Tag & Namensschild, Titel „VIP“, Wrap „VIP-Gold“ für alle Waffen, Finisher „Kronen-Konfetti“, +1 Tages-Reroll, +1 Glücksrad-Dreh, VIP-Balkon",
			en = "+20% XP & Pass XP (no coins), gold chat tag & nameplate, “VIP” title, “VIP Gold” wrap for every weapon, “Crown Confetti” finisher, +1 daily reroll, +1 wheel spin, VIP balcony",
		},
	},
	{
		Key = "DoubleXP",
		Id = 0,
		Price = 299,
		Icon = "⚡",
		Name = { de = "Doppelte XP", en = "Double XP" },
		Desc = {
			de = "×2 Match-XP für immer (zählt im Deckel ×3). Nur XP – keine Münzen, kein Kampfvorteil.",
			en = "×2 match XP forever (counts toward the ×3 cap). XP only – no coins, no combat edge.",
		},
	},
	{
		Key = "LoadoutPlus",
		Id = 0,
		Price = 99,
		Icon = "🎒",
		Name = { de = "Loadout+", en = "Loadout+" },
		Desc = {
			de = "8 Loadout-Vorlagen statt 3, Namen ändern, „Zufall aus Favoriten“.",
			en = "8 loadout presets instead of 3, rename them, “random from favorites”.",
		},
	},
	{
		Key = "MasteryBoost",
		Id = 0,
		Price = 199,
		Icon = "🏅",
		Name = { de = "Meisterschafts-Boost", en = "Mastery Boost" },
		Desc = {
			de = "×2 Meisterschafts-Fortschritt – schneller zu den Meister-Wraps (nur Kosmetik-Tempo).",
			en = "×2 mastery progress – reach mastery wraps faster (cosmetic pace only).",
		},
	},
}

-- ---------------------------------------------------------------------
-- 2) DEVELOPER PRODUCTS (16, B22.2) – Grant = was der Kauf gibt (Types.Grant)
--    FirstBonus: erster Kauf dieses Pakets gibt doppelte Gems
--    Once:       einmalig (Wiederholung -> Fallback)
--    PerSeason:  einmal pro Saison (schon besessen -> Fallback)
--    Random:     Zufallsprodukt? (keins ist zufällig – Prüfung trotzdem im Code)
-- ---------------------------------------------------------------------
Shop.Products = {
	{
		Key = "Gems120",
		Id = 0,
		Price = 99,
		Kind = "Gems",
		Icon = "💎",
		Name = { de = "Handvoll Gems", en = "Handful of Gems" },
		Grant = { Gems = 120 },
		FirstBonus = true,
		Random = false,
	},
	{
		Key = "Gems250",
		Id = 0,
		Price = 199,
		Kind = "Gems",
		Icon = "💎",
		Name = { de = "Beutel Gems", en = "Pouch of Gems" },
		Grant = { Gems = 250 },
		FirstBonus = true,
		Random = false,
	},
	{
		Key = "Gems500",
		Id = 0,
		Price = 399,
		Kind = "Gems",
		Icon = "💎",
		Name = { de = "Sack Gems", en = "Sack of Gems" },
		Grant = { Gems = 500 },
		FirstBonus = true,
		Random = false,
	},
	{
		Key = "Gems1000",
		Id = 0,
		Price = 749,
		Kind = "Gems",
		Icon = "💎",
		Name = { de = "Kiste Gems", en = "Crate of Gems" },
		Grant = { Gems = 1000 },
		FirstBonus = true,
		Random = false,
	},
	{
		Key = "Gems2200",
		Id = 0,
		Price = 1499,
		Kind = "Gems",
		Icon = "💎",
		Name = { de = "Truhe Gems", en = "Chest of Gems" },
		Grant = { Gems = 2200 },
		FirstBonus = true,
		Random = false,
		Tag = "Popular",
	},
	{
		Key = "Gems5000",
		Id = 0,
		Price = 2999,
		Kind = "Gems",
		Icon = "💎",
		Name = { de = "Tresor Gems", en = "Vault of Gems" },
		Grant = { Gems = 5000 },
		FirstBonus = true,
		Random = false,
		Tag = "BestValue",
	},
	{
		Key = "StarterPack",
		Id = 0,
		Price = 49,
		Kind = "Starter",
		Icon = "⭐",
		Name = { de = "Starter-Paket", en = "Starter Pack" },
		Grant = { Gems = 250, Cosmetics = { "W_RookieRainbow", "C_StarterStar", "TT_Frischling" } },
		Once = true,
		Fallback = { Gems = 120 },
		Random = false,
	},
	{
		Key = "PassPremium",
		Id = 0,
		Price = 449,
		Kind = "Pass",
		Icon = "🎟️",
		Name = { de = "Clutch Pass Premium (Saison)", en = "Clutch Pass Premium (Season)" },
		Grant = { PassPremium = true },
		PerSeason = true,
		Fallback = { Gems = 500 },
		Random = false,
	},
	{
		Key = "PassBundle",
		Id = 0,
		Price = 899,
		Kind = "Pass",
		Icon = "🎟️",
		Name = { de = "Clutch Pass Premium + 10 Stufen", en = "Clutch Pass Premium + 10 Tiers" },
		Grant = { PassPremium = true, PassTiers = 10 },
		PerSeason = true,
		Fallback = { PassTiers = 10, Gems = 500 },
		Random = false,
	},
	{
		Key = "PassTier1",
		Id = 0,
		Price = 49,
		Kind = "Tiers",
		Icon = "⏫",
		Name = { de = "+1 Pass-Stufe", en = "+1 Pass Tier" },
		Grant = { PassTiers = 1 },
		Random = false,
	},
	{
		Key = "PassTier10",
		Id = 0,
		Price = 349,
		Kind = "Tiers",
		Icon = "⏫",
		Name = { de = "+10 Pass-Stufen", en = "+10 Pass Tiers" },
		Grant = { PassTiers = 10 },
		Random = false,
	},
	{
		Key = "XPBoost30",
		Id = 0,
		Price = 39,
		Kind = "Boost",
		Icon = "🚀",
		Name = { de = "XP-Boost 30 min", en = "XP Boost 30 min" },
		Grant = { XpBoostSeconds = 1800 },
		Random = false,
	},
	{
		Key = "XPBoost120",
		Id = 0,
		Price = 99,
		Kind = "Boost",
		Icon = "🚀",
		Name = { de = "XP-Boost 2 h", en = "XP Boost 2 h" },
		Grant = { XpBoostSeconds = 7200 },
		Random = false,
	},
	{
		Key = "PartyBoost",
		Id = 0,
		Price = 199,
		Kind = "Party",
		Icon = "🎉",
		Name = { de = "Party-Boost (ganzer Server)", en = "Party Boost (whole server)" },
		Grant = { Cosmetics = { "TT_PartyStarter" } },
		PartyBoost = true,
		Random = false,
	},
	{
		Key = "Support49",
		Id = 0,
		Price = 49,
		Kind = "Support",
		Icon = "❤️",
		Name = { de = "Unterstütze den Entwickler", en = "Support the Dev" },
		Grant = { Cosmetics = { "TT_Supporter" } },
		Supporter = true,
		Random = false,
	},
	{
		Key = "Support499",
		Id = 0,
		Price = 499,
		Kind = "Support",
		Icon = "💖",
		Name = { de = "Unterstütze den Entwickler (groß)", en = "Support the Dev (big)" },
		Grant = { Cosmetics = { "TT_Supporter" } },
		Supporter = true,
		Random = false,
	},
}

-- ---------------------------------------------------------------------
-- 3) KATALOG & TÄGLICH IM RAMPENLICHT (B19, B21.1)
-- ---------------------------------------------------------------------
Shop.CatalogPrices = { Common = 120, Rare = 250, Epic = 500, Legendary = 1000, Mythic = 2200 }
Shop.GemPacks = { 120, 250, 500, 1000, 2200, 5000 } -- B23.4: jeder Listenpreis = genau ein Paket
Shop.FeaturedDiscount = 0.2 -- −20 % auf die 6 Rampenlicht-Items (Rotation nach UTC-Tag, überall gleich)
Shop.FeaturedSlots = 6

-- ---------------------------------------------------------------------
-- 4) KISTE "Blaster-Kiste S1" (B20.1) – Gewichte in Basispunkten, Summe 10.000
--    Anzeige = Gewicht / 100 (%). Server würfelt NextInteger(1, 10000). Nur Einzel-Öffnungen.
-- ---------------------------------------------------------------------
Shop.Crates = {
	S1 = {
		Name = { de = "Blaster-Kiste S1", en = "Blaster Crate S1" },
		GemPrice = 120,
		KeyPrice = 1,
		Items = {
			-- Common 10 × 5,00 % = 50 %
			{ Id = "W_Mint", Weight = 500, Rarity = "Common" },
			{ Id = "W_Sky", Weight = 500, Rarity = "Common" },
			{ Id = "W_Sunny", Weight = 500, Rarity = "Common" },
			{ Id = "W_Bubblegum", Weight = 500, Rarity = "Common" },
			{ Id = "W_Grape", Weight = 500, Rarity = "Common" },
			{ Id = "W_Charcoal", Weight = 500, Rarity = "Common" },
			{ Id = "C_Duck", Weight = 500, Rarity = "Common" },
			{ Id = "C_Dice", Weight = 500, Rarity = "Common" },
			{ Id = "C_Star", Weight = 500, Rarity = "Common" },
			{ Id = "C_Heart", Weight = 500, Rarity = "Common" },
			-- Rare 6 × 5,00 % = 30 %
			{ Id = "W_Ocean", Weight = 500, Rarity = "Rare" },
			{ Id = "W_Lemonade", Weight = 500, Rarity = "Rare" },
			{ Id = "W_Cherry", Weight = 500, Rarity = "Rare" },
			{ Id = "W_ToyCamo", Weight = 500, Rarity = "Rare" },
			{ Id = "S_Scatter_BubbleBath", Weight = 500, Rarity = "Rare" },
			{ Id = "T_Gold", Weight = 500, Rarity = "Rare" },
			-- Epic 5 × 2,80 % = 14 %
			{ Id = "W_NeonGrid", Weight = 280, Rarity = "Epic" },
			{ Id = "W_Candy", Weight = 280, Rarity = "Epic" },
			{ Id = "S_PopRifle_WaterBlaster", Weight = 280, Rarity = "Epic" },
			{ Id = "S_BuzzSMG_HairDryer", Weight = 280, Rarity = "Epic" },
			{ Id = "F_IceCube", Weight = 280, Rarity = "Epic" },
			-- Legendary 2 × 2,50 % = 5 %
			{ Id = "S_Longshot_PoolNoodle", Weight = 250, Rarity = "Legendary" },
			{ Id = "F_GoldStatue", Weight = 250, Rarity = "Legendary" },
			-- Mythic 1 × 1,00 % = 1 %
			{ Id = "S_PopGrenade_RubberDuck", Weight = 100, Rarity = "Mythic" },
		},
		-- Garantie: nach 29 Öffnungen ohne Legendary/Mythic würfelt die 30. nur unter diesen
		PityAfter = 29,
		PityRarities = { "Legendary", "Mythic" },
	},
}
Shop.CrateOrder = { "S1" }

-- Duplikate -> Splitter, Splitter-Shop-Preise (B20.1)
Shop.DupeShards = { Common = 20, Rare = 50, Epic = 150, Legendary = 400, Mythic = 800 }
Shop.ShardPrices = { Common = 100, Rare = 250, Epic = 600, Legendary = 1500, Mythic = 3000 }

-- ---------------------------------------------------------------------
-- 5) LOADOUT-VORLAGEN, ANGEBOTE, PASS-REGELN, BOOSTS
-- ---------------------------------------------------------------------
Shop.PresetSlotCoins = 5000 -- Loadout-Platz 4 und 5 je 5.000 Münzen
Shop.Presets = { Base = 3, LoadoutPlus = 8, CoinSlotsMax = 2, NameMax = 16 }
Shop.StarterOfferHours = 72 -- Starter-Karte nach dem Angebot 72 h im Shop
Shop.MaxOffersPerSession = 1 -- max. 1 Angebots-Popup pro Sitzung (B23.1)
Shop.TierGemFallback = 40 -- Pass-Stufen über dem Maximum -> 40 Gems je Stufe
Shop.PassOwnedGems = 500 -- Premium schon besessen -> 500 Gems
Shop.XpBoostCapSeconds = 86400 -- XP-Boost höchstens 24 h im Voraus
Shop.PartyBoost = { Seconds = 900, CapSeconds = 3600 } -- 15 min pro Kauf, stapelbar bis 60 min
Shop.MaxBalance = 1000000000 -- Obergrenze jeder Währung (Schutz vor Überlauf/kaputten Daten)

-- =====================================================================
-- 6) NACHSCHLAGEN (doppelte Keys/Ids = Fehler beim Laden)
-- =====================================================================
Shop.ProductsByKey = {} :: { [string]: any }
Shop.ProductsById = {} :: { [number]: any }
Shop.PassesByKey = {} :: { [string]: any }
Shop.PassesById = {} :: { [number]: any }

for _, product in ipairs(Shop.Products) do
	assert(Shop.ProductsByKey[product.Key] == nil, "[Config.Shop] Doppelter Produkt-Key: " .. product.Key)
	Shop.ProductsByKey[product.Key] = product
	if product.Id ~= 0 then
		assert(Shop.ProductsById[product.Id] == nil, "[Config.Shop] Doppelte Produkt-Id: " .. tostring(product.Id))
		Shop.ProductsById[product.Id] = product
	end
end
for _, pass in ipairs(Shop.GamePasses) do
	assert(Shop.PassesByKey[pass.Key] == nil, "[Config.Shop] Doppelter Pass-Key: " .. pass.Key)
	Shop.PassesByKey[pass.Key] = pass
	if pass.Id ~= 0 then
		assert(Shop.PassesById[pass.Id] == nil, "[Config.Shop] Doppelte Pass-Id: " .. tostring(pass.Id))
		Shop.PassesById[pass.Id] = pass
	end
end

local crateIndex: { [string]: { [string]: any } } = {}
local anyCrateItem: { [string]: boolean } = {}
for crateKey, crate in pairs(Shop.Crates) do
	local index = {}
	for _, item in ipairs(crate.Items) do
		index[item.Id] = item
		anyCrateItem[item.Id] = true
	end
	crateIndex[crateKey] = index
end

function Shop.CrateItem(crateKey: string, id: string): any
	local index = crateIndex[crateKey]
	return index and index[id]
end

function Shop.IsCrateItem(id: string): boolean
	return anyCrateItem[id] == true
end

-- =====================================================================
-- 7) SAISON-HILFE (gleiche Regel wie B21.2, ohne Roblox-APIs)
-- =====================================================================
local function daysFromCivil(year: number, month: number, day: number): number
	local y = year - (if month <= 2 then 1 else 0)
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp = (month + 9) % 12
	local doy = math.floor((153 * mp + 2) / 5) + day - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

-- "2026-10-15T00:00:00Z" -> Sekunden seit 1970 (UTC); kaputt -> nil
function Shop.ParseUtc(text: string): number?
	if type(text) ~= "string" then
		return nil
	end
	local y, mo, d, h, mi, s = string.match(text, "^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)Z$")
	if not y then
		return nil
	end
	local year, month, day = tonumber(y) :: number, tonumber(mo) :: number, tonumber(d) :: number
	local hour, minute, second = tonumber(h) :: number, tonumber(mi) :: number, tonumber(s) :: number
	if month < 1 or month > 12 or day < 1 or day > 31 or hour > 23 or minute > 59 or second > 59 then
		return nil
	end
	return daysFromCivil(year, month, day) * 86400 + hour * 3600 + minute * 60 + second
end

-- Aktive Saison: Datumsfenster passt -> diese; sonst die mit dem jüngsten StartUtc ≤ jetzt;
-- liegt jetzt vor allen -> die erste (Saison 1). Keine Saisons -> 1.
function Shop.SeasonIdAt(seasons: any, now: number): number
	if type(seasons) ~= "table" or #seasons == 0 then
		return 1
	end
	local bestId, bestStart = nil, -math.huge
	local firstId, firstStart = nil, math.huge
	for _, season in ipairs(seasons) do
		local id = tonumber(season.Id)
		local start = Shop.ParseUtc(season.StartUtc)
		local finish = Shop.ParseUtc(season.EndUtc)
		if id and start then
			if finish and now >= start and now < finish then
				return id
			end
			if start <= now and start > bestStart then
				bestId, bestStart = id, start
			end
			if start < firstStart then
				firstId, firstStart = id, start
			end
		end
	end
	return bestId or firstId or 1
end

-- =====================================================================
-- 7b) PREISE & RAMPENLICHT – EINE Regel für Server (ShopService) UND Anzeige (Client-Shop)
--     cosmetics = Config.Cosmetics (wird übergeben, damit dieses Modul ohne Roblox-Typen lädt)
-- =====================================================================
-- Preis eines Kosmetik-Items in einer Währung; nil = so nicht kaufbar.
--   Coins:  nur Münz-Wraps (Price = { Coins = n })
--   Gems:   Katalog-Items, Kisten-Items (B20.1: jedes Kisten-Item auch direkt) und Pass-Items NACH ihrer Saison
--   Shards: nur Kisten-Items (Splitter-Shop)
--   featured = true -> Rampenlicht-Rabatt (−20 %) auf den Gem-Preis
function Shop.PriceOf(cosmetics: any, id: string, currency: string, seasonId: number, featured: boolean?): number?
	if type(cosmetics) ~= "table" or type(cosmetics.ById) ~= "table" or type(id) ~= "string" then
		return nil
	end
	local def = cosmetics.ById[id]
	if def == nil or def.Kind == "Title" then
		return nil
	end
	local exclusive = type(cosmetics.IsExclusive) == "function" and cosmetics.IsExclusive(id, seasonId) == true
	if exclusive then
		return nil -- Pass-Item während seiner Saison: nur über den Pass
	end
	if currency == "Coins" then
		local price = type(def.Price) == "table" and def.Price.Coins or nil
		return if type(price) == "number" and price > 0 then price else nil
	elseif currency == "Gems" then
		local buyable = def.Source == "Catalog" or def.Source == "Pass" or Shop.IsCrateItem(id)
		local price = Shop.CatalogPrices[def.Rarity]
		if not buyable or type(price) ~= "number" then
			return nil
		end
		if featured then
			price = math.floor(price * (1 - Shop.FeaturedDiscount) + 0.5)
		end
		return price
	elseif currency == "Shards" then
		if not Shop.IsCrateItem(id) then
			return nil
		end
		local price = Shop.ShardPrices[def.Rarity]
		return if type(price) == "number" then price else nil
	end
	return nil
end

-- Alle Items mit Gem-Preis (Kandidaten fürs Rampenlicht), alphabetisch -> überall gleiche Reihenfolge
function Shop.FeaturedPool(cosmetics: any, seasonId: number): { string }
	local pool: { string } = {}
	if type(cosmetics) ~= "table" or type(cosmetics.ById) ~= "table" then
		return pool
	end
	for id in pairs(cosmetics.ById) do
		if Shop.PriceOf(cosmetics, id, "Gems", seasonId, false) ~= nil then
			table.insert(pool, id)
		end
	end
	table.sort(pool)
	return pool
end

-- 6 Items des UTC-Tages: deterministisch (MINSTD-Zufall mit dem Tag als Saat) -> auf allen Servern gleich
function Shop.PickFeatured(pool: { string }, day: number, count: number?): { string }
	local list = table.clone(pool)
	local n = math.min(count or Shop.FeaturedSlots, #list)
	local seed = (math.floor(math.abs(tonumber(day) or 0)) % 2147483646) + 1
	local picked: { string } = {}
	for i = 1, n do
		seed = (seed * 48271) % 2147483647 -- Produkt < 2^47: exakt in Luau-Zahlen
		local j = i + (seed % (#list - i + 1))
		list[i], list[j] = list[j], list[i]
		table.insert(picked, list[i])
	end
	return picked
end

-- =====================================================================
-- 8) PRÜFEN (Config.Validate sammelt das; leere Liste = alles ok)
-- =====================================================================
-- Robux dürfen NIE diese Felder geben (Muss-Regel 4)
Shop.ForbiddenRobuxFields = { "Coins", "Keys", "Shards", "Weapons", "FreeWeaponPicks" }
local GRANT_FIELDS = {
	Coins = "number",
	Gems = "number",
	Keys = "number",
	Shards = "number",
	Weapons = "table",
	Cosmetics = "table",
	FreeWeaponPicks = "number",
	PassPremium = "boolean",
	PassTiers = "number",
	XpBoostSeconds = "number",
}
Shop.GrantFields = GRANT_FIELDS

local function checkName(errors: { string }, path: string, name: any)
	if type(name) ~= "table" or type(name.de) ~= "string" or type(name.en) ~= "string" then
		table.insert(errors, path .. ": { de, en } erwartet")
	end
end

local function checkGrant(errors: { string }, path: string, grant: any, cosmetics: any)
	if type(grant) ~= "table" then
		table.insert(errors, path .. ": Tabelle erwartet")
		return
	end
	for field, value in pairs(grant) do
		local expected = GRANT_FIELDS[field]
		if expected == nil then
			table.insert(errors, ("%s.%s: unbekanntes Grant-Feld"):format(path, tostring(field)))
		elseif type(value) ~= expected then
			table.insert(errors, ("%s.%s: %s erwartet"):format(path, tostring(field), expected))
		elseif expected == "number" and (value < 0 or value % 1 ~= 0) then
			table.insert(errors, ("%s.%s: ganze Zahl ≥ 0 erwartet"):format(path, tostring(field)))
		end
	end
	for _, field in ipairs(Shop.ForbiddenRobuxFields) do
		if grant[field] ~= nil then
			table.insert(errors, ("%s.%s: Robux dürfen nie %s geben (kein Pay-to-Win)"):format(path, field, field))
		end
	end
	if type(grant.Cosmetics) == "table" and type(cosmetics) == "table" and type(cosmetics.ById) == "table" then
		for _, id in ipairs(grant.Cosmetics) do
			if cosmetics.ById[id] == nil then
				table.insert(errors, ("%s.Cosmetics: unbekannte Id %s"):format(path, tostring(id)))
			end
		end
	end
end

function Shop.Validate(Config: any): { string }
	local errors: { string } = {}
	local cosmetics = Config and Config.Cosmetics
	local packs: { [number]: boolean } = {}
	for _, n in ipairs(Shop.GemPacks) do
		packs[n] = true
	end
	-- Pässe
	for i, pass in ipairs(Shop.GamePasses) do
		local path = ("Config.Shop.GamePasses[%d]"):format(i)
		if type(pass.Key) ~= "string" then
			table.insert(errors, path .. ".Key: Text erwartet")
		end
		if type(pass.Id) ~= "number" or pass.Id < 0 or pass.Id % 1 ~= 0 then
			table.insert(errors, path .. ".Id: ganze Zahl ≥ 0 erwartet (0 = noch nicht eingerichtet)")
		end
		if type(pass.Price) ~= "number" or pass.Price <= 0 then
			table.insert(errors, path .. ".Price: Zahl > 0 erwartet")
		end
		checkName(errors, path .. ".Name", pass.Name)
		checkName(errors, path .. ".Desc", pass.Desc)
	end
	-- Produkte
	for i, product in ipairs(Shop.Products) do
		local path = ("Config.Shop.Products[%d] (%s)"):format(i, tostring(product.Key))
		if type(product.Id) ~= "number" or product.Id < 0 or product.Id % 1 ~= 0 then
			table.insert(errors, path .. ".Id: ganze Zahl ≥ 0 erwartet (0 = noch nicht eingerichtet)")
		end
		if type(product.Price) ~= "number" or product.Price <= 0 then
			table.insert(errors, path .. ".Price: Zahl > 0 erwartet")
		end
		checkName(errors, path .. ".Name", product.Name)
		checkGrant(errors, path .. ".Grant", product.Grant, cosmetics)
		if product.Fallback ~= nil then
			checkGrant(errors, path .. ".Fallback", product.Fallback, cosmetics)
		end
		if (product.Once or product.PerSeason) and product.Fallback == nil then
			table.insert(errors, path .. ".Fallback: nötig bei Once/PerSeason")
		end
		if product.Random ~= false then
			table.insert(errors, path .. ".Random: kein Robux-Produkt darf ein Zufallsitem geben (false setzen)")
		end
		if product.FirstBonus and (type(product.Grant) ~= "table" or type(product.Grant.Gems) ~= "number") then
			table.insert(errors, path .. ".FirstBonus: nur für Gem-Pakete")
		end
		if product.Kind == "Gems" and type(product.Grant) == "table" and not packs[product.Grant.Gems] then
			table.insert(errors, path .. ".Grant.Gems: muss ein Paket aus Config.Shop.GemPacks sein")
		end
	end
	-- Katalog-Preise = genau ein Gem-Paket (B23.4)
	for rarity, price in pairs(Shop.CatalogPrices) do
		if not packs[price] then
			table.insert(errors, ("Config.Shop.CatalogPrices.%s: muss ein Gem-Paket sein"):format(rarity))
		end
	end
	if type(Shop.FeaturedDiscount) ~= "number" or Shop.FeaturedDiscount < 0 or Shop.FeaturedDiscount >= 1 then
		table.insert(errors, "Config.Shop.FeaturedDiscount: 0 ≤ x < 1 erwartet")
	end
	-- Kisten: Gewichte ganzzahlig > 0, Summe 10.000, Items existieren mit gleicher Rarity
	for crateKey, crate in pairs(Shop.Crates) do
		local path = "Config.Shop.Crates." .. crateKey
		checkName(errors, path .. ".Name", crate.Name)
		local total, seen = 0, {}
		for i, item in ipairs(crate.Items) do
			local ipath = ("%s.Items[%d]"):format(path, i)
			if type(item.Weight) ~= "number" or item.Weight <= 0 or item.Weight % 1 ~= 0 then
				table.insert(errors, ipath .. ".Weight: ganze Zahl > 0 erwartet")
			else
				total += item.Weight
			end
			if seen[item.Id] then
				table.insert(errors, ipath .. ": doppelte Id " .. tostring(item.Id))
			end
			seen[item.Id] = true
			if Shop.DupeShards[item.Rarity] == nil then
				table.insert(errors, ipath .. ".Rarity: unbekannt")
			end
			if type(cosmetics) == "table" and type(cosmetics.ById) == "table" then
				local def = cosmetics.ById[item.Id]
				if def == nil then
					table.insert(errors, ipath .. ": unbekannte Kosmetik " .. tostring(item.Id))
				elseif def.Rarity ~= item.Rarity then
					table.insert(
						errors,
						ipath .. ".Rarity: passt nicht zu Config.Cosmetics (" .. tostring(def.Rarity) .. ")"
					)
				elseif def.Source ~= "Catalog" and def.Source ~= "Coins" then
					table.insert(errors, ipath .. ": nur Katalog-/Münz-Items gehören in eine Kiste")
				end
			end
		end
		if total ~= 10000 then
			table.insert(errors, ("%s.Items: Gewichte ergeben %d statt 10000"):format(path, total))
		end
		if type(crate.GemPrice) ~= "number" or not packs[crate.GemPrice] then
			table.insert(errors, path .. ".GemPrice: muss ein Gem-Paket sein")
		end
		if type(crate.PityAfter) ~= "number" or crate.PityAfter < 1 then
			table.insert(errors, path .. ".PityAfter: Zahl ≥ 1 erwartet")
		end
		local pityCount = 0
		for _, item in ipairs(crate.Items) do
			if table.find(crate.PityRarities, item.Rarity) then
				pityCount += 1
			end
		end
		if pityCount == 0 then
			table.insert(errors, path .. ".PityRarities: keine Items dieser Rarity in der Kiste")
		end
	end
	for _, rarity in ipairs({ "Common", "Rare", "Epic", "Legendary", "Mythic" }) do
		if type(Shop.CatalogPrices[rarity]) ~= "number" then
			table.insert(errors, "Config.Shop.CatalogPrices." .. rarity .. ": fehlt")
		end
		if type(Shop.DupeShards[rarity]) ~= "number" then
			table.insert(errors, "Config.Shop.DupeShards." .. rarity .. ": fehlt")
		end
		if type(Shop.ShardPrices[rarity]) ~= "number" then
			table.insert(errors, "Config.Shop.ShardPrices." .. rarity .. ": fehlt")
		end
	end
	if Shop.MaxOffersPerSession ~= 1 then
		table.insert(errors, "Config.Shop.MaxOffersPerSession: B23.1 erlaubt genau 1 Angebot pro Sitzung")
	end
	if type(Shop.StarterOfferHours) ~= "number" or Shop.StarterOfferHours < 24 then
		table.insert(errors, "Config.Shop.StarterOfferHours: keine Timer unter 24 h (B23.3)")
	end
	return errors
end

return Shop
