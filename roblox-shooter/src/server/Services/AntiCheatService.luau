-- =====================================================================
--  CLUTCH CLASH – Anti-Cheat (Server/Services/AntiCheatService)
--  Besitzer: WP7 (Sicherheit, Admin, Live-Balance). Vertrag: DESIGN.md C5.7, C12.1–C12.5, C14, C9 ("Report").
--
--  Grundsätze (C12.1): Der Server entscheidet. Schaden zuerst verhindern (Zurücksetzen auf die letzte gültige
--  Position), Verdacht aus MEHREREN Signalen, Statistik bannt NIE automatisch, nur harte Signale eskalieren
--  (3 harte Kicks in 7 Tagen = 1-Tages-Bann). Admins, Gepoppte (Vault) und Ausnahmen sind ausgenommen.
--
--  Bewegung (C12.3, 5 Hz gestaffelt über Lib/Scheduler, MH-CarryService-Muster):
--    Weg-Budget (32 × SpeedMult × 1.15 + 6 Studs/s, Vorrat 1 s) · Teleport > 40 Studs ohne Gnade ·
--    Höhe über letztem Bodenkontakt · Fliegen (> 3 s Luft ohne Fallen, Mondsprung 6 s) · Noclip (Strahl zwischen
--    zwei Messungen, nur echtes Durchqueren einer Wand zählt) · Verstoß -> Zurücksetzen + Verdachtspunkte.
--  Verdacht (C12.4): Gewichte aus Config.Security.Weights, Abbau 1 Punkt je 30 s, ≥ 25 Prüf-Flag (gespeichert in
--    CC_Mod_v1 F_<yyyymmdd>_<shard>), ≥ 60 Kick. Honeypot-Remote "GrantCoins" = +100, Kick, Flag.
--  Meldungen (C9 "Report"): 3 pro 10 min, Server hängt einen Statistik-Schnappschuss an (R_<yyyymmdd>_<shard>).
--
--  Öffentliche API (C5.7):
--    AntiCheatService.NoteTeleport(p, cf)                       1 s Gnade nach Server-Teleport
--    AntiCheatService.Grace(p, kind, seconds, maxSpeed?)         kind "Impulse" | "Launch" | "Teleport"
--    AntiCheatService.SetAllowance(p, { SpeedMult?, VerticalMult?, AirJumps? })   ersetzt die alte Erlaubnis
--    AntiCheatService.Exempt(p, seconds)                         z. B. im Vault (0 = Ausnahme beenden)
--    AntiCheatService.Add(p, reason, points, evidence?)
--    AntiCheatService.Score(p): number
--    AntiCheatService.Flags(): { Flag }                          Prüf-Flags dieses Servers (neueste zuerst)
--  Zusatz (nur WP7, AdminService):
--    AntiCheatService.Snapshot(p)          Statistik-Schnappschuss (Kopf-%, Genauigkeit, Pops/min, Reject-Zähler)
--    AntiCheatService.Reports()            Meldungen dieses Servers
--    AntiCheatService.AllFlags(days?) / AllReports(days?)   + gespeicherte Shards (yieldet, 60 s Cache)
--    AntiCheatService.Dismiss(id): boolean                  Flag/Meldung abweisen (yieldet)
--    AntiCheatService.LogBan(entry) / BanLog() / MarkUnbanned(userId)   Bann-Log CC_Mod_v1 "BanLog" (yieldet)
-- =====================================================================

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Lang = require(Shared:WaitForChild("Lang"))
local Types = require(Shared:WaitForChild("Types"))
local Util = require(Shared:WaitForChild("Util"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local AntiCheatService = {}
local Services: any = nil

local SEC: any = Config.Security
local HARD_REASONS: { [string]: boolean } = { Honeypot = true, RateBurst = true, Teleport = true }
local HARD_WINDOW = 600 -- ein hartes Signal zählt so lange für "Kick wegen harter Signale"
local DEFAULT_GRAVITY = 196.2
local MAX_EVIDENCE_KEYS = 12
local RECENT_MAX = 64 -- Zeitstempel pro Grund für die Minuten-Zählung
local STORE_CACHE_SECONDS = 60
local BANLOG_CACHE_SECONDS = 15

-- Grund-Texte (auch Reject-Codes aus WP3, egal ob groß/klein geschrieben) -> Schlüssel in Weights
local REASON_KEYS: { [string]: string } = {
	honeypot = "Honeypot",
	type = "Type",
	rate = "Rate",
	rateburst = "RateBurst",
	origin = "Origin",
	los = "Los",
	losburst = "LosBurst",
	mismatch = "Mismatch",
	hitbox = "Hitbox", -- einzelne abgelehnte Treffer-Behauptung (für die Mismatch-Quote)
	speed = "Speed",
	teleport = "Teleport",
	fly = "Fly",
	noclip = "Noclip",
	stats = "Stats",
	state = "State",
	time = "Time",
	range = "Range",
}

local REPORT_REASONS: { [string]: boolean } = { Aimbot = true, Speed = true, Toxic = true, Other = true }

-- ---------------------------------------------------------------------
-- TYPEN
-- ---------------------------------------------------------------------
type Allowance = { SpeedMult: number, VerticalMult: number, AirJumps: number }

type Track = {
	Character: Model?,
	Pos: Vector3?, -- letzte anerkannte Position
	ValidCF: CFrame?, -- letzte gültige CFrame (Zurücksetzen bei waagrechten Verstößen)
	GroundCF: CFrame?, -- letzte CFrame mit Bodenkontakt (Zurücksetzen bei Höhe/Fliegen)
	Time: number,
	Budget: number,
	GraceUntil: number,
	Anchor: Vector3?, -- Ziel des letzten Server-Teleports
	ImpulseUntil: number,
	ImpulseSpeed: number,
	ExemptUntil: number,
	GroundY: number?,
	AirSince: number?,
	LastY: number?,
	StillSince: number, -- seit wann sich die Position nicht mehr bewegt hat (Lag-Erkennung)
	LastRaw: Vector3?,
	LastSpeed: number, -- waagrechte Geschwindigkeit bei der letzten Messung (eingefroren = Lag)
	EffSpeed: number, -- zuletzt wirksamer Tempo-Faktor (Kontext-Regeln)
	Allowance: Allowance,
	Probe: RaycastParams,
}

type Suspicion = {
	Score: number,
	Review: number,
	T: number,
	Counts: { [string]: number },
	Recent: { [string]: { number } },
	BurstAt: { [string]: number },
	HardAt: number?,
	FlagAt: number,
	Evidence: { [string]: any },
	Kicking: boolean,
}

type ShotStats = {
	JoinedAt: number,
	Shots: number,
	ShotsHit: number,
	Hits: number,
	Heads: number,
	Pops: number,
	Claims: { boolean },
	StatsFlagged: boolean,
}

export type Flag = {
	Id: string,
	UserId: number,
	Name: string,
	Score: number,
	Reasons: { string },
	Evidence: { [string]: any },
	T: number,
}

export type Report = {
	Id: string,
	From: number,
	FromName: string,
	UserId: number,
	Name: string,
	Reason: string,
	Snapshot: { [string]: any },
	T: number,
}

export type BanEntry = {
	UserId: number,
	Name: string,
	Reason: string,
	Duration: number,
	By: number,
	ByName: string,
	T: number,
	Active: boolean,
	Auto: boolean,
}

-- ---------------------------------------------------------------------
-- ZUSTAND (alle Pro-Spieler-Tabellen werden bei PlayerRemoving geleert)
-- ---------------------------------------------------------------------
local tracks: { [Player]: Track } = {}
local trackedList: { Player } = {}
local suspicions: { [Player]: Suspicion } = {}
local shotStats: { [Player]: ShotStats } = {}
local honeypotHit: { [Player]: boolean } = {}

local localFlags: { Flag } = {}
local localReports: { Report } = {}
local pendingFlags: { Flag } = {}
local pendingReports: { Report } = {}
local dismissed: { [string]: boolean } = {}
local idCounter = 0

local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
wallParams.RespectCanCollide = true
wallParams.IgnoreWater = true
local excludesDirty = true

local modStore: DataStore? = nil
local storeDisabled = false
local storeWarned = false
local flushing = false
local storedCache: { [string]: { T: number, List: { any } } } = {}
local sessionBans: { BanEntry } = {}
local banLogCache: { BanEntry }? = nil
local banLogAt = -math.huge

-- ---------------------------------------------------------------------
-- KLEINE HELFER
-- ---------------------------------------------------------------------
local function service(name: string): any
	return if Services then Services[name] else nil
end

-- Ruft Services.<name>.<fn>(...) in pcall auf. Gibt (ok, Ergebnis …) zurück; fehlt der Dienst -> false.
local function call(name: string, fnName: string, ...: any): (boolean, ...any)
	local svc = service(name)
	local fn = if type(svc) == "table" then svc[fnName] else nil
	if type(fn) ~= "function" then
		return false
	end
	return pcall(fn, ...)
end

local function langOf(p: Player): Types.Lang
	local ok, lang = call("PlayerStateService", "LangOf", p)
	if ok and (lang == "de" or lang == "en") then
		return lang
	end
	return Lang.For(p)
end

local function L(p: Player, key: string, ...: any): string
	return Lang.T(langOf(p), key, ...)
end

local function isAdmin(p: Player): boolean
	local ok, result = call("AdminService", "IsAdmin", p)
	return ok and result == true
end

local function round(n: number, digits: number?): number
	local m = 10 ^ (digits or 0)
	return math.floor(n * m + 0.5) / m
end

local function utcDay(): number
	return math.floor(os.time() / 86400)
end

local function dateKey(day: number): string
	return os.date("!%Y%m%d", day * 86400) :: string
end

local function shard(): number
	local count = math.max(1, math.floor(tonumber(Config.Tech.Shards) or 8))
	return Util.Hash(game.JobId) % count
end

local function newId(prefix: string): string
	idCounter += 1
	local key = ("%s_%s_%d"):format(prefix, dateKey(utcDay()), shard())
	return ("%s:%x%04x"):format(key, os.time() % 0xFFFFFF, idCounter % 0xFFFF)
end

-- Beweise klein und JSON-tauglich halten (keine Instanzen, keine riesigen Texte)
local function sanitizeValue(value: any): any
	local kind = typeof(value)
	if kind == "number" then
		return if Util.IsFinite(value) then round(value, 2) else 0
	elseif kind == "boolean" then
		return value
	elseif kind == "string" then
		return string.sub(value, 1, 80)
	elseif kind == "Vector3" then
		return ("%.1f,%.1f,%.1f"):format(value.X, value.Y, value.Z)
	elseif kind == "Instance" then
		return string.sub(value.Name, 1, 40)
	end
	return string.sub(tostring(value), 1, 40)
end

local function sanitizeEvidence(evidence: any): { [string]: any }
	local clean: { [string]: any } = {}
	if type(evidence) ~= "table" then
		return clean
	end
	local count = 0
	for key, value in pairs(evidence) do
		if count >= MAX_EVIDENCE_KEYS then
			break
		end
		if type(key) == "string" and type(value) ~= "table" and type(value) ~= "function" then
			clean[string.sub(key, 1, 24)] = sanitizeValue(value)
			count += 1
		end
	end
	return clean
end

local function normalizeReason(reason: any): string
	local text = if type(reason) == "string" then reason else tostring(reason)
	text = string.sub(text, 1, 32)
	local key = REASON_KEYS[string.lower(text)]
	if key then
		return key
	end
	return text
end

-- ---------------------------------------------------------------------
-- SPEICHER (CC_Mod_v1) – alles in pcall; Studio ohne API-Zugriff -> leise aus
-- ---------------------------------------------------------------------
local function noteStoreError(err: any)
	local text = string.lower(tostring(err))
	local studioError = string.find(text, "studio", 1, true)
		or string.find(text, "publish", 1, true)
		or string.find(text, "api services", 1, true)
		or string.find(text, "403", 1, true)
	if RunService:IsStudio() and studioError then
		storeDisabled = true
		if not storeWarned then
			storeWarned = true
			warn("[AntiCheat] Kein DataStore-Zugriff im Studio – Flags/Meldungen/Bann-Log nur im Speicher.")
		end
	else
		warn("[AntiCheat] DataStore-Fehler: " .. tostring(err))
	end
end

local function getStore(): DataStore?
	if storeDisabled then
		return nil
	end
	if modStore then
		return modStore
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Tech.ModStore)
	end)
	if ok and result then
		modStore = result
		return result
	end
	noteStoreError(result)
	return nil
