-- =====================================================================
--  AKYTEX TYCOON – Lifestyle: Uhren, Accessoires, Jetpack (Config.Lifestyle)
--  Besitzer: WP8 (Turm-Optik, Interiors, Lifestyle). Vertrag: DESIGN.md §C14.2 (Lifestyle), §B12.2 (Uhren), §B12.3
--  (Accessoires), §B12.4 (Neon-Jetpack, nur Werte), §B9.6 (Vorstand „Lifestyle“), §C14.3 (Asset-/Bild-Plätze).
--  Jugendfrei: kein Alkohol, keine Zigarren, keine Partys. Alles aus Parts (keine hochgeladene Kleidung).
--  Wird an alle Clients repliziert -> KEINE Geheimnisse hier! Lädt keine Roblox-Dienste (Luau-CLI-ladbar).
--
--  Abschnitte:
--    1) Regeln (max. 3 Accessoires, Vorstand-Rabatt, Zeiger-Reichweite)
--    2) Boutique-Rotation (Ersatzwerte, falls Config.Shop / ShopService.Rotation fehlen)
--    3) Uhren (15)        4) Accessoires (8)        5) Neon-Jetpack (Pass, §B12.4)
--  Quelle (Source): "Shop" (CR, Price > 0) · "Starter" (Starter-Paket) · "Login" (Login-Kalender) · "Season"
--    (Skyline-Pass) · "Perk" (Vorstand-Ast Perk.Branch ab Perk.Level) · "Pass" (Gamepass Pass) · "Licence"
--    (ab Lizenz-Index Licence) · "Group" (Gruppe „AKYTEX Games“, Data.Social.Group). Nicht-Shop-Teile: Price = 0,
--    Value = Sammlungswert für das Vermögen (LifestyleService.CollectionValue).
--  Recipe = Bau-Rezept für Shared/LifestyleModels. Asset = Mesh-Platz, ImageId = Boutique-Bild (0 = Code-Grafik).
--  Helfer: Lifestyle.ByKey[key] (Uhr ODER Accessoire), Lifestyle.Validate(Config): { string }
-- =====================================================================

local Lifestyle = {}

local IDENTITY: any = nil
pcall(function()
	IDENTITY = (CFrame :: any).identity
end)

local function slot(): { [string]: any }
	return { MeshId = 0, TextureId = 0, Scale = 1, Offset = IDENTITY }
end

-- ---------------------------------------------------------------------
-- 1) REGELN
-- ---------------------------------------------------------------------
Lifestyle.MaxAccessories = 3 -- höchstens 3 Accessoires gleichzeitig (§B12.3)
Lifestyle.Perk = { Branch = "Lifestyle", Pct = 0.05, Max = 5 } -- −5 % Uhren-/Deko-Preise je Stufe (§B9.6)
Lifestyle.WatchRange = 60 -- Zeiger drehen nur ≤ 60 Studs von der Kamera (§B12.2)
Lifestyle.SlotNames = { "Watch", "Acc" } -- LifeEquip { Slot = "Watch" | "Acc", Key? }

-- ---------------------------------------------------------------------
-- 2) BOUTIQUE-ROTATION (Ersatz; maßgeblich ist ShopService.Rotation / Config.Shop.BoutiqueHours/-Slots)
-- ---------------------------------------------------------------------
Lifestyle.Boutique = { Hours = 4, Slots = 6 }

-- ---------------------------------------------------------------------
-- 3) UHREN (15) – am Handgelenk für alle sichtbar, 6–10 Parts (§B12.2)
-- ---------------------------------------------------------------------
local function watch(
	key: string,
	de: string,
	en: string,
	price: number,
	source: string,
	recipe: { [string]: any },
	extra: { [string]: any }?
): { [string]: any }
	local entry: { [string]: any } = {
		Key = key,
		Name = { de = de, en = en },
		Price = price,
		Source = source,
		Value = price,
		Recipe = recipe,
		Asset = slot(),
		ImageId = 0,
	}
	if extra then
		for k, v in pairs(extra) do
			entry[k] = v
		end
	end
	return entry
