--!strict
-- =====================================================================
--  CLUTCH CLASH – Kleine Helfer für Server UND Client (Shared/Util)
--  Besitzer: WP1 (Core & Plattform). Basis: Meteor-Heist-Util + Fix REUSE §14.2.
--  Reines Modul (keine Roblox-Dienste beim Laden) -> auch mit der Luau-CLI testbar
--  (tests/util.test.luau).
--
--  Öffentliche API (DESIGN.md C6.1):
--    Util.FormatNumber(n): string          1150 -> "1.15K", math.huge -> "MAX", -0.5 -> "0"
--    Util.FormatTime(seconds): string      "5h 12m" (ab 1 Stunde), sonst "3:07"
--    Util.DeepCopy(v), Util.Reconcile(target, template)
--    Util.WeightedPick(list, weightOf?, rng?): T?   Gewicht 0/NaN/negativ/unendlich wird nie gewählt
--    Util.RateLimiter(maxCalls, perSeconds, clock?)  -> { Check(key): boolean, Clear(key) }
--    Util.TokenBucket(capacity, refillPerSecond, clock?) -> { Take(key, n?): boolean, Clear(key) }
--    Util.IsFinite(n), Util.IsFiniteVector(v)
--    Util.UtcDay(now?), Util.IsoWeek(now?), Util.SetDayOffset(n), Util.GetDayOffset()
--    Util.Snapshot(t): { K }, Util.Hash(s): number (FNV-1a 32 Bit, 0..2^31-1)
--  "clock" ist optional (künstliche Uhr für Tests), Standard os.clock.
-- =====================================================================

local Util = {}

export type RateLimiter = {
	Check: (key: any) -> boolean,
	Clear: (key: any) -> (),
}

export type TokenBucket = {
	Take: (key: any, n: number?) -> boolean,
	Clear: (key: any) -> (),
}

local HUGE = math.huge

-- ---------------------------------------------------------------------
-- 1) ZAHLEN PRÜFEN
-- ---------------------------------------------------------------------

-- true nur für echte, endliche Zahlen (kein NaN, kein ±unendlich, kein String)
function Util.IsFinite(n: any): boolean
	return typeof(n) == "number" and n == n and n ~= HUGE and n ~= -HUGE
end

-- true nur für einen Vector3 mit drei endlichen Komponenten
function Util.IsFiniteVector(v: any): boolean
	if typeof(v) ~= "Vector3" then
		return false
	end
	return Util.IsFinite(v.X) and Util.IsFinite(v.Y) and Util.IsFinite(v.Z)
end

-- ---------------------------------------------------------------------
-- 2) ANZEIGE
-- ---------------------------------------------------------------------
local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
local EPS = 1e-9

-- 1234 -> "1.23K", 15000000 -> "15M" (abgerundet, nie "1000K")
function Util.FormatNumber(n: number): string
	if typeof(n) ~= "number" or n ~= n then
		return "0"
	elseif n == HUGE or n == -HUGE then
		return if n > 0 then "MAX" else "-MAX"
	end
	local negative = n <= -1 -- -0.5 -> "0" statt "-0"
	n = math.abs(n)
	if n < 1000 then
		local s = string.format("%d", math.floor(n + EPS))
		return if negative then "-" .. s else s
	end
	-- Stufe über Vergleiche statt wiederholtem Teilen (sonst wird 1e33 zu "999No")
	local index, scale = 1, 1
	while index < #SUFFIXES and n * (1 + EPS) >= scale * 1000 do
		scale *= 1000
		index += 1
	end
	local v = n / scale
	local text: string
	if v >= 100 then
		text = string.format("%.0f", math.floor(v + EPS)) -- %.0f: kein Überlauf bei riesigen Zahlen
	elseif v >= 10 then
		text = string.format("%.1f", math.floor(v * 10 + EPS) / 10)
	else
		text = string.format("%.2f", math.floor(v * 100 + EPS) / 100)
	end
	if string.find(text, ".", 1, true) then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return (if negative then "-" else "") .. text .. SUFFIXES[index]
end

