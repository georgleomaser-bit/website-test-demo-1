--!strict
-- =====================================================================
--  CLUTCH CLASH – A* auf dem Nav-Graph (Server/Bot/Pathfind)
--  Besitzer: WP6 (Bots & Training-Range). Vertrag: DESIGN.md B10.3 (Navigation) + C4 (NavGraph).
--  Reines Rechenmodul (keine Services, kein Yield). Graph kommt von WP2 (NavBuilder → Arena.Nav).
--
--  Öffentliche API:
--    Pathfind.Prepare(nav, origin?): Graph        Nav-Graph -> Welt-Koordinaten, symmetrische Nachbarn,
--                                                 Kosten, Komponenten, Raster-Hash (einmal pro Arena)
--    Pathfind.ForArena(arena): Graph              wie Prepare, gecacht pro Arena (schwache Tabelle)
--    Pathfind.Empty(g): boolean                   kein Knoten (z. B. Range ohne Nav)
--    Pathfind.Nearest(g, pos, maxDist?): (index?, dist)   nächster Knoten (Raster, sonst alle)
--    Pathfind.Find(g, from, to, maxExpand?): { index }?    A* mit Binär-Heap (Start..Ziel inkl.)
--    Pathfind.Path(g, fromPos, toPos): { index }?         nächste Knoten + A*, Ziel notfalls in
--                                                         der eigenen Komponente
--    Pathfind.IsWalkable(g, pos, footY): boolean  liegt pos über begehbarem Boden (für Seitwärts-Schritte)
--    Pathfind.NodesNear(g, pos, radius, coverOnly?): { index }
--
--  Hinweis zu Nav.Edges: Vertrag C4 = { { number } }. Gelesen wird es wörtlich als Nachbarliste
--  pro Knoten (Edges[i] = { j, k, … }). Eine Kantenliste aus Paaren ({ a, b }) wird erkannt und
--  ebenfalls verstanden. Kanten werden immer symmetrisch gemacht.
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local Pathfind = {}

export type Graph = {
	Count: number,
	P: { Vector3 }, -- Welt-Position (Boden-Oberkante) je Knoten
	Cover: { boolean },
	CoverList: { number },
	Adj: { { number } }, -- symmetrische Nachbarn
	Cost: { { number } }, -- Kosten parallel zu Adj
	Comp: { number }, -- Komponenten-Nummer je Knoten
	CompSize: { number },
	Spacing: number, -- typischer Knotenabstand (≈ Raster 6)
	CellSize: number,
	Cells: { [number]: { number } },
	-- Arbeitsspeicher für A* (Stempel statt neuer Tabellen pro Suche)
	Stamp: number,
	GScore: { number },
	Parent: { number },
	Seen: { number },
	Closed: { number },
}

local DEFAULT_SPACING = 6
local MAX_NODES = 2000 -- Schutz (Vertrag: ≤ 300)
local CELL_OFFSET = 32768

local function emptyGraph(): Graph
	return {
		Count = 0,
		P = {},
		Cover = {},
		CoverList = {},
		Adj = {},
		Cost = {},
		Comp = {},
		CompSize = {},
		Spacing = DEFAULT_SPACING,
		CellSize = DEFAULT_SPACING,
		Cells = {},
		Stamp = 0,
		GScore = {},
		Parent = {},
		Seen = {},
		Closed = {},
	}
end

local function cellKey(cs: number, x: number, z: number): number
	local ix = math.floor(x / cs) + CELL_OFFSET
	local iz = math.floor(z / cs) + CELL_OFFSET
	return ix * 65536 + iz
end

local function isFiniteVector(v: any): boolean
	if typeof(v) ~= "Vector3" then
		return false
	end
	local x, y, z = v.X, v.Y, v.Z
	return x == x and y == y and z == z and math.abs(x) < 1e7 and math.abs(y) < 1e7 and math.abs(z) < 1e7
end

-- Kantenliste aus Paaren? (alle Einträge Länge 2, Anzahl ≠ Knoten oder nicht symmetrisch als Nachbarliste)
local function looksLikePairs(edges: { { number } }, count: number): boolean
	if #edges == 0 then
		return false
	end
	for _, e in ipairs(edges) do
		if type(e) ~= "table" or #e ~= 2 then
			return false
		end
	end
	if #edges ~= count then
		return true
	end
	-- gleiche Anzahl: als Nachbarliste symmetrisch? Dann Nachbarliste.
	for i, list in ipairs(edges) do
		for _, j in ipairs(list) do
			local back = edges[j]
			if type(back) ~= "table" then
				return true
			end
			local found = false
			for _, k in ipairs(back) do
				if k == i then
					found = true
					break
				end
			end
			if not found then
				return true
			end
		end
	end
	return false
