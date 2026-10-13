--!strict
-- =====================================================================
--  AKYTEX TYCOON – Auto-Baupläne aus Parts (Shared/VehicleModels)
--  Besitzer: WP7 (Stadt, Grafik, Fahrzeuge). Vertrag: DESIGN.md §C6.2 (VehicleModels.Build/Recipes), §B12.1 (Bau:
--  VehicleSeat, 4 Räder als Zylinder mit HingeConstraint-Motor, Servo-Lenkung, SpringConstraint-Federung, Neon-
--  Unterbodenlicht im Licht-Budget), §A4 (Autos aus Wedge/Zylinder), §C14.3 (Asset-Platz der Karosserie).
--  Gleiche Baupläne auf Server (fahrbare Autos, Showroom) und Client (Garage-Vorschau, Enthüllung) – deterministisch.
--
--  Koordinaten im Modell: Ursprung = Boden-Mitte zwischen den Achsen, vorn = −Z (LookVector), rechts = +X, oben = +Y.
--  Benannte Teile: "Chassis" (PrimaryPart, unsichtbar, Masse), "Seat" (VehicleSeat), "Body" (Kollision mit der Welt),
--  "Wheel_FL/FR/RL/RR" (Zylinder, Achse = +X). Attribute an Teilen: Paint (Lack), Rim, Glow, Spoiler, Light.
--  Unterbodenlicht: PointLight "Underglow" im Chassis, Attribut "Budget" (WorldLook schaltet es im Licht-Budget ein).
--
--  Öffentliche API:
--    VehicleModels.Recipes: { [string]: Recipe }                  Baupläne (Config.Vehicles.Cars[i].Recipe)
--    VehicleModels.Build(key, paint?, rims?, glow?): Model        statisches, verankertes Modell (Pivot = Boden-Mitte)
--    VehicleModels.ApplyTune(model, key, tune?)                   Lack/Felgen/Unterbodenlicht/Spoiler live ändern
--    VehicleModels.Rig(model, key): Rig                           Server: Schweißnähte, Federbeine, Motoren, Servo-Lenkung
--    VehicleModels.WHEEL_SIGN                                     Vorzeichen: vorwärts = WHEEL_SIGN × v / r (rad/s)
--  Rig-Felder: Chassis, Seat, Wheels { FL, FR, RL, RR }, Motors { FL, FR, RL, RR } (HingeConstraint), Steer { FL, FR }
--    (HingeConstraint Servo), Springs, Downforce (VectorForce), Mass, WheelRadius
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = script.Parent
local Config = require(Shared:WaitForChild("Config")) :: any

local VehicleModels = {}

export type Recipe = {
	L: number, -- Länge
	W: number, -- Breite
	H: number, -- Karosserie-Höhe (ohne Kabine)
	Clear: number, -- Bodenfreiheit
	WheelR: number,
	WheelW: number,
	Base: number, -- Radstand
	Track: number, -- Rad-Mitte seitlich
	Nose: number, -- Länge Front-Keil
	Tail: number, -- Länge Heck-Keil
	CabinF: number, -- Kabine vorn (z, negativ = vorn)
	CabinR: number, -- Kabine hinten (z)
	CabinH: number,
	Inset: number, -- Kabine seitlich eingerückt
	Shield: number, -- Länge Frontscheibe
	Rear: number, -- Länge Heckscheibe
	Spoiler: boolean, -- Standard-Spoiler (Tuning schaltet um)
	Fins: boolean?,
	Scoops: boolean?,
	Canopy: boolean?, -- Kuppel-Kabine (Hyper)
	Lights: string, -- "Dual" | "Slim" | "Bar"
	Neon: Color3, -- Akzentlinie
	Grille: string?, -- "Chrome" | nil
}

export type Rig = {
	Chassis: BasePart,
	Seat: VehicleSeat,
	Wheels: { [string]: BasePart },
	Motors: { [string]: HingeConstraint },
	Steer: { [string]: HingeConstraint },
	Springs: { SpringConstraint },
	Downforce: VectorForce,
	Mass: number,
	WheelRadius: number,
}

VehicleModels.WHEEL_SIGN = -1 -- Drehung um +X (rechts): oben nach hinten = vorwärts -> negativ

local ACCENT = Color3.fromRGB(79, 140, 255)
local CYAN = Color3.fromRGB(34, 211, 238)
local UP = Color3.fromRGB(34, 197, 94)
local DOWN = Color3.fromRGB(239, 68, 68)
local COSMIC = Color3.fromRGB(179, 107, 255)
local VIOLET = Color3.fromRGB(124, 92, 255)
local WARN = Color3.fromRGB(234, 179, 8)

local TIRE = Color3.fromRGB(22, 23, 27)
local TRIM = Color3.fromRGB(26, 28, 33)
local GLASS = Color3.fromRGB(14, 20, 32)
local CHROME = Color3.fromRGB(214, 220, 228)
local HEAD = Color3.fromRGB(235, 242, 255)
local TAIL = Color3.fromRGB(239, 48, 56)

local WHEELS = { "FL", "FR", "RL", "RR" }

