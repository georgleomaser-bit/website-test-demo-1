-- =====================================================================
--  AKYTEX TYCOON – Depot-Buchhaltung: der EINZIGE Schreibtrichter für Cash und Basis (Server/Market/Portfolio)
--  Besitzer: WP4 (Orders, Depot, Bots). Vertrag: DESIGN.md §C11.4 #3 (Depot-Schreibtrichter), §B8.1, §C12.1,
--  MARKET.md §12.1–§12.6. Reines Daten-Modul (keine Remotes, keine Services, kein Yield) – wird von OrderService,
--  OrderEngine, BotEngine und CatchUp benutzt.
--
--  Firewall: Depot.Cash und Depot.Basis ändern sich NUR über Portfolio.Credit/Debit mit einem Grund aus der
--  Whitelist (Start, Licence, Refill, Trade, Fee, Dividend, BotWage, Transfer, Admin, Tutorial, Migration).
--  Es gibt keine Funktion, die Turm-Geld in das Depot bringt.
--
--  Öffentliche API:
--    Portfolio.Credit(d, cents, reason): boolean       Gutschrift (Licence/Admin/Start erhöhen auch die Basis)
--    Portfolio.Debit(d, cents, reason): boolean        Abbuchung, nie unter 0 (Licence-Herabstufung: Cash höchstens bis 0)
--    Portfolio.Reserved(d, except?): number            Summe Res offener Kauf-Orders (ohne except)
--    Portfolio.ReservedQty(d, inst, except?): number   reservierte Stück offener Verkaufs-Orders eines Werts
--    Portfolio.Free(d): number                         Cash − Reserved
--    Portfolio.Buy(d, inst, qty, ask, bps, fromOrder?, opts?): (boolean, info | reasonKey)
--    Portfolio.Sell(d, inst, qty, bid, bps, fromOrder?, opts?): (boolean, info | reasonKey)
--    Portfolio.Nav(d, bidOf): number                   Cash + Σ Q · bidOf(inst) (fehlt ein Kurs: Einstand)
--    Portfolio.PosQty(d, inst) · PosValue(d, inst, bid)
--    Portfolio.OpenDay(d, day, nav, active) · CurrentDay(d) · MarkActive(d) · AddCountingTrade(d)
--    Portfolio.PushFill(d, tick, inst, side, qty, px, fee, pnl, bot)
--    Portfolio.NoteSell(d, pnl, basis)                 Depot-Statistik (Trades, Wins, Losses, BestPct …)
--    Portfolio.Sanitize(d, nowTick, isValidInst): { string }   Spielstand reparieren (nach DataService-Reconcile)
--    Portfolio.LeagueRoll(league, week) · LeagueAddDay(league, r, qualifying) · LeagueAddTrade(league)
--    Portfolio.LeagueStats(league, extraTaint): Types.LeagueStats · Portfolio.TierOf(score, qualified): string
--    Portfolio.SetObserver(fn(d, signedCents, reason))  Metriken (OrderService) – wird nie im Trichter selbst ausgewertet
--    Portfolio.REASONS · Portfolio.FLOW_REASONS
--  Positionen tragen zusätzlich T (Eröffnungs-Tick) und F (Bits: 1 = mit Schutz eröffnet, 2 = "Gut gelesen"-Kandidat).
--  Nav-Ring je Börsentag: { day, navStart, navEnd, flow, zählendeTrades, aktiv(0/1) }; Fills: { tick, inst, side
--  (1 = Kauf, 2 = Verkauf), qty, px, fee, pnl, bot(0/1) }.
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))
local PortfolioMath = require(Shared:WaitForChild("Market"):WaitForChild("PortfolioMath"))

local Portfolio = {}

type Depot = { [string]: any }

local MAX_MONEY = 9e15
local FILLS_MAX = 100
local NAV_MAX = 72
local SEQ_MAX = 64
local ORDERS_MAX = 50
local ALERTS_MAX = 18
local BOTS_MAX = 5
local WATCH_LISTS_MAX = 5
local WATCH_IDS_MAX = 12
local INST_MAX = 255

