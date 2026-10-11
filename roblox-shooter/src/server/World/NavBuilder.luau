-- =====================================================================
--  CLUTCH CLASH – Nav-Graph für Bots (Server/World/NavBuilder)
--  Besitzer: WP2 (Welt). Vertrag: DESIGN.md B8.1 (Nav-Graph) + C4 (Types.NavGraph).
--  Läuft beim Template-Bau, während die Map kurz im Workspace steht (Staging (0, 3000, 0)).
--  Ergebnis RELATIV zum Map-Ursprung (Bodenmitte) – WP6 Pathfind rechnet mit Arena.Origin um.
--
--  Ablauf:
--    1) Raster (Config.Maps.Nav.Grid = 6): pro Spalte Strahlen nach unten, bis zu 4 Ebenen
--       (Brücken, Wehrgänge, Dächer). Begehbar = Fläche zeigt nach oben (Normal.Y ≥ 0.7) und
--       Kopffreiheit ≥ Headroom (5.5) – auch kein Teil, in dem der Punkt steckt.
--    2) Extra-Knoten: CoverNodes (A + gespiegelt, Cover = true), Zone, Stützpunkte auf Brücken
--       (Teile mit Namen "Bridge", auch schräge).
--    3) Kanten zu den 8 Rasternachbarn (Extras: alle Knoten im Umkreis 1.5 Raster):
--       Höhenunterschied ≤ StepMax (4.5), freier Weg auf Knie- und Kopfhöhe über dem höheren
--       Knoten, Boden unter der Mitte (keine Kante über Löcher/Leere).
--    4) Hauptkomponente = die mit dem Zonen-Knoten. Alles andere wird entfernt; Inseln mit
--       ≥ 3 Knoten oder mit Deckungs-Knoten -> warn (Dächer/Kistendeckel einzeln sind normal).
--    5) Mehr als MaxNodes (300) -> Raster um 1 Stud gröber, höchstens 4 Versuche.
--
--  Öffentliche API (WP2-intern + WorldTests):
--    NavBuilder.Build(model, layout, origin): (Types.NavGraph, Report)
--    NavBuilder.Components(nav): { number }               Größe jeder Komponente (absteigend)
--    NavBuilder.Nearest(nav, localPos, maxHoriz?, maxDy?): number?
--    NavBuilder.Reachable(nav, fromIndex): { [number]: boolean }
--    NavBuilder.SpawnBlockers(model, layout, origin, box): { string }   Spawns mit Teil im Kopfbereich
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Config = require(Shared:WaitForChild("Config"))
local MapKit = require(script.Parent:WaitForChild("MapKit"))

local NavBuilder = {}

export type Report = {
	Key: string,
	Grid: number,
	Attempts: number,
	Nodes: number,
	Edges: number,
	Pruned: number,
	LostIslands: number,
	ZoneOk: boolean,
	SpawnsOk: boolean,
	BadSpawns: { string },
}

type Node = { P: Vector3, Cover: boolean, Col: number?, Kind: string }
type Ctx = {
	Origin: CFrame,
	Params: RaycastParams,
	Head: number,
	Step: number,
	TopY: number,
	BottomY: number,
}

local MAX_LEVELS = 4 -- Ebenen pro Rasterspalte
local MAX_ATTEMPTS = 4
local GRID_OFFSET = 0.37 -- Raster nicht genau auf Teilekanten (viele Kanten liegen auf Vielfachen von 6)
local EDGE_MARGIN = 1.2 -- Abstand zu den Außengrenzen
local NORMAL_MIN = 0.7
local KNEE = 1.0
local HEAD = 2.6
local BRIDGE_STEP = 4
local ZONE_PROBES = {
	Vector3.zero,
	Vector3.new(3, 0, 0),
	Vector3.new(-3, 0, 0),
	Vector3.new(0, 0, 3),
	Vector3.new(0, 0, -3),
	Vector3.new(5, 0, 0),
	Vector3.new(-5, 0, 0),
	Vector3.new(0, 0, 5),
	Vector3.new(0, 0, -5),
}

-- ---------------------------------------------------------------------
-- Strahlen in lokalen Koordinaten
-- ---------------------------------------------------------------------
local function cast(ctx: Ctx, fromLocal: Vector3, deltaLocal: Vector3): RaycastResult?
	return workspace:Raycast(
		ctx.Origin:PointToWorldSpace(fromLocal),
		ctx.Origin:VectorToWorldSpace(deltaLocal),
		ctx.Params
	)
