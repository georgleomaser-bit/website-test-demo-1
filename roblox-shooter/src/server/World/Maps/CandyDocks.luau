--!strict
-- =====================================================================
--  CLUTCH CLASH – Map "CandyDocks" / Zuckerhafen (Server/World/Maps/CandyDocks)
--  Besitzer: WP2 (Welt). Vertrag: DESIGN.md B8.3.4 (Koordinaten exakt aus der Tabelle).
--  L, 64×150, Wände 18 · Teams 2–4 · inkl. 12 FFA-Spawns.
--  Datei beschreibt die A-Hälfte (z < 0); MapKit spiegelt alles ohne Center/Mirror=false.
--  Lange Randgassen (x ±28) = Scharfschützen-Linien; Mitte = Nahkampf-Labyrinth.
--  CoverNodes "hinter K1/K2/K3" = 2 Studs hinter dem Container (Seite der eigenen Basis),
--  "Floß" = im Kanal auf der A-Seite des Floßes.
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local MapKit = require(script.Parent.Parent:WaitForChild("MapKit"))

local V = Vector3.new
local RED = Color3.fromRGB(235, 60, 70)

local parts: { Types.MapPart } = {
	-- B8.3.4 Tabelle
	{
		Shape = "Block",
		Tag = "Dock",
		Pos = V(0, -0.5, -41.5),
		Size = V(64, 1, 67),
		Color = "Wood",
		Material = "WoodPlanks",
	},
	{ Shape = "Block", Tag = "Canal", Pos = V(0, -2.5, 0), Size = V(64, 1, 16), Color = "Water", Center = true },
	{ Shape = "Block", Tag = "CanalEdge", Pos = V(0, -1, -8.5), Size = V(64, 2, 1), Color = "Charcoal" },
	{
		Shape = "Block",
		Tag = "Bridge",
		Pos = V(-18, -0.25, 0),
		Size = V(6, 0.5, 16),
		Color = "Wood",
		Material = "WoodPlanks",
		Center = true,
	},
	{
		Shape = "Block",
		Tag = "Bridge",
		Pos = V(18, -0.25, 0),
		Size = V(6, 0.5, 16),
		Color = "Wood",
		Material = "WoodPlanks",
		Center = true,
	},
	{
		Shape = "Block",
		Tag = "Raft",
		Pos = V(0, -1, 0),
		Size = V(10, 2, 10),
		Color = "Wood",
		Material = "WoodPlanks",
		Center = true,
	},
	{ Shape = "Block", Tag = "Wall", Pos = V(0, 9, -76), Size = V(68, 18, 2), Color = "Pink", Center = true },
	{ Shape = "Block", Tag = "Wall", Pos = V(0, 9, 76), Size = V(68, 18, 2), Color = "Pink", Center = true },
	{ Shape = "Block", Tag = "Wall", Pos = V(-33, 9, 0), Size = V(2, 18, 150), Color = "Pink", Center = true },
	{ Shape = "Block", Tag = "Wall", Pos = V(33, 9, 0), Size = V(2, 18, 150), Color = "Pink", Center = true },
	{ Shape = "Block", Tag = "Container", Pos = V(-20, 4.25, -40), Size = V(8, 8.5, 20), Color = "Pink" },
	{ Shape = "Block", Tag = "Container", Pos = V(10, 4.25, -30), Size = V(20, 8.5, 8), Color = "Mint" },
	{ Shape = "Block", Tag = "Stack", Pos = V(24, 4.25, -56), Size = V(8, 8.5, 20), Color = "Yellow" },
	{ Shape = "Block", Tag = "Container", Pos = V(24, 12.75, -56), Size = V(8, 8.5, 20), Color = "Lilac" },
	{ Shape = "Block", Tag = "Crate", Pos = V(-6, 2, -18), Size = V(4, 4, 4), Color = "Sand" },
	{ Shape = "Block", Tag = "Crate", Pos = V(4, 2, -22), Size = V(4, 4, 4), Color = "Sand" },
	{ Shape = "Block", Tag = "Crate", Pos = V(-2, 2, -26), Size = V(4, 4, 4), Color = "Sand" },
	{ Shape = "Block", Tag = "Crate", Pos = V(8, 2, -14), Size = V(4, 4, 4), Color = "Sand" },
	-- Zuckerstangen-Kran: Mast aus 5 Segmenten rot/weiß, Arm rot
	{ Shape = "Block", Tag = "CraneMast", Pos = V(-28, 2, -20), Size = V(2, 4, 2), Color = RED },
	{ Shape = "Block", Tag = "CraneMast", Pos = V(-28, 6, -20), Size = V(2, 4, 2), Color = "PureWhite" },
	{ Shape = "Block", Tag = "CraneMast", Pos = V(-28, 10, -20), Size = V(2, 4, 2), Color = RED },
	{ Shape = "Block", Tag = "CraneMast", Pos = V(-28, 14, -20), Size = V(2, 4, 2), Color = "PureWhite" },
	{ Shape = "Block", Tag = "CraneMast", Pos = V(-28, 18, -20), Size = V(2, 4, 2), Color = RED },
	{ Shape = "Block", Tag = "CraneArm", Pos = V(-20, 19, -20), Size = V(16, 1.5, 1.5), Color = RED },
	{ Shape = "Cylinder", Tag = "Bollard", Pos = V(-28, 1, -10), Size = V(1.5, 2, 1.5), Color = "Charcoal" },
	{ Shape = "Cylinder", Tag = "Bollard", Pos = V(8, 1, -10), Size = V(1.5, 2, 1.5), Color = "Charcoal" },

	-- Optik (reine Deko)
	{ Shape = "Block", Tag = "DecoSpawnPlate", Pos = V(0, 0.05, -68), Size = V(26, 0.1, 6), Color = "TeamA" },
	{ Shape = "Block", Tag = "DecoRope", Pos = V(-13, 16, -20), Size = V(0.3, 5, 0.3), Color = "Charcoal" },
	{ Shape = "Ball", Tag = "DecoHook", Pos = V(-13, 13.2, -20), Size = V(1.4, 1.4, 1.4), Color = "Yellow" },
	{ Shape = "Block", Tag = "DecoBand", Pos = V(0, 5, -74.9), Size = V(64, 1.4, 0.2), Color = "PureWhite" },
	{ Shape = "Block", Tag = "DecoDoor", Pos = V(-20, 4.25, -50.15), Size = V(6.4, 7, 0.3), Color = "Charcoal" },
	{ Shape = "Block", Tag = "DecoDoor", Pos = V(24, 4.25, -66.15), Size = V(6.4, 7, 0.3), Color = "Charcoal" },
	{ Shape = "Cylinder", Tag = "DecoBollardCap", Pos = V(-28, 2.1, -10), Size = V(1.9, 0.2, 1.9), Color = RED },
	{ Shape = "Cylinder", Tag = "DecoBollardCap", Pos = V(8, 2.1, -10), Size = V(1.9, 0.2, 1.9), Color = RED },
}

