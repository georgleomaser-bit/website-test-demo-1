-- =====================================================================
--  AKYTEX TYCOON – Stellschrauben der Markt-Engine (Config.Market)
--  Besitzer: WP3 (Markt-Engine). Vertrag: DESIGN.md §B6, §B6.3, §B10.4, §B15.3, §C14.2, §C19; MARKET.md §3–§10, §13, §17.
--  Jede Zahl hier ist ein Startwert aus der Spec und wurde mit tools/market_calibrate.py geprüft (Gates G5/G6).
--  Nach JEDER Änderung an Rauschen, News, Bändern oder Bremse: `python3 tools/market_calibrate.py` laufen lassen.
--
--  WICHTIG – Determinismus: Alle Server rechnen denselben Kurs aus Wochen-Seed + Tick + Event-Liste. Werte, die den
--  Kurs verändern, nur zum Wochenwechsel ändern (Montag 00:00 UTC) – sonst sehen Server mit alter/neuer Config
--  verschiedene Kurse. Einzige Live-Stellschraube: NewsMeanGap (wird beim Anlegen einer Woche als Tune_W<w>
--  im DataStore eingefroren, gilt also für alle Server dieser Woche gleich).
--  Der Seed steht NIE hier (Config wird an alle Clients repliziert).
--
--  Abschnitte: 1 Zeit · 2 Rauschen · 3 Risikoklassen · 4 Fundament & Bewertungs-Bremse · 5 Firmen-News ·
--  6 Sektor-News & Makro-Matrix · 7 Quartalszahlen & Analysten · 8 Dividenden · 9 Crash & Rallye ·
--  10 Wochen-Termine (Berlin-Zeit) · 11 Handelspausen · 12 Admin-Markt (§B15.3) · 13 GlobalBus · 14 Kerzen & Historie ·
--  15 Anfragen · 16 IPO-Pipeline · 17 Seed · 18 Fundamentaldaten-Anzeige · Validate(Config)
-- =====================================================================

local Market = {}

-- ---------------------------------------------------------------------
-- 1) ZEIT (EPOCH und Tick kommen aus Shared/Clock: EPOCH = Mo 2026-01-05 00:00 UTC)
-- ---------------------------------------------------------------------
Market.DayTicks = 1200 -- ein Börsentag = 20 min = 1200 Ticks (= Clock.DAY_TICKS)
Market.Delay = 8 -- Lesefenster: so viele Sekunden nach einer Schlagzeile reagiert der Kurs noch NICHT
Market.Tau = 45 -- Reaktions-Rampe (Smoothstep) in Sekunden
Market.Overshoot = { Max = 0.3, Decay = 300, Span = 3600 } -- Übertreibung 0…30 %, bildet sich mit e^(−x/300) zurück
Market.RumorResolve = 120 -- Gerücht: Bestätigung/Dementi nach 2 min (danach wieder 8 s Lesefenster)
Market.QuietEnd = 300 -- in den letzten 5 min einer Woche keine neuen Firmen-News (kein Überhang in die neue Woche)

-- ---------------------------------------------------------------------
-- 2) RAUSCHEN (MARKET §5.1/§5.2): Markt-, Sektor-, Firmen-Feld (14 Oktaven, 2 s … 16.384 s) + Mikrostruktur
-- ---------------------------------------------------------------------
Market.Noise = {
	Beta = 0.45, -- Markt-Feld
	Gamma = 0.55, -- Sektor-Feld
	Eps = 0.70, -- Firmen-Feld (Quadratsumme ≈ 1 -> Korrelation gleicher Sektor 0,52, sonst 0,18)
	Micro = 0.010, -- Mikrostruktur je Sekunde relativ zu Sigma (Bid/Ask-Bounce)
	RegimeK = 0.25, -- R(t) = exp(0,25 · V(t)) · Volatilitäts-Faktor (Crash/Rallye/Admin)
	RegimeOctaves = { 10, 14 }, -- V(t): langsames Feld, Perioden 1.024 s … 16.384 s (≈ 15 min … 4,5 h)
	RegimeRange = { 0.3, 4 }, -- R wird hierauf geklemmt
	Weather = { Calm = 0.85, Storm = 1.2 }, -- R < 0,85 sonnig · bis 1,2 wolkig · darüber Sturm (Markt-Wetter)
}

