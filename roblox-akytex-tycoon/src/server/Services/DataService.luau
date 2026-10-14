-- =====================================================================
--  AKYTEX TYCOON – Spielstände (Server/Services/DataService)
--  Besitzer: WP1 (Kern & Plattform). Vertrag: DESIGN.md §C5.2 + §C12 (CC-Kopie 1:1 mit allen Fixes, REUSE §3.9/§7):
--    * DataStore "AT_Player_v1", Schlüssel "P_<UserId>", Datensatz { Data, Lock = { JobId, Time } }
--    * Session-Lock: ein Spielstand ist immer nur in EINEM Server offen (keine Duplikate)
--    * 6 Lade-Versuche, fremdes Lock (< 30 Min) -> 5 s warten, letzter Versuch übernimmt (mit warn beider JobIds)
--    * Speichern: 4 Versuche, nie über ein fremdes Lock schreiben, Saves pro Profil SERIALISIERT
--      (ein Auto-Save kann den Release nicht überholen, während des Release wird nie ein Lock gesetzt)
--    * Auto-Save alle 90 s aus einer Schnappschuss-Liste, 0,5 s versetzt, jedes Save in pcall (eigener Thread)
--    * Studio: NoSave (Config.Studio.NoSave, Test-Spieler mit UserId <= 0, oder kein API-Zugriff)
--    * Live: Laden fehlgeschlagen -> Kick mit Meldung (nie mit leerem Stand spielen)
--    * Laden: Migrate (Version) -> Reconcile -> Sanitize (falsche Typen/NaN -> Standard) -> Reconcile ->
--      String-Schlüssel (auch in Listen) -> Ringpuffer kürzen. SavedAt = Server-os.time() bei JEDEM Speichern
--      (auch im finalen Release-Save); LastSavedAt(p) liefert den Wert vom Laden (Offline-Abrechnung).
--
--  Öffentliche API:
--    DataService.Get(p): PlayerData?                 nil, solange nicht geladen
--    DataService.IsLoaded(p): boolean
--    DataService.IsNoSave(p): boolean
--    DataService.NoSaveReason(p): ("Config" | "TestPlayer" | "NoApi")?
--    DataService.OnProfileLoaded(cb(p, data))        jeder Callback per task.spawn nach dem Laden (später registriert -> nachgereicht)
--    DataService.OnProfileReleasing(cb(p, data))     pcall, VOR dem letzten Speichern
--    DataService.Save(p): boolean                    yieldet; NoSave -> true; während Release -> false
--    DataService.Reset(p): boolean                   frischer Stand, behält Purchases.Receipts/Starter/PassSeasons/RobuxSpent
--    DataService.Migrate(data)                       Versions-Schritte + Reparatur (idempotent, siehe oben)
--    DataService.DefaultData(): PlayerData           Kopie von DEFAULT_DATA (SelfTest)
--    DataService.LastSavedAt(p): number              SavedAt beim Laden (für Offline), 0 = neu
--    DataService.Profiles                            { [Player]: Profile } (nur lesen)
--  WP1 pflegt V, Created, SavedAt, Playtime, Sessions; jedes andere Feld (auch LastUtcDay, Tages-Logik WP9) schreibt
--  sein Besitzer-WP (§C12).
-- =====================================================================

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Lang = require(Shared:WaitForChild("Lang"))
local Types = require(Shared:WaitForChild("Types"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local DataService = {}
local Services: any = nil

type PlayerData = Types.PlayerData
type NoSaveReason = "Config" | "TestPlayer" | "NoApi"
type Profile = {
	Loaded: boolean,
	Data: PlayerData?,
	NoSave: boolean,
	NoSaveReason: NoSaveReason?,
	Releasing: boolean,
	Saving: boolean,
	PlayBase: number, -- Playtime beim Laden
	SessionStart: number, -- os.clock() beim Laden
	LoadedSavedAt: number, -- SavedAt beim Laden (Offline-Abrechnung), 0 = neu
}

DataService.Profiles = {} :: { [Player]: Profile }
local Profiles = DataService.Profiles

local TECH = Config.Tech
local DATA_VERSION = math.max(1, math.floor(tonumber(TECH.DataVersion) or 1))
local KEY_PREFIX = if type(TECH.KeyPrefix) == "string" and TECH.KeyPrefix ~= "" then TECH.KeyPrefix else "P_"
local LOAD_ATTEMPTS = math.max(1, math.floor(tonumber(TECH.LoadAttempts) or 6))
local SAVE_ATTEMPTS = math.max(1, math.floor(tonumber(TECH.SaveAttempts) or 4))
local LOCK_STALE = tonumber(TECH.LockStaleSeconds) or 1800 -- ein Lock älter als 30 Min gilt als verwaist
local LOCK_WAIT = 5 -- Sekunden warten, wenn ein anderer Server den Stand noch offen hat
local RECEIPT_KEEP = math.max(1, math.floor(tonumber(TECH.ReceiptKeep) or 60))
local SAVE_QUEUE_TIMEOUT = 60 -- so lange wartet ein Save höchstens auf ein laufendes
local RELEASE_WAIT_TIMEOUT = 35 -- zweiter Release-Aufrufer wartet höchstens so lange
local SANITIZE_DEPTH = 6
local MAX_ARRAY_CHECK = 128
local KEYS_DEPTH = 12 -- String-Schlüssel-Reparatur: so tief
local KEYS_MAX_NODES = 20000 -- … und höchstens so viele Tabellen je Durchlauf

-- Ringpuffer (§C12.1): Pfad -> höchstens so viele Einträge (älteste zuerst raus). Orders/Alerts NICHT kürzen
-- (Reservierungen gehören WP4 – die Grenzen 50/18 setzt OrderService beim Anlegen durch).
local RINGS: { { Path: { string }, Max: number } } = {
	{ Path = { "Purchases", "Receipts" }, Max = RECEIPT_KEEP },
	{ Path = { "Depot", "Fills" }, Max = 100 },
	{ Path = { "Depot", "Nav" }, Max = 72 },
	{ Path = { "League", "Returns" }, Max = 504 },
}

-- ---------------------------------------------------------------------
-- 1) STANDARD-SPIELSTAND (§C12.1) – nur String-Schlüssel in Dictionaries, nie nil (leere Tabellen/false/0)
-- ---------------------------------------------------------------------
local DEFAULT_DATA: PlayerData = {
	V = DATA_VERSION,
	Created = 0,
	SavedAt = 0,
	LastUtcDay = 0,
	Playtime = 0,
	Sessions = 0,
	Credits = 0, -- CR, ganzzahlig, ≤ 9e15 (WP10 ShopService)
	Depot = { -- Cent; einziger Schreiber OrderService/Portfolio (WP4)
		V = 1,
		Cash = 2500000,
		Basis = 2500000, -- 25.000 AKY
		Pos = {},
		Short = {},
		Orders = {},
		Alerts = {},
		Watch = { {} },
		Fills = {},
		Nav = {},
		Seq = {},
		NextId = 1,
		LastTick = 0,
		LastTransferDay = -1,
		LastRefillUtcDay = -1,
		AutoTransfer = true,
		Bots = {},
		Stats = {
			Trades = 0,
			Wins = 0,
			Losses = 0,
			GrossWin = 0,
			GrossLoss = 0,
			PeakNav = 0,
			MaxDD = 0,
			BestPct = 0,
			ReadWell = 0,
		},
		Tutorial = { T0 = 0, Q = 0, Done = false },
	},
	League = { Week = 0, Returns = {}, Trades = 0, Days = 0, Tainted = false, LastGrantedWeek = 0, Trophies = {} }, -- WP4/WP9
	Tower = { -- WP6
		Floors = {},
		Vault = 0,
		Build = {},
		Eff = 0,
		Skin = "GlassBlue",
		Neon = "Accent",
		Crown = "",
		Name = { A = 1, N = 1 },
		Private = {},
		RunSpend = 0,
		KeepLayout = true,
		Layouts = {},
		Express = {},
		Instant = 0,
		InstantDay = 0,
		Helpers = {},
	},
	Garage = { Cars = { LamCity = true }, Active = "LamCity", Tune = {} }, -- WP7
	Life = { Watches = {}, Accessories = {}, Equipped = { Watch = "", Acc = {} } }, -- WP8
	Storage = { Decor = {} }, -- [key] = Anzahl (WP8)
	Prog = { -- WP9
		Xp = 0,
		Licence = 1,
		Exams = {},
		ExamProgress = {},
		Lessons = {},
		KH = {},
		KHSpent = 0,
		KHResetWeek = 0,
		Ruf = 0,
		RufDay = 0,
		RufToday = 0,
		Title = "",
		Titles = {},
		Album = {},
		Ach = {},
		AchProgress = {},
		Badges = {},
		XpDay = 0,
		XpCounts = {},
		Prestige = { Count = 0, Stars = 0, Perks = {}, Firmenwert = 0, Tickers = {}, RespecFree = false },
	},
	Quests = { Day = 0, Daily = {}, Rerolled = false, Week = 0, Weekly = {}, Starter = 1, StarterDone = {} }, -- WP9
	Login = { LastDay = 0, Streak = 0, Best = 0, Freeze = 1, FreezeWeek = 0, Cycle = 1, Track = 0 }, -- WP9
	Season = { Id = 1, Xp = 0, Premium = false, ClaimedFree = {}, ClaimedPremium = {}, PlayToday = 0, PlayDay = 0 }, -- WP9
	Social = { -- WP9
		RespektGiven = {},
		RespektDay = 0,
		ReferredBy = 0,
		ReferralDone = false,
		ReferralWeek = 0,
		ReferralCount = 0,
		Group = false,
	},
	Boosts = { X2 = 0, X5 = 0, Bull = 0 }, -- Rest-Spielsekunden (WP6/WP10)
	Notif = { LastPrompt = 0, OptIn = false }, -- WP9
	Purchases = {
		Receipts = {},
		RobuxSpent = 0,
		Starter = false,
		PassSeasons = {},
		Quote = {},
		ClubClaimDay = 0,
		Gifts = 0,
	}, -- WP10
	Stats = { -- AdminCredits = Admin-Geschenke in CR (Wunsch 18, ShopService markiert sie; zählen nie für die Liga)
		LifetimeCredits = 0,
		Collected = 0,
		FloorsBuilt = 0,
		Ipos = 0,
		Drive = 0,
		Pickups = 0,
		AdminCredits = 0,
	},
	Settings = {}, -- WP1 (Schema Config.Client.SettingsSchema, Standardwerte beim Laden ergänzt)
	Flags = {}, -- WP1 (TutorialFlag) + Besitzer-WPs (z. B. Flags.TutorialTrade WP4)
	Mod = {}, -- WP11 (Verwarnungen, harte Kicks)
}

local function freshData(): PlayerData
	return Util.DeepCopy(DEFAULT_DATA)
end

-- ---------------------------------------------------------------------
-- 2) MIGRATION + BEREINIGUNG
-- ---------------------------------------------------------------------
local function isArray(t: { [any]: any }): boolean
	return t[1] ~= nil
