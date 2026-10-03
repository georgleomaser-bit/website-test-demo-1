-- Speichert Spielstände sicher:
--  * Session-Lock: ein Spielstand ist immer nur in EINEM Server offen (keine Duplikate)
--  * Wiederholungen bei DataStore-Fehlern, Auto-Save, Speichern beim Server-Ende
--  * Wenn Laden fehlschlägt, wird der Spieler gekickt statt mit leerem Stand zu spielen
--  * Alte Spielstände (v1: Meteore ohne Aliens, Speed-Level) werden automatisch umgebaut

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Aliens = require(Shared:WaitForChild("Aliens"))

local DataService = {}
DataService.Profiles = {} :: { [Player]: any }

local DATA_VERSION = 2

local DEFAULT_DATA = {
	Version = DATA_VERSION,
	Cash = Config.StartCash,
	Pending = 0,
	-- ["1"] = { Id = "Pebble", Mut = "Normal", Lv = 1, Xp = 0, Hatch = 0, Alien = "PebbleBlob" }
	--   Hatch = Restsekunden bis zum Schlüpfen (0 = geschlüpft), Alien = nil solange noch Meteor
	Meteors = {},
	Rebirths = 0,
	Steps = 0, -- 👟 Schritte von den Laufbändern (bleiben bei Rebirth)
	TotalEarned = 0,
	Index = {}, -- ["PebbleBlob"] = true -> Alien schon entdeckt (bleibt bei Rebirth)
	Stats = { Stolen = 0, Robbed = 0, Bought = 0, RobuxSpent = 0 },
	Daily = { Last = 0, Streak = 0 },
	Receipts = {}, -- zuletzt verarbeitete Käufe (gegen doppelte Gutschrift)
	LastOnline = 0,
}

local LOCK_EXPIRE = 30 * 60 -- ein Lock älter als 30 Min gilt als verwaist
local LOAD_ATTEMPTS = 6
local LOCK_WAIT = 5

local store = nil
local storeOk = pcall(function()
	store = DataStoreService:GetDataStore(Config.DataStoreName)
end)

local loadedCallbacks = {}
local releasingCallbacks = {}

local function keyFor(userId: number): string
	return "Player_" .. userId
end

local function jobId(): string
	return game.JobId ~= "" and game.JobId or "studio"
end

function DataService.OnProfileLoaded(callback)
	table.insert(loadedCallbacks, callback)
end

-- Wird VOR dem finalen Speichern aufgerufen (z.B. um laufende Diebstähle abzubrechen)
function DataService.OnProfileReleasing(callback)
	table.insert(releasingCallbacks, callback)
end

function DataService.Get(player: Player)
	local profile = DataService.Profiles[player]
	if profile and profile.Loaded then
		return profile.Data
	end
	return nil
end

function DataService.IsLoaded(player: Player): boolean
	local profile = DataService.Profiles[player]
	return profile ~= nil and profile.Loaded == true
end

-- -------------------------------------------------------------------
-- MIGRATION: alte Spielstände auf das neue Format bringen
-- -------------------------------------------------------------------
-- Ein Slot-Eintrag reparieren (fehlende Felder, unbekannte Aliens)
local function migrateEntry(entry)
	local hatch = tonumber(entry.Hatch)
	if entry.Alien ~= nil and not Aliens.ById[entry.Alien] then
		-- Alien gibt es nicht mehr (Aliens.luau geändert) -> neu würfeln
		entry.Alien = Aliens.Roll(entry.Id)
	end
	if entry.Alien == nil and hatch == nil then
		-- Meteor aus v1 (vor den Aliens): sofort geschlüpft
		entry.Alien = Aliens.Roll(entry.Id)
		entry.Hatch = 0
	elseif entry.Alien ~= nil then
		entry.Hatch = 0
	else
		entry.Hatch = math.max(0, hatch or 0)
		if entry.Hatch ~= entry.Hatch then
			entry.Hatch = 0
		end
	end
end

function DataService.Migrate(data)
	local version = tonumber(data.Version) or 1
	if version < 2 then
		-- Speed-Level (v1, mit Cash gekauft) -> Schritte, damit niemand langsamer wird
		local speedLevel = tonumber(data.SpeedLevel) or 0
		if speedLevel > 0 then
			data.Steps = math.max(tonumber(data.Steps) or 0, math.floor(10 ^ (speedLevel / 6)))
		end
		-- Index (v1 = Meteor-Ids) -> das Normal-Alien jedes entdeckten Meteors
		local newIndex = {}
		if type(data.Index) == "table" then
			for id in pairs(data.Index) do
				if Aliens.ById[id] then
					newIndex[id] = true
				elseif Config.MeteorsById[id] then
					local options = Aliens.ByMeteor[id]
					if options and options[1] then
						newIndex[options[1].Id] = true
					end
				end
			end
		end
		data.Index = newIndex
	end
	data.SpeedLevel = nil
	data.Version = DATA_VERSION

	if type(data.Meteors) ~= "table" then
		data.Meteors = {}
	end
	for key, entry in pairs(data.Meteors) do
		if type(entry) ~= "table" or type(entry.Id) ~= "string" then
			data.Meteors[key] = nil
		else
			migrateEntry(entry)
		end
	end
	if type(data.Index) == "table" then
		-- Index zählt nur Alien-Ids
		for id in pairs(data.Index) do
			if not Aliens.ById[id] then
				data.Index[id] = nil
			end
		end
	end
	local steps = tonumber(data.Steps) or 0
	data.Steps = (steps == steps and steps >= 0) and steps or 0
end

