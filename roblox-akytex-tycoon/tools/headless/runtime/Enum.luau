--!nocheck
-- =====================================================================
--  Headless-Harness · Enum-System
--  Enum (global, typeof "Enums") -> Enum.Material (typeof "Enum") -> Enum.Material.Neon (typeof "EnumItem").
--  EnumItems sind Singletons (rawequal-vergleichbar, als Tabellenschlüssel nutzbar), Werte aus api_data.luau.
--  Unbekannte Namen -> Fehler wie Roblox: 'Foo is not a valid member of "Enum.Material"'.
--
--  Harness-API:
--   E.item(enumName, itemName)      -> EnumItem (wirft Harness-Fehler, wenn unbekannt)
--   E.fromValue(enumName, value)    -> EnumItem oder nil
--   E.coerce(v, enumName)           -> EnumItem oder nil (akzeptiert EnumItem des Typs, Namen-String, Zahl-Wert)
--   E.isItem(v), E.enumOf(item)     -> Hilfen
--   E.global                        -> das globale Enum-Objekt für Script-Umgebungen
-- =====================================================================
return function(R)
	local Util = R.Util
	local raise = Util.raise
	local getmt = getmetatable
	local api = R.api
	local E = {}

	local enumObjs = {} -- name -> Enum-userdata
	local itemIndex, enumIndex, enumsIndex

	-- ---------------------------------------------------------------------------------------------
	--  EnumItem
	-- ---------------------------------------------------------------------------------------------
	local itemMethods = {}
	function itemMethods.IsA(self, enumName)
		local m = Util.hostMeta(self)
		if not m or m.__index ~= itemIndex then
			raise("Expected ':' not '.' calling member function IsA")
		end
		enumName = Util.checkString(enumName, 1, "IsA")
		return m.enumName == enumName
	end
	function itemMethods.GetEnumItems(self)
		raise("GetEnumItems is not a valid member of EnumItem")
	end

	function itemIndex(self, k)
		local m = getmt(self)
		if k == "Name" then
			return m.name
		elseif k == "Value" then
			return m.value
		elseif k == "EnumType" then
			return enumObjs[m.enumName]
		elseif k == "IsA" then
			return itemMethods.IsA
		end
		raise(tostring(k) .. ' is not a valid member of "' .. "Enum." .. m.enumName .. "." .. m.name .. '"')
	end
	Util.registerHostIndex(itemIndex)

	local function itemNewindex(self, k)
		raise(tostring(k) .. " cannot be assigned to")
	end

	local function itemToString(self)
		local m = getmt(self)
		return "Enum." .. m.enumName .. "." .. m.name
	end
	local function itemConcat(a, b)
		raise(string.format("attempt to concatenate %s with %s", Util.typeof(a), Util.typeof(b)))
	end
	local function itemLt(a, b)
		raise(string.format("attempt to compare %s < %s", Util.typeof(a), Util.typeof(b)))
	end
	local function itemLe(a, b)
		raise(string.format("attempt to compare %s <= %s", Util.typeof(a), Util.typeof(b)))
	end
	local function newItem(enumName, name, value)
		local u = newproxy(true)
		local mt = getmt(u)
		mt.__index = itemIndex
		mt.__newindex = itemNewindex
		mt.__type = "EnumItem"
		mt.__tostring = itemToString
		mt.__concat = itemConcat
		mt.__lt = itemLt
		mt.__le = itemLe
		mt.enumName = enumName
		mt.name = name
		mt.value = value
		return u
	end

	-- ---------------------------------------------------------------------------------------------
	--  Enum
	-- ---------------------------------------------------------------------------------------------
	local enumMethods = {}
	local function selfEnum(self, m)
		local mt = Util.hostMeta(self)
		if not mt or mt.__index ~= enumIndex then
			raise("Expected ':' not '.' calling member function " .. m)
		end
		return mt
	end
	function enumMethods.GetEnumItems(self)
		local mt = selfEnum(self, "GetEnumItems")
		local out = table.create(#mt.list)
		for i, it in mt.list do
			out[i] = it
		end
		return out
	end
	function enumMethods.FromName(self, name)
		local mt = selfEnum(self, "FromName")
		name = Util.checkString(name, 1, "FromName")
		return mt.byName[name]
	end
	function enumMethods.FromValue(self, value)
		local mt = selfEnum(self, "FromValue")
		value = Util.checkNumber(value, 1, "FromValue")
		return mt.byValue[value]
	end

	function enumIndex(self, k)
		local mt = getmt(self)
		local it = mt.byName[k]
		if it then
			return it
		end
		local f = enumMethods[k]
		if f then
			return f
		end
		raise(tostring(k) .. ' is not a valid member of "Enum.' .. mt.name .. '"')
	end
	Util.registerHostIndex(enumIndex)

	local function buildEnum(name)
		local items = api.enums[name]
		if not items then
			return nil
		end
		local u = newproxy(true)
		local mt = getmt(u)
		mt.__index = enumIndex
		mt.__newindex = itemNewindex
		mt.__type = "Enum"
		mt.__tostring = function()
			return name
		end
		mt.name = name
		mt.byName = {}
		mt.byValue = {}
		mt.list = {}
		local order = api.enumOrder and api.enumOrder[name]
		local names = {}
		if order then
			for _, n in order do
				names[#names + 1] = n
			end
		else
			for n in items do
				names[#names + 1] = n
			end
		end
		for _, n in names do
			local it = newItem(name, n, items[n])
			mt.byName[n] = it
			if mt.byValue[items[n]] == nil then
				mt.byValue[items[n]] = it
			end
			mt.list[#mt.list + 1] = it
		end
		table.sort(mt.list, function(a, b)
			local va, vb = getmt(a).value, getmt(b).value
			if va ~= vb then
				return va < vb
			end
			return getmt(a).name < getmt(b).name
		end)
		enumObjs[name] = u
		return u
	end

	local function getEnum(name)
		local e = enumObjs[name]
		if e == nil then
			e = buildEnum(name)
		end
		return e
	end
	E.getEnum = getEnum

	-- ---------------------------------------------------------------------------------------------
	--  Enums (globales Enum)
	-- ---------------------------------------------------------------------------------------------
	local enumsMethods = {}
	function enumsMethods.GetEnums(self)
		local out = {}
		for name in api.enums do
			out[#out + 1] = getEnum(name)
		end
		table.sort(out, function(a, b)
			return getmt(a).name < getmt(b).name
		end)
		return out
	end
	function enumsIndex(self, k)
		if type(k) == "string" then
			local e = getEnum(k)
			if e then
				return e
			end
		end
		local f = enumsMethods[k]
		if f then
			return f
		end
		raise(tostring(k) .. ' is not a valid member of "Enum"')
	end
	Util.registerHostIndex(enumsIndex)
	do
		local u = newproxy(true)
		local mt = getmt(u)
		mt.__index = enumsIndex
		mt.__newindex = itemNewindex
		mt.__type = "Enums"
		mt.__tostring = function()
			return "Enums"
		end
		E.global = u
	end

	-- ---------------------------------------------------------------------------------------------
	--  Harness-Helfer
	-- ---------------------------------------------------------------------------------------------
	function E.isItem(v)
		local mt = Util.hostMeta(v)
		return mt ~= nil and mt.__index == itemIndex
	end
	function E.isEnum(v)
		local mt = Util.hostMeta(v)
		return mt ~= nil and mt.__index == enumIndex
	end
	function E.enumNameOf(item)
		return getmt(item).enumName
	end
	function E.item(enumName, itemName)
		local e = getEnum(enumName)
		if not e then
			error("Harness: unbekanntes Enum " .. tostring(enumName), 2)
		end
		local it = getmt(e).byName[itemName]
		if not it then
			error("Harness: unbekanntes EnumItem Enum." .. enumName .. "." .. tostring(itemName), 2)
		end
		return it
	end
	function E.tryItem(enumName, itemName)
		local e = getEnum(enumName)
		return e and getmt(e).byName[itemName]
	end
	function E.fromValue(enumName, value)
		local e = getEnum(enumName)
		return e and getmt(e).byValue[value]
	end
	function E.first(enumName)
		local e = getEnum(enumName)
		if not e then
			return nil
		end
		local m = getmt(e)
		return m.byValue[0] or m.list[1]
	end
	--- EnumItem des richtigen Typs, Name als String oder Zahl-Wert -> EnumItem; sonst nil
	function E.coerce(v, enumName)
		local mt = Util.hostMeta(v)
		if mt ~= nil and mt.__index == itemIndex then
			if mt.enumName == enumName then
				return v
			end
			return nil
		end
		local t = type(v)
		if t == "string" then
			return E.tryItem(enumName, v)
		elseif t == "number" then
			return E.fromValue(enumName, v)
		end
		return nil
	end
	function E.items(enumName)
		local e = getEnum(enumName)
		return e and getmt(e).list or {}
	end

	return E
end
