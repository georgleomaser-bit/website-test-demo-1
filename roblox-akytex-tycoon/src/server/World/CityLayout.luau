-- =====================================================================
--  AKYTEX TYCOON – Stadtplan als Bauplan (Server/World/CityLayout)
--  Besitzer: WP7 (Stadt, Grafik, Fahrzeuge). Vertrag: DESIGN.md §A4 (Materialien, Neon nur als Streifen), §A5 (alle Zonen
--  mit Maßen), §B3 (Streaming-Modi, Teilebudget), §C5.6 (Anker, Routen, Läden, Plot-Seiten, Board-Flächen),
--  §D WP7 (Monitor-/Board-Parts mit Attribut "Monitor"/"Board", Anker mit Attributen).
--  REIN: erzeugt nur Daten (Teile-Beschreibungen = Specs) und Terrain-Aufträge (Funktionen). Gebaut wird über CityKit,
--  verteilt auf viele Frames durch CityService (≤ Config.City.BuildPerFrame Teile je Frame). Gleiche Eingabe = gleiche
--  Stadt auf jedem Server (feste Saat für die Kulisse).
--
--  Öffentliche API (nur WP7):
--    CityLayout.Plan(config): Plan          Gruppen (je ein Model mit Streaming-Modus) + Anker + Terrain + Plot-Seiten
--    CityLayout.Anchors(config): { [name]: CFrame }   nur die Anker (schnell, für CityService.Anchor vor dem Bau)
--    CityLayout.HillHeight(x, z): number    Gelände-Höhe des Villenhügels (Serpentine/Villen/Tests)
--  Spec-Felder siehe Typ "Spec". Anker sind FUSSPUNKTE (Oberfläche) mit LookVector = Blickrichtung.
--  Attribute-Konventionen in der Welt (andere Pakete lesen sie, StreamingEnabled-sicher):
--    Anchor = Name · Board = Name · Monitor = Kind/Id/Kürzel (+ Inst, Face) · Plot = k · Shop = instId (Laden-Front) ·
--    ShopTicker = instId (Platz für den Mini-Ticker) · ShopSpot = instId (Spot-Licht) · WindowLight = Etage (Kaskade) ·
--    Spin = Grad/s (Drehteller/Vitrinen/Leuchtturm, Client) · LocalDoor = "Vip"/"Club" (nur lokal offen) ·
--    Bell = true (Glocke, schwingt bei der Glocke) · Budget/NightOnly an Lichtern (Licht-Budget, WorldLook)
-- =====================================================================

local CityLayout = {}

export type LightSpec = {
	Kind: string, -- "Point" | "Spot" | "Surface"
	Range: number,
	Brightness: number,
	Color: Color3,
	Face: Enum.NormalId?,
	Angle: number?,
	NightOnly: boolean?,
	Shadows: boolean?,
}
export type GuiSpec = {
	Face: Enum.NormalId?,
	Text: string,
	Color: Color3,
	Background: Color3?,
	Display: boolean?, -- BuilderExtended (sonst BuilderSans Bold)
	MaxDistance: number?,
	Sub: string?, -- zweite Zeile (klein)
	SubColor: Color3?,
}
export type PromptSpec = {
	TextKey: string,
	ObjectKey: string?,
	Window: string?,
	Action: string?,
	Tab: string?,
	Distance: number?,
	Hold: number?,
}
export type EmitterSpec = {
	Texture: string,
	Rate: number,
	Lifetime: NumberRange,
	Speed: NumberRange,
	Size: NumberSequence,
	Color: ColorSequence,
	Transparency: NumberSequence?,
	LightEmission: number?,
	Spread: Vector2?,
	Acceleration: Vector3?,
	Face: Enum.NormalId?,
}
export type Spec = {
	Class: string, -- "Part" | "WedgePart" | "Seat" | "SpawnLocation"
	Shape: Enum.PartType?,
	Name: string,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3,
	Material: Enum.Material,
	Transparency: number?,
	Reflectance: number?,
	Collide: boolean?,
	Shadow: boolean?,
	Attrs: { [string]: any }?,
	Light: LightSpec?,
	Gui: GuiSpec?,
	Prompt: PromptSpec?,
	Emitter: EmitterSpec?,
	Mesh: { Type: Enum.MeshType, Scale: Vector3 }?,
	Sub: string?, -- Unter-Model in der Gruppe (z. B. "Bell", Drehteller)
	SubAttrs: { [string]: any }?,
	Asset: string?, -- gehört zum Rezept dieses Asset-Platzes (Config.City.Assets) -> bei gesetzter Id ersetzt
	Car: string?, -- Ausstellungsauto (VehicleModels.Build) statt Part
	Priority: boolean?, -- sofort in Init bauen (Boden unter dem Spawn, Anker, Boards)
}
export type Group = {
	Key: string,
	District: string,
	Mode: string, -- "Persistent" | "Atomic" | "Default"
	Lod: boolean,
	Specs: { Spec },
	AssetCFrames: { [string]: CFrame }, -- Asset-Platz -> Pivot des Meshes
}
export type Plan = {
	Groups: { Group },
	Anchors: { [string]: CFrame },
	Terrain: { (terrain: Terrain) -> () },
	PlotSites: { CFrame },
	ShopFronts: { [number]: string }, -- instId -> Name der Laden-Front (Spec-Name)
	Count: number,
}

-- ---------------------------------------------------------------------
-- 1) PALETTE (§A4: Glas, Marmor, gebürstetes Metall; Neon nur als Akzent)
-- ---------------------------------------------------------------------
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

type Look = { Mat: Enum.Material, Color: Color3, Refl: number?, Transp: number? }

local L: { [string]: Look } = {
	MarbleBlack = { Mat = Enum.Material.Marble, Color = rgb(21, 23, 28), Refl = 0.15 },
	MarbleWhite = { Mat = Enum.Material.Marble, Color = rgb(226, 228, 232), Refl = 0.12 },
	MarbleGrey = { Mat = Enum.Material.Marble, Color = rgb(96, 100, 110), Refl = 0.14 },
	Glass = { Mat = Enum.Material.Glass, Color = rgb(111, 143, 184), Refl = 0.2, Transp = 0.3 },
	GlassDark = { Mat = Enum.Material.Glass, Color = rgb(40, 52, 72), Refl = 0.25, Transp = 0.15 },
	GlassClear = { Mat = Enum.Material.Glass, Color = rgb(200, 214, 235), Refl = 0.15, Transp = 0.6 },
	Metal = { Mat = Enum.Material.Metal, Color = rgb(31, 41, 55), Refl = 0.08 },
	Steel = { Mat = Enum.Material.Metal, Color = rgb(138, 148, 166), Refl = 0.15 },
	Asphalt = { Mat = Enum.Material.Asphalt, Color = rgb(40, 42, 48) },
	Concrete = { Mat = Enum.Material.Concrete, Color = rgb(110, 114, 122) },
	ConcreteLight = { Mat = Enum.Material.Concrete, Color = rgb(160, 164, 171) },
	Pavement = { Mat = Enum.Material.Pavement, Color = rgb(122, 126, 134) },
	Line = { Mat = Enum.Material.SmoothPlastic, Color = rgb(226, 230, 236) },
	Grass = { Mat = Enum.Material.Grass, Color = rgb(47, 93, 58) },
	Leaf = { Mat = Enum.Material.Grass, Color = rgb(36, 82, 50) },
	LeafDark = { Mat = Enum.Material.Grass, Color = rgb(28, 64, 42) },
	Wood = { Mat = Enum.Material.WoodPlanks, Color = rgb(107, 79, 58) },
	Bark = { Mat = Enum.Material.Wood, Color = rgb(74, 56, 42) },
	Plastic = { Mat = Enum.Material.SmoothPlastic, Color = rgb(26, 33, 48) },
	PlasticLight = { Mat = Enum.Material.SmoothPlastic, Color = rgb(230, 234, 240) },
	Showroom = { Mat = Enum.Material.SmoothPlastic, Color = rgb(232, 234, 238), Refl = 0.3 },
	Mirror = { Mat = Enum.Material.SmoothPlastic, Color = rgb(210, 216, 226), Refl = 0.85 },
	Gold = { Mat = Enum.Material.Metal, Color = rgb(250, 204, 21), Refl = 0.3 }, -- nur Glocke, Hall of Fame (§A4)
	Water = { Mat = Enum.Material.Glass, Color = rgb(79, 140, 255), Refl = 0.3, Transp = 0.45 },
	Fabric = { Mat = Enum.Material.Fabric, Color = rgb(40, 46, 62) },
	Rubber = { Mat = Enum.Material.SmoothPlastic, Color = rgb(22, 23, 27) },
	Sand = { Mat = Enum.Material.Sand, Color = rgb(150, 138, 110) },
}
local NEON = {
	Accent = rgb(79, 140, 255),
	Up = rgb(34, 197, 94),
	Down = rgb(239, 68, 68),
	Warn = rgb(234, 179, 8),
	Cosmic = rgb(124, 92, 255),
	Cosmic2 = rgb(179, 107, 255),
	Ring = rgb(110, 162, 242),
	Letters = rgb(234, 241, 255),
	Candle = rgb(42, 79, 138),
	Grid = rgb(36, 72, 140),
	White = rgb(235, 242, 255),
	Warm = rgb(255, 214, 150),
	Cyan = rgb(34, 211, 238),
	Gold = rgb(250, 204, 21),
}
local SECTOR_COLORS: { [string]: Color3 } = {
	T = rgb(79, 140, 255),
	E = rgb(34, 211, 238),
	M = rgb(139, 92, 246),
	K = rgb(245, 158, 11),
	G = rgb(236, 72, 153),
	F = rgb(250, 204, 21),
}

-- ---------------------------------------------------------------------
-- 2) BAU-WERKZEUG (sammelt Specs in Gruppen)
-- ---------------------------------------------------------------------
local plan: Plan
local current: Group
local cfg: any

local function group(key: string, district: string, mode: string, lod: boolean?)
	local g: Group = {
		Key = key,
		District = district,
		Mode = mode,
		Lod = lod == true,
		Specs = {},
		AssetCFrames = {},
	}
	table.insert(plan.Groups, g)
	current = g
end

type Opts = {
	Collide: boolean?,
	Shadow: boolean?,
	Shape: Enum.PartType?,
	Wedge: boolean?,
	Transp: number?,
	Refl: number?,
	Attrs: { [string]: any }?,
	Light: LightSpec?,
	Gui: GuiSpec?,
	Prompt: PromptSpec?,
	Emitter: EmitterSpec?,
	Mesh: { Type: Enum.MeshType, Scale: Vector3 }?,
	Sub: string?,
	SubAttrs: { [string]: any }?,
	Asset: string?,
	Priority: boolean?,
	Class: string?,
	Color: Color3?,
}

local function part(name: string, cf: CFrame, size: Vector3, look: Look, opts: Opts?): Spec
	local o: Opts = opts or {}
	local spec: Spec = {
		Class = o.Class or (if o.Wedge then "WedgePart" else "Part"),
		Shape = o.Shape,
		Name = name,
		Size = size,
		CFrame = cf,
		Color = o.Color or look.Color,
		Material = look.Mat,
		Transparency = if o.Transp ~= nil then o.Transp else look.Transp,
		Reflectance = if o.Refl ~= nil then o.Refl else look.Refl,
		Collide = if o.Collide ~= nil then o.Collide else true,
		Shadow = o.Shadow,
		Attrs = o.Attrs,
		Light = o.Light,
		Gui = o.Gui,
		Prompt = o.Prompt,
		Emitter = o.Emitter,
		Mesh = o.Mesh,
		Sub = o.Sub,
		SubAttrs = o.SubAttrs,
		Asset = o.Asset,
		Priority = o.Priority,
	}
	table.insert(current.Specs, spec)
	plan.Count += 1
	return spec
end

-- Neon-Streifen (nie kollidierend, kein Schatten)
local function neon(name: string, cf: CFrame, size: Vector3, color: Color3, opts: Opts?): Spec
	local o: Opts = opts or {}
	o.Collide = false
	o.Shadow = false
	o.Color = color
	return part(name, cf, size, { Mat = Enum.Material.Neon, Color = color }, o)
end

-- Deko ohne Kollision
local function deco(name: string, cf: CFrame, size: Vector3, look: Look, opts: Opts?): Spec
	local o: Opts = opts or {}
	if o.Collide == nil then
		o.Collide = false
	end
	if o.Shadow == nil then
		o.Shadow = false
	end
	return part(name, cf, size, look, o)
end

-- liegender Zylinder (Achse senkrecht): Größe (Höhe, Durchmesser)
local function disc(name: string, pos: Vector3, height: number, radius: number, look: Look, opts: Opts?): Spec
	local o: Opts = opts or {}
	o.Shape = Enum.PartType.Cylinder
	return part(
		name,
		CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2),
		Vector3.new(height, radius * 2, radius * 2),
		look,
		o
	)
end

local function anchor(name: string, cf: CFrame)
	plan.Anchors[name] = cf
	part("Anchor_" .. name, cf * CFrame.new(0, 1, 0), Vector3.new(2, 2, 2), L.Plastic, {
		Collide = false,
		Transp = 1,
		Shadow = false,
		Attrs = { Anchor = name },
		Priority = true,
	})
end

local function polar(r: number, deg: number, y: number?): Vector3
	local a = math.rad(deg)
	return Vector3.new(r * math.cos(a), y or 0, r * math.sin(a))
end

-- Blick zur Plaza-Mitte (auf Höhe y)
local function facingCenter(pos: Vector3): CFrame
	return CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0))
end

local function lightSpec(kind: string, def: any, nightOnly: boolean?, extra: { [string]: any }?): LightSpec
	local spec: LightSpec = {
		Kind = kind,
		Range = def.Range,
		Brightness = def.Brightness,
		Color = def.Color,
		NightOnly = nightOnly,
		Angle = def.Angle,
	}
	if extra then
		for k, v in pairs(extra) do
			(spec :: any)[k] = v
		end
	end
	return spec
end

local function signName(key: string, fallback: string): string
	local signs = cfg.City and cfg.City.Signs
	if type(signs) == "table" then
		for _, sign in ipairs(signs) do
			if sign.Key == key and type(sign.Name) == "string" then
				return sign.Name
			end
		end
	end
	return fallback
end