-- Kulisse: Wand-Lisenen, Spielzeug-Stapel hinter den Mauern, Ballons (nur Deko)
for _, piece in
	ipairs(MapKit.Scenery({
		Size = V(64, 18, 150),
		WallHeight = 18,
		Seed = 41,
		Colors = { "Mint", "Yellow", "Lilac", "PureWhite", "Pink" },
		Pilaster = "PureWhite",
		Balloons = 4,
	}))
do
	table.insert(parts, piece)
end

local layout: Types.MapLayout = {
	Key = "CandyDocks",
	Size = V(64, 18, 150),
	WallHeight = 18,
	Parts = parts,
	SpawnsA = { V(-9, 3, -68), V(-3, 3, -68), V(3, 3, -68), V(9, 3, -68) },
	FFA = {
		V(-26, 3, -66),
		V(16, 3, -70),
		V(-16, 3, 70),
		V(26, 3, 66),
		V(0, 3, -60),
		V(0, 3, 60),
		V(-28, 3, -28),
		V(28, 3, 28),
		V(28, 3, -28),
		V(-28, 3, 28),
		V(14, 3, -44),
		V(-14, 3, 44),
	},
	Zone = V(0, 0, 0),
	ZoneRadius = nil,
	CoverNodes = {
		V(-20, 0, -52), -- hinter K1
		V(10, 0, -36), -- hinter K2
		V(24, 0, -68), -- hinter K3
		V(0, 0, -20), -- Labyrinth
		V(0, -2, -6.5), -- Floß (im Kanal, A-Seite)
	},
	CustomBounds = nil,
	KillY = -40,
}

return layout