end

-- Recipe: Case (Gehäuse), Dial (Zifferblatt), Strap (Armband), Hands (Zeiger), Glow (Neon-Akzent),
--         M (Gehäuse-Material), Shape ("Round" | "Square"), Bezel (Lünette ja/nein)
-- stylua: ignore start
Lifestyle.Watches = {
	watch("FirstBell",      "Erste Glocke",        "First Bell",           0,             "Starter", { Case = "#c0c7d4", Dial = "#0b0f17", Strap = "#1f2937", Hands = "#facc15", Glow = "#4f8cff", M = "Metal", Shape = "Round", Bezel = false }, { Value = 25000 }),
	watch("Copper",         "Kupfer Classic",      "Copper Classic",       50000,         "Shop",    { Case = "#b8733d", Dial = "#f4e3c1", Strap = "#5b3a24", Hands = "#1a1410", Glow = "#b8733d", M = "Metal", Shape = "Round", Bezel = false }),
	watch("NeonPulse",      "Neon Pulse",          "Neon Pulse",           2000000,       "Shop",    { Case = "#121824", Dial = "#0b0f17", Strap = "#121824", Hands = "#22d3ee", Glow = "#22d3ee", M = "SmoothPlastic", Shape = "Square", Bezel = false }),
	watch("ChronoL",        "Chrono Λ",            "Chrono Λ",             80000000,      "Shop",    { Case = "#d7dee8", Dial = "#1a2130", Strap = "#d7dee8", Hands = "#4f8cff", Glow = "#4f8cff", M = "Metal", Shape = "Round", Bezel = true }),
	watch("OrbitGold",      "Orbit Gold",          "Orbit Gold",           3000000000,    "Shop",    { Case = "#facc15", Dial = "#0b0f17", Strap = "#1a1410", Hands = "#ffcf6e", Glow = "#facc15", M = "Metal", Shape = "Round", Bezel = true }),
	watch("DiamondTicker",  "Diamant-Ticker",      "Diamond Ticker",       2000000000000, "Shop",    { Case = "#e0f2fe", Dial = "#0b0f17", Strap = "#c0c7d4", Hands = "#a5f3fc", Glow = "#a5f3fc", M = "Glass", Shape = "Square", Bezel = true }),
	watch("WeekChrono",     "Wochen-Chrono",       "Week Chrono",          0,             "Login",   { Case = "#7d889a", Dial = "#121824", Strap = "#2a3342", Hands = "#22c55e", Glow = "#22c55e", M = "Metal", Shape = "Round", Bezel = true }, { Value = 500000 }),
	watch("SkylineChrono",  "Skyline-Chrono",      "Skyline Chrono",       0,             "Season",  { Case = "#1a1440", Dial = "#0b0f17", Strap = "#7c5cff", Hands = "#b36bff", Glow = "#7c5cff", M = "Metal", Shape = "Square", Bezel = true }, { Value = 50000000 }),
	watch("BellTourbillon", "Glocken-Tourbillon",  "Bell Tourbillon",      0,             "Perk",    { Case = "#facc15", Dial = "#f4f6fa", Strap = "#3a2418", Hands = "#1a1410", Glow = "#ffcf6e", M = "Metal", Shape = "Round", Bezel = true }, { Perk = { Branch = "Lifestyle", Level = 5 }, Value = 1000000000 }),
	watch("ChronoNight",    "Chrono Nacht",        "Chrono Night",         0,             "Pass",    { Case = "#0b0f17", Dial = "#03040a", Strap = "#0b0f17", Hands = "#7c9cff", Glow = "#3b5bdb", M = "Metal", Shape = "Round", Bezel = true }, { Pass = "Chrono", Value = 5000000 }),
	watch("ChronoAurora",   "Chrono Aurora",       "Chrono Aurora",        0,             "Pass",    { Case = "#1a2130", Dial = "#0b0f17", Strap = "#1a2130", Hands = "#22c55e", Glow = "#22d3ee", M = "Metal", Shape = "Round", Bezel = true }, { Pass = "Chrono", Value = 5000000 }),
	watch("ChronoArctic",   "Chrono Arktis",       "Chrono Arctic",        0,             "Pass",    { Case = "#e6ecf5", Dial = "#dbeafe", Strap = "#f4f6fa", Hands = "#2563eb", Glow = "#93c5fd", M = "Metal", Shape = "Square", Bezel = false }, { Pass = "Chrono", Value = 5000000 }),
	watch("ChronoSolar",    "Chrono Solar",        "Chrono Solar",         0,             "Pass",    { Case = "#f59e0b", Dial = "#1a1410", Strap = "#3a2418", Hands = "#facc15", Glow = "#f59e0b", M = "Metal", Shape = "Round", Bezel = true }, { Pass = "Chrono", Value = 5000000 }),
	watch("ChronoMidnight", "Chrono Mitternacht",  "Chrono Midnight",      0,             "Pass",    { Case = "#1e1b4b", Dial = "#03040a", Strap = "#1e1b4b", Hands = "#b36bff", Glow = "#7c5cff", M = "Metal", Shape = "Square", Bezel = true }, { Pass = "Chrono", Value = 5000000 }),
	watch("Legend",         "Legenden-Uhr",        "Legend Watch",         0,             "Licence", { Case = "#facc15", Dial = "#03040a", Strap = "#facc15", Hands = "#f4f6fa", Glow = "#7c5cff", M = "Metal", Shape = "Round", Bezel = true }, { Licence = 10, Value = 10000000000 }),
}

