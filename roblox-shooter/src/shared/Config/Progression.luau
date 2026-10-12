-- =====================================================================
--  CLUTCH CLASH – FORTSCHRITT & BELOHNUNGEN (Config.Progression)
--  Besitzer: WP8 (Fortschritt). Vertrag: DESIGN.md C15 + B16 + B24.
--  Alle Zahlen sind Startwerte aus DESIGN.md und hier 1:1 änderbar
--  (XP, Coins, Quests, Login, Glücksrad, Erfolge, Kopfgeld, Codes, Chat).
--  ACHTUNG: wird an alle Clients repliziert -> KEINE Geheimnisse (Codes sind öffentlich gedacht).
--
--  Aufbau:
--    1) Level-Kurve + XP-Quellen + Multiplikatoren      7) Glücksrad + Spielzeit-Geschenke
--    2) Coins pro Match                                 8) Erfolge (12)
--    3) Level-Belohnungen                               9) MMR, Kopfgeld, Comeback, Krone, Ehre, GG
--    4) Waffen-Meisterschaft                           10) Codes
--    5) Quests (Anfänger, Täglich, Wöchentlich)        11) Bestenlisten + Chat-Umschreibungen
--    6) Login-Kalender
--  Validate(Config) prüft alles (SelfTest + Boot-warn), Fehlertexte mit exaktem Pfad.
-- =====================================================================

local Progression = {}

-- ---------------------------------------------------------------------
-- 1) LEVEL-KURVE (B16.1): XPToNext(L) = Base + Step·(L − 1), Max-Level 100
-- ---------------------------------------------------------------------
Progression.Curve = { Base = 250, Step = 50, MaxLevel = 100 }

-- XP-Quellen (Casual gegen Menschen)
Progression.Xp = {
	Played = 40, -- Match beendet
	Win = 60, -- Sieg
	Round = 12, -- je gewonnene Runde
	Elim = 15, -- je Pop
	Assist = 7,
	HeadElim = 5, -- Kopf-Pop extra
	MeleeElim = 10, -- Nahkampf-Pop extra
	Mvp = 20,
	GG = 5, -- beide Seiten drücken GG
	CrownDefence = 15, -- Kronen-Verteidigung gegen Menschen
}

-- Multiplikatoren: additiv, gedeckelt auf Cap. Danach Bot- bzw. Practice-Faktor.
-- Gilt NUR für XP (und Pass-XP aus Matches) – nie für Coins (kein Pay-to-Win).
Progression.XpMult = {
	Vip = 0.2,
	DoubleXP = 1.0,
	Boost = 1.0, -- XP-Boost-Produkt / Glücksrad (Boosts.XP2Until)
	Party = 1.0, -- Party-Boost (ganzer Server)
	Event = 1.0, -- Admin-Abuse-Event
	Cap = 3.0,
	Bot = 0.6,
	Practice = 0.3,
}

-- ---------------------------------------------------------------------
-- 2) COINS PRO MATCH (B18.2) – gutgeschrieben NUR über ShopService.Grant
-- ---------------------------------------------------------------------
Progression.Coins = {
	Played = 30,
	Round = 10,
	Elim = 6,
	Assist = 3,
	HeadElim = 2,
	Win = 50,
	Mvp = 15,
	GG = 5,
	StreakStep = 5, -- Siegesserie: +5 je Stufe ab dem 2. Sieg in Folge …
	StreakCap = 30, -- … höchstens +30
	BotMult = 0.6, -- gegen Bots ×0.6 …
	BotMin = 15, -- … mindestens 15 …
	BotDailyCap = 2500, -- … höchstens 2.500 pro UTC-Tag
	DrawBonus = 0.1, -- Unentschieden: Niederlagen-Belohnung +10 %
}

Progression.FirstWin = { Xp = 200, Coins = 150 } -- erster Sieg des UTC-Tages (flach)
Progression.Tutorial = { Xp = 250, Coins = 300 } -- Tutorial-Duell (einmalig)

-- ---------------------------------------------------------------------
-- 3) LEVEL-BELOHNUNGEN (B16.1)
-- ---------------------------------------------------------------------
Progression.LevelRewards = {
	CoinsBase = 50, -- jedes Level: 50 + 10·L Coins
	CoinsPerLevel = 10,
	FreeWeaponLevels = { 4, 10, 20 }, -- "Wähle eine Waffe gratis!"
	KeyEvery = 5, -- jedes 5. Level 1 Schlüssel
	GemsEvery = 10, -- jedes 10. Level …
	Gems = 25, -- … 25 Gems
	Titles = { [10] = "TT_Lv10", [25] = "TT_Lv25", [50] = "TT_Lv50", [75] = "TT_Lv75", [100] = "TT_Lv100" },
	AnnounceLevels = { 25, 50, 100 }, -- Lobby-Ansage (B24)
}

