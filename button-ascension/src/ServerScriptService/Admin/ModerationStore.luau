--[[
	ModerationStore (ModuleScript)
	Location: ServerScriptService/Admin/ModerationStore
	Depends on: Admin/AdminConfig

	SERVER-ONLY storage for the two moderation lists that change while the game
	runs:
	  * Staff roles an Owner handed out in the game ([UserId] = Moderator | Admin)
	  * Bans ([UserId] = { Until, Reason, By, ... }; Until 0 = permanent)

	Both live in one DataStore (AdminConfig.Moderation.StoreName), keyed by
	UserId only. Writes use UpdateAsync, so two servers changing the lists at
	the same time never overwrite each other. After a write the server
	publishes "this list changed" over MessagingService; receiving servers do
	NOT trust the message and simply re-read the DataStore. Every server also
	re-reads both lists every RefreshSeconds in case a message is lost.

	Everything read from the DataStore is sanitised: unknown roles (including
	"Owner"), malformed ids and expired bans are dropped.

	Without DataStore access (Studio without API access) the lists are kept in
	memory for that session only and ModerationStore.Persistent is false.
]]

local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AdminConfig = require(script.Parent.AdminConfig)
local CONFIG = AdminConfig.Moderation

export type StaffEntry = { Role: string, Name: string, By: number, ByName: string, At: number }
export type BanEntry = {
	Name: string,
	Reason: string,
	By: number,
	ByName: string,
	ByRank: number,
	At: number,
	Until: number, -- unix time; 0 = permanent
}

local KEYS = { staff = "StaffRoles", bans = "Bans" }

local ModerationStore = {
	Staff = {} :: { [number]: StaffEntry },
	Bans = {} :: { [number]: BanEntry },
	Loaded = { staff = false, bans = false },
	Persistent = false,
	LastError = nil :: string?,
}

local store: DataStore? = nil
local listeners: { (string) -> () } = {}
local grantable: { [string]: boolean } = {}
for _, role in ipairs(CONFIG.GrantableRoles) do
	if role ~= "Owner" and AdminConfig.Roles[role] then
		grantable[role] = true
	end
end

-- Sanitising -------------------------------------------------------------------------------

local function text(value: any, max: number, fallback: string): string
	if type(value) == "string" and #value > 0 then
		return string.sub(value, 1, max)
	end
	return fallback
end

local function number(value: any): number
	return if type(value) == "number" and value == value and math.abs(value) < 2 ^ 53 then value else 0
end

local function userIdOf(key: any): number?
	local id = tonumber(key)
	if id and id == math.floor(id) and math.abs(id) < 2 ^ 53 then
		return id
	end
	return nil
end

local function cleanStaff(raw: any): { [number]: StaffEntry }
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for key, entry in pairs(raw) do
		local userId = userIdOf(key)
		if userId and type(entry) == "table" and grantable[entry.Role] then
			out[userId] = {
				Role = entry.Role,
				Name = text(entry.Name, 60, "#" .. tostring(userId)),
				By = number(entry.By),
				ByName = text(entry.ByName, 60, "?"),
				At = number(entry.At),
			}
		end
	end
	return out
end

local function isActive(entry: BanEntry, now: number): boolean
	return entry.Until == 0 or entry.Until > now
end

local function cleanBans(raw: any, now: number): { [number]: BanEntry }
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for key, entry in pairs(raw) do
		local userId = userIdOf(key)
		if userId and type(entry) == "table" then
			local clean: BanEntry = {
				Name = text(entry.Name, 60, "#" .. tostring(userId)),
				Reason = text(entry.Reason, 300, "Banned by staff."),
				By = number(entry.By),
				ByName = text(entry.ByName, 60, "?"),
				ByRank = number(entry.ByRank),
				At = number(entry.At),
				Until = math.max(0, number(entry.Until)),
			}
			if isActive(clean, now) then
				out[userId] = clean
			end
		end
	end
	return out
end

local function clean(kind: string, raw: any)
	return if kind == "staff" then cleanStaff(raw) else cleanBans(raw, os.time())
