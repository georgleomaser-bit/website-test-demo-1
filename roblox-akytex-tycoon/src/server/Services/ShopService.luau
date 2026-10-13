-- =====================================================================
--  AKYTEX TYCOON – CR-Konto, Gewährungen, Boutique-Rotation, Shop-Anfragen (Server/Services/ShopService)
--  Besitzer: WP10 (Monetarisierung, Shop, CR-Konto). Vertrag: DESIGN.md §C5.9, §C9 (ShopQuote, ShopPrecheck,
--  ShopClubClaim), §C10 (State Credits), §C11.4 Punkte 4–6 (Grant-Filter), §B13 (Wirtschaft), §B14.3 (Club-Tagesgabe).
--  Muster: CLUTCH-CLASH-ShopService (REUSE §3.12): Grant/Spend sind der EINZIGE Weg, nie yielden, erst alles prüfen,
--  dann in einem Rutsch buchen, Preise nur aus der Server-Config, Core.* reine Funktionen für EconomyTests.
--
--  CR-KONTO (§0.4): Credit/Debit sind der einzige CR-Gutschreiber/-Abzieher (kein Yield). Quellen/Senken-Whitelist
--  aus Config.Shop.Sources/Sinks, Beträge ganzzahlig, Kontostand 0 … 9e15 (Muss-Regel 9). Es gibt KEINE Funktion,
--  die CR in AKY verwandelt. Metriken (MetricsService.Economy) je Spieler alle 60 s gebündelt.
--  GEWÄHRUNG: Grant(p, grant, reason) – Robux-Quellen (reason "Robux:…") laufen durch Core.Sanitize (streicht
--  Config.Shop.ForbiddenRobuxFields), dann ValidateGrant (Typen, Schlüssel, Grenzen, Dienste, Kapazität) und erst
--  danach wird gebucht: Fremd-Teile über die Besitzer-APIs (Auto, Uhr, Deko, Boost, Token, Saison), eigene Teile
--  (CR, Kosmetik) direkt. Schlägt die Prüfung fehl, ändert sich NICHTS (alles-oder-nichts).
--
--  Öffentliche API (§C5.9):
--    ShopService.Credit(p, amount, source): boolean         einziger CR-Gutschreiber (kein Yield; über 9e15 geklemmt)
--    ShopService.Debit(p, amount, sink): boolean            einziger CR-Abzieher (kein Yield; nur bei Deckung)
--    ShopService.Balance(p): number
--    ShopService.Grant(p, grant, reason): boolean           alles-oder-nichts, Robux-Quellen gefiltert
--    ShopService.RefreshPlayer(p)                           Attribute Vip/Club + MarkDirty
--    ShopService.Rotation(): { string }                     Boutique-Rotation (4 h, deterministisch, alle Server gleich)
--    ShopService.Core: { Sanitize, ValidateGrant, ApplyGrant, CanSpend, Ensure, Balance, Credit, Debit, Rotation,
--                        SourceOf, IsRobux, RewardToGrant }   (rein, ohne Spieler -> EconomyTests)
--  Zusätzlich: ShopService.MissingFor(grant): string?        fehlender Besitzer-Dienst für eine Gewährung (Vorprüfung)
--  Request-Handler: ShopQuote {Key} (1/s) · ShopPrecheck {Key, UserId?} (2/s) · ShopClubClaim {} (1/s)
--  State-Schlüssel: Credits. Player-Attribute: Vip, Club.
--  Braucht (zur Laufzeit, optional per pcall): DataService, PlayerStateService, MonetizationService, MetricsService,
--    TowerService (AddBoost, ApplyExpress, AddExpressToken, AddInstantToken, Income), VehicleService (GrantCar),
--    LifestyleService (GrantWatch, GrantAccessory, GrantDecor), RewardService (GrantSeasonPremium, AddSeasonTiers,
--    GrantSeasonXp).
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Lang = require(Shared:WaitForChild("Lang"))
local Types = require(Shared:WaitForChild("Types"))
local Format = require(Shared:WaitForChild("Format"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local ShopService = {}
local Services: any = nil

type Reply = Types.Reply
type MetricEntry = { Flow: string, Tx: string, Amount: number }

local SHOP: any = Config.Shop

-- ---------------------------------------------------------------------
-- 1) KONSTANTEN
-- ---------------------------------------------------------------------
local MAX_MONEY = 9e15 -- Muss-Regel 9 (Anzeige "MAX"), < 2^53
local KEY_MAX = 40 -- Länge eines Item-Schlüssels
local LIST_MAX = math.clamp(math.floor(tonumber(SHOP.GrantListMax) or 64), 1, 256)
local NUMBER_MAX: { [string]: number } = if type(SHOP.GrantNumberMax) == "table" then SHOP.GrantNumberMax else {}
local DECOR_MAX = 999
local METRICS_EVERY = math.max(10, tonumber(SHOP.MetricsFlushSeconds) or 60)
local METRIC_ENTRIES_MAX = 32 -- je Spieler und Takt (Quellen + Senken sind ohnehin Whitelists)
local WARN_REASONS_MAX = 64
local TITLE_MAX = 200 -- Titel-Liste im Spielstand begrenzt
local COSMETICS_MAX = 512 -- Kosmetik-Besitz begrenzt
local SEASON_TIER_XP = 1000 -- Rückfall, falls Config.Season fehlt

local SOURCE_SET: { [string]: boolean } = {}
for _, name in ipairs(SHOP.Sources or {}) do
	SOURCE_SET[name] = true
end
local SINK_SET: { [string]: boolean } = {}
for _, name in ipairs(SHOP.Sinks or {}) do
	SINK_SET[name] = true
end

-- ---------------------------------------------------------------------
-- 2) ZUSTAND (Pro-Spieler-Tabellen werden bei PlayerRemoving geleert)
-- ---------------------------------------------------------------------
local metricsAcc: { [Player]: { [string]: MetricEntry } } = {}
local metricsCount: { [Player]: number } = {}
local warnedReasons: { [string]: boolean } = {}
local warnedCount = 0
local rotationCache: { Window: number, Slots: number, Keys: { string } }? = nil