end

local function storeGet(key: string): (boolean, any)
	local store = getStore()
	if not store then
		return false, nil
	end
	local ok, result = pcall(function()
		return (store :: DataStore):GetAsync(key)
	end)
	if not ok then
		noteStoreError(result)
		return false, nil
	end
	return true, result
end

local function storeUpdate(key: string, transform: (old: any) -> any): (boolean, any)
	local store = getStore()
	if not store then
		return false, nil
	end
	local ok, result = pcall(function()
		return (store :: DataStore):UpdateAsync(key, function(old)
			return transform(old)
		end)
	end)
	if not ok then
		noteStoreError(result)
		return false, nil
	end
	return true, result
end

-- Liste mit Ids zusammenführen (ohne Doppelte), auf "max" neueste kürzen
local function mergeList(old: any, additions: { any }, max: number): { any }
	local list: { any } = {}
	local seen: { [string]: boolean } = {}
	if type(old) == "table" then
		for _, entry in ipairs(old) do
			if type(entry) == "table" and type(entry.Id) == "string" and not seen[entry.Id] then
				seen[entry.Id] = true
				table.insert(list, entry)
			end
		end
	end
	for _, entry in ipairs(additions) do
		if not seen[entry.Id] then
			seen[entry.Id] = true
			table.insert(list, entry)
		end
	end
	while #list > max do
		table.remove(list, 1)
	end
	return list
end

-- Wartende Flags/Meldungen in den Tages-Shard schreiben (höchstens StoreWritesPerMinute je Art)
local function flushPending(pending: { any }, prefix: string)
	if #pending == 0 then
		return
	end
	local batch = table.clone(pending)
	local key = ("%s_%s_%d"):format(prefix, dateKey(utcDay()), shard())
	local maxPerKey = math.floor(SEC.StoreMaxPerKey or 50)
	local ok = storeUpdate(key, function(old)
		return mergeList(old, batch, maxPerKey)
	end)
	if ok or storeDisabled then
		-- geschrieben (oder kein Speicher vorhanden): aus der Warteschlange nehmen
		for _, entry in ipairs(batch) do
			local index = table.find(pending, entry)
			if index then
				table.remove(pending, index)
			end
		end
		storedCache[prefix] = nil
	end
	while #pending > maxPerKey do
		table.remove(pending, 1)
	end
end

local function flushStores()
	if flushing then
		return
	end
	flushing = true
	task.spawn(function()
		local ok, err = pcall(function()
			flushPending(pendingFlags, "F")
			flushPending(pendingReports, "R")
		end)
		if not ok then
			warn("[AntiCheat] Speichern der Flags fehlgeschlagen: " .. tostring(err))
		end
		flushing = false
	end)
