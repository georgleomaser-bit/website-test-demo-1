-- =====================================================================
--  AKYTEX TYCOON – Handelbare Instrumente: 36 Firmen, 7 ETFs, IPO-Pipeline, Übungsaktie (Config.Companies)
--  Besitzer: WP3 (Markt-Engine). Vertrag: DESIGN.md §B6.2 (Tabelle, Lizenz-Sätze, Körbe), §C14.2, §C19 Nr. 1;
--  MARKET.md §4.2. ALLE Firmen sind frei erfunden (keine echten Firmen, Kürzel, Indizes, Personen).
--
--  So änderst du etwas:
--    * Startkurs:   Start in CENT (24000 = 240,00 AKY). Gilt nur, solange es noch keinen Wochenschluss gibt.
--    * Dividende:   DivBps in Basispunkten je Ausschüttung (40 = 0,4 %), 0 = zahlt nicht. Ausschüttung am Quartalstag :19.
--    * Lizenz-Satz: Set = "Azubi" | "Trader" | "Fonds" (ab welcher Lizenz handelbar) – "Tutorial" nur für ACAD (250).
--    * IDs NIE wiederverwenden (1–36 Firmen, 40–46 ETFs, 100–139 IPO-Plätze, 250 ACAD).
--    * Neue IPO-Firma: Eintrag mit Ipo = true, Id 100–139, Season/Slot und in Config.Market.IpoPipeline.Season eintragen.
--  Logo = UI-Form (Letter + Shape in Sektorfarbe), ImageId = 0 -> Code-Grafik (optional eigenes Bild, §C14.3).
--
--  Inhalt:  Companies.Sectors { {Key, Name {de,en}, Color} }   Companies.Instruments { Types.Instrument (+ ImageId,
--           Members bei ETFs, Season/Slot bei IPOs) }   Companies.Baskets { {Key, Name {de,en}, Members {Id}} }
--           Companies.ById[id]  Companies.SectorIndex[key] = 1…6   Companies.Validate(Config): { string }
-- =====================================================================

local Companies = {}

-- ---------------------------------------------------------------------
-- 1) SEKTOREN (Reihenfolge = Sektor-Index 1…6; Farben = Config.Colors.Sectors)
-- ---------------------------------------------------------------------
Companies.Sectors = {
	{ Key = "T", Name = { de = "Tech & KI", en = "Tech & AI" }, Color = Color3.fromRGB(79, 140, 255) },
	{ Key = "E", Name = { de = "Energie & Klima", en = "Energy & Climate" }, Color = Color3.fromRGB(34, 211, 238) },
	{
		Key = "M",
		Name = { de = "Mobilität & Raumfahrt", en = "Mobility & Space" },
		Color = Color3.fromRGB(139, 92, 246),
	},
	{ Key = "K", Name = { de = "Konsum & Food", en = "Consumer & Food" }, Color = Color3.fromRGB(245, 158, 11) },
	{ Key = "G", Name = { de = "Gaming & Medien", en = "Gaming & Media" }, Color = Color3.fromRGB(236, 72, 153) },
	{
		Key = "F",
		Name = { de = "Finanzen & Immobilien", en = "Finance & Real Estate" },
		Color = Color3.fromRGB(250, 204, 21),
	},
}

local SHAPE = { T = "Hex", E = "Circle", M = "Diamond", K = "Circle", G = "Square", F = "Square" }

local function firm(
	id: number,
	ticker: string,
	name: string,
	sector: string,
	class: string,
	startAky: number,
	divPct: number,
	set: string,
	storyDe: string,
	storyEn: string
)
	return {
		Id = id,
		Ticker = ticker,
		Name = name,
		Story = { de = storyDe, en = storyEn },
		Sector = sector,
		Class = class,
		Start = math.round(startAky * 100),
		DivBps = math.round(divPct * 100),
		Set = set,
		Logo = { Letter = string.sub(ticker, 1, 1), Shape = SHAPE[sector] or "Circle" },
		ImageId = 0,
	}
end

