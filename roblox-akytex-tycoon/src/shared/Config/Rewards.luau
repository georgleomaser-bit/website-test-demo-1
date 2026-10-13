-- =====================================================================
--  AKYTEX TYCOON – Login-Kalender, Codes, Rückkehr-Belohnungen (Config.Rewards)
--  Besitzer: WP9 (Fortschritt, Tutorial, Sozial, Bestenlisten). Vertrag: DESIGN.md §C14.2 (Rewards), §B9.9
--  (Login deterministisch, nie Rad; 1 Gratis-Serien-Schutz je Woche, Club +1, max. 2; KEIN bezahlter Serien-Retter),
--  §B9.9 Rückkehr (≥ 14 Tage: 3 h Boost x2 + Aufhol-Quest · ≥ 60 Tage: + Rückkehrer-Neon), §C14.1 LiveFields
--  ("Rewards.Codes.*": Codes nur CR/Kosmetik, live änderbar und geklemmt).
--  Alle Zahlen sind Startwerte und 1:1 änderbar. Wird an alle Clients repliziert -> KEINE Geheimnisse hier
--  (Codes sind öffentlich gedacht: Social-Links/Events). Diese Datei lädt KEINE Roblox-Dienste -> Luau-CLI-ladbar.
--
--  Belohnungs-Felder wie Config.Season: Credits = { Minutes, Min } · Decor · Cosmetics · Watches · Cars · BoostX2 ·
--    InstantTokens · SeasonXp (nur Login Tag 6). Der tägliche Gratis-Sofortbau-Token kommt von TowerService.
--  Helfer: Rewards.Validate(Config): { string }
-- =====================================================================

local Rewards = {}

-- ---------------------------------------------------------------------
-- 1) LOGIN-KALENDER (§B9.9) – 7er-Zyklus + 28er-Spur (zählt abgeholte Tage, Serie egal)
-- ---------------------------------------------------------------------
Rewards.Login = {
	Cycle = {
		{ Day = 1, Credits = { Minutes = 15, Min = 1000 } },
		{ Day = 2, Cosmetics = { "Accent" } }, -- Lack „Akzentblau“
		{ Day = 3, BoostX2 = 1800 }, -- Boost x2 30 min (Spielzeit)
		{ Day = 4, Decor = { MiniBull = 1 } }, -- Deko „Mini-Bulle“
		{ Day = 5, Credits = { Minutes = 60, Min = 3000 } },
		{ Day = 6, SeasonXp = 300 },
		{ Day = 7, Watches = { "WeekChrono" }, Repeat = { Credits = { Minutes = 180, Min = 8000 } } }, -- ab Zyklus 2
	},
	Track = {
		{ Day = 14, Cosmetics = { "Obsidian" } }, -- Fassade Obsidian
		{ Day = 28, Cars = { "StreakGT" }, Cosmetics = { "Polar" } }, -- Auto Streak-GT + Fassade Polar
	},
	TrackMax = 28,
	FreezePerWeek = 1, -- Gratis-Serien-Schutz je ISO-Woche …
	FreezeClubBonus = 1, -- … Vorstands-Club +1 (Abo-Vorteil, Komfort – kein Spielvorteil)
	FreezeMax = 2, -- höchstens so viele gespeichert
}

-- ---------------------------------------------------------------------
-- 2) CODES (nur CR/Kosmetik – Firewall; Großschreibung egal; ≤ 20 Zeichen; Expires = ISO-UTC oder nil)
--    Live änderbar über Config.LiveFields "Rewards.Codes.*" (Admin-Tab Live-Ops, geprüft und geklemmt).
-- ---------------------------------------------------------------------
Rewards.Codes = {
	LAUNCH = { Grant = { Credits = 5000 }, Expires = "2027-01-31T00:00:00Z" },
}
Rewards.CodeMaxLength = 20
Rewards.CodesKeep = 200 -- eingelöste Codes je Spieler (Liste begrenzt)

-- ---------------------------------------------------------------------
-- 3) RÜCKKEHR (§B9.9) – gemessen an SavedAt (Server-Zeit) beim Beitritt
-- ---------------------------------------------------------------------
Rewards.WinBack = {
	Days = 14, -- ≥ 14 Tage weg …
	BoostX2 = 10800, -- … 3 h Boost x2 (Spielzeit) + Aufhol-Quest (Config.Progression.Quests.Comeback)
	LongDays = 60, -- ≥ 60 Tage weg: zusätzlich …
	LongCosmetics = { "Returner" }, -- … Rückkehrer-Fassaden-Neon
}