end

-- ---------------------------------------------------------------------
-- VERDACHT
-- ---------------------------------------------------------------------
local function suspicionOf(p: Player): Suspicion
	local s = suspicions[p]
	if not s then
		s = {
			Score = 0,
			Review = 0,
			T = os.clock(),
			Counts = {},
			Recent = {},
			BurstAt = {},
			HardAt = nil,
			FlagAt = -math.huge,
			Evidence = {},
			Kicking = false,
		}
		suspicions[p] = s
	end
	return s
end

local function statsOf(p: Player): ShotStats
	local st = shotStats[p]
	if not st then
		st = {
			JoinedAt = os.clock(),
			Shots = 0,
			ShotsHit = 0,
			Hits = 0,
			Heads = 0,
			Pops = 0,
			Claims = {},
			StatsFlagged = false,
		}
		shotStats[p] = st
	end
	return st
end

-- Abbau 1 Punkt je DecayEvery Sekunden (stetig, ohne Schleife)
local function decay(s: Suspicion)
	local now = os.clock()
	local every = math.max(1, tonumber(SEC.DecayEvery) or 30)
	local amount = (now - s.T) / every
	s.T = now
	if amount > 0 then
		s.Score = math.max(0, s.Score - amount)
		s.Review = math.max(0, s.Review - amount)
	end
end

-- Wie oft kam dieser Grund in den letzten 60 s? (Zeitstempel-Liste begrenzt)
local function countRecent(s: Suspicion, key: string, now: number): number
	local list = s.Recent[key]
	if not list then
		list = {}
		s.Recent[key] = list
	end
	table.insert(list, now)
	while #list > RECENT_MAX or (list[1] ~= nil and now - list[1] > 60) do
		table.remove(list, 1)
	end
	return #list
end

local function reasonList(s: Suspicion): { string }
	local keys = Util.Snapshot(s.Counts)
	table.sort(keys, function(a, b)
		return s.Counts[a] > s.Counts[b]
	end)
	local out: { string } = {}
	for i, key in ipairs(keys) do
		if i > 8 then
			break
		end
		table.insert(out, ("%s ×%d"):format(key, s.Counts[key]))
	end
	return out
end

local function snapshotOf(p: Player): { [string]: any }
	local st = statsOf(p)
	local s = suspicionOf(p)
	decay(s)
	local minutes = math.max(1 / 60, (os.clock() - st.JoinedAt) / 60)
	local rejects: { [string]: number } = table.clone(s.Counts)
	return {
		HeadPct = if st.Hits > 0 then round(st.Heads / st.Hits * 100) else 0,
		Accuracy = if st.Shots > 0 then round(st.ShotsHit / st.Shots * 100) else 0,
		PopsPerMin = round(st.Pops / minutes, 2),
		Hits = st.Hits,
		Shots = st.Shots,
		Pops = st.Pops,
		Score = round(s.Score),
		Review = round(s.Review),
		Rejects = rejects,
		Minutes = round(minutes, 1),
	}
end

-- Neues Prüf-Flag (lokal + Warteschlange zum Speichern)
local function raiseFlag(p: Player, s: Suspicion, why: string, force: boolean?)
	local now = os.clock()
	if not force and now - s.FlagAt < (tonumber(SEC.FlagCooldown) or 300) then
		return
	end
	s.FlagAt = now
	local evidence = sanitizeEvidence(s.Evidence)
	evidence.Why = why
	local snap = snapshotOf(p)
	evidence.HeadPct = snap.HeadPct
	evidence.Accuracy = snap.Accuracy
	evidence.PopsPerMin = snap.PopsPerMin
	local flag: Flag = {
		Id = newId("F"),
		UserId = p.UserId,
		Name = p.Name,
		Score = round(s.Score + s.Review),
		Reasons = reasonList(s),
		Evidence = evidence,
		T = os.time(),
	}
	table.insert(localFlags, flag)
	while #localFlags > (SEC.FlagsLocalMax or 200) do
		table.remove(localFlags, 1)
	end
	table.insert(pendingFlags, flag)
	warn(("[AntiCheat] Prüf-Flag: %s (%d) – %s, Punkte %d"):format(p.Name, p.UserId, why, flag.Score))
end

local function playerData(p: Player): any
	local ok, data = call("DataService", "Get", p)
	if ok and type(data) == "table" then
		return data
	end
	return nil
end

-- Bann-Log (CC_Mod_v1 "BanLog", letzte 100) – yieldet
function AntiCheatService.LogBan(entry: BanEntry): boolean
	local clean: BanEntry = {
		UserId = math.floor(tonumber(entry.UserId) or 0),
		Name = string.sub(tostring(entry.Name or ""), 1, 40),
		Reason = string.sub(tostring(entry.Reason or ""), 1, 200),
		Duration = math.floor(tonumber(entry.Duration) or -1),
		By = math.floor(tonumber(entry.By) or 0),
		ByName = string.sub(tostring(entry.ByName or ""), 1, 40),
		T = math.floor(tonumber(entry.T) or os.time()),
		Active = entry.Active ~= false,
		Auto = entry.Auto == true,
	}
	table.insert(sessionBans, clean)
	while #sessionBans > (SEC.BanLogMax or 100) do
		table.remove(sessionBans, 1)
	end
	local max = math.floor(SEC.BanLogMax or 100)
	local ok = storeUpdate("BanLog", function(old)
		local list: { any } = if type(old) == "table" then old else {}
		table.insert(list, clean)
		while #list > max do
			table.remove(list, 1)
		end
		return list
	end)
	banLogCache = nil
	return ok
end

-- Bann-Log: gespeichert + diese Sitzung, neueste zuerst – yieldet (15 s Cache)
function AntiCheatService.BanLog(): { BanEntry }
	if not banLogCache or os.clock() - banLogAt > BANLOG_CACHE_SECONDS then
		local ok, stored = storeGet("BanLog")
		local list: { BanEntry } = {}
		if ok and type(stored) == "table" then
			for _, entry in ipairs(stored) do
				if type(entry) == "table" and Util.IsFinite(entry.UserId) then
					table.insert(list, entry)
				end
			end
		end
		banLogCache = list
		banLogAt = os.clock()
	end
	local merged: { BanEntry } = {}
	local seen: { [string]: boolean } = {}
	local function add(entry: BanEntry)
		local key = ("%d_%d"):format(entry.UserId, entry.T)
		if not seen[key] then
			seen[key] = true
			table.insert(merged, entry)
		end
	end
	for _, entry in ipairs(banLogCache or {}) do
		add(entry)
	end
	for _, entry in ipairs(sessionBans) do
		add(entry)
	end
	table.sort(merged, function(a, b)
		return a.T > b.T
	end)
	return merged
end

-- Nach dem Entbannen: Einträge dieses Spielers als "nicht mehr aktiv" markieren – yieldet
function AntiCheatService.MarkUnbanned(userId: number)
	for _, entry in ipairs(sessionBans) do
		if entry.UserId == userId then
			entry.Active = false
		end
	end
	storeUpdate("BanLog", function(old)
		if type(old) ~= "table" then
			return nil -- nichts zu ändern (UpdateAsync bricht ab)
		end
		for _, entry in ipairs(old) do
			if type(entry) == "table" and entry.UserId == userId then
				entry.Active = false
			end
		end
		return old
	end)
	banLogCache = nil
end

