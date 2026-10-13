-- =====================================================================
--  AKYTEX TYCOON – Luau-CLI-Test für Shared/Market/PortfolioMath (ohne Roblox)
--  Besitzer: WP4 (Orders, Depot, Bots). DESIGN.md §D WP4 "Tests": Gebühren-Rundung, Basis-Verhältnis,
--  Withdrawable (§B8.2), Modified Dietz, TWR, Ø-Tagesrendite, Skill-Score-Grenzfälle (MARKET §12.6),
--  MaxQty < 2^53, Kaufen + Sofortverkauf ≤ 0 (1.000 Zufallsfälle, Abnahme WP4 #1).
--  Start (im Projektordner):  <scratchpad>/luau-build/luau tests/portfoliomath.test.luau
-- =====================================================================

local PM = require("../src/shared/Market/PortfolioMath")

local passed, failed = 0, 0
local failures: { string } = {}

local function check(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		table.insert(failures, name .. ": " .. tostring(err))
	end
end

local function eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(("%s erwartet %s, bekommen %s"):format(label or "Wert", tostring(expected), tostring(actual)), 2)
	end
end

local function near(actual: number, expected: number, tolerance: number, label: string?)
	if math.abs(actual - expected) > tolerance then
		error(("%s erwartet ≈%.10f, bekommen %.10f"):format(label or "Wert", expected, actual), 2)
	end
end

local NAN = 0 / 0
local HUGE = math.huge

-- ---------------------------------------------------------------------
-- Gebühren & Kosten
-- ---------------------------------------------------------------------
check("Fee: aufgerundet, Mindestgebühr 1 AKY", function()
	eq(PM.Fee(10000, 10, 100), 100, "10 Cent Gebühr -> Mindestgebühr")
	eq(PM.Fee(1234567, 10, 100), 1235, "ceil(1234,567)")
	eq(PM.Fee(1230000, 10, 100), 1230, "glatt ohne Aufrunden")
	eq(PM.Fee(1230001, 10, 100), 1231, "ein Cent mehr -> aufrunden")
	eq(PM.Fee(1000000, 8, 100), 800, "Trader 0,08 %")
	eq(PM.Fee(1000000, 3, 0), 300, "Legende 0,03 %")
	eq(PM.Fee(0, 10, 100), 0, "kein Brutto, keine Gebühr")
	eq(PM.Fee(-5, 10, 100), 0, "negativ -> 0")
	eq(PM.Fee(NAN, 10, 100), 0, "NaN -> 0")
	eq(PM.Fee(1000000, NAN, 100), 100, "NaN-Satz -> nur Mindestgebühr")
end)

check("Fee: exakt auch bei sehr großen Beträgen", function()
	eq(PM.Fee(8e15, 10, 100), 8e12, "8e15 × 10 bp")
	eq(PM.Fee(8e15 + 1, 10, 100), 8e12 + 1, "Rest-Cent wird aufgerundet")
	eq(PM.Fee(4503599627370495, 3, 0), 1351079888212, "2^52 − 1 bei 3 bp (ceil)")
end)

check("BuyCost / SellProceeds", function()
	eq(PM.BuyCost(10, 10000, 10), 100100, "10 × 100 AKY + 1 AKY")
	eq(PM.BuyCost(10, 10000, 10, 0), 100100, "ohne Mindestgebühr: 0,1 % = 100")
	eq(PM.SellProceeds(10, 9990, 10), 99800, "99.900 − 100")
	eq(PM.SellProceeds(1, 50, 10), 0, "Gebühr nie größer als Brutto")
	eq(PM.BuyCost(0, 10000, 10), 0, "0 Stück")
	eq(PM.SellProceeds(-3, 10000, 10), 0, "negative Menge")
	eq(PM.BuyCost(2.7, 10000, 10), 20100, "Menge abgeschnitten")
end)

-- kleiner deterministischer Zufall (die Luau-CLI kennt kein Random)
local seed = 20261013
local function nextInt(lo: number, hi: number): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return lo + seed % (hi - lo + 1)
end
local rng = {
	NextInteger = function(_self: any, lo: number, hi: number): number
		return nextInt(lo, hi)
	end,
}

check("Kaufen + Sofortverkauf ist nie positiv (1.000 Zufallsfälle)", function()
	for n = 1, 1000 do
		local mid = rng:NextInteger(50, 9999999)
		local spread = math.max(1, math.floor(mid * rng:NextInteger(1, 40) / 10000 + 0.5))
		local bid = math.max(1, mid - spread // 2)
		local ask = bid + spread
		local bps = ({ 10, 8, 5, 3 })[rng:NextInteger(1, 4)]
		local q = rng:NextInteger(1, math.max(1, PM.MaxQty(ask, 5e9)))
		q = math.min(q, 100000)
		local cost = PM.BuyCost(q, ask, bps)
		local back = PM.SellProceeds(q, bid, bps)
		if back - cost > 0 then
			error(("Fall %d: Gewinn %d (q=%d ask=%d bid=%d bps=%d)"):format(n, back - cost, q, ask, bid, bps))
		end
		-- auch ohne Spread (bid == ask) nie positiv
		if PM.SellProceeds(q, ask, bps) - cost > 0 then
			error(("Fall %d: Gewinn ohne Spread"):format(n))
		end
	end
end)

-- ---------------------------------------------------------------------
-- Einstand & Depotwert
-- ---------------------------------------------------------------------
check("Basis: anteilig gerundet, ganze Position exakt", function()
	local p = { Q = 3, C = 100, R = 0 }
	eq(PM.Basis(p, 1), 33, "1/3")
	eq(PM.Basis(p, 2), 67, "2/3")
	eq(PM.Basis(p, 3), 100, "alles = C")
	eq(PM.Basis(p, 5), 100, "mehr als da -> C")
	eq(PM.Basis(p, 0), 0, "0 Stück")
	eq(PM.Basis({ Q = 0, C = 50, R = 0 }, 1), 0, "leere Position")
	-- Summe der Teilverkäufe ergibt nie mehr als C (der Rest bleibt im letzten Verkauf)
	local q, c, sum = 7, 1000, 0
	for _ = 1, 6 do
		local part = PM.Basis({ Q = q, C = c, R = 0 }, 1)
		sum += part
		q -= 1
		c -= part
	end
	sum += PM.Basis({ Q = q, C = c, R = 0 }, q)
	eq(sum, 1000, "Teilverkäufe summieren sich exakt")
end)

check("Nav: Cash + Q · Bid, fehlender Kurs -> Einstand", function()
	local d = {
		Cash = 1000,
		Pos = { ["5"] = { Q = 10, C = 900, R = 0 }, ["7"] = { Q = 2, C = 500, R = 0 } },
	}
	eq(PM.Nav(d :: any, { [5] = 95, [7] = 300 }), 1000 + 950 + 600, "beide Kurse")
	eq(PM.Nav(d :: any, { [5] = 95 }), 1000 + 950 + 500, "Kurs 7 fehlt -> C")
	eq(PM.Nav({ Cash = 5, Pos = {} } :: any, {}), 5, "nur Cash")
	eq(PM.Nav(nil :: any, {}), 0, "kein Depot")
end)

-- ---------------------------------------------------------------------
-- Gewinn-Transfer (§B8.2)
-- ---------------------------------------------------------------------
check("Withdrawable: Schwelle 1,02, Tageslimit 6 %, freies Cash", function()
	local basis = 2500000
	eq(PM.Withdrawable(2549999, 1000000, basis, 0.06, 1.02), 0, "knapp unter 1,02 × Basis")
	eq(PM.Withdrawable(2550000, 1000000, basis, 0.06, 1.02), 50000, "genau 1,02 -> NAV − Basis")
	eq(PM.Withdrawable(3000000, 1000000, basis, 0.06, 1.02), 150000, "Deckel 6 % der Basis")
	eq(PM.Withdrawable(3000000, 20000, basis, 0.06, 1.02), 20000, "nur freies Cash")
	eq(PM.Withdrawable(3000000, 0, basis, 0.06, 1.02), 0, "kein freies Cash")
	eq(PM.Withdrawable(2537500, 1000000, basis, 0.06, 0), 37500, "Tutorial-Ausnahme ohne Schwelle")
	eq(PM.Withdrawable(2400000, 1000000, basis, 0.06, 0), 0, "unter der Basis nie etwas")
	eq(PM.Withdrawable(3000000, 1000000, 0, 0.06, 1.02), 0, "Basis 0 -> nichts")
	-- große Basis (Legende 60 Mio. AKY): Schwelle ohne Fließkomma-Rest
	local big = 6000000000
	eq(PM.Withdrawable(6120000000, 1e12, big, 0.06, 1.02), 120000000, "Legende genau an der Schwelle")
	eq(PM.Withdrawable(9e9, 1e12, big, 0.06, 1.02), 360000000, "Legende Deckel 6 % = 3,6 Mio. AKY")
end)

check("Rettungsschirm ist nie abhebbar (0,5 × Basis < 1,02 × Basis)", function()
	local basis = 10000000
	local navAfterRefill = basis // 2
	eq(PM.Withdrawable(navAfterRefill, navAfterRefill, basis, 0.06, 1.02), 0, "Starthilfe")
end)

-- ---------------------------------------------------------------------
-- Renditen & Liga
-- ---------------------------------------------------------------------
check("DayReturn (Modified Dietz)", function()
	near(PM.DayReturn(100, 110, 0), 0.1, 1e-12, "ohne Fluss")
	near(PM.DayReturn(100, 160, 50), 10 / 125, 1e-12, "Einzahlung 50")
	near(PM.DayReturn(100, 60, -50), 10 / 75, 1e-12, "Auszahlung 50 (Gewinn-Transfer)")
	eq(PM.DayReturn(0, 100, 0), 0, "Start 0")
	eq(PM.DayReturn(100, 50, -300), 0, "Nenner ≤ 0")
	eq(PM.DayReturn(NAN, 1, 0), 0, "NaN")
end)

check("Twr / AvgDaily", function()
	near(PM.Twr({ 0.1, -0.1 }), -0.01, 1e-12, "1,1 · 0,9 − 1")
	eq(PM.Twr({}), 0, "leer")
	near(PM.Twr({ 0.1, NAN, 0.1 }), 0.21, 1e-12, "NaN wird ignoriert")
	near(PM.AvgDaily(0.21, 2), 0.1, 1e-12, "(1,21)^(1/2) − 1")
	eq(PM.AvgDaily(0.21, 0), 0, "0 Tage")
	eq(PM.AvgDaily(-1, 3), -1, "Totalverlust")
	near(PM.AvgDaily(PM.Twr({ 0.02, 0.02, 0.02 }), 3), 0.02, 1e-12, "konstant 2 %")
end)

check("MaxDrawdown", function()
	near(PM.MaxDrawdown({ 0.1, -0.2, 0.05 }), 0.2, 1e-12, "Spitze 1,1 -> 0,88")
	eq(PM.MaxDrawdown({ 0.01, 0.02 }), 0, "nie gefallen")
	eq(PM.MaxDrawdown({}), 0, "leer")
	near(PM.MaxDrawdown({ -0.5, 0.2, -0.5 }), 1 - 0.5 * 1.2 * 0.5, 1e-12, "von Start 1,0 gemessen")
end)

check("SkillScore: Formel und Grenzfälle", function()
	eq(PM.SkillScore({}, 0), 0, "keine Tage -> 0")
	-- < 6 Tage: Sharpe zählt nicht
	eq(PM.SkillScore({ 0.01, 0.02, 0.01 }, 0), 600, "3 positive Tage, kein Drawdown")
	eq(PM.SkillScore({ -0.01, -0.02, -0.01 }, 0.2), 0, "nur Verluste, 20 % Drawdown")
	-- 6 gleiche Tage: Std-Untergrenze 0,5 % -> Sharpe = 0,01 / 0,005 = 2
	local expected = math.floor(400 * math.tanh(2 / 1.5) + 300 + 300 + 0.5)
	eq(PM.SkillScore({ 0.01, 0.01, 0.01, 0.01, 0.01, 0.01 }, 0), expected, "Std-Untergrenze")
	-- gemischte Woche
	local r = { 0.02, -0.01, 0.015, 0.005, -0.005, 0.01, 0.02 }
	local mean = 0
	for _, x in ipairs(r) do
		mean += x
	end
	mean /= #r
	local sq = 0
	for _, x in ipairs(r) do
		sq += (x - mean) ^ 2
	end
	local std = math.max(0.005, math.sqrt(sq / (#r - 1)))
	local dd = PM.MaxDrawdown(r)
	local want = 400 * math.tanh(mean / std / 1.5) + 300 * (5 / 7) + 300 * (1 - math.min(1, dd / 0.2))
	eq(PM.SkillScore(r, dd), math.floor(want + 0.5), "gemischte Woche")
	-- Drawdown ≥ 20 % -> Drawdown-Teil 0; Ergebnis immer 0 … 1000 und ganzzahlig
	local s = PM.SkillScore({ 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5 }, 0)
	assert(s <= 1000 and s >= 0 and s % 1 == 0, "Bereich")
	eq(PM.SkillScore({ 0.01, 0.01, 0.01 }, 0.5), 300, "Drawdown 50 % -> 0 Drawdown-Punkte")
	eq(PM.SkillScore({ 0.01, 0.01, 0.01 }, NAN), 300, "NaN-Drawdown zählt als voll")
end)

-- ---------------------------------------------------------------------
-- Mengen-Grenzen
-- ---------------------------------------------------------------------
check("MaxQty: Positions-Grenze und Q · Preis < 2^53", function()
	eq(PM.MaxQty(300, 1000000), 3333, "Positions-Grenze")
	eq(PM.MaxQty(0, 1000000), 0, "Preis 0")
	eq(PM.MaxQty(2 ^ 52, HUGE), 0, "riesiger Preis -> 0")
	local ask = 9999999
	local q = PM.MaxQty(ask, HUGE)
	assert(q * ask * 2 < 2 ^ 53, "Präzisions-Grenze eingehalten")
	assert((q + 1) * ask * 2 >= 2 ^ 53 - ask * 2, "nicht unnötig klein")
	eq(PM.MaxQty(100, -5), 0, "negative Grenze")
	eq(PM.MaxQty(100, NAN), PM.MaxQty(100, HUGE), "NaN-Grenze = nur Präzision")
end)

check("AffordableQty: größte bezahlbare Menge inkl. Gebühr", function()
	eq(PM.AffordableQty(100100, 10000, 10), 10, "genau passend")
	eq(PM.AffordableQty(100099, 10000, 10), 9, "ein Cent zu wenig")
	eq(PM.AffordableQty(10050, 10000, 10), 0, "Mindestgebühr verhindert 1 Stück")
	eq(PM.AffordableQty(0, 10000, 10), 0, "kein Geld")
	eq(PM.AffordableQty(5e9, 50, 3), 99970008, "großes Budget")
	assert(PM.BuyCost(99970008, 50, 3) <= 5e9, "Kosten passen")
	assert(PM.BuyCost(99970009, 50, 3) > 5e9, "eins mehr passt nicht")
	-- gegen Durchprobieren (kleine Fälle, alle Gebühren-Bereiche)
	for _ = 1, 300 do
		local price = rng:NextInteger(1, 5000)
		local budget = rng:NextInteger(0, 400000)
		local bps = ({ 10, 8, 5, 3 })[rng:NextInteger(1, 4)]
		local want = 0
		local q = 1
		while PM.BuyCost(q, price, bps) <= budget do
			want = q
			q += 1
		end
		eq(PM.AffordableQty(budget, price, bps), want, ("Budget %d Preis %d"):format(budget, price))
	end
end)

check("Weight", function()
	near(PM.Weight(200, 100, 1000), 0.3, 1e-12, "(200 + 100) / 1000")
	eq(PM.Weight(1, 1, 0), HUGE, "Depotwert 0")
end)

-- ---------------------------------------------------------------------
for _, failure in ipairs(failures) do
	print("FAIL " .. failure)
end
print(("portfoliomath.test: %d/%d PASS"):format(passed, passed + failed))
if failed > 0 then
	error(("%d Test(s) fehlgeschlagen"):format(failed))
end