end

-- DataStore values are JSON: use string keys.
local function encode(map: { [number]: any }): { [string]: any }
	local out = {}
	for userId, entry in pairs(map) do
		out[tostring(userId)] = entry
	end
	return out
end

local function count(map): number
	local n = 0
	for _ in pairs(map) do
		n += 1
	end
	return n
end

-- Loading and change notifications -------------------------------------------------------------

local function notify(kind: string)
	for _, listener in ipairs(listeners) do
		task.spawn(listener, kind)
	end
end

local function apply(kind: string, raw: any)
	if kind == "staff" then
		ModerationStore.Staff = cleanStaff(raw)
	else
		ModerationStore.Bans = cleanBans(raw, os.time())
	end
end

-- Re-reads one list from the DataStore. Returns false if Roblox did not answer.
function ModerationStore.reload(kind: string): boolean
	if not store then
		return true
	end
	local ok, raw = pcall(function()
		return (store :: DataStore):GetAsync(KEYS[kind])
	end)
	if not ok then
		ModerationStore.LastError = tostring(raw)
		return false
	end
	apply(kind, raw)
	ModerationStore.Loaded[kind] = true
	notify(kind)
	return true
end

local function publish(kind: string)
	if not store then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:PublishAsync(CONFIG.Topic, { Kind = kind, JobId = game.JobId })
		end)
		if not ok then
			-- Other servers still pick the change up on their next periodic refresh.
			warn("[ModerationStore] Could not notify other servers: " .. tostring(err))
		end
	end)
end

function ModerationStore.onChanged(listener: (string) -> ())
	table.insert(listeners, listener)
end

function ModerationStore.init(persistent: boolean)
	if persistent then
		local ok, result = pcall(function()
			return DataStoreService:GetDataStore(CONFIG.StoreName)
		end)
		if ok then
			store = result
		else
			warn("[ModerationStore] DataStore unavailable: " .. tostring(result))
		end
	end
	ModerationStore.Persistent = store ~= nil
	if not store then
		-- Temporary session: start empty, keep changes in memory only.
		ModerationStore.Loaded.staff = true
		ModerationStore.Loaded.bans = true
		return
	end

	task.spawn(function()
		local attempt = 0
		while not (ModerationStore.Loaded.staff and ModerationStore.Loaded.bans) do
			for kind in pairs(KEYS) do
				if not ModerationStore.Loaded[kind] then
					ModerationStore.reload(kind)
				end
			end
			if ModerationStore.Loaded.staff and ModerationStore.Loaded.bans then
				break
			end
			attempt += 1
			warn(`[ModerationStore] Loading the moderation lists failed (attempt {attempt}); retrying.`)
			task.wait(math.min(30, 2 ^ attempt))
		end
	end)

	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(CONFIG.Topic, function(message)
				local data = if type(message) == "table" then message.Data else nil
				local kind = if type(data) == "table" then data.Kind else nil
				if type(kind) == "string" and KEYS[kind] and data.JobId ~= game.JobId then
					-- Never trust the message itself: re-read the DataStore.
					ModerationStore.reload(kind)
				end
			end)
		end)
		if not ok then
			warn("[ModerationStore] Live updates between servers unavailable: " .. tostring(err))
		end
	end)

	task.spawn(function()
		while true do
			task.wait(CONFIG.RefreshSeconds)
			for kind in pairs(KEYS) do
				ModerationStore.reload(kind)
			end
		end
	end)
end

-- Waits until a list has been loaded once (or the timeout passes).
function ModerationStore.waitLoaded(kind: string, timeout: number): boolean
	local deadline = os.clock() + timeout
	while not ModerationStore.Loaded[kind] and os.clock() < deadline do
		task.wait(0.2)
	end
	return ModerationStore.Loaded[kind]
end

-- Writing ------------------------------------------------------------------------------------------

