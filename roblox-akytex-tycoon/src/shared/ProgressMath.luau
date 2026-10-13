--!strict
-- =====================================================================
--  AKYTEX TYCOON – Fortschritts-Mathematik (Shared/ProgressMath)
--  Besitzer: WP9 (Fortschritt, Tutorial, Sozial, Bestenlisten). Vertrag: DESIGN.md §C6.2 (rein, ohne Roblox-Dienste
--  -> mit der Luau-CLI testbar: tests/progressmath.test.luau), §B9.1 (Level-Kurve), §B9.2 (Lizenz-Ermittlung),
--  §B9.4 (Ruf-Stufen/Abbau/Untergrenzen), §B9.5 (Vermögens-Titel), §B9.7 (deterministische Quest-Auswahl),
--  §B9.6 (Sterne), §B11.1 (Bestenlisten-Kodierung).
--
--  Öffentliche API (§C6.2):
--    ProgressMath.LevelFromXp(xp): (level, progress)     Level 1–100 und Anteil 0 ≤ p < 1 bis zum nächsten Level
--    ProgressMath.XpForLevel(l): number                  ceil(12,5 · (L − 1)²) -> L10 1.013 · L100 122.513
--    ProgressMath.LicenceFor(xp, exams, table): number   höchste Lizenz, deren XP erreicht und deren Prüfungen
--                                                        (inkl. aller früheren) bestanden sind
--    ProgressMath.RufLevel(points): number               0–10 (Schwellen 10/30/60/…/550)
--    ProgressMath.RufDecay(points, days, floorLvl): number   −8 % je Tag (max. 30 Tage), nie unter die Lizenz-Untergrenze
--    ProgressMath.WealthTitle(v): string                 Schlüssel des Vermögens-Titels ("Starter" … "QuadBoss")
--    ProgressMath.QuestPick(seed, pool, n): { any }      n verschiedene Einträge, deterministisch je Seed
--  Ergänzungen (gleich rein): Configure(cfg), LevelCurve(), Stars(runSpend), RufFloor(licence), RufFactor(ruf),
--    TraderFactor(towerBonus, ruf), KnowHowTotal(level, licence, series), MaxDrawdown(returns), AvgDaily(returns),
--    SeasonTier(xp, tierXp, tiers), LoginDay(streak), BoardLog(v), BoardLogDecode(v), BoardLeague(score, avgBp),
--    BoardReturn(avgBp), BoardSkyline(ipos, floors), Clamp(n), Rng(seed)
--  Alle Startwerte stehen in Config.Progression; Configure(Config.Progression) übernimmt sie (sonst die Spec-Werte).
-- =====================================================================

local ProgressMath = {}

local MAX_MONEY = 9e15
local MAX_LEVEL_DEFAULT = 100

-- Startwerte (= DESIGN.md); Configure() übernimmt Werte aus Config.Progression
local P = {
	LevelCurve = 12.5,
	MaxLevel = MAX_LEVEL_DEFAULT,
	RufThresholds = { 10, 30, 60, 100, 150, 210, 280, 360, 450, 550 },
	RufDecayPct = 0.08,
	RufDecayMaxDays = 30,
	RufFactorStep = 0.03,
	RufFloors = { { Licence = 4, Level = 2 }, { Licence = 7, Level = 4 }, { Licence = 10, Level = 6 } },
	WealthTitles = {
		{ Key = "Starter", Min = 0 },
		{ Key = "TenK", Min = 1e4 },
		{ Key = "HundredK", Min = 1e5 },
		{ Key = "Millionaire", Min = 1e6 },
		{ Key = "MultiMillionaire", Min = 1e7 },
		{ Key = "HundredMillionaire", Min = 1e8 },
		{ Key = "Billionaire", Min = 1e9 },
		{ Key = "MultiBillionaire", Min = 1e10 },
		{ Key = "HundredBillionaire", Min = 1e11 },
		{ Key = "Trillionaire", Min = 1e12 },
		{ Key = "MultiTrillionaire", Min = 1e13 },
		{ Key = "QuadBoss", Min = 1e15 },
	},
	StarsK = 4,
	StarsDiv = 1e6,
	StarsMin = 1e7,
	KhPerLevel = 1,
	KhPerLicence = 3,
	KhPerSeries = 1,
	LoginCycle = 7,
}

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function num(v: any, default: number): number
	return if finite(v) then v else default
end

