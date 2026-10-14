-- =====================================================================
--  AKYTEX TYCOON – Sicherheit, Anti-Cheat & Admin-Grenzen (Config.Security)
--  Besitzer: WP1 (Kern & Plattform). Vertrag: DESIGN.md §C14.2 (Security) + §C11 + §B15. Basis: CC Config.Security
--  (Abschnitte Verdacht, Spam-Bremsen, Moderation, Admin übernommen; Schuss-Statistik und Shooter-Bewegung entfernt).
--  Gelesen von: AntiCheatService/AdminService (WP11), PlayerStateService (WP1, Rates.Request), Social-Regeln (WP9).
--  Wird an alle Clients repliziert -> KEINE Geheimnisse hier!
--
--  Abschnitte:
--    1) Bewegungs-Prüfung (§C11.3)        5 Hz gestaffelt, Weg-Budget, Teleport-Gnade, Höhe, Fliegen
--    2) Erlaubnisse                       Auto (Klassen-Deckel), Jetpack, Aufzug/Teleport – Richtwerte für SetAllowance
--    3) Verdachtspunkte                   Gewichte, Abbau, Prüf-Flag, Kick, Auto-Bann (nur harte Signale)
--    4) Spam-Bremsen                      Rates { Aufrufe, Sekunden } je Remote
--    5) Moderation & Banns                Melden, Bann-Dauern, Speicher-Grenzen
--    6) Admin-Panel (§B15)                Text-Längen, Kräfte, Abklingzeiten, Log
--    7) Sozial (§C11.2 Alt-Farming)       Kontoalter, Mindest-Sitzung
--  Validate(Config): { string }           prüft alle Zahlen (SelfTest / Boot-warn)
-- =====================================================================

