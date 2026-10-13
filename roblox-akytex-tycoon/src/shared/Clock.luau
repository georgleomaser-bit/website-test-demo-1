--!strict
-- =====================================================================
--  AKYTEX TYCOON – Globale Spieluhr: Tick, Börsentag, Woche, Tageszeit, Berlin-Zeit (Shared/Clock)
--  Besitzer: WP1 (Kern & Plattform). Vertrag: DESIGN.md §C6.1, §A4 (Tag/Nacht), §B10.4 (Berlin-Kalender),
--  MARKET.md §3 (Tick = floor(unixMs/1000) − EPOCH).
--  Reines Modul: lädt keine Roblox-Dienste beim require -> mit der Luau-CLI testbar (tests/clock.test.luau).
--  Alle Server rechnen dasselbe (deterministisch aus der Weltzeit) – nie lokale Zeitzonen von os.date.
--
--  Öffentliche API:
--    Clock.EPOCH            1767571200 (Mo 2026-01-05 00:00 UTC)
--    Clock.DAY_TICKS        1200 (ein Börsentag = 20 min = ein Tag/Nacht-Zyklus)
--    Clock.WEEK_TICKS       604800 (7 echte Tage = 504 Börsentage, Wechsel Mo 00:00 UTC)
--    Clock.Now(): number    Server: DateTime.now().UnixTimestampMillis/1000 · Client: workspace:GetServerTimeNow()
--                           (ohne Roblox, z. B. Luau-CLI: os.time())
--    Clock.Tick(): number   floor(Now()) − EPOCH
--    Clock.DayIndex(tick)   Börsentag-Index (floor(tick / 1200))
--    Clock.DayMinute(tick)  Minute im Börsentag, 0 ≤ x < 20 (mit Bruchteil: Sekunde 30 -> 0,5)
--    Clock.WeekIndex(tick)  Woche seit EPOCH      Clock.WeekStartTick(week): erster Tick der Woche
--    Clock.ClockTime(tick)  Tageszeit der Welt (Lighting.ClockTime, §A4: :00 6,5 · :06 12 · :12 18,5 ·
--                           :12,5–:18,5 Nacht 21 → 4 · :19,5 Dämmerung 5,5)
--    Clock.IsNight(tick)    true ab Sonnenuntergang (ClockTime ≥ 18,5) bis kurz vor Sonnenaufgang (< 6)
--    Clock.BerlinOffset(unix): number   3600 oder 7200 (EU-Regel: +2 h vom letzten So im März 01:00 UTC
--                           bis zum letzten So im Oktober 01:00 UTC)
--    Clock.NextBerlin(dow?, hh, mm, afterUnix): number   nächster Unix-Zeitpunkt STRIKT nach afterUnix, an dem
--                           in Berlin dow hh:mm ist (dow 1 = Mo … 7 = So, nil = täglich)
--    Clock.TickOf(unix): number    floor(unix) − EPOCH        Clock.UnixOf(tick): number   tick + EPOCH
--    Clock.Weekday(unix): number   1 = Mo … 7 = So (UTC-Kalendertag)
-- =====================================================================

local Clock = {}

Clock.EPOCH = 1767571200
Clock.DAY_TICKS = 1200
Clock.WEEK_TICKS = 604800

local DAY_MINUTES = Clock.DAY_TICKS / 60 -- 20
local SECONDS_PER_DAY = 86400
local HUGE = math.huge

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= HUGE and n ~= -HUGE
end

local function num(n: any): number
	return if finite(n) then n else 0
end

-- ---------------------------------------------------------------------
-- 1) ZEITQUELLE (einmal bestimmt, danach gecacht)
-- ---------------------------------------------------------------------
local nowFn: (() -> number)? = nil

local function resolveNow(): () -> number
	local ok, fn = pcall(function(): () -> number
		local RunService = game:GetService("RunService")
		if RunService:IsServer() then
			return function(): number
				return DateTime.now().UnixTimestampMillis / 1000
			end
		end
		return function(): number
			return workspace:GetServerTimeNow()
		end
	end)
	if ok and type(fn) == "function" then
		return fn
	end
	-- Luau-CLI / Tests: keine Roblox-Dienste
	return function(): number
		return os.time()
	end
end

function Clock.Now(): number
	local fn: () -> number = nowFn or resolveNow()
	nowFn = fn
	local value = fn()
	return if finite(value) then value else os.time()
end

function Clock.Tick(): number
	return math.floor(Clock.Now()) - Clock.EPOCH
end

function Clock.TickOf(unix: number): number
	return math.floor(num(unix)) - Clock.EPOCH
end

function Clock.UnixOf(tick: number): number
	return num(tick) + Clock.EPOCH
end

-- ---------------------------------------------------------------------
-- 2) BÖRSENTAG & WOCHE
-- ---------------------------------------------------------------------
function Clock.DayIndex(tick: number): number
	return math.floor(num(tick) / Clock.DAY_TICKS)
end

function Clock.DayMinute(tick: number): number
	local t = num(tick)
	local within = t - math.floor(t / Clock.DAY_TICKS) * Clock.DAY_TICKS
	local minute = within / 60
	if minute < 0 or minute >= DAY_MINUTES then
		return 0 -- Rundungsrest an der Tagesgrenze
	end
	return minute
end

function Clock.WeekIndex(tick: number): number
	return math.floor(num(tick) / Clock.WEEK_TICKS)
