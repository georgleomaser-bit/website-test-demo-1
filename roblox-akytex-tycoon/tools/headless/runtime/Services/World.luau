--!nocheck
-- =====================================================================
--  Headless-Harness · Welt: WorldRoot-Abfragen, Kamera, Terrain, Kollisionsgruppen (PhysicsService)
--
--  Räumlicher Index je Workspace (Gitter 32 Studs, große Teile separat), gepflegt über Inst-Beobachter
--  (Parent-Wechsel, CFrame/Size). Abfragen:
--   Raycast (Box exakt per Slab-Test, Ball als Kugel, Zylinder exakt, Keil/Mesh/Union als Box; Strahlen aus dem
--   Inneren treffen das Teil NICHT – wie Roblox), Spherecast/Blockcast/Shapecast (Box um Radius/Halbmaß
--   aufgebläht, Startüberlappung zählt nicht), GetPartBoundsInBox (OBB/OBB-SAT), GetPartBoundsInRadius (OBB/Kugel),
--   GetPartsInPart (OBB/OBB), ArePartsTouchingOthers, BulkMoveTo (FireAllEvents/FireCFrameChanged/FireNoEvents),
--   veraltete FindPartOnRay*/FindPartsInRegion3*. Filter: RaycastParams/OverlapParams (Exclude/Include mit
--   Nachfahren, CollisionGroup, RespectCanCollide, IgnoreWater), CanQuery (nur wirksam bei CanCollide = false).
--  Terrain: Fill*-Formen (Block/Kugel/Zylinder/Keil) + WriteVoxels (dünn besetzte 4-Stud-Voxel), ReadVoxels
--   (Ausrichtung/Größe geprüft), Raycast trifft Terrain (Wasser optional), Clear, Material-Farben.
--  Kamera: ViewportSize (Client 1280×720, Server 1×1), WorldToViewportPoint/WorldToScreenPoint (Topbar-Inset),
--   ViewportPointToRay/ScreenPointToRay (vertikales FOV), Standard-Kamerasteuerung des Clients
--   (CameraType Custom: folgt CameraSubject; CameraSubject wird beim Spawn auf den eigenen Humanoid gesetzt).
-- =====================================================================
return function(R, Svc)
	local Util = R.Util
	local Sched = R.Sched
	local Report = R.Report
	local Inst = R.Inst
	local DT = R.DT
	local Enum = R.Enum
	local raise = Util.raise
	local getmt = getmetatable
	local fmt = string.format
	local mk = DT.make
	local CF = DT.CFrame
	local abs, min, max, sqrt, huge = math.abs, math.min, math.max, math.sqrt, math.huge

	local W = {}
	Svc.World = W

	-- =================================================================================================
	--  Kollisionsgruppen (global – Roblox repliziert sie an alle Clients)
	-- =================================================================================================
	local groups = { { name = "Default", id = 0, collide = {} } }
	W.collisionGroups = groups
	local function findGroup(name)
		for _, g in groups do
			if g.name == name then
				return g
			end
		end
		return nil
	end
	local function groupsCollide(a, b)
		local ga, gb = findGroup(a), findGroup(b)
		if ga == nil or gb == nil then
			return true
		end
		local v = ga.collide[gb.name]
		if v == nil then
			return true
		end
		return v
	end
	W.groupsCollide = groupsCollide
	Inst.collisionGroupsCollide = groupsCollide

	local PH = {}
	function PH.RegisterCollisionGroup(self, name)
		Inst.checkSelf(self, "RegisterCollisionGroup")
		name = Util.checkString(name, 1, "RegisterCollisionGroup")
		if name == "Default" then
			raise("Cannot register a collision group named Default")
		end
		if findGroup(name) then
			return
		end
		if #groups >= 32 then
			raise("Could not create collision group, the maximum number of collision groups (32) has been reached")
		end
		if #name > 100 then
			raise("Collision group name is too long")
		end
		groups[#groups + 1] = { name = name, id = #groups, collide = {} }
	end
	function PH.UnregisterCollisionGroup(self, name)
		Inst.checkSelf(self, "UnregisterCollisionGroup")
		name = Util.checkString(name, 1, "UnregisterCollisionGroup")
		if name == "Default" then
			raise("Cannot unregister the Default collision group")
		end
		for i, g in groups do
			if g.name == name then
				table.remove(groups, i)
				break
			end
		end
		for _, g in groups do
			g.collide[name] = nil
		end
	end
	function PH.RenameCollisionGroup(self, from, to)
		Inst.checkSelf(self, "RenameCollisionGroup")
		from = Util.checkString(from, 1, "RenameCollisionGroup")
		to = Util.checkString(to, 2, "RenameCollisionGroup")
		local g = findGroup(from)
		if g == nil then
			raise(fmt("Collision group '%s' does not exist", from))
		end
		g.name = to
	end
	function PH.IsCollisionGroupRegistered(self, name)
		Inst.checkSelf(self, "IsCollisionGroupRegistered")
		name = Util.checkString(name, 1, "IsCollisionGroupRegistered")
		return findGroup(name) ~= nil
	end
	function PH.CollisionGroupSetCollidable(self, a, b, collidable)
		Inst.checkSelf(self, "CollisionGroupSetCollidable")
		a = Util.checkString(a, 1, "CollisionGroupSetCollidable")
		b = Util.checkString(b, 2, "CollisionGroupSetCollidable")
		collidable = Util.checkBool(collidable, 3, "CollisionGroupSetCollidable")
		local ga, gb = findGroup(a), findGroup(b)
		if ga == nil then
			raise(fmt("Collision group '%s' does not exist.", a))
		end
		if gb == nil then
			raise(fmt("Collision group '%s' does not exist.", b))
		end
		ga.collide[b] = collidable
		gb.collide[a] = collidable
	end
	function PH.CollisionGroupsAreCollidable(self, a, b)
		Inst.checkSelf(self, "CollisionGroupsAreCollidable")
		a = Util.checkString(a, 1, "CollisionGroupsAreCollidable")
		b = Util.checkString(b, 2, "CollisionGroupsAreCollidable")
		return groupsCollide(a, b)
	end
	function PH.GetRegisteredCollisionGroups(self)
		Inst.checkSelf(self, "GetRegisteredCollisionGroups")
		local out = {}
		for i, g in groups do
			local mask = 0
			for j, h in groups do
				if groupsCollide(g.name, h.name) then
					mask = bit32.bor(mask, bit32.lshift(1, j - 1))
				end
			end
			out[#out + 1] = { id = i - 1, mask = mask, name = g.name }
		end
		return out
	end
	function PH.GetMaxCollisionGroups(self)
		Inst.checkSelf(self, "GetMaxCollisionGroups")
		return 32
	end
	function PH.SetPartCollisionGroup(self, part, name)
		Inst.checkSelf(self, "SetPartCollisionGroup")
		Svc.checkInstance(part, 1, "SetPartCollisionGroup", "BasePart")
		name = Util.checkString(name, 2, "SetPartCollisionGroup")
		if findGroup(name) == nil then
			raise(fmt("Collision group '%s' does not exist.", name))
		end
		part.CollisionGroup = name
	end
	function PH.GetCollisionGroupName(self, id)
		Inst.checkSelf(self, "GetCollisionGroupName")
		id = Util.checkNumber(id, 1, "GetCollisionGroupName")
		local g = groups[id + 1]
		return g and g.name or ""
	end
	function PH.CreateCollisionGroup(self, name)
		PH.RegisterCollisionGroup(self, name)
		local g = findGroup(name)
		return g and (table.find(groups, g) - 1) or 0
	end
	Inst.registerService("PhysicsService", { methods = PH })

	-- =================================================================================================
	--  Geometrie-Helfer
	-- =================================================================================================
	local cfData = DT.cfData
	local v3xyz = DT.v3xyz

	local function partShape(M)
		local cls = M.cls
		if cls.name == "Part" or cls.name == "SpawnLocation" or cls.name == "Seat" then
			local s = M.props.Shape
			if s then
				local n = s.Name
				if n == "Ball" then
					return "ball"
				elseif n == "Cylinder" then
					return "cyl"
				end
			end
		end
		return "box"
	end

	local function sizeOf(M)
		local s = M.props.Size
		if s == nil then
			s = Inst.defaultValue(M.self, "Size")
		end
		return s
	end

	-- AABB eines Teils (min x,y,z, max x,y,z)
	local function partAabb(M)
		local cf = M.props.CFrame or CF.identity
		local d = cfData(cf)
		local sx, sy, sz = v3xyz(sizeOf(M))
		local hx = (abs(d[4]) * sx + abs(d[5]) * sy + abs(d[6]) * sz) / 2
		local hy = (abs(d[7]) * sx + abs(d[8]) * sy + abs(d[9]) * sz) / 2
		local hz = (abs(d[10]) * sx + abs(d[11]) * sy + abs(d[12]) * sz) / 2
		return d[1] - hx, d[2] - hy, d[3] - hz, d[1] + hx, d[2] + hy, d[3] + hz
	end

	-- Strahl gegen Box im lokalen Raum: liefert t, lokale Normalen-Achse/Vorzeichen (nur Eintritt, t >= 0)
	local function rayBox(ox, oy, oz, dx, dy, dz, hx, hy, hz)
		local tmin, tmax = -huge, huge
		local nAxis, nSign = 0, 0
		-- x
		if abs(dx) < 1e-12 then
			if ox < -hx or ox > hx then
				return nil
			end
		else
			local t1, t2 = (-hx - ox) / dx, (hx - ox) / dx
			local s = -1
			if t1 > t2 then
				t1, t2 = t2, t1
				s = 1
			end
			if t1 > tmin then
				tmin, nAxis, nSign = t1, 1, s
			end
			if t2 < tmax then
				tmax = t2
			end
		end
		if abs(dy) < 1e-12 then
			if oy < -hy or oy > hy then
				return nil
			end
		else
			local t1, t2 = (-hy - oy) / dy, (hy - oy) / dy
			local s = -1
			if t1 > t2 then
				t1, t2 = t2, t1
				s = 1
			end
			if t1 > tmin then
				tmin, nAxis, nSign = t1, 2, s
			end
			if t2 < tmax then
				tmax = t2
			end
		end
		if abs(dz) < 1e-12 then
			if oz < -hz or oz > hz then
				return nil
			end
		else
			local t1, t2 = (-hz - oz) / dz, (hz - oz) / dz
			local s = -1
			if t1 > t2 then
				t1, t2 = t2, t1
				s = 1
			end
			if t1 > tmin then
				tmin, nAxis, nSign = t1, 3, s
			end
			if t2 < tmax then
				tmax = t2
			end
		end
		if tmin > tmax or tmin < 0 or nAxis == 0 then
			return nil
		end
		return tmin, nAxis, nSign
	end
	W.rayBox = rayBox

	-- Strahl (Welt, dir nicht normiert, t in [0,1]) gegen Teil; Rückgabe t, Normale (Vector3)
	local function rayPart(M, ox, oy, oz, dx, dy, dz, inflate)
		local cf = M.props.CFrame or CF.identity
		local d = cfData(cf)
		local px, py, pz = ox - d[1], oy - d[2], oz - d[3]
		-- lokale Koordinaten: R^T * v (Spalten = lokale Achsen)
		local lox = d[4] * px + d[7] * py + d[10] * pz
		local loy = d[5] * px + d[8] * py + d[11] * pz
		local loz = d[6] * px + d[9] * py + d[12] * pz
		local ldx = d[4] * dx + d[7] * dy + d[10] * dz
		local ldy = d[5] * dx + d[8] * dy + d[11] * dz
		local ldz = d[6] * dx + d[9] * dy + d[12] * dz
		local sx, sy, sz = v3xyz(sizeOf(M))
		inflate = inflate or 0
		local shape = partShape(M)
		if shape == "ball" and inflate == 0 then
			local r = min(sx, sy, sz) / 2
			local a = ldx * ldx + ldy * ldy + ldz * ldz
			local b = 2 * (lox * ldx + loy * ldy + loz * ldz)
			local c = lox * lox + loy * loy + loz * loz - r * r
			if c < 0 then
				return nil -- Start im Inneren
			end
			local disc = b * b - 4 * a * c
			if disc < 0 or a == 0 then
				return nil
			end
			local t = (-b - sqrt(disc)) / (2 * a)
			if t < 0 then
				return nil
			end
			local hx, hy, hz = lox + ldx * t, loy + ldy * t, loz + ldz * t
			local len = sqrt(hx * hx + hy * hy + hz * hz)
			local nx, ny, nz = hx / len, hy / len, hz / len
			return t,
				d[4] * nx + d[5] * ny + d[6] * nz,
				d[7] * nx + d[8] * ny + d[9] * nz,
				d[10] * nx + d[11] * ny + d[12] * nz
		elseif shape == "cyl" and inflate == 0 then
			local r = min(sy, sz) / 2
			local h = sx / 2
			if abs(lox) <= h and loy * loy + loz * loz <= r * r then
				return nil
			end
			local best, bnx, bny, bnz = huge, 0, 0, 0
			local a = ldy * ldy + ldz * ldz
			if a > 1e-12 then
				local b = 2 * (loy * ldy + loz * ldz)
				local c = loy * loy + loz * loz - r * r
				local disc = b * b - 4 * a * c
				if disc >= 0 then
					local t = (-b - sqrt(disc)) / (2 * a)
					if t >= 0 then
						local x = lox + ldx * t
						if abs(x) <= h and t < best then
							local hy2, hz2 = loy + ldy * t, loz + ldz * t
							best, bnx, bny, bnz = t, 0, hy2 / r, hz2 / r
						end
					end
				end
			end
			if abs(ldx) > 1e-12 then
				for _, sgn in { -1, 1 } do
					local t = (sgn * h - lox) / ldx
					if t >= 0 and t < best then
						local y, z = loy + ldy * t, loz + ldz * t
						if y * y + z * z <= r * r and (lox - sgn * h) * sgn > 0 then
							best, bnx, bny, bnz = t, sgn, 0, 0
						end
					end
				end
			end
			if best == huge then
				return nil
			end
			return best,
				d[4] * bnx + d[5] * bny + d[6] * bnz,
				d[7] * bnx + d[8] * bny + d[9] * bnz,
				d[10] * bnx + d[11] * bny + d[12] * bnz
		end
		local t, axis, sgn = rayBox(lox, loy, loz, ldx, ldy, ldz, sx / 2 + inflate, sy / 2 + inflate, sz / 2 + inflate)
		if t == nil then
			return nil
		end
		local nx, ny, nz = 0, 0, 0
		if axis == 1 then
			nx = sgn
		elseif axis == 2 then
			ny = sgn
		else
			nz = sgn
		end
		return t, d[4] * nx + d[5] * ny + d[6] * nz, d[7] * nx + d[8] * ny + d[9] * nz, d[10] * nx + d[11] * ny + d[12] * nz
	end
	W.rayPart = rayPart

	-- OBB als { cx, cy, cz, ax = {3 Achsen}, h = {3 Halbmaße} }
	local function obbOf(cf, sx, sy, sz)
		local d = cfData(cf)
		return {
			d[1],
			d[2],
			d[3],
			{ d[4], d[7], d[10] },
			{ d[5], d[8], d[11] },
			{ d[6], d[9], d[12] },
			sx / 2,
			sy / 2,
			sz / 2,
		}
	end
	local function partObb(M)
		local sx, sy, sz = v3xyz(sizeOf(M))
		return obbOf(M.props.CFrame or CF.identity, sx, sy, sz)
	end

	local function dot(a, b)
		return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
	end
	local function cross(a, b)
		return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
	end

	-- SAT-Test zweier OBBs
	local function obbOverlap(A, B)
		local T = { B[1] - A[1], B[2] - A[2], B[3] - A[3] }
		local Aax = { A[4], A[5], A[6] }
		local Bax = { B[4], B[5], B[6] }
		local Ah = { A[7], A[8], A[9] }
		local Bh = { B[7], B[8], B[9] }
		local axes = {}
		for i = 1, 3 do
			axes[#axes + 1] = Aax[i]
			axes[#axes + 1] = Bax[i]
		end
		for i = 1, 3 do
			for j = 1, 3 do
				local c = cross(Aax[i], Bax[j])
				if dot(c, c) > 1e-10 then
					axes[#axes + 1] = c
				end
			end
		end
		for _, L in axes do
			local ra = Ah[1] * abs(dot(Aax[1], L)) + Ah[2] * abs(dot(Aax[2], L)) + Ah[3] * abs(dot(Aax[3], L))
			local rb = Bh[1] * abs(dot(Bax[1], L)) + Bh[2] * abs(dot(Bax[2], L)) + Bh[3] * abs(dot(Bax[3], L))
			if abs(dot(T, L)) > ra + rb + 1e-6 then
				return false
			end
		end
		return true
	end
	W.obbOverlap = obbOverlap

	local function obbSphere(A, cx, cy, cz, r)
		local T = { cx - A[1], cy - A[2], cz - A[3] }
		local dsq = 0
		for i = 1, 3 do
			local ax = A[3 + i]
			local h = A[6 + i]
			local p = dot(T, ax)
			local c = math.clamp(p, -h, h)
			dsq += (p - c) * (p - c)
		end
		return dsq <= r * r
	end

	-- =================================================================================================
	--  Räumlicher Index je Workspace
	-- =================================================================================================
	local CELL = 32
	local BIG_CELLS = 512
	local OFF = 32768
	local function cellKey(ix, iy, iz)
		return ((ix + OFF) * 65536 + (iy + OFF)) * 65536 + (iz + OFF)
	end

	local function wsOf(u)
		local cur = u
		while cur do
			local M = getmt(cur)
			if M.cls.isA.Workspace then
				return cur
			end
			cur = M.parent
		end
		return nil
	end

	local function spatial(ws)
		local M = getmt(ws)
		M.ext = M.ext or {}
		local s = M.ext.spatial
		if s == nil then
			s = { parts = {}, grid = {}, cells = {}, big = {}, dirty = {}, count = 0 }
			M.ext.spatial = s
		end
		return s
	end

	local function unindex(s, part)
		local keys = s.cells[part]
		if keys then
			local grid = s.grid
			for _, k in keys do
				local list = grid[k]
				if list then
					list[part] = nil
				end
			end
			s.cells[part] = nil
		end
		s.big[part] = nil
	end

	local function index(s, part)
		local M = getmt(part)
		local x0, y0, z0, x1, y1, z1 = partAabb(M)
		if x0 ~= x0 or x1 ~= x1 or y0 ~= y0 or z0 ~= z0 then
			s.big[part] = true
			return
		end
		local ix0, iy0, iz0 = math.floor(x0 / CELL), math.floor(y0 / CELL), math.floor(z0 / CELL)
		local ix1, iy1, iz1 = math.floor(x1 / CELL), math.floor(y1 / CELL), math.floor(z1 / CELL)
		local n = (ix1 - ix0 + 1) * (iy1 - iy0 + 1) * (iz1 - iz0 + 1)
		if n > BIG_CELLS or ix0 < -OFF + 2 or ix1 > OFF - 2 or iy0 < -OFF + 2 or iy1 > OFF - 2 or iz0 < -OFF + 2 or iz1 > OFF - 2 then
			s.big[part] = true
			return
		end
		local keys = table.create(n)
		local grid = s.grid
		for ix = ix0, ix1 do
			for iy = iy0, iy1 do
				for iz = iz0, iz1 do
					local k = cellKey(ix, iy, iz)
					local list = grid[k]
					if list == nil then
						list = {}
						grid[k] = list
					end
					list[part] = true
					keys[#keys + 1] = k
				end
			end
		end
		s.cells[part] = keys
	end

	local function refresh(s)
		if next(s.dirty) == nil then
			return
		end
		for part in s.dirty do
			unindex(s, part)
			if s.parts[part] then
				index(s, part)
			end
		end
		table.clear(s.dirty)
	end

	local function isIndexable(M)
		return M.cls.isPart and not M.cls.isA.Terrain
	end

	local function addPart(ws, part)
		local s = spatial(ws)
		if not s.parts[part] then
			s.parts[part] = true
			s.count += 1
		end
		s.dirty[part] = true
		local M = getmt(part)
		M.ext = M.ext or {}
		M.ext.spatialWs = ws
	end
	local function removePart(ws, part)
		local s = spatial(ws)
		if s.parts[part] then
			s.parts[part] = nil
			s.count -= 1
		end
		s.dirty[part] = nil
		unindex(s, part)
		local M = getmt(part)
		if M.ext then
			M.ext.spatialWs = nil
		end
	end

	Inst.observe("reparented", function(u, old, new)
		local oldWs = old and wsOf(old)
		local newWs = new and wsOf(new)
		if oldWs == newWs then
			return
		end
		Inst.forSubtree(u, function(x)
			local XM = getmt(x)
			if isIndexable(XM) then
				if oldWs then
					removePart(oldWs, x)
				end
				if newWs and not XM.destroying then
					addPart(newWs, x)
				end
			end
		end)
	end)
	Inst.observe("changed", function(u, k)
		if k == "CFrame" or k == "Size" or k == "Shape" then
			local M = getmt(u)
			local e = M.ext
			local ws = e and e.spatialWs
			if ws then
				spatial(ws).dirty[u] = true
			end
		end
	end)
	W.markDirty = function(u)
		local e = getmt(u).ext
		local ws = e and e.spatialWs
		if ws then
			spatial(ws).dirty[u] = true
		end
	end

	-- Kandidaten in einer AABB
	local function candidatesInAabb(s, x0, y0, z0, x1, y1, z1, out)
		refresh(s)
		out = out or {}
		local seen = {}
		local ix0, iy0, iz0 = math.floor(x0 / CELL), math.floor(y0 / CELL), math.floor(z0 / CELL)
		local ix1, iy1, iz1 = math.floor(x1 / CELL), math.floor(y1 / CELL), math.floor(z1 / CELL)
		local n = (ix1 - ix0 + 1) * (iy1 - iy0 + 1) * (iz1 - iz0 + 1)
		if n > 20000 or n ~= n then
			for p in s.parts do
				out[#out + 1] = p
			end
			return out
		end
		local grid = s.grid
		for ix = ix0, ix1 do
			for iy = iy0, iy1 do
				for iz = iz0, iz1 do
					local list = grid[cellKey(ix, iy, iz)]
					if list then
						for p in list do
							if not seen[p] then
								seen[p] = true
								out[#out + 1] = p
							end
						end
					end
				end
			end
		end
		for p in s.big do
			if not seen[p] then
				seen[p] = true
				out[#out + 1] = p
			end
		end
		return out
	end

	--- Harness (Streaming): alle indizierten Teile, deren AABB die Kugel (pos, radius) schneidet
	function W.partsNear(ws, x, y, z, radius)
		local s = spatial(ws)
		local out = {}
		for _, p in candidatesInAabb(s, x - radius, y - radius, z - radius, x + radius, y + radius, z + radius) do
			local M = getmt(p)
			if not M.destroyed then
				local x0, y0, z0, x1, y1, z1 = partAabb(M)
				local dx = math.max(x0 - x, 0, x - x1)
				local dy = math.max(y0 - y, 0, y - y1)
				local dz = math.max(z0 - z, 0, z - z1)
				if dx * dx + dy * dy + dz * dz <= radius * radius then
					out[#out + 1] = p
				end
			end
		end
		return out
	end
	--- Abstand Punkt -> AABB eines Teils
	function W.partDistance(part, x, y, z)
		local x0, y0, z0, x1, y1, z1 = partAabb(getmt(part))
		local dx = math.max(x0 - x, 0, x - x1)
		local dy = math.max(y0 - y, 0, y - y1)
		local dz = math.max(z0 - z, 0, z - z1)
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end

	-- =================================================================================================
	--  Filter
	-- =================================================================================================
	local function makeFilter(params, isOverlap)
		local f = params and DT.paramFields(params)
		local include = false
		local set = nil
		local group = "Default"
		local respect = false
		local ignoreWater = false
		if f then
			include = f.FilterType and f.FilterType.Name == "Include"
			local list = f.FilterDescendantsInstances
			if list and #list > 0 then
				set = {}
				for _, x in list do
					set[x] = true
				end
			end
			group = f.CollisionGroup or "Default"
			respect = f.RespectCanCollide == true
			ignoreWater = f.IgnoreWater == true
		end
		local function listed(u)
			if set == nil then
				return false
			end
			local cur = u
			while cur do
				if set[cur] then
					return true
				end
				cur = getmt(cur).parent
			end
			return false
		end
		local function accept(u, M)
			local props = M.props
			local cc = props.CanCollide
			if cc == nil then
				cc = true
			end
			if cc == false and props.CanQuery == false then
				return false
			end
			if respect and cc == false then
				return false
			end
			if not groupsCollide(group, props.CollisionGroup or "Default") then
				return false
			end
			if include then
				return listed(u)
			end
			return not listed(u)
		end
		return accept, include and set or nil, ignoreWater, listed, include
	end
	W.makeFilter = makeFilter

	-- =================================================================================================
	--  Terrain (Formen + Voxel)
	-- =================================================================================================
	local TERRAIN_MATS = {
		Air = true,
		Water = true,
		Grass = true,
		Slate = true,
		Concrete = true,
		Brick = true,
		Sand = true,
		WoodPlanks = true,
		Rock = true,
		Glacier = true,
		Snow = true,
		Sandstone = true,
		Mud = true,
		Basalt = true,
		Ground = true,
		CrackedLava = true,
		Asphalt = true,
		Cobblestone = true,
		Ice = true,
		LeafyGrass = true,
		Salt = true,
		Limestone = true,
		Pavement = true,
	}
	local function terrainState(t)
		local M = getmt(t)
		M.ext = M.ext or {}
		local st = M.ext.terrain
		if st == nil then
			st = { shapes = {}, voxels = {}, vcount = 0, seq = 0, colors = {}, vmin = nil, vmax = nil }
			M.ext.terrain = st
		end
		return st
	end
	local function checkTerrainMat(v, n, fname)
		local it = Enum.coerce(v, "Material")
		if it == nil then
			Util.badArg(n, fname, "Enum.Material", v)
		end
		if not TERRAIN_MATS[it.Name] then
			raise(fmt("%s: Material %s is not a valid terrain material", fname, it.Name))
		end
		return it
	end
	local function vkey(ix, iy, iz)
		return cellKey(ix, iy, iz)
	end

	-- Material am Punkt (oder nil)
	local function terrainMaterialAt(st, x, y, z)
		local best, bestSeq = nil, -1
		if st.vcount > 0 then
			local ix, iy, iz = math.floor(x / 4), math.floor(y / 4), math.floor(z / 4)
			local v = st.voxels[vkey(ix, iy, iz)]
			if v then
				best, bestSeq = v[1], v[2]
			end
		end
		for i = #st.shapes, 1, -1 do
			local sh = st.shapes[i]
			if sh.seq <= bestSeq then
				break
			end
			local inside = false
			if sh.kind == "ball" then
				local dx, dy, dz = x - sh.cx, y - sh.cy, z - sh.cz
				inside = dx * dx + dy * dy + dz * dz <= sh.r * sh.r
			else
				local d = sh.d
				local px, py, pz = x - d[1], y - d[2], z - d[3]
				local lx = d[4] * px + d[7] * py + d[10] * pz
				local ly = d[5] * px + d[8] * py + d[11] * pz
				local lz = d[6] * px + d[9] * py + d[12] * pz
				if sh.kind == "cyl" then
					inside = abs(ly) <= sh.h and lx * lx + lz * lz <= sh.r * sh.r
				else
					inside = abs(lx) <= sh.hx and abs(ly) <= sh.hy and abs(lz) <= sh.hz
				end
			end
			if inside then
				best, bestSeq = sh.mat, sh.seq
				break
			end
		end
		if best and best.Name == "Air" then
			return nil
		end
		return best
	end
	W.ensureTerrainState = function(t)
		return terrainState(t)
	end
	W.terrainMaterialAt = function(t, x, y, z)
		return terrainMaterialAt(terrainState(t), x, y, z)
	end

	local function addShape(t, sh)
		local st = terrainState(t)
		st.seq += 1
		sh.seq = st.seq
		st.shapes[#st.shapes + 1] = sh
	end

	-- Strahl gegen Terrain: Formen analytisch, Voxel per Abtastung (Schritt 1 Stud)
	local function rayTerrain(t, ox, oy, oz, dx, dy, dz, ignoreWater)
		local st = terrainState(t)
		if #st.shapes == 0 and st.vcount == 0 then
			return nil
		end
		local len = sqrt(dx * dx + dy * dy + dz * dz)
		if len == 0 then
			return nil
		end
		local best = huge
		local bestMat, bnx, bny, bnz
		for _, sh in st.shapes do
			if not (sh.mat.Name == "Air" or (ignoreWater and sh.mat.Name == "Water")) then
				local tt, nx, ny, nz
				if sh.kind == "ball" then
					local px, py, pz = ox - sh.cx, oy - sh.cy, oz - sh.cz
					local a = dx * dx + dy * dy + dz * dz
					local b = 2 * (px * dx + py * dy + pz * dz)
					local c = px * px + py * py + pz * pz - sh.r * sh.r
					local disc = b * b - 4 * a * c
					if c >= 0 and disc >= 0 then
						local t0 = (-b - sqrt(disc)) / (2 * a)
						if t0 >= 0 then
							tt = t0
							local hx, hy, hz = px + dx * t0, py + dy * t0, pz + dz * t0
							local l = sqrt(hx * hx + hy * hy + hz * hz)
							nx, ny, nz = hx / l, hy / l, hz / l
						end
					end
				else
					local d = sh.d
					local px, py, pz = ox - d[1], oy - d[2], oz - d[3]
					local lox = d[4] * px + d[7] * py + d[10] * pz
					local loy = d[5] * px + d[8] * py + d[11] * pz
					local loz = d[6] * px + d[9] * py + d[12] * pz
					local ldx = d[4] * dx + d[7] * dy + d[10] * dz
					local ldy = d[5] * dx + d[8] * dy + d[11] * dz
					local ldz = d[6] * dx + d[9] * dy + d[12] * dz
					local hx, hy, hz = sh.hx, sh.hy, sh.hz
					if sh.kind == "cyl" then
						hx, hy, hz = sh.r, sh.h, sh.r
					end
					local t0, axis, sgn = rayBox(lox, loy, loz, ldx, ldy, ldz, hx, hy, hz)
					if t0 then
						tt = t0
						local lnx, lny, lnz = 0, 0, 0
						if axis == 1 then
							lnx = sgn
						elseif axis == 2 then
							lny = sgn
						else
							lnz = sgn
						end
						nx = d[4] * lnx + d[5] * lny + d[6] * lnz
						ny = d[7] * lnx + d[8] * lny + d[9] * lnz
						nz = d[10] * lnx + d[11] * lny + d[12] * lnz
					end
				end
				if tt and tt <= 1 and tt < best then
					best, bestMat, bnx, bny, bnz = tt, sh.mat, nx, ny, nz
				end
			end
		end
		if st.vcount > 0 and st.vmin then
			-- Abtastung entlang des Strahls, nur innerhalb der Voxel-Hülle
			local steps = math.ceil(len)
			local stepT = 1 / max(steps, 1)
			local vmin, vmax = st.vmin, st.vmax
			for i = 0, steps do
				local tt = i * stepT
				if tt >= best then
					break
				end
				local x, y, z = ox + dx * tt, oy + dy * tt, oz + dz * tt
				if x >= vmin[1] and x <= vmax[1] and y >= vmin[2] and y <= vmax[2] and z >= vmin[3] and z <= vmax[3] then
					local v = st.voxels[vkey(math.floor(x / 4), math.floor(y / 4), math.floor(z / 4))]
					if v and v[1].Name ~= "Air" and not (ignoreWater and v[1].Name == "Water") then
						best, bestMat = tt, v[1]
						bnx, bny, bnz = -dx / len, -dy / len, -dz / len
						break
					end
				end
			end
		end
		if bestMat == nil then
			return nil
		end
		return best, bnx, bny, bnz, bestMat
	end

	local function regionAligned(region, res)
		local mn, mx = DT.region3MinMax(region) -- native vectors
		local function al(v)
			return abs(v / res - math.floor(v / res + 0.5)) < 1e-6
		end
		local x0, y0, z0 = mn.x, mn.y, mn.z
		local x1, y1, z1 = mx.x, mx.y, mx.z
		return al(x0) and al(y0) and al(z0) and al(x1) and al(y1) and al(z1), x0, y0, z0, x1, y1, z1
	end

	local TR = {}
	local function terrSelf(self, m)
		return Inst.checkSelf(self, m)
	end
	function TR.FillBlock(self, cframe, size, material)
		terrSelf(self, "FillBlock")
		Util.checkType(cframe, "CFrame", 1, "FillBlock")
		local s = DT.checkV3(size, 2, "FillBlock")
		local mat = checkTerrainMat(material, 3, "FillBlock")
		local sx, sy, sz = v3xyz(mk.V3vec(s))
		addShape(self, { kind = "box", d = cfData(cframe), hx = sx / 2, hy = sy / 2, hz = sz / 2, mat = mat })
	end
	function TR.FillWedge(self, cframe, size, material)
		terrSelf(self, "FillWedge")
		Util.checkType(cframe, "CFrame", 1, "FillWedge")
		local s = DT.checkV3(size, 2, "FillWedge")
		local mat = checkTerrainMat(material, 3, "FillWedge")
		local sx, sy, sz = v3xyz(mk.V3vec(s))
		addShape(self, { kind = "box", d = cfData(cframe), hx = sx / 2, hy = sy / 2, hz = sz / 2, mat = mat })
	end
	function TR.FillBall(self, center, radius, material)
		terrSelf(self, "FillBall")
		local c = DT.checkV3(center, 1, "FillBall")
		radius = Util.checkNumber(radius, 2, "FillBall")
		local mat = checkTerrainMat(material, 3, "FillBall")
		local cx, cy, cz = v3xyz(mk.V3vec(c))
		addShape(self, { kind = "ball", cx = cx, cy = cy, cz = cz, r = radius, mat = mat })
	end
	function TR.FillCylinder(self, cframe, height, radius, material)
		terrSelf(self, "FillCylinder")
		Util.checkType(cframe, "CFrame", 1, "FillCylinder")
		height = Util.checkNumber(height, 2, "FillCylinder")
		radius = Util.checkNumber(radius, 3, "FillCylinder")
		local mat = checkTerrainMat(material, 4, "FillCylinder")
		addShape(self, { kind = "cyl", d = cfData(cframe), h = height / 2, r = radius, mat = mat })
	end
	function TR.FillRegion(self, region, resolution, material)
		terrSelf(self, "FillRegion")
		Util.checkType(region, "Region3", 1, "FillRegion")
		resolution = Util.checkNumber(resolution, 2, "FillRegion")
		local mat = checkTerrainMat(material, 3, "FillRegion")
		local ok = regionAligned(region, 4)
		if not ok then
			raise("Region has to be aligned to the grid (use Region3:ExpandToGrid)")
		end
		local mn, mx = DT.region3MinMax(region)
		local c = (mn + mx) / 2
		local sz = mx - mn
		addShape(self, {
			kind = "box",
			d = cfData(CF.new(c.x, c.y, c.z)),
			hx = sz.x / 2,
			hy = sz.y / 2,
			hz = sz.z / 2,
			mat = mat,
		})
	end
	function TR.Clear(self)
		terrSelf(self, "Clear")
		-- in place leeren (der Zustand wird mit den Clients geteilt)
		local st = terrainState(self)
		table.clear(st.shapes)
		table.clear(st.voxels)
		st.vcount = 0
		st.vmin, st.vmax = nil, nil
	end
	function TR.WriteVoxels(self, region, resolution, materials, occupancy)
		terrSelf(self, "WriteVoxels")
		Util.checkType(region, "Region3", 1, "WriteVoxels")
		resolution = Util.checkNumber(resolution, 2, "WriteVoxels")
		if resolution ~= 4 then
			raise("Resolution has to be 4")
		end
		if type(materials) ~= "table" then
			Util.badArg(3, "WriteVoxels", "table", materials)
		end
		if type(occupancy) ~= "table" then
			Util.badArg(4, "WriteVoxels", "table", occupancy)
		end
		local ok, x0, y0, z0, x1, y1, z1 = regionAligned(region, 4)
		if not ok then
			raise("Region has to be aligned to the grid (use Region3:ExpandToGrid)")
		end
		local nx, ny, nz = math.floor((x1 - x0) / 4 + 0.5), math.floor((y1 - y0) / 4 + 0.5), math.floor((z1 - z0) / 4 + 0.5)
		if #materials ~= nx or #occupancy ~= nx then
			raise("Materials/occupancy array size doesn't match region size")
		end
		local st = terrainState(self)
		st.seq += 1
		local seq = st.seq
		local bx, by, bz = math.floor(x0 / 4), math.floor(y0 / 4), math.floor(z0 / 4)
		for i = 1, nx do
			local mcol, ocol = materials[i], occupancy[i]
			if type(mcol) ~= "table" or type(ocol) ~= "table" or #mcol ~= ny or #ocol ~= ny then
				raise("Materials/occupancy array size doesn't match region size")
			end
			for j = 1, ny do
				local mrow, orow = mcol[j], ocol[j]
				if type(mrow) ~= "table" or type(orow) ~= "table" or #mrow ~= nz or #orow ~= nz then
					raise("Materials/occupancy array size doesn't match region size")
				end
				for k = 1, nz do
					local m = mrow[k]
					local o = orow[k]
					local it = Enum.coerce(m, "Material")
					if it == nil then
						raise("Invalid material in materials array")
					end
					if not TERRAIN_MATS[it.Name] then
						raise(fmt("Material %s is not a valid terrain material", it.Name))
					end
					if type(o) ~= "number" then
						raise("Invalid occupancy in occupancy array")
					end
					local key = vkey(bx + i - 1, by + j - 1, bz + k - 1)
					local old = st.voxels[key]
					if it.Name == "Air" or o <= 0 then
						if old then
							st.vcount -= 1
						end
						st.voxels[key] = { Enum.item("Material", "Air"), seq }
						if not old then
							st.vcount += 1
						end
					else
						if not old then
							st.vcount += 1
						end
						st.voxels[key] = { it, seq, o }
					end
				end
			end
		end
		st.vmin = st.vmin or { huge, huge, huge }
		st.vmax = st.vmax or { -huge, -huge, -huge }
		st.vmin = { min(st.vmin[1], x0), min(st.vmin[2], y0), min(st.vmin[3], z0) }
		st.vmax = { max(st.vmax[1], x1), max(st.vmax[2], y1), max(st.vmax[3], z1) }
	end
	function TR.ReadVoxels(self, region, resolution)
		terrSelf(self, "ReadVoxels")
		Util.checkType(region, "Region3", 1, "ReadVoxels")
		resolution = Util.checkNumber(resolution, 2, "ReadVoxels")
		if resolution ~= 4 then
			raise("Resolution has to be 4")
		end
		local ok, x0, y0, z0, x1, y1, z1 = regionAligned(region, 4)
		if not ok then
			raise("Region has to be aligned to the grid (use Region3:ExpandToGrid)")
		end
		local nx, ny, nz = math.floor((x1 - x0) / 4 + 0.5), math.floor((y1 - y0) / 4 + 0.5), math.floor((z1 - z0) / 4 + 0.5)
		if nx * ny * nz > 4194304 then
			raise("Region is too large")
		end
		local st = terrainState(self)
		local air = Enum.item("Material", "Air")
		local mats, occ = {}, {}
		for i = 1, nx do
			local mc, oc = table.create(ny), table.create(ny)
			for j = 1, ny do
				local mr, orr = table.create(nz), table.create(nz)
				for k = 1, nz do
					local m = terrainMaterialAt(st, x0 + (i - 0.5) * 4, y0 + (j - 0.5) * 4, z0 + (k - 0.5) * 4)
					mr[k] = m or air
					orr[k] = m and 1 or 0
				end
				mc[j], oc[j] = mr, orr
			end
			mats[i], occ[i] = mc, oc
		end
		mats.Size = mk.V3(nx, ny, nz)
		occ.Size = mk.V3(nx, ny, nz)
		return mats, occ
	end
	function TR.ReplaceMaterial(self, region, resolution, source, target)
		terrSelf(self, "ReplaceMaterial")
		Util.checkType(region, "Region3", 1, "ReplaceMaterial")
		checkTerrainMat(source, 3, "ReplaceMaterial")
		checkTerrainMat(target, 4, "ReplaceMaterial")
	end
	function TR.SetMaterialColor(self, material, color)
		terrSelf(self, "SetMaterialColor")
		local mat = checkTerrainMat(material, 1, "SetMaterialColor")
		Util.checkType(color, "Color3", 2, "SetMaterialColor")
		terrainState(self).colors[mat] = color
	end
	function TR.GetMaterialColor(self, material)
		terrSelf(self, "GetMaterialColor")
		local mat = checkTerrainMat(material, 1, "GetMaterialColor")
		return terrainState(self).colors[mat] or mk.C3(0.5, 0.5, 0.5)
	end
	function TR.CountCells(self)
		terrSelf(self, "CountCells")
		return terrainState(self).vcount
	end
	function TR.CellCenterToWorld(self, x, y, z)
		terrSelf(self, "CellCenterToWorld")
		return mk.V3(x * 4 + 2, y * 4 + 2, z * 4 + 2)
	end
	function TR.CellCornerToWorld(self, x, y, z)
		terrSelf(self, "CellCornerToWorld")
		return mk.V3(x * 4, y * 4, z * 4)
	end
	function TR.WorldToCell(self, p)
		terrSelf(self, "WorldToCell")
		local v = DT.checkV3(p, 1, "WorldToCell")
		local x, y, z = v3xyz(mk.V3vec(v))
		return mk.V3(math.floor(x / 4), math.floor(y / 4), math.floor(z / 4))
	end
	TR.WorldToCellPreferSolid = TR.WorldToCell
	TR.WorldToCellPreferEmpty = TR.WorldToCell
	Inst.define("Terrain", { methods = TR })

	-- =================================================================================================
	--  WorldRoot-Abfragen
	-- =================================================================================================
	local function terrainOf(ws)
		local M = getmt(ws)
		return M.ext and M.ext.terrain
	end

	--- Strahl (origin/direction als Vector3-Werte); Rückgabe RaycastResult oder nil
	local function raycast(ws, origin, direction, params, inflate, skipStartOverlap)
		local s = spatial(ws)
		local ox, oy, oz = v3xyz(origin)
		local dx, dy, dz = v3xyz(direction)
		local accept, _, ignoreWater = makeFilter(params)
		local x0, y0, z0 = min(ox, ox + dx), min(oy, oy + dy), min(oz, oz + dz)
		local x1, y1, z1 = max(ox, ox + dx), max(oy, oy + dy), max(oz, oz + dz)
		local inf = inflate or 0
		local cands = candidatesInAabb(s, x0 - inf, y0 - inf, z0 - inf, x1 + inf, y1 + inf, z1 + inf)
		local best, bestPart, bnx, bny, bnz = huge, nil, 0, 0, 0
		for _, p in cands do
			local M = getmt(p)
			if not M.destroyed and accept(p, M) then
				local t, nx, ny, nz = rayPart(M, ox, oy, oz, dx, dy, dz, inf)
				if t and t <= 1 and t < best then
					best, bestPart, bnx, bny, bnz = t, p, nx, ny, nz
				end
			end
		end
		local terrain = terrainOf(ws)
		if terrain and inf == 0 then
			local TM = getmt(terrain)
			if accept(terrain, TM) then
				local t, nx, ny, nz, mat = rayTerrain(terrain, ox, oy, oz, dx, dy, dz, ignoreWater)
				if t and t < best then
					local len = sqrt(dx * dx + dy * dy + dz * dz)
					return mk.RaycastResult(
						terrain,
						mk.V3(ox + dx * t, oy + dy * t, oz + dz * t),
						mk.V3(nx, ny, nz),
						mat,
						t * len
					)
				end
			end
		end
		if bestPart == nil then
			return nil
		end
		local len = sqrt(dx * dx + dy * dy + dz * dz)
		local BM = getmt(bestPart)
		local mat = BM.props.Material or Enum.item("Material", "Plastic")
		return mk.RaycastResult(
			bestPart,
			mk.V3(ox + dx * best, oy + dy * best, oz + dz * best),
			mk.V3(bnx, bny, bnz),
			mat,
			best * len
		)
	end
	W.raycast = raycast
	function W.raycastFor(ctx, origin, direction, ignore)
		local game = ctx and ctx.game
		local ws = game and Inst.findServiceRaw(game, "Workspace")
		if ws == nil then
			return nil
		end
		local params = DT.RaycastParams.new()
		if ignore then
			params.FilterDescendantsInstances = { ignore }
		end
		return raycast(ws, origin, direction, params)
	end

	local function checkDir(v, n, fname)
		local d = DT.checkV3(v, n, fname)
		return mk.V3vec(d)
	end

	local WR = {}
	function WR.Raycast(self, origin, direction, params)
		Inst.checkSelf(self, "Raycast")
		local o = checkDir(origin, 1, "Raycast")
		local d = checkDir(direction, 2, "Raycast")
		if params ~= nil then
			Util.checkType(params, "RaycastParams", 3, "Raycast")
		end
		if d.Magnitude > 15000 then
			d = d.Unit * 15000
		end
		return raycast(self, o, d, params)
	end
	function WR.Spherecast(self, position, radius, direction, params)
		Inst.checkSelf(self, "Spherecast")
		local o = checkDir(position, 1, "Spherecast")
		radius = Util.checkNumber(radius, 2, "Spherecast")
		local d = checkDir(direction, 3, "Spherecast")
		if params ~= nil then
			Util.checkType(params, "RaycastParams", 4, "Spherecast")
		end
		if radius > 256 then
			raise("Spherecast: radius must be at most 256")
		end
		if d.Magnitude > 1024 then
			d = d.Unit * 1024
		end
		return raycast(self, o, d, params, radius)
	end
	function WR.Blockcast(self, cframe, size, direction, params)
		Inst.checkSelf(self, "Blockcast")
		Util.checkType(cframe, "CFrame", 1, "Blockcast")
		local s = mk.V3vec(DT.checkV3(size, 2, "Blockcast"))
		local d = checkDir(direction, 3, "Blockcast")
		if params ~= nil then
			Util.checkType(params, "RaycastParams", 4, "Blockcast")
		end
		if d.Magnitude > 1024 then
			d = d.Unit * 1024
		end
		local inf = max(s.X, s.Y, s.Z) / 2
		return raycast(self, cframe.Position, d, params, inf)
	end
	function WR.Shapecast(self, part, direction, params)
		Inst.checkSelf(self, "Shapecast")
		local _, PM = Svc.checkInstance(part, 1, "Shapecast", "BasePart")
		local d = checkDir(direction, 2, "Shapecast")
		local s = sizeOf(PM)
		local p2 = params
		if p2 == nil then
			p2 = DT.RaycastParams.new()
		end
		local f = DT.paramFields(p2)
		local list = table.clone(f.FilterDescendantsInstances or {})
		if f.FilterType.Name ~= "Include" then
			list[#list + 1] = part
			p2 = DT.RaycastParams.new()
			p2.FilterType = f.FilterType
			p2.FilterDescendantsInstances = list
			p2.CollisionGroup = f.CollisionGroup
			p2.RespectCanCollide = f.RespectCanCollide
		end
		return raycast(self, part.Position, d, p2, max(s.X, s.Y, s.Z) / 2)
	end

	local function overlapCollect(ws, params, x0, y0, z0, x1, y1, z1, test)
		local s = spatial(ws)
		local accept = makeFilter(params, true)
		local maxParts = 0
		if params then
			maxParts = DT.paramFields(params).MaxParts or 0
		end
		local out = {}
		for _, p in candidatesInAabb(s, x0, y0, z0, x1, y1, z1) do
			local M = getmt(p)
			if not M.destroyed and accept(p, M) and test(M, p) then
				out[#out + 1] = p
				if maxParts > 0 and #out >= maxParts then
					break
				end
			end
		end
		return out
	end

	function WR.GetPartBoundsInBox(self, cframe, size, params)
		Inst.checkSelf(self, "GetPartBoundsInBox")
		Util.checkType(cframe, "CFrame", 1, "GetPartBoundsInBox")
		local s = mk.V3vec(DT.checkV3(size, 2, "GetPartBoundsInBox"))
		if params ~= nil then
			Util.checkType(params, "OverlapParams", 3, "GetPartBoundsInBox")
		end
		local sx, sy, sz = v3xyz(s)
		local box = obbOf(cframe, sx, sy, sz)
		local d = cfData(cframe)
		local hx = (abs(d[4]) * sx + abs(d[5]) * sy + abs(d[6]) * sz) / 2
		local hy = (abs(d[7]) * sx + abs(d[8]) * sy + abs(d[9]) * sz) / 2
		local hz = (abs(d[10]) * sx + abs(d[11]) * sy + abs(d[12]) * sz) / 2
		return overlapCollect(self, params, d[1] - hx, d[2] - hy, d[3] - hz, d[1] + hx, d[2] + hy, d[3] + hz, function(M)
			return obbOverlap(box, partObb(M))
		end)
	end
	function WR.GetPartBoundsInRadius(self, position, radius, params)
		Inst.checkSelf(self, "GetPartBoundsInRadius")
		local p = mk.V3vec(DT.checkV3(position, 1, "GetPartBoundsInRadius"))
		radius = Util.checkNumber(radius, 2, "GetPartBoundsInRadius")
		if params ~= nil then
			Util.checkType(params, "OverlapParams", 3, "GetPartBoundsInRadius")
		end
		local cx, cy, cz = v3xyz(p)
		return overlapCollect(self, params, cx - radius, cy - radius, cz - radius, cx + radius, cy + radius, cz + radius, function(M)
			return obbSphere(partObb(M), cx, cy, cz, radius)
		end)
	end
	function WR.GetPartsInPart(self, part, params)
		Inst.checkSelf(self, "GetPartsInPart")
		local _, PM = Svc.checkInstance(part, 1, "GetPartsInPart", "BasePart")
		if params ~= nil then
			Util.checkType(params, "OverlapParams", 2, "GetPartsInPart")
		end
		local box = partObb(PM)
		local x0, y0, z0, x1, y1, z1 = partAabb(PM)
		return overlapCollect(self, params, x0, y0, z0, x1, y1, z1, function(M, p)
			return p ~= part and obbOverlap(box, partObb(M))
		end)
	end
	function WR.ArePartsTouchingOthers(self, parts, overlapIgnored)
		Inst.checkSelf(self, "ArePartsTouchingOthers")
		if type(parts) ~= "table" then
			Util.badArg(1, "ArePartsTouchingOthers", "table", parts)
		end
		local set = {}
		for _, p in parts do
			set[p] = true
		end
		for _, p in parts do
			local PM = Inst.meta(p)
			if PM and PM.cls.isPart then
				for _, q in WR.GetPartsInPart(self, p) do
					if not set[q] then
						return true
					end
				end
			end
		end
		return false
	end

	local bulkModes = { FireAllEvents = true, FireCFrameChanged = true, FireNoEvents = true }
	function WR.BulkMoveTo(self, partList, cframeList, eventMode)
		Inst.checkSelf(self, "BulkMoveTo")
		if type(partList) ~= "table" then
			Util.badArg(1, "BulkMoveTo", "table", partList)
		end
		if type(cframeList) ~= "table" then
			Util.badArg(2, "BulkMoveTo", "table", cframeList)
		end
		local mode = "FireAllEvents"
		if eventMode ~= nil then
			local it = Enum.coerce(eventMode, "BulkMoveMode")
			if it == nil then
				Util.badArg(3, "BulkMoveTo", "Enum.BulkMoveMode", eventMode)
			end
			mode = it.Name
		end
		local n = #partList
		if #cframeList ~= n then
			raise("BulkMoveTo: partList and cframeList must have the same number of entries")
		end
		for i = 1, n do
			local p = partList[i]
			local PM = Inst.meta(p)
			if PM == nil or not PM.cls.isPart then
				raise("Unable to cast value to Objects")
			end
			if Util.typeof(cframeList[i]) ~= "CFrame" then
				raise("Unable to cast value to std::vector<CoordinateFrame>")
			end
		end
		for i = 1, n do
			local p = partList[i]
			local PM = getmt(p)
			local cf = cframeList[i]:Orthonormalize()
			if mode == "FireAllEvents" then
				Inst.Parts.setCFrame(p, cf, true)
			else
				local old = PM.props.CFrame
				if old == nil or old ~= cf then
					PM.props.CFrame = cf
					if mode == "FireCFrameChanged" then
						Inst.changed(p, PM, "CFrame")
					else
						Inst.notify("changed", p, "CFrame")
					end
				end
			end
		end
	end

	-- veraltete Strahl-API
	local function legacyRay(self, ray, list, include, fname, terrainCellsAreCubes, ignoreWater)
		Util.checkType(ray, "Ray", 1, fname)
		local params = DT.RaycastParams.new()
		if list ~= nil then
			if type(list) == "table" then
				params.FilterDescendantsInstances = list
			elseif Inst.is(list) then
				params.FilterDescendantsInstances = { list }
			end
		end
		params.FilterType = Enum.item("RaycastFilterType", include and "Include" or "Exclude")
		params.IgnoreWater = ignoreWater == true
		local o, d = ray.Origin, ray.Direction
		local res = raycast(self, o, d, params)
		if res == nil then
			return nil, o + d, DT.Vector3.zero, Enum.item("Material", "Air")
		end
		return res.Instance, res.Position, res.Normal, res.Material
	end
	function WR.FindPartOnRay(self, ray, ignore, a, b)
		Inst.checkSelf(self, "FindPartOnRay")
		return legacyRay(self, ray, ignore, false, "FindPartOnRay", a, b)
	end
	function WR.FindPartOnRayWithIgnoreList(self, ray, list, a, b)
		Inst.checkSelf(self, "FindPartOnRayWithIgnoreList")
		return legacyRay(self, ray, list, false, "FindPartOnRayWithIgnoreList", a, b)
	end
	function WR.FindPartOnRayWithWhitelist(self, ray, list, a)
		Inst.checkSelf(self, "FindPartOnRayWithWhitelist")
		return legacyRay(self, ray, list, true, "FindPartOnRayWithWhitelist", a)
	end
	local function regionParts(self, region, ignore, maxParts, fname)
		Util.checkType(region, "Region3", 1, fname)
		local mn, mx = DT.region3MinMax(region)
		local params = DT.OverlapParams.new()
		if ignore ~= nil then
			params.FilterDescendantsInstances = type(ignore) == "table" and ignore or { ignore }
		end
		params.MaxParts = maxParts or 20
		local c = (mn + mx) / 2
		local sz = mx - mn
		return WR.GetPartBoundsInBox(self, CF.new(c.x, c.y, c.z), mk.V3(sz.x, sz.y, sz.z), params)
	end
	function WR.FindPartsInRegion3(self, region, ignore, maxParts)
		Inst.checkSelf(self, "FindPartsInRegion3")
		return regionParts(self, region, ignore, maxParts, "FindPartsInRegion3")
	end
	function WR.FindPartsInRegion3WithIgnoreList(self, region, list, maxParts)
		Inst.checkSelf(self, "FindPartsInRegion3WithIgnoreList")
		return regionParts(self, region, list, maxParts, "FindPartsInRegion3WithIgnoreList")
	end
	function WR.IsRegion3Empty(self, region, ignore)
		Inst.checkSelf(self, "IsRegion3Empty")
		return #regionParts(self, region, ignore, 1, "IsRegion3Empty") == 0
	end
	-- Kollisionsgruppen-API am WorldRoot (neuere Roblox-API; gemeinsames Register mit PhysicsService)
	for _, m in {
		"RegisterCollisionGroup",
		"UnregisterCollisionGroup",
		"RenameCollisionGroup",
		"IsCollisionGroupRegistered",
		"CollisionGroupSetCollidable",
		"CollisionGroupsAreCollidable",
		"GetRegisteredCollisionGroups",
		"GetMaxCollisionGroups",
	} do
		WR[m] = PH[m]
	end
	Inst.define("WorldRoot", { methods = WR })

	-- Workspace-Eigenschaften
	Inst.define("Workspace", {
		methods = {
			GetServerTimeNow = function(self)
				Inst.checkSelf(self, "GetServerTimeNow")
				return Sched.unix()
			end,
		},
	})

	-- =================================================================================================
	--  Kamera
	-- =================================================================================================
	local function viewport(M)
		local ctx = Svc.ctxOf(M.self)
		if ctx and ctx.isClient then
			local vp = R.config.viewport or { 1280, 720 }
			return vp[1], vp[2]
		end
		return 1, 1
	end
	local function project(M, p)
		local cf = M.props.CFrame or CF.identity
		local w, h = viewport(M)
		local fov = math.rad(M.props.FieldOfView or 70)
		local tanY = math.tan(fov / 2)
		local aspect = w / h
		local lp = cf:PointToObjectSpace(p)
		local depth = -lp.Z
		local ndcX, ndcY
		if depth == 0 then
			ndcX, ndcY = 0, 0
		else
			ndcX = lp.X / (depth * tanY * aspect)
			ndcY = lp.Y / (depth * tanY)
		end
		local x = (ndcX + 1) / 2 * w
		local y = (1 - ndcY) / 2 * h
		local on = depth > 0 and x >= 0 and x <= w and y >= 0 and y <= h
		return x, y, depth, on
	end
	local function unproject(M, x, y, depth)
		local cf = M.props.CFrame or CF.identity
		local w, h = viewport(M)
		local fov = math.rad(M.props.FieldOfView or 70)
		local tanY = math.tan(fov / 2)
		local aspect = w / h
		local ndcX = x / w * 2 - 1
		local ndcY = 1 - y / h * 2
		local dirL = mk.V3(ndcX * tanY * aspect, ndcY * tanY, -1).Unit
		local dir = cf:VectorToWorldSpace(dirL)
		local origin = cf.Position + dir * (depth or 0)
		return DT.Ray.new(origin, dir)
	end
	local function inset()
		return R.config.topInset or 58
	end
	local CAM = {}
	function CAM.WorldToViewportPoint(self, p)
		local M = Inst.checkSelf(self, "WorldToViewportPoint")
		local v = mk.V3vec(DT.checkV3(p, 1, "WorldToViewportPoint"))
		local x, y, depth, on = project(M, v)
		return mk.V3(x, y, depth), on
	end
	function CAM.WorldToScreenPoint(self, p)
		local M = Inst.checkSelf(self, "WorldToScreenPoint")
		local v = mk.V3vec(DT.checkV3(p, 1, "WorldToScreenPoint"))
		local x, y, depth, on = project(M, v)
		return mk.V3(x, y - inset(), depth), on
	end
	function CAM.ViewportPointToRay(self, x, y, depth)
		local M = Inst.checkSelf(self, "ViewportPointToRay")
		x = Util.checkNumber(x, 1, "ViewportPointToRay")
		y = Util.checkNumber(y, 2, "ViewportPointToRay")
		depth = Util.optNumber(depth, 3, "ViewportPointToRay", 0)
		return unproject(M, x, y, depth)
	end
	function CAM.ScreenPointToRay(self, x, y, depth)
		local M = Inst.checkSelf(self, "ScreenPointToRay")
		x = Util.checkNumber(x, 1, "ScreenPointToRay")
		y = Util.checkNumber(y, 2, "ScreenPointToRay")
		depth = Util.optNumber(depth, 3, "ScreenPointToRay", 0)
		return unproject(M, x, y + inset(), depth)
	end
	function CAM.GetRenderCFrame(self)
		local M = Inst.checkSelf(self, "GetRenderCFrame")
		return M.props.CFrame or CF.identity
	end
	function CAM.GetRoll(self)
		local M = Inst.checkSelf(self, "GetRoll")
		local _, _, z = (M.props.CFrame or CF.identity):ToOrientation()
		return z
	end
	function CAM.SetRoll(self, roll)
		Inst.checkSelf(self, "SetRoll")
		Util.checkNumber(roll, 1, "SetRoll")
	end
	function CAM.GetPartsObscuringTarget(self, castPoints, ignoreList)
		Inst.checkSelf(self, "GetPartsObscuringTarget")
		if type(castPoints) ~= "table" then
			Util.badArg(1, "GetPartsObscuringTarget", "table", castPoints)
		end
		return {}
	end
	function CAM.GetLargestCutoffDistance(self, ignoreList)
		Inst.checkSelf(self, "GetLargestCutoffDistance")
		return 0
	end
	function CAM.ZoomToExtents(self, boundingBoxCFrame, boundingBoxSize)
		local M = Inst.checkSelf(self, "ZoomToExtents")
		Util.checkType(boundingBoxCFrame, "CFrame", 1, "ZoomToExtents")
		local s = mk.V3vec(DT.checkV3(boundingBoxSize, 2, "ZoomToExtents"))
		local cf = M.props.CFrame or CF.identity
		local target = boundingBoxCFrame.Position
		local dist = s.Magnitude
		Inst.setProp(self, "CFrame", CF.lookAt(target - cf.LookVector * dist, target))
	end
	function CAM.Interpolate(self, endPos, endFocus, duration)
		Inst.checkSelf(self, "Interpolate")
		Util.checkType(endPos, "CFrame", 1, "Interpolate")
		Util.checkType(endFocus, "CFrame", 2, "Interpolate")
		Inst.setProp(self, "CFrame", endPos)
		Inst.setProp(self, "Focus", endFocus)
		Sched.addTimer(Sched.now + (tonumber(duration) or 0), function()
			Inst.fire(self, "InterpolationFinished")
		end)
	end
	Inst.define("Camera", {
		methods = CAM,
		props = {
			ViewportSize = {
				get = function(u, M)
					local w, h = viewport(M)
					return mk.V2(w, h)
				end,
			},
			NearPlaneZ = {
				get = function()
					return -0.1
				end,
			},
		},
	})

	-- Standard-Kamerasteuerung (Client): CameraType Custom/Follow folgt dem CameraSubject
	local camState = setmetatable({}, { __mode = "k" })
	function W.updateClientCamera(ctx)
		local game = ctx.game
		if game == nil then
			return
		end
		local ws = Inst.findServiceRaw(game, "Workspace")
		local cam = ws and ws.CurrentCamera
		if cam == nil then
			return
		end
		local CM = getmt(cam)
		local ct = CM.props.CameraType
		local tname = ct and ct.Name or "Fixed"
		local lp = getmt(game).ext.localPlayer
		local subject = CM.props.CameraSubject
		if subject ~= nil and getmt(subject).destroyed then
			subject = nil
		end
		if lp ~= nil then
			local ch = getmt(lp).props.Character
			local hum = ch and not getmt(ch).destroyed and Inst.findChild(ch, "Humanoid")
			local st = camState[cam]
			if st == nil then
				st = {}
				camState[cam] = st
			end
			if hum and st.lastChar ~= ch then
				st.lastChar = ch
				if subject == nil or not Inst.isAncestor(ch, subject) then
					Inst.storeProp(cam, "CameraSubject", hum)
					subject = hum
				end
				if tname == "Fixed" or ct == nil then
					Inst.storeProp(cam, "CameraType", Enum.item("CameraType", "Custom"))
					tname = "Custom"
				end
			end
		end
		if subject == nil or not (tname == "Custom" or tname == "Follow" or tname == "Track" or tname == "Attach" or tname == "Watch") then
			return
		end
		local SM = getmt(subject)
		local focusPart
		if SM.cls.isA.Humanoid then
			local model = SM.parent
			focusPart = model and Inst.findChild(model, "HumanoidRootPart") or (model and Inst.findChild(model, "Head"))
		elseif SM.cls.isPart then
			focusPart = subject
		elseif SM.cls.isA.Model then
			local pp = subject.PrimaryPart
			focusPart = pp
		end
		if focusPart == nil or getmt(focusPart).destroyed then
			return
		end
		local focus = focusPart.Position + mk.V3(0, 1.5, 0)
		local cur = CM.props.CFrame or CF.identity
		local look = cur.LookVector
		if look.Y > -0.05 or look.Y < -0.95 then
			look = mk.V3(0, -0.35, -1).Unit
		end
		local zoom = 12.5
		local lp2 = lp and getmt(lp).props
		if lp2 and lp2.CameraMaxZoomDistance then
			zoom = math.min(zoom, lp2.CameraMaxZoomDistance)
		end
		local pos = focus - look * zoom
		local newCF = CF.lookAt(pos, focus)
		if cur ~= newCF then
			Inst.setProp(cam, "CFrame", newCF)
		end
		local f = CF.new(focus)
		if CM.props.Focus ~= f then
			Inst.setProp(cam, "Focus", f)
		end
	end
	Sched.addHook("input", function()
		for _, g in Svc.games do
			local ctx = g.ctx
			if ctx and ctx.isClient and not ctx.closed then
				local ok, err = xpcall(W.updateClientCamera, debug.traceback, ctx)
				if not ok then
					Report.harnessError("Kamera-Steuerung fehlgeschlagen: " .. tostring(err))
				end
			end
		end
	end, "DefaultCamera")
end
