-- =====================================================================
--  AKYTEX TYCOON – Admin-Panel, Server-Seite (Server/Services/AdminService)
--  Besitzer: WP11 (Admin, Events, Anti-Cheat). Vertrag: DESIGN.md §B15 (Zugriff, 11 Tabs, Admin-Abuse-Katalog),
--  §C5.10, §C8 (Remote "Admin"), §C11.2 (Admin-Insider: Besitzer-Trades ±120 s), §C13 (AT_Mod_v1, AT_Global, AT_Live_v1,
--  AT_Stats_v1, AT_Heartbeat, Messaging "AT_Global"). Basis: CLUTCH-CLASH-AdminService (REUSE §3.13 ADAPT): Owner-Regel,
--  Cache + Attribut IsAdmin, Rate-Limit VOR der Prüfung, Ablehnung 1× geloggt, dispatch mit p.Parent-Guard, Ziele
--  (me/all/others/Name/Präfix/UserId), Bann-Regeln, Ansage (gefiltert), publishGlobal/handleGlobal mit oberer Zeitgrenze
--  und Dedupe. Shooter-Teile sind entfernt; Markt-Aktionen laufen NUR über MarketService.Admin (GlobalBus, Admin-Fenster).
--
--  BESITZER = ROLLE OWNER (§B15.1, Regel unverändert):
--    Live, Nutzer-Spiel:   game.CreatorType == User and p.UserId == game.CreatorId and game.CreatorId ~= 0
--    Live, Gruppen-Spiel:  GroupService:GetGroupInfoAsync(game.CreatorId).Owner.Id == p.UserId (pcall, 10 min Cache,
--                          Fehler = kein Besitzer, nur 30 s gecacht)
--    Studio:               Config.Admin.StudioIsAdmin and (UserId > 0 or UserId == -1); Player2 (-2) NIE.
--  IsAdmin / Attribut IsAdmin = NUR der Besitzer (MarketService, OrderService, OwnerTradeBlocked, PlotService fragen das).
--  TEAM-ROLLEN (W19/W26): Admin und Moderator kommen von StaffService (gespeichert, Gruppen-Rang); Rollen kann man NIE
--  kaufen. JEDE Aktion – Panel und Chat – läuft durch AdminService.Run: Rang ≥ 1 -> Core.PermFor(Aktion, args) -> Recht
--  aus Config.Security.Staff.Perms (Shared/Staff.Can) -> Besitzer bekannt? (strafende Rechte) -> Abstand schwerer
--  Lese-Aktionen -> Aktion. Fehlt StaffService, gilt die alte Regel: nur der Besitzer (Rolle Owner).
--  Rang-Regel: strafende Aktionen nur gegen niedrigere Ränge (Kick, Bann, Stumm, Verwarnen, Einfrieren, Herholen,
--  Respawn, Zuschauen, TpTo, CR abziehen); Aufheben (Unfreeze/Unmute) nach Staff.CanUndo; Listen mit > 3 Zielen = Masse.
--
--  Remote "Admin": (action, args) -> { Ok, Message, Data }  – Reihenfolge: p.Parent -> Rate 12/s -> Run (Rang, Recht,
--  Besitzer bekannt, Schwer-Abstand) -> Aktion. Chat-Befehle (StaffService) rufen Run(p, action, args, "Chat").
--  Jede Aktion -> Admin-Log (AT_Mod_v1 "AdminLog", letzte 500, Kopie AT_Global "AdminLog_W<w>") mit Via/Role/Target.
--  Markt-Aktionen: MarketService.Admin (3 s Abklingzeit dort), Besitzer hat in den letzten 120 s gehandelt -> abgelehnt;
--  danach sind Besitzer-Trades bis 120 s nach dem Event-Start gesperrt (OwnerTradeBlocked, OrderService fragt).
--  Globale Nachrichten (MessagingService Config.Tech.MessagingTopic, Sender empfängt selbst): Announce {Text, UserId,
--  Name, Id}, AdminAbuse {Event, Args, StartAt, Until, Id, By}, Live {Version, Id}. Jedes Feld geprüft,
--  Until ≤ now + Config.Events.MaxGlobalSeconds, Dedupe per Id (letzte 200). Fehler beim Senden -> nur dieser Server.
--
--  Öffentliche API (§C5.10):
--    AdminService.IsAdmin(p): boolean  (= Besitzer)   AdminService.Power(p, name): any   (nil ohne das Recht der Kraft)
--    AdminService.IsServerLocked(): boolean           AdminService.OwnerTradeBlocked(p): boolean   (±120 s)
--  Ergänzungen (WP11-intern, W19/W26):
--    AdminService.Run(p, action, args, via?): (ok, message?, data?)   einziges Tor für Panel ("Panel") und Chat ("Chat")
--    AdminService.IsOwnerId(userId): boolean          AdminService.OwnerKnown(): boolean   (Gruppen-Besitzer geladen?)
--    AdminService.SyncPowers(p)                       Kräfte-Attribute ohne passendes Recht löschen (StaffService.Refresh)
--    AdminService.PublishAbuse(kind, args, by): (boolean, "global" | "local")   globales Nicht-Markt-Event senden
--    AdminService.Core: { OwnerRule, MarketArgs, ValidateGlobal, NewDedupe, TradeBlocked, TradeLockBefore, PermFor,
--      ActionNames, IsMassList, OwnerBlocks, GapOk, GiftTargets, CreditCaps, HEAVY, PUNITIVE }  (rein, AdminTests/StaffTests)
-- =====================================================================

