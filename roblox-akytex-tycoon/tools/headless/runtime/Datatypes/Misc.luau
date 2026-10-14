--!nocheck
-- =====================================================================
--  Headless-Harness · übrige Datentypen
--  NumberRange, NumberSequence(+Keypoint), TweenInfo, Ray, Region3, Region3int16, PhysicalProperties, Axes,
--  Faces, PathWaypoint, RaycastParams, OverlapParams, RaycastResult (nur intern erzeugbar), CatalogSearchParams,
--  SharedTable (Basis) sowie einfache Stubs (FloatCurveKey, RotationCurveKey, ValueCurveKey, Path2DControlPoint,
--  SecurityCapabilities, User, InstanceHandle, Secret, DockWidgetPluginGuiInfo).
--
--  Wichtige Roblox-Eigenheit: RaycastParams/OverlapParams.FilterDescendantsInstances liefert beim Lesen eine
--  KOPIE (table.insert darauf ändert die Params nicht) – hier genauso.
-- =====================================================================
return function(R, DT)
	local Util = R.Util
	local raise = Util.raise
	local typeof = Util.typeof
	local checkNumber = Util.checkNumber
	local fmtFloat = Util.fmtFloat
	local getmt = getmetatable
	local f32 = Util.f32
	local fmt = string.format

	-- Allgemeiner Baustein: unveränderlicher Record mit Feldern (Wertgleichheit)
	local function record(tname, fieldNames, tostr)
		local index
		local function isT(u)
			local mt = Util.hostMeta(u)
			return mt ~= nil and mt.__index == index
		end
		local function eq(a, b)
			if not (isT(a) and isT(b)) then
				return false
			end
			local x, y = getmt(a).f, getmt(b).f
			for _, k in fieldNames do
				if x[k] ~= y[k] then
					return false
				end
			end
			return true
		end
		function index(self, k)
			local f = getmt(self).f
			local v = f[k]
			if v ~= nil or table.find(fieldNames, k) then
				return v
			end
			DT.badMember(tname, k)
		end
		Util.registerHostIndex(index)
		local tostrFn = tostr
			or function(self)
				local parts = {}
				for _, k in fieldNames do
					parts[#parts + 1] = tostring(getmt(self).f[k])
				end
				return table.concat(parts, ", ")
			end
		local function new(fields)
			local u, mt = DT.newHost(index, tname, tostrFn, eq)
			mt.f = fields
			return u
		end
		DT.is[tname] = isT
		return new, isT
	end
	DT.record = record

	-- Allgemeiner Baustein: veränderliches Parameter-Objekt (RaycastParams usw.)
	-- spec[Feld] = { default = Wert oder function() -> Wert, check = function(v) -> v (raise bei Fehler), copy = bool }
	local function mutable(tname, spec, methods)
		local index, newindex
		local function isT(u)
			local mt = Util.hostMeta(u)
			return mt ~= nil and mt.__index == index
		end
		function index(self, k)
			local m = getmt(self)
			local s = spec[k]
			if s then
				local v = m.f[k]
				if s.copy and type(v) == "table" then
					return table.clone(v)
				end
				return v
			end
			local fn = methods and methods[k]
			if fn then
				return fn
			end
			DT.badMember(tname, k)
		end
		Util.registerHostIndex(index)
		function newindex(self, k, v)
			local s = spec[k]
			if not s then
				DT.badMember(tname, k)
			end
			if s.readonly then
				raise(k .. " cannot be assigned to")
			end
			getmt(self).f[k] = s.check(v, k)
		end
		local function tostrFn()
			return tname
		end
		local function new()
			local u, mt = DT.newHost(index, tname, tostrFn, nil)
			mt.__newindex = newindex
			local f = {}
			for k, s in spec do
				local d = s.default
				if type(d) == "function" then
					d = d()
				end
				f[k] = d
			end
			mt.f = f
			return u
		end
		DT.is[tname] = isT
		return new, isT
	end
	DT.mutable = mutable

	-- Prüf-Helfer für Property-Zuweisungen an Datentyp-Felder
	local function chkNum(v, k)
		if type(v) == "number" then
			return v
		end
		local x = type(v) == "string" and tonumber(v)
		if x then
			return x
		end
		raise(fmt("invalid argument #3 (number expected, got %s)", typeof(v)))
	end
	local function chkBool(v, k)
		if type(v) ~= "boolean" then
			raise(fmt("invalid argument #3 (boolean expected, got %s)", typeof(v)))
		end
		return v
	end
	local function chkStr(v, k)
		if type(v) == "number" then
			return tostring(v)
		end
		if type(v) ~= "string" then
			raise(fmt("invalid argument #3 (string expected, got %s)", typeof(v)))
		end
		return v
	end
	local function chkEnum(enumName)
		return function(v, k)
			local it = R.Enum.coerce(v, enumName)
			if not it then
				raise(fmt("invalid argument #3 (Enum.%s expected, got %s)", enumName, typeof(v)))
			end
			return it
		end
	end
	local function chkInstances(v, k)
		if type(v) ~= "table" then
			raise(fmt("invalid argument #3 (table expected, got %s)", typeof(v)))
		end
		local out = {}
		for i, x in ipairs(v) do
			if typeof(x) ~= "Instance" then
				raise("Unable to cast value to Objects")
			end
			out[i] = x
		end
		return out
	end
	DT.chk = { num = chkNum, bool = chkBool, str = chkStr, enum = chkEnum, instances = chkInstances }

	-- =================================================================================================
	--  NumberRange
	-- =================================================================================================
	local NR = {}
	DT.NumberRange = NR
	local newNRrec = record("NumberRange", { "Min", "Max" }, function(self)
		local f = getmt(self).f
		return fmtFloat(f.Min) .. " " .. fmtFloat(f.Max) .. " "
	end)
	local function newNR(a, b)
		return newNRrec({ Min = f32(a), Max = f32(b) })
	end
	DT.make.NR = newNR
	function NR.new(a, b)
		a = checkNumber(a, 1, "new")
		if b == nil then
			return newNR(a, a)
		end
		b = checkNumber(b, 2, "new")
		if a > b then
			raise("NumberRange: invalid range (min must be less than or equal to max)")
		end
		return newNR(a, b)
	end

	-- =================================================================================================
	--  NumberSequenceKeypoint / NumberSequence
	-- =================================================================================================
	local NSK = {}
	DT.NumberSequenceKeypoint = NSK
	local NSKindex
	local function isNSK(u)
		local mt = Util.hostMeta(u)
		return mt ~= nil and mt.__index == NSKindex
	end
	DT.is.NumberSequenceKeypoint = isNSK
	function NSKindex(self, k)
		local m = getmt(self)
		if k == "Time" then
			return m.t
		elseif k == "Value" then
			return m.v
		elseif k == "Envelope" then
			return m.e
		end
		DT.badMember("NumberSequenceKeypoint", k)
	end
	Util.registerHostIndex(NSKindex)
	local function NSKtostring(self)
		local m = getmt(self)
		return fmtFloat(m.t) .. " " .. fmtFloat(m.v) .. " " .. fmtFloat(m.e) .. " "
	end
	local function NSKeq(a, b)
		if not (isNSK(a) and isNSK(b)) then
			return false
		end
		local x, y = getmt(a), getmt(b)
		return x.t == y.t and x.v == y.v and x.e == y.e
	end
	local function newNSK(t, v, e)
		local u, mt = DT.newHost(NSKindex, "NumberSequenceKeypoint", NSKtostring, NSKeq)
		mt.t, mt.v, mt.e = f32(t), f32(v), f32(e or 0)
		return u
	end
	DT.make.NSK = newNSK
	function NSK.new(time, value, envelope)
		return newNSK(
			checkNumber(time, 1, "new"),
			checkNumber(value, 2, "new"),
			envelope == nil and 0 or checkNumber(envelope, 3, "new")
		)
	end

	local NS = {}
	DT.NumberSequence = NS
	local NSindex
	local function isNS(u)
		local mt = Util.hostMeta(u)
		return mt ~= nil and mt.__index == NSindex
	end
	DT.is.NumberSequence = isNS
	function NSindex(self, k)
		if k == "Keypoints" then
			return table.clone(getmt(self).k)
		end
		DT.badMember("NumberSequence", k)
	end
	Util.registerHostIndex(NSindex)
	local function NStostring(self)
		local parts = {}
		for _, kp in getmt(self).k do
			parts[#parts + 1] = tostring(kp)
		end
		return table.concat(parts, "")
	end
	local function NSeq(a, b)
		if not (isNS(a) and isNS(b)) then
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
	local function newNS(kps)
		local u, mt = DT.newHost(NSindex, "NumberSequence", NStostring, NSeq)
		mt.k = kps
		return u
	end
	DT.make.NS = newNS
	function DT.nsKeypoints(u)
		return getmt(u).k
	end
	function NS.new(a, b)
		if type(a) == "number" or (type(a) == "string" and tonumber(a)) then
			a = checkNumber(a, 1, "new")
			if b == nil then
				return newNS({ newNSK(0, a, 0), newNSK(1, a, 0) })
			end
			b = checkNumber(b, 2, "new")
			return newNS({ newNSK(0, a, 0), newNSK(1, b, 0) })
		end
		if type(a) == "table" then
			local kps = table.clone(a)
			DT.validateKeypoints(kps, "NumberSequence", isNSK)
			return newNS(kps)
		end
		Util.badArg(1, "new", "number", a)
	end
	--- Wert einer NumberSequence zur Zeit t (für Harness-Ausgaben)
	function DT.nsEval(ns, t)
		local k = getmt(ns).k
		for i = 1, #k - 1 do
			local a, b = getmt(k[i]), getmt(k[i + 1])
			if t >= a.t and t <= b.t then
				local u = (b.t - a.t) == 0 and 0 or (t - a.t) / (b.t - a.t)
				return a.v + (b.v - a.v) * u
			end
		end
		return getmt(k[#k]).v
	end

	-- =================================================================================================
	--  TweenInfo
	-- =================================================================================================
	local TI = {}
	DT.TweenInfo = TI
	local newTIrec = record(
		"TweenInfo",
		{ "Time", "EasingStyle", "EasingDirection", "RepeatCount", "Reverses", "DelayTime" },
		function(self)
			local f = getmt(self).f
			return fmt(
				"Time:%s DelayTime:%s RepeatCount:%d Reverses:%s EasingDirection:%s EasingStyle:%s",
				fmtFloat(f.Time),
				fmtFloat(f.DelayTime),
				f.RepeatCount,
				f.Reverses and "True" or "False",
				f.EasingDirection.Name,
				f.EasingStyle.Name
			)
		end
	)
	function TI.new(time, easingStyle, easingDirection, repeatCount, reverses, delayTime)
		local E = R.Enum
		local style = E.item("EasingStyle", "Quad")
		local dir = E.item("EasingDirection", "Out")
		if easingStyle ~= nil then
			style = E.coerce(easingStyle, "EasingStyle")
			if not style then
				Util.badArg(2, "new", "Enum.EasingStyle", easingStyle)
			end
		end
		if easingDirection ~= nil then
			dir = E.coerce(easingDirection, "EasingDirection")
			if not dir then
				Util.badArg(3, "new", "Enum.EasingDirection", easingDirection)
			end
		end
		if reverses ~= nil and type(reverses) ~= "boolean" then
			Util.badArg(5, "new", "boolean", reverses)
		end
		return newTIrec({
			Time = time == nil and 1 or checkNumber(time, 1, "new"),
			EasingStyle = style,
			EasingDirection = dir,
			RepeatCount = repeatCount == nil and 0 or Util.toInt(checkNumber(repeatCount, 4, "new")),
			Reverses = reverses == true,
			DelayTime = delayTime == nil and 0 or checkNumber(delayTime, 6, "new"),
		})
	end
	function DT.tweenInfoFields(ti)
		return getmt(ti).f
	end

	-- =================================================================================================
	--  Ray
	-- =================================================================================================
	local RY = {}
	DT.Ray = RY
	local RYindex
	local rayMethods = {}
	local function isRY(u)
		local mt = Util.hostMeta(u)
		return mt ~= nil and mt.__index == RYindex
	end
	DT.is.Ray = isRY
	local function RYtostring(self)
		local m = getmt(self)
		return "{" .. tostring(m.o) .. "}, {" .. tostring(m.d) .. "}"
	end
	local function RYeq(a, b)
		if not (isRY(a) and isRY(b)) then
			return false
		end
		local x, y = getmt(a), getmt(b)
		return x.o == y.o and x.d == y.d
	end
	local function newRY(o, d)
		local u, mt = DT.newHost(RYindex, "Ray", RYtostring, RYeq)
		mt.o, mt.d = o, d
		return u
	end
	DT.make.RY = newRY
	function RYindex(self, k)
		local m = getmt(self)
		if k == "Origin" then
			return m.o
		elseif k == "Direction" then
			return m.d
		elseif k == "Unit" then
			return newRY(m.o, m.d.Unit)
		end
		local f = rayMethods[k]
		if f then
			return f
		end
		DT.badMember("Ray", k)
	end
	Util.registerHostIndex(RYindex)
	local function closestT(m, p)
		local o, d = DT.v3vec(m.o), DT.v3vec(m.d)
		local dd = vector.dot(d, d)
		if dd == 0 then
			return o
		end
		local t = vector.dot(p - o, d) / dd
		if t < 0 then
			t = 0
		end
		return o + d * t
	end
	function rayMethods.ClosestPoint(self, point)
		if not isRY(self) then
			raise("Expected ':' not '.' calling member function ClosestPoint")
		end
		local p = DT.checkV3(point, 1, "ClosestPoint")
		return DT.make.V3vec(closestT(getmt(self), p))
	end
	function rayMethods.Distance(self, point)
		if not isRY(self) then
			raise("Expected ':' not '.' calling member function Distance")
		end
		local p = DT.checkV3(point, 1, "Distance")
		return vector.magnitude(closestT(getmt(self), p) - p)
	end
	function RY.new(origin, direction)
		DT.checkV3(origin, 1, "new")
		DT.checkV3(direction, 2, "new")
		return newRY(origin, direction)
	end

	-- =================================================================================================
	--  Region3 / Region3int16
	-- =================================================================================================
	local R3 = {}
	DT.Region3 = R3
	local R3index
	local r3methods = {}
	local function isR3(u)
		local mt = Util.hostMeta(u)
		return mt ~= nil and mt.__index == R3index
	end
	DT.is.Region3 = isR3
	local function R3tostring(self)
		local m = getmt(self)
		return tostring(
			DT.make.CF((m.mn.x + m.mx.x) / 2, (m.mn.y + m.mx.y) / 2, (m.mn.z + m.mx.z) / 2, 1, 0, 0, 0, 1, 0, 0, 0, 1)
		) .. "; " .. tostring(DT.make.V3vec(m.mx - m.mn))
	end
	local function R3eq(a, b)
		if not (isR3(a) and isR3(b)) then
			return false
		end
		local x, y = getmt(a), getmt(b)
		return x.mn == y.mn and x.mx == y.mx
	end
	local function newR3(minv, maxv)
		local u, mt = DT.newHost(R3index, "Region3", R3tostring, R3eq)
		mt.mn, mt.mx = minv, maxv
		return u
	end
	function R3index(self, k)
		local m = getmt(self)
		if k == "CFrame" then
			local c = (m.mn + m.mx) / 2
			return DT.make.CF(c.x, c.y, c.z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
		elseif k == "Size" then
			return DT.make.V3vec(m.mx - m.mn)
		end
		local f = r3methods[k]
		if f then
			return f
		end
		DT.badMember("Region3", k)
	end
	Util.registerHostIndex(R3index)
	function r3methods.ExpandToGrid(self, res)
		if not isR3(self) then
			raise("Expected ':' not '.' calling member function ExpandToGrid")
		end
		res = checkNumber(res, 1, "ExpandToGrid")
		local m = getmt(self)
		local mn = vector.floor(m.mn / res) * res
		local mx = vector.ceil(m.mx / res) * res
		return newR3(mn, mx)
	end
	function R3.new(minv, maxv)
		local a = DT.checkV3(minv, 1, "new")
		local b = DT.checkV3(maxv, 2, "new")
		return newR3(a, b)
	end
	function DT.region3MinMax(r)
		local m = getmt(r)
		return m.mn, m.mx
	end

	local R3i = {}
	DT.Region3int16 = R3i
	local newR3irec = record("Region3int16", { "Min", "Max" })
	function R3i.new(minv, maxv)
		if not DT.is.Vector3int16(minv) then
			Util.badArg(1, "new", "Vector3int16", minv)
		end
		if not DT.is.Vector3int16(maxv) then
			Util.badArg(2, "new", "Vector3int16", maxv)
		end
		return newR3irec({ Min = minv, Max = maxv })
	end

	-- =================================================================================================
	--  PhysicalProperties
	-- =================================================================================================
	-- Dichte, Reibung, Elastizität, Reibungs-Gewicht, Elastizitäts-Gewicht je Material (Roblox-Standardwerte)
	local MAT = {
		Plastic = { 0.7, 0.3, 0.5, 1, 1 },
		SmoothPlastic = { 0.7, 0.2, 0.5, 1, 1 },
		Neon = { 0.7, 0.3, 0.2, 1, 1 },
		Wood = { 0.35, 0.48, 0.2, 1, 1 },
		WoodPlanks = { 0.35, 0.48, 0.2, 1, 1 },
		Marble = { 2.563, 0.2, 0.17, 1, 1 },
		Slate = { 2.691, 0.4, 0.2, 1, 1 },
		Concrete = { 2.403, 0.7, 0.2, 0.3, 1 },
		Granite = { 2.691, 0.4, 0.2, 1, 1 },
		Brick = { 1.922, 0.8, 0.15, 0.3, 1 },
		Pebble = { 2.403, 0.4, 0.17, 1, 1 },
		Cobblestone = { 2.691, 0.5, 0.17, 1, 1 },
		CorrodedMetal = { 7.85, 0.7, 0.2, 1, 1 },
		DiamondPlate = { 7.85, 0.35, 0.25, 1, 1 },
		Foil = { 2.7, 0.4, 0.25, 1, 1 },
		Metal = { 7.85, 0.4, 0.25, 1, 1 },
		Grass = { 0.9, 0.4, 0.1, 1, 1.5 },
		Sand = { 1.6, 0.5, 0.05, 5, 2.5 },
		Fabric = { 0.7, 0.35, 0.05, 1, 1 },
		Ice = { 0.919, 0.02, 0.15, 3, 1 },
		Glass = { 2.4, 0.25, 0.2, 1, 1 },
		ForceField = { 2.4, 0.25, 0.2, 1, 1 },
		Air = { 0.01, 0.01, 0.01, 1, 1 },
		Water = { 1, 0, 0, 1, 1 },
		Asphalt = { 2.36, 0.8, 0.2, 0.3, 1 },
		Basalt = { 2.691, 0.7, 0.15, 0.3, 1 },
		Rock = { 2.691, 0.5, 0.17, 1, 1 },
		Ground = { 0.9, 0.45, 0.1, 1, 1 },
		Mud = { 0.9, 0.3, 0.07, 3, 4 },
		Snow = { 0.9, 0.3, 0.03, 3, 4 },
		Salt = { 2.16, 0.5, 0.05, 1, 1 },
		Limestone = { 2.691, 0.5, 0.15, 1, 1 },
		Sandstone = { 2.691, 0.5, 0.15, 5, 1 },
		Glacier = { 0.919, 0.05, 0.15, 2, 1 },
		LeafyGrass = { 0.9, 0.4, 0.1, 2, 2 },
		CrackedLava = { 2.691, 0.65, 0.15, 1, 1 },
		Cardboard = { 0.7, 0.5, 0.05, 1, 1 },
		Carpet = { 1.1, 0.4, 0.25, 1.1, 1 },
		CeramicTiles = { 2.403, 0.51, 0.2, 1, 1 },
		ClayRoofTiles = { 2, 0.51, 0.2, 1, 1 },
		Leather = { 0.86, 0.35, 0.25, 1, 1 },
		Plaster = { 0.75, 0.6, 0.2, 1, 1 },
		RoofShingles = { 2.36, 0.8, 0.2, 0.3, 1 },
		Rubber = { 1.3, 1.5, 0.95, 3, 2 },
	}
	DT.materialPhysics = MAT
	local PP = {}
	DT.PhysicalProperties = PP
	local newPPrec = record(
		"PhysicalProperties",
		{ "Density", "Friction", "Elasticity", "FrictionWeight", "ElasticityWeight", "AcousticAbsorption" },
		function(self)
			local f = getmt(self).f
			return fmt(
				"%s, %s, %s, %s, %s",
				fmtFloat(f.Density),
				fmtFloat(f.Friction),
				fmtFloat(f.Elasticity),
				fmtFloat(f.FrictionWeight),
				fmtFloat(f.ElasticityWeight)
			)
		end
	)
	local function newPP(d, f, e, fw, ew, aa)
		return newPPrec({
			Density = f32(math.max(d, 0.0001)),
			Friction = f32(f),
			Elasticity = f32(e),
			FrictionWeight = f32(fw or 1),
			ElasticityWeight = f32(ew or 1),
			AcousticAbsorption = f32(aa or 1),
		})
	end
	DT.make.PP = newPP
	function DT.materialDensity(materialName)
		local m = MAT[materialName] or MAT.Plastic
		return m[1]
	end
	function PP.new(a, b, c, d, e, g)
		if typeof(a) == "EnumItem" then
			local it = R.Enum.coerce(a, "Material")
			if not it then
				Util.badArg(1, "new", "Enum.Material", a)
			end
			local m = MAT[it.Name] or MAT.Plastic
			return newPP(m[1], m[2], m[3], m[4], m[5], 1)
		end
		a = checkNumber(a, 1, "new")
		b = checkNumber(b, 2, "new")
		c = checkNumber(c, 3, "new")
		d = d == nil and 1 or checkNumber(d, 4, "new")
		e = e == nil and 1 or checkNumber(e, 5, "new")
		g = g == nil and 1 or checkNumber(g, 6, "new")
		return newPP(a, b, c, d, e, g)
	end

	-- =================================================================================================
	--  Axes / Faces
	-- =================================================================================================
	local function flagsType(tname, names, enumNames)
		local T = {}
		local newRec = record(tname, names, function(self)
			local f = getmt(self).f
			local parts = {}
			for _, k in names do
				if f[k] then
					parts[#parts + 1] = k
				end
			end
			return table.concat(parts, ", ")
		end)
		function T.new(...)
			local f = {}
			for _, k in names do
				f[k] = false
			end
			for i = 1, select("#", ...) do
				local v = select(i, ...)
				local ok = false
				for _, en in enumNames do
					local it = R.Enum.coerce(v, en)
					if it and typeof(v) == "EnumItem" then
						local map = DT.flagMap[tname][en][it.Name]
						if map then
							for _, k in map do
								f[k] = true
							end
							ok = true
							break
						end
					end
				end
				if not ok then
					Util.badArg(i, "new", "EnumItem", v)
				end
			end
			return newRec(f)
		end
		return T, newRec
	end
	DT.flagMap = {
		Axes = {
			Axis = { X = { "X", "Right", "Left" }, Y = { "Y", "Top", "Bottom" }, Z = { "Z", "Back", "Front" } },
			NormalId = {
				Right = { "X", "Right" },
				Left = { "X", "Left" },
				Top = { "Y", "Top" },
				Bottom = { "Y", "Bottom" },
				Back = { "Z", "Back" },
				Front = { "Z", "Front" },
			},
		},
		Faces = {
			NormalId = {
				Right = { "Right" },
				Left = { "Left" },
				Top = { "Top" },
				Bottom = { "Bottom" },
				Back = { "Back" },
				Front = { "Front" },
			},
		},
	}
	DT.Axes, DT.make.AXrec = flagsType(
		"Axes",
		{ "X", "Y", "Z", "Top", "Bottom", "Left", "Right", "Back", "Front" },
		{ "Axis", "NormalId" }
	)
	DT.Faces, DT.make.FArec = flagsType("Faces", { "Top", "Bottom", "Left", "Right", "Back", "Front" }, { "NormalId" })
	-- Bitmasken aus api_data (rbx_types): Faces Right=1,Top=2,Back=4,Left=8,Bottom=16,Front=32; Axes X=1,Y=2,Z=4
	function DT.make.FAbits(bits)
		local function b(n)
			return bit32.band(bits, n) ~= 0
		end
		return DT.make.FArec({ Right = b(1), Top = b(2), Back = b(4), Left = b(8), Bottom = b(16), Front = b(32) })
	end
	function DT.make.AXbits(bits)
		local x, y, z = bit32.band(bits, 1) ~= 0, bit32.band(bits, 2) ~= 0, bit32.band(bits, 4) ~= 0
		return DT.make.AXrec({ X = x, Y = y, Z = z, Right = x, Left = x, Top = y, Bottom = y, Back = z, Front = z })
	end

	-- =================================================================================================
	--  PathWaypoint
	-- =================================================================================================
	local PW = {}
	DT.PathWaypoint = PW
	local newPWrec = record("PathWaypoint", { "Position", "Action", "Label" })
	function PW.new(position, action, label)
		DT.checkV3(position, 1, "new")
		local act = R.Enum.item("PathWaypointAction", "Walk")
		if action ~= nil then
			act = R.Enum.coerce(action, "PathWaypointAction")
			if not act then
				Util.badArg(2, "new", "Enum.PathWaypointAction", action)
			end
		end
		return newPWrec({
			Position = position,
			Action = act,
			Label = label == nil and "" or Util.checkString(label, 3, "new"),
		})
	end
	DT.make.PW = function(position, actionName, label)
		return newPWrec({
			Position = position,
			Action = R.Enum.item("PathWaypointAction", actionName or "Walk"),
			Label = label or "",
		})
	end

	-- =================================================================================================
	--  RaycastParams / OverlapParams / CatalogSearchParams
	-- =================================================================================================
	local paramMethods = {}
	function paramMethods.AddToFilter(self, instances)
		local mt = Util.hostMeta(self)
		if not mt or (mt.__type ~= "RaycastParams" and mt.__type ~= "OverlapParams") then
			raise("Expected ':' not '.' calling member function AddToFilter")
		end
		local list = mt.f.FilterDescendantsInstances
		if typeof(instances) == "Instance" then
			list[#list + 1] = instances
		elseif type(instances) == "table" then
			for _, x in ipairs(instances) do
				if typeof(x) ~= "Instance" then
					raise("Unable to cast value to Objects")
				end
				list[#list + 1] = x
			end
		else
			Util.badArg(1, "AddToFilter", "Instance", instances)
		end
	end
	local filterTypeDefault = function()
		return R.Enum.item("RaycastFilterType", "Exclude")
	end
	local RP = {}
	DT.RaycastParams = RP
	local newRP = mutable("RaycastParams", {
		FilterDescendantsInstances = {
			default = function()
				return {}
			end,
			check = chkInstances,
			copy = true,
		},
		ExcludeInstances = {
			default = function()
				return {}
			end,
			check = chkInstances,
			copy = true,
		},
		IncludeInstances = {
			default = function()
				return {}
			end,
			check = chkInstances,
			copy = true,
		},
		FilterType = { default = filterTypeDefault, check = chkEnum("RaycastFilterType") },
		IgnoreWater = { default = false, check = chkBool },
		CollisionGroup = { default = "Default", check = chkStr },
		RespectCanCollide = { default = false, check = chkBool },
		BruteForceAllSlow = { default = false, check = chkBool },
	}, paramMethods)
	function RP.new()
		return newRP()
	end
	local OP = {}
	DT.OverlapParams = OP
	local newOP = mutable("OverlapParams", {
		FilterDescendantsInstances = {
			default = function()
				return {}
			end,
			check = chkInstances,
			copy = true,
		},
		ExcludeInstances = {
			default = function()
				return {}
			end,
			check = chkInstances,
			copy = true,
		},
		IncludeInstances = {
			default = function()
				return {}
			end,
			check = chkInstances,
			copy = true,
		},
		FilterType = { default = filterTypeDefault, check = chkEnum("RaycastFilterType") },
		MaxParts = {
			default = 0,
			check = function(v, k)
				return Util.toInt(chkNum(v, k))
			end,
		},
		CollisionGroup = { default = "Default", check = chkStr },
		RespectCanCollide = { default = false, check = chkBool },
		BruteForceAllSlow = { default = false, check = chkBool },
		Tolerance = { default = 0, check = chkNum },
	}, paramMethods)
	function OP.new()
		return newOP()
	end
	--- interne Felder (ohne Kopie) für Raycast-Implementierungen
	function DT.paramFields(p)
		return getmt(p).f
	end

	local CSP = {}
	DT.CatalogSearchParams = CSP
	local newCSP = mutable("CatalogSearchParams", {
		SearchKeyword = { default = "", check = chkStr },
		MinPrice = { default = 0, check = chkNum },
		MaxPrice = { default = 2147483647, check = chkNum },
		CreatorName = { default = "", check = chkStr },
		CreatorId = { default = 0, check = chkNum },
		IncludeOffSale = { default = false, check = chkBool },
		Limit = { default = 30, check = chkNum },
		AssetTypes = {
			default = function()
				return {}
			end,
			check = function(v)
				return table.clone(v)
			end,
			copy = true,
		},
		BundleTypes = {
			default = function()
				return {}
			end,
			check = function(v)
				return table.clone(v)
			end,
			copy = true,
		},
		CategoryFilter = {
			default = function()
				return R.Enum.item("CatalogCategoryFilter", "None")
			end,
			check = chkEnum("CatalogCategoryFilter"),
		},
		SortType = {
			default = function()
				return R.Enum.item("CatalogSortType", "Relevance")
			end,
			check = chkEnum("CatalogSortType"),
		},
		SortAggregation = {
			default = function()
				return R.Enum.item("CatalogSortAggregation", "AllTime")
			end,
			check = chkEnum("CatalogSortAggregation"),
		},
		SalesTypeFilter = {
			default = function()
				return R.Enum.item("SalesTypeFilter", "All")
			end,
			check = chkEnum("SalesTypeFilter"),
		},
		CreatorType = {
			default = function()
				return R.Enum.item("CreatorTypeFilter", "All")
			end,
			check = chkEnum("CreatorTypeFilter"),
		},
	})
	function CSP.new()
		return newCSP()
	end

	-- =================================================================================================
	--  RaycastResult (nicht per Skript konstruierbar; Harness erzeugt es in workspace:Raycast)
	-- =================================================================================================
	local newRRrec = record(
		"RaycastResult",
		{ "Instance", "Position", "Normal", "Material", "Distance" },
		function(self)
			return "RaycastResult{"
				.. tostring(getmt(self).f.Instance)
				.. " @ "
				.. tostring(getmt(self).f.Position)
				.. "}"
		end
	)
	DT.make.RaycastResult = function(inst, position, normal, material, distance)
		return newRRrec({
			Instance = inst,
			Position = position,
			Normal = normal,
			Material = material,
			Distance = distance,
		})
	end

	-- =================================================================================================
	--  SharedTable (Basis: Schlüssel string|number, Werte primitiv/SharedTable/userdata; Iteration)
	-- =================================================================================================
	local ST = {}
	DT.SharedTable = ST
	local STindex, STnewindex, STiter
	local function isST(u)
		local mt = Util.hostMeta(u)
		return mt ~= nil and mt.__index == STindex
	end
	DT.is.SharedTable = isST
	local function checkKey(k)
		local t = type(k)
		if t ~= "string" and t ~= "number" then
			raise("invalid key type " .. typeof(k) .. " for SharedTable (expected string or number)")
		end
	end
	local function checkVal(v)
		local t = type(v)
		if t == "table" or t == "function" or t == "thread" then
			raise("invalid value type " .. typeof(v) .. " for SharedTable")
		end
	end
	local function newST(src)
		local u, mt = DT.newHost(STindex, "SharedTable", function()
			return "SharedTable"
		end, nil)
		mt.__newindex = STnewindex
		mt.__iter = STiter
		mt.__len = function(self)
			return #getmt(self).t
		end
		mt.t = {}
		mt.frozen = false
		if src then
			for k, v in src do
				checkKey(k)
				if type(v) == "table" then
					v = newST(v)
				end
				checkVal(v)
				mt.t[k] = v
			end
		end
		return u
	end
	function STindex(self, k)
		checkKey(k)
		return getmt(self).t[k]
	end
	Util.registerHostIndex(STindex)
	function STnewindex(self, k, v)
		local m = getmt(self)
		if m.frozen then
			raise("attempt to modify a frozen SharedTable")
		end
		checkKey(k)
		if type(v) == "table" then
			v = newST(v)
		end
		checkVal(v)
		m.t[k] = v
	end
	function STiter(self)
		return next, getmt(self).t
	end
	function ST.new(t)
		if t ~= nil and type(t) ~= "table" then
			Util.badArg(1, "new", "table", t)
		end
		return newST(t)
	end
	local function stCheck(st, n, fname)
		if not isST(st) then
			Util.badArg(n, fname, "SharedTable", st)
		end
		return getmt(st)
	end
	function ST.clear(st)
		local m = stCheck(st, 1, "clear")
		if m.frozen then
			raise("attempt to modify a frozen SharedTable")
		end
		table.clear(m.t)
	end
	local function cloneST(st, deep, freeze)
		local m = getmt(st)
		local out = newST(nil)
		local om = getmt(out)
		for k, v in m.t do
			if deep and isST(v) then
				v = cloneST(v, true, freeze)
			end
			om.t[k] = v
		end
		om.frozen = freeze
		return out
	end
	function ST.clone(st, deep)
		stCheck(st, 1, "clone")
		return cloneST(st, deep == true, false)
	end
	function ST.cloneAndFreeze(st, deep)
		stCheck(st, 1, "cloneAndFreeze")
		return cloneST(st, deep == true, true)
	end
	function ST.increment(st, key, delta)
		local m = stCheck(st, 1, "increment")
		checkKey(key)
		delta = checkNumber(delta, 3, "increment")
		local old = m.t[key] or 0
		if type(old) ~= "number" then
			raise("SharedTable.increment: value is not a number")
		end
		m.t[key] = old + delta
		return old
	end
	function ST.isFrozen(st)
		return stCheck(st, 1, "isFrozen").frozen
	end
	function ST.size(st)
		local m = stCheck(st, 1, "size")
		local n = 0
		for _ in m.t do
			n += 1
		end
		return n
	end
	function ST.update(st, key, fn)
		local m = stCheck(st, 1, "update")
		checkKey(key)
		if type(fn) ~= "function" then
			Util.badArg(3, "update", "function", fn)
		end
		local v = fn(m.t[key])
		if type(v) == "table" then
			v = newST(v)
		end
		checkVal(v)
		m.t[key] = v
	end

	-- =================================================================================================
	--  einfache Stubs (selten genutzt; Konstruktoren vorhanden, damit Spiel-Code nicht an nil scheitert)
	-- =================================================================================================
	local function curveKey(tname)
		local T = {}
		local newRec = record(tname, { "Time", "Value", "Interpolation", "LeftTangent", "RightTangent" })
		function T.new(time, value, interpolation)
			local it = R.Enum.coerce(interpolation, "KeyInterpolationMode")
				or R.Enum.item("KeyInterpolationMode", "Linear")
			return newRec({
				Time = checkNumber(time, 1, "new"),
				Value = value,
				Interpolation = it,
				LeftTangent = 0,
				RightTangent = 0,
			})
		end
		return T
	end
	DT.FloatCurveKey = curveKey("FloatCurveKey")
	DT.RotationCurveKey = curveKey("RotationCurveKey")
	DT.ValueCurveKey = curveKey("ValueCurveKey")

	local P2D = {}
	DT.Path2DControlPoint = P2D
	local newP2D = record("Path2DControlPoint", { "Position", "LeftTangent", "RightTangent" })
	function P2D.new(pos, l, r)
		local z = DT.make.U2(0, 0, 0, 0)
		return newP2D({ Position = pos or z, LeftTangent = l or z, RightTangent = r or z })
	end

	local SC = {}
	DT.SecurityCapabilities = SC
	local newSC = record("SecurityCapabilities", { "List" })
	function SC.new(...)
		return newSC({ List = { ... } })
	end
	function SC.fromCurrent()
		return newSC({ List = {} })
	end

	local US = {}
	DT.User = US
	local newUS = record("User", { "Id", "DomainType", "DomainId" })
	function US.fromId(id)
		return newUS({ Id = checkNumber(id, 1, "fromId"), DomainType = nil, DomainId = 0 })
	end
	function US.fromString(s)
		return newUS({ Id = tonumber(s) or 0, DomainType = nil, DomainId = 0 })
	end

	local IH = {}
	DT.InstanceHandle = IH
	local newIH = record("InstanceHandle", { "Instance" })
	function IH.new(inst)
		return newIH({ Instance = inst })
	end

	DT.Secret = {}

	local DW = {}
	DT.DockWidgetPluginGuiInfo = DW
	local newDW = record(
		"DockWidgetPluginGuiInfo",
		{ "InitialEnabled", "FloatingXSize", "FloatingYSize", "MinWidth", "MinHeight" }
	)
	function DW.new(_state, enabled, _override, fx, fy, mw, mh)
		return newDW({
			InitialEnabled = enabled == true,
			FloatingXSize = fx or 0,
			FloatingYSize = fy or 0,
			MinWidth = mw or 0,
			MinHeight = mh or 0,
		})
	end
end
