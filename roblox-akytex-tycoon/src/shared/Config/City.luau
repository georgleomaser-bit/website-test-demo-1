-- =====================================================================
--  AKYTEX TYCOON – Stadt, Licht, Wetter, Umgebungsleben (Config.City)
--  Besitzer: WP7 (Stadt, Grafik, Fahrzeuge). Vertrag: DESIGN.md §C14.2 (City), §A4 (Licht, Materialien, Tag/Nacht,
--  Markt-Wetter, Crash/Rally), §A5 (Welt-Karte), §B3 (Plots, Streaming, Teilebudget), §C16 (Budgets).
--  Alle Zahlen sind Startwerte aus DESIGN.md und 1:1 änderbar. Wird an alle Clients repliziert -> KEINE Geheimnisse hier!
--
--  Koordinaten: Ursprung = Plaza-Mitte, Boden-Oberkante Y = 0. +X = Osten (Helipad), −X = Westen (Λ Motors),
--  +Z = Süden (Marina), −Z = Norden (Börsensaal, Villenhügel). Winkel in Grad, 0° = +X, 90° = +Z (Süden).
--
--  Abschnitte:
--    1) Ebenen & Boden           6) Firmen-Läden & Hologramme      11) Teilebudget & Aufbau
--    2) Licht & Look (§A4)       7) Kulisse (Finanzviertel)        12) Streaming (§B3)
--    3) Markt-Wetter (§A4)       8) Umgebungsleben (nur Client)    13) Asset-Plätze (§C14.3)
--    4) Zonen (§A5)              9) Lichter & Budget                14) Helfer (Routen, Plot-Seiten) + Prüfung
--    5) Plots, Straßen, Routen  10) Schilder (Marken, sprachneutral)
--  Helfer (rein, auf Server und Client gleich):
--    City.RoadRadius(road, angleDeg, offset?): number   Mittellinien-Radius (Ring weicht dem Börsensaal aus)
--    City.RoutePoints(name, spacing?): { Vector3 }      geschlossene Route (letzter Punkt = erster), Y = Fahrbahn
--    City.PlotCFrame(plot): CFrame                      Plot-Mitte auf der Plot-Oberkante, LookVector zur Plaza
--    City.ShopCFrame(instId): CFrame?                   Laden-Mitte am Boden, LookVector = Eingang (zur Plaza)
--    City.Validate(Config): { string }
-- =====================================================================

local City = {}

-- Leerer Asset-Platz (0 = Code-Rezept, §C14.3)
local function slot(): { [string]: any }
	return { MeshId = 0, TextureId = 0, Scale = 1, Offset = CFrame.identity }
end

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- ---------------------------------------------------------------------
-- 1) EBENEN & BODEN – Oberkanten in Studs
-- ---------------------------------------------------------------------
City.Levels = {
	Ground = 0, -- Terrain-Oberkante (Pflaster)
	Road = 0.25, -- Fahrbahn-Oberkante (Teile liegen leicht auf dem Terrain)
	Walk = 0.6, -- Gehweg, Plaza, Plot-Oberkante
	RoadThickness = 1,
	WalkThickness = 1.2,
}
City.Ground = {
	MapSize = 2048, -- 2.048 × 2.048 Studs (§A5)
	Depth = 8, -- Terrain-Dicke unter Y = 0
	CityRadius = 600, -- innerhalb: Pflaster, außerhalb: Gras
	CityMaterial = Enum.Material.Pavement,
	OuterMaterial = Enum.Material.Grass,
	Colors = { -- Terrain-Materialfarben (dunkle Premium-Stadt)
		Pavement = rgb(58, 62, 70),
		Grass = rgb(46, 78, 54),
		Rock = rgb(70, 72, 78),
		Ground = rgb(74, 66, 58),
		Sand = rgb(150, 138, 110),
		Asphalt = rgb(38, 40, 46),
	},
	Water = {
		Color = rgb(18, 52, 78),
		Transparency = 0.35,
		Reflectance = 0.6,
		WaveSize = 0.08,
		WaveSpeed = 6,
	},
}

