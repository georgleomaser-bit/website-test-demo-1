-- =====================================================================
--  CLUTCH CLASH – Bau-Helfer für Maps und Lobby (Server/World/MapKit)
--  Besitzer: WP2 (Welt). Vertrag: DESIGN.md B8.1 (Datenformat, Spiegel-Logik, Teilebudget),
--  A4 (Art Direction: Pastell-Plastik, „Fake-Fase“, Neon sparsam), Muster aus dem
--  Meteor-Heist-MapBuilder (REUSE §1.3): part/folder/Schild-Helfer, „unparented bauen,
--  dann EINMAL parenten“.
--
--  Öffentliche API (nur für WP2-Module: ArenaService, LobbyBuilder, Map-Dateien, WorldTests):
--    MapKit.Color(name | Color3, flipped?): Color3      Palette-Namen (Config.Colors.Palette + Extras),
--                                                       "TeamA"/"TeamB" tauschen beim Spiegeln
--    MapKit.Material(name?): Enum.Material              nie Ice (Muss-Regel 11)
--    MapKit.Mirror(v): Vector3                          (x, y, z) -> (−x, y, −z)
--    MapKit.Expand(layout): { Spec }                    alle Teile inkl. Spiegel-Kopien (rein, nur Positionen)
--    MapKit.SpawnCFrames(layout): (A, B, FFA)           lokale CFrames (A Blick +Z, B Blick −Z, FFA zur Mitte)
--    MapKit.CoverPoints(layout): { Vector3 }            CoverNodes A + gespiegelt (ohne Doppelte)
--    MapKit.Checker(min, max, tile, color): { MapPart } Deko-Bodenfliesen (punktsymmetrisch, Center)
--    MapKit.Scenery(opts): { MapPart }                  Kulisse: Wand-Lisenen, Spielzeug-Stapel, Ballons
--    MapKit.Clouds(seed, count, spreadX, minZ, maxZ)    Wolken-Haufen (Insel-Maps)
--    MapKit.part(props) / wedge(props) / cyl(props, center, height, diameter) / ball(props, center, d)
--    MapKit.sign(part, face, lines, opts?): SurfaceGui  Schrift FredokaOne + dicke schwarze Kontur
--    MapKit.surfaceLetter(part, text, faces, color?)    großer Buchstabe auf Flächen (BlockYard, Lobby)
--    MapKit.barrier(parent, cf, size): Part             unsichtbar, Gruppe ArenaBarrier, CanQuery=false
--    MapKit.Count(root): (parts, neon)                  Teilezähler
--    MapKit.Build(layout): (Model, BuildInfo)           komplette Map UNPARENTED (Ursprung = Bodenmitte)
--
--  Konventionen der Map-Tabellen (Types.MapPart):
--    * Pos = Mittelpunkt, Size = (X, Y, Z). Zylinder: Size = (Ø, Höhe, Ø), Achse senkrecht.
--      Kugel: Size = (Ø, Ø, Ø).
--    * Wedge: HighEnd = z-Wert des hohen Endes (die hohe Kante einer WedgePart liegt bei lokal +Z).
--    * Center = true -> genau einmal; Mirror = false -> genau einmal; sonst + Kopie (−x, y, −z), 180° gedreht.
--    * Tag = Name des Teils. Tags mit "Deco" vorne: CanCollide/CanQuery/CastShadow aus (reine Optik).
--      Tag "Wall" bekommt automatisch eine Charcoal-Kappe, die Tags aus LIP_TAGS eine 0.2-Lippe („Fake-Fase“).
--    * Text = SurfaceGui-Buchstabe auf ±Z. Barrier = unsichtbare ArenaBarrier.
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Config = require(Shared:WaitForChild("Config"))

local MapKit = {}

export type Spec = { Def: Types.MapPart, Pos: Vector3, Flip: boolean }
export type BuildInfo = {
	Key: string,
	Parts: number,
	Neon: number,
	Budget: number,
	NeonLimit: number,
	OverBudget: boolean,
	TooMuchNeon: boolean,
}
export type SignLine = { Text: string, Color: Color3?, Height: number? }

local FLIP = CFrame.Angles(0, math.pi, 0)
local CYLINDER_UP = CFrame.Angles(0, 0, math.rad(90))
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local BARRIER_GROUP = "ArenaBarrier"

