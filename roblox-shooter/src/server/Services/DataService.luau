-- =====================================================================
--  CLUTCH CLASH – Spielstände (Server/Services/DataService)
--  Besitzer: WP1 (Core & Plattform). Vertrag: DESIGN.md C5.2 + C13, Basis Meteor Heist
--  (REUSE §8) mit den Fixes aus REUSE §14.3 #1–#4:
--    * Session-Lock: ein Spielstand ist immer nur in EINEM Server offen (keine Duplikate)
--    * 6 Lade-Versuche, fremdes Lock (< 30 Min) -> 5 s warten, letzter Versuch übernimmt (mit warn)
--    * Speichern: 4 Versuche, nie über ein fremdes Lock schreiben, Saves pro Profil SERIALISIERT
--      (ein Auto-Save kann den Release nicht mehr überholen)
--    * Auto-Save alle 90 s aus einer Schnappschuss-Liste, 0.5 s versetzt, jedes Save in pcall
--    * Studio: NoSave (Config.Studio.NoSave, Test-Spieler mit UserId <= 0, oder kein API-Zugriff)
--    * Live: Laden fehlgeschlagen -> Kick mit Meldung (nie mit leerem Stand spielen)
--
--  Öffentliche API:
--    DataService.Get(p): PlayerData?                 nil, solange nicht geladen
--    DataService.IsLoaded(p): boolean
--    DataService.IsNoSave(p): boolean
--    DataService.NoSaveReason(p): string?           "Config" | "TestPlayer" | "NoApi" (für den Toast)
--    DataService.OnProfileLoaded(cb(p, data))        jeder Callback per task.spawn nach dem Laden
--    DataService.OnProfileReleasing(cb(p, data))     pcall, VOR dem letzten Speichern
--    DataService.Save(p): boolean                    yieldet; NoSave -> true; während Release -> false
--    DataService.Reset(p): boolean                   frischer Stand, behält Purchases.Receipts/Starter/
--                                                    PassSeasons/FirstPack (+ Created/LastJoin)
--    DataService.Migrate(data)                       Versions-Schritte + Typ-Bereinigung (vor Reconcile)
--    DataService.DefaultData(): PlayerData           Kopie von DEFAULT_DATA (SelfTest)
--  Feld-Besitzer siehe C13 – nur das genannte WP schreibt ein Feld. WP1 pflegt
--  Version, Created, LastJoin, PlaySeconds (und Flags/Settings über PlayerStateService).
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
type Profile = {
	Loaded: boolean,
	Data: PlayerData?,
	NoSave: boolean,
	NoSaveReason: string?,
	Releasing: boolean,
	Saving: boolean,
	PlayBase: number, -- PlaySeconds beim Laden
	SessionStart: number, -- os.clock() beim Laden
}

DataService.Profiles = {} :: { [Player]: Profile }
local Profiles = DataService.Profiles

local TECH = Config.Tech
local DATA_VERSION = math.max(1, math.floor(tonumber(TECH.DataVersion) or 1))
local LOAD_ATTEMPTS = math.max(1, math.floor(tonumber(TECH.LoadAttempts) or 6))
local SAVE_ATTEMPTS = math.max(1, math.floor(tonumber(TECH.SaveAttempts) or 4))
local LOCK_STALE = tonumber(TECH.LockStaleSeconds) or 1800 -- ein Lock älter als 30 Min gilt als verwaist
local LOCK_WAIT = 5 -- Sekunden warten, wenn ein anderer Server den Stand noch offen hat
local RECEIPT_KEEP = math.max(1, math.floor(tonumber(TECH.ReceiptKeep) or 60))
local SAVE_QUEUE_TIMEOUT = 60 -- so lange wartet ein Save höchstens auf ein laufendes
local RELEASE_WAIT_TIMEOUT = 35 -- zweiter Release-Aufrufer wartet höchstens so lange
local SANITIZE_DEPTH = 6
local MAX_ARRAY_CHECK = 64

-- ---------------------------------------------------------------------
-- 1) STANDARD-SPIELSTAND (C13) – nur String-Schlüssel in Dictionaries!
-- ---------------------------------------------------------------------
local function defaultSettings(): { [string]: any }
	local client = Config.Client
	local defaults = type(client) == "table" and client.DefaultSettings or nil
	return if type(defaults) == "table" then Util.DeepCopy(defaults) else {}
end

