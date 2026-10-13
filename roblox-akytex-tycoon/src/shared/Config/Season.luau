-- =====================================================================
--  AKYTEX TYCOON – Saison & Skyline-Pass (Config.Season)
--  Besitzer: WP9 (Fortschritt, Tutorial, Sozial, Bestenlisten). Vertrag: DESIGN.md §C14.2 (Season), §B9.9
--  (Skyline-Pass: 4 Wochen, 50 Stufen à 1.000 Saison-XP), §E2 (Saison-Plan), §B14.2 (SeasonPremium/SeasonTier).
--  Alle Zahlen sind Startwerte und 1:1 änderbar. Wird an alle Clients repliziert -> KEINE Geheimnisse.
--  Diese Datei lädt KEINE Roblox-Dienste/-Typen -> Luau-CLI-ladbar.
--
--  Robux-Firewall (§0.4/§0.8): Pass-Belohnungen sind NUR Turm-Seite (CR, Deko, Kosmetik, Uhr, Auto, Boost-Token,
--  Titel) – NIE AKY, Trader-XP, Know-how, Ruf, Lizenz. Gekaufte Stufen (Produkt SeasonTier) schalten nur Kosmetik
--  frei; CR/Boost/Token zahlt eine Stufe nur, wenn sie mit verdienter Saison-XP erreicht wurde (REUSE §7 #8).
--  Premium rückwirkend; ehrlicher Countdown bis EndUtc (feste Enddaten, kein Neustart).
--
--  Belohnungs-Felder: Credits = { Minutes, Min } (Minuten Dauer-Einkommen ohne Zeitlich, mindestens Min CR) ·
--    Decor = { [Key] = Anzahl } · Cosmetics = { Key } · Watches = { Key } · Cars = { Key } · Accessories = { Key } ·
--    BoostX2 = Spielsekunden · InstantTokens = Anzahl · Title = Titel-Schlüssel (Config.Progression.Titles)
--  Helfer: Season.Validate(Config): { string }
-- =====================================================================

local Season = {}

-- ---------------------------------------------------------------------
-- 1) SAISON-QUELLEN (§B9.9) – ≈ 1.800 Saison-XP je Tag -> Stufe 50 in ≈ 28 Tagen
-- ---------------------------------------------------------------------
Season.XpSources = {
	DailyQuest = 150, -- je Tagesquest (3×)
	WeeklyQuest = 600, -- je Wochenquest (3×)
	Playtime = { Xp = 10, Minutes = 10, MaxMinutes = 60 }, -- 10 je 10 min, max. 60 min/Tag
	CountingDay = { Xp = 25, Cap = 12 }, -- zählender Börsentag, max. 12/Tag
	WorldEvent = { Xp = 50 }, -- Welt-Event-Teilnahme (EventService ruft GrantSeasonXp)
	HelpBuild = { Xp = 25 }, -- Bau-Hilfe (TowerService ruft GrantSeasonXp)
	Respekt = { Xp = 25, Cap = 5 }, -- Respekt geben, max. 5/Tag
	Login = { Xp = 300 }, -- Login-Kalender Tag 6
	League = { Bronze = 300, Silber = 600, Gold = 1200, Diamant = 2500 }, -- Liga-Stufe der Vorwoche
}
Season.MaxGrant = 5000 -- eine einzelne Saison-XP-Gutschrift höchstens (Schutz)

-- ---------------------------------------------------------------------
-- 2) BELOHNUNGEN Saison 1 „Neon-Skyline“ (Deko-Set S1, Uhr Skyline-Chrono, Auto Orbit-R, Fassade Holo-Prisma)
-- ---------------------------------------------------------------------
local function cr(tier: number, minutes: number, min: number)
	return { Tier = tier, Credits = { Minutes = minutes, Min = min } }
end

-- stylua: ignore start
local FREE_S1 = {
	cr(2, 15, 2000),
	{ Tier = 4, Decor = { NeonBench = 1 } },
	{ Tier = 6, BoostX2 = 1800 },
	cr(8, 30, 5000),
	{ Tier = 10, Decor = { SkylineRug = 1 } },
	{ Tier = 12, InstantTokens = 1 },
	cr(14, 45, 8000),
	{ Tier = 16, Decor = { OrbitLamp = 1 } },
	{ Tier = 18, BoostX2 = 1800 },
	cr(20, 60, 12000),
	{ Tier = 22, InstantTokens = 1 },
	{ Tier = 24, Decor = { NeonPalm = 1 } },
	cr(26, 60, 15000),
	{ Tier = 28, BoostX2 = 3600 },
	cr(30, 90, 20000),
	{ Tier = 32, InstantTokens = 2 },
	cr(34, 90, 25000),
	{ Tier = 36, BoostX2 = 3600 },
	cr(38, 120, 30000),
	{ Tier = 40, InstantTokens = 2 },
	cr(42, 120, 40000),
	{ Tier = 44, BoostX2 = 3600 },
	cr(46, 150, 50000),
	{ Tier = 48, InstantTokens = 3 },
	{ Tier = 50, Title = "S1Pioneer", Credits = { Minutes = 180, Min = 80000 } },
}

