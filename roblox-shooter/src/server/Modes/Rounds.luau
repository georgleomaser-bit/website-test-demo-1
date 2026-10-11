-- =====================================================================
--  CLUTCH CLASH – Regelwerk "Rounds" (Server/Modes/Rounds)
--  Besitzer: WP5 (Match & Warteschlangen). Vertrag: DESIGN.md C5.5, B5 (Prep/Live/RoundEnd), B6.
--
--  Reine Regel-Logik: Dieses Modul ruft KEINE Services auf. Alle Seiteneffekte (Teleport, Revive,
--  Nachrichten an die Clients) laufen über m.Api, das MatchService pro Match baut. Dadurch sind
--  Tiebreak, Zone, Rundenlimit und Sudden Death mit Fake-Matches testbar (Tests/MatchTests).
--
--  Lebenszyklus (von MatchService aufgerufen, Vertrag C5.5):
--    Rounds.Start(m)                       nach dem Intro: Runde 1 (Prep)
--    Rounds.Tick(m, dt)                    5 Hz: Prep -> Live -> Overtime -> RoundEnd -> …
--    Rounds.OnElim(m, victim, killer, info)
--    Rounds.CheckEnd(m): (boolean, number?) Match vorbei? + Sieger-Team (0 = Unentschieden)
--  Reine Helfer (testbar):
--    Rounds.RoundCap(roundsToWin): number                       2 × RoundsToWin + 1
--    Rounds.Tiebreak(teams, useAlive?): (winner, reason)        B6.3 (a) lebende (b) HP (c) Schaden (d) Draw
--    Rounds.ZoneStep(state, holder, contested, dt, cfg): number? B6.2 Fortschritt, gibt Sieger-Team zurück
--    Rounds.Outcome(score, roundsToWin, roundsPlayed, cap, suddenDeathPlayed, lastWinner): (kind, winner)
--    Rounds.BuildRules(modeKey, mutatorKey?, modesCfg): ContextRules
--    Rounds.MatchPointTeams(score, roundsToWin): { number }
--
--  m.Api (von MatchService): Now(), Send(kind, data), BeginRound(suddenDeath), GoLive(), StartOvertime(endsAt),
--    AliveByTeam(): { [team]: { Combatant } }, TeamHp(team), TeamDamage(team), ZonePresence(): { [team]: number },
--    AllReady(): boolean, RoundEnded(info), ZoneUpdate(team, progress, contested), AntiCamp(untilT)
--  Zusätzlich: Rounds.OnDamage(m, attacker, victim, dealt) (FLAWLESS/Anti-Camp), Rounds.Forfeit(m, winner)
-- =====================================================================

local Rounds = {}

export type TeamStat = { Team: number, Alive: number, Hp: number, Damage: number }
export type ZoneState = { Team: number, Value: number }

-- ---------------------------------------------------------------------
-- 1) REINE HELFER
-- ---------------------------------------------------------------------
function Rounds.RoundCap(roundsToWin: number): number
	return 2 * roundsToWin + 1
end

-- B6.3: (a) mehr lebende Spieler, (b) höhere HP-Summe, (c) mehr Schaden in dieser Runde, (d) Unentschieden.
-- useAlive = false überspringt (a) (wird nie gebraucht, aber für Sudden-Death-Varianten offen).
function Rounds.Tiebreak(teams: { TeamStat }, useAlive: boolean?): (number, string)
	local candidates: { TeamStat } = {}
	for _, t in ipairs(teams) do
		table.insert(candidates, t)
	end
	if #candidates == 0 then
		return 0, "Draw"
	end
	local steps: { { Field: string, Reason: string } } = {}
	if useAlive ~= false then
		table.insert(steps, { Field = "Alive", Reason = "Alive" })
	end
	table.insert(steps, { Field = "Hp", Reason = "Hp" })
	table.insert(steps, { Field = "Damage", Reason = "Damage" })
	for _, step in ipairs(steps) do
		local best = -math.huge
		for _, t in ipairs(candidates) do
			local v = (t :: any)[step.Field] or 0
			if v > best + 1e-6 then
				best = v
			end
		end
		local top: { TeamStat } = {}
		for _, t in ipairs(candidates) do
			if math.abs(((t :: any)[step.Field] or 0) - best) <= 1e-6 then
				table.insert(top, t)
			end
		end
		if #top == 1 then
			return top[1].Team, step.Reason
		end
		candidates = top
	end
	return 0, "Draw"
