-- =====================================================================
--  AKYTEX TYCOON – Autos, Klassen, Tuning, Garage (Config.Vehicles)
--  Besitzer: WP7 (Stadt, Grafik, Fahrzeuge). Vertrag: DESIGN.md §C14.2 (Vehicles), §B12.1 (16 Autos, Klassen-Tempo,
--  Boost, Drift, Kollisionsgruppen, Garage, Tuning, Aktionärs-Rabatt), §B14.1 (VIP-Lack „Platin“, Pass Λ-1, Mega-Garage),
--  §0.4 (Robux berühren nie AKY; Fluss Depot -> Turm beim Rabatt ist erlaubt, nie umgekehrt).
--  Alle Zahlen sind Startwerte und 1:1 änderbar. Wird an alle Clients repliziert -> KEINE Geheimnisse hier!
--
--  Abschnitte:
--    1) Klassen (Höchsttempo Studs/s, Beschleunigung)     5) Tuning (24 Lacke, 8 Felgen, 6 Unterboden-Farben, Spoiler)
--    2) Die 16 Autos (§B12.1)                             6) Garage, Spawn, Despawn, Rabatt
--    3) Boost & Drift                                     7) Fahrphysik (Constraints) + Tempo-Prüfung (Server 5 Hz)
--    4) Herkunft (Source) & Freischaltung                 8) Prüfung
--  Helfer:   Vehicles.Car(key): entry?     Vehicles.Cap(key): number     Vehicles.Option(kind, key): entry?
--            Vehicles.TunePrice(carKey, kind, optionKey): number      Vehicles.Validate(Config): { string }
--  Geld: CR ganzzahlig, jeder Preis < 1e14 (Config.Validate prüft "Price" überall).
-- =====================================================================

local Vehicles = {}

local function slot(): { [string]: any }
	return { MeshId = 0, TextureId = 0, Scale = 1, Offset = CFrame.identity }
end

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- ---------------------------------------------------------------------
-- 1) KLASSEN – Höchsttempo je Klasse (Studs/s, §B12.1); Server prüft 5 Hz mit 1,3 × Deckel
-- ---------------------------------------------------------------------
Vehicles.Classes = { Kompakt = 60, Limousine = 75, Sport = 95, Super = 120, Hyper = 150 }
Vehicles.ClassOrder = { "Kompakt", "Limousine", "Sport", "Super", "Hyper" }
Vehicles.ClassInfo = {
	Kompakt = { Accel = 30, Name = { de = "Kompakt", en = "Compact" }, Color = rgb(125, 136, 154) },
	Limousine = { Accel = 34, Name = { de = "Limousine", en = "Sedan" }, Color = rgb(79, 140, 255) },
	Sport = { Accel = 46, Name = { de = "Sport", en = "Sport" }, Color = rgb(34, 197, 94) },
	Super = { Accel = 58, Name = { de = "Super", en = "Super" }, Color = rgb(139, 92, 246) },
	Hyper = { Accel = 72, Name = { de = "Hyper", en = "Hyper" }, Color = rgb(179, 107, 255) },
}
-- Bezugswert für Tuning-Preise von Autos ohne CR-Preis (Gratis, Login, Pass, Lizenz)
Vehicles.ClassValue =
	{ Kompakt = 25000, Limousine = 750000, Sport = 60000000, Super = 6000000000, Hyper = 600000000000 }