end

-- Nav-Graph (C4) in einen fertigen Such-Graphen verwandeln.
-- origin: Arena-Ursprung. Liegen die Knoten offensichtlich relativ zum Ursprung (gespeichert
-- relativ zur Map, B8.1), werden sie in Welt-Koordinaten umgerechnet.
function Pathfind.Prepare(nav: Types.NavGraph?, origin: CFrame?): Graph
	local g = emptyGraph()
	local raw: any = nav
	if type(raw) ~= "table" or type(raw.Nodes) ~= "table" then
		return g
	end
	local nodes: { any } = raw.Nodes
	local count = math.min(#nodes, MAX_NODES)
	if count == 0 then
		return g
	end

	-- 1) Positionen lesen (kaputte Knoten bleiben als isolierte Knoten an Ort 0 drin -> Indizes stimmen)
	local positions: { Vector3 } = table.create(count)
	local valid: { boolean } = table.create(count, false)
	local sum = Vector3.zero
	local validCount = 0
	for i = 1, count do
		local node = nodes[i]
		local p = if type(node) == "table" then node.P else nil
		if isFiniteVector(p) then
			positions[i] = p
			valid[i] = true
			sum += p
			validCount += 1
		else
			positions[i] = Vector3.zero
		end
	end
	if validCount == 0 then
		return g
	end

	-- 2) relativ oder Welt? Schwerpunkt näher am Ursprung -> Welt, sonst relativ
	if origin then
		local centroid = sum / validCount
		local toOrigin = (centroid - origin.Position).Magnitude
		if toOrigin > centroid.Magnitude then
			for i = 1, count do
				if valid[i] then
					positions[i] = origin:PointToWorldSpace(positions[i])
				end
			end
		end
	end

	g.Count = count
	g.P = positions
	for i = 1, count do
		local node = nodes[i]
		local cover = type(node) == "table" and node.Cover == true and valid[i]
		g.Cover[i] = cover
		if cover then
			table.insert(g.CoverList, i)
		end
		g.Adj[i] = {}
		g.Cost[i] = {}
	end

	-- 3) Kanten (symmetrisch, ohne Doppelte)
	local edgeSeen: { [number]: boolean } = {}
	local function link(a: number, b: number)
		if a == b or a < 1 or b < 1 or a > count or b > count or a % 1 ~= 0 or b % 1 ~= 0 then
			return
		end
		if not (valid[a] and valid[b]) then
			return
		end
		local lo, hi = math.min(a, b), math.max(a, b)
		local key = lo * (MAX_NODES + 1) + hi
		if edgeSeen[key] then
			return
		end
		edgeSeen[key] = true
		local cost = (positions[a] - positions[b]).Magnitude
		table.insert(g.Adj[a], b)
		table.insert(g.Cost[a], cost)
		table.insert(g.Adj[b], a)
		table.insert(g.Cost[b], cost)
	end
	local edges: any = raw.Edges
	if type(edges) == "table" then
		if looksLikePairs(edges, count) then
			for _, e in ipairs(edges) do
				local a, b = e[1], e[2]
				if type(a) == "number" and type(b) == "number" then
					link(a, b)
				end
			end
		else
			for i = 1, math.min(#edges, count) do
				local list = edges[i]
				if type(list) == "table" then
					for _, j in ipairs(list) do
						if type(j) == "number" then
							link(i, j)
						end
					end
				end
			end
		end
	end

	-- 4) typischer Abstand (Mittel der kürzesten Kante je Knoten) -> Raster-Zellgröße
	local spacingSum, spacingCount = 0, 0
	for i = 1, count do
		local best = math.huge
		for _, c in ipairs(g.Cost[i]) do
			if c < best then
				best = c
			end
		end
		if best < math.huge then
			spacingSum += best
			spacingCount += 1
		end
	end
	g.Spacing = if spacingCount > 0 then math.clamp(spacingSum / spacingCount, 2, 20) else DEFAULT_SPACING
	g.CellSize = g.Spacing
	for i = 1, count do
		if valid[i] then
			local p = positions[i]
			local key = cellKey(g.CellSize, p.X, p.Z)
			local bucket = g.Cells[key]
			if bucket == nil then
				bucket = {}
				g.Cells[key] = bucket
			end
			table.insert(bucket, i)
		end
	end

	-- 5) Komponenten (Breitensuche, gebunden durch count)
	local compId = 0
	for i = 1, count do
		g.Comp[i] = 0
	end
	for start = 1, count do
		if g.Comp[start] == 0 and valid[start] then
			compId += 1
			local size = 0
			local queue = { start }
			g.Comp[start] = compId
			local head = 1
			while head <= #queue do
				local cur = queue[head]
				head += 1
				size += 1
				for _, nb in ipairs(g.Adj[cur]) do
					if g.Comp[nb] == 0 then
						g.Comp[nb] = compId
						table.insert(queue, nb)
					end
				end
			end
			g.CompSize[compId] = size
		end
	end

	g.GScore = table.create(count, 0)
	g.Parent = table.create(count, 0)
	g.Seen = table.create(count, 0)
	g.Closed = table.create(count, 0)
	return g
