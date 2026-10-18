--[[
	Reflection.luau

	Answers "what is this member?" questions for mock Instances.

	Properties (name, datatype, scriptability, defaults) come from the Roblox
	reflection database bundled with Lune (@lune/roblox). Events, methods and
	callbacks come from generated/ApiMembers.luau (derived from the luau-lsp
	Roblox definitions, see tools/generate_api.luau), because the reflection
	database only describes properties.

	Also implements value coercion for property writes with Roblox-style error
	messages, e.g. "Unable to assign property Size. UDim2 expected, got number".
]]

local roblox = require("@lune/roblox")
local Types = require("./Types")
local Api = require("./generated/ApiMembers")

local db = roblox.getReflectionDatabase()
local Enum = roblox.Enum

local Reflection = {}

local classCache = {}
local memberCache = {}
local chainCache = {}
local defaultCache = {}

local function getClass(name: string)
	local cached = classCache[name]
	if cached ~= nil then
		return cached or nil
	end
	local ok, class = pcall(function()
		return db:GetClass(name)
	end)
	classCache[name] = (ok and class) or false
	return if ok then class else nil
end

local function tagSet(tags)
	local set = {}
	for _, t in ipairs(tags or {}) do
		set[t] = true
	end
	return set
end

function Reflection.classExists(name: string): boolean
	return type(name) == "string" and getClass(name) ~= nil
end

function Reflection.classTags(name: string): { [string]: boolean }
	local class = getClass(name)
	return if class then tagSet(class.Tags) else {}
end

function Reflection.isService(name: string): boolean
	return Reflection.classTags(name).Service == true
end

function Reflection.isCreatable(name: string): boolean
	local tags = Reflection.classTags(name)
	return Reflection.classExists(name) and not tags.NotCreatable and not tags.Service
end

function Reflection.superclass(name: string): string?
	local class = getClass(name)
	if class then
		return class.Superclass
	end
	local api = Api[name]
	return api and api.Super
end

-- { name, superclass, ..., "Instance", "Object" }
function Reflection.chain(name: string): { string }
	local cached = chainCache[name]
	if cached then
		return cached
	end
	local chain = {}
	local current: string? = name
	while current do
		table.insert(chain, current)
		local nextName = Reflection.superclass(current)
		if nextName == nil and current == "Instance" then
			nextName = "Object"
		end
		current = nextName
	end
	chainCache[name] = chain
	return chain
end

function Reflection.isA(className: string, base: string): boolean
	if className == base then
		return true
	end
	for _, name in ipairs(Reflection.chain(className)) do
		if name == base then
			return true
		end
	end
	return false
end

export type Member = {
	kind: string, -- "property" | "event" | "method" | "callback"
	name: string,
	owner: string,
	datatype: string?,
	scriptability: string?,
	tags: { [string]: boolean }?,
}

-- Resolves a member name on a class (walking the inheritance chain). Cached.
function Reflection.member(className: string, name: string): Member?
	local perClass = memberCache[className]
	if not perClass then
		perClass = {}
		memberCache[className] = perClass
	end
	local cached = perClass[name]
	if cached ~= nil then
		return cached or nil
	end
	local result: Member? = nil
	for _, owner in ipairs(Reflection.chain(className)) do
		local class = getClass(owner)
		if class then
			local prop = class.Properties[name]
			if prop then
				result = {
					kind = "property",
					name = name,
					owner = owner,
					datatype = prop.Datatype,
					scriptability = prop.Scriptability,
					tags = tagSet(prop.Tags),
				}
				break
			end
		end
		local api = Api[owner]
		if api then
			if table.find(api.Events, name) then
				result = { kind = "event", name = name, owner = owner }
				break
			elseif table.find(api.Methods, name) then
				result = { kind = "method", name = name, owner = owner }
				break
			elseif table.find(api.Callbacks, name) then
				result = { kind = "callback", name = name, owner = owner }
				break
			end
		end
	end
	perClass[name] = result or false
	return result
end

