--[[
	Types.luau

	Roblox datatypes for the mock environment.

	Most datatypes (Vector3, CFrame, Color3, UDim2, ...) come straight from
	@lune/roblox, so they behave exactly like the engine types. This module adds
	the ones Lune lacks (Random, TweenInfo, DateTime, RaycastParams,
	OverlapParams), patches Font.fromEnum for families Lune does not know, and
	provides a `typeof` that understands the harness' own objects (mock
	Instances, signals, connections ...).
]]

local roblox = require("@lune/roblox")

local Types = {}

-- Weak registry: object -> Roblox type name reported by typeof().
local registry = setmetatable({}, { __mode = "k" })
Types.registry = registry

local nativeTypeof = typeof

function Types.register(object: any, typeName: string)
	registry[object] = typeName
	return object
end

function Types.typeof(value: any): string
	local name = registry[value]
	if name then
		return name
	end
	return nativeTypeof(value)
end

-- Random ---------------------------------------------------------------------------
-- Mulberry32 implemented with 32-bit integer maths (bit32), deterministic per seed.

local function imul(a: number, b: number): number
	local aHi, aLo = bit32.rshift(a, 16), bit32.band(a, 0xFFFF)
	local bHi, bLo = bit32.rshift(b, 16), bit32.band(b, 0xFFFF)
	local lo = aLo * bLo
	local mid = bit32.band(aHi * bLo + aLo * bHi, 0xFFFF)
	return bit32.band(lo + bit32.lshift(mid, 16), 0xFFFFFFFF)
end

local RandomMethods = {}
RandomMethods.__index = RandomMethods

local seedCounter = 0

local function nextUInt32(self): number
	self._state = bit32.band(self._state + 0x6D2B79F5, 0xFFFFFFFF)
	local t = self._state
	t = imul(bit32.bxor(t, bit32.rshift(t, 15)), bit32.bor(t, 1))
	t = bit32.bxor(t, bit32.band(t + imul(bit32.bxor(t, bit32.rshift(t, 7)), bit32.bor(t, 61)), 0xFFFFFFFF))
	return bit32.bxor(t, bit32.rshift(t, 14))
end

local function newRandom(seed: number?)
	if seed == nil then
		seedCounter += 1
		seed = math.floor(os.clock() * 1e6) + seedCounter * 7919
	end
	local s = math.floor(seed :: number) % 4294967296
	local self = setmetatable({ _state = s, _seed = s }, RandomMethods)
	-- Warm up so nearby seeds diverge quickly.
	for _ = 1, 4 do
		nextUInt32(self)
	end
	registry[self] = "Random"
	return self
end

function RandomMethods:NextNumber(min: number?, max: number?): number
	local u = nextUInt32(self) / 4294967296
	if min == nil and max == nil then
		return u
	end
	local lo, hi = min or 0, max or 1
	return lo + (hi - lo) * u
end

function RandomMethods:NextInteger(min: number, max: number): number
	assert(type(min) == "number" and type(max) == "number", "NextInteger expects two numbers")
	min, max = math.floor(min), math.floor(max)
	if max < min then
		error("invalid argument #2 to 'NextInteger' (interval is empty)", 2)
	end
	local span = max - min + 1
	return min + math.floor(self:NextNumber() * span)
end

function RandomMethods:NextUnitVector()
	local z = self:NextNumber(-1, 1)
	local a = self:NextNumber(0, 2 * math.pi)
	local r = math.sqrt(1 - z * z)
	return roblox.Vector3.new(r * math.cos(a), r * math.sin(a), z)
end

function RandomMethods:Shuffle(t: { any })
	for i = #t, 2, -1 do
		local j = self:NextInteger(1, i)
		t[i], t[j] = t[j], t[i]
	end
end

function RandomMethods:Clone()
	local copy = newRandom(0)
	copy._state = self._state
	copy._seed = self._seed
	return copy
end

Types.Random = table.freeze({ new = newRandom })

-- TweenInfo ---------------------------------------------------------------------------

local TweenInfoMeta = {}
TweenInfoMeta.__index = function(self, key)
	local v = rawget(self, "_" .. tostring(key))
	if v == nil then
		error(tostring(key) .. " is not a valid member of TweenInfo", 2)
	end
	return v
