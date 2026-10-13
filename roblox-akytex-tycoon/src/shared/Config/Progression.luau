-- =====================================================================
--  AKYTEX TYCOON – Fortschritt: Lizenzen, Trader-XP, Know-how, Ruf, Titel, Börsengang, Akademie, Quests,
--  Erfolge, Badges, Album, Tutorial, Sozial, Bestenlisten (Config.Progression)
--  Besitzer: WP9 (Fortschritt, Tutorial, Sozial, Bestenlisten). Vertrag: DESIGN.md §C14.2 (Progression), §B9.1–§B9.8,
--  §B2 (Tutorial), §B11 (Sozial/Bestenlisten). Alle Zahlen sind Startwerte und 1:1 änderbar.
--  Wird an alle Clients repliziert -> KEINE Geheimnisse hier (Quiz-Lösungen stehen deshalb im Server-Code,
--  ProgressionService "QUIZ_KEY"). Diese Datei lädt KEINE Roblox-Dienste/-Typen -> Luau-CLI-ladbar (Tests).
--
--  Robux-Firewall (§0.4): Nichts in dieser Datei ist mit Robux erreichbar. Lizenz, Trader-XP, Know-how, Ruf und
--  Aktien-Sterne entstehen nur aus Handeln/Lernen; Vorstand-Perks (Sterne) wirken nur auf Turm/Lifestyle.
--
--  Abschnitte:
--    1) Lizenzen (eine Tabelle für WP4/WP6/WP9)     8) Börsengang & Vorstand + Ticker-Sperrliste
--    2) Prüfungs-Aufgaben                            9) Akademie (16 Lektionen, Texte in Lang/Progress)
--    3) Trader-XP-Quellen, Level, Power-Hour         10) Quest-Arten + Vorlagen (30 Tages, 12 Wochen, 20 Starter)
--    4) Know-how-Baum                                11) Erfolge (60) · 12) Badges (15) · 13) Firmen-Album
--    5) Indikatoren je Lizenz                        14) Tutorial (Funnel 1–18)
--    6) Ruf                                          15) Sozial (Respekt, Reaktionen, Einladen, Gruppe, Zeigen)
--    7) Titel (Vermögen + Sonder-Titel)              16) Bestenlisten + Hall of Fame
--  Helfer: Progression.Validate(Config): { string }
-- =====================================================================

local Progression = {}

-- ---------------------------------------------------------------------
-- 1) LIZENZEN (§B9.2) – Basis in CENT (2.500.000 = 25.000 AKY), Gebühr in Basispunkten (10 = 0,10 %),
--    Klumpen-Grenze als Anteil, Turm-Bonus als Anteil (0,04 = +4 %), Positions-Faktor × LiquidityBase (MARKET §11.6).
--    Layer = Terminal-Schicht ("Simple" | "Trader" | "Pro"), Set = Instrumenten-Satz, MaxStage = höchste Tower-Stufe,
--    MaxIpo = so viele Börsengänge erlaubt (BG 1–2 Trader I · 3–4 Trader II · 5–9 Trader III · ab 10 Fondsmanager I),
--    BotSlots = Strategie-Bot-Plätze. Prüfungen sind gratis und NIE mit Robux überspringbar.
-- ---------------------------------------------------------------------
-- stylua: ignore start
Progression.Licences = {
	{ Key = "Azubi1",  Name = { de = "Azubi I", en = "Apprentice I" },            Xp = 0,      Exam = {},                               Basis = 2500000,    BauKurs = 40,    TowerBonus = 0,    FeeBps = 10, MaxWeight = 0.30, MaxOrders = 5,  PosFactor = 0.01, Layer = "Simple", Set = "Azubi",  MaxStage = 4,  MaxIpo = 0,   BotSlots = 0, ImageId = 0 },
	{ Key = "Azubi2",  Name = { de = "Azubi II", en = "Apprentice II" },          Xp = 300,    Exam = { "ProtectPair" },                Basis = 5000000,    BauKurs = 200,   TowerBonus = 0.04, FeeBps = 10, MaxWeight = 0.30, MaxOrders = 5,  PosFactor = 0.01, Layer = "Simple", Set = "Azubi",  MaxStage = 5,  MaxIpo = 0,   BotSlots = 0, ImageId = 0 },
	{ Key = "Azubi3",  Name = { de = "Azubi III", en = "Apprentice III" },        Xp = 1200,   Exam = { "Sectors3", "ProtectedProfit" }, Basis = 10000000,   BauKurs = 800,   TowerBonus = 0.08, FeeBps = 10, MaxWeight = 0.30, MaxOrders = 5,  PosFactor = 0.01, Layer = "Simple", Set = "Azubi",  MaxStage = 6,  MaxIpo = 0,   BotSlots = 1, ImageId = 0 },
	{ Key = "Trader1", Name = { de = "Trader I", en = "Trader I" },               Xp = 3000,   Exam = { "AsExpected", "BuyAfterGood" }, Basis = 25000000,   BauKurs = 1500,  TowerBonus = 0.12, FeeBps = 8,  MaxWeight = 0.40, MaxOrders = 15, PosFactor = 0.2,  Layer = "Trader", Set = "Trader", MaxStage = 8,  MaxIpo = 2,   BotSlots = 2, ImageId = 0 },
	{ Key = "Trader2", Name = { de = "Trader II", en = "Trader II" },             Xp = 7000,   Exam = {},                               Basis = 60000000,   BauKurs = 3000,  TowerBonus = 0.16, FeeBps = 8,  MaxWeight = 0.40, MaxOrders = 15, PosFactor = 0.2,  Layer = "Trader", Set = "Trader", MaxStage = 9,  MaxIpo = 4,   BotSlots = 2, ImageId = 0 },
	{ Key = "Trader3", Name = { de = "Trader III", en = "Trader III" },           Xp = 14000,  Exam = { "CrashSurvive" },               Basis = 150000000,  BauKurs = 6000,  TowerBonus = 0.20, FeeBps = 8,  MaxWeight = 0.40, MaxOrders = 15, PosFactor = 0.2,  Layer = "Trader", Set = "Trader", MaxStage = 10, MaxIpo = 9,   BotSlots = 3, ImageId = 0 },
	{ Key = "Fonds1",  Name = { de = "Fondsmanager I", en = "Fund Manager I" },   Xp = 28000,  Exam = { "Skill500", "Analyst3" },       Basis = 400000000,  BauKurs = 12000, TowerBonus = 0.25, FeeBps = 5,  MaxWeight = 0.50, MaxOrders = 30, PosFactor = 5,    Layer = "Pro",    Set = "Fonds",  MaxStage = 12, MaxIpo = 999, BotSlots = 4, ImageId = 0 },
	{ Key = "Fonds2",  Name = { de = "Fondsmanager II", en = "Fund Manager II" }, Xp = 50000,  Exam = {},                               Basis = 1000000000, BauKurs = 20000, TowerBonus = 0.30, FeeBps = 5,  MaxWeight = 0.50, MaxOrders = 30, PosFactor = 5,    Layer = "Pro",    Set = "Fonds",  MaxStage = 12, MaxIpo = 999, BotSlots = 4, ImageId = 0 },
	{ Key = "Fonds3",  Name = { de = "Fondsmanager III", en = "Fund Manager III" }, Xp = 80000, Exam = { "LeagueGold" },                Basis = 2500000000, BauKurs = 30000, TowerBonus = 0.35, FeeBps = 5,  MaxWeight = 0.50, MaxOrders = 30, PosFactor = 5,    Layer = "Pro",    Set = "Fonds",  MaxStage = 12, MaxIpo = 999, BotSlots = 4, ImageId = 0 },
	{ Key = "Legende", Name = { de = "Börsen-Legende", en = "Exchange Legend" },  Xp = 125000, Exam = { "LeagueDiamond", "LowDrawdown" }, Basis = 6000000000, BauKurs = 40000, TowerBonus = 0.40, FeeBps = 3,  MaxWeight = 0.60, MaxOrders = 50, PosFactor = 100,  Layer = "Pro",    Set = "Fonds",  MaxStage = 12, MaxIpo = 999, BotSlots = 5, ImageId = 0 },
}
-- stylua: ignore end
Progression.LicenceLegend = 10 -- schaltet Auto "Singularity", goldenes Terminal-Theme, Titel "Börsen-Legende" frei
Progression.LegendCosmetic = "ThemeGold" -- goldenes Terminal-Theme (Kosmetik in Purchases.Cosmetics; Auto über Config.Vehicles)

