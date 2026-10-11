--!strict
-- =====================================================================
--  CLUTCH CLASH – BOTS & TRAINING (Shared/Config/Bots)
--  Besitzer: WP6 (Bots & Training-Range). Vertrag: DESIGN.md C15 + B10 + B2 (Range).
--  Erreichbar als Config.Bots. Zahlen = Startwerte aus DESIGN.md, 1:1 änderbar.
--  ACHTUNG: wird an alle Clients repliziert -> keine Geheimnisse!
--
--  Inhalt:
--    1) Difficulties   – die 5 Stufen (Tabelle B10.3) + Feinwerte fürs Spielgefühl
--    2) Names          – 30 Bot-Namen (B10.2)
--    3) Loadouts       – Gewichte ab Normal, Gratis-Set für Rookie/Easy
--    4) Gehirn         – Takt, Raycast-Budget, Navigation, Handicap, Adaptiv
--    5) Crown          – Bot-Herausforderer je Serie
--    6) Range          – Übungspuppen, Schiene, Zone, Flick-Test
--    7) Aussehen       – Gesicht, Namensschild, Standard-Animationen (Muss-Regel 2)
--  Validate(Config): { string } prüft alles (leere Liste = ok).
-- =====================================================================

export type Difficulty = {
	-- Pflichtspalten aus B10.3 (Prozentwerte wie in der Tabelle: 3 = 3 %)
	Reaction: number, -- Sekunden bis zum ersten Schuss, nachdem das Ziel sichtbar wurde
	AimErr: number, -- Grad Zielfehler direkt nach dem Erfassen
	Tau: number, -- Sekunden: Zielfehler fällt exponentiell mit dieser Zeitkonstante
	MinErr: number, -- Grad: kleinster Zielfehler
	HeadChance: number, -- % der Feuerstöße, die auf den Kopf zielen
	StrafeMin: number, -- Sekunden zwischen zwei Seitwärts-Wechseln (min)
	StrafeMax: number, -- … (max)
	MoveTech: number, -- % Chance pro Seitwärts-Wechsel zu springen/rutschen (0 = nie)
	UtilityChance: number, -- % Chance, eine Gelegenheit für Granate/Rauch/Heilung zu nutzen
	RetreatHp: number, -- unter so vielen HP zieht sich der Bot zurück (0 = nie)
	SpeedMult: number, -- Tempo-Faktor (Gehen/Sprinten)
	-- Feinwerte (machen die Stufen fühlbar verschieden; nicht in der Spec-Tabelle)
	Fov: number, -- Sichtkegel in Grad (ganzer Winkel); näher als 14 Studs sieht er immer
	Burst: { number }, -- Schüsse pro Feuerstoß {min, max} (Automatik-Waffen)
	BurstPause: { number }, -- Pause zwischen Feuerstößen in s {min, max}
	ClickDelay: { number }, -- Zusatz-Verzögerung bei Halbautomatik/Einzelschuss in s {min, max}
	Lead: number, -- 0..1 Vorhalt bei Projektilwaffen (Rakete)
	Push: boolean, -- drängt nach PushDelay, wenn der Gegner nachlädt (B10.3: Hard/Insane)
	QuickSwap: boolean, -- wechselt beim Nachladen auf die Sekundärwaffe
	PreAim: boolean, -- zielt nach Sichtverlust auf die letzte bekannte Stelle
	Reposition: number, -- 0..1 Chance pro Entscheidungsfenster, eine Deckung zu wechseln
	Wander: number, -- 0..1 Anteil zufälliger Umwege beim Patrouillieren
	UseAds: boolean, -- zielt mit Visier (ADS) auf Distanz
	MeleeChance: number, -- 0..1 Chance, im Nahbereich (≤ MeleeRange) zur Nahkampfwaffe zu greifen
	Level: { number }, -- angezeigtes Level im Namensschild {min, max} (nur Optik)
	PracticeOnly: boolean?, -- nur Practice/Crown (Insane)
}

local Bots = {}

-- ---------------------------------------------------------------------
-- 1) SCHWIERIGKEITSSTUFEN (B10.3) – Reihenfolge = leicht -> schwer
-- ---------------------------------------------------------------------
Bots.Order = { "Rookie", "Easy", "Normal", "Hard", "Insane" }

