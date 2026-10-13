--!strict
-- =====================================================================
--  AKYTEX TYCOON – CLIENT-EINSTELLUNGEN (Shared/Config/Client)
--  Besitzer: WP2 (Client-Plattform & UI-Kit). Vertrag: DESIGN.md §C14.2 (Config.Client), §C7.5 (Controls), §A4 (Sound).
--  Erreichbar als Config.Client (wird von Config/init automatisch geladen).
--
--  Inhalt:
--    1) Keys / Gamepad          Tastenbelegung – Namen von Enum.KeyCode bzw. Enum.UserInputType (Listen erlaubt)
--    2) DefaultSettings         Standardwerte von Data.Settings
--    3) SettingsSchema          [Key] = { Type, Min?, Max?, Step?, Integer?, Options?, Fields? } für JEDEN Standardwert
--                               (Server klemmt SaveSettings damit, Client baut das Einstellungen-Fenster damit)
--    4) Sounds                  0 = eingebautes Rezept (Sfx, nur docs/ASSETS.md §2), sonst eigene Audio-ID (Hybrid, Wunsch 17)
--    5) HUD / Touch / Bewegung  Grenzen, Größen, Takt-Werte
--    6) Ladebildschirm          Splash-Zeiten (§A4)
--  ACHTUNG: Config wird an alle Clients repliziert -> KEINE Geheimnisse hier!
-- =====================================================================

export type SchemaEntry = {
	Type: "number" | "boolean" | "enum" | "table",
	Min: number?,
	Max: number?,
	Step: number?, -- Schrittweite des Reglers im Einstellungen-Fenster
	Integer: boolean?, -- nur ganze Zahlen
	Options: { string }?, -- nur Type = "enum"
	Fields: { [string]: SchemaEntry }?, -- nur Type = "table" (fehlende Felder = Standard des Feldes)
}

local Client = {}

-- ---------------------------------------------------------------------
-- 1) TASTEN – alles läuft über ContextActionService (Modul Controls). Aktionen (§C7.5):
--    Interact, Terminal, Tower, Shop, Quests, Menu, Sprint, Boost, Handbrake, ChartTf, ChartType, React,
--    AdminPanel, Fly, Spectate, Debug, PhotoMode. Kontexte World | Vehicle | Terminal | Menu | Spectate.
--    ChartTf: die Ziffern 1–7 wählen den Zeitrahmen (1s · 5s · 1m · 5m · 15m · 1T · 1W), Taste über input.KeyCode.
-- ---------------------------------------------------------------------
Client.Keys = {
	Interact = { "E" },
	Terminal = { "T" },
	Tower = { "B" },
	Shop = { "N" },
	Quests = { "J" },
	Menu = { "M" },
	Sprint = { "LeftShift" },
	Boost = { "LeftShift" },
	Handbrake = { "Space" },
	React = { "R" },
	ChartTf = { "One", "Two", "Three", "Four", "Five", "Six", "Seven" },
	ChartType = { "C" },
	AdminPanel = { "P" },
	Fly = { "G" },
	Spectate = { "X" },
	Debug = { "F8" },
	PhotoMode = { "F7" },
}

-- Gamepad: ein Knopf oder eine Liste je Aktion. ProximityPrompts (ButtonX) bleiben frei (Interact wird durchgereicht).
-- Terminal = Y (halten/tippen), LB/RB = Zeitrahmen im Terminal, R1 = Boost im Auto, B = Handbremse im Auto.
Client.Gamepad = {
	Interact = "ButtonX",
	Terminal = "ButtonY",
	Menu = "ButtonStart",
	Tower = "DPadUp",
	Quests = "DPadRight",
	Shop = "DPadLeft",
	React = "DPadDown",
	Sprint = "ButtonL3",
	Boost = "ButtonR1",
	Handbrake = "ButtonB",
	ChartTf = { "ButtonL1", "ButtonR1" },
	ChartType = "ButtonSelect",
}

