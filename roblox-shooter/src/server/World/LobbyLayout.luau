--!strict
-- =====================================================================
--  CLUTCH CLASH – Koordinaten der Lobby „Clutch Plaza“ (Server/World/LobbyLayout)
--  Besitzer: WP2 (Welt). Vertrag: DESIGN.md B2 (Zonen-Tabelle), B3.2 (Pads), B16.9 (Tafeln).
--  Reine Daten – LobbyBuilder baut daraus die Welt, ArenaService nimmt die Spawns (LobbySpawn).
--  Welt-Koordinaten: X Ost, Z Süd, Boden-Oberkante Y = 0.
-- =====================================================================

local V = Vector3.new

export type PadDef = { Id: number, Mode: string, Pos: Vector3, Seats: number, Color: Color3, Ffa: boolean? }
export type KioskDef = { Window: string, Pos: Vector3, Label: string, Color: Color3, Roof: Color3 }
export type FloorDef = { Name: string, Pos: Vector3, Size: Vector3 }

local L = {}

L.FolderName = "Lobby" -- workspace.Lobby (ArenaLook versteckt den Ordner im Match)
L.RangeName = "Range" -- workspace.Lobby.Range (Model, Arena-Objekt "Range")
L.PartBudget = 2500 -- inkl. Crown Ring (≤ 400) und Range (≤ 400)

-- ---------------------------------------------------------------------
-- Boden: 5 Stücke (Loch für den Crown Ring X 70..120, Z −25..25)
-- ---------------------------------------------------------------------
L.Floor = {
	{ Name = "FloorWest", Pos = V(-30, -0.5, 0), Size = V(200, 1, 220) },
	{ Name = "FloorNorthEast", Pos = V(100, -0.5, -67.5), Size = V(60, 1, 85) },
	{ Name = "FloorSouthEast", Pos = V(100, -0.5, 67.5), Size = V(60, 1, 85) },
	{ Name = "FloorEast", Pos = V(125, -0.5, 0), Size = V(10, 1, 50) },
	{ Name = "FloorRange", Pos = V(-165, -0.5, 0), Size = V(70, 1, 112) },
} :: { FloorDef }

-- Rand (Zaun 3 hoch + Barriere 60 hoch): Linien { von, bis } auf Y 0
L.Edges = {
	{ V(-130, 0, -110), V(130, 0, -110) }, -- Nord
	{ V(-130, 0, 110), V(130, 0, 110) }, -- Süd
	{ V(130, 0, -110), V(130, 0, 110) }, -- Ost
	{ V(-130, 0, -110), V(-130, 0, -56) }, -- West (Nord-Stück)
	{ V(-130, 0, 56), V(-130, 0, 110) }, -- West (Süd-Stück)
	{ V(-200, 0, -56), V(-130, 0, -56) }, -- Range Nord
	{ V(-200, 0, 56), V(-130, 0, 56) }, -- Range Süd
	{ V(-200, 0, -56), V(-200, 0, 56) }, -- Range West (Rückwand)
}
L.FenceHeight = 3
L.BarrierHeight = 60

-- ---------------------------------------------------------------------
-- Spawn-Platz (0,0): Brunnen + 6 SpawnLocations auf Ring r 16
-- ---------------------------------------------------------------------
L.Fountain = V(0, 0, 0)
L.SpawnRadius = 16
L.Spawns = {} :: { Vector3 }
for i = 0, 5 do
	local angle = math.rad(i * 60)
	table.insert(L.Spawns, V(math.cos(angle) * L.SpawnRadius, 0, math.sin(angle) * L.SpawnRadius))
end