end
TweenInfoMeta.__newindex = function(_, key)
	error(tostring(key) .. " cannot be assigned to", 2)
end
TweenInfoMeta.__tostring = function(self)
	return string.format("TweenInfo(%s, %s, %s)", tostring(rawget(self, "_Time")), tostring(rawget(self, "_EasingStyle")), tostring(rawget(self, "_EasingDirection")))
end

local function newTweenInfo(time: number?, style: any?, direction: any?, repeatCount: number?, reverses: boolean?, delayTime: number?)
	local info = setmetatable({
		_Time = time or 1,
		_EasingStyle = style or roblox.Enum.EasingStyle.Quad,
		_EasingDirection = direction or roblox.Enum.EasingDirection.Out,
		_RepeatCount = repeatCount or 0,
		_Reverses = if reverses == nil then false else reverses,
		_DelayTime = delayTime or 0,
	}, TweenInfoMeta)
	registry[info] = "TweenInfo"
	return info
end

Types.TweenInfo = table.freeze({ new = newTweenInfo })

-- DateTime ---------------------------------------------------------------------------
-- The clock is provided by the scheduler so DateTime.now() follows virtual time.

local DateTimeMeta = {}
DateTimeMeta.__index = DateTimeMeta

local function newDateTime(millis: number)
	local dt = setmetatable({ UnixTimestampMillis = math.floor(millis), UnixTimestamp = math.floor(millis / 1000) }, DateTimeMeta)
	registry[dt] = "DateTime"
	return dt
end

local function universal(self)
	local t = os.date("!*t", self.UnixTimestamp) :: any
	return {
		Year = t.year,
		Month = t.month,
		Day = t.day,
		Hour = t.hour,
		Minute = t.min,
		Second = t.sec,
		Millisecond = self.UnixTimestampMillis % 1000,
	}
end

function DateTimeMeta:ToUniversalTime()
	return universal(self)
end

function DateTimeMeta:ToLocalTime()
	return universal(self)
end

function DateTimeMeta:ToIsoDate(): string
	local t = universal(self)
	return string.format("%04d-%02d-%02dT%02d:%02d:%02dZ", t.Year, t.Month, t.Day, t.Hour, t.Minute, t.Second)
end

local function formatTime(self, format: string): string
	local t = universal(self)
	local replacements = {
		YYYY = string.format("%04d", t.Year),
		MM = string.format("%02d", t.Month),
		DD = string.format("%02d", t.Day),
		HH = string.format("%02d", t.Hour),
		mm = string.format("%02d", t.Minute),
		ss = string.format("%02d", t.Second),
	}
	local out = format
	for _, token in ipairs({ "YYYY", "MM", "DD", "HH", "mm", "ss" }) do
		out = string.gsub(out, token, replacements[token])
	end
	return out
end

function DateTimeMeta:FormatUniversalTime(format: string, _locale: string?): string
	return formatTime(self, format)
end

function DateTimeMeta:FormatLocalTime(format: string, _locale: string?): string
	return formatTime(self, format)
end

DateTimeMeta.__tostring = function(self)
	return self:ToIsoDate()
end
DateTimeMeta.__eq = function(a, b)
	return a.UnixTimestampMillis == b.UnixTimestampMillis
end
DateTimeMeta.__lt = function(a, b)
	return a.UnixTimestampMillis < b.UnixTimestampMillis
end
DateTimeMeta.__le = function(a, b)
	return a.UnixTimestampMillis <= b.UnixTimestampMillis
end

-- clock: function returning the current unix time in seconds (float)
function Types.makeDateTime(clock: () -> number)
	return table.freeze({
		now = function()
			return newDateTime(clock() * 1000)
		end,
		fromUnixTimestamp = function(seconds: number)
			return newDateTime(seconds * 1000)
		end,
		fromUnixTimestampMillis = function(millis: number)
			return newDateTime(millis)
		end,
		fromUniversalTime = function(year, month, day, hour, minute, second, millisecond)
			local t = os.time({
				year = year or 1970,
				month = month or 1,
				day = day or 1,
				hour = hour or 0,
				min = minute or 0,
				sec = second or 0,
			})
			-- os.time interprets the table as local time; Lune runs in UTC in CI, but correct anyway.
			local offset = os.time(os.date("!*t", 0) :: any)
			return newDateTime((t - offset) * 1000 + (millisecond or 0))
		end,
	})
