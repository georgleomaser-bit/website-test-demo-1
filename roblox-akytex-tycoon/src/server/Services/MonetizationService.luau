-- =====================================================================
--  AKYTEX TYCOON – Robux: Gamepässe, Developer Products, Abo, PolicyService, Angebote (Server/Services/MonetizationService)
--  Besitzer: WP10 (Monetarisierung, Shop, CR-Konto). Vertrag: DESIGN.md §C5.9, §B14 (Pässe, Produkte, Abo, Angebots-
--  Regeln, Firewall & Policy), §B10.3 (Bullen-Parade/Feuerwerk), §C11.1 (idempotente Belege), §C11.4 (Firewall).
--  Basis: CLUTCH-CLASH-MonetizationService (REUSE §3.11, Kern 1:1 inkl. aller Runde-2-Fixes REUSE §7 #25/#26/#30).
--
--  ROBUX-FIREWALL (§0.4): Robux geben NUR Turm-Seite. Jede Gewährung läuft über ShopService.Grant (Grund "Robux:<Key>"),
--  dort streicht Core.Sanitize die ForbiddenRobuxFields; Types.Grant hat ohnehin keine AKY-/XP-/Lizenz-Felder. Keine
--  Funktion hier berührt Depot, Orders, Lizenz, XP, Know-how, Ruf oder Marktinfos.
--
--  ProcessReceipt (§C11.1, CC-Fluss exakt):
--    1. Callback früh in Start. Unbekanntes Produkt -> NotProcessedYet (+ warn "in Config eintragen").
--    2. Bis zu 60 s auf den Spielstand warten (Roblox ruft beim Beitritt oft VOR dem Laden auf).
--    3. Läuft dieselbe PurchaseId schon -> bis 60 s warten, dann Belege erneut prüfen. Beleg vorhanden -> Granted.
--    4. Alles Yieldende zuerst (prepare: Policy, Einkommen, Saison), dann OHNE Yield gutschreiben + Beleg (letzte 60)
--       + RobuxSpent in einem Rutsch.
--    5. PurchaseGranted erst nach erfolgreichem DataService.Save (Beleg steht im Stand -> nie doppelt).
--
--  Öffentliche API (§C5.9):
--    MonetizationService.HasPass(p, key): boolean          TycoonBundle zählt für Income2x/AutoCollect/OfflineVault
--    MonetizationService.PassFactor(p): number              1 / 2 / 3 / 4 (x2 + x3 = x4, nie x6)
--    MonetizationService.FixedFactor(p): number             VIP 1,10 × Club 1,15 × Roblox Premium 1,10
--    MonetizationService.IsClub(p): boolean
--    MonetizationService.LoadPasses(p)                      3 Versuche je Pass + Abo-Status, loading-Guard
--    MonetizationService.RandomAllowed(p): boolean?         nil = unbekannt = eingeschränkt behandeln
--    MonetizationService.TradingAllowed(p): boolean         IsPaidItemTradingAllowed == true (sonst false)
--    MonetizationService.SetPolicyOverride(p, field, value?)   Admin "Policy simulieren"; field = "Random" | "Trading" |
--                                                           "Subscription" | "All" (oder PolicyService-Feldname); nil = aus
--    MonetizationService.SimulatePurchase(p, productKey, purchaseId?): (boolean, string)   gleicher Weg wie ein echter
--                                                           Kauf (Id 0 ok); purchaseId fest = Idempotenz-Test
--    MonetizationService.TryOffer(p, offerKey): boolean    max. 1 Angebot je Sitzung + alle Regeln §B14.4
--    MonetizationService.Quote(p, productKey): (number?, number?)   CR-Angebot eines Bau-Gutscheins (+ gültig bis, Unix)
--  Zusätzlich (für ShopService/Admin/Tests): MonetizationService.Precheck(p, key, userId?): Reply ·
--    MonetizationService.ParadeUntil(): number · MonetizationService.Core (reine Entscheidungen für EconomyTests)
--  State-Schlüssel: Passes, Club, Boosts, Offers, RandomAllowed, TradingAllowed, Starter.
--  Braucht (zur Laufzeit, optional per pcall): DataService, PlayerStateService, ShopService, TowerService
--    (Income, SetServerBoost, OnStageUp), RewardService (SeasonPremium), EventService (StartParade, StartFireworks,
--    IsAdminAbuse), MarketService (OnNews), PlotService (PlotOf), MetricsService (Custom).
-- =====================================================================

local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Lang = require(Shared:WaitForChild("Lang"))
local Types = require(Shared:WaitForChild("Types"))
local Format = require(Shared:WaitForChild("Format"))

local MonetizationService = {}
local Services: any = nil

type Reply = Types.Reply
type Policy = { Random: boolean, Trading: boolean, Subscription: boolean }
type OfferCtx = {
	Shown: number,
	Max: number,
	Sessions: number,
	MinSession: number,
	SessionSeconds: number,
	MinSeconds: number,
	TutorialDone: boolean,
	AdminAbuse: boolean,
	MarketBlocked: boolean,
}

local SHOP: any = Config.Shop
local TECH: any = Config.Tech or {}

-- ---------------------------------------------------------------------
-- 1) KONSTANTEN
-- ---------------------------------------------------------------------
local MAX_MONEY = 9e15
local RECEIPT_KEEP = math.max(1, math.floor(tonumber(TECH.ReceiptKeep) or 60))
local PROFILE_WAIT = 60 -- Sekunden auf den Spielstand warten (Roblox ruft ProcessReceipt oft vor dem Laden)
local PROFILE_POLL = 0.25
local PROCESSING_WAIT = 60 -- Sekunden auf einen parallel laufenden gleichen Kauf warten
local PROCESSING_POLL = 0.2
local POLICY_WAIT = 10 -- prepare: so lange höchstens auf eine Policy-Antwort warten (danach: eingeschränkt)
local READY_WAIT = 20 -- prepare (Bau-Gutschein): so lange höchstens auf Pässe + Turm-Einkommen nach dem Beitritt warten
local POLICY_ATTEMPTS = 2
local POLICY_RETRY = 2
local PASS_ATTEMPTS = 3
local CLUB_ATTEMPTS = 2
local LOAD_WAIT_STEPS = 600 -- zweiter LoadPasses-Aufrufer wartet höchstens 60 s
local MAX_OFFERS = math.clamp(math.floor(tonumber(SHOP.MaxOffersPerSession) or 1), 0, 1)
local OFFER_MIN_SECONDS = math.max(0, (tonumber(SHOP.OfferMinMinutes) or 15) * 60)
local OFFER_MIN_SESSION = math.max(2, math.floor(tonumber(SHOP.OfferMinSession) or 2))
local OFFER_DELAY = math.max(0, tonumber(SHOP.OfferDelaySeconds) or 4)
local MARKET_BLOCK = math.max(0, tonumber(SHOP.OfferMarketBlockSeconds) or 900)
local QUOTE_SECONDS = math.max(60, math.floor(tonumber(SHOP.QuoteSeconds) or 600))
local GIFT_HOLD = math.max(10, tonumber(SHOP.GiftHoldSeconds) or 180)
local PRECHECK_POLICY_WAIT = math.max(1, tonumber(SHOP.PolicyWaitSeconds) or 5)
local PARADE: any = SHOP.Parade or {}
local PARADE_SECONDS = math.max(1, math.floor(tonumber(PARADE.Seconds) or 900))
local PARADE_CAP = math.max(PARADE_SECONDS, math.floor(tonumber(PARADE.CapSeconds) or 3600))
local FIREWORK_SECONDS = math.max(1, tonumber(SHOP.Fireworks and SHOP.Fireworks.Seconds) or 20)
local SUB: any = SHOP.Subscription or {}
local CLUB_KEY: string = if type(SUB.Key) == "string" then SUB.Key else "Club"
local MARKET_BLOCK_KINDS: { [string]: boolean } = { Warn = true, Crash = true, Rally = true }

