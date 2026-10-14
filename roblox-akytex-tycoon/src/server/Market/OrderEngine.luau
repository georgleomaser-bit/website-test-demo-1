-- =====================================================================
--  AKYTEX TYCOON – Order-Logik: Platzieren, Trigger je 1s-Kerze, Ablauf, Dividenden, Börsentag-Schluss
--  (Server/Market/OrderEngine)
--  Besitzer: WP4 (Orders, Depot, Bots). Vertrag: DESIGN.md §B7.3, §B8.2, §C9 (TradePlace/Cancel/Modify), §C11;
--  MARKET.md §11.1–§11.6, §12.3, §12.6, §13.
--  Reines Daten-Modul ohne Remotes/Services/Yield: alle Kurse kommen über eine "Env"-Tabelle (OrderService baut sie
--  aus MarketService; Tests bauen einen künstlichen Markt). Online und Offline (CatchUp) rufen DIESELBE Funktion
--  Step(d, env, t, ctx) je Tick auf -> gleiche Fills, gleiche Ticks (Abnahme WP4 #4).
--
--  Ablauf je Tick (Step):  Börsentag-Schluss (t % 1200 == 0) -> abgelaufene Orders -> Trigger je Wert (1s-Kerze t,
--  nur Orders mit T0 < t, Pfad-Regel) -> Alarme -> Dividenden (Bestand nach den Triggern) -> Bots (t % 60 == 0)
--  -> d.LastTick = t.
--
--  Kurse der Engine (Trigger, Bots, Depotwert-Grenzen): mid = PriceAt(i, t), halber Spread hs je Minute aus dem
--  Schlusskurs der Vorminute × Klassen-Spread (Config.Market.Classes) – deterministisch, damit Offline == Online.
--  "Sofort"-Orders der Spieler laufen zum zuletzt gesendeten Quote (env.Quote, MARKET §11.1).
--
--  Öffentliche API:
--    OrderEngine.HalfSpread(env, i, t): number         OrderEngine.EngineQuote(env, i, t): (bid?, ask?, mid?)
--    OrderEngine.NavAt(d, env, t): number              OrderEngine.TransferAmount(d, env, nav): (cents, reasonKey?)
--    OrderEngine.Place(d, env, t, req): Result         req = { I, Side, Type, Qty?, Pct?, Lim?, Stp?, Tp?, Trl?,
--                                                      Protect?, Exp?, MaxPx?, MinPx?, Bot?, Live? }
--    OrderEngine.Cancel(d, id): boolean                OrderEngine.Modify(d, env, t, id, changes): Result
--    OrderEngine.CancelBotOrders(d, slot, inst?) · BuyNow/SellNow · AttachProtection/AttachStop (Bots)
--    OrderEngine.CheckInstrument(d, env, i, t, o, h, l, c)   OrderEngine.CheckAlerts(d, env, i, t, h, l)
--    OrderEngine.Expire(d, env, t) · OrderEngine.PayDividends(d, env, t, list) · OrderEngine.CloseDay(d, env, t)
--    OrderEngine.Step(d, env, t, ctx)                  ctx = { Candle = (i) -> (o, h, l, c)?, Divs = { … }? }
--    OrderEngine.ActiveInstruments(d): { number }      Werte mit offenen Orders oder Alarmen (sortiert)
--    OrderEngine.CanTrigger(d, i, hMax, lMin, hs): boolean   Minuten-Überspringen im Offline-Abgleich (exakt)
--    OrderEngine.InstAllowed(env, i) · ClassOf(env, i) · PosCap(env, i) · MaxWeightFor(env, i)
--    OrderEngine.UseBots(botEngine)                    BotEngine meldet sich selbst an (keine Ring-Abhängigkeit)
--  Result = { Ok: boolean, Key: string?, Args: { any }?, Fill: Types.FillInfo?, OrderId: number?, Qty: number? }
--  Env-Ereignisse (env.Emit(kind, data)): Fill, Expired, Cancelled, Cut, Alert, Dividend, DayResult, Transfer, Bell,
--  BotPaused.
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))
local Clock = require(Shared:WaitForChild("Clock"))
local PortfolioMath = require(Shared:WaitForChild("Market"):WaitForChild("PortfolioMath"))
local Portfolio = require(script.Parent:WaitForChild("Portfolio"))

local OrderEngine = {}

type Depot = { [string]: any }
type Order = { [string]: any }
export type Result = {
	Ok: boolean,
	Key: string?,
	Args: { any }?,
	Fill: Types.FillInfo?,
	OrderId: number?,
	Qty: number?,
}
export type Lic = {
	Index: number,
	Basis: number,
	BauKurs: number,
	FeeBps: number,
	MaxWeight: number,
	MaxOrders: number,
	PosFactor: number,
	Set: string,
	SetRank: number,
	BotSlots: number,
	Layer: string,
}
export type Env = {
	Mode: string, -- "Live" | "Replay"
	Licence: Lic,
	Perks: { [string]: any },
	PriceAt: (number, number) -> number?,
	Quote: ((number) -> (number?, number?, number?))?,
	Class: (number) -> string?,
	Set: (number) -> string?,
	DivBps: (number) -> number,
	Listed: (number) -> boolean,
	Halted: (number, number?) -> boolean, -- (Wert, Tick?) – mit Tick: Pause zu genau diesem Tick (offline == online)
	FactDir: (number, number) -> number?,
	AdminActive: (number) -> boolean,
	AdminBetween: (number, number) -> boolean,
	Dividends: (number, number) -> { { [string]: number } },
	Emit: (string, any) -> (),
	League: { [string]: any }?,
	Week: (number) -> number,
	OwnerTaint: boolean,
	CacheBefore: number, -- Minuten-Caches nur für Ticks davor (späte Bus-Events ändern nie Gecachtes)
	Watch: { number }?,
	ActiveIds: (() -> { number })?,
	BotsUntil: number?, -- Offline-Abgleich: Bots ruhen für Ticks in (BotsUntil, BotsFrom] (12-h-Grenze)
	BotsFrom: number?,
	NoAutoTransfer: boolean?, -- Offline-Abgleich: Höchstzahl verpasster Auto-Transfers erreicht
}

local DAY = Clock.DAY_TICKS
local SET_RANK = { Azubi = 1, Trader = 2, Fonds = 3 }
local HS_CACHE_MAX = 20000
local MAX_PRICE = 9999999 -- Kurs-Obergrenze (Cent) wie die Engine

