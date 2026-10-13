-- =====================================================================
--  AKYTEX TYCOON – Turm-Ökonomie (Config.Tower)
--  Besitzer: WP6 (Turm-Ökonomie). Vertrag: DESIGN.md §C14.2 (Tower), §B3, §B4, §B5; geprüft mit tools/economy_sim.py.
--  Alle Zahlen sind die Startwerte aus DESIGN.md §B4/§B5 und 1:1 änderbar. Shared/TowerMath liest diese Datei direkt
--  (gleiche Werte auf Server und Client). Ändern -> danach `python3 tools/economy_sim.py` laufen lassen (Gates G1–G4).
--  Wird an alle Clients repliziert -> KEINE Geheimnisse hier!
--
--  Diese Datei lädt KEINE Roblox-Dienste und braucht keine Roblox-Typen beim Laden (Farben als Hex-Text,
--  CFrame nur über pcall) -> die Luau-CLI-Tests (tests/towermath.test.luau) können sie direkt laden und prüfen,
--  dass TowerMath exakt diese Werte benutzt.
--
--  Abschnitte:
--    1) Etagen, Kosten, Einkommen (§B5.1)      8) Bauen, Beschleuniger, Bau-Hilfe (§B4.7)
--    2) Maße & Geometrie (§B4.1)                9) Multiplikatoren (§B5.2)
--    3) Die 12 Stufen + Tore (§B4.2)           10) Börsengang-Reset & Vorstand (§B9.6)
--    4) Abteilungen (§B4.3)                    11) Deko-Ersatzwerte (§B4.8, falls Config.Decor fehlt)
--    5) Personal (§B4.4)                       12) Name, Fassaden, Neon, Kronen (§B4.9)
--    6) Raum-Stufen & Effizienz (§B4.5/§B5.3)  13) Besuche, Aufzug, Privat-Etagen, Plots (§B3/§B4.10)
--    7) Tresor & Offline (§B4.6)               14) Asset-Plätze (§C14.3)
--  Helfer:   Tower.NameText(a, n, lang): string     Tower-Name aus Wortbausteinen ("Stiller Falke Tower")
--            Tower.Validate(Config): { string }     prüft alles (SelfTest / Boot-warn)
-- =====================================================================

local Tower = {}

-- CFrame.identity nur, wenn Roblox-Typen da sind (Luau-CLI: nil -> Asset-Plätze ohne Versatz, nur für Tests)
local IDENTITY: any = nil
pcall(function()
	IDENTITY = (CFrame :: any).identity
end)

-- Leerer Asset-Platz (0 = Code-Rezept, §C14.3)
local function slot(): { [string]: any }
	return { MeshId = 0, TextureId = 0, Scale = 1, Offset = IDENTITY }
end

-- ---------------------------------------------------------------------
-- 1) ETAGEN, KOSTEN, EINKOMMEN (§B5.1)
--    Basis-Einkommen Etage n: I(n) = I0 × IR^(n−1) CR/s. Gehalt: Salary CR/s immer (auch mit 0 Etagen).
--    Kosten: Etage 1 gratis, Etage 2 = C2, danach je Etage × Faktor des Bandes (gerundet auf ganze CR).
--    Summe aller 50 Etagen 5,23e12 CR, Etage 50 = 1.961.500.847.186 CR (Tabelle: tools/economy_sim.py --table).
-- ---------------------------------------------------------------------
Tower.I0 = 4
Tower.IR = 1.30
Tower.C2 = 1000
Tower.Bands = { -- { erste Etage, letzte Etage, Faktor je Etage }
	{ 3, 12, 1.50 },
	{ 13, 25, 1.56 },
	{ 26, 40, 1.58 },
	{ 41, 50, 1.60 },
}
Tower.Salary = 3
Tower.Floors = 50

-- ---------------------------------------------------------------------
-- 2) MASSE & GEOMETRIE (§B4.1) – gemeinsame Konvention für PlotService (Teleports) und TowerVisualService (Hülle)
--    Etage n (1 … 50) beginnt auf Höhe (n − 1) × FloorHeight über dem Plot-Boden; Etage 1 = Erdgeschoss mit Lobby.
--    Der Aufzugskern (10 × 10) steht in der Plot-Mitte, seine Tür zeigt nach vorn (Plot-LookVector = zur Plaza).
--    Ankunftspunkt (Füße) = Plot-Mitte + vorn × ElevatorLanding, Höhe Boden + Slab.
-- ---------------------------------------------------------------------
Tower.FloorHeight = 12
Tower.Geometry = {
	Slab = 1, -- Deckenplatte 1 Stud
	Core = 10, -- Aufzugskern 10 × 10
	ElevatorLanding = 8, -- Studs vor der Kern-Mitte (Kern-Hälfte 5 + 3)
	CrownMax = 80, -- Krone höchstens 80 Studs
	Footprint = { Small = 40, Large = 56, LargeFromStage = 5 }, -- Stufen 1–4: 40 × 40, ab Stufe 5: 56 × 56
	Setbacks = { { 31, 52 }, { 41, 48 } }, -- Rücksprung ab Etage 31 auf 52 × 52, ab Etage 41 auf 48 × 48
}

