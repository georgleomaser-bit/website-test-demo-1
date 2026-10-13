-- =====================================================================
--  AKYTEX TYCOON – Welt-Events, Live-Ops-Kalender, Admin-Abuse-Grenzen (Config.Events)
--  Besitzer: WP11 (Admin, Events, Anti-Cheat). Vertrag: DESIGN.md §C14.2 (Events), §B10 (Welt-Events, Glocken-Moment,
--  Sky-Show, Bär/Bulle, Bullen-Parade, Feuerwerk, Geldregen, Samstags-Show), §B15.3 (Admin-Abuse-Katalog, 21 Events),
--  §C13 (globale Nachrichten: Until ≤ now + MaxGlobalSeconds), §C14.1 LiveFields ("Events.Rotation", "Events.BoostPause",
--  "Events.BellMoment.Mult", "Events.BuildBoom.Pct", "Events.Truck.Bundles", "Events.RainCoinsMax").
--  Alle Zahlen sind Startwerte und 1:1 änderbar. Wird an alle Clients repliziert -> KEINE Geheimnisse hier.
--  Spielertexte stehen in Lang/Events (evt.*) bzw. Lang/Admin (admin.*); hier nur Schlüssel und Zahlen.
--  Diese Datei lädt KEINE Roblox-Dienste (nur CFrame-Werte für Asset-Plätze).
--
--  Abschnitte:
--    1) Welt-Events :10 (Rotation Börsentag % 4)      2) Stündlich: Glocken-Moment, Sky-Show
--    3) Crash & Rally in der Welt (Bär, Bulle)         4) Robux-Shows (Parade, Feuerwerk)
--    5) Geldregen, Pickups                             6) Wochen-Kalender (Berlin-Zeit, Nicht-Markt-Teile)
--    7) Admin-Abuse-Katalog + Grenzen (§B15.3)         8) Globale Nachrichten, Notschalter
--    9) Asset-Plätze (Hybrid, Wunsch 17)               Validate(Config): { string }
-- =====================================================================

local Events = {}

local function slot(): { MeshId: number, TextureId: number, Scale: number, Offset: CFrame }
	return { MeshId = 0, TextureId = 0, Scale = 1, Offset = CFrame.identity }
end

-- ---------------------------------------------------------------------
-- 1) WELT-EVENTS (Minute :10 jedes Börsentags, Rotation = Börsentag-Index % #Rotation, auf allen Servern gleich)
--    Pickups werden PRO SPIELER instanziert (kein Wegschnappen); Server prüft Abstand, Fenster, max. 1 je Id.
-- ---------------------------------------------------------------------
Events.Rotation = { "Truck", "Drones", "BuildBoom", "Press" } -- live änderbar (Admin-Tab Live-Ops)
Events.WorldMinute = 10 -- Minute im Börsentag (Dividenden kommen um :19, Glocke um :00)

Events.Truck = {
	Bundles = 30, -- Bündel je Spieler (live 5 … 60)
	IncomeSeconds = 20, -- je Bündel so viele Sekunden Dauer-Einkommen (ohne Zeitlich)
	Seconds = 120, -- eine Runde um den Ring-Boulevard
	Route = "Ring",
	Lateral = 8, -- Bündel liegen bis zu so viele Studs neben der Fahrbahn-Mitte
	Linger = 30, -- so lange nach dem Ende bleiben liegende Bündel einsammelbar
	SeasonXpMin = 10, -- ab so vielen Bündeln gibt es die Saison-XP für die Teilnahme
}

Events.Drones = {
	Packages = 8, -- Pakete je Spieler (Positionen deterministisch aus dem Start-Tick)
	IncomeSeconds = 60,
	Seconds = 120,
	DropSeconds = 8, -- Drohnen-Anflug: so lange nach dem Start werden die Pakete einsammelbar
	Spread = 14, -- Streuung um den gewählten Ankerpunkt
}

Events.BuildBoom = {
	Pct = 0.25, -- Etagen- und Raum-Stufen-Kosten −25 % (live 0,05 … 0,5)
	Seconds = 300, -- ehrlicher Timer im HUD
}

Events.Press = {
	LeadMinutes = 13, -- zeigt die Quartalszahlen von :03 des NÄCHSTEN Börsentags
	Seconds = 90,
	QuizXp = 50, -- Trader-XP bei bestandenem Quiz (Config.Progression.XpSources.PressQuiz)
	Questions = 3,
	PassCorrect = 2, -- so viele richtige Antworten = bestanden
	PadSpacing = 7, -- Abstand der Antwort-Felder vor dem Hologramm
	MaxItems = 4, -- höchstens so viele Firmen auf dem Hologramm
	-- Fragen-Pool (Texte evt.quiz.<Id>.q / .a1 / .a2 / .a3); Auswahl deterministisch aus dem Börsentag
	Quiz = {
		{ Id = 1, Correct = 1 },
		{ Id = 2, Correct = 2 },
		{ Id = 3, Correct = 3 },
		{ Id = 4, Correct = 1 },
		{ Id = 5, Correct = 2 },
		{ Id = 6, Correct = 3 },
		{ Id = 7, Correct = 1 },
		{ Id = 8, Correct = 2 },
		{ Id = 9, Correct = 3 },
		{ Id = 10, Correct = 1 },
		{ Id = 11, Correct = 2 },
		{ Id = 12, Correct = 3 },
	},
}

-- ---------------------------------------------------------------------
-- 2) STÜNDLICH (Börsentag-Index % DayEvery == 0)
-- ---------------------------------------------------------------------
Events.BellMoment = {
	MinPlayers = 3, -- ≥ 3 Spieler in der Glocken-Zone (Studio: Config.Studio.BellZoneMinPlayers)
	Mult = 1.2, -- Server-Boost (Gruppe Zeitlich/Server; mit der Bullen-Parade gilt der größere Wert)
	Seconds = 300,
	DayEvery = 3,
	WindowSeconds = 60, -- :00 – :01
	ZoneRadius = 18, -- Rückfall, falls Config.City.Zones.Plaza.BellZoneRadius fehlt
}

