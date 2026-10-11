-- =====================================================================
--  CLUTCH CLASH – Selbsttests Wirtschaft (Server/Tests/EconomyTests)
--  Besitzer: WP9 (Wirtschaft, Monetarisierung, Kosmetik). Vertrag: DESIGN.md WP9-Tests + C18.
--  Gibt { [testName]: (Services) -> () } zurück; jeder Fehler = FAIL (SelfTestService).
--  Prüft: Kisten-Gewichte/Anzeige, Grant/Spend-Atomik, Receipt-Replay (auch parallel), Policy-Gate,
--  Garantie bei Öffnung 30, Duplikat -> Splitter, Saison-Fallback-Kauf (PassPremium zweimal -> 500 Gems),
--  Erstkauf ×2, kein Robux-Grant mit Münzen/Schlüsseln/Waffen, Katalog-/Rampenlicht-Regeln, Boost-Deckel.
--  Arbeitet nur mit Test-Spielständen (DataService.DefaultData) – echte Spieler bleiben unberührt.
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Odds = require(Shared:WaitForChild("Odds"))

local SHOP: any = Config.Shop
local COSMETICS: any = Config.Cosmetics

local function eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(("%s erwartet %s, bekommen %s"):format(label or "Wert", tostring(expected), tostring(actual)), 2)
	end
end

local function truthy(value: any, label: string)
	if not value then
		error(label, 2)
	end
end

local function cores(services: any): (any, any)
	local shop = services and services.ShopService
	local monetization = services and services.MonetizationService
	assert(shop and shop.Core, "ShopService.Core fehlt")
	assert(monetization and monetization.Core, "MonetizationService.Core fehlt")
	return shop.Core, monetization.Core
end

-- frischer Test-Spielstand (DEFAULT_DATA aus WP1, sonst Minimal-Stand)
local function newData(services: any): any
	local dataService = services and services.DataService
	local data: any
	if dataService and type(dataService.DefaultData) == "function" then
		data = dataService.DefaultData()
	else
		data = {
			Coins = 0,
			Gems = 0,
			Keys = 0,
			Shards = 0,
			FreeWeaponPicks = 0,
			Weapons = { Owned = {} },
			Cosmetics = { Owned = {}, Equipped = {}, PerWeapon = {} },
			Crates = { Pity = 0, Opened = 0 },
			Boosts = { XP2Until = 0 },
			Loadouts = { Active = 1, Slots = 3, Presets = {} },
			Purchases = { Receipts = {}, PassSeasons = {}, FirstPack = {} },
		}
	end
	local shopCore = services.ShopService.Core
	shopCore.Ensure(data)
	return data
end

-- Zufall-Attrappe: immer der kleinste Wert (= erstes Item der jeweiligen Liste)
local LOW_RNG = {
	NextInteger = function(_self: any, lo: number, _hi: number): number
		return lo
	end,
}

local testId = 0
local function purchaseId(): string
	testId += 1
	return ("TEST-%d-%d"):format(os.time(), testId)
end

local FAKE_PLAYER = { Name = "Testspieler", UserId = 999001 }
local GEMS_PRODUCT = { Key = "TestGems", Id = 4242, Grant = { Gems = 120 }, FirstBonus = true, Random = false }

local function receiptEnv(data: any, opts: { SaveOk: boolean?, PrepareWait: number?, Counter: { n: number } }): any
	return {
		FindPlayer = function(userId: any): any
			return if userId == FAKE_PLAYER.UserId then FAKE_PLAYER else nil
		end,
		Product = function(productId: any): any
			return if productId == GEMS_PRODUCT.Id then GEMS_PRODUCT else nil
		end,
		WaitData = function(_p: any): any
			return data
		end,
		CurrentData = function(_p: any): any
			return data
		end,
		Prepare = function(_p: any, _product: any): any
			if opts.PrepareWait then
				task.wait(opts.PrepareWait)
			end
			return { SeasonId = 1 }
		end,
		Grant = function(_p: any, d: any, _product: any, _prepared: any): boolean
			opts.Counter.n += 1
			d.Gems += 120
			return true
		end,
		Save = function(_p: any): boolean
			return opts.SaveOk ~= false
		end,
		Wait = function(seconds: number)
			task.wait(seconds)
		end,
	}
end