-- Level-Abzeichen-Farben (Chat, Scoreboard): ab Level Min
Progression.LevelColors = {
	{ Min = 1, Color = Color3.fromRGB(255, 255, 255) },
	{ Min = 10, Color = Color3.fromRGB(90, 220, 110) },
	{ Min = 25, Color = Color3.fromRGB(60, 140, 255) },
	{ Min = 50, Color = Color3.fromRGB(170, 90, 255) },
	{ Min = 75, Color = Color3.fromRGB(255, 145, 35) },
	{ Min = 100, Color = Color3.fromRGB(255, 200, 40) },
}

-- ---------------------------------------------------------------------
-- 4) WAFFEN-MEISTERSCHAFT (B16.2) – Pops je Stufe; Nahkampf/Utility ×2, MasteryBoost ×2
--    Wraps sind NICHT kaufbar; Ausrüsten prüft die Stufe (kein Besitz-Eintrag).
--    Title = "Master" -> Titel "TT_Master_<WeaponKey>"
-- ---------------------------------------------------------------------
Progression.Mastery = {
	Tiers = { 10, 30, 75, 150, 300, 600, 1000, 2000, 3500, 6000 },
	MeleeUtilityMult = 2,
	BoostMult = 2,
	PracticeMult = 0.5,
	StarTier = 5, -- Stern im Killfeed ab Stufe V
	Rewards = {
		{ Coins = 150 },
		{ Wrap = "W_MBronze" },
		{ Keys = 1, Coins = 250 },
		{ Wrap = "W_MSilver" },
		{ Wrap = "W_MGold" },
		{ Gems = 50 },
		{ Wrap = "W_MDiamond" },
		{ Wrap = "W_MNeon" },
		{ Wrap = "W_MGalaxy", Title = "Master" },
		{ Wrap = "W_MPrism" },
	},
}

-- ---------------------------------------------------------------------
-- 5) QUESTS (B16.3)
--    Kind = Zähl-Art (RewardService.Track), Goal = Ziel, Tier = Easy/Medium/Hard,
--    Filter = nur zählen, wenn ctx.Mode / ctx.Map passt. Text = Lang "prog.q.<Id>" (%d = Ziel).
--    Pvp = true: zählt nur in PvP-Matches ("gegen Spieler").
-- ---------------------------------------------------------------------
Progression.Quests = {
	DailyCount = 3,
	WeeklyCount = 5,
	FreeRerolls = 1, -- pro Tag gratis tauschen (VIP +1)
	VipRerolls = 1,
	RerollCoins = 100, -- jeder weitere Tausch
	DailyTiers = { "Easy", "Medium", "Hard" },
	DailyRewards = {
		Easy = { Coins = 150, PassXp = 300 },
		Medium = { Coins = 250, PassXp = 300 },
		Hard = { Coins = 400, PassXp = 300 },
	},
	WeeklyReward = { Coins = 600, PassXp = 1500 },
	WeeklyChest = { Keys = 2, Gems = 50 }, -- alle 5 Wochenquests
	Daily = {
		{ Id = "D_WinMatches", Kind = "Win", Goal = 2, Tier = "Medium" },
		{ Id = "D_PlayMatches", Kind = "Match", Goal = 3, Tier = "Easy" },
		{ Id = "D_Elims", Kind = "Elim", Goal = 15, Tier = "Medium" },
		{ Id = "D_HeadshotElims", Kind = "HeadElim", Goal = 5, Tier = "Hard" },
		{ Id = "D_Damage", Kind = "Damage", Goal = 1500, Tier = "Easy" },
		{ Id = "D_MeleeElims", Kind = "MeleeElim", Goal = 3, Tier = "Medium" },
		{ Id = "D_SecondaryElims", Kind = "SecondaryElim", Goal = 5, Tier = "Medium" },
		{ Id = "D_SmgShotgunElims", Kind = "SmgShotgunElim", Goal = 8, Tier = "Medium" },
		{ Id = "D_RoundFullHp", Kind = "RoundFullHp", Goal = 1, Tier = "Hard" },
		{ Id = "D_OvertimeRound", Kind = "OvertimeRound", Goal = 1, Tier = "Medium" },
		{ Id = "D_FfaElims", Kind = "Elim", Goal = 10, Tier = "Medium", Filter = { Mode = "FFA" } },
		{ Id = "D_PlayMutator", Kind = "Match", Goal = 1, Tier = "Easy", Filter = { Mode = "Mutator" } },
		{ Id = "D_CrownChallenge", Kind = "Match", Goal = 1, Tier = "Easy", Filter = { Mode = "Crown" } },
		{ Id = "D_Heal", Kind = "Heal", Goal = 150, Tier = "Easy" },
		{ Id = "D_SlideElims", Kind = "SlideElim", Goal = 3, Tier = "Hard" },
		{ Id = "D_SplashElims", Kind = "SplashElim", Goal = 2, Tier = "Hard" },
		{ Id = "D_RoundsWon", Kind = "RoundWon", Goal = 6, Tier = "Easy" },
		{ Id = "D_Assists", Kind = "Assist", Goal = 5, Tier = "Easy" },
		{ Id = "D_FfaStreak3", Kind = "FfaStreak3", Goal = 1, Tier = "Hard" },
		{ Id = "D_WinOnMap", Kind = "Win", Goal = 1, Tier = "Hard", Filter = { Map = "SkyGarden" } },
	},
	Weekly = {
		{ Id = "W_WinMatches", Kind = "Win", Goal = 10 },
		{ Id = "W_Elims", Kind = "Elim", Goal = 75 },
		{ Id = "W_HeadshotElims", Kind = "HeadElim", Goal = 20 },
		{ Id = "W_CrownDefences", Kind = "CrownDefence", Goal = 3 },
		{ Id = "W_MasteryTier", Kind = "MasteryTier", Goal = 3 },
		{ Id = "W_DifferentMaps", Kind = "DifferentMaps", Goal = 5 },
		{ Id = "W_PvpWins", Kind = "PvpWin", Goal = 10, Pvp = true },
		{ Id = "W_Commend", Kind = "Commend", Goal = 5 },
	},
	-- Anfänger-Kette: eine nach der anderen, zusammen 1.250 Coins.
	-- Kinds "NewWeapon", "LoadoutEdit", "Level" werden zusätzlich am Spielstand geprüft.
	Beginner = {
		{ Id = "B1", Kind = "DummyHit", Goal = 10, Coins = 100 },
		{ Id = "B2", Kind = "Win", Goal = 1, Coins = 150 },
		{ Id = "B3", Kind = "Elim", Goal = 5, Coins = 100 },
		{ Id = "B4", Kind = "HeadElim", Goal = 3, Coins = 100 },
		{ Id = "B5", Kind = "NewWeapon", Goal = 1, Coins = 100 },
		{ Id = "B6", Kind = "LoadoutEdit", Goal = 1, Coins = 50 },
		{ Id = "B7", Kind = "Slide", Goal = 5, Coins = 75 },
		{ Id = "B8", Kind = "Match", Goal = 1, Coins = 125, Filter = { Mode = "Duel2" } },
		{ Id = "B9", Kind = "Match", Goal = 1, Coins = 150, Filter = { Mode = "Crown" } },
		{ Id = "B10", Kind = "Level", Goal = 5, Coins = 300, FreePick = 1 },
	},
	-- Diese Waffen zählen für die Tagesquest "SMG/Schrot-Pops" (Kind SmgShotgunElim)
	SmgShotgunWeapons = { "BuzzSMG", "Scatter", "MiniScatter" },
}

