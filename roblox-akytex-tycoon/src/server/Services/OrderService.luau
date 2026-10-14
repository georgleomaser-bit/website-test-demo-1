-- =====================================================================
--  AKYTEX TYCOON – Orders, Depot, Strategie-Bots, Gewinn-Transfer-Regeln, Liga-Statistik (Server/Services/OrderService)
--  Besitzer: WP4 (Orders, Depot, Bots – EINZIGER Depot-Schreiber). Vertrag: DESIGN.md §C5.4, §C9 (Trade*, Alert*,
--  Bot*, DepotHistory, TutorialTrade), §C10 (State Depot, League), §B7.3, §B8, §B11.1, §C11.4; MARKET.md §11–§13.
--
--  Firewall (§C11.4): dieses Modul kennt kein Turm-Geld. Gewinn-Transfers verlassen das Depot als AKY-Cent
--  (Withdraw); umrechnen und gutschreiben macht der Turm (WP6). Zur Laufzeit nur erlaubte Dienste:
--  DataService, PlayerStateService, MarketService, ProgressionService (TradingPerks/LicenceDef/Licence),
--  AdminService (OwnerTradeBlocked), MetricsService, AntiCheatService – alle per pcall, alle optional.
--
--  Ablauf:
--    * Beitritt: Depot reparieren (Portfolio.Sanitize) -> Lizenz-Basis abgleichen -> Offline-Abgleich im Hintergrund
--      (CatchUp, Orders 24 h, Bots 12 h, Dividenden, Auto-Transfers) -> "live". Während des Abgleichs sind
--      Handels-Anfragen gesperrt (trade.syncing), danach laufen alle Ticks über OrderEngine.Step (wie offline).
--    * Live: MarketService.OnTick(t) -> je bereitem Spieler Step(t) direkt nach PriceEngine.Step (Dividenden des
--      Ex-Ticks vor jeder Anfrage zum neuen Quote; Sofort-Orders laufen zum Quote des verarbeiteten Ticks).
--    * Glocke (t % 1200 == 0, in Step): Tagesrendite, Liga, Bot-Lohn, Auto-Transfer in Depot.Pending, dann OnBell(p)
--      -> der Turm holt Pending über Withdraw(p, "Bell") ab.
--
--  Öffentliche API (§C5.4):
--    OrderService.Depot(p): Types.Depot?                 nur lesen
--    OrderService.Nav(p): number                         Cent
--    OrderService.Withdrawable(p): (number, boolean, string?)   Cent, jetzt erlaubt, Grund-Schlüssel wenn nicht
--    OrderService.Withdraw(p, reason): (number, string?) "Manual" | "Bell" | "Offline" – bucht ab, gibt Cent zurück
--    OrderService.SetLicence(p, idx)                     Cash/Basis um die Basis-Differenz anpassen (Fluss)
--    OrderService.AdminCredit(p, cents): boolean         Cash + Basis (nie abhebbar); negativ = Admin-Abzug; taintet
--    OrderService.TaintWeek(p, reason)
--    OrderService.HoldsShares(p, i): number
--    OrderService.LeagueStats(p): Types.LeagueStats
--    OrderService.CatchUpReport(p): { Fills, Dividends, Bots = { { Preset, Pct } }, Alerts }?
--    OrderService.OnTrade(cb(p, FillInfo)) · OnDayResult(cb(p, DayResult)) · OnBell(cb(p))
--    OrderService.TutorialState(p): "None" | "Running" | "Done"
--  Request-Handler: TradePlace, TradeCancel, TradeModify, TradeBasket, TradeRefill, TradeAuto, TradeWatch,
--    AlertSet, AlertRemove, BotSet, BotToggle, DepotHistory, TutorialTrade
--  State: Depot, League. Effekt: ReadWell. Remotes: Replay (ACAD-Übung), Market "DayClose" (FireClient).
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Types = require(Shared:WaitForChild("Types"))
local Clock = require(Shared:WaitForChild("Clock"))
local MarketShared = Shared:WaitForChild("Market")
local PortfolioMath = require(MarketShared:WaitForChild("PortfolioMath"))
local MarketFolder = script.Parent.Parent:WaitForChild("Market")
local Portfolio = require(MarketFolder:WaitForChild("Portfolio"))
local OrderEngine = require(MarketFolder:WaitForChild("OrderEngine"))
local BotEngine = require(MarketFolder:WaitForChild("BotEngine"))
local CatchUp = require(MarketFolder:WaitForChild("CatchUp"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

-- Replay-Kodierung (WP3, Shared/Market/QuoteCodec) – optional; ohne Modul kodieren wir die 9 Byte selbst
local QuoteCodec: any = nil
do
	local module = MarketShared:FindFirstChild("QuoteCodec")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			QuoteCodec = result
		end
	end
end

local OrderService = {}
local Services: any = nil

type Reply = Types.Reply
type Depot = { [string]: any }
type Env = OrderEngine.Env
type Lic = OrderEngine.Lic

local DAY = Clock.DAY_TICKS
local LIVE_LAG = 0 -- Tick t wird direkt in OnTick(t) verarbeitet (nach PriceEngine.Step, vor jeder Anfrage zum Quote t)
local LIVE_GAP_MAX = 120 -- größere Lücke (Hänger) -> Abgleich im Hintergrund statt synchron
local CACHE_SAFETY = 120 -- Minuten-Caches nur für Ticks, die mindestens so alt sind (späte Bus-Events)
local PERKS_SECONDS = 5
local IDS_SECONDS = 10
local MAX_PENDING_EVENTS = 100
local MAX_PENDING_DAYS = 72
local MAX_NUMBER_ARG = 1e12
local MAX_PRICE_ARG = 1e9
local INVALID_LOG_EVERY = 10
local MARKET_WAIT = 90 -- s: so lange wartet der Offline-Abgleich beim Beitritt auf den bootenden Markt
local MAX_MONEY = 9e15

-- Pro-Spieler-Zustand (alles wird bei PlayerRemoving geleert)
local live: { [Player]: boolean } = {}
local syncing: { [Player]: boolean } = {}
local replies: { [Player]: { [number]: Reply } } = {}
local reports: { [Player]: { [string]: any } } = {}
local tutorials: { [Player]: { [string]: any } } = {}
local lossTimes: { [Player]: { number } } = {}
local spam: { [Player]: { Window: number, Count: number, Flagged: boolean } } = {}
local perksCache: { [Player]: { At: number, Lic: Lic, Perks: { [string]: any } } } = {}
local pendingLicence: { [Player]: number } = {}
local dirty: { [Player]: { [string]: boolean } } = {}
local ownerOf: { [any]: Player } = {} -- Depot-Tabelle -> Spieler (Metriken)

local tradeCallbacks: { (Player, Types.FillInfo) -> () } = {}
local dayCallbacks: { (Player, Types.DayResult) -> () } = {}
local bellCallbacks: { (Player) -> () } = {}
local errorAt: { [string]: number } = {}

-- ---------------------------------------------------------------------
-- 1) HELFER
-- ---------------------------------------------------------------------
local function logError(source: string, err: any)
	local now = os.clock()
	if now - (errorAt[source] or -math.huge) >= INVALID_LOG_EVERY then
		errorAt[source] = now
		warn(("[OrderService] %s: %s"):format(source, tostring(err)))
	end
end

local function trading(): { [string]: any }
	local t = Config.Trading
	return if type(t) == "table" then t else {}
end

local function num(v: any, fallback: number): number
	if Util.IsFinite(v) then
		return v
	end
	return fallback
end

local function isInt(v: any): boolean
	return Util.IsFinite(v) and v % 1 == 0
end

-- Optionaler Dienst-Aufruf: (ok, ...) – nie ein Fehler nach außen
local function call(serviceName: string, fnName: string, ...: any): (boolean, ...any)
	local s = Services and Services[serviceName]
	local fn = s and s[fnName]
	if type(fn) ~= "function" then
		return false
	end
	return pcall(fn, ...)
end

local function dataOf(p: Player): { [string]: any }?
	local ok, data = call("DataService", "Get", p)
	if ok and type(data) == "table" then
		return data
	end
	return nil
end

local function depotOf(p: Player): Depot?
	local data = dataOf(p)
	local d = data and data.Depot
	return if type(d) == "table" then d else nil
end

local function present(p: any): boolean
	return typeof(p) == "Instance" and p:IsA("Player") and p.Parent == Players
end

local function marketTick(): number?
	local ok, t = call("MarketService", "Tick")
	if ok and isInt(t) and t > 0 then
		return t
	end
	return nil
end

-- Markt fertig gebootet? (Tick() ist schon kurz VOR "ready" gesetzt; PriceAt/Dividends liefern bis dahin nur
-- Startkurse bzw. nichts – der Offline-Abgleich darf erst danach rechnen). Fehlt die Funktion: als bereit werten.
local function marketReady(): boolean
	local ok, ready = call("MarketService", "IsReady")
	return not ok or ready == true
end

-- "Jetzt" der Engine: der zuletzt verarbeitete Markt-Tick; ohne Markt die Weltzeit
local function engineNow(): number
	local t = marketTick()
	if t then
		return t - LIVE_LAG
	end
	return Clock.Tick()
end

local function markDirty(p: Player, ...: string)
	local set = dirty[p]
	if not set then
		set = {}
		dirty[p] = set
	end
	for i = 1, select("#", ...) do
		set[select(i, ...)] = true
	end
end

local function flushDirty(p: Player)
	local set = dirty[p]
	if not set then
		return
	end
	dirty[p] = nil
	local keys: { string } = {}
	for key in pairs(set) do
		table.insert(keys, key)
	end
	if #keys > 0 then
		call("PlayerStateService", "MarkDirty", p, table.unpack(keys))
	end
end

local function notify(p: Player, key: string, args: { any }?, kind: Types.NotifyKind?)
	if present(p) then
		call("PlayerStateService", "Notify", p, key, args, kind)
	end
end

local function fire(list: { any }, ...: any)
	for _, cb in ipairs(list) do
		task.spawn(function(...)
			local ok, err = pcall(cb, ...)
			if not ok then
				logError("Callback", err)
			end
		end, ...)
	end
end

-- wie fire, aber erst nach dem laufenden Markt-Tick (MarketService öffnet den Tagesschluss nach den Tick-Callbacks)
local function fireDeferred(list: { any }, ...: any)
	for _, cb in ipairs(list) do
		task.defer(function(...)
			local ok, err = pcall(cb, ...)
			if not ok then
				logError("Callback", err)
			end
		end, ...)
	end
end

local function tickerOf(i: number): string
	local companies = Config.Companies
	local inst = type(companies) == "table" and type(companies.ById) == "table" and companies.ById[i] or nil
	return if type(inst) == "table" and type(inst.Ticker) == "string" then inst.Ticker else ("#" .. tostring(i))
end

-- Preis als zwei Ganzzahlen (Lang-Text setzt das Dezimalzeichen je Sprache: "%d,%02d" / "%d.%02d")
local function priceArgs(cents: number): (number, number)
	local c = math.max(0, math.floor(cents))
	return c // 100, c % 100
end

-- ---------------------------------------------------------------------
-- 2) INSTRUMENTE (Config.Companies + MarketService)
-- ---------------------------------------------------------------------
local activeSet: { [number]: boolean } = {}
local activeList: { number } = {}
local activeAt = -math.huge