local DEFAULT_DATA: PlayerData = {
	Version = DATA_VERSION,
	Created = 0,
	LastJoin = 0,
	PlaySeconds = 0, -- (WP1)
	Coins = 0,
	Gems = 0,
	Keys = 0,
	Shards = 0, -- (WP9, über ShopService.Grant/Spend)
	XP = 0,
	Level = 1,
	TotalXP = 0,
	FreeWeaponPicks = 0, -- (WP8; Picks einlösen WP8 -> ShopService.Grant)
	Stats = { -- (WP8)
		Matches = 0,
		PvpMatches = 0,
		Wins = 0,
		PvpWins = 0,
		Losses = 0,
		BotWins = 0,
		Draws = 0,
		RoundsWon = 0,
		Elims = 0,
		PvpElims = 0,
		Deaths = 0,
		Assists = 0,
		Headshots = 0,
		MeleeElims = 0,
		ShotsFired = 0,
		ShotsHit = 0,
		Damage = 0,
		Flawless = 0,
		Clutches = 0,
		Aces = 0,
		Streak = 0,
		BestStreak = 0,
		LossStreak = 0,
		BotLossStreak = 0,
		BotWinStreak = 0,
		CrownBest = 0,
		CrownDefences = 0,
		Bounties = 0,
		OvertimeCaps = 0,
		VoidKnocks = 0,
		FlickBest = 0,
	},
	Mmr = 1000,
	MmrGames = 0,
	BotTier = 0, -- (WP8; BotTier −1..1)
	Ranked = { Season = 0, Rating = 0, Placements = 0, ShieldDay = 0, Peak = 0 }, -- reserviert v1.1 (WP8)
	Weapons = { -- (WP9)
		Owned = { PopRifle = true, PipPistol = true, BoxingGloves = true, PopGrenade = true },
		Mastery = {}, -- [weaponKey] = { K = Pops, T = eingelöste Stufe } (WP8)
	},
	Loadouts = { -- Slots = 3 + gekaufte Coin-Plätze (max 5); LoadoutPlus-Pass -> 8 (WP9)
		Active = 1,
		Slots = 3,
		Presets = {
			{ Name = "Loadout 1", P = "PopRifle", S = "PipPistol", M = "BoxingGloves", U = "PopGrenade" },
			{ Name = "Loadout 2", P = "PopRifle", S = "PipPistol", M = "BoxingGloves", U = "PopGrenade" },
			{ Name = "Loadout 3", P = "PopRifle", S = "PipPistol", M = "BoxingGloves", U = "PopGrenade" },
		},
	},
	Cosmetics = { -- (WP9)
		Owned = {}, -- [cosmeticId] = true (inkl. Titel "TT_…")
		Equipped = { Finisher = "F_Confetti", Tracer = "T_Team", Title = "" },
		PerWeapon = {}, -- [weaponKey] = { Skin = "", Wrap = "", Charm = "" }
	},
	Crates = { Pity = 0, Opened = 0 }, -- (WP9)
	Boosts = { XP2Until = 0 }, -- os.time() (WP9)
	Quests = { -- Daily/Weekly: { {Id, Kind, Goal, P, Claimed, Tier} } (WP8)
		Day = 0,
		Daily = {},
		Rerolls = 1,
		DailyBonus = false,
		Week = 0,
		Weekly = {},
		WeeklyChest = false,
		Beginner = { Step = 1, P = 0 },
	},
	Login = { LastDay = 0, CalDay = 0, Streak = 0, Best = 0, FreezeWeek = 0, CatGiven = false }, -- (WP8)
	Daily = { -- (WP8)
		FirstWinDay = 0,
		WheelDay = 0,
		WheelSpins = 0,
		PlayDay = 0,
		PlaySec = 0,
		Gifts = {},
		BotCoinsDay = 0,
		BotCoins = 0,
	},
	Pass = { Season = 0, XP = 0, Premium = false, Free = {}, Prem = {} }, -- Free/Prem: ["<tier>"] = true (WP8)
	Achievements = {},
	AchProgress = {}, -- ["Id"] = true / Zahl (WP8)
	Honor = { Commends = 0, Day = 0, Today = 0, GG = 0 }, -- (WP8)
	Codes = {}, -- ["CODE"] = os.time() (WP8)
	Purchases = { -- Receipts: { {Id = purchaseId, T = os.time()} } max 60 (WP9)
		Receipts = {},
		Starter = false,
		StarterOfferedAt = 0,
		PassSeasons = {},
		FirstPack = {},
		RobuxSpent = 0,
		Supporter = 0,
	},
	Flags = { Tutorial = false, TourDone = false, FirstRealWin = false, Rules = false }, -- (WP1/WP5)
	Settings = defaultSettings(), -- Defaults aus Config.Client.DefaultSettings (WP1-Handler)
	Mod = { Warnings = 0, HardKicks = {} }, -- HardKicks: Zeitstempel, max 10 (WP7)
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
-- Geht in "Datensätze" (Tabellen mit festen Feldern) und in Listen von Datensätzen (Presets).
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

function DataService.Migrate(data: PlayerData)
	local version = tonumber(data.Version) or 0
	if version ~= version then
		version = 0
	end
	-- Versions-Schritte (v0 -> v1: nichts umzubauen; künftige Schritte hier anhängen: if version < 2 then … end)
	if version > DATA_VERSION then
		warn(("[DataService] Spielstand-Version %d ist neuer als dieser Server (%d)"):format(version, DATA_VERSION))
	end
	sanitize(data, DEFAULT_DATA, 1)
	-- Belege: höchstens RECEIPT_KEEP behalten (älteste zuerst raus)
	local purchases = data.Purchases
	if type(purchases) == "table" and type(purchases.Receipts) == "table" then
		local receipts = purchases.Receipts
		while #receipts > RECEIPT_KEEP do
			table.remove(receipts, 1)
		end
	end
	data.Version = math.max(version, DATA_VERSION) -- nie herunterstufen
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
	return "Player_" .. tostring(userId)
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
				-- §14.3 #4: Übernahme eines (noch nicht verwaisten) Locks sichtbar machen
				warn(
					("[DataService] Lock von Server %s übernommen (dieser Server %s) für UserId %d"):format(
						tookOverFrom,
						jobId(),
						userId
					)
				)
			end
			local data = if type(result) == "table" and type(result.Data) == "table" then result.Data else freshData()
			-- erst migrieren (Version prüfen), DANN fehlende Felder ergänzen
			local migrated, err = pcall(DataService.Migrate, data)
			if not migrated then
				warn("[DataService] Migration fehlgeschlagen: " .. tostring(err))
			end
			Util.Reconcile(data, DEFAULT_DATA)
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
				-- §14.3 #2: läuft schon der Release, nie wieder ein Lock setzen
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

function DataService.NoSaveReason(player: Player): string?
	local profile = Profiles[player]
	return if profile and profile.NoSave then profile.NoSaveReason else nil
end

-- Spielzeit fortschreiben (WP1-Feld PlaySeconds)
local function stampPlayTime(profile: Profile)
	local data = profile.Data
	if data then
		data.PlaySeconds = profile.PlayBase + math.max(0, math.floor(os.clock() - profile.SessionStart))
	end
end

-- Saves pro Profil hintereinander (§14.3 #2). fn darf yielden.
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
		stampPlayTime(profile)
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
	}
end

local function onPlayerAdded(player: Player)
	if Profiles[player] then
		return -- schon in Arbeit (Start-Schleife + PlayerAdded)
	end
	local profile = newProfile()
	Profiles[player] = profile

	local data: PlayerData
	local noSaveReason: string? = nil
	if RunService:IsStudio() and (Config.Studio.NoSave == true or player.UserId <= 0) then
		-- Studio-Test: nie den Live-Speicher anfassen (§14.3 #3)
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
		-- Spieler hat das Spiel während des Ladens verlassen -> Lock sofort freigeben
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
	data.LastJoin = now
	profile.PlayBase = if Util.IsFinite(data.PlaySeconds) then math.max(0, data.PlaySeconds) else 0
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
			-- wartet auf ein laufendes Auto-Save, dann letzter Save mit Lock = nil
			serialized(profile, function()
				stampPlayTime(profile)
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
		if type(oldPurchases.FirstPack) == "table" then
			fresh.Purchases.FirstPack = oldPurchases.FirstPack
		end
	end
	fresh.Created = if Util.IsFinite(data.Created) then data.Created else os.time()
	fresh.LastJoin = os.time()
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
		pcall(state.SetLeaderstat, player, "Level", 1)
		pcall(state.SetLeaderstat, player, "Wins", 0)
	end
	return true
end

-- ---------------------------------------------------------------------
-- 5) START
-- ---------------------------------------------------------------------
local autoSaveRunning = false

-- §14.3 #1: Schnappschuss-Liste statt pairs(Profiles) mit yield, jedes Save in pcall
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
