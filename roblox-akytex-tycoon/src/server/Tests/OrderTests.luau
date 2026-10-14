-- =====================================================================
--  AKYTEX TYCOON – Selbsttests Orders, Depot, Bots (Server/Tests/OrderTests)
--  Besitzer: WP4 (Orders, Depot, Bots). Vertrag: DESIGN.md §D WP4 "Abnahme"/"Tests", §C17 (Depot-Invarianten,
--  Offline == Online, Gewinn-Transfer-Regeln). SelfTestService lädt dieses Modul; jeder Fehler = FAIL.
--  Alle Tests laufen gegen einen künstlichen, deterministischen Markt (keine Abhängigkeit von der echten Engine,
--  keine Spieler) und schreiben NIE in echte Spielstände. Engine-Caches bleiben unberührt (CacheBefore = −∞).
--
--  Prüft: Trichter-Gründe (Whitelist), Kaufen + Sofortverkauf ≤ 0, Cash nie negativ, Reservierungen 0 nach Storno,
--  OCO storniert die Gegenseite, Trigger-Lücken, Pfad-Regel, Nachzieh-Stopp ohne Zukunftsblick, Ablauf, Dividenden-
--  Ex-Tick, Gewinn-Transfer (Schwelle 1,02, Limit 6 %, 1× je Börsentag, Starthilfe/Admin nicht abhebbar, Tutorial-
--  Ausnahme), Offline == Online (gleiche Fills, gleiche Ticks), Bot-Deckel, Tagesbremse, Seq-Fenster rückt bei
--  Ablehnung vor, Token-Bucket 6/1,5, Depot-Reparatur, Liga-Statistik, ACAD-Pfad.
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared:WaitForChild("Util"))
local Config = require(Shared:WaitForChild("Config"))
local MarketFolder = script.Parent.Parent:WaitForChild("Market")
local Portfolio = require(MarketFolder:WaitForChild("Portfolio"))
local OrderEngine = require(MarketFolder:WaitForChild("OrderEngine"))
local BotEngine = require(MarketFolder:WaitForChild("BotEngine"))
local CatchUp = require(MarketFolder:WaitForChild("CatchUp"))
local PortfolioMath = require(Shared:WaitForChild("Market"):WaitForChild("PortfolioMath"))

local DAY = 1200

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

local function orderService(services: any): any
	local svc = services and services.OrderService
	if svc then
		return svc
	end
	local module = script.Parent.Parent:WaitForChild("Services"):FindFirstChild("OrderService")
	assert(module and module:IsA("ModuleScript"), "OrderService fehlt")
	return require(module) :: any
end

-- ---------------------------------------------------------------------
-- Künstlicher Markt (deterministisch, ohne Zufall)
-- ---------------------------------------------------------------------
local BASE: { [number]: number } = { [1] = 24000, [2] = 18000, [5] = 8800, [7] = 6400, [40] = 10000, [41] = 9000 }

local function midAt(i: number, t: number): number
	local b = BASE[i] or 10000
	local x = b
		* (1 + 0.04 * math.sin(t / 53 + i) + 0.015 * math.sin(t / 9.7 + 2 * i) + 0.006 * math.sin(t / 2.3 + 3 * i))
	return math.floor(x + 0.5)
end

local function candleAt(i: number, t: number): (number, number, number, number)
	local o, c = midAt(i, t - 1), midAt(i, t)
	local wick = math.floor(math.abs(math.sin(t * 1.7 + i)) * 0.0008 * c + 0.5)
	return o, math.max(o, c) + wick, math.min(o, c) - wick, c
end

local function cursorFor(i: number, _t0: number): any
	return {
		Candle = function(_self: any, t: number): (number, number, number, number)
			return candleAt(i, t)
		end,
		Seek = function(_self: any, _t: number) end,
	}
end

local function fallbackLicence(idx: number): any
	local svc = orderService(nil)
	local list = Config.Trading.LicenceFallback
	return svc._Test.NormalizeLicence(list[idx], idx, 1)
end

local function newDepot(cash: number): { [string]: any }
	return {
		V = 1,
		Cash = cash,
		Basis = cash,
		Pos = {},
		Short = {},
		Orders = {},
		Alerts = {},
		Watch = { {} },
		Fills = {},
		Nav = {},
		Seq = {},
		NextId = 1,
		LastTick = 0,
		LastTransferDay = -1,
		LastRefillUtcDay = -1,
		AutoTransfer = true,
		Bots = {},
		Stats = {
			Trades = 0,
			Wins = 0,
			Losses = 0,
			GrossWin = 0,
			GrossLoss = 0,
			PeakNav = 0,
			MaxDD = 0,
			BestPct = 0,
			ReadWell = 0,
		},
		Tutorial = { T0 = 0, Q = 0, Done = false },
		Lic = 1,
		Pending = 0,
	}
end

type TestEnv = { [string]: any }

local function makeEnv(opts: { [string]: any }?): (TestEnv, { { any } })
	local o = opts or {}
	local events: { { any } } = {}
	local priceFn = o.PriceAt or midAt
	local env: TestEnv = {
		Mode = o.Mode or "Replay",
		Licence = fallbackLicence(o.Licence or 7),
		Perks = { BotSlots = 4, BotLevels = o.BotLevels or {}, Alerts = 18, Watchlists = 5 },
		PriceAt = function(i: number, t: number): number?
			return priceFn(i, t)
		end,
		Quote = o.Quote,
		Class = function(i: number): string?
			return if i >= 40 and i <= 46 then "ETF" else "Normal"
		end,
		Set = function(i: number): string?
			return if i == 41 then "Trader" else "Azubi"
		end,
		DivBps = function(i: number): number
			return if i == 2 then 40 elseif i == 5 then 30 else 0
		end,
		Listed = function(i: number): boolean
			return BASE[i] ~= nil
		end,
		Halted = function(_i: number): boolean
			return false
		end,
		FactDir = function(_i: number, _t: number): number?
			return o.FactDir
		end,
		AdminActive = function(_t: number): boolean
			return o.Admin == true
		end,
		AdminBetween = function(_t0: number, _t1: number): boolean
			return o.Admin == true
		end,
		Dividends = function(t0: number, t1: number): { any }
			local list = {}
			for _, div in ipairs(o.Divs or {}) do
				if div.Tick >= t0 and div.Tick <= t1 then
					table.insert(list, div)
				end
			end
			return list
		end,
		Emit = function(kind: string, data: any)
			table.insert(events, { kind, data })
		end,
		League = { Week = 0, Returns = {}, Trades = 0, Days = 0, Tainted = false },
		Week = function(t: number): number
			return 1 + t // 604800
		end,
		OwnerTaint = false,
		CacheBefore = -math.huge, -- Tests füllen nie die server-weiten Caches
		Watch = o.Watch or {},
		ActiveIds = function(): { number }
			return { 1, 2, 5, 7, 40, 41 }
		end,
	}
	return env, events