-- ---------------------------------------------------------------------
-- 3) DIE 12 STUFEN (§B4.2) – Tor = Lizenz-Index (Config.Progression.Licences) + Mindestzahl Börsengänge.
--    Robux überspringen nie ein Tor. 0 Etagen = Bauplatz mit Garagen-Rolltor (Stufe 1 ohne Büro).
-- ---------------------------------------------------------------------
-- stylua: ignore start
Tower.Stages = {
	{ Key = "Garage",     First = 1,  Last = 1,  Licence = 1, Ipo = 0, Name = { de = "Garage-Startup", en = "Garage Startup" },
		Desc = { de = "Rolltor, Neon „STARTUP“", en = "Roller door, neon “STARTUP”" } },
	{ Key = "Kiosk",      First = 2,  Last = 3,  Licence = 1, Ipo = 0, Name = { de = "Kiosk-Büro", en = "Kiosk Office" },
		Desc = { de = "Markise, erstes Glas", en = "Awning, first glass" } },
	{ Key = "Loft",       First = 4,  Last = 6,  Licence = 1, Ipo = 0, Name = { de = "Loft", en = "Loft" },
		Desc = { de = "Klinker und Glas, Dachterrasse", en = "Brick and glass, roof terrace" } },
	{ Key = "Office",     First = 7,  Last = 9,  Licence = 1, Ipo = 0, Name = { de = "Bürohaus", en = "Office Block" },
		Desc = { de = "Fensterbänder, blaues Neonband", en = "Window bands, blue neon strip" } },
	{ Key = "Glass",      First = 10, Last = 13, Licence = 2, Ipo = 0, Name = { de = "Glas-Office", en = "Glass Office" },
		Desc = { de = "Volle Glasfassade", en = "Full glass facade" } },
	{ Key = "Business",   First = 14, Last = 17, Licence = 3, Ipo = 0, Name = { de = "Business-Tower", en = "Business Tower" },
		Desc = { de = "Abgetreppte Krone, Dach-LED", en = "Stepped crown, roof LED" } },
	{ Key = "HighRise",   First = 18, Last = 21, Licence = 4, Ipo = 0, Name = { de = "Hochhaus", en = "High-Rise" },
		Desc = { de = "Senkrechte Neon-Finnen", en = "Vertical neon fins" } },
	{ Key = "Skyscraper", First = 22, Last = 25, Licence = 4, Ipo = 0, Name = { de = "Wolkenkratzer", en = "Skyscraper" },
		Desc = { de = "Zwillingskrone, LED-Fassaden-Ticker", en = "Twin crown, LED facade ticker" } },
	{ Key = "Skyline",    First = 26, Last = 30, Licence = 5, Ipo = 0, Name = { de = "Skyline-Tower", en = "Skyline Tower" },
		Desc = { de = "Beleuchtete Turmspitze, Himmelsgarten", en = "Lit spire, sky garden" } },
	{ Key = "Mega",       First = 31, Last = 36, Licence = 6, Ipo = 0, Name = { de = "Mega-Tower", en = "Mega Tower" },
		Desc = { de = "Helipad, Leuchtfeuer, Suchscheinwerfer", en = "Helipad, beacon, searchlights" } },
	{ Key = "Hyper",      First = 37, Last = 43, Licence = 7, Ipo = 0, Name = { de = "Hyper-Spire", en = "Hyper Spire" },
		Desc = { de = "Sky-Lounge-Ring, Holo-Bänder", en = "Sky lounge ring, holo bands" } },
	{ Key = "Orbit",      First = 44, Last = 50, Licence = 7, Ipo = 1, Name = { de = "ΛKYTEX Orbit-Spire", en = "ΛKYTEX Orbit Spire" },
		Desc = { de = "Antennen-Beam in die Wolken, Holo-Krone", en = "Antenna beam into the clouds, holo crown" } },
}
-- stylua: ignore end

-- ---------------------------------------------------------------------
-- 4) ABTEILUNGEN (§B4.3) – eine je Etage, Wechsel kostet RoomChangePct der Etagenkosten (sofort).
--    Factor = Raum-Faktor auf die eigene Etage. MinStage = ab Tower-Stufe. Max = höchstens so viele im Tower
--    (mehr hätten keine Wirkung). Code = Kurz-Code im Plot-Attribut "Layout" (§C12.3).
--    Wirkungen (nur Turm): StaffMult/Radius (Personal-Boni auf Etagen ±Radius), TowerStaffMult (alle Personal-Boni
--    je Raum), NeighbourMult (Etagen direkt darüber/darunter), IncomePct (Perm-Anteil je Raum), VaultBonus
--    (Tresor-Kapazität je Raum), OfflineHours (Offline-Deckel je Raum), CarSlots, TopOnly, DecorSlots.
-- ---------------------------------------------------------------------
Tower.DefaultRoom = "Office"
Tower.RoomChangePct = 0.25
Tower.Rooms = {
	{
		Key = "Office",
		Code = "O",
		Name = { de = "Büro", en = "Office" },
		Desc = { de = "Solides Grundeinkommen.", en = "Solid base income." },
		Factor = 1.00,
		MinStage = 1,
	},
	{
		Key = "Desk",
		Code = "D",
		Name = { de = "Trading-Desk", en = "Trading Desk" },
		Desc = { de = "Monitore zeigen deine Live-Positionen.", en = "Monitors show your live positions." },
		Factor = 1.25,
		MinStage = 1,
	},
	{
		Key = "Cafe",
		Code = "C",
		Name = { de = "Smoothie-Café", en = "Smoothie Café" },
		Desc = {
			de = "Personal-Boni auf den Etagen ±2 zählen ×1,20.",
			en = "Staff bonuses on floors ±2 count ×1.20.",
		},
		Factor = 0.60,
		MinStage = 3,
		StaffMult = 1.20,
		Radius = 2,
	},
	{
		Key = "Garage",
		Code = "G",
		Name = { de = "Garagen-Ebene", en = "Garage Level" },
		Desc = { de = "+4 Auto-Plätze und ein Auto-Aufzug.", en = "+4 car slots and a car lift." },
		Factor = 0.40,
		MinStage = 3,
		CarSlots = 4,
	},
	{
		Key = "Marketing",
		Code = "M",
		Name = { de = "Marketing-Studio", en = "Marketing Studio" },
		Desc = {
			de = "+5 % Turm-Einkommen je Studio (max. 3), Respekt zählt doppelt.",
			en = "+5% tower income per studio (max 3), respect counts double.",
		},
		Factor = 0.80,
		MinStage = 4,
		IncomePct = 0.05,
		Max = 3,
	},
	{
		Key = "Vault",
		Code = "V",
		Name = { de = "Tresor-Etage", en = "Vault Floor" },
		Desc = { de = "Tresor-Kapazität +50 % je Etage (max. 2).", en = "Vault capacity +50% per floor (max 2)." },
		Factor = 0.50,
		MinStage = 4,
		VaultBonus = 0.5,
		Max = 2,
	},
	{
		Key = "Lab",
		Code = "L",
		Name = { de = "Research-Labor", en = "Research Lab" },
		Desc = {
			de = "Etagen direkt darüber und darunter verdienen ×1,15.",
			en = "Floors directly above and below earn ×1.15.",
		},
		Factor = 0.80,
		MinStage = 5,
		NeighbourMult = 1.15,
	},
	{
		Key = "Server",
		Code = "S",
		Name = { de = "Server-Raum", en = "Server Room" },
		Desc = {
			de = "Alle Personal-Boni im Turm ×1,10 je Raum (max. 3).",
			en = "All staff bonuses in the tower ×1.10 per room (max 3).",
		},
		Factor = 0.70,
		MinStage = 5,
		TowerStaffMult = 1.10,
		Max = 3,
	},
	{
		Key = "Lounge",
		Code = "U",
		Name = { de = "Lounge", en = "Lounge" },
		Desc = {
			de = "+1 h Offline-Deckel je Lounge (max. +4 h), Respekt wirkt 2 h.",
			en = "+1 h offline cap per lounge (max +4 h), respect lasts 2 h.",
		},
		Factor = 0.50,
		MinStage = 6,
		OfflineHours = 1,
		Max = 4,
	},
	{
		Key = "BotLab",
		Code = "B",
		Name = { de = "Bot-Labor", en = "Bot Lab" },
		Desc = {
			de = "Zuhause deiner Strategie-Bots mit Live-Dashboards (nur Optik).",
			en = "Home of your strategy bots with live dashboards (visual only).",
		},
		Factor = 1.10,
		MinStage = 6,
	},
	{
		Key = "Penthouse",
		Code = "P",
		Name = { de = "Penthouse", en = "Penthouse" },
		Desc = {
			de = "Nur ganz oben: +10 % Turm-Einkommen, 8 Deko-Plätze, Pool und Balkon.",
			en = "Top floor only: +10% tower income, 8 decor slots, pool and balcony.",
		},
		Factor = 0,
		MinStage = 10,
		IncomePct = 0.10,
		TopOnly = true,
		DecorSlots = 8,
		Max = 1,
	},
}

