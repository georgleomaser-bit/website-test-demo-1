--!strict
-- =====================================================================
--  AKYTEX TYCOON – Team-Rollen, Rechte & Chat-Befehle (Shared/Staff)
--  Besitzer: WP11 (Admin, Events, Anti-Cheat) – W19 Team-Rollen + W26 Entbannen.
--  Vertrag: aky3_admin_spec §3 + §16 (Korrektur), DESIGN.md §B15. REIN: keine Dienste beim Laden, kein Config-require
--  -> mit der Luau-CLI testbar (tests/staff.test.luau). Pfad im Spiel: ReplicatedStorage.Shared.Staff.
--  Benutzt von: Config/Security.Validate (lazy), StaffService, AdminService, ChatTools, AdminPanel, AdminTools, Fly.
--
--  Rollen: Owner (3, fest) > Admin (2) > Moderator (1) > Spieler (0). Rollen kann man NIE kaufen.
--  Rang-Regel: Handelnder > Ziel (CanActOn). Rechte aus LOCKED_OWNER hat immer nur der Besitzer (egal, was in Config steht).
--  Der Server prüft JEDE Aktion neu – Client-Aufrufe dieser Hilfen sind nur Anzeige.
--
--  Daten:
--    Staff.ROLES { "Moderator", "Admin", "Owner" } · Staff.RANK { Moderator = 1, Admin = 2, Owner = 3 }
--    Staff.PERMS (46 Rechte, inkl. UnbanOwn/BanView) · Staff.LOCKED_OWNER (8 Besitzer-Rechte) · Staff.REPORT_REASONS
--    Staff.RESERVED (Roblox-Standard-Aliase + trade/terminal von W20 – nie belegt)
--    Staff.COMMANDS (31 Befehle, Reihenfolge = /cmds) · Staff.EVENTS (/event-Namen; Text-Werte = Alias)
--
--  Öffentliche API (alle rein, nie yieldend):
--    Staff.Rank(role): number                        nil/unbekannt -> 0
--    Staff.Can(role, perm, cfg): boolean             cfg = Config.Security.Staff; unbekanntes Recht -> false
--    Staff.CanAny(role, perms, cfg): boolean
--    Staff.CanActOn(actorRank, targetRank): boolean  actorRank > targetRank
--    Staff.CanSetRole(actorRole, targetRank, targetIsOwner, newRole, cfg): (boolean, string?)   Fehler = Lang-Schlüssel
--    Staff.CanUnban(actorRole, actorUserId, entry, cfg): (boolean, string?)   Moderator nur eigene Zeit-Banns (W26)
--    Staff.CanUndo(actorRank, punisherRank, isSelf, actorIsOwner): boolean    Unmute/Unfreeze-Regel (§16.2 Nr. 5)
--    Staff.ResolveRole(info): string?                Owner > max(gespeichert, Gruppe)
--    Staff.ParseDuration(text, plainUnit?): number?  Sekunden, -1 = dauerhaft
--    Staff.ParseAmount(text): number?                5000, 25k, 1.5m, 1,5m, 2b, 3t, 2mio, 1mrd, -2k
--    Staff.Tokenize(text): { string }                Leerzeichen-getrennt, ≤ 40 Teile à ≤ 100 Byte
--    Staff.ParseCommand(raw): (def?, args, prefix?, name?)
--    Staff.IsCommandText(text, prefix?): boolean     ";kick bob" true, ";)" false
--    Staff.MatchTargets(text, players, actor): (list, errKey?, errArg?)
--    Staff.IsMass(text): boolean                     "all" / "others"
--    Staff.ReasonFromText(word): string              -> REPORT_REASONS
--    Staff.ShouldDeliver(info): boolean              TextChannel.ShouldDeliverCallback (Stumm, persönlich, ;-Befehle)
--    Staff.ValidateMsg(msg, now): table?             MessagingService "AT_Staff" (Role / Kick / Report)
--    Staff.CheckPerms(perms, eventPerms): { string } für Security.Validate
--    Staff.CommandByName(name): Command?             Name oder Alias
--    Staff.VisibleCommand(def, role, cfg): boolean   Perm "" / Personal / Can / CanAny(AnyPerm)
--  Ergänzungen (gleich rein): Staff.EventSpec(name): (spec?, key?) löst /event-Aliase auf · Staff.EventNames(): { string }
-- =====================================================================

local Staff = {}

export type Command = {
	Name: string, -- Kleinbuchstaben, ≤ 12 (/name)
	Alias: string?, -- zweiter /-Name
	Perm: string, -- "" = alle
	MinArgs: number,
	Personal: boolean?, -- für alle nutzbar, ohne Recht persönlich (z. B. /mute = nur für mich stumm)
	Confirm: boolean?, -- braucht "confirm" am Ende
	AnyPerm: { string }?, -- sichtbar, wenn eines dieser Rechte da ist
}

export type EventSpec = {
	Type: string, -- "Abuse" | "World" | "Market" | "Stop"
	Kind: string?,
	Args: { [string]: any }?,
	Num: string?, -- Zahl hinter dem Namen landet in Args[Num]
	Inst: boolean?, -- braucht Ticker/Id
}