-- ---------------------------------------------------------------------
-- 3) BAUSTEINE: Laterne, Baum, Bank, Straßenabschnitte
-- ---------------------------------------------------------------------
local function lantern(name: string, base: Vector3, toward: Vector3)
	local lights = cfg.City.Lights
	local dir = Vector3.new(toward.X, 0, toward.Z)
	if dir.Magnitude < 1e-3 then
		dir = Vector3.new(0, 0, -1)
	end
	dir = dir.Unit
	-- Mast reicht 1,2 Studs in den Boden: steht bündig, egal ob auf Gehweg (0,6), Fahrbahn (0,25) oder Terrain (0)
	part(
		name .. "Pole",
		CFrame.new(base + Vector3.new(0, 6.4, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Vector3.new(15.2, 0.7, 0.7),
		L.Metal,
		{ Shape = Enum.PartType.Cylinder, Shadow = false }
	)
	local armCf = CFrame.lookAt(base + Vector3.new(0, 13.8, 0) + dir * 1.6, base + Vector3.new(0, 13.8, 0) + dir * 3)
	deco(name .. "Arm", armCf, Vector3.new(0.35, 0.35, 3.2), L.Metal)
	neon(name .. "Head", armCf * CFrame.new(0, -0.25, -1.4), Vector3.new(1.1, 0.25, 1.8), NEON.Warm, {
		Light = lightSpec("Point", lights.Lantern, true, { Face = nil }),
	})
end

local function tree(name: string, base: Vector3, scale: number)
	local s = scale
	local trunk = deco(
		name .. "Trunk",
		CFrame.new(base + Vector3.new(0, 3 * s, 0)),
		Vector3.new(6 * s, 1.1 * s, 1.1 * s),
		L.Bark,
		{
			Shape = Enum.PartType.Cylinder,
			Collide = true,
		}
	)
	trunk.CFrame = CFrame.new(base + Vector3.new(0, 3 * s, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	deco(name .. "Crown", CFrame.new(base + Vector3.new(0, 7.5 * s, 0)), Vector3.new(7 * s, 7 * s, 7 * s), L.Leaf, {
		Shape = Enum.PartType.Ball,
		Shadow = true,
	})
	deco(
		name .. "Crown2",
		CFrame.new(base + Vector3.new(1.2 * s, 9.6 * s, -0.8 * s)),
		Vector3.new(4.6 * s, 4.6 * s, 4.6 * s),
		L.LeafDark,
		{ Shape = Enum.PartType.Ball, Shadow = true }
	)
end

local function bench(name: string, cf: CFrame)
	part(name .. "Seat", cf * CFrame.new(0, 1.2, 0), Vector3.new(6, 0.4, 1.8), L.Wood, { Shadow = true })
	deco(name .. "Leg", cf * CFrame.new(0, 0.5, 0), Vector3.new(5, 1, 0.5), L.Metal)
	deco(
		name .. "Back",
		cf * CFrame.new(0, 2.3, 0.75) * CFrame.Angles(math.rad(-10), 0, 0),
		Vector3.new(6, 1.6, 0.3),
		L.Wood
	)
end

local function planter(name: string, pos: Vector3)
	part(name .. "Box", CFrame.new(pos + Vector3.new(0, 1, 0)), Vector3.new(6, 2, 6), L.MarbleGrey, { Shadow = true })
	tree(name, pos + Vector3.new(0, 2, 0), 0.75)
end

type RoadOpts = {
	Width: number,
	Thickness: number,
	Top: number,
	Look: Look,
	Overlap: number,
	Center: string?, -- "Solid" | "Dash" | "Barrier"
	Lanes: { number }?, -- Strich-Versatz der Spurmarkierungen
	Walks: boolean?,
	EdgeBarriers: boolean?,
	Curbs: boolean?,
	LampEvery: number?,
	LampSide: number?, -- 1 = außen, −1 = innen, 0 = beide
	Prefix: string,
	Kerbs: ((midDeg: number) -> boolean)?,
	Extra: ((i: number, cf: CFrame, len: number, p0: Vector3, p1: Vector3) -> ())?,
	GroupEvery: number?,
	GroupFn: ((index: number) -> ())?,
}

-- Straße entlang einer Punktliste (geschlossen oder offen). Abschnitte überlappen leicht; jeder zweite liegt 0,02 höher
-- (kein Z-Flackern an den Überlappungen).
local function road(points: { Vector3 }, o: RoadOpts)
	local walkW = cfg.City.Roads.WalkWidth
	local walkTop = cfg.City.Levels.Walk
	local walkT = cfg.City.Levels.WalkThickness
	for i = 1, #points - 1 do
		if o.GroupEvery and o.GroupFn and (i - 1) % o.GroupEvery == 0 then
			o.GroupFn((i - 1) // o.GroupEvery + 1)
		end
		local p0, p1 = points[i], points[i + 1]
		local flat = Vector3.new(p1.X - p0.X, 0, p1.Z - p0.Z)
		local len = flat.Magnitude
		if len < 0.5 then
			continue
		end
		local lift = if i % 2 == 0 then 0.02 else 0
		local mid = (p0 + p1) / 2
		local center = Vector3.new(mid.X, o.Top - o.Thickness / 2 + lift, mid.Z)
		local cf = CFrame.lookAt(center, center + flat)
		local segLen = len + o.Overlap
		local name = o.Prefix .. i
		part(name, cf, Vector3.new(o.Width, o.Thickness, segLen), o.Look, { Shadow = false })
		local markY = o.Thickness / 2 + 0.03
		if o.Center == "Solid" then
			deco(name .. "C", cf * CFrame.new(0, markY, 0), Vector3.new(0.4, 0.06, segLen), L.Line)
		elseif o.Center == "Dash" then
			deco(name .. "C", cf * CFrame.new(0, markY, 0), Vector3.new(0.35, 0.06, segLen * 0.5), L.Line)
		elseif o.Center == "Barrier" then
			part(
				name .. "C",
				cf * CFrame.new(0, o.Thickness / 2 + 1.1, 0),
				Vector3.new(0.9, 2.2, segLen),
				L.ConcreteLight,
				{
					Shadow = false,
				}
			)
		end
		if o.Lanes then
			for k, offset in ipairs(o.Lanes) do
				deco(name .. "L" .. k, cf * CFrame.new(offset, markY, 0), Vector3.new(0.3, 0.06, segLen * 0.45), L.Line)
			end
		end
		if o.Walks then
			for _, side in ipairs({ -1, 1 }) do
				local x = side * (o.Width / 2 + walkW / 2)
				local y = (walkTop - walkT / 2) - (o.Top - o.Thickness / 2) + lift
				part(
					name .. (if side < 0 then "WI" else "WO"),
					cf * CFrame.new(x, y, 0),
					Vector3.new(walkW, walkT, segLen + 0.6),
					L.Pavement,
					{
						Shadow = false,
					}
				)
			end
		end
		if o.EdgeBarriers then
			for _, side in ipairs({ -1, 1 }) do
				part(
					name .. (if side < 0 then "BI" else "BO"),
					cf * CFrame.new(side * (o.Width / 2 - 0.4), o.Thickness / 2 + 1.1, 0),
					Vector3.new(0.8, 2.2, segLen),
					L.ConcreteLight,
					{ Shadow = false }
				)
			end
		elseif o.Curbs then
			for _, side in ipairs({ -1, 1 }) do
				part(
					name .. (if side < 0 then "KI" else "KO"),
					cf * CFrame.new(side * (o.Width / 2 + 0.4), o.Thickness / 2 + 0.15, 0),
					Vector3.new(0.8, 0.3 + o.Thickness, segLen),
					L.ConcreteLight,
					{ Shadow = false }
				)
			end
		end
		if o.Kerbs then
			local midDeg = math.deg(math.atan2(mid.Z, mid.X)) % 360
			if o.Kerbs(midDeg) then
				deco(
					name .. "Kerb",
					cf * CFrame.new(o.Width / 2 - 1.6, o.Thickness / 2 + 0.06, 0),
					Vector3.new(1.6, 0.12, segLen * 0.5),
					{ Mat = Enum.Material.SmoothPlastic, Color = if i % 2 == 0 then NEON.Down else rgb(240, 242, 246) }
				)
			end
		end
		if o.LampEvery and i % o.LampEvery == 0 then
			local sides = if o.LampSide == 0 then { -1, 1 } else { o.LampSide or 1 }
			for _, side in ipairs(sides) do
				local offset = o.Width / 2 + (if o.Walks then walkW * 0.6 else 1.5)
				local pos = (cf * CFrame.new(side * offset, 0, 0)).Position
				local base = Vector3.new(pos.X, (if o.Walks then walkTop else o.Top), pos.Z)
				local toward = (cf * CFrame.new(-side * 10, 0, 0)).Position - pos
				lantern(name .. "Lamp" .. (if side < 0 then "I" else "O"), base, toward)
			end
		end
		if o.Extra then
			o.Extra(i, cf, segLen, p0, p1)
		end
	end
end

-- gerade Strecke von a nach b (Avenue, Einfahrt)
local function straight(
	name: string,
	a: Vector3,
	b: Vector3,
	width: number,
	look: Look,
	top: number,
	walks: boolean,
	center: string?
)
	road({ a, b }, {
		Width = width,
		Thickness = cfg.City.Levels.RoadThickness,
		Top = top,
		Look = look,
		Overlap = 0,
		Center = center,
		Walks = walks,
		Prefix = name,
	})
end

-- Text-Schild (SurfaceGui auf einem Teil)
local function sign(name: string, cf: CFrame, size: Vector3, text: string, color: Color3, opts: Opts?): Spec
	local o: Opts = opts or {}
	o.Gui = { Face = Enum.NormalId.Front, Text = text, Color = color, Display = true, MaxDistance = 900 }
	o.Shadow = false
	return part(name, cf, size, L.Plastic, o)
end

-- ---------------------------------------------------------------------
-- 4) TERRAIN (Boden, Grüngürtel, Marina, Villenhügel mit Serpentine + Autobahn-Tunnel)
-- ---------------------------------------------------------------------
local HILL_SPHERE = 300 -- Kugel-Radius der Hügelkappe
local HILL_DROP = 180 -- Kugel-Mittelpunkt liegt so tief unter dem Boden (Kappe 120 hoch, Fuß-Radius 240)

function CityLayout.HillHeight(x: number, z: number): number
	local zones = (cfg and cfg.City and cfg.City.Zones) or nil
	local center = if zones then zones.Hill.Center else Vector3.new(0, 0, -820)
	local dx, dz = x - center.X, z - center.Z
	local d2 = dx * dx + dz * dz
	local r2 = HILL_SPHERE * HILL_SPHERE
	if d2 >= r2 then
		return 0
	end
	return math.max(0, math.sqrt(r2 - d2) - HILL_DROP)
end

-- Serpentine (x, z) vom äußeren Ring zum Gipfel
local SERPENTINE: { Vector2 } = {
	Vector2.new(0, -578),
	Vector2.new(40, -598),
	Vector2.new(92, -618),
	Vector2.new(112, -640),
	Vector2.new(84, -662),
	Vector2.new(20, -676),
	Vector2.new(-60, -690),
	Vector2.new(-108, -708),
	Vector2.new(-96, -730),
	Vector2.new(-30, -744),
	Vector2.new(40, -756),
	Vector2.new(74, -774),
	Vector2.new(50, -792),
	Vector2.new(10, -800),
}

local function serpentinePoints(): { Vector3 }
	-- fein unterteilt (≤ 24 Studs), Höhe aus der Hügelkappe
	local out: { Vector3 } = {}
	for i = 1, #SERPENTINE - 1 do
		local a, b = SERPENTINE[i], SERPENTINE[i + 1]
		local n = math.max(1, math.ceil((b - a).Magnitude / 24))
		for k = 0, n - 1 do
			local p = a:Lerp(b, k / n)
			table.insert(out, Vector3.new(p.X, CityLayout.HillHeight(p.X, p.Y), p.Y))
		end
	end
	local last = SERPENTINE[#SERPENTINE]
	table.insert(out, Vector3.new(last.X, CityLayout.HillHeight(last.X, last.Y), last.Y))
	return out
end

-- Abstand eines Punkts zur Serpentine (waagerecht) + Straßenhöhe dort
local function serpentineAt(points: { Vector3 }, x: number, z: number): (number, number)
	local best, height = math.huge, 0
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local abx, abz = b.X - a.X, b.Z - a.Z
		local len2 = abx * abx + abz * abz
		local t = 0
		if len2 > 0 then
			t = math.clamp(((x - a.X) * abx + (z - a.Z) * abz) / len2, 0, 1)
		end
		local px, pz = a.X + abx * t, a.Z + abz * t
		local d = math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
		if d < best then
			best = d
			height = a.Y + (b.Y - a.Y) * t
		end
	end
	return best, height
end

local function addTerrainJobs(serpentine: { Vector3 })
	local ground = cfg.City.Ground
	local levels = cfg.City.Levels
	local zones = cfg.City.Zones
	local size = ground.MapSize
	local depth = ground.Depth
	local tile = 256
	local half = size / 2
	-- Boden: ganze Karte Gras (Kacheln), dann Stadt-Scheibe Pflaster, Grüngürtel, Plaza-Pflaster
	for x = -half, half - tile, tile do
		for z = -half, half - tile, tile do
			table.insert(plan.Terrain, function(terrain: Terrain)
				terrain:FillBlock(
					CFrame.new(x + tile / 2, levels.Ground - depth / 2, z + tile / 2),
					Vector3.new(tile, depth, tile),
					ground.OuterMaterial
				)
			end)
		end
	end
	local cylinder = CFrame.new(0, levels.Ground - depth / 2, 0)
	table.insert(plan.Terrain, function(terrain: Terrain)
		terrain:FillCylinder(cylinder, depth, ground.CityRadius, ground.CityMaterial)
	end)
	table.insert(plan.Terrain, function(terrain: Terrain)
		terrain:FillCylinder(cylinder, depth, 224, Enum.Material.Grass) -- Grüngürtel zwischen Plaza und Ring
	end)
	table.insert(plan.Terrain, function(terrain: Terrain)
		terrain:FillCylinder(cylinder, depth, zones.Plaza.Radius + 6, ground.CityMaterial)
	end)
	-- Marina: Mulde, Sandgrund, Wasser (Oberfläche 2 Studs unter dem Boden)
	local marina = zones.Marina
	local mc = marina.Center
	table.insert(plan.Terrain, function(terrain: Terrain)
		local water = Vector3.new(marina.Width, 0, marina.Depth)
		terrain:FillBlock(
			CFrame.new(mc.X, -marina.WaterDepth / 2 - 4, mc.Z),
			Vector3.new(water.X, marina.WaterDepth + 8, water.Z),
			Enum.Material.Air
		)
		terrain:FillBlock(
			CFrame.new(mc.X, -marina.WaterDepth - 3, mc.Z),
			Vector3.new(water.X, 6, water.Z),
			Enum.Material.Sand
		)
		terrain:FillBlock(
			CFrame.new(mc.X, (-marina.WaterDepth - 2) / 2, mc.Z),
			Vector3.new(water.X, marina.WaterDepth - 2, water.Z),
			Enum.Material.Water
		)
	end)
	-- Villenhügel: glatte Kugelkappe per WriteVoxels in Kacheln (16 × 16 Spalten), mit Serpentinen-Einschnitt
	-- (Luft über der Fahrbahn, Fels darunter) und Autobahn-Tunnel (Luft bis 24 Studs Höhe).
	local hill = zones.Hill
	local highway = cfg.City.Roads.Highway
	local res = 4
	local x0 = math.floor((hill.Center.X - 256) / res) * res
	local z0 = math.floor((hill.Center.Z - 256) / res) * res
	local columns = 512 / res -- 128
	local layers = 32 -- 0 … 128
	local chunk = 16
	local roadHalf = 11 + 3
	local tunnelHalf = highway.Width / 2 + 3
	local tunnelTop = (highway.TunnelHeight or 22) + 2
	for cx = 0, columns - 1, chunk do
		for cz = 0, columns - 1, chunk do
			table.insert(plan.Terrain, function(terrain: Terrain)
				local minX, minZ = x0 + cx * res, z0 + cz * res
				local region = Region3.new(
					Vector3.new(minX, 0, minZ),
					Vector3.new(minX + chunk * res, layers * res, minZ + chunk * res)
				)
				local materials: { { { Enum.Material } } } = {}
				local occupancy: { { { number } } } = {}
				local any = false
				for ix = 1, chunk do
					local mx: { { Enum.Material } } = {}
					local ox: { { number } } = {}
					materials[ix] = mx
					occupancy[ix] = ox
					local wx = minX + (ix - 0.5) * res
					for iy = 1, layers do
						mx[iy] = {}
						ox[iy] = {}
					end
					for iz = 1, chunk do
						local wz = minZ + (iz - 0.5) * res
						local h = CityLayout.HillHeight(wx, wz)
						local roadDist, roadTop = math.huge, 0
						if h > 0 then
							roadDist, roadTop = serpentineAt(serpentine, wx, wz)
						end
						local r = math.sqrt(wx * wx + wz * wz)
						local inTunnel = math.abs(r - highway.Radius) < tunnelHalf
						for iy = 1, layers do
							local y0 = (iy - 1) * res
							local fill = math.clamp((h - y0) / res, 0, 1)
							local material = if h - y0 > 6 then Enum.Material.Rock else Enum.Material.Grass
							if roadDist < roadHalf then
								local cut = roadTop - 0.6
								fill = math.clamp((cut - y0) / res, 0, 1)
								material = Enum.Material.Rock
							end
							if inTunnel and y0 < tunnelTop then
								fill = 0
							end
							if fill > 0.001 then
								any = true
								mx[iy][iz] = material
								ox[iy][iz] = fill
							else
								mx[iy][iz] = Enum.Material.Air
								ox[iy][iz] = 0
							end
						end
					end
				end
				if any then
					terrain:WriteVoxels(region, res, materials, occupancy)
				end
			end)
		end
	end
end

-- ---------------------------------------------------------------------
-- 5) BEZIRKE
-- ---------------------------------------------------------------------

-- 5.1 EXCHANGE PLAZA (Persistent): schwarzer Marmor, blaues Raster, Logo-Ring R 46, ΛKYTEX-Buchstaben, Brunnen,
--     Kerzentafel, 4 Ticker-Wände, Hall of Fame, Tiko, Glocken-Moment-Zone, Bestenlisten, Spawn
local LOGO_STROKES: { { number } } = { -- logo.svg (REUSE §8.5): x1, y1, x2, y2
	{ 60, 285, 81, 227 },
	{ 81, 227, 102, 285 },
	{ 132, 227, 132, 285 },
	{ 170, 227, 134, 258 },
	{ 144, 250, 172, 285 },
	{ 200, 227, 221, 256 },
	{ 242, 227, 221, 256 },
	{ 221, 256, 221, 285 },
	{ 270, 230, 312, 230 },
	{ 291, 230, 291, 285 },
	{ 377, 230, 340, 230 },
	{ 340, 230, 340, 282 },
	{ 340, 282, 377, 282 },
	{ 340, 256, 372, 256 },
	{ 410, 227, 452, 285 },
	{ 452, 227, 410, 285 },
}

local function buildPlaza()
	local zones = cfg.City.Zones
	local plaza = zones.Plaza
	local top = cfg.City.Levels.Walk
	local R = plaza.Radius
	group("Plaza", "Plaza", "Persistent", false)

	-- Boden (Priorität: steht, bevor die ersten Spieler landen)
	disc("PlazaFloor", Vector3.new(0, top - 0.6, 0), 1.2, R, L.MarbleBlack, { Priority = true, Shadow = false })
	disc("PlazaRim", Vector3.new(0, top - 0.75, 0), 0.9, R + 2.5, L.MarbleGrey, { Priority = true, Shadow = false })

	-- blaues Raster
	for i = -6, 6 do
		local offset = i * 20
		local chord = 2 * math.sqrt(math.max(0, R * R - offset * offset)) - 4
		if chord > 4 then
			deco("GridX" .. i, CFrame.new(offset, top + 0.02, 0), Vector3.new(0.22, 0.05, chord), {
				Mat = Enum.Material.Neon,
				Color = NEON.Grid,
			}, { Transp = 0.35 })
			deco("GridZ" .. i, CFrame.new(0, top + 0.02, offset), Vector3.new(chord, 0.05, 0.22), {
				Mat = Enum.Material.Neon,
				Color = NEON.Grid,
			}, { Transp = 0.35 })
		end
	end

	-- Logo-Ring R 46 (40 Segmente) + ΛKYTEX-Buchstaben + aufsteigende Kerzen (logo.svg)
	local ring = plaza.LogoRadius
	local segments = 40
	for i = 0, segments - 1 do
		local a = (i + 0.5) * 2 * math.pi / segments
		local pos = Vector3.new(ring * math.cos(a), top + 0.04, ring * math.sin(a))
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		neon(
			"LogoRing" .. i,
			CFrame.lookAt(pos, pos + tangent),
			Vector3.new(0.55, 0.06, 2 * math.pi * ring / segments + 0.2),
			NEON.Ring
		)
	end
	local s = ring / 228
	for i, stroke in ipairs(LOGO_STROKES) do
		local a = Vector3.new((stroke[1] - 256) * s, top + 0.05, (stroke[2] - 256) * s)
		local b = Vector3.new((stroke[3] - 256) * s, top + 0.05, (stroke[4] - 256) * s)
		local len = (b - a).Magnitude
		neon("LogoStroke" .. i, CFrame.lookAt((a + b) / 2, b), Vector3.new(0.95, 0.06, len + 0.9), NEON.Letters)
	end
	for i = 0, 19 do
		local x = 58 + i * (412 / 19)
		local y = 390 - i * (280 / 19)
		local offset = Vector3.new((x - 256) * s, 0, (y - 256) * s)
		if offset.Magnitude < 205 * s then
			local bodyLen = (24 + 12 * math.sin(i * 1.7)) * s
			neon(
				"Candle" .. i,
				CFrame.new(offset.X, top + 0.03, offset.Z),
				Vector3.new(1.4, 0.05, bodyLen),
				NEON.Candle,
				{
					Transp = 0.35,
				}
			)
		end
	end

	-- ΛKYTEX-Neonbuchstaben (Metallkörper + Neon-Front), Blick nach Süden
	local letterH = plaza.LetterHeight or 24
	local bs = letterH / 58
	local baseZ = 106
	local baseY = top + 1.6
	part("LetterPlinth", CFrame.new(0, top + 0.8, baseZ), Vector3.new(176, 1.6, 8), L.MarbleGrey, { Shadow = true })
	for i, stroke in ipairs(LOGO_STROKES) do
		local a = Vector3.new((stroke[1] - 256) * bs, baseY + (285 - stroke[2]) * bs, baseZ)
		local b = Vector3.new((stroke[3] - 256) * bs, baseY + (285 - stroke[4]) * bs, baseZ)
		local dir = (b - a)
		local len = dir.Magnitude
		dir = dir.Unit
		local perp = Vector3.new(-dir.Y, dir.X, 0)
		local cf = CFrame.fromMatrix((a + b) / 2, dir, perp)
		part("BigLetter" .. i, cf, Vector3.new(len + 1.6, 1.6, 2), L.Metal, { Shadow = true })
		neon("BigLetterNeon" .. i, cf * CFrame.new(0, 0, 1.05), Vector3.new(len + 1.2, 0.7, 0.3), NEON.Letters)
	end

	-- Brunnen (Asset-Platz "Fountain")
	local fc = Vector3.new(0, top, 74)
	current.AssetCFrames.Fountain = CFrame.new(fc)
	disc("FountainBasin", fc + Vector3.new(0, 0.7, 0), 1.4, 12, L.MarbleWhite, { Asset = "Fountain" })
	disc("FountainWater", fc + Vector3.new(0, 1.2, 0), 0.6, 11, L.Water, { Asset = "Fountain", Collide = false })
	disc("FountainRing", fc + Vector3.new(0, 1.45, 0), 0.1, 12.2, { Mat = Enum.Material.Neon, Color = NEON.Accent }, {
		Asset = "Fountain",
		Collide = false,
		Shadow = false,
	})
	part("FountainColumn", CFrame.new(fc + Vector3.new(0, 4, 0)), Vector3.new(2.6, 6, 2.6), L.MarbleWhite, {
		Asset = "Fountain",
	})
	disc("FountainBowl", fc + Vector3.new(0, 7.2, 0), 0.8, 4.5, L.MarbleWhite, {
		Asset = "Fountain",
		Emitter = {
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Rate = 40,
			Lifetime = NumberRange.new(1.1, 1.5),
			Speed = NumberRange.new(14, 18),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.6) }),
			Color = ColorSequence.new(Color3.fromRGB(200, 225, 255)),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
			LightEmission = 0.4,
			Spread = Vector2.new(14, 14),
			Acceleration = Vector3.new(0, -26, 0),
			Face = Enum.NormalId.Right, -- Zylinder-Achse X = oben
		},
	})

	-- Riesen-Kerzentafel 24 Studs (AKX36 live) im Osten, Blick zur Mitte
	local boardPos = Vector3.new(100, top, 6)
	local boardCf = CFrame.lookAt(boardPos + Vector3.new(0, 14, 0), Vector3.new(0, top + 14, 6))
	part("CandleBoard", boardCf, Vector3.new(24, 13.5, 0.6), L.Plastic, {
		Attrs = { Monitor = "Candles", Inst = 40 },
		Shadow = false,
	})
	part("CandleBoardFrame", boardCf * CFrame.new(0, 0, 0.5), Vector3.new(25.4, 14.9, 0.4), L.Metal)
	for _, side in ipairs({ -1, 1 }) do
		part(
			"CandleBoardLeg" .. side,
			CFrame.new(boardPos + boardCf.RightVector * side * 9 + Vector3.new(0, 3.6, 0)),
			Vector3.new(1, 7.2, 1),
			L.Metal
		)
	end
	neon("CandleBoardGlow", boardCf * CFrame.new(0, -7.6, 0.2), Vector3.new(25.4, 0.25, 0.3), NEON.Accent)

	-- 4 Ticker-Wände (64 × 8) auf Säulen, Blick zur Mitte
	for k, deg in ipairs({ 30, 150, 210, 330 }) do
		local pos = polar(118, deg, top)
		local cf = facingCenter(pos + Vector3.new(0, 14, 0))
		part(
			"TickerWall" .. k,
			cf,
			Vector3.new(64, 8, 0.6),
			L.Plastic,
			{ Attrs = { Monitor = "Ticker" }, Shadow = false }
		)
		part("TickerWallBack" .. k, cf * CFrame.new(0, 0, 0.5), Vector3.new(65, 9, 0.4), L.Metal)
		neon("TickerWallTop" .. k, cf * CFrame.new(0, 4.6, 0.1), Vector3.new(65, 0.25, 0.5), NEON.Accent)
		for _, side in ipairs({ -1, 1 }) do
			local leg = (cf * CFrame.new(side * 26, -7, 0.5)).Position
			part(
				"TickerWallLeg" .. k .. side,
				CFrame.new(Vector3.new(leg.X, top + 5, leg.Z)),
				Vector3.new(1.2, 10, 1.2),
				L.Metal
			)
		end
	end

	-- Hall of Fame (3 Sockel + Tafel) im Westen
	local hof = Vector3.new(-102, top, -4)
	local hofLook = Vector3.new(1, 0, 0)
	for i, spec in ipairs({ { 0, 4 }, { -9, 3 }, { 9, 2.4 } }) do
		local pos = hof + Vector3.new(0, 0, spec[1])
		part(
			"HallPlinth" .. i,
			CFrame.new(pos + Vector3.new(0, spec[2] / 2, 0)),
			Vector3.new(6, spec[2], 6),
			L.MarbleWhite
		)
		part(
			"HallTop" .. i,
			CFrame.lookAt(pos + Vector3.new(0, spec[2] + 0.15, 0), pos + Vector3.new(0, spec[2] + 0.15, 0) + hofLook),
			Vector3.new(6.4, 0.3, 6.4),
			L.Gold,
			{
				Attrs = { Board = "Hall" .. i },
				Priority = true,
			}
		)
	end
	part(
		"HallPlaque",
		CFrame.lookAt(hof + Vector3.new(-6, 6, 0), hof + Vector3.new(4, 6, 0)),
		Vector3.new(24, 7, 0.5),
		L.MarbleBlack,
		{
			Attrs = { Board = "HallOfFame" },
			Priority = true,
		}
	)
	neon(
		"HallPlaqueTop",
		CFrame.lookAt(hof + Vector3.new(-5.7, 9.6, 0), hof + Vector3.new(4, 9.6, 0)),
		Vector3.new(24, 0.25, 0.3),
		NEON.Gold
	)
	anchor("HallOfFame", CFrame.lookAt(hof + Vector3.new(20, 0, 0), hof))

	-- Tiko-Hologramm (Asset-Platz "Tiko"); WP9 findet es über Attribut "Tiko"
	local tiko = Vector3.new(-34, top, 58)
	current.AssetCFrames.Tiko = CFrame.new(tiko)
	disc("TikoPad", tiko + Vector3.new(0, 0.15, 0), 0.3, 3.2, L.Metal, { Asset = "Tiko" })
	disc("TikoPadRing", tiko + Vector3.new(0, 0.32, 0), 0.06, 3.3, { Mat = Enum.Material.Neon, Color = NEON.Accent }, {
		Asset = "Tiko",
		Collide = false,
		Shadow = false,
	})
	deco(
		"TikoBody",
		CFrame.new(tiko + Vector3.new(0, 3.2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Vector3.new(2.6, 1.8, 1.8),
		{
			Mat = Enum.Material.Glass,
			Color = NEON.Accent,
			Transp = 0.35,
		},
		{ Shape = Enum.PartType.Cylinder, Asset = "Tiko", Attrs = { Tiko = true } }
	)
	deco("TikoHead", CFrame.new(tiko + Vector3.new(0, 5.4, 0)), Vector3.new(2.2, 2.2, 2.2), {
		Mat = Enum.Material.Glass,
		Color = NEON.Ring,
		Transp = 0.3,
	}, { Shape = Enum.PartType.Ball, Asset = "Tiko" })
	neon(
		"TikoEyes",
		CFrame.lookAt(tiko + Vector3.new(0, 5.5, 0), tiko + Vector3.new(0, 5.5, -10)) * CFrame.new(0, 0, -1.05),
		Vector3.new(1.1, 0.25, 0.1),
		NEON.White,
		{
			Asset = "Tiko",
		}
	)
	neon(
		"TikoHalo",
		CFrame.new(tiko + Vector3.new(0, 1.6, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Vector3.new(0.12, 3.4, 3.4),
		NEON.Accent,
		{
			Shape = Enum.PartType.Cylinder,
			Asset = "Tiko",
		}
	)

	-- Pressekonferenz-Bildschirm (WP11 zeigt dort das CEO-Hologramm)
	local press = Vector3.new(74, top, 50)
	local pressCf = CFrame.lookAt(press + Vector3.new(0, 7, 0), Vector3.new(0, top + 7, 0))
	part("PressScreen", pressCf, Vector3.new(16, 9, 0.4), L.Plastic, {
		Attrs = { Board = "PressScreen" },
		Shadow = false,
		Priority = true,
	})
	part("PressStand", CFrame.new(press + Vector3.new(0, 1.3, 0)), Vector3.new(1.2, 2.6, 1.2), L.Metal)
	disc("PressStage", press + Vector3.new(0, 0.2, 0) + pressCf.LookVector * 8, 0.4, 7, L.MarbleGrey)
	anchor("PressScreen", CFrame.lookAt(press + pressCf.LookVector * 14, press))

	-- Bestenlisten-Hologramme vor dem Börsensaal (WP9 schreibt auf die Board-Flächen)
	for _, def in ipairs({
		{ "Wealth", Vector3.new(-72, top, -103) },
		{ "Skyline", Vector3.new(-40, top, -103) },
		{ "League", Vector3.new(40, top, -103) },
		{ "Respekt", Vector3.new(72, top, -103) },
	}) do
		local name, pos = def[1], def[2]
		local cf = CFrame.lookAt(pos + Vector3.new(0, 10, 0), pos + Vector3.new(0, 10, 0) + Vector3.new(0, 0, 1))
		part("Board" .. name, cf, Vector3.new(14, 18, 0.4), L.Plastic, {
			Attrs = { Board = name },
			Shadow = false,
			Priority = true,
		})
		neon("Board" .. name .. "Glow", cf * CFrame.new(0, -9.3, 0), Vector3.new(14.4, 0.3, 0.5), NEON.Accent)
		disc("Board" .. name .. "Base", pos + Vector3.new(0, 0.3, 0), 0.6, 3.5, L.Metal, {
			Prompt = {
				TextKey = "world.prompt.boards",
				ObjectKey = "world.object.boards",
				Window = "Boards",
				Distance = 12,
			},
		})
	end

	-- Glocken-Moment-Zone (R 18) vor dem Eingang
	local zoneCenter = Vector3.new(0, top, -120 + plaza.BellZoneRadius + 4)
	for i = 0, 23 do
		local a = (i + 0.5) * 2 * math.pi / 24
		local pos = zoneCenter
			+ Vector3.new(plaza.BellZoneRadius * math.cos(a), 0.05, plaza.BellZoneRadius * math.sin(a))
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		neon("BellZone" .. i, CFrame.lookAt(pos, pos + tangent), Vector3.new(0.4, 0.06, 3), NEON.Gold, { Transp = 0.2 })
	end
	anchor("BellZone", CFrame.lookAt(zoneCenter, zoneCenter + Vector3.new(0, 0, -1)))

	-- Tower-Tour-Kiosk (Liste nach Höhe – Fenster "Social", Tab "Visit")
	local kiosk = Vector3.new(36, top, 60)
	local kioskCf = CFrame.lookAt(kiosk + Vector3.new(0, 3.5, 0), kiosk + Vector3.new(0, 3.5, 10))
	part("TourKiosk", CFrame.new(kiosk + Vector3.new(0, 1.6, 0)), Vector3.new(4, 3.2, 2), L.Metal, {
		Prompt = {
			TextKey = "world.prompt.tour",
			ObjectKey = "world.object.tour",
			Window = "Social",
			Tab = "Visit",
			Distance = 10,
		},
	})
	part("TourScreen", kioskCf * CFrame.Angles(math.rad(15), 0, 0), Vector3.new(4.6, 2.8, 0.25), L.Plastic, {
		Attrs = { Board = "TowerTour" },
		Collide = false,
		Shadow = false,
		Priority = true,
	})
	anchor("TowerTour", CFrame.lookAt(kiosk + Vector3.new(0, 0, 7), kiosk))

	-- Spawn (unsichtbar), Laternen, Bänke, Pflanzkübel
	local spawnPos = Vector3.new(0, top, 52)
	part("SpawnPad", CFrame.new(spawnPos + Vector3.new(0, 0.05, 0)), Vector3.new(10, 0.1, 10), L.Plastic, {
		Class = "SpawnLocation",
		Collide = false,
		Transp = 1,
		Shadow = false,
		Priority = true,
	})
	anchor("Spawn", CFrame.lookAt(spawnPos, spawnPos + Vector3.new(0, 0, -1)))
	for i = 0, 15 do
		local deg = 11.25 + i * 22.5
		if deg > 230 and deg < 310 then
			continue -- vor dem Börsensaal frei
		end
		local pos = polar(R - 5, deg, top)
		lantern("PlazaLamp" .. i, pos, -pos)
	end
	for i, def in ipairs({
		{ Vector3.new(-22, top, 74), Vector3.new(1, 0, 0) },
		{ Vector3.new(22, top, 74), Vector3.new(-1, 0, 0) },
		{ Vector3.new(-62, top, -22), Vector3.new(1, 0, 0) },
		{ Vector3.new(62, top, -22), Vector3.new(-1, 0, 0) },
	}) do
		bench("PlazaBench" .. i, CFrame.lookAt(def[1], def[1] + def[2]))
	end
	for i, pos in ipairs({
		Vector3.new(-48, top, 90),
		Vector3.new(48, top, 90),
		Vector3.new(-60, top, -44),
		Vector3.new(60, top, -44),
	}) do
		planter("PlazaPlanter" .. i, pos)
	end

	-- Fußwege zur Ringstraße (Ost, Süd, West) durch den Grüngürtel
	local walkTop = cfg.City.Levels.Walk
	for _, deg in ipairs({ 0, 90, 180 }) do
		local a = polar(R, deg, walkTop)
		local b = polar(224, deg, walkTop)
		part(
			"Walkway" .. deg,
			CFrame.lookAt((a + b) / 2 - Vector3.new(0, 0.6, 0), b - Vector3.new(0, 0.6, 0)),
			Vector3.new(16, 1.2, (b - a).Magnitude + 2),
			L.Pavement,
			{ Shadow = false }
		)
	end
	-- Bäume im Grüngürtel
	local treeIndex = 0
	for _, deg in ipairs({ 12, 24, 52, 60, 84, 96, 120, 132, 156, 168, 192, 204, 228, 340, 352 }) do
		for _, radius in ipairs({ 158, 208 }) do
			treeIndex += 1
			tree("BeltTree" .. treeIndex, polar(radius, deg + (radius - 158) * 0.05, 0), 1 + ((treeIndex % 3) * 0.12))
		end
	end
end

-- 5.2 BÖRSENSAAL „AKYTEX Exchange“ (Persistent + LOD): Glaskuppel, Glocke, Tickerring, Heatmap, Monitorwand,
--     8 Terminal-Pulte, VIP-Balkon, Akademie, Dachterrasse (Club), IPO-Wand
local function buildExchange()
	local ex = cfg.City.Zones.Exchange
	local c = ex.Center
	local top = cfg.City.Levels.Walk
	local hw, hd, H = ex.Width / 2, ex.Depth / 2, ex.Height
	local front = c.Z + hd -- −120
	local back = c.Z - hd -- −260
	group("Exchange", "Exchange", "Persistent", cfg.City.Streaming.MeshLod.Exchange == true)

	-- Boden: Marmor-Parkett
	part("HallFloor", CFrame.new(c.X, top - 0.6, c.Z), Vector3.new(ex.Width, 1.2, ex.Depth), L.MarbleWhite, {
		Priority = true,
		Shadow = false,
	})
	for i, z in ipairs({ -10, 10 }) do
		deco(
			"FloorInlay" .. i,
			CFrame.new(c.X, top + 0.02, c.Z + z * 4),
			Vector3.new(ex.Width - 8, 0.05, 1.2),
			L.MarbleBlack
		)
	end
	for i, x in ipairs({ -1, 1 }) do
		deco(
			"FloorInlayX" .. i,
			CFrame.new(c.X + x * (hw - 4), top + 0.02, c.Z),
			Vector3.new(1.2, 0.05, ex.Depth - 8),
			L.MarbleBlack
		)
	end
	for i = 0, 23 do
		local a = (i + 0.5) * 2 * math.pi / 24
		local pos = Vector3.new(c.X + 24 * math.cos(a), top + 0.03, c.Z + 24 * math.sin(a))
		neon(
			"FloorRing" .. i,
			CFrame.lookAt(pos, pos + Vector3.new(-math.sin(a), 0, math.cos(a))),
			Vector3.new(0.35, 0.05, 6.4),
			NEON.Accent
		)
	end

	-- Wände: Glas vorn (mit Eingang) und seitlich, Marmor hinten; Pfosten, Riegel, Neonband, Eckpfeiler
	local door = 15
	local doorH = 22
	part(
		"FrontGlassL",
		CFrame.new(-(door + (hw - door) / 2), top + H / 2, front),
		Vector3.new(hw - door, H, 0.6),
		L.Glass
	)
	part("FrontGlassR", CFrame.new(door + (hw - door) / 2, top + H / 2, front), Vector3.new(hw - door, H, 0.6), L.Glass)
	part(
		"FrontLintel",
		CFrame.new(0, top + doorH + (H - doorH) / 2, front),
		Vector3.new(door * 2, H - doorH, 0.6),
		L.Glass
	)
	part("SideGlassW", CFrame.new(-hw, top + H / 2, c.Z), Vector3.new(0.6, H, ex.Depth), L.Glass)
	part("SideGlassE", CFrame.new(hw, top + H / 2, c.Z), Vector3.new(0.6, H, ex.Depth), L.Glass)
	part("BackWall", CFrame.new(0, top + H / 2, back), Vector3.new(ex.Width, H, 2), L.MarbleWhite)
	for x = -hw + 15, hw - 15, 15 do
		if math.abs(x) < door then
			continue -- Eingang frei
		end
		part(
			"FrontMullion" .. x,
			CFrame.new(x, top + H / 2, front + 0.4),
			Vector3.new(1, H, 1.2),
			L.Metal,
			{ Shadow = false }
		)
	end
	for z = back + 14, front - 14, 14 do
		for _, side in ipairs({ -1, 1 }) do
			part(
				"SideMullion" .. side .. z,
				CFrame.new(side * (hw + 0.4), top + H / 2, z),
				Vector3.new(1.2, H, 1),
				L.Metal,
				{
					Shadow = false,
				}
			)
		end
	end
	for i, y in ipairs({ 24, 48 }) do
		part(
			"FrontTransom" .. i,
			CFrame.new(0, top + y, front + 0.5),
			Vector3.new(ex.Width, 0.8, 1),
			L.Metal,
			{ Shadow = false }
		)
		for _, side in ipairs({ -1, 1 }) do
			part(
				"SideTransom" .. side .. i,
				CFrame.new(side * (hw + 0.5), top + y, c.Z),
				Vector3.new(1, 0.8, ex.Depth),
				L.Metal,
				{
					Shadow = false,
				}
			)
		end
	end
	neon("TopBandF", CFrame.new(0, top + H - 1, front + 0.7), Vector3.new(ex.Width, 0.3, 0.3), NEON.Accent)
	neon("TopBandB", CFrame.new(0, top + H - 1, back - 1.1), Vector3.new(ex.Width, 0.3, 0.3), NEON.Accent)
	neon("TopBandW", CFrame.new(-hw - 0.7, top + H - 1, c.Z), Vector3.new(0.3, 0.3, ex.Depth), NEON.Accent)
	neon("TopBandE", CFrame.new(hw + 0.7, top + H - 1, c.Z), Vector3.new(0.3, 0.3, ex.Depth), NEON.Accent)
	for _, corner in ipairs({ Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) }) do
		local x = corner.X * (hw + 1)
		local z = if corner.Y > 0 then front + 1 else back - 1
		part("Pilaster" .. corner.X .. corner.Y, CFrame.new(x, top + H / 2, z), Vector3.new(4, H, 4), L.MarbleWhite)
	end
	part(
		"BasePlinth",
		CFrame.new(0, top + 0.75, front + 1),
		Vector3.new(ex.Width, 1.5, 1.4),
		L.Metal,
		{ Shadow = false }
	)

	-- Schild + Vordach + offene Glastüren
	sign(
		"ExchangeSign",
		CFrame.new(0, top + 28, front + 0.9) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(60, 6, 0.5),
		signName("Exchange", "AKYTEX EXCHANGE"),
		NEON.Letters
	)
	neon("ExchangeSignLine", CFrame.new(0, top + 24.8, front + 1), Vector3.new(60, 0.3, 0.3), NEON.Accent)
	part("Canopy", CFrame.new(0, top + doorH - 0.4, front + 6), Vector3.new(40, 0.8, 12), L.Metal)
	for _, side in ipairs({ -1, 1 }) do
		part(
			"CanopyPost" .. side,
			CFrame.new(side * 18, top + (doorH - 0.8) / 2, front + 11),
			Vector3.new(0.8, doorH - 0.8, 0.8),
			L.Steel
		)
		deco(
			"DoorLeaf" .. side,
			CFrame.new(side * (door - 1), top + 9, front - 4) * CFrame.Angles(0, side * math.rad(80), 0),
			Vector3.new(8, 18, 0.3),
			L.GlassClear
		)
	end

	-- Dach als Ring um die Kuppel-Öffnung (84 × 84) + Glasgeländer der Dachterrasse
	local roofY = top + H + 1
	local open = 42
	local roofD = hd - open
	part(
		"RoofFront",
		CFrame.new(0, roofY, front - roofD / 2),
		Vector3.new(ex.Width, 2, roofD),
		L.MarbleGrey,
		{ Shadow = true }
	)
	part("RoofBack", CFrame.new(0, roofY, back + roofD / 2), Vector3.new(ex.Width, 2, roofD), L.MarbleGrey)
	part(
		"RoofWest",
		CFrame.new(-(open + (hw - open) / 2), roofY, c.Z),
		Vector3.new(hw - open, 2, open * 2),
		L.MarbleGrey
	)
	part("RoofEast", CFrame.new(open + (hw - open) / 2, roofY, c.Z), Vector3.new(hw - open, 2, open * 2), L.MarbleGrey)
	local deckY = roofY + 1
	for i, def in ipairs({
		{ Vector3.new(0, deckY + 0.8, front - 0.4), Vector3.new(ex.Width, 1.6, 0.3) },
		{ Vector3.new(0, deckY + 0.8, back + 0.4), Vector3.new(ex.Width, 1.6, 0.3) },
		{ Vector3.new(-hw + 0.4, deckY + 0.8, c.Z), Vector3.new(0.3, 1.6, ex.Depth) },
		{ Vector3.new(hw - 0.4, deckY + 0.8, c.Z), Vector3.new(0.3, 1.6, ex.Depth) },
	}) do
		part("RoofRail" .. i, CFrame.new(def[1]), def[2], L.GlassClear, { Shadow = false })
		deco(
			"RoofRailTop" .. i,
			CFrame.new(def[1] + Vector3.new(0, 0.9, 0)),
			def[2] + Vector3.new(0.1, -1.45, 0.1),
			L.Steel
		)
	end

	-- facettierte Glaskuppel (16 Längen × 3 Ringe) mit Rippen, Fußring und Kappe
	local R = ex.DomeRadius
	local dc = Vector3.new(c.X, deckY, c.Z)
	local lon = 16
	local bands = { { 0, 30 }, { 30, 58 }, { 58, 80 } }
	for j = 0, lon - 1 do
		local lam = (j + 0.5) * 2 * math.pi / lon
		local lamB = (j + 1) * 2 * math.pi / lon
		local tangent = Vector3.new(-math.sin(lam), 0, math.cos(lam))
		for b, band in ipairs(bands) do
			local fa, fb = math.rad(band[1]), math.rad(band[2])
			local bottomMid = dc
				+ Vector3.new(
					R * math.cos(fa) * math.cos(lam) * math.cos(math.pi / lon),
					R * math.sin(fa),
					R * math.cos(fa) * math.sin(lam) * math.cos(math.pi / lon)
				)
			local topMid = dc
				+ Vector3.new(
					R * math.cos(fb) * math.cos(lam) * math.cos(math.pi / lon),
					R * math.sin(fb),
					R * math.cos(fb) * math.sin(lam) * math.cos(math.pi / lon)
				)
			local upDir = (topMid - bottomMid).Unit
			local width = 2 * R * math.cos(fa) * math.sin(math.pi / lon) + 0.3
			local height = (topMid - bottomMid).Magnitude + 0.3
			part(
				"DomeGlass" .. j .. "_" .. b,
				CFrame.fromMatrix((bottomMid + topMid) / 2, tangent, upDir),
				Vector3.new(width, height, 0.4),
				L.Glass,
				{
					Shadow = false,
				}
			)
			-- Rippe an der Kante
			local ra = dc
				+ Vector3.new(R * math.cos(fa) * math.cos(lamB), R * math.sin(fa), R * math.cos(fa) * math.sin(lamB))
			local rb = dc
				+ Vector3.new(R * math.cos(fb) * math.cos(lamB), R * math.sin(fb), R * math.cos(fb) * math.sin(lamB))
			deco(
				"DomeRib" .. j .. "_" .. b,
				CFrame.lookAt((ra + rb) / 2, rb),
				Vector3.new(0.6, 0.6, (rb - ra).Magnitude + 0.6),
				L.Metal
			)
		end
		local p0 = dc + Vector3.new(R * math.cos(lam - math.pi / lon), 0.4, R * math.sin(lam - math.pi / lon))
		local p1 = dc + Vector3.new(R * math.cos(lam + math.pi / lon), 0.4, R * math.sin(lam + math.pi / lon))
		part(
			"DomeFoot" .. j,
			CFrame.lookAt((p0 + p1) / 2, p1),
			Vector3.new(1.4, 0.8, (p1 - p0).Magnitude + 0.4),
			L.Metal
		)
	end
	local capR = R * math.cos(math.rad(80)) + 0.6
	local capY = deckY + R * math.sin(math.rad(80))
	disc("DomeCap", Vector3.new(c.X, capY + 0.2, c.Z), 0.8, capR, L.Metal)
	disc(
		"DomeCapRing",
		Vector3.new(c.X, capY + 0.7, c.Z),
		0.15,
		capR + 0.1,
		{ Mat = Enum.Material.Neon, Color = NEON.Accent },
		{
			Collide = false,
			Shadow = false,
		}
	)

	-- Säulen + Hallenlicht
	local hallLight = cfg.City.Lights.Hall
	for _, x in ipairs({ -60, 60 }) do
		for k, z in ipairs({ -145, -175, -205, -235 }) do
			disc("Column" .. x .. "_" .. k, Vector3.new(x, top + H / 2, z), H, 1.8, L.MarbleWhite, {
				Light = if k % 2 == 0 then lightSpec("Point", hallLight, false, nil) else nil,
			}).CFrame = CFrame.new(
				x,
				top + H / 2,
				z
			) * CFrame.Angles(0, 0, math.pi / 2)
		end
	end

	-- Börsenglocke auf dem Podium (Asset-Platz "Bell"), Gravur-Tafel
	local bellZ = back + 28
	disc("BellPodium1", Vector3.new(0, top + 0.7, bellZ), 1.4, 12, L.MarbleWhite)
	disc("BellPodium2", Vector3.new(0, top + 2.1, bellZ), 1.4, 8, L.MarbleWhite)
	local podiumTop = top + 2.8
	current.AssetCFrames.Bell = CFrame.new(0, podiumTop, bellZ)
	for _, side in ipairs({ -1, 1 }) do
		part(
			"BellPost" .. side,
			CFrame.new(side * 5, podiumTop + 6, bellZ),
			Vector3.new(1, 12, 1),
			L.Metal,
			{ Asset = "Bell" }
		)
	end
	part("BellBeam", CFrame.new(0, podiumTop + 12.4, bellZ), Vector3.new(12, 1.2, 1.2), L.Metal, { Asset = "Bell" })
	local bellAttrs = { Bell = true }
	deco(
		"BellBody",
		CFrame.new(0, podiumTop + 9.3, bellZ) * CFrame.Angles(0, 0, math.pi / 2),
		Vector3.new(4.2, 4.8, 4.8),
		L.Gold,
		{
			Shape = Enum.PartType.Cylinder,
			Sub = "Bell",
			SubAttrs = bellAttrs,
			Asset = "Bell",
			Shadow = true,
		}
	)
	deco(
		"BellLip",
		CFrame.new(0, podiumTop + 6.9, bellZ) * CFrame.Angles(0, 0, math.pi / 2),
		Vector3.new(1.1, 6.4, 6.4),
		L.Gold,
		{
			Shape = Enum.PartType.Cylinder,
			Sub = "Bell",
			Asset = "Bell",
		}
	)
	deco("BellCrown", CFrame.new(0, podiumTop + 11.6, bellZ), Vector3.new(3.2, 3.2, 3.2), L.Gold, {
		Shape = Enum.PartType.Ball,
		Sub = "Bell",
		Asset = "Bell",
	})
	deco("BellClapper", CFrame.new(0, podiumTop + 6.4, bellZ), Vector3.new(1.2, 1.2, 1.2), L.Metal, {
		Shape = Enum.PartType.Ball,
		Sub = "Bell",
		Asset = "Bell",
	})
	part("BellPlaque", CFrame.new(0, top + 1.2, bellZ + 13.2), Vector3.new(16, 1.8, 0.4), L.MarbleBlack, {
		Gui = {
			Face = Enum.NormalId.Back,
			Text = cfg.BellTagline or "CAPITAL BUILDS TOMORROW",
			Color = NEON.Gold,
			Display = true,
			MaxDistance = 120,
		},
	})
	anchor("Bell", CFrame.lookAt(Vector3.new(0, podiumTop, bellZ + 6), Vector3.new(0, podiumTop, bellZ)))

	-- IPO-Wand (Board) an der Rückwand
	local ipoCf = CFrame.lookAt(Vector3.new(0, top + 30, back + 1.3), Vector3.new(0, top + 30, back + 10))
	part(
		"IpoWall",
		ipoCf,
		Vector3.new(64, 18, 0.5),
		L.Plastic,
		{ Attrs = { Board = "IpoWall" }, Shadow = false, Priority = true }
	)
	neon("IpoWallTop", ipoCf * CFrame.new(0, 9.4, 0), Vector3.new(64.6, 0.3, 0.5), NEON.Cosmic2)
	neon("IpoWallBottom", ipoCf * CFrame.new(0, -9.4, 0), Vector3.new(64.6, 0.3, 0.5), NEON.Cosmic2)
	anchor("IpoWall", CFrame.lookAt(Vector3.new(0, top, back + 56), Vector3.new(0, top, back)))

	-- 360°-Tickerring (16 Segmente, Blick nach innen) an Stangen
	local tickerR = 50
	for j = 0, 15 do
		local a = (j + 0.5) * 2 * math.pi / 16
		local pos = Vector3.new(c.X + tickerR * math.cos(a), top + 42, c.Z + tickerR * math.sin(a))
		part(
			"TickerRing" .. j,
			CFrame.lookAt(pos, Vector3.new(c.X, pos.Y, c.Z)),
			Vector3.new(2 * tickerR * math.sin(math.pi / 16) + 0.2, 8, 0.6),
			L.Plastic,
			{
				Attrs = { Monitor = "TickerRing" },
				Collide = false,
				Shadow = false,
			}
		)
	end
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 16
		local pos = Vector3.new(
			c.X + (tickerR + 0.6) * math.cos(a),
			top + 46 + (H - 46) / 2,
			c.Z + (tickerR + 0.6) * math.sin(a)
		)
		deco("TickerRod" .. k, CFrame.new(pos), Vector3.new(0.3, H - 46, 0.3), L.Steel)
	end

	-- Heatmap-Wand (West) und 12er-Monitorwand (Ost)
	local wallZ = c.Z - 25
	local heatCf = CFrame.lookAt(Vector3.new(-hw + 1, top + 22, wallZ), Vector3.new(0, top + 22, wallZ))
	part(
		"HeatmapWall",
		heatCf,
		Vector3.new(36, 24, 0.5),
		L.Plastic,
		{ Attrs = { Monitor = "Heatmap" }, Collide = false, Shadow = false }
	)
	part("HeatmapFrame", heatCf * CFrame.new(0, 0, 0.4), Vector3.new(37.4, 25.4, 0.3), L.Metal, { Collide = false })
	local monitorIds = { 40, 1, 4, 7, 11, 13, 15, 19, 22, 25, 31, 33 }
	local monCf0 = CFrame.lookAt(Vector3.new(hw - 1, top + 19, wallZ), Vector3.new(0, top + 19, wallZ))
	part("MonitorWallBack", monCf0 * CFrame.new(0, 0, 0.45), Vector3.new(40, 18.5, 0.3), L.Metal, { Collide = false })
	for idx, instId in ipairs(monitorIds) do
		local col = (idx - 1) % 4
		local row = (idx - 1) // 4
		part(
			"WallMonitor" .. idx,
			monCf0 * CFrame.new((col - 1.5) * 9.6, (1 - row) * 5.8, 0),
			Vector3.new(9.2, 5.4, 0.3),
			L.Plastic,
			{
				Attrs = { Monitor = instId },
				Collide = false,
				Shadow = false,
			}
		)
	end

	-- 8 Terminal-Pulte (Prompt "Terminal", Hocker = Seat, Monitor "Chart")
	local pulpitIds = { 40, 2, 5, 9, 14, 19, 22, 31 }
	for k = 0, 7 do
		local deg = 22.5 + k * 45
		local a = math.rad(deg)
		local pos = Vector3.new(c.X + 26 * math.cos(a), top, c.Z + 26 * math.sin(a))
		local outward = Vector3.new(math.cos(a), 0, math.sin(a))
		local cf = CFrame.lookAt(pos, pos + outward)
		part("PulpitBase" .. k, cf * CFrame.new(0, 1.5, 0), Vector3.new(5, 3, 2.4), L.Metal, {
			Prompt = {
				TextKey = "world.prompt.terminal",
				ObjectKey = "world.object.terminal",
				Window = "Terminal",
				Distance = 9,
			},
		})
		part(
			"PulpitTop" .. k,
			cf * CFrame.new(0, 3.15, -0.2),
			Vector3.new(5.6, 0.3, 3),
			L.MarbleWhite,
			{ Shadow = false }
		)
		part(
			"PulpitScreen" .. k,
			cf * CFrame.new(0, 4.6, 0.6) * CFrame.Angles(math.rad(15), 0, 0),
			Vector3.new(4, 2.4, 0.25),
			L.Plastic,
			{
				Attrs = { Monitor = "Chart", Inst = pulpitIds[k + 1] },
				Collide = false,
				Shadow = false,
			}
		)
		neon("PulpitEdge" .. k, cf * CFrame.new(0, 3.32, -1.65), Vector3.new(5.6, 0.12, 0.15), NEON.Accent)
		part(
			"PulpitStool" .. k,
			cf * CFrame.new(0, 1.4, -3.2) * CFrame.Angles(0, math.pi, 0),
			Vector3.new(1.6, 0.4, 1.6),
			L.Fabric,
			{
				Class = "Seat",
				Shadow = false,
			}
		)
		deco("PulpitStoolPost" .. k, cf * CFrame.new(0, 0.6, -3.2), Vector3.new(0.4, 1.2, 0.4), L.Steel)
	end

	-- Mezzanine: VIP-Balkon (West, Tür nur lokal offen) und Akademie (Ost, 4 Lern-Kapseln)
	local mezzY = top + 20
	local mezzDepth = 16
	local mezzZ = front - 2 - mezzDepth / 2
	for _, def in ipairs({ { "Vip", -1 }, { "Academy", 1 } }) do
		local name, side = def[1] :: string, def[2] :: number
		local x0, x1 = side * 24, side * (hw - 3)
		local cx = (x0 + x1) / 2
		local width = math.abs(x1 - x0)
		part(
			name .. "Floor",
			CFrame.new(cx, mezzY - 0.5, mezzZ),
			Vector3.new(width, 1, mezzDepth),
			L.MarbleWhite,
			{ Priority = true }
		)
		local railEnd = side * (hw - 3 - 6.5) -- Lücke für die Rampe an der Seitenwand
		part(
			name .. "RailFront",
			CFrame.new((x0 + railEnd) / 2, mezzY + 1.6, mezzZ - mezzDepth / 2 + 0.2),
			Vector3.new(math.abs(railEnd - x0), 3.2, 0.3),
			L.GlassClear,
			{
				Shadow = false,
			}
		)
		part(
			name .. "RailInner",
			CFrame.new(x0, mezzY + 1.6, mezzZ),
			Vector3.new(0.3, 3.2, mezzDepth),
			L.GlassClear,
			{ Shadow = false }
		)
		deco(
			name .. "RailTop",
			CFrame.new(cx, mezzY + 3.25, mezzZ - mezzDepth / 2 + 0.2),
			Vector3.new(width, 0.2, 0.4),
			L.Steel
		)
		neon(
			name .. "Glow",
			CFrame.new(cx, mezzY - 1.05, mezzZ - mezzDepth / 2 + 0.3),
			Vector3.new(width, 0.12, 0.2),
			if side < 0 then NEON.Gold else NEON.Accent
		)
		for k = 0, 2 do
			part(
				name .. "Support" .. k,
				CFrame.new(x0 + (x1 - x0) * (k + 0.5) / 3, (top + mezzY - 1) / 2, mezzZ - mezzDepth / 2 + 1),
				Vector3.new(1, mezzY - 1 - top, 1),
				L.Steel
			)
		end
		-- Rampe entlang der Seitenwand (von hinten nach vorn steigend)
		local rampX = side * (hw - 4.5)
		local rampZ0, rampZ1 = front - 2 - mezzDepth, front - 2 - mezzDepth - 56
		local rampLen = math.sqrt((rampZ0 - rampZ1) ^ 2 + (mezzY - top) ^ 2)
		local rampMid = Vector3.new(rampX, (top + mezzY) / 2 - 0.5, (rampZ0 + rampZ1) / 2)
		part(
			name .. "Ramp",
			CFrame.lookAt(rampMid, rampMid + Vector3.new(0, mezzY - top, rampZ0 - rampZ1)),
			Vector3.new(6, 1, rampLen),
			L.MarbleGrey
		)
		part(
			name .. "RampRail",
			CFrame.lookAt(
				rampMid + Vector3.new(-side * 3.1, 1.6, 0),
				rampMid + Vector3.new(-side * 3.1, 1.6, 0) + Vector3.new(0, mezzY - top, rampZ0 - rampZ1)
			),
			Vector3.new(0.3, 3.2, rampLen),
			L.GlassClear,
			{
				Shadow = false,
			}
		)
		if name == "Vip" then
			part("VipDoor", CFrame.new(rampX, mezzY + 4, rampZ0 - 0.6), Vector3.new(6, 8, 0.4), L.GlassDark, {
				Attrs = { LocalDoor = "Vip" },
				Shadow = false,
			})
			neon("VipDoorFrame", CFrame.new(rampX, mezzY + 8.2, rampZ0 - 0.6), Vector3.new(6.4, 0.25, 0.5), NEON.Gold)
			anchor("VipBalcony", CFrame.lookAt(Vector3.new(cx, mezzY, mezzZ), Vector3.new(cx, mezzY, mezzZ - 10)))
		else
			sign(
				"AcademySign",
				CFrame.new(cx, mezzY + 4.8, mezzZ - mezzDepth / 2 - 0.2),
				Vector3.new(26, 2.8, 0.3),
				signName("Academy", "AKADEMIE"),
				NEON.Letters
			)
			for k = 0, 3 do
				local px = x0 + side * (6 + k * (width - 12) / 3)
				local capPos = Vector3.new(px, mezzY, mezzZ + 2)
				disc("CapsuleBase" .. k, capPos + Vector3.new(0, 0.2, 0), 0.4, 2.8, L.Metal, {
					Prompt = {
						TextKey = "world.prompt.academy",
						ObjectKey = "world.object.academy",
						Window = "Academy",
						Distance = 8,
					},
				})
				deco(
					"CapsuleGlass" .. k,
					CFrame.new(capPos + Vector3.new(0, 4.4, 0)) * CFrame.Angles(0, 0, math.pi / 2),
					Vector3.new(8, 5.2, 5.2),
					L.GlassClear,
					{
						Shape = Enum.PartType.Cylinder,
					}
				)
				neon(
					"CapsuleRing" .. k,
					CFrame.new(capPos + Vector3.new(0, 8.5, 0)) * CFrame.Angles(0, 0, math.pi / 2),
					Vector3.new(0.15, 5.4, 5.4),
					NEON.Accent,
					{
						Shape = Enum.PartType.Cylinder,
					}
				)
			end
			anchor("Academy", CFrame.lookAt(Vector3.new(cx, mezzY, mezzZ - 3), Vector3.new(cx, mezzY, mezzZ + 6)))
		end
	end

	-- Bestenlisten im Saal (Ø-Tagesrendite, Firmenwert) neben dem Podium
	for _, def in ipairs({ { "Return", -40 }, { "Firm", 40 } }) do
		local name, x = def[1] :: string, def[2] :: number
		local pos = Vector3.new(x, top, back + 14)
		local cf = CFrame.lookAt(pos + Vector3.new(0, 9, 0), pos + Vector3.new(0, 9, 10))
		part(
			"Board" .. name,
			cf,
			Vector3.new(12, 16, 0.4),
			L.Plastic,
			{ Attrs = { Board = name }, Shadow = false, Priority = true }
		)
		neon("Board" .. name .. "Glow", cf * CFrame.new(0, -8.3, 0), Vector3.new(12.4, 0.3, 0.5), NEON.Accent)
	end

	-- Club-Lift (hinten Ost) -> Dachterrasse; Rückweg-Pad auf dem Dach
	local liftPos = Vector3.new(hw - 12, top, back + 12)
	disc("ClubLiftPad", liftPos + Vector3.new(0, 0.15, 0), 0.3, 3.4, L.Metal, {
		Prompt = { TextKey = "world.prompt.clubUp", ObjectKey = "world.object.club", Action = "ClubUp", Distance = 8 },
	})
	deco(
		"ClubLiftTube",
		CFrame.new(liftPos + Vector3.new(0, 5, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Vector3.new(10, 7.4, 7.4),
		L.GlassClear,
		{
			Shape = Enum.PartType.Cylinder,
		}
	)
	neon(
		"ClubLiftRing",
		CFrame.new(liftPos + Vector3.new(0, 10.1, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Vector3.new(0.2, 7.6, 7.6),
		NEON.Cosmic2,
		{
			Shape = Enum.PartType.Cylinder,
		}
	)
	local roofFrontZ = front - roofD / 2
	disc("ClubReturnPad", Vector3.new(hw - 16, deckY + 0.15, roofFrontZ), 0.3, 3.4, L.Metal, {
		Prompt = {
			TextKey = "world.prompt.clubDown",
			ObjectKey = "world.object.club",
			Action = "ClubDown",
			Distance = 8,
		},
	})
	anchor("Rooftop", CFrame.lookAt(Vector3.new(0, deckY, roofFrontZ), Vector3.new(0, deckY, roofFrontZ + 10)))
	-- Lounge auf dem Dach (Sofas, Tische, Pflanzen – Smoothie-Bar-frei, jugendfrei)
	for k, x in ipairs({ -60, -30, 30, 60 }) do
		local p = Vector3.new(x, deckY, roofFrontZ + 4)
		part("RoofSofa" .. k, CFrame.new(p + Vector3.new(0, 0.8, 0)), Vector3.new(8, 1.6, 3), L.Fabric)
		deco("RoofSofaBack" .. k, CFrame.new(p + Vector3.new(0, 2, 1.3)), Vector3.new(8, 2, 0.6), L.Fabric)
		disc("RoofTable" .. k, p + Vector3.new(0, 0.9, -4), 1.8, 2.2, L.MarbleWhite)
	end
	for k, x in ipairs({ -80, 80 }) do
		planter("RoofPlanter" .. k, Vector3.new(x, deckY, roofFrontZ))
	end

	-- Pflanzen am Eingang (innen) + Monitor am Empfang
	for k, x in ipairs({ -26, 26 }) do
		planter("HallPlanter" .. k, Vector3.new(x, top, front - 8))
	end
end

-- 5.3 RING-BOULEVARD (Persistent) mit Ausweichbogen um den Börsensaal, Laternen, Ampeln, Zebrastreifen
local function buildRing()
	local roads = cfg.City.Roads
	local levels = cfg.City.Levels
	group("Ring", "Ring", "Persistent", false)
	local points = cfg.City.RoutePoints("Ring")
	local zebraDone: { [number]: boolean } = {}
	road(points, {
		Width = roads.Ring.Width,
		Thickness = levels.RoadThickness,
		Top = levels.Road,
		Look = L.Asphalt,
		Overlap = 1.6,
		Center = "Solid",
		Lanes = { -7.5, 7.5 },
		Walks = true,
		LampEvery = 3,
		LampSide = 0,
		Prefix = "Ring",
		Extra = function(_i: number, cf: CFrame, len: number, p0: Vector3, p1: Vector3)
			local mid = (p0 + p1) / 2
			local deg = math.deg(math.atan2(mid.Z, mid.X)) % 360
			for _, target in ipairs({ 0, 90, 180 }) do
				local diff = math.abs(((deg - target + 180) % 360) - 180)
				if diff < (len / roads.Ring.Radius) * 90 / math.pi and not zebraDone[target] then
					zebraDone[target] = true
					for k = -3, 2 do
						deco(
							"Zebra" .. target .. "_" .. k,
							cf * CFrame.new(k * 4.6 + 2.3, levels.RoadThickness / 2 + 0.04, 0),
							Vector3.new(2.6, 0.06, 12),
							L.Line
						)
					end
				end
			end
		end,
	})
	-- optische Ampeln an den Avenue-Einmündungen (Ost/West)
	for _, deg in ipairs(roads.Avenues) do
		for _, side in ipairs({ -1, 1 }) do
			local r = cfg.City.RoadRadius("Ring", deg, 0)
			local tangentDeg = deg + side * 5
			local pos = polar(r + roads.Ring.Width / 2 + 3, tangentDeg, levels.Walk)
			local face = CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0))
			local name = "Signal" .. deg .. "_" .. side
			deco(
				name .. "Pole",
				CFrame.new(pos + Vector3.new(0, 5, 0)),
				Vector3.new(0.5, 10, 0.5),
				L.Metal,
				{ Collide = true }
			)
			deco(name .. "Box", face * CFrame.new(0, 10.8, 0), Vector3.new(1.2, 3.4, 1), L.Metal)
			-- Attribut Signal = Lampe, SignalGroup = Einmündung: CityLife schaltet die Phasen lokal (Server-Zeit-synchron)
			neon(name .. "Red", face * CFrame.new(0, 11.8, -0.55), Vector3.new(0.7, 0.7, 0.1), rgb(90, 30, 30), {
				Attrs = { Signal = "Red", SignalGroup = deg },
			})
			neon(name .. "Amber", face * CFrame.new(0, 10.8, -0.55), Vector3.new(0.7, 0.7, 0.1), rgb(90, 70, 20), {
				Attrs = { Signal = "Amber", SignalGroup = deg },
			})
			neon(name .. "Green", face * CFrame.new(0, 9.8, -0.55), Vector3.new(0.7, 0.7, 0.1), NEON.Up, {
				Attrs = { Signal = "Green", SignalGroup = deg },
			})
		end
	end
end

-- 5.4 ÄUSSERER RING (Persistent) R 560
local function buildOuter()
	local roads = cfg.City.Roads
	local levels = cfg.City.Levels
	group("Outer", "Outer", "Persistent", false)
	road(cfg.City.RoutePoints("Outer"), {
		Width = roads.Outer.Width,
		Thickness = levels.RoadThickness,
		Top = levels.Road,
		Look = L.Asphalt,
		Overlap = 1.8,
		Center = "Dash",
		Curbs = true,
		LampEvery = 3,
		LampSide = 1,
		Prefix = "Outer",
	})
end

-- 5.5 AVENUEN (Ost/West) + Plot-Einfahrten werden je Plot gebaut
local function buildAvenues()
	local roads = cfg.City.Roads
	local levels = cfg.City.Levels
	group("Avenues", "Avenues", "Atomic", false)
	local outerIn = roads.Outer.Radius - roads.Outer.Width / 2
	local outerOut = roads.Outer.Radius + roads.Outer.Width / 2
	for _, deg in ipairs(roads.Avenues) do
		local ringOut = cfg.City.RoadRadius("Ring", deg, 0) + roads.Ring.Width / 2
		local finish = if deg == 0 then 712 else 662
		straight(
			"Avenue" .. deg .. "A",
			polar(ringOut, deg, levels.Road),
			polar(outerIn, deg, levels.Road),
			roads.AvenueWidth,
			L.Asphalt,
			levels.Road,
			true,
			"Solid"
		)
		straight(
			"Avenue" .. deg .. "B",
			polar(outerOut, deg, levels.Road),
			polar(finish, deg, levels.Road),
			roads.AvenueWidth,
			L.Asphalt,
			levels.Road,
			true,
			"Solid"
		)
		for k = 1, 6 do
			local r = ringOut + k * (outerIn - ringOut) / 7
			for _, side in ipairs({ -1, 1 }) do
				local pos = polar(r, deg, 0)
					+ (CFrame.lookAt(Vector3.zero, polar(1, deg, 0))).RightVector
						* side
						* (roads.AvenueWidth / 2 + 4)
				lantern(
					"AvenueLamp" .. deg .. "_" .. k .. "_" .. side,
					Vector3.new(pos.X, levels.Walk, pos.Z),
					-side * (CFrame.lookAt(Vector3.zero, polar(1, deg, 0))).RightVector
				)
			end
		end
	end
end

-- 5.6 PLOT-SEITEN (10 × 110 × 110, Atomic + LOD) mit Einfahrt zum Ring-Boulevard
local function buildPlots()
	local plots = cfg.City.Plots
	local roads = cfg.City.Roads
	local levels = cfg.City.Levels
	for k = 1, plots.Count do
		group("Plot" .. k, "Plots", "Atomic", cfg.City.Streaming.MeshLod.Plots == true)
		local cf = cfg.City.PlotCFrame(k)
		table.insert(plan.PlotSites, cf)
		local half = plots.Size / 2
		part("PlotPad" .. k, cf * CFrame.new(0, -0.6, 0), Vector3.new(plots.Size, 1.2, plots.Size), L.Pavement, {
			Attrs = { Plot = k },
			Priority = true,
			Shadow = false,
		})
		for e, def in ipairs({
			{ CFrame.new(0, 0.03, -half + 0.2), Vector3.new(plots.Size, 0.06, 0.3) },
			{ CFrame.new(0, 0.03, half - 0.2), Vector3.new(plots.Size, 0.06, 0.3) },
			{ CFrame.new(-half + 0.2, 0.03, 0), Vector3.new(0.3, 0.06, plots.Size) },
			{ CFrame.new(half - 0.2, 0.03, 0), Vector3.new(0.3, 0.06, plots.Size) },
		}) do
			neon("PlotEdge" .. k .. "_" .. e, cf * def[1], def[2], NEON.Accent, { Transp = 0.15 })
		end
		deco("PlotForecourt" .. k, cf * CFrame.new(0, 0.02, -half + 14), Vector3.new(56, 0.05, 24), L.MarbleBlack)
		-- Einfahrt bis zum Ring-Boulevard
		local deg = plots.StartAngle + (k - 1) * plots.Step
		local ringOut = cfg.City.RoadRadius("Ring", deg, 0) + roads.Ring.Width / 2
		local a = polar(plots.Radius - half, deg, levels.Road)
		local b = polar(ringOut, deg, levels.Road)
		straight("PlotDrive" .. k, a, b, roads.Driveway, L.Asphalt, levels.Road, false, "Dash")
		for _, side in ipairs({ -1, 1 }) do
			tree(
				"PlotTree" .. k .. "_" .. side,
				(cf * CFrame.new(side * (half - 8), -levels.Walk, -half + 8)).Position,
				1.1
			)
			local lamp = (cf * CFrame.new(side * (roads.Driveway / 2 + 3), 0, -half - 6)).Position
			lantern(
				"PlotLamp" .. k .. "_" .. side,
				Vector3.new(lamp.X, levels.Road, lamp.Z),
				(cf * CFrame.new(-side * 10, 0, -half - 6)).Position - lamp
			)
		end
	end
end

-- 5.7 FIRMEN-LÄDEN (6) im Grüngürtel – Spot + Mini-Ticker bei aktiver News (Client)
local function shopProps(i: number, style: string, cf: CFrame, color: Color3)
	if style == "Diner" then
		part("Counter" .. i, cf * CFrame.new(0, 1.6, 6), Vector3.new(20, 3.2, 3), L.MarbleWhite)
		for k = -2, 2 do
			disc("Stool" .. i .. "_" .. k, (cf * CFrame.new(k * 4, 1.2, 3)).Position, 2.4, 0.9, L.Fabric)
		end
		neon("DinerSign" .. i, cf * CFrame.new(0, 9, 11.6), Vector3.new(14, 2, 0.2), color)
	elseif style == "Vending" then
		for k = -3, 3, 2 do
			part("Vending" .. i .. "_" .. k, cf * CFrame.new(k * 4.4, 3.5, 10), Vector3.new(3.6, 7, 3), L.Plastic)
			neon(
				"VendingFront" .. i .. "_" .. k,
				cf * CFrame.new(k * 4.4, 4.2, 8.45),
				Vector3.new(2.6, 4.6, 0.1),
				color
			)
		end
	elseif style == "Showroom" then
		part("ShowPlinth" .. i, cf * CFrame.new(0, 0.9, 1), Vector3.new(16, 0.6, 9), L.Showroom)
		local spec = part(
			"ShowCar" .. i,
			cf * CFrame.new(0, 1.2, 1) * CFrame.Angles(0, math.rad(-120), 0),
			Vector3.one,
			L.Plastic
		)
		spec.Car = "VelocitraS"
	elseif style == "Bank" then
		for k = -1, 1 do
			part("Atm" .. i .. "_" .. k, cf * CFrame.new(k * 6, 3, 11), Vector3.new(3.4, 6, 2), L.Steel)
			neon("AtmScreen" .. i .. "_" .. k, cf * CFrame.new(k * 6, 4.2, 9.95), Vector3.new(2.2, 1.6, 0.1), color)
		end
	elseif style == "Arcade" then
		for k = -3, 3, 2 do
			part("Cabinet" .. i .. "_" .. k, cf * CFrame.new(k * 4.4, 3.6, 10), Vector3.new(3.2, 7.2, 3), L.Plastic)
			neon(
				"CabinetScreen" .. i .. "_" .. k,
				cf * CFrame.new(k * 4.4, 4.6, 8.45) * CFrame.Angles(math.rad(10), 0, 0),
				Vector3.new(2.4, 2, 0.1),
				color
			)
			neon(
				"CabinetTop" .. i .. "_" .. k,
				cf * CFrame.new(k * 4.4, 6.8, 8.45),
				Vector3.new(2.8, 0.6, 0.1),
				NEON.Cosmic2
			)
		end
	elseif style == "Sneaker" then
		for k, x in ipairs({ -12, 12 }) do
			part("Shelf" .. i .. "_" .. k, cf * CFrame.new(x, 4, 10.5), Vector3.new(10, 8, 2), L.Wood)
			for b = 0, 2 do
				deco(
					"Box" .. i .. "_" .. k .. "_" .. b,
					cf * CFrame.new(x - 3 + b * 3, 2 + b * 2.2, 9.2),
					Vector3.new(2.2, 1.2, 1.4),
					{
						Mat = Enum.Material.SmoothPlastic,
						Color = if b == 1 then color else rgb(240, 242, 246),
					}
				)
			end
		end
	end
end

local function buildShops()
	local city = cfg.City
	local top = city.Levels.Walk
	local size = city.ShopSize
	local spot = city.Lights.Spot
	for _, site in ipairs(city.ShopSites) do
		local i = site.I
		group("Shop" .. i, "Shops", "Atomic", false)
		local base = city.ShopCFrame(i) :: CFrame
		local cf = base + Vector3.new(0, top, 0)
		local w, h, d = size.X, size.Y, size.Z
		local company = cfg.Companies and cfg.Companies.ById and cfg.Companies.ById[i] or nil
		local color = SECTOR_COLORS[company and company.Sector or "K"] or NEON.Accent
		part("ShopFloor" .. i, cf * CFrame.new(0, -0.3, 0), Vector3.new(w, 0.6, d), L.MarbleWhite, { Shadow = false })
		part("ShopBack" .. i, cf * CFrame.new(0, h / 2, d / 2 - 0.5), Vector3.new(w, h, 1), L.MarbleGrey)
		for _, side in ipairs({ -1, 1 }) do
			part(
				"ShopSide" .. i .. side,
				cf * CFrame.new(side * (w / 2 - 0.5), h / 2, 0),
				Vector3.new(1, h, d),
				L.MarbleGrey
			)
		end
		part("ShopRoof" .. i, cf * CFrame.new(0, h + 0.5, 0), Vector3.new(w + 2, 1, d + 2), L.Metal)
		local glassH = 14
		for _, side in ipairs({ -1, 1 }) do
			part(
				"ShopGlass" .. i .. side,
				cf * CFrame.new(side * (w / 4 + 2.5), glassH / 2, -d / 2 + 0.3),
				Vector3.new(w / 2 - 5, glassH, 0.3),
				L.Glass
			)
		end
		part(
			"ShopHeader" .. i,
			cf * CFrame.new(0, 10 + (glassH - 10) / 2, -d / 2 + 0.3),
			Vector3.new(10, glassH - 10, 0.3),
			L.Glass
		)
		local front = sign(
			"ShopFront" .. i,
			cf * CFrame.new(0, glassH + 2, -d / 2 + 0.2),
			Vector3.new(w, 4, 0.6),
			site.Name,
			color,
			{
				Attrs = { Shop = i },
				Priority = true,
			}
		)
		front.Name = "ShopFront" .. i
		plan.ShopFronts[i] = front.Name
		neon("ShopLine" .. i, cf * CFrame.new(0, glassH - 0.1, -d / 2 + 0.1), Vector3.new(w, 0.25, 0.3), color)
		deco(
			"ShopAwning" .. i,
			cf * CFrame.new(0, glassH - 1.2, -d / 2 - 2.2) * CFrame.Angles(math.rad(-14), 0, 0),
			Vector3.new(w - 2, 0.3, 4.6),
			L.Metal
		)
		part("ShopTicker" .. i, cf * CFrame.new(0, 7.2, -d / 2 - 0.4), Vector3.new(8, 4.5, 0.2), L.Plastic, {
			Collide = false,
			Transp = 1,
			Shadow = false,
			Attrs = { ShopTicker = i },
		})
		local spotPos = (cf * CFrame.new(0, h + 4, -d / 2 - 12)).Position
		local spotAim = (cf * CFrame.new(0, 8, -d / 2)).Position
		part("ShopSpot" .. i, CFrame.lookAt(spotPos, spotAim), Vector3.new(1, 1, 1), L.Metal, {
			Collide = false,
			Transp = 1,
			Shadow = false,
			Attrs = { ShopSpot = i },
			Light = {
				Kind = "Spot",
				Range = spot.Range,
				Brightness = spot.Brightness,
				Color = spot.Color,
				Angle = spot.Angle,
				Face = Enum.NormalId.Front,
			},
		})
		shopProps(i, site.Style, cf, color)
		local anchorName = city.Shops[i]
		if type(anchorName) == "string" then
			local foot = (cf * CFrame.new(0, 0, -d / 2 - 10)).Position
			anchor(
				anchorName,
				CFrame.lookAt(
					foot,
					(cf * CFrame.new(0, 0, 0)).Position * Vector3.new(1, 0, 1) + Vector3.new(0, foot.Y, 0)
				)
			)
		end
	end
end

-- 5.8 AUTOBAHNRING R 950 (Atomic-Blöcke) mit Tunnel (Nord), Brücke (Süd), Rampen, Drift-Kerbs
local function buildHighway()
	local roads = cfg.City.Roads
	local hw = roads.Highway
	local levels = cfg.City.Levels
	local marina = cfg.City.Zones.Marina
	local points = cfg.City.RoutePoints("Highway")
	local tunnelTop = hw.TunnelHeight or 22
	road(points, {
		Width = hw.Width,
		Thickness = 1.4,
		Top = levels.Road,
		Look = L.Asphalt,
		Overlap = 1.6,
		Center = "Barrier",
		Lanes = { -8, 8 },
		EdgeBarriers = true,
		LampEvery = 3,
		LampSide = -1,
		Prefix = "Highway",
		GroupEvery = 12,
		GroupFn = function(index: number)
			group("Highway" .. index, "Highway", "Atomic", false)
		end,
		Kerbs = function(midDeg: number): boolean
			for _, arc in ipairs(hw.DriftArcs) do
				if midDeg >= arc[1] and midDeg <= arc[2] then
					return true
				end
			end
			return false
		end,
		Extra = function(i: number, cf: CFrame, len: number, _p0: Vector3, _p1: Vector3)
			local pos = cf.Position
			local hill = CityLayout.HillHeight(pos.X, pos.Z)
			if hill > tunnelTop - 4 then
				-- Tunnel-Auskleidung
				for _, side in ipairs({ -1, 1 }) do
					part(
						"TunnelWall" .. i .. side,
						cf * CFrame.new(side * (hw.Width / 2 + 1), tunnelTop / 2, 0),
						Vector3.new(2, tunnelTop + 1.4, len),
						L.Concrete
					)
				end
				part(
					"TunnelRoof" .. i,
					cf * CFrame.new(0, tunnelTop + 1, 0),
					Vector3.new(hw.Width + 4, 2, len),
					L.Concrete
				)
				neon(
					"TunnelLight" .. i,
					cf * CFrame.new(0, tunnelTop - 0.1, 0),
					Vector3.new(1.2, 0.2, len * 0.8),
					NEON.Warm,
					{
						Light = lightSpec(
							"Surface",
							{ Range = 16, Brightness = 1.2, Color = NEON.Warm },
							false,
							{ Face = Enum.NormalId.Bottom }
						),
					}
				)
			end
			local inWater = math.abs(pos.X - marina.Center.X) < marina.Width / 2
				and math.abs(pos.Z - marina.Center.Z) < marina.Depth / 2
			if inWater then
				-- Brücke über die Marina: Pfeiler bis zum Grund
				for _, side in ipairs({ -1, 1 }) do
					disc(
						"BridgePier" .. i .. side,
						(cf * CFrame.new(side * (hw.Width / 2 - 4), -10.2, 0)).Position,
						19.6,
						1.6,
						L.Concrete
					)
				end
			end
		end,
	})
	-- Tunnel-Portale (Ein-/Ausfahrt am Hügelrand)
	group("HighwayPortals", "Highway", "Atomic", false)
	local portals = 0
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local ha = CityLayout.HillHeight(a.X, a.Z) > tunnelTop - 4
		local hb = CityLayout.HillHeight(b.X, b.Z) > tunnelTop - 4
		if ha ~= hb and portals < 2 then
			portals += 1
			local p = if ha then a else b
			local cf = CFrame.lookAt(Vector3.new(p.X, levels.Road, p.Z), Vector3.new(b.X, levels.Road, b.Z))
			part(
				"PortalArch" .. portals,
				cf * CFrame.new(0, tunnelTop + 3, 0),
				Vector3.new(hw.Width + 10, 6, 4),
				L.ConcreteLight
			)
			for _, side in ipairs({ -1, 1 }) do
				part(
					"PortalPost" .. portals .. side,
					cf * CFrame.new(side * (hw.Width / 2 + 3), tunnelTop / 2, 0),
					Vector3.new(4, tunnelTop + 1, 4),
					L.ConcreteLight
				)
			end
			neon(
				"PortalLine" .. portals,
				cf * CFrame.new(0, tunnelTop + 0.4, -2.1),
				Vector3.new(hw.Width, 0.3, 0.2),
				NEON.Accent
			)
		end
	end
	-- Rampen (Auf-/Abfahrten vom äußeren Ring)
	group("HighwayRamps", "Highway", "Atomic", false)
	for _, deg in ipairs(hw.Ramps) do
		local a = polar(roads.Outer.Radius + roads.Outer.Width / 2, deg, levels.Road)
		local b = polar(hw.Radius - hw.Width / 2, deg, levels.Road)
		straight("Ramp" .. deg, a, b, 24, L.Asphalt, levels.Road, false, "Dash")
		local mid = (a + b) / 2
		neon(
			"RampChevron" .. deg,
			CFrame.lookAt(mid + Vector3.new(0, 0.32, 0), b + Vector3.new(0, 0.32, 0)),
			Vector3.new(6, 0.06, 2),
			NEON.Accent
		)
	end
end

-- 5.9 Λ MOTORS (Autohaus West): Glas-Showroom, 12 Drehteller mit Ausstellungsautos, Enthüllungs-Drehteller, Tuning-Box
local function buildMotors()
	local z = cfg.City.Zones.Motors
	local top = cfg.City.Levels.Walk
	group("Motors", "Motors", "Atomic", false)
	local M = CFrame.lookAt(z.Center, z.Center + Vector3.new(1, 0, 0)) + Vector3.new(0, top, 0) -- vorn = Osten
	local W, D, H = z.Depth, z.Width, z.Height -- lokal: x = Breite (Welt-z), z = Tiefe (Welt-x)
	part("MotorsFloor", M * CFrame.new(0, -0.6, 0), Vector3.new(W, 1.2, D), L.Showroom, { Shadow = false })
	local apronPos = (M * CFrame.new(0, 0, -D / 2 - 15)).Position
	part(
		"MotorsApron",
		CFrame.new(apronPos.X, cfg.City.Levels.Road - 0.6, apronPos.Z),
		Vector3.new(30, 1.2, W),
		L.Pavement,
		{ Shadow = false }
	)
	local door = 10
	for _, side in ipairs({ -1, 1 }) do
		part(
			"MotorsFront" .. side,
			M * CFrame.new(side * (door + (W / 2 - door) / 2), H / 2, -D / 2),
			Vector3.new(W / 2 - door, H, 0.5),
			L.Glass
		)
		part("MotorsSide" .. side, M * CFrame.new(side * W / 2, H / 2, 0), Vector3.new(0.5, H, D), L.Glass)
	end
	part("MotorsHeader", M * CFrame.new(0, 16 + (H - 16) / 2, -D / 2), Vector3.new(door * 2, H - 16, 0.5), L.Glass)
	part("MotorsBack", M * CFrame.new(0, H / 2, D / 2), Vector3.new(W, H, 1.5), L.MarbleWhite)
	for x = -W / 2 + 16, W / 2 - 16, 16 do
		part(
			"MotorsMullionF" .. x,
			M * CFrame.new(x, H / 2, -D / 2 - 0.4),
			Vector3.new(0.8, H, 0.8),
			L.Metal,
			{ Shadow = false }
		)
	end
	for zz = -D / 2 + 16, D / 2 - 16, 16 do
		for _, side in ipairs({ -1, 1 }) do
			part(
				"MotorsMullionS" .. side .. zz,
				M * CFrame.new(side * (W / 2 + 0.4), H / 2, zz),
				Vector3.new(0.8, H, 0.8),
				L.Metal,
				{
					Shadow = false,
				}
			)
		end
	end
	part("MotorsRoof", M * CFrame.new(0, H + 0.6, 0), Vector3.new(W + 2, 1.2, D + 2), L.Metal, {
		Light = lightSpec(
			"Surface",
			{ Range = 30, Brightness = 1.2, Color = rgb(240, 244, 255) },
			false,
			{ Face = Enum.NormalId.Bottom }
		),
	})
	neon("MotorsBandF", M * CFrame.new(0, H - 0.6, -D / 2 - 0.6), Vector3.new(W, 0.3, 0.3), NEON.Accent)
	neon("MotorsBandB", M * CFrame.new(0, H - 0.6, D / 2 + 0.9), Vector3.new(W, 0.3, 0.3), NEON.Accent)
	for _, side in ipairs({ -1, 1 }) do
		neon(
			"MotorsBandS" .. side,
			M * CFrame.new(side * (W / 2 + 0.6), H - 0.6, 0),
			Vector3.new(0.3, 0.3, D),
			NEON.Accent
		)
	end
	sign(
		"MotorsSign",
		M * CFrame.new(0, 20.5, -D / 2 - 0.6),
		Vector3.new(50, 6, 0.5),
		signName("Motors", "Λ MOTORS"),
		NEON.Letters
	)
	-- 12 Drehteller (2 Reihen × 6) mit Ausstellungsautos; jeder Drehteller ist ein Unter-Model mit Spin
	local display: { string } = {}
	for _, car in ipairs(cfg.Vehicles.Cars or {}) do
		if car.Display then
			table.insert(display, car.Key)
		end
	end
	local slots = math.min(z.Turntables, #display)
	for k = 1, slots do
		local row = if k <= 6 then -1 else 1
		local col = (k - 1) % 6
		local p = M * CFrame.new(row * 24, 0, -60 + col * 20)
		local sub = "Turntable" .. k
		disc("TurnDisc" .. k, p.Position + Vector3.new(0, 0.3, 0), 0.6, 7.5, L.MarbleBlack, {
			Sub = sub,
			SubAttrs = { Spin = 10 + (k % 3) * 2 },
		})
		disc(
			"TurnRing" .. k,
			p.Position + Vector3.new(0, 0.62, 0),
			0.06,
			7.6,
			{ Mat = Enum.Material.Neon, Color = NEON.Ring },
			{
				Sub = sub,
				Collide = false,
				Shadow = false,
			}
		)
		local spec = part(
			"DisplayCar" .. k,
			CFrame.new(p.Position + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, math.rad(k * 30), 0),
			Vector3.one,
			L.Plastic,
			{
				Sub = sub,
			}
		)
		spec.Car = display[k]
	end
	-- Empfang mit Prompt "Autohaus" + VLCT-Monitor
	part("MotorsDesk", M * CFrame.new(0, 1.6, -D / 2 + 14), Vector3.new(14, 3.2, 3), L.MarbleWhite, {
		Prompt = {
			TextKey = "world.prompt.garage",
			ObjectKey = "world.object.motors",
			Window = "Garage",
			Distance = 12,
		},
	})
	part("MotorsMonitor", M * CFrame.new(0, 6.4, -D / 2 + 15.6), Vector3.new(8, 4.5, 0.3), L.Plastic, {
		Attrs = { Monitor = 15 },
		Collide = false,
		Shadow = false,
	})
	-- Tuning-Box (hinten rechts)
	local box = M * CFrame.new(W / 2 - 14, 0, D / 2 - 16)
	for _, def in ipairs({
		{ CFrame.new(-8, 6, 0), Vector3.new(0.4, 12, 18) },
		{ CFrame.new(8, 6, 0), Vector3.new(0.4, 12, 18) },
		{ CFrame.new(0, 6, 9), Vector3.new(16, 12, 0.4) },
	}) do
		part("TuneWall" .. def[1].X .. def[1].Z, box * def[1], def[2], L.GlassClear, { Shadow = false })
	end
	part("TuneRoof", box * CFrame.new(0, 12.2, 0), Vector3.new(16.4, 0.4, 18.4), L.Metal)
	neon("TuneFrame", box * CFrame.new(0, 11.8, -9), Vector3.new(16, 0.3, 0.3), NEON.Cosmic2)
	part("TuneConsole", box * CFrame.new(5, 1.8, 6), Vector3.new(4, 3.6, 2), L.Metal, {
		Prompt = {
			TextKey = "world.prompt.tuning",
			ObjectKey = "world.object.tuning",
			Window = "Garage",
			Tab = "Tune",
			Distance = 10,
		},
	})
	-- Enthüllungs-Drehteller auf dem Vorplatz + Probefahrt-Start
	local hero = Vector3.new(z.Center.X + D / 2 + 12, top, z.Center.Z - 34)
	disc(
		"HeroDisc",
		hero + Vector3.new(0, 0.3, 0),
		0.6,
		9,
		L.MarbleBlack,
		{ Sub = "HeroTurntable", SubAttrs = { Spin = 8 } }
	)
	disc("HeroRing", hero + Vector3.new(0, 0.62, 0), 0.08, 9.2, { Mat = Enum.Material.Neon, Color = NEON.Cosmic2 }, {
		Sub = "HeroTurntable",
		Collide = false,
		Shadow = false,
	})
	part("HeroSpot", CFrame.lookAt(hero + Vector3.new(0, 18, 10), hero), Vector3.one, L.Metal, {
		Collide = false,
		Transp = 1,
		Shadow = false,
		Light = {
			Kind = "Spot",
			Range = 30,
			Brightness = 3,
			Color = rgb(255, 244, 230),
			Angle = 45,
			Face = Enum.NormalId.Front,
		},
	})
	anchor("Showroom", CFrame.lookAt(hero + Vector3.new(20, 0, 0), hero))
	local pad = cfg.Vehicles.SpawnPoints and cfg.Vehicles.SpawnPoints[2] or nil
	if pad and typeof(pad.Position) == "Vector3" then
		for k = 0, 2 do
			neon(
				"TestDriveChevron" .. k,
				CFrame.lookAt(
					pad.Position + Vector3.new(k * 4, 0.33, 0),
					pad.Position + Vector3.new(k * 4 + 1, 0.33, 0)
				),
				Vector3.new(6, 0.06, 1.2),
				NEON.Accent
			)
		end
	end
end

-- 5.10 CHRONOHAUS (Luxus-Boutique): Vitrinen mit drehenden Uhren, Spiegelwand, Accessoires, Deko-Ecke
local function buildChrono()
	local z = cfg.City.Zones.Chrono
	local top = cfg.City.Levels.Walk
	group("Chrono", "Chrono", "Atomic", false)
	local M = CFrame.lookAt(z.Center, z.Center + Vector3.new(1, 0, 0)) + Vector3.new(0, top, 0)
	local W, D, H = z.Depth, z.Width, z.Height
	part("ChronoFloor", M * CFrame.new(0, -0.6, 0), Vector3.new(W, 1.2, D), L.MarbleBlack, { Shadow = false })
	local door = 6
	for _, side in ipairs({ -1, 1 }) do
		part(
			"ChronoFront" .. side,
			M * CFrame.new(side * (door + (W / 2 - door) / 2), H / 2, -D / 2),
			Vector3.new(W / 2 - door, H, 0.5),
			L.Glass
		)
		part("ChronoSide" .. side, M * CFrame.new(side * W / 2, H / 2, 0), Vector3.new(1, H, D), L.MarbleWhite)
	end
	part("ChronoHeader", M * CFrame.new(0, 12 + (H - 12) / 2, -D / 2), Vector3.new(door * 2, H - 12, 0.5), L.Glass)
	part("ChronoMirror", M * CFrame.new(0, H / 2, D / 2), Vector3.new(W, H, 1), L.Mirror)
	part("ChronoRoof", M * CFrame.new(0, H + 0.5, 0), Vector3.new(W + 2, 1, D + 2), L.Metal, {
		Light = lightSpec(
			"Surface",
			{ Range = 24, Brightness = 1, Color = rgb(255, 240, 220) },
			false,
			{ Face = Enum.NormalId.Bottom }
		),
	})
	neon("ChronoBand", M * CFrame.new(0, H - 0.6, -D / 2 - 0.4), Vector3.new(W, 0.3, 0.3), NEON.Cosmic2)
	sign(
		"ChronoSign",
		M * CFrame.new(0, 16.5, -D / 2 - 0.5),
		Vector3.new(36, 4.5, 0.5),
		signName("Chrono", "CHRONOHAUS"),
		NEON.Letters
	)
	for k = 0, z.Vitrines - 1 do
		local row = if k < 4 then -1 else 1
		local col = k % 4
		local p = M * CFrame.new(row * 12, 0, -24 + col * 14)
		part("VitrinePlinth" .. k, p * CFrame.new(0, 1.8, 0), Vector3.new(3.2, 3.6, 3.2), L.MarbleWhite)
		deco("VitrineGlass" .. k, p * CFrame.new(0, 5.2, 0), Vector3.new(3, 3.2, 3), L.GlassClear, { Collide = true })
		local sub = "Watch" .. k
		deco(
			"WatchCase" .. k,
			p * CFrame.new(0, 5.2, 0) * CFrame.Angles(0, math.rad(90), 0),
			Vector3.new(0.35, 1.7, 1.7),
			L.Steel,
			{
				Shape = Enum.PartType.Cylinder,
				Sub = sub,
				SubAttrs = { Spin = 30 },
			}
		)
		neon(
			"WatchDial" .. k,
			p * CFrame.new(0, 5.2, -0.19) * CFrame.Angles(0, math.rad(90), 0),
			Vector3.new(0.05, 1.3, 1.3),
			if k % 2 == 0 then NEON.Accent else NEON.Cosmic2,
			{
				Shape = Enum.PartType.Cylinder,
				Sub = sub,
			}
		)
	end
	for k, x in ipairs({ -W / 2 + 1.5, W / 2 - 1.5 }) do
		part("AccShelf" .. k, M * CFrame.new(x, 4, 18), Vector3.new(2, 8, 14), L.Wood)
		for b = 0, 2 do
			deco(
				"AccItem" .. k .. "_" .. b,
				M * CFrame.new(x - k * 0.1, 3 + b * 2.3, 13 + b * 4.5),
				Vector3.new(1.4, 0.6, 1.6),
				L.Metal
			)
		end
	end
	part("DecoSofa", M * CFrame.new(-W / 2 + 8, 1, D / 2 - 6), Vector3.new(10, 2, 4), L.Fabric)
	deco("DecoSofaBack", M * CFrame.new(-W / 2 + 8, 2.6, D / 2 - 4.4), Vector3.new(10, 2.2, 0.8), L.Fabric)
	deco(
		"DecoRug",
		M * CFrame.new(-W / 2 + 8, 0.03, D / 2 - 12),
		Vector3.new(12, 0.05, 8),
		{ Mat = Enum.Material.Fabric, Color = NEON.Cosmic }
	)
	planter("DecoPlant", (M * CFrame.new(-W / 2 + 18, 0, D / 2 - 6)).Position)
	part("ChronoCounter", M * CFrame.new(0, 1.6, D / 2 - 8), Vector3.new(14, 3.2, 3), L.MarbleWhite, {
		Prompt = {
			TextKey = "world.prompt.boutique",
			ObjectKey = "world.object.chrono",
			Window = "Boutique",
			Distance = 12,
		},
	})
	part("ChronoEntrance", M * CFrame.new(0, 1.2, -D / 2 - 2.6), Vector3.new(3, 2.4, 1.2), L.Metal, {
		Prompt = {
			TextKey = "world.prompt.boutique",
			ObjectKey = "world.object.chrono",
			Window = "Boutique",
			Distance = 10,
		},
	})
	local foot = (M * CFrame.new(0, 0, -D / 2 - 8)).Position
	anchor("Boutique", CFrame.lookAt(foot, z.Center + Vector3.new(0, foot.Y, 0)))
end

-- 5.11 MARINA SÜD: Promenade, Geländer, 6 Liegeplätze, Deko-Yachten, Leuchtturm, Fotospot
local function buildMarina()
	local m = cfg.City.Zones.Marina
	local top = cfg.City.Levels.Walk
	local north = m.Center.Z - m.Depth / 2 -- 630
	group("Marina", "Marina", "Atomic", false)
	part(
		"Promenade",
		CFrame.new(m.Center.X, top - 0.6, north - 20),
		Vector3.new(m.Width + 40, 1.2, 40),
		L.Pavement,
		{ Shadow = false }
	)
	part("QuayN", CFrame.new(m.Center.X, top - 3, north + 1), Vector3.new(m.Width, 7, 2), L.ConcreteLight)
	for _, side in ipairs({ -1, 1 }) do
		part(
			"QuaySide" .. side,
			CFrame.new(m.Center.X + side * (m.Width / 2 + 1), top - 3, m.Center.Z),
			Vector3.new(2, 7, m.Depth),
			L.ConcreteLight
		)
	end
	for k = 0, 29 do
		local x = m.Center.X - m.Width / 2 + 10 + k * (m.Width - 20) / 29
		deco(
			"RailPost" .. k,
			CFrame.new(x, top + 1.5, north - 1),
			Vector3.new(0.4, 3, 0.4),
			L.Steel,
			{ Collide = true }
		)
	end
	for k, xOffset in ipairs({ -m.Width / 4, m.Width / 4 }) do
		part(
			"RailTop" .. k,
			CFrame.new(m.Center.X + xOffset, top + 3, north - 1),
			Vector3.new(m.Width / 2, 0.25, 0.4),
			L.Steel,
			{ Shadow = false }
		)
	end
	for k = 0, 11 do
		local x = m.Center.X - m.Width / 2 + 25 + k * (m.Width - 50) / 11
		lantern("MarinaLamp" .. k, Vector3.new(x, top, north - 34), Vector3.new(0, 0, 1))
		if k % 2 == 0 then
			bench(
				"MarinaBench" .. k,
				CFrame.lookAt(Vector3.new(x + 10, top, north - 8), Vector3.new(x + 10, top, north + 10))
			)
		end
	end
	for k = 0, m.Berths - 1 do
		local x = m.Center.X - m.Width / 2 + 50 + k * (m.Width - 100) / (m.Berths - 1)
		part("Pier" .. k, CFrame.new(x, 0.2, north + 32), Vector3.new(6, 1, 60), L.Wood)
		for _, side in ipairs({ -1, 1 }) do
			disc("Bollard" .. k .. side, Vector3.new(x + side * 2.4, 1.2, north + 58), 1.2, 0.5, L.Metal)
		end
	end
	-- Deko-Yachten (Asset-Platz "Yacht")
	for k, berth in ipairs({ 1, 4 }) do
		local x = m.Center.X - m.Width / 2 + 50 + berth * (m.Width - 100) / (m.Berths - 1) + 13
		local base = CFrame.new(x, -1.2, north + 34)
		if k == 1 then
			current.AssetCFrames.Yacht = base
		end
		part("YachtHull" .. k, base * CFrame.new(0, 0, 4), Vector3.new(9, 3.6, 30), L.PlasticLight, { Asset = "Yacht" })
		part(
			"YachtBow" .. k,
			base * CFrame.new(0, 0, -16),
			Vector3.new(9, 3.6, 10),
			L.PlasticLight,
			{ Asset = "Yacht", Wedge = true }
		)
		part(
			"YachtCabin" .. k,
			base * CFrame.new(0, 3.2, 6),
			Vector3.new(6.6, 2.8, 14),
			L.PlasticLight,
			{ Asset = "Yacht" }
		)
		deco(
			"YachtGlass" .. k,
			base * CFrame.new(0, 3.4, 6),
			Vector3.new(6.8, 1.2, 12),
			L.GlassDark,
			{ Asset = "Yacht" }
		)
		neon(
			"YachtLine" .. k,
			base * CFrame.new(0, 1.2, 0),
			Vector3.new(9.1, 0.2, 38),
			NEON.Accent,
			{ Asset = "Yacht" }
		)
		deco("YachtMast" .. k, base * CFrame.new(0, 9, 2), Vector3.new(0.4, 10, 0.4), L.Steel, { Asset = "Yacht" })
	end
	-- Leuchtturm am Ostende (Asset-Platz "Lighthouse"); der Lichtkegel dreht sich clientseitig (Spin)
	local lh = Vector3.new(m.Center.X + m.Width / 2 - 18, 0, north + 20)
	current.AssetCFrames.Lighthouse = CFrame.new(lh)
	part(
		"LighthouseJetty",
		CFrame.new(lh + Vector3.new(0, 0.3, -6)),
		Vector3.new(10, 1.4, 30),
		L.ConcreteLight,
		{ Asset = "Lighthouse" }
	)
	disc("LighthouseBase", lh + Vector3.new(0, 6, 0), 12, 4, L.PlasticLight, { Asset = "Lighthouse" }).CFrame = CFrame.new(
		lh + Vector3.new(0, 6, 0)
	) * CFrame.Angles(0, 0, math.pi / 2)
	disc(
		"LighthouseMid",
		lh + Vector3.new(0, 17, 0),
		10,
		3.2,
		{ Mat = Enum.Material.SmoothPlastic, Color = NEON.Down },
		{
			Asset = "Lighthouse",
		}
	).CFrame = CFrame.new(
		lh + Vector3.new(0, 17, 0)
	) * CFrame.Angles(0, 0, math.pi / 2)
	disc("LighthouseRoom", lh + Vector3.new(0, 24, 0), 4, 2.8, L.GlassClear, { Asset = "Lighthouse" }).CFrame = CFrame.new(
		lh + Vector3.new(0, 24, 0)
	) * CFrame.Angles(0, 0, math.pi / 2)
	neon("LighthouseLamp", CFrame.new(lh + Vector3.new(0, 24, 0)), Vector3.new(1.6, 1.6, 1.6), NEON.Warm, {
		Shape = Enum.PartType.Ball,
		Asset = "Lighthouse",
		Sub = "LighthouseHead",
		SubAttrs = { Spin = 40, Beam = true },
		Light = lightSpec("Point", { Range = 40, Brightness = 2, Color = NEON.Warm }, true, nil),
	})
	-- Fotospot
	local photo = Vector3.new(m.Center.X, top, north - 14)
	disc("PhotoSpot", photo + Vector3.new(0, 0.03, 0), 0.06, 3, { Mat = Enum.Material.Neon, Color = NEON.Accent }, {
		Collide = false,
		Shadow = false,
	})
	anchor("Marina", CFrame.lookAt(photo, photo + Vector3.new(0, 0, 1)))
end

-- 5.12 VILLENHÜGEL NORD: Serpentine, Aussichtspunkt, 4 Deko-Villen
local function buildHill(serpentine: { Vector3 })
	local hill = cfg.City.Zones.Hill
	group("HillRoad", "Hill", "Atomic", false)
	for i = 1, #serpentine - 1 do
		local a, b = serpentine[i], serpentine[i + 1]
		local ta = a + Vector3.new(0, 0.1, 0)
		local tb = b + Vector3.new(0, 0.1, 0)
		local mid = (ta + tb) / 2
		local cf = CFrame.lookAt(mid - Vector3.new(0, 0.75, 0), tb - Vector3.new(0, 0.75, 0))
		local len = (tb - ta).Magnitude + 1.4
		part("Serpentine" .. i, cf, Vector3.new(22, 1.5, len), L.Asphalt, { Shadow = false })
		deco("SerpentineLine" .. i, cf * CFrame.new(0, 0.78, 0), Vector3.new(0.3, 0.06, len * 0.5), L.Line)
		for _, side in ipairs({ -1, 1 }) do
			part(
				"Guard" .. i .. side,
				cf * CFrame.new(side * 11.4, 1.2, 0),
				Vector3.new(0.6, 1.4, len),
				L.Steel,
				{ Shadow = false }
			)
		end
	end
	-- Aussichtspunkt
	group("Lookout", "Hill", "Atomic", false)
	local summit = serpentine[#serpentine]
	local deckTop = summit.Y + 0.6
	local deck = Vector3.new(summit.X - 10, deckTop, summit.Z - 4)
	disc("LookoutDeck", deck - Vector3.new(0, 0.5, 0), 1, 13, L.Wood)
	for k = 0, 9 do
		local a = (k + 0.5) * 2 * math.pi / 10
		local pos = deck + Vector3.new(12.6 * math.cos(a), 1.6, 12.6 * math.sin(a))
		if math.sin(a) > -0.3 then
			part(
				"LookoutRail" .. k,
				CFrame.lookAt(pos, pos + Vector3.new(-math.sin(a), 0, math.cos(a))),
				Vector3.new(0.3, 3.2, 8),
				L.GlassClear,
				{
					Shadow = false,
				}
			)
		end
	end
	part("Telescope", CFrame.new(deck + Vector3.new(0, 1.8, 9)), Vector3.new(0.6, 3.6, 0.6), L.Steel)
	deco(
		"TelescopeTube",
		CFrame.lookAt(deck + Vector3.new(0, 3.8, 9), deck + Vector3.new(0, 4.4, 20)),
		Vector3.new(0.8, 0.8, 3),
		L.Metal
	)
	bench("LookoutBench", CFrame.lookAt(deck + Vector3.new(-6, 0, 4), deck + Vector3.new(-6, 0, 20)))
	anchor("Lookout", CFrame.lookAt(deck + Vector3.new(0, 0, 4), Vector3.new(0, deckTop, 0)))
	-- Villen (Asset-Platz "Villa" – jede Villa ein eigenes Model)
	local spots = {
		Vector2.new(hill.Center.X + 112, hill.Center.Z),
		Vector2.new(hill.Center.X - 112, hill.Center.Z + 6),
		Vector2.new(hill.Center.X + 70, hill.Center.Z - 88),
		Vector2.new(hill.Center.X - 76, hill.Center.Z - 84),
	}
	for k = 1, math.min(hill.Villas, #spots) do
		group("Villa" .. k, "Hill", "Atomic", false)
		local s = spots[k]
		local h = CityLayout.HillHeight(s.X, s.Y)
		local base = CFrame.lookAt(Vector3.new(s.X, h + 1, s.Y), Vector3.new(0, h + 1, 0))
		if k == 1 then
			current.AssetCFrames.Villa = base
		end
		part(
			"VillaFoundation" .. k,
			base * CFrame.new(0, -6, 0),
			Vector3.new(34, 14, 28),
			L.ConcreteLight,
			{ Asset = "Villa" }
		)
		part(
			"VillaMain" .. k,
			base * CFrame.new(-3, 4.5, 2),
			Vector3.new(24, 8, 18),
			L.MarbleWhite,
			{ Asset = "Villa" }
		)
		part(
			"VillaUpper" .. k,
			base * CFrame.new(4, 11.5, -2),
			Vector3.new(20, 6, 14),
			L.MarbleWhite,
			{ Asset = "Villa" }
		)
		deco(
			"VillaGlass" .. k,
			base * CFrame.new(-3, 4.5, -7.1),
			Vector3.new(22, 5, 0.3),
			L.GlassDark,
			{ Asset = "Villa", Attrs = { WindowLight = 1 } }
		)
		deco(
			"VillaGlass2" .. k,
			base * CFrame.new(4, 11.5, -9.1),
			Vector3.new(18, 3.6, 0.3),
			L.GlassDark,
			{ Asset = "Villa", Attrs = { WindowLight = 2 } }
		)
		part("VillaRoof" .. k, base * CFrame.new(4, 14.8, -2), Vector3.new(22, 0.6, 16), L.Metal, { Asset = "Villa" })
		deco("VillaPool" .. k, base * CFrame.new(-4, 1.05, -11), Vector3.new(14, 0.2, 6), L.Water, { Asset = "Villa" })
		neon(
			"VillaLine" .. k,
			base * CFrame.new(4, 8.4, -9.2),
			Vector3.new(20, 0.2, 0.2),
			NEON.Accent,
			{ Asset = "Villa" }
		)
	end
end

-- 5.13 HELIPAD / LOGISTIK OST: 60-Stud-Turm mit Schnellreise, Hangar mit Deko-Jet
local function buildHelipad()
	local z = cfg.City.Zones.Helipad
	local c = z.Center
	local levels = cfg.City.Levels
	group("Helipad", "Helipad", "Atomic", false)
	part(
		"HeliApron",
		CFrame.new(c.X, levels.Road - 0.6, c.Z + 20),
		Vector3.new(140, 1.2, 150),
		L.Concrete,
		{ Shadow = false }
	)
	local towerH = z.TowerHeight
	disc("HeliTower", c + Vector3.new(0, towerH / 2, 0), towerH, 10, L.Concrete).CFrame = CFrame.new(
		c + Vector3.new(0, towerH / 2, 0)
	) * CFrame.Angles(0, 0, math.pi / 2)
	for k = 1, 3 do
		disc(
			"HeliTowerBand" .. k,
			c + Vector3.new(0, k * 15, 0),
			0.5,
			10.15,
			{ Mat = Enum.Material.Neon, Color = NEON.Accent },
			{
				Collide = false,
				Shadow = false,
			}
		)
	end
	local padTop = towerH + 1.5
	disc("HeliPad", c + Vector3.new(0, padTop - 0.75, 0), 1.5, z.PadRadius, L.MarbleGrey)
	for k, def in ipairs({
		{ CFrame.new(-4, 0, 0), Vector3.new(1.4, 0.06, 12) },
		{ CFrame.new(4, 0, 0), Vector3.new(1.4, 0.06, 12) },
		{ CFrame.new(0, 0, 0), Vector3.new(8, 0.06, 1.4) },
	}) do
		neon("HeliH" .. k, CFrame.new(c + Vector3.new(0, padTop + 0.03, 0)) * def[1], def[2], NEON.White)
	end
	for k = 0, 7 do
		local a = k * math.pi / 4
		neon(
			"HeliEdge" .. k,
			CFrame.new(c + Vector3.new((z.PadRadius - 1) * math.cos(a), padTop + 0.2, (z.PadRadius - 1) * math.sin(a))),
			Vector3.new(0.8, 0.4, 0.8),
			NEON.Warn
		)
		local railPos = c
			+ Vector3.new(
				(z.PadRadius - 0.3) * math.cos(a + math.pi / 8),
				padTop + 1.6,
				(z.PadRadius - 0.3) * math.sin(a + math.pi / 8)
			)
		part(
			"HeliRail" .. k,
			CFrame.lookAt(railPos, railPos + Vector3.new(-math.sin(a + math.pi / 8), 0, math.cos(a + math.pi / 8))),
			Vector3.new(0.3, 3.2, 2 * z.PadRadius * math.sin(math.pi / 8)),
			L.GlassClear,
			{
				Shadow = false,
			}
		)
	end
	-- Helikopter-Platzhalter (v1.1, Asset-Platz "Heli")
	current.AssetCFrames.Heli = CFrame.new(c + Vector3.new(6, padTop, -6))
	deco("HeliBody", CFrame.new(c + Vector3.new(6, padTop + 2.2, -6)), Vector3.new(4.4, 4.4, 4.4), L.PlasticLight, {
		Shape = Enum.PartType.Ball,
		Asset = "Heli",
		Collide = true,
	})
	deco(
		"HeliTail",
		CFrame.new(c + Vector3.new(6, padTop + 2.6, 0)),
		Vector3.new(0.8, 0.8, 9),
		L.PlasticLight,
		{ Asset = "Heli" }
	)
	deco(
		"HeliRotor",
		CFrame.new(c + Vector3.new(6, padTop + 4.7, -6)),
		Vector3.new(14, 0.15, 0.6),
		L.Metal,
		{ Asset = "Heli" }
	)
	-- Schnellreise: unten hoch, oben zur Plaza
	part("HeliLiftBase", CFrame.new(c + Vector3.new(-12, 1.2, 0)), Vector3.new(3, 2.4, 3), L.Metal, {
		Prompt = {
			TextKey = "world.prompt.helipadUp",
			ObjectKey = "world.object.helipad",
			Action = "HelipadUp",
			Distance = 10,
		},
	})
	disc(
		"HeliFlyPad",
		c + Vector3.new(-12, padTop + 0.15, 0),
		0.3,
		3,
		{ Mat = Enum.Material.Neon, Color = NEON.Accent },
		{
			Prompt = {
				TextKey = "world.prompt.helipadFly",
				ObjectKey = "world.object.helipad",
				Action = "HelipadFly",
				Distance = 10,
			},
			Collide = false,
		}
	)
	sign(
		"HeliSign",
		CFrame.lookAt(c + Vector3.new(-10.2, 40, 0), c + Vector3.new(-30, 40, 0)),
		Vector3.new(14, 3, 0.3),
		signName("Heliport", "HELIPORT"),
		NEON.Letters
	)
	anchor("Helipad", CFrame.lookAt(c + Vector3.new(-6, padTop, 0), Vector3.new(0, padTop, 0)))
	-- Hangar mit Deko-Jet (Asset-Platz "Jet")
	group("Hangar", "Helipad", "Atomic", false)
	local hg = CFrame.lookAt(c + Vector3.new(40, 0, 80), c + Vector3.new(40, 0, 0)) + Vector3.new(0, levels.Road, 0)
	part("HangarFloor", hg * CFrame.new(0, -0.3, 0), Vector3.new(60, 0.6, 40), L.Concrete, { Shadow = false })
	for _, side in ipairs({ -1, 1 }) do
		part("HangarWall" .. side, hg * CFrame.new(side * 30, 10, 0), Vector3.new(1, 20, 40), L.Steel)
	end
	part("HangarBack", hg * CFrame.new(0, 10, 20), Vector3.new(60, 20, 1), L.Steel)
	for k = -1, 1 do
		part(
			"HangarRoof" .. k,
			hg * CFrame.new(k * 20, 21 + (1 - math.abs(k)) * 2.5, 0) * CFrame.Angles(0, 0, -k * math.rad(8)),
			Vector3.new(21, 1, 41),
			L.Metal
		)
	end
	neon("HangarLine", hg * CFrame.new(0, 19.4, -20.2), Vector3.new(60, 0.3, 0.3), NEON.Accent)
	local jet = hg * CFrame.new(0, 3.2, 2)
	current.AssetCFrames.Jet = jet
	deco("JetBody", jet * CFrame.Angles(0, math.rad(90), 0), Vector3.new(30, 3.6, 3.6), L.PlasticLight, {
		Shape = Enum.PartType.Cylinder,
		Asset = "Jet",
		Collide = true,
	})
	deco(
		"JetNose",
		jet * CFrame.new(0, 0, -15),
		Vector3.new(3.6, 3.6, 3.6),
		L.PlasticLight,
		{ Shape = Enum.PartType.Ball, Asset = "Jet" }
	)
	for _, side in ipairs({ -1, 1 }) do
		deco(
			"JetWing" .. side,
			jet * CFrame.new(side * 8, -0.6, 2) * CFrame.Angles(0, side * math.rad(18), 0),
			Vector3.new(14, 0.4, 5),
			L.PlasticLight,
			{ Asset = "Jet" }
		)
		deco(
			"JetEngine" .. side,
			jet * CFrame.new(side * 3.2, 0.8, 11) * CFrame.Angles(0, math.rad(90), 0),
			Vector3.new(4, 1.6, 1.6),
			L.Metal,
			{
				Shape = Enum.PartType.Cylinder,
				Asset = "Jet",
			}
		)
	end
	deco(
		"JetFin",
		jet * CFrame.new(0, 3.2, 13) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(0.4, 5, 4),
		L.PlasticLight,
		{ Asset = "Jet", Wedge = true }
	)
	neon(
		"JetStripe",
		jet * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, math.rad(90), 0),
		Vector3.new(26, 0.3, 3.7),
		NEON.Accent,
		{ Asset = "Jet" }
	)
end

-- 5.14 FINANZVIERTEL-KULISSE: 36 Deko-Türme (8 Parts) mit Leuchtschildern der fiktiven Firmen (Atomic + LOD je Turm)
local function buildBackdrop()
	local bd = cfg.City.Backdrop
	local zone = cfg.City.Zones.Backdrop
	local roads = cfg.City.Roads
	local hill = cfg.City.Zones.Hill
	local rng = Random.new(bd.Seed)
	local candidates: { { Pos: Vector3, Width: number, Height: number } } = {}
	for _, range in ipairs(bd.AngleRanges) do
		local deg = range[1]
		while deg <= range[2] do
			for ringIndex, radius in ipairs(bd.Rings) do
				local jitterDeg = deg + rng:NextNumber(-2.2, 2.2) + (ringIndex % 2) * 3.5
				local r = radius + rng:NextNumber(-12, 12)
				local pos = polar(r, jitterDeg, 0)
				local okPos = true
				if math.abs(r - roads.Outer.Radius) < 50 or math.abs(r - roads.Highway.Radius) < 55 then
					okPos = false
				end
				local dh = Vector2.new(pos.X - hill.Center.X, pos.Z - hill.Center.Z).Magnitude
				if dh < hill.Radius + 60 then
					okPos = false
				end
				for _, ramp in ipairs(roads.Highway.Ramps) do
					if math.abs(((jitterDeg - ramp + 180) % 360) - 180) < 7 then
						okPos = false
					end
				end
				for _, avenue in ipairs(roads.Avenues) do
					if math.abs(((jitterDeg - avenue + 180) % 360) - 180) < 9 then
						okPos = false
					end
				end
				for _, box in ipairs(bd.Keepout) do
					if pos.X > box[1] and pos.X < box[3] and pos.Z > box[2] and pos.Z < box[4] then
						okPos = false
					end
				end
				if okPos then
					table.insert(candidates, {
						Pos = pos,
						Width = rng:NextNumber(bd.MinWidth, bd.MaxWidth),
						Height = rng:NextNumber(bd.MinHeight, bd.MaxHeight),
					})
				end
			end
			deg += 8
		end
	end
	-- gleichmäßig auswählen (deterministisch)
	local count = math.min(zone.Count, #candidates)
	local chosen: { { Pos: Vector3, Width: number, Height: number } } = {}
	if count > 0 then
		local stride = #candidates / count
		for k = 0, count - 1 do
			table.insert(chosen, candidates[math.floor(k * stride) + 1])
		end
	end
	local instruments = cfg.Companies and cfg.Companies.ById or {}
	for k, tower in ipairs(chosen) do
		group("Tower" .. k, "Backdrop", "Atomic", cfg.City.Streaming.MeshLod.Backdrop == true)
		local company = instruments[k]
		local sector = company and company.Sector or "T"
		local color = SECTOR_COLORS[sector] or NEON.Accent
		local w, h = tower.Width, tower.Height
		local cf = facingCenter(Vector3.new(tower.Pos.X, 0, tower.Pos.Z))
		part("Podium" .. k, cf * CFrame.new(0, 3, 0), Vector3.new(w + 10, 6, w + 10), L.Concrete)
		part("Shaft" .. k, cf * CFrame.new(0, 6 + h / 2, 0), Vector3.new(w, h, w), L.GlassDark)
		part("Cap" .. k, cf * CFrame.new(0, 6 + h + 2, 0), Vector3.new(w * 0.7, 4, w * 0.7), L.Metal)
		for _, side in ipairs({ -1, 1 }) do
			neon(
				"Fin" .. k .. side,
				cf * CFrame.new(side * (w / 2 + 0.1), 6 + h / 2, -w / 2 - 0.1),
				Vector3.new(0.35, h, 0.35),
				color
			)
		end
		for band = 1, 2 do
			deco(
				"Windows" .. k .. "_" .. band,
				cf * CFrame.new(0, 6 + h * band / 3, -w / 2 - 0.12),
				Vector3.new(w - 2, h * 0.22, 0.12),
				L.GlassDark,
				{
					Attrs = { WindowLight = band * 3 },
				}
			)
		end
		local text = if company then company.Ticker else "AKX"
		part("Sign" .. k, cf * CFrame.new(0, 6 + h - 6, -w / 2 - 0.4), Vector3.new(w - 4, 7, 0.4), L.Plastic, {
			Gui = {
				Face = Enum.NormalId.Front,
				Text = text,
				Sub = if company then company.Name else nil,
				Color = color,
				SubColor = NEON.Letters,
				Display = true,
				MaxDistance = 1400,
			},
			Attrs = { Company = if company then company.Id else 0 },
			Shadow = false,
		})
	end
end

-- ---------------------------------------------------------------------
-- 6) PLAN
-- ---------------------------------------------------------------------
local function newPlan(): Plan
	return {
		Groups = {},
		Anchors = {},
		Terrain = {},
		PlotSites = {},
		ShopFronts = {},
		Count = 0,
	}
end

function CityLayout.Plan(config: any): Plan
	cfg = config
	plan = newPlan()
	local serpentine = serpentinePoints()
	addTerrainJobs(serpentine)
	buildPlaza()
	buildExchange()
	buildRing()
	buildOuter()
	buildAvenues()
	buildPlots()
	buildShops()
	buildHighway()
	buildMotors()
	buildChrono()
	buildMarina()
	buildHill(serpentine)
	buildHelipad()
	buildBackdrop()
	local result = plan
	plan = newPlan()
	return result
end

-- Nur die Anker (ohne Terrain-Aufträge) – für CityService.Anchor schon vor dem Bau
local anchorCache: { [string]: CFrame }? = nil
function CityLayout.Anchors(config: any): { [string]: CFrame }
	local cached = anchorCache
	if cached then
		return cached
	end
	local full = CityLayout.Plan(config)
	anchorCache = full.Anchors
	return full.Anchors
end

return CityLayout