-- ---------------------------------------------------------------------
-- 2) DIE 16 AUTOS (§B12.1) – Recipe = Bauplan in Shared/VehicleModels.Recipes, Asset = optionales Mesh der Karosserie
--    Source: Free (gratis) · Shop (CR-Preis) · Starter (Starter-Paket) · Login (Login-Tag) · Licence (Lizenz-Index) ·
--            Season (Skyline-Pass) · Pass (Gamepass)
--    Maker = "Velocitra" -> Aktionärs-Rabatt möglich. Display = steht auf einem Drehteller im Showroom von Λ Motors.
-- ---------------------------------------------------------------------
-- stylua: ignore start
Vehicles.Cars = {
	{ Key = "LamCity", Name = { de = "Λ City", en = "Λ City" }, Class = "Kompakt", Price = 0, Source = "Free",
		Recipe = "LamCity", Paint = "Polar", Asset = slot(), SoundId = 0, Display = false },
	{ Key = "VoltaHatch", Name = { de = "Volta Hatch", en = "Volta Hatch" }, Class = "Kompakt", Price = 25000, Source = "Shop",
		Recipe = "VoltaHatch", Paint = "Cyan", Asset = slot(), SoundId = 0, Display = true },
	{ Key = "PixelMini", Name = { de = "Pixel Mini", en = "Pixel Mini" }, Class = "Kompakt", Price = 120000, Source = "Shop",
		Recipe = "PixelMini", Paint = "Pink", Asset = slot(), SoundId = 0, Display = true },
	{ Key = "LamNeon", Name = { de = "Λ Kompakt Neon", en = "Λ Compact Neon" }, Class = "Kompakt", Price = 0, Source = "Starter",
		Recipe = "LamNeon", Paint = "Midnight", Asset = slot(), SoundId = 0, Display = false },
	{ Key = "Stratos", Name = { de = "Stratos Sedan", en = "Stratos Sedan" }, Class = "Limousine", Price = 750000, Source = "Shop",
		Recipe = "Stratos", Paint = "SilverM", Asset = slot(), SoundId = 0, Display = true },
	{ Key = "Nordlicht", Name = { de = "Nordlicht Executive", en = "Nordlicht Executive" }, Class = "Limousine", Price = 4000000,
		Source = "Shop", Recipe = "Nordlicht", Paint = "BlackM", Asset = slot(), SoundId = 0, Display = true },
	{ Key = "VelocitraS", Name = { de = "Velocitra S", en = "Velocitra S" }, Class = "Sport", Price = 60000000, Source = "Shop",
		Recipe = "VelocitraS", Paint = "Red", Asset = slot(), SoundId = 0, Display = true, Maker = "Velocitra" },
	{ Key = "NeonCoupe", Name = { de = "Neon Coupé", en = "Neon Coupé" }, Class = "Sport", Price = 250000000, Source = "Shop",
		Recipe = "NeonCoupe", Paint = "Accent", Asset = slot(), SoundId = 0, Display = true },
	{ Key = "StreakGT", Name = { de = "Streak-GT", en = "Streak GT" }, Class = "Sport", Price = 0, Source = "Login", LoginDay = 28,
		Recipe = "StreakGT", Paint = "Orange", Asset = slot(), SoundId = 0, Display = false },
	{ Key = "Kometa", Name = { de = "Kometa SL", en = "Kometa SL" }, Class = "Super", Price = 6000000000, Source = "Shop",
		Recipe = "Kometa", Paint = "TitanM", Asset = slot(), SoundId = 0, Display = true },
	{ Key = "AuroraGT", Name = { de = "Aurora GT", en = "Aurora GT" }, Class = "Super", Price = 40000000000, Source = "Shop",
		Recipe = "AuroraGT", Paint = "GreenM", Asset = slot(), SoundId = 0, Display = true },
	{ Key = "QuasarX", Name = { de = "Quasar X", en = "Quasar X" }, Class = "Hyper", Price = 600000000000, Source = "Shop",
		Recipe = "QuasarX", Paint = "CosmosM", Asset = slot(), SoundId = 0, Display = true },
	{ Key = "VelocitraH", Name = { de = "Velocitra Hyper", en = "Velocitra Hyper" }, Class = "Hyper", Price = 4000000000000,
		Source = "Shop", Recipe = "VelocitraH", Paint = "RedM", Asset = slot(), SoundId = 0, Display = true, Maker = "Velocitra" },
	{ Key = "Singularity", Name = { de = "Singularity", en = "Singularity" }, Class = "Hyper", Price = 0, Source = "Licence",
		Licence = 10, Recipe = "Singularity", Paint = "BlackM", Asset = slot(), SoundId = 0, Display = true },
	{ Key = "OrbitR", Name = { de = "Orbit-R", en = "Orbit-R" }, Class = "Hyper", Price = 0, Source = "Season",
		Season = 1, Tier = 50, Recipe = "OrbitR", Paint = "NebulaM", Asset = slot(), SoundId = 0, Display = false },
	{ Key = "Lam1", Name = { de = "ΛKYTEX Λ-1", en = "ΛKYTEX Λ-1" }, Class = "Hyper", Price = 0, Source = "Pass", Pass = "Lam1",
		Recipe = "Lam1", Paint = "Arctic", Asset = slot(), SoundId = 0, Display = true, Trail = true },
}
-- stylua: ignore end