-- ---------------------------------------------------------------------
-- 2) DIE 36 FIRMEN (§B6.2; fett geänderte Namen aus §C19: CGVO, KRWK, PFFR)
-- ---------------------------------------------------------------------
-- stylua: ignore start
Companies.Instruments = {
	firm(1, "CGVO", "Cognivo KI", "T", "Normal", 240, 0, "Trader", "Lern-Roboter mit KI", "Learning robots with AI"),
	firm(2, "KRWK", "Kernwerk Systems", "T", "Stabil", 180, 0.4, "Azubi", "Software für Fabriken", "Software for factories"),
	firm(3, "QTRX", "Quantorix Quantum", "T", "Wild", 42, 0, "Fonds", "Quantencomputer, schreibt noch Verluste", "Quantum computers, still loss-making"),
	firm(4, "LMRA", "Lumora Chips", "T", "Normal", 115, 0.2, "Trader", "Chips für KI-Rechenzentren", "Chips for AI data centres"),
	firm(5, "NMBY", "Nimbusly Cloud", "T", "Stabil", 88, 0.3, "Azubi", "Cloud-Speicher", "Cloud storage"),
	firm(6, "PXWK", "Pixelwerk Robotics", "T", "Wild", 27, 0, "Fonds", "Haushaltsroboter", "Household robots"),
	firm(7, "SNWK", "Sonnwerk Solar", "E", "Normal", 64, 0.3, "Azubi", "Solarparks", "Solar parks"),
	firm(8, "FSNT", "Fusionaut", "E", "Wild", 19, 0, "Fonds", "Kernfusion-Start-up", "Fusion energy start-up"),
	firm(9, "NBRZ", "Nordbrise Wind", "E", "Stabil", 52, 0.6, "Azubi", "Windparks auf See", "Offshore wind parks"),
	firm(10, "HDRV", "Hydrava", "E", "Normal", 36, 0, "Fonds", "Wasserstoff", "Hydrogen"),
	firm(11, "VLTR", "Voltaris", "E", "Normal", 98, 0.2, "Trader", "Batterien", "Batteries"),
	firm(12, "GTHM", "Geotherma", "E", "Stabil", 74, 0.7, "Trader", "Erdwärme", "Geothermal power"),
	firm(13, "ORBV", "Orbivo Space", "M", "Wild", 155, 0, "Fonds", "Raketen und Satelliten", "Rockets and satellites"),
	firm(14, "MGLN", "Magliner", "M", "Stabil", 61, 0.5, "Azubi", "Magnetschwebebahn", "Maglev trains"),
	firm(15, "VLCT", "Velocitra Motors", "M", "Normal", 210, 0.1, "Azubi", "Elektro-Sportwagen", "Electric sports cars"),
	firm(16, "DRNR", "Dronaro", "M", "Normal", 33, 0, "Trader", "Lieferdrohnen", "Delivery drones"),
	firm(17, "ARLF", "Aerolift", "M", "Wild", 24, 0, "Fonds", "Flugtaxis", "Flying taxis"),
	firm(18, "RTXO", "Robotaxo", "M", "Normal", 47, 0, "Trader", "Robotaxis", "Robotaxis"),
	firm(19, "KNSX", "Knusperix", "K", "Stabil", 58, 0.8, "Azubi", "Snacks", "Snacks"),
	firm(20, "BLBR", "Blubbro", "K", "Stabil", 41, 0.9, "Fonds", "Limonaden", "Lemonades"),
	firm(21, "SNKA", "Sneakora", "K", "Normal", 132, 0.3, "Trader", "Sneaker", "Sneakers"),
	firm(22, "BGPT", "Burgerplanet", "K", "Stabil", 77, 0.7, "Azubi", "Burger-Kette", "Burger chain"),
	firm(23, "PFFR", "Pfotenfreund", "K", "Normal", 29, 0.2, "Fonds", "Tierbedarf", "Pet supplies"),
	firm(24, "SPWK", "Spielwerk Toys", "K", "Normal", 45, 0.4, "Trader", "Spielzeug", "Toys"),
	firm(25, "ARCN", "Arcadeon Games", "G", "Normal", 96, 0.1, "Azubi", "Videospiele", "Video games"),
	firm(26, "STMR", "Streamora", "G", "Normal", 143, 0, "Trader", "Streaming", "Streaming"),
	firm(27, "PLVO", "Playverso VR", "G", "Wild", 38, 0, "Fonds", "VR-Brillen", "VR headsets"),
	firm(28, "MEMT", "Memetastic Media", "G", "Wild", 12, 0, "Fonds", "Meme-Videos", "Meme videos"),
	firm(29, "ESPV", "Esportiva Arena", "G", "Normal", 54, 0.2, "Trader", "E-Sport-Ligen", "Esports leagues"),
	firm(30, "NNBT", "Neonbeat Records", "G", "Stabil", 66, 0.5, "Azubi", "Musiklabel", "Music label"),
	firm(31, "TWBK", "Towerbank", "F", "Stabil", 118, 1.0, "Azubi", "Bank", "Bank"),
	firm(32, "SKLA", "Skylinea", "F", "Stabil", 84, 1.1, "Azubi", "Immobilien", "Real estate"),
	firm(33, "GLDR", "Goldader Mining", "F", "Normal", 71, 0.4, "Trader", "Goldminen", "Gold mines"),
	firm(34, "SCHF", "Sicherhafen", "F", "Stabil", 102, 1.2, "Trader", "Versicherung", "Insurance"),
	firm(35, "KLPY", "Klickpay", "F", "Normal", 89, 0, "Fonds", "Bezahl-App", "Payment app"),
	firm(36, "BKRZ", "Baukranz", "F", "Normal", 49, 0.5, "Fonds", "Baukonzern", "Construction group"),
}
-- stylua: ignore end

