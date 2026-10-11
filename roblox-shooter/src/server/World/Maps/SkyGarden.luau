--!strict
-- =====================================================================
--  CLUTCH CLASH – Map "SkyGarden" / Himmelsgarten (Server/World/Maps/SkyGarden)
--  Besitzer: WP2 (Welt). Vertrag: DESIGN.md B8.3.6 (Koordinaten exakt aus der Tabelle).
--  M, Inseln über der Leere · Teams 1–3 · inkl. 12 FFA-Spawns · CustomBounds x ±70, z ±85, Decke 50.
--  Sturz unter KillY −40 = Pop (gutgeschrieben dem letzten Schadensverursacher – WP3/WP5).
--  Jede Insel = Gras-Platte (1 dick) + Erd-Unterseite (3 dick). Die Diagonal-Brücke steht zwischen
--  den beiden Punkten aus CFrame.lookAt((−15,−0.25,−40),(−36,−0.25,−7)) (Mitte, Länge 39, Breite 4).
--  CoverNodes stehen nicht in B8.3.6 – hier hinter Hecken, Töpfen und der Kiste (A-Seite).
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local V = Vector3.new

-- Diagonal-Brücke A–Seite: Mitte zwischen den beiden lookAt-Punkten, Gierwinkel aus der Richtung
local DIAG_FROM = V(-15, -0.25, -40)
local DIAG_TO = V(-36, -0.25, -7)
local DIAG_DIR = DIAG_TO - DIAG_FROM
local DIAG_MID = (DIAG_FROM + DIAG_TO) / 2
local DIAG_YAW = math.deg(math.atan2(-DIAG_DIR.X, -DIAG_DIR.Z)) -- LookVector = (−sin, 0, −cos)

