-- =====================================================================
--  CLUTCH CLASH – Robux: GamePässe, Developer Products, PolicyService (Server/Services/MonetizationService)
--  Besitzer: WP9 (Wirtschaft, Monetarisierung, Kosmetik). Vertrag: DESIGN.md C5.9, B20.2, B22, B23.
--  Basis: Meteor-Heist-MonetizationService (REUSE §7) mit den Fixes aus REUSE §14.3 #5–#7.
--
--  KEIN PAY-TO-WIN (Muss-Regel 4): Robux geben NIE Münzen, Waffen, Schlüssel, Splitter oder Werte.
--  Jeder Kauf läuft über ShopService.Grant; verbotene Felder werden vor dem Gutschreiben gestrichen.
--
--  ProcessReceipt (B22.3):
--    1. Callback früh in Start. Unbekanntes Produkt -> NotProcessedYet.
--    2. Bis zu 60 s auf den Spielstand warten (Roblox ruft beim Beitritt oft VOR dem Laden auf).
--    3. Läuft dieselbe PurchaseId schon -> warten, dann Belege erneut prüfen.
--    4. Alles Yieldende zuerst (prepare), dann OHNE Yield gutschreiben + Beleg eintragen (letzte 60).
--    5. PurchaseGranted erst nach erfolgreichem DataService.Save (Beleg steht im Stand -> nie doppelt).
--    6. Zufallsprodukte gibt es nicht – die Prüfung (eingeschränkt -> Ersatz) steht trotzdem im Code.
--
--  Öffentliche API (C5.9):
--    MonetizationService.HasPass(p, key): boolean
--    MonetizationService.LoadPasses(p)                         3 Versuche je Pass, loading-Guard
--    MonetizationService.RandomAllowed(p): boolean?             nil = unbekannt (= eingeschränkt behandeln)
--    MonetizationService.SetPolicyOverride(p, allowed?)         Admin "Policy simulieren" (nil = aus)
--    MonetizationService.SimulatePurchase(p, productKey): (boolean, string)   gleicher Weg wie ein echter Kauf
--    MonetizationService.PartyXpActive(): boolean
--    MonetizationService.TryOffer(p, offerKey): boolean        max. 1 Angebot pro Sitzung, nie in Live-Runde
--  Zusätzlich: MonetizationService.PartyUntil(): number, MonetizationService.Core (für EconomyTests).
--  State-Schlüssel: Passes, RandomAllowed, Boosts, Offer.
-- =====================================================================

local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Lang = require(Shared:WaitForChild("Lang"))
local Types = require(Shared:WaitForChild("Types"))

local MonetizationService = {}
local Services: any = nil

local SHOP: any = Config.Shop
local TECH: any = Config.Tech or {}

local RECEIPT_KEEP = math.max(1, math.floor(tonumber(TECH.ReceiptKeep) or 60))
local PROFILE_WAIT = 60 -- Sekunden auf den Spielstand warten (B22.3 #2)
local PROFILE_POLL = 0.25
local PROCESSING_WAIT = 60 -- Sekunden auf einen parallel laufenden gleichen Kauf warten
local PROCESSING_POLL = 0.2
local POLICY_WAIT = 10 -- prepare: so lange höchstens auf die Policy-Antwort warten
local PASS_ATTEMPTS = 3
local STARTER_HOURS = math.max(24, tonumber(SHOP.StarterOfferHours) or 72)
local MAX_OFFERS = math.max(0, math.floor(tonumber(SHOP.MaxOffersPerSession) or 1))
local PARTY_SECONDS = math.max(1, tonumber(SHOP.PartyBoost and SHOP.PartyBoost.Seconds) or 900)
local PARTY_CAP = math.max(PARTY_SECONDS, tonumber(SHOP.PartyBoost and SHOP.PartyBoost.CapSeconds) or 3600)
-- Phasen, in denen KEIN Angebot erscheinen darf (B23.1: nie während einer laufenden Runde)
local BLOCKED_PHASES: { [string]: boolean } =
	{ Load = true, Intro = true, Prep = true, Live = true, Overtime = true, RoundEnd = true }

local owned: { [Player]: { [string]: boolean } } = {}
local loading: { [Player]: boolean } = {}
local sessionPasses: { [Player]: { [string]: boolean } } = {} -- Admin-Simulation, nicht gespeichert
local policy: { [Player]: boolean } = {} -- true = Zufallsitems erlaubt, false = eingeschränkt (bekannt)
local policyStarted: { [Player]: boolean } = {}
local policyOverride: { [Player]: boolean } = {}
local offersShown: { [Player]: number } = {}
local processing: { [string]: boolean } = {} -- PurchaseIds, die gerade gutgeschrieben werden
local partyUntil = 0 -- os.time(), serverweit (nicht gespeichert)

-- =====================================================================
-- 1) HELFER
-- =====================================================================
local function service(name: string): any
	return Services and Services[name]
