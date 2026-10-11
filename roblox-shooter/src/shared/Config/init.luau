-- =====================================================================
--  CLUTCH CLASH – ZENTRALE EINSTELLUNGEN (Shared/Config)
--  Besitzer: WP1 (Core & Plattform). Vertrag: DESIGN.md C15 + C6.1.
--  Hier stellst du (fast) alles ein, ohne anderen Code anzufassen.
--  Zahlen sind Startwerte aus DESIGN.md und 1:1 änderbar.
--  ACHTUNG: Config wird an alle Clients repliziert -> KEINE Geheimnisse hier!
--
--  Kindmodule (werden automatisch geladen, jedes Paket pflegt sein eigenes):
--    Weapons (WP3), Combat (WP3), Maps (WP2), Modes (WP5), Bots (WP6), Security (WP7),
--    Progression (WP8), Season (WP8), Cosmetics (WP9), Shop (WP9), Client (WP10)
--    -> erreichbar als Config.Weapons, Config.Modes, … Jedes darf Validate(Config): { string } haben.
--
--  Öffentliche Helfer:
--    Config.Weapon(key): WeaponDef?          Basiswerte + Live-Balance-Overrides
--    Config.WeaponById(id): WeaponDef?
--    Config.ApplyBalance(data)               { Version, Weapons = {[key] = {[field] = value}}, Disabled = {[key] = true} }
--    Config.CurrentBalance()                 Kopie der gerade aktiven Overrides { Version, Weapons, Disabled }
--    Config.Validate(): { string }           sammelt Child.Validate(Config) aller Kindmodule + eigene Prüfungen
-- =====================================================================

local RunService = game:GetService("RunService")

local Shared = script.Parent
local Util = require(Shared:WaitForChild("Util"))
local Types = require(Shared:WaitForChild("Types"))

local Config = {}

Config.GameName = "CLUTCH CLASH"
Config.Version = "1.0.0"

-- ---------------------------------------------------------------------
-- 1) ADMINS – NUR DU: Wem das Spiel gehört (dein Account, mit dem du es
--    veröffentlichst), ist Admin. Du musst hier nichts eintragen!
--    Admin kann man NICHT kaufen – der Server prüft es bei jeder Aktion.
--    Im Studio-Test bist du Admin (Player1 = -1), Player2 (-2) bewusst NICHT.
-- ---------------------------------------------------------------------
Config.Admin = {
	OwnerIsAdmin = true,
	StudioIsAdmin = true,
	StudioAllPlayersAdmin = false, -- false lassen, sonst ist der "Abgelehnt"-Weg nicht testbar
}

-- ---------------------------------------------------------------------
-- 2) TECHNIK (nur ändern, wenn du weißt was du tust)
--    DataStoreName ändern = alle Spielstände sind weg!
-- ---------------------------------------------------------------------
Config.Tech = {
	DataStoreName = "CC_Player_v1",
	DataVersion = 1,
	MessagingTopic = "CC_Global",
	AutoSaveSeconds = 90, -- Auto-Save aller Spielstände
	AutoSaveStagger = 0.5, -- Abstand zwischen zwei Spielern beim Auto-Save
	LoadAttempts = 6,
	SaveAttempts = 4,
	LockStaleSeconds = 1800, -- Session-Lock älter als 30 Min gilt als verwaist
	BindToCloseSeconds = 25, -- Roblox gibt beim Herunterfahren max. 30 s
	ReceiptKeep = 60, -- so viele Kauf-Belege bleiben im Spielstand
	StateFlush = 0.2, -- State an den Client höchstens alle 0.2 s (≤ 5 Pakete/s)
	FullStateEvery = 20, -- voller State als Sicherheitsnetz
	LiveStore = "CC_Live_v1",
	StatsStore = "CC_Stats_v1",
	ModStore = "CC_Mod_v1",
	Shards = 8,
	BoardPrefix = "CC_LB_",
	BoardWriteSeconds = 300,
	BalancePollSeconds = 120,
	StatsFlushSeconds = 600,
	PingAttrEvery = 2, -- Attribut "PingMs" am Player alle 2 s
}

-- ---------------------------------------------------------------------
-- 3) STUDIO – Testen ohne Speichern, schnelle Bots, Selbsttest
-- ---------------------------------------------------------------------
Config.Studio = {
	NoSave = true, -- im Studio nie speichern (Toast "Studio: Fortschritt wird nicht gespeichert")
	BotFillSeconds = 2, -- Pads füllen im Studio schon nach 2 s mit Bots
	SelfTest = true, -- "[SelfTest] n/n PASS" im Output beim Start
}

