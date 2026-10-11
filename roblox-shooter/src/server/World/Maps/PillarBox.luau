--!strict
-- =====================================================================
--  CLUTCH CLASH – Map "PillarBox" / Säulenkiste (Server/World/Maps/PillarBox)
--  Besitzer: WP2 (Welt). Vertrag: DESIGN.md B8.3.1 (Koordinaten exakt aus der Tabelle).
--  S, 72×72, Wände 14 · Teams 1–2 · Modi/Stimmungen in Config.Maps.Maps.PillarBox.
--  Datei beschreibt die A-Hälfte (z < 0); MapKit spiegelt alles ohne Center/Mirror=false.
--  Zusätzlich (A4-Optik, ohne Einfluss aufs Spiel): Deko-Fliesen, Teamfarben-Spawnplatten,
--  Wandstreifen, Eckkugeln. Kappen/Lippen setzt MapKit automatisch.
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local MapKit = require(script.Parent.Parent:WaitForChild("MapKit"))

local V = Vector3.new

local parts: { Types.MapPart } = {
	-- B8.3.1 Tabelle
	{ Shape = "Block", Tag = "Floor", Pos = V(0, -0.5, 0), Size = V(72, 1, 72), Color = "Cream", Center = true },
	{ Shape = "Block", Tag = "Wall", Pos = V(0, 7, -37), Size = V(76, 14, 2), Color = "Mint", Center = true },
	{ Shape = "Block", Tag = "Wall", Pos = V(0, 7, 37), Size = V(76, 14, 2), Color = "Mint", Center = true },
	{ Shape = "Block", Tag = "Wall", Pos = V(-37, 7, 0), Size = V(2, 14, 72), Color = "Mint", Center = true },
	{ Shape = "Block", Tag = "Wall", Pos = V(37, 7, 0), Size = V(2, 14, 72), Color = "Mint", Center = true },
	{ Shape = "Block", Tag = "Platform", Pos = V(0, 2, 0), Size = V(16, 4, 16), Color = "Lilac", Center = true },
	{ Shape = "Wedge", Tag = "Ramp", Pos = V(0, 2, -13), Size = V(6, 4, 10), HighEnd = -8, Color = "Lilac" },
	{ Shape = "Block", Tag = "Pillar", Pos = V(-18, 5, -18), Size = V(4, 10, 4), Color = "Pink" },
	{ Shape = "Block", Tag = "Pillar", Pos = V(18, 7, -18), Size = V(4, 14, 4), Color = "Pink" },
	{ Shape = "Block", Tag = "Pillar", Pos = V(-20, 3, 0), Size = V(4, 6, 4), Color = "Sand" },
	{ Shape = "Block", Tag = "Crate", Pos = V(-10, 1.5, -27), Size = V(6, 3, 3), Color = "Sand" },
	{ Shape = "Block", Tag = "Crate", Pos = V(13, 1.5, -25), Size = V(3, 3, 6), Color = "Sand" },
	{ Shape = "Block", Tag = "HalfWall", Pos = V(-28, 2.5, -8), Size = V(2, 5, 10), Color = "Mint" },
	{ Shape = "Block", Tag = "Cover", Pos = V(6, 1, -20), Size = V(4, 2, 2), Color = "Charcoal" },

	-- Optik (reine Deko, CanCollide/CanQuery aus)
	{ Shape = "Block", Tag = "DecoSpawnPlate", Pos = V(0, 0.05, -32.5), Size = V(30, 0.1, 6), Color = "TeamA" },
	{ Shape = "Block", Tag = "DecoBand", Pos = V(0, 3.5, -35.9), Size = V(72, 1, 0.2), Color = "Pink" },
	{ Shape = "Block", Tag = "DecoBand", Pos = V(-35.9, 3.5, 0), Size = V(0.2, 1, 72), Color = "Lilac" },
	{ Shape = "Ball", Tag = "DecoBall", Pos = V(-37, 16.1, -37), Size = V(3, 3, 3), Color = "Pink" },
	{ Shape = "Ball", Tag = "DecoBall", Pos = V(37, 16.1, -37), Size = V(3, 3, 3), Color = "Lilac" },
}

-- Schachbrett-Fliesen 12×12 (6×6 Felder -> punktsymmetrisch)
for _, tile in ipairs(MapKit.Checker(Vector2.new(-36, -36), Vector2.new(36, 36), 12, 0, "CreamDark")) do
	table.insert(parts, tile)
end

-- Kulisse: Wand-Lisenen, Spielzeug-Stapel hinter den Mauern, Ballons (nur Deko)
for _, piece in
	ipairs(MapKit.Scenery({
		Size = V(72, 14, 72),
		WallHeight = 14,
		Seed = 11,
		Colors = { "Pink", "Lilac", "Sand", "Mint" },
		Pilaster = "Lilac",
		Balloons = 3,
	}))
do
	table.insert(parts, piece)
end

local layout: Types.MapLayout = {
	Key = "PillarBox",
	Size = V(72, 14, 72),
	WallHeight = 14,
	Parts = parts,
	SpawnsA = { V(-6, 3, -32), V(6, 3, -32), V(-12, 3, -33), V(12, 3, -33) },
	FFA = nil,
	Zone = V(0, 4, 0),
	ZoneRadius = nil,
	CoverNodes = { V(-18, 0, -22), V(-10, 0, -30), V(-31, 0, -8), V(18, 0, -22), V(13, 0, -29) },
	CustomBounds = nil,
	KillY = -40,
}

return layout