local function instDef(i: number): { [string]: any }?
	local companies = Config.Companies
	local inst = type(companies) == "table" and type(companies.ById) == "table" and companies.ById[i] or nil
	return if type(inst) == "table" then inst else nil
end

local function refreshActive()
	local now = os.clock()
	if now - activeAt < IDS_SECONDS then
		return
	end
	activeAt = now
	local ok, list = call("MarketService", "ActiveIds")
	table.clear(activeSet)
	table.clear(activeList)
	if ok and type(list) == "table" then
		for _, i in ipairs(list) do
			if isInt(i) then
				activeSet[i] = true
				table.insert(activeList, i)
			end
		end
	end
	if #activeList == 0 then
		-- ohne Markt-Liste: alle festen Werte (Firmen + ETFs), keine IPO-Plätze
		local companies = Config.Companies
		if type(companies) == "table" and type(companies.Instruments) == "table" then
			for _, inst in ipairs(companies.Instruments) do
				if type(inst) == "table" and isInt(inst.Id) and inst.Ipo ~= true and inst.Set ~= "Tutorial" then
					activeSet[inst.Id] = true
					table.insert(activeList, inst.Id)
				end
			end
		end
	end
	table.sort(activeList)
end

local function isListed(i: number): boolean
	local def = instDef(i)
	if not def or def.Set == "Tutorial" then
		return false
	end
	refreshActive()
	return activeSet[i] == true
end

-- gültig für gespeicherte Daten (auch gerade nicht gelistete IPOs bleiben erhalten)
local function isKnownInst(i: number): boolean
	local def = instDef(i)
	return def ~= nil and def.Set ~= "Tutorial"
end

local function classOf(i: number): string?
	local ok, inst = call("MarketService", "Instrument", i)
	if ok and type(inst) == "table" and type(inst.Class) == "string" then
		return inst.Class
	end
	local def = instDef(i)
	return def and def.Class
end

local function setOf(i: number): string?
	local def = instDef(i)
	return def and def.Set
end

local function divBpsOf(i: number): number
	local def = instDef(i)
	return if def and isInt(def.DivBps) then def.DivBps else 0
end

-- ---------------------------------------------------------------------
-- 3) LIZENZ & KNOW-HOW (nur Prog.* – Robux-frei)
-- ---------------------------------------------------------------------
local SET_RANK = { Azubi = 1, Trader = 2, Fonds = 3 }

local function licenceTable(): ({ any }, number)
	local prog = Config.Progression
	local list = type(prog) == "table" and prog.Licences or nil
	if type(list) == "table" and #list >= 1 and type(list[1]) == "table" then
		-- Basis in AKY (25.000) oder in Cent (2.500.000)? Am ersten Eintrag erkennen.
		local first = num(list[1].Basis, 0)
		return list, if first > 0 and first < 1e6 then 100 else 1
	end
	return trading().LicenceFallback or {}, 1
end

local function normalizeLicence(def: any, idx: number, factor: number): Lic
	local fallback = (trading().LicenceFallback or {})[idx] or {}
	local function pick(key: string, default: any): any
		local v = if type(def) == "table" then def[key] else nil
		if v == nil then
			v = fallback[key]
		end
		if v == nil then
			v = default
		end
		return v
	end
	local fee = num(pick("FeeBps", 10), 10)
	if fee > 0 and fee < 1 then
		fee *= 10000 -- als Bruch angegeben
	end
	local weight = num(pick("MaxWeight", 0.3), 0.3)
	if weight > 1 then
		weight /= 100 -- als Prozent angegeben
	end
	local basisRaw = if type(def) == "table" and Util.IsFinite(def.Basis)
		then def.Basis * factor
		else num(fallback.Basis, 2500000)
	local set = pick("Set", if idx >= 7 then "Fonds" elseif idx >= 4 then "Trader" else "Azubi")
	return {
		Index = idx,
		Basis = math.floor(math.max(1, basisRaw)),
		BauKurs = num(pick("BauKurs", 40), 40),
		FeeBps = math.clamp(fee, 0, 100),
		MaxWeight = math.clamp(weight, 0.05, 1),
		MaxOrders = math.clamp(math.floor(num(pick("MaxOrders", 5), 5)), 1, 50),
		PosFactor = math.max(0, num(pick("PosFactor", 0.01), 0.01)),
		Set = if SET_RANK[set] then set else "Azubi",
		SetRank = SET_RANK[set] or 1,
		BotSlots = math.clamp(math.floor(num(pick("BotSlots", 0), 0)), 0, 5),
		Layer = tostring(pick("Layer", "Simple")),
	}
end

local function licenceIndex(p: Player): number
	local data = dataOf(p)
	local prog = data and data.Prog
	if type(prog) == "table" and isInt(prog.Licence) and prog.Licence >= 1 and prog.Licence <= 10 then
		return prog.Licence
	end
	local ok, idx = call("ProgressionService", "Licence", p)
	if ok and isInt(idx) and idx >= 1 and idx <= 10 then
		return idx
	end
	return 1
end

local function basisFor(idx: number): number
	local list, factor = licenceTable()
	return normalizeLicence(list[idx], idx, factor).Basis
end

local function licenceOf(p: Player?): Lic
	local idx = if p then licenceIndex(p) else 1
	local list, factor = licenceTable()
	local def = list[idx]
	if p then
		local ok, liveDef = call("ProgressionService", "LicenceDef", p)
		if ok and type(liveDef) == "table" then
			def = liveDef
		end
	end
	return normalizeLicence(def, idx, factor)
end

local function perksFor(p: Player?, lic: Lic): { [string]: any }
	local perks: { [string]: any } = {
		Licence = lic.Index,
		Layer = lic.Layer,
		BotSlots = lic.BotSlots,
		BotLevels = {},
		Alerts = 3,
		Watchlists = 1,
	}
	if p then
		local ok, result = call("ProgressionService", "TradingPerks", p)
		if ok and type(result) == "table" then
			perks.BotSlots = math.clamp(math.floor(num(result.BotSlots, lic.BotSlots)), 0, 5)
			perks.BotLevels = if type(result.BotLevels) == "table" then result.BotLevels else {}
			perks.Alerts = math.clamp(math.floor(num(result.Alerts, 3)), 0, num(trading().MaxAlertsHard, 18))
			perks.Watchlists = math.clamp(math.floor(num(result.Watchlists, 1)), 1, 5)
			perks.Risk = num(result.Risk, 0)
		end
	end
	return perks
end

local function licAndPerks(p: Player): (Lic, { [string]: any })
	local now = os.clock()
	local cached = perksCache[p]
	if cached and now - cached.At < PERKS_SECONDS then
		return cached.Lic, cached.Perks
	end
	local lic = licenceOf(p)
	local perks = perksFor(p, lic)
	perksCache[p] = { At = now, Lic = lic, Perks = perks }
	return lic, perks
end

-- ---------------------------------------------------------------------
-- 4) MARKT-ZUGRIFF (pcall) + Tick-Caches
-- ---------------------------------------------------------------------
local tickPx: { [number]: number } = {}
local tickPxAt = -1

local function priceAt(i: number, t: number): number?
	local now = marketTick()
	if now and t == now - LIVE_LAG then
		if tickPxAt ~= t then
			table.clear(tickPx)
			tickPxAt = t
		end
		local cached = tickPx[i]
		if cached then
			return cached
		end
	end
	local ok, px = call("MarketService", "PriceAt", i, t)
	if ok and Util.IsFinite(px) and px > 0 then
		local value = math.floor(px)
		if tickPxAt == t then
			tickPx[i] = value
		end
		return value
	end
	return nil
end

local function liveQuote(i: number): (number?, number?, number?)
	local ok, bid, ask, mid = call("MarketService", "Quote", i)
	if ok and Util.IsFinite(bid) and Util.IsFinite(ask) and Util.IsFinite(mid) and bid > 0 and ask >= bid then
		return math.floor(bid), math.floor(ask), math.floor(mid)
	end
	return nil, nil, nil
end

local candleTick = -1
local candleCache: { [number]: { number } | false } = {}

local function liveCandle(i: number, t: number): (number?, number?, number?, number?)
	if candleTick ~= t then
		candleTick = t
		table.clear(candleCache)
	end
	local cached = candleCache[i]
	if cached == nil then
		local ok, o, h, l, c = call("MarketService", "Candle1s", i, t)
		if ok and Util.IsFinite(o) and Util.IsFinite(h) and Util.IsFinite(l) and Util.IsFinite(c) then
			cached = { o, h, l, c }
		else
			cached = false
		end
		candleCache[i] = cached
	end
	if cached then
		return cached[1], cached[2], cached[3], cached[4]
	end
	return nil, nil, nil, nil
end

local divTick = -1
local divList: { any }? = nil