local bots: any = nil -- BotEngine (meldet sich über UseBots an)

-- ---------------------------------------------------------------------
-- 0) KONFIG-HELFER
-- ---------------------------------------------------------------------
local function trading(): { [string]: any }
	local t = Config.Trading
	return if type(t) == "table" then t else {}
end

local function num(v: any, fallback: number): number
	if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then
		return v
	end
	return fallback
end

local function isInt(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and v % 1 == 0
end

local function minFee(): number
	return num(trading().MinFeeCents, PortfolioMath.MIN_FEE)
end

local function protectCfg(): (number, number)
	local p = trading().Protect
	return num(type(p) == "table" and p.Sl, 0.08), num(type(p) == "table" and p.Tp, 0.15)
end

function OrderEngine.UseBots(botEngine: any)
	bots = botEngine
end

-- ---------------------------------------------------------------------
-- 1) INSTRUMENTE & GRENZEN
-- ---------------------------------------------------------------------
function OrderEngine.ClassOf(env: Env, i: number): string
	local class = env.Class(i)
	return if type(class) == "string" then class else "Normal"
end

function OrderEngine.InstAllowed(env: Env, i: number): boolean
	if not isInt(i) or not env.Listed(i) then
		return false
	end
	local rank = SET_RANK[env.Set(i) or ""]
	return rank ~= nil and rank <= env.Licence.SetRank
end

function OrderEngine.PosCap(env: Env, i: number): number
	local bases = trading().LiquidityBase
	local base = num(type(bases) == "table" and bases[OrderEngine.ClassOf(env, i)], 200000000)
	return math.floor(base * env.Licence.PosFactor)
end

-- ETFs sind von der Klumpen-Grenze ausgenommen (Diversifikation lernen, MARKET §11.6)
function OrderEngine.MaxWeightFor(env: Env, i: number): number?
	if OrderEngine.ClassOf(env, i) == "ETF" then
		return nil
	end
	return env.Licence.MaxWeight
end

-- ---------------------------------------------------------------------
-- 2) ENGINE-KURSE (deterministisch je Minute)
-- ---------------------------------------------------------------------
local hsCache: { [number]: { [number]: number } } = {}
local hsCount = 0

local function spreadBps(env: Env, i: number): number
	local classes = Config.Market and Config.Market.Classes
	local entry = type(classes) == "table" and classes[OrderEngine.ClassOf(env, i)] or nil
	return num(type(entry) == "table" and entry.SpreadBps, 8)
end

-- Junge Minuten (noch nicht "sicher", späte Bus-Events möglich) landen in einem kleinen Extra-Cache: der Live-Takt
-- fragt jede Sekunde für jeden Wert mit Orders – ohne Cache wäre das ein Random-Access-Kurs je Abfrage.
local hsRecent: { [number]: { [number]: number } } = {}
local hsRecentCount = 0
local HS_RECENT_MAX = 2000

function OrderEngine.HalfSpread(env: Env, i: number, t: number): number
	local minute = t // 60
	local perInst = hsCache[i]
	local cached = perInst and perInst[minute]
	if cached then
		return cached
	end
	local safe = minute * 60 + 59 < env.CacheBefore
	local recent = hsRecent[i]
	if not safe and env.Mode == "Live" then
		local value = recent and recent[minute]
		if value then
			return value
		end
	end
	local ref = env.PriceAt(i, minute * 60 - 1) or env.PriceAt(i, t)
	if type(ref) ~= "number" or ref <= 0 then
		return 1
	end
	local spread = math.max(1, math.floor(ref * spreadBps(env, i) / 10000 + 0.5))
	local hs = math.max(1, spread // 2)
	if safe then
		if hsCount >= HS_CACHE_MAX then
			table.clear(hsCache)
			hsCount = 0
		end
		perInst = hsCache[i]
		if not perInst then
			perInst = {}
			hsCache[i] = perInst
		end
		perInst[minute] = hs
		hsCount += 1
	elseif env.Mode == "Live" then
		if hsRecentCount >= HS_RECENT_MAX then
			table.clear(hsRecent)
			hsRecentCount = 0
		end
		recent = hsRecent[i]
		if not recent then
			recent = {}
			hsRecent[i] = recent
		end
		recent[minute] = hs
		hsRecentCount += 1
	end
	return hs
end

function OrderEngine.EngineQuote(env: Env, i: number, t: number): (number?, number?, number?)
	local mid = env.PriceAt(i, t)
	if type(mid) ~= "number" or mid <= 0 then
		return nil, nil, nil
	end
	mid = math.floor(mid)
	local hs = OrderEngine.HalfSpread(env, i, t)
	return math.max(1, mid - hs), mid + hs, mid
end

function OrderEngine.NavAt(d: Depot, env: Env, t: number): number
	return Portfolio.Nav(d, function(i: number): number?
		local bid = OrderEngine.EngineQuote(env, i, t)
		return bid
	end)
end

-- Gewinn-Transfer-Betrag (§B8.2). Ausnahme: der erste Transfer nach dem ACAD-Tutorial ignoriert die 2-%-Schwelle.
function OrderEngine.TransferAmount(d: Depot, _env: Env, nav: number): (number, string?)
	local cfg = trading().Transfer or {}
	local tut = d.Tutorial
	local tutorialException = type(tut) == "table" and tut.Done == true and num(d.LastTransferDay, -1) < 0
	local threshold = if tutorialException then 0 else num(cfg.Threshold, 1.02)
	local basis = num(d.Basis, 0)
	local amount = PortfolioMath.Withdrawable(nav, Portfolio.Free(d), basis, num(cfg.DayCapPct, 0.06), threshold)
	if amount > 0 then
		return amount, nil
	end
	if nav < math.ceil(basis * threshold - 1e-6) then
		return 0, "trade.transferBelow"
	end
	return 0, "trade.transferNone"
end

-- ---------------------------------------------------------------------
-- 3) HILFEN FÜR ORDER-LISTEN
-- ---------------------------------------------------------------------
local function findOrder(d: Depot, id: number): (Order?, number?)
	for index, o in ipairs(d.Orders) do
		if o.Id == id then
			return o, index
		end
	end
	return nil, nil
end

local function removeOrder(d: Depot, o: Order): boolean
	for index, other in ipairs(d.Orders) do
		if other == o then
			table.remove(d.Orders, index)
			return true
		end
	end
	return false