-- ---------------------------------------------------------------------
-- 1) BAUPLÄNE (16 Autos, je eigene Silhouette)
-- ---------------------------------------------------------------------
-- stylua: ignore start
VehicleModels.Recipes = {
	LamCity = { L = 12, W = 6.2, H = 2.0, Clear = 0.8, WheelR = 1.25, WheelW = 1.0, Base = 7.6, Track = 2.65, Nose = 2.0,
		Tail = 1.0, CabinF = -2.6, CabinR = 4.4, CabinH = 2.3, Inset = 0.45, Shield = 1.7, Rear = 0.8, Spoiler = false,
		Lights = "Dual", Neon = ACCENT },
	VoltaHatch = { L = 12.4, W = 6.3, H = 2.0, Clear = 0.75, WheelR = 1.28, WheelW = 1.05, Base = 7.8, Track = 2.7, Nose = 2.2,
		Tail = 1.1, CabinF = -2.4, CabinR = 4.5, CabinH = 2.2, Inset = 0.45, Shield = 1.9, Rear = 0.9, Spoiler = true,
		Lights = "Slim", Neon = CYAN },
	PixelMini = { L = 10.8, W = 6.0, H = 2.1, Clear = 0.8, WheelR = 1.2, WheelW = 1.0, Base = 7.0, Track = 2.55, Nose = 1.6,
		Tail = 0.7, CabinF = -2.0, CabinR = 4.0, CabinH = 2.45, Inset = 0.35, Shield = 1.2, Rear = 0.5, Spoiler = false,
		Lights = "Dual", Neon = COSMIC },
	LamNeon = { L = 12.2, W = 6.3, H = 1.95, Clear = 0.7, WheelR = 1.28, WheelW = 1.05, Base = 7.7, Track = 2.7, Nose = 2.2,
		Tail = 1.0, CabinF = -2.4, CabinR = 4.4, CabinH = 2.2, Inset = 0.45, Shield = 1.8, Rear = 0.9, Spoiler = true,
		Lights = "Bar", Neon = VIOLET },
	Stratos = { L = 15, W = 6.8, H = 2.1, Clear = 0.8, WheelR = 1.35, WheelW = 1.1, Base = 9.4, Track = 2.95, Nose = 3.2,
		Tail = 2.6, CabinF = -2.6, CabinR = 3.4, CabinH = 2.2, Inset = 0.5, Shield = 1.9, Rear = 1.7, Spoiler = false,
		Lights = "Slim", Neon = ACCENT },
	Nordlicht = { L = 16, W = 7.0, H = 2.3, Clear = 0.85, WheelR = 1.4, WheelW = 1.15, Base = 10.2, Track = 3.05, Nose = 3.6,
		Tail = 2.8, CabinF = -2.8, CabinR = 4.0, CabinH = 2.3, Inset = 0.5, Shield = 2.0, Rear = 1.8, Spoiler = false,
		Lights = "Slim", Neon = CYAN, Grille = "Chrome" },
	VelocitraS = { L = 14.6, W = 7.0, H = 1.7, Clear = 0.6, WheelR = 1.4, WheelW = 1.2, Base = 9.0, Track = 3.0, Nose = 4.0,
		Tail = 2.0, CabinF = -1.6, CabinR = 2.8, CabinH = 1.75, Inset = 0.6, Shield = 2.3, Rear = 2.0, Spoiler = true,
		Lights = "Slim", Neon = DOWN },
	NeonCoupe = { L = 14.8, W = 7.0, H = 1.75, Clear = 0.6, WheelR = 1.4, WheelW = 1.2, Base = 9.1, Track = 3.0, Nose = 4.0,
		Tail = 2.2, CabinF = -1.8, CabinR = 3.0, CabinH = 1.75, Inset = 0.6, Shield = 2.2, Rear = 2.2, Spoiler = false,
		Lights = "Bar", Neon = ACCENT },
	StreakGT = { L = 15, W = 7.2, H = 1.7, Clear = 0.6, WheelR = 1.42, WheelW = 1.25, Base = 9.2, Track = 3.1, Nose = 4.2,
		Tail = 2.0, CabinF = -1.4, CabinR = 2.8, CabinH = 1.7, Inset = 0.65, Shield = 2.3, Rear = 1.8, Spoiler = true,
		Lights = "Bar", Neon = WARN },
	Kometa = { L = 15.6, W = 7.4, H = 1.5, Clear = 0.5, WheelR = 1.45, WheelW = 1.3, Base = 9.4, Track = 3.15, Nose = 4.6,
		Tail = 2.2, CabinF = -0.9, CabinR = 2.8, CabinH = 1.55, Inset = 0.8, Shield = 2.4, Rear = 1.7, Spoiler = true,
		Scoops = true, Lights = "Slim", Neon = CYAN },
	AuroraGT = { L = 16, W = 7.4, H = 1.55, Clear = 0.5, WheelR = 1.45, WheelW = 1.3, Base = 9.6, Track = 3.15, Nose = 4.8,
		Tail = 2.4, CabinF = -1.0, CabinR = 3.0, CabinH = 1.55, Inset = 0.8, Shield = 2.5, Rear = 1.9, Spoiler = false,
		Scoops = true, Lights = "Bar", Neon = UP },
	QuasarX = { L = 16.4, W = 7.6, H = 1.35, Clear = 0.45, WheelR = 1.5, WheelW = 1.35, Base = 9.8, Track = 3.25, Nose = 5.0,
		Tail = 2.4, CabinF = -0.6, CabinR = 2.8, CabinH = 1.45, Inset = 1.4, Shield = 2.6, Rear = 1.6, Spoiler = true,
		Fins = true, Scoops = true, Canopy = true, Lights = "Bar", Neon = COSMIC },
	VelocitraH = { L = 16.2, W = 7.6, H = 1.4, Clear = 0.45, WheelR = 1.5, WheelW = 1.35, Base = 9.7, Track = 3.25, Nose = 5.2,
		Tail = 2.2, CabinF = -0.8, CabinR = 2.6, CabinH = 1.45, Inset = 1.0, Shield = 2.6, Rear = 1.5, Spoiler = true,
		Scoops = true, Lights = "Slim", Neon = DOWN },
	Singularity = { L = 16.6, W = 7.6, H = 1.3, Clear = 0.45, WheelR = 1.5, WheelW = 1.35, Base = 9.9, Track = 3.25, Nose = 5.4,
		Tail = 2.6, CabinF = -0.4, CabinR = 2.8, CabinH = 1.4, Inset = 1.5, Shield = 2.6, Rear = 1.6, Spoiler = true,
		Fins = true, Scoops = true, Canopy = true, Lights = "Bar", Neon = VIOLET },
	OrbitR = { L = 16.2, W = 7.5, H = 1.35, Clear = 0.45, WheelR = 1.5, WheelW = 1.35, Base = 9.7, Track = 3.2, Nose = 5.0,
		Tail = 2.4, CabinF = -0.6, CabinR = 2.6, CabinH = 1.45, Inset = 1.4, Shield = 2.5, Rear = 1.6, Spoiler = false,
		Fins = true, Scoops = true, Canopy = true, Lights = "Bar", Neon = CYAN },
	Lam1 = { L = 16.8, W = 7.6, H = 1.3, Clear = 0.42, WheelR = 1.52, WheelW = 1.38, Base = 10.0, Track = 3.25, Nose = 5.6,
		Tail = 2.4, CabinF = -0.4, CabinR = 2.6, CabinH = 1.4, Inset = 1.5, Shield = 2.7, Rear = 1.5, Spoiler = true,
		Fins = true, Scoops = true, Canopy = true, Lights = "Bar", Neon = ACCENT },
}
-- stylua: ignore end