-- Übernimmt Werte aus Config.Progression (fehlende Felder behalten die Spec-Werte)
function ProgressMath.Configure(cfg: any)
	if type(cfg) ~= "table" then
		return
	end
	P.LevelCurve = num(cfg.LevelCurve, P.LevelCurve)
	P.MaxLevel = math.max(1, math.floor(num(cfg.MaxLevel, P.MaxLevel)))
	local ruf = cfg.Ruf
	if type(ruf) == "table" then
		if type(ruf.Thresholds) == "table" and #ruf.Thresholds > 0 then
			local list: { number } = {}
			for _, v in ipairs(ruf.Thresholds) do
				if finite(v) then
					table.insert(list, v)
				end
			end
			if #list > 0 then
				P.RufThresholds = list
			end
		end
		P.RufDecayPct = math.clamp(num(ruf.DecayPct, P.RufDecayPct), 0, 1)
		P.RufDecayMaxDays = math.max(0, math.floor(num(ruf.DecayMaxDays, P.RufDecayMaxDays)))
		P.RufFactorStep = num(ruf.FactorStep, P.RufFactorStep)
		if type(ruf.Floors) == "table" then
			P.RufFloors = ruf.Floors
		end
	end
	if type(cfg.Titles) == "table" and type(cfg.Titles.Wealth) == "table" and #cfg.Titles.Wealth > 0 then
		P.WealthTitles = cfg.Titles.Wealth
	end
	local prestige = cfg.Prestige
	if type(prestige) == "table" then
		P.StarsK = num(prestige.StarsK, P.StarsK)
		P.StarsDiv = math.max(1, num(prestige.StarsDiv, P.StarsDiv))
		P.StarsMin = math.max(0, num(prestige.StarsMin, P.StarsMin))
	end
	local kh = cfg.KnowHow
	if type(kh) == "table" then
		P.KhPerLevel = num(kh.PerLevel, P.KhPerLevel)
		P.KhPerLicence = num(kh.PerLicence, P.KhPerLicence)
		P.KhPerSeries = num(kh.PerSeries, P.KhPerSeries)
	end
end

function ProgressMath.LevelCurve(): number
	return P.LevelCurve
end

-- Ganzzahl, geklemmt auf 0 … 9e15 (Muss-Regel 9)
function ProgressMath.Clamp(n: number): number
	if not finite(n) then
		return 0
	end
	return math.clamp(math.floor(n), 0, MAX_MONEY)
end

-- ---------------------------------------------------------------------
-- 1) TRADER-LEVEL (§B9.1): XP_gesamt(L) = 12,5 × (L − 1)²
-- ---------------------------------------------------------------------
function ProgressMath.XpForLevel(l: number): number
	local level = math.clamp(math.floor(num(l, 1)), 1, P.MaxLevel)
	return math.ceil(P.LevelCurve * (level - 1) ^ 2 - 1e-9)
end

-- (Level, Fortschritt 0 ≤ p < 1 zum nächsten Level; am Höchstlevel 1)
function ProgressMath.LevelFromXp(xp: number): (number, number)
	local total = math.max(0, num(xp, 0))
	local level = math.floor(math.sqrt(total / P.LevelCurve) + 1 + 1e-9)
	level = math.clamp(level, 1, P.MaxLevel)
	-- Rundungsschutz: Grenze exakt wie XpForLevel
	while level < P.MaxLevel and total >= ProgressMath.XpForLevel(level + 1) do
		level += 1
	end
	while level > 1 and total < ProgressMath.XpForLevel(level) do
		level -= 1
	end
	if level >= P.MaxLevel then
		return P.MaxLevel, 1
	end
	local lo = ProgressMath.XpForLevel(level)
	local hi = ProgressMath.XpForLevel(level + 1)
	local progress = if hi > lo then (total - lo) / (hi - lo) else 0
	return level, math.clamp(progress, 0, 0.999999)
end

-- ---------------------------------------------------------------------
-- 2) LIZENZ (§B9.2): XP + alle Prüfungs-Aufgaben (auch die der früheren Lizenzen)
-- ---------------------------------------------------------------------
function ProgressMath.LicenceFor(xp: number, exams: { [string]: boolean }, licences: { any }): number
	local total = math.max(0, num(xp, 0))
	local done = if type(exams) == "table" then exams else {}
	local best = 1
	if type(licences) ~= "table" then
		return best
	end
	for i, def in ipairs(licences) do
		if type(def) ~= "table" then
			break
		end
		if i > 1 then
			if total < num(def.Xp, math.huge) then
				break
			end
			local passed = true
			if type(def.Exam) == "table" then
				for _, task in ipairs(def.Exam) do
					if done[task] ~= true then
						passed = false
						break
					end
				end
			end
			if not passed then
				break
			end
		end
		best = i
	end
	return best
end

-- ---------------------------------------------------------------------
-- 3) RUF (§B9.4)
-- ---------------------------------------------------------------------
function ProgressMath.RufLevel(points: number): number
	local p = math.max(0, num(points, 0))
	local level = 0
	for i, threshold in ipairs(P.RufThresholds) do
		if p >= threshold then
			level = i
		else
			break
		end
	end
	return level
end