end

-- Unterkante des achsparallelen Hüllquaders eines Teils (lokal)
local function bottomOf(ctx: Ctx, part: BasePart): number
	local cf = ctx.Origin:ToObjectSpace(part.CFrame)
	local s = part.Size / 2
	local _, _, _, _, _, _, r10, r11, r12 = cf:GetComponents()
	return cf.Y - (math.abs(r10) * s.X + math.abs(r11) * s.Y + math.abs(r12) * s.Z)
end

-- Alle begehbaren Flächen einer Spalte (lokale Y-Werte, von oben nach unten)
local function surfacesAt(ctx: Ctx, x: number, z: number): { number }
	local ys: { number } = {}
	local y = ctx.TopY
	local prevBottom: number? = nil
	for _ = 1, MAX_LEVELS do
		local dist = y - ctx.BottomY
		if dist <= 0 then
			break
		end
		local hit = cast(ctx, Vector3.new(x, y, z), Vector3.new(0, -dist, 0))
		if not hit then
			break
		end
		local hitY = ctx.Origin:PointToObjectSpace(hit.Position).Y
		local normalUp = ctx.Origin:VectorToObjectSpace(hit.Normal).Y
		local ok = normalUp >= NORMAL_MIN
		-- Der Strahl kam aus dem vorher getroffenen Teil: steht der darüber, ist kein Platz
		if ok and prevBottom ~= nil and prevBottom - hitY < ctx.Head then
			ok = false
		end
		if ok then
			local blocked = cast(ctx, Vector3.new(x, hitY + 0.1, z), Vector3.new(0, ctx.Head - 0.1, 0))
			if blocked then
				ok = false
			end
		end
		if ok then
			table.insert(ys, hitY)
		end
		local part = hit.Instance
		prevBottom = if part:IsA("BasePart") then bottomOf(ctx, part) else hitY
		y = hitY - 0.05
	end
	return ys
end

-- Fläche einer Spalte, die einer Wunsch-Höhe am nächsten liegt
local function projectTo(ctx: Ctx, p: Vector3, maxDy: number): Vector3?
	local best: number? = nil
	local bestD = math.huge
	for _, y in ipairs(surfacesAt(ctx, p.X, p.Z)) do
		local d = math.abs(y - p.Y)
		if d < bestD then
			bestD = d
			best = y
		end
	end
	if best == nil or bestD > maxDy then
		return nil
	end
	return Vector3.new(p.X, best, p.Z)
end

-- Darf ein Bot von a nach b gehen/springen?
local function canLink(ctx: Ctx, a: Vector3, b: Vector3): boolean
	if math.abs(a.Y - b.Y) > ctx.Step then
		return false
	end
	local high = math.max(a.Y, b.Y)
	local low = math.min(a.Y, b.Y)
	for _, lift in ipairs({ KNEE, HEAD }) do
		local from = Vector3.new(a.X, high + lift, a.Z)
		local to = Vector3.new(b.X, high + lift, b.Z)
		if cast(ctx, from, to - from) then
			return false
		end
	end
	-- Boden unter der Mitte (sonst Kante über Loch/Leere)
	local mid = Vector3.new((a.X + b.X) / 2, high + KNEE, (a.Z + b.Z) / 2)
	local drop = (high + KNEE) - (low - 1.5)
	local ground = cast(ctx, mid, Vector3.new(0, -drop, 0))
	if not ground then
		return false
	end
	return true
end

-- ---------------------------------------------------------------------
-- Bau
-- ---------------------------------------------------------------------
local function settings(): (number, number, number, number)
	local nav = Config.Maps.Nav or {}
	return tonumber(nav.Grid) or 6, tonumber(nav.Headroom) or 5.5, tonumber(nav.StepMax) or 4.5, tonumber(nav.MaxNodes)
		or 300
end

-- Oberkante aller abfragbaren Teile (lokal) – Startpunkt der Strahlen
local function topOf(model: Model, origin: CFrame): number
	local top = 0
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") and inst.CanQuery then
			local cf = origin:ToObjectSpace(inst.CFrame)
			local s = inst.Size / 2
			local _, _, _, _, _, _, r10, r11, r12 = cf:GetComponents()
			local t = cf.Y + math.abs(r10) * s.X + math.abs(r11) * s.Y + math.abs(r12) * s.Z
			if t > top then
				top = t
			end
		end
	end
	return top + 1
end

