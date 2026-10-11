--!strict
-- =====================================================================
--  CLUTCH CLASH – Maps & Licht-Stimmungen (Shared/Config/Maps)
--  Besitzer: WP2 (Welt). Vertrag: DESIGN.md C15 (Config/Maps), B8.1–B8.3, B9.
--  Erreichbar als Config.Maps (wird von Config/init dynamisch geladen).
--
--  Inhalt:
--    Maps         = 6 Arenen + Crown Ring: Name {de,en}, Größenklasse, Teamgrößen, Modi,
--                   Stimmungs-Gewichte (oder ForcedMood), Teilebudget
--    Moods        = 5 Licht-Stimmungen (B8.2) – NUR client-lokal (ArenaLook), die Lobby nutzt LobbyMood
--    LobbyMood, StagingOrigin (Template-Bau), CrownOrigin (Crown Ring in der Lobby), Nav (Nav-Graph)
--    Validate(Config): { string }   Fehlertexte mit exaktem Pfad (leere Liste = alles ok)
--
--  Ändern ohne Code: Gewichte/Stimmungen/Budgets hier anpassen. Die Map-GEOMETRIE steht in
--  src/server/World/Maps/<Key>.luau.
-- =====================================================================

export type MoodDef = {
	ClockTime: number,
	Ambient: Color3,
	OutdoorAmbient: Color3,
	Atmosphere: {
		Density: number,
		Haze: number,
		Color: Color3,
		Decay: Color3,
		Glare: number,
		Offset: number,
	},
	Bloom: { Intensity: number, Size: number, Threshold: number },
	ColorCorrection: { Saturation: number, Contrast: number, Brightness: number, TintColor: Color3 },
	Snow: boolean,
}

export type MapDef = {
	Name: { de: string, en: string },
	Class: "S" | "M" | "L",
	TeamSizes: { number },
	Modes: { string },
	Moods: { [string]: number }?,
	ForcedMood: string?,
	Fixed: boolean?,
	PartBudget: number,
}

local WHITE = Color3.fromRGB(255, 255, 255)

local Maps = {}

-- ---------------------------------------------------------------------
-- 1) ARENEN (B8.3) – Modi/Teamgrößen bestimmen, welche Karten im Vote erscheinen
-- ---------------------------------------------------------------------
local MAPS: { [string]: MapDef } = {
	PillarBox = {
		Name = { de = "Säulenkiste", en = "Pillar Box" },
		Class = "S",
		TeamSizes = { 1, 2 },
		Modes = { "Duel1", "Duel2", "Mutator", "Practice" },
		Moods = { Day = 40, Sunset = 30, NeonNight = 15, Fog = 15 },
		PartBudget = 700,
	},
	BlockYard = {
		Name = { de = "Bauklotz-Hof", en = "Block Yard" },
		Class = "M",
		TeamSizes = { 1, 2, 3, 4 },
		Modes = { "Duel1", "Duel2", "Duel3", "Duel4", "Mutator", "Practice", "FFA" },
		Moods = { Day = 45, Sunset = 35, Fog = 20 },
		PartBudget = 900,
	},
	NeonGrid = {
		Name = { de = "Neon-Raster", en = "Neon Grid" },
		Class = "S",
		TeamSizes = { 1, 2 },
		Modes = { "Duel1", "Duel2", "Mutator", "Practice", "FFA" },
		ForcedMood = "NeonNight",
		PartBudget = 700,
	},
	CandyDocks = {
		Name = { de = "Zuckerhafen", en = "Candy Docks" },
		Class = "L",
		TeamSizes = { 2, 3, 4 },
		Modes = { "Duel2", "Duel3", "Duel4", "FFA" },
		Moods = { Day = 40, Sunset = 35, Fog = 25 },
		PartBudget = 1100,
	},
	SnowFort = {
		Name = { de = "Schneefestung", en = "Snow Fort" },
		Class = "M",
		TeamSizes = { 2, 3, 4 },
		Modes = { "Duel2", "Duel3", "Duel4" },
		ForcedMood = "Snowy",
		PartBudget = 900,
	},
	SkyGarden = {
		Name = { de = "Himmelsgarten", en = "Sky Garden" },
		Class = "M",
		TeamSizes = { 1, 2, 3 },
		Modes = { "Duel1", "Duel2", "Duel3", "Mutator", "Practice", "FFA" },
		Moods = { Day = 45, Sunset = 35, NeonNight = 20 },
		PartBudget = 800,
	},
	CrownRing = {
		Name = { de = "Kronen-Ring", en = "Crown Ring" },
		Class = "S",
		TeamSizes = { 1 },
		Modes = { "Crown" },
		Fixed = true, -- fest in der Lobby (Slot 0), nie im Vote, nie in Slot 1..8
		PartBudget = 400,
	},
}
Maps.Maps = MAPS