-- Enum defaults are missing from the bundled reflection defaults; these are the
-- engine defaults for the enum properties the harness is most likely to meet.
local ENUM_DEFAULTS = {
	TextXAlignment = "Center",
	TextYAlignment = "Center",
	FillDirection = "Vertical",
	SortOrder = "LayoutOrder",
	ScrollingDirection = "XY",
	HorizontalAlignment = "Left",
	VerticalAlignment = "Top",
	Font = "Legacy",
	ZIndexBehavior = "Sibling",
	ScaleType = "Stretch",
	AspectType = "FitWithinMaxSize",
	DominantAxis = "Width",
	EasingStyle = "Quad",
	EasingDirection = "Out",
	ApplyStrokeMode = "Contextual",
	LineJoinMode = "Round",
	ElasticBehavior = "WhenScrollable",
	VerticalScrollBarPosition = "Right",
	RunContext = "Legacy",
	Material = "Plastic",
	PartType = "Block",
	ResetOnSpawn = nil,
}

local function enumByName(enumName: string)
	local ok, enum = pcall(function()
		return (Enum :: any)[enumName]
	end)
	return if ok then enum else nil
end

local function defaultForDatatype(datatype: string, propName: string)
	if string.sub(datatype, 1, 5) == "Enum." then
		local enumName = string.sub(datatype, 6)
		local enum = enumByName(enumName)
		if not enum then
			return nil
		end
		local preferred = ENUM_DEFAULTS[enumName] or ENUM_DEFAULTS[propName]
		if preferred then
			local ok, item = pcall(function()
				return enum[preferred]
			end)
			if ok then
				return item
			end
		end
		local best = nil
		for _, item in ipairs(enum:GetEnumItems()) do
			if item.Value == 0 then
				return item
			end
			if best == nil or item.Value < best.Value then
				best = item
			end
		end
		return best
	end
	if datatype == "Bool" then
		return false
	elseif datatype == "Int32" or datatype == "Int64" or datatype == "Float32" or datatype == "Float64" then
		return 0
	elseif datatype == "String" or datatype == "BinaryString" or datatype == "ContentId" or datatype == "Content" then
		return ""
	elseif datatype == "Vector3" then
		return roblox.Vector3.zero
	elseif datatype == "Vector2" then
		return roblox.Vector2.zero
	elseif datatype == "CFrame" then
		return roblox.CFrame.new()
	elseif datatype == "Color3" then
		return roblox.Color3.new(0, 0, 0)
	elseif datatype == "UDim" then
		return roblox.UDim.new(0, 0)
	elseif datatype == "UDim2" then
		return roblox.UDim2.new(0, 0, 0, 0)
	elseif datatype == "Rect" then
		return roblox.Rect.new(0, 0, 0, 0)
	elseif datatype == "NumberRange" then
		return roblox.NumberRange.new(0)
	elseif datatype == "NumberSequence" then
		return roblox.NumberSequence.new(0)
	elseif datatype == "ColorSequence" then
		return roblox.ColorSequence.new(roblox.Color3.new(1, 1, 1))
	elseif datatype == "BrickColor" then
		return roblox.BrickColor.new("Medium stone grey")
	elseif datatype == "Font" then
		return roblox.Font.new("rbxasset://fonts/families/LegacyArial.json")
	end
	return nil
end

-- Engine defaults that are missing from the bundled reflection defaults.
-- Keyed by the class that declares the property.
local DEFAULT_OVERRIDES = {
	["BaseScript.Enabled"] = true,
	["Humanoid.Health"] = 100,
	["Sound.Pitch"] = 1,
	["Lighting.ClockTime"] = 14,
	["Workspace.FilteringEnabled"] = true,
	["Player.CanLoadCharacterAppearance"] = true,
	["BasePart.Elasticity"] = 0.5,
	["BasePart.Friction"] = 0.3,
}

-- Default value of a property for a concrete class.
function Reflection.default(className: string, member: Member)
	local key = className .. "." .. member.name
	local cached = defaultCache[key]
	if cached ~= nil then
		if cached == false then
			return nil
		end
		return cached
	end
	local value = DEFAULT_OVERRIDES[member.owner .. "." .. member.name]
	for _, owner in ipairs(if value == nil then Reflection.chain(className) else {}) do
		local class = getClass(owner)
		if class and class.DefaultProperties then
			local v = class.DefaultProperties[member.name]
			if v ~= nil then
				value = v
				break
			end
		end
	end
	local datatype = member.datatype or ""
	if value == nil or (string.sub(datatype, 1, 5) == "Enum." and Types.typeof(value) ~= "EnumItem") then
		value = defaultForDatatype(datatype, member.name)
	elseif datatype == "Ref" then
		value = nil
	end
	if value == nil then
		defaultCache[key] = false
	else
		defaultCache[key] = value
	end
	return value