local function bridgeSamples(ctx: Ctx, model: Model): { Vector3 }
	local out: { Vector3 } = {}
	for _, inst in ipairs(model:GetChildren()) do
		if inst:IsA("BasePart") and inst.Name == "Bridge" then
			local cf = ctx.Origin:ToObjectSpace(inst.CFrame)
			local size = inst.Size
			local alongZ = size.Z >= size.X
			local length = if alongZ then size.Z else size.X
			local count = math.max(1, math.floor((length - 2) / BRIDGE_STEP) + 1)
			for i = 0, count - 1 do
				local t = if count == 1 then 0 else -((length - 2) / 2) + i * ((length - 2) / (count - 1))
				local localOffset = if alongZ then Vector3.new(0, size.Y / 2, t) else Vector3.new(t, size.Y / 2, 0)
				table.insert(out, cf:PointToWorldSpace(localOffset))
			end
		end
	end
	return out
end

type Attempt = {
	Nodes: { Node },
	Adj: { { number } },
	EdgeCount: number,
	ZoneIndex: number?,
}

local function attempt(ctx: Ctx, layout: Types.MapLayout, model: Model, grid: number): Attempt
	local nodes: { Node } = {}
	local adj: { { number } } = {}
	local edgeCount = 0
	local columns: { [number]: { number } } = {}

	local minX, maxX, minZ, maxZ
	if layout.CustomBounds then
		minX, maxX = layout.CustomBounds.Min.X, layout.CustomBounds.Max.X
		minZ, maxZ = layout.CustomBounds.Min.Z, layout.CustomBounds.Max.Z
	else
		minX, maxX = -layout.Size.X / 2, layout.Size.X / 2
		minZ, maxZ = -layout.Size.Z / 2, layout.Size.Z / 2
	end
	minX += EDGE_MARGIN
	maxX -= EDGE_MARGIN
	minZ += EDGE_MARGIN
	maxZ -= EDGE_MARGIN

	local function addNode(p: Vector3, cover: boolean, col: number?, kind: string): number
		table.insert(nodes, { P = p, Cover = cover, Col = col, Kind = kind })
		table.insert(adj, {})
		return #nodes
	end
	local function link(i: number, j: number)
		if i == j or table.find(adj[i], j) then
			return
		end
		table.insert(adj[i], j)
		table.insert(adj[j], i)
		edgeCount += 1
	end
	local function colKey(ix: number, iz: number): number
		return (ix + 1000) * 4096 + (iz + 1000)
	end

	-- 1) Raster
	local ixMin = math.ceil((minX - GRID_OFFSET) / grid)
	local ixMax = math.floor((maxX - GRID_OFFSET) / grid)
	local izMin = math.ceil((minZ - GRID_OFFSET) / grid)
	local izMax = math.floor((maxZ - GRID_OFFSET) / grid)
	for ix = ixMin, ixMax do
		for iz = izMin, izMax do
			local x = ix * grid + GRID_OFFSET
			local z = iz * grid + GRID_OFFSET
			local key = colKey(ix, iz)
			for _, y in ipairs(surfacesAt(ctx, x, z)) do
				local index = addNode(Vector3.new(x, y, z), false, key, "Grid")
				local list = columns[key]
				if not list then
					list = {}
					columns[key] = list
				end
				table.insert(list, index)
			end
		end
	end
	-- Kanten zu den Nachbarspalten (4 Richtungen reichen, Kanten sind symmetrisch)
	for ix = ixMin, ixMax do
		for iz = izMin, izMax do
			local here = columns[colKey(ix, iz)]
			if here then
				for _, d in ipairs({ { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, -1 } }) do
					local there = columns[colKey(ix + d[1], iz + d[2])]
					if there then
						for _, i in ipairs(here) do
							for _, j in ipairs(there) do
								if canLink(ctx, nodes[i].P, nodes[j].P) then
									link(i, j)
								end
							end
						end
					end
				end
			end
		end
	end

	-- 2) Extra-Knoten
	local extras: { number } = {}
	local zoneIndex: number? = nil
	-- Zonen-Mitte kann in einem Teil stecken (Crown Ring: Kiste) -> Punkte im Zonenkreis probieren
	for _, offset in ipairs(ZONE_PROBES) do
		local zoneP = projectTo(ctx, layout.Zone + offset, 3)
		if zoneP then
			zoneIndex = addNode(zoneP, false, nil, "Zone")
			table.insert(extras, zoneIndex :: number)
			break
		end
	end
	for _, p in ipairs(MapKit.CoverPoints(layout)) do
		local projected = projectTo(ctx, p, 3)
		if projected then
			table.insert(extras, addNode(projected, true, nil, "Cover"))
		else
			warn(("[Nav] %s: Deckungs-Knoten %s hat keinen Boden"):format(layout.Key, tostring(p)))
		end
	end
	for _, p in ipairs(bridgeSamples(ctx, model)) do
		local projected = projectTo(ctx, p, 1)
		if projected then
			table.insert(extras, addNode(projected, false, nil, "Bridge"))
		end
	end
	local radius = grid * 1.5
	for _, e in ipairs(extras) do
		local pe = nodes[e].P
		for j = 1, #nodes do
			if j ~= e then
				local pj = nodes[j].P
				local horizontal = Vector2.new(pe.X - pj.X, pe.Z - pj.Z).Magnitude
				if horizontal <= radius and canLink(ctx, pe, pj) then
					link(e, j)
				end
			end
		end
	end

	return { Nodes = nodes, Adj = adj, EdgeCount = edgeCount, ZoneIndex = zoneIndex }
