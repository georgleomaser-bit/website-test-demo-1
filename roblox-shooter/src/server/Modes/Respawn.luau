-- =====================================================================
--  CLUTCH CLASH – Regelwerk "Respawn" / FFA-Brawl (Server/Modes/Respawn)
--  Besitzer: WP5 (Match & Warteschlangen). Vertrag: DESIGN.md C5.5, B4 (FFA), B5 (Regelwerk Respawn).
--
--  Reine Regel-Logik wie Modes/Rounds: Seiteneffekte nur über m.Api (MatchService).
--  Ablauf: Vote 5 → Load ≤ 4 → Intro 2 → Live 300 s → MatchEnd 10 s (Vote/Load/Intro/MatchEnd macht MatchService).
--  Punkte: Pop +KillPoints (2), Assist +AssistPoints (1); Sieg bei ScoreToWin (25) oder nach MatchTime.
--  Respawn nach RespawnDelay (3 s) am besten von 8 Kandidaten: minDist − 40 × (Gegner mit Sicht).
--  Regeneration: +Rate HP/s nach Delay s ohne Schaden (Config.Player.Regen, ContextRules.Regen).
--
--  Lebenszyklus (C5.5): Respawn.Start(m) · Respawn.Tick(m, dt) · Respawn.OnElim(m, victim, killer, info) ·
--    Respawn.CheckEnd(m): (boolean, number?)
--  Reine Helfer (testbar):
--    Respawn.SpawnScore(minDist, visibleEnemies, penalty): number
--    Respawn.Leader(scores, tiebreak?): (id?, tie)       höchste Punktzahl; Gleichstand -> tiebreak[id] höher gewinnt
--
--  m.Api (von MatchService): Now(), Send(kind, data), GoLive(), Combatants(): { Combatant },
--    Respawn(c), Heal(c, amount), TeamOf(id): number, DamageOf(id): number
-- =====================================================================

local Respawn = {}

-- ---------------------------------------------------------------------
-- 1) REINE HELFER
-- ---------------------------------------------------------------------
function Respawn.SpawnScore(minDist: number, visibleEnemies: number, penalty: number): number
	return minDist - penalty * visibleEnemies
end

-- Führender nach Punkten; Gleichstand -> höherer tiebreak-Wert (z. B. Schaden), sonst tie = true
function Respawn.Leader(scores: { [number]: number }, tiebreak: { [number]: number }?): (number?, boolean)
	local bestId: number? = nil
	local best = -math.huge
	local tie = false
	for id, value in pairs(scores) do
		if value > best then
			best, bestId, tie = value, id, false
		elseif value == best then
			local a = if tiebreak then tiebreak[id] or 0 else 0
			local b = if tiebreak and bestId then tiebreak[bestId] or 0 else 0
			if a > b then
				bestId, tie = id, false
			elseif a == b then
				tie = true
				-- deterministisch: kleinere Id merken, Gleichstand bleibt markiert
				if bestId == nil or id < bestId then
					bestId = id
				end
			end
		end
	end
	return bestId, tie
end

-- ---------------------------------------------------------------------
-- 2) LEBENSZYKLUS
-- ---------------------------------------------------------------------
local function sendScores(m: any)
	local copy: { [string]: number } = {}
	for id, value in pairs(m.Scores) do
		copy[tostring(id)] = value -- String-Schlüssel: Remote-Tabellen mit gemischten Zahl-Keys gehen verloren
	end
	m.Api.Send("Score", { Scores = copy, EndsAt = m.PhaseEnds })
end

function Respawn.Start(m: any)
	local now = m.Api.Now()
	m.Scores = m.Scores or {}
	m.RespawnAt = {}
	m.Phase = "Live"
	m.PhaseStart = now
	m.PhaseEnds = now + (m.Def.MatchTime or 300)
	m.MatchOver = false
	m.MatchWinner = nil
	for _, c in ipairs(m.Api.Combatants()) do
		if m.Scores[c.Id] == nil then
			m.Scores[c.Id] = 0
		end
	end
	m.Api.GoLive()
	m.Api.Send("Live", { EndsAt = m.PhaseEnds })
	sendScores(m)
end

-- Neuer Teilnehmer (Drop-in oder Bot-Nachfüllung)
function Respawn.AddCombatant(m: any, c: any)
	if m.Scores[c.Id] == nil then
		m.Scores[c.Id] = 0
	end
	sendScores(m)
end

function Respawn.RemoveCombatant(m: any, id: number)
	m.RespawnAt[id] = nil
	if m.Scores[id] ~= nil then
		m.Scores[id] = nil
		sendScores(m)
	end
end

function Respawn.Tick(m: any, dt: number)
	if m.Phase ~= "Live" or m.MatchOver then
		return
	end
	local now = m.Api.Now()
	local regen = m.Regen
	for _, c in ipairs(m.Api.Combatants()) do
		local at = m.RespawnAt[c.Id]
		if not c.Alive then
			if at and now >= at then
				m.RespawnAt[c.Id] = nil
				m.Api.Respawn(c)
			elseif at == nil then
				-- Pop ohne OnElim (z. B. Fallback) -> trotzdem wiederbeleben
				m.RespawnAt[c.Id] = now + (m.Def.RespawnDelay or 3)
			end
		elseif regen and c.Hp < c.MaxHp and now - (c.LastDamageAt or 0) >= regen.Delay then
			m.Api.Heal(c, regen.Rate * dt)
		end
	end
	if now >= m.PhaseEnds then
		local leader, tie = Respawn.Leader(m.Scores, m.Api.DamageTable())
		m.MatchOver = true
		m.MatchWinner = if leader and not tie then m.Api.TeamOf(leader) else 0
	end
end

function Respawn.OnElim(m: any, victim: any, killer: any?, info: any)
	if m.Phase ~= "Live" or m.MatchOver then
		return
	end
	local now = m.Api.Now()
	m.RespawnAt[victim.Id] = now + (m.Def.RespawnDelay or 3)
	local changed = false
	if killer and killer ~= victim and m.Scores[killer.Id] ~= nil then
		m.Scores[killer.Id] += m.Def.KillPoints or 2
		changed = true
	end
	if type(info) == "table" and type(info.Assists) == "table" then
		for _, assistId in ipairs(info.Assists) do
			if m.Scores[assistId] ~= nil and assistId ~= victim.Id and (killer == nil or assistId ~= killer.Id) then
				m.Scores[assistId] += m.Def.AssistPoints or 1
				changed = true
			end
		end
	end
	if changed then
		sendScores(m)
	end
	local target = m.Def.ScoreToWin or 25
	for id, value in pairs(m.Scores) do
		if value >= target then
			m.MatchOver = true
			m.MatchWinner = m.Api.TeamOf(id)
			break
		end
	end
end

function Respawn.OnDamage(_m: any, _attacker: any?, _victim: any, _dealt: number) end

function Respawn.CheckEnd(m: any): (boolean, number?)
	if m.MatchOver then
		return true, m.MatchWinner or 0
	end
	return false, nil
end

return Respawn
