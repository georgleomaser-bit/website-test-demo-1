-- =====================================================================
--  CLUTCH CLASH – CLUTCH PASS / SAISONS (Config.Season)
--  Besitzer: WP8 (Fortschritt). Vertrag: DESIGN.md C15 + B21.2.
--
--  So legst du eine NEUE SAISON an (Anleitung, Abschnitt "Neue Saison"):
--    1. Den kompletten Block { Id = 1, … } unten kopieren und hinter die letzte Saison setzen.
--    2. Id um 1 erhöhen – eine Id wird NIE wiederverwendet (sonst gelten alte Einlösungen weiter).
--    3. StartUtc/EndUtc anpassen (UTC, Format "JJJJ-MM-TTT00:00:00Z"), Name, Farben, Belohnungen.
--    4. Play drücken und im Output auf "[SelfTest]"- bzw. "[Config]"-Meldungen achten.
--  Fallback (das Spiel funktioniert immer): Passt kein Datumsfenster, bleibt die Saison mit dem
--  jüngsten StartUtc ≤ jetzt aktiv; liegt jetzt vor der ersten Saison, ist Saison 1 aktiv.
--
--  Belohnungs-Felder je Stufe ("<Stufe>" als Text-Schlüssel):
--    Coins, Gems, Keys, Shards = Anzahl · Cosmetic = Kosmetik-Id (Skin/Wrap/Charm/Finisher/Tracer/Titel "TT_…")
--  Gratis-Spur: jede 2. Stufe. Premium-Spur: jede Stufe, NIE Coins oder Schlüssel (kein Pay-to-Win).
-- =====================================================================

local Season = {}

Season.Seasons = {
	{
		Id = 1,
		Name = { de = "Saison 1: Neon-Start", en = "Season 1: Neon Start" },
		StartUtc = "2026-10-15T00:00:00Z",
		EndUtc = "2026-12-10T00:00:00Z",
		Tiers = 30,
		TierXp = 3000,
		Theme = { Primary = Color3.fromRGB(255, 60, 170), Accent = Color3.fromRGB(0, 230, 255) },
		Free = {
			["2"] = { Coins = 300 },
			["4"] = { Keys = 1 },
			["6"] = { Coins = 300 },
			["8"] = { Gems = 30 },
			["10"] = { Coins = 300 },
			["12"] = { Keys = 1 },
			["14"] = { Coins = 300 },
			["16"] = { Gems = 30 },
			["18"] = { Coins = 300 },
			["20"] = { Keys = 1 },
			["22"] = { Gems = 30 },
			["24"] = { Gems = 30 },
			["26"] = { Gems = 30 },
			["28"] = { Keys = 1 },
			["30"] = { Cosmetic = "TT_S1Veteran" },
		},
		Premium = {
			["1"] = { Cosmetic = "S_PipPistol_RayGun" },
			["2"] = { Gems = 50 },
			["3"] = { Cosmetic = "W_S1_Neon" },
			["4"] = { Shards = 100 },
			["5"] = { Cosmetic = "C_Ghost" },
			["6"] = { Gems = 50 },
			["7"] = { Cosmetic = "W_S1_Sunset" },
			["8"] = { Shards = 100 },
			["9"] = { Cosmetic = "C_Cactus" },
			["10"] = { Gems = 50 },
			["11"] = { Cosmetic = "W_S1_Ice" },
			["12"] = { Shards = 100 },
			["13"] = { Cosmetic = "F_RainbowPuff" },
			["14"] = { Gems = 50 },
			["15"] = { Cosmetic = "W_S1_Gold" },
			["16"] = { Shards = 100 },
			["17"] = { Cosmetic = "C_Crown" },
			["18"] = { Gems = 50 },
			["19"] = { Cosmetic = "W_S1_Circuit" },
			["20"] = { Cosmetic = "TT_PassHolderS1" },
			["21"] = { Cosmetic = "T_Zigzag" },
			["22"] = { Gems = 50 },
			["23"] = { Cosmetic = "F_BalloonFloat" },
			["24"] = { Shards = 100 },
			["25"] = { Cosmetic = "C_Trophy" },
			["26"] = { Gems = 50 },
			["27"] = { Cosmetic = "W_S1_Champion" },
			["28"] = { Gems = 100 },
			["29"] = { Cosmetic = "T_Rainbow" },
			["30"] = { Cosmetic = "S_PopRifle_CarrotCannon" },
		},
	},
}

-- =====================================================================
-- PRÜFEN (Config.Validate sammelt das)
-- =====================================================================
local REWARD_FIELDS = { Coins = true, Gems = true, Keys = true, Shards = true, Cosmetic = true }

