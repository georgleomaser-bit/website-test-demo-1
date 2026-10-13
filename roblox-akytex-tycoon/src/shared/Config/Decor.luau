-- =====================================================================
--  AKYTEX TYCOON – Deko & Komfort (Config.Decor)
--  Besitzer: WP8 (Turm-Optik, Interiors, Lifestyle). Vertrag: DESIGN.md §C14.2 (Decor), §B4.8 (Deko & Komfort),
--  §C12.3 (Kurz-Codes im Plot-Attribut "Layout"), §C14.3 (Asset-Plätze, 0 = Code-Rezept).
--  Alle Zahlen sind Startwerte und 1:1 änderbar. Wird an alle Clients repliziert -> KEINE Geheimnisse hier!
--
--  Diese Datei lädt KEINE Roblox-Dienste (Farben als Hex-Text, CFrame nur über pcall) -> Luau-CLI-ladbar.
--
--  Abschnitte:
--    1) Plätze & Komfort (§B4.8)          3) Neon-Schriftzüge (sprachneutral, Marke)
--    2) Sets (6 + Saison)                 4) Die 68 Deko-Teile { Key, Code, Name, Set, Price, Comfort, Source, Recipe, Asset }
--  Quelle (Source): "Shop" = in der Boutique für CR kaufbar (Price > 0) · "Login" (Login-Kalender) · "League"
--    (Liga-Pokale) · "Season" (Skyline-Pass) – nicht kaufbar (Price = 0), kommen über ShopService.Grant { Decor }.
--  Recipe = Bau-Rezept für Shared/DecorModels: { Kind, A (Hauptfarbe), B (Zweitfarbe), C (Akzent/Neon), M (Material) }.
--  Code = Kurz-Code im Layout-Attribut ("s1", "c10", …): Kleinbuchstabe des Sets + laufende Nummer.
--  Zugriff: Config.Decor.Items (Liste, feste Reihenfolge) · Config.Decor.ByKey[key] · Config.Decor[key] (gleicher
--    Eintrag, damit „Config.Decor[key].Code“ aus §C12.3 wörtlich funktioniert).
--  Helfer: Decor.Validate(Config): { string }
-- =====================================================================

local Decor = {}

-- CFrame.identity nur, wenn Roblox-Typen da sind (Luau-CLI: nil -> nur für Tests)
local IDENTITY: any = nil
pcall(function()
	IDENTITY = (CFrame :: any).identity
end)

-- Leerer Asset-Platz (0 = Code-Rezept, §C14.3)
local function slot(): { [string]: any }
	return { MeshId = 0, TextureId = 0, Scale = 1, Offset = IDENTITY }
end

-- ---------------------------------------------------------------------
-- 1) PLÄTZE & KOMFORT (§B4.8)
--    3 feste Plätze je Etage, 8 im Penthouse. Komfort: jedes Teil 1–5 Punkte; je Etage +ComfortPct je Punkt,
--    höchstens ComfortMax (+10 %) je Etage. Kauf ins Lager (Anzahl je Teil), Platzieren/Entfernen gratis.
-- ---------------------------------------------------------------------
Decor.SlotsPerFloor = 3
Decor.PenthouseSlots = 8
Decor.ComfortPct = 0.005
Decor.ComfortMax = 0.10
Decor.ComfortItemMax = 5
Decor.StorageMax = 999 -- höchstens so viele Stück je Teil im Lager

