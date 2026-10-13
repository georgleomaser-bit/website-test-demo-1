-- =====================================================================
--  AKYTEX TYCOON – ZENTRALE EINSTELLUNGEN (Shared/Config)
--  Besitzer: WP1 (Kern & Plattform). Vertrag: DESIGN.md §C14.1 + §C6.1 (CC-Stil).
--  Hier stellst du (fast) alles ein, ohne anderen Code anzufassen. Alle Zahlen sind Startwerte aus DESIGN.md
--  und 1:1 änderbar. ACHTUNG: Config wird an alle Clients repliziert -> KEINE Geheimnisse hier!
--
--  Kindmodule (werden automatisch geladen, jedes Paket pflegt sein eigenes, jedes exportiert Validate(Config)):
--    Security (WP1) · Client, Quality (WP2) · Market, Companies, News (WP3) · Trading (WP4) · Tower (WP6) ·
--    City, Vehicles (WP7) · Decor, Lifestyle (WP8) · Progression, Season, Rewards (WP9) · Shop (WP10) · Events (WP11)
--    -> erreichbar als Config.Market, Config.Tower, … Fehlt ein Kind: leere Tabelle + Meldung in Validate().
--
--  Öffentliche Helfer:
--    Config.Validate(): { string }        Kinder-Validate + eigene Prüfungen (MaxMoney, Ganzzahligkeit, Preise < 1e14,
--                                         Asset-Plätze typ-korrekt, LiveFields wohlgeformt). Leer = alles ok (SelfTest).
--    Config.ApplyLive(data): (number, { string })   LiveConfig aus AT_Live_v1 übernehmen: NUR Pfade aus
--                                         Config.LiveFields, geklemmt/geprüft. Jeder Aufruf setzt zuerst alle früher
--                                         geänderten Pfade auf den Code-Stand zurück (Ergebnis = Code + data).
--                                         data = { ["Pfad"] = Wert } oder { Fields = { … } }. Rückgabe: übernommen, Probleme.
--    Config.CurrentLive(): { [string]: any }   Kopie der gerade aktiven Live-Werte (für Admin-Panel/Replikation)
-- =====================================================================

local RunService = game:GetService("RunService")

local Shared = script.Parent
local Util = require(Shared:WaitForChild("Util"))

local Config = {}

Config.GameName = "AKYTEX TYCOON"
Config.Version = "1.0.0"

-- ---------------------------------------------------------------------
-- 1) ADMINS – NUR DU: Wem das Spiel gehört (dein Account bzw. der Besitzer deiner Gruppe), ist Admin.
--    Du musst hier nichts eintragen! Admin kann man NICHT kaufen – der Server prüft es bei jeder Aktion.
--    Im Studio-Test bist du Admin (Player1 = -1), Player2 (-2) bewusst NIE (§B15.1).
-- ---------------------------------------------------------------------
Config.Admin = {
	OwnerIsAdmin = true,
	GroupOwnerIsAdmin = true, -- Spiel unter einer Gruppe veröffentlicht -> Gruppen-Besitzer ist Admin
	StudioIsAdmin = true,
	StudioAllPlayersAdmin = false, -- false lassen, sonst ist der "Abgelehnt"-Weg nicht testbar
}