-- ---------------------------------------------------------------------
-- 1) FARBEN & MATERIAL
-- ---------------------------------------------------------------------
-- Zusätzliche Namen zu Config.Colors.Palette (Cream, Mint, Pink, Lilac, Sand, Charcoal, Navy, White, Tip)
local EXTRA_COLORS: { [string]: Color3 } = {
	PureWhite = Color3.fromRGB(255, 255, 255),
	Red = Color3.fromRGB(255, 90, 90),
	Blue = Color3.fromRGB(60, 140, 255),
	Yellow = Color3.fromRGB(255, 210, 40),
	Green = Color3.fromRGB(90, 220, 110),
	Purple = Color3.fromRGB(170, 90, 255),
	Orange = Color3.fromRGB(255, 160, 60),
	Wood = Color3.fromRGB(200, 160, 120),
	WoodDeck = Color3.fromRGB(200, 170, 130),
	Water = Color3.fromRGB(90, 190, 255),
	Grass = Color3.fromRGB(110, 200, 110),
	Lawn = Color3.fromRGB(160, 214, 140),
	Dirt = Color3.fromRGB(150, 110, 80),
	Hedge = Color3.fromRGB(70, 150, 80),
	Terracotta = Color3.fromRGB(200, 110, 80),
	NeonCyan = Color3.fromRGB(0, 230, 255),
	NeonPink = Color3.fromRGB(255, 60, 170),
	Gold = Color3.fromRGB(255, 200, 60),
	Snow = Color3.fromRGB(240, 245, 255),
	SnowWall = Color3.fromRGB(225, 235, 250),
	FortWall = Color3.fromRGB(230, 240, 255),
	Pond = Color3.fromRGB(180, 220, 255),
	Bark = Color3.fromRGB(120, 80, 50),
	Pine = Color3.fromRGB(60, 140, 90),
	CreamDark = Color3.fromRGB(234, 222, 202),
	NavyLight = Color3.fromRGB(40, 46, 88),
	Steel = Color3.fromRGB(120, 125, 140),
}

local warnedColors: { [string]: boolean } = {}
local warnedMaterials: { [string]: boolean } = {}

-- Farbname -> Color3. "TeamA"/"TeamB" werden bei gespiegelten Teilen getauscht (A-Hälfte orange, B blau).
function MapKit.Color(value: string | Color3, flipped: boolean?): Color3
	if typeof(value) == "Color3" then
		return value
	end
	local name = value :: string
	if name == "TeamA" or name == "TeamB" then
		local teamA = name == "TeamA"
		if flipped then
			teamA = not teamA
		end
		local colors = Config.Colors
		return if teamA then colors.TeamA else colors.TeamB
	end
	local palette = Config.Colors and Config.Colors.Palette
	local color = (palette and palette[name]) or EXTRA_COLORS[name]
	if typeof(color) == "Color3" then
		return color
	end
	if not warnedColors[name] then
		warnedColors[name] = true
		warn("[MapKit] Unbekannte Farbe '" .. tostring(name) .. "' – nehme Cream")
	end
	return Color3.fromRGB(244, 235, 221)
end

-- Material-Name -> Enum.Material (Standard SmoothPlastic). Ice ist verboten (rutschig, Muss-Regel 11).
function MapKit.Material(name: string?): Enum.Material
	if name == nil or name == "" then
		return Enum.Material.SmoothPlastic
	end
	if name == "Ice" then
		if not warnedMaterials.Ice then
			warnedMaterials.Ice = true
			warn("[MapKit] Material Ice ist verboten – nehme SmoothPlastic")
		end
		return Enum.Material.SmoothPlastic
	end
	local ok, value = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	if ok and typeof(value) == "EnumItem" then
		return value :: any
	end
	if not warnedMaterials[name] then
		warnedMaterials[name] = true
		warn("[MapKit] Unbekanntes Material '" .. name .. "' – nehme SmoothPlastic")
	end
	return Enum.Material.SmoothPlastic
end

-- ---------------------------------------------------------------------
-- 2) SPIEGELN & DATEN (rein, ohne Instanzen)
-- ---------------------------------------------------------------------
function MapKit.Mirror(v: Vector3): Vector3
	return Vector3.new(-v.X, v.Y, -v.Z)
end