-- ---------------------------------------------------------------------
-- 4) DEBUG – auch im Admin-Panel (Tab Debug) umschaltbar
-- ---------------------------------------------------------------------
Config.Debug = {
	LogRejects = false, -- abgelehnte Schüsse mit Grund an den Schützen melden
	ShowHitboxes = false,
	BotPaths = false,
	ForceRestricted = false, -- so tun, als wären bezahlte Zufallsitems verboten (Policy-Test)
}

-- ---------------------------------------------------------------------
-- 5) SERVER – Arenen, Bots, Grenzen
-- ---------------------------------------------------------------------
Config.Server = {
	MaxPlayers = 18,
	ArenaSlots = 8,
	SlotSpacing = 4000,
	SlotRowZ = 4000,
	VaultDepth = 250,
	IdleMapSeconds = 180,
	KeepWarmMaps = 3,
	CleanupEvery = 30,
	MaxBots = 12,
	MaxBotsPerMatch = 7,
	MaxProjectilesPerArena = 40,
	MaxProjectilesTotal = 160,
	CrownAudienceRadius = 150,
}

-- ---------------------------------------------------------------------
-- 6) SPIELER – Leben, Bewegung (B12/B13)
-- ---------------------------------------------------------------------
Config.Player = {
	MaxHp = 100,
	Walk = 16,
	Sprint = 22,
	JumpHeight = 7.2,
	AirJumpHeight = 6,
	SprintToFire = 0.12,
	Slide = {
		MinSpeed = 18,
		Start = 32,
		End = 14,
		Time = 0.75,
		Cooldown = 1.0,
		JumpKeep = 0.9,
		JumpCap = 30,
		CamDrop = 1.6,
		FovKick = 6,
		SpreadAdd = 1,
	},
	SpawnShield = 1.5,
	Regen = { Delay = 5, Rate = 12 },
	KillY = -40,
	LobbyZoomMax = 14,
}

-- ---------------------------------------------------------------------
-- 7) FARBEN (A4) – Teamfarben farbenblind-tauglich
-- ---------------------------------------------------------------------
Config.Colors = {
	TeamA = Color3.fromRGB(255, 140, 40), -- BLAZE
	TeamB = Color3.fromRGB(60, 170, 255), -- FROST
	Enemy = {
		Red = Color3.fromRGB(255, 59, 59),
		Magenta = Color3.fromRGB(255, 59, 216),
		Yellow = Color3.fromRGB(255, 212, 59),
		White = Color3.fromRGB(255, 255, 255),
	},
	Rarity = {
		Common = Color3.fromRGB(170, 170, 170),
		Rare = Color3.fromRGB(60, 140, 255),
		Epic = Color3.fromRGB(170, 90, 255),
		Legendary = Color3.fromRGB(255, 200, 40),
		Mythic = Color3.fromRGB(255, 60, 170),
	},
	Palette = {
		Cream = Color3.fromRGB(244, 235, 221),
		Mint = Color3.fromRGB(154, 209, 212),
		Pink = Color3.fromRGB(247, 183, 200),
		Lilac = Color3.fromRGB(185, 167, 242),
		Sand = Color3.fromRGB(242, 213, 154),
		Charcoal = Color3.fromRGB(43, 43, 51),
		Navy = Color3.fromRGB(28, 32, 64),
		White = Color3.fromRGB(235, 238, 245),
		Tip = Color3.fromRGB(255, 120, 0), -- orange Spitze jedes Blasters
	},
}

-- =====================================================================
-- 8) KINDMODULE – dynamisch geladen (fehlt eins, gibt es eine leere Tabelle
--    und Config.Validate() meldet es; der Rest läuft weiter)
-- =====================================================================
local CHILDREN = {
	"Weapons",
	"Combat",
	"Maps",
	"Modes",
	"Bots",
	"Security",
	"Progression",
	"Season",
	"Cosmetics",
	"Shop",
	"Client",
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

Config.Weapons = loadChild("Weapons")
Config.Combat = loadChild("Combat")
Config.Maps = loadChild("Maps")
Config.Modes = loadChild("Modes")
Config.Bots = loadChild("Bots")
Config.Security = loadChild("Security")
Config.Progression = loadChild("Progression")
Config.Season = loadChild("Season")
Config.Cosmetics = loadChild("Cosmetics")
Config.Shop = loadChild("Shop")
Config.Client = loadChild("Client")

-- =====================================================================
-- 9) WAFFEN-NACHSCHLAGEN + LIVE-BALANCE
--    Basis = Config.Weapons.List. Overrides nur für Felder aus
--    Config.Weapons.BalanceFields (geklemmt), Disabled -> Enabled = false.
-- =====================================================================
type WeaponDef = Types.WeaponDef
type BalanceData = { Version: number, Weapons: { [string]: { [string]: number } }, Disabled: { [string]: boolean } }

local INTEGER_FIELDS = { Mag = true } -- ganze Zahlen (Magazin)

