--!strict
-- =====================================================================
--  CLUTCH CLASH – MODI, MUTATOREN, MATCH-TIMER, WARTESCHLANGEN (Shared/Config/Modes)
--  Besitzer: WP5 (Match & Warteschlangen). Vertrag: DESIGN.md C15 (Config/Modes), B3–B7.
--  -> erreichbar als Config.Modes
--
--  Abschnitte:
--    1) Modes        – alle 8 Modi (B4): Teams, Regelwerk, Siegbedingung, Zeiten, Kartenwahl, Bots
--    2) Mutators     – 8 Mutatoren (B7) mit partiellen ContextRules
--    3) Rotation     – Tages-Mutator = Rotation[(Util.UtcDay() % #Rotation) + 1]
--    4) DefaultRules – Grund-Regeln jedes Match-Kontexts (Types.ContextRules)
--    5) Match        – Timer der Zustandsmaschine (B5/B6), AFK, Verlassen
--    6) Queue        – Pads, Matcher, Bot-Füllung, Neulings-Schutz, Krone (B3/B4)
--    7) Tutorial     – Tutorial-Duell (B1.1)
--    8) Skill        – Skill-Momente (DOUBLE/TRIPLE/QUAD, CLUTCH-Bonus-XP) aus docs/SKILL-WUENSCHE.md
--  Alle Zahlen sind Startwerte aus DESIGN.md – hier änderbar, ohne Code anzufassen.
--  Validate(Config): { string } prüft alles (SelfTest + Boot-warn).
-- =====================================================================

local Modes = {}

export type ModeDef = {
	Name: { de: string, en: string },
	Teams: number, -- 2 = Rundenmodus mit zwei Teams, 0 = jeder für sich (FFA)
	TeamSize: number,
	MaxPlayers: number?,
	Ruleset: "Rounds" | "Respawn",
	RoundsToWin: number?,
	RoundTime: number?,
	Overtime: number?,
	RoundCap: number?,
	Vote: boolean,
	Bots: boolean?,
	UsesMutator: boolean?,
	FixedMap: string?,
	AlwaysBot: boolean?,
	RandomMap: boolean?,
	Queue: boolean, -- über Pads/PLAY-Menü in eine virtuelle Schlange
	Order: number, -- Reihenfolge im PLAY-Menü
	Rewards: { XpMult: number, CoinMult: number, MasteryMult: number }?,
	ScoreToWin: number?,
	KillPoints: number?,
	AssistPoints: number?,
	MatchTime: number?,
	RespawnDelay: number?,
	FillTo: number?,
	DropInUntil: number?,
	MinPlayers: number?,
}