-- ---------------------------------------------------------------------
-- 2) HELFER
-- ---------------------------------------------------------------------
local function carEntry(key: string): any?
	local vehicles = Config.Vehicles
	if type(vehicles) ~= "table" or type(vehicles.Car) ~= "function" then
		return nil
	end
	return vehicles.Car(key)
end

local function option(kind: string, key: string?): any?
	local vehicles = Config.Vehicles
	if type(vehicles) ~= "table" or type(vehicles.Option) ~= "function" or type(key) ~= "string" then
		return nil
	end
	return vehicles.Option(kind, key)
end

local function recipeOf(key: string): Recipe
	local car = carEntry(key)
	local recipeKey = if car and type(car.Recipe) == "string" then car.Recipe else key
	local recipe = (VehicleModels.Recipes :: any)[recipeKey]
	if recipe == nil then
		recipe = VehicleModels.Recipes.LamCity
	end
	return recipe :: Recipe
end

type PartOpts = {
	Shape: Enum.PartType?,
	Wedge: boolean?,
	Transparency: number?,
	Reflectance: number?,
	Collide: boolean?,
	Shadow: boolean?,
	Attr: string?,
	AttrValue: any?,
}

local function makePart(
	model: Model,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	opts: PartOpts?
): BasePart
	local o: PartOpts = opts or {}
	local part: BasePart
	if o.Wedge then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		p.Shape = o.Shape or Enum.PartType.Block
		part = p
	end
	part.Name = name
	part.Size = Vector3.new(math.max(0.05, size.X), math.max(0.05, size.Y), math.max(0.05, size.Z))
	part.CFrame = cf
	part.Color = color
	part.Material = material
	part.Transparency = o.Transparency or 0
	part.Reflectance = o.Reflectance or 0
	part.Anchored = true
	part.CanCollide = o.Collide == true
	part.CanTouch = false
	part.CanQuery = o.Collide == true
	part.CastShadow = o.Shadow ~= false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if o.Attr then
		part:SetAttribute(o.Attr, if o.AttrValue ~= nil then o.AttrValue else true)
	end
	part.Parent = model
	return part
end

local function paintColor(paintKey: string?): (Color3, boolean)
	local paint = option("Paint", paintKey)
	if paint and typeof(paint.Color) == "Color3" then
		return paint.Color, paint.Metallic == true
	end
	return Color3.fromRGB(232, 235, 240), false
end

