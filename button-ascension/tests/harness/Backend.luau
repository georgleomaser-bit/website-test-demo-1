--[[
	Backend.luau

	In-memory stand-ins for Roblox cloud services, shared by every world that
	uses the same Backend (so two "servers" can fight over one DataStore key):

	  * DataStores (GlobalDataStore + OrderedDataStore) with UpdateAsync
	    cancel semantics, JSON-serialisability checks and failure injection
	  * MessagingService bus
	  * Text filtering (configurable blocklist)
	  * Username registry for Players:GetNameFromUserIdAsync

	Failure injection (all errors are raised inside the calling script thread,
	exactly where Roblox would raise them):
	  backend:failNext("UpdateAsync", 2, "502: API Services rejected request")
	  backend:failNext("*", 1)                      -- any DataStore method
	  backend:setFailureRate(0.3, "message")         -- random failures (seeded)
	  backend:setUnavailable("Studio access to API services is disabled")
	  backend:failFilterNext(1)                      -- TextService:FilterStringAsync
	  backend:failPublishNext(1)                     -- MessagingService:PublishAsync
]]

local serde = require("@lune/serde")
local Types = require("./Types")

local Backend = {}
Backend.__index = Backend

local DEFAULT_ERROR = "502: API Services rejected request with error. HTTP 500 (Internal Server Error)"
local MAX_VALUE_SIZE = 4194304

function Backend.new(scheduler, options: { latency: number?, seed: number? }?)
	local opts = options or {}
	local self = setmetatable({}, Backend)
	self.scheduler = scheduler
	self.stores = {}
	self.latency = opts.latency or 0.02
	self.budget = 1000
	self.failures = {}
	self.failureRate = 0
	self.failureRateMessage = DEFAULT_ERROR
	self.unavailable = nil
	self.rng = Types.Random.new(opts.seed or 1)
	self.calls = {}
	self.callLog = {}
	self.subscribers = {}
	self.published = {}
	self.publishFailures = 0
	self.filterFailures = 0
	self.blocklist = { "badword", "darn" }
	self.userNames = {}
	return self
end

-- Failure injection --------------------------------------------------------------------------

function Backend:failNext(method: string, count: number?, message: string?)
	self.failures[method] = { count = count or 1, message = message or DEFAULT_ERROR }
end

function Backend:setFailureRate(rate: number, message: string?)
	self.failureRate = rate
	self.failureRateMessage = message or DEFAULT_ERROR
end

function Backend:setUnavailable(message: string?)
	self.unavailable = message
end

function Backend:failFilterNext(count: number?)
	self.filterFailures = count or 1
end

function Backend:failPublishNext(count: number?)
	self.publishFailures = count or 1
end

function Backend:resetFailures()
	self.failures = {}
	self.failureRate = 0
	self.unavailable = nil
	self.publishFailures = 0
	self.filterFailures = 0
end

-- Serialisation checks ------------------------------------------------------------------------

local function deepCopy(value, seen)
	if type(value) ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		error("Harness: cyclic table", 0)
	end
	seen[value] = true
	local copy = {}
	for k, v in pairs(value) do
		copy[k] = deepCopy(v, seen)
	end
	seen[value] = nil
	return copy
end
Backend.deepCopy = deepCopy

local function checkStorable(value, path: string, seen)
	local t = Types.typeof(value)
	if t == "nil" or t == "boolean" or t == "string" then
		if t == "string" and not utf8.len(value) then
			error("Cannot store invalid UTF-8 string at " .. path, 0)
		end
		return
	elseif t == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			error("Cannot store " .. tostring(value) .. " in data store (at " .. path .. "). NaN and infinite numbers are not allowed.", 0)
		end
		return
	elseif t == "table" then
		if seen[value] then
			error("Cannot store cyclic table in data store (at " .. path .. ")", 0)
		end
		seen[value] = true
		local n = #value
		local hasString, hasNumber = false, false
		for k, v in pairs(value) do
			if type(k) == "string" then
				hasString = true
			elseif type(k) == "number" then
				if k ~= math.floor(k) or k < 1 or k > n then
					error("Cannot store array with non-sequential or non-integer keys in data store (at " .. path .. ")", 0)
				end
				hasNumber = true
			else
				error("Cannot store table with " .. type(k) .. " keys in data store (at " .. path .. ")", 0)
			end
			checkStorable(v, path .. "." .. tostring(k), seen)
		end
		if hasString and hasNumber then
			error("Cannot store mixed table (array + dictionary) in data store (at " .. path .. ")", 0)
		end
		seen[value] = nil
		return
	end
	error("Cannot store " .. t .. " in data store (at " .. path .. "). Only JSON-compatible values are allowed.", 0)