-- ---------------------------------------------------------------------
-- 1) MODI (B4) – Name, Teams, Regelwerk, Sieg, Rundenzeit, Overtime, Rundenlimit, Kartenwahl, Bots
--    RoundCap = 2 × RoundsToWin + 1 (B6.4)
-- ---------------------------------------------------------------------
local MODES: { [string]: ModeDef } = {
	Duel1 = {
		Name = { de = "Duell 1v1", en = "Duel 1v1" },
		Teams = 2,
		TeamSize = 1,
		Ruleset = "Rounds",
		RoundsToWin = 4,
		RoundTime = 60,
		Overtime = 15,
		RoundCap = 9,
		Vote = true,
		Bots = true,
		Queue = true,
		Order = 1,
	},
	Duel2 = {
		Name = { de = "Duell 2v2", en = "Duel 2v2" },
		Teams = 2,
		TeamSize = 2,
		Ruleset = "Rounds",
		RoundsToWin = 4,
		RoundTime = 75,
		Overtime = 15,
		RoundCap = 9,
		Vote = true,
		Bots = true,
		Queue = true,
		Order = 2,
	},
	Duel3 = {
		Name = { de = "Duell 3v3", en = "Duel 3v3" },
		Teams = 2,
		TeamSize = 3,
		Ruleset = "Rounds",
		RoundsToWin = 4,
		RoundTime = 90,
		Overtime = 15,
		RoundCap = 9,
		Vote = true,
		Bots = true,
		Queue = true,
		Order = 3,
	},
	Duel4 = {
		Name = { de = "Duell 4v4", en = "Duel 4v4" },
		Teams = 2,
		TeamSize = 4,
		Ruleset = "Rounds",
		RoundsToWin = 4,
		RoundTime = 90,
		Overtime = 15,
		RoundCap = 9,
		Vote = true,
		Bots = true,
		Queue = true,
		Order = 4,
	},
	Mutator = {
		Name = { de = "Mutator-Duell", en = "Mutator Duel" },
		Teams = 2,
		TeamSize = 1,
		Ruleset = "Rounds",
		RoundsToWin = 3,
		RoundTime = 50,
		Overtime = 15,
		RoundCap = 7,
		Vote = true,
		Bots = true,
		UsesMutator = true,
		Queue = true,
		Order = 5,
	},
	Crown = {
		Name = { de = "Kronen-Duell", en = "Crown Duel" },
		Teams = 2,
		TeamSize = 1,
		Ruleset = "Rounds",
		RoundsToWin = 2,
		RoundTime = 45,
		Overtime = 10,
		RoundCap = 5,
		Vote = false,
		Bots = true,
		FixedMap = "CrownRing",
		Queue = false, -- eigene Herausforderer-Linie (QueueService.CrownJoin)
		Order = 7,
	},
	Practice = {
		Name = { de = "Training gegen Bots", en = "Bot Practice" },
		Teams = 2,
		TeamSize = 1,
		Ruleset = "Rounds",
		RoundsToWin = 3,
		RoundTime = 60,
		Overtime = 15,
		RoundCap = 7,
		Vote = false,
		AlwaysBot = true,
		RandomMap = true, -- zufällige 1v1-Map
		Queue = false, -- startet sofort (Request "PracticeStart")
		Order = 8,
		Rewards = { XpMult = 0.3, CoinMult = 0, MasteryMult = 0.5 },
	},
	FFA = {
		Name = { de = "FFA-Brawl", en = "FFA Brawl" },
		Teams = 0,
		TeamSize = 1,
		MaxPlayers = 8,
		MinPlayers = 2,
		Ruleset = "Respawn",
		ScoreToWin = 25,
		KillPoints = 2,
		AssistPoints = 1,
		MatchTime = 300,
		RespawnDelay = 3,
		FillTo = 6,
		DropInUntil = 240, -- Drop-in nur in den ersten 4:00
		Vote = true,
		Bots = true,
		Queue = true,
		Order = 6,
	},
}
Modes.Modes = MODES

-- Reihenfolge der Modi (PLAY-Menü, Tests)
Modes.Order = { "Duel1", "Duel2", "Duel3", "Duel4", "Mutator", "FFA", "Crown", "Practice" }

-- ---------------------------------------------------------------------
-- 2) MUTATOREN (B7) – Rules = partielle ContextRules (überschreiben DefaultRules)
-- ---------------------------------------------------------------------
export type MutatorDef = {
	Name: { de: string, en: string },
	Desc: { de: string, en: string },
	Rules: { [string]: any },
}

