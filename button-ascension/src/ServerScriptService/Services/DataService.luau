--[[
	DataService (ModuleScript)
	Location: ServerScriptService/Services/DataService
	Depends on: Core/DataSchema, Shared/Util, Shared/Signal, Shared/Config/GameConfig

	Loads, saves and protects player data in DataStoreService.

	Record format stored under "Player_<UserId>":
	    { Schema = <version>, Data = <player data>, Lock = { JobId, PlaceId, Time } | nil, UpdatedAt }

	Session locking
	  * Loading uses UpdateAsync to claim the lock. If another live server holds
	    a fresh lock, loading waits and retries (that server is usually saving
	    the player right now). Locks older than LockStaleSeconds are treated as
	    abandoned (crashed server) and taken over.
	  * Every save verifies this server still owns the lock. If another server
	    took it over, this server stops saving and removes the player, so two
	    servers can never overwrite each other.
	  * Leaving / shutdown saves with release = true, which clears the lock.

	Failure handling
	  * Every DataStore call is wrapped in pcall, retried with exponential
	    backoff and waits for request budget.
	  * If data cannot be loaded in a live server the player is kicked with an
	    explanation instead of playing on empty data that could later overwrite
	    real progress (GameConfig.Data.KickOnLoadFailure).
	  * In Studio without "Enable Studio Access to API Services", players get a
	    clearly labelled temporary profile that is never saved.
	  * Saving is never reported as guaranteed: failures are counted, logged and
	    surfaced to admins (GetStatus).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Util = require(Shared.Util)
local Signal = require(Shared.Signal)
local DataSchema = require(script.Parent.Parent.Core.DataSchema)

local CONFIG = GameConfig.Data

local DataService = {
	Name = "DataService",
	Profiles = {} :: { [Player]: any },
	ProfileLoaded = Signal.new(),
	ShuttingDown = false,
	Status = {
		Available = true,
		Mode = "persistent",
		LastError = nil :: string?,
		Loads = 0,
		LoadFailures = 0,
		Saves = 0,
		SaveFailures = 0,
		LockConflicts = 0,
		LastAutosave = 0,
	},
}

local loading: { [Player]: boolean } = {}
local releasing: { [number]: boolean } = {}

local function keyFor(userId: number): string
	return CONFIG.KeyPrefix .. tostring(userId)
end

local function lockIsActive(lock: any, now: number): boolean
	return type(lock) == "table"
		and lock.JobId ~= game.JobId
		and type(lock.Time) == "number"
		and now - lock.Time < CONFIG.LockStaleSeconds
end

local function backoff(attempt: number): number
	return math.min(8, 0.5 * 2 ^ attempt)
end

function DataService:Init(services)
	self.Services = services
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(CONFIG.StoreName)
	end)
	if ok then
		self.Store = store
	else
		self.Status.Available = false
		self.Status.LastError = tostring(store)
	end
end

function DataService:Start()
	if self.Store and RunService:IsStudio() then
		-- Probe once: in Studio, DataStores error unless API access is enabled.
		local ok, err = pcall(function()
			return self.Store:GetAsync("__probe")
		end)
		if not ok then
			self.Status.Available = false
			self.Status.LastError = tostring(err)
		end
	end
	if not self.Status.Available then
		self.Status.Mode = "temporary"
		warn(
			"[DataService] DataStores are unavailable ("
				.. tostring(self.Status.LastError)
				.. "). In Studio, enable Game Settings > Security > 'Enable Studio Access to API Services'. "
				.. "Players receive temporary data that is NOT saved."
		)
	end

	Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerRemoving(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(self._onPlayerAdded, self, player)
	end

	game:BindToClose(function()
		self:_onClose()
	end)

	task.spawn(function()
		while not self.ShuttingDown do
			task.wait(CONFIG.AutosaveInterval)
			self:_autosave()
		end
	end)
end

-- Public API ------------------------------------------------------------------

function DataService:GetProfile(player: Player)
	return self.Profiles[player]
end

function DataService:WaitForProfile(player: Player, timeout: number?)
	local deadline = os.clock() + (timeout or 30)
	while player.Parent == Players and os.clock() < deadline do
		local profile = self.Profiles[player]
		if profile then
			return profile
		end
		task.wait(0.1)
	end
	return self.Profiles[player]
end

function DataService:GetProfileByUserId(userId: number)
	for player, profile in pairs(self.Profiles) do
		if player.UserId == userId then
			return profile
		end
	end
	return nil
end

function DataService:IsPersistent(): boolean
	return self.Status.Available
end

function DataService:GetStatus()
	return table.clone(self.Status)
end

-- Saves immediately (used after important changes such as ascending).
function DataService:SaveNow(profile): boolean
	return self:_save(profile, false)
end

-- Budget ------------------------------------------------------------------------

local function waitForBudget(requestType: Enum.DataStoreRequestType)
	local deadline = os.clock() + 10
	while os.clock() < deadline do
		local ok, budget = pcall(function()
			return DataStoreService:GetRequestBudgetForRequestType(requestType)
		end)
		if not ok or budget >= 1 then
			return
		end
		task.wait(0.5)
	end
end

-- Loading ------------------------------------------------------------------------

-- Returns ({ data, isNew } | nil, status). status: ok | locked | newer | corrupt | error
function DataService:_loadData(userId: number)
	local key = keyFor(userId)
	local lastStatus = "error"
	for attempt = 1, CONFIG.LoadAttempts do
		waitForBudget(Enum.DataStoreRequestType.UpdateAsync)
		local status, loaded = nil, nil
		local ok, err = pcall(function()
			self.Store:UpdateAsync(key, function(record)
				status, loaded = nil, nil
				if record ~= nil and type(record) ~= "table" then
					status = "corrupt"
					return nil
				end
				local rec = record or {}
				local now = os.time()
				if lockIsActive(rec.Lock, now) then
					status = "locked"
					return nil
				end
				local raw, versionOk = DataSchema.migrate(rec.Data)
				if not versionOk then
					status = "newer"
					return nil
				end
				loaded = { raw = raw, isNew = rec.Data == nil }
				rec.Lock = { JobId = game.JobId, PlaceId = game.PlaceId, Time = now }
				rec.Schema = DataSchema.CURRENT_VERSION
				status = "ok"
				return rec
			end)
		end)

		if ok and status == "ok" then
			local data
			if loaded.raw == nil then
				data = DataSchema.default()
			else
				local issues
				data, issues = DataSchema.sanitize(loaded.raw)
				if #issues > 0 then
					warn(`[DataService] Sanitised data for {userId}: {table.concat(issues, "; ")}`)
				end
			end
			return { data = data, isNew = loaded.isNew }, "ok"
		elseif ok and (status == "newer" or status == "corrupt") then
			return nil, status
		end

		if not ok then
			self.Status.LastError = tostring(err)
			lastStatus = "error"
			warn(`[DataService] Load attempt {attempt} for {userId} failed: {err}`)
			task.wait(backoff(attempt))
		else
			lastStatus = "locked"
			self.Status.LockConflicts += 1
			task.wait(CONFIG.LockedRetryDelay)
		end
	end
	return nil, lastStatus
end

function DataService:_newProfile(player: Player, data, temporary: boolean, isNew: boolean)
	return {
		Player = player,
		UserId = player.UserId,
		Key = keyFor(player.UserId),
		Data = data,
		Temporary = temporary,
		IsNew = isNew,
		Runtime = {},
		Dirty = {},
		LoadedAt = os.clock(),
		Saving = false,
		LockLost = false,
	}
end

local KICK_MESSAGES = {
	locked = "Your progress is still being saved by another server. Please rejoin in a minute — nothing is lost.",
	newer = "Your progress was saved by a newer version of the game. Please rejoin to get the latest version.",
	corrupt = "We could not read your saved progress safely, so we stopped to protect it. Please contact the game owner.",
	error = "Roblox data services are not responding right now. Please rejoin in a minute — your progress is safe.",
}

function DataService:_onPlayerAdded(player: Player)
	if loading[player] or self.Profiles[player] then
		return
	end
	loading[player] = true

	-- If this user is still being saved after leaving this very server, wait for it.
	local deadline = os.clock() + 30
	while releasing[player.UserId] and os.clock() < deadline do
		task.wait(0.2)
	end

	local profile
	if not self.Status.Available then
		if RunService:IsStudio() or not CONFIG.KickOnLoadFailure then
			profile = self:_newProfile(player, DataSchema.default(), true, true)
		else
			loading[player] = nil
			self.Status.LoadFailures += 1
			player:Kick(KICK_MESSAGES.error)
			return
		end
	else
		local result, status = self:_loadData(player.UserId)
		if player.Parent ~= Players then
			-- Left while loading: give the lock back without touching the data.
			loading[player] = nil
			if result then
				self:_releaseLockOnly(player.UserId)
			end
			return
		end
		if not result then
			self.Status.LoadFailures += 1
			warn(`[DataService] Could not load data for {player.Name} ({player.UserId}): {status}`)
			if RunService:IsStudio() and status == "error" then
				profile = self:_newProfile(player, DataSchema.default(), true, true)
			else
				loading[player] = nil
				player:Kick(KICK_MESSAGES[status] or KICK_MESSAGES.error)
				return
			end
		else
			self.Status.Loads += 1
			profile = self:_newProfile(player, result.data, false, result.isNew)
		end
	end

	loading[player] = nil
	if player.Parent ~= Players then
		return
	end
	profile.Data.Meta.Sessions += 1
	self.Profiles[player] = profile

	for _, name in ipairs(self.Services.Order) do
		local service = self.Services[name]
		if service ~= self and service.OnProfileLoaded then
			local ok, err = pcall(service.OnProfileLoaded, service, profile)
			if not ok then
				warn(`[DataService] {name}.OnProfileLoaded failed for {player.Name}: {err}`)
			end
		end
	end
	self.Services.SyncService:SendFull(profile)
	if profile.Temporary then
		self.Services.Net.notify(player, "Warning", {
			Text = "Saving is disabled in this session. Progress will not be kept.",
		})
	end
	self.ProfileLoaded:Fire(profile)
end

-- Saving ------------------------------------------------------------------------------

function DataService:_save(profile, release: boolean): boolean
	if profile.Temporary or profile.LockLost then
		return false
	end
	-- Serialise saves per profile so a release never races an autosave.
	local waitDeadline = os.clock() + 30
	while profile.Saving and os.clock() < waitDeadline do
		task.wait(0.1)
	end
	profile.Saving = true

	local snapshot = Util.deepCopy(profile.Data)
	local now = os.time()
	snapshot.Meta.LastSave = now
	snapshot.Meta.LastSeen = now
	snapshot.Version = DataSchema.CURRENT_VERSION

	local success = false
	for attempt = 1, CONFIG.SaveAttempts do
		waitForBudget(Enum.DataStoreRequestType.UpdateAsync)
		local lost = false
		local ok, err = pcall(function()
			self.Store:UpdateAsync(profile.Key, function(record)
				lost = false
				local rec = if type(record) == "table" then record else {}
				local lock = rec.Lock
				if type(lock) == "table" and lock.JobId ~= game.JobId then
					lost = true
					return nil
				end
				rec.Data = snapshot
				rec.Schema = DataSchema.CURRENT_VERSION
				rec.UpdatedAt = os.time()
				rec.Lock = if release then nil else { JobId = game.JobId, PlaceId = game.PlaceId, Time = os.time() }
				return rec
			end)
		end)
		if ok then
			if lost then
				self.Status.LockConflicts += 1
				profile.LockLost = true
				profile.Saving = false
				self:_onLockLost(profile)
				return false
			end
			self.Status.Saves += 1
			profile.Data.Meta.LastSave = now
			success = true
			break
		end
		self.Status.SaveFailures += 1
		self.Status.LastError = tostring(err)
		warn(`[DataService] Save attempt {attempt} for {profile.UserId} failed: {err}`)
		if attempt < CONFIG.SaveAttempts then
			task.wait(backoff(attempt))
		end
	end
	profile.Saving = false
	if not success then
		warn(`[DataService] Could not save data for {profile.UserId} after {CONFIG.SaveAttempts} attempts.`)
	end
	return success
end

function DataService:_onLockLost(profile)
	warn(`[DataService] Session lock for {profile.UserId} was taken by another server; this server stopped saving.`)
	local player = profile.Player
	if self.Profiles[player] == profile then
		self.Profiles[player] = nil
	end
	if player.Parent == Players then
		player:Kick("Your progress was opened in another server. Please rejoin.")
	end
end

function DataService:_releaseLockOnly(userId: number)
	pcall(function()
		self.Store:UpdateAsync(keyFor(userId), function(record)
			if type(record) ~= "table" then
				return nil
			end
			if type(record.Lock) == "table" and record.Lock.JobId == game.JobId then
				record.Lock = nil
				return record
			end
			return nil
		end)
	end)
end

function DataService:_runReleasingHooks(profile)
	for _, name in ipairs(self.Services.Order) do
		local service = self.Services[name]
		if service ~= self and service.OnProfileReleasing then
			local ok, err = pcall(service.OnProfileReleasing, service, profile)
			if not ok then
				warn(`[DataService] {name}.OnProfileReleasing failed: {err}`)
			end
		end
	end
end

function DataService:_onPlayerRemoving(player: Player)
	local profile = self.Profiles[player]
	if not profile then
		return
	end
	self.Profiles[player] = nil
	releasing[player.UserId] = true
	self:_runReleasingHooks(profile)
	self:_save(profile, true)
	profile.Released = true
	releasing[player.UserId] = nil
end

function DataService:_autosave()
	self.Status.LastAutosave = os.time()
	local list = {}
	for _, profile in pairs(self.Profiles) do
		if not profile.Temporary then
			table.insert(list, profile)
		end
	end
	for _, profile in ipairs(list) do
		if self.ShuttingDown then
			return
		end
		if self.Profiles[profile.Player] == profile then
			task.spawn(self._save, self, profile, false)
			task.wait(0.25)
		end
	end
end

function DataService:_onClose()
	self.ShuttingDown = true
	local pending = 0
	for player, profile in pairs(self.Profiles) do
		self.Profiles[player] = nil
		releasing[profile.UserId] = true
		pending += 1
		task.spawn(function()
			self:_runReleasingHooks(profile)
			self:_save(profile, true)
			releasing[profile.UserId] = nil
			pending -= 1
		end)
	end
	-- Also wait for saves that PlayerRemoving started (players are removed as the
	-- server shuts down); returning early could end the server mid-save.
	local deadline = os.clock() + CONFIG.ShutdownTimeout
	while (pending > 0 or next(releasing) ~= nil) and os.clock() < deadline do
		task.wait(0.1)
	end
	if pending > 0 or next(releasing) ~= nil then
		warn(`[DataService] Shutdown timed out with unsaved profile(s).`)
	end
end

-- Offline access (admin tools) -----------------------------------------------------------

-- Reads a player's stored data without locking it. Returns (data | nil, info).
function DataService:ReadOffline(userId: number)
	if not self.Status.Available then
		return nil, { status = "unavailable" }
	end
	local ok, record = pcall(function()
		return self.Store:GetAsync(keyFor(userId))
	end)
	if not ok then
		return nil, { status = "error", message = tostring(record) }
	end
	if record == nil then
		return nil, { status = "nodata" }
	end
	if type(record) ~= "table" then
		return nil, { status = "corrupt" }
	end
	local raw, versionOk = DataSchema.migrate(record.Data)
	if not versionOk then
		return nil, { status = "newer" }
	end
	local data = DataSchema.sanitize(raw)
	return data, { status = "ok", locked = lockIsActive(record.Lock, os.time()) }
end

--[[
	Safely modifies an OFFLINE player's data. The mutator receives sanitised
	data and must be pure (no yielding); it returns (ok, message).
	The update is refused when the player is online in this server or when an
	active session lock shows they are playing in another server, so an
	offline edit can never be overwritten by (or overwrite) a live session.
]]
function DataService:UpdateOffline(userId: number, mutator: (any) -> (boolean, string?)): (boolean, string)
	if not self.Status.Available then
		return false, "DataStores are unavailable in this session."
	end
	if Players:GetPlayerByUserId(userId) then
		return false, "That player is online in this server; use the normal action."
	end
	local result, message = "error", "Unknown error"
	local ok, err = pcall(function()
		self.Store:UpdateAsync(keyFor(userId), function(record)
			result, message = "error", "Unknown error"
			if record == nil then
				result, message = "nodata", "No saved data exists for that UserId."
				return nil
			end
			if type(record) ~= "table" then
				result, message = "corrupt", "Stored data is unreadable."
				return nil
			end
			if lockIsActive(record.Lock, os.time()) then
				result, message = "locked", "That player is currently playing in another server. Try again when they are offline."
				return nil
			end
			local raw, versionOk = DataSchema.migrate(record.Data)
			if not versionOk then
				result, message = "newer", "Data was saved by a newer game version."
				return nil
			end
			local data = DataSchema.sanitize(raw)
			local okMut, mutOk, mutMessage = pcall(mutator, data)
			if not okMut then
				result, message = "error", tostring(mutOk)
				return nil
			end
			if not mutOk then
				result, message = "rejected", mutMessage or "Change rejected."
				return nil
			end
			record.Data = data
			record.Schema = DataSchema.CURRENT_VERSION
			record.UpdatedAt = os.time()
			result, message = "ok", mutMessage or "Saved."
			return record
		end)
	end)
	if not ok then
		return false, "DataStore error: " .. tostring(err)
	end
	return result == "ok", message
end

return DataService
