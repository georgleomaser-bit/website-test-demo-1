-- =====================================================================
--  CLUTCH CLASH – Sicherheit, Anti-Cheat & Admin-Grenzen (Config.Security)
--  Besitzer: WP7 (Sicherheit, Admin, Live-Balance). Vertrag: DESIGN.md C15 + C12 + B25.
--  Wird an alle Clients repliziert -> KEINE Geheimnisse hier!
--
--  Abschnitte:
--    1) Bewegungs-Prüfung (C12.3)          5 Hz, Weg-Budget, Teleport-Gnade, Höhe, Fliegen
--    2) Verdachtspunkte (C12.4)            Gewichte, Abbau, Prüf-Flag, Kick, Auto-Bann (nur harte Signale)
--    3) Statistik-Prüfung                  Kopf-Quote/Genauigkeit -> nur Prüfliste, NIE Bann
--    4) Spam-Bremsen                       Token-Eimer/Rate-Limits pro Remote
--    5) Moderation & Banns (B25.4)          Melden, Bann-Dauern, Speicher-Grenzen
--    6) Admin-Panel (B25.3)                Text-Längen, Kraft-Grenzen, Events
--  Validate(Config): { string }            prüft alle Zahlen (SelfTest / Boot-warn)
--
--  Zusätzlich zu C15 (nur WP7 liest sie): Weights.Noclip, ImpulseMaxSpeed, ImpulseGrace, FlagsLocalMax,
--  StoreMaxPerKey, StoreWritesPerMinute, StoreReadGap, BanLogMax, BanDisplayMax, BanPrivateMax,
--  Powers (Grenzen der Admin-Kräfte), LobbyGravity, AutoBan.Keep, RateBurstPerMinute, LosBurstPerMinute,
--  FlagCooldown, AnchorRadius, HistoryVersions, MutatorGlobalHours.
-- =====================================================================

