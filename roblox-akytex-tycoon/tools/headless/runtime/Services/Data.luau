--!nocheck
-- =====================================================================
--  Headless-Harness · DataStoreService, MemoryStoreService, MessagingService
--
--  Werteprüfung wie Roblox (Svc.storable): nur nil/boolean/number/string/buffer/Tabellen; Tabellen müssen reine
--  Arrays (1..n ohne Lücken) oder Dictionaries mit String-Schlüsseln sein; Strings gültiges UTF-8; keine Zyklen;
--  NaN/±inf werden abgelehnt (Spezifikation: nicht JSON-fähig). Fehlertexte nach Roblox ("104: Cannot store
--  Vector3 in data store. Data stores can only accept valid UTF-8 characters.", "102: Key name exceeds the 50
--  character limit.", "105: Serialized value converted byte size exceeds max size 4194304 bytes."), der
--  Harness hängt den Pfad des fehlerhaften Werts in Klammern an.
--  DataStore: In-Memory (für alle Server gemeinsam), Latenz 0,1 s, Budgets je Anfrage-Typ (60 + 10·Spieler pro
--  Minute, Start 100) und 6-s-Schreibsperre je Schlüssel -> Roblox-Warnung "DataStore request was added to queue…"
--  + Verzögerung. UpdateAsync-Transform darf nicht yielden; nil bricht ab. Werte werden kopiert (wie JSON).
--  MemoryStore: SortedMap/Queue/HashMap mit Ablaufzeiten (simuliert), Grenzen (Schlüssel 128, Wert 32 KB,
--  Ablauf 1..3 888 000 s). MessagingService: PublishAsync (Thema ≤ 80, Nachricht ≤ 1 KB JSON), SubscribeAsync
--  (Rückmeldung an alle Abonnenten des Universums, auch den Sender, nach 0,1 s, {Data, Sent}).
--  Harness: R.Svc.Data.stores (Inhalt), R.Svc.Data.dump(), R.Svc.Data.studioAccess (false -> Fehler 502 wie Studio
--  ohne API-Zugriff).
-- =====================================================================
return function(R, Svc)
	local Util = R.Util
	local Sched = R.Sched
	local Report = R.Report
	local Inst = R.Inst
	local DT = R.DT
	local Enum = R.Enum
	local raise = Util.raise
	local typeof = Util.typeof
	local getmt = getmetatable
	local fmt = string.format

	local D = {}
	Svc.Data = D
	D.stores = {} -- storeKey -> { name, scope, ordered, data = { key -> entry } }
	D.studioAccess = true

	-- =================================================================================================
	--  Werteprüfung + Kopie (JSON-Semantik)
	-- =================================================================================================
	local function classify(t)
		local n, count, hasStr, hasNum, maxN, bad = 0, 0, false, false, 0, nil
		for k in t do
			count += 1
			local kt = type(k)
			if kt == "number" then
				hasNum = true
				if k > maxN then
					maxN = k
				end
				if k ~= math.floor(k) or k < 1 then
					bad = "Array"
				end
			elseif kt == "string" then
				hasStr = true
			else
				bad = "Dictionary"
			end
		end
		if bad then
			return bad
		end
		if hasNum and hasStr then
			return "Mixed"
		end
		if hasNum then
			if maxN ~= count then
				return "Sparse"
			end
			return "array"
		end
		return "dict"
	end

	--- Prüft v auf Speicherbarkeit; Rückgabe Kopie, Bytes. errPrefix = "104: Cannot store %s in data store…"
	function D.storable(v, opts)
		opts = opts or {}
		local storeWord = opts.word or "data store"
		local seen = {}
		local bytes = 0
		local function fail(kind, path)
			local msg
			if kind == "utf8" then
				msg = fmt("104: Cannot store string in %s. Data stores can only accept valid UTF-8 characters.", storeWord)
			elseif kind == "cyclic" then
				msg = "tables cannot be cyclic"
			else
				msg = fmt("104: Cannot store %s in %s. Data stores can only accept valid UTF-8 characters.", kind, storeWord)
			end
			if path ~= "" then
				msg ..= " (Harness: Wert bei " .. path .. ")"
			end
			raise(msg)
		end
		local function copy(x, path, container)
			local t = type(x)
			if t == "nil" then
				bytes += 4
				return nil
			elseif t == "boolean" then
				bytes += 5
				return x
			elseif t == "number" then
				if x ~= x or x == math.huge or x == -math.huge then
					fail(x ~= x and "NaN" or "inf", path)
				end
				bytes += #tostring(x)
				return x
			elseif t == "string" then
				if utf8.len(x) == nil then
					fail("utf8", path)
				end
				bytes += #x + 2
				return x
			elseif t == "buffer" then
				bytes += math.ceil(buffer.len(x) * 4 / 3) + 16
				local b = buffer.create(buffer.len(x))
				buffer.copy(b, 0, x)
				return b
			elseif t == "table" then
				if seen[x] then
					fail("cyclic", path)
				end
				if getmetatable(x) ~= nil and opts.rejectMeta then
					fail("Dictionary", path)
				end
				seen[x] = true
				local kind = classify(x)
				local out = {}
				if kind == "array" then
					bytes += 2
					for i = 1, #x do
						out[i] = copy(x[i], path .. "[" .. i .. "]", "Array")
						bytes += 1
					end
				elseif kind == "dict" then
					bytes += 2
					for k, val in x do
						bytes += #k + 4
						out[k] = copy(val, path .. "." .. k, "Dictionary")
					end
				elseif kind == "Mixed" or kind == "Sparse" then
					fail("Array", path)
				else
					fail(kind, path)
				end
				seen[x] = nil
				return out
			else
				fail(typeof(x), path)
			end
		end
		local c = copy(v, "", nil)
		return c, bytes
	end

	local function deepCopy(x)
		if type(x) == "table" then
			local o = {}
			for k, v in x do
				o[k] = deepCopy(v)
			end
			return o
		elseif type(x) == "buffer" then
			local b = buffer.create(buffer.len(x))
			buffer.copy(b, 0, x)
			return b
		end
		return x
	end
	D.deepCopy = deepCopy

	-- =================================================================================================
	--  Budgets
	-- =================================================================================================
	local budgetTypes = {
		GetAsync = "GetAsync",
		SetIncrementAsync = "SetIncrementAsync",
		UpdateAsync = "UpdateAsync",
		GetSortedAsync = "GetSortedAsync",
		SetIncrementSortedAsync = "SetIncrementSortedAsync",
		OnUpdate = "OnUpdate",
		ListAsync = "ListAsync",
		GetVersionAsync = "GetVersionAsync",
		RemoveVersionAsync = "RemoveVersionAsync",
	}
	local budgets = {}
	local lastRefill = 0
	local function numPlayers()
		local n = 0
		local g = Svc.games[1]
		if g then
			local ps = Inst.findServiceRaw(g.game, "Players")
			if ps then
				for _, c in Inst.children(ps) do
					if getmt(c).cls.isA.Player then
						n += 1
					end
				end
			end
		end
		return n
	end
	local function refill()
		local now = Sched.now
		local dt = now - lastRefill
		lastRefill = now
		local perSec = (60 + 10 * numPlayers()) / 60
		for k in budgetTypes do
			local b = budgets[k]
			if b == nil then
				b = 100
			end
			local rate = perSec
			if k == "GetSortedAsync" or k == "SetIncrementSortedAsync" then
				rate = (5 + 2 * numPlayers()) / 60
			end
			budgets[k] = math.min(b + dt * rate, 300)
		end
	end
	local function budgetOf(kind)
		refill()
		return math.floor(budgets[kind] or 100)
	end
	D.budgetOf = budgetOf

	local keyLastWrite = {}
	local warnedQueue = {}
	local function consume(kind, storeKey, key, isWrite)
		refill()
		local waited = false
		while (budgets[kind] or 100) < 1 do
			if not warnedQueue[kind .. key] then
				warnedQueue[kind .. key] = true
				local msg = "DataStore request was added to queue. If request queue fills, further requests will be dropped. Try sending fewer requests.Key = "
					.. key
				Report.print(Sched.ctx(), "warn", msg)
				Report.warn(msg, Sched.ctx(), debug.traceback("", 3), "dataStoreQueue")
			end
			Sched.wait(1)
			refill()
			waited = true
		end
		budgets[kind] -= 1
		if isWrite then
			local wk = storeKey .. "\0" .. key
			local last = keyLastWrite[wk]
			if last and Sched.now - last < 6 then
				local msg = "DataStore request was added to queue. If request queue fills, further requests will be dropped. Try sending fewer requests.Key = "
					.. key
				Report.print(Sched.ctx(), "warn", msg)
				Report.warn(msg, Sched.ctx(), debug.traceback("", 3), "dataStoreQueue")
				Sched.wait(6 - (Sched.now - last))
			end
			keyLastWrite[wk] = Sched.now
		end
		return waited
	end

	-- =================================================================================================
	--  DataStore-Objekte
	-- =================================================================================================
	local function checkAccess(self)
		local ctx = Svc.ctxOf(self)
		if ctx.isClient then
			raise("DataStore can't be accessed from client")
		end
		if R.config.studio and not D.studioAccess then
			raise("502: API Services rejected request with error. HTTP 403 (Forbidden)")
		end
	end
	local function checkKey(key, n, fname)
		if key == nil then
			raise("Argument " .. n .. " missing or nil")
		end
		key = Util.checkString(key, n, fname)
		if #key == 0 then
			raise("101: Key name can't be empty.")
		end
		if #key > 50 then
			raise("102: Key name exceeds the 50 character limit.")
		end
		return key
	end
	local function storeOf(self)
		local M = getmt(self)
		return M.ext.store
	end
	local function newKeyInfo(entry)
		local ki = Inst.create("DataStoreKeyInfo", { Name = "DataStoreKeyInfo" })
		local M = getmt(ki)
		M.props.CreatedTime = entry and entry.created or 0
		M.props.UpdatedTime = entry and entry.updated or 0
		M.props.Version = entry and entry.version or ""
		M.ext = { userIds = entry and deepCopy(entry.userIds) or {}, metadata = entry and deepCopy(entry.metadata) or {} }
		return ki
	end
	Inst.define("DataStoreKeyInfo", {
		methods = {
			GetUserIds = function(self)
				local M = Inst.checkSelf(self, "GetUserIds")
				return deepCopy(M.ext.userIds)
			end,
			GetMetadata = function(self)
				local M = Inst.checkSelf(self, "GetMetadata")
				return deepCopy(M.ext.metadata)
			end,
		},
	})
	local function validUserIds(ids, n, fname)
		if ids == nil then
			return {}
		end
		if type(ids) ~= "table" then
			Util.badArg(n, fname, "table", ids)
		end
		for _, id in ids do
			if type(id) ~= "number" then
				raise("Attempted to set userIds to a non-number value")
			end
		end
		return table.clone(ids)
	end
	local function writeEntry(store, key, value, userIds, metadata)
		local now = Sched.unixMillis()
		local e = store.data[key]
		if e == nil then
			e = { created = now, versionN = 0 }
			store.data[key] = e
		end
		e.versionN += 1
		e.version = fmt("%016X", e.versionN)
		e.updated = now
		e.value = value
		e.userIds = userIds or {}
		e.metadata = metadata or {}
		return e
	end
	local MAX_VALUE = 4194304

	local function prepValue(value, store)
		local copy, bytes = D.storable(value)
		if bytes > MAX_VALUE then
			raise(fmt("105: Serialized value converted byte size exceeds max size %d bytes.", MAX_VALUE))
		end
		if store.ordered then
			if type(copy) ~= "number" or copy ~= math.floor(copy) then
				raise("105: Ordered data stores can only store integers (got " .. typeof(value) .. ")")
			end
		end
		return copy
	end

	local GDS = {}
	function GDS.GetAsync(self, key, options)
		Inst.checkSelf(self, "GetAsync")
		checkAccess(self)
		key = checkKey(key, 1, "GetAsync")
		local store = storeOf(self)
		consume("GetAsync", store.key, key, false)
		Svc.latency(0.1)
		local e = store.data[key]
		if e == nil or e.value == nil then
			return nil, nil
		end
		return deepCopy(e.value), (not store.ordered) and newKeyInfo(e) or nil
	end
	function GDS.SetAsync(self, key, value, userIds, options)
		Inst.checkSelf(self, "SetAsync")
		checkAccess(self)
		key = checkKey(key, 1, "SetAsync")
		if value == nil then
			raise("Argument 2 missing or nil")
		end
		local store = storeOf(self)
		local copy = prepValue(value, store)
		local ids = validUserIds(userIds, 3, "SetAsync")
		local meta = {}
		if options ~= nil then
			if typeof(options) ~= "DataStoreSetOptions" and not (Inst.meta(options) and Inst.meta(options).cls.isA.DataStoreSetOptions) then
				Util.badArg(4, "SetAsync", "DataStoreSetOptions", options)
			end
			local OM = Inst.meta(options)
			meta = OM and OM.ext and OM.ext.metadata or {}
		end
		consume("SetIncrementAsync", store.key, key, true)
		Svc.latency(0.1)
		local e = writeEntry(store, key, copy, ids, meta)
		return e.version
	end
	function GDS.UpdateAsync(self, key, transform)
		Inst.checkSelf(self, "UpdateAsync")
		checkAccess(self)
		key = checkKey(key, 1, "UpdateAsync")
		if type(transform) ~= "function" then
			Util.badArg(2, "UpdateAsync", "function", transform)
		end
		local store = storeOf(self)
		consume("UpdateAsync", store.key, key, true)
		Svc.latency(0.1)
		local e = store.data[key]
		local cur = e and e.value ~= nil and deepCopy(e.value) or nil
		local ki = (not store.ordered) and (e and e.value ~= nil and newKeyInfo(e) or nil) or nil
		local res = table.pack(Sched.callNoYield(transform, cur, ki))
		if not res[1] then
			local msg = res[2]
			if type(msg) == "string" and string.find(msg, "yield across", 1, true) then
				raise("UpdateAsync: the transform function cannot yield (attempt to yield across metamethod/C-call boundary)")
			end
			error(msg, 0)
		end
		local newValue, newIds, newMeta = res[2], res[3], res[4]
		if newValue == nil then
			return nil, nil
		end
		local copy = prepValue(newValue, store)
		local ids = validUserIds(newIds, 2, "UpdateAsync")
		local meta = newMeta
		if meta ~= nil and type(meta) ~= "table" then
			raise("UpdateAsync: metadata must be a table")
		end
		local ne = writeEntry(store, key, copy, ids, meta and deepCopy(meta) or {})
		return deepCopy(copy), (not store.ordered) and newKeyInfo(ne) or nil
	end
	function GDS.IncrementAsync(self, key, delta, userIds, options)
		Inst.checkSelf(self, "IncrementAsync")
		checkAccess(self)
		key = checkKey(key, 1, "IncrementAsync")
		delta = delta == nil and 1 or Util.checkNumber(delta, 2, "IncrementAsync")
		if delta ~= math.floor(delta) then
			raise("IncrementAsync: delta must be an integer")
		end
		local store = storeOf(self)
		consume("SetIncrementAsync", store.key, key, true)
		Svc.latency(0.1)
		local e = store.data[key]
		local cur = e and e.value or 0
		if type(cur) ~= "number" or cur ~= math.floor(cur) then
			raise("IncrementAsync: the stored value is not an integer")
		end
		local ne = writeEntry(store, key, cur + delta, validUserIds(userIds, 3, "IncrementAsync"), e and e.metadata or {})
		return ne.value, (not store.ordered) and newKeyInfo(ne) or nil
	end
	function GDS.RemoveAsync(self, key)
		Inst.checkSelf(self, "RemoveAsync")
		checkAccess(self)
		key = checkKey(key, 1, "RemoveAsync")
		local store = storeOf(self)
		consume("SetIncrementAsync", store.key, key, true)
		Svc.latency(0.1)
		local e = store.data[key]
		if e == nil or e.value == nil then
			return nil, nil
		end
		local old = e.value
		local ki = (not store.ordered) and newKeyInfo(e) or nil
		store.data[key] = nil
		return old, ki
	end
	function GDS.OnUpdate(self, key, callback)
		Inst.checkSelf(self, "OnUpdate")
		checkAccess(self)
		checkKey(key, 1, "OnUpdate")
		if type(callback) ~= "function" then
			Util.badArg(2, "OnUpdate", "function", callback)
		end
		local sig = R.Signal.new("OnUpdate")
		return sig:Connect(callback)
	end
	function GDS.BatchGetAsync(self, keys, options)
		Inst.checkSelf(self, "BatchGetAsync")
		checkAccess(self)
		if type(keys) ~= "table" then
			Util.badArg(1, "BatchGetAsync", "table", keys)
		end
		local out = {}
		for _, k in keys do
			local v = GDS.GetAsync(self, k)
			out[k] = v
		end
		return out
	end
	Inst.define("GlobalDataStore", { methods = GDS })
	-- OrderedDataStore deklariert Get/Set/Remove/Update neu (gleiches Verhalten, Werte = Ganzzahlen)
	Inst.define("OrderedDataStore", {
		methods = {
			GetAsync = GDS.GetAsync,
			SetAsync = GDS.SetAsync,
			RemoveAsync = GDS.RemoveAsync,
			UpdateAsync = GDS.UpdateAsync,
		},
	})

	local DS = {}
	function DS.GetVersionAsync(self, key, version)
		Inst.checkSelf(self, "GetVersionAsync")
		checkAccess(self)
		key = checkKey(key, 1, "GetVersionAsync")
		version = Util.checkString(version, 2, "GetVersionAsync")
		local store = storeOf(self)
		consume("GetVersionAsync", store.key, key, false)
		Svc.latency(0.1)
		local e = store.data[key]
		if e and e.version == version then
			return deepCopy(e.value), newKeyInfo(e)
		end
		return nil, nil
	end
	function DS.ListVersionsAsync(self, key, sortDirection, minDate, maxDate, pageSize)
		Inst.checkSelf(self, "ListVersionsAsync")
		checkAccess(self)
		key = checkKey(key, 1, "ListVersionsAsync")
		local store = storeOf(self)
		consume("ListAsync", store.key, key, false)
		Svc.latency(0.1)
		local e = store.data[key]
		local list = {}
		if e then
			list[1] = { Version = e.version, CreatedTime = e.created, IsDeleted = false }
		end
		return Svc.newPages("DataStoreVersionPages", { list })
	end
	function DS.ListKeysAsync(self, prefix, pageSize, cursor, excludeDeleted)
		Inst.checkSelf(self, "ListKeysAsync")
		checkAccess(self)
		local store = storeOf(self)
		consume("ListAsync", store.key, "", false)
		Svc.latency(0.1)
		prefix = prefix and Util.checkString(prefix, 1, "ListKeysAsync") or ""
		pageSize = pageSize and Util.checkNumber(pageSize, 2, "ListKeysAsync") or 50
		local keys = {}
		for k in store.data do
			if string.sub(k, 1, #prefix) == prefix then
				keys[#keys + 1] = k
			end
		end
		table.sort(keys)
		local pages, page = {}, {}
		for _, k in keys do
			local ki = Inst.create("DataStoreKey", { Name = "DataStoreKey" })
			getmt(ki).props.KeyName = k
			page[#page + 1] = ki
			if #page >= pageSize then
				pages[#pages + 1] = page
				page = {}
			end
		end
		pages[#pages + 1] = page
		return Svc.newPages("DataStoreKeyPages", pages)
	end
	function DS.RemoveVersionAsync(self, key, version)
		Inst.checkSelf(self, "RemoveVersionAsync")
		checkAccess(self)
		checkKey(key, 1, "RemoveVersionAsync")
		Svc.latency(0.1)
	end
	function DS.GetVersionAtTimeAsync(self, key, timestamp)
		Inst.checkSelf(self, "GetVersionAtTimeAsync")
		checkAccess(self)
		key = checkKey(key, 1, "GetVersionAtTimeAsync")
		Util.checkNumber(timestamp, 2, "GetVersionAtTimeAsync")
		Svc.latency(0.1)
		local e = storeOf(self).data[key]
		if e then
			return deepCopy(e.value), newKeyInfo(e)
		end
		return nil, nil
	end
	Inst.define("DataStore", { methods = DS })

	local ODS = {}
	function ODS.GetSortedAsync(self, ascending, pageSize, minValue, maxValue)
		Inst.checkSelf(self, "GetSortedAsync")
		checkAccess(self)
		ascending = Util.checkBool(ascending, 1, "GetSortedAsync")
		pageSize = Util.checkNumber(pageSize, 2, "GetSortedAsync")
		if pageSize < 1 or pageSize > 100 or pageSize ~= math.floor(pageSize) then
			raise("GetSortedAsync: pageSize must be an integer between 1 and 100")
		end
		if minValue ~= nil then
			minValue = Util.checkNumber(minValue, 3, "GetSortedAsync")
		end
		if maxValue ~= nil then
			maxValue = Util.checkNumber(maxValue, 4, "GetSortedAsync")
		end
		local store = storeOf(self)
		consume("GetSortedAsync", store.key, "", false)
		Svc.latency(0.1)
		local list = {}
		for k, e in store.data do
			local v = e.value
			if type(v) == "number" and (minValue == nil or v >= minValue) and (maxValue == nil or v <= maxValue) then
				list[#list + 1] = { key = k, value = v }
			end
		end
		table.sort(list, function(a, b)
			if a.value ~= b.value then
				if ascending then
					return a.value < b.value
				end
				return a.value > b.value
			end
			return a.key < b.key
		end)
		local pages, page = {}, {}
		for _, it in list do
			page[#page + 1] = it
			if #page >= pageSize then
				pages[#pages + 1] = page
				page = {}
			end
		end
		if #page > 0 or #pages == 0 then
			pages[#pages + 1] = page
		end
		return Svc.newPages("DataStorePages", pages)
	end
	Inst.define("OrderedDataStore", { methods = ODS })

	-- DataStoreSetOptions / DataStoreOptions (über Instance.new erzeugbar)
	Inst.define("DataStoreSetOptions", {
		methods = {
			SetMetadata = function(self, meta)
				local M = Inst.checkSelf(self, "SetMetadata")
				if type(meta) ~= "table" then
					Util.badArg(1, "SetMetadata", "table", meta)
				end
				M.ext = M.ext or {}
				M.ext.metadata = deepCopy(meta)
			end,
			GetMetadata = function(self)
				local M = Inst.checkSelf(self, "GetMetadata")
				return deepCopy(M.ext and M.ext.metadata or {})
			end,
		},
	})

	local function getStore(svc, name, scope, ordered, global)
		local key = (ordered and "O:" or "D:") .. name .. "\0" .. (scope or "global")
		local st = D.stores[key]
		if st == nil then
			st = { key = key, name = name, scope = scope or "global", ordered = ordered, data = {} }
			D.stores[key] = st
		end
		local M = getmt(svc)
		M.ext = M.ext or {}
		M.ext.objects = M.ext.objects or {}
		local obj = M.ext.objects[key]
		if obj == nil then
			local cls = ordered and "OrderedDataStore" or (global and "GlobalDataStore" or "DataStore")
			obj = Inst.create(cls, { Name = name })
			getmt(obj).ext = { store = st }
			M.ext.objects[key] = obj
		end
		return obj
	end
	local function checkName(name, n, fname, what)
		name = Util.checkString(name, n, fname)
		if #name == 0 then
			raise(fmt("%s can't be empty", what))
		end
		if #name > 50 then
			raise(fmt("%s exceeds the 50 character limit", what))
		end
		return name
	end
	local DSS = {}
	function DSS.GetDataStore(self, name, scope, options)
		Inst.checkSelf(self, "GetDataStore")
		checkAccess(self)
		name = checkName(name, 1, "GetDataStore", "DataStore name")
		if scope ~= nil then
			scope = checkName(scope, 2, "GetDataStore", "DataStore scope")
		end
		return getStore(self, name, scope, false, false)
	end
	function DSS.GetGlobalDataStore(self)
		Inst.checkSelf(self, "GetGlobalDataStore")
		checkAccess(self)
		return getStore(self, "global", "global", false, true)
	end
	function DSS.GetOrderedDataStore(self, name, scope)
		Inst.checkSelf(self, "GetOrderedDataStore")
		checkAccess(self)
		name = checkName(name, 1, "GetOrderedDataStore", "DataStore name")
		if scope ~= nil then
			scope = checkName(scope, 2, "GetOrderedDataStore", "DataStore scope")
		end
		return getStore(self, name, scope, true, false)
	end
	function DSS.GetRequestBudgetForRequestType(self, requestType)
		Inst.checkSelf(self, "GetRequestBudgetForRequestType")
		local it = Enum.coerce(requestType, "DataStoreRequestType")
		if it == nil then
			Util.badArg(1, "GetRequestBudgetForRequestType", "Enum.DataStoreRequestType", requestType)
		end
		local map = {
			GetAsync = "GetAsync",
			SetIncrementAsync = "SetIncrementAsync",
			UpdateAsync = "UpdateAsync",
			GetSortedAsync = "GetSortedAsync",
			SetIncrementSortedAsync = "SetIncrementSortedAsync",
			OnUpdate = "OnUpdate",
			ListAsync = "ListAsync",
			GetVersionAsync = "GetVersionAsync",
			RemoveVersionAsync = "RemoveVersionAsync",
		}
		return budgetOf(map[it.Name] or "GetAsync")
	end
	function DSS.ListDataStoresAsync(self, prefix, pageSize)
		Inst.checkSelf(self, "ListDataStoresAsync")
		checkAccess(self)
		Svc.latency(0.1)
		local list = {}
		for _, st in D.stores do
			if not st.ordered then
				list[#list + 1] = { DataStoreName = st.name }
			end
		end
		return Svc.newPages("DataStoreListingPages", { list })
	end
	Inst.registerService("DataStoreService", { methods = DSS })

	function D.dump()
		local out = {}
		for key, st in D.stores do
			local entries = {}
			for k, e in st.data do
				entries[k] = { value = e.value, version = e.version, userIds = e.userIds }
			end
			out[key] = { name = st.name, scope = st.scope, ordered = st.ordered, entries = entries }
		end
		return out
	end

	-- =================================================================================================
	--  MemoryStoreService
	-- =================================================================================================
	local MAX_MS_VALUE = 32 * 1024
	local function msCheckKey(key, n, fname)
		key = Util.checkString(key, n, fname)
		if #key == 0 then
			raise(fmt("%s: key can't be empty", fname))
		end
		if #key > 128 then
			raise(fmt("%s: key name exceeds the 128 character limit", fname))
		end
		return key
	end
	local function msCheckExpiration(e, n, fname)
		e = Util.checkNumber(e, n, fname)
		if e <= 0 or e > 3888000 then
			raise(fmt("%s: expiration must be between 1 and 3888000 seconds", fname))
		end
		return e
	end
	local function msValue(v, fname)
		if v == nil then
			raise(fmt("%s: value can't be nil", fname))
		end
		local copy, bytes = D.storable(v, { word = "memory store" })
		if bytes > MAX_MS_VALUE then
			raise(fmt("%s: value size exceeds the %d byte limit", fname, MAX_MS_VALUE))
		end
		return copy
	end
	local function msLive(e)
		return e ~= nil and e.expires > Sched.now
	end
	local function msAccess(self)
		local ctx = Svc.ctxOf(self)
		if ctx.isClient then
			raise("MemoryStoreService can't be accessed from client")
		end
	end
	local msStructs = {}
	local function msStruct(kind, name)
		local key = kind .. "\0" .. name
		local s = msStructs[key]
		if s == nil then
			s = { kind = kind, name = name, data = {}, queue = {}, seq = 0, invisible = {} }
			msStructs[key] = s
		end
		return s
	end
	D.memory = msStructs
	local function msObj(svc, cls, kind, name, extra)
		local M = getmt(svc)
		M.ext = M.ext or {}
		M.ext.ms = M.ext.ms or {}
		local key = kind .. "\0" .. name
		local o = M.ext.ms[key]
		if o == nil then
			o = Inst.create(cls, { Name = name })
			getmt(o).ext = { s = msStruct(kind, name), extra = extra }
			M.ext.ms[key] = o
		end
		return o
	end
	local function sOf(self)
		return getmt(self).ext.s
	end
	local function sortKeyOk(sk, n, fname)
		if sk ~= nil and type(sk) ~= "number" and type(sk) ~= "string" then
			raise(fmt("%s: sortKey must be a number or string", fname))
		end
		return sk
	end

	local SM = {}
	function SM.GetAsync(self, key)
		Inst.checkSelf(self, "GetAsync")
		key = msCheckKey(key, 1, "GetAsync")
		Svc.latency(0.05)
		local e = sOf(self).data[key]
		if not msLive(e) then
			return nil
		end
		return deepCopy(e.value), e.sortKey
	end
	function SM.SetAsync(self, key, value, expiration, sortKey)
		Inst.checkSelf(self, "SetAsync")
		key = msCheckKey(key, 1, "SetAsync")
		local copy = msValue(value, "SetAsync")
		expiration = msCheckExpiration(expiration, 3, "SetAsync")
		sortKeyOk(sortKey, 4, "SetAsync")
		Svc.latency(0.05)
		local s = sOf(self)
		local isNew = not msLive(s.data[key])
		s.data[key] = { value = copy, expires = Sched.now + expiration, sortKey = sortKey }
		return isNew
	end
	function SM.UpdateAsync(self, key, transform, expiration)
		Inst.checkSelf(self, "UpdateAsync")
		key = msCheckKey(key, 1, "UpdateAsync")
		if type(transform) ~= "function" then
			Util.badArg(2, "UpdateAsync", "function", transform)
		end
		expiration = msCheckExpiration(expiration, 3, "UpdateAsync")
		Svc.latency(0.05)
		local s = sOf(self)
		local e = s.data[key]
		local cur = msLive(e) and deepCopy(e.value) or nil
		local res = table.pack(Sched.callNoYield(transform, cur, msLive(e) and e.sortKey or nil))
		if not res[1] then
			error(res[2], 0)
		end
		if res[2] == nil then
			return nil
		end
		local copy = msValue(res[2], "UpdateAsync")
		local sk = s.kind == "sorted" and sortKeyOk(res[3], 2, "UpdateAsync") or nil
		s.data[key] = { value = copy, expires = Sched.now + expiration, sortKey = sk }
		return deepCopy(copy), sk
	end
	function SM.RemoveAsync(self, key)
		Inst.checkSelf(self, "RemoveAsync")
		key = msCheckKey(key, 1, "RemoveAsync")
		Svc.latency(0.05)
		sOf(self).data[key] = nil
	end
	function SM.GetRangeAsync(self, direction, count, lower, upper)
		Inst.checkSelf(self, "GetRangeAsync")
		local dir = Enum.coerce(direction, "SortDirection")
		if dir == nil then
			Util.badArg(1, "GetRangeAsync", "Enum.SortDirection", direction)
		end
		count = Util.checkNumber(count, 2, "GetRangeAsync")
		if count < 1 or count > 200 or count ~= math.floor(count) then
			raise("GetRangeAsync: count must be an integer between 1 and 200")
		end
		local function bound(b, n)
			if b == nil then
				return nil
			end
			if type(b) == "string" then
				-- ältere Form (nur Schlüssel) – wird von Roblox weiterhin akzeptiert
				return { key = b }
			end
			if type(b) ~= "table" then
				Util.badArg(n, "GetRangeAsync", "table", b)
			end
			return b
		end
		lower, upper = bound(lower, 3), bound(upper, 4)
		Svc.latency(0.05)
		local items = {}
		for k, e in sOf(self).data do
			if msLive(e) then
				items[#items + 1] = { key = k, value = deepCopy(e.value), sortKey = e.sortKey }
			end
		end
		local function cmp(a, b)
			-- Sortierung: sortKey (Zahlen vor Strings), dann key
			local sa, sb = a.sortKey, b.sortKey
			if sa ~= sb then
				if sa == nil then
					return true
				elseif sb == nil then
					return false
				end
				local ta, tb = type(sa), type(sb)
				if ta ~= tb then
					return ta == "number"
				end
				return sa < sb
			end
			return a.key < b.key
		end
		table.sort(items, cmp)
		local function above(it, b)
			if b == nil then
				return true
			end
			local probe = { key = b.key or "", sortKey = b.sortKey }
			return cmp(probe, it)
		end
		local function below(it, b)
			if b == nil then
				return true
			end
			local probe = { key = b.key or "\255", sortKey = b.sortKey }
			return cmp(it, probe)
		end
		local out = {}
		local function consider(it)
			if above(it, lower) and below(it, upper) and #out < count then
				out[#out + 1] = it
			end
		end
		if dir.Name == "Ascending" then
			for i = 1, #items do
				consider(items[i])
			end
		else
			for i = #items, 1, -1 do
				consider(items[i])
			end
		end
		return out
	end
	Inst.define("MemoryStoreSortedMap", { methods = SM })

	local HM = {}
	HM.GetAsync = function(self, key)
		Inst.checkSelf(self, "GetAsync")
		key = msCheckKey(key, 1, "GetAsync")
		Svc.latency(0.05)
		local e = sOf(self).data[key]
		if not msLive(e) then
			return nil
		end
		return deepCopy(e.value)
	end
	HM.SetAsync = function(self, key, value, expiration)
		Inst.checkSelf(self, "SetAsync")
		key = msCheckKey(key, 1, "SetAsync")
		local copy = msValue(value, "SetAsync")
		expiration = msCheckExpiration(expiration, 3, "SetAsync")
		Svc.latency(0.05)
		local s = sOf(self)
		local isNew = not msLive(s.data[key])
		s.data[key] = { value = copy, expires = Sched.now + expiration }
		return isNew
	end
	HM.UpdateAsync = function(self, key, transform, expiration)
		Inst.checkSelf(self, "UpdateAsync")
		key = msCheckKey(key, 1, "UpdateAsync")
		if type(transform) ~= "function" then
			Util.badArg(2, "UpdateAsync", "function", transform)
		end
		expiration = msCheckExpiration(expiration, 3, "UpdateAsync")
		Svc.latency(0.05)
		local s = sOf(self)
		local e = s.data[key]
		local res = table.pack(Sched.callNoYield(transform, msLive(e) and deepCopy(e.value) or nil))
		if not res[1] then
			error(res[2], 0)
		end
		if res[2] == nil then
			return nil
		end
		local copy = msValue(res[2], "UpdateAsync")
		s.data[key] = { value = copy, expires = Sched.now + expiration }
		return deepCopy(copy)
	end
	HM.RemoveAsync = SM.RemoveAsync
	HM.ListItemsAsync = function(self, count)
		Inst.checkSelf(self, "ListItemsAsync")
		count = Util.checkNumber(count, 1, "ListItemsAsync")
		if count < 1 or count > 200 then
			raise("ListItemsAsync: count must be between 1 and 200")
		end
		Svc.latency(0.05)
		local keys = {}
		for k, e in sOf(self).data do
			if msLive(e) then
				keys[#keys + 1] = k
			end
		end
		table.sort(keys)
		local pages, page = {}, {}
		for _, k in keys do
			page[#page + 1] = { key = k, value = deepCopy(sOf(self).data[k].value) }
			if #page >= count then
				pages[#pages + 1] = page
				page = {}
			end
		end
		if #page > 0 or #pages == 0 then
			pages[#pages + 1] = page
		end
		return Svc.newPages("MemoryStoreHashMapPages", pages)
	end
	Inst.define("MemoryStoreHashMap", { methods = HM })

	local MQ = {}
	function MQ.AddAsync(self, value, expiration, priority)
		Inst.checkSelf(self, "AddAsync")
		local copy = msValue(value, "AddAsync")
		expiration = msCheckExpiration(expiration, 2, "AddAsync")
		priority = Util.optNumber(priority, 3, "AddAsync", 0)
		Svc.latency(0.05)
		local s = sOf(self)
		s.seq += 1
		table.insert(s.queue, { value = copy, expires = Sched.now + expiration, priority = priority, seq = s.seq })
		table.sort(s.queue, function(a, b)
			if a.priority ~= b.priority then
				return a.priority > b.priority
			end
			return a.seq < b.seq
		end)
	end
	function MQ.ReadAsync(self, count, allOrNothing, waitTimeout)
		Inst.checkSelf(self, "ReadAsync")
		count = Util.checkNumber(count, 1, "ReadAsync")
		if count < 1 or count > 200 then
			raise("ReadAsync: count must be between 1 and 200")
		end
		waitTimeout = Util.optNumber(waitTimeout, 3, "ReadAsync", -1)
		local s = sOf(self)
		local invis = (getmt(self).ext.extra or 30)
		local deadline = waitTimeout < 0 and Sched.now + 30 or Sched.now + waitTimeout
		while true do
			Svc.latency(0.05)
			local avail = {}
			for _, it in s.queue do
				if msLive(it) and (it.invisibleUntil == nil or it.invisibleUntil <= Sched.now) then
					avail[#avail + 1] = it
					if #avail >= count then
						break
					end
				end
			end
			if #avail > 0 and (not allOrNothing or #avail >= count) then
				s.readSeq = (s.readSeq or 0) + 1
				local id = "read-" .. s.readSeq
				local out = {}
				for _, it in avail do
					it.invisibleUntil = Sched.now + invis
					it.readId = id
					out[#out + 1] = deepCopy(it.value)
				end
				return out, id
			end
			if Sched.now >= deadline then
				return {}, ""
			end
			Sched.wait(0.5)
		end
	end
	function MQ.RemoveAsync(self, id)
		Inst.checkSelf(self, "RemoveAsync")
		id = Util.checkString(id, 1, "RemoveAsync")
		Svc.latency(0.05)
		local s = sOf(self)
		for i = #s.queue, 1, -1 do
			if s.queue[i].readId == id then
				table.remove(s.queue, i)
			end
		end
	end
	function MQ.GetSizeAsync(self, excludeInvisible)
		Inst.checkSelf(self, "GetSizeAsync")
		Svc.latency(0.05)
		local n = 0
		for _, it in sOf(self).queue do
			if msLive(it) and not (excludeInvisible and it.invisibleUntil and it.invisibleUntil > Sched.now) then
				n += 1
			end
		end
		return n
	end
	Inst.define("MemoryStoreQueue", { methods = MQ })

	local MSS = {}
	function MSS.GetSortedMap(self, name)
		Inst.checkSelf(self, "GetSortedMap")
		msAccess(self)
		name = Util.checkString(name, 1, "GetSortedMap")
		return msObj(self, "MemoryStoreSortedMap", "sorted", name)
	end
	function MSS.GetHashMap(self, name)
		Inst.checkSelf(self, "GetHashMap")
		msAccess(self)
		name = Util.checkString(name, 1, "GetHashMap")
		return msObj(self, "MemoryStoreHashMap", "hash", name)
	end
	function MSS.GetQueue(self, name, invisibilityTimeout)
		Inst.checkSelf(self, "GetQueue")
		msAccess(self)
		name = Util.checkString(name, 1, "GetQueue")
		invisibilityTimeout = Util.optNumber(invisibilityTimeout, 2, "GetQueue", 30)
		return msObj(self, "MemoryStoreQueue", "queue", name, invisibilityTimeout)
	end
	Inst.registerService("MemoryStoreService", { methods = MSS })

	-- =================================================================================================
	--  MessagingService
	-- =================================================================================================
	local subscribers = {} -- topic -> list { fn, ctx, conn }
	D.subscribers = subscribers
	local MS = {}
	local function msgAccess(self)
		local ctx = Svc.ctxOf(self)
		if ctx.isClient then
			raise("MessagingService can't be accessed from client")
		end
	end
	function MS.PublishAsync(self, topic, message)
		Inst.checkSelf(self, "PublishAsync")
		msgAccess(self)
		topic = Util.checkString(topic, 1, "PublishAsync")
		if #topic > 80 then
			raise("PublishAsync: topic name exceeds the 80 character limit")
		end
		local copy, bytes = D.storable(message, { word = "message" })
		if bytes > 1024 then
			raise(fmt("PublishAsync: message size (%d bytes) exceeds the 1kB limit", bytes))
		end
		Svc.latency(0.05)
		local sent = Sched.unix()
		Sched.addTimer(Sched.now + 0.1, function()
			for _, sub in table.clone(subscribers[topic] or {}) do
				local cm = getmt(sub.conn)
				if cm.connected and not (sub.ctx and sub.ctx.closed) then
					Sched.spawnHandler(sub.fn, sub.ctx, "MessagingService:" .. topic, { Data = deepCopy(copy), Sent = sent })
				end
			end
		end)
	end
	function MS.SubscribeAsync(self, topic, callback)
		Inst.checkSelf(self, "SubscribeAsync")
		msgAccess(self)
		topic = Util.checkString(topic, 1, "SubscribeAsync")
		if #topic > 80 then
			raise("SubscribeAsync: topic name exceeds the 80 character limit")
		end
		if type(callback) ~= "function" then
			Util.badArg(2, "SubscribeAsync", "function", callback)
		end
		Svc.latency(0.05)
		local sig = R.Signal.new("MessagingService:" .. topic)
		local conn = sig:Connect(function() end)
		subscribers[topic] = subscribers[topic] or {}
		table.insert(subscribers[topic], { fn = callback, ctx = Sched.ctx(), conn = conn })
		return conn
	end
	Inst.registerService("MessagingService", { methods = MS })
end