Portfolio.FLAG_PROTECTED = 1
Portfolio.FLAG_READWELL = 2

Portfolio.REASONS = {
	Start = true,
	Licence = true,
	Refill = true,
	Trade = true,
	Fee = true,
	Dividend = true,
	BotWage = true,
	Transfer = true,
	Admin = true,
	Tutorial = true,
	Migration = true,
}
-- Gründe, die auch die Basis (Hochwassermarke) bewegen: Lizenz-Aufstieg, Admin-Gabe (nie abhebbar), Neustart
local BASIS_REASONS = { Start = true, Licence = true, Admin = true }
-- Gründe, die in der Börsentag-Rendite als Fluss F zählen (keine Handelsleistung)
Portfolio.FLOW_REASONS = {
	Start = true,
	Licence = true,
	Refill = true,
	Transfer = true,
	Admin = true,
	Tutorial = true,
	Migration = true,
}

local observer: ((Depot, number, string) -> ())? = nil

local function trading(): { [string]: any }
	local t = Config.Trading
	return if type(t) == "table" then t else {}
end

local function minFee(): number
	local v = trading().MinFeeCents
	return if type(v) == "number" and v >= 0 then v else PortfolioMath.MIN_FEE
end

local function isInt(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and v % 1 == 0
end

local function int(v: any, fallback: number): number
	if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then
		return math.floor(v)
	end
	return fallback
end

function Portfolio.SetObserver(fn: ((Depot, number, string) -> ())?)
	observer = fn
end

local function notify(d: Depot, signed: number, reason: string)
	local fn = observer
	if fn then
		local ok, err = pcall(fn, d, signed, reason)
		if not ok then
			warn("[Portfolio] Beobachter-Fehler: " .. tostring(err))
		end
	end
end

-- ---------------------------------------------------------------------
-- 1) BÖRSENTAG-AUFZEICHNUNG (Nav-Ring; Fluss F für Modified Dietz)
-- ---------------------------------------------------------------------
function Portfolio.CurrentDay(d: Depot): { number }?
	local nav = d.Nav
	if type(nav) ~= "table" then
		return nil
	end
	local rec = nav[#nav]
	return if type(rec) == "table" then rec else nil
end

local function addFlow(d: Depot, signed: number)
	local rec = Portfolio.CurrentDay(d)
	if rec then
		rec[4] = (rec[4] or 0) + signed
	end
end

-- Öffnet (oder liefert) den Datensatz des Börsentags "day". navStart = nav.
function Portfolio.OpenDay(d: Depot, day: number, nav: number, active: boolean?): { number }
	if type(d.Nav) ~= "table" then
		d.Nav = {}
	end
	local current = Portfolio.CurrentDay(d)
	if current and current[1] == day then
		return current
	end
	local rec = { day, nav, nav, 0, 0, if active then 1 else 0 }
	table.insert(d.Nav, rec)
	while #d.Nav > NAV_MAX do
		table.remove(d.Nav, 1)
	end
	return rec
end

function Portfolio.MarkActive(d: Depot)
	local rec = Portfolio.CurrentDay(d)
	if rec then
		rec[6] = 1
	end
end

function Portfolio.AddCountingTrade(d: Depot)
	local rec = Portfolio.CurrentDay(d)
	if rec then
		rec[5] = (rec[5] or 0) + 1
	end
end

-- ---------------------------------------------------------------------
-- 2) DER TRICHTER: Credit / Debit
-- ---------------------------------------------------------------------
function Portfolio.Credit(d: Depot, cents: number, reason: string): boolean
	if type(d) ~= "table" or not Portfolio.REASONS[reason] or not isInt(cents) or cents < 0 then
		return false
	end
	if cents == 0 then
		return true
	end
	local cash = int(d.Cash, 0)
	local amount = math.min(cents, math.max(0, MAX_MONEY - cash)) -- nie über MAX (9e15 < 2^53)
	d.Cash = cash + amount
	if BASIS_REASONS[reason] then
		d.Basis = math.min(MAX_MONEY, int(d.Basis, 0) + amount)
	end
	if Portfolio.FLOW_REASONS[reason] then
		addFlow(d, amount)
	end
	notify(d, amount, reason)
	return true