local baseByKey: { [string]: WeaponDef } = {}
local baseById: { [number]: WeaponDef } = {}
local effectiveByKey: { [string]: WeaponDef } = {}
local effectiveById: { [number]: WeaponDef } = {}
local weaponIssues: { string } = {}
local balance: BalanceData = { Version = 0, Weapons = {}, Disabled = {} }

local function balanceFields(): { [string]: { number } }
	local fields = Config.Weapons.BalanceFields
	return if type(fields) == "table" then fields else {}
end

-- Gültige Grenzen {min, max} eines Balance-Felds (oder nil)
local function boundsOf(field: string): (number?, number?)
	local bounds = balanceFields()[field]
	if type(bounds) ~= "table" then
		return nil, nil
	end
	local lo, hi = bounds[1], bounds[2]
	if not (Util.IsFinite(lo) and Util.IsFinite(hi)) or lo > hi then
		return nil, nil
	end
	return lo, hi
end

-- Ein Override auf eine Kopie der Waffe schreiben ("Projectile.SplashMax" = verschachteltes Feld)
local function applyField(def: { [string]: any }, path: string, value: number): boolean
	local lo, hi = boundsOf(path)
	if lo == nil or hi == nil or not Util.IsFinite(value) then
		return false
	end
	local v = math.clamp(value, lo, hi)
	local parent: { [string]: any } = def
	local leaf = path
	local dot = string.find(path, ".", 1, true)
	if dot then
		local head = string.sub(path, 1, dot - 1)
		leaf = string.sub(path, dot + 1)
		local nested = def[head]
		if type(nested) ~= "table" then
			return false -- z. B. Projectile-Feld bei einer Hitscan-Waffe
		end
		parent = nested
	end
	if type(parent[leaf]) ~= "number" then
		return false -- nur vorhandene Zahlenfelder überschreiben
	end
	if INTEGER_FIELDS[leaf] then
		v = math.clamp(math.floor(v + 0.5), math.ceil(lo), math.floor(hi))
	end
	parent[leaf] = v
	return true
end

local function rebuildEffective()
	table.clear(effectiveByKey)
	table.clear(effectiveById)
	for key, base in pairs(baseByKey) do
		local def: any = Util.DeepCopy(base)
		local overrides = balance.Weapons[key]
		if overrides then
			for field, value in pairs(overrides) do
				applyField(def, field, value)
			end
		end
		if balance.Disabled[key] then
			def.Enabled = false
		end
		effectiveByKey[key] = def
		effectiveById[def.Id] = def
	end
end

local function buildWeaponLookups()
	local list = Config.Weapons.List
	if list == nil then
		return
	end
	if type(list) ~= "table" then
		table.insert(weaponIssues, "Config.Weapons.List: Tabelle erwartet")
		return
	end
	for index, def in ipairs(list) do
		if type(def) ~= "table" or type(def.Key) ~= "string" or not Util.IsFinite(def.Id) then
			table.insert(weaponIssues, ("Config.Weapons.List[%d]: Key (string) und Id (Zahl) erwartet"):format(index))
		else
			assert(baseByKey[def.Key] == nil, "[Config] Doppelter Waffen-Key: " .. def.Key)
			assert(baseById[def.Id] == nil, "[Config] Doppelte Waffen-Id: " .. tostring(def.Id))
			baseByKey[def.Key] = def
			baseById[def.Id] = def
		end
	end
	rebuildEffective()
end

buildWeaponLookups()

-- Waffe mit Live-Balance (gecachte Tabelle – NICHT verändern!)
function Config.Weapon(key: string): Types.WeaponDef?
	if type(key) ~= "string" then
		return nil
	end
	return effectiveByKey[key]
end

function Config.WeaponById(id: number): Types.WeaponDef?
	if type(id) ~= "number" then
		return nil
	end
	return effectiveById[id]
end

-- Live-Balance übernehmen (BalanceService auf dem Server, LiveBalance-StringValue auf dem Client).
-- Unbekannte Waffen/Felder und kaputte Zahlen werden still ignoriert, Werte geklemmt.
function Config.ApplyBalance(data: {
	Version: number,
	Weapons: { [string]: { [string]: any } },
	Disabled: { [string]: boolean },
})
	if type(data) ~= "table" then
		warn("[Config] ApplyBalance: Tabelle erwartet")
		return
	end
	local raw: any = data
	local clean: BalanceData = {
		Version = if Util.IsFinite(raw.Version) then raw.Version else 0,
		Weapons = {},
		Disabled = {},
	}
	if type(raw.Weapons) == "table" then
		for key, fields in pairs(raw.Weapons) do
			if type(key) == "string" and baseByKey[key] and type(fields) == "table" then
				local entry: { [string]: number } = {}
				local count = 0
				for field, value in pairs(fields) do
					if type(field) == "string" and boundsOf(field) ~= nil and Util.IsFinite(value) then
						entry[field] = value
						count += 1
					end
				end
				if count > 0 then
					clean.Weapons[key] = entry
				end
			end
		end
	end
	if type(raw.Disabled) == "table" then
		for key, flag in pairs(raw.Disabled) do
			if type(key) == "string" and baseByKey[key] and flag == true then
				clean.Disabled[key] = true
			end
		end
	end
	balance = clean
	rebuildEffective()