-- Jedes Teil + Spiegel-Kopie (B8.1). Reihenfolge stabil (Original, dann Kopie).
function MapKit.Expand(layout: Types.MapLayout): { Spec }
	local out: { Spec } = {}
	for _, def in ipairs(layout.Parts) do
		table.insert(out, { Def = def, Pos = def.Pos, Flip = false })
		if not def.Center and def.Mirror ~= false then
			table.insert(out, { Def = def, Pos = MapKit.Mirror(def.Pos), Flip = true })
		end
	end
	return out
end

local function faceTowardCenter(p: Vector3): CFrame
	local flat = Vector3.new(-p.X, 0, -p.Z)
	if flat.Magnitude < 0.1 then
		return CFrame.lookAt(p, p + Vector3.zAxis)
	end
	return CFrame.lookAt(p, p + flat.Unit)
end

-- Lokale Spawn-CFrames: A blickt nach +Z, B (gespiegelt) nach −Z, FFA zur Map-Mitte.
function MapKit.SpawnCFrames(layout: Types.MapLayout): ({ CFrame }, { CFrame }, { CFrame })
	local a: { CFrame } = {}
	local b: { CFrame } = {}
	local ffa: { CFrame } = {}
	for _, p in ipairs(layout.SpawnsA) do
		table.insert(a, CFrame.lookAt(p, p + Vector3.zAxis))
		local m = MapKit.Mirror(p)
		table.insert(b, CFrame.lookAt(m, m - Vector3.zAxis))
	end
	for _, p in ipairs(layout.FFA or {}) do
		table.insert(ffa, faceTowardCenter(p))
	end
	return a, b, ffa
end

-- CoverNodes der A-Hälfte + Spiegelung; Punkte näher als 0.5 Studs zählen als derselbe.
function MapKit.CoverPoints(layout: Types.MapLayout): { Vector3 }
	local out: { Vector3 } = {}
	local function add(p: Vector3)
		for _, q in ipairs(out) do
			if (q - p).Magnitude < 0.5 then
				return
			end
		end
		table.insert(out, p)
	end
	for _, p in ipairs(layout.CoverNodes) do
		add(p)
		add(MapKit.Mirror(p))
	end
	return out
end

-- Schachbrett-Fliesen (nur die „dunklen“ Felder) als Deko auf einem Boden (Oberkante y).
-- Punktsymmetrisch, wenn (Anzahl X + Anzahl Z) gerade ist – die Maps wählen tile passend.
function MapKit.Checker(minXZ: Vector2, maxXZ: Vector2, tile: number, y: number, color: string): { Types.MapPart }
	local out: { Types.MapPart } = {}
	local nx = math.floor((maxXZ.X - minXZ.X) / tile + 0.5)
	local nz = math.floor((maxXZ.Y - minXZ.Y) / tile + 0.5)
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			if (i + j) % 2 == 0 then
				local x = minXZ.X + (i + 0.5) * tile
				local z = minXZ.Y + (j + 0.5) * tile
				table.insert(out, {
					Shape = "Block",
					Tag = "DecoTile",
					Pos = Vector3.new(x, y + 0.025, z),
					Size = Vector3.new(tile, 0.05, tile),
					Color = color,
					Center = true,
				})
			end
		end
	end
	return out
end

-- Kulisse für ummauerte Arenen (A4-Optik, nur Deko): Lisenen an den Wand-Innenseiten und
-- Spielzeug-Stapel außerhalb der Wände, die über die Mauerkrone ragen, dazu Ballons.
-- Erzeugt die A-Hälfte (Nordwand + ganze Westseite); MapKit spiegelt den Rest. Deterministisch (Seed).
export type SceneryOpts = {
	Size: Vector3,
	WallHeight: number,
	Seed: number,
	Colors: { string | Color3 },
	Pilaster: (string | Color3)?,
	Balloons: number?,
}

local function lcg(seed: number): () -> number
	local state = math.floor(math.abs(seed)) % 2147483647 + 1
	return function(): number
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
end