-- ---------------------------------------------------------------------
-- 4) SPIELZEIT (Saison-XP) – Takt der Zählung
-- ---------------------------------------------------------------------
Rewards.PlaytimeTick = 60 -- Sekunden je Zähl-Schritt (Saison-XP alle 10 min laut Config.Season)

-- =====================================================================
-- PRÜFUNG (Config.Validate sammelt alle Meldungen; leer = alles ok)
-- =====================================================================
local function isNum(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isInt(v: any): boolean
	return isNum(v) and v % 1 == 0
end

local ALLOWED = {
	Day = true,
	Credits = true,
	Decor = true,
	Cosmetics = true,
	Watches = true,
	Cars = true,
	BoostX2 = true,
	InstantTokens = true,
	SeasonXp = true,
	Repeat = true,
}

local function checkReward(add: (string) -> (), where: string, reward: any)
	if type(reward) ~= "table" then
		add(where .. ": Tabelle erwartet")
		return
	end
	for field, value in pairs(reward) do
		if not ALLOWED[field] then
			add(where .. ": Feld " .. tostring(field) .. " nicht erlaubt (nur Turm-Seite, §0.4)")
		elseif field == "Credits" then
			if type(value) ~= "table" or not isNum(value.Minutes) or value.Minutes <= 0 or not isInt(value.Min) then
				add(where .. ".Credits: { Minutes > 0, Min } erwartet")
			end
		elseif field == "BoostX2" or field == "InstantTokens" or field == "SeasonXp" then
			if not isInt(value) or value < 1 then
				add(where .. "." .. field .. ": ganze Zahl ≥ 1 erwartet")
			end
		elseif field == "Repeat" then
			checkReward(add, where .. ".Repeat", value)
		elseif field == "Decor" then
			if type(value) ~= "table" then
				add(where .. ".Decor: { [Key] = Anzahl } erwartet")
			end
		elseif field ~= "Day" and (type(value) ~= "table" or #value == 0) then
			add(where .. "." .. field .. ": Liste erwartet")
		end
	end
end

local function isIso(text: any): boolean
	return type(text) == "string" and string.match(text, "^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$") ~= nil
end

function Rewards.Validate(_config: any): { string }
	local errors: { string } = {}
	local function add(text: string)
		table.insert(errors, "Config.Rewards." .. text)
	end
	local login = Rewards.Login
	if #login.Cycle ~= 7 then
		add("Login.Cycle: 7 Tage erwartet")
	end
	for i, reward in ipairs(login.Cycle) do
		if reward.Day ~= i then
			add(("Login.Cycle[%d].Day: %d erwartet"):format(i, i))
		end
		checkReward(add, ("Login.Cycle[%d]"):format(i), reward)
	end
	for i, reward in ipairs(login.Track) do
		if not isInt(reward.Day) or reward.Day < 1 or reward.Day > login.TrackMax then
			add(("Login.Track[%d].Day: 1 … %d erwartet"):format(i, login.TrackMax))
		end
		checkReward(add, ("Login.Track[%d]"):format(i), reward)
	end
	if not isInt(login.FreezeMax) or login.FreezeMax < 0 or not isInt(login.FreezePerWeek) then
		add("Login.Freeze*: ganze Zahlen erwartet")
	end
	for code, entry in pairs(Rewards.Codes) do
		local where = "Codes." .. tostring(code)
		if type(code) ~= "string" or #code > Rewards.CodeMaxLength or string.match(code, "^[%w_]+$") == nil then
			add(where .. ": Code aus Buchstaben/Ziffern, ≤ " .. Rewards.CodeMaxLength .. " Zeichen erwartet")
		end
		if code ~= string.upper(code) then
			add(where .. ": Codes in GROSSBUCHSTABEN eintragen")
		end
		if type(entry) ~= "table" or type(entry.Grant) ~= "table" then
			add(where .. ".Grant: Tabelle erwartet")
		else
			for field, value in pairs(entry.Grant) do
				if field == "Credits" then
					if not isInt(value) or value < 1 or value >= 1e14 then
						add(where .. ".Grant.Credits: ganze Zahl 1 … 1e14 erwartet")
					end
				elseif field ~= "Cosmetics" then
					add(where .. ".Grant: nur Credits/Cosmetics erlaubt (Firewall)")
				end
			end
			if entry.Expires ~= nil and not isIso(entry.Expires) then
				add(where .. ".Expires: ISO-UTC (JJJJ-MM-TTThh:mm:ssZ) erwartet")
			end
		end
	end
	local winBack = Rewards.WinBack
	if not isInt(winBack.Days) or not isInt(winBack.LongDays) or winBack.LongDays < winBack.Days then
		add("WinBack: Days ≤ LongDays (ganze Zahlen) erwartet")
	end
	return errors
end

return Rewards