-- ---------------------------------------------------------------------
-- 5) PERSONAL (§B4.4) – Roboter aus Parts. Slots je Etage (3 mit Pass "Personal+"), einstellen sofort,
--    entlassen ohne Rückerstattung. Kosten = CostMult × max(Etagenkosten, UpgradeMin).
--    Janitor/Security belegen keinen Platz, je 1 im Tower (Lobby). Code = Kurz-Code im "Layout" (§C12.3).
-- ---------------------------------------------------------------------
Tower.StaffSlots = 2
Tower.StaffSlotsPlus = 3
Tower.StaffPass = "StaffPlus" -- Pass-Schlüssel (Config.Shop / MonetizationService.HasPass)
Tower.Staff = {
	{
		Key = "Intern",
		Code = "I",
		Name = { de = "Praktikant P-1", en = "Intern P-1" },
		Desc = { de = "+10 % auf die Etage.", en = "+10% on the floor." },
		Bonus = 0.10,
		CostMult = 1,
		MinStage = 2,
		Asset = slot(),
	},
	{
		Key = "Analyst",
		Code = "A",
		Name = { de = "Analyst A-3", en = "Analyst A-3" },
		Desc = { de = "+25 % auf die Etage.", en = "+25% on the floor." },
		Bonus = 0.25,
		CostMult = 3,
		MinStage = 3,
		Asset = slot(),
	},
	{
		Key = "Senior",
		Code = "S",
		Name = { de = "Senior-Droid S-7", en = "Senior Droid S-7" },
		Desc = { de = "+50 % auf die Etage.", en = "+50% on the floor." },
		Bonus = 0.50,
		CostMult = 9,
		MinStage = 5,
		Asset = slot(),
	},
	{
		Key = "Quant",
		Code = "Q",
		Name = { de = "Quant-Mainframe Q-9", en = "Quant Mainframe Q-9" },
		Desc = { de = "+100 % auf die Etage.", en = "+100% on the floor." },
		Bonus = 1.00,
		CostMult = 25,
		MinStage = 8,
		Asset = slot(),
	},
	{
		Key = "Janitor",
		Code = "J",
		Name = { de = "Hausmeister-Bot", en = "Janitor Bot" },
		Desc = {
			de = "Leert den Tresor alle 60 s, solange du auf deinem Plot bist.",
			en = "Empties the vault every 60 s while you are on your plot.",
		},
		Price = 0,
		MinStage = 1,
		Lobby = true,
		Asset = slot(),
	},
	{
		Key = "Security",
		Code = "W",
		Name = { de = "Sicherheits-Bot", en = "Security Bot" },
		Desc = { de = "Patrouilliert in der Lobby (Deko).", en = "Patrols the lobby (decor)." },
		Price = 50000,
		MinStage = 8,
		Lobby = true,
		Asset = slot(),
	},
}
Tower.FireRefund = 0 -- Entlassen: keine Rückerstattung (Bestätigung im Client)

-- ---------------------------------------------------------------------
-- 6) RAUM-STUFEN L1–L5 (§B4.5) & EFFIZIENZ (§B5.3)
--    LevelCost[l] = Kosten von L(l) nach L(l+1) als Vielfaches von max(Etagenkosten, UpgradeMin).
--    Effizienz: +Step Perm je Stufe, höchstens Max je Lauf, Stufe k+1 kostet Base × Ratio^k (Stufe 20: 1,16e13).
-- ---------------------------------------------------------------------
Tower.LevelFactor = { 1.00, 1.25, 1.50, 1.80, 2.20 }
Tower.LevelCost = { 1, 2.5, 6, 15 }
Tower.UpgradeMin = 500
Tower.Efficiency = { Step = 0.10, Base = 10000, Ratio = 3, Max = 20 }

-- ---------------------------------------------------------------------
-- 7) TRESOR & OFFLINE (§B4.6)
--    Tresor-Kapazität = VaultMinutes aktuelles Einkommen (+VaultFloorBonus je Tresor-Etage, max. 2).
--    Sammeln: Kassen-Tor/HUD-Knopf nur auf dem eigenen Plot (≤ CollectRange Studs waagerecht zur Plot-Mitte),
--    Hausmeister-Bot alle JanitorSeconds (nur auf dem Plot), Pass Auto-Kassierer alle AutoCollectSeconds (überall).
--    Offline (ab MinAway s): Dauer-Einkommen ohne Zeitlich/Sozial × Rate × min(Abwesenheit, Deckel).
-- ---------------------------------------------------------------------
Tower.VaultMinutes = 20
Tower.VaultFloorBonus = 0.5
Tower.VaultPrefill = 300 -- erster Bau des Kontos: Tresor mit 300 CR vorgefüllt (Tutorial "Erstes Sammeln", §B2)
Tower.CollectRange = 70
Tower.JanitorSeconds = 60
Tower.AutoCollectSeconds = 3
Tower.AutoCollectPass = "AutoCollect"
Tower.Offline = {
	Rate = 0.5, -- 50 %
	RateMax = 0.9, -- Obergrenze 90 %
	CapHours = 8, -- Grund-Deckel 8 h
	CapMax = 24, -- Obergrenze 24 h
	MinAway = 60, -- erst ab 60 s Abwesenheit
	PerkRate = 0.05, -- +5 Pp je Vorstand-Stufe "Tresor"
	PerkHours = 1, -- +1 h je Vorstand-Stufe "Tresor"
	PerkMax = 8, -- Vorstand "Tresor" hat 8 Stufen (max. +40 Pp)
	PassRate = 0.15, -- Pass Offline-Tresor +15 Pp …
	PassMinHours = 24, -- … und Deckel mindestens 24 h
	Pass = "OfflineVault",
	LoungeHours = 1, -- +1 h je Lounge …
	LoungeMax = 4, -- … höchstens 4
	ClubHours = 4, -- Vorstands-Club +4 h
}

-- ---------------------------------------------------------------------
-- 8) BAUEN (§B4.7) – eine Baustelle gleichzeitig. Etagen 1–Instant: SceneSeconds (nur Kran-Szene).
--    Ab Etage Instant+1: min(Cap, BaseSeconds × Ratio^(n−10)). Beschleuniger (Bau-Crew Pro, Vorstand "Tempo",
--    Admin-Bau-Boom, Bau-Hilfe) nie unter MinFactor der Grundzeit; Sofortbau-Token und Bau-Express beenden direkt.
-- ---------------------------------------------------------------------
Tower.Build = {
	Instant = 9,
	SceneSeconds = 3,
	BaseSeconds = 20,
	Ratio = 1.33,
	Cap = 5400, -- 90 min
	MinFactor = 0.25,
	HelpPct = 0.10, -- Bau-Hilfe: −10 % der Restzeit je Helfer
	HelpMax = 3, -- höchstens 3 Helfer je Etage, jeder 1× je Etage
	HelpRange = 40, -- Studs (waagerecht) zur Baustelle
	HelpSeasonXp = 25, -- Helfer: +25 Saison-XP (nie Trader-XP)
	CrewPct = 0.5, -- Pass Bau-Crew Pro: −50 %
	CrewPass = "BuildCrew",
	TempoPct = 0.10, -- Vorstand "Tempo": −10 % je Stufe …
	TempoMax = 5, -- … höchstens 5 Stufen
	DailyInstant = 1, -- 1 Gratis-Sofortbau-Token je UTC-Tag
	InstantMax = 99, -- gespeicherte Sofortbau-Token höchstens
	ExpressMax = 50, -- gespeicherte Bau-Express-Token höchstens (verfallen nie)
	ExpressMaxSeconds = 86400,
}