-- ---------------------------------------------------------------------
-- 3) BOOST & DRIFT (§B12.1)
-- ---------------------------------------------------------------------
Vehicles.Boost = { Mult = 1.25, Seconds = 3, Cooldown = 8 } -- +25 % für 3 s, 8 s Abklingzeit
Vehicles.DriftFriction = 0.3 -- Handbremse: Hinterrad-Reibung

-- ---------------------------------------------------------------------
-- 4) HERKUNFT – Anzeige-Texte stehen in Lang ("car.source.<Source>")
-- ---------------------------------------------------------------------
Vehicles.Sources =
	{ Free = true, Shop = true, Starter = true, Login = true, Licence = true, Season = true, Pass = true }

-- ---------------------------------------------------------------------
-- 5) TUNING (CR) – Preis = max(Base, Bezugswert des Autos × Pct) (Bezugswert = CR-Preis oder ClassValue)
--    Unlock: Default (alle) · Pass (Gamepass, z. B. VIP-Lack „Platin“) · Club (Vorstands-Club, Monats-Lack)
-- ---------------------------------------------------------------------
Vehicles.TuneCost = {
	Paint = { Base = 2500, Pct = 0.004 },
	Metallic = { Base = 7500, Pct = 0.008 },
	Rims = { Base = 4000, Pct = 0.006 },
	Glow = { Base = 6000, Pct = 0.005 },
	Spoiler = { Base = 10000, Pct = 0.01 },
}
-- stylua: ignore start
Vehicles.Paints = {
	{ Key = "Polar", Name = { de = "Polarweiß", en = "Polar White" }, Color = rgb(232, 235, 240), Metallic = false, Unlock = "Default" },
	{ Key = "Graphite", Name = { de = "Graphit", en = "Graphite" }, Color = rgb(43, 47, 54), Metallic = false, Unlock = "Default" },
	{ Key = "Midnight", Name = { de = "Mitternacht", en = "Midnight" }, Color = rgb(15, 22, 38), Metallic = false, Unlock = "Default" },
	{ Key = "Accent", Name = { de = "Akzentblau", en = "Accent Blue" }, Color = rgb(79, 140, 255), Metallic = false, Unlock = "Default" },
	{ Key = "Deep", Name = { de = "Tiefblau", en = "Deep Blue" }, Color = rgb(41, 98, 255), Metallic = false, Unlock = "Default" },
	{ Key = "Red", Name = { de = "Signalrot", en = "Signal Red" }, Color = rgb(239, 68, 68), Metallic = false, Unlock = "Default" },
	{ Key = "Green", Name = { de = "Grün", en = "Green" }, Color = rgb(34, 197, 94), Metallic = false, Unlock = "Default" },
	{ Key = "Purple", Name = { de = "Violett", en = "Purple" }, Color = rgb(139, 92, 246), Metallic = false, Unlock = "Default" },
	{ Key = "Orange", Name = { de = "Orange", en = "Orange" }, Color = rgb(245, 158, 11), Metallic = false, Unlock = "Default" },
	{ Key = "Pink", Name = { de = "Pink", en = "Pink" }, Color = rgb(236, 72, 153), Metallic = false, Unlock = "Default" },
	{ Key = "Cyan", Name = { de = "Cyan", en = "Cyan" }, Color = rgb(34, 211, 238), Metallic = false, Unlock = "Default" },
	{ Key = "Sand", Name = { de = "Sand", en = "Sand" }, Color = rgb(201, 169, 110), Metallic = false, Unlock = "Default" },
	{ Key = "SilverM", Name = { de = "Silber Metallic", en = "Silver Metallic" }, Color = rgb(184, 192, 204), Metallic = true, Unlock = "Default" },
	{ Key = "BlueM", Name = { de = "Blau Metallic", en = "Blue Metallic" }, Color = rgb(59, 91, 219), Metallic = true, Unlock = "Default" },
	{ Key = "RedM", Name = { de = "Rot Metallic", en = "Red Metallic" }, Color = rgb(185, 28, 28), Metallic = true, Unlock = "Default" },
	{ Key = "GreenM", Name = { de = "Grün Metallic", en = "Green Metallic" }, Color = rgb(21, 128, 61), Metallic = true, Unlock = "Default" },
	{ Key = "CosmosM", Name = { de = "Kosmos Metallic", en = "Cosmos Metallic" }, Color = rgb(124, 92, 255), Metallic = true, Unlock = "Default" },
	{ Key = "NebulaM", Name = { de = "Nebula Metallic", en = "Nebula Metallic" }, Color = rgb(179, 107, 255), Metallic = true, Unlock = "Default" },
	{ Key = "ChampagneM", Name = { de = "Champagner Metallic", en = "Champagne Metallic" }, Color = rgb(214, 183, 106), Metallic = true, Unlock = "Default" },
	{ Key = "TitanM", Name = { de = "Titan Metallic", en = "Titanium Metallic" }, Color = rgb(107, 114, 128), Metallic = true, Unlock = "Default" },
	{ Key = "BlackM", Name = { de = "Schwarz Metallic", en = "Black Metallic" }, Color = rgb(17, 19, 24), Metallic = true, Unlock = "Default" },
	{ Key = "Arctic", Name = { de = "Arktis Perlmutt", en = "Arctic Pearl" }, Color = rgb(223, 231, 242), Metallic = true, Unlock = "Default" },
	{ Key = "Platin", Name = { de = "Platin", en = "Platinum" }, Color = rgb(229, 228, 226), Metallic = true, Unlock = "Pass", Pass = "VIP" },
	{ Key = "ClubNoir", Name = { de = "Club Noir", en = "Club Noir" }, Color = rgb(27, 21, 48), Metallic = true, Unlock = "Club" },
}
Vehicles.Rims = {
	{ Key = "Stock", Name = { de = "Serie", en = "Stock" }, Color = rgb(170, 178, 190), Style = "Disc", Unlock = "Default" },
	{ Key = "Black", Name = { de = "Schwarz", en = "Black" }, Color = rgb(22, 24, 30), Style = "Spoke", Unlock = "Default" },
	{ Key = "Chrome", Name = { de = "Chrom", en = "Chrome" }, Color = rgb(225, 230, 238), Style = "Spoke", Unlock = "Default" },
	{ Key = "Carbon", Name = { de = "Carbon", en = "Carbon" }, Color = rgb(36, 38, 44), Style = "Turbine", Unlock = "Default" },
	{ Key = "NeonBlue", Name = { de = "Neon Blau", en = "Neon Blue" }, Color = rgb(79, 140, 255), Style = "Neon", Unlock = "Default" },
	{ Key = "NeonGreen", Name = { de = "Neon Grün", en = "Neon Green" }, Color = rgb(34, 197, 94), Style = "Neon", Unlock = "Default" },
	{ Key = "White", Name = { de = "Weiß", en = "White" }, Color = rgb(240, 242, 246), Style = "Disc", Unlock = "Default" },
	{ Key = "Turbine", Name = { de = "Turbine", en = "Turbine" }, Color = rgb(124, 92, 255), Style = "Turbine", Unlock = "Default" },
}
Vehicles.Glow = { -- Neon-Unterbodenlicht (PointLight im Licht-Budget); "Off" = aus (gratis)
	{ Key = "Blue", Name = { de = "Blau", en = "Blue" }, Color = rgb(79, 140, 255), Unlock = "Default" },
	{ Key = "Green", Name = { de = "Grün", en = "Green" }, Color = rgb(34, 197, 94), Unlock = "Default" },
	{ Key = "Red", Name = { de = "Rot", en = "Red" }, Color = rgb(239, 68, 68), Unlock = "Default" },
	{ Key = "Violet", Name = { de = "Violett", en = "Violet" }, Color = rgb(139, 92, 246), Unlock = "Default" },
	{ Key = "Cyan", Name = { de = "Cyan", en = "Cyan" }, Color = rgb(34, 211, 238), Unlock = "Default" },
	{ Key = "Cosmic", Name = { de = "Kosmos", en = "Cosmic" }, Color = rgb(179, 107, 255), Unlock = "Default" },
}
-- stylua: ignore end
Vehicles.GlowOff = "Off"
Vehicles.DefaultRims = "Stock"