end

-- Felder mit falschem Typ / kaputten Zahlen auf nil setzen -> Reconcile trägt danach den Standard ein.
-- Geht in "Datensätze" (Tabellen mit festen Feldern) und in Listen von Datensätzen (erstes Element = Muster).
local function sanitize(target: { [any]: any }, template: { [any]: any }, depth: number)
	if depth > SANITIZE_DEPTH then
		return
	end
	for key, default in pairs(template) do
		local value = target[key]
		if value == nil then
			continue
		end
		local kind = type(value)
		if kind ~= type(default) or (kind == "number" and not Util.IsFinite(value)) then
			-- falscher Typ oder NaN/unendlich -> Standard (Reconcile)
			target[key] = nil
		elseif kind == "table" and next(default) ~= nil then
			if isArray(default) and type(default[1]) == "table" then
				-- Liste von Datensätzen: jedes Element gegen das erste Muster prüfen
				local pattern = default[1]
				local count = 0
				for index, element in ipairs(value) do
					count += 1
					if count > MAX_ARRAY_CHECK then
						break
					end
					if type(element) ~= "table" then
						value[index] = Util.DeepCopy(default[index] or pattern)
					else
						sanitize(element, default[index] or pattern, depth + 1)
						Util.Reconcile(element, default[index] or pattern)
					end
				end
			elseif not isArray(default) then
				sanitize(value, default, depth + 1)
			end
		end
	end
