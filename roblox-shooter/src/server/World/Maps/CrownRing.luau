--!strict
-- =====================================================================
--  CLUTCH CLASH – Map "CrownRing" / Kronen-Ring (Server/World/Maps/CrownRing)
--  Besitzer: WP2 (Welt). Vertrag: DESIGN.md B8.3.7 + B2 (fest in der Lobby, ≤ 400 Teile).
--  Map-Ursprung in Weltkoordinaten = Config.Maps.CrownOrigin (95, −6, 0): die Grube ist 6 tief,
--  das Glas-Geländer steht 8 hoch über dem Lobby-Boden. Nur Modus Crown, Lobby-Licht (keine Stimmung).
--  Barrieren (Seiten bis Y 40 + Decke) baut MapKit automatisch aus Size.
--  CoverNodes stehen nicht in B8.3.7 – hier hinter der niedrigen Mauer und den Säulen.
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local MapKit = require(script.Parent.Parent:WaitForChild("MapKit"))

local V = Vector3.new
local GOLD = Color3.fromRGB(255, 200, 60)

local parts: { Types.MapPart } = {
	-- B8.3.7 Tabelle
	{ Shape = "Block", Tag = "Floor", Pos = V(0, -0.5, 0), Size = V(50, 1, 50), Color = "Navy", Center = true },
	{ Shape = "Block", Tag = "Wall", Pos = V(0, 3, -26), Size = V(54, 6, 2), Color = "Charcoal", Center = true },
	{ Shape = "Block", Tag = "Wall", Pos = V(0, 3, 26), Size = V(54, 6, 2), Color = "Charcoal", Center = true },
	{ Shape = "Block", Tag = "Wall", Pos = V(-26, 3, 0), Size = V(2, 6, 50), Color = "Charcoal", Center = true },
	{ Shape = "Block", Tag = "Wall", Pos = V(26, 3, 0), Size = V(2, 6, 50), Color = "Charcoal", Center = true },
	{
		Shape = "Block",
		Tag = "Glass",
		Pos = V(0, 10, -26),
		Size = V(54, 8, 1),
		Color = "PureWhite",
		Material = "Glass",
		Transparency = 0.6,
		Center = true,
	},
	{
		Shape = "Block",
		Tag = "Glass",
		Pos = V(0, 10, 26),
		Size = V(54, 8, 1),
		Color = "PureWhite",
		Material = "Glass",
		Transparency = 0.6,
		Center = true,
	},
	{
		Shape = "Block",
		Tag = "Glass",
		Pos = V(-26, 10, 0),
		Size = V(1, 8, 50),
		Color = "PureWhite",
		Material = "Glass",
		Transparency = 0.6,
		Center = true,
	},
	{
		Shape = "Block",
		Tag = "Glass",
		Pos = V(26, 10, 0),
		Size = V(1, 8, 50),
		Color = "PureWhite",
		Material = "Glass",
		Transparency = 0.6,
		Center = true,
	},
	{
		Shape = "Block",
		Tag = "CrownCrate",
		Pos = V(0, 2, 0),
		Size = V(4, 4, 4),
		Color = GOLD,
		Material = "Foil",
		Center = true,
	},
	{ Shape = "Block", Tag = "Pillar", Pos = V(-12, 5, -12), Size = V(4, 10, 4), Color = "Pink" },
	{ Shape = "Block", Tag = "Pillar", Pos = V(12, 5, -12), Size = V(4, 10, 4), Color = "Pink" },
	{ Shape = "Block", Tag = "Cover", Pos = V(0, 1.5, -9), Size = V(10, 3, 2), Color = "Mint" },

	-- Optik (reine Deko): Gold-Neon in den Ecken, Krone auf der Kiste, Spawnplatte
	{
		Shape = "Block",
		Tag = "DecoCorner",
		Pos = V(-25.5, 7.1, -25.5),
		Size = V(1, 1, 1),
		Color = GOLD,
		Material = "Neon",
	},
	{
		Shape = "Block",
		Tag = "DecoCorner",
		Pos = V(25.5, 7.1, -25.5),
		Size = V(1, 1, 1),
		Color = GOLD,
		Material = "Neon",
	},
	{
		Shape = "Cylinder",
		Tag = "DecoCrown",
		Pos = V(0, 4.45, 0),
		Size = V(2.6, 0.5, 2.6),
		Color = GOLD,
		Center = true,
	},
	{ Shape = "Ball", Tag = "DecoCrown", Pos = V(0, 5.3, 0), Size = V(0.9, 0.9, 0.9), Color = "Pink", Center = true },
	{ Shape = "Block", Tag = "DecoSpawnPlate", Pos = V(-2, 0.05, -20), Size = V(10, 0.1, 5), Color = "TeamA" },
}

-- Schachbrett-Fliesen 10×10 (5×5 Felder -> punktsymmetrisch)
for _, tile in ipairs(MapKit.Checker(Vector2.new(-25, -25), Vector2.new(25, 25), 10, 0, "NavyLight")) do
	table.insert(parts, tile)
end

local layout: Types.MapLayout = {
	Key = "CrownRing",
	Size = V(50, 6, 50),
	WallHeight = 6,
	Parts = parts,
	SpawnsA = { V(0, 3, -20), V(-4, 3, -20) }, -- Reserve-Spawn (−4,3,−20)
	FFA = nil,
	Zone = V(0, 0, 0),
	ZoneRadius = 7,
	CoverNodes = { V(0, 0, -11.5), V(-12, 0, -15.5), V(12, 0, -15.5) },
	CustomBounds = nil,
	KillY = -40,
}

return layout