-- ---------------------------------------------------------------------
-- 2) LICHT & LOOK (§A4) – GraphicsService setzt den Tag-Startwert, WorldLook rechnet live (Client)
--    Lighting.Technology = Future steht in default.project.json (Skripte dürfen es nicht setzen).
-- ---------------------------------------------------------------------
City.Look = {
	Day = {
		Ambient = rgb(92, 98, 112),
		OutdoorAmbient = rgb(128, 136, 152),
		Brightness = 2.4,
		ColorShiftTop = rgb(255, 246, 232),
		ExposureCompensation = 0,
		Atmosphere = {
			Density = 0.30,
			Haze = 1.2,
			Color = rgb(199, 214, 255), -- #c7d6ff
			Decay = rgb(106, 122, 154),
			Glare = 0.2,
			Offset = 0.25,
		},
	},
	Night = {
		Ambient = rgb(26, 32, 52),
		OutdoorAmbient = rgb(38, 46, 74),
		Brightness = 1.1,
		ColorShiftTop = rgb(124, 156, 255), -- #7c9cff (Space-Set)
		ExposureCompensation = 0.15,
		Atmosphere = {
			Density = 0.38,
			Haze = 1.8,
			Color = rgb(199, 214, 255), -- #c7d6ff (gleich, bei Nacht dunkel = bläulicher Dunst)
			Decay = rgb(40, 46, 88),
			Glare = 0,
			Offset = 0.15,
		},
	},
	Golden = { -- goldene Stunde (Kamera-Anflug §B2, Override "Golden")
		ClockTime = 17.6,
		Tint = rgb(255, 236, 214),
	},
	Bloom = { Intensity = 0.55, Size = 24, Threshold = 1.5 },
	SunRays = { Intensity = 0.04, Spread = 0.6 },
	ColorCorrection = { Contrast = 0.08, Saturation = 0.05, Brightness = 0, Tint = rgb(255, 255, 255) },
	DepthOfField = { FarIntensity = 0.28, FocusDistance = 14, InFocusRadius = 22, NearIntensity = 0.2 }, -- nur Menüs/Kamerafahrten
	Sky = { StarCount = 3000, SunAngularSize = 12, MoonAngularSize = 9 },
	Shadows = { Softness = 0.15, Latitude = 41 },
	Crash = { Tint = rgb(255, 218, 218), Saturation = -0.15, Contrast = 0.14, Atmosphere = rgb(255, 176, 168) }, -- #ffdada
	Rally = { Tint = rgb(255, 244, 220), Saturation = 0.12, Contrast = 0.1, Aurora = { rgb(34, 197, 94), rgb(34, 211, 238) } },
	BlendSeconds = 4, -- Übergänge (Crash/Rally/Wetter) so weich
	WindowCascade = 0.05, -- Fensterlichter: Sekunden je Etage (von unten nach oben)
	WindowOnAt = 18.5, -- ClockTime: Fenster an (Sonnenuntergang)
	WindowOffAt = 6.2, -- ClockTime: Fenster aus (nach Sonnenaufgang)
	WindowLit = rgb(255, 214, 150), -- warmes Fensterlicht (Neon)
	WindowDark = rgb(40, 52, 72), -- Glas tagsüber
}

-- ---------------------------------------------------------------------
-- 3) MARKT-WETTER (§A4, MARKET.md §5.3): Regime R aus dem Frame
-- ---------------------------------------------------------------------
City.Weather = {
	ClearBelow = 0.85, -- R < 0,85 klar
	StormAbove = 1.2, -- R > 1,2 Sturm
	Cover = { Clear = 0.2, Clouds = 0.45, Storm = 0.85 },
	Density = { Clear = 0.5, Clouds = 0.65, Storm = 0.92 },
	CloudColor = { Clear = rgb(255, 255, 255), Storm = rgb(120, 128, 146) },
	Rain = { Rate = 380, Radius = 70, Height = 45, Speed = 120, Color = rgb(190, 205, 230) },
	Lightning = { MinGap = 6, MaxGap = 14, Flash = 0.12 }, -- harmlose Blitz-Flashes ohne Schaden
	BlendSeconds = 8,
}

