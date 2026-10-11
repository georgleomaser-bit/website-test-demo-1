--!strict
-- =====================================================================
--  CLUTCH CLASH – CLIENT-EINSTELLUNGEN (Shared/Config/Client)
--  Besitzer: WP10 (Client-Hülle). Vertrag: DESIGN.md C15 (Config.Client), B15.1, B15.3.
--  Erreichbar als Config.Client (wird von Config/init automatisch geladen).
--
--  Inhalt:
--    1) Keys / Gamepad          Tastenbelegung (B15.1) – Namen von Enum.KeyCode bzw. Enum.UserInputType
--    2) AimAssist               Zielhilfe (nur Touch & Gamepad, nie Maus – B15.2)
--    3) DefaultSettings         Standardwerte von Data.Settings (B15.3)
--    4) SettingsSchema          [Key] = { Type, Min?, Max?, Step?, Integer?, Options?, Fields? } für JEDEN Standardwert
--                               (Server klemmt SaveSettings damit, Client baut das Einstellungen-Fenster damit)
--    5) Sounds                  0 = eingebautes Rezept aus docs/ASSETS.md §2.2, sonst eigene Audio-ID
--    6) HUD / Touch / Effekte   Grenzen, Pools (Budgets C17), Farben
--  ACHTUNG: Config wird an alle Clients repliziert -> KEINE Geheimnisse hier!
-- =====================================================================

export type SchemaEntry = {
	Type: "number" | "boolean" | "enum" | "table",
	Min: number?,
	Max: number?,
	Step: number?, -- Schrittweite des Reglers im Einstellungen-Fenster
	Integer: boolean?, -- nur ganze Zahlen
	Options: { string }?, -- nur Type = "enum"
	Fields: { [string]: SchemaEntry }?, -- nur Type = "table" (z. B. Crosshair)
}

local Client = {}

-- ---------------------------------------------------------------------
-- 1) TASTEN (B15.1) – alles läuft über ContextActionService (Modul Controls)
--    Werte: Liste von Enum.KeyCode-Namen ("R", "LeftShift", "One" …) oder
--    Enum.UserInputType-Namen ("MouseButton1", "MouseButton2").
--    Mausrad = Waffe weiter/zurück (siehe WheelSwitch).
-- ---------------------------------------------------------------------
Client.Keys = {
	Fire = { "MouseButton1" },
	Ads = { "MouseButton2" },
	Reload = { "R" },
	Slot1 = { "One" },
	Slot2 = { "Two" },
	Slot3 = { "Three" },
	Slot4 = { "Four" },
	LastWeapon = { "Q" },
	Utility = { "E" },
	Melee = { "F" },
	Sprint = { "LeftShift" },
	Slide = { "C", "LeftControl" },
	Inspect = { "V" },
	Scoreboard = { "Tab" },
	Loadout = { "L" },
	Menu = { "M" },
	Ready = { "Return" },
	AdminPanel = { "P" },
	Fly = { "G" },
	Spectate = { "X" },
	Debug = { "F8" },
	-- Zuschauen: wechseln mit Klick / Pfeiltasten (nur im Zuschau-Modus aktiv)
	SpecNext = { "Right", "MouseButton1" },
	SpecPrev = { "Left" },
}
Client.WheelSwitch = true -- Mausrad: runter = NextWeapon, hoch = PrevWeapon