end

local function try(name: string, fnName: string, ...: any): (boolean, any)
	local s = service(name)
	if s == nil or type(s[fnName]) ~= "function" then
		return false, nil
	end
	return pcall(s[fnName], ...)
end

local function dataOf(p: Player): any
	local dataService = service("DataService")
	return if dataService then dataService.Get(p) else nil
end

local function langOf(p: Player): Types.Lang
	local ok, lang = try("PlayerStateService", "LangOf", p)
	return if ok and (lang == "de" or lang == "en") then lang else "en"
end

local function markDirty(p: Player, ...: string)
	local stateService = service("PlayerStateService")
	if stateService and type(stateService.MarkDirty) == "function" then
		stateService.MarkDirty(p, ...)
	end
end

local function notify(p: Player, key: string, args: { any }?, kind: Types.NotifyKind?)
	try("PlayerStateService", "Notify", p, key, args, kind)
end

local function refreshShop(p: Player)
	try("ShopService", "RefreshPlayer", p)
	markDirty(p, "Passes", "Loadouts", "Cosmetics")
end

local function isInteger(n: any): boolean
	return Util.IsFinite(n) and (n :: number) % 1 == 0
end

local function currentSeasonId(): number
	local ok, season = try("ProgressionService", "Season")
	if ok and type(season) == "table" and isInteger(season.Id) then
		return season.Id
	end
	return SHOP.SeasonIdAt(Config.Season and Config.Season.Seasons, os.time())
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
	if type(purchases.FirstPack) ~= "table" then
		purchases.FirstPack = {}
	end
	if not Util.IsFinite(purchases.RobuxSpent) then
		purchases.RobuxSpent = 0
	end
	if not isInteger(purchases.Supporter) then
		purchases.Supporter = 0
	end
	if not Util.IsFinite(purchases.StarterOfferedAt) then
		purchases.StarterOfferedAt = 0
	end
	if type(purchases.Starter) ~= "boolean" then
		purchases.Starter = false
	end
	return purchases
end

-- =====================================================================
-- 2) CORE – Entscheidungen ohne Roblox-Aufrufe (EconomyTests)
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

function Core.AddReceipt(data: any, purchaseId: string, now: number)
	local receipts = purchasesOf(data).Receipts
	table.insert(receipts, { Id = purchaseId, T = now })
	while #receipts > RECEIPT_KEEP do
		table.remove(receipts, 1)
	end
end

-- Robux dürfen nie diese Felder geben -> Kopie ohne sie (Muss-Regel 4)
function Core.Sanitize(grant: any): { [string]: any }
	local clean: { [string]: any } = {}
	if type(grant) ~= "table" then
		return clean
	end
	for field, value in pairs(grant) do
		if table.find(SHOP.ForbiddenRobuxFields, field) then
			warn("[Monetization] Verbotenes Robux-Feld gestrichen: " .. tostring(field))
		elseif type(value) == "table" then
			clean[field] = table.clone(value)
		else
			clean[field] = value
		end
	end
	return clean
end

-- Was gibt dieser Kauf JETZT? (Erstkauf ×2, einmalig, pro Saison, Zufall eingeschränkt)
-- Gibt (grant, info) zurück; info = { FirstBonus, Fallback, SeasonId, MarkSeason, MarkStarter }
function Core.BuildGrant(product: any, data: any, seasonId: number, randomAllowed: boolean?): ({ [string]: any }, any)
	local purchases = purchasesOf(data)
	local info = { FirstBonus = false, Fallback = false, SeasonId = seasonId, MarkSeason = false, MarkStarter = false }
	-- Ersatz statt Inhalt, wenn: Starter-Paket schon gekauft (-> 120 Gems), Premium dieser Saison
	-- schon da (-> 500 Gems) oder Zufallsprodukt bei eingeschränktem Spieler (gibt es nicht -> fester Ersatz)
	info.Fallback = (product.Once == true and purchases.Starter == true)
		or (product.PerSeason == true and purchases.PassSeasons[tostring(seasonId)] == true)
		or (product.Random == true and randomAllowed ~= true)
	local grant = Core.Sanitize(if info.Fallback then product.Fallback else product.Grant)
	if not info.Fallback then
		if product.FirstBonus and purchases.FirstPack[product.Key] ~= true and isInteger(grant.Gems) then
			grant.Gems *= 2 -- erster Kauf jedes Gem-Pakets doppelt (B23.5)
			info.FirstBonus = true
		end
		info.MarkSeason = product.PerSeason == true
		info.MarkStarter = product.Once == true
	end
	return grant, info
