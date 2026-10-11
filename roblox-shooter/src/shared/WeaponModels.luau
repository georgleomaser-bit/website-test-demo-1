--!strict
-- =====================================================================
--  CLUTCH CLASH – Waffen-Modelle aus Parts (Shared/WeaponModels)
--  Besitzer: WP4 (Kampf Client). Vertrag: DESIGN.md B11.8, B19 (Skins), C6.3.
--  Keine hochgeladenen Assets: jede Waffe und jeder Skin ist ein REZEPT aus Parts
--  (Block/Cylinder/Ball/Wedge/CornerWedge/SpecialMesh Sphere+Cylinder). Spielzeug-Blaster
--  mit ORANGER SPITZE (Rolle "Tip", immer 255,120,0 Neon – Wraps ändern sie nie).
--  Gleiches Rezept für Viewmodel (Skala 1.0), 3rd Person (Skala 0.8) und Shop/Locker-Vorschau.
--
--  Öffentliche API:
--    WeaponModels.Build(key, opts?): Model
--        key  = Waffen-Key (Config.Weapons) ODER Skin-Id (S_…); unbekannt -> Ersatz-Blaster
--        opts = { Skin: string?, Scale: number?, Viewmodel: boolean? }
--        Ergebnis: Model (Name = Waffen-Key, Attribute WeaponKey/Skin/Recipe), PrimaryPart = erster Body-Teil,
--        WorldPivot = Griff (Grip). Attachments Grip/Muzzle/Sight/Charm/Support im PrimaryPart,
--        ein Teil heißt "Mag", jeder Teil hat das Attribut "Role". Alle Teile:
--        CanQuery/CanTouch/CanCollide = false, Massless, CastShadow = false.
--        Viewmodel = true -> alle Teile verankert, KEINE Schweißungen (Viewmodel setzt CFrames selbst);
--        sonst unverankert, per WeldConstraint an den PrimaryPart geschweißt (zum Anschweißen an die Hand).
--    WeaponModels.HasRecipe(key): boolean        Waffen-Keys, Admin-Waffen und Skin-Ids
--    WeaponModels.Recipes: { [key]: { PartSpec } }   Teile-Listen { Shape, Size, Offset, Role, Material?, Name?, Color?, Transparency? }
--    WeaponModels.Specs:   { [key]: { Base, Palette, Points, Emitters? } }   Farben je Rolle + Punkte
--    WeaponModels.SkinBase(id): string?           Waffe eines Skins (nil = kein Skin)
--    WeaponModels.TipColor                         Color3.fromRGB(255, 120, 0)
--  Koordinaten im Rezept: Ursprung = Handfläche am Griff, vorne = −Z, oben = +Y (Studs bei Skala 1).
-- =====================================================================

local WeaponModels = {}

export type PartSpec = {
	Shape: string,
	Size: Vector3,
	Offset: CFrame,
	Role: string,
	Material: string?,
	Name: string?,
	Color: Color3?,
	Transparency: number?,
}
export type EmitterSpec = { At: CFrame, Color: Color3, Rate: number, Size: number }
export type RecipeSpec = {
	Base: string,
	Palette: { [string]: Color3 },
	Points: { [string]: CFrame },
	Emitters: { EmitterSpec }?,
}
export type BuildOpts = { Skin: string?, Scale: number?, Viewmodel: boolean? }

WeaponModels.TipColor = Color3.fromRGB(255, 120, 0)
WeaponModels.Recipes = {} :: { [string]: { PartSpec } }
WeaponModels.Specs = {} :: { [string]: RecipeSpec }

local Recipes = WeaponModels.Recipes
local Specs = WeaponModels.Specs

local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local MAX_PARTS = 30

-- ---------------------------------------------------------------------
-- 1) REZEPT-HELFER (kurze Schreibweise)
-- ---------------------------------------------------------------------
local rad = math.rad
local v3 = Vector3.new
local rgb = Color3.fromRGB

local function at(x: number, y: number, z: number, rx: number?, ry: number?, rz: number?): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(rad(rx or 0), rad(ry or 0), rad(rz or 0))
end

type Extra = { M: string?, N: string?, C: Color3?, T: number? }

local function spec(shape: string, role: string, size: Vector3, offset: CFrame, extra: Extra?): PartSpec
	local e: Extra = extra or {}
	return {
		Shape = shape,
		Size = size,
		Offset = offset,
		Role = role,
		Material = e.M,
		Name = e.N,
		Color = e.C,
		Transparency = e.T,
	}
end

local AXIS_Z = CFrame.Angles(0, rad(90), 0) -- Zylinder-Achse (X) zeigt nach Z
local AXIS_Y = CFrame.Angles(0, 0, rad(90)) -- Zylinder-Achse (X) zeigt nach Y

local function blk(role: string, size: Vector3, offset: CFrame, extra: Extra?): PartSpec
	return spec("Block", role, size, offset, extra)
end
-- Zylinder entlang Z (Läufe, Rohre): Durchmesser d, Länge len
local function cylZ(role: string, d: number, len: number, offset: CFrame, extra: Extra?): PartSpec
	return spec("Cylinder", role, v3(len, d, d), offset * AXIS_Z, extra)
end
-- Zylinder entlang Y (Griffe, Klingen)
local function cylY(role: string, d: number, len: number, offset: CFrame, extra: Extra?): PartSpec
	return spec("Cylinder", role, v3(len, d, d), offset * AXIS_Y, extra)
end
-- Zylinder entlang X (Querbolzen)
local function cylX(role: string, d: number, len: number, offset: CFrame, extra: Extra?): PartSpec
	return spec("Cylinder", role, v3(len, d, d), offset, extra)
end
local function ball(role: string, d: number, offset: CFrame, extra: Extra?): PartSpec
	return spec("Ball", role, v3(d, d, d), offset, extra)
end
-- Ellipsoid (SpecialMesh Sphere, Größe = Part-Größe)
local function ell(role: string, size: Vector3, offset: CFrame, extra: Extra?): PartSpec
	return spec("MeshSphere", role, size, offset, extra)
end
-- weicher Zylinder (SpecialMesh Cylinder, Achse = lokales Y)
local function mcyl(role: string, size: Vector3, offset: CFrame, extra: Extra?): PartSpec
	return spec("MeshCylinder", role, size, offset, extra)
end
-- Keil: hohe Kante hinten (+Z), Schräge fällt nach vorne (−Z)
local function wedge(role: string, size: Vector3, offset: CFrame, extra: Extra?): PartSpec
	return spec("Wedge", role, size, offset, extra)
end
local function corner(role: string, size: Vector3, offset: CFrame, extra: Extra?): PartSpec
	return spec("CornerWedge", role, size, offset, extra)
end

local function pal(body: Color3, detail: Color3, accent: Color3, metal: Color3, grip: Color3): { [string]: Color3 }
	return { Body = body, Detail = detail, Accent = accent, Metal = metal, Grip = grip }
end

local function points(
	muzzle: CFrame,
	sight: CFrame,
	charm: CFrame,
	support: CFrame,
	grip: CFrame?
): { [string]: CFrame }
	return { Grip = grip or CFrame.identity, Muzzle = muzzle, Sight = sight, Charm = charm, Support = support }
end

