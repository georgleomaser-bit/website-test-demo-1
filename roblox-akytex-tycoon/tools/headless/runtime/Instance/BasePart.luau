--!nocheck
-- =====================================================================
--  Headless-Harness · PVInstance / BasePart / Model / Gelenke
--
--  BasePart: CFrame ist die Wahrheit; Position/Orientation/Rotation werden daraus abgeleitet (Grad, YXZ bzw. XYZ).
--  Size wird auf [0.001, 2048] geklemmt. BrickColor <-> Color gekoppelt. Mass/GetMass aus Material-Dichte bzw.
--  CustomPhysicalProperties und Form (Block/Kugel/Zylinder/Keil). SetNetworkOwner prüft wie Roblox
--  (Workspace-Nachfahre, nicht verankert / nicht an verankertes Teil geschweißt, nur Server).
--
--  Gelenke (nur innerhalb von Workspace, wie Roblox' Physik): WeldConstraint (Versatz beim Aktivwerden gemerkt) und
--  JointInstance (Weld/Motor6D/…: Part1 = Part0 * C0 * Transform * C1:Inverse()).
--   - part.CFrame = … bewegt die ganze Baugruppe starr mit (Roblox-Doku "Repositioning Behavior").
--   - part.Position/Orientation = … bewegt nur das Teil; WeldConstraint-Versätze werden neu berechnet.
--   - Änderungen an C0/C1/Transform/Part0/Part1/Enabled lösen die Baugruppe von der Wurzel aus neu auf
--     (verankerte Teile werden nie verschoben).
--  Model: PrimaryPart (nil, wenn nicht mehr Nachfahre), WorldPivot, GetPivot/PivotTo, GetBoundingBox,
--  GetExtentsSize, MoveTo, TranslateBy, ScaleTo/GetScale, Set/GetPrimaryPartCFrame (mit Roblox-Fehlern).
--  Harness: Inst.Parts.setCFrame(part, cf, propagate), Inst.Parts.simulateTouch(a, b), Inst.Parts.inWorkspace(p)
-- =====================================================================
return function(R, Inst)
	local Util = R.Util
	local DT = R.DT
	local Enum = R.Enum
	local Report = R.Report
	local raise = Util.raise
	local getmt = getmetatable
	local fmt = string.format
	local mk = DT.make
	local rad, deg = math.rad, math.deg

	local Parts = {}
	Inst.Parts = Parts

	local function ext(M)
		local e = M.ext
		if e == nil then
			e = {}
			M.ext = e
		end
		return e
	end

	local function cfOf(M)
		local v = M.props.CFrame
		if v == nil then
			return DT.CFrame.identity
		end
		return v
	end
	Parts.cfOf = cfOf

	local function inWorkspace(u)
		local p = getmt(u).parent
		while p do
			local PM = getmt(p)
			if PM.cls.isA.Workspace then
				return true
			end
			p = PM.parent
		end
		return false
	end
	Parts.inWorkspace = inWorkspace

	-- =================================================================================================
	--  Gelenk-Register
	-- =================================================================================================
	local function jointsOf(M)
		local e = M.ext
		return e and e.joints
	end
	local function registerJoint(part, joint)
		if part == nil then
			return
		end
		local e = ext(getmt(part))
		e.joints = e.joints or {}
		if not table.find(e.joints, joint) then
			e.joints[#e.joints + 1] = joint
		end
	end
	local function unregisterJoint(part, joint)
		if part == nil then
			return
		end
		local js = jointsOf(getmt(part))
		if js then
			local i = table.find(js, joint)
			if i then
				table.remove(js, i)
			end
		end
	end

	local function jointActive(jM)
		if jM.destroyed then
			return false
		end
		local en = jM.props.Enabled
		if en == false then
			return false
		end
		local p0, p1 = jM.props.Part0, jM.props.Part1
		return p0 ~= nil and p1 ~= nil and p0 ~= p1
	end

	-- Nachbarn eines Teils über aktive Gelenke: Liste {joint, other, jM}
	local function neighbours(part)
		local js = jointsOf(getmt(part))
		local out = {}
		if js == nil then
			return out
		end
		for _, j in js do
			local jM = getmt(j)
			if jointActive(jM) then
				local p0, p1 = jM.props.Part0, jM.props.Part1
				local other = (p0 == part and p1) or (p1 == part and p0) or nil
				if other ~= nil and not getmt(other).destroyed and inWorkspace(other) then
					out[#out + 1] = { j, other, jM }
				end
			end
		end
		return out
	end

	local function assembly(part)
		local seen = { [part] = true }
		local list = { part }
		local i = 1
		while i <= #list do
			for _, nb in neighbours(list[i]) do
				local o = nb[2]
				if not seen[o] then
					seen[o] = true
					list[#list + 1] = o
				end
			end
			i += 1
		end
		return list
	end
	Parts.assembly = assembly

	local function isAnchored(u)
		return getmt(u).props.Anchored == true
	end

	local function volume(M)
		local size = M.props.Size or Inst.defaultValue(M.self, "Size")
		local x, y, z = DT.v3xyz(size)
		local shape = M.props.Shape
		local cls = M.cls.name
		if cls == "WedgePart" then
			return x * y * z / 2
		elseif cls == "CornerWedgePart" then
			return x * y * z / 3
		end
		if shape ~= nil then
			local n = shape.Name
			if n == "Ball" then
				local r = math.min(x, y, z) / 2
				return 4 / 3 * math.pi * r * r * r
			elseif n == "Cylinder" then
				local r = math.min(y, z) / 2
				return math.pi * r * r * x
			elseif n == "Wedge" then
				return x * y * z / 2
			elseif n == "CornerWedge" then
				return x * y * z / 3
			end
		end
		return x * y * z
	end

	local function density(M)
		local cpp = M.props.CustomPhysicalProperties
		if cpp ~= nil then
			return cpp.Density
		end
		local mat = M.props.Material
		return DT.materialDensity(mat and mat.Name or "Plastic")
	end

	local function massOf(M)
		return Util.f32(density(M) * volume(M))
	end
	Parts.massOf = function(u)
		return massOf(getmt(u))
	end

	local function rootOf(list)
		local best, bestScore = list[1], -math.huge
		for _, p in list do
			local PM = getmt(p)
			local score
			if PM.props.Anchored == true then
				score = 1e30
			else
				score = (PM.props.RootPriority or 0) * 1e20 + volume(PM)
			end
			if score > bestScore then
				best, bestScore = p, score
			end
		end
		return best
	end
	Parts.assemblyRoot = function(part)
		return rootOf(assembly(part))
	end

	-- Teil-CFrame setzen und Änderungen melden (ohne Baugruppen-Logik)
	local function storeCF(u, M, cf)
		local old = M.props.CFrame
		if old ~= nil and old == cf then
			return
		end
		local oldPos = old and old.Position
		M.props.CFrame = cf
		Inst.changed(u, M, "CFrame")
		if oldPos == nil or oldPos ~= cf.Position then
			Inst.changed(u, M, "Position")
		end
		if old == nil or old.Rotation ~= cf.Rotation then
			Inst.changed(u, M, "Orientation")
			Inst.changed(u, M, "Rotation")
		end
	end
	Parts.storeCF = function(u, cf)
		storeCF(u, getmt(u), cf)
	end

	-- Zielposition des Nachbarn über ein Gelenk
	local function relation(from, jM, to, fromCF)
		local cls = jM.cls
		if cls.isA.WeldConstraint then
			local off = jM.ext and jM.ext.offset
			if off == nil then
				return nil
			end
			if jM.props.Part0 == from then
				return fromCF * off
			else
				return fromCF * off:Inverse()
			end
		end
		-- JointInstance: Part1 = Part0 * C0 * T * C1^-1
		local c0 = jM.props.C0 or DT.CFrame.identity
		local c1 = jM.props.C1 or DT.CFrame.identity
		local t = jM.props.Transform
		local mid = t and (c0 * t) or c0
		if jM.props.Part0 == from then
			return fromCF * mid * c1:Inverse()
		else
			return fromCF * c1 * mid:Inverse()
		end
	end

	-- Baugruppe ab 'start' (mit fester CFrame) per Breitensuche auflösen; verankerte Teile bleiben stehen
	local function solveFrom(start, keepAnchored)
		local seen = { [start] = true }
		local queue = { start }
		local i = 1
		while i <= #queue do
			local cur = queue[i]
			i += 1
			local curCF = cfOf(getmt(cur))
			for _, nb in neighbours(cur) do
				local j, other, jM = nb[1], nb[2], nb[3]
				if not seen[other] then
					seen[other] = true
					local OM = getmt(other)
					if not (keepAnchored and OM.props.Anchored == true) then
						local target = relation(cur, jM, other, curCF)
						if target then
							storeCF(other, OM, target)
						end
					end
					queue[#queue + 1] = other
				end
			end
		end
	end

	local function captureWeldOffset(jM)
		local p0, p1 = jM.props.Part0, jM.props.Part1
		if p0 and p1 then
			ext(jM).offset = cfOf(getmt(p0)):Inverse() * cfOf(getmt(p1))
		end
	end

	local function resolveAssembly(part)
		if not inWorkspace(part) then
			return
		end
		local list = assembly(part)
		if #list < 2 then
			return
		end
		local root = rootOf(list)
		solveFrom(root, true)
	end
	Parts.resolveAssembly = resolveAssembly

	--- CFrame eines Teils setzen; propagate = Baugruppe starr mitbewegen (wie Skript-Zuweisung an .CFrame)
	local function setCFrame(u, M, cf, propagate)
		storeCF(u, M, cf)
		if propagate and jointsOf(M) and #M.ext.joints > 0 and inWorkspace(u) then
			solveFrom(u, false)
		end
	end
	Parts.setCFrame = function(u, cf, propagate)
		setCFrame(u, getmt(u), cf, propagate)
	end

	-- nach Bewegung eines einzelnen Teils (Position/Orientation): WeldConstraint-Versätze neu, Joints neu lösen
	local function afterSingleMove(u, M)
		local js = jointsOf(M)
		if not js or #js == 0 or not inWorkspace(u) then
			return
		end
		local needSolve = false
		for _, j in js do
			local jM = getmt(j)
			if jointActive(jM) then
				if jM.cls.isA.WeldConstraint then
					captureWeldOffset(jM)
				else
					needSolve = true
				end
			end
		end
		if needSolve then
			resolveAssembly(u)
		end
	end

	-- =================================================================================================
	--  BasePart
	-- =================================================================================================
	local function orthonormal(cf)
		return cf:Orthonormalize()
	end

	local function clampSize(v)
		local x, y, z = DT.v3xyz(v)
		local function c(a)
			if a ~= a then
				return 0.001
			end
			return math.clamp(a, 0.001, 2048)
		end
		return mk.V3(c(x), c(y), c(z))
	end

	local BP = {}
	function BP.GetMass(self)
		local M = Inst.checkSelf(self, "GetMass")
		return massOf(M)
	end
	function BP.GetRootPart(self)
		Inst.checkSelf(self, "GetRootPart")
		return rootOf(assembly(self))
	end
	function BP.GetConnectedParts(self, recursive)
		Inst.checkSelf(self, "GetConnectedParts")
		if recursive then
			local list = assembly(self)
			return list
		end
		local out = { self }
		for _, nb in neighbours(self) do
			if not table.find(out, nb[2]) then
				out[#out + 1] = nb[2]
			end
		end
		return out
	end
	function BP.GetJoints(self)
		local M = Inst.checkSelf(self, "GetJoints")
		local js = jointsOf(M)
		return js and table.clone(js) or {}
	end
	function BP.GetNoCollisionConstraints(self)
		Inst.checkSelf(self, "GetNoCollisionConstraints")
		return {}
	end
	function BP.BreakJoints(self)
		local M = Inst.checkSelf(self, "BreakJoints")
		local js = jointsOf(M)
		if js then
			for _, j in table.clone(js) do
				Inst.destroy(j)
			end
		end
	end
	function BP.MakeJoints(self)
		Inst.checkSelf(self, "MakeJoints")
	end
	BP.ApplyImpulse = function(self, impulse)
		Inst.checkSelf(self, "ApplyImpulse")
		Util.checkType(impulse, "Vector3", 1, "ApplyImpulse")
	end
	BP.ApplyAngularImpulse = function(self, impulse)
		Inst.checkSelf(self, "ApplyAngularImpulse")
		Util.checkType(impulse, "Vector3", 1, "ApplyAngularImpulse")
	end
	BP.ApplyImpulseAtPosition = function(self, impulse, position)
		Inst.checkSelf(self, "ApplyImpulseAtPosition")
		Util.checkType(impulse, "Vector3", 1, "ApplyImpulseAtPosition")
		Util.checkType(position, "Vector3", 2, "ApplyImpulseAtPosition")
	end
	function BP.GetVelocityAtPosition(self, position)
		Inst.checkSelf(self, "GetVelocityAtPosition")
		Util.checkType(position, "Vector3", 1, "GetVelocityAtPosition")
		return self.AssemblyLinearVelocity
	end
	function BP.IsGrounded(self)
		Inst.checkSelf(self, "IsGrounded")
		for _, p in assembly(self) do
			if isAnchored(p) then
				return true
			end
		end
		return false
	end
	function BP.CanCollideWith(self, part)
		local M = Inst.checkSelf(self, "CanCollideWith")
		local OM = Inst.meta(part)
		if OM == nil or not OM.cls.isPart then
			Util.badArg(1, "CanCollideWith", "BasePart", part)
		end
		local function cc(X)
			local v = X.props.CanCollide
			if v == nil then
				return true
			end
			return v
		end
		if Inst.collisionGroupsCollide then
			return cc(M)
				and cc(OM)
				and Inst.collisionGroupsCollide(
					M.props.CollisionGroup or "Default",
					OM.props.CollisionGroup or "Default"
				)
		end
		return cc(M) and cc(OM)
	end

	-- Netzwerk-Besitz
	local function ownershipCheck(self, M, fname)
		local ctx = R.Sched.ctx()
		if ctx.isClient then
			raise("Network Ownership API can only be called from the server")
		end
		if not inWorkspace(self) then
			raise("Can only call Network Ownership API on a part that is descendent of Workspace")
		end
		for _, p in assembly(self) do
			if isAnchored(p) then
				raise("Network Ownership API cannot be called on Anchored parts or parts welded to Anchored parts.")
			end
		end
	end
	function BP.SetNetworkOwner(self, player)
		local M = Inst.checkSelf(self, "SetNetworkOwner")
		if player ~= nil then
			local PM = Inst.meta(player)
			if PM == nil or not PM.cls.isA.Player then
				Util.badArg(1, "SetNetworkOwner", "Player", player)
			end
		end
		ownershipCheck(self, M, "SetNetworkOwner")
		for _, p in assembly(self) do
			local e = ext(getmt(p))
			e.networkOwner = player
			e.networkAuto = false
		end
	end
	function BP.SetNetworkOwnershipAuto(self)
		local M = Inst.checkSelf(self, "SetNetworkOwnershipAuto")
		ownershipCheck(self, M, "SetNetworkOwnershipAuto")
		for _, p in assembly(self) do
			local e = ext(getmt(p))
			e.networkOwner = nil
			e.networkAuto = true
		end
	end
	function BP.GetNetworkOwner(self)
		local M = Inst.checkSelf(self, "GetNetworkOwner")
		ownershipCheck(self, M, "GetNetworkOwner")
		return M.ext and M.ext.networkOwner or nil
	end
	function BP.GetNetworkOwnershipAuto(self)
		local M = Inst.checkSelf(self, "GetNetworkOwnershipAuto")
		ownershipCheck(self, M, "GetNetworkOwnershipAuto")
		return not (M.ext and M.ext.networkAuto == false)
	end
	function BP.CanSetNetworkOwnership(self)
		Inst.checkSelf(self, "CanSetNetworkOwnership")
		if not inWorkspace(self) then
			return false, "Can only call Network Ownership API on a part that is descendent of Workspace"
		end
		for _, p in assembly(self) do
			if isAnchored(p) then
				return false, "Cannot change NetworkOwnership on Anchored parts or parts welded to Anchored parts"
			end
		end
		return true, nil
	end

	-- Überlappung (orientierte Boxen grob über AABB)
	local function aabb(M)
		local cf = cfOf(M)
		local size = M.props.Size or Inst.defaultValue(M.self, "Size")
		local sx, sy, sz = DT.v3xyz(size)
		local d = DT.cfData(cf)
		local hx = (math.abs(d[4]) * sx + math.abs(d[5]) * sy + math.abs(d[6]) * sz) / 2
		local hy = (math.abs(d[7]) * sx + math.abs(d[8]) * sy + math.abs(d[9]) * sz) / 2
		local hz = (math.abs(d[10]) * sx + math.abs(d[11]) * sy + math.abs(d[12]) * sz) / 2
		return d[1] - hx, d[2] - hy, d[3] - hz, d[1] + hx, d[2] + hy, d[3] + hz
	end
	Parts.aabb = function(u)
		return aabb(getmt(u))
	end
	function BP.GetTouchingParts(self)
		local M = Inst.checkSelf(self, "GetTouchingParts")
		local out = {}
		local dm = Inst.dataModelOf(self)
		if dm == nil or not inWorkspace(self) then
			return out
		end
		local ws = Inst.findServiceRaw and Inst.findServiceRaw(dm, "Workspace")
		if ws == nil then
			return out
		end
		local ax0, ay0, az0, ax1, ay1, az1 = aabb(M)
		for _, d in Inst.descendants(ws) do
			local DM = getmt(d)
			if d ~= self and DM.cls.isPart then
				local bx0, by0, bz0, bx1, by1, bz1 = aabb(DM)
				if ax0 < bx1 and ax1 > bx0 and ay0 < by1 and ay1 > by0 and az0 < bz1 and az1 > bz0 then
					out[#out + 1] = d
				end
			end
		end
		return out
	end
	function BP.GetClosestPointOnSurface(self, position)
		local M = Inst.checkSelf(self, "GetClosestPointOnSurface")
		local p = DT.checkV3(position, 1, "GetClosestPointOnSurface")
		local cf = cfOf(M)
		local lp = cf:PointToObjectSpace(mk.V3vec(p))
		local sx, sy, sz = DT.v3xyz(M.props.Size or Inst.defaultValue(self, "Size"))
		local x, y, z = DT.v3xyz(lp)
		local cx, cy, cz =
			math.clamp(x, -sx / 2, sx / 2), math.clamp(y, -sy / 2, sy / 2), math.clamp(z, -sz / 2, sz / 2)
		return cf:PointToWorldSpace(mk.V3(cx, cy, cz))
	end
	function BP.Resize(self, normalId, delta)
		local M = Inst.checkSelf(self, "Resize")
		local face = Enum.coerce(normalId, "NormalId")
		if not face then
			Util.badArg(1, "Resize", "Enum.NormalId", normalId)
		end
		delta = Util.checkNumber(delta, 2, "Resize")
		local sx, sy, sz = DT.v3xyz(M.props.Size or Inst.defaultValue(self, "Size"))
		local n = face.Name
		local axis = (n == "Right" or n == "Left") and "x" or (n == "Top" or n == "Bottom") and "y" or "z"
		local sign = (n == "Right" or n == "Top" or n == "Back") and 1 or -1
		local nx, ny, nz = sx, sy, sz
		if axis == "x" then
			nx = math.max(sx + delta, 0.001)
		elseif axis == "y" then
			ny = math.max(sy + delta, 0.001)
		else
			nz = math.max(sz + delta, 0.001)
		end
		local grow = (axis == "x" and nx - sx) or (axis == "y" and ny - sy) or (nz - sz)
		local off = mk.V3(
			axis == "x" and grow / 2 * sign or 0,
			axis == "y" and grow / 2 * sign or 0,
			axis == "z" and grow / 2 * sign or 0
		)
		Inst.storeProp(self, "Size", clampSize(mk.V3(nx, ny, nz)))
		setCFrame(self, M, cfOf(M) * DT.CFrame.new(off), false)
		return true
	end
	-- PVInstance-Teil
	function BP.GetPivot(self)
		local M = Inst.checkSelf(self, "GetPivot")
		return cfOf(M) * (M.props.PivotOffset or DT.CFrame.identity)
	end
	function BP.PivotTo(self, cf)
		local M = Inst.checkSelf(self, "PivotTo")
		Util.checkType(cf, "CFrame", 1, "PivotTo")
		local off = M.props.PivotOffset or DT.CFrame.identity
		setCFrame(self, M, cf * off:Inverse(), true)
	end

	Inst.define("BasePart", {
		props = {
			CFrame = {
				get = function(_, M)
					return cfOf(M)
				end,
				set = function(u, M, v)
					setCFrame(u, M, orthonormal(v), true)
				end,
			},
			Position = {
				get = function(_, M)
					return cfOf(M).Position
				end,
				set = function(u, M, v)
					local cf = cfOf(M)
					storeCF(u, M, cf.Rotation + v)
					afterSingleMove(u, M)
				end,
			},
			Orientation = {
				get = function(_, M)
					local x, y, z = cfOf(M):ToOrientation()
					return mk.V3(deg(x), deg(y), deg(z))
				end,
				set = function(u, M, v)
					local x, y, z = DT.v3xyz(v)
					local cf = cfOf(M)
					storeCF(u, M, DT.CFrame.fromOrientation(rad(x), rad(y), rad(z)) + cf.Position)
					afterSingleMove(u, M)
				end,
			},
			Rotation = {
				get = function(_, M)
					local x, y, z = cfOf(M):ToEulerAnglesXYZ()
					return mk.V3(deg(x), deg(y), deg(z))
				end,
				set = function(u, M, v)
					local x, y, z = DT.v3xyz(v)
					local cf = cfOf(M)
					storeCF(u, M, DT.CFrame.Angles(rad(x), rad(y), rad(z)) + cf.Position)
					afterSingleMove(u, M)
				end,
			},
			Size = {
				set = function(u, M, v)
					Inst.storeProp(u, "Size", clampSize(v))
				end,
			},
			BrickColor = {
				get = function(u, M)
					local c = M.props.Color or Inst.defaultValue(u, "Color")
					return DT.closestBrickColor(c)
				end,
				set = function(u, M, v)
					Inst.storeProp(u, "Color", v.Color)
					Inst.changed(u, M, "BrickColor")
				end,
			},
			Mass = {
				get = function(_, M)
					return massOf(M)
				end,
			},
			AssemblyMass = {
				get = function(u, M)
					local list = assembly(u)
					local root = rootOf(list)
					local total = 0
					for _, p in list do
						local PM = getmt(p)
						if p == root or PM.props.Massless ~= true then
							total += massOf(PM)
						end
					end
					return Util.f32(total)
				end,
			},
			AssemblyRootPart = {
				get = function(u)
					return rootOf(assembly(u))
				end,
			},
			AssemblyCenterOfMass = {
				get = function(u, M)
					return cfOf(M).Position
				end,
			},
			CenterOfMass = {
				get = function(u, M)
					return cfOf(M).Position
				end,
			},
			ExtentsCFrame = {
				get = function(_, M)
					return cfOf(M)
				end,
			},
			ExtentsSize = {
				get = function(u, M)
					return M.props.Size or Inst.defaultValue(u, "Size")
				end,
			},
			CurrentPhysicalProperties = {
				get = function(_, M)
					local cpp = M.props.CustomPhysicalProperties
					if cpp then
						return cpp
					end
					local mat = M.props.Material
					return DT.PhysicalProperties.new(mat or Enum.item("Material", "Plastic"))
				end,
			},
		},
		methods = BP,
	})

	-- =================================================================================================
	--  Gelenk-Klassen
	-- =================================================================================================
	local function jointChanged(u, M, prop)
		if prop == "Part0" or prop == "Part1" then
			local e = ext(M)
			-- altes Paar abmelden, neues anmelden
			if e.p0 ~= M.props.Part0 then
				unregisterJoint(e.p0, u)
			end
			if e.p1 ~= M.props.Part1 then
				unregisterJoint(e.p1, u)
			end
			e.p0, e.p1 = M.props.Part0, M.props.Part1
			registerJoint(e.p0, u)
			registerJoint(e.p1, u)
			if M.cls.isA.WeldConstraint then
				e.offset = nil
				if jointActive(M) and inWorkspace(e.p0) and inWorkspace(e.p1) then
					captureWeldOffset(M)
				end
			elseif jointActive(M) then
				resolveAssembly(e.p0)
			end
		elseif prop == "Enabled" then
			if M.cls.isA.WeldConstraint then
				if jointActive(M) then
					captureWeldOffset(M)
				end
			elseif jointActive(M) then
				resolveAssembly(M.props.Part0)
			end
		elseif prop == "C0" or prop == "C1" or prop == "Transform" then
			if jointActive(M) then
				resolveAssembly(M.props.Part0)
			end
		end
	end
	local jointTotal = 0
	local function activateJoint(j, seenRoots)
		local jM = getmt(j)
		if not jointActive(jM) then
			return
		end
		local p0, p1 = jM.props.Part0, jM.props.Part1
		if not (inWorkspace(p0) and inWorkspace(p1)) then
			return
		end
		if jM.cls.isA.WeldConstraint then
			if not (jM.ext and jM.ext.offset) then
				captureWeldOffset(jM)
			end
		elseif not seenRoots[p0] then
			for _, p in assembly(p0) do
				seenRoots[p] = true
			end
			resolveAssembly(p0)
		end
	end
	local function isJoint(M)
		return M.cls.isA.WeldConstraint or M.cls.isA.JointInstance
	end
	Inst.observe("reparented", function(u, old, new)
		if jointTotal == 0 then
			return
		end
		local nowIn = new ~= nil and (getmt(u).cls.isA.Workspace or inWorkspace(u))
		local wasIn = false
		if old ~= nil then
			local OM = getmt(old)
			wasIn = OM.cls.isA.Workspace or inWorkspace(old)
		end
		if nowIn == wasIn then
			return
		end
		local seenRoots = {}
		Inst.forSubtree(u, function(x)
			local XM = getmt(x)
			if isJoint(XM) then
				if nowIn then
					activateJoint(x, seenRoots)
				elseif XM.cls.isA.WeldConstraint and XM.ext then
					XM.ext.offset = nil -- außerhalb von Workspace inaktiv; beim Wiedereintritt neu erfassen
				end
			elseif XM.cls.isPart and XM.ext and XM.ext.joints then
				for _, j in XM.ext.joints do
					local JM = getmt(j)
					if nowIn then
						activateJoint(j, seenRoots)
					elseif JM.cls.isA.WeldConstraint and JM.ext then
						JM.ext.offset = nil
					end
				end
			end
		end)
	end)
	Inst.define("WeldConstraint", {
		init = function()
			jointTotal += 1
		end,
	})
	Inst.define("JointInstance", {
		init = function()
			jointTotal += 1
		end,
	})

	local function jointDestroyed(u, M)
		local e = M.ext
		if e then
			unregisterJoint(e.p0, u)
			unregisterJoint(e.p1, u)
		end
	end
	local function jointCloned(copy, CM, src, SM)
		CM.ext = {}
		local p0, p1 = CM.props.Part0, CM.props.Part1
		CM.ext.p0, CM.ext.p1 = p0, p1
		registerJoint(p0, copy)
		registerJoint(p1, copy)
		if SM.ext and SM.ext.offset then
			CM.ext.offset = SM.ext.offset
		end
	end
	for _, cname in { "WeldConstraint", "JointInstance" } do
		Inst.define(cname, { onChanged = jointChanged, onDestroy = jointDestroyed, postClone = jointCloned })
	end

	-- =================================================================================================
	--  Model
	-- =================================================================================================
	local function partsOf(model)
		local out = {}
		for _, d in Inst.descendants(model) do
			if getmt(d).cls.isPart then
				out[#out + 1] = d
			end
		end
		return out
	end
	Parts.partsOf = partsOf

	-- Roblox (Doku Model.PrimaryPart): ein Nicht-Nachfahre darf gesetzt werden, wird aber im nächsten
	-- Simulationsschritt auf nil zurückgesetzt (ebenso, wenn das Teil das Modell verlässt).
	local function primaryPart(u, M)
		local pp = M.props.PrimaryPart
		if pp ~= nil and getmt(pp).destroyed then
			return nil
		end
		return pp
	end
	local primaryModels = setmetatable({}, { __mode = "k" })
	R.Sched.addHook("physics", function()
		for model in primaryModels do
			local MM = getmt(model)
			local pp = MM.props.PrimaryPart
			if pp == nil then
				primaryModels[model] = nil
			elseif getmt(pp).destroyed or not Inst.isAncestor(model, pp) then
				primaryModels[model] = nil
				Inst.storeProp(model, "PrimaryPart", nil)
			end
		end
	end, "Model.PrimaryPart")

	local function boundingBox(u, M, orient)
		local parts = partsOf(u)
		if #parts == 0 then
			return nil
		end
		local inv = orient:Inverse()
		local mnx, mny, mnz, mxx, mxy, mxz = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
		for _, p in parts do
			local PM = getmt(p)
			local rel = inv * cfOf(PM)
			local sx, sy, sz = DT.v3xyz(PM.props.Size or Inst.defaultValue(p, "Size"))
			local d = DT.cfData(rel)
			local hx = (math.abs(d[4]) * sx + math.abs(d[5]) * sy + math.abs(d[6]) * sz) / 2
			local hy = (math.abs(d[7]) * sx + math.abs(d[8]) * sy + math.abs(d[9]) * sz) / 2
			local hz = (math.abs(d[10]) * sx + math.abs(d[11]) * sy + math.abs(d[12]) * sz) / 2
			mnx, mny, mnz = math.min(mnx, d[1] - hx), math.min(mny, d[2] - hy), math.min(mnz, d[3] - hz)
			mxx, mxy, mxz = math.max(mxx, d[1] + hx), math.max(mxy, d[2] + hy), math.max(mxz, d[3] + hz)
		end
		local center = orient * DT.CFrame.new((mnx + mxx) / 2, (mny + mxy) / 2, (mnz + mxz) / 2)
		return center, mk.V3(mxx - mnx, mxy - mny, mxz - mnz)
	end

	local function getPivot(u, M)
		local pp = primaryPart(u, M)
		if pp then
			local PM = getmt(pp)
			return cfOf(PM) * (PM.props.PivotOffset or DT.CFrame.identity)
		end
		local wp = M.ext and M.ext.worldPivot
		if wp then
			return wp
		end
		local center = boundingBox(u, M, DT.CFrame.identity)
		return center or DT.CFrame.identity
	end
	Parts.modelPivot = function(u)
		return getPivot(u, getmt(u))
	end

	-- alle Teile mit Transformation 'delta' bewegen (ohne Baugruppen-Doppelbewegung)
	local function moveParts(parts, delta)
		local targets = {}
		for i, p in parts do
			targets[i] = delta * cfOf(getmt(p))
		end
		for i, p in parts do
			storeCF(p, getmt(p), targets[i])
		end
	end

	local function pivotTo(u, M, cf)
		local cur = getPivot(u, M)
		local delta = cf * cur:Inverse()
		moveParts(partsOf(u), delta)
		if primaryPart(u, M) == nil then
			ext(M).worldPivot = cf
			Inst.changed(u, M, "WorldPivot")
		end
	end

	local Mo = {}
	function Mo.GetPivot(self)
		local M = Inst.checkSelf(self, "GetPivot")
		return getPivot(self, M)
	end
	function Mo.PivotTo(self, cf)
		local M = Inst.checkSelf(self, "PivotTo")
		Util.checkType(cf, "CFrame", 1, "PivotTo")
		pivotTo(self, M, cf)
	end
	function Mo.GetBoundingBox(self)
		local M = Inst.checkSelf(self, "GetBoundingBox")
		local orient = getPivot(self, M).Rotation
		local c, s = boundingBox(self, M, orient)
		if c == nil then
			return getPivot(self, M), DT.Vector3.zero
		end
		return c, s
	end
	function Mo.GetExtentsSize(self)
		local M = Inst.checkSelf(self, "GetExtentsSize")
		local pp = primaryPart(self, M)
		local orient = pp and cfOf(getmt(pp)).Rotation or DT.CFrame.identity
		local _, s = boundingBox(self, M, orient)
		return s or DT.Vector3.zero
	end
	function Mo.GetModelCFrame(self)
		local M = Inst.checkSelf(self, "GetModelCFrame")
		local c = boundingBox(self, M, getPivot(self, M).Rotation)
		return c or getPivot(self, M)
	end
	function Mo.GetModelSize(self)
		return Mo.GetExtentsSize(self)
	end
	function Mo.MoveTo(self, position)
		local M = Inst.checkSelf(self, "MoveTo")
		local target = DT.checkV3(position, 1, "MoveTo")
		local parts = partsOf(self)
		if #parts == 0 then
			return
		end
		local pivotBefore = getPivot(self, M)
		local ref = primaryPart(self, M) or rootOf(parts)
		local cur = cfOf(getmt(ref)).Position
		local d = mk.V3vec(target) - cur
		moveParts(parts, DT.CFrame.new(d))
		if primaryPart(self, M) == nil then
			-- MoveTo setzt (laut Doku) die WorldPivot
			ext(M).worldPivot = pivotBefore + d
		end
	end
	function Mo.TranslateBy(self, delta)
		local M = Inst.checkSelf(self, "TranslateBy")
		Util.checkType(delta, "Vector3", 1, "TranslateBy")
		local pivotBefore = getPivot(self, M)
		moveParts(partsOf(self), DT.CFrame.new(delta))
		if primaryPart(self, M) == nil then
			ext(M).worldPivot = pivotBefore + delta
		end
	end
	local function noPrimary(fname)
		raise(
			fmt(
				"Model:%s() failed because no PrimaryPart has been set, or the PrimaryPart no longer exists. Please set Model.PrimaryPart before using this.",
				fname
			)
		)
	end
	function Mo.SetPrimaryPartCFrame(self, cf)
		local M = Inst.checkSelf(self, "SetPrimaryPartCFrame")
		Util.checkType(cf, "CFrame", 1, "SetPrimaryPartCFrame")
		local pp = primaryPart(self, M)
		if pp == nil then
			noPrimary("SetPrimaryPartCFrame")
		end
		local delta = cf * cfOf(getmt(pp)):Inverse()
		moveParts(partsOf(self), delta)
	end
	function Mo.GetPrimaryPartCFrame(self)
		local M = Inst.checkSelf(self, "GetPrimaryPartCFrame")
		local pp = primaryPart(self, M)
		if pp == nil then
			noPrimary("GetPrimaryPartCFrame")
		end
		return cfOf(getmt(pp))
	end
	function Mo.GetScale(self)
		local M = Inst.checkSelf(self, "GetScale")
		return M.ext and M.ext.scale or 1
	end
	function Mo.ScaleTo(self, factor)
		local M = Inst.checkSelf(self, "ScaleTo")
		factor = Util.checkNumber(factor, 1, "ScaleTo")
		if factor <= 0 or factor ~= factor then
			raise("Model:ScaleTo() requires a positive scale factor")
		end
		local cur = M.ext and M.ext.scale or 1
		local ratio = factor / cur
		local pivot = getPivot(self, M)
		for _, p in partsOf(self) do
			local PM = getmt(p)
			local rel = pivot:Inverse() * cfOf(PM)
			local pos = rel.Position * ratio
			local d = DT.cfData(rel)
			local scaled = DT.CFrame.new(pos.X, pos.Y, pos.Z, d[4], d[5], d[6], d[7], d[8], d[9], d[10], d[11], d[12])
			storeCF(p, PM, pivot * scaled)
			local size = PM.props.Size or Inst.defaultValue(p, "Size")
			Inst.storeProp(p, "Size", clampSize(size * ratio))
		end
		ext(M).scale = factor
	end
	function Mo.AddPersistentPlayer(self, player)
		local M = Inst.checkSelf(self, "AddPersistentPlayer")
		local e = ext(M)
		e.persistent = e.persistent or {}
		if player and not table.find(e.persistent, player) then
			e.persistent[#e.persistent + 1] = player
		end
	end
	function Mo.RemovePersistentPlayer(self, player)
		local M = Inst.checkSelf(self, "RemovePersistentPlayer")
		local e = M.ext
		if e and e.persistent then
			local i = table.find(e.persistent, player)
			if i then
				table.remove(e.persistent, i)
			end
		end
	end
	function Mo.GetPersistentPlayers(self)
		local M = Inst.checkSelf(self, "GetPersistentPlayers")
		return M.ext and M.ext.persistent and table.clone(M.ext.persistent) or {}
	end
	Mo.BreakJoints = function(self)
		Inst.checkSelf(self, "BreakJoints")
		for _, p in partsOf(self) do
			BP.BreakJoints(p)
		end
	end
	Mo.MakeJoints = function(self)
		Inst.checkSelf(self, "MakeJoints")
	end

	Inst.define("Model", {
		props = {
			PrimaryPart = {
				get = function(u, M)
					return primaryPart(u, M)
				end,
				set = function(u, M, v)
					Inst.storeProp(u, "PrimaryPart", v)
					if v ~= nil then
						primaryModels[u] = true
					end
				end,
			},
			WorldPivot = {
				get = function(u, M)
					return getPivot(u, M)
				end,
				set = function(u, M, cf)
					local pp = primaryPart(u, M)
					if pp then
						local PM = getmt(pp)
						Inst.storeProp(pp, "PivotOffset", cfOf(PM):Inverse() * cf)
					else
						ext(M).worldPivot = cf
					end
					Inst.changed(u, M, "WorldPivot")
				end,
			},
		},
		methods = Mo,
		postClone = function(copy, CM, src, SM)
			if SM.ext then
				CM.ext = CM.ext or {}
				CM.ext.worldPivot = SM.ext.worldPivot
				CM.ext.scale = SM.ext.scale
			end
		end,
	})

	-- =================================================================================================
	--  Harness: Berührung simulieren (keine Physik im Harness)
	-- =================================================================================================
	function Parts.simulateTouch(a, b)
		local AM, BM = getmt(a), getmt(b)
		local function canTouch(X)
			local v = X.props.CanTouch
			return v == nil or v == true
		end
		if not (canTouch(AM) and canTouch(BM)) then
			return false
		end
		Inst.fire(a, "Touched", b)
		Inst.fire(b, "Touched", a)
		return true
	end
	function Parts.simulateTouchEnded(a, b)
		Inst.fire(a, "TouchEnded", b)
		Inst.fire(b, "TouchEnded", a)
	end
end