-- ---------------------------------------------------------------------
-- 6) GARAGE, SPAWN, DESPAWN, RABATT
-- ---------------------------------------------------------------------
Vehicles.GarageBase = 6 -- Plätze
Vehicles.GarageLevelSlots = 4 -- je Garagen-Ebene im Tower (Abteilung "Garage")
Vehicles.GarageLevelsMax = 2
Vehicles.MegaGarageSlots = 12 -- Pass "MegaGarage"
Vehicles.DespawnSeconds = 60 -- Auto verschwindet 60 s nach dem Aussteigen
Vehicles.SpawnCooldown = 3 -- = Request-Rate CarSpawn 1/3 s
Vehicles.ShareholderDiscount = { I = 15, Min = 50, Pct = 0.10 } -- ≥ 50 Anteile VLCT -> −10 % auf Velocitra-Autos
-- Spawnpunkte (Fußpunkte, Blick = Fahrtrichtung). "Garage" = vor dem eigenen Plot (CityService.PlotSite).
Vehicles.SpawnPoints = {
	{ Key = "Plaza", Position = Vector3.new(-26, 0.25, 214), Facing = Vector3.new(0, 0, 1) },
	{ Key = "Motors", Position = Vector3.new(-655, 0.25, 0), Facing = Vector3.new(1, 0, 0) },
	{ Key = "Helipad", Position = Vector3.new(705, 0.25, 26), Facing = Vector3.new(-1, 0, 0) },
}
Vehicles.GarageSpawnOffset = 68 -- Studs vor der Plot-Mitte (auf der Einfahrt)