local MUTATORS: { [string]: MutatorDef } = {
	MoonJump = {
		Name = { de = "Mondsprung", en = "Moon Jump" },
		Desc = { de = "Fast schwerelos – springe über alles!", en = "Almost weightless – jump over everything!" },
		Rules = { GravityLift = 0.55 },
	},
	HeadsOnly = {
		Name = { de = "Nur Kopftreffer", en = "Headshots Only" },
		Desc = {
			de = "Nur Kopftreffer machen Schaden. Nahkampf und Explosionen wirken normal.",
			en = "Only headshots deal damage. Melee and explosions work normally.",
		},
		Rules = { HeadOnly = true },
	},
	BigHeads = {
		Name = { de = "Großkopf", en = "Big Heads" },
		Desc = { de = "Riesige Köpfe – leichter zu treffen!", en = "Huge heads – easier to hit!" },
		Rules = { HeadRadiusMult = 1.6 },
	},
	Turbo = {
		Name = { de = "Turbo", en = "Turbo" },
		Desc = {
			de = "Schneller laufen, schneller schießen, schneller nachladen.",
			en = "Run faster, shoot faster, reload faster.",
		},
		Rules = { SpeedMult = 1.35, IntervalMult = 0.8, ReloadMult = 0.7 },
	},
	MeleeMayhem = {
		Name = { de = "Nahkampf-Chaos", en = "Melee Mayhem" },
		Desc = { de = "Nur Nahkampf und Utility – ran an den Gegner!", en = "Melee and utility only – get close!" },
		Rules = { AllowedSlots = { Melee = true, Utility = true }, SpeedMult = 1.2 },
	},
	SnipersOnly = {
		Name = { de = "Nur Scharfschützen", en = "Snipers Only" },
		Desc = { de = "Fernschuss für alle. Ein Treffer zählt!", en = "Longshots for everyone. Every hit counts!" },
		Rules = {
			ForcedLoadout = {
				Primary = "Longshot",
				Secondary = "HandCannon",
				Melee = "BoxingGloves",
				Utility = "SmokeBomb",
			},
			IgnoreOwnership = true,
		},
	},
	LuckyLoadout = {
		Name = { de = "Glücks-Loadout", en = "Lucky Loadout" },
		Desc = {
			de = "Jede Runde ein zufälliges Loadout – für beide Seiten gleich. Gratis-Probe!",
			en = "A random loadout every round – the same for both sides. Free trial!",
		},
		Rules = { RandomLoadout = true, IgnoreOwnership = true },
	},
	Instapop = {
		Name = { de = "Sofort-Pop", en = "Instapop" },
		Desc = {
			de = "Fünffacher Schaden – ein Treffer, ein Pop!",
			en = "Five times the damage – one hit, one pop!",
		},
		Rules = {
			ForcedLoadout = {
				Primary = "Longshot",
				Secondary = "PipPistol",
				Melee = "BoxingGloves",
				Utility = "PopGrenade",
			},
			DamageMult = 5,
			IgnoreOwnership = true,
		},
	},
}
Modes.Mutators = MUTATORS

-- ---------------------------------------------------------------------
-- 3) ROTATION – Tages-Mutator (Admin-Override lokal oder global möglich)
-- ---------------------------------------------------------------------
Modes.Rotation =
	{ "MoonJump", "HeadsOnly", "Turbo", "BigHeads", "MeleeMayhem", "SnipersOnly", "LuckyLoadout", "Instapop" }

-- ---------------------------------------------------------------------
-- 4) GRUND-REGELN jedes Match-Kontexts (Types.ContextRules)
--    Modus-Besonderheiten: FFA -> Regen + Utility-Abklingzeit, Practice/Tutorial -> jede Waffe erlaubt.
-- ---------------------------------------------------------------------
Modes.DefaultRules = {
	DamageMult = 1,
	HeadOnly = false,
	HeadRadiusMult = 1,
	IntervalMult = 1,
	ReloadMult = 1,
	SpeedMult = 1,
	GravityLift = 0,
	RandomLoadout = false,
	Regen = false,
	UtilityMode = "Charges",
	FriendlyFire = false,
	IgnoreOwnership = false,
}
Modes.ModeRules = {
	FFA = { Regen = true, UtilityMode = "Cooldown" },
	Practice = { IgnoreOwnership = true },
} :: { [string]: { [string]: any } }