local function define(
	key: string,
	base: string,
	palette: { [string]: Color3 },
	pts: { [string]: CFrame },
	parts: { PartSpec },
	emitters: { EmitterSpec }?
)
	assert(Recipes[key] == nil, "[WeaponModels] Doppeltes Rezept: " .. key)
	assert(#parts <= MAX_PARTS, "[WeaponModels] Zu viele Teile: " .. key)
	Recipes[key] = parts
	Specs[key] = { Base = base, Palette = palette, Points = pts, Emitters = emitters }
end

-- Skin: Punkte der Basis-Waffe übernehmen, einzelne überschreiben (gleiche Attachments -> gleiche Animationen)
local function skinPoints(base: string, overrides: { [string]: CFrame }?): { [string]: CFrame }
	local result: { [string]: CFrame } = {}
	local baseSpec = Specs[base]
	if baseSpec then
		for name, cf in pairs(baseSpec.Points) do
			result[name] = cf
		end
	end
	if overrides then
		for name, cf in pairs(overrides) do
			result[name] = cf
		end
	end
	return result
end

-- Farben (A4: Pastell-Plastik + Neon-Kanten)
local CREAM = rgb(244, 235, 221)
local MINT = rgb(154, 209, 212)
local PINK = rgb(247, 183, 200)
local LILAC = rgb(185, 167, 242)
local SAND = rgb(242, 213, 154)
local CHARCOAL = rgb(43, 43, 51)
local NAVY = rgb(28, 32, 64)
local WHITE = rgb(235, 238, 245)
local SILVER = rgb(196, 202, 214)
local WOOD = rgb(156, 106, 66)

-- =====================================================================
-- 2) PRIMÄRWAFFEN (B11.2)
-- =====================================================================

-- 1 PopRifle – Pop-Gewehr (Beispiel aus B11.8)
define(
	"PopRifle",
	"PopRifle",
	pal(CREAM, rgb(60, 178, 200), rgb(0, 230, 255), SILVER, CHARCOAL),
	points(at(0, 0.5, -3.0), at(0, 1.1, -0.3), at(0.3, 0.12, 0.35), at(0, 0.16, -1.5)),
	{
		blk("Body", v3(0.5, 0.6, 2.2), at(0, 0.45, -0.6)),
		blk("Detail", v3(0.34, 0.14, 1.5), at(0, 0.82, -0.6)),
		cylZ("Metal", 0.25, 1.2, at(0, 0.5, -2.25), { M = "Foil" }),
		cylZ("Tip", 0.36, 0.2, at(0, 0.5, -2.9), { N = "Tip" }),
		blk("Detail", v3(0.3, 0.7, 0.4), at(0, -0.12, -0.95, -8, 0, 0), { N = "Mag" }),
		blk("Grip", v3(0.28, 0.72, 0.36), at(0, -0.14, 0.1, -14, 0, 0)),
		wedge("Body", v3(0.42, 0.6, 1.0), at(0, 0.32, 1.0, 0, 180, 0)),
		blk("Detail", v3(0.18, 0.16, 0.34), at(0, 0.97, -0.3)),
		ball("Accent", 0.13, at(0, 1.08, -0.3)),
		blk("Accent", v3(0.05, 0.1, 1.6), at(-0.255, 0.48, -0.6)),
		blk("Accent", v3(0.05, 0.1, 1.6), at(0.255, 0.48, -0.6)),
		cylZ("Grip", 0.34, 0.55, at(0, 0.18, -1.5)),
	}
)

-- 2 BuzzSMG – Summ-MP (kompakt, langes Magazin)
define(
	"BuzzSMG",
	"BuzzSMG",
	pal(rgb(255, 212, 59), CHARCOAL, rgb(170, 255, 80), SILVER, CHARCOAL),
	points(at(0, 0.45, -1.82), at(0, 1.07, -0.15), at(0.28, 0.2, 0.3), at(0, -0.28, -0.75)),
	{
		blk("Body", v3(0.48, 0.55, 1.35), at(0, 0.42, -0.45)),
		blk("Detail", v3(0.5, 0.2, 0.9), at(0, 0.78, -0.35)),
		cylZ("Metal", 0.22, 0.55, at(0, 0.45, -1.4), { M = "Foil" }),
		cylZ("Tip", 0.32, 0.16, at(0, 0.45, -1.72), { N = "Tip" }),
		blk("Detail", v3(0.22, 0.95, 0.32), at(0, -0.3, -0.75), { N = "Mag" }),
		blk("Grip", v3(0.26, 0.65, 0.34), at(0, -0.12, 0.05, -12, 0, 0)),
		wedge("Body", v3(0.4, 0.45, 0.5), at(0, 0.36, 0.5, 0, 180, 0)),
		blk("Accent", v3(0.05, 0.1, 1.1), at(-0.245, 0.42, -0.45)),
		blk("Accent", v3(0.05, 0.1, 1.1), at(0.245, 0.42, -0.45)),
		blk("Detail", v3(0.14, 0.2, 0.14), at(0, 0.97, -0.15)),
		ball("Accent", 0.1, at(0, 1.07, -0.15)),
	}
)

-- 3 BurstBlaster – Salven-Blaster (Dreifach-Lauf)
define(
	"BurstBlaster",
	"BurstBlaster",
	pal(LILAC, NAVY, rgb(255, 80, 200), SILVER, CHARCOAL),
	points(at(0, 0.56, -2.55), at(0, 1.12, -0.2), at(0.3, 0.15, 0.3), at(0, 0.2, -1.3)),
	{
		blk("Body", v3(0.5, 0.62, 2.0), at(0, 0.45, -0.55)),
		blk("Detail", v3(0.56, 0.18, 1.2), at(0, 0.82, -0.75)),
		cylZ("Metal", 0.16, 0.9, at(-0.1, 0.5, -1.95), { M = "Foil" }),
		cylZ("Metal", 0.16, 0.9, at(0.1, 0.5, -1.95), { M = "Foil" }),
		cylZ("Metal", 0.16, 0.9, at(0, 0.66, -1.95), { M = "Foil" }),
		blk("Tip", v3(0.42, 0.38, 0.14), at(0, 0.56, -2.45), { N = "Tip" }),
		blk("Detail", v3(0.3, 0.75, 0.42), at(0, -0.14, -0.9, -6, 0, 0), { N = "Mag" }),
		blk("Grip", v3(0.28, 0.72, 0.36), at(0, -0.14, 0.1, -14, 0, 0)),
		wedge("Body", v3(0.44, 0.62, 0.95), at(0, 0.34, 0.92, 0, 180, 0)),
		blk("Accent", v3(0.05, 0.12, 1.7), at(-0.255, 0.45, -0.55)),
		blk("Accent", v3(0.05, 0.12, 1.7), at(0.255, 0.45, -0.55)),
		blk("Detail", v3(0.2, 0.18, 0.4), at(0, 1.0, -0.2)),
		ball("Accent", 0.12, at(0, 1.11, -0.2)),
	}
)

-- 4 Scatter – Streuer (Doppellauf-Pumpe)
define(
	"Scatter",
	"Scatter",
	pal(rgb(255, 104, 104), CREAM, rgb(255, 236, 80), SILVER, WOOD),
	points(at(0, 0.55, -2.52), at(0, 0.95, -0.75), at(0.34, 0.2, 0.3), at(0, 0.24, -1.45)),
	{
		blk("Body", v3(0.6, 0.62, 1.6), at(0, 0.45, -0.35)),
		cylZ("Metal", 0.24, 1.3, at(-0.13, 0.55, -1.75), { M = "Foil" }),
		cylZ("Metal", 0.24, 1.3, at(0.13, 0.55, -1.75), { M = "Foil" }),
		blk("Tip", v3(0.62, 0.34, 0.16), at(0, 0.55, -2.42), { N = "Tip" }),
		cylZ("Detail", 0.42, 0.7, at(0, 0.24, -1.45)),
		blk("Detail", v3(0.34, 0.4, 0.6), at(0, 0.05, -0.55), { N = "Mag" }),
		blk("Grip", v3(0.3, 0.72, 0.38), at(0, -0.14, 0.12, -16, 0, 0), { M = "Wood" }),
		wedge("Body", v3(0.5, 0.66, 1.0), at(0, 0.32, 0.95, 0, 180, 0)),
		blk("Accent", v3(0.64, 0.06, 0.6), at(0, 0.78, -0.35)),
		ball("Accent", 0.18, at(0, 0.86, -0.75)),
		blk("Detail", v3(0.06, 0.3, 1.2), at(-0.31, 0.45, -0.35)),
		blk("Detail", v3(0.06, 0.3, 1.2), at(0.31, 0.45, -0.35)),
	}
)