end

-- B6.2: +1/s beim Halten, eingefroren bei umkämpft, −Decay/s wenn leer, Capture s = Sieg.
-- Hält ein anderes Team als der aktuelle Besitzer des Fortschritts, drückt es ihn erst auf 0.
-- Gibt das Sieger-Team zurück, sobald der Fortschritt voll ist (sonst nil). state wird verändert.
function Rounds.ZoneStep(
	state: ZoneState,
	holder: number,
	contested: boolean,
	dt: number,
	cfg: { ZoneCapture: number, ZoneDecay: number }
): number?
	if contested then
		return nil
	end
	if holder ~= 0 then
		if state.Team == holder or state.Team == 0 or state.Value <= 0 then
			state.Team = holder
			state.Value += dt
		else
			state.Value -= dt
			if state.Value <= 0 then
				state.Team = holder
				state.Value = 0
			end
		end
	else
		state.Value = math.max(0, state.Value - cfg.ZoneDecay * dt)
		if state.Value <= 0 then
			state.Team = 0
		end
	end
	if state.Team ~= 0 and state.Value >= cfg.ZoneCapture then
		state.Value = cfg.ZoneCapture
		return state.Team
	end
	return nil
end

-- Wer hält die Zone? presence = { [team] = lebende Mitglieder in der Zone }
function Rounds.ZoneHolder(presence: { [number]: number }): (number, boolean)
	local holder, teams = 0, 0
	for team, count in pairs(presence) do
		if count > 0 then
			teams += 1
			holder = team
		end
	end
	if teams >= 2 then
		return 0, true
	end
	return holder, false
end

-- Nach einer Runde: "Win" (Match-Sieger), "Draw" (Match-Unentschieden), "SuddenDeath" (nächste Runde SD) oder "Continue".
function Rounds.Outcome(
	score: { number },
	roundsToWin: number,
	roundsPlayed: number,
	cap: number,
	suddenDeathPlayed: boolean,
	lastWinner: number
): (string, number)
	if suddenDeathPlayed then
		-- Sudden Death entscheidet: Sieger der SD-Runde gewinnt, sonst Match-Unentschieden
		if lastWinner > 0 then
			return "Win", lastWinner
		end
		return "Draw", 0
	end
	for team, value in ipairs(score) do
		if value >= roundsToWin then
			return "Win", team
		end
	end
	if roundsPlayed >= cap then
		local best, bestTeam, tie = -1, 0, false
		for team, value in ipairs(score) do
			if value > best then
				best, bestTeam, tie = value, team, false
			elseif value == best then
				tie = true
			end
		end
		if tie then
			return "SuddenDeath", 0
		end
		return "Win", bestTeam
	end
	return "Continue", 0
end

-- Teams, die nur noch eine Runde brauchen (MATCH POINT)
function Rounds.MatchPointTeams(score: { number }, roundsToWin: number): { number }
	local list: { number } = {}
	for team, value in ipairs(score) do
		if value == roundsToWin - 1 then
			table.insert(list, team)
		end
	end
	return list
end

-- ContextRules aus Grund-Regeln + Modus + Mutator (alles aus Config.Modes)
function Rounds.BuildRules(modeKey: string, mutatorKey: string?, modesCfg: any): { [string]: any }
	local rules: { [string]: any } = {}
	local function apply(src: any)
		if type(src) ~= "table" then
			return
		end
		for key, value in pairs(src) do
			if type(value) == "table" then
				rules[key] = table.clone(value)
			else
				rules[key] = value
			end
		end
	end
	apply(modesCfg.DefaultRules)
	apply(modesCfg.ModeRules and modesCfg.ModeRules[modeKey])
	if mutatorKey then
		local mutator = modesCfg.Mutators and modesCfg.Mutators[mutatorKey]
		if mutator then
			apply(mutator.Rules)
		end
	end
	return rules