-- ---------------------------------------------------------------------
-- 3) KAROSSERIE (Rezept) – wird durch einen gesetzten Asset-Platz ersetzt
-- ---------------------------------------------------------------------
local function buildBody(model: Model, r: Recipe)
	local paint = Color3.new(1, 1, 1) -- echte Farbe setzt ApplyTune
	local top = r.Clear + r.H
	local mainLen = r.L - r.Nose - r.Tail
	local mainZ = (r.Nose - r.Tail) / 2
	local frontZ = -r.L / 2
	local rearZ = r.L / 2

	-- Wanne (kollidiert mit der Welt)
	makePart(
		model,
		"Body",
		Vector3.new(r.W, r.H, mainLen),
		CFrame.new(0, r.Clear + r.H / 2, mainZ),
		paint,
		Enum.Material.SmoothPlastic,
		{ Collide = true, Attr = "Paint" }
	)
	-- Front: Stoßfänger-Block + Motorhaube als Keil (niedrig vorn)
	local bumperH = r.H * 0.48
	makePart(
		model,
		"Bumper",
		Vector3.new(r.W - 0.1, bumperH, r.Nose),
		CFrame.new(0, r.Clear + bumperH / 2, frontZ + r.Nose / 2),
		paint,
		Enum.Material.SmoothPlastic,
		{ Attr = "Paint" }
	)
	makePart(
		model,
		"Hood",
		Vector3.new(r.W - 0.1, r.H - bumperH, r.Nose),
		CFrame.new(0, r.Clear + bumperH + (r.H - bumperH) / 2, frontZ + r.Nose / 2),
		paint,
		Enum.Material.SmoothPlastic,
		{ Wedge = true, Attr = "Paint" }
	)
	-- Heck: Block + Keil (niedrig hinten)
	local tailH = r.H * 0.62
	makePart(
		model,
		"TailBlock",
		Vector3.new(r.W - 0.1, tailH, r.Tail),
		CFrame.new(0, r.Clear + tailH / 2, rearZ - r.Tail / 2),
		paint,
		Enum.Material.SmoothPlastic,
		{ Attr = "Paint" }
	)
	makePart(
		model,
		"Deck",
		Vector3.new(r.W - 0.1, r.H - tailH, r.Tail),
		CFrame.new(0, r.Clear + tailH + (r.H - tailH) / 2, rearZ - r.Tail / 2) * CFrame.Angles(0, math.pi, 0),
		paint,
		Enum.Material.SmoothPlastic,
		{ Wedge = true, Attr = "Paint" }
	)

	-- Kabine
	local cabinW = r.W - 2 * r.Inset
	local coreLen = math.max(0.4, (r.CabinR - r.CabinF) - r.Shield - r.Rear)
	local coreZ = r.CabinF + r.Shield + coreLen / 2
	local cabinY = top + r.CabinH / 2
	if r.Canopy then
		-- Kuppel aus Glas (SpecialMesh Sphere, ellipsoid) + Lackrücken
		local canopy = makePart(
			model,
			"Canopy",
			Vector3.new(1, 1, 1),
			CFrame.new(0, top + 0.05, (r.CabinF + r.CabinR) / 2),
			GLASS,
			Enum.Material.Glass,
			{ Transparency = 0.2, Reflectance = 0.4 }
		)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = Vector3.new(cabinW, r.CabinH * 2, r.CabinR - r.CabinF)
		mesh.Parent = canopy
		makePart(
			model,
			"Spine",
			Vector3.new(cabinW * 0.5, r.CabinH * 0.6, r.Rear + 1.2),
			CFrame.new(0, top + r.CabinH * 0.3, r.CabinR + (r.Rear + 1.2) / 2 - 0.6) * CFrame.Angles(0, math.pi, 0),
			paint,
			Enum.Material.SmoothPlastic,
			{ Wedge = true, Attr = "Paint" }
		)
	else
		makePart(
			model,
			"Windshield",
			Vector3.new(cabinW, r.CabinH, r.Shield),
			CFrame.new(0, cabinY, r.CabinF + r.Shield / 2),
			GLASS,
			Enum.Material.Glass,
			{ Wedge = true, Transparency = 0.2, Reflectance = 0.35 }
		)
		makePart(
			model,
			"Cabin",
			Vector3.new(cabinW, r.CabinH, coreLen),
			CFrame.new(0, cabinY, coreZ),
			GLASS,
			Enum.Material.Glass,
			{ Transparency = 0.25, Reflectance = 0.35 }
		)
		makePart(
			model,
			"RearWindow",
			Vector3.new(cabinW, r.CabinH, r.Rear),
			CFrame.new(0, cabinY, r.CabinR - r.Rear / 2) * CFrame.Angles(0, math.pi, 0),
			GLASS,
			Enum.Material.Glass,
			{ Wedge = true, Transparency = 0.2, Reflectance = 0.35 }
		)
		makePart(
			model,
			"Roof",
			Vector3.new(cabinW + 0.08, 0.22, coreLen + 0.15),
			CFrame.new(0, top + r.CabinH + 0.11, coreZ),
			paint,
			Enum.Material.SmoothPlastic,
			{ Attr = "Paint" }
		)
		for _, side in ipairs({ -1, 1 }) do
			makePart(
				model,
				if side < 0 then "PillarL" else "PillarR",
				Vector3.new(0.12, r.CabinH, 0.45),
				CFrame.new(side * (cabinW / 2 + 0.03), cabinY, coreZ),
				paint,
				Enum.Material.SmoothPlastic,
				{ Attr = "Paint", Shadow = false }
			)
		end
	end

	-- Spiegel, Schweller, Lufteinlässe, Finnen
	for _, side in ipairs({ -1, 1 }) do
		local suffix = if side < 0 then "L" else "R"
		makePart(
			model,
			"Mirror" .. suffix,
			Vector3.new(0.5, 0.32, 0.36),
			CFrame.new(side * (r.W / 2 + 0.15), top + 0.25, r.CabinF + r.Shield * 0.55),
			paint,
			Enum.Material.SmoothPlastic,
			{ Attr = "Paint", Shadow = false }
		)
		makePart(
			model,
			"Skirt" .. suffix,
			Vector3.new(0.3, 0.32, r.Base - 2 * r.WheelR - 0.4),
			CFrame.new(side * (r.W / 2 + 0.05), r.Clear + 0.16, 0),
			TRIM,
			Enum.Material.SmoothPlastic,
			{ Shadow = false }
		)
		-- Akzentlinie (Neon nur als 0,2-Stud-Streifen)
		makePart(
			model,
			"Accent" .. suffix,
			Vector3.new(0.06, 0.12, mainLen * 0.9),
			CFrame.new(side * (r.W / 2 + 0.03), r.Clear + r.H * 0.55, mainZ),
			r.Neon,
			Enum.Material.Neon,
			{ Shadow = false }
		)
		if r.Scoops then
			makePart(
				model,
				"Scoop" .. suffix,
				Vector3.new(0.4, r.H * 0.6, 1.8),
				CFrame.new(side * (r.W / 2 + 0.05), r.Clear + r.H * 0.45, r.CabinR - 0.3) * CFrame.Angles(0, math.pi, 0),
				TRIM,
				Enum.Material.SmoothPlastic,
				{ Wedge = true, Shadow = false }
			)
		end
		if r.Fins then
			makePart(
				model,
				"Fin" .. suffix,
				Vector3.new(0.15, r.CabinH * 0.9, 1.8),
				CFrame.new(side * (r.W / 2 - 0.9), top + r.CabinH * 0.45, rearZ - 1.4) * CFrame.Angles(0, math.pi, 0),
				paint,
				Enum.Material.SmoothPlastic,
				{ Wedge = true, Attr = "Paint" }
			)
		end
	end

	-- Kühlergrill
	makePart(
		model,
		"Grille",
		Vector3.new(r.W * 0.46, bumperH * 0.55, 0.12),
		CFrame.new(0, r.Clear + bumperH * 0.42, frontZ - 0.04),
		if r.Grille == "Chrome" then CHROME else TRIM,
		if r.Grille == "Chrome" then Enum.Material.Metal else Enum.Material.SmoothPlastic,
		{ Reflectance = if r.Grille == "Chrome" then 0.4 else 0, Shadow = false }
	)
