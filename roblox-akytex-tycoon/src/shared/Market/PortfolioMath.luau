--!strict
-- =====================================================================
--  AKYTEX TYCOON – Depot-Mathematik ohne Seiteneffekte (Shared/Market/PortfolioMath)
--  Besitzer: WP4 (Orders, Depot, Bots). Vertrag: DESIGN.md §C6.2, §B8.2, §B11.1; MARKET.md §12.2–§12.6.
--  Rein: lädt keine Roblox-Dienste und kein anderes Modul -> Server (Portfolio/OrderEngine) UND Client
--  (Kosten-Vorschau im Order-Ticket, WP5) rechnen exakt gleich; mit der Luau-CLI testbar (tests/portfoliomath.test.luau).
--
--  Geld-Regeln (MARKET §12.2): alles in ganzzahligen CENT, Rundung immer zugunsten des Hauses
--  (Kosten/Gebühren aufrunden, Erlöse abrunden), Menge × Preis < 2^53 (MaxQty). Ungültige Eingaben (NaN, ±inf,
--  negative Mengen) ergeben 0 – nie einen Fehler.
--
--  Öffentliche API (§C6.2; optionale letzte Parameter sind abwärtskompatible Ergänzungen):
--    PortfolioMath.Fee(gross, bps, minFee): number             ceil(gross · bps / 10.000), mindestens minFee (gross > 0)
--    PortfolioMath.BuyCost(q, ask, bps, minFee?): number       q · ask + Gebühr (Mindestgebühr Std. 100 Cent = 1 AKY)
--    PortfolioMath.SellProceeds(q, bid, bps, minFee?): number  q · bid − min(Brutto, Gebühr), abgerundet
--    PortfolioMath.Basis(p, q): number                         anteiliger Einstand für q Stück (Verhältnis ≤ 1)
--    PortfolioMath.Nav(d, bids): number                        Cash + Σ Q · Bid (fehlt ein Bid: Einstand C)
--    PortfolioMath.Withdrawable(nav, free, basis, capPct, threshold): number
--                                                              §B8.2: 0 unter threshold·Basis, sonst
--                                                              max(0, min(free, nav − basis, capPct · basis))
--    PortfolioMath.DayReturn(navStart, navEnd, flow): number   Modified Dietz (navEnd − navStart − F) / (navStart + F/2)
--    PortfolioMath.Twr(returns): number                        Π(1 + r) − 1
--    PortfolioMath.AvgDaily(twr, days): number                 (1 + TWR)^(1/Tage) − 1
--    PortfolioMath.SkillScore(returns, maxDD): number          MARKET §12.6, ganzzahlig 0 … 1000
--    PortfolioMath.MaxQty(ask, posCap): number                 min(floor(posCap / ask), floor((2^53 − 1) / (2 · ask)))
--  Helfer:
--    PortfolioMath.MaxDrawdown(returns): number                größter Rückgang der Kapitalkurve (0 … 1)
--    PortfolioMath.AffordableQty(free, px, bps, minFee?): number   größte Menge mit BuyCost ≤ free
--    PortfolioMath.Weight(posValue, gross, nav): number        (Positionswert + Kauf) / Depotwert
--    PortfolioMath.MIN_FEE (100) · PortfolioMath.MAX_SAFE (2^53) · PortfolioMath.SHARPE_DAYS (6)
-- =====================================================================

local PortfolioMath = {}

-- Lokale Typen (strukturell gleich Shared/Types – hier ohne require, damit das Modul CLI-testbar bleibt)
export type Position = { Q: number, C: number, R: number, [string]: any }
export type DepotLike = { Cash: number, Pos: { [string]: Position }, [string]: any }

PortfolioMath.MIN_FEE = 100 -- Mindestgebühr 1 AKY (Config.Trading.MinFeeCents)
PortfolioMath.MAX_SAFE = 2 ^ 53 -- ab hier sind Luau-Zahlen keine exakten Ganzzahlen mehr
PortfolioMath.SHARPE_DAYS = 6 -- Sharpe zählt erst ab so vielen Börsentagen (MARKET §12.6)

local HUGE = math.huge
local STD_FLOOR = 0.005 -- Std-Untergrenze 0,5 % (sonst explodiert Sharpe bei sehr ruhigen Wochen)
local DD_FULL = 0.20 -- 20 % Drawdown = 0 Punkte im Drawdown-Teil
local EPS = 1e-7

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= HUGE and n ~= -HUGE
end

local function int(n: any): number
	if not finite(n) then
		return 0
	end
	return math.floor(n)
end

