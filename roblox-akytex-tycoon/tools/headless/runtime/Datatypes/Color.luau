--!nocheck
-- =====================================================================
--  Headless-Harness · Color3 / BrickColor / ColorSequence(+Keypoint)
--  Color3-Komponenten float32 (nativer vector in mt.v), keine Klemmung (Color3.new(2,0,0) ist erlaubt).
--  BrickColor-Tabelle (Name/Nummer/Palette/RGB) kommt aus api_data.luau (creator-docs).
-- =====================================================================
return function(R, DT)
	local Util = R.Util
	local raise = Util.raise
	local typeof = Util.typeof
	local checkNumber = Util.checkNumber
	local fmtFloat = Util.fmtFloat
	local getmt = getmetatable
	local vcreate = vector.create
	local floor, max, min, abs = math.floor, math.max, math.min, math.abs
	local fmt = string.format

	-- =================================================================================================
	--  Color3
	-- =================================================================================================
	local C3 = {}
	DT.Color3 = C3
	local methods = {}
	local C3index, C3eq, C3tostring

	local function newC3(r, g, b)
		local u = newproxy(true)
		local mt = getmt(u)
		mt.__index = C3index
		mt.__newindex = DT.readonlyNewindex
		mt.__eq = C3eq
		mt.__tostring = C3tostring
		mt.__concat = DT.concatError
		mt.__lt = DT.ltError
		mt.__le = DT.leError
		mt.__add = DT.arithError("add")
		mt.__sub = DT.arithError("sub")
		mt.__mul = DT.arithError("mul")
		mt.__div = DT.arithError("div")
		mt.__type = "Color3"
		mt.v = vcreate(r, g, b)
		return u
	end
	DT.make.C3 = newC3

	local function isC3(u)
		if type(u) ~= "userdata" then
			return false
		end
		local mt = getmt(u)
		return type(mt) == "table" and rawget(mt, "__index") == C3index
	end
	DT.is.Color3 = isC3
	local function checkC3(u, n, fname)
		if isC3(u) then
			return getmt(u).v
		end
		Util.badArg(n, fname, "Color3", u)
	end
	DT.checkC3 = checkC3
	function DT.c3rgb(u)
		local v = getmt(u).v
		return v.x, v.y, v.z
	end
	local function selfC3(self, mname)
		if isC3(self) then
			return getmt(self).v
		end
		raise(fmt("Expected ':' not '.' calling member function %s", mname))
	end

	function C3index(self, k)
		local v = getmt(self).v
		if k == "R" or k == "r" then
			return v.x
		elseif k == "G" or k == "g" then
			return v.y
		elseif k == "B" or k == "b" then
			return v.z
		end
		local m = methods[k]
		if m then
			return m
		end
		DT.badMember("Color3", k)
	end
	Util.registerHostIndex(C3index)
	function C3eq(a, b)
		if not (isC3(a) and isC3(b)) then
			return false
		end
		return getmt(a).v == getmt(b).v
	end
	function C3tostring(self)
		local v = getmt(self).v
		return fmtFloat(v.x) .. ", " .. fmtFloat(v.y) .. ", " .. fmtFloat(v.z)
	end

	function C3.new(r, g, b)
		return newC3(
			r == nil and 0 or checkNumber(r, 1, "new"),
			g == nil and 0 or checkNumber(g, 2, "new"),
			b == nil and 0 or checkNumber(b, 3, "new")
		)
	end
	function C3.fromRGB(r, g, b)
		r = r == nil and 0 or checkNumber(r, 1, "fromRGB")
		g = g == nil and 0 or checkNumber(g, 2, "fromRGB")
		b = b == nil and 0 or checkNumber(b, 3, "fromRGB")
		return newC3(r / 255, g / 255, b / 255)
	end

	local function hsvToRgb(h, s, v)
		h = h % 1
		local i = floor(h * 6)
		local f = h * 6 - i
		local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
		i = i % 6
		if i == 0 then
			return v, t, p
		elseif i == 1 then
			return q, v, p
		elseif i == 2 then
			return p, v, t
		elseif i == 3 then
			return p, q, v
		elseif i == 4 then
			return t, p, v
		end
		return v, p, q
	end
	DT.hsvToRgb = hsvToRgb
	local function rgbToHsv(r, g, b)
		local mx, mn = max(r, g, b), min(r, g, b)
		local d = mx - mn
		local h = 0
		if d ~= 0 then
			if mx == r then
				h = (g - b) / d % 6
			elseif mx == g then
				h = (b - r) / d + 2
			else
				h = (r - g) / d + 4
			end
			h = h / 6
			if h < 0 then
				h += 1
			end
		end
		local s = mx == 0 and 0 or d / mx
		return h, s, mx
	end
	DT.rgbToHsv = rgbToHsv

	function C3.fromHSV(h, s, v)
		h = checkNumber(h, 1, "fromHSV")
		s = checkNumber(s, 2, "fromHSV")
		v = checkNumber(v, 3, "fromHSV")
		return newC3(hsvToRgb(h, s, v))
	end
	function C3.toHSV(c)
		local v = checkC3(c, 1, "toHSV")
		return rgbToHsv(v.x, v.y, v.z)
	end
	function C3.fromHex(hex)
		hex = Util.checkString(hex, 1, "fromHex")
		local s = string.gsub(hex, "^#", "")
		if #s == 3 and not string.find(s, "[^%x]") then
			s = string.rep(string.sub(s, 1, 1), 2)
				.. string.rep(string.sub(s, 2, 2), 2)
				.. string.rep(string.sub(s, 3, 3), 2)
		end
		if #s ~= 6 or string.find(s, "[^%x]") then
			raise("Unable to convert characters to hex value")
		end
		return newC3(
			tonumber(string.sub(s, 1, 2), 16) / 255,
			tonumber(string.sub(s, 3, 4), 16) / 255,
			tonumber(string.sub(s, 5, 6), 16) / 255
		)
	end

	function methods.Lerp(self, color, alpha)
		local a = selfC3(self, "Lerp")
		local b = checkC3(color, 1, "Lerp")
		local t = checkNumber(alpha, 2, "Lerp")
		local v = a + (b - a) * t
		return newC3(v.x, v.y, v.z)
	end
	methods.lerp = methods.Lerp
	function methods.ToHSV(self)
		local v = selfC3(self, "ToHSV")
		return rgbToHsv(v.x, v.y, v.z)
	end
	local function byte(x)
		local n = floor(x * 255 + 0.5)
		if n < 0 then
			n = 0
		elseif n > 255 then
			n = 255
		end
		return n
	end
	DT.colorByte = byte
	function methods.ToHex(self)
		local v = selfC3(self, "ToHex")
		return fmt("%02x%02x%02x", byte(v.x), byte(v.y), byte(v.z))
	end

	-- =================================================================================================
	--  BrickColor
	-- =================================================================================================
	local BC = {}
	DT.BrickColor = BC
	local byNumber, byName, palette, ordered = {}, {}, {}, {}
	for _, row in R.api.brickColors do
		local e =
			{ number = row[1], name = row[2], r = row[3] / 255, g = row[4] / 255, b = row[5] / 255, palette = row[6] }
		byNumber[e.number] = e
		if byName[e.name] == nil then
			byName[e.name] = e
		end
		if e.palette >= 0 then
			palette[e.palette] = e
		end
		ordered[#ordered + 1] = e
	end
	if byNumber[194] == nil then
		byNumber[194] =
			{ number = 194, name = "Medium stone grey", r = 163 / 255, g = 162 / 255, b = 165 / 255, palette = -1 }
		ordered[#ordered + 1] = byNumber[194]
		byName["Medium stone grey"] = byNumber[194]
	end
	local DEFAULT = byNumber[194]
	local BCindex, BCeq, BCtostring

	local function newBC(e)
		local u = newproxy(true)
		local mt = getmt(u)
		mt.__index = BCindex
		mt.__newindex = DT.readonlyNewindex
		mt.__eq = BCeq
		mt.__tostring = BCtostring
		mt.__concat = DT.concatError
		mt.__type = "BrickColor"
		mt.e = e
		return u
	end
	local function isBC(u)
		if type(u) ~= "userdata" then
			return false
		end
		local mt = getmt(u)
		return type(mt) == "table" and rawget(mt, "__index") == BCindex
	end
	DT.is.BrickColor = isBC
	function DT.make.BC(number)
		return newBC(byNumber[number] or DEFAULT)
	end
	function DT.bcEntry(u)
		return getmt(u).e
	end
	function BCindex(self, k)
		local e = getmt(self).e
		if k == "Number" then
			return e.number
		elseif k == "Name" then
			return e.name
		elseif k == "Color" then
			return newC3(e.r, e.g, e.b)
		elseif k == "r" then
			return Util.f32(e.r)
		elseif k == "g" then
			return Util.f32(e.g)
		elseif k == "b" then
			return Util.f32(e.b)
		end
		DT.badMember("BrickColor", k)
	end
	Util.registerHostIndex(BCindex)
	function BCeq(a, b)
		if not (isBC(a) and isBC(b)) then
			return false
		end
		return getmt(a).e.number == getmt(b).e.number
	end
	function BCtostring(self)
		return getmt(self).e.name
	end

	local function closest(r, g, b)
		local best, bestD = DEFAULT, math.huge
		for _, e in ordered do
			local d = abs(e.r - r) + abs(e.g - g) + abs(e.b - b)
			if d < bestD then
				best, bestD = e, d
			end
		end
		return best
	end
	DT.closestBrickColor = function(c3)
		local v = getmt(c3).v
		return newBC(closest(v.x, v.y, v.z))
	end

	function BC.new(...)
		local n = select("#", ...)
		local a, b, c = ...
		if n >= 3 then
			return newBC(closest(checkNumber(a, 1, "new"), checkNumber(b, 2, "new"), checkNumber(c, 3, "new")))
		end
		if type(a) == "number" then
			return newBC(byNumber[Util.toInt(a)] or DEFAULT)
		elseif type(a) == "string" then
			return newBC(byName[a] or DEFAULT)
		elseif isC3(a) then
			local v = getmt(a).v
			return newBC(closest(v.x, v.y, v.z))
		end
		Util.badArg(1, "new", "number", a)
	end
	function BC.palette(i)
		i = checkNumber(i, 1, "palette")
		local e = palette[Util.toInt(i)]
		if not e then
			raise("palette index out of bounds")
		end
		return newBC(e)
	end
	function BC.random()
		local idx = R.rng and R.rng:NextInteger(0, 127) or math.random(0, 127)
		return newBC(palette[idx] or DEFAULT)
	end
	BC.Random = BC.random
	function BC.White()
		return newBC(byNumber[1] or DEFAULT)
	end
	function BC.Gray()
		return newBC(byNumber[194] or DEFAULT)
	end
	function BC.DarkGray()
		return newBC(byNumber[199] or DEFAULT)
	end
	function BC.Black()
		return newBC(byNumber[26] or DEFAULT)
	end
	function BC.Red()
		return newBC(byNumber[21] or DEFAULT)
	end
	function BC.Yellow()
		return newBC(byNumber[24] or DEFAULT)
	end
	function BC.Green()
		return newBC(byNumber[28] or DEFAULT)
	end
	function BC.Blue()
		return newBC(byNumber[23] or DEFAULT)
	end

	-- =================================================================================================
	--  ColorSequenceKeypoint / ColorSequence
	-- =================================================================================================
	local CSK = {}
	DT.ColorSequenceKeypoint = CSK
	local CSKindex, CSKeq
	local function CSKtostring(self)
		local m = getmt(self)
		return fmtFloat(m.t) .. " " .. tostring(m.c) .. " "
	end
	local function newCSK(t, c3)
		local u = newproxy(true)
		local mt = getmt(u)
		mt.__index = CSKindex
		mt.__newindex = DT.readonlyNewindex
		mt.__eq = CSKeq
		mt.__tostring = CSKtostring
		mt.__concat = DT.concatError
		mt.__type = "ColorSequenceKeypoint"
		mt.t = Util.f32(t)
		mt.c = c3
		return u
	end
	local function isCSK(u)
		local mt = Util.hostMeta(u)
		return mt ~= nil and mt.__index == CSKindex
	end
	DT.is.ColorSequenceKeypoint = isCSK
	function CSKindex(self, k)
		local m = getmt(self)
		if k == "Time" then
			return m.t
		elseif k == "Value" then
			return m.c
		end
		DT.badMember("ColorSequenceKeypoint", k)
	end
	Util.registerHostIndex(CSKindex)
	function CSKeq(a, b)
		if not (isCSK(a) and isCSK(b)) then
			return false
		end
		local x, y = getmt(a), getmt(b)
		return x.t == y.t and x.c == y.c
	end
	function CSK.new(time, color)
		local t = checkNumber(time, 1, "new")
		local c = color
		if not isC3(c) then
			Util.badArg(2, "new", "Color3", color)
		end
		return newCSK(t, c)
	end
	DT.make.CSK = newCSK

	local CS = {}
	DT.ColorSequence = CS
	local CSindex, CSeq
	local function CStostring(self)
		local parts = {}
		for _, kp in getmt(self).k do
			parts[#parts + 1] = tostring(kp)
		end
		return table.concat(parts, "")
	end
	local function newCS(kps)
		local u = newproxy(true)
		local mt = getmt(u)
		mt.__index = CSindex
		mt.__newindex = DT.readonlyNewindex
		mt.__eq = CSeq
		mt.__tostring = CStostring
		mt.__concat = DT.concatError
		mt.__type = "ColorSequence"
		mt.k = kps
		return u
	end
	local function isCS(u)
		local mt = Util.hostMeta(u)
		return mt ~= nil and mt.__index == CSindex
	end
	DT.is.ColorSequence = isCS
	function CSindex(self, k)
		if k == "Keypoints" then
			return table.clone(getmt(self).k)
		end
		DT.badMember("ColorSequence", k)
	end
	Util.registerHostIndex(CSindex)
	function CSeq(a, b)
		if not (isCS(a) and isCS(b)) then
			return false
		end
		local x, y = getmt(a).k, getmt(b).k
		if #x ~= #y then
			return false
		end
		for i = 1, #x do
			if x[i] ~= y[i] then
				return false
			end
		end
		return true
	end
	function DT.csKeypoints(u)
		return getmt(u).k
	end

	local function validateKeypoints(kps, tname, isKp)
		if #kps < 2 then
			raise(tname .. ": requires at least 2 keypoints")
		end
		if #kps > 20 then
			raise(tname .. ": table is too long.")
		end
		for i, kp in kps do
			if not isKp(kp) then
				raise(fmt("%s.new(): table value %d is not a %sKeypoint", tname, i, tname))
			end
		end
		local first = getmt(kps[1]).t
		local last = getmt(kps[#kps]).t
		if first ~= 0 or last ~= 1 then
			raise(tname .. " time must start at 0, and end at 1")
		end
		for i = 2, #kps do
			if getmt(kps[i]).t < getmt(kps[i - 1]).t then
				raise(tname .. ": all keypoints must be ordered by time")
			end
		end
	end
	DT.validateKeypoints = validateKeypoints

	function CS.new(a, b)
		if isC3(a) then
			if b == nil then
				return newCS({ newCSK(0, a), newCSK(1, a) })
			end
			if not isC3(b) then
				Util.badArg(2, "new", "Color3", b)
			end
			return newCS({ newCSK(0, a), newCSK(1, b) })
		end
		if type(a) == "table" then
			local kps = table.clone(a)
			validateKeypoints(kps, "ColorSequence", isCSK)
			return newCS(kps)
		end
		Util.badArg(1, "new", "Color3", a)
	end
	DT.make.CS = newCS
end