local PREMIUM_S1 = {
	cr(1, 20, 3000),
	{ Tier = 2, Decor = { SkylineModel = 1 } },
	{ Tier = 3, BoostX2 = 1800 },
	cr(4, 30, 5000),
	{ Tier = 5, Decor = { NeonBench = 1 } },
	{ Tier = 6, InstantTokens = 1 },
	cr(7, 30, 6000),
	{ Tier = 8, Decor = { HoloTicker = 1 } },
	{ Tier = 9, BoostX2 = 1800 },
	{ Tier = 10, Cosmetics = { "ThemeSkyline" } }, -- Terminal-Theme „Neon-Skyline“ (rein kosmetisch)
	cr(11, 45, 8000),
	{ Tier = 12, Decor = { SkylineRug = 1 } },
	{ Tier = 13, InstantTokens = 1 },
	cr(14, 45, 9000),
	{ Tier = 15, Decor = { BlimpModel = 1 } },
	{ Tier = 16, BoostX2 = 3600 },
	cr(17, 60, 10000),
	{ Tier = 18, Decor = { OrbitLamp = 1 } },
	{ Tier = 19, InstantTokens = 1 },
	{ Tier = 20, Cosmetics = { "HoloPrism" } }, -- Fassade Holo-Prisma
	cr(21, 60, 12000),
	{ Tier = 22, Decor = { NeonPalm = 1 } },
	{ Tier = 23, BoostX2 = 3600 },
	cr(24, 75, 14000),
	{ Tier = 25, Decor = { SkylineModel = 1 } },
	{ Tier = 26, InstantTokens = 2 },
	cr(27, 75, 16000),
	{ Tier = 28, Decor = { HoloTicker = 1 } },
	{ Tier = 29, BoostX2 = 3600 },
	{ Tier = 30, Watches = { "SkylineChrono" } }, -- Uhr Skyline-Chrono
	cr(31, 90, 18000),
	{ Tier = 32, Decor = { NeonBench = 1 } },
	{ Tier = 33, InstantTokens = 2 },
	cr(34, 90, 20000),
	{ Tier = 35, Decor = { BlimpModel = 1 } },
	{ Tier = 36, BoostX2 = 5400 },
	cr(37, 105, 24000),
	{ Tier = 38, Decor = { OrbitLamp = 1 } },
	{ Tier = 39, InstantTokens = 2 },
	{ Tier = 40, Cosmetics = { "CrownFxS1" } }, -- Kronen-Effekt S1 (kosmetisch)
	cr(41, 120, 28000),
	{ Tier = 42, Decor = { NeonPalm = 1 } },
	{ Tier = 43, BoostX2 = 5400 },
	cr(44, 120, 32000),
	{ Tier = 45, Decor = { SkylineTrophy = 1 } },
	{ Tier = 46, InstantTokens = 3 },
	cr(47, 150, 40000),
	{ Tier = 48, Decor = { SkylineRug = 1 } },
	{ Tier = 49, BoostX2 = 7200 },
	{ Tier = 50, Cars = { "OrbitR" }, Title = "S1Elite" }, -- Saison-Auto Orbit-R
}
-- stylua: ignore end

-- ---------------------------------------------------------------------
-- 3) SAISONS (UTC, ISO-Zeit). Rolling: nach der letzten Saison startet automatisch die nächste mit gleicher Länge
--    und den Spuren der letzten Saison (Name „Saison n“), damit der Pass nie „leer“ ist – ehrliche Enddaten bleiben.
-- ---------------------------------------------------------------------
Season.Seasons = {
	{
		Id = 1,
		Key = "S1",
		Name = { de = "Neon-Skyline", en = "Neon Skyline" },
		StartUtc = "2026-10-12T00:00:00Z",
		EndUtc = "2026-11-09T00:00:00Z",
		Tiers = 50,
		TierXp = 1000,
		Free = FREE_S1,
		Premium = PREMIUM_S1,
		ImageId = 0,
	},
}
Season.Rolling = { Enabled = true, LengthDays = 28 }
Season.MaxSeasons = 999 -- Schutz für die Rolling-Rechnung

-- Felder, die eine Pass-Belohnung haben darf (alles andere ist ein Firewall-Fehler)
Season.AllowedFields = {
	Tier = true,
	Credits = true,
	Decor = true,
	Cosmetics = true,
	Watches = true,
	Cars = true,
	Accessories = true,
	BoostX2 = true,
	InstantTokens = true,
	Title = true,
}
-- Teile, die eine NUR GEKAUFTE Stufe nicht auszahlt (CR/Boost/Token = einkommenswirksam)
Season.EarnedOnlyFields = { Credits = true, BoostX2 = true, InstantTokens = true }