Bots.Difficulties = {
	Rookie = {
		Reaction = 0.75,
		AimErr = 9,
		Tau = 0.9,
		MinErr = 3.5,
		HeadChance = 3,
		StrafeMin = 1.5,
		StrafeMax = 2.5,
		MoveTech = 0, -- springt/rutscht nie
		UtilityChance = 0,
		RetreatHp = 0, -- zieht sich nie zurück ("–" in der Tabelle)
		SpeedMult = 0.85,
		Fov = 100,
		Burst = { 2, 4 },
		BurstPause = { 0.45, 0.8 },
		ClickDelay = { 0.18, 0.35 },
		Lead = 0,
		Push = false,
		QuickSwap = false,
		PreAim = false,
		Reposition = 0,
		Wander = 0.5,
		UseAds = false,
		MeleeChance = 0.2,
		Level = { 1, 4 },
	},
	Easy = {
		Reaction = 0.55,
		AimErr = 7,
		Tau = 0.7,
		MinErr = 2.5,
		HeadChance = 6,
		StrafeMin = 1.0,
		StrafeMax = 1.8,
		MoveTech = 5,
		UtilityChance = 10,
		RetreatHp = 25,
		SpeedMult = 0.92,
		Fov = 110,
		Burst = { 3, 5 },
		BurstPause = { 0.35, 0.6 },
		ClickDelay = { 0.12, 0.25 },
		Lead = 0.3,
		Push = false,
		QuickSwap = false,
		PreAim = false,
		Reposition = 0.15,
		Wander = 0.35,
		UseAds = true,
		MeleeChance = 0.25,
		Level = { 3, 12 },
	},
	Normal = {
		Reaction = 0.40,
		AimErr = 5,
		Tau = 0.6,
		MinErr = 1.5,
		HeadChance = 12,
		StrafeMin = 0.8,
		StrafeMax = 1.5,
		MoveTech = 10,
		UtilityChance = 25,
		RetreatHp = 35,
		SpeedMult = 1.0,
		Fov = 120,
		Burst = { 4, 7 },
		BurstPause = { 0.25, 0.45 },
		ClickDelay = { 0.06, 0.15 },
		Lead = 0.6,
		Push = false,
		QuickSwap = true,
		PreAim = true,
		Reposition = 0.3,
		Wander = 0.2,
		UseAds = true,
		MeleeChance = 0.3,
		Level = { 8, 25 },
	},
	Hard = {
		Reaction = 0.28,
		AimErr = 3,
		Tau = 0.5,
		MinErr = 0.9,
		HeadChance = 22,
		StrafeMin = 0.6,
		StrafeMax = 1.2,
		MoveTech = 25,
		UtilityChance = 40,
		RetreatHp = 40,
		SpeedMult = 1.0,
		Fov = 140,
		Burst = { 5, 9 },
		BurstPause = { 0.15, 0.3 },
		ClickDelay = { 0.03, 0.09 },
		Lead = 0.85,
		Push = true,
		QuickSwap = true,
		PreAim = true,
		Reposition = 0.5,
		Wander = 0.1,
		UseAds = true,
		MeleeChance = 0.35,
		Level = { 18, 45 },
	},
	Insane = {
		Reaction = 0.19,
		AimErr = 1.8,
		Tau = 0.4,
		MinErr = 0.5,
		HeadChance = 32,
		StrafeMin = 0.5,
		StrafeMax = 1.0,
		MoveTech = 35,
		UtilityChance = 60,
		RetreatHp = 45,
		SpeedMult = 1.0,
		Fov = 160,
		Burst = { 7, 12 },
		BurstPause = { 0.08, 0.2 },
		ClickDelay = { 0.01, 0.05 },
		Lead = 1.0,
		Push = true,
		QuickSwap = true,
		PreAim = true,
		Reposition = 0.6,
		Wander = 0.05,
		UseAds = true,
		MeleeChance = 0.4,
		Level = { 40, 80 },
		PracticeOnly = true, -- nur Practice/Crown
	},
} :: { [string]: Difficulty }

-- ---------------------------------------------------------------------
-- 2) NAMEN (B10.2) – Namensschild "[BOT] Waffel" (grau)
-- ---------------------------------------------------------------------
Bots.Names = {
	"Waffel",
	"Blinky",
	"Pixel",
	"Nudel",
	"Turbo",
	"Gizmo",
	"Sprocket",
	"Murmel",
	"Keks",
	"Bonbon",
	"Kiwi",
	"Fizz",
	"Mochi",
	"Nugget",
	"Zappy",
	"Biscuit",
	"Mango",
	"Pudding",
	"Rakete",
	"Socke",
	"Toffee",
	"Bolzen",
	"Flummi",
	"Knopf",
	"Wolke",
	"Brezel",
	"Zimt",
	"Quark",
	"Kobold",
	"Funke",
}