-- ---------------------------------------------------------------------
-- 7) FAHRPHYSIK (VehicleSeat + HingeConstraint-Motoren, Servo-Lenkung, SpringConstraint-Federung) & TEMPO-PRÜFUNG
--    Feinschliff in Studio: diese Werte ändern, nicht den Code.
-- ---------------------------------------------------------------------
Vehicles.Physics = {
	ChassisDensity = 2.2,
	WheelDensity = 0.9,
	PartDensity = 0.05, -- Federbeine/Achsschenkel
	FrontFriction = 1.7,
	RearFriction = 1.5,
	FrictionWeight = 4,
	SpringTravel = 0.9, -- Federweg ± (Studs)
	SpringCompression = 0.45, -- Einfederung im Stand
	SpringDampingRatio = 0.55,
	SteerMax = 34, -- Grad bei Schritttempo
	SteerMin = 9, -- Grad bei Höchsttempo
	SteerSpeed = 7, -- rad/s Servo
	TorqueFactor = 1.4, -- Motormoment relativ zu Gewicht × Radius
	BrakeFactor = 2.2,
	CoastTorque = 0.08,
	Downforce = 0.6, -- Zusatz-Anpressdruck bei Höchsttempo (Anteil Gewicht)
	FlipSeconds = 2, -- so lange auf dem Dach -> automatisch aufrichten
	ReverseFactor = 0.35, -- Rückwärts höchstens 35 % des Deckels
}
Vehicles.SpeedCheck = {
	Hz = 5, -- Server prüft 5×/s (§B12.1)
	Factor = 1.3, -- > 1,3 × Klassen-Deckel -> Tempo zurücksetzen + Verdachtspunkte
	Strikes = 2, -- so viele Messungen hintereinander über der Grenze
	OwnerBack = 0.6, -- Sekunden Server-Besitz nach dem Zurücksetzen
	FallY = -60, -- tiefer = Auto weg (aus der Welt gefallen)
}