-- ---------------------------------------------------------------------
-- 2) SETS (6 Sets à 10 Teile + Saison-Set S1 „Neon-Skyline“ mit 8 Teilen)
-- ---------------------------------------------------------------------
Decor.Sets = {
	{
		Key = "Startup",
		Code = "s",
		Name = { de = "Startup", en = "Startup" },
		Desc = { de = "Garagen-Charme für die ersten Etagen.", en = "Garage charm for your first floors." },
	},
	{
		Key = "Corporate",
		Code = "c",
		Name = { de = "Corporate", en = "Corporate" },
		Desc = { de = "Holz, Leder, Messing – klassisches Büro.", en = "Wood, leather, brass – a classic office." },
	},
	{
		Key = "GlassChrome",
		Code = "g",
		Name = { de = "Glas & Chrom", en = "Glass & Chrome" },
		Desc = { de = "Klare Linien, kühler Glanz.", en = "Clean lines, cool shine." },
	},
	{
		Key = "NeonCyber",
		Code = "n",
		Name = { de = "Neon-Cyber", en = "Neon Cyber" },
		Desc = { de = "Leuchtende Akzente für die Nacht.", en = "Glowing accents for the night." },
	},
	{
		Key = "LuxeGold",
		Code = "l",
		Name = { de = "Luxe-Gold", en = "Luxe Gold" },
		Desc = { de = "Samt, Gold und große Gesten.", en = "Velvet, gold and grand gestures." },
	},
	{
		Key = "ZenGarden",
		Code = "z",
		Name = { de = "Zen-Garten", en = "Zen Garden" },
		Desc = { de = "Ruhe über den Wolken.", en = "Calm above the clouds." },
	},
	{
		Key = "Season1",
		Code = "q",
		Name = { de = "Neon-Skyline (Saison 1)", en = "Neon Skyline (Season 1)" },
		Desc = { de = "Belohnungen aus dem Skyline-Pass.", en = "Rewards from the Skyline Pass." },
	},
}

-- ---------------------------------------------------------------------
-- 3) NEON-SCHRIFTZÜGE (Marke/Bauschild – sprachneutral, auf Neon-Teilen der Hülle)
-- ---------------------------------------------------------------------
Decor.Signs = {
	Startup = "STARTUP",
	Brand = "ΛKYTEX",
}

-- ---------------------------------------------------------------------
-- 4) DIE 68 DEKO-TEILE
-- ---------------------------------------------------------------------
local function item(
	key: string,
	code: string,
	set: string,
	de: string,
	en: string,
	price: number,
	comfort: number,
	source: string,
	recipe: { [string]: any }
): { [string]: any }
	return {
		Key = key,
		Code = code,
		Set = set,
		Name = { de = de, en = en },
		Price = price,
		Comfort = comfort,
		Source = source,
		Recipe = recipe,
		Asset = slot(),
	}
end