Events.SkyShow = {
	RespektMult = 2, -- Respekt zählt doppelt (CommunityService liest EventService.Active())
	Seconds = 600, -- so lange zählt Respekt doppelt
	ShowSeconds = 75, -- Fassaden-Lichtshow + Feuerwerks-Beams
	Minute = 15,
	DayEvery = 3,
}

-- ---------------------------------------------------------------------
-- 3) CRASH & RALLY IN DER WELT (§B10.2; serverlokal, OHNE Markteinfluss)
-- ---------------------------------------------------------------------
Events.Bear = {
	OrbsPerPlayer = 8, -- gleichzeitig sichtbare Vertrauens-Kugeln je Spieler (respawnen nach dem Sammeln)
	GoalPerPlayer = 25, -- Server-Ziel = 25 × anwesende Spieler
	RewardMinutes = 10, -- Erfolg: 10 min Dauer-Einkommen für jeden Teilnehmer
	Seconds = 150, -- Fallphase des Crashs (+ Puffer)
	RadiusMin = 20, -- Kugeln im Ring um die Plaza-Mitte
	RadiusMax = 110,
	OrbsMaxPerPlayer = 60, -- Schutz: höchstens so viele Kugeln je Spieler und Bär
}

Events.GoldenBull = {
	Seconds = 180, -- eine Runde um den Ring-Boulevard
	Route = "Ring",
	TouchRange = 14, -- Berühren = Abstand Wurzel ↔ Bulle (Server misst 1×/s)
	BonusSeconds = 300, -- persönlicher Bullen-Bonus ×1,5 (TowerService.AddBoost "Bull"), 1× je Rally
}

-- ---------------------------------------------------------------------
-- 4) ROBUX-SHOWS (§B10.3; Kauf/Boost macht MonetizationService – hier nur die Welt)
-- ---------------------------------------------------------------------
Events.Parade = {
	Route = "Parade",
	Bulls = 5, -- goldene Bullen hintereinander
	LapSeconds = 150,
	MaxSeconds = 3600, -- Warteschlange höchstens 60 min
}
Events.Fireworks = { Seconds = 20 }

-- ---------------------------------------------------------------------
-- 5) GELDREGEN & PICKUPS
-- ---------------------------------------------------------------------
Events.RainCoinsMax = 30 -- höchstens so viele Münzen je Spieler und Geldregen (live 5 … 30)
Events.RainCoinMinutes = 2 -- je Münze 2 min Dauer-Einkommen
Events.MoneyRain = {
	DefaultSeconds = 120,
	FallSeconds = 1.6, -- Münze fällt so lange, erst danach einsammelbar
	NearShare = 0.5, -- Anteil der Münzen in der Nähe des Spielers, Rest über Plaza und eigenem Plot
	NearMin = 10,
	NearMax = 40,
	Linger = 25, -- liegende Münzen bleiben nach dem Ende noch so lange
}
Events.PickupRange = 12 -- Abstand Wurzel ↔ Pickup (Server)
Events.PickupMaxPerPlayer = 60 -- offene Pickup-Token je Spieler (§C16)
Events.MinPickupCredits = 10 -- Untergrenze je Pickup (neue Spieler mit kleinem Einkommen)
Events.WorldSeasonXp = 50 -- Saison-XP für die Teilnahme an einem Welt-Event (Config.Season.WorldEvent)