-- ---------------------------------------------------------------------
-- 2) TECHNIK (nur ändern, wenn du weißt was du tust)
--    DataStoreName oder KeyPrefix ändern = alle Spielstände sind weg!
-- ---------------------------------------------------------------------
Config.Tech = {
	DataStoreName = "AT_Player_v1",
	DataVersion = 1,
	KeyPrefix = "P_", -- Schlüssel P_<UserId>
	MessagingTopic = "AT_Global", -- Ansagen, Admin-Abuse (Nicht-Markt)
	BusTopic = "AT_EV", -- Schnellweg für neue Markt-Bus-Events
	AutoSaveSeconds = 90, -- Auto-Save aller Spielstände
	AutoSaveStagger = 0.5, -- Abstand zwischen zwei Spielern beim Auto-Save
	LoadAttempts = 6,
	SaveAttempts = 4,
	LockStaleSeconds = 1800, -- Session-Lock älter als 30 Min gilt als verwaist
	BindToCloseSeconds = 25, -- Roblox gibt beim Herunterfahren max. 30 s
	ReceiptKeep = 60, -- so viele Kauf-Belege bleiben im Spielstand
	StateFlush = 0.2, -- State an den Client höchstens alle 0,2 s (≤ 5 Pakete/s)
	FullStateEvery = 20, -- voller State als Sicherheitsnetz
	LiveStore = "AT_Live_v1",
	StatsStore = "AT_Stats_v1",
	ModStore = "AT_Mod_v1",
	MarketStore = "AT_Market_v1", -- Seed_W<w>, Close_W<w>, Ipo_S<s> (WP3)
	GlobalStore = "AT_Global", -- DataStore: Admin-Log-Kopie je Woche, Live-Kalender-Overrides (WP11)
	GroupsStore = "AT_Groups_v1", -- v1.1 Hedgefonds-Gruppen
	BusMapPrefix = "AT_Bus_W", -- MemoryStore SortedMap AT_Bus_W<w>: Markt-Admin-Events (Wahrheit, WP3)
	HeartbeatMap = "AT_Heartbeat", -- MemoryStore HashMap: Server-Herzschlag (Admin-Dashboard)
	Shards = 8,
	BoardPrefix = "AT_LB_",
	BoardWriteSeconds = 300,
	StatsFlushSeconds = 600,
	PingAttrEvery = 2, -- Attribut "PingMs" am Player alle 2 s
}

-- ---------------------------------------------------------------------
-- 3) STUDIO – Testen ohne Speichern, lokaler Testmarkt, Selbsttest
-- ---------------------------------------------------------------------
Config.Studio = {
	NoSave = true, -- im Studio nie speichern (Toast "Studio: Fortschritt wird nicht gespeichert")
	SelfTest = true, -- "[SelfTest] n/n PASS" im Output beim Start
	LocalMarket = true, -- ohne API-Zugriff: Markt mit Fallback-Seed ("Lokaler Testmarkt")
	BellZoneMinPlayers = 1, -- Glocken-Moment schon ab 1 Spieler (live: Config.Events.BellMoment.MinPlayers)
	SkipAccountAge = true, -- Respekt/Bau-Hilfe: AccountAge-Prüfung im Studio überspringen (§C17)
}

-- ---------------------------------------------------------------------
-- 4) DEBUG – auch im Admin-Panel (Tab Debug) umschaltbar
-- ---------------------------------------------------------------------
Config.Debug = {
	LogRejects = false, -- abgelehnte Anfragen mit Grund im Output
	ForceRestricted = false, -- so tun, als wären bezahlte Zufallsitems verboten (Policy-Test)
	ShowTriggers = false, -- Auslöse-Zonen (Kassen-Tor, Glocken-Zone, Pickups) sichtbar machen
}

-- ---------------------------------------------------------------------
-- 5) SERVER – Spieler, Plots, Geld-Obergrenze (Muss-Regel 9)
-- ---------------------------------------------------------------------
Config.Server = {
	MaxPlayers = 10, -- = Plots (in Studio unter Game Settings → Places ebenfalls 10 einstellen)
	Plots = 10,
	MaxMoney = 9e15, -- kein Kontostand/Preis/Bestenlisten-Wert ≥ 9e15 (Anzeige "MAX"), < 2^53
}