end

-- Party-Boost verlängern: +15 min, höchstens 60 min ab jetzt (B22.2)
function Core.ExtendParty(currentUntil: number, now: number): number
	local base = math.max(now, currentUntil)
	return math.min(base + PARTY_SECONDS, now + PARTY_CAP)
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
			("[Monetization] Unbekannte ProductId %s – in Config.Shop.Products eintragen!"):format(
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
	-- gleicher Kauf läuft schon: warten statt NotProcessedYet (REUSE §14.3 #6)
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
		-- ab hier KEIN Yield: gutschreiben + Beleg in einem Rutsch (REUSE §14.3 #7)
		local okGrant, result = pcall(env.Grant, player, data, product, prepared)
		granted = okGrant and result == true
		if not okGrant then
			warn("[Monetization] Gutschrift fehlgeschlagen: " .. tostring(result))
		end
		if granted then
			Core.AddReceipt(data, purchaseId, os.time())
			local purchases = purchasesOf(data)
			local spent = tonumber(receipt.CurrencySpent)
			if spent and Util.IsFinite(spent) and spent > 0 then
				purchases.RobuxSpent += spent
			end
		end
	elseif not okPrepare then
		warn("[Monetization] Vorbereitung fehlgeschlagen: " .. tostring(prepared))
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
-- 3) GAMEPÄSSE
-- =====================================================================
function MonetizationService.HasPass(p: Player, key: string): boolean
	local passes = owned[p]
	local session = sessionPasses[p]
	return (passes ~= nil and passes[key] == true) or (session ~= nil and session[key] == true)
end

function MonetizationService.LoadPasses(p: Player)
	if owned[p] then
		return
	end
	if loading[p] then
		-- zweiter Aufruf wartet auf den ersten (MH-Fix: kein doppeltes Laden)
		for _ = 1, 600 do
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
				local ok, has = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, p.UserId, pass.Id)
				if ok then
					result[pass.Key] = has == true
					break
				end
				if attempt < PASS_ATTEMPTS then
					task.wait(attempt)
				end
			end
		end
	end
	loading[p] = nil
	if p.Parent ~= Players then
		return
	end
	owned[p] = result
	refreshShop(p)
end

local function passByKey(key: string): any
	return SHOP.PassesByKey[key]
end

local function onPassPurchased(p: Player, passId: number, purchased: boolean)
	if not purchased or not isInteger(passId) then
		return
	end
	local pass = SHOP.PassesById[passId]
	if pass == nil or p.Parent ~= Players then
		return
	end
	local passes = owned[p]
	if passes == nil then
		passes = {}
		owned[p] = passes
	end
	passes[pass.Key] = true
	refreshShop(p)
	notify(p, "shop.passThanks", { Lang.Pick(langOf(p), pass.Name) }, "Success")
	try("PlayerStateService", "Effect", p, "Confetti", 2, nil)
end

-- =====================================================================
-- 4) POLICYSERVICE (einmal pro Spieler, in pcall, unbekannt/Fehler = eingeschränkt)
-- =====================================================================
local function fetchPolicy(p: Player)
	local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, p)
	if p.Parent ~= Players then
		return
	end
	policy[p] = ok and type(info) == "table" and info.ArePaidRandomItemsRestricted == false
	markDirty(p, "RandomAllowed")
end

function MonetizationService.RandomAllowed(p: Player): boolean?
	local debugConfig = Config.Debug
	if type(debugConfig) == "table" and debugConfig.ForceRestricted == true then
		return false
	end
	local override = policyOverride[p]
	if override ~= nil then
		return override
	end
	local known = policy[p]
	if known ~= nil then
		return known
	end
	if not policyStarted[p] and typeof(p) == "Instance" and p.Parent == Players then
		policyStarted[p] = true
		task.spawn(fetchPolicy, p) -- nie im Aufrufer yielden
	end
	return nil
end

function MonetizationService.SetPolicyOverride(p: Player, allowed: boolean?)
	if typeof(p) ~= "Instance" or not p:IsA("Player") then
		return
	end
	if allowed == nil then
		policyOverride[p] = nil
	else
		policyOverride[p] = allowed == true
	end
	markDirty(p, "RandomAllowed")
end

