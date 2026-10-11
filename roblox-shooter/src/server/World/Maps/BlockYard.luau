--!strict
-- =====================================================================
--  CLUTCH CLASH – Map "BlockYard" / Bauklotz-Hof (Server/World/Maps/BlockYard)
--  Besitzer: WP2 (Welt). Vertrag: DESIGN.md B8.3.2 (Koordinaten exakt aus der Tabelle).
--  M, 80×120, Wände 16 · Teams 1–4 · inkl. 12 FFA-Spawns.
--  Datei beschreibt die A-Hälfte (z < 0); MapKit spiegelt alles ohne Center/Mirror=false.
--  Zusätzlich (A4-Optik): Deko-Fliesen, Teamfarben-Spawnplatten, Spielzeug-Noppen auf den
--  Buchstaben-Klötzen, Wandstreifen.
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local MapKit = require(script.Parent.Parent:WaitForChild("MapKit"))

local V = Vector3.new

local parts: { Types.MapPart } = {
	-- B8.3.2 Tabelle
	{ Shape = "Block", Tag = "Floor", Pos = V(0, -0.5, 0), Size = V(80, 1, 120), Color = "Cream", Center = true },
	{ Shape = "Block", Tag = "Wall", Pos = V(0, 8, -61), Size = V(84, 16, 2), Color = "White", Center = true },
	{ Shape = "Block", Tag = "Wall", Pos = V(0, 8, 61), Size = V(84, 16, 2), Color = "White", Center = true },
	{ Shape = "Block", Tag = "Wall", Pos = V(-41, 8, 0), Size = V(2, 16, 120), Color = "White", Center = true },
	{ Shape = "Block", Tag = "Wall", Pos = V(41, 8, 0), Size = V(2, 16, 120), Color = "White", Center = true },
	{ Shape = "Block", Tag = "Tower", Pos = V(0, 4, 0), Size = V(16, 8, 16), Color = "Lilac", Center = true },
	{ Shape = "Block", Tag = "Parapet", Pos = V(-7.5, 9, 0), Size = V(1, 2, 16), Color = "Charcoal", Center = true },
	{ Shape = "Block", Tag = "Parapet", Pos = V(7.5, 9, 0), Size = V(1, 2, 16), Color = "Charcoal", Center = true },
	{ Shape = "Wedge", Tag = "Ramp", Pos = V(0, 4, -15), Size = V(6, 8, 14), HighEnd = -8, Color = "Lilac" },
	{
		Shape = "Block",
		Tag = "Letter",
		Pos = V(-24, 4, -32),
		Size = V(8, 8, 8),
		Color = Color3.fromRGB(255, 90, 90),
		Text = "A",
	},
	{
		Shape = "Block",
		Tag = "Letter",
		Pos = V(22, 3, -40),
		Size = V(6, 6, 6),
		Color = Color3.fromRGB(60, 140, 255),
		Text = "B",
	},
	{
		Shape = "Block",
		Tag = "Letter",
		Pos = V(-8, 2, -46),
		Size = V(4, 4, 4),
		Color = Color3.fromRGB(255, 210, 40),
		Text = "C",
	},
	{ Shape = "Block", Tag = "Alley", Pos = V(-32, 4, -22), Size = V(2, 8, 10), Color = "Mint" },
	{ Shape = "Block", Tag = "Alley", Pos = V(-32, 4, -2), Size = V(2, 8, 10), Color = "Mint" },
	{ Shape = "Block", Tag = "Lintel", Pos = V(-32, 7, -12), Size = V(2, 2, 10), Color = "Mint" },
	{ Shape = "Block", Tag = "Cover", Pos = V(12, 1.5, -22), Size = V(8, 3, 2), Color = "Sand" },
	{ Shape = "Block", Tag = "Cover", Pos = V(-14, 1.5, -16), Size = V(2, 3, 8), Color = "Sand" },
	{ Shape = "Block", Tag = "Crate", Pos = V(28, 2, -18), Size = V(4, 4, 4), Color = "Sand" },
	{ Shape = "Block", Tag = "Crate", Pos = V(24, 2, -54), Size = V(4, 4, 4), Color = "Sand" },
	{ Shape = "Block", Tag = "Crate", Pos = V(-20, 2, -52), Size = V(4, 4, 4), Color = "Sand" },

	-- Optik (reine Deko)
	{ Shape = "Block", Tag = "DecoSpawnPlate", Pos = V(0, 0.05, -54), Size = V(26, 0.1, 6), Color = "TeamA" },
	{ Shape = "Block", Tag = "DecoBand", Pos = V(0, 4, -59.9), Size = V(80, 1.2, 0.2), Color = "Pink" },
	{ Shape = "Block", Tag = "DecoBand", Pos = V(-39.9, 4, -30), Size = V(0.2, 1.2, 60), Color = "Mint" },
}

-- Spielzeug-Noppen auf den Buchstaben-Klötzen (oben auf der Lippe, Höhe 0.5)
local function studs(center: Vector3, half: number, offset: number, color: Color3)
	for _, dx in ipairs({ -offset, offset }) do
		for _, dz in ipairs({ -offset, offset }) do
			table.insert(parts, {
				Shape = "Cylinder",
				Tag = "DecoStud",
				Pos = V(center.X + dx, center.Y + half + 0.2 + 0.25, center.Z + dz),
				Size = V(1.6, 0.5, 1.6),
				Color = color,
			})
		end
	end
end
studs(V(-24, 4, -32), 4, 2, Color3.fromRGB(255, 120, 120))
studs(V(22, 3, -40), 3, 1.5, Color3.fromRGB(100, 165, 255))
studs(V(-8, 2, -46), 2, 1, Color3.fromRGB(255, 225, 90))

-- Schachbrett-Fliesen 10×10 (8×12 Felder -> punktsymmetrisch)
for _, tile in ipairs(MapKit.Checker(Vector2.new(-40, -60), Vector2.new(40, 60), 10, 0, "CreamDark")) do
	table.insert(parts, tile)
end

-- Kulisse: Wand-Lisenen, Spielzeug-Stapel hinter den Mauern, Ballons (nur Deko)
for _, piece in
	ipairs(MapKit.Scenery({
		Size = V(80, 16, 120),
		WallHeight = 16,
		Seed = 23,
		Colors = { "Red", "Blue", "Yellow", "Mint", "Lilac" },
		Pilaster = "Lilac",
		Balloons = 4,
	}))
do
	table.insert(parts, piece)
end

local layout: Types.MapLayout = {
	Key = "BlockYard",
	Size = V(80, 16, 120),
	WallHeight = 16,
	Parts = parts,
	SpawnsA = { V(-9, 3, -54), V(-3, 3, -54), V(3, 3, -54), V(9, 3, -54) },
	FFA = {
		V(-27, 3, -50),
		V(27, 3, -50),
		V(-27, 3, 50),
		V(27, 3, 50),
		V(0, 3, -56),
		V(0, 3, 56),
		V(-27, 3, 0),
		V(27, 3, 0),
		V(-14, 3, -32),
		V(14, 3, 32),
		V(14, 3, -36),
		V(-14, 3, 36),
	},
	Zone = V(0, 8, 0),
	ZoneRadius = nil,
	CoverNodes = { V(-24, 0, -37), V(22, 0, -44), V(-35, 0, -22), V(12, 0, -24), V(-14, 0, -19), V(0, 0, -24) },
	CustomBounds = nil,
	KillY = -40,
}

return layout
