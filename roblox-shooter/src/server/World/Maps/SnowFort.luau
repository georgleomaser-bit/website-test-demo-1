--!strict
-- =====================================================================
--  CLUTCH CLASH – Map "SnowFort" / Schneefestung (Server/World/Maps/SnowFort)
--  Besitzer: WP2 (Welt). Vertrag: DESIGN.md B8.3.5 (Koordinaten exakt aus der Tabelle).
--  M, 90×120, Wände 16 · Teams 2–4 · Stimmung fest Snowy (Schnee-Emitter: ArenaLook).
--  Datei beschreibt die A-Hälfte (z < 0); MapKit spiegelt alles ohne Center/Mirror=false.
--  Kein Material Ice (Muss-Regel 11): der Teich ist SmoothPlastic-Deko ohne Kollision.
--  CoverNodes "hinter …" = hinter der Deckung von B aus gesehen (Fort: hinter dem Wehrgang).
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local V = Vector3.new

local parts: { Types.MapPart } = {
	-- B8.3.5 Tabelle
	{ Shape = "Block", Tag = "Floor", Pos = V(0, -0.5, 0), Size = V(90, 1, 120), Color = "Snow", Center = true },
	{ Shape = "Block", Tag = "Wall", Pos = V(0, 8, -61), Size = V(94, 16, 2), Color = "SnowWall", Center = true },
	{ Shape = "Block", Tag = "Wall", Pos = V(0, 8, 61), Size = V(94, 16, 2), Color = "SnowWall", Center = true },
	{ Shape = "Block", Tag = "Wall", Pos = V(-46, 8, 0), Size = V(2, 16, 120), Color = "SnowWall", Center = true },
	{ Shape = "Block", Tag = "Wall", Pos = V(46, 8, 0), Size = V(2, 16, 120), Color = "SnowWall", Center = true },
	{ Shape = "Cylinder", Tag = "DecoPond", Pos = V(0, 0.1, 0), Size = V(24, 0.2, 24), Color = "Pond", Center = true },
	-- Fort-Front (Sehschlitz zwischen Y 4 und 5.5 bei x ±8)
	{ Shape = "Block", Tag = "FortWall", Pos = V(-14.5, 4, -40), Size = V(11, 8, 2), Color = "FortWall" },
	{ Shape = "Block", Tag = "FortWall", Pos = V(0, 4, -40), Size = V(14, 8, 2), Color = "FortWall" },
	{ Shape = "Block", Tag = "FortWall", Pos = V(14.5, 4, -40), Size = V(11, 8, 2), Color = "FortWall" },
	{ Shape = "Block", Tag = "SlitLow", Pos = V(-8, 2, -40), Size = V(2, 4, 2), Color = "FortWall" },
	{ Shape = "Block", Tag = "SlitLow", Pos = V(8, 2, -40), Size = V(2, 4, 2), Color = "FortWall" },
	{ Shape = "Block", Tag = "SlitHigh", Pos = V(-8, 6.75, -40), Size = V(2, 2.5, 2), Color = "FortWall" },
	{ Shape = "Block", Tag = "SlitHigh", Pos = V(8, 6.75, -40), Size = V(2, 2.5, 2), Color = "FortWall" },
	{ Shape = "Block", Tag = "FortSide", Pos = V(-21, 4, -47), Size = V(2, 8, 16), Color = "FortWall" },
	{ Shape = "Block", Tag = "FortSide", Pos = V(21, 4, -47), Size = V(2, 8, 16), Color = "FortWall" },
	{
		Shape = "Block",
		Tag = "Walkway",
		Pos = V(0, 5.25, -42.5),
		Size = V(40, 0.5, 3),
		Color = "WoodDeck",
		Material = "WoodPlanks",
	},
	{
		Shape = "Wedge",
		Tag = "Ramp",
		Pos = V(-16, 2.75, -49),
		Size = V(4, 5.5, 10),
		HighEnd = -44,
		Color = "WoodDeck",
		Material = "WoodPlanks",
	},
	-- Schneeball-Haufen
	{ Shape = "Ball", Tag = "Snowball", Pos = V(-12, 1.6, -18), Size = V(4, 4, 4), Color = "PureWhite" },
	{ Shape = "Ball", Tag = "Snowball", Pos = V(-10, 1.2, -16), Size = V(3, 3, 3), Color = "PureWhite" },
	{ Shape = "Ball", Tag = "Snowball", Pos = V(14, 2, -24), Size = V(5, 5, 5), Color = "PureWhite" },
	{ Shape = "Ball", Tag = "Snowball", Pos = V(16, 1.2, -21), Size = V(3, 3, 3), Color = "PureWhite" },
	-- Tannen (Stamm + 3 Kronen-Scheiben)
	{ Shape = "Cylinder", Tag = "TreeTrunk", Pos = V(-32, 2, -22), Size = V(1.5, 4, 1.5), Color = "Bark" },
	{ Shape = "Cylinder", Tag = "TreeTop", Pos = V(-32, 5, -22), Size = V(6, 2, 6), Color = "Pine" },
	{ Shape = "Cylinder", Tag = "TreeTop", Pos = V(-32, 7, -22), Size = V(4.5, 2, 4.5), Color = "Pine" },
	{ Shape = "Cylinder", Tag = "TreeTop", Pos = V(-32, 9, -22), Size = V(3, 2, 3), Color = "Pine" },
	{ Shape = "Cylinder", Tag = "TreeTrunk", Pos = V(28, 2, -8), Size = V(1.5, 4, 1.5), Color = "Bark" },
	{ Shape = "Cylinder", Tag = "TreeTop", Pos = V(28, 5, -8), Size = V(6, 2, 6), Color = "Pine" },
	{ Shape = "Cylinder", Tag = "TreeTop", Pos = V(28, 7, -8), Size = V(4.5, 2, 4.5), Color = "Pine" },
	{ Shape = "Cylinder", Tag = "TreeTop", Pos = V(28, 9, -8), Size = V(3, 2, 3), Color = "Pine" },
	-- Schneemauern
	{ Shape = "Block", Tag = "SnowWall", Pos = V(-24, 1.5, -26), Size = V(10, 3, 2), Color = "PureWhite" },
	{ Shape = "Block", Tag = "SnowWall", Pos = V(22, 1.5, -32), Size = V(2, 3, 8), Color = "PureWhite" },
	{ Shape = "Block", Tag = "SnowWall", Pos = V(6, 1.5, -14), Size = V(6, 3, 2), Color = "PureWhite" },

	-- Optik (reine Deko): Schneehauben, Fort-Fahne in Teamfarbe, Spawnplatte
	{ Shape = "Cylinder", Tag = "DecoSnowCap", Pos = V(-32, 10.2, -22), Size = V(2, 0.4, 2), Color = "PureWhite" },
	{ Shape = "Cylinder", Tag = "DecoSnowCap", Pos = V(28, 10.2, -8), Size = V(2, 0.4, 2), Color = "PureWhite" },
	{ Shape = "Cylinder", Tag = "DecoFlagPole", Pos = V(0, 12, -40), Size = V(0.4, 8, 0.4), Color = "Charcoal" },
	{ Shape = "Block", Tag = "DecoFlag", Pos = V(1.6, 14.8, -40), Size = V(3, 2, 0.2), Color = "TeamA" },
	{ Shape = "Block", Tag = "DecoSpawnPlate", Pos = V(0, 0.05, -50), Size = V(26, 0.1, 6), Color = "TeamA" },
}

local layout: Types.MapLayout = {
	Key = "SnowFort",
	Size = V(90, 16, 120),
	WallHeight = 16,
	Parts = parts,
	SpawnsA = { V(-9, 3, -50), V(-3, 3, -50), V(3, 3, -50), V(9, 3, -50) },
	FFA = nil,
	Zone = V(0, 0, 0),
	ZoneRadius = nil,
	CoverNodes = {
		V(-11, 0, -45.5), -- hinter FW1 (neben der Rampe)
		V(14.5, 0, -45.5), -- hinter FW3
		V(0, 5.5, -42.5), -- Wehrgang
		V(-12, 0, -21), -- Schneeball-Haufen
		V(14, 0, -27.5), -- Schneeball-Haufen
		V(-24, 0, -28), -- Schneemauer 1
		V(24, 0, -32), -- Schneemauer 2
		V(6, 0, -16), -- Schneemauer 3
	},
	CustomBounds = nil,
	KillY = -40,
}

return layout