-- ---------------------------------------------------------------------
-- 6) WOCHEN-KALENDER (Berlin-Ortszeit über Clock.NextBerlin -> alle Server gleich; Markt-Termine: Config.Market.Weekly)
--    Dow 1 = Mo … 7 = So, fehlt = täglich. Kind: PowerHour | Reminder | AutoShow | LeagueFinale
-- ---------------------------------------------------------------------
Events.Weekly = {
	{ Key = "PowerHour", HH = 19, MM = 0, Kind = "PowerHour", Args = { Minutes = 60 } },
	{ Key = "UpdatePublish", Dow = 6, HH = 16, MM = 0, Kind = "Reminder", Args = { Text = "evt.cal.update" } },
	{ Key = "AdminAbuse", Dow = 6, HH = 18, MM = 0, Kind = "Reminder", Args = { Text = "evt.cal.abuse" } },
	{
		Key = "AutoShow",
		Dow = 6,
		HH = 18,
		MM = 15,
		Kind = "AutoShow",
		Args = { GoldenMult = 2, GoldenMinutes = 30, RainDelay = 75, RainSeconds = 180, FireworksDelay = 260 },
	},
	{ Key = "LeagueFinale", Dow = 7, HH = 20, MM = 0, Kind = "LeagueFinale", Args = { Seconds = 150, Top = 10 } },
}
Events.LeagueBoard = "League" -- LeaderboardService-Brett für die Top-10-Hologramme am Bilanz-Sonntag
Events.KindsHud = { -- Kinds mit Anzeigenamen ui.event.<Kind> (HUD-Pille; Rest = "Welt-Event")
	"Truck",
	"Drones",
	"BuildBoom",
	"Press",
	"BellMoment",
	"SkyShow",
	"Bear",
	"GoldenBull",
	"Parade",
	"Fireworks",
	"MoneyRain",
	"GoldenHour",
	"PowerHour",
	"AutoShow",
}

-- ---------------------------------------------------------------------
-- 7) ADMIN-ABUSE-KATALOG (§B15.3, 21 Events; Texte admin.ev.<Key>) – alles geklemmt, angekündigt, geloggt.
--    Market = true: läuft IMMER global über MarketService.Admin (GlobalBus) und öffnet ein Admin-Fenster (Liga-Taint).
-- ---------------------------------------------------------------------
Events.Catalogue = {
	{ Key = "MegaRally", Market = true },
	{ Key = "MegaCrash", Market = true },
	{ Key = "Pump", Market = true },
	{ Key = "Dump", Market = true },
	{ Key = "News", Market = true },
	{ Key = "Halt", Market = true },
	{ Key = "Resume", Market = true },
	{ Key = "Ipo", Market = true },
	{ Key = "Vol", Market = true },
	{ Key = "Normalize", Market = true },
	{ Key = "MoneyRain", Market = false },
	{ Key = "GoldenHour", Market = false },
	{ Key = "XpRush", Market = false },
	{ Key = "BuildBoom", Market = false },
	{ Key = "Lightshow", Market = false },
	{ Key = "Fireworks", Market = false },
	{ Key = "Confetti", Market = false },
	{ Key = "BellShow", Market = false },
	{ Key = "Boss", Market = false },
	{ Key = "AllToHall", Market = false, LocalOnly = true },
	{ Key = "SaturdayShow", Market = false },
}