-- stylua: ignore start
Decor.Items = {
	-- Startup (s)
	item("DeskStartup",   "s1",  "Startup", "Startup-Schreibtisch", "Startup Desk",         2500,  1, "Shop",  { Kind = "Desk", A = "#b08a5a", B = "#2a3342", C = "#4f8cff", M = "WoodPlanks" }),
	item("BeanBag",       "s2",  "Startup", "Sitzsack",             "Bean Bag",             4000,  1, "Shop",  { Kind = "BeanBag", A = "#4f8cff", B = "#1a2130", C = "#e6ecf5", M = "Fabric" }),
	item("PlantMonstera", "s3",  "Startup", "Monstera",             "Monstera",             6000,  1, "Shop",  { Kind = "Plant", A = "#2f9e5b", B = "#e6ecf5", C = "#1f6f3f", M = "Ceramic" }),
	item("Whiteboard",    "s4",  "Startup", "Ideen-Whiteboard",     "Idea Whiteboard",      8000,  1, "Shop",  { Kind = "Whiteboard", A = "#f4f6fa", B = "#7d889a", C = "#22c55e", M = "SmoothPlastic" }),
	item("NeonArrow",     "s5",  "Startup", "Neon-Pfeil",           "Neon Arrow",           12000, 2, "Shop",  { Kind = "NeonArrow", A = "#22c55e", B = "#1a2130", C = "#22c55e", M = "Metal" }),
	item("MiniBull",      "s6",  "Startup", "Mini-Bulle",           "Mini Bull",            0,     2, "Login", { Kind = "Bull", A = "#4f8cff", B = "#1a2130", C = "#facc15", M = "SmoothPlastic", S = 0.55 }),
	item("SmoothieBar",   "s7",  "Startup", "Smoothie-Station",     "Smoothie Station",     15000, 2, "Shop",  { Kind = "Counter", A = "#e6ecf5", B = "#f59e0b", C = "#22c55e", M = "SmoothPlastic" }),
	item("RacingChair",   "s8",  "Startup", "Racing-Stuhl",         "Racing Chair",         18000, 2, "Shop",  { Kind = "Chair", A = "#ef4444", B = "#1a2130", C = "#e6ecf5", M = "Fabric" }),
	item("PosterRocket",  "s9",  "Startup", "Raketen-Poster",       "Rocket Poster",        20000, 1, "Shop",  { Kind = "Art", A = "#3b5bdb", B = "#f59e0b", C = "#e6ecf5", M = "SmoothPlastic" }),
	item("RugStartup",    "s10", "Startup", "Startup-Teppich",      "Startup Rug",          25000, 2, "Shop",  { Kind = "Rug", A = "#4f8cff", B = "#1a2130", C = "#e6ecf5", M = "Fabric" }),
	-- Corporate (c)
	item("DeskExec",      "c1",  "Corporate", "Chef-Schreibtisch",  "Executive Desk",       60000,  2, "Shop",  { Kind = "Desk", A = "#5b3a24", B = "#c8a165", C = "#4f8cff", M = "Wood" }),
	item("SofaLeather",   "c2",  "Corporate", "Ledersofa",          "Leather Sofa",         90000,  3, "Shop",  { Kind = "Sofa", A = "#6b3f2a", B = "#3a2418", C = "#c8a165", M = "Leather" }),
	item("Bookshelf",     "c3",  "Corporate", "Bücherregal",        "Bookshelf",            120000, 2, "Shop",  { Kind = "Bookshelf", A = "#5b3a24", B = "#c9d2de", C = "#3b5bdb", M = "Wood" }),
	item("PlantFicus",    "c4",  "Corporate", "Ficus",              "Ficus",                150000, 2, "Shop",  { Kind = "Tree", A = "#2f8f4e", B = "#5b3a24", C = "#c8a165", M = "Wood" }),
	item("GlobeBrass",    "c5",  "Corporate", "Messing-Globus",     "Brass Globe",          200000, 3, "Shop",  { Kind = "Globe", A = "#2563eb", B = "#c8a165", C = "#22c55e", M = "Metal" }),
	item("ClockWall",     "c6",  "Corporate", "Börsen-Standuhr",    "Exchange Clock",       250000, 2, "Shop",  { Kind = "Clock", A = "#3a2418", B = "#f4f6fa", C = "#c8a165", M = "Wood" }),
	item("MeetingTable",  "c7",  "Corporate", "Konferenztisch",     "Meeting Table",        300000, 3, "Shop",  { Kind = "Table", A = "#5b3a24", B = "#1f2937", C = "#c8a165", M = "Wood" }),
	item("LampBrass",     "c8",  "Corporate", "Stehlampe Messing",  "Brass Floor Lamp",     400000, 2, "Shop",  { Kind = "Lamp", A = "#c8a165", B = "#f4e3c1", C = "#ffd9a0", M = "Metal" }),
	item("TrophyBronze",  "c9",  "Corporate", "Liga-Pokal Bronze",  "League Cup Bronze",    0,      3, "League", { Kind = "Trophy", A = "#b8733d", B = "#1a2130", C = "#facc15", M = "Metal" }),
	item("TrophySilver",  "c10", "Corporate", "Liga-Pokal Silber",  "League Cup Silver",    0,      4, "League", { Kind = "Trophy", A = "#c0c7d4", B = "#1a2130", C = "#facc15", M = "Metal" }),
	-- Glas & Chrom (g)
	item("DeskGlass",     "g1",  "GlassChrome", "Glas-Schreibtisch", "Glass Desk",          1200000,  3, "Shop", { Kind = "Desk", A = "#a9c7ea", B = "#d7dee8", C = "#4f8cff", M = "Glass" }),
	item("EggChair",      "g2",  "GlassChrome", "Ei-Sessel Chrom",   "Chrome Egg Chair",    1800000,  3, "Shop", { Kind = "EggChair", A = "#e6ecf5", B = "#d7dee8", C = "#4f8cff", M = "SmoothPlastic" }),
	item("SculptChrome",  "g3",  "GlassChrome", "Chrom-Skulptur",    "Chrome Sculpture",    2500000,  3, "Shop", { Kind = "Sculpture", A = "#d7dee8", B = "#1f2937", C = "#4f8cff", M = "Metal" }),
	item("AquariumSmall", "g4",  "GlassChrome", "Aquarium",          "Aquarium",            3500000,  4, "Shop", { Kind = "Aquarium", A = "#22d3ee", B = "#d7dee8", C = "#f59e0b", M = "Glass" }),
	item("LampArc",       "g5",  "GlassChrome", "Bogenlampe",        "Arc Lamp",            4500000,  2, "Shop", { Kind = "ArcLamp", A = "#d7dee8", B = "#1f2937", C = "#e6f0ff", M = "Metal" }),
	item("TableGlass",    "g6",  "GlassChrome", "Glas-Couchtisch",   "Glass Coffee Table",  5500000,  3, "Shop", { Kind = "LowTable", A = "#a9c7ea", B = "#d7dee8", C = "#4f8cff", M = "Glass" }),
	item("ArtPrism",      "g7",  "GlassChrome", "Prisma-Kunst",      "Prism Art",           7000000,  3, "Shop", { Kind = "Prism", A = "#7c9cff", B = "#d7dee8", C = "#b36bff", M = "Glass" }),
	item("ChartWall",     "g8",  "GlassChrome", "Chart-Wand",        "Chart Wall",          9000000,  3, "Shop", { Kind = "Screen", A = "#0b0f17", B = "#d7dee8", C = "#4f8cff", M = "SmoothPlastic" }),
	item("BambooGlass",   "g9",  "GlassChrome", "Bambus im Glas",    "Bamboo in Glass",     11000000, 3, "Shop", { Kind = "Bamboo", A = "#5fae4f", B = "#a9c7ea", C = "#2f8f4e", M = "Glass" }),
	item("RugGeo",        "g10", "GlassChrome", "Geo-Teppich",       "Geo Rug",             14000000, 3, "Shop", { Kind = "Rug", A = "#d7dee8", B = "#3b6ea8", C = "#1f2937", M = "Fabric" }),
	-- Neon-Cyber (n)
	item("DeskNeon",      "n1",  "NeonCyber", "Neon-Desk",           "Neon Desk",           25000000,  3, "Shop", { Kind = "Desk", A = "#121824", B = "#1f2937", C = "#22d3ee", M = "SmoothPlastic" }),
	item("SignLambda",    "n2",  "NeonCyber", "ΛKYTEX-Neonschild",   "ΛKYTEX Neon Sign",    35000000,  4, "Shop", { Kind = "LambdaSign", A = "#4f8cff", B = "#121824", C = "#4f8cff", M = "Metal" }),
	item("HoloGlobe",     "n3",  "NeonCyber", "Holo-Globus",         "Holo Globe",          50000000,  4, "Shop", { Kind = "HoloGlobe", A = "#22d3ee", B = "#121824", C = "#7c5cff", M = "Metal" }),
	item("CyberChair",    "n4",  "NeonCyber", "Cyber-Sessel",        "Cyber Lounge Chair",  70000000,  3, "Shop", { Kind = "PodChair", A = "#121824", B = "#ec4899", C = "#22d3ee", M = "SmoothPlastic" }),
	item("TickerTotem",   "n5",  "NeonCyber", "Ticker-Säule",        "Ticker Totem",        90000000,  4, "Shop", { Kind = "Totem", A = "#121824", B = "#1f2937", C = "#22c55e", M = "Metal" }),
	item("NeonTree",      "n6",  "NeonCyber", "Neon-Baum",           "Neon Tree",           120000000, 4, "Shop", { Kind = "NeonTree", A = "#ec4899", B = "#121824", C = "#22d3ee", M = "Metal" }),
	item("RoboDog",       "n7",  "NeonCyber", "Robo-Hund",           "Robo Dog",            150000000, 4, "Shop", { Kind = "RoboDog", A = "#d7dee8", B = "#121824", C = "#22d3ee", M = "SmoothPlastic" }),
	item("LightCube",     "n8",  "NeonCyber", "Licht-Kubus",         "Light Cube",          180000000, 3, "Shop", { Kind = "LightCube", A = "#7c5cff", B = "#121824", C = "#b36bff", M = "Glass" }),
	item("RetroConsole",  "n9",  "NeonCyber", "Retro-Konsole",       "Retro Console",       220000000, 4, "Shop", { Kind = "Console", A = "#121824", B = "#4f8cff", C = "#ec4899", M = "SmoothPlastic" }),
	item("RugCircuit",    "n10", "NeonCyber", "Platinen-Teppich",    "Circuit Rug",         280000000, 3, "Shop", { Kind = "Rug", A = "#0f2a1e", B = "#22c55e", C = "#22d3ee", M = "Fabric" }),
	-- Luxe-Gold (l)
	item("DeskGold",      "l1",  "LuxeGold", "Gold-Schreibtisch",    "Gold Desk",           500000000,  4, "Shop",  { Kind = "Desk", A = "#1a1410", B = "#facc15", C = "#ffcf6e", M = "Marble" }),
	item("SofaVelvet",    "l2",  "LuxeGold", "Samt-Sofa",            "Velvet Sofa",         800000000,  4, "Shop",  { Kind = "Sofa", A = "#5b1f3a", B = "#facc15", C = "#ffcf6e", M = "Fabric" }),
	item("StatueBull",    "l3",  "LuxeGold", "Gold-Bulle",           "Golden Bull",         1200000000, 5, "Shop",  { Kind = "Bull", A = "#facc15", B = "#1a1410", C = "#ffcf6e", M = "Metal", S = 1 }),
	item("Chandelier",    "l4",  "LuxeGold", "Kronleuchter",         "Chandelier",          1800000000, 4, "Shop",  { Kind = "Chandelier", A = "#facc15", B = "#fff4dc", C = "#ffe2a8", M = "Metal" }),
	item("GrandPiano",    "l5",  "LuxeGold", "Flügel",               "Grand Piano",         2500000000, 5, "Shop",  { Kind = "Piano", A = "#0b0f17", B = "#f4f6fa", C = "#facc15", M = "SmoothPlastic" }),
	item("VaseGold",      "l6",  "LuxeGold", "Gold-Vase",            "Gold Vase",           3200000000, 3, "Shop",  { Kind = "Vase", A = "#facc15", B = "#1a1410", C = "#ec4899", M = "Metal" }),
	item("AquariumGrand", "l7",  "LuxeGold", "Riesen-Aquarium",      "Grand Aquarium",      4500000000, 5, "Shop",  { Kind = "Aquarium", A = "#22d3ee", B = "#facc15", C = "#f59e0b", M = "Glass", S = 1.35 }),
	item("FountainGold",  "l8",  "LuxeGold", "Gold-Brunnen",         "Gold Fountain",       6000000000, 5, "Shop",  { Kind = "Fountain", A = "#facc15", B = "#e6ecf5", C = "#22d3ee", M = "Marble" }),
	item("TrophyGold",    "l9",  "LuxeGold", "Liga-Pokal Gold",      "League Cup Gold",     0,          5, "League", { Kind = "Trophy", A = "#facc15", B = "#1a1410", C = "#ffcf6e", M = "Metal", S = 1.15 }),
	item("TrophyDiamond", "l10", "LuxeGold", "Liga-Pokal Diamant",   "League Cup Diamond",  0,          5, "League", { Kind = "Trophy", A = "#a5f3fc", B = "#1a1410", C = "#e0f2fe", M = "Glass", S = 1.25 }),
	-- Zen-Garten (z)
	item("Bonsai",        "z1",  "ZenGarden", "Bonsai",              "Bonsai",              10000000000,  4, "Shop", { Kind = "Bonsai", A = "#3f8f3a", B = "#5b3a24", C = "#2a3342", M = "Slate" }),
	item("SandGarden",    "z2",  "ZenGarden", "Sand-Garten",         "Sand Garden",         15000000000,  4, "Shop", { Kind = "SandGarden", A = "#e8dcc0", B = "#5b5f66", C = "#3f8f3a", M = "Sand" }),
	item("StoneLantern",  "z3",  "ZenGarden", "Steinlaterne",        "Stone Lantern",       22000000000,  3, "Shop", { Kind = "Lantern", A = "#8a8f98", B = "#5b5f66", C = "#ffd9a0", M = "Slate" }),
	item("WaterBowl",     "z4",  "ZenGarden", "Wasserschale",        "Water Bowl",          30000000000,  4, "Shop", { Kind = "WaterBowl", A = "#5b5f66", B = "#22d3ee", C = "#f4f6fa", M = "Slate" }),
	item("CherryTree",    "z5",  "ZenGarden", "Kirschbaum",          "Cherry Tree",         45000000000,  5, "Shop", { Kind = "BlossomTree", A = "#f9a8d4", B = "#4a2f20", C = "#fbcfe8", M = "Wood" }),
	item("Gong",          "z6",  "ZenGarden", "Klang-Gong",          "Sound Gong",          60000000000,  3, "Shop", { Kind = "Gong", A = "#c8a165", B = "#3a2418", C = "#facc15", M = "Metal" }),
	item("TeaTable",      "z7",  "ZenGarden", "Tee-Tisch",           "Tea Table",           80000000000,  4, "Shop", { Kind = "LowTable", A = "#3a2418", B = "#c8a165", C = "#3f8f3a", M = "Wood" }),
	item("KoiPond",       "z8",  "ZenGarden", "Koi-Teich",           "Koi Pond",            120000000000, 5, "Shop", { Kind = "Pond", A = "#5b5f66", B = "#1e6f8f", C = "#f97316", M = "Slate" }),
	item("BambooScreen",  "z9",  "ZenGarden", "Bambus-Paravent",     "Bamboo Screen",       180000000000, 3, "Shop", { Kind = "Screenwall", A = "#c8b27a", B = "#5b3a24", C = "#3f8f3a", M = "Wood" }),
	item("CalmPod",       "z10", "ZenGarden", "Ruhe-Kapsel",         "Calm Pod",            250000000000, 5, "Shop", { Kind = "CalmPod", A = "#f4f6fa", B = "#8fb3a0", C = "#a7f3d0", M = "SmoothPlastic" }),
	-- Saison 1 „Neon-Skyline“ (q) – Skyline-Pass
	item("SkylineModel",  "q1",  "Season1", "Skyline-Modell",        "Skyline Model",       0, 4, "Season", { Kind = "SkylineModel", A = "#1a2130", B = "#4f8cff", C = "#7c5cff", M = "Glass" }),
	item("NeonBench",     "q2",  "Season1", "Neon-Bank",             "Neon Bench",          0, 3, "Season", { Kind = "Bench", A = "#121824", B = "#7c5cff", C = "#b36bff", M = "Metal" }),
	item("HoloTicker",    "q3",  "Season1", "Holo-Ticker",           "Holo Ticker",         0, 4, "Season", { Kind = "Totem", A = "#1a2130", B = "#7c5cff", C = "#4f8cff", M = "Glass" }),
	item("SkylineRug",    "q4",  "Season1", "Skyline-Teppich",       "Skyline Rug",         0, 3, "Season", { Kind = "Rug", A = "#1a1440", B = "#7c5cff", C = "#4f8cff", M = "Fabric" }),
	item("NeonPalm",      "q5",  "Season1", "Neon-Palme",            "Neon Palm",           0, 4, "Season", { Kind = "Palm", A = "#7c5cff", B = "#1a2130", C = "#22d3ee", M = "Metal" }),
	item("OrbitLamp",     "q6",  "Season1", "Orbit-Lampe",           "Orbit Lamp",          0, 3, "Season", { Kind = "OrbitLamp", A = "#b36bff", B = "#1a2130", C = "#e9d5ff", M = "Metal" }),
	item("BlimpModel",    "q7",  "Season1", "Luftschiff-Modell",     "Blimp Model",         0, 4, "Season", { Kind = "Blimp", A = "#d7dee8", B = "#1a2130", C = "#4f8cff", M = "SmoothPlastic" }),
	item("SkylineTrophy", "q8",  "Season1", "Skyline-Pokal",         "Skyline Cup",         0, 5, "Season", { Kind = "Trophy", A = "#b36bff", B = "#1a2130", C = "#7c5cff", M = "Glass", S = 1.1 }),
}
-- stylua: ignore end

