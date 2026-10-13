-- =====================================================================
--  AKYTEX TYCOON – Luau-CLI-Test für Shared/ProgressMath + Config.Progression/Season/Rewards (ohne Roblox)
--  Besitzer: WP9 (Fortschritt, Tutorial, Sozial, Bestenlisten). DESIGN.md §D WP9 "Tests": Level-Kurve, Lizenz-
--  Ermittlung, Ruf-Stufen/Abbau/Untergrenzen, Titel-Grenzen, deterministische Quest-Auswahl – dazu Sterne-Formel,
--  Know-how-Summe, Bestenlisten-Kodierung, Login-Zyklus, Saison-Stufen, Config-Prüfungen und Text-Abdeckung (DE + EN)
--  aller dynamisch gebildeten Lang-Schlüssel (Lektionen, Know-how, Vorstand, Prüfungen, Quests, Erfolge …).
--  Start (im Projektordner):  <scratchpad>/luau-build/luau tests/progressmath.test.luau
-- =====================================================================

local PM = require("../src/shared/ProgressMath")
local Progression = require("../src/shared/Config/Progression")
local Season = require("../src/shared/Config/Season")
local Rewards = require("../src/shared/Config/Rewards")
local LangProgress = require("../src/shared/Lang/Progress")
local LangTutorial = require("../src/shared/Lang/Tutorial")
local LangSocial = require("../src/shared/Lang/Social")

PM.Configure(Progression)

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

local function near(actual: number, expected: number, eps: number, label: string?)
	if math.abs(actual - expected) > eps then
		error(("%s erwartet ≈ %s, bekommen %s"):format(label or "Wert", tostring(expected), tostring(actual)), 2)
	end
end

local function truthy(value: any, label: string)
	if not value then
		error(label, 2)
	end
end

-- ---------------------------------------------------------------------
-- 1) LEVEL-KURVE: XP_gesamt(L) = ceil(12,5 × (L − 1)²)
-- ---------------------------------------------------------------------
check("Level-Kurve Stützstellen", function()
	eq(PM.LevelCurve(), 12.5, "Kurve")
	eq(PM.XpForLevel(1), 0, "L1")
	eq(PM.XpForLevel(2), 13, "L2")
	eq(PM.XpForLevel(10), 1013, "L10")
	eq(PM.XpForLevel(100), 122513, "L100")
	eq(PM.XpForLevel(250), PM.XpForLevel(100), "über MaxLevel geklemmt")
end)

check("Level aus XP (Grenzen + Fortschritt)", function()
	local level, progress = PM.LevelFromXp(0)
	eq(level, 1, "0 XP")
	eq(progress, 0, "0 XP Fortschritt")
	eq((PM.LevelFromXp(1012)), 9, "1012 XP")
	eq((PM.LevelFromXp(1013)), 10, "1013 XP")
	eq((PM.LevelFromXp(1e12)), 100, "Riesen-XP")
	local _, half = PM.LevelFromXp(PM.XpForLevel(5) + (PM.XpForLevel(6) - PM.XpForLevel(5)) / 2)
	near(half, 0.5, 1e-9, "halbe Stufe")
	local last = 0
	for l = 1, 100 do
		local xp = PM.XpForLevel(l)
		truthy(xp >= last, "Kurve muss steigen bei L" .. l)
		last = xp
		eq((PM.LevelFromXp(xp)), l, "Rundreise L" .. l)
	end
end)

