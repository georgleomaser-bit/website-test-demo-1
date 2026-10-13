-- =====================================================================
--  AKYTEX TYCOON – Selbsttests Fortschritt, Quests, Börsengang, Know-how, Lizenzen (Server/Tests/ProgressionTests)
--  Besitzer: WP9 (Fortschritt, Tutorial, Sozial, Bestenlisten). Vertrag: DESIGN.md §D WP9 "Abnahme"/"Tests":
--  Quest-Tracker-Abdeckung (jede Quest-Art hat einen Aufrufer), Börsengang-Erhalt (§B9.6), Know-how-Grenzen,
--  Admin-Lizenz taintet die Liga-Woche, Lizenz-Aufstieg ruft OrderService.SetLicence, Ruf-Deckel/Abbau/Untergrenzen,
--  Quiz-Schlüssel, Quest-Auswahl, Login-Serie, Saison-Rechnung, Vorstand nur Turm/Lifestyle.
--  SelfTestService lädt dieses Modul und ruft jede Funktion mit Services auf; jeder Fehler = FAIL.
--  Arbeitet nur mit Test-Spielständen (Kopien von DataService.DefaultData) und Attrappen – echte Spieler bleiben unberührt.
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any
local Util = require(Shared:WaitForChild("Util")) :: any
local ProgressMath = require(Shared:WaitForChild("ProgressMath")) :: any

local PCFG: any = Config.Progression
local DAY = 86400

local Tests: { [string]: (any) -> () } = {}

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(("%s erwartet %s, bekommen %s"):format(label or "Wert", tostring(expected), tostring(actual)), 2)
	end
end

local function truthy(value: any, label: string)
	if not value then
		error(label, 2)
	end
end

-- rekursiver Vergleich -> (gleich, Pfad der Abweichung)
local function deepEqual(a: any, b: any, path: string, depth: number?): (boolean, string?)
	local level = depth or 0
	if level > 16 then
		return false, path .. " (zu tief)"
	end
	if type(a) ~= type(b) then
		return false, path
	end
	if type(a) ~= "table" then
		if a ~= b and not (a ~= a and b ~= b) then
			return false, path
		end
		return true, nil
	end
	for key, value in pairs(a) do
		local ok, where = deepEqual(value, b[key], path .. "." .. tostring(key), level + 1)
		if not ok then
			return false, where
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false, path .. "." .. tostring(key)
		end
	end
	return true, nil
end

local function serviceModule(services: any, name: string): any
	local svc = services and services[name]
	if svc then
		return svc
	end
	local module = script.Parent.Parent:WaitForChild("Services"):FindFirstChild(name)
	assert(module and module:IsA("ModuleScript"), name .. " fehlt")
	return require(module) :: any
end

local function serviceExists(services: any, name: string): boolean
	if services and services[name] then
		return true
	end
	local folder = script.Parent.Parent:FindFirstChild("Services")
	local module = folder and folder:FindFirstChild(name)
	return module ~= nil and module:IsA("ModuleScript")
end

local function core(services: any): any
	local test = serviceModule(services, "ProgressionService")._Test
	assert(type(test) == "table" and type(test.Core) == "table", "ProgressionService._Test.Core fehlt")
	return test.Core
end

local function rewardTest(services: any): any
	local test = serviceModule(services, "RewardService")._Test
	assert(type(test) == "table" and type(test.Core) == "table", "RewardService._Test fehlt")
	return test
end

-- frischer Test-Spielstand (Kopie von DEFAULT_DATA, Prog repariert)
local function newData(services: any): any
	local data = serviceModule(services, "DataService").DefaultData()
	core(services).Repair(data)
	return data
end

local function copy(value: any): any
	return Util.DeepCopy(value)
end