-- Paket-Teil -> Pakete, die ihn enthalten (HasPass zählt Paket-Besitz wie Besitz der Teile)
local BUNDLES_FOR: { [string]: { string } } = {}
for _, pass in ipairs(SHOP.GamePasses or {}) do
	if type(pass.Includes) == "table" then
		for _, part in ipairs(pass.Includes) do
			BUNDLES_FOR[part] = BUNDLES_FOR[part] or {}
			table.insert(BUNDLES_FOR[part], pass.Key)
		end
	end
end

-- ---------------------------------------------------------------------
-- 2) ZUSTAND (jede Pro-Spieler-Tabelle wird bei PlayerRemoving geleert)
-- ---------------------------------------------------------------------
local owned: { [Player]: { [string]: boolean } } = {} -- Marktplatz-Besitz (geladen)
local loading: { [Player]: boolean } = {}
local passesLoaded: { [Player]: boolean } = {} -- Marktplatz-Besitz einmal vollständig geladen
local sessionPasses: { [Player]: { [string]: boolean } } = {} -- Admin-Simulation, nicht gespeichert
local club: { [Player]: boolean } = {} -- Abo-Status vom Marktplatz
local sessionClub: { [Player]: boolean } = {} -- Admin-Simulation
local policy: { [Player]: Policy } = {}
local policyStarted: { [Player]: boolean } = {}
local policyOverride: { [Player]: { [string]: boolean } } = {}
local offersShown: { [Player]: number } = {}
local offerState: { [Player]: { Key: string, Id: number, At: number } } = {}
local sessionStart: { [Player]: number } = {}
local giftTarget: { [Player]: { UserId: number, Until: number } } = {}
local processing: { [string]: boolean } = {} -- PurchaseIds, die gerade gutgeschrieben werden
local paradeUntil = 0 -- os.time(), serverweit (nicht gespeichert)
local marketBlockUntil = 0 -- os.time(): bis dahin kein Angebot (Warnung/Crash/Rally)
local offerSerial = 0

-- =====================================================================
-- 3) HELFER
-- =====================================================================
local function service(name: string): any
	return Services and Services[name]
end

-- optionaler Dienst über pcall: (ok, ergebnis …)
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

local function notify(p: Player, key: string, args: { any }?, kind: Types.NotifyKind?)
	call("PlayerStateService", "Notify", p, key, args, kind)
end

local function fail(p: Player, key: string, ...: any): Reply
	return { Ok = false, Message = Lang.T(langOf(p), key, ...) }
end

local function itemName(p: Player, entry: any): string
	return if type(entry) == "table" and type(entry.Name) == "table" then Lang.Pick(langOf(p), entry.Name) else "?"
end

local function credits(p: Player, n: number): string
	return Format.Credits(n, langOf(p))
end

local function isDisabled(key: string): boolean
	local disabled = SHOP.Disabled
	return type(disabled) == "table" and disabled[key] == true
end

local function currentSeasonId(): number
	return SHOP.SeasonIdAt(Config.Season, os.time())
end

local function purchasesOf(data: any): any
	if type(data.Purchases) ~= "table" then
		data.Purchases = {}
	end
	local purchases = data.Purchases
	if type(purchases.Receipts) ~= "table" then
		purchases.Receipts = {}
	end
	if type(purchases.PassSeasons) ~= "table" then
		purchases.PassSeasons = {}
	end
	if type(purchases.Quote) ~= "table" then
		purchases.Quote = {}
	end
	if not Util.IsFinite(purchases.RobuxSpent) or purchases.RobuxSpent < 0 then
		purchases.RobuxSpent = 0
	end
	if type(purchases.Starter) ~= "boolean" then
		purchases.Starter = false
	end
	if not isInteger(purchases.ClubClaimDay) then
		purchases.ClubClaimDay = 0
	end
	if not isInteger(purchases.Gifts) or purchases.Gifts < 0 then
		purchases.Gifts = 0
	end
	if not Util.IsFinite(purchases.StarterOfferedAt) then
		purchases.StarterOfferedAt = 0
	end
	return purchases
end

-- Dauer-Einkommen pro Sekunde ohne Zeitlich (TowerService.Income(p).Steady), 0 wenn unbekannt
local function steadyOf(p: Player): number
	local ok, info = call("TowerService", "Income", p)
	if ok and type(info) == "table" and Util.IsFinite(info.Steady) and info.Steady > 0 then
		return info.Steady
	end
	return 0
end

local function seasonPremiumOf(p: Player): boolean
	local ok, premium = call("RewardService", "SeasonPremium", p)
	return ok and premium == true
end

local function isPremiumMember(p: Player): boolean
	local ok, result = pcall(function(): boolean
		return p.MembershipType == Enum.MembershipType.Premium
	end)
	return ok and result == true
end

local function fixedMult(key: string): number
	local mult = type(Config.Tower) == "table" and Config.Tower.Mult or nil
	local value = type(mult) == "table" and mult[key] or nil
	if Util.IsFinite(value) and value >= 1 then
		return value
	end
	local fixed = SHOP.Fixed
	local fallback = type(fixed) == "table" and fixed[key] or nil
	return if Util.IsFinite(fallback) and fallback >= 1 then fallback else 1
end

local function paradeMult(): number
	local mult = type(Config.Tower) == "table" and Config.Tower.Mult or nil
	local value = type(mult) == "table" and mult.Parade or nil
	return if Util.IsFinite(value) and value > 1 then value else 1.5
end

local function itemOf(key: string): (any, string?)
	local pass = SHOP.PassesByKey[key]
	if pass then
		return pass, "Pass"
	end
	local product = SHOP.ProductsByKey[key]
	if product then
		return product, "Product"
	end
	if key == CLUB_KEY then
		return SUB, "Subscription"
	end
	return nil, nil
end

-- =====================================================================
-- 4) CORE – Entscheidungen ohne Roblox-Aufrufe (EconomyTests)
-- =====================================================================
local Core = {}
MonetizationService.Core = Core

function Core.HasReceipt(data: any, purchaseId: string): boolean
	local purchases = purchasesOf(data)
	for _, entry in ipairs(purchases.Receipts) do
		local id = if type(entry) == "table" then entry.Id else entry
		if tostring(id) == purchaseId then
			return true
		end
	end
	return false
end

-- key (optional) = Produkt-Schlüssel -> Admin-Tab "Belege" zeigt, WAS gekauft wurde
function Core.AddReceipt(data: any, purchaseId: string, now: number, key: string?)
	local receipts = purchasesOf(data).Receipts
	table.insert(receipts, { Id = purchaseId, T = now, Key = if type(key) == "string" then key else nil })
	while #receipts > RECEIPT_KEEP do
		table.remove(receipts, 1)
	end
end

-- Robux dürfen nie die ForbiddenRobuxFields geben -> Kopie ohne sie (Firewall §0.4)
function Core.Sanitize(grant: any): { [string]: any }
	local clean, removed = SHOP.SanitizeGrant(grant, true)
	for _, field in ipairs(removed) do
		warn("[MonetizationService] Verbotenes Robux-Feld gestrichen: " .. tostring(field))
	end
	return clean
end

-- Gültiges Angebot (Quote) eines Bau-Gutscheins oder nil
function Core.QuoteFor(data: any, key: string, now: number): number?
	local quotes = type(data) == "table" and type(data.Purchases) == "table" and data.Purchases.Quote or nil
	local entry = type(quotes) == "table" and quotes[key] or nil
	if type(entry) ~= "table" or not isInteger(entry.Credits) or not Util.IsFinite(entry.Until) then
		return nil
	end
	-- abgelaufen oder unplausibel weit in der Zukunft (Uhr-/Datenfehler) -> zählt nicht
	if entry.Until <= now or entry.Until > now + QUOTE_SECONDS then
		return nil
	end
	return math.clamp(entry.Credits, 0, MAX_MONEY)
end