-- ---------------------------------------------------------------------
-- 9) MULTIPLIKATOREN (§B5.2) – wirken NUR auf Turm-Einkommen (nie auf AKY, Gewinn-Transfer, Dividenden, Trades)
--    Perm (additiv) · Trader-Faktor (Skill, ProgressionService) · Pässe (1 + x2 + 2·x3) · VIP/Club/Premium ·
--    Zeitlich = min(TimedCap, Boost × Server × Event), Event nie über EventMax.
--    Bull/Parade/BellMoment/EventMax sind live änderbar (Config.LiveFields, Admin-Tab „Live-Ops“).
-- ---------------------------------------------------------------------
Tower.Mult = {
	IpoStep = 0.25, -- je Börsengang …
	IpoMax = 20, -- … höchstens 20 gezählt
	GrowthStep = 0.10, -- Vorstand "Wachstum" je Stufe …
	GrowthMax = 10,
	AlbumStep = 0.02, -- je vollständigem Sektor-Satz im Firmen-Album …
	AlbumMax = 6,
	FriendStep = 0.10, -- je Freund im Server …
	FriendMax = 4,
	RespektStep = 0.01, -- je aktivem Respekt …
	RespektMax = 20,
	Vip = 1.10, -- Anzeige-Aufteilung von MonetizationService.FixedFactor
	Club = 1.15,
	Premium = 1.10,
	X2 = 2, -- persönlicher Boost x2
	X5 = 5, -- Turbo x5 (überlagert x2, x2-Zeit pausiert)
	Bull = 1.5, -- Bullen-Bonus (Goldener Bulle, nicht stapelbar)
	Parade = 1.5, -- Bullen-Parade (ganzer Server)
	BellMoment = 1.2, -- Glocken-Moment (ganzer Server; es gilt der größere Server-Wert)
	ServerMax = 2, -- Server-Boost höchstens ×2
	EventMax = 3, -- Golden Hour / Admin höchstens ×3
	TimedCap = 10, -- Zeitlich gesamt höchstens ×10
	BoostMaxSeconds = 2592000, -- gespeicherte Boost-Zeit höchstens 30 Tage je Art
	CostEventMin = 0.1, -- Bau-Boom-Rabatt: Kosten höchstens auf 10 %
	EventMaxSeconds = 3600, -- Event-/Server-/Kosten-Fenster höchstens 1 h im Voraus
}

-- ---------------------------------------------------------------------
-- 10) BÖRSENGANG-RESET (§B9.6) & VORSTAND (nur Turm/Lifestyle)
--     Perk-Namen = Ast-Schlüssel von ProgressionService.Perk(p, branch) (Config.Progression.Prestige.Perks).
--     Bleibt: Depot, Lizenz, Lager, Fassade/Neon/Name, Token, Boosts, Hausmeister-/Sicherheits-Bot (Lobby).
-- ---------------------------------------------------------------------
Tower.Ipo = {
	Blitz = { 4, 8, 12 }, -- Vorstand "Blitzstart" 1/2/3: Start mit so vielen fertigen Etagen
	BuildPct = 0.05, -- Vorstand "Bau": −5 % Kosten je Stufe (Etagen, Raum-Stufen, Personal, Effizienz) …
	BuildMax = 8, -- … höchstens 8 Stufen
	KeepLobbyBots = true,
}
Tower.Perks = {
	Growth = "Wachstum",
	Blitz = "Blitzstart",
	Build = "Bau",
	Tempo = "Tempo",
	Vault = "Tresor",
}
Tower.Crowns = { -- Börsengang-Krone nach Anzahl Börsengänge (kosmetisch)
	{ Key = "Silver", Ipos = 1, Hex = "#c0c7d4", Name = { de = "Silber-Krone", en = "Silver Crown" }, Asset = slot() },
	{ Key = "Gold", Ipos = 3, Hex = "#facc15", Name = { de = "Gold-Krone", en = "Gold Crown" }, Asset = slot() },
	{
		Key = "Platinum",
		Ipos = 5,
		Hex = "#e5e7eb",
		Name = { de = "Platin-Krone", en = "Platinum Crown" },
		Asset = slot(),
	},
	{ Key = "Holo", Ipos = 10, Hex = "#7c5cff", Name = { de = "Holo-Krone", en = "Holo Crown" }, Asset = slot() },
	{ Key = "Orbit", Ipos = 20, Hex = "#b36bff", Name = { de = "Orbit-Ring", en = "Orbit Ring" }, Asset = slot() },
}

-- ---------------------------------------------------------------------
-- 11) DEKO-ERSATZWERTE (§B4.8) – gelten nur, wenn Config.Decor (WP8) sie nicht liefert
-- ---------------------------------------------------------------------
Tower.Decor = {
	SlotsPerFloor = 3,
	PenthouseSlots = 8,
	ComfortPct = 0.005, -- +0,5 % Etagen-Einkommen je Komfort-Punkt …
	ComfortMax = 0.10, -- … höchstens +10 % je Etage
	ComfortItemMax = 5, -- ein Teil gibt 1–5 Punkte
}

