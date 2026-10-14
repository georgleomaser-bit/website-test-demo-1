-- =====================================================================
--  AKYTEX TYCOON – Selbsttests Monetarisierung & CR-Konto (Server/Tests/EconomyTests)
--  Besitzer: WP10 (Monetarisierung, Shop, CR-Konto). Vertrag: DESIGN.md §D WP10 "Abnahme"/"Tests", §C11.4 Punkte 5–6
--  (SelfTest "Firewall" byte-gleich, "NoPaidRandom"), §C17 (Beleg-Idempotenz: doppelt + gleichzeitig).
--  SelfTestService lädt dieses Modul und ruft jede Funktion mit Services auf; jeder Fehler = FAIL.
--  Arbeitet nur mit Test-Spielständen (Kopien von DataService.DefaultData) und Test-Attrappen – echte Spieler bleiben
--  unberührt. Einzige Ausnahme: der Live-Idempotenz-Test läuft nur mit einem geladenen Studio-Spieler im NoSave-Modus.
--
--  Prüft: Config (14 Pässe, 17 Produkte, Validate leer) · Belege (Wiederholung, gleichzeitig, Spieler weg, unbekanntes
--  Produkt, Speichern scheitert, Belegliste begrenzt) · Grant alles-oder-nichts · Sanitize · Firewall byte-gleich
--  (jedes Produkt + Wiederholung, jeder Pass, jede Saison-Stufe beider Spuren, Club-Tagesgabe, jeder Code, Admin-/
--  Event-Gutschriften) · NoPaidRandom · Paket/Pässe-Faktor (x2 + x3 = x4, echter Rabatt) · Starter einmalig ·
--  Bau-Gutschein max(Angebot, Neu) + Angebots-Ablauf · Angebots-Regeln · Geschenk-Gate fail-closed · CR-Konto
--  (Whitelist, Ganzzahl, Deckel 9e15) · Bullen-Parade-Deckel · Saison-Premium zweimal · Boutique-Rotation.
-- =====================================================================

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))

local SHOP: any = Config.Shop
local MAX_MONEY = 9e15

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
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

-- rekursiver Vergleich (gleiche Typen, gleiche Werte, gleiche Schlüssel) -> (gleich, Pfad der Abweichung)
local function deepEqual(a: any, b: any, path: string, depth: number?): (boolean, string?)
	local level = depth or 0
	if level > 16 then
		return false, path .. " (zu tief)"
	end
	if type(a) ~= type(b) then
		return false, path
	end
	if type(a) ~= "table" then
		if a ~= b and not (a ~= a and b ~= b) then
			return false, path
		end
		return true, nil
	end
	for key, value in pairs(a) do
		local ok, where = deepEqual(value, b[key], path .. "." .. tostring(key), level + 1)
		if not ok then
			return false, where
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false, path .. "." .. tostring(key)
		end
	end
	return true, nil
end

local function serviceModule(services: any, name: string): any
	local svc = services and services[name]
	if svc then
		return svc
	end
	local module = script.Parent.Parent:WaitForChild("Services"):FindFirstChild(name)
	assert(module and module:IsA("ModuleScript"), name .. " fehlt")
	return require(module) :: any
end

local function cores(services: any): (any, any)
	local shop = serviceModule(services, "ShopService")
	local monetization = serviceModule(services, "MonetizationService")
	assert(shop.Core, "ShopService.Core fehlt")
	assert(monetization.Core, "MonetizationService.Core fehlt")
	return shop.Core, monetization.Core
end

-- frischer Test-Spielstand (DEFAULT_DATA aus WP1, sonst Minimal-Stand mit Depot/Prog-Attrappe)
local function newData(services: any): any
	local dataService = services and services.DataService
	local data: any
	if dataService and type(dataService.DefaultData) == "function" then
		data = dataService.DefaultData()
	else
		data = {
			Credits = 0,
			Sessions = 0,
			Depot = { V = 1, Cash = 2500000, Basis = 2500000, Pos = {}, Orders = {}, Bots = {} },
			Prog = { Xp = 0, Licence = 1, KH = {}, Ruf = 0, Titles = {} },
			Tower = { Floors = {}, Build = {}, Express = {}, Instant = 0 },
			Garage = { Cars = {} },
			Life = { Watches = {}, Accessories = {} },
			Storage = { Decor = {} },
			Season = { Id = 1, Xp = 0, Premium = false },
			Boosts = { X2 = 0, X5 = 0, Bull = 0 },
			Purchases = { Receipts = {}, RobuxSpent = 0, Starter = false, PassSeasons = {}, Quote = {} },
			Stats = { LifetimeCredits = 0 },
			Flags = {},
		}
	end
	local shopCore = cores(services)
	shopCore.Ensure(data)
	return data
end