end

function Portfolio.Debit(d: Depot, cents: number, reason: string): boolean
	if type(d) ~= "table" or not Portfolio.REASONS[reason] or not isInt(cents) or cents < 0 then
		return false
	end
	if cents == 0 then
		return true
	end
	local cash = int(d.Cash, 0)
	if reason == "Licence" then
		-- Lizenz-Herabstufung (nur Admin): Basis sinkt voll, Cash höchstens bis 0 (nie negativ)
		local take = math.min(cash, cents)
		d.Cash = cash - take
		d.Basis = math.max(0, int(d.Basis, 0) - cents)
		addFlow(d, -take)
		notify(d, -take, reason)
		return true
	end
	if cash < cents then
		return false
	end
	d.Cash = cash - cents
	if BASIS_REASONS[reason] then
		d.Basis = math.max(0, int(d.Basis, 0) - cents)
	end
	if Portfolio.FLOW_REASONS[reason] then
		addFlow(d, -cents)
	end
	notify(d, -cents, reason)
	return true
end

-- ---------------------------------------------------------------------
-- 3) RESERVIERUNGEN (MARKET §12.3; Schutz-Paar = ein Datensatz, zählt einmal)
-- ---------------------------------------------------------------------
local function isExcept(o: any, except: any): boolean
	if except == nil then
		return false
	end
	if o == except then
		return true
	end
	return type(except) == "number" and o.Id == except
end

function Portfolio.Reserved(d: Depot, except: any?): number
	local sum = 0
	if type(d.Orders) == "table" then
		for _, o in ipairs(d.Orders) do
			if o.Side == "B" and not isExcept(o, except) then
				sum += int(o.Res, 0)
			end
		end
	end
	return sum
end

function Portfolio.ReservedQty(d: Depot, inst: number, except: any?): number
	local sum = 0
	if type(d.Orders) == "table" then
		for _, o in ipairs(d.Orders) do
			if o.Side == "S" and o.I == inst and not isExcept(o, except) then
				sum += int(o.Q, 0)
			end
		end
	end
	return sum
end

function Portfolio.Free(d: Depot): number
	return math.max(0, int(d.Cash, 0) - Portfolio.Reserved(d))
end

function Portfolio.PosQty(d: Depot, inst: number): number
	local p = type(d.Pos) == "table" and d.Pos[tostring(inst)] or nil
	return if type(p) == "table" then int(p.Q, 0) else 0
end

function Portfolio.PosValue(d: Depot, inst: number, bid: number?): number
	local p = type(d.Pos) == "table" and d.Pos[tostring(inst)] or nil
	if type(p) ~= "table" then
		return 0
	end
	if type(bid) == "number" and bid > 0 then
		return int(p.Q, 0) * math.floor(bid)
	end
	return math.max(0, int(p.C, 0))
end