-- ---------------------------------------------------------------------
-- 6) FARBEN – Spiegel von UI.Theme für Server-SurfaceGuis (Ticker-Wände, Schilder, Bestenlisten)
-- ---------------------------------------------------------------------
Config.Colors = {
	Bg = Color3.fromRGB(11, 15, 23), -- #0b0f17
	Bg2 = Color3.fromRGB(15, 20, 29), -- #0f141d
	Surface = Color3.fromRGB(18, 24, 36), -- #121824
	Surface2 = Color3.fromRGB(26, 33, 48), -- #1a2130
	Hover = Color3.fromRGB(31, 40, 56), -- #1f2838
	Border = Color3.fromRGB(31, 41, 55), -- #1f2937
	Text = Color3.fromRGB(230, 236, 245), -- #e6ecf5
	Text2 = Color3.fromRGB(170, 180, 195), -- #aab4c3
	Muted = Color3.fromRGB(125, 136, 154), -- #7d889a
	Accent = Color3.fromRGB(79, 140, 255), -- #4f8cff
	AccentDeep = Color3.fromRGB(41, 98, 255), -- #2962ff
	Up = Color3.fromRGB(34, 197, 94), -- #22c55e
	Down = Color3.fromRGB(239, 68, 68), -- #ef4444
	Warn = Color3.fromRGB(234, 179, 8), -- #eab308
	Gold = Color3.fromRGB(250, 204, 21), -- #facc15 (nur Kronen, Glocke, Hall of Fame)
	Orange = Color3.fromRGB(245, 158, 11), -- #f59e0b (Farbenblind-Modus statt Down)
	Cosmic1 = Color3.fromRGB(59, 91, 219), -- #3b5bdb (Verlauf Premium/Penthouse)
	Cosmic2 = Color3.fromRGB(124, 92, 255), -- #7c5cff
	Cosmic3 = Color3.fromRGB(179, 107, 255), -- #b36bff
	LogoRing = Color3.fromRGB(110, 162, 242), -- #6ea2f2
	LogoLetters = Color3.fromRGB(234, 241, 255), -- #eaf1ff
	Sectors = {
		T = Color3.fromRGB(79, 140, 255), -- Tech #4f8cff
		E = Color3.fromRGB(34, 211, 238), -- Energie #22d3ee
		M = Color3.fromRGB(139, 92, 246), -- Mobilität #8b5cf6
		K = Color3.fromRGB(245, 158, 11), -- Konsum #f59e0b
		G = Color3.fromRGB(236, 72, 153), -- Gaming #ec4899
		F = Color3.fromRGB(250, 204, 21), -- Finanzen #facc15
	},
}

-- ---------------------------------------------------------------------
-- 7) BENACHRICHTIGUNGEN (Experience Notifications; Senden erst v1.1, §B11.9)
-- ---------------------------------------------------------------------
Config.Notifications = {
	Enabled = false,
	MaxPerDay = 1,
	PromptAfterStep = 17, -- Opt-in-Abfrage frühestens nach Tutorial-Schritt 17 (§B2)
}

-- ---------------------------------------------------------------------
-- 8) LIVE-CONFIG (AT_Live_v1, Admin-Tab „Live-Ops“) – NUR diese Pfade dürfen live geändert werden.
--    Formen:  { min, max }  bzw. { Type = "number", Min, Max, Integer = true }   Zahl, geklemmt
--             { Type = "boolean" }                                  true/false
--             { Type = "list", Options = {…}, Min = n, Max = n }    Liste von Texten (aus Options, ohne Doppelte)
--             { Type = "code", MaxCredits = n }                     Code-Eintrag: Grant nur Credits/Cosmetics, Expires
--    Pfade mit ".*" am Ende erlauben beliebige Schlüssel (Buchstaben/Ziffern/_, ≤ 40 Zeichen) darunter.
-- ---------------------------------------------------------------------
Config.LiveFields = {
	["Market.NewsMeanGap"] = { 300, 6000 }, -- News-Takt (Ticks zwischen Schlagzeilen je Instrument)
	["Events.Rotation"] = { Type = "list", Options = { "Truck", "Drones", "BuildBoom", "Press" }, Min = 1, Max = 4 },
	["Events.BoostPause"] = { Type = "boolean" }, -- Notschalter: Boosts pausieren
	["Events.BellMoment.Mult"] = { 1, 1.5 },
	["Events.BuildBoom.Pct"] = { 0.05, 0.5 },
	["Events.Truck.Bundles"] = { Type = "number", Min = 5, Max = 60, Integer = true },
	["Events.RainCoinsMax"] = { Type = "number", Min = 5, Max = 30, Integer = true },
	["Tower.Mult.Bull"] = { 1, 2 }, -- Boost-Werte (Deckel ×10 gilt immer zusätzlich)
	["Tower.Mult.Parade"] = { 1, 2 },
	["Tower.Mult.BellMoment"] = { 1, 1.5 },
	["Tower.Mult.EventMax"] = { 1, 3 },
	["Shop.Disabled.*"] = { Type = "boolean" }, -- Notschalter: Produkt/Pass deaktivieren
	["Rewards.Codes.*"] = { Type = "code", MaxCredits = 1000000 }, -- Codes nur CR/Kosmetik (Firewall)
}