-- Gamepad (B15.1). Y = Primär/Sekundär wechseln, Y doppelt = letzte Waffe.
-- ButtonStart ist im Match "Bereit", sonst "Menü" (Priorität entscheidet).
Client.Gamepad = {
	Fire = "ButtonR2",
	Ads = "ButtonL2",
	Reload = "ButtonX",
	Cycle = "ButtonY",
	Melee = "ButtonL1",
	Utility = "ButtonR1",
	Sprint = "ButtonL3",
	Slide = "ButtonB",
	Scoreboard = "ButtonSelect",
	Ready = "ButtonStart",
	TriggerThreshold = 0.4, -- RT/LT gelten ab Position.Z ≥ 0.4 als gedrückt
	-- Ergänzungen aus der Tabelle B15.1 (D-Pad, Menü, Zuschauen)
	Loadout = "DPadDown",
	Inspect = "DPadUp",
	Menu = "ButtonStart",
	SpecNext = "ButtonR1",
	SpecPrev = "ButtonL1",
	DoubleTap = 0.28, -- Sekunden: zweimal Y in dieser Zeit = letzte Waffe
}

-- ---------------------------------------------------------------------
-- 2) ZIELHILFE (B15.2) – nur Touch & Gamepad, NIE Maus
-- ---------------------------------------------------------------------
Client.AimAssist = {
	Gamepad = { Cone = 3.5, Friction = 0.55, Magnet = 4 },
	Touch = { Cone = 4.5, Friction = 0.55, Magnet = 5 },
	Range = 70,
	RankedMult = 0.5,
	AutoFireRate = 0.85, -- Auto-Feuer feuert mit 85 % der Feuerrate
	AutoFireDwell = 0.15, -- so lange muss das Fadenkreuz auf einem sichtbaren Gegner liegen
}

-- ---------------------------------------------------------------------
-- 3) STANDARD-EINSTELLUNGEN (B15.3) – landen per Reconcile in Data.Settings
-- ---------------------------------------------------------------------
Client.DefaultSettings = {
	Fov = 80,
	SensMouse = 0.5,
	SensPad = 0.5,
	SensTouch = 0.6,
	AdsMult = 0.8,
	ScopeMult = 0.6,
	InvertY = false,
	AdsToggle = false,
	SprintToggle = false,
	AutoReload = true,
	AutoFire = "auto", -- "auto" = an bei Touch in Casual, "on", "off"
	AimAssist = 1,
	Crosshair = { Style = 1, Color = "White", Size = 8, Gap = 4, Dot = true },
	EnemyColor = "Red",
	DamageNumbers = true,
	HitSound = true,
	ReducedFx = false,
	Shake = 1,
	LeftHanded = false,
	ButtonScale = 1,
	Lang = "auto",
	Sfx = 1,
	Music = 0.5,
	Ui = 0.8,
	ShowNet = false,
	AutoRequeue = false,
	PublicDrops = true,
}

-- ---------------------------------------------------------------------
-- 4) SCHEMA – für jeden Standardwert genau ein Eintrag (Config.Validate prüft das)
-- ---------------------------------------------------------------------
local schema: { [string]: SchemaEntry } = {
	Fov = { Type = "number", Min = 70, Max = 100, Step = 1, Integer = true },
	SensMouse = { Type = "number", Min = 0.05, Max = 2, Step = 0.05 },
	SensPad = { Type = "number", Min = 0.05, Max = 2, Step = 0.05 },
	SensTouch = { Type = "number", Min = 0.05, Max = 2, Step = 0.05 },
	AdsMult = { Type = "number", Min = 0.2, Max = 1.5, Step = 0.05 },
	ScopeMult = { Type = "number", Min = 0.2, Max = 1.5, Step = 0.05 },
	InvertY = { Type = "boolean" },
	AdsToggle = { Type = "boolean" },
	SprintToggle = { Type = "boolean" },
	AutoReload = { Type = "boolean" },
	AutoFire = { Type = "enum", Options = { "auto", "on", "off" } },
	AimAssist = { Type = "number", Min = 0, Max = 1, Step = 0.05 },
	Crosshair = {
		Type = "table",
		Fields = {
			Style = { Type = "number", Min = 1, Max = 4, Step = 1, Integer = true }, -- 1 Kreuz, 2 Punkt, 3 Kreis, 4 T
			Color = { Type = "enum", Options = { "White", "Green", "Yellow", "Cyan", "Pink" } },
			Size = { Type = "number", Min = 4, Max = 16, Step = 1, Integer = true },
			Gap = { Type = "number", Min = 0, Max = 10, Step = 1, Integer = true },
			Dot = { Type = "boolean" },
		},
	},
	EnemyColor = { Type = "enum", Options = { "Red", "Magenta", "Yellow", "White" } },
	DamageNumbers = { Type = "boolean" },
	HitSound = { Type = "boolean" },
	ReducedFx = { Type = "boolean" },
	Shake = { Type = "number", Min = 0, Max = 1, Step = 0.05 },
	LeftHanded = { Type = "boolean" },
	ButtonScale = { Type = "number", Min = 0.9, Max = 1.3, Step = 0.05 },
	Lang = { Type = "enum", Options = { "auto", "de", "en" } },
	Sfx = { Type = "number", Min = 0, Max = 1, Step = 0.05 },
	Music = { Type = "number", Min = 0, Max = 1, Step = 0.05 },
	Ui = { Type = "number", Min = 0, Max = 1, Step = 0.05 },
	ShowNet = { Type = "boolean" },
	AutoRequeue = { Type = "boolean" },
	PublicDrops = { Type = "boolean" },
}
Client.SettingsSchema = schema