function MapKit.Scenery(o: SceneryOpts): { Types.MapPart }
	local out: { Types.MapPart } = {}
	local hx, hz, h = o.Size.X / 2, o.Size.Z / 2, o.WallHeight
	local rand = lcg(o.Seed)
	local colorCount = #o.Colors
	local colorIndex = 0
	local function nextColor(): string | Color3
		colorIndex += 1
		return o.Colors[(colorIndex - 1) % colorCount + 1]
	end
	-- 1) Lisenen (Innenseite der Nordwand, ganze Westwand)
	if o.Pilaster then
		local nx = math.max(2, math.floor(2 * hx / 12))
		for i = 1, nx - 1 do
			table.insert(out, {
				Shape = "Block",
				Tag = "DecoPilaster",
				Pos = Vector3.new(-hx + i * (2 * hx / nx), h / 2, -hz + 0.15),
				Size = Vector3.new(1.2, h - 1, 0.3),
				Color = o.Pilaster,
			})
		end
		local nz = math.max(2, math.floor(2 * hz / 12))
		for i = 1, nz - 1 do
			table.insert(out, {
				Shape = "Block",
				Tag = "DecoPilaster",
				Pos = Vector3.new(-hx + 0.15, h / 2, -hz + i * (2 * hz / nz)),
				Size = Vector3.new(0.3, h - 1, 1.2),
				Color = o.Pilaster,
			})
		end
	end
	-- 2) Spielzeug-Stapel außen (Säule aus der Tiefe + kleinerer Klotz + Kugel)
	local function stack(x: number, z: number)
		local base = 6 + rand() * 5
		local top = h + 2 + rand() * 8
		local bottom = -18
		table.insert(out, {
			Shape = "Block",
			Tag = "DecoStack",
			Pos = Vector3.new(x, (top + bottom) / 2, z),
			Size = Vector3.new(base, top - bottom, base),
			Color = nextColor(),
		})
		local cap = base * (0.55 + rand() * 0.2)
		local capH = 3 + rand() * 3
		table.insert(out, {
			Shape = "Block",
			Tag = "DecoStack",
			Pos = Vector3.new(x, top + capH / 2, z),
			Size = Vector3.new(cap, capH, cap),
			Rot = Vector3.new(0, rand() * 40 - 20, 0),
			Color = nextColor(),
		})
		local ball = cap * 0.7
		table.insert(out, {
			Shape = "Ball",
			Tag = "DecoStack",
			Pos = Vector3.new(x, top + capH + ball / 2, z),
			Size = Vector3.new(ball, ball, ball),
			Color = nextColor(),
		})
	end
	local countN = math.max(2, math.floor(2 * hx / 18))
	for i = 1, countN do
		local x = -hx + (i - 0.5) * (2 * hx / countN) + (rand() - 0.5) * 4
		stack(x, -hz - 8 - rand() * 12)
	end
	local countW = math.max(2, math.floor(2 * hz / 18))
	for i = 1, countW do
		local z = -hz + (i - 0.5) * (2 * hz / countW) + (rand() - 0.5) * 4
		stack(-hx - 8 - rand() * 12, z)
	end
	-- 3) Ballons über der Kulisse
	for _ = 1, o.Balloons or 3 do
		local x = (rand() * 2 - 1) * (hx + 10)
		local z = -hz - 12 - rand() * 14
		local y = h + 14 + rand() * 10
		table.insert(out, {
			Shape = "Ball",
			Tag = "DecoBalloon",
			Pos = Vector3.new(x, y, z),
			Size = Vector3.new(4, 4, 4),
			Color = nextColor(),
		})
		table.insert(out, {
			Shape = "Block",
			Tag = "DecoString",
			Pos = Vector3.new(x, y - 4.5, z),
			Size = Vector3.new(0.12, 5, 0.12),
			Color = "PureWhite",
		})
	end
	return out
end

-- Wolken-Haufen (je 3 weiße Kugeln) rund um eine Insel-Map (A-Hälfte, z < 0; Rest gespiegelt)
function MapKit.Clouds(seed: number, count: number, spreadX: number, minZ: number, maxZ: number): { Types.MapPart }
	local out: { Types.MapPart } = {}
	local rand = lcg(seed)
	for _ = 1, count do
		local center = Vector3.new((rand() * 2 - 1) * spreadX, -14 - rand() * 16, minZ + rand() * (maxZ - minZ))
		for k = 1, 3 do
			local d = 6 + rand() * 6
			table.insert(out, {
				Shape = "Ball",
				Tag = "DecoCloud",
				Pos = center + Vector3.new((k - 2) * d * 0.6, rand() * 2, (rand() - 0.5) * 4),
				Size = Vector3.new(d, d, d),
				Color = "PureWhite",
				Transparency = 0.1,
			})
		end
	end
	return out
end