-- =====================================================================
-- 9) KINDMODULE – dynamisch geladen (fehlt eins, gibt es eine leere Tabelle
--    und Config.Validate() meldet es; der Rest läuft weiter)
-- =====================================================================
local CHILDREN = {
	"Security",
	"Client",
	"Quality",
	"Market",
	"Companies",
	"News",
	"Trading",
	"Tower",
	"City",
	"Vehicles",
	"Decor",
	"Lifestyle",
	"Progression",
	"Season",
	"Rewards",
	"Shop",
	"Events",
}

-- Client: erst warten, bis die erste Replikation fertig ist (sonst fehlen Kindmodule evtl. noch)
if RunService:IsClient() and not RunService:IsServer() and not game:IsLoaded() then
	game.Loaded:Wait()
end

local children: { [string]: { [string]: any } } = {}
local loadErrors: { [string]: string } = {}

local function loadChild(name: string): { [string]: any }
	local module = script:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		loadErrors[name] = "Modul fehlt"
		children[name] = {}
		return children[name]
	end
	local ok, result = pcall(require, module)
	if not ok then
		loadErrors[name] = "Fehler beim Laden: " .. tostring(result)
		warn("[Config] Config." .. name .. " konnte nicht geladen werden: " .. tostring(result))
		result = {}
	elseif type(result) ~= "table" then
		loadErrors[name] = "gibt keine Tabelle zurück"
		warn("[Config] Config." .. name .. " gibt keine Tabelle zurück")
		result = {}
	end
	children[name] = result
	return result
end

Config.Security = loadChild("Security")
Config.Client = loadChild("Client")
Config.Quality = loadChild("Quality")
Config.Market = loadChild("Market")
Config.Companies = loadChild("Companies")
Config.News = loadChild("News")
Config.Trading = loadChild("Trading")
Config.Tower = loadChild("Tower")
Config.City = loadChild("City")
Config.Vehicles = loadChild("Vehicles")
Config.Decor = loadChild("Decor")
Config.Lifestyle = loadChild("Lifestyle")
Config.Progression = loadChild("Progression")
Config.Season = loadChild("Season")
Config.Rewards = loadChild("Rewards")
Config.Shop = loadChild("Shop")
Config.Events = loadChild("Events")

-- =====================================================================
-- 10) LIVE-CONFIG ÜBERNEHMEN (ApplyLive)
-- =====================================================================
local MAX_LIVE_FIELDS = 256
local MAX_LIST = 16
local MAX_KEY_LEN = 40
local MAX_CODE_COSMETICS = 10
local MAX_TRACKED_PATHS = 1024 -- Obergrenze gemerkter Code-Stände (Wildcard-Schlüssel)

local liveBase: { [string]: { Value: any } } = {} -- Pfad -> Code-Wert vor der ersten Live-Änderung
local liveCurrent: { [string]: any } = {}
local trackedPaths = 0

local function splitPath(path: string): { string }
	local parts: { string } = {}
	for part in string.gmatch(path, "[^%.]+") do
		table.insert(parts, part)
		if #parts > 8 then
			break
		end
	end
	return parts
end

