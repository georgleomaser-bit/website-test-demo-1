--!strict
-- =====================================================================
--  CLUTCH CLASH – Fortschritts-Mathematik (Shared/ProgressMath)
--  Besitzer: WP8 (Fortschritt). Vertrag: DESIGN.md C6.3 + B16 + B21.2.
--  Reines Modul (keine Roblox-Dienste, kein Random/Vector3) -> auch mit der
--  Luau-CLI testbar (tests/progressmath.test.luau). Server UND Client rechnen
--  damit gleich (Level-Balken, Pass-Stufen, Login-Kalender, Quest-Rotation).
--
--  Öffentliche API (C6.3):
--    ProgressMath.XpToNext(level): number                 250 + 50·(L−1); 0 ab Max-Level
--    ProgressMath.LevelFromTotal(totalXp): (level, xpInLevel)
--    ProgressMath.Expected(a, b): number                  Elo-Erwartung von a gegen b (0..1)
--    ProgressMath.EloDelta(a, b, score, k): number        ganzzahlig, symmetrisch gerundet
--    ProgressMath.MasteryTier(kills): number              0..10
--  Zusätzlich (von WP8 benutzt, ebenfalls rein):
--    ProgressMath.Configure(progressionConfig)            Kurve/Meisterschaft aus Config.Progression übernehmen
--    ProgressMath.MaxLevel(), ProgressMath.TotalForLevel(level)
--    ProgressMath.MasteryGoal(tier): number?              Pops für die nächste Stufe (nil = max)
--    ProgressMath.ParseIsoUtc(text): number?              "2026-10-15T00:00:00Z" -> Unix-Sekunden
--    ProgressMath.PickSeason(seasons, now): season?       Datumsfenster + Fallback (B21.2)
--    ProgressMath.PassTier(xp, tierXp, tiers): number     erreichte Pass-Stufe
--    ProgressMath.LoginStep(login, today, isoWeek, calendarLength, freezesPerWeek): LoginResult?
--    ProgressMath.Bounty(streak, cfg?): number            Kopfgeld (B16.7)
--    ProgressMath.CapMult(bonusSum, cap): number          additive Multiplikatoren, gedeckelt
--    ProgressMath.Rng(seed): () -> number                 deterministischer Zufall 0..1 (LCG)
--    ProgressMath.Seed(a, b): number                      Seed aus zwei Zahlen (Tag, UserId)
--    ProgressMath.PickDaily(pool, tiers, seed): { string }   je Stufe eine Quest-Id
--    ProgressMath.PickWeekly(pool, count, seed): { string }  count verschiedene Quest-Ids
-- =====================================================================

local ProgressMath = {}

export type LoginData = {
	LastDay: number,
	CalDay: number,
	Streak: number,
	Best: number,
	FreezeWeek: number,
}
export type LoginResult = { CalDay: number, Streak: number, UsedFreeze: boolean, NewCycle: boolean }
export type QuestDef = { Id: string, Tier: string?, [string]: any }

local TWO32 = 4294967296

-- Startwerte = Config.Progression (B16.1 / B16.2); Configure() überschreibt sie
local curveBase = 250
local curveStep = 50
local maxLevel = 100
local masteryTiers: { number } = { 10, 30, 75, 150, 300, 600, 1000, 2000, 3500, 6000 }
local bountyCfg = { MinStreak = 5, Base = 100, Step = 25, Cap = 300 }

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function int(n: any, default: number): number
	if not finite(n) then
		return default
	end
	return math.floor(n)
end