-- =====================================================================
-- 5) PRODUKTE GUTSCHREIBEN (alles Yieldende in prepare, Gutschrift ohne Yield)
-- =====================================================================
local function prepare(p: Player, product: any): any
	local randomAllowed: boolean? = nil
	if product.Random == true then
		-- Policy-Antwort abwarten (höchstens 10 s), danach gilt: unbekannt = eingeschränkt
		for _ = 1, POLICY_WAIT * 4 do
			randomAllowed = MonetizationService.RandomAllowed(p)
			if randomAllowed ~= nil or p.Parent ~= Players then
				break
			end
			task.wait(0.25)
		end
	end
	return { SeasonId = currentSeasonId(), RandomAllowed = randomAllowed }
end

local function announceParty(p: Player)
	local stateService = service("PlayerStateService")
	if stateService == nil then
		return
	end
	if type(stateService.EffectAll) == "function" then
		stateService.EffectAll("PartyBoost", 1, { Name = p.DisplayName, Until = partyUntil })
	end
	if type(stateService.NotifyAll) == "function" then
		stateService.NotifyAll("shop.partyBoost", { p.DisplayName }, "Event")
	end
	for _, other in ipairs(Players:GetPlayers()) do
		markDirty(other, "Boosts")
	end
end

-- Gutschrift eines Produkts – yieldet NIE (B22.3 #4). true = komplett gutgeschrieben.
local function grantProduct(p: Player, data: any, product: any, prepared: any): boolean
	local shopService = service("ShopService")
	if shopService == nil or type(shopService.Grant) ~= "function" then
		return false -- später erneut (Kauf bleibt offen)
	end
	local seasonId = if type(prepared) == "table" and isInteger(prepared.SeasonId) then prepared.SeasonId else 1
	local randomAllowed = if type(prepared) == "table" then prepared.RandomAllowed else nil
	local grant, info = Core.BuildGrant(product, data, seasonId, randomAllowed)
	if next(grant) ~= nil and not shopService.Grant(p, grant, "Robux:" .. tostring(product.Key)) then
		return false
	end
	local purchases = purchasesOf(data)
	if info.FirstBonus then
		purchases.FirstPack[product.Key] = true
	end
	if info.MarkStarter then
		purchases.Starter = true
	end
	if info.MarkSeason then
		purchases.PassSeasons[tostring(seasonId)] = true
	end
	if product.Supporter then
		purchases.Supporter += 1
		try("ShopService", "RefreshPlayer", p)
	end
	if product.PartyBoost then
		partyUntil = Core.ExtendParty(partyUntil, os.time())
		announceParty(p)
	end
	-- Rückmeldung (kein Yield)
	local lang = langOf(p)
	local name = Lang.Pick(lang, product.Name)
	if info.Fallback and product.PerSeason then
		notify(p, "shop.passOwnedGems", { tonumber(grant.Gems) or 0 }, "Info")
	elseif info.Fallback and product.Once then
		notify(p, "shop.starterRepeat", { tonumber(grant.Gems) or 0 }, "Info")
	else
		notify(p, "shop.thanks", { name }, "Success")
		if info.FirstBonus then
			notify(p, "shop.firstBonus", nil, "Success")
		end
	end
	try("PlayerStateService", "Effect", p, "Confetti", 1, nil)
	markDirty(p, "Offer", "Boosts")
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
	warn("[Monetization] ProcessReceipt Fehler: " .. tostring(decision))
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- =====================================================================
-- 6) ADMIN-SIMULATION (gleiche Gutschrift wie ein echter Kauf, auch mit Id = 0)
-- =====================================================================
function MonetizationService.SimulatePurchase(p: Player, productKey: string): (boolean, string)
	if typeof(p) ~= "Instance" or not p:IsA("Player") or p.Parent ~= Players then
		return false, "Spieler nicht im Spiel"
	end
	if type(productKey) ~= "string" then
		return false, "Produkt-Key fehlt"
	end
	local pass = passByKey(productKey)
	if pass then
		local session = sessionPasses[p]
		if session == nil then
			session = {}
			sessionPasses[p] = session
		end
		session[pass.Key] = true
		refreshShop(p)
		notify(p, "shop.simulated", { Lang.Pick(langOf(p), pass.Name) }, "Info")
		return true, "Pass " .. pass.Key .. " für diese Sitzung aktiv"
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
		PurchaseId = "SIM-" .. HttpService:GenerateGUID(false),
		CurrencySpent = 0,
	}
	local ok, decision = pcall(Core.ProcessReceiptWith, receipt, env)
	if ok and decision == Enum.ProductPurchaseDecision.PurchaseGranted then
		return true, "Kauf simuliert: " .. productKey
	end
	return false, "Simulation nicht gutgeschrieben (" .. tostring(decision) .. ")"