end

-- Ist t eine lückenlose Liste 1..n (JSON-Array)?
local function isProperArray(t: { [any]: any }): boolean
	local count = 0
	for key in pairs(t) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			return false
		end
		count += 1
	end
	return count == #t
end

-- DataStore-sicher machen (auch tief in Listen): Dictionaries nur mit String-Schlüsseln (Zahl-Schlüssel ->
-- tostring, andere Schlüssel weg), NaN/±unendlich -> 0, nicht speicherbare Werte (Instanzen, Funktionen,
-- Vector3 …) weg. Tabellen-Identität bleibt erhalten (andere Services halten Verweise).
local function ensureStringKeys(root: { [any]: any })
	local nodes = 0
	local visited: { [any]: boolean } = {}
	local function fix(t: { [any]: any }, depth: number)
		if depth > KEYS_DEPTH or visited[t] or nodes >= KEYS_MAX_NODES then
			return
		end
		visited[t] = true
		nodes += 1
		local array = isProperArray(t)
		for _, key in ipairs(Util.Snapshot(t)) do
			local value = t[key]
			local kind = type(value)
			if kind == "number" and not Util.IsFinite(value) then
				t[key] = 0
			elseif kind ~= "number" and kind ~= "string" and kind ~= "boolean" and kind ~= "table" then
				t[key] = nil -- nicht speicherbar
				continue
			end
			if not array and type(key) ~= "string" then
				t[key] = nil
				if type(key) == "number" and Util.IsFinite(key) then
					local text = if key % 1 == 0 then string.format("%d", key) else tostring(key)
					if t[text] == nil then
						t[text] = value
					end
				end
			end
			if kind == "table" then
				fix(value, depth + 1)
			end
		end
	end
	fix(root, 1)