-- Nachschlage-Tabellen (Schlüssel -> Eintrag, Code -> Schlüssel)
Decor.ByKey = {} :: { [string]: { [string]: any } }
Decor.ByCode = {} :: { [string]: string }
local RESERVED: { [string]: boolean } = {
	SlotsPerFloor = true,
	PenthouseSlots = true,
	ComfortPct = true,
	ComfortMax = true,
	ComfortItemMax = true,
	StorageMax = true,
	Sets = true,
	Signs = true,
	Items = true,
	ByKey = true,
	ByCode = true,
	Validate = true,
}
for _, entry in ipairs(Decor.Items) do
	assert(Decor.ByKey[entry.Key] == nil, "[Config.Decor] doppelter Schlüssel " .. entry.Key)
	assert(Decor.ByCode[entry.Code] == nil, "[Config.Decor] doppelter Code " .. entry.Code)
	assert(not RESERVED[entry.Key], "[Config.Decor] Schlüssel kollidiert mit einem Feld: " .. entry.Key)
	Decor.ByKey[entry.Key] = entry
	Decor.ByCode[entry.Code] = entry.Key;
	(Decor :: any)[entry.Key] = entry
end

-- =====================================================================
-- PRÜFUNG (Config.Validate sammelt alle Meldungen; leer = alles ok)
-- =====================================================================
local SOURCES: { [string]: boolean } = { Shop = true, Login = true, League = true, Season = true }