-- ---------------------------------------------------------------------
-- 2) PRÜFUNGS-AUFGABEN (Akademie-Aufgaben, MARKET §14.3). Texte: Lang "prog.exam.<Key>" / "prog.exam.<Key>.d".
--    Source sagt, woher der Server das Bestehen erkennt (ProgressionService):
--      Trade = eigene Fills (OrderService.OnTrade) · Lesson = perfektes Quiz der genannten Lektion ·
--      Crash = Depotwert über einen Crash (Kurs-Nachricht "Crash") · League = Liga-Statistik (OrderService.LeagueStats)
--      Earnings = Kauf vor Quartalszahlen (Analysten-Urteile sichtbar) und Zahlen in Kaufrichtung
--    Eine gescheiterte Crash-Prüfung ist nach 1 Börsentag (RetryTicks) wiederholbar.
-- ---------------------------------------------------------------------
Progression.ExamTasks = {
	{ Key = "ProtectPair", Source = "Trade" }, -- Kauf mit "Schutz an" (Schutz-Paar) – auch die ACAD-Übung zählt
	{ Key = "Sectors3", Source = "Trade" }, -- gleichzeitig Anteile in 3 Sektoren
	{ Key = "ProtectedProfit", Source = "Trade" }, -- geschützter Trade mit Gewinn verkauft
	{ Key = "AsExpected", Source = "Lesson", Lesson = "L07" }, -- Lektion „Wie erwartet“ perfekt
	{ Key = "BuyAfterGood", Source = "Trade" }, -- Kauf ≤ 60 s nach guter Fakten-Nachricht
	{ Key = "CrashSurvive", Source = "Crash" }, -- investiert durch einen Crash, Verlust < 10 %
	{ Key = "Skill500", Source = "League" }, -- Skill-Score ≥ 500 in einer Woche (≥ 6 zählende Börsentage)
	{ Key = "Analyst3", Source = "Earnings" }, -- Kauf ≤ 5 min vor Quartalszahlen, Zahlen in Kaufrichtung
	{ Key = "LeagueGold", Source = "League" }, -- Liga-Stufe Gold
	{ Key = "LeagueDiamond", Source = "League" }, -- Liga-Stufe Diamant
	{ Key = "LowDrawdown", Source = "League" }, -- Woche mit max. Drawdown < 8 % und Ø-Tagesrendite ≥ +1 %
}
Progression.Exam = {
	RetryTicks = 1200, -- gescheiterte Crash-Prüfung: nach 1 Börsentag wieder offen
	CrashSeconds = 900, -- Beobachtungsfenster ab der Crash-Nachricht (Fallphase + Erholung)
	CrashMaxLoss = 0.10,
	CrashMinExposure = 0.10, -- mindestens 10 % des Depotwerts investiert (sonst zählt der Crash nicht)
	GoodNewsSeconds = 60, -- "Kaufe nach einer guten Nachricht": Fenster nach der Fakten-Nachricht
	EarningsLeadSeconds = 300, -- "★★★-Analyst": Kauf höchstens 5 min vor den Zahlen
	SkillMin = 500,
	SkillMinDays = 6,
	DrawdownMax = 0.08,
	AvgDailyMin = 0.01,
	DrawdownMinDays = 6,
	Sectors = 3,
}

-- ---------------------------------------------------------------------
-- 3) TRADER-XP (§B9.1) – nur Handeln/Lernen, nie Bauen, nie Robux. Cap = höchstens so viele Gutschriften je
--    UTC-Tag (WeeklyQuest: je ISO-Woche). Ziel ≈ 700 XP je aktiver Stunde.
-- ---------------------------------------------------------------------
Progression.XpSources = {
	Trade = { Xp = 5, Cap = 40 }, -- abgeschlossener Trade (≥ 2 % Depotwert, ≥ 60 s gehalten)
	TradeProfit = { Xp = 5, Cap = 40 }, -- … davon mit Gewinn nach Gebühren
	TradeProtected = { Xp = 2, Cap = 40 }, -- … mit Schutz eröffnet
	ReadWell = { Xp = 10, Cap = 20 }, -- „Gut gelesen“
	PositiveDay = { Xp = 40, Cap = 12 }, -- positiver Börsentag (≥ 3 zählende Trades, Rendite > 0)
	LessonFirst = { Xp = 100 },
	LessonRepeat = { Xp = 10, Cap = 5 },
	LessonPerfect = { Xp = 30 },
	DailyQuest = { Xp = 100, Cap = 3 }, -- Handels-/Akademie-Tagesquest
	WeeklyQuest = { Xp = 500, Cap = 3, Weekly = true }, -- Handels-Wochenquest
	Exam = { Xp = 250, NoMult = true }, -- Lizenzprüfung bestanden
	Tutorial = { Xp = 300, NoMult = true }, -- Tutorial (Schritte 6–14), einmalig
	PressQuiz = { Xp = 50, Cap = 6 }, -- Pressekonferenz-Quiz (WP11 ruft AddXp)
	League = { Xp = 0, NoMult = true }, -- Liga-Stufe der Vorwoche (Beträge in LeagueXp)
}
Progression.LeagueXp = { Bronze = 300, Silber = 600, Gold = 1200, Diamant = 2500 }
Progression.LevelCurve = 12.5 -- XP_gesamt(L) = 12,5 × (L − 1)²
Progression.MaxLevel = 100
Progression.MaxXpGrant = 10000 -- Schutz: eine einzelne Gutschrift höchstens so groß
-- Kostenlose Verdoppler für alle (nie Robux): täglich 19:00 Berlin, 60 min ×2 (Admin "XP-Rausch" über EventService)
Progression.PowerHour = { Hour = 19, Minute = 0, Minutes = 60, Mult = 2 }
Progression.XpRushKind = "XpRush" -- EventService.Active()-Art für den Admin-XP-Rausch (×2, für alle gleich)
Progression.XpMultMax = 2 -- Power-Hour und XP-Rausch stapeln nicht (höchstens ×2)

-- ---------------------------------------------------------------------
-- 4) KNOW-HOW (§B9.3) – Trading-Werkzeuge, nie Robux. Quellen: +1 je Trader-Level ab 2, +3 je Lizenz (ab Azubi II),
--    +1 je abgeschlossener Akademie-Serie (4 Lektionen) -> bis zu 130 KH. Umverteilen 1× je ISO-Woche gratis.
--    Licence = ab welcher Lizenz die NÄCHSTE Stufe kaufbar ist (LevelLicence je Stufe überschreibt).
-- ---------------------------------------------------------------------
Progression.KnowHow = {
	PerLevel = 1,
	PerLicence = 3,
	PerSeries = 1,
	SeriesSize = 4,
	Max = 130,
	Nodes = {
		{ Key = "Alerts", Max = 5, Cost = 1, Licence = 1, Base = 3, Step = 3, Cap = 18 }, -- Alarm-Linien
		{ Key = "Watch", Max = 4, Cost = 1, Licence = 1, Base = 1, Step = 1, Cap = 5 }, -- Watchlists (je 12 Werte)
		{ Key = "Layouts", Max = 3, Cost = 1, Licence = 4, Base = 1, Step = 1, Cap = 4 }, -- Terminal-Layouts
		{ Key = "Monitors", Max = 3, Cost = 1, Licence = 1, Base = 0, Step = 1, Cap = 3 }, -- Live-Monitore im Tower
		{ Key = "Risk", Max = 2, Cost = 2, Licence = 3 }, -- Risiko-Büro
		{ Key = "BotLvl.Sparplan", Max = 4, Cost = 2, Licence = 3, Preset = "Sparplan" },
		{ Key = "BotLvl.Trend", Max = 4, Cost = 2, Licence = 4, Preset = "Trend" },
		{ Key = "BotLvl.Dividend", Max = 4, Cost = 2, Licence = 6, Preset = "Dividend" },
		{ Key = "BotLvl.Dip", Max = 4, Cost = 2, Licence = 7, Preset = "Dip" },
		{ Key = "Research", Max = 2, Cost = 3, Licence = 5, LevelLicence = { 5, 7 } }, -- Quartals-Tendenz 2 → 3 → 5 min
		{ Key = "MultiChart", Max = 1, Cost = 3, Licence = 7 }, -- Multi-Chart 2×2
	},
	ResearchLead = { 2, 3, 5 }, -- Minuten vor Quartalszahlen (Stufe 0/1/2)
	BotCapital = { 0.10, 0.15, 0.20, 0.25, 0.30 }, -- Kapitalanteil je Bot nach Bot-Stufe 0 … 4 (Anzeige)
}

-- ---------------------------------------------------------------------
-- 5) INDIKATOREN je Lizenz (§B7.5): ab welcher Lizenz-Nummer sichtbar (nie Robux)
-- ---------------------------------------------------------------------
Progression.Indicators = {
	SMA20 = 3,
	SMA50 = 3,
	SMA200 = 3,
	EMA9 = 3,
	EMA21 = 3,
	BB = 4,
	RSI = 5,
	MACD = 6,
	VWAP = 6,
	Stoch = 7,
	ATR = 7,
}

-- ---------------------------------------------------------------------
-- 6) RUF (§B9.4) – Teil des Trader-Faktors. Verluste kosten NIE Ruf. Admins können Ruf nicht geben.
-- ---------------------------------------------------------------------
Progression.Ruf = {
	DayBase = 1, -- je zählendem Börsentag (≥ 3 zählende Trades)
	DayPositive = 2, -- + wenn Rendite > 0
	DayStrong = 2, -- + weitere, wenn Rendite ≥ StrongReturn
	StrongReturn = 0.015,
	DailyCap = 20, -- Punkte je UTC-Tag (ohne Akademie/Prüfung)
	FirstLesson = 3, -- erste Akademie-Lektion (außerhalb des Deckels)
	Exam = 20, -- Lizenzprüfung (außerhalb des Deckels)
	Thresholds = { 10, 30, 60, 100, 150, 210, 280, 360, 450, 550 }, -- Ruf 1 … 10 (5 Sterne mit Halben)
	DecayPct = 0.08, -- je UTC-Tag ohne zählenden Börsentag
	DecayMaxDays = 30,
	Floors = { { Licence = 4, Level = 2 }, { Licence = 7, Level = 4 }, { Licence = 10, Level = 6 } },
	FactorStep = 0.03, -- Trader-Faktor × (1 + 0,03 × Ruf)
}