-- 5 Longshot – Fernschuss (Bolzen-Blaster mit Zielfernrohr)
define(
	"Longshot",
	"Longshot",
	pal(rgb(52, 78, 150), WHITE, rgb(0, 230, 255), SILVER, CHARCOAL),
	points(at(0, 0.48, -4.05), at(0, 0.98, 0.15), at(0.28, 0.15, 0.4), at(0, 0.25, -1.6)),
	{
		blk("Body", v3(0.46, 0.55, 2.6), at(0, 0.42, -0.75)),
		cylZ("Metal", 0.2, 1.8, at(0, 0.48, -2.95), { M = "Foil" }),
		cylZ("Tip", 0.3, 0.2, at(0, 0.48, -3.95), { N = "Tip" }),
		cylZ("Detail", 0.36, 1.3, at(0, 0.98, -0.6)),
		cylZ("Accent", 0.3, 0.04, at(0, 0.98, -1.26), { M = "Glass", T = 0.2 }),
		cylZ("Detail", 0.42, 0.25, at(0, 0.98, 0.0)),
		blk("Detail", v3(0.16, 0.2, 0.3), at(0, 0.78, -0.95)),
		blk("Detail", v3(0.16, 0.2, 0.3), at(0, 0.78, -0.25)),
		blk("Detail", v3(0.26, 0.45, 0.4), at(0, 0.0, -0.75), { N = "Mag" }),
		blk("Grip", v3(0.28, 0.7, 0.36), at(0, -0.14, 0.1, -14, 0, 0)),
		wedge("Body", v3(0.42, 0.7, 1.3), at(0, 0.25, 1.2, 0, 180, 0)),
		blk("Accent", v3(0.05, 0.1, 2.0), at(0.235, 0.42, -0.75)),
		cylX("Metal", 0.1, 0.35, at(0.32, 0.55, -0.1)),
	}
)

-- 6 PopRocket – Plopp-Rakete (Schulter-Rohr)
define(
	"PopRocket",
	"PopRocket",
	pal(rgb(96, 200, 118), SAND, rgb(255, 236, 80), SILVER, CHARCOAL),
	points(at(0, 0.62, -2.15), at(-0.4, 1.06, -0.6), at(0.36, 0.4, 0.2), at(0, 0.05, -1.1)),
	{
		cylZ("Body", 0.62, 2.8, at(0, 0.62, -0.6)),
		cylZ("Detail", 0.72, 0.3, at(0, 0.62, 0.75)),
		cylZ("Tip", 0.74, 0.22, at(0, 0.62, -2.0), { N = "Tip" }),
		ell("Metal", v3(0.42, 0.42, 0.5), at(0, 0.62, -1.85), { M = "Foil" }),
		blk("Grip", v3(0.28, 0.7, 0.36), at(0, -0.1, 0.05, -12, 0, 0)),
		blk("Grip", v3(0.26, 0.6, 0.32), at(0, 0.05, -1.1, -8, 0, 0)),
		blk("Detail", v3(0.2, 0.3, 0.6), at(-0.4, 0.85, -0.6)),
		ball("Accent", 0.12, at(-0.4, 1.04, -0.6)),
		cylZ("Accent", 0.66, 0.08, at(0, 0.62, -0.2)),
		cylZ("Detail", 0.4, 0.5, at(0, 0.62, 1.05), { N = "Mag" }),
	}
)

-- =====================================================================
-- 3) SEKUNDÄRWAFFEN (B11.3)
-- =====================================================================

-- 7 PipPistol – Pieps-Pistole
define(
	"PipPistol",
	"PipPistol",
	pal(PINK, WHITE, rgb(0, 230, 255), SILVER, CHARCOAL),
	points(at(0, 0.38, -1.2), at(0, 0.75, -0.1), at(0.18, 0.05, 0.2), at(-0.12, -0.15, 0.02)),
	{
		blk("Body", v3(0.3, 0.42, 1.0), at(0, 0.36, -0.32)),
		blk("Detail", v3(0.32, 0.14, 0.9), at(0, 0.62, -0.3)),
		cylZ("Metal", 0.16, 0.3, at(0, 0.38, -0.95), { M = "Foil" }),
		cylZ("Tip", 0.22, 0.12, at(0, 0.38, -1.12), { N = "Tip" }),
		blk("Grip", v3(0.26, 0.7, 0.34), at(0, -0.1, 0.05, -12, 0, 0)),
		blk("Detail", v3(0.2, 0.2, 0.26), at(0, -0.5, 0.12, -12, 0, 0), { N = "Mag" }),
		blk("Detail", v3(0.08, 0.2, 0.3), at(0, 0.05, -0.32)),
		blk("Accent", v3(0.04, 0.08, 0.8), at(-0.155, 0.36, -0.32)),
		blk("Accent", v3(0.04, 0.08, 0.8), at(0.155, 0.36, -0.32)),
		ball("Accent", 0.09, at(0, 0.73, -0.1)),
	}
)

-- 8 HandCannon – Hand-Kanone (Trommel = "Mag")
define(
	"HandCannon",
	"HandCannon",
	pal(rgb(86, 72, 132), SAND, rgb(190, 110, 255), SILVER, CHARCOAL),
	points(at(0, 0.5, -1.6), at(0, 0.8, -0.05), at(0.2, 0.05, 0.25), at(-0.12, -0.15, 0.02)),
	{
		blk("Body", v3(0.34, 0.46, 0.75), at(0, 0.38, -0.15)),
		mcyl("Detail", v3(0.46, 0.42, 0.46), at(0, 0.38, -0.45, 90, 0, 0), { N = "Mag" }),
		cylZ("Metal", 0.22, 0.9, at(0, 0.5, -1.0), { M = "Foil" }),
		blk("Metal", v3(0.1, 0.12, 0.9), at(0, 0.66, -1.0), { M = "Foil" }),
		cylZ("Tip", 0.3, 0.14, at(0, 0.5, -1.5), { N = "Tip" }),
		blk("Grip", v3(0.28, 0.75, 0.36), at(0, -0.12, 0.12, -18, 0, 0)),
		wedge("Detail", v3(0.12, 0.22, 0.2), at(0, 0.66, 0.2)),
		blk("Detail", v3(0.08, 0.22, 0.32), at(0, 0.08, -0.3)),
		blk("Accent", v3(0.04, 0.1, 0.6), at(-0.175, 0.38, -0.15)),
		blk("Accent", v3(0.04, 0.1, 0.6), at(0.175, 0.38, -0.15)),
		ball("Accent", 0.09, at(0, 0.78, -0.05)),
	}
)

-- 9 MiniScatter – Mini-Streuer (Kipplauf-Doppelflinte)
define(
	"MiniScatter",
	"MiniScatter",
	pal(rgb(110, 170, 255), CREAM, rgb(255, 236, 80), SILVER, WOOD),
	points(at(0, 0.42, -1.25), at(0, 0.66, -0.6), at(0.24, 0.1, 0.2), at(-0.12, -0.15, 0.02)),
	{
		blk("Body", v3(0.42, 0.4, 0.6), at(0, 0.36, -0.1)),
		cylZ("Metal", 0.2, 0.8, at(-0.1, 0.42, -0.75), { M = "Foil" }),
		cylZ("Metal", 0.2, 0.8, at(0.1, 0.42, -0.75), { M = "Foil" }),
		blk("Tip", v3(0.44, 0.24, 0.12), at(0, 0.42, -1.18), { N = "Tip" }),
		blk("Grip", v3(0.28, 0.68, 0.36), at(0, -0.1, 0.1, -20, 0, 0), { M = "Wood" }),
		blk("Detail", v3(0.36, 0.18, 0.22), at(0, 0.36, -0.42), { N = "Mag" }),
		blk("Detail", v3(0.08, 0.2, 0.28), at(0, 0.06, -0.2)),
		blk("Accent", v3(0.44, 0.05, 0.4), at(0, 0.57, -0.1)),
		ball("Accent", 0.08, at(0, 0.62, -0.6)),
		wedge("Detail", v3(0.12, 0.18, 0.18), at(0, 0.6, 0.18)),
	}
)