-- Automatischer 1-Tages-Bann (nur nach 3 harten Kicks in 7 Tagen) – yieldet
local function autoBan(p: Player, evidence: string): boolean
	if p.UserId <= 0 then
		warn("[AntiCheat] Auto-Bann im Studio-Test übersprungen: " .. p.Name)
		return false
	end
	local auto = SEC.AutoBan
	local seconds = math.max(60, math.floor((tonumber(auto.Days) or 1) * 86400))
	local display = string.sub(L(p, "admin.acBanReason"), 1, SEC.BanDisplayMax or 400)
	local ok, err = pcall(function()
		Players:BanAsync({
			UserIds = { p.UserId },
			Duration = seconds,
			DisplayReason = display,
			PrivateReason = string.sub(evidence, 1, SEC.BanPrivateMax or 1000),
			ApplyToUniverse = true,
			ExcludeAltAccounts = false,
		})
	end)
	if not ok then
		warn("[AntiCheat] Auto-Bann fehlgeschlagen: " .. tostring(err))
		return false
	end
	AntiCheatService.LogBan({
		UserId = p.UserId,
		Name = p.Name,
		Reason = display,
		Duration = seconds,
		By = 0,
		ByName = "AntiCheat",
		T = os.time(),
		Active = true,
		Auto = true,
	})
	return true
end

local function evidenceText(p: Player, s: Suspicion, why: string): string
	local snap = snapshotOf(p)
	local parts = {
		("AntiCheat %s (%d): %s"):format(p.Name, p.UserId, why),
		("Punkte %d"):format(round(s.Score)),
		"Gründe " .. table.concat(reasonList(s), ", "),
		("Kopf %d%%, Genauigkeit %d%%, Pops/min %.2f"):format(snap.HeadPct, snap.Accuracy, snap.PopsPerMin),
	}
	for key, value in pairs(sanitizeEvidence(s.Evidence)) do
		table.insert(parts, ("%s=%s"):format(key, tostring(value)))
	end
	return table.concat(parts, " | ")
end

-- Kick (≥ Kick-Punkte oder Honeypot). Harte Signale zählen für den Auto-Bann.
local function kick(p: Player, s: Suspicion, why: string)
	if s.Kicking or not p.Parent then
		return
	end
	s.Kicking = true
	local now = os.clock()
	local hard = s.HardAt ~= nil and now - (s.HardAt :: number) <= HARD_WINDOW
	s.Evidence.Kicked = true
	s.Evidence.Hard = hard
	raiseFlag(p, s, why, true)
	local shouldBan = false
	if hard then
		local data = playerData(p)
		if data then
			if type(data.Mod) ~= "table" then
				data.Mod = { Warnings = 0, HardKicks = {} }
			end
			local mod = data.Mod
			local auto = SEC.AutoBan
			local window = (tonumber(auto.WindowDays) or 7) * 86400
			local nowUtc = os.time()
			local kicks: { number } = {}
			if type(mod.HardKicks) == "table" then
				for _, stamp in ipairs(mod.HardKicks) do
					if Util.IsFinite(stamp) and nowUtc - stamp <= window then
						table.insert(kicks, stamp)
					end
				end
			end
			table.insert(kicks, nowUtc)
			while #kicks > (tonumber(auto.Keep) or 10) do
				table.remove(kicks, 1)
			end
			mod.HardKicks = kicks -- wird beim Verlassen mit dem Profil gespeichert
			shouldBan = auto.Enabled == true and #kicks >= (tonumber(auto.HardKicks) or 3)
		end
	end
	local message = L(p, "admin.acKick")
	local evidence = evidenceText(p, s, why)
	warn(("[AntiCheat] Kick %s (%d): %s%s"):format(p.Name, p.UserId, why, if shouldBan then " + 1-Tages-Bann" else ""))
	task.spawn(function()
		if shouldBan then
			autoBan(p, evidence)
		end
		if p.Parent then
			p:Kick(message)
		end
	end)
end

-- Kern: Punkte vergeben (Abbau, Minuten-Bursts, Flags, Kick)
local function addPoints(p: Player, reason: string, points: number, evidence: any)
	local key = normalizeReason(reason)
	local s = suspicionOf(p)
	decay(s)
	local now = os.clock()
	local weights = SEC.Weights
	s.Counts[key] = (s.Counts[key] or 0) + 1
	for k, v in pairs(sanitizeEvidence(evidence)) do
		s.Evidence[k] = v
	end
	s.Evidence.Last = key

	-- Statistik: nur Prüfliste, nie Kick/Bann
	if key == "Stats" then
		s.Review += points
		raiseFlag(p, s, "Stats", true)
		return
	end

	-- einzelne abgelehnte Treffer-Behauptung -> Mismatch-Quote
	if key == "Hitbox" then
		local st = statsOf(p)
		table.insert(st.Claims, false)
		while #st.Claims > (SEC.Stats.MismatchClaims or 30) do
			table.remove(st.Claims, 1)
		end
	end

	local extra = 0
	local hard = HARD_REASONS[key] == true
	if key == "Rate" then
		local n = countRecent(s, "Rate", now)
		if n > (SEC.RateBurstPerMinute or 20) and now - (s.BurstAt.Rate or -math.huge) >= 60 then
			s.BurstAt.Rate = now
			extra += tonumber(weights.RateBurst) or 15
			s.Counts.RateBurst = (s.Counts.RateBurst or 0) + 1
			hard = true
		end
	elseif key == "Los" then
		local n = countRecent(s, "Los", now)
		if n > (SEC.LosBurstPerMinute or 10) and now - (s.BurstAt.Los or -math.huge) >= 60 then
			s.BurstAt.Los = now
			extra += tonumber(weights.LosBurst) or 10
			s.Counts.LosBurst = (s.Counts.LosBurst or 0) + 1
		end
	end
	if hard then
		s.HardAt = now
	end
	s.Score += points + extra

	if key == "Honeypot" then
		kick(p, s, "Honeypot")
		return
	end
	if s.Score >= (tonumber(SEC.Kick) or 60) then
		kick(p, s, key)
	elseif s.Score >= (tonumber(SEC.Review) or 25) then
		raiseFlag(p, s, key, false)
	end
end

-- Mismatch-Quote prüfen (> 40 % abgelehnte Behauptungen über 30 Behauptungen -> +10)
local function checkMismatch(p: Player, st: ShotStats)
	local stats = SEC.Stats
	local needed = stats.MismatchClaims or 30
	if #st.Claims < needed then
		return
	end
	local misses = 0
	for _, ok in ipairs(st.Claims) do
		if not ok then
			misses += 1
		end
	end
	if misses / #st.Claims > (stats.MismatchRatio or 0.4) then
		table.clear(st.Claims)
		addPoints(p, "Mismatch", tonumber(SEC.Weights.Mismatch) or 10, { Misses = misses, Claims = needed })
	end
end

-- Statistik-Flag (nur Prüfliste): Kopf-Quote > 0.75 über ≥ 60 Treffer UND Genauigkeit > 0.70
local function checkStats(p: Player, st: ShotStats)
	if st.StatsFlagged then
		return
	end
	local stats = SEC.Stats
	if st.Hits < (stats.MinHits or 60) or st.Shots <= 0 then
		return
	end
	local headRatio = st.Heads / st.Hits
	local accuracy = st.ShotsHit / st.Shots
	if headRatio > (stats.HeadRatio or 0.75) and accuracy > (stats.Accuracy or 0.7) then
		st.StatsFlagged = true
		addPoints(p, "Stats", tonumber(SEC.Weights.Stats) or 20, {
			HeadRatio = headRatio,
			Accuracy = accuracy,
			Hits = st.Hits,
		})
	end