-- ---------------------------------------------------------------------
-- 5) MATCH – Zustandsmaschine (B5/B6), AFK und Verlassen
-- ---------------------------------------------------------------------
Modes.Match = {
	VoteSeconds = 5, -- Kartenwahl (Spieler bleiben in der Lobby)
	BotVoteMin = 1, -- Bots stimmen nach 1–3 s zufällig
	BotVoteMax = 3,
	LoadTimeout = 4, -- weiter, wenn alle Menschen "ArenaReady" gesendet haben oder nach 4 s
	ArenaWait = 10, -- kein freier Slot beim Laden: so lange neu versuchen, dann abbrechen
	IntroSeconds = 2,
	FirstPrep = 4, -- Prep Runde 1 (und Rematch)
	Prep = 3, -- Prep ab Runde 2
	ReadyMinPrep = 1, -- alle Menschen "BEREIT" -> Prep endet nach ≥ 1 s
	RoundEnd = 2.5,
	Results = 10, -- Ergebnis-Bildschirm
	CrownResults = 4, -- Krone: kurzer Ergebnis-Bildschirm, damit der König schnell weiterkämpft
	ZoneRadius = 8,
	ZoneCapture = 3, -- 3 s halten = Rundensieg
	ZoneDecay = 0.5, -- −0.5/s wenn leer
	ZoneHeight = 10, -- Höhen-Toleranz der Zone (Studs über/unter dem Mittelpunkt)
	SuddenDeath = 30,
	SuddenDeathHp = 50,
	AfkWarn = 20,
	AfkKick = 30,
	AfkMoveStuds = 2, -- weniger Bewegung = "ohne Eingabe"
	LeaverCooldown = 60, -- Pad-Sperre nach Verlassen
	LeaverBotDelay = 10, -- Team-Modi: Bot ersetzt nach 10 s
	RecentMaps = 2, -- nie die letzten 2 Maps dieses Servers für diesen Modus
	ZoneHz = 5,
	SpawnLift = 3, -- Teleport an Spawns +3 Y
	FfaSpawnCandidates = 8, -- Respawn-Wertung: beste von 8 Kandidaten
	FfaSightPenalty = 40, -- minDist − 40 × (Gegner mit Sicht)
	FfaFillEvery = 2, -- FFA: höchstens alle 2 s einen Bot nachfüllen
	CrownEdgeX = 60, -- Verlierer an den Rand der Grube (Lobby-Ebene)
	CrownEdgeZ = 16,
	ArenaLobbyY = 3,
}

-- ---------------------------------------------------------------------
-- 6) WARTESCHLANGEN & PADS (B3) + KRONE (B4)
-- ---------------------------------------------------------------------
Modes.Queue = {
	BotFillSeconds = 8, -- Studio: Config.Studio.BotFillSeconds (2)
	RookieFillSeconds = 3, -- wartet ein Rookie, kommen Bots schon nach 3 s
	FillNowAfter = 3, -- "Bots jetzt" frühestens nach 3 s
	MatcherHz = 2,
	PadScanHz = 4,
	SeatRadius = 2.2,
	SeatHeight = 5, -- |ΔY| < 5
	SeatLeaveSeconds = 1.5,
	InputMatchSeconds = 6,
	MmrWindow = 200,
	MmrWiden = 50,
	MmrWidenEvery = 3,
	NewPlayerMatches = 5, -- < 5 Matches = Neuling …
	NewPlayerPool = 15, -- … trifft nur Spieler mit < 15 Matches oder Bots
	CrownLine = 6,
	CrownIdleBot = 15,
	CrownSoloWait = 8,
	CrownRejoinGrace = 3, -- nach einem Kronen-Teleport zählt ein Kreis erst nach 3 s wieder
	PracticeCooldown = 5,
	RangeTeleportCooldown = 2,
	MaxEntries = 64, -- Obergrenze Einträge pro Modus
}