end

-- Lichter (immer aus Code – auch zu einem Mesh-Körper)
local function buildLights(model: Model, r: Recipe)
	local frontZ = -r.L / 2
	local rearZ = r.L / 2
	local headY = r.Clear + r.H * 0.42
	if r.Lights == "Bar" then
		makePart(
			model,
			"HeadBar",
			Vector3.new(r.W * 0.86, 0.14, 0.12),
			CFrame.new(0, headY, frontZ - 0.05),
			HEAD,
			Enum.Material.Neon,
			{ Attr = "Light", AttrValue = "Head", Shadow = false }
		)
	else
		local w = if r.Lights == "Slim" then r.W * 0.22 else r.W * 0.16
		local h = if r.Lights == "Slim" then 0.16 else 0.3
		for _, side in ipairs({ -1, 1 }) do
			makePart(
				model,
				if side < 0 then "HeadL" else "HeadR",
				Vector3.new(w, h, 0.14),
				CFrame.new(side * r.W * 0.33, headY, frontZ - 0.05),
				HEAD,
				Enum.Material.Neon,
				{ Attr = "Light", AttrValue = "Head", Shadow = false }
			)
		end
	end
	makePart(
		model,
		"TailLight",
		Vector3.new(r.W * 0.82, 0.16, 0.12),
		CFrame.new(0, r.Clear + r.H * 0.62 * 0.82, rearZ + 0.05),
		TAIL,
		Enum.Material.Neon,
		{ Attr = "Light", AttrValue = "Tail", Shadow = false }
	)
	-- Auspuff
	for _, side in ipairs({ -1, 1 }) do
		makePart(
			model,
			if side < 0 then "ExhaustL" else "ExhaustR",
			Vector3.new(0.6, 0.34, 0.34),
			CFrame.new(side * r.W * 0.28, r.Clear + 0.2, rearZ + 0.15) * CFrame.Angles(0, math.rad(90), 0),
			CHROME,
			Enum.Material.Metal,
			{ Shape = Enum.PartType.Cylinder, Reflectance = 0.3, Shadow = false }
		)
	end
end

local function buildSpoiler(model: Model, r: Recipe)
	local top = r.Clear + r.H
	local rearZ = r.L / 2
	local wingY = top + math.max(0.8, r.CabinH * 0.55)
	local wingZ = rearZ - r.Tail * 0.45
	makePart(
		model,
		"Wing",
		Vector3.new(r.W * 0.92, 0.14, 1.1),
		CFrame.new(0, wingY, wingZ) * CFrame.Angles(math.rad(-6), 0, 0),
		Color3.new(1, 1, 1),
		Enum.Material.SmoothPlastic,
		{ Attr = "Spoiler", Shadow = false }
	):SetAttribute("Paint", true)
	for _, side in ipairs({ -1, 1 }) do
		makePart(
			model,
			if side < 0 then "WingStrutL" else "WingStrutR",
			Vector3.new(0.14, wingY - top, 0.35),
			CFrame.new(side * r.W * 0.3, top + (wingY - top) / 2, wingZ + 0.1),
			TRIM,
			Enum.Material.SmoothPlastic,
			{ Attr = "Spoiler", Shadow = false }
		)
	end
end

local function buildWheels(model: Model, r: Recipe)
	for _, key in ipairs(WHEELS) do
		local front = string.sub(key, 1, 1) == "F"
		local side = if string.sub(key, 2, 2) == "L" then -1 else 1
		local center = CFrame.new(side * r.Track, r.WheelR, if front then -r.Base / 2 else r.Base / 2)
		local wheel = makePart(
			model,
			"Wheel_" .. key,
			Vector3.new(r.WheelW, r.WheelR * 2, r.WheelR * 2),
			center,
			TIRE,
			Enum.Material.SmoothPlastic,
			{ Shape = Enum.PartType.Cylinder, Collide = true, Attr = "Wheel", AttrValue = key }
		)
		local outer = side * (r.WheelW / 2 + 0.02)
		local rim = makePart(
			model,
			"Rim_" .. key,
			Vector3.new(0.16, r.WheelR * 1.36, r.WheelR * 1.36),
			center * CFrame.new(outer, 0, 0),
			CHROME,
			Enum.Material.Metal,
			{ Shape = Enum.PartType.Cylinder, Attr = "Rim", Shadow = false }
		)
		rim:SetAttribute("WheelOf", key)
		local spoke = makePart(
			model,
			"Spoke_" .. key,
			Vector3.new(0.1, r.WheelR * 1.25, 0.28),
			center * CFrame.new(outer + side * 0.06, 0, 0),
			TRIM,
			Enum.Material.SmoothPlastic,
			{ Attr = "Spoke", Shadow = false }
		)
		spoke:SetAttribute("WheelOf", key)
		local hub = makePart(
			model,
			"Hub_" .. key,
			Vector3.new(0.12, r.WheelR * 0.4, r.WheelR * 0.4),
			center * CFrame.new(outer + side * 0.1, 0, 0),
			TRIM,
			Enum.Material.Metal,
			{ Shape = Enum.PartType.Cylinder, Shadow = false }
		)
		hub:SetAttribute("WheelOf", key)
		wheel:SetAttribute("Radius", r.WheelR)
	end