local Security = {
	-- -----------------------------------------------------------------
	-- 1) BEWEGUNG (§C11.3) – Server misst 5× pro Sekunde (gestaffelt)
	-- -----------------------------------------------------------------
	MoveHz = 5,
	BaseAllowedSpeed = 32, -- schnellstes legales Tempo zu Fuß (Sprint 24 + Puffer)
	SpeedTolerance = 1.15, -- erlaubtes Tempo = 32 × SpeedMult × 1,15 + 6
	SpeedSlack = 6,
	BucketSeconds = 1.0, -- Weg-Vorrat = so viele Sekunden erlaubtes Tempo
	TeleportGrace = 1.0, -- Sekunden Gnade nach jedem Server-Teleport (Aufzug, Tower-Besuch, Schnellreise)
	TeleportMaxDist = 40, -- Sprung > 40 Studs ohne Gnade = Teleport-Verstoß (hart)
	VerticalSlack = 3, -- Höhe über letztem Boden ≤ 7,2 × (Luftsprünge + 1) × VerticalMult + 3
	SkillAirJumps = 0, -- AKYTEX TYCOON hat keinen Doppelsprung (Jetpack über Erlaubnis, Abschnitt 2)
	StallSeconds = 0.6, -- so lange keine neue Position = Lag-Hänger (Sprung danach ist kein harter Teleport)
	StallCredit = 1.5, -- nach einem Hänger zählt höchstens so viel Zeit fürs Weg-Budget
	FlyAirSeconds = 3, -- länger in der Luft ohne zu fallen = Fliegen (ohne Jetpack-Erlaubnis)
	ImpulseMaxSpeed = 95, -- Standard-Höchsttempo während Grace("Impulse"/"Launch")
	ImpulseGrace = 1.5, -- Standard-Dauer, wenn Grace ohne Sekunden kommt
	ImpulseAirSeconds = 3, -- nach der Impuls-Gnade bleibt das Tempo bis zur Landung erlaubt (höchstens so lange)
	AnchorRadius = 30, -- während der Teleport-Gnade zählen nur Positionen so nah am Ziel

	-- -----------------------------------------------------------------
	-- 2) ERLAUBNISSE – wer Fahrzeug-/Jetpack-Werte erhöht, prüft diese Summen (REUSE §7 #20)
	-- -----------------------------------------------------------------
	Allowances = {
		CarSlack = 1.2, -- im Auto: erlaubt = Klassen-Deckel (Config.Vehicles.Classes) × Boost × 1,2
		-- Jetpack aktiv: Untergrenzen – LifestyleService setzt je max(Config.Lifestyle.Jetpack, diesen Wert, MaxHeight-Bedarf
		-- (MaxHeight + 8) / 7,2), aktuell also SetAllowance{ SpeedMult = 1,6, VerticalMult ≈ 17,8 } (≈ 120 Studs Höhe)
		JetpackSpeedMult = 1.5,
		JetpackVerticalMult = 17,
		ElevatorGrace = 1.0, -- Aufzug-Fahrt = Server-Teleport -> NoteTeleport + so viel Gnade
	},

	-- -----------------------------------------------------------------
	-- 3) VERDACHTSPUNKTE – Abbau 1 Punkt je 30 s
	-- -----------------------------------------------------------------
	Weights = {
		Honeypot = 100, -- hart (Remote GrantCash)
		Type = 5, -- kaputtes Paket / falsche Typen
		Rate = 1, -- Spam-Verstoß (je)
		RateBurst = 15, -- > 20 Spam-Verstöße pro Minute (hart)
		Speed = 2, -- zu schnell
		Teleport = 8, -- Sprung > 40 Studs (hart)
		Fly = 5, -- Fliegen / zu hoch
		Car = 4, -- Auto schneller als Klassen-Deckel
		Noclip = 2, -- durch eine Wand gelaufen (lokal versteckte Geometrie wird ignoriert)
	},
	RateBurstPerMinute = 20,
	DecayEvery = 30, -- Sekunden pro abgebautem Punkt
	Review = 25, -- ab hier: Prüf-Flag (gespeichert)
	Kick = 60, -- ab hier: Kick mit Meldung
	FlagCooldown = 300, -- höchstens ein neues Prüf-Flag pro Spieler in so vielen Sekunden
	AutoBan = {
		Enabled = true,
		HardKicks = 3, -- so viele Kicks wegen HARTER Signale …
		WindowDays = 7, -- … in so vielen Tagen …
		Days = 1, -- … = 1-Tages-Bann (Beweis in PrivateReason)
		Keep = 10, -- so viele Kick-Zeitstempel bleiben im Spielstand (Mod.HardKicks)
	},

	-- -----------------------------------------------------------------
	-- 4) SPAM-BREMSEN – { Aufrufe, Sekunden }
	-- -----------------------------------------------------------------
	Rates = { Request = { 8, 1 }, Admin = { 12, 1 } },

	-- -----------------------------------------------------------------
	-- 5) MODERATION & BANNS
	-- -----------------------------------------------------------------
	ReportLimit = { 3, 600 }, -- 3 Meldungen pro 10 Minuten pro Melder
	BanPresets = { ["1h"] = 3600, ["1d"] = 86400, ["7d"] = 604800, ["30d"] = 2592000, perm = -1 },
	BanDisplayMax = 400, -- Roblox-Grenze DisplayReason (Byte)
	BanPrivateMax = 1000, -- Roblox-Grenze PrivateReason (Byte)
	BanLogMax = 100, -- AT_Mod_v1 / BanLog
	FlagsLocalMax = 200, -- Flags/Meldungen im Speicher dieses Servers
	StoreMaxPerKey = 50, -- Flags bzw. Meldungen pro Shard-Schlüssel und Tag
	StoreWritesPerMinute = 6, -- je Art (Flags / Meldungen)
	StoreReadGap = 0.25, -- Sekunden zwischen zwei Lesungen (Admin-Listen/Statistik)

	-- -----------------------------------------------------------------
	-- 6) ADMIN-PANEL (§B15)
	-- -----------------------------------------------------------------
	AnnounceMax = 200,
	AnnounceSeconds = 8,
	AnnounceQueue = 5,
	WarnMax = 150,
	NewsTextMax = 80, -- Admin-Eilmeldung DE/EN je ≤ 80 Zeichen (gefiltert)
	AdminAbuseMaxMinutes = 60,
	AdminLogMax = 500, -- Tab „Moderation“ zeigt die letzten 500 Admin-Aktionen
	MarketActionCooldown = 3, -- Sekunden Abklingzeit je Markt-Aktion
	OwnerTradeBlockSeconds = 120, -- Besitzer-Trades ±120 s um eigene Markt-Events gesperrt
	GroupOwnerCacheSeconds = 600, -- Gruppen-Besitzer (GetGroupInfoAsync) 10 min gecacht
	GlobalDedupe = 200, -- globale Nachrichten: Dedupe der letzten 200 Ids
	ConfirmSeconds = 5, -- globale Aktionen: 5-s-Bestätigung im Panel
	StatsMaxKeys = 64, -- Live-Statistik: höchstens so viele Schlüssel pro Art
	StatsCacheSeconds = 60, -- Admin-Statistik (Shards lesen) so lange zwischenspeichern
	Powers = {
		Speed = { Min = 16, Max = 200 }, -- AdminSpeed (WalkSpeed) und Speed-Geschenk an Spieler (Wunsch 18: 16–200)
		Jump = { Min = 7.2, Max = 100 }, -- AdminJump (JumpHeight) und Sprung-Geschenk
		FlySpeed = 70, -- Fliegen (Taste G), Shift = ×2
		EspMax = 20, -- ESP über Highlights (Budget 31 gesamt)
		GiftMaxMinutes = 120, -- Speed-Geschenk: höchstens so viele Minuten (0 = bis zum Zurücksetzen)
	},

	-- -----------------------------------------------------------------
	-- 7) SOZIAL – Alt-Farming-Bremsen (§C11.2)
	-- -----------------------------------------------------------------
	AccountAgeMin = 3, -- Respekt/Bau-Hilfe erst ab 3 Tagen Kontoalter (Studio: Config.Studio.SkipAccountAge)
	SessionMinForSocial = 600, -- … und ab 10 min Sitzung
}