-- ---------------------------------------------------------------------
-- 7) TITEL (§B9.5) – Kopftitel (BillboardGui, Gold/Holo). Wealth = Vermögens-Titel (automatisch), Extra = Sonder-Titel.
--    Server-Toast bei jedem neuen Titel. Vermögen = CR + 0,5 × Lauf-Ausgaben + Firmenwert + Sammlung +
--    NAV_AKY × Bau-Kurs (geklemmt 9e15).
-- ---------------------------------------------------------------------
Progression.Titles = {
	Wealth = {
		{ Key = "Starter", Min = 0, Name = { de = "Starter", en = "Starter" } },
		{ Key = "TenK", Min = 1e4, Name = { de = "Zehntausender", en = "Ten-Thousander" } },
		{ Key = "HundredK", Min = 1e5, Name = { de = "Hunderttausender", en = "Hundred-Thousander" } },
		{ Key = "Millionaire", Min = 1e6, Name = { de = "Millionär", en = "Millionaire" }, Fanfare = true },
		{ Key = "MultiMillionaire", Min = 1e7, Name = { de = "Multi-Millionär", en = "Multi-Millionaire" } },
		{ Key = "HundredMillionaire", Min = 1e8, Name = { de = "Hundert-Millionär", en = "Hundred-Millionaire" } },
		{ Key = "Billionaire", Min = 1e9, Name = { de = "Milliardär", en = "Billionaire" }, Fanfare = true },
		{ Key = "MultiBillionaire", Min = 1e10, Name = { de = "Multi-Milliardär", en = "Multi-Billionaire" } },
		{ Key = "HundredBillionaire", Min = 1e11, Name = { de = "Hundert-Milliardär", en = "Hundred-Billionaire" } },
		{ Key = "Trillionaire", Min = 1e12, Name = { de = "Billionär", en = "Trillionaire" }, Fanfare = true },
		{ Key = "MultiTrillionaire", Min = 1e13, Name = { de = "Multi-Billionär", en = "Multi-Trillionaire" } },
		{ Key = "QuadBoss", Min = 1e15, Name = { de = "Billiarden-Boss", en = "Quadrillion Boss" }, Fanfare = true },
	},
	Extra = {
		{ Key = "Founder", Name = { de = "Gründer", en = "Founder" } }, -- Starter-Linie Schritt 20
		{ Key = "CEO", Name = { de = "CEO", en = "CEO" } }, -- 1. Börsengang / Vorstand Lifestyle 5
		{ Key = "SerialFounder", Name = { de = "Serien-Gründer", en = "Serial Founder" } }, -- 5 Börsengänge
		{ Key = "Tycoon", Name = { de = "Tycoon", en = "Tycoon" } }, -- 10 Börsengänge
		{ Key = "Mogul", Name = { de = "Mogul", en = "Mogul" } }, -- 20 Börsengänge
		{ Key = "Legend", Name = { de = "Börsen-Legende", en = "Exchange Legend" } }, -- Lizenz 10
		{ Key = "Constancy", Name = { de = "Konstanz", en = "Consistency" } },
		{ Key = "DiamondHead", Name = { de = "Diamantkopf", en = "Diamond Mind" } },
		{ Key = "CrisisProof", Name = { de = "Krisenfest", en = "Crisis-Proof" } },
		{ Key = "Graduate", Name = { de = "Akademie-Absolvent", en = "Academy Graduate" } },
		{ Key = "Favorite", Name = { de = "Publikumsliebling", en = "Crowd Favourite" } },
		{ Key = "OrbitArchitect", Name = { de = "Orbit-Architekt", en = "Orbit Architect" } },
		{ Key = "LeagueBronze", Name = { de = "Liga Bronze", en = "League Bronze" } },
		{ Key = "LeagueSilber", Name = { de = "Liga Silber", en = "League Silver" } },
		{ Key = "LeagueGold", Name = { de = "Liga Gold", en = "League Gold" } },
		{ Key = "LeagueDiamant", Name = { de = "Liga Diamant", en = "League Diamond" } },
		{ Key = "S1Pioneer", Name = { de = "Skyline-Pionier S1", en = "Skyline Pioneer S1" } }, -- Pass gratis T50
		{ Key = "S1Elite", Name = { de = "Skyline-Elite S1", en = "Skyline Elite S1" } }, -- Pass Premium T50
	},
	ShowRange = 80, -- Kopftitel sichtbar bis (Studs)
}
Progression.WealthCollectionPct = 0.5 -- Sammlungswert im Vermögen = 50 % der Kaufpreise (Autos, Uhren, Deko)

-- ---------------------------------------------------------------------
-- 8) BÖRSENGANG & VORSTAND (§B9.6) – Sterne nur aus Lauf-Ausgaben, Perks wirken NUR auf Turm/Lifestyle.
-- ---------------------------------------------------------------------
Progression.Prestige = {
	MinFloor = 25, -- Etage 25 fertig
	PreviewStage = 7, -- Vorschau ab Stufe 7
	StarsK = 4,
	StarsDiv = 1e6,
	StarsMin = 1e7, -- unter 1e7 Lauf-Ausgaben: 0 ★
	PermStep = 0.25, -- +0,25 Perm je Börsengang (max. 20 gezählt, rechnet TowerService)
	FirmPct = 0.5, -- Firmenwert += 0,5 × Lauf-Ausgaben
	StartCredits = 0, -- Start-CR nach dem Börsengang
	TokenSeconds = 60, -- Vorschau-Token gültig
	TickerMin = 3,
	TickerMax = 4,
	TickerKeep = 50, -- so viele eigene Ticker bleiben im Spielstand
	RespecCost = 1, -- Umverteilen kostet 1 ★ …
	RespecFreeAt = 3, -- … bei Börsengang 3 einmal gratis
	EstimateStage = 7, -- Vorschau: "Stufe 1–7 in ca. … wieder erreicht" = erste Etage dieser Stufe (Config.Tower.Stages)
	EstimateFloors = 18, -- Rückfall, falls Config.Tower.Stages fehlt (Stufe 7 beginnt bei Etage 18, §B4.2)
	EstimateFactor = 1.2, -- grobe Zeit: Bauzeit-Summe (TowerMath) × Faktor für das Ansparen (≈ 15 min, §B9.6)
	Perks = {
		{ Key = "Wachstum", Max = 10, Step = 0.10 }, -- +0,10 Perm je Stufe
		{ Key = "Blitzstart", Max = 3, Floors = { 4, 8, 12 } }, -- Start mit fertigen Etagen
		{ Key = "Bau", Max = 8, Step = 0.05 }, -- −5 % Kosten je Stufe
		{ Key = "Tempo", Max = 5, Step = 0.10 }, -- −10 % Bauzeit je Stufe
		{ Key = "Tresor", Max = 8, Hours = 1, RatePp = 5 }, -- +1 h Offline-Deckel, +5 Pp Offline-Rate
		{ Key = "Lifestyle", Max = 5, Step = 0.05, Title = "CEO" }, -- −5 % Auto/Uhr/Deko; Stufe 5: Uhr + Titel
	},
	TitleSteps = {
		{ Ipos = 1, Title = "CEO" },
		{ Ipos = 5, Title = "SerialFounder" },
		{ Ipos = 10, Title = "Tycoon" },
		{ Ipos = 20, Title = "Mogul" },
	},
	Crowns = {
		{ Ipos = 1, Key = "Silver" },
		{ Ipos = 3, Key = "Gold" },
		{ Ipos = 5, Key = "Platinum" },
		{ Ipos = 10, Key = "Holo" },
		{ Ipos = 20, Key = "Orbit" },
	},
	WallHours = 24, -- Ticker 24 h auf der Plaza-IPO-Wand, dauerhaft in der "Hall of IPOs"
	HallKeep = 60, -- Einträge in der Hall of IPOs (DataStore, alle Server)
}
-- Ticker-Sperrliste (große echte Kürzel/Indizes, Marken und Wörter) – zusätzlich TextService-Filter + Sperre der
-- eigenen Börsen-Kürzel (Config.Companies). Groß geschrieben, 3–4 Buchstaben.
Progression.TickerBlock = {
	"NFT",
	"BTC",
	"ETH",
	"XRP",
	"SOL",
	"DOGE",
	"USDT",
	"USDC",
	"BNB",
	"ADA",
	"COIN",
	"CASH",
	"BANK",
	"AAPL",
	"MSFT",
	"GOOG",
	"AMZN",
	"META",
	"TSLA",
	"NVDA",
	"NFLX",
	"INTC",
	"ORCL",
	"CSCO",
	"ADBE",
	"PYPL",
	"UBER",
	"SHOP",
	"SPOT",
	"BABA",
	"SONY",
	"NKE",
	"PEP",
	"MCD",
	"DIS",
	"IBM",
	"AMD",
	"SAP",
	"BMW",
	"VOW",
	"SIE",
	"ALV",
	"DTE",
	"BAS",
	"BAYN",
	"ADS",
	"MBG",
	"DBK",
	"LHA",
	"RBLX",
	"GME",
	"AMC",
	"PLTR",
	"DAX",
	"SPX",
	"SPY",
	"QQQ",
	"DOW",
	"DJI",
	"NDX",
	"FTSE",
	"CAC",
	"NIKK",
	"MSCI",
	"ETF",
	"IPO",
	"FED",
	"ECB",
	"EZB",
	"SEC",
	"BAFI",
	"USA",
	"EUR",
	"USD",
	"GBP",
	"JPY",
	"CHF",
	"AKY",
	"AKYX",
	"AKYT",
	"NOVA",
	"ACAD",
	"AKX",
	"PRO",
	"APP",
	"WEB",
	"WWW",
	"COM",
	"NET",
	"ORG",
	"URL",
	"GOD",
	"SEX",
	"XXX",
	"KKK",
	"NAZI",
	"ISIS",
	"ADMN",
	"MOD",
	"MODS",
	"DEV",
	"OWNR",
	"HACK",
	"SCAM",
	"FREE",
	"ROBX",
	"RBX",
	"BUX",
	"GAMB",
	"BETS",
	"LUCK",
	"SLOT",
	"DICE",
	"CASI",
	"POKR",
	"LOTT",
	"MOON",
	"PUMP",
	"DUMP",
}