-- "JJJJ-MM-TTTHH:MM:SSZ" -> Sekunden (nur zum Vergleichen; ProgressMath.ParseIsoUtc rechnet genauso)
local function parseIso(text: any): number?
	if type(text) ~= "string" then
		return nil
	end
	local y, mo, d, h, mi, s = string.match(text, "^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)Z$")
	if not y then
		return nil
	end
	local month = tonumber(mo) :: number
	local day = tonumber(d) :: number
	if month < 1 or month > 12 or day < 1 or day > 31 then
		return nil
	end
	return ((((tonumber(y) :: number) * 12 + month) * 31 + day) * 24 + (tonumber(h) :: number)) * 3600
		+ (tonumber(mi) :: number) * 60
		+ tonumber(s) :: number
end

local function isNumber(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function Season.Validate(Config: any): { string }
	local errors: { string } = {}
	local function err(path: string, text: string)
		table.insert(errors, "Config.Season." .. path .. ": " .. text)
	end
	if type(Season.Seasons) ~= "table" or #Season.Seasons == 0 then
		err("Seasons", "mindestens eine Saison erwartet")
		return errors
	end
	local ids: { [number]: boolean } = {}
	local cosmetics = Config and Config.Cosmetics
	local function cosmeticKnown(id: string): boolean
		if type(cosmetics) ~= "table" or next(cosmetics) == nil then
			return true -- Kosmetik-Config (WP9) noch nicht da -> nicht prüfen
		end
		for _, group in ipairs({ "Wraps", "Skins", "Charms", "Finishers", "Tracers", "Titles" }) do
			local t = cosmetics[group]
			if type(t) == "table" and t[id] ~= nil then
				return true
			end
		end
		return false
	end
	for index, season in ipairs(Season.Seasons) do
		local p = ("Seasons[%d]"):format(index)
		if not isNumber(season.Id) or season.Id < 1 or season.Id % 1 ~= 0 then
			err(p .. ".Id", "ganze Zahl ≥ 1 erwartet")
		elseif ids[season.Id] then
			err(p .. ".Id", "Saison-Id " .. season.Id .. " doppelt – Ids nie wiederverwenden!")
		else
			ids[season.Id] = true
		end
		if type(season.Name) ~= "table" or type(season.Name.de) ~= "string" or type(season.Name.en) ~= "string" then
			err(p .. ".Name", "{ de, en } erwartet")
		end
		local start, finish = parseIso(season.StartUtc), parseIso(season.EndUtc)
		if not start then
			err(p .. ".StartUtc", 'Datum "JJJJ-MM-TTT00:00:00Z" erwartet')
		end
		if not finish then
			err(p .. ".EndUtc", 'Datum "JJJJ-MM-TTT00:00:00Z" erwartet')
		end
		if start and finish and finish <= start then
			err(p .. ".EndUtc", "muss nach StartUtc liegen")
		end
		if not isNumber(season.Tiers) or season.Tiers < 1 or season.Tiers % 1 ~= 0 then
			err(p .. ".Tiers", "ganze Zahl ≥ 1 erwartet")
		end
		if not isNumber(season.TierXp) or season.TierXp < 1 then
			err(p .. ".TierXp", "Zahl ≥ 1 erwartet")
		end
		if type(season.Theme) ~= "table" or typeof(season.Theme.Primary) ~= "Color3" then
			err(p .. ".Theme.Primary", "Color3 erwartet")
		end
		local tiers = if isNumber(season.Tiers) then season.Tiers else 0
		for _, track in ipairs({ "Free", "Premium" }) do
			local rewards = season[track]
			if type(rewards) ~= "table" then
				err(p .. "." .. track, "Tabelle erwartet")
				continue
			end
			for key, reward in pairs(rewards) do
				local rp = ('%s.%s["%s"]'):format(p, track, tostring(key))
				local tier = tonumber(key)
				if type(key) ~= "string" or tier == nil or tier < 1 or tier > tiers or tier % 1 ~= 0 then
					err(rp, 'Schlüssel muss eine Stufe "1"…"' .. tostring(tiers) .. '" (Text) sein')
				end
				if type(reward) ~= "table" or next(reward) == nil then
					err(rp, "Belohnung erwartet")
					continue
				end
				for field, value in pairs(reward) do
					if not REWARD_FIELDS[field] then
						err(rp .. "." .. tostring(field), "unbekanntes Feld")
					elseif field == "Cosmetic" then
						if type(value) ~= "string" or value == "" then
							err(rp .. ".Cosmetic", "Kosmetik-Id erwartet")
						elseif not cosmeticKnown(value) then
							err(rp .. ".Cosmetic", "unbekannte Kosmetik " .. value .. " (Config.Cosmetics)")
						end
					elseif not isNumber(value) or value <= 0 or value % 1 ~= 0 then
						err(rp .. "." .. field, "ganze Zahl > 0 erwartet")
					end
					if track == "Premium" and (field == "Coins" or field == "Keys") then
						err(rp .. "." .. field, "Premium darf KEINE Coins/Schlüssel geben (B21.2)")
					end
				end
			end
		end
	end
	return errors
end

return Season