-- ---------------------------------------------------------------------
-- 5) SOUNDS – 0 = eingebautes Rezept (docs/ASSETS.md §2.2, nur die 11 eingebauten Dateien).
--    Eigene Audio-ID eintragen (z. B. Roblox-Audio aus dem Creator Store) = diese wird benutzt.
-- ---------------------------------------------------------------------
Client.Sounds = {
	RifleShot = 0,
	PistolShot = 0,
	SmgShot = 0,
	ShotgunShot = 0,
	SniperShot = 0,
	CannonShot = 0,
	RocketLaunch = 0,
	Explosion = 0,
	MagOut = 0,
	MagIn = 0,
	Equip = 0,
	MeleeSwing = 0,
	MeleeHit = 0,
	Hitmarker = 0,
	Headshot = 0,
	Kill = 0,
	Eliminated = 0,
	UIClick = 0,
	UIHover = 0,
	UIError = 0,
	Countdown = 0,
	Go = 0,
	Win = 0,
	Lose = 0,
	LevelUp = 0,
	Heal = 0,
	LobbyMusic = 0, -- ohne ID keine Musik (es gibt keine eingebaute Musik)
	MatchMusic = 0,
}

-- ---------------------------------------------------------------------
-- 6) HUD, TOUCH, EFFEKTE (Budgets C17)
-- ---------------------------------------------------------------------
Client.TouchButtonMin = 64 -- kein Touch-Knopf kleiner als 64 px (auch bei Knopfgröße 90 %)
Client.AutoReducedFx = { Fps = 35, Seconds = 5, StartDelay = 15 } -- < 35 FPS für 5 s -> Reduzierte Effekte (erst 15 s nach dem Start)
Client.HighlightCap = 31 -- Roblox zeigt höchstens 31 Highlights gleichzeitig
Client.Pools = {
	Tracers = 48,
	Impacts = 32, -- höchstens so viele Treffer-Effekte pro Sekunde
	DamageNumbers = 24,
	Sounds = 24, -- je Hälfte 2D (Oberfläche) und 3D (Welt)
	Lights = 4,
	Projectiles = 40,
	Finishers = 4,
}

-- Touch-Knöpfe (unskalierte TouchGui). Größen in Pixel bei Knopfgröße 100 %.
Client.Touch = {
	FireSize = 116, -- großer FEUER-Knopf rechts (ziehen = zielen)
	SmallFireSize = 76, -- kleiner FEUER-Knopf links
	ButtonSize = 72, -- ADS, NACHLADEN, RUTSCHEN, UTILITY
	SlotSize = 66, -- Slot-Leiste unten Mitte
	SmallSize = 64, -- Scoreboard/Loadout/Inspizieren/Menü oben rechts
	Margin = 16,
	LookPerPixel = 0.0065, -- Bogenmaß pro Pixel beim Ziehen des Feuerknopfs (× SensTouch)
}