local parts: { Types.MapPart } = {
	-- Mittel-Insel + Pavillon
	{ Shape = "Block", Tag = "Grass", Pos = V(0, -0.5, 0), Size = V(36, 1, 36), Color = "Grass", Center = true },
	{ Shape = "Block", Tag = "Dirt", Pos = V(0, -2.5, 0), Size = V(34, 3, 34), Color = "Dirt", Center = true },
	{ Shape = "Block", Tag = "PavilionPillar", Pos = V(-5, 4, -5), Size = V(1, 8, 1), Color = "PureWhite", Center = true },
	{ Shape = "Block", Tag = "PavilionPillar", Pos = V(5, 4, -5), Size = V(1, 8, 1), Color = "PureWhite", Center = true },
	{ Shape = "Block", Tag = "PavilionPillar", Pos = V(-5, 4, 5), Size = V(1, 8, 1), Color = "PureWhite", Center = true },
	{ Shape = "Block", Tag = "PavilionPillar", Pos = V(5, 4, 5), Size = V(1, 8, 1), Color = "PureWhite", Center = true },
	{ Shape = "Block", Tag = "Roof", Pos = V(0, 8.5, 0), Size = V(12, 1, 12), Color = "Pink", Center = true },
	-- Seiten-Insel (gespiegelt -> +36)
	{ Shape = "Block", Tag = "Grass", Pos = V(-36, -0.5, 0), Size = V(14, 1, 14), Color = "Grass" },
	{ Shape = "Block", Tag = "Dirt", Pos = V(-36, -2.5, 0), Size = V(12, 3, 12), Color = "Dirt" },
	-- Spawn-Insel A
	{ Shape = "Block", Tag = "Grass", Pos = V(0, -0.5, -48), Size = V(30, 1, 30), Color = "Grass" },
	{ Shape = "Block", Tag = "Dirt", Pos = V(0, -2.5, -48), Size = V(28, 3, 28), Color = "Dirt" },
	-- Brücken
	{
		Shape = "Block",
		Tag = "Bridge",
		Pos = V(0, -0.25, -25.5),
		Size = V(6, 0.5, 15),
		Color = "Wood",
		Material = "WoodPlanks",
	},
	{
		Shape = "Block",
		Tag = "Bridge",
		Pos = V(-23.5, -0.25, 0),
		Size = V(11, 0.5, 6),
		Color = "Wood",
		Material = "WoodPlanks",
	},
	{
		Shape = "Block",
		Tag = "Bridge",
		Pos = DIAG_MID,
		Size = V(4, 0.5, 39),
		Rot = V(0, DIAG_YAW, 0),
		Color = "Wood",
		Material = "WoodPlanks",
	},
	-- Hecken
	{ Shape = "Block", Tag = "Hedge", Pos = V(-8, 1.5, -40), Size = V(6, 3, 2), Color = "Hedge" },
	{ Shape = "Block", Tag = "Hedge", Pos = V(9, 1.5, -52), Size = V(2, 3, 6), Color = "Hedge" },
	{ Shape = "Block", Tag = "Hedge", Pos = V(-12, 1.5, -8), Size = V(6, 3, 2), Color = "Hedge" },
	{ Shape = "Block", Tag = "Hedge", Pos = V(10, 1.5, -12), Size = V(2, 3, 6), Color = "Hedge" },
	{ Shape = "Block", Tag = "Hedge", Pos = V(0, 2, -61), Size = V(20, 4, 2), Color = "Hedge" },
	-- Blumentöpfe + Kiste
	{ Shape = "Cylinder", Tag = "FlowerPot", Pos = V(-4, 1.25, -14), Size = V(3, 2.5, 3), Color = "Terracotta" },
	{ Shape = "Cylinder", Tag = "FlowerPot", Pos = V(14, 1.25, -4), Size = V(3, 2.5, 3), Color = "Terracotta" },
	{ Shape = "Block", Tag = "Crate", Pos = V(-36, 2, -3), Size = V(4, 4, 4), Color = "Sand" },

	-- Optik (reine Deko): hängende Erd-Stufen unter den Inseln, Blüten, Spawnplatte
	{ Shape = "Block", Tag = "DecoDirt", Pos = V(0, -5.5, 0), Size = V(24, 3, 24), Color = "Dirt", Center = true },
	{ Shape = "Block", Tag = "DecoDirt", Pos = V(0, -8, 0), Size = V(12, 2, 12), Color = "Dirt", Center = true },
	{ Shape = "Block", Tag = "DecoDirt", Pos = V(0, -5.5, -48), Size = V(18, 3, 18), Color = "Dirt" },
	{ Shape = "Block", Tag = "DecoDirt", Pos = V(0, -7.75, -48), Size = V(8, 1.5, 8), Color = "Dirt" },
	{ Shape = "Block", Tag = "DecoDirt", Pos = V(-36, -5, 0), Size = V(7, 2, 7), Color = "Dirt" },
	{ Shape = "Ball", Tag = "DecoBloom", Pos = V(-4, 3.1, -14), Size = V(2.2, 2.2, 2.2), Color = "Pink" },
	{ Shape = "Ball", Tag = "DecoBloom", Pos = V(14, 3.1, -4), Size = V(2.2, 2.2, 2.2), Color = "Yellow" },
	{ Shape = "Ball", Tag = "DecoBloom", Pos = V(-6, 3.2, -40), Size = V(1.2, 1.2, 1.2), Color = "Pink" },
	{ Shape = "Ball", Tag = "DecoBloom", Pos = V(9, 3.2, -50), Size = V(1.2, 1.2, 1.2), Color = "Lilac" },
	{ Shape = "Ball", Tag = "DecoBloom", Pos = V(-5, 4.2, -61), Size = V(1.4, 1.4, 1.4), Color = "Yellow" },
	{ Shape = "Ball", Tag = "DecoBloom", Pos = V(5, 4.2, -61), Size = V(1.4, 1.4, 1.4), Color = "Pink" },
	{ Shape = "Block", Tag = "DecoSpawnPlate", Pos = V(0, 0.05, -48), Size = V(24, 0.1, 6), Color = "TeamA" },
}

local layout: Types.MapLayout = {
	Key = "SkyGarden",
	Size = V(140, 50, 170),
	WallHeight = 0,
	Parts = parts,
	SpawnsA = { V(-5, 3, -50), V(5, 3, -50), V(-10, 3, -46), V(10, 3, -46) },
	FFA = {
		V(0, 3, -52),
		V(0, 3, 52),
		V(-9, 3, -44),
		V(9, 3, 44),
		V(9, 3, -44),
		V(-9, 3, 44),
		V(-36, 3, 4),
		V(36, 3, -4),
		V(-12, 3, 12),
		V(12, 3, -12),
		V(-12, 3, -12),
		V(12, 3, 12),
	},
	Zone = V(0, 0, 0),
	ZoneRadius = nil,
	CoverNodes = {
		V(-8, 0, -42), -- hinter Hecke 1
		V(11, 0, -52), -- hinter Hecke 2
		V(-12, 0, -10), -- hinter Hecke 3
		V(12, 0, -12), -- hinter Hecke 4
		V(-4, 0, -16.5), -- hinter Blumentopf
		V(-36, 0, -6), -- hinter der Kiste (Seiten-Insel)
	},
	CustomBounds = { Min = V(-70, -45, -85), Max = V(70, 50, 85) },
	KillY = -40,
}

return layout