-- ---------------------------------------------------------------------
-- 4) ZONEN (§A5) – Mittelpunkte am Boden, Maße in Studs
-- ---------------------------------------------------------------------
City.Zones = {
	Plaza = { Center = Vector3.new(0, 0, 0), Radius = 130, LogoRadius = 46, BellZoneRadius = 18 },
	Exchange = { Center = Vector3.new(0, 0, -190), Width = 180, Depth = 140, Height = 70, DomeRadius = 60 },
	Motors = { Center = Vector3.new(-760, 0, 0), Width = 160, Depth = 100, Height = 26, Turntables = 12 },
	Chrono = { Center = Vector3.new(-760, 0, 190), Width = 90, Depth = 60, Height = 22, Vitrines = 8 },
	Marina = { Center = Vector3.new(0, 0, 780), Width = 600, Depth = 300, WaterDepth = 18, Berths = 6 },
	Hill = { Center = Vector3.new(0, 0, -820), Peak = 120, Radius = 240, Villas = 4 },
	Helipad = { Center = Vector3.new(780, 0, 0), TowerHeight = 60, PadRadius = 22 },
	Backdrop = { InnerRadius = 640, OuterRadius = 880, Count = 36 }, -- NE/NW-Quadranten (z < 0)
}

-- ---------------------------------------------------------------------
-- 5) PLOTS, STRASSEN, ROUTEN
-- ---------------------------------------------------------------------
City.Plots = { Count = 10, Radius = 420, StartAngle = 18, Step = 36, Size = 110 } -- §A5: R 420, 18° + k·36°, 110 × 110

City.Roads = {
	-- Ring-Boulevard R 230–260 (2 × 2 Spuren). Weicht dem Börsensaal (Rückseite z = −260) im Norden in einem
	-- Bogen aus: die Mittellinie bleibt außerhalb des Rechtecks |x| ≤ HalfX, −Depth ≤ z ≤ 0 (weich gerundet).
	Ring = { Radius = 245, Width = 30, Avoid = { HalfX = 120, Depth = 290, Smooth = 40 } },
	Outer = { Radius = 560, Width = 30 },
	Highway = {
		Radius = 950,
		Width = 40,
		Ramps = { 36, 144 }, -- Auf-/Abfahrten vom äußeren Ring
		DriftArcs = { { 20, 52 }, { 128, 160 }, { 200, 232 }, { 308, 340 } }, -- rot-weiße Kurven-Kerbs
		TunnelHeight = 22, -- Tunnel durch den Villenhügel (Norden)
	},
	Avenues = { 0, 180 }, -- Ost (Helipad) und West (Λ Motors)
	AvenueWidth = 30,
	Driveway = 20, -- Plot-Einfahrt
	WalkWidth = 6, -- Gehweg je Seite
}

-- Routen (geschlossen) für Verkehr (Client), Parade/Bulle (WP11) und CityService.Route
City.Routes = {
	Ring = { Road = "Ring", Offset = 0, Spacing = 24 },
	Outer = { Road = "Outer", Offset = 0, Spacing = 30 },
	Highway = { Road = "Highway", Offset = 0, Spacing = 40 },
	Parade = { Road = "Ring", Offset = -7.5, Spacing = 20 }, -- innere Spur des Ring-Boulevards
}

-- Spuren für den Verkehr (Rechtsverkehr: Richtung +1 = steigender Winkel fährt innen)
City.Lanes = {
	{ Road = "Ring", Offset = -11.25, Dir = 1, Speed = 34 },
	{ Road = "Ring", Offset = -3.75, Dir = 1, Speed = 42 },
	{ Road = "Ring", Offset = 3.75, Dir = -1, Speed = 42 },
	{ Road = "Ring", Offset = 11.25, Dir = -1, Speed = 34 },
	{ Road = "Outer", Offset = -7.5, Dir = 1, Speed = 48 },
	{ Road = "Outer", Offset = 7.5, Dir = -1, Speed = 48 },
	{ Road = "Highway", Offset = -12, Dir = 1, Speed = 82 },
	{ Road = "Highway", Offset = -4, Dir = 1, Speed = 96 },
	{ Road = "Highway", Offset = 4, Dir = -1, Speed = 96 },
	{ Road = "Highway", Offset = 12, Dir = -1, Speed = 82 },
}

