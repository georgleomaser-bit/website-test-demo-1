-- =====================================================================
--  CLUTCH CLASH – Selbsttests Fortschritt (Server/Tests/ProgressionTests)
--  Besitzer: WP8 (Fortschritt). Vertrag: DESIGN.md C5.2 (SelfTestService) + C18 + WP8-Tests.
--  Gibt { [testName]: () -> () } zurück; jeder Fehler = FAIL.
--  Prüft: Config.Progression/Season.Validate leer, Quest-Rotation pro Tag deterministisch, Rad-Gewichte = 100,
--  Login-Kalender mit SkipDay (Util.SetDayOffset), Level-Kurve, Elo-Symmetrie, Meisterschaft, Saison-Fallback,
--  Pass-Belohnungen B21.2, Match-Belohnung (Abnahme 1), Chat-Umschreibung (Abnahme 6), Quest-Texte vorhanden.
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Lang = require(Shared:WaitForChild("Lang"))
local ProgressMath = require(Shared:WaitForChild("ProgressMath"))

local P = Config.Progression
local S = Config.Season

local function eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(("%s erwartet %s, bekommen %s"):format(label or "Wert", tostring(expected), tostring(actual)), 2)
	end
end

local function check(condition: boolean, label: string)
	if not condition then
		error(label, 2)
	end
end