end

-- Gecacht pro Arena-Tabelle (neu, wenn Nav oder Ursprung wechseln)
type CacheEntry = { Nav: any, Origin: CFrame?, Graph: Graph }
local cache: { [any]: CacheEntry } = setmetatable({}, { __mode = "k" }) :: any

function Pathfind.ForArena(arena: Types.Arena?): Graph
	local raw: any = arena
	if type(raw) ~= "table" then
		return emptyGraph()
	end
	local nav = raw.Nav
	local origin: CFrame? = if typeof(raw.Origin) == "CFrame" then raw.Origin else nil
	local entry = cache[raw]
	if entry and entry.Nav == nav and entry.Origin == origin then
		return entry.Graph
	end
	local graph = Pathfind.Prepare(nav, origin)
	cache[raw] = { Nav = nav, Origin = origin, Graph = graph }
	return graph
end

function Pathfind.Empty(g: Graph): boolean
	return g.Count == 0
end

-- Nächster Knoten (horizontal + leicht vertikal gewichtet). Erst Raster (3×3, dann 5×5), sonst alle.
function Pathfind.Nearest(g: Graph, pos: Vector3, maxDist: number?): (number?, number)
	if g.Count == 0 then
		return nil, math.huge
	end
	local limit = maxDist or math.huge
	local cs = g.CellSize
	local best: number? = nil
	local bestD = math.huge
	local function consider(i: number)
		local p = g.P[i]
		local dx, dy, dz = p.X - pos.X, (p.Y - pos.Y) * 1.5, p.Z - pos.Z
		local d = math.sqrt(dx * dx + dy * dy + dz * dz)
		if d < bestD then
			bestD = d
			best = i
		end
	end
	local cx = math.floor(pos.X / cs)
	local cz = math.floor(pos.Z / cs)
	for ring = 1, 2 do
		for ix = cx - ring, cx + ring do
			for iz = cz - ring, cz + ring do
				-- nur den neuen Rand prüfen (Ring 1 = 3×3 komplett)
				if ring == 1 or math.abs(ix - cx) == ring or math.abs(iz - cz) == ring then
					local bucket = g.Cells[(ix + CELL_OFFSET) * 65536 + (iz + CELL_OFFSET)]
					if bucket then
						for _, i in ipairs(bucket) do
							consider(i)
						end
					end
				end
			end
		end
		if best ~= nil and bestD <= cs * ring then
			break
		end
	end
	if best == nil and limit > cs * 2 then
		for i = 1, g.Count do
			if g.Comp[i] ~= 0 then
				consider(i)
			end
		end
	end
	if best == nil or bestD > limit then
		return nil, bestD
	end
	return best, bestD
end

-- Binär-Heap (min) über parallele Arrays
local function heapPush(nodes: { number }, keys: { number }, node: number, key: number)
	local i = #nodes + 1
	nodes[i] = node
	keys[i] = key
	while i > 1 do
		local parent = i // 2
		if keys[parent] <= keys[i] then
			break
		end
		nodes[parent], nodes[i] = nodes[i], nodes[parent]
		keys[parent], keys[i] = keys[i], keys[parent]
		i = parent
	end
end

local function heapPop(nodes: { number }, keys: { number }): number
	local top = nodes[1]
	local last = #nodes
	nodes[1] = nodes[last]
	keys[1] = keys[last]
	nodes[last] = nil
	keys[last] = nil
	last -= 1
	local i = 1
	while true do
		local l = i * 2
		local r = l + 1
		local smallest = i
		if l <= last and keys[l] < keys[smallest] then
			smallest = l
		end
		if r <= last and keys[r] < keys[smallest] then
			smallest = r
		end
		if smallest == i then
			break
		end
		nodes[smallest], nodes[i] = nodes[i], nodes[smallest]
		keys[smallest], keys[i] = keys[i], keys[smallest]
		i = smallest
	end
	return top
end