-- ---------------------------------------------------------------------
-- 3) INSTANZ-HELFER (MH-Muster)
-- ---------------------------------------------------------------------
local function apply(target: Instance, props: { [string]: any })
	for key, value in pairs(props) do
		if key ~= "Parent" then
			(target :: any)[key] = value
		end
	end
end

local function finish(p: BasePart, props: { [string]: any })
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false -- nichts in der Welt braucht Touched (spart Physik-Arbeit)
	p.Material = Enum.Material.SmoothPlastic
	apply(p, props)
end

-- Klotz (Anchored, glatt, CanTouch=false). Parent wird zuletzt gesetzt.
function MapKit.part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	finish(p, props)
	p.Parent = props.Parent
	return p
end

function MapKit.wedge(props: { [string]: any }): WedgePart
	local p = Instance.new("WedgePart")
	finish(p, props)
	p.Parent = props.Parent
	return p
end

-- Senkrechter Zylinder (Roblox-Zylinder liegen entlang X -> 90° um Z drehen)
function MapKit.cyl(props: { [string]: any }, center: Vector3, height: number, diameter: number): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	finish(p, props)
	p.Size = Vector3.new(height, diameter, diameter)
	p.CFrame = CFrame.new(center) * CYLINDER_UP
	p.Parent = props.Parent
	return p
end

function MapKit.ball(props: { [string]: any }, center: Vector3, diameter: number): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	finish(p, props)
	p.Size = Vector3.new(diameter, diameter, diameter)
	p.CFrame = CFrame.new(center)
	p.Parent = props.Parent
	return p
end