-- ---------------------------------------------------------------------
-- 6) FIRMEN-LÄDEN & HOLOGRAMME (§A5) – Läden bekommen Spot + Mini-Ticker, solange ihre Firma eine aktive News hat
-- ---------------------------------------------------------------------
-- Pflichtform §C14.2: Shops = { [instId] = AnchorName }
City.Shops = {
	[22] = "ShopBurger", -- Burgerplanet-Diner
	[19] = "ShopKnusperix", -- Knusperix-Automaten
	[15] = "ShopVelocitra", -- Velocitra-Schaufenster
	[31] = "ShopTowerbank", -- Towerbank-Automaten
	[25] = "ShopArcadeon", -- Arcadeon-Halle (Videospiele)
	[21] = "ShopSneakora", -- Sneakora-Laden
}
-- Lage im Grüngürtel zwischen Plaza und Ring-Boulevard, Eingang zur Plaza
City.ShopSites = {
	{ I = 22, Angle = 36, Style = "Diner", Name = "BURGERPLANET" },
	{ I = 19, Angle = 72, Style = "Vending", Name = "KNUSPERIX" },
	{ I = 15, Angle = 108, Style = "Showroom", Name = "VELOCITRA" },
	{ I = 31, Angle = 144, Style = "Bank", Name = "TOWERBANK" },
	{ I = 25, Angle = 216, Style = "Arcade", Name = "ARCADEON" },
	{ I = 21, Angle = 324, Style = "Sneaker", Name = "SNEAKORA" },
}
City.ShopRadius = 186
City.ShopSize = Vector3.new(40, 18, 26)
City.ShopNewsSeconds = 120 -- so lange gilt eine Firmen-News als "aktiv" (zusätzlich Zeilen-Flag News im Frame)

-- Hologramm-Werbetafeln fiktiver Firmen (Spielfiktion, keine Werbung) – baut CityLife (Client)
City.Billboards = {
	{ I = 1, Angle = 18, Radius = 206, Height = 24 },
	{ I = 4, Angle = 54, Radius = 206, Height = 26 },
	{ I = 7, Angle = 90, Radius = 206, Height = 24 },
	{ I = 13, Angle = 126, Radius = 206, Height = 26 },
	{ I = 26, Angle = 162, Radius = 206, Height = 24 },
	{ I = 11, Angle = 198, Radius = 206, Height = 26 },
	{ I = 30, Angle = 234, Radius = 206, Height = 24 },
	{ I = 32, Angle = 306, Radius = 206, Height = 24 },
	{ I = 2, Angle = 0, Radius = 318, Height = 30 },
	{ I = 16, Angle = 36, Radius = 318, Height = 30 },
	{ I = 9, Angle = 72, Radius = 318, Height = 30 },
	{ I = 24, Angle = 108, Radius = 318, Height = 30 },
	{ I = 18, Angle = 144, Radius = 318, Height = 30 },
	{ I = 5, Angle = 180, Radius = 318, Height = 30 },
	{ I = 29, Angle = 216, Radius = 318, Height = 30 },
	{ I = 33, Angle = 324, Radius = 318, Height = 30 },
}

-- ---------------------------------------------------------------------
-- 7) KULISSE (Finanzviertel NE/NW, R 640–880): 36 Deko-Türme (5–8 Parts), je mit Leuchtschild einer Firma
-- ---------------------------------------------------------------------
City.Backdrop = {
	AngleRanges = { { 188, 252 }, { 288, 352 } }, -- NW und NE, Villenhügel (≈ 255–285°) bleibt frei
	Rings = { 660, 740, 815, 870 },
	MinHeight = 90,
	MaxHeight = 230,
	MinWidth = 28,
	MaxWidth = 46,
	Seed = 7351, -- feste Saat -> gleiche Skyline auf allen Servern
	Keepout = { -- Rechtecke { MinX, MinZ, MaxX, MaxZ } (Λ Motors, Helipad)
		{ -870, -80, -650, 80 },
		{ 660, -90, 900, 110 },
	},
}