-- ---------------------------------------------------------------------
-- 12) NAME, FASSADEN, NEON, KRONEN (§B4.9) – Name nur aus Wortbausteinen (kein Freitext)
--     Unlock: "Default" = immer · "Pass" = MonetizationService.HasPass(Pass) · "Cosmetic" = Kosmetik-Besitz
--     (Login-Kalender, Erfolge, Saison, Codes – über ShopService.Grant { Cosmetics = { Key } }).
-- ---------------------------------------------------------------------
-- stylua: ignore start
Tower.Names = {
	Suffix = { de = "Tower", en = "Tower" },
	Adj = {
		{ de = "Blauer", en = "Blue" }, { de = "Goldener", en = "Golden" }, { de = "Silberner", en = "Silver" },
		{ de = "Schneller", en = "Swift" }, { de = "Stiller", en = "Silent" }, { de = "Kluger", en = "Clever" },
		{ de = "Kühner", en = "Bold" }, { de = "Hoher", en = "High" }, { de = "Heller", en = "Bright" },
		{ de = "Frischer", en = "Fresh" }, { de = "Mutiger", en = "Brave" }, { de = "Freier", en = "Free" },
		{ de = "Starker", en = "Strong" }, { de = "Ruhiger", en = "Calm" }, { de = "Leuchtender", en = "Shining" },
		{ de = "Gläserner", en = "Glass" }, { de = "Eiserner", en = "Iron" }, { de = "Kristall-", en = "Crystal" },
		{ de = "Polarer", en = "Polar" }, { de = "Urbaner", en = "Urban" }, { de = "Digitaler", en = "Digital" },
		{ de = "Smarter", en = "Smart" }, { de = "Moderner", en = "Modern" }, { de = "Großer", en = "Grand" },
		{ de = "Weiter", en = "Wide" }, { de = "Klarer", en = "Clear" }, { de = "Edler", en = "Noble" },
		{ de = "Junger", en = "Young" }, { de = "Wilder", en = "Wild" }, { de = "Treuer", en = "Loyal" },
		{ de = "Wacher", en = "Alert" }, { de = "Mitternachts-", en = "Midnight" }, { de = "Sonniger", en = "Sunny" },
		{ de = "Strahlender", en = "Radiant" }, { de = "Kosmischer", en = "Cosmic" }, { de = "Elektrischer", en = "Electric" },
		{ de = "Grüner", en = "Green" }, { de = "Purpurner", en = "Crimson" }, { de = "Violetter", en = "Violet" },
		{ de = "Smaragd-", en = "Emerald" },
	},
	Noun = {
		{ de = "Falke", en = "Falcon" }, { de = "Adler", en = "Eagle" }, { de = "Komet", en = "Comet" },
		{ de = "Meteor", en = "Meteor" }, { de = "Horizont", en = "Horizon" }, { de = "Gipfel", en = "Summit" },
		{ de = "Pfeil", en = "Arrow" }, { de = "Blitz", en = "Bolt" }, { de = "Löwe", en = "Lion" },
		{ de = "Wolf", en = "Wolf" }, { de = "Tiger", en = "Tiger" }, { de = "Phönix", en = "Phoenix" },
		{ de = "Drache", en = "Dragon" }, { de = "Stern", en = "Star" }, { de = "Mond", en = "Moon" },
		{ de = "Planet", en = "Planet" }, { de = "Orbit", en = "Orbit" }, { de = "Diamant", en = "Diamond" },
		{ de = "Fluss", en = "River" }, { de = "Strom", en = "Current" }, { de = "Wind", en = "Wind" },
		{ de = "Sturm", en = "Storm" }, { de = "Funke", en = "Spark" }, { de = "Puls", en = "Pulse" },
		{ de = "Kompass", en = "Compass" }, { de = "Anker", en = "Anchor" }, { de = "Bulle", en = "Bull" },
		{ de = "Titan", en = "Titan" }, { de = "Gigant", en = "Giant" }, { de = "Magnet", en = "Magnet" },
		{ de = "Motor", en = "Engine" }, { de = "Rekord", en = "Record" }, { de = "Zenit", en = "Zenith" },
		{ de = "Nordstern", en = "North Star" }, { de = "Delfin", en = "Dolphin" }, { de = "Pionier", en = "Pioneer" },
		{ de = "Ozean", en = "Ocean" }, { de = "Vulkan", en = "Volcano" }, { de = "Gletscher", en = "Glacier" },
		{ de = "Panther", en = "Panther" },
	},
}
-- stylua: ignore end

Tower.DefaultSkin = "GlassBlue"
Tower.Skins = {
	{ Key = "GlassBlue", Unlock = "Default", Name = { de = "Glas-Blau", en = "Glass Blue" } },
	{ Key = "Obsidian", Unlock = "Cosmetic", Name = { de = "Obsidian", en = "Obsidian" } }, -- Login Tag 14
	{ Key = "MarbleWhite", Unlock = "Cosmetic", Name = { de = "Marmor-Weiß", en = "Marble White" } }, -- Erfolg
	{ Key = "NeonCyber", Unlock = "Cosmetic", Name = { de = "Neon-Cyber", en = "Neon Cyber" } }, -- Erfolg
	{ Key = "GoldLuxe", Unlock = "Pass", Pass = "FacadeKit", Name = { de = "Gold-Luxe", en = "Gold Luxe" } },
	{ Key = "HoloPrism", Unlock = "Cosmetic", Name = { de = "Holo-Prisma", en = "Holo Prism" } }, -- Saison-Premium
	{ Key = "Polar", Unlock = "Cosmetic", Name = { de = "Polar", en = "Polar" } }, -- Login Tag 28
}

Tower.DefaultNeon = "Accent"
Tower.Neon = {
	{ Key = "Accent", Unlock = "Default", Hex = "#4f8cff", Name = { de = "Akzentblau", en = "Accent Blue" } },
	{ Key = "Up", Unlock = "Default", Hex = "#22c55e", Name = { de = "Grün", en = "Green" } },
	{ Key = "Down", Unlock = "Default", Hex = "#ef4444", Name = { de = "Rot", en = "Red" } },
	{ Key = "Cyan", Unlock = "Default", Hex = "#22d3ee", Name = { de = "Cyan", en = "Cyan" } },
	{ Key = "Purple", Unlock = "Default", Hex = "#8b5cf6", Name = { de = "Violett", en = "Purple" } },
	{ Key = "Gold", Unlock = "Default", Hex = "#facc15", Name = { de = "Gold", en = "Gold" } },
	{ Key = "Startup", Unlock = "Cosmetic", Hex = "#7c9cff", Name = { de = "Startup", en = "Startup" } }, -- Starter-Paket
	{ Key = "Partner", Unlock = "Cosmetic", Hex = "#ec4899", Name = { de = "Partner", en = "Partner" } }, -- Einladen
	{ Key = "Returner", Unlock = "Cosmetic", Hex = "#ffcf6e", Name = { de = "Rückkehrer", en = "Returner" } },
}

-- ---------------------------------------------------------------------
-- 13) BESUCHE, AUFZUG, PRIVAT-ETAGEN, PLOTS (§B3, §B4.10)
-- ---------------------------------------------------------------------
Tower.PrivateMax = 5
Tower.Visit = {
	TowerRadius = 55, -- waagerecht so nah an einer Plot-Mitte = "in diesem Tower" (Plot 110 × 110)
	SpawnAtPlot = true, -- Figur erscheint vor dem eigenen Tower (Tutorial "Das ist deine Garage")
	SpawnOffset = 40, -- Studs vor der Plot-Mitte (Vorplatz am Kassen-Tor)
	StreamTimeout = 2, -- Sekunden: Player:RequestStreamAroundAsync vor Teleports
	PlazaFallback = { 0, 4, 60 }, -- Plaza-Punkt (x, y, z), falls CityService.Anchor("Spawn") fehlt
}
Tower.Plots = { -- Ersatz, falls CityService.PlotSite / Config.City.Plots fehlen (§A5: R 420, 18° + k·36°)
	Radius = 420,
	StartAngle = 18,
	Step = 36,
	Size = 110,
}
Tower.StageToastCooldown = 90 -- Server-Toast "X erreicht Stufe Y" höchstens alle 90 s je Spieler

