-- =====================================================================
--  CLUTCH CLASH – Luau-CLI-Test für Shared/ProgressMath (WP8)
--  Start im Projektordner:  <scratchpad>/luau-build/luau tests/progressmath.test.luau
--  Prüft: Level-Summen aus B16.1, Elo-Symmetrie, Meisterschafts-Stufen, Saison-Fallback,
--  Login-Kalender (Freeze), Quest-Rotation deterministisch, Kopfgeld, Multiplikator-Deckel.
--  Ein Fehler beendet das Skript mit Exit-Code 1.
-- =====================================================================

local ProgressMath = require("../src/shared/ProgressMath")

local passed, failed = 0, 0

local function check(name: string, condition: boolean, detail: string?)
	if condition then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. (if detail then " – " .. detail else ""))
	end
end

local function eq(name: string, actual: any, expected: any)
	check(name, actual == expected, ("erwartet %s, bekommen %s"):format(tostring(expected), tostring(actual)))
end

-- 1) XP-Kurve (B16.1): XPToNext(L) = 250 + 50·(L−1)
eq("XpToNext(1)", ProgressMath.XpToNext(1), 250)
eq("XpToNext(2)", ProgressMath.XpToNext(2), 300)
eq("XpToNext(99)", ProgressMath.XpToNext(99), 250 + 50 * 98)
eq("XpToNext(100) = 0 (Max)", ProgressMath.XpToNext(100), 0)
eq("XpToNext(0) wie Level 1", ProgressMath.XpToNext(0), 250)
eq("MaxLevel", ProgressMath.MaxLevel(), 100)

-- Gesamt-Summen aus der Spec
eq("TotalForLevel(2)", ProgressMath.TotalForLevel(2), 250)
eq("TotalForLevel(10)", ProgressMath.TotalForLevel(10), 4050)
eq("TotalForLevel(15)", ProgressMath.TotalForLevel(15), 8050)
eq("TotalForLevel(50)", ProgressMath.TotalForLevel(50), 71050)
eq("TotalForLevel(100)", ProgressMath.TotalForLevel(100), 267300)

-- Summe der Einzelschritte = geschlossene Formel
local running = 0
for level = 1, 99 do
	running += ProgressMath.XpToNext(level)
	if running ~= ProgressMath.TotalForLevel(level + 1) then
		check("Summe bis Level " .. (level + 1), false)
		break
	end
end
eq("Summe aller Schritte", running, 267300)

local function levelOf(total: number): (number, number)
	return ProgressMath.LevelFromTotal(total)
end
do
	local l, x = levelOf(0)
	check("LevelFromTotal(0)", l == 1 and x == 0)
	l, x = levelOf(249)
	check("LevelFromTotal(249)", l == 1 and x == 249)
	l, x = levelOf(250)
	check("LevelFromTotal(250) = Level 2", l == 2 and x == 0)
	l, x = levelOf(4049)
	check("LevelFromTotal(4049)", l == 9 and x == 649, ("%d/%d"):format(l, x))
	l, x = levelOf(4050)
	check("LevelFromTotal(4050) = Level 10", l == 10 and x == 0)
	l, x = levelOf(8050)
	check("LevelFromTotal(8050) = Level 15", l == 15 and x == 0)
	l, x = levelOf(71050)
	check("LevelFromTotal(71050) = Level 50", l == 50 and x == 0)
	l, x = levelOf(267300)
	check("LevelFromTotal(267300) = Level 100", l == 100 and x == 0)
	l, x = levelOf(10 ^ 9)
	check("LevelFromTotal(riesig) = 100", l == 100 and x == 0)
	l, x = levelOf(0 / 0)
	check("LevelFromTotal(NaN)", l == 1 and x == 0)
	l, x = levelOf(-50)
	check("LevelFromTotal(negativ)", l == 1 and x == 0)
end

-- 2) Elo (B16.6)
eq("Expected gleich", ProgressMath.Expected(1000, 1000), 0.5)
check("Expected +400 ≈ 0.909", math.abs(ProgressMath.Expected(1400, 1000) - 10 / 11) < 1e-9)
check(
	"Expected-Summe = 1",
	math.abs(ProgressMath.Expected(1234, 987) + ProgressMath.Expected(987, 1234) - 1) < 1e-12
)
eq("EloDelta gleich, Sieg K40", ProgressMath.EloDelta(1000, 1000, 1, 40), 20)
eq("EloDelta gleich, Niederlage K40", ProgressMath.EloDelta(1000, 1000, 0, 40), -20)
eq("EloDelta gleich, Remis", ProgressMath.EloDelta(1000, 1000, 0.5, 24), 0)
local symmetric = true
local ratings = { 600, 875, 1000, 1013, 1150, 1333, 1600, 2100 }
for _, a in ipairs(ratings) do
	for _, b in ipairs(ratings) do
		for _, k in ipairs({ 24, 40, 32 }) do
			local win = ProgressMath.EloDelta(a, b, 1, k)
			local loss = ProgressMath.EloDelta(b, a, 0, k)
			if win ~= -loss then
				symmetric = false
				print(("  Elo asymmetrisch: %d vs %d K%d: %d / %d"):format(a, b, k, win, loss))
			end
		end
	end
