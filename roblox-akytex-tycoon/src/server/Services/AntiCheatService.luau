-- =====================================================================
--  AKYTEX TYCOON – Anti-Cheat, schlank (Server/Services/AntiCheatService)
--  Besitzer: WP11 (Admin, Events, Anti-Cheat). Vertrag: DESIGN.md §C5.10, §C11 (Sicherheit), §C11.3 (Bewegung &
--  Erlaubnisse), §C9 ("Report"), §C8 (Honeypot "GrantCash"), §C13 (AT_Mod_v1). Basis: CLUTCH-CLASH-AntiCheatService
--  (REUSE §3.14 ADAPT): Verdachts-Modell, Flags/Meldungen/Bann-Log, Honeypot, present(p)-Guard und das gestaffelte
--  5-Hz-Bewegungsbudget bleiben; Schuss-Statistik, Sichtlinien und Kampf-Kontexte sind entfernt.
--
--  Grundsätze (§C11.1): Wirtschafts-Schummeln verhindert die Server-Autorität (Kurse, Fills, Einkommen, Pickups liegen
--  alle auf dem Server) – NICHT dieser Dienst. Hier geht es nur um Bewegung (Privatsphäre der Tower, verschlossene
--  Türen, Pickup-Reichweite) und gefälschte Remotes. Schaden zuerst verhindern (Zurücksetzen auf die letzte gültige
--  Position), Verdacht aus mehreren Signalen, nur harte Signale eskalieren (3 harte Kicks in 7 Tagen = 1-Tages-Bann).
--
--  Bewegung (§C11.3, 5 Hz gestaffelt über Lib/Scheduler):
--    Weg-Budget (32 × SpeedMult × 1,15 + 6 Studs/s, Vorrat 1 s) · Teleport > 40 Studs ohne Gnade (bei Autos mit dem
--    Tempo skaliert) · Höhe über letztem Bodenkontakt · Fliegen (> 3 s Luft ohne Fallen) · Noclip (Strahl zwischen zwei
--    Messungen, nur echtes Durchqueren einer Wand; lokal geöffnete/versteckte Teile werden ignoriert).
--    Erlaubnisse: Auto (VehicleService: SetAllowance{ MaxSpeed = Klassen-Deckel × Boost × 1,2 }), Aufzug/Teleport
--    (NoteTeleport: 1 s Gnade + Ziel-Anker), Jetpack (SetAllowance{ SpeedMult, VerticalMult } nur aktiv), Admin-Fly/
--    Noclip (ausgenommen: Besitzer und Teammitglieder mit Recht Fly/Noclip – StaffService.MoveExempt), Impulse (Grace
--    "Impulse"/"Launch" mit Tempo bis zur Landung). Punkte (Add) und Honeypot nehmen NUR den Besitzer aus.
--  Verdacht: Gewichte aus Config.Security.Weights, Abbau 1 Punkt je 30 s, ≥ 25 Prüf-Flag (AT_Mod_v1 F_<yyyymmdd>_<shard>),
--    ≥ 60 Kick. Honeypot-Remote "GrantCash" = +100, Kick, Flag (unser Code feuert ihn NIE).
--  Meldungen (Request "Report" {UserId, Reason, Note?} und Chat /report über SubmitReport, gemeinsam 3 pro 10 min): Server
--    hängt einen Schnappschuss an (R_<yyyymmdd>_<shard>), Notiz gefiltert, Teammitglieder werden benachrichtigt
--    (StaffService.OnReport). Auto-Bann landet zusätzlich in der eigenen Bann-Liste (StaffService.AddBan, Src "Auto").
--
--  Öffentliche API (§C5.10):
--    AntiCheatService.NoteTeleport(p, cf)                              1 s Gnade nach einem Server-Teleport
--    AntiCheatService.Grace(p, "Impulse" | "Launch" | "Teleport", seconds, maxSpeed?)
--    AntiCheatService.SetAllowance(p, { SpeedMult?, VerticalMult?, MaxSpeed? }?)   ersetzt die alte Erlaubnis (nil = Standard)
--    AntiCheatService.Exempt(p, seconds)                               0 = Ausnahme beenden
--    AntiCheatService.Add(p, reason, points, evidence?)
--    AntiCheatService.Score(p): number      AntiCheatService.Flags(): { Flag }      AntiCheatService.Snapshot(p)
--  Zusatz (AdminService, gleiche Namen wie CC):
--    AntiCheatService.Reports() · AllFlags(days?) · AllReports(days?) · Dismiss(id): (true, entry?) · LogBan(entry) ·
--    BanLog() · MarkUnbanned(userId) · Stats(): { Tracked, Flags, Reports, Kicks }  (AllFlags/AllReports/Dismiss/Bann-Log
--    yielden)
--  W19: AntiCheatService.SubmitReport(p, userId, reason, note?, via?): Reply   Menü ("Menu") und Chat /report ("Chat")
-- =====================================================================

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

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
local DEFAULT_JUMP_HEIGHT = 7.2
local MAX_EVIDENCE_KEYS = 12
local RECENT_MAX = 64 -- Zeitstempel pro Grund für die Minuten-Zählung
local STORE_CACHE_SECONDS = 60
local BANLOG_CACHE_SECONDS = 15
local MAX_ALLOWED_SPEED = 600 -- absolute Obergrenze jeder Erlaubnis (Studs/s)
local TELEPORT_SLACK = 1.5 -- Teleport-Schwelle mindestens 1,5 × erlaubter Weg seit der letzten Messung