-- ---------------------------------------------------------------------
-- 3) ETFs (Kurs = Basis · exp(Mittel der Log-Renditen der Mitglieder seit Wochenstart), kein eigenes Rauschen)
-- ---------------------------------------------------------------------
local function etf(id: number, ticker: string, name: string, set: string, members: { number }, de: string, en: string)
	return {
		Id = id,
		Ticker = ticker,
		Name = name,
		Story = { de = de, en = en },
		Sector = "X",
		Class = "ETF",
		Start = 10000, -- 100,00 AKY in der allerersten Woche
		DivBps = 0,
		Set = set,
		Logo = { Letter = "Λ", Shape = "Hex" },
		ImageId = 0,
		Members = members,
	}
end

local function range(a: number, b: number): { number }
	local list = {}
	for i = a, b do
		table.insert(list, i)
	end
	return list
end

table.insert(
	Companies.Instruments,
	etf(
		40,
		"AKX36",
		"AKYTEX 36",
		"Azubi",
		range(1, 36),
		"Alle 36 Firmen gleich gewichtet – der ruhige Einstieg",
		"All 36 companies equally weighted – the calm way in"
	)
)
table.insert(
	Companies.Instruments,
	etf(41, "AKXT", "AKYTEX Tech", "Trader", range(1, 6), "Alle 6 Tech-Firmen", "All 6 tech companies")
)
table.insert(
	Companies.Instruments,
	etf(42, "AKXE", "AKYTEX Energie", "Trader", range(7, 12), "Alle 6 Energie-Firmen", "All 6 energy companies")
)
table.insert(
	Companies.Instruments,
	etf(
		43,
		"AKXM",
		"AKYTEX Mobilität",
		"Trader",
		range(13, 18),
		"Alle 6 Mobilitäts-Firmen",
		"All 6 mobility companies"
	)
)
table.insert(
	Companies.Instruments,
	etf(44, "AKXK", "AKYTEX Konsum", "Trader", range(19, 24), "Alle 6 Konsum-Firmen", "All 6 consumer companies")
)
table.insert(
	Companies.Instruments,
	etf(45, "AKXG", "AKYTEX Gaming", "Trader", range(25, 30), "Alle 6 Gaming-Firmen", "All 6 gaming companies")
)
table.insert(
	Companies.Instruments,
	etf(46, "AKXF", "AKYTEX Finanzen", "Trader", range(31, 36), "Alle 6 Finanz-Firmen", "All 6 finance companies")
)

-- ---------------------------------------------------------------------
-- 4) IPO-PIPELINE (v1: Erstnotiz ohne Zeichnung, §B6.3). Start = Ausgabepreis (Cent). Class = Klasse ab Börsentag 2
--    (am ersten Börsentag immer "Wild"). Season/Slot = Saison und Woche in der Saison (Config.Market.IpoPipeline).
-- ---------------------------------------------------------------------
local function ipo(
	id: number,
	ticker: string,
	name: string,
	sector: string,
	class: string,
	issueAky: number,
	season: number,
	slot: number,
	de: string,
	en: string
)
	local entry = firm(id, ticker, name, sector, class, issueAky, 0, "Fonds", de, en)
	entry.Ipo = true
	entry.Season = season
	entry.Slot = slot
	return entry
