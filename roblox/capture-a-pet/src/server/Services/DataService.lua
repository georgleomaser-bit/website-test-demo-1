-- Loads, autosaves and saves player data with a session lock so the same account can never
-- be loaded on two servers at once (prevents item duplication).
-- If DataStores are not available (Studio without "Enable Studio Access to API Services"),
-- the game still runs with temporary data and prints a warning.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Game = require(Shared.Config.Game)

local DataService = {}

local LOCK_EXPIRE_SECONDS = Game.AutosaveSeconds * 5
local SESSION_ID = game.JobId ~= "" and game.JobId or ("studio-" .. HttpService:GenerateGUID(false))

local store = nil
local storeAvailable = false
local profiles = {} -- [player] = { Data = table, Dirty = bool, Saving = bool }
local loadedCallbacks = {}
local releasingCallbacks = {}

local function defaultData()
	return {
		Version = 1,
		Cash = 0,
		Speed = 0,
		Rebirths = 0,
		Treadmill = 1,
		Upgrades = { Cash = 0, Training = 0, Luck = 0, Hatch = 0, PenSlots = 0, Incubators = 0 },
		Animals = {},
		NextUid = 1,
		Mount = "",
		Eggs = {},
		Bait = 3,
		Index = {},
		IndexClaimed = { Zones = {}, Milestones = {} },
		Boosts = {},
		Daily = { Streak = 0, Last = 0 },
		Tasks = { Day = 0, List = {}, AllClaimed = false },
		Expedition = { Level = 0, Zones = { false, false, false, false } },
		Codes = {},
		Receipts = {},
		Stats = { Tamed = 0, Hatched = 0, Stolen = 0, EggsDelivered = 0, Playtime = 0, TotalCash = 0, TotalSpeed = 0 },
		MaxZone = 1,
		BaitBagDay = 0,
		LastOnline = 0,
		SlowMode = false,
	}
end

-- Fills in fields added in later versions without touching existing values.
local function reconcile(data, template)
	for key, value in pairs(template) do
		if data[key] == nil then
			if type(value) == "table" then
				data[key] = table.clone(value)
				reconcile(data[key], value)
			else
				data[key] = value
			end
		elseif type(value) == "table" and type(data[key]) == "table" and next(value) ~= nil and #value == 0 then
			reconcile(data[key], value)
		end
	end
	-- sanitize numbers that could have become invalid
	for _, key in ipairs({ "Cash", "Speed" }) do
		local v = data[key]
		if type(v) ~= "number" or v ~= v or v == math.huge or v < 0 then
			data[key] = 0
		end
	end
	return data
end

local function keyFor(userId: number): string
	return "Player_" .. userId
end

local function retry(fn, attempts: number)
	local lastErr
	for i = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		task.wait(math.min(2 ^ i, 8))
	end
	return false, lastErr
end

local function loadData(player: Player)
	if not storeAvailable then
		return reconcile(defaultData(), defaultData())
	end
	local key = keyFor(player.UserId)
	for attempt = 1, 6 do
		local lockedElsewhere = false
		local ok, result = retry(function()
			return store:UpdateAsync(key, function(old)
				old = old or { Data = defaultData() }
				local lock = old.Lock
				if lock and lock.Session ~= SESSION_ID and os.time() - (lock.Time or 0) < LOCK_EXPIRE_SECONDS then
					lockedElsewhere = true
					return nil -- abort, keep the other server's lock
				end
				old.Lock = { Session = SESSION_ID, Time = os.time() }
				return old
			end)
		end, 3)
		if not ok then
			warn("[DataService] Load failed for", player.Name, result)
			return nil
		end
		if not lockedElsewhere and result then
			return reconcile(result.Data or defaultData(), defaultData())
		end
		if not player.Parent then
			return nil
		end
		-- another server still holds the lock (e.g. the player just switched servers)
		task.wait(attempt * 2)
	end
	return nil
end

local function saveData(player: Player, release: boolean): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	if not storeAvailable then
		return true
	end
	while profile.Saving do
		task.wait(0.1)
	end
	profile.Saving = true
	profile.Data.LastOnline = os.time()
	local snapshot = profile.Data
	local ok, err = retry(function()
		return store:UpdateAsync(keyFor(player.UserId), function(old)
			old = old or {}
			if old.Lock and old.Lock.Session ~= SESSION_ID and os.time() - (old.Lock.Time or 0) < LOCK_EXPIRE_SECONDS then
				return nil -- someone else owns the session now; never overwrite their data
			end
			old.Data = snapshot
			old.Lock = (not release) and { Session = SESSION_ID, Time = os.time() } or nil
			return old
		end)
	end, release and 5 or 3)
	profile.Saving = false
	if not ok then
		warn("[DataService] Save failed for", player.Name, err)
	end
	return ok
end

function DataService.Init(_services)
	local ok = pcall(function()
		store = DataStoreService:GetDataStore(Game.DataStoreName)
		-- a cheap call that fails quickly when API access is disabled in Studio
		store:GetAsync("__probe")
	end)
	storeAvailable = ok
	if not ok then
		warn("[DataService] DataStores are not available. Data will NOT be saved. In Studio enable Game Settings > Security > Enable Studio Access to API Services.")
	end
end

function DataService.Start()
	local function onPlayerAdded(player: Player)
		local data = loadData(player)
		if not player.Parent then
			if data and storeAvailable then
				-- player left while loading: release the lock we just took
				profiles[player] = { Data = data, Saving = false }
				saveData(player, true)
				profiles[player] = nil
			end
			return
		end
		if not data then
			player:Kick("Your data could not be loaded. Please rejoin in a moment.")
			return
		end
		profiles[player] = { Data = data, Saving = false }
		for _, callback in ipairs(loadedCallbacks) do
			task.spawn(callback, player, data)
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		if not profile then
			return
		end
		for _, callback in ipairs(releasingCallbacks) do
			local ok, err = pcall(callback, player, profile.Data)
			if not ok then
				warn("[DataService] release callback error", err)
			end
		end
		saveData(player, true)
		profiles[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(Game.AutosaveSeconds)
			for player in pairs(profiles) do
				task.spawn(saveData, player, false)
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() and not storeAvailable then
			return
		end
		local pending = 0
		for player in pairs(profiles) do
			pending += 1
			task.spawn(function()
				for _, callback in ipairs(releasingCallbacks) do
					pcall(callback, player, profiles[player] and profiles[player].Data)
				end
				saveData(player, true)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)
end

function DataService.get(player: Player)
	local profile = profiles[player]
	return profile and profile.Data or nil
end

function DataService.isLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

-- Saves right away (used after Robux purchases). Returns true on success.
function DataService.saveNow(player: Player): boolean
	return saveData(player, false)
end

function DataService.onLoaded(callback)
	table.insert(loadedCallbacks, callback)
end

-- Called before the final save when a player leaves; use it to clean up runtime state.
function DataService.onReleasing(callback)
	table.insert(releasingCallbacks, callback)
end

function DataService.reset(player: Player)
	local profile = profiles[player]
	if profile then
		profile.Data = reconcile(defaultData(), defaultData())
		return profile.Data
	end
	return nil
end

DataService.defaultData = defaultData

return DataService