-- CR eines Bau-Gutscheins beim Kauf: max(gültiges Angebot, Neuberechnung) – nie weniger als angezeigt (§B14.2)
function Core.VoucherCredits(product: any, steady: number, data: any, now: number): number
	local fresh = SHOP.VoucherCredits(product, steady)
	local quote = if type(product) == "table" then Core.QuoteFor(data, product.Key, now) else nil
	return math.clamp(math.max(fresh, quote or 0), 0, MAX_MONEY)
end

-- Was gibt dieser Kauf JETZT? ctx = { SeasonId, Steady, Now, RandomAllowed, Premium }
-- Rückgabe (grant, info); info = { Repeat, MarkStarter, MarkSeason, Vouchers = { { Key, Credits } } }
function Core.BuildGrant(product: any, data: any, ctx: { [string]: any }): ({ [string]: any }, { [string]: any })
	local purchases = purchasesOf(data)
	local now = if Util.IsFinite(ctx.Now) then ctx.Now else os.time()
	local seasonId = if isInteger(ctx.SeasonId) then ctx.SeasonId else 1
	local steady = if Util.IsFinite(ctx.Steady) then ctx.Steady else 0
	local info: { [string]: any } = { Repeat = false, MarkStarter = false, MarkSeason = false, Vouchers = {} }
	-- Ersatz statt Inhalt: Starter-Paket schon gekauft, Saison-Premium schon da, oder ein (nie vorhandenes)
	-- Zufallsprodukt bei eingeschränktem/unbekanntem Spieler
	local repeatCase = (product.Once == true and purchases.Starter == true)
		or (product.PerSeason == true and (purchases.PassSeasons[tostring(seasonId)] == true or ctx.Premium == true))
		or (product.Random == true and ctx.RandomAllowed ~= true)
	local base: any = product
	if repeatCase then
		base = if type(product.Repeat) == "table" then product.Repeat else {}
		info.Repeat = true
	end
	local grant = Core.Sanitize(base.Grant or {})
	local voucherKeys: { string } = {}
	if not repeatCase and product.Kind == "Voucher" then
		table.insert(voucherKeys, product.Key)
	end
	if type(base.Vouchers) == "table" then
		for _, key in ipairs(base.Vouchers) do
			table.insert(voucherKeys, key)
		end
	end
	local total = if isInteger(grant.Credits) then grant.Credits else 0
	for _, key in ipairs(voucherKeys) do
		local voucher = SHOP.ProductsByKey[key]
		if voucher and voucher.Kind == "Voucher" then
			local amount = Core.VoucherCredits(voucher, steady, data, now)
			table.insert(info.Vouchers, { Key = key, Credits = amount })
			total += amount
		end
	end
	if total > 0 then
		grant.Credits = math.clamp(math.floor(total), 0, MAX_MONEY)
	end
	if not repeatCase and product.Kind == "Express" and isInteger(product.Express) then
		grant.ExpressTokens = product.Express
	end
	info.MarkStarter = product.Once == true and not repeatCase
	info.MarkSeason = product.PerSeason == true and not repeatCase
	return grant, info
end

-- Bullen-Parade verlängern: +15 min, höchstens 60 min ab jetzt (§B10.3)
function Core.ExtendParade(currentUntil: number, now: number): number
	local base = math.max(now, if Util.IsFinite(currentUntil) then currentUntil else 0)
	return math.min(base + PARADE_SECONDS, now + PARADE_CAP)
end

-- Pässe-Faktor: x2 +1, x3 +2 -> 1 / 2 / 3 / 4 (ehrlich "x2 + x3 = x4", nie x6)
function Core.PassFactor(has2x: boolean, has3x: boolean): number
	return 1 + (if has2x then 1 else 0) + (if has3x then 2 else 0)
end

-- Fixe Faktoren: VIP × Club × Roblox Premium (Werte aus Config.Tower.Mult, Rückfall Config.Shop.Fixed)
function Core.FixedFactor(vip: boolean, isClub: boolean, premium: boolean): number
	local factor = 1
	if vip then
		factor *= fixedMult("Vip")
	end
	if isClub then
		factor *= fixedMult("Club")
	end
	if premium then
		factor *= fixedMult("Premium")
	end
	return factor
end

-- Roher Besitz -> wirksamer Besitz (Paket zählt für seine Teile)
function Core.EffectivePasses(raw: { [string]: boolean }): { [string]: boolean }
	local result: { [string]: boolean } = {}
	for _, pass in ipairs(SHOP.GamePasses) do
		result[pass.Key] = raw[pass.Key] == true
	end
	for part, bundles in pairs(BUNDLES_FOR) do
		for _, bundle in ipairs(bundles) do
			if raw[bundle] == true then
				result[part] = true
			end
		end
	end
	return result
end

-- PolicyService-Antwort -> Erlaubnisse (fail-closed: Fehler/fehlendes Feld = NICHT erlaubt)
function Core.ParsePolicy(info: any): Policy
	if type(info) ~= "table" then
		return { Random = false, Trading = false, Subscription = false }
	end
	return {
		Random = info.ArePaidRandomItemsRestricted == false,
		Trading = info.IsPaidItemTradingAllowed == true,
		Subscription = info.IsEligibleToPurchaseSubscription == true,
	}
end

-- Angebots-Regeln §B14.4 (ohne Artikel-Prüfung). Rückgabe (erlaubt, Grund)
function Core.OfferCheck(ctx: OfferCtx): (boolean, string)
	if ctx.Shown >= ctx.Max then
		return false, "MaxPerSession"
	end
	if ctx.Sessions < ctx.MinSession then
		return false, "FirstSession"
	end
	if ctx.SessionSeconds < ctx.MinSeconds then
		return false, "TooEarly"
	end
	if not ctx.TutorialDone then
		return false, "Tutorial"
	end
	if ctx.AdminAbuse then
		return false, "AdminAbuse"
	end
	if ctx.MarketBlocked then
		return false, "MarketWarning"
	end
	return true, "Ok"
end

-- Geschenk-Gate: beide Seiten IsPaidItemTradingAllowed == true (unbekannt = gesperrt), nie an sich selbst
function Core.GiftCheck(
	buyerAllowed: boolean?,
	targetAllowed: boolean?,
	isSelf: boolean,
	targetPresent: boolean
): (boolean, string)
	if isSelf then
		return false, "shop.giftSelfNot"
	end
	if not targetPresent then
		return false, "shop.giftTargetGone"
	end
	if buyerAllowed ~= true or targetAllowed ~= true then
		return false, "shop.giftBlocked"
	end
	return true, "Ok"
end