end

local function nextId(d: Depot): number
	local id = math.max(1, math.floor(num(d.NextId, 1)))
	d.NextId = id + 1
	return id
end

local function manualOrderCount(d: Depot): number
	local n = 0
	for _, o in ipairs(d.Orders) do
		if o.Bot == nil then
			n += 1
		end
	end
	return n
end

local function expiryFor(t: number, exp: string?): number
	if exp == "DAY" then
		return (t // DAY + 1) * DAY
	end
	local life = trading().OrderLife
	return t + math.floor(num(type(life) == "table" and life.H24, 86400))
end

function OrderEngine.ActiveInstruments(d: Depot): { number }
	local set: { [number]: boolean } = {}
	local list: { number } = {}
	for _, o in ipairs(d.Orders) do
		if not set[o.I] then
			set[o.I] = true
			table.insert(list, o.I)
		end
	end
	for _, a in ipairs(d.Alerts) do
		if not set[a.I] then
			set[a.I] = true
			table.insert(list, a.I)
		end
	end
	table.sort(list)
	return list
end

-- ---------------------------------------------------------------------
-- 4) FILLS BUCHEN + MELDEN (gemeinsam für Sofort-Orders, Trigger und Bots)
-- ---------------------------------------------------------------------
local function noteBotFill(d: Depot, botSlot: number?, i: number, side: string, qty: number, cash: number)
	if not botSlot then
		return
	end
	local slot = d.Bots[botSlot]
	if type(slot) ~= "table" then
		return
	end
	if type(slot.Q) ~= "table" then
		slot.Q = {}
	end
	local key = tostring(i)
	local have = math.floor(num(slot.Q[key], 0))
	if side == "B" then
		slot.Q[key] = have + qty
		slot.DayFlow = math.floor(num(slot.DayFlow, 0)) - cash
	else
		local left = math.max(0, have - qty)
		slot.Q[key] = if left > 0 then left else nil
		slot.DayFlow = math.floor(num(slot.DayFlow, 0)) + cash
	end
end

-- Liga-Woche des Ticks sicherstellen (Wochenwechsel = Montag 00:00 UTC)
local function leagueFor(env: Env, t: number): { [string]: any }?
	local league = env.League
	if type(league) == "table" then
		Portfolio.LeagueRoll(league, env.Week(t))
	end
	return league
end

local function emitFill(
	d: Depot,
	env: Env,
	t: number,
	i: number,
	side: string,
	info: any,
	navBefore: number,
	botSlot: number?,
	kind: string,
	order: Order?,
	gap: boolean
): Types.FillInfo
	local cfg = trading()
	local pctNav = if navBefore > 0 then info.Gross / navBefore else 0
	local isBot = botSlot ~= nil
	local fill: Types.FillInfo
	if side == "B" then
		fill = {
			I = i,
			Side = "B",
			Q = info.Q,
			Px = info.Px,
			Fee = info.Fee,
			Pnl = nil,
			HeldS = nil,
			PctNav = pctNav,
			Protected = info.Protected == true,
			ReadWell = false,
			Bot = isBot,
			Tick = t,
		}
		Portfolio.PushFill(d, t, i, "B", info.Q, info.Px, info.Fee, 0, isBot)
		noteBotFill(d, botSlot, i, "B", info.Q, info.Total)
	else
		local held = math.floor(num(info.HeldS, 0))
		local flags = math.floor(num(info.Flags, 0))
		local minHold = num(cfg.MinHoldSeconds, 60)
		local readWell = not isBot and bit32.band(flags, Portfolio.FLAG_READWELL) ~= 0 and held >= minHold
		fill = {
			I = i,
			Side = "S",
			Q = info.Q,
			Px = info.Px,
			Fee = info.Fee,
			Pnl = info.Pnl,
			HeldS = held,
			PctNav = pctNav,
			Protected = bit32.band(flags, Portfolio.FLAG_PROTECTED) ~= 0,
			ReadWell = readWell,
			Bot = isBot,
			Tick = t,
		}
		Portfolio.PushFill(d, t, i, "S", info.Q, info.Px, info.Fee, info.Pnl, isBot)
		Portfolio.NoteSell(d, info.Pnl, info.Basis)
		noteBotFill(d, botSlot, i, "S", info.Q, info.Net)
		if readWell and type(d.Stats) == "table" then
			d.Stats.ReadWell = math.floor(num(d.Stats.ReadWell, 0)) + 1
		end
		-- zählender Trade (Liga, Börsentag): ≥ 2 % Depotwert, ≥ 60 s gehalten, kein Bot, kein Admin-Fenster
		if not isBot and pctNav >= num(cfg.MinTradePct, 0.02) and held >= minHold and not env.AdminActive(t) then
			Portfolio.AddCountingTrade(d)
			local league = leagueFor(env, t)
			if league then
				Portfolio.LeagueAddTrade(league)
			end
		end
	end
	if kind == "Market" and not isBot then
		(fill :: any).Type = "MKT" -- Sofort-Order: Fill-Audit (WP3) prüft exakt gegen Geld/Brief des Ticks
	end
	env.Emit("Fill", {
		Fill = fill,
		Kind = kind,
		OrderId = if order then order.Id else nil,
		Gap = gap,
		BotSlot = botSlot,
	})
	return fill
end

-- ---------------------------------------------------------------------
-- 5) INTERNE ORDER-ANLAGE (Schutz-Paare nach Käufen, Bots)
-- ---------------------------------------------------------------------
local function hardCap(): number
	return math.floor(num(trading().MaxOrdersHard, 50))
end

-- Schutz-Paar (OCO) für frisch gekaufte Stück; gibt die Order oder nil (Grenze erreicht) zurück
local function attachProtection(
	d: Depot,
	t: number,
	i: number,
	qty: number,
	stp: number,
	tp: number,
	botSlot: number?
): Order?
	if #d.Orders >= hardCap() or qty <= 0 then
		return nil
	end
	if stp < 1 or tp <= stp then
		return nil
	end
	local o: Order = {
		Id = nextId(d),
		I = i,
		Side = "S",
		Type = "OCO",
		Q = qty,
		Stp = stp,
		Tp = math.min(tp, MAX_PRICE),
		Res = 0,
		Exp = expiryFor(t, "24H"),
		T0 = t,
		Bot = botSlot,
	}
	table.insert(d.Orders, o)
	return o
