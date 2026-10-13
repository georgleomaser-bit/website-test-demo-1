-- =====================================================================
--  AKYTEX TYCOON – Luau-CLI-Test für Shared/Clock (ohne Roblox)
--  Besitzer: WP1 (Kern & Plattform). DESIGN.md §D WP1 "Tests": EPOCH, DayIndex/Minute, Tageszeit, Sommerzeit-Grenzen
--  (Abnahme 6: 2026-03-29 00:59/01:00 UTC und 2026-10-25 00:59/01:00 UTC), NextBerlin über Wochen-/Jahresgrenze.
--  Referenzwerte unabhängig mit Python zoneinfo("Europe/Berlin") berechnet.
--  Start (im Projektordner):  <scratchpad>/luau-build/luau tests/clock.test.luau
-- =====================================================================

local Clock = require("../src/shared/Clock")

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
		error(("%s erwartet ≈%s, bekommen %s"):format(label or "Wert", tostring(expected), tostring(actual)), 2)
	end
end

local DAY = 86400
local OCT13 = 1791849600 -- 2026-10-13 00:00 UTC

-- ---------------------------------------------------------------------
-- EPOCH, Tick, Umrechnung
-- ---------------------------------------------------------------------
check("EPOCH = Mo 2026-01-05 00:00 UTC", function()
	eq(Clock.EPOCH, 1767571200)
	eq(Clock.DAY_TICKS, 1200)
	eq(Clock.WEEK_TICKS, 604800)
	eq(Clock.Weekday(Clock.EPOCH), 1, "Montag")
	eq(Clock.Weekday(OCT13), 2, "2026-10-13 Dienstag")
	eq(Clock.Weekday(1774742400), 7, "2026-03-29 Sonntag")
end)

check("Tick/TickOf/UnixOf", function()
	eq(Clock.TickOf(Clock.EPOCH), 0)
	eq(Clock.TickOf(Clock.EPOCH + 1234.9), 1234, "abgerundet")
	eq(Clock.UnixOf(0), Clock.EPOCH)
	eq(Clock.UnixOf(Clock.TickOf(OCT13)), OCT13)
	eq(Clock.TickOf(0 / 0), -Clock.EPOCH, "NaN -> 0")
	-- Now() ohne Roblox = os.time() (Luau-CLI)
	local tick = Clock.Tick()
	assert(math.abs(tick - (os.time() - Clock.EPOCH)) <= 2, "Tick weicht von os.time ab")
	assert(tick % 1 == 0, "Tick ganzzahlig")
end)

-- ---------------------------------------------------------------------
-- Börsentag & Woche
-- ---------------------------------------------------------------------
check("DayIndex/DayMinute", function()
	eq(Clock.DayIndex(0), 0)
	eq(Clock.DayIndex(1199), 0)
	eq(Clock.DayIndex(1200), 1)
	eq(Clock.DayIndex(-1), -1, "vor EPOCH")
	eq(Clock.DayMinute(0), 0)
	eq(Clock.DayMinute(600), 10, ":10 Welt-Event")
	eq(Clock.DayMinute(1230), 0.5, "Bruchteil")
	near(Clock.DayMinute(1199), 19.9833, 0.001, "letzte Sekunde")
	eq(Clock.DayMinute(-60), 19, "vor EPOCH positiv")
	eq(Clock.DayMinute(0 / 0), 0, "NaN")
	for t = 0, 24000, 37 do
		local m = Clock.DayMinute(t)
		assert(m >= 0 and m < 20, "DayMinute außerhalb [0, 20): " .. t)
	end
	-- 504 Börsentage je Woche
	eq(Clock.DayIndex(Clock.WEEK_TICKS), 504)
end)

check("WeekIndex/WeekStartTick (Wechsel Mo 00:00 UTC)", function()
	eq(Clock.WeekIndex(0), 0)
	eq(Clock.WeekIndex(604799), 0)
	eq(Clock.WeekIndex(604800), 1)
	eq(Clock.WeekStartTick(3), 1814400)
	eq(Clock.WeekIndex(Clock.TickOf(OCT13)), 40, "2026-10-13 = Woche 40 seit EPOCH")
	for w = 0, 60 do
		local unix = Clock.UnixOf(Clock.WeekStartTick(w))
		eq(Clock.Weekday(unix), 1, "Wochenstart Montag " .. w)
		eq(unix % DAY, 0, "Wochenstart 00:00 UTC " .. w)
		eq(Clock.WeekIndex(Clock.WeekStartTick(w)), w)
		eq(Clock.WeekIndex(Clock.WeekStartTick(w) - 1), w - 1)
	end
end)

-- ---------------------------------------------------------------------
-- Tageszeit der Welt (§A4)
-- ---------------------------------------------------------------------
check("ClockTime-Stützpunkte", function()
	near(Clock.ClockTime(0), 6.5, 1e-9, ":00 Sonnenaufgang")
	near(Clock.ClockTime(360), 12, 1e-9, ":06 Mittag")
	near(Clock.ClockTime(720), 18.5, 1e-9, ":12 Sonnenuntergang")
	near(Clock.ClockTime(750), 21, 1e-9, ":12,5 Nacht")
	near(Clock.ClockTime(1110), 4, 1e-9, ":18,5 4 Uhr")
	near(Clock.ClockTime(1170), 5.5, 1e-9, ":19,5 Dämmerung")
	near(Clock.ClockTime(1200), 6.5, 1e-9, "nächster Tag")
	near(Clock.ClockTime(900), 21 + 2.5 / 6 * 7, 1e-9, ":15 kurz vor Mitternacht")
	near(Clock.ClockTime(750 + 3 / 7 * 360), 0, 1e-9, "Mitternacht bei :15,07")
end)

