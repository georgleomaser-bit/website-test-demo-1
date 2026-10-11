-- =====================================================================
--  CLUTCH CLASH – Selbsttests Match & Warteschlangen (Server/Tests/MatchTests)
--  Besitzer: WP5 (Match & Warteschlangen). Vertrag: DESIGN.md D (WP5 Tests), C18 (SelfTestService).
--  Gibt { [testName]: () -> () } zurück; ein Fehler = FAIL. Reine Regel-Logik mit Fake-Matches:
--  Tiebreak-Tabelle (B6.3), Overtime-Fortschritt (B6.2), Rundenlimit + Sudden Death (B6.4),
--  komplette Runden-Simulation, FFA-Punkte, Matcher-Paarung mit Fake-Einträgen (B3.1), Config + Lang.
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Lang = require(Shared:WaitForChild("Lang"))
local Server = script.Parent.Parent
local Rounds = require(Server:WaitForChild("Modes"):WaitForChild("Rounds"))
local Respawn = require(Server:WaitForChild("Modes"):WaitForChild("Respawn"))
local QueueService = require(Server:WaitForChild("Services"):WaitForChild("QueueService"))

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

local function truthy(value: any, label: string)
	if not value then
		error(label .. " erwartet wahr", 2)
	end
end

-- ---------------------------------------------------------------------
-- Fake-Match für die Regelwerke (m.Api wie in MatchService)
-- ---------------------------------------------------------------------
type FakeCombatant = { Id: number, Team: number, Alive: boolean, Hp: number, MaxHp: number, LastDamageAt: number }

local function fakeMatch(teamSize: number, roundsToWin: number)
	local clock = 0
	local combatants: { FakeCombatant } = {}
	local id = 0
	for team = 1, 2 do
		for _ = 1, teamSize do
			id += 1
			table.insert(combatants, { Id = id, Team = team, Alive = true, Hp = 100, MaxHp = 100, LastDamageAt = 0 })
		end
	end
	local presence: { [number]: number } = {}
	local ready = false
	local ended: any = nil
	local m: any = {
		TeamSize = teamSize,
		RoundsToWin = roundsToWin,
		RoundCap = Rounds.RoundCap(roundsToWin),
		RoundTime = 60,
		OvertimeTime = 15,
		Cfg = Config.Modes.Match,
		AntiCamp = { Duel = 30, Team = 40, Pulse = 10, Show = 1 },
		Score = { 0, 0 },
		Tainted = false,
	}
	m.Api = {
		Now = function()
			return clock
		end,
		Send = function(_kind: string, _data: any) end,
		BeginRound = function(_sd: boolean)
			for _, c in ipairs(combatants) do
				c.Alive = true
				c.Hp = 100
			end
		end,
		GoLive = function() end,
		StartOvertime = function(_endsAt: number) end,
		AliveByTeam = function()
			local byTeam = {}
			for _, c in ipairs(combatants) do
				if c.Alive then
					byTeam[c.Team] = byTeam[c.Team] or {}
					table.insert(byTeam[c.Team], c)
				end
			end
			return byTeam
		end,
		TeamHp = function(team: number)
			local sum = 0
			for _, c in ipairs(combatants) do
				if c.Alive and c.Team == team then
					sum += c.Hp
				end
			end
			return sum
		end,
		TeamDamage = function(_team: number)
			return 0
		end,
		ZonePresence = function()
			return presence
		end,
		AllReady = function()
			return ready
		end,
		RoundEnded = function(info: any)
			ended = info
		end,
		ZoneUpdate = function() end,
		AntiCamp = function() end,
	}
	local fake = {}
	function fake.Advance(seconds: number, step: number?)
		local dt = step or 0.2
		local t = 0
		while t < seconds - 1e-9 do
			clock += dt
			t += dt
			Rounds.Tick(m, dt)
		end
	end
	-- so lange ticken, bis die Bedingung gilt (höchstens maxSeconds)
	function fake.Until(cond: () -> boolean, maxSeconds: number): boolean
		local t = 0
		while t < maxSeconds do
			if cond() then
				return true
			end
			clock += 0.2
			t += 0.2
			Rounds.Tick(m, 0.2)
		end
		return cond()
	end
	function fake.Kill(victimId: number, killerId: number?)
		local victim, killer
		for _, c in ipairs(combatants) do
			if c.Id == victimId then
				victim = c
			elseif c.Id == killerId then
				killer = c
			end
		end
		victim.Alive = false
		Rounds.OnElim(m, victim, killer, { WeaponKey = "PopRifle", Assists = {} })
	end
	function fake.SetPresence(p: { [number]: number })
		presence = p
	end
	function fake.SetReady(on: boolean)
		ready = on
	end
	function fake.LastEnd(): any
		return ended
	end
	function fake.Combatants(): { FakeCombatant }
		return combatants
	end
	return m, fake