-- ---------------------------------------------------------------------
-- 6) LOGIN-KALENDER (B16.4) – rückt nur an Login-Tagen vor
-- ---------------------------------------------------------------------
Progression.Login = {
	Calendar = {
		{ Coins = 150 },
		{ Keys = 1 },
		{ Coins = 250 },
		{ Gems = 15 },
		{ Coins = 350 },
		{ Keys = 1 },
		{ Keys = 2, Gems = 30 },
	},
	FirstCycleCharm = "C_CalendarCat", -- beim ersten vollen Zyklus
	FreezesPerWeek = 1, -- 1 Serien-Freeze pro ISO-Woche (automatisch)
	PassXp = 100, -- Pass-XP pro Login-Tag
	OnFireDays = 7, -- Titel "Brennt! / On Fire" ab 7 Tagen Serie
	OnFireTitle = "TT_OnFire",
}

-- ---------------------------------------------------------------------
-- 7) GRATIS-GLÜCKSRAD (B16.4) – W = Gewicht in %, Summe 100. KEINE bezahlten Drehs.
-- ---------------------------------------------------------------------
Progression.Wheel = {
	FreeSpins = 1,
	VipSpins = 1,
	AllDailiesSpins = 1,
	Prizes = {
		{ Coins = 100, W = 30 },
		{ Coins = 200, W = 22 },
		{ Keys = 1, W = 15 },
		{ XpBoostSeconds = 900, W = 12 },
		{ Gems = 25, W = 10 },
		{ Coins = 500, W = 7 },
		{ Keys = 3, W = 3 },
		{ Gems = 250, W = 1 },
	},
}

-- Spielzeit-Geschenke pro UTC-Tag (über alle Besuche summiert)
Progression.Playtime = {
	Minutes = { 5, 15, 30, 60 },
	Rewards = { { Coins = 50 }, { Coins = 100 }, { Keys = 1 }, { Coins = 150 } },
}