end

table.insert(
	Companies.Instruments,
	ipo(100, "NRNT", "Neuronauten", "T", "Normal", 30, 1, 1, "KI-Assistenten für Schulen", "AI tutors for schools")
)
table.insert(
	Companies.Instruments,
	ipo(101, "FLRA", "Flora Energy", "E", "Normal", 22, 1, 2, "Algen-Kraftwerke", "Algae power plants")
)
table.insert(
	Companies.Instruments,
	ipo(102, "MNDW", "Mondwerk", "M", "Wild", 48, 1, 3, "Mond-Stationen und Rover", "Moon bases and rovers")
)
table.insert(
	Companies.Instruments,
	ipo(
		103,
		"RBCF",
		"Robochef",
		"K",
		"Normal",
		26,
		1,
		4,
		"Koch-Roboter für Restaurants",
		"Cooking robots for restaurants"
	)
)

-- ---------------------------------------------------------------------
-- 5) TUTORIAL-ÜBUNGSAKTIE ACAD (250): nie im Frame, Kurs pro Spieler (WP4, §B8.6)
-- ---------------------------------------------------------------------
table.insert(Companies.Instruments, {
	Id = 250,
	Ticker = "ACAD",
	Name = "Akademie Übungsaktie",
	Story = { de = "Nur für deine erste Übung", en = "Just for your first practice trade" },
	Sector = "X",
	Class = "Normal",
	Start = 10000,
	DivBps = 0,
	Set = "Tutorial",
	Logo = { Letter = "A", Shape = "Circle" },
	ImageId = 0,
})

-- ---------------------------------------------------------------------
-- 6) THEMEN-KÖRBE (ab Trader I; 1 Tipp kauft alle Werte gleich gewichtet, §B6.2)
-- ---------------------------------------------------------------------
Companies.Baskets = {
	{ Key = "Ai", Name = { de = "KI-Korb", en = "AI basket" }, Members = { 1, 4, 5, 2 } },
	{ Key = "Space", Name = { de = "Raumfahrt-Korb", en = "Space basket" }, Members = { 13, 17, 14, 16 } },
	{
		Key = "Dividend",
		Name = { de = "Dividenden-Korb", en = "Dividend basket" },
		Members = { 31, 32, 34, 9, 12, 19 },
	},
	{ Key = "Climate", Name = { de = "Klima-Korb", en = "Climate basket" }, Members = { 7, 9, 12, 11, 10 } },
	{ Key = "Snack", Name = { de = "Snack-Korb", en = "Snack basket" }, Members = { 19, 22, 20, 21 } },
	{ Key = "Gaming", Name = { de = "Gaming-Korb", en = "Gaming basket" }, Members = { 25, 26, 29, 30 } },
}

-- ---------------------------------------------------------------------
-- 7) NACHSCHLAGE-TABELLEN (beim Laden gebaut; doppelte Ids/Kürzel -> assert, CC-Stil)
-- ---------------------------------------------------------------------
Companies.ById = {}
Companies.SectorIndex = {}
do
	local tickers = {}
	for _, inst in ipairs(Companies.Instruments) do
		assert(Companies.ById[inst.Id] == nil, "[Config.Companies] doppelte Id " .. tostring(inst.Id))
		assert(tickers[inst.Ticker] == nil, "[Config.Companies] doppeltes Kürzel " .. tostring(inst.Ticker))
		Companies.ById[inst.Id] = inst
		tickers[inst.Ticker] = true
	end
	for index, sector in ipairs(Companies.Sectors) do
		assert(Companies.SectorIndex[sector.Key] == nil, "[Config.Companies] doppelter Sektor " .. sector.Key)
		Companies.SectorIndex[sector.Key] = index
	end
end

-- ---------------------------------------------------------------------
-- 8) PRÜFUNG (Config.Validate sammelt alle Meldungen; leer = alles ok)
-- ---------------------------------------------------------------------
local CLASSES = { Stabil = true, Normal = true, Wild = true, ETF = true }
local SETS = { Azubi = true, Trader = true, Fonds = true, Tutorial = true }
local SHAPES = { Circle = true, Square = true, Hex = true, Diamond = true }

local function isInt(n: any): boolean
	return type(n) == "number" and n == n and n % 1 == 0 and n > -2 ^ 53 and n < 2 ^ 53