--[[
	Sets (entry) or removes (nil) one user's entry in a list, atomically.
	Returns ok, error message. The caller has already checked permissions.
]]
function ModerationStore.write(kind: string, userId: number, entry: any): (boolean, string?)
	assert(KEYS[kind], "unknown moderation list")
	local limit = if kind == "staff" then CONFIG.MaxStaff else CONFIG.MaxBans
	if not store then
		local map = if kind == "staff" then ModerationStore.Staff else ModerationStore.Bans
		if entry ~= nil and map[userId] == nil and count(map) >= limit then
			return false, "The list is full."
		end
		local updated = table.clone(map)
		updated[userId] = entry
		apply(kind, encode(updated))
		notify(kind)
		return true, nil
	end

	local full = false
	local result = nil
	local ok, err = pcall(function()
		result = (store :: DataStore):UpdateAsync(KEYS[kind], function(raw)
			full = false
			local map = clean(kind, raw)
			if entry ~= nil and map[userId] == nil and count(map) >= limit then
				full = true
				return nil
			end
			map[userId] = entry
			return encode(map)
		end)
	end)
	if not ok then
		ModerationStore.LastError = tostring(err)
		return false, "Roblox data services did not respond, so nothing was changed. Try again in a moment."
	end
	if full then
		return false, "The list is full."
	end
	apply(kind, result)
	ModerationStore.Loaded[kind] = true
	notify(kind)
	publish(kind)
	return true, nil
end

-- Reading -------------------------------------------------------------------------------------------

-- Role handed out in the game, or nil.
function ModerationStore.staffRole(userId: number): string?
	local entry = ModerationStore.Staff[userId]
	return if entry then entry.Role else nil
end

-- The active ban for a user, or nil (expired bans count as no ban).
function ModerationStore.activeBan(userId: number): BanEntry?
	local entry = ModerationStore.Bans[userId]
	if entry and isActive(entry, os.time()) then
		return entry
	end
	return nil
end

function ModerationStore.listStaff(): { any }
	local out = {}
	for userId, entry in pairs(ModerationStore.Staff) do
		local row = table.clone(entry) :: any
		row.UserId = userId
		table.insert(out, row)
	end
	table.sort(out, function(a, b)
		if a.Role ~= b.Role then
			return a.Role < b.Role
		end
		return a.Name < b.Name
	end)
	return out
end

function ModerationStore.listBans(): { any }
	local out = {}
	local now = os.time()
	for userId, entry in pairs(ModerationStore.Bans) do
		if isActive(entry, now) then
			local row = table.clone(entry) :: any
			row.UserId = userId
			table.insert(out, row)
		end
	end
	table.sort(out, function(a, b)
		return a.At > b.At
	end)
	return out
end

function ModerationStore.isGrantable(role: any): boolean
	return type(role) == "string" and grantable[role] == true
end

-- Roblox Ban API mirror ---------------------------------------------------------------------------

local function robloxBanApiEnabled(): boolean
	return CONFIG.UseRobloxBanApi and not RunService:IsStudio() and store ~= nil
end

--[[
	Also bans through Players:BanAsync so Roblox blocks the user before they
	can join any server. Optional and best-effort: our own list stays the
	source of truth, so a failure here never undoes a ban.
]]
function ModerationStore.robloxBan(userId: number, seconds: number, displayReason: string, privateReason: string): (boolean, string?)
	if not robloxBanApiEnabled() then
		return false, "off"
	end
	local ok, err = pcall(function()
		(Players :: any):BanAsync({
			UserIds = { userId },
			ApplyToUniverse = true,
			Duration = if seconds == 0 then -1 else seconds,
			DisplayReason = string.sub(displayReason, 1, 400),
			PrivateReason = string.sub(privateReason, 1, 1000),
			ExcludeAltAccounts = not CONFIG.BanAltAccounts,
		})
	end)
	return ok, if ok then nil else tostring(err)
end

function ModerationStore.robloxUnban(userId: number): (boolean, string?)
	if not robloxBanApiEnabled() then
		return false, "off"
	end
	local ok, err = pcall(function()
		(Players :: any):UnbanAsync({ UserIds = { userId }, ApplyToUniverse = true })
	end)
	return ok, if ok then nil else tostring(err)
end

return ModerationStore