-- ---------------------------------------------------------------------
-- Duell-Halle (0,−75) + 9 Pads (B3.2)
-- ---------------------------------------------------------------------
L.DuelFloor = { Pos = V(0, 0.05, -75), Size = V(140, 0.1, 60) }
L.DuelSign = V(0, 14, -50)
L.Letters = V(0, 16, -108) -- großer Block-Schriftzug "CLUTCH CLASH"
L.PadSize = V(20, 0.6, 12)
L.FfaPadDiameter = 12
L.SeatRadius = 1.6
L.FfaSeatRing = 4
L.Pads = {
	{ Id = 1, Mode = "Duel1", Pos = V(-48, 0, -60), Seats = 1, Color = Color3.fromRGB(90, 220, 110) },
	{ Id = 2, Mode = "Duel1", Pos = V(-16, 0, -60), Seats = 1, Color = Color3.fromRGB(90, 220, 110) },
	{ Id = 3, Mode = "Duel1", Pos = V(16, 0, -60), Seats = 1, Color = Color3.fromRGB(90, 220, 110) },
	{ Id = 4, Mode = "Duel2", Pos = V(48, 0, -60), Seats = 2, Color = Color3.fromRGB(60, 140, 255) },
	{ Id = 5, Mode = "Duel2", Pos = V(-48, 0, -82), Seats = 2, Color = Color3.fromRGB(60, 140, 255) },
	{ Id = 6, Mode = "Duel3", Pos = V(-16, 0, -82), Seats = 3, Color = Color3.fromRGB(170, 90, 255) },
	{ Id = 7, Mode = "Duel4", Pos = V(16, 0, -82), Seats = 4, Color = Color3.fromRGB(255, 80, 80) },
	{ Id = 8, Mode = "Mutator", Pos = V(48, 0, -82), Seats = 1, Color = Color3.fromRGB(255, 210, 40) },
	{ Id = 9, Mode = "FFA", Pos = V(0, 0, -100), Seats = 8, Color = Color3.fromRGB(255, 60, 170), Ffa = true },
} :: { PadDef }

-- Sitz-Versatz in Z je Anzahl Sitze pro Hälfte (B3.2)
L.SeatOffsets = {
	[1] = { 0 },
	[2] = { -2, 2 },
	[3] = { -3.5, 0, 3.5 },
	[4] = { -4.5, -1.5, 1.5, 4.5 },
} :: { [number]: { number } }

-- ---------------------------------------------------------------------
-- Crown Ring (95,0): Grube (Map CrownRing, Ursprung Config.Maps.CrownOrigin), Tribünen, Linie, Tafel
-- ---------------------------------------------------------------------
L.CrownCenter = V(95, 0, 0)
L.CrownStands = {
	{ Pos = V(95, 1.5, -32), Size = V(50, 3, 4) },
	{ Pos = V(95, 3, -35), Size = V(50, 6, 2) },
	{ Pos = V(95, 1.5, 32), Size = V(50, 3, 4) },
	{ Pos = V(95, 3, 35), Size = V(50, 6, 2) },
}
L.CrownLine = {
	V(64, 0, -10),
	V(64, 0, -6),
	V(64, 0, -2),
	V(64, 0, 2),
	V(64, 0, 6),
	V(64, 0, 10),
} :: { Vector3 }
L.CrownBoard = { Pos = V(128, 10, 0), Size = V(20, 10, 1), Look = V(-1, 0, 0) } -- Blick nach Westen

-- ---------------------------------------------------------------------
-- Training / Range (−131,0): Zone X −200..−62, Z −56..56
-- ---------------------------------------------------------------------
L.Range = {
	ZoneMin = V(-200, -2, -56),
	ZoneMax = V(-62, 22, 56),
	ShootX = -66, -- Schusslinie, Blick nach −X
	Lanes = { -35, -21, -7, 7, 21, 35 },
	Dividers = { -42, -28, -14, 0, 14, 28, 42 },
	DividerFromX = -70,
	DividerToX = -198,
	DummyX = { -81, -96, -126, -166 }, -- 15 / 30 / 60 / 100 Studs
	DummyDistances = { 15, 30, 60, 100 },
	RailLanes = { 3, 4 },
	RailX = -110,
	RailSwing = 5,
	BackX = -199,
	BoothZ = 48,
	BoothX = { -92, -84, -76, -68 },
	BoothDifficulties = { "Easy", "Normal", "Hard", "Insane" },
	BoothColors = {
		Color3.fromRGB(90, 220, 110),
		Color3.fromRGB(60, 140, 255),
		Color3.fromRGB(255, 160, 60),
		Color3.fromRGB(255, 70, 70),
	},
	BoothPadSize = V(4, 0.2, 4),
	Rack = { Pos = V(-64, 4, -52), Size = V(30, 8, 1) },
}