-- =====================================================================
-- 4) NAHKAMPF (B11.4)
-- =====================================================================

-- 10 BoxingGloves – ein Handschuh (Viewmodel baut ihn zweimal)
define(
	"BoxingGloves",
	"BoxingGloves",
	pal(rgb(232, 52, 64), WHITE, rgb(255, 236, 80), SILVER, WHITE),
	points(at(0, 0.05, -0.7), at(0, 0.5, -0.15), at(0, -0.3, 0.5), at(0, 0, 0)),
	{
		ell("Body", v3(0.85, 0.8, 1.0), at(0, 0.05, -0.15)),
		ell("Body", v3(0.42, 0.4, 0.55), at(-0.36, -0.05, -0.12)),
		ell("Body", v3(0.8, 0.3, 0.42), at(0, 0.25, -0.45)),
		mcyl("Detail", v3(0.7, 0.45, 0.7), at(0, 0, 0.42, 90, 0, 0), { N = "Mag" }),
		mcyl("Tip", v3(0.72, 0.1, 0.72), at(0, 0, 0.24, 90, 0, 0), { N = "Tip" }),
		blk("Accent", v3(0.1, 0.04, 0.4), at(0, 0.24, 0.42)),
		ell("Accent", v3(0.22, 0.12, 0.22), at(0.16, 0.36, -0.32)),
		blk("Detail", v3(0.74, 0.12, 0.2), at(0, -0.05, 0.62)),
		blk("Accent", v3(0.05, 0.3, 0.6), at(0.42, 0.05, -0.1)),
	}
)

-- 11 BonkHammer – Bonk-Hammer (Stiel nach oben, Kopf mit Gummiflächen)
define(
	"BonkHammer",
	"BonkHammer",
	pal(rgb(255, 204, 64), rgb(230, 60, 70), rgb(0, 230, 255), SILVER, WOOD),
	points(at(0, 1.75, -0.85), at(0, 1.0, 0), at(0.15, 0.2, 0), at(0, -0.22, 0)),
	{
		cylY("Grip", 0.2, 2.0, at(0, 0.6, 0), { M = "Wood" }),
		cylY("Tip", 0.26, 0.16, at(0, -0.42, 0), { N = "Tip" }),
		mcyl("Body", v3(0.9, 1.4, 0.9), at(0, 1.75, 0, 90, 0, 0)),
		mcyl("Detail", v3(0.95, 0.18, 0.95), at(0, 1.75, -0.72, 90, 0, 0)),
		mcyl("Detail", v3(0.95, 0.18, 0.95), at(0, 1.75, 0.72, 90, 0, 0)),
		mcyl("Accent", v3(0.92, 0.08, 0.92), at(0, 1.75, 0, 90, 0, 0)),
		blk("Detail", v3(0.26, 0.3, 0.26), at(0, 1.18, 0), { N = "Mag" }),
		cylY("Grip", 0.26, 0.5, at(0, 0, 0), { M = "Fabric", C = CHARCOAL }),
		blk("Accent", v3(0.02, 0.3, 0.6), at(0.46, 1.75, 0)),
		ball("Accent", 0.15, at(-0.46, 1.75, 0)),
	}
)

-- 12 LaserSword – Laserschwert (Klinge Neon nach oben)
define(
	"LaserSword",
	"LaserSword",
	pal(SILVER, CHARCOAL, rgb(90, 200, 255), SILVER, rgb(30, 30, 36)),
	points(at(0, 3.7, 0), at(0, 0.8, 0), at(0, -0.5, 0.05), at(0, -0.25, 0)),
	{
		cylY("Metal", 0.22, 0.9, at(0, 0.1, 0), { M = "Foil" }),
		cylY("Grip", 0.25, 0.5, at(0, 0, 0), { M = "Fabric" }),
		blk("Detail", v3(0.5, 0.12, 0.22), at(0, 0.6, 0)),
		cylY("Detail", 0.28, 0.14, at(0, -0.38, 0), { N = "Mag" }),
		cylY("Accent", 0.16, 3.0, at(0, 2.15, 0)),
		cylY("Accent", 0.26, 3.0, at(0, 2.15, 0), { T = 0.65 }),
		ball("Tip", 0.2, at(0, 3.68, 0), { N = "Tip" }),
		blk("Accent", v3(0.04, 0.3, 0.04), at(0.12, 0.1, 0)),
		cylY("Detail", 0.26, 0.08, at(0, 0.45, 0)),
		ball("Accent", 0.1, at(0, 0.25, -0.12)),
	}
)

-- =====================================================================
-- 5) UTILITY (B11.5)
-- =====================================================================

-- 13 PopGrenade – Plopp-Granate (Hebel = "Mag")
define(
	"PopGrenade",
	"PopGrenade",
	pal(rgb(100, 200, 120), CHARCOAL, rgb(170, 255, 80), SILVER, CHARCOAL),
	points(at(0, 0.25, -0.4), at(0, 0.6, 0), at(0, 0, 0), at(0, 0.25, -0.05)),
	{
		ball("Body", 0.55, at(0, 0.25, -0.05)),
		mcyl("Detail", v3(0.57, 0.06, 0.57), at(0, 0.25, -0.05)),
		mcyl("Detail", v3(0.57, 0.06, 0.57), at(0, 0.25, -0.05, 90, 0, 0)),
		mcyl("Tip", v3(0.26, 0.18, 0.26), at(0, 0.58, -0.05), { N = "Tip" }),
		blk("Metal", v3(0.08, 0.2, 0.18), at(0.18, 0.5, -0.05, 0, 0, -20), { N = "Mag", M = "Foil" }),
		mcyl("Metal", v3(0.18, 0.03, 0.18), at(-0.12, 0.68, -0.05, 0, 0, 90), { M = "Foil" }),
		ball("Accent", 0.12, at(0, 0.25, -0.33)),
		ball("Accent", 0.1, at(0, 0.25, 0.23)),
	}
)

-- 14 SmokeBomb – Rauchbombe (Dose)
define(
	"SmokeBomb",
	"SmokeBomb",
	pal(rgb(150, 160, 182), WHITE, rgb(220, 240, 255), SILVER, CHARCOAL),
	points(at(0, 0.3, -0.35), at(0, 0.7, 0), at(0, 0, 0), at(0, 0.3, -0.05)),
	{
		mcyl("Body", v3(0.42, 0.75, 0.42), at(0, 0.3, -0.05)),
		mcyl("Detail", v3(0.44, 0.08, 0.44), at(0, 0.5, -0.05)),
		mcyl("Detail", v3(0.44, 0.08, 0.44), at(0, 0.1, -0.05)),
		mcyl("Tip", v3(0.26, 0.14, 0.26), at(0, 0.74, -0.05), { N = "Tip" }),
		blk("Metal", v3(0.07, 0.4, 0.14), at(0.24, 0.45, -0.05), { N = "Mag", M = "Foil" }),
		mcyl("Metal", v3(0.16, 0.03, 0.16), at(-0.12, 0.82, -0.05, 0, 0, 90), { M = "Foil" }),
		blk("Accent", v3(0.05, 0.25, 0.05), at(0, 0.3, -0.27)),
		blk("Accent", v3(0.05, 0.25, 0.05), at(0, 0.3, 0.17)),
		mcyl("Detail", v3(0.36, 0.06, 0.36), at(0, -0.08, -0.05)),
	}
)