-- ---------------------------------------------------------------------
-- 3) RISIKOKLASSEN (MARKET §4.1). SpreadBps = voller Spread in Basispunkten (× R(t)), Sigma1s = 1s-Std für die
--    Kerzen-Dochte, VolBase = Grund-Umsatz je Sekunde (Stück), CrashBeta = Stärke bei Crash/Rallye
-- ---------------------------------------------------------------------
Market.Classes = {
	Stabil = { Sigma = 0.030, SpreadBps = 4, NewsFactor = 0.74, Sigma1s = 0.0006, VolBase = 600, CrashBeta = 0.7 },
	Normal = { Sigma = 0.055, SpreadBps = 8, NewsFactor = 1.00, Sigma1s = 0.0011, VolBase = 900, CrashBeta = 1.0 },
	Wild = { Sigma = 0.100, SpreadBps = 16, NewsFactor = 1.35, Sigma1s = 0.0019, VolBase = 1400, CrashBeta = 1.4 },
	ETF = { Sigma = 0, SpreadBps = 3, NewsFactor = 0, Sigma1s = 0.0007, VolBase = 2500, CrashBeta = 1.0 },
}

-- ---------------------------------------------------------------------
-- 4) FUNDAMENT & BEWERTUNGS-BREMSE (MARKET §4.3, §5.4)
--    Drift je Börsentag = Base + Quality · q − Revert · C (q ∈ [−1, 1] je Firma und Woche, geheim, aus dem Seed),
--    C = Bewertung = ln(Wochenbasis / Startkurs) + Drift seit Wochenstart + dauerhafte Sprünge der Woche.
--    Bei C = 0 ist das genau die Spec-Drift (+0,2 % + 0,4 % · q). Der Anker (Revert, Halbwertszeit ≈ 28 Börsentage
--    ≈ 9 h) verhindert, dass Drift, Quartals-Überraschungen (Mittel 0,6 · q) und Dividenden-Abschläge über 504
--    Börsentage je Woche exponentiell wachsen (gemessen ohne Anker: Faktor 100 in einer Woche). C enthält dafür auch
--    die Dividenden (Nennrendite).
--    Liegt C über Above, sinkt zusätzlich die Chance positiver Firmen-News auf PosP (unter −Above spiegelbildlich).
-- ---------------------------------------------------------------------
Market.Drift = { Base = 0.002, Quality = 0.004, Revert = 0.025, MaxRate = 0.04 }
Market.Brake = {
	PosBase = 0.52, -- normal: 52 % der Firmen-News sind positiv
	Steps = { { Above = 0.9, PosP = 0.30 }, { Above = 1.6, PosP = 0.15 } },
}
Market.Price = { MinCents = 50, MaxCents = 9999999 } -- 0,50 … 99.999,99 AKY
Market.Activity = { EdgeMinutes = 3, EdgeMult = 1.4 } -- Umsatz ×1,4 in den ersten/letzten 3 Minuten jedes Börsentags

-- ---------------------------------------------------------------------
-- 5) FIRMEN-NEWS (MARKET §6.1/§6.2)
-- ---------------------------------------------------------------------
Market.NewsMeanGap = 1500 -- Ø Sekunden zwischen zwei News derselben Firma (Live-Stellschraube, 300 … 6000)
Market.Bands = { -- Stärke-Wortschatz: Anteil, |J| von/bis (Klasse Normal; × NewsFactor der Klasse)
	{ P = 0.50, Lo = 0.01, Hi = 0.03 }, -- 1 leicht
	{ P = 0.30, Lo = 0.03, Hi = 0.06 }, -- 2 deutlich
	{ P = 0.15, Lo = 0.06, Hi = 0.12 }, -- 3 massiv
	{ P = 0.05, Lo = 0.12, Hi = 0.25 }, -- 4 historisch
}
Market.Kinds = { Fact = 0.55, Rumor = 0.25, AsExpected = 0.20 }
Market.Rumor = {
	StarsMix = { 0.45, 0.35, 0.20 }, -- Anteil ★ / ★★ / ★★★
	Confirm = { 0.35, 0.60, 0.85 }, -- Bestätigungsquote je Sterne (sichtbar, lernbar)
}