-- ---------------------------------------------------------------------
-- 9) AKADEMIE (§B2, §B9.1) – 16 Lektionen in 4 Serien à 4. Texte in Lang/Progress:
--    "prog.les.<Id>.t" (Titel), ".c1" … (Karten), ".q1" … (Fragen), ".q1.a1" … (Antworten).
--    Cards = Anzahl Karten (3–5), Quiz = Anzahl Antworten je Frage. Die richtigen Antworten prüft NUR der Server.
--    Lektion des Tages: (UTC-Tag % 16) + 1 (Hinweis in der Akademie).
-- ---------------------------------------------------------------------
Progression.Academy = {
	Lessons = {
		{ Id = "L01", Series = 1, Cards = 3, Quiz = { 3, 3 }, Seconds = 30 }, -- Was ist eine Aktie?
		{ Id = "L02", Series = 1, Cards = 4, Quiz = { 3, 3, 3 }, Seconds = 45 }, -- Kurs, Spread, Gebühr
		{ Id = "L03", Series = 1, Cards = 4, Quiz = { 3, 3, 3 }, Seconds = 45 }, -- Schutz-Paar
		{ Id = "L04", Series = 1, Cards = 4, Quiz = { 3, 3, 3 }, Seconds = 45 }, -- Verteilen
		{ Id = "L05", Series = 2, Cards = 4, Quiz = { 3, 3, 3 }, Seconds = 45 }, -- Eilmeldung & Lesefenster
		{ Id = "L06", Series = 2, Cards = 4, Quiz = { 3, 3, 3 }, Seconds = 45 }, -- Gerüchte & Quellen-Sterne
		{ Id = "L07", Series = 2, Cards = 4, Quiz = { 3, 3, 3 }, Seconds = 45 }, -- „Wie erwartet“
		{ Id = "L08", Series = 2, Cards = 4, Quiz = { 3, 3, 3 }, Seconds = 45 }, -- Makro-Termine
		{ Id = "L09", Series = 3, Cards = 4, Quiz = { 3, 3, 3 }, Seconds = 45 }, -- Kerzen lesen
		{ Id = "L10", Series = 3, Cards = 4, Quiz = { 3, 3, 3 }, Seconds = 45 }, -- SMA & EMA
		{ Id = "L11", Series = 3, Cards = 5, Quiz = { 3, 3, 3 }, Seconds = 60 }, -- Quartalszahlen & Analysten
		{ Id = "L12", Series = 3, Cards = 4, Quiz = { 3, 3, 3 }, Seconds = 45 }, -- Dividenden
		{ Id = "L13", Series = 4, Cards = 4, Quiz = { 3, 3, 3 }, Seconds = 45 }, -- Crash & Rallye
		{ Id = "L14", Series = 4, Cards = 4, Quiz = { 3, 3, 3 }, Seconds = 45 }, -- Strategie-Bots
		{ Id = "L15", Series = 4, Cards = 5, Quiz = { 3, 3, 3 }, Seconds = 60 }, -- Skill-Score & Drawdown
		{ Id = "L16", Series = 4, Cards = 5, Quiz = { 3, 3, 3 }, Seconds = 60 }, -- Basis, Bau-Kurs, Börsengang
	},
	Series = 4,
	PassRatio = 0.5, -- Lektion gilt als geschafft ab 50 % richtiger Antworten
	MinCardSeconds = 2, -- Server: so viele Sekunden je Karte mindestens zwischen zwei Abgaben derselben Lektion
}

-- ---------------------------------------------------------------------
-- 10) QUESTS (§B9.7) – jede Art braucht einen RewardService.Track-Aufrufer (SelfTest prüft das über "Tracker").
--     Cat: "Trade" | "Academy" (+ Trader-XP) · "Tower" | "World" | "Social" (nur CR + Saison-XP).
--     Vorlagen: Kind, Goal, Tier (1/2/3 = 10/15/20 min Dauer-Einkommen), Min (ctx-Mindestwerte), Distinct (ctx-Feld,
--     verschiedene Werte zählen), Text (Lang-Schlüssel, sonst "prog.qk.<Kind>"). Drive-Ziele in Studs (1 km = 1000).
-- ---------------------------------------------------------------------
Progression.QuestKinds = {
	{ Key = "Collect", Cat = "Tower", Tracker = "TowerService" },
	{ Key = "BuildFloor", Cat = "Tower", Tracker = "TowerService" },
	{ Key = "RoomLevel", Cat = "Tower", Tracker = "TowerService" },
	{ Key = "Hire", Cat = "Tower", Tracker = "TowerService" },
	{ Key = "Efficiency", Cat = "Tower", Tracker = "TowerService" },
	{ Key = "Transfer", Cat = "Tower", Tracker = "TowerService" },
	{ Key = "TradeProtected", Cat = "Trade", Tracker = "ProgressionService" },
	{ Key = "TradeProfit", Cat = "Trade", Tracker = "ProgressionService" },
	{ Key = "PositiveDay", Cat = "Trade", Tracker = "ProgressionService" },
	{ Key = "ReadNews", Cat = "Trade", Tracker = "ProgressionService" },
	{ Key = "NewSector", Cat = "Trade", Tracker = "ProgressionService" },
	{ Key = "HoldThroughBell", Cat = "Trade", Tracker = "ProgressionService" },
	{ Key = "EarningsTrade", Cat = "Trade", Tracker = "ProgressionService" },
	{ Key = "Lesson", Cat = "Academy", Tracker = "ProgressionService" },
	{ Key = "Drive", Cat = "World", Tracker = "VehicleService" },
	{ Key = "VisitTower", Cat = "Social", Tracker = "PlotService" },
	{ Key = "GiveRespekt", Cat = "Social", Tracker = "CommunityService" },
	{ Key = "HelpBuild", Cat = "Social", Tracker = "TowerService" },
	{ Key = "Pickup", Cat = "World", Tracker = "EventService" },
	{ Key = "BearOrbs", Cat = "World", Tracker = "EventService" },
	{ Key = "Bell", Cat = "World", Tracker = "ProgressionService" },
}

Progression.Quests = {
	DailyCount = 3,
	WeeklyCount = 3,
	MinTradeDaily = 1, -- mindestens 1 Handels-/Akademie-Quest je Tag
	RerollsPerDay = 1, -- 1 Gratis-Neuwählen je Tag (kein Kauf)
	TierMinutes = { 10, 15, 20 }, -- CR = Minuten Dauer-Einkommen (ohne Zeitlich) …
	DailyMinCredits = 2000, -- … mindestens
	WeeklyHours = 2,
	WeeklyMinCredits = 20000,
	DailySeasonXp = 150,
	WeeklySeasonXp = 600,
	DailyPool = 30,
	WeeklyPool = 12,
	Starter = 20,
	Daily = {
		{ Id = "D01", Kind = "Collect", Goal = 5, Tier = 1 },
		{ Id = "D02", Kind = "Collect", Goal = 15, Tier = 2 },
		{ Id = "D03", Kind = "BuildFloor", Goal = 1, Tier = 1 },
		{ Id = "D04", Kind = "BuildFloor", Goal = 3, Tier = 3 },
		{ Id = "D05", Kind = "RoomLevel", Goal = 2, Tier = 1 },
		{ Id = "D06", Kind = "RoomLevel", Goal = 5, Tier = 2 },
		{ Id = "D07", Kind = "Hire", Goal = 2, Tier = 2 },
		{ Id = "D08", Kind = "Efficiency", Goal = 1, Tier = 2 },
		{ Id = "D09", Kind = "Transfer", Goal = 1, Tier = 2 },
		{ Id = "D10", Kind = "TradeProtected", Goal = 3, Tier = 2 },
		{ Id = "D11", Kind = "TradeProfit", Goal = 1, Tier = 1 },
		{ Id = "D12", Kind = "TradeProfit", Goal = 3, Tier = 3 },
		{ Id = "D13", Kind = "PositiveDay", Goal = 1, Tier = 2 },
		{
			Id = "D14",
			Kind = "PositiveDay",
			Goal = 1,
			Tier = 3,
			Min = { Return = 0.01 },
			Text = "prog.qt.PositiveDay1",
		},
		{ Id = "D15", Kind = "ReadNews", Goal = 5, Tier = 1 },
		{ Id = "D16", Kind = "ReadNews", Goal = 15, Tier = 2 },
		{ Id = "D17", Kind = "NewSector", Goal = 1, Tier = 1 },
		{ Id = "D18", Kind = "NewSector", Goal = 3, Tier = 3, Distinct = "Sector" },
		{ Id = "D19", Kind = "HoldThroughBell", Goal = 1, Tier = 1 },
		{ Id = "D20", Kind = "EarningsTrade", Goal = 1, Tier = 2 },
		{ Id = "D21", Kind = "Lesson", Goal = 1, Tier = 1 },
		{ Id = "D22", Kind = "Lesson", Goal = 2, Tier = 2 },
		{ Id = "D23", Kind = "Drive", Goal = 2000, Tier = 1 },
		{ Id = "D24", Kind = "Drive", Goal = 6000, Tier = 2 },
		{ Id = "D25", Kind = "VisitTower", Goal = 2, Tier = 1, Distinct = "Owner" },
		{ Id = "D26", Kind = "GiveRespekt", Goal = 2, Tier = 2 },
		{ Id = "D27", Kind = "HelpBuild", Goal = 1, Tier = 2 },
		{ Id = "D28", Kind = "Pickup", Goal = 10, Tier = 1 },
		{ Id = "D29", Kind = "BearOrbs", Goal = 5, Tier = 2 },
		{ Id = "D30", Kind = "Bell", Goal = 1, Tier = 2 },
	},
	Weekly = {
		{ Id = "W01", Kind = "Collect", Goal = 100 },
		{ Id = "W02", Kind = "BuildFloor", Goal = 10 },
		{ Id = "W03", Kind = "TradeProfit", Goal = 15 },
		{ Id = "W04", Kind = "PositiveDay", Goal = 10 },
		{ Id = "W05", Kind = "ReadNews", Goal = 60 },
		{ Id = "W06", Kind = "NewSector", Goal = 6, Distinct = "Sector" },
		{ Id = "W07", Kind = "Lesson", Goal = 5 },
		{ Id = "W08", Kind = "Drive", Goal = 25000 },
		{ Id = "W09", Kind = "GiveRespekt", Goal = 10 },
		{ Id = "W10", Kind = "HelpBuild", Goal = 5 },
		{ Id = "W11", Kind = "Pickup", Goal = 60 },
		{ Id = "W12", Kind = "TradeProtected", Goal = 20 },
	},
	-- Starter-Linie „Vom Azubi zum Millionär“: Check = Zustand prüfen (Floors, Eff, Licence, Lessons, RoomKinds,
	-- BotOn, LeagueDays, Wealth), sonst Track-Art. Text: "prog.st.<Id>" (Aufgabe) + "prog.st.<Id>.tiko" (Tiko-Satz).
	StarterLine = {
		{ Id = "S01", Check = "Floors", Goal = 3, Credits = 500 },
		{ Id = "S02", Kind = "Collect", Goal = 3, Credits = 800 },
		{ Id = "S03", Kind = "TradeProfit", Goal = 1, Credits = 1500 },
		{ Id = "S04", Check = "Floors", Goal = 7, Credits = 2500 },
		{ Id = "S05", Kind = "Drive", Goal = 1000, Credits = 2000 },
		{ Id = "S06", Check = "Lessons", Goal = 1, Credits = 2500 },
		{ Id = "S07", Kind = "Hire", Goal = 2, Credits = 3000 },
		{ Id = "S08", Kind = "RoomLevel", Goal = 3, Credits = 4000 },
		{ Id = "S09", Kind = "Transfer", Goal = 1, Credits = 5000 },
		{ Id = "S10", Check = "Eff", Goal = 1, Credits = 6000 },
		{ Id = "S11", Check = "Licence", Goal = 2, Credits = 7500 },
		{ Id = "S12", Check = "Floors", Goal = 10, Credits = 10000 },
		{ Id = "S13", Kind = "TradeProtected", Goal = 3, Credits = 10000 },
		{ Id = "S14", Check = "RoomKinds", Goal = 3, Credits = 12000 },
		{ Id = "S15", Check = "Lessons", Goal = 4, Credits = 15000 },
		{ Id = "S16", Check = "BotOn", Goal = 1, Credits = 20000 },
		{ Id = "S17", Check = "Licence", Goal = 3, Credits = 20000 },
		{ Id = "S18", Kind = "VisitTower", Goal = 2, Credits = 25000, Distinct = "Owner" },
		{ Id = "S19", Check = "LeagueDays", Goal = 6, Credits = 30000 },
		{ Id = "S20", Check = "Wealth", Goal = 1000000, Credits = 50000, Title = "Founder" },
	},
	-- Rückkehrer (§B9.9, ≥ 14 Tage weg): Aufhol-Quest
	Comeback = { Id = "C01", Kind = "BuildFloor", Goal = 3, Minutes = 60, MinCredits = 5000 },
}

