-- =====================================================================
--  AKYTEX TYCOON – Luau-CLI-Test für Shared/Format (ohne Roblox)
--  Besitzer: WP1 (Kern & Plattform). DESIGN.md §D WP1 "Tests": DE/EN-Trennzeichen, Kürzel bis Brd./Qa,
--  "MAX" ab 9e15, Prozent mit Vorzeichen; dazu Preise in Cent, Multiplikator, Dauer, kaputte Eingaben.
--  Start (im Projektordner):  <scratchpad>/luau-build/luau tests/format.test.luau
-- =====================================================================

local Format = require("../src/shared/Format")

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
		error(("%s erwartet %q, bekommen %q"):format(label or "Wert", tostring(expected), tostring(actual)), 2)
	end
end

local NAN = 0 / 0

-- ---------------------------------------------------------------------
-- Ganze Zahlen & Trennzeichen
-- ---------------------------------------------------------------------
check("Int: Tausendertrennzeichen DE/EN", function()
	eq(Format.Int(0, "de"), "0")
	eq(Format.Int(999, "de"), "999")
	eq(Format.Int(1000, "de"), "1.000")
	eq(Format.Int(1234567, "de"), "1.234.567")
	eq(Format.Int(1234567, "en"), "1,234,567")
	eq(Format.Int(-1234.9, "de"), "-1.234", "abgeschnitten")
	eq(Format.Int(-0.5, "en"), "0", "kein -0")
	eq(Format.Int(8999999999999999, "en"), "8,999,999,999,999,999")
	eq(Format.Int(NAN, "de"), "0")
	eq(Format.Int(math.huge, "de"), "0")
end)

-- ---------------------------------------------------------------------
-- Kürzel bis Brd./Qa
-- ---------------------------------------------------------------------
check("Compact: DE-Kürzel Tsd. … Brd.", function()
	eq(Format.Compact(999, "de"), "999")
	eq(Format.Compact(1000, "de"), "1 Tsd.")
	eq(Format.Compact(1150, "de"), "1,15 Tsd.", "Float-Fall 1150")
	eq(Format.Compact(12345, "de"), "12,3 Tsd.")
	eq(Format.Compact(999999, "de"), "999 Tsd.", "nie 1000 Tsd.")
	eq(Format.Compact(1250000, "de"), "1,25 Mio.")
	eq(Format.Compact(4.35e9, "de"), "4,35 Mrd.")
	eq(Format.Compact(7.1e12, "de"), "7,1 Bio.")
	eq(Format.Compact(2.5e15, "de"), "2,5 Brd.")
	eq(Format.Compact(8.999e15, "de"), "8,99 Brd.", "abgeschnitten, knapp unter MAX")
end)

check("Compact: EN-Kürzel K … Qa", function()
	eq(Format.Compact(1000, "en"), "1K")
	eq(Format.Compact(1150, "en"), "1.15K")
	eq(Format.Compact(12345, "en"), "12.3K")
	eq(Format.Compact(123456, "en"), "123K")
	eq(Format.Compact(1250000, "en"), "1.25M")
	eq(Format.Compact(4.35e9, "en"), "4.35B")
	eq(Format.Compact(7.1e12, "en"), "7.1T")
	eq(Format.Compact(2.5e15, "en"), "2.5Qa")
	eq(Format.Compact(-1500, "en"), "-1.5K")
	eq(Format.Compact(1e3 ^ 2, "en"), "1M")
	eq(Format.Compact(1e12, "en"), "1T")
	eq(Format.Compact(1e15, "en"), "1Qa")
end)

check("MAX ab 9e15", function()
	eq(Format.Compact(9e15, "de"), "MAX")
	eq(Format.Compact(1e30, "en"), "MAX")
	eq(Format.Compact(-9e15, "en"), "-MAX")
	eq(Format.Credits(9e15, "de"), "MAX")
	eq(Format.Credits(math.huge, "de"), "0", "unendlich ist ungültig")
	eq(Format.Credits(8.99e15, "en"), "8.99Qa")
	eq(Format.Aky(9e15, "de"), "MAX AKY")
end)

-- ---------------------------------------------------------------------
-- Geld
-- ---------------------------------------------------------------------
check("Credits", function()
	eq(Format.Credits(0, "de"), "0")
	eq(Format.Credits(9999, "de"), "9.999", "unter 10.000 ausgeschrieben")
	eq(Format.Credits(9999, "en"), "9,999")
	eq(Format.Credits(10000, "de"), "10 Tsd.")
	eq(Format.Credits(1250000, "de"), "1,25 Mio.", "Spec-Beispiel")
	eq(Format.Credits(1250000, "en"), "1.25M", "Spec-Beispiel")
	eq(Format.Credits(-15000, "en"), "-15K")
	eq(Format.Credits(NAN, "en"), "0")
end)