end

local function trimRings(data: PlayerData)
	for _, ring in ipairs(RINGS) do
		local node: any = data
		for _, part in ipairs(ring.Path) do
			node = if type(node) == "table" then node[part] else nil
		end
		if type(node) == "table" and #node > ring.Max then
			local excess = #node - ring.Max
			table.move(node, excess + 1, #node, 1)
			for i = #node, ring.Max + 1, -1 do
				node[i] = nil
			end
		end
	end
end

function DataService.Migrate(data: PlayerData)
	if type(data) ~= "table" then
		return
	end
	-- 1) Versions-Schritte (§C12.2): nie Felder löschen, nur umbenennen/umrechnen
	local version = data.V
	if not Util.IsFinite(version) then
		data.V = 1
		version = 1
	end
	if version > DATA_VERSION then
		warn(("[DataService] Spielstand-Version %d ist neuer als dieser Server (%d)"):format(version, DATA_VERSION))
	end
	-- künftige Schritte hier anhängen:  if data.V < 2 then … data.V = 2 end
	-- 2) Reconcile -> 3) Sanitize -> Reconcile (Reparaturen wieder auffüllen)
	Util.Reconcile(data, DEFAULT_DATA)
	sanitize(data, DEFAULT_DATA, 1)
	Util.Reconcile(data, DEFAULT_DATA)
	-- 4) String-Schlüssel + speicherbare Werte, 5) Ringpuffer
	ensureStringKeys(data)
	trimRings(data)
	data.V = math.max(data.V, DATA_VERSION) -- nie herunterstufen
end

function DataService.DefaultData(): PlayerData
	return freshData()
end

-- ---------------------------------------------------------------------
-- 3) DATASTORE
-- ---------------------------------------------------------------------
local store: DataStore? = nil
local storeError: string? = nil

local function getStore(): DataStore?
	if store or storeError then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(TECH.DataStoreName)
	end)
	if ok then
		store = result
	else
		local message = tostring(result)
		storeError = message
		warn("[DataService] DataStore nicht verfügbar: " .. message)
	end
	return store
end

local function keyFor(userId: number): string
	return KEY_PREFIX .. string.format("%d", userId)
end

local function jobId(): string
	return if game.JobId ~= "" then game.JobId else "studio"
end