-- Fadenkreuz (4 Stile) und Treffer-Anzeigen (B14.1)
Client.CrosshairColors = {
	White = Color3.fromRGB(255, 255, 255),
	Green = Color3.fromRGB(90, 255, 120),
	Yellow = Color3.fromRGB(255, 230, 60),
	Cyan = Color3.fromRGB(60, 230, 255),
	Pink = Color3.fromRGB(255, 105, 200),
}
Client.Hud = {
	HitmarkerBody = 0.12, -- weißes X
	HitmarkerHead = 0.22, -- gelbes großes X
	HitmarkerKill = 0.4, -- rotes X
	DamageStack = 0.6, -- Schadenszahlen am selben Ziel stapeln sich so lange
	DamageLife = 0.85,
	HurtArrow = 1.2, -- Richtungs-Pfeil nach erhaltenem Schaden
	LowHp = 30, -- ab hier Herzschlag-Vignette + leises "Autsch"
	LowAmmo = 0.25, -- Anteil des Magazins: doppelter Tick
	MultiKillWindow = 4, -- DOUBLE!/TRIPLE!/QUAD! (Team/FFA)
	KillBanner = 1.6,
}

-- Tracer (Beam zwischen zwei Attachments, ASSETS §5)
Client.Tracer = {
	Texture = "rbxasset://textures/gradient.png",
	Width0 = 0.12,
	Width1 = 0.05,
	Life = 0.07, -- ausblenden in 0.05–0.08 s
}
Client.FxRange = 450 -- weiter weg: keine Partikel
Client.FinisherRange = 300 -- weiter weg: Finisher ausgeblendet (B19)

-- ---------------------------------------------------------------------
-- 7) PRÜFEN (Config.Validate sammelt das) – leere Liste = alles ok
-- ---------------------------------------------------------------------
local function isFinite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function checkValue(errors: { string }, path: string, entry: SchemaEntry, value: any)
	if entry.Type == "number" then
		if not isFinite(value) then
			table.insert(errors, path .. ": Zahl erwartet")
			return
		end
		local lo, hi = entry.Min, entry.Max
		if lo == nil or hi == nil or lo > hi then
			table.insert(errors, path .. ": Schema braucht Min ≤ Max")
		elseif value < lo or value > hi then
			table.insert(errors, ("%s: Standard %s außerhalb %s..%s"):format(path, tostring(value), tostring(lo), tostring(hi)))
		end
		if entry.Integer and value % 1 ~= 0 then
			table.insert(errors, path .. ": ganze Zahl erwartet")
		end
	elseif entry.Type == "boolean" then
		if type(value) ~= "boolean" then
			table.insert(errors, path .. ": true/false erwartet")
		end
	elseif entry.Type == "enum" then
		local options = entry.Options
		if type(options) ~= "table" or #options == 0 then
			table.insert(errors, path .. ": Schema braucht Options")
		elseif not table.find(options, value) then
			table.insert(errors, path .. ": Standard " .. tostring(value) .. " ist keine Option")
		end
	elseif entry.Type == "table" then
		local fields = entry.Fields
		if type(fields) ~= "table" or type(value) ~= "table" then
			table.insert(errors, path .. ": Tabelle + Fields erwartet")
			return
		end
		for key, sub in pairs(fields) do
			checkValue(errors, path .. "." .. key, sub, value[key])
		end
		for key in pairs(value) do
			if fields[key] == nil then
				table.insert(errors, path .. "." .. tostring(key) .. ": fehlt im Schema")
			end
		end
	else
		table.insert(errors, path .. ": unbekannter Schema-Typ " .. tostring(entry.Type))
	end