Events.AdminLimits = {
	-- Markt (MarketService klemmt zusätzlich; Prozent 5 … 50, Abklingen in Minuten)
	MarketStrength = { 5, 50 },
	Ramp = { 30, 300 },
	DecayMinutes = { 5, 60 },
	CrashWarnSeconds = 180, -- optionale 3-min-Warnung
	HaltSeconds = { 10, 600 },
	Vol = { 0.5, 3 },
	VolMinutes = { 5, 30 },
	NewsChars = 80,
	NewsBand = { 1, 4 },
	-- Nicht-Markt
	MoneyRain = { Seconds = { 60, 300 } },
	GoldenHour = { Mult = { 2, 3 }, Minutes = { 5, 60 } },
	XpRush = { Mult = 2, Minutes = { 15, 60 } },
	BuildBoom = { Minutes = 10, CostMult = 0.5, BuildMult = 0.1 }, -- Etagenkosten −50 %, Bauzeit −90 %
	Lightshow = { Seconds = 75 },
	Fireworks = { Seconds = 20 },
	Confetti = { Seconds = 6 },
	BellShow = { Seconds = 30 },
	Boss = { Seconds = { 60, 300 }, Count = 8, Spacing = 9 },
	SaturdayShow = {
		GoldenMult = 2,
		GoldenMinutes = 30,
		RallyPct = 15,
		RainDelay = 75,
		RainSeconds = 180,
		FireworksDelay = 260,
	},
	AllToHall = { Ring = 4, Spacing = 5 },
}

-- ---------------------------------------------------------------------
-- 8) GLOBALE NACHRICHTEN & NOTSCHALTER
-- ---------------------------------------------------------------------
Events.MaxGlobalSeconds = 3600 -- globale Nachricht: Until ≤ now + 3600 (sonst verworfen)
Events.GlobalLead = 5 -- globale Nicht-Markt-Events starten so viele Sekunden nach dem Senden (alle Server gleich)
Events.GlobalDedupe = 200 -- Dedupe der letzten 200 Ids
Events.BoostPause = false -- Notschalter (live): persönliche Boosts pausieren (TowerService liest das)
Events.AnnounceGap = 1 -- Mindestabstand zweier Ansagen (s)

-- ---------------------------------------------------------------------
-- 9) ASSET-PLÄTZE (Hybrid, §C14.3; 0 = Code-Rezept aus Parts)
-- ---------------------------------------------------------------------
Events.Assets = {
	Truck = slot(), -- gepanzerter Geldtransporter
	Drone = slot(), -- Liefer-Drohne
	Bull = slot(), -- goldener Bulle (Rally, Parade)
	Bear = slot(), -- freundlicher Part-Bär
	Coin = slot(), -- Neon-Münze (Geldregen)
	Bundle = slot(), -- Geld-Bündel (Transporter)
	Package = slot(), -- Drohnen-Paket
	Orb = slot(), -- Vertrauens-Kugel
	Hologram = slot(), -- Roboter-CEO der Pressekonferenz
	Crane = slot(), -- Bau-Boom-Kran
}

-- =====================================================================
-- PRÜFEN (Config.Validate sammelt das) – leere Liste = alles ok
-- =====================================================================
local KNOWN_ROTATION = { Truck = true, Drones = true, BuildBoom = true, Press = true }
local WEEKLY_KINDS = { PowerHour = true, Reminder = true, AutoShow = true, LeagueFinale = true }