-- Fehlermeldungen, die im Studio bedeuten: DataStores sind hier gar nicht erreichbar
local function isStudioAccessError(err: any): boolean
	local text = string.lower(tostring(err))
	return string.find(text, "studio", 1, true) ~= nil
		or string.find(text, "publish", 1, true) ~= nil
		or string.find(text, "api services", 1, true) ~= nil
		or string.find(text, "403", 1, true) ~= nil
end

local function lockOf(record: any): { JobId: any, Time: any }?
	if type(record) == "table" and type(record.Lock) == "table" then
		return record.Lock
	end
	return nil
end

-- Lädt + sperrt den Spielstand. Gibt (true, data) oder (false, grund) zurück.
local function loadData(userId: number): (boolean, any)
	local ds = getStore()
	if not ds then
		return false, storeError or "DataStore nicht verfügbar"
	end
	for attempt = 1, LOAD_ATTEMPTS do
		local lockedByOther = false
		local tookOverFrom: string? = nil
		local forceTake = attempt == LOAD_ATTEMPTS
		local ok, result = pcall(function()
			return ds:UpdateAsync(keyFor(userId), function(old)
				-- kann mehrfach aufgerufen werden -> Merker jedes Mal neu setzen; KEIN yield hier
				lockedByOther = false
				tookOverFrom = nil
				local record = if type(old) == "table" then old else {}
				local lock = lockOf(record)
				if lock and lock.JobId ~= jobId() then
					local age = os.time() - (tonumber(lock.Time) or 0)
					if age < LOCK_STALE then
						if not forceTake then
							lockedByOther = true
							return nil -- nichts schreiben
						end
						tookOverFrom = tostring(lock.JobId)
					end
				end
				record.Lock = { JobId = jobId(), Time = os.time() }
				return record
			end)
		end)
		if ok and not lockedByOther then
			if tookOverFrom then
				-- REUSE §7 #24: Übernahme eines (noch nicht verwaisten) Locks sichtbar machen
				warn(
					("[DataService] Lock von Server %s übernommen (dieser Server %s) für UserId %d"):format(
						tookOverFrom,
						jobId(),
						userId
					)
				)
			end
			local data = if type(result) == "table" and type(result.Data) == "table" then result.Data else freshData()
			-- erst migrieren (Version prüfen), dabei Reconcile + Sanitize + String-Schlüssel
			local migrated, err = pcall(DataService.Migrate, data)
			if not migrated then
				warn("[DataService] Migration fehlgeschlagen: " .. tostring(err))
				Util.Reconcile(data, DEFAULT_DATA)
			end
			return true, data
		end
		if not ok then
			warn(("[DataService] Laden fehlgeschlagen (Versuch %d): %s"):format(attempt, tostring(result)))
			-- Studio ohne API-Zugriff / unveröffentlichter Ort: sofort aufgeben (Studio-Test startet gleich)
			if RunService:IsStudio() and isStudioAccessError(result) then
				return false, "studio"
			end
		end
		if attempt < LOAD_ATTEMPTS then
			task.wait(if lockedByOther then LOCK_WAIT else attempt * 1.5)
		end
	end
	return false, "Konnte Spielstand nicht laden"
end

-- Schreibt den Spielstand. release = true gibt das Lock frei.
local function saveData(userId: number, data: PlayerData, release: boolean, profile: Profile?): boolean
	local ds = getStore()
	if not ds then
		return false
	end
	for attempt = 1, SAVE_ATTEMPTS do
		local lostLock = false
		local ok, err = pcall(function()
			ds:UpdateAsync(keyFor(userId), function(old)
				lostLock = false
				local lock = lockOf(old)
				if lock and lock.JobId ~= jobId() then
					-- Ein anderer Server hat den Spielstand übernommen -> NICHT überschreiben
					lostLock = true
					return nil
				end
				-- REUSE §7 #22: läuft schon der Release, nie wieder ein Lock setzen
				local keepLock = not release and not (profile and profile.Releasing)
				return {
					Data = data,
					Lock = if keepLock then { JobId = jobId(), Time = os.time() } else nil,
				}
			end)
		end)
		if ok then
			if lostLock then
				warn(
					("[DataService] Speichern abgelehnt: Spielstand %d gehört jetzt einem anderen Server"):format(
						userId
					)
				)
			end
			return not lostLock
		end
		warn(("[DataService] Speichern fehlgeschlagen (Versuch %d): %s"):format(attempt, tostring(err)))
		if attempt < SAVE_ATTEMPTS then
			task.wait(attempt * 1.5)
		end
	end
	return false