-- ---------------------------------------------------------------------
-- 11) ERFOLGE (§B9.8) – 60 in 6 Kategorien. Stat = Zähler/Höchstwert (Prog.AchProgress), Goal = Schwelle.
--     Belohnung: Minutes = Minuten Dauer-Einkommen (mind. Min CR), Title, Decor, Cosmetic. Keine „Glücks“-Wörter.
-- ---------------------------------------------------------------------
local function ach(
	id: string,
	cat: string,
	stat: string,
	goal: number,
	de: string,
	en: string,
	reward: { [string]: any }?
)
	return { Id = id, Cat = cat, Stat = stat, Goal = goal, Name = { de = de, en = en }, Reward = reward or {} }
end

Progression.AchievementCats = { "Trading", "Tower", "Academy", "Collection", "Social", "Events" }
-- stylua: ignore start
Progression.Achievements = {
	-- Trading (14)
	ach("T01", "Trading", "Trades", 1, "Erster Trade", "First Trade", { Minutes = 10, Min = 1000 }),
	ach("T02", "Trading", "ProfitTrades", 1, "Erster Gewinn", "First Profit", { Minutes = 15, Min = 1500 }),
	ach("T03", "Trading", "Trades", 25, "Händler", "Dealer", { Minutes = 30, Min = 3000 }),
	ach("T04", "Trading", "Trades", 250, "Profi-Händler", "Pro Dealer", { Minutes = 60, Min = 10000 }),
	ach("T05", "Trading", "PosStreak", 10, "Konstanz", "Consistency", { Minutes = 90, Min = 20000, Title = "Constancy" }),
	ach("T06", "Trading", "ProtectedTrades", 10, "Gut geschützt", "Well Protected", { Minutes = 30, Min = 3000 }),
	ach("T07", "Trading", "ReadWell", 1, "Gut gelesen", "Well Read", { Minutes = 15, Min = 1500 }),
	ach("T08", "Trading", "ReadWell", 10, "Nachrichten-Profi", "News Pro", { Minutes = 45, Min = 6000 }),
	ach("T09", "Trading", "ReadWell", 50, "Diamantkopf", "Diamond Mind", { Minutes = 120, Min = 40000, Title = "DiamondHead" }),
	ach("T10", "Trading", "PositiveDays", 1, "Grüner Tag", "Green Day", { Minutes = 20, Min = 2000 }),
	ach("T11", "Trading", "PositiveDays", 25, "Grüner Monat", "Green Streak", { Minutes = 90, Min = 20000 }),
	ach("T12", "Trading", "CrashSurvived", 1, "Krisenfest", "Crisis-Proof", { Minutes = 90, Min = 15000, Title = "CrisisProof" }),
	ach("T13", "Trading", "Sectors", 6, "Breit gestreut", "Well Spread", { Minutes = 60, Min = 10000 }),
	ach("T14", "Trading", "EarningsTrades", 5, "Quartals-Kenner", "Earnings Expert", { Minutes = 60, Min = 10000 }),
	-- Tower (14)
	ach("B01", "Tower", "Floors", 1, "Erste Etage", "First Floor", { Minutes = 5, Min = 500 }),
	ach("B02", "Tower", "Stage", 3, "Loft-Besitzer", "Loft Owner", { Minutes = 15, Min = 1500 }),
	ach("B03", "Tower", "Stage", 5, "Glas-Office", "Glass Office", { Minutes = 30, Min = 5000 }),
	ach("B04", "Tower", "Stage", 7, "Hochhaus", "High-Rise", { Minutes = 45, Min = 20000 }),
	ach("B05", "Tower", "Stage", 8, "Skyline-Pionier", "Skyline Pioneer", { Minutes = 60, Min = 50000, Decor = "StatueBull" }),
	ach("B06", "Tower", "Stage", 10, "Mega-Tower", "Mega Tower", { Minutes = 90, Min = 100000 }),
	ach("B07", "Tower", "Stage", 12, "Orbit-Spire", "Orbit Spire", { Minutes = 120, Min = 500000, Title = "OrbitArchitect" }),
	ach("B08", "Tower", "Collect", 100, "Kassierer", "Cashier", { Minutes = 30, Min = 3000 }),
	ach("B09", "Tower", "Eff", 10, "Effizienz-Experte", "Efficiency Expert", { Minutes = 60, Min = 20000 }),
	ach("B10", "Tower", "Hired", 25, "Personalchef", "Head of Staff", { Minutes = 45, Min = 10000 }),
	ach("B11", "Tower", "RoomLevels", 50, "Raumgestalter", "Space Designer", { Minutes = 45, Min = 10000 }),
	ach("B12", "Tower", "Transfers", 25, "Brückenbauer", "Bridge Builder", { Minutes = 60, Min = 15000 }),
	ach("B13", "Tower", "Ipos", 1, "Börsengang", "Public Listing", { Minutes = 60, Min = 50000 }),
	ach("B14", "Tower", "Ipos", 5, "Serien-Gründer", "Serial Founder", { Minutes = 120, Min = 200000 }),
	-- Akademie & Lizenz (10)
	ach("A01", "Academy", "Lessons", 1, "Erste Lektion", "First Lesson", { Minutes = 10, Min = 1000 }),
	ach("A02", "Academy", "Lessons", 8, "Fleißig", "Diligent", { Minutes = 45, Min = 8000 }),
	ach("A03", "Academy", "Lessons", 16, "Akademie-Absolvent", "Academy Graduate", { Minutes = 90, Min = 20000, Title = "Graduate" }),
	ach("A04", "Academy", "Perfect", 1, "Perfekt", "Perfect Score", { Minutes = 15, Min = 1500 }),
	ach("A05", "Academy", "Perfect", 16, "Musterschüler", "Model Student", { Minutes = 120, Min = 30000 }),
	ach("A06", "Academy", "Licence", 2, "Azubi II", "Apprentice II", { Minutes = 15, Min = 2000 }),
	ach("A07", "Academy", "Licence", 4, "Trader-Lizenz", "Trader Licence", { Minutes = 60, Min = 20000 }),
	ach("A08", "Academy", "Licence", 7, "Fondsmanager-Lizenz", "Fund Manager Licence", { Minutes = 120, Min = 200000 }),
	ach("A09", "Academy", "Licence", 10, "Börsen-Legende", "Exchange Legend", { Minutes = 180, Min = 1000000, Title = "Legend" }),
	ach("A10", "Academy", "KHSpent", 50, "Know-how-Meister", "Know-how Master", { Minutes = 90, Min = 50000 }),
	-- Sammlung (10)
	ach("C01", "Collection", "AlbumCards", 10, "Album-Start", "Album Starter", { Minutes = 20, Min = 3000 }),
	ach("C02", "Collection", "AlbumCards", 25, "Sammler", "Collector", { Minutes = 45, Min = 10000 }),
	ach("C03", "Collection", "AlbumCards", 43, "Komplett", "Complete", { Minutes = 120, Min = 50000, Cosmetic = "NeonCyber" }),
	ach("C04", "Collection", "AlbumSets", 1, "Sektor-Satz", "Sector Set", { Minutes = 30, Min = 5000 }),
	ach("C05", "Collection", "AlbumSets", 6, "Alle Sektoren", "Every Sector", { Minutes = 120, Min = 50000, Cosmetic = "MarbleWhite" }),
	ach("C06", "Collection", "Cars", 3, "Autofan", "Car Fan", { Minutes = 30, Min = 5000 }),
	ach("C07", "Collection", "Cars", 8, "Fuhrpark", "Fleet Owner", { Minutes = 120, Min = 100000 }),
	ach("C08", "Collection", "Watches", 3, "Uhrensammler", "Watch Collector", { Minutes = 60, Min = 20000 }),
	ach("C09", "Collection", "DecorKinds", 10, "Einrichter", "Interior Designer", { Minutes = 45, Min = 10000 }),
	ach("C10", "Collection", "Drive", 50000, "Vielfahrer", "Road Warrior", { Minutes = 60, Min = 10000 }),
	-- Sozial (6)
	ach("S01", "Social", "Respekt", 1, "Respekt!", "Respect!", { Minutes = 10, Min = 1000 }),
	ach("S02", "Social", "RespektGot", 10, "Gastgeber", "Host", { Minutes = 30, Min = 5000 }),
	ach("S03", "Social", "RespektGot", 100, "Beliebt", "Popular", { Minutes = 120, Min = 50000, Title = "Favorite" }),
	ach("S04", "Social", "HelpBuild", 10, "Bau-Helfer", "Build Helper", { Minutes = 45, Min = 8000 }),
	ach("S05", "Social", "Visits", 10, "Tower-Tourist", "Tower Tourist", { Minutes = 30, Min = 5000 }),
	ach("S06", "Social", "Invites", 1, "Netzwerker", "Networker", { Minutes = 60, Min = 10000 }),
	-- Events (6)
	ach("E01", "Events", "Bell", 1, "Glocken-Moment", "Bell Moment", { Minutes = 15, Min = 2000 }),
	ach("E02", "Events", "Bell", 25, "Glockenfreund", "Bell Regular", { Minutes = 60, Min = 15000 }),
	ach("E03", "Events", "Pickups", 100, "Bündel-Sammler", "Bundle Collector", { Minutes = 45, Min = 8000 }),
	ach("E04", "Events", "BearOrbs", 50, "Bären-Bändiger", "Bear Whisperer", { Minutes = 60, Min = 10000 }),
	ach("E05", "Events", "LeagueTier", 1, "Liga-Einsteiger", "League Rookie", { Minutes = 60, Min = 10000 }),
	ach("E06", "Events", "LeagueTier", 3, "Liga-Gold", "League Gold", { Minutes = 180, Min = 100000 }),
}
-- stylua: ignore end
-- Zähler (Summe) vs. Höchstwert (aus dem Spielstand neu berechnet) – ProgressionService
Progression.AchievementMaxStats = {
	PosStreak = true,
	Sectors = true,
	Floors = true,
	Stage = true,
	Eff = true,
	Ipos = true,
	Lessons = true,
	Perfect = true,
	Licence = true,
	KHSpent = true,
	AlbumCards = true,
	AlbumSets = true,
	Cars = true,
	Watches = true,
	DecorKinds = true,
	LeagueTier = true,
}