-- =====================================================================
-- 3) HELFER
-- =====================================================================
local function service(name: string): any
	return Services and Services[name]
end

local function call(name: string, fnName: string, ...: any): (boolean, any)
	local s = service(name)
	if s == nil or type(s[fnName]) ~= "function" then
		return false, nil
	end
	return pcall(s[fnName], ...)
end

local function has(name: string, fnName: string): boolean
	local s = service(name)
	return s ~= nil and type(s[fnName]) == "function"
end

local function present(p: any): boolean
	return typeof(p) == "Instance" and p:IsA("Player") and p.Parent == Players
end

local function isInteger(n: any): boolean
	return Util.IsFinite(n) and (n :: number) % 1 == 0
end

local function dataOf(p: Player): any
	local dataService = service("DataService")
	if dataService == nil or type(dataService.Get) ~= "function" then
		return nil
	end
	return dataService.Get(p)
end

local function langOf(p: Player): Types.Lang
	local ok, lang = call("PlayerStateService", "LangOf", p)
	return if ok and (lang == "de" or lang == "en") then lang else "en"
end

local function markDirty(p: Player, ...: string)
	local stateService = service("PlayerStateService")
	if stateService and type(stateService.MarkDirty) == "function" then
		stateService.MarkDirty(p, ...)
	end
end

local function fail(p: Player, key: string, ...: any): Reply
	return { Ok = false, Message = Lang.T(langOf(p), key, ...) }
end

local function validKey(key: any): boolean
	return type(key) == "string" and #key >= 1 and #key <= KEY_MAX and string.match(key, "^[%w_]+$") ~= nil
end

local function hasPass(p: Player, key: string): boolean
	local ok, result = call("MonetizationService", "HasPass", p, key)
	return ok and result == true
end

local function isClub(p: Player): boolean
	local ok, result = call("MonetizationService", "IsClub", p)
	return ok and result == true
end

-- Liste ODER Menge um einen Schlüssel ergänzen (Titel: WP9 entscheidet die Form; leer -> Menge)
local function addToCollection(collection: { [any]: any }, key: string, max: number)
	if #collection > 0 then
		if not table.find(collection, key) and #collection < max then
			table.insert(collection, key)
		end
	elseif collection[key] ~= true then
		local count = 0
		for _ in pairs(collection) do
			count += 1
			if count >= max then
				return
			end
		end
		collection[key] = true
	end
end

-- Exakte Schlüssel (§C9): nur erlaubte Felder, jedes vom richtigen Typ; required = Pflichtfelder
local function exact(arg: any, allowed: { [string]: string }, required: { string }): boolean
	if arg == nil then
		return #required == 0
	end
	if type(arg) ~= "table" then
		return false
	end
	for key, value in pairs(arg) do
		local kind = if type(key) == "string" then allowed[key] else nil
		if kind == nil or type(value) ~= kind then
			return false
		end
	end
	for _, key in ipairs(required) do
		if arg[key] == nil then
			return false
		end
	end
	return true
end

-- =====================================================================
-- 4) CORE – reine Daten-Funktionen (kein Spieler, kein Yield) -> EconomyTests
-- =====================================================================
local Core = {}
ShopService.Core = Core

-- fehlende/kaputte eigene Felder reparieren (DataService reconciliert schon; doppelt hält besser)
function Core.Ensure(data: any)
	local balance = data.Credits
	if not Util.IsFinite(balance) or balance < 0 then
		data.Credits = 0
	else
		data.Credits = math.clamp(math.floor(balance), 0, MAX_MONEY)
	end
	if type(data.Purchases) ~= "table" then
		data.Purchases = {}
	end
	if type(data.Purchases.Cosmetics) ~= "table" then
		data.Purchases.Cosmetics = {}
	end
	if type(data.Stats) ~= "table" then
		data.Stats = {}
	end
	if not Util.IsFinite(data.Stats.LifetimeCredits) or data.Stats.LifetimeCredits < 0 then
		data.Stats.LifetimeCredits = 0
	end
end

function Core.Balance(data: any): number
	local value = if type(data) == "table" then data.Credits else nil
	if not Util.IsFinite(value) or value < 0 then
		return 0
	end
	return math.clamp(math.floor(value), 0, MAX_MONEY)
end