local function receipt(id: string, productId: number?, playerId: number?): any
	return {
		PlayerId = playerId or FAKE_PLAYER.UserId,
		ProductId = productId or GEMS_PRODUCT.Id,
		PurchaseId = id,
		CurrencySpent = 99,
	}
end

local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted
local NOT_YET = Enum.ProductPurchaseDecision.NotProcessedYet

local Tests = {}

-- ---------------------------------------------------------------------
-- Config & Quoten
-- ---------------------------------------------------------------------
Tests["Kiste S1 Gewichte 10000 + Anzeige 100.00"] = function()
	local crate = SHOP.Crates.S1
	local ok, err = Odds.Validate(crate)
	truthy(ok, "Odds.Validate: " .. tostring(err))
	local sum = 0
	for i, row in ipairs(Odds.Table(crate)) do
		eq(row.Hundredths, crate.Items[i].Weight, "Anzeige = Gewicht " .. row.Id)
		sum += row.Hundredths
	end
	eq(sum, 10000, "Summe Hundertstel")
	local pitySum = 0
	for _, row in ipairs(Odds.PityTable(crate)) do
		pitySum += row.Hundredths
	end
	eq(pitySum, 10000, "Garantie-Summe")
end

Tests["Config.Shop + Config.Cosmetics Validate leer"] = function()
	local errors = SHOP.Validate(Config)
	eq(#errors, 0, "Shop-Fehler: " .. table.concat(errors, " | "))
	local cosErrors = COSMETICS.Validate(Config)
	eq(#cosErrors, 0, "Kosmetik-Fehler: " .. table.concat(cosErrors, " | "))
	-- Kisten-Items existieren in Config.Cosmetics mit gleicher Seltenheit, keins ist exklusiv
	for _, item in ipairs(SHOP.Crates.S1.Items) do
		local def = COSMETICS.ById[item.Id]
		truthy(def ~= nil, "Kisten-Item fehlt: " .. item.Id)
		eq(def.Rarity, item.Rarity, "Seltenheit " .. item.Id)
		truthy(COSMETICS.Exclusive[item.Id] == nil, "exklusives Item in der Kiste: " .. item.Id)
	end
end

-- ---------------------------------------------------------------------
-- Grant / Spend
-- ---------------------------------------------------------------------
Tests["Grant/Spend Atomik"] = function(services: any)
	local core = cores(services)
	local data = newData(services)
	data.Coins, data.Gems = 100, 50
	-- ungültige Grants ändern NICHTS
	local before = Util.DeepCopy(data)
	for _, bad in ipairs({
		{ Coins = -5 },
		{ Coins = 1.5 },
		{ Gems = 0 / 0 },
		{ Unbekannt = 1 },
		{ Coins = 10, Weapons = { "GibtEsNicht" } },
		{ Gems = 10, Cosmetics = { "X_Unbekannt" } },
		{ FreeWeaponPicks = -1, Weapons = {} },
	}) do
		local ok = core.ValidateGrant(data, bad)
		truthy(not ok, "ungültiger Grant wurde akzeptiert")
	end
	eq(data.Coins, before.Coins, "Coins unverändert")
	eq(data.Gems, before.Gems, "Gems unverändert")
	-- Spend: zu wenig -> false, nichts abgezogen
	truthy(not core.Spend(data, "Coins", 101), "Spend über Kontostand")
	eq(data.Coins, 100, "Coins nach Fehl-Spend")
	truthy(not core.Spend(data, "Coins", -1), "negativer Spend")
	truthy(not core.Spend(data, "Robux", 1), "unbekannte Währung")
	truthy(core.Spend(data, "Coins", 100), "Spend genau Kontostand")
	eq(data.Coins, 0, "Coins nach Spend")
	-- gültiger Grant
	local grant = { Coins = 250, Gems = 30, Keys = 2, Shards = 5, Cosmetics = { "W_Ocean" }, XpBoostSeconds = 600 }
	local ok, err = core.ValidateGrant(data, grant)
	truthy(ok, "gültiger Grant abgelehnt: " .. tostring(err))
	local now = os.time()
	core.ApplyGrant(data, grant, now, 0)
	eq(data.Coins, 250, "Coins")
	eq(data.Gems, 80, "Gems")
	eq(data.Keys, 2, "Keys")
	eq(data.Shards, 5, "Shards")
	eq(data.Cosmetics.Owned.W_Ocean, true, "Kosmetik")
	eq(data.Boosts.XP2Until, now + 600, "XP-Boost")
	-- Meisterschafts-Wrap bekommt keinen Besitz-Eintrag (B16.2)
	core.ApplyGrant(data, { Cosmetics = { "W_MBronze" } }, now, 0)
	eq(data.Cosmetics.Owned.W_MBronze, nil, "Meisterschafts-Wrap ohne Besitz")
	-- Obergrenze
	data.Gems = (SHOP.MaxBalance or 1e9) - 1
	core.ApplyGrant(data, { Gems = 100 }, now, 0)
	eq(data.Gems, SHOP.MaxBalance or 1e9, "Gem-Obergrenze")
end

Tests["XP-Boost höchstens 24 h, Party-Boost höchstens 60 min"] = function(services: any)
	local core, monCore = cores(services)
	local data = newData(services)
	local now = os.time()
	for _ = 1, 60 do
		core.ApplyGrant(data, { XpBoostSeconds = 7200 }, now, 0)
	end
	eq(data.Boosts.XP2Until, now + (SHOP.XpBoostCapSeconds or 86400), "XP-Boost-Deckel")
	local untilT = 0
	for _ = 1, 10 do
		untilT = monCore.ExtendParty(untilT, now)
	end
	eq(untilT, now + SHOP.PartyBoost.CapSeconds, "Party-Deckel")
	eq(monCore.ExtendParty(0, now), now + SHOP.PartyBoost.Seconds, "Party 15 min")
end

-- ---------------------------------------------------------------------
-- ProcessReceipt (B22.3)
-- ---------------------------------------------------------------------
Tests["Receipt-Replay gewährt genau einmal"] = function(services: any)
	local _, monCore = cores(services)
	local data = newData(services)
	local counter = { n = 0 }
	local env = receiptEnv(data, { Counter = counter })
	local id = purchaseId()
	eq(monCore.ProcessReceiptWith(receipt(id), env), GRANTED, "erster Aufruf")
	eq(monCore.ProcessReceiptWith(receipt(id), env), GRANTED, "Wiederholung")
	eq(monCore.ProcessReceiptWith(receipt(id), env), GRANTED, "dritter Aufruf")
	eq(counter.n, 1, "Gutschriften")
	eq(data.Gems, 120, "Gems nur einmal")
	truthy(monCore.HasReceipt(data, id), "Beleg vermerkt")
	eq(data.Purchases.RobuxSpent, 99, "RobuxSpent")
end

Tests["Receipt parallel (gleiche PurchaseId) gewährt einmal"] = function(services: any)
	local _, monCore = cores(services)
	local data = newData(services)
	local counter = { n = 0 }
	local env = receiptEnv(data, { Counter = counter, PrepareWait = 0.3 })
	local id = purchaseId()
	local results: { any } = {}
	for i = 1, 2 do
		task.spawn(function()
			results[i] = monCore.ProcessReceiptWith(receipt(id), env)
		end)
	end
	for _ = 1, 50 do
		if results[1] ~= nil and results[2] ~= nil then
			break
		end
		task.wait(0.1)
	end
	eq(results[1], GRANTED, "Aufruf 1")
	eq(results[2], GRANTED, "Aufruf 2 (wartet, erkennt Beleg)")
	eq(counter.n, 1, "Gutschriften")
end

Tests["Receipt: Spieler weg / unbekanntes Produkt / Speichern scheitert"] = function(services: any)
	local _, monCore = cores(services)
	local data = newData(services)
	local counter = { n = 0 }
	local env = receiptEnv(data, { Counter = counter })
	eq(monCore.ProcessReceiptWith(receipt(purchaseId(), nil, 12345), env), NOT_YET, "Spieler nicht da")
	eq(monCore.ProcessReceiptWith(receipt(purchaseId(), 777), env), NOT_YET, "unbekanntes Produkt")
	eq(counter.n, 0, "nichts gutgeschrieben")
	-- Speichern scheitert: NotProcessedYet, Beleg steht -> nächster Versuch ohne Doppel-Gutschrift
	local failing = receiptEnv(data, { Counter = counter, SaveOk = false })
	local id = purchaseId()
	eq(monCore.ProcessReceiptWith(receipt(id), failing), NOT_YET, "Save-Fehler")
	eq(counter.n, 1, "einmal gutgeschrieben")
	eq(monCore.ProcessReceiptWith(receipt(id), env), GRANTED, "Wiederholung nach Save-Fehler")
	eq(counter.n, 1, "keine Doppel-Gutschrift")
	-- Belegliste bleibt begrenzt
	for _ = 1, 70 do
		monCore.AddReceipt(data, purchaseId(), os.time())
	end
	truthy(#data.Purchases.Receipts <= (Config.Tech.ReceiptKeep or 60), "Belege begrenzt")
end

Tests["Saison-Fallback-Kauf: PassPremium zweimal -> 500 Gems"] = function(services: any)
	local _, monCore = cores(services)
	local data = newData(services)
	-- vor jeder Saison: Fallback-Regel liefert Saison 1
	local seasons = Config.Season and Config.Season.Seasons
	local season = SHOP.SeasonIdAt(seasons, 0)
	eq(season, 1, "Saison vor allen")
	local product = SHOP.ProductsByKey.PassPremium
	local grant1, info1 = monCore.BuildGrant(product, data, season, nil)
	eq(grant1.PassPremium, true, "erster Kauf: Premium")
	eq(info1.MarkSeason, true, "Saison wird vermerkt")
	data.Purchases.PassSeasons[tostring(season)] = true
	local grant2, info2 = monCore.BuildGrant(product, data, season, nil)
	eq(grant2.PassPremium, nil, "zweiter Kauf: kein Premium")
	eq(grant2.Gems, SHOP.PassOwnedGems, "zweiter Kauf: 500 Gems")
	eq(info2.Fallback, true, "Ersatz")
	-- Bundle schon besessen: 10 Stufen + 500 Gems
	local bundle = monCore.BuildGrant(SHOP.ProductsByKey.PassBundle, data, season, nil)
	eq(bundle.PassTiers, 10, "Bundle-Ersatz Stufen")
	eq(bundle.Gems, 500, "Bundle-Ersatz Gems")
	-- neue Saison: wieder Premium
	local grant3 = monCore.BuildGrant(product, data, season + 1, nil)
	eq(grant3.PassPremium, true, "neue Saison")
end

Tests["Erstkauf ×2 nur einmal, Starter-Paket zweimal -> 120 Gems"] = function(services: any)
	local _, monCore = cores(services)
	local data = newData(services)
	local gems = SHOP.ProductsByKey.Gems500
	local g1, i1 = monCore.BuildGrant(gems, data, 1, nil)
	eq(g1.Gems, 1000, "erster Kauf doppelt")
	eq(i1.FirstBonus, true, "Erstkauf-Flag")
	data.Purchases.FirstPack.Gems500 = true
	local g2 = monCore.BuildGrant(gems, data, 1, nil)
	eq(g2.Gems, 500, "zweiter Kauf normal")
	local starter = SHOP.ProductsByKey.StarterPack
	local s1, si1 = monCore.BuildGrant(starter, data, 1, nil)
	eq(s1.Gems, 250, "Starter Gems")
	eq(#s1.Cosmetics, 3, "Starter Kosmetik")
	eq(si1.MarkStarter, true, "Starter wird vermerkt")
	data.Purchases.Starter = true
	local s2 = monCore.BuildGrant(starter, data, 1, nil)
	eq(s2.Gems, 120, "Starter-Wiederholung")
	eq(s2.Cosmetics, nil, "Wiederholung ohne Kosmetik")
end

Tests["Kein Robux-Grant gibt Münzen, Schlüssel, Splitter oder Waffen"] = function(services: any)
	local _, monCore = cores(services)
	local forbidden = SHOP.ForbiddenRobuxFields
	for _, product in ipairs(SHOP.Products) do
		for _, bought in ipairs({ false, true }) do
			local data = newData(services)
			if bought then
				data.Purchases.Starter = true
				data.Purchases.PassSeasons["1"] = true
				data.Purchases.FirstPack[product.Key] = true
			end
			local grant = monCore.BuildGrant(product, data, 1, false)
			for _, field in ipairs(forbidden) do
				eq(grant[field], nil, product.Key .. "." .. field)
			end
		end
		eq(product.Random, false, product.Key .. " zufällig?")
	end
	-- Sanitize streicht verbotene Felder, auch wenn jemand die Config falsch ändert
	local clean = monCore.Sanitize({ Gems = 10, Coins = 999, Keys = 5, Shards = 1, Weapons = { "BuzzSMG" } })
	eq(clean.Gems, 10, "Gems bleiben")
	eq(clean.Coins, nil, "Coins gestrichen")
	eq(clean.Keys, nil, "Keys gestrichen")
	eq(clean.Shards, nil, "Shards gestrichen")
	eq(clean.Weapons, nil, "Waffen gestrichen")
end

-- ---------------------------------------------------------------------
-- Kisten: Policy-Gate, Garantie, Duplikate
-- ---------------------------------------------------------------------
Tests["Policy-Gate: Gem-Öffnung nur erlaubt, Schlüssel immer"] = function(services: any)
	local core = cores(services)
	local crate = SHOP.Crates.S1
	local data = newData(services)
	data.Gems, data.Keys = 1000, 1
	for case = 1, 2 do
		local value: boolean? = if case == 1 then false else nil -- eingeschränkt / unbekannt
		local ok, key = core.OpenCrate(data, crate, "Gems", value, LOW_RNG)
		truthy(not ok, "Gem-Öffnung trotz Einschränkung")
		eq(key, "shop.restricted", "Meldung")
		eq(data.Gems, 1000, "keine Gems abgezogen")
	end
	local okKey, _, result = core.OpenCrate(data, crate, "Key", false, LOW_RNG)
	truthy(okKey, "Schlüssel-Öffnung muss gehen")
	eq(data.Keys, 0, "Schlüssel abgezogen")
	eq(result.Id, crate.Items[1].Id, "Ergebnis")
	local okGems = core.OpenCrate(data, crate, "Gems", true, LOW_RNG)
	truthy(okGems, "Gem-Öffnung wenn erlaubt")
	eq(data.Gems, 1000 - crate.GemPrice, "Gems abgezogen")
	-- ohne Schlüssel
	local okNone, keyNone = core.OpenCrate(data, crate, "Key", true, LOW_RNG)
	truthy(not okNone, "Öffnung ohne Schlüssel")
	eq(keyNone, "shop.notEnoughKeys", "Meldung ohne Schlüssel")
end

Tests["Garantie greift bei Öffnung 30, Duplikate -> Splitter"] = function(services: any)
	local core = cores(services)
	local crate = SHOP.Crates.S1
	local data = newData(services)
	data.Keys = 30
	for i = 1, 29 do
		local ok, _, result = core.OpenCrate(data, crate, "Key", false, LOW_RNG)
		truthy(ok, "Öffnung " .. i)
		eq(result.WasPity, false, "keine Garantie bei Öffnung " .. i)
		eq(result.Duplicate, i > 1, "Duplikat bei Öffnung " .. i)
		if i > 1 then
			eq(result.Shards, SHOP.DupeShards.Common, "Splitter für Common-Duplikat")
		end
	end
	eq(data.Crates.Pity, 29, "Zähler nach 29")
	eq(data.Shards, 28 * SHOP.DupeShards.Common, "Splitter gesamt")
	local ok, _, result = core.OpenCrate(data, crate, "Key", false, LOW_RNG)
	truthy(ok, "Öffnung 30")
	eq(result.WasPity, true, "Garantie aktiv")
	truthy(result.Rarity == "Legendary" or result.Rarity == "Mythic", "Öffnung 30 ist " .. tostring(result.Rarity))
	eq(data.Crates.Pity, 0, "Zähler zurückgesetzt")
	eq(data.Crates.Opened, 30, "Öffnungen gezählt")
	-- echter Zufall: bei Zähler 29 immer Legendary/Mythic
	local rng = Random.new(7)
	for _ = 1, 100 do
		data.Crates.Pity = 29
		data.Keys = 1
		local okPity, _, res = core.OpenCrate(data, crate, "Key", false, rng)
		truthy(okPity and (res.Rarity == "Legendary" or res.Rarity == "Mythic"), "Garantie-Wurf")
	end
end

-- ---------------------------------------------------------------------
-- Katalog & Rampenlicht
-- ---------------------------------------------------------------------
Tests["Katalog-Kauf: Preis aus Config, exklusiv gesperrt, kein Doppelkauf"] = function(services: any)
	local core = cores(services)
	local data = newData(services)
	data.Gems, data.Coins, data.Shards = 5000, 5000, 5000
	local ok, key, price = core.BuyItem(data, "W_Ocean", "Gems", 1, false)
	truthy(ok, "Kauf W_Ocean: " .. tostring(key))
	eq(price, SHOP.CatalogPrices.Rare, "Rare-Preis")
	eq(data.Gems, 5000 - SHOP.CatalogPrices.Rare, "Gems abgezogen")
	local again, keyAgain = core.BuyItem(data, "W_Ocean", "Gems", 1, false)
	truthy(not again, "Doppelkauf")
	eq(keyAgain, "shop.owned", "Doppelkauf-Meldung")
	local excl, keyExcl = core.BuyItem(data, "C_Ghost", "Gems", 1, false)
	truthy(not excl, "Pass-Item in seiner Saison")
	eq(keyExcl, "shop.exclusive", "Exklusiv-Meldung")
	local okLater = core.BuyItem(data, "C_Ghost", "Gems", 2, false)
	truthy(okLater, "Pass-Item nach der Saison im Katalog")
	local okCoins, _, coinPrice = core.BuyItem(data, "W_Mint", "Coins", 1, false)
	truthy(okCoins, "Münz-Wrap")
	eq(coinPrice, 1500, "Münz-Preis")
	local okShards, _, shardPrice = core.BuyItem(data, "S_PopGrenade_RubberDuck", "Shards", 1, false)
	truthy(okShards, "Mythic-Kisten-Item für Splitter")
	eq(shardPrice, SHOP.ShardPrices.Mythic, "Splitter-Preis")
	eq(data.Shards, 5000 - SHOP.ShardPrices.Mythic, "Splitter abgezogen")
	local mastery, keyMastery = core.BuyItem(data, "W_MGold", "Gems", 1, false)
	truthy(not mastery, "Meisterschafts-Wrap kaufbar?")
	eq(keyMastery, "shop.notForSale", "Meisterschaft nicht kaufbar")
	local vip = core.BuyItem(data, "W_VIPGold", "Gems", 1, false)
	truthy(not vip, "VIP-Wrap kaufbar?")
	local broke = newData(services)
	local okBroke, keyBroke = core.BuyItem(broke, "W_Ocean", "Gems", 1, false)
	truthy(not okBroke, "Kauf ohne Gems")
	eq(keyBroke, "shop.notEnoughGems", "Meldung ohne Gems")
end

Tests["Rampenlicht: 6 verschiedene kaufbare Items, deterministisch"] = function(services: any)
	local core = cores(services)
	local day = Util.UtcDay()
	local a = core.Featured(day, 1)
	local b = core.Featured(day, 1)
	eq(#a, SHOP.FeaturedSlots, "Anzahl")
	eq(table.concat(a, ","), table.concat(b, ","), "deterministisch")
	local seen = {}
	for _, id in ipairs(a) do
		truthy(not seen[id], "doppelt: " .. id)
		seen[id] = true
		local full = SHOP.PriceOf(COSMETICS, id, "Gems", 1, false)
		local discounted = SHOP.PriceOf(COSMETICS, id, "Gems", 1, true)
		truthy(full ~= nil and discounted ~= nil and discounted < full, "Rabatt " .. id)
		truthy(not COSMETICS.IsExclusive(id, 1), "exklusiv im Rampenlicht: " .. id)
	end
end

Tests["Loadout-Vorlagen: Basis 3, Münz-Plätze bis 5, Loadout+ 8"] = function(services: any)
	local core = cores(services)
	local data = newData(services)
	eq(core.PresetMax(data, false), SHOP.Presets.Base, "Basis")
	data.Loadouts.Slots = 99
	core.Ensure(data)
	eq(data.Loadouts.Slots, SHOP.Presets.Base + SHOP.Presets.CoinSlotsMax, "geklemmt")
	eq(core.PresetMax(data, true), SHOP.Presets.LoadoutPlus, "Loadout+")
	local preset = core.EnsurePreset(data, 5)
	truthy(type(preset) == "table" and type(preset.P) == "string", "Vorlage 5 angelegt")
	local loadout = core.PresetLoadout(preset)
	truthy(type(loadout.Primary) == "string" and type(loadout.Utility) == "string", "Loadout aus Vorlage")
end

return Tests
