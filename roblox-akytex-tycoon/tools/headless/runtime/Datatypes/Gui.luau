--!nocheck
-- =====================================================================
--  Headless-Harness · UDim / UDim2 / Rect / Font / Content
--  UDim: Scale float32, Offset int32 (abgeschnitten wie lua_tointeger).
--  UDim2 speichert vier Zahlen; .X/.Y/.Width/.Height erzeugen (wie Roblox) jeweils neue UDim-Werte.
--  Font ist (wie in Roblox) veränderbar: font.Weight = … ist erlaubt; Property-Getter liefern daher Kopien.
-- =====================================================================
return function(R, DT)
	local Util = R.Util
	local raise = Util.raise
	local typeof = Util.typeof
	local checkNumber = Util.checkNumber
	local fmtFloat = Util.fmtFloat
	local getmt = getmetatable
	local f32 = Util.f32
	local toInt = Util.toInt
	local fmt = string.format

	-- int32-Abschneiden wie Roblox' Offset
	local function i32(x)
		x = toInt(x)
		if x > 2147483647 or x < -2147483648 then
			x = (x + 2147483648) % 4294967296 - 2147483648
		end
		return x
	end

	-- =================================================================================================
	--  UDim
	-- =================================================================================================
	local UD = {}
	DT.UDim = UD
	local UDindex, UDeq, UDtostring, UDadd, UDsub, UDunm
	local function newUD(s, o)
		local u = newproxy(true)
		local mt = getmt(u)
		mt.__index = UDindex
		mt.__newindex = DT.readonlyNewindex
		mt.__eq = UDeq
		mt.__tostring = UDtostring
		mt.__add = UDadd
		mt.__sub = UDsub
		mt.__unm = UDunm
		mt.__concat = DT.concatError
		mt.__lt = DT.ltError
		mt.__le = DT.leError
		mt.__type = "UDim"
		mt.s = f32(s)
		mt.o = i32(o)
		return u
	end
	DT.make.UD = newUD
	local function isUD(u)
		if type(u) ~= "userdata" then
			return false
		end
		local mt = getmt(u)
		return type(mt) == "table" and rawget(mt, "__index") == UDindex
	end
	DT.is.UDim = isUD
	function UDindex(self, k)
		local m = getmt(self)
		if k == "Scale" then
			return m.s
		elseif k == "Offset" then
			return m.o
		end
		DT.badMember("UDim", k)
	end
	Util.registerHostIndex(UDindex)
	function UDeq(a, b)
		if not (isUD(a) and isUD(b)) then
			return false
		end
		local x, y = getmt(a), getmt(b)
		return x.s == y.s and x.o == y.o
	end
	function UDtostring(self)
		local m = getmt(self)
		return fmtFloat(m.s) .. ", " .. m.o
	end
	local function udOp(a, n)
		if isUD(a) then
			return getmt(a)
		end
		raise(fmt("invalid argument #%d (UDim expected, got %s)", n, typeof(a)))
	end
	function UDadd(a, b)
		local x, y = udOp(a, 1), udOp(b, 2)
		return newUD(x.s + y.s, x.o + y.o)
	end
	function UDsub(a, b)
		local x, y = udOp(a, 1), udOp(b, 2)
		return newUD(x.s - y.s, x.o - y.o)
	end
	function UDunm(a)
		local x = getmt(a)
		return newUD(-x.s, -x.o)
	end
	function UD.new(s, o)
		return newUD(s == nil and 0 or checkNumber(s, 1, "new"), o == nil and 0 or checkNumber(o, 2, "new"))
	end
	function DT.udParts(u)
		local m = getmt(u)
		return m.s, m.o
	end

	-- =================================================================================================
	--  UDim2
	-- =================================================================================================
	local U2 = {}
	DT.UDim2 = U2
	local methods = {}
	local U2index, U2eq, U2tostring, U2add, U2sub, U2unm
	local function newU2(xs, xo, ys, yo)
		local u = newproxy(true)
		local mt = getmt(u)
		mt.__index = U2index
		mt.__newindex = DT.readonlyNewindex
		mt.__eq = U2eq
		mt.__tostring = U2tostring
		mt.__add = U2add
		mt.__sub = U2sub
		mt.__unm = U2unm
		mt.__concat = DT.concatError
		mt.__lt = DT.ltError
		mt.__le = DT.leError
		mt.__type = "UDim2"
		mt.xs = f32(xs)
		mt.xo = i32(xo)
		mt.ys = f32(ys)
		mt.yo = i32(yo)
		return u
	end
	DT.make.U2 = newU2
	local function isU2(u)
		if type(u) ~= "userdata" then
			return false
		end
		local mt = getmt(u)
		return type(mt) == "table" and rawget(mt, "__index") == U2index
	end
	DT.is.UDim2 = isU2
	function DT.u2Parts(u)
		local m = getmt(u)
		return m.xs, m.xo, m.ys, m.yo
	end
	function U2index(self, k)
		local m = getmt(self)
		if k == "X" or k == "Width" then
			return newUD(m.xs, m.xo)
		elseif k == "Y" or k == "Height" then
			return newUD(m.ys, m.yo)
		end
		local f = methods[k]
		if f then
			return f
		end
		DT.badMember("UDim2", k)
	end
	Util.registerHostIndex(U2index)
	function U2eq(a, b)
		if not (isU2(a) and isU2(b)) then
			return false
		end
		local x, y = getmt(a), getmt(b)
		return x.xs == y.xs and x.xo == y.xo and x.ys == y.ys and x.yo == y.yo
	end
	function U2tostring(self)
		local m = getmt(self)
		return "{" .. fmtFloat(m.xs) .. ", " .. m.xo .. "}, {" .. fmtFloat(m.ys) .. ", " .. m.yo .. "}"
	end
	local function u2Op(a, n)
		if isU2(a) then
			return getmt(a)
		end
		raise(fmt("invalid argument #%d (UDim2 expected, got %s)", n, typeof(a)))
	end
	function U2add(a, b)
		local x, y = u2Op(a, 1), u2Op(b, 2)
		return newU2(x.xs + y.xs, x.xo + y.xo, x.ys + y.ys, x.yo + y.yo)
	end
	function U2sub(a, b)
		local x, y = u2Op(a, 1), u2Op(b, 2)
		return newU2(x.xs - y.xs, x.xo - y.xo, x.ys - y.ys, x.yo - y.yo)
	end
	function U2unm(a)
		local x = getmt(a)
		return newU2(-x.xs, -x.xo, -x.ys, -x.yo)
	end

	function U2.new(a, b, c, d)
		if isUD(a) or isUD(b) then
			if not isUD(a) then
				Util.badArg(1, "new", "UDim", a)
			end
			if not isUD(b) then
				Util.badArg(2, "new", "UDim", b)
			end
			local x, y = getmt(a), getmt(b)
			return newU2(x.s, x.o, y.s, y.o)
		end
		return newU2(
			a == nil and 0 or checkNumber(a, 1, "new"),
			b == nil and 0 or checkNumber(b, 2, "new"),
			c == nil and 0 or checkNumber(c, 3, "new"),
			d == nil and 0 or checkNumber(d, 4, "new")
		)
	end
	function U2.fromScale(xs, ys)
		return newU2(xs == nil and 0 or checkNumber(xs, 1, "fromScale"), 0, ys == nil and 0 or checkNumber(ys, 2, "fromScale"), 0)
	end
	function U2.fromOffset(xo, yo)
		return newU2(0, xo == nil and 0 or checkNumber(xo, 1, "fromOffset"), 0, yo == nil and 0 or checkNumber(yo, 2, "fromOffset"))
	end
	function methods.Lerp(self, goal, alpha)
		if not isU2(self) then
			raise("Expected ':' not '.' calling member function Lerp")
		end
		if not isU2(goal) then
			Util.badArg(1, "Lerp", "UDim2", goal)
		end
		local t = checkNumber(alpha, 2, "Lerp")
		local a, b = getmt(self), getmt(goal)
		return newU2(
			a.xs + (b.xs - a.xs) * t,
			a.xo + (b.xo - a.xo) * t,
			a.ys + (b.ys - a.ys) * t,
			a.yo + (b.yo - a.yo) * t
		)
	end

	-- =================================================================================================
	--  Rect
	-- =================================================================================================
	local RC = {}
	DT.Rect = RC
	local RCindex, RCeq
	local function newRC(x0, y0, x1, y1)
		local u = newproxy(true)
		local mt = getmt(u)
		mt.__index = RCindex
		mt.__newindex = DT.readonlyNewindex
		mt.__eq = RCeq
		mt.__tostring = function(self)
			local m = getmt(self)
			return fmtFloat(m.x0) .. ", " .. fmtFloat(m.y0) .. ", " .. fmtFloat(m.x1) .. ", " .. fmtFloat(m.y1)
		end
		mt.__concat = DT.concatError
		mt.__type = "Rect"
		mt.x0, mt.y0, mt.x1, mt.y1 = f32(x0), f32(y0), f32(x1), f32(y1)
		return u
	end
	DT.make.RC = newRC
	local function isRC(u)
		local mt = Util.hostMeta(u)
		return mt ~= nil and mt.__index == RCindex
	end
	DT.is.Rect = isRC
	function RCindex(self, k)
		local m = getmt(self)
		if k == "Min" then
			return DT.make.V2(m.x0, m.y0)
		elseif k == "Max" then
			return DT.make.V2(m.x1, m.y1)
		elseif k == "Width" then
			return m.x1 - m.x0
		elseif k == "Height" then
			return m.y1 - m.y0
		end
		DT.badMember("Rect", k)
	end
	Util.registerHostIndex(RCindex)
	function RCeq(a, b)
		if not (isRC(a) and isRC(b)) then
			return false
		end
		local x, y = getmt(a), getmt(b)
		return x.x0 == y.x0 and x.y0 == y.y0 and x.x1 == y.x1 and x.y1 == y.y1
	end
	function RC.new(a, b, c, d)
		local n = (a ~= nil and 1 or 0) + (b ~= nil and 1 or 0) + (c ~= nil and 1 or 0) + (d ~= nil and 1 or 0)
		if n == 0 then
			return newRC(0, 0, 0, 0)
		end
		if DT.is.Vector2(a) then
			if not DT.is.Vector2(b) then
				Util.badArg(2, "new", "Vector2", b)
			end
			local p, q = getmt(a), getmt(b)
			return newRC(p.x, p.y, q.x, q.y)
		end
		return newRC(checkNumber(a, 1, "new"), checkNumber(b, 2, "new"), checkNumber(c, 3, "new"), checkNumber(d, 4, "new"))
	end

	-- =================================================================================================
	--  Font
	-- =================================================================================================
	local FT = {}
	DT.Font = FT
	local FTindex, FTnewindex, FTeq
	local function enumItem(v, enumName)
		return R.Enum.coerce(v, enumName)
	end
	local function newFT(family, weightItem, styleItem)
		local u = newproxy(true)
		local mt = getmt(u)
		mt.__index = FTindex
		mt.__newindex = FTnewindex
		mt.__eq = FTeq
		mt.__tostring = function(self)
			local m = getmt(self)
			return fmt("Font { Family = %s, Weight = %s, Style = %s }", m.family, m.weight.Name, m.style.Name)
		end
		mt.__concat = DT.concatError
		mt.__type = "Font"
		mt.family = family
		mt.weight = weightItem
		mt.style = styleItem
		return u
	end
	local function isFT(u)
		local mt = Util.hostMeta(u)
		return mt ~= nil and mt.__index == FTindex
	end
	DT.is.Font = isFT
	function DT.make.FT(family, weightName, styleName)
		return newFT(family, R.Enum.item("FontWeight", weightName or "Regular"), R.Enum.item("FontStyle", styleName or "Normal"))
	end
	function DT.copyFont(f)
		local m = getmt(f)
		return newFT(m.family, m.weight, m.style)
	end
	function DT.fontParts(f)
		local m = getmt(f)
		return m.family, m.weight, m.style
	end
	function FTindex(self, k)
		local m = getmt(self)
		if k == "Family" then
			return m.family
		elseif k == "Weight" then
			return m.weight
		elseif k == "Style" then
			return m.style
		elseif k == "Bold" then
			return m.weight.Value >= 600
		end
		DT.badMember("Font", k)
	end
	Util.registerHostIndex(FTindex)
	function FTnewindex(self, k, v)
		local m = getmt(self)
		if k == "Family" then
			m.family = Util.checkString(v, 3, "Family")
		elseif k == "Weight" then
			local it = enumItem(v, "FontWeight")
			if not it then
				raise(fmt("invalid argument #3 (Enum.FontWeight expected, got %s)", typeof(v)))
			end
			m.weight = it
		elseif k == "Style" then
			local it = enumItem(v, "FontStyle")
			if not it then
				raise(fmt("invalid argument #3 (Enum.FontStyle expected, got %s)", typeof(v)))
			end
			m.style = it
		elseif k == "Bold" then
			if type(v) ~= "boolean" then
				raise(fmt("invalid argument #3 (boolean expected, got %s)", typeof(v)))
			end
			m.weight = R.Enum.item("FontWeight", v and "Bold" or "Regular")
		else
			DT.badMember("Font", k)
		end
	end
	function FTeq(a, b)
		if not (isFT(a) and isFT(b)) then
			return false
		end
		local x, y = getmt(a), getmt(b)
		return x.family == y.family and x.weight == y.weight and x.style == y.style
	end
	local function weightStyle(fname, weight, style)
		local w = R.Enum.item("FontWeight", "Regular")
		local s = R.Enum.item("FontStyle", "Normal")
		if weight ~= nil then
			w = enumItem(weight, "FontWeight")
			if not w then
				Util.badArg(2, fname, "Enum.FontWeight", weight)
			end
		end
		if style ~= nil then
			s = enumItem(style, "FontStyle")
			if not s then
				Util.badArg(3, fname, "Enum.FontStyle", style)
			end
		end
		return w, s
	end
	function FT.new(family, weight, style)
		family = Util.checkString(family, 1, "new")
		local w, s = weightStyle("new", weight, style)
		return newFT(family, w, s)
	end
	function FT.fromName(name, weight, style)
		name = Util.checkString(name, 1, "fromName")
		if string.find(name, "[^%w_%-]") then
			raise("Font name can only contain alphanumeric characters, '_' and '-'")
		end
		local w, s = weightStyle("fromName", weight, style)
		return newFT("rbxasset://fonts/families/" .. name .. ".json", w, s)
	end
	function FT.fromId(id, weight, style)
		id = checkNumber(id, 1, "fromId")
		local w, s = weightStyle("fromId", weight, style)
		return newFT("rbxassetid://" .. tostring(Util.toInt(id)), w, s)
	end
	local suffixWeights = {
		{ "ExtraBold", "ExtraBold" },
		{ "SemiBold", "SemiBold" },
		{ "Semibold", "SemiBold" },
		{ "Black", "Heavy" },
		{ "Heavy", "Heavy" },
		{ "Bold", "Bold" },
		{ "Medium", "Medium" },
		{ "Light", "Light" },
	}
	function FT.fromEnum(fontEnum)
		local item = enumItem(fontEnum, "Font")
		if not item then
			Util.badArg(1, "fromEnum", "Enum.Font", fontEnum)
		end
		if item.Name == "Unknown" then
			raise("Cannot convert Enum.Font.Unknown to a Font")
		end
		local fam = R.api.fontEnum[item.Name]
		if not fam then
			fam = "rbxasset://fonts/families/" .. item.Name .. ".json"
		end
		local wname = "Regular"
		for _, pair in suffixWeights do
			local suf = pair[1]
			if #item.Name > #suf and string.sub(item.Name, -#suf) == suf then
				wname = pair[2]
				break
			end
		end
		local sname = string.find(item.Name, "Italic", 1, true) and "Italic" or "Normal"
		return newFT(fam, R.Enum.item("FontWeight", wname), R.Enum.item("FontStyle", sname))
	end

	-- =================================================================================================
	--  Content (neuer Asset-Typ)
	-- =================================================================================================
	local CT = {}
	DT.Content = CT
	local CTindex
	local function newCT(sourceType, uri, object)
		local u, mt = DT.newHost(CTindex, "Content", function(self)
			local m = getmt(self)
			return m.uri or (m.object and tostring(m.object)) or ""
		end, function(a, b)
			local x, y = Util.hostMeta(a), Util.hostMeta(b)
			return x ~= nil and y ~= nil and x.__index == CTindex and y.__index == CTindex and x.uri == y.uri and rawequal(x.object, y.object)
		end)
		mt.sourceType = sourceType
		mt.uri = uri
		mt.object = object
		return u
	end
	DT.is.Content = function(u)
		local mt = Util.hostMeta(u)
		return mt ~= nil and mt.__index == CTindex
	end
	function CTindex(self, k)
		local m = getmt(self)
		if k == "SourceType" then
			return R.Enum.item("ContentSourceType", m.sourceType)
		elseif k == "Uri" then
			return m.uri
		elseif k == "Object" then
			return m.object
		end
		DT.badMember("Content", k)
	end
	Util.registerHostIndex(CTindex)
	CT.none = newCT("None", nil, nil)
	function CT.fromUri(uri)
		return newCT("Uri", Util.checkString(uri, 1, "fromUri"), nil)
	end
	function CT.fromAssetId(id)
		return newCT("Uri", "rbxassetid://" .. tostring(Util.toInt(checkNumber(id, 1, "fromAssetId"))), nil)
	end
	function CT.fromObject(obj)
		if obj == nil then
			Util.missingArg(1)
		end
		return newCT("Object", nil, obj)
	end
end
