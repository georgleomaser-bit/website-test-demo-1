--[[
	Guard (ModuleScript)
	Location: ServerScriptService/Core/Guard

	Validation helpers for values that arrive from clients. Every helper
	returns the validated value, or nil when the input is unacceptable.
	Client input is never trusted: types, ranges and lengths are all checked.
]]

local Guard = {}

local function isFinite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- A string of at most maxLength characters (and at least minLength).
function Guard.string(value: any, maxLength: number, minLength: number?): string?
	if type(value) ~= "string" then
		return nil
	end
	local len = #value
	if len > maxLength or len < (minLength or 0) then
		return nil
	end
	return value
end

-- An integer within [min, max].
function Guard.integer(value: any, min: number, max: number): number?
	if not isFinite(value) or value ~= math.floor(value) then
		return nil
	end
	if value < min or value > max then
		return nil
	end
	return value
end

-- A finite number within [min, max].
function Guard.number(value: any, min: number, max: number): number?
	if not isFinite(value) then
		return nil
	end
	if value < min or value > max then
		return nil
	end
	return value
end

function Guard.boolean(value: any): boolean?
	if type(value) ~= "boolean" then
		return nil
	end
	return value
end

-- A string id that exists as a key in lookup (e.g. Items.ById).
function Guard.id(value: any, lookup: { [string]: any }, maxLength: number?): string?
	local s = Guard.string(value, maxLength or 64, 1)
	if s == nil or lookup[s] == nil then
		return nil
	end
	return s
end

-- A value contained in an array of allowed values.
function Guard.oneOf<T>(value: any, allowed: { T }): T?
	for _, v in ipairs(allowed) do
		if v == value then
			return v
		end
	end
	return nil
end

-- A plain table payload (or an empty table when nil). Rejects anything else.
function Guard.payload(value: any): { [any]: any }?
	if value == nil then
		return {}
	end
	if type(value) ~= "table" then
		return nil
	end
	return value
end

Guard.isFinite = isFinite

return Guard