-- ---------------------------------------------------------------------
-- 2) LIZENZ-ERMITTLUNG (XP + Prüfungen aller Stufen bis dahin, nacheinander)
-- ---------------------------------------------------------------------
check("Lizenz-Ermittlung", function()
	local L = Progression.Licences
	eq(PM.LicenceFor(0, {}, L), 1, "Start")
	eq(PM.LicenceFor(299, { ProtectPair = true }, L), 1, "zu wenig XP")
	eq(PM.LicenceFor(300, {}, L), 1, "Prüfung fehlt")
	eq(PM.LicenceFor(300, { ProtectPair = true }, L), 2, "Azubi II")
	eq(PM.LicenceFor(5000, { ProtectPair = true }, L), 2, "Azubi III braucht Sectors3 + ProtectedProfit")
	local upTo5 =
		{ ProtectPair = true, Sectors3 = true, ProtectedProfit = true, AsExpected = true, BuyAfterGood = true }
	eq(PM.LicenceFor(7000, upTo5, L), 5, "Trader II ohne eigene Prüfung")
	eq(PM.LicenceFor(13999, upTo5, L), 5, "Trader III: XP fehlt")
	eq(PM.LicenceFor(14000, upTo5, L), 5, "Trader III: CrashSurvive fehlt")
	-- Lücke in einer früheren Stufe blockiert alles darüber
	local gap = table.clone(upTo5)
	gap.Sectors3 = nil
	gap.CrashSurvive = true
	eq(PM.LicenceFor(1e9, gap, L), 2, "Lücke bei Azubi III")
	local all: { [string]: boolean } = {}
	for _, task in ipairs(Progression.ExamTasks) do
		all[task.Key] = true
	end
	eq(PM.LicenceFor(1e12, all, L), #L, "alles erfüllt -> Legende")
end)

check("Lizenz-Tabelle steigt (Basis in Cent, Bau-Kurs, Turm-Bonus)", function()
	local last = { Xp = -1, Basis = 0, BauKurs = 0, TowerBonus = -1 }
	for i, lic in ipairs(Progression.Licences) do
		truthy(lic.Xp > last.Xp, "Xp steigt bei " .. i)
		truthy(lic.Basis > last.Basis and lic.Basis % 1 == 0, "Basis steigt/ganzzahlig bei " .. i)
		truthy(lic.BauKurs > last.BauKurs, "Bau-Kurs steigt bei " .. i)
		truthy(lic.TowerBonus >= last.TowerBonus, "Turm-Bonus fällt nie bei " .. i)
		last = lic
	end
	eq(Progression.Licences[1].Basis, 2500000, "Azubi I Basis 25.000 AKY")
	eq(Progression.Licences[2].Basis, 5000000, "Azubi II Basis 50.000 AKY (verdoppelt)")
end)

-- ---------------------------------------------------------------------
-- 3) RUF: Stufen, Untergrenzen, Abbau
-- ---------------------------------------------------------------------
check("Ruf-Stufen", function()
	eq(PM.RufLevel(0), 0, "0")
	eq(PM.RufLevel(9), 0, "9")
	eq(PM.RufLevel(10), 1, "10")
	eq(PM.RufLevel(549), 9, "549")
	eq(PM.RufLevel(550), 10, "550")
	eq(PM.RufLevel(1e9), 10, "Deckel 10")
	eq(PM.RufLevel(-5), 0, "negativ")
end)

check("Ruf-Untergrenzen nach Lizenz", function()
	eq(PM.RufFloor(1), 0, "Azubi I")
	eq(PM.RufFloor(3), 0, "Azubi III")
	eq(PM.RufFloor(4), 2, "Trader I")
	eq(PM.RufFloor(7), 4, "Fondsmanager I")
	eq(PM.RufFloor(10), 6, "Legende")
end)

check("Ruf-Abbau −8 %/Tag, max. 30 Tage, nie unter die Untergrenze", function()
	eq(PM.RufDecay(100, 0, 0), 100, "0 Tage")
	eq(PM.RufDecay(100, 1, 0), 92, "1 Tag")
	eq(PM.RufDecay(100, 2, 0), 84, "2 Tage")
	eq(PM.RufDecay(100, 30, 0), PM.RufDecay(100, 99, 0), "max. 30 Tage")
	eq(PM.RufDecay(100, 30, 0), math.floor(100 * 0.92 ^ 30), "30 Tage")
	eq(PM.RufDecay(100, 30, 2), 30, "Untergrenze Stufe 2 = 30 Punkte")
	eq(PM.RufDecay(20, 5, 2), 20, "schon unter der Untergrenze: bleibt")
	eq(PM.RufDecay(600, 30, 6), 210, "Legende: Stufe 6 = 210 Punkte")
	truthy(PM.RufDecay(1000, 3, 0) % 1 == 0, "ganzzahlig")
end)

check("Trader-Faktor = (1 + Turm-Bonus) × (1 + 0,03 × Ruf)", function()
	local total, lic, ruf = PM.TraderFactor(0.12, 5)
	near(lic, 1.12, 1e-12, "Lizenz-Teil")
	near(ruf, 1.15, 1e-12, "Ruf-Teil")
	near(total, 1.12 * 1.15, 1e-12, "gesamt")
	near(PM.RufFactor(99), 1.3, 1e-12, "Ruf geklemmt auf 10")
end)