local function feeOf(gross: number, bps: number, minFee: number): number
	if gross <= 0 then
		return 0
	end
	-- exakt auch für große Beträge: ganze 10.000er-Blöcke getrennt vom Rest rechnen (kein Produkt > 2^53)
	local whole = gross // 10000
	local rest = gross - whole * 10000
	local fee = whole * bps + math.ceil(rest * bps / 10000 - EPS)
	return math.max(minFee, fee)
end

-- ---------------------------------------------------------------------
-- 1) GEBÜHREN, KOSTEN, ERLÖSE
-- ---------------------------------------------------------------------
function PortfolioMath.Fee(gross: number, bps: number, minFee: number): number
	local g = int(gross)
	local b = if finite(bps) and bps > 0 then bps else 0
	local m = if finite(minFee) and minFee > 0 then math.floor(minFee) else 0
	return feeOf(g, b, m)
end

function PortfolioMath.BuyCost(q: number, ask: number, bps: number, minFee: number?): number
	local qty, px = int(q), int(ask)
	if qty <= 0 or px <= 0 then
		return 0
	end
	local gross = qty * px
	return gross + PortfolioMath.Fee(gross, bps, minFee or PortfolioMath.MIN_FEE)
end

function PortfolioMath.SellProceeds(q: number, bid: number, bps: number, minFee: number?): number
	local qty, px = int(q), int(bid)
	if qty <= 0 or px <= 0 then
		return 0
	end
	local gross = qty * px
	local fee = math.min(gross, PortfolioMath.Fee(gross, bps, minFee or PortfolioMath.MIN_FEE))
	return math.floor(gross - fee)
end

-- Anteiliger Einstand (inkl. Gebühren) für q von p.Q Stück; ganze Position -> exakt p.C (kein Rundungsrest)
function PortfolioMath.Basis(p: Position, q: number): number
	if type(p) ~= "table" then
		return 0
	end
	local total, cost, qty = int(p.Q), int(p.C), int(q)
	if total <= 0 or qty <= 0 then
		return 0
	end
	if qty >= total then
		return cost
	end
	return math.floor(cost * (qty / total) + 0.5)
end

-- Depotwert: Cash + Σ Q · Bid (Long vorsichtig zum Bid). bids[instId] in Cent; fehlt ein Kurs -> Einstand.
function PortfolioMath.Nav(d: DepotLike, bids: { [number]: number }): number
	if type(d) ~= "table" then
		return 0
	end
	local nav = int(d.Cash)
	if type(d.Pos) == "table" then
		for key, p in pairs(d.Pos) do
			if type(p) == "table" then
				local qty = int(p.Q)
				if qty > 0 then
					local id = tonumber(key)
					local bid = if id ~= nil and type(bids) == "table" then bids[id] else nil
					if finite(bid) and (bid :: number) > 0 then
						nav += qty * math.floor(bid :: number)
					else
						nav += math.max(0, int(p.C))
					end
				end
			end
		end
	end
	return nav
end

-- ---------------------------------------------------------------------
-- 2) GEWINN-TRANSFER (§B8.2)
-- ---------------------------------------------------------------------
function PortfolioMath.Withdrawable(nav: number, free: number, basis: number, capPct: number, threshold: number): number
	local n, f, b = int(nav), int(free), int(basis)
	if b <= 0 or f <= 0 then
		return 0
	end
	local t = if finite(threshold) then threshold else 1
	-- Schwelle als Ganzzahl (1,02 · 2.500.000 = 2.550.000 exakt, ohne Fließkomma-Rest)
	local slack = math.max(EPS, b * 1e-12) -- relativer Puffer gegen Fließkomma-Rest bei großen Basen
	local needed = math.ceil(b * t - slack)
	if n < needed then
		return 0
	end
	local cap = if finite(capPct) and capPct > 0 then math.floor(b * capPct + slack) else 0
	return math.max(0, math.min(f, n - b, cap))
end

-- ---------------------------------------------------------------------
-- 3) RENDITEN & LIGA (MARKET §12.6, DESIGN §B11.1)
-- ---------------------------------------------------------------------
function PortfolioMath.DayReturn(navStart: number, navEnd: number, flow: number): number
	if not (finite(navStart) and finite(navEnd)) then
		return 0
	end
	local f = if finite(flow) then flow else 0
	local denom = navStart + 0.5 * f
	if denom <= 0 then
		return 0
	end
	local r = (navEnd - navStart - f) / denom
	return if finite(r) then r else 0
end

function PortfolioMath.Twr(returns: { number }): number
	local growth = 1
	if type(returns) == "table" then
		for _, r in ipairs(returns) do
			if finite(r) then
				growth *= math.max(0, 1 + r)
			end
		end
	end
	return growth - 1
end

function PortfolioMath.AvgDaily(twr: number, days: number): number
	if not finite(twr) or not finite(days) or days <= 0 then
		return 0
	end
	local base = 1 + twr
	if base <= 0 then
		return -1
	end
	local avg = base ^ (1 / days) - 1
	return if finite(avg) then avg else 0