-- ---------------------------------------------------------------------
-- 4) KAUFEN / VERKAUFEN (ohne Yield zwischen Prüfung und Buchung)
--    opts: { Tick, Flags, Nav, MaxWeight?, PosCap?, Bid? }  (MaxWeight nil = ETF, von der Klumpen-Grenze ausgenommen)
-- ---------------------------------------------------------------------
function Portfolio.Buy(
	d: Depot,
	inst: number,
	qty: number,
	ask: number,
	bps: number,
	fromOrder: any?,
	opts: { [string]: any }?
): (boolean, any)
	if not isInt(qty) or qty <= 0 or not isInt(ask) or ask <= 0 then
		return false, "trade.invalid"
	end
	local gross = qty * ask
	if gross >= PortfolioMath.MAX_SAFE / 2 then
		return false, "trade.posLimit"
	end
	local fee = PortfolioMath.Fee(gross, bps, minFee())
	local total = gross + fee
	local available = int(d.Cash, 0) - Portfolio.Reserved(d, fromOrder)
	if available < total then
		return false, "trade.noCash"
	end
	local o = opts or {}
	local key = tostring(inst)
	local p = d.Pos[key]
	if o.MaxWeight ~= nil and type(o.Nav) == "number" then
		local posValue = Portfolio.PosValue(d, inst, o.Bid)
		if PortfolioMath.Weight(posValue, gross, o.Nav) > o.MaxWeight + 1e-9 then
			return false, "trade.concentration"
		end
	end
	if type(o.PosCap) == "number" then
		local have = if type(p) == "table" then int(p.Q, 0) else 0
		if (have + qty) * ask > o.PosCap then
			return false, "trade.posLimit"
		end
	end
	-- Buchung: Brutto + Gebühr über den Trichter
	Portfolio.Debit(d, gross, "Trade")
	Portfolio.Debit(d, fee, "Fee")
	local tick = int(o.Tick, 0)
	local flags = int(o.Flags, 0)
	if type(p) ~= "table" or int(p.Q, 0) <= 0 then
		p = { Q = 0, C = 0, R = if type(p) == "table" then int(p.R, 0) else 0, T = tick, F = flags }
	else
		p.F = bit32.bor(int(p.F, 0), flags)
		if not isInt(p.T) then
			p.T = tick
		elseif tick > p.T then
			-- Nachkauf: Eröffnungs-Tick mengengewichtet nachziehen. Sonst zählt "1 Stück 60 s halten, dann groß
			-- nachkaufen und sofort verkaufen" als ≥ 60 s gehalten (Liga-/XP-Trade, "Gut gelesen").
			local have = int(p.Q, 0)
			p.T = p.T + math.floor((tick - p.T) * qty / (have + qty))
		end
	end
	p.Q += qty
	p.C += total -- Einstand inkl. Gebühr
	d.Pos[key] = p
	Portfolio.MarkActive(d)
	return true, { Px = ask, Q = qty, Fee = fee, Gross = gross, Total = total }
end

function Portfolio.Sell(
	d: Depot,
	inst: number,
	qty: number,
	bid: number,
	bps: number,
	fromOrder: any?,
	opts: { [string]: any }?
): (boolean, any)
	if not isInt(qty) or qty <= 0 or not isInt(bid) or bid <= 0 then
		return false, "trade.invalid"
	end
	local key = tostring(inst)
	local p = d.Pos[key]
	if type(p) ~= "table" or int(p.Q, 0) - Portfolio.ReservedQty(d, inst, fromOrder) < qty then
		return false, "trade.noShares"
	end
	local gross = qty * bid
	local fee = math.min(gross, PortfolioMath.Fee(gross, bps, minFee()))
	local net = gross - fee
	local basis = PortfolioMath.Basis(p, qty)
	local tick = int(opts and opts.Tick, 0)
	local held = if isInt(p.T) then math.max(0, tick - p.T) else 0
	local flags = int(p.F, 0)
	p.Q -= qty
	p.C -= basis
	p.R = int(p.R, 0) + (net - basis)
	Portfolio.Credit(d, gross, "Trade")
	Portfolio.Debit(d, fee, "Fee")
	if p.Q <= 0 then
		d.Pos[key] = nil
	end
	Portfolio.MarkActive(d)
	return true,
		{
			Px = bid,
			Q = qty,
			Fee = fee,
			Gross = gross,
			Net = net,
			Basis = basis,
			Pnl = net - basis,
			HeldS = held,
			Flags = flags,
		}
end

-- ---------------------------------------------------------------------
-- 5) DEPOTWERT
-- ---------------------------------------------------------------------
function Portfolio.Nav(d: Depot, bidOf: (number) -> number?): number
	local nav = int(d.Cash, 0)
	if type(d.Pos) ~= "table" then
		return nav
	end
	for key, p in pairs(d.Pos) do
		local qty = if type(p) == "table" then int(p.Q, 0) else 0
		if qty > 0 then
			local id = tonumber(key)
			local bid = if id then bidOf(id) else nil
			if type(bid) == "number" and bid > 0 then
				nav += qty * math.floor(bid)
			else
				nav += math.max(0, int(p.C, 0))
			end
		end
	end
	return math.min(nav, MAX_MONEY)