-- ---------------------------------------------------------------------
-- 0) EINSTELLUNGEN ÜBERNEHMEN (Config.Progression, fehlende Teile bleiben)
-- ---------------------------------------------------------------------
function ProgressMath.Configure(cfg: any)
	if type(cfg) ~= "table" then
		return
	end
	local curve = cfg.Curve
	if type(curve) == "table" then
		if finite(curve.Base) and curve.Base > 0 then
			curveBase = curve.Base
		end
		if finite(curve.Step) and curve.Step >= 0 then
			curveStep = curve.Step
		end
		if finite(curve.MaxLevel) and curve.MaxLevel >= 2 then
			maxLevel = math.floor(curve.MaxLevel)
		end
	end
	local mastery = cfg.Mastery
	if type(mastery) == "table" and type(mastery.Tiers) == "table" then
		local list: { number } = {}
		local last = 0
		for _, goal in ipairs(mastery.Tiers) do
			if finite(goal) and goal > last then
				table.insert(list, goal)
				last = goal
			end
		end
		if #list > 0 then
			masteryTiers = list
		end
	end
	local bounty = cfg.Bounty
	if type(bounty) == "table" then
		for _, key in ipairs({ "MinStreak", "Base", "Step", "Cap" }) do
			local v = bounty[key]
			if finite(v) and v >= 0 then
				(bountyCfg :: any)[key] = v
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- 1) XP & LEVEL (B16.1)
-- ---------------------------------------------------------------------
function ProgressMath.MaxLevel(): number
	return maxLevel
end

-- XP von Level L nach L+1. Ab dem Max-Level gibt es kein "nächstes" Level -> 0.
function ProgressMath.XpToNext(level: number): number
	local l = math.max(1, int(level, 1))
	if l >= maxLevel then
		return 0
	end
	return curveBase + curveStep * (l - 1)
end

-- Gesamt-XP, die man braucht, um Level "level" zu erreichen (Level 1 = 0)
function ProgressMath.TotalForLevel(level: number): number
	local l = math.clamp(int(level, 1), 1, maxLevel)
	local n = l - 1
	return n * curveBase + curveStep * n * (n - 1) / 2
end

-- Gesamt-XP -> (Level, XP im Level). Am Max-Level ist "XP im Level" immer 0.
function ProgressMath.LevelFromTotal(totalXp: number): (number, number)
	if not finite(totalXp) or totalXp <= 0 then
		return 1, 0
	end
	local level = 1
	local rest = totalXp
	-- höchstens maxLevel Durchläufe
	while level < maxLevel do
		local need = ProgressMath.XpToNext(level)
		if need <= 0 or rest < need then
			break
		end
		rest -= need
		level += 1
	end
	if level >= maxLevel then
		return maxLevel, 0
	end
	return level, rest
end

-- ---------------------------------------------------------------------
-- 2) ELO / VERDECKTES MMR (B16.6)
-- ---------------------------------------------------------------------
function ProgressMath.Expected(a: number, b: number): number
	local ra = if finite(a) then a else 1000
	local rb = if finite(b) then b else 1000
	return 1 / (1 + 10 ^ ((rb - ra) / 400))
end

-- k × (score − Erwartung), symmetrisch gerundet (Gewinn des einen = Verlust des anderen)
function ProgressMath.EloDelta(a: number, b: number, score: number, k: number): number
	local s = if finite(score) then math.clamp(score, 0, 1) else 0.5
	local factor = if finite(k) then math.max(0, k) else 0
	local raw = factor * (s - ProgressMath.Expected(a, b))
	if raw >= 0 then
		return math.floor(raw + 0.5)
	end
	return -math.floor(-raw + 0.5)
end

-- ---------------------------------------------------------------------
-- 3) WAFFEN-MEISTERSCHAFT (B16.2)
-- ---------------------------------------------------------------------
function ProgressMath.MasteryTier(kills: number): number
	if not finite(kills) or kills <= 0 then
		return 0
	end
	local tier = 0
	for i, goal in ipairs(masteryTiers) do
		if kills + 1e-9 >= goal then
			tier = i
		else
			break
		end
	end
	return tier
end

-- Pops, die für Stufe tier+1 nötig sind (nil = höchste Stufe erreicht)
function ProgressMath.MasteryGoal(tier: number): number?
	return masteryTiers[int(tier, 0) + 1]
end

function ProgressMath.MasteryTierCount(): number
	return #masteryTiers
end

-- ---------------------------------------------------------------------
-- 4) DATUM & SAISON (B21.2)
-- ---------------------------------------------------------------------

-- (Jahr, Monat, Tag) -> Tage seit 1970-01-01 (H. Hinnant)
local function daysFromCivil(year: number, month: number, day: number): number
	local y = year - (if month <= 2 then 1 else 0)
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp = (month + 9) % 12
	local doy = math.floor((153 * mp + 2) / 5) + day - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