end
Backend.checkStorable = function(value)
	checkStorable(value, "value", {})
end

-- Request plumbing -------------------------------------------------------------------------------

function Backend:_request(method: string, storeId: string, key: string?)
	self.calls[method] = (self.calls[method] or 0) + 1
	table.insert(self.callLog, { method = method, store = storeId, key = key, time = self.scheduler.now })
	if #self.callLog > 5000 then
		table.remove(self.callLog, 1)
	end
	if self.unavailable then
		error(self.unavailable, 0)
	end
	local injected = self.failures[method] or self.failures["*"]
	if injected and injected.count > 0 then
		injected.count -= 1
		error(injected.message, 0)
	end
	if self.failureRate > 0 and self.rng:NextNumber() < self.failureRate then
		error(self.failureRateMessage, 0)
	end
	if self.latency > 0 and coroutine.isyieldable() then
		self.scheduler:wait(self.latency)
	end
end

function Backend:_bucket(kind: string, name: string, scope: string?)
	local id = kind .. ":" .. name .. ":" .. (scope or "global")
	local bucket = self.stores[id]
	if not bucket then
		bucket = { id = id, kind = kind, name = name, data = {} }
		self.stores[id] = bucket
	end
	return bucket
end

local function validateKey(key)
	if type(key) == "number" then
		key = tostring(key)
	end
	if type(key) ~= "string" or #key == 0 then
		error("Argument 1 missing or nil", 0)
	end
	if #key > 50 then
		error("Key name exceeds the 50 character limit.", 0)
	end
	return key
end

local function keyInfo(entry)
	local info = {
		Version = tostring(entry and entry.version or 0),
		CreatedTime = entry and entry.created or 0,
		UpdatedTime = entry and entry.updated or 0,
		GetUserIds = function()
			return entry and entry.userIds or {}
		end,
		GetMetadata = function()
			return entry and entry.metadata or {}
		end,
	}
	Types.register(info, "Instance")
	return info
end

-- GlobalDataStore ------------------------------------------------------------------------------------

local StoreMethods = {}
StoreMethods.__index = StoreMethods

function StoreMethods:GetAsync(key)
	key = validateKey(key)
	self._backend:_request("GetAsync", self._bucket.id, key)
	local entry = self._bucket.data[key]
	if not entry then
		return nil, nil
	end
	return deepCopy(entry.value), keyInfo(entry)
end

local function write(self, key: string, value, userIds)
	checkStorable(value, "value", {})
	local encoded = serde.encode("json", value)
	if #encoded > MAX_VALUE_SIZE then
		error("Value exceeds the 4MB data store limit.", 0)
	end
	local now = math.floor(self._backend.scheduler:unixTime() * 1000)
	local entry = self._bucket.data[key]
	if not entry then
		entry = { version = 0, created = now }
		self._bucket.data[key] = entry
	end
	entry.value = deepCopy(value)
	entry.version += 1
	entry.updated = now
	if userIds then
		entry.userIds = table.clone(userIds)
	end
	return entry
end

function StoreMethods:SetAsync(key, value, userIds, _options)
	key = validateKey(key)
	self._backend:_request("SetAsync", self._bucket.id, key)
	if self._ordered then
		if type(value) ~= "number" or value ~= math.floor(value) then
			error("OrderedDataStore values must be integers", 0)
		end
	end
	local entry = write(self, key, value, userIds)
	return tostring(entry.version)