-- 15 MedFizz – Heil-Limo (Glasflasche mit Neon-Limo)
define(
	"MedFizz",
	"MedFizz",
	pal(rgb(255, 150, 196), WHITE, rgb(255, 80, 170), SILVER, CHARCOAL),
	points(at(0, 1.1, -0.05), at(0, 0.8, 0), at(0, 0, 0.2), at(0, 0.3, -0.05)),
	{
		mcyl("Body", v3(0.4, 0.8, 0.4), at(0, 0.3, -0.05), { M = "Glass", T = 0.4 }),
		mcyl("Accent", v3(0.34, 0.6, 0.34), at(0, 0.24, -0.05)),
		mcyl("Detail", v3(0.42, 0.3, 0.42), at(0, 0.3, -0.05)),
		ell("Body", v3(0.36, 0.3, 0.36), at(0, 0.76, -0.05), { M = "Glass", T = 0.4 }),
		mcyl("Body", v3(0.16, 0.22, 0.16), at(0, 0.96, -0.05), { M = "Glass", T = 0.4 }),
		mcyl("Tip", v3(0.2, 0.08, 0.2), at(0, 1.08, -0.05), { N = "Tip" }),
		ball("Accent", 0.12, at(0, 0.32, -0.26)),
		mcyl("Metal", v3(0.42, 0.04, 0.42), at(0, -0.1, -0.05), { N = "Mag", M = "Foil" }),
	}
)

-- =====================================================================
-- 6) ADMIN-WAFFEN (B11.7, ≤ 30 Teile + Partikel)
-- =====================================================================

-- 101 OrbitalLaser – weiß/gold mit rotem Neon-Kern
define(
	"OrbitalLaser",
	"OrbitalLaser",
	pal(WHITE, rgb(255, 200, 40), rgb(255, 50, 60), SILVER, CHARCOAL),
	points(at(0, 0.5, -3.2), at(0, 1.25, -0.4), at(0.32, 0.12, 0.35), at(0, 0.2, -1.5)),
	{
		blk("Body", v3(0.52, 0.6, 2.4), at(0, 0.45, -0.7)),
		blk("Detail", v3(0.56, 0.16, 1.8), at(0, 0.82, -0.7), { M = "Foil" }),
		cylZ("Metal", 0.3, 1.0, at(0, 0.5, -2.4), { M = "Foil" }),
		ell("Detail", v3(0.95, 0.95, 0.22), at(0, 0.5, -2.95)),
		cylZ("Tip", 0.4, 0.14, at(0, 0.5, -3.1), { N = "Tip" }),
		ball("Accent", 0.34, at(0, 0.5, -3.02)),
		blk("Grip", v3(0.28, 0.72, 0.36), at(0, -0.14, 0.1, -14, 0, 0)),
		blk("Detail", v3(0.32, 0.6, 0.45), at(0, -0.1, -0.95), { N = "Mag" }),
		wedge("Body", v3(0.44, 0.6, 1.0), at(0, 0.32, 1.0, 0, 180, 0)),
		blk("Accent", v3(0.05, 0.1, 2.0), at(-0.265, 0.45, -0.7)),
		blk("Accent", v3(0.05, 0.1, 2.0), at(0.265, 0.45, -0.7)),
		cylZ("Detail", 0.3, 0.9, at(0, 1.05, -0.6)),
		cylZ("Accent", 0.24, 0.05, at(0, 1.05, -1.06)),
		blk("Detail", v3(0.05, 0.4, 0.6), at(-0.35, 0.55, -1.6), { M = "Foil" }),
		blk("Detail", v3(0.05, 0.4, 0.6), at(0.35, 0.55, -1.6), { M = "Foil" }),
		ball("Accent", 0.12, at(0, 1.25, -0.4)),
	},
	{ { At = at(0, 0.5, -3.05), Color = rgb(255, 60, 60), Rate = 10, Size = 0.35 } }
)

-- 102 RocketMinigun – sechs Läufe im Kreis
do
	local parts: { PartSpec } = {
		cylZ("Body", 0.9, 0.7, at(0, 0.5, -0.6)),
		cylZ("Detail", 0.85, 0.1, at(0, 0.5, -2.2)),
		cylZ("Tip", 0.92, 0.12, at(0, 0.5, -2.45), { N = "Tip" }),
		cylZ("Detail", 0.8, 0.4, at(0, 0.5, 0.05)),
		blk("Grip", v3(0.28, 0.72, 0.36), at(0, -0.14, 0.1, -14, 0, 0)),
		blk("Grip", v3(0.15, 0.15, 0.9), at(0, 1.05, -0.6)),
		blk("Detail", v3(0.5, 0.55, 0.5), at(-0.55, 0.25, -0.5), { N = "Mag" }),
		blk("Accent", v3(0.05, 0.1, 0.6), at(-0.46, 0.5, -0.6)),
		blk("Accent", v3(0.05, 0.1, 0.6), at(0.46, 0.5, -0.6)),
		ball("Accent", 0.12, at(0, 1.2, -0.3)),
	}
	for k = 0, 5 do
		local a = k * math.pi / 3
		table.insert(parts, cylZ("Metal", 0.18, 1.6, at(math.cos(a) * 0.28, 0.5 + math.sin(a) * 0.28, -1.45)))
	end
	define(
		"RocketMinigun",
		"RocketMinigun",
		pal(CHARCOAL, rgb(220, 60, 60), rgb(255, 120, 60), SILVER, CHARCOAL),
		points(at(0, 0.5, -2.55), at(0, 1.22, -0.3), at(0.48, 0.2, 0.2), at(0, 1.05, -0.6)),
		parts,
		{ { At = at(0, 0.5, -2.5), Color = rgb(255, 140, 60), Rate = 8, Size = 0.3 } }
	)
end

-- 103 BlackHoleCannon – violetter Neon-Kern mit Ringen
define(
	"BlackHoleCannon",
	"BlackHoleCannon",
	pal(rgb(70, 40, 120), rgb(20, 16, 34), rgb(190, 90, 255), SILVER, CHARCOAL),
	points(at(0, 0.5, -2.45), at(0, 1.2, -0.3), at(0.36, 0.2, 0.3), at(0, 0.05, -1.1)),
	{
		cylZ("Body", 0.6, 2.0, at(0, 0.5, -0.6)),
		ball("Accent", 0.75, at(0, 0.5, -1.9)),
		mcyl("Detail", v3(1.0, 0.08, 1.0), at(0, 0.5, -1.9, 90, 0, 0)),
		mcyl("Detail", v3(1.0, 0.08, 1.0), at(0, 0.5, -1.9, 0, 0, 90)),
		cylZ("Tip", 0.7, 0.15, at(0, 0.5, -2.35), { N = "Tip" }),
		cylZ("Detail", 0.7, 0.3, at(0, 0.5, 0.45)),
		blk("Grip", v3(0.28, 0.72, 0.36), at(0, -0.14, 0.1, -14, 0, 0)),
		blk("Grip", v3(0.26, 0.6, 0.32), at(0, 0.05, -1.1, -8, 0, 0)),
		blk("Detail", v3(0.35, 0.5, 0.4), at(0, -0.05, -0.55), { N = "Mag" }),
		blk("Accent", v3(0.05, 0.1, 1.6), at(-0.31, 0.5, -0.6)),
		blk("Accent", v3(0.05, 0.1, 1.6), at(0.31, 0.5, -0.6)),
		cylZ("Detail", 0.25, 0.7, at(0, 1.0, -0.4)),
		ball("Accent", 0.1, at(0, 1.18, -0.3)),
	},
	{ { At = at(0, 0.5, -1.9), Color = rgb(190, 90, 255), Rate = 14, Size = 0.4 } }
)