-- 187 -> "3:07", 18720 -> "5h 12m" (ab einer Stunde ohne Sekunden)
function Util.FormatTime(seconds: number): string
	if not Util.IsFinite(seconds) then
		seconds = 0
	end
	local total = math.clamp(math.floor(seconds), 0, 359999999) -- höchstens 99999h 59m
	local h = math.floor(total / 3600)
	local m = math.floor((total % 3600) / 60)
	local s = total % 60
	if h > 0 then
		return string.format("%dh %dm", h, m)
	end
	return string.format("%d:%02d", m, s)
end

-- ---------------------------------------------------------------------
-- 3) TABELLEN
-- ---------------------------------------------------------------------
function Util.DeepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value :: any) do
		copy[k] = Util.DeepCopy(v)
	end
	return copy :: any
end

-- Ergänzt fehlende Felder aus "template" (für Spielstände nach Updates).
function Util.Reconcile(target: { [any]: any }, template: { [any]: any })
	for k, v in pairs(template) do
		if target[k] == nil then
			target[k] = Util.DeepCopy(v)
		elseif type(v) == "table" and type(target[k]) == "table" then
			Util.Reconcile(target[k], v)
		end
	end
end

-- Liste der Schlüssel (zum sicheren Durchlaufen, während die Tabelle sich ändert)
function Util.Snapshot<K, V>(t: { [K]: V }): { K }
	local keys = {}
	for k in pairs(t) do
		table.insert(keys, k)
	end
	return keys
end

-- ---------------------------------------------------------------------
-- 4) ZUFALL
-- ---------------------------------------------------------------------

-- Gewichtete Zufallsauswahl: list = { {Weight = 5, ...}, ... } oder eigene weightOf-Funktion.
-- Einträge mit Gewicht 0 (oder NaN/negativ/unendlich) werden NIE gewählt.
-- Haben alle Einträge Gewicht 0 (oder ist die Liste leer) -> nil.
function Util.WeightedPick<T>(list: { T }, weightOf: ((T) -> number)?, rng: Random?): T?
	local function weight(item: T): number
		local raw: any
		if weightOf then
			local ok, result = pcall(weightOf, item)
			raw = if ok then result else 0
		elseif type(item) == "table" then
			raw = (item :: any).Weight
		end
		local w = tonumber(raw) or 0
		if not Util.IsFinite(w) or w < 0 then
			return 0
		end
		return w
	end
	local total = 0
	local lastPositive: T? = nil
	for _, item in ipairs(list) do
		local w = weight(item)
		total += w
		if w > 0 then
			lastPositive = item
		end
	end
	if total <= 0 or not Util.IsFinite(total) then
		return nil
	end
	local random: any = rng or Random.new()
	local roll = random:NextNumber() * total
	for _, item in ipairs(list) do
		local w = weight(item)
		if w > 0 then
			roll -= w
			if roll <= 0 then
				return item
			end
		end
	end
	-- Rundungsfehler: letzter Eintrag mit Gewicht > 0
	return lastPositive
end

-- ---------------------------------------------------------------------
-- 5) SPAM-BREMSEN
-- ---------------------------------------------------------------------