-- "YYYY-MM-DDTHH:MM:SSZ" (oder nur "YYYY-MM-DD") -> Unix-Sekunden UTC; kaputt -> nil
function ProgressMath.ParseIsoUtc(text: string): number?
	if type(text) ~= "string" then
		return nil
	end
	local y, mo, d, h, mi, s = string.match(text, "^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)Z$")
	if not y then
		y, mo, d = string.match(text, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
		h, mi, s = "0", "0", "0"
	end
	if not (y and mo and d and h and mi and s) then
		return nil
	end
	local year, month, day = tonumber(y) :: number, tonumber(mo) :: number, tonumber(d) :: number
	local hour, minute, second = tonumber(h) :: number, tonumber(mi) :: number, tonumber(s) :: number
	if month < 1 or month > 12 or day < 1 or day > 31 or hour > 23 or minute > 59 or second > 60 then
		return nil
	end
	return daysFromCivil(year, month, day) * 86400 + hour * 3600 + minute * 60 + second
end

-- Aktive Saison: Datumsfenster StartUtc ≤ jetzt < EndUtc (bei Überschneidung der jüngste Start).
-- Passt keins: jüngster Start ≤ jetzt. Liegt jetzt vor allen: Saison mit Id 1 (sonst die früheste).
-- Leere/kaputte Liste -> nil.
function ProgressMath.PickSeason(seasons: { any }, now: number): any
	if type(seasons) ~= "table" then
		return nil
	end
	local t = if finite(now) then now else 0
	local inWindow, inWindowStart = nil, -math.huge
	local lastStarted, lastStartedAt = nil, -math.huge
	local earliest, earliestAt = nil, math.huge
	local first = nil
	for _, season in ipairs(seasons) do
		if type(season) == "table" then
			local start = ProgressMath.ParseIsoUtc(season.StartUtc)
			local finish = ProgressMath.ParseIsoUtc(season.EndUtc)
			if start then
				if season.Id == 1 then
					first = season
				end
				if start <= t and (finish == nil or t < finish) and start > inWindowStart then
					inWindow, inWindowStart = season, start
				end
				if start <= t and start > lastStartedAt then
					lastStarted, lastStartedAt = season, start
				end
				if start < earliestAt then
					earliest, earliestAt = season, start
				end
			end
		end
	end
	return inWindow or lastStarted or first or earliest
end

-- Erreichte Pass-Stufe für Pass-XP (0..tiers)
function ProgressMath.PassTier(xp: number, tierXp: number, tiers: number): number
	if not finite(xp) or not finite(tierXp) or tierXp <= 0 then
		return 0
	end
	return math.clamp(math.floor(xp / tierXp + 1e-9), 0, math.max(0, int(tiers, 0)))
end

-- ---------------------------------------------------------------------
-- 5) LOGIN-KALENDER (B16.4) – verändert "login" direkt; nil = heute schon abgeholt
--    Kalender rückt nur an Login-Tagen vor; ein verpasster Tag setzt nur die Serie zurück.
--    Genau EIN verpasster Tag wird pro ISO-Woche automatisch mit einem Freeze überbrückt.
-- ---------------------------------------------------------------------
function ProgressMath.LoginStep(
	login: LoginData,
	today: number,
	isoWeek: number,
	calendarLength: number,
	freezesPerWeek: number
): LoginResult?
	local last = int(login.LastDay, 0)
	if last == today then
		return nil
	end
	local length = math.max(1, int(calendarLength, 7))
	local streak = math.max(0, int(login.Streak, 0))
	local gap = today - last
	local usedFreeze = false
	if last > 0 and gap == 1 then
		streak += 1
	elseif last > 0 and gap == 2 and int(freezesPerWeek, 0) > 0 and int(login.FreezeWeek, 0) ~= isoWeek then
		streak += 1
		usedFreeze = true
		login.FreezeWeek = isoWeek
	else
		streak = 1
	end
	local calDay = (math.clamp(int(login.CalDay, 0), 0, length) % length) + 1
	login.CalDay = calDay
	login.Streak = streak
	login.Best = math.max(int(login.Best, 0), streak)
	login.LastDay = today
	return { CalDay = calDay, Streak = streak, UsedFreeze = usedFreeze, NewCycle = calDay == length }
