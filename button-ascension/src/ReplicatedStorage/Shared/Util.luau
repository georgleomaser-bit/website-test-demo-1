--[[
	Util (ModuleScript)
	Location: ReplicatedStorage/Shared/Util

	Small pure helpers shared by server and client. No Roblox services
	(serverTime only reads the synced workspace clock).
]]

local Util = {}

function Util.deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value :: any) do
		copy[Util.deepCopy(k)] = Util.deepCopy(v)
	end
	return (copy :: any) :: T
end

function Util.isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Util.clamp(value: number, min: number, max: number): number
	if value < min then
		return min
	elseif value > max then
		return max
	end
	return value
end

function Util.round(value: number, decimals: number?): number
	local m = 10 ^ (decimals or 0)
	return math.floor(value * m + 0.5) / m
end

function Util.countKeys(t: { [any]: any }): number
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

function Util.sortedKeys(t: { [any]: any }): { any }
	local keys = {}
	for k in pairs(t) do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return keys
end

-- Picks an entry from a list of tables that each have a Weight field.
function Util.weightedPick<T>(rng: Random, list: { T }): T
	local total = 0
	for _, entry in ipairs(list) do
		total += (entry :: any).Weight
	end
	local roll = rng:NextNumber() * total
	for _, entry in ipairs(list) do
		roll -= (entry :: any).Weight
		if roll <= 0 then
			return entry
		end
	end
	return list[#list]
end

-- Whole UTC day number for a unix timestamp.
-- Unix time synced to the server clock (a player's device clock can be wrong).
function Util.serverTime(): number
	return math.floor(workspace:GetServerTimeNow())
end

function Util.dayNumber(timestamp: number): number
	return math.floor(timestamp / 86400)
end

-- Seconds until the next UTC midnight.
function Util.secondsUntilNextDay(timestamp: number): number
	return (Util.dayNumber(timestamp) + 1) * 86400 - timestamp
end

function Util.trim(s: string): string
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

function Util.split(s: string): { string }
	local parts = {}
	for part in string.gmatch(s, "%S+") do
		table.insert(parts, part)
	end
	return parts
end

-- Returns a shallow array of the values of t, in key order (deterministic).
function Util.values<V>(t: { [any]: V }): { V }
	local out = {}
	for _, k in ipairs(Util.sortedKeys(t)) do
		table.insert(out, t[k])
	end
	return out
end

return Util