end

-- ---------------------------------------------------------------------
-- BEWEGUNG (C12.3)
-- Skill-Bewegung (docs/SKILL-WUENSCHE.md) ist ausdrücklich erlaubt und gibt NIE Fehlalarm:
--   * Rutsch-Sprung-Ketten: Rutschen startet mit 32 Studs/s, Rutsch-Sprung behält 90 % (Obergrenze 30) ->
--     immer unter dem Budget 32 × SpeedMult × 1.15 + 6 (= 42.8 Studs/s bei SpeedMult 1).
--   * Doppelsprung + Wand-Absprung (einmal pro Sprung): zählen immer als SkillAirJumps (2) Luftsprünge.
--   * Schwerkraft-Lift (Mondsprung-Mutator, Lobby-Schwerkraft): Höhe und Luftzeit wachsen mit.
--   * Kontext-Regeln (Turbo, Nahkampf-Chaos, BaseSpeed) werden selbst gelesen – auch ohne SetAllowance.
-- ---------------------------------------------------------------------
type Effective = { SpeedMult: number, VerticalMult: number, AirJumps: number, Moon: boolean }

local function capacityFor(track: Track, now: number): (number, number)
	local speedMult = math.max(track.Allowance.SpeedMult, track.EffSpeed)
	local rate = SEC.BaseAllowedSpeed * speedMult * SEC.SpeedTolerance + SEC.SpeedSlack
	if now < track.ImpulseUntil then
		rate = math.max(rate, track.ImpulseSpeed)
	end
	return rate, rate * SEC.BucketSeconds
end

-- Weniger Schwerkraft (workspace.Gravity oder Lobby-Schwerkraft des Admin-Panels) = höhere/längere Sprünge erlaubt.
-- Die Lobby-Schwerkraft ist eine Server-VectorForce "CC_LobbyGravity" am HRP (vom AdminService angelegt).
local function gravityFactor(root: BasePart): number
	local g = workspace.Gravity
	local effective = g
	local lift = root:FindFirstChild("CC_LobbyGravity")
	if lift and lift:IsA("VectorForce") then
		effective = g - lift.Force.Y / math.max(0.1, root.AssemblyMass)
	end
	return math.max(1, DEFAULT_GRAVITY / math.max(10, effective), g / math.max(10, effective))
end

-- Boxhandschuhe ausgerüstet = 1 Luftsprung (B11.4) – nur nötig, wenn SkillAirJumps auf 0 gestellt wurde
local function glovesAirJumps(c: any): number
	if type(c) ~= "table" or c.Equipped ~= "Melee" or type(c.Loadout) ~= "table" then
		return 0
	end
	local def: any = Config.Weapon(c.Loadout.Melee)
	if def and type(def.Melee) == "table" and def.Melee.AirJump then
		return 1
	end
	return 0
end

-- Erlaubnis = max(SetAllowance, Kontext-Regeln, BaseSpeed-Attribut) + Skill-Luftsprünge
local function effectiveAllowance(p: Player, track: Track, character: Model): Effective
	local a = track.Allowance
	local speed, vertical = a.SpeedMult, a.VerticalMult
	local moon = false
	local okC, c = call("CombatService", "OfPlayer", p)
	if not okC then
		c = nil
	end
	if type(c) == "table" and type(c.Ctx) == "string" then
		local okX, info = call("CombatService", "Context", c.Ctx)
		local rules = if okX and type(info) == "table" then info.Rules else nil
		if type(rules) == "table" then
			if Util.IsFinite(rules.SpeedMult) then
				speed = math.max(speed, rules.SpeedMult)
			end
			if Util.IsFinite(rules.GravityLift) and rules.GravityLift > 0 then
				local lift = math.clamp(rules.GravityLift, 0, 0.9)
				vertical = math.max(vertical, tonumber(SEC.MoonVerticalMult) or 2.5, 1 / (1 - lift))
				moon = true
			end
		end
	end
	local walk = tonumber(Config.Player.Walk) or 16
	local base = character:GetAttribute("BaseSpeed")
	if base == nil then
		base = p:GetAttribute("BaseSpeed")
	end
	if Util.IsFinite(base) and base > walk then
		speed = math.max(speed, base / walk)
	end
	local airJumps = math.max(a.AirJumps, math.floor(tonumber(SEC.SkillAirJumps) or 0))
	if airJumps < 1 then
		airJumps = math.max(airJumps, glovesAirJumps(c))
	end
	return {
		SpeedMult = math.clamp(speed, 0.5, 5),
		VerticalMult = vertical,
		AirJumps = airJumps,
		Moon = moon or vertical >= 2,
	}
end

local function inVault(p: Player): boolean
	local ok, result = call("CharacterService", "InVault", p)
	if ok and result == true then
		return true
	end
	local okC, c = call("CombatService", "OfPlayer", p)
	return okC and type(c) == "table" and c.Alive == false
end

local function newTrack(): Track
	local probe = RaycastParams.new()
	probe.FilterType = Enum.RaycastFilterType.Exclude
	probe.RespectCanCollide = true
	probe.IgnoreWater = true
	return {
		Character = nil,
		Pos = nil,
		ValidCF = nil,
		GroundCF = nil,
		Time = os.clock(),
		Budget = 0,
		GraceUntil = 0,
		Anchor = nil,
		ImpulseUntil = 0,
		ImpulseSpeed = 0,
		ExemptUntil = 0,
		GroundY = nil,
		AirSince = nil,
		LastY = nil,
		StillSince = os.clock(),
		LastRaw = nil,
		LastSpeed = 0,
		EffSpeed = 1,
		Allowance = { SpeedMult = 1, VerticalMult = 1, AirJumps = 0 },
		Probe = probe,
	}
end

local function trackOf(p: Player): Track
	local track = tracks[p]
	if not track then
		track = newTrack()
		tracks[p] = track
		if not table.find(trackedList, p) then
			table.insert(trackedList, p)
		end
	end
	return track
end

-- Messung übernehmen; full = auch Boden/Luftzeit zurücksetzen (Gnade, Ausnahme, neuer Character)
local function accept(track: Track, root: BasePart, now: number, full: boolean)
	local pos = root.Position
	local _, capacity = capacityFor(track, now)
	track.Pos = pos
	track.ValidCF = root.CFrame
	track.Time = now
	track.Budget = capacity
	track.LastY = pos.Y
	if full then
		track.GroundY = pos.Y
		track.GroundCF = root.CFrame
		track.AirSince = nil
	end
end

local function setCharacter(track: Track, character: Model)
	track.Character = character
	track.Probe.ExcludeInstances = { character }
	track.Pos = nil
	track.ValidCF = nil
	track.GroundCF = nil
	track.GroundY = nil
	track.AirSince = nil
	track.LastRaw = nil
	track.LastSpeed = 0
	track.GraceUntil = os.clock() + (SEC.TeleportGrace or 1)
	track.Anchor = nil
	excludesDirty = true
end

local function refreshExcludes()
	if not excludesDirty then
		return
	end
	excludesDirty = false
	local list: { Instance } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, bot in ipairs(CollectionService:GetTagged("Bot")) do
		table.insert(list, bot)
	end
	wallParams.ExcludeInstances = list
end

-- Treffer, die kein Noclip sind: VIP-Tür für VIPs (lokal offen), Puppen/Bots/Combatants
local function ignorableHit(p: Player, inst: Instance): boolean
	if inst.Name == "VipDoor" and (p:GetAttribute("Vip") == true or p:GetAttribute("VIP") == true) then
		return true
	end
	local model = inst:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:GetAttribute("CombatantId") ~= nil