end

function Clock.WeekStartTick(week: number): number
	return math.floor(num(week)) * Clock.WEEK_TICKS
end

-- ---------------------------------------------------------------------
-- 3) TAGESZEIT DER WELT (§A4) – stückweise linear, Werte über 24 werden umgebrochen
-- ---------------------------------------------------------------------
local KNOTS: { { number } } = {
	{ 0, 6.5 }, -- Sonnenaufgang + Glocke
	{ 6, 12 }, -- Mittag
	{ 12, 18.5 }, -- Sonnenuntergang (Fensterlichter an)
	{ 12.5, 21 }, -- Nacht beginnt
	{ 18.5, 28 }, -- 04:00
	{ 19.5, 29.5 }, -- Dämmerung 05:30
	{ 20, 30.5 }, -- = 06:30 des nächsten Börsentags
}

function Clock.ClockTime(tick: number): number
	local m = Clock.DayMinute(tick)
	for i = 2, #KNOTS do
		local a, b = KNOTS[i - 1], KNOTS[i]
		if m <= b[1] then
			local f = (m - a[1]) / (b[1] - a[1])
			return (a[2] + (b[2] - a[2]) * f) % 24
		end
	end
	return KNOTS[1][2]
end

function Clock.IsNight(tick: number): boolean
	local ct = Clock.ClockTime(tick)
	return ct >= 18.5 or ct < 6
end

-- ---------------------------------------------------------------------
-- 4) KALENDER (UTC, ohne os.date) – Algorithmen von H. Hinnant
-- ---------------------------------------------------------------------
local function civilFromDays(days: number): (number, number, number)
	local z = days + 719468
	local era = math.floor(z / 146097)
	local doe = z - era * 146097
	local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
	local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
	local mp = math.floor((5 * doy + 2) / 153)
	local d = doy - math.floor((153 * mp + 2) / 5) + 1
	local m = if mp < 10 then mp + 3 else mp - 9
	local y = yoe + era * 400 + (if m <= 2 then 1 else 0)
	return y, m, d
end

local function daysFromCivil(year: number, month: number, day: number): number
	local y = year - (if month <= 2 then 1 else 0)
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp = (month + 9) % 12
	local doy = math.floor((153 * mp + 2) / 5) + day - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

-- 1 = Montag … 7 = Sonntag (1970-01-01 war ein Donnerstag)
local function weekdayOfDay(days: number): number
	return ((days + 3) % 7) + 1
end

function Clock.Weekday(unix: number): number
	return weekdayOfDay(math.floor(num(unix) / SECONDS_PER_DAY))
end

-- Unix-Zeit "letzter Sonntag des Monats, 01:00 UTC"
local function lastSundayOneUtc(year: number, month: number): number
	local firstOfNext = if month == 12 then daysFromCivil(year + 1, 1, 1) else daysFromCivil(year, month + 1, 1)
	local lastDay = firstOfNext - 1
	local sunday = lastDay - (weekdayOfDay(lastDay) % 7)
	return sunday * SECONDS_PER_DAY + 3600
end

-- ---------------------------------------------------------------------
-- 5) BERLIN-ZEIT (§B10.4) – Sommerzeit automatisch, auf allen Servern gleich
-- ---------------------------------------------------------------------
function Clock.BerlinOffset(unix: number): number
	if not finite(unix) then
		return 3600
	end
	local year = civilFromDays(math.floor(unix / SECONDS_PER_DAY))
	local summerStart = lastSundayOneUtc(year, 3)
	local summerEnd = lastSundayOneUtc(year, 10)
	if unix >= summerStart and unix < summerEnd then
		return 7200
	end
	return 3600
end

-- Ortszeit (Berlin) in Sekunden seit 1970 -> UTC. Nicht existierende Zeiten (Sprung im März) landen
-- eine Stunde später, doppelte Zeiten (Oktober) auf der zweiten (Winterzeit-)Variante.
local function berlinLocalToUtc(localSeconds: number): number
	local offset = Clock.BerlinOffset(localSeconds - 3600)
	local utc = localSeconds - offset
	local check = Clock.BerlinOffset(utc)
	if check ~= offset then
		utc = localSeconds - check
	end
	return utc
end

function Clock.NextBerlin(dow: number?, hh: number, mm: number, afterUnix: number): number
	local after = num(afterUnix)
	local hour = math.clamp(math.floor(num(hh)), 0, 23)
	local minute = math.clamp(math.floor(num(mm)), 0, 59)
	local wanted: number? = nil
	if dow ~= nil and finite(dow) and dow % 1 == 0 and dow >= 1 and dow <= 7 then
		wanted = dow
	end
	local localNow = after + Clock.BerlinOffset(after)
	local firstDay = math.floor(localNow / SECONDS_PER_DAY) - 1 -- ein Tag Puffer (Zeitumstellung)
	for day = firstDay, firstDay + 9 do -- höchstens 10 Kandidaten-Tage (Woche + Puffer)
		if wanted == nil or weekdayOfDay(day) == wanted then
			local utc = berlinLocalToUtc(day * SECONDS_PER_DAY + hour * 3600 + minute * 60)
			if utc > after then
				return utc
			end
		end
	end
	return after + 7 * SECONDS_PER_DAY -- nicht erreichbar (Sicherheitsnetz)
end

return Clock