end

-- Einfacher Verlust-Stopp (Dip-Käufer-Bot) für frisch gekaufte Stück
local function attachStop(d: Depot, t: number, i: number, qty: number, stp: number, botSlot: number?): Order?
	if #d.Orders >= hardCap() or qty <= 0 or stp < 1 then
		return nil
	end
	local o: Order = {
		Id = nextId(d),
		I = i,
		Side = "S",
		Type = "STP",
		Q = qty,
		Stp = stp,
		Res = 0,
		Exp = expiryFor(t, "24H"),
		T0 = t,
		Bot = botSlot,
	}
	table.insert(d.Orders, o)
	return o
end
OrderEngine.AttachStop = attachStop

local function protectLevels(px: number): (number, number)
	local sl, tp = protectCfg()
	return math.max(1, math.floor(px * (1 - sl))), math.ceil(px * (1 + tp))
end

-- ---------------------------------------------------------------------
-- 6) SOFORT-AUSFÜHRUNG (Spieler-"Sofort" zum gesendeten Quote, Bots zum Engine-Kurs)
-- ---------------------------------------------------------------------
local function buyNow(
	d: Depot,
	env: Env,
	t: number,
	i: number,
	qty: number,
	ask: number,
	bid: number,
	protect: boolean,
	botSlot: number?,
	kind: string
): Result
	local nav = OrderEngine.NavAt(d, env, t)
	local flags = 0
	if protect then
		flags = bit32.bor(flags, Portfolio.FLAG_PROTECTED)
	end
	local cfg = trading()
	if botSlot == nil and qty * ask >= num(cfg.MinTradePct, 0.02) * nav then
		local dir = env.FactDir(i, t)
		if type(dir) == "number" and dir > 0 then
			flags = bit32.bor(flags, Portfolio.FLAG_READWELL)
		end
	end
	local ok, info = Portfolio.Buy(d, i, qty, ask, env.Licence.FeeBps, nil, {
		Tick = t,
		Flags = flags,
		Nav = nav,
		MaxWeight = OrderEngine.MaxWeightFor(env, i),
		PosCap = OrderEngine.PosCap(env, i),
		Bid = bid,
	})
	if not ok then
		local args = if info == "trade.concentration" then { math.floor(env.Licence.MaxWeight * 100 + 0.5) } else nil
		return { Ok = false, Key = info, Args = args }
	end
	info.Protected = protect
	local fill = emitFill(d, env, t, i, "B", info, nav, botSlot, kind, nil, false)
	if protect then
		local stp, tp = protectLevels(info.Px)
		attachProtection(d, t, i, info.Q, stp, tp, botSlot)
	end
	return { Ok = true, Fill = fill, Qty = info.Q }
end

local function sellNow(
	d: Depot,
	env: Env,
	t: number,
	i: number,
	qty: number,
	bid: number,
	botSlot: number?,
	kind: string
): Result
	local nav = OrderEngine.NavAt(d, env, t)
	local ok, info = Portfolio.Sell(d, i, qty, bid, env.Licence.FeeBps, nil, { Tick = t })
	if not ok then
		return { Ok = false, Key = info }
	end
	local fill = emitFill(d, env, t, i, "S", info, nav, botSlot, kind, nil, false)
	return { Ok = true, Fill = fill, Qty = info.Q }
end

OrderEngine.BuyNow = buyNow
OrderEngine.SellNow = sellNow
OrderEngine.AttachProtection = attachProtection
OrderEngine.ProtectLevels = protectLevels

-- ---------------------------------------------------------------------
-- 7) PLATZIEREN (§C9 TradePlace; Struktur/Typen prüft OrderService, hier die Markt-Regeln)
-- ---------------------------------------------------------------------
local function fail(key: string, args: { any }?): Result
	return { Ok = false, Key = key, Args = args }
end

local function inBand(px: number, mid: number): boolean
	local band = num(trading().FatFinger, 0.5)
	return px >= mid * (1 - band) and px <= mid * (1 + band)
end