-- ---------------------------------------------------------------------
-- 6) SEKTOR-NEWS & MAKRO (MARKET §6.2, §6.4). Matrix-Faktor × Grundsprung 1,5 % × Überraschung bzw. Themen-Stärke.
-- ---------------------------------------------------------------------
Market.Sector = {
	MeanGap = 600, -- Ø alle 10 min eine Sektor-Nachricht im ganzen Markt
	Sensitivity = { 0.6, 1.4 }, -- Firmen-Sensitivität
	ThemeShare = 0.4, -- Anteil Themen-News (KI-Durchbruch, Chip-Knappheit …) statt einfacher Sektor-News
	ThemeMult = { 1, 2, 3.5 }, -- Themen-Stärke leicht / deutlich / massiv
}
Market.Macro = {
	Minute = 10, -- Ergebnis um :10
	PreviewMinute = 2, -- Konsens um :02
	BaseJump = 0.015,
	SurpriseMax = 2, -- Überraschung s ∈ [−2, 2]
	FlatBelow = 0.25, -- |s| darunter = "wie erwartet" (kein Sprung)
	Kinds = { "Rates", "Growth", "Energy" },
}
Market.Themes = { "Ai", "Chips", "Heat", "Esport", "Space" }
Market.Matrix = { -- Faktor je Sektor (T Tech · E Energie · M Mobilität · K Konsum · G Gaming · F Finanzen)
	Rates = { T = -1.0, E = -0.3, M = -0.6, K = -0.3, G = -0.5, F = 0.8 }, -- Zinsen höher als erwartet
	Growth = { T = 0.6, E = 0.5, M = 0.8, K = 0.6, G = 0.5, F = 0.6 }, -- Konjunktur stärker
	Energy = { T = -0.2, E = 1.0, M = -0.8, K = -0.4, G = -0.1, F = 0 }, -- Energiepreis steigt
	Ai = { T = 1.2, E = 0.4, M = 0.3, K = 0, G = 0.6, F = 0.2 }, -- KI-Durchbruch
	Chips = { T = -0.8, E = 0, M = -0.7, K = 0, G = -0.6, F = 0 }, -- Chip-Knappheit
	Heat = { T = 0, E = 0.5, M = 0, K = 0.6, G = 0.2, F = -0.2 }, -- Hitzewelle
	Esport = { T = 0, E = 0, M = 0, K = 0.2, G = 1.0, F = 0 }, -- Esport-WM
	Space = { T = 0.2, E = 0, M = 0.9, K = 0, G = 0.2, F = 0 }, -- Raumfahrt-Mission
}

-- ---------------------------------------------------------------------
-- 7) QUARTALSZAHLEN & ANALYSTEN (MARKET §6.3, DESIGN §B8.7)
-- ---------------------------------------------------------------------
Market.Earnings = {
	EveryDays = 3, -- Firma i berichtet, wenn (Börsentag + i) % 3 == 0
	Slots = { 3, 7, 11, 15 }, -- Minuten (je 3 Firmen)
	PreviewMinutes = 5, -- Schlagzeile "Zahlen um :xx – Konsens …" 5 min vorher
	SurpriseQ = 0.6, -- s = 0,6 · q + 0,8 · z
	SurpriseZ = 0.8,
	JumpPerS = 0.03, -- J = clamp(0,03 · s · NewsFactor, ±0,20)
	JumpMax = 0.20,
	InlineBelow = 0.004, -- |J| darunter = "im Rahmen der Erwartungen"
	Covering = 3, -- so viele Analysten urteilen je Termin
}
Market.Analysts = { -- erfundene Personen, feste Genauigkeit; angezeigt wird die LIVE gemessene Trefferquote
	{ Key = "MiraSommer", Name = "Mira Sommer", Accuracy = 0.85 },
	{ Key = "JonasFalk", Name = "Jonas Falk", Accuracy = 0.62 },
	{ Key = "LeaBrandt", Name = "Lea Brandt", Accuracy = 0.78 },
	{ Key = "KenjiMori", Name = "Kenji Mori", Accuracy = 0.55 },
	{ Key = "AvaLindqvist", Name = "Ava Lindqvist", Accuracy = 0.81 },
	{ Key = "OmarHaddad", Name = "Omar Haddad", Accuracy = 0.67 },
	{ Key = "ClaraWeiss", Name = "Clara Weiß", Accuracy = 0.72 },
	{ Key = "TheoKranz", Name = "Theo Kranz", Accuracy = 0.58 },
}
Market.AnalystWindow = 30 -- Trefferquote über die letzten 30 Urteile
Market.Research = { BaseLeadMinutes = 2, MaxLeadMinutes = 5 } -- Analysten-Urteile 2 min vor den Zahlen (Know-how: bis 5)