-- Reicht das Guthaben? (nur positive ganze Beträge)
function Core.CanSpend(data: any, amount: number): boolean
	return isInteger(amount) and amount > 0 and Core.Balance(data) >= amount
end

-- CR gutschreiben: Quelle aus der Whitelist, Betrag ≥ 1 (abgerundet), Kontostand ≤ 9e15. (ok, tatsächlich gutgeschrieben)
function Core.Credit(data: any, amount: number, source: string): (boolean, number)
	if type(data) ~= "table" or not SOURCE_SET[source] then
		return false, 0
	end
	if not Util.IsFinite(amount) or amount < 1 then
		return false, 0
	end
	Core.Ensure(data)
	local before = data.Credits
	local after = math.min(MAX_MONEY, before + math.floor(amount))
	data.Credits = after
	local added = after - before
	data.Stats.LifetimeCredits = math.min(MAX_MONEY, data.Stats.LifetimeCredits + added)
	return true, added
end

-- CR abziehen: Senke aus der Whitelist, ganzzahliger Betrag > 0, nur bei voller Deckung (Prüfen + Abziehen ohne Yield)
function Core.Debit(data: any, amount: number, sink: string): boolean
	if type(data) ~= "table" or not SINK_SET[sink] or not Core.CanSpend(data, amount) then
		return false
	end
	Core.Ensure(data)
	data.Credits = math.clamp(data.Credits - amount, 0, MAX_MONEY)
	return true
end

-- Robux-Quelle? (Gründe "Robux:<Key>", "Robux:ClubDaily", …)
function Core.IsRobux(reason: string): boolean
	return type(reason) == "string" and string.sub(reason, 1, 5) == "Robux"
end

-- CR-Quelle zu einem Grant-Grund: Robux -> "Purchase", sonst das erste Wort, wenn es in der Whitelist steht
function Core.SourceOf(reason: string, robux: boolean): string?
	if robux then
		return "Purchase"
	end
	local head = if type(reason) == "string" then string.match(reason, "^(%a+)") else nil
	if head and SOURCE_SET[head] then
		return head
	end
	return nil
end

-- Kopie einer Gewährung; robux = true streicht Config.Shop.ForbiddenRobuxFields (§B14.5)
function Core.Sanitize(grant: any, robux: boolean): { [string]: any }
	local clean, removed = SHOP.SanitizeGrant(grant, robux == true)
	for _, field in ipairs(removed) do
		warn("[ShopService] Verbotenes Robux-Feld gestrichen: " .. tostring(field))
	end
	return clean
end