local function noErrors(list: { string }, label: string)
	if #list > 0 then
		local shown = {}
		for i = 1, math.min(#list, 6) do
			shown[i] = list[i]
		end
		error(label .. ": " .. table.concat(shown, " | "), 2)
	end
end

local Tests = {}

Tests["Progression: Config.Progression.Validate leer"] = function()
	check(type(P.Validate) == "function", "Validate fehlt")
	noErrors(P.Validate(Config), "Config.Progression")
end

Tests["Progression: Config.Season.Validate leer"] = function()
	check(type(S.Validate) == "function", "Validate fehlt")
	noErrors(S.Validate(Config), "Config.Season")
end

Tests["Progression: Glücksrad-Gewichte = 100"] = function()
	local sum = 0
	for _, prize in ipairs(P.Wheel.Prizes) do
		sum += prize.W
	end
	check(math.abs(sum - 100) < 1e-9, "Summe " .. tostring(sum))
end

Tests["Progression: Quest-Rotation pro Tag deterministisch"] = function()
	local tiers = P.Quests.DailyTiers
	local userId = 123456
	local seenSets: { [string]: boolean } = {}
	for day = 20000, 20013 do
		local a = ProgressMath.PickDaily(P.Quests.Daily, tiers, ProgressMath.Seed(day, userId))
		local b = ProgressMath.PickDaily(P.Quests.Daily, tiers, ProgressMath.Seed(day, userId))
		eq(#a, P.Quests.DailyCount, "Tagesquests")
		eq(table.concat(a, ","), table.concat(b, ","), "gleicher Tag")
		-- je Stufe genau eine Quest
		local byId: { [string]: any } = {}
		for _, def in ipairs(P.Quests.Daily) do
			byId[def.Id] = def
		end
		for i, id in ipairs(a) do
			eq(byId[id].Tier, tiers[i], "Stufe " .. id)
		end
		seenSets[table.concat(a, ",")] = true
	end
	local variety = 0
	for _ in pairs(seenSets) do
		variety += 1
	end
	check(variety >= 5, "zu wenig Abwechslung über 14 Tage: " .. variety)
	local week = ProgressMath.PickWeekly(P.Quests.Weekly, P.Quests.WeeklyCount, ProgressMath.Seed(202642, userId))
	eq(#week, P.Quests.WeeklyCount, "Wochenquests")
	local unique: { [string]: boolean } = {}
	for _, id in ipairs(week) do
		check(not unique[id], "doppelte Wochenquest " .. id)
		unique[id] = true
	end
end

Tests["Progression: Login-Kalender mit SkipDay"] = function()
	local oldOffset = Util.GetDayOffset()
	local ok, err = pcall(function()
		local login = { LastDay = 0, CalDay = 0, Streak = 0, Best = 0, FreezeWeek = 0 }
		local length = #P.Login.Calendar
		local function step(offset: number)
			Util.SetDayOffset(offset)
			return ProgressMath.LoginStep(login, Util.UtcDay(), Util.IsoWeek(), length, P.Login.FreezesPerWeek)
		end
		local r = step(oldOffset)
		check(r ~= nil and r.CalDay == 1 and r.Streak == 1, "Tag 1")
		check(step(oldOffset) == nil, "gleicher Tag zweimal")
		r = step(oldOffset + 1)
		check(r ~= nil and r.CalDay == 2 and r.Streak == 2, "Folgetag")
		-- ein Tag ausgelassen: Kalender rückt trotzdem nur um 1 vor
		r = step(oldOffset + 3)
		check(r ~= nil and r.CalDay == 3, "Kalender rückt nur an Login-Tagen vor")
		-- lange Pause: Serie zurück, Kalender läuft weiter
		r = step(oldOffset + 20)
		check(r ~= nil and r.CalDay == 4 and r.Streak == 1, "lange Pause")
		for i = 1, 3 do
			r = step(oldOffset + 20 + i)
		end
		check(r ~= nil and r.CalDay == 7 and r.NewCycle, "voller Zyklus an Tag 7")
		r = step(oldOffset + 24)
		check(r ~= nil and r.CalDay == 1 and not r.NewCycle, "danach wieder Tag 1")
		check(login.Best >= 5, "Bestwert " .. tostring(login.Best))
	end)
	Util.SetDayOffset(oldOffset)
	if not ok then
		error(err, 0)
	end
end

Tests["Progression: Level-Kurve (B16.1)"] = function()
	eq(ProgressMath.XpToNext(1), 250, "XpToNext(1)")
	eq(ProgressMath.TotalForLevel(10), 4050, "Level 10")
	eq(ProgressMath.TotalForLevel(15), 8050, "Level 15")
	eq(ProgressMath.TotalForLevel(50), 71050, "Level 50")
	eq(ProgressMath.TotalForLevel(100), 267300, "Level 100")
	local level, inLevel = ProgressMath.LevelFromTotal(4050)
	check(level == 10 and inLevel == 0, "LevelFromTotal(4050)")
end

Tests["Progression: Elo-Symmetrie (B16.6)"] = function()
	for _, pair in ipairs({ { 1000, 1000 }, { 1200, 950 }, { 800, 1500 } }) do
		for _, k in ipairs({ P.Mmr.KNew, P.Mmr.K }) do
			local win = ProgressMath.EloDelta(pair[1], pair[2], 1, k)
			local loss = ProgressMath.EloDelta(pair[2], pair[1], 0, k)
			eq(win, -loss, ("Symmetrie %d/%d K%d"):format(pair[1], pair[2], k))
		end
	end
	eq(ProgressMath.EloDelta(1000, 1000, 1, 40), 20, "gleich stark, Sieg K40")
end

Tests["Progression: Meisterschafts-Stufen (B16.2)"] = function()
	eq(ProgressMath.MasteryTier(9), 0, "9 Pops")
	eq(ProgressMath.MasteryTier(10), 1, "10 Pops")
	eq(ProgressMath.MasteryTier(299), 4, "299 Pops")
	eq(ProgressMath.MasteryTier(6000), 10, "6000 Pops")
	eq(#P.Mastery.Rewards, 10, "Belohnungen")
end

Tests["Progression: Saison-Fallback (B21.2)"] = function()
	local seasons = S.Seasons
	local first = ProgressMath.PickSeason(seasons, 0)
	check(first ~= nil and first.Id == 1, "vor allen Saisons -> Saison 1")
	local future = ProgressMath.PickSeason(seasons, os.time() + 10 * 365 * 86400)
	check(future ~= nil, "nach allen Fenstern -> jüngste gestartete")
	local start = ProgressMath.ParseIsoUtc(seasons[1].StartUtc)
	check(start ~= nil, "StartUtc lesbar")
	local inside = ProgressMath.PickSeason(seasons, (start :: number) + 86400)
	check(inside ~= nil and inside.Id == seasons[1].Id, "im Fenster")
end

Tests["Progression: Pass-Belohnungen (B21.2)"] = function()
	local season = S.Seasons[1]
	eq(season.Tiers, 30, "Stufen")
	eq(season.TierXp, 3000, "Pass-XP je Stufe")
	local freeCount, freeGems, premCount, premGems = 0, 0, 0, 0
	for tier = 1, season.Tiers do
		local free = season.Free[tostring(tier)]
		local prem = season.Premium[tostring(tier)]
		if free then
			freeCount += 1
			freeGems += free.Gems or 0
			eq(tier % 2, 0, "Gratis nur jede 2. Stufe (" .. tier .. ")")
		end
		if prem then
			premCount += 1
			premGems += prem.Gems or 0
			check(prem.Coins == nil and prem.Keys == nil, "Premium ohne Coins/Schlüssel (" .. tier .. ")")
		end
	end
	eq(freeCount, 15, "Gratis-Belohnungen")
	eq(freeGems, 150, "Gratis-Gems")
	eq(premCount, 30, "Premium-Belohnungen")
	eq(premGems, 450, "Premium-Gems")
end

Tests["Progression: Match-Belohnung 1v1 (Abnahme 1)"] = function()
	local win = { Won = true, RoundsWon = 4, Elims = 5, Headshots = 2, Mvp = true }
	local xp = ProgressMath.MatchXp(win, P.Xp) + P.GG.Xp
	check(xp >= 240 and xp <= 300, "1v1-Sieg ≈ 270 XP, ist " .. xp)
	local coins = ProgressMath.MatchCoins(win, P.Coins, {})
	check(coins >= 140 and coins <= 180, "1v1-Sieg ≈ 159 Coins, ist " .. coins)
	eq(ProgressMath.MatchCoins(win, P.Coins, { Practice = true }), 0, "Practice 0 Coins")
	local bots = ProgressMath.MatchCoins(win, P.Coins, { VsBots = true })
	eq(bots, math.floor(coins * P.Coins.BotMult + 0.5), "Bots ×0.6")
	check(P.Coins.BotDailyCap == 2500, "Bot-Tageslimit 2.500")
end

Tests["Progression: Chat-Umschreibung (Abnahme 6)"] = function()
	local rewrites = P.Chat.Rewrites
	eq(ProgressMath.RewriteChat("ez", rewrites, "de"), "gg wp", "ez")
	eq(ProgressMath.RewriteChat("EZ noob", rewrites, "en"), "gg wp friend", "ganze Wörter")
	eq(ProgressMath.RewriteChat("mein Ping ist schlecht", rewrites, "de"), nil, "normale Wörter bleiben")
	eq(ProgressMath.RewriteChat("easy", rewrites, "en"), nil, "Teilwörter bleiben")
end

Tests["Progression: Texte für alle Quests und Tafeln"] = function()
	local missing = {}
	for _, listName in ipairs({ "Daily", "Weekly", "Beginner" }) do
		for _, def in ipairs(P.Quests[listName]) do
			if not Lang.Has("prog.q." .. def.Id) then
				table.insert(missing, "prog.q." .. def.Id)
			end
		end
	end
	for _, board in ipairs(P.Leaderboards) do
		if not Lang.Has("prog.announceTop." .. board) then
			table.insert(missing, "prog.announceTop." .. board)
		end
	end
	noErrors(missing, "fehlende Texte")
	local beginnerCoins = 0
	for _, step in ipairs(P.Quests.Beginner) do
		beginnerCoins += step.Coins
	end
	eq(beginnerCoins, 1250, "Anfänger-Kette Coins")
end

return Tests