-- ---------------------------------------------------------------------
-- 4) ACCESSOIRES (8) – aus Parts, max. 3 gleichzeitig (§B12.3). Attach: Head | Torso | RightHand | Root
-- ---------------------------------------------------------------------
local function acc(
	key: string,
	de: string,
	en: string,
	price: number,
	source: string,
	attach: string,
	recipe: { [string]: any },
	extra: { [string]: any }?
): { [string]: any }
	local entry: { [string]: any } = {
		Key = key,
		Name = { de = de, en = en },
		Price = price,
		Source = source,
		Value = price,
		Attach = attach,
		Recipe = recipe,
		Asset = slot(),
		ImageId = 0,
	}
	if extra then
		for k, v in pairs(extra) do
			entry[k] = v
		end
	end
	return entry
end

Lifestyle.Accessories = {
	acc("Sunglasses",     "Sonnenbrille",     "Sunglasses",       10000,       "Shop",    "Head",      { Kind = "Sunglasses", A = "#0b0f17", B = "#1f2937", C = "#4f8cff" }),
	acc("TiePin",         "Krawattennadel",   "Tie Pin",          100000,      "Shop",    "Torso",     { Kind = "TiePin", A = "#facc15", B = "#c0c7d4", C = "#4f8cff" }),
	acc("Briefcase",      "Aktentasche",      "Briefcase",        1000000,     "Shop",    "RightHand", { Kind = "Briefcase", A = "#3a2418", B = "#c8a165", C = "#1a1410" }),
	acc("LapelNeon",      "Revers-Neon",      "Lapel Neon",       20000000,    "Shop",    "Torso",     { Kind = "Lapel", A = "#22d3ee", B = "#121824", C = "#22d3ee" }),
	acc("AuraBlue",       "Aura-Ring Blau",   "Aura Ring Blue",   500000000,   "Shop",    "Root",      { Kind = "Aura", A = "#4f8cff", B = "#7c9cff", C = "#4f8cff" }),
	acc("AuraGold",       "Aura-Ring Gold",   "Aura Ring Gold",   10000000000, "Shop",    "Root",      { Kind = "Aura", A = "#facc15", B = "#ffcf6e", C = "#facc15" }),
	acc("HoloBadge",      "Holo-Abzeichen",   "Holo Badge",       0,           "Licence", "Torso",     { Kind = "Badge", A = "#7c5cff", B = "#121824", C = "#b36bff" }, { Licence = 7, Value = 400000000 }),
	acc("CommunityCrown", "Community-Krone",  "Community Crown",  0,           "Group",   "Head",      { Kind = "Crown", A = "#4f8cff", B = "#facc15", C = "#7c9cff" }, { Value = 100000 }),
}
-- stylua: ignore end