local function seasonTierXp(): number
	local season = Config.Season
	local list = type(season) == "table" and season.Seasons or nil
	local entry = type(list) == "table" and list[#list] or nil
	local xp = if type(entry) == "table" then entry.TierXp else nil
	return if Util.IsFinite(xp) and xp > 0 then xp else SEASON_TIER_XP
end

local function knownCar(key: string): boolean
	local vehicles = Config.Vehicles
	if type(vehicles) ~= "table" or type(vehicles.Car) ~= "function" then
		return false
	end
	local ok, car = pcall(vehicles.Car, key)
	return ok and car ~= nil
end

local function lifeKind(key: string): string?
	local lifestyle = Config.Lifestyle
	local kinds = type(lifestyle) == "table" and lifestyle.KindOf or nil
	return if type(kinds) == "table" then kinds[key] else nil
end

local function knownDecor(key: string): boolean
	local decor = Config.Decor
	local byKey = type(decor) == "table" and decor.ByKey or nil
	return type(byKey) == "table" and byKey[key] ~= nil
end

-- Grant prüfen, OHNE etwas zu ändern. Gibt (ok, Fehlertext) zurück.
function Core.ValidateGrant(_data: any, grant: any): (boolean, string?)
	if type(grant) ~= "table" then
		return false, "Grant ist keine Tabelle"
	end
	local fields = SHOP.GrantFields
	for field, value in pairs(grant) do
		local kind = if type(field) == "string" then fields[field] else nil
		if kind == nil then
			return false, "unbekanntes Feld " .. tostring(field)
		end
		if kind == "number" then
			if not isInteger(value) or value < 0 then
				return false, field .. ": ganze Zahl ≥ 0 erwartet"
			end
			local max = if Util.IsFinite(NUMBER_MAX[field]) then NUMBER_MAX[field] else MAX_MONEY
			if value > max then
				return false, ("%s: höchstens %s"):format(field, tostring(max))
			end
		elseif kind == "boolean" then
			if type(value) ~= "boolean" then
				return false, field .. ": true/false erwartet"
			end
		elseif kind == "list" then
			if type(value) ~= "table" then
				return false, field .. ": Liste erwartet"
			end
			local count = 0
			for k, v in pairs(value) do
				count += 1
				if type(k) ~= "number" or not validKey(v) then
					return false, field .. ": Liste von Schlüsseln erwartet"
				end
			end
			if count ~= #value or count > LIST_MAX then
				return false, ("%s: lückenlose Liste mit höchstens %d Einträgen erwartet"):format(field, LIST_MAX)
			end
		elseif kind == "map" then
			if type(value) ~= "table" then
				return false, field .. ": { [Schlüssel] = Anzahl } erwartet"
			end
			local count = 0
			for k, v in pairs(value) do
				count += 1
				if not validKey(k) or not isInteger(v) or v < 1 or v > DECOR_MAX then
					return false, field .. ": { [Schlüssel] = Anzahl 1 … 999 } erwartet"
				end
			end
			if count > LIST_MAX then
				return false, field .. ": zu viele Einträge"
			end
		end
	end
	-- Querverweise auf die Besitzer-Configs (unbekannte Teile nie gutschreiben)
	for _, key in ipairs(if type(grant.Cars) == "table" then grant.Cars else {}) do
		if not knownCar(key) then
			return false, "unbekanntes Auto " .. tostring(key)
		end
	end
	for _, key in ipairs(if type(grant.Watches) == "table" then grant.Watches else {}) do
		if lifeKind(key) ~= "Watch" then
			return false, "unbekannte Uhr " .. tostring(key)
		end
	end
	for _, key in ipairs(if type(grant.Accessories) == "table" then grant.Accessories else {}) do
		if lifeKind(key) ~= "Accessory" then
			return false, "unbekanntes Accessoire " .. tostring(key)
		end
	end
	for key in pairs(if type(grant.Decor) == "table" then grant.Decor else {}) do
		if not knownDecor(key) then
			return false, "unbekannte Deko " .. tostring(key)
		end
	end
	return true, nil
end

local function ensureTable(parent: any, key: string): { [any]: any }
	if type(parent[key]) ~= "table" then
		parent[key] = {}
	end
	return parent[key]
end

-- Eine GEPRÜFTE Gewährung auf Daten-Ebene anwenden (rein, kein Spieler). Das ist die Daten-Abbildung jedes
-- Grant-Felds laut §C12 – für Test-Profile (SelfTest "Firewall"). Live bucht ShopService.Grant Fremd-Teile über
-- die Besitzer-APIs (die genau diese Felder schreiben) und nur CR/Kosmetik selbst.
function Core.ApplyGrant(data: any, grant: any)
	Core.Ensure(data)
	if isInteger(grant.Credits) and grant.Credits > 0 then
		data.Credits = math.min(MAX_MONEY, data.Credits + grant.Credits)
		data.Stats.LifetimeCredits = math.min(MAX_MONEY, data.Stats.LifetimeCredits + grant.Credits)
	end
	if type(grant.Cosmetics) == "table" then
		for _, key in ipairs(grant.Cosmetics) do
			addToCollection(data.Purchases.Cosmetics, key, COSMETICS_MAX)
		end
	end
	if type(grant.Titles) == "table" then
		local prog = ensureTable(data, "Prog")
		local titles = ensureTable(prog, "Titles")
		for _, key in ipairs(grant.Titles) do
			addToCollection(titles, key, TITLE_MAX)
		end
	end
	if type(grant.Cars) == "table" then
		local cars = ensureTable(ensureTable(data, "Garage"), "Cars")
		for _, key in ipairs(grant.Cars) do
			cars[key] = true
		end
	end
	if type(grant.Watches) == "table" then
		local watches = ensureTable(ensureTable(data, "Life"), "Watches")
		for _, key in ipairs(grant.Watches) do
			watches[key] = true
		end
	end
	if type(grant.Accessories) == "table" then
		local accessories = ensureTable(ensureTable(data, "Life"), "Accessories")
		for _, key in ipairs(grant.Accessories) do
			accessories[key] = true
		end
	end
	if type(grant.Decor) == "table" then
		local decor = ensureTable(ensureTable(data, "Storage"), "Decor")
		for key, n in pairs(grant.Decor) do
			decor[key] = math.clamp((if isInteger(decor[key]) then decor[key] else 0) + n, 0, DECOR_MAX)
		end
	end
	local boosts = ensureTable(data, "Boosts")
	for _, pair in ipairs({ { "BoostX2", "X2" }, { "BoostX5", "X5" } }) do
		local seconds = grant[pair[1]]
		if isInteger(seconds) and seconds > 0 then
			local before = if Util.IsFinite(boosts[pair[2]]) then boosts[pair[2]] else 0
			boosts[pair[2]] = math.min(NUMBER_MAX[pair[1]] or 2592000, before + seconds)
		end
	end
	local tower = ensureTable(data, "Tower")
	if isInteger(grant.ExpressTokens) and grant.ExpressTokens > 0 then
		table.insert(ensureTable(tower, "Express"), grant.ExpressTokens)
	end
	if isInteger(grant.InstantTokens) and grant.InstantTokens > 0 then
		local before = if isInteger(tower.Instant) then tower.Instant else 0
		tower.Instant = math.min(NUMBER_MAX.InstantTokens or 99, before + grant.InstantTokens)
	end
	local season = ensureTable(data, "Season")
	if grant.SeasonPremium == true then
		season.Premium = true
	end
	local xp = if Util.IsFinite(season.Xp) then season.Xp else 0
	if isInteger(grant.SeasonTiers) and grant.SeasonTiers > 0 then
		xp += grant.SeasonTiers * seasonTierXp()
	end
	if isInteger(grant.SeasonXp) and grant.SeasonXp > 0 then
		xp += grant.SeasonXp
	end
	season.Xp = math.min(MAX_MONEY, xp)
end

-- Saison-/Login-/Code-Belohnung (Config.Season/Rewards-Form) -> Types.Grant. Credits = { Minutes, Min } -> steady-
-- abhängig (Min als Untergrenze), Title -> Titles. Unbekannte Felder fallen weg (der Grant-Filter prüft danach).
function Core.RewardToGrant(reward: any, steadyPerSec: number?): { [string]: any }
	local grant: { [string]: any } = {}
	if type(reward) ~= "table" then
		return grant
	end
	for field, value in pairs(reward) do
		if field == "Credits" then
			if type(value) == "table" and Util.IsFinite(value.Minutes) and Util.IsFinite(value.Min) then
				local rate = if Util.IsFinite(steadyPerSec) then math.max(0, steadyPerSec :: number) else 0
				grant.Credits =
					math.clamp(math.max(math.floor(value.Min), math.floor(rate * value.Minutes * 60)), 0, MAX_MONEY)
			elseif isInteger(value) then
				grant.Credits = value
			end
		elseif field == "Title" then
			if type(value) == "string" then
				grant.Titles = { value }
			end
		elseif type(field) == "string" and SHOP.GrantFields[field] ~= nil then
			grant[field] = if type(value) == "table" then table.clone(value) else value
		end
	end
	return grant
end

-- Boutique-Rotation: `slots` verschiedene Schlüssel aus `pool`, deterministisch aus dem Zeitfenster (alle Server gleich)
function Core.Rotation(window: number, slots: number, pool: { string }): { string }
	local list: { string } = {}
	local want = math.min(math.max(0, math.floor(slots)), #pool)
	if want == 0 then
		return list
	end
	local attempts = 0
	while #list < want and attempts < want * 16 do
		attempts += 1
		local index = Util.Hash(("boutique:%d:%d"):format(window, attempts)) % #pool + 1
		local key = pool[index]
		if not table.find(list, key) then
			table.insert(list, key)
		end
	end
	-- Hash-Kollisionen: deterministisch mit den nächsten freien Teilen auffüllen
	for _, key in ipairs(pool) do
		if #list >= want then
			break
		end
		if not table.find(list, key) then
			table.insert(list, key)
		end
	end
	return list
end

-- =====================================================================
-- 5) METRIKEN (Quellen/Senken je Spieler gebündelt, alle 60 s an MetricsService.Economy)
-- =====================================================================
local function addMetric(p: Player, flow: string, tx: string, amount: number)
	if amount <= 0 or not present(p) then
		return
	end
	local acc = metricsAcc[p]
	if acc == nil then
		acc = {}
		metricsAcc[p] = acc
	end
	local key = flow .. "|" .. tx
	local entry = acc[key]
	if entry == nil then
		if (metricsCount[p] or 0) >= METRIC_ENTRIES_MAX then
			return
		end
		entry = { Flow = flow, Tx = tx, Amount = 0 }
		acc[key] = entry
		metricsCount[p] = (metricsCount[p] or 0) + 1
	end
	entry.Amount = math.min(MAX_MONEY, entry.Amount + amount)
end

local function flushMetrics(p: Player)
	local acc = metricsAcc[p]
	metricsAcc[p] = nil
	metricsCount[p] = nil
	if acc == nil then
		return
	end
	local balance = Core.Balance(dataOf(p))
	for _, entry in pairs(acc) do
		call("MetricsService", "Economy", p, entry.Flow, "CR", entry.Amount, balance, entry.Tx, nil)
	end
end

local function warnReason(reason: string)
	if warnedReasons[reason] or warnedCount >= WARN_REASONS_MAX then
		return
	end
	warnedReasons[reason] = true
	warnedCount += 1
	warn("[ShopService] Grant-Grund ohne CR-Quelle in der Whitelist: " .. reason .. " (CR werden als Event gebucht)")
end

-- =====================================================================
-- 6) CR-KONTO (einziger Gutschreiber/Abzieher, kein Yield)
-- =====================================================================
function ShopService.Credit(p: Player, amount: number, source: string): boolean
	local data = dataOf(p)
	if data == nil then
		return false
	end
	local ok, added = Core.Credit(data, amount, source)
	if not ok then
		warn(
			("[ShopService] Credit abgelehnt (%s, %s, %s)"):format(
				if typeof(p) == "Instance" then p.Name else "?",
				tostring(amount),
				tostring(source)
			)
		)
		return false
	end
	if added > 0 then
		addMetric(p, "Source", source, added)
		markDirty(p, "Credits")
	end
	return true