end

-- Kopie der aktiven Overrides (für Admin-Panel/Anzeige)
function Config.CurrentBalance(): {
	Version: number,
	Weapons: { [string]: { [string]: number } },
	Disabled: { [string]: boolean },
}
	return Util.DeepCopy(balance)
end

-- =====================================================================
-- 10) PRÜFEN – SelfTest und Boot-warn nutzen das (leere Liste = alles ok)
-- =====================================================================
local function checkNumber(errors: { string }, path: string, value: any, min: number?, integer: boolean?)
	if not Util.IsFinite(value) then
		table.insert(errors, path .. ": Zahl erwartet")
	elseif min ~= nil and value < min then
		table.insert(errors, ("%s: mindestens %s erwartet"):format(path, tostring(min)))
	elseif integer and value % 1 ~= 0 then
		table.insert(errors, path .. ": ganze Zahl erwartet")
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
	for _, name in ipairs({ "DataStoreName", "MessagingTopic", "LiveStore", "StatsStore", "ModStore", "BoardPrefix" }) do
		local value = (Config.Tech :: any)[name]
		if type(value) ~= "string" or value == "" or #value > 50 then
			table.insert(errors, "Config.Tech." .. name .. ": Text (1–50 Zeichen) erwartet")
		end
	end
	local tech = Config.Tech
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
	checkNumber(errors, "Config.Tech.BalancePollSeconds", tech.BalancePollSeconds, 1)
	checkNumber(errors, "Config.Tech.StatsFlushSeconds", tech.StatsFlushSeconds, 1)
	checkNumber(errors, "Config.Tech.PingAttrEvery", tech.PingAttrEvery, 0.1)
	if tech.BindToCloseSeconds > 29 then
		table.insert(errors, "Config.Tech.BindToCloseSeconds: höchstens 29 (Roblox gibt 30 s)")
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
	for key, value in pairs(Config.Server) do
		checkNumber(errors, "Config.Server." .. key, value, 0)
	end
	local slots = Config.Server.ArenaSlots
	if not Util.IsFinite(slots) or slots % 1 ~= 0 or slots < 1 or slots > 8 then
		table.insert(errors, "Config.Server.ArenaSlots: ganze Zahl 1–8 erwartet (Slot-Koordinaten B9.1)")
	end
	if Config.Server.MaxBotsPerMatch > Config.Server.MaxBots then
		table.insert(errors, "Config.Server.MaxBotsPerMatch: darf nicht größer als MaxBots sein")
	end
	if Config.Server.MaxProjectilesPerArena > Config.Server.MaxProjectilesTotal then
		table.insert(errors, "Config.Server.MaxProjectilesPerArena: darf nicht größer als MaxProjectilesTotal sein")
	end
	local player = Config.Player
	checkNumber(errors, "Config.Player.MaxHp", player.MaxHp, 1)
	checkNumber(errors, "Config.Player.Walk", player.Walk, 1)
	checkNumber(errors, "Config.Player.Sprint", player.Sprint, player.Walk)
	checkNumber(errors, "Config.Player.JumpHeight", player.JumpHeight, 0)
	checkNumber(errors, "Config.Player.SpawnShield", player.SpawnShield, 0)
	checkNumber(errors, "Config.Player.KillY", player.KillY, -490) -- über FallenPartsDestroyHeight (−500)
	for key, value in pairs(player.Slide) do
		checkNumber(errors, "Config.Player.Slide." .. key, value, 0)
	end
	checkNumber(errors, "Config.Player.Regen.Delay", player.Regen.Delay, 0)
	checkNumber(errors, "Config.Player.Regen.Rate", player.Regen.Rate, 0)
	checkColors(errors, "Config.Colors", Config.Colors)
	-- Balance-Grenzen (von ApplyBalance benutzt)
	local fields = Config.Weapons.BalanceFields
	if fields ~= nil then
		if type(fields) ~= "table" then
			table.insert(errors, "Config.Weapons.BalanceFields: Tabelle erwartet")
		else
			for field in pairs(fields) do
				if type(field) ~= "string" or boundsOf(field) == nil then
					table.insert(errors, "Config.Weapons.BalanceFields." .. tostring(field) .. ": {min, max} erwartet")
				end
			end
		end
	end
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
			end
		end
	end
	for _, message in ipairs(weaponIssues) do
		table.insert(errors, message)
	end
	for _, message in ipairs(validateCore()) do
		table.insert(errors, message)
	end
	return errors
end

return Config