check("ClockTime stetig und im Bereich", function()
	local prev = Clock.ClockTime(0)
	for t = 1, 1200 do
		local ct = Clock.ClockTime(t)
		assert(ct >= 0 and ct < 24, "außerhalb [0, 24): " .. t)
		local step = (ct - prev) % 24
		assert(step < 0.25, ("Sprung bei %d: %s -> %s"):format(t, prev, ct))
		prev = ct
	end
end)

check("IsNight", function()
	eq(Clock.IsNight(0), false, "Sonnenaufgang")
	eq(Clock.IsNight(360), false, "Mittag")
	eq(Clock.IsNight(719), false, "kurz vor Sonnenuntergang")
	eq(Clock.IsNight(720), true, "Sonnenuntergang")
	eq(Clock.IsNight(900), true, "Mitternacht")
	eq(Clock.IsNight(1170), true, "Dämmerung 5,5")
	eq(Clock.IsNight(1190), false, "Morgen")
end)

-- ---------------------------------------------------------------------
-- Berlin-Sommerzeit (Abnahme 6)
-- ---------------------------------------------------------------------
check("BerlinOffset Grenzen 2026", function()
	eq(Clock.BerlinOffset(1774745940), 3600, "2026-03-29 00:59 UTC")
	eq(Clock.BerlinOffset(1774746000), 7200, "2026-03-29 01:00 UTC")
	eq(Clock.BerlinOffset(1792889940), 7200, "2026-10-25 00:59 UTC")
	eq(Clock.BerlinOffset(1792890000), 3600, "2026-10-25 01:00 UTC")
	eq(Clock.BerlinOffset(1782907200), 7200, "Juli")
	eq(Clock.BerlinOffset(1768478400), 3600, "Januar")
end)

check("BerlinOffset andere Jahre + Unsinn", function()
	eq(Clock.BerlinOffset(1806195540), 3600, "2027-03-28 00:59")
	eq(Clock.BerlinOffset(1806195600), 7200, "2027-03-28 01:00")
	eq(Clock.BerlinOffset(1824944340), 7200, "2027-10-31 00:59")
	eq(Clock.BerlinOffset(1824944400), 3600, "2027-10-31 01:00")
	eq(Clock.BerlinOffset(1743296400), 7200, "2025-03-30 01:00")
	eq(Clock.BerlinOffset(1761440340), 7200, "2025-10-26 00:59")
	eq(Clock.BerlinOffset(0 / 0), 3600, "NaN")
	eq(Clock.BerlinOffset(math.huge), 3600, "unendlich")
end)

-- ---------------------------------------------------------------------
-- NextBerlin (Wochen-/Jahresgrenze, Zeitumstellung, strikt danach)
-- ---------------------------------------------------------------------
check("NextBerlin täglich + Wochentag", function()
	eq(Clock.NextBerlin(nil, 19, 0, 1791892800), 1791910800, "täglich 19:00 (Power-Hour)")
	eq(Clock.NextBerlin(5, 19, 0, 1791892800), 1792170000, "Fr 19:00 Crash-Freitag")
	eq(Clock.NextBerlin(1, 0, 0, 1791892800), 1792360800, "Mo 00:00 Berlin")
	eq(Clock.NextBerlin(nil, 19, 0, 1791910800), 1791997200, "strikt nach dem Zeitpunkt")
	eq(Clock.NextBerlin(nil, 19, 0, 1791910799), 1791910800, "eine Sekunde davor")
end)

check("NextBerlin über Zeitumstellung", function()
	eq(Clock.NextBerlin(6, 18, 0, 1792861200), 1793466000, "Sa 18:00 nach Ende der Sommerzeit")
	eq(Clock.NextBerlin(3, 19, 0, 1792888200), 1793210400, "Mi 19:00 in der Umstellungsnacht")
	eq(Clock.NextBerlin(7, 20, 0, 1792954800), 1793559600, "So 20:00 Bilanz-Sonntag")
	eq(Clock.NextBerlin(nil, 19, 0, 1774722600), 1774803600, "täglich über Beginn der Sommerzeit")
end)

check("NextBerlin über Jahresgrenze + Eingaben", function()
	eq(Clock.NextBerlin(4, 20, 0, 1798747200), 1799348400, "Do 20:00 über Silvester")
	eq(Clock.NextBerlin(0, 19, 0, 1791892800), 1791910800, "ungültiger Wochentag = täglich")
	eq(Clock.NextBerlin(nil, 30, 99, 1791892800), Clock.NextBerlin(nil, 23, 59, 1791892800), "geklemmt")
	-- Ergebnis immer in der Zukunft und höchstens 8 Tage entfernt
	for i = 0, 400 do
		local after = 1767571200 + i * 97531
		for dow = 1, 7 do
			local t = Clock.NextBerlin(dow, 17, 0, after)
			assert(t > after and t - after <= 8 * DAY, "Bereich " .. after)
			eq(Clock.Weekday(t + Clock.BerlinOffset(t)), dow, "Wochentag in Berlin")
			eq((t + Clock.BerlinOffset(t)) % DAY, 17 * 3600, "17:00 Ortszeit")
		end
	end
end)

-- ---------------------------------------------------------------------
print(("[clock.test] %d/%d PASS"):format(passed, passed + failed))
if failed > 0 then
	for _, failure in ipairs(failures) do
		print("  FAIL " .. failure)
	end
	error(("%d Test(s) fehlgeschlagen"):format(failed))
end