-- ---------------------------------------------------------------------
-- 8) ERFOLGE (B16.5) – Stat = Zähler in Data.Stats; Sonderfälle:
--    "OwnedWeapons" (Anzahl besessener Waffen), "Commends" (erhaltenes Lob),
--    "CrownVsHuman" (Kronen-Verteidigungen gegen Menschen, Data.AchProgress).
--    Reward: Coins/Gems + Title (Kosmetik-Id "TT_<Id>").
-- ---------------------------------------------------------------------
Progression.Achievements = {
	FirstPop = {
		Order = 1,
		Name = { de = "Erster Pop", en = "First Pop" },
		Desc = { de = "Schalte 1 Gegner aus", en = "Pop 1 opponent" },
		Stat = "Elims",
		Goal = 1,
		Reward = { Coins = 50 },
	},
	Headhunter = {
		Order = 2,
		Name = { de = "Kopfjäger", en = "Headhunter" },
		Desc = { de = "100 Kopf-Pops", en = "100 headshot pops" },
		Stat = "Headshots",
		Goal = 100,
		Reward = { Title = "TT_Headhunter" },
	},
	Untouchable = {
		Order = 3,
		Name = { de = "Unberührbar", en = "Untouchable" },
		Desc = { de = "Gewinne eine FLAWLESS-Runde", en = "Win a FLAWLESS round" },
		Stat = "Flawless",
		Goal = 1,
		Reward = { Title = "TT_Untouchable" },
	},
	ClutchMaster = {
		Order = 4,
		Name = { de = "Clutch-Meister", en = "Clutch Master" },
		Desc = { de = "Gewinne eine Runde als Letzter gegen 2+", en = "Win a round as the last one vs 2+" },
		Stat = "Clutches",
		Goal = 1,
		Reward = { Gems = 50, Title = "TT_ClutchMaster" },
	},
	Ace = {
		Order = 5,
		Name = { de = "Ass", en = "Ace" },
		Desc = { de = "Erziele ein ACE (ab 3v3)", en = "Get an ACE (3v3 or bigger)" },
		Stat = "Aces",
		Goal = 1,
		Reward = { Title = "TT_Ace" },
	},
	ThroneKeeper = {
		Order = 6,
		Name = { de = "Kronen-Hüter", en = "Throne Keeper" },
		Desc = { de = "10 Kronen-Verteidigungen gegen Spieler", en = "10 crown defences vs players" },
		Stat = "CrownVsHuman",
		Goal = 10,
		Reward = { Title = "TT_ThroneKeeper" },
	},
	BountyHunter = {
		Order = 7,
		Name = { de = "Kopfgeldjäger", en = "Bounty Hunter" },
		Desc = { de = "Kassiere 3 Kopfgelder", en = "Claim 3 bounties" },
		Stat = "Bounties",
		Goal = 3,
		Reward = { Title = "TT_BountyHunter" },
	},
	Collector = {
		Order = 8,
		Name = { de = "Sammler", en = "Collector" },
		Desc = { de = "Besitze 8 Waffen", en = "Own 8 weapons" },
		Stat = "OwnedWeapons",
		Goal = 8,
		Reward = { Gems = 25 },
	},
	Arsenal = {
		Order = 9,
		Name = { de = "Arsenal", en = "Arsenal" },
		Desc = { de = "Besitze alle 15 Waffen", en = "Own all 15 weapons" },
		Stat = "OwnedWeapons",
		Goal = 15,
		Reward = { Title = "TT_Arsenal" },
	},
	GoodSport = {
		Order = 10,
		Name = { de = "Fairer Sportler", en = "Good Sport" },
		Desc = { de = "Erhalte 25 Lob", en = "Receive 25 commends" },
		Stat = "Commends",
		Goal = 25,
		Reward = { Title = "TT_GoodSport" },
	},
	Marathon = {
		Order = 11,
		Name = { de = "Marathon", en = "Marathon" },
		Desc = { de = "Spiele 100 Matches", en = "Play 100 matches" },
		Stat = "Matches",
		Goal = 100,
		Reward = { Gems = 30 },
	},
	SkyDiver = {
		Order = 12,
		Name = { de = "Himmelstaucher", en = "Sky Diver" },
		Desc = {
			de = "Schubse 10 Gegner in die Leere (≤ 3 s nach deinem Treffer)",
			en = "Knock 10 opponents into the void (≤ 3 s after your hit)",
		},
		Stat = "VoidKnocks",
		Goal = 10,
		Reward = { Title = "TT_SkyDiver" },
	},
}
Progression.VoidKnockWindow = 3 -- Sekunden zwischen deinem Treffer und dem Sturz (SkyDiver)