-- ---------------------------------------------------------------------
-- 8) DIVIDENDEN (MARKET §6.3): Zahler schütten am Quartalstag um :19 aus, Betrag je Aktie = round(mid · DivBps/10000),
--    der Kurs fällt im selben Tick um genau diesen Betrag (Dividenden-Mitnahme bringt nichts).
-- ---------------------------------------------------------------------
Market.Dividend = { Minute = 19 }

-- ---------------------------------------------------------------------
-- 9) CRASH & RALLYE (MARKET §6.5): unangekündigt Ø alle 3,5 h, immer mit 3-min-Warnphase
-- ---------------------------------------------------------------------
Market.CrashRally = {
	Rate = 1 / 12600, -- je Tick
	CrashShare = 0.5, -- Anteil Crash (Rest Rallye)
	WarnSeconds = 180,
	WarnRegime = { 1.3, 1.6 }, -- Regime-Faktor steigt in der Warnphase
	PeakRegime = 2.0, -- in der Fallphase
	CrashDrop = { 0.12, 0.30 }, -- × CrashBeta der Klasse
	RallyRise = { 0.08, 0.20 },
	FallSeconds = { 60, 120 },
	RecoverShare = { 0.4, 0.6 }, -- Erholung in Anteilen des Falls
	RecoverSeconds = { 600, 1200 },
	MaxMove = 0.6, -- kein Einzelsprung über 60 %
	QuietEndDays = 3, -- keine Plan-Crashs in den letzten 3 Börsentagen der Woche
	MinGap = 3600, -- Mindestabstand zwischen zwei Plan-Crashs/-Rallyes (s)
}

-- ---------------------------------------------------------------------
-- 10) WOCHEN-TERMINE (Berlin-Ortszeit, über Clock.NextBerlin -> alle Server gleich; DESIGN §B6.3/§B10.4)
--     Dow 1 = Mo … 7 = So. Strength = Bewegung (Anteil), Recover = Rückgabe danach, Scope "Sector" = Sektor (Woche % 6) + 1.
-- ---------------------------------------------------------------------
Market.Weekly = {
	{ Key = "CrashFriday", Dow = 5, HH = 19, MM = 0, Kind = "Crash", Scope = "All", Strength = 0.18, Recover = 0.5 },
	{
		Key = "RallyWednesday",
		Dow = 3,
		HH = 19,
		MM = 0,
		Kind = "Rally",
		Scope = "Sector",
		Strength = 0.12,
		Recover = 0.5,
	},
	{ -- automatische Samstags-Show: abgesagt, wenn bis 18:14:50 ein CancelAutoShow im GlobalBus steht
		Key = "AutoShow",
		Dow = 6,
		HH = 18,
		MM = 15,
		Kind = "Rally",
		Scope = "Sector",
		Strength = 0.15,
		Recover = 0.5,
		Cancelable = true,
		CancelLead = 10,
		Offset = 30, -- Rallye-Schlagzeile 30 s nach Show-Beginn (Banner zuerst)
	},
	{ Key = "Ipo", Dow = 6, HH = 17, MM = 0, Kind = "Ipo" },
}
Market.ShowWindow = { Dow = 6, HH = 18, MM = 0 } -- Admin-Abuse-Termin: Markt-Admin-Events ab hier sagen die Auto-Show ab
Market.CalendarWeeklyDays = 7 -- Wochen-Termine stehen 7 echte Tage vorher im Kalender