end

-- Breitensuche: Komponente jedes Knotens
local function components(adj: { { number } }): ({ number }, { number })
	local comp: { number } = table.create(#adj, 0)
	local sizes: { number } = {}
	for start = 1, #adj do
		if comp[start] == 0 then
			local id = #sizes + 1
			local size = 0
			local queue = { start }
			comp[start] = id
			local head = 1
			while head <= #queue do
				local i = queue[head]
				head += 1
				size += 1
				for _, j in ipairs(adj[i]) do
					if comp[j] == 0 then
						comp[j] = id
						table.insert(queue, j)
					end
				end
			end
			sizes[id] = size
		end
	end
	return comp, sizes
end

local function nearestIn(nodes: { Node }, keep: { [number]: boolean }?, p: Vector3, maxHoriz: number, maxDy: number): number?
	local best: number? = nil
	local bestD = math.huge
	for i, node in ipairs(nodes) do
		if keep == nil or keep[i] then
			local dy = math.abs(node.P.Y - p.Y)
			if dy <= maxDy then
				local d = Vector2.new(node.P.X - p.X, node.P.Z - p.Z).Magnitude
				if d <= maxHoriz and d < bestD then
					bestD = d
					best = i
				end
			end
		end
	end
	return best
end

function NavBuilder.Build(model: Model, layout: Types.MapLayout, origin: CFrame): (Types.NavGraph, Report)
	local grid, headroom, stepMax, maxNodes = settings()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.IncludeInstances = { model }
	params.RespectCanCollide = true
	params.IgnoreWater = true
	local ctx: Ctx = {
		Origin = origin,
		Params = params,
		Head = headroom,
		Step = stepMax,
		TopY = topOf(model, origin),
		BottomY = (layout.KillY or -40) + 1,
	}

	local result: Attempt? = nil
	local keep: { [number]: boolean } = {}
	local kept = 0
	local pruned = 0
	local lost = 0
	local attempts = 0
	for _ = 1, MAX_ATTEMPTS do
		attempts += 1
		local current = attempt(ctx, layout, model, grid)
		local comp, sizes = components(current.Adj)
		-- Hauptkomponente: die mit der Zone, sonst die größte
		local main = 0
		if current.ZoneIndex then
			main = comp[current.ZoneIndex :: number]
		else
			local bestSize = -1
			for id, size in ipairs(sizes) do
				if size > bestSize then
					bestSize = size
					main = id
				end
			end
		end
		keep = {}
		kept, pruned, lost = 0, 0, 0
		local lostIds: { [number]: boolean } = {}
		for i, node in ipairs(current.Nodes) do
			if comp[i] == main then
				keep[i] = true
				kept += 1
			else
				pruned += 1
				local id = comp[i]
				if (sizes[id] >= 3 or node.Cover) and not lostIds[id] then
					lostIds[id] = true
					lost += 1
				end
			end
		end
		result = current
		if kept <= maxNodes then
			break
		end
		grid += 1
	end
	local final = result :: Attempt

	-- Neu nummerieren (nur Hauptkomponente)
	local newIndex: { [number]: number } = {}
	local nav: Types.NavGraph = { Nodes = {}, Edges = {} }
	for i, node in ipairs(final.Nodes) do
		if keep[i] then
			table.insert(nav.Nodes, { P = node.P, Cover = node.Cover })
			newIndex[i] = #nav.Nodes
		end
	end
	local edgeCount = 0
	for i, list in ipairs(final.Adj) do
		local ni = newIndex[i]
		if ni then
			local out: { number } = {}
			for _, j in ipairs(list) do
				local nj = newIndex[j]
				if nj then
					table.insert(out, nj)
					if nj > ni then
						edgeCount += 1
					end
				end
			end
			nav.Edges[ni] = out
		end
	end

	-- Zone und Spawns erreichbar?
	local zoneOk = final.ZoneIndex ~= nil and keep[final.ZoneIndex :: number] == true
	local badSpawns: { string } = {}
	local a, b, ffa = MapKit.SpawnCFrames(layout)
	local function checkSpawns(list: { CFrame }, label: string)
		for index, cf in ipairs(list) do
			local ground = cf.Position - Vector3.new(0, 3, 0)
			if not nearestIn(final.Nodes, keep, ground, grid * 1.5 + 1, 2.5) then
				table.insert(badSpawns, ("%s%d"):format(label, index))
			end
		end
	end
	checkSpawns(a, "A")
	checkSpawns(b, "B")
	checkSpawns(ffa, "FFA")

	if kept > maxNodes then
		warn(("[Nav] %s: %d Knoten (Grenze %d) auch mit Raster %d"):format(layout.Key, kept, maxNodes, grid))
	end
	if lost > 0 then
		warn(("[Nav] %s: %d unerreichbare Bereiche entfernt (%d Knoten)"):format(layout.Key, lost, pruned))
	end
	if not zoneOk then
		warn(("[Nav] %s: Zone nicht erreichbar"):format(layout.Key))
	end
	if #badSpawns > 0 then
		warn(("[Nav] %s: Spawns ohne Nav-Anschluss: %s"):format(layout.Key, table.concat(badSpawns, ", ")))
	end

	local report: Report = {
		Key = layout.Key,
		Grid = grid,
		Attempts = attempts,
		Nodes = #nav.Nodes,
		Edges = edgeCount,
		Pruned = pruned,
		LostIslands = lost,
		ZoneOk = zoneOk,
		SpawnsOk = #badSpawns == 0,
		BadSpawns = badSpawns,
	}
	return nav, report
end

-- ---------------------------------------------------------------------
-- Spawn-Freiheit: Box über jedem Spawn (A, B, FFA) darf kein kollidierendes Teil berühren
-- ---------------------------------------------------------------------
function NavBuilder.SpawnBlockers(model: Model, layout: Types.MapLayout, origin: CFrame, box: Vector3): { string }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.IncludeInstances = { model }
	params.RespectCanCollide = true
	params.MaxParts = 4
	local bad: { string } = {}
	local a, b, ffa = MapKit.SpawnCFrames(layout)
	local function check(list: { CFrame }, label: string)
		for index, cf in ipairs(list) do
			local hits = workspace:GetPartBoundsInBox(origin * cf, box, params)
			if #hits > 0 then
				table.insert(bad, ("%s%d(%s)"):format(label, index, hits[1].Name))
			end
		end
	end
	check(a, "A")
	check(b, "B")
	check(ffa, "FFA")
	return bad
end

-- ---------------------------------------------------------------------
-- Helfer für Tests / Auswertung
-- ---------------------------------------------------------------------
function NavBuilder.Components(nav: Types.NavGraph): { number }
	local _, sizes = components(nav.Edges)
	table.sort(sizes, function(x, y)
		return x > y
	end)
	return sizes
end

function NavBuilder.Reachable(nav: Types.NavGraph, fromIndex: number): { [number]: boolean }
	local seen: { [number]: boolean } = {}
	if not nav.Nodes[fromIndex] then
		return seen
	end
	local queue = { fromIndex }
	seen[fromIndex] = true
	local head = 1
	while head <= #queue do
		local i = queue[head]
		head += 1
		for _, j in ipairs(nav.Edges[i] or {}) do
			if not seen[j] then
				seen[j] = true
				table.insert(queue, j)
			end
		end
	end
	return seen
end

function NavBuilder.Nearest(nav: Types.NavGraph, localPos: Vector3, maxHoriz: number?, maxDy: number?): number?
	local nodes: { Node } = {}
	for _, node in ipairs(nav.Nodes) do
		table.insert(nodes, { P = node.P, Cover = node.Cover, Col = nil, Kind = "" })
	end
	return nearestIn(nodes, nil, localPos, maxHoriz or math.huge, maxDy or math.huge)
end

return NavBuilder