end

-- Größter Rückgang der Kapitalkurve aus Tagesrenditen (0 = nie gefallen, 1 = alles weg)
function PortfolioMath.MaxDrawdown(returns: { number }): number
	local equity, peak, worst = 1, 1, 0
	if type(returns) == "table" then
		for _, r in ipairs(returns) do
			if finite(r) then
				equity *= math.max(0, 1 + r)
				if equity > peak then
					peak = equity
				elseif peak > 0 then
					worst = math.max(worst, (peak - equity) / peak)
				end
			end
		end
	end
	return math.clamp(worst, 0, 1)
end

-- Skill-Score 0–1000: 400·tanh(Sharpe/1,5) + 300·Anteil positiver Tage + 300·(1 − min(1, MaxDD/20 %)).
-- Sharpe = Mittel / Std (Stichprobe, Untergrenze 0,5 %) und zählt erst ab 6 Tagen. Keine Tage -> 0.
function PortfolioMath.SkillScore(returns: { number }, maxDD: number): number
	local clean: { number } = {}
	if type(returns) == "table" then
		for _, r in ipairs(returns) do
			if finite(r) then
				table.insert(clean, r)
			end
		end
	end
	local n = #clean
	if n == 0 then
		return 0
	end
	local sum, positive = 0, 0
	for _, r in ipairs(clean) do
		sum += r
		if r > 0 then
			positive += 1
		end
	end
	local mean = sum / n
	local sharpe = 0
	if n >= PortfolioMath.SHARPE_DAYS then
		local sq = 0
		for _, r in ipairs(clean) do
			sq += (r - mean) ^ 2
		end
		local std = math.max(STD_FLOOR, math.sqrt(sq / (n - 1)))
		sharpe = mean / std
	end
	local dd = if finite(maxDD) then math.clamp(maxDD, 0, 1) else 1
	local score = 400 * math.tanh(sharpe / 1.5) + 300 * (positive / n) + 300 * (1 - math.min(1, dd / DD_FULL))
	if not finite(score) then
		return 0
	end
	return math.clamp(math.floor(score + 0.5), 0, 1000)
end

-- ---------------------------------------------------------------------
-- 4) MENGEN & GEWICHTE
-- ---------------------------------------------------------------------
-- Größte erlaubte Stückzahl: Positions-Grenze (Cent) und Präzisions-Grenze Q · Preis < 2^53 (MARKET §12.2)
function PortfolioMath.MaxQty(ask: number, posCap: number): number
	local px = int(ask)
	if px <= 0 then
		return 0
	end
	local safe = math.floor((PortfolioMath.MAX_SAFE - 1) / (px * 2))
	local byCap = if finite(posCap) then math.floor(math.max(0, posCap) / px) else safe
	return math.max(0, math.min(byCap, safe))
end

-- Größte Menge, deren Kosten inkl. Gebühr in "free" passen (Betrags-Chips 10 % · 25 % · Max)
function PortfolioMath.AffordableQty(free: number, px: number, bps: number, minFee: number?): number
	local budget, price = int(free), int(px)
	if budget <= 0 or price <= 0 then
		return 0
	end
	local b = if finite(bps) and bps > 0 then bps else 0
	local m = if minFee ~= nil and finite(minFee) and minFee > 0 then math.floor(minFee) else PortfolioMath.MIN_FEE
	local cap = math.min(math.floor(budget / price), math.floor((PortfolioMath.MAX_SAFE - 1) / (price * 2)))
	local function fits(q: number): boolean
		return q * price + feeOf(q * price, b, m) <= budget
	end
	-- Schätzung über den Gebührensatz; liegt die Gebühr dort noch unter der Mindestgebühr, gilt die Mindestgebühr
	local q = math.min(cap, math.floor(budget / (price * (1 + b / 10000))))
	if q > 0 and feeOf(q * price, b, m) <= m then
		q = math.min(cap, math.floor((budget - m) / price))
	end
	q = math.max(0, q)
	-- exakte Nachkorrektur (Aufrunden der Gebühr verschiebt höchstens um wenige Stück)
	for _ = 1, 64 do
		if q > 0 and not fits(q) then
			q -= 1
		else
			break
		end
	end
	for _ = 1, 64 do
		if q < cap and fits(q + 1) then
			q += 1
		else
			break
		end
	end
	return if q > 0 and fits(q) then q else 0
end

function PortfolioMath.Weight(posValue: number, gross: number, nav: number): number
	local n = if finite(nav) then nav else 0
	if n <= 0 then
		return HUGE
	end
	local v = (if finite(posValue) then posValue else 0) + (if finite(gross) then gross else 0)
	return v / n
end

return PortfolioMath