-- ---------------------------------------------------------------------
-- 11) HANDELSPAUSEN (MARKET §6.5, §8.4)
-- ---------------------------------------------------------------------
Market.Halts = { AdminSeconds = 10, LateSeconds = 10, IpoSeconds = 60 }

-- ---------------------------------------------------------------------
-- 12) ADMIN-MARKT (§B15.3, MARKET §17) – alles geklemmt, immer global über den GlobalBus
-- ---------------------------------------------------------------------
Market.Admin = {
	Strength = { 0.05, 0.50 }, -- ±5 … 50 %
	Ramp = { 30, 300 },
	Decay = { 300, 3600 }, -- Abklingen 5 … 60 min (gesamt höchstens MaxSpan)
	MaxSpan = 3600, -- Ankündigung bis Ende höchstens 1 h (globale Nachrichten: Until ≤ now + 3600)
	HaltSeconds = { 10, 600 },
	Vol = { 0.5, 3 },
	VolSeconds = { 300, 1800 },
	VolRamp = 30,
	NormalizeSeconds = 60,
	Cooldown = 3, -- Sekunden je Markt-Aktion
	Lead = 10, -- Vorlauf: Aktivierung = jetzt + 10 s (> Poll + Messaging-Latenz)
	WarnSeconds = 180, -- optionale Crash-Warnung
	WindowAfter = 600, -- Admin-Fenster läuft bis 10 min nach dem Abklingen
	NewsMaxChars = 80,
	NewsDecay = 600, -- Admin-Eilmeldung klingt nach 10 min zum Modellkurs zurück
	PeakRegime = 1.6,
}

-- ---------------------------------------------------------------------
-- 13) GLOBALBUS (MARKET §8.2–§8.4; MemoryStore = Wahrheit, Messaging = Schnellweg)
-- ---------------------------------------------------------------------
Market.Bus = {
	PollSeconds = 5,
	ExpirySeconds = 93600, -- 26 h
	PageSize = 50,
	MaxPages = 20,
	Dedupe = 200,
	MaxEvents = 200, -- so viele Bus-Events hält ein Server höchstens
	LogMax = 200, -- Einträge im Admin-Log AdminLog_W<w>
	MaxFuture = 60, -- StartTick höchstens so weit in der Zukunft (Vorlauf + Puffer)
	PollLookback = 30, -- jeder Poll liest die letzten 30 s erneut (Events, die ein anderer Server spät geschrieben hat)
}

-- ---------------------------------------------------------------------
-- 14) KERZEN & HISTORIE (MARKET §9)
-- ---------------------------------------------------------------------
Market.Rings = { S1 = 300, S5 = 360, M1 = 1440 }
Market.Backfill = { ExactHours = 6, SampleHours = 24, SampleStep = 10, FrameMs = 2 }
Market.History = { Candles = 120 } -- je Anfrage höchstens 120 Kerzen (+ 1 Eröffnungsreferenz)
Market.CatchUp = { MaxTicksPerRun = 10, JumpAfter = 60 }
Market.WeekHighCandles = 140 -- Wochen-Hoch-Flag = Hoch der letzten 140 1m-Kerzen (eine 1W-Kerze)

-- ---------------------------------------------------------------------
-- 15) ANFRAGEN (§C9; B = Token-Bucket {Kapazität, Nachfüllen/s})
-- ---------------------------------------------------------------------
Market.Buckets = { MktCandles = { 6, 2 }, MktProfile = { 6, 1 }, MktCalendar = { 6, 1 } }
Market.NewsRate = { 2, 1 } -- MktNews 2/s
Market.NewsKeep = 50 -- News-Liste endlich (letzte 50)

-- ---------------------------------------------------------------------
-- 16) IPO-PIPELINE (v1 Erstnotiz ohne Zeichnung, §B6.3). Saison s, Woche k der Saison -> Season[s][k] notiert
--     Samstag 17:00 Berlin. Eröffnung = Ausgabepreis · (1 + pop), pop ∈ Pop, korreliert mit der Prospekt-Qualität.
-- ---------------------------------------------------------------------
Market.IpoPipeline = {
	FirstWeek = 41, -- Woche seit EPOCH, in der Saison 1 beginnt (41 = Mo 2026-10-19)
	SeasonWeeks = 4,
	Season = { [1] = { 100, 101, 102, 103 } },
	Pop = { -0.10, 0.40 },
	PopBase = 0.15,
	PopQuality = 0.25,
	PopNoise = 0.08,
	ProspectLead = 86400, -- Prospekt 24 h vorher im Kalender
	AdminLead = 600, -- Admin-IPO: Erstnotiz 10 min nach dem Start
	FirstDayClass = "Wild",
	ClassBlend = 300, -- Übergang Wild -> eigene Klasse über 5 min (kein Kurssprung)
}