end

function ShopService.Debit(p: Player, amount: number, sink: string): boolean
	local data = dataOf(p)
	if data == nil then
		return false
	end
	if not Core.Debit(data, amount, sink) then
		return false -- zu wenig CR oder ungültige Senke/Menge: nichts abgezogen
	end
	addMetric(p, "Sink", sink, amount)
	markDirty(p, "Credits")
	return true
end

function ShopService.Balance(p: Player): number
	return Core.Balance(dataOf(p))
end

-- =====================================================================
-- 7) GEWÄHRUNG (alles-oder-nichts: erst prüfen, dann in einem Rutsch buchen, kein Yield)
-- =====================================================================
-- Fehlender Besitzer-Dienst für eine Gewährung (nil = alles da)
function ShopService.MissingFor(grant: any): string?
	if type(grant) ~= "table" then
		return nil
	end
	if grant.Cars ~= nil and not has("VehicleService", "GrantCar") then
		return "VehicleService.GrantCar"
	end
	if grant.Watches ~= nil and not has("LifestyleService", "GrantWatch") then
		return "LifestyleService.GrantWatch"
	end
	if grant.Accessories ~= nil and not has("LifestyleService", "GrantAccessory") then
		return "LifestyleService.GrantAccessory"
	end
	if grant.Decor ~= nil and not has("LifestyleService", "GrantDecor") then
		return "LifestyleService.GrantDecor"
	end
	if (grant.BoostX2 ~= nil or grant.BoostX5 ~= nil) and not has("TowerService", "AddBoost") then
		return "TowerService.AddBoost"
	end
	if
		grant.ExpressTokens ~= nil
		and (not has("TowerService", "AddExpressToken") or not has("TowerService", "ApplyExpress"))
	then
		return "TowerService.AddExpressToken"
	end
	if grant.InstantTokens ~= nil and not has("TowerService", "AddInstantToken") then
		return "TowerService.AddInstantToken"
	end
	if grant.SeasonPremium ~= nil and not has("RewardService", "GrantSeasonPremium") then
		return "RewardService.GrantSeasonPremium"
	end
	if grant.SeasonTiers ~= nil and not has("RewardService", "AddSeasonTiers") then
		return "RewardService.AddSeasonTiers"
	end
	if grant.SeasonXp ~= nil and not has("RewardService", "GrantSeasonXp") then
		return "RewardService.GrantSeasonXp"
	end
	return nil