-- ---------------------------------------------------------------------
-- 12) ROBLOX-BADGES (§B9.8) – Id = 0 = aus (Badge-Anlage kann Robux kosten, ANLEITUNG). Rule: Stat ≥ Min.
--     Wird ein Id später eingetragen, vergibt der Server das Badge beim nächsten Beitritt rückwirkend.
-- ---------------------------------------------------------------------
Progression.Badges = {
	{ Key = "Welcome", Id = 0, Stat = "Joined", Min = 1, Name = { de = "Willkommen", en = "Welcome" } },
	{ Key = "FirstFloor", Id = 0, Stat = "Floors", Min = 1, Name = { de = "Erste Etage", en = "First Floor" } },
	{
		Key = "FirstProfit",
		Id = 0,
		Stat = "ProfitTrades",
		Min = 1,
		Name = { de = "Erster Gewinn", en = "First Profit" },
	},
	{ Key = "Loft", Id = 0, Stat = "Stage", Min = 3, Name = { de = "Loft", en = "Loft" } },
	{ Key = "Skyscraper", Id = 0, Stat = "Stage", Min = 8, Name = { de = "Wolkenkratzer", en = "Skyscraper" } },
	{ Key = "OrbitSpire", Id = 0, Stat = "Stage", Min = 12, Name = { de = "Orbit-Spire", en = "Orbit Spire" } },
	{ Key = "FirstIpo", Id = 0, Stat = "Ipos", Min = 1, Name = { de = "Erster Börsengang", en = "First Listing" } },
	{
		Key = "TraderLicence",
		Id = 0,
		Stat = "Licence",
		Min = 4,
		Name = { de = "Trader-Lizenz", en = "Trader Licence" },
	},
	{
		Key = "FondsLicence",
		Id = 0,
		Stat = "Licence",
		Min = 7,
		Name = { de = "Fondsmanager-Lizenz", en = "Fund Licence" },
	},
	{ Key = "Legend", Id = 0, Stat = "Licence", Min = 10, Name = { de = "Börsen-Legende", en = "Exchange Legend" } },
	{ Key = "Millionaire", Id = 0, Stat = "Wealth", Min = 1e6, Name = { de = "Millionär", en = "Millionaire" } },
	{ Key = "Billionaire", Id = 0, Stat = "Wealth", Min = 1e9, Name = { de = "Milliardär", en = "Billionaire" } },
	{
		Key = "CrashSurvived",
		Id = 0,
		Stat = "CrashSurvived",
		Min = 1,
		Name = { de = "Crash überstanden", en = "Crash Survived" },
	},
	{ Key = "LeagueGold", Id = 0, Stat = "LeagueTier", Min = 3, Name = { de = "Liga Gold", en = "League Gold" } },
	{ Key = "Streak7", Id = 0, Stat = "LoginStreak", Min = 7, Name = { de = "7-Tage-Serie", en = "7-Day Streak" } },
}

-- ---------------------------------------------------------------------
-- 13) FIRMEN-ALBUM (§B9.8) – einmal ≥ 1 Anteil jeder Firma/jedes ETFs besitzen (43 Karten) + IPO-Seite je Saison.
--     Je vollständigem Sektor-Satz (6 Firmen) +0,02 Perm (max. +0,12, rechnet TowerService über AlbumSets).
-- ---------------------------------------------------------------------
Progression.Album = {
	SectorBonus = 0.02,
	MaxSets = 6,
	Cards = {
		1,
		2,
		3,
		4,
		5,
		6,
		7,
		8,
		9,
		10,
		11,
		12,
		13,
		14,
		15,
		16,
		17,
		18,
		19,
		20,
		21,
		22,
		23,
		24,
		25,
		26,
		27,
		28,
		29,
		30,
		31,
		32,
		33,
		34,
		35,
		36,
		40,
		41,
		42,
		43,
		44,
		45,
		46,
	},
	IpoFrom = 100, -- IPO-Seite: Ids 100–139 (je Saison)
	IpoTo = 139,
}

-- ---------------------------------------------------------------------
-- 14) TUTORIAL (§B2) – Funnel 1–18 (MetricsService.Funnel). Xp = Tutorial-Trader-XP je Schritt (Summe 300, Schritte
--     6–14, einmalig). Überspringen (SkipStep) gibt dieselben Belohnungen. Kein Robux-Angebot in Sitzung 1.
-- ---------------------------------------------------------------------
Progression.Tutorial = {
	Steps = 17, -- Client-Skript endet mit Schritt 17 ("TenMinutes"); 18 = Rückkehr an Tag 2
	SkipStep = 99,
	Xp = { [6] = 60, [7] = 30, [8] = 30, [9] = 30, [10] = 30, [11] = 40, [12] = 30, [13] = 20, [14] = 30 },
	TenMinutesSeconds = 570, -- Funnel 17, wenn die erste Sitzung so lange dauert
	FlyInSeconds = 4,
	PracticeInst = 250, -- ACAD
	SuggestInst = 40, -- AKX36 (Einsteiger-Empfehlung)
	RoomChoices = { "Office", "Desk", "Cafe" }, -- Abteilungs-Wahl auf Etage 2 (Trading-Desk empfohlen)
	Recommended = "Desk",
	FirstStaff = "Intern",
	StageFloors = 5, -- Etagen 2–5 verkettet (Loft-Morph bei Etage 4)
	ExchangeRadius = 70, -- Ankunft am Börsensaal (Studs um Config.City.Zones.Exchange.Center)
	FunnelNames = {
		[1] = "Joined",
		[2] = "SplashDone",
		[3] = "Spawned",
		[4] = "Floor1",
		[5] = "FirstCollect",
		[6] = "TutorialTrade",
		[7] = "FirstTransfer",
		[8] = "Stage3",
		[9] = "FirstStaff",
		[10] = "FirstAutomation",
		[11] = "FirstLiveTrade",
		[12] = "CarDriven",
		[13] = "Lesson1",
		[14] = "LicenceAzubi2",
		[15] = "FirstMultiplier",
		[16] = "FavoritePrompted",
		[17] = "TenMinutes",
		[18] = "Day2Return",
	},
}

-- ---------------------------------------------------------------------
-- 15) SOZIAL (§B11.3–§B11.5, §B11.9) – funktioniert komplett ohne Chat
-- ---------------------------------------------------------------------
Progression.Social = {
	RespektHours = 1, -- Besitzer +0,01 Perm für 1 h …
	LoungeHours = 2, -- … mit Lounge 2 h
	RespektMax = 20, -- höchstens 20 gleichzeitig
	RespektRange = 90, -- Geber muss so nah an der Plot-Mitte des Towers sein (Studs)
	RespektSeasonXpMax = 5, -- Besucher +25 Saison-XP höchstens 5× je Tag
	SessionMinStudio = 30, -- Studio: Mindest-Sitzung für Respekt (live: Config.Security.SessionMinForSocial = 600 s)
	SkyShowKind = "SkyShow", -- EventService-Art: Respekt zählt doppelt
	Reactions = {
		{ Key = "Like", Emoji = "👍" },
		{ Key = "Rocket", Emoji = "🚀" },
		{ Key = "Chart", Emoji = "📈" },
		{ Key = "Clap", Emoji = "👏" },
		{ Key = "Bell", Emoji = "🔔" },
	},
	Emotes = { "wave", "cheer", "point", "dance" },
	ReactSeconds = 3,
	ShowSeconds = 6,
	ShowRange = 60,
	FriendMax = 4,
	InviteFromStage = 3, -- Einladen-Knopf ab Stufe 3
	Referral = { Floor = 10, PlayMinutes = 10, BoostSeconds = 1800, Neon = "Partner", WeeklyMax = 10 },
	GroupId = 0, -- Gruppe "AKYTEX Games" (0 = aus): Community-Krone + Namensschild-Rahmen, kein Einkommen
	NotifyRepromptDays = 30, -- Opt-in-Abfrage höchstens alle 30 Tage (Roblox begrenzt zusätzlich)
}