-- Eltern-Tabelle + Blatt-Schlüssel eines Pfads (Zwischen-Tabellen werden NIE angelegt)
local function resolveParent(path: string): ({ [string]: any }?, string?)
	local parts = splitPath(path)
	if #parts < 2 then
		return nil, nil
	end
	local node: any = Config
	for i = 1, #parts - 1 do
		node = node[parts[i]]
		if type(node) ~= "table" then
			return nil, nil
		end
	end
	return node, parts[#parts]
end

local function validKey(key: any): boolean
	return type(key) == "string" and #key >= 1 and #key <= MAX_KEY_LEN and string.match(key, "^[%w_]+$") ~= nil
end

-- Spezifikation zu einem Pfad: exakt oder über "Eltern.*"
local function specFor(path: string): (any, string?)
	local exact = Config.LiveFields[path]
	if exact ~= nil then
		return exact, nil
	end
	local parent, leaf = string.match(path, "^(.+)%.([^%.]+)$")
	if parent and leaf and validKey(leaf) then
		local wildcard = Config.LiveFields[parent .. ".*"]
		if wildcard ~= nil then
			return wildcard, leaf
		end
	end
	return nil, nil
end

local function numberBounds(spec: any): (number?, number?, boolean)
	if type(spec) ~= "table" then
		return nil, nil, false
	end
	local lo = if spec.Type == "number" then spec.Min else spec[1]
	local hi = if spec.Type == "number" then spec.Max else spec[2]
	if Util.IsFinite(lo) and Util.IsFinite(hi) and lo <= hi then
		return lo, hi, spec.Integer == true
	end
	return nil, nil, false
end

local function isIsoDate(text: any): boolean
	return type(text) == "string" and string.match(text, "^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$") ~= nil
end

-- Prüft/klemmt einen Live-Wert. Gibt (ok, sauberer Wert) zurück; Wert nil = Eintrag entfernen.
local function cleanValue(spec: any, value: any, current: any): (boolean, any)
	if type(spec) ~= "table" then
		return false, nil
	end
	local kind = spec.Type
	if kind == "boolean" then
		if type(value) ~= "boolean" then
			return false, nil
		end
		return true, value
	elseif kind == "list" then
		if type(value) ~= "table" then
			return false, nil
		end
		local minLen = if Util.IsFinite(spec.Min) then spec.Min else 1
		local maxLen = math.min(if Util.IsFinite(spec.Max) then spec.Max else MAX_LIST, MAX_LIST)
		local allowed: { [string]: boolean }? = nil
		if type(spec.Options) == "table" then
			allowed = {}
			for _, option in ipairs(spec.Options) do
				(allowed :: any)[option] = true
			end
		end
		local clean: { string } = {}
		local seen: { [string]: boolean } = {}
		for index, item in ipairs(value) do
			if index > maxLen or not validKey(item) or seen[item] then
				return false, nil
			end
			if allowed and not allowed[item] then
				return false, nil
			end
			seen[item] = true
			table.insert(clean, item)
		end
		if #clean < minLen then
			return false, nil
		end
		return true, clean
	elseif kind == "code" then
		if value == false then
			return true, nil -- Code live abschalten
		end
		if type(value) ~= "table" or type(value.Grant) ~= "table" then
			return false, nil
		end
		local maxCredits = if Util.IsFinite(spec.MaxCredits) then spec.MaxCredits else 0
		local grant: { [string]: any } = {}
		local any = false
		for field, amount in pairs(value.Grant) do
			if field == "Credits" then
				if not Util.IsFinite(amount) or amount % 1 ~= 0 or amount < 1 or amount > maxCredits then
					return false, nil
				end
				grant.Credits = amount
				any = true
			elseif field == "Cosmetics" then
				if type(amount) ~= "table" or #amount > MAX_CODE_COSMETICS then
					return false, nil
				end
				local list: { string } = {}
				for _, key in ipairs(amount) do
					if not validKey(key) then
						return false, nil
					end
					table.insert(list, key)
				end
				if #list > 0 then
					grant.Cosmetics = list
					any = true
				end
			else
				return false, nil -- Codes geben NUR CR oder Kosmetik (nie AKY/XP/Lizenz …)
			end
		end
		if not any then
			return false, nil
		end
		local entry: { [string]: any } = { Grant = grant }
		if value.Expires ~= nil then
			if not isIsoDate(value.Expires) then
				return false, nil
			end
			entry.Expires = value.Expires
		end
		return true, entry
	end
	-- Zahl
	local lo, hi, integer = numberBounds(spec)
	if lo == nil or hi == nil or not Util.IsFinite(value) then
		return false, nil
	end
	if current ~= nil and type(current) ~= "number" then
		return false, nil -- Code-Wert ist keine Zahl -> nicht überschreiben
	end
	local v = math.clamp(value, lo, hi)
	if integer then
		v = math.clamp(math.floor(v + 0.5), math.ceil(lo), math.floor(hi))
	end
	return true, v
end

function Config.ApplyLive(data: { [string]: any }): (number, { string })
	-- 1) alles früher Geänderte auf den Code-Stand zurück
	for path, base in pairs(liveBase) do
		local parent, leaf = resolveParent(path)
		if parent and leaf then
			parent[leaf] = Util.DeepCopy(base.Value)
		end
	end
	table.clear(liveCurrent)
	local issues: { string } = {}
	if type(data) ~= "table" then
		table.insert(issues, "LiveConfig: Tabelle erwartet")
		return 0, issues
	end
	local fields: { [any]: any } = if type(data.Fields) == "table" then data.Fields else data
	local applied = 0
	local seen = 0
	for path, value in pairs(fields) do
		if type(path) ~= "string" or not string.find(path, ".", 1, true) then
			continue -- Metadaten (Version, At, By …)
		end
		seen += 1
		if seen > MAX_LIVE_FIELDS then
			table.insert(issues, ("LiveConfig: mehr als %d Felder – Rest ignoriert"):format(MAX_LIVE_FIELDS))
			break
		end
		local spec = specFor(path)
		if spec == nil then
			table.insert(issues, path .. ": nicht in Config.LiveFields freigegeben")
			continue
		end
		local parent, leaf = resolveParent(path)
		if not parent or not leaf then
			table.insert(issues, path .. ": Pfad existiert nicht")
			continue
		end
		local base = liveBase[path]
		if base == nil and trackedPaths >= MAX_TRACKED_PATHS then
			table.insert(issues, path .. ": zu viele Live-Pfade")
			continue
		end
		local current = if base then base.Value else parent[leaf]
		local ok, clean = cleanValue(spec, value, current)
		if not ok then
			table.insert(issues, path .. ": ungültiger Wert")
			continue
		end
		if base == nil then
			liveBase[path] = { Value = Util.DeepCopy(parent[leaf]) }
			trackedPaths += 1
		end
		parent[leaf] = clean
		liveCurrent[path] = Util.DeepCopy(clean)
		applied += 1
	end
	return applied, issues