end

-- ---------------------------------------------------------------------
-- 2) LEBENSZYKLUS (Seiteneffekte nur über m.Api)
-- ---------------------------------------------------------------------
local function teamCount(m: any): number
	return #m.Score
end

local function aliveTeams(m: any): ({ number }, { [number]: { any } })
	local byTeam = m.Api.AliveByTeam()
	local teams: { number } = {}
	for team = 1, teamCount(m) do
		local list = byTeam[team]
		if list and #list > 0 then
			table.insert(teams, team)
		end
	end
	return teams, byTeam
end

local function teamStats(m: any): { TeamStat }
	local _, byTeam = aliveTeams(m)
	local stats: { TeamStat } = {}
	for team = 1, teamCount(m) do
		local list = byTeam[team] or {}
		table.insert(stats, {
			Team = team,
			Alive = #list,
			Hp = m.Api.TeamHp(team),
			Damage = m.Api.TeamDamage(team),
		})
	end
	return stats
end

local function beginPrep(m: any)
	local now = m.Api.Now()
	m.Round += 1
	m.SuddenDeath = m.PendingSuddenDeath == true
	m.PendingSuddenDeath = false
	m.RoundKills = {}
	m.RoundKillsByTeam = {}
	m.RoundDamageTaken = {}
	m.RoundClutch = {}
	m.RoundTeamSize = {}
	m.Zone = { Team = 0, Value = 0 }
	m.ZoneOpen = false
	m.ZoneSent = nil
	m.LastDamageAt = now
	m.NextAntiCamp = 0
	m.Api.BeginRound(m.SuddenDeath)
	local cfg = m.Cfg
	local prep = if m.Round == 1 then cfg.FirstPrep else cfg.Prep
	m.Phase = "Prep"
	m.PhaseStart = now
	m.PhaseEnds = now + prep
	local matchPoint = #Rounds.MatchPointTeams(m.Score, m.RoundsToWin) > 0
	m.Api.Send("Prep", {
		Round = m.Round,
		Score = table.clone(m.Score),
		EndsAt = m.PhaseEnds,
		MatchPoint = matchPoint and not m.SuddenDeath,
		SuddenDeath = m.SuddenDeath,
		Tainted = m.Tainted == true,
	})
end

local function openZone(m: any)
	m.ZoneOpen = true
	m.Api.StartOvertime(m.PhaseEnds)
end

local function goLive(m: any)
	local now = m.Api.Now()
	local cfg = m.Cfg
	m.Phase = "Live"
	m.PhaseStart = now
	m.PhaseEnds = now + (if m.SuddenDeath then cfg.SuddenDeath else m.RoundTime)
	m.LastDamageAt = now
	m.NextAntiCamp = 0
	-- Teamgrößen zu Rundenbeginn (für ACE)
	local _, byTeam = aliveTeams(m)
	for team = 1, teamCount(m) do
		m.RoundTeamSize[team] = #(byTeam[team] or {})
	end
	m.Api.GoLive()
	m.Api.Send("Live", { EndsAt = m.PhaseEnds })
	if m.SuddenDeath then
		-- Sudden Death: Zone von Anfang an offen
		openZone(m)
	end
end