-- ---------------------------------------------------------------------
-- 5) NEON-JETPACK (Gamepass „Jetpack“, §B12.4) – Werte für Flug-Code und Anti-Cheat-Erlaubnis
-- ---------------------------------------------------------------------
Lifestyle.Jetpack = {
	Pass = "Jetpack",
	Fuel = 8, -- Sekunden Schub
	Recharge = 12, -- Sekunden bis voll
	MaxHeight = 120, -- Studs über Boden
	VerticalMult = 3, -- Anti-Cheat-Erlaubnis nur während aktiv (SetAllowance)
	SpeedMult = 1.6,
	Asset = slot(),
}

-- Nachschlagen: Schlüssel -> Eintrag (Uhren und Accessoires teilen sich den Namensraum)
Lifestyle.ByKey = {} :: { [string]: { [string]: any } }
Lifestyle.KindOf = {} :: { [string]: string } -- Schlüssel -> "Watch" | "Accessory"
for _, entry in ipairs(Lifestyle.Watches) do
	assert(Lifestyle.ByKey[entry.Key] == nil, "[Config.Lifestyle] doppelter Schlüssel " .. entry.Key)
	Lifestyle.ByKey[entry.Key] = entry
	Lifestyle.KindOf[entry.Key] = "Watch"
end
for _, entry in ipairs(Lifestyle.Accessories) do
	assert(Lifestyle.ByKey[entry.Key] == nil, "[Config.Lifestyle] doppelter Schlüssel " .. entry.Key)
	Lifestyle.ByKey[entry.Key] = entry
	Lifestyle.KindOf[entry.Key] = "Accessory"
end

-- =====================================================================
-- PRÜFUNG
-- =====================================================================
local SOURCES: { [string]: boolean } = {
	Shop = true,
	Starter = true,
	Login = true,
	Season = true,
	Perk = true,
	Pass = true,
	Licence = true,
	Group = true,
}
local ATTACH: { [string]: boolean } = { Head = true, Torso = true, RightHand = true, Root = true }