local OWNER_RANK = 3
local MAX_COMMAND_BYTES = 300
local MAX_TOKENS = 40
local MAX_TOKEN_BYTES = 100
local MAX_TARGET_BYTES = 60
local MAX_LIST_PARTS = 10
local MAX_AMBIGUOUS_NAMES = 5
local MAX_DURATION = 3650 * 86400 -- 10 Jahre
local MAX_AMOUNT = 1e15
local TEN_YEARS = 3650 * 86400

-- =====================================================================
-- DATEN
-- =====================================================================
Staff.ROLES = { "Moderator", "Admin", "Owner" } :: { string }
Staff.RANK = { Moderator = 1, Admin = 2, Owner = 3 } :: { [string]: number }

Staff.PERMS = {
	-- Moderator
	"Panel",
	"PlayerList",
	"Kick",
	"Mute",
	"Warn",
	"TempBan",
	"Teleport",
	"Bring",
	"Freeze",
	"Spectate",
	"Respawn",
	"Reports",
	"Logs",
	"TeamView",
	"UnbanOwn", -- W26: eigene Zeit-Banns aufheben
	"BanView", -- W26: Tab „Banns“ + Liste
	-- Admin
	"Ban",
	"Unban",
	"MassTarget",
	"Fly",
	"Noclip",
	"GiveSpeed",
	"GiveCredits",
	"Announce",
	"AnnounceGlobal",
	"FunEvents",
	"WorldEvents",
	"ManageMods",
	"ShowCam",
	-- Owner
	"ManageAdmins",
	"TakeCredits",
	"GiveItems",
	"GiveAky",
	"PlayerData",
	"Purchases",
	"MarketEvents",
	"EconomyEvents",
	"GlobalEvents",
	"LockServer",
	"Shutdown",
	"KickAll",
	"LiveConfig",
	"Stats",
	"Debug",
	"Invisible",
	"Esp",
} :: { string }

-- Fest auf den Besitzer gesperrt (Security.Validate lehnt andere Werte ab, Can ignoriert Config hier)
Staff.LOCKED_OWNER = {
	ManageAdmins = true,
	GiveAky = true,
	MarketEvents = true,
	LockServer = true,
	Shutdown = true,
	LiveConfig = true,
	Purchases = true,
	Debug = true,
} :: { [string]: boolean }

Staff.REPORT_REASONS = { "Speed", "Fly", "Exploit", "Toxic", "Other" } :: { string } -- = AntiCheatService.REPORT_REASONS

-- Roblox-Standard-Aliase, die wir NIE belegen (mute/unmute übernehmen wir bewusst, der Standard ist dort aus).
-- trade/terminal legt W20 clientseitig an (aky3_trading_spec §4.4.11).
Staff.RESERVED = {
	team = true,
	t = true,
	whisper = true,
	w = true,
	emote = true,
	e = true,
	help = true,
	["?"] = true,
	console = true,
	clear = true,
	cls = true,
	version = true,
	v = true,
	m = true,
	um = true,
	trade = true,
	terminal = true,
} :: { [string]: boolean }

-- Reihenfolge = Reihenfolge in /cmds
Staff.COMMANDS = {
	{ Name = "cmds", Alias = "commands", Perm = "", MinArgs = 0 },
	{ Name = "report", Perm = "", MinArgs = 2 },
	{ Name = "staff", Perm = "", MinArgs = 0 },
	{ Name = "mute", Perm = "Mute", MinArgs = 1, Personal = true },
	{ Name = "unmute", Perm = "Mute", MinArgs = 1, Personal = true },
	{ Name = "kick", Perm = "Kick", MinArgs = 1 },
	{ Name = "ban", Perm = "TempBan", MinArgs = 1 },
	{ Name = "unban", Perm = "UnbanOwn", MinArgs = 1 }, -- W26: Moderatoren nur eigene Zeit-Banns (Server: CanUnban)
	{ Name = "warn", Perm = "Warn", MinArgs = 2 },
	{ Name = "tp", Alias = "goto", Perm = "Teleport", MinArgs = 1 },
	{ Name = "bring", Perm = "Bring", MinArgs = 1 },
	{ Name = "freeze", Perm = "Freeze", MinArgs = 1 },
	{ Name = "unfreeze", Alias = "thaw", Perm = "Freeze", MinArgs = 1 },
	{ Name = "spectate", Alias = "spec", Perm = "Spectate", MinArgs = 1 },
	{ Name = "unspectate", Alias = "unspec", Perm = "Spectate", MinArgs = 0 },
	{ Name = "respawn", Alias = "re", Perm = "Respawn", MinArgs = 1 },
	{ Name = "logs", Alias = "log", Perm = "Logs", MinArgs = 0 },
	{ Name = "fly", Perm = "Fly", MinArgs = 0 },
	{ Name = "noclip", Perm = "Noclip", MinArgs = 0 },
	{ Name = "speed", Alias = "ws", Perm = "GiveSpeed", MinArgs = 2 },
	{ Name = "jump", Alias = "jp", Perm = "GiveSpeed", MinArgs = 2 },
	{ Name = "money", Alias = "cr", Perm = "GiveCredits", MinArgs = 2 },
	{ Name = "announce", Alias = "ann", Perm = "Announce", MinArgs = 1 },
	{
		Name = "event",
		Alias = "ev",
		Perm = "FunEvents",
		MinArgs = 0,
		AnyPerm = { "FunEvents", "WorldEvents", "EconomyEvents", "MarketEvents" },
	},
	{ Name = "mod", Perm = "ManageMods", MinArgs = 1 },
	{ Name = "unrank", Alias = "demote", Perm = "ManageMods", MinArgs = 1 },
	{ Name = "admin", Perm = "ManageAdmins", MinArgs = 1 },
	{ Name = "aky", Perm = "GiveAky", MinArgs = 2 },
	{ Name = "lock", Perm = "LockServer", MinArgs = 0 },
	{ Name = "unlock", Perm = "LockServer", MinArgs = 0 },
	{ Name = "shutdown", Perm = "Shutdown", MinArgs = 0, Confirm = true },
} :: { Command }