end

-- Echtes Durchqueren: Start und Ende liegen auf GEGENÜBERLIEGENDEN Seiten des Teils und auf den anderen
-- Achsen innerhalb seiner Ausdehnung (Ecken schneiden, Kanten hochziehen und Wand-Absprung zählen nicht).
local function crossesThrough(part: BasePart, from: Vector3, to: Vector3): boolean
	local a = part.CFrame:PointToObjectSpace(from)
	local b = part.CFrame:PointToObjectSpace(to)
	local half = part.Size * 0.5
	local axes = { { a.X, b.X, half.X }, { a.Y, b.Y, half.Y }, { a.Z, b.Z, half.Z } }
	for i, axis in ipairs(axes) do
		local opposite = (axis[1] > axis[3] and axis[2] < -axis[3]) or (axis[1] < -axis[3] and axis[2] > axis[3])
		if opposite then
			local inside = true
			for j, other in ipairs(axes) do
				if j ~= i then
					local margin = other[3] + 1
					if math.abs(other[1]) > margin or math.abs(other[2]) > margin then
						inside = false
					end
				end
			end
			if inside then
				return true
			end
		end
	end
	return false
end

local function throughWall(p: Player, root: BasePart, from: Vector3, to: Vector3): (boolean, string?)
	refreshExcludes()
	wallParams.CollisionGroup = root.CollisionGroup
	local origin = from
	local direction = to - from
	for _ = 1, 3 do
		local length = direction.Magnitude
		if length < 0.05 then
			return false, nil
		end
		local result = workspace:Raycast(origin, direction, wallParams)
		if not result then
			return false, nil
		end
		local inst = result.Instance
		if not ignorableHit(p, inst) and inst:IsA("BasePart") and crossesThrough(inst, from, to) then
			return true, inst.Name
		end
		-- hinter dem Treffer weitersuchen
		local travelled = (result.Position - origin).Magnitude + 0.05
		local remaining = length - travelled
		if remaining <= 0.05 then
			return false, nil
		end
		local unit = direction.Unit
		origin += unit * travelled
		direction = unit * remaining
	end
	return false, nil
end

local function isGrounded(track: Track, root: BasePart, humanoid: Humanoid): boolean
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		return true
	end
	local probe = math.max(humanoid.HipHeight + root.Size.Y * 0.5, 3) + 2
	track.Probe.CollisionGroup = root.CollisionGroup
	local result = workspace:Spherecast(root.Position, 1, Vector3.new(0, -(probe - 1), 0), track.Probe)
	return result ~= nil
end

-- Auf eine sichere CFrame zurücksetzen (Verstoß) – mit Teleport-Gnade
local function resetTo(p: Player, track: Track, cf: CFrame?)
	local character = p.Character
	if not character or not cf then
		return
	end
	local target: CFrame = cf
	local root = character:FindFirstChild("HumanoidRootPart")
	pcall(function()
		character:PivotTo(target)
		if root and root:IsA("BasePart") then
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end)
	AntiCheatService.NoteTeleport(p, target)
	track.Budget = 0
end

local function violation(p: Player, track: Track, key: string, evidence: { [string]: any }, vertical: boolean)
	local target = if vertical then (track.GroundCF or track.ValidCF) else track.ValidCF
	resetTo(p, track, target)
	addPoints(p, key, tonumber(SEC.Weights[key]) or 1, evidence)
end

local function horizontalSpeed(root: BasePart): number
	local v = root.AssemblyLinearVelocity
	return math.sqrt(v.X * v.X + v.Z * v.Z)
end

local function checkPlayer(p: Player, _dt: number)
	local track = tracks[p]
	if not track or not p.Parent then
		return
	end
	local character = p.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid then
		return
	end
	local now = os.clock()
	local pos = root.Position
	if track.Character ~= character then
		setCharacter(track, character)
	end

	-- Lag-Erkennung: Stand die gemeldete Position still, während der Spieler sich bewegte (eingefrorene
	-- Geschwindigkeit > 2)? Dann ist der Sprung danach Nachholen von Paketen, kein harter Teleport.
	local stalledFor = 0
	local raw = track.LastRaw
	if raw == nil or (pos - raw).Magnitude > 0.01 then
		if raw ~= nil then
			stalledFor = now - track.StillSince
		end
		track.LastRaw = pos
		track.StillSince = now
	end
	local stalled = stalledFor >= (tonumber(SEC.StallSeconds) or 0.6) and track.LastSpeed > 2
	track.LastSpeed = horizontalSpeed(root)

	-- Ausnahmen: tot, verankert (Prep/Einfrieren), Ausnahme-Zeit, Admin, Vault
	if humanoid.Health <= 0 or root.Anchored or now < track.ExemptUntil or isAdmin(p) or inVault(p) then
		accept(track, root, now, true)
		return
	end
	-- Teleport-Gnade: nur Positionen nahe am Ziel zählen (alte Pakete werden ignoriert)
	if now < track.GraceUntil then
		local anchor = track.Anchor
		local near = true
		if anchor then
			local ax, az = pos.X - anchor.X, pos.Z - anchor.Z
			near = ax * ax + az * az <= (SEC.AnchorRadius or 30) ^ 2
		end
		if near then
			accept(track, root, now, true)
		else
			track.Time = now
		end
		return
	end
	local last = track.Pos
	if not last then
		accept(track, root, now, true)
		return
	end

	local eff = effectiveAllowance(p, track, character)
	track.EffSpeed = eff.SpeedMult
	local impulse = now < track.ImpulseUntil
	local rate, capacity = capacityFor(track, now)
	local elapsed = math.clamp(now - track.Time, 0, 2)
	local dx, dz = pos.X - last.X, pos.Z - last.Z
	local dist = math.sqrt(dx * dx + dz * dz)

	-- 1) Teleport (> 40 Studs ohne Gnade) – hart, außer nach einem Lag-Hänger
	if dist > SEC.TeleportMaxDist and not impulse and not stalled then
		violation(p, track, "Teleport", { Dist = dist, From = last, To = pos }, false)
		return
	end
	-- 2) Weg-Budget (nach einem Hänger zählt die Zeit ohne Pakete, höchstens StallCredit Sekunden)
	local refill = rate * elapsed
	local cap = capacity
	if stalled then
		local credit = rate * math.min(stalledFor, tonumber(SEC.StallCredit) or 1.5)
		refill = math.max(refill, credit)
		cap = math.max(cap, credit)
	end
	local budget = math.min(cap, track.Budget + refill) - dist
	if budget < 0 then
		violation(p, track, "Speed", { Dist = dist, Rate = rate, Dt = elapsed, Stall = stalledFor }, false)
		return
	end
	budget = math.min(budget, capacity)
	-- 3) Noclip (Strahl zwischen den Messungen gegen feste Geometrie)
	if dist > 0.5 then
		local through, partName = throughWall(p, root, last, pos)
		if through then
			violation(p, track, "Noclip", { From = last, To = pos, Part = partName }, false)
			return
		end
	end
	-- 4) Höhe und Fliegen
	local grounded = isGrounded(track, root, humanoid)
	if impulse then
		-- Raketensprung/Rückstoß: höchsten Punkt merken, Luftzeit zählt erst nach der Gnade
		track.GroundY = math.max(track.GroundY or pos.Y, pos.Y)
		track.AirSince = if grounded then nil else now
		if grounded then
			track.GroundCF = root.CFrame
		end
	elseif grounded then
		track.GroundY = pos.Y
		track.GroundCF = root.CFrame
		track.AirSince = nil
	else
		local factor = gravityFactor(root)
		local airSince: number = track.AirSince or now
		track.AirSince = airSince
		local jumpHeight = tonumber(Config.Player.JumpHeight) or 7.2
		local maxHeight = jumpHeight * (eff.AirJumps + 1) * eff.VerticalMult * factor + SEC.VerticalSlack
		local height = pos.Y - (track.GroundY or pos.Y)
		if height > maxHeight then
			violation(p, track, "Fly", { Height = height, Max = maxHeight }, true)
			return
		end
		local airLimit = (if eff.Moon then SEC.FlyAirSecondsMoon else SEC.FlyAirSeconds) * factor
		local lastY = track.LastY
		local falling = lastY ~= nil and pos.Y < lastY - 0.25
		if now - airSince > airLimit and not falling then
			violation(p, track, "Fly", { Air = now - airSince, Limit = airLimit }, true)
			return
		end
	end
	track.Pos = pos
	track.ValidCF = root.CFrame
	track.Time = now
	track.Budget = budget
	track.LastY = pos.Y
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICHE API (C5.7)
-- ---------------------------------------------------------------------
function AntiCheatService.NoteTeleport(p: Player, cf: CFrame)
	if typeof(p) ~= "Instance" or not p:IsA("Player") or typeof(cf) ~= "CFrame" then
		return
	end
	local track = trackOf(p)
	local now = os.clock()
	local _, capacity = capacityFor(track, now)
	track.GraceUntil = now + (SEC.TeleportGrace or 1)
	track.Anchor = cf.Position
	track.Pos = cf.Position
	track.ValidCF = cf
	track.GroundCF = cf
	track.GroundY = cf.Position.Y
	track.AirSince = nil
	track.LastY = cf.Position.Y
	track.Time = now
	track.Budget = capacity