end

function Config.CurrentLive(): { [string]: any }
	return Util.DeepCopy(liveCurrent)
end

-- =====================================================================
-- 11) PRÜFEN – SelfTest und Boot-warn nutzen das (leere Liste = alles ok)
-- =====================================================================
local PRICE_LIMIT = 1e14 -- teuerster Einzelpreis laut Sim 4,9e13 (§C17 "alle Preise < 1e14 ganzzahlig")
local SCAN_DEPTH = 8
local SCAN_MAX_NODES = 20000
local MONEY_KEYS = { Price = true, Credits = true }
local ID_KEYS = { ImageId = true, SoundId = true }

local function checkNumber(errors: { string }, path: string, value: any, min: number?, integer: boolean?)
	if not Util.IsFinite(value) then
		table.insert(errors, path .. ": Zahl erwartet")
	elseif min ~= nil and value < min then
		table.insert(errors, ("%s: mindestens %s erwartet"):format(path, tostring(min)))
	elseif integer and value % 1 ~= 0 then
		table.insert(errors, path .. ": ganze Zahl erwartet")
	end
end

local function checkText(errors: { string }, path: string, value: any)
	if type(value) ~= "string" or value == "" or #value > 50 then
		table.insert(errors, path .. ": Text (1–50 Zeichen) erwartet")
	end
end

local function checkColors(errors: { string }, path: string, t: any)
	if type(t) ~= "table" then
		table.insert(errors, path .. ": Tabelle erwartet")
		return
	end
	for key, value in pairs(t) do
		if type(value) == "table" then
			checkColors(errors, path .. "." .. tostring(key), value)
		elseif typeof(value) ~= "Color3" then
			table.insert(errors, path .. "." .. tostring(key) .. ": Color3 erwartet")
		end
	end
end

local function isId(value: any): boolean
	return Util.IsFinite(value) and value >= 0 and value % 1 == 0 and value < 2 ^ 53
end

local function checkSlot(errors: { string }, path: string, slot: any)
	if type(slot) ~= "table" then
		table.insert(errors, path .. ": Asset-Platz { MeshId, TextureId, Scale, Offset } erwartet")
		return
	end
	if not isId(slot.MeshId) then
		table.insert(errors, path .. ".MeshId: ganze Zahl ≥ 0 erwartet (0 = Code-Rezept)")
	end
	if not isId(slot.TextureId) then
		table.insert(errors, path .. ".TextureId: ganze Zahl ≥ 0 erwartet")
	end
	if not Util.IsFinite(slot.Scale) or slot.Scale <= 0 then
		table.insert(errors, path .. ".Scale: Zahl > 0 erwartet")
	end
	if typeof(slot.Offset) ~= "CFrame" then
		table.insert(errors, path .. ".Offset: CFrame erwartet")
	end
end