local function dividendsRange(t0: number, t1: number): { { [string]: number } }
	local ok, list = call("MarketService", "Dividends", t0, t1)
	if ok and type(list) == "table" then
		return list
	end
	return {}
end

local function liveDivs(t: number): { any }?
	if divTick ~= t then
		divTick = t
		local list = dividendsRange(t, t)
		divList = if #list > 0 then list else nil
	end
	return divList
end

-- Handelspause; mit Tick t die Pause GENAU zu diesem Tick (Offline-Abgleich rechnet dieselben Pausen wie online)
local function halted(i: number, t: number?): boolean
	local ok, result = call("MarketService", "IsHalted", i, t)
	return ok and result == true
end

local function factDir(i: number, t: number): number?
	local window = math.floor(num(trading().ReadWellSeconds, 60))
	local ok, item = call("MarketService", "FactNewsFor", i, t, window)
	if ok and type(item) == "table" and Util.IsFinite(item.Dir) then
		return item.Dir
	end
	return nil
end

local function adminActive(t: number): boolean
	local ok, result = call("MarketService", "AdminWindowActive", t)
	return ok and result == true
end

local function adminBetween(t0: number, t1: number): boolean
	local ok, list = call("MarketService", "AdminWindowsBetween", t0, t1)
	return ok and type(list) == "table" and #list > 0
end

local function weekOf(t: number): number
	return Util.IsoWeek(Clock.UnixOf(t))
end

local function activeIds(): { number }
	refreshActive()
	return table.clone(activeList)
end

-- ---------------------------------------------------------------------
-- 5) ENV (Markt-Sicht für die Engine) + Ereignisse
-- ---------------------------------------------------------------------
local handleEvent: (Player, Depot, string, string, any, { [string]: any }?) -> ()

local function makeEnv(p: Player, d: Depot, mode: string, buffer: { [string]: any }?): Env
	local lic, perks = licAndPerks(p)
	local data = dataOf(p)
	local watch = if type(d.Watch) == "table" and type(d.Watch[1]) == "table" then d.Watch[1] else {}
	local env: Env = {
		Mode = mode,
		Licence = lic,
		Perks = perks,
		PriceAt = priceAt,
		Quote = if mode == "Live" then liveQuote else nil,
		Class = classOf,
		Set = setOf,
		DivBps = divBpsOf,
		Listed = isListed,
		Halted = halted,
		FactDir = factDir,
		AdminActive = adminActive,
		AdminBetween = adminBetween,
		Dividends = dividendsRange,
		Emit = function(kind: string, payload: any)
			handleEvent(p, d, mode, kind, payload, buffer)
		end,
		League = if data and type(data.League) == "table" then data.League else nil,
		Week = weekOf,
		OwnerTaint = p:GetAttribute("IsAdmin") == true,
		CacheBefore = (marketTick() or 0) - CACHE_SAFETY,
		Watch = watch,
		ActiveIds = activeIds,
	}
	return env
end

local function noteLoss(p: Player)
	local cfg = trading().LossStreakWarn or {}
	local limit = math.floor(num(cfg.Trades, 10))
	local window = num(cfg.Seconds, 120)
	local list = lossTimes[p]
	if not list then
		list = {}
		lossTimes[p] = list
	end
	local now = os.clock()
	table.insert(list, now)
	while list[1] ~= nil and now - list[1] > window do
		table.remove(list, 1)
	end
	if #list >= limit then
		table.clear(list)
		notify(p, "trade.lossStreak", nil, "Info")
	end
end

local FILL_KEYS = {
	Limit = { B = "trade.fillLimitBuy", S = "trade.fillLimitSell" },
	Stop = { S = "trade.fillStop" },
	Target = { S = "trade.fillTarget" },
	Trail = { S = "trade.fillTrail" },
	OcoStop = { S = "trade.fillStop" },
	OcoTarget = { S = "trade.fillTarget" },
	BuyStop = { B = "trade.fillBuyStop" },
}

handleEvent = function(p: Player, _d: Depot, mode: string, kind: string, data: any, buffer: { [string]: any }?)
	markDirty(p, "Depot")
	if mode ~= "Live" then
		-- Offline-Abgleich: Signale sammeln und nach dem Abgleich der Reihe nach auslösen
		if buffer then
			if kind == "Fill" and #buffer.Fills < MAX_PENDING_EVENTS then
				table.insert(buffer.Fills, data.Fill)
			elseif kind == "DayResult" and #buffer.Days < MAX_PENDING_DAYS then
				table.insert(buffer.Days, data)
			elseif kind == "Bell" then
				buffer.Bell = true
			end
		end
		if kind == "DayResult" or kind == "Fill" then
			markDirty(p, "League")
		end
		return
	end
	if kind == "Fill" then
		local fill = data.Fill
		fire(tradeCallbacks, p, fill)
		markDirty(p, "League")
		if fill.Bot then
			return -- Bots handeln still (Depot-Ansicht zeigt es)
		end
		local keys = FILL_KEYS[data.Kind]
		local key = keys and keys[fill.Side]
		if key then
			local whole, cents = priceArgs(fill.Px)
			if data.Kind == "Stop" or data.Kind == "OcoStop" then
				key = if data.Gap then "trade.fillStopGap" else "trade.fillStop"
				notify(p, key, { tickerOf(fill.I), whole, cents }, "Alarm")
			elseif data.Kind == "Limit" then
				notify(p, key, { fill.Q, tickerOf(fill.I), whole, cents }, "Success")
			else
				notify(p, key, { tickerOf(fill.I), whole, cents }, "Success")
			end
		end
		if fill.Side == "S" and Util.IsFinite(fill.Pnl) and fill.Pnl < 0 then
			noteLoss(p)
		end
		if fill.ReadWell then
			call("PlayerStateService", "Effect", p, "ReadWell", 1, { I = fill.I, Ticker = tickerOf(fill.I) })
		end
	elseif kind == "Expired" then
		if data.Bot == nil then
			notify(p, "trade.expired", { tickerOf(data.I) }, "Info")
		end
	elseif kind == "Cancelled" then
		if data.Bot == nil then -- Bot-Orders laufen still (Depot-Ansicht zeigt es)
			local key = if data.Reason == "trade.noCash" then "trade.cancelNoCash" else "trade.cancelLimit"
			notify(p, key, { tickerOf(data.I) }, "Info")
		end
	elseif kind == "Cut" then
		if data.Bot == nil then
			notify(p, "trade.cut", { data.Q, tickerOf(data.I) }, "Info")
		end
	elseif kind == "Alert" then
		local whole, cents = priceArgs(data.Px)
		notify(p, "trade.alertHit", { tickerOf(data.I), whole, cents }, "Alarm")
	elseif kind == "Dividend" then
		local whole, cents = priceArgs(data.Cents)
		notify(p, "trade.dividend", { tickerOf(data.I), whole, cents }, "Success")
	elseif kind == "DayResult" then
		-- MarketService schickt die "DayClose"-Nachricht mit dieser Rendite (eine Meldung, ein Weg)
		fireDeferred(dayCallbacks, p, data)
		markDirty(p, "League")
	elseif kind == "Bell" then
		fire(bellCallbacks, p)
	elseif kind == "BotPaused" then
		notify(p, "trade.botPaused", { data.Slot }, "Alarm")
	end
end

-- Metriken der AKY-Flüsse (nur seltene Gründe – kein Eintrag je Trade/Gebühr)
local METRIC_REASONS = {
	Licence = "Source",
	Refill = "Source",
	Admin = "Source",
	Tutorial = "Source",
	Transfer = "Sink",
	BotWage = "Sink",
}

local function onFlow(d: Depot, signed: number, reason: string)
	local p = ownerOf[d]
	local flow = METRIC_REASONS[reason]
	if not p or not flow or signed == 0 then
		return
	end
	if reason == "Tutorial" or reason == "Admin" then
		flow = if signed > 0 then "Source" else "Sink" -- Übung (Kauf/Verkauf) · Admin-Gabe/-Abzug
	end
	call("MetricsService", "Economy", p, flow, "AKY", math.abs(signed), math.floor(num(d.Cash, 0)), reason)
end

-- ---------------------------------------------------------------------
-- 6) LIVE-VERARBEITUNG & OFFLINE-ABGLEICH
-- ---------------------------------------------------------------------
local startCatchUp: (Player) -> ()

local function ensureDayRecord(d: Depot, env: Env, t: number)
	local day = t // DAY
	local rec = Portfolio.CurrentDay(d)
	if rec == nil or rec[1] ~= day then
		Portfolio.OpenDay(d, day, OrderEngine.NavAt(d, env, t), next(d.Pos) ~= nil)
	end
end

local function processLive(p: Player, d: Depot, target: number)
	local last = math.floor(num(d.LastTick, 0))
	if last >= target then
		return
	end
	if target - last > LIVE_GAP_MAX then
		live[p] = false
		startCatchUp(p)
		return
	end
	local env = makeEnv(p, d, "Live")
	for tt = last + 1, target do
		local ctx = {
			Candle = function(i: number): (number?, number?, number?, number?)
				return liveCandle(i, tt)
			end,
			Divs = liveDivs(tt),
		}
		local ok, err = pcall(OrderEngine.Step, d, env, tt, ctx)
		if not ok then
			d.LastTick = tt -- nie an einem kaputten Tick hängen bleiben
			logError("Step " .. p.Name, err)
		end
	end
end

local function onMarketTick(t: number)
	if not isInt(t) then
		return
	end
	local target = t - LIVE_LAG
	for _, p in ipairs(Players:GetPlayers()) do
		if live[p] then
			local d = depotOf(p)
			if d then
				processLive(p, d, target)
			end
			flushDirty(p)
		end
	end
end

local function newCursor(i: number, t0: number): any
	local ok, cursor = call("MarketService", "NewCursor", i, t0)
	if ok and type(cursor) == "table" then
		return cursor
	end
	return nil
end

local function randomCandle(i: number, t: number): (number?, number?, number?, number?)
	local ok, o, h, l, c = call("MarketService", "Candle1s", i, t)
	if ok and Util.IsFinite(o) then
		return o, h, l, c
	end
	return nil, nil, nil, nil