-- ---------------------------------------------------------------------
-- 9) MMR, KOPFGELD, COMEBACK, KRONE, EHRE, GG (B16.6–B16.8, B4)
-- ---------------------------------------------------------------------
Progression.Mmr = { Start = 1000, KNew = 40, KNewGames = 20, K = 24 }
Progression.Bounty = { MinStreak = 5, Base = 100, Step = 25, Cap = 300 }
Progression.Comeback = { Losses = 3, CoinBonus = 0.25 }
Progression.Crown = { DefenceCoinsHuman = 40, DefenceCoinsBot = 10, Announce = { 3, 5, 10 } }
Progression.Honor = { CommendDailyCap = 3, Badges = { 10, 50, 200 } }
Progression.GG = { Xp = 5, Coins = 5 }
Progression.RookieMatches = 3 -- IsRookie: Stats.Matches < 3

-- Sichtbarer SKILL-RANG im Statistik-Fenster (SKILL-WUENSCHE) – NUR ANZEIGE aus dem verdeckten MMR (B16.6).
-- Ranked-Warteschlange/RP bleiben v1.1 (B17). Min = MMR ab dem der Rang gilt (aufsteigend, Start 1000 = Silber).
-- Placement: so viele gewertete PvP-Matches (Data.MmrGames), bevor ein Rang angezeigt wird.
-- Farbe = Rang-Akzent (nur Rahmen/Streifen, AKYTEX).
Progression.SkillRanks = {
	Placement = 5,
	List = {
		{ Key = "Bronze", Min = 0, Color = Color3.fromRGB(205, 127, 50) },
		{ Key = "Silver", Min = 950, Color = Color3.fromRGB(170, 180, 195) },
		{ Key = "Gold", Min = 1100, Color = Color3.fromRGB(234, 179, 8) },
		{ Key = "Platinum", Min = 1250, Color = Color3.fromRGB(34, 211, 238) },
		{ Key = "Diamond", Min = 1400, Color = Color3.fromRGB(79, 140, 255) },
		{ Key = "Champion", Min = 1550, Color = Color3.fromRGB(236, 72, 153) },
	},
}

-- Aim-Trainer-Bestwerte (Request "TrainerScore", Schießstand): erlaubte Bereiche je Modus (Server klemmt/prüft).
-- Flick = Punkte (größer besser, höchstens 100 × Zielanzahl), Track = % Zeit auf dem Ziel (größer besser),
-- Reaction = Durchschnitt in ms (kleiner besser; unter MinMs ist menschlich nicht möglich -> abgelehnt).
Progression.Trainer = {
	FlickMax = 5000,
	TrackMax = 100,
	ReactionMinMs = 100,
	ReactionMaxMs = 2500,
}

-- ---------------------------------------------------------------------
-- 10) CODES (statisch; Großbuchstaben, ≤ 20 Zeichen). Expires = UTC (optional).
--     Neue Codes einfach hier eintragen. Jeder Spieler kann jeden Code einmal einlösen.
-- ---------------------------------------------------------------------
Progression.Codes = {
	LAUNCH = { Grant = { Coins = 250 }, Expires = "2027-01-31T00:00:00Z" },
	CLUTCH = { Grant = { Keys = 1 } },
}

-- ---------------------------------------------------------------------
-- 11) BESTENLISTEN (6 Lobby-Tafeln, B16.9) + CHAT (B24)
-- ---------------------------------------------------------------------
Progression.Leaderboards = { "Wins", "Elims", "BestStreak", "TotalXP", "WeeklyWins", "CrownBest" }
Progression.BoardRows = 10
Progression.BoardNameCache = 200

-- Nur Anzeige, nur Nachrichten ANDERER, nur ganze Wörter/ganze Nachricht (Groß/Klein egal).
-- Schlüssel klein schreiben. NIE normale deutsche Wörter eintragen (z. B. "schlecht")!
Progression.Chat = {
	Rewrites = {
		ez = { de = "gg wp", en = "gg wp" },
		ggez = { de = "GG ❤", en = "GG ❤" },
		noob = { de = "Freund", en = "friend" },
		p2w = { de = "faires Loadout", en = "fair loadout" },
		trash = { de = "gutes Spiel", en = "good game" },
	},
	-- AKYTEX-Farben (Chat-Präfixe): Besitzer/VIP = Warn-Gold, Titel = Text2
	OwnerColor = "#EAB308",
	VipColor = "#EAB308",
	TitleColor = "#AAB4C3",
}