end

local function keyExists(name: string): boolean
	return Enum.KeyCode:FromName(name) ~= nil or Enum.UserInputType:FromName(name) ~= nil
end

function Client.Validate(_config: any): { string }
	local errors: { string } = {}
	local defaults: { [string]: any } = Client.DefaultSettings
	for key, value in pairs(defaults) do
		local entry = schema[key]
		if not entry then
			table.insert(errors, "Config.Client.SettingsSchema." .. key .. ": Eintrag fehlt")
		else
			checkValue(errors, "Config.Client.DefaultSettings." .. key, entry, value)
		end
	end
	for key in pairs(schema) do
		if defaults[key] == nil then
			table.insert(errors, "Config.Client.SettingsSchema." .. key .. ": kein Standardwert")
		end
	end
	local keys: { [string]: { string } } = Client.Keys
	for action, list in pairs(keys) do
		if type(list) ~= "table" or #list == 0 then
			table.insert(errors, "Config.Client.Keys." .. action .. ": Liste erwartet")
		else
			for _, name in ipairs(list) do
				if type(name) ~= "string" or not keyExists(name) then
					table.insert(errors, "Config.Client.Keys." .. action .. ": unbekannte Taste " .. tostring(name))
				end
			end
		end
	end
	local pad: { [string]: any } = Client.Gamepad
	for action, name in pairs(pad) do
		if type(name) == "string" and Enum.KeyCode:FromName(name) == nil then
			table.insert(errors, "Config.Client.Gamepad." .. action .. ": unbekannter Knopf " .. name)
		end
	end
	if not isFinite(pad.TriggerThreshold) or pad.TriggerThreshold <= 0 or pad.TriggerThreshold > 1 then
		table.insert(errors, "Config.Client.Gamepad.TriggerThreshold: Zahl 0..1 erwartet")
	end
	local sounds: { [string]: any } = Client.Sounds
	for role, id in pairs(sounds) do
		if not isFinite(id) or id < 0 or id % 1 ~= 0 then
			table.insert(errors, "Config.Client.Sounds." .. role .. ": 0 oder Audio-ID (ganze Zahl) erwartet")
		end
	end
	local pools: { [string]: any } = Client.Pools
	for name, size in pairs(pools) do
		if not isFinite(size) or size < 1 or size % 1 ~= 0 then
			table.insert(errors, "Config.Client.Pools." .. name .. ": ganze Zahl ≥ 1 erwartet")
		end
	end
	if not isFinite(Client.HighlightCap) or Client.HighlightCap < 1 or Client.HighlightCap > 31 then
		table.insert(errors, "Config.Client.HighlightCap: 1..31 erwartet (Roblox-Grenze)")
	end
	if not isFinite(Client.TouchButtonMin) or Client.TouchButtonMin < 44 then
		table.insert(errors, "Config.Client.TouchButtonMin: mindestens 44 px erwartet")
	end
	local touch: { [string]: any } = Client.Touch
	for name, value in pairs(touch) do
		if not isFinite(value) or value <= 0 then
			table.insert(errors, "Config.Client.Touch." .. name .. ": positive Zahl erwartet")
		end
	end
	local crosshair = schema.Crosshair.Fields
	local colorOptions = crosshair and crosshair.Color.Options or {}
	for _, name in ipairs(colorOptions :: { string }) do
		if typeof((Client.CrosshairColors :: any)[name]) ~= "Color3" then
			table.insert(errors, "Config.Client.CrosshairColors." .. name .. ": Color3 fehlt")
		end
	end
	local auto = Client.AutoReducedFx
	if not isFinite(auto.Fps) or not isFinite(auto.Seconds) or auto.Fps <= 0 or auto.Seconds <= 0 then
		table.insert(errors, "Config.Client.AutoReducedFx: Fps und Seconds > 0 erwartet")
	end
	return errors
end

return Client