end

-- ---------------------------------------------------------------------
-- 6) VERLAUF & STATISTIK
-- ---------------------------------------------------------------------
function Portfolio.PushFill(
	d: Depot,
	tick: number,
	inst: number,
	side: string,
	qty: number,
	px: number,
	fee: number,
	pnl: number,
	bot: boolean
)
	if type(d.Fills) ~= "table" then
		d.Fills = {}
	end
	table.insert(d.Fills, { tick, inst, if side == "B" then 1 else 2, qty, px, fee, pnl, if bot then 1 else 0 })
	while #d.Fills > FILLS_MAX do
		table.remove(d.Fills, 1)
	end
end

function Portfolio.NoteSell(d: Depot, pnl: number, basis: number)
	local s = d.Stats
	if type(s) ~= "table" then
		return
	end
	s.Trades = int(s.Trades, 0) + 1
	if pnl > 0 then
		s.Wins = int(s.Wins, 0) + 1
		s.GrossWin = int(s.GrossWin, 0) + pnl
	elseif pnl < 0 then
		s.Losses = int(s.Losses, 0) + 1
		s.GrossLoss = int(s.GrossLoss, 0) - pnl
	end
	if basis > 0 then
		local pct = pnl / basis
		if pct > (tonumber(s.BestPct) or 0) then
			s.BestPct = math.floor(pct * 10000 + 0.5) / 10000
		end
	end
end

-- ---------------------------------------------------------------------
-- 7) LIGA (Wochen-Daten in PlayerData.League; MARKET §12.6 mit §C19 Nr. 7)
-- ---------------------------------------------------------------------
local function leagueCfg(): { [string]: any }
	local l = trading().League
	return if type(l) == "table" then l else {}
end

function Portfolio.TierOf(score: number, qualified: boolean): string
	if not qualified then
		return "None"
	end
	local tier = "None"
	local tiers = leagueCfg().Tiers
	if type(tiers) == "table" then
		for _, entry in ipairs(tiers) do
			if type(entry) == "table" and type(entry.Min) == "number" and score >= entry.Min then
				tier = entry.Key
			end
		end
	end
	return tier
end

-- Woche wechseln: alte Woche als "Last*" merken (für die Liga-Belohnung der Folgewoche, WP9), dann leeren
function Portfolio.LeagueRoll(league: { [string]: any }, week: number)
	if type(league) ~= "table" or not isInt(week) then
		return
	end
	if league.Week == week then
		return
	end
	if isInt(league.Week) and league.Week > 0 then
		local stats = Portfolio.LeagueStats(league, false)
		league.LastWeek = league.Week
		league.LastScore = stats.SkillScore
		league.LastAvgBp = stats.AvgDailyBp
		league.LastQualified = stats.Qualified
		league.LastTier = Portfolio.TierOf(stats.SkillScore, stats.Qualified)
	end
	league.Week = week
	league.Returns = {}
	league.Trades = 0
	league.Days = 0
	league.Tainted = false
end

function Portfolio.LeagueAddDay(league: { [string]: any }, r: number, qualifying: boolean)
	if type(league) ~= "table" or type(r) ~= "number" or r ~= r then
		return
	end
	if type(league.Returns) ~= "table" then
		league.Returns = {}
	end
	table.insert(league.Returns, math.floor(r * 1e8 + 0.5) / 1e8)
	local maxReturns = int(leagueCfg().MaxReturns, 504)
	while #league.Returns > maxReturns do
		table.remove(league.Returns, 1)
	end
	if qualifying then
		league.Days = int(league.Days, 0) + 1
	end
end

function Portfolio.LeagueAddTrade(league: { [string]: any })
	if type(league) == "table" then
		league.Trades = int(league.Trades, 0) + 1
	end
end