-- ---------------------------------------------------------------------
-- 3) LOADOUTS (B10.3) – Rookie/Easy nur Gratis-Set (Config.Weapons.DefaultLoadout),
--    ab Normal gewichtet zufällig aus allen 15 (pro Platz nur Waffen dieses Platzes).
--    Gewicht 0 = Bots nehmen die Waffe nie.
-- ---------------------------------------------------------------------
Bots.LoadoutWeights = {
	-- Primär
	PopRifle = 10,
	BuzzSMG = 8,
	BurstBlaster = 7,
	Scatter = 6,
	Longshot = 4,
	PopRocket = 3,
	-- Sekundär
	PipPistol = 10,
	HandCannon = 6,
	MiniScatter = 5,
	-- Nahkampf
	BoxingGloves = 10,
	BonkHammer = 5,
	LaserSword = 5,
	-- Utility
	PopGrenade = 10,
	SmokeBomb = 4,
	MedFizz = 5,
} :: { [string]: number }

Bots.FreeOnly = { Rookie = true, Easy = true } :: { [string]: boolean }

-- ---------------------------------------------------------------------
-- 4) GEHIRN & NAVIGATION (B10.3)
-- ---------------------------------------------------------------------
Bots.TickHz = 10 -- jeder Bot 1× pro 100 ms (gestaffelt über die Frames)
Bots.MaxRaycastsPerTick = 3 -- Sichtlinien-Strahlen pro Bot-Tick
Bots.LateralErrPerStud = 0.15 -- +0.15° Zielfehler pro Stud/s Querbewegung des Ziels
Bots.RepathSeconds = 2 -- Pfad neu planen alle 2 s (oder bei Zielwechsel)
Bots.StuckSeconds = 1.5 -- < 1 Stud in 1.5 s = hängt fest -> springen + neu planen
Bots.StuckMinMove = 1 -- Studs
Bots.UnstickAfter = 2 -- so viele Hänger in Folge -> auf den nächsten Nav-Knoten setzen (≤ 3 s)
Bots.PushDelay = 0.4 -- Hard/Insane drängen, wenn der Gegner so lange nachlädt
Bots.MeleeRange = 12 -- Studs: Nahkampf-Zustand nur bei Ziel ≤ 12 Studs
Bots.Memory = 4 -- Sekunden: letzte bekannte Position eines Gegners bleibt im Kopf
Bots.HearRange = 80 -- Studs: Schüsse in dieser Nähe verraten die Position
Bots.MaxSight = 400 -- Studs: weiter weg wird niemand wahrgenommen
Bots.RetreatMaxSeconds = 4 -- Rundenmodi: höchstens so lange verstecken, dann wieder kämpfen
Bots.UtilityRollSeconds = 3 -- Abstand zwischen zwei Utility-Würfen
Bots.SwitchCooldown = 0.8 -- s zwischen zwei Waffenwechseln
Bots.WaypointReach = 2.5 -- Studs: Wegpunkt erreicht
Bots.Slide = { Start = 32, End = 14, Time = 0.75 } -- Bot-"Rutschen" = kurzer Tempo-Schub (Hitbox gleich)
Bots.RookieMissShots = 2 -- erste 2 Schüsse jeder Runde gehen absichtlich daneben …
Bots.RookieMatches = 3 -- … in den ersten 3 Matches eines Menschen
Bots.Adaptive = { LossesDown = 2, WinsUp = 3, Range = 1 } -- Data.BotTier = Versatz −1..+1 (WP8 pflegt ihn)
Bots.MmrTiers = { Easy = 900, Hard = 1150 } -- < 900 Easy, 900–1150 Normal, > 1150 Hard

-- ---------------------------------------------------------------------
-- 5) CROWN – Bot-Herausforderer je Serie des Königs (B4)
-- ---------------------------------------------------------------------
Bots.CrownTiers = {
	{ MaxStreak = 2, Diff = "Normal" },
	{ MaxStreak = 5, Diff = "Hard" },
	{ MaxStreak = 1e9, Diff = "Insane" },
}