-- =====================================================================
-- PRÜFEN (Config.Validate sammelt das) – leere Liste = alles ok
-- =====================================================================
local function isNumber(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local GRANT_FIELDS = { Coins = true, Gems = true, Keys = true, Shards = true, XpBoostSeconds = true, W = true }

function Progression.Validate(Config: any): { string }
	local errors: { string } = {}
	local function err(path: string, text: string)
		table.insert(errors, "Config.Progression." .. path .. ": " .. text)
	end
	local function num(path: string, v: any, min: number?, integer: boolean?)
		if not isNumber(v) then
			err(path, "Zahl erwartet")
		elseif min ~= nil and v < min then
			err(path, "mindestens " .. tostring(min))
		elseif integer and v % 1 ~= 0 then
			err(path, "ganze Zahl erwartet")
		end
	end
	local function numbers(path: string, t: any, min: number?)
		if type(t) ~= "table" then
			err(path, "Tabelle erwartet")
			return
		end
		for key, value in pairs(t) do
			num(path .. "." .. tostring(key), value, min)
		end
	end
	local function grant(path: string, t: any)
		if type(t) ~= "table" then
			err(path, "Belohnungs-Tabelle erwartet")
			return
		end
		for key, value in pairs(t) do
			if not GRANT_FIELDS[key] then
				err(path .. "." .. tostring(key), "unbekanntes Belohnungsfeld")
			else
				num(path .. "." .. tostring(key), value, 0)
			end
		end
	end

	num("Curve.Base", Progression.Curve.Base, 1)
	num("Curve.Step", Progression.Curve.Step, 0)
	num("Curve.MaxLevel", Progression.Curve.MaxLevel, 2, true)
	numbers("Xp", Progression.Xp, 0)
	numbers("XpMult", Progression.XpMult, 0)
	if isNumber(Progression.XpMult.Cap) and Progression.XpMult.Cap < 1 then
		err("XpMult.Cap", "mindestens 1")
	end
	numbers("Coins", Progression.Coins, 0)
	numbers("FirstWin", Progression.FirstWin, 0)
	numbers("Tutorial", Progression.Tutorial, 0)

	local lr = Progression.LevelRewards
	num("LevelRewards.CoinsBase", lr.CoinsBase, 0)
	num("LevelRewards.CoinsPerLevel", lr.CoinsPerLevel, 0)
	num("LevelRewards.KeyEvery", lr.KeyEvery, 1, true)
	num("LevelRewards.GemsEvery", lr.GemsEvery, 1, true)
	num("LevelRewards.Gems", lr.Gems, 0)
	for i, level in ipairs(lr.FreeWeaponLevels) do
		num("LevelRewards.FreeWeaponLevels[" .. i .. "]", level, 2, true)
	end
	for level, title in pairs(lr.Titles) do
		if not isNumber(level) or type(title) ~= "string" or string.sub(title, 1, 3) ~= "TT_" then
			err("LevelRewards.Titles[" .. tostring(level) .. "]", 'Level -> "TT_…" erwartet')
		end
	end

	-- Meisterschaft: 10 aufsteigende Stufen + 10 Belohnungen
	local mastery = Progression.Mastery
	local last = 0
	for i, goal in ipairs(mastery.Tiers) do
		num("Mastery.Tiers[" .. i .. "]", goal, 1)
		if isNumber(goal) and goal <= last then
			err("Mastery.Tiers[" .. i .. "]", "muss größer als die vorige Stufe sein")
		end
		last = if isNumber(goal) then goal else last
	end
	if #mastery.Rewards ~= #mastery.Tiers then
		err("Mastery.Rewards", "genau eine Belohnung je Stufe erwartet")
	end
	for i, reward in ipairs(mastery.Rewards) do
		for key, value in pairs(reward) do
			if key == "Wrap" then
				if type(value) ~= "string" then
					err("Mastery.Rewards[" .. i .. "].Wrap", "Wrap-Id erwartet")
				end
			elseif key == "Title" then
				if value ~= "Master" then
					err("Mastery.Rewards[" .. i .. "].Title", '"Master" erwartet')
				end
			elseif not GRANT_FIELDS[key] then
				err("Mastery.Rewards[" .. i .. "]." .. tostring(key), "unbekanntes Feld")
			else
				num("Mastery.Rewards[" .. i .. "]." .. tostring(key), value, 0)
			end
		end
	end

	-- Quests
	local q = Progression.Quests
	num("Quests.DailyCount", q.DailyCount, 1, true)
	num("Quests.WeeklyCount", q.WeeklyCount, 1, true)
	num("Quests.FreeRerolls", q.FreeRerolls, 0, true)
	num("Quests.RerollCoins", q.RerollCoins, 0)
	local ids: { [string]: boolean } = {}
	local tierCount: { [string]: number } = {}
	local function questList(path: string, list: any, needsTier: boolean)
		if type(list) ~= "table" then
			err(path, "Liste erwartet")
			return
		end
		for i, def in ipairs(list) do
			local p = ("%s[%d]"):format(path, i)
			if type(def.Id) ~= "string" or def.Id == "" then
				err(p .. ".Id", "Text erwartet")
			elseif ids[def.Id] then
				err(p .. ".Id", "doppelte Quest-Id " .. def.Id)
			else
				ids[def.Id] = true
			end
			if type(def.Kind) ~= "string" then
				err(p .. ".Kind", "Text erwartet")
			end
			num(p .. ".Goal", def.Goal, 1)
			if needsTier then
				if q.DailyRewards[def.Tier] == nil then
					err(p .. ".Tier", "Easy/Medium/Hard erwartet")
				else
					tierCount[def.Tier] = (tierCount[def.Tier] or 0) + 1
				end
			end
			if def.Filter ~= nil and type(def.Filter) ~= "table" then
				err(p .. ".Filter", "Tabelle erwartet")
			end
		end
	end
	questList("Quests.Daily", q.Daily, true)
	questList("Quests.Weekly", q.Weekly, false)
	questList("Quests.Beginner", q.Beginner, false)
	if #q.Daily ~= 20 then
		err("Quests.Daily", "20 Einträge erwartet (B16.3)")
	end
	if #q.Weekly ~= 8 then
		err("Quests.Weekly", "8 Einträge erwartet (B16.3)")
	end
	if #q.Weekly < q.WeeklyCount then
		err("Quests.Weekly", "weniger Einträge als WeeklyCount")
	end
	for _, tier in ipairs(q.DailyTiers) do
		if (tierCount[tier] or 0) < 2 then
			err("Quests.Daily", "Stufe " .. tier .. " braucht mindestens 2 Quests (Tauschen)")
		end
	end
	for tier, reward in pairs(q.DailyRewards) do
		num("Quests.DailyRewards." .. tier .. ".Coins", reward.Coins, 0)
		num("Quests.DailyRewards." .. tier .. ".PassXp", reward.PassXp, 0)
	end
	num("Quests.WeeklyReward.Coins", q.WeeklyReward.Coins, 0)
	num("Quests.WeeklyReward.PassXp", q.WeeklyReward.PassXp, 0)
	grant("Quests.WeeklyChest", q.WeeklyChest)
	local beginnerCoins = 0
	for i, step in ipairs(q.Beginner) do
		num(("Quests.Beginner[%d].Coins"):format(i), step.Coins, 0)
		beginnerCoins += if isNumber(step.Coins) then step.Coins else 0
	end
	if #q.Beginner ~= 10 or beginnerCoins ~= 1250 then
		err("Quests.Beginner", "10 Schritte mit zusammen 1.250 Coins erwartet (B16.3)")
	end

	-- Login
	local login = Progression.Login
	if #login.Calendar ~= 7 then
		err("Login.Calendar", "7 Tage erwartet")
	end
	for i, reward in ipairs(login.Calendar) do
		grant("Login.Calendar[" .. i .. "]", reward)
	end
	num("Login.FreezesPerWeek", login.FreezesPerWeek, 0, true)
	num("Login.PassXp", login.PassXp, 0)
	num("Login.OnFireDays", login.OnFireDays, 1, true)

	-- Glücksrad: Summe genau 100 %
	local wheelSum = 0
	for i, prize in ipairs(Progression.Wheel.Prizes) do
		grant("Wheel.Prizes[" .. i .. "]", prize)
		num("Wheel.Prizes[" .. i .. "].W", prize.W, 0)
		wheelSum += if isNumber(prize.W) then prize.W else 0
	end
	if math.abs(wheelSum - 100) > 1e-6 then
		err("Wheel.Prizes", ("Gewichte müssen 100 ergeben (sind %s)"):format(tostring(wheelSum)))
	end
	num("Wheel.FreeSpins", Progression.Wheel.FreeSpins, 0, true)
	num("Wheel.VipSpins", Progression.Wheel.VipSpins, 0, true)
	num("Wheel.AllDailiesSpins", Progression.Wheel.AllDailiesSpins, 0, true)

	-- Spielzeit
	local pt = Progression.Playtime
	if #pt.Minutes ~= #pt.Rewards then
		err("Playtime", "gleich viele Minuten und Belohnungen erwartet")
	end
	local lastMinute = 0
	for i, minutes in ipairs(pt.Minutes) do
		num("Playtime.Minutes[" .. i .. "]", minutes, 1)
		if isNumber(minutes) and minutes <= lastMinute then
			err("Playtime.Minutes[" .. i .. "]", "aufsteigend erwartet")
		end
		lastMinute = if isNumber(minutes) then minutes else lastMinute
	end
	for i, reward in ipairs(pt.Rewards) do
		grant("Playtime.Rewards[" .. i .. "]", reward)
	end

	-- Erfolge
	local count = 0
	for id, def in pairs(Progression.Achievements) do
		count += 1
		local p = "Achievements." .. tostring(id)
		if type(def.Name) ~= "table" or type(def.Name.de) ~= "string" or type(def.Name.en) ~= "string" then
			err(p .. ".Name", "{ de, en } erwartet")
		end
		if type(def.Desc) ~= "table" or type(def.Desc.de) ~= "string" or type(def.Desc.en) ~= "string" then
			err(p .. ".Desc", "{ de, en } erwartet")
		end
		if type(def.Stat) ~= "string" then
			err(p .. ".Stat", "Text erwartet")
		end
		num(p .. ".Goal", def.Goal, 1)
		num(p .. ".Order", def.Order, 1, true)
		if type(def.Reward) ~= "table" then
			err(p .. ".Reward", "Tabelle erwartet")
		else
			for key, value in pairs(def.Reward) do
				if key == "Title" then
					if type(value) ~= "string" or string.sub(value, 1, 3) ~= "TT_" then
						err(p .. ".Reward.Title", '"TT_…" erwartet')
					end
				elseif key ~= "Coins" and key ~= "Gems" then
					err(p .. ".Reward." .. tostring(key), "nur Coins, Gems, Title erlaubt")
				else
					num(p .. ".Reward." .. tostring(key), value, 0)
				end
			end
		end
	end
	if count ~= 12 then
		err("Achievements", "12 Erfolge erwartet (B16.5)")
	end

	numbers("Mmr", Progression.Mmr, 0)
	numbers("Bounty", Progression.Bounty, 0)
	numbers("Comeback", Progression.Comeback, 0)
	num("Crown.DefenceCoinsHuman", Progression.Crown.DefenceCoinsHuman, 0)
	num("Crown.DefenceCoinsBot", Progression.Crown.DefenceCoinsBot, 0)
	num("Honor.CommendDailyCap", Progression.Honor.CommendDailyCap, 0, true)
	numbers("GG", Progression.GG, 0)
	num("SkillRanks.Placement", Progression.SkillRanks.Placement, 0, true)
	local lastMin = -math.huge
	for i, rank in ipairs(Progression.SkillRanks.List) do
		local p = "SkillRanks.List[" .. i .. "]"
		if type(rank.Key) ~= "string" then
			err(p .. ".Key", "Text erwartet")
		end
		num(p .. ".Min", rank.Min, 0)
		if isNumber(rank.Min) then
			if rank.Min <= lastMin then
				err(p .. ".Min", "Ränge aufsteigend sortieren")
			end
			lastMin = rank.Min
		end
		if typeof(rank.Color) ~= "Color3" then
			err(p .. ".Color", "Color3 erwartet")
		end
	end
	if #Progression.SkillRanks.List ~= 6 then
		err("SkillRanks.List", "6 Ränge erwartet (Bronze bis Champion)")
	end
	numbers("Trainer", Progression.Trainer, 0)

	for code, def in pairs(Progression.Codes) do
		local p = "Codes." .. tostring(code)
		if type(code) ~= "string" or #code > 20 or string.upper(code) ~= code or string.find(code, "[^%w_%-]") then
			err(p, "Code muss aus GROSSBUCHSTABEN/Ziffern bestehen (≤ 20 Zeichen)")
		end
		grant(p .. ".Grant", def.Grant)
		if def.Expires ~= nil then
			local y, mo, d = string.match(tostring(def.Expires), "^(%d%d%d%d)%-(%d%d)%-(%d%d)")
			if not (y and mo and d) then
				err(p .. ".Expires", 'Datum "YYYY-MM-DDTHH:MM:SSZ" erwartet')
			end
		end
	end

	local boards: { [string]: boolean } = {}
	for _, name in ipairs(Progression.Leaderboards) do
		boards[name] = true
	end
	for _, name in ipairs({ "Wins", "Elims", "BestStreak", "TotalXP", "WeeklyWins", "CrownBest" }) do
		if not boards[name] then
			err("Leaderboards", "Tafel " .. name .. " fehlt (B16.9)")
		end
	end
	for word, text in pairs(Progression.Chat.Rewrites) do
		if type(word) ~= "string" or string.lower(word) ~= word or string.find(word, "[^%w]") then
			err("Chat.Rewrites." .. tostring(word), "ein kleingeschriebenes Wort erwartet")
		end
		if type(text) ~= "table" or type(text.de) ~= "string" or type(text.en) ~= "string" then
			err("Chat.Rewrites." .. tostring(word), "{ de, en } erwartet")
		end
	end

	-- Quer-Prüfung gegen andere Config-Teile (nur wenn geladen)
	local weapons = Config and Config.Weapons and Config.Weapons.List
	if type(weapons) == "table" and #weapons > 0 then
		local known: { [string]: boolean } = {}
		for _, def in ipairs(weapons) do
			if type(def) == "table" and type(def.Key) == "string" then
				known[def.Key] = true
			end
		end
		for _, key in ipairs(q.SmgShotgunWeapons) do
			if not known[key] then
				err("Quests.SmgShotgunWeapons", "unbekannte Waffe " .. tostring(key))
			end
		end
	end
	local maps = Config and Config.Maps and Config.Maps.Maps
	if type(maps) == "table" and next(maps) ~= nil then
		for _, def in ipairs(q.Daily) do
			if def.Filter and def.Filter.Map and maps[def.Filter.Map] == nil then
				err("Quests.Daily." .. def.Id .. ".Filter.Map", "unbekannte Map " .. tostring(def.Filter.Map))
			end
		end
	end
	return errors
end

return Progression