-- ---------------------------------------------------------------------
-- PRÜFEN (Config.Validate sammelt das) – leere Liste = alles ok
-- ---------------------------------------------------------------------
local function isNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Security.Validate(_config: any): { string }
	local errors: { string } = {}
	local function positive(path: string, value: any)
		if not isNumber(value) or value <= 0 then
			table.insert(errors, path .. ": Zahl > 0 erwartet")
		end
	end
	local function pair(path: string, value: any)
		if type(value) ~= "table" or not isNumber(value[1]) or not isNumber(value[2]) or value[1] <= 0 then
			table.insert(errors, path .. ": { Zahl, Zahl } erwartet")
		end
	end
	local function range(path: string, value: any)
		if type(value) ~= "table" or not isNumber(value.Min) or not isNumber(value.Max) or value.Min > value.Max then
			table.insert(errors, path .. ": { Min, Max } mit Min ≤ Max erwartet")
		end
	end

	for _, key in ipairs({
		"MoveHz",
		"BaseAllowedSpeed",
		"SpeedTolerance",
		"BucketSeconds",
		"TeleportGrace",
		"TeleportMaxDist",
		"StallSeconds",
		"StallCredit",
		"FlyAirSeconds",
		"ImpulseMaxSpeed",
		"ImpulseGrace",
		"ImpulseAirSeconds",
		"AnchorRadius",
		"RateBurstPerMinute",
		"DecayEvery",
		"Review",
		"Kick",
		"FlagCooldown",
		"BanDisplayMax",
		"BanPrivateMax",
		"BanLogMax",
		"FlagsLocalMax",
		"StoreMaxPerKey",
		"StoreWritesPerMinute",
		"StoreReadGap",
		"AnnounceMax",
		"AnnounceSeconds",
		"AnnounceQueue",
		"WarnMax",
		"NewsTextMax",
		"AdminAbuseMaxMinutes",
		"AdminLogMax",
		"MarketActionCooldown",
		"OwnerTradeBlockSeconds",
		"GroupOwnerCacheSeconds",
		"GlobalDedupe",
		"ConfirmSeconds",
		"StatsMaxKeys",
		"StatsCacheSeconds",
		"AccountAgeMin",
		"SessionMinForSocial",
	}) do
		positive("Config.Security." .. key, (Security :: any)[key])
	end
	if not isNumber(Security.SpeedSlack) or Security.SpeedSlack < 0 then
		table.insert(errors, "Config.Security.SpeedSlack: Zahl ≥ 0 erwartet")
	end
	if not isNumber(Security.VerticalSlack) or Security.VerticalSlack < 0 then
		table.insert(errors, "Config.Security.VerticalSlack: Zahl ≥ 0 erwartet")
	end
	if not isNumber(Security.SkillAirJumps) or Security.SkillAirJumps < 0 or Security.SkillAirJumps > 5 then
		table.insert(errors, "Config.Security.SkillAirJumps: Zahl 0–5 erwartet")
	end
	if isNumber(Security.Review) and isNumber(Security.Kick) and Security.Review >= Security.Kick then
		table.insert(errors, "Config.Security.Review: muss kleiner als Kick sein")
	end
	if Security.BanDisplayMax > 400 or Security.BanPrivateMax > 1000 then
		table.insert(errors, "Config.Security.BanDisplayMax/BanPrivateMax: Roblox-Grenzen 400/1000")
	end
	if Security.StoreMaxPerKey > 50 then
		table.insert(errors, "Config.Security.StoreMaxPerKey: höchstens 50")
	end
	if Security.AnnounceMax > 500 then
		table.insert(errors, "Config.Security.AnnounceMax: höchstens 500 (Notify-Grenze)")
	end
	for key, value in pairs(Security.Allowances) do
		positive("Config.Security.Allowances." .. tostring(key), value)
	end
	for key, value in pairs(Security.Weights) do
		if not isNumber(value) or value < 0 then
			table.insert(errors, "Config.Security.Weights." .. tostring(key) .. ": Zahl ≥ 0 erwartet")
		end
	end
	if Security.Weights.Honeypot < Security.Kick then
		table.insert(errors, "Config.Security.Weights.Honeypot: muss ≥ Kick sein (Honeypot = sofort Kick)")
	end
	local auto = Security.AutoBan
	if type(auto.Enabled) ~= "boolean" then
		table.insert(errors, "Config.Security.AutoBan.Enabled: true/false erwartet")
	end
	positive("Config.Security.AutoBan.HardKicks", auto.HardKicks)
	positive("Config.Security.AutoBan.WindowDays", auto.WindowDays)
	positive("Config.Security.AutoBan.Days", auto.Days)
	positive("Config.Security.AutoBan.Keep", auto.Keep)
	if isNumber(auto.Keep) and isNumber(auto.HardKicks) and auto.Keep < auto.HardKicks then
		table.insert(errors, "Config.Security.AutoBan.Keep: muss ≥ HardKicks sein")
	end
	for key, value in pairs(Security.Rates) do
		pair("Config.Security.Rates." .. tostring(key), value)
	end
	pair("Config.Security.ReportLimit", Security.ReportLimit)
	for key, value in pairs(Security.BanPresets) do
		if not isNumber(value) or (value ~= -1 and value < 60) then
			table.insert(errors, "Config.Security.BanPresets." .. tostring(key) .. ": Sekunden ≥ 60 oder -1 erwartet")
		end
	end
	range("Config.Security.Powers.Speed", Security.Powers.Speed)
	range("Config.Security.Powers.Jump", Security.Powers.Jump)
	positive("Config.Security.Powers.FlySpeed", Security.Powers.FlySpeed)
	positive("Config.Security.Powers.GiftMaxMinutes", Security.Powers.GiftMaxMinutes)
	if isNumber(Security.Powers.Speed.Max) and Security.Powers.Speed.Max * Security.SpeedTolerance > 500 then
		table.insert(errors, "Config.Security.Powers.Speed.Max: zu hoch für die Anti-Cheat-Obergrenze (600 Studs/s)")
	end
	positive("Config.Security.Powers.EspMax", Security.Powers.EspMax)
	if isNumber(Security.Powers.EspMax) and Security.Powers.EspMax > 31 then
		table.insert(errors, "Config.Security.Powers.EspMax: höchstens 31 (Highlight-Budget)")
	end
	return errors
end

return Security