end

function Companies.Validate(_config: any): { string }
	local errors: { string } = {}
	local function add(text: string)
		table.insert(errors, "Config.Companies: " .. text)
	end
	local firms, etfs = 0, 0
	for _, inst in ipairs(Companies.Instruments) do
		local where = "Id " .. tostring(inst.Id)
		if not isInt(inst.Id) or inst.Id < 1 or inst.Id > 255 then
			add(where .. ": Id 1…255 erwartet")
		end
		if type(inst.Ticker) ~= "string" or not string.match(inst.Ticker, "^[A-Z0-9]+$") or #inst.Ticker > 6 then
			add(where .. ": Kürzel aus A–Z/0–9 (≤ 6) erwartet")
		end
		if type(inst.Name) ~= "string" or inst.Name == "" or #inst.Name > 40 then
			add(where .. ": Name (1–40 Zeichen) erwartet")
		end
		if type(inst.Story) ~= "table" or type(inst.Story.de) ~= "string" or type(inst.Story.en) ~= "string" then
			add(where .. ": Story { de, en } erwartet")
		end
		if not CLASSES[inst.Class] then
			add(where .. ": Klasse Stabil/Normal/Wild/ETF erwartet")
		end
		if not SETS[inst.Set] then
			add(where .. ": Set Azubi/Trader/Fonds/Tutorial erwartet")
		end
		if not isInt(inst.Start) or inst.Start < 50 or inst.Start > 9999999 then
			add(where .. ": Start in Cent (50 … 9.999.999) erwartet")
		end
		if not isInt(inst.DivBps) or inst.DivBps < 0 or inst.DivBps > 500 then
			add(where .. ": DivBps 0…500 erwartet")
		end
		if type(inst.Logo) ~= "table" or type(inst.Logo.Letter) ~= "string" or not SHAPES[inst.Logo.Shape] then
			add(where .. ": Logo { Letter, Shape } erwartet")
		end
		if inst.Class == "ETF" then
			etfs += 1
			if type(inst.Members) ~= "table" or #inst.Members == 0 then
				add(where .. ": ETF braucht Members")
			else
				for _, member in ipairs(inst.Members) do
					local m = Companies.ById[member]
					if not m or m.Class == "ETF" or m.Ipo or member > 36 then
						add(where .. ": ETF-Mitglied " .. tostring(member) .. " ist keine der 36 Firmen")
					end
				end
			end
		elseif inst.Set ~= "Tutorial" then
			if Companies.SectorIndex[inst.Sector] == nil then
				add(where .. ": Sektor T/E/M/K/G/F erwartet")
			end
			if inst.Ipo then
				if inst.Id < 100 or inst.Id > 139 then
					add(where .. ": IPO-Plätze sind 100–139")
				end
				if not isInt(inst.Season) or inst.Season < 1 or not isInt(inst.Slot) or inst.Slot < 1 then
					add(where .. ": IPO braucht Season und Slot (≥ 1)")
				end
			else
				firms += 1
				if inst.Id > 36 then
					add(where .. ": Firmen-Ids sind 1–36")
				end
			end
		end
	end
	if firms ~= 36 then
		add(("genau 36 Firmen erwartet (gefunden %d)"):format(firms))
	end
	if etfs ~= 7 then
		add(("genau 7 ETFs erwartet (gefunden %d)"):format(etfs))
	end
	if Companies.ById[250] == nil or Companies.ById[250].Set ~= "Tutorial" then
		add("ACAD (250, Set Tutorial) fehlt")
	end
	for index = 1, 36 do
		if Companies.ById[index] == nil then
			add("Firma " .. index .. " fehlt")
		end
	end
	for _, basket in ipairs(Companies.Baskets) do
		if type(basket.Key) ~= "string" or type(basket.Name) ~= "table" or type(basket.Members) ~= "table" then
			add("Korb: { Key, Name, Members } erwartet")
		elseif #basket.Members < 4 or #basket.Members > 6 then
			add("Korb " .. basket.Key .. ": 4–6 Werte erwartet")
		else
			for _, member in ipairs(basket.Members) do
				local m = Companies.ById[member]
				if not m or member > 36 then
					add("Korb " .. basket.Key .. ": Wert " .. tostring(member) .. " ist keine der 36 Firmen")
				end
			end
		end
	end
	return errors
end

return Companies