end

-- ---------------------------------------------------------------------
-- 4) PROFILE
-- ---------------------------------------------------------------------
local loadedCallbacks: { (Player, PlayerData) -> () } = {}
local releasingCallbacks: { (Player, PlayerData) -> () } = {}
local started = false

local function runLoaded(callback: (Player, PlayerData) -> (), player: Player, data: PlayerData)
	local ok, err = xpcall(callback, debug.traceback, player, data)
	if not ok then
		warn("[DataService] OnProfileLoaded-Callback Fehler: " .. tostring(err))
	end
end

function DataService.OnProfileLoaded(callback: (p: Player, data: PlayerData) -> ())
	table.insert(loadedCallbacks, callback)
	if started then
		-- später registriert: schon geladene Profile nachreichen
		for _, player in ipairs(Util.Snapshot(Profiles)) do
			local profile = Profiles[player]
			if profile and profile.Loaded and not profile.Releasing and profile.Data then
				task.spawn(runLoaded, callback, player, profile.Data)
			end
		end
	end
end

-- Wird VOR dem finalen Speichern aufgerufen (laufende Aktionen abbrechen, Bestenliste schreiben …)
function DataService.OnProfileReleasing(callback: (p: Player, data: PlayerData) -> ())
	table.insert(releasingCallbacks, callback)
end

function DataService.Get(player: Player): PlayerData?
	local profile = Profiles[player]
	if profile and profile.Loaded then
		return profile.Data
	end
	return nil
end

function DataService.IsLoaded(player: Player): boolean
	local profile = Profiles[player]
	return profile ~= nil and profile.Loaded == true
end

function DataService.IsNoSave(player: Player): boolean
	local profile = Profiles[player]
	return profile ~= nil and profile.NoSave == true
end

function DataService.NoSaveReason(player: Player): NoSaveReason?
	local profile = Profiles[player]
	return if profile and profile.NoSave then profile.NoSaveReason else nil
end

function DataService.LastSavedAt(player: Player): number
	local profile = Profiles[player]
	return if profile and profile.Loaded then profile.LoadedSavedAt else 0
end

-- WP1-Felder vor jedem Speichern fortschreiben: Spielzeit + Server-Zeitstempel (Offline-Abrechnung beim nächsten
-- Laden; auch bei Absturz ohne Release liegt SavedAt so höchstens ein Auto-Save-Intervall zurück).
-- LastUtcDay schreibt WP1 bewusst NICHT: der Tageswechsel gehört dem Besitzer der Tages-Logik (WP9) – ein
-- automatischer Stempel um Mitternacht würde dessen Tages-Reset für die laufende Sitzung verschlucken.
local function stampSession(profile: Profile)
	local data = profile.Data
	if data then
		data.Playtime = profile.PlayBase + math.max(0, math.floor(os.clock() - profile.SessionStart))
		data.SavedAt = os.time()
	end
end

-- Vor dem Schreiben DataStore-sicher machen (kein yield)
local function prepareForSave(data: PlayerData)
	local ok, err = pcall(ensureStringKeys, data)
	if not ok then
		warn("[DataService] Bereinigung vor dem Speichern fehlgeschlagen: " .. tostring(err))
	end
end