-- ---------------------------------------------------------------------
-- 2) LICHT-STIMMUNGEN (B8.2) – Werte 1:1 aus der Tabelle.
--    Atmosphere-Dichte immer ≥ 0.32 (fremde Welten verschwinden im Dunst, B9.4).
-- ---------------------------------------------------------------------
local MOODS: { [string]: MoodDef } = {
	Day = {
		ClockTime = 14,
		Ambient = Color3.fromRGB(140, 140, 150),
		OutdoorAmbient = Color3.fromRGB(150, 150, 160),
		Atmosphere = {
			Density = 0.32,
			Haze = 1.0,
			Color = Color3.fromRGB(199, 210, 230),
			Decay = Color3.fromRGB(106, 112, 125),
			Glare = 0,
			Offset = 0.25,
		},
		Bloom = { Intensity = 0.5, Size = 24, Threshold = 1.6 },
		ColorCorrection = { Saturation = 0.15, Contrast = 0.05, Brightness = 0, TintColor = WHITE },
		Snow = false,
	},
	Sunset = {
		ClockTime = 17.6,
		Ambient = Color3.fromRGB(170, 120, 100),
		OutdoorAmbient = Color3.fromRGB(190, 130, 110),
		Atmosphere = {
			Density = 0.35,
			Haze = 1.5,
			Color = Color3.fromRGB(255, 190, 150),
			Decay = Color3.fromRGB(190, 110, 90),
			Glare = 0,
			Offset = 0.25,
		},
		Bloom = { Intensity = 0.6, Size = 24, Threshold = 1.5 },
		ColorCorrection = {
			Saturation = 0.2,
			Contrast = 0,
			Brightness = 0,
			TintColor = Color3.fromRGB(255, 235, 215),
		},
		Snow = false,
	},
	NeonNight = {
		ClockTime = 0.5,
		Ambient = Color3.fromRGB(60, 60, 90),
		OutdoorAmbient = Color3.fromRGB(40, 40, 70),
		Atmosphere = {
			Density = 0.32,
			Haze = 0.8,
			Color = Color3.fromRGB(60, 60, 120),
			Decay = Color3.fromRGB(40, 40, 90),
			Glare = 0,
			Offset = 0.25,
		},
		Bloom = { Intensity = 1.0, Size = 32, Threshold = 1.2 },
		ColorCorrection = { Saturation = 0.25, Contrast = 0, Brightness = 0, TintColor = WHITE },
		Snow = false,
	},
	Fog = {
		ClockTime = 12,
		Ambient = Color3.fromRGB(150, 150, 150),
		OutdoorAmbient = Color3.fromRGB(150, 150, 155),
		Atmosphere = {
			Density = 0.45,
			Haze = 2.5,
			Color = Color3.fromRGB(200, 200, 205),
			Decay = Color3.fromRGB(180, 180, 185),
			Glare = 0,
			Offset = 0.25,
		},
		Bloom = { Intensity = 0.3, Size = 24, Threshold = 1.8 },
		ColorCorrection = { Saturation = -0.1, Contrast = 0, Brightness = 0, TintColor = WHITE },
		Snow = false,
	},
	Snowy = {
		ClockTime = 13,
		Ambient = Color3.fromRGB(170, 180, 200),
		OutdoorAmbient = Color3.fromRGB(180, 190, 210),
		Atmosphere = {
			Density = 0.38,
			Haze = 1.5,
			Color = Color3.fromRGB(220, 230, 245),
			Decay = Color3.fromRGB(200, 210, 230),
			Glare = 0,
			Offset = 0.25,
		},
		Bloom = { Intensity = 0.4, Size = 24, Threshold = 1.6 },
		ColorCorrection = { Saturation = 0.05, Contrast = 0, Brightness = 0, TintColor = WHITE },
		Snow = true, -- Schnee-Emitter an der Kamera (smoke_main.dds, weiß, Size 0.15, Rate 60)
	},
}
Maps.Moods = MOODS