local function isNum(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isPair(v: any): boolean
	return type(v) == "table" and type(v.de) == "string" and v.de ~= "" and type(v.en) == "string" and v.en ~= ""
end

local function isHex(v: any): boolean
	return type(v) == "string" and string.match(v, "^#%x%x%x%x%x%x$") ~= nil
end

function Decor.Validate(_config: any): { string }
	local errors: { string } = {}
	local function add(text: string)
		table.insert(errors, "Config.Decor." .. text)
	end
	local function int(path: string, v: any, lo: number, hi: number)
		if not isNum(v) or v % 1 ~= 0 or v < lo or v > hi then
			add(("%s: ganze Zahl %s … %s erwartet"):format(path, tostring(lo), tostring(hi)))
		end
	end
	int("SlotsPerFloor", Decor.SlotsPerFloor, 1, 16)
	int("PenthouseSlots", Decor.PenthouseSlots, 1, 16)
	int("ComfortItemMax", Decor.ComfortItemMax, 1, 20)
	int("StorageMax", Decor.StorageMax, 1, 100000)
	if not isNum(Decor.ComfortPct) or Decor.ComfortPct < 0 or Decor.ComfortPct > 0.1 then
		add("ComfortPct: Zahl 0 … 0,1 erwartet")
	end
	if not isNum(Decor.ComfortMax) or Decor.ComfortMax < 0 or Decor.ComfortMax > 1 then
		add("ComfortMax: Zahl 0 … 1 erwartet")
	end
	local sets: { [string]: string } = {}
	for i, set in ipairs(Decor.Sets) do
		local where = ("Sets[%d]"):format(i)
		if type(set.Key) ~= "string" or type(set.Code) ~= "string" or not string.match(set.Code, "^%l$") then
			add(where .. ": Key + Code (ein Kleinbuchstabe) erwartet")
		else
			assert(sets[set.Key] == nil, "[Config.Decor] doppeltes Set " .. set.Key)
			sets[set.Key] = set.Code
		end
		if not isPair(set.Name) then
			add(where .. ".Name: { de, en } erwartet")
		end
	end
	if #Decor.Items ~= 68 then
		add(("Items: genau 68 Teile erwartet (§B4.8), gefunden %d"):format(#Decor.Items))
	end
	for i, entry in ipairs(Decor.Items) do
		local where = ("Items[%d] (%s)"):format(i, tostring(entry.Key))
		if type(entry.Key) ~= "string" or not string.match(entry.Key, "^[%w_]+$") or #entry.Key > 40 then
			add(where .. ".Key: Buchstaben/Ziffern (≤ 40) erwartet")
		end
		local setCode = sets[entry.Set]
		if setCode == nil then
			add(where .. ".Set: unbekanntes Set")
		elseif type(entry.Code) ~= "string" or string.match(entry.Code, "^" .. setCode .. "%d%d?$") == nil then
			add(where .. ".Code: Set-Buchstabe + Nummer erwartet")
		end
		if not isPair(entry.Name) then
			add(where .. ".Name: { de, en } erwartet")
		end
		int(where .. ".Comfort", entry.Comfort, 1, Decor.ComfortItemMax)
		if not SOURCES[entry.Source] then
			add(where .. ".Source: Shop/Login/League/Season erwartet")
		elseif entry.Source == "Shop" then
			int(where .. ".Price", entry.Price, 1, 1e14 - 1)
		elseif entry.Price ~= 0 then
			add(where .. ".Price: 0 erwartet (nicht kaufbar)")
		end
		local recipe = entry.Recipe
		if type(recipe) ~= "table" or type(recipe.Kind) ~= "string" or recipe.Kind == "" then
			add(where .. ".Recipe.Kind: Text erwartet")
		else
			for _, field in ipairs({ "A", "B", "C" }) do
				if not isHex(recipe[field]) then
					add(where .. ".Recipe." .. field .. ": #rrggbb erwartet")
				end
			end
			if type(recipe.M) ~= "string" then
				add(where .. ".Recipe.M: Material-Name erwartet")
			end
			if recipe.S ~= nil and (not isNum(recipe.S) or recipe.S < 0.3 or recipe.S > 2) then
				add(where .. ".Recipe.S: Skala 0,3 … 2 erwartet")
			end
		end
		if type(entry.Asset) ~= "table" then
			add(where .. ".Asset: Asset-Platz erwartet")
		end
	end
	for key, text in pairs(Decor.Signs) do
		if type(text) ~= "string" or text == "" or #text > 24 then
			add("Signs." .. tostring(key) .. ": Text (1–24 Zeichen) erwartet")
		end
	end
	return errors
end

return Decor