-- ---------------------------------------------------------------------
-- 7) TUTORIAL (B1.1) – Practice 1v1 gegen Rookie auf PillarBox, Erster auf 3
-- ---------------------------------------------------------------------
Modes.Tutorial = {
	Map = "PillarBox",
	Mood = "Day",
	Difficulty = "Rookie",
	RoundsToWin = 3,
	TourRadius = 12, -- Pfeil-Tour: Ziel erreicht, wenn näher als 12 Studs
	TourTargets = {
		{ Key = "Locker", Pos = Vector3.new(-10, 0, 70) },
		{ Key = "Shop", Pos = Vector3.new(-30, 0, 70) },
		{ Key = "Pads", Pos = Vector3.new(0, 0, -60) },
	},
	TourWeapon = "BuzzSMG", -- "Summ-MP 600 Coins – im Training gratis testen"
}

-- ---------------------------------------------------------------------
-- 8) SKILL-MOMENTE (docs/SKILL-WUENSCHE.md)
-- ---------------------------------------------------------------------
Modes.Skill = {
	MultiKillWindow = 4, -- DOUBLE/TRIPLE/QUAD: nächster Pop innerhalb von 4 s
	MultiKillMax = 4, -- ab 4 heißt es QUAD
	ClutchXpPerEnemy = 15, -- CLUTCH 1vX: +15 XP je Gegner (1v2 = 30, 1v4 = 60), über ProgressionService.AddXp
	AceXp = 20, -- ACE (ab 3v3): Bonus-XP für den Spieler
}

-- =====================================================================
-- PRÜFEN – Fehlertexte mit exaktem Pfad
-- =====================================================================
local RULE_KEYS: { [string]: string } = {
	DamageMult = "number",
	HeadOnly = "boolean",
	HeadRadiusMult = "number",
	IntervalMult = "number",
	ReloadMult = "number",
	SpeedMult = "number",
	GravityLift = "number",
	AllowedSlots = "table",
	ForcedLoadout = "table",
	RandomLoadout = "boolean",
	Regen = "boolean",
	UtilityMode = "string",
	FriendlyFire = "boolean",
	IgnoreOwnership = "boolean",
}
local SLOTS = { "Primary", "Secondary", "Melee", "Utility" }