-- ---------------------------------------------------------------------
-- 3) WELT-KONSTANTEN
-- ---------------------------------------------------------------------
Maps.LobbyMood = "Day" -- Lobby, Range und Crown Ring
Maps.StagingOrigin = Vector3.new(0, 3000, 0) -- hier steht jede Map beim Boot kurz für Nav-Graph + Spawn-Prüfung
Maps.CrownOrigin = Vector3.new(95, -6, 0) -- Welt-Ursprung des Crown Rings (Grubenboden-Oberkante)
Maps.Nav = { Grid = 6, Headroom = 5.5, StepMax = 4.5, MaxNodes = 300 }
Maps.DefaultKillY = -40 -- lokal unter der Map-Oberkante (gilt, wenn eine Map keine eigene KillY hat)
Maps.BarrierCeiling = 40 -- Decke der automatischen Barrieren (B8.1)
Maps.NeonShare = 0.08 -- Richtwert: höchstens ~8 % Neon-Teile pro Map (A4)

-- ---------------------------------------------------------------------
-- 4) PRÜFEN (Config.Validate sammelt das ein)
-- ---------------------------------------------------------------------
local CLASSES = { S = true, M = true, L = true }

local function isFinite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function checkColor(errors: { string }, path: string, value: any)
	if typeof(value) ~= "Color3" then
		table.insert(errors, path .. ": Color3 erwartet")
	end
end

local function checkNumber(errors: { string }, path: string, value: any, lo: number?, hi: number?)
	if not isFinite(value) then
		table.insert(errors, path .. ": Zahl erwartet")
		return
	end
	if lo ~= nil and value < lo then
		table.insert(errors, ("%s: mindestens %s erwartet"):format(path, tostring(lo)))
	end
	if hi ~= nil and value > hi then
		table.insert(errors, ("%s: höchstens %s erwartet"):format(path, tostring(hi)))
	end
end

local function validateMood(errors: { string }, key: string, mood: any)
	local path = "Config.Maps.Moods." .. key
	if type(mood) ~= "table" then
		table.insert(errors, path .. ": Tabelle erwartet")
		return
	end
	checkNumber(errors, path .. ".ClockTime", mood.ClockTime, 0, 24)
	checkColor(errors, path .. ".Ambient", mood.Ambient)
	checkColor(errors, path .. ".OutdoorAmbient", mood.OutdoorAmbient)
	local atmo = mood.Atmosphere
	if type(atmo) ~= "table" then
		table.insert(errors, path .. ".Atmosphere: Tabelle erwartet")
	else
		-- B9.4: Dichte ≥ 0.32 in ALLEN Stimmungen (sonst sieht man fremde Arenen)
		checkNumber(errors, path .. ".Atmosphere.Density", atmo.Density, 0.32, 1)
		checkNumber(errors, path .. ".Atmosphere.Haze", atmo.Haze, 0, 10)
		checkNumber(errors, path .. ".Atmosphere.Glare", atmo.Glare, 0, 10)
		checkNumber(errors, path .. ".Atmosphere.Offset", atmo.Offset, 0, 1)
		checkColor(errors, path .. ".Atmosphere.Color", atmo.Color)
		checkColor(errors, path .. ".Atmosphere.Decay", atmo.Decay)
	end
	local bloom = mood.Bloom
	if type(bloom) ~= "table" then
		table.insert(errors, path .. ".Bloom: Tabelle erwartet")
	else
		checkNumber(errors, path .. ".Bloom.Intensity", bloom.Intensity, 0, 5)
		checkNumber(errors, path .. ".Bloom.Size", bloom.Size, 0, 56)
		checkNumber(errors, path .. ".Bloom.Threshold", bloom.Threshold, 0, 4)
	end
	local cc = mood.ColorCorrection
	if type(cc) ~= "table" then
		table.insert(errors, path .. ".ColorCorrection: Tabelle erwartet")
	else
		checkNumber(errors, path .. ".ColorCorrection.Saturation", cc.Saturation, -1, 1)
		checkNumber(errors, path .. ".ColorCorrection.Contrast", cc.Contrast, -1, 1)
		checkNumber(errors, path .. ".ColorCorrection.Brightness", cc.Brightness, -1, 1)
		checkColor(errors, path .. ".ColorCorrection.TintColor", cc.TintColor)
	end
	if type(mood.Snow) ~= "boolean" then
		table.insert(errors, path .. ".Snow: true/false erwartet")
	end
end