end

-- =====================================================================
-- 7) BOOSTS & ANGEBOTE
-- =====================================================================
function MonetizationService.PartyXpActive(): boolean
	return os.time() < partyUntil
end

function MonetizationService.PartyUntil(): number
	return partyUntil
end

local function inBlockedPhase(p: Player): boolean
	local okMatch, matchId = try("MatchService", "MatchOf", p)
	if not okMatch or matchId == nil then
		return false
	end
	local okInfo, info = try("MatchService", "Info", matchId)
	if not okInfo or type(info) ~= "table" then
		return true -- im Zweifel kein Angebot
	end
	return BLOCKED_PHASES[tostring(info.Phase)] == true
end

function MonetizationService.TryOffer(p: Player, offerKey: string): boolean
	if typeof(p) ~= "Instance" or p.Parent ~= Players or type(offerKey) ~= "string" then
		return false
	end
	local product = SHOP.ProductsByKey[offerKey]
	if product == nil then
		return false
	end
	if (offersShown[p] or 0) >= MAX_OFFERS then
		return false -- max. 1 Angebots-Popup pro Sitzung (B23.1)
	end
	if inBlockedPhase(p) then
		return false
	end
	local data = dataOf(p)
	if data == nil then
		return false
	end
	local purchases = purchasesOf(data)
	if product.Once then
		-- Starter-Paket: genau EINMAL angeboten (erster echter Sieg), danach 72 h im Shop (B23.2)
		if purchases.Starter == true or purchases.StarterOfferedAt > 0 then
			return false
		end
		purchases.StarterOfferedAt = os.time()
	elseif product.PerSeason and purchases.PassSeasons[tostring(currentSeasonId())] == true then
		return false
	end
	offersShown[p] = (offersShown[p] or 0) + 1
	markDirty(p, "Offer")
	return true
end

-- =====================================================================
-- 8) STATE-SCHLÜSSEL
-- =====================================================================
local function registerState()
	local stateService = service("PlayerStateService")
	if stateService == nil or type(stateService.Provide) ~= "function" then
		return
	end
	stateService.Provide("Passes", function(p: Player)
		local result: { [string]: boolean } = {}
		for _, pass in ipairs(SHOP.GamePasses) do
			result[pass.Key] = MonetizationService.HasPass(p, pass.Key)
		end
		return result
	end)
	stateService.Provide("RandomAllowed", function(p: Player)
		return MonetizationService.RandomAllowed(p) -- nil bis bekannt (Client: versteckt)
	end)
	stateService.Provide("Boosts", function(p: Player)
		local data = dataOf(p)
		local boosts = data and data.Boosts
		return {
			XP2Until = if type(boosts) == "table" and Util.IsFinite(boosts.XP2Until) then boosts.XP2Until else 0,
			PartyUntil = partyUntil,
			PartyCap = PARTY_CAP,
		}
	end)
	stateService.Provide("Offer", function(p: Player)
		local data = dataOf(p)
		if data == nil then
			return { StarterUntil = 0, Starter = false, FirstPack = {}, PassSeasons = {} }
		end
		local purchases = purchasesOf(data)
		local offeredAt = purchases.StarterOfferedAt
		return {
			Starter = purchases.Starter == true,
			StarterUntil = if offeredAt > 0 then offeredAt + STARTER_HOURS * 3600 else 0,
			FirstPack = purchases.FirstPack,
			PassSeasons = purchases.PassSeasons,
			Season = currentSeasonId(),
		}
	end)
end

-- =====================================================================
-- 9) INIT / START
-- =====================================================================
function MonetizationService.Init(services: any)
	Services = services
end

function MonetizationService.Start()
	-- B22.3 #1: früh setzen (ohne Callback quittiert Roblox Käufe automatisch -> verloren)
	MarketplaceService.ProcessReceipt = processReceipt
	registerState()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPassPurchased)
	Players.PlayerRemoving:Connect(function(p: Player)
		owned[p] = nil
		loading[p] = nil
		sessionPasses[p] = nil
		policy[p] = nil
		policyStarted[p] = nil
		policyOverride[p] = nil
		offersShown[p] = nil
	end)
	-- Policy schon beim Beitritt anfragen (PlayerStateService ruft RandomAllowed zusätzlich im Ready-Ablauf)
	Players.PlayerAdded:Connect(function(p: Player)
		MonetizationService.RandomAllowed(p)
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		MonetizationService.RandomAllowed(p)
	end
end

return MonetizationService