-- Untergrenze (Stufe) nach Lizenz: Trader I ≥ 2, Fondsmanager I ≥ 4, Legende ≥ 6
function ProgressMath.RufFloor(licence: number): number
	local lic = math.floor(num(licence, 1))
	local floorLvl = 0
	for _, entry in ipairs(P.RufFloors) do
		if type(entry) == "table" and lic >= num(entry.Licence, math.huge) then
			floorLvl = math.max(floorLvl, math.floor(num(entry.Level, 0)))
		end
	end
	return floorLvl
end

-- Abbau −8 % je Tag ohne zählenden Börsentag (max. 30 Tage); nie unter die Punkte der Untergrenzen-Stufe
-- (liegt der Spieler schon darunter, bleibt der Wert, wie er ist). Ergebnis ganzzahlig.
function ProgressMath.RufDecay(points: number, days: number, floorLvl: number): number
	local p = math.max(0, math.floor(num(points, 0)))
	local d = math.clamp(math.floor(num(days, 0)), 0, P.RufDecayMaxDays)
	if d <= 0 or p <= 0 then
		return p
	end
	local decayed = math.floor(p * (1 - P.RufDecayPct) ^ d)
	local lvl = math.clamp(math.floor(num(floorLvl, 0)), 0, #P.RufThresholds)
	local floorPoints = if lvl > 0 then P.RufThresholds[lvl] else 0
	if p <= floorPoints then
		return p
	end
	return math.max(decayed, floorPoints)
end

-- Ruf-Anteil am Trader-Faktor: 1 + 0,03 × Ruf
function ProgressMath.RufFactor(ruf: number): number
	return 1 + P.RufFactorStep * math.clamp(math.floor(num(ruf, 0)), 0, #P.RufThresholds)
end

-- Trader-Faktor = (1 + Lizenz-Bonus) × (1 + 0,03 × Ruf)  -> (gesamt, Lizenz-Teil, Ruf-Teil)
function ProgressMath.TraderFactor(towerBonus: number, ruf: number): (number, number, number)
	local licPart = 1 + math.clamp(num(towerBonus, 0), 0, 1)
	local rufPart = ProgressMath.RufFactor(ruf)
	return licPart * rufPart, licPart, rufPart
end

-- ---------------------------------------------------------------------
-- 4) VERMÖGEN & TITEL (§B9.5)
-- ---------------------------------------------------------------------
function ProgressMath.WealthTitle(v: number): string
	local value = math.max(0, num(v, 0))
	local key = "Starter"
	local best = -math.huge
	for _, entry in ipairs(P.WealthTitles) do
		if type(entry) == "table" and type(entry.Key) == "string" then
			local min = num(entry.Min, math.huge)
			if value >= min and min >= best then
				best = min
				key = entry.Key
			end
		end
	end
	return key
end

-- ---------------------------------------------------------------------
-- 5) DETERMINISTISCHE AUSWAHL (§B9.7) – Park-Miller (16807 · x mod 2^31−1, Produkt < 2^53)
-- ---------------------------------------------------------------------
local MODULUS = 2147483647

export type Rng = { Next: () -> number, Int: (lo: number, hi: number) -> number }

function ProgressMath.Rng(seed: number): Rng
	local state = math.floor(math.abs(num(seed, 1))) % MODULUS
	if state == 0 then
		state = 1
	end
	local rng = {}
	function rng.Next(): number
		state = (state * 16807) % MODULUS
		return state
	end
	-- gleichverteilte ganze Zahl lo … hi
	function rng.Int(lo: number, hi: number): number
		if hi <= lo then
			return lo
		end
		return lo + (rng.Next() % (hi - lo + 1))
	end
	return rng :: Rng
end