-- =====================================================================
-- PRÜFUNG (Config.Validate sammelt alle Meldungen; leer = alles ok)
-- =====================================================================
local function isNum(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isInt(v: any): boolean
	return isNum(v) and v % 1 == 0
end

local function isIso(text: any): boolean
	return type(text) == "string" and string.match(text, "^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$") ~= nil
end

local function checkReward(add: (string) -> (), where: string, reward: any, tiers: number)
	if type(reward) ~= "table" then
		add(where .. ": Tabelle erwartet")
		return
	end
	if not isInt(reward.Tier) or reward.Tier < 1 or reward.Tier > tiers then
		add(where .. ".Tier: 1 … " .. tiers .. " erwartet")
	end
	local any = false
	for field, value in pairs(reward) do
		if not Season.AllowedFields[field] then
			add(where .. ": Feld " .. tostring(field) .. " ist nicht erlaubt (nur Turm-Seite, §0.4)")
		elseif field ~= "Tier" then
			any = true
			if field == "Credits" then
				if type(value) ~= "table" or not isNum(value.Minutes) or value.Minutes <= 0 or not isInt(value.Min) then
					add(where .. ".Credits: { Minutes > 0, Min (ganze Zahl) } erwartet")
				end
			elseif field == "BoostX2" or field == "InstantTokens" then
				if not isInt(value) or value < 1 then
					add(where .. "." .. field .. ": ganze Zahl ≥ 1 erwartet")
				end
			elseif field == "Decor" then
				if type(value) ~= "table" or next(value) == nil then
					add(where .. ".Decor: { [Key] = Anzahl } erwartet")
				else
					for key, n in pairs(value) do
						if type(key) ~= "string" or not isInt(n) or n < 1 then
							add(where .. ".Decor: { [Key] = Anzahl ≥ 1 } erwartet")
						end
					end
				end
			elseif field == "Title" then
				if type(value) ~= "string" or value == "" then
					add(where .. ".Title: Titel-Schlüssel erwartet")
				end
			elseif type(value) ~= "table" or #value == 0 then
				add(where .. "." .. field .. ": Liste von Schlüsseln erwartet")
			end
		end
	end
	if not any then
		add(where .. ": leere Belohnung")
	end
end

function Season.Validate(config: any): { string }
	local errors: { string } = {}
	local function add(text: string)
		table.insert(errors, "Config.Season." .. text)
	end
	local titles = if type(config) == "table" and type(config.Progression) == "table"
		then config.Progression.TitleByKey
		else nil
	if #Season.Seasons < 1 then
		add("Seasons: mindestens eine Saison erwartet")
	end
	local lastId = 0
	for i, s in ipairs(Season.Seasons) do
		local where = ("Seasons[%d]"):format(i)
		if not isInt(s.Id) or s.Id <= lastId then
			add(where .. ".Id: steigende ganze Zahl erwartet")
		end
		lastId = if isInt(s.Id) then s.Id else lastId
		if type(s.Name) ~= "table" or type(s.Name.de) ~= "string" or type(s.Name.en) ~= "string" then
			add(where .. ".Name: { de, en } erwartet")
		end
		if not isIso(s.StartUtc) or not isIso(s.EndUtc) or s.EndUtc <= s.StartUtc then
			add(where .. ": StartUtc < EndUtc (ISO, UTC) erwartet")
		end
		if not isInt(s.Tiers) or s.Tiers < 1 or not isInt(s.TierXp) or s.TierXp < 1 then
			add(where .. ": Tiers/TierXp ganze Zahlen ≥ 1 erwartet")
		end
		local tiers = if isInt(s.Tiers) then s.Tiers else 50
		local seen: { [string]: boolean } = {}
		for track, list in pairs({ Free = s.Free, Premium = s.Premium }) do
			if type(list) ~= "table" then
				add(where .. "." .. track .. ": Liste erwartet")
				continue
			end
			for j, reward in ipairs(list) do
				local w = ("%s.%s[%d]"):format(where, track, j)
				checkReward(add, w, reward, tiers)
				if type(reward) == "table" and isInt(reward.Tier) then
					local id = track .. ":" .. reward.Tier
					if seen[id] then
						add(w .. ": Stufe doppelt")
					end
					seen[id] = true
				end
				if titles and type(reward) == "table" and reward.Title ~= nil and not titles[reward.Title] then
					add(w .. ".Title: unbekannter Titel " .. tostring(reward.Title))
				end
			end
		end
		if type(s.Free) == "table" and #s.Free ~= 25 then
			add(where .. ".Free: 25 Belohnungen erwartet (§B9.9)")
		end
		if type(s.Premium) == "table" and #s.Premium ~= 50 then
			add(where .. ".Premium: 50 Belohnungen erwartet (§B9.9)")
		end
	end
	if type(Season.Rolling) ~= "table" or not isInt(Season.Rolling.LengthDays) or Season.Rolling.LengthDays < 1 then
		add("Rolling.LengthDays: ganze Zahl ≥ 1 erwartet")
	end
	local playtime = Season.XpSources.Playtime
	if not isInt(playtime.Xp) or not isInt(playtime.Minutes) or playtime.Minutes < 1 then
		add("XpSources.Playtime: { Xp, Minutes ≥ 1, MaxMinutes } erwartet")
	end
	return errors
end

return Season