end

function StoreMethods:UpdateAsync(key, transform)
	key = validateKey(key)
	if type(transform) ~= "function" then
		error("Argument 2 missing or nil", 0)
	end
	self._backend:_request("UpdateAsync", self._bucket.id, key)
	local entry = self._bucket.data[key]
	local current = entry and deepCopy(entry.value)
	-- Roblox forbids yielding inside the transform; run it in a coroutine to detect that.
	local thread = coroutine.create(transform)
	local results = table.pack(coroutine.resume(thread, current, keyInfo(entry)))
	if not results[1] then
		error(results[2], 0)
	end
	if coroutine.status(thread) ~= "dead" then
		error("Harness: UpdateAsync transform function yielded, which Roblox does not allow", 0)
	end
	local newValue = results[2]
	if newValue == nil then
		return nil, nil -- update cancelled
	end
	if self._ordered and (type(newValue) ~= "number" or newValue ~= math.floor(newValue)) then
		error("OrderedDataStore values must be integers", 0)
	end
	local written = write(self, key, newValue, results[3])
	return deepCopy(written.value), keyInfo(written)
end

function StoreMethods:IncrementAsync(key, delta, userIds)
	key = validateKey(key)
	self._backend:_request("IncrementAsync", self._bucket.id, key)
	local entry = self._bucket.data[key]
	local current = entry and entry.value or 0
	if type(current) ~= "number" then
		error("IncrementAsync can only be used on numbers", 0)
	end
	local nextValue = current + math.floor(delta or 1)
	write(self, key, nextValue, userIds)
	return nextValue
end

function StoreMethods:RemoveAsync(key)
	key = validateKey(key)
	self._backend:_request("RemoveAsync", self._bucket.id, key)
	local entry = self._bucket.data[key]
	self._bucket.data[key] = nil
	if entry then
		return deepCopy(entry.value), keyInfo(entry)
	end
	return nil, nil
end