-- Grund-Texte (auch Ablehnungs-Codes anderer WPs, egal ob groß/klein) -> Schlüssel in Weights
local REASON_KEYS: { [string]: string } = {
	honeypot = "Honeypot",
	type = "Type",
	rate = "Rate",
	rateburst = "RateBurst",
	speed = "Speed",
	teleport = "Teleport",
	fly = "Fly",
	noclip = "Noclip",
	car = "Car",
	tradespam = "Rate",
	pickup = "Type",
}

local REPORT_REASONS: { [string]: boolean } = { Speed = true, Fly = true, Exploit = true, Toxic = true, Other = true }

-- ---------------------------------------------------------------------
-- TYPEN
-- ---------------------------------------------------------------------
type Allowance = { SpeedMult: number, VerticalMult: number, MaxSpeed: number }

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
	ImpulseAirUntil: number, -- Impuls-Schwung in der Luft: Tempo-Erlaubnis bis zur Landung (höchstens bis hier)
	ExemptUntil: number,
	GroundY: number?,
	AirSince: number?,
	LastY: number?,
	StillSince: number, -- seit wann sich die Position nicht mehr bewegt hat (Lag-Erkennung)
	LastRaw: Vector3?,
	LastSpeed: number, -- waagrechte Geschwindigkeit bei der letzten Messung (eingefroren = Lag)
	Allowance: Allowance,
	GiftSpeed: number, -- Speed-Geschenk des Besitzers (Spieler-Attribut GiftSpeed, nur der Server setzt es), 0 = keins
	GiftJump: number, -- Sprung-Geschenk (Attribut GiftJump), 0 = keins
	Probe: RaycastParams,
	Violations: { [string]: number },
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
	JoinedAt: number,
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
	Note: string?, -- Freitext des Melders (gefiltert, ≤ Config.Security.Staff.ReportNoteMax Zeichen)
	Via: string?, -- "Menu" | "Chat"
	Job: string?, -- erste 8 Zeichen der JobId (welcher Server)
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
local honeypotHit: { [Player]: boolean } = {}

local localFlags: { Flag } = {}
local localReports: { Report } = {}
local pendingFlags: { Flag } = {}
local pendingReports: { Report } = {}
local dismissed: { [string]: boolean } = {}
local idCounter = 0
local kickCount = 0

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
-- Meldungen: EIN Limiter für Menü und Chat (/report), damit beide Wege zusammen höchstens ReportLimit erlauben
local reportRate = SEC.ReportLimit or { 3, 600 }
local reportLimiter = Util.RateLimiter(tonumber(reportRate[1]) or 3, tonumber(reportRate[2]) or 600)

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