end

local function applyLicence(p: Player, d: Depot, idx: number)
	local current = if isInt(d.Lic) then d.Lic else 1
	if current == idx then
		return
	end
	local delta = basisFor(idx) - basisFor(current)
	if delta > 0 then
		Portfolio.Credit(d, delta, "Licence")
	elseif delta < 0 then
		Portfolio.Debit(d, -delta, "Licence")
		-- Herabstufung (nur Admin): Kauf-Orders ohne Deckung streichen (jüngste zuerst)
		local guard = 0
		while Portfolio.Reserved(d) > d.Cash and guard < 50 do
			guard += 1
			for i = #d.Orders, 1, -1 do
				if d.Orders[i].Side == "B" then
					table.remove(d.Orders, i)
					break
				end
			end
		end
	end
	d.Lic = idx
	perksCache[p] = nil
	markDirty(p, "Depot")
end

-- Übung: liegengebliebene ACAD-Stück verkaufen (Abschnitt 9; vorab deklariert, goLive braucht sie)
local finishTutorial: (Player, Depot, boolean) -> number?

local function goLive(p: Player, d: Depot, buffer: { [string]: any }?, report: { [string]: any }?)
	local env = makeEnv(p, d, "Live")
	ensureDayRecord(d, env, math.floor(num(d.LastTick, engineNow())))
	live[p] = true
	syncing[p] = nil
	local queued = pendingLicence[p]
	if queued then
		pendingLicence[p] = nil
		applyLicence(p, d, queued)
	end
	-- mitten in der Übung gegangen: liegengebliebene ACAD-Stück zum Automatik-Kurs verkaufen
	if num(d.Tutorial.Q, 0) > 0 and not tutorials[p] then
		finishTutorial(p, d, true)
	end
	if report and (report.Fills > 0 or report.Dividends > 0 or report.Alerts > 0 or #report.Bots > 0) then
		reports[p] = {
			Fills = report.Fills,
			Dividends = report.Dividends,
			Bots = report.Bots,
			Alerts = report.Alerts,
		}
	end
	if buffer then
		for _, fill in ipairs(buffer.Fills) do
			fire(tradeCallbacks, p, fill)
		end
		for _, day in ipairs(buffer.Days) do
			fire(dayCallbacks, p, day)
		end
	end
	if math.floor(num(d.Pending, 0)) > 0 then
		fire(bellCallbacks, p) -- Turm holt offline verbuchte Auto-Transfers ab (Withdraw "Bell"/"Offline")
	end
	markDirty(p, "Depot", "League")
	flushDirty(p)
end

startCatchUp = function(p: Player)
	if syncing[p] then
		return
	end
	syncing[p] = true
	live[p] = false
	markDirty(p, "Depot")
	flushDirty(p)
	task.spawn(function()
		local d = depotOf(p)
		if not d or not present(p) then
			syncing[p] = nil
			return
		end
		local now = if marketReady() then marketTick() else nil
		-- Markt bootet noch (Seed aus dem DataStore): warten statt die Offline-Zeit zu überspringen
		local waited = 0
		while not now and Services and Services.MarketService ~= nil and present(p) and waited < MARKET_WAIT do
			task.wait(1)
			waited += 1
			now = if marketReady() then marketTick() else nil
		end
		if not present(p) or depotOf(p) ~= d then
			syncing[p] = nil
			return
		end
		if not now then
			-- kein Markt (Dienst fehlt/ausgefallen): nichts nachzurechnen, Depot trotzdem nutzbar
			d.LastTick = math.max(math.floor(num(d.LastTick, 0)), Clock.Tick())
			goLive(p, d, nil, nil)
			return
		end
		local target = now - LIVE_LAG
		if math.floor(num(d.LastTick, 0)) <= 0 then
			d.LastTick = target -- neues Depot: nichts nachzuholen
			goLive(p, d, nil, nil)
			return
		end
		local buffer = { Fills = {}, Days = {}, Bell = false }
		local env = makeEnv(p, d, "Replay", buffer)
		local report = CatchUp.Run(d, env, target, {
			Cursor = newCursor,
			Candle = randomCandle,
			Yield = function()
				task.wait()
			end,
			BudgetMs = 2,
			Abort = function(): boolean
				return not present(p) or depotOf(p) ~= d
			end,
			Target = function(): number?
				local t = marketTick()
				return if t then t - LIVE_LAG else nil
			end,
		})
		-- ab hier kein Yield mehr bis "live" (kein Tick darf verloren gehen)
		if not present(p) or depotOf(p) ~= d then
			syncing[p] = nil
			return
		end
		local nowAfter = marketTick()
		if nowAfter and math.floor(num(d.LastTick, 0)) < nowAfter - LIVE_LAG - LIVE_GAP_MAX then
			-- Abgleich kam nicht hinterher (Fehler/Ausfall): Rest überspringen statt endlos neu anzusetzen
			warn(("[OrderService] Abgleich für %s unvollständig – springe auf den Markt-Tick"):format(p.Name))
			d.LastTick = nowAfter - LIVE_LAG
		end
		goLive(p, d, buffer, report)
	end)
end

local function onProfileLoaded(p: Player, data: { [string]: any })
	if not present(p) or type(data) ~= "table" or type(data.Depot) ~= "table" then
		return
	end
	local d = data.Depot
	ownerOf[d] = p
	if not isInt(d.Lic) then
		-- Depot ohne gespeicherte Lizenz-Basis: höchste Lizenz, deren Basis schon im Depot steckt
		local lic = 1
		for idx = 2, 10 do
			if basisFor(idx) <= math.floor(num(d.Basis, 0)) then
				lic = idx
			end
		end
		d.Lic = lic
	end
	local issues = Portfolio.Sanitize(d, engineNow(), isKnownInst)
	if #issues > 0 then
		warn(("[OrderService] Depot von %s repariert: %s"):format(p.Name, table.concat(issues, "; ")))
	end
	local window = math.floor(num(trading().SeqWindow, 32))
	while #d.Seq > window do
		table.remove(d.Seq, 1)
	end
	if type(data.League) ~= "table" then
		data.League = { Week = 0, Returns = {}, Trades = 0, Days = 0, Tainted = false }
	end
	Portfolio.LeagueRoll(data.League, weekOf(engineNow()))
	-- Lizenz-Basis abgleichen (Lizenz-Aufstieg, während das Depot nicht geladen war) – erst NACH dem
	-- Offline-Abgleich, damit der Abgleich mit dem Stand beim Verlassen rechnet
	pendingLicence[p] = licenceIndex(p)
	startCatchUp(p)
end

local function onPlayerRemoving(p: Player)
	local d = depotOf(p)
	if d then
		ownerOf[d] = nil
	end
	live[p] = nil
	syncing[p] = nil
	replies[p] = nil
	reports[p] = nil
	tutorials[p] = nil
	lossTimes[p] = nil
	spam[p] = nil
	perksCache[p] = nil
	pendingLicence[p] = nil
	dirty[p] = nil
end

-- ---------------------------------------------------------------------
-- 7) GEWINN-TRANSFER, RETTUNGSSCHIRM
-- ---------------------------------------------------------------------
local function navNow(p: Player, d: Depot): number
	local env = makeEnv(p, d, "Live")
	return OrderEngine.NavAt(d, env, engineNow())
end

local function currentDay(): number
	return engineNow() // DAY
end

-- (Betrag, jetzt erlaubt, Grund) – inkl. offline verbuchter Auto-Transfers (Pending)
local function transferInfo(p: Player, d: Depot): (number, boolean, string?)
	local pending = math.floor(num(d.Pending, 0))
	if not live[p] then
		return pending, false, "trade.syncing"
	end
	if math.floor(num(d.LastTransferDay, -1)) >= currentDay() then
		return pending, pending > 0, if pending > 0 then nil else "trade.transferUsed"
	end
	local amount, reason = OrderEngine.TransferAmount(d, makeEnv(p, d, "Live"), navNow(p, d))
	local total = pending + amount
	return total, total > 0, if total > 0 then nil else reason
end

local function refillInfo(p: Player, d: Depot): (number, string?)
	local cfg = trading().Refill or {}
	if math.floor(num(d.LastRefillUtcDay, -1)) >= Util.UtcDay() then
		return 0, "trade.refillUsed"
	end
	if next(d.Pos) ~= nil or #d.Orders > 0 or num(d.Tutorial.Q, 0) > 0 then
		return 0, "trade.refillNotNeeded"
	end
	local basis = math.floor(num(d.Basis, 0))
	local nav = navNow(p, d)
	if nav >= math.floor(num(cfg.Below, 0.5) * basis) then
		return 0, "trade.refillNotNeeded"
	end
	local amount = math.floor(num(cfg.To, 0.5) * basis) - nav
	if amount <= 0 then
		return 0, "trade.refillNotNeeded"
	end
	return amount, nil
end

-- ---------------------------------------------------------------------
-- 8) ÖFFENTLICHE API (§C5.4)
-- ---------------------------------------------------------------------
function OrderService.Depot(p: Player): Types.Depot?
	return depotOf(p) :: any
end

function OrderService.Nav(p: Player): number
	local d = depotOf(p)
	if not d then
		return 0
	end
	return navNow(p, d)
end

function OrderService.Withdrawable(p: Player): (number, boolean, string?)
	local d = depotOf(p)
	if not d then
		return 0, false, "core.loading"
	end
	return transferInfo(p, d)
end