-- OrderedDataStore pages
function StoreMethods:GetSortedAsync(ascending: boolean, pageSize: number, minValue: number?, maxValue: number?)
	if not self._ordered then
		error("GetSortedAsync is only available on OrderedDataStore", 0)
	end
	self._backend:_request("GetSortedAsync", self._bucket.id, nil)
	pageSize = math.clamp(math.floor(pageSize or 50), 1, 100)
	local entries = {}
	for key, entry in pairs(self._bucket.data) do
		local v = entry.value
		if (minValue == nil or v >= minValue) and (maxValue == nil or v <= maxValue) then
			table.insert(entries, { key = key, value = v })
		end
	end
	table.sort(entries, function(a, b)
		if a.value == b.value then
			return a.key < b.key
		end
		if ascending then
			return a.value < b.value
		end
		return a.value > b.value
	end)
	local backend = self._backend
	local bucketId = self._bucket.id
	local pages = { _offset = 0, IsFinished = false }
	function pages:GetCurrentPage()
		local page = {}
		for i = self._offset + 1, math.min(self._offset + pageSize, #entries) do
			table.insert(page, { key = entries[i].key, value = entries[i].value })
		end
		return page
	end
	function pages:AdvanceToNextPageAsync()
		backend:_request("AdvanceToNextPageAsync", bucketId, nil)
		self._offset += pageSize
		self.IsFinished = self._offset + pageSize >= #entries
	end
	pages.IsFinished = pageSize >= #entries
	Types.register(pages, "Instance")
	return pages
end

function Backend:getStore(kind: string, name: string, scope: string?)
	if type(name) ~= "string" or #name == 0 then
		error("Argument 1 missing or nil", 0)
	end
	local bucket = self:_bucket(kind, name, scope)
	local store = setmetatable({
		_backend = self,
		_bucket = bucket,
		_ordered = kind == "ordered",
		Name = name,
		ClassName = if kind == "ordered" then "OrderedDataStore" else "DataStore",
	}, StoreMethods)
	Types.register(store, "Instance")
	return store
end

-- Test helpers: read / write raw values without going through the request pipeline.
function Backend:peek(storeName: string, key: string, scope: string?, kind: string?)
	local bucket = self:_bucket(kind or "global", storeName, scope)
	local entry = bucket.data[key]
	return entry and deepCopy(entry.value)
end

function Backend:poke(storeName: string, key: string, value: any, scope: string?, kind: string?)
	local bucket = self:_bucket(kind or "global", storeName, scope)
	if value == nil then
		bucket.data[key] = nil
		return
	end
	local entry = bucket.data[key] or { version = 0, created = 0 }
	entry.value = deepCopy(value)
	entry.version += 1
	entry.updated = math.floor(self.scheduler:unixTime() * 1000)
	bucket.data[key] = entry
end

function Backend:keys(storeName: string, scope: string?, kind: string?): { string }
	local bucket = self:_bucket(kind or "global", storeName, scope)
	local out = {}
	for key in pairs(bucket.data) do
		table.insert(out, key)
	end
	table.sort(out)
	return out
end

-- MessagingService -------------------------------------------------------------------------------------

function Backend:subscribe(world, topic: string, callback)
	if type(topic) ~= "string" or #topic == 0 or #topic > 80 then
		error("MessagingService: invalid topic", 0)
	end
	self:_messagingRequest("SubscribeAsync")
	local list = self.subscribers[topic]
	if not list then
		list = {}
		self.subscribers[topic] = list
	end
	local entry = { world = world, callback = callback, connected = true }
	table.insert(list, entry)
	local connection = {
		Connected = true,
	}
	function connection.Disconnect()
		connection.Connected = false
		entry.connected = false
	end
	Types.register(connection, "RBXScriptConnection")
	return connection
end

function Backend:_messagingRequest(method: string)
	self.calls[method] = (self.calls[method] or 0) + 1
	if self.unavailable then
		error(self.unavailable, 0)
	end
	if method == "PublishAsync" and self.publishFailures > 0 then
		self.publishFailures -= 1
		error("MessagingService: PublishAsync failed (injected)", 0)
	end
end

function Backend:publish(topic: string, message: any)
	if type(topic) ~= "string" or #topic == 0 or #topic > 80 then
		error("MessagingService: invalid topic", 0)
	end
	self:_messagingRequest("PublishAsync")
	checkStorable(message, "message", {})
	local encoded = serde.encode("json", message)
	if #encoded > 1024 then
		error("MessagingService: message exceeds 1kB", 0)
	end
	table.insert(self.published, { topic = topic, message = deepCopy(message), time = self.scheduler.now })
	local sent = self.scheduler:unixTime()
	for _, entry in ipairs(self.subscribers[topic] or {}) do
		if entry.connected and not entry.world.closed then
			local payload = { Data = deepCopy(message), Sent = sent }
			self.scheduler:after(0.05, function()
				if entry.connected then
					entry.callback(payload)
				end
			end, entry.world)
		end
	end
	if self.latency > 0 and coroutine.isyieldable() then
		self.scheduler:wait(self.latency)
	end
end

-- Text filtering ------------------------------------------------------------------------------------------

function Backend:filter(text: string): string
	self.calls.FilterStringAsync = (self.calls.FilterStringAsync or 0) + 1
	if self.filterFailures > 0 then
		self.filterFailures -= 1
		error("TextService: FilterStringAsync failed (injected)", 0)
	end
	if self.unavailable then
		error(self.unavailable, 0)
	end
	local out = text
	for _, word in ipairs(self.blocklist) do
		local lower = string.lower(out)
		local start = 1
		while true do
			local s, e = string.find(lower, string.lower(word), start, true)
			if not s then
				break
			end
			out = string.sub(out, 1, s - 1) .. string.rep("#", e - s + 1) .. string.sub(out, e + 1)
			lower = string.lower(out)
			start = e + 1
		end
	end
	if self.latency > 0 and coroutine.isyieldable() then
		self.scheduler:wait(self.latency)
	end
	return out
end

return Backend