-- =====================================================================
-- HELFER
-- =====================================================================
local HUGE = math.huge
local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= HUGE and n ~= -HUGE
end

local carIndex: { [string]: any } = {}
for _, car in ipairs(Vehicles.Cars) do
	assert(carIndex[car.Key] == nil, "[Config.Vehicles] doppelter Auto-Schlüssel " .. tostring(car.Key))
	carIndex[car.Key] = car
end

local optionIndex: { [string]: { [string]: any } } = { Paint = {}, Rims = {}, Glow = {} }
for kind, list in pairs({ Paint = Vehicles.Paints, Rims = Vehicles.Rims, Glow = Vehicles.Glow }) do
	for _, entry in ipairs(list) do
		assert(
			optionIndex[kind][entry.Key] == nil,
			"[Config.Vehicles] doppelter Tuning-Schlüssel " .. kind .. "." .. entry.Key
		)
		optionIndex[kind][entry.Key] = entry
	end
end

function Vehicles.Car(key: string): any?
	return if type(key) == "string" then carIndex[key] else nil
end

-- Klassen-Deckel (Studs/s) eines Autos
function Vehicles.Cap(key: string): number
	local car = Vehicles.Car(key)
	local cap = if car then Vehicles.Classes[car.Class] else nil
	return if finite(cap) then cap else 60
end

function Vehicles.Option(kind: string, key: string): any?
	local index = optionIndex[kind]
	return if index and type(key) == "string" then index[key] else nil
end

-- Bezugswert eines Autos (CR-Preis oder Klassen-Wert)
local function refValue(car: any): number
	if finite(car.Price) and car.Price > 0 then
		return car.Price
	end
	local value = Vehicles.ClassValue[car.Class]
	return if finite(value) then value else 25000
end

-- Preis einer Tuning-Option für ein Auto (ganzzahlig, < 1e14); Spoiler: optionKey egal; "Off"/Serie = 0
function Vehicles.TunePrice(carKey: string, kind: string, optionKey: string?): number
	local car = Vehicles.Car(carKey)
	if not car then
		return 0
	end
	local costKey = kind
	if kind == "Paint" then
		local paint = Vehicles.Option("Paint", optionKey or "")
		if not paint then
			return 0
		end
		costKey = if paint.Metallic then "Metallic" else "Paint"
	elseif kind == "Glow" then
		if optionKey == Vehicles.GlowOff then
			return 0
		end
	elseif kind == "Rims" then
		if optionKey == Vehicles.DefaultRims then
			return 0
		end
	end
	local cost = Vehicles.TuneCost[costKey]
	if type(cost) ~= "table" then
		return 0
	end
	local price = math.max(cost.Base, math.floor(refValue(car) * cost.Pct))
	return math.clamp(math.floor(price), 0, 9e13)
end