-- /event-Tabelle: Name -> Spec (Text-Wert = Alias auf einen anderen Namen). Type: "Abuse" (Actions.Abuse),
-- "World" (Actions.WorldEvent), "Market" (Actions.Abuse mit Markt-Art, immer global), "Stop" (Actions.AbuseStop).
-- Args werden vom Aufrufer KOPIERT; Markt-Werte klemmt AdminService.Core.MarketArgs.
Staff.EVENTS = {
	rain = { Type = "Abuse", Kind = "MoneyRain", Args = { Seconds = 120 } },
	moneyrain = "rain",
	golden = { Type = "Abuse", Kind = "GoldenHour", Args = { Mult = 2, Minutes = 15 } },
	goldenhour = "golden",
	xp = { Type = "Abuse", Kind = "XpRush", Args = { Minutes = 30 } },
	xprush = "xp",
	boom = { Type = "Abuse", Kind = "BuildBoom" },
	buildboom = "boom",
	lights = { Type = "Abuse", Kind = "Lightshow" },
	lightshow = "lights",
	fireworks = { Type = "Abuse", Kind = "Fireworks" },
	confetti = { Type = "Abuse", Kind = "Confetti" },
	bell = { Type = "Abuse", Kind = "BellShow" },
	bellshow = "bell",
	boss = { Type = "Abuse", Kind = "Boss", Args = { Seconds = 120 } },
	hall = { Type = "Abuse", Kind = "AllToHall" },
	alltohall = "hall",
	show = { Type = "Abuse", Kind = "SaturdayShow" },
	saturday = "show",
	truck = { Type = "World", Kind = "Truck" },
	drones = { Type = "World", Kind = "Drones" },
	press = { Type = "World", Kind = "Press" },
	skyshow = { Type = "World", Kind = "SkyShow" },
	bear = { Type = "World", Kind = "Bear" },
	bull = { Type = "World", Kind = "GoldenBull" },
	bellmoment = { Type = "World", Kind = "BellMoment" },
	rally = { Type = "Market", Kind = "MegaRally", Num = "Strength" }, -- /event rally [5–50]
	crash = { Type = "Market", Kind = "MegaCrash", Num = "Strength" },
	pump = { Type = "Market", Kind = "Pump", Inst = true, Num = "Strength" }, -- /event pump <Ticker|Id> [%]
	dump = { Type = "Market", Kind = "Dump", Inst = true, Num = "Strength" },
	halt = { Type = "Market", Kind = "Halt", Num = "Seconds" },
	resume = { Type = "Market", Kind = "Resume" },
	normalize = { Type = "Market", Kind = "Normalize" },
	vol = { Type = "Market", Kind = "Vol", Num = "Strength" },
	ipo = { Type = "Market", Kind = "Ipo", Inst = true },
	stop = { Type = "Stop" }, -- /event stop <Name, z. B. golden|rain|boss|lights|fireworks|bear|bull|xp>
} :: { [string]: any }

-- =====================================================================
-- INDIZES (beim Laden; Daten sind fest -> Verstöße sind Programmierfehler)
-- =====================================================================
local RANK = Staff.RANK
local LOCKED = Staff.LOCKED_OWNER
local ROLE_BY_RANK: { [number]: string } = { [1] = "Moderator", [2] = "Admin", [3] = "Owner" }

local PERM_SET: { [string]: boolean } = {}
for _, perm in ipairs(Staff.PERMS) do
	assert(not PERM_SET[perm], "Staff.PERMS: doppeltes Recht " .. perm)
	PERM_SET[perm] = true
end
for perm in pairs(LOCKED) do
	assert(PERM_SET[perm], "Staff.LOCKED_OWNER: unbekanntes Recht " .. perm)
end

local REASON_SET: { [string]: boolean } = {}
for _, reason in ipairs(Staff.REPORT_REASONS) do
	REASON_SET[reason] = true
end

