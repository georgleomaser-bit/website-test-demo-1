--!strict
-- =====================================================================
--  CLUTCH CLASH – Map "NeonGrid" / Neon-Raster (Server/World/Maps/NeonGrid)
--  Besitzer: WP2 (Welt). Vertrag: DESIGN.md B8.3.3 (Koordinaten exakt aus der Tabelle).
--  S/M, 96×96, Wände 14 · Teams 1–2 · inkl. 12 FFA-Spawns · Stimmung fest NeonNight.
--  Datei beschreibt die A-Hälfte (z < 0); MapKit spiegelt alles ohne Center/Mirror=false.
--  "Charcoal + Neon-Kante" / "Neon Pink Streifen" sind eigene Deko-Teile (Neon, ohne Kollision).
--  CoverNodes "hinter LW1–LW4, PY1, PY2" = 2.5 Studs hinter der Deckung (von der Mitte/B aus gesehen).
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local V = Vector3.new
local CYAN = Color3.fromRGB(0, 230, 255)
local PINK = Color3.fromRGB(255, 60, 170)

local parts: { Types.MapPart } = {
	-- Böden
	{ Shape = "Block", Tag = "Floor", Pos = V(0, -0.5, -30), Size = V(96, 1, 36), Color = "Navy" },
	{ Shape = "Block", Tag = "Floor", Pos = V(-30, -0.5, 0), Size = V(36, 1, 24), Color = "Navy" },
	{ Shape = "Block", Tag = "PitFloor", Pos = V(0, -4.5, 0), Size = V(24, 1, 24), Color = "Navy", Center = true },
	-- Grube
	{ Shape = "Block", Tag = "PitWall", Pos = V(-10.5, -2, -12.5), Size = V(3, 4, 1), Color = "Charcoal" },
	{ Shape = "Block", Tag = "PitWall", Pos = V(4.5, -2, -12.5), Size = V(15, 4, 1), Color = "Charcoal" },
	{ Shape = "Block", Tag = "PitWall", Pos = V(-12.5, -2, 0), Size = V(1, 4, 24), Color = "Charcoal" },
	{ Shape = "Wedge", Tag = "Ramp", Pos = V(-6, -2, -8), Size = V(6, 4, 8), HighEnd = -12, Color = "Charcoal" },
	-- Wände
	{ Shape = "Block", Tag = "Wall", Pos = V(0, 7, -49), Size = V(100, 14, 2), Color = "Charcoal", Center = true },
	{ Shape = "Block", Tag = "Wall", Pos = V(0, 7, 49), Size = V(100, 14, 2), Color = "Charcoal", Center = true },
	{ Shape = "Block", Tag = "Wall", Pos = V(-49, 7, 0), Size = V(2, 14, 96), Color = "Charcoal", Center = true },
	{ Shape = "Block", Tag = "Wall", Pos = V(49, 7, 0), Size = V(2, 14, 96), Color = "Charcoal", Center = true },
	-- Niedrige Mauern + Neon-Kante
	{ Shape = "Block", Tag = "LowWall", Pos = V(-20, 1.75, -26), Size = V(12, 3.5, 1.5), Color = "Charcoal" },
	{ Shape = "Block", Tag = "LowWall", Pos = V(18, 1.75, -32), Size = V(1.5, 3.5, 12), Color = "Charcoal" },
	{ Shape = "Block", Tag = "LowWall", Pos = V(-36, 1.75, -6), Size = V(1.5, 3.5, 10), Color = "Charcoal" },
	{ Shape = "Block", Tag = "LowWall", Pos = V(6, 1.75, -20), Size = V(10, 3.5, 1.5), Color = "Charcoal" },
	{ Shape = "Block", Tag = "DecoEdge", Pos = V(-20, 3.55, -26), Size = V(12, 0.1, 0.5), Color = CYAN, Material = "Neon" },
	{ Shape = "Block", Tag = "DecoEdge", Pos = V(18, 3.55, -32), Size = V(0.5, 0.1, 12), Color = CYAN, Material = "Neon" },
	{ Shape = "Block", Tag = "DecoEdge", Pos = V(-36, 3.55, -6), Size = V(0.5, 0.1, 10), Color = CYAN, Material = "Neon" },
	{ Shape = "Block", Tag = "DecoEdge", Pos = V(6, 3.55, -20), Size = V(10, 0.1, 0.5), Color = CYAN, Material = "Neon" },
	-- Pylone + pinke Neon-Streifen
	{ Shape = "Block", Tag = "Pylon", Pos = V(-26, 8, -38), Size = V(4, 16, 4), Color = "Charcoal" },
	{ Shape = "Block", Tag = "Pylon", Pos = V(30, 8, -18), Size = V(4, 16, 4), Color = "Charcoal" },
	{ Shape = "Block", Tag = "DecoStripe", Pos = V(-26, 5, -38), Size = V(4.2, 0.5, 4.2), Color = PINK, Material = "Neon" },
	{ Shape = "Block", Tag = "DecoStripe", Pos = V(-26, 11, -38), Size = V(4.2, 0.5, 4.2), Color = PINK, Material = "Neon" },
	{ Shape = "Block", Tag = "DecoStripe", Pos = V(30, 5, -18), Size = V(4.2, 0.5, 4.2), Color = PINK, Material = "Neon" },
	{ Shape = "Block", Tag = "DecoStripe", Pos = V(30, 11, -18), Size = V(4.2, 0.5, 4.2), Color = PINK, Material = "Neon" },
	-- Würfel
	{ Shape = "Block", Tag = "Cube", Pos = V(-38, 2, -34), Size = V(4, 4, 4), Color = "Lilac" },
	{ Shape = "Block", Tag = "Cube", Pos = V(36, 1.5, -40), Size = V(3, 3, 3), Color = "Lilac" },
	-- Optik: Teamfarben-Spawnplatte
	{ Shape = "Block", Tag = "DecoSpawnPlate", Pos = V(0, 0.05, -41), Size = V(30, 0.1, 6), Color = "TeamA" },
}