local function isNum(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isInt(value: any): boolean
	return isNum(value) and value % 1 == 0
end

function Events.Validate(_config: any): { string }
	local errors: { string } = {}
	local function add(text: string)
		table.insert(errors, "Config.Events." .. text)
	end
	local function positive(path: string, value: any)
		if not isNum(value) or value <= 0 then
			add(path .. ": Zahl > 0 erwartet")
		end
	end
	local function range(path: string, value: any)
		if type(value) ~= "table" or not isNum(value[1]) or not isNum(value[2]) or value[1] > value[2] then
			add(path .. ": { min, max } mit min ≤ max erwartet")
		end
	end

	-- 1) Rotation + Welt-Events
	if type(Events.Rotation) ~= "table" or #Events.Rotation < 1 or #Events.Rotation > 4 then
		add("Rotation: 1 … 4 Einträge erwartet")
	else
		local seen: { [string]: boolean } = {}
		for _, kind in ipairs(Events.Rotation) do
			if not KNOWN_ROTATION[kind] or seen[kind] then
				add("Rotation: unbekannter oder doppelter Eintrag " .. tostring(kind))
			end
			seen[kind] = true
		end
	end
	if not isInt(Events.WorldMinute) or Events.WorldMinute < 1 or Events.WorldMinute > 18 then
		add("WorldMinute: 1 … 18 erwartet")
	end
	if not isInt(Events.Truck.Bundles) or Events.Truck.Bundles < 1 or Events.Truck.Bundles > 60 then
		add("Truck.Bundles: 1 … 60 erwartet")
	end
	for _, key in ipairs({ "IncomeSeconds", "Seconds", "Lateral", "Linger" }) do
		positive("Truck." .. key, (Events.Truck :: any)[key])
	end
	if not isInt(Events.Drones.Packages) or Events.Drones.Packages < 1 or Events.Drones.Packages > 30 then
		add("Drones.Packages: 1 … 30 erwartet")
	end
	for _, key in ipairs({ "IncomeSeconds", "Seconds", "DropSeconds", "Spread" }) do
		positive("Drones." .. key, (Events.Drones :: any)[key])
	end
	if not isNum(Events.BuildBoom.Pct) or Events.BuildBoom.Pct <= 0 or Events.BuildBoom.Pct >= 1 then
		add("BuildBoom.Pct: 0 < x < 1 erwartet")
	end
	positive("BuildBoom.Seconds", Events.BuildBoom.Seconds)
	local press = Events.Press
	positive("Press.Seconds", press.Seconds)
	positive("Press.QuizXp", press.QuizXp)
	if not isInt(press.Questions) or press.Questions < 1 or press.Questions > #press.Quiz then
		add("Press.Questions: 1 … #Quiz erwartet")
	end
	if not isInt(press.PassCorrect) or press.PassCorrect < 1 or press.PassCorrect > press.Questions then
		add("Press.PassCorrect: 1 … Questions erwartet")
	end
	local quizIds: { [number]: boolean } = {}
	for index, q in ipairs(press.Quiz) do
		if not isInt(q.Id) or quizIds[q.Id] then
			add(("Press.Quiz[%d].Id: eindeutige ganze Zahl erwartet"):format(index))
		else
			quizIds[q.Id] = true
		end
		if not isInt(q.Correct) or q.Correct < 1 or q.Correct > 3 then
			add(("Press.Quiz[%d].Correct: 1 … 3 erwartet"):format(index))
		end
	end

	-- 2) Stündlich
	local bell = Events.BellMoment
	if not isInt(bell.MinPlayers) or bell.MinPlayers < 1 then
		add("BellMoment.MinPlayers: ganze Zahl ≥ 1 erwartet")
	end
	if not isNum(bell.Mult) or bell.Mult < 1 or bell.Mult > 1.5 then
		add("BellMoment.Mult: 1 … 1,5 erwartet")
	end
	for _, key in ipairs({ "Seconds", "DayEvery", "WindowSeconds", "ZoneRadius" }) do
		positive("BellMoment." .. key, (bell :: any)[key])
	end
	local sky = Events.SkyShow
	for _, key in ipairs({ "RespektMult", "Seconds", "ShowSeconds", "DayEvery" }) do
		positive("SkyShow." .. key, (sky :: any)[key])
	end
	if not isInt(sky.Minute) or sky.Minute < 0 or sky.Minute > 19 then
		add("SkyShow.Minute: 0 … 19 erwartet")
	end

	-- 3) Bär/Bulle
	local bear = Events.Bear
	for _, key in ipairs({ "OrbsPerPlayer", "GoalPerPlayer", "RewardMinutes", "Seconds", "OrbsMaxPerPlayer" }) do
		positive("Bear." .. key, (bear :: any)[key])
	end
	if not isNum(bear.RadiusMin) or not isNum(bear.RadiusMax) or bear.RadiusMin >= bear.RadiusMax then
		add("Bear.RadiusMin/RadiusMax: min < max erwartet")
	end
	for _, key in ipairs({ "Seconds", "TouchRange", "BonusSeconds" }) do
		positive("GoldenBull." .. key, (Events.GoldenBull :: any)[key])
	end

	-- 4/5) Shows, Geldregen, Pickups
	positive("Parade.Bulls", Events.Parade.Bulls)
	positive("Parade.LapSeconds", Events.Parade.LapSeconds)
	positive("Fireworks.Seconds", Events.Fireworks.Seconds)
	if not isInt(Events.RainCoinsMax) or Events.RainCoinsMax < 1 or Events.RainCoinsMax > 30 then
		add("RainCoinsMax: 1 … 30 erwartet (§B15.3)")
	end
	positive("RainCoinMinutes", Events.RainCoinMinutes)
	positive("MoneyRain.FallSeconds", Events.MoneyRain.FallSeconds)
	if not isNum(Events.MoneyRain.NearShare) or Events.MoneyRain.NearShare < 0 or Events.MoneyRain.NearShare > 1 then
		add("MoneyRain.NearShare: 0 … 1 erwartet")
	end
	positive("PickupRange", Events.PickupRange)
	if not isInt(Events.PickupMaxPerPlayer) or Events.PickupMaxPerPlayer < 10 or Events.PickupMaxPerPlayer > 60 then
		add("PickupMaxPerPlayer: 10 … 60 erwartet (§C16)")
	end
	if not isInt(Events.MinPickupCredits) or Events.MinPickupCredits < 0 then
		add("MinPickupCredits: ganze Zahl ≥ 0 erwartet")
	end

	-- 6) Wochen-Kalender
	local weeklyKeys: { [string]: boolean } = {}
	for index, entry in ipairs(Events.Weekly) do
		local where = ("Weekly[%d]"):format(index)
		if type(entry.Key) ~= "string" or weeklyKeys[entry.Key] then
			add(where .. ".Key: eindeutiger Text erwartet")
		else
			weeklyKeys[entry.Key] = true
		end
		if entry.Dow ~= nil and (not isInt(entry.Dow) or entry.Dow < 1 or entry.Dow > 7) then
			add(where .. ".Dow: 1 … 7 oder leer (täglich) erwartet")
		end
		if
			not isInt(entry.HH)
			or entry.HH < 0
			or entry.HH > 23
			or not isInt(entry.MM)
			or entry.MM < 0
			or entry.MM > 59
		then
			add(where .. ": HH 0 … 23 und MM 0 … 59 erwartet")
		end
		if not WEEKLY_KINDS[entry.Kind] then
			add(where .. ".Kind: PowerHour/Reminder/AutoShow/LeagueFinale erwartet")
		end
		if type(entry.Args) ~= "table" then
			add(where .. ".Args: Tabelle erwartet")
		end
	end

	-- 7) Katalog + Grenzen
	if #Events.Catalogue ~= 21 then
		add(("Catalogue: 21 Admin-Abuse-Events erwartet (§B15.3), gefunden %d"):format(#Events.Catalogue))
	end
	local catKeys: { [string]: boolean } = {}
	for index, entry in ipairs(Events.Catalogue) do
		if type(entry.Key) ~= "string" or catKeys[entry.Key] then
			add(("Catalogue[%d].Key: eindeutiger Text erwartet"):format(index))
		else
			catKeys[entry.Key] = true
		end
		if type(entry.Market) ~= "boolean" then
			add(("Catalogue[%d].Market: true/false erwartet"):format(index))
		end
	end
	local limits = Events.AdminLimits
	for _, key in ipairs({ "MarketStrength", "Ramp", "DecayMinutes", "HaltSeconds", "Vol", "VolMinutes", "NewsBand" }) do
		range("AdminLimits." .. key, (limits :: any)[key])
	end
	if isNum(limits.MarketStrength[2]) and limits.MarketStrength[2] > 50 then
		add("AdminLimits.MarketStrength: höchstens 50 % (§B15.3)")
	end
	range("AdminLimits.MoneyRain.Seconds", limits.MoneyRain.Seconds)
	range("AdminLimits.GoldenHour.Mult", limits.GoldenHour.Mult)
	range("AdminLimits.GoldenHour.Minutes", limits.GoldenHour.Minutes)
	range("AdminLimits.XpRush.Minutes", limits.XpRush.Minutes)
	range("AdminLimits.Boss.Seconds", limits.Boss.Seconds)
	if isNum(limits.GoldenHour.Mult[2]) and limits.GoldenHour.Mult[2] > 3 then
		add("AdminLimits.GoldenHour.Mult: höchstens ×3 (Deckel Config.Tower.Mult.EventMax)")
	end
	positive("AdminLimits.NewsChars", limits.NewsChars)
	positive("AdminLimits.CrashWarnSeconds", limits.CrashWarnSeconds)
	positive("AdminLimits.BuildBoom.Minutes", limits.BuildBoom.Minutes)
	positive("AdminLimits.Boss.Count", limits.Boss.Count)

	-- 8) Global
	if not isNum(Events.MaxGlobalSeconds) or Events.MaxGlobalSeconds < 60 or Events.MaxGlobalSeconds > 3600 then
		add("MaxGlobalSeconds: 60 … 3600 erwartet (§C13)")
	end
	positive("GlobalLead", Events.GlobalLead)
	if not isInt(Events.GlobalDedupe) or Events.GlobalDedupe < 50 then
		add("GlobalDedupe: ganze Zahl ≥ 50 erwartet")
	end
	if type(Events.BoostPause) ~= "boolean" then
		add("BoostPause: true/false erwartet")
	end
	if type(Events.LeagueBoard) ~= "string" then
		add("LeagueBoard: Text erwartet")
	end
	return errors
end

return Events