-- Bewegungs-Ausnahme: Besitzer und Teammitglieder, die fliegen/noclippen dürfen (StaffService); fehlt der Dienst,
-- gilt die alte Regel (nur der Besitzer). Punkte/Honeypot nehmen weiter nur den Besitzer aus (isAdmin).
local function moveExempt(p: Player): boolean
	local ok, result = call("StaffService", "MoveExempt", p)
	if ok then
		return result == true
	end
	return isAdmin(p)
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

-- Auf höchstens maxBytes kürzen, ohne ein UTF-8-Zeichen zu zerschneiden (Bann-Gründe zählen Bytes)
local function truncate(text: string, maxBytes: number): string
	if #text <= maxBytes then
		return text
	end
	local cut = maxBytes
	for _ = 1, 4 do
		if cut <= 0 or utf8.len(string.sub(text, 1, cut)) ~= nil then
			break
		end
		cut -= 1
	end
	return string.sub(text, 1, math.max(0, cut))
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

-- Nur Spieler, die noch im Spiel sind (PlayerRemoving-Handler anderer Services rufen NoteTeleport/SetAllowance
-- evtl. NACH unserem Aufräumen auf -> sonst bliebe ein Track für immer liegen; REUSE §7 #2)
local function present(p: any): boolean
	return typeof(p) == "Instance" and p:IsA("Player") and p.Parent == Players
end

-- ---------------------------------------------------------------------
-- SPEICHER (AT_Mod_v1) – alles in pcall; Studio ohne API-Zugriff -> leise aus
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
		table.clear(storedCache)
	end
	while #pending > maxPerKey do
		table.remove(pending, 1)
	end
end

local function flushStores()
	if flushing or (#pendingFlags == 0 and #pendingReports == 0) then
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
			JoinedAt = os.clock(),
		}
		suspicions[p] = s
	end
	return s
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

-- Schnappschuss für Admin-Liste, Bann-Beweis und Meldungen (nur Bewegung/Verdacht – keine Kampf-Statistik)
local function snapshotOf(p: Player): { [string]: any }
	local s = suspicionOf(p)
	decay(s)
	local track = tracks[p]
	local minutes = math.max(1 / 60, (os.clock() - s.JoinedAt) / 60)
	local violations: { [string]: number } = if track then table.clone(track.Violations) else {}
	local allowance = if track then track.Allowance else nil
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	local speed = 0
	if root and root:IsA("BasePart") then
		local v = root.AssemblyLinearVelocity
		speed = round(math.sqrt(v.X * v.X + v.Z * v.Z), 1)
	end
	return {
		Score = round(s.Score),
		Review = round(s.Review),
		Rejects = table.clone(s.Counts),
		Violations = violations,
		Minutes = round(minutes, 1),
		Speed = speed,
		Allowance = if allowance
			then ("x%.2f/x%.1f/%d"):format(allowance.SpeedMult, allowance.VerticalMult, math.floor(allowance.MaxSpeed))
			else "-",
		AccountAge = p.AccountAge,
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
	while #pendingFlags > (SEC.FlagsLocalMax or 200) do
		table.remove(pendingFlags, 1)
	end
	warn(("[AntiCheat] Prüf-Flag: %s (%d) – %s, Punkte %d"):format(p.Name, p.UserId, why, flag.Score))
end

local function playerData(p: Player): any
	local ok, data = call("DataService", "Get", p)
	if ok and type(data) == "table" then
		return data
	end
	return nil
end

-- Bann-Log (AT_Mod_v1 "BanLog", letzte 100) – yieldet
function AntiCheatService.LogBan(entry: BanEntry): boolean
	if type(entry) ~= "table" then
		return false
	end
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
	if not Util.IsFinite(userId) then
		return
	end
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
	local display = truncate(L(p, "admin.acBanReason"), SEC.BanDisplayMax or 400)
	local ok, err = pcall(function()
		Players:BanAsync({
			UserIds = { p.UserId },
			Duration = seconds,
			DisplayReason = display,
			PrivateReason = truncate(evidence, SEC.BanPrivateMax or 1000),
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
	-- W26: auch in die eigene Bann-Liste (Tab „Banns“, /unban); By = 0 = Anti-Cheat
	call("StaffService", "AddBan", {
		UserId = p.UserId,
		Until = os.time() + seconds,
		Reason = display,
		By = 0,
		ByName = "Anti-Cheat",
		Name = p.Name,
		Src = "Auto",
	})
	return true
end

local function evidenceText(p: Player, s: Suspicion, why: string): string
	local snap = snapshotOf(p)
	local parts = {
		("AntiCheat %s (%d): %s"):format(p.Name, p.UserId, why),
		("Punkte %d"):format(round(s.Score)),
		"Gründe " .. table.concat(reasonList(s), ", "),
		("Tempo %s, Erlaubnis %s, Minuten %s"):format(
			tostring(snap.Speed),
			tostring(snap.Allowance),
			tostring(snap.Minutes)
		),
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
	kickCount += 1
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
				data.Mod = {}
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

-- ---------------------------------------------------------------------
-- BEWEGUNG (§C11.3)
-- ---------------------------------------------------------------------
local function capacityFor(track: Track, now: number): (number, number)
	local a = track.Allowance
	local rate = SEC.BaseAllowedSpeed * a.SpeedMult * SEC.SpeedTolerance + SEC.SpeedSlack
	if a.MaxSpeed > 0 then
		rate = math.max(rate, a.MaxSpeed) -- im Auto: Klassen-Deckel × Boost × Puffer (VehicleService)
	end
	if track.GiftSpeed > 0 then
		-- vom Besitzer geschenktes Lauf-Tempo (AdminService.GiveSpeed) – nie ein Fehlalarm für Beschenkte
		rate = math.max(rate, track.GiftSpeed * SEC.SpeedTolerance + SEC.SpeedSlack)
	end
	-- Impuls-Gnade, danach noch bis zur ersten Landung (der Client behält den Schwung in der Luft)
	if now < math.max(track.ImpulseUntil, track.ImpulseAirUntil) then
		rate = math.max(rate, track.ImpulseSpeed)
	end
	rate = math.min(rate, MAX_ALLOWED_SPEED)
	return rate, rate * SEC.BucketSeconds
end

-- Weniger Schwerkraft (workspace.Gravity) = höhere/längere Sprünge erlaubt
local function gravityFactor(): number
	local g = workspace.Gravity
	return math.max(1, DEFAULT_GRAVITY / math.max(10, g))
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
		ImpulseAirUntil = 0,
		ExemptUntil = 0,
		GroundY = nil,
		AirSince = nil,
		LastY = nil,
		StillSince = os.clock(),
		LastRaw = nil,
		LastSpeed = 0,
		Allowance = { SpeedMult = 1, VerticalMult = 1, MaxSpeed = 0 },
		GiftSpeed = 0,
		GiftJump = 0,
		Probe = probe,
		Violations = {},
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
	wallParams.ExcludeInstances = list
end

-- Treffer, die kein Noclip sind: lokal geöffnete Türen (VIP/Club), ausdrücklich markierte Teile, Fahrzeuge
local function ignorableHit(p: Player, inst: Instance): boolean
	local door = inst:GetAttribute("LocalDoor")
	if door ~= nil then
		-- WorldLook öffnet diese Türen nur lokal für Berechtigte (Spieler-Attribut Vip/Club)
		if type(door) == "string" and p:GetAttribute(door) == true then
			return true
		end
	end
	if inst:GetAttribute("NoclipIgnore") == true then
		return true
	end
	local model = inst:FindFirstAncestorOfClass("Model")
	if model and (model:GetAttribute("NoclipIgnore") == true or model:GetAttribute("Vehicle") ~= nil) then
		return true
	end
	return false
end

-- Echtes Durchqueren: Start und Ende liegen auf GEGENÜBERLIEGENDEN Seiten des Teils und auf den anderen
-- Achsen innerhalb seiner Ausdehnung (Ecken schneiden und Kanten hochziehen zählen nicht).
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

-- Steckt die Wurzel in Terrain-Wasser (Marina)? Schwimmen ist kein Fliegen (eine 4er-Voxel-Säule, billig)
local function inWater(pos: Vector3): boolean
	local terrain = workspace.Terrain
	local ok, inside = pcall(function()
		local region = Region3.new(pos - Vector3.new(1, 5, 1), pos + Vector3.new(1, 1, 1)):ExpandToGrid(4)
		local materials = terrain:ReadVoxels(region, 4)
		for x = 1, #materials do
			local column = materials[x]
			for y = 1, #column do
				local row = column[y]
				for z = 1, #row do
					if row[z] == Enum.Material.Water then
						return true
					end
				end
			end
		end
		return false
	end)
	return ok and inside == true
end

local function isGrounded(track: Track, root: BasePart, humanoid: Humanoid): boolean
	if humanoid.FloorMaterial ~= Enum.Material.Air or humanoid.SeatPart ~= nil then
		return true
	end
	if humanoid:GetState() == Enum.HumanoidStateType.Swimming or inWater(root.Position) then
		return true -- schwimmt (Marina): Höhe/Luftzeit messen erst wieder an Land
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
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.SeatPart ~= nil then
		return -- im Fahrzeug nie versetzen (Sitz-Schweißung würde das Auto mitreißen)
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
	track.Violations[key] = (track.Violations[key] or 0) + 1
	local target = if vertical then (track.GroundCF or track.ValidCF) else track.ValidCF
	resetTo(p, track, target)
	local weight = tonumber(SEC.Weights[key]) or 1
	-- Fahrzeug-Verstoß (schneller als der Klassen-Deckel) hat ein eigenes Gewicht
	if key == "Speed" and track.Allowance.MaxSpeed > 0 then
		weight = tonumber(SEC.Weights.Car) or weight
	end
	addPoints(p, key, weight, evidence)
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

	-- Lag-Erkennung: Stand die gemeldete Position still, während der Spieler sich bewegte? Dann ist der Sprung
	-- danach Nachholen von Paketen, kein harter Teleport.
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

	-- Ausnahmen: tot, verankert (Einfrieren/Zeremonie), Ausnahme-Zeit, Besitzer/Team mit Fly-/Noclip-Recht
	if humanoid.Health <= 0 or root.Anchored or now < track.ExemptUntil or moveExempt(p) then
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

	local giftSpeed = p:GetAttribute("GiftSpeed")
	local giftJump = p:GetAttribute("GiftJump")
	track.GiftSpeed = if Util.IsFinite(giftSpeed) then math.clamp(giftSpeed, 0, MAX_ALLOWED_SPEED) else 0
	track.GiftJump = if Util.IsFinite(giftJump) then math.clamp(giftJump, 0, 200) else 0

	local impulse = now < track.ImpulseUntil
	local grounded = isGrounded(track, root, humanoid)
	if not impulse and track.ImpulseAirUntil > 0 and (grounded or now >= track.ImpulseAirUntil) then
		track.ImpulseAirUntil = 0 -- gelandet (oder Obergrenze erreicht): ab jetzt normales Budget
	end
	local rate, capacity = capacityFor(track, now)
	local elapsed = math.clamp(now - track.Time, 0, 2)
	local dx, dz = pos.X - last.X, pos.Z - last.Z
	local dist = math.sqrt(dx * dx + dz * dz)

	-- 1) Teleport (> 40 Studs ohne Gnade; schnelle Erlaubnisse wie Autos heben die Schwelle) – hart, außer nach Lag
	local teleportLimit = math.max(SEC.TeleportMaxDist, rate * math.max(elapsed, 0.2) * TELEPORT_SLACK)
	if dist > teleportLimit and not impulse and not stalled then
		violation(p, track, "Teleport", { Dist = dist, Limit = teleportLimit, From = last, To = pos }, false)
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
	-- 3) Noclip (Strahl zwischen den Messungen gegen feste Geometrie; nicht im Fahrzeug)
	if dist > 0.5 and humanoid.SeatPart == nil then
		local through, partName = throughWall(p, root, last, pos)
		if through then
			violation(p, track, "Noclip", { From = last, To = pos, Part = partName }, false)
			return
		end
	end
	-- 4) Höhe und Fliegen (Jetpack: VerticalMult hebt Höhe und Luftzeit)
	local vertical = track.Allowance.VerticalMult
	if impulse then
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
		local factor = gravityFactor()
		local airSince: number = track.AirSince or now
		track.AirSince = airSince
		local jumpHeight = humanoid.JumpHeight
		if not Util.IsFinite(jumpHeight) or jumpHeight <= 0 then
			jumpHeight = DEFAULT_JUMP_HEIGHT
		end
		jumpHeight = math.min(jumpHeight, math.max(DEFAULT_JUMP_HEIGHT * 2, track.GiftJump)) -- Sprung-Geschenk zählt
		local maxHeight = jumpHeight * (SEC.SkillAirJumps + 1) * vertical * factor + SEC.VerticalSlack
		local height = pos.Y - (track.GroundY or pos.Y)
		if height > maxHeight then
			violation(p, track, "Fly", { Height = height, Max = maxHeight }, true)
			return
		end
		local airLimit = SEC.FlyAirSeconds * factor * math.max(1, vertical / 2)
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
-- ÖFFENTLICHE API (§C5.10)
-- ---------------------------------------------------------------------
function AntiCheatService.NoteTeleport(p: Player, cf: CFrame)
	if not present(p) or typeof(cf) ~= "CFrame" or not Util.IsFiniteVector(cf.Position) then
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
	if not present(p) then
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
	if kind ~= "Impulse" and kind ~= "Launch" then
		return
	end
	local speed: number = if Util.IsFinite(maxSpeed)
		then math.clamp(maxSpeed :: number, 0, MAX_ALLOWED_SPEED)
		else (tonumber(SEC.ImpulseMaxSpeed) or 95)
	if now < track.ImpulseUntil then
		track.ImpulseSpeed = math.max(track.ImpulseSpeed, speed)
	else
		track.ImpulseSpeed = speed
	end
	track.ImpulseUntil = math.max(track.ImpulseUntil, now + duration)
	track.ImpulseAirUntil = math.max(track.ImpulseAirUntil, track.ImpulseUntil + (tonumber(SEC.ImpulseAirSeconds) or 3))
	track.Budget = math.max(track.Budget, track.ImpulseSpeed * SEC.BucketSeconds)
end

function AntiCheatService.SetAllowance(p: Player, a: { SpeedMult: number?, VerticalMult: number?, MaxSpeed: number? }?)
	if not present(p) then
		return
	end
	local raw: any = if type(a) == "table" then a else {}
	local track = trackOf(p)
	local old = track.Allowance
	track.Allowance = {
		SpeedMult = if Util.IsFinite(raw.SpeedMult) then math.clamp(raw.SpeedMult, 0.5, 5) else 1,
		VerticalMult = if Util.IsFinite(raw.VerticalMult) then math.clamp(raw.VerticalMult, 0.5, 20) else 1,
		MaxSpeed = if Util.IsFinite(raw.MaxSpeed) then math.clamp(raw.MaxSpeed, 0, MAX_ALLOWED_SPEED) else 0,
	}
	-- Erlaubnis sinkt (Aussteigen, Jetpack aus): Schwung bis zur Landung behalten (kein Fehlalarm beim Ausrollen)
	local oldRate = SEC.BaseAllowedSpeed * old.SpeedMult * SEC.SpeedTolerance + SEC.SpeedSlack
	oldRate = math.max(oldRate, old.MaxSpeed)
	local _, newCapacity = capacityFor(track, os.clock())
	if oldRate > newCapacity / math.max(0.1, SEC.BucketSeconds) + 1 then
		AntiCheatService.Grace(p, "Impulse", tonumber(SEC.ImpulseGrace) or 1.5, oldRate)
	end
end

function AntiCheatService.Exempt(p: Player, seconds: number)
	if not present(p) then
		return
	end
	local track = trackOf(p)
	local duration = if Util.IsFinite(seconds) then math.clamp(seconds, 0, 86400) else 0
	track.ExemptUntil = os.clock() + duration -- letzter Aufruf gewinnt (0 = Ausnahme beenden)
end

function AntiCheatService.Add(p: Player, reason: string, points: number, evidence: { [string]: any }?)
	if not present(p) then
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

function AntiCheatService.Snapshot(p: Player): { [string]: any }
	if not present(p) then
		return {}
	end
	return snapshotOf(p)
end

-- ---------------------------------------------------------------------
-- ZUSATZ-API (AdminService)
-- ---------------------------------------------------------------------
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

function AntiCheatService.Stats(): { [string]: number }
	return {
		Tracked = #trackedList,
		Flags = #localFlags,
		Reports = #localReports,
		Kicks = kickCount,
		Pending = #pendingFlags + #pendingReports,
	}
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

-- Flag oder Meldung abweisen (lokal + im gespeicherten Shard) – yieldet. Gibt (true, Eintrag?) zurück: den entfernten
-- Eintrag aus den lokalen Listen oder aus dem gespeicherten Shard (ResolveReport benachrichtigt damit den Melder).
function AntiCheatService.Dismiss(id: string): (boolean, any?)
	if type(id) ~= "string" or #id > 80 then
		return false, nil
	end
	dismissed[id] = true
	local removed: any = nil
	for _, list in ipairs({ localFlags, localReports, pendingFlags, pendingReports } :: { { any } }) do
		for i = #list, 1, -1 do
			if list[i].Id == id then
				removed = removed or list[i]
				table.remove(list, i)
			end
		end
	end
	local colon = string.find(id, ":", 1, true)
	local key = if colon then string.sub(id, 1, colon - 1) else nil
	if key and string.match(key, "^[FR]_%d+_%d+$") then
		local fromStore: any = nil
		storeUpdate(key, function(old)
			fromStore = nil -- der Transform kann mehrfach laufen: nur der letzte Lauf zählt
			if type(old) ~= "table" then
				return nil
			end
			local kept: { any } = {}
			for _, entry in ipairs(old) do
				if type(entry) == "table" then
					if entry.Id == id then
						fromStore = entry
					else
						table.insert(kept, entry)
					end
				end
			end
			if fromStore == nil then
				return nil -- nicht in diesem Shard: nichts schreiben
			end
			return kept
		end)
		removed = removed or fromStore
	end
	table.clear(storedCache)
	return true, removed
end

-- ---------------------------------------------------------------------
-- HONEYPOT & MELDEN
-- ---------------------------------------------------------------------
local function onHoneypot(p: Player, ...: any)
	if not present(p) or honeypotHit[p] then
		return
	end
	local args = table.pack(...)
	if not isAdmin(p) then
		honeypotHit[p] = true
	end
	AntiCheatService.Add(p, "Honeypot", tonumber(SEC.Weights.Honeypot) or 100, {
		Remote = "GrantCash",
		Args = args.n,
		First = if args.n > 0 then sanitizeValue(args[1]) else "-",
	})
end

-- Freitext zur Meldung: getrimmt, auf ReportNoteMax Zeichen gekürzt, gefiltert (TextService, pcall). Fehler/leer -> nil.
local function cleanNote(p: Player, note: any): string?
	if type(note) ~= "string" then
		return nil
	end
	local text = string.gsub(string.gsub(note, "^%s+", ""), "%s+$", "")
	if text == "" or utf8.len(text) == nil then
		return nil
	end
	local staff = if type(SEC.Staff) == "table" then SEC.Staff else {}
	local maxChars = math.max(1, math.floor(tonumber(staff.ReportNoteMax) or 120))
	if (utf8.len(text) :: number) > maxChars then
		local cut = utf8.offset(text, maxChars + 1)
		text = if cut then string.sub(text, 1, cut - 1) else text
	end
	local ok, filtered = pcall(function()
		local result = TextService:FilterStringAsync(text, p.UserId, Enum.TextFilterContext.PublicChat)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(filtered) == "string" and filtered ~= "" then
		return filtered
	end
	return nil
end

-- Meldung abgeben (Menü "Report" und Chat /report über StaffService): gemeinsamer Limiter (ReportLimit), Ziel muss auf
-- diesem Server sein, Notiz gefiltert, Schnappschuss des Ziels; danach werden Teammitglieder benachrichtigt. Yieldet.
function AntiCheatService.SubmitReport(p: Player, userId: any, reason: any, note: any, via: any): Types.Reply
	if not present(p) then
		return { Ok = false }
	end
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
	if not reportLimiter.Check(p) then
		return { Ok = false, Message = L(p, "admin.rep.limit") }
	end
	local cleanedNote = cleanNote(p, note)
	if not present(p) or target.Parent ~= Players then
		return { Ok = false, Message = L(p, "admin.reportGone") } -- während des Filterns gegangen
	end
	local report: Report = {
		Id = newId("R"),
		From = p.UserId,
		FromName = p.Name,
		UserId = target.UserId,
		Name = target.Name,
		Reason = reason,
		Note = cleanedNote,
		Via = if via == "Chat" then "Chat" else "Menu",
		Job = string.sub(if game.JobId ~= "" then game.JobId else "Studio", 1, 8),
		Snapshot = snapshotOf(target),
		T = os.time(),
	}
	table.insert(localReports, report)
	while #localReports > (SEC.FlagsLocalMax or 200) do
		table.remove(localReports, 1)
	end
	table.insert(pendingReports, report)
	while #pendingReports > (SEC.FlagsLocalMax or 200) do
		table.remove(pendingReports, 1)
	end
	-- Teammitglieder mit Recht Reports benachrichtigen (yieldet ggf. – eigener Thread, die Antwort wartet nicht)
	task.spawn(function()
		call("StaffService", "OnReport", report)
	end)
	return { Ok = true, Message = L(p, "admin.reportThanks") }
end

-- Request "Report": nur UserId, Reason und optional Note (Text) -> SubmitReport(..., "Menu")
local function onReport(p: Player, arg: any): Types.Reply
	if type(arg) ~= "table" then
		return { Ok = false, Message = L(p, "core.invalid") }
	end
	for key in pairs(arg) do
		if key ~= "UserId" and key ~= "Reason" and key ~= "Note" then
			return { Ok = false, Message = L(p, "core.invalid") }
		end
	end
	if arg.Note ~= nil and (type(arg.Note) ~= "string" or #arg.Note > 600) then
		return { Ok = false, Message = L(p, "core.invalid") }
	end
	return AntiCheatService.SubmitReport(p, arg.UserId, arg.Reason, arg.Note, "Menu")
end

-- ---------------------------------------------------------------------
-- LEBENSZYKLUS
-- ---------------------------------------------------------------------
function AntiCheatService.Init(services: any)
	Services = services
	-- Request "Report" (3 pro 10 Minuten) – Registrierung in Init (§C3 Phase 2)
	local limit = SEC.ReportLimit or { 3, 600 }
	local pss = services and services.PlayerStateService
	if pss and type(pss.Handle) == "function" then
		pss.Handle("Report", onReport, { Rate = tonumber(limit[1]) or 3, Per = tonumber(limit[2]) or 600 })
	else
		warn("[AntiCheat] Request 'Report' konnte nicht registriert werden (PlayerStateService fehlt)")
	end
end

function AntiCheatService.Start()
	local function onPlayer(p: Player)
		local track = trackOf(p)
		suspicionOf(p)
		p.CharacterAdded:Connect(function(character)
			if present(p) then
				setCharacter(track, character)
			end
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
		honeypotHit[p] = nil
		reportLimiter.Clear(p)
		local index = table.find(trackedList, p)
		if index then
			table.remove(trackedList, index)
		end
		excludesDirty = true
	end)

	-- Honeypot: unser Code feuert "GrantCash" NIE – jeder Aufruf ist ein Exploit
	local honeypot: any = Remotes.GrantCash
	if typeof(honeypot) == "Instance" and honeypot:IsA("RemoteEvent") then
		honeypot.OnServerEvent:Connect(onHoneypot)
	else
		warn("[AntiCheat] Remote GrantCash fehlt – Honeypot inaktiv")
	end

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