end

local function buildGlow(model: Model, r: Recipe, chassis: BasePart)
	local mainLen = r.L - r.Nose - r.Tail
	makePart(
		model,
		"GlowStrip",
		Vector3.new(r.W * 0.7, 0.08, mainLen),
		CFrame.new(0, r.Clear - 0.06, (r.Nose - r.Tail) / 2),
		ACCENT,
		Enum.Material.Neon,
		{ Attr = "Glow", Shadow = false }
	)
	local light = Instance.new("PointLight")
	light.Name = "Underglow"
	light.Range = 12
	light.Brightness = 2
	light.Shadows = false
	light.Enabled = false -- WorldLook schaltet im Licht-Budget (Attribut "Budget")
	light:SetAttribute("Budget", true)
	light.Parent = chassis
end

-- ---------------------------------------------------------------------
-- 4) ÖFFENTLICH: Build / ApplyTune
-- ---------------------------------------------------------------------
local assetSlot: any = false
local function getAssetSlot(): any?
	if assetSlot == false then
		local module = ReplicatedStorage:FindFirstChild("Shared")
		local found = module and module:FindFirstChild("AssetSlot")
		local ok, result = false, nil
		if found and found:IsA("ModuleScript") then
			ok, result = pcall(require, found)
		end
		assetSlot = if ok and type(result) == "table" then result else nil
	end
	return assetSlot
end

function VehicleModels.Build(key: string, paint: string?, rims: string?, glow: string?): Model
	local r = recipeOf(key)
	local car = carEntry(key)
	local model = Instance.new("Model")
	model.Name = if car then car.Key else tostring(key)

	-- Chassis (Masse, unsichtbar) + Sitz
	local chassis = makePart(
		model,
		"Chassis",
		Vector3.new(r.W - 1.2, 0.8, r.Base + 1.2),
		CFrame.new(0, r.WheelR, 0),
		TRIM,
		Enum.Material.SmoothPlastic,
		{ Transparency = 1, Shadow = false }
	)
	model.PrimaryPart = chassis
	local seat = Instance.new("VehicleSeat")
	seat.Name = "Seat"
	seat.Size = Vector3.new(1.8, 0.4, 1.8)
	seat.CFrame = CFrame.new(-r.W * 0.2, r.Clear + 0.75, (r.CabinF + r.CabinR) / 2 + 0.3)
	seat.Transparency = 1
	seat.Anchored = true
	seat.CanCollide = false
	seat.CanQuery = false
	seat.CanTouch = false -- Einsteigen nur über den Server (Prompt), nie durch Berühren
	seat.HeadsUpDisplay = false
	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.TurnSpeed = 0
	seat.Parent = model

	-- Karosserie: Asset-Platz (Mesh) oder Rezept
	local slot = if car then car.Asset else nil
	local built = false
	local AssetSlot = getAssetSlot()
	if AssetSlot and slot and AssetSlot.IsSet(slot) then
		local ok, result = pcall(AssetSlot.Mesh, "Vehicles." .. model.Name, slot, function(): Instance
			local recipeModel = Instance.new("Model")
			recipeModel.Name = "Recipe"
			return recipeModel
		end)
		if ok and typeof(result) == "Instance" and result.Name ~= "Recipe" then
			for _, child in ipairs(result:GetDescendants()) do
				if child:IsA("BasePart") then
					child.Anchored = true
					child.CanCollide = false
					child.CanTouch = false
					child:SetAttribute("Paint", true)
					child.Parent = model
				end
			end
			result:Destroy()
			-- Kollisionswanne bleibt Rezept-Form (unsichtbar)
			local hull = makePart(
				model,
				"Body",
				Vector3.new(r.W, r.H, r.L - r.Nose - r.Tail),
				CFrame.new(0, r.Clear + r.H / 2, (r.Nose - r.Tail) / 2),
				TRIM,
				Enum.Material.SmoothPlastic,
				{ Collide = true, Transparency = 1, Shadow = false }
			)
			hull:SetAttribute("Hull", true)
			built = true
		elseif ok and typeof(result) == "Instance" then
			result:Destroy()
		end
	end
	if not built then
		buildBody(model, r)
	end
	buildLights(model, r)
	buildSpoiler(model, r)
	buildWheels(model, r)
	buildGlow(model, r, chassis)

	model:SetAttribute("Car", model.Name)
	model:SetAttribute("Class", if car then car.Class else "Kompakt")
	model:SetAttribute("WheelR", r.WheelR)
	model.WorldPivot = CFrame.identity
	VehicleModels.ApplyTune(model, model.Name, {
		Paint = paint,
		Rims = rims,
		Glow = glow,
		Spoiler = nil,
	})
	return model
end