end

local Tests = {}

-- ---------------------------------------------------------------------
-- B6.3 Tiebreak-Tabelle
-- ---------------------------------------------------------------------
Tests["Rounds.Tiebreak Tabelle (B6.3)"] = function()
	local cases = {
		{ { 1, 2, 150, 10 }, { 2, 1, 100, 300 }, 1, "Alive" },
		{ { 1, 1, 40, 300 }, { 2, 1, 70, 10 }, 2, "Hp" },
		{ { 1, 2, 120, 80 }, { 2, 2, 120, 95 }, 2, "Damage" },
		{ { 1, 1, 50, 60 }, { 2, 1, 50, 60 }, 0, "Draw" },
		{ { 1, 0, 0, 0 }, { 2, 0, 0, 0 }, 0, "Draw" },
	}
	for i, case in ipairs(cases) do
		local a, b = case[1], case[2]
		local winner, reason = Rounds.Tiebreak({
			{ Team = a[1], Alive = a[2], Hp = a[3], Damage = a[4] },
			{ Team = b[1], Alive = b[2], Hp = b[3], Damage = b[4] },
		})
		eq(winner, case[3], "Fall " .. i .. " Sieger")
		eq(reason, case[4], "Fall " .. i .. " Grund")
	end
end

-- ---------------------------------------------------------------------
-- B6.2 Overtime-Zone
-- ---------------------------------------------------------------------
Tests["Rounds.ZoneStep halten/umkämpft/leer/zurückdrängen (B6.2)"] = function()
	local cfg = { ZoneCapture = 3, ZoneDecay = 0.5 }
	local state = { Team = 0, Value = 0 }
	eq(Rounds.ZoneStep(state, 1, false, 1, cfg), nil, "nach 1 s")
	eq(state.Team, 1, "Besitzer")
	near(state.Value, 1, 1e-6, "Fortschritt 1 s")
	eq(Rounds.ZoneStep(state, 0, true, 5, cfg), nil, "umkämpft")
	near(state.Value, 1, 1e-6, "umkämpft eingefroren")
	Rounds.ZoneStep(state, 0, false, 1, cfg)
	near(state.Value, 0.5, 1e-6, "leer −0.5/s")
	Rounds.ZoneStep(state, 2, false, 0.25, cfg)
	near(state.Value, 0.25, 1e-6, "Gegner drückt zurück")
	eq(state.Team, 1, "Besitzer bleibt beim Zurückdrängen")
	Rounds.ZoneStep(state, 2, false, 0.5, cfg)
	eq(state.Team, 2, "Besitzer wechselt bei 0")
	local captured = nil
	for _ = 1, 20 do
		captured = Rounds.ZoneStep(state, 2, false, 0.2, cfg)
		if captured then
			break
		end
	end
	eq(captured, 2, "nach 3 s gehalten = Rundensieg")
	local holder, contested = Rounds.ZoneHolder({ [1] = 1, [2] = 2 })
	eq(holder, 0, "beide Teams in der Zone")
	eq(contested, true, "umkämpft erkannt")
	holder, contested = Rounds.ZoneHolder({ [2] = 1 })
	eq(holder, 2, "nur Team 2")
	eq(contested, false, "nicht umkämpft")