-- Schild auf einer Fläche: Zeilen untereinander, FredokaOne, dicke schwarze Kontur, kein Kasten.
function MapKit.sign(
	part: BasePart,
	face: Enum.NormalId,
	lines: { SignLine },
	opts: { Name: string?, Background: Color3?, MaxDistance: number?, Font: Enum.Font? }?
): SurfaceGui
	local o = opts or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = o.Name or "Sign"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.MaxDistance = o.MaxDistance or 400
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local frame = Instance.new("Frame")
	frame.Name = "Frame"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BorderSizePixel = 0
	if o.Background then
		frame.BackgroundColor3 = o.Background
		frame.BackgroundTransparency = 0
	else
		frame.BackgroundTransparency = 1
	end
	frame.Parent = gui

	local total = 0
	for _, line in ipairs(lines) do
		total += line.Height or (1 / math.max(1, #lines))
	end
	local y = math.max(0, (1 - total) / 2)
	for index, line in ipairs(lines) do
		local height = line.Height or (1 / math.max(1, #lines))
		local label = Instance.new("TextLabel")
		label.Name = "Line" .. index
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0.03, y)
		label.Size = UDim2.fromScale(0.94, height)
		label.Font = o.Font or Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = line.Color or WHITE
		label.Text = line.Text
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = if index == 1 then 5 else 4
		stroke.Color = BLACK
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Parent = label
		label.Parent = frame
		y += height
	end
	gui.Parent = part
	return gui
end

-- Großer Buchstabe auf mehreren Flächen eines Teils (Spielzeug-Bauklotz)
function MapKit.surfaceLetter(part: BasePart, text: string, faces: { Enum.NormalId }, color: Color3?)
	for _, face in ipairs(faces) do
		MapKit.sign(part, face, { { Text = text, Color = color or WHITE, Height = 0.86 } }, {
			Name = "Letter" .. face.Name,
			MaxDistance = 300,
			Font = Enum.Font.LuckiestGuy,
		})
	end
end

-- Unsichtbare Barriere: blockiert Spieler/Bots (Kollisionsgruppe), aber KEINE Kugeln/Raycasts.
function MapKit.barrier(parent: Instance, cf: CFrame, size: Vector3): Part
	local p = MapKit.part({
		Name = "Barrier",
		CFrame = cf,
		Size = size,
		Transparency = 1,
		CanCollide = true,
		CanQuery = false,
		CastShadow = false,
	})
	p.CollisionGroup = BARRIER_GROUP
	p.Parent = parent
	return p
end

-- Teile zählen (inkl. root, falls root selbst ein BasePart ist)
function MapKit.Count(root: Instance): (number, number)
	local parts, neon = 0, 0
	local function visit(inst: Instance)
		if inst:IsA("BasePart") then
			parts += 1
			if inst.Material == Enum.Material.Neon then
				neon += 1
			end
		end
	end
	visit(root)
	for _, inst in ipairs(root:GetDescendants()) do
		visit(inst)
	end
	return parts, neon
end

-- ---------------------------------------------------------------------
-- 4) MAP BAUEN
-- ---------------------------------------------------------------------
-- Tags mit automatischer „Fake-Fase“ (0.2-Lippe oben, etwas heller) – A4
local LIP_TAGS: { [string]: boolean } = {
	Crate = true,
	Pillar = true,
	Platform = true,
	Tower = true,
	Letter = true,
	Cover = true,
	HalfWall = true,
	Container = true,
	Cube = true,
	Alley = true,
}

local function isDeco(def: Types.MapPart): boolean
	local tag = def.Tag
	return tag ~= nil and string.sub(tag, 1, 4) == "Deco"
end

local function baseCFrame(def: Types.MapPart): CFrame
	local rot = def.Rot or Vector3.zero
	local yaw = rot.Y
	-- WedgePart: hohe Kante bei lokal +Z. Liegt das hohe Ende bei kleinerem z -> 180° drehen.
	if def.Shape == "Wedge" and def.HighEnd ~= nil and def.HighEnd < def.Pos.Z then
		yaw += 180
	end
	return CFrame.new(def.Pos) * CFrame.Angles(math.rad(rot.X), math.rad(yaw), math.rad(rot.Z))
end

local function makePart(def: Types.MapPart, flip: boolean): BasePart
	local cf = baseCFrame(def)
	if flip then
		cf = FLIP * cf
	end
	local size = def.Size
	local inst: BasePart
	if def.Shape == "Wedge" then
		inst = Instance.new("WedgePart")
	elseif def.Shape == "CornerWedge" then
		inst = Instance.new("CornerWedgePart")
	else
		local p = Instance.new("Part")
		if def.Shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
			local d = math.max(size.X, size.Z)
			size = Vector3.new(size.Y, d, d)
			cf = cf * CYLINDER_UP
		elseif def.Shape == "Ball" then
			p.Shape = Enum.PartType.Ball
			local d = math.max(size.X, size.Y, size.Z)
			size = Vector3.new(d, d, d)
		end
		inst = p
	end
	inst.Name = def.Tag or def.Shape
	inst.Anchored = true
	inst.TopSurface = Enum.SurfaceType.Smooth
	inst.BottomSurface = Enum.SurfaceType.Smooth
	inst.CanTouch = false
	inst.Size = size
	inst.CFrame = cf
	inst.Color = MapKit.Color(def.Color, flip)
	inst.Material = MapKit.Material(def.Material)
	if inst.Material == Enum.Material.Glass then
		inst.Transparency = math.clamp(def.Transparency or 0.45, 0.3, 0.6) -- Glas blockiert Kugeln (A4)
	elseif def.Transparency ~= nil then
		inst.Transparency = math.clamp(def.Transparency, 0, 1)
	end
	inst.CanCollide = def.CanCollide ~= false
	if def.Barrier then
		inst.Transparency = 1
		inst.CanCollide = true
		inst.CanQuery = false
		inst.CastShadow = false
		inst.CollisionGroup = BARRIER_GROUP
		inst.Name = "Barrier"
	elseif isDeco(def) then
		inst.CanCollide = false
		inst.CanQuery = false
		inst.CastShadow = false
	end
	if inst.Material == Enum.Material.Neon then
		inst.CastShadow = false
	end
	if def.Text and def.Text ~= "" then
		MapKit.surfaceLetter(inst, def.Text, { Enum.NormalId.Front, Enum.NormalId.Back })
	end
	return inst
end

-- Automatische Details (A4): Kappe auf Wänden, Lippe auf klobigen Blöcken
local function addDetails(def: Types.MapPart, inst: BasePart, model: Model)
	if def.Shape ~= "Block" or def.Barrier or isDeco(def) then
		return
	end
	local size = inst.Size
	local top = inst.CFrame * CFrame.new(0, size.Y / 2, 0)
	if def.Tag == "Wall" then
		MapKit.part({
			Name = "WallCap",
			Size = Vector3.new(size.X + 0.4, 0.6, size.Z + 0.4),
			CFrame = top * CFrame.new(0, 0.3, 0),
			Color = MapKit.Color("Charcoal"),
			CastShadow = false,
			Parent = model,
		})
		return
	end
	local tag = def.Tag
	if tag == nil or not LIP_TAGS[tag] then
		return
	end
	if (def.Transparency or 0) > 0 or def.CanCollide == false then
		return
	end
	if size.X < 1.4 or size.Z < 1.4 or size.Y < 1.5 then
		return
	end
	MapKit.part({
		Name = "Lip",
		Size = Vector3.new(size.X - 0.4, 0.2, size.Z - 0.4),
		CFrame = top * CFrame.new(0, 0.1, 0),
		Color = inst.Color:Lerp(WHITE, 0.22),
		Material = inst.Material,
		CastShadow = false,
		Parent = model,
	})
end

-- Automatische Barrieren (B8.1): 4 Seiten + Decke aus Size (Decke Config.Maps.BarrierCeiling),
-- bei CustomBounds genau dort (Min/Max lokal).
local function addBarriers(layout: Types.MapLayout, model: Model)
	local folder = Instance.new("Folder")
	folder.Name = "Barriers"
	local minV: Vector3
	local maxV: Vector3
	if layout.CustomBounds then
		minV = layout.CustomBounds.Min
		maxV = layout.CustomBounds.Max
	else
		local ceiling = tonumber(Config.Maps.BarrierCeiling) or 40
		minV = Vector3.new(-layout.Size.X / 2, -1, -layout.Size.Z / 2)
		maxV = Vector3.new(layout.Size.X / 2, ceiling, layout.Size.Z / 2)
	end
	local sizeX = maxV.X - minV.X
	local sizeZ = maxV.Z - minV.Z
	local height = maxV.Y - minV.Y
	local midY = (maxV.Y + minV.Y) / 2
	local midX = (maxV.X + minV.X) / 2
	local midZ = (maxV.Z + minV.Z) / 2
	MapKit.barrier(folder, CFrame.new(minV.X - 1, midY, midZ), Vector3.new(2, height, sizeZ + 4))
	MapKit.barrier(folder, CFrame.new(maxV.X + 1, midY, midZ), Vector3.new(2, height, sizeZ + 4))
	MapKit.barrier(folder, CFrame.new(midX, midY, minV.Z - 1), Vector3.new(sizeX + 4, height, 2))
	MapKit.barrier(folder, CFrame.new(midX, midY, maxV.Z + 1), Vector3.new(sizeX + 4, height, 2))
	MapKit.barrier(folder, CFrame.new(midX, maxV.Y + 1, midZ), Vector3.new(sizeX + 4, 2, sizeZ + 4))
	folder.Parent = model
end

-- Ganze Map unparented bauen (Ursprung = Bodenmitte, Boden-Oberkante y = 0). Teilezähler + Budget-warn.
function MapKit.Build(layout: Types.MapLayout): (Model, BuildInfo)
	local model = Instance.new("Model")
	model.Name = "Map"
	model:SetAttribute("MapKey", layout.Key)

	for _, spec in ipairs(MapKit.Expand(layout)) do
		local inst = makePart(spec.Def, spec.Flip)
		inst.Parent = model
		addDetails(spec.Def, inst, model)
	end
	addBarriers(layout, model)
	model.WorldPivot = CFrame.new()

	local mapDef = Config.Maps.Maps and Config.Maps.Maps[layout.Key]
	local budget = if mapDef and tonumber(mapDef.PartBudget) then mapDef.PartBudget else 700
	local parts, neon = MapKit.Count(model)
	-- Neon-Richtwert ~8 % (A4) – gemessen am Teilebudget der Map-Klasse
	local neonLimit = math.floor(budget * (tonumber(Config.Maps.NeonShare) or 0.08))
	local info: BuildInfo = {
		Key = layout.Key,
		Parts = parts,
		Neon = neon,
		Budget = budget,
		NeonLimit = neonLimit,
		OverBudget = parts > budget,
		TooMuchNeon = neon > neonLimit,
	}
	if info.OverBudget then
		warn(("[MapKit] %s: %d Teile – Budget %d überschritten"):format(layout.Key, parts, budget))
	end
	if info.TooMuchNeon then
		warn(("[MapKit] %s: %d Neon-Teile – Richtwert %d"):format(layout.Key, neon, neonLimit))
	end
	model:SetAttribute("PartCount", parts)
	return model, info
end

return MapKit