end

-- Bau-Express möglich? (laufende Baustelle oder Platz im Token-Lager)
local function expressPossible(data: any): boolean
	local tower = type(data) == "table" and data.Tower or nil
	if type(tower) ~= "table" then
		return false
	end
	if type(tower.Build) == "table" and tower.Build.Floor ~= nil then
		return true
	end
	local buildCfg = type(Config.Tower) == "table" and Config.Tower.Build or nil
	local maxTokens = if type(buildCfg) == "table" and isInteger(buildCfg.ExpressMax) then buildCfg.ExpressMax else 50
	return (if type(tower.Express) == "table" then #tower.Express else 0) < maxTokens
end

local function allTrue(list: { string }, fn: (key: string) -> boolean): boolean
	local ok = true
	for _, key in ipairs(list) do
		if not fn(key) then
			ok = false
		end
	end
	return ok
end

local function resultTrue(okCall: boolean, result: any): boolean
	return okCall and result == true
end

-- Fremd-Teile in fester Reihenfolge: was am ehesten "nein" sagt, zuerst (dann ist noch nichts gebucht)
type Step = { Field: string, Run: (p: Player, value: any, reason: string) -> boolean }
local STEPS: { Step } = {
	{
		Field = "SeasonPremium",
		Run = function(p: Player, value: any, _reason: string): boolean
			if value ~= true then
				return true
			end
			return resultTrue(call("RewardService", "GrantSeasonPremium", p))
		end,
	},
	{
		Field = "ExpressTokens",
		Run = function(p: Player, seconds: any, _reason: string): boolean
			-- laufende Baustelle -> sofort verkürzen/beenden, sonst Token für den nächsten Bau
			if resultTrue(call("TowerService", "ApplyExpress", p, seconds)) then
				return true
			end
			return resultTrue(call("TowerService", "AddExpressToken", p, seconds))
		end,
	},
	{
		Field = "SeasonTiers",
		Run = function(p: Player, n: any, _reason: string): boolean
			local okCall = call("RewardService", "AddSeasonTiers", p, n)
			return okCall
		end,
	},
	{
		Field = "SeasonXp",
		Run = function(p: Player, n: any, reason: string): boolean
			local okCall = call("RewardService", "GrantSeasonXp", p, n, reason)
			return okCall
		end,
	},
	{
		Field = "Cars",
		Run = function(p: Player, list: any, _reason: string): boolean
			return allTrue(list, function(key: string): boolean
				return resultTrue(call("VehicleService", "GrantCar", p, key))
			end)
		end,
	},
	{
		Field = "Watches",
		Run = function(p: Player, list: any, _reason: string): boolean
			return allTrue(list, function(key: string): boolean
				return resultTrue(call("LifestyleService", "GrantWatch", p, key))
			end)
		end,
	},
	{
		Field = "Accessories",
		Run = function(p: Player, list: any, _reason: string): boolean
			return allTrue(list, function(key: string): boolean
				return resultTrue(call("LifestyleService", "GrantAccessory", p, key))
			end)
		end,
	},
	{
		Field = "Decor",
		Run = function(p: Player, map: any, _reason: string): boolean
			local ok = true
			for key, n in pairs(map) do
				if not resultTrue(call("LifestyleService", "GrantDecor", p, key, n)) then
					ok = false
				end
			end
			return ok
		end,
	},
	{
		Field = "BoostX2",
		Run = function(p: Player, seconds: any, _reason: string): boolean
			return resultTrue(call("TowerService", "AddBoost", p, "X2", seconds))
		end,
	},
	{
		Field = "BoostX5",
		Run = function(p: Player, seconds: any, _reason: string): boolean
			return resultTrue(call("TowerService", "AddBoost", p, "X5", seconds))
		end,
	},
	{
		Field = "InstantTokens",
		Run = function(p: Player, n: any, _reason: string): boolean
			return resultTrue(call("TowerService", "AddInstantToken", p, n))
		end,
	},
}

function ShopService.Grant(p: Player, grant: Types.Grant, reason: string): boolean
	local data = dataOf(p)
	if data == nil then
		return false
	end
	local why = if type(reason) == "string" and reason ~= "" then string.sub(reason, 1, 80) else "?"
	local robux = Core.IsRobux(why)
	local clean = Core.Sanitize(grant, robux)
	Core.Ensure(data)
	local ok, err = Core.ValidateGrant(data, clean)
	if not ok then
		warn(("[ShopService] Grant abgelehnt (%s, %s): %s"):format(p.Name, why, tostring(err)))
		return false
	end
	local missing = ShopService.MissingFor(clean)
	if missing then
		warn(("[ShopService] Grant (%s, %s) wartet: %s fehlt – später erneut"):format(p.Name, why, missing))
		return false
	end
	if isInteger(clean.ExpressTokens) and clean.ExpressTokens > 0 and not expressPossible(data) then
		warn(("[ShopService] Grant (%s, %s): Bau-Express-Lager voll"):format(p.Name, why))
		return false
	end
	-- Fremd-Teile über die Besitzer-APIs
	local applied = 0
	for _, step in ipairs(STEPS) do
		local value = clean[step.Field]
		if value ~= nil and value ~= false and value ~= 0 then
			if step.Run(p, value, why) then
				applied += 1
			elseif applied == 0 then
				warn(("[ShopService] Grant (%s, %s): %s abgelehnt – nichts gebucht"):format(p.Name, why, step.Field))
				return false
			else
				warn(
					("[ShopService] Grant (%s, %s): %s nicht gebucht (Teil-Gutschrift)"):format(p.Name, why, step.Field)
				)
			end
		end
	end
	-- eigene Teile (kein Yield)
	if isInteger(clean.Credits) and clean.Credits > 0 then
		local source = Core.SourceOf(why, robux)
		if source == nil then
			warnReason(why)
			source = "Event"
		end
		local okCredit, added = Core.Credit(data, clean.Credits, source :: string)
		if okCredit and added > 0 then
			addMetric(p, "Source", source :: string, added)
			markDirty(p, "Credits")
		end
	end
	if type(clean.Cosmetics) == "table" and #clean.Cosmetics > 0 then
		for _, key in ipairs(clean.Cosmetics) do
			addToCollection(data.Purchases.Cosmetics, key, COSMETICS_MAX)
		end
		markDirty(p, "Tower", "Garage", "Life") -- Fassaden/Neon/Lacke werden sofort wählbar
	end
	if type(clean.Titles) == "table" and #clean.Titles > 0 then
		local prog = ensureTable(data, "Prog")
		local titles = ensureTable(prog, "Titles")
		for _, key in ipairs(clean.Titles) do
			addToCollection(titles, key, TITLE_MAX)
		end
		markDirty(p, "Prog")
	end
	return true
end

-- Attribute Vip/Club (Namensschild, Chat-Tag, Lack, Balkon, Dachterrasse – Besitzer-Pakete lesen sie) + State
function ShopService.RefreshPlayer(p: Player)
	if not present(p) then
		return
	end
	local vip = hasPass(p, "VIP")
	if p:GetAttribute("Vip") ~= vip then
		p:SetAttribute("Vip", vip)
	end
	local member = isClub(p)
	if p:GetAttribute("Club") ~= member then
		p:SetAttribute("Club", member)
	end
	markDirty(p, "Passes", "Club", "Credits")
end

-- =====================================================================
-- 8) BOUTIQUE-ROTATION (4 h, deterministisch)
-- =====================================================================
local function rotationPool(): { string }
	local pool: { string } = {}
	local seen: { [string]: boolean } = {}
	local lifestyle = Config.Lifestyle
	local decor = Config.Decor
	local lists = {
		if type(lifestyle) == "table" then lifestyle.Watches else nil,
		if type(lifestyle) == "table" then lifestyle.Accessories else nil,
		if type(decor) == "table" then decor.Items else nil,
	}
	for i = 1, 3 do
		local list = lists[i]
		if type(list) == "table" then
			for _, entry in ipairs(list) do
				if
					type(entry) == "table"
					and entry.Source == "Shop"
					and Util.IsFinite(entry.Price)
					and entry.Price > 0
					and validKey(entry.Key)
					and not seen[entry.Key]
				then
					seen[entry.Key] = true
					table.insert(pool, entry.Key)
				end
			end
		end
	end
	table.sort(pool)
	return pool
