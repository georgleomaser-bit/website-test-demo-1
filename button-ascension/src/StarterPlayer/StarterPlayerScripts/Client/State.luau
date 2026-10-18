--[[
	State (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/State
	Depends on: (none)

	Read-only client mirror of the player's own data, filled by StateSync
	from the server. UI code subscribes to sections and re-renders when they
	change. Nothing here is ever sent back to the server.
]]

local State = {
	Data = {} :: { [string]: any },
	Ready = false,
}

local listeners: { [string]: { (string) -> () } } = {}
local readyCallbacks: { () -> () } = {}
local ALL = "*"

local function notify(sections: { [string]: boolean })
	local called: { [any]: boolean } = {}
	for section in pairs(sections) do
		for _, list in ipairs({ listeners[section] or {}, listeners[ALL] or {} }) do
			for _, fn in ipairs(list) do
				if not called[fn] then
					called[fn] = true
					task.spawn(fn, section)
				end
			end
		end
	end
end

function State.apply(kind: string, payload: { [string]: any })
	if type(payload) ~= "table" then
		return
	end
	local changed = {}
	for section, value in pairs(payload) do
		State.Data[section] = value
		changed[section] = true
	end
	if kind == "full" and not State.Ready then
		State.Ready = true
		for _, fn in ipairs(readyCallbacks) do
			task.spawn(fn)
		end
		table.clear(readyCallbacks)
	end
	if State.Ready then
		notify(changed)
	end
end

-- Calls fn(section) whenever one of the sections changes. Returns an unsubscribe function.
function State.subscribe(sections: { string } | string, fn: (string) -> ()): () -> ()
	local list = if type(sections) == "string" then { sections } else sections
	for _, section in ipairs(list) do
		listeners[section] = listeners[section] or {}
		table.insert(listeners[section], fn)
	end
	return function()
		for _, section in ipairs(list) do
			local l = listeners[section]
			if l then
				local index = table.find(l, fn)
				if index then
					table.remove(l, index)
				end
			end
		end
	end
end

function State.onReady(fn: () -> ())
	if State.Ready then
		task.spawn(fn)
	else
		table.insert(readyCallbacks, fn)
	end
end

function State.get(section: string): any
	return State.Data[section]
end

function State.stats()
	local derived = State.Data.Derived
	return derived and derived.Stats
end

function State.currency(currency: string): number
	local c = State.Data.Currencies
	return c and c[currency] or 0
end

function State.progress()
	return State.Data.Progress or { Level = 1, XP = 0, SkillPoints = 0, Rebirths = 0, XPRequired = 1 }
end

-- A table shaped like the server data, for Shared/Formulas previews.
function State.view()
	local d = State.Data
	local progress = State.progress()
	return {
		Currencies = d.Currencies or {},
		Upgrades = d.Upgrades or {},
		Ascension = d.Ascension or {},
		Skills = d.Skills or {},
		Inventory = d.Inventory or {},
		Equipped = d.Equipped or {},
		Discovered = d.Discovered or {},
		Stats = d.Stats or {},
		Passes = d.Passes or {},
		Boosts = d.Boosts or {},
		Rebirths = progress.Rebirths,
		Level = progress.Level,
	}
end

return State