-- ---------------------------------------------------------------------
-- 2) STANDARD-EINSTELLUNGEN (§C14.2) – landen per Reconcile in Data.Settings
-- ---------------------------------------------------------------------
Client.DefaultSettings = {
	Lang = "auto", -- "auto" (LocaleId) | "de" | "en"
	Sfx = 1,
	Music = 0.5,
	Ui = 0.8,
	Quality = "auto", -- "auto" (FPS-gesteuert) | "Low" | "Medium" | "High" | "Ultra"
	ReducedFx = false, -- = Website prefers-reduced-motion
	ChartType = "Candles",
	ChartTf = "1m",
	Indicators = {}, -- [Name] = true (Terminal, WP5); fehlende Felder = aus
	NumberStyle = "short", -- "short" (1,25 Mio.) | "long" (1.250.000)
	Colorblind = false, -- Up/Down -> Accent/Orange, ▲/▼ immer sichtbar
	Shake = 1,
	ShowNet = false,
	TickerBar = true,
	NewsCards = "Normal", -- "Normal" | "Quiet" (nur Crash/Rally/Glocke) | "Off"
	AutoTransfer = true, -- Gewinn-Transfer an der Glocke (Server: Request TradeAuto)
	LeftHanded = false,
	ButtonScale = 1,
}

-- ---------------------------------------------------------------------
-- 3) SCHEMA – für jeden Standardwert genau ein Eintrag (Validate prüft das)
-- ---------------------------------------------------------------------
local INDICATOR_NAMES = {
	"SMA20",
	"SMA50",
	"SMA200",
	"EMA9",
	"EMA21",
	"BB",
	"VWAP",
	"RSI",
	"MACD",
	"Stoch",
	"ATR",
}
local indicatorFields: { [string]: SchemaEntry } = {}
for _, name in ipairs(INDICATOR_NAMES) do
	indicatorFields[name] = { Type = "boolean" }
end
Client.IndicatorNames = INDICATOR_NAMES

local schema: { [string]: SchemaEntry } = {
	Lang = { Type = "enum", Options = { "auto", "de", "en" } },
	Sfx = { Type = "number", Min = 0, Max = 1, Step = 0.05 },
	Music = { Type = "number", Min = 0, Max = 1, Step = 0.05 },
	Ui = { Type = "number", Min = 0, Max = 1, Step = 0.05 },
	Quality = { Type = "enum", Options = { "auto", "Low", "Medium", "High", "Ultra" } },
	ReducedFx = { Type = "boolean" },
	ChartType = { Type = "enum", Options = { "Candles", "Hollow", "Line", "Area", "HeikinAshi" } },
	ChartTf = { Type = "enum", Options = { "1s", "5s", "1m", "5m", "15m", "1T", "1W" } },
	Indicators = { Type = "table", Fields = indicatorFields },
	NumberStyle = { Type = "enum", Options = { "short", "long" } },
	Colorblind = { Type = "boolean" },
	Shake = { Type = "number", Min = 0, Max = 1, Step = 0.05 },
	ShowNet = { Type = "boolean" },
	TickerBar = { Type = "boolean" },
	NewsCards = { Type = "enum", Options = { "Normal", "Quiet", "Off" } },
	AutoTransfer = { Type = "boolean" },
	LeftHanded = { Type = "boolean" },
	ButtonScale = { Type = "number", Min = 0.9, Max = 1.3, Step = 0.05 },
}
Client.SettingsSchema = schema

-- ---------------------------------------------------------------------
-- 4) SOUNDS (§A4) – 0 = eingebautes Rezept aus den 9 nutzbaren Dateien (docs/ASSETS.md §2), sonst eigene Audio-ID.
--    Engine = Loop (action_falling.ogg, Tonhöhe nach Tempo), Music = ohne ID keine Musik.
-- ---------------------------------------------------------------------
Client.Sounds = {
	UIClick = 0,
	UIHover = 0,
	UIError = 0,
	Buy = 0,
	Sell = 0,
	Profit = 0,
	Loss = 0,
	CashRegister = 0,
	TickerTick = 0,
	MarketBell = 0,
	CrashAlarm = 0,
	RallyFanfare = 0,
	ElevatorDing = 0,
	Construct = 0,
	MoneyRain = 0,
	Engine = 0,
	LevelUp = 0,
	Achievement = 0,
	Pickup = 0,
	Whoosh = 0,
	Countdown = 0,
	Notify = 0,
	Music = 0,
}