-- alles, was Robux NIE berühren dürfen (§C11.4 #5): Depot, Depot.Bots, Prog.Licence/Xp/KnowHow/KH/Ruf
local function firewallSnapshot(data: any): any
	local prog = if type(data.Prog) == "table" then data.Prog else {}
	local depot = data.Depot
	return Util.DeepCopy({
		Depot = depot,
		Bots = if type(depot) == "table" then depot.Bots else nil,
		Licence = prog.Licence,
		Xp = prog.Xp,
		KnowHow = prog.KnowHow,
		KH = prog.KH,
		Ruf = prog.Ruf,
	})
end

local function assertFirewall(before: any, data: any, label: string)
	local ok, where = deepEqual(before, firewallSnapshot(data), "Firewall")
	truthy(ok, label .. ": Depot/Lizenz/XP/KH/Ruf verändert bei " .. tostring(where))
end

local function noForbidden(grant: any, label: string)
	for _, field in ipairs(SHOP.ForbiddenRobuxFields) do
		eq(grant[field], nil, label .. "." .. field)
	end
end

local function seasonNow(): number
	return SHOP.SeasonIdAt(Config.Season, os.time())
end

-- ---------------------------------------------------------------------
-- BELEG-ATTRAPPEN (Core.ProcessReceiptWith mit austauschbarer Umgebung)
-- ---------------------------------------------------------------------
local FAKE_PLAYER = { Name = "Testspieler", UserId = 999001, DisplayName = "Testspieler" }
local TEST_PRODUCT = {
	Key = "TestVoucher",
	Id = 4242,
	Kind = "Voucher",
	Voucher = { Minutes = 30, Min = 5000 },
	Random = false,
}

local testId = 0
local function purchaseId(): string
	testId += 1
	return ("TEST-%d-%d-%s"):format(os.time(), testId, string.sub(HttpService:GenerateGUID(false), 1, 8))
end

local function receiptEnv(
	services: any,
	data: any,
	opts: { SaveOk: boolean?, PrepareWait: number?, Counter: { n: number } }
): any
	local shopCore = cores(services)
	return {
		FindPlayer = function(userId: any): any
			return if userId == FAKE_PLAYER.UserId then FAKE_PLAYER else nil
		end,
		Product = function(productId: any): any
			return if productId == TEST_PRODUCT.Id then TEST_PRODUCT else nil
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
			return { SeasonId = 1, Steady = 0 }
		end,
		Grant = function(_p: any, d: any, _product: any, _prepared: any): boolean
			opts.Counter.n += 1
			local ok = shopCore.Credit(d, 5000, "Purchase")
			return ok
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
		ProductId = productId or TEST_PRODUCT.Id,
		PurchaseId = id,
		CurrencySpent = 49,
	}
end

local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted
local NOT_YET = Enum.ProductPurchaseDecision.NotProcessedYet

local Tests = {}

-- ---------------------------------------------------------------------
-- CONFIG
-- ---------------------------------------------------------------------
Tests["Config.Shop: 14 Pässe, 17 Produkte, Validate leer"] = function()
	eq(#SHOP.GamePasses, 14, "Gamepässe")
	eq(#SHOP.Products, 17, "Developer Products")
	local errors = SHOP.Validate(Config)
	eq(#errors, 0, "Shop-Fehler: " .. table.concat(errors, " | "))
	truthy(type(SHOP.Subscription) == "table" and type(SHOP.Subscription.Id) == "string", "Abo-Eintrag")
	for _, key in ipairs({ "CreditsS", "CreditsM", "CreditsL", "CreditsXL" }) do
		eq(SHOP.ProductsByKey[key].Kind, "Voucher", key)
	end
	eq(SHOP.QuoteSeconds, 600, "Angebot 10 min")
	eq(SHOP.MaxOffersPerSession, 1, "max. 1 Angebot je Sitzung")
end

-- ---------------------------------------------------------------------
-- BELEGE (§C11.1, Abnahme 1)
-- ---------------------------------------------------------------------
Tests["Beleg: Wiederholung gewährt genau einmal"] = function(services: any)
	local _, monCore = cores(services)
	local data = newData(services)
	local counter = { n = 0 }
	local env = receiptEnv(services, data, { Counter = counter })
	local id = purchaseId()
	eq(monCore.ProcessReceiptWith(receipt(id), env), GRANTED, "erster Aufruf")
	eq(monCore.ProcessReceiptWith(receipt(id), env), GRANTED, "Wiederholung")
	eq(monCore.ProcessReceiptWith(receipt(id), env), GRANTED, "dritter Aufruf")
	eq(counter.n, 1, "Gutschriften")
	eq(data.Credits, 5000, "CR nur einmal")
	truthy(monCore.HasReceipt(data, id), "Beleg vermerkt")
	eq(data.Purchases.RobuxSpent, 49, "RobuxSpent")
	local last = data.Purchases.Receipts[#data.Purchases.Receipts]
	truthy(type(last) == "table" and type(last.Key) == "string" and last.Key ~= "", "Beleg nennt den Artikel (Admin)")
end

Tests["Beleg: gleichzeitig mit gleicher PurchaseId genau einmal"] = function(services: any)
	local _, monCore = cores(services)
	local data = newData(services)
	local counter = { n = 0 }
	local env = receiptEnv(services, data, { Counter = counter, PrepareWait = 0.3 })
	local id = purchaseId()
	local results: { any } = {}
	for i = 1, 3 do
		task.spawn(function()
			results[i] = monCore.ProcessReceiptWith(receipt(id), env)
		end)
	end
	for _ = 1, 60 do
		if results[1] ~= nil and results[2] ~= nil and results[3] ~= nil then
			break
		end
		task.wait(0.1)
	end
	for i = 1, 3 do
		eq(results[i], GRANTED, "Aufruf " .. i)
	end
	eq(counter.n, 1, "Gutschriften")
	eq(data.Credits, 5000, "CR nur einmal")
end

Tests["Beleg: Spieler weg, unbekanntes Produkt, Speichern scheitert, Liste begrenzt"] = function(services: any)
	local _, monCore = cores(services)
	local data = newData(services)
	local counter = { n = 0 }
	local env = receiptEnv(services, data, { Counter = counter })
	eq(monCore.ProcessReceiptWith(receipt(purchaseId(), nil, 12345), env), NOT_YET, "Spieler nicht da")
	eq(monCore.ProcessReceiptWith(receipt(purchaseId(), 777), env), NOT_YET, "unbekanntes Produkt")
	eq(monCore.ProcessReceiptWith("kaputt", env), NOT_YET, "kaputter Beleg")
	eq(counter.n, 0, "nichts gutgeschrieben")
	-- Speichern scheitert: NotProcessedYet, Beleg steht -> nächster Versuch ohne Doppel-Gutschrift
	local failing = receiptEnv(services, data, { Counter = counter, SaveOk = false })
	local id = purchaseId()
	eq(monCore.ProcessReceiptWith(receipt(id), failing), NOT_YET, "Save-Fehler")
	eq(counter.n, 1, "einmal gutgeschrieben")
	eq(monCore.ProcessReceiptWith(receipt(id), env), GRANTED, "Wiederholung nach Save-Fehler")
	eq(counter.n, 1, "keine Doppel-Gutschrift")
	for _ = 1, 75 do
		monCore.AddReceipt(data, purchaseId(), os.time())
	end
	truthy(#data.Purchases.Receipts <= (Config.Tech.ReceiptKeep or 60), "Belege begrenzt (60)")
end

Tests["Beleg live: SimulatePurchase doppelt + gleichzeitig (gleiche Id) = eine Gewährung"] = function(services: any)
	-- nur mit einem geladenen Studio-Spieler im NoSave-Modus (sonst decken die Core-Tests den Fluss ab)
	local monetization = serviceModule(services, "MonetizationService")
	local shop = serviceModule(services, "ShopService")
	local dataService = services and services.DataService
	if dataService == nil or type(dataService.Get) ~= "function" then
		return
	end
	local target: Player? = nil
	for _, p in ipairs(Players:GetPlayers()) do
		if dataService.Get(p) ~= nil and type(dataService.IsNoSave) == "function" and dataService.IsNoSave(p) then
			target = p
			break
		end
	end
	if target == nil then
		return
	end
	local p = target :: Player
	local before = shop.Balance(p)
	local voucher = SHOP.ProductsByKey.CreditsS
	local tower = services.TowerService
	local steady = 0
	if tower and type(tower.Income) == "function" then
		local okIncome, info = pcall(tower.Income, p)
		if okIncome and type(info) == "table" and Util.IsFinite(info.Steady) then
			steady = info.Steady
		end
	end
	local single = SHOP.VoucherCredits(voucher, steady)
	local id = "SELFTEST-" .. HttpService:GenerateGUID(false)
	local results: { boolean } = {}
	for i = 1, 2 do
		task.spawn(function()
			results[i] = (monetization.SimulatePurchase(p, "CreditsS", id))
		end)
	end
	for _ = 1, 100 do
		if results[1] ~= nil and results[2] ~= nil then
			break
		end
		task.wait(0.1)
	end
	truthy(results[1] == true and results[2] == true, "beide Aufrufe bestätigt")
	local again = monetization.SimulatePurchase(p, "CreditsS", id)
	truthy(again == true, "dritter Aufruf bestätigt (Beleg vorhanden)")
	local gained = shop.Balance(p) - before
	truthy(gained >= voucher.Voucher.Min, "eine Gutschrift (" .. tostring(gained) .. ")")
	truthy(
		gained < 2 * single,
		("nie doppelt (%s für einen Gutschein von %s)"):format(tostring(gained), tostring(single))
	)
	local count = 0
	local data = dataService.Get(p)
	local receipts = if data and type(data.Purchases) == "table" then data.Purchases.Receipts else {}
	for _, entry in ipairs(receipts) do
		if type(entry) == "table" and entry.Id == id then
			count += 1
		end
	end
	eq(count, 1, "genau ein Beleg")
end

-- ---------------------------------------------------------------------
-- GRANT / SANITIZE
-- ---------------------------------------------------------------------
Tests["Grant alles-oder-nichts: ungültige Gewährungen ändern nichts"] = function(services: any)
	local shopCore = cores(services)
	local data = newData(services)
	data.Credits = 100
	local before = Util.DeepCopy(data)
	-- Liste mit zusätzlichem Text-Schlüssel (absichtlich kaputt, zur Laufzeit gebaut)
	local mixedList: { [any]: any } = { "ok" }
	mixedList.Extra = "x"
	for i, bad in ipairs({
		{ Credits = -5 },
		{ Credits = 1.5 },
		{ Credits = 0 / 0 },
		{ Credits = math.huge },
		{ Unbekannt = 1 },
		{ Xp = 10 },
		{ Cars = { "GibtEsNicht" } },
		{ Accessories = { "Copper" } }, -- Copper ist eine Uhr, kein Accessoire
		{ Decor = { NeonBench = 0 } },
		{ Decor = { GibtEsNicht = 1 } },
		{ Cosmetics = { 1 } },
		{ Cosmetics = mixedList },
		{ BoostX2 = 1e12 },
		{ SeasonPremium = "ja" },
		{ Credits = 10, Cars = { "GibtEsNicht" } },
	}) do
		local ok = shopCore.ValidateGrant(data, bad)
		truthy(not ok, "ungültiger Grant #" .. i .. " wurde akzeptiert")
	end
	local same, where = deepEqual(before, data, "Daten")
	truthy(same, "Prüfung hat Daten verändert bei " .. tostring(where))
	-- gültige Gewährung
	local grant = { Credits = 250, Cosmetics = { "Startup" }, BoostX2 = 600, Decor = { NeonBench = 2 } }
	local ok, err = shopCore.ValidateGrant(data, grant)
	truthy(ok, "gültiger Grant abgelehnt: " .. tostring(err))
	shopCore.ApplyGrant(data, grant)
	eq(data.Credits, 350, "CR")
	eq(data.Purchases.Cosmetics.Startup, true, "Kosmetik")
	eq(data.Boosts.X2, 600, "Boost x2")
	eq(data.Storage.Decor.NeonBench, 2, "Deko")
end

Tests["Sanitize streicht verbotene Robux-Felder"] = function(services: any)
	local shopCore, monCore = cores(services)
	local dirty = {
		Credits = 10,
		Xp = 5,
		AKY = 1,
		Depot = { Cash = 1 },
		Basis = 9,
		Licence = 2,
		KnowHow = 3,
		Ruf = 1,
		Stars = 4,
		BotSlots = 1,
		MarketInfo = true,
		ExamPass = true,
	}
	for _, clean in ipairs({ shopCore.Sanitize(dirty, true), monCore.Sanitize(dirty) }) do
		eq(clean.Credits, 10, "CR bleiben")
		noForbidden(clean, "Sanitize")
	end
	-- Nicht-Robux-Quelle: verbotene Felder werden zwar nicht gestrichen, aber die Prüfung lehnt sie ab
	local loose = shopCore.Sanitize({ Credits = 10, Xp = 5 }, false)
	local ok = shopCore.ValidateGrant(newData(services), loose)
	truthy(not ok, "XP-Feld bei Nicht-Robux-Quelle akzeptiert")
end

-- ---------------------------------------------------------------------
-- FIREWALL (§C11.4 #5, Abnahme 2) – byte-gleich für jeden Robux-Pfad
-- ---------------------------------------------------------------------
Tests["Firewall byte-gleich: Produkte, Pässe, Saison, Club, Codes, Events"] = function(services: any)
	local shopCore, monCore = cores(services)
	local season = seasonNow()
	local checked = 0
	-- 1) jedes Produkt, Erstkauf und Wiederholung
	for _, product in ipairs(SHOP.Products) do
		for _, repeatCase in ipairs({ false, true }) do
			local data = newData(services)
			data.Prog.Xp, data.Prog.Ruf = 12345, 7
			if repeatCase then
				data.Purchases.Starter = true
				data.Purchases.PassSeasons[tostring(season)] = true
			end
			local before = firewallSnapshot(data)
			local grant = monCore.BuildGrant(
				product,
				data,
				{ SeasonId = season, Steady = 123.45, Now = os.time(), RandomAllowed = false, Premium = repeatCase }
			)
			grant = shopCore.Sanitize(grant, true)
			noForbidden(grant, product.Key)
			local ok, err = shopCore.ValidateGrant(data, grant)
			truthy(ok, product.Key .. ": Gewährung ungültig: " .. tostring(err))
			shopCore.ApplyGrant(data, grant)
			assertFirewall(before, data, product.Key .. (if repeatCase then " (Wiederholung)" else ""))
			checked += 1
		end
	end
	-- 2) jeder Pass (Refresh: wirksamer Besitz + Faktoren, schreibt nie Spielstand-Werte)
	for _, pass in ipairs(SHOP.GamePasses) do
		local data = newData(services)
		local before = firewallSnapshot(data)
		local effective = monCore.EffectivePasses({ [pass.Key] = true })
		local factor = monCore.PassFactor(effective.Income2x == true, effective.Income3x == true)
		truthy(factor >= 1 and factor <= 4, pass.Key .. ": Pässe-Faktor " .. tostring(factor))
		local fixed = monCore.FixedFactor(effective.VIP == true, false, false)
		truthy(fixed >= 1 and fixed <= 1.5, pass.Key .. ": Fix-Faktor " .. tostring(fixed))
		shopCore.Ensure(data)
		assertFirewall(before, data, "Pass " .. pass.Key)
		checked += 1
	end
	-- 3) jede Saison-Stufe beider Spuren (gekauft = Robux-Pfad)
	local seasons = type(Config.Season) == "table" and Config.Season.Seasons or {}
	for _, entry in ipairs(seasons) do
		for _, track in ipairs({ entry.Free or {}, entry.Premium or {} }) do
			for _, reward in ipairs(track) do
				local data = newData(services)
				local before = firewallSnapshot(data)
				local grant = shopCore.Sanitize(shopCore.RewardToGrant(reward, 50), true)
				noForbidden(grant, "Saison-Stufe " .. tostring(reward.Tier))
				local ok, err = shopCore.ValidateGrant(data, grant)
				truthy(ok, "Saison-Stufe " .. tostring(reward.Tier) .. " ungültig: " .. tostring(err))
				shopCore.ApplyGrant(data, grant)
				assertFirewall(before, data, "Saison-Stufe " .. tostring(reward.Tier))
				checked += 1
			end
		end
	end
	-- 4) Club-Tagesgabe (Bau-Gutschein S)
	do
		local data = newData(services)
		local before = firewallSnapshot(data)
		local voucher = SHOP.ProductsByKey[SHOP.Subscription.DailyVoucher]
		local grant = shopCore.Sanitize({ Credits = SHOP.VoucherCredits(voucher, 99) }, true)
		truthy(shopCore.ValidateGrant(data, grant), "Club-Tagesgabe ungültig")
		shopCore.ApplyGrant(data, grant)
		assertFirewall(before, data, "Club-Tagesgabe")
		checked += 1
	end
	-- 5) jeder Code (Config.Rewards.Codes – nur CR/Kosmetik)
	local codes = type(Config.Rewards) == "table" and Config.Rewards.Codes or {}
	for code, entry in pairs(codes) do
		local data = newData(services)
		local before = firewallSnapshot(data)
		local grant = shopCore.Sanitize(shopCore.RewardToGrant(entry.Grant, 0), false)
		local ok, err = shopCore.ValidateGrant(data, grant)
		truthy(ok, "Code " .. tostring(code) .. " ungültig: " .. tostring(err))
		shopCore.ApplyGrant(data, grant)
		assertFirewall(before, data, "Code " .. tostring(code))
		checked += 1
	end
	-- 6) Admin-/Event-Gutschriften (Geldregen, Pickups, Admin-Abuse-Belohnungen laufen alle über Credit)
	for _, source in ipairs({ "Event", "Rain", "Pickup", "Admin", "Code", "Season", "Login", "Quest" }) do
		local data = newData(services)
		local before = firewallSnapshot(data)
		truthy(shopCore.Credit(data, 1000, source), "Credit " .. source)
		assertFirewall(before, data, "Gutschrift " .. source)
		checked += 1
	end
	truthy(checked >= #SHOP.Products * 2 + #SHOP.GamePasses + 2, "zu wenige Firewall-Fälle: " .. checked)
end

-- ---------------------------------------------------------------------
-- NO PAID RANDOM (§C11.4 #6, Abnahme 3)
-- ---------------------------------------------------------------------
Tests["NoPaidRandom: keine bezahlten Zufallsartikel, Policy fail-closed"] = function(services: any)
	local _, monCore = cores(services)
	eq(SHOP.RandomItemsEnabled, false, "RandomItemsEnabled")
	local banned = { Odds = true, Weights = true, Weight = true, Chance = true, Pity = true }
	local function scan(node: any, path: string, depth: number)
		if type(node) ~= "table" or depth > 6 then
			return
		end
		for key, value in pairs(node) do
			if banned[key] then
				error(path .. "." .. tostring(key) .. ": Zufalls-Feld im Shop", 0)
			end
			if key == "Random" and value ~= false then
				error(path .. ".Random ist nicht false", 0)
			end
			scan(value, path .. "." .. tostring(key), depth + 1)
		end
	end
	scan(SHOP.GamePasses, "GamePasses", 0)
	scan(SHOP.Products, "Products", 0)
	scan(SHOP.Subscription, "Subscription", 0)
	for _, product in ipairs(SHOP.Products) do
		eq(product.Random, false, product.Key .. ".Random")
	end
	-- PolicyService: Fehler/fehlend = eingeschränkt
	eq(monCore.ParsePolicy(nil).Random, false, "Policy unbekannt")
	eq(monCore.ParsePolicy({ ArePaidRandomItemsRestricted = true }).Random, false, "eingeschränkt")
	eq(monCore.ParsePolicy({}).Random, false, "Feld fehlt")
	eq(monCore.ParsePolicy({ ArePaidRandomItemsRestricted = false }).Random, true, "erlaubt")
	-- gedachtes Zufallsprodukt bei unbekannter Policy -> fester Ersatz, nie der Zufallsinhalt
	local fake = {
		Key = "FakeRandom",
		Kind = "Boost",
		Random = true,
		Grant = { BoostX2 = 60 },
		Repeat = { Grant = { BoostX2 = 30 } },
	}
	local grant = monCore.BuildGrant(fake, newData(services), { SeasonId = 1, Steady = 0, Now = os.time() })
	eq(grant.BoostX2, 30, "eingeschränkt -> Ersatz")
end

-- ---------------------------------------------------------------------
-- PAKET & FAKTOREN (§B14.1)
-- ---------------------------------------------------------------------
Tests["Paket: Besitz zählt für die Teile, x2 + x3 = x4, echter Rabatt"] = function(services: any)
	local _, monCore = cores(services)
	local effective = monCore.EffectivePasses({ TycoonBundle = true })
	eq(effective.Income2x, true, "Paket -> x2")
	eq(effective.AutoCollect, true, "Paket -> Auto-Kassierer")
	eq(effective.OfflineVault, true, "Paket -> Offline-Tresor")
	eq(effective.Income3x, false, "Paket gibt kein x3")
	eq(monCore.PassFactor(false, false), 1, "ohne Pässe")
	eq(monCore.PassFactor(true, false), 2, "x2")
	eq(monCore.PassFactor(false, true), 3, "x3")
	eq(monCore.PassFactor(true, true), 4, "x2 + x3 = x4")
	eq(SHOP.BundleValue("TycoonBundle"), 1097, "Einzelpreise")
	eq(SHOP.BundleDiscountPct("TycoonBundle"), 32, "Rabatt −32 %")
	truthy(SHOP.PassesByKey.TycoonBundle.Price < SHOP.BundleValue("TycoonBundle"), "Paket günstiger")
	eq(SHOP.BundleDiscountPct("TycoonBundle", 700, 749), 0, "kein Fake-Rabatt aus Live-Preisen")
	local vip = monCore.FixedFactor(true, false, false)
	local all = monCore.FixedFactor(true, true, true)
	truthy(math.abs(vip - 1.10) < 1e-9, "VIP ×1,10")
	truthy(math.abs(all - 1.10 * 1.15 * 1.10) < 1e-9, "VIP × Club × Premium")
end

-- ---------------------------------------------------------------------
-- STARTER-PAKET (einmal je Konto)
-- ---------------------------------------------------------------------
Tests["Starter einmalig, Wiederholung = 2 × Bau-Gutschein M"] = function(services: any)
	local _, monCore = cores(services)
	local data = newData(services)
	local starter = SHOP.ProductsByKey.Starter
	local voucherM = SHOP.ProductsByKey.CreditsM
	local ctx = { SeasonId = 1, Steady = 10, Now = os.time() }
	local g1, i1 = monCore.BuildGrant(starter, data, ctx)
	eq(g1.Cars and g1.Cars[1], "LamNeon", "Auto Λ Kompakt Neon")
	eq(g1.Watches and g1.Watches[1], "FirstBell", "Uhr Erste Glocke")
	eq(g1.BoostX2, 7200, "Boost x2 2 h")
	truthy(type(g1.Cosmetics) == "table" and table.find(g1.Cosmetics, "Startup") ~= nil, "Fassaden-Neon Startup")
	truthy(table.find(g1.Cosmetics, "FounderFrame") ~= nil, "Namensrahmen Gründer")
	eq(g1.Credits, SHOP.VoucherCredits(voucherM, 10), "Bau-Gutschein M")
	eq(i1.MarkStarter, true, "Starter wird vermerkt")
	data.Purchases.Starter = true
	local g2, i2 = monCore.BuildGrant(starter, data, ctx)
	eq(i2.Repeat, true, "Wiederholung")
	eq(i2.MarkStarter, false, "kein zweites Vermerken")
	eq(g2.Cars, nil, "kein zweites Auto")
	eq(g2.BoostX2, nil, "kein zweiter Boost")
	eq(g2.Credits, 2 * SHOP.VoucherCredits(voucherM, 10), "2 × Gutschein M")
end

-- ---------------------------------------------------------------------
-- BAU-GUTSCHEIN (Abnahme 5): max(Angebot, Neuberechnung), nur CR, Angebots-Ablauf
-- ---------------------------------------------------------------------
Tests["Bau-Gutschein: max(Angebot, Neu), nur CR, Angebot läuft ab"] = function(services: any)
	local _, monCore = cores(services)
	local now = os.time()
	local product = SHOP.ProductsByKey.CreditsM
	local fresh = SHOP.VoucherCredits(product, 10)
	eq(fresh, math.max(20000, 10 * 120 * 60), "Neuberechnung")
	eq(SHOP.VoucherCredits(product, 0), 20000, "Mindestbetrag")
	local data = newData(services)
	local ctx = { SeasonId = 1, Steady = 10, Now = now }
	data.Purchases.Quote.CreditsM = { Credits = 100000, Until = now + 300 }
	local grant = monCore.BuildGrant(product, data, ctx)
	eq(grant.Credits, 100000, "höheres Angebot zählt")
	for field in pairs(grant) do
		eq(field, "Credits", "Bau-Gutschein gibt nur CR")
	end
	data.Purchases.Quote.CreditsM = { Credits = 1000, Until = now + 300 }
	eq(monCore.BuildGrant(product, data, ctx).Credits, fresh, "höhere Neuberechnung zählt")
	data.Purchases.Quote.CreditsM = { Credits = 100000, Until = now - 1 }
	eq(monCore.BuildGrant(product, data, ctx).Credits, fresh, "abgelaufenes Angebot zählt nicht")
	data.Purchases.Quote.CreditsM = { Credits = 100000, Until = now + SHOP.QuoteSeconds + 120 }
	eq(monCore.BuildGrant(product, data, ctx).Credits, fresh, "unplausibles Angebot zählt nicht")
	eq(monCore.QuoteFor(data, "CreditsM", now), nil, "QuoteFor ignoriert es")
end

-- ---------------------------------------------------------------------
-- ANGEBOTS-REGELN (§B14.4, Abnahme 4)
-- ---------------------------------------------------------------------
Tests["Angebote: nie in Sitzung 1, max. 1, nie bei Warnung/Tutorial/Admin-Abuse"] = function(services: any)
	local _, monCore = cores(services)
	local function ctx(overrides: { [string]: any }): any
		local base = {
			Shown = 0,
			Max = SHOP.MaxOffersPerSession,
			Sessions = 3,
			MinSession = SHOP.OfferMinSession,
			SessionSeconds = 3600,
			MinSeconds = SHOP.OfferMinMinutes * 60,
			TutorialDone = true,
			AdminAbuse = false,
			MarketBlocked = false,
		}
		for key, value in pairs(overrides) do
			base[key] = value
		end
		return base
	end
	truthy(monCore.OfferCheck(ctx({})), "ruhiger Moment ab Sitzung 2")
	local cases = {
		{ { Sessions = 1 }, "FirstSession" },
		{ { Shown = 1 }, "MaxPerSession" },
		{ { SessionSeconds = 14 * 60 }, "TooEarly" },
		{ { TutorialDone = false }, "Tutorial" },
		{ { AdminAbuse = true }, "AdminAbuse" },
		{ { MarketBlocked = true }, "MarketWarning" },
	}
	for _, case in ipairs(cases) do
		local ok, reason = monCore.OfferCheck(ctx(case[1]))
		truthy(not ok, "Angebot trotz " .. case[2])
		eq(reason, case[2], "Grund")
	end
	truthy(SHOP.OfferMinSession >= 2, "nie in Sitzung 1 (Config)")
end

-- ---------------------------------------------------------------------
-- GESCHENK-GATE (Abnahme 6)
-- ---------------------------------------------------------------------
Tests["Geschenk gesperrt ohne IsPaidItemTradingAllowed (fail-closed)"] = function(services: any)
	local _, monCore = cores(services)
	eq(monCore.ParsePolicy({}).Trading, false, "Feld fehlt = gesperrt")
	eq(monCore.ParsePolicy(nil).Trading, false, "Fehler = gesperrt")
	eq(monCore.ParsePolicy({ IsPaidItemTradingAllowed = true }).Trading, true, "erlaubt")
	local cases = {
		{ false, true, false, true, "shop.giftBlocked" },
		{ true, false, false, true, "shop.giftBlocked" },
		{ nil, true, false, true, "shop.giftBlocked" },
		{ true, nil, false, true, "shop.giftBlocked" },
		{ true, true, true, true, "shop.giftSelfNot" },
		{ true, true, false, false, "shop.giftTargetGone" },
	}
	for i, case in ipairs(cases) do
		local ok, reason = monCore.GiftCheck(case[1], case[2], case[3], case[4])
		truthy(not ok, "Geschenk-Fall " .. i .. " durchgelassen")
		eq(reason, case[5], "Grund Fall " .. i)
	end
	truthy(monCore.GiftCheck(true, true, false, true), "beide erlaubt")
end

-- ---------------------------------------------------------------------
-- CR-KONTO (Whitelist, Ganzzahl, Deckel)
-- ---------------------------------------------------------------------
Tests["CR-Konto: Quellen/Senken-Whitelist, Ganzzahl, Deckel 9e15"] = function(services: any)
	local shopCore = cores(services)
	local data = newData(services)
	truthy(not shopCore.Credit(data, 100, "Robux"), "unbekannte Quelle")
	truthy(not shopCore.Credit(data, -5, "Income"), "negativ")
	truthy(not shopCore.Credit(data, 0 / 0, "Income"), "NaN")
	truthy(not shopCore.Credit(data, 0.5, "Income"), "unter 1")
	eq(data.Credits, 0, "nichts gebucht")
	local ok, added = shopCore.Credit(data, 1000, "Income")
	truthy(ok and added == 1000, "Credit 1000")
	eq(data.Stats.LifetimeCredits, 1000, "Lebenszeit-CR")
	truthy(not shopCore.Debit(data, 10, "Robux"), "unbekannte Senke")
	truthy(not shopCore.Debit(data, 1.5, "Floor"), "Bruchteil")
	truthy(not shopCore.Debit(data, 1001, "Floor"), "mehr als Guthaben")
	eq(data.Credits, 1000, "nichts abgezogen")
	truthy(shopCore.Debit(data, 400, "Floor"), "Debit 400")
	eq(data.Credits, 600, "Rest")
	truthy(shopCore.CanSpend(data, 600) and not shopCore.CanSpend(data, 601), "CanSpend")
	data.Credits = MAX_MONEY - 10
	local okCap, addedCap = shopCore.Credit(data, 100, "Vault")
	truthy(okCap, "Credit am Deckel")
	eq(addedCap, 10, "nur bis zum Deckel")
	eq(data.Credits, MAX_MONEY, "Deckel 9e15")
	data.Credits = 12.7
	shopCore.Ensure(data)
	eq(data.Credits, 12, "Kontostand ganzzahlig")
	for _, source in ipairs(SHOP.Sources) do
		truthy(shopCore.Credit(newData(services), 1, source), "Quelle " .. source)
	end
	eq(shopCore.SourceOf("Robux:CreditsM", true), "Purchase", "Robux -> Purchase")
	eq(shopCore.SourceOf("Season:Tier12", false), "Season", "Saison")
	eq(shopCore.SourceOf("Irgendwas", false), nil, "unbekannt")
end

-- ---------------------------------------------------------------------
-- BULLEN-PARADE, SAISON-PREMIUM, ROTATION
-- ---------------------------------------------------------------------
Tests["Bullen-Parade: 15 min je Kauf, höchstens 60 min im Voraus"] = function(services: any)
	local _, monCore = cores(services)
	local now = os.time()
	eq(monCore.ExtendParade(0, now), now + SHOP.Parade.Seconds, "erster Kauf")
	local untilT = 0
	for _ = 1, 10 do
		untilT = monCore.ExtendParade(untilT, now)
	end
	eq(untilT, now + SHOP.Parade.CapSeconds, "Deckel 60 min")
	eq(monCore.ExtendParade(now + 3000, now), now + SHOP.Parade.CapSeconds, "Verlängerung geklemmt")
end

Tests["Saison-Premium zweimal -> Bau-Gutschein L, neue Saison wieder Premium"] = function(services: any)
	local _, monCore = cores(services)
	local data = newData(services)
	local product = SHOP.ProductsByKey.SeasonPremium
	local voucherL = SHOP.ProductsByKey.CreditsL
	local season = seasonNow()
	local g1, i1 = monCore.BuildGrant(product, data, { SeasonId = season, Steady = 5, Now = os.time() })
	eq(g1.SeasonPremium, true, "erster Kauf: Premium")
	eq(i1.MarkSeason, true, "Saison vermerkt")
	data.Purchases.PassSeasons[tostring(season)] = true
	local g2, i2 = monCore.BuildGrant(product, data, { SeasonId = season, Steady = 5, Now = os.time() })
	eq(g2.SeasonPremium, nil, "kein zweites Premium")
	eq(i2.Repeat, true, "Ersatz")
	eq(g2.Credits, SHOP.VoucherCredits(voucherL, 5), "Bau-Gutschein L")
	local g3 = monCore.BuildGrant(
		product,
		newData(services),
		{ SeasonId = season, Steady = 5, Now = os.time(), Premium = true }
	)
	eq(g3.SeasonPremium, nil, "schon Premium (anders erhalten) -> Ersatz")
	local g4 = monCore.BuildGrant(product, data, { SeasonId = season + 1, Steady = 5, Now = os.time() })
	eq(g4.SeasonPremium, true, "neue Saison")
end

Tests["Saison-Id: Lücke zwischen festen Saisons = vorige (wie RewardService), danach Rolling"] = function()
	local day = 86400
	local cfg = {
		Seasons = {
			{ Id = 1, StartUtc = "2030-01-01T00:00:00Z", EndUtc = "2030-01-29T00:00:00Z" },
			{ Id = 2, StartUtc = "2030-03-01T00:00:00Z", EndUtc = "2030-03-29T00:00:00Z" },
		},
		Rolling = { Enabled = true, LengthDays = 28 },
		MaxSeasons = 999,
	}
	local s1 = SHOP.ParseUtc("2030-01-01T00:00:00Z") :: number
	local s2 = SHOP.ParseUtc("2030-03-01T00:00:00Z") :: number
	local e2 = SHOP.ParseUtc("2030-03-29T00:00:00Z") :: number
	eq(SHOP.SeasonIdAt(cfg, s1 - day), 1, "vor der ersten")
	eq(SHOP.SeasonIdAt(cfg, s1 + day), 1, "in Saison 1")
	eq(SHOP.SeasonIdAt(cfg, s2 - day), 1, "Lücke: Saison 1 gilt weiter (kein Rolling)")
	eq(SHOP.SeasonIdAt(cfg, s2 + day), 2, "in Saison 2")
	eq(SHOP.SeasonIdAt(cfg, e2 + day), 3, "nach der letzten: Rolling")
	eq(SHOP.SeasonIdAt(cfg, e2 + 29 * day), 4, "Rolling weiter")
end

Tests["CR-Senke Ipo und Quellen League/WinBack/Referral (keine Fremd-Buchung als Event/Admin)"] = function(
	services: any
)
	local shopCore = cores(services)
	local data = newData(services)
	truthy(shopCore.Credit(data, 1000, "League"), "Quelle League")
	truthy(shopCore.Credit(data, 1000, "WinBack"), "Quelle WinBack")
	eq(shopCore.SourceOf("Referral", false), "Referral", "Einladung")
	truthy(shopCore.Debit(data, 2000, "Ipo"), "Börsengang-Senke")
	eq(data.Credits, 0, "Börsengang leert das CR-Konto")
	truthy(shopCore.Credit(data, 300, "Admin"), "Admin-Geschenk")
	eq(data.Stats.AdminCredits, 300, "Admin-CR im Konto markiert (Wunsch 18)")
	truthy(SHOP.Disabled.TerminalDesigner == true, "Terminal-Designer gesperrt, solange die Themes fehlen")
end

Tests["Boutique-Rotation deterministisch, verschieden, begrenzt"] = function(services: any)
	local shopCore = cores(services)
	local pool = { "A", "B", "C", "D", "E", "F", "G", "H", "I", "J" }
	local a = shopCore.Rotation(123, 6, pool)
	local b = shopCore.Rotation(123, 6, pool)
	eq(#a, 6, "Anzahl")
	eq(table.concat(a, ","), table.concat(b, ","), "deterministisch")
	local seen: { [string]: boolean } = {}
	for _, key in ipairs(a) do
		truthy(not seen[key], "doppelt: " .. key)
		seen[key] = true
	end
	eq(#shopCore.Rotation(5, 6, { "X", "Y", "Z" }), 3, "kleiner Pool")
	eq(#shopCore.Rotation(5, 6, {}), 0, "leerer Pool")
	local shop = serviceModule(services, "ShopService")
	local live = shop.Rotation()
	truthy(#live <= SHOP.BoutiqueSlots, "Rotation höchstens BoutiqueSlots")
	eq(table.concat(live, ","), table.concat(shop.Rotation(), ","), "gleiches Fenster = gleiche Rotation")
end

return Tests