-- ---------------------------------------------------------------------
-- 16) BESTENLISTEN (§B11.1) – OrderedDataStores Config.Tech.BoardPrefix .. Store (.."_v1" bzw. .."_<IsoWeek>"),
--     Wert ganzzahlig 0 … 9e15. Schreiben ≥ 300 s Abstand + beim Verlassen, nur bei Änderung, nie NoSave/UserId ≤ 0.
--     Lesen Top 100 (Anzeige 10) alle 300 s. Kind: Log = floor(log10(1 + v) × 1e12) · League · Return · Int.
-- ---------------------------------------------------------------------
Progression.Boards = {
	List = {
		{ Key = "Wealth", Store = "Wealth", Weekly = false, Kind = "Log", Title = "VERMÖGEN · NET WORTH" },
		{ Key = "League", Store = "League", Weekly = true, Kind = "League", Title = "WOCHEN-LIGA · WEEKLY LEAGUE" },
		{
			Key = "Return",
			Store = "Return",
			Weekly = true,
			Kind = "Return",
			Title = "Ø-TAGESRENDITE · AVG DAILY RETURN",
		},
		{ Key = "Skyline", Store = "Skyline", Weekly = false, Kind = "Int", Title = "SKYLINE" },
		{ Key = "Firm", Store = "Firm", Weekly = false, Kind = "Log", Title = "FIRMENWERT · COMPANY VALUE" },
		{ Key = "Respekt", Store = "Respekt", Weekly = true, Kind = "Int", Title = "BELIEBTESTER TOWER · MOST LIKED" },
	},
	Rows = 10,
	CacheTop = 100,
	NameCache = 200,
	ReadStagger = 0.5,
	HallOfFame = { Count = 3, Board = "League", Color = "#facc15" },
	IpoStoreKey = "IpoHall_v1", -- Hall of IPOs (DataStore Config.Tech.GlobalStore)
	ReferralKeyPrefix = "Ref_", -- Einladungs-Gutschriften für gerade nicht verbundene Einlader (gleicher Store)
}

-- =====================================================================
-- NACHSCHLAGE-TABELLEN (beim Laden gebaut; doppelte Schlüssel -> assert, CC-Stil)
-- =====================================================================
Progression.ExamByKey = {}
Progression.LessonById = {}
Progression.QuestKindByKey = {}
Progression.QuestById = {}
Progression.AchievementById = {}
Progression.TitleByKey = {}
Progression.PerkByKey = {}
Progression.NodeByKey = {}
Progression.BadgeByKey = {}
do
	for _, task in ipairs(Progression.ExamTasks) do
		assert(Progression.ExamByKey[task.Key] == nil, "[Config.Progression] doppelte Prüfungs-Aufgabe " .. task.Key)
		Progression.ExamByKey[task.Key] = task
	end
	for index, lesson in ipairs(Progression.Academy.Lessons) do
		assert(Progression.LessonById[lesson.Id] == nil, "[Config.Progression] doppelte Lektion " .. lesson.Id)
		lesson.Index = index
		Progression.LessonById[lesson.Id] = lesson
	end
	for _, kind in ipairs(Progression.QuestKinds) do
		assert(Progression.QuestKindByKey[kind.Key] == nil, "[Config.Progression] doppelte Quest-Art " .. kind.Key)
		Progression.QuestKindByKey[kind.Key] = kind
	end
	for _, listName in ipairs({ "Daily", "Weekly", "StarterLine" }) do
		for _, quest in ipairs((Progression.Quests :: any)[listName]) do
			assert(Progression.QuestById[quest.Id] == nil, "[Config.Progression] doppelte Quest " .. quest.Id)
			Progression.QuestById[quest.Id] = quest
		end
	end
	local comeback = Progression.Quests.Comeback
	Progression.QuestById[comeback.Id] = comeback
	for _, entry in ipairs(Progression.Achievements) do
		assert(Progression.AchievementById[entry.Id] == nil, "[Config.Progression] doppelter Erfolg " .. entry.Id)
		Progression.AchievementById[entry.Id] = entry
	end
	for _, listName in ipairs({ "Wealth", "Extra" }) do
		for _, title in ipairs((Progression.Titles :: any)[listName]) do
			assert(Progression.TitleByKey[title.Key] == nil, "[Config.Progression] doppelter Titel " .. title.Key)
			Progression.TitleByKey[title.Key] = title
		end
	end
	for _, perk in ipairs(Progression.Prestige.Perks) do
		assert(Progression.PerkByKey[perk.Key] == nil, "[Config.Progression] doppelter Vorstand-Ast " .. perk.Key)
		Progression.PerkByKey[perk.Key] = perk
	end
	for _, node in ipairs(Progression.KnowHow.Nodes) do
		assert(Progression.NodeByKey[node.Key] == nil, "[Config.Progression] doppelter Know-how-Knoten " .. node.Key)
		Progression.NodeByKey[node.Key] = node
	end
	for _, badge in ipairs(Progression.Badges) do
		assert(Progression.BadgeByKey[badge.Key] == nil, "[Config.Progression] doppeltes Badge " .. badge.Key)
		Progression.BadgeByKey[badge.Key] = badge
	end
end

