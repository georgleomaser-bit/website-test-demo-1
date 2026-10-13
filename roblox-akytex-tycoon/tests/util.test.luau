-- =====================================================================
--  AKYTEX TYCOON – Luau-CLI-Test für Shared/Util (ohne Roblox)
--  Besitzer: WP1 (Kern & Plattform). DESIGN.md §D WP1 "Tests" (CC-Fälle FormatNumber bis 1e33, WeightedPick 0/NaN,
--  Limiter mit künstlicher Uhr, IsoWeek(2026-10-13) = 202642).
--  Start (im Projektordner):  <scratchpad>/luau-build/luau tests/util.test.luau
--  Bei einem Fehler endet das Skript mit error(...) -> Exit-Code ≠ 0.
-- =====================================================================

local Util = require("../src/shared/Util")

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

-- Künstliche Uhr für RateLimiter/TokenBucket
local fakeNow = 0
local function clock(): number
	return fakeNow
end

-- Fester "Zufall": NextNumber liefert der Reihe nach die Werte aus der Liste
local function fakeRandom(values: { number }): any
	local index = 0
	return {
		NextNumber = function(_self: any): number
			index += 1
			return values[((index - 1) % #values) + 1]
		end,
	}
end

-- ---------------------------------------------------------------------
-- FormatNumber (REUSE §7 #33)
-- ---------------------------------------------------------------------
check("FormatNumber: Fälle aus REUSE §7 #33", function()
	eq(Util.FormatNumber(1150), "1.15K", "1150")
	eq(Util.FormatNumber(4350000), "4.35M", "4350000")
	eq(Util.FormatNumber(1e33), "1Dc", "1e33")
	eq(Util.FormatNumber(math.huge), "MAX", "math.huge")
	eq(Util.FormatNumber(-math.huge), "-MAX", "-math.huge")
	eq(Util.FormatNumber(-0.5), "0", "-0.5")
	eq(Util.FormatNumber(0 / 0), "0", "NaN")
end)

check("FormatNumber: kleine Zahlen und Rundung", function()
	eq(Util.FormatNumber(0), "0")
	eq(Util.FormatNumber(7.9), "7")
	eq(Util.FormatNumber(999), "999")
	eq(Util.FormatNumber(999.99), "999")
	eq(Util.FormatNumber(-1), "-1")
	eq(Util.FormatNumber(-1500), "-1.5K")
	eq(Util.FormatNumber(1000), "1K")
	eq(Util.FormatNumber(1234), "1.23K")
	eq(Util.FormatNumber(12345), "12.3K")
	eq(Util.FormatNumber(123456), "123K")
	eq(Util.FormatNumber(999999), "999K") -- nie "1000K"
	eq(Util.FormatNumber(15000000), "15M")
	eq(Util.FormatNumber(1e6), "1M")
end)

check("FormatNumber: jede 1000er-Potenz bis 1e36", function()
	local suffixes = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
	for power = 0, 11 do
		eq(Util.FormatNumber(1000 ^ power), "1" .. suffixes[power + 1], "1e" .. power * 3)
		local expected = if power == 0 then "2" else "2.5" .. suffixes[power + 1] -- unter 1000 ganzzahlig
		eq(Util.FormatNumber(1000 ^ power * 2.5), expected, "2.5e" .. power * 3)
	end
	eq(Util.FormatNumber(1e36), "1000Dc", "1e36")
	eq(Util.FormatNumber(5e40), "50000000Dc", "5e40")
end)

-- ---------------------------------------------------------------------
-- FormatTime
-- ---------------------------------------------------------------------
check("FormatTime", function()
	eq(Util.FormatTime(187), "3:07")
	eq(Util.FormatTime(18720), "5h 12m")
	eq(Util.FormatTime(0), "0:00")
	eq(Util.FormatTime(59.9), "0:59")
	eq(Util.FormatTime(3600), "1h 0m")
	eq(Util.FormatTime(-5), "0:00")
	eq(Util.FormatTime(0 / 0), "0:00")
	eq(Util.FormatTime(math.huge), "0:00")
end)

-- ---------------------------------------------------------------------
-- Tabellen
-- ---------------------------------------------------------------------
check("DeepCopy ist unabhängig", function()
	local original = { A = 1, B = { C = 2, D = { 3, 4 } } }
	local copy = Util.DeepCopy(original)
	copy.B.C = 99
	copy.B.D[1] = 99
	eq(original.B.C, 2)
	eq(original.B.D[1], 3)
	eq(Util.DeepCopy(5), 5)
	eq(Util.DeepCopy("x"), "x")
end)

check("Reconcile ergänzt nur Fehlendes", function()
	local target: any = { A = 5, B = { X = 1 } }
	local template = { A = 0, B = { X = 0, Y = 2 }, C = { 1, 2 } }
	Util.Reconcile(target, template)
	eq(target.A, 5)
	eq(target.B.X, 1)
	eq(target.B.Y, 2)
	eq(#target.C, 2)
	target.C[1] = 9
	eq(template.C[1], 1, "Vorlage unverändert")
end)

check("Snapshot liefert alle Schlüssel", function()
	local keys = Util.Snapshot({ a = 1, b = 2, c = 3 })
	table.sort(keys)
	eq(#keys, 3)
	eq(table.concat(keys, ","), "a,b,c")
end)

-- ---------------------------------------------------------------------
-- WeightedPick
-- ---------------------------------------------------------------------
check("WeightedPick: Gewicht 0/NaN/negativ/unendlich nie gewählt", function()
	local list = {
		{ Id = "zero", Weight = 0 },
		{ Id = "nan", Weight = 0 / 0 },
		{ Id = "neg", Weight = -5 },
		{ Id = "inf", Weight = math.huge },
		{ Id = "ok", Weight = 3 },
	}
	for _, roll in ipairs({ 0, 0.0001, 0.5, 0.9999, 1 }) do
		local pick = Util.WeightedPick(list, nil, fakeRandom({ roll }))
		eq(pick and pick.Id, "ok", "roll " .. roll)
	end
end)

check("WeightedPick: alle 0 oder leer -> nil", function()
	eq(Util.WeightedPick({ { Weight = 0 }, { Weight = 0 / 0 } }, nil, fakeRandom({ 0.5 })), nil)
	eq(Util.WeightedPick({}, nil, fakeRandom({ 0.5 })), nil)
end)

check("WeightedPick: Verteilung nach Gewicht + eigene weightOf", function()
	local list = { "a", "b", "c" }
	local weights = { a = 1, b = 2, c = 1 }
	local function weightOf(item: string): number
		return weights[item]
	end
	eq(Util.WeightedPick(list, weightOf, fakeRandom({ 0.1 })), "a") -- 0.4 von 4
	eq(Util.WeightedPick(list, weightOf, fakeRandom({ 0.3 })), "b") -- 1.2
	eq(Util.WeightedPick(list, weightOf, fakeRandom({ 0.74 })), "b") -- 2.96
	eq(Util.WeightedPick(list, weightOf, fakeRandom({ 0.9 })), "c") -- 3.6
	-- kaputte weightOf-Funktion zählt als Gewicht 0
	local function broken(item: string): number
		if item == "a" then
			error("kaputt")
		end
		return 1
	end
	eq(Util.WeightedPick(list, broken, fakeRandom({ 0 })), "b")
end)

-- ---------------------------------------------------------------------
-- RateLimiter / TokenBucket (künstliche Uhr)
-- ---------------------------------------------------------------------
check("RateLimiter: gleitendes Fenster", function()
	fakeNow = 0
	local limiter = Util.RateLimiter(3, 1, clock)
	eq(limiter.Check("p"), true)
	eq(limiter.Check("p"), true)
	eq(limiter.Check("p"), true)
	eq(limiter.Check("p"), false, "4. Aufruf")
	eq(limiter.Check("other"), true, "anderer Schlüssel")
	fakeNow = 0.99
	eq(limiter.Check("p"), false, "noch im Fenster")
	fakeNow = 1.0
	eq(limiter.Check("p"), true, "Fenster vorbei")
	limiter.Clear("p")
	eq(limiter.Check("p"), true)
	eq(limiter.Check("p"), true)
	eq(limiter.Check("p"), true)
	eq(limiter.Check("p"), false, "nach Clear wieder 3")
end)

check("TokenBucket: voll starten, nachfüllen, Kapazität", function()
	fakeNow = 0
	local bucket = Util.TokenBucket(12, 20, clock)
	for i = 1, 12 do
		eq(bucket.Take("p"), true, "Marke " .. i)
	end
	eq(bucket.Take("p"), false, "leer")
	fakeNow = 0.05 -- +1 Marke
	eq(bucket.Take("p"), true)
	eq(bucket.Take("p"), false)
	fakeNow = 100 -- nie über die Kapazität
	eq(bucket.Take("p", 12), true)
	eq(bucket.Take("p"), false)
	eq(bucket.Take("p", 0 / 0), false, "NaN")
	eq(bucket.Take("p", -1), false, "negativ")
	bucket.Clear("p")
	eq(bucket.Take("p", 12), true, "nach Clear voll")
	-- Uhr läuft rückwärts -> kein Geschenk
	fakeNow = 50
	eq(bucket.Take("p"), false)
end)

-- ---------------------------------------------------------------------
-- Zahlen prüfen
-- ---------------------------------------------------------------------
check("IsFinite", function()
	eq(Util.IsFinite(1), true)
	eq(Util.IsFinite(-1e300), true)
	eq(Util.IsFinite(0 / 0), false)
	eq(Util.IsFinite(math.huge), false)
	eq(Util.IsFinite(-math.huge), false)
	eq(Util.IsFinite("1"), false)
	eq(Util.IsFinite(nil), false)
	eq(Util.IsFiniteVector(nil), false)
	eq(Util.IsFiniteVector({ X = 1, Y = 2, Z = 3 }), false, "Tabelle ist kein Vector3")
end)

-- ---------------------------------------------------------------------
-- Datum
-- ---------------------------------------------------------------------
check("UtcDay", function()
	Util.SetDayOffset(0)
	eq(Util.UtcDay(0), 0)
	eq(Util.UtcDay(86399), 0)
	eq(Util.UtcDay(86400), 1)
	eq(Util.UtcDay(1791676800), 20737) -- 2026-10-11
	Util.SetDayOffset(2)
	eq(Util.UtcDay(0), 2, "mit Debug-Versatz")
	Util.SetDayOffset(0 / 0) -- ignoriert
	eq(Util.GetDayOffset(), 2)
	Util.SetDayOffset(0)
	eq(Util.UtcDay(0), 0)
end)

check("IsoWeek", function()
	Util.SetDayOffset(0)
	eq(Util.IsoWeek(1791676800), 202641, "2026-10-11")
	eq(Util.IsoWeek(1791720000), 202641, "2026-10-11 12:00")
	eq(Util.IsoWeek(1798804800), 202653, "2027-01-01")
	eq(Util.IsoWeek(1798459200), 202653, "2026-12-28")
	eq(Util.IsoWeek(1609675200), 202053, "2021-01-03")
	eq(Util.IsoWeek(1735560000), 202501, "2024-12-30")
	eq(Util.IsoWeek(1767268800), 202601, "2026-01-01")
	eq(Util.IsoWeek(43200), 197001, "1970-01-01")
	eq(Util.IsoWeek(1791849600), 202642, "2026-10-13 (DESIGN §D WP1)")
	eq(Util.IsoWeek(1767571200), 202602, "2026-01-05 (Clock.EPOCH, Montag)")
end)

-- ---------------------------------------------------------------------
-- Hash (FNV-1a 32 Bit, auf 0..2^31-1 begrenzt)
-- ---------------------------------------------------------------------
check("Hash", function()
	eq(Util.Hash(""), 18652613) -- 2166136261 & 0x7FFFFFFF
	eq(Util.Hash("a"), 1678518572) -- 0xE40C292C & 0x7FFFFFFF
	eq(Util.Hash("foobar"), 0xBF9CF968 % 0x80000000)
	eq(Util.Hash("abc"), Util.Hash("abc"), "deterministisch")
	for _, text in ipairs({ "x", "game-job-id-1234", string.rep("z", 500) }) do
		local h = Util.Hash(text)
		assert(h >= 0 and h <= 2 ^ 31 - 1 and h % 1 == 0, "Bereich " .. text)
	end
end)

-- ---------------------------------------------------------------------
print(("[util.test] %d/%d PASS"):format(passed, passed + failed))
if failed > 0 then
	for _, failure in ipairs(failures) do
		print("  FAIL " .. failure)
	end
	error(("%d Test(s) fehlgeschlagen"):format(failed))
end