-- ---------------------------------------------------------------------
-- 6) RANGE (Schießstand B2) – 24 Puppen + 2 Schiene-Puppen, Waffen-Regal, Bot-Duell-Kabine
-- ---------------------------------------------------------------------
Bots.Range = {
	DummyHp = 150, -- Leben einer Puppe
	DummyRegenAfter = 3, -- s ohne Schaden -> wieder voll (gepoppte Puppen kommen nach 3 s zurück)
	RailSpeed = 8, -- Studs/s der Schiene-Puppen
	RailFlip = 2, -- spätestens alle 2 s Richtungswechsel …
	RailAmplitude = 5, -- … und immer an den Enden (pendeln Z ±5, B2)
	ScanHz = 4, -- Zone prüfen (betreten/verlassen)
	PlayerReviveDelay = 1.5, -- eigener Raketen-/Granaten-Pop in der Range -> so schnell zurück
	FlickTargets = 10, -- Flick-Test: so viele Ziele nacheinander
	FlickDistance = { 16, 34 }, -- Studs vor der Kamera
	FlickYaw = { 12, 42 }, -- Grad seitlich (zufällige Seite)
	FlickPitch = 12, -- Grad hoch/runter (max)
	FlickRadius = 1.1, -- Zielkugel-Radius
	FlickTimeout = 30, -- s, danach Abbruch
	DpsReset = 3, -- s ohne Treffer -> DPS-Anzeige beginnt neu
	-- Aim-Trainer (SKILL-WUENSCHE): Tracking = Fadenkreuz auf einer wandernden Kugel halten,
	-- Reaktion = schießen, sobald das Ziel erscheint. Bestwerte nur lokal (wie Flick, v1).
	TrackSeconds = 15, -- Dauer eines Tracking-Laufs
	TrackDistance = 24, -- Studs vor der Kamera
	TrackRadius = 1.3, -- Zielkugel-Radius
	TrackSpeed = { 0.6, 1.4 }, -- Winkelgeschwindigkeit der Bahn (rad/s), zufällig pro Lauf
	TrackYaw = 30, -- Grad seitlicher Ausschlag (max)
	TrackPitch = 10, -- Grad hoch/runter (max)
	ReactionRounds = 5, -- so viele Runden, Ergebnis = Durchschnitt
	ReactionDelay = { 1.2, 3.5 }, -- s Wartezeit bis das Ziel erscheint
	ReactionDistance = 20,
	ReactionRadius = 1.4,
	ReactionYaw = 14, -- Grad seitlicher Versatz (max)
	ReactionTimeout = 2.5, -- s ohne Treffer -> Runde zählt als Fehlversuch (= Timeout)
	-- Roster-Slots im Kontext "Range": Spieler/Bots 1..32, Puppen ab DummySlotBase + 1
	-- (Puppen schießen nie und tauchen daher nie als Quelle in FX/LookBatch auf; u8-tauglich)
	DummySlotBase = 200,
	-- Puppen-Farben je Entfernung (Optik)
	DummyDistances = { 15, 30, 60, 100 },
}

-- ---------------------------------------------------------------------
-- 7) AUSSEHEN & ANIMATION (Muss-Regel 2: nur Roblox-Standard-IDs)
-- ---------------------------------------------------------------------
Bots.PoolSize = 12 -- Klone in ServerStorage.BotPool (= MaxBots)
Bots.Face = "rbxasset://textures/face.png"
Bots.NameplateColor = Color3.fromRGB(190, 190, 200) -- grau = ehrlich als Bot markiert
Bots.Animations = {
	Idle = "rbxassetid://507766388",
	Walk = "rbxassetid://507777826",
	Run = "rbxassetid://507767714",
	Jump = "rbxassetid://507765000",
	Fall = "rbxassetid://507767968",
	ToolNone = "rbxassetid://507768375", -- Halte-Pose für die Waffe
}
Bots.AnimateDistance = 260 -- Client spielt Animationen nur bis zu dieser Entfernung

-- ---------------------------------------------------------------------
-- PRÜFEN (Config.Validate sammelt das) – Fehlertexte mit exaktem Pfad
-- ---------------------------------------------------------------------
local REQUIRED_NUMBERS = {
	"Reaction",
	"AimErr",
	"Tau",
	"MinErr",
	"HeadChance",
	"StrafeMin",
	"StrafeMax",
	"MoveTech",
	"UtilityChance",
	"RetreatHp",
	"SpeedMult",
	"Fov",
	"Lead",
	"Reposition",
	"Wander",
	"MeleeChance",
}
local PERCENT_FIELDS = { HeadChance = true, MoveTech = true, UtilityChance = true }
local RANGE_PAIRS = { "Burst", "BurstPause", "ClickDelay", "Level" }
local BOOL_FIELDS = { "Push", "QuickSwap", "PreAim", "UseAds" }