-- Neon-Linien (Center, je 8 längs X und längs Z), y 0.02 über dem Boden
for _, k in ipairs({ 16, 24, 32, 40 }) do
	for _, s in ipairs({ -1, 1 }) do
		table.insert(parts, {
			Shape = "Block",
			Tag = "DecoLine",
			Pos = V(0, 0.02, s * k),
			Size = V(96, 0.05, 0.3),
			Color = CYAN,
			Material = "Neon",
			Center = true,
		})
		table.insert(parts, {
			Shape = "Block",
			Tag = "DecoLine",
			Pos = V(s * k, 0.02, 0),
			Size = V(0.3, 0.05, 96),
			Color = CYAN,
			Material = "Neon",
			Center = true,
		})
	end
end

local layout: Types.MapLayout = {
	Key = "NeonGrid",
	Size = V(96, 14, 96),
	WallHeight = 14,
	Parts = parts,
	SpawnsA = { V(-6, 3, -42), V(6, 3, -42), V(-12, 3, -40), V(12, 3, -40) },
	FFA = {
		V(-40, 3, -40),
		V(40, 3, -40),
		V(-40, 3, 40),
		V(40, 3, 40),
		V(0, 3, -44),
		V(0, 3, 44),
		V(-42, 3, 0),
		V(42, 3, 0),
		V(-20, 3, -8),
		V(20, 3, 8),
		V(20, 3, -8),
		V(-20, 3, 8),
	},
	Zone = V(0, -4, 0),
	ZoneRadius = nil,
	CoverNodes = {
		V(-20, 0, -28.5), -- hinter LW1
		V(20.5, 0, -32), -- hinter LW2
		V(-38.5, 0, -6), -- hinter LW3
		V(6, 0, -22.5), -- hinter LW4
		V(-26, 0, -41.5), -- hinter PY1
		V(30, 0, -21.5), -- hinter PY2
		V(0, -4, 0), -- Grubenmitte
	},
	CustomBounds = nil,
	KillY = -40,
}

return layout