-- ---------------------------------------------------------------------
-- Shop-Straße (0,70): Kiosk-Buden 8×8×6 (X×Y×Z) mit Prompt-Attribut Window + Kisten-Automat
-- ---------------------------------------------------------------------
L.KioskSize = V(8, 8, 6)
L.Kiosks = {
	{
		Window = "Shop",
		Pos = V(-30, 0, 70),
		Label = "world.sign.shop",
		Color = Color3.fromRGB(255, 160, 60),
		Roof = Color3.fromRGB(255, 225, 120),
	},
	{
		Window = "Locker",
		Pos = V(-10, 0, 70),
		Label = "world.sign.locker",
		Color = Color3.fromRGB(185, 167, 242),
		Roof = Color3.fromRGB(235, 225, 255),
	},
	{
		Window = "Pass",
		Pos = V(34, 0, 70),
		Label = "world.sign.pass",
		Color = Color3.fromRGB(255, 60, 170),
		Roof = Color3.fromRGB(0, 230, 255),
	},
	{
		Window = "Quests",
		Pos = V(52, 0, 62),
		Label = "world.sign.quests",
		Color = Color3.fromRGB(90, 200, 120),
		Roof = Color3.fromRGB(230, 255, 220),
	},
	{
		Window = "Daily",
		Pos = V(-52, 0, 62),
		Label = "world.sign.daily",
		Color = Color3.fromRGB(60, 140, 255),
		Roof = Color3.fromRGB(255, 240, 160),
	},
} :: { KioskDef }
L.Crate = { Pos = V(12, 0, 74), Size = V(12, 16, 12) }

-- ---------------------------------------------------------------------
-- Bestenlisten (Südrand Z 104): 6 Tafeln 20×12, Mitte Y 8, Blick nach Norden
-- ---------------------------------------------------------------------
L.BoardKeys = { "Wins", "Elims", "BestStreak", "TotalXP", "WeeklyWins", "CrownBest" }
L.BoardX = { -75, -45, -15, 15, 45, 75 }
L.BoardZ = 104
L.BoardY = 8
L.BoardSize = V(20, 12, 1)
L.BoardRows = 10

-- ---------------------------------------------------------------------
-- VIP-Balkon (−70,−90): Plattform 40×1×24 auf Y 14, Wendeltreppe hinter der VIP-Tür
-- ---------------------------------------------------------------------
L.Vip = {
	Platform = { Pos = V(-70, 13.5, -90), Size = V(40, 1, 24) }, -- Oberkante Y 14
	Door = { Pos = V(-70, 4, -70), Size = V(6, 8, 1) },
	StairCenter = V(-70, 0, -74.25), -- Wendeltreppe (Treppe bei (−70,·,−74))
	StairSteps = 14, -- Stufen à 1 Stud bis Y 14
	StairOuter = 3.5,
	StairInner = 0.75,
	Tower = { MinX = -74.5, MaxX = -65.5, MinZ = -79, MaxZ = -69.5, Top = 15 },
}

-- ---------------------------------------------------------------------
-- Wege (Deko-Boden, zeigen Neulingen die Richtung)
-- ---------------------------------------------------------------------
L.Paths = {
	{ Pos = V(0, 0.03, -27), Size = V(10, 0.06, 34), Color = Color3.fromRGB(242, 213, 154) }, -- Nord: Duelle
	{ Pos = V(0, 0.03, 40), Size = V(10, 0.06, 40), Color = Color3.fromRGB(247, 183, 200) }, -- Süd: Shop
	{ Pos = V(-43, 0.03, 0), Size = V(46, 0.06, 10), Color = Color3.fromRGB(154, 209, 212) }, -- West: Training
	{ Pos = V(43, 0.03, 0), Size = V(42, 0.06, 10), Color = Color3.fromRGB(185, 167, 242) }, -- Ost: Krone
	{ Pos = V(0, 0.03, 68), Size = V(124, 0.06, 18), Color = Color3.fromRGB(244, 235, 221) }, -- Shop-Straße
}

return L