local function endRound(m: any, winner: number, reason: string)
	if m.Phase == "RoundEnd" then
		return
	end
	local now = m.Api.Now()
	if winner > 0 and m.Score[winner] ~= nil then
		m.Score[winner] += 1
	end
	m.RoundsPlayed += 1
	-- COMEBACK-Merker: ein Team lag 0–3 zurück
	for team = 1, teamCount(m) do
		local other = if team == 1 then 2 else 1
		if m.Score[team] == 0 and (m.Score[other] or 0) >= 3 then
			m.ComebackFrom[team] = true
		end
	end

	-- Banner-Flags (B6.6)
	local banners: { string } = {}
	local clutch = if winner > 0 then m.RoundClutch[winner] else nil
	if clutch then
		table.insert(banners, "Clutch")
	end
	local aceId: number? = nil
	if winner > 0 and m.TeamSize >= 3 then
		local other = if winner == 1 then 2 else 1
		local need = m.RoundTeamSize[other] or 0
		if need >= 3 then
			for killerId, kills in pairs(m.RoundKills) do
				if m.RoundKillsTeamOf[killerId] == winner and kills >= need then
					aceId = killerId
					break
				end
			end
		end
		if aceId then
			table.insert(banners, "Ace")
		end
	end
	local flawless = winner > 0 and (m.RoundDamageTaken[winner] or 0) <= 0
	if flawless then
		table.insert(banners, "Flawless")
	end

	local kind, matchWinner = Rounds.Outcome(m.Score, m.RoundsToWin, m.RoundsPlayed, m.RoundCap, m.SuddenDeath, winner)
	if kind == "Win" or kind == "Draw" then
		m.MatchOver = true
		m.MatchWinner = matchWinner
		if kind == "Win" and m.ComebackFrom[matchWinner] then
			table.insert(banners, "Comeback")
			m.Comeback = matchWinner
		end
	elseif kind == "SuddenDeath" then
		m.PendingSuddenDeath = true
		m.SuddenDeathPlayed = true
	else
		if #Rounds.MatchPointTeams(m.Score, m.RoundsToWin) > 0 then
			table.insert(banners, "MatchPoint")
		end
	end
	if m.PendingSuddenDeath then
		table.insert(banners, "SuddenDeath")
	end

	m.Phase = "RoundEnd"
	m.PhaseStart = now
	m.PhaseEnds = now + m.Cfg.RoundEnd
	m.ZoneOpen = false
	m.Api.RoundEnded({
		Winner = winner,
		Reason = reason,
		Banners = banners,
		Clutch = clutch,
		AceId = aceId,
		Flawless = flawless,
	})
end

local function resolveTimeout(m: any)
	local winner, reason = Rounds.Tiebreak(teamStats(m))
	endRound(m, winner, reason)
end

local function stepZone(m: any, dt: number)
	if not m.ZoneOpen then
		return
	end
	local holder, contested = Rounds.ZoneHolder(m.Api.ZonePresence())
	local captured = Rounds.ZoneStep(m.Zone, holder, contested, dt, m.Cfg)
	local progress = math.clamp(m.Zone.Value / m.Cfg.ZoneCapture, 0, 1)
	local sent = m.ZoneSent
	if
		sent == nil
		or sent.Team ~= m.Zone.Team
		or sent.Contested ~= contested
		or math.abs(sent.Progress - progress) >= 0.02
		or (progress == 0) ~= (sent.Progress == 0)
	then
		m.ZoneSent = { Team = m.Zone.Team, Progress = progress, Contested = contested }
		m.Api.ZoneUpdate(m.Zone.Team, progress, contested)
	end
	if captured then
		m.ZoneCaptured = captured
		endRound(m, captured, "Zone")
	end
end

local function stepAntiCamp(m: any)
	local now = m.Api.Now()
	local threshold = if m.TeamSize <= 1 then m.AntiCamp.Duel else m.AntiCamp.Team
	if now - m.LastDamageAt >= threshold and now >= m.NextAntiCamp then
		m.NextAntiCamp = now + m.AntiCamp.Pulse
		m.Api.AntiCamp(now + m.AntiCamp.Show)
	end
end

function Rounds.Start(m: any)
	m.Round = 0
	m.RoundsPlayed = 0
	m.Score = m.Score or { 0, 0 }
	m.ComebackFrom = {}
	m.RoundKillsTeamOf = {}
	m.MatchOver = false
	m.MatchWinner = nil
	m.SuddenDeathPlayed = false
	m.PendingSuddenDeath = false
	beginPrep(m)
end

-- Phase frisch lesen (stepZone kann die Runde beenden)
local function phaseOf(m: any): string
	return m.Phase