end
check("Elo-Symmetrie (Sieger + = Verlierer −)", symmetric)
check("Favorit gewinnt weniger", ProgressMath.EloDelta(1400, 1000, 1, 24) < ProgressMath.EloDelta(1000, 1400, 1, 24))

-- 3) Meisterschaft (B16.2)
local tierCases = {
	{ 0, 0 },
	{ 9, 0 },
	{ 10, 1 },
	{ 29.5, 1 },
	{ 30, 2 },
	{ 75, 3 },
	{ 149, 3 },
	{ 150, 4 },
	{ 300, 5 },
	{ 600, 6 },
	{ 999, 6 },
	{ 1000, 7 },
	{ 2000, 8 },
	{ 3500, 9 },
	{ 5999, 9 },
	{ 6000, 10 },
	{ 1e9, 10 },
}
for _, case in ipairs(tierCases) do
	eq(("MasteryTier(%s)"):format(tostring(case[1])), ProgressMath.MasteryTier(case[1]), case[2])
end
eq("MasteryTier(NaN)", ProgressMath.MasteryTier(0 / 0), 0)
eq("MasteryGoal(0)", ProgressMath.MasteryGoal(0), 10)
eq("MasteryGoal(9)", ProgressMath.MasteryGoal(9), 6000)
eq("MasteryGoal(10) = nil", ProgressMath.MasteryGoal(10), nil)

-- 4) Datum + Saison-Fallback (B21.2)
eq("ParseIsoUtc(Epoch)", ProgressMath.ParseIsoUtc("1970-01-01T00:00:00Z"), 0)
eq("ParseIsoUtc(S1 Start)", ProgressMath.ParseIsoUtc("2026-10-15T00:00:00Z"), 1792022400)
eq("ParseIsoUtc(nur Datum)", ProgressMath.ParseIsoUtc("2026-10-15"), 1792022400)
eq("ParseIsoUtc(kaputt)", ProgressMath.ParseIsoUtc("15.10.2026"), nil)
eq("ParseIsoUtc(Monat 13)", ProgressMath.ParseIsoUtc("2026-13-01T00:00:00Z"), nil)

local seasons = {
	{ Id = 1, StartUtc = "2026-10-15T00:00:00Z", EndUtc = "2026-12-10T00:00:00Z" },
	{ Id = 2, StartUtc = "2026-12-10T00:00:00Z", EndUtc = "2027-02-04T00:00:00Z" },
}
local function seasonAt(iso: string, list: { any }?): number?
	local picked = ProgressMath.PickSeason(list or seasons, ProgressMath.ParseIsoUtc(iso) :: number)
	return if picked then picked.Id else nil
end
eq("Saison vor dem Start -> 1", seasonAt("2026-10-11T12:00:00Z"), 1)
eq("Saison im Fenster S1", seasonAt("2026-11-01T00:00:00Z"), 1)
eq("Saison Grenze -> S2", seasonAt("2026-12-10T00:00:00Z"), 2)
eq("Saison nach allen Fenstern -> jüngste", seasonAt("2027-06-01T00:00:00Z"), 2)
local gap = {
	{ Id = 1, StartUtc = "2026-10-15T00:00:00Z", EndUtc = "2026-12-10T00:00:00Z" },
	{ Id = 3, StartUtc = "2027-03-01T00:00:00Z", EndUtc = "2027-05-01T00:00:00Z" },
}
eq("Lücke zwischen Saisons -> letzte gestartete", seasonAt("2027-01-15T00:00:00Z", gap), 1)
local noOne = {
	{ Id = 7, StartUtc = "2027-03-01T00:00:00Z", EndUtc = "2027-05-01T00:00:00Z" },
	{ Id = 5, StartUtc = "2027-01-01T00:00:00Z", EndUtc = "2027-02-01T00:00:00Z" },
}
eq("Vor allen, keine Id 1 -> früheste", seasonAt("2026-01-01T00:00:00Z", noOne), 5)
eq("Leere Liste -> nil", ProgressMath.PickSeason({}, 0), nil)

