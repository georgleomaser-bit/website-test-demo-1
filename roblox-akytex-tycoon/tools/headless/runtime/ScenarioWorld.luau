--!nocheck
-- =====================================================================
--  Headless-Harness · Szenario "world": gebaute Welt als JSON (out/world.json) für worldcheck.py und den Renderer
--
--  Ablauf (python3 tools/headless/run.py world [--seconds 30]):
--    1. Wie "boot": Server-Start, Spieler 1 (Besitzer, mit Client) und Spieler 2 treten bei.
--    2. Turm-Aufbau für Spieler 1 – ausschließlich über die echten Remotes des Spiels vom Besitzer-Client aus
--       (genau so, wie der Besitzer es im Admin-Panel/Tower-Menü machen würde):
--         Admin  SetLicence {Licence = 4}            Lizenz für Stufe "Hochhaus" (Etage 18–21)
--         Admin  Give {Grant = {Credits = 1e12}}     Bau-Kasse
--         Admin  SetFloors {Floors = 18}             18 Etagen (TowerService.AdminSetFloors -> Hülle neu)
--         Admin  GiveAllItems {Kind = "Decor"}       alle Deko-Teile ins Lager
--         Request TowerRoom {Floor, Room}            Abteilungen je Etage (alle für die Stufe erlaubten Räume)
--         Request TowerHire {Floor, Staff}           Personal (Roboter an Schreibtischen) + Lobby-Bots
--         Request TowerDecor {Floor, Slot, Key}      Deko in den unteren Etagen
--         Request TowerBuild {}                      Etage 19 beginnt -> Baustelle + Kran (Effekt "Crane")
--         Request TowerHome {}                       Figur in die eigene Lobby (TowerView baut Interiors)
--         Request TowerElevator {Floor = 6}          Aufzug in Etage 6 (Interior einer Büro-Etage)
--       Jede Antwort steht im Bericht (report.txt, Abschnitt "Welt").
--    3. Client-Schnappschüsse (nur clientseitig gebaute Teile: Interiors, Aufzug, Kran, Verkehr …) in den Phasen
--       "lobby" (nach TowerHome) und "floor6" (nach dem Aufzug), jeweils mit Kamera-/Figur-Position.
--    4. Server-Sicht von Workspace nach opts.seconds (Standard 30 s) NACH dem Beitritt als world.json.
--
--  world.json (kompakt, Zahlen gerundet; Teile über Index "i" referenziert):
--    meta    Zeit, Modus, Zähler (Teile/Lichter je Gruppe), Spieler-Plot, Turm-Antworten
--    config  Config.City (Zonen, Plots, Straßen, Budgets), Config.Quality.Tiers, Config.Tower (Geometrie)
--    terrain Formen (FillBlock/-Cylinder/-Ball/-Wedge, Reihenfolge = Schreibreihenfolge) + Voxel-Säulen (Hügel)
--    models  { i, p (Pfad), mode (ModelStreamingMode), lod, n (Teile), hum (Humanoid), pp (PrimaryPart-Index) }
--    parts   { i, p, c (Klasse), sh (Form), s (Größe), cf (12 Zahlen), col (Hex), m (Material), t, r, a (verankert),
--              cc (CanCollide), cq/ct (nur wenn false), cs (CastShadow=false), md (Model-Index), mesh, dec (Decals),
--              at (Attribute), mk (Erzeugungsort src/…:Zeile), src ("s" Server | "c" nur Client), ph (Phase) }
--    lights  { pi (Teil-Index), c, pos, dir, range, b, col, e, sh, ang, face, at }
--    guis    { pi, c, face, e, aot, txt }        fx { pi, c, … }        joints { c, p0, p1, e, p }
--    anchors { name, pos, look }   plots { plot, pivot, owner, floors, stage }   client { phase, cam, root, n }
-- =====================================================================
return function(R, Sc)
	local Sched = R.Sched
	local Report = R.Report
	local Inst = R.Inst
	local DT = R.DT
	local Net = R.Net
	local GM = R.Game
	local Globals = R.Globals
	local getmt = getmetatable
	local fmt = string.format
	local floor = math.floor

	local W = {}

	-- ---------------------------------------------------------------------------------------------
	--  Erzeugungsort je Instanz (erste Spiel-Frames des Stacks beim Erzeugen) – hilft, Welt-Bugs der Quelle zuzuordnen
	-- ---------------------------------------------------------------------------------------------
	local madeAt = setmetatable({}, { __mode = "k" })
	local stopObserve = nil
	function W.trackCreation()
		if stopObserve then
			return
		end
		stopObserve = Inst.observe("created", function(u)
			if Net.applying ~= nil then
				return -- Replikat auf einem Client (kein Spiel-Code)
			end
			local first, second = nil, nil
			for level = 3, 40 do
				local s, l = debug.info(level, "sl")
				if s == nil then
					break
				end
				if string.sub(s, 1, 4) == "src/" then
					local loc = s .. ":" .. tostring(l)
					if first == nil then
						first = loc
					elseif loc ~= first and second == nil then
						second = loc
						break
					end
				end
			end
			if first then
				madeAt[u] = second and (first .. " < " .. second) or first
			end
		end)
	end

	-- ---------------------------------------------------------------------------------------------
	--  JSON-Ausgabe (kompakt, gerundet)
	-- ---------------------------------------------------------------------------------------------
	local function n3(x)
		if x ~= x or x == math.huge or x == -math.huge then
			return "null"
		end
		if x == floor(x) and math.abs(x) < 1e15 then
			return tostring(floor(x))
		end
		local s = fmt("%.3f", x)
		s = string.gsub(s, "0+$", "")
		s = string.gsub(s, "%.$", "")
		if s == "-0" then
			s = "0"
		end
		return s
	end
	local function n5(x)
		if x ~= x or x == math.huge or x == -math.huge then
			return "null"
		end
		local s = fmt("%.5f", x)
		s = string.gsub(s, "0+$", "")
		s = string.gsub(s, "%.$", "")
		if s == "-0" then
			s = "0"
		end
		return s
	end
	local quote = DT.json.quote

	local function hasNaN(t)
		for _, v in t do
			if v ~= v or v == math.huge or v == -math.huge then
				return true
			end
		end
		return false
	end

	local function cfJson(d)
		return "["
			.. n3(d[1]) .. "," .. n3(d[2]) .. "," .. n3(d[3]) .. ","
			.. n5(d[4]) .. "," .. n5(d[5]) .. "," .. n5(d[6]) .. ","
			.. n5(d[7]) .. "," .. n5(d[8]) .. "," .. n5(d[9]) .. ","
			.. n5(d[10]) .. "," .. n5(d[11]) .. "," .. n5(d[12]) .. "]"
	end
	local function v3Json(v)
		local x, y, z = DT.v3xyz(v)
		return "[" .. n3(x) .. "," .. n3(y) .. "," .. n3(z) .. "]"
	end
	local function colHex(c)
		local r, g, b = DT.c3rgb(c)
		local function ch(x)
			x = math.clamp(floor(x * 255 + 0.5), 0, 255)
			return x
		end
		return fmt('"%02x%02x%02x"', ch(r), ch(g), ch(b))
	end

	-- beliebigen Wert (Config/Attribut) in JSON wandeln: Userdata -> Zahlenlisten/Namen, Funktionen -> ausgelassen
	local function anyJson(v, depth)
		depth = depth or 0
		local t = R.Util.typeof(v)
		if t == "number" then
			return n3(v)
		elseif t == "string" then
			return quote(Sc.cut(v, 200))
		elseif t == "boolean" then
			return v and "true" or "false"
		elseif t == "Vector3" then
			return v3Json(v)
		elseif t == "Vector2" then
			return "[" .. n3(v.X) .. "," .. n3(v.Y) .. "]"
		elseif t == "Color3" then
			return colHex(v)
		elseif t == "CFrame" then
			return cfJson(DT.cfData(v))
		elseif t == "EnumItem" then
			return quote(v.Name)
		elseif t == "table" then
			if depth > 6 then
				return "null"
			end
			local n = #v
			local parts = {}
			if n > 0 then
				for i = 1, math.min(n, 400) do
					parts[#parts + 1] = anyJson(v[i], depth + 1)
				end
				return "[" .. table.concat(parts, ",") .. "]"
			end
			local keys = {}
			for k in v do
				if type(k) == "string" then
					keys[#keys + 1] = k
				end
			end
			table.sort(keys)
			for _, k in keys do
				local tv = R.Util.typeof(v[k])
				if tv ~= "function" and tv ~= "thread" and tv ~= "Instance" then
					parts[#parts + 1] = quote(k) .. ":" .. anyJson(v[k], depth + 1)
				end
			end
			return "{" .. table.concat(parts, ",") .. "}"
		elseif t == "nil" then
			return "null"
		else
			return quote(t .. ":" .. Sc.cut(tostring(v), 60))
		end
	end
	W.anyJson = anyJson

	-- ---------------------------------------------------------------------------------------------
	--  Instanz-Helfer
	-- ---------------------------------------------------------------------------------------------
	local function gp(u, k)
		local M = getmt(u)
		local d = M.cls.members[k]
		if d == nil or d.kind ~= "prop" then
			return nil
		end
		local ok, v = pcall(Inst.getProp, u, k)
		if ok then
			return v
		end
		return nil
	end
	W.gp = gp

	--- Enabled wie Roblox: Lichter, Gelenke, Constraints, Beams, Partikel, GUIs sind standardmäßig an. Der Harness legt
	--- nur gesetzte Werte in M.props ab; die API-Defaults fehlen für manche Klassen (z. B. WeldConstraint.Enabled ->
	--- false), darum hier der Rohwert: nil = Roblox-Standard true.
	function W.enabled(u)
		return getmt(u).props.Enabled ~= false
	end

	local function attrsJson(u)
		local M = getmt(u)
		local a = M.attrs
		if a == nil or next(a) == nil then
			return nil
		end
		local keys = {}
		for k in a do
			keys[#keys + 1] = k
		end
		table.sort(keys)
		local parts = {}
		for i, k in keys do
			if i > 12 then
				break
			end
			local v = a[k]
			if type(v) == "string" then
				v = Sc.cut(v, 48)
			end
			parts[#parts + 1] = quote(k) .. ":" .. anyJson(v, 5)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end

	local SHAPE_BY_CLASS = {
		WedgePart = "Wedge",
		CornerWedgePart = "CornerWedge",
		MeshPart = "Mesh",
		TrussPart = "Truss",
		UnionOperation = "Union",
		NegateOperation = "Negate",
		IntersectOperation = "Union",
		PartOperation = "Union",
	}
	local function shapeOf(M)
		local s = SHAPE_BY_CLASS[M.cls.name]
		if s then
			return s
		end
		local sh = M.props.Shape
		if sh == nil then
			sh = gp(M.self, "Shape")
		end
		if sh and type(sh) == "userdata" then
			return sh.Name
		end
		return "Block"
	end

	local JOINT_CLASSES = {
		Weld = true,
		WeldConstraint = true,
		Motor6D = true,
		Motor = true,
		Snap = true,
		ManualWeld = true,
		ManualGlue = true,
		Glue = true,
		RigidConstraint = true,
	}

	-- Welt-Position/Richtung einer Lichtquelle (Teil oder Attachment)
	local function attachmentWorld(att)
		local AM = getmt(att)
		local parent = AM.parent
		local cf = gp(att, "CFrame") or DT.CFrame.identity
		if parent and getmt(parent).cls.isPart then
			local pcf = getmt(parent).props.CFrame or DT.CFrame.identity
			return pcf * cf, parent
		end
		return cf, parent
	end

	local FACE_VEC = {
		Front = { 0, 0, -1 },
		Back = { 0, 0, 1 },
		Top = { 0, 1, 0 },
		Bottom = { 0, -1, 0 },
		Right = { 1, 0, 0 },
		Left = { -1, 0, 0 },
	}
	local function faceDir(d, faceName)
		local f = FACE_VEC[faceName or "Front"] or FACE_VEC.Front
		-- Welt = R * lokal (Zeilen d[4..6], d[7..9], d[10..12])
		local x = d[4] * f[1] + d[5] * f[2] + d[6] * f[3]
		local y = d[7] * f[1] + d[8] * f[2] + d[9] * f[3]
		local z = d[10] * f[1] + d[11] * f[2] + d[12] * f[3]
		return x, y, z
	end

	local function guiTexts(gui, maxN)
		local list = {}
		for _, d in Inst.descendants(gui) do
			local DM = getmt(d)
			if DM.cls.isA.TextLabel or DM.cls.isA.TextButton or DM.cls.isA.TextBox then
				local txt = DM.props.Text
				if type(txt) == "string" and txt ~= "" then
					txt = string.gsub(txt, "<[^>]+>", "")
					txt = string.gsub(txt, "%s+", " ")
					list[#list + 1] = Sc.cut(txt, 40)
					if #list >= maxN then
						break
					end
				end
			end
		end
		return list
	end

	-- ---------------------------------------------------------------------------------------------
	--  Dump eines Workspace-Baums
	--  st = { parts = {}, lights = {}, guis = {}, fx = {}, joints = {}, models = {}, idOf = {}, modelIdOf = {},
	--         counts = {…} }   filter(u) -> true = aufnehmen (für "nur Client"-Schnappschüsse)
	-- ---------------------------------------------------------------------------------------------
	local function newState()
		return {
			parts = {},
			lights = {},
			guis = {},
			fx = {},
			joints = {},
			models = {},
			idOf = {},
			modelIdOf = {},
			pendingJoints = {},
			pendingFx = {},
			counts = { parts = 0, lights = 0, guis = 0, fx = 0, joints = 0, models = 0, nan = 0, prompts = 0, sounds = 0, decals = 0 },
		}
	end
	W.newState = newState

	local function partEntry(st, u, M, modelIdx, src, phase)
		local id = #st.parts + 1
		st.idOf[u] = id
		local props = M.props
		local cf = props.CFrame or DT.CFrame.identity
		local d = DT.cfData(cf)
		local size = props.Size or gp(u, "Size")
		local sx, sy, sz = 4, 1, 2
		if size then
			sx, sy, sz = DT.v3xyz(size)
		end
		local L = {}
		L[#L + 1] = '{"i":' .. id
		L[#L + 1] = '"p":' .. quote(Inst.fullName(u))
		L[#L + 1] = '"c":' .. quote(M.cls.name)
		L[#L + 1] = '"sh":' .. quote(shapeOf(M))
		L[#L + 1] = '"s":[' .. n3(sx) .. "," .. n3(sy) .. "," .. n3(sz) .. "]"
		L[#L + 1] = '"cf":' .. cfJson(d)
		if hasNaN(d) or sx ~= sx or sy ~= sy or sz ~= sz then
			L[#L + 1] = '"nan":1'
			st.counts.nan += 1
		end
		local col = props.Color or gp(u, "Color")
		if col then
			L[#L + 1] = '"col":' .. colHex(col)
		end
		local mat = props.Material or gp(u, "Material")
		if mat then
			L[#L + 1] = '"m":' .. quote(mat.Name)
		end
		local tr = props.Transparency or gp(u, "Transparency") or 0
		if tr ~= 0 then
			L[#L + 1] = '"t":' .. n3(tr)
		end
		local rf = props.Reflectance or gp(u, "Reflectance") or 0
		if rf ~= 0 then
			L[#L + 1] = '"r":' .. n3(rf)
		end
		local anch = props.Anchored
		if anch == nil then
			anch = gp(u, "Anchored")
		end
		L[#L + 1] = '"a":' .. (anch and "1" or "0")
		local cc = props.CanCollide
		if cc == nil then
			cc = gp(u, "CanCollide")
		end
		L[#L + 1] = '"cc":' .. (cc and "1" or "0")
		local cq = props.CanQuery
		if cq == false then
			L[#L + 1] = '"cq":0'
		end
		local ct = props.CanTouch
		if ct == false then
			L[#L + 1] = '"ct":0'
		end
		if props.CastShadow == false then
			L[#L + 1] = '"cs":0'
		end
		if props.Massless == true then
			L[#L + 1] = '"ml":1'
		end
		if modelIdx then
			L[#L + 1] = '"md":' .. modelIdx
		end
		-- Mesh: MeshPart.MeshId oder SpecialMesh/BlockMesh/CylinderMesh als Kind
		local meshBits = nil
		if M.cls.name == "MeshPart" then
			local mid = props.MeshId or gp(u, "MeshId") or ""
			meshBits = '{"t":"MeshPart","id":' .. quote(tostring(mid)) .. "}"
		end
		local decals = 0
		for _, c in M.children do
			local CM = getmt(c)
			local cn = CM.cls.name
			if cn == "SpecialMesh" or cn == "BlockMesh" or cn == "CylinderMesh" then
				local mt = cn == "SpecialMesh" and (CM.props.MeshType or gp(c, "MeshType")) or nil
				local scale = CM.props.Scale or gp(c, "Scale")
				local off = CM.props.Offset or gp(c, "Offset")
				local mid = cn == "SpecialMesh" and (CM.props.MeshId or gp(c, "MeshId")) or ""
				meshBits = '{"t":'
					.. quote(mt and mt.Name or cn)
					.. ',"id":'
					.. quote(tostring(mid or ""))
					.. (scale and (',"sc":' .. v3Json(scale)) or "")
					.. (off and (',"off":' .. v3Json(off)) or "")
					.. "}"
			elseif CM.cls.isA.Decal then
				decals += 1
			end
		end
		if meshBits then
			L[#L + 1] = '"mesh":' .. meshBits
		end
		if decals > 0 then
			L[#L + 1] = '"dec":' .. decals
			st.counts.decals += decals
		end
		local at = attrsJson(u)
		if at then
			L[#L + 1] = '"at":' .. at
		end
		local mk = madeAt[u]
		if mk then
			L[#L + 1] = '"mk":' .. quote(mk)
		end
		L[#L + 1] = '"src":"' .. src .. '"'
		if phase then
			L[#L + 1] = '"ph":' .. quote(phase)
		end
		st.parts[id] = table.concat(L, ",") .. "}"
		st.counts.parts += 1
		return id
	end

	local LIGHT = { PointLight = true, SpotLight = true, SurfaceLight = true }
	local FX = {
		Beam = true,
		ParticleEmitter = true,
		Trail = true,
		Fire = true,
		Smoke = true,
		Sparkles = true,
		Highlight = true,
		SelectionBox = true,
		BoxHandleAdornment = true,
		CylinderHandleAdornment = true,
		SphereHandleAdornment = true,
	}

	local function lightEntry(st, u, M, src, phase)
		local parent = M.parent
		if parent == nil then
			return
		end
		local PM = getmt(parent)
		local cf, part
		if PM.cls.isPart then
			cf, part = PM.props.CFrame or DT.CFrame.identity, parent
		elseif PM.cls.name == "Attachment" then
			cf, part = attachmentWorld(parent)
		else
			return
		end
		local d = DT.cfData(cf)
		local face = M.props.Face or gp(u, "Face")
		local faceName = face and face.Name or "Front"
		local dx, dy, dz = faceDir(d, faceName)
		local L = {}
		L[#L + 1] = '{"c":' .. quote(M.cls.name)
		L[#L + 1] = '"pi":' .. tostring(part and st.idOf[part] or "null")
		L[#L + 1] = '"pos":[' .. n3(d[1]) .. "," .. n3(d[2]) .. "," .. n3(d[3]) .. "]"
		if M.cls.name ~= "PointLight" then
			L[#L + 1] = '"dir":[' .. n3(dx) .. "," .. n3(dy) .. "," .. n3(dz) .. "]"
			L[#L + 1] = '"face":' .. quote(faceName)
			L[#L + 1] = '"ang":' .. n3(gp(u, "Angle") or 90)
		end
		L[#L + 1] = '"range":' .. n3(gp(u, "Range") or 0)
		L[#L + 1] = '"b":' .. n3(gp(u, "Brightness") or 0)
		local col = gp(u, "Color")
		if col then
			L[#L + 1] = '"col":' .. colHex(col)
		end
		L[#L + 1] = '"e":' .. (W.enabled(u) and "1" or "0")
		L[#L + 1] = '"sh":' .. (gp(u, "Shadows") == true and "1" or "0")
		local at = attrsJson(u)
		if at then
			L[#L + 1] = '"at":' .. at
		end
		L[#L + 1] = '"p":' .. quote(Inst.fullName(u))
		L[#L + 1] = '"src":"' .. src .. '"'
		if phase then
			L[#L + 1] = '"ph":' .. quote(phase)
		end
		st.lights[#st.lights + 1] = table.concat(L, ",") .. "}"
		st.counts.lights += 1
	end

	local function guiEntry(st, u, M, src, phase)
		local adornee = gp(u, "Adornee")
		local host = adornee or M.parent
		if host and not getmt(host).cls.isPart then
			if getmt(host).cls.name == "Attachment" then
				host = getmt(host).parent
			end
		end
		local L = {}
		L[#L + 1] = '{"c":' .. quote(M.cls.name)
		L[#L + 1] = '"pi":' .. tostring(host and st.idOf[host] or "null")
		if M.cls.name == "SurfaceGui" then
			local face = gp(u, "Face")
			L[#L + 1] = '"face":' .. quote(face and face.Name or "Front")
		else
			local aot = gp(u, "AlwaysOnTop")
			if aot then
				L[#L + 1] = '"aot":1'
			end
			local md = gp(u, "MaxDistance")
			if md then
				L[#L + 1] = '"maxd":' .. n3(md)
			end
			local off = gp(u, "StudsOffset")
			if off then
				L[#L + 1] = '"off":' .. v3Json(off)
			end
		end
		L[#L + 1] = '"e":' .. (W.enabled(u) and "1" or "0")
		local texts = guiTexts(u, 3)
		local q = {}
		for _, t in texts do
			q[#q + 1] = quote(t)
		end
		L[#L + 1] = '"txt":[' .. table.concat(q, ",") .. "]"
		L[#L + 1] = '"n":' .. #Inst.descendants(u)
		L[#L + 1] = '"p":' .. quote(Inst.fullName(u))
		L[#L + 1] = '"src":"' .. src .. '"'
		if phase then
			L[#L + 1] = '"ph":' .. quote(phase)
		end
		if host and not st.idOf[host] then
			st.pendingFx[#st.pendingFx + 1] = { kind = "gui", idx = #st.guis + 1, host = host }
		end
		st.guis[#st.guis + 1] = L
		st.counts.guis += 1
	end

	local function fxEntry(st, u, M, src, phase)
		local L = {}
		L[#L + 1] = '{"c":' .. quote(M.cls.name)
		local host = M.parent
		if host and getmt(host).cls.name == "Attachment" then
			host = getmt(host).parent
		end
		local cn = M.cls.name
		if cn == "Beam" then
			local a0, a1 = gp(u, "Attachment0"), gp(u, "Attachment1")
			if a0 and a1 then
				local c0 = attachmentWorld(a0)
				local c1 = attachmentWorld(a1)
				local d0, d1 = DT.cfData(c0), DT.cfData(c1)
				L[#L + 1] = '"a":[' .. n3(d0[1]) .. "," .. n3(d0[2]) .. "," .. n3(d0[3]) .. "]"
				L[#L + 1] = '"b":[' .. n3(d1[1]) .. "," .. n3(d1[2]) .. "," .. n3(d1[3]) .. "]"
			end
			L[#L + 1] = '"w":[' .. n3(gp(u, "Width0") or 1) .. "," .. n3(gp(u, "Width1") or 1) .. "]"
			local cs = gp(u, "Color")
			if cs then
				local kps = DT.csKeypoints(cs)
				local km = kps and kps[1] and getmt(kps[1])
				if km and km.c then
					L[#L + 1] = '"col":' .. colHex(km.c)
				end
			end
			L[#L + 1] = '"le":' .. n3(gp(u, "LightEmission") or 0)
		elseif cn == "ParticleEmitter" then
			L[#L + 1] = '"rate":' .. n3(gp(u, "Rate") or 0)
		end
		L[#L + 1] = '"e":' .. (W.enabled(u) and "1" or "0")
		L[#L + 1] = '"p":' .. quote(Inst.fullName(u))
		L[#L + 1] = '"src":"' .. src .. '"'
		if phase then
			L[#L + 1] = '"ph":' .. quote(phase)
		end
		st.pendingFx[#st.pendingFx + 1] = { kind = "fx", idx = #st.fx + 1, host = host }
		st.fx[#st.fx + 1] = L
		st.counts.fx += 1
	end

	local function jointEntry(st, u, M, src, phase)
		local cn = M.cls.name
		local p0, p1
		if JOINT_CLASSES[cn] or M.cls.isA.JointInstance then
			p0, p1 = gp(u, "Part0"), gp(u, "Part1")
		elseif M.cls.isA.Constraint then
			local a0, a1 = gp(u, "Attachment0"), gp(u, "Attachment1")
			p0 = a0 and getmt(a0).parent or nil
			p1 = a1 and getmt(a1).parent or nil
		elseif cn == "NoCollisionConstraint" then
			p0, p1 = gp(u, "Part0"), gp(u, "Part1")
		else
			return
		end
		st.joints[#st.joints + 1] = { c = cn, p0 = p0, p1 = p1, e = W.enabled(u), path = Inst.fullName(u), src = src, ph = phase }
		st.counts.joints += 1
	end

	local CLASS_COUNT_SKIP = { Folder = true, Model = true }
	--- Baum ab root aufnehmen. accept(u) = false -> Instanz (und Kinder) überspringen; acceptOwn(u) = false ->
	--- nur die Instanz selbst nicht aufnehmen (Kinder trotzdem durchsuchen).
	function W.walk(st, root, src, phase, acceptOwn)
		local classCount = st.classCount or {}
		st.classCount = classCount
		local function visit(u, modelIdx)
			local M = getmt(u)
			local cls = M.cls
			local own = acceptOwn == nil or acceptOwn(u)
			local myModel = modelIdx
			if own then
				local cn = cls.name
				if not CLASS_COUNT_SKIP[cn] then
					classCount[cn] = (classCount[cn] or 0) + 1
				end
				if cls.isPart and not cls.isA.Terrain then
					partEntry(st, u, M, modelIdx, src, phase)
				elseif cls.isA.Model and not cls.isA.Workspace then
					local idx = #st.models + 1
					local hum = false
					for _, c in M.children do
						if getmt(c).cls.name == "Humanoid" then
							hum = true
						end
					end
					local mode = gp(u, "ModelStreamingMode")
					local lod = gp(u, "LevelOfDetail")
					st.models[idx] = {
						p = Inst.fullName(u),
						mode = mode and mode.Name or "Default",
						lod = lod and lod.Name or "Automatic",
						hum = hum,
						pp = gp(u, "PrimaryPart"),
						n = 0,
						src = src,
						ph = phase,
						parent = modelIdx,
						inst = u,
					}
					st.modelIdOf[u] = idx
					st.counts.models += 1
					myModel = idx
				elseif LIGHT[cls.name] then
					lightEntry(st, u, M, src, phase)
				elseif cls.name == "SurfaceGui" or cls.name == "BillboardGui" then
					guiEntry(st, u, M, src, phase)
					return -- GUI-Inhalt nicht weiter durchsuchen
				elseif FX[cls.name] then
					fxEntry(st, u, M, src, phase)
				elseif JOINT_CLASSES[cls.name] or cls.isA.JointInstance or cls.isA.Constraint or cls.name == "NoCollisionConstraint" then
					st.pendingJoints[#st.pendingJoints + 1] = { u = u, M = M, src = src, ph = phase }
				elseif cls.name == "ProximityPrompt" then
					st.counts.prompts += 1
				elseif cls.isA.Sound then
					st.counts.sounds += 1
				end
			else
				-- Modell-Zugehörigkeit trotzdem weiterreichen (z. B. Client-Teil in repliziertem Modell)
				if cls.isA.Model and st.modelIdOf[u] then
					myModel = st.modelIdOf[u]
				end
			end
			for _, c in M.children do
				visit(c, myModel)
			end
		end
		visit(root, nil)
	end

	--- offene Verweise auflösen und die Listen in JSON-Strings verwandeln
	function W.finish(st)
		for _, pj in st.pendingJoints do
			jointEntry(st, pj.u, pj.M, pj.src, pj.ph)
		end
		st.pendingJoints = {}
		local jl = {}
		for _, j in st.joints do
			if type(j) == "table" then
				jl[#jl + 1] = '{"c":'
					.. quote(j.c)
					.. ',"p0":'
					.. tostring(j.p0 and st.idOf[j.p0] or "null")
					.. ',"p1":'
					.. tostring(j.p1 and st.idOf[j.p1] or "null")
					.. ',"e":'
					.. (j.e and "1" or "0")
					.. ',"p":'
					.. quote(j.path)
					.. ',"src":"'
					.. j.src
					.. '"'
					.. (j.ph and (',"ph":' .. quote(j.ph)) or "")
					.. "}"
			else
				jl[#jl + 1] = j
			end
		end
		st.joints = jl
		for _, pf in st.pendingFx do
			local list = pf.kind == "gui" and st.guis or st.fx
			local L = list[pf.idx]
			if type(L) == "table" and pf.kind == "fx" then
				table.insert(L, 2, '"pi":' .. tostring(pf.host and st.idOf[pf.host] or "null"))
			end
		end
		for i, L in st.guis do
			if type(L) == "table" then
				st.guis[i] = table.concat(L, ",") .. "}"
			end
		end
		for i, L in st.fx do
			if type(L) == "table" then
				st.fx[i] = table.concat(L, ",") .. "}"
			end
		end
		-- Modelle: Teilezahl + PrimaryPart-Index
		local nByModel = {}
		for u, id in st.idOf do
			local _ = id
			local p = getmt(u).parent
			while p do
				local mid = st.modelIdOf[p]
				if mid then
					nByModel[mid] = (nByModel[mid] or 0) + 1
					break
				end
				p = getmt(p).parent
			end
		end
		local ml = {}
		for i, m in st.models do
			if type(m) == "table" then
				ml[i] = '{"i":'
					.. i
					.. ',"p":'
					.. quote(m.p)
					.. ',"mode":'
					.. quote(m.mode)
					.. ',"lod":'
					.. quote(m.lod)
					.. ',"n":'
					.. (nByModel[i] or 0)
					.. (m.hum and ',"hum":1' or "")
					.. (m.pp and st.idOf[m.pp] and (',"pp":' .. st.idOf[m.pp]) or "")
					.. (m.parent and (',"up":' .. m.parent) or "")
					.. ',"src":"'
					.. m.src
					.. '"'
					.. (m.ph and (',"ph":' .. quote(m.ph)) or "")
					.. "}"
			else
				ml[i] = m
			end
		end
		st.models = ml
	end

	-- ---------------------------------------------------------------------------------------------
	--  Terrain
	-- ---------------------------------------------------------------------------------------------
	function W.terrainJson(game)
		local ws = Inst.findServiceRaw(game, "Workspace")
		local terrain = nil
		for _, c in getmt(ws).children do
			if getmt(c).cls.isA.Terrain then
				terrain = c
			end
		end
		if terrain == nil then
			return '{"shapes":[],"voxels":{"res":4,"cols":[]}}'
		end
		local st = R.Svc.World.ensureTerrainState(terrain)
		local shapes = {}
		for _, sh in st.shapes do
			local s
			if sh.kind == "ball" then
				s = '{"k":"ball","c":[' .. n3(sh.cx) .. "," .. n3(sh.cy) .. "," .. n3(sh.cz) .. '],"r":' .. n3(sh.r)
			elseif sh.kind == "cyl" then
				s = '{"k":"cyl","cf":' .. cfJson(sh.d) .. ',"h":' .. n3(sh.h * 2) .. ',"r":' .. n3(sh.r)
			else
				s = '{"k":"'
					.. (sh.wedge and "wedge" or "box")
					.. '","cf":'
					.. cfJson(sh.d)
					.. ',"s":['
					.. n3(sh.hx * 2)
					.. ","
					.. n3(sh.hy * 2)
					.. ","
					.. n3(sh.hz * 2)
					.. "]"
			end
			shapes[#shapes + 1] = s .. ',"m":' .. quote(sh.mat and sh.mat.Name or "?") .. "}"
		end
		-- Voxel -> Säulen: je 4×4-Säule (x0, z0) die festen Abschnitte [y0, y1] (Füllgrad der obersten Zelle
		-- eines Abschnitts verkürzt y1), Material der obersten Zelle; Luft/Wasser zählen nicht als fest
		local cols = {}
		local colList = {}
		local voxels = st.voxels or {}
		for key, v in voxels do
			local ix, iy, iz = W.decodeCellKey(key)
			if ix then
				local ck = ix .. "," .. iz
				local c = cols[ck]
				if c == nil then
					c = { ix = ix, iz = iz, cells = {} }
					cols[ck] = c
					colList[#colList + 1] = c
				end
				local mat = v[1]
				local occ = v[3] or 1
				if mat and mat.Name ~= "Air" and mat.Name ~= "Water" and occ > 0 then
					c.cells[iy] = { math.clamp(occ, 0, 1), mat.Name }
				else
					c.cells[iy] = false -- explizit Luft (schneidet Formen darunter frei)
				end
			end
		end
		local cl = {}
		for _, c in colList do
			local ys = {}
			for iy in c.cells do
				ys[#ys + 1] = iy
			end
			table.sort(ys)
			local runs = {}
			local air = {}
			local topMat = ""
			local cur = nil
			for _, iy in ys do
				local cell = c.cells[iy]
				if cell then
					local y0, y1 = iy * 4, iy * 4 + 4 * cell[1]
					if cur and math.abs(cur[2] - y0) < 1e-6 then
						cur[2] = y1
					else
						cur = { y0, y1 }
						runs[#runs + 1] = cur
					end
					topMat = cell[2]
					if cell[1] < 0.999 then
						cur = nil -- Teilfüllung beendet den Abschnitt
					end
				else
					cur = nil
					air[#air + 1] = iy * 4
				end
			end
			local rs = {}
			for _, r in runs do
				rs[#rs + 1] = "[" .. n3(r[1]) .. "," .. n3(r[2]) .. "]"
			end
			-- Luft-Zellen als zusammengefasste Bereiche [y0, y1]
			local as = {}
			local a0, a1 = nil, nil
			for _, y in air do
				if a1 and math.abs(a1 - y) < 1e-6 then
					a1 = y + 4
				else
					if a0 then
						as[#as + 1] = "[" .. n3(a0) .. "," .. n3(a1) .. "]"
					end
					a0, a1 = y, y + 4
				end
			end
			if a0 then
				as[#as + 1] = "[" .. n3(a0) .. "," .. n3(a1) .. "]"
			end
			cl[#cl + 1] = "["
				.. (c.ix * 4)
				.. ","
				.. (c.iz * 4)
				.. ",["
				.. table.concat(rs, ",")
				.. "],["
				.. table.concat(as, ",")
				.. "],"
				.. quote(topMat)
				.. "]"
		end
		local colors = {}
		for k, v in st.colors or {} do
			local name = type(k) == "string" and k or (type(k) == "userdata" and k.Name) or tostring(k)
			if R.Util.typeof(v) == "Color3" then
				colors[#colors + 1] = quote(name) .. ":" .. colHex(v)
			end
		end
		return '{"shapes":['
			.. table.concat(shapes, ",")
			.. '],"voxels":{"res":4,"cols":['
			.. table.concat(cl, ",")
			.. ']},"colors":{'
			.. table.concat(colors, ",")
			.. "}}"
	end

	-- Voxel-Schlüssel des Harness zerlegen (World.luau: cellKey) – robust gegen verschiedene Formate
	function W.decodeCellKey(key)
		if type(key) == "string" then
			local a, b, c = string.match(key, "^(-?%d+),(-?%d+),(-?%d+)$")
			if a then
				return tonumber(a), tonumber(b), tonumber(c)
			end
			return nil
		elseif type(key) == "number" then
			-- World.luau: ((ix + OFF) * 65536 + (iy + OFF)) * 65536 + (iz + OFF), OFF = 32768
			local OFF = 32768
			local iz = key % 65536 - OFF
			local rest = floor(key / 65536)
			local iy = rest % 65536 - OFF
			local ix = floor(rest / 65536) - OFF
			return ix, iy, iz
		end
		return nil
	end

	-- ---------------------------------------------------------------------------------------------
	--  Remotes vom Besitzer-Client aufrufen
	-- ---------------------------------------------------------------------------------------------
	local function clientRemote(rec, name)
		local rs = Inst.findServiceRaw(rec.game, "ReplicatedStorage")
		local folder = rs and Inst.findChild(rs, "Remotes")
		return folder and Inst.findChild(folder, name)
	end

	local function invoke(rec, remoteName, a, b)
		local remote = clientRemote(rec, remoteName)
		if remote == nil then
			return false, "Remote " .. remoteName .. " fehlt auf dem Client"
		end
		local h = Sched.invoke(rec.ctx, function()
			return remote:InvokeServer(a, b)
		end)
		local done = Sched.await(h, 15)
		if not done then
			return false, "keine Antwort nach 15 s"
		end
		if not h.ok then
			return false, "Fehler: " .. tostring(h.err)
		end
		return true, h.results[1]
	end
	W.invoke = invoke

	local function replyText(ok, reply)
		if not ok then
			return "FEHLER " .. tostring(reply)
		end
		if type(reply) ~= "table" then
			return "Antwort " .. tostring(reply)
		end
		local msg = reply.Message or reply.Msg or reply.Text or reply.Key or ""
		return (reply.Ok and "Ok" or "abgelehnt") .. (msg ~= "" and (" – " .. Sc.cut(tostring(msg), 120)) or "")
	end

	-- Config des Servers lesen (gleiches Modul wie im Spiel, Cache des Server-Kontexts)
	function W.serverConfig()
		local game = GM.server.game
		local rs = Inst.findServiceRaw(game, "ReplicatedStorage")
		local shared = rs and Inst.findChild(rs, "Shared")
		local cfgMod = shared and Inst.findChild(shared, "Config")
		if cfgMod == nil then
			return nil
		end
		local h = Sched.invoke(GM.server.ctx, function()
			return Globals.require(GM.server.ctx, cfgMod)
		end)
		Sched.await(h, 5)
		return h.ok and h.results[1] or nil
	end

	-- ---------------------------------------------------------------------------------------------
	--  Turm-Aufbau für den Besitzer (nur über Admin-/Request-Remotes)
	-- ---------------------------------------------------------------------------------------------
	function W.buildTower(rec, results, cfg, opts)
		local log = {}
		results.towerLog = log
		local function step(label, remote, a, b, pause)
			Report.setTrigger("Welt: Turm-Aufbau " .. remote .. " " .. label)
			local ok, reply = invoke(rec, remote, a, b)
			local txt = replyText(ok, reply)
			log[#log + 1] = fmt("%-7s %-34s %s", remote, label, txt)
			Sched.run(pause or 0.3)
			return ok and type(reply) == "table" and reply.Ok == true, reply
		end
		local floorsWanted = opts.floors or 18
		step("SetLicence 4", "Admin", "SetLicence", { Licence = 4 })
		step("Give Credits 1e12", "Admin", "Give", { Grant = { Credits = 1e12 } })
		step("GiveAky 1e6", "Admin", "GiveAky", { Aky = 1000000 })
		step("SetFloors " .. floorsWanted, "Admin", "SetFloors", { Floors = floorsWanted })
		step("GiveAllItems Decor", "Admin", "GiveAllItems", { Kind = "Decor" })
		Sched.run(1)
		-- Räume: alle für die Stufe erlaubten (ohne Penthouse), reihum, Max beachten
		local tower = cfg and cfg.Tower or {}
		local stage = 1
		for i, s in tower.Stages or {} do
			if floorsWanted >= (s.First or 0) then
				stage = i
			end
		end
		local rooms = {}
		for _, r in tower.Rooms or {} do
			if (r.MinStage or 1) <= stage and not r.TopOnly then
				rooms[#rooms + 1] = { key = r.Key, max = r.Max or 99, used = 0 }
			end
		end
		local ri = 0
		for f = 2, floorsWanted do
			if #rooms == 0 then
				break
			end
			for _ = 1, #rooms do
				ri = ri % #rooms + 1
				local r = rooms[ri]
				if r.used < r.max then
					r.used += 1
					step("Etage " .. f .. " -> " .. r.key, "Request", "TowerRoom", { Floor = f, Room = r.key }, 0.35)
					break
				end
			end
		end
		-- Personal
		local staffKeys = {}
		for _, s in tower.Staff or {} do
			if (s.MinStage or 1) <= stage then
				staffKeys[#staffKeys + 1] = s
			end
		end
		for _, s in staffKeys do
			if s.Lobby then
				step("Lobby " .. s.Key, "Request", "TowerHire", { Floor = 0, Staff = s.Key }, 0.35)
			end
		end
		local desk = {}
		for _, s in staffKeys do
			if not s.Lobby then
				desk[#desk + 1] = s.Key
			end
		end
		for f = 1, math.min(8, floorsWanted) do
			for k = 1, 2 do
				local key = desk[((f + k) % math.max(1, #desk)) + 1]
				if key then
					step("Etage " .. f .. " Personal " .. key, "Request", "TowerHire", { Floor = f, Staff = key }, 0.35)
				end
			end
		end
		-- Deko: verschiedene Teile in Etage 1–8
		local decorKeys = {}
		local items = cfg and cfg.Decor and cfg.Decor.Items or {}
		for _, it in items do
			if type(it) == "table" and type(it.Key) == "string" then
				decorKeys[#decorKeys + 1] = it.Key
			end
		end
		local di = 0
		for f = 1, math.min(8, floorsWanted) do
			for slot = 1, 3 do
				di = di % math.max(1, #decorKeys) + 1
				local key = decorKeys[di]
				if key then
					step("Etage " .. f .. " Deko " .. slot .. " " .. key, "Request", "TowerDecor", { Floor = f, Slot = slot, Key = key }, 0.35)
				end
			end
		end
		-- nächste Etage bauen -> Baustelle + Kran
		step("Etage " .. (floorsWanted + 1) .. " bauen", "Request", "TowerBuild", {}, 1)
		return log
	end

	-- ---------------------------------------------------------------------------------------------
	--  Client-Schnappschuss (nur Teile, die der Client selbst erzeugt hat)
	-- ---------------------------------------------------------------------------------------------
	function W.snapClient(st, rec, phase, info)
		local ws = Inst.findServiceRaw(rec.game, "Workspace")
		local before = st.counts.parts
		local beforeL = st.counts.lights
		W.walk(st, ws, "c", phase, function(u)
			if getmt(u).cls.isA.Workspace or getmt(u).cls.isA.Terrain then
				return false
			end
			return Net.serverInstanceOf(u) == nil
		end)
		-- Client-Gesamtsicht: gestreamte + lokale Teile, eingeschaltete Lichter (WorldLook schaltet die nächsten N
		-- Server-Lichter lokal ein), GUI-Objekte in SurfaceGui/BillboardGui der Welt
		local visParts, litLights, lights, worldGuiObjects = 0, 0, 0, 0
		for _, d in Inst.descendants(ws) do
			local DM = getmt(d)
			local c = DM.cls
			if c.isPart and not c.isA.Terrain then
				visParts += 1
			elseif LIGHT[c.name] then
				lights += 1
				if W.enabled(d) then
					litLights += 1
				end
			elseif c.isA.GuiObject then
				worldGuiObjects += 1
			end
		end
		local cam = getmt(ws).props.CurrentCamera
		local camCf = cam and gp(cam, "CFrame")
		local lp = rec.localPlayer
		local ch = lp and getmt(lp).props.Character
		local root = ch and Inst.findChild(ch, "HumanoidRootPart")
		local rootCf = root and getmt(root).props.CFrame
		info[#info + 1] = '{"phase":'
			.. quote(phase)
			.. ',"cam":'
			.. (camCf and cfJson(DT.cfData(camCf)) or "null")
			.. ',"root":'
			.. (rootCf and cfJson(DT.cfData(rootCf)) or "null")
			.. ',"parts":'
			.. (st.counts.parts - before)
			.. ',"lights":'
			.. (st.counts.lights - beforeL)
			.. ',"clientWorkspaceParts":'
			.. visParts
			.. ',"clientLights":'
			.. lights
			.. ',"clientLightsOn":'
			.. litLights
			.. ',"clientWorldGuiObjects":'
			.. worldGuiObjects
			.. "}"
		return st.counts.parts - before
	end

	-- ---------------------------------------------------------------------------------------------
	--  Zähler je Gruppe (Pfad-Präfix) für den Bericht
	-- ---------------------------------------------------------------------------------------------
	local function groupOf(path)
		local a, b, c = string.match(path, "^([^%.]+)%.([^%.]+)%.?([^%.]*)")
		if a == nil then
			return path
		end
		if b == "AkytexCity" or b == "AkyTowers" then
			return a .. "." .. b .. (c ~= "" and ("." .. c) or "")
		end
		return a .. "." .. b
	end

	-- ---------------------------------------------------------------------------------------------
	--  Szenario
	-- ---------------------------------------------------------------------------------------------
	function W.run(bundle, opts, results)
		W.trackCreation()
		opts.client = 1 -- der Besitzer braucht den Client (Admin-Remote, Interiors)
		Sc.setupBoot(bundle, opts, results)
		local rec = results.rec
		local joinedAt = Sched.now
		Report.setTrigger("Laufzeit")
		-- warten, bis der Spielstand geladen ist (State kommt beim Client an) und die Stadt steht
		Sched.run(6)
		local cfg = W.serverConfig()
		local clientInfo = {}
		local stClient = newState()
		local log = {}
		if rec then
			log = W.buildTower(rec, results, cfg, opts)
			Report.setTrigger("Welt: TowerHome")
			local okH, rH = invoke(rec, "Request", "TowerHome", {})
			log[#log + 1] = fmt("%-7s %-34s %s", "Request", "TowerHome", replyText(okH, rH))
			Sched.run(6)
			Report.setTrigger("Welt: Schnappschuss lobby")
			W.snapClient(stClient, rec, "lobby", clientInfo)
			Report.setTrigger("Welt: TowerElevator 6")
			local okE, rE = invoke(rec, "Request", "TowerElevator", { Floor = 6 })
			log[#log + 1] = fmt("%-7s %-34s %s", "Request", "TowerElevator {Floor = 6}", replyText(okE, rE))
			Sched.run(6)
			Report.setTrigger("Welt: Schnappschuss floor6")
			W.snapClient(stClient, rec, "floor6", clientInfo)
		end
		Report.setTrigger("Laufzeit")
		local target = joinedAt + (opts.worldSeconds or 30)
		if Sched.now < target then
			Sched.run(target - Sched.now)
		end
		Report.setTrigger(nil)
		-- Server-Sicht
		local game = GM.server.game
		local ws = Inst.findServiceRaw(game, "Workspace")
		local st = newState()
		W.walk(st, ws, "s", nil, function(u)
			return not getmt(u).cls.isA.Workspace
		end)
		W.finish(st)
		-- Client-Teile hinter die Server-Teile hängen (eigene Indizes)
		-- erst alle Verweise in Client-Nummerierung auflösen, danach einheitlich verschieben
		W.finish(stClient)
		local offset = #st.parts
		-- Client-Einträge neu erzeugen wäre teuer: die Indizes stehen schon im Text -> Index-Verschiebung per Ersetzung
		local function shiftIds(s)
			s = string.gsub(s, '^{"i":(%d+)', function(i)
				return '{"i":' .. (tonumber(i) + offset)
			end)
			return s
		end
		local clientParts = {}
		for i, s in stClient.parts do
			clientParts[i] = shiftIds(s)
		end
		local function shiftField(s, field)
			return (string.gsub(s, '"' .. field .. '":(%d+)', function(i)
				return '"' .. field .. '":' .. (tonumber(i) + offset)
			end))
		end
		local modelOffset = #st.models
		local function shiftModel(s)
			s = string.gsub(s, '"md":(%d+)', function(i)
				return '"md":' .. (tonumber(i) + modelOffset)
			end)
			return s
		end
		for i, s in clientParts do
			clientParts[i] = shiftModel(s)
		end
		local clientModels = {}
		for i, s in stClient.models do
			local x = string.gsub(s, '^{"i":(%d+)', function(n)
				return '{"i":' .. (tonumber(n) + modelOffset)
			end)
			x = shiftField(x, "pp")
			x = string.gsub(x, '"up":(%d+)', function(n)
				return '"up":' .. (tonumber(n) + modelOffset)
			end)
			clientModels[i] = x
		end
		local function shiftList(list, fields)
			local out = {}
			for i, s in list do
				local x = s
				for _, f in fields do
					x = shiftField(x, f)
				end
				out[i] = x
			end
			return out
		end
		local cLights = shiftList(stClient.lights, { "pi" })
		local cGuis = shiftList(stClient.guis, { "pi" })
		local cFx = shiftList(stClient.fx, { "pi" })
		local cJoints = shiftList(stClient.joints, { "p0", "p1" })
		-- Anker (Teile mit Attribut "Anchor") und Plots
		local anchors = {}
		local plots = {}
		for _, d in Inst.descendants(ws) do
			local DM = getmt(d)
			local a = DM.attrs and DM.attrs.Anchor
			if type(a) == "string" and DM.cls.isPart then
				local cf = DM.props.CFrame or DT.CFrame.identity
				local dd = DT.cfData(cf)
				anchors[#anchors + 1] = fmt(
					'{"name":%s,"pos":[%s,%s,%s],"look":[%s,%s,%s],"p":%s}',
					quote(a),
					n3(dd[1]),
					n3(dd[2]),
					n3(dd[3]),
					n3(-dd[6]),
					n3(-dd[9]),
					n3(-dd[12]),
					quote(Inst.fullName(d))
				)
			end
		end
		local towers = Inst.findChild(ws, "AkyTowers")
		if towers then
			for _, f in Inst.children(towers) do
				local attrs = getmt(f).attrs or {}
				do
					local pn = tonumber(string.match(getmt(f).name, "%d+")) or 0
					plots[#plots + 1] = fmt(
						'{"plot":%d,"p":%s,"attrs":%s}',
						pn,
						quote(Inst.fullName(f)),
						anyJson(attrs, 3)
					)
				end
			end
		end
		-- Zähler je Gruppe
		local groups = {}
		local function bump(path, key)
			local g = groupOf(path)
			local e = groups[g]
			if e == nil then
				e = { parts = 0, lights = 0, enabled = 0 }
				groups[g] = e
			end
			e[key] += 1
		end
		for _, s in st.parts do
			local path = string.match(s, '"p":"(.-)","c"')
			if path then
				bump(path, "parts")
			end
		end
		for _, s in st.lights do
			local path = string.match(s, '"p":"(.-)","src"')
			if path then
				bump(path, "lights")
				if string.find(s, '"e":1', 1, true) then
					bump(path, "enabled")
				end
			end
		end
		local gnames = {}
		for g in groups do
			gnames[#gnames + 1] = g
		end
		table.sort(gnames, function(a, b)
			return groups[a].parts > groups[b].parts
		end)
		local gjson = {}
		local glines = {}
		for _, g in gnames do
			local e = groups[g]
			gjson[#gjson + 1] = fmt("%s:{\"parts\":%d,\"lights\":%d,\"lightsOn\":%d}", quote(g), e.parts, e.lights, e.enabled)
			glines[#glines + 1] = fmt("    %-52s %6d Teile %4d Lichter (%d an)", g, e.parts, e.lights, e.enabled)
		end
		local classLines = {}
		local cc = {}
		for k, v in st.classCount or {} do
			cc[#cc + 1] = { k, v }
		end
		table.sort(cc, function(a, b)
			return a[2] > b[2]
		end)
		local ccj = {}
		for i, e in cc do
			ccj[#ccj + 1] = quote(e[1]) .. ":" .. e[2]
			if i <= 24 then
				classLines[#classLines + 1] = fmt("%s %d", e[1], e[2])
			end
		end
		-- Config-Auszug
		local cfgJson = "null"
		if cfg then
			cfgJson = "{"
				.. '"City":'
				.. anyJson(cfg.City, 0)
				.. ',"Quality":'
				.. anyJson(cfg.Quality and cfg.Quality.Tiers, 0)
				.. ',"Tower":'
				.. anyJson(
					cfg.Tower
						and {
							FloorHeight = cfg.Tower.FloorHeight,
							Geometry = cfg.Tower.Geometry,
							Floors = cfg.Tower.Floors,
						},
					0
				)
				.. "}"
		end
		local towerLogJson = {}
		for _, l in log do
			towerLogJson[#towerLogJson + 1] = quote(l)
		end
		local out = {}
		out[#out + 1] = '{"meta":{'
			.. fmt(
				'"scenario":"world","simTime":%s,"joinedAt":%s,"mode":%s,"seed":%d,"unix":%s,"counts":{"serverParts":%d,"serverLights":%d,"serverGuis":%d,"serverFx":%d,"serverJoints":%d,"serverModels":%d,"clientParts":%d,"clientLights":%d,"nan":%d,"prompts":%d,"sounds":%d,"decals":%d},"groups":{%s},"classes":{%s},"towerLog":[%s]',
				n3(Sched.now),
				n3(joinedAt),
				quote(opts.studio and "studio" or "live"),
				R.config.seed,
				n3(Sched.unix()),
				st.counts.parts,
				st.counts.lights,
				st.counts.guis,
				st.counts.fx,
				st.counts.joints,
				st.counts.models,
				stClient.counts.parts,
				stClient.counts.lights,
				st.counts.nan + stClient.counts.nan,
				st.counts.prompts,
				st.counts.sounds,
				st.counts.decals,
				table.concat(gjson, ","),
				table.concat(ccj, ","),
				table.concat(towerLogJson, ",")
			)
			.. "},"
		out[#out + 1] = '"config":' .. cfgJson .. ","
		out[#out + 1] = '"terrain":' .. W.terrainJson(game) .. ","
		out[#out + 1] = '"anchors":[' .. table.concat(anchors, ",") .. "],"
		out[#out + 1] = '"plots":[' .. table.concat(plots, ",") .. "],"
		out[#out + 1] = '"client":[' .. table.concat(clientInfo, ",") .. "],"
		local function list(name, a, b, last)
			local all = table.clone(a)
			for _, x in b do
				all[#all + 1] = x
			end
			out[#out + 1] = '"' .. name .. '":[\n' .. table.concat(all, ",\n") .. "\n]" .. (last and "" or ",")
		end
		list("models", st.models, clientModels)
		list("parts", st.parts, clientParts)
		list("lights", st.lights, cLights)
		list("guis", st.guis, cGuis)
		list("fx", st.fx, cFx)
		list("joints", st.joints, cJoints, true)
		out[#out + 1] = "}"
		results.worldJson = table.concat(out, "\n")
		-- Bericht
		local info = results.info
		info[#info + 1] = fmt(
			"Welt (Server-Sicht nach %.1f s, %.1f s nach dem Beitritt): %d Teile, %d Lichter, %d SurfaceGui/BillboardGui, %d Effekte, %d Gelenke, %d Modelle, %d ProximityPrompts, %d NaN-CFrames",
			Sched.now,
			Sched.now - joinedAt,
			st.counts.parts,
			st.counts.lights,
			st.counts.guis,
			st.counts.fx,
			st.counts.joints,
			st.counts.models,
			st.counts.prompts,
			st.counts.nan
		)
		info[#info + 1] = fmt("Welt (nur Client, Phasen lobby/floor6): %d Teile, %d Lichter", stClient.counts.parts, stClient.counts.lights)
		info[#info + 1] = "Teile/Lichter je Gruppe (Server):"
		for i, l in glines do
			if i > 40 then
				break
			end
			info[#info + 1] = l
		end
		info[#info + 1] = "Klassen: " .. table.concat(classLines, ", ")
		info[#info + 1] = "Turm-Aufbau (Spieler 1, über Admin-/Request-Remote):"
		for _, l in log do
			info[#info + 1] = "    " .. l
		end
		local okCount = 0
		for _, l in log do
			if string.find(l, " Ok", 1, true) then
				okCount += 1
			end
		end
		results.checks[#results.checks + 1] = {
			name = "Welt: Turm-Aufbau über Remotes",
			ok = okCount > 0,
			detail = fmt("%d/%d Aufrufe Ok", okCount, #log),
		}
		results.checks[#results.checks + 1] = {
			name = "Welt: Server-Teile vorhanden",
			ok = st.counts.parts > 0,
			detail = tostring(st.counts.parts),
		}
		results.checks[#results.checks + 1] = {
			name = "Welt: Client-Interiors (lobby/floor6)",
			ok = stClient.counts.parts > 0,
			detail = tostring(stClient.counts.parts) .. " Teile",
		}
		return results
	end

	--- Einstieg für run.luau (gleicher Rahmen wie Sc.run: Modus, Fehler-Injektion, Berichte)
	function W.runScenario(name, bundle, opts)
		local t0 = os.clock()
		local results = { scenario = name, checks = {}, info = {} }
		R.config.studio = opts.studio == true
		if opts.streaming ~= nil then
			Net.streamingOverride = opts.streaming
		end
		if opts.faults then
			local parts = {}
			for k, v in opts.faults do
				R.Svc.faults[k] = v
				parts[#parts + 1] = k .. "=" .. v
			end
			table.sort(parts)
			results.info[#results.info + 1] = "Fehler-Injektion: " .. table.concat(parts, ", ")
		end
		opts.worldSeconds = opts.seconds or 30
		results.info[#results.info + 1] = fmt(
			"Modus: %s · Client: Spieler 1 (Besitzer) · Welt-Dump %d s nach dem Beitritt · %d Hz · Seed %d",
			opts.studio and "Studio (RunService:IsStudio() = true)" or "Live (RunService:IsStudio() = false)",
			opts.worldSeconds,
			R.config.frameRate,
			R.config.seed
		)
		W.run(bundle, opts, results)
		Sc.checkBoot(results, opts)
		Sc.netInfo(results)
		results.wall = os.clock() - t0
		Report.emit("report.txt", Sc.renderReport(results))
		local L = {}
		for _, o in Report.output do
			L[#L + 1] = fmt("[%7.2f %-18s %-5s] %s", o.t, o.ctx, o.kind, o.text)
		end
		Report.emit("output.txt", table.concat(L, "\n"))
		if results.uiTree then
			Report.emit("ui_tree.txt", results.uiTree)
		end
		Report.emit("world.json", results.worldJson or "{}")
		local ok, json = pcall(DT.json.encodeStrict, Sc.reportTable({
			scenario = results.scenario,
			checks = results.checks,
			info = results.info,
			wall = results.wall,
		}))
		Report.emit("report.json", ok and json or ('{"error": ' .. DT.json.quote(tostring(json)) .. "}"))
		return results
	end

	return W
end