-- Der eigentliche Beleg-Ablauf mit austauschbarer Umgebung (echte Dienste oder Test-Attrappen).
-- env: FindPlayer(userId), Product(productId), WaitData(p), CurrentData(p), Prepare(p, product),
--      Grant(p, data, product, prepared) -> boolean (darf NICHT yielden), Save(p) -> boolean, Wait(s)
function Core.ProcessReceiptWith(receipt: any, env: any): Enum.ProductPurchaseDecision
	local NOT_YET = Enum.ProductPurchaseDecision.NotProcessedYet
	if type(receipt) ~= "table" then
		return NOT_YET
	end
	local player = env.FindPlayer(receipt.PlayerId)
	if player == nil then
		return NOT_YET -- Roblox versucht es beim nächsten Beitritt erneut
	end
	local product = env.Product(receipt.ProductId)
	if product == nil then
		warn(
			("[MonetizationService] Unbekannte ProductId %s – in Config.Shop.Products eintragen!"):format(
				tostring(receipt.ProductId)
			)
		)
		return NOT_YET -- nie einen Kauf "verschlucken"
	end
	local data = env.WaitData(player)
	if data == nil then
		return NOT_YET
	end
	local purchaseId = tostring(receipt.PurchaseId)
	-- gleicher Kauf läuft schon: warten statt NotProcessedYet (REUSE §7 #25)
	local polls = math.ceil(PROCESSING_WAIT / PROCESSING_POLL)
	for _ = 1, polls do
		if not processing[purchaseId] then
			break
		end
		env.Wait(PROCESSING_POLL)
	end
	if processing[purchaseId] then
		return NOT_YET
	end
	if Core.HasReceipt(data, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	processing[purchaseId] = true
	local okPrepare, prepared = pcall(env.Prepare, player, product)
	local granted = false
	if okPrepare and env.CurrentData(player) == data and not Core.HasReceipt(data, purchaseId) then
		-- ab hier KEIN Yield: gutschreiben + Beleg + RobuxSpent in einem Rutsch (REUSE §7 #26)
		local okGrant, result = pcall(env.Grant, player, data, product, prepared)
		granted = okGrant and result == true
		if not okGrant then
			warn("[MonetizationService] Gutschrift fehlgeschlagen: " .. tostring(result))
		end
		if granted then
			Core.AddReceipt(data, purchaseId, os.time(), if type(product) == "table" then product.Key else nil)
			local purchases = purchasesOf(data)
			local spent = tonumber(receipt.CurrencySpent)
			if spent and Util.IsFinite(spent) and spent > 0 then
				purchases.RobuxSpent += spent
			end
		end
	elseif not okPrepare then
		warn("[MonetizationService] Vorbereitung fehlgeschlagen: " .. tostring(prepared))
	end
	processing[purchaseId] = nil
	if not granted then
		return NOT_YET
	end
	if env.Save(player) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	-- Speichern ging nicht: Beleg steht im Spielstand -> nächster Versuch erkennt ihn, nie doppelt
	return NOT_YET
end

-- =====================================================================
-- 5) GAMEPÄSSE & ABO
-- =====================================================================
local function rawHas(p: Player, key: string): boolean
	local passes = owned[p]
	local session = sessionPasses[p]
	return (passes ~= nil and passes[key] == true) or (session ~= nil and session[key] == true)
end

function MonetizationService.HasPass(p: Player, key: string): boolean
	if type(key) ~= "string" then
		return false
	end
	if rawHas(p, key) then
		return true
	end
	local bundles = BUNDLES_FOR[key]
	if bundles then
		for _, bundle in ipairs(bundles) do
			if rawHas(p, bundle) then
				return true -- Tycoon-Paket = Besitz aller drei Teile (§B14.1)
			end
		end
	end
	return false
end

function MonetizationService.PassFactor(p: Player): number
	return Core.PassFactor(MonetizationService.HasPass(p, "Income2x"), MonetizationService.HasPass(p, "Income3x"))
end

function MonetizationService.IsClub(p: Player): boolean
	return club[p] == true or sessionClub[p] == true
end

function MonetizationService.FixedFactor(p: Player): number
	return Core.FixedFactor(MonetizationService.HasPass(p, "VIP"), MonetizationService.IsClub(p), isPremiumMember(p))
end

local function refresh(p: Player)
	if not present(p) then
		return
	end
	call("ShopService", "RefreshPlayer", p) -- Attribute Vip/Club + MarkDirty
	call("TowerService", "Refresh", p) -- Multiplikator-Chip sofort neu (§0.8 Punkt 3: sofort sichtbare Wirkung)
	markDirty(p, "Passes", "Club", "Offers", "Starter")
end

-- Abo-Status vom Marktplatz (pcall, 2 Versuche; Fehler = kein Club, nächster Statuswechsel prüft erneut)
local function fetchClub(p: Player): boolean
	local id = SUB.Id
	if type(id) ~= "string" or id == "" then
		return false
	end
	for attempt = 1, CLUB_ATTEMPTS do
		local ok, info = pcall(MarketplaceService.GetUserSubscriptionStatusAsync, MarketplaceService, p, id)
		if ok then
			return type(info) == "table" and info.IsSubscribed == true
		end
		if attempt < CLUB_ATTEMPTS and p.Parent == Players then
			task.wait(attempt)
		end
	end
	return false
end

function MonetizationService.LoadPasses(p: Player)
	if passesLoaded[p] then
		return
	end
	if loading[p] then
		-- zweiter Aufruf wartet auf den ersten (REUSE §7 #30: kein doppeltes Laden)
		for _ = 1, LOAD_WAIT_STEPS do
			if not loading[p] or p.Parent ~= Players then
				break
			end
			task.wait(0.1)
		end
		return
	end
	loading[p] = true
	local result: { [string]: boolean } = {}
	for _, pass in ipairs(SHOP.GamePasses) do
		if isInteger(pass.Id) and pass.Id > 0 then
			for attempt = 1, PASS_ATTEMPTS do
				local ok, hasPass =
					pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, p.UserId, pass.Id)
				if ok then
					result[pass.Key] = hasPass == true
					break
				end
				if attempt < PASS_ATTEMPTS and p.Parent == Players then
					task.wait(attempt)
				end
			end
		end
	end
	local member = if p.Parent == Players then fetchClub(p) else false
	loading[p] = nil
	if p.Parent ~= Players then
		return
	end
	-- während des Ladens gekaufte Pässe (PromptGamePassPurchaseFinished) nie wieder verlieren
	local early = owned[p]
	if early then
		for key, value in pairs(early) do
			if value == true then
				result[key] = true
			end
		end
	end
	owned[p] = result
	passesLoaded[p] = true
	club[p] = member
	refresh(p)
end

local function onPassPurchased(p: Player, passId: number, purchased: boolean)
	if not purchased or not isInteger(passId) or not present(p) then
		return
	end
	local pass = SHOP.PassesById[passId]
	if pass == nil then
		return
	end
	local passes = owned[p]
	if passes == nil then
		passes = {}
		owned[p] = passes
	end
	passes[pass.Key] = true
	refresh(p)
	notify(p, "shop.passThanks", { itemName(p, pass) }, "Success")
	call("PlayerStateService", "Effect", p, "Confetti", 2, nil)
	call("MetricsService", "Custom", p, "PassBought", pass.Price, { Key = pass.Key })
end

local function onSubscriptionChanged(p: Player, subscriptionId: string)
	if not present(p) or subscriptionId ~= SUB.Id then
		return
	end
	task.spawn(function()
		local before = club[p] == true
		local member = fetchClub(p)
		if not present(p) then
			return
		end
		club[p] = member
		refresh(p)
		if member and not before then
			notify(p, "shop.club.welcome", nil, "Success")
			call("PlayerStateService", "Effect", p, "Confetti", 2, nil)
			call("MetricsService", "Custom", p, "ClubJoined", 1, nil)
		end
	end)
end

-- =====================================================================
-- 6) POLICYSERVICE (einmal je Spieler, pcall, unbekannt/Fehler = eingeschränkt)
-- =====================================================================
local function fetchPolicy(p: Player)
	local info: any = nil
	for attempt = 1, POLICY_ATTEMPTS do
		local ok, result = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, p)
		if ok and type(result) == "table" then
			info = result
			break
		end
		if p.Parent ~= Players then
			return
		end
		if attempt < POLICY_ATTEMPTS then
			task.wait(POLICY_RETRY)
		end
	end
	if p.Parent ~= Players then
		return
	end
	policy[p] = Core.ParsePolicy(info)
	markDirty(p, "RandomAllowed", "TradingAllowed", "Offers")
end

local function ensurePolicy(p: Player)
	if not policyStarted[p] and present(p) then
		policyStarted[p] = true
		task.spawn(fetchPolicy, p) -- nie im Aufrufer yielden
	end
end

-- Wert eines Policy-Felds: Debug-Zwang -> Admin-Override -> bekannt -> nil (Anfrage läuft)
local function policyValue(p: Player, field: string): boolean?
	local debugConfig = Config.Debug
	if type(debugConfig) == "table" and debugConfig.ForceRestricted == true then
		return false
	end
	local override = policyOverride[p]
	if override ~= nil and override[field] ~= nil then
		return override[field]
	end
	local known = policy[p]
	if known ~= nil then
		return (known :: any)[field] == true
	end
	ensurePolicy(p)
	return nil