end

function AntiCheatService.Grace(p: Player, kind: "Impulse" | "Launch" | "Teleport", seconds: number, maxSpeed: number?)
	if typeof(p) ~= "Instance" or not p:IsA("Player") then
		return
	end
	local track = trackOf(p)
	local now = os.clock()
	local duration = if Util.IsFinite(seconds) then math.clamp(seconds, 0, 30) else (SEC.ImpulseGrace or 1.5)
	if kind == "Teleport" then
		track.GraceUntil = math.max(track.GraceUntil, now + duration)
		track.Anchor = nil -- Ziel unbekannt: jede Position gilt
		return
	end
	local speed = if Util.IsFinite(maxSpeed) then math.clamp(maxSpeed :: number, 0, 500) else nil
	speed = speed or tonumber(Config.Combat.ImpulseMaxSpeed) or SEC.ImpulseMaxSpeed or 95
	if now < track.ImpulseUntil then
		track.ImpulseSpeed = math.max(track.ImpulseSpeed, speed :: number)
	else
		track.ImpulseSpeed = speed :: number
	end
	track.ImpulseUntil = math.max(track.ImpulseUntil, now + duration)
	track.Budget = math.max(track.Budget, track.ImpulseSpeed * SEC.BucketSeconds)
end

function AntiCheatService.SetAllowance(p: Player, a: { SpeedMult: number?, VerticalMult: number?, AirJumps: number? })
	if typeof(p) ~= "Instance" or not p:IsA("Player") then
		return
	end
	local raw: any = if type(a) == "table" then a else {}
	local track = trackOf(p)
	track.Allowance = {
		SpeedMult = if Util.IsFinite(raw.SpeedMult) then math.clamp(raw.SpeedMult, 0.5, 5) else 1,
		VerticalMult = if Util.IsFinite(raw.VerticalMult) then math.clamp(raw.VerticalMult, 0.5, 10) else 1,
		AirJumps = if Util.IsFinite(raw.AirJumps) then math.clamp(math.floor(raw.AirJumps), 0, 5) else 0,
	}
end

function AntiCheatService.Exempt(p: Player, seconds: number)
	if typeof(p) ~= "Instance" or not p:IsA("Player") then
		return
	end
	local track = trackOf(p)
	local duration = if Util.IsFinite(seconds) then math.clamp(seconds, 0, 86400) else 0
	track.ExemptUntil = os.clock() + duration -- letzter Aufruf gewinnt (0 = Ausnahme beenden)
end

function AntiCheatService.Add(p: Player, reason: string, points: number, evidence: { [string]: any }?)
	if typeof(p) ~= "Instance" or not p:IsA("Player") or not p.Parent then
		return
	end
	local amount = if Util.IsFinite(points) then math.clamp(points, 0, 1000) else 0
	local key = normalizeReason(reason)
	if isAdmin(p) then
		-- Admins sind ausgenommen (Honeypot wird trotzdem protokolliert, aber ohne Kick)
		if key == "Honeypot" then
			warn(("[AntiCheat] Honeypot von Admin %s ausgelöst – kein Kick (Admin)."):format(p.Name))
		end
		return
	end
	addPoints(p, key, amount, evidence)
end

function AntiCheatService.Score(p: Player): number
	local s = suspicions[p]
	if not s then
		return 0
	end
	decay(s)
	return round(s.Score, 1)
end

-- Prüf-Flags dieses Servers (Kopie, neueste zuerst)
function AntiCheatService.Flags(): { Flag }
	local list: { Flag } = {}
	for i = #localFlags, 1, -1 do
		local flag = localFlags[i]
		if not dismissed[flag.Id] then
			table.insert(list, flag)
		end
	end
	return list
end

-- ---------------------------------------------------------------------
-- ZUSATZ-API (AdminService)
-- ---------------------------------------------------------------------
function AntiCheatService.Snapshot(p: Player): { [string]: any }
	return snapshotOf(p)
end

function AntiCheatService.Reports(): { Report }
	local list: { Report } = {}
	for i = #localReports, 1, -1 do
		local report = localReports[i]
		if not dismissed[report.Id] then
			table.insert(list, report)
		end
	end
	return list
end

-- Gespeicherte Einträge (Prefix "F" oder "R") der letzten "days" Tage aller Shards – yieldet
local function storedEntries(prefix: string, days: number): { any }
	local cacheKey = prefix .. tostring(days)
	local cached = storedCache[cacheKey]
	if cached and os.clock() - cached.T < STORE_CACHE_SECONDS then
		return cached.List
	end
	local list: { any } = {}
	if getStore() then
		local shards = math.max(1, math.floor(tonumber(Config.Tech.Shards) or 8))
		local today = utcDay()
		local gap = tonumber(SEC.StoreReadGap) or 0.25
		local first = true
		for d = 0, days - 1 do
			for s = 0, shards - 1 do
				if storeDisabled then
					break
				end
				if not first then
					task.wait(gap)
				end
				first = false
				local ok, value = storeGet(("%s_%s_%d"):format(prefix, dateKey(today - d), s))
				if ok and type(value) == "table" then
					for _, entry in ipairs(value) do
						if type(entry) == "table" and type(entry.Id) == "string" then
							table.insert(list, entry)
						end
					end
				end
			end
		end
	end
	storedCache[cacheKey] = { T = os.clock(), List = list }
	return list
end

local function mergeWithLocal(localList: { any }, stored: { any }): { any }
	local out: { any } = {}
	local seen: { [string]: boolean } = {}
	for _, entry in ipairs(localList) do
		if not seen[entry.Id] and not dismissed[entry.Id] then
			seen[entry.Id] = true
			table.insert(out, entry)
		end
	end
	for _, entry in ipairs(stored) do
		if not seen[entry.Id] and not dismissed[entry.Id] and entry.Dismissed ~= true then
			seen[entry.Id] = true
			table.insert(out, entry)
		end
	end
	table.sort(out, function(a, b)
		return (tonumber(a.T) or 0) > (tonumber(b.T) or 0)
	end)
	while #out > (SEC.FlagsLocalMax or 200) do
		table.remove(out)
	end
	return out
