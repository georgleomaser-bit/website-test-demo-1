-- =====================================================================
--  CLUTCH CLASH – Matches, Runden, Krone, Ergebnis (Server/Services/MatchService)
--  Besitzer: WP5 (Match & Warteschlangen). Vertrag: DESIGN.md C5.5, B1.1 (Funnel 3–7), B4–B7, B9, B13.3, B14, B16.7, B25.2.
--
--  Zustandsmaschine (B5): Vote (5 s, Spieler in der Lobby) → Load (ArenaService.Acquire, ArenaReady, ≤ 4 s) →
--    Intro (2 s) → Regelwerk (Modes/Rounds: Prep/Live/Overtime/RoundEnd · Modes/Respawn: Live) → MatchEnd (10 s) → Closed.
--  Rematch: alle Menschen stimmen zu → gleiche Teams/Arena/Map, sofort Prep (ohne Laden/Intro).
--  Match-Daten gehen NUR an MatchService.Recipients(id) (Mitglieder + Crown-Zuschauer ≤ 150 Studs), nie FireAllClients.
--
--  Öffentliche API (C5.5):
--    MatchService.Create(spec: Types.MatchSpec): number?
--    MatchService.End(id, reason)
--    MatchService.MatchOf(p): number?
--    MatchService.Members(id): { Player }
--    MatchService.Recipients(id): { Player }
--    MatchService.Info(id): { MatchId, Slot, Mode, Map, Phase, Score, Players, Bots, Tainted }?
--    MatchService.List(): { Info }
--    MatchService.Taint(id, reason)
--    MatchService.OnMatchEnd(cb(result: Types.MatchResult))
--    MatchService.Route(p, char): ("Lobby" | "Vault" | "Spawn", CFrame?)     CharacterAdded-Router (B13.3)
--    MatchService.ActiveMutator(): string
--    MatchService.SetMutatorOverride(key?)
--  Zusätzlich (intern für QueueService/AdminService, WP5):
--    MatchService.CanHost(modeKey): boolean        freier Arena-Slot (abzüglich laufender Kartenwahlen)
--    MatchService.Leave(p, reason): boolean         "Left" | "LeftPad" | "Done"
--    MatchService.DropIn(p): boolean                FFA-Drop-in (B4)
--    MatchService.Phase(id): string?
--  Request-Aktionen (C9): ArenaReady, VoteMap, Ready, Rematch, AutoRequeue, LeaveMatch, PracticeStart, TutorialStart.
--  State-Schlüssel: "Mutator" (aktiver Tages-Mutator). Effect "Mutator" {Key} bei Admin-Override.
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Lang = require(Shared:WaitForChild("Lang"))
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))
local ModesFolder = script.Parent.Parent:WaitForChild("Modes")
local Rounds = require(ModesFolder:WaitForChild("Rounds"))
local Respawn = require(ModesFolder:WaitForChild("Respawn"))

-- ProgressMath (WP8) ist optional: nur für die Level-Anzeige im Ergebnis
local ProgressMath: any = nil
do
	local module = Shared:FindFirstChild("ProgressMath")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			ProgressMath = result
		end
	end
end

local MatchService = {}
local Services: any = nil

type Combatant = Types.Combatant
type Reply = Types.Reply

local MODES: any = Config.Modes
local MCFG: any = MODES.Match or {}
local SKILL: any = MODES.Skill or {}
local TICK_HZ = 5
local MAX_MATCHES = 24
local MAX_ROSTER = 32
local ERROR_LOG_EVERY = 10
local RANDOM_VOTE = 4 -- Vote-Index "Zufall"
local DEFAULT_LOADOUT =
	{ Primary = "PopRifle", Secondary = "PipPistol", Melee = "BoxingGloves", Utility = "PopGrenade" }
local SLOTS: { Types.SlotName } = { "Primary", "Secondary", "Melee", "Utility" }
local RULESET_PHASES = { Prep = true, Live = true, Overtime = true, RoundEnd = true }
local LIVE_PHASES = { Live = true, Overtime = true }

local rng = Random.new()

-- ---------------------------------------------------------------------
-- 1) ZUSTAND
-- ---------------------------------------------------------------------
type Stats = {
	Elims: number,
	PvpElims: number,
	Headshots: number,
	MeleeElims: number,
	Assists: number,
	Damage: number,
	Deaths: number,
	Flawless: number,
	Clutches: number,
	Aces: number,
	OvertimeCaps: number,
	WeaponKills: { [string]: number },
	WeaponUsed: { [string]: boolean },
	WeaponShots: { [string]: number },
	ShotsFired: number,
	ShotsHit: number,
}

type Entry = {
	Key: number, -- Roster-Slot 1..32
	Player: Player?,
	IsBot: boolean,
	Difficulty: string?,
	Team: number,
	Name: string,
	Id: number, -- Combatant-Id (Spieler = UserId, Bot erst nach dem Spawn)
	Combatant: Combatant?,
	Level: number,
	Title: string,
	Finisher: string,
	Removed: boolean,
	Left: boolean,
	AfkRemoved: boolean,
	Ready: boolean,
	LoadReady: boolean,
	AfkIdle: number,
	AfkWarned: boolean,
	AfkPos: Vector3?,
	AfkInput: number,
	MultiCount: number,
	MultiAt: number,
	Stats: Stats,
	Reported: boolean?, -- Leaver/AFK: Ergebnis schon einzeln gemeldet
	PendingSpawn: boolean?, -- Figur fehlte beim Laden
}

local matches: { [number]: any } = {}
local matchByCtx: { [string]: any } = {}
local playerMatch: { [Player]: number } = {}
local autoRequeue: { [Player]: boolean } = {}
local funnelDone: { [Player]: { [number]: boolean } } = {}
local practiceAt: { [Player]: number } = {}
local endCallbacks: { (Types.MatchResult) -> () } = {}
local recentMaps: { [string]: { string } } = {}
local nextMatchId = 0
local mutatorOverride: string? = nil
local lastMutator: string? = nil
local lastErrorAt: { [string]: number } = {}
local audienceAt = 0
local leaving: { [Player]: boolean } = {} -- gerade in PlayerRemoving (Parent ist dann noch Players)

local function now(): number
	return workspace:GetServerTimeNow()
end

local function logError(key: string, err: any)
	local t = os.clock()
	if (lastErrorAt[key] or -math.huge) + ERROR_LOG_EVERY <= t then
		lastErrorAt[key] = t
		warn("[MatchService] " .. key .. ": " .. tostring(err))
	end
end

-- Service-Aufruf in pcall (fehlender Service/Fehler -> false + Log, das Match läuft weiter)
local function call(service: string, fn: string, ...: any): (boolean, any, any)
	local s = Services and Services[service]
	local f = s and s[fn]
	if type(f) ~= "function" then
		return false, nil, nil
	end
	local ok, a, b = pcall(f, ...)
	if not ok then
		logError(service .. "." .. fn, a)
		return false, nil, nil
	end
	return true, a, b
end

local function modeDef(key: string): any
	return type(MODES.Modes) == "table" and MODES.Modes[key] or nil
end

local function langOf(p: Player): Types.Lang
	local ok, lang = call("PlayerStateService", "LangOf", p)
	if ok and (lang == "de" or lang == "en") then
		return lang
	end
	return Lang.For(p)
end

local function notify(p: Player, key: string, args: { any }?, kind: Types.NotifyKind?)
	call("PlayerStateService", "Notify", p, key, args, kind)
end

local function reply(p: Player, ok: boolean, key: string?, args: { any }?): Reply
	if key then
		return { Ok = ok, Message = Lang.T(langOf(p), key, table.unpack(args or {})) }
	end
	return { Ok = ok }
end

local function funnel(p: Player, step: number, name: string)
	local done = funnelDone[p]
	if not done then
		done = {}
		funnelDone[p] = done
	end
	if done[step] then
		return
	end
	done[step] = true
	call("MetricsService", "Funnel", p, step, name)
end

local function dataOf(p: Player): any
	local ok, data = call("DataService", "Get", p)
	return if ok and type(data) == "table" then data else nil
end

local function otherTeam(team: number): number
	return if team == 1 then 2 else 1
end

local function newStats(): Stats
	return {
		Elims = 0,
		PvpElims = 0,
		Headshots = 0,
		MeleeElims = 0,
		Assists = 0,
		Damage = 0,
		Deaths = 0,
		Flawless = 0,
		Clutches = 0,
		Aces = 0,
		OvertimeCaps = 0,
		WeaponKills = {},
		WeaponUsed = {},
		WeaponShots = {},
		ShotsFired = 0,
		ShotsHit = 0,
	}
end

-- ---------------------------------------------------------------------
-- 2) SENDEN (nur an Empfänger dieses Matches)
-- ---------------------------------------------------------------------
local function sendTo(p: Player, kind: string, data: any)
	if p.Parent == Players then
		Remotes.Match:FireClient(p, kind, data)
	end
end

local function humanEntries(m: any): { Entry }
	local list: { Entry } = {}
	for _, e in ipairs(m.Entries) do
		if e.Player and not e.Removed then
			table.insert(list, e)
		end
	end
	return list
end

local function sendMembers(m: any, kind: string, data: any)
	for _, e in ipairs(humanEntries(m)) do
		sendTo(e.Player :: Player, kind, data)
	end
end

local function sendRecipients(m: any, kind: string, data: any)
	for _, p in ipairs(MatchService.Recipients(m.Id)) do
		sendTo(p, kind, data)
	end
end

local function notifyMembers(m: any, key: string, args: { any }?, kind: Types.NotifyKind?)
	for _, e in ipairs(humanEntries(m)) do
		notify(e.Player :: Player, key, args, kind)
	end
end

-- ---------------------------------------------------------------------
-- 3) MAPS, STIMMUNGEN, MUTATOR, REGELN
-- ---------------------------------------------------------------------
local function mapCfg(key: string): any
	local maps = Config.Maps and Config.Maps.Maps
	return if type(maps) == "table" then maps[key] else nil
end

local function mapsFor(modeKey: string, teamSize: number): { string }
	local ok, list = call("ArenaService", "MapsFor", modeKey, teamSize)
	local result: { string } = {}
	if ok and type(list) == "table" then
		for _, key in ipairs(list) do
			if type(key) == "string" and mapCfg(key) and not mapCfg(key).Fixed then
				table.insert(result, key)
			end
		end
	end
	if #result == 0 then
		-- Fallback direkt aus Config.Maps (gleiche Regeln: Modus passt, Teamgröße passt, nicht fest)
		local maps = Config.Maps and Config.Maps.Maps
		if type(maps) == "table" then
			for key, def in pairs(maps) do
				if type(def) == "table" and not def.Fixed and type(def.Modes) == "table" then
					local sizeOk = modeKey == "FFA"
						or type(def.TeamSizes) ~= "table"
						or table.find(def.TeamSizes, teamSize) ~= nil
					if table.find(def.Modes, modeKey) and sizeOk then
						table.insert(result, key)
					end
				end
			end
			table.sort(result)
		end
	end
	return result
end

local function pickMood(mapKey: string): string
	local def = mapCfg(mapKey)
	local fallback = (Config.Maps and Config.Maps.LobbyMood) or "Day"
	if type(def) ~= "table" then
		return fallback
	end
	if type(def.ForcedMood) == "string" then
		return def.ForcedMood
	end
	if type(def.Moods) == "table" then
		local list = {}
		for mood, weight in pairs(def.Moods) do
			table.insert(list, { Mood = mood, Weight = weight })
		end
		table.sort(list, function(a, b)
			return a.Mood < b.Mood
		end)
		local pick = Util.WeightedPick(list, function(item)
			return item.Weight
		end, rng)
		if pick then
			return pick.Mood
		end
	end
	return fallback
end

local function shuffle<T>(list: { T })
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