-- 104 LightningRifle – gelbe Neon-Spulen
define(
	"LightningRifle",
	"LightningRifle",
	pal(NAVY, rgb(80, 96, 160), rgb(255, 230, 60), SILVER, CHARCOAL),
	points(at(0, 0.5, -3.15), at(0, 1.1, -0.3), at(0.3, 0.12, 0.35), at(0, 0.2, -1.4)),
	{
		blk("Body", v3(0.48, 0.58, 2.2), at(0, 0.45, -0.6)),
		cylZ("Metal", 0.2, 1.4, at(0, 0.5, -2.3), { M = "Foil" }),
		mcyl("Accent", v3(0.42, 0.1, 0.42), at(0, 0.5, -1.85, 90, 0, 0)),
		mcyl("Accent", v3(0.42, 0.1, 0.42), at(0, 0.5, -2.25, 90, 0, 0)),
		mcyl("Accent", v3(0.42, 0.1, 0.42), at(0, 0.5, -2.65, 90, 0, 0)),
		cylZ("Tip", 0.3, 0.16, at(0, 0.5, -3.05), { N = "Tip" }),
		blk("Grip", v3(0.28, 0.72, 0.36), at(0, -0.14, 0.1, -14, 0, 0)),
		wedge("Body", v3(0.42, 0.58, 0.95), at(0, 0.32, 0.95, 0, 180, 0)),
		blk("Detail", v3(0.32, 0.6, 0.45), at(0, -0.1, -0.9), { N = "Mag" }),
		blk("Accent", v3(0.05, 0.1, 0.45), at(-0.25, 0.55, -0.9, 30, 0, 0)),
		blk("Accent", v3(0.05, 0.1, 0.45), at(-0.25, 0.4, -0.45, -30, 0, 0)),
		blk("Accent", v3(0.05, 0.1, 0.45), at(0.25, 0.55, -0.9, 30, 0, 0)),
		blk("Detail", v3(0.3, 0.14, 1.4), at(0, 0.8, -0.6)),
		ball("Accent", 0.12, at(0, 0.95, -0.3)),
	},
	{ { At = at(0, 0.5, -2.25), Color = rgb(255, 230, 60), Rate = 10, Size = 0.3 } }
)

-- =====================================================================
-- 7) SKINS (B19 – 8 Stück, gleiche Attachments wie die Basis-Waffe)
-- =====================================================================

-- Wasser-Blaster (PopRifle): durchsichtiger Tank oben
define(
	"S_PopRifle_WaterBlaster",
	"PopRifle",
	pal(rgb(70, 150, 255), rgb(255, 220, 60), rgb(90, 200, 255), WHITE, rgb(255, 220, 60)),
	skinPoints("PopRifle", { Sight = at(0, 1.3, -0.6), Muzzle = at(0, 0.45, -2.68) }),
	{
		blk("Body", v3(0.5, 0.6, 2.0), at(0, 0.42, -0.6)),
		ell("Detail", v3(0.55, 0.5, 1.3), at(0, 0.95, -0.4), { M = "Glass", T = 0.35, C = rgb(170, 220, 255) }),
		ell("Accent", v3(0.42, 0.28, 1.1), at(0, 0.88, -0.4)),
		cylZ("Metal", 0.18, 0.9, at(0, 0.45, -2.05)),
		cylZ("Tip", 0.28, 0.18, at(0, 0.45, -2.55), { N = "Tip" }),
		cylZ("Grip", 0.36, 0.6, at(0, 0.12, -1.4)),
		blk("Grip", v3(0.28, 0.72, 0.36), at(0, -0.14, 0.1, -14, 0, 0)),
		wedge("Body", v3(0.42, 0.55, 0.9), at(0, 0.3, 0.9, 0, 180, 0)),
		blk("Detail", v3(0.3, 0.55, 0.36), at(0, -0.08, -0.9), { N = "Mag" }),
		cylY("Metal", 0.18, 0.12, at(0, 1.22, 0.05)),
		blk("Accent", v3(0.05, 0.1, 1.5), at(-0.255, 0.42, -0.6)),
		blk("Accent", v3(0.05, 0.1, 1.5), at(0.255, 0.42, -0.6)),
	}
)

-- Karotten-Kanone (PopRifle): Karotte mit Blättern
define(
	"S_PopRifle_CarrotCannon",
	"PopRifle",
	pal(rgb(240, 140, 50), rgb(70, 170, 70), rgb(140, 255, 120), rgb(200, 120, 40), rgb(120, 80, 50)),
	skinPoints("PopRifle", { Muzzle = at(0, 0.5, -2.75) }),
	{
		cylZ("Body", 0.62, 1.2, at(0, 0.5, -0.3)),
		cylZ("Body", 0.5, 0.8, at(0, 0.5, -1.25)),
		cylZ("Body", 0.36, 0.6, at(0, 0.5, -1.92)),
		cylZ("Metal", 0.24, 0.4, at(0, 0.5, -2.4)),
		cylZ("Tip", 0.3, 0.14, at(0, 0.5, -2.66), { N = "Tip" }),
		wedge("Detail", v3(0.12, 0.7, 0.5), at(0, 1.0, 0.45, 20, 0, 0)),
		wedge("Detail", v3(0.12, 0.6, 0.45), at(0.18, 0.95, 0.42, 20, 0, -25)),
		wedge("Detail", v3(0.12, 0.6, 0.45), at(-0.18, 0.95, 0.42, 20, 0, 25)),
		blk("Grip", v3(0.28, 0.72, 0.36), at(0, -0.14, 0.1, -14, 0, 0)),
		blk("Detail", v3(0.26, 0.6, 0.36), at(0, -0.06, -0.95), { N = "Mag" }),
		mcyl("Accent", v3(0.64, 0.05, 0.64), at(0, 0.5, -0.75, 90, 0, 0)),
		mcyl("Accent", v3(0.52, 0.05, 0.52), at(0, 0.5, -1.55, 90, 0, 0)),
		blk("Detail", v3(0.16, 0.16, 0.3), at(0, 0.92, -0.3)),
		ball("Accent", 0.12, at(0, 1.06, -0.3)),
	}
)

-- Föhn (BuzzSMG): runder Körper, Düse, Lüftungsgitter
define(
	"S_BuzzSMG_HairDryer",
	"BuzzSMG",
	pal(PINK, WHITE, rgb(255, 120, 200), SILVER, WHITE),
	skinPoints("BuzzSMG", { Muzzle = at(0, 0.5, -1.62), Sight = at(0, 1.02, -0.3) }),
	{
		mcyl("Body", v3(0.7, 1.0, 0.7), at(0, 0.5, -0.4, 90, 0, 0)),
		mcyl("Detail", v3(0.72, 0.1, 0.72), at(0, 0.5, 0.12, 90, 0, 0)),
		mcyl("Metal", v3(0.4, 0.6, 0.4), at(0, 0.5, -1.15, 90, 0, 0)),
		mcyl("Tip", v3(0.46, 0.12, 0.46), at(0, 0.5, -1.5, 90, 0, 0), { N = "Tip" }),
		blk("Grip", v3(0.28, 0.75, 0.36), at(0, -0.1, 0.0, -8, 0, 0)),
		mcyl("Detail", v3(0.06, 0.6, 0.06), at(0, -0.55, 0.2), { N = "Mag" }),
		blk("Accent", v3(0.5, 0.04, 0.04), at(0, 0.5, 0.18)),
		blk("Accent", v3(0.04, 0.5, 0.04), at(0, 0.5, 0.18)),
		blk("Accent", v3(0.05, 0.12, 0.2), at(0.2, 0.1, -0.05)),
		ball("Accent", 0.1, at(0, 0.9, -0.3)),
	}
)