-- Saves pro Profil hintereinander (REUSE §7 #22). fn darf yielden.
local function serialized(profile: Profile, fn: () -> boolean): boolean
	local waited = os.clock()
	while profile.Saving do
		if os.clock() - waited > SAVE_QUEUE_TIMEOUT then
			warn("[DataService] Warten auf laufendes Speichern abgebrochen")
			return false
		end
		task.wait(0.1)
	end
	profile.Saving = true
	local ok, result = pcall(fn)
	profile.Saving = false
	if not ok then
		warn("[DataService] Speicherfehler: " .. tostring(result))
		return false
	end
	return result == true
end

function DataService.Save(player: Player): boolean
	local profile = Profiles[player]
	if not profile or not profile.Loaded then
		return false
	end
	if profile.NoSave then
		return true
	end
	if profile.Releasing then
		return false -- der Release speichert gleich ohnehin
	end
	return serialized(profile, function()
		if profile.Releasing or Profiles[player] ~= profile then
			return false
		end
		local data = profile.Data
		if not data then
			return false
		end
		stampSession(profile)
		prepareForSave(data)
		return saveData(player.UserId, data, false, profile)
	end)
end

local function newProfile(): Profile
	return {
		Loaded = false,
		Data = nil,
		NoSave = false,
		NoSaveReason = nil,
		Releasing = false,
		Saving = false,
		PlayBase = 0,
		SessionStart = os.clock(),
		LoadedSavedAt = 0,
	}
end

local function onPlayerAdded(player: Player)
	if Profiles[player] then
		return -- schon in Arbeit (Start-Schleife + PlayerAdded)
	end
	local profile = newProfile()
	Profiles[player] = profile

	local data: PlayerData
	local noSaveReason: NoSaveReason? = nil
	if RunService:IsStudio() and (Config.Studio.NoSave == true or player.UserId <= 0) then
		-- Studio-Test: nie den Live-Speicher anfassen (REUSE §7 #23)
		data = freshData()
		noSaveReason = if Config.Studio.NoSave == true then "Config" else "TestPlayer"
	else
		local ok, result = loadData(player.UserId)
		if ok then
			data = result
		elseif RunService:IsStudio() then
			warn(
				"[DataService] Studio: Speichern ist AUS. Aktiviere in Game Settings > Security "
					.. "'Enable Studio Access to API Services'."
			)
			data = freshData()
			noSaveReason = "NoApi"
		else
			if Profiles[player] == profile then
				Profiles[player] = nil
			end
			if player.Parent then
				player:Kick(Lang.T(Lang.For(player), "core.loadFailed"))
			end
			return
		end
	end

	if not player.Parent or Profiles[player] ~= profile or profile.Releasing then
		-- Spieler hat das Spiel während des Ladens verlassen -> Lock sofort freigeben (Daten unverändert)
		if noSaveReason == nil then
			saveData(player.UserId, data, true, nil)
		end
		if Profiles[player] == profile then
			Profiles[player] = nil
		end
		return
	end

	-- WP1-Felder
	local now = os.time()
	if not Util.IsFinite(data.Created) or data.Created <= 0 then
		data.Created = now
	end
	profile.LoadedSavedAt = if Util.IsFinite(data.SavedAt) and data.SavedAt > 0 then math.min(data.SavedAt, now) else 0
	data.Sessions = (if Util.IsFinite(data.Sessions) then math.max(0, data.Sessions) else 0) + 1
	profile.PlayBase = if Util.IsFinite(data.Playtime) then math.max(0, data.Playtime) else 0
	profile.SessionStart = os.clock()

	profile.Data = data
	profile.NoSave = noSaveReason ~= nil
	profile.NoSaveReason = noSaveReason
	profile.Loaded = true
	for _, callback in ipairs(loadedCallbacks) do
		task.spawn(runLoaded, callback, player, data)
	end
end

local function releaseProfile(player: Player)
	local profile = Profiles[player]
	if not profile then
		return
	end
	if profile.Releasing then
		-- wird bereits gespeichert (PlayerRemoving + BindToClose gleichzeitig) -> warten bis fertig
		local start = os.clock()
		while Profiles[player] == profile and os.clock() - start < RELEASE_WAIT_TIMEOUT do
			task.wait(0.1)
		end
		return
	end
	profile.Releasing = true
	local data = profile.Data
	if profile.Loaded and data then
		for _, callback in ipairs(releasingCallbacks) do
			local ok, err = pcall(callback, player, data)
			if not ok then
				warn("[DataService] OnProfileReleasing-Callback Fehler: " .. tostring(err))
			end
		end
		if not profile.NoSave then
			-- wartet auf ein laufendes Auto-Save, dann letzter Save mit Lock = nil (SavedAt = jetzt)
			serialized(profile, function()
				stampSession(profile)
				prepareForSave(data)
				return saveData(player.UserId, data, true, profile)
			end)
		end
	end
	if Profiles[player] == profile then
		Profiles[player] = nil
	end
end

-- Spielstand komplett zurücksetzen (Admin). Käufe bleiben verbucht.
function DataService.Reset(player: Player): boolean
	local profile = Profiles[player]
	if not profile or not profile.Loaded or profile.Releasing or not profile.Data then
		return false
	end
	local data = profile.Data :: PlayerData
	local fresh = freshData()
	local oldPurchases = data.Purchases
	if type(oldPurchases) == "table" then
		if type(oldPurchases.Receipts) == "table" then
			fresh.Purchases.Receipts = oldPurchases.Receipts -- Käufe bleiben verbucht (nie doppelt)
		end
		fresh.Purchases.Starter = oldPurchases.Starter == true -- Starter-Paket gibt es nur einmal
		if type(oldPurchases.PassSeasons) == "table" then
			fresh.Purchases.PassSeasons = oldPurchases.PassSeasons
		end
		if Util.IsFinite(oldPurchases.RobuxSpent) then
			fresh.Purchases.RobuxSpent = math.max(0, oldPurchases.RobuxSpent)
		end
	end
	fresh.Created = if Util.IsFinite(data.Created) then data.Created else os.time()
	fresh.Sessions = if Util.IsFinite(data.Sessions) then data.Sessions else 1
	-- dieselbe Tabelle behalten (andere Services halten Verweise darauf)
	table.clear(data)
	for key, value in pairs(fresh) do
		data[key] = value
	end
	profile.PlayBase = 0
	profile.SessionStart = os.clock()
	-- Client + Spielerliste sofort auffrischen
	local state = Services and Services.PlayerStateService
	if state then
		pcall(state.MarkDirty, player)
		pcall(state.SetLeaderstat, player, "Vermögen", 0)
		pcall(state.SetLeaderstat, player, "Etagen", 0)
		pcall(state.Notify, player, "core.dataReset", nil, "Info")
	end
	return true
end

-- ---------------------------------------------------------------------
-- 5) START
-- ---------------------------------------------------------------------
local autoSaveRunning = false

-- REUSE §7 #21: Schnappschuss-Liste statt pairs(Profiles) mit yield, jedes Save in pcall
local function autoSaveRound()
	if autoSaveRunning then
		return
	end
	autoSaveRunning = true
	local stagger = math.max(0, tonumber(TECH.AutoSaveStagger) or 0.5)
	for _, player in ipairs(Util.Snapshot(Profiles)) do
		local profile = Profiles[player]
		if profile and profile.Loaded and not profile.NoSave and not profile.Releasing and player.Parent then
			task.spawn(function()
				local ok, err = pcall(DataService.Save, player)
				if not ok then
					warn("[DataService] Auto-Save Fehler: " .. tostring(err))
				end
			end)
			task.wait(stagger) -- verteilen, um Limits zu schonen
		end
	end
	autoSaveRunning = false
end

function DataService.Init(services: any)
	Services = services
end

function DataService.Start()
	started = true
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(releaseProfile)

	local interval = math.max(10, tonumber(TECH.AutoSaveSeconds) or 90)
	Scheduler.Every("DataAutoSave", 1 / interval, function()
		task.spawn(autoSaveRound) -- Speichern yieldet -> eigener Thread (Scheduler-Callbacks yielden nie)
	end)

	-- Server fährt herunter: alles speichern (Roblox gibt max. 30 Sekunden)
	game:BindToClose(function()
		local limit = math.clamp(tonumber(TECH.BindToCloseSeconds) or 25, 1, 29)
		local pending = 0
		for _, player in ipairs(Util.Snapshot(Profiles)) do
			pending += 1
			task.spawn(function()
				local ok, err = pcall(releaseProfile, player)
				if not ok then
					warn("[DataService] Release beim Herunterfahren fehlgeschlagen: " .. tostring(err))
				end
				pending -= 1
			end)
		end
		local start = os.clock()
		while pending > 0 and os.clock() - start < limit do
			task.wait(0.1)
		end
	end)
end

return DataService