end

-- ---------------------------------------------------------------------
-- 6) KOPFGELD & MULTIPLIKATOREN (B16.7 / B16.1)
-- ---------------------------------------------------------------------
function ProgressMath.Bounty(streak: number, cfg: any): number
	local c: any = if type(cfg) == "table" then cfg else bountyCfg
	local minStreak = if finite(c.MinStreak) then c.MinStreak else bountyCfg.MinStreak
	local s = int(streak, 0)
	if s < minStreak then
		return 0
	end
	local base = if finite(c.Base) then c.Base else bountyCfg.Base
	local step = if finite(c.Step) then c.Step else bountyCfg.Step
	local cap = if finite(c.Cap) then c.Cap else bountyCfg.Cap
	return math.min(cap, base + step * (s - minStreak))
end

-- 1 + Summe der Boni, gedeckelt (B16.1: additiv, Deckel ×3.0)
function ProgressMath.CapMult(bonusSum: number, cap: number): number
	local sum = if finite(bonusSum) then math.max(0, bonusSum) else 0
	local limit = if finite(cap) then math.max(1, cap) else 3
	return math.min(limit, 1 + sum)
end

-- ---------------------------------------------------------------------
-- 7) DETERMINISTISCHER ZUFALL + QUEST-ROTATION (B16.3)
--    Gleicher Seed -> gleiche Quests (auf jedem Server, nach jedem Neubeitritt).
-- ---------------------------------------------------------------------
function ProgressMath.Seed(a: number, b: number): number
	local x = int(a, 0) % TWO32
	local y = int(b, 0) % TWO32
	-- Knuth-Mischung (Produkte bleiben < 2^53, also exakt)
	local h = (x * 2654435761 + y) % TWO32
	h = (h * 40503 + 2246822519) % TWO32
	return h
end

-- Lineare Kongruenz (Numerical Recipes), liefert Zahlen in [0, 1)
function ProgressMath.Rng(seed: number): () -> number
	local state = int(seed, 1) % TWO32
	return function(): number
		state = (state * 1664525 + 1013904223) % TWO32
		return state / TWO32
	end
end

local function pickIndex(rng: () -> number, count: number): number
	return math.clamp(math.floor(rng() * count) + 1, 1, count)
end

-- Je Stufe (z. B. {"Easy","Medium","Hard"}) eine Quest; fehlt eine Stufe, kommt eine beliebige freie Quest.
function ProgressMath.PickDaily(pool: { QuestDef }, tiers: { string }, seed: number): { string }
	local rng = ProgressMath.Rng(seed)
	local used: { [string]: boolean } = {}
	local result: { string } = {}
	for _, tier in ipairs(tiers) do
		local candidates: { QuestDef } = {}
		for _, def in ipairs(pool) do
			if def.Tier == tier and not used[def.Id] then
				table.insert(candidates, def)
			end
		end
		if #candidates == 0 then
			for _, def in ipairs(pool) do
				if not used[def.Id] then
					table.insert(candidates, def)
				end
			end
		end
		if #candidates > 0 then
			local def = candidates[pickIndex(rng, #candidates)]
			used[def.Id] = true
			table.insert(result, def.Id)
		end
	end
	return result
end

-- count verschiedene Quests (Fisher-Yates mit festem Seed)
function ProgressMath.PickWeekly(pool: { QuestDef }, count: number, seed: number): { string }
	local rng = ProgressMath.Rng(seed)
	local ids: { string } = {}
	for _, def in ipairs(pool) do
		table.insert(ids, def.Id)
	end
	for i = #ids, 2, -1 do
		local j = pickIndex(rng, i)
		ids[i], ids[j] = ids[j], ids[i]
	end
	local result: { string } = {}
	for i = 1, math.min(math.max(0, int(count, 0)), #ids) do
		table.insert(result, ids[i])
	end
	return result
end

return ProgressMath
