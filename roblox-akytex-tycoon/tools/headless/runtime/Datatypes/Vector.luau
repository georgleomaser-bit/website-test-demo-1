--!nocheck
-- =====================================================================
--  Headless-Harness · Vector3 / Vector2 / Vector3int16 / Vector2int16
--
--  Vector3: Komponenten als nativer Luau-vector gespeichert (mt.v) -> float32 wie in Roblox, schnelle Arithmetik.
--  Gleiche Vector3-Werte werden INTERNIERT (schwache Tabelle, Schlüssel = nativer vector): dadurch sind gleiche
--  Vector3 rawequal und taugen wie in Roblox (dort nativer Typ) als Tabellenschlüssel.
--  type(Vector3) liefert über die Spiel-Umgebung "vector" (wie Roblox), typeof "Vector3".
--  Vector2 ist in Roblox userdata ohne Wertgleichheit als Schlüssel -> nicht interniert.
-- =====================================================================
return function(R, DT)
	local Util = R.Util
	local raise = Util.raise
	local typeof = Util.typeof
	local checkNumber = Util.checkNumber
	local fmtFloat = Util.fmtFloat
	local getmt = getmetatable
	local vcreate = vector.create
	local vmag = vector.magnitude
	local vnorm = vector.normalize
	local vdot = vector.dot
	local vcross = vector.cross
	local vfloor = vector.floor
	local vceil = vector.ceil
	local vabs = vector.abs
	local vsign = vector.sign
	local vmin = vector.min
	local vmax = vector.max
	local sqrt, abs, acos, atan2, max = math.sqrt, math.abs, math.acos, math.atan2, math.max
	local fmt = string.format

	-- =================================================================================================
	--  Vector3
	-- =================================================================================================
	local V3 = {}
	DT.Vector3 = V3
	local V3methods = {}
	local cache = setmetatable({}, { __mode = "v" })
	local V3index, V3eq, V3tostring, V3add, V3sub, V3mul, V3div, V3idiv, V3unm, V3len

	local function newV3vec(vec)
		local x, y, z = vec.x, vec.y, vec.z
		local nan = x ~= x or y ~= y or z ~= z
		if not nan then
			local u = cache[vec]
			if u then
				return u
			end
		end
		local u = newproxy(true)
		local mt = getmt(u)
		mt.__index = V3index
		mt.__newindex = DT.readonlyNewindex
		mt.__eq = V3eq
		mt.__tostring = V3tostring
		mt.__add = V3add
		mt.__sub = V3sub
		mt.__mul = V3mul
		mt.__div = V3div
		mt.__idiv = V3idiv
		mt.__unm = V3unm
		mt.__concat = DT.concatError
		mt.__lt = DT.ltError
		mt.__le = DT.leError
		mt.__len = V3len
		mt.__type = "Vector3"
		mt.v = vec
		if not nan then
			cache[vec] = u
		end
		return u
	end

	local function newV3(x, y, z)
		return newV3vec(vcreate(x, y, z))
	end
	DT.make.V3 = newV3
	DT.make.V3vec = newV3vec

	--- interne Komponenten (x, y, z) eines Vector3 (ohne Prüfung)
	local function v3xyz(u)
		local v = getmt(u).v
		return v.x, v.y, v.z
	end
	DT.v3xyz = v3xyz
	function DT.v3vec(u)
		return getmt(u).v
	end

	local function isV3(u)
		if type(u) ~= "userdata" then
			return false
		end
		local mt = getmt(u)
		return type(mt) == "table" and rawget(mt, "__index") == V3index
	end
	DT.is.Vector3 = isV3

	local function checkV3(u, n, fname)
		if isV3(u) then
			return getmt(u).v
		end
		Util.badArg(n, fname, "Vector3", u)
	end
	DT.checkV3 = checkV3

	local function selfV3(self, mname)
		if isV3(self) then
			return getmt(self).v
		end
		raise(fmt("Expected ':' not '.' calling member function %s", mname))
	end

	function V3index(self, k)
		local v = getmt(self).v
		if k == "X" or k == "x" then
			return v.x
		elseif k == "Y" or k == "y" then
			return v.y
		elseif k == "Z" or k == "z" then
			return v.z
		elseif k == "Magnitude" or k == "magnitude" then
			return vmag(v)
		elseif k == "Unit" or k == "unit" then
			return newV3vec(vnorm(v))
		end
		local m = V3methods[k]
		if m then
			return m
		end
		DT.badMember("Vector3", k)
	end
	Util.registerHostIndex(V3index)

	function V3eq(a, b)
		local ma, mb = getmt(a), getmt(b)
		if rawget(ma, "__index") ~= V3index or rawget(mb, "__index") ~= V3index then
			return false
		end
		return ma.v == mb.v
	end

	function V3tostring(self)
		local v = getmt(self).v
		return fmtFloat(v.x) .. ", " .. fmtFloat(v.y) .. ", " .. fmtFloat(v.z)
	end

	local function arithOperand(a, n)
		if isV3(a) then
			return getmt(a).v
		end
		Util.raise(fmt("invalid argument #%d (Vector3 expected, got %s)", n, typeof(a)))
	end

	function V3add(a, b)
		return newV3vec(arithOperand(a, 1) + arithOperand(b, 2))
	end
	function V3sub(a, b)
		return newV3vec(arithOperand(a, 1) - arithOperand(b, 2))
	end
	local function scalarOrVec(a, n)
		local t = type(a)
		if t == "number" then
			return a
		end
		if isV3(a) then
			return getmt(a).v
		end
		Util.raise(fmt("invalid argument #%d (Vector3 expected, got %s)", n, typeof(a)))
	end
	function V3mul(a, b)
		return newV3vec(scalarOrVec(a, 1) * scalarOrVec(b, 2))
	end
	function V3div(a, b)
		return newV3vec(scalarOrVec(a, 1) / scalarOrVec(b, 2))
	end
	function V3idiv(a, b)
		local x, y = scalarOrVec(a, 1), scalarOrVec(b, 2)
		return newV3vec(vfloor(x / y))
	end
	function V3unm(a)
		return newV3vec(-getmt(a).v)
	end
	function V3len(a)
		raise("attempt to get length of a Vector3 value")
	end

	function V3.new(x, y, z)
		return newV3vec(
			vcreate(
				x == nil and 0 or checkNumber(x, 1, "new"),
				y == nil and 0 or checkNumber(y, 2, "new"),
				z == nil and 0 or checkNumber(z, 3, "new")
			)
		)
	end
	V3.zero = newV3(0, 0, 0)
	V3.one = newV3(1, 1, 1)
	V3.xAxis = newV3(1, 0, 0)
	V3.yAxis = newV3(0, 1, 0)
	V3.zAxis = newV3(0, 0, 1)
	-- Vector3-Konstanten dauerhaft im Cache halten (schwache Werte würden sie sonst neu erzeugen)
	DT.keepAlive = { V3.zero, V3.one, V3.xAxis, V3.yAxis, V3.zAxis }

	local normalVecs = {
		[0] = newV3(1, 0, 0), -- Right
		[1] = newV3(0, 1, 0), -- Top
		[2] = newV3(0, 0, 1), -- Back
		[3] = newV3(-1, 0, 0), -- Left
		[4] = newV3(0, -1, 0), -- Bottom
		[5] = newV3(0, 0, -1), -- Front
	}
	local function enumArg(v, enumName, n, fname)
		local E = R.Enum
		local item = E and E.coerce(v, enumName)
		if item == nil then
			Util.badArg(n, fname, "Enum." .. enumName, v)
		end
		return item
	end
	function V3.fromNormalId(normal)
		return normalVecs[enumArg(normal, "NormalId", 1, "fromNormalId").Value]
	end
	V3.FromNormalId = V3.fromNormalId
	function V3.fromAxis(axis)
		local v = enumArg(axis, "Axis", 1, "fromAxis").Value
		return normalVecs[v]
	end
	V3.FromAxis = V3.fromAxis
	function V3.min(...)
		local n = select("#", ...)
		if n == 0 then
			Util.missingArg(1)
		end
		local acc = checkV3((...), 1, "min")
		for i = 2, n do
			acc = vmin(acc, checkV3((select(i, ...)), i, "min"))
		end
		return newV3vec(acc)
	end
	function V3.max(...)
		local n = select("#", ...)
		if n == 0 then
			Util.missingArg(1)
		end
		local acc = checkV3((...), 1, "max")
		for i = 2, n do
			acc = vmax(acc, checkV3((select(i, ...)), i, "max"))
		end
		return newV3vec(acc)
	end

	-- Hybrides Epsilon je Komponente (Doku: skaliert relativ zur Größe der Komponente)
	local function fuzzy(a, b, eps)
		return abs(a - b) <= eps * max(1, abs(a), abs(b))
	end
	DT.fuzzy = fuzzy

	function V3methods.Dot(self, other)
		local a = selfV3(self, "Dot")
		return vdot(a, checkV3(other, 1, "Dot"))
	end
	function V3methods.Cross(self, other)
		local a = selfV3(self, "Cross")
		return newV3vec(vcross(a, checkV3(other, 1, "Cross")))
	end
	function V3methods.Lerp(self, goal, alpha)
		local a = selfV3(self, "Lerp")
		local b = checkV3(goal, 1, "Lerp")
		local t = checkNumber(alpha, 2, "Lerp")
		return newV3vec(a + (b - a) * t)
	end
	V3methods.lerp = V3methods.Lerp
	function V3methods.FuzzyEq(self, other, epsilon)
		local a = selfV3(self, "FuzzyEq")
		local b = checkV3(other, 1, "FuzzyEq")
		local eps = epsilon == nil and 1e-5 or checkNumber(epsilon, 2, "FuzzyEq")
		return fuzzy(a.x, b.x, eps) and fuzzy(a.y, b.y, eps) and fuzzy(a.z, b.z, eps)
	end
	function V3methods.Abs(self)
		return newV3vec(vabs(selfV3(self, "Abs")))
	end
	function V3methods.Floor(self)
		return newV3vec(vfloor(selfV3(self, "Floor")))
	end
	function V3methods.Ceil(self)
		return newV3vec(vceil(selfV3(self, "Ceil")))
	end
	function V3methods.Sign(self)
		return newV3vec(vsign(selfV3(self, "Sign")))
	end
	function V3methods.Min(self, ...)
		local acc = selfV3(self, "Min")
		for i = 1, select("#", ...) do
			acc = vmin(acc, checkV3((select(i, ...)), i, "Min"))
		end
		return newV3vec(acc)
	end
	function V3methods.Max(self, ...)
		local acc = selfV3(self, "Max")
		for i = 1, select("#", ...) do
			acc = vmax(acc, checkV3((select(i, ...)), i, "Max"))
		end
		return newV3vec(acc)
	end
	function V3methods.Angle(self, other, axis)
		local a = selfV3(self, "Angle")
		local b = checkV3(other, 1, "Angle")
		local cr = vcross(a, b)
		local ang = atan2(vmag(cr), vdot(a, b))
		if axis ~= nil then
			local ax = checkV3(axis, 2, "Angle")
			if vdot(cr, ax) < 0 then
				ang = -ang
			end
		end
		return ang
	end

	-- =================================================================================================
	--  Vector2 (float32-Komponenten, kein Interning)
	-- =================================================================================================
	local V2 = {}
	DT.Vector2 = V2
	local V2methods = {}
	local V2index, V2eq, V2tostring, V2add, V2sub, V2mul, V2div, V2idiv, V2unm

	local function newV2(x, y)
		local vec = vcreate(x, y, 0)
		local u = newproxy(true)
		local mt = getmt(u)
		mt.__index = V2index
		mt.__newindex = DT.readonlyNewindex
		mt.__eq = V2eq
		mt.__tostring = V2tostring
		mt.__add = V2add
		mt.__sub = V2sub
		mt.__mul = V2mul
		mt.__div = V2div
		mt.__idiv = V2idiv
		mt.__unm = V2unm
		mt.__concat = DT.concatError
		mt.__lt = DT.ltError
		mt.__le = DT.leError
		mt.__type = "Vector2"
		mt.x = vec.x
		mt.y = vec.y
		return u
	end
	DT.make.V2 = newV2

	local function isV2(u)
		if type(u) ~= "userdata" then
			return false
		end
		local mt = getmt(u)
		return type(mt) == "table" and rawget(mt, "__index") == V2index
	end
	DT.is.Vector2 = isV2
	local function checkV2(u, n, fname)
		if isV2(u) then
			return getmt(u)
		end
		Util.badArg(n, fname, "Vector2", u)
	end
	DT.checkV2 = checkV2
	local function selfV2(self, mname)
		if isV2(self) then
			return getmt(self)
		end
		raise(fmt("Expected ':' not '.' calling member function %s", mname))
	end

	function V2index(self, k)
		local m = getmt(self)
		if k == "X" or k == "x" then
			return m.x
		elseif k == "Y" or k == "y" then
			return m.y
		elseif k == "Magnitude" or k == "magnitude" then
			return Util.f32(sqrt(m.x * m.x + m.y * m.y))
		elseif k == "Unit" or k == "unit" then
			local l = sqrt(m.x * m.x + m.y * m.y)
			return newV2(m.x / l, m.y / l)
		end
		local f = V2methods[k]
		if f then
			return f
		end
		DT.badMember("Vector2", k)
	end
	Util.registerHostIndex(V2index)
	function V2eq(a, b)
		local ma, mb = getmt(a), getmt(b)
		if rawget(ma, "__index") ~= V2index or rawget(mb, "__index") ~= V2index then
			return false
		end
		return ma.x == mb.x and ma.y == mb.y
	end
	function V2tostring(self)
		local m = getmt(self)
		return fmtFloat(m.x) .. ", " .. fmtFloat(m.y)
	end
	local function v2operand(a, n)
		if isV2(a) then
			return getmt(a)
		end
		raise(fmt("invalid argument #%d (Vector2 expected, got %s)", n, typeof(a)))
	end
	function V2add(a, b)
		local x, y = v2operand(a, 1), v2operand(b, 2)
		return newV2(x.x + y.x, x.y + y.y)
	end
	function V2sub(a, b)
		local x, y = v2operand(a, 1), v2operand(b, 2)
		return newV2(x.x - y.x, x.y - y.y)
	end
	local function v2scalar(a, n)
		if type(a) == "number" then
			return a, a
		end
		local m = v2operand(a, n)
		return m.x, m.y
	end
	function V2mul(a, b)
		local ax, ay = v2scalar(a, 1)
		local bx, by = v2scalar(b, 2)
		return newV2(ax * bx, ay * by)
	end
	function V2div(a, b)
		local ax, ay = v2scalar(a, 1)
		local bx, by = v2scalar(b, 2)
		return newV2(ax / bx, ay / by)
	end
	function V2idiv(a, b)
		local ax, ay = v2scalar(a, 1)
		local bx, by = v2scalar(b, 2)
		return newV2(math.floor(ax / bx), math.floor(ay / by))
	end
	function V2unm(a)
		local m = getmt(a)
		return newV2(-m.x, -m.y)
	end

	function V2.new(x, y)
		return newV2(x == nil and 0 or checkNumber(x, 1, "new"), y == nil and 0 or checkNumber(y, 2, "new"))
	end
	V2.zero = newV2(0, 0)
	V2.one = newV2(1, 1)
	V2.xAxis = newV2(1, 0)
	V2.yAxis = newV2(0, 1)
	function V2.min(...)
		local n = select("#", ...)
		if n == 0 then
			Util.missingArg(1)
		end
		local m = checkV2((...), 1, "min")
		local x, y = m.x, m.y
		for i = 2, n do
			local o = checkV2((select(i, ...)), i, "min")
			x, y = math.min(x, o.x), math.min(y, o.y)
		end
		return newV2(x, y)
	end
	function V2.max(...)
		local n = select("#", ...)
		if n == 0 then
			Util.missingArg(1)
		end
		local m = checkV2((...), 1, "max")
		local x, y = m.x, m.y
		for i = 2, n do
			local o = checkV2((select(i, ...)), i, "max")
			x, y = math.max(x, o.x), math.max(y, o.y)
		end
		return newV2(x, y)
	end

	function V2methods.Dot(self, other)
		local a = selfV2(self, "Dot")
		local b = checkV2(other, 1, "Dot")
		return a.x * b.x + a.y * b.y
	end
	function V2methods.Cross(self, other)
		local a = selfV2(self, "Cross")
		local b = checkV2(other, 1, "Cross")
		return a.x * b.y - a.y * b.x
	end
	function V2methods.Lerp(self, goal, alpha)
		local a = selfV2(self, "Lerp")
		local b = checkV2(goal, 1, "Lerp")
		local t = checkNumber(alpha, 2, "Lerp")
		return newV2(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
	end
	V2methods.lerp = V2methods.Lerp
	function V2methods.FuzzyEq(self, other, epsilon)
		local a = selfV2(self, "FuzzyEq")
		local b = checkV2(other, 1, "FuzzyEq")
		local eps = epsilon == nil and 1e-5 or checkNumber(epsilon, 2, "FuzzyEq")
		return fuzzy(a.x, b.x, eps) and fuzzy(a.y, b.y, eps)
	end
	function V2methods.Abs(self)
		local a = selfV2(self, "Abs")
		return newV2(abs(a.x), abs(a.y))
	end
	function V2methods.Floor(self)
		local a = selfV2(self, "Floor")
		return newV2(math.floor(a.x), math.floor(a.y))
	end
	function V2methods.Ceil(self)
		local a = selfV2(self, "Ceil")
		return newV2(math.ceil(a.x), math.ceil(a.y))
	end
	function V2methods.Sign(self)
		local a = selfV2(self, "Sign")
		return newV2(math.sign(a.x), math.sign(a.y))
	end
	function V2methods.Min(self, ...)
		local a = selfV2(self, "Min")
		local x, y = a.x, a.y
		for i = 1, select("#", ...) do
			local o = checkV2((select(i, ...)), i, "Min")
			x, y = math.min(x, o.x), math.min(y, o.y)
		end
		return newV2(x, y)
	end
	function V2methods.Max(self, ...)
		local a = selfV2(self, "Max")
		local x, y = a.x, a.y
		for i = 1, select("#", ...) do
			local o = checkV2((select(i, ...)), i, "Max")
			x, y = math.max(x, o.x), math.max(y, o.y)
		end
		return newV2(x, y)
	end
	function V2methods.Angle(self, other, isSigned)
		local a = selfV2(self, "Angle")
		local b = checkV2(other, 1, "Angle")
		local ang = atan2(a.x * b.y - a.y * b.x, a.x * b.x + a.y * b.y)
		if not isSigned then
			ang = abs(ang)
		end
		return ang
	end

	-- =================================================================================================
	--  Vector3int16 / Vector2int16 (Komponenten als int16 mit Überlauf-Wrap)
	-- =================================================================================================
	local function i16(x)
		x = Util.toInt(x)
		x = (x + 32768) % 65536 - 32768
		return x
	end

	local function makeIntVec(tname, dims)
		local T = {}
		local index, eq, tostr
		local ops = {}
		local function isT(u)
			if type(u) ~= "userdata" then
				return false
			end
			local mt = getmt(u)
			return type(mt) == "table" and rawget(mt, "__index") == index
		end
		local function new(...)
			local u = newproxy(true)
			local mt = getmt(u)
			mt.__index = index
			mt.__newindex = DT.readonlyNewindex
			mt.__eq = eq
			mt.__tostring = tostr
			mt.__add = ops.add
			mt.__sub = ops.sub
			mt.__mul = ops.mul
			mt.__div = ops.div
			mt.__unm = ops.unm
			mt.__concat = DT.concatError
			mt.__type = tname
			local a, b, c = ...
			mt.X = i16(a)
			mt.Y = i16(b)
			if dims == 3 then
				mt.Z = i16(c)
			end
			return u
		end
		function index(self, k)
			local m = getmt(self)
			if k == "X" or k == "Y" or (k == "Z" and dims == 3) then
				return m[k]
			end
			DT.badMember(tname, k)
		end
		Util.registerHostIndex(index)
		function eq(a, b)
			local ma, mb = getmt(a), getmt(b)
			if not (isT(a) and isT(b)) then
				return false
			end
			return ma.X == mb.X and ma.Y == mb.Y and (dims == 2 or ma.Z == mb.Z)
		end
		function tostr(self)
			local m = getmt(self)
			if dims == 3 then
				return m.X .. ", " .. m.Y .. ", " .. m.Z
			end
			return m.X .. ", " .. m.Y
		end
		local function operand(a, n)
			if isT(a) then
				return getmt(a)
			end
			raise(fmt("invalid argument #%d (%s expected, got %s)", n, tname, typeof(a)))
		end
		local function sc(a, n)
			if type(a) == "number" then
				return a, a, a
			end
			local m = operand(a, n)
			return m.X, m.Y, m.Z
		end
		function ops.add(a, b)
			local x, y = operand(a, 1), operand(b, 2)
			return new(x.X + y.X, x.Y + y.Y, dims == 3 and x.Z + y.Z or nil)
		end
		function ops.sub(a, b)
			local x, y = operand(a, 1), operand(b, 2)
			return new(x.X - y.X, x.Y - y.Y, dims == 3 and x.Z - y.Z or nil)
		end
		function ops.mul(a, b)
			local ax, ay, az = sc(a, 1)
			local bx, by, bz = sc(b, 2)
			return new(ax * bx, ay * by, dims == 3 and az * bz or nil)
		end
		function ops.div(a, b)
			local ax, ay, az = sc(a, 1)
			local bx, by, bz = sc(b, 2)
			return new(ax / bx, ay / by, dims == 3 and az / bz or nil)
		end
		function ops.unm(a)
			local m = getmt(a)
			return new(-m.X, -m.Y, dims == 3 and -m.Z or nil)
		end
		function T.new(x, y, z)
			x = x == nil and 0 or checkNumber(x, 1, "new")
			y = y == nil and 0 or checkNumber(y, 2, "new")
			if dims == 3 then
				z = z == nil and 0 or checkNumber(z, 3, "new")
			end
			return new(x, y, z)
		end
		DT.is[tname] = isT
		return T, new
	end
	DT.Vector3int16, DT.make.V3i = makeIntVec("Vector3int16", 3)
	DT.Vector2int16, DT.make.V2i = makeIntVec("Vector2int16", 2)
end