end

-- höchstens `seconds` auf eine Policy-Antwort warten (yieldet; nur in prepare/Anfrage-Handlern)
local function waitPolicy(p: Player, field: string, seconds: number): boolean?
	local value = policyValue(p, field)
	local steps = math.ceil(seconds / 0.25)
	for _ = 1, steps do
		if value ~= nil or p.Parent ~= Players then
			break
		end
		task.wait(0.25)
		value = policyValue(p, field)
	end
	return value
end

function MonetizationService.RandomAllowed(p: Player): boolean?
	if not present(p) then
		return nil
	end
	return policyValue(p, "Random")
end

function MonetizationService.TradingAllowed(p: Player): boolean
	if not present(p) then
		return false
	end
	return policyValue(p, "Trading") == true
end

local OVERRIDE_FIELDS: { [string]: { Field: string, Invert: boolean } } = {
	Random = { Field = "Random", Invert = false },
	RandomAllowed = { Field = "Random", Invert = false },
	ArePaidRandomItemsRestricted = { Field = "Random", Invert = true },
	Trading = { Field = "Trading", Invert = false },
	TradingAllowed = { Field = "Trading", Invert = false },
	IsPaidItemTradingAllowed = { Field = "Trading", Invert = false },
	Subscription = { Field = "Subscription", Invert = false },
	IsEligibleToPurchaseSubscription = { Field = "Subscription", Invert = false },
}

function MonetizationService.SetPolicyOverride(p: Player, field: string, value: boolean?)
	if typeof(p) ~= "Instance" or not p:IsA("Player") then
		return
	end
	local rawField: any = field
	local rawValue: any = value
	-- CC-Form SetPolicyOverride(p, allowed?) = Zufallsitems
	if type(rawField) == "boolean" or rawField == nil then
		rawValue = rawField
		rawField = "Random"
	end
	if rawValue ~= nil and type(rawValue) ~= "boolean" then
		return
	end
	local targets: { { Field: string, Invert: boolean } } = {}
	if rawField == "All" then
		targets = {
			{ Field = "Random", Invert = false },
			{ Field = "Trading", Invert = false },
			{ Field = "Subscription", Invert = false },
		}
	elseif type(rawField) == "string" and OVERRIDE_FIELDS[rawField] then
		targets = { OVERRIDE_FIELDS[rawField] }
	else
		warn("[MonetizationService] SetPolicyOverride: unbekanntes Feld " .. tostring(rawField))
		return
	end
	local entry = policyOverride[p] or {}
	for _, target in ipairs(targets) do
		if rawValue == nil then
			entry[target.Field] = nil
		elseif target.Invert then
			entry[target.Field] = not rawValue
		else
			entry[target.Field] = rawValue
		end
	end
	policyOverride[p] = if next(entry) ~= nil then entry else nil
	markDirty(p, "RandomAllowed", "TradingAllowed", "Offers")
end

-- =====================================================================
-- 7) PRODUKTE GUTSCHREIBEN (alles Yieldende in prepare, Gutschrift ohne Yield)
-- =====================================================================
-- Bau-Gutscheine rechnen mit dem Dauer-Einkommen: kommt der Beleg direkt beim Beitritt (offener Kauf aus der
-- letzten Sitzung), erst Pässe/Turm-Einkommen abwarten (höchstens READY_WAIT s) – sonst gäbe es nur den Mindestwert.
local function waitSteady(p: Player): number
	local steady = steadyOf(p)
	for _ = 1, math.ceil(READY_WAIT / 0.25) do
		if p.Parent ~= Players then
			break
		end
		local okReady, ready = call("PlayerStateService", "IsReady", p)
		if steady > 0 and (not okReady or ready == true) then
			break
		end
		task.wait(0.25)
		steady = steadyOf(p)
	end
	return steady
end

local function usesVouchers(product: any): boolean
	local again = product.Repeat
	return product.Kind == "Voucher"
		or type(product.Vouchers) == "table"
		or (type(again) == "table" and type(again.Vouchers) == "table")
end

local function prepare(p: Player, product: any): { [string]: any }
	local prepared: { [string]: any } = {
		SeasonId = currentSeasonId(),
		Steady = if usesVouchers(product) then waitSteady(p) else steadyOf(p),
		Premium = if product.Kind == "Season" then seasonPremiumOf(p) else false,
		RandomAllowed = nil,
		Gift = nil,
	}
	if product.Random == true then
		-- Policy-Antwort abwarten (höchstens 10 s), danach gilt: unbekannt = eingeschränkt
		prepared.RandomAllowed = waitPolicy(p, "Random", POLICY_WAIT)
	end
	if product.Gift == true then
		local hold = giftTarget[p]
		local target = if hold and hold.Until >= os.time() then Players:GetPlayerByUserId(hold.UserId) else nil
		if target and target ~= p then
			local buyerOk = waitPolicy(p, "Trading", POLICY_WAIT)
			local targetOk = waitPolicy(target, "Trading", POLICY_WAIT)
			local ok = Core.GiftCheck(buyerOk, targetOk, false, target.Parent == Players)
			if ok then
				prepared.Gift = target
			end
		end
	end
	return prepared
end

local function plotOf(p: Player): number?
	local ok, plot = call("PlotService", "PlotOf", p)
	return if ok and isInteger(plot) then plot else nil
end

local function markAllDirty(...: string)
	for _, other in ipairs(Players:GetPlayers()) do
		markDirty(other, ...)
	end
end

-- Bullen-Parade: ×1,5 für alle (TowerService), Show + Dank-Banner (EventService, sonst Effekt direkt) – EIN Weg
local function grantParade(p: Player): boolean
	local tower = service("TowerService")
	if tower == nil or type(tower.SetServerBoost) ~= "function" then
		return false -- später erneut (Kauf bleibt offen)
	end
	local t = os.time()
	local untilT = Core.ExtendParade(paradeUntil, t)
	local seconds = untilT - t
	local okBoost, err = pcall(tower.SetServerBoost, "Parade", paradeMult(), seconds)
	if not okBoost then
		warn("[MonetizationService] Bullen-Parade: " .. tostring(err))
		return false
	end
	paradeUntil = untilT
	local okEvent = call("EventService", "StartParade", p, seconds)
	if not okEvent then
		call(
			"PlayerStateService",
			"EffectAll",
			"BullParade",
			1,
			{ Seconds = seconds, UserId = p.UserId, Until = untilT },
			nil
		)
	end
	markAllDirty("Offers")
	return true
end

local function grantFireworks(p: Player): boolean
	local okEvent = call("EventService", "StartFireworks", p)
	if not okEvent then
		call(
			"PlayerStateService",
			"EffectAll",
			"Fireworks",
			1,
			{ Seconds = FIREWORK_SECONDS, UserId = p.UserId, Plot = plotOf(p) },
			nil
		)
	end
	return true
end

-- Rückmeldung nach einer Gewährung (kein Yield, eine Meldung je Ereignis)
local function feedback(p: Player, product: any, grant: { [string]: any }, info: { [string]: any }, receiver: Player)
	local credited = if isInteger(grant.Credits) then grant.Credits else 0
	if product.Kind == "Gift" then
		if receiver ~= p then
			notify(p, "shop.giftSent", { receiver.DisplayName }, "Success")
			notify(receiver, "shop.giftReceived", { p.DisplayName }, "Success")
			call("PlayerStateService", "Effect", receiver, "Confetti", 1, nil)
		else
			notify(p, "shop.giftSelf", nil, "Info")
		end
	elseif info.Repeat and product.Kind == "Starter" then
		notify(p, "shop.starterRepeat", { credits(p, credited) }, "Info")
	elseif info.Repeat and product.Kind == "Season" then
		notify(p, "shop.seasonRepeat", { credits(p, credited) }, "Info")
	elseif product.Kind == "Voucher" then
		notify(p, "shop.voucherGranted", { credits(p, credited), itemName(p, product) }, "Success")
	else
		notify(p, "shop.thanks", { itemName(p, product) }, "Success")
	end
	call("PlayerStateService", "Effect", p, "Confetti", 1, nil)