-- Durchsucht alle Kinder: Preise/Credits ganzzahlig und < 1e14, Asset-/Bild-/Sound-Plätze typ-korrekt
local function scanChildren(errors: { string })
	local visited: { [any]: boolean } = {}
	local nodes = 0
	local function walk(path: string, t: { [any]: any }, depth: number)
		if depth > SCAN_DEPTH or visited[t] or nodes >= SCAN_MAX_NODES then
			return
		end
		visited[t] = true
		nodes += 1
		for key, value in pairs(t) do
			local here = path .. "." .. tostring(key)
			if type(key) == "string" and MONEY_KEYS[key] and type(value) == "number" then
				if not Util.IsFinite(value) or value < 0 or value % 1 ~= 0 then
					table.insert(errors, here .. ": ganze Zahl ≥ 0 erwartet")
				elseif value >= PRICE_LIMIT then
					table.insert(errors, here .. (": %s ≥ 1e14 (Preis-/Geld-Obergrenze)"):format(tostring(value)))
				end
			elseif type(key) == "string" and ID_KEYS[key] then
				if not isId(value) then
					table.insert(errors, here .. ": ganze Zahl ≥ 0 erwartet (0 = Code-Grafik/Rezept)")
				end
			elseif key == "Asset" then
				checkSlot(errors, here, value)
			elseif key == "Assets" and type(value) == "table" then
				for name, slot in pairs(value) do
					checkSlot(errors, here .. "." .. tostring(name), slot)
				end
			elseif type(value) == "table" then
				walk(here, value, depth + 1)
			end
		end
	end
	for _, name in ipairs(CHILDREN) do
		local child = children[name]
		if type(child) == "table" and loadErrors[name] == nil then
			walk("Config." .. name, child, 1)
		end
	end
end

local function validateLiveFields(errors: { string })
	if type(Config.LiveFields) ~= "table" then
		table.insert(errors, "Config.LiveFields: Tabelle erwartet")
		return
	end
	for path, spec in pairs(Config.LiveFields) do
		local where = "Config.LiveFields[" .. tostring(path) .. "]"
		if type(path) ~= "string" or #splitPath(path) < 2 or type(spec) ~= "table" then
			table.insert(errors, where .. ": Pfad mit Punkt und Spezifikation erwartet")
			continue
		end
		local kind = spec.Type
		if kind == "boolean" then
			continue
		elseif kind == "list" then
			if spec.Options ~= nil and type(spec.Options) ~= "table" then
				table.insert(errors, where .. ".Options: Liste erwartet")
			end
		elseif kind == "code" then
			if not Util.IsFinite(spec.MaxCredits) or spec.MaxCredits < 1 or spec.MaxCredits >= PRICE_LIMIT then
				table.insert(errors, where .. ".MaxCredits: Zahl 1 … 1e14 erwartet")
			end
		else
			local lo, hi = numberBounds(spec)
			if lo == nil or hi == nil then
				table.insert(errors, where .. ": { min, max } mit min ≤ max erwartet")
			end
		end
	end
end