local Security = {
	-- -----------------------------------------------------------------
	-- 1) BEWEGUNG (C12.3) – Server misst 5x pro Sekunde (gestaffelt)
	-- -----------------------------------------------------------------
	MoveHz = 5,
	BaseAllowedSpeed = 32, -- schnellstes legales Tempo (Rutsch-Start)
	SpeedTolerance = 1.15, -- erlaubtes Tempo = 32 × SpeedMult × 1.15 + 6
	SpeedSlack = 6,
	BucketSeconds = 1.0, -- Weg-Vorrat = so viele Sekunden erlaubtes Tempo
	TeleportGrace = 1.0, -- Sekunden Gnade nach jedem Server-Teleport
	TeleportMaxDist = 40, -- Sprung > 40 Studs ohne Gnade = Teleport-Verstoß (hart)
	VerticalSlack = 3, -- Höhe über letztem Boden ≤ 7.2 × (Luftsprünge + 1) × VerticalMult + 3
	FlyAirSeconds = 3, -- länger in der Luft ohne zu fallen = Fliegen
	FlyAirSecondsMoon = 6, -- Mondsprung-Mutator
	ImpulseMaxSpeed = 95, -- Standard-Höchsttempo während Grace("Impulse"/"Launch")
	ImpulseGrace = 1.5, -- Standard-Dauer, wenn Grace ohne Sekunden kommt
	AnchorRadius = 30, -- während der Teleport-Gnade zählen nur Positionen so nah am Ziel

	-- -----------------------------------------------------------------
	-- 2) VERDACHTSPUNKTE (C12.4) – Abbau 1 Punkt je 30 s
	-- -----------------------------------------------------------------
	Weights = {
		Honeypot = 100, -- hart
		Type = 5, -- kaputtes Paket
		Rate = 1, -- Feuerraten-Verstoß (je)
		RateBurst = 15, -- > 20 Feuerraten-Verstöße pro Minute (hart)
		Origin = 2, -- Schuss-Ursprung zu weit weg
		Los = 1, -- Sichtlinie durch Wand (je)
		LosBurst = 10, -- > 10 pro Minute
		Mismatch = 10, -- Hitbox-Abweichung > 40 % über 30 Behauptungen
		Speed = 2, -- zu schnell
		Teleport = 8, -- Sprung > 40 Studs (hart)
		Fly = 5, -- Fliegen / zu hoch gesprungen
		Noclip = 2, -- durch eine Wand gelaufen
		Stats = 20, -- Statistik (nur Prüfliste, nie Kick/Bann)
	},
	RateBurstPerMinute = 20,
	LosBurstPerMinute = 10,
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
	-- 3) STATISTIK (nur Prüfliste – Statistik bannt NIE automatisch)
	-- -----------------------------------------------------------------
	Stats = {
		MinHits = 60,
		HeadRatio = 0.75,
		Accuracy = 0.70,
		MismatchClaims = 30,
		MismatchRatio = 0.4,
	},

	-- -----------------------------------------------------------------
	-- 4) SPAM-BREMSEN – { Kapazität, Nachfüllung pro s } bzw. { Aufrufe, Sekunden }
	-- -----------------------------------------------------------------
	Buckets = { Fire = { 12, 20 }, WeaponAction = { 12, 12 }, Look = { 20, 20 } },
	Rates = { Request = { 8, 1 }, Admin = { 12, 1 } },

	-- -----------------------------------------------------------------
	-- 5) MODERATION & BANNS (B25.4, C14)
	-- -----------------------------------------------------------------
	ReportLimit = { 3, 600 }, -- 3 Meldungen pro 10 Minuten pro Melder
	BanPresets = { ["1h"] = 3600, ["1d"] = 86400, ["7d"] = 604800, ["30d"] = 2592000, perm = -1 },
	BanDisplayMax = 400, -- Roblox-Grenze DisplayReason
	BanPrivateMax = 1000, -- Roblox-Grenze PrivateReason
	BanLogMax = 100, -- CC_Mod_v1 / BanLog
	FlagsLocalMax = 200, -- Flags/Meldungen im Speicher dieses Servers
	StoreMaxPerKey = 50, -- Flags bzw. Meldungen pro Shard-Schlüssel und Tag
	StoreWritesPerMinute = 6, -- je Art (Flags / Meldungen)
	StoreReadGap = 0.25, -- Sekunden zwischen zwei Lesungen (Admin-Listen/Statistik)

	-- -----------------------------------------------------------------
	-- 6) ADMIN-PANEL (B25.3)
	-- -----------------------------------------------------------------
	AnnounceMax = 200,
	WarnMax = 150,
	AnnounceSeconds = 8,
	AnnounceQueue = 5,
	AdminAbuseMaxMinutes = 60,
	MutatorGlobalHours = 24, -- globaler Mutator-Override gilt so lange
	HistoryVersions = 10, -- Live-Balance: so viele Versionen im Verlauf
	LobbyGravity = { Min = 50, Max = 196.2 },
	Powers = {
		Speed = { Min = 16, Max = 150 }, -- AdminSpeed
		Jump = { Min = 7.2, Max = 100 }, -- AdminJump (JumpHeight)
		RapidFire = { Min = 1, Max = 5 }, -- AdminRapidFire (Faktor)
		FlySpeed = 70, -- Fliegen (Taste G), Shift = ×2
	},
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

	for _, key in
		ipairs({
			"MoveHz",
			"BaseAllowedSpeed",
			"SpeedTolerance",
			"BucketSeconds",
			"TeleportGrace",
			"TeleportMaxDist",
			"FlyAirSeconds",
			"FlyAirSecondsMoon",
			"ImpulseMaxSpeed",
			"ImpulseGrace",
			"AnchorRadius",
			"DecayEvery",
			"Review",
			"Kick",
			"FlagCooldown",
			"RateBurstPerMinute",
			"LosBurstPerMinute",
			"BanDisplayMax",
			"BanPrivateMax",
			"BanLogMax",
			"FlagsLocalMax",
			"StoreMaxPerKey",
			"StoreWritesPerMinute",
			"StoreReadGap",
			"AnnounceMax",
			"WarnMax",
			"AnnounceSeconds",
			"AnnounceQueue",
			"AdminAbuseMaxMinutes",
			"MutatorGlobalHours",
			"HistoryVersions",
		})
	do
		positive("Config.Security." .. key, (Security :: any)[key])
	end
	if not isNumber(Security.SpeedSlack) or Security.SpeedSlack < 0 then
		table.insert(errors, "Config.Security.SpeedSlack: Zahl ≥ 0 erwartet")
	end
	if not isNumber(Security.VerticalSlack) or Security.VerticalSlack < 0 then
		table.insert(errors, "Config.Security.VerticalSlack: Zahl ≥ 0 erwartet")
	end
	if isNumber(Security.Review) and isNumber(Security.Kick) and Security.Review >= Security.Kick then
		table.insert(errors, "Config.Security.Review: muss kleiner als Kick sein")
	end
	if Security.BanDisplayMax > 400 or Security.BanPrivateMax > 1000 then
		table.insert(errors, "Config.Security.BanDisplayMax/BanPrivateMax: Roblox-Grenzen 400/1000")
	end
	if Security.StoreMaxPerKey > 50 then
		table.insert(errors, "Config.Security.StoreMaxPerKey: höchstens 50 (C14)")
	end
	for key, value in pairs(Security.Weights) do
		if not isNumber(value) or value < 0 then
			table.insert(errors, "Config.Security.Weights." .. tostring(key) .. ": Zahl ≥ 0 erwartet")
		end
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
	for key, value in pairs(Security.Stats) do
		positive("Config.Security.Stats." .. tostring(key), value)
	end
	for key, value in pairs(Security.Buckets) do
		pair("Config.Security.Buckets." .. tostring(key), value)
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
	range("Config.Security.LobbyGravity", Security.LobbyGravity)
	range("Config.Security.Powers.Speed", Security.Powers.Speed)
	range("Config.Security.Powers.Jump", Security.Powers.Jump)
	range("Config.Security.Powers.RapidFire", Security.Powers.RapidFire)
	positive("Config.Security.Powers.FlySpeed", Security.Powers.FlySpeed)
	return errors
end

return Security