eq("PassTier(0)", ProgressMath.PassTier(0, 3000, 30), 0)
eq("PassTier(2999)", ProgressMath.PassTier(2999, 3000, 30), 0)
eq("PassTier(3000)", ProgressMath.PassTier(3000, 3000, 30), 1)
eq("PassTier(90000)", ProgressMath.PassTier(90000, 3000, 30), 30)
eq("PassTier(gedeckelt)", ProgressMath.PassTier(999999, 3000, 30), 30)

-- 5) Login-Kalender (B16.4)
local login = { LastDay = 0, CalDay = 0, Streak = 0, Best = 0, FreezeWeek = 0 }
local r = ProgressMath.LoginStep(login, 20000, 202641, 7, 1)
check("Login Tag 1", r ~= nil and r.CalDay == 1 and r.Streak == 1)
check("Login gleicher Tag -> nil", ProgressMath.LoginStep(login, 20000, 202641, 7, 1) == nil)
r = ProgressMath.LoginStep(login, 20001, 202641, 7, 1)
check("Login Folgetag", r ~= nil and r.CalDay == 2 and r.Streak == 2 and not r.UsedFreeze)
r = ProgressMath.LoginStep(login, 20003, 202641, 7, 1) -- ein Tag verpasst -> Freeze
check("Login Freeze", r ~= nil and r.CalDay == 3 and r.Streak == 3 and r.UsedFreeze)
r = ProgressMath.LoginStep(login, 20005, 202641, 7, 1) -- noch ein Tag verpasst, gleiche Woche -> kein Freeze
check("Login zweiter Freeze gleiche Woche -> Serie 1", r ~= nil and r.CalDay == 4 and r.Streak == 1)
r = ProgressMath.LoginStep(login, 20007, 202642, 7, 1) -- neue Woche -> Freeze wieder da
check("Login Freeze neue Woche", r ~= nil and r.Streak == 2 and r.UsedFreeze)
r = ProgressMath.LoginStep(login, 20020, 202644, 7, 1) -- lange weg: nur Serie zurück, Kalender rückt weiter
check("Login lange Pause", r ~= nil and r.CalDay == 6 and r.Streak == 1)
r = ProgressMath.LoginStep(login, 20021, 202644, 7, 1)
check("Login Tag 7 = voller Zyklus", r ~= nil and r.CalDay == 7 and r.NewCycle)
r = ProgressMath.LoginStep(login, 20022, 202644, 7, 1)
check("Login nach Tag 7 wieder Tag 1", r ~= nil and r.CalDay == 1 and not r.NewCycle)
eq("Login Bestwert", login.Best, 3)
local noFreeze = { LastDay = 100, CalDay = 2, Streak = 4, Best = 4, FreezeWeek = 0 }
r = ProgressMath.LoginStep(noFreeze, 102, 1, 7, 0)
check("Login ohne Freezes", r ~= nil and r.Streak == 1)

-- 6) Kopfgeld + Multiplikatoren (B16.7 / B16.1)
eq("Bounty(4)", ProgressMath.Bounty(4), 0)
eq("Bounty(5)", ProgressMath.Bounty(5), 100)
eq("Bounty(6)", ProgressMath.Bounty(6), 125)
eq("Bounty(13)", ProgressMath.Bounty(13), 300)
eq("Bounty(40) gedeckelt", ProgressMath.Bounty(40), 300)
eq("CapMult ohne Boni", ProgressMath.CapMult(0, 3), 1)
eq("CapMult VIP", ProgressMath.CapMult(0.2, 3), 1.2)
eq("CapMult alles", ProgressMath.CapMult(0.2 + 1 + 1 + 1 + 1, 3), 3)

