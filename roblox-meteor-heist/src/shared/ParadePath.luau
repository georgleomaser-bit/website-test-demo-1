-- =====================================================================
--  PARADE-PFAD (Server UND Client rechnen hiermit – deshalb exakt gleich)
--   Die Alien-Parade läuft über eine Polyline aus Wegpunkten (Config.Parade.Path).
--   Die Aliens laufen genau auf den geraden Stücken; an den Ecken wird nur die Blickrichtung
--   (und damit der seitliche Versatz der Spuren) weich überblendet -> kein Ruckeln, keine Sprünge.
--   Die Straße (MapBuilder) besteht aus denselben geraden Stücken + runden Scheiben an den Ecken.
--
--   Position aus der zurückgelegten Strecke:  ParadePath.Sample(path, dist, hint)
--   Länge:                                    path.Length
--   Nächster Punkt (Egg Rush, Fallenlassen):  ParadePath.Nearest(path, pos)
--
--  PARADE-UHR: Alle Träger teilen sich EINE Uhr P(t) = P + (t - T) * Rate (Rate 1 normal, im
--  Meteoritenschauer schneller). Ein Ei kennt P0 (Uhr beim Start) und Speed (Studs pro Uhr-Sekunde):
--     Strecke = (P(jetzt) - P0) * Speed
--  So werden im Schauer ALLE gleichzeitig schneller (niemand läuft durch den Vordermann).
--  Die Uhr steht als EIN Text-Attribut "ParadeClock" am Ordner "Parade" (kommt immer komplett an).
--
--  AUSWEICHEN: Bosse laufen langsamer. Wer einen Boss überholt, weicht seitlich nach außen aus
--  (ParadePath.Lateral) – Server (Reichweiten-Prüfung) und Client (Optik) rechnen gleich.
-- =====================================================================

local ParadePath = {}

export type Path = {
	Points: { Vector3 }, -- Wegpunkte (Y = Straßen-Oberkante)
	Cum: { number }, -- zurückgelegte Strecke bis Wegpunkt i
	Dirs: { Vector3 }, -- Richtung des Stücks i -> i+1 (waagrecht, Einheitsvektor)
	Tangents: { Vector3 }, -- weiche Richtung an Wegpunkt i (Mittel der Nachbarstücke)
	Length: number,
	RoadTop: number,
}

local DEFAULT_ROAD_TOP = 0.3
local MAX_POINTS = 64 -- Sicherheitsgrenze beim Lesen aus Attributen

