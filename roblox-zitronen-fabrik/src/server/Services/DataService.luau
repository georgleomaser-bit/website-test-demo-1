--[[
	Speichern & Laden mit DataStores.
	In Roblox Studio musst du dafür unter Game Settings → Security
	"Enable Studio Access to API Services" einschalten, sonst wird nicht gespeichert.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Core = require(script.Parent.Core)

local DataService = {}

local store: DataStore? = nil

local function keyFor(userId: number): string
	return "Player_" .. userId
end

local function isNoAccessError(err: any): boolean
	local text = tostring(err)
	return string.find(text, "StudioAccessToApisNotAllowed") ~= nil
		or string.find(text, "403") ~= nil
		or string.find(text, "must publish") ~= nil
		or string.find(text, "not allowed") ~= nil
end

-- Sitzungs-Sperre: Ein Spielstand gehört immer nur einem Server. So kann ein
-- schneller Wiederbeitritt (oder ein zweiter Server) keine alten Daten laden
-- und danach die neuen überschreiben. Autosave erneuert die Sperre.
local LOCK_TIMEOUT = 150
local LOAD_ATTEMPTS = 8
local pendingLeave: { [number]: boolean } = {}

local function lockedByOther(data: any): boolean
	if type(data) ~= "table" or type(data.Lock) ~= "table" then
		return false
	end
	if data.Lock.JobId == game.JobId then
		return false
	end
	return os.time() - (tonumber(data.Lock.Time) or 0) < LOCK_TIMEOUT
end

-- Lädt das Profil. Gibt (profil, darfSpeichern) zurück.
function DataService.Load(player: Player)
	if not store then
		return Economy.NewProfile(), false
	end
	-- Gleicher Server: erst das Speichern vom letzten Verlassen abwarten
	local waited = 0
	while pendingLeave[player.UserId] and waited < 20 do
		task.wait(0.5)
		waited += 0.5
	end
	local key = keyFor(player.UserId)
	for attempt = 1, LOAD_ATTEMPTS do
		local result = nil
		local blocked = false
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(key, function(old)
				blocked = false
				result = nil
				-- Beim letzten Versuch übernehmen wir die Sperre trotzdem (Server abgestürzt?)
				if lockedByOther(old) and attempt < LOAD_ATTEMPTS then
					blocked = true
					return nil
				end
				local profile = if old ~= nil then Economy.Reconcile(old) else Economy.NewProfile()
				profile.Lock = { JobId = game.JobId, Time = os.time() }
				result = profile
				return profile
			end)
		end)
		if ok and result and not blocked then
			return result, true
		end
		if not player.Parent then
			break
		end
		if not ok then
			warn("[ZitronenFabrik] Laden fehlgeschlagen (Versuch " .. attempt .. "): " .. tostring(err))
			if isNoAccessError(err) then
				break
			end
			task.wait(math.min(attempt * 2, 6))
		else
			-- Ein anderer Server speichert gerade noch – kurz warten
			task.wait(4)
		end
	end
	-- Lieber nicht speichern als einen Spielstand zu überschreiben
	return Economy.NewProfile(), false
end

local function cleanNumbers(t)
	for k, v in pairs(t) do
		if type(v) == "number" then
			if v ~= v then
				t[k] = 0
			elseif v == math.huge then
				t[k] = 1e300
			elseif v == -math.huge then
				t[k] = 0
			end
		elseif type(v) == "table" then
			cleanNumbers(v)
		end
	end
end

-- Speichert das Profil. releaseLock = true beim Verlassen (Sperre freigeben).
function DataService.Save(session, releaseLock: boolean?): boolean
	if not store or not session.CanSave or not session.Loaded then
		return false
	end
	local profile = session.Profile
	profile.LastOnline = os.time()
	profile.Lock = if releaseLock then nil else { JobId = game.JobId, Time = os.time() }
	cleanNumbers(profile)
	local lost = false
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(keyFor(session.Player.UserId), function(old)
			lost = false
			if lockedByOther(old) then
				lost = true
				return nil
			end
			return profile
		end)
	end)
	if not ok then
		warn("[ZitronenFabrik] Speichern fehlgeschlagen: " .. tostring(err))
	end
	if lost then
		-- Ein anderer Server hat den Spielstand übernommen: nicht mehr überschreiben
		session.CanSave = false
		warn("[ZitronenFabrik] Spielstand wird auf einem anderen Server benutzt – Speichern hier gestoppt.")
	end
	return ok and not lost
end

-- Beim Verlassen: mit Wiederholungen speichern und Sperre freigeben
function DataService.SaveOnLeave(session)
	local userId = session.Player.UserId
	if pendingLeave[userId] then
		return -- wird schon gespeichert (z. B. Server fährt herunter)
	end
	pendingLeave[userId] = true
	for attempt = 1, 3 do
		if DataService.Save(session, true) or not session.CanSave then
			break
		end
		task.wait(attempt * 2)
	end
	pendingLeave[userId] = nil
end

function DataService.Init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[ZitronenFabrik] Kein DataStore verfügbar – es wird nicht gespeichert. " .. tostring(result))
	end
end

function DataService.Start()
	-- Automatisch speichern
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveInterval)
			for _, session in pairs(Core.Sessions) do
				task.spawn(DataService.Save, session)
			end
		end
	end)

	-- Beim Herunterfahren alle speichern
	game:BindToClose(function()
		for _, session in pairs(Core.Sessions) do
			task.spawn(DataService.SaveOnLeave, session)
		end
		task.wait(0.1)
		local started = os.clock()
		while next(pendingLeave) ~= nil and os.clock() - started < 25 do
			task.wait(0.2)
		end
	end)
end

DataService.Players = Players

return DataService