-- Gleitendes Fenster pro Schlüssel (meist der Player): höchstens maxCalls in perSeconds.
-- PlayerRemoving: limiter.Clear(player) (sonst hält die Tabelle den Player fest)
function Util.RateLimiter(maxCalls: number, perSeconds: number, clock: (() -> number)?): RateLimiter
	local limit = math.max(1, math.floor(if Util.IsFinite(maxCalls) then maxCalls else 1))
	local window = if Util.IsFinite(perSeconds) then math.max(0, perSeconds) else 1
	local now: () -> number = clock or os.clock
	local buckets: { [any]: { number } } = {}

	local limiter = {}
	function limiter.Check(key: any): boolean
		local t = now()
		local bucket = buckets[key]
		if not bucket then
			bucket = {}
			buckets[key] = bucket
		end
		-- alte Einträge vorne entfernen (höchstens #bucket <= limit Durchläufe)
		while bucket[1] ~= nil and t - bucket[1] >= window do
			table.remove(bucket, 1)
		end
		if #bucket >= limit then
			return false
		end
		table.insert(bucket, t)
		return true
	end
	function limiter.Clear(key: any)
		buckets[key] = nil
	end
	return limiter
end

-- Token-Eimer pro Schlüssel: startet voll (capacity), füllt refillPerSecond Marken pro Sekunde nach.
-- Take(key, n) nimmt n Marken (Standard 1), wenn genug da sind.
function Util.TokenBucket(capacity: number, refillPerSecond: number, clock: (() -> number)?): TokenBucket
	local cap = if Util.IsFinite(capacity) then math.max(0, capacity) else 1
	local rate = if Util.IsFinite(refillPerSecond) then math.max(0, refillPerSecond) else 0
	local now: () -> number = clock or os.clock
	local tokens: { [any]: number } = {}
	local stamps: { [any]: number } = {}

	local bucket = {}
	function bucket.Take(key: any, n: number?): boolean
		local amount = if n == nil then 1 else n
		if not Util.IsFinite(amount) or amount < 0 then
			return false
		end
		local t = now()
		local have = tokens[key]
		if have == nil then
			have = cap
		else
			local elapsed = math.max(0, t - (stamps[key] or t))
			have = math.min(cap, have + elapsed * rate)
		end
		stamps[key] = t
		if have >= amount then
			tokens[key] = have - amount
			return true
		end
		tokens[key] = have
		return false
	end
	function bucket.Clear(key: any)
		tokens[key] = nil
		stamps[key] = nil
	end
	return bucket
end

-- ---------------------------------------------------------------------
-- 6) DATUM (UTC) – Tages-/Wochenindex für Quests, Login, Bestenlisten
-- ---------------------------------------------------------------------
local dayOffset = 0 -- nur Debug (Studio, Admin "SkipDay")

-- Tage seit 1970-01-01 -> (Jahr, Monat, Tag) (Algorithmus von H. Hinnant, ohne os.date)
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

-- (Jahr, Monat, Tag) -> Tage seit 1970-01-01
local function daysFromCivil(year: number, month: number, day: number): number
	local y = year - (if month <= 2 then 1 else 0)
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp = (month + 9) % 12
	local doy = math.floor((153 * mp + 2) / 5) + day - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

-- UTC-Tagesindex: floor(os.time() / 86400) + DayOffset. UtcDay(0) == 0 (ohne Offset).
function Util.UtcDay(now: number?): number
	local t = if Util.IsFinite(now) then now :: number else os.time()
	return math.floor(t / 86400) + dayOffset
end

-- ISO-Woche als Zahl JJJJWW (Montag = Wochenstart, Woche 1 enthält den ersten Donnerstag).
-- Beispiel: 2026-10-11 -> 202641. Der Debug-Tagesversatz zählt mit.
function Util.IsoWeek(now: number?): number
	local day = Util.UtcDay(now)
	local weekday = ((day + 3) % 7) + 1 -- 1 = Montag … 7 = Sonntag (1970-01-01 war ein Donnerstag)
	local thursday = day - weekday + 4
	local year = civilFromDays(thursday)
	local week = math.floor((thursday - daysFromCivil(year, 1, 1)) / 7) + 1
	return year * 100 + week
end

-- Nur Debug (Studio): verschiebt UtcDay/IsoWeek um n Tage (geklemmt auf ±10 Jahre)
function Util.SetDayOffset(n: number)
	if Util.IsFinite(n) then
		dayOffset = math.clamp(math.floor(n), -3650, 3650)
	end
end

function Util.GetDayOffset(): number
	return dayOffset
end

-- ---------------------------------------------------------------------
-- 7) HASH – deterministisch (z. B. Shard = Util.Hash(game.JobId) % 8)
-- ---------------------------------------------------------------------

-- FNV-1a 32 Bit, auf 0..2^31-1 begrenzt
function Util.Hash(s: string): number
	local text = if type(s) == "string" then s else tostring(s)
	local h = 2166136261
	for i = 1, #text do
		h = bit32.bxor(h, string.byte(text, i))
		-- h * 16777619 mod 2^32 ohne Genauigkeitsverlust: 16777619 = 2^24 + 403
		h = (bit32.lshift(h, 24) + h * 403) % 4294967296
	end
	return bit32.band(h, 0x7FFFFFFF)
end

return Util
