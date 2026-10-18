--[[
	AuditLog (ModuleScript)
	Location: ServerScriptService/Admin/AuditLog
	Depends on: Admin/AdminConfig

	Records every admin request: who (UserId, name, role), what (action and
	sanitised parameters), whom (target UserId/name), when (unix time), and
	the result (success | denied | invalid | error | rate_limited |
	confirm_required | duplicate). Unauthorised attempts are recorded too.

	Entries live in a bounded in-memory buffer and are periodically appended
	to a DataStore key per UTC day ("Audit_YYYY-MM-DD") with UpdateAsync, so
	logs from every server end up in one place. Persistence failures are
	retried on the next flush and never block admin actions.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local AdminConfig = require(script.Parent.AdminConfig)
local CONFIG = AdminConfig.Audit

local AuditLog = {
	Entries = {} :: { any },
	Pending = {} :: { any },
	Persisting = false,
	PersistAvailable = false,
	LastFlushError = nil :: string?,
	Listeners = {} :: { (any) -> () },
}

local counter = 0
local serverTag = string.sub(HttpService:GenerateGUID(false), 1, 8)
local store: DataStore? = nil

local SENSITIVE_KEYS = { Token = true, RequestId = true }

-- Converts parameters into a short, readable, bounded string.
function AuditLog.formatParams(params: any): string
	if type(params) ~= "table" then
		return ""
	end
	local keys = {}
	for k in pairs(params) do
		if type(k) == "string" and not SENSITIVE_KEYS[k] then
			table.insert(keys, k)
		end
	end
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do
		local v = params[k]
		local text
		if type(v) == "table" then
			text = "{…}"
		else
			text = string.sub(tostring(v), 1, 80)
		end
		table.insert(parts, k .. "=" .. text)
		if #parts >= 8 then
			break
		end
	end
	return table.concat(parts, " ")
end

function AuditLog.init(persist: boolean)
	if CONFIG.Persist and persist then
		local ok, result = pcall(function()
			return DataStoreService:GetDataStore(CONFIG.StoreName)
		end)
		if ok then
			store = result
			AuditLog.PersistAvailable = true
		end
	end
	if AuditLog.PersistAvailable then
		task.spawn(function()
			while true do
				task.wait(CONFIG.FlushInterval)
				AuditLog.flush()
			end
		end)
		game:BindToClose(function()
			AuditLog.flush()
		end)
	end
end

--[[
	entry fields: AdminId, AdminName, Role, Action, TargetId, TargetName,
	Params (table), Result, Message
]]
function AuditLog.record(entry)
	counter += 1
	local record = {
		Id = serverTag .. "-" .. counter,
		Time = os.time(),
		AdminId = entry.AdminId,
		AdminName = entry.AdminName,
		Role = entry.Role or "None",
		Action = string.sub(tostring(entry.Action or "?"), 1, 60),
		TargetId = entry.TargetId,
		TargetName = entry.TargetName,
		Params = AuditLog.formatParams(entry.Params),
		Result = entry.Result or "success",
		Message = string.sub(tostring(entry.Message or ""), 1, 200),
		JobId = string.sub(game.JobId, 1, 12),
	}
	table.insert(AuditLog.Entries, record)
	if #AuditLog.Entries > CONFIG.MemoryLimit then
		table.remove(AuditLog.Entries, 1)
	end
	if AuditLog.PersistAvailable then
		table.insert(AuditLog.Pending, record)
		if #AuditLog.Pending > CONFIG.MaxEntriesPerDay then
			table.remove(AuditLog.Pending, 1)
		end
	end
	for _, listener in ipairs(AuditLog.Listeners) do
		task.spawn(listener, record)
	end
	return record
end

function AuditLog.onRecord(listener: (any) -> ())
	table.insert(AuditLog.Listeners, listener)
end

-- Recent entries, newest first, optionally filtered by text and result.
function AuditLog.recent(limit: number, filterText: string?, result: string?)
	local out = {}
	local needle = if filterText and filterText ~= "" then string.lower(filterText) else nil
	for i = #AuditLog.Entries, 1, -1 do
		local e = AuditLog.Entries[i]
		local matches = true
		if result and result ~= "" and result ~= "all" and e.Result ~= result then
			matches = false
		end
		if matches and needle then
			local hay = string.lower(
				table.concat({ e.Action, e.AdminName or "", e.TargetName or "", e.Params, e.Message, tostring(e.AdminId), tostring(e.TargetId or "") }, " ")
			)
			matches = string.find(hay, needle, 1, true) ~= nil
		end
		if matches then
			table.insert(out, e)
			if #out >= limit then
				break
			end
		end
	end
	return out
end

local function dayKey(t: number): string
	return "Audit_" .. os.date("!%Y-%m-%d", t)
end

function AuditLog.flush()
	if not store or AuditLog.Persisting or #AuditLog.Pending == 0 then
		return
	end
	AuditLog.Persisting = true
	-- Take the pending list; entries recorded while saving go into a fresh list.
	local taken = AuditLog.Pending
	AuditLog.Pending = {}
	-- Group pending entries by UTC day.
	local batches = {}
	for _, e in ipairs(taken) do
		local key = dayKey(e.Time)
		batches[key] = batches[key] or {}
		table.insert(batches[key], e)
	end
	local failed = {}
	for key, entries in pairs(batches) do
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(key, function(existing)
				local list = if type(existing) == "table" then existing else {}
				for _, e in ipairs(entries) do
					table.insert(list, e)
				end
				while #list > CONFIG.MaxEntriesPerDay do
					table.remove(list, 1)
				end
				return list
			end)
		end)
		if not ok then
			AuditLog.LastFlushError = tostring(err)
			for _, e in ipairs(entries) do
				table.insert(failed, e)
			end
		end
	end
	-- Failed entries are retried on the next flush, ahead of newer ones.
	for _, e in ipairs(AuditLog.Pending) do
		table.insert(failed, e)
	end
	AuditLog.Pending = failed
	AuditLog.Persisting = false
end

-- Loads persisted entries for a UTC day "YYYY-MM-DD" (newest first).
function AuditLog.loadDay(day: string)
	if not store then
		return nil, "Persistent audit logs are unavailable in this session."
	end
	if not string.match(day, "^%d%d%d%d%-%d%d%-%d%d$") then
		return nil, "Use the format YYYY-MM-DD."
	end
	local ok, result = pcall(function()
		return (store :: DataStore):GetAsync("Audit_" .. day)
	end)
	if not ok then
		return nil, "DataStore error: " .. tostring(result)
	end
	local list = if type(result) == "table" then result else {}
	local out = {}
	for i = #list, math.max(1, #list - 199), -1 do
		table.insert(out, list[i])
	end
	return out
end

return AuditLog