-- ---------------------------------------------------------------------
-- 1) CONFIG
-- ---------------------------------------------------------------------
Tests["Config: Progression/Season/Rewards prüfen ohne Meldung"] = function()
	for _, name in ipairs({ "Progression", "Season", "Rewards" }) do
		local module = Shared:WaitForChild("Config"):FindFirstChild(name)
		assert(module and module:IsA("ModuleScript"), "Config." .. name .. " fehlt")
		local child = require(module) :: any
		local list = child.Validate(Config)
		if #list > 0 then
			error(table.concat(list, "; "))
		end
	end
	eq(#PCFG.Licences, 10, "10 Lizenzen")
	eq(#PCFG.Academy.Lessons, 16, "16 Lektionen")
	eq(#PCFG.Achievements, 60, "60 Erfolge")
	eq(#PCFG.Badges, 15, "15 Badges")
	eq(#PCFG.Album.Cards, 43, "43 Album-Karten")
	eq(#PCFG.Quests.Daily, 30, "30 Tages-Vorlagen")
	eq(#PCFG.Quests.Weekly, 12, "12 Wochen-Vorlagen")
	eq(#PCFG.Quests.StarterLine, 20, "20 Starter-Schritte")
end

-- ---------------------------------------------------------------------
-- 2) QUEST-TRACKER-ABDECKUNG (Abnahme 5)
-- ---------------------------------------------------------------------
Tests["Quest-Arten: jede Art hat einen Tracker"] = function(services: any)
	local reward = rewardTest(services)
	local internal = reward.InternalKinds
	local missing: { string } = {}
	for _, kind in ipairs(PCFG.QuestKinds) do
		local tracker = kind.Tracker
		if type(tracker) ~= "string" or tracker == "" then
			table.insert(missing, kind.Key .. " (kein Tracker eingetragen)")
		elseif not serviceExists(services, tracker) then
			table.insert(missing, kind.Key .. " (" .. tracker .. " fehlt)")
		elseif tracker == "ProgressionService" or tracker == "CommunityService" then
			-- WP9 meldet selbst: die Art muss im internen Verzeichnis stehen
			if internal[kind.Key] ~= tracker then
				table.insert(missing, kind.Key .. " (" .. tracker .. " meldet sie nicht)")
			end
		end
	end
	if #missing > 0 then
		error("ohne Tracker: " .. table.concat(missing, ", "))
	end
	-- interne Arten sind echte Quest-Arten
	for key in pairs(internal) do
		truthy(PCFG.QuestKindByKey[key] ~= nil, "interne Art ohne Quest-Art: " .. key)
	end
end

Tests["Quest-Vorlagen: nur bekannte Arten/Prüfungen, Ziele > 0"] = function()
	local checks = { Floors = true, Eff = true, Licence = true, Lessons = true, RoomKinds = true, BotOn = true }
	checks.LeagueDays = true
	checks.Wealth = true
	for _, list in ipairs({ PCFG.Quests.Daily, PCFG.Quests.Weekly }) do
		for _, def in ipairs(list) do
			truthy(PCFG.QuestKindByKey[def.Kind] ~= nil, "unbekannte Art " .. tostring(def.Kind) .. " in " .. def.Id)
			truthy(type(def.Goal) == "number" and def.Goal > 0, "Ziel > 0 in " .. def.Id)
		end
	end
	for _, def in ipairs(PCFG.Quests.StarterLine) do
		if def.Check then
			truthy(checks[def.Check] == true, "unbekannte Prüfung " .. tostring(def.Check) .. " in " .. def.Id)
		else
			truthy(PCFG.QuestKindByKey[def.Kind] ~= nil, "unbekannte Art in " .. def.Id)
		end
		truthy(def.Credits > 0 and def.Credits % 1 == 0, "Starter-CR ganzzahlig in " .. def.Id)
	end
	truthy(PCFG.QuestKindByKey[PCFG.Quests.Comeback.Kind] ~= nil, "Aufhol-Quest-Art")
	eq(PCFG.Quests.StarterLine[#PCFG.Quests.StarterLine].Title, "Founder", "Schritt 20: Titel Gründer")
end

Tests["Quest-Auswahl: deterministisch, 3 verschiedene, mind. 1 Handels-/Akademie-Quest"] = function(services: any)
	local c = rewardTest(services).Core
	for userId = 1, 40 do
		for day = 20000, 20010 do
			local a = c.PickDaily(userId * 7919, day)
			local b = c.PickDaily(userId * 7919, day)
			eq(#a, PCFG.Quests.DailyCount, "Anzahl")
			eq(table.concat(a, ","), table.concat(b, ","), "deterministisch")
			local seen: { [string]: boolean } = {}
			local trade = 0
			for _, id in ipairs(a) do
				truthy(not seen[id], "doppelt " .. id)
				seen[id] = true
				if c.IsTradeKind(PCFG.QuestById[id].Kind) then
					trade += 1
				end
			end
			truthy(trade >= PCFG.Quests.MinTradeDaily, "Handels-Garantie verletzt")
			-- Neuwählen ersetzt durch eine neue Vorlage, Garantie bleibt
			local list = {}
			for _, id in ipairs(a) do
				table.insert(list, { Id = id })
			end
			local replaced = c.RerollPick(userId, day, list, a[1])
			truthy(replaced ~= nil and not seen[replaced], "Neuwahl liefert neue Vorlage")
		end
	end
	local weekly = c.PickWeekly(42, 2900)
	eq(#weekly, PCFG.Quests.WeeklyCount, "Wochenquests")
end

Tests["Quest-Fortschritt: Mindestwerte und verschiedene Werte (Distinct)"] = function(services: any)
	local c = rewardTest(services).Core
	local def = { Id = "T", Kind = "NewSector", Goal = 2, Distinct = "Sector" }
	local q = { Id = "T", P = 0, Done = false, Claimed = false, Seen = {} }
	eq((c.Advance(q, def, 1, { Sector = "T" })), true, "erster Sektor")
	eq((c.Advance(q, def, 1, { Sector = "T" })), false, "gleicher Sektor zählt nicht")
	local moved, finished = c.Advance(q, def, 1, { Sector = "E" })
	eq(moved and finished, true, "zweiter Sektor -> fertig")
	eq((c.Advance(q, def, 1, { Sector = "M" })), false, "fertig bleibt fertig")
	local minDef = { Id = "M", Kind = "TradeProfit", Goal = 1, Min = { Pct = 0.05 } }
	local q2 = { Id = "M", P = 0, Done = false, Claimed = false }
	eq((c.Advance(q2, minDef, 1, { Pct = 0.02 })), false, "unter Mindestwert")
	eq((c.Advance(q2, minDef, 1, nil)), false, "ohne Kontext")
	eq((c.Advance(q2, minDef, 1, { Pct = 0.06 })), true, "Mindestwert erreicht")
end

-- ---------------------------------------------------------------------
-- 3) BÖRSENGANG (Abnahme 3)
-- ---------------------------------------------------------------------
local function fakeTowerEnv(balance: number): (any, { [string]: any })
	local account = { Balance = balance, Storage = {} :: { [string]: number } }
	local env = {
		Now = os.time(),
		Licence = 4,
		Ipo = 0,
		Perk = function(_key: string): number
			return 0
		end,
		HasPass = function(_key: string): boolean
			return false
		end,
		Balance = function(): number
			return account.Balance
		end,
		Debit = function(amount: number, _sink: string): boolean
			if amount > account.Balance or amount % 1 ~= 0 then
				return false
			end
			account.Balance -= amount
			return true
		end,
		Credit = function(amount: number, _source: string): boolean
			account.Balance += amount
			return true
		end,
		TakeDecor = function(key: string): boolean
			local n = account.Storage[key] or 0
			if n <= 0 then
				return false
			end
			account.Storage[key] = n - 1
			return true
		end,
		ReturnDecor = function(key: string)
			account.Storage[key] = (account.Storage[key] or 0) + 1
		end,
		Comfort = function(_key: string): number
			return 0
		end,
		Owns = function(_entry: any): boolean
			return true
		end,
		BuildEvent = 1,
		CostEvent = function(_kind: string): number
			return 1
		end,
	}
	return env, account
end

Tests["Börsengang: behält alles laut §B9.6, Sterne-Formel, Vorstand-Blitzstart"] = function(services: any)
	local c = core(services)
	local tower = serviceModule(services, "TowerService")._Test
	assert(type(tower) == "table" and type(tower.Core) == "table", "TowerService._Test.Core fehlt")
	local data = newData(services)
	local prog = data.Prog
	-- Fortschritt, der bleiben muss
	prog.Xp = 30000
	prog.Licence = 7
	prog.Exams = { ProtectPair = true, Sectors3 = true }
	prog.Lessons = { L01 = 2, L02 = 1 }
	prog.KH = { Alerts = 2 }
	prog.Ruf = 200
	prog.Album = { ["1"] = true, ["2"] = true }
	prog.Ach = { T01 = true }
	prog.Titles = { Founder = true }
	prog.Title = "Founder"
	c.Repair(data)
	-- Depot: Standard-Depot aus DataService.DefaultData (Spielstand-Kopie; nur OrderService schreibt echte Depots)
	data.Garage = { Cars = { LamCity = true, VoltaHatch = true }, Active = "VoltaHatch", Tune = {} }
	data.Life = { Watches = { WeekChrono = true }, Accessories = {}, Equipped = {} }
	data.Season = { Id = 1, Xp = 4200, Premium = true, ClaimedFree = { ["2"] = true }, ClaimedPremium = {} }
	data.Login = { LastDay = 20000, Streak = 9, Best = 9, Freeze = 1, FreezeWeek = 0, Cycle = 2, Track = 9 }
	-- Lauf: 30 Etagen, Effizienz, Tresor, Lauf-Ausgaben 1e8
	local t = data.Tower
	table.clear(t.Floors)
	for i = 1, 30 do
		t.Floors[i] = tower.Core.NewFloor()
	end
	t.Eff = 5
	t.Vault = 5000
	t.RunSpend = 1e8
	local keep = {
		ProgNoPrestige = (function()
			local p = copy(prog)
			p.Prestige = nil
			return p
		end)(),
		Depot = copy(data.Depot),
		Garage = copy(data.Garage),
		Life = copy(data.Life),
		Season = copy(data.Season),
		Login = copy(data.Login),
		Purchases = copy(data.Purchases),
	}
	-- 1) Börsengang buchen (WP9)
	local stars = c.ApplyIpo(prog, t.RunSpend, "TEST", 1000)
	eq(stars, ProgressMath.Stars(1e8), "Sterne = floor(4 × log10(1e8 / 1e6))")
	eq(stars, 8, "8 ★ bei 1e8")
	eq(prog.Prestige.Count, 1, "Börsengänge")
	eq(prog.Prestige.Firmenwert, 0.5e8, "Firmenwert += 0,5 × Lauf-Ausgaben")
	eq(prog.Prestige.Tickers[1].T, "TEST", "Ticker gemerkt")
	eq(c.CrownFor(prog.Prestige.Count), "Silver", "Krone nach 1 Börsengang")
	-- Vorstand: Blitzstart 1 kaufen (nur Turm)
	local okPerk = c.BuyPerk(prog, "Blitzstart")
	eq(okPerk, true, "Perk gekauft")
	eq(c.StarsFree(prog), stars - 1, "1 ★ ausgegeben")
	local perks = c.PerkTable(prog)
	eq(perks.Blitzstart, 1, "Perk-Tabelle")
	eq(perks.StartCredits, PCFG.Prestige.StartCredits, "Start-CR")
	-- 2) Turm-Neustart (WP6)
	local env, account = fakeTowerEnv(777777)
	eq(tower.Core.ResetForIpo(data, env, perks), true, "ResetForIpo")
	eq(account.Balance, PCFG.Prestige.StartCredits, "CR startet neu")
	eq(#t.Floors, Config.Tower.Ipo.Blitz[1], "Blitzstart 1 = 4 fertige Etagen")
	eq(t.Eff, 0, "Effizienz neu")
	eq(t.Vault, 0, "Tresor neu")
	eq(t.RunSpend, 0, "Lauf-Ausgaben neu")
	-- 3) alles andere bleibt
	local progNow = copy(prog)
	progNow.Prestige = nil
	for name, before in pairs(keep) do
		local now = if name == "ProgNoPrestige" then progNow else data[name]
		local same, where = deepEqual(before, now, name)
		truthy(same, name .. " muss bleiben (" .. tostring(where) .. ")")
	end
	eq(prog.Licence, 7, "Lizenz bleibt")
	eq(prog.Xp, 30000, "Trader-XP bleiben")
end

Tests["Börsengang: Sterne-Grenzen, Gratis-Umverteilen ab dem 3., Ticker-Liste begrenzt"] = function(services: any)
	local c = core(services)
	local prog = newData(services).Prog
	eq(c.ApplyIpo(prog, 9.99e6, "AAA", 1), 0, "unter 1e7: 0 ★")
	eq(c.ApplyIpo(prog, 1e7, "BBB", 2), 4, "1e7: 4 ★")
	eq(prog.Prestige.RespecFree, false, "noch kein Gratis-Umverteilen")
	c.ApplyIpo(prog, 1e9, "CCC", 3)
	eq(prog.Prestige.Count, 3, "3 Börsengänge")
	eq(prog.Prestige.RespecFree, true, "ab dem 3. Börsengang einmal gratis")
	eq(prog.Prestige.Stars, 16, "4 + 12 ★")
	for i = 1, PCFG.Prestige.TickerKeep + 10 do
		c.ApplyIpo(prog, 0, "T" .. i, i)
	end
	eq(#prog.Prestige.Tickers, PCFG.Prestige.TickerKeep, "Ticker-Liste begrenzt")
end

Tests["Vorstand wirkt nur auf Turm/Lifestyle, nie auf Trading-Werkzeuge"] = function(services: any)
	local c = core(services)
	local towerKeys: { [string]: boolean } = {}
	for _, value in pairs(Config.Tower.Perks) do
		towerKeys[value] = true
	end
	for _, def in ipairs(PCFG.Prestige.Perks) do
		truthy(towerKeys[def.Key] or def.Key == "Lifestyle", "Vorstand-Ast ohne Turm/Lifestyle-Wirkung: " .. def.Key)
	end
	local data = newData(services)
	local prog = data.Prog
	prog.Licence = 5
	prog.Xp = 20000
	prog.KH = { Alerts = 3, Risk = 1 }
	c.Repair(data)
	local toolsBefore = copy(c.TradingPerks(prog))
	local khBefore = c.KhTotal(prog)
	local xpBefore = prog.Xp
	prog.Prestige.Stars = 100
	for _, def in ipairs(PCFG.Prestige.Perks) do
		for _ = 1, def.Max do
			c.BuyPerk(prog, def.Key)
		end
	end
	eq(c.StarsSpent(prog), 39, "alle Äste voll = 39 ★")
	local same, where = deepEqual(toolsBefore, c.TradingPerks(prog), "TradingPerks")
	truthy(same, "Trading-Werkzeuge unverändert (" .. tostring(where) .. ")")
	eq(c.KhTotal(prog), khBefore, "Know-how unverändert")
	eq(prog.Xp, xpBefore, "XP unverändert")
	-- Umverteilen kostet 1 ★ (außer gratis)
	local stars = prog.Prestige.Stars
	eq((c.Respec(prog)), true, "Umverteilen")
	eq(prog.Prestige.Stars, stars - PCFG.Prestige.RespecCost, "kostet 1 ★")
	eq(next(prog.Prestige.Perks), nil, "Äste leer")
	eq(select(2, c.Respec(prog)), "prog.respecEmpty", "nichts zum Umverteilen")
end

-- ---------------------------------------------------------------------
-- 4) KNOW-HOW-GRENZEN
-- ---------------------------------------------------------------------
Tests["Know-how: Punkte, Lizenz-Sperren, Höchststufe, Umverteilen 1× je Woche, Deckel 130"] = function(services: any)
	local c = core(services)
	local data = newData(services)
	local prog = data.Prog
	eq(c.KhTotal(prog), 0, "Start ohne KH")
	eq(select(2, c.BuyNode(prog, "Alerts")), "prog.khNoPoints", "ohne Punkte")
	eq(select(2, c.BuyNode(prog, "Unbekannt")), "core.invalid", "unbekannter Knoten")
	prog.Xp = ProgressMath.XpForLevel(11) -- Level 11 -> 10 KH
	eq(c.KhTotal(prog), 10, "10 KH aus Level")
	local ok, key, args = c.BuyNode(prog, "Risk")
	eq(ok, false, "Risiko-Büro gesperrt")
	eq(key, "prog.khLocked", "Sperr-Text")
	eq(args and args[1], 3, "ab Azubi III")
	prog.Licence = 3
	eq(c.KhTotal(prog), 16, "+3 je Lizenz ab Azubi II")
	eq((c.BuyNode(prog, "Risk")), true, "Risiko 1")
	eq((c.BuyNode(prog, "Risk")), true, "Risiko 2")
	eq(select(2, c.BuyNode(prog, "Risk")), "prog.khMax", "Höchststufe")
	eq(c.KhFree(prog), 12, "16 − 2 × 2")
	prog.Licence = 5
	eq((c.BuyNode(prog, "Research")), true, "Research 1 ab Trader II")
	local ok2, key2, args2 = c.BuyNode(prog, "Research")
	eq(ok2, false, "Research 2 gesperrt")
	eq(key2, "prog.khLocked", "Stufen-Lizenz")
	eq(args2 and args2[1], 7, "Research 2 ab Fondsmanager I")
	-- alles ausgeben -> keine Punkte mehr
	local guard = 0
	while c.KhFree(prog) > 0 and guard < 50 do
		guard += 1
		if not c.BuyNode(prog, "Alerts") and not c.BuyNode(prog, "Watch") and not c.BuyNode(prog, "Monitors") then
			break
		end
	end
	truthy(c.KhSpent(prog) <= c.KhTotal(prog), "nie mehr ausgegeben als vorhanden")
	-- Umverteilen
	local week = 2900
	eq((c.ResetNodes(prog, week)), true, "Umverteilen")
	eq(next(prog.KH), nil, "leer")
	eq(c.KhSpent(prog), 0, "nichts ausgegeben")
	c.BuyNode(prog, "Alerts")
	eq(select(2, c.ResetNodes(prog, week)), "prog.khResetUsed", "nur 1× je Woche")
	prog.KH = {}
	eq(select(2, c.ResetNodes(prog, week + 1)), "prog.khResetEmpty", "nichts verteilt")
	-- Deckel
	prog.Xp = 1e12
	prog.Licence = #PCFG.Licences
	for _, lesson in ipairs(PCFG.Academy.Lessons) do
		prog.Lessons[lesson.Id] = 2
	end
	eq(c.Series(prog), 4, "4 Serien")
	eq(c.KhTotal(prog), PCFG.KnowHow.Max, "Deckel 130")
	-- Werkzeuge kommen nur aus Lizenz + KH
	prog.KH = { Alerts = 5, Watch = 4 }
	local tools = c.TradingPerks(prog)
	eq(tools.Alerts, 18, "3 + 5 × 3 Alarme")
	eq(tools.Watchlists, 5, "1 + 4 Watchlists")
end

-- ---------------------------------------------------------------------
-- 5) LIZENZEN: Aufstieg ruft SetLicence (Abnahme 2), Admin-Lizenz taintet (Test-Vorgabe)
-- ---------------------------------------------------------------------
Tests["Lizenz-Aufstieg: SetLicence je Stufe, +250 XP, +20 Ruf, Basis steigt"] = function(services: any)
	local c = core(services)
	local prog = newData(services).Prog
	local calls: { number } = {}
	local function record(idx: number)
		table.insert(calls, idx)
	end
	eq(#c.Promote(prog, 20000, 2900, record), 0, "ohne XP kein Aufstieg")
	prog.Xp = 300
	eq(#c.Promote(prog, 20000, 2900, record), 0, "Prüfung fehlt")
	prog.Exams.ProtectPair = true
	local promoted = c.Promote(prog, 20000, 2900, record)
	eq(#promoted, 1, "eine Stufe")
	eq(promoted[1], 2, "Azubi II")
	eq(calls[1], 2, "OrderService.SetLicence(2)")
	eq(prog.Licence, 2, "Lizenz gesetzt")
	eq(prog.Xp, 300 + PCFG.XpSources.Exam.Xp, "+250 XP Prüfung")
	eq(prog.Ruf, PCFG.Ruf.Exam, "+20 Ruf (außerhalb des Deckels)")
	truthy(PCFG.Licences[2].Basis > PCFG.Licences[1].Basis, "Basis steigt")
	-- Kette bis zur Legende: jede Stufe einzeln gemeldet
	table.clear(calls)
	prog.Xp = 1e7
	for _, task in ipairs(PCFG.ExamTasks) do
		prog.Exams[task.Key] = true
	end
	local exams = 0
	for idx = 3, #PCFG.Licences do
		if #PCFG.Licences[idx].Exam > 0 then
			exams += 1
		end
	end
	local chain = c.Promote(prog, 20000, 2900, record)
	eq(#chain, #PCFG.Licences - 2, "Stufen 3 … 10")
	for i, idx in ipairs(chain) do
		eq(idx, i + 2, "Reihenfolge")
		eq(calls[i], idx, "SetLicence je Stufe")
	end
	eq(prog.Licence, #PCFG.Licences, "Legende")
	-- Prüfungs-Bonus nur für Lizenzen mit Prüfung (Trader II / Fondsmanager II steigen nur über XP)
	eq(prog.Xp, 1e7 + exams * PCFG.XpSources.Exam.Xp, "+250 XP je bestandener Prüfung")
end

Tests["Admin-Lizenz: SetLicence + TaintWeek(AdminLicence), ungültige Stufen abgelehnt"] = function(services: any)
	local c = core(services)
	local prog = newData(services).Prog
	local calls: { { any } } = {}
	local function report(fnName: string, arg: any)
		table.insert(calls, { fnName, arg })
	end
	eq(c.AdminLicence(prog, 7, report), true, "Admin setzt Fondsmanager I")
	eq(prog.Licence, 7, "Lizenz")
	eq(prog.AchProgress.Licence, 7, "Erfolgs-Zähler")
	local tainted, licenced = false, false
	for _, entry in ipairs(calls) do
		if entry[1] == "TaintWeek" and entry[2] == "AdminLicence" then
			tainted = true
		elseif entry[1] == "SetLicence" and entry[2] == 7 then
			licenced = true
		end
	end
	truthy(licenced, "OrderService.SetLicence(7) fehlt")
	truthy(tainted, "OrderService.TaintWeek(AdminLicence) fehlt – Admin-Gaben müssen die Liga-Woche tainten")
	table.clear(calls)
	for _, bad in ipairs({ 0, 11, 2.5, -1 } :: { any }) do
		eq(c.AdminLicence(prog, bad, report), false, "ungültig: " .. tostring(bad))
	end
	eq(#calls, 0, "keine Meldung bei ungültiger Stufe")
	eq(prog.Licence, 7, "unverändert")
end

-- ---------------------------------------------------------------------
-- 6) RUF (Abnahme 4)
-- ---------------------------------------------------------------------
Tests["Ruf: Deckel 20/Tag, Abbau ohne zählenden Börsentag, Lizenz-Untergrenzen"] = function(services: any)
	local c = core(services)
	local data = newData(services)
	local prog = data.Prog
	local day = 20000
	eq(c.AddRuf(prog, 15, day, true), 15, "15 Punkte")
	eq(c.AddRuf(prog, 15, day, true), 5, "Deckel 20 je Tag")
	eq(c.AddRuf(prog, 15, day, true), 0, "Deckel erreicht")
	eq(c.AddRuf(prog, PCFG.Ruf.Exam, day, false), PCFG.Ruf.Exam, "Prüfung außerhalb des Deckels")
	eq(c.AddRuf(prog, 15, day + 1, true), 15, "neuer Tag")
	eq(prog.Ruf, 15 + 5 + PCFG.Ruf.Exam + 15, "Summe")
	-- Abbau: letzter Tag hatte einen zählenden Börsentag, danach 2 Tage ohne
	prog.Ruf = 100
	prog.RufDay = day + 1
	data.LastUtcDay = day + 1
	eq(c.DayRoll(data, day + 4), 2, "2 Tage ohne Börsentag")
	eq(prog.Ruf, math.floor(100 * (1 - PCFG.Ruf.DecayPct) ^ 2), "−8 % je Tag")
	eq(c.DayRoll(data, day + 4), 0, "gleicher Tag: nichts")
	-- Untergrenze Fondsmanager I (Stufe 4 = 100 Punkte)
	prog.Licence = 7
	prog.Ruf = 160
	prog.RufDay = 0
	data.LastUtcDay = day
	c.DayRoll(data, day + 40)
	eq(prog.Ruf, PCFG.Ruf.Thresholds[4], "nie unter die Lizenz-Untergrenze")
	eq(c.RufLevel(prog), 4, "Stufe 4")
	prog.Ruf = 0
	eq(c.RufLevel(prog), 4, "Stufe nie unter der Untergrenze")
end

-- ---------------------------------------------------------------------
-- 7) AKADEMIE: Quiz-Schlüssel nur auf dem Server, Form-Prüfung
-- ---------------------------------------------------------------------
Tests["Akademie: Quiz-Schlüssel vollständig, Antworten streng geprüft"] = function(services: any)
	local test = serviceModule(services, "ProgressionService")._Test
	local c = test.Core
	local key = test.QuizKey
	for _, lesson in ipairs(PCFG.Academy.Lessons) do
		local solution = key[lesson.Id]
		truthy(type(solution) == "table", "Schlüssel fehlt für " .. lesson.Id)
		eq(#solution, #lesson.Quiz, "Fragen in " .. lesson.Id)
		for q, answer in ipairs(solution) do
			truthy(answer >= 1 and answer <= lesson.Quiz[q], "Antwort außerhalb in " .. lesson.Id .. " Frage " .. q)
		end
		local correct, total = c.LessonResult(lesson.Id, table.clone(solution), key)
		eq(correct, total, "alles richtig in " .. lesson.Id)
	end
	eq((c.LessonResult("L01", { 1 }, key)), nil, "zu wenige Antworten")
	eq((c.LessonResult("L01", { 1, 9 }, key)), nil, "Antwort außerhalb")
	eq((c.LessonResult("L01", { 1, 1.5 }, key)), nil, "keine ganze Zahl")
	local extra: any = { 1, 3 }
	extra.X = 1
	eq((c.LessonResult("L01", extra, key)), nil, "Fremd-Schlüssel")
	eq((c.LessonResult("L99", { 1, 1 }, key)), nil, "unbekannte Lektion")
	local wrong = c.LessonResult("L01", { 2, 1 }, key)
	eq(wrong, 0, "alles falsch")
end

-- ---------------------------------------------------------------------
-- 8) LOGIN, SAISON, XP-DECKEL, ALBUM
-- ---------------------------------------------------------------------
Tests["Login: Serie, Serien-Schutz, neue Serie, 28er-Spur, einmal je Tag"] = function(services: any)
	local c = rewardTest(services).Core
	-- Woche 10 hat ihren Gratis-Schutz schon bekommen (1 vorhanden)
	local login = { LastDay = 0, Streak = 0, Best = 0, Freeze = 1, FreezeWeek = 10, Cycle = 1, Track = 0 }
	local function claim(day: number, week: number)
		local nextState = c.LoginStep(login, day, week, false)
		assert(nextState, "Tag " .. day .. " abholbar")
		nextState.DayIdx = nil
		nextState.UsedFreeze = nil
		login = nextState
	end
	claim(100, 10)
	eq(login.Streak, 1, "Tag 1")
	eq(c.LoginStep(login, 100, 10, false), nil, "heute schon abgeholt")
	claim(101, 10)
	eq(login.Streak, 2, "Serie läuft")
	claim(103, 10) -- 1 Tag Lücke, 1 Schutz vorhanden
	eq(login.Streak, 3, "Schutz überbrückt die Lücke")
	eq(login.Freeze, 0, "Schutz verbraucht")
	claim(106, 10) -- 2 Tage Lücke, kein Schutz
	eq(login.Streak, 1, "neue Serie")
	eq(login.Best, 3, "Rekord bleibt")
	eq(login.Track, 4, "28er-Spur zählt abgeholte Tage")
	claim(107, 11)
	eq(login.Freeze, 1, "neue Woche: 1 Schutz")
	local club = c.LoginStep(login, 108, 12, true)
	assert(club, "abholbar")
	eq(club.Freeze, math.min(Config.Rewards.Login.FreezeMax, 1 + 1 + 1), "Club +1, höchstens 2")
end

Tests["Saison: aktive Saison, ehrliches Ende, Rolling danach"] = function(services: any)
	local c = rewardTest(services).Core
	local def = Config.Season.Seasons[1]
	local start = DateTime.fromIsoDate(def.StartUtc).UnixTimestamp
	local stop = DateTime.fromIsoDate(def.EndUtc).UnixTimestamp
	local inside = c.SeasonAt(start + DAY)
	assert(inside, "Saison 1 aktiv")
	eq(inside.Id, def.Id, "Saison 1")
	eq(inside.EndsAt, stop, "festes Ende")
	eq(inside.Rolling, false, "fest")
	local after = c.SeasonAt(stop + DAY)
	assert(after, "Rolling nach dem Ende")
	eq(after.Rolling, true, "Rolling")
	eq(after.Id, def.Id + 1, "Folge-Saison")
	eq(after.StartsAt, stop, "beginnt am Ende der letzten")
	eq(after.EndsAt - after.StartsAt, Config.Season.Rolling.LengthDays * DAY, "Länge")
	eq(ProgressMath.SeasonTier(def.Tiers * def.TierXp + 5, def.TierXp, def.Tiers), def.Tiers, "Stufen-Deckel")
end

Tests["XP: Tagesdeckel je Quelle, Prüfung ohne Verdoppler, nie Robux-Quellen"] = function(services: any)
	local c = core(services)
	local prog = newData(services).Prog
	local source = PCFG.XpSources.ReadWell
	local gained = 0
	for _ = 1, source.Cap + 5 do
		gained += c.AddXp(prog, source.Xp, "ReadWell", 1, 20000, 2900)
	end
	eq(gained, source.Xp * source.Cap, "Deckel " .. source.Cap .. "× je Tag")
	eq(c.AddXp(prog, source.Xp, "ReadWell", 1, 20001, 2900), source.Xp, "neuer Tag")
	eq(c.AddXp(prog, 100, "Unbekannt", 1, 20001, 2900), 0, "unbekannte Quelle")
	eq(c.AddXp(prog, 100, "LessonFirst", 5, 20001, 2900), 100 * PCFG.XpMultMax, "Verdoppler höchstens ×2")
	for reason in pairs(PCFG.XpSources) do
		local lower = string.lower(reason)
		truthy(
			not string.find(lower, "robux", 1, true) and not string.find(lower, "purchase", 1, true),
			"XP-Quelle aus Käufen: " .. reason
		)
	end
end

Tests["Album: Karten, Sektor-Sätze, IPO-Seite"] = function(services: any)
	local c = core(services)
	local prog = newData(services).Prog
	local companies = Config.Companies
	local firstSector = companies.Sectors[1].Key
	local lastSector: string? = nil
	for _, inst in ipairs(companies.Instruments) do
		if inst.Sector == firstSector and inst.Class ~= "ETF" and inst.Set ~= "Tutorial" and inst.Ipo ~= true then
			local added, sector = c.AlbumAdd(prog, inst.Id)
			eq(added, true, "Karte " .. inst.Id)
			lastSector = sector or lastSector
		end
	end
	eq(c.AlbumSets(prog), 1, "1 Sektor-Satz")
	eq(lastSector, firstSector, "Satz gemeldet")
	eq((c.AlbumAdd(prog, companies.Instruments[1].Id)), false, "doppelte Karte")
	eq((c.AlbumAdd(prog, 250)), false, "Übungsaktie ist keine Karte")
	eq((c.AlbumAdd(prog, PCFG.Album.IpoFrom)), true, "IPO-Seite")
end

return Tests