function OrderEngine.Place(d: Depot, env: Env, t: number, req: { [string]: any }): Result
	local i = req.I
	if not isInt(i) or not env.Listed(i) then
		return fail("trade.unknownInst")
	end
	if not OrderEngine.InstAllowed(env, i) then
		return fail("trade.notLicensed")
	end
	local side: string = req.Side
	local isBuy = side == "B"
	local otype: string = req.Type
	local lic = env.Licence
	local cfg = trading()
	local traderFrom = math.floor(num(cfg.TraderFrom, 4))
	-- Ordertyp nach Lizenz und Seite (§B7.3)
	if otype == "TRL" or (otype == "STP" and isBuy) then
		if lic.Index < traderFrom then
			return fail("trade.typeLocked")
		end
	end
	if (otype == "TP" or otype == "OCO" or otype == "TRL") and isBuy then
		return fail("trade.invalid")
	end

	-- Kurs: Spieler-"Sofort" zum gesendeten Quote, sonst Engine-Kurs
	local bid, ask, mid
	if req.Live == true and env.Quote then
		bid, ask, mid = env.Quote(i)
	end
	if type(mid) ~= "number" or type(bid) ~= "number" or type(ask) ~= "number" then
		bid, ask, mid = OrderEngine.EngineQuote(env, i, t)
	end
	if type(mid) ~= "number" or type(bid) ~= "number" or type(ask) ~= "number" or mid <= 0 then
		return fail("trade.marketClosed")
	end
	bid, ask, mid = math.floor(bid :: number), math.floor(ask :: number), math.floor(mid :: number)

	-- Preise: gerundet, im Fehleingabe-Band, sinnvolle Seite
	local lim = if req.Lim ~= nil then math.floor(req.Lim + 0.5) else nil
	local stp = if req.Stp ~= nil then math.floor(req.Stp + 0.5) else nil
	local tp = if req.Tp ~= nil then math.floor(req.Tp + 0.5) else nil
	for _, px in ipairs({ lim or mid, stp or mid, tp or mid }) do
		if px < 1 or not inBand(px, mid) then
			return fail("trade.fatFinger")
		end
	end
	if otype == "LMT" and lim == nil then
		return fail("trade.invalid")
	elseif otype == "STP" and stp == nil then
		return fail("trade.invalid")
	elseif otype == "TP" and tp == nil then
		return fail("trade.invalid")
	elseif otype == "OCO" and (stp == nil or tp == nil) then
		return fail("trade.invalid")
	end
	if otype == "STP" and not isBuy and (stp :: number) >= bid then
		return fail("trade.stopAbove")
	elseif otype == "STP" and isBuy and (stp :: number) <= ask then
		return fail("trade.buyStopBelow")
	elseif otype == "TP" and (tp :: number) <= bid then
		return fail("trade.targetBelow")
	elseif otype == "OCO" and ((stp :: number) >= bid or (tp :: number) <= bid) then
		return fail(if (stp :: number) >= bid then "trade.stopAbove" else "trade.targetBelow")
	end
	local trl: number? = nil
	if otype == "TRL" then
		local bounds = cfg.TrailBps or {}
		trl = req.Trl
		if not isInt(trl) or (trl :: number) < num(bounds.Min, 50) or (trl :: number) > num(bounds.Max, 2000) then
			return fail("trade.invalid")
		end
	end

	-- Menge (Stück oder Chip 10 % · 25 % · Max)
	local nav = OrderEngine.NavAt(d, env, t)
	local bps = lic.FeeBps
	local qty: number
	if isBuy then
		local refPx = if otype == "LMT"
			then lim :: number
			elseif otype == "STP" then math.ceil((stp :: number) * num(cfg.BuyStopReserve, 1.05))
			else ask
		local posValue = Portfolio.PosValue(d, i, bid)
		local capLeft = OrderEngine.PosCap(env, i) - Portfolio.PosQty(d, i) * refPx
		local maxQty = PortfolioMath.MaxQty(refPx, capLeft)
		if req.Pct ~= nil then
			local free = Portfolio.Free(d)
			local notional: number
			if req.Pct == "Max" then
				notional = free
				local maxWeight = OrderEngine.MaxWeightFor(env, i)
				if maxWeight then
					notional = math.min(notional, math.floor(maxWeight * nav) - posValue)
					if notional <= 0 then
						return fail("trade.concentration", { math.floor(maxWeight * 100 + 0.5) })
					end
				end
			else
				notional = math.floor((req.Pct :: number) * nav)
			end
			qty = math.min(PortfolioMath.AffordableQty(math.min(notional, free), refPx, bps, minFee()), maxQty)
		else
			qty = req.Qty
			if qty > maxQty then
				return fail("trade.posLimit")
			end
		end
	else
		local available = Portfolio.PosQty(d, i) - Portfolio.ReservedQty(d, i)
		if req.Pct ~= nil then
			if req.Pct == "Max" then
				qty = available
			else
				qty = math.min(available, math.ceil((req.Pct :: number) * nav / bid))
			end
		else
			qty = req.Qty
			if qty > available then
				return fail("trade.noShares")
			end
		end
	end
	if not isInt(qty) or qty < 1 then
		return fail(if isBuy then "trade.qtyZero" else "trade.noShares")
	end

	local botSlot = req.Bot
	-- SOFORT
	if otype == "MKT" then
		if env.Halted(i) then
			return fail("trade.halted")
		end
		if isBuy then
			if req.MaxPx ~= nil and ask > req.MaxPx then
				return fail("trade.priceMoved")
			end
			return buyNow(d, env, t, i, qty, ask, bid, req.Protect == true, botSlot, "Market")
		end
		if req.MinPx ~= nil and bid < req.MinPx then
			return fail("trade.priceMoved")
		end
		return sellNow(d, env, t, i, qty, bid, botSlot, "Market")
	end

	-- WARTENDE ORDER
	if #d.Orders >= hardCap() then
		return fail("trade.maxOrders", { hardCap() })
	end
	if botSlot == nil and manualOrderCount(d) >= math.min(lic.MaxOrders, hardCap()) then
		return fail("trade.maxOrders", { math.min(lic.MaxOrders, hardCap()) })
	end
	local o: Order = {
		Id = 0,
		I = i,
		Side = side,
		Type = otype,
		Q = qty,
		Res = 0,
		Exp = expiryFor(t, req.Exp),
		T0 = t,
		Bot = botSlot,
	}
	if isBuy then
		local refPx = if otype == "LMT"
			then lim :: number
			else math.ceil((stp :: number) * num(cfg.BuyStopReserve, 1.05))
		local res = PortfolioMath.BuyCost(qty, refPx, bps, minFee())
		if Portfolio.Free(d) < res then
			return fail("trade.noCash")
		end
		local maxWeight = OrderEngine.MaxWeightFor(env, i)
		if maxWeight and PortfolioMath.Weight(Portfolio.PosValue(d, i, bid), qty * refPx, nav) > maxWeight + 1e-9 then
			return fail("trade.concentration", { math.floor(maxWeight * 100 + 0.5) })
		end
		if (Portfolio.PosQty(d, i) + qty) * refPx > OrderEngine.PosCap(env, i) then
			return fail("trade.posLimit")
		end
		o.Res = res
		if otype == "LMT" then
			o.Lim = lim
			if req.Protect == true then
				-- Klammer: nach dem Kauf entsteht ein Schutz-Paar mit genau diesen Marken (relativ zum Wunschpreis)
				o.Stp, o.Tp = protectLevels(lim :: number)
			end
		else
			o.Stp = stp
		end
	else
		if otype == "LMT" then
			o.Lim = lim
		elseif otype == "STP" then
			o.Stp = stp
		elseif otype == "TP" then
			o.Tp = tp
		elseif otype == "OCO" then
			o.Stp, o.Tp = stp, tp
		elseif otype == "TRL" then
			o.Trl = trl
			o.Peak = bid
		end
	end
	o.Id = nextId(d)
	table.insert(d.Orders, o)
	return { Ok = true, OrderId = o.Id, Qty = qty }
end

-- ---------------------------------------------------------------------
-- 8) STORNO & ÄNDERN
-- ---------------------------------------------------------------------
function OrderEngine.Cancel(d: Depot, id: number): boolean
	local o = findOrder(d, id)
	if not o then
		return false
	end
	return removeOrder(d, o)
end

-- Alle offenen Orders eines Bots (optional nur eines Werts) streichen; gibt die Anzahl zurück
function OrderEngine.CancelBotOrders(d: Depot, botSlot: number, inst: number?): number
	local removed = 0
	for index = #d.Orders, 1, -1 do
		local o = d.Orders[index]
		if o.Bot == botSlot and (inst == nil or o.I == inst) then
			table.remove(d.Orders, index)
			removed += 1
		end
	end
	return removed
