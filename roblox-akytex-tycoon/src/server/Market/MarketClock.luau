--!strict
-- =====================================================================
--  AKYTEX TYCOON – Markt-Uhr: Tick, Börsentag, Woche, Berlin-Termine (Server/Market/MarketClock)
--  Besitzer: WP3 (Markt-Engine). Vertrag: MARKET.md §3, §18.1; DESIGN.md §B10.4 (Berlin-Zeit über Shared/Clock).
--  Dünne Schicht über Shared/Clock (WP1): Tick = floor(unixMs/1000) − EPOCH, Börsentag = 1200 Ticks, Woche = 604.800.
--
--  Öffentliche API
--    MarketClock.Tick(): number                     aktueller Server-Tick
--    MarketClock.DayIndex(t) · DayStart(d) · Minute(t) (0…19, ganzzahlig) · Second(t) (0…1199 im Börsentag)
--    MarketClock.WeekIndex(t) · WeekStart(w) · WeekEnd(w) (letzter Tick der Woche) · DayInWeek(t) (0…503)
--    MarketClock.Unix(t) · MarketClock.TickOf(unix)
--    MarketClock.WeeklyTick(w, dow, hh, mm): number?   Tick des Berlin-Termins (dow 1 = Mo … 7 = So) in Woche w, sonst nil
--    MarketClock.DAY · MarketClock.WEEK · MarketClock.DAYS_PER_WEEK (504)
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clock = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Clock"))

local MarketClock = {}

local DAY = Clock.DAY_TICKS
local WEEK = Clock.WEEK_TICKS

MarketClock.DAY = DAY
MarketClock.WEEK = WEEK
MarketClock.DAYS_PER_WEEK = WEEK // DAY

function MarketClock.Tick(): number
	return Clock.Tick()
end

function MarketClock.DayIndex(t: number): number
	return t // DAY
end

function MarketClock.DayStart(d: number): number
	return d * DAY
end

function MarketClock.Second(t: number): number
	return t - (t // DAY) * DAY
end

function MarketClock.Minute(t: number): number
	return MarketClock.Second(t) // 60
end

function MarketClock.WeekIndex(t: number): number
	return t // WEEK
end

function MarketClock.WeekStart(w: number): number
	return w * WEEK
end

function MarketClock.WeekEnd(w: number): number
	return (w + 1) * WEEK - 1
end

function MarketClock.DayInWeek(t: number): number
	return (t - (t // WEEK) * WEEK) // DAY
end

function MarketClock.Unix(t: number): number
	return Clock.UnixOf(t)
end

function MarketClock.TickOf(unix: number): number
	return Clock.TickOf(unix)
end

-- Berlin-Termin (Ortszeit, Sommerzeit automatisch) innerhalb der Woche w; alle Server rechnen denselben Tick
function MarketClock.WeeklyTick(w: number, dow: number, hh: number, mm: number): number?
	local startUnix = Clock.UnixOf(MarketClock.WeekStart(w))
	local unix = Clock.NextBerlin(dow, hh, mm, startUnix - 1)
	local t = Clock.TickOf(unix)
	if t < MarketClock.WeekStart(w) or t > MarketClock.WeekEnd(w) then
		return nil
	end
	return t
end

return MarketClock