-- ---------------------------------------------------------------------
-- 14) ASSET-PLÄTZE (§C14.3) – 0 = Code-Rezept (WP8 baut), gesetzte Ids werden beim Start vorgeladen
-- ---------------------------------------------------------------------
Tower.Assets = {
	Crane = slot(),
	Lobby = slot(),
	Vault = slot(),
	CashGate = slot(),
	RespektPillar = slot(),
	Elevator = slot(),
	PlotSign = slot(),
}

-- =====================================================================
-- HELFER
-- =====================================================================
local function pick(pair: any, lang: string): string
	if type(pair) ~= "table" then
		return ""
	end
	local text = pair[lang]
	if type(text) ~= "string" then
		text = pair.en
	end
	return if type(text) == "string" then text else ""
end

-- Tower-Name aus den Bausteinen a (Adjektiv) und n (Nomen); ungültige Indizes -> 1
function Tower.NameText(a: number, n: number, lang: string): string
	local adjList = Tower.Names.Adj
	local nounList = Tower.Names.Noun
	local ai = if type(a) == "number" and adjList[a] then a else 1
	local ni = if type(n) == "number" and nounList[n] then n else 1
	local adj = pick(adjList[ai], lang)
	local noun = pick(nounList[ni], lang)
	local suffix = pick(Tower.Names.Suffix, lang)
	-- Bindestrich-Bausteine ("Kristall-") hängen direkt am Nomen
	if string.sub(adj, -1) == "-" then
		return adj .. noun .. " " .. suffix
	end
	return adj .. " " .. noun .. " " .. suffix
end