end

-- Gutschrift eines Produkts – yieldet NIE (§C11.1). true = komplett gutgeschrieben.
local function grantProduct(p: Player, data: any, product: any, prepared: any): boolean
	local shopService = service("ShopService")
	if shopService == nil or type(shopService.Grant) ~= "function" then
		return false -- später erneut (Kauf bleibt offen)
	end
	local kind = product.Kind
	if kind == "Parade" then
		if not grantParade(p) then
			return false
		end
		notify(p, "shop.thanks", { itemName(p, product) }, "Success")
		return true
	elseif kind == "Fireworks" then
		grantFireworks(p)
		notify(p, "shop.thanks", { itemName(p, product) }, "Success")
		return true
	end
	local ctx = {
		SeasonId = if type(prepared) == "table" then prepared.SeasonId else currentSeasonId(),
		Steady = if type(prepared) == "table" then prepared.Steady else 0,
		Now = os.time(),
		RandomAllowed = if type(prepared) == "table" then prepared.RandomAllowed else nil,
		Premium = type(prepared) == "table" and prepared.Premium == true,
	}
	local grant, info = Core.BuildGrant(product, data, ctx)
	local receiver = p
	if kind == "Gift" and type(prepared) == "table" then
		local target = prepared.Gift
		if
			typeof(target) == "Instance"
			and target ~= p
			and target.Parent == Players
			and dataOf(target :: Player) ~= nil
		then
			receiver = target :: Player
		end
	end
	if next(grant) ~= nil and not shopService.Grant(receiver, grant, "Robux:" .. tostring(product.Key)) then
		return false
	end
	local purchases = purchasesOf(data)
	if info.MarkStarter then
		purchases.Starter = true
	end
	if info.MarkSeason then
		purchases.PassSeasons[tostring(ctx.SeasonId)] = true
	end
	if kind == "Gift" then
		giftTarget[p] = nil
		if receiver ~= p then
			purchases.Gifts += 1
		end
	end
	feedback(p, product, grant, info, receiver)
	call("MetricsService", "Custom", p, "ProductBought", product.Price, { Key = product.Key })
	markDirty(p, "Offers", "Starter")
	return true
end

local function waitForData(p: Player): any
	local dataService = service("DataService")
	if dataService == nil then
		return nil
	end
	for _ = 1, math.ceil(PROFILE_WAIT / PROFILE_POLL) do
		if p.Parent ~= Players then
			return nil
		end
		local data = dataService.Get(p)
		if data ~= nil then
			return data
		end
		task.wait(PROFILE_POLL)
	end
	return nil
end

local function realEnv(productLookup: (id: any) -> any): any
	return {
		FindPlayer = function(userId: any): Player?
			return if isInteger(userId) then Players:GetPlayerByUserId(userId) else nil
		end,
		Product = productLookup,
		WaitData = waitForData,
		CurrentData = dataOf,
		Prepare = prepare,
		Grant = grantProduct,
		Save = function(p: Player): boolean
			local dataService = service("DataService")
			if dataService == nil then
				return false
			end
			local ok, saved = pcall(dataService.Save, p)
			return ok and saved == true
		end,
		Wait = function(seconds: number)
			task.wait(seconds)
		end,
	}
end

local RECEIPT_ENV = realEnv(function(id: any): any
	return if isInteger(id) and id > 0 then SHOP.ProductsById[id] else nil
end)

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local ok, decision = pcall(Core.ProcessReceiptWith, receipt, RECEIPT_ENV)
	if ok then
		return decision
	end
	warn("[MonetizationService] ProcessReceipt Fehler: " .. tostring(decision))
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- =====================================================================
-- 8) ADMIN-SIMULATION (gleiche Gutschrift wie ein echter Kauf, auch mit Id = 0)
-- =====================================================================
-- purchaseId (optional, nur SelfTest/Admin): feste Beleg-Id, um die Idempotenz live zu prüfen (gleiche Id = eine Gewährung)
function MonetizationService.SimulatePurchase(p: Player, productKey: string, purchaseId: string?): (boolean, string)
	if not present(p) then
		return false, "Spieler nicht im Spiel"
	end
	if type(productKey) ~= "string" then
		return false, "Produkt-Key fehlt"
	end
	local pass = SHOP.PassesByKey[productKey]
	if pass then
		local session = sessionPasses[p]
		if session == nil then
			session = {}
			sessionPasses[p] = session
		end
		session[pass.Key] = true
		refresh(p)
		notify(p, "shop.simulated", { itemName(p, pass) }, "Info")
		return true, "Pass " .. pass.Key .. " für diese Sitzung aktiv"
	end
	if productKey == CLUB_KEY then
		sessionClub[p] = true
		refresh(p)
		notify(p, "shop.simulated", { itemName(p, SUB) }, "Info")
		return true, "Vorstands-Club für diese Sitzung aktiv"
	end
	local product = SHOP.ProductsByKey[productKey]
	if product == nil then
		return false, "Unbekanntes Produkt " .. productKey
	end
	local env = realEnv(function(_id: any): any
		return product
	end)
	local receipt = {
		PlayerId = p.UserId,
		ProductId = product.Id,
		PurchaseId = if type(purchaseId) == "string"
				and purchaseId ~= ""
				and #purchaseId <= 64
			then purchaseId
			else "SIM-" .. HttpService:GenerateGUID(false),
		CurrencySpent = 0,
	}
	local ok, decision = pcall(Core.ProcessReceiptWith, receipt, env)
	if ok and decision == Enum.ProductPurchaseDecision.PurchaseGranted then
		return true, "Kauf simuliert: " .. productKey
	end
	return false, "Simulation nicht gutgeschrieben (" .. tostring(decision) .. ")"
end

function MonetizationService.ParadeUntil(): number
	return paradeUntil
end

-- =====================================================================
-- 9) BAU-GUTSCHEIN-ANGEBOT (10 min gültig, fester Ablauf; Gewährung max(Angebot, Neuberechnung))
-- =====================================================================
local function pruneQuotes(purchases: any, now: number)
	for key, entry in pairs(purchases.Quote) do
		local product = SHOP.ProductsByKey[key]
		if
			type(entry) ~= "table"
			or product == nil
			or product.Kind ~= "Voucher"
			or not Util.IsFinite(entry.Until)
			or entry.Until <= now
		then
			purchases.Quote[key] = nil
		end
	end
end

function MonetizationService.Quote(p: Player, productKey: string): (number?, number?)
	local product = if type(productKey) == "string" then SHOP.ProductsByKey[productKey] else nil
	if product == nil or product.Kind ~= "Voucher" then
		return nil, nil
	end
	local data = dataOf(p)
	if data == nil then
		return nil, nil
	end
	local t = os.time()
	local purchases = purchasesOf(data)
	pruneQuotes(purchases, t)
	local fresh = SHOP.VoucherCredits(product, steadyOf(p))
	local existing = Core.QuoteFor(data, productKey, t)
	if existing ~= nil then
		-- Ablauf bleibt fest (kein Neustart); die Zahl steigt mit, sinkt aber nie
		local entry = purchases.Quote[productKey]
		entry.Credits = math.max(existing, fresh)
		markDirty(p, "Offers")
		return entry.Credits, entry.Until
	end
	local untilT = t + QUOTE_SECONDS
	purchases.Quote[productKey] = { Credits = fresh, Until = untilT }
	markDirty(p, "Offers")
	return fresh, untilT
end