local DataStoreService = game:GetService("DataStoreService")
local GroupService = game:GetService("GroupService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Lang = require(Shared:WaitForChild("Lang"))
local Types = require(Shared:WaitForChild("Types"))
local Util = require(Shared:WaitForChild("Util"))
local Clock = require(Shared:WaitForChild("Clock"))
local Format = require(Shared:WaitForChild("Format"))
local Staff = require(Shared:WaitForChild("Staff"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local AdminService = {}
local Services: any = nil

type Plain = { [string]: any }
-- ctx (von Run): { Via = "Panel" | "Chat", Target = Log-Ziel (die Aktion darf es genauer setzen) }
type Ctx = { Via: string, Target: string? }
type Action = (admin: Player, args: Plain, ctx: Ctx) -> (boolean, string, any?)

local SEC: any = Config.Security
local STAFF: any = if type(SEC.Staff) == "table" then SEC.Staff else {}
local EV: any = Config.Events
local MAX_NAME = 40
local MAX_REASON = 200
local MAX_LIST = 100
local MAX_ACTION_LEN = 40
local MAX_GIVE_CREDITS = 1e12
local MAX_GIVE_AKY = 1e9 -- ganze AKY je Gabe (× 100 = Cent)
local LOG_FLUSH_SECONDS = 60
local LOG_MSG_MAX = 140
local HEARTBEAT_SECONDS = 30
local HEARTBEAT_TTL = 60
local HEARTBEAT_CACHE = 30
local STATS_SAMPLE_SECONDS = 30
local LIVE_KEY = "Live"
local LIVE_RELOAD_GAP = 2
local MARKET_TRADE_WINDOW = 60 -- Sekunden, über die "Fills/min" gezählt wird
local MAX_TRADED_KEYS = 64
local MAX_OWNER_EVENTS = 16
local BANNER_MAX = 120
local MAINTENANCE_ATTR = "AT_Maintenance"
-- Speed-Geschenk (Wunsch 18): Spieler-Attribute, die NUR der Server setzt (AntiCheatService liest sie mit)
local GIFT_SPEED = "GiftSpeed"
local GIFT_JUMP = "GiftJump"
local GIFT_UNTIL = "GiftUntil"
local DEFAULT_JUMP = 7.2
local MASS_LIST = 3 -- Komma-Listen mit mehr aufgelösten Zielen gelten als Masse (§16.2 Nr. 8)
local DENIED_LOG_GAP = 60 -- Teammitglieder: Ablehnung je Aktion höchstens 1× pro Minute ins Log
local GROUP_FAIL_CACHE = 30 -- Gruppen-Besitzer: Fehlschlag nur so lange cachen (§16.2 Nr. 1)
local UNBAN_NAME_MIN, UNBAN_NAME_MAX = 3, 20 -- Roblox-Benutzernamen

-- Kräfte (§B15.2 "Kräfte"): "bool" = an/aus, sonst { Min, Max } aus Config.Security.Powers
local POWERS: { [string]: string } = {
	CanFly = "bool",
	AdminNoclip = "bool",
	AdminSpeed = "Speed",
	AdminJump = "Jump",
	AdminInvisible = "bool",
	AdminESP = "bool",
}
-- Kraft -> Recht (Shared/Staff.PERMS): ohne das Recht wird das Attribut gelöscht (SyncPowers) und nie geehrt (Power)
local POWER_PERM: { [string]: string } = {
	CanFly = "Fly",
	AdminNoclip = "Noclip",
	AdminSpeed = "GiveSpeed",
	AdminJump = "GiveSpeed",
	AdminInvisible = "Invisible",
	AdminESP = "Esp",
}

-- Aktionen, die nicht ins Output geloggt werden (Abfragen; F8-Anzeige pollt jede Sekunde)
local QUIET: { [string]: boolean } = {
	GetPlayers = true,
	ServerInfo = true,
	Dashboard = true,
	Stats = true,
	Flags = true,
	Reports = true,
	BanList = true,
	BanHistory = true,
	PlayerData = true,
	Receipts = true,
	AdminLog = true,
	LiveGet = true,
	MarketLog = true,
	StaffList = true,
	Bans = true,
}

-- Schwere Lese-Aktionen (§16.2 Nr. 7): je (Handelnder, Aktion) höchstens ein Aufruf je STAFF.HeavyGap Sekunden
local HEAVY: { [string]: boolean } = {
	Dashboard = true,
	ServerInfo = true,
	Flags = true,
	Reports = true,
	BanList = true,
	Bans = true,
	BanHistory = true,
	AdminLog = true,
	StaffList = true,
	Stats = true,
	PlayerData = true,
	Receipts = true,
	MarketLog = true,
	LiveGet = true,
}

-- Strafende Rechte: bei unbekanntem Gruppen-Besitzer nur für den Besitzer selbst (§16.2 Nr. 1)
local PUNITIVE: { [string]: boolean } = {
	Kick = true,
	TempBan = true,
	Ban = true,
	Mute = true,
	Warn = true,
	Freeze = true,
	Bring = true,
	Respawn = true,
	Spectate = true,
	ManageMods = true,
	ManageAdmins = true,
}

-- Aktion -> Recht (feste Einträge, §5.2 + §16.1); Aktionen mit Argument-abhängigem Recht stehen in Core.PermFor
local STATIC_PERMS: { [string]: string } = {
	Dashboard = "Panel",
	ServerInfo = "Panel",
	GetPlayers = "PlayerList",
	Kick = "Kick",
	Unban = "UnbanOwn", -- der Handler setzt die strengere Regel durch (Staff.CanUnban)
	Bans = "BanView",
	BanList = "Logs",
	BanHistory = "Ban",
	Warn = "Warn",
	Freeze = "Freeze",
	Bring = "Bring",
	Goto = "Teleport",
	Visit = "Teleport",
	PlayerData = "PlayerData",
	Receipts = "Purchases",
	Regrant = "Purchases",
	ResetData = "Purchases",
	GiveSpeed = "GiveSpeed",
	Spectate = "Spectate",
	GiveAllItems = "GiveItems",
	GiveAky = "GiveAky",
	SetLicence = "GiveItems",
	SetFloors = "GiveItems",
	LockServer = "LockServer",
	KickAll = "KickAll",
	Market = "MarketEvents",
	MarketLog = "MarketEvents",
	LiveGet = "LiveConfig",
	LiveSet = "LiveConfig",
	LiveBanner = "LiveConfig",
	Stats = "Stats",
	Flags = "Reports",
	DismissFlag = "Reports",
	Reports = "Reports",
	AdminLog = "Logs",
	SimulatePurchase = "Debug",
	SimulatePolicy = "Debug",
	SkipDay = "Debug",
	SetDebug = "Debug",
	RunSelfTest = "Debug",
	Mute = "Mute",
	Unmute = "Mute",
	Respawn = "Respawn",
	TpTo = "Bring",
	Shutdown = "Shutdown",
	StaffList = "TeamView",
	ResolveReport = "Reports",
}

-- Katalog-Schlüssel -> MarketService.Admin-Aktion (Types.MarketEvent.Kind)
local MARKET_ACTIONS: { [string]: string } = {
	MegaRally = "Rally",
	MegaCrash = "Crash",
	Pump = "Pump",
	Dump = "Dump",
	News = "News",
	Halt = "Halt",
	Resume = "Resume",
	Ipo = "Ipo",
	Vol = "Vol",
	Normalize = "Normalize",
}
local SECTOR_KEYS: { [string]: boolean } = { T = true, E = true, M = true, K = true, G = true, F = true }

-- ---------------------------------------------------------------------
-- ZUSTAND (Pro-Spieler-Tabellen werden bei PlayerRemoving geleert)
-- ---------------------------------------------------------------------
local rate = SEC.Rates and SEC.Rates.Admin or { 12, 1 }
local limiter = Util.RateLimiter(rate[1] or 12, rate[2] or 1)
local adminCache: { [Player]: boolean } = {}
local warnedDenied: { [Player]: boolean } = {}
local joinedAt: { [Player]: number } = {}
local invisConn: { [Player]: RBXScriptConnection } = {}
local ownerEvents: { [Player]: { { Issued: number, Start: number } } } = {}
local ownerLastTrade: { [Player]: number } = {}
local purchaseSeen: { [Player]: { Robux: number, Receipts: number } } = {}
-- Team-Rollen (W19): Ablehnungen je Aktion, Schwer-Abstand, Ansage-Abstände, Einfrierer (Undo-Regel)
local deniedAt: { [Player]: { [string]: number } } = {}
local heavyAt: { [Player]: { [string]: number } } = {}
local announceBy: { [Player]: { [string]: number } } = {} -- ["Local"] / ["Global"] = os.clock() der letzten Ansage
local frozenBy: { [Player]: number } = {}
local lookupRate = if type(STAFF.LookupLimit) == "table" then STAFF.LookupLimit else { 10, 60 }
local lookupLimiter = Util.RateLimiter(tonumber(lookupRate[1]) or 10, tonumber(lookupRate[2]) or 60)
local funEventAt: { [string]: number } = {} -- ["Server"] = os.clock() des letzten Spaß-Events (je Server)
local shuttingDown = false

local serverLocked = false
local startedAt = os.clock()
local groupOwner: { Id: number, At: number, Failed: boolean? }? = nil
local groupLoading = false
local heartbeatOff = false
local heartbeatCache: { At: number, Players: number, Servers: number }? = nil
local liveDoc: Plain = { Fields = {}, Version = 0 }
local liveReloadAt = -math.huge
local announceAt = -math.huge

local adminLog: { Plain } = {}
local logPending: { Plain } = {}
local storedLog: { List: { Plain }, At: number }? = nil
local tradeTimes: { number } = {}
local tradedCount: { [string]: number } = {}
local tradedKeys = 0
local statsPending = { Robux = 0, Count = 0 }
local statsCache: { At: number, Data: Plain }? = nil
local storeOff: { [string]: boolean } = {}

local Actions: { [string]: Action } = {}

-- =====================================================================
-- REINE KERN-FUNKTIONEN (AdminTests)
-- =====================================================================
local Core = {}

-- Besitzer-Regel (§B15.1). info = { CreatorType = "User" | "Group", CreatorId, UserId, Studio, GroupOwnerId?, Cfg }
function Core.OwnerRule(info: Plain): boolean
	local cfg: Plain = if type(info.Cfg) == "table" then info.Cfg else {}
	local userId = info.UserId
	if not Util.IsFinite(userId) or userId % 1 ~= 0 then
		return false
	end
	if userId == -2 then
		return false -- Player2 im Studio-Test: NIE Admin (Ablehnungspfad testbar)
	end
	local creatorId = info.CreatorId
	if Util.IsFinite(creatorId) and creatorId ~= 0 then
		if info.CreatorType == "User" and cfg.OwnerIsAdmin ~= false and userId == creatorId then
			return true
		end
		if info.CreatorType == "Group" and cfg.GroupOwnerIsAdmin ~= false then
			local owner = info.GroupOwnerId
			if Util.IsFinite(owner) and owner ~= 0 and owner == userId then
				return true
			end
		end
	end
	if info.Studio == true and cfg.StudioIsAdmin == true then
		if userId > 0 or userId == -1 then
			return true
		end
		return cfg.StudioAllPlayersAdmin == true and userId ~= -2
	end
	return false
end

local function clampNum(value: any, lo: number, hi: number, default: number): number
	local n = tonumber(value)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		n = default
	end
	return math.clamp(n :: number, lo, hi)
end

local function cleanText(value: any, max: number): string?
	if type(value) ~= "string" then
		return nil
	end
	local text = string.gsub(value, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	local len = utf8.len(text)
	if not len or len < 1 or len > max then
		return nil
	end
	return text
end

local function isInt(n: any): boolean
	return Util.IsFinite(n) and n % 1 == 0
end

-- Markt-Parameter klemmen (§B15.3). Gibt (Aktion für MarketService.Admin, Argumente) oder (nil, nil, Fehler-Schlüssel).
function Core.MarketArgs(kind: string, args: any, limits: Plain?): (string?, Plain?, string?)
	local action = MARKET_ACTIONS[kind]
	if not action then
		return nil, nil, "admin.evUnknown"
	end
	local raw: Plain = if type(args) == "table" then args else {}
	local lim: Plain = limits or EV.AdminLimits
	local out: Plain = {}
	local function scope(allowAll: boolean): boolean
		local s = raw.Scope
		if (s == "All" or s == nil) and allowAll then
			out.Scope = "All"
			return true
		elseif s == "Sector" then
			if type(raw.Target) ~= "string" or not SECTOR_KEYS[raw.Target] then
				return false
			end
			out.Scope = "Sector"
			out.Target = raw.Target
			return true
		elseif s == "Inst" then
			if not isInt(raw.Target) or raw.Target < 1 or raw.Target > 999 then
				return false
			end
			out.Scope = "Inst"
			out.Target = raw.Target
			return true
		end
		return false
	end
	local strength = lim.MarketStrength
	local ramp = lim.Ramp
	local decay = lim.DecayMinutes
	if action == "Crash" or action == "Rally" then
		if not scope(true) then
			return nil, nil, "admin.badScope"
		end
		out.Strength = math.floor(clampNum(raw.Strength, strength[1], strength[2], strength[1]) + 0.5)
		out.Ramp = math.floor(clampNum(raw.Ramp, ramp[1], ramp[2], ramp[1]))
		out.Decay = math.floor(clampNum(raw.Decay, decay[1], decay[2], decay[1]))
		if action == "Crash" and raw.Warn == true then
			out.Warn = true
		end
	elseif action == "Pump" or action == "Dump" then
		if not isInt(raw.Target) or raw.Target < 1 or raw.Target > 999 then
			return nil, nil, "admin.badTarget"
		end
		out.Target = raw.Target
		out.Strength = math.floor(clampNum(raw.Strength, strength[1], strength[2], strength[1]) + 0.5)
		out.Ramp = math.floor(clampNum(raw.Ramp, ramp[1], ramp[2], ramp[1]))
		out.Decay = math.floor(clampNum(raw.Decay, decay[1], decay[2], decay[1]))
	elseif action == "News" then
		if raw.Scope ~= "Inst" and raw.Scope ~= "Sector" then
			return nil, nil, "admin.badScope"
		end
		if not scope(false) then
			return nil, nil, "admin.badScope"
		end
		local band = lim.NewsBand
		out.Band = math.floor(clampNum(raw.Band, band[1], band[2], 2))
		out.Dir = if tonumber(raw.Dir) and (tonumber(raw.Dir) :: number) < 0 then -1 else 1
		local maxChars = math.floor(tonumber(lim.NewsChars) or 80)
		local text = raw.Text
		if type(text) ~= "table" then
			return nil, nil, "admin.newsText"
		end
		local de = cleanText(text.de, maxChars)
		local en = cleanText(text.en, maxChars) or de
		if not de or not en then
			return nil, nil, "admin.newsText"
		end
		out.Text = { de = de, en = en }
	elseif action == "Halt" then
		if raw.Scope == "Inst" then
			if not scope(false) then
				return nil, nil, "admin.badTarget"
			end
		else
			out.Scope = "All"
		end
		local r = lim.HaltSeconds
		out.Seconds = math.floor(clampNum(raw.Seconds, r[1], r[2], 60))
	elseif action == "Resume" then
		if raw.Scope == "Inst" and isInt(raw.Target) then
			out.Scope = "Inst"
			out.Target = raw.Target
		else
			out.Scope = "All"
		end
	elseif action == "Ipo" then
		if not isInt(raw.Target) or raw.Target < 1 or raw.Target > 999 then
			return nil, nil, "admin.badTarget"
		end
		out.Target = raw.Target
	elseif action == "Vol" then
		local v, m = lim.Vol, lim.VolMinutes
		out.Strength = math.floor(clampNum(raw.Strength, v[1], v[2], 1.5) * 10 + 0.5) / 10
		out.Minutes = math.floor(clampNum(raw.Minutes, m[1], m[2], m[1]))
	end
	return action, out, nil
end

-- Rolle in globalen Nachrichten: fehlt = "Owner" (ältere Server), sonst nur Staff.ROLES; alles andere -> ungültig
local function globalRole(role: any): string?
	if role == nil then
		return "Owner"
	end
	if type(role) == "string" and Staff.RANK[role] ~= nil then
		return role
	end
	return nil
end

-- Globale Nachricht feldweise prüfen (obere Zeitgrenze!). Gibt eine saubere Kopie oder nil.
function Core.ValidateGlobal(msg: any, now: number, maxSeconds: number): Plain?
	if type(msg) ~= "table" then
		return nil
	end
	local id = msg.Id
	if type(id) ~= "string" or #id < 4 or #id > 64 then
		return nil
	end
	local kind = msg.Kind
	if kind == "Announce" then
		local text = cleanText(msg.Text, ((tonumber(SEC.AnnounceMax) or 200) * 3))
		local name = cleanText(msg.Name, MAX_NAME)
		local userId = msg.UserId
		local role = globalRole(msg.Role)
		if not text or not name or not isInt(userId) or not role then
			return nil
		end
		return { Kind = "Announce", Id = id, Text = text, Name = name, UserId = userId, Role = role }
	elseif kind == "AdminAbuse" then
		if type(msg.Event) ~= "string" or #msg.Event > 40 then
			return nil
		end
		local startAt, untilT = msg.StartAt, msg.Until
		if not Util.IsFinite(startAt) or not Util.IsFinite(untilT) then
			return nil
		end
		if untilT <= now or untilT > now + maxSeconds or startAt > untilT or startAt > now + maxSeconds then
			return nil
		end
		local by = if isInt(msg.By) then msg.By else 0
		local args: Plain = {}
		if type(msg.Args) == "table" then
			local count = 0
			for key, value in pairs(msg.Args) do
				count += 1
				if count > 12 then
					break
				end
				if type(key) == "string" and #key <= 24 and (Util.IsFinite(value) or type(value) == "boolean") then
					args[key] = value
				end
			end
		end
		return {
			Kind = "AdminAbuse",
			Id = id,
			Event = msg.Event,
			Args = args,
			StartAt = startAt,
			Until = untilT,
			By = by,
		}
	elseif kind == "Live" then
		if not isInt(msg.Version) or msg.Version < 0 then
			return nil
		end
		return { Kind = "Live", Id = id, Version = msg.Version }
	elseif kind == "AbuseNote" then
		-- Besitzer-Ansage zu einem Admin-Abuse-Event (Avatar + Haken, Text je Empfänger lokalisiert)
		local event = msg.Event
		local name = cleanText(msg.Name, MAX_NAME)
		if type(event) ~= "string" or #event < 1 or #event > 40 or not string.match(event, "^%w+$") then
			return nil
		end
		local role = globalRole(msg.Role)
		if not name or not isInt(msg.UserId) or not role then
			return nil
		end
		return { Kind = "AbuseNote", Id = id, Event = event, UserId = msg.UserId, Name = name, Role = role }
	end
	return nil
end

-- Dedupe der letzten n Ids (Ring). Seen(id) = true, wenn die Id schon da war (dann verwerfen).
function Core.NewDedupe(n: number): { Seen: (id: string) -> boolean, Size: () -> number }
	local limit = math.max(1, math.floor(n))
	local set: { [string]: boolean } = {}
	local order: { string } = {}
	return {
		Seen = function(id: string): boolean
			if set[id] then
				return true
			end
			set[id] = true
			table.insert(order, id)
			while #order > limit do
				local old = table.remove(order, 1)
				if old then
					set[old] = nil
				end
			end
			return false
		end,
		Size = function(): number
			return #order
		end,
	}
end

-- Besitzer-Handelssperre: ab dem Auslösen bis seconds nach dem Event-Start
function Core.TradeBlocked(list: { { Issued: number, Start: number } }, now: number, seconds: number): boolean
	for _, entry in ipairs(list) do
		if now >= entry.Issued - 1 and now <= entry.Start + seconds then
			return true
		end
	end
	return false
end

-- Markt-Event ablehnen, wenn der Besitzer in den letzten "seconds" gehandelt hat (die "−120 s"-Hälfte)
function Core.TradeLockBefore(lastTrade: number?, now: number, seconds: number): boolean
	return lastTrade ~= nil and now - lastTrade < seconds
end

-- ---------------------------------------------------------------------
-- TEAM-ROLLEN (W19/W26) – reine Hilfen für Run und die Aktionen (StaffTests/AdminTests)
-- ---------------------------------------------------------------------
-- Bann-Dauer: Duration ("30m", "1d", "perm", Preset-Schlüssel) oder Seconds (endlich, -1 = dauerhaft). nil = ungültig.
function Core.BanSeconds(args: any): number?
	local a: Plain = if type(args) == "table" then args else {}
	local seconds = Staff.ParseDuration(a.Duration)
	if seconds == nil and type(a.Duration) == "string" then
		local presets = SEC.BanPresets
		local preset = if type(presets) == "table" then presets[a.Duration] else nil
		if Util.IsFinite(preset) then
			seconds = math.floor(preset)
		end
	end
	if seconds == nil and Util.IsFinite(a.Seconds) then
		seconds = if a.Seconds == -1 then -1 else math.floor(a.Seconds)
	end
	return seconds
end

local function eventPerm(cfg: Plain, event: any, default: string): string
	local perms = cfg.EventPerms
	local value = if type(perms) == "table" and type(event) == "string" then perms[event] else nil
	return if type(value) == "string" then value else default
end

-- Recht für eine Aktion (§5.2 + §16.1). nil = unbekannte Aktion -> ablehnen. cfg = Config.Security.Staff.
function Core.PermFor(action: any, args: any, cfg: any): string?
	if type(action) ~= "string" then
		return nil
	end
	local a: Plain = if type(args) == "table" then args else {}
	local c: Plain = if type(cfg) == "table" then cfg else {}
	local fixed = STATIC_PERMS[action]
	if fixed then
		return fixed
	end
	if action == "Ban" then
		if a.UserId ~= nil or a.Name ~= nil then
			return "Ban" -- offline per UserId/Name: nur mit vollem Bann-Recht
		end
		local seconds = Core.BanSeconds(a)
		if seconds == nil then
			return "TempBan" -- der Handler meldet die ungültige Dauer
		end
		local max = if type(c.TempBanMax) == "table" then c.TempBanMax.Moderator else nil
		if seconds ~= -1 and (max == -1 or (Util.IsFinite(max) and seconds <= max)) then
			return "TempBan"
		end
		return "Ban"
	elseif action == "SetPower" then
		local name = a.Name
		return if type(name) == "string" and POWER_PERM[name] then POWER_PERM[name] else "Debug"
	elseif action == "Give" then
		local grant = a.Grant
		if type(grant) == "table" then
			for key in pairs(grant) do
				if key ~= "Credits" then
					return "GiveItems"
				end
			end
			if Util.IsFinite(grant.Credits) and grant.Credits < 0 then
				return "TakeCredits"
			end
		end
		return "GiveCredits"
	elseif action == "Announce" then
		return if a.Global == true then "AnnounceGlobal" else "Announce"
	elseif action == "Abuse" then
		if type(a.Event) == "string" and MARKET_ACTIONS[a.Event] then
			return "MarketEvents"
		end
		return eventPerm(c, a.Event, "EconomyEvents")
	elseif action == "AbuseStop" then
		return eventPerm(c, a.Event, "EconomyEvents")
	elseif action == "WorldEvent" then
		return eventPerm(c, a.Event, "WorldEvents")
	elseif action == "SetRole" then
		return if a.Role == "Admin" then "ManageAdmins" else "ManageMods"
	end
	return nil
end

-- Alle Admin-Aktionen (sortiert) – StaffTests: jede braucht einen PermFor-Eintrag
function Core.ActionNames(): { string }
	local list: { string } = {}
	for name in pairs(Actions) do
		table.insert(list, name)
	end
	table.sort(list)
	return list
end

-- Masse: all/others oder eine Liste mit mehr als MASS_LIST aufgelösten Zielen (§16.2 Nr. 8)
function Core.IsMassList(text: any, count: number): boolean
	return Staff.IsMass(text) or (Util.IsFinite(count) and count > MASS_LIST)
end

-- Unbekannter Gruppen-Besitzer: strafende Rechte nur für den Besitzer selbst (§16.2 Nr. 1). true = ablehnen.
function Core.OwnerBlocks(perm: any, actorIsOwner: boolean, ownerKnown: boolean): boolean
	return type(perm) == "string" and PUNITIVE[perm] == true and actorIsOwner ~= true and ownerKnown ~= true
end

-- Mindest-Abstand je Schlüssel: (true, 0) und Zeit merken – oder (false, Restsekunden)
function Core.GapOk(store: { [string]: number }, key: string, t: number, gap: number): (boolean, number)
	local last = store[key]
	if last ~= nil and Util.IsFinite(gap) and t - last < gap then
		return false, gap - (t - last)
	end
	store[key] = t
	return true, 0
end

-- Keine Selbstgeschenke für Nicht-Besitzer (§16.2 Nr. 6; auch über me/all/Listen)
function Core.GiftTargets(list: { any }, actor: any, actorIsOwner: boolean): { any }
	if actorIsOwner == true then
		return list
	end
	local out: { any } = {}
	for _, p in ipairs(list) do
		if p ~= actor then
			table.insert(out, p)
		end
	end
	return out
end

-- CR-Deckel für Nicht-Besitzer (Config.Security.Staff.Credits): (true) oder (false, Lang-Schlüssel, Betrag für den Text)
function Core.CreditCaps(amount: number, count: number, givenToday: number, credits: any): (boolean, string?, number?)
	local caps: Plain = if type(credits) == "table" then credits else {}
	local perAction = tonumber(caps.PerAction) or 0
	local perDay = tonumber(caps.PerDay) or 0
	local total = amount * count
	if total > perAction then
		return false, "admin.cmd.capAction", perAction
	end
	local left = math.max(0, perDay - math.max(0, tonumber(givenToday) or 0))
	if total > left then
		return false, "admin.cmd.capDay", left
	end
	return true, nil, nil
end

Core.HEAVY = table.freeze(HEAVY)
Core.PUNITIVE = table.freeze(PUNITIVE)

AdminService.Core = Core

-- =====================================================================
-- HELFER
-- =====================================================================
local function service(name: string): any
	return if Services then Services[name] else nil
end

local function has(name: string, fnName: string): boolean
	local svc = service(name)
	return type(svc) == "table" and type(svc[fnName]) == "function"
end

-- Services.<name>.<fn>(...) in pcall. (ok, Ergebnis …); fehlt der Dienst -> false
local function call(name: string, fnName: string, ...: any): (boolean, ...any)
	local svc = service(name)
	local fn = if type(svc) == "table" then svc[fnName] else nil
	if type(fn) ~= "function" then
		return false
	end
	local result = table.pack(pcall(fn, ...))
	if not result[1] then
		warn(("[Admin] %s.%s fehlgeschlagen: %s"):format(name, fnName, tostring(result[2])))
	end
	return table.unpack(result, 1, result.n)
end

local function langOf(p: Player): Types.Lang
	local ok, lang = call("PlayerStateService", "LangOf", p)
	if ok and (lang == "de" or lang == "en") then
		return lang
	end
	return Lang.For(p)
end

local function L(p: Player, key: string, ...: any): string
	return Lang.T(langOf(p), key, ...)
end

local function now(): number
	return Clock.Now()
end

local function truncate(text: string, maxBytes: number): string
	if #text <= maxBytes then
		return text
	end
	local cut = maxBytes
	for _ = 1, 4 do
		if cut <= 0 or utf8.len(string.sub(text, 1, cut)) ~= nil then
			break
		end
		cut -= 1
	end
	return string.sub(text, 1, math.max(0, cut))
end

local function names(list: { Player }): string
	local out: { string } = {}
	for i, p in ipairs(list) do
		if i > 8 then
			table.insert(out, ("+%d"):format(#list - 8))
			break
		end
		table.insert(out, p.DisplayName)
	end
	return table.concat(out, ", ")
end

local function rootOf(p: Player): BasePart?
	local character = p.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function footOf(p: Player): CFrame?
	local root = rootOf(p)
	local character = p.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return nil
	end
	local offset = if humanoid.RigType == Enum.HumanoidRigType.R6
		then root.Size.Y * 0.5 + 2
		else humanoid.HipHeight + root.Size.Y * 0.5
	return root.CFrame - Vector3.new(0, offset, 0)
end

local function effect(p: Player, name: string, strength: number, data: any?)
	call("PlayerStateService", "Effect", p, name, strength, data)
end

local function effectAll(name: string, strength: number, data: any?)
	call("PlayerStateService", "EffectAll", name, strength, data)
end

local function filterBroadcast(text: string, fromUserId: number): string?
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, fromUserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(result) == "string" then
		return result
	end
	return nil
end

local function utcDay(): number
	return math.floor(os.time() / 86400)
end

local function dateKey(day: number): string
	return os.date("!%Y%m%d", day * 86400) :: string
end

local function shard(): number
	local count = math.max(1, math.floor(tonumber(Config.Tech.Shards) or 8))
	return Util.Hash(game.JobId) % count
end

local guidCounter = 0
local function newId(prefix: string): string
	guidCounter += 1
	return ("%s%x_%x_%x"):format(prefix, os.time(), Util.Hash(game.JobId .. tostring(guidCounter)), guidCounter)
end

local function noApi(err: any): boolean
	local text = string.lower(tostring(err))
	return RunService:IsStudio()
		and (
			string.find(text, "studio", 1, true) ~= nil
			or string.find(text, "publish", 1, true) ~= nil
			or string.find(text, "api services", 1, true) ~= nil
			or string.find(text, "403", 1, true) ~= nil
		)
end

-- DataStore-Zugriff mit "aus"-Schalter je Speicher (Studio ohne API: leise lokal)
local function storeCall(storeName: string, fn: (DataStore) -> any): (boolean, any)
	if storeOff[storeName] then
		return false, "off"
	end
	local ok, result = pcall(function()
		return fn(DataStoreService:GetDataStore(storeName))
	end)
	if not ok then
		if noApi(result) then
			storeOff[storeName] = true
		else
			warn(("[Admin] DataStore %s: %s"):format(storeName, tostring(result)))
		end
	end
	return ok, result
end

-- =====================================================================
-- BESITZER-PRÜFUNG (§B15.1)
-- =====================================================================
local function creatorTypeName(): string
	if game.CreatorType == Enum.CreatorType.Group then
		return "Group"
	end
	return "User"
end

-- Gruppen-Besitzer im Hintergrund laden (yieldet; Ergebnis 10 min gecacht, Fehler = kein Besitzer und nur 30 s
-- gecacht – solange gilt der Besitzer als unbekannt und strafende Team-Rechte sind gesperrt, §16.2 Nr. 1)
local function refreshGroupOwner()
	if groupLoading or creatorTypeName() ~= "Group" or game.CreatorId == 0 then
		return
	end
	local cached = groupOwner
	local cacheSeconds = if cached and cached.Failed
		then GROUP_FAIL_CACHE
		else tonumber(SEC.GroupOwnerCacheSeconds) or 600
	if cached and os.clock() - cached.At < cacheSeconds then
		return
	end
	groupLoading = true
	task.spawn(function()
		local ok, info = pcall(function()
			return GroupService:GetGroupInfoAsync(game.CreatorId)
		end)
		groupLoading = false
		local ownerId = 0
		if ok and type(info) == "table" and type(info.Owner) == "table" and isInt(info.Owner.Id) then
			ownerId = info.Owner.Id
		elseif not ok then
			-- schon einmal sicher geladen: diesen Besitzer behalten (ein Aussetzer stuft ihn nicht herab), bald neu fragen
			local previous = groupOwner
			if previous and previous.Id ~= 0 then
				ownerId = previous.Id
			end
			warn("[Admin] GetGroupInfoAsync fehlgeschlagen (nächster Versuch in 30 s): " .. tostring(info))
		end
		groupOwner = { Id = ownerId, At = os.clock(), Failed = not ok }
		-- Spieler neu bewerten (Attribut IsAdmin = Besitzer nachziehen, Team-Rolle neu berechnen)
		for _, p in ipairs(Players:GetPlayers()) do
			adminCache[p] = nil
			local isAdmin = AdminService.IsAdmin(p)
			p:SetAttribute("IsAdmin", if isAdmin then true else nil)
			if isAdmin and p:GetAttribute("CanFly") == nil then
				p:SetAttribute("CanFly", true)
			end
			call("StaffService", "Refresh", p)
		end
	end)
end

local function computeAdmin(p: Player): boolean
	local owner = groupOwner
	return Core.OwnerRule({
		CreatorType = creatorTypeName(),
		CreatorId = game.CreatorId,
		UserId = p.UserId,
		Studio = RunService:IsStudio(),
		GroupOwnerId = if owner then owner.Id else nil,
		Cfg = Config.Admin,
	})
end

-- Nie yielden (AntiCheat/PlotService fragen aus Takten): nur Cache + nicht-yieldende Regel
function AdminService.IsAdmin(p: Player): boolean
	if typeof(p) ~= "Instance" or not p:IsA("Player") then
		return false
	end
	local cached = adminCache[p]
	if cached == nil then
		cached = computeAdmin(p)
		if p.Parent == Players then
			adminCache[p] = cached
		end
	end
	return cached == true
end

-- Besitzer-Id (Nutzer-Spiel: CreatorId; Gruppen-Spiel: geladener Gruppen-Besitzer) – nie yieldend
local function isOwnerId(userId: number): boolean
	if creatorTypeName() == "User" then
		return game.CreatorId ~= 0 and userId == game.CreatorId
	end
	local owner = groupOwner
	return owner ~= nil and owner.Id ~= 0 and owner.Id == userId
end

function AdminService.IsOwnerId(userId: number): boolean
	return isInt(userId) and isOwnerId(userId)
end

-- Besitzer bekannt? Nutzer-Spiel immer; Gruppen-Spiel erst, wenn GetGroupInfoAsync einen Besitzer geliefert hat.
-- Solange unbekannt, lehnt Run strafende Team-Rechte ab (sonst könnte ein Admin den echten Besitzer bannen, §16.2 Nr. 1).
function AdminService.OwnerKnown(): boolean
	if creatorTypeName() == "User" then
		return true
	end
	local owner = groupOwner
	return owner ~= nil and owner.Id ~= 0
end

-- =====================================================================
-- ROLLEN & RECHTE (W19) – StaffService liefert Admin/Moderator; fehlt er, gilt die alte Regel: nur der Besitzer
-- =====================================================================
-- Besitzer immer "Owner" (aus IsAdmin, nie aus StaffService); sonst StaffService.RoleOf (nie yieldend)
local function roleOf(p: Player): string?
	if AdminService.IsAdmin(p) then
		return "Owner"
	end
	local ok, role = call("StaffService", "RoleOf", p)
	if ok and type(role) == "string" and role ~= "Owner" and Staff.RANK[role] ~= nil then
		return role
	end
	return nil
end

local function can(p: Player, perm: string): boolean
	return Staff.Can(roleOf(p), perm, STAFF)
end

local function rankOf(p: Player): number
	return Staff.Rank(roleOf(p))
end

-- Rang-Regel: nur gegen niedrigere Ränge (Besitzer gegen Besitzer im Studio = gleich = geschützt)
local function canActOn(actor: Player, target: Player): boolean
	return Staff.CanActOn(rankOf(actor), rankOf(target))
end

local function groupEnabled(): boolean
	local group = STAFF.Group
	return type(group) == "table" and Util.IsFinite(group.Id) and group.Id > 0
end

-- Rang einer (auch offline) UserId: (Rang, bekannt). Unbekannt = geschützt (§16.2 Nr. 2). Yieldet (Gruppen-Abfrage).
local function rankOfUserIdAsync(userId: number): (number, boolean)
	local online = Players:GetPlayerByUserId(userId)
	if online then
		return rankOf(online), true
	end
	if isOwnerId(userId) then
		return Staff.RANK.Owner, true
	end
	if has("StaffService", "RankOfUserIdAsync") then
		local ok, rank, known = call("StaffService", "RankOfUserIdAsync", userId)
		if ok and Util.IsFinite(rank) then
			return rank, known ~= false
		end
		return Staff.RANK.Owner, false
	end
	if has("StaffService", "RankOfUserId") then
		local ok, rank = call("StaffService", "RankOfUserId", userId)
		if ok and Util.IsFinite(rank) then
			return rank, not groupEnabled() -- ohne Gruppen-Abfrage ist ein Gruppen-Rang unbekannt
		end
		return Staff.RANK.Owner, false
	end
	return 0, true -- ohne StaffService handelt nur der Besitzer; jedes andere Ziel hat Rang 0
end

-- Rang eines Bestrafenden (Undo-Regel): online -> Rolle, offline -> gespeicherte Rolle (nie yieldend), unbekannt -> 0
local function punisherRank(userId: any): number
	if not isInt(userId) then
		return 0
	end
	local online = Players:GetPlayerByUserId(userId)
	if online then
		return rankOf(online)
	end
	if isOwnerId(userId) then
		return Staff.RANK.Owner
	end
	local ok, rank = call("StaffService", "RankOfUserId", userId)
	return if ok and Util.IsFinite(rank) then rank else 0
end

-- =====================================================================
-- ZIELE (Shared/Staff.MatchTargets: me, all, others, a,b,c, @Anzeigename, UserId, Name, Präfix – nur eindeutig)
-- =====================================================================
local function targetError(admin: Player, errKey: string?, errArg: string?): string
	if errKey == nil then
		return L(admin, "admin.noTarget")
	end
	local arg = errArg or ""
	if errKey == "admin.cmd.ambiguous" then
		local text, list = string.match(arg, "^(.-)|(.*)$")
		return L(admin, errKey, text or arg, list or "")
	end
	return L(admin, errKey, arg)
end

-- (Liste, Fehlertext): leere Liste -> Fehlertext (kein Spieler, mehrdeutig mit Namen)
local function resolveTargets(admin: Player, text: any): ({ Player }, string?)
	local list, errKey, errArg = Staff.MatchTargets(text, Players:GetPlayers(), admin)
	local out: { Player } = {}
	for _, p in ipairs(list) do
		if typeof(p) == "Instance" and p:IsA("Player") then
			table.insert(out, p)
		end
	end
	if #out == 0 then
		return out, targetError(admin, errKey, errArg)
	end
	return out, nil
end

local function resolveOne(admin: Player, text: any): (Player?, string?)
	local list, err = resolveTargets(admin, text)
	if #list == 0 then
		return nil, err or L(admin, "admin.noTarget")
	elseif #list > 1 then
		return nil, L(admin, "admin.oneTarget")
	end
	return list[1], nil
end

-- Rang-Filter für strafende Aktionen: (erlaubt, wegen Rang übersprungen, war man selbst dabei?)
local function filterRank(admin: Player, list: { Player }, allowSelf: boolean): ({ Player }, { Player }, boolean)
	local kept: { Player } = {}
	local skipped: { Player } = {}
	local hadSelf = false
	local myRank = rankOf(admin)
	for _, p in ipairs(list) do
		if p == admin then
			hadSelf = true
			if allowSelf then
				table.insert(kept, p)
			end
		elseif Staff.CanActOn(myRank, rankOf(p)) then
			table.insert(kept, p)
		else
			table.insert(skipped, p)
		end
	end
	return kept, skipped, hadSelf
end

-- Fehlertext, wenn nach dem Rang-Filter niemand übrig ist
local function rankError(admin: Player, skipped: { Player }, hadSelf: boolean): string
	if #skipped > 0 then
		return L(admin, "admin.cmd.rank", names(skipped))
	end
	return L(admin, if hadSelf then "admin.notSelf" else "admin.noTarget")
end

-- Antwort + "· n übersprungen (gleicher oder höherer Rang)"
local function withSkipped(admin: Player, text: string, skipped: number): string
	if skipped <= 0 then
		return text
	end
	return text .. " · " .. L(admin, "admin.cmd.skipped", skipped)
end

-- Masse (all/others oder > 3 Ziele) ohne MassTarget -> Fehlertext, sonst nil
local function massError(admin: Player, text: any, count: number, key: string?): string?
	if Core.IsMassList(text, count) and not can(admin, "MassTarget") then
		return L(admin, key or "admin.cmd.mass")
	end
	return nil
end

-- Kraft-Attribut nur mit dem passenden Recht (Fliegen, Noclip, Tempo, Sprung, Unsichtbar, ESP); sonst nil
function AdminService.Power(p: Player, name: string): any
	if typeof(p) ~= "Instance" or not p:IsA("Player") or type(name) ~= "string" then
		return nil
	end
	local perm = POWER_PERM[name]
	if perm == nil then
		return if AdminService.IsAdmin(p) then p:GetAttribute(name) else nil
	end
	if not can(p, perm) then
		return nil
	end
	return p:GetAttribute(name)
end

function AdminService.IsServerLocked(): boolean
	return serverLocked
end

function AdminService.OwnerTradeBlocked(p: Player): boolean
	if typeof(p) ~= "Instance" or not AdminService.IsAdmin(p) then
		return false
	end
	local list = ownerEvents[p]
	if not list or #list == 0 then
		return false
	end
	return Core.TradeBlocked(list, now(), tonumber(SEC.OwnerTradeBlockSeconds) or 120)
end

-- =====================================================================
-- ADMIN-LOG (AT_Mod_v1 "AdminLog", letzte 500 + Wochen-Kopie AT_Global "AdminLog_W<w>")
-- =====================================================================
-- via = "Panel" | "Chat"; Role = O/A/M/- (Rolle beim Handeln); Target = Ziel-Text (nie Chat-Rohtext)
local function logAction(p: Player, action: string, ok: boolean, message: string?, via: string?, target: string?)
	local entry = {
		T = os.time(),
		By = p.UserId,
		Name = string.sub(p.Name, 1, MAX_NAME),
		Action = string.sub(action, 1, MAX_ACTION_LEN),
		Ok = ok,
		Msg = truncate(tostring(message or ""), LOG_MSG_MAX),
		Job = string.sub(if game.JobId ~= "" then game.JobId else "Studio", 1, 12),
		Via = if via == "Chat" then "Chat" else "Panel",
		Role = string.sub(roleOf(p) or "-", 1, 1),
		Target = if type(target) == "string" and target ~= "" then truncate(target, MAX_NAME) else nil,
	}
	table.insert(adminLog, entry)
	local max = math.floor(tonumber(SEC.AdminLogMax) or 500)
	while #adminLog > max do
		table.remove(adminLog, 1)
	end
	table.insert(logPending, entry)
	while #logPending > max do
		table.remove(logPending, 1)
	end
end

local function flushLog()
	if #logPending == 0 then
		return
	end
	local batch = table.clone(logPending)
	table.clear(logPending)
	task.spawn(function()
		local max = math.floor(tonumber(SEC.AdminLogMax) or 500)
		local function merge(old: any): { Plain }
			local list: { Plain } = if type(old) == "table" then old else {}
			for _, entry in ipairs(batch) do
				table.insert(list, entry)
			end
			while #list > max do
				table.remove(list, 1)
			end
			return list
		end
		local okMod = storeCall(Config.Tech.ModStore, function(store)
			return store:UpdateAsync("AdminLog", merge)
		end)
		local week = Clock.WeekIndex(Clock.Tick())
		storeCall(Config.Tech.GlobalStore or "AT_Global", function(store)
			return store:UpdateAsync(("AdminLog_W%d"):format(week), merge)
		end)
		if okMod then
			storedLog = nil
		end
	end)
end

local function readLog(): { Plain }
	local cached = storedLog
	local list: { Plain } = {}
	if cached and os.clock() - cached.At < 30 then
		list = cached.List
	else
		local ok, stored = storeCall(Config.Tech.ModStore, function(store)
			return store:GetAsync("AdminLog")
		end)
		if ok and type(stored) == "table" then
			for _, entry in ipairs(stored) do
				if type(entry) == "table" and Util.IsFinite(entry.T) then
					table.insert(list, entry)
				end
			end
		end
		storedLog = { List = list, At = os.clock() }
	end
	local merged: { Plain } = {}
	local seen: { [string]: boolean } = {}
	local function add(entry: Plain)
		local key = ("%s_%s_%s_%s"):format(
			tostring(entry.T),
			tostring(entry.By),
			tostring(entry.Action),
			tostring(entry.Job)
		)
		if not seen[key] then
			seen[key] = true
			table.insert(merged, entry)
		end
	end
	for _, entry in ipairs(list) do
		add(entry)
	end
	for _, entry in ipairs(adminLog) do
		add(entry)
	end
	table.sort(merged, function(a, b)
		return (tonumber(a.T) or 0) > (tonumber(b.T) or 0)
	end)
	local max = math.floor(tonumber(SEC.AdminLogMax) or 500)
	while #merged > max do
		table.remove(merged)
	end
	return merged
end

-- =====================================================================
-- GLOBALE NACHRICHTEN (MessagingService, jedes Feld geprüft, Dedupe)
-- =====================================================================
local dedupe = Core.NewDedupe(tonumber(EV.GlobalDedupe) or tonumber(SEC.GlobalDedupe) or 200)

local applyLiveDoc: (doc: any) -> number
local loadLive: () -> ()

-- role = Rolle des Absenders ("Owner" | "Admin" | "Moderator") – der Client zeigt sie an der Ansage (Effects)
local function showAnnouncement(text: string, userId: number, name: string, role: string?)
	effectAll("Announce", 0, { Text = text, UserId = userId, Name = name, Role = role or "Owner" })
end

-- Admin-Abuse-Ansage im Besitzer-Stil (Avatar + blauer Haken, ohne Kasten), je Empfänger in seiner Sprache
local function showAbuseNote(event: string, userId: number, name: string, role: string?)
	local key = "admin.note." .. event
	local known = Lang.Has(key)
	for _, p in ipairs(Players:GetPlayers()) do
		local lang = langOf(p)
		local text = if known
			then Lang.T(lang, key)
			else Lang.T(lang, "admin.note.Generic", Lang.T(lang, "admin.ev." .. event))
		effect(p, "Announce", 0, { Text = text, UserId = userId, Name = name, Role = role or "Owner" })
	end
end

local function handleGlobal(message: any)
	local clean = Core.ValidateGlobal(message, now(), tonumber(EV.MaxGlobalSeconds) or 3600)
	if not clean then
		return
	end
	if dedupe.Seen(clean.Id) then
		return
	end
	if clean.Kind == "Announce" then
		showAnnouncement(clean.Text, clean.UserId, clean.Name, clean.Role)
	elseif clean.Kind == "AbuseNote" then
		showAbuseNote(clean.Event, clean.UserId, clean.Name, clean.Role)
	elseif clean.Kind == "AdminAbuse" then
		call("EventService", "ApplyGlobal", clean)
	elseif clean.Kind == "Live" then
		if clean.Version > (tonumber(liveDoc.Version) or 0) and os.clock() - liveReloadAt >= LIVE_RELOAD_GAP then
			liveReloadAt = os.clock()
			task.spawn(loadLive)
		end
	end
end

-- Global senden; Fehler -> wenigstens auf diesem Server. Auch bei Erfolg sofort lokal ausführen: MessagingService
-- liefert nur "best effort" (das Echo an den Sender kann fehlen, im Studio scheitert oft schon SubscribeAsync) –
-- das Dedupe per Id verwirft das spätere Echo, nichts läuft doppelt.
local function publishGlobal(message: Plain): boolean
	local ok, err = pcall(function()
		MessagingService:PublishAsync(Config.Tech.MessagingTopic, message)
	end)
	if not ok then
		warn("[Admin] Global senden fehlgeschlagen (nur dieser Server): " .. tostring(err))
	end
	handleGlobal(message)
	return ok
end

-- Ansage zu einem Admin-Abuse-Event: global (alle Server) oder nur dieser Server
local function announceAbuse(admin: Player, event: string, global: boolean)
	local message = {
		Kind = "AbuseNote",
		Id = newId("B"),
		Event = event,
		UserId = admin.UserId,
		Name = string.sub(admin.DisplayName, 1, MAX_NAME),
		Role = roleOf(admin) or "Owner",
	}
	if global then
		publishGlobal(message)
	else
		handleGlobal(message)
	end
end

local function abuseSeconds(kind: string, args: Plain): number
	local limits = EV.AdminLimits
	if kind == "GoldenHour" or kind == "XpRush" then
		return (tonumber(args.Minutes) or 5) * 60
	elseif kind == "MoneyRain" or kind == "Boss" then
		return tonumber(args.Seconds) or 120
	elseif kind == "AdminBuildBoom" then
		return (tonumber(limits.BuildBoom.Minutes) or 10) * 60
	elseif kind == "SaturdayShow" then
		local show = limits.SaturdayShow
		return math.max(
			(tonumber(show.RainDelay) or 75) + (tonumber(show.RainSeconds) or 180),
			(tonumber(show.FireworksDelay) or 260) + 20
		)
	end
	return 120
end

function AdminService.PublishAbuse(kind: string, args: Plain, by: Player): (boolean, string)
	if typeof(by) ~= "Instance" or not by:IsA("Player") or type(kind) ~= "string" or not can(by, "GlobalEvents") then
		return false, "denied"
	end
	local t = now()
	local lead = tonumber(EV.GlobalLead) or 5
	local seconds = math.clamp(abuseSeconds(kind, if type(args) == "table" then args else {}), 1, 3600 - lead - 1)
	local message = {
		Kind = "AdminAbuse",
		Id = newId("A"),
		Event = kind,
		Args = if type(args) == "table" then args else {},
		StartAt = t + lead,
		Until = t + lead + seconds,
		By = by.UserId,
	}
	if publishGlobal(message) then
		return true, "global"
	end
	return true, "local"
end

-- =====================================================================
-- LIVE-CONFIG (AT_Live_v1, Admin-Tab Live-Ops)
-- =====================================================================
applyLiveDoc = function(doc: any): number
	if type(doc) ~= "table" then
		return 0
	end
	local fields = if type(doc.Fields) == "table" then doc.Fields else {}
	local applied, issues = Config.ApplyLive({ Fields = fields })
	for i = 1, math.min(#issues, 5) do
		warn("[Admin] LiveConfig: " .. tostring(issues[i]))
	end
	local banner = if type(doc.Banner) == "string" then truncate(doc.Banner, BANNER_MAX * 3) else ""
	workspace:SetAttribute(MAINTENANCE_ATTR, if banner ~= "" then banner else nil)
	liveDoc = {
		Fields = fields,
		Banner = banner,
		Version = if isInt(doc.Version) then doc.Version else 0,
		At = if Util.IsFinite(doc.At) then doc.At else 0,
		By = if isInt(doc.By) then doc.By else 0,
	}
	return applied
end

loadLive = function()
	local ok, doc = storeCall(Config.Tech.LiveStore, function(store)
		return store:GetAsync(LIVE_KEY)
	end)
	if ok and type(doc) == "table" then
		applyLiveDoc(doc)
	end
end

-- Neues Live-Dokument prüfen (ApplyLive auf die Kandidaten-Felder), speichern, verteilen
local function saveLive(admin: Player, fields: Plain, banner: string): (boolean, string)
	local applied, issues = Config.ApplyLive({ Fields = fields })
	local candidateCount = 0
	for _ in pairs(fields) do
		candidateCount += 1
	end
	if #issues > 0 or applied ~= candidateCount then
		Config.ApplyLive({ Fields = liveDoc.Fields or {} }) -- zurück auf den gültigen Stand
		return false, L(admin, "admin.liveInvalid", tostring(issues[1] or "?"))
	end
	local version = (tonumber(liveDoc.Version) or 0) + 1
	local doc = { Fields = fields, Banner = banner, Version = version, At = os.time(), By = admin.UserId }
	local okStore = storeCall(Config.Tech.LiveStore, function(store)
		return store:UpdateAsync(LIVE_KEY, function(old)
			if type(old) == "table" and isInt(old.Version) and old.Version >= version then
				doc.Version = old.Version + 1
			end
			return doc
		end)
	end)
	applyLiveDoc(doc)
	if okStore then
		publishGlobal({ Kind = "Live", Id = newId("L"), Version = doc.Version })
		return true, L(admin, "admin.liveSaved", doc.Version)
	end
	return true, L(admin, "admin.liveLocal", doc.Version)
end

-- =====================================================================
-- UNSICHTBAR, EINFRIEREN, TELEPORT
-- =====================================================================
local function setPartInvisible(d: Instance, invisible: boolean)
	if d:IsA("BasePart") or d:IsA("Decal") then
		if invisible then
			if d:GetAttribute("AdminOrigT") == nil then
				d:SetAttribute("AdminOrigT", (d :: any).Transparency)
			end
			(d :: any).Transparency = 1
		else
			local orig = d:GetAttribute("AdminOrigT")
			if orig ~= nil then
				(d :: any).Transparency = orig
				d:SetAttribute("AdminOrigT", nil)
			end
		end
	elseif d:IsA("BillboardGui") then
		if invisible then
			if d:GetAttribute("AdminOrigE") == nil then
				d:SetAttribute("AdminOrigE", d.Enabled)
			end
			d.Enabled = false
		else
			local orig = d:GetAttribute("AdminOrigE")
			if orig ~= nil then
				d.Enabled = orig == true
				d:SetAttribute("AdminOrigE", nil)
			end
		end
	end
end

local function setInvisible(p: Player, invisible: boolean)
	local old = invisConn[p]
	if old then
		old:Disconnect()
		invisConn[p] = nil
	end
	local character = p.Character
	if not character then
		return
	end
	for _, d in ipairs(character:GetDescendants()) do
		setPartInvisible(d, invisible)
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = if invisible
			then Enum.HumanoidDisplayDistanceType.None
			else Enum.HumanoidDisplayDistanceType.Viewer
	end
	if invisible then
		-- später angehängte Teile (Uhr, Accessoires, Namensschild) ebenfalls verstecken
		invisConn[p] = character.DescendantAdded:Connect(function(d)
			setPartInvisible(d, true)
		end)
	end
end

-- Kräfte, die die (neue) Rolle nicht hat, löschen – StaffService.Refresh ruft das bei jeder Rollen-Änderung (auch beim
-- Herabstufen). Der Besitzer bleibt unverändert.
function AdminService.SyncPowers(p: Player)
	if typeof(p) ~= "Instance" or not p:IsA("Player") or AdminService.IsAdmin(p) then
		return
	end
	for name, perm in pairs(POWER_PERM) do
		if p:GetAttribute(name) ~= nil and not can(p, perm) then
			p:SetAttribute(name, nil)
			if name == "AdminInvisible" then
				setInvisible(p, false)
			end
		end
	end
end

local function freeze(p: Player, on: boolean)
	local root = rootOf(p)
	if not root then
		return
	end
	root.Anchored = on
	if not on then
		pcall(function()
			root:SetNetworkOwner(p)
		end)
	end
end

-- Erst aussteigen lassen: wer im Auto sitzt, würde sonst samt Auto versetzt (Sitz-Schweißung). VehicleService merkt
-- das Aussteigen über den Sitz selbst (Erlaubnis zurück, Ausroll-Gnade). Yieldet höchstens ~0,5 s (Admin-Aktion).
local function unseat(p: Player): boolean
	local character = p.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if not humanoid or not seat then
		return true
	end
	local weld = seat:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end
	humanoid.Sit = false
	for _ = 1, 10 do
		if humanoid.SeatPart == nil then
			break
		end
		task.wait(0.05)
	end
	return humanoid.SeatPart == nil
end

local function teleport(p: Player, cf: CFrame): boolean
	if not unseat(p) then
		return false
	end
	local ok, moved = call("PlotService", "Teleport", p, cf)
	if ok and moved == true then
		return true
	end
	local character = p.Character
	if character then
		local okPivot = pcall(function()
			character:PivotTo(cf + Vector3.new(0, 3, 0))
		end)
		call("AntiCheatService", "NoteTeleport", p, cf + Vector3.new(0, 3, 0))
		return okPivot
	end
	return false
end

-- =====================================================================
-- SPEED-GESCHENK (Wunsch 18): Tempo/Sprungkraft für beliebige Spieler, befristet oder bis zum Zurücksetzen.
-- Der Server setzt Humanoid.WalkSpeed/JumpHeight (repliziert zum Client des Spielers) und die Attribute
-- GiftSpeed/GiftJump/GiftUntil (AntiCheatService erlaubt das Tempo/die Höhe; ein Respawn übernimmt das Geschenk).
-- =====================================================================
local function defaultWalk(): number
	local client: any = Config.Client
	local move = if type(client) == "table" then client.Movement else nil
	return if type(move) == "table" and Util.IsFinite(move.WalkSpeed) then move.WalkSpeed else 16
end

local function giftActive(p: Player): boolean
	return p:GetAttribute(GIFT_SPEED) ~= nil or p:GetAttribute(GIFT_JUMP) ~= nil
end

local function applyGift(p: Player)
	local character = p.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local speed = p:GetAttribute(GIFT_SPEED)
	local jump = p:GetAttribute(GIFT_JUMP)
	humanoid.WalkSpeed = if type(speed) == "number" then speed else defaultWalk()
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = if type(jump) == "number" then jump else DEFAULT_JUMP
end

-- Geschenk beenden: Standardwerte zurück, laufender Schwung/Sprung zählt bis zur Landung nicht als Verstoß
local function clearGift(p: Player, tell: boolean): boolean
	if not giftActive(p) then
		return false
	end
	local oldSpeed = tonumber(p:GetAttribute(GIFT_SPEED)) or defaultWalk()
	call("AntiCheatService", "Grace", p, "Impulse", 2, oldSpeed * 1.25)
	p:SetAttribute(GIFT_SPEED, nil)
	p:SetAttribute(GIFT_JUMP, nil)
	p:SetAttribute(GIFT_UNTIL, nil)
	local character = p.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = defaultWalk()
		humanoid.JumpHeight = DEFAULT_JUMP
	end
	if tell then
		call("PlayerStateService", "Notify", p, "admin.giftEnded", nil, "Info")
	end
	return true
end

-- Abgelaufene Geschenke beenden (1 Hz, kein Yield)
local function expireGifts()
	local t = now()
	for _, p in ipairs(Players:GetPlayers()) do
		local untilT = p:GetAttribute(GIFT_UNTIL)
		if type(untilT) == "number" and t >= untilT then
			clearGift(p, true)
		end
	end
end

-- =====================================================================
-- GABEN (nur Turm-Seite über ShopService.Grant; AKY/Lizenz taint die Liga-Woche)
-- =====================================================================
local function keysOf(list: any): { string }
	local out: { string } = {}
	if type(list) == "table" then
		for _, entry in ipairs(list) do
			if type(entry) == "table" and type(entry.Key) == "string" then
				table.insert(out, entry.Key)
			end
		end
	end
	return out
end

local function cleanKeyList(raw: any, max: number): { string }?
	if type(raw) ~= "table" then
		return nil
	end
	local list: { string } = {}
	for i, key in ipairs(raw) do
		if i > max then
			break
		end
		if type(key) == "string" and #key >= 1 and #key <= 40 and string.match(key, "^[%w_]+$") then
			table.insert(list, key)
		end
	end
	return if #list > 0 then list else nil
end

local function sanitizeGrant(raw: any): Types.Grant?
	if type(raw) ~= "table" then
		return nil
	end
	local grant: Plain = {}
	if Util.IsFinite(raw.Credits) and raw.Credits >= 1 then
		grant.Credits = math.floor(math.min(raw.Credits, MAX_GIVE_CREDITS))
	end
	for _, field in ipairs({ "Cars", "Watches", "Accessories", "Cosmetics", "Titles" }) do
		local list = cleanKeyList(raw[field], 64)
		if list then
			grant[field] = list
		end
	end
	if type(raw.Decor) == "table" then
		local decor: { [string]: number } = {}
		local count = 0
		for key, n in pairs(raw.Decor) do
			count += 1
			if count > 64 then
				break
			end
			if type(key) == "string" and #key <= 40 and Util.IsFinite(n) and n >= 1 then
				decor[key] = math.floor(math.min(n, 99))
			end
		end
		if next(decor) ~= nil then
			grant.Decor = decor
		end
	end
	local numberMax = Config.Shop and Config.Shop.GrantNumberMax or {}
	for _, field in ipairs({ "BoostX2", "BoostX5", "ExpressTokens", "InstantTokens", "SeasonTiers", "SeasonXp" }) do
		local v = raw[field]
		if Util.IsFinite(v) and v >= 1 then
			local cap = tonumber(numberMax[field]) or 100000
			grant[field] = math.floor(math.min(v, cap))
		end
	end
	if raw.SeasonPremium == true then
		grant.SeasonPremium = true
	end
	if next(grant) == nil then
		return nil
	end
	return grant :: any
end

local function grantTo(targets: { Player }, grant: Types.Grant): { Player }
	local done: { Player } = {}
	for _, p in ipairs(targets) do
		local ok, result = call("ShopService", "Grant", p, grant, "Admin")
		if ok and result == true then
			table.insert(done, p)
		end
	end
	return done
end

-- =====================================================================
-- STATISTIK (Fills/min, meistgehandelt, Käufe über AT_Stats_v1-Shards, globale Spieler über Herzschlag)
-- =====================================================================
local function onTrade(p: Player, fill: any)
	if typeof(p) ~= "Instance" or type(fill) ~= "table" then
		return
	end
	local t = now()
	if AdminService.IsAdmin(p) then
		ownerLastTrade[p] = t
	end
	table.insert(tradeTimes, t)
	while #tradeTimes > 2000 or (tradeTimes[1] ~= nil and t - tradeTimes[1] > MARKET_TRADE_WINDOW) do
		table.remove(tradeTimes, 1)
	end
	if isInt(fill.I) then
		local key = tostring(fill.I)
		if tradedCount[key] == nil then
			if tradedKeys >= MAX_TRADED_KEYS then
				return
			end
			tradedKeys += 1
		end
		tradedCount[key] = (tradedCount[key] or 0) + 1
	end
end

-- Käufe erkennen: RobuxSpent/Belege im Spielstand steigen (unabhängig vom Kaufweg; kein Eingriff in WP10)
local function samplePurchases()
	for _, p in ipairs(Players:GetPlayers()) do
		local ok, data = call("DataService", "Get", p)
		if ok and type(data) == "table" and type(data.Purchases) == "table" then
			local robux = tonumber(data.Purchases.RobuxSpent) or 0
			local receipts = if type(data.Purchases.Receipts) == "table" then #data.Purchases.Receipts else 0
			local seen = purchaseSeen[p]
			if seen then
				if robux > seen.Robux then
					statsPending.Robux += robux - seen.Robux
					statsPending.Count += math.max(1, receipts - seen.Receipts)
				end
			end
			purchaseSeen[p] = { Robux = robux, Receipts = receipts }
		end
	end
end

local function flushPurchaseStats()
	if statsPending.Robux <= 0 and statsPending.Count <= 0 then
		return
	end
	local batch = { Robux = statsPending.Robux, Count = statsPending.Count }
	statsPending.Robux, statsPending.Count = 0, 0
	task.spawn(function()
		local key = ("D_%s_%d"):format(dateKey(utcDay()), shard())
		local ok = storeCall(Config.Tech.StatsStore, function(store)
			return store:UpdateAsync(key, function(old)
				local entry: Plain = if type(old) == "table" then old else {}
				entry.Robux = (tonumber(entry.Robux) or 0) + batch.Robux
				entry.Count = (tonumber(entry.Count) or 0) + batch.Count
				return entry
			end)
		end)
		if not ok and not storeOff[Config.Tech.StatsStore] then
			statsPending.Robux += batch.Robux -- später erneut
			statsPending.Count += batch.Count
		end
	end)
end

local function readPurchaseDay(day: number): Plain
	local total = { Robux = 0, Count = 0 }
	local shards = math.max(1, math.floor(tonumber(Config.Tech.Shards) or 8))
	for s = 0, shards - 1 do
		local ok, entry = storeCall(Config.Tech.StatsStore, function(store)
			return store:GetAsync(("D_%s_%d"):format(dateKey(day), s))
		end)
		if ok and type(entry) == "table" then
			total.Robux += tonumber(entry.Robux) or 0
			total.Count += tonumber(entry.Count) or 0
		end
		if storeOff[Config.Tech.StatsStore] then
			break
		end
	end
	return total
end

local function writeHeartbeat()
	if heartbeatOff then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			local map = MemoryStoreService:GetHashMap(Config.Tech.HeartbeatMap)
			map:SetAsync(if game.JobId ~= "" then game.JobId else "Studio", #Players:GetPlayers(), HEARTBEAT_TTL)
		end)
		if not ok then
			if noApi(err) then
				heartbeatOff = true
			else
				warn("[Admin] Herzschlag: " .. tostring(err))
			end
		end
	end)
end

local function readHeartbeat(): (number, number)
	local cached = heartbeatCache
	if cached and os.clock() - cached.At < HEARTBEAT_CACHE then
		return cached.Players, cached.Servers
	end
	local playersSum, servers = #Players:GetPlayers(), 1
	if not heartbeatOff then
		local ok, page = pcall(function()
			local map = MemoryStoreService:GetHashMap(Config.Tech.HeartbeatMap)
			return map:ListItemsAsync(200):GetCurrentPage()
		end)
		if ok and type(page) == "table" then
			playersSum, servers = 0, 0
			for _, item in ipairs(page) do
				if type(item) == "table" and Util.IsFinite(item.value) then
					playersSum += item.value
					servers += 1
				end
			end
			if servers == 0 then
				playersSum, servers = #Players:GetPlayers(), 1
			end
		end
	end
	heartbeatCache = { At = os.clock(), Players = playersSum, Servers = servers }
	return playersSum, servers
end

local function schedulerTop(n: number): ({ Plain }, number, number)
	local schedulerStats = Scheduler.Stats()
	local total = schedulerStats._Total
	local jobs: { Plain } = {}
	for name, stat in pairs(schedulerStats) do
		if name ~= "_Total" then
			table.insert(jobs, { Name = name, AvgMs = stat.AvgMs, MaxMs = stat.MaxMs })
		end
	end
	table.sort(jobs, function(a, b)
		return a.AvgMs > b.AvgMs
	end)
	while #jobs > n do
		table.remove(jobs)
	end
	return jobs, if total then total.AvgMs else 0, if total then total.MaxMs else 0
end

local function memoryMb(): number
	local ok, memory = pcall(function()
		return Stats:GetTotalMemoryUsageMb()
	end)
	return if ok and Util.IsFinite(memory) then math.floor(memory) else 0
end

-- =====================================================================
-- AKTIONEN – DASHBOARD & F8
-- =====================================================================
Actions.Dashboard = function(admin, _args)
	local jobs, avg, max = schedulerTop(6)
	local globalPlayers, servers = readHeartbeat()
	local okMarket, market = call("MarketService", "Stats")
	local okLocal, localMarket = call("MarketService", "IsLocalMarket")
	local okEvents, active = call("EventService", "Active")
	local kinds: { string } = {}
	if okEvents and type(active) == "table" then
		for _, ev in ipairs(active) do
			if type(ev) == "table" and type(ev.Kind) == "string" then
				table.insert(kinds, ev.Kind)
			end
		end
	end
	local okAbuse, abuse = call("EventService", "IsAdminAbuse")
	-- Markt-Kennzahlen + Start-Zustand (W20: MarketService.Status = "Booting" | "Live" | "Local" | "Failed", Versuch)
	local marketData: Plain? = if okMarket and type(market) == "table" then table.clone(market) else nil
	local okStatus, status, attempt = call("MarketService", "Status")
	if okStatus and type(status) == "string" then
		local info: Plain = marketData or {}
		info.Status = string.sub(status, 1, 16)
		info.Attempt = if isInt(attempt) then attempt else 0
		marketData = info
	end
	local data = {
		Players = #Players:GetPlayers(),
		MaxPlayers = Players.MaxPlayers,
		GlobalPlayers = globalPlayers,
		Servers = servers,
		Events = kinds,
		AdminAbuse = okAbuse and abuse == true,
		Market = marketData,
		LocalMarket = okLocal and localMarket == true,
		HeartbeatMs = avg,
		HeartbeatMaxMs = max,
		Jobs = jobs,
		MemoryMb = memoryMb(),
		Uptime = math.floor(os.clock() - startedAt),
		Version = Config.Version,
		JobId = if game.JobId ~= "" then game.JobId else "Studio",
		Locked = serverLocked,
		Studio = RunService:IsStudio(),
		LiveVersion = tonumber(liveDoc.Version) or 0,
		Maintenance = liveDoc.Banner or "",
	}
	return true, L(admin, "admin.dashboardLoaded"), data
end

Actions.ServerInfo = function(admin, _args)
	local jobs, avg, max = schedulerTop(5)
	local okMarket, market = call("MarketService", "Stats")
	local okCity, cityParts = call("CityService", "PartCount")
	local okTower, towerParts = call("TowerVisualService", "PartCount")
	local towers = 0
	local plots = math.floor(tonumber(Config.Server.Plots) or 10)
	for k = 1, plots do
		local ok, owner = call("PlotService", "OwnerOf", k)
		if ok and owner ~= nil then
			towers += 1
		end
	end
	local okEv, evStats = call("EventService", "Stats")
	local data = {
		Players = #Players:GetPlayers(),
		HeartbeatMs = avg,
		HeartbeatMaxMs = max,
		Jobs = jobs,
		MarketTickMs = if okMarket and type(market) == "table" then market.TickMs else 0,
		Instruments = if okMarket and type(market) == "table" then market.Instruments else 0,
		FrameBytes = if okMarket and type(market) == "table" then market.FrameBytes else 0,
		BusOk = okMarket and type(market) == "table" and market.BusOk == true,
		Towers = towers,
		Parts = (if okCity and Util.IsFinite(cityParts) then cityParts else 0)
			+ (if okTower and Util.IsFinite(towerParts) then towerParts else 0),
		Pickups = if okEv and type(evStats) == "table" then evStats.OpenTokens else 0,
		MemoryMb = memoryMb(),
		Uptime = math.floor(os.clock() - startedAt),
	}
	return true, L(admin, "admin.serverInfo"), data
end

-- =====================================================================
-- AKTIONEN – SPIELER
-- =====================================================================
Actions.GetPlayers = function(_admin, _args)
	local list: { Plain } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local okScore, score = call("AntiCheatService", "Score", p)
		local okLic, licence = call("ProgressionService", "Licence", p)
		local okFloors, floors = call("TowerService", "Floors", p)
		local okData, data = call("DataService", "Get", p)
		local mod = if okData and type(data) == "table" and type(data.Mod) == "table" then data.Mod else nil
		local muted = p:GetAttribute("MutedUntil")
		table.insert(list, {
			UserId = p.UserId,
			Name = p.Name,
			DisplayName = p.DisplayName,
			Licence = if okLic and Util.IsFinite(licence) then licence else 1,
			Floors = if okFloors and Util.IsFinite(floors) then floors else 0,
			PingMs = p:GetAttribute("PingMs") or 0,
			Suspicion = if okScore and Util.IsFinite(score) then score else 0,
			IsAdmin = AdminService.IsAdmin(p),
			Role = roleOf(p),
			MutedUntil = if type(muted) == "number" then muted else nil,
			Warnings = if mod and Util.IsFinite(mod.Warnings) then mod.Warnings else 0,
			Frozen = p:GetAttribute("AdminFrozen") == true,
			Minutes = math.floor((os.clock() - (joinedAt[p] or os.clock())) / 60),
		})
	end
	return true, "OK", list
end

Actions.Kick = function(admin, args, ctx)
	-- all/others = alle kicken: nur mit KickAll (Besitzer), sonst gesperrt
	if Staff.IsMass(args.Target) then
		if not can(admin, "KickAll") then
			return false, L(admin, "admin.cmd.mass")
		end
		return Actions.KickAll(admin, { Reason = args.Reason }, ctx)
	end
	local targets, err = resolveTargets(admin, args.Target)
	if #targets == 0 then
		return false, err or L(admin, "admin.noTarget")
	end
	local mass = massError(admin, args.Target, #targets)
	if mass then
		return false, mass
	end
	local kept, skipped, hadSelf = filterRank(admin, targets, false)
	if #kept == 0 then
		return false, rankError(admin, skipped, hadSelf)
	end
	local raw = cleanText(args.Reason, MAX_REASON)
	local filtered = if raw then filterBroadcast(raw, admin.UserId) else nil
	for _, p in ipairs(kept) do
		if p.Parent == Players then
			p:Kick(filtered or L(p, "admin.kickDefault"))
		end
	end
	return true, withSkipped(admin, L(admin, "admin.kicked", names(kept)), #skipped)
end

-- Sperr-Dauer für den Kick-Text: "dauerhaft" oder "noch 2 h 5 min"
local function banUntilText(p: Player, untilT: number): string
	if untilT == -1 then
		return L(p, "admin.ban2.forever")
	end
	return L(p, "admin.ban2.left", Format.Duration(math.max(0, untilT - os.time()), langOf(p)))
end

-- Benutzername -> UserId (online ohne Abfrage; sonst Lookup-Limiter je Handelndem, pcall). Yieldet.
local function userIdFromName(admin: Player, name: any): (number?, string?)
	if
		type(name) ~= "string"
		or #name < UNBAN_NAME_MIN
		or #name > UNBAN_NAME_MAX
		or not string.match(name, "^[%w_]+$")
	then
		return nil, L(admin, "core.invalid")
	end
	local lower = string.lower(name)
	for _, p in ipairs(Players:GetPlayers()) do
		if string.lower(p.Name) == lower then
			return p.UserId, nil
		end
	end
	if not lookupLimiter.Check(admin) then
		return nil, L(admin, "admin.cmd.tooFast")
	end
	local ok, id = pcall(function()
		return Players:GetUserIdFromNameAsync(name)
	end)
	if not ok or not isInt(id) or id <= 0 then
		return nil, L(admin, "admin.role.notFound", name)
	end
	return id, nil
end

-- UserId -> Benutzername (online direkt; sonst Lookup-Limiter, pcall; Fehler -> nil). Yieldet.
local function nameFromUserId(admin: Player, userId: number): string?
	local online = Players:GetPlayerByUserId(userId)
	if online then
		return online.Name
	end
	if userId <= 0 or not lookupLimiter.Check(admin) then
		return nil
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(name) == "string" and name ~= "" then
		return string.sub(name, 1, MAX_NAME)
	end
	return nil
end

-- Bann: online per Ziel (TempBan bis TempBanMax der Rolle) oder offline per UserId/Name (Recht Ban). Rang-Regel mit
-- Offline-Rang (Gruppe!), Grund gefiltert, Roblox-Bann + eigene Liste (StaffService.AddBan); fällt BanAsync aus, gilt
-- die eigene Liste und Online-Ziele werden gekickt (kein Abbruch).
Actions.Ban = function(admin, args, ctx)
	local seconds = Core.BanSeconds(args)
	if seconds == nil or (seconds ~= -1 and seconds < 60) then
		return false, L(admin, "admin.banDuration")
	end
	local maxTable = STAFF.TempBanMax
	local role = roleOf(admin)
	local max = if type(maxTable) == "table" and role then maxTable[role] else nil
	if Util.IsFinite(max) and max ~= -1 and (seconds == -1 or seconds > max) then
		return false, L(admin, "admin.cmd.maxDuration", Format.Duration(max, langOf(admin)))
	end
	local ids: { number } = {}
	local namesById: { [number]: string } = {}
	local onlineById: { [number]: Player } = {}
	if args.UserId ~= nil or args.Name ~= nil then
		if not can(admin, "Ban") then
			return false, L(admin, "admin.ban2.onlineOnly")
		end
		local id: number? = nil
		local typedName: string? = nil
		if args.UserId ~= nil then
			local n = tonumber(args.UserId)
			if not n or n % 1 ~= 0 then
				return false, L(admin, "core.invalid")
			end
			id = n
		else
			local found, err = userIdFromName(admin, args.Name)
			if not found then
				return false, err or L(admin, "core.invalid")
			end
			id = found
			typedName = args.Name
		end
		local uid = id :: number
		table.insert(ids, uid)
		local online = Players:GetPlayerByUserId(uid)
		if online then
			onlineById[uid] = online
			namesById[uid] = online.Name
		elseif typedName then
			namesById[uid] = typedName
		else
			namesById[uid] = (if uid > 0 then nameFromUserId(admin, uid) else nil) or tostring(uid)
		end
	else
		if Staff.IsMass(args.Target) then
			return false, L(admin, "admin.cmd.massBan") -- alle auf einmal sperren geht nie
		end
		local targets, err = resolveTargets(admin, args.Target)
		if #targets == 0 then
			return false, err or L(admin, "admin.noTarget")
		end
		local mass = massError(admin, args.Target, #targets, "admin.cmd.massBan")
		if mass then
			return false, mass
		end
		for _, p in ipairs(targets) do
			table.insert(ids, p.UserId)
			namesById[p.UserId] = p.Name
			onlineById[p.UserId] = p
		end
	end
	-- Rang-Regel (offline: gespeicherte Rolle + Gruppen-Rang; unbekannt = geschützt)
	local myRank = rankOf(admin)
	local valid: { number } = {}
	local skipped = 0
	local lastError = L(admin, "admin.noTarget")
	for _, id in ipairs(ids) do
		local online = onlineById[id]
		local name = namesById[id] or tostring(id)
		if id == admin.UserId then
			lastError = L(admin, "admin.notSelf")
		elseif id <= 0 then
			lastError = L(admin, "admin.studioUser")
		else
			local rank, known = 0, true
			if online then
				rank = rankOf(online)
			else
				if groupEnabled() and not lookupLimiter.Check(admin) then
					return false, L(admin, "admin.cmd.tooFast")
				end
				rank, known = rankOfUserIdAsync(id)
			end
			if not known then
				skipped += 1
				lastError = L(admin, "admin.cmd.rankUnknown", name)
			elseif not Staff.CanActOn(myRank, rank) then
				skipped += 1
				lastError = L(admin, "admin.cmd.rank", name)
			elseif #valid < 50 then
				table.insert(valid, id)
			end
		end
	end
	if #valid == 0 then
		return false, lastError
	end
	-- Grund: für Spieler sichtbar -> gefiltert (Fehler = Standard-Grund); der Rohtext steht nur im privaten Beweis
	local displayMax = tonumber(SEC.BanDisplayMax) or 400
	local raw = cleanText(args.Reason, displayMax)
	local filtered = if raw then filterBroadcast(raw, admin.UserId) else nil
	local reason = truncate(if filtered and filtered ~= "" then filtered else L(admin, "admin.banDefault"), displayMax)
	local label = if seconds == -1
		then L(admin, "admin.ban2.forever")
		elseif type(args.Duration) == "string" and #args.Duration <= 12 then args.Duration
		else Format.Duration(seconds, langOf(admin))
	local evidence: { string } = {
		("Gebannt von %s (%d, %s), %s"):format(admin.Name, admin.UserId, role or "-", label),
	}
	if raw and raw ~= reason then
		table.insert(evidence, "Grund: " .. raw)
	end
	local privateNote = cleanText(args.Private, SEC.BanPrivateMax or 1000)
	if privateNote then
		table.insert(evidence, privateNote)
	end
	for _, id in ipairs(valid) do
		local online = onlineById[id]
		if online then
			local okSnap, snap = call("AntiCheatService", "Snapshot", online)
			if okSnap and type(snap) == "table" then
				local violations: { string } = {}
				if type(snap.Violations) == "table" then
					for key, n in pairs(snap.Violations) do
						table.insert(violations, ("%s×%s"):format(tostring(key), tostring(n)))
					end
				end
				table.insert(
					evidence,
					("%s: Punkte %s, Verstöße %s, Tempo %s, Minuten %s"):format(
						online.Name,
						tostring(snap.Score),
						if #violations > 0 then table.concat(violations, " ") else "-",
						tostring(snap.Speed),
						tostring(snap.Minutes)
					)
				)
			end
		end
	end
	local duration = if seconds == -1 then -1 else math.max(60, math.floor(seconds))
	local okBan, banErr = pcall(function()
		Players:BanAsync({
			UserIds = valid,
			Duration = duration,
			DisplayReason = reason,
			PrivateReason = truncate(table.concat(evidence, " | "), SEC.BanPrivateMax or 1000),
			ApplyToUniverse = true,
			ExcludeAltAccounts = false,
		})
	end)
	local untilT = if duration == -1 then -1 else os.time() + duration
	local src = if ctx and ctx.Via == "Chat" then "Chat" else "Panel"
	local bannedNames: { string } = {}
	local ownSaved = false
	for _, id in ipairs(valid) do
		local name = namesById[id] or tostring(id)
		table.insert(bannedNames, name)
		-- eigene Liste (Ban_<id> + BanIndex) und Kick-Nachricht an alle Server
		local okAdd, added = call("StaffService", "AddBan", {
			UserId = id,
			Until = untilT,
			Reason = reason,
			By = admin.UserId,
			ByName = admin.Name,
			Name = name,
			Src = src,
		})
		local saved = okAdd and added == true
		ownSaved = ownSaved or saved
		if okBan or saved then
			call("AntiCheatService", "LogBan", {
				UserId = id,
				Name = name,
				Reason = reason,
				Duration = duration,
				By = admin.UserId,
				ByName = admin.Name,
				T = os.time(),
				Active = true,
				Auto = false,
			})
		end
	end
	local nameList = table.concat(bannedNames, ", ")
	if ctx then
		ctx.Target = nameList
	end
	if not okBan then
		-- Roblox-Bann nicht erreichbar: kein Abbruch – Online-Ziele jetzt kicken, die eigene Liste sperrt beim Beitritt
		warn("[Admin] BanAsync fehlgeschlagen: " .. tostring(banErr))
		for _, id in ipairs(valid) do
			local p = onlineById[id] or Players:GetPlayerByUserId(id)
			if p and p.Parent == Players then
				p:Kick(L(p, "admin.ban2.kick", banUntilText(p, untilT), reason))
			end
		end
		if ownSaved then
			return false, L(admin, "admin.ban2.fallback", nameList)
		end
		return false, L(admin, "admin.banFailed", tostring(banErr))
	end
	return true, withSkipped(admin, L(admin, "admin.banned", label, nameList), skipped)
end

-- W26: Entbannen per UserId ODER Name (auch offline), optionaler Grund (gefiltert). Moderatoren nur eigene Zeit-Banns
-- (Staff.CanUnban mit dem Eintrag aus BanIndex/Ban_<id>). Roblox-Fehler wird toleriert, wenn ein eigener Eintrag bestand.
Actions.Unban = function(admin, args, ctx)
	local hasId, hasName = args.UserId ~= nil, args.Name ~= nil
	if hasId == hasName then
		return false, L(admin, "core.invalid") -- genau eins von UserId/Name
	end
	local id: number? = nil
	if hasId then
		local n = tonumber(args.UserId)
		if not n or n % 1 ~= 0 then
			return false, L(admin, "core.invalid")
		end
		id = n
	else
		local found, err = userIdFromName(admin, args.Name)
		if not found then
			return false, err or L(admin, "core.invalid")
		end
		id = found
	end
	local uid = id :: number
	if uid <= 0 then
		return false, L(admin, "admin.studioUser")
	end
	local okEntry, rawEntry = call("StaffService", "BanEntry", uid)
	local entry: Plain? = if okEntry and type(rawEntry) == "table" then rawEntry else nil
	local allowed, key = Staff.CanUnban(roleOf(admin), admin.UserId, entry, STAFF)
	if not allowed then
		return false, L(admin, key or "admin.cmd.denied")
	end
	local raw = cleanText(args.Reason, tonumber(STAFF.UnbanReasonMax) or 120)
	local reason = if raw then filterBroadcast(raw, admin.UserId) else nil
	local okRoblox, err = pcall(function()
		Players:UnbanAsync({ UserIds = { uid }, ApplyToUniverse = true })
	end)
	call("StaffService", "RemoveBan", uid, "Unban")
	call("AntiCheatService", "MarkUnbanned", uid)
	local entryName = if entry and type(entry.Name) == "string" and entry.Name ~= "" then entry.Name else nil
	local name = entryName or (if hasName then args.Name else nil) or nameFromUserId(admin, uid) or tostring(uid)
	if ctx then
		ctx.Target = name
	end
	if not okRoblox and entry == nil then
		return false, L(admin, "admin.unbanFailed", tostring(err))
	end
	local text = L(admin, "admin.bans.done", name)
	if not okRoblox then
		text ..= " " .. L(admin, "admin.bans.robloxFailed")
	end
	if reason and reason ~= "" then
		text ..= " · " .. reason
	end
	return true, text, { UserId = uid, Name = name }
end

Actions.BanList = function(admin, _args)
	local ok, list = call("AntiCheatService", "BanLog")
	local out: { any } = {}
	if ok and type(list) == "table" then
		for i, entry in ipairs(list) do
			if i > MAX_LIST then
				break
			end
			table.insert(out, entry)
		end
	end
	return true, L(admin, "admin.banList", #out), out
end

Actions.BanHistory = function(admin, args)
	if RunService:IsStudio() then
		return false, L(admin, "admin.liveOnly")
	end
	local id = tonumber(args.UserId)
	if not id or id % 1 ~= 0 or id <= 0 then
		return false, L(admin, "core.invalid")
	end
	local ok, page = pcall(function()
		local pages = Players:GetBanHistoryAsync(id)
		return pages:GetCurrentPage()
	end)
	if not ok or type(page) ~= "table" then
		return false, L(admin, "admin.banFailed", tostring(page))
	end
	local out: { any } = {}
	for i = #page, 1, -1 do -- neueste zuerst
		local entry = page[i]
		if type(entry) == "table" then
			table.insert(out, {
				Ban = entry.Ban == true,
				DisplayReason = tostring(entry.DisplayReason or ""),
				PrivateReason = tostring(entry.PrivateReason or ""),
				Duration = tonumber(entry.Duration) or 0,
				StartTime = tostring(entry.StartTime or ""),
			})
		end
		if #out >= 10 then
			break
		end
	end
	return true, L(admin, "admin.banHistory", #out), out
end

-- W26 Tab „Banns“: aktive Banns aus der eigenen Liste (StaffService.BanList) mit Suche/Seiten; je Eintrag, ob DIESER
-- Handelnde entbannen darf. Danach im Hintergrund Abgleich der Seite mit Roblox (Zustände beim nächsten Laden).
local BAN_STATES: { [string]: boolean } = { Active = true, Unbanned = true, Expired = true, Unknown = true }

Actions.Bans = function(admin, args)
	local query: string? = nil
	if type(args.Query) == "string" then
		local clean = string.gsub(string.gsub(string.sub(args.Query, 1, 30), "^%s+", ""), "%s+$", "")
		query = if clean ~= "" and utf8.len(clean) ~= nil then clean else nil
	end
	local page = if isInt(args.Page) then math.clamp(args.Page, 1, 100) else 1
	if not has("StaffService", "BanList") then
		return false, L(admin, "admin.unavailable", "StaffService")
	end
	local ok, result = call("StaffService", "BanList", { Query = query, Page = page })
	if not ok or type(result) ~= "table" then
		return false, L(admin, "core.error")
	end
	local role = roleOf(admin)
	local t = os.time()
	local entries: { Plain } = {}
	local ids: { number } = {}
	if type(result.Entries) == "table" then
		for _, e in ipairs(result.Entries) do
			if type(e) == "table" and isInt(e.UserId) and Util.IsFinite(e.Until) then
				local untilT = e.Until
				local canUnban = Staff.CanUnban(role, admin.UserId, e, STAFF)
				table.insert(entries, {
					UserId = e.UserId,
					Name = string.sub(tostring(e.Name or e.UserId), 1, MAX_NAME),
					Reason = truncate(tostring(e.Reason or ""), 400),
					By = if isInt(e.By) then e.By else 0,
					ByName = string.sub(tostring(e.ByName or ""), 1, MAX_NAME),
					T = if Util.IsFinite(e.T) then e.T else 0,
					Until = untilT,
					Left = if untilT == -1 then -1 else math.max(0, untilT - t),
					State = if type(e.State) == "string" and BAN_STATES[e.State] then e.State else "Active",
					Src = if type(e.Src) == "string" then string.sub(e.Src, 1, 12) else nil,
					CanUnban = canUnban == true,
				})
				table.insert(ids, e.UserId)
			end
			if #entries >= MAX_LIST then
				break
			end
		end
	end
	local total = if isInt(result.Total) then result.Total else #entries
	local pages = if isInt(result.Pages) then math.max(1, result.Pages) else 1
	if #ids > 0 and has("StaffService", "Reconcile") then
		task.spawn(function()
			call("StaffService", "Reconcile", ids)
		end)
	end
	return true,
		L(admin, "admin.bans.loaded", total),
		{
			Entries = entries,
			Total = total,
			Page = if isInt(result.Page) then result.Page else page,
			Pages = pages,
			Reconciled = result.Reconciled == true,
			CanAll = can(admin, "Unban"),
		}
end

Actions.Warn = function(admin, args)
	local max = SEC.WarnMax or 150
	local text = cleanText(args.Text, max)
	if not text then
		return false, L(admin, "admin.textLen", max)
	end
	local targets, err = resolveTargets(admin, args.Target)
	if #targets == 0 then
		return false, err or L(admin, "admin.noTarget")
	end
	local mass = massError(admin, args.Target, #targets)
	if mass then
		return false, mass
	end
	-- sich selbst nur als einziges Ziel (zum Ausprobieren), sonst Rang-Regel
	local kept, skipped, hadSelf = filterRank(admin, targets, #targets == 1)
	if #kept == 0 then
		return false, rankError(admin, skipped, hadSelf)
	end
	local filtered = filterBroadcast(text, admin.UserId)
	if not filtered then
		return false, L(admin, "admin.filterDown")
	end
	local warned: { Player } = {}
	for _, p in ipairs(kept) do
		if p.Parent == Players then
			effect(p, "AdminWarn", 1, { Text = filtered })
			table.insert(warned, p)
			local okData, data = call("DataService", "Get", p)
			if okData and type(data) == "table" then
				if type(data.Mod) ~= "table" then
					data.Mod = {}
				end
				data.Mod.Warnings = (tonumber(data.Mod.Warnings) or 0) + 1
			end
		end
	end
	if #warned == 0 then
		return false, L(admin, "admin.noTarget")
	end
	return true, withSkipped(admin, L(admin, "admin.warned", names(warned)), #skipped)
end

-- Einfrieren: Rang-Regel, Masse nur mit MassTarget, Einfrierer gemerkt (frozenBy). Auftauen: Staff.CanUndo (nicht für
-- sich selbst außer Besitzer; nur mit Rang ≥ dem des Einfrierers, §16.2 Nr. 5).
Actions.Freeze = function(admin, args)
	local on = args.On ~= false
	local targets, err = resolveTargets(admin, args.Target)
	if #targets == 0 then
		return false, err or L(admin, "admin.noTarget")
	end
	local myRank = rankOf(admin)
	if on then
		local mass = massError(admin, args.Target, #targets)
		if mass then
			return false, mass
		end
		local kept, skipped, hadSelf = filterRank(admin, targets, false)
		if #kept == 0 then
			return false, rankError(admin, skipped, hadSelf)
		end
		for _, p in ipairs(kept) do
			freeze(p, true)
			p:SetAttribute("AdminFrozen", true)
			-- ein ranghöherer Einfrierer bleibt eingetragen (sonst könnte ein niedrigerer Rang ihn "übernehmen")
			local previous = frozenBy[p]
			if previous == nil or punisherRank(previous) <= myRank then
				frozenBy[p] = admin.UserId
			end
			call("PlayerStateService", "Notify", p, "admin.cmd.youFrozen", nil, "Alarm")
		end
		return true, withSkipped(admin, L(admin, "admin.frozen", names(kept)), #skipped)
	end
	local isOwner = AdminService.IsAdmin(admin)
	local done: { Player } = {}
	local skipped: { Player } = {}
	for _, p in ipairs(targets) do
		if Staff.CanUndo(myRank, punisherRank(frozenBy[p]), p == admin, isOwner) then
			freeze(p, false)
			p:SetAttribute("AdminFrozen", nil)
			frozenBy[p] = nil
			if p ~= admin then
				call("PlayerStateService", "Notify", p, "admin.cmd.youUnfrozen", nil, "Success")
			end
			table.insert(done, p)
		else
			table.insert(skipped, p)
		end
	end
	if #done == 0 then
		if #skipped == 1 and skipped[1] == admin then
			return false, L(admin, "admin.notSelf")
		end
		return false, L(admin, "admin.cmd.rank", names(skipped))
	end
	return true, withSkipped(admin, L(admin, "admin.unfrozen", names(done)), #skipped)
end

Actions.Bring = function(admin, args)
	local base = footOf(admin)
	if not base then
		return false, L(admin, "admin.noCharacter")
	end
	local targets, err = resolveTargets(admin, args.Target)
	if #targets == 0 then
		return false, err or L(admin, "admin.noTarget")
	end
	local mass = massError(admin, args.Target, #targets)
	if mass then
		return false, mass
	end
	local kept, skipped, hadSelf = filterRank(admin, targets, false)
	if #kept == 0 then
		return false, rankError(admin, skipped, hadSelf)
	end
	local done: { Player } = {}
	for _, p in ipairs(kept) do
		if p.Character then
			local i = #done
			local offset = CFrame.new(((i % 5) - 2) * 3, 0, -5 - math.floor(i / 5) * 3)
			if teleport(p, base * offset) then
				table.insert(done, p)
			end
		end
	end
	if #done == 0 then
		return false, L(admin, "admin.noTarget")
	end
	return true, withSkipped(admin, L(admin, "admin.brought", names(done)), #skipped)
end

Actions.Goto = function(admin, args)
	local target, err = resolveOne(admin, args.Target)
	if not target then
		return false, err or ""
	end
	local base = footOf(target)
	if not base or target == admin then
		return false, L(admin, "admin.noTarget")
	end
	teleport(admin, base * CFrame.new(0, 0, 4))
	return true, L(admin, "admin.went", target.DisplayName)
end

Actions.Visit = function(admin, args)
	local target, err = resolveOne(admin, args.Target)
	if not target then
		return false, err or ""
	end
	local okPlot, plot = call("PlotService", "PlotOf", target)
	if not okPlot or not isInt(plot) then
		return false, L(admin, "admin.noPlot")
	end
	local okCf, cf = call("PlotService", "LobbyCFrame", plot)
	if not okCf or typeof(cf) ~= "CFrame" then
		return false, L(admin, "admin.noPlot")
	end
	if not teleport(admin, cf) then
		return false, L(admin, "admin.noCharacter")
	end
	return true, L(admin, "admin.visited", target.DisplayName)
end

Actions.PlayerData = function(admin, args)
	local target, err = resolveOne(admin, args.Target)
	if not target then
		return false, err or ""
	end
	local ok, data = call("DataService", "Get", target)
	if not ok or type(data) ~= "table" then
		return false, L(admin, "core.loading")
	end
	local function count(t: any): number
		local n = 0
		if type(t) == "table" then
			for _ in pairs(t) do
				n += 1
			end
		end
		return n
	end
	local depot = if type(data.Depot) == "table" then data.Depot else {}
	local prog = if type(data.Prog) == "table" then data.Prog else {}
	local tower = if type(data.Tower) == "table" then data.Tower else {}
	local purchases = if type(data.Purchases) == "table" then data.Purchases else {}
	local mod = if type(data.Mod) == "table" then data.Mod else {}
	local league = if type(data.League) == "table" then data.League else {}
	local summary = {
		UserId = target.UserId,
		Name = target.Name,
		Credits = data.Credits,
		AkyCash = math.floor((tonumber(depot.Cash) or 0) / 100),
		AkyBasis = math.floor((tonumber(depot.Basis) or 0) / 100),
		Floors = count(tower.Floors),
		Licence = prog.Licence,
		Xp = prog.Xp,
		Stars = type(prog.Prestige) == "table" and prog.Prestige.Stars or 0,
		Ipos = type(prog.Prestige) == "table" and prog.Prestige.Count or 0,
		LeagueTainted = league.Tainted == true,
		AdminGiftCredits = type(data.Stats) == "table" and tonumber(data.Stats.AdminCredits) or 0,
		GiftSpeed = target:GetAttribute(GIFT_SPEED) or "-",
		Cars = count(type(data.Garage) == "table" and data.Garage.Cars),
		Watches = count(type(data.Life) == "table" and data.Life.Watches),
		Playtime = math.floor((tonumber(data.Playtime) or 0) / 60),
		Sessions = data.Sessions,
		RobuxSpent = purchases.RobuxSpent or 0,
		Receipts = count(purchases.Receipts),
		Warnings = mod.Warnings or 0,
		HardKicks = count(mod.HardKicks),
		NoSave = select(2, call("DataService", "IsNoSave", target)) == true,
	}
	return true, L(admin, "admin.dataShown", target.DisplayName), summary
end

Actions.Receipts = function(admin, args)
	local target, err = resolveOne(admin, args.Target)
	if not target then
		return false, err or ""
	end
	local ok, data = call("DataService", "Get", target)
	if not ok or type(data) ~= "table" then
		return false, L(admin, "core.loading")
	end
	local out: { any } = {}
	local receipts = type(data.Purchases) == "table" and data.Purchases.Receipts
	if type(receipts) == "table" then
		for i = #receipts, 1, -1 do
			local r = receipts[i]
			if type(r) == "table" then
				table.insert(
					out,
					{ Id = tostring(r.Id), T = tonumber(r.T) or 0, Key = tostring(r.Key or r.Product or "") }
				)
			elseif type(r) == "string" then
				table.insert(out, { Id = r, T = 0, Key = "" })
			end
			if #out >= MAX_LIST then
				break
			end
		end
	end
	return true, L(admin, "admin.receipts", #out, target.DisplayName), out
end

local function productExists(key: any): boolean
	local shop = Config.Shop
	if type(key) ~= "string" or type(shop) ~= "table" then
		return false
	end
	local byKey = shop.ProductsByKey
	if type(byKey) == "table" and byKey[key] ~= nil then
		return true
	end
	local passes = shop.PassesByKey
	return type(passes) == "table" and passes[key] ~= nil
end

Actions.Regrant = function(admin, args)
	local target, err = resolveOne(admin, args.Target)
	if not target then
		return false, err or ""
	end
	if not productExists(args.ProductKey) then
		return false, L(admin, "admin.badProduct")
	end
	local ok, granted, message = call("MonetizationService", "SimulatePurchase", target, args.ProductKey)
	if not ok then
		return false, L(admin, "admin.unavailable", "MonetizationService")
	end
	if granted ~= true then
		return false, tostring(message or L(admin, "core.error"))
	end
	return true, L(admin, "admin.regranted", tostring(args.ProductKey) .. " → " .. target.DisplayName)
end

Actions.ResetData = function(admin, args)
	local target, err = resolveOne(admin, args.Target)
	if not target then
		return false, err or ""
	end
	if args.Confirm ~= true then
		return false, L(admin, "admin.confirmNeeded")
	end
	local ok, result = call("DataService", "Reset", target)
	if not ok or result ~= true then
		return false, L(admin, "admin.resetFailed")
	end
	call("PlayerStateService", "Notify", target, "core.dataReset", nil, "Alarm")
	call("PlayerStateService", "MarkDirty", target)
	return true, L(admin, "admin.reset", target.DisplayName)
end

-- =====================================================================
-- AKTIONEN – KRÄFTE (eigene Attribute; Server ehrt sie nur bei IsAdmin)
-- =====================================================================
Actions.SetPower = function(admin, args)
	local name = args.Name
	local kind = if type(name) == "string" then POWERS[name] else nil
	if not kind then
		return false, L(admin, "admin.powerUnknown")
	end
	local value: any = nil
	if kind == "bool" then
		value = if args.Value == true then true else nil
		if name == "CanFly" then
			value = args.Value ~= false -- Fliegen ist Standard (an); aus = false
		end
	else
		local limits = SEC.Powers and SEC.Powers[kind]
		local lo = if type(limits) == "table" then tonumber(limits.Min) or 0 else 0
		local hi = if type(limits) == "table" then tonumber(limits.Max) or 100 else 100
		if Util.IsFinite(args.Value) then
			local v = math.clamp(args.Value, lo, hi)
			if v > lo + 0.001 then
				value = if kind == "Jump" then math.floor(v * 10 + 0.5) / 10 else math.floor(v + 0.5)
			end
		end
	end
	admin:SetAttribute(name, value)
	if name == "AdminInvisible" then
		setInvisible(admin, value == true)
	end
	local shown = if value == nil or value == false
		then L(admin, "admin.off")
		elseif value == true then L(admin, "admin.on")
		else tostring(value)
	return true, L(admin, "admin.powerSet", name, shown), { Name = name, Value = value }
end

-- Speed/Sprung schenken (Ziel-Feld me/all/others/Name): { Target, Speed?, Jump?, Seconds? | Minutes? (0 = bis Reset),
-- Reset? } – Seconds (Chat "/speed Name 50 90") hat Vorrang vor Minutes (Panel). Geschenke prüfen keinen Rang.
Actions.GiveSpeed = function(admin, args)
	local targets, err = resolveTargets(admin, args.Target)
	if #targets == 0 then
		return false, err or L(admin, "admin.noTarget")
	end
	if args.Reset == true then
		local cleared: { Player } = {}
		for _, p in ipairs(targets) do
			if clearGift(p, p ~= admin) then
				table.insert(cleared, p)
			end
		end
		if #cleared == 0 then
			return false, L(admin, "admin.giftNone")
		end
		return true, L(admin, "admin.giftReset", names(cleared))
	end
	local powers: Plain = SEC.Powers or {}
	local speedRange: Plain = powers.Speed or { Min = 16, Max = 200 }
	local jumpRange: Plain = powers.Jump or { Min = DEFAULT_JUMP, Max = 100 }
	local speedMin = tonumber(speedRange.Min) or 16
	local jumpMin = tonumber(jumpRange.Min) or DEFAULT_JUMP
	local speed: number? = nil
	if Util.IsFinite(args.Speed) then
		speed = math.floor(math.clamp(args.Speed, speedMin, tonumber(speedRange.Max) or 200) + 0.5)
		if (speed :: number) <= speedMin then
			speed = nil -- Standard-Tempo = kein Geschenk
		end
	end
	local jump: number? = nil
	if Util.IsFinite(args.Jump) then
		jump = math.floor(math.clamp(args.Jump, jumpMin, tonumber(jumpRange.Max) or 100) * 10 + 0.5) / 10
		if (jump :: number) <= jumpMin + 0.05 then
			jump = nil
		end
	end
	if speed == nil and jump == nil then
		return false, L(admin, "admin.giftEmpty")
	end
	local maxMinutes = math.max(1, math.floor(tonumber(powers.GiftMaxMinutes) or 120))
	local seconds = 0
	if Util.IsFinite(args.Seconds) then
		local wanted = math.floor(args.Seconds)
		seconds = if wanted <= 0 then 0 else math.clamp(wanted, 10, maxMinutes * 60)
	elseif Util.IsFinite(args.Minutes) then
		seconds = math.clamp(math.floor(args.Minutes), 0, maxMinutes) * 60
	end
	local minutes = math.ceil(seconds / 60)
	local untilT: number? = if seconds > 0 then now() + seconds else nil
	local shownSpeed = speed or defaultWalk()
	local shownJump = jump or DEFAULT_JUMP
	for _, p in ipairs(targets) do
		local old = tonumber(p:GetAttribute(GIFT_SPEED))
		if old and old > shownSpeed then
			call("AntiCheatService", "Grace", p, "Impulse", 2, old * 1.25) -- langsamer werden ist nie ein Verstoß
		end
		p:SetAttribute(GIFT_SPEED, speed)
		p:SetAttribute(GIFT_JUMP, jump)
		p:SetAttribute(GIFT_UNTIL, untilT)
		applyGift(p)
		if p ~= admin then
			call(
				"PlayerStateService",
				"Notify",
				p,
				if minutes > 0 then "admin.giftGot" else "admin.giftGotOpen",
				{ shownSpeed, shownJump, minutes },
				"Success"
			)
		end
	end
	local lower = if type(args.Target) == "string" then string.lower(args.Target) else ""
	if lower == "all" or lower == "others" then
		announceAbuse(admin, "SpeedGift", false) -- Geschenk gilt auf diesem Server
	end
	local duration = if minutes > 0 then L(admin, "admin.giftMinutes", minutes) else L(admin, "admin.giftOpen")
	return true, L(admin, "admin.giftGiven", shownSpeed, shownJump, duration, names(targets))
end

-- Zuschauen auch bei fernen Spielern (StreamingEnabled): Replikation um das Ziel, Client folgt mit der Kamera
Actions.Spectate = function(admin, args)
	if args.On == false then
		admin.ReplicationFocus = nil
		return true, L(admin, "admin.spectateStop")
	end
	local target, err = resolveOne(admin, args.Target)
	if not target then
		return false, err or ""
	end
	if target == admin then
		return false, L(admin, "admin.notSelf")
	end
	if not canActOn(admin, target) then
		return false, L(admin, "admin.cmd.rank", target.DisplayName)
	end
	local root = rootOf(target)
	if not root then
		return false, L(admin, "admin.noTarget")
	end
	admin.ReplicationFocus = root
	return true, L(admin, "admin.spectating", target.DisplayName)
end

-- =====================================================================
-- AKTIONEN – GELD & ITEMS (Turm-Seite über ShopService.Grant, AKY/Lizenz taint die Liga-Woche)
-- =====================================================================
Actions.Give = function(admin, args)
	-- negative CR = abziehen (Besitzer-Wunsch 18 "geben oder abziehen"): höchstens das Guthaben, Senke "Admin"
	local raw = if type(args.Grant) == "table" then args.Grant else nil
	if raw and Util.IsFinite(raw.Credits) and raw.Credits <= -1 then
		if not has("ShopService", "Debit") then
			return false, L(admin, "admin.unavailable", "ShopService")
		end
		local want = math.floor(math.min(-raw.Credits, MAX_GIVE_CREDITS))
		local targets, err = resolveTargets(admin, args.Target)
		if #targets == 0 then
			return false, err or L(admin, "admin.noTarget")
		end
		-- Abziehen ist strafend: nur bei niedrigerem Rang (Besitzer gegen Besitzer im Studio geschützt)
		local kept, skipped, hadSelf = filterRank(admin, targets, false)
		if #kept == 0 then
			return false, rankError(admin, skipped, hadSelf)
		end
		local taken: { Player } = {}
		local total = 0 -- tatsächlich abgezogen (höchstens das jeweilige Guthaben)
		for _, p in ipairs(kept) do
			local okBal, balance = call("ShopService", "Balance", p)
			local amount = math.min(want, if okBal and Util.IsFinite(balance) then math.floor(balance) else 0)
			if amount >= 1 then
				local okDebit, debited = call("ShopService", "Debit", p, amount, "Admin")
				if okDebit and debited == true then
					table.insert(taken, p)
					total += amount
				end
			end
		end
		if #taken == 0 then
			return false, L(admin, "admin.giveFailed")
		end
		return true, withSkipped(admin, L(admin, "admin.taken", total, names(taken)), #skipped)
	end
	local grant = sanitizeGrant(args.Grant)
	if not grant then
		return false, L(admin, "admin.giveEmpty")
	end
	if not has("ShopService", "Grant") then
		return false, L(admin, "admin.unavailable", "ShopService")
	end
	local all, err = resolveTargets(admin, args.Target)
	if #all == 0 then
		return false, err or L(admin, "admin.noTarget")
	end
	-- Nicht-Besitzer beschenken sich nie selbst (auch nicht über me/all/Listen, §16.2 Nr. 6)
	local isOwner = AdminService.IsAdmin(admin)
	local targets = Core.GiftTargets(all, admin, isOwner) :: { Player }
	if #targets == 0 then
		return false, L(admin, "admin.cmd.noSelfGive")
	end
	-- CR-Deckel für Nicht-Besitzer: je Befehl und je Tag (Tageszähler im eigenen Spielstand, serverübergreifend)
	local mod: Plain? = nil
	local reserved = 0
	if grant.Credits and not isOwner then
		local okData, data = call("DataService", "Get", admin)
		if not okData or type(data) ~= "table" then
			return false, L(admin, "core.loading")
		end
		if type(data.Mod) ~= "table" then
			data.Mod = {}
		end
		local m: Plain = data.Mod
		if m.GiveDay ~= utcDay() then
			m.GiveDay = utcDay()
			m.GiveCredits = 0
		end
		local given = if Util.IsFinite(m.GiveCredits) then m.GiveCredits else 0
		local okCap, capKey, capValue = Core.CreditCaps(grant.Credits, #targets, given, STAFF.Credits)
		if not okCap then
			return false, L(admin, capKey or "core.invalid", Format.Credits(capValue or 0, langOf(admin)))
		end
		reserved = grant.Credits * #targets
		m.GiveCredits = given + reserved -- vorab reservieren (parallele Aufrufe), unten auf das Gewährte korrigiert
		mod = m
	end
	local done = grantTo(targets, grant)
	if mod then
		local granted = (grant.Credits or 0) * #done
		mod.GiveCredits = math.max(0, (tonumber(mod.GiveCredits) or 0) - reserved + granted)
	end
	if #done == 0 then
		return false, L(admin, "admin.giveFailed")
	end
	local lower = if type(args.Target) == "string" then string.lower(args.Target) else ""
	if grant.Credits and (lower == "all" or lower == "others") then
		announceAbuse(admin, "MoneyGift", false) -- Admin-Geschenk an alle auf diesem Server (im Konto markiert)
	end
	return true, L(admin, "admin.given", names(done))
end

Actions.GiveAllItems = function(admin, args)
	local kind = args.Kind
	local grant: Plain = {}
	if kind == "Cars" then
		grant.Cars = keysOf(Config.Vehicles and Config.Vehicles.Cars)
	elseif kind == "Watches" then
		grant.Watches = keysOf(Config.Lifestyle and Config.Lifestyle.Watches)
	elseif kind == "Accessories" then
		grant.Accessories = keysOf(Config.Lifestyle and Config.Lifestyle.Accessories)
	elseif kind == "Decor" then
		local decor: { [string]: number } = {}
		for _, key in ipairs(keysOf(Config.Decor and Config.Decor.Items)) do
			decor[key] = 1
		end
		grant.Decor = decor
	else
		return false, L(admin, "core.invalid")
	end
	local clean = sanitizeGrant(grant)
	if not clean then
		return false, L(admin, "admin.giveEmpty")
	end
	local all, err = resolveTargets(admin, args.Target)
	if #all == 0 then
		return false, err or L(admin, "admin.noTarget")
	end
	local targets = Core.GiftTargets(all, admin, AdminService.IsAdmin(admin)) :: { Player }
	if #targets == 0 then
		return false, L(admin, "admin.cmd.noSelfGive")
	end
	local done = grantTo(targets, clean)
	if #done == 0 then
		return false, L(admin, "admin.giveFailed")
	end
	return true, L(admin, "admin.given", names(done))
end

Actions.GiveAky = function(admin, args)
	local aky = tonumber(args.Aky)
	if not aky or aky ~= aky or math.abs(aky) < 1 then
		return false, L(admin, "core.invalid")
	end
	-- negativ = abziehen (Besitzer-Wunsch "geben oder abziehen"; OrderService.AdminCredit zieht höchstens freies AKY ab)
	local cents = math.sign(aky) * math.floor(math.min(math.abs(aky), MAX_GIVE_AKY)) * 100
	local done: { Player } = {}
	local targets, err = resolveTargets(admin, args.Target)
	if #targets == 0 then
		return false, err or L(admin, "admin.noTarget")
	end
	local skipped: { Player } = {}
	if cents < 0 then
		-- Abziehen ist strafend: Rang-Regel (Besitzer gegen Besitzer im Studio geschützt)
		local kept, rankSkipped, hadSelf = filterRank(admin, targets, false)
		if #kept == 0 then
			return false, rankError(admin, rankSkipped, hadSelf)
		end
		targets, skipped = kept, rankSkipped
	else
		targets = Core.GiftTargets(targets, admin, AdminService.IsAdmin(admin)) :: { Player }
		if #targets == 0 then
			return false, L(admin, "admin.cmd.noSelfGive")
		end
	end
	local taken = 0 -- beim Abziehen tatsächlich gebucht (Cent; höchstens das jeweils freie AKY)
	for _, p in ipairs(targets) do
		local okDepot, depot = call("OrderService", "Depot", p)
		local before = if okDepot and type(depot) == "table" and Util.IsFinite(depot.Cash) then depot.Cash else nil
		local ok, result = call("OrderService", "AdminCredit", p, cents)
		if ok and result == true then
			table.insert(done, p)
			if before and Util.IsFinite(depot.Cash) then
				taken += math.max(0, before - depot.Cash)
			end
			-- Wunsch 18: Admin-AKY im Konto markiert (Netto-Vermögen-Bestenliste zeigt die Marke, wie bei Admin-CR)
			local okData, data = call("DataService", "Get", p)
			local stats = if cents > 0 and okData and type(data) == "table" then data.Stats else nil
			if type(stats) == "table" then
				local gifted = stats.AdminAky
				stats.AdminAky = math.min(9e15, (if Util.IsFinite(gifted) then gifted else 0) + cents)
			end
		end
	end
	if #done == 0 then
		return false, L(admin, if cents < 0 then "admin.akyNoneFree" else "admin.giveFailed")
	end
	if cents < 0 then
		return true,
			withSkipped(admin, L(admin, "admin.akyTaken", Format.Aky(taken, langOf(admin)), names(done)), #skipped)
	end
	return true, L(admin, "admin.akyGiven", math.floor(cents / 100), names(done))
end

Actions.SetLicence = function(admin, args)
	local licences = Config.Progression and Config.Progression.Licences or {}
	local idx = tonumber(args.Licence)
	if not idx or idx % 1 ~= 0 or idx < 1 or idx > #licences then
		return false, L(admin, "core.invalid")
	end
	local targets, err = resolveTargets(admin, args.Target)
	if #targets == 0 then
		return false, err or L(admin, "admin.noTarget")
	end
	local done: { Player } = {}
	for _, p in ipairs(targets) do
		local ok, result = call("ProgressionService", "AdminSetLicence", p, idx)
		if ok and result == true then
			table.insert(done, p)
		end
	end
	if #done == 0 then
		return false, L(admin, "admin.noTarget")
	end
	return true, L(admin, "admin.licenceSet", idx, names(done))
end

Actions.SetFloors = function(admin, args)
	local maxFloors = math.floor(tonumber(Config.Tower and Config.Tower.Floors) or 50)
	local n = tonumber(args.Floors)
	if not n or n % 1 ~= 0 or n < 0 or n > maxFloors then
		return false, L(admin, "core.invalid")
	end
	local targets, err = resolveTargets(admin, args.Target)
	if #targets == 0 then
		return false, err or L(admin, "admin.noTarget")
	end
	local done: { Player } = {}
	for _, p in ipairs(targets) do
		local ok, result = call("TowerService", "AdminSetFloors", p, n)
		if ok and result == true then
			table.insert(done, p)
		end
	end
	if #done == 0 then
		return false, L(admin, "admin.noTarget")
	end
	return true, L(admin, "admin.floorsSet", n, names(done))
end

-- =====================================================================
-- AKTIONEN – SERVER
-- =====================================================================
Actions.LockServer = function(admin, args)
	serverLocked = args.On == true
	workspace:SetAttribute("ServerLocked", if serverLocked then true else nil)
	return true, L(admin, if serverLocked then "admin.locked" else "admin.unlockedServer")
end

Actions.KickAll = function(admin, args)
	local raw = cleanText(args.Reason, MAX_REASON)
	local filtered = if raw then filterBroadcast(raw, admin.UserId) else nil
	local count, skipped = 0, 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= admin then
			if canActOn(admin, p) then
				count += 1
				p:Kick(filtered or L(p, "admin.kickAllDefault"))
			else
				skipped += 1 -- gleicher oder höherer Rang bleibt (Teammitglieder ab dem eigenen Rang)
			end
		end
	end
	return true, withSkipped(admin, L(admin, "admin.kickedAll", count), skipped)
end

-- =====================================================================
-- AKTIONEN – MARKT (nur MarketService.Admin; Besitzer-Handelssperre ±120 s)
-- =====================================================================
local function noteOwnerEvent(admin: Player)
	local t = now()
	local lead = tonumber(Config.Market and Config.Market.Admin and Config.Market.Admin.Lead) or 10
	local list = ownerEvents[admin]
	if not list then
		list = {}
		ownerEvents[admin] = list
	end
	table.insert(list, { Issued = t, Start = t + lead })
	local block = tonumber(SEC.OwnerTradeBlockSeconds) or 120
	while #list > MAX_OWNER_EVENTS or (list[1] ~= nil and t > list[1].Start + block) do
		table.remove(list, 1)
	end
end

local function marketAction(admin: Player, kind: string, args: Plain, quiet: boolean?): (boolean, string)
	local action, clean, errKey = Core.MarketArgs(kind, args, nil)
	if not action or not clean then
		return false, L(admin, errKey or "core.invalid")
	end
	local block = tonumber(SEC.OwnerTradeBlockSeconds) or 120
	if action ~= "Resume" and Core.TradeLockBefore(ownerLastTrade[admin], now(), block) then
		return false, L(admin, "admin.tradeLock", block)
	end
	if not has("MarketService", "Admin") then
		return false, L(admin, "admin.unavailable", "MarketService")
	end
	local ok, success, message = call("MarketService", "Admin", action, clean, admin)
	if not ok then
		return false, L(admin, "admin.unavailable", "MarketService")
	end
	if success == true and action ~= "Resume" and action ~= "Normalize" and action ~= "Halt" then
		noteOwnerEvent(admin)
	end
	if success == true and not quiet then
		-- Markt-Events laufen immer global (GlobalBus) -> Besitzer-Ansage ebenfalls auf allen Servern
		announceAbuse(admin, kind, true)
	end
	return success == true, tostring(message or "")
end

Actions.Market = function(admin, args)
	local kind = args.Kind
	if type(kind) ~= "string" or not MARKET_ACTIONS[kind] then
		return false, L(admin, "admin.evUnknown")
	end
	return marketAction(admin, kind, args)
end

Actions.MarketLog = function(admin, _args)
	local tickNow = Clock.Tick()
	local okWin, windows = call("MarketService", "AdminWindowsBetween", tickNow - 6 * 3600, tickNow + 3600)
	local okNews, news = call("MarketService", "RecentNews", 50)
	local okStats, market = call("MarketService", "Stats")
	local okLocal, localMarket = call("MarketService", "IsLocalMarket")
	local items: { Plain } = {}
	if okNews and type(news) == "table" then
		for _, n in ipairs(news) do
			if
				type(n) == "table"
				and (
					n.Kind == "Admin"
					or n.Kind == "Halt"
					or n.Kind == "Resume"
					or n.Kind == "Ipo"
					or n.Kind == "Crash"
					or n.Kind == "Rally"
				)
			then
				table.insert(
					items,
					{ T = n.T, Kind = n.Kind, Key = n.Key, I = n.I, Sector = n.Sector, Dir = n.Dir, Text = n.Text }
				)
			end
			if #items >= 30 then
				break
			end
		end
	end
	return true,
		L(admin, "admin.marketLog"),
		{
			Windows = if okWin and type(windows) == "table" then windows else {},
			News = items,
			Market = if okStats then market else nil,
			LocalMarket = okLocal and localMarket == true,
			Tick = tickNow,
			Blocked = AdminService.OwnerTradeBlocked(admin),
		}
end

-- =====================================================================
-- AKTIONEN – EVENTS (Ansage, Admin-Abuse-Katalog, Samstags-Show)
-- =====================================================================
Actions.Announce = function(admin, args)
	local max = SEC.AnnounceMax or 200
	local text = cleanText(args.Text, max)
	if not text then
		return false, L(admin, "admin.textLen", max)
	end
	if os.clock() - announceAt < (tonumber(EV.AnnounceGap) or 1) then
		return false, L(admin, "core.tooFast")
	end
	-- Nicht-Besitzer: eigener Abstand je Handelndem (lokal 10 s, global 60 s; §16.2 Nr. 9)
	if not AdminService.IsAdmin(admin) then
		local scope = if args.Global == true then "Global" else "Local"
		local gap = if scope == "Global"
			then tonumber(STAFF.AnnounceGlobalGap) or 60
			else tonumber(STAFF.AnnounceGap) or 10
		local store = announceBy[admin]
		if not store then
			store = {}
			announceBy[admin] = store
		end
		if not Core.GapOk(store, scope, os.clock(), gap) then
			return false, L(admin, "core.tooFast")
		end
	end
	announceAt = os.clock()
	local filtered = filterBroadcast(text, admin.UserId)
	if not filtered then
		return false, L(admin, "admin.filterDown")
	end
	local message = {
		Kind = "Announce",
		Id = newId("N"),
		Text = filtered,
		UserId = admin.UserId,
		Name = string.sub(admin.DisplayName, 1, MAX_NAME),
		Role = roleOf(admin) or "Owner",
	}
	if args.Global == true then
		if publishGlobal(message) then
			return true, L(admin, "admin.announcedGlobal")
		end
		return true, L(admin, "admin.globalFailed")
	end
	handleGlobal(message)
	return true, L(admin, "admin.announced")
end

-- Samstags-Show (1 Klick): CancelAutoShow (GlobalBus) -> Show auf allen Servern -> Rally +15 % Sektor der Woche
local function saturdayShow(admin: Player, global: boolean): (boolean, string)
	local market: any = Config.Market
	local week = Clock.WeekIndex(Clock.Tick())
	local okCancelled, cancelled = call("MarketService", "AutoShowCancelled", week)
	local block = tonumber(SEC.OwnerTradeBlockSeconds) or 120
	if Core.TradeLockBefore(ownerLastTrade[admin], now(), block) then
		return false, L(admin, "admin.tradeLock", block)
	end
	if not (okCancelled and cancelled == true) then
		call("MarketService", "Admin", "CancelAutoShow", { Target = week }, admin)
	end
	local okStart, started, key =
		call("EventService", "Start", "SaturdayShow", {}, if global then "Global" else "Local", admin)
	if not okStart or started ~= true then
		return false, L(admin, if type(key) == "string" then key else "admin.evBusy")
	end
	-- Rally nach der Markt-Abklingzeit (3 s) – Plan-Rally der Auto-Show ist abgesagt
	local sectors = Config.Companies and Config.Companies.Sectors
	local sector = "T"
	if type(sectors) == "table" and #sectors > 0 then
		local entry = sectors[(week % #sectors) + 1]
		if type(entry) == "table" and type(entry.Key) == "string" then
			sector = entry.Key
		end
	end
	local cooldown = tonumber(market and market.Admin and market.Admin.Cooldown) or 3
	local pct = tonumber(EV.AdminLimits.SaturdayShow.RallyPct) or 15
	task.delay(cooldown + 0.25, function()
		if admin.Parent ~= Players then
			return
		end
		local okRally, rallied, message = pcall(marketAction, admin, "MegaRally", {
			Scope = "Sector",
			Target = sector,
			Strength = pct,
			Ramp = 60,
			Decay = 30,
		}, true)
		if not okRally or rallied ~= true then
			call(
				"PlayerStateService",
				"NotifyRaw",
				admin,
				tostring(message or L(admin, "admin.showRallyFailed")),
				"Error"
			)
		end
	end)
	announceAbuse(admin, "SaturdayShow", global)
	return true, L(admin, "admin.showStarted")
end

Actions.Abuse = function(admin, args)
	local kind = args.Event
	if type(kind) ~= "string" then
		return false, L(admin, "admin.evUnknown")
	end
	if MARKET_ACTIONS[kind] then
		return marketAction(admin, kind, if type(args.Args) == "table" then args.Args else {})
	end
	if kind == "SaturdayShow" then
		-- die Auto-Show wird im GlobalBus für ALLE Server abgesagt -> die Show läuft auch auf allen Servern (§B15.3)
		return saturdayShow(admin, true)
	end
	-- Nicht-Markt-Events auf allen Servern nur mit GlobalEvents (Besitzer)
	if args.Global == true and not can(admin, "GlobalEvents") then
		return false, L(admin, "admin.cmd.denied")
	end
	-- Spaß-Events: höchstens eins je FunEventGap Sekunden pro Server, wenn kein Besitzer startet (§16.2 Nr. 9)
	local isFun = eventPerm(STAFF, kind, "EconomyEvents") == "FunEvents"
	local isOwner = AdminService.IsAdmin(admin)
	if isFun and not isOwner then
		local gap = tonumber(STAFF.FunEventGap) or 300
		local last = funEventAt.Server
		if last ~= nil and os.clock() - last < gap then
			return false, L(admin, "admin.cmd.eventGap", Format.Duration(gap - (os.clock() - last), langOf(admin)))
		end
	end
	local eventKind = if kind == "BuildBoom" then "AdminBuildBoom" else kind
	local ok, started, key = call(
		"EventService",
		"Start",
		eventKind,
		if type(args.Args) == "table" then args.Args else {},
		if args.Global == true then "Global" else "Local",
		admin
	)
	if not ok then
		return false, L(admin, "admin.unavailable", "EventService")
	end
	if started == true then
		if isFun then
			funEventAt.Server = os.clock() -- auch Besitzer-Starts zählen (kein Stapeln direkt danach)
		end
		announceAbuse(admin, kind, args.Global == true and kind ~= "AllToHall")
	end
	return started == true, L(admin, if type(key) == "string" then key else "core.error")
end

Actions.AbuseStop = function(admin, args)
	local kind = args.Event
	if type(kind) ~= "string" or #kind > 40 then
		return false, L(admin, "core.invalid")
	end
	local ok, count = call("EventService", "Stop", kind)
	if not ok then
		return false, L(admin, "admin.unavailable", "EventService")
	end
	return true, L(admin, "admin.evStopped", tonumber(count) or 0)
end

-- Welt-Event jetzt starten (nur dieser Server) – Admin-Tab Welt + Crash-Freitag-Probe (Debug)
Actions.WorldEvent = function(admin, args)
	local kind = args.Event
	local allowed = {
		Truck = true,
		Drones = true,
		BuildBoom = true,
		Press = true,
		BellMoment = true,
		SkyShow = true,
		Bear = true,
		GoldenBull = true,
	}
	if type(kind) ~= "string" or not allowed[kind] then
		return false, L(admin, "admin.evUnknown")
	end
	local ok, started, key = call("EventService", "Start", kind, { Probe = args.Probe == true }, "Local", admin)
	if not ok then
		return false, L(admin, "admin.unavailable", "EventService")
	end
	return started == true, L(admin, if type(key) == "string" then key else "core.error")
end

-- =====================================================================
-- AKTIONEN – LIVE-OPS (AT_Live_v1, Notschalter)
-- =====================================================================
Actions.LiveGet = function(admin, _args)
	local specs: { Plain } = {}
	for path, spec in pairs(Config.LiveFields) do
		if type(path) == "string" and type(spec) == "table" then
			local kindName = spec.Type or "number"
			local entry: Plain = { Path = path, Type = kindName }
			if kindName == "number" then
				entry.Min = spec.Min or spec[1]
				entry.Max = spec.Max or spec[2]
				entry.Integer = spec.Integer == true
			elseif kindName == "list" then
				entry.Options = spec.Options
			elseif kindName == "code" then
				entry.MaxCredits = spec.MaxCredits
			end
			if type(spec[1]) == "number" then
				entry.Min, entry.Max, entry.Type = spec[1], spec[2], "number"
			end
			table.insert(specs, entry)
		end
	end
	table.sort(specs, function(a, b)
		return a.Path < b.Path
	end)
	local products: { string } = {}
	local shop = Config.Shop
	if type(shop) == "table" then
		for _, list in ipairs({ shop.Products, shop.GamePasses }) do
			for _, key in ipairs(keysOf(list)) do
				table.insert(products, key)
			end
		end
	end
	return true,
		L(admin, "admin.liveLoaded", tonumber(liveDoc.Version) or 0),
		{
			Specs = specs,
			Current = Config.CurrentLive(),
			Banner = liveDoc.Banner or "",
			Version = liveDoc.Version or 0,
			At = liveDoc.At or 0,
			By = liveDoc.By or 0,
			Products = products,
			Local = storeOff[Config.Tech.LiveStore] == true,
		}
end

Actions.LiveSet = function(admin, args)
	local path = args.Path
	if type(path) ~= "string" or #path > 80 or not string.find(path, ".", 1, true) then
		return false, L(admin, "core.invalid")
	end
	local fields: Plain = Util.DeepCopy(liveDoc.Fields or {})
	if args.Clear == true then
		fields[path] = nil
	else
		local value = args.Value
		local t = type(value)
		if t ~= "number" and t ~= "boolean" and t ~= "table" then
			return false, L(admin, "core.invalid")
		end
		fields[path] = value
	end
	return saveLive(admin, fields, liveDoc.Banner or "")
end

Actions.LiveBanner = function(admin, args)
	local text = args.Text
	local banner = ""
	if type(text) == "string" and text ~= "" then
		local clean = cleanText(text, BANNER_MAX)
		if not clean then
			return false, L(admin, "admin.textLen", BANNER_MAX)
		end
		local filtered = filterBroadcast(clean, admin.UserId)
		if not filtered then
			return false, L(admin, "admin.filterDown")
		end
		banner = filtered
	end
	return saveLive(admin, Util.DeepCopy(liveDoc.Fields or {}), banner)
end

-- =====================================================================
-- AKTIONEN – STATISTIK & MODERATION
-- =====================================================================
Actions.Stats = function(admin, _args)
	local cached = statsCache
	if cached and os.clock() - cached.At < (tonumber(SEC.StatsCacheSeconds) or 60) then
		return true, L(admin, "admin.statsLoaded"), cached.Data
	end
	local credits, aky = 0, 0
	local suspicious: { Plain } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local okBal, balance = call("ShopService", "Balance", p)
		if okBal and Util.IsFinite(balance) then
			credits += balance
		end
		local okNav, nav = call("OrderService", "Nav", p)
		if okNav and Util.IsFinite(nav) then
			aky += nav
		end
		local okScore, score = call("AntiCheatService", "Score", p)
		if okScore and Util.IsFinite(score) and score >= (tonumber(SEC.Review) or 25) then
			table.insert(suspicious, { Name = p.Name, UserId = p.UserId, Score = score })
		end
	end
	local traded: { Plain } = {}
	for key, n in pairs(tradedCount) do
		table.insert(traded, { I = tonumber(key), N = n })
	end
	table.sort(traded, function(a, b)
		return a.N > b.N
	end)
	while #traded > 5 do
		table.remove(traded)
	end
	local okAudit, audit = call("MarketService", "AuditStats")
	local globalPlayers, servers = readHeartbeat()
	local today, yesterday = readPurchaseDay(utcDay()), readPurchaseDay(utcDay() - 1)
	local okAc, acStats = call("AntiCheatService", "Stats")
	local okEv, evStats = call("EventService", "Stats")
	local data = {
		Online = #Players:GetPlayers(),
		GlobalPlayers = globalPlayers,
		Servers = servers,
		Credits = credits,
		AkyCents = aky,
		Traded = traded,
		FillsPerMin = #tradeTimes,
		Audit = if okAudit and type(audit) == "table" then audit else {},
		Today = today,
		Yesterday = yesterday,
		Suspicious = suspicious,
		AntiCheat = if okAc and type(acStats) == "table" then acStats else {},
		Events = if okEv and type(evStats) == "table" then evStats else {},
		Local = storeOff[Config.Tech.StatsStore] == true,
	}
	statsCache = { At = os.clock(), Data = data }
	return true, L(admin, "admin.statsLoaded"), data
end

Actions.Flags = function(admin, _args)
	local ok, list = call("AntiCheatService", "AllFlags", 2)
	if not ok or type(list) ~= "table" then
		return false, L(admin, "admin.unavailable", "AntiCheatService")
	end
	return true, L(admin, "admin.flags", #list), list
end

Actions.DismissFlag = function(admin, args)
	if type(args.Id) ~= "string" or #args.Id > 80 then
		return false, L(admin, "core.invalid")
	end
	local ok, done = call("AntiCheatService", "Dismiss", args.Id)
	if not ok or done ~= true then
		return false, L(admin, "core.error")
	end
	return true, L(admin, "admin.dismissed")
end

Actions.Reports = function(admin, _args)
	local ok, list = call("AntiCheatService", "AllReports", 2)
	if not ok or type(list) ~= "table" then
		return false, L(admin, "admin.unavailable", "AntiCheatService")
	end
	-- Kopien (die Listen gehören AntiCheatService) + "Ziel ist gerade auf diesem Server"
	local out: { Plain } = {}
	for _, entry in ipairs(list) do
		if type(entry) == "table" then
			local copy: Plain = table.clone(entry)
			copy.Online = isInt(entry.UserId) and Players:GetPlayerByUserId(entry.UserId) ~= nil
			table.insert(out, copy)
		end
	end
	return true, L(admin, "admin.reports", #out), out
end

Actions.AdminLog = function(admin, _args)
	-- Panel zeigt die letzten 100 Admin-Aktionen (Wunsch 18); gespeichert bleiben bis zu AdminLogMax
	local list = readLog()
	local shown: { Plain } = table.move(list, 1, math.min(#list, MAX_LIST), 1, {})
	return true, L(admin, "admin.logLoaded", #shown), shown
end

-- =====================================================================
-- AKTIONEN – TEAM (W19/W26): Stumm, Rollen, Team-Liste, Meldungen, Respawn, TpTo, Neustart
-- =====================================================================
-- Stummschalten führt StaffService aus (Chat-Kanäle, Sprachchat, Spielstand, Undo-Regel); die Masse prüft das Tor hier
local function staffDelegate(admin: Player, fnName: string, ...: any): (boolean, string, any?)
	local ok, success, message, data = call("StaffService", fnName, admin, ...)
	if not ok then
		return false, L(admin, "admin.unavailable", "StaffService")
	end
	return success == true, tostring(message or ""), data
end

Actions.Mute = function(admin, args)
	local targets = resolveTargets(admin, args.Target)
	local mass = massError(admin, args.Target, #targets)
	if mass then
		return false, mass
	end
	local ok, message = staffDelegate(admin, "Mute", args)
	return ok, message
end

Actions.Unmute = function(admin, args)
	local ok, message = staffDelegate(admin, "Unmute", args)
	return ok, message
end

-- Rolle setzen/entfernen: { Target? | UserId? | Name?, Role = "Admin" | "Moderator" | "" } – Prüfung in StaffService
-- (Staff.CanSetRole, im UpdateAsync-Transform mit dem frischen Dokument wiederholt)
Actions.SetRole = function(admin, args)
	return staffDelegate(admin, "SetRole", args)
end

Actions.StaffList = function(admin, _args)
	return staffDelegate(admin, "List")
end

-- Meldung erledigen: { Id ≤ 80 } -> AntiCheatService.Dismiss (gibt den Eintrag zurück); der Melder bekommt Bescheid
Actions.ResolveReport = function(admin, args)
	local id = args.Id
	if type(id) ~= "string" or #id < 1 or #id > 80 then
		return false, L(admin, "core.invalid")
	end
	local ok, done, entry = call("AntiCheatService", "Dismiss", id)
	if not ok or done ~= true then
		return false, L(admin, "core.error")
	end
	local reporter = if type(entry) == "table" and isInt(entry.From) then Players:GetPlayerByUserId(entry.From) else nil
	if reporter and reporter ~= admin then
		call("StaffService", "SayKey", reporter, "admin.rep.yours", { tostring(entry.Name or "?") }, "Ok")
	end
	return true, L(admin, "admin.rep.resolved")
end

-- Neu spawnen: sich selbst erlaubt, andere nur bei niedrigerem Rang, Masse nur mit MassTarget
Actions.Respawn = function(admin, args)
	local targets, err = resolveTargets(admin, args.Target)
	if #targets == 0 then
		return false, err or L(admin, "admin.noTarget")
	end
	local mass = massError(admin, args.Target, #targets)
	if mass then
		return false, mass
	end
	local kept, skipped, hadSelf = filterRank(admin, targets, true)
	if #kept == 0 then
		return false, rankError(admin, skipped, hadSelf)
	end
	for _, p in ipairs(kept) do
		task.spawn(function()
			unseat(p) -- erst aus dem Auto (sonst reißt der neue Character den Sitz mit)
			if p.Parent ~= Players then
				return
			end
			local okLoad, loadErr = pcall(function()
				p:LoadCharacter()
			end)
			if not okLoad then
				warn(("[Admin] Respawn %s fehlgeschlagen: %s"):format(p.Name, tostring(loadErr)))
			end
		end)
	end
	return true, withSkipped(admin, L(admin, "admin.cmd.respawned", names(kept)), #skipped)
end

-- Spieler A zu Spieler B: { Target = A, To = B }; A wird bewegt -> Rang-Regel (außer A = man selbst)
Actions.TpTo = function(admin, args)
	local target, err = resolveOne(admin, args.Target)
	if not target then
		return false, err or L(admin, "admin.noTarget")
	end
	local to, errTo = resolveOne(admin, args.To)
	if not to then
		return false, errTo or L(admin, "admin.noTarget")
	end
	if target == to then
		return false, L(admin, "admin.noTarget")
	end
	if target ~= admin and not canActOn(admin, target) then
		return false, L(admin, "admin.cmd.rank", target.DisplayName)
	end
	local base = footOf(to)
	if not base or not target.Character then
		return false, L(admin, "admin.noCharacter")
	end
	if not teleport(target, base * CFrame.new(0, 0, 4)) then
		return false, L(admin, "admin.noCharacter")
	end
	return true, L(admin, "admin.cmd.tpOther", target.DisplayName, to.DisplayName)
end

-- Server neu starten (nur dieser Server): { Confirm = true, Reason? } – sperren, Vorwarnung an alle (in ihrer Sprache),
-- nach ShutdownDelay alle kicken (der Auslöser zuletzt). Roblox schließt den leeren Server; neue Beitritte fliegen raus.
Actions.Shutdown = function(admin, args)
	if args.Confirm ~= true then
		return false, L(admin, "admin.confirmNeeded")
	end
	local seconds = math.clamp(math.floor(tonumber(STAFF.ShutdownDelay) or 10), 1, 120)
	if shuttingDown then
		return true, L(admin, "admin.cmd.shutdown", seconds)
	end
	shuttingDown = true
	serverLocked = true
	workspace:SetAttribute("ServerLocked", true)
	local raw = cleanText(args.Reason, MAX_REASON)
	local reason = if raw then filterBroadcast(raw, admin.UserId) else nil
	local role = roleOf(admin) or "Owner"
	local shownName = string.sub(admin.DisplayName, 1, MAX_NAME)
	for _, p in ipairs(Players:GetPlayers()) do
		local note = L(p, "admin.cmd.shutdownNote")
		if reason and reason ~= "" then
			note ..= " – " .. reason
		end
		effect(p, "Announce", 0, { Text = note, UserId = admin.UserId, Name = shownName, Role = role })
	end
	task.delay(seconds, function()
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= admin then
				p:Kick(L(p, "admin.cmd.shutdownKick"))
			end
		end
		if admin.Parent == Players then
			admin:Kick(L(admin, "admin.cmd.shutdownKick"))
		end
	end)
	return true, L(admin, "admin.cmd.shutdown", seconds)
end

-- =====================================================================
-- AKTIONEN – DEBUG
-- =====================================================================
Actions.SimulatePurchase = function(admin, args)
	if not productExists(args.ProductKey) then
		return false, L(admin, "admin.badProduct")
	end
	local ok, granted, message = call("MonetizationService", "SimulatePurchase", admin, args.ProductKey)
	if not ok then
		return false, L(admin, "admin.unavailable", "MonetizationService")
	end
	if granted ~= true then
		return false, tostring(message or L(admin, "core.error"))
	end
	return true, L(admin, "admin.simulated", tostring(args.ProductKey))
end

Actions.SimulatePolicy = function(admin, args)
	local field = if args.Field == "Trading" or args.Field == "Subscription" then args.Field else "Random"
	local allowed: boolean? = nil
	if args.Allowed == true then
		allowed = true
	elseif args.Allowed == false then
		allowed = false
	end
	if not call("MonetizationService", "SetPolicyOverride", admin, field, allowed) then
		return false, L(admin, "admin.unavailable", "MonetizationService")
	end
	local label = if allowed == true
		then L(admin, "admin.policyAllowed")
		elseif allowed == false then L(admin, "admin.policyRestricted")
		else L(admin, "admin.policyAuto")
	return true, L(admin, "admin.policy", field, label)
end

Actions.SkipDay = function(admin, _args)
	if not RunService:IsStudio() then
		return false, L(admin, "admin.studioOnly")
	end
	local offset = Util.GetDayOffset() + 1
	Util.SetDayOffset(offset)
	return true, L(admin, "admin.daySkipped", offset)
end

Actions.SetDebug = function(admin, args)
	local debug: any = Config.Debug
	for _, key in ipairs({ "LogRejects", "ForceRestricted", "ShowTriggers" }) do
		local v = args[key]
		if type(v) == "boolean" then
			debug[key] = v
			workspace:SetAttribute("Debug" .. key, if v then true else nil)
		end
	end
	local function onOff(v: any): string
		return L(admin, if v == true then "admin.on" else "admin.off")
	end
	return true,
		L(admin, "admin.debugSet", onOff(debug.LogRejects), onOff(debug.ForceRestricted), onOff(debug.ShowTriggers)),
		{
			LogRejects = debug.LogRejects == true,
			ForceRestricted = debug.ForceRestricted == true,
			ShowTriggers = debug.ShowTriggers == true,
		}
end

Actions.RunSelfTest = function(admin, _args)
	local ok, passed, total = call("SelfTestService", "Run")
	-- CoreTests setzen die Live-Werte auf den Code-Stand zurück -> gültigen Live-Stand wieder anwenden
	applyLiveDoc(liveDoc)
	if not ok then
		return false, L(admin, "admin.unavailable", "SelfTestService")
	end
	return (tonumber(passed) or 0) == (tonumber(total) or -1),
		L(admin, "admin.selfTest", tonumber(passed) or 0, tonumber(total) or 0)
end

-- =====================================================================
-- LEBENSZYKLUS
-- =====================================================================
-- Log-Ziel aus den Argumenten (Target / To / Name / UserId) – nie Freitext oder Chat-Rohtext
local function targetText(args: Plain): string?
	local function one(value: any): string?
		if type(value) == "string" and value ~= "" then
			return truncate(value, MAX_NAME)
		elseif isInt(value) then
			return tostring(value)
		end
		return nil
	end
	local target = one(args.Target) or one(args.Name) or one(args.UserId)
	local to = one(args.To)
	if target and to then
		return truncate(target .. " -> " .. to, MAX_NAME)
	end
	return target
end

-- Ablehnung: Teammitglieder, die eine schwächere Variante dürfen, bekommen den passenden Hinweis statt "keine Berechtigung"
local function deniedText(p: Player, action: string, args: Plain): string
	if action == "Ban" and can(p, "TempBan") then
		if args.UserId ~= nil or args.Name ~= nil then
			return L(p, "admin.ban2.onlineOnly")
		end
		local maxTable = STAFF.TempBanMax
		local role = roleOf(p)
		local max = if type(maxTable) == "table" and role then maxTable[role] else nil
		if Util.IsFinite(max) and max > 0 then
			return L(p, "admin.cmd.maxDuration", Format.Duration(max, langOf(p)))
		end
	end
	return L(p, "admin.denied")
end

-- Teammitglieder: Ablehnung je Aktion höchstens einmal pro Minute ins Admin-Log
local function noteDenied(p: Player, action: string, via: string)
	local map = deniedAt[p]
	if not map then
		map = {}
		deniedAt[p] = map
	end
	if Core.GapOk(map, action, os.clock(), DENIED_LOG_GAP) then
		logAction(p, "Denied", false, action, via)
	end
end

-- DAS Tor für jede Admin-Aktion (Panel und Chat): Rang ≥ 1 -> Recht (Core.PermFor + Staff.Can) -> Besitzer bekannt
-- (strafende Rechte) -> Schwer-Abstand -> Aktion (pcall) -> Admin-Log mit Via/Role/Target. Gibt (ok, Meldung?, Daten?).
function AdminService.Run(p: Player, action: any, args: any, via: string?): (boolean, string?, any?)
	if typeof(p) ~= "Instance" or not p:IsA("Player") or p.Parent ~= Players then
		return false, nil, nil
	end
	local viaName = if via == "Chat" then "Chat" else "Panel"
	if rankOf(p) < 1 then
		if not warnedDenied[p] then
			warnedDenied[p] = true
			warn(("[Admin] Unerlaubter Zugriff von %s (%d)"):format(p.Name, p.UserId))
			logAction(
				p,
				"Denied",
				false,
				if type(action) == "string" then string.sub(action, 1, MAX_ACTION_LEN) else "?",
				viaName
			)
		end
		return false, L(p, "admin.denied"), nil
	end
	if type(action) ~= "string" or #action > MAX_ACTION_LEN or not Actions[action] then
		return false, L(p, "core.unknownAction"), nil
	end
	local cleanArgs: Plain = if type(args) == "table" then args else {}
	local perm = Core.PermFor(action, cleanArgs, STAFF)
	if perm == nil or not can(p, perm) then
		noteDenied(p, action, viaName)
		return false, deniedText(p, action, cleanArgs), nil
	end
	-- Gruppen-Spiel mit (noch) unbekanntem Besitzer: strafende Rechte nur für den Besitzer selbst
	if Core.OwnerBlocks(perm, AdminService.IsAdmin(p), AdminService.OwnerKnown()) then
		refreshGroupOwner()
		return false, L(p, "admin.ownerUnknown"), nil
	end
	if HEAVY[action] then
		local map = heavyAt[p]
		if not map then
			map = {}
			heavyAt[p] = map
		end
		if not Core.GapOk(map, action, os.clock(), tonumber(STAFF.HeavyGap) or 3) then
			return false, L(p, "core.tooFast"), nil
		end
	end
	local ctx: Ctx = { Via = viaName, Target = targetText(cleanArgs) }
	local ok, success, message, data = pcall(Actions[action], p, cleanArgs, ctx)
	if not ok then
		warn(("[Admin] Fehler bei %s: %s"):format(action, tostring(success)))
		logAction(p, action, false, tostring(success), viaName, ctx.Target)
		return false, L(p, "admin.error", tostring(success)), nil
	end
	local text = if type(message) == "string" then message else nil
	if not QUIET[action] then
		print(("[Admin] %s -> %s (%s): %s"):format(p.Name, action, viaName, tostring(text)))
		logAction(p, action, success == true, text, viaName, ctx.Target)
	end
	return success == true, text, data
end

-- Remote "Admin": Spam-Bremse ZUERST (auch für Nicht-Teammitglieder, sonst fluten Exploiter das Log), dann nur Run
local function dispatch(p: Player, action: any, args: any): { Ok: boolean, Message: string?, Data: any? }
	if p.Parent ~= Players then
		return { Ok = false } -- schon gegangen (sonst bliebe ein Limiter-Eintrag nach PlayerRemoving liegen)
	end
	if not limiter.Check(p) then
		return { Ok = false, Message = L(p, "core.tooFast") }
	end
	local ok, message, data = AdminService.Run(p, action, args, "Panel")
	return { Ok = ok, Message = message, Data = data }
end

local function onPlayer(p: Player)
	joinedAt[p] = joinedAt[p] or os.clock()
	refreshGroupOwner()
	if shuttingDown then
		p:Kick(L(p, "admin.cmd.shutdownKick")) -- Server startet gerade neu
		return
	end
	if AdminService.IsAdmin(p) then
		p:SetAttribute("IsAdmin", true) -- nur der Besitzer (Team-Rollen setzen nur "Role", StaffService)
		p:SetAttribute("CanFly", true)
	else
		p:SetAttribute("IsAdmin", nil)
		if serverLocked then
			-- gesperrter Server: Teammitglieder dürfen rein – erst die Rolle abwarten (Team-Dokument + Gruppen-Rang,
			-- §16.2 Nr. 10), sonst flögen Gruppen-Moderatoren raus, bevor ihr Rang geladen ist
			task.spawn(function()
				if has("StaffService", "WaitRole") then
					call("StaffService", "WaitRole", p, 6)
				else
					call("StaffService", "WaitReady", 5)
				end
				if p.Parent == Players and serverLocked and rankOf(p) < 1 then
					p:Kick(L(p, "admin.lockedKick"))
				end
			end)
		end
	end
	p.CharacterAdded:Connect(function(character)
		if p:GetAttribute("AdminInvisible") == true and can(p, "Invisible") then
			task.defer(setInvisible, p, true)
		end
		if p:GetAttribute("AdminFrozen") == true or giftActive(p) then
			-- Einfrieren übersteht den Respawn (kein Entkommen per Reset), das Speed-Geschenk ebenso
			task.spawn(function()
				local root = character:WaitForChild("HumanoidRootPart", 10)
				character:WaitForChild("Humanoid", 10)
				if p.Character ~= character or p.Parent ~= Players then
					return
				end
				if p:GetAttribute("AdminFrozen") == true and root and root:IsA("BasePart") then
					root.Anchored = true
				end
				if giftActive(p) then
					applyGift(p)
				end
			end)
		end
	end)
end

function AdminService.Init(services: any)
	Services = services
end

function AdminService.Start()
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayer, p)
	end
	Players.PlayerRemoving:Connect(function(p)
		limiter.Clear(p)
		lookupLimiter.Clear(p)
		adminCache[p] = nil
		warnedDenied[p] = nil
		deniedAt[p] = nil
		heavyAt[p] = nil
		announceBy[p] = nil
		frozenBy[p] = nil
		joinedAt[p] = nil
		ownerEvents[p] = nil
		ownerLastTrade[p] = nil
		purchaseSeen[p] = nil
		local conn = invisConn[p]
		if conn then
			conn:Disconnect()
		end
		invisConn[p] = nil
		-- Zuschauer, deren Replikation um diesen Spieler lief, wieder um die eigene Figur streamen
		local character = p.Character
		if character then
			for _, other in ipairs(Players:GetPlayers()) do
				local focus = other.ReplicationFocus
				if other ~= p and focus and focus:IsDescendantOf(character) then
					other.ReplicationFocus = nil
				end
			end
		end
	end)

	Remotes.Admin.OnServerInvoke = dispatch
	call("OrderService", "OnTrade", onTrade)

	Scheduler.Every("AdminLog", 1 / LOG_FLUSH_SECONDS, flushLog)
	Scheduler.Every("AdminHeartbeat", 1 / HEARTBEAT_SECONDS, writeHeartbeat)
	Scheduler.Every("AdminPurchases", 1 / STATS_SAMPLE_SECONDS, samplePurchases)
	Scheduler.Every(
		"AdminStatsFlush",
		1 / math.max(60, tonumber(Config.Tech.StatsFlushSeconds) or 600),
		flushPurchaseStats
	)
	Scheduler.Every("AdminGroupOwner", 1 / GROUP_FAIL_CACHE, refreshGroupOwner) -- prüft nur den Cache (Fehler: 30 s)
	Scheduler.Every("AdminGifts", 1, expireGifts)

	-- Global: Ansagen, Admin-Abuse, Live-Config (Sender empfängt auch selbst)
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(Config.Tech.MessagingTopic, function(packet)
				handleGlobal(if type(packet) == "table" then packet.Data else nil)
			end)
		end)
		if not ok then
			warn("[Admin] MessagingService nicht verfügbar (in Studio normal): " .. tostring(err))
		end
	end)
	-- Live-Config beim Start laden (geprüft und geklemmt über Config.ApplyLive)
	task.spawn(loadLive)
	writeHeartbeat()
	game:BindToClose(function()
		if #logPending > 0 then
			local batch = table.clone(logPending)
			table.clear(logPending)
			pcall(function()
				storeCall(Config.Tech.ModStore, function(store)
					return store:UpdateAsync("AdminLog", function(old)
						local list: { Plain } = if type(old) == "table" then old else {}
						for _, entry in ipairs(batch) do
							table.insert(list, entry)
						end
						while #list > (tonumber(SEC.AdminLogMax) or 500) do
							table.remove(list, 1)
						end
						return list
					end)
				end)
			end)
		end
	end)
end

return AdminService