end

function OrderEngine.Modify(d: Depot, env: Env, t: number, id: number, changes: { [string]: any }): Result
	local o = findOrder(d, id)
	if not o then
		return fail("trade.orderNotFound")
	end
	if o.Bot ~= nil then
		return fail("trade.botOrder")
	end
	local bid, ask, mid = OrderEngine.EngineQuote(env, o.I, t)
	if type(mid) ~= "number" or type(bid) ~= "number" or type(ask) ~= "number" then
		return fail("trade.marketClosed")
	end
	local allowed = {
		LMT = { Lim = true },
		STP = { Stp = true },
		TP = { Tp = true },
		OCO = { Stp = true, Tp = true },
		TRL = { Trl = true },
	}
	local fields = allowed[o.Type] or {}
	local new: { [string]: number } = {}
	local any = false
	for key, value in pairs(changes) do
		if not fields[key] then
			return fail("trade.invalid")
		end
		if key == "Trl" then
			local bounds = trading().TrailBps or {}
			if not isInt(value) or value < num(bounds.Min, 50) or value > num(bounds.Max, 2000) then
				return fail("trade.invalid")
			end
			new.Trl = value
		else
			local px = math.floor(value + 0.5)
			if px < 1 or not inBand(px, mid) then
				return fail("trade.fatFinger")
			end
			new[key] = px
		end
		any = true
	end
	if not any then
		return fail("trade.invalid")
	end
	local stp = new.Stp or o.Stp
	local tp = new.Tp or o.Tp
	if o.Side == "S" then
		if (o.Type == "STP" or o.Type == "OCO") and stp >= bid then
			return fail("trade.stopAbove")
		end
		if (o.Type == "TP" or o.Type == "OCO") and tp <= bid then
			return fail("trade.targetBelow")
		end
	elseif o.Type == "STP" and stp <= ask then
		return fail("trade.buyStopBelow")
	end
	if o.Side == "B" then
		local cfg = trading()
		local refPx = if o.Type == "LMT"
			then new.Lim or o.Lim
			else math.ceil((new.Stp or o.Stp) * num(cfg.BuyStopReserve, 1.05))
		local res = PortfolioMath.BuyCost(o.Q, refPx, env.Licence.FeeBps, minFee())
		-- freies Geld zählt die alte Reservierung dieser Order schon mit
		if math.floor(num(d.Cash, 0)) - Portfolio.Reserved(d, o) < res then
			return fail("trade.noCash")
		end
		o.Res = res
		if o.Type == "LMT" then
			o.Lim = new.Lim or o.Lim
			if o.Stp and o.Tp then
				o.Stp, o.Tp = protectLevels(o.Lim)
			end
		else
			o.Stp = new.Stp or o.Stp
		end
	else
		for key, value in pairs(new) do
			o[key] = value
		end
		if o.Type == "TRL" then
			o.Peak = math.max(o.Peak or bid, bid)
		end
	end
	o.T0 = t -- geänderte Orders gelten ab dem nächsten Tick (kein Blick zurück)
	return { Ok = true, OrderId = o.Id }
end

-- ---------------------------------------------------------------------
-- 9) TRIGGER JE 1s-KERZE (MARKET §11.3) inkl. Pfad-Regel und Nachzieh-Stopp ohne Zukunftsblick
-- ---------------------------------------------------------------------
local function trailStop(o: Order): number
	return math.floor(num(o.Peak, 0) * (1 - num(o.Trl, 0) / 10000))
end

-- Gibt (ausgelöst, Preis, Art, Lücke) für eine Order in der Kerze (o, h, l, c) zurück
local function evaluate(
	ord: Order,
	op: number,
	h: number,
	l: number,
	c: number,
	hs: number
): (boolean, number, string, boolean)
	local t = ord.Type
	if ord.Side == "B" then
		if t == "LMT" then
			if l + hs <= ord.Lim then
				return true, math.min(ord.Lim, op + hs), "Limit", false
			end
		elseif t == "STP" then
			if h + hs >= ord.Stp then
				local px = math.max(ord.Stp, op + hs)
				return true, px, "BuyStop", px > ord.Stp
			end
		end
		return false, 0, "", false
	end
	if t == "LMT" then
		if h - hs >= ord.Lim then
			return true, math.max(ord.Lim, op - hs), "Limit", false
		end
	elseif t == "TP" then
		if h - hs >= ord.Tp then
			return true, math.max(ord.Tp, op - hs), "Target", false
		end
	elseif t == "STP" then
		if l - hs <= ord.Stp then
			local px = math.min(ord.Stp, op - hs)
			return true, px, "Stop", px < ord.Stp
		end
	elseif t == "TRL" then
		local stop = trailStop(ord)
		if stop > 0 and l - hs <= stop then
			local px = math.min(stop, op - hs)
			return true, px, "Trail", px < stop
		end
	elseif t == "OCO" then
		local slHit = l - hs <= ord.Stp
		local tpHit = h - hs >= ord.Tp
		local stopFirst: boolean
		if op - hs <= ord.Stp then
			stopFirst = true -- Lücke unter den Stopp schon zur Eröffnung
		elseif op - hs >= ord.Tp then
			stopFirst = false -- Lücke über das Ziel zur Eröffnung
		elseif slHit and tpHit then
			stopFirst = c >= op -- steigend O→L→H→C (Tief zuerst), fallend O→H→L→C (Hoch zuerst)
		else
			stopFirst = slHit
		end
		if slHit and stopFirst then
			local px = math.min(ord.Stp, op - hs)
			return true, px, "OcoStop", px < ord.Stp
		elseif tpHit then
			return true, math.max(ord.Tp, op - hs), "OcoTarget", false
		end
	end
	return false, 0, "", false
end