end

function Rounds.Tick(m: any, dt: number)
	if m.MatchOver and m.Phase ~= "RoundEnd" then
		return
	end
	local now = m.Api.Now()
	local phase = m.Phase
	if phase == "Prep" then
		local readyEarly = m.Api.AllReady() and now - m.PhaseStart >= m.Cfg.ReadyMinPrep
		if now >= m.PhaseEnds or readyEarly then
			goLive(m)
		end
	elseif phase == "Live" then
		stepZone(m, dt)
		if phaseOf(m) ~= "Live" then
			return
		end
		-- Team leer (z. B. verlassen/AFK mitten in der Runde) -> Runde sofort entscheiden
		local teams = aliveTeams(m)
		if #teams <= 1 then
			endRound(m, teams[1] or 0, if #teams == 1 then "Elim" else "Draw")
			return
		end
		stepAntiCamp(m)
		if now >= m.PhaseEnds then
			if m.SuddenDeath then
				resolveTimeout(m)
			else
				m.Phase = "Overtime"
				m.PhaseStart = now
				m.PhaseEnds = now + m.OvertimeTime
				openZone(m)
			end
		end
	elseif phase == "Overtime" then
		stepZone(m, dt)
		if phaseOf(m) ~= "Overtime" then
			return
		end
		local teams = aliveTeams(m)
		if #teams <= 1 then
			endRound(m, teams[1] or 0, if #teams == 1 then "Elim" else "Draw")
			return
		end
		stepAntiCamp(m)
		if now >= m.PhaseEnds then
			resolveTimeout(m)
		end
	elseif phase == "RoundEnd" then
		if now >= m.PhaseEnds and not m.MatchOver then
			beginPrep(m)
		end
	end
end

-- Pop in diesem Match (MatchService hat Statistik und Nachrichten schon erledigt)
function Rounds.OnElim(m: any, victim: any, killer: any?, _info: any)
	if m.Phase ~= "Live" and m.Phase ~= "Overtime" then
		return
	end
	if killer and killer ~= victim and killer.Team ~= victim.Team then
		m.RoundKills[killer.Id] = (m.RoundKills[killer.Id] or 0) + 1
		m.RoundKillsTeamOf[killer.Id] = killer.Team
	end
	local teams, byTeam = aliveTeams(m)
	-- CLUTCH-Kandidat: letzter Lebender seines Teams gegen ≥ 2 Gegner
	for team = 1, teamCount(m) do
		local mine = byTeam[team] or {}
		if #mine == 1 and m.RoundClutch[team] == nil then
			local enemies = 0
			for other = 1, teamCount(m) do
				if other ~= team then
					enemies += #(byTeam[other] or {})
				end
			end
			if enemies >= 2 then
				m.RoundClutch[team] = { Id = mine[1].Id, Vs = enemies }
			end
		end
	end
	if #teams <= 1 then
		endRound(m, teams[1] or 0, if #teams == 1 then "Elim" else "Draw")
	end
end

-- Schaden in diesem Match (für FLAWLESS und Anti-Camp)
function Rounds.OnDamage(m: any, _attacker: any?, victim: any, dealt: number)
	if m.Phase ~= "Live" and m.Phase ~= "Overtime" then
		return
	end
	if dealt > 0 then
		m.RoundDamageTaken[victim.Team] = (m.RoundDamageTaken[victim.Team] or 0) + dealt
		m.LastDamageAt = m.Api.Now()
		m.NextAntiCamp = 0
	end
end

-- Team ist weg (Aufgabe/AFK in 1v1): sofort entscheiden
function Rounds.Forfeit(m: any, winner: number)
	m.MatchOver = true
	m.MatchWinner = winner
	m.Phase = "RoundEnd"
	m.PhaseEnds = m.Api.Now()
end

function Rounds.CheckEnd(m: any): (boolean, number?)
	if m.MatchOver and m.Phase == "RoundEnd" and m.Api.Now() >= m.PhaseEnds then
		return true, m.MatchWinner or 0
	end
	return false, nil
end

return Rounds