local function isNum(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isPair(v: any): boolean
	return type(v) == "table" and type(v.de) == "string" and v.de ~= "" and type(v.en) == "string" and v.en ~= ""
end

local function isHex(v: any): boolean
	return type(v) == "string" and string.match(v, "^#%x%x%x%x%x%x$") ~= nil
end

function Lifestyle.Validate(_config: any): { string }
	local errors: { string } = {}
	local function add(text: string)
		table.insert(errors, "Config.Lifestyle." .. text)
	end
	local function int(path: string, v: any, lo: number, hi: number)
		if not isNum(v) or v % 1 ~= 0 or v < lo or v > hi then
			add(("%s: ganze Zahl %s … %s erwartet"):format(path, tostring(lo), tostring(hi)))
		end
	end
	int("MaxAccessories", Lifestyle.MaxAccessories, 1, 6)
	int("WatchRange", Lifestyle.WatchRange, 10, 500)
	int("Perk.Max", Lifestyle.Perk.Max, 0, 10)
	if not isNum(Lifestyle.Perk.Pct) or Lifestyle.Perk.Pct < 0 or Lifestyle.Perk.Pct * Lifestyle.Perk.Max >= 1 then
		add("Perk.Pct: Rabatt muss unter 100 % bleiben")
	end
	int("Boutique.Hours", Lifestyle.Boutique.Hours, 1, 48)
	int("Boutique.Slots", Lifestyle.Boutique.Slots, 1, 24)
	local function common(list: { any }, label: string, count: number, check: (entry: any, where: string) -> ())
		if #list ~= count then
			add(("%s: genau %d Einträge erwartet, gefunden %d"):format(label, count, #list))
		end
		for i, entry in ipairs(list) do
			local where = ("%s[%d] (%s)"):format(label, i, tostring(entry.Key))
			if type(entry.Key) ~= "string" or not string.match(entry.Key, "^[%w_]+$") or #entry.Key > 40 then
				add(where .. ".Key: Buchstaben/Ziffern (≤ 40) erwartet")
			end
			if not isPair(entry.Name) then
				add(where .. ".Name: { de, en } erwartet")
			end
			if not SOURCES[entry.Source] then
				add(where .. ".Source: unbekannte Quelle")
			elseif entry.Source == "Shop" then
				int(where .. ".Price", entry.Price, 1, 1e14 - 1)
			elseif entry.Price ~= 0 then
				add(where .. ".Price: 0 erwartet (nicht kaufbar)")
			end
			if entry.Source == "Pass" and (type(entry.Pass) ~= "string" or entry.Pass == "") then
				add(where .. ".Pass: Pass-Schlüssel erwartet")
			end
			if entry.Source == "Licence" then
				int(where .. ".Licence", entry.Licence, 1, 10)
			end
			if entry.Source == "Perk" then
				local perk = entry.Perk
				if type(perk) ~= "table" or type(perk.Branch) ~= "string" then
					add(where .. ".Perk: { Branch, Level } erwartet")
				else
					int(where .. ".Perk.Level", perk.Level, 1, 10)
				end
			end
			int(where .. ".Value", entry.Value, 0, 1e14 - 1)
			if type(entry.Recipe) ~= "table" then
				add(where .. ".Recipe: Tabelle erwartet")
			end
			check(entry, where)
		end
	end
	common(Lifestyle.Watches, "Watches", 15, function(entry: any, where: string)
		local r = entry.Recipe
		if type(r) == "table" then
			for _, field in ipairs({ "Case", "Dial", "Strap", "Hands", "Glow" }) do
				if not isHex(r[field]) then
					add(where .. ".Recipe." .. field .. ": #rrggbb erwartet")
				end
			end
			if r.Shape ~= "Round" and r.Shape ~= "Square" then
				add(where .. ".Recipe.Shape: Round/Square erwartet")
			end
		end
	end)
	common(Lifestyle.Accessories, "Accessories", 8, function(entry: any, where: string)
		if not ATTACH[entry.Attach] then
			add(where .. ".Attach: Head/Torso/RightHand/Root erwartet")
		end
		local r = entry.Recipe
		if type(r) == "table" then
			if type(r.Kind) ~= "string" then
				add(where .. ".Recipe.Kind: Text erwartet")
			end
			for _, field in ipairs({ "A", "B", "C" }) do
				if not isHex(r[field]) then
					add(where .. ".Recipe." .. field .. ": #rrggbb erwartet")
				end
			end
		end
	end)
	local jet = Lifestyle.Jetpack
	int("Jetpack.Fuel", jet.Fuel, 1, 60)
	int("Jetpack.Recharge", jet.Recharge, 1, 120)
	int("Jetpack.MaxHeight", jet.MaxHeight, 10, 400)
	if not isNum(jet.VerticalMult) or jet.VerticalMult < 1 or jet.VerticalMult > 10 then
		add("Jetpack.VerticalMult: Zahl 1 … 10 erwartet")
	end
	if not isNum(jet.SpeedMult) or jet.SpeedMult < 1 or jet.SpeedMult > 5 then
		add("Jetpack.SpeedMult: Zahl 1 … 5 erwartet")
	end
	return errors
end

return Lifestyle
