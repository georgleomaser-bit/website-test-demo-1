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

-- Lädt das Profil. Gibt (profil, darfSpeichern) zurück.
function DataService.Load(player: Player)
	if not store then
		return Economy.NewProfile(), false
	end
	for attempt = 1, 3 do
		local ok, data = pcall(function()
			return (store :: DataStore):GetAsync(keyFor(player.UserId))
		end)
		if ok then
			if data == nil then
				return Economy.NewProfile(), true
			end
			return Economy.Reconcile(data), true
		end
		warn("[ZitronenFabrik] Laden fehlgeschlagen (Versuch " .. attempt .. "): " .. tostring(data))
		if isNoAccessError(data) or not player.Parent then
			break
		end
		task.wait(attempt * 2)
	end
	-- Lieber nicht speichern als einen alten Spielstand zu überschreiben
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

function DataService.Save(session): boolean
	if not store or not session.CanSave or not session.Loaded then
		return false
	end
	local profile = session.Profile
	profile.LastOnline = os.time()
	cleanNumbers(profile)
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(keyFor(session.Player.UserId), function()
			return profile
		end)
	end)
	if not ok then
		warn("[ZitronenFabrik] Speichern fehlgeschlagen: " .. tostring(err))
	end
	return ok
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
		local pending = 0
		for _, session in pairs(Core.Sessions) do
			pending += 1
			task.spawn(function()
				DataService.Save(session)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.2)
		end
	end)
end

DataService.Players = Players

return DataService