-- ---------------------------------------------------------------------
-- 5) HUD, TOUCH, BEWEGUNG, EFFEKTE (Budgets §C16)
-- ---------------------------------------------------------------------
Client.TouchButtonMin = 64 -- kein Touch-Knopf kleiner als 64 px (auch bei Knopfgröße 90 %)
Client.AutoReducedFx = { Fps = 35, Seconds = 5 } -- auf "Low" noch < 35 FPS für 5 s -> Reduzierte Effekte (einmal)
Client.HighlightCap = 31 -- Roblox zeigt höchstens 31 Highlights gleichzeitig
Client.Pools = {
	Sounds = 24, -- je Hälfte 2D (Oberfläche) und 3D (Welt)
	CoinFly = 16, -- fliegende CR-Chips beim Einsammeln
	Confetti = 140, -- gleichzeitig fliegende Konfetti-Stücke
}

-- Touch-Knöpfe (unskalierte TouchGui). Größen in Pixel bei Knopfgröße 100 %.
Client.Touch = {
	ButtonSize = 76, -- SPRINT (Welt), HANDBREMSE (Auto)
	BigSize = 96, -- BOOST (Auto)
	SmallSize = 64, -- REAKTION
	Margin = 16,
	AutoSprint = 0.9, -- Stick-Auslenkung, ab der automatisch gesprintet wird
}

-- Bewegung: Sprinten setzt die Lauf-Geschwindigkeit (AntiCheat erlaubt 32 × 1,15 – Config.Security)
Client.Movement = {
	WalkSpeed = 16,
	SprintSpeed = 24,
}

-- HUD (§D WP2): Takt-Werte und Größen
Client.Hud = {
	TickerHeight = 28, -- Ticker-Leiste oben
	PillHeight = 30,
	MaxPills = 4, -- so viele Pillen gleichzeitig oben in der Mitte
	VaultRingTicks = 32, -- Segmente des Tresor-Rings
	VaultWarn = 0.85, -- ab hier Ring in Warn-Farbe
	MultPopGap = 0.6, -- Multiplikator-Chip ploppt höchstens so oft
	TickerRefresh = 1, -- Sekunden zwischen zwei Ticker-Aktualisierungen
}

-- ---------------------------------------------------------------------
-- 6) LADEBILDSCHIRM (§A4: max. 4 s, endet früher wenn geladen, tippen überspringt; harte Grenze 12 s)
-- ---------------------------------------------------------------------
Client.Splash = {
	MinSeconds = 2.4, -- Logo-Animation darf so lange laufen (Taglines bei 1,25 / 1,45 s)
	LoadedMaxSeconds = 4, -- ist das Spiel geladen, endet die Splash spätestens hier
	HardCapSeconds = 12, -- harte Obergrenze, auch wenn noch nicht alles da ist
	SkipAfter = 0.3, -- tippen/klicken überspringt erst nach so vielen Sekunden
	OutSeconds = 0.7, -- Ausblenden (Skalierung 1,12 + Fade)
}