local function buildVoteOptions(modeKey: string, teamSize: number): ({ { Map: string, Mood: string } }, { string })
	local all = mapsFor(modeKey, teamSize)
	local recent = recentMaps[modeKey] or {}
	local fresh: { string } = {}
	local stale: { string } = {}
	for _, key in ipairs(all) do
		if table.find(recent, key) then
			table.insert(stale, key)
		else
			table.insert(fresh, key)
		end
	end
	shuffle(fresh)
	shuffle(stale)
	-- reichen die Maps nicht, wird die Sperre der letzten 2 gelockert
	for _, key in ipairs(stale) do
		if #fresh >= 3 then
			break
		end
		table.insert(fresh, key)
	end
	local options = {}
	for i = 1, math.min(3, #fresh) do
		table.insert(options, { Map = fresh[i], Mood = pickMood(fresh[i]) })
	end
	return options, all
end

local function rememberMap(modeKey: string, mapKey: string)
	local list = recentMaps[modeKey]
	if not list then
		list = {}
		recentMaps[modeKey] = list
	end
	local idx = table.find(list, mapKey)
	if idx then
		table.remove(list, idx)
	end
	table.insert(list, 1, mapKey)
	while #list > (MCFG.RecentMaps or 2) do
		table.remove(list)
	end
end

function MatchService.ActiveMutator(): string
	local rotation = MODES.Rotation
	if mutatorOverride and MODES.Mutators and MODES.Mutators[mutatorOverride] then
		return mutatorOverride
	end
	if type(rotation) ~= "table" or #rotation == 0 then
		return "Turbo"
	end
	return rotation[(Util.UtcDay() % #rotation) + 1]
end

local function broadcastMutator()
	local key = MatchService.ActiveMutator()
	lastMutator = key
	call("PlayerStateService", "EffectAll", "Mutator", 1, { Key = key })
	for _, p in ipairs(Players:GetPlayers()) do
		call("PlayerStateService", "MarkDirty", p, "Mutator")
	end
end

function MatchService.SetMutatorOverride(key: string?)
	if key ~= nil and (type(key) ~= "string" or not (MODES.Mutators and MODES.Mutators[key])) then
		return
	end
	mutatorOverride = key
	broadcastMutator()
end

local function buildRules(modeKey: string, mutator: string?, tutorial: boolean): Types.ContextRules
	local rules = Rounds.BuildRules(modeKey, mutator, MODES)
	if tutorial then
		rules.IgnoreOwnership = true
	end
	return rules :: any
end

-- Zufälliges Loadout aus allen aktiven Waffen (LuckyLoadout, für beide Seiten gleich)
local function randomLoadout(): Types.Loadout
	local bySlot: { [string]: { string } } = { Primary = {}, Secondary = {}, Melee = {}, Utility = {} }
	local list = Config.Weapons and Config.Weapons.List
	if type(list) == "table" then
		for _, base in ipairs(list) do
			local def = Config.Weapon(base.Key)
			if def and def.Enabled ~= false and not def.AdminOnly and bySlot[def.Slot] then
				table.insert(bySlot[def.Slot], def.Key)
			end
		end
	end
	local out = table.clone(DEFAULT_LOADOUT)
	for _, slot in ipairs(SLOTS) do
		local options = bySlot[slot]
		if #options > 0 then
			out[slot] = options[rng:NextInteger(1, #options)]
		end
	end
	return out
end

local function loadoutFor(m: any, e: Entry): Types.Loadout?
	local rules = m.Rules
	if m.RoundLoadout then
		return table.clone(m.RoundLoadout)
	end
	if rules.ForcedLoadout then
		return table.clone(rules.ForcedLoadout)
	end
	if e.IsBot then
		return nil -- BotService wählt nach Stufe
	end
	local p = e.Player :: Player
	local ok, loadout = call("ShopService", "GetLoadout", p, rules)
	if ok and type(loadout) == "table" then
		return loadout
	end
	local default = Config.Weapons and Config.Weapons.DefaultLoadout
	return table.clone(if type(default) == "table" then default else DEFAULT_LOADOUT)
end

-- ---------------------------------------------------------------------
-- 4) ROSTER & COMBATANTS
-- ---------------------------------------------------------------------
local function entryByCombatant(m: any, c: Combatant?): Entry?
	if not c then
		return nil
	end
	return m.ById[c.Id]
end

local function liveEntries(m: any): { Entry }
	local list: { Entry } = {}
	for _, e in ipairs(m.Entries) do
		if not e.Removed and e.Combatant then
			table.insert(list, e)
		end
	end
	return list
end

local function teamColor(team: number, ffa: boolean): Color3
	if ffa then
		return Config.Colors.Enemy.Yellow
	end
	return if team == 2 then Config.Colors.TeamB else Config.Colors.TeamA
end

local function spawnFor(m: any, e: Entry): CFrame
	local arena = m.Arena
	local spawns = arena and arena.Spawns
	local list: { CFrame }? = nil
	if spawns then
		if m.Ffa then
			list = spawns.FFA
			if not list or #list == 0 then
				list = spawns.A
			end
		else
			list = if e.Team == 2 then spawns.B else spawns.A
		end
	end
	if list and #list > 0 then
		-- Index = Position im Team
		local idx = 0
		for _, other in ipairs(m.Entries) do
			if other.Team == e.Team and not other.Removed then
				idx += 1
				if other == e then
					break
				end
			end
		end
		if m.Ffa then
			idx = e.Key
		end
		return list[((math.max(1, idx) - 1) % #list) + 1]
	end
	local origin = if arena then arena.Origin else CFrame.new(0, 5, 0)
	return origin * CFrame.new(if e.Team == 2 then 20 else -20, 0, 0)
end

local function lifted(cf: CFrame): CFrame
	return cf + Vector3.new(0, MCFG.SpawnLift or 3, 0)
end

local function playerLevel(p: Player): (number, string)
	local okL, level = call("ProgressionService", "LevelOf", p)
	local okT, title = call("ProgressionService", "TitleOf", p)
	local lvl = if okL and type(level) == "number" then level else (tonumber(p:GetAttribute("Level")) or 1)
	local ttl = if okT and type(title) == "string" then title else tostring(p:GetAttribute("Title") or "")
	return lvl, ttl
end

local function newEntry(m: any, member: any, team: number): Entry?
	if #m.Entries >= MAX_ROSTER then
		return nil
	end
	local key = #m.Entries + 1
	local e: Entry
	if typeof(member) == "Instance" and member:IsA("Player") then
		local p = member :: Player
		local level, title = playerLevel(p)
		local okF, fin = call("ShopService", "Finisher", p)
		e = {
			Key = key,
			Player = p,
			IsBot = false,
			Difficulty = nil,
			Team = team,
			Name = p.DisplayName,
			Id = p.UserId,
			Combatant = nil,
			Level = level,
			Title = title,
			Finisher = if okF and type(fin) == "string" then fin else "F_Confetti",
			Removed = false,
			Left = false,
			AfkRemoved = false,
			Ready = false,
			LoadReady = false,
			AfkIdle = 0,
			AfkWarned = false,
			AfkPos = nil,
			AfkInput = 0,
			MultiCount = 0,
			MultiAt = 0,
			Stats = newStats(),
		}
		m.ByPlayer[p] = e
	else
		e = {
			Key = key,
			Player = nil,
			IsBot = true,
			Difficulty = if type(member) == "table" and type(member.Difficulty) == "string"
				then member.Difficulty
				else "Normal",
			Team = team,
			Name = "",
			Id = 0,
			Combatant = nil,
			Level = 0,
			Title = "",
			Finisher = "F_Confetti",
			Removed = false,
			Left = false,
			AfkRemoved = false,
			Ready = true,
			LoadReady = true,
			AfkIdle = 0,
			AfkWarned = false,
			AfkPos = nil,
			AfkInput = 0,
			MultiCount = 0,
			MultiAt = 0,
			Stats = newStats(),
		}
	end
	table.insert(m.Entries, e)
	return e
end

local function rosterFound(m: any): { any }
	local teams = {}
	local teamTotal = if m.Ffa then 1 else 2
	for t = 1, teamTotal do
		teams[t] = {}
	end
	for _, e in ipairs(m.Entries) do
		if not e.Removed then
			local t = if m.Ffa then 1 else e.Team
			table.insert(teams[t], {
				Slot = e.Key,
				Id = e.Id,
				Name = e.Name,
				IsBot = e.IsBot,
				Level = e.Level,
				Title = e.Title,
			})
		end
	end
	return teams
end

local function rosterStart(m: any): { any }
	local list = {}
	for _, e in ipairs(m.Entries) do
		if not e.Removed and (e.Combatant or not e.IsBot) then
			table.insert(list, {
				Slot = e.Key,
				Id = e.Id,
				Name = e.Name,
				Team = e.Team,
				IsBot = e.IsBot,
				Level = e.Level,
				Title = e.Title,
				Finisher = e.Finisher,
			})
		end
	end
	return list
end

local function setAllowance(p: Player, rules: any)
	call("AntiCheatService", "SetAllowance", p, {
		SpeedMult = rules and rules.SpeedMult or 1,
		VerticalMult = if rules and (rules.GravityLift or 0) > 0 then 2.5 else 1,
	})
end

-- Combatant für einen Eintrag anlegen und an seinen Spawn stellen (verankert)
local function spawnEntry(m: any, e: Entry): boolean
	if e.Combatant or e.Removed then
		return e.Combatant ~= nil
	end
	local spawnCf = spawnFor(m, e)
	local loadout = loadoutFor(m, e)
	if e.IsBot then
		local ok, c = call("BotService", "Spawn", e.Difficulty or "Normal", m.Ctx, e.Team, e.Key, loadout)
		if not ok or type(c) ~= "table" then
			return false
		end
		e.Combatant = c
		e.Id = c.Id
		e.Name = c.Name
		m.ById[c.Id] = e
		call("CharacterService", "Teleport", c, lifted(spawnCf))
		call("CharacterService", "Freeze", c, true)
		-- Tempo (Stufe × Mutator) setzt BotService.Spawn selbst
		call("BotService", "SetGoal", c, { Kind = "Idle" })
		return true
	end
	local p = e.Player :: Player
	local char = p.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local head = char and char:FindFirstChild("Head")
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not root or not head or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local ok, c = call("CombatService", "NewCombatant", {
		Kind = "Player",
		Player = p,
		Model = char,
		Ctx = m.Ctx,
		Team = e.Team,
		Slot = e.Key,
		Name = p.DisplayName,
		Loadout = loadout or table.clone(DEFAULT_LOADOUT),
		MaxHp = Config.Player.MaxHp,
	})
	if not ok or type(c) ~= "table" then
		return false
	end
	e.Combatant = c
	e.Id = c.Id
	m.ById[c.Id] = e
	call("CombatService", "Register", c)
	call("CharacterService", "Teleport", c, lifted(spawnCf))
	call("CharacterService", "Freeze", c, true)
	-- BaseSpeed (Walk × SpeedMult) und 3rd-Person-Waffen setzt CombatService.Register (B14.8)
	setAllowance(p, m.Rules)
	return true
end

-- Spieler zurück in die Lobby (oder an den Kronen-Rand), Combatant abmelden
local function returnPlayer(m: any, e: Entry, target: CFrame?)
	local c = e.Combatant
	local p = e.Player
	if c then
		if p and p.Parent == Players then
			local okSpawn, lobby = call("ArenaService", "LobbySpawn")
			local cf = target or (if okSpawn and typeof(lobby) == "CFrame" then lobby else CFrame.new(0, 5, 0))
			if c.Alive then
				call("CharacterService", "Freeze", c, false)
				call("CharacterService", "Teleport", c, lifted(cf))
			else
				call("CombatService", "Revive", c, cf)
				call("CharacterService", "Freeze", c, false)
			end
			call("CharacterService", "ClearGunVisuals", c)
		end
		call("CombatService", "Unregister", c)
		m.ById[c.Id] = nil
		e.Combatant = nil
	end
	if p then
		setAllowance(p, nil)
		if playerMatch[p] == m.Id then
			playerMatch[p] = nil
		end
	end
end

local function despawnBot(m: any, e: Entry)
	local c = e.Combatant
	if c then
		call("BotService", "Despawn", c)
		m.ById[c.Id] = nil
		e.Combatant = nil
	end
end

-- ---------------------------------------------------------------------
-- 5) API FÜR DIE REGELWERKE (m.Api)
-- ---------------------------------------------------------------------
local function aliveByTeam(m: any): { [number]: { Combatant } }
	local byTeam: { [number]: { Combatant } } = {}
	for _, e in ipairs(liveEntries(m)) do
		local c = e.Combatant :: Combatant
		if c.Alive then
			local list = byTeam[e.Team]
			if not list then
				list = {}
				byTeam[e.Team] = list
			end
			table.insert(list, c)
		end
	end
	return byTeam
end

local function roundDamage(m: any): { [number]: number }
	local ok, map = call("CombatService", "RoundDamage", m.Ctx)
	return if ok and type(map) == "table" then map else {}
end

local function inZone(m: any, pos: Vector3): boolean
	local zone = m.Arena and m.Arena.Zone
	if typeof(zone) ~= "Vector3" then
		return false
	end
	local radius = (m.Arena.ZoneRadius or MCFG.ZoneRadius or 8)
	local flat = Vector3.new(pos.X - zone.X, 0, pos.Z - zone.Z)
	return flat.Magnitude <= radius and math.abs(pos.Y - zone.Y) <= (MCFG.ZoneHeight or 10)
end

local function statsSnapshot(m: any): { [string]: any }
	local snap = {}
	for _, e in ipairs(m.Entries) do
		if e.Id ~= 0 then
			snap[tostring(e.Id)] = {
				K = e.Stats.Elims,
				D = e.Stats.Deaths,
				A = e.Stats.Assists,
				Dmg = math.floor(e.Stats.Damage + 0.5),
			}
		end
	end
	return snap
end

local function spawnPendingBots(m: any)
	local t = now()
	for _, pending in ipairs(m.PendingBots) do
		if not pending.Done then
			local teamEmpty = true
			for _, e in ipairs(m.Entries) do
				if e.Team == pending.Team and not e.Removed then
					teamEmpty = false
					break
				end
			end
			if teamEmpty or t >= pending.At then
				local okBudget, budget = call("BotService", "Budget")
				if not okBudget or (type(budget) == "number" and budget > 0) then
					local e = newEntry(m, { Bot = true, Difficulty = pending.Difficulty }, pending.Team)
					if e and spawnEntry(m, e) then
						pending.Done = true
						if m.Ffa then
							Respawn.AddCombatant(m, e.Combatant)
						end
					elseif e then
						e.Removed = true
					end
				end
			end
		end
	end
	local open = {}
	for _, pending in ipairs(m.PendingBots) do
		if not pending.Done then
			table.insert(open, pending)
		end
	end
	m.PendingBots = open
end

local function makeApi(m: any): any
	local api = {}

	function api.Now(): number
		return now()
	end

	function api.Send(kind: string, data: any)
		sendMembers(m, kind, data)
	end

	function api.BeginRound(suddenDeath: boolean)
		call("CombatService", "ResetRound", m.Ctx)
		call("ProjectileService", "ClearCtx", m.Ctx)
		call("BotService", "OnRoundStart", m.Ctx)
		spawnPendingBots(m)
		m.RoundLoadout = if m.Rules.RandomLoadout then randomLoadout() else nil
		local missShots = (Config.Bots and Config.Bots.RookieMissShots) or 2
		for _, e in ipairs(liveEntries(m)) do
			local c = e.Combatant :: Combatant
			local cf = spawnFor(m, e)
			if m.RoundLoadout then
				call("WeaponService", "SetLoadout", c, table.clone(m.RoundLoadout))
			end
			call("CombatService", "Revive", c, cf)
			call("CharacterService", "Freeze", c, true) -- Revive setzt auch Munition zurück
			if suddenDeath then
				-- Sudden Death: alle starten mit 50 HP (Server-Wert + Attribut für die Anzeige)
				local hp = math.min(c.MaxHp, MCFG.SuddenDeathHp or 50)
				c.Hp = hp
				if c.Model then
					c.Model:SetAttribute("Hp", hp)
				end
			end
			e.Ready = e.IsBot
			e.MultiCount = 0
			e.AfkPos = nil -- Teleport an den Spawn zählt nicht als Bewegung
			if e.IsBot then
				call("BotService", "SetGoal", c, { Kind = "Idle" })
				if e.Difficulty == "Rookie" then
					call("BotService", "SetHandicap", c, missShots)
				end
			end
		end
	end

	function api.GoLive()
		m.LiveSince = now()
		for _, e in ipairs(liveEntries(m)) do
			local c = e.Combatant :: Combatant
			call("CharacterService", "Freeze", c, false)
			if e.IsBot then
				call("BotService", "SetGoal", c, { Kind = "Engage" })
			end
		end
	end

	function api.StartOvertime(endsAt: number)
		local zone = m.Arena and m.Arena.Zone or Vector3.zero
		local radius = m.Arena and m.Arena.ZoneRadius or MCFG.ZoneRadius or 8
		sendMembers(m, "Overtime", { EndsAt = endsAt, Zone = zone, Radius = radius })
		for _, e in ipairs(liveEntries(m)) do
			if e.IsBot then
				call("BotService", "SetGoal", e.Combatant, { Kind = "Zone", Pos = zone })
			end
		end
	end

	function api.AliveByTeam(): { [number]: { Combatant } }
		return aliveByTeam(m)
	end

	function api.TeamHp(team: number): number
		local ok, hp = call("CombatService", "TeamHp", m.Ctx, team)
		if ok and type(hp) == "number" then
			return hp
		end
		local sum = 0
		for _, c in ipairs(aliveByTeam(m)[team] or {}) do
			sum += c.Hp
		end
		return sum
	end

	function api.TeamDamage(team: number): number
		local dmg = roundDamage(m)
		local sum = 0
		for _, e in ipairs(m.Entries) do
			if e.Team == team and e.Id ~= 0 then
				sum += dmg[e.Id] or 0
			end
		end
		return sum
	end

	function api.ZonePresence(): { [number]: number }
		local presence: { [number]: number } = {}
		for team, list in pairs(aliveByTeam(m)) do
			for _, c in ipairs(list) do
				if c.Root and inZone(m, c.Root.Position) then
					presence[team] = (presence[team] or 0) + 1
				end
			end
		end
		return presence
	end

	function api.AllReady(): boolean
		local any = false
		for _, e in ipairs(liveEntries(m)) do
			if not e.IsBot then
				any = true
				if not e.Ready then
					return false
				end
			end
		end
		return any
	end

	function api.ZoneUpdate(team: number, progress: number, contested: boolean)
		sendMembers(m, "Zone", { Team = team, Progress = progress, Contested = contested })
	end

	function api.AntiCamp(untilT: number)
		sendMembers(m, "AntiCamp", { Until = untilT })
	end

	function api.RoundEnded(info: any)
		local dmg = roundDamage(m)
		local mvpId: number? = nil
		local best = 0
		for id, value in pairs(dmg) do
			if m.ById[id] and value > best then
				best, mvpId = value, id
			end
		end
		local winner = info.Winner
		for _, e in ipairs(m.Entries) do
			if not e.Removed and e.Team == winner and info.Flawless then
				e.Stats.Flawless += 1
			end
		end
		local clutchData = nil
		if info.Clutch then
			local ce = m.ById[info.Clutch.Id]
			if ce then
				ce.Stats.Clutches += 1
				local xp = (SKILL.ClutchXpPerEnemy or 15) * info.Clutch.Vs
				local granted = 0
				if ce.Player then
					local ok, given = call("ProgressionService", "AddXp", ce.Player, xp, "Clutch")
					granted = if ok and type(given) == "number" then given else 0
				end
				clutchData = { Id = info.Clutch.Id, Vs = info.Clutch.Vs, Xp = granted }
			end
		end
		local aceData = nil
		if info.AceId then
			local ae = m.ById[info.AceId]
			if ae then
				ae.Stats.Aces += 1
				local granted = 0
				if ae.Player and (SKILL.AceXp or 0) > 0 then
					local ok, given = call("ProgressionService", "AddXp", ae.Player, SKILL.AceXp, "Ace")
					granted = if ok and type(given) == "number" then given else 0
				end
				aceData = { Id = info.AceId, Xp = granted }
			end
		end
		if info.Reason == "Zone" and winner > 0 then
			for _, c in ipairs(aliveByTeam(m)[winner] or {}) do
				local e = m.ById[c.Id]
				if e and c.Root and inZone(m, c.Root.Position) then
					e.Stats.OvertimeCaps += 1
				end
			end
		end
		for _, e in ipairs(liveEntries(m)) do
			if e.IsBot then
				call("BotService", "SetGoal", e.Combatant, { Kind = "Idle" })
			end
		end
		sendMembers(m, "RoundEnd", {
			Winner = winner,
			Reason = info.Reason,
			Score = table.clone(m.Score),
			Mvp = mvpId,
			Banners = info.Banners,
			Clutch = clutchData,
			Ace = aceData,
			Stats = statsSnapshot(m),
		})
	end

	-- Respawn-Regelwerk (FFA)
	function api.Combatants(): { Combatant }
		local list: { Combatant } = {}
		for _, e in ipairs(liveEntries(m)) do
			table.insert(list, e.Combatant :: Combatant)
		end
		return list
	end

	function api.Respawn(c: Combatant)
		local e = m.ById[c.Id]
		if not e then
			return
		end
		local cf = MatchService._FfaSpawn(m, c)
		call("CombatService", "Revive", c, cf, Config.Player.SpawnShield or 1.5)
		call("CharacterService", "Freeze", c, false)
		call("WeaponService", "ResetForRound", c)
		if e.IsBot then
			call("BotService", "SetGoal", c, { Kind = "Engage" })
		end
	end

	function api.Heal(c: Combatant, amount: number)
		call("CombatService", "Heal", c, amount)
	end

	function api.TeamOf(id: number): number
		local e = m.ById[id]
		return if e then e.Team else 0
	end

	function api.DamageTable(): { [number]: number }
		local out: { [number]: number } = {}
		for _, e in ipairs(m.Entries) do
			if e.Id ~= 0 then
				out[e.Id] = e.Stats.Damage
			end
		end
		return out
	end

	return api
end

-- FFA-Respawn: beste von 8 Kandidaten nach minDist − 40 × (Gegner mit Sicht)
function MatchService._FfaSpawn(m: any, c: Combatant): CFrame
	local arena = m.Arena
	local list: { CFrame } = {}
	if arena and arena.Spawns then
		for _, cf in ipairs(arena.Spawns.FFA or {}) do
			table.insert(list, cf)
		end
		if #list == 0 then
			for _, cf in ipairs(arena.Spawns.A or {}) do
				table.insert(list, cf)
			end
			for _, cf in ipairs(arena.Spawns.B or {}) do
				table.insert(list, cf)
			end
		end
	end
	if #list == 0 then
		return (if arena then arena.Origin else CFrame.new(0, 5, 0)) + Vector3.new(0, 2, 0)
	end
	shuffle(list)
	local enemies: { Combatant } = {}
	for _, e in ipairs(liveEntries(m)) do
		local other = e.Combatant :: Combatant
		if other ~= c and other.Alive and other.Root and other.Head then
			table.insert(enemies, other)
		end
	end
	local params = arena and arena.MapParams
	local bestCf, bestScore = list[1], -math.huge
	for i = 1, math.min(#list, MCFG.FfaSpawnCandidates or 8) do
		local cf = list[i]
		local point = cf.Position + Vector3.new(0, 3, 0)
		local minDist, visible = 999, 0
		for _, enemy in ipairs(enemies) do
			local headPos = enemy.Head.Position
			local dist = (enemy.Root.Position - point).Magnitude
			if dist < minDist then
				minDist = dist
			end
			if params then
				local dir = point - headPos
				local hit = workspace:Raycast(headPos, dir, params)
				if hit == nil then
					visible += 1
				end
			end
		end
		local score = Respawn.SpawnScore(minDist, visible, MCFG.FfaSightPenalty or 40)
		if score > bestScore then
			bestScore, bestCf = score, cf
		end
	end
	return bestCf
end

-- ---------------------------------------------------------------------
-- 6) ERGEBNIS
-- ---------------------------------------------------------------------
local function bountyOf(p: Player): number
	local ok, value = call("CommunityService", "BountyOf", p)
	return if ok and type(value) == "number" then value else 0
end

local function playerResult(m: any, e: Entry, winner: number): Types.PlayerResult
	local s = e.Stats
	local draw = winner == 0
	local won = not draw and e.Team == winner and not e.Left and not e.AfkRemoved
	local roundsWon = if m.Ffa then 0 else (m.Score[e.Team] or 0)
	return {
		Team = e.Team,
		Won = won,
		Draw = draw and not e.Left and not e.AfkRemoved,
		Left = e.Left,
		AfkRemoved = e.AfkRemoved,
		RoundsWon = roundsWon,
		Elims = s.Elims,
		PvpElims = s.PvpElims,
		Headshots = s.Headshots,
		MeleeElims = s.MeleeElims,
		Assists = s.Assists,
		Damage = math.floor(s.Damage + 0.5),
		Deaths = s.Deaths,
		Mvp = m.MvpId ~= nil and m.MvpId == e.Id,
		Flawless = s.Flawless,
		Clutches = s.Clutches,
		Aces = s.Aces,
		OvertimeCaps = s.OvertimeCaps,
		CrownDefences = 0,
		CrownVsHuman = 0,
		BountyClaimed = 0,
		WeaponKills = table.clone(s.WeaponKills),
		WeaponUsed = table.clone(s.WeaponUsed),
		ShotsFired = s.ShotsFired,
		ShotsHit = s.ShotsHit,
		Comeback = m.Comeback ~= nil and m.Comeback == e.Team and won,
	}
end

local function hasBots(m: any): boolean
	for _, e in ipairs(m.Entries) do
		if e.IsBot then
			return true
		end
	end
	return false
end

local function matchResult(m: any, winner: number, perPlayer: { [Player]: Types.PlayerResult }): Types.MatchResult
	return {
		MatchId = m.Id,
		Mode = m.Mode,
		Map = m.Map or "",
		Winner = winner,
		Draw = winner == 0,
		Tainted = m.Tainted == true,
		VsBots = hasBots(m),
		Practice = m.Mode == "Practice",
		Tutorial = m.Tutorial == true,
		Duration = math.max(0, now() - (m.StartedAt or now())),
		PerPlayer = perPlayer,
	}
end

local function fireMatchEnd(result: Types.MatchResult)
	for _, cb in ipairs(endCallbacks) do
		-- task.spawn: läuft sofort bis zum ersten Yield, ein Fehler stoppt die anderen nicht
		task.spawn(function()
			local ok, err = pcall(cb, result)
			if not ok then
				logError("OnMatchEnd-Callback", err)
			end
		end)
	end
end

local function mvpOf(m: any): number?
	local bestId, bestScore = nil, -1
	for _, e in ipairs(m.Entries) do
		if e.Id ~= 0 then
			local s = e.Stats
			local score = s.Elims * 2 + s.Assists + s.Damage / 100
			if score > bestScore then
				bestScore, bestId = score, e.Id
			end
		end
	end
	return bestId
end

local function mostUsedWeapon(e: Entry): string?
	local best, bestKey = -1, nil
	for key, kills in pairs(e.Stats.WeaponKills) do
		if kills > best then
			best, bestKey = kills, key
		end
	end
	if bestKey then
		return bestKey
	end
	for key, shots in pairs(e.Stats.WeaponShots) do
		if shots > best then
			best, bestKey = shots, key
		end
	end
	if bestKey then
		return bestKey
	end
	local c = e.Combatant
	return if c and c.Loadout then c.Loadout.Primary else nil
end

-- Schnappschuss der (von WP8/WP9 gepflegten) Daten vor/nach OnMatchEnd für die Ergebnis-Balken
local function snapshot(p: Player, weaponKey: string?): any
	local data = dataOf(p)
	if not data then
		return nil
	end
	local quests: { [string]: { P: number, Goal: number } } = {}
	local q = data.Quests
	if type(q) == "table" then
		for _, listName in ipairs({ "Daily", "Weekly" }) do
			local list = q[listName]
			if type(list) == "table" then
				for _, quest in ipairs(list) do
					if type(quest) == "table" and type(quest.Id) == "string" then
						quests[quest.Id] = { P = tonumber(quest.P) or 0, Goal = tonumber(quest.Goal) or 1 }
					end
				end
			end
		end
	end
	local mastery = 0
	if weaponKey and type(data.Weapons) == "table" and type(data.Weapons.Mastery) == "table" then
		local entry = data.Weapons.Mastery[weaponKey]
		mastery = if type(entry) == "table" then tonumber(entry.K) or 0 else 0
	end
	local stats = type(data.Stats) == "table" and data.Stats or {}
	return {
		TotalXP = tonumber(data.TotalXP) or 0,
		Level = tonumber(data.Level) or 1,
		XP = tonumber(data.XP) or 0,
		Coins = tonumber(data.Coins) or 0,
		PassXp = if type(data.Pass) == "table" then tonumber(data.Pass.XP) or 0 else 0,
		Mastery = mastery,
		Quests = quests,
		Wins = tonumber(stats.Wins) or 0,
	}
end

-- Werte aus der Fortschritts-Auswertung (WP8) bevorzugen, sonst Vorher/Nachher-Vergleich der Daten
local SUMMARY_KEYS = {
	"XpGain",
	"Level",
	"XpInLevel",
	"XpNext",
	"Coins",
	"MasteryWeapon",
	"MasteryBefore",
	"MasteryAfter",
	"PassXpBefore",
	"PassXpAfter",
}

local function buildMe(m: any, e: Entry, before: any, after: any, r: Types.PlayerResult, weaponKey: string?): any
	local s = e.Stats
	local stats = {
		K = s.Elims,
		D = s.Deaths,
		A = s.Assists,
		Dmg = math.floor(s.Damage + 0.5),
		Acc = if s.ShotsFired > 0 then s.ShotsHit / s.ShotsFired else 0,
		Head = s.Headshots,
		Shots = s.ShotsFired,
		Score = if m.Ffa and m.Scores then (m.Scores[e.Id] or 0) else nil,
	}
	local me: { [string]: any } = {
		XpGain = 0,
		Level = 1,
		XpInLevel = 0,
		XpNext = 0,
		Coins = 0,
		MasteryWeapon = weaponKey,
		MasteryBefore = 0,
		MasteryAfter = 0,
		PassXpBefore = 0,
		PassXpAfter = 0,
		QuestTicks = {},
		Mvp = r.Mvp,
		Stats = stats,
	}
	if before and after then
		local level, inLevel = after.Level, after.XP
		if ProgressMath and type(ProgressMath.LevelFromTotal) == "function" then
			local ok, l, x = pcall(ProgressMath.LevelFromTotal, after.TotalXP)
			if ok and type(l) == "number" and type(x) == "number" then
				level, inLevel = l, x
			end
		end
		local xpNext = 0
		if ProgressMath and type(ProgressMath.XpToNext) == "function" then
			local ok, n = pcall(ProgressMath.XpToNext, level)
			xpNext = if ok and type(n) == "number" then n else 0
		end
		local ticks = {}
		for id, q in pairs(after.Quests) do
			local old = before.Quests[id]
			if old == nil or q.P > old.P then
				table.insert(ticks, { Id = id, P = q.P, Goal = q.Goal })
			end
		end
		me.XpGain = math.max(0, after.TotalXP - before.TotalXP)
		me.Level = level
		me.XpInLevel = inLevel
		me.XpNext = xpNext
		me.Coins = math.max(0, after.Coins - before.Coins)
		me.MasteryBefore = before.Mastery
		me.MasteryAfter = after.Mastery
		me.PassXpBefore = before.PassXp
		me.PassXpAfter = after.PassXp
		me.QuestTicks = ticks
	end
	local p = e.Player
	if p then
		local ok, summary = call("ProgressionService", "MatchSummary", p, m.Id)
		if ok and type(summary) == "table" then
			for _, key in ipairs(SUMMARY_KEYS) do
				local value = summary[key]
				if value ~= nil and value ~= "" then
					me[key] = value
				end
			end
		end
	end
	return me
end

-- Ergebnis für einen einzelnen Leaver/AFK sofort melden (Verlierer-Wertung, B5)
local function reportSingle(m: any, e: Entry)
	local p = e.Player
	if not p or m.Phase == "Vote" or m.Phase == "Load" or m.ResultSent then
		return
	end
	local winner = if m.Ffa then 0 else otherTeam(e.Team)
	local r = playerResult(m, e, winner)
	r.Won = false
	r.Draw = false
	local result = matchResult(m, winner, { [p] = r })
	result.Draw = false
	fireMatchEnd(result)
	e.Reported = true
end

-- ---------------------------------------------------------------------
-- 7) LEBENSZYKLUS
-- ---------------------------------------------------------------------
local function setPhase(m: any, phase: string, duration: number?)
	m.Phase = phase
	m.PhaseStart = now()
	m.PhaseEnds = if duration then now() + duration else math.huge
end

local function ruleset(m: any): any
	return if m.Ffa then Respawn else Rounds
end

local function humansLeft(m: any): number
	return #humanEntries(m)
end

local function teardown(m: any, keepPlayers: boolean)
	-- Combatants abmelden (Spieler zurück in die Lobby, außer bei Rematch/Krone)
	for _, e in ipairs(m.Entries) do
		if e.IsBot then
			despawnBot(m, e)
		elseif e.Combatant then
			if keepPlayers then
				local c = e.Combatant :: Combatant
				if not c.Alive then
					call("CombatService", "Revive", c, spawnFor(m, e))
				end
				call("CharacterService", "ClearGunVisuals", c)
				call("CombatService", "Unregister", c)
				m.ById[c.Id] = nil
				e.Combatant = nil
			else
				returnPlayer(m, e, nil)
			end
		end
	end
	if m.Ctx then
		call("ProjectileService", "ClearCtx", m.Ctx)
		call("CombatService", "UnregisterContext", m.Ctx)
		matchByCtx[m.Ctx] = nil
	end
end

local function closeMatch(m: any, reason: string)
	if m.Phase == "Closed" then
		return
	end
	local crown = m.Mode == "Crown"
	local crownWinner: Player? = nil
	local crownLosers: { Player } = {}
	if crown and m.MatchWinner ~= nil then
		for _, e in ipairs(m.Entries) do
			if e.Player and not e.Removed then
				if m.MatchWinner > 0 and e.Team == m.MatchWinner then
					crownWinner = e.Player
				else
					table.insert(crownLosers, e.Player :: Player)
				end
			end
		end
	end
	local requeue: { Player } = {}
	local noWinner = m.MatchWinner == nil or m.MatchWinner == 0
	for _, e in ipairs(m.Entries) do
		local p = e.Player
		if p and not e.Removed then
			local stays = crown
				and (
					(crownWinner ~= nil and p == crownWinner) or (noWinner and m.CrownKing ~= nil and p == m.CrownKing)
				)
			if stays then
				-- König bleibt in der Grube (B4)
				local c = e.Combatant
				if c then
					if not c.Alive then
						call("CombatService", "Revive", c, spawnFor(m, e))
					end
					call("CharacterService", "Freeze", c, false)
					call("CharacterService", "ClearGunVisuals", c)
					call("CombatService", "Unregister", c)
					m.ById[c.Id] = nil
					e.Combatant = nil
				end
				setAllowance(p, nil)
				playerMatch[p] = nil
			elseif crown then
				local z = if rng:NextNumber() < 0.5 then -(MCFG.CrownEdgeZ or 16) else (MCFG.CrownEdgeZ or 16)
				local edge = CFrame.lookAt(
					Vector3.new(MCFG.CrownEdgeX or 60, 0, z),
					Vector3.new((MCFG.CrownEdgeX or 60) - 10, 0, z)
				)
				returnPlayer(m, e, edge)
			else
				returnPlayer(m, e, nil)
			end
			sendTo(p, "Closed", {})
			if reason ~= "Abandoned" and autoRequeue[p] and not e.AfkRemoved and m.Mode ~= "Crown" then
				table.insert(requeue, p)
			end
		end
	end
	teardown(m, false)
	if m.Arena and not crown and not m.KeepArena then
		call("ArenaService", "Release", m.Arena)
	end
	m.Phase = "Closed"
	matches[m.Id] = nil
	for p, id in pairs(playerMatch) do
		if id == m.Id then
			playerMatch[p] = nil
		end
	end
	if crown then
		call("QueueService", "CrownMatchEnded", m.Id, crownWinner, crownLosers, m.MatchWinner or 0, m.CrownKing)
	end
	-- Auto-Requeue (nach dem Aufräumen, damit der Spieler frei ist)
	local mode = m.Mode
	if mode == "Practice" or mode == "Crown" then
		return
	end
	for _, p in ipairs(requeue) do
		task.defer(function()
			if p.Parent == Players and playerMatch[p] == nil then
				call("QueueService", "Join", p, mode, nil)
			end
		end)
	end
end

local function finishMatch(m: any, winner: number)
	if m.Phase == "MatchEnd" or m.Phase == "Closed" then
		return
	end
	m.MatchWinner = winner
	local resultsTime = if m.Mode == "Crown" then (MCFG.CrownResults or 4) else (MCFG.Results or 10)
	setPhase(m, "MatchEnd", resultsTime)
	m.RematchVotes = {}
	m.MvpId = mvpOf(m)
	-- alle anhalten
	for _, e in ipairs(liveEntries(m)) do
		local c = e.Combatant :: Combatant
		if c.Alive then
			call("CharacterService", "Freeze", c, true)
		end
		if e.IsBot then
			call("BotService", "SetGoal", c, { Kind = "Idle" })
		end
	end

	-- Ergebnis zusammenbauen
	local perPlayer: { [Player]: Types.PlayerResult } = {}
	local entriesOf: { [Player]: Entry } = {}
	local weapons: { [Player]: string? } = {}
	local before: { [Player]: any } = {}
	local loserBounty = 0
	if not m.Tainted and not hasBots(m) and winner > 0 then
		for _, e in ipairs(humanEntries(m)) do
			if e.Team ~= winner then
				loserBounty += bountyOf(e.Player :: Player)
			end
		end
	end
	for _, e in ipairs(humanEntries(m)) do
		if not e.Reported then
			local p = e.Player :: Player
			local r = playerResult(m, e, winner)
			if m.Mode == "Crown" and r.Won and m.CrownKing == p then
				r.CrownDefences = 1
				local opponentHuman = false
				for _, other in ipairs(m.Entries) do
					if other.Team ~= e.Team and not other.IsBot then
						opponentHuman = true
					end
				end
				r.CrownVsHuman = if opponentHuman then 1 else 0
			end
			if r.Won and loserBounty > 0 then
				r.BountyClaimed = loserBounty
			end
			perPlayer[p] = r
			entriesOf[p] = e
			weapons[p] = mostUsedWeapon(e)
			before[p] = snapshot(p, weapons[p])
		end
	end
	local result = matchResult(m, winner, perPlayer)
	m.ResultSent = true
	fireMatchEnd(result)

	-- Ergebnis-Bildschirm pro Spieler (eigener Teil)
	for p, r in pairs(perPlayer) do
		local e = entriesOf[p]
		local after = snapshot(p, weapons[p])
		local me = buildMe(m, e, before[p], after, r, weapons[p])
		local offer: string? = nil
		local data = dataOf(p)
		if r.Won and not m.Tutorial and m.Mode ~= "Practice" and data and type(data.Flags) == "table" then
			if data.Flags.FirstRealWin ~= true then
				data.Flags.FirstRealWin = true
				call("PlayerStateService", "MarkDirty", p, "Flags")
				local ok, shown = call("MonetizationService", "TryOffer", p, "StarterPack")
				if ok and shown == true then
					offer = "StarterPack"
				end
			end
		end
		if m.Tutorial then
			funnel(p, 6, "TutorialDone")
			if data and type(data.Flags) == "table" and data.Flags.Tutorial ~= true then
				data.Flags.Tutorial = true
				call("PlayerStateService", "MarkDirty", p, "Flags")
			end
		end
		if r.Won and before[p] and before[p].Wins == 0 then
			funnel(p, 7, "FirstWin")
		end
		sendTo(p, "End", {
			Winner = winner,
			Draw = winner == 0,
			Tainted = m.Tainted == true,
			Me = me,
			Offer = offer,
			MyTeam = e.Team,
			Mode = m.Mode,
			Rematch = m.Mode ~= "Crown",
			Stats = statsSnapshot(m),
		})
	end
end

-- Start-Paket (pro Spieler eigenes Team)
local function sendStart(m: any)
	local roster = rosterStart(m)
	local arena = m.Arena
	for _, e in ipairs(humanEntries(m)) do
		sendTo(e.Player :: Player, "Start", {
			MatchId = m.Id,
			Slot = arena and arena.Slot or 0,
			Map = m.Map,
			Mood = m.Mood,
			BuildId = arena and arena.BuildId or 0,
			Origin = arena and arena.Origin.Position or Vector3.zero,
			Mode = m.Mode,
			Mutator = m.Mutator,
			RoundsToWin = m.RoundsToWin,
			MyTeam = e.Team,
			MyId = e.Id,
			Roster = roster,
			Tutorial = m.Tutorial == true,
			Tainted = m.Tainted == true,
		})
	end
end

local function registerContext(m: any)
	local id = m.Id
	m.Ctx = "M" .. tostring(id)
	matchByCtx[m.Ctx] = m
	call("CombatService", "RegisterContext", {
		Ctx = m.Ctx,
		Arena = m.Arena,
		Rules = m.Rules,
		Recipients = function()
			return MatchService.Recipients(id)
		end,
		MatchId = id,
	})
end

local function beginIntro(m: any)
	setPhase(m, "Intro", MCFG.IntroSeconds or 2)
	for _, e in ipairs(humanEntries(m)) do
		local enemies = {}
		for _, other in ipairs(liveEntries(m)) do
			if other.Team ~= e.Team then
				local c = other.Combatant :: Combatant
				local lo = c.Loadout or DEFAULT_LOADOUT
				table.insert(enemies, {
					Slot = other.Key,
					P = lo.Primary,
					S = lo.Secondary,
					M = lo.Melee,
					U = lo.Utility,
				})
			end
		end
		sendTo(e.Player :: Player, "Intro", { EndsAt = m.PhaseEnds, Enemies = enemies, Tainted = m.Tainted == true })
	end
end

local function startRuleset(m: any)
	m.StartedAt = m.StartedAt or now()
	ruleset(m).Start(m)
end

-- Arena da: Kontext registrieren, alle Combatants an die Spawns, Start senden
local function setupArena(m: any)
	registerContext(m)
	rememberMap(m.Mode, m.Map)
	for _, e in ipairs(m.Entries) do
		if not e.Removed then
			if not spawnEntry(m, e) then
				e.PendingSpawn = true
			end
		end
	end
	-- Bots, die nicht spawnen konnten (Budget), fallen weg
	for _, e in ipairs(m.Entries) do
		if e.IsBot and e.PendingSpawn and not e.Combatant then
			e.Removed = true
		end
	end
	sendStart(m)
end

local function beginLoad(m: any)
	setPhase(m, "Load", MCFG.LoadTimeout or 4)
	m.ArenaWaitUntil = now() + (MCFG.ArenaWait or 10)
	if m.Mode == "Crown" then
		local ok, arena = call("ArenaService", "Crown")
		if ok and type(arena) == "table" then
			m.Arena = arena
		end
	elseif not m.Arena then
		local ok, arena = call("ArenaService", "Acquire", m.Map, m.Mood)
		if ok and type(arena) == "table" then
			m.Arena = arena
		end
	end
	if m.Arena then
		setupArena(m)
	else
		notifyMembers(m, "match.arenasFull", nil, "Info")
	end
end

local function cancelMatch(m: any, key: string?)
	if key then
		notifyMembers(m, key, nil, "Error")
	end
	closeMatch(m, "Abandoned")
end

local function resolveVote(m: any)
	local counts = { 0, 0, 0, 0 }
	for _, idx in pairs(m.Votes) do
		counts[idx] += 1
	end
	local best, tied = -1, {}
	for idx = 1, RANDOM_VOTE do
		if idx == RANDOM_VOTE or m.VoteOptions[idx] then
			if counts[idx] > best then
				best, tied = counts[idx], { idx }
			elseif counts[idx] == best then
				table.insert(tied, idx)
			end
		end
	end
	local pick = tied[rng:NextInteger(1, #tied)]
	if pick == RANDOM_VOTE or not m.VoteOptions[pick] then
		local pool = if #m.VoteMaps > 0 then m.VoteMaps else {}
		if #pool == 0 then
			for _, opt in ipairs(m.VoteOptions) do
				table.insert(pool, opt.Map)
			end
		end
		local map = pool[rng:NextInteger(1, #pool)]
		m.Map = map
		m.Mood = pickMood(map)
	else
		m.Map = m.VoteOptions[pick].Map
		m.Mood = m.VoteOptions[pick].Mood
	end
end

local function sendVoteCounts(m: any)
	local counts = { 0, 0, 0, 0 }
	for _, idx in pairs(m.Votes) do
		counts[idx] += 1
	end
	sendMembers(m, "Vote", { Counts = counts })
end

-- ---------------------------------------------------------------------
-- 8) ENTFERNEN (Verlassen, AFK, Pad verlassen)
-- ---------------------------------------------------------------------
-- Mitglieder (Menschen + Bots) eines Teams, die noch im Match sind
local function teamMembers(m: any, team: number): number
	local n = 0
	for _, e in ipairs(m.Entries) do
		if e.Team == team and not e.Removed then
			n += 1
		end
	end
	return n
end

local function removeEntry(m: any, e: Entry, reason: string)
	if e.Removed then
		return
	end
	local p = e.Player
	local t = now()
	local inGame = p ~= nil and p.Parent == Players and not leaving[p]
	local afterVote = m.Phase ~= "Vote"
	local matchRunning = m.Phase ~= "MatchEnd" and m.Phase ~= "Closed"
	e.Left = reason == "Left" and matchRunning and afterVote
	e.AfkRemoved = reason == "Afk"
	if (e.Left or e.AfkRemoved) and matchRunning then
		reportSingle(m, e)
	end
	if e.Combatant then
		if m.Ffa then
			Respawn.RemoveCombatant(m, e.Id)
		end
		if inGame then
			returnPlayer(m, e, nil)
		else
			local c = e.Combatant :: Combatant
			call("CombatService", "Unregister", c)
			m.ById[c.Id] = nil
			e.Combatant = nil
		end
	end
	e.Removed = true
	if p then
		m.ByPlayer[p] = nil
		if playerMatch[p] == m.Id then
			playerMatch[p] = nil
		end
		if inGame then
			sendTo(p, "Closed", {})
		end
		if e.Left then
			call("QueueService", "LockPads", p.UserId, MCFG.LeaverCooldown or 60)
			if inGame then
				notify(p, "match.leftPenalty", { MCFG.LeaverCooldown or 60 }, "Alarm")
			end
		elseif e.AfkRemoved and inGame then
			autoRequeue[p] = false
			notify(p, "match.afkKicked", nil, "Alarm")
		end
	end
	if matchRunning then
		sendMembers(m, "Left", { Id = e.Id })
		notifyMembers(m, "match.playerLeft", { e.Name }, "Info")
	end
	if not matchRunning then
		if humansLeft(m) == 0 then
			closeMatch(m, "Abandoned")
		end
		return
	end
	if humansLeft(m) == 0 then
		closeMatch(m, "Abandoned")
		return
	end
	-- Ersatz
	if m.Phase == "Vote" then
		-- vor dem Laden: sofort ein Bot an seine Stelle
		newEntry(m, { Bot = true, Difficulty = m.BotDifficulty }, e.Team)
		return
	end
	if m.Ffa then
		return -- FFA füllt selbst auf
	end
	if m.TeamSize <= 1 then
		-- 1v1: Gegner gewinnt voll (Aufgabe)
		if teamMembers(m, e.Team) == 0 then
			local winner = otherTeam(e.Team)
			for _, other in ipairs(humanEntries(m)) do
				if other.Team == winner then
					notify(other.Player :: Player, "match.forfeitWin", nil, "Success")
				end
			end
			if RULESET_PHASES[m.Phase] then
				Rounds.Forfeit(m, winner)
			else
				finishMatch(m, winner)
			end
		end
		return
	end
	-- Team-Modi: Bot ersetzt nach 10 s (AFK sofort) – er steigt zur nächsten Runde ein
	local delay = if reason == "Afk" then 0 else (MCFG.LeaverBotDelay or 10)
	table.insert(m.PendingBots, { Team = e.Team, Difficulty = m.BotDifficulty, At = t + delay, Done = false })
	notifyMembers(m, "match.botReplaced", { e.Name }, "Info")
end

function MatchService.Leave(p: Player, reason: string): boolean
	local id = playerMatch[p]
	local m = id and matches[id]
	local e = m and m.ByPlayer[p]
	if not m or not e then
		return false
	end
	if reason == "Done" or m.Phase == "MatchEnd" then
		-- Ergebnis gesehen -> sofort zurück in die Lobby, ohne Strafe
		if m.Mode == "Crown" then
			return true -- Krone: König bleibt bis zum Schließen
		end
		returnPlayer(m, e, nil)
		e.Removed = true
		m.ByPlayer[p] = nil
		sendTo(p, "Closed", {})
		if humansLeft(m) == 0 then
			closeMatch(m, "Done")
		end
		return true
	end
	removeEntry(m, e, reason)
	return true
end

-- ---------------------------------------------------------------------
-- 9) ÖFFENTLICHE API
-- ---------------------------------------------------------------------
local function pendingReservations(): number
	local n = 0
	for _, m in pairs(matches) do
		if m.Mode ~= "Crown" and not m.Arena and (m.Phase == "Vote" or m.Phase == "Load") then
			n += 1
		end
	end
	return n
end

function MatchService.CanHost(modeKey: string): boolean
	if modeKey == "Crown" then
		return true
	end
	local count = 0
	for _ in pairs(matches) do
		count += 1
	end
	if count >= MAX_MATCHES then
		return false
	end
	local ok, free = call("ArenaService", "FreeSlots")
	if not ok or type(free) ~= "number" then
		return false
	end
	return free - pendingReservations() > 0
end

function MatchService.Create(spec: Types.MatchSpec): number?
	if type(spec) ~= "table" or type(spec.Mode) ~= "string" then
		return nil
	end
	local def = modeDef(spec.Mode)
	if not def or type(spec.Teams) ~= "table" then
		return nil
	end
	local ffa = def.Ruleset == "Respawn"
	local tutorial = spec.Tutorial == true
	if spec.Mode == "Crown" then
		-- der Crown Ring ist EINE feste Arena: nie zwei Kronen-Duelle gleichzeitig
		for _, other in pairs(matches) do
			if other.Mode == "Crown" then
				return nil
			end
		end
	end
	-- Teams normalisieren und Menschen prüfen
	local humans: { Player } = {}
	local seen: { [Player]: boolean } = {}
	local teams: { { any } } = {}
	local teamTotal = if ffa then 1 else 2
	for t = 1, teamTotal do
		teams[t] = {}
	end
	for t, list in ipairs(spec.Teams) do
		if type(list) == "table" then
			local target = if ffa then 1 else math.clamp(t, 1, 2)
			for _, member in ipairs(list) do
				if typeof(member) == "Instance" and member:IsA("Player") then
					local p = member :: Player
					if p.Parent == Players and not seen[p] and playerMatch[p] == nil then
						seen[p] = true
						table.insert(humans, p)
						table.insert(teams[target], p)
					end
				elseif type(member) == "table" and member.Bot == true then
					table.insert(teams[target], { Bot = true, Difficulty = member.Difficulty })
				end
			end
		end
	end
	if #humans == 0 then
		return nil
	end
	-- Bot-Stufe (verdeckt adaptiv, B10.3)
	local botDifficulty = "Normal"
	if tutorial then
		botDifficulty = (MODES.Tutorial and MODES.Tutorial.Difficulty) or "Rookie"
	else
		local ok, diff = call("BotService", "DifficultyFor", humans)
		if ok and type(diff) == "string" then
			botDifficulty = diff
		end
	end
	-- auffüllen mit Bots (Duelle: bis TeamSize, FFA: bis FillTo)
	if ffa then
		local fillTo = math.min(def.FillTo or 6, def.MaxPlayers or 8)
		while #teams[1] < fillTo do
			table.insert(teams[1], { Bot = true, Difficulty = botDifficulty })
		end
		while #teams[1] > (def.MaxPlayers or 8) do
			local last = teams[1][#teams[1]]
			if typeof(last) == "Instance" then
				break
			end
			table.remove(teams[1])
		end
	else
		for t = 1, 2 do
			while #teams[t] < def.TeamSize do
				table.insert(teams[t], { Bot = true, Difficulty = botDifficulty })
			end
		end
	end
	local botsNeeded = 0
	for _, list in ipairs(teams) do
		for _, member in ipairs(list) do
			if typeof(member) ~= "Instance" then
				botsNeeded += 1
			end
		end
	end
	if botsNeeded > (Config.Server.MaxBotsPerMatch or 7) then
		return nil
	end
	if botsNeeded > 0 then
		local ok, budget = call("BotService", "Budget")
		if not ok or type(budget) ~= "number" or budget < botsNeeded then
			return nil
		end
	end
	local rematchArena = (spec :: any)._Arena
	if not rematchArena and not MatchService.CanHost(spec.Mode) then
		return nil
	end
	-- Menschen aus allen Schlangen nehmen
	for _, p in ipairs(humans) do
		call("QueueService", "Leave", p)
	end

	nextMatchId += 1
	local id = nextMatchId
	local mutator: string? = nil
	if type(spec.Mutator) == "string" and MODES.Mutators and MODES.Mutators[spec.Mutator] then
		mutator = spec.Mutator
	elseif def.UsesMutator then
		mutator = MatchService.ActiveMutator()
	end
	local m: any = {
		Id = id,
		Mode = spec.Mode,
		Def = def,
		Ffa = ffa,
		Tutorial = tutorial,
		TeamSize = def.TeamSize,
		RoundsToWin = if tutorial
			then ((MODES.Tutorial and MODES.Tutorial.RoundsToWin) or def.RoundsToWin)
			else def.RoundsToWin,
		RoundCap = def.RoundCap,
		RoundTime = def.RoundTime,
		OvertimeTime = def.Overtime,
		Cfg = MCFG,
		AntiCamp = (Config.Combat and Config.Combat.AntiCamp) or { Duel = 30, Team = 40, Pulse = 10, Show = 1 },
		Regen = if ffa then (Config.Player.Regen or { Delay = 5, Rate = 12 }) else nil,
		Mutator = mutator,
		Rules = buildRules(spec.Mode, mutator, tutorial),
		Entries = {},
		ByPlayer = {},
		ById = {},
		Score = { 0, 0 },
		Scores = {},
		Votes = {},
		BotVoteAt = {},
		VoteOptions = {},
		VoteMaps = {},
		PendingBots = {},
		RematchVotes = {},
		Tainted = false,
		BotDifficulty = botDifficulty,
		AdminStarted = spec.AdminStarted == true,
		RematchOf = spec.RematchOf,
		Phase = "Init",
		PhaseStart = now(),
		PhaseEnds = math.huge,
		CrownKing = nil,
	}
	if m.Tutorial and m.RoundsToWin then
		m.RoundCap = Rounds.RoundCap(m.RoundsToWin)
	end
	m.Api = makeApi(m)
	for t, list in ipairs(teams) do
		for i, member in ipairs(list) do
			local team = if ffa then i else t
			newEntry(m, member, team)
		end
	end
	matches[id] = m
	for _, p in ipairs(humans) do
		playerMatch[p] = id
	end
	if spec.Mode == "Crown" then
		local ok, king = call("QueueService", "CrownKing")
		if ok and typeof(king) == "Instance" then
			m.CrownKing = king
		end
	end
	if tutorial then
		for _, p in ipairs(humans) do
			funnel(p, 3, "TutorialStarted")
		end
	end

	-- Map + Stimmung
	local voting = false
	if def.FixedMap then
		m.Map = def.FixedMap
		m.Mood = (Config.Maps and Config.Maps.LobbyMood) or "Day"
	elseif type(spec.Map) == "string" and mapCfg(spec.Map) and not mapCfg(spec.Map).Fixed then
		m.Map = spec.Map
		local moods = Config.Maps and Config.Maps.Moods
		local moodOk = type(spec.Mood) == "string" and type(moods) == "table" and moods[spec.Mood] ~= nil
		m.Mood = if moodOk then spec.Mood else pickMood(spec.Map)
	elseif tutorial then
		m.Map = (MODES.Tutorial and MODES.Tutorial.Map) or "PillarBox"
		m.Mood = (MODES.Tutorial and MODES.Tutorial.Mood) or pickMood(m.Map)
	elseif def.Vote and not spec.RematchOf then
		local options, all = buildVoteOptions(spec.Mode, if ffa then 1 else def.TeamSize)
		m.VoteOptions = options
		m.VoteMaps = all
		voting = #options > 0
		if not voting then
			m.Map = all[1]
		end
	else
		local pool = mapsFor(spec.Mode, if ffa then 1 else def.TeamSize)
		if #pool == 0 then
			pool = mapsFor("Duel1", 1)
		end
		m.Map = pool[rng:NextInteger(1, math.max(1, #pool))]
		if m.Map then
			m.Mood = pickMood(m.Map)
		end
	end
	if not voting and not m.Map then
		-- keine passende Map: Match kann nicht laufen
		matches[id] = nil
		for _, p in ipairs(humans) do
			playerMatch[p] = nil
		end
		return nil
	end

	-- MATCH GEFUNDEN!
	if voting then
		setPhase(m, "Vote", MCFG.VoteSeconds or 5)
		local t = now()
		for _, e in ipairs(m.Entries) do
			if e.IsBot then
				m.BotVoteAt[e.Key] = t + rng:NextNumber(MCFG.BotVoteMin or 1, MCFG.BotVoteMax or 3)
			end
		end
	end
	if not rematchArena then
		sendMembers(m, "Found", {
			MatchId = id,
			Mode = m.Mode,
			Mutator = m.Mutator,
			Teams = rosterFound(m),
			VoteOptions = if voting then m.VoteOptions else nil,
			VoteEnds = if voting then m.PhaseEnds else nil,
			Tutorial = tutorial,
		})
	end
	if rematchArena then
		-- Rematch: gleiche Arena, sofort Prep (B5)
		m.Arena = rematchArena
		m.Map = spec.Map
		m.Mood = spec.Mood
		setPhase(m, "Load", 0)
		setupArena(m)
		if not m.Ffa and (teamMembers(m, 1) == 0 or teamMembers(m, 2) == 0) then
			local specAny: any = spec
			specAny._Cancelled = true
			cancelMatch(m, "match.botsBusy") -- schickt alle in die Lobby und gibt die Arena frei
			return nil
		end
		startRuleset(m)
	elseif not voting then
		beginLoad(m)
	end
	return id
end

local function startRematch(m: any)
	local teams: { { any } } = { {}, {} }
	if m.Ffa then
		teams = { {} }
	end
	for _, e in ipairs(m.Entries) do
		if not e.Removed then
			local t = if m.Ffa then 1 else e.Team
			if e.Player then
				table.insert(teams[t], e.Player)
			else
				table.insert(teams[t], { Bot = true, Difficulty = e.Difficulty })
			end
		end
	end
	local arena = m.Arena
	m.KeepArena = true
	-- altes Match ohne Lobby-Rückkehr abbauen
	teardown(m, true)
	m.Phase = "Closed"
	matches[m.Id] = nil
	for p, id in pairs(playerMatch) do
		if id == m.Id then
			playerMatch[p] = nil
		end
	end
	local spec: any = {
		Mode = m.Mode,
		Teams = teams,
		Map = m.Map,
		Mood = m.Mood,
		Mutator = m.Mutator,
		Tutorial = false, -- Tutorial-Belohnung gibt es nur einmal
		RematchOf = m.Id,
		_Arena = arena,
	}
	local newId = MatchService.Create(spec)
	if not newId and not spec._Cancelled then
		-- Rematch ging nicht (z. B. Bot-Budget): normal schließen
		for _, e in ipairs(m.Entries) do
			local p = e.Player
			if p and not e.Removed and p.Parent == Players then
				local okSpawn, lobby = call("ArenaService", "LobbySpawn")
				call(
					"CharacterService",
					"Teleport",
					p,
					lifted(if okSpawn and typeof(lobby) == "CFrame" then lobby else CFrame.new(0, 5, 0))
				)
				setAllowance(p, nil)
				sendTo(p, "Closed", {})
			end
		end
		call("ArenaService", "Release", arena)
	end
end

function MatchService.End(id: number, reason: string)
	local m = matches[id]
	if not m then
		return
	end
	if m.Phase == "Vote" or m.Phase == "Load" or m.Phase == "Intro" or m.Phase == "Init" then
		cancelMatch(m, "match.cancelled")
	elseif m.Phase == "MatchEnd" then
		closeMatch(m, reason)
	else
		local winner = 0
		if m.Ffa then
			local leader, tie = Respawn.Leader(m.Scores, m.Api.DamageTable())
			winner = if leader and not tie then m.Api.TeamOf(leader) else 0
		elseif m.Score[1] ~= m.Score[2] then
			winner = if m.Score[1] > m.Score[2] then 1 else 2
		end
		finishMatch(m, winner)
	end
end

function MatchService.MatchOf(p: Player): number?
	return playerMatch[p]
end

function MatchService.Phase(id: number): string?
	local m = matches[id]
	return m and m.Phase
end

function MatchService.Members(id: number): { Player }
	local m = matches[id]
	local list: { Player } = {}
	if m then
		for _, e in ipairs(humanEntries(m)) do
			table.insert(list, e.Player :: Player)
		end
	end
	return list
end

-- Crown-Zuschauer (≤ 150 Studs um den Ring, nicht selbst in einem Match), gecacht 2 Hz
local crownAudience: { Player } = {}

local function refreshAudience()
	table.clear(crownAudience)
	local hasCrown = false
	for _, m in pairs(matches) do
		if m.Mode == "Crown" and m.Arena then
			hasCrown = true
			break
		end
	end
	if not hasCrown then
		return
	end
	local ok, arena = call("ArenaService", "Crown")
	if not ok or type(arena) ~= "table" or typeof(arena.Origin) ~= "CFrame" then
		return
	end
	local center = arena.Origin.Position
	local radius = Config.Server.CrownAudienceRadius or 150
	for _, p in ipairs(Players:GetPlayers()) do
		if playerMatch[p] == nil then
			local char = p.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and (root.Position - center).Magnitude <= radius then
				table.insert(crownAudience, p)
			end
		end
	end
end

function MatchService.Recipients(id: number): { Player }
	local list = MatchService.Members(id)
	local m = matches[id]
	if m and m.Mode == "Crown" then
		for _, p in ipairs(crownAudience) do
			if p.Parent == Players and playerMatch[p] == nil then
				table.insert(list, p)
			end
		end
	end
	return list
end

function MatchService.Info(id: number): any
	local m = matches[id]
	if not m then
		return nil
	end
	local names: { string } = {}
	local bots = 0
	for _, e in ipairs(m.Entries) do
		if not e.Removed then
			if e.IsBot then
				bots += 1
			else
				table.insert(names, e.Name)
			end
		end
	end
	local score: { number } = {}
	if m.Ffa then
		for _, value in pairs(m.Scores) do
			table.insert(score, value)
		end
		table.sort(score, function(a, b)
			return a > b
		end)
	else
		score = table.clone(m.Score)
	end
	return {
		MatchId = m.Id,
		Slot = m.Arena and m.Arena.Slot or 0,
		Mode = m.Mode,
		Map = m.Map or "",
		Phase = m.Phase,
		Score = score,
		Players = names,
		Bots = bots,
		Tainted = m.Tainted == true,
	}
end

function MatchService.List(): { any }
	local list = {}
	for id in pairs(matches) do
		local info = MatchService.Info(id)
		if info then
			table.insert(list, info)
		end
	end
	table.sort(list, function(a, b)
		return a.MatchId < b.MatchId
	end)
	return list
end

function MatchService.Taint(id: number, reason: string)
	local m = matches[id]
	if not m or m.Tainted then
		return
	end
	m.Tainted = true
	m.TaintReason = tostring(reason)
	notifyMembers(m, "match.tainted", nil, "Alarm")
end

function MatchService.OnMatchEnd(cb: (result: Types.MatchResult) -> ())
	if type(cb) == "function" then
		table.insert(endCallbacks, cb)
	end
end

function MatchService.Route(p: Player, _char: Model): (string, CFrame?)
	local id = playerMatch[p]
	local m = id and matches[id]
	local e = m and m.ByPlayer[p]
	if not m or not e or not e.Combatant then
		return "Lobby", nil
	end
	local phase = m.Phase
	if phase == "Vote" or phase == "Init" then
		return "Lobby", nil
	end
	-- CharacterService.Unpop setzt selbst +3 Y auf den Spawn
	if phase == "Load" or phase == "Intro" or phase == "Prep" then
		return "Spawn", spawnFor(m, e)
	end
	local c = e.Combatant :: Combatant
	if (phase == "RoundEnd" or phase == "MatchEnd") and c.Alive then
		return "Spawn", spawnFor(m, e) -- kein Fallback-Pop zwischen den Runden
	end
	return "Vault", nil
end

-- FFA-Drop-in: < 8 Menschen und < 4:00 Spielzeit -> sofort rein (ersetzt einen Bot ab 6 Teilnehmern)
function MatchService.DropIn(p: Player): boolean
	if playerMatch[p] ~= nil then
		return false
	end
	for _, m in pairs(matches) do
		local def = m.Def
		if m.Ffa and m.Phase == "Live" and m.Arena and now() - (m.StartedAt or now()) < (def.DropInUntil or 240) then
			local humans, total = 0, 0
			for _, e in ipairs(m.Entries) do
				if not e.Removed then
					total += 1
					if not e.IsBot then
						humans += 1
					end
				end
			end
			if humans < (def.MaxPlayers or 8) then
				if total >= (def.FillTo or 6) or total >= (def.MaxPlayers or 8) then
					-- einen Bot ersetzen
					for _, e in ipairs(m.Entries) do
						if e.IsBot and not e.Removed then
							Respawn.RemoveCombatant(m, e.Id)
							despawnBot(m, e)
							e.Removed = true
							break
						end
					end
				end
				local total2 = 0
				for _, e in ipairs(m.Entries) do
					if not e.Removed then
						total2 += 1
					end
				end
				if total2 < (def.MaxPlayers or 8) then
					local e = newEntry(m, p, 0)
					if e then
						e.Team = e.Key -- FFA: jeder sein eigenes Team
						playerMatch[p] = m.Id
						if spawnEntry(m, e) then
							call("QueueService", "Leave", p)
							sendStart(m)
							Respawn.AddCombatant(m, e.Combatant)
							m.Api.Respawn(e.Combatant)
							sendTo(p, "Live", { EndsAt = m.PhaseEnds })
							return true
						end
						e.Removed = true
						m.ByPlayer[p] = nil
						playerMatch[p] = nil
					end
				end
			end
		end
	end
	return false
end

-- ---------------------------------------------------------------------
-- 10) SIGNALE AUS DEM KAMPF
-- ---------------------------------------------------------------------
local function onDamage(attacker: Combatant?, victim: Combatant, dealt: number, _info: any)
	local m = matchByCtx[victim.Ctx]
	if not m or not RULESET_PHASES[m.Phase] then
		return
	end
	local ae = entryByCombatant(m, attacker)
	if ae and attacker ~= victim and attacker and attacker.Team ~= victim.Team then
		ae.Stats.Damage += dealt
	end
	ruleset(m).OnDamage(m, attacker, victim, dealt)
end

local function eliminationFlags(ke: Entry?, info: any): any
	local flags: any = {}
	if not ke then
		return flags
	end
	local p = ke.Player
	if p then
		local data = dataOf(p)
		local streak = data and type(data.Stats) == "table" and tonumber(data.Stats.Streak) or 0
		if streak >= 3 then
			flags.Streak = streak
		end
		local bounty = bountyOf(p)
		if bounty > 0 then
			flags.Bounty = bounty
		end
		local ok, tier = call("ProgressionService", "MasteryTier", p, info.WeaponKey)
		if ok and type(tier) == "number" and tier >= 5 then
			flags.Mastery = tier
		end
		local okK, king = call("QueueService", "CrownKing")
		if okK and king == p then
			flags.Crown = true
		end
	end
	if info.Void then
		flags.Void = true
	end
	-- Skill-Moment: DOUBLE / TRIPLE / QUAD (nächster Pop innerhalb von MultiKillWindow)
	local t = now()
	if t - ke.MultiAt <= (SKILL.MultiKillWindow or 4) then
		ke.MultiCount += 1
	else
		ke.MultiCount = 1
	end
	ke.MultiAt = t
	if ke.MultiCount >= 2 then
		flags.Multi = math.min(ke.MultiCount, SKILL.MultiKillMax or 4)
	end
	return flags
end

local function onElimination(victim: Combatant, killer: Combatant?, info: Types.ElimInfo)
	local m = matchByCtx[victim.Ctx]
	if not m or not RULESET_PHASES[m.Phase] then
		return
	end
	local ve = entryByCombatant(m, victim)
	local ke = entryByCombatant(m, killer)
	if ke == ve then
		ke = nil -- Selbst-Pop: keine Gutschrift
	end
	if ve then
		ve.Stats.Deaths += 1
	end
	if ke and killer and killer.Team ~= victim.Team then
		local s = ke.Stats
		s.Elims += 1
		if victim.Kind == "Player" then
			s.PvpElims += 1
		end
		if info.Head then
			s.Headshots += 1
		end
		local def = Config.Weapon(info.WeaponKey)
		if info.Melee or (def and def.Kind == "Melee") then
			s.MeleeElims += 1
		end
		s.WeaponKills[info.WeaponKey] = (s.WeaponKills[info.WeaponKey] or 0) + 1
		if m.Tutorial and ke.Player then
			funnel(ke.Player, 5, "FirstKill")
		end
	end
	for _, assistId in ipairs(info.Assists or {}) do
		local ae = m.ById[assistId]
		if ae and ae ~= ke and ae ~= ve then
			ae.Stats.Assists += 1
		end
	end
	local flags = eliminationFlags(if ke and killer and killer.Team ~= victim.Team then ke else nil, info)
	local killerTeam = if killer then killer.Team else (if ve then otherTeam(ve.Team) else 1)
	local finisher = if ke then ke.Finisher else "F_Confetti"
	sendRecipients(m, "Elim", {
		K = if killer and killer ~= victim then killer.Id else nil,
		V = victim.Id,
		W = info.WeaponKey,
		H = info.Head == true,
		A = info.Assists or {},
		Fin = finisher,
		P = info.Pos,
		C = teamColor(killerTeam, m.Ffa),
		Fl = flags,
	})
	if ve and ve.Player then
		local ok, recap = call("CombatService", "Recap", victim.Id)
		if ok and type(recap) == "table" then
			sendTo(ve.Player, "Recap", recap)
		end
		if not m.Ffa and killer and killer ~= victim then
			sendTo(ve.Player, "Spectate", { TargetId = killer.Id })
		end
	end
	ruleset(m).OnElim(m, victim, killer, info)
end

local function onShot(c: Combatant, def: Types.WeaponDef, hits: number, _heads: number)
	local m = matchByCtx[c.Ctx]
	if not m then
		return
	end
	local e = m.ById[c.Id]
	if not e then
		return
	end
	local s = e.Stats
	s.ShotsFired += 1
	if hits > 0 then
		s.ShotsHit += 1
	end
	s.WeaponUsed[def.Key] = true
	s.WeaponShots[def.Key] = (s.WeaponShots[def.Key] or 0) + 1
	if m.Tutorial and e.Player then
		funnel(e.Player, 4, "FirstShot")
	end
end

-- ---------------------------------------------------------------------
-- 11) TAKT (5 Hz)
-- ---------------------------------------------------------------------
local function tickAfk(m: any, dt: number)
	if not LIVE_PHASES[m.Phase] then
		return
	end
	local warnAt, kickAt = MCFG.AfkWarn or 20, MCFG.AfkKick or 30
	for _, e in ipairs(humanEntries(m)) do
		if m.Phase == "Closed" then
			return -- letzter Mensch entfernt -> Match zu
		end
		local c = e.Combatant
		local p = e.Player :: Player
		if c and c.Alive and c.Root and not e.Removed then
			local okInput, lastInput = call("ReplicationService", "LastInput", p)
			local input = if okInput and type(lastInput) == "number" then lastInput else 0
			local pos = c.Root.Position
			local active = input > e.AfkInput
			e.AfkInput = math.max(e.AfkInput, input)
			if e.AfkPos == nil or (pos - e.AfkPos).Magnitude >= (MCFG.AfkMoveStuds or 2) then
				active = active or e.AfkPos ~= nil
				e.AfkPos = pos
			end
			if active then
				if e.AfkWarned then
					sendTo(p, "Afk", { Warn = false })
				end
				e.AfkIdle = 0
				e.AfkWarned = false
			else
				e.AfkIdle += dt
				if e.AfkIdle >= kickAt then
					removeEntry(m, e, "Afk")
				elseif e.AfkIdle >= warnAt and not e.AfkWarned then
					e.AfkWarned = true
					sendTo(p, "Afk", { Warn = true })
				end
			end
		end
	end
end

local function tickFfaFill(m: any)
	if not m.Ffa or m.Phase ~= "Live" then
		return
	end
	local t = now()
	if t < (m.NextFill or 0) then
		return
	end
	m.NextFill = t + (MCFG.FfaFillEvery or 2)
	local total = 0
	for _, e in ipairs(m.Entries) do
		if not e.Removed then
			total += 1
		end
	end
	if total < (m.Def.FillTo or 6) and #m.Entries < MAX_ROSTER then
		local okBudget, budget = call("BotService", "Budget")
		if okBudget and type(budget) == "number" and budget > 0 then
			local e = newEntry(m, { Bot = true, Difficulty = m.BotDifficulty }, 0)
			if e then
				e.Team = e.Key
				if spawnEntry(m, e) then
					Respawn.AddCombatant(m, e.Combatant)
					m.Api.Respawn(e.Combatant)
					sendStart(m)
				else
					e.Removed = true
				end
			end
		end
	end
end

-- Laden fertig? Alle Menschen haben "ArenaReady" gesendet (oder Zeit um) -> Intro
local function checkLoadDone(m: any, timeout: boolean)
	if m.Phase ~= "Load" or not m.Arena then
		return
	end
	-- noch nicht gespawnte Menschen (Figur fehlte) erneut versuchen
	local allReady = true
	for _, e in ipairs(humanEntries(m)) do
		if not e.Combatant then
			if spawnEntry(m, e) then
				e.PendingSpawn = false
				sendStart(m)
			end
		end
		if not e.LoadReady or not e.Combatant then
			allReady = false
		end
	end
	if not allReady and not timeout then
		return
	end
	for _, e in ipairs(humanEntries(m)) do
		if not e.Combatant then
			removeEntry(m, e, "NoSpawn")
			if m.Phase == "Closed" then
				return
			end
		end
	end
	if m.Phase == "Load" then
		-- ein Team ohne Mitglieder (z. B. Bot-Budget beim Laden erschöpft) -> abbrechen statt Freilos
		if not m.Ffa and (teamMembers(m, 1) == 0 or teamMembers(m, 2) == 0) then
			cancelMatch(m, "match.botsBusy")
			return
		end
		beginIntro(m)
	end
end

local function tickMatch(m: any, dt: number)
	local t = now()
	local phase = m.Phase
	if phase == "Vote" then
		for key, at in pairs(m.BotVoteAt) do
			if t >= at then
				m.BotVoteAt[key] = nil
				local options = #m.VoteOptions
				local pick = rng:NextInteger(1, options + 1)
				m.Votes["Bot" .. tostring(key)] = if pick > options then RANDOM_VOTE else pick
				sendVoteCounts(m)
			end
		end
		if t >= m.PhaseEnds then
			resolveVote(m)
			beginLoad(m)
		end
	elseif phase == "Load" then
		if not m.Arena then
			local ok, arena = call("ArenaService", "Acquire", m.Map, m.Mood)
			if ok and type(arena) == "table" then
				m.Arena = arena
				m.PhaseEnds = t + (MCFG.LoadTimeout or 4)
				setupArena(m)
			elseif t >= m.ArenaWaitUntil then
				cancelMatch(m, "match.noArena")
			end
			return
		end
		checkLoadDone(m, t >= m.PhaseEnds)
	elseif phase == "Intro" then
		if t >= m.PhaseEnds then
			startRuleset(m)
		end
	elseif RULESET_PHASES[phase] then
		local rs = ruleset(m)
		rs.Tick(m, dt)
		if m.Phase == "Closed" then
			return
		end
		tickAfk(m, dt)
		if m.Phase == "Closed" then
			return
		end
		tickFfaFill(m)
		local over, winner = rs.CheckEnd(m)
		if over then
			finishMatch(m, winner or 0)
		end
	elseif phase == "MatchEnd" then
		local needed, votes = 0, 0
		for _, e in ipairs(humanEntries(m)) do
			needed += 1
			if m.RematchVotes[e.Player] then
				votes += 1
			end
		end
		if needed > 0 and votes >= needed and m.Mode ~= "Crown" and m.Arena then
			startRematch(m)
		elseif t >= m.PhaseEnds then
			closeMatch(m, "Done")
		end
	end
end

local function tickAll(dt: number)
	local t = os.clock()
	if t - audienceAt >= 0.5 then
		audienceAt = t
		refreshAudience()
		-- Tages-Mutator gewechselt (UTC-Tag)?
		local active = MatchService.ActiveMutator()
		if lastMutator ~= nil and active ~= lastMutator then
			broadcastMutator()
		end
		lastMutator = active
	end
	for _, id in ipairs(Util.Snapshot(matches)) do
		local m = matches[id]
		if m then
			local ok, err = pcall(tickMatch, m, dt)
			if not ok then
				logError("Match " .. tostring(id), err)
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- 12) REQUEST-AKTIONEN (C9)
-- ---------------------------------------------------------------------
local function entryOf(p: Player): (any, Entry?)
	local id = playerMatch[p]
	local m = id and matches[id]
	return m, m and m.ByPlayer[p]
end

local function handleArenaReady(p: Player, arg: any): Reply
	if not Util.IsFinite(arg) then
		return reply(p, false, "core.invalid")
	end
	local m, e = entryOf(p)
	if not m or not e then
		return reply(p, false)
	end
	if m.Arena and (m.Arena.BuildId == nil or math.floor(arg) == m.Arena.BuildId) then
		e.LoadReady = true
		-- letzter Bereiter startet das Intro sofort (spart bis zu einen Takt, "erster Schuss ≤ 15 s")
		local ok, err = pcall(checkLoadDone, m, false)
		if not ok then
			logError("ArenaReady", err)
		end
		return reply(p, true)
	end
	return reply(p, false)
end

local function handleVoteMap(p: Player, arg: any): Reply
	if not Util.IsFinite(arg) then
		return reply(p, false, "core.invalid")
	end
	local index = math.floor(arg)
	local m, e = entryOf(p)
	if not m or not e or m.Phase ~= "Vote" then
		return reply(p, false)
	end
	if index < 1 or index > RANDOM_VOTE or (index < RANDOM_VOTE and m.VoteOptions[index] == nil) then
		return reply(p, false, "core.invalid")
	end
	m.Votes[p] = index
	sendVoteCounts(m)
	return reply(p, true)
end

local function handleReady(p: Player, _arg: any): Reply
	local m, e = entryOf(p)
	if not m or not e or m.Phase ~= "Prep" then
		return reply(p, false)
	end
	e.Ready = true
	return reply(p, true)
end

local function handleRematch(p: Player, _arg: any): Reply
	local m, e = entryOf(p)
	if not m or not e or m.Phase ~= "MatchEnd" or m.Mode == "Crown" then
		return reply(p, false)
	end
	m.RematchVotes[p] = true
	local needed, votes = 0, 0
	for _, other in ipairs(humanEntries(m)) do
		needed += 1
		if m.RematchVotes[other.Player] then
			votes += 1
		end
	end
	sendMembers(m, "Rematch", { Votes = votes, Needed = needed })
	return reply(p, true)
end

local function handleAutoRequeue(p: Player, arg: any): Reply
	if type(arg) ~= "boolean" then
		return reply(p, false, "core.invalid")
	end
	autoRequeue[p] = arg
	return reply(p, true)
end

local function handleLeaveMatch(p: Player, _arg: any): Reply
	if playerMatch[p] == nil then
		return reply(p, false)
	end
	MatchService.Leave(p, "Left")
	return reply(p, true)
end

local function validDifficulty(d: any): boolean
	if type(d) ~= "string" or #d > 16 then
		return false
	end
	local list = Config.Bots and Config.Bots.Difficulties
	if type(list) == "table" and next(list) ~= nil then
		return list[d] ~= nil
	end
	return d == "Rookie" or d == "Easy" or d == "Normal" or d == "Hard" or d == "Insane"
end

-- Practice starten (Request, Bot-Duell-Kabine oder PLAY-Menü)
function MatchService._StartPractice(p: Player, difficulty: string, tutorial: boolean): (boolean, string?)
	if playerMatch[p] ~= nil then
		return false, "match.inMatch"
	end
	local t = os.clock()
	local cooldown = (MODES.Queue and MODES.Queue.PracticeCooldown) or 5
	if (practiceAt[p] or -math.huge) + cooldown > t then
		return false, "match.tooFast"
	end
	practiceAt[p] = t
	local spec: any = {
		Mode = "Practice",
		Teams = { { p }, { { Bot = true, Difficulty = difficulty } } },
		Tutorial = tutorial,
	}
	if tutorial then
		spec.Map = (MODES.Tutorial and MODES.Tutorial.Map) or "PillarBox"
	end
	local id = MatchService.Create(spec)
	if not id then
		local okBudget, budget = call("BotService", "Budget")
		if okBudget and type(budget) == "number" and budget <= 0 then
			return false, "match.botsBusy"
		end
		return false, "match.arenasFull"
	end
	return true, nil
end

local function handlePracticeStart(p: Player, arg: any): Reply
	if not validDifficulty(arg) then
		return reply(p, false, "match.badDifficulty")
	end
	local ok, key = MatchService._StartPractice(p, arg, false)
	return reply(p, ok, key)
end

local function handleTutorialStart(p: Player, _arg: any): Reply
	local data = dataOf(p)
	local first = not (data and type(data.Flags) == "table" and data.Flags.Tutorial == true)
	local difficulty = (MODES.Tutorial and MODES.Tutorial.Difficulty) or "Rookie"
	local ok, key
	if first then
		ok, key = MatchService._StartPractice(p, difficulty, true)
	else
		-- Tutorial schon gemacht: normales Practice auf der Tutorial-Map (ohne Sonderbelohnung)
		ok, key = MatchService._StartPractice(p, difficulty, false)
	end
	return reply(p, ok, key)
end

-- ---------------------------------------------------------------------
-- 13) INIT / START
-- ---------------------------------------------------------------------
local function onPlayerRemoving(p: Player)
	leaving[p] = true
	local m, e = entryOf(p)
	if m and e then
		local ok, err = pcall(removeEntry, m, e, "Left")
		if not ok then
			logError("PlayerRemoving", err)
		end
	end
	leaving[p] = nil
	playerMatch[p] = nil
	autoRequeue[p] = nil
	funnelDone[p] = nil
	practiceAt[p] = nil
	for _, match in pairs(matches) do
		match.ByPlayer[p] = nil
		match.Votes[p] = nil
		match.RematchVotes[p] = nil
	end
	local idx = table.find(crownAudience, p)
	if idx then
		table.remove(crownAudience, idx)
	end
end

local function onReady(p: Player)
	-- Auto-Requeue-Standard aus den Einstellungen (Data.Settings.AutoRequeue)
	local data = dataOf(p)
	if data and type(data.Settings) == "table" and type(data.Settings.AutoRequeue) == "boolean" then
		if autoRequeue[p] == nil then
			autoRequeue[p] = data.Settings.AutoRequeue
		end
	end
end

function MatchService.Init(services: any)
	Services = services
	local pss = Services.PlayerStateService
	if pss then
		pss.Handle("ArenaReady", handleArenaReady)
		pss.Handle("VoteMap", handleVoteMap)
		pss.Handle("Ready", handleReady)
		pss.Handle("Rematch", handleRematch)
		pss.Handle("AutoRequeue", handleAutoRequeue)
		pss.Handle("LeaveMatch", handleLeaveMatch)
		pss.Handle("PracticeStart", handlePracticeStart, { Rate = 1, Per = 5 })
		pss.Handle("TutorialStart", handleTutorialStart, { Rate = 1, Per = 10 })
		pss.Provide("Mutator", function(_p: Player)
			return MatchService.ActiveMutator()
		end)
	else
		warn("[MatchService] PlayerStateService fehlt – keine Match-Anfragen möglich")
	end
end

function MatchService.Start()
	lastMutator = MatchService.ActiveMutator()
	call("CharacterService", "SetRouter", MatchService.Route)
	local okD = call("CombatService", "OnDamage", onDamage)
	local okE = call("CombatService", "OnElimination", onElimination)
	if not okD or not okE then
		warn("[MatchService] CombatService-Signale fehlen – Matches ohne Pop-Erkennung")
	end
	call("WeaponService", "OnShot", onShot)
	call("PlayerStateService", "OnReady", onReady)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	Scheduler.Every("Matches", TICK_HZ, tickAll)
	if RunService:IsStudio() then
		print("[MatchService] bereit (Tages-Mutator: " .. MatchService.ActiveMutator() .. ")")
	end
end

return MatchService