end

local DATATYPE_NAMES = {
	Bool = "bool",
	Int32 = "int",
	Int64 = "int64",
	Float32 = "float",
	Float64 = "double",
	String = "string",
	BinaryString = "string",
	ContentId = "Content",
	Content = "Content",
	Ref = "Instance",
}

local VALUE_DATATYPES = {
	Vector3 = true,
	Vector2 = true,
	CFrame = true,
	Color3 = true,
	UDim = true,
	UDim2 = true,
	Rect = true,
	NumberRange = true,
	NumberSequence = true,
	ColorSequence = true,
	Font = true,
	BrickColor = true,
	Ray = true,
	Faces = true,
	Axes = true,
	Vector3int16 = true,
	Vector2int16 = true,
	Region3int16 = true,
	PhysicalProperties = true,
}

local function typeError(member: Member, expected: string, value)
	error(
		string.format("Unable to assign property %s. %s expected, got %s", member.name, expected, Types.typeof(value)),
		0
	)
end

--[[
	Converts `value` for assignment to `member`, raising Roblox-style errors.
	isInstance(value) tells whether value is a mock Instance (for Ref props).
]]
function Reflection.coerce(member: Member, value: any, isInstance: (any) -> boolean): any
	local datatype = member.datatype or ""
	local t = Types.typeof(value)

	if datatype == "Bool" then
		if t ~= "boolean" then
			typeError(member, "bool", value)
		end
		return value
	elseif datatype == "Int32" or datatype == "Int64" then
		local n = if t == "number" then value elseif t == "string" then tonumber(value) else nil
		if n == nil then
			typeError(member, DATATYPE_NAMES[datatype], value)
		end
		if n ~= n or n == math.huge or n == -math.huge then
			return 0
		end
		return if n >= 0 then math.floor(n) else -math.floor(-n)
	elseif datatype == "Float32" or datatype == "Float64" then
		local n = if t == "number" then value elseif t == "string" then tonumber(value) else nil
		if n == nil then
			typeError(member, DATATYPE_NAMES[datatype], value)
		end
		return n
	elseif datatype == "String" or datatype == "BinaryString" then
		if t == "number" then
			return tostring(value)
		end
		if t ~= "string" then
			typeError(member, "string", value)
		end
		return value
	elseif datatype == "ContentId" or datatype == "Content" then
		if t == "string" or t == "Content" then
			return value
		end
		if t == "number" then
			return tostring(value)
		end
		typeError(member, "Content", value)
	elseif datatype == "Ref" then
		if value == nil or isInstance(value) then
			return value
		end
		typeError(member, "Instance", value)
	elseif datatype == "OptionalCFrame" then
		if value == nil or t == "CFrame" then
			return value
		end
		typeError(member, "CFrame", value)
	elseif string.sub(datatype, 1, 5) == "Enum." then
		local enumName = string.sub(datatype, 6)
		local enum = enumByName(enumName)
		if t == "EnumItem" then
			if enum and value.EnumType ~= enum then
				error(
					string.format(
						"Unable to assign property %s. Expected Enum.%s, got %s",
						member.name,
						enumName,
						tostring(value)
					),
					0
				)
			end
			return value
		elseif t == "number" and enum then
			for _, item in ipairs(enum:GetEnumItems()) do
				if item.Value == value then
					return item
				end
			end
			error(string.format("Unable to assign property %s. Invalid value %d for enum %s", member.name, value, enumName), 0)
		elseif t == "string" and enum then
			local ok, item = pcall(function()
				return enum[value]
			end)
			if ok then
				return item
			end
			error(string.format('Unable to assign property %s. Invalid value "%s" for enum %s', member.name, value, enumName), 0)
		end
		typeError(member, "EnumItem", value)
	elseif VALUE_DATATYPES[datatype] then
		if datatype == "PhysicalProperties" and value == nil then
			return nil
		end
		if t ~= datatype then
			typeError(member, datatype, value)
		end
		return value
	end
	-- Unknown/exotic datatypes: accept as-is.
	return value
end

function Reflection.enumItems(enumName: string)
	local enum = enumByName(enumName)
	return if enum then enum:GetEnumItems() else {}
end

Reflection.Api = Api
Reflection.database = db

return Reflection