end

function ShopService.Rotation(): { string }
	local hours = math.clamp(tonumber(SHOP.BoutiqueHours) or 4, 1, 48)
	local slots = math.clamp(math.floor(tonumber(SHOP.BoutiqueSlots) or 6), 1, 24)
	local window = math.floor(os.time() / (hours * 3600))
	local cache = rotationCache
	if cache == nil or cache.Window ~= window or cache.Slots ~= slots then
		cache = { Window = window, Slots = slots, Keys = Core.Rotation(window, slots, rotationPool()) }
		rotationCache = cache
	end
	return table.clone((cache :: any).Keys)
end

-- =====================================================================
-- 9) REQUEST-HANDLER (§C9) – Ablauf: exakte Schlüssel/Typen -> Daten -> Prüfen -> Buchen
-- =====================================================================
local function handleQuote(p: Player, arg: any): Reply
	if not exact(arg, { Key = "string" }, { "Key" }) or not validKey(arg.Key) then
		return fail(p, "core.invalid")
	end
	local product = SHOP.ProductsByKey[arg.Key]
	if product == nil or product.Kind ~= "Voucher" then
		return fail(p, "shop.unknown")
	end
	if dataOf(p) == nil then
		return fail(p, "core.loading")
	end
	local ok, creditsValue, untilT = call("MonetizationService", "Quote", p, arg.Key)
	if not ok or not isInteger(creditsValue) or not Util.IsFinite(untilT) then
		return fail(p, "core.error")
	end
	return { Ok = true, Credits = creditsValue, Until = untilT }