-- =====================================================================
-- 10) KAUF-VORPRÜFUNG (ShopPrecheck): Policy, Empfänger, Besitz – vor Prompt…Purchase (darf yielden)
-- =====================================================================
local function seasonTierInfo(data: any): (number, number)
	local seasonCfg = Config.Season
	local seasons = type(seasonCfg) == "table" and seasonCfg.Seasons or nil
	local id = currentSeasonId()
	local entry: any = nil
	if type(seasons) == "table" then
		for _, s in ipairs(seasons) do
			if type(s) == "table" and s.Id == id then
				entry = s
			end
		end
		entry = entry or seasons[#seasons]
	end
	local tiers = if entry and isInteger(entry.Tiers) then entry.Tiers else 50
	local tierXp = if entry and Util.IsFinite(entry.TierXp) and entry.TierXp > 0 then entry.TierXp else 1000
	local season = type(data) == "table" and data.Season or nil
	if type(season) ~= "table" or season.Id ~= id or not Util.IsFinite(season.Xp) then
		return 0, tiers -- neue Saison: Stufe 0
	end
	return math.clamp(math.floor(season.Xp / tierXp), 0, tiers), tiers
end

local function expressRoom(data: any): boolean
	local tower = type(data) == "table" and data.Tower or nil
	if type(tower) ~= "table" then
		return false
	end
	local build = tower.Build
	if type(build) == "table" and build.Floor ~= nil then
		return true -- laufende Baustelle: wird direkt verkürzt
	end
	local buildCfg = type(Config.Tower) == "table" and Config.Tower.Build or nil
	local maxTokens = if type(buildCfg) == "table" and isInteger(buildCfg.ExpressMax) then buildCfg.ExpressMax else 50
	local tokens = if type(tower.Express) == "table" then #tower.Express else 0
	return tokens < maxTokens
end

function MonetizationService.Precheck(p: Player, key: string, userId: number?): Reply
	if not present(p) then
		return { Ok = false }
	end
	local item, kind = itemOf(key)
	if item == nil or kind == nil then
		return fail(p, "shop.unknown")
	end
	if isDisabled(key) then
		return fail(p, "shop.disabled")
	end
	local studio = RunService:IsStudio()
	local data = dataOf(p)
	if data == nil then
		return fail(p, "core.loading")
	end
	if kind == "Pass" then
		if not (isInteger(item.Id) and item.Id > 0) then
			return fail(p, "shop.notSetUp")
		end
		if MonetizationService.HasPass(p, key) then
			return fail(p, if rawHas(p, key) then "shop.owned" else "shop.passInBundle")
		end
		if type(item.Includes) == "table" then
			local missing = 0
			for _, part in ipairs(item.Includes) do
				if not MonetizationService.HasPass(p, part) then
					missing += 1
				end
			end
			if missing == 0 then
				return fail(p, "shop.bundleAllOwned")
			end
		end
		return { Ok = true, Kind = "Pass", Id = item.Id }
	elseif kind == "Subscription" then
		if type(SUB.Id) ~= "string" or SUB.Id == "" then
			return fail(p, "shop.notSetUp")
		end
		if MonetizationService.IsClub(p) then
			return fail(p, "shop.club.already")
		end
		if waitPolicy(p, "Subscription", PRECHECK_POLICY_WAIT) ~= true then
			return fail(p, "shop.restricted")
		end
		return { Ok = true, Kind = "Subscription", Id = SUB.Id }
	end
	-- Developer Product. Id 0 wird erst NACH allen anderen Prüfungen gemeldet, damit Studio-Tests (Policy simulieren,
	-- Geschenk-Gate, Lager voll …) den echten Weg sehen; danach Hinweis auf Admin "Kauf simulieren".
	local configuredId = isInteger(item.Id) and item.Id > 0
	local function notConfigured(): Reply
		return fail(p, if studio then "shop.studioSim" else "shop.notSetUp")
	end
	if not configuredId and not studio then
		return notConfigured()
	end
	if item.Random == true and waitPolicy(p, "Random", PRECHECK_POLICY_WAIT) ~= true then
		return fail(p, "shop.restricted")
	end
	local purchases = purchasesOf(data)
	local productKind = item.Kind
	-- fehlt ein Besitzer-Dienst für die Gewährung, würde der Kauf bis zum nächsten Beitritt offen bleiben
	local provisional = Core.BuildGrant(item, data, {
		SeasonId = currentSeasonId(),
		Steady = 0,
		Now = os.time(),
		RandomAllowed = false,
		Premium = false,
	})
	local okMissing, missing = call("ShopService", "MissingFor", provisional)
	if not okMissing or missing ~= nil then
		return fail(
			p,
			if productKind == "Season" or productKind == "Tiers" then "shop.seasonOffline" else "shop.serviceMissing"
		)
	end
	if productKind == "Season" then
		if seasonPremiumOf(p) then
			return fail(p, "shop.seasonOwned")
		end
	elseif productKind == "Tiers" then
		local tier, tiers = seasonTierInfo(data)
		if tier >= tiers then
			return fail(p, "shop.tiersFull")
		end
		-- nie Stufen verkaufen, die es nicht mehr gibt (ehrlich: lieber das kleinere Paket empfehlen)
		local wanted = if type(item.Grant) == "table" and isInteger(item.Grant.SeasonTiers)
			then item.Grant.SeasonTiers
			else 1
		if tier + wanted > tiers then
			return fail(p, "shop.tiersTooMany", tiers - tier)
		end
	elseif productKind == "Express" then
		if not expressRoom(data) then
			return fail(p, "shop.expressFull")
		end
	elseif productKind == "Parade" then
		if not has("TowerService", "SetServerBoost") then
			return fail(p, "shop.serviceMissing")
		end
	elseif productKind == "Gift" then
		if not isInteger(userId) then
			return fail(p, "shop.giftPick")
		end
		local target = Players:GetPlayerByUserId(userId :: number)
		local isSelf = userId == p.UserId
		local targetPresent = target ~= nil and target.Parent == Players and dataOf(target :: Player) ~= nil
		local buyerOk = waitPolicy(p, "Trading", PRECHECK_POLICY_WAIT)
		local targetOk = if target and not isSelf
			then waitPolicy(target :: Player, "Trading", PRECHECK_POLICY_WAIT)
			else false
		local ok, reason = Core.GiftCheck(buyerOk, targetOk, isSelf, targetPresent)
		if not ok then
			return fail(p, reason)
		end
		giftTarget[p] = { UserId = userId :: number, Until = os.time() + GIFT_HOLD }
		if not configuredId then
			return notConfigured()
		end
		return {
			Ok = true,
			Kind = "Product",
			Id = item.Id,
			Gift = { UserId = userId, Name = (target :: Player).DisplayName },
		}
	end
	if not configuredId then
		return notConfigured()
	end
	return { Ok = true, Kind = "Product", Id = item.Id, Repeat = item.Once == true and purchases.Starter == true }
end

-- =====================================================================
-- 11) ANGEBOTE (§B14.4, Muss-Regel 17)
-- =====================================================================
local function offerContext(p: Player, data: any): OfferCtx
	local flags = type(data.Flags) == "table" and data.Flags or {}
	local okAbuse, abuse = call("EventService", "IsAdminAbuse")
	local started = sessionStart[p]
	return {
		Shown = offersShown[p] or 0,
		Max = MAX_OFFERS,
		Sessions = if isInteger(data.Sessions) then data.Sessions else 0,
		MinSession = OFFER_MIN_SESSION,
		SessionSeconds = if started then os.clock() - started else 0,
		MinSeconds = OFFER_MIN_SECONDS,
		TutorialDone = flags.Done == true,
		AdminAbuse = okAbuse and abuse == true,
		MarketBlocked = os.time() < marketBlockUntil,
	}
end