-- ---------------------------------------------------------------------
-- 8) UMGEBUNGSLEBEN (nur Client; Verkehr/Drohnen aus Config.Quality, Rest hier je Grafikstufe)
-- ---------------------------------------------------------------------
City.Life = {
	Billboards = { Low = 4, Medium = 8, High = 12, Ultra = 16 },
	Blimp = { Low = true, Medium = true, High = true, Ultra = true, Radius = 720, Height = 270, Speed = 11 },
	TrafficHeight = 0.25, -- Fahrbahn
	TrafficColors = {
		rgb(30, 34, 44),
		rgb(225, 230, 238),
		rgb(79, 140, 255),
		rgb(139, 92, 246),
		rgb(170, 180, 195),
		rgb(20, 24, 30),
		rgb(239, 68, 68),
		rgb(34, 197, 94),
	},
	Drones = { MinHeight = 70, MaxHeight = 150, MinRadius = 160, MaxRadius = 700, Speed = 26 },
	UpdateRadius = 900, -- Verkehr weiter weg als 900 Studs wird nicht bewegt (unsichtbar geparkt)
	SpinRadius = 260, -- drehende Ausstellungsstücke (Drehteller, Vitrinen, Leuchtturm) nur so nah
}

-- ---------------------------------------------------------------------
-- 9) LICHTER & BUDGET – Server legt alle Stadt-Lichter AUS an (Attribut "Budget"), WorldLook schaltet die
--    nächsten N je Grafikstufe ein (Quality.Budget("Lights")), Laternen nur nachts (Attribut "NightOnly").
-- ---------------------------------------------------------------------
City.Lights = {
	Lantern = { Range = 26, Brightness = 2.2, Color = rgb(255, 226, 180) },
	Accent = { Range = 18, Brightness = 1.6, Color = rgb(79, 140, 255) },
	Hall = { Range = 40, Brightness = 1.2, Color = rgb(235, 240, 255) },
	Spot = { Range = 34, Brightness = 4, Angle = 50, Color = rgb(255, 240, 210) },
	ManageHz = 2, -- so oft sortiert WorldLook die Lichter neu
	MaxManaged = 600,
}

-- ---------------------------------------------------------------------
-- 10) SCHILDER – Markennamen (sprachneutral, keine echten Firmen)
-- ---------------------------------------------------------------------
City.Signs = {
	{ Key = "Exchange", Name = "AKYTEX EXCHANGE" },
	{ Key = "Motors", Name = "Λ MOTORS" },
	{ Key = "Chrono", Name = "CHRONOHAUS" },
	{ Key = "Marina", Name = "MARINA" },
	{ Key = "Heliport", Name = "HELIPORT" },
	{ Key = "Academy", Name = "AKADEMIE" },
	{ Key = "Logo", Name = "ΛKYTEX" },
}

-- ---------------------------------------------------------------------
-- 11) TEILEBUDGET & AUFBAU (§B3, §C16)
-- ---------------------------------------------------------------------
City.PartBudget = 12000 -- Stadt statisch ≤ 12.000 Server-Teile (SelfTest zählt)
City.BuildPerFrame = 400 -- Aufbau beim Start ≤ 400 Parts je Frame
City.TerrainPerFrame = 3 -- Terrain-Aufträge je Frame (FillBlock/WriteVoxels-Kacheln)

-- ---------------------------------------------------------------------
-- 12) STREAMING (§B3): Plaza, Börsensaal, Ringstraßen Persistent; Kulisse Atomic + LevelOfDetail StreamingMesh
-- ---------------------------------------------------------------------
City.Streaming = {
	Persistent = { Plaza = true, Exchange = true, Ring = true, Outer = true },
	MeshLod = { Backdrop = true, Plots = true, Exchange = true }, -- aus der Ferne sichtbar bleiben (in Studio prüfen)
}