local function isNum(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function Bots.Validate(config: any): { string }
	local errors: { string } = {}
	local function add(msg: string)
		table.insert(errors, msg)
	end

	-- Stufen
	local seen: { [string]: boolean } = {}
	for _, name in ipairs(Bots.Order) do
		seen[name] = true
		local d: any = Bots.Difficulties[name]
		local base = "Config.Bots.Difficulties." .. name
		if type(d) ~= "table" then
			add(base .. ": Tabelle fehlt")
			continue
		end
		for _, field in ipairs(REQUIRED_NUMBERS) do
			local v = d[field]
			if not isNum(v) or v < 0 then
				add(("%s.%s: Zahl ≥ 0 erwartet"):format(base, field))
			elseif PERCENT_FIELDS[field] and v > 100 then
				add(("%s.%s: Prozent 0–100 erwartet"):format(base, field))
			end
		end
		if isNum(d.StrafeMin) and isNum(d.StrafeMax) and d.StrafeMin > d.StrafeMax then
			add(base .. ".StrafeMin: darf nicht größer als StrafeMax sein")
		end
		if isNum(d.Tau) and d.Tau <= 0 then
			add(base .. ".Tau: muss größer als 0 sein")
		end
		if isNum(d.MinErr) and isNum(d.AimErr) and d.MinErr > d.AimErr then
			add(base .. ".MinErr: darf nicht größer als AimErr sein")
		end
		if isNum(d.SpeedMult) and (d.SpeedMult < 0.3 or d.SpeedMult > 2) then
			add(base .. ".SpeedMult: 0.3–2 erwartet")
		end
		for _, field in ipairs({ "Lead", "Reposition", "Wander", "MeleeChance" }) do
			if isNum(d[field]) and d[field] > 1 then
				add(("%s.%s: 0–1 erwartet"):format(base, field))
			end
		end
		for _, field in ipairs(RANGE_PAIRS) do
			local pair = d[field]
			if
				type(pair) ~= "table"
				or not isNum(pair[1])
				or not isNum(pair[2])
				or pair[1] < 0
				or pair[1] > pair[2]
			then
				add(("%s.%s: {min, max} mit 0 ≤ min ≤ max erwartet"):format(base, field))
			end
		end
		if type(d.Burst) == "table" and isNum(d.Burst[1]) and d.Burst[1] < 1 then
			add(base .. ".Burst: mindestens 1 Schuss pro Feuerstoß")
		end
		for _, field in ipairs(BOOL_FIELDS) do
			if type(d[field]) ~= "boolean" then
				add(("%s.%s: true/false erwartet"):format(base, field))
			end
		end
	end
	for name in pairs(Bots.Difficulties) do
		if not seen[name] then
			add("Config.Bots.Difficulties." .. tostring(name) .. ": fehlt in Config.Bots.Order")
		end
	end

	-- Namen
	if #Bots.Names < 12 then
		add("Config.Bots.Names: mindestens 12 Namen erwartet (MaxBots)")
	end
	local names: { [string]: boolean } = {}
	for i, n in ipairs(Bots.Names) do
		if type(n) ~= "string" or n == "" or #n > 20 then
			add(("Config.Bots.Names[%d]: Text (1–20 Zeichen) erwartet"):format(i))
		elseif names[n] then
			add(("Config.Bots.Names[%d]: doppelter Name %s"):format(i, n))
		else
			names[n] = true
		end
	end

	-- Loadout-Gewichte (nur prüfbar, wenn Config.Weapons geladen ist)
	local weaponFn = type(config) == "table" and config.Weapon or nil
	local slotsWithWeight: { [string]: boolean } = {}
	for key, weight in pairs(Bots.LoadoutWeights) do
		local path = "Config.Bots.LoadoutWeights." .. tostring(key)
		if not isNum(weight) or weight < 0 then
			add(path .. ": Gewicht ≥ 0 erwartet")
		end
		if type(weaponFn) == "function" then
			local ok, def = pcall(weaponFn, key)
			if ok and def == nil then
				add(path .. ": unbekannte Waffe")
			elseif ok and type(def) == "table" then
				if def.AdminOnly then
					add(path .. ": Admin-Waffen sind für Bots verboten")
				elseif isNum(weight) and weight > 0 and type(def.Slot) == "string" then
					slotsWithWeight[def.Slot] = true
				end
			end
		end
	end
	if type(weaponFn) == "function" then
		local list = config.Weapons and config.Weapons.List
		if type(list) == "table" and #list > 0 then
			for _, slot in ipairs({ "Primary", "Secondary", "Melee", "Utility" }) do
				if not slotsWithWeight[slot] then
					add("Config.Bots.LoadoutWeights: kein Gewicht > 0 für Platz " .. slot)
				end
			end
		end
	end
	for name, flag in pairs(Bots.FreeOnly) do
		if Bots.Difficulties[name] == nil or type(flag) ~= "boolean" then
			add("Config.Bots.FreeOnly." .. tostring(name) .. ": unbekannte Stufe oder kein true/false")
		end
	end

	-- Gehirn-Zahlen
	local numbers: { [string]: number } = {
		TickHz = 1,
		MaxRaycastsPerTick = 1,
		LateralErrPerStud = 0,
		RepathSeconds = 0.2,
		StuckSeconds = 0.3,
		StuckMinMove = 0,
		UnstickAfter = 1,
		PushDelay = 0,
		MeleeRange = 1,
		Memory = 0,
		HearRange = 0,
		MaxSight = 10,
		RetreatMaxSeconds = 0,
		UtilityRollSeconds = 0.2,
		SwitchCooldown = 0,
		WaypointReach = 0.5,
		RookieMissShots = 0,
		RookieMatches = 0,
		PoolSize = 1,
		AnimateDistance = 10,
	}
	local raw: any = Bots
	for key, min in pairs(numbers) do
		local v = raw[key]
		if not isNum(v) or v < min then
			add(("Config.Bots.%s: Zahl ≥ %s erwartet"):format(key, tostring(min)))
		end
	end
	if isNum(Bots.MaxRaycastsPerTick) and Bots.MaxRaycastsPerTick > 3 then
		add("Config.Bots.MaxRaycastsPerTick: höchstens 3 (Budget C17)")
	end
	for key, v in pairs(Bots.Slide) do
		if not isNum(v) or v <= 0 then
			add("Config.Bots.Slide." .. key .. ": Zahl > 0 erwartet")
		end
	end
	for key, v in pairs(Bots.Adaptive) do
		if not isNum(v) or v < 0 then
			add("Config.Bots.Adaptive." .. key .. ": Zahl ≥ 0 erwartet")
		end
	end
	if not (isNum(Bots.MmrTiers.Easy) and isNum(Bots.MmrTiers.Hard)) or Bots.MmrTiers.Easy > Bots.MmrTiers.Hard then
		add("Config.Bots.MmrTiers: Easy ≤ Hard erwartet")
	end

	-- Crown
	local last = -math.huge
	for i, tier in ipairs(Bots.CrownTiers) do
		local path = ("Config.Bots.CrownTiers[%d]"):format(i)
		if not isNum(tier.MaxStreak) or tier.MaxStreak < last then
			add(path .. ".MaxStreak: aufsteigende Zahl erwartet")
		else
			last = tier.MaxStreak
		end
		if Bots.Difficulties[tier.Diff] == nil then
			add(path .. ".Diff: unbekannte Stufe " .. tostring(tier.Diff))
		end
	end

	-- Range
	local range: any = Bots.Range
	for key, v in pairs(range) do
		local path = "Config.Bots.Range." .. key
		if type(v) == "table" then
			if not isNum(v[1]) or not isNum(v[2]) or v[1] > v[2] or v[1] < 0 then
				add(path .. ": {min, max} erwartet")
			end
		elseif not isNum(v) or v < 0 then
			add(path .. ": Zahl ≥ 0 erwartet")
		end
	end
	if isNum(range.DummyHp) and range.DummyHp < 1 then
		add("Config.Bots.Range.DummyHp: mindestens 1")
	end
	if isNum(range.FlickTargets) and (range.FlickTargets < 1 or range.FlickTargets > 50) then
		add("Config.Bots.Range.FlickTargets: 1–50 erwartet")
	end

	-- Aussehen
	if type(Bots.Face) ~= "string" or string.sub(Bots.Face, 1, 13) ~= "rbxasset://te" then
		add("Config.Bots.Face: rbxasset://textures/… erwartet (ASSETS.md)")
	end
	for key, id in pairs(Bots.Animations) do
		if type(id) ~= "string" or not string.match(id, "^rbxassetid://%d+$") then
			add("Config.Bots.Animations." .. key .. ": rbxassetid://<Zahl> erwartet")
		end
	end
	if typeof(Bots.NameplateColor) ~= "Color3" then
		add("Config.Bots.NameplateColor: Color3 erwartet")
	end
	return errors
end

return Bots
