--!nocheck
-- =====================================================================
--  Headless-Harness · CFrame
--  Datenablage: mt.d = {x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22} (float32-gerundet wie Roblox).
--  Spalten der Rotationsmatrix: X = RightVector, Y = UpVector, Z = -LookVector.
--  Algorithmen nach G3D (Roblox' Ursprung): toEulerAnglesXYZ/YXZ, toAxisAngle, lookAt (Up-Wechsel auf X-Achse bei
--  senkrechtem Blick, NaN bei Nullrichtung), Lerp = Quaternion-Slerp.
-- =====================================================================
return function(R, DT)
	local Util = R.Util
	local raise = Util.raise
	local typeof = Util.typeof
	local checkNumber = Util.checkNumber
	local fmtFloat = Util.fmtFloat
	local getmt = getmetatable
	local vcreate = vector.create
	local newV3 = DT.make.V3
	local newV3vec = DT.make.V3vec
	local isV3 = DT.is.Vector3
	local checkV3 = DT.checkV3
	local sqrt, sin, cos, abs, asin, acos, atan2 =
		math.sqrt, math.sin, math.cos, math.abs, math.asin, math.acos, math.atan2
	local fmt = string.format
	local HALF_PI = math.pi / 2

	local CF = {}
	DT.CFrame = CF
	local methods = {}
	local CFindex, CFeq, CFtostring, CFmul, CFadd, CFsub

	local function newCF(x, y, z, a, b, c, d, e, f, g, h, i)
		local p = vcreate(x, y, z)
		local r0 = vcreate(a, b, c)
		local r1 = vcreate(d, e, f)
		local r2 = vcreate(g, h, i)
		local u = newproxy(true)
		local mt = getmt(u)
		mt.__index = CFindex
		mt.__newindex = DT.readonlyNewindex
		mt.__eq = CFeq
		mt.__tostring = CFtostring
		mt.__mul = CFmul
		mt.__add = CFadd
		mt.__sub = CFsub
		mt.__concat = DT.concatError
		mt.__lt = DT.ltError
		mt.__le = DT.leError
		mt.__type = "CFrame"
		mt.d = { p.x, p.y, p.z, r0.x, r0.y, r0.z, r1.x, r1.y, r1.z, r2.x, r2.y, r2.z }
		return u
	end
	DT.make.CF = newCF

	local function isCF(u)
		if type(u) ~= "userdata" then
			return false
		end
		local mt = getmt(u)
		return type(mt) == "table" and rawget(mt, "__index") == CFindex
	end
	DT.is.CFrame = isCF

	local function cfData(u)
		return getmt(u).d
	end
	DT.cfData = cfData

	local function checkCF(u, n, fname)
		if isCF(u) then
			return getmt(u).d
		end
		Util.badArg(n, fname, "CFrame", u)
	end
	DT.checkCF = checkCF

	local function selfCF(self, mname)
		if isCF(self) then
			return getmt(self).d
		end
		raise(fmt("Expected ':' not '.' calling member function %s", mname))
	end

	local function fromD(d)
		return newCF(d[1], d[2], d[3], d[4], d[5], d[6], d[7], d[8], d[9], d[10], d[11], d[12])
	end
	DT.make.CFfromData = fromD

	-- ---------------------------------------------------------------------------------------------
	--  Kernmathematik
	-- ---------------------------------------------------------------------------------------------
	local function mulCF(a, b)
		local ax, ay, az, a00, a01, a02, a10, a11, a12, a20, a21, a22 =
			a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12]
		local bx, by, bz, b00, b01, b02, b10, b11, b12, b20, b21, b22 =
			b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12]
		return newCF(
			a00 * bx + a01 * by + a02 * bz + ax,
			a10 * bx + a11 * by + a12 * bz + ay,
			a20 * bx + a21 * by + a22 * bz + az,
			a00 * b00 + a01 * b10 + a02 * b20,
			a00 * b01 + a01 * b11 + a02 * b21,
			a00 * b02 + a01 * b12 + a02 * b22,
			a10 * b00 + a11 * b10 + a12 * b20,
			a10 * b01 + a11 * b11 + a12 * b21,
			a10 * b02 + a11 * b12 + a12 * b22,
			a20 * b00 + a21 * b10 + a22 * b20,
			a20 * b01 + a21 * b11 + a22 * b21,
			a20 * b02 + a21 * b12 + a22 * b22
		)
	end
	DT.mulCFdata = mulCF

	local function invCF(a)
		local x, y, z, a00, a01, a02, a10, a11, a12, a20, a21, a22 =
			a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12]
		return newCF(
			-(a00 * x + a10 * y + a20 * z),
			-(a01 * x + a11 * y + a21 * z),
			-(a02 * x + a12 * y + a22 * z),
			a00,
			a10,
			a20,
			a01,
			a11,
			a21,
			a02,
			a12,
			a22
		)
	end

	local function pointToWorld(a, v)
		return newV3(
			a[4] * v.x + a[5] * v.y + a[6] * v.z + a[1],
			a[7] * v.x + a[8] * v.y + a[9] * v.z + a[2],
			a[10] * v.x + a[11] * v.y + a[12] * v.z + a[3]
		)
	end
	local function pointToObject(a, v)
		local x, y, z = v.x - a[1], v.y - a[2], v.z - a[3]
		return newV3(a[4] * x + a[7] * y + a[10] * z, a[5] * x + a[8] * y + a[11] * z, a[6] * x + a[9] * y + a[12] * z)
	end
	local function vectorToWorld(a, v)
		return newV3(
			a[4] * v.x + a[5] * v.y + a[6] * v.z,
			a[7] * v.x + a[8] * v.y + a[9] * v.z,
			a[10] * v.x + a[11] * v.y + a[12] * v.z
		)
	end
	local function vectorToObject(a, v)
		local x, y, z = v.x, v.y, v.z
		return newV3(a[4] * x + a[7] * y + a[10] * z, a[5] * x + a[8] * y + a[11] * z, a[6] * x + a[9] * y + a[12] * z)
	end
	DT.cfPointToWorld = pointToWorld
	DT.cfPointToObject = pointToObject
	DT.cfVectorToWorld = vectorToWorld

	-- Quaternion (x, y, z, w) aus Rotationsmatrix (Shepperd)
	local function toQuat(d)
		local m00, m01, m02, m10, m11, m12, m20, m21, m22 = d[4], d[5], d[6], d[7], d[8], d[9], d[10], d[11], d[12]
		local tr = m00 + m11 + m22
		local qx, qy, qz, qw
		if tr > 0 then
			local s = sqrt(tr + 1) * 2
			qw = 0.25 * s
			qx = (m21 - m12) / s
			qy = (m02 - m20) / s
			qz = (m10 - m01) / s
		elseif m00 > m11 and m00 > m22 then
			local s = sqrt(1 + m00 - m11 - m22) * 2
			qw = (m21 - m12) / s
			qx = 0.25 * s
			qy = (m01 + m10) / s
			qz = (m02 + m20) / s
		elseif m11 > m22 then
			local s = sqrt(1 + m11 - m00 - m22) * 2
			qw = (m02 - m20) / s
			qx = (m01 + m10) / s
			qy = 0.25 * s
			qz = (m12 + m21) / s
		else
			local s = sqrt(1 + m22 - m00 - m11) * 2
			qw = (m10 - m01) / s
			qx = (m02 + m20) / s
			qy = (m12 + m21) / s
			qz = 0.25 * s
		end
		return qx, qy, qz, qw
	end
	DT.cfToQuat = toQuat

	local function quatToRot(qx, qy, qz, qw)
		local n = sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
		if n == 0 then
			return 1, 0, 0, 0, 1, 0, 0, 0, 1
		end
		qx, qy, qz, qw = qx / n, qy / n, qz / n, qw / n
		local xx, yy, zz = qx * qx, qy * qy, qz * qz
		local xy, xz, yz = qx * qy, qx * qz, qy * qz
		local wx, wy, wz = qw * qx, qw * qy, qw * qz
		return 1 - 2 * (yy + zz),
			2 * (xy - wz),
			2 * (xz + wy),
			2 * (xy + wz),
			1 - 2 * (xx + zz),
			2 * (yz - wx),
			2 * (xz - wy),
			2 * (yz + wx),
			1 - 2 * (xx + yy)
	end
	DT.quatToRot = quatToRot

	local function rotX(a)
		local c, s = cos(a), sin(a)
		return 1, 0, 0, 0, c, -s, 0, s, c
	end
	local function rotY(a)
		local c, s = cos(a), sin(a)
		return c, 0, s, 0, 1, 0, -s, 0, c
	end
	local function rotZ(a)
		local c, s = cos(a), sin(a)
		return c, -s, 0, s, c, 0, 0, 0, 1
	end
	local function mul3(a00, a01, a02, a10, a11, a12, a20, a21, a22, b00, b01, b02, b10, b11, b12, b20, b21, b22)
		return a00 * b00 + a01 * b10 + a02 * b20,
			a00 * b01 + a01 * b11 + a02 * b21,
			a00 * b02 + a01 * b12 + a02 * b22,
			a10 * b00 + a11 * b10 + a12 * b20,
			a10 * b01 + a11 * b11 + a12 * b21,
			a10 * b02 + a11 * b12 + a12 * b22,
			a20 * b00 + a21 * b10 + a22 * b20,
			a20 * b01 + a21 * b11 + a22 * b21,
			a20 * b02 + a21 * b12 + a22 * b22
	end
	-- Rotation aus Euler-Winkeln: order = Zeichenkette wie "XYZ" -> R = R_X * R_Y * R_Z
	local rotFns = { X = rotX, Y = rotY, Z = rotZ }
	local function eulerRot(rx, ry, rz, order)
		local angles = { X = rx, Y = ry, Z = rz }
		local a1, a2, a3 = string.sub(order, 1, 1), string.sub(order, 2, 2), string.sub(order, 3, 3)
		local m = { rotFns[a1](angles[a1]) }
		m = { mul3(m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9], rotFns[a2](angles[a2])) }
		return mul3(m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9], rotFns[a3](angles[a3]))
	end
	DT.eulerRot = eulerRot

	-- G3D toEulerAnglesXYZ
	local function toEulerXYZ(d)
		local r00, r01, r02, r10, r11, r12, r22 = d[4], d[5], d[6], d[7], d[8], d[9], d[12]
		if r02 < 1 then
			if r02 > -1 then
				return atan2(-r12, r22), asin(r02), atan2(-r01, r00)
			end
			return -atan2(r10, r11), -HALF_PI, 0
		end
		return atan2(r10, r11), HALF_PI, 0
	end
	-- G3D toEulerAnglesYXZ -> (x, y, z)
	local function toEulerYXZ(d)
		local r00, r01, r02, r10, r11, r12, r22 = d[4], d[5], d[6], d[7], d[8], d[9], d[12]
		if r12 < 1 then
			if r12 > -1 then
				return asin(-r12), atan2(r02, r22), atan2(r10, r11)
			end
			return HALF_PI, atan2(r01, r00), 0
		end
		return -HALF_PI, atan2(-r01, r00), 0
	end
	DT.cfToEulerXYZ = toEulerXYZ
	DT.cfToEulerYXZ = toEulerYXZ

	-- Allgemeine Tait-Bryan-Zerlegung R = R_i(a) * R_j(b) * R_k(c)
	local axisIndex = { X = 0, Y = 1, Z = 2 }
	local function toEulerOrder(d, order)
		if order == "XYZ" then
			return toEulerXYZ(d)
		elseif order == "YXZ" then
			return toEulerYXZ(d)
		end
		local i = axisIndex[string.sub(order, 1, 1)]
		local j = axisIndex[string.sub(order, 2, 2)]
		local k = axisIndex[string.sub(order, 3, 3)]
		local function M(r, c)
			return d[4 + r * 3 + c]
		end
		local even = (j - i + 3) % 3 == 1
		local s = even and 1 or -1
		local a, b, c
		local rik = M(i, k)
		if abs(rik) < 0.9999999 then
			b = asin(math.clamp(s * rik, -1, 1))
			a = atan2(-s * M(j, k), M(k, k))
			c = atan2(-s * M(i, j), M(i, i))
		else
			b = (s * rik > 0) and HALF_PI or -HALF_PI
			c = 0
			a = atan2(s * M(k, j), M(j, j))
		end
		local out = {}
		out[i] = a
		out[j] = b
		out[k] = c
		return out[0], out[1], out[2]
	end

	-- G3D Matrix3::toAxisAngle
	local function toAxisAngle(d)
		local m00, m01, m02, m10, m11, m12, m20, m21, m22 = d[4], d[5], d[6], d[7], d[8], d[9], d[10], d[11], d[12]
		local tr = m00 + m11 + m22
		local c = math.clamp(0.5 * (tr - 1), -1, 1)
		local angle = acos(c)
		if angle > 0 then
			if angle < math.pi - 1e-6 then
				local x, y, z = m21 - m12, m02 - m20, m10 - m01
				local l = sqrt(x * x + y * y + z * z)
				return newV3(x / l, y / l, z / l), angle
			end
			-- Winkel = PI
			local x, y, z
			if m00 >= m11 then
				if m00 >= m22 then
					x = 0.5 * sqrt(math.max(m00 - m11 - m22 + 1, 0))
					local h = 0.5 / x
					y, z = h * m01, h * m02
				else
					z = 0.5 * sqrt(math.max(m22 - m00 - m11 + 1, 0))
					local h = 0.5 / z
					x, y = h * m02, h * m12
				end
			else
				if m11 >= m22 then
					y = 0.5 * sqrt(math.max(m11 - m00 - m22 + 1, 0))
					local h = 0.5 / y
					x, z = h * m01, h * m12
				else
					z = 0.5 * sqrt(math.max(m22 - m00 - m11 + 1, 0))
					local h = 0.5 / z
					x, y = h * m02, h * m12
				end
			end
			return newV3(x, y, z), angle
		end
		return newV3(1, 0, 0), 0
	end

	local function axisAngleRot(ax, ay, az, angle)
		local l = sqrt(ax * ax + ay * ay + az * az)
		ax, ay, az = ax / l, ay / l, az / l
		local c, s = cos(angle), sin(angle)
		local t = 1 - c
		return t * ax * ax + c,
			t * ax * ay - s * az,
			t * ax * az + s * ay,
			t * ax * ay + s * az,
			t * ay * ay + c,
			t * ay * az - s * ax,
			t * ax * az - s * ay,
			t * ay * az + s * ax,
			t * az * az + c
	end

	-- G3D CoordinateFrame::lookAt
	local function lookAtRot(px, py, pz, tx, ty, tz, ux, uy, uz)
		local ul = sqrt(ux * ux + uy * uy + uz * uz)
		ux, uy, uz = ux / ul, uy / ul, uz / ul
		local lx, ly, lz = tx - px, ty - py, tz - pz
		local ll = sqrt(lx * lx + ly * ly + lz * lz)
		lx, ly, lz = lx / ll, ly / ll, lz / ll -- Nullrichtung -> NaN wie Roblox
		if abs(lx * ux + ly * uy + lz * uz) > 0.99 then
			ux, uy, uz = 1, 0, 0
			if abs(lx) > 0.99 then
				ux, uy, uz = 0, 1, 0
			end
		end
		local dp = lx * ux + ly * uy + lz * uz
		ux, uy, uz = ux - lx * dp, uy - ly * dp, uz - lz * dp
		ul = sqrt(ux * ux + uy * uy + uz * uz)
		ux, uy, uz = ux / ul, uy / ul, uz / ul
		local zx, zy, zz = -lx, -ly, -lz
		-- x = -z × up
		local xx, xy, xz = -(zy * uz - zz * uy), -(zz * ux - zx * uz), -(zx * uy - zy * ux)
		local xl = sqrt(xx * xx + xy * xy + xz * xz)
		xx, xy, xz = xx / xl, xy / xl, xz / xl
		-- y = z × x
		local yx, yy, yz = zy * xz - zz * xy, zz * xx - zx * xz, zx * xy - zy * xx
		return xx, yx, zx, xy, yy, zy, xz, yz, zz
	end

	-- ---------------------------------------------------------------------------------------------
	--  Metamethoden + Index
	-- ---------------------------------------------------------------------------------------------
	function CFindex(self, k)
		local d = getmt(self).d
		if k == "Position" or k == "p" then
			return newV3(d[1], d[2], d[3])
		elseif k == "X" or k == "x" then
			return d[1]
		elseif k == "Y" or k == "y" then
			return d[2]
		elseif k == "Z" or k == "z" then
			return d[3]
		elseif k == "LookVector" or k == "lookVector" then
			return newV3(-d[6], -d[9], -d[12])
		elseif k == "RightVector" or k == "rightVector" or k == "XVector" then
			return newV3(d[4], d[7], d[10])
		elseif k == "UpVector" or k == "upVector" or k == "YVector" then
			return newV3(d[5], d[8], d[11])
		elseif k == "ZVector" then
			return newV3(d[6], d[9], d[12])
		elseif k == "Rotation" then
			return newCF(0, 0, 0, d[4], d[5], d[6], d[7], d[8], d[9], d[10], d[11], d[12])
		end
		local m = methods[k]
		if m then
			return m
		end
		DT.badMember("CFrame", k)
	end
	Util.registerHostIndex(CFindex)

	function CFeq(a, b)
		if not (isCF(a) and isCF(b)) then
			return false
		end
		local x, y = getmt(a).d, getmt(b).d
		for i = 1, 12 do
			if x[i] ~= y[i] then
				return false
			end
		end
		return true
	end

	function CFtostring(self)
		local d = getmt(self).d
		local parts = table.create(12)
		for i = 1, 12 do
			parts[i] = fmtFloat(d[i])
		end
		return table.concat(parts, ", ")
	end

	function CFmul(a, b)
		if not isCF(a) then
			raise(fmt("invalid argument #1 (CFrame expected, got %s)", typeof(a)))
		end
		local da = getmt(a).d
		if isCF(b) then
			return mulCF(da, getmt(b).d)
		elseif isV3(b) then
			return pointToWorld(da, DT.v3vec(b))
		end
		raise(fmt("invalid argument #2 (Vector3 expected, got %s)", typeof(b)))
	end
	function CFadd(a, b)
		if not isCF(a) then
			raise(fmt("invalid argument #1 (CFrame expected, got %s)", typeof(a)))
		end
		if not isV3(b) then
			raise(fmt("invalid argument #2 (Vector3 expected, got %s)", typeof(b)))
		end
		local d = getmt(a).d
		local v = DT.v3vec(b)
		return newCF(d[1] + v.x, d[2] + v.y, d[3] + v.z, d[4], d[5], d[6], d[7], d[8], d[9], d[10], d[11], d[12])
	end
	function CFsub(a, b)
		if not isCF(a) then
			raise(fmt("invalid argument #1 (CFrame expected, got %s)", typeof(a)))
		end
		if not isV3(b) then
			raise(fmt("invalid argument #2 (Vector3 expected, got %s)", typeof(b)))
		end
		local d = getmt(a).d
		local v = DT.v3vec(b)
		return newCF(d[1] - v.x, d[2] - v.y, d[3] - v.z, d[4], d[5], d[6], d[7], d[8], d[9], d[10], d[11], d[12])
	end

	-- ---------------------------------------------------------------------------------------------
	--  Konstruktoren
	-- ---------------------------------------------------------------------------------------------
	local IDENTITY = newCF(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	CF.identity = IDENTITY

	function CF.new(...)
		local n = select("#", ...)
		if n == 0 then
			return newCF(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
		end
		local a1, a2 = ...
		if n == 1 then
			local p = checkV3(a1, 1, "new")
			return newCF(p.x, p.y, p.z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
		end
		if n == 2 then
			local p = checkV3(a1, 1, "new")
			local t = checkV3(a2, 2, "new")
			return newCF(p.x, p.y, p.z, lookAtRot(p.x, p.y, p.z, t.x, t.y, t.z, 0, 1, 0))
		end
		if n == 3 then
			local x, y, z = ...
			return newCF(
				checkNumber(x, 1, "new"),
				checkNumber(y, 2, "new"),
				checkNumber(z, 3, "new"),
				1,
				0,
				0,
				0,
				1,
				0,
				0,
				0,
				1
			)
		end
		if n == 7 then
			local x, y, z, qx, qy, qz, qw = ...
			x, y, z = checkNumber(x, 1, "new"), checkNumber(y, 2, "new"), checkNumber(z, 3, "new")
			qx, qy, qz, qw =
				checkNumber(qx, 4, "new"),
				checkNumber(qy, 5, "new"),
				checkNumber(qz, 6, "new"),
				checkNumber(qw, 7, "new")
			return newCF(x, y, z, quatToRot(qx, qy, qz, qw))
		end
		if n == 12 then
			local v = { ... }
			for i = 1, 12 do
				v[i] = checkNumber(v[i], i, "new")
			end
			return newCF(v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], v[10], v[11], v[12])
		end
		raise("Invalid number of arguments: " .. n)
	end

	function CF.lookAt(at, target, up)
		local p = checkV3(at, 1, "lookAt")
		local t = checkV3(target, 2, "lookAt")
		local ux, uy, uz = 0, 1, 0
		if up ~= nil then
			local u = checkV3(up, 3, "lookAt")
			ux, uy, uz = u.x, u.y, u.z
		end
		return newCF(p.x, p.y, p.z, lookAtRot(p.x, p.y, p.z, t.x, t.y, t.z, ux, uy, uz))
	end
	function CF.lookAlong(at, direction, up)
		local p = checkV3(at, 1, "lookAlong")
		local dv = checkV3(direction, 2, "lookAlong")
		local ux, uy, uz = 0, 1, 0
		if up ~= nil then
			local u = checkV3(up, 3, "lookAlong")
			ux, uy, uz = u.x, u.y, u.z
		end
		return newCF(p.x, p.y, p.z, lookAtRot(0, 0, 0, dv.x, dv.y, dv.z, ux, uy, uz))
	end

	local function anglesArgs(fname, rx, ry, rz)
		return checkNumber(rx, 1, fname), checkNumber(ry, 2, fname), checkNumber(rz, 3, fname)
	end
	function CF.Angles(rx, ry, rz)
		rx, ry, rz = anglesArgs("Angles", rx, ry, rz)
		return newCF(0, 0, 0, eulerRot(rx, ry, rz, "XYZ"))
	end
	function CF.fromEulerAnglesXYZ(rx, ry, rz)
		rx, ry, rz = anglesArgs("fromEulerAnglesXYZ", rx, ry, rz)
		return newCF(0, 0, 0, eulerRot(rx, ry, rz, "XYZ"))
	end
	function CF.fromEulerAnglesYXZ(rx, ry, rz)
		rx, ry, rz = anglesArgs("fromEulerAnglesYXZ", rx, ry, rz)
		return newCF(0, 0, 0, eulerRot(rx, ry, rz, "YXZ"))
	end
	function CF.fromOrientation(rx, ry, rz)
		rx, ry, rz = anglesArgs("fromOrientation", rx, ry, rz)
		return newCF(0, 0, 0, eulerRot(rx, ry, rz, "YXZ"))
	end
	function CF.fromEulerAngles(rx, ry, rz, order)
		rx, ry, rz = anglesArgs("fromEulerAngles", rx, ry, rz)
		local o = "XYZ"
		if order ~= nil then
			local item = R.Enum.coerce(order, "RotationOrder")
			if not item then
				Util.badArg(4, "fromEulerAngles", "Enum.RotationOrder", order)
			end
			o = item.Name
		end
		return newCF(0, 0, 0, eulerRot(rx, ry, rz, o))
	end
	function CF.fromAxisAngle(axis, angle)
		local v = checkV3(axis, 1, "fromAxisAngle")
		local a = checkNumber(angle, 2, "fromAxisAngle")
		return newCF(0, 0, 0, axisAngleRot(v.x, v.y, v.z, a))
	end
	function CF.fromMatrix(pos, vX, vY, vZ)
		local p = checkV3(pos, 1, "fromMatrix")
		local x = checkV3(vX, 2, "fromMatrix")
		local y = checkV3(vY, 3, "fromMatrix")
		local z
		if vZ == nil then
			z = vector.normalize(vector.cross(x, y))
		else
			z = checkV3(vZ, 4, "fromMatrix")
		end
		return newCF(p.x, p.y, p.z, x.x, y.x, z.x, x.y, y.y, z.y, x.z, y.z, z.z)
	end
	function CF.fromRotationBetweenVectors(from, to)
		local a = vector.normalize(checkV3(from, 1, "fromRotationBetweenVectors"))
		local b = vector.normalize(checkV3(to, 2, "fromRotationBetweenVectors"))
		local d = vector.dot(a, b)
		if d > 0.9999999 then
			return newCF(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
		end
		if d < -0.9999999 then
			-- 180° um eine beliebige Senkrechte
			local axis = vector.cross(vector.create(1, 0, 0), a)
			if vector.magnitude(axis) < 1e-6 then
				axis = vector.cross(vector.create(0, 1, 0), a)
			end
			return newCF(0, 0, 0, axisAngleRot(axis.x, axis.y, axis.z, math.pi))
		end
		local c = vector.cross(a, b)
		-- Quaternion des kürzesten Bogens
		local w = 1 + d
		return newCF(0, 0, 0, quatToRot(c.x, c.y, c.z, w))
	end

	-- ---------------------------------------------------------------------------------------------
	--  Methoden
	-- ---------------------------------------------------------------------------------------------
	function methods.Inverse(self)
		return invCF(selfCF(self, "Inverse"))
	end
	methods.inverse = methods.Inverse

	local function slerpData(a, b, t)
		local ax, ay, az, aw = toQuat(a)
		local bx, by, bz, bw = toQuat(b)
		local dot = ax * bx + ay * by + az * bz + aw * bw
		if dot < 0 then
			bx, by, bz, bw = -bx, -by, -bz, -bw
			dot = -dot
		end
		local qx, qy, qz, qw
		if dot > 0.9995 then
			qx, qy, qz, qw = ax + (bx - ax) * t, ay + (by - ay) * t, az + (bz - az) * t, aw + (bw - aw) * t
		else
			local theta = acos(math.clamp(dot, -1, 1))
			local s = sin(theta)
			local wa, wb = sin((1 - t) * theta) / s, sin(t * theta) / s
			qx, qy, qz, qw = ax * wa + bx * wb, ay * wa + by * wb, az * wa + bz * wb, aw * wa + bw * wb
		end
		return newCF(
			a[1] + (b[1] - a[1]) * t,
			a[2] + (b[2] - a[2]) * t,
			a[3] + (b[3] - a[3]) * t,
			quatToRot(qx, qy, qz, qw)
		)
	end
	DT.cfSlerp = function(a, b, t)
		return slerpData(getmt(a).d, getmt(b).d, t)
	end

	function methods.Lerp(self, goal, alpha)
		local a = selfCF(self, "Lerp")
		local b = checkCF(goal, 1, "Lerp")
		local t = checkNumber(alpha, 2, "Lerp")
		return slerpData(a, b, t)
	end
	methods.lerp = methods.Lerp

	function methods.Orthonormalize(self)
		local d = selfCF(self, "Orthonormalize")
		local x = vector.normalize(vcreate(d[4], d[7], d[10]))
		local yRaw = vcreate(d[5], d[8], d[11])
		local y = vector.normalize(yRaw - x * vector.dot(x, yRaw))
		local z = vector.cross(x, y)
		return newCF(d[1], d[2], d[3], x.x, y.x, z.x, x.y, y.y, z.y, x.z, y.z, z.z)
	end

	local function variadic(self, mname, check, op, ...)
		local d = selfCF(self, mname)
		local n = select("#", ...)
		if n == 0 then
			return
		end
		if n == 1 then
			return op(d, check((...), 1, mname))
		end
		local out = table.create(n)
		for i = 1, n do
			out[i] = op(d, check((select(i, ...)), i, mname))
		end
		return table.unpack(out, 1, n)
	end
	function methods.ToWorldSpace(self, ...)
		return variadic(self, "ToWorldSpace", checkCF, mulCF, ...)
	end
	methods.toWorldSpace = methods.ToWorldSpace
	function methods.ToObjectSpace(self, ...)
		return variadic(self, "ToObjectSpace", checkCF, function(d, o)
			return mulCF(getmt(invCF(d)).d, o)
		end, ...)
	end
	methods.toObjectSpace = methods.ToObjectSpace
	function methods.PointToWorldSpace(self, ...)
		return variadic(self, "PointToWorldSpace", checkV3, pointToWorld, ...)
	end
	methods.pointToWorldSpace = methods.PointToWorldSpace
	function methods.PointToObjectSpace(self, ...)
		return variadic(self, "PointToObjectSpace", checkV3, pointToObject, ...)
	end
	methods.pointToObjectSpace = methods.PointToObjectSpace
	function methods.VectorToWorldSpace(self, ...)
		return variadic(self, "VectorToWorldSpace", checkV3, vectorToWorld, ...)
	end
	methods.vectorToWorldSpace = methods.VectorToWorldSpace
	function methods.VectorToObjectSpace(self, ...)
		return variadic(self, "VectorToObjectSpace", checkV3, vectorToObject, ...)
	end
	methods.vectorToObjectSpace = methods.VectorToObjectSpace

	function methods.GetComponents(self)
		local d = selfCF(self, "GetComponents")
		return d[1], d[2], d[3], d[4], d[5], d[6], d[7], d[8], d[9], d[10], d[11], d[12]
	end
	methods.components = methods.GetComponents

	function methods.ToEulerAnglesXYZ(self)
		return toEulerXYZ(selfCF(self, "ToEulerAnglesXYZ"))
	end
	methods.toEulerAnglesXYZ = methods.ToEulerAnglesXYZ
	function methods.ToEulerAnglesYXZ(self)
		return toEulerYXZ(selfCF(self, "ToEulerAnglesYXZ"))
	end
	methods.toEulerAnglesYXZ = methods.ToEulerAnglesYXZ
	function methods.ToOrientation(self)
		return toEulerYXZ(selfCF(self, "ToOrientation"))
	end
	function methods.ToEulerAngles(self, order)
		local d = selfCF(self, "ToEulerAngles")
		local o = "XYZ"
		if order ~= nil then
			local item = R.Enum.coerce(order, "RotationOrder")
			if not item then
				Util.badArg(1, "ToEulerAngles", "Enum.RotationOrder", order)
			end
			o = item.Name
		end
		return toEulerOrder(d, o)
	end
	function methods.ToAxisAngle(self)
		return toAxisAngle(selfCF(self, "ToAxisAngle"))
	end
	methods.toAxisAngle = methods.ToAxisAngle

	function methods.FuzzyEq(self, other, epsilon)
		local a = selfCF(self, "FuzzyEq")
		local b = checkCF(other, 1, "FuzzyEq")
		local eps = epsilon == nil and 1e-5 or checkNumber(epsilon, 2, "FuzzyEq")
		local fz = DT.fuzzy
		for i = 1, 3 do
			if not fz(a[i], b[i], eps) then
				return false
			end
		end
		for i = 4, 12 do
			if not fz(a[i], b[i], eps) then
				return false
			end
		end
		return true
	end

	-- intern: Rotation (Matrix) + Position
	function DT.cfFromPosRot(x, y, z, rot)
		return newCF(x, y, z, rot[1], rot[2], rot[3], rot[4], rot[5], rot[6], rot[7], rot[8], rot[9])
	end
end