-- n verschiedene Einträge aus pool (Reihenfolge = Ziehung), gleicher Seed -> gleiches Ergebnis
function ProgressMath.QuestPick(seed: number, pool: { any }, n: number): { any }
	local out: { any } = {}
	if type(pool) ~= "table" then
		return out
	end
	local count = math.clamp(math.floor(num(n, 0)), 0, #pool)
	if count == 0 then
		return out
	end
	local index: { number } = table.create(#pool)
	for i = 1, #pool do
		index[i] = i
	end
	local rng = ProgressMath.Rng(seed)
	-- zwei Vorläufe: kleine Seeds (1, 2, 3 …) streuen sonst schlecht
	rng.Next()
	rng.Next()
	for i = 1, count do
		local j = rng.Int(i, #pool)
		index[i], index[j] = index[j], index[i]
		table.insert(out, pool[index[i]])
	end
	return out
end

-- ---------------------------------------------------------------------
-- 6) BÖRSENGANG (§B9.6): ★ = floor(4 × log10(Lauf-Ausgaben / 1e6)), 0 unter 1e7
-- ---------------------------------------------------------------------
function ProgressMath.Stars(runSpend: number): number
	local spend = num(runSpend, 0)
	if spend < P.StarsMin or spend <= 0 then
		return 0
	end
	return math.max(0, math.floor(P.StarsK * math.log10(spend / P.StarsDiv) + 1e-9))
end

-- ---------------------------------------------------------------------
-- 7) KNOW-HOW (§B9.3): +1 je Trader-Level ab 2, +3 je Lizenz (ab Azubi II), +1 je Akademie-Serie
-- ---------------------------------------------------------------------
function ProgressMath.KnowHowTotal(level: number, licence: number, series: number): number
	local l = math.max(1, math.floor(num(level, 1)))
	local lic = math.max(1, math.floor(num(licence, 1)))
	local s = math.max(0, math.floor(num(series, 0)))
	return math.floor((l - 1) * P.KhPerLevel + (lic - 1) * P.KhPerLicence + s * P.KhPerSeries)
end

-- ---------------------------------------------------------------------
-- 8) RENDITE-KENNZAHLEN (Lizenz-Aufgabe "Drawdown < 8 % mit Ø ≥ +1 %")
-- ---------------------------------------------------------------------
-- größter Rückgang der Kurve Π(1 + r) (Anteil 0 … 1)
function ProgressMath.MaxDrawdown(returns: { number }): number
	local value, peak, maxDD = 1, 1, 0
	if type(returns) ~= "table" then
		return 0
	end
	for _, r in ipairs(returns) do
		if finite(r) then
			value *= math.max(0, 1 + r)
			if value > peak then
				peak = value
			elseif peak > 0 then
				maxDD = math.max(maxDD, (peak - value) / peak)
			end
		end
	end
	return maxDD
end

-- Ø-Tagesrendite = (Π(1 + r))^(1/n) − 1
function ProgressMath.AvgDaily(returns: { number }): number
	if type(returns) ~= "table" then
		return 0
	end
	local product, n = 1, 0
	for _, r in ipairs(returns) do
		if finite(r) then
			product *= math.max(0, 1 + r)
			n += 1
		end
	end
	if n == 0 or product <= 0 then
		return if n == 0 then 0 else -1
	end
	return product ^ (1 / n) - 1
end

-- ---------------------------------------------------------------------
-- 9) SAISON & LOGIN
-- ---------------------------------------------------------------------
-- erreichte Pass-Stufe (0 … tiers)
function ProgressMath.SeasonTier(xp: number, tierXp: number, tiers: number): number
	local per = math.max(1, num(tierXp, 1000))
	return math.clamp(math.floor(math.max(0, num(xp, 0)) / per), 0, math.max(0, math.floor(num(tiers, 50))))
end

-- Tag im 7er-Zyklus (1 … 7) und Zyklus-Nummer (1, 2, …) zur Serie
function ProgressMath.LoginDay(streak: number): (number, number)
	local s = math.max(1, math.floor(num(streak, 1)))
	local cycle = P.LoginCycle
	return ((s - 1) % cycle) + 1, math.floor((s - 1) / cycle) + 1
end

-- ---------------------------------------------------------------------
-- 10) BESTENLISTEN-KODIERUNG (§B11.1; Ganzzahl 0 … 9e15)
-- ---------------------------------------------------------------------
function ProgressMath.BoardLog(v: number): number
	local value = math.clamp(num(v, 0), 0, MAX_MONEY)
	return math.clamp(math.floor(math.log10(1 + value) * 1e12), 0, MAX_MONEY)
end

-- ≈ ursprünglicher Wert (Anzeige)
function ProgressMath.BoardLogDecode(v: number): number
	local value = math.max(0, num(v, 0))
	return math.max(0, 10 ^ (value / 1e12) - 1)
end

-- SkillScore × 10.000 + clamp(round(Ø-Tagesrendite_bp) + 5.000, 0, 9.999)
function ProgressMath.BoardLeague(score: number, avgBp: number): number
	local s = math.clamp(math.floor(num(score, 0) + 0.5), 0, 1000)
	local tie = math.clamp(math.floor(num(avgBp, 0) + 0.5) + 5000, 0, 9999)
	return s * 10000 + tie
end

-- round(Ø-Tagesrendite_bp) + 1.000.000
function ProgressMath.BoardReturn(avgBp: number): number
	return math.clamp(math.floor(num(avgBp, 0) + 0.5) + 1000000, 0, MAX_MONEY)
end

-- Börsengänge × 100 + Etage
function ProgressMath.BoardSkyline(ipos: number, floors: number): number
	local i = math.max(0, math.floor(num(ipos, 0)))
	local f = math.clamp(math.floor(num(floors, 0)), 0, 99)
	return math.clamp(i * 100 + f, 0, MAX_MONEY)
end

return ProgressMath