end

-- Raycast / overlap parameter objects (plain property bags) -----------------------------

local function propertyBag(typeName: string, defaults: { [string]: any })
	return table.freeze({
		new = function()
			local bag = table.clone(defaults)
			registry[bag] = typeName
			return bag
		end,
	})
end

Types.RaycastParams = propertyBag("RaycastParams", {
	FilterDescendantsInstances = {},
	FilterType = roblox.Enum.RaycastFilterType.Exclude,
	IgnoreWater = false,
	CollisionGroup = "Default",
	RespectCanCollide = false,
	BruteForceAllSlow = false,
})
Types.OverlapParams = propertyBag("OverlapParams", {
	FilterDescendantsInstances = {},
	FilterType = roblox.Enum.RaycastFilterType.Exclude,
	CollisionGroup = "Default",
	RespectCanCollide = false,
	MaxParts = 0,
	BruteForceAllSlow = false,
})

-- Font: Lune only knows a subset of Enum.Font values; fall back to the family file. ----------

local LuneFont = roblox.Font
Types.Font = table.freeze({
	new = LuneFont.new,
	fromName = LuneFont.fromName,
	fromId = LuneFont.fromId,
	fromEnum = function(enumItem)
		local ok, font = pcall(LuneFont.fromEnum, enumItem)
		if ok then
			return font
		end
		local name = tostring(enumItem.Name)
		local weight = roblox.Enum.FontWeight.Regular
		for _, suffix in ipairs({ "ExtraBold", "SemiBold", "Bold", "Medium", "Light", "Heavy", "Black" }) do
			if #name > #suffix and string.sub(name, -#suffix) == suffix then
				local ok2, w = pcall(function()
					return (roblox.Enum.FontWeight :: any)[suffix]
				end)
				if ok2 then
					weight = w
				end
				name = string.sub(name, 1, #name - #suffix)
				break
			end
		end
		return LuneFont.new("rbxasset://fonts/families/" .. name .. ".json", weight)
	end,
})

-- Datatypes exposed to scripts --------------------------------------------------------------

Types.Datatypes = {
	Axes = roblox.Axes,
	BrickColor = roblox.BrickColor,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	Content = roblox.Content,
	Faces = roblox.Faces,
	Font = Types.Font,
	NumberRange = roblox.NumberRange,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	OverlapParams = Types.OverlapParams,
	PhysicalProperties = roblox.PhysicalProperties,
	Random = Types.Random,
	Ray = roblox.Ray,
	RaycastParams = Types.RaycastParams,
	Rect = roblox.Rect,
	Region3 = roblox.Region3,
	Region3int16 = roblox.Region3int16,
	TweenInfo = Types.TweenInfo,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Vector2 = roblox.Vector2,
	Vector2int16 = roblox.Vector2int16,
	Vector3 = roblox.Vector3,
	Vector3int16 = roblox.Vector3int16,
}

Types.Enum = roblox.Enum

-- Value types that are immutable and can be shared between worlds as-is.
Types.ValueTypes = {
	Axes = true,
	BrickColor = true,
	CFrame = true,
	Color3 = true,
	ColorSequence = true,
	ColorSequenceKeypoint = true,
	Content = true,
	EnumItem = true,
	Enum = true,
	Enums = true,
	Faces = true,
	Font = true,
	NumberRange = true,
	NumberSequence = true,
	NumberSequenceKeypoint = true,
	PhysicalProperties = true,
	Ray = true,
	Rect = true,
	Region3 = true,
	Region3int16 = true,
	TweenInfo = true,
	DateTime = true,
	UDim = true,
	UDim2 = true,
	Vector2 = true,
	Vector2int16 = true,
	Vector3 = true,
	Vector3int16 = true,
}

-- Attribute value types allowed by Instance:SetAttribute.
Types.AttributeTypes = {
	boolean = true,
	number = true,
	string = true,
	UDim = true,
	UDim2 = true,
	BrickColor = true,
	Color3 = true,
	Vector2 = true,
	Vector3 = true,
	CFrame = true,
	NumberSequence = true,
	ColorSequence = true,
	NumberRange = true,
	Rect = true,
	Font = true,
	EnumItem = true,
}

return Types