-- Schaumbad (Scatter): Wannen-Körper mit Seifenblasen
define(
	"S_Scatter_BubbleBath",
	"Scatter",
	pal(WHITE, MINT, rgb(140, 230, 255), SILVER, MINT),
	skinPoints("Scatter", { Muzzle = at(0, 0.5, -2.2), Sight = at(0, 1.08, -0.6) }),
	{
		ell("Body", v3(0.8, 0.6, 1.8), at(0, 0.45, -0.5)),
		mcyl("Detail", v3(0.82, 0.08, 1.82), at(0, 0.7, -0.5)),
		cylZ("Metal", 0.26, 1.0, at(0, 0.5, -1.6), { M = "Foil" }),
		cylZ("Tip", 0.34, 0.14, at(0, 0.5, -2.12), { N = "Tip" }),
		ball("Accent", 0.32, at(0.15, 0.88, -0.2), { M = "Glass", T = 0.45 }),
		ball("Accent", 0.24, at(-0.18, 0.86, -0.7), { M = "Glass", T = 0.45 }),
		ball("Accent", 0.18, at(0.05, 1.0, -0.6), { M = "Glass", T = 0.45 }),
		blk("Grip", v3(0.3, 0.72, 0.38), at(0, -0.14, 0.12, -16, 0, 0)),
		mcyl("Detail", v3(0.4, 0.5, 0.4), at(0, 0.1, -1.4, 90, 0, 0)),
		blk("Detail", v3(0.3, 0.3, 0.5), at(0, 0.08, -0.5), { N = "Mag" }),
		ell("Metal", v3(0.16, 0.16, 0.3), at(0.35, 0.3, 0.25), { M = "Foil" }),
	}
)

-- Poolnudel (Longshot): lange Schaumstoff-Nudel
define(
	"S_Longshot_PoolNoodle",
	"Longshot",
	pal(rgb(255, 100, 190), rgb(255, 230, 90), rgb(120, 255, 200), SILVER, rgb(80, 80, 96)),
	skinPoints("Longshot", { Muzzle = at(0, 0.48, -3.9) }),
	{
		mcyl("Body", v3(0.45, 3.6, 0.45), at(0, 0.48, -1.95, 90, 0, 0), { M = "Fabric" }),
		mcyl("Detail", v3(0.47, 0.12, 0.47), at(0, 0.48, -1.0, 90, 0, 0)),
		mcyl("Detail", v3(0.47, 0.12, 0.47), at(0, 0.48, -2.6, 90, 0, 0)),
		mcyl("Tip", v3(0.47, 0.14, 0.47), at(0, 0.48, -3.78, 90, 0, 0), { N = "Tip" }),
		cylZ("Detail", 0.34, 1.2, at(0, 0.98, -0.6)),
		cylZ("Accent", 0.28, 0.04, at(0, 0.98, -1.21), { M = "Glass", T = 0.2 }),
		cylZ("Detail", 0.4, 0.22, at(0, 0.98, 0.0)),
		blk("Grip", v3(0.28, 0.7, 0.36), at(0, -0.14, 0.1, -14, 0, 0)),
		blk("Detail", v3(0.26, 0.4, 0.36), at(0, 0.05, -0.75), { N = "Mag" }),
		mcyl("Body", v3(0.42, 0.9, 0.42), at(0, 0.36, 0.6, 90, 0, 0), { M = "Fabric" }),
		blk("Grip", v3(0.16, 0.2, 0.3), at(0, 0.78, -0.6)),
	}
)

-- Baguette (BonkHammer): knuspriges Brot als Hammerkopf
define(
	"S_BonkHammer_Baguette",
	"BonkHammer",
	pal(rgb(214, 160, 92), rgb(246, 222, 170), rgb(255, 240, 160), SILVER, rgb(196, 140, 80)),
	skinPoints("BonkHammer", { Muzzle = at(0, 1.8, -1.25) }),
	{
		cylY("Grip", 0.22, 1.9, at(0, 0.55, 0), { M = "Wood" }),
		cylY("Tip", 0.26, 0.16, at(0, -0.42, 0), { N = "Tip" }),
		ell("Body", v3(0.62, 0.62, 2.4), at(0, 1.8, 0)),
		ell("Detail", v3(0.18, 0.08, 0.36), at(0, 2.08, -0.65, 0, 20, 0)),
		ell("Detail", v3(0.18, 0.08, 0.36), at(0, 2.1, 0, 0, 20, 0)),
		ell("Detail", v3(0.18, 0.08, 0.36), at(0, 2.08, 0.65, 0, 20, 0)),
		blk("Detail", v3(0.26, 0.26, 0.26), at(0, 1.42, 0), { N = "Mag" }),
		cylY("Grip", 0.27, 0.5, at(0, 0, 0), { M = "Fabric", C = rgb(200, 60, 60) }),
		ball("Accent", 0.1, at(0.3, 1.8, 0.9)),
	}
)

-- Gummiente (PopGrenade): Schnabel = orange Spitze
define(
	"S_PopGrenade_RubberDuck",
	"PopGrenade",
	pal(rgb(255, 220, 50), CHARCOAL, rgb(255, 255, 200), SILVER, CHARCOAL),
	skinPoints("PopGrenade", nil),
	{
		ell("Body", v3(0.6, 0.45, 0.7), at(0, 0.2, -0.02)),
		ball("Body", 0.38, at(0, 0.52, -0.2)),
		wedge("Tip", v3(0.2, 0.08, 0.18), at(0, 0.48, -0.44, 0, 180, 0), { N = "Tip" }),
		ball("Detail", 0.07, at(0.11, 0.6, -0.34)),
		ball("Detail", 0.07, at(-0.11, 0.6, -0.34)),
		ell("Body", v3(0.3, 0.18, 0.4), at(0.24, 0.24, 0.02, 0, 0, -20), { N = "Mag" }),
		ell("Body", v3(0.3, 0.18, 0.4), at(-0.24, 0.24, 0.02, 0, 0, 20)),
		corner("Body", v3(0.2, 0.22, 0.2), at(0, 0.36, 0.3)),
		ell("Accent", v3(0.08, 0.04, 0.08), at(0.06, 0.66, -0.28)),
	}
)

-- Strahlenkanone (PipPistol): Retro-Ringe und Neon-Kolben
define(
	"S_PipPistol_RayGun",
	"PipPistol",
	pal(rgb(200, 210, 230), rgb(120, 70, 200), rgb(80, 255, 170), SILVER, CHARCOAL),
	skinPoints("PipPistol", { Muzzle = at(0, 0.4, -1.3) }),
	{
		ell("Body", v3(0.46, 0.5, 0.8), at(0, 0.4, -0.2), { M = "Foil" }),
		cylZ("Metal", 0.16, 0.6, at(0, 0.4, -0.85), { M = "Foil" }),
		mcyl("Detail", v3(0.4, 0.06, 0.4), at(0, 0.4, -0.72, 90, 0, 0)),
		mcyl("Detail", v3(0.32, 0.06, 0.32), at(0, 0.4, -0.95, 90, 0, 0)),
		cylZ("Tip", 0.22, 0.12, at(0, 0.4, -1.2), { N = "Tip" }),
		ball("Accent", 0.26, at(0, 0.72, 0.0)),
		blk("Grip", v3(0.26, 0.7, 0.34), at(0, -0.1, 0.05, -12, 0, 0)),
		wedge("Detail", v3(0.05, 0.3, 0.35), at(0.2, 0.55, 0.05)),
		wedge("Detail", v3(0.05, 0.3, 0.35), at(-0.2, 0.55, 0.05)),
		blk("Detail", v3(0.2, 0.2, 0.26), at(0, -0.5, 0.12, -12, 0, 0), { N = "Mag" }),
		ball("Accent", 0.08, at(0, 0.62, -0.5)),
	}
)