local function validateCore(): { string }
	local errors: { string } = {}
	if type(Config.GameName) ~= "string" or Config.GameName == "" then
		table.insert(errors, "Config.GameName: Text erwartet")
	end
	if type(Config.Version) ~= "string" then
		table.insert(errors, "Config.Version: Text erwartet")
	end
	for key, value in pairs(Config.Admin) do
		if type(value) ~= "boolean" then
			table.insert(errors, "Config.Admin." .. key .. ": true/false erwartet")
		end
	end
	if Config.Admin.StudioAllPlayersAdmin == true then
		table.insert(errors, "Config.Admin.StudioAllPlayersAdmin: muss false sein (Player2 nie Admin, §B15.1)")
	end
	local tech = Config.Tech
	for _, name in ipairs({
		"DataStoreName",
		"KeyPrefix",
		"MessagingTopic",
		"BusTopic",
		"LiveStore",
		"StatsStore",
		"ModStore",
		"MarketStore",
		"GlobalStore",
		"GroupsStore",
		"BusMapPrefix",
		"HeartbeatMap",
		"BoardPrefix",
	}) do
		checkText(errors, "Config.Tech." .. name, (tech :: any)[name])
	end
	checkNumber(errors, "Config.Tech.DataVersion", tech.DataVersion, 1, true)
	checkNumber(errors, "Config.Tech.AutoSaveSeconds", tech.AutoSaveSeconds, 10)
	checkNumber(errors, "Config.Tech.AutoSaveStagger", tech.AutoSaveStagger, 0)
	checkNumber(errors, "Config.Tech.LoadAttempts", tech.LoadAttempts, 1, true)
	checkNumber(errors, "Config.Tech.SaveAttempts", tech.SaveAttempts, 1, true)
	checkNumber(errors, "Config.Tech.LockStaleSeconds", tech.LockStaleSeconds, 60)
	checkNumber(errors, "Config.Tech.BindToCloseSeconds", tech.BindToCloseSeconds, 1)
	checkNumber(errors, "Config.Tech.ReceiptKeep", tech.ReceiptKeep, 1, true)
	checkNumber(errors, "Config.Tech.StateFlush", tech.StateFlush, 0.05)
	checkNumber(errors, "Config.Tech.FullStateEvery", tech.FullStateEvery, 1)
	checkNumber(errors, "Config.Tech.Shards", tech.Shards, 1, true)
	checkNumber(errors, "Config.Tech.BoardWriteSeconds", tech.BoardWriteSeconds, 1)
	checkNumber(errors, "Config.Tech.StatsFlushSeconds", tech.StatsFlushSeconds, 1)
	checkNumber(errors, "Config.Tech.PingAttrEvery", tech.PingAttrEvery, 0.1)
	if Util.IsFinite(tech.BindToCloseSeconds) and tech.BindToCloseSeconds > 29 then
		table.insert(errors, "Config.Tech.BindToCloseSeconds: höchstens 29 (Roblox gibt 30 s)")
	end
	if Util.IsFinite(tech.StateFlush) and tech.StateFlush < 0.2 then
		table.insert(errors, "Config.Tech.StateFlush: mindestens 0,2 (State ≤ 5×/s)")
	end
	for key, value in pairs(Config.Studio) do
		if type(value) ~= "boolean" and not Util.IsFinite(value) then
			table.insert(errors, "Config.Studio." .. key .. ": Zahl oder true/false erwartet")
		end
	end
	for key, value in pairs(Config.Debug) do
		if type(value) ~= "boolean" then
			table.insert(errors, "Config.Debug." .. key .. ": true/false erwartet")
		end
	end
	local server = Config.Server
	checkNumber(errors, "Config.Server.MaxPlayers", server.MaxPlayers, 1, true)
	checkNumber(errors, "Config.Server.Plots", server.Plots, 1, true)
	if Util.IsFinite(server.Plots) and Util.IsFinite(server.MaxPlayers) and server.MaxPlayers > server.Plots then
		table.insert(errors, "Config.Server.MaxPlayers: höchstens so viele wie Plots (ein Plot je Spieler)")
	end
	if server.MaxMoney ~= 9e15 then
		table.insert(errors, "Config.Server.MaxMoney: muss 9e15 sein (Muss-Regel 9, < 2^53)")
	end
	checkColors(errors, "Config.Colors", Config.Colors)
	local notifications = Config.Notifications
	if type(notifications.Enabled) ~= "boolean" then
		table.insert(errors, "Config.Notifications.Enabled: true/false erwartet")
	end
	checkNumber(errors, "Config.Notifications.MaxPerDay", notifications.MaxPerDay, 0, true)
	checkNumber(errors, "Config.Notifications.PromptAfterStep", notifications.PromptAfterStep, 1, true)
	validateLiveFields(errors)
	scanChildren(errors)
	return errors
end

function Config.Validate(): { string }
	local errors: { string } = {}
	for _, name in ipairs(CHILDREN) do
		local loadError = loadErrors[name]
		if loadError then
			table.insert(errors, "Config." .. name .. ": " .. loadError)
		else
			local validate = children[name].Validate
			if type(validate) == "function" then
				local ok, result = pcall(validate, Config)
				if not ok then
					table.insert(errors, "Config." .. name .. ".Validate: Fehler " .. tostring(result))
				elseif type(result) == "table" then
					for _, message in ipairs(result) do
						table.insert(errors, tostring(message))
					end
				elseif result ~= nil then
					table.insert(errors, "Config." .. name .. ".Validate: Liste von Texten erwartet")
				end
			else
				table.insert(errors, "Config." .. name .. ": Validate(Config) fehlt (§C14)")
			end
		end
	end
	for _, message in ipairs(validateCore()) do
		table.insert(errors, message)
	end
	return errors
end

return Config