local function executeOrder(d: Depot, env: Env, t: number, ord: Order, px: number, kind: string, gap: boolean)
	local i = ord.I
	local bps = env.Licence.FeeBps
	px = math.clamp(math.floor(px), 1, MAX_PRICE)
	if ord.Side == "B" then
		local nav = OrderEngine.NavAt(d, env, t)
		local bid = OrderEngine.EngineQuote(env, i, t)
		local qty = ord.Q
		local flags = if ord.Stp and ord.Tp and ord.Type == "LMT" then Portfolio.FLAG_PROTECTED else 0
		-- "Gut gelesen"-Kandidat auch für Wunschpreis-/Kauf-Stopp-Käufe des Spielers (nie für Bots)
		if ord.Bot == nil and qty * px >= num(trading().MinTradePct, 0.02) * nav then
			local dir = env.FactDir(i, t)
			if type(dir) == "number" and dir > 0 then
				flags = bit32.bor(flags, Portfolio.FLAG_READWELL)
			end
		end
		local opts = {
			Tick = t,
			Flags = flags,
			Nav = nav,
			MaxWeight = OrderEngine.MaxWeightFor(env, i),
			PosCap = OrderEngine.PosCap(env, i),
			Bid = bid,
		}
		local ok, info = Portfolio.Buy(d, i, qty, px, bps, ord, opts)
		if not ok and info == "trade.noCash" then
			-- Kurslücke beim Kauf-Stopp: auf das Bezahlbare kürzen und melden (MARKET §12.3)
			local free = math.floor(num(d.Cash, 0)) - Portfolio.Reserved(d, ord)
			local cut = PortfolioMath.AffordableQty(free, px, bps, minFee())
			if cut >= 1 then
				ok, info = Portfolio.Buy(d, i, cut, px, bps, ord, opts)
				if ok then
					env.Emit("Cut", { OrderId = ord.Id, I = i, Q = cut, Bot = ord.Bot })
				end
			end
		end
		removeOrder(d, ord)
		if not ok then
			env.Emit("Cancelled", { OrderId = ord.Id, I = i, Reason = info, Bot = ord.Bot })
			return
		end
		info.Protected = bit32.band(flags, Portfolio.FLAG_PROTECTED) ~= 0
		emitFill(d, env, t, i, "B", info, nav, ord.Bot, kind, ord, gap)
		if ord.Type == "LMT" and ord.Stp and ord.Tp then
			attachProtection(d, t, i, info.Q, ord.Stp, ord.Tp, ord.Bot)
		end
		return
	end
	local nav = OrderEngine.NavAt(d, env, t)
	local ok, info = Portfolio.Sell(d, i, ord.Q, px, bps, ord, { Tick = t })
	removeOrder(d, ord)
	if not ok then
		env.Emit("Cancelled", { OrderId = ord.Id, I = i, Reason = info, Bot = ord.Bot })
		return
	end
	emitFill(d, env, t, i, "S", info, nav, ord.Bot, kind, ord, gap)
end

-- Alle Orders eines Werts gegen die Kerze von Tick t (nur Orders mit T0 < t)
function OrderEngine.CheckInstrument(
	d: Depot,
	env: Env,
	i: number,
	t: number,
	o: number,
	h: number,
	l: number,
	c: number
)
	if #d.Orders == 0 then
		return
	end
	local hs = OrderEngine.HalfSpread(env, i, t)
	-- Schnappschuss (Ausführungen ändern die Liste)
	local list: { Order } = {}
	for _, ord in ipairs(d.Orders) do
		if ord.I == i and ord.T0 < t then
			table.insert(list, ord)
		end
	end
	for _, ord in ipairs(list) do
		if not findOrder(d, ord.Id) then
			continue -- inzwischen ausgeführt/storniert
		end
		local hit, px, kind, gap = evaluate(ord, o, h, l, c, hs)
		if hit then
			executeOrder(d, env, t, ord, px, kind, gap)
		elseif ord.Type == "TRL" then
			-- Nachführung NACH der Prüfung mit dem Hoch dieser Kerze (kein Blick in die Zukunft)
			ord.Peak = math.max(num(ord.Peak, 0), h - hs)
		end
	end
end

-- Kann in einer Minute (Hoch hMax, Tief lMin, ein hs je Minute) irgendeine Order/ein Alarm des Werts auslösen?
-- Exakte Bedingung: Trigger sind monoton in H bzw. L -> nein heißt sicher kein Trigger (Minute überspringbar).
function OrderEngine.CanTrigger(d: Depot, i: number, hMax: number, lMin: number, hs: number): boolean
	for _, ord in ipairs(d.Orders) do
		if ord.I == i then
			local t = ord.Type
			if ord.Side == "B" then
				if t == "LMT" and lMin + hs <= ord.Lim then
					return true
				elseif t == "STP" and hMax + hs >= ord.Stp then
					return true
				end
			elseif (t == "LMT" and hMax - hs >= ord.Lim) or (t == "TP" and hMax - hs >= ord.Tp) then
				return true
			elseif t == "STP" and lMin - hs <= ord.Stp then
				return true
			elseif t == "OCO" and (lMin - hs <= ord.Stp or hMax - hs >= ord.Tp) then
				return true
			elseif t == "TRL" then
				-- der Stopp kann innerhalb der Minute höchstens bis zum Minuten-Hoch nachziehen
				local peak = math.max(num(ord.Peak, 0), hMax - hs)
				local stop = math.floor(peak * (1 - num(ord.Trl, 0) / 10000))
				if lMin - hs <= stop then
					return true
				end
			end
		end
	end
	for _, a in ipairs(d.Alerts) do
		if a.I == i and ((a.Dir == "Up" and hMax >= a.Px) or (a.Dir == "Down" and lMin <= a.Px)) then
			return true
		end
	end
	return false
end

-- Nachzieh-Stopps einer übersprungenen Minute nachführen (identisch zu 60 Einzel-Kerzen ohne Auslösung)
function OrderEngine.SkipMinute(d: Depot, i: number, hMax: number, hs: number)
	for _, ord in ipairs(d.Orders) do
		if ord.I == i and ord.Type == "TRL" then
			ord.Peak = math.max(num(ord.Peak, 0), hMax - hs)
		end
	end
end

-- ---------------------------------------------------------------------
-- 10) ALARME, ABLAUF, DIVIDENDEN
-- ---------------------------------------------------------------------
function OrderEngine.CheckAlerts(d: Depot, env: Env, i: number, t: number, h: number, l: number)
	for index = #d.Alerts, 1, -1 do
		local a = d.Alerts[index]
		if a.I == i and ((a.Dir == "Up" and h >= a.Px) or (a.Dir == "Down" and l <= a.Px)) then
			table.remove(d.Alerts, index)
			env.Emit("Alert", { Id = a.Id, I = i, Px = a.Px, Dir = a.Dir, Tick = t })
		end
	end