function Portfolio.LeagueStats(league: { [string]: any }, extraTaint: boolean): Types.LeagueStats
	local returns = if type(league) == "table" and type(league.Returns) == "table" then league.Returns else {}
	local trades = int(type(league) == "table" and league.Trades, 0)
	local days = int(type(league) == "table" and league.Days, 0)
	local tainted = (type(league) == "table" and league.Tainted == true) or extraTaint == true
	local maxDD = PortfolioMath.MaxDrawdown(returns)
	local score = PortfolioMath.SkillScore(returns, maxDD)
	local avg = PortfolioMath.AvgDaily(PortfolioMath.Twr(returns), #returns)
	local cfg = leagueCfg()
	local qualified = not tainted and trades >= int(cfg.MinTrades, 20) and days >= int(cfg.MinDays, 6) and #returns > 0
	return {
		Week = int(type(league) == "table" and league.Week, 0),
		SkillScore = score,
		AvgDailyBp = math.floor(avg * 10000 + 0.5),
		Trades = trades,
		Days = days,
		Tainted = tainted,
		Qualified = qualified,
	}
end

-- ---------------------------------------------------------------------
-- 8) SPIELSTAND REPARIEREN (nach DataService Migrate/Reconcile; nie Geld erfinden)
-- ---------------------------------------------------------------------
local SIDES = { B = true, S = true }
local TYPES = { MKT = true, LMT = true, STP = true, TP = true, OCO = true, TRL = true }

local function cleanPrice(v: any): number?
	if isInt(v) and v > 0 and v < 1e10 then
		return v
	end
	return nil
end

local function cleanOrder(o: any, isValidInst: (number) -> boolean): any?
	if type(o) ~= "table" then
		return nil
	end
	if not isInt(o.Id) or o.Id < 1 or not isInt(o.I) or not isValidInst(o.I) then
		return nil
	end
	if not SIDES[o.Side] or not TYPES[o.Type] or o.Type == "MKT" then
		return nil
	end
	if not isInt(o.Q) or o.Q < 1 or not isInt(o.Exp) or not isInt(o.T0) then
		return nil
	end
	local clean: { [string]: any } = {
		Id = o.Id,
		I = o.I,
		Side = o.Side,
		Type = o.Type,
		Q = o.Q,
		Lim = cleanPrice(o.Lim),
		Stp = cleanPrice(o.Stp),
		Tp = cleanPrice(o.Tp),
		Trl = if isInt(o.Trl) and o.Trl > 0 and o.Trl < 10000 then o.Trl else nil,
		Peak = cleanPrice(o.Peak),
		Oco = if isInt(o.Oco) then o.Oco else nil,
		Res = if o.Side == "B" and isInt(o.Res) and o.Res > 0 then o.Res else 0,
		Exp = o.Exp,
		T0 = o.T0,
		Bot = if isInt(o.Bot) and o.Bot >= 1 and o.Bot <= BOTS_MAX then o.Bot else nil,
	}
	-- Pflichtfelder je Typ
	local t = clean.Type
	if t == "LMT" and clean.Lim == nil then
		return nil
	elseif t == "STP" and clean.Stp == nil then
		return nil
	elseif t == "TP" and clean.Tp == nil then
		return nil
	elseif t == "OCO" and (clean.Stp == nil or clean.Tp == nil or clean.Side ~= "S") then
		return nil
	elseif t == "TRL" and (clean.Trl == nil or clean.Side ~= "S") then
		return nil
	end
	if o.Side == "B" and clean.Res <= 0 then
		return nil -- Kauf-Order ohne Reservierung wäre Geld aus dem Nichts
	end
	return clean
end