-- ---------------------------------------------------------------------
-- 4) VERMÖGENS-TITEL
-- ---------------------------------------------------------------------
check("Titel-Grenzen", function()
	eq(PM.WealthTitle(0), "Starter", "0")
	eq(PM.WealthTitle(9999), "Starter", "9.999")
	eq(PM.WealthTitle(1e4), "TenK", "10.000")
	eq(PM.WealthTitle(999999), "HundredK", "999.999")
	eq(PM.WealthTitle(1e6), "Millionaire", "1 Mio")
	eq(PM.WealthTitle(1e9), "Billionaire", "1 Mrd")
	eq(PM.WealthTitle(5e14), "MultiTrillionaire", "500 Bio")
	eq(PM.WealthTitle(1e15), "QuadBoss", "1e15")
	eq(PM.WealthTitle(0 / 0), "Starter", "NaN")
	for _, entry in ipairs(Progression.Titles.Wealth) do
		truthy(Progression.TitleByKey[entry.Key] ~= nil, "TitleByKey fehlt für " .. entry.Key)
	end
end)

-- ---------------------------------------------------------------------
-- 5) DETERMINISTISCHE QUEST-AUSWAHL
-- ---------------------------------------------------------------------
check("Quest-Auswahl deterministisch und ohne Doppelte", function()
	local pool = Progression.Quests.Daily
	local a = PM.QuestPick(123456, pool, 3)
	local b = PM.QuestPick(123456, pool, 3)
	eq(#a, 3, "Anzahl")
	for i = 1, 3 do
		eq(a[i], b[i], "gleicher Seed, Eintrag " .. i)
	end
	local seen: { [any]: boolean } = {}
	for _, entry in ipairs(a) do
		truthy(not seen[entry], "doppelte Quest")
		seen[entry] = true
	end
	local different = 0
	for seed = 1, 20 do
		local x = PM.QuestPick(seed, pool, 3)
		local y = PM.QuestPick(seed + 1000, pool, 3)
		if x[1] ~= y[1] or x[2] ~= y[2] or x[3] ~= y[3] then
			different += 1
		end
	end
	truthy(different >= 15, "verschiedene Seeds sollen streuen (" .. different .. "/20)")
	eq(#PM.QuestPick(1, pool, 999), #pool, "n > Pool -> ganzer Pool")
	eq(#PM.QuestPick(1, {}, 3), 0, "leerer Pool")
	-- Verteilung: über viele Tage kommt jede Vorlage vor
	local hits: { [any]: number } = {}
	for seed = 1, 3000 do
		for _, entry in ipairs(PM.QuestPick(seed * 7919, pool, 3)) do
			hits[entry] = (hits[entry] or 0) + 1
		end
	end
	for _, entry in ipairs(pool) do
		truthy((hits[entry] or 0) > 0, "Vorlage nie gezogen: " .. tostring(entry.Id))
	end
end)

-- ---------------------------------------------------------------------
-- 6) STERNE, KNOW-HOW, LOGIN, SAISON, KENNZAHLEN, BESTENLISTEN
-- ---------------------------------------------------------------------
check("Sterne-Formel floor(4 × log10(Ausgaben / 1e6)), 0 unter 1e7", function()
	eq(PM.Stars(0), 0, "0")
	eq(PM.Stars(9.99e6), 0, "knapp unter 1e7")
	eq(PM.Stars(1e7), 4, "1e7")
	eq(PM.Stars(1e8), 8, "1e8")
	eq(PM.Stars(1e9), 12, "1e9")
	eq(PM.Stars(3.2e7), 6, "3,2e7")
end)

check("Know-how-Summe (+1/Level ab 2, +3/Lizenz ab Azubi II, +1/Serie), Max 130", function()
	eq(PM.KnowHowTotal(1, 1, 0), 0, "Start")
	eq(PM.KnowHowTotal(10, 4, 2), 20, "Beispiel")
	eq(PM.KnowHowTotal(100, 10, 4), Progression.KnowHow.Max, "Maximum")
	local spendAll = 0
	for _, node in ipairs(Progression.KnowHow.Nodes) do
		spendAll += node.Max * node.Cost
	end
	truthy(spendAll <= Progression.KnowHow.Max, "alle Knoten voll kosten höchstens das KH-Maximum")
end)

check("Login-Zyklus (7 Tage)", function()
	local d1, c1 = PM.LoginDay(1)
	eq(d1, 1, "Tag 1")
	eq(c1, 1, "Zyklus 1")
	eq((PM.LoginDay(7)), 7, "Tag 7")
	local d8, c8 = PM.LoginDay(8)
	eq(d8, 1, "Tag 8 -> 1")
	eq(c8, 2, "Zyklus 2")
	eq((PM.LoginDay(0)), 1, "0 -> Tag 1")
end)

check("Saison-Stufe", function()
	eq(PM.SeasonTier(0, 1000, 50), 0, "0")
	eq(PM.SeasonTier(999, 1000, 50), 0, "999")
	eq(PM.SeasonTier(1000, 1000, 50), 1, "1000")
	eq(PM.SeasonTier(1e9, 1000, 50), 50, "Deckel")
end)

check("Drawdown und Ø-Tagesrendite", function()
	near(PM.MaxDrawdown({ 0.1, -0.2, 0.05 }), 0.2, 1e-12, "Drawdown")
	eq(PM.MaxDrawdown({ 0.01, 0.02 }), 0, "nur Gewinne")
	near(PM.AvgDaily({ 0.01, 0.01, 0.01 }), 0.01, 1e-12, "Ø konstant")
	near(PM.AvgDaily({ 0.1, -0.1 }), math.sqrt(0.99) - 1, 1e-12, "Ø geometrisch")
	eq(PM.AvgDaily({}), 0, "leer")
end)

check("Bestenlisten-Kodierung", function()
	eq(PM.BoardLeague(500, 25), 5005025, "Liga")
	eq(PM.BoardLeague(1200, 99999), 10009999, "Liga geklemmt")
	eq(PM.BoardLeague(0, -99999), 0, "Liga unten")
	eq(PM.BoardReturn(-30), 999970, "Rendite")
	eq(PM.BoardSkyline(2, 37), 237, "Skyline")
	eq(PM.BoardSkyline(0, 250), 99, "Etage geklemmt")
	local code = PM.BoardLog(123456789)
	truthy(code % 1 == 0 and code <= 9e15, "Log ganzzahlig")
	near(PM.BoardLogDecode(code) / 123456789, 1, 1e-6, "Log-Rundreise")
	truthy(PM.BoardLog(2e6) > PM.BoardLog(1e6), "Log monoton")
	eq(PM.BoardLog(9e40), PM.BoardLog(9e15), "Log geklemmt")
end)

check("Clamp", function()
	eq(PM.Clamp(1e20), 9e15, "oben")
	eq(PM.Clamp(-5), 0, "unten")
	eq(PM.Clamp(0 / 0), 0, "NaN")
	eq(PM.Clamp(12.9), 12, "abrunden")
end)

-- ---------------------------------------------------------------------
-- 7) CONFIG-PRÜFUNGEN (Validate leer, Firewall-Felder, Tutorial-XP)
-- ---------------------------------------------------------------------
check("Config.Progression/Season/Rewards.Validate ohne Meldungen", function()
	local config = { Progression = Progression, Season = Season, Rewards = Rewards }
	for _, list in ipairs({ Progression.Validate(config), Season.Validate(config), Rewards.Validate(config) }) do
		if #list > 0 then
			error(table.concat(list, "; "))
		end
	end
end)

check("Tutorial: Schritt-XP = 300 (Azubi II), Schritte 17", function()
	local sum = 0
	for _, xp in pairs(Progression.Tutorial.Xp) do
		sum += xp
	end
	eq(sum, Progression.XpSources.Tutorial.Xp, "Summe Tutorial-XP")
	eq(sum, Progression.Licences[2].Xp, "reicht genau für Azubi II")
	eq(Progression.Tutorial.Steps, 17, "Schritte")
end)

check("Skyline-Pass: nur Turm-Seite, gekaufte Stufen ohne Einkommen", function()
	for _, def in ipairs(Season.Seasons) do
		for _, track in ipairs({ def.Free, def.Premium }) do
			for _, reward in ipairs(track) do
				for field in pairs(reward) do
					truthy(Season.AllowedFields[field] == true, "Feld nicht erlaubt: " .. tostring(field))
				end
			end
		end
		eq(#def.Free, 25, "Gratis-Spur 25")
		eq(#def.Premium, 50, "Premium-Spur 50")
	end
	truthy(Season.EarnedOnlyFields.Credits and Season.EarnedOnlyFields.BoostX2, "Einkommens-Teile nur verdient")
end)

check("Codes geben nur CR oder Kosmetik", function()
	for code, entry in pairs(Rewards.Codes) do
		for field in pairs(entry.Grant) do
			truthy(field == "Credits" or field == "Cosmetics", "Code " .. code .. " gibt " .. field)
		end
	end
end)

-- ---------------------------------------------------------------------
-- 8) TEXT-ABDECKUNG: jeder dynamisch gebildete Schlüssel existiert auf DE und EN
-- ---------------------------------------------------------------------
local function merged(lang: string): { [string]: string }
	local out: { [string]: string } = {}
	for _, file in ipairs({ LangProgress, LangTutorial, LangSocial }) do
		for key, value in pairs((file :: any)[lang]) do
			out[key] = value
		end
	end
	return out
end
local DE, EN = merged("de"), merged("en")

local function need(key: string)
	truthy(DE[key] ~= nil, "DE fehlt: " .. key)
	truthy(EN[key] ~= nil, "EN fehlt: " .. key)
end

check("Lang: Lektionen (Titel, Karten, Fragen, Antworten)", function()
	eq(#Progression.Academy.Lessons, 16, "16 Lektionen")
	for _, lesson in ipairs(Progression.Academy.Lessons) do
		local base = "prog.les." .. lesson.Id
		need(base .. ".t")
		for c = 1, lesson.Cards do
			need(base .. ".c" .. c)
		end
		truthy(DE[base .. ".c" .. (lesson.Cards + 1)] == nil, "überzählige Karte in " .. lesson.Id)
		for q, options in ipairs(lesson.Quiz) do
			need(base .. ".q" .. q)
			for a = 1, options do
				need(base .. ".q" .. q .. ".a" .. a)
			end
		end
	end
end)

check("Lang: Know-how, Vorstand, Prüfungen, Serien, Kronen, Stufen", function()
	for _, node in ipairs(Progression.KnowHow.Nodes) do
		need("prog.kh." .. node.Key)
		need("prog.kh." .. node.Key .. ".d")
	end
	for _, perk in ipairs(Progression.Prestige.Perks) do
		need("prog.perk." .. perk.Key)
		need("prog.perk." .. perk.Key .. ".d")
	end
	for _, task in ipairs(Progression.ExamTasks) do
		need("prog.exam." .. task.Key)
		need("prog.exam." .. task.Key .. ".d")
	end
	for s = 1, Progression.Academy.Series do
		need("prog.series." .. s)
	end
	for _, key in ipairs({ "Silver", "Gold", "Platinum", "Holo", "Orbit" }) do
		need("prog.crown." .. key)
	end
	for _, key in ipairs({ "None", "Bronze", "Silber", "Gold", "Diamant" }) do
		need("prog.tier." .. key)
	end
end)

check("Lang: Quests, Starter-Linie, Erfolge", function()
	for _, kind in ipairs(Progression.QuestKinds) do
		need("prog.qk." .. kind.Key)
	end
	for _, list in ipairs({ Progression.Quests.Daily, Progression.Quests.Weekly }) do
		for _, q in ipairs(list) do
			if q.Text then
				need(q.Text)
			end
		end
	end
	for _, step in ipairs(Progression.Quests.StarterLine) do
		need("prog.st." .. step.Id)
		need("prog.st." .. step.Id .. ".tiko")
	end
	for _, cat in ipairs(Progression.AchievementCats) do
		need("prog.achCat." .. cat)
	end
	for _, ach in ipairs(Progression.Achievements) do
		need("prog.ach.stat." .. ach.Stat)
	end
end)

check("Lang: Sozial (Reaktionen, Emotes, Bestenlisten)", function()
	for _, reaction in ipairs(Progression.Social.Reactions) do
		need("soc.react." .. reaction.Key)
	end
	for _, name in ipairs(Progression.Social.Emotes) do
		need("soc.emote." .. name)
	end
	for _, board in ipairs(Progression.Boards.List) do
		need("soc.board." .. board.Key)
		need("soc.board.info." .. board.Key)
	end
	for _, scope in ipairs({ "Global", "Friends", "Server" }) do
		need("soc.scope." .. scope)
	end
end)

check("Lang: Platzhalter DE/EN gleich, kein einzelnes % in Format-Texten", function()
	for key, de in pairs(DE) do
		local en = EN[key]
		truthy(en ~= nil, "EN fehlt: " .. key)
		local function holes(s: string): string
			local clean = string.gsub(s, "%%%%", "")
			local list = {}
			for spec in string.gmatch(clean, "%%[%d%.]*[sdf]") do
				table.insert(list, (string.gsub(spec, "[%d%.]", "")))
			end
			return table.concat(list, ",")
		end
		eq(holes(en), holes(de), "Platzhalter " .. key)
		if holes(de) ~= "" then
			local stray = string.gsub(string.gsub(de, "%%%%", ""), "%%[%d%.]*[sdf]", "")
			truthy(not string.find(stray, "%", 1, true), "einzelnes % in " .. key)
		end
	end
end)

-- ---------------------------------------------------------------------
print(("progressmath.test: %d bestanden, %d fehlgeschlagen"):format(passed, failed))
for _, line in ipairs(failures) do
	print("  FEHLER " .. line)
end
if failed > 0 then
	error("progressmath.test fehlgeschlagen")
end