-- ---------------------------------------------------------------------
-- 13) ASSET-PLÄTZE (§C14.3) – 0 = Code-Rezept; gesetzte Ids lädt AssetSlot beim Start vor ("City.<Name>")
-- ---------------------------------------------------------------------
City.Assets = {
	Blimp = slot(), -- Luftschiff mit ΛKYTEX-Logo (Client)
	Fountain = slot(), -- Brunnen auf der Plaza
	Bell = slot(), -- Börsenglocke
	Lighthouse = slot(), -- Leuchtturm Marina
	Jet = slot(), -- Deko-Jet im Hangar
	Yacht = slot(), -- Deko-Yachten (befahrbar erst v1.1)
	Heli = slot(), -- Helikopter-Platzhalter (v1.1)
	Villa = slot(), -- Deko-Villen
	Drone = slot(), -- Lieferdrohne (Client)
	TrafficCar = slot(), -- Verkehrsauto (Client)
	Tiko = slot(), -- Tiko-Hologramm auf der Plaza
}

-- =====================================================================
-- 14) HELFER (rein; Server-CityLayout, CityService und Client-CityLife rechnen identisch)
-- =====================================================================
local HUGE = math.huge

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= HUGE and n ~= -HUGE
end

-- weiches Maximum (Polynom, exakt a solange b < a − k)
local function smoothMax(a: number, b: number, k: number): number
	if k <= 0 then
		return math.max(a, b)
	end
	local h = math.clamp(0.5 + 0.5 * (b - a) / k, 0, 1)
	return a + (b - a) * h + k * h * (1 - h)
end

-- Mittellinien-Radius einer Ringstraße beim Winkel (Grad); offset = radialer Spur-Versatz
function City.RoadRadius(road: string, angleDeg: number, offset: number?): number
	local def = City.Roads[road]
	local base = if type(def) == "table" and finite(def.Radius) then def.Radius else 245
	local r = base
	local avoid = if type(def) == "table" then def.Avoid else nil
	if type(avoid) == "table" then
		local a = math.rad(angleDeg)
		local c, s = math.cos(a), math.sin(a)
		if s < -1e-6 then
			local tx = if math.abs(c) > 1e-6 then avoid.HalfX / math.abs(c) else HUGE
			local tz = avoid.Depth / math.abs(s)
			local t = math.min(tx, tz)
			r = smoothMax(base, t, avoid.Smooth or 0)
		end
	end
	return r + (if finite(offset) then offset :: number else 0)
end

local routeCache: { [string]: { Vector3 } } = {}

-- Geschlossene Route: fein abgetastet, dann auf gleichmäßige Abstände (spacing) umgerechnet.
function City.RoutePoints(name: string, spacing: number?): { Vector3 }
	local def = City.Routes[name]
	if type(def) ~= "table" then
		return {}
	end
	local step = if finite(spacing) and (spacing :: number) >= 4 then spacing :: number else def.Spacing or 24
	local cacheKey = name .. ":" .. tostring(step)
	local cached = routeCache[cacheKey]
	if cached then
		return table.clone(cached)
	end
	local y = City.Levels.Road
	local fine: { Vector3 } = {}
	local samples = 1440
	for i = 0, samples - 1 do
		local deg = i * 360 / samples
		local r = City.RoadRadius(def.Road, deg, def.Offset)
		local a = math.rad(deg)
		table.insert(fine, Vector3.new(r * math.cos(a), y, r * math.sin(a)))
	end
	-- Gesamtlänge + gleichmäßige Abtastung
	local total = 0
	local cumulative: { number } = { 0 }
	for i = 1, samples do
		local p0 = fine[i]
		local p1 = fine[(i % samples) + 1]
		total += (p1 - p0).Magnitude
		cumulative[i + 1] = total
	end
	local count = math.max(8, math.floor(total / step + 0.5))
	local out: { Vector3 } = {}
	local j = 1
	for k = 0, count - 1 do
		local s = k * total / count
		while j < samples and cumulative[j + 1] < s do
			j += 1
		end
		local segLen = cumulative[j + 1] - cumulative[j]
		local f = if segLen > 0 then (s - cumulative[j]) / segLen else 0
		local p0 = fine[j]
		local p1 = fine[(j % samples) + 1]
		table.insert(out, p0:Lerp(p1, f))
	end
	table.insert(out, out[1]) -- geschlossen: letzter Punkt = erster
	routeCache[cacheKey] = out
	return table.clone(out)
end