end

function AntiCheatService.AllFlags(days: number?): { Flag }
	local count = math.clamp(math.floor(tonumber(days) or 2), 1, 7)
	return mergeWithLocal(AntiCheatService.Flags(), storedEntries("F", count))
end

function AntiCheatService.AllReports(days: number?): { Report }
	local count = math.clamp(math.floor(tonumber(days) or 2), 1, 7)
	return mergeWithLocal(AntiCheatService.Reports(), storedEntries("R", count))
end

-- Flag oder Meldung abweisen (lokal + im gespeicherten Shard) – yieldet
function AntiCheatService.Dismiss(id: string): boolean
	if type(id) ~= "string" or #id > 80 then
		return false
	end
	dismissed[id] = true
	for _, list in ipairs({ localFlags, localReports, pendingFlags, pendingReports } :: { { any } }) do
		for i = #list, 1, -1 do
			if list[i].Id == id then
				table.remove(list, i)
			end
		end
	end
	local colon = string.find(id, ":", 1, true)
	local key = if colon then string.sub(id, 1, colon - 1) else nil
	if key and string.match(key, "^[FR]_%d+_%d+$") then
		storeUpdate(key, function(old)
			if type(old) ~= "table" then
				return nil
			end
			local kept: { any } = {}
			for _, entry in ipairs(old) do
				if type(entry) == "table" and entry.Id ~= id then
					table.insert(kept, entry)
				end
			end
			return kept
		end)
	end
	table.clear(storedCache)
	return true
end

-- ---------------------------------------------------------------------
-- HONEYPOT & MELDEN
-- ---------------------------------------------------------------------
local function onHoneypot(p: Player, ...: any)
	if honeypotHit[p] then
		return
	end
	local args = table.pack(...)
	if not isAdmin(p) then
		honeypotHit[p] = true
	end
	AntiCheatService.Add(p, "Honeypot", tonumber(SEC.Weights.Honeypot) or 100, {
		Remote = "GrantCoins",
		Args = args.n,
		First = if args.n > 0 then sanitizeValue(args[1]) else "-",
	})
end

local function onReport(p: Player, arg: any): Types.Reply
	if type(arg) ~= "table" then
		return { Ok = false, Message = L(p, "core.invalid") }
	end
	local userId = arg.UserId
	local reason = arg.Reason
	if not Util.IsFinite(userId) or userId % 1 ~= 0 or type(reason) ~= "string" or not REPORT_REASONS[reason] then
		return { Ok = false, Message = L(p, "core.invalid") }
	end
	if userId == p.UserId then
		return { Ok = false, Message = L(p, "admin.reportSelf") }
	end
	local target = Players:GetPlayerByUserId(userId)
	if not target then
		return { Ok = false, Message = L(p, "admin.reportGone") }
	end
	local report: Report = {
		Id = newId("R"),
		From = p.UserId,
		FromName = p.Name,
		UserId = target.UserId,
		Name = target.Name,
		Reason = reason,
		Snapshot = snapshotOf(target),
		T = os.time(),
	}
	table.insert(localReports, report)
	while #localReports > (SEC.FlagsLocalMax or 200) do
		table.remove(localReports, 1)
	end
	table.insert(pendingReports, report)
	return { Ok = true, Message = L(p, "admin.reportThanks") }
end

-- ---------------------------------------------------------------------
-- LEBENSZYKLUS
-- ---------------------------------------------------------------------
function AntiCheatService.Init(services: any)
	Services = services
end

function AntiCheatService.Start()
	local function onPlayer(p: Player)
		local track = trackOf(p)
		suspicionOf(p)
		statsOf(p)
		p.CharacterAdded:Connect(function(character)
			setCharacter(track, character)
		end)
		p.CharacterRemoving:Connect(function()
			excludesDirty = true
		end)
		if p.Character then
			setCharacter(track, p.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayer, p)
	end
	Players.PlayerRemoving:Connect(function(p)
		tracks[p] = nil
		suspicions[p] = nil
		shotStats[p] = nil
		honeypotHit[p] = nil
		local index = table.find(trackedList, p)
		if index then
			table.remove(trackedList, index)
		end
		excludesDirty = true
	end)
	CollectionService:GetInstanceAddedSignal("Bot"):Connect(function()
		excludesDirty = true
	end)
	CollectionService:GetInstanceRemovedSignal("Bot"):Connect(function()
		excludesDirty = true
	end)

	-- Honeypot: unser Code feuert "GrantCoins" NIE – jeder Aufruf ist ein Exploit
	local honeypot = Remotes.GrantCoins
	if honeypot and typeof(honeypot) == "Instance" and honeypot:IsA("RemoteEvent") then
		honeypot.OnServerEvent:Connect(onHoneypot)
	else
		warn("[AntiCheat] Remote GrantCoins fehlt – Honeypot inaktiv")
	end

	-- Request "Report" (3 pro 10 Minuten)
	local limit = SEC.ReportLimit or { 3, 600 }
	local okHandle = call("PlayerStateService", "Handle", "Report", onReport, { Rate = limit[1], Per = limit[2] })
	if not okHandle then
		warn("[AntiCheat] Request 'Report' konnte nicht registriert werden (PlayerStateService fehlt)")
	end

	-- Schuss-Statistik (Genauigkeit, Kopf-Quote, Mismatch-Quote) – nur Menschen, keine Admins
	call("WeaponService", "OnShot", function(c: any, _def: any, hits: number, heads: number)
		if type(c) ~= "table" or c.Kind ~= "Player" then
			return
		end
		local p = c.Player
		if typeof(p) ~= "Instance" or not p:IsA("Player") or not p.Parent or isAdmin(p) then
			return
		end
		local st = statsOf(p)
		local h = if Util.IsFinite(hits) then math.max(0, math.floor(hits)) else 0
		local hd = if Util.IsFinite(heads) then math.clamp(math.floor(heads), 0, h) else 0
		st.Shots += 1
		st.Hits += h
		st.Heads += hd
		if h > 0 then
			st.ShotsHit += 1
			for _ = 1, math.min(h, 16) do
				table.insert(st.Claims, true)
			end
			while #st.Claims > (SEC.Stats.MismatchClaims or 30) do
				table.remove(st.Claims, 1)
			end
		end
		checkMismatch(p, st)
		checkStats(p, st)
	end)
	call("CombatService", "OnElimination", function(_victim: any, killer: any, _info: any)
		if type(killer) == "table" and killer.Kind == "Player" then
			local p = killer.Player
			if typeof(p) == "Instance" and p:IsA("Player") and p.Parent then
				statsOf(p).Pops += 1
			end
		end
	end)

	-- Bewegung 5 Hz gestaffelt; Speichern der Flags/Meldungen höchstens StoreWritesPerMinute pro Minute
	Scheduler.Staggered("AntiCheatMove", SEC.MoveHz or 5, function()
		return trackedList
	end, checkPlayer)
	Scheduler.Every("AntiCheatStore", (SEC.StoreWritesPerMinute or 6) / 60, flushStores)
	game:BindToClose(function()
		if #pendingFlags > 0 or #pendingReports > 0 then
			pcall(flushPending, pendingFlags, "F")
			pcall(flushPending, pendingReports, "R")
		end
	end)
end

return AntiCheatService