-- tune = { Paint?, Rims?, Glow?, Spoiler? } – fehlende Felder: Standard des Autos
function VehicleModels.ApplyTune(model: Model, key: string, tune: { [string]: any }?)
	if typeof(model) ~= "Instance" then
		return
	end
	local t = tune or {}
	local car = carEntry(key)
	local r = recipeOf(key)
	local paintKey = if type(t.Paint) == "string" and option("Paint", t.Paint) then t.Paint
		elseif car then car.Paint
		else "Polar"
	local color, metallic = paintColor(paintKey)
	local rim = option("Rims", t.Rims) or option("Rims", "Stock")
	local glowEntry = option("Glow", t.Glow)
	local glowOn = glowEntry ~= nil
	local spoilerOn = if type(t.Spoiler) == "boolean" then t.Spoiler else r.Spoiler

	for _, part in ipairs(model:GetDescendants()) do
		if not part:IsA("BasePart") then
			continue
		end
		if part:GetAttribute("Paint") == true and part:GetAttribute("Hull") ~= true then
			part.Color = color
			part.Material = Enum.Material.SmoothPlastic -- Lack: glatt, Metallic = stärkere Spiegelung (Future-Licht)
			part.Reflectance = if metallic then 0.32 else 0.12
		end
		if part:GetAttribute("Rim") == true and rim then
			part.Color = rim.Color
			part.Material = if rim.Style == "Neon" then Enum.Material.Neon else Enum.Material.Metal
			part.Reflectance = if rim.Style == "Neon" then 0 else 0.3
		end
		if part:GetAttribute("Spoke") == true and rim then
			part.Transparency = if rim.Style == "Disc" then 1 else 0
			part.Color = if rim.Style == "Neon" then rim.Color else TRIM
			part.Material = if rim.Style == "Neon" then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
		if part:GetAttribute("Glow") == true then
			part.Transparency = if glowOn then 0 else 1
			if glowEntry then
				part.Color = glowEntry.Color
			end
		end
		if part:GetAttribute("Spoiler") == true then
			part.Transparency = if spoilerOn then 0 else 1
		end
	end
	local chassis = model:FindFirstChild("Chassis")
	local light = chassis and chassis:FindFirstChild("Underglow")
	if light and light:IsA("PointLight") then
		light:SetAttribute("Budget", glowOn)
		if glowEntry then
			light.Color = glowEntry.Color
		end
		if not glowOn then
			light.Enabled = false
		end
	end
	model:SetAttribute("Paint", paintKey)
	model:SetAttribute("Rims", if rim then rim.Key else "Stock")
	model:SetAttribute("Glow", if glowEntry then glowEntry.Key else "Off")
	model:SetAttribute("Spoiler", spoilerOn)
end

-- ---------------------------------------------------------------------
-- 5) RIG (Server): Schweißen, Federbeine (Prismatic + Spring), Servo-Lenkung, Rad-Motoren
-- ---------------------------------------------------------------------
local function axisAttachment(parent: BasePart, worldCf: CFrame, axis: Vector3, secondary: Vector3, name: string): Attachment
	local att = Instance.new("Attachment")
	att.Name = name
	att.Parent = parent -- erst einhängen, dann Welt-Lage setzen (WorldCFrame braucht den Träger)
	local x = axis.Unit
	local y = secondary.Unit
	local z = x:Cross(y)
	att.WorldCFrame = CFrame.fromMatrix(worldCf.Position, x, y, z)
	return att
end

local function physical(density: number, friction: number, weight: number): PhysicalProperties
	return PhysicalProperties.new(density, friction, 0, weight, 1)
end