-- ---------------------------------------------------------------------
-- 7) PRÜFEN (Config.Validate sammelt das) – leere Liste = alles ok
-- ---------------------------------------------------------------------
local function isFinite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function checkValue(errors: { string }, path: string, entry: SchemaEntry, value: any, optional: boolean)
	if value == nil and optional then
		return
	end
	if entry.Type == "number" then
		if not isFinite(value) then
			table.insert(errors, path .. ": Zahl erwartet")
			return
		end
		local lo, hi = entry.Min, entry.Max
		if lo == nil or hi == nil or lo > hi then
			table.insert(errors, path .. ": Schema braucht Min ≤ Max")
		elseif value < lo or value > hi then
			table.insert(
				errors,
				("%s: Standard %s außerhalb %s..%s"):format(path, tostring(value), tostring(lo), tostring(hi))
			)
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
		-- Felder einer Tabellen-Einstellung sind optional (fehlend = aus/Standard)
		for key, sub in pairs(fields) do
			checkValue(errors, path .. "." .. key, sub, value[key], true)
		end
		for key in pairs(value) do
			if type(key) ~= "string" or fields[key] == nil then
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

local REQUIRED_ACTIONS = {
	"Interact",
	"Terminal",
	"Tower",
	"Shop",
	"Quests",
	"Menu",
	"Sprint",
	"Boost",
	"Handbrake",
	"ChartTf",
	"ChartType",
	"React",
	"AdminPanel",
	"Fly",
	"Spectate",
	"Debug",
	"PhotoMode",
}

function Client.Validate(_config: any): { string }
	local errors: { string } = {}
	local defaults: { [string]: any } = Client.DefaultSettings
	for key, value in pairs(defaults) do
		local entry = schema[key]
		if not entry then
			table.insert(errors, "Config.Client.SettingsSchema." .. key .. ": Eintrag fehlt")
		else
			checkValue(errors, "Config.Client.DefaultSettings." .. key, entry, value, false)
		end
	end
	for key in pairs(schema) do
		if defaults[key] == nil then
			table.insert(errors, "Config.Client.SettingsSchema." .. key .. ": kein Standardwert")
		end
	end
	local keys: { [string]: { string } } = Client.Keys
	for _, action in ipairs(REQUIRED_ACTIONS) do
		if keys[action] == nil then
			table.insert(errors, "Config.Client.Keys." .. action .. ": Aktion fehlt (§C7.5)")
		end
	end
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
	for action, value in pairs(pad) do
		local list: { any } = if type(value) == "table" then value else { value }
		for _, name in ipairs(list) do
			if type(name) ~= "string" or Enum.KeyCode:FromName(name) == nil then
				table.insert(errors, "Config.Client.Gamepad." .. action .. ": unbekannter Knopf " .. tostring(name))
			end
		end
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
	local auto = Client.AutoReducedFx
	if not isFinite(auto.Fps) or not isFinite(auto.Seconds) or auto.Fps <= 0 or auto.Seconds <= 0 then
		table.insert(errors, "Config.Client.AutoReducedFx: Fps und Seconds > 0 erwartet")
	end
	local move = Client.Movement
	if not isFinite(move.WalkSpeed) or not isFinite(move.SprintSpeed) or move.SprintSpeed < move.WalkSpeed then
		table.insert(errors, "Config.Client.Movement: WalkSpeed ≤ SprintSpeed (Zahlen) erwartet")
	elseif move.SprintSpeed > 32 then
		table.insert(errors, "Config.Client.Movement.SprintSpeed: über Config.Security.BaseAllowedSpeed (32)")
	end
	local hud: { [string]: any } = Client.Hud
	for name, value in pairs(hud) do
		if not isFinite(value) or value <= 0 then
			table.insert(errors, "Config.Client.Hud." .. name .. ": positive Zahl erwartet")
		end
	end
	local splash = Client.Splash
	if
		not isFinite(splash.MinSeconds)
		or not isFinite(splash.LoadedMaxSeconds)
		or not isFinite(splash.HardCapSeconds)
		or splash.MinSeconds > splash.LoadedMaxSeconds
		or splash.LoadedMaxSeconds > 4
		or splash.HardCapSeconds > 12
	then
		table.insert(
			errors,
			"Config.Client.Splash: MinSeconds ≤ LoadedMaxSeconds ≤ 4, HardCapSeconds ≤ 12 erwartet"
		)
	end
	return errors
end

return Client