-- =====================================================================
-- 8) ERSATZ-BLASTER (unbekannte Keys: nie Fehler, immer etwas in der Hand)
-- =====================================================================
define(
	"Fallback",
	"Fallback",
	pal(MINT, CHARCOAL, rgb(0, 230, 255), SILVER, CHARCOAL),
	points(at(0, 0.45, -1.9), at(0, 0.95, -0.3), at(0.28, 0.1, 0.3), at(0, 0.15, -1.1)),
	{
		blk("Body", v3(0.45, 0.55, 1.6), at(0, 0.42, -0.45)),
		cylZ("Metal", 0.22, 0.6, at(0, 0.45, -1.5), { M = "Foil" }),
		cylZ("Tip", 0.3, 0.16, at(0, 0.45, -1.85), { N = "Tip" }),
		blk("Detail", v3(0.26, 0.6, 0.34), at(0, -0.1, -0.75), { N = "Mag" }),
		blk("Grip", v3(0.26, 0.7, 0.34), at(0, -0.12, 0.08, -14, 0, 0)),
		blk("Detail", v3(0.3, 0.12, 1.0), at(0, 0.76, -0.45)),
		ball("Accent", 0.11, at(0, 0.88, -0.3)),
		blk("Accent", v3(0.05, 0.1, 1.2), at(0.235, 0.42, -0.45)),
	}
)

-- =====================================================================
-- 9) BAUEN
-- =====================================================================
local MATERIALS: { [string]: Enum.Material } = {
	SmoothPlastic = Enum.Material.SmoothPlastic,
	Plastic = Enum.Material.Plastic,
	Neon = Enum.Material.Neon,
	Foil = Enum.Material.Foil,
	Glass = Enum.Material.Glass,
	Metal = Enum.Material.Metal,
	DiamondPlate = Enum.Material.DiamondPlate,
	Fabric = Enum.Material.Fabric,
	Wood = Enum.Material.Wood,
	WoodPlanks = Enum.Material.WoodPlanks,
	Marble = Enum.Material.Marble,
	Granite = Enum.Material.Granite,
	Concrete = Enum.Material.Concrete,
	ForceField = Enum.Material.ForceField,
	Pebble = Enum.Material.Pebble,
} -- bewusst ohne "Ice" (Muss-Regel 11)

local ROLE_MATERIAL: { [string]: Enum.Material } = {
	Body = Enum.Material.SmoothPlastic,
	Detail = Enum.Material.SmoothPlastic,
	Accent = Enum.Material.Neon,
	Metal = Enum.Material.Foil,
	Grip = Enum.Material.SmoothPlastic,
	Tip = Enum.Material.Neon,
}

local FALLBACK_COLOR = rgb(200, 200, 210)

local function makePart(shape: string): BasePart
	if shape == "Wedge" then
		return Instance.new("WedgePart")
	elseif shape == "CornerWedge" then
		return Instance.new("CornerWedgePart")
	end
	local part = Instance.new("Part")
	if shape == "Cylinder" then
		part.Shape = Enum.PartType.Cylinder
	elseif shape == "Ball" then
		part.Shape = Enum.PartType.Ball
	elseif shape == "MeshSphere" or shape == "MeshCylinder" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = if shape == "MeshSphere" then Enum.MeshType.Sphere else Enum.MeshType.Cylinder
		mesh.Parent = part
	end
	return part
end

local function scaled(cf: CFrame, scale: number): CFrame
	if scale == 1 then
		return cf
	end
	return CFrame.new(cf.Position * scale) * cf.Rotation
end

-- Skin-Ids -> Waffe (nil = kein Skin)
function WeaponModels.SkinBase(id: string): string?
	local s = Specs[id]
	if s and s.Base ~= id then
		return s.Base
	end
	return nil
end

function WeaponModels.HasRecipe(key: string): boolean
	return type(key) == "string" and key ~= "Fallback" and Recipes[key] ~= nil
end

-- Welches Rezept gilt? (Skin nur, wenn er zur Waffe passt)
local function resolve(key: string, skin: string?): (string, string, string)
	local weaponKey = key
	local recipeKey = key
	local skinUsed = ""
	local base = WeaponModels.SkinBase(key)
	if base then
		-- direkt eine Skin-Id übergeben (z. B. Shop-Vorschau)
		weaponKey = base
		skinUsed = key
	elseif type(skin) == "string" and skin ~= "" and WeaponModels.SkinBase(skin) == key then
		recipeKey = skin
		skinUsed = skin
	end
	if Recipes[recipeKey] == nil then
		recipeKey = "Fallback"
	end
	return weaponKey, recipeKey, skinUsed
end

function WeaponModels.Build(key: string, opts: BuildOpts?): Model
	local o: BuildOpts = opts or {}
	local scale = 1
	if type(o.Scale) == "number" and o.Scale == o.Scale then
		scale = math.clamp(o.Scale, 0.1, 4)
	end
	local viewmodel = o.Viewmodel == true
	local weaponKey, recipeKey, skinUsed = resolve(if type(key) == "string" then key else "Fallback", o.Skin)
	local recipe = Recipes[recipeKey]
	local info = Specs[recipeKey]

	local model = Instance.new("Model")
	model.Name = weaponKey
	model:SetAttribute("WeaponKey", weaponKey)
	model:SetAttribute("Skin", skinUsed)
	model:SetAttribute("Recipe", recipeKey)

	local primary: BasePart? = nil
	local parts: { BasePart } = {}
	for index, ps in ipairs(recipe) do
		local part = makePart(ps.Shape)
		part.Size = ps.Size * scale
		part.CFrame = scaled(ps.Offset, scale)
		if ps.Role == "Tip" then
			-- orange Sicherheitsspitze: immer gleich, nie von Wraps verändert
			part.Color = WeaponModels.TipColor
			part.Material = Enum.Material.Neon
		else
			part.Color = ps.Color or info.Palette[ps.Role] or FALLBACK_COLOR
			local material = if ps.Material then MATERIALS[ps.Material] else nil
			part.Material = material or ROLE_MATERIAL[ps.Role] or Enum.Material.SmoothPlastic
		end
		if ps.Transparency then
			part.Transparency = math.clamp(ps.Transparency, 0, 0.9)
		end
		part.Name = ps.Name or ps.Role
		part:SetAttribute("Role", ps.Role)
		part:SetAttribute("Index", index)
		part.Anchored = viewmodel
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Massless = true
		part.Parent = model
		table.insert(parts, part)
		if primary == nil and ps.Role == "Body" then
			primary = part
		end
	end
	local root: BasePart = primary or parts[1]
	model.PrimaryPart = root

	-- Attachments (Grip/Muzzle/Sight/Charm/Support) im PrimaryPart
	for name, cf in pairs(info.Points) do
		local attachment = Instance.new("Attachment")
		attachment.Name = name
		attachment.CFrame = root.CFrame:ToObjectSpace(scaled(cf, scale))
		attachment.Parent = root
	end

	-- Admin-Waffen: Neon-Funken (ParticleEmitter, Textur aus ASSETS.md)
	if info.Emitters then
		for i, e in ipairs(info.Emitters) do
			local attachment = Instance.new("Attachment")
			attachment.Name = "Fx" .. i
			attachment.CFrame = root.CFrame:ToObjectSpace(scaled(e.At, scale))
			attachment.Parent = root
			local emitter = Instance.new("ParticleEmitter")
			emitter.Texture = SPARKLE_TEXTURE
			emitter.Color = ColorSequence.new(e.Color)
			emitter.LightEmission = 1
			emitter.Rate = e.Rate
			emitter.Lifetime = NumberRange.new(0.3, 0.6)
			emitter.Speed = NumberRange.new(0.4, 1.4)
			emitter.SpreadAngle = Vector2.new(180, 180)
			emitter.Size = NumberSequence.new(e.Size * scale, 0)
			emitter.Transparency = NumberSequence.new(0.1, 1)
			emitter.Parent = attachment
		end
	end

	-- Ohne Viewmodel: alles an den PrimaryPart schweißen (CharacterService schweißt den an die Hand)
	if not viewmodel then
		for _, part in ipairs(parts) do
			if part ~= root then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = part
				weld.Parent = part
			end
		end
	end

	model.WorldPivot = scaled(info.Points.Grip or CFrame.identity, scale)
	return model
end

return WeaponModels