local function isNum(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function checkRules(errors: { string }, path: string, rules: any, weaponOf: ((string) -> any)?)
	if type(rules) ~= "table" then
		table.insert(errors, path .. ": Tabelle erwartet")
		return
	end
	for key, value in pairs(rules) do
		local expected = RULE_KEYS[key]
		if expected == nil then
			table.insert(errors, path .. "." .. tostring(key) .. ": unbekannte Regel")
		elseif type(value) ~= expected then
			table.insert(errors, path .. "." .. tostring(key) .. ": " .. expected .. " erwartet")
		elseif expected == "number" and (not isNum(value) or value < 0) then
			table.insert(errors, path .. "." .. tostring(key) .. ": Zahl ≥ 0 erwartet")
		end
	end
	if rules.UtilityMode ~= nil and rules.UtilityMode ~= "Charges" and rules.UtilityMode ~= "Cooldown" then
		table.insert(errors, path .. '.UtilityMode: "Charges" oder "Cooldown" erwartet')
	end
	local forced = rules.ForcedLoadout
	if type(forced) == "table" then
		for _, slot in ipairs(SLOTS) do
			local key = forced[slot]
			if type(key) ~= "string" then
				table.insert(errors, path .. ".ForcedLoadout." .. slot .. ": Waffen-Key erwartet")
			elseif weaponOf then
				local def = weaponOf(key)
				if def == nil then
					table.insert(errors, path .. ".ForcedLoadout." .. slot .. ": unbekannte Waffe " .. key)
				elseif def.Slot ~= slot then
					table.insert(
						errors,
						path .. ".ForcedLoadout." .. slot .. ": " .. key .. " passt nicht in diesen Platz"
					)
				end
			end
		end
	end
	local allowed = rules.AllowedSlots
	if type(allowed) == "table" then
		for slot, on in pairs(allowed) do
			if table.find(SLOTS, slot) == nil or on ~= true then
				table.insert(errors, path .. ".AllowedSlots." .. tostring(slot) .. ": Platzname = true erwartet")
			end
		end
	end
end

local function checkNumbers(errors: { string }, path: string, t: any)
	if type(t) ~= "table" then
		table.insert(errors, path .. ": Tabelle erwartet")
		return
	end
	for key, value in pairs(t) do
		if type(value) == "number" and (not isNum(value) or value < 0) then
			table.insert(errors, path .. "." .. tostring(key) .. ": Zahl ≥ 0 erwartet")
		end
	end
end

function Modes.Validate(Config: any): { string }
	local errors: { string } = {}
	local weaponOf: ((string) -> any)? = nil
	if type(Config) == "table" and type(Config.Weapon) == "function" then
		local list = type(Config.Weapons) == "table" and Config.Weapons.List or nil
		if type(list) == "table" and #list > 0 then
			weaponOf = Config.Weapon
		end
	end
	local mapsCfg = if type(Config) == "table" and type(Config.Maps) == "table" then Config.Maps.Maps else nil

	for key, def in pairs(MODES) do
		local path = "Config.Modes.Modes." .. key
		if type(def.Name) ~= "table" or type(def.Name.de) ~= "string" or type(def.Name.en) ~= "string" then
			table.insert(errors, path .. ".Name: { de, en } erwartet")
		end
		if def.Ruleset ~= "Rounds" and def.Ruleset ~= "Respawn" then
			table.insert(errors, path .. '.Ruleset: "Rounds" oder "Respawn" erwartet')
		end
		if not isNum(def.TeamSize) or def.TeamSize < 1 or def.TeamSize > 8 or def.TeamSize % 1 ~= 0 then
			table.insert(errors, path .. ".TeamSize: ganze Zahl 1–8 erwartet")
		end
		if table.find(Modes.Order, key) == nil then
			table.insert(errors, path .. ": fehlt in Config.Modes.Order")
		end
		if def.Ruleset == "Rounds" then
			if def.Teams ~= 2 then
				table.insert(errors, path .. ".Teams: Rundenmodi brauchen 2 Teams")
			end
			local rtw, cap = def.RoundsToWin, def.RoundCap
			if not isNum(rtw) or (rtw :: number) < 1 then
				table.insert(errors, path .. ".RoundsToWin: Zahl ≥ 1 erwartet")
			elseif not isNum(cap) or cap ~= 2 * (rtw :: number) + 1 then
				table.insert(errors, path .. ".RoundCap: muss 2 × RoundsToWin + 1 sein (B6.4)")
			end
			if not isNum(def.RoundTime) or (def.RoundTime :: number) < 5 then
				table.insert(errors, path .. ".RoundTime: Zahl ≥ 5 erwartet")
			end
			if not isNum(def.Overtime) or (def.Overtime :: number) < 1 then
				table.insert(errors, path .. ".Overtime: Zahl ≥ 1 erwartet")
			end
			if (def.TeamSize :: number) * 2 > 16 then
				table.insert(errors, path .. ".TeamSize: höchstens 8 pro Team")
			end
		else
			for _, field in ipairs({ "ScoreToWin", "KillPoints", "AssistPoints", "MatchTime", "RespawnDelay", "FillTo" }) do
				local value = (def :: any)[field]
				if not isNum(value) or value < 0 then
					table.insert(errors, path .. "." .. field .. ": Zahl ≥ 0 erwartet")
				end
			end
			local maxPlayers = def.MaxPlayers
			if not isNum(maxPlayers) or (maxPlayers :: number) < 2 or (maxPlayers :: number) > 32 then
				table.insert(errors, path .. ".MaxPlayers: Zahl 2–32 erwartet")
			elseif isNum(def.FillTo) and (def.FillTo :: number) > (maxPlayers :: number) then
				table.insert(errors, path .. ".FillTo: darf nicht größer als MaxPlayers sein")
			end
		end
		if def.FixedMap ~= nil and type(mapsCfg) == "table" and mapsCfg[def.FixedMap] == nil then
			table.insert(errors, path .. ".FixedMap: unbekannte Map " .. tostring(def.FixedMap))
		end
		if def.Rewards ~= nil then
			checkNumbers(errors, path .. ".Rewards", def.Rewards)
		end
	end

	for key, mutator in pairs(MUTATORS) do
		local path = "Config.Modes.Mutators." .. key
		if type(mutator.Name) ~= "table" or type(mutator.Name.de) ~= "string" or type(mutator.Name.en) ~= "string" then
			table.insert(errors, path .. ".Name: { de, en } erwartet")
		end
		if type(mutator.Desc) ~= "table" or type(mutator.Desc.de) ~= "string" or type(mutator.Desc.en) ~= "string" then
			table.insert(errors, path .. ".Desc: { de, en } erwartet")
		end
		checkRules(errors, path .. ".Rules", mutator.Rules, weaponOf)
	end
	if #Modes.Rotation == 0 then
		table.insert(errors, "Config.Modes.Rotation: mindestens ein Mutator erwartet")
	end
	for i, key in ipairs(Modes.Rotation) do
		if MUTATORS[key] == nil then
			table.insert(errors, ("Config.Modes.Rotation[%d]: unbekannter Mutator %s"):format(i, tostring(key)))
		end
	end
	checkRules(errors, "Config.Modes.DefaultRules", Modes.DefaultRules, weaponOf)
	for key, rules in pairs(Modes.ModeRules) do
		if MODES[key] == nil then
			table.insert(errors, "Config.Modes.ModeRules." .. key .. ": unbekannter Modus")
		end
		checkRules(errors, "Config.Modes.ModeRules." .. key, rules, weaponOf)
	end

	checkNumbers(errors, "Config.Modes.Match", Modes.Match)
	checkNumbers(errors, "Config.Modes.Queue", Modes.Queue)
	checkNumbers(errors, "Config.Modes.Skill", Modes.Skill)
	local match = Modes.Match
	if match.AfkWarn >= match.AfkKick then
		table.insert(errors, "Config.Modes.Match.AfkWarn: muss kleiner als AfkKick sein")
	end
	if match.BotVoteMax < match.BotVoteMin or match.BotVoteMax > match.VoteSeconds then
		table.insert(errors, "Config.Modes.Match.BotVoteMax: zwischen BotVoteMin und VoteSeconds erwartet")
	end
	if match.ReadyMinPrep > match.Prep then
		table.insert(errors, "Config.Modes.Match.ReadyMinPrep: darf nicht größer als Prep sein")
	end
	local queue = Modes.Queue
	if queue.MatcherHz <= 0 or queue.PadScanHz <= 0 then
		table.insert(errors, "Config.Modes.Queue: MatcherHz und PadScanHz müssen > 0 sein")
	end
	if queue.NewPlayerMatches > queue.NewPlayerPool then
		table.insert(errors, "Config.Modes.Queue.NewPlayerMatches: darf nicht größer als NewPlayerPool sein")
	end
	local tutorial = Modes.Tutorial
	if type(mapsCfg) == "table" and mapsCfg[tutorial.Map] == nil then
		table.insert(errors, "Config.Modes.Tutorial.Map: unbekannte Map " .. tostring(tutorial.Map))
	end
	if weaponOf and weaponOf(tutorial.TourWeapon) == nil then
		table.insert(errors, "Config.Modes.Tutorial.TourWeapon: unbekannte Waffe " .. tostring(tutorial.TourWeapon))
	end
	local bots = if type(Config) == "table" and type(Config.Bots) == "table" then Config.Bots.Difficulties else nil
	if type(bots) == "table" and next(bots) ~= nil and bots[tutorial.Difficulty] == nil then
		table.insert(errors, "Config.Modes.Tutorial.Difficulty: unbekannte Bot-Stufe " .. tostring(tutorial.Difficulty))
	end
	return errors
end

return Modes