-- =====================================================================
-- PRÜFUNG (Config.Validate sammelt alle Meldungen; leer = alles ok)
-- =====================================================================
local function isNum(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isInt(v: any): boolean
	return isNum(v) and v % 1 == 0
end

local function isPair(v: any): boolean
	return type(v) == "table" and type(v.de) == "string" and v.de ~= "" and type(v.en) == "string" and v.en ~= ""
end

local LAYERS = { Simple = true, Trader = true, Pro = true }
local SETS = { Azubi = true, Trader = true, Fonds = true }
local CATS = { Trade = true, Academy = true, Tower = true, World = true, Social = true }
local CHECKS = {
	Floors = true,
	Eff = true,
	Licence = true,
	Lessons = true,
	RoomKinds = true,
	BotOn = true,
	LeagueDays = true,
	Wealth = true,
}

function Progression.Validate(_config: any): { string }
	local errors: { string } = {}
	local function add(text: string)
		table.insert(errors, "Config.Progression." .. text)
	end

	-- Lizenzen
	if #Progression.Licences ~= 10 then
		add("Licences: genau 10 Lizenzen erwartet")
	end
	local lastXp, lastBasis, lastKurs = -1, 0, 0
	for i, lic in ipairs(Progression.Licences) do
		local where = ("Licences[%d]"):format(i)
		if type(lic.Key) ~= "string" or not isPair(lic.Name) then
			add(where .. ": Key und Name {de, en} erwartet")
		end
		if not isInt(lic.Xp) or lic.Xp <= lastXp then
			add(where .. ".Xp: ganze Zahl, steigend erwartet")
		end
		if i == 1 and lic.Xp ~= 0 then
			add(where .. ".Xp: Azubi I startet bei 0")
		end
		if not isInt(lic.Basis) or lic.Basis <= lastBasis or lic.Basis >= 9e15 then
			add(where .. ".Basis: ganze Cent, steigend, < 9e15 erwartet")
		end
		if not isNum(lic.BauKurs) or lic.BauKurs <= lastKurs then
			add(where .. ".BauKurs: steigend erwartet")
		end
		if not isNum(lic.TowerBonus) or lic.TowerBonus < 0 or lic.TowerBonus > 1 then
			add(where .. ".TowerBonus: 0 … 1 erwartet")
		end
		if not isNum(lic.FeeBps) or lic.FeeBps < 0 or lic.FeeBps > 100 then
			add(where .. ".FeeBps: 0 … 100 erwartet")
		end
		if not isNum(lic.MaxWeight) or lic.MaxWeight < 0.05 or lic.MaxWeight > 1 then
			add(where .. ".MaxWeight: 0,05 … 1 erwartet")
		end
		if not isInt(lic.MaxOrders) or lic.MaxOrders < 1 or lic.MaxOrders > 50 then
			add(where .. ".MaxOrders: 1 … 50 erwartet")
		end
		if not LAYERS[lic.Layer] then
			add(where .. ".Layer: Simple/Trader/Pro erwartet")
		end
		if not SETS[lic.Set] then
			add(where .. ".Set: Azubi/Trader/Fonds erwartet")
		end
		if not isInt(lic.MaxStage) or lic.MaxStage < 1 or lic.MaxStage > 12 then
			add(where .. ".MaxStage: 1 … 12 erwartet")
		end
		if not isInt(lic.MaxIpo) or lic.MaxIpo < 0 then
			add(where .. ".MaxIpo: ganze Zahl ≥ 0 erwartet")
		end
		if not isInt(lic.BotSlots) or lic.BotSlots < 0 or lic.BotSlots > 5 then
			add(where .. ".BotSlots: 0 … 5 erwartet")
		end
		if type(lic.Exam) ~= "table" then
			add(where .. ".Exam: Liste erwartet")
		else
			for _, task in ipairs(lic.Exam) do
				if not Progression.ExamByKey[task] then
					add(where .. ".Exam: unbekannte Aufgabe " .. tostring(task))
				end
			end
		end
		lastXp = if isInt(lic.Xp) then lic.Xp else lastXp
		lastBasis = if isInt(lic.Basis) then lic.Basis else lastBasis
		lastKurs = if isNum(lic.BauKurs) then lic.BauKurs else lastKurs
	end
	for _, task in ipairs(Progression.ExamTasks) do
		if task.Source == "Lesson" and not Progression.LessonById[task.Lesson] then
			add("ExamTasks." .. task.Key .. ".Lesson: unbekannte Lektion")
		end
	end

	-- XP-Quellen
	for key, source in pairs(Progression.XpSources) do
		if type(source) ~= "table" or not isInt(source.Xp) or source.Xp < 0 then
			add("XpSources." .. tostring(key) .. ".Xp: ganze Zahl ≥ 0 erwartet")
		elseif source.Cap ~= nil and (not isInt(source.Cap) or source.Cap < 1) then
			add("XpSources." .. tostring(key) .. ".Cap: ganze Zahl ≥ 1 erwartet")
		end
	end
	local tutorialSum = 0
	for _, xp in pairs(Progression.Tutorial.Xp) do
		tutorialSum += if isInt(xp) then xp else 0
	end
	if tutorialSum ~= Progression.XpSources.Tutorial.Xp then
		add(
			("Tutorial.Xp: Summe %d, erwartet %d (XpSources.Tutorial)"):format(
				tutorialSum,
				Progression.XpSources.Tutorial.Xp
			)
		)
	end
	if not isNum(Progression.LevelCurve) or Progression.LevelCurve <= 0 then
		add("LevelCurve: Zahl > 0 erwartet")
	end

	-- Know-how
	local khMax = 0
	for _, node in ipairs(Progression.KnowHow.Nodes) do
		if not isInt(node.Max) or node.Max < 1 or not isInt(node.Cost) or node.Cost < 1 then
			add("KnowHow.Nodes." .. tostring(node.Key) .. ": Max/Cost ganze Zahlen ≥ 1 erwartet")
		else
			khMax += node.Max * node.Cost
		end
		if not isInt(node.Licence) or node.Licence < 1 or node.Licence > 10 then
			add("KnowHow.Nodes." .. tostring(node.Key) .. ".Licence: 1 … 10 erwartet")
		end
	end
	if khMax < 1 then
		add("KnowHow.Nodes: leer")
	end

	-- Ruf
	local last = 0
	for i, threshold in ipairs(Progression.Ruf.Thresholds) do
		if not isInt(threshold) or threshold <= last then
			add(("Ruf.Thresholds[%d]: steigend erwartet"):format(i))
		end
		last = if isInt(threshold) then threshold else last
	end
	if #Progression.Ruf.Thresholds ~= 10 then
		add("Ruf.Thresholds: 10 Stufen erwartet")
	end

	-- Titel
	if #Progression.Titles.Wealth ~= 12 then
		add("Titles.Wealth: 12 Vermögens-Titel erwartet")
	end
	for _, list in ipairs({ Progression.Titles.Wealth, Progression.Titles.Extra }) do
		for _, title in ipairs(list) do
			if type(title.Key) ~= "string" or not isPair(title.Name) then
				add("Titles." .. tostring(title.Key) .. ": Key und Name {de, en} erwartet")
			end
		end
	end

	-- Börsengang
	local stars = 0
	for _, perk in ipairs(Progression.Prestige.Perks) do
		if not isInt(perk.Max) or perk.Max < 1 then
			add("Prestige.Perks." .. tostring(perk.Key) .. ".Max: ganze Zahl ≥ 1 erwartet")
		else
			stars += perk.Max
		end
	end
	if stars ~= 39 then
		add(("Prestige.Perks: Summe %d ★, erwartet 39 (§B9.6)"):format(stars))
	end
	for _, step in ipairs(Progression.Prestige.TitleSteps) do
		if not Progression.TitleByKey[step.Title] then
			add("Prestige.TitleSteps: unbekannter Titel " .. tostring(step.Title))
		end
	end
	for _, word in ipairs(Progression.TickerBlock) do
		if type(word) ~= "string" or string.match(word, "^[A-Z]+$") == nil then
			add("TickerBlock: nur Großbuchstaben erwartet (" .. tostring(word) .. ")")
		end
	end

	-- Akademie
	if #Progression.Academy.Lessons ~= 16 then
		add("Academy.Lessons: 16 Lektionen erwartet")
	end
	for _, lesson in ipairs(Progression.Academy.Lessons) do
		if not isInt(lesson.Cards) or lesson.Cards < 3 or lesson.Cards > 5 then
			add("Academy.Lessons." .. lesson.Id .. ".Cards: 3 … 5 erwartet")
		end
		if type(lesson.Quiz) ~= "table" or #lesson.Quiz < 2 or #lesson.Quiz > 3 then
			add("Academy.Lessons." .. lesson.Id .. ".Quiz: 2 … 3 Fragen erwartet")
		else
			for _, options in ipairs(lesson.Quiz) do
				if not isInt(options) or options < 2 or options > 4 then
					add("Academy.Lessons." .. lesson.Id .. ".Quiz: 2 … 4 Antworten je Frage erwartet")
				end
			end
		end
		if not isInt(lesson.Series) or lesson.Series < 1 or lesson.Series > Progression.Academy.Series then
			add("Academy.Lessons." .. lesson.Id .. ".Series: 1 … " .. Progression.Academy.Series .. " erwartet")
		end
	end

	-- Quests
	if #Progression.QuestKinds ~= 21 then
		add("QuestKinds: 21 Arten erwartet (§B9.7)")
	end
	for _, kind in ipairs(Progression.QuestKinds) do
		if not CATS[kind.Cat] then
			add("QuestKinds." .. kind.Key .. ".Cat: Trade/Academy/Tower/World/Social erwartet")
		end
		if type(kind.Tracker) ~= "string" or kind.Tracker == "" then
			add("QuestKinds." .. kind.Key .. ".Tracker: Service-Name erwartet (jede Art braucht einen Tracker)")
		end
	end
	local q = Progression.Quests
	if #q.Daily ~= q.DailyPool then
		add(("Quests.Daily: %d Vorlagen erwartet"):format(q.DailyPool))
	end
	if #q.Weekly ~= q.WeeklyPool then
		add(("Quests.Weekly: %d Vorlagen erwartet"):format(q.WeeklyPool))
	end
	if #q.StarterLine ~= q.Starter then
		add(("Quests.StarterLine: %d Schritte erwartet"):format(q.Starter))
	end
	local tradeDaily = 0
	for _, listName in ipairs({ "Daily", "Weekly", "StarterLine" }) do
		for _, quest in ipairs((q :: any)[listName]) do
			local where = "Quests." .. listName .. "." .. tostring(quest.Id)
			if quest.Check ~= nil then
				if not CHECKS[quest.Check] then
					add(where .. ".Check: unbekannt")
				end
			elseif not Progression.QuestKindByKey[quest.Kind] then
				add(where .. ".Kind: unbekannte Quest-Art " .. tostring(quest.Kind))
			end
			if not isNum(quest.Goal) or quest.Goal < 1 then
				add(where .. ".Goal: Zahl ≥ 1 erwartet")
			end
			if listName == "Daily" then
				if not isInt(quest.Tier) or quest.Tier < 1 or quest.Tier > #q.TierMinutes then
					add(where .. ".Tier: 1 … " .. #q.TierMinutes .. " erwartet")
				end
				local kind = Progression.QuestKindByKey[quest.Kind]
				if kind and (kind.Cat == "Trade" or kind.Cat == "Academy") then
					tradeDaily += 1
				end
			end
			if listName == "StarterLine" then
				if not isInt(quest.Credits) or quest.Credits < 500 or quest.Credits > 50000 then
					add(where .. ".Credits: 500 … 50.000 erwartet (§B9.7)")
				end
				if quest.Title ~= nil and not Progression.TitleByKey[quest.Title] then
					add(where .. ".Title: unbekannter Titel")
				end
			end
		end
	end
	if tradeDaily < q.DailyCount then
		add("Quests.Daily: zu wenige Handels-/Akademie-Vorlagen")
	end

	-- Erfolge
	if #Progression.Achievements ~= 60 then
		add("Achievements: 60 Erfolge erwartet (§B9.8)")
	end
	local perCat: { [string]: number } = {}
	for _, entry in ipairs(Progression.Achievements) do
		perCat[entry.Cat] = (perCat[entry.Cat] or 0) + 1
		if not isPair(entry.Name) or type(entry.Stat) ~= "string" or not isNum(entry.Goal) or entry.Goal <= 0 then
			add("Achievements." .. entry.Id .. ": Name/Stat/Goal erwartet")
		end
		local reward = entry.Reward
		if reward.Title ~= nil and not Progression.TitleByKey[reward.Title] then
			add("Achievements." .. entry.Id .. ".Reward.Title: unbekannter Titel")
		end
		if reward.Minutes ~= nil and (not isNum(reward.Minutes) or reward.Minutes <= 0) then
			add("Achievements." .. entry.Id .. ".Reward.Minutes: Zahl > 0 erwartet")
		end
		if reward.Min ~= nil and (not isInt(reward.Min) or reward.Min < 0 or reward.Min >= 1e14) then
			add("Achievements." .. entry.Id .. ".Reward.Min: ganze Zahl < 1e14 erwartet")
		end
	end
	local expected = { Trading = 14, Tower = 14, Academy = 10, Collection = 10, Social = 6, Events = 6 }
	for cat, n in pairs(expected) do
		if perCat[cat] ~= n then
			add(("Achievements: Kategorie %s hat %d statt %d"):format(cat, perCat[cat] or 0, n))
		end
	end

	-- Badges
	if #Progression.Badges ~= 15 then
		add("Badges: 15 Badges erwartet (§B9.8)")
	end
	for _, badge in ipairs(Progression.Badges) do
		if not isInt(badge.Id) or badge.Id < 0 or not isPair(badge.Name) then
			add("Badges." .. tostring(badge.Key) .. ": Id (ganze Zahl ≥ 0, 0 = aus) und Name erwartet")
		end
	end

	-- Album
	if #Progression.Album.Cards ~= 43 then
		add("Album.Cards: 43 Karten erwartet (36 Firmen + 7 ETFs)")
	end

	-- Tutorial
	for step, name in pairs(Progression.Tutorial.FunnelNames) do
		if not isInt(step) or step < 1 or step > 18 or type(name) ~= "string" then
			add("Tutorial.FunnelNames: Schritte 1 … 18 mit Namen erwartet")
		end
	end

	-- Sozial
	local social = Progression.Social
	if not isInt(social.GroupId) or social.GroupId < 0 then
		add("Social.GroupId: ganze Zahl ≥ 0 erwartet (0 = aus)")
	end
	if #social.Reactions ~= 5 then
		add("Social.Reactions: 5 Reaktionen erwartet (§B11.3)")
	end

	-- Bestenlisten
	if #Progression.Boards.List ~= 6 then
		add("Boards.List: 6 Bestenlisten erwartet (§B11.1)")
	end
	return errors
end

return Progression