function Portfolio.Sanitize(d: Depot, nowTick: number, isValidInst: (number) -> boolean): { string }
	local issues: { string } = {}
	local function note(text: string)
		if #issues < 20 then
			table.insert(issues, text)
		end
	end
	local defaultCash = 2500000
	local cash = int(d.Cash, -1)
	if cash < 0 then
		note("Cash ungültig")
		cash = 0
	end
	d.Cash = math.min(cash, MAX_MONEY)
	local basis = int(d.Basis, -1)
	if basis <= 0 then
		note("Basis ungültig")
		basis = defaultCash
	end
	d.Basis = math.min(basis, MAX_MONEY)
	d.Lic = if isInt(d.Lic) and d.Lic >= 1 and d.Lic <= 10 then d.Lic else 1
	d.Pending = math.max(0, int(d.Pending, 0))

	-- Positionen: Schlüssel = tostring(gültige Id), Q > 0 ganzzahlig
	local pos: { [string]: any } = {}
	if type(d.Pos) == "table" then
		for key, p in pairs(d.Pos) do
			local id = tonumber(key)
			if
				id
				and isInt(id)
				and id >= 1
				and id <= INST_MAX
				and isValidInst(id)
				and type(p) == "table"
				and isInt(p.Q)
				and p.Q > 0
			then
				pos[tostring(id)] = {
					Q = p.Q,
					C = math.max(0, int(p.C, 0)),
					R = int(p.R, 0),
					T = if isInt(p.T) then math.min(p.T, nowTick) else nowTick,
					F = if isInt(p.F) and p.F >= 0 then p.F else 0,
				}
			else
				note("Position " .. tostring(key) .. " entfernt")
			end
		end
	end
	d.Pos = pos
	if type(d.Short) ~= "table" then
		d.Short = {}
	end

	-- Orders
	local orders = {}
	local maxId = 0
	if type(d.Orders) == "table" then
		for _, o in ipairs(d.Orders) do
			local clean = cleanOrder(o, isValidInst)
			if clean and #orders < ORDERS_MAX then
				table.insert(orders, clean)
				maxId = math.max(maxId, clean.Id)
			else
				note("Order entfernt")
			end
		end
	end
	d.Orders = orders

	-- Alarme
	local alerts = {}
	if type(d.Alerts) == "table" then
		for _, a in ipairs(d.Alerts) do
			if
				type(a) == "table"
				and isInt(a.Id)
				and isInt(a.I)
				and isValidInst(a.I)
				and cleanPrice(a.Px)
				and (a.Dir == "Up" or a.Dir == "Down")
				and #alerts < ALERTS_MAX
			then
				table.insert(alerts, { Id = a.Id, I = a.I, Px = a.Px, Dir = a.Dir })
				maxId = math.max(maxId, a.Id)
			end
		end
	end
	d.Alerts = alerts
	d.NextId = math.max(int(d.NextId, 1), maxId + 1)

	-- Watchlisten: 1 … 5 Listen je ≤ 12 gültige, eindeutige Ids
	local watch = {}
	if type(d.Watch) == "table" then
		for _, list in ipairs(d.Watch) do
			if #watch >= WATCH_LISTS_MAX then
				break
			end
			local clean, seen = {}, {}
			if type(list) == "table" then
				for _, id in ipairs(list) do
					if isInt(id) and isValidInst(id) and not seen[id] and #clean < WATCH_IDS_MAX then
						seen[id] = true
						table.insert(clean, id)
					end
				end
			end
			table.insert(watch, clean)
		end
	end
	if #watch == 0 then
		watch = { {} }
	end
	d.Watch = watch

	-- Ringe
	if type(d.Fills) ~= "table" then
		d.Fills = {}
	end
	while #d.Fills > FILLS_MAX do
		table.remove(d.Fills, 1)
	end
	local navs = {}
	if type(d.Nav) == "table" then
		for _, rec in ipairs(d.Nav) do
			if type(rec) == "table" and isInt(rec[1]) and type(rec[2]) == "number" and type(rec[3]) == "number" then
				table.insert(navs, {
					rec[1],
					int(rec[2], 0),
					int(rec[3], 0),
					int(rec[4], 0),
					math.max(0, int(rec[5], 0)),
					if rec[6] == 1 then 1 else 0,
				})
			end
		end
	end
	while #navs > NAV_MAX do
		table.remove(navs, 1)
	end
	d.Nav = navs
	local seq = {}
	if type(d.Seq) == "table" then
		for _, s in ipairs(d.Seq) do
			if isInt(s) then
				table.insert(seq, s)
			end
		end
	end
	while #seq > SEQ_MAX do
		table.remove(seq, 1)
	end
	d.Seq = seq

	-- Bots (Presets prüft BotEngine beim Entscheiden; hier nur Form)
	local bots = {}
	if type(d.Bots) == "table" then
		for _, slot in ipairs(d.Bots) do
			if #bots >= BOTS_MAX then
				break
			end
			if type(slot) == "table" and type(slot.Preset) == "string" then
				local q: { [string]: number } = {}
				if type(slot.Q) == "table" then
					for key, n in pairs(slot.Q) do
						local id = tonumber(key)
						if id and isInt(n) and n > 0 then
							q[tostring(id)] = n
						end
					end
				end
				table.insert(bots, {
					Preset = slot.Preset,
					Pct = if type(slot.Pct) == "number" and slot.Pct == slot.Pct then slot.Pct else 0,
					Target = if isInt(slot.Target) then slot.Target else nil,
					On = slot.On == true,
					Paused = slot.Paused == true,
					DayNav = math.max(0, int(slot.DayNav, 0)),
					DayVal = math.max(0, int(slot.DayVal, 0)),
					DayFlow = int(slot.DayFlow, 0),
					Day = int(slot.Day, -1),
					Last = int(slot.Last, -1),
					Q = q,
				})
			else
				-- leerer Platz (Liste bleibt lückenlos)
				table.insert(bots, {
					Preset = "",
					Pct = 0,
					On = false,
					Paused = false,
					DayNav = 0,
					DayVal = 0,
					DayFlow = 0,
					Day = -1,
					Last = -1,
					Q = {},
				})
			end
		end
	end
	d.Bots = bots

	local stats = if type(d.Stats) == "table" then d.Stats else {}
	for _, key in ipairs({ "Trades", "Wins", "Losses", "GrossWin", "GrossLoss", "PeakNav", "ReadWell" }) do
		stats[key] = math.max(0, int(stats[key], 0))
	end
	stats.MaxDD = if type(stats.MaxDD) == "number" and stats.MaxDD == stats.MaxDD
		then math.clamp(stats.MaxDD, 0, 1)
		else 0
	stats.BestPct = if type(stats.BestPct) == "number" and stats.BestPct == stats.BestPct
		then math.max(0, stats.BestPct)
		else 0
	d.Stats = stats
	local tut = if type(d.Tutorial) == "table" then d.Tutorial else {}
	tut.T0 = math.max(0, int(tut.T0, 0))
	tut.Q = math.max(0, int(tut.Q, 0))
	tut.Done = tut.Done == true
	d.Tutorial = tut
	d.LastTick = math.clamp(int(d.LastTick, 0), 0, math.max(0, nowTick))
	d.LastTransferDay = int(d.LastTransferDay, -1)
	d.LastRefillUtcDay = int(d.LastRefillUtcDay, -1)
	d.AutoTransfer = d.AutoTransfer ~= false
	d.NextId = math.max(1, int(d.NextId, 1))

	-- Invariante Cash ≥ Reservierungen: notfalls jüngste Kauf-Orders streichen (nie Geld erfinden)
	local guard = 0
	while Portfolio.Reserved(d) > d.Cash and guard < ORDERS_MAX do
		guard += 1
		for i = #d.Orders, 1, -1 do
			if d.Orders[i].Side == "B" then
				table.remove(d.Orders, i)
				note("Kauf-Order ohne Deckung entfernt")
				break
			end
		end
	end
	-- Verkaufs-Orders dürfen nie mehr Stück reservieren, als da sind (älteste behalten, Überhang streichen)
	local used: { [number]: number } = {}
	local kept = {}
	for _, o in ipairs(d.Orders) do
		if o.Side == "S" then
			local sum = (used[o.I] or 0) + o.Q
			if sum <= Portfolio.PosQty(d, o.I) then
				used[o.I] = sum
				table.insert(kept, o)
			else
				note("Verkaufs-Order ohne Anteile entfernt")
			end
		else
			table.insert(kept, o)
		end
	end
	d.Orders = kept
	return issues
end

return Portfolio