-- ---------------------------------------------------------------------
-- 17) SEED (MARKET §5.6): DataStore AT_Market_v1 (Config.Tech.MarketStore). Studio -> lokaler Testmarkt.
-- ---------------------------------------------------------------------
Market.Seed = { RetrySeconds = 60, Backoff = { 2, 4, 8, 15, 30 }, PrefetchBefore = 3600 }
Market.StudioSalt = 0x2A7E5713 -- Fallback-Seed = hash4(StudioSalt, w, …) (+ Server-Geheimnis, siehe MarketSeed)

-- ---------------------------------------------------------------------
-- 18) FUNDAMENTALDATEN-ANZEIGE (Firmenprofil; deterministisch, verrät q nur über die Quartale)
-- ---------------------------------------------------------------------
Market.Fundamentals = {
	Pe = { Stabil = 16, Normal = 24, Wild = -40 }, -- Start-KGV (negativ = schreibt Verluste)
	Revenue = { 0.5, 20 }, -- Umsatz je Quartal in Mrd. AKY
	GrowthBase = 0.02,
	GrowthQ = 0.03,
	GrowthS = 0.02,
	EpsS = 0.05,
}

-- =====================================================================
-- PRÜFUNG
-- =====================================================================
local function isNum(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function isInt(n: any): boolean
	return isNum(n) and n % 1 == 0
end

local function pair(t: any): boolean
	return type(t) == "table" and isNum(t[1]) and isNum(t[2]) and t[1] <= t[2]
end

function Market.Validate(config: any): { string }
	local errors: { string } = {}
	local function add(text: string)
		table.insert(errors, "Config.Market: " .. text)
	end
	if Market.DayTicks ~= 1200 then
		add("DayTicks muss 1200 sein (= Clock.DAY_TICKS)")
	end
	for _, key in ipairs({ "Delay", "Tau", "RumorResolve", "NewsMeanGap", "QuietEnd" }) do
		local v = (Market :: any)[key]
		if not isNum(v) or v <= 0 then
			add(key .. ": Zahl > 0 erwartet")
		end
	end
	if isNum(Market.NewsMeanGap) and (Market.NewsMeanGap < 300 or Market.NewsMeanGap > 6000) then
		add("NewsMeanGap: 300 … 6000 erwartet")
	end
	local noise = Market.Noise
	for _, key in ipairs({ "Beta", "Gamma", "Eps", "Micro", "RegimeK" }) do
		if not isNum((noise :: any)[key]) or (noise :: any)[key] < 0 then
			add("Noise." .. key .. ": Zahl ≥ 0 erwartet")
		end
	end
	local oct = noise.RegimeOctaves
	if not pair(oct) or not isInt(oct[1]) or not isInt(oct[2]) or oct[1] < 1 or oct[2] > 14 then
		add("Noise.RegimeOctaves: { von, bis } mit 1 ≤ von ≤ bis ≤ 14 erwartet")
	end
	if not pair(noise.RegimeRange) or noise.RegimeRange[1] <= 0 then
		add("Noise.RegimeRange: { min > 0, max } erwartet")
	end
	for _, name in ipairs({ "Stabil", "Normal", "Wild", "ETF" }) do
		local c = (Market.Classes :: any)[name]
		if type(c) ~= "table" then
			add("Classes." .. name .. " fehlt")
		else
			for _, key in ipairs({ "Sigma", "SpreadBps", "NewsFactor", "Sigma1s", "VolBase", "CrashBeta" }) do
				if not isNum(c[key]) or c[key] < 0 then
					add(("Classes.%s.%s: Zahl ≥ 0 erwartet"):format(name, key))
				end
			end
			if isNum(c.SpreadBps) and c.SpreadBps < 1 then
				add(("Classes.%s.SpreadBps: mindestens 1"):format(name))
			end
		end
	end
	local sum = 0
	for index, band in ipairs(Market.Bands) do
		if not isNum(band.P) or not isNum(band.Lo) or not isNum(band.Hi) or band.Lo > band.Hi or band.Lo < 0 then
			add("Bands[" .. index .. "]: { P, Lo ≤ Hi } erwartet")
		else
			sum += band.P
		end
	end
	if #Market.Bands ~= 4 or math.abs(sum - 1) > 1e-6 then
		add("Bands: genau 4 Bänder mit Anteilen Summe 1 erwartet")
	end
	local kinds = Market.Kinds
	if math.abs((kinds.Fact or 0) + (kinds.Rumor or 0) + (kinds.AsExpected or 0) - 1) > 1e-6 then
		add("Kinds: Fact + Rumor + AsExpected müssen 1 ergeben")
	end
	local mix = 0
	for index = 1, 3 do
		local share = Market.Rumor.StarsMix[index]
		local confirm = Market.Rumor.Confirm[index]
		if not isNum(share) or not isNum(confirm) or confirm < 0 or confirm > 1 then
			add("Rumor: StarsMix/Confirm je 3 Werte erwartet")
			break
		end
		mix += share
	end
	if math.abs(mix - 1) > 1e-6 then
		add("Rumor.StarsMix: Summe 1 erwartet")
	end
	local sectors = { "T", "E", "M", "K", "G", "F" }
	for row, factors in pairs(Market.Matrix) do
		for _, key in ipairs(sectors) do
			if not isNum((factors :: any)[key]) then
				add(("Matrix.%s.%s: Zahl erwartet"):format(tostring(row), key))
			end
		end
	end
	for _, kind in ipairs(Market.Macro.Kinds) do
		if (Market.Matrix :: any)[kind] == nil then
			add("Macro.Kinds: " .. kind .. " fehlt in der Matrix")
		end
	end
	for _, theme in ipairs(Market.Themes) do
		if (Market.Matrix :: any)[theme] == nil then
			add("Themes: " .. theme .. " fehlt in der Matrix")
		end
	end
	if #Market.Earnings.Slots ~= 4 then
		add("Earnings.Slots: 4 Minuten erwartet")
	end
	for _, minute in ipairs(Market.Earnings.Slots) do
		if not isInt(minute) or minute < 1 or minute > 18 then
			add("Earnings.Slots: Minuten 1…18 erwartet")
		end
	end
	if #Market.Analysts ~= 8 then
		add("Analysts: genau 8 erwartet")
	end
	for _, analyst in ipairs(Market.Analysts) do
		if type(analyst.Name) ~= "string" or not isNum(analyst.Accuracy) then
			add("Analysts: { Key, Name, Accuracy } erwartet")
		elseif analyst.Accuracy < 0.5 or analyst.Accuracy > 0.95 then
			add("Analysts." .. tostring(analyst.Key) .. ": Genauigkeit 0,5 … 0,95 erwartet")
		end
	end
	if not isInt(Market.Earnings.Covering) or Market.Earnings.Covering < 1 or Market.Earnings.Covering > 8 then
		add("Earnings.Covering: 1…8 erwartet")
	end
	local cr = Market.CrashRally
	for _, key in ipairs({ "CrashDrop", "RallyRise", "FallSeconds", "RecoverShare", "RecoverSeconds", "WarnRegime" }) do
		if not pair((cr :: any)[key]) then
			add("CrashRally." .. key .. ": { von ≤ bis } erwartet")
		end
	end
	local seenWeekly: { [string]: boolean } = {}
	for _, entry in ipairs(Market.Weekly) do
		local key = tostring(entry.Key)
		if seenWeekly[key] then
			add("Weekly: doppelter Schlüssel " .. key)
		end
		seenWeekly[key] = true
		if not isInt(entry.Dow) or entry.Dow < 1 or entry.Dow > 7 then
			add("Weekly." .. key .. ".Dow: 1…7 erwartet")
		end
		if
			not isInt(entry.HH)
			or entry.HH < 0
			or entry.HH > 23
			or not isInt(entry.MM)
			or entry.MM < 0
			or entry.MM > 59
		then
			add("Weekly." .. key .. ": HH 0…23 und MM 0…59 erwartet")
		end
		if entry.Kind ~= "Crash" and entry.Kind ~= "Rally" and entry.Kind ~= "Ipo" then
			add("Weekly." .. key .. ".Kind: Crash/Rally/Ipo erwartet")
		end
		if entry.Kind ~= "Ipo" and (not isNum(entry.Strength) or entry.Strength <= 0 or entry.Strength > 0.5) then
			add("Weekly." .. key .. ".Strength: 0 … 0,5 erwartet")
		end
	end
	local admin = Market.Admin
	for _, key in ipairs({ "Strength", "Ramp", "Decay", "HaltSeconds", "Vol", "VolSeconds" }) do
		if not pair((admin :: any)[key]) then
			add("Admin." .. key .. ": { von ≤ bis } erwartet")
		end
	end
	if not isNum(admin.MaxSpan) or admin.MaxSpan > 3600 then
		add("Admin.MaxSpan: höchstens 3600 (globale Nachrichten §C13)")
	end
	if not isNum(admin.Lead) or admin.Lead < 6 then
		add("Admin.Lead: mindestens 6 s (Poll + Messaging-Latenz)")
	end
	if not isNum(Market.Bus.PollSeconds) or Market.Bus.PollSeconds < 1 then
		add("Bus.PollSeconds: mindestens 1")
	end
	if isNum(admin.Lead) and isNum(Market.Bus.PollSeconds) and admin.Lead <= Market.Bus.PollSeconds then
		add("Admin.Lead muss größer als Bus.PollSeconds sein")
	end
	for _, key in ipairs({ "S1", "S5", "M1" }) do
		local v = (Market.Rings :: any)[key]
		if not isInt(v) or v < 60 or v > 5000 then
			add("Rings." .. key .. ": 60 … 5000 erwartet")
		end
	end
	if not isInt(Market.History.Candles) or Market.History.Candles < 10 or Market.History.Candles > 300 then
		add("History.Candles: 10 … 300 erwartet")
	end
	for name, bucket in pairs(Market.Buckets) do
		if not pair(bucket) or bucket[1] < 1 then
			add("Buckets." .. tostring(name) .. ": { Kapazität ≥ 1, Nachfüllen } erwartet")
		end
	end
	local pipeline = Market.IpoPipeline
	if not isInt(pipeline.FirstWeek) or not isInt(pipeline.SeasonWeeks) or pipeline.SeasonWeeks < 1 then
		add("IpoPipeline: FirstWeek/SeasonWeeks ganzzahlig erwartet")
	end
	if not pair(pipeline.Pop) or pipeline.Pop[1] < -0.5 or pipeline.Pop[2] > 1 then
		add("IpoPipeline.Pop: { −0,5 … 1 } erwartet")
	end
	if type(pipeline.Season) == "table" then
		local companies = type(config) == "table" and config.Companies or nil
		local byId = type(companies) == "table" and companies.ById or nil
		local used: { [number]: boolean } = {}
		for season, ids in pairs(pipeline.Season) do
			if not isInt(season) or type(ids) ~= "table" then
				add("IpoPipeline.Season: { [Saison] = { Id … } } erwartet")
				continue
			end
			if #ids > (pipeline.SeasonWeeks or 4) then
				add(("IpoPipeline.Season[%d]: höchstens %d IPOs (eins je Woche)"):format(season, pipeline.SeasonWeeks))
			end
			for _, id in ipairs(ids) do
				if used[id] then
					add("IpoPipeline: Id " .. tostring(id) .. " doppelt")
				end
				used[id] = true
				local inst = type(byId) == "table" and byId[id] or nil
				if type(byId) == "table" and (type(inst) ~= "table" or inst.Ipo ~= true) then
					add("IpoPipeline: Id " .. tostring(id) .. " ist keine IPO-Firma in Config.Companies")
				end
			end
		end
	else
		add("IpoPipeline.Season: Tabelle erwartet")
	end
	if not isInt(Market.StudioSalt) or Market.StudioSalt < 1 then
		add("StudioSalt: ganze Zahl > 0 erwartet")
	end
	return errors
end

return Market