end

-- ---------------------------------------------------------------------
-- B6.4 Rundenlimit + Sudden Death
-- ---------------------------------------------------------------------
Tests["Rounds.Outcome Rundenlimit + Sudden Death (B6.4)"] = function()
	local kind, winner = Rounds.Outcome({ 4, 2 }, 4, 6, 9, false, 1)
	eq(kind, "Win", "Erster auf 4")
	eq(winner, 1, "Sieger Team 1")
	kind = Rounds.Outcome({ 3, 3 }, 4, 6, 9, false, 2)
	eq(kind, "Continue", "unter dem Limit")
	kind, winner = Rounds.Outcome({ 3, 2 }, 4, 9, 9, false, 0)
	eq(kind, "Win", "Limit: mehr Rundensiege gewinnt")
	eq(winner, 1, "Limit-Sieger")
	kind = Rounds.Outcome({ 3, 3 }, 4, 9, 9, false, 0)
	eq(kind, "SuddenDeath", "Limit bei Gleichstand")
	kind, winner = Rounds.Outcome({ 4, 3 }, 4, 10, 9, true, 1)
	eq(kind, "Win", "Sudden Death gewonnen")
	eq(winner, 1, "SD-Sieger")
	kind, winner = Rounds.Outcome({ 3, 3 }, 4, 10, 9, true, 0)
	eq(kind, "Draw", "Sudden Death ohne Sieger = Match-Unentschieden")
	eq(winner, 0, "kein Sieger")
	eq(Rounds.RoundCap(4), 9, "RoundCap 2×4+1")
	eq(Rounds.RoundCap(2), 5, "RoundCap Krone")
	eq(#Rounds.MatchPointTeams({ 3, 1 }, 4), 1, "MATCH POINT")
end

Tests["Rounds Simulation: Elim, Overtime, Tiebreak, Match-Ende"] = function()
	local m, fake = fakeMatch(1, 2)
	Rounds.Start(m)
	eq(m.Phase, "Prep", "Start = Prep")
	fake.Advance(4.2)
	eq(m.Phase, "Live", "nach FirstPrep = Live")
	-- Runde 1: Team 1 poppt Team 2
	fake.Kill(2, 1)
	eq(m.Phase, "RoundEnd", "Elim beendet die Runde")
	eq(fake.LastEnd().Winner, 1, "Rundensieger")
	eq(fake.LastEnd().Reason, "Elim", "Grund Elim")
	eq(m.Score[1], 1, "Punktestand")
	truthy(table.find(fake.LastEnd().Banners, "MatchPoint"), "MATCH POINT-Banner")
	truthy(table.find(fake.LastEnd().Banners, "Flawless"), "FLAWLESS ohne Schaden")
	-- Runde 2: Zeit läuft ab -> Overtime -> Zone von Team 2 -> Sieg Team 2
	fake.Advance(2.6)
	eq(m.Phase, "Prep", "nächste Runde")
	eq(m.Round, 2, "Runde 2")
	fake.SetReady(true)
	fake.Advance(1.2)
	eq(m.Phase, "Live", "alle bereit -> Prep endet nach ≥ 1 s")
	fake.Advance(60.2)
	eq(m.Phase, "Overtime", "Zeit vorbei, beide leben -> Overtime")
	fake.SetPresence({ [2] = 1 })
	fake.Advance(3.4)
	eq(fake.LastEnd().Winner, 2, "Zone eingenommen")
	eq(fake.LastEnd().Reason, "Zone", "Grund Zone")
	-- Runde 3: Overtime ohne Einnahme -> Tiebreak über HP
	fake.SetPresence({})
	truthy(
		fake.Until(function()
			return m.Phase == "Live" and m.Round == 3
		end, 10),
		"Runde 3 live"
	)
	fake.Combatants()[1].Hp = 80
	fake.Combatants()[2].Hp = 30
	truthy(
		fake.Until(function()
			return m.Phase == "Overtime"
		end, 61),
		"Overtime in Runde 3"
	)
	truthy(
		fake.Until(function()
			return m.Phase == "RoundEnd"
		end, 16),
		"Overtime-Ende"
	)
	eq(fake.LastEnd().Winner, 1, "Tiebreak HP")
	eq(fake.LastEnd().Reason, "Hp", "Grund Hp")
	local over, winner = Rounds.CheckEnd(m)
	eq(over, false, "erst nach RoundEnd vorbei")
	fake.Advance(2.6)
	over, winner = Rounds.CheckEnd(m)
	eq(over, true, "Match vorbei")
	eq(winner, 1, "Match-Sieger")
end

Tests["Rounds Simulation: Rundenlimit endet mit Sudden Death"] = function()
	local m, fake = fakeMatch(1, 1) -- Erster auf 1, Limit 3
	Rounds.Start(m)
	for round = 1, 3 do
		truthy(
			fake.Until(function()
				return m.Phase == "Live"
			end, 10),
			"Runde " .. round .. " live"
		)
		truthy(
			fake.Until(function()
				return m.Phase == "RoundEnd"
			end, 80),
			"Runde " .. round .. " vorbei"
		)
		eq(fake.LastEnd().Winner, 0, "Runde unentschieden (beide voll)")
		truthy(
			fake.Until(function()
				return m.Phase == "Prep"
			end, 5),
			"nächste Prep"
		)
	end
	eq(m.SuddenDeath, true, "nach dem Limit: Sudden Death")
	truthy(
		fake.Until(function()
			return m.Phase == "Live"
		end, 5),
		"SD live"
	)
	eq(m.ZoneOpen, true, "Zone von Anfang an offen")
	fake.Kill(1, 2)
	eq(fake.LastEnd().Winner, 2, "SD-Runde gewonnen")
	fake.Advance(2.6)
	local over, winner = Rounds.CheckEnd(m)
	eq(over, true, "Match beendet")
	eq(winner, 2, "Sieger nach Sudden Death")
end

Tests["Rounds CLUTCH 1v2 und ACE ab 3v3 (B6.6)"] = function()
	local m, fake = fakeMatch(3, 4)
	Rounds.Start(m)
	fake.Advance(4.2)
	-- Team 1: Spieler 1+2 fallen, Spieler 3 bleibt gegen 3 -> Clutch-Kandidat, poppt alle 3 = ACE
	fake.Kill(1, 4)
	fake.Kill(2, 5)
	fake.Kill(4, 3)
	fake.Kill(5, 3)
	fake.Kill(6, 3)
	local info = fake.LastEnd()
	eq(info.Winner, 1, "Team 1 gewinnt")
	truthy(info.Clutch ~= nil and info.Clutch.Id == 3, "Clutch-Spieler")
	eq(info.Clutch.Vs, 3, "1v3")
	eq(info.AceId, 3, "ACE")
	truthy(table.find(info.Banners, "Clutch") and table.find(info.Banners, "Ace"), "Banner")
end

-- ---------------------------------------------------------------------
-- FFA (Respawn)
-- ---------------------------------------------------------------------
Tests["Respawn Punkte, Führender, Spawn-Wertung (B4/FFA)"] = function()
	eq(Respawn.SpawnScore(100, 2, 40), 20, "minDist − 40 × Sicht")
	local leader, tie = Respawn.Leader({ [1] = 10, [2] = 12, [3] = 12 }, { [2] = 300, [3] = 200 })
	eq(leader, 2, "Gleichstand -> mehr Schaden")
	eq(tie, false, "kein Gleichstand mehr")
	leader, tie = Respawn.Leader({ [1] = 5, [2] = 5 }, nil)
	eq(tie, true, "echter Gleichstand")
	local clock = 0
	local m: any = {
		Def = Config.Modes.Modes.FFA,
		Scores = {},
		Api = {
			Now = function()
				return clock
			end,
			Send = function() end,
			GoLive = function() end,
			Combatants = function()
				return {}
			end,
			TeamOf = function(id: number)
				return id
			end,
			DamageTable = function()
				return {}
			end,
		},
	}
	Respawn.Start(m)
	m.Scores[1], m.Scores[2], m.Scores[3] = 0, 0, 0
	for _ = 1, 12 do
		Respawn.OnElim(m, { Id = 2 }, { Id = 1 }, { Assists = { 3 } })
	end
	eq(m.Scores[1], 24, "12 Pops × 2")
	eq(m.Scores[3], 12, "12 Assists × 1")
	eq(Respawn.CheckEnd(m), false, "noch nicht 25")
	Respawn.OnElim(m, { Id = 2 }, { Id = 1 }, { Assists = {} })
	local over, winner = Respawn.CheckEnd(m)
	eq(over, true, "25 Punkte = Sieg")
	eq(winner, 1, "FFA-Sieger")
end

-- ---------------------------------------------------------------------
-- Matcher (B3.1)
-- ---------------------------------------------------------------------
local function agg(mmr: number, matches: number, input: string)
	local new = matches < Config.Modes.Queue.NewPlayerMatches
	local veteran = matches >= Config.Modes.Queue.NewPlayerPool
	return { Mmr = mmr, New = new, Veteran = veteran, Rookie = matches < 3, Input = input }
end

Tests["Matcher-Regeln: Eingabegruppe, MMR-Fenster, Neulings-Schutz"] = function()
	local q = Config.Modes.Queue
	eq(QueueService._Compatible(agg(1000, 10, "KBM"), agg(1100, 12, "KBM"), 0, q), true, "gleich, im Fenster")
	eq(
		QueueService._Compatible(agg(1000, 10, "KBM"), agg(1000, 10, "Pad"), 2, q),
		false,
		"Eingabe ≠ in den ersten 6 s"
	)
	eq(QueueService._Compatible(agg(1000, 10, "KBM"), agg(1000, 10, "Pad"), 6.5, q), true, "Eingabe egal nach 6 s")
	eq(QueueService._Compatible(agg(1000, 10, "KBM"), agg(1260, 10, "KBM"), 1, q), false, "MMR 260 > 200")
	eq(QueueService._Compatible(agg(1000, 10, "KBM"), agg(1260, 10, "KBM"), 6, q), true, "nach 6 s: Fenster 300")
	eq(
		QueueService._Compatible(agg(1000, 2, "KBM"), agg(1000, 40, "KBM"), 30, q),
		false,
		"Neuling trifft keinen Veteran"
	)
	eq(QueueService._Compatible(agg(1000, 2, "KBM"), agg(1000, 14, "KBM"), 0, q), true, "Neuling trifft < 15 Matches")
end

Tests["Matcher-Paarung mit Fake-Einträgen (zwei 1v1-Pads, 2v2 gemischt)"] = function()
	local always = function()
		return true
	end
	-- zwei Menschen auf VERSCHIEDENEN 1v1-Pads werden gepaart (Abnahme 2)
	local e1 = { Players = { "p1" }, Since = 0 }
	local e2 = { Players = { "p2" }, Since = 1 }
	local units = { { A = e1 }, { A = e2 } }
	local t1, t2, _, n1, n2 = QueueService._FormTeams(units, units[1], 1, always)
	eq(n1, 1, "Team 1 voll")
	eq(n2, 1, "Team 2 voll")
	eq(t1[1], e1, "ältester Eintrag in Team 1")
	eq(t2[1], e2, "zweiter Eintrag als Gegner")
	-- 2v2: Pad-Paar (je 1) + zwei Einzelne -> 2 gegen 2, Pad-Hälften bleiben Gegner
	local a = { Players = { "a" }, Since = 0 }
	local b = { Players = { "b" }, Since = 0 }
	local c = { Players = { "c" }, Since = 1 }
	local d = { Players = { "d" }, Since = 2 }
	units = { { A = a, B = b }, { A = c }, { A = d } }
	t1, t2, _, n1, n2 = QueueService._FormTeams(units, units[1], 2, always)
	eq(n1 + n2, 4, "4 Spieler verteilt")
	eq(n1, 2, "Team 1 = 2")
	eq(n2, 2, "Team 2 = 2")
	eq(t1[1], a, "Pad-Hälfte A in Team 1")
	eq(t2[1], b, "Pad-Hälfte B in Team 2")
	-- inkompatibel: niemand wird dazugenommen -> Bot-Füllung später
	local never = function()
		return false
	end
	t1, t2, _, n1, n2 = QueueService._FormTeams({ { A = e1 }, { A = e2 } }, { A = e1 }, 1, never)
	eq(n1, 1, "nur der Anker")
	eq(n2, 0, "kein Gegner")
end

-- ---------------------------------------------------------------------
-- Regeln, Config, Texte
-- ---------------------------------------------------------------------
Tests["Rounds.BuildRules: Modus + Mutator (B7)"] = function()
	local turbo = Rounds.BuildRules("Mutator", "Turbo", Config.Modes)
	eq(turbo.SpeedMult, 1.35, "Turbo SpeedMult")
	eq(turbo.ReloadMult, 0.7, "Turbo ReloadMult")
	eq(turbo.HeadOnly, false, "Grundregel bleibt")
	local ffa = Rounds.BuildRules("FFA", nil, Config.Modes)
	eq(ffa.Regen, true, "FFA Regeneration")
	eq(ffa.UtilityMode, "Cooldown", "FFA Utility-Abklingzeit")
	local practice = Rounds.BuildRules("Practice", nil, Config.Modes)
	eq(practice.IgnoreOwnership, true, "Practice: jede Waffe")
	local melee = Rounds.BuildRules("Mutator", "MeleeMayhem", Config.Modes)
	truthy(melee.AllowedSlots and melee.AllowedSlots.Melee and not melee.AllowedSlots.Primary, "Nahkampf-Chaos Slots")
	truthy(melee.AllowedSlots ~= Config.Modes.Mutators.MeleeMayhem.Rules.AllowedSlots, "Regeln sind Kopien")
	local snipers = Rounds.BuildRules("Mutator", "SnipersOnly", Config.Modes)
	eq(snipers.ForcedLoadout.Primary, "Longshot", "Erzwungenes Loadout")
end

Tests["Config.Modes.Validate leer + Tages-Mutator in der Rotation"] = function()
	local errors = Config.Modes.Validate(Config)
	if #errors > 0 then
		error("Config.Modes: " .. table.concat(errors, " | "))
	end
	local rotation = Config.Modes.Rotation
	for day = 0, 7 do
		local key = rotation[(day % #rotation) + 1]
		truthy(Config.Modes.Mutators[key] ~= nil, "Rotation Tag " .. day)
	end
end

Tests["Lang: Pflicht-Schlüssel match.* (C16)"] = function()
	local required = {
		"match.found",
		"match.botIn",
		"match.searching",
		"match.overtime",
		"match.clutch",
		"match.ace",
		"match.flawless",
		"match.comeback",
		"match.matchPoint",
		"match.suddenDeath",
		"match.arenasFull",
		"match.botsBusy",
	}
	for _, key in ipairs(required) do
		truthy(Lang.T("de", key) ~= key and Lang.T("en", key) ~= key, key)
	end
	eq(Lang.T("en", "match.botIn", 6), "BOT JOINS IN 6", "Format botIn")
	eq(Lang.T("de", "match.searching", 3), "3 suchen", "Format searching")
end

return Tests