function OrderService.Withdraw(p: Player, reason: "Manual" | "Bell" | "Offline"): (number, string?)
	local d = depotOf(p)
	if not d or not present(p) then
		return 0, "core.loading"
	end
	if not live[p] then
		return 0, "trade.syncing"
	end
	local total = 0
	local why: string? = nil
	-- 1) schon abgebuchte Auto-Transfers (Glocke / Offline-Abgleich) abholen
	local pending = math.floor(num(d.Pending, 0))
	if pending > 0 then
		d.Pending = 0
		total += pending
	end
	-- 2) Knopf "Gewinn in den Tower": 1× je Börsentag nach den Regeln §B8.2
	if reason == "Manual" then
		local day = currentDay()
		if math.floor(num(d.LastTransferDay, -1)) >= day then
			why = "trade.transferUsed"
		else
			local amount, key = OrderEngine.TransferAmount(d, makeEnv(p, d, "Live"), navNow(p, d))
			if amount > 0 and Portfolio.Debit(d, amount, "Transfer") then
				d.LastTransferDay = day
				total += amount
			else
				why = key or "trade.transferNone"
			end
		end
	elseif total == 0 then
		why = if d.AutoTransfer == false then "trade.autoOff" else "trade.transferNone"
	end
	markDirty(p, "Depot")
	flushDirty(p)
	if total > 0 then
		return total, nil
	end
	return 0, why
end

function OrderService.SetLicence(p: Player, idx: number)
	if not isInt(idx) or idx < 1 or idx > 10 then
		return
	end
	local d = depotOf(p)
	if not d then
		return
	end
	if not live[p] then
		pendingLicence[p] = idx -- nach dem Offline-Abgleich anwenden (Abgleich rechnet mit festem Stand)
		return
	end
	applyLicence(p, d, idx)
	flushDirty(p)
end

function OrderService.TaintWeek(p: Player, reason: string)
	local data = dataOf(p)
	if not data or type(data.League) ~= "table" then
		return
	end
	Portfolio.LeagueRoll(data.League, weekOf(engineNow()))
	data.League.Tainted = true
	call("MetricsService", "Custom", p, "LeagueTaint", 1, { Reason = tostring(reason) })
	markDirty(p, "League")
	flushDirty(p)
end

-- cents > 0: Admin-Gabe (Cash + Basis, nie abhebbar). cents < 0: Admin-Abzug (Besitzer-Wunsch "geben oder abziehen")
-- höchstens bis zum freien Geld – Positionen und Reservierungen bleiben unberührt, die Basis sinkt um denselben Betrag
-- (der abhebbare Gewinn NAV − Basis bleibt gleich). Beides taintet die Liga-Woche.
function OrderService.AdminCredit(p: Player, cents: number): boolean
	if not isInt(cents) or cents == 0 or math.abs(cents) >= MAX_MONEY then
		return false
	end
	local d = depotOf(p)
	if not d then
		return false
	end
	if cents > 0 then
		if not Portfolio.Credit(d, cents, "Admin") then
			return false
		end
	else
		local take = math.min(-cents, Portfolio.Free(d))
		if take <= 0 or not Portfolio.Debit(d, take, "Admin") then
			return false
		end
	end
	OrderService.TaintWeek(p, "AdminCredit")
	markDirty(p, "Depot")
	flushDirty(p)
	return true
end

function OrderService.HoldsShares(p: Player, i: number): number
	local d = depotOf(p)
	if not d or not isInt(i) then
		return 0
	end
	return Portfolio.PosQty(d, i)
end

function OrderService.LeagueStats(p: Player): Types.LeagueStats
	local data = dataOf(p)
	local league = data and data.League
	if type(league) ~= "table" then
		return {
			Week = weekOf(engineNow()),
			SkillScore = 0,
			AvgDailyBp = 0,
			Trades = 0,
			Days = 0,
			Tainted = false,
			Qualified = false,
		}
	end
	Portfolio.LeagueRoll(league, weekOf(engineNow()))
	return Portfolio.LeagueStats(league, p:GetAttribute("IsAdmin") == true)
end

function OrderService.CatchUpReport(p: Player): { [string]: any }?
	return reports[p]
end

function OrderService.OnTrade(cb: (p: Player, f: Types.FillInfo) -> ())
	if type(cb) == "function" then
		table.insert(tradeCallbacks, cb)
	end
end

function OrderService.OnDayResult(cb: (p: Player, r: Types.DayResult) -> ())
	if type(cb) == "function" then
		table.insert(dayCallbacks, cb)
	end
end

function OrderService.OnBell(cb: (p: Player) -> ())
	if type(cb) == "function" then
		table.insert(bellCallbacks, cb)
	end
end

function OrderService.TutorialState(p: Player): "None" | "Running" | "Done"
	local data = dataOf(p)
	local d = data and data.Depot
	if type(d) == "table" and type(d.Tutorial) == "table" and d.Tutorial.Done == true then
		return "Done"
	end
	if data and type(data.Flags) == "table" and data.Flags.TutorialTrade == true then
		return "Done"
	end
	if tutorials[p] then
		return "Running"
	end
	return "None"
end

-- ---------------------------------------------------------------------
-- 9) ACAD-ÜBUNG (§B8.6): Kurs pro Spieler, Replay-Remote 1 Hz
-- ---------------------------------------------------------------------
local function tutCfg(): { [string]: any }
	local t = trading().Tutorial
	return if type(t) == "table" then t else {}
end

local function smoothstep(x: number): number
	local c = math.clamp(x, 0, 1)
	return c * c * (3 - 2 * c)
end

-- Kurs (Cent) und Phase (0 vor der News · 1 Lesefenster · 2 Rampe · 3 flach) dt Sekunden nach dem Start
local function tutPrice(dt: number): (number, number)
	local cfg = tutCfg()
	local start = num(cfg.Start, 10000)
	local newsAt = num(cfg.NewsAt, 2)
	local rampFrom = newsAt + num(cfg.ReadSeconds, 8)
	local ramp = math.max(1, num(cfg.Ramp, 45))
	local progress = smoothstep((dt - rampFrom) / ramp)
	local wiggle = num(cfg.Wiggle, 0.0015) * (math.sin(dt * 0.9) + 0.6 * math.sin(dt * 2.3)) / 1.6
	local px = math.floor(start * (1 + num(cfg.Jump, 0.15) * progress) * (1 + wiggle) + 0.5)
	local phase = if dt < newsAt then 0 elseif dt < rampFrom then 1 elseif dt < rampFrom + ramp then 2 else 3
	return math.max(1, px), phase
end