end

local function countKind(events: { { any } }, kind: string): number
	local n = 0
	for _, e in ipairs(events) do
		if e[1] == kind then
			n += 1
		end
	end
	return n
end

local function lastOf(events: { { any } }, kind: string): any
	for index = #events, 1, -1 do
		if events[index][1] == kind then
			return events[index][2]
		end
	end
	return nil
end

-- konstanter Kurs (für exakte Trigger-Fälle): hs = max(1, round(10000 · 8 / 10.000) // 2) = 4
local function flat(_i: number, _t: number): number
	return 10000
end

local function addPosition(d: { [string]: any }, i: number, q: number, cost: number, t: number)
	d.Pos[tostring(i)] = { Q = q, C = cost, R = 0, T = t, F = 0 }
end

local Tests = {}

-- ---------------------------------------------------------------------
-- 1) Trichter & Invarianten
-- ---------------------------------------------------------------------
function Tests.FunnelReasonsWhitelist()
	local want = {
		"Start",
		"Licence",
		"Refill",
		"Trade",
		"Fee",
		"Dividend",
		"BotWage",
		"Transfer",
		"Admin",
		"Tutorial",
		"Migration",
	}
	local count = 0
	for _ in pairs(Portfolio.REASONS) do
		count += 1
	end
	eq(count, #want, "Anzahl Gründe")
	for _, reason in ipairs(want) do
		truthy(Portfolio.REASONS[reason], "Grund fehlt: " .. reason)
	end
	local d = newDepot(1000)
	eq(Portfolio.Credit(d, 50, "Robux"), false, "unbekannter Grund abgelehnt")
	eq(Portfolio.Credit(d, 1.5, "Trade"), false, "kein Bruch-Cent")
	eq(Portfolio.Debit(d, 2000, "Trade"), false, "nie unter 0")
	eq(d.Cash, 1000, "Cash unverändert")
	Portfolio.OpenDay(d, 5, 1000, false)
	truthy(Portfolio.Credit(d, 500, "Admin"), "Admin-Gabe")
	eq(d.Basis, 1500, "Admin erhöht die Basis mit")
	truthy(Portfolio.Credit(d, 300, "Refill"), "Starthilfe")
	eq(d.Basis, 1500, "Starthilfe erhöht die Basis nicht")
	truthy(Portfolio.Debit(d, 200, "Transfer"), "Transfer")
	eq((Portfolio.CurrentDay(d) :: any)[4], 600, "Fluss F = +500 + 300 − 200")
	truthy(Portfolio.Debit(d, 99999, "Licence"), "Herabstufung (Admin)")
	eq(d.Cash, 0, "Cash höchstens bis 0")
	eq(d.Basis, 0, "Basis sinkt voll")
end

function Tests.BuySellRoundTripNeverPositive()
	local env = makeEnv()
	local t = 1200 * 50 + 30
	for n = 1, 200 do
		local d = newDepot(50000000)
		local i = ({ 1, 2, 5, 7 })[(n % 4) + 1]
		local bid, ask = OrderEngine.EngineQuote(env :: any, i, t + n)
		local qty = 1 + (n * 37) % 400
		local ok = Portfolio.Buy(d, i, qty, ask :: number, env.Licence.FeeBps, nil, { Tick = t })
		truthy(ok, "Kauf " .. n)
		local okSell = Portfolio.Sell(d, i, qty, bid :: number, env.Licence.FeeBps, nil, { Tick = t + 1 })
		truthy(okSell, "Verkauf " .. n)
		truthy(d.Cash <= 50000000, ("Fall %d: Geld aus dem Nichts (%d)"):format(n, d.Cash - 50000000))
		truthy(d.Cash >= 0, "Cash ≥ 0")
		eq(d.Pos[tostring(i)], nil, "Position leer")
	end
end

-- Nachkauf zieht den Eröffnungs-Tick mengengewichtet nach: "1 Stück lange halten, dann groß nachkaufen und sofort
-- verkaufen" zählt NICHT als ≥ 60 s gehalten (Liga/XP/"Gut gelesen")
function Tests.AddToPositionHoldTimeWeighted()
	local env = makeEnv()
	local d = newDepot(50000000)
	local t = 1200 * 60
	local _, ask = OrderEngine.EngineQuote(env :: any, 1, t)
	truthy(Portfolio.Buy(d, 1, 1, ask :: number, env.Licence.FeeBps, nil, { Tick = t }), "1 Stück")
	truthy(Portfolio.Buy(d, 1, 99, ask :: number, env.Licence.FeeBps, nil, { Tick = t + 600 }), "99 nachgekauft")
	eq(d.Pos["1"].T, t + 594, "Eröffnungs-Tick mengengewichtet (1 × t + 99 × (t + 600)) / 100")
	local bid = OrderEngine.EngineQuote(env :: any, 1, t + 601)
	local ok, info = Portfolio.Sell(d, 1, 100, bid :: number, env.Licence.FeeBps, nil, { Tick = t + 601 })
	truthy(ok, "Verkauf")
	eq(info.HeldS, 7, "Haltedauer zählt ab dem gewichteten Einstieg")
end

function Tests.ReservationsZeroAfterCancelCashNeverNegative()
	local env = makeEnv({ Licence = 4 })
	local d = newDepot(2500000)
	local t = 1200 * 80 + 100
	local placed = {}
	for k = 1, 20 do
		local mid = midAt(1, t)
		local result = OrderEngine.Place(d, env :: any, t, {
			I = 1,
			Side = "B",
			Type = "LMT",
			Qty = 10,
			Lim = math.floor(mid * (0.9 + k * 0.001)),
		})
		if result.Ok then
			table.insert(placed, result.OrderId)
		end
		truthy(Portfolio.Reserved(d) <= d.Cash, "Reservierung ≤ Cash")
	end
	truthy(#placed >= 1, "mindestens eine Order")
	truthy(#placed < 20, "Lizenz-/Geld-Grenze greift")
	for _, id in ipairs(placed) do
		truthy(OrderEngine.Cancel(d, id), "Storno")
	end
	eq(Portfolio.Reserved(d), 0, "Reservierungen nach Storno")
	eq(d.Cash, 2500000, "Cash unverändert")
	eq(#d.Orders, 0, "keine Orders")
end

-- ---------------------------------------------------------------------
-- 2) Trigger (MARKET §11.3)
-- ---------------------------------------------------------------------
function Tests.TriggerGaps()
	local env, events = makeEnv({ PriceAt = flat })
	local t = 1200 * 10 + 61
	-- Verlust-Stopp mit Kurslücke: Ausführung schlechter als der Stopp
	local d = newDepot(1000000)
	addPosition(d, 1, 10, 100000, t - 100)
	table.insert(
		d.Orders,
		{ Id = 1, I = 1, Side = "S", Type = "STP", Q = 10, Stp = 9500, Res = 0, Exp = t + 999, T0 = t - 5 }
	)
	d.NextId = 2
	OrderEngine.CheckInstrument(d, env :: any, 1, t, 9300, 9350, 9200, 9250)
	local fill = lastOf(events, "Fill")
	truthy(fill, "Stopp ausgelöst")
	eq(fill.Fill.Px, 9296, "Lücke: O − hs")
	eq(fill.Gap, true, "Lücken-Hinweis")
	eq(#d.Orders, 0, "Order weg")
	-- Kauf-Limit mit Lücke nach unten: besser als das Limit
	local d2 = newDepot(1000000)
	local res = PortfolioMath.BuyCost(10, 9800, env.Licence.FeeBps)
	table.insert(
		d2.Orders,
		{ Id = 1, I = 1, Side = "B", Type = "LMT", Q = 10, Lim = 9800, Res = res, Exp = t + 999, T0 = t - 5 }
	)
	OrderEngine.CheckInstrument(d2, env :: any, 1, t, 9500, 9550, 9400, 9450)
	local fill2 = lastOf(events, "Fill")
	eq(fill2.Fill.Px, 9504, "Lücke: min(Limit, O + hs)")
	eq(Portfolio.Reserved(d2), 0, "Reservierung frei")
	eq(d2.Cash, 1000000 - PortfolioMath.BuyCost(10, 9504, env.Licence.FeeBps), "genau die Kosten")
	-- Order aus demselben Tick löst nicht aus (gilt ab Tick nach Erstellung)
	local d3 = newDepot(1000000)
	addPosition(d3, 1, 10, 100000, t - 100)
	table.insert(
		d3.Orders,
		{ Id = 1, I = 1, Side = "S", Type = "STP", Q = 10, Stp = 9500, Res = 0, Exp = t + 999, T0 = t }
	)
	OrderEngine.CheckInstrument(d3, env :: any, 1, t, 9300, 9350, 9200, 9250)
	eq(#d3.Orders, 1, "T0 == t löst nicht aus")
end

function Tests.OcoPathRuleCancelsOtherSide()
	local env, events = makeEnv({ PriceAt = flat })
	local t = 1200 * 10 + 61
	local function setup(): { [string]: any }
		local d = newDepot(0)
		addPosition(d, 1, 10, 100000, t - 100)
		table.insert(d.Orders, {
			Id = 7,
			I = 1,
			Side = "S",
			Type = "OCO",
			Q = 10,
			Stp = 9500,
			Tp = 10500,
			Res = 0,
			Exp = t + 999,
			T0 = t - 5,
		})
		return d
	end
	-- steigende Kerze O→L→H→C: Stopp zuerst
	local up = setup()
	OrderEngine.CheckInstrument(up, env :: any, 1, t, 10000, 10600, 9400, 10100)
	local a = lastOf(events, "Fill")
	eq(a.Kind, "OcoStop", "steigend: Stopp zuerst")
	eq(a.Fill.Px, 9500, "Stopp-Preis")
	eq(#up.Orders, 0, "Gegenseite storniert (ein Datensatz)")
	eq(countKind(events, "Fill"), 1, "genau ein Fill")
	-- fallende Kerze O→H→L→C: Ziel zuerst
	local down = setup()
	OrderEngine.CheckInstrument(down, env :: any, 1, t, 10000, 10600, 9400, 9900)
	local b = lastOf(events, "Fill")
	eq(b.Kind, "OcoTarget", "fallend: Ziel zuerst")
	eq(b.Fill.Px, 10500, "Ziel-Preis")
	eq(countKind(events, "Fill"), 2, "wieder genau ein Fill")
	eq(Portfolio.PosQty(down, 1), 0, "Position verkauft")
end

function Tests.TrailingStopNoLookAhead()
	local env, events = makeEnv({ PriceAt = flat })
	local t = 1200 * 10 + 61
	local d = newDepot(0)
	addPosition(d, 1, 10, 100000, t - 100)
	table.insert(
		d.Orders,
		{ Id = 1, I = 1, Side = "S", Type = "TRL", Q = 10, Trl = 500, Peak = 10000, Res = 0, Exp = t + 999, T0 = t - 5 }
	)
	-- Kerze 1: neues Hoch 11.000, Tief 9.600. Alter Stopp 9.500 -> keine Auslösung, auch wenn der neue Stopp
	-- (10.446) im selben Tief läge (das wäre ein Blick in die Zukunft).
	OrderEngine.CheckInstrument(d, env :: any, 1, t, 10000, 11000, 9600, 10500)
	eq(countKind(events, "Fill"), 0, "keine Auslösung in Kerze 1")
	eq(d.Orders[1].Peak, 10996, "Peak = H − hs nach der Prüfung")
	OrderEngine.CheckInstrument(d, env :: any, 1, t + 1, 10500, 10600, 10400, 10450)
	local fill = lastOf(events, "Fill")
	truthy(fill, "Kerze 2 löst aus")
	eq(fill.Kind, "Trail", "Nachzieh-Stopp")
	eq(fill.Fill.Px, 10446, "Stopp = floor(10.996 · 0,95)")
end

function Tests.ExpiryDayAnd24h()
	local env, events = makeEnv()
	local t = 1200 * 30 + 500
	local d = newDepot(5000000)
	local a = OrderEngine.Place(
		d,
		env :: any,
		t,
		{ I = 1, Side = "B", Type = "LMT", Qty = 1, Lim = midAt(1, t) - 500, Exp = "DAY" }
	)
	local b = OrderEngine.Place(d, env :: any, t, { I = 1, Side = "B", Type = "LMT", Qty = 1, Lim = midAt(1, t) - 500 })
	truthy(a.Ok and b.Ok, "beide gesetzt")
	eq(d.Orders[1].Exp, 1200 * 31, "DAY = nächste Glocke")
	eq(d.Orders[2].Exp, t + 86400, "24 h")
	OrderEngine.Expire(d, env :: any, 1200 * 31)
	eq(#d.Orders, 1, "DAY abgelaufen")
	eq(countKind(events, "Expired"), 1, "Meldung")
	eq(Portfolio.Reserved(d), d.Orders[1].Res, "nur noch eine Reservierung")
end

function Tests.DividendExTick()
	local env, events = makeEnv()
	local d = newDepot(0)
	addPosition(d, 2, 40, 720000, 0)
	OrderEngine.PayDividends(
		d,
		env :: any,
		5000,
		{ { I = 2, Tick = 4999, Cents = 50 }, { I = 2, Tick = 5000, Cents = 50 } }
	)
	eq(d.Cash, 2000, "nur der Ex-Tick zählt: 40 × 50")
	eq(countKind(events, "Dividend"), 1, "eine Meldung")
	OrderEngine.PayDividends(d, env :: any, 5000, { { I = 5, Tick = 5000, Cents = 50 } })
	eq(d.Cash, 2000, "ohne Bestand keine Dividende")
end

-- ---------------------------------------------------------------------
-- 3) Gewinn-Transfer & Rettungsschirm (§B8.2, §B8.4)
-- ---------------------------------------------------------------------
function Tests.TransferRules()
	local env, events = makeEnv()
	local basis = 2500000
	local d = newDepot(basis)
	-- unter 1,02 × Basis: nichts
	eq((OrderEngine.TransferAmount(d, env :: any, 2549999)), 0, "Schwelle")
	-- 6-%-Deckel
	Portfolio.Credit(d, 1000000, "Trade")
	eq((OrderEngine.TransferAmount(d, env :: any, 3500000)), 150000, "6 % der Basis")
	-- Glocke: genau einmal je Börsentag, Betrag wartet in Pending
	local t = 1200 * 40
	Portfolio.OpenDay(d, 39, 3500000, false)
	OrderEngine.CloseDay(d, env :: any, t)
	local transfer = lastOf(events, "Transfer")
	truthy(transfer, "Auto-Transfer an der Glocke")
	eq(d.LastTransferDay, 39, "für den beendeten Tag")
	local pending = d.Pending
	truthy(pending > 0 and pending <= 150000, "Betrag im Pending")
	local before = countKind(events, "Transfer")
	OrderEngine.CloseDay(d, env :: any, t) -- gleicher Tag nochmal (z. B. doppelter Aufruf)
	eq(countKind(events, "Transfer"), before, "kein zweiter Transfer für denselben Tag")
	-- Admin-Gabe ist nie abhebbar (Basis steigt mit)
	local d2 = newDepot(basis)
	local navBefore = d2.Cash
	Portfolio.Credit(d2, 5000000, "Admin")
	eq((OrderEngine.TransferAmount(d2, env :: any, navBefore + 5000000)), 0, "Admin-AKY nicht abhebbar")
	-- Starthilfe ist nie abhebbar
	local d3 = newDepot(basis)
	Portfolio.Debit(d3, basis, "Trade")
	Portfolio.Credit(d3, basis // 2, "Refill")
	eq((OrderEngine.TransferAmount(d3, env :: any, basis // 2)), 0, "Starthilfe nicht abhebbar")
	-- Tutorial-Ausnahme: erster Transfer nach der Übung ohne 2-%-Schwelle
	local d4 = newDepot(basis)
	Portfolio.Credit(d4, 37500, "Tutorial")
	d4.Tutorial.Done = true
	eq((OrderEngine.TransferAmount(d4, env :: any, basis + 37500)), 37500, "Tutorial-Ausnahme")
	d4.LastTransferDay = 3
	eq((OrderEngine.TransferAmount(d4, env :: any, basis + 37500)), 0, "nur beim ersten Transfer")
end

function Tests.AutoTransferOffNoPending()
	local env = makeEnv()
	local d = newDepot(2500000)
	Portfolio.Credit(d, 1000000, "Trade")
	d.AutoTransfer = false
	Portfolio.OpenDay(d, 39, 3500000, false)
	OrderEngine.CloseDay(d, env :: any, 1200 * 40)
	eq(d.Pending, 0, "Auto-Transfer aus")
	eq(d.LastTransferDay, -1, "Tag bleibt frei für den Knopf")
end

-- ---------------------------------------------------------------------
-- 4) Offline == Online (gleiche Fills, gleiche Ticks) inkl. Bots, Dividenden, Glocken
-- ---------------------------------------------------------------------
local function prepareScenario(t0: number): ({ [string]: any }, { any })
	local divs = { { I = 2, Tick = t0 + 1500, Cents = 50 }, { I = 5, Tick = t0 + 4100, Cents = 30 } }
	local env = makeEnv({ Licence = 7, Divs = divs, Watch = { 1, 5, 7 } })
	local d = newDepot(40000000)
	d.Lic = 7
	d.LastTick = t0
	Portfolio.OpenDay(d, t0 // DAY, d.Cash, false)
	local function place(req: { [string]: any })
		local result = OrderEngine.Place(d, env :: any, t0, req)
		assert(result.Ok, "Szenario-Order: " .. tostring(result.Key))
	end
	local m1, m5, m7 = midAt(1, t0), midAt(5, t0), midAt(7, t0)
	place({ I = 1, Side = "B", Type = "LMT", Qty = 50, Lim = math.floor(m1 * 0.97) })
	place({ I = 5, Side = "B", Type = "LMT", Qty = 80, Lim = math.floor(m5 * 0.99), Protect = true })
	place({ I = 7, Side = "B", Type = "MKT", Qty = 200 })
	place({ I = 7, Side = "S", Type = "STP", Qty = 100, Stp = math.floor(m7 * 0.975) })
	place({ I = 7, Side = "S", Type = "TRL", Qty = 100, Trl = 150 })
	place({ I = 2, Side = "B", Type = "MKT", Qty = 100 })
	place({
		I = 2,
		Side = "S",
		Type = "OCO",
		Qty = 100,
		Stp = math.floor(midAt(2, t0) * 0.96),
		Tp = math.floor(midAt(2, t0) * 1.03),
	})
	place({ I = 1, Side = "B", Type = "STP", Qty = 20, Stp = math.floor(m1 * 1.02) })
	table.insert(d.Alerts, { Id = 900, I = 1, Px = math.floor(m1 * 1.03), Dir = "Up" })
	table.insert(d.Alerts, { Id = 901, I = 5, Px = math.floor(m5 * 0.96), Dir = "Down" })
	d.Bots[1] = BotEngine.NewSlot("Sparplan", 0.10, 40)
	d.Bots[2] = BotEngine.NewSlot("Trend", 0.10, 1)
	d.Bots[3] = BotEngine.NewSlot("Dip", 0.03, nil)
	d.Watch[1] = { 1, 5, 7 }
	return d, divs
end

function Tests.OfflineEqualsOnline()
	local t0 = 1200 * 200 + 900
	local t1 = t0 + 7200 -- 2 h, 6 Glocken
	local base, divs = prepareScenario(t0)
	local online = Util.DeepCopy(base)
	local offline = Util.DeepCopy(base)

	-- online: Tick für Tick
	-- Modus "Replay" auch online: Tests schreiben nie in die server-weiten Spread-Caches
	local envOn, eventsOn = makeEnv({ Licence = 7, Divs = divs, Watch = { 1, 5, 7 } })
	envOn.League = { Week = 0, Returns = {}, Trades = 0, Days = 0, Tainted = false }
	for t = t0 + 1, t1 do
		local divsAt = nil
		for _, div in ipairs(divs) do
			if div.Tick == t then
				divsAt = divs
			end
		end
		OrderEngine.Step(online, envOn :: any, t, {
			Candle = function(i: number): (number?, number?, number?, number?)
				return candleAt(i, t)
			end,
			Divs = divsAt,
		})
	end

	-- offline: Abgleich mit Minuten-Überspringen
	local envOff, eventsOff = makeEnv({ Licence = 7, Divs = divs, Watch = { 1, 5, 7 } })
	envOff.League = { Week = 0, Returns = {}, Trades = 0, Days = 0, Tainted = false }
	local report = CatchUp.Run(offline, envOff :: any, t1, { Cursor = cursorFor })

	local fillsOn, fillsOff = {}, {}
	for _, e in ipairs(eventsOn) do
		if e[1] == "Fill" then
			local f = e[2].Fill
			table.insert(fillsOn, ("%d:%d:%s:%d:%d:%d"):format(f.Tick, f.I, f.Side, f.Q, f.Px, f.Fee))
		end
	end
	for _, e in ipairs(eventsOff) do
		if e[1] == "Fill" then
			local f = e[2].Fill
			table.insert(fillsOff, ("%d:%d:%s:%d:%d:%d"):format(f.Tick, f.I, f.Side, f.Q, f.Px, f.Fee))
		end
	end
	truthy(#fillsOn >= 4, "Szenario erzeugt Fills (" .. #fillsOn .. ")")
	eq(#fillsOff, #fillsOn, "gleiche Anzahl Fills")
	for k = 1, #fillsOn do
		eq(fillsOff[k], fillsOn[k], "Fill " .. k)
	end
	eq(report.Fills, #fillsOn, "Bericht zählt die Fills")
	eq(offline.Cash, online.Cash, "Cash")
	eq(offline.LastTick, t1, "Offline bis zum Ziel-Tick")
	eq(online.LastTick, t1, "Online bis zum Ziel-Tick")
	eq(#offline.Orders, #online.Orders, "offene Orders")
	eq(#offline.Alerts, #online.Alerts, "Alarme")
	eq(countKind(eventsOff, "Alert"), countKind(eventsOn, "Alert"), "ausgelöste Alarme")
	eq(countKind(eventsOff, "DayResult"), countKind(eventsOn, "DayResult"), "Börsentage")
	eq(offline.Pending, online.Pending, "Auto-Transfers")
	for key, p in pairs(online.Pos) do
		local q = offline.Pos[key]
		truthy(q, "Position " .. key)
		eq(q.Q, p.Q, "Stück " .. key)
		eq(q.C, p.C, "Einstand " .. key)
	end
	for index, rec in ipairs(online.Nav) do
		for k = 1, 6 do
			eq(offline.Nav[index][k], rec[k], ("Nav[%d][%d]"):format(index, k))
		end
	end
	for index, slot in ipairs(online.Bots) do
		for key, q in pairs(slot.Q) do
			eq(offline.Bots[index].Q[key], q, ("Bot %d Bestand %s"):format(index, key))
		end
	end
	for k, order in ipairs(online.Orders) do
		eq(offline.Orders[k].Id, order.Id, "Order-Id " .. k)
		eq(offline.Orders[k].Peak, order.Peak, "Nachzieh-Peak " .. k)
	end
end

-- Gleicher Vergleich gegen die ECHTE Kurs-Engine (isolierter Test-Kontext von WP3, eigener Seed): Random-Access-
-- Kerzen (online) gegen Cursor-Kerzen (offline). Ohne MarketService (Teil-Build) wird der Test übersprungen.
function Tests.OfflineEqualsOnlineRealEngine(services: any)
	local market = services and services.MarketService
	if not (market and type(market.TestContext) == "function") then
		return
	end
	local Clock = require(Shared:WaitForChild("Clock"))
	local week = 41
	local ctx = market.TestContext(424242, week)
	local t0 = Clock.WeekStartTick(week) + 60 * DAY + 1050
	local t1 = t0 + 1800
	local guard = 0
	while ctx.Director:BuiltThrough() < t1 // DAY + 1 and guard < 400 do
		ctx.Director:EnsureBuilt(t1 // DAY + 1, 16)
		guard += 1
		task.wait()
	end
	local companies = Config.Companies
	local function def(i: number): any
		return companies.ById[i]
	end
	local function baseEnv(): (TestEnv, { { any } })
		local env, events = makeEnv({ Licence = 7, Watch = { 2, 5, 9 } })
		env.PriceAt = function(i: number, t: number): number?
			return ctx.Engine:MidAt(i, t)
		end
		env.Class = function(i: number): string?
			return def(i) and def(i).Class
		end
		env.Set = function(i: number): string?
			return def(i) and def(i).Set
		end
		env.DivBps = function(i: number): number
			return def(i) and def(i).DivBps or 0
		end
		env.Listed = function(i: number): boolean
			return def(i) ~= nil and def(i).Set ~= "Tutorial" and def(i).Ipo ~= true
		end
		env.Dividends = function(a: number, b: number): { any }
			return ctx.Director:Dividends(a, b)
		end
		env.ActiveIds = function(): { number }
			local ids = {}
			for i = 1, 46 do
				if def(i) and def(i).Ipo ~= true then
					table.insert(ids, i)
				end
			end
			return ids
		end
		return env, events
	end
	-- Szenario mit engen Marken (lösen in 30 min sicher aus)
	local envSetup = baseEnv()
	local d = newDepot(80000000)
	d.Lic = 7
	d.LastTick = t0
	Portfolio.OpenDay(d, t0 // DAY, d.Cash, false)
	local function place(req: { [string]: any })
		local result = OrderEngine.Place(d, envSetup :: any, t0, req)
		assert(result.Ok, "Szenario-Order: " .. tostring(result.Key))
	end
	local function mid(i: number): number
		return ctx.Engine:MidAt(i, t0)
	end
	place({ I = 2, Side = "B", Type = "LMT", Qty = 100, Lim = math.floor(mid(2) * 0.998) })
	place({ I = 5, Side = "B", Type = "MKT", Qty = 300 })
	place({ I = 5, Side = "S", Type = "STP", Qty = 150, Stp = math.floor(mid(5) * 0.997) })
	place({ I = 5, Side = "S", Type = "TRL", Qty = 150, Trl = 50 })
	place({ I = 9, Side = "B", Type = "MKT", Qty = 400 })
	place({
		I = 9,
		Side = "S",
		Type = "OCO",
		Qty = 400,
		Stp = math.floor(mid(9) * 0.996),
		Tp = math.ceil(mid(9) * 1.004),
	})
	local _, ask7 = OrderEngine.EngineQuote(envSetup :: any, 7, t0)
	place({ I = 7, Side = "B", Type = "STP", Qty = 50, Stp = math.max(math.ceil(mid(7) * 1.003), (ask7 :: number) + 2) })
	table.insert(d.Alerts, { Id = 950, I = 2, Px = math.ceil(mid(2) * 1.002), Dir = "Up" })
	table.insert(d.Alerts, { Id = 951, I = 40, Px = math.floor(mid(40) * 0.998), Dir = "Down" })
	d.Bots[1] = BotEngine.NewSlot("Sparplan", 0.10, 40)
	d.Bots[2] = BotEngine.NewSlot("Trend", 0.10, 7)
	d.Bots[3] = BotEngine.NewSlot("Dividend", 0.10, nil)
	local online = Util.DeepCopy(d)
	local offline = Util.DeepCopy(d)

	local envOn, eventsOn = baseEnv()
	for t = t0 + 1, t1 do
		local divs = ctx.Director:Dividends(t, t)
		OrderEngine.Step(online, envOn :: any, t, {
			Candle = function(i: number): (number?, number?, number?, number?)
				local o, h, l, c = ctx.Engine:CandleAt(i, t)
				return o, h, l, c
			end,
			Divs = if #divs > 0 then divs else nil,
		})
		if (t - t0) % 300 == 0 then
			task.wait()
		end
	end
	local envOff, eventsOff = baseEnv()
	CatchUp.Run(offline, envOff :: any, t1, {
		Cursor = function(i: number, t: number): any
			return ctx.Engine:NewCursor(i, t)
		end,
		Yield = function()
			task.wait()
		end,
		BudgetMs = 4,
	})
	local function fills(events: { { any } }): { string }
		local out = {}
		for _, e in ipairs(events) do
			if e[1] == "Fill" then
				local f = e[2].Fill
				table.insert(out, ("%d:%d:%s:%d:%d"):format(f.Tick, f.I, f.Side, f.Q, f.Px))
			end
		end
		return out
	end
	local a, b = fills(eventsOn), fills(eventsOff)
	truthy(#a >= 3, "echte Engine erzeugt Fills (" .. #a .. ")")
	eq(#b, #a, "gleiche Anzahl Fills (echte Engine)")
	for k = 1, #a do
		eq(b[k], a[k], "Fill " .. k .. " (echte Engine)")
	end
	eq(offline.Cash, online.Cash, "Cash (echte Engine)")
	eq(#offline.Orders, #online.Orders, "offene Orders (echte Engine)")
	eq(countKind(eventsOff, "Alert"), countKind(eventsOn, "Alert"), "Alarme (echte Engine)")
end

function Tests.CatchUpWindowAndJump()
	local t0 = 1200 * 300
	local d = newDepot(5000000)
	d.LastTick = t0
	local from, winEnd, botsUntil = CatchUp.Window(d, t0 + 200000)
	eq(from, t0 + 1, "ab dem Tick nach dem Verlassen")
	eq(winEnd, t0 + 86400, "Orders 24 h")
	eq(botsUntil, t0 + 43200, "Bots 12 h")
	-- Sprung: nach 24 h ist alles abgelaufen, LastTick landet auf dem Ziel
	local env = makeEnv()
	Portfolio.OpenDay(d, t0 // DAY, d.Cash, false)
	table.insert(
		d.Orders,
		{ Id = 1, I = 1, Side = "S", Type = "TP", Q = 1, Tp = 99999, Res = 0, Exp = t0 + 86400, T0 = t0 }
	)
	addPosition(d, 1, 1, 24000, t0)
	local report = CatchUp.Run(d, env :: any, t0 + 90000, { Cursor = cursorFor })
	eq(d.LastTick, t0 + 90000, "Ziel erreicht")
	eq(#d.Orders, 0, "abgelaufen")
	eq(report.Expired, 1, "Ablauf gezählt")
	eq(report.Jumped, true, "Rest übersprungen")
end

-- ---------------------------------------------------------------------
-- 5) Bots (§B8.5)
-- ---------------------------------------------------------------------
function Tests.BotCapitalCap()
	local env = makeEnv({ BotLevels = { Sparplan = 2 } })
	local slot = BotEngine.NewSlot("Sparplan", 0.20, 40)
	eq(BotEngine.Capital(env :: any, slot), 0.20, "Bot-Stufe 2 -> 20 %")
	local trend = BotEngine.NewSlot("Trend", 0.08, 1)
	eq(BotEngine.Capital(env :: any, trend), 0.08, "Capital-Preset: eingestellter Anteil ≤ Stufe 0 (10 %)")
	local big = BotEngine.NewSlot("Trend", 0.30, 1)
	eq(BotEngine.Capital(env :: any, big), 0.10, "Stufe 0 deckelt auf 10 %")
	-- Sparplan über viele Börsentage: Bot-Wert bleibt unter Kapital × Depotwert
	local d = newDepot(10000000)
	d.Bots[1] = BotEngine.NewSlot("Sparplan", 0.20, 40)
	local envCap = makeEnv({ BotLevels = {} })
	local t = 1200 * 400
	for day = 0, 15 do
		local tt = t + day * DAY
		-- Kursgewinne dürfen den Bot-Wert über den Deckel heben, KÄUFE nie (gleiche Kurse vorher/nachher)
		local before = BotEngine.Value(d, envCap :: any, tt, d.Bots[1])
		BotEngine.Decide(d, envCap :: any, tt)
		local nav = OrderEngine.NavAt(d, envCap :: any, tt)
		local after = BotEngine.Value(d, envCap :: any, tt, d.Bots[1])
		if after > before then
			truthy(
				after <= 0.10 * nav + midAt(40, tt),
				("Tag %d: Kauf über den Deckel (%d > 10 %% von %d)"):format(day, after, nav)
			)
		end
	end
	truthy(Portfolio.PosQty(d, 40) > 0, "Sparplan hat gekauft")
end

function Tests.BotDailyLossBrake()
	local env, events = makeEnv()
	local d = newDepot(10000000)
	local t = 1200 * 500 + 120
	addPosition(d, 1, 100, 2400000, t - 600)
	local slot = BotEngine.NewSlot("Trend", 0.10, 1)
	slot.Q = { ["1"] = 100 }
	slot.Day = t // DAY
	slot.DayNav = 1000000
	slot.DayVal = BotEngine.Value(d, env :: any, t, slot) + 60000 -- heute schon 6 % des Tageskapitals verloren
	slot.DayFlow = 0
	d.Bots[1] = slot
	BotEngine.Decide(d, env :: any, t)
	eq(slot.Paused, true, "Bremse pausiert den Bot")
	eq(countKind(events, "BotPaused"), 1, "Meldung")
	-- nächster Börsentag löst die Bremse
	BotEngine.Decide(d, env :: any, (t // DAY + 1) * DAY)
	eq(slot.Paused, false, "neuer Tag")
end

function Tests.BotWagesNeverFromReserved()
	local env = makeEnv()
	local d = newDepot(1000)
	addPosition(d, 40, 1000, 10000000, 0)
	local slot = BotEngine.NewSlot("Sparplan", 0.1, 40)
	slot.Q = { ["40"] = 1000 }
	d.Bots[1] = slot
	table.insert(
		d.Orders,
		{ Id = 1, I = 1, Side = "B", Type = "LMT", Q = 1, Lim = 900, Res = 1000, Exp = 99999999, T0 = 0 }
	)
	BotEngine.PayWages(d, env :: any, 1200 * 50)
	eq(d.Cash, 1000, "freies Cash 0 -> kein Lohn aus der Reservierung")
	local d2 = newDepot(10000000)
	addPosition(d2, 40, 1000, 10000000, 0)
	d2.Bots[1] = slot
	BotEngine.PayWages(d2, env :: any, 1200 * 50)
	local value = 1000 * (OrderEngine.EngineQuote(env :: any, 40, 1200 * 50) :: number)
	eq(10000000 - d2.Cash, math.ceil(value * 2 / 10000), "0,02 % des verwalteten Kapitals")
end

-- ---------------------------------------------------------------------
-- 6) Anfragen: Seq-Fenster, Bucket
-- ---------------------------------------------------------------------
function Tests.SeqWindowAdvancesOnReject(services: any)
	local seq = orderService(services)._Test.Seq
	local key = {} -- Stellvertreter für einen Spieler
	local d = newDepot(0)
	eq(seq.Duplicate(key, d, 1), nil, "neu")
	seq.Record(key, d, 1)
	seq.Store(key, 1, { Ok = false, Key = "trade.noCash" })
	local again = seq.Duplicate(key, d, 1)
	truthy(again and again.Key == "trade.noCash", "Ablehnung wird wiederholt, Fenster ist vorgerückt")
	for s = 2, 40 do
		seq.Record(key, d, s)
	end
	eq(#d.Seq, Config.Trading.SeqWindow, "Fenster begrenzt")
	eq(seq.Duplicate(key, d, 1), nil, "alte Nummer aus dem Fenster gefallen")
	seq.Clear(key)
end

function Tests.TradePlaceBucketLimitsBurst()
	local now = 0
	local bucket = Util.TokenBucket(6, 1.5, function(): number
		return now
	end)
	local ok = 0
	for _ = 1, 10 do
		if bucket.Take("p") then
			ok += 1
		end
	end
	eq(ok, 6, "10 Orders in einer Sekunde -> 6")
	now = 2
	local later = 0
	for _ = 1, 10 do
		if bucket.Take("p") then
			later += 1
		end
	end
	eq(later, 3, "nach 2 s wieder 3 (1,5/s)")
end

-- ---------------------------------------------------------------------
-- 7) Reparatur, Liga, Übung
-- ---------------------------------------------------------------------
function Tests.SanitizeRepairsWithoutMakingMoney()
	local d: { [string]: any } = newDepot(1000)
	d.Cash = 0 / 0
	d.Pos =
		{ ["1"] = { Q = 5, C = 100, R = 0 }, abc = { Q = 1 }, ["999"] = { Q = 3, C = 1, R = 0 }, ["2"] = { Q = -1 } }
	d.Orders = {
		{ Id = 1, I = 1, Side = "B", Type = "LMT", Q = 1, Lim = 100, Res = 0, Exp = 10, T0 = 1 }, -- ohne Reservierung
		{ Id = 2, I = 1, Side = "S", Type = "STP", Q = 9, Stp = 50, Res = 0, Exp = 10, T0 = 1 }, -- mehr als da
		{ Id = 3, I = 1, Side = "S", Type = "TP", Q = 2, Tp = 150, Res = 0, Exp = 10, T0 = 1 },
		{ Id = 4, I = 1, Side = "X", Type = "LMT", Q = 1 },
	}
	d.LastTick = 1e12
	local issues = Portfolio.Sanitize(d, 5000, function(i: number): boolean
		return i == 1 or i == 2
	end)
	truthy(#issues > 0, "Probleme gemeldet")
	eq(d.Cash, 0, "NaN-Cash -> 0 (nie erfunden)")
	eq(d.Pos["1"].Q, 5, "gültige Position bleibt")
	eq(d.Pos.abc, nil, "kaputter Schlüssel weg")
	eq(d.Pos["999"], nil, "unbekannter Wert weg")
	eq(d.Pos["2"], nil, "negative Menge weg")
	eq(#d.Orders, 1, "nur die gültige Verkaufs-Order bleibt")
	eq(d.Orders[1].Id, 3, "TP bleibt")
	eq(d.LastTick, 5000, "Zukunfts-Tick geklemmt")
	truthy(d.NextId > 3, "NextId über allen Ids")
end

function Tests.LeagueStatsAndRoll()
	local league: { [string]: any } = { Week = 0, Returns = {}, Trades = 0, Days = 0, Tainted = false }
	Portfolio.LeagueRoll(league, 202642)
	for _ = 1, 6 do
		Portfolio.LeagueAddDay(league, 0.01, true)
	end
	for _ = 1, 20 do
		Portfolio.LeagueAddTrade(league)
	end
	local stats = Portfolio.LeagueStats(league, false)
	eq(stats.Qualified, true, "20 Trades + 6 Tage")
	eq(stats.AvgDailyBp, 100, "Ø 1 %")
	truthy(stats.SkillScore >= 850, "konstante Woche -> Diamant-Bereich")
	eq(Portfolio.TierOf(stats.SkillScore, true), "Diamant", "Stufe")
	eq(Portfolio.LeagueStats(league, true).Qualified, false, "Besitzer/Admin ausgenommen")
	league.Tainted = true
	eq(Portfolio.LeagueStats(league, false).Qualified, false, "Taint schließt aus")
	Portfolio.LeagueRoll(league, 202643)
	eq(league.LastWeek, 202642, "Vorwoche gemerkt")
	eq(league.Trades, 0, "neue Woche leer")
	eq(league.Tainted, false, "Taint gilt nur eine Woche")
	eq(Portfolio.TierOf(500, false), "None", "ohne Teilnahme keine Stufe")
end

function Tests.CountingTradeRules()
	local env = makeEnv({ PriceAt = flat })
	local t = 1200 * 70 + 300
	local d = newDepot(1000000)
	Portfolio.OpenDay(d, t // DAY, 1000000, false)
	addPosition(d, 1, 100, 1000000, t - 120) -- 100 × 100 AKY, 120 s gehalten
	local result = OrderEngine.SellNow(d, env :: any, t, 1, 10, 9996, nil, "Market")
	truthy(result.Ok, "Verkauf")
	eq((Portfolio.CurrentDay(d) :: any)[5], 1, "≥ 2 % und ≥ 60 s zählt")
	eq(env.League.Trades, 1, "Liga zählt mit")
	local d2 = newDepot(1000000)
	Portfolio.OpenDay(d2, t // DAY, 1000000, false)
	addPosition(d2, 1, 100, 1000000, t - 10) -- nur 10 s gehalten
	OrderEngine.SellNow(d2, env :: any, t, 1, 10, 9996, nil, "Market")
	eq((Portfolio.CurrentDay(d2) :: any)[5], 0, "zu kurz gehalten zählt nicht")
	local envAdmin = makeEnv({ PriceAt = flat, Admin = true })
	local d3 = newDepot(1000000)
	Portfolio.OpenDay(d3, t // DAY, 1000000, false)
	addPosition(d3, 1, 100, 1000000, t - 120)
	OrderEngine.SellNow(d3, envAdmin :: any, t, 1, 10, 9996, nil, "Market")
	eq((Portfolio.CurrentDay(d3) :: any)[5], 0, "Admin-Fenster zählt nicht")
end

function Tests.AcadTutorialPath(services: any)
	local tutPrice = orderService(services)._Test.TutPrice
	local cfg = Config.Trading.Tutorial
	local p0, phase0 = tutPrice(0)
	truthy(math.abs(p0 - cfg.Start) <= cfg.Start * 0.003, "Start 100 AKY")
	eq(phase0, 0, "vor der News")
	local _, phase1 = tutPrice(5)
	eq(phase1, 1, "Lesefenster (News bei t0 + 2 s, 8 s)")
	local pRead = tutPrice(9)
	truthy(math.abs(pRead - cfg.Start) <= cfg.Start * 0.003, "im Lesefenster noch keine Reaktion")
	local _, phase2 = tutPrice(30)
	eq(phase2, 2, "Rampe")
	local pEnd, phase3 = tutPrice(80)
	eq(phase3, 3, "flach")
	local want = cfg.Start * (1 + cfg.Jump)
	truthy(math.abs(pEnd - want) <= want * 0.003, "+15 % nach der Rampe")
	-- Gewinn bei 10 % von 25.000 AKY ≈ +375 AKY (vor Gebühren)
	local qty = math.floor(0.10 * 2500000 / p0)
	truthy(math.abs(qty * (pEnd - p0) - 37500) <= 2000, "≈ +375 AKY")
end

return Tests