local BY_ALIAS: { [string]: Command } = {}
local function registerName(name: string, def: Command)
	assert(string.match(name, "^%l+$") ~= nil and #name <= 12, "Staff.COMMANDS: nur Kleinbuchstaben ≤ 12: " .. name)
	assert(BY_ALIAS[name] == nil, "Staff.COMMANDS: doppelter Name/Alias " .. name)
	assert(not Staff.RESERVED[name], "Staff.COMMANDS: reservierter Roblox-Alias " .. name)
	BY_ALIAS[name] = def
end
for _, def in ipairs(Staff.COMMANDS) do
	registerName(def.Name, def)
	if def.Alias ~= nil then
		registerName(def.Alias, def)
	end
end

-- /event: jeder Name (auch Alias) -> { Spec, Key } (Key = Name der Tabelle, auf die der Alias zeigt)
local EVENT_BY: { [string]: { Spec: EventSpec, Key: string } } = {}
local EVENT_KEYS: { string } = {}
for name, value in pairs(Staff.EVENTS) do
	local key = name
	local spec = value
	if type(spec) == "string" then
		key = spec
		spec = Staff.EVENTS[spec]
	end
	assert(type(spec) == "table", "Staff.EVENTS: Alias zeigt ins Leere: " .. tostring(name))
	EVENT_BY[name] = { Spec = spec :: EventSpec, Key = key }
	if type(value) == "table" then
		table.insert(EVENT_KEYS, name)
	end
end
table.sort(EVENT_KEYS)

-- =====================================================================
-- KLEINE HELFER
-- =====================================================================
local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isInt(value: any): boolean
	return isFinite(value) and value % 1 == 0
end

local function trim(text: string): string
	return string.match(text, "^%s*(.-)%s*$") or ""
end

local function textOk(value: any, minBytes: number, maxBytes: number): boolean
	return type(value) == "string" and #value >= minBytes and #value <= maxBytes and utf8.len(value) ~= nil
end

local function permsOf(cfg: any): any
	if type(cfg) == "table" and type(cfg.Perms) == "table" then
		return cfg.Perms
	end
	return nil
end

-- =====================================================================
-- RÄNGE & RECHTE
-- =====================================================================
function Staff.Rank(role: string?): number
	if type(role) ~= "string" then
		return 0
	end
	return RANK[role] or 0
end

-- rank(role) >= rank(cfg.Perms[perm]). Gesperrte Rechte: nur Owner. ManageMods: Owner immer, sonst nur mit
-- cfg.AdminCanManageMods. Fehlt das Recht in cfg -> nur Owner (sicherer Standard).
function Staff.Can(role: string?, perm: string, cfg: any): boolean
	if type(perm) ~= "string" or not PERM_SET[perm] then
		return false
	end
	local rank = Staff.Rank(role)
	if rank <= 0 then
		return false
	end
	if rank >= OWNER_RANK then
		return true
	end
	if LOCKED[perm] then
		return false
	end
	if perm == "ManageMods" and not (type(cfg) == "table" and cfg.AdminCanManageMods == true) then
		return false
	end
	local perms = permsOf(cfg)
	local min = if perms ~= nil then perms[perm] else nil
	local need = if type(min) == "string" and RANK[min] then RANK[min] else OWNER_RANK
	return rank >= need
end

function Staff.CanAny(role: string?, perms: { string }, cfg: any): boolean
	if type(perms) ~= "table" then
		return false
	end
	for _, perm in ipairs(perms) do
		if Staff.Can(role, perm, cfg) then
			return true
		end
	end
	return false
end

function Staff.CanActOn(actorRank: number, targetRank: number): boolean
	return isFinite(actorRank) and isFinite(targetRank) and actorRank > targetRank
end

-- newRole "Admin" | "Moderator" | nil/"" (= entfernen). Fehler = Lang-Schlüssel. Selbst-Änderung prüft der Aufrufer.
function Staff.CanSetRole(
	actorRole: string?,
	targetRank: number,
	targetIsOwner: boolean,
	newRole: string?,
	cfg: any
): (boolean, string?)
	local role: string? = if newRole == "" then nil else newRole
	if role ~= nil and role ~= "Admin" and role ~= "Moderator" then
		return false, "admin.role.badRole"
	end
	local current = if isFinite(targetRank) then targetRank else OWNER_RANK -- unbekannt = geschützt
	if targetIsOwner == true or current >= OWNER_RANK then
		return false, "admin.role.owner"
	end
	if role == "Admin" and not Staff.Can(actorRole, "ManageAdmins", cfg) then
		return false, "admin.role.cantGrant"
	end
	if role == "Moderator" and not Staff.Can(actorRole, "ManageMods", cfg) then
		return false, "admin.role.cantGrant"
	end
	if role == nil and not Staff.Can(actorRole, "ManageMods", cfg) then
		return false, "admin.role.cantRemove"
	end
	-- Ziel ändern/entfernen: nur niedrigere Ränge; ein Admin-Ziel braucht ManageAdmins
	if current >= Staff.Rank(actorRole) then
		return false, "admin.role.cantRemove"
	end
	if current >= RANK.Admin and not Staff.Can(actorRole, "ManageAdmins", cfg) then
		return false, "admin.role.cantRemove"
	end
	return true, nil
end

-- W26: Unban-Recht hebt jede Sperre auf; UnbanOwn nur eigene Zeit-Banns (entry.By == actorUserId, Until ~= -1).
function Staff.CanUnban(actorRole: string?, actorUserId: number, entry: any, cfg: any): (boolean, string?)
	if Staff.Can(actorRole, "Unban", cfg) then
		return true, nil
	end
	if Staff.Can(actorRole, "UnbanOwn", cfg) then
		if
			type(entry) == "table"
			and isInt(actorUserId)
			and isInt(entry.By)
			and entry.By == actorUserId
			and isFinite(entry.Until)
			and entry.Until ~= -1
		then
			return true, nil
		end
		return false, "admin.bans.modOwnOnly"
	end
	return false, "admin.cmd.denied"
end

-- §16.2 Nr. 5: Unmute/Unfreeze nicht für sich selbst (außer Owner) und nur mit Rang ≥ dem des Bestrafenden.
-- Unbekannter Bestrafender (kein Rang übergeben) zählt als Spieler (0).
function Staff.CanUndo(actorRank: number, punisherRank: number, isSelf: boolean, actorIsOwner: boolean): boolean
	if actorIsOwner == true then
		return true
	end
	if isSelf == true or not isFinite(actorRank) then
		return false
	end
	local punisher = if isFinite(punisherRank) then punisherRank else 0
	return actorRank >= punisher
end

-- Owner > max(gespeicherte Rolle, Gruppen-Rolle). Group.Id 0 = Gruppe aus (GroupRank wird ignoriert).
function Staff.ResolveRole(info: any): string?
	if type(info) ~= "table" then
		return nil
	end
	if info.IsOwner == true then
		return "Owner"
	end
	local best = 0
	if info.Stored == "Admin" or info.Stored == "Moderator" then
		best = RANK[info.Stored]
	end
	local group = info.Group
	local groupRank = info.GroupRank
	if type(group) == "table" and isFinite(group.Id) and group.Id > 0 and isFinite(groupRank) and groupRank >= 1 then
		if isFinite(group.AdminRank) and group.AdminRank >= 1 and groupRank >= group.AdminRank then
			best = math.max(best, RANK.Admin)
		elseif isFinite(group.ModeratorRank) and group.ModeratorRank >= 1 and groupRank >= group.ModeratorRank then
			best = math.max(best, RANK.Moderator)
		end
	end
	return ROLE_BY_RANK[best]
end

-- =====================================================================
-- PARSER
-- =====================================================================
local PERMANENT: { [string]: boolean } =
	{ perm = true, permanent = true, forever = true, dauerhaft = true, p = true, ["-1"] = true }
local DURATION_UNITS: { [string]: number } = {
	s = 1,
	m = 60,
	min = 60,
	h = 3600,
	std = 3600,
	d = 86400,
	tag = 86400,
	tage = 86400,
	w = 604800,
}

-- Sekunden; -1 = dauerhaft. Ohne Einheit -> plainUnit (Standard 60 = Minuten). 0 oder > 10 Jahre -> nil.
function Staff.ParseDuration(text: any, plainUnit: number?): number?
	if type(text) ~= "string" or #text > 32 then
		return nil
	end
	local clean = string.lower(trim(text))
	if PERMANENT[clean] then
		return -1
	end
	local digits, unit = string.match(clean, "^(%d+)%s*(%a*)$")
	if digits == nil or unit == nil or #digits > 12 then
		return nil
	end
	local mult: number?
	if unit == "" then
		mult = if isFinite(plainUnit) and (plainUnit :: number) > 0 then plainUnit else 60
	else
		mult = DURATION_UNITS[unit]
	end
	if mult == nil then
		return nil
	end
	local seconds = math.floor((tonumber(digits) or 0) * mult)
	if seconds <= 0 or seconds > MAX_DURATION then
		return nil
	end
	return seconds
end

local AMOUNT_UNITS: { [string]: number } = { [""] = 1, k = 1e3, m = 1e6, mio = 1e6, b = 1e9, mrd = 1e9, t = 1e12 }

-- Ganzzahl (zur Null hin abgeschnitten), |x| ≤ 1e15, negativ erlaubt (Recht prüft der Aufrufer).
-- Trennzeichen: ein "," oder "." = Dezimalzeichen (1,5m = 1.5m) – außer ohne Einheit mit genau 3 Ziffern danach
-- (1.500 / 1,500 = 1500); mehrere gleiche = Tausender (1.000.000), dann je genau 3 Ziffern.
function Staff.ParseAmount(text: any): number?
	if type(text) == "number" then
		if not isFinite(text) or math.abs(text) > MAX_AMOUNT then
			return nil
		end
		local whole = if text >= 0 then math.floor(text) else -math.floor(-text)
		return if whole == 0 then 0 else whole
	end
	if type(text) ~= "string" or #text > 40 then
		return nil
	end
	local sign, body, unit = string.match(string.lower(trim(text)), "^([+-]?)([%d.,]+)%s*(%a*)$")
	if sign == nil or body == nil or unit == nil then
		return nil
	end
	local mult = AMOUNT_UNITS[unit]
	if mult == nil then
		return nil
	end
	local intPart, fracPart = body, ""
	local _, separators = string.gsub(body, "[.,]", "")
	if separators == 1 then
		local a, b = string.match(body, "^(%d*)[.,](%d*)$")
		if a == nil or b == nil then
			return nil
		end
		if unit == "" and #a >= 1 and #a <= 3 and #b == 3 then
			intPart, fracPart = a .. b, "" -- Tausender-Trennzeichen
		else
			intPart, fracPart = a, b
		end
	elseif separators > 1 then
		local sepChar = string.match(body, "[.,]") :: string
		if string.find(body, if sepChar == "." then "," else ".", 1, true) then
			return nil -- gemischte Trennzeichen
		end
		local groups = string.split(body, sepChar)
		for index, group in ipairs(groups) do
			local pattern = if index == 1 then "^%d%d?%d?$" else "^%d%d%d$"
			if string.match(group, pattern) == nil then
				return nil
			end
		end
		intPart = table.concat(groups)
	end
	if intPart == "" and fracPart == "" then
		return nil
	end
	if #intPart > 16 then
		return nil
	end
	if #intPart + #fracPart > 15 then
		fracPart = string.sub(fracPart, 1, math.max(0, 15 - #intPart))
	end
	-- exakt rechnen: 1.15k = 115 × 1000 / 100 (statt 1.15 × 1000 = 1149,999…)
	local mantissa = tonumber(intPart .. fracPart) or 0
	local value = math.floor(mantissa * mult / (10 ^ #fracPart))
	if not isFinite(value) or value > MAX_AMOUNT then
		return nil
	end
	if sign == "-" and value ~= 0 then
		return -value
	end
	return value
end

function Staff.Tokenize(text: any): { string }
	local tokens: { string } = {}
	if type(text) ~= "string" then
		return tokens
	end
	for token in string.gmatch(text, "%S+") do
		if #tokens >= MAX_TOKENS then
			break
		end
		table.insert(tokens, string.sub(token, 1, MAX_TOKEN_BYTES))
	end
	return tokens
end

-- raw ≤ 300 Byte (länger = abgeschnitten), getrimmt; prefix = "/" oder ";" (erstes Zeichen) sonst nil;
-- name = erstes Wort direkt hinter dem Präfix (klein); def nur mit Präfix. args = restliche Wörter.
function Staff.ParseCommand(raw: any): (Command?, { string }, string?, string?)
	if type(raw) ~= "string" then
		return nil, {}, nil, nil
	end
	local text = trim(string.sub(raw, 1, MAX_COMMAND_BYTES))
	local first = string.sub(text, 1, 1)
	local prefix: string? = if first == "/" or first == ";" then first else nil
	local body = if prefix ~= nil then string.sub(text, 2) else text
	local tokens = Staff.Tokenize(body)
	local name: string? = nil
	if #tokens > 0 and string.match(body, "^%s") == nil then
		name = string.lower(tokens[1])
	end
	local args: { string } = {}
	for i = 2, #tokens do
		table.insert(args, tokens[i])
	end
	local def = if prefix ~= nil and name ~= nil then BY_ALIAS[name] else nil
	return def, args, prefix, name
end

-- Nur bekannte Befehle direkt hinter dem Präfix zählen (";)" oder ";hallo" bleiben normaler Chat).
-- prefix nil = "/" oder ";".
function Staff.IsCommandText(text: any, prefix: string?): boolean
	if type(text) ~= "string" then
		return false
	end
	local first = string.sub(text, 1, 1)
	if prefix ~= nil then
		if first ~= prefix then
			return false
		end
	elseif first ~= "/" and first ~= ";" then
		return false
	end
	local name = string.match(text, "^.(%a+)")
	if name == nil or #name > 12 then
		return false
	end
	local after = string.sub(text, 2 + #name, 2 + #name)
	if after ~= "" and string.match(after, "%s") == nil then
		return false
	end
	return BY_ALIAS[string.lower(name)] ~= nil
end

-- =====================================================================
-- ZIELE ("me", "all", "others", "a,b,c", "@Anzeigename", UserId, Name)
-- =====================================================================
local function lowerField(p: any, field: string): string
	local value = p[field]
	return if type(value) == "string" then string.lower(value) else ""
end

local function ambiguous(text: string, list: { any }): (any, string?, string?)
	local names: { string } = {}
	for i = 1, math.min(#list, MAX_AMBIGUOUS_NAMES) do
		table.insert(names, tostring(list[i].Name))
	end
	return nil, "admin.cmd.ambiguous", text .. "|" .. table.concat(names, ", ")
end

-- Eindeutiger Treffer aus einer Liste: 1 -> Spieler, > 1 -> mehrdeutig, 0 -> nil ohne Fehler
local function pick(text: string, list: { any }): (any, string?, string?)
	if #list == 1 then
		return list[1], nil, nil
	elseif #list > 1 then
		return ambiguous(text, list)
	end
	return nil, nil, nil
end

local function collect(players: { any }, test: (any) -> boolean): { any }
	local list: { any } = {}
	for _, p in ipairs(players) do
		if test(p) then
			table.insert(list, p)
		end
	end
	return list
end

-- Ein einzelnes Ziel (keine Liste, kein all/others)
local function matchOne(text: string, players: { any }, actor: any): (any, string?, string?)
	local lower = string.lower(text)
	if lower == "" or lower == "me" then
		if actor == nil then
			return nil, "admin.cmd.noTarget", text
		end
		return actor, nil, nil
	end
	if string.sub(lower, 1, 1) == "@" then
		local want = string.sub(lower, 2)
		if want ~= "" then
			local found, key, arg = pick(
				text,
				collect(players, function(p: any): boolean
					return lowerField(p, "DisplayName") == want
				end)
			)
			if found ~= nil or key ~= nil then
				return found, key, arg
			end
			found, key, arg = pick(
				text,
				collect(players, function(p: any): boolean
					return string.sub(lowerField(p, "DisplayName"), 1, #want) == want
				end)
			)
			if found ~= nil or key ~= nil then
				return found, key, arg
			end
		end
		return nil, "admin.cmd.noTarget", text
	end
	if string.match(lower, "^%d+$") then
		-- Ziffern = nur UserId (nie Namens-Präfix: "/ban 1234" darf keinen Spieler "1234abc" treffen)
		local userId = tonumber(lower)
		for _, p in ipairs(players) do
			if p.UserId == userId then
				return p, nil, nil
			end
		end
		return nil, "admin.cmd.noTarget", text
	end
	for _, p in ipairs(players) do
		if lowerField(p, "Name") == lower then
			return p, nil, nil
		end
	end
	local tests: { (any) -> boolean } = {
		function(p: any): boolean
			return lowerField(p, "DisplayName") == lower
		end,
		function(p: any): boolean
			return string.sub(lowerField(p, "Name"), 1, #lower) == lower
		end,
		function(p: any): boolean
			return string.sub(lowerField(p, "DisplayName"), 1, #lower) == lower
		end,
	}
	for _, test in ipairs(tests) do
		local found, key, arg = pick(text, collect(players, test))
		if found ~= nil or key ~= nil then
			return found, key, arg
		end
	end
	return nil, "admin.cmd.noTarget", text
end

-- players: Liste mit { Name, DisplayName, UserId } (Player-Instanzen gehen). Rückgabe (Liste, errKey, errArg);
-- mehrdeutig: errArg = "<Text>|<Namen ≤ 5>" (für admin.cmd.ambiguous an "|" teilen).
function Staff.MatchTargets(text: any, players: { any }, actor: any): ({ any }, string?, string?)
	local pool: { any } = if type(players) == "table" then players else {}
	local raw: string
	if type(text) == "string" then
		raw = text
	elseif isInt(text) and math.abs(text) < 2 ^ 53 then
		raw = string.format("%d", text)
	else
		raw = ""
	end
	local clean = trim(string.sub(raw, 1, MAX_TARGET_BYTES))
	local lower = string.lower(clean)
	if lower == "all" or lower == "others" then
		local list: { any } = {}
		for _, p in ipairs(pool) do
			if lower == "all" or p ~= actor then
				table.insert(list, p)
			end
		end
		return list, nil, nil
	end
	if string.find(clean, ",", 1, true) then
		local list: { any } = {}
		local seen: { [any]: boolean } = {}
		local parts = 0
		for part in string.gmatch(clean, "[^,]+") do
			local piece = trim(part)
			if piece ~= "" then
				parts += 1
				local pieceLower = string.lower(piece)
				if parts > MAX_LIST_PARTS then
					return {}, "admin.cmd.noTarget", clean
				end
				if pieceLower == "all" or pieceLower == "others" then
					return {}, "admin.cmd.noTarget", piece -- Masse nie über Listen (MassTarget-Gate)
				end
				local found, key, arg = matchOne(piece, pool, actor)
				if found == nil then
					return {}, key or "admin.cmd.noTarget", arg or piece
				end
				if not seen[found] then
					seen[found] = true
					table.insert(list, found)
				end
			end
		end
		if #list == 0 then
			return {}, "admin.cmd.noTarget", clean
		end
		return list, nil, nil
	end
	local found, key, arg = matchOne(clean, pool, actor)
	if found == nil then
		return {}, key or "admin.cmd.noTarget", arg or clean
	end
	return { found }, nil, nil
end

function Staff.IsMass(text: any): boolean
	if type(text) ~= "string" then
		return false
	end
	local lower = string.lower(trim(string.sub(text, 1, MAX_TARGET_BYTES)))
	return lower == "all" or lower == "others"
end

local REASON_WORDS: { [string]: string } = {
	speed = "Speed",
	tempo = "Speed",
	schnell = "Speed",
	fly = "Fly",
	fliegen = "Fly",
	flug = "Fly",
	flying = "Fly",
	exploit = "Exploit",
	hack = "Exploit",
	hacker = "Exploit",
	cheat = "Exploit",
	cheater = "Exploit",
	cheats = "Exploit",
	toxic = "Toxic",
	beleidigung = "Toxic",
	beleidigt = "Toxic",
	insult = "Toxic",
	spam = "Toxic",
	mobbing = "Toxic",
	bully = "Toxic",
	rude = "Toxic",
}

function Staff.ReasonFromText(word: any): string
	if type(word) ~= "string" then
		return "Other"
	end
	return REASON_WORDS[string.lower(trim(string.sub(word, 1, 40)))] or "Other"
end

-- =====================================================================
-- CHAT-ZUSTELLUNG (läuft im ShouldDeliverCallback: nie yielden, nie werfen)
-- =====================================================================
-- System (kein Absender) -> true; stumm (Until == -1 oder > Now) -> false; ";befehl" -> nur an den Absender selbst;
-- persönlich stummgeschaltet (Personal[Empfänger][Absender]) -> false; sonst true.
function Staff.ShouldDeliver(info: any): boolean
	if type(info) ~= "table" then
		return true
	end
	local sender = info.SenderId
	if type(sender) ~= "number" then
		return true
	end
	local muted = info.MutedUntil
	if type(muted) == "table" then
		local untilT = muted[sender]
		if type(untilT) == "number" and (untilT == -1 or not isFinite(info.Now) or untilT > info.Now) then
			return false
		end
	end
	if info.RecipientId ~= sender and Staff.IsCommandText(info.Text, ";") then
		return false
	end
	local personal = info.Personal
	if type(personal) == "table" then
		local list = personal[info.RecipientId]
		if type(list) == "table" and list[sender] then
			return false
		end
	end
	return true
end

-- =====================================================================
-- MESSAGINGSERVICE "AT_Staff" – nur bekannte Felder kopieren, alles andere -> nil (verworfen)
-- =====================================================================
local MSG_ROLES: { [string]: boolean } = { Admin = true, Moderator = true, [""] = true }

function Staff.ValidateMsg(msg: any, now: number): { [string]: any }?
	if type(msg) ~= "table" or not textOk(msg.Id, 4, 64) or not isFinite(now) then
		return nil
	end
	local kind = msg.Kind
	if kind == "Role" then
		if not (isInt(msg.UserId) and msg.UserId >= 1 and msg.UserId < 2 ^ 53) then
			return nil
		end
		if type(msg.Role) ~= "string" or not MSG_ROLES[msg.Role] then
			return nil
		end
		if not (isInt(msg.Rev) and msg.Rev >= 0 and msg.Rev < 2 ^ 53) then
			return nil
		end
		if not (isInt(msg.By) and math.abs(msg.By) < 2 ^ 53) then
			return nil
		end
		return { Kind = "Role", Id = msg.Id, UserId = msg.UserId, Role = msg.Role, Rev = msg.Rev, By = msg.By }
	elseif kind == "Kick" then
		if not (isInt(msg.UserId) and msg.UserId >= 1 and msg.UserId < 2 ^ 53) then
			return nil
		end
		if not textOk(msg.Reason, 0, 400) then
			return nil
		end
		local untilT = msg.Until
		if not (isInt(untilT) and (untilT == -1 or (untilT >= 1 and untilT <= now + TEN_YEARS))) then
			return nil
		end
		return { Kind = "Kick", Id = msg.Id, UserId = msg.UserId, Reason = msg.Reason, Until = untilT }
	elseif kind == "Report" then
		if not textOk(msg.FromName, 1, 20) or not textOk(msg.TargetName, 1, 20) then
			return nil
		end
		if type(msg.Reason) ~= "string" or not REASON_SET[msg.Reason] then
			return nil
		end
		return {
			Kind = "Report",
			Id = msg.Id,
			FromName = msg.FromName,
			TargetName = msg.TargetName,
			Reason = msg.Reason,
		}
	end
	return nil
end

-- =====================================================================
-- CONFIG-PRÜFUNG (Security.Validate setzt "Config.Security.Staff." davor)
-- =====================================================================
function Staff.CheckPerms(perms: any, eventPerms: any): { string }
	local problems: { string } = {}
	if type(perms) ~= "table" then
		table.insert(problems, "Perms: Tabelle Recht -> Rolle erwartet")
	else
		local unknown: { string } = {}
		for name in pairs(perms) do
			if type(name) ~= "string" or not PERM_SET[name] then
				table.insert(unknown, tostring(name))
			end
		end
		table.sort(unknown)
		for _, name in ipairs(unknown) do
			table.insert(problems, ("Perms.%s: unbekanntes Recht"):format(name))
		end
		for _, perm in ipairs(Staff.PERMS) do
			local value = perms[perm]
			if value == nil then
				table.insert(problems, ("Perms.%s: fehlt"):format(perm))
			elseif type(value) ~= "string" or not RANK[value] then
				table.insert(problems, ('Perms.%s: "Moderator", "Admin" oder "Owner" erwartet'):format(perm))
			elseif LOCKED[perm] and value ~= "Owner" then
				table.insert(problems, ('Perms.%s: gesperrt – muss "Owner" bleiben'):format(perm))
			end
		end
	end
	if type(eventPerms) ~= "table" then
		table.insert(problems, "EventPerms: Tabelle Event -> Recht erwartet")
	else
		local bad: { string } = {}
		for key, value in pairs(eventPerms) do
			if type(key) ~= "string" or type(value) ~= "string" or not PERM_SET[value] then
				table.insert(bad, tostring(key))
			end
		end
		table.sort(bad)
		for _, key in ipairs(bad) do
			table.insert(problems, ("EventPerms.%s: unbekanntes Recht"):format(key))
		end
	end
	return problems
end

-- =====================================================================
-- BEFEHLE & EVENTS
-- =====================================================================
function Staff.CommandByName(name: any): Command?
	if type(name) ~= "string" then
		return nil
	end
	return BY_ALIAS[string.lower(name)]
end

function Staff.VisibleCommand(def: any, role: string?, cfg: any): boolean
	if type(def) ~= "table" then
		return false
	end
	if def.Perm == "" or def.Personal == true then
		return true
	end
	if type(def.Perm) == "string" and Staff.Can(role, def.Perm, cfg) then
		return true
	end
	return type(def.AnyPerm) == "table" and Staff.CanAny(role, def.AnyPerm, cfg)
end

-- /event-Name (auch Alias, Groß/klein egal) -> (Spec, Name der Haupt-Tabelle); unbekannt -> nil
function Staff.EventSpec(name: any): (EventSpec?, string?)
	if type(name) ~= "string" then
		return nil, nil
	end
	local entry = EVENT_BY[string.lower(trim(string.sub(name, 1, 40)))]
	if entry == nil then
		return nil, nil
	end
	return entry.Spec, entry.Key
end

-- Haupt-Namen (ohne Aliase), alphabetisch – Kopie
function Staff.EventNames(): { string }
	return table.clone(EVENT_KEYS)
end

return Staff