local function tutHalfSpread(px: number): number
	local classes = Config.Market and Config.Market.Classes
	local normal = type(classes) == "table" and classes.Normal or nil
	local bps = num(type(normal) == "table" and normal.SpreadBps, 8)
	return math.max(1, math.max(1, math.floor(px * bps / 10000 + 0.5)) // 2)
end

local function encodeReplay(tick: number, close: number, phase: number): buffer
	if QuoteCodec and type(QuoteCodec.EncodeReplay) == "function" then
		local ok, b = pcall(QuoteCodec.EncodeReplay, tick, close, phase)
		if ok and typeof(b) == "buffer" then
			return b
		end
	end
	local b = buffer.create(9)
	buffer.writeu32(b, 0, math.clamp(math.floor(tick), 0, 4294967295))
	buffer.writeu32(b, 4, math.clamp(math.floor(close), 0, 4294967295))
	buffer.writeu8(b, 8, math.clamp(math.floor(phase), 0, 255))
	return b
end

-- Verkauf der Übungsstück (Knopf, Automatik bei 90 s, oder beim nächsten Beitritt). auto = Preis +12 %.
finishTutorial = function(p: Player, d: Depot, auto: boolean): number?
	local tut = d.Tutorial
	local qty = math.floor(num(tut.Q, 0))
	if qty <= 0 then
		return nil
	end
	local cfg = tutCfg()
	local session = tutorials[p]
	local px: number
	if auto or not session then
		px = math.floor(num(cfg.Start, 10000) * (1 + num(cfg.AutoSellAt, 0.12)) + 0.5)
	else
		px = tutPrice(Clock.Tick() - session.T0)
	end
	local bid = math.max(1, px - tutHalfSpread(px))
	local lic = licenceOf(p)
	local proceeds = PortfolioMath.SellProceeds(qty, bid, lic.FeeBps, num(trading().MinFeeCents, 100))
	Portfolio.Credit(d, proceeds, "Tutorial")
	tut.Q = 0
	tut.Done = true
	local data = dataOf(p)
	if data then
		if type(data.Flags) ~= "table" then
			data.Flags = {}
		end
		data.Flags.TutorialTrade = true
		call("PlayerStateService", "MarkDirty", p, "Flags")
	end
	local cost = if session then math.floor(num(session.Cost, 0)) else 0
	local pnl = proceeds - cost
	if session then
		session.Ended = true
	end
	markDirty(p, "Depot")
	if cost > 0 then
		local sign = if pnl >= 0 then "+" else "-"
		notify(p, "trade.tutSold", { sign .. tostring(math.abs(pnl) // 100) }, "Success")
	end
	return pnl
end

local function tutorialStep()
	local now = Clock.Tick()
	for p, session in pairs(tutorials) do
		if not present(p) then
			tutorials[p] = nil
			continue
		end
		local d = depotOf(p)
		if not d then
			tutorials[p] = nil
			continue
		end
		local cfg = tutCfg()
		local dt = now - session.T0
		if session.Bought and not session.Ended and num(d.Tutorial.Q, 0) > 0 and dt >= num(cfg.AutoSellAfter, 90) then
			finishTutorial(p, d, true)
			flushDirty(p)
		end
		if session.Ended or dt > num(cfg.Timeout, 240) then
			if num(d.Tutorial.Q, 0) > 0 then
				finishTutorial(p, d, true)
				flushDirty(p)
			end
			tutorials[p] = nil
			continue
		end
		local px, phase = tutPrice(dt)
		pcall(function()
			Remotes.Replay:FireClient(p, encodeReplay(now, px, phase))
		end)
	end
end

-- ---------------------------------------------------------------------
-- 10) REQUEST-HYGIENE: exakte Schlüssel, Typen, Seq-Fenster (rückt auch bei Ablehnung vor)
-- ---------------------------------------------------------------------
local function exactKeys(arg: any, allowed: { [string]: boolean }): boolean
	if type(arg) ~= "table" then
		return false
	end
	local n = 0
	for key in pairs(arg) do
		n += 1
		if n > 24 or type(key) ~= "string" or not allowed[key] then
			return false
		end
	end
	return true
end

local function isId(v: any): boolean
	return isInt(v) and v >= 1 and v <= MAX_NUMBER_ARG
end

local function isPrice(v: any): boolean
	return Util.IsFinite(v) and v > 0 and v <= MAX_PRICE_ARG
end

local function reject(p: Player, key: string, args: { any }?): Reply
	notify(p, key, args, "Error")
	return { Ok = false, Key = key, Args = args }
end

local function seqDuplicate(p: Player, d: Depot, seq: number): Reply?
	if table.find(d.Seq, seq) then
		local cache = replies[p]
		local cached = cache and cache[seq]
		return cached or { Ok = false, Key = "trade.duplicate" }
	end
	return nil
end

local function recordSeq(p: Player, d: Depot, seq: number)
	table.insert(d.Seq, seq)
	local window = math.floor(num(trading().SeqWindow, 32))
	while #d.Seq > window do
		local old = table.remove(d.Seq, 1)
		local cache = replies[p]
		if cache and old ~= nil then
			cache[old] = nil
		end
	end
end

local function storeReply(p: Player, seq: number, reply: Reply)
	local cache = replies[p]
	if not cache then
		cache = {}
		replies[p] = cache
	end
	cache[seq] = reply
end

-- Gemeinsamer Rahmen für Seq-Aktionen: Depot da? live? Seq gültig/neu? -> Fenster vorrücken -> Handler
local function withSeq(p: Player, arg: any, fn: (Depot) -> Reply): Reply
	if type(arg) ~= "table" or not isInt(arg.Seq) or arg.Seq < 0 or arg.Seq > 2 ^ 31 then
		return reject(p, "trade.invalid")
	end
	local d = depotOf(p)
	if not d then
		return { Ok = false, Key = "core.loading" }
	end
	local duplicate = seqDuplicate(p, d, arg.Seq)
	if duplicate then
		return duplicate -- gleiche Antwort wie beim ersten Mal (Doppelklick/Retry), ohne neue Meldung
	end
	recordSeq(p, d, arg.Seq) -- Fenster rückt AUCH bei Ablehnung vor (CC Runde-2, kritisch)
	local ok, result = pcall(fn, d)
	local reply: Reply = if ok and type(result) == "table" then result else { Ok = false, Key = "core.error" }
	if not ok then
		logError("Seq-Aktion", result)
	end
	storeReply(p, arg.Seq, reply)
	markDirty(p, "Depot")
	flushDirty(p)
	return reply
end

local function tradingOpen(p: Player): string?
	if not live[p] then
		return "trade.syncing"
	end
	if not marketTick() or not marketReady() then
		return "trade.marketClosed"
	end
	local ok, blocked = call("AdminService", "OwnerTradeBlocked", p)
	if ok and blocked == true then
		return "trade.ownerBlocked"
	end
	return nil
end

local function noteSpam(p: Player)
	local now = os.clock()
	local entry = spam[p]
	if not entry or now - entry.Window >= 60 then
		entry = { Window = now, Count = 0, Flagged = false }
		spam[p] = entry
	end
	entry.Count += 1
	if not entry.Flagged and entry.Count > math.floor(num(trading().SpamPerMinute, 50)) then
		entry.Flagged = true
		local weights = Config.Security and Config.Security.Weights
		local points = num(type(weights) == "table" and weights.Rate, 1)
		call("AntiCheatService", "Add", p, "TradeSpam", points, { PerMin = entry.Count })
	end
end

-- ---------------------------------------------------------------------
-- 11) HANDLER
-- ---------------------------------------------------------------------
local PLACE_KEYS = {
	I = true,
	Side = true,
	Type = true,
	Qty = true,
	Pct = true,
	Lim = true,
	Stp = true,
	Tp = true,
	Trl = true,
	Protect = true,
	Exp = true,
	MaxPx = true,
	MinPx = true,
	Seq = true,
}
local TYPE_FIELDS = { -- erlaubte Preis-Felder je Ordertyp
	MKT = {},
	LMT = { Lim = true },
	STP = { Stp = true },
	TP = { Tp = true },
	OCO = { Stp = true, Tp = true },
	TRL = { Trl = true },
}

local function fillReply(p: Player, result: OrderEngine.Result): Reply
	if not result.Ok then
		return reject(p, result.Key or "trade.invalid", result.Args)
	end
	local fill = result.Fill
	if fill then
		local whole, cents = priceArgs(fill.Px)
		local key = if fill.Side == "B" then "trade.boughtNow" else "trade.soldNow"
		notify(p, key, { fill.Q, tickerOf(fill.I), whole, cents }, "Success")
		return { Ok = true, Key = key, Fill = fill, Qty = result.Qty }
	end
	return { Ok = true, OrderId = result.OrderId, Qty = result.Qty }
end

local function handlePlace(p: Player, arg: any): Reply
	noteSpam(p)
	if not exactKeys(arg, PLACE_KEYS) then
		return reject(p, "trade.invalid")
	end
	return withSeq(p, arg, function(d: Depot): Reply
		local closed = tradingOpen(p)
		if closed then
			return reject(p, closed)
		end
		-- Typen & Wertebereiche
		if not isId(arg.I) or (arg.Side ~= "B" and arg.Side ~= "S") or TYPE_FIELDS[arg.Type] == nil then
			return reject(p, "trade.invalid")
		end
		local hasQty, hasPct = arg.Qty ~= nil, arg.Pct ~= nil
		if hasQty == hasPct then
			return reject(p, "trade.invalid") -- genau eins von Stück oder Chip
		end
		if hasQty and (not isId(arg.Qty)) then
			return reject(p, "trade.invalid")
		end
		local pct: any = nil
		if hasPct then
			local chips = trading().Chips or { 0.10, 0.25, "Max" }
			if arg.Pct == "Max" then
				pct = "Max"
			elseif arg.Pct == 10 then
				pct = num(chips[1], 0.10)
			elseif arg.Pct == 25 then
				pct = num(chips[2], 0.25)
			else
				return reject(p, "trade.invalid")
			end
		end
		local fields = TYPE_FIELDS[arg.Type]
		for _, key in ipairs({ "Lim", "Stp", "Tp", "Trl" }) do
			if arg[key] ~= nil and not fields[key] then
				return reject(p, "trade.invalid")
			end
		end
		for _, key in ipairs({ "Lim", "Stp", "Tp", "MaxPx", "MinPx" }) do
			if arg[key] ~= nil and not isPrice(arg[key]) then
				return reject(p, "trade.invalid")
			end
		end
		if arg.Trl ~= nil and not isInt(arg.Trl) then
			return reject(p, "trade.invalid")
		end
		if arg.Protect ~= nil and type(arg.Protect) ~= "boolean" then
			return reject(p, "trade.invalid")
		end
		if arg.Protect == true and (arg.Side ~= "B" or (arg.Type ~= "MKT" and arg.Type ~= "LMT")) then
			return reject(p, "trade.invalid")
		end
		if arg.Exp ~= nil and arg.Exp ~= "DAY" and arg.Exp ~= "24H" then
			return reject(p, "trade.invalid")
		end
		local isMarket = arg.Type == "MKT"
		local isBuy = arg.Side == "B"
		if (arg.MaxPx ~= nil and not (isMarket and isBuy)) or (arg.MinPx ~= nil and not (isMarket and not isBuy)) then
			return reject(p, "trade.invalid")
		end
		local env = makeEnv(p, d, "Live")
		local result = OrderEngine.Place(d, env, engineNow(), {
			I = arg.I,
			Side = arg.Side,
			Type = arg.Type,
			Qty = arg.Qty,
			Pct = pct,
			Lim = arg.Lim,
			Stp = arg.Stp,
			Tp = arg.Tp,
			Trl = arg.Trl,
			Protect = arg.Protect == true,
			Exp = arg.Exp,
			MaxPx = arg.MaxPx,
			MinPx = arg.MinPx,
			Live = true,
		})
		if result.Ok and result.Fill == nil and result.OrderId then
			notify(p, "trade.orderPlaced", { tickerOf(arg.I) }, "Info")
			return { Ok = true, Key = "trade.orderPlaced", OrderId = result.OrderId, Qty = result.Qty }
		end
		return fillReply(p, result)
	end)
end

local function handleCancel(p: Player, arg: any): Reply
	if not exactKeys(arg, { OrderId = true, Seq = true }) then
		return reject(p, "trade.invalid")
	end
	return withSeq(p, arg, function(d: Depot): Reply
		if not live[p] then
			return reject(p, "trade.syncing")
		end
		if not isId(arg.OrderId) then
			return reject(p, "trade.invalid")
		end
		if not OrderEngine.Cancel(d, arg.OrderId) then
			return reject(p, "trade.orderNotFound")
		end
		notify(p, "trade.cancelled", nil, "Info")
		return { Ok = true, Key = "trade.cancelled" }
	end)
end

local function handleModify(p: Player, arg: any): Reply
	if not exactKeys(arg, { OrderId = true, Lim = true, Stp = true, Tp = true, Trl = true, Seq = true }) then
		return reject(p, "trade.invalid")
	end
	return withSeq(p, arg, function(d: Depot): Reply
		local closed = tradingOpen(p)
		if closed then
			return reject(p, closed)
		end
		if not isId(arg.OrderId) then
			return reject(p, "trade.invalid")
		end
		local changes: { [string]: number } = {}
		for _, key in ipairs({ "Lim", "Stp", "Tp" }) do
			if arg[key] ~= nil then
				if not isPrice(arg[key]) then
					return reject(p, "trade.invalid")
				end
				changes[key] = arg[key]
			end
		end
		if arg.Trl ~= nil then
			if not isInt(arg.Trl) then
				return reject(p, "trade.invalid")
			end
			changes.Trl = arg.Trl
		end
		local result = OrderEngine.Modify(d, makeEnv(p, d, "Live"), engineNow(), arg.OrderId, changes)
		if not result.Ok then
			return reject(p, result.Key or "trade.invalid", result.Args)
		end
		notify(p, "trade.modified", nil, "Info")
		return { Ok = true, Key = "trade.modified", OrderId = result.OrderId }
	end)
end

local function basketMembers(key: string): { number }?
	local companies = Config.Companies
	local baskets = type(companies) == "table" and companies.Baskets or nil
	if type(baskets) ~= "table" then
		return nil
	end
	for _, basket in ipairs(baskets) do
		if type(basket) == "table" and basket.Key == key and type(basket.Members) == "table" then
			return basket.Members
		end
	end
	return nil
end

local function handleBasket(p: Player, arg: any): Reply
	if not exactKeys(arg, { Basket = true, Pct = true, Seq = true }) then
		return reject(p, "trade.invalid")
	end
	return withSeq(p, arg, function(d: Depot): Reply
		local closed = tradingOpen(p)
		if closed then
			return reject(p, closed)
		end
		if type(arg.Basket) ~= "string" or #arg.Basket > 32 or (arg.Pct ~= 10 and arg.Pct ~= 25) then
			return reject(p, "trade.invalid")
		end
		local env = makeEnv(p, d, "Live")
		if env.Licence.Index < math.floor(num(trading().TraderFrom, 4)) then
			return reject(p, "trade.basketLocked")
		end
		local members = basketMembers(arg.Basket)
		if not members or #members == 0 then
			return reject(p, "trade.basketUnknown")
		end
		local chips = trading().Chips or { 0.10, 0.25 }
		local pct = if arg.Pct == 10 then num(chips[1], 0.10) else num(chips[2], 0.25)
		local t = engineNow()
		local nav = OrderEngine.NavAt(d, env, t)
		local per = math.floor(pct * nav / #members)
		local done = 0
		local minFee = num(trading().MinFeeCents, 100)
		for _, i in ipairs(members) do
			if isInt(i) and OrderEngine.InstAllowed(env, i) then
				local _, ask = liveQuote(i)
				if ask then
					local qty =
						PortfolioMath.AffordableQty(math.min(per, Portfolio.Free(d)), ask, env.Licence.FeeBps, minFee)
					if qty >= 1 then
						local result =
							OrderEngine.Place(d, env, t, { I = i, Side = "B", Type = "MKT", Qty = qty, Live = true })
						if result.Ok then
							done += 1
						end
					end
				end
			end
		end
		if done == 0 then
			return reject(p, "trade.basketNone")
		end
		notify(p, "trade.basketDone", { done, #members }, "Success")
		return { Ok = true, Key = "trade.basketDone", Fills = done }
	end)
end

local function handleRefill(p: Player, arg: any): Reply
	if arg ~= nil and not exactKeys(arg, {}) then
		return reject(p, "trade.invalid")
	end
	local d = depotOf(p)
	if not d then
		return { Ok = false, Key = "core.loading" }
	end
	if not live[p] then
		return reject(p, "trade.syncing")
	end
	local amount, why = refillInfo(p, d)
	if amount <= 0 then
		return reject(p, why or "trade.refillNotNeeded")
	end
	if not Portfolio.Credit(d, amount, "Refill") then
		return reject(p, "trade.invalid")
	end
	d.LastRefillUtcDay = Util.UtcDay()
	notify(p, "trade.refill", { amount // 100 }, "Success")
	markDirty(p, "Depot")
	flushDirty(p)
	return { Ok = true, Key = "trade.refill", Amount = amount }
end

local function handleAuto(p: Player, arg: any): Reply
	if not exactKeys(arg, { On = true }) or type(arg.On) ~= "boolean" then
		return reject(p, "trade.invalid")
	end
	local d = depotOf(p)
	if not d then
		return { Ok = false, Key = "core.loading" }
	end
	d.AutoTransfer = arg.On
	notify(p, if arg.On then "trade.autoOn" else "trade.autoOff", nil, "Info")
	markDirty(p, "Depot")
	flushDirty(p)
	return { Ok = true }
end

local function handleWatch(p: Player, arg: any): Reply
	if not exactKeys(arg, { List = true, Ids = true }) or not isInt(arg.List) or type(arg.Ids) ~= "table" then
		return reject(p, "trade.invalid")
	end
	local d = depotOf(p)
	if not d then
		return { Ok = false, Key = "core.loading" }
	end
	local cfg = trading().Watch or {}
	local maxIds = math.floor(num(cfg.MaxIds, 12))
	local _, perks = licAndPerks(p)
	local lists = math.min(math.floor(num(perks.Watchlists, 1)), math.floor(num(cfg.MaxLists, 5)))
	if arg.List < 1 or arg.List > lists or arg.List > #d.Watch + 1 then
		return reject(p, "trade.watchLocked")
	end
	local clean, seen = {}, {}
	local count = 0
	for key, id in pairs(arg.Ids) do
		count += 1
		if count > maxIds or type(key) ~= "number" or not isId(id) or not isListed(id) then
			return reject(p, "trade.invalid")
		end
		if not seen[id] then
			seen[id] = true
			table.insert(clean, id)
		end
	end
	if count ~= #arg.Ids then
		return reject(p, "trade.invalid") -- nur lückenlose Listen
	end
	d.Watch[arg.List] = clean
	markDirty(p, "Depot")
	flushDirty(p)
	return { Ok = true }
end

local function handleAlertSet(p: Player, arg: any): Reply
	if not exactKeys(arg, { I = true, Px = true, Dir = true }) then
		return reject(p, "trade.invalid")
	end
	if not isId(arg.I) or not isPrice(arg.Px) or (arg.Dir ~= "Up" and arg.Dir ~= "Down") then
		return reject(p, "trade.invalid")
	end
	local d = depotOf(p)
	if not d then
		return { Ok = false, Key = "core.loading" }
	end
	if not isListed(arg.I) then
		return reject(p, "trade.unknownInst")
	end
	local _, perks = licAndPerks(p)
	local limit = math.min(math.floor(num(perks.Alerts, 3)), math.floor(num(trading().MaxAlertsHard, 18)))
	if #d.Alerts >= limit then
		return reject(p, "trade.alertLimit", { limit })
	end
	local mid = priceAt(arg.I, engineNow())
	local px = math.floor(arg.Px + 0.5)
	local band = num(trading().AlertBand, 0.5)
	if not mid or px < mid * (1 - band) or px > mid * (1 + band) then
		return reject(p, "trade.fatFinger")
	end
	local id = math.max(1, math.floor(num(d.NextId, 1)))
	d.NextId = id + 1
	table.insert(d.Alerts, { Id = id, I = arg.I, Px = px, Dir = arg.Dir })
	notify(p, "trade.alertSet", { tickerOf(arg.I) }, "Info")
	markDirty(p, "Depot")
	flushDirty(p)
	return { Ok = true, Id = id }
end

local function handleAlertRemove(p: Player, arg: any): Reply
	if not exactKeys(arg, { Id = true }) or not isId(arg.Id) then
		return reject(p, "trade.invalid")
	end
	local d = depotOf(p)
	if not d then
		return { Ok = false, Key = "core.loading" }
	end
	for index, a in ipairs(d.Alerts) do
		if a.Id == arg.Id then
			table.remove(d.Alerts, index)
			markDirty(p, "Depot")
			flushDirty(p)
			return { Ok = true }
		end
	end
	return reject(p, "trade.alertNotFound")
end

-- Summe der Kapitalanteile aller laufenden Bots (ohne Platz "except")
local function botCapitalSum(env: Env, d: Depot, except: number?): number
	local sum = 0
	for index, slot in ipairs(d.Bots) do
		if index ~= except and slot.On == true and BotEngine.Preset(slot.Preset) then
			sum += BotEngine.Capital(env, slot)
		end
	end
	return sum
end

local function handleBotSet(p: Player, arg: any): Reply
	if not exactKeys(arg, { Slot = true, Preset = true, Pct = true, Target = true }) then
		return reject(p, "trade.invalid")
	end
	if not isInt(arg.Slot) or type(arg.Preset) ~= "string" or not Util.IsFinite(arg.Pct) then
		return reject(p, "trade.invalid")
	end
	if arg.Target ~= nil and not isId(arg.Target) then
		return reject(p, "trade.invalid")
	end
	local d = depotOf(p)
	if not d then
		return { Ok = false, Key = "core.loading" }
	end
	if not live[p] then
		return reject(p, "trade.syncing")
	end
	local env = makeEnv(p, d, "Live")
	local slots = math.floor(num(env.Perks.BotSlots, env.Licence.BotSlots))
	if arg.Slot < 1 or arg.Slot > slots or arg.Slot > #d.Bots + 1 then
		return reject(p, "trade.botSlots")
	end
	local preset = BotEngine.Preset(arg.Preset)
	if not preset or not BotEngine.Unlocked(env, arg.Preset) then
		return reject(p, "trade.botLocked")
	end
	local pct = arg.Pct
	if pct < num(preset.Min, 0) - 1e-9 or pct > num(preset.Max, 1) + 1e-9 then
		return reject(p, "trade.invalid")
	end
	local target: number? = nil
	if preset.Target == "ETF" then
		target = arg.Target or math.floor(num(preset.DefaultTarget, 40))
		if
			OrderEngine.ClassOf(env, target :: number) ~= "ETF" or not OrderEngine.InstAllowed(env, target :: number)
		then
			return reject(p, "trade.botTarget")
		end
	elseif preset.Target == "Inst" then
		target = arg.Target
		if target == nil or not OrderEngine.InstAllowed(env, target) then
			return reject(p, "trade.botTarget")
		end
	elseif arg.Target ~= nil then
		return reject(p, "trade.botTarget")
	end
	local existing = d.Bots[arg.Slot]
	local slot = BotEngine.NewSlot(arg.Preset, pct, target)
	if type(existing) == "table" then
		if existing.Preset == arg.Preset then
			slot.Q = existing.Q or {} -- gleiche Strategie: Bestände bleiben beim Bot
			slot.On = existing.On == true
			slot.Day, slot.DayVal, slot.DayFlow, slot.DayNav, slot.Last =
				existing.Day, existing.DayVal, existing.DayFlow, existing.DayNav, existing.Last
		else
			OrderEngine.CancelBotOrders(d, arg.Slot) -- neue Strategie: Bestände gehören wieder dir
		end
	end
	if
		slot.On
		and botCapitalSum(env, d, arg.Slot) + BotEngine.Capital(env, slot) > num(trading().BotTotalPct, 0.30) + 1e-9
	then
		return reject(p, "trade.botTotal")
	end
	d.Bots[arg.Slot] = slot
	notify(p, "trade.botSaved", nil, "Success")
	markDirty(p, "Depot")
	flushDirty(p)
	return { Ok = true }
end

local function handleBotToggle(p: Player, arg: any): Reply
	if not exactKeys(arg, { Slot = true, On = true }) or not isInt(arg.Slot) or type(arg.On) ~= "boolean" then
		return reject(p, "trade.invalid")
	end
	local d = depotOf(p)
	if not d then
		return { Ok = false, Key = "core.loading" }
	end
	if not live[p] then
		return reject(p, "trade.syncing")
	end
	local slot = d.Bots[arg.Slot]
	if type(slot) ~= "table" or not BotEngine.Preset(slot.Preset) then
		return reject(p, "trade.botSlots")
	end
	local env = makeEnv(p, d, "Live")
	if arg.On then
		if not BotEngine.Unlocked(env, slot.Preset) then
			return reject(p, "trade.botLocked")
		end
		if botCapitalSum(env, d, arg.Slot) + BotEngine.Capital(env, slot) > num(trading().BotTotalPct, 0.30) + 1e-9 then
			return reject(p, "trade.botTotal")
		end
		slot.On = true
		slot.Paused = false
		notify(p, "trade.botOn", nil, "Success")
	else
		slot.On = false -- Not-Aus: keine neuen Trades, offene Bot-Orders weg, Bestände bleiben
		OrderEngine.CancelBotOrders(d, arg.Slot)
		notify(p, "trade.botOff", nil, "Info")
	end
	markDirty(p, "Depot")
	flushDirty(p)
	return { Ok = true }
end

local function handleHistory(p: Player, arg: any): Reply
	if arg ~= nil and not exactKeys(arg, {}) then
		return reject(p, "trade.invalid")
	end
	local d = depotOf(p)
	if not d then
		return { Ok = false, Key = "core.loading" }
	end
	return { Ok = true, Fills = d.Fills, Nav = d.Nav }
end

local function handleTutorial(p: Player, arg: any): Reply
	if not exactKeys(arg, { Action = true }) then
		return reject(p, "trade.invalid")
	end
	local action = arg.Action
	if action ~= "Start" and action ~= "Buy" and action ~= "Sell" then
		return reject(p, "trade.invalid")
	end
	local data = dataOf(p)
	local d = data and data.Depot
	if type(d) ~= "table" then
		return { Ok = false, Key = "core.loading" }
	end
	if not live[p] then
		return reject(p, "trade.syncing")
	end
	local cfg = tutCfg()
	local done = d.Tutorial.Done == true or (type(data.Flags) == "table" and data.Flags.TutorialTrade == true)
	local now = Clock.Tick()
	local session = tutorials[p]
	if action == "Start" then
		if done then
			return reject(p, "trade.tutDone")
		end
		if session and session.Bought and not session.Ended then
			return { Ok = true, T0 = session.T0 } -- läuft schon (z. B. zweiter Klick)
		end
		tutorials[p] = { T0 = now, Bought = false, Ended = false, Cost = 0 }
		d.Tutorial.T0 = now
		d.Tutorial.Q = 0
		local px = tutPrice(0)
		return { Ok = true, T0 = now, Px = px, I = math.floor(num(cfg.InstId, 250)) }
	end
	if not session or session.Ended then
		return reject(p, "trade.tutNotRunning")
	end
	local dt = now - session.T0
	local px = tutPrice(dt)
	local hs = tutHalfSpread(px)
	local lic = licenceOf(p)
	local minFee = num(trading().MinFeeCents, 100)
	if action == "Buy" then
		if session.Bought then
			return reject(p, "trade.duplicate")
		end
		local ask = px + hs
		local nav = navNow(p, d)
		local budget = math.min(math.floor(num(cfg.Chip, 0.10) * nav), Portfolio.Free(d))
		local qty = PortfolioMath.AffordableQty(budget, ask, lic.FeeBps, minFee)
		if qty < 1 then
			return reject(p, "trade.qtyZero")
		end
		local cost = PortfolioMath.BuyCost(qty, ask, lic.FeeBps, minFee)
		if not Portfolio.Debit(d, cost, "Tutorial") then
			return reject(p, "trade.noCash")
		end
		d.Tutorial.Q = qty
		session.Bought = true
		session.Cost = cost
		call("MetricsService", "Funnel", p, 6, "TutorialTrade")
		markDirty(p, "Depot")
		flushDirty(p)
		notify(p, "trade.tutBought", { qty }, "Success")
		return { Ok = true, Q = qty, Px = ask }
	end
	-- Sell
	if not session.Bought or num(d.Tutorial.Q, 0) <= 0 then
		return reject(p, "trade.noShares")
	end
	local pnl = finishTutorial(p, d, false)
	flushDirty(p)
	return { Ok = true, Pnl = pnl or 0 }
end

-- ---------------------------------------------------------------------
-- 12) STATE (§C10) – nie yielden, nie nil
-- ---------------------------------------------------------------------
local function depotState(p: Player): { [string]: any }
	local d = depotOf(p)
	if not d then
		return {
			Cash = 0,
			Basis = 0,
			Nav = 0,
			Pos = {},
			Orders = {},
			Alerts = {},
			Watch = { {} },
			Bots = {},
			AutoTransfer = true,
			Withdrawable = 0,
			TransferReady = false,
			RefillReady = false,
			Stats = {},
			Pending = 0,
			Syncing = true,
			Tutorial = "None",
		}
	end
	local withdrawable, ready = transferInfo(p, d)
	local refill = if live[p] then refillInfo(p, d) else 0
	return {
		Cash = d.Cash,
		Basis = d.Basis,
		Nav = navNow(p, d),
		Pos = d.Pos,
		Orders = d.Orders,
		Alerts = d.Alerts,
		Watch = d.Watch,
		Bots = d.Bots,
		AutoTransfer = d.AutoTransfer ~= false,
		Withdrawable = withdrawable,
		TransferReady = ready,
		RefillReady = refill > 0,
		Stats = d.Stats,
		Pending = math.floor(num(d.Pending, 0)),
		Syncing = live[p] ~= true,
		Tutorial = OrderService.TutorialState(p),
	}
end

local function leagueState(p: Player): { [string]: any }
	local stats = OrderService.LeagueStats(p)
	local data = dataOf(p)
	local league = data and data.League
	local state: { [string]: any } = table.clone(stats :: any)
	state.Tier = Portfolio.TierOf(stats.SkillScore, stats.Qualified)
	state.LastTier = if type(league) == "table" and type(league.LastTier) == "string" then league.LastTier else "None"
	state.LastWeek = if type(league) == "table" and isInt(league.LastWeek) then league.LastWeek else 0
	return state
end

-- ---------------------------------------------------------------------
-- 13) INIT / START
-- ---------------------------------------------------------------------
function OrderService.Init(services: any)
	Services = services
	Portfolio.SetObserver(onFlow)

	call("PlayerStateService", "Provide", "Depot", depotState)
	call("PlayerStateService", "Provide", "League", leagueState)

	local function Handle(action: string, fn: (Player, any) -> Reply, opts: { [string]: any })
		local ok, err = call("PlayerStateService", "Handle", action, fn, opts)
		if not ok then
			logError("Handle " .. action, err)
		end
	end
	-- Raten laut §C9 (B = Token-Bucket {Kapazität, Nachfüllen/s})
	Handle("TradePlace", handlePlace, { Bucket = { 6, 1.5 } })
	Handle("TradeCancel", handleCancel, { Bucket = { 10, 3 } })
	Handle("TradeModify", handleModify, { Bucket = { 10, 3 } })
	Handle("TradeBasket", handleBasket, { Rate = 1, Per = 2 })
	Handle("TradeRefill", handleRefill, { Rate = 1, Per = 5 })
	Handle("TradeAuto", handleAuto, { Rate = 1, Per = 1 })
	Handle("TradeWatch", handleWatch, { Rate = 1, Per = 1 })
	Handle("AlertSet", handleAlertSet, { Rate = 2, Per = 1 })
	Handle("AlertRemove", handleAlertRemove, { Rate = 2, Per = 1 })
	Handle("BotSet", handleBotSet, { Rate = 2, Per = 1 })
	Handle("BotToggle", handleBotToggle, { Rate = 2, Per = 1 })
	Handle("DepotHistory", handleHistory, { Rate = 1, Per = 1 })
	Handle("TutorialTrade", handleTutorial, { Rate = 2, Per = 1 })
end

function OrderService.Start()
	local okLoaded, errLoaded = call("DataService", "OnProfileLoaded", onProfileLoaded)
	if not okLoaded then
		warn("[OrderService] DataService fehlt – Depots werden nicht geladen: " .. tostring(errLoaded))
	end
	local okTick = call("MarketService", "OnTick", onMarketTick)
	if not okTick then
		warn("[OrderService] MarketService.OnTick fehlt – Orders werden nicht ausgelöst")
	end
	call("MarketService", "OnDayClose", function(_day: number, _t: number)
		-- Tagesabschluss rechnet Step selbst (gleiche Reihenfolge wie offline); hier nur State auffrischen
		for _, p in ipairs(Players:GetPlayers()) do
			if live[p] then
				markDirty(p, "Depot", "League")
			end
		end
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	Scheduler.Every("AcadReplay", 1, function()
		tutorialStep()
	end)
end

-- Nur für Selbsttests (OrderTests): Engine-Module und Hilfen ohne Spieler
OrderService._Test = {
	Portfolio = Portfolio,
	OrderEngine = OrderEngine,
	BotEngine = BotEngine,
	CatchUp = CatchUp,
	TutPrice = tutPrice,
	NormalizeLicence = normalizeLicence,
	BasisFor = basisFor,
	Seq = {
		Duplicate = seqDuplicate,
		Record = recordSeq,
		Store = storeReply,
		Clear = function(key: any)
			replies[key] = nil
		end,
	},
}

return OrderService