-- 7) Quest-Rotation deterministisch (B16.3)
local pool = {
	{ Id = "A", Tier = "Easy" },
	{ Id = "B", Tier = "Easy" },
	{ Id = "C", Tier = "Medium" },
	{ Id = "D", Tier = "Medium" },
	{ Id = "E", Tier = "Hard" },
	{ Id = "F", Tier = "Hard" },
	{ Id = "G", Tier = "Hard" },
}
local tiers = { "Easy", "Medium", "Hard" }
local first = ProgressMath.PickDaily(pool, tiers, ProgressMath.Seed(20000, 123))
local again = ProgressMath.PickDaily(pool, tiers, ProgressMath.Seed(20000, 123))
check("PickDaily 3 Stück", #first == 3)
check("PickDaily deterministisch", table.concat(first, ",") == table.concat(again, ","))
local tierOf = {}
for _, def in ipairs(pool) do
	tierOf[def.Id] = def.Tier
end
check(
	"PickDaily je Stufe eine",
	tierOf[first[1]] == "Easy" and tierOf[first[2]] == "Medium" and tierOf[first[3]] == "Hard"
)
local variety: { [string]: boolean } = {}
for day = 20000, 20030 do
	variety[table.concat(ProgressMath.PickDaily(pool, tiers, ProgressMath.Seed(day, 123)), ",")] = true
end
local kinds = 0
for _ in pairs(variety) do
	kinds += 1
end
check("PickDaily wechselt über die Tage", kinds > 3, tostring(kinds))
local weekly = ProgressMath.PickWeekly(pool, 5, ProgressMath.Seed(202641, 123))
local weeklyAgain = ProgressMath.PickWeekly(pool, 5, ProgressMath.Seed(202641, 123))
check("PickWeekly 5 Stück", #weekly == 5)
check("PickWeekly deterministisch", table.concat(weekly, ",") == table.concat(weeklyAgain, ","))
local seen: { [string]: boolean } = {}
local unique = true
for _, id in ipairs(weekly) do
	if seen[id] then
		unique = false
	end
	seen[id] = true
end
check("PickWeekly ohne Doppelte", unique)
check("PickWeekly mehr als Pool", #ProgressMath.PickWeekly(pool, 50, 1) == #pool)
local rng = ProgressMath.Rng(42)
local inRange = true
for _ = 1, 1000 do
	local v = rng()
	if v < 0 or v >= 1 then
		inRange = false
	end
end
check("Rng in [0,1)", inRange)
check("Seed negative UserId ok", ProgressMath.Seed(20000, -1) >= 0)

-- 8) Configure übernimmt die Kurve
ProgressMath.Configure({ Curve = { Base = 100, Step = 10, MaxLevel = 5 } })
eq("Configure XpToNext(1)", ProgressMath.XpToNext(1), 100)
eq("Configure XpToNext(5) = 0", ProgressMath.XpToNext(5), 0)
ProgressMath.Configure({ Curve = { Base = 250, Step = 50, MaxLevel = 100 } })
eq("Configure zurück", ProgressMath.TotalForLevel(100), 267300)

-- 9) Match-Belohnung (WP8-Abnahme 1): 1v1-Sieg gegen Menschen ≈ 270 XP / ≈ 159 Coins
local XP_CFG = { Played = 40, Win = 60, Round = 12, Elim = 15, Assist = 7, HeadElim = 5, MeleeElim = 10, Mvp = 20, CrownDefence = 15 }
local COIN_CFG = { Played = 30, Round = 10, Elim = 6, Assist = 3, HeadElim = 2, Win = 50, Mvp = 15, StreakStep = 5,
	StreakCap = 30, BotMult = 0.6, BotMin = 15, DrawBonus = 0.1 }
local win1v1 = { Won = true, RoundsWon = 4, Elims = 5, Assists = 0, Headshots = 2, MeleeElims = 0, Mvp = true }
local winXp = ProgressMath.MatchXp(win1v1, XP_CFG) + 5 -- + GG
check("1v1-Sieg ≈ 270 XP", winXp >= 240 and winXp <= 300, tostring(winXp))
local winCoins = ProgressMath.MatchCoins(win1v1, COIN_CFG, {})
check("1v1-Sieg ≈ 159 Coins", winCoins >= 140 and winCoins <= 180, tostring(winCoins))
local loss1v1 = { Won = false, RoundsWon = 2, Elims = 3, Assists = 1, Headshots = 1 }
local lossXp = ProgressMath.MatchXp(loss1v1, XP_CFG)
check("1v1-Niederlage ≈ 136 XP", lossXp >= 100 and lossXp <= 160, tostring(lossXp))
local lossCoins = ProgressMath.MatchCoins(loss1v1, COIN_CFG, {})
check("1v1-Niederlage ≈ 62 Coins", lossCoins >= 50 and lossCoins <= 80, tostring(lossCoins))
eq("Practice 0 Coins", ProgressMath.MatchCoins(win1v1, COIN_CFG, { Practice = true }), 0)
eq("Bots ×0.6", ProgressMath.MatchCoins(win1v1, COIN_CFG, { VsBots = true }), math.floor(winCoins * 0.6 + 0.5))
eq("Bots mindestens 15", ProgressMath.MatchCoins({}, COIN_CFG, { VsBots = true }), 18)
eq("Bots mindestens 15 (leer)", ProgressMath.MatchCoins({}, { Played = 0, BotMult = 0.6, BotMin = 15 }, { VsBots = true }), 15)
eq("Serie 1 ohne Bonus", ProgressMath.MatchCoins({ Won = true }, COIN_CFG, { Streak = 1 }), 80)
eq("Serie 3 +10", ProgressMath.MatchCoins({ Won = true }, COIN_CFG, { Streak = 3 }), 90)
eq("Serie 20 gedeckelt +30", ProgressMath.MatchCoins({ Won = true }, COIN_CFG, { Streak = 20 }), 110)
eq("Comeback +25 %", ProgressMath.MatchCoins({}, COIN_CFG, { Comeback = true, ComebackBonus = 0.25 }), 38)
eq("Event ×2", ProgressMath.MatchCoins({}, COIN_CFG, { EventMult = 2 }), 60)
eq("Event gedeckelt ×2", ProgressMath.MatchCoins({}, COIN_CFG, { EventMult = 99 }), 60)
eq("Krone Mensch +40", ProgressMath.MatchCoins({ CrownDefences = 1, CrownVsHuman = 1 }, COIN_CFG, { CrownHumanCoins = 40, CrownBotCoins = 10 }), 70)
eq("Krone Bot +10", ProgressMath.MatchCoins({ CrownDefences = 1 }, COIN_CFG, { CrownHumanCoins = 40, CrownBotCoins = 10 }), 40)
eq("Unentschieden +10 %", ProgressMath.MatchCoins({ Draw = true }, COIN_CFG, {}), 33)
eq("MatchXp leer = Played", ProgressMath.MatchXp({}, XP_CFG), 40)
eq("MatchXp NaN-sicher", ProgressMath.MatchXp({ Elims = 0 / 0 }, XP_CFG), 40)

-- 10) Chat-Umschreibung (WP8-Abnahme 6)
local REWRITES = {
	ez = { de = "gg wp", en = "gg wp" },
	ggez = { de = "GG ❤", en = "GG ❤" },
	noob = { de = "Freund", en = "friend" },
	p2w = { de = "faires Loadout", en = "fair loadout" },
	trash = { de = "gutes Spiel", en = "good game" },
}
eq("Chat ez", ProgressMath.RewriteChat("ez", REWRITES, "de"), "gg wp")
eq("Chat EZ groß", ProgressMath.RewriteChat("EZ", REWRITES, "en"), "gg wp")
eq("Chat ganze Wörter", ProgressMath.RewriteChat("so ein noob!", REWRITES, "de"), "so ein Freund!")
eq("Chat englisch", ProgressMath.RewriteChat("NOOB", REWRITES, "en"), "friend")
eq("Chat mehrere", ProgressMath.RewriteChat("ggez, trash p2w", REWRITES, "en"), "GG ❤, good game fair loadout")
eq("Chat schlecht bleibt", ProgressMath.RewriteChat("mein Ping ist schlecht", REWRITES, "de"), nil)
eq("Chat Teilwort bleibt (easy)", ProgressMath.RewriteChat("easy peasy", REWRITES, "en"), nil)
eq("Chat Teilwort bleibt (noobs)", ProgressMath.RewriteChat("noobs", REWRITES, "en"), nil)
eq("Chat Umlaut-Wort bleibt", ProgressMath.RewriteChat("Trashübung", REWRITES, "de"), nil)
eq("Chat ez in Wort bleibt", ProgressMath.RewriteChat("jezt", REWRITES, "de"), nil)
eq("Chat leer", ProgressMath.RewriteChat("", REWRITES, "de"), nil)
eq("Chat Satzzeichen", ProgressMath.RewriteChat("...ez?!", REWRITES, "de"), "...gg wp?!")

-- 11) Belohnung als Text
local function fakeT(key: string, ...: any): string
	return key .. "=" .. table.concat({ ... }, ",")
end
eq("Describe Coins+Keys", ProgressMath.DescribeReward({ Keys = 1, Coins = 150 }, fakeT), "prog.r.coins=150 + prog.r.keys=1")
eq("Describe Boost Minuten", ProgressMath.DescribeReward({ XpBoostSeconds = 900 }, fakeT), "prog.r.xpBoost=15")
eq("Describe Kosmetik", ProgressMath.DescribeReward({ Cosmetic = "C_Ghost" }, fakeT, function(id)
	return "<" .. id .. ">"
end), "<C_Ghost>")
eq("Describe leer", ProgressMath.DescribeReward(nil, fakeT), "")

print(("[progressmath.test] %d/%d PASS"):format(passed, passed + failed))
if failed > 0 then
	error(("%d Test(s) fehlgeschlagen"):format(failed))
end