-- =====================================================================
-- PRÜFUNG (Config.Validate sammelt alle Meldungen; leer = alles ok)
-- =====================================================================
local function isNum(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isPair(v: any): boolean
	return type(v) == "table" and type(v.de) == "string" and v.de ~= "" and type(v.en) == "string" and v.en ~= ""
end

function Tower.Validate(_config: any): { string }
	local errors: { string } = {}
	local function add(text: string)
		table.insert(errors, "Config.Tower." .. text)
	end
	local function num(path: string, v: any, lo: number, hi: number)
		if not isNum(v) or v < lo or v > hi then
			add(("%s: Zahl %s … %s erwartet"):format(path, tostring(lo), tostring(hi)))
		end
	end
	local function int(path: string, v: any, lo: number, hi: number)
		if not isNum(v) or v % 1 ~= 0 or v < lo or v > hi then
			add(("%s: ganze Zahl %s … %s erwartet"):format(path, tostring(lo), tostring(hi)))
		end
	end
	local function keyed(path: string, list: any, extra: ((entry: any, where: string) -> ())?): { [string]: any }
		local seen: { [string]: any } = {}
		if type(list) ~= "table" or #list == 0 then
			add(path .. ": Liste erwartet")
			return seen
		end
		for i, entry in ipairs(list) do
			local where = ("%s[%d]"):format(path, i)
			if type(entry) ~= "table" or type(entry.Key) ~= "string" or entry.Key == "" then
				add(where .. ".Key: Text erwartet")
				continue
			end
			assert(seen[entry.Key] == nil, "[Config.Tower] doppelter Schlüssel " .. path .. "." .. entry.Key)
			seen[entry.Key] = entry
			if not isPair(entry.Name) then
				add(where .. ".Name: { de, en } erwartet")
			end
			if extra then
				extra(entry, where)
			end
		end
		return seen
	end

	-- 1) Etagen
	num("I0", Tower.I0, 0.01, 1e6)
	num("IR", Tower.IR, 1, 3)
	int("C2", Tower.C2, 1, 1e9)
	int("Salary", Tower.Salary, 0, 1e6)
	if Tower.Floors ~= 50 then
		add("Floors: 50 erwartet (Stufen-Tabelle §B4.2 endet bei Etage 50)")
	end
	local nextFirst = 3
	for i, band in ipairs(Tower.Bands) do
		local where = ("Bands[%d]"):format(i)
		if type(band) ~= "table" or not isNum(band[1]) or not isNum(band[2]) or not isNum(band[3]) then
			add(where .. ": { erste, letzte, Faktor } erwartet")
			continue
		end
		if band[1] ~= nextFirst or band[2] < band[1] then
			add(where .. ": lückenlose Bänder ab Etage 3 erwartet")
		end
		num(where .. "[3]", band[3], 1, 3)
		nextFirst = band[2] + 1
	end
	if nextFirst ~= 51 then
		add("Bands: müssen genau bis Etage 50 reichen")
	end
	-- teuerste Etage: Kosten < 1e14 (Gate G1)
	local cost = Tower.C2
	for n = 3, 50 do
		for _, band in ipairs(Tower.Bands) do
			if type(band) == "table" and isNum(band[1]) and isNum(band[2]) and n >= band[1] and n <= band[2] then
				cost *= band[3]
			end
		end
	end
	if isNum(cost) and cost >= 1e14 then
		add(("Bands: Etage 50 kostet %.3g ≥ 1e14 (Gate G1)"):format(cost))
	end

	-- 2) Geometrie
	int("FloorHeight", Tower.FloorHeight, 4, 40)
	num("Geometry.Slab", Tower.Geometry.Slab, 0, 4)
	num("Geometry.ElevatorLanding", Tower.Geometry.ElevatorLanding, 0, 40)

	-- 3) Stufen
	keyed("Stages", Tower.Stages, function(entry: any, where: string)
		int(where .. ".First", entry.First, 1, 50)
		int(where .. ".Last", entry.Last, 1, 50)
		int(where .. ".Licence", entry.Licence, 1, 10)
		int(where .. ".Ipo", entry.Ipo, 0, 100)
		if not isPair(entry.Desc) then
			add(where .. ".Desc: { de, en } erwartet")
		end
	end)
	if #Tower.Stages ~= 12 then
		add("Stages: genau 12 Stufen erwartet (§B4.2)")
	end
	local expectFirst = 1
	local lastLicence, lastIpo = 0, 0
	for i, stage in ipairs(Tower.Stages) do
		if type(stage) == "table" and isNum(stage.First) and isNum(stage.Last) then
			if stage.First ~= expectFirst or stage.Last < stage.First then
				add(("Stages[%d]: lückenlose Etagen-Bereiche ab 1 erwartet"):format(i))
			end
			expectFirst = stage.Last + 1
			if isNum(stage.Licence) and stage.Licence < lastLicence then
				add(("Stages[%d].Licence: Tore dürfen nicht sinken"):format(i))
			end
			if isNum(stage.Ipo) and stage.Ipo < lastIpo then
				add(("Stages[%d].Ipo: Tore dürfen nicht sinken"):format(i))
			end
			lastLicence = if isNum(stage.Licence) then stage.Licence else lastLicence
			lastIpo = if isNum(stage.Ipo) then stage.Ipo else lastIpo
		end
	end
	if expectFirst ~= 51 then
		add("Stages: müssen genau bis Etage 50 reichen")
	end

	-- 4) Abteilungen
	local codes: { [string]: boolean } = {}
	local rooms = keyed("Rooms", Tower.Rooms, function(entry: any, where: string)
		num(where .. ".Factor", entry.Factor, 0, 5)
		int(where .. ".MinStage", entry.MinStage, 1, 12)
		if not isPair(entry.Desc) then
			add(where .. ".Desc: { de, en } erwartet")
		end
		if type(entry.Code) ~= "string" or not string.match(entry.Code, "^%u$") then
			add(where .. ".Code: ein Großbuchstabe erwartet")
		elseif codes[entry.Code] then
			add(where .. ".Code: doppelt")
		else
			codes[entry.Code] = true
		end
		if entry.Max ~= nil then
			int(where .. ".Max", entry.Max, 1, 50)
		end
		if entry.StaffMult ~= nil then
			num(where .. ".StaffMult", entry.StaffMult, 1, 3)
			int(where .. ".Radius", entry.Radius, 0, 10)
		end
		if entry.TowerStaffMult ~= nil then
			num(where .. ".TowerStaffMult", entry.TowerStaffMult, 1, 3)
		end
		if entry.NeighbourMult ~= nil then
			num(where .. ".NeighbourMult", entry.NeighbourMult, 1, 3)
		end
		if entry.IncomePct ~= nil then
			num(where .. ".IncomePct", entry.IncomePct, 0, 1)
		end
		if entry.VaultBonus ~= nil then
			num(where .. ".VaultBonus", entry.VaultBonus, 0, 5)
		end
		if entry.OfflineHours ~= nil then
			num(where .. ".OfflineHours", entry.OfflineHours, 0, 24)
		end
		if entry.DecorSlots ~= nil then
			int(where .. ".DecorSlots", entry.DecorSlots, 1, 16)
		end
	end)
	if type(Tower.DefaultRoom) ~= "string" or rooms[Tower.DefaultRoom] == nil then
		add("DefaultRoom: Schlüssel aus Rooms erwartet")
	end
	num("RoomChangePct", Tower.RoomChangePct, 0, 1)

	-- 5) Personal
	local staffCodes: { [string]: boolean } = {}
	keyed("Staff", Tower.Staff, function(entry: any, where: string)
		int(where .. ".MinStage", entry.MinStage, 1, 12)
		if not isPair(entry.Desc) then
			add(where .. ".Desc: { de, en } erwartet")
		end
		if type(entry.Code) ~= "string" or not string.match(entry.Code, "^%u$") then
			add(where .. ".Code: ein Großbuchstabe erwartet")
		elseif staffCodes[entry.Code] then
			add(where .. ".Code: doppelt")
		else
			staffCodes[entry.Code] = true
		end
		if entry.Lobby then
			int(where .. ".Price", entry.Price, 0, 1e13)
		else
			num(where .. ".Bonus", entry.Bonus, 0, 10)
			num(where .. ".CostMult", entry.CostMult, 0, 1000)
		end
	end)
	int("StaffSlots", Tower.StaffSlots, 1, 6)
	int("StaffSlotsPlus", Tower.StaffSlotsPlus, 1, 6)
	if isNum(Tower.StaffSlots) and isNum(Tower.StaffSlotsPlus) and Tower.StaffSlotsPlus < Tower.StaffSlots then
		add("StaffSlotsPlus: mindestens StaffSlots erwartet")
	end

	-- 6) Raum-Stufen & Effizienz
	if #Tower.LevelFactor ~= 5 then
		add("LevelFactor: 5 Stufen erwartet")
	end
	local lastFactor = 0
	for i, factor in ipairs(Tower.LevelFactor) do
		num(("LevelFactor[%d]"):format(i), factor, 0.1, 10)
		if isNum(factor) and factor < lastFactor then
			add(("LevelFactor[%d]: darf nicht sinken"):format(i))
		end
		lastFactor = if isNum(factor) then factor else lastFactor
	end
	if #Tower.LevelCost ~= 4 then
		add("LevelCost: 4 Werte erwartet (L1→L2 … L4→L5)")
	end
	for i, mult in ipairs(Tower.LevelCost) do
		num(("LevelCost[%d]"):format(i), mult, 0, 1000)
	end
	int("UpgradeMin", Tower.UpgradeMin, 0, 1e9)
	num("Efficiency.Step", Tower.Efficiency.Step, 0, 1)
	int("Efficiency.Base", Tower.Efficiency.Base, 1, 1e9)
	num("Efficiency.Ratio", Tower.Efficiency.Ratio, 1, 10)
	int("Efficiency.Max", Tower.Efficiency.Max, 1, 40)
	if
		isNum(Tower.Efficiency.Base)
		and isNum(Tower.Efficiency.Ratio)
		and isNum(Tower.Efficiency.Max)
		and Tower.Efficiency.Base * Tower.Efficiency.Ratio ^ (Tower.Efficiency.Max - 1) >= 1e14
	then
		add("Efficiency: teuerste Stufe ≥ 1e14 (Gate G1)")
	end

	-- 7) Tresor & Offline
	num("VaultMinutes", Tower.VaultMinutes, 1, 240)
	num("VaultFloorBonus", Tower.VaultFloorBonus, 0, 5)
	int("VaultPrefill", Tower.VaultPrefill, 0, 1e9)
	num("CollectRange", Tower.CollectRange, 10, 500)
	num("JanitorSeconds", Tower.JanitorSeconds, 1, 3600)
	num("AutoCollectSeconds", Tower.AutoCollectSeconds, 1, 3600)
	local off = Tower.Offline
	num("Offline.Rate", off.Rate, 0, 1)
	num("Offline.RateMax", off.RateMax, 0, 1)
	num("Offline.CapHours", off.CapHours, 0, 48)
	num("Offline.CapMax", off.CapMax, 0, 48)
	num("Offline.MinAway", off.MinAway, 0, 3600)
	num("Offline.PerkRate", off.PerkRate, 0, 0.2)
	num("Offline.PerkHours", off.PerkHours, 0, 6)
	int("Offline.PerkMax", off.PerkMax, 0, 20)
	num("Offline.PassRate", off.PassRate, 0, 1)
	num("Offline.PassMinHours", off.PassMinHours, 0, 48)
	num("Offline.LoungeHours", off.LoungeHours, 0, 6)
	int("Offline.LoungeMax", off.LoungeMax, 0, 20)
	num("Offline.ClubHours", off.ClubHours, 0, 24)
	if isNum(off.Rate) and isNum(off.RateMax) and off.Rate > off.RateMax then
		add("Offline.Rate: darf nicht über RateMax liegen")
	end
	if isNum(off.CapHours) and isNum(off.CapMax) and off.CapHours > off.CapMax then
		add("Offline.CapHours: darf nicht über CapMax liegen")
	end

	-- 8) Bauen
	local build = Tower.Build
	int("Build.Instant", build.Instant, 0, 50)
	num("Build.SceneSeconds", build.SceneSeconds, 0, 60)
	num("Build.BaseSeconds", build.BaseSeconds, 1, 3600)
	num("Build.Ratio", build.Ratio, 1, 3)
	num("Build.Cap", build.Cap, 1, 86400)
	num("Build.MinFactor", build.MinFactor, 0.01, 1)
	num("Build.HelpPct", build.HelpPct, 0, 0.5)
	int("Build.HelpMax", build.HelpMax, 0, 10)
	num("Build.HelpRange", build.HelpRange, 5, 500)
	int("Build.HelpSeasonXp", build.HelpSeasonXp, 0, 1000)
	num("Build.CrewPct", build.CrewPct, 0, 0.9)
	num("Build.TempoPct", build.TempoPct, 0, 0.2)
	int("Build.TempoMax", build.TempoMax, 0, 10)
	int("Build.DailyInstant", build.DailyInstant, 0, 5)
	int("Build.InstantMax", build.InstantMax, 1, 999)
	int("Build.ExpressMax", build.ExpressMax, 1, 200)
	int("Build.ExpressMaxSeconds", build.ExpressMaxSeconds, 60, 7 * 86400)

	-- 9) Multiplikatoren
	local mult = Tower.Mult
	for _, key in ipairs({ "IpoStep", "GrowthStep", "AlbumStep", "FriendStep", "RespektStep" }) do
		num("Mult." .. key, (mult :: any)[key], 0, 1)
	end
	for _, key in ipairs({ "IpoMax", "GrowthMax", "AlbumMax", "FriendMax", "RespektMax" }) do
		int("Mult." .. key, (mult :: any)[key], 0, 100)
	end
	for _, key in ipairs({ "Vip", "Club", "Premium", "Bull", "Parade", "BellMoment" }) do
		num("Mult." .. key, (mult :: any)[key], 1, 3)
	end
	num("Mult.X2", mult.X2, 1, 10)
	num("Mult.X5", mult.X5, 1, 10)
	num("Mult.ServerMax", mult.ServerMax, 1, 3)
	num("Mult.EventMax", mult.EventMax, 1, 3) -- Event nie > ×3 (§B5.2)
	num("Mult.TimedCap", mult.TimedCap, 1, 10) -- Zeitlich nie > ×10 (§B5.2)
	int("Mult.BoostMaxSeconds", mult.BoostMaxSeconds, 3600, 31536000)
	num("Mult.CostEventMin", mult.CostEventMin, 0.01, 1)
	int("Mult.EventMaxSeconds", mult.EventMaxSeconds, 60, 86400)

	-- 10) Börsengang
	if type(Tower.Ipo.Blitz) ~= "table" or #Tower.Ipo.Blitz ~= 3 then
		add("Ipo.Blitz: 3 Stufen erwartet (4 / 8 / 12)")
	else
		for i, floors in ipairs(Tower.Ipo.Blitz) do
			int(("Ipo.Blitz[%d]"):format(i), floors, 0, 50)
		end
	end
	num("Ipo.BuildPct", Tower.Ipo.BuildPct, 0, 0.1)
	int("Ipo.BuildMax", Tower.Ipo.BuildMax, 0, 20)
	for key, branch in pairs(Tower.Perks) do
		if type(branch) ~= "string" or branch == "" then
			add("Perks." .. tostring(key) .. ": Ast-Name erwartet")
		end
	end
	local lastIpos = 0
	keyed("Crowns", Tower.Crowns, function(entry: any, where: string)
		int(where .. ".Ipos", entry.Ipos, 1, 1000)
		if isNum(entry.Ipos) and entry.Ipos <= lastIpos then
			add(where .. ".Ipos: muss steigen")
		end
		lastIpos = if isNum(entry.Ipos) then entry.Ipos else lastIpos
		if type(entry.Hex) ~= "string" or not string.match(entry.Hex, "^#%x%x%x%x%x%x$") then
			add(where .. ".Hex: #rrggbb erwartet")
		end
	end)

	-- 11) Deko-Ersatz
	int("Decor.SlotsPerFloor", Tower.Decor.SlotsPerFloor, 1, 16)
	int("Decor.PenthouseSlots", Tower.Decor.PenthouseSlots, 1, 16)
	num("Decor.ComfortPct", Tower.Decor.ComfortPct, 0, 0.1)
	num("Decor.ComfortMax", Tower.Decor.ComfortMax, 0, 1)
	int("Decor.ComfortItemMax", Tower.Decor.ComfortItemMax, 1, 20)

	-- 12) Name, Fassaden, Neon
	for _, list in ipairs({ "Adj", "Noun" }) do
		local entries = (Tower.Names :: any)[list]
		if type(entries) ~= "table" or #entries ~= 40 then
			add("Names." .. list .. ": 40 Bausteine erwartet")
		else
			for i, entry in ipairs(entries) do
				if not isPair(entry) then
					add(("Names.%s[%d]: { de, en } erwartet"):format(list, i))
				end
			end
		end
	end
	local function unlockCheck(entry: any, where: string)
		if entry.Unlock ~= "Default" and entry.Unlock ~= "Pass" and entry.Unlock ~= "Cosmetic" then
			add(where .. ".Unlock: Default/Pass/Cosmetic erwartet")
		elseif entry.Unlock == "Pass" and (type(entry.Pass) ~= "string" or entry.Pass == "") then
			add(where .. ".Pass: Pass-Schlüssel erwartet")
		end
	end
	local skins = keyed("Skins", Tower.Skins, unlockCheck)
	if skins[Tower.DefaultSkin] == nil or skins[Tower.DefaultSkin].Unlock ~= "Default" then
		add("DefaultSkin: freie Fassade aus Skins erwartet")
	end
	local neons = keyed("Neon", Tower.Neon, function(entry: any, where: string)
		unlockCheck(entry, where)
		if type(entry.Hex) ~= "string" or not string.match(entry.Hex, "^#%x%x%x%x%x%x$") then
			add(where .. ".Hex: #rrggbb erwartet")
		end
	end)
	if neons[Tower.DefaultNeon] == nil or neons[Tower.DefaultNeon].Unlock ~= "Default" then
		add("DefaultNeon: freie Farbe aus Neon erwartet")
	end

	-- 13) Besuche & Plots
	int("PrivateMax", Tower.PrivateMax, 0, 50)
	num("Visit.TowerRadius", Tower.Visit.TowerRadius, 10, 200)
	num("Visit.SpawnOffset", Tower.Visit.SpawnOffset, 0, 80)
	num("Visit.StreamTimeout", Tower.Visit.StreamTimeout, 0, 10)
	if type(Tower.Visit.SpawnAtPlot) ~= "boolean" then
		add("Visit.SpawnAtPlot: true/false erwartet")
	end
	local fallback = Tower.Visit.PlazaFallback
	if type(fallback) ~= "table" or not isNum(fallback[1]) or not isNum(fallback[2]) or not isNum(fallback[3]) then
		add("Visit.PlazaFallback: { x, y, z } erwartet")
	end
	num("Plots.Radius", Tower.Plots.Radius, 50, 2000)
	num("Plots.StartAngle", Tower.Plots.StartAngle, -360, 360)
	num("Plots.Step", Tower.Plots.Step, 1, 360)
	num("Plots.Size", Tower.Plots.Size, 20, 400)
	num("StageToastCooldown", Tower.StageToastCooldown, 0, 3600)
	return errors
end

return Tower