-- A* von Knoten from nach to. Gibt die Knotenliste (inkl. Start und Ziel) oder nil zurück.
-- maxExpand begrenzt die Arbeit (Standard: alle Knoten einmal).
function Pathfind.Find(g: Graph, from: number, to: number, maxExpand: number?): { number }?
	if g.Count == 0 or from < 1 or to < 1 or from > g.Count or to > g.Count then
		return nil
	end
	if from == to then
		return { from }
	end
	if g.Comp[from] == 0 or g.Comp[from] ~= g.Comp[to] then
		return nil
	end
	g.Stamp += 1
	local stamp = g.Stamp
	local P, gScore, parent, seen, closed = g.P, g.GScore, g.Parent, g.Seen, g.Closed
	local goal = P[to]
	local heapNodes: { number } = {}
	local heapKeys: { number } = {}
	gScore[from] = 0
	parent[from] = 0
	seen[from] = stamp
	heapPush(heapNodes, heapKeys, from, (P[from] - goal).Magnitude)
	local budget = maxExpand or (g.Count + 8)
	local expanded = 0
	while #heapNodes > 0 do
		local cur = heapPop(heapNodes, heapKeys)
		if closed[cur] ~= stamp then
			if cur == to then
				-- Pfad rückwärts einsammeln (gebunden durch Count)
				local path: { number } = {}
				local node = to
				local guard = 0
				while node ~= 0 and guard <= g.Count do
					table.insert(path, node)
					node = parent[node]
					guard += 1
				end
				-- umdrehen
				local n = #path
				for i = 1, n // 2 do
					path[i], path[n - i + 1] = path[n - i + 1], path[i]
				end
				return path
			end
			closed[cur] = stamp
			expanded += 1
			if expanded > budget then
				return nil
			end
			local base = gScore[cur]
			local adj, cost = g.Adj[cur], g.Cost[cur]
			for k = 1, #adj do
				local nb = adj[k]
				if closed[nb] ~= stamp then
					local tentative = base + cost[k]
					if seen[nb] ~= stamp or tentative < gScore[nb] then
						seen[nb] = stamp
						gScore[nb] = tentative
						parent[nb] = cur
						heapPush(heapNodes, heapKeys, nb, tentative + (P[nb] - goal).Magnitude)
					end
				end
			end
		end
	end
	return nil
end

-- Bester Knoten nahe target in der Komponente comp (Ersatz-Ziel, wenn das echte unerreichbar ist)
local function nearestInComponent(g: Graph, target: Vector3, comp: number): number?
	local best: number? = nil
	local bestD = math.huge
	for i = 1, g.Count do
		if g.Comp[i] == comp then
			local d = (g.P[i] - target).Magnitude
			if d < bestD then
				bestD = d
				best = i
			end
		end
	end
	return best
end

-- Pfad zwischen zwei Welt-Positionen (Knotenindizes). nil, wenn kein Graph / kein Startknoten.
function Pathfind.Path(g: Graph, fromPos: Vector3, toPos: Vector3): { number }?
	if g.Count == 0 then
		return nil
	end
	local s = Pathfind.Nearest(g, fromPos, g.Spacing * 4)
	if s == nil then
		s = Pathfind.Nearest(g, fromPos)
	end
	local t = Pathfind.Nearest(g, toPos)
	if s == nil or t == nil then
		return nil
	end
	if g.Comp[s] ~= g.Comp[t] then
		t = nearestInComponent(g, toPos, g.Comp[s])
		if t == nil then
			return nil
		end
	end
	return Pathfind.Find(g, s, t)
end

-- Liegt pos über begehbarem Boden? footY = Höhe der Füße. Ohne Graph immer true.
function Pathfind.IsWalkable(g: Graph, pos: Vector3, footY: number): boolean
	if g.Count == 0 then
		return true
	end
	local idx = Pathfind.Nearest(g, pos, g.Spacing * 2)
	if idx == nil then
		return false
	end
	local p = g.P[idx]
	local dx, dz = p.X - pos.X, p.Z - pos.Z
	if dx * dx + dz * dz > (g.Spacing * 0.85) ^ 2 then
		return false
	end
	return math.abs(p.Y - footY) <= 4.5
end

-- Alle Knoten im Radius (optional nur Deckungs-Knoten). Höchstens Count Prüfungen.
function Pathfind.NodesNear(g: Graph, pos: Vector3, radius: number, coverOnly: boolean?): { number }
	local result: { number } = {}
	local list: { number }? = if coverOnly and #g.CoverList > 0 then g.CoverList else nil
	local r2 = radius * radius
	if list then
		for _, i in ipairs(list) do
			local p = g.P[i]
			local dx, dz = p.X - pos.X, p.Z - pos.Z
			if dx * dx + dz * dz <= r2 then
				table.insert(result, i)
			end
		end
	else
		for i = 1, g.Count do
			if g.Comp[i] ~= 0 then
				local p = g.P[i]
				local dx, dz = p.X - pos.X, p.Z - pos.Z
				if dx * dx + dz * dz <= r2 then
					table.insert(result, i)
				end
			end
		end
	end
	return result
end

return Pathfind