end

function OrderEngine.Expire(d: Depot, env: Env, t: number)
	for index = #d.Orders, 1, -1 do
		local o = d.Orders[index]
		if o.Exp <= t then
			table.remove(d.Orders, index)
			env.Emit("Expired", { OrderId = o.Id, I = o.I, Bot = o.Bot })
		end
	end
end

-- Dividenden: Anspruch = Bestand im Ex-Tick (nach den Triggern dieses Ticks); Betrag je Aktie in Cent
function OrderEngine.PayDividends(d: Depot, env: Env, t: number, list: { { [string]: number } }?)
	if type(list) ~= "table" then
		return
	end
	for _, div in ipairs(list) do
		if type(div) == "table" and div.Tick == t and isInt(div.I) and isInt(div.Cents) and div.Cents > 0 then
			local qty = Portfolio.PosQty(d, div.I)
			if qty > 0 then
				local amount = qty * div.Cents
				if Portfolio.Credit(d, amount, "Dividend") then
					Portfolio.MarkActive(d)
					env.Emit("Dividend", { I = div.I, Cents = amount, Tick = t })
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- 11) BÖRSENTAG-SCHLUSS (Glocke bei t % 1200 == 0): Bot-Lohn, Tagesrendite, Liga, neuer Tag, Auto-Transfer
-- ---------------------------------------------------------------------
local function hasExposure(d: Depot): boolean
	if next(d.Pos) ~= nil then
		return true
	end
	local tut = d.Tutorial
	return type(tut) == "table" and num(tut.Q, 0) > 0
end

function OrderEngine.CloseDay(d: Depot, env: Env, t: number)
	local cfg = trading()
	local closedDay = t // DAY - 1
	local dayStart, dayEnd = closedDay * DAY, t - 1
	-- 1) Bot-Lohn gehört zum abgelaufenen Tag
	if bots and type(bots.PayWages) == "function" then
		bots.PayWages(d, env, dayEnd)
	end
	-- 2) Tagesrendite (Modified Dietz) des abgelaufenen Tags
	local navEnd = OrderEngine.NavAt(d, env, dayEnd)
	local rec = Portfolio.CurrentDay(d)
	local result: Types.DayResult = { Day = closedDay, Return = 0, Trades = 0, Qualifying = false, Tainted = false }
	local complete = false
	if rec then
		rec[3] = navEnd
		complete = rec[1] == closedDay
		local tainted = env.AdminBetween(dayStart, dayEnd) or env.OwnerTaint
		local counted = complete and rec[6] == 1 and rec[2] >= num(cfg.MinNavStart, 100000)
		local r = if counted then PortfolioMath.DayReturn(rec[2], navEnd, rec[4]) else 0
		local qualifying = counted and rec[5] >= num(cfg.QualifyingTrades, 3)
		result = {
			Day = closedDay,
			Return = math.floor(r * 1e6 + 0.5) / 1e6,
			Trades = rec[5],
			Qualifying = qualifying and not tainted,
			Tainted = tainted,
		}
		local league = leagueFor(env, dayEnd)
		if league and counted and not tainted then
			Portfolio.LeagueAddDay(league, r, qualifying)
		end
		local stats = d.Stats
		if type(stats) == "table" then
			local peak = math.max(math.floor(num(stats.PeakNav, 0)), navEnd)
			stats.PeakNav = peak
			if peak > 0 then
				stats.MaxDD = math.max(num(stats.MaxDD, 0), math.floor((peak - navEnd) / peak * 10000 + 0.5) / 10000)
			end
		end
	end
	-- 3) neuer Börsentag startet mit dem Schluss-Depotwert
	Portfolio.OpenDay(d, closedDay + 1, navEnd, hasExposure(d))
	-- 4) Auto-Transfer an der Glocke für den gerade beendeten Tag (nur ohne Transfer in diesem Tag).
	--    Der Betrag verlässt das Depot sofort (Fluss F des neuen Tags) und wartet in d.Pending, bis der Turm ihn
	--    über OrderService.Withdraw abholt – der Markt-Code bucht nie Turm-Geld.
	if
		d.AutoTransfer ~= false
		and env.NoAutoTransfer ~= true
		and math.floor(num(d.LastTransferDay, -1)) < closedDay
	then
		local amount = OrderEngine.TransferAmount(d, env, navEnd)
		if amount > 0 and Portfolio.Debit(d, amount, "Transfer") then
			d.Pending = math.floor(num(d.Pending, 0)) + amount
			d.LastTransferDay = closedDay
			env.Emit("Transfer", { Cents = amount, Day = closedDay })
			-- Tagesbilanz zeigt "Auto-Transfer: … in den Tower" (DayClose.Transfer, AKY-Cent)
			local withTransfer: any = result
			withTransfer.Transfer = amount
		end
	end
	if complete then
		env.Emit("DayResult", result)
	end
	env.Emit("Bell", { Day = closedDay + 1 })
end

-- ---------------------------------------------------------------------
-- 12) EIN TICK (gemeinsam online/offline)
-- ---------------------------------------------------------------------
function OrderEngine.Step(d: Depot, env: Env, t: number, ctx: { [string]: any })
	if t % DAY == 0 then
		OrderEngine.CloseDay(d, env, t)
	end
	if #d.Orders > 0 then
		OrderEngine.Expire(d, env, t)
	end
	if #d.Orders > 0 or #d.Alerts > 0 then
		local candleOf = ctx.Candle
		for _, i in ipairs(OrderEngine.ActiveInstruments(d)) do
			local o, h, l, c = candleOf(i)
			if type(o) == "number" and type(h) == "number" and type(l) == "number" and type(c) == "number" then
				if #d.Orders > 0 and not env.Halted(i, t) then
					OrderEngine.CheckInstrument(d, env, i, t, o, h, l, c)
				end
				if #d.Alerts > 0 then
					OrderEngine.CheckAlerts(d, env, i, t, h, l)
				end
			end
		end
	end
	if ctx.Divs ~= nil and next(d.Pos) ~= nil then
		OrderEngine.PayDividends(d, env, t, ctx.Divs)
	end
	if t % 60 == 0 and bots and type(bots.Decide) == "function" and type(d.Bots) == "table" and #d.Bots > 0 then
		if ctx.NoBots ~= true then
			bots.Decide(d, env, t)
		end
	end
	d.LastTick = t
end

return OrderEngine