function City.PlotCFrame(plot: number): CFrame
	local p = City.Plots
	local k = math.clamp(math.floor(if finite(plot) then plot else 1), 1, math.max(1, p.Count))
	local a = math.rad(p.StartAngle + (k - 1) * p.Step)
	local y = City.Levels.Walk
	local pos = Vector3.new(p.Radius * math.cos(a), y, p.Radius * math.sin(a))
	return CFrame.lookAt(pos, Vector3.new(0, y, 0))
end

function City.ShopCFrame(instId: number): CFrame?
	for _, site in ipairs(City.ShopSites) do
		if site.I == instId then
			local a = math.rad(site.Angle)
			local pos = Vector3.new(City.ShopRadius * math.cos(a), City.Levels.Ground, City.ShopRadius * math.sin(a))
			return CFrame.lookAt(pos, Vector3.new(0, City.Levels.Ground, 0))
		end
	end
	return nil
end

-- ---------------------------------------------------------------------
-- PRÜFUNG (Config.Validate sammelt alle Meldungen; leer = alles ok)
-- ---------------------------------------------------------------------
function City.Validate(config: any): { string }
	local errors: { string } = {}
	local function add(text: string)
		table.insert(errors, "Config.City." .. text)
	end
	local function num(path: string, v: any, lo: number, hi: number)
		if not finite(v) or v < lo or v > hi then
			add(("%s: Zahl %s … %s erwartet"):format(path, tostring(lo), tostring(hi)))
		end
	end
	local function int(path: string, v: any, lo: number, hi: number)
		if not finite(v) or v % 1 ~= 0 or v < lo or v > hi then
			add(("%s: ganze Zahl %s … %s erwartet"):format(path, tostring(lo), tostring(hi)))
		end
	end
	local function color(path: string, v: any)
		if typeof(v) ~= "Color3" then
			add(path .. ": Color3 erwartet")
		end
	end

	-- Budget & Aufbau (§B3/§C16)
	int("PartBudget", City.PartBudget, 1000, 12000)
	int("BuildPerFrame", City.BuildPerFrame, 10, 400)
	int("TerrainPerFrame", City.TerrainPerFrame, 1, 16)

	-- Ebenen
	num("Levels.Road", City.Levels.Road, 0, 2)
	num("Levels.Walk", City.Levels.Walk, City.Levels.Road, 3)
	num("Ground.MapSize", City.Ground.MapSize, 1024, 4096)

	-- Look
	for _, phase in ipairs({ "Day", "Night" }) do
		local look = (City.Look :: any)[phase]
		if type(look) ~= "table" or type(look.Atmosphere) ~= "table" then
			add("Look." .. phase .. ": Tabelle mit Atmosphere erwartet")
		else
			num("Look." .. phase .. ".Brightness", look.Brightness, 0, 10)
			num("Look." .. phase .. ".Atmosphere.Density", look.Atmosphere.Density, 0, 1)
			num("Look." .. phase .. ".Atmosphere.Haze", look.Atmosphere.Haze, 0, 10)
			color("Look." .. phase .. ".Atmosphere.Color", look.Atmosphere.Color)
			color("Look." .. phase .. ".Ambient", look.Ambient)
		end
	end
	num("Look.Bloom.Intensity", City.Look.Bloom.Intensity, 0, 2)
	num("Look.Bloom.Size", City.Look.Bloom.Size, 0, 56)
	num("Look.Bloom.Threshold", City.Look.Bloom.Threshold, 0, 4)
	num("Look.SunRays.Intensity", City.Look.SunRays.Intensity, 0, 1)
	num("Look.WindowCascade", City.Look.WindowCascade, 0, 1)
	num("Look.WindowOnAt", City.Look.WindowOnAt, 12, 24)
	num("Look.WindowOffAt", City.Look.WindowOffAt, 0, 12)

	-- Wetter
	num("Weather.ClearBelow", City.Weather.ClearBelow, 0.1, 5)
	num("Weather.StormAbove", City.Weather.StormAbove, City.Weather.ClearBelow, 5)
	for _, key in ipairs({ "Clear", "Clouds", "Storm" }) do
		num("Weather.Cover." .. key, (City.Weather.Cover :: any)[key], 0, 1)
	end
	num("Weather.Lightning.MinGap", City.Weather.Lightning.MinGap, 1, 120)
	num("Weather.Lightning.MaxGap", City.Weather.Lightning.MaxGap, City.Weather.Lightning.MinGap, 240)

	-- Plots
	local plots = City.Plots
	int("Plots.Count", plots.Count, 1, 32)
	num("Plots.Radius", plots.Radius, 100, 1000)
	num("Plots.Size", plots.Size, 40, 200)
	local server = type(config) == "table" and config.Server or nil
	if type(server) == "table" and finite(server.Plots) and server.Plots ~= plots.Count then
		add("Plots.Count: muss Config.Server.Plots entsprechen")
	end

	-- Straßen & Routen
	for _, road in ipairs({ "Ring", "Outer", "Highway" }) do
		local def = (City.Roads :: any)[road]
		if type(def) ~= "table" then
			add("Roads." .. road .. ": Tabelle erwartet")
		else
			num("Roads." .. road .. ".Radius", def.Radius, 100, 1000)
			num("Roads." .. road .. ".Width", def.Width, 8, 80)
		end
	end
	for name, def in pairs(City.Routes) do
		if type(def) ~= "table" or type(City.Roads[def.Road]) ~= "table" then
			add("Routes." .. tostring(name) .. ": Road unbekannt")
		end
	end
	for i, lane in ipairs(City.Lanes) do
		if type(City.Roads[lane.Road]) ~= "table" or (lane.Dir ~= 1 and lane.Dir ~= -1) then
			add(("Lanes[%d]: Road/Dir ungültig"):format(i))
		end
		num(("Lanes[%d].Speed"):format(i), lane.Speed, 1, 200)
	end

	-- Läden
	local shopCount = 0
	for instId, anchorName in pairs(City.Shops) do
		shopCount += 1
		if not finite(instId) or type(anchorName) ~= "string" or anchorName == "" then
			add("Shops: { [instId] = AnchorName } erwartet")
		end
	end
	local sitesSeen: { [number]: boolean } = {}
	for i, site in ipairs(City.ShopSites) do
		if City.Shops[site.I] == nil then
			add(("ShopSites[%d]: Firma %s fehlt in Shops"):format(i, tostring(site.I)))
		end
		assert(not sitesSeen[site.I], "[Config.City] doppelter Laden " .. tostring(site.I))
		sitesSeen[site.I] = true
		num(("ShopSites[%d].Angle"):format(i), site.Angle, 0, 360)
	end
	if #City.ShopSites ~= shopCount then
		add("ShopSites: je Eintrag in Shops genau ein Laden")
	end
	num("ShopNewsSeconds", City.ShopNewsSeconds, 10, 3600)

	-- Hologramme, Kulisse, Leben
	for i, board in ipairs(City.Billboards) do
		int(("Billboards[%d].I"):format(i), board.I, 1, 99)
	end
	int("Zones.Backdrop.Count", City.Zones.Backdrop.Count, 0, 64)
	for _, tier in ipairs({ "Low", "Medium", "High", "Ultra" }) do
		int("Life.Billboards." .. tier, (City.Life.Billboards :: any)[tier], 0, #City.Billboards)
	end
	num("Lights.ManageHz", City.Lights.ManageHz, 0.2, 10)
	int("Lights.MaxManaged", City.Lights.MaxManaged, 10, 2000)

	-- Schilder (eindeutige Schlüssel)
	local signs: { [string]: boolean } = {}
	for i, sign in ipairs(City.Signs) do
		if type(sign.Key) ~= "string" or type(sign.Name) ~= "string" or sign.Name == "" then
			add(("Signs[%d]: Key + Name erwartet"):format(i))
		else
			assert(not signs[sign.Key], "[Config.City] doppeltes Schild " .. sign.Key)
			signs[sign.Key] = true
		end
	end

	-- Routen müssen geschlossen sein
	for name in pairs(City.Routes) do
		local points = City.RoutePoints(name)
		if #points < 9 or (points[1] - points[#points]).Magnitude > 1e-3 then
			add("Routes." .. tostring(name) .. ": Route nicht geschlossen")
		end
	end
	return errors
end

return City