-- -------------------------------------------------------------------
-- BAUEN
-- -------------------------------------------------------------------
-- points: Wegpunkte (X/Z zählen, Y wird auf roadTop gesetzt). Doppelte Punkte werden übersprungen.
function ParadePath.Build(points: { Vector3 }, roadTop: number?): Path?
	local top = tonumber(roadTop) or DEFAULT_ROAD_TOP
	local clean: { Vector3 } = {}
	for _, p in ipairs(points) do
		if typeof(p) == "Vector3" then
			local flat = Vector3.new(p.X, top, p.Z)
			local last = clean[#clean]
			if not last or (flat - last).Magnitude > 0.05 then
				table.insert(clean, flat)
			end
		end
	end
	if #clean < 2 then
		return nil
	end
	local cum: { number } = { 0 }
	local dirs: { Vector3 } = {}
	for i = 1, #clean - 1 do
		local delta = clean[i + 1] - clean[i]
		cum[i + 1] = cum[i] + delta.Magnitude
		dirs[i] = delta.Unit
	end
	local tangents: { Vector3 } = {}
	for i = 1, #clean do
		local a = dirs[i - 1] or dirs[i]
		local b = dirs[i] or dirs[i - 1]
		local sum = a + b
		tangents[i] = if sum.Magnitude > 1e-3 then sum.Unit else b
	end
	return {
		Points = clean,
		Cum = cum,
		Dirs = dirs,
		Tangents = tangents,
		Length = cum[#cum],
		RoadTop = top,
	}
end

-- Wegpunkte aus Config.Parade.Path (Config wird übergeben -> kein Kreis-require)
function ParadePath.FromConfig(config: any): Path?
	local parade = config and config.Parade
	if type(parade) ~= "table" or type(parade.Path) ~= "table" then
		return nil
	end
	return ParadePath.Build(parade.Path, parade.RoadTop)
end

-- Wegpunkte als Attribute an den Map-Ordner "Parade" schreiben (P1..Pn, PointCount, RoadTop, Length)
function ParadePath.Export(folder: Instance, path: Path)
	folder:SetAttribute("PointCount", #path.Points)
	folder:SetAttribute("RoadTop", path.RoadTop)
	folder:SetAttribute("Length", path.Length)
	for i, p in ipairs(path.Points) do
		folder:SetAttribute("P" .. i, p)
	end
end

-- Wegpunkte aus dem Map-Ordner lesen (nil = noch nicht da / kaputt)
function ParadePath.FromFolder(folder: Instance): Path?
	local count = tonumber(folder:GetAttribute("PointCount"))
	if not count or count < 2 or count > MAX_POINTS then
		return nil
	end
	local points: { Vector3 } = {}
	for i = 1, count do
		local p = folder:GetAttribute("P" .. i)
		if typeof(p) ~= "Vector3" then
			return nil
		end
		table.insert(points, p)
	end
	return ParadePath.Build(points, tonumber(folder:GetAttribute("RoadTop")))
end

-- -------------------------------------------------------------------
-- ABFRAGEN
-- -------------------------------------------------------------------
-- Index des Stücks, auf dem "dist" liegt. hint = letzter Index (die Träger laufen nur vorwärts ->
-- meist 0-1 Schritte statt Suche).
local function segmentIndex(path: Path, dist: number, hint: number?): number
	local cum = path.Cum
	local last = #cum - 1
	local i = math.clamp(hint or 1, 1, last)
	while i < last and dist > cum[i + 1] do
		i += 1
	end
	while i > 1 and dist < cum[i] do
		i -= 1
	end
	return i
end

-- Punkt + weiche Blickrichtung bei Strecke dist (wird auf 0..Length begrenzt).
-- Gibt (Position auf der Straße, Richtung waagrecht, Index für den nächsten Aufruf) zurück.
function ParadePath.Sample(path: Path, dist: number, hint: number?): (Vector3, Vector3, number)
	local d = math.clamp(dist, 0, path.Length)
	local i = segmentIndex(path, d, hint)
	local cum = path.Cum
	local segLength = cum[i + 1] - cum[i]
	local u = if segLength > 1e-4 then (d - cum[i]) / segLength else 0
	local pos = path.Points[i] + path.Dirs[i] * (d - cum[i])
	-- Blickrichtung: an den Ecken weich überblenden (erste/letzte 35 % eines Stücks)
	local dir = path.Dirs[i]
	local blend = 0.35
	if u < blend then
		local k = 0.5 + 0.5 * (u / blend)
		dir = path.Tangents[i]:Lerp(dir, (k - 0.5) * 2)
	elseif u > 1 - blend then
		local k = (u - (1 - blend)) / blend
		dir = dir:Lerp(path.Tangents[i + 1], k)
	end
	if dir.Magnitude > 1e-4 then
		dir = dir.Unit
	else
		dir = path.Dirs[i]
	end
	return pos, dir, i
end

-- Rechts-Vektor zu einer Blickrichtung (waagrecht)
function ParadePath.Right(dir: Vector3): Vector3
	return Vector3.new(-dir.Z, 0, dir.X)
end

-- Nächster Punkt auf dem Pfad (nur waagrecht gerechnet).
-- Gibt (Punkt, Strecke entlang des Pfads, waagrechter Abstand, Richtung vom Pfad weg) zurück.
function ParadePath.Nearest(path: Path, pos: Vector3): (Vector3, number, number, Vector3)
	local best, bestAlong, bestDist = path.Points[1], 0, math.huge
	local flat = Vector3.new(pos.X, path.RoadTop, pos.Z)
	for i = 1, #path.Points - 1 do
		local a = path.Points[i]
		local dir = path.Dirs[i]
		local segLength = path.Cum[i + 1] - path.Cum[i]
		local t = math.clamp((flat - a):Dot(dir), 0, segLength)
		local point = a + dir * t
		local d = (flat - point).Magnitude
		if d < bestDist then
			best, bestAlong, bestDist = point, path.Cum[i] + t, d
		end
	end
	local away = flat - best
	local outward = if away.Magnitude > 1e-3 then away.Unit else ParadePath.Right(path.Dirs[1])
	return best, bestAlong, bestDist, outward
end

-- Größter Abstand eines Pfad-Punkts von "from" (für die Server-Reichweite der Prompts)
function ParadePath.MaxDistanceFrom(path: Path, from: Vector3): number
	local best = 0
	for _, p in ipairs(path.Points) do
		best = math.max(best, (p - from).Magnitude)
	end
	return best
end

-- -------------------------------------------------------------------
-- PARADE-UHR
-- -------------------------------------------------------------------
function ParadePath.FormatClock(t: number, p: number, rate: number): string
	return string.format("%.6f|%.6f|%.6f", t, p, rate)
end

-- "T|P|Rate" -> (T, P, Rate) oder nil
function ParadePath.ParseClock(text: any): (number?, number?, number?)
	if type(text) ~= "string" then
		return nil, nil, nil
	end
	local a, b, c = string.match(text, "^([^|]+)|([^|]+)|([^|]+)$")
	local t, p, rate = tonumber(a), tonumber(b), tonumber(c)
	if not t or not p or not rate then
		return nil, nil, nil
	end
	return t, p, rate
end

-- -------------------------------------------------------------------
-- AUSWEICHEN (Überholen eines langsameren Bosses)
-- -------------------------------------------------------------------
-- lane = normale Spur (seitlicher Versatz), dist = eigene Strecke, bossDist = Strecke des Bosses.
-- zone = so nah (entlang) wird voll ausgewichen, fade = danach weich zurück, offset = Ausweich-Versatz.
-- Gibt den Anteil 0..1 zurück (1 = ganz außen).
function ParadePath.DodgeAmount(dist: number, bossDist: number, zone: number, fade: number): number
	local gap = math.abs(dist - bossDist)
	if gap >= zone + fade then
		return 0
	elseif gap <= zone then
		return 1
	end
	local k = 1 - (gap - zone) / fade
	return k * k * (3 - 2 * k) -- weich (Smoothstep)
end

-- Seitlicher Versatz mit Ausweichen: amount = größter DodgeAmount aller Bosse
function ParadePath.Lateral(lane: number, amount: number, offset: number): number
	if amount <= 0 then
		return lane
	end
	local side = if lane < 0 then -1 else 1
	return lane + (side * offset - lane) * amount
end

return ParadePath