-- Lohnt sich das Angebot für diesen Spieler überhaupt? (nichts Besessenes, nichts Gesperrtes, eingerichtet)
local function offerItemOk(p: Player, key: string, data: any): boolean
	local item, kind = itemOf(key)
	if item == nil or kind == nil or isDisabled(key) then
		return false
	end
	local configured = if kind == "Subscription"
		then type(SUB.Id) == "string" and SUB.Id ~= ""
		else isInteger(item.Id) and item.Id > 0
	if not configured and not RunService:IsStudio() then
		return false
	end
	local purchases = purchasesOf(data)
	if kind == "Pass" then
		if MonetizationService.HasPass(p, key) then
			return false
		end
		if type(item.Includes) == "table" then
			for _, part in ipairs(item.Includes) do
				if MonetizationService.HasPass(p, part) then
					return false -- Teil schon da: die Karte empfiehlt Einzelkäufe, kein Popup
				end
			end
		end
		return true
	elseif kind == "Subscription" then
		return not MonetizationService.IsClub(p) and policyValue(p, "Subscription") == true
	end
	if item.Once == true then
		return purchases.Starter ~= true and purchases.StarterOfferedAt <= 0
	end
	if item.PerSeason == true then
		return purchases.PassSeasons[tostring(currentSeasonId())] ~= true and not seasonPremiumOf(p)
	end
	return item.Random ~= true
end

function MonetizationService.TryOffer(p: Player, offerKey: string): boolean
	if not present(p) or type(offerKey) ~= "string" then
		return false
	end
	local data = dataOf(p)
	if data == nil then
		return false
	end
	local ok = Core.OfferCheck(offerContext(p, data))
	if not ok or not offerItemOk(p, offerKey, data) then
		return false
	end
	local item = itemOf(offerKey)
	if type(item) == "table" and item.Once == true then
		purchasesOf(data).StarterOfferedAt = os.time() -- Starter-Angebot genau einmal je Konto
	end
	offersShown[p] = (offersShown[p] or 0) + 1
	offerSerial += 1
	offerState[p] = { Key = offerKey, Id = offerSerial, At = os.time() }
	markDirty(p, "Offers", "Starter")
	call("MetricsService", "Custom", p, "OfferShown", 1, { Key = offerKey })
	return true
end

-- automatisches Angebot nach einem positiven Moment: erstes passendes aus Config.Shop.OfferOrder
local function autoOffer(p: Player)
	if not present(p) or (offersShown[p] or 0) >= MAX_OFFERS then
		return
	end
	for _, key in ipairs(SHOP.OfferOrder or {}) do
		if MonetizationService.TryOffer(p, key) then
			return
		end
	end
end

-- =====================================================================
-- 12) STATE-SCHLÜSSEL (§C10; nie nil für "leer")
-- =====================================================================
local function voucherPreview(p: Player): { [string]: number }
	local steady = steadyOf(p)
	local preview: { [string]: number } = {}
	for _, product in ipairs(SHOP.Products) do
		if product.Kind == "Voucher" then
			preview[product.Key] = SHOP.VoucherCredits(product, steady)
		end
	end
	return preview
end

local function offersState(p: Player): { [string]: any }
	local data = dataOf(p)
	local t = os.time()
	local quotes: { [string]: any } = {}
	local claimDay, gifts = 0, 0
	local passSeasons: { [string]: boolean } = {}
	if data ~= nil then
		local purchases = purchasesOf(data)
		for _, product in ipairs(SHOP.Products) do
			if product.Kind == "Voucher" then
				local quoted = Core.QuoteFor(data, product.Key, t)
				if quoted ~= nil then
					quotes[product.Key] = { Credits = quoted, Until = purchases.Quote[product.Key].Until }
				end
			end
		end
		claimDay = purchases.ClubClaimDay
		gifts = purchases.Gifts
		passSeasons = purchases.PassSeasons
	end
	local offer = offerState[p]
	local hold = giftTarget[p]
	return {
		Pending = if offer then offer.Key else "",
		Id = if offer then offer.Id else 0,
		Shown = offersShown[p] or 0,
		Max = MAX_OFFERS,
		Quotes = quotes,
		Preview = voucherPreview(p),
		QuoteSeconds = QUOTE_SECONDS,
		ClubEligible = policyValue(p, "Subscription") == true,
		ClubClaimDay = claimDay,
		Today = Util.UtcDay(),
		Gifts = gifts,
		Gift = if hold and hold.Until >= t then { UserId = hold.UserId, Until = hold.Until } else false,
		Parade = paradeUntil,
		Season = currentSeasonId(),
		PassSeasons = passSeasons,
		SeasonPremium = seasonPremiumOf(p),
		Disabled = if type(SHOP.Disabled) == "table" then SHOP.Disabled else {},
	}
end

local function registerState()
	local stateService = service("PlayerStateService")
	if stateService == nil or type(stateService.Provide) ~= "function" then
		warn("[MonetizationService] PlayerStateService fehlt – kein Shop-State")
		return
	end
	stateService.Provide("Passes", function(p: Player)
		local result: { [string]: boolean } = {}
		for _, pass in ipairs(SHOP.GamePasses) do
			result[pass.Key] = MonetizationService.HasPass(p, pass.Key)
		end
		return result
	end)
	stateService.Provide("Club", function(p: Player)
		return MonetizationService.IsClub(p)
	end)
	stateService.Provide("Boosts", function(p: Player)
		local data = dataOf(p)
		local boosts = data and data.Boosts
		local function seconds(key: string): number
			local value = if type(boosts) == "table" then boosts[key] else nil
			return if Util.IsFinite(value) and value > 0 then value else 0
		end
		return { X2 = seconds("X2"), X5 = seconds("X5"), Bull = seconds("Bull") }
	end)
	stateService.Provide("Offers", offersState)
	stateService.Provide("RandomAllowed", function(p: Player)
		return MonetizationService.RandomAllowed(p) == true -- unbekannt = eingeschränkt (false), nie nil
	end)
	stateService.Provide("TradingAllowed", function(p: Player)
		return MonetizationService.TradingAllowed(p)
	end)
	stateService.Provide("Starter", function(p: Player)
		local data = dataOf(p)
		if data == nil then
			return { Bought = false, Offered = false, Eligible = false }
		end
		local purchases = purchasesOf(data)
		local sessions = if isInteger(data.Sessions) then data.Sessions else 0
		return {
			Bought = purchases.Starter == true,
			Offered = purchases.StarterOfferedAt > 0,
			Eligible = sessions >= OFFER_MIN_SESSION,
		}
	end)
end

-- =====================================================================
-- 13) INIT / START
-- =====================================================================
local function onPlayerRemoving(p: Player)
	owned[p] = nil
	loading[p] = nil
	passesLoaded[p] = nil
	sessionPasses[p] = nil
	club[p] = nil
	sessionClub[p] = nil
	policy[p] = nil
	policyStarted[p] = nil
	policyOverride[p] = nil
	offersShown[p] = nil
	offerState[p] = nil
	sessionStart[p] = nil
	giftTarget[p] = nil
end

local function onPlayerAdded(p: Player)
	sessionStart[p] = os.clock()
	ensurePolicy(p) -- Policy schon beim Beitritt anfragen (PlayerStateService ruft RandomAllowed zusätzlich)
end

function MonetizationService.Init(services: any)
	Services = services
	registerState()
end

function MonetizationService.Start()
	-- §C11.1 #1: früh setzen (ohne Callback quittiert Roblox Käufe automatisch -> verloren)
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPassPurchased)
	Players.UserSubscriptionStatusChanged:Connect(onSubscriptionChanged)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, p)
	end
	-- Crash/Rally-Warnung -> eine Weile kein Angebot (Muss-Regel 17)
	call("MarketService", "OnNews", function(news: any)
		if type(news) == "table" and MARKET_BLOCK_KINDS[tostring(news.Kind)] then
			marketBlockUntil = math.max(marketBlockUntil, os.time() + MARKET_BLOCK)
		end
	end)
	-- positiver Moment (Stufen-Morph) -> kurz danach höchstens ein Angebot (Callback yieldet nie)
	call("TowerService", "OnStageUp", function(p: Player, _stage: number)
		if present(p) and (offersShown[p] or 0) < MAX_OFFERS then
			task.delay(OFFER_DELAY, autoOffer, p)
		end
	end)
end

return MonetizationService