end

local function handlePrecheck(p: Player, arg: any): Reply
	if not exact(arg, { Key = "string", UserId = "number" }, { "Key" }) or not validKey(arg.Key) then
		return fail(p, "core.invalid")
	end
	local userId = arg.UserId
	if userId ~= nil and (not isInteger(userId) or math.abs(userId) > 2 ^ 53) then
		return fail(p, "core.invalid")
	end
	local monetization = service("MonetizationService")
	if monetization == nil or type(monetization.Precheck) ~= "function" then
		return fail(p, "shop.serviceMissing")
	end
	local ok, reply = pcall(monetization.Precheck, p, arg.Key, userId)
	if not ok or type(reply) ~= "table" then
		return fail(p, "core.error")
	end
	return reply
end

local function nextUtcMidnight(): number
	return (math.floor(os.time() / 86400) + 1) * 86400
end

local function steadyOf(p: Player): number
	local ok, info = call("TowerService", "Income", p)
	if ok and type(info) == "table" and Util.IsFinite(info.Steady) and info.Steady > 0 then
		return info.Steady
	end
	return 0
end

local function handleClubClaim(p: Player, arg: any): Reply
	if not exact(arg, {}, {}) then
		return fail(p, "core.invalid")
	end
	if not isClub(p) then
		return fail(p, "shop.club.notMember")
	end
	local data = dataOf(p)
	if data == nil then
		return fail(p, "core.loading")
	end
	Core.Ensure(data)
	local purchases = data.Purchases
	local today = Util.UtcDay()
	if purchases.ClubClaimDay == today then
		return fail(p, "shop.club.claimed", Format.Duration(nextUtcMidnight() - os.time(), langOf(p)))
	end
	local sub = SHOP.Subscription
	local voucher = SHOP.ProductsByKey[if type(sub) == "table" then sub.DailyVoucher else "CreditsS"]
	local amount = SHOP.VoucherCredits(voucher, steadyOf(p))
	if amount <= 0 or not ShopService.Grant(p, { Credits = amount }, "Robux:ClubDaily") then
		return fail(p, "core.error")
	end
	purchases.ClubClaimDay = today
	markDirty(p, "Offers")
	call("PlayerStateService", "Effect", p, "Confetti", 1, nil)
	return {
		Ok = true,
		Credits = amount,
		Message = Lang.T(langOf(p), "shop.club.claimOk", Format.Credits(amount, langOf(p))),
	}
end

-- =====================================================================
-- 10) INIT / START
-- =====================================================================
function ShopService.Init(services: any)
	Services = services
	local stateService = service("PlayerStateService")
	if stateService == nil or type(stateService.Handle) ~= "function" then
		warn("[ShopService] PlayerStateService fehlt – keine Shop-Anfragen")
		return
	end
	stateService.Provide("Credits", function(p: Player)
		return Core.Balance(dataOf(p))
	end)
	stateService.Handle("ShopQuote", handleQuote, { Rate = 1, Per = 1 })
	stateService.Handle("ShopPrecheck", handlePrecheck, { Rate = 2, Per = 1 })
	stateService.Handle("ShopClubClaim", handleClubClaim, { Rate = 1, Per = 1 })
end

function ShopService.Start()
	local stateService = service("PlayerStateService")
	if stateService and type(stateService.OnReady) == "function" then
		stateService.OnReady(function(p: Player)
			local data = dataOf(p)
			if data ~= nil then
				Core.Ensure(data)
			end
			ShopService.RefreshPlayer(p)
		end)
	end
	Players.PlayerRemoving:Connect(function(p: Player)
		local ok, err = pcall(flushMetrics, p)
		if not ok then
			warn("[ShopService] Metriken: " .. tostring(err))
		end
		metricsAcc[p] = nil
		metricsCount[p] = nil
	end)
	Scheduler.Every("ShopMetrics", 1 / METRICS_EVERY, function()
		for _, p in ipairs(Util.Snapshot(metricsAcc)) do
			flushMetrics(p)
		end
	end)
end

return ShopService