local function loadData(userId: number): (boolean, any)
	if not storeOk or not store then
		return false, "DataStore nicht verfügbar"
	end
	for attempt = 1, LOAD_ATTEMPTS do
		local lockedByOther = false
		local forceTake = attempt == LOAD_ATTEMPTS
		local ok, result = pcall(function()
			return store:UpdateAsync(keyFor(userId), function(old)
				old = old or {}
				local lock = old.Lock
				if lock and lock.JobId ~= jobId() and os.time() - (lock.Time or 0) < LOCK_EXPIRE and not forceTake then
					lockedByOther = true
					return nil -- nichts schreiben
				end
				old.Lock = { JobId = jobId(), Time = os.time() }
				return old
			end)
		end)
		if ok and not lockedByOther then
			local data = (result and result.Data) or Util.DeepCopy(DEFAULT_DATA)
			-- erst migrieren (Version prüfen), DANN fehlende Felder ergänzen
			local migrated, err = pcall(DataService.Migrate, data)
			if not migrated then
				warn("[DataService] Migration fehlgeschlagen: " .. tostring(err))
				data.Version = data.Version or 1 -- beim nächsten Laden nochmal versuchen
			end
			Util.Reconcile(data, DEFAULT_DATA)
			return true, data
		end
		if not ok then
			warn("[DataService] Laden fehlgeschlagen (Versuch " .. attempt .. "): " .. tostring(result))
		end
		task.wait(lockedByOther and LOCK_WAIT or (attempt * 1.5))
	end
	return false, "Konnte Spielstand nicht laden"
end

local function saveData(userId: number, data, release: boolean): boolean
	if not storeOk or not store then
		return false
	end
	for attempt = 1, 4 do
		local lostLock = false
		local ok, err = pcall(function()
			store:UpdateAsync(keyFor(userId), function(old)
				old = old or {}
				if old.Lock and old.Lock.JobId ~= jobId() then
					-- Ein anderer Server hat den Spielstand übernommen -> NICHT überschreiben
					lostLock = true
					return nil
				end
				return {
					Data = data,
					Lock = (not release) and { JobId = jobId(), Time = os.time() } or nil,
				}
			end)
		end)
		if ok then
			return not lostLock
		end
		warn("[DataService] Speichern fehlgeschlagen (Versuch " .. attempt .. "): " .. tostring(err))
		task.wait(attempt * 1.5)
	end
	return false
end

function DataService.Save(player: Player): boolean
	local profile = DataService.Profiles[player]
	if not profile or not profile.Loaded or profile.NoSave or profile.Releasing then
		return profile ~= nil and profile.NoSave == true
	end
	profile.Data.LastOnline = os.time()
	return saveData(player.UserId, profile.Data, false)
end

local function onPlayerAdded(player: Player)
	local profile = { Loaded = false, Data = nil, NoSave = false }
	DataService.Profiles[player] = profile

	local ok, data = loadData(player.UserId)
	if not ok then
		if RunService:IsStudio() then
			warn(
				"[DataService] Studio: Speichern ist AUS. Aktiviere in Game Settings > Security 'Enable Studio Access to API Services'."
			)
			data = Util.DeepCopy(DEFAULT_DATA)
			profile.NoSave = true
		else
			DataService.Profiles[player] = nil
			if player.Parent then
				player:Kick(
					"Dein Spielstand konnte nicht geladen werden. Bitte tritt erneut bei. (Roblox-Server ausgelastet)"
				)
			end
			return
		end
	end

	if not player.Parent then
		-- Spieler hat das Spiel während des Ladens verlassen -> Lock freigeben
		if not profile.NoSave then
			saveData(player.UserId, data, true)
		end
		DataService.Profiles[player] = nil
		return
	end

	profile.Data = data
	profile.Loaded = true
	for _, callback in ipairs(loadedCallbacks) do
		task.spawn(callback, player, data)
	end
end

local function releaseProfile(player: Player)
	local profile = DataService.Profiles[player]
	if not profile then
		return
	end
	if profile.Releasing then
		-- wird bereits gespeichert (PlayerRemoving + BindToClose gleichzeitig)
		while DataService.Profiles[player] == profile do
			task.wait(0.1)
		end
		return
	end
	profile.Releasing = true
	if profile.Loaded then
		for _, callback in ipairs(releasingCallbacks) do
			local ok, err = pcall(callback, player, profile.Data)
			if not ok then
				warn("[DataService] Releasing-Callback Fehler: " .. tostring(err))
			end
		end
		if not profile.NoSave then
			profile.Data.LastOnline = os.time()
			saveData(player.UserId, profile.Data, true)
		end
	end
	DataService.Profiles[player] = nil
end

-- Spielstand komplett zurücksetzen (Admin)
function DataService.Reset(player: Player)
	local profile = DataService.Profiles[player]
	if profile and profile.Loaded then
		local fresh = Util.DeepCopy(DEFAULT_DATA)
		fresh.Receipts = profile.Data.Receipts -- Käufe bleiben verbucht
		for k in pairs(profile.Data) do
			profile.Data[k] = nil
		end
		for k, v in pairs(fresh) do
			profile.Data[k] = v
		end
	end
end

function DataService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(releaseProfile)

	-- Auto-Save
	task.spawn(function()
		while true do
			task.wait(Config.AutoSaveInterval)
			for player in pairs(DataService.Profiles) do
				if player.Parent then
					task.spawn(DataService.Save, player)
					task.wait(0.5) -- verteilen, um Limits zu schonen
				end
			end
		end
	end)

	-- Server fährt herunter: alles speichern (Roblox gibt max. 30 Sekunden)
	game:BindToClose(function()
		local pending = 0
		for _, player in ipairs(Players:GetPlayers()) do
			pending += 1
			task.spawn(function()
				releaseProfile(player)
				pending -= 1
			end)
		end
		local start = os.clock()
		while pending > 0 and os.clock() - start < 25 do
			task.wait(0.1)
		end
	end)
end

return DataService