function VehicleModels.Rig(model: Model, key: string): Rig
	local r = recipeOf(key)
	local vehicles = Config.Vehicles or {}
	local phys = vehicles.Physics or {}
	local chassis = model:FindFirstChild("Chassis") :: BasePart
	local seat = model:FindFirstChild("Seat") :: VehicleSeat
	assert(chassis and seat, "VehicleModels.Rig: Chassis/Seat fehlt")
	local right = chassis.CFrame.RightVector
	local up = chassis.CFrame.UpVector
	local forward = chassis.CFrame.LookVector

	chassis.CustomPhysicalProperties = physical(phys.ChassisDensity or 2.2, 0.3, 1)

	-- Räder + Rad-Anbauteile sammeln
	local wheels: { [string]: BasePart } = {}
	for _, key2 in ipairs(WHEELS) do
		local wheel = model:FindFirstChild("Wheel_" .. key2)
		if wheel and wheel:IsA("BasePart") then
			wheels[key2] = wheel
		end
	end
	for _, part in ipairs(model:GetDescendants()) do
		if not part:IsA("BasePart") or part == chassis then
			continue
		end
		local wheelOf = part:GetAttribute("WheelOf")
		local isWheel = part:GetAttribute("Wheel") ~= nil
		if isWheel then
			continue
		end
		local target: BasePart = chassis
		if type(wheelOf) == "string" and wheels[wheelOf] then
			target = wheels[wheelOf]
		end
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = target
		weld.Part1 = part
		weld.Parent = part
		part.Massless = true
	end

	-- Masse: Chassis-Baugruppe + Räder
	local mass = chassis:GetMass()
	for _, wheel in pairs(wheels) do
		wheel.CustomPhysicalProperties = physical(phys.WheelDensity or 0.9, phys.FrontFriction or 1.7, phys.FrictionWeight or 4)
		mass += wheel:GetMass()
	end
	local gravity = workspace.Gravity
	local corner = mass / 4
	local compression = phys.SpringCompression or 0.45
	local stiffness = corner * gravity / math.max(0.05, compression)
	local damping = 2 * (phys.SpringDampingRatio or 0.55) * math.sqrt(stiffness * corner)
	local travel = phys.SpringTravel or 0.9
	local springTop = 2.2

	local motors: { [string]: HingeConstraint } = {}
	local steer: { [string]: HingeConstraint } = {}
	local springs: { SpringConstraint } = {}
	local baseTorque = (phys.TorqueFactor or 1.4) * corner * gravity * r.WheelR

	for wheelKey, wheel in pairs(wheels) do
		local front = string.sub(wheelKey, 1, 1) == "F"
		local center = wheel.CFrame
		-- Federbein
		local strut = Instance.new("Part")
		strut.Name = "Strut_" .. wheelKey
		strut.Size = Vector3.new(0.4, 0.4, 0.4)
		strut.CFrame = CFrame.fromMatrix(center.Position, right, up)
		strut.Transparency = 1
		strut.CanCollide = false
		strut.CanQuery = false
		strut.CanTouch = false
		strut.CastShadow = false
		strut.CustomPhysicalProperties = physical(phys.PartDensity or 0.05, 0.3, 1)
		strut.Parent = model

		local slideA = axisAttachment(chassis, center, up, -right, "SlideA_" .. wheelKey)
		local slideB = axisAttachment(strut, center, up, -right, "SlideB_" .. wheelKey)
		local slider = Instance.new("PrismaticConstraint")
		slider.Name = "Slide_" .. wheelKey
		slider.Attachment0 = slideA
		slider.Attachment1 = slideB
		slider.LimitsEnabled = true
		slider.LowerLimit = -travel
		slider.UpperLimit = travel
		slider.Restitution = 0
		slider.Parent = strut

		local springA = axisAttachment(chassis, center * CFrame.new(0, springTop, 0), up, -right, "SpringA_" .. wheelKey)
		local springB = axisAttachment(strut, center, up, -right, "SpringB_" .. wheelKey)
		local spring = Instance.new("SpringConstraint")
		spring.Name = "Spring_" .. wheelKey
		spring.Attachment0 = springA
		spring.Attachment1 = springB
		spring.Stiffness = stiffness
		spring.Damping = damping
		spring.FreeLength = springTop
		spring.Visible = false
		spring.Parent = strut
		table.insert(springs, spring)

		-- Lenkung (vorn): Achsschenkel per Servo um die Hochachse
		local hub: BasePart = strut
		if front then
			local knuckle = Instance.new("Part")
			knuckle.Name = "Knuckle_" .. wheelKey
			knuckle.Size = Vector3.new(0.4, 0.4, 0.4)
			knuckle.CFrame = CFrame.fromMatrix(center.Position, right, up)
			knuckle.Transparency = 1
			knuckle.CanCollide = false
			knuckle.CanQuery = false
			knuckle.CanTouch = false
			knuckle.CastShadow = false
			knuckle.CustomPhysicalProperties = physical(phys.PartDensity or 0.05, 0.3, 1)
			knuckle.Parent = model
			local steerA = axisAttachment(strut, center, up, forward, "SteerA_" .. wheelKey)
			local steerB = axisAttachment(knuckle, center, up, forward, "SteerB_" .. wheelKey)
			local servo = Instance.new("HingeConstraint")
			servo.Name = "Steer_" .. wheelKey
			servo.Attachment0 = steerA
			servo.Attachment1 = steerB
			servo.ActuatorType = Enum.ActuatorType.Servo
			servo.ServoMaxTorque = mass * gravity * 40
			servo.AngularSpeed = phys.SteerSpeed or 7
			servo.AngularResponsiveness = 60
			servo.TargetAngle = 0
			servo.LimitsEnabled = true
			servo.LowerAngle = -(phys.SteerMax or 34) - 2
			servo.UpperAngle = (phys.SteerMax or 34) + 2
			servo.Parent = knuckle
			steer[wheelKey] = servo
			hub = knuckle
		end

		-- Rad-Motor um die Querachse (+X = rechts)
		local driveA = axisAttachment(hub, center, right, up, "DriveA_" .. wheelKey)
		local driveB = axisAttachment(wheel, center, right, up, "DriveB_" .. wheelKey)
		local motor = Instance.new("HingeConstraint")
		motor.Name = "Motor_" .. wheelKey
		motor.Attachment0 = driveA
		motor.Attachment1 = driveB
		motor.ActuatorType = Enum.ActuatorType.Motor
		motor.MotorMaxTorque = baseTorque * (phys.CoastTorque or 0.08)
		motor.MotorMaxAcceleration = 400
		motor.AngularVelocity = 0
		motor.Parent = wheel
		motors[wheelKey] = motor
		if not front then
			wheel.CustomPhysicalProperties =
				physical(phys.WheelDensity or 0.9, phys.RearFriction or 1.5, phys.FrictionWeight or 4)
		end
	end

	-- Anpressdruck (Client setzt die Kraft je nach Tempo)
	local forceAttachment = Instance.new("Attachment")
	forceAttachment.Name = "ForceAttachment"
	forceAttachment.Parent = chassis
	local downforce = Instance.new("VectorForce")
	downforce.Name = "Downforce"
	downforce.Attachment0 = forceAttachment
	downforce.RelativeTo = Enum.ActuatorRelativeTo.World
	downforce.ApplyAtCenterOfMass = true
	downforce.Force = Vector3.zero
	downforce.Parent = chassis

	-- alles ins Kollisionsgruppen-System, dann lösen
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Cars"
			part.Anchored = false
		end
	end
	model:SetAttribute("Mass", mass)
	model:SetAttribute("BaseTorque", baseTorque)
	return {
		Chassis = chassis,
		Seat = seat,
		Wheels = wheels,
		Motors = motors,
		Steer = steer,
		Springs = springs,
		Downforce = downforce,
		Mass = mass,
		WheelRadius = r.WheelR,
	}
end

return VehicleModels