-- ---------------------------------------------------------------------
-- 8) PRÜFUNG
-- ---------------------------------------------------------------------
function Vehicles.Validate(_config: any): { string }
	local errors: { string } = {}
	local function add(text: string)
		table.insert(errors, "Config.Vehicles." .. text)
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
	local function pair(path: string, v: any)
		if type(v) ~= "table" or type(v.de) ~= "string" or type(v.en) ~= "string" or v.de == "" or v.en == "" then
			add(path .. ": { de, en } erwartet")
		end
	end

	-- Klassen (§B12.1: 60 / 75 / 95 / 120 / 150)
	local expected = { Kompakt = 60, Limousine = 75, Sport = 95, Super = 120, Hyper = 150 }
	for _, class in ipairs(Vehicles.ClassOrder) do
		num("Classes." .. class, Vehicles.Classes[class], 10, 400)
		if expected[class] and Vehicles.Classes[class] ~= expected[class] then
			add(("Classes.%s: Spec-Wert %d"):format(class, expected[class]))
		end
		local info = Vehicles.ClassInfo[class]
		if type(info) ~= "table" then
			add("ClassInfo." .. class .. ": fehlt")
		else
			num("ClassInfo." .. class .. ".Accel", info.Accel, 1, 400)
			pair("ClassInfo." .. class .. ".Name", info.Name)
		end
		int("ClassValue." .. class, Vehicles.ClassValue[class], 0, 9e13)
	end

	-- Autos
	if #Vehicles.Cars ~= 16 then
		add(("Cars: 16 Autos erwartet (§B12.1), gefunden %d"):format(#Vehicles.Cars))
	end
	local hyperBest = 0
	for i, car in ipairs(Vehicles.Cars) do
		local where = ("Cars[%d] (%s)"):format(i, tostring(car.Key))
		if type(car.Key) ~= "string" or not string.match(car.Key, "^%a[%w]*$") then
			add(where .. ".Key: Buchstaben/Ziffern erwartet")
		end
		pair(where .. ".Name", car.Name)
		if Vehicles.Classes[car.Class] == nil then
			add(where .. ".Class: unbekannt")
		end
		if not Vehicles.Sources[car.Source] then
			add(where .. ".Source: unbekannt")
		end
		int(where .. ".Price", car.Price, 0, 9e13)
		if car.Source == "Shop" and (not finite(car.Price) or car.Price <= 0) then
			add(where .. ".Price: Shop-Autos brauchen einen CR-Preis")
		end
		if car.Source ~= "Shop" and finite(car.Price) and car.Price > 0 then
			add(where .. ".Price: nur Shop-Autos haben einen CR-Preis")
		end
		if car.Source == "Pass" and (type(car.Pass) ~= "string" or car.Pass == "") then
			add(where .. ".Pass: Pass-Schlüssel erwartet")
		end
		if car.Source == "Licence" then
			int(where .. ".Licence", car.Licence, 1, 10)
		end
		if car.Source == "Login" then
			int(where .. ".LoginDay", car.LoginDay, 1, 365)
		end
		if type(car.Recipe) ~= "string" or car.Recipe == "" then
			add(where .. ".Recipe: Bauplan-Schlüssel erwartet")
		end
		if Vehicles.Option("Paint", car.Paint) == nil then
			add(where .. ".Paint: Lack aus Paints erwartet")
		end
		if car.Class == "Hyper" and car.Source ~= "Pass" then
			hyperBest = math.max(hyperBest, Vehicles.Classes.Hyper)
		end
	end
	-- Λ-1 (Pass): nie schneller als das beste erspielte Hyper (§B12.1)
	local lam1 = Vehicles.Car("Lam1")
	if lam1 and Vehicles.Cap("Lam1") > hyperBest then
		add("Cars.Lam1: darf nie schneller sein als das beste erspielte Hyper")
	end
	local freeCar = Vehicles.Car("LamCity")
	if freeCar == nil or freeCar.Source ~= "Free" then
		add("Cars.LamCity: Gratis-Auto des Tutorials fehlt")
	end

	-- Boost/Drift
	num("Boost.Mult", Vehicles.Boost.Mult, 1, 2)
	num("Boost.Seconds", Vehicles.Boost.Seconds, 0.5, 30)
	num("Boost.Cooldown", Vehicles.Boost.Cooldown, Vehicles.Boost.Seconds, 120)
	num("DriftFriction", Vehicles.DriftFriction, 0.05, 2)
	if Vehicles.Boost.Mult >= Vehicles.SpeedCheck.Factor then
		add("Boost.Mult: muss unter SpeedCheck.Factor liegen (sonst Fehlalarm beim Boost)")
	end

	-- Tuning (§B12.1: 24 Lacke, 8 Felgen, 6 Unterboden-Farben)
	local counts = { Paints = 24, Rims = 8, Glow = 6 }
	for name, n in pairs(counts) do
		local list = (Vehicles :: any)[name]
		if type(list) ~= "table" or #list ~= n then
			add(("%s: %d Einträge erwartet"):format(name, n))
		else
			for i, entry in ipairs(list) do
				local where = ("%s[%d]"):format(name, i)
				pair(where .. ".Name", entry.Name)
				if typeof(entry.Color) ~= "Color3" then
					add(where .. ".Color: Color3 erwartet")
				end
				if entry.Unlock ~= "Default" and entry.Unlock ~= "Pass" and entry.Unlock ~= "Club" then
					add(where .. ".Unlock: Default/Pass/Club erwartet")
				elseif entry.Unlock == "Pass" and (type(entry.Pass) ~= "string" or entry.Pass == "") then
					add(where .. ".Pass: Pass-Schlüssel erwartet")
				end
			end
		end
	end
	for kind, cost in pairs(Vehicles.TuneCost) do
		int("TuneCost." .. kind .. ".Base", cost.Base, 0, 9e13)
		num("TuneCost." .. kind .. ".Pct", cost.Pct, 0, 0.5)
	end
	if Vehicles.Option("Rims", Vehicles.DefaultRims) == nil then
		add("DefaultRims: Felge aus Rims erwartet")
	end

	-- Garage & Rabatt
	int("GarageBase", Vehicles.GarageBase, 1, 100)
	int("GarageLevelSlots", Vehicles.GarageLevelSlots, 0, 50)
	int("GarageLevelsMax", Vehicles.GarageLevelsMax, 0, 10)
	int("MegaGarageSlots", Vehicles.MegaGarageSlots, 0, 100)
	num("DespawnSeconds", Vehicles.DespawnSeconds, 5, 3600)
	local discount = Vehicles.ShareholderDiscount
	int("ShareholderDiscount.I", discount.I, 1, 99)
	int("ShareholderDiscount.Min", discount.Min, 1, 1e9)
	num("ShareholderDiscount.Pct", discount.Pct, 0, 0.5)
	for i, point in ipairs(Vehicles.SpawnPoints) do
		if typeof(point.Position) ~= "Vector3" or typeof(point.Facing) ~= "Vector3" then
			add(("SpawnPoints[%d]: Position/Facing (Vector3) erwartet"):format(i))
		end
	end

	-- Physik & Prüfung
	local physics = Vehicles.Physics
	num("Physics.ChassisDensity", physics.ChassisDensity, 0.01, 100)
	num("Physics.WheelDensity", physics.WheelDensity, 0.01, 100)
	num("Physics.FrontFriction", physics.FrontFriction, 0, 2)
	num("Physics.RearFriction", physics.RearFriction, 0, 2)
	num("Physics.SteerMax", physics.SteerMax, 5, 60)
	num("Physics.SteerMin", physics.SteerMin, 1, physics.SteerMax)
	num("SpeedCheck.Hz", Vehicles.SpeedCheck.Hz, 1, 30)
	num("SpeedCheck.Factor", Vehicles.SpeedCheck.Factor, 1.05, 3)
	int("SpeedCheck.Strikes", Vehicles.SpeedCheck.Strikes, 1, 10)
	return errors
end

return Vehicles