local function validateMap(errors: { string }, key: string, map: any, knownModes: { [string]: any }?)
	local path = "Config.Maps.Maps." .. key
	if type(map) ~= "table" then
		table.insert(errors, path .. ": Tabelle erwartet")
		return
	end
	if type(map.Name) ~= "table" or type(map.Name.de) ~= "string" or type(map.Name.en) ~= "string" then
		table.insert(errors, path .. ".Name: { de, en } erwartet")
	end
	if not CLASSES[map.Class] then
		table.insert(errors, path .. '.Class: "S", "M" oder "L" erwartet')
	end
	if type(map.TeamSizes) ~= "table" or #map.TeamSizes == 0 then
		table.insert(errors, path .. ".TeamSizes: Liste erwartet")
	else
		for i, size in ipairs(map.TeamSizes) do
			if not isFinite(size) or size < 1 or size > 4 or size % 1 ~= 0 then
				table.insert(errors, ("%s.TeamSizes[%d]: ganze Zahl 1–4 erwartet"):format(path, i))
			end
		end
	end
	if type(map.Modes) ~= "table" or #map.Modes == 0 then
		table.insert(errors, path .. ".Modes: Liste erwartet")
	else
		for i, mode in ipairs(map.Modes) do
			if type(mode) ~= "string" then
				table.insert(errors, ("%s.Modes[%d]: Text erwartet"):format(path, i))
			elseif knownModes and knownModes[mode] == nil then
				table.insert(errors, ("%s.Modes[%d]: unbekannter Modus %s"):format(path, i, mode))
			end
		end
	end
	if map.ForcedMood ~= nil then
		if type(map.ForcedMood) ~= "string" or MOODS[map.ForcedMood] == nil then
			table.insert(errors, path .. ".ForcedMood: unbekannte Stimmung " .. tostring(map.ForcedMood))
		end
	elseif not map.Fixed then
		if type(map.Moods) ~= "table" then
			table.insert(errors, path .. ".Moods: Gewichte oder ForcedMood erwartet")
		else
			local total = 0
			for mood, weight in pairs(map.Moods) do
				if type(mood) ~= "string" or MOODS[mood] == nil then
					table.insert(errors, path .. ".Moods: unbekannte Stimmung " .. tostring(mood))
				elseif not isFinite(weight) or weight < 0 then
					table.insert(errors, path .. ".Moods." .. mood .. ": Gewicht ≥ 0 erwartet")
				else
					total += weight
				end
			end
			if total <= 0 then
				table.insert(errors, path .. ".Moods: Summe der Gewichte muss > 0 sein")
			end
		end
	end
	checkNumber(errors, path .. ".PartBudget", map.PartBudget, 50, 1100)
end

function Maps.Validate(Config: any): { string }
	local errors: { string } = {}
	local knownModes: { [string]: any }? = nil
	local modes = if type(Config) == "table" and type(Config.Modes) == "table" then Config.Modes.Modes else nil
	if type(modes) == "table" and next(modes) ~= nil then
		knownModes = modes
	end
	for key, map in pairs(MAPS) do
		validateMap(errors, key, map, knownModes)
	end
	for key, mood in pairs(MOODS) do
		validateMood(errors, key, mood)
	end
	if MOODS[Maps.LobbyMood] == nil then
		table.insert(errors, "Config.Maps.LobbyMood: unbekannte Stimmung " .. tostring(Maps.LobbyMood))
	end
	local nav = Maps.Nav
	checkNumber(errors, "Config.Maps.Nav.Grid", nav.Grid, 2, 20)
	checkNumber(errors, "Config.Maps.Nav.Headroom", nav.Headroom, 3, 20)
	checkNumber(errors, "Config.Maps.Nav.StepMax", nav.StepMax, 0.5, 10)
	checkNumber(errors, "Config.Maps.Nav.MaxNodes", nav.MaxNodes, 20, 2000)
	checkNumber(errors, "Config.Maps.DefaultKillY", Maps.DefaultKillY, -200, -5)
	checkNumber(errors, "Config.Maps.BarrierCeiling", Maps.BarrierCeiling, 10, 200)
	checkNumber(errors, "Config.Maps.NeonShare", Maps.NeonShare, 0, 1)
	-- Vault (Ursprung − VaultDepth) und KillY müssen über FallenPartsDestroyHeight (−500) liegen
	local server = if type(Config) == "table" and type(Config.Server) == "table" then Config.Server else nil
	if server and isFinite(server.VaultDepth) and server.VaultDepth + 10 >= 500 then
		table.insert(errors, "Config.Server.VaultDepth: Vault muss über −500 liegen (FallenPartsDestroyHeight)")
	end
	return errors
end

return Maps