check("Price (Cent)", function()
	eq(Format.Price(12345, "de"), "123,45", "Spec-Beispiel")
	eq(Format.Price(12345, "en"), "123.45")
	eq(Format.Price(123456, "de"), "1.234,56")
	eq(Format.Price(123456, "en"), "1,234.56")
	eq(Format.Price(5, "de"), "0,05")
	eq(Format.Price(-250, "de"), "-2,50")
	eq(Format.Price(0, "en"), "0.00")
	eq(Format.Price(0.4, "en"), "0.00", "gerundet, kein -0")
	eq(Format.Price(-0.4, "en"), "0.00", "kein -0,00")
	eq(Format.Price(NAN, "de"), "0,00")
	eq(Format.Price(2500000, "de"), "25.000,00", "Start-Basis")
end)

check("Aky", function()
	eq(Format.Aky(123456, "de"), "1.234,56 AKY", "Spec-Beispiel DE")
	eq(Format.Aky(123456, "en"), "1,234.56 AKY")
	eq(Format.Aky(123456, "en", true), "1.23K AKY", "kompakt")
	eq(Format.Aky(123456, "de", true), "1,23 Tsd. AKY")
	eq(Format.Aky(99999, "de", true), "999,99 AKY", "unter 1.000 AKY ausgeschrieben")
	eq(Format.Aky(2500000, "en", true), "25K AKY")
	eq(Format.Aky(-5000, "de"), "-50,00 AKY")
	eq(Format.Aky(NAN, "en"), "0.00 AKY")
end)

-- ---------------------------------------------------------------------
-- Verhältnisse
-- ---------------------------------------------------------------------
check("Pct mit Vorzeichen", function()
	eq(Format.Pct(0.0235, "de", 2, true), "+2,35 %", "Spec-Beispiel")
	eq(Format.Pct(0.0235, "en", 2, true), "+2.35%")
	eq(Format.Pct(-0.0235, "de", 2, true), "-2,35 %")
	eq(Format.Pct(-0.0235, "de"), "-2,35 %", "negativ immer mit Minus")
	eq(Format.Pct(0.0235, "de"), "2,35 %", "ohne signed kein Plus")
	eq(Format.Pct(0, "de", 2, true), "0,00 %", "0 ohne Vorzeichen")
	eq(Format.Pct(-0.00001, "en", 2, true), "0.00%", "kein -0,00")
	eq(Format.Pct(0.5, "de", 0), "50 %")
	eq(Format.Pct(0.123456, "en", 4), "12.3456%")
	eq(Format.Pct(12.5, "de", 1, true), "+1.250,0 %", "Tausender")
	eq(Format.Pct(NAN, "en"), "0.00%")
	eq(Format.Pct(0.02, "en", 9), "2.0000%", "digits auf 4 geklemmt")
end)

check("Mult", function()
	eq(Format.Mult(7.4, "de"), "x7,4", "Spec-Beispiel")
	eq(Format.Mult(7.4, "en"), "x7.4")
	eq(Format.Mult(1.1, "de"), "x1,1")
	eq(Format.Mult(1.25, "de"), "x1,25")
	eq(Format.Mult(2, "en"), "x2")
	eq(Format.Mult(1.8249999, "en"), "x1.82")
	eq(Format.Mult(1.825, "en"), "x1.83", "gerundet")
	eq(Format.Mult(NAN, "en"), "x1")
end)

-- ---------------------------------------------------------------------
-- Dauer
-- ---------------------------------------------------------------------
check("Duration", function()
	eq(Format.Duration(187, "de"), "3:07", "Spec-Beispiel")
	eq(Format.Duration(0, "en"), "0:00")
	eq(Format.Duration(59.9, "en"), "0:59")
	eq(Format.Duration(3599, "de"), "59:59")
	eq(Format.Duration(18720, "de"), "5 h 12 min", "Spec-Beispiel")
	eq(Format.Duration(18720, "en"), "5 h 12 min")
	eq(Format.Duration(3600, "de"), "1 h 0 min")
	eq(Format.Duration(2 * 86400 + 3 * 3600 + 59, "de"), "2 T 3 h")
	eq(Format.Duration(2 * 86400 + 3 * 3600, "en"), "2 d 3 h")
	eq(Format.Duration(-5, "de"), "0:00")
	eq(Format.Duration(NAN, "de"), "0:00")
	eq(Format.Duration(math.huge, "de"), "0:00")
end)

check("Unbekannte Sprache = Englisch", function()
	eq(Format.Credits(1250000, "fr" :: any), "1.25M")
	eq(Format.Price(123456, nil :: any), "1,234.56")
end)

-- ---------------------------------------------------------------------
print(("[format.test] %d/%d PASS"):format(passed, passed + failed))
if failed > 0 then
	for _, failure in ipairs(failures) do
		print("  FAIL " .. failure)
	end
	error(("%d Test(s) fehlgeschlagen"):format(failed))
end
