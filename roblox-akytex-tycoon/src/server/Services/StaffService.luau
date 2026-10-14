-- =====================================================================
--  AKYTEX TYCOON – Team-Rollen, Chat-Befehle, Stummschalten, Bann-Liste (Server/Services/StaffService)
--  Besitzer: WP11 (Admin, Events, Anti-Cheat) – W19 Team-Rollen + W26 Entbannen. Vertrag: aky3_admin_spec §4, §6, §11
--  + §16 (Korrektur), DESIGN.md §B15, §C5.10, §C7.4 (Effekte ChatSystem/StaffDo, Besitzer ChatTools), §C9
--  (Request "StaffCommand"), §C13 (AT_Mod_v1 "Staff", "Ban_<UserId>", "BanIndex"; Messaging "AT_Staff").
--
--  Rollen: Owner (fest, AdminService.IsAdmin) > Admin > Moderator > Spieler. Quelle = max(Besitzer, gespeicherte Rolle
--  (AT_Mod_v1 "Staff"), Gruppen-Rang (Config.Security.Staff.Group)). Rollen kann man NIE kaufen – nur SetRole schreibt
--  sie, und SetRole läuft nur über AdminService.Run (Recht ManageMods/ManageAdmins). IsAdmin setzt dieser Dienst NIE;
--  das Attribut "Role" setzt er NUR in Refresh (reine Anzeige, der Server prüft jede Aktion neu).
--  UserIds ≤ 0 (Studio-Testspieler) und Studio ohne API: Rollen/Banns nur im Speicher (nie DataStore).
--
--  Chat: "/"-Befehle = TextChatCommands (Ordner TextChatService.AT_StaffCommands, Triggered), ";"-Befehle =
--  Player.Chatted + Request "StaffCommand" (Client-Rückfall, 6/10 s) – beide entdoppelt (gleicher Text < 1,5 s).
--  Jede Aktion läuft über AdminService.Run(p, action, args, "Chat") (ein Rechte-Tor, ein Log). Rückmeldung nur an den
--  Handelnden über Effekt "ChatSystem" { Text, Kind, Lines? }; "StaffDo" { Do, UserId? } steuert ChatTools/AdminPanel.
--  Zustellung (ShouldDeliverCallback, yieldet nie): Stumme nie, ";"-Befehle nie an andere, persönliches Stumm je Empfänger.
--  Roblox-Standard /mute und /unmute sind aus (unser /mute: Team = Server-Stumm, alle anderen = nur für mich stumm).
--
--  Sync: MessagingService Config.Tech.StaffTopic ("AT_Staff"): Role (nur mit höherem Rev), Kick (nach jedem Bann),
--  Report (≤ 1 je 5 s je Server) – jedes Feld über Staff.ValidateMsg geprüft, Dedupe per Id, Sender wendet selbst an.
--  Team-Dokument alle DocRefreshSeconds neu (heilt verlorene Nachrichten), Gruppen-Rang je Spieler einmal je Sitzung.
--  SetRole prüft die Rechte im UpdateAsync-Transform mit dem FRISCHEN Dokument noch einmal (§16.2 Nr. 3).
--  Bann-Liste (W26): Ban_<id> = Durchsetzung beim Beitritt, BanIndex = Liste für Tab „Banns“ (abgelaufene raus,
--  höchstens BanIndexMax), einmaliger Import aus dem Bann-Log, Abgleich mit Players:GetBanHistoryAsync (nur live).
--
--  Öffentliche API (§6.1 + §16):
--    StaffService.RoleOf(p): string?            Rank(p): number             IsStaff(p): boolean
--    StaffService.Can(p, perm): boolean         CanActOn(actor, target: Player | UserId): boolean      (nie yieldend)
--    StaffService.RankOfUserId(id): number      RankOfUserIdAsync(id): (number, known)  (yieldet; unbekannt = 3, false)
--    StaffService.MoveExempt(p): boolean        Besitzer oder Recht Fly/Noclip (AntiCheat-Bewegung)
--    StaffService.WaitReady(timeout): boolean   WaitRole(p, timeout): boolean   (Team-Dokument [+ Gruppen-Rang] geladen)
--    StaffService.Refresh(p)                    Rolle neu berechnen, Attribut Role, Begrüßung / Hinweis bei Verlust
--    StaffService.SetRole(actor, args): (ok, msg, data?)   List(actor): (ok, msg, data?)      (AdminService-Delegates)
--    StaffService.Mute(actor, args): (ok, msg)  Unmute(actor, args): (ok, msg)                IsMuted(p): boolean
--    StaffService.AddBan(entry): boolean        RemoveBan(userId, why?): boolean               (yielden)
--    StaffService.BanList(args): { Entries, Total, Page, Pages, Reconciled }   BanEntry(userId): entry?   Reconcile(ids)
--    StaffService.Say(p, text, kind?, lines?)   SayKey(p, key, args?, kind?)                   (Effekt ChatSystem)
--    StaffService.OnReport(report)              StaffService.Run(p, raw, via)                  (Befehl ausführen)
--    StaffService.Core = { ApplyRole, SanitizeDoc, CleanIndexEntry, SanitizeIndex, PruneIndex, SearchIndex, PageOf,
--                          ImportEntries, ReconcileState, CommandArg, Tail, StudioRole }      (rein; StaffTests)
-- =====================================================================

local DataStoreService = game:GetService("DataStoreService")
local GroupService = game:GetService("GroupService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Lang = require(Shared:WaitForChild("Lang"))
local Types = require(Shared:WaitForChild("Types"))
local Util = require(Shared:WaitForChild("Util"))
local Format = require(Shared:WaitForChild("Format"))
local Staff = require(Shared:WaitForChild("Staff"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local StaffService = {}
local Services: any = nil

type Plain = { [string]: any }
type Member = { Role: string, Name: string, By: number, ByName: string, Since: number }
type StaffDoc = { V: number, Rev: number, Members: { [string]: Member } }
type IndexEntry = { Name: string, Until: number, Reason: string, By: number, ByName: string, T: number, Src: string }
type IndexDoc = { V: number, Rev: number, Entries: { [string]: IndexEntry }, Imported: boolean? }
type Handler = (p: Player, args: { string }, raw: string) -> ()

local SEC: any = Config.Security
local STAFF: any = SEC.Staff
local IS_STUDIO = RunService:IsStudio()

local DOC_KEY = "Staff"
local INDEX_KEY = "BanIndex"
local BAN_PREFIX = "Ban_"
local OWNER_RANK = 3
local MAX_NAME = 20 -- Roblox-Namen
local MAX_SAY_TEXT = 500 -- Byte je ChatSystem-Text
local MAX_SAY_LINES = 20
local MAX_SAY_LINE = 200 -- Byte je Zeile
local HELP_LINE = 150 -- /cmds: Befehle je Zeile höchstens so viele Byte
local MAX_COMMAND = 300
local DOC_SCAN_MAX = 1000 -- höchstens so viele Einträge aus einem gespeicherten Dokument lesen
local PERSONAL_MAX = 50 -- persönlich Stummgeschaltete je Empfänger
local GREET_DELAY = 8 -- Begrüßung frühestens so viele s nach dem Beitritt (Client-Chat ist dann bereit)
local DUP_SECONDS = 1.5 -- gleicher Befehls-Text über zwei Wege (Chatted + Request) = einmal
local DENIED_GAP = 10
local RELOAD_DELAY = 5 -- Team-Dokument nach einer Rollen-Nachricht so viel später neu lesen
local REPORT_PUBLISH_GAP = 5
local GROUP_CACHE_SECONDS = 60
local GROUP_CACHE_MAX = 256
local INDEX_CACHE_SECONDS = 10
local INDEX_REASON_MAX = 120 -- Zeichen Grund in der Bann-Liste
local INDEX_RETRY_SECONDS = 5
local BAN_REASON_MAX = 400 -- Byte (Roblox DisplayReason)
local MUTE_REASON_MAX = 200
local MIN_MUTE = 60
local LOGS_DEFAULT = 5
local LOGS_MAX = 10
local LOG_MSG_CHARS = 60
local MASS_LIST = 3 -- Listen mit mehr aufgelösten Zielen gelten als Masse (§16.2 Nr. 8)
local RECONCILE_IDS_MAX = 50
local TEN_YEARS = 3650 * 86400
local VOICE_ATTR = "AT_VoiceMuted" -- nur Mikrofone, die WIR stummgeschaltet haben, werden wieder freigegeben

local CONFIRM_WORDS: { [string]: boolean } = { confirm = true, ok = true, ja = true, yes = true }
local RESET_WORDS: { [string]: boolean } = { reset = true, off = true, aus = true, normal = true }
local GLOBAL_WORDS: { [string]: boolean } = { global = true, ["-g"] = true }
local SAY_KINDS: { [string]: boolean } = { Ok = true, Err = true, Info = true, Warn = true }
local SOURCES: { [string]: boolean } = { Panel = true, Chat = true, Auto = true, Import = true }
local REMOVE_WHY: { [string]: boolean } = { Unban = true, Reconcile = true, Expired = true }
local HELP_GROUPS = { "All", "Moderator", "Admin", "Owner" }
local ROLE_BY_RANK: { [number]: string } = { [1] = "Moderator", [2] = "Admin", [3] = "Owner" }

-- ---------------------------------------------------------------------
-- ZUSTAND (Pro-Spieler-Tabellen werden bei PlayerRemoving geleert)
-- ---------------------------------------------------------------------
local staffDoc: StaffDoc = { V = 1, Rev = 0, Members = {} }
local docReady = false -- erster Ladeversuch fertig (auch bei Fehler)
local docLoaded = false -- Dokument wirklich gelesen/geschrieben
local docLoading = false
local reloadPending = false
local modOff = false -- Studio ohne API-Zugriff: alles nur im Speicher

local localMembers: { [number]: Member } = {} -- UserId ≤ 0 oder ohne Speicher
local localBans: { [number]: Plain } = {} -- Ban_-Ersatz (Studio / Schreibfehler)
local localIndex: IndexDoc = { V = 1, Rev = 0, Entries = {} }
local indexCache: { Doc: IndexDoc, At: number }? = nil
local pruning = false
local reconciling = false
local reconcileCache: { [number]: { State: string, At: number } } = {}

local groupRank: { [Player]: number } = {}
local groupLoaded: { [Player]: boolean } = {}
local groupCache: { [number]: { Rank: number, Raw: number, At: number } } = {}
local roleCache: { [Player]: string | false } = {}
local testRole: { [Player]: string | false } = {} -- nur Studio-SelfTests (Core.StudioRole)
local joinedAt: { [Player]: number } = {}
local lastCmd: { [Player]: { Text: string, At: number } } = {}
local deniedAt: { [Player]: number } = {}
local notifyAt: { [Player]: number } = {}
local confirm: { [Player]: { Key: string, At: number } } = {}

local mutedUntil: { [number]: number } = {} -- nur Spieler auf diesem Server (Unix, -1 = dauerhaft)
local personal: { [number]: { [number]: boolean } } = {} -- [Empfänger][Absender] = true (nur diese Sitzung)

local cmdRate = SEC.Rates and SEC.Rates.Command or { 6, 10 }
local roleRate = SEC.Rates and SEC.Rates.Role or { 6, 60 }
local lookupRate = STAFF.LookupLimit or { 10, 60 }
local cmdLimiter = Util.RateLimiter(cmdRate[1] or 6, cmdRate[2] or 10)
local roleLimiter = Util.RateLimiter(roleRate[1] or 6, roleRate[2] or 60)
local lookupLimiter = Util.RateLimiter(lookupRate[1] or 10, lookupRate[2] or 60)

type Dedupe = { Seen: (id: string) -> boolean }

-- Rückfall-Dedupe (gleiches Verhalten wie AdminService.Core.NewDedupe, das Init bevorzugt)
local function newDedupe(n: number): Dedupe
	local seen: { [string]: boolean } = {}
	local order: { string } = {}
	return {
		Seen = function(id: string): boolean
			if seen[id] then
				return true
			end
			seen[id] = true
			table.insert(order, id)
			while #order > n do
				local old = table.remove(order, 1)
				if old then
					seen[old] = nil
				end
			end
			return false
		end,
	}
end

local dedupe: Dedupe = newDedupe(200)
local reportPublishAt = -math.huge
local publishWarned = false
local legacyChat = false
local idCounter = 0

local Core = {}
local Handlers: { [string]: Handler } = {}

-- =====================================================================
-- KLEINE HELFER
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
		warn(("[Staff] %s.%s fehlgeschlagen: %s"):format(name, fnName, tostring(result[2])))
	end
	return table.unpack(result, 1, result.n)
end

local function isPlayer(p: any): boolean
	return typeof(p) == "Instance" and p:IsA("Player")
end

local function isInt(n: any): boolean
	return Util.IsFinite(n) and n % 1 == 0 and math.abs(n) < 2 ^ 53
end

local function idKey(userId: number): string
	return string.format("%d", userId)
end

local function trim(text: string): string
	return (string.gsub(string.gsub(text, "^%s+", ""), "%s+$", ""))
end

-- UTF-8-sicher auf höchstens maxBytes kürzen
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

-- Text getrimmt auf höchstens maxChars Zeichen; kein Text / kaputtes UTF-8 -> ""
local function clip(value: any, maxChars: number): string
	if type(value) ~= "string" then
		return ""
	end
	local text = trim(value)
	local len = utf8.len(text)
	if len == nil then
		return ""
	end
	if len > maxChars then
		local stop = utf8.offset(text, maxChars + 1)
		text = if stop then string.sub(text, 1, stop - 1) else text
	end
	return text
end

local function isNameText(text: any): boolean
	return type(text) == "string" and #text >= 3 and #text <= MAX_NAME and string.match(text, "^[%w_]+$") ~= nil
end

local function newId(prefix: string): string
	idCounter += 1
	return ("%s%x_%x_%x"):format(prefix, os.time(), Util.Hash(game.JobId .. tostring(idCounter)), idCounter)
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

local function roleLabel(p: Player, role: string): string
	return L(p, "admin.role." .. role)
end

local function groupEnabled(): boolean
	local group = STAFF.Group
	return type(group) == "table" and isInt(group.Id) and group.Id > 0
end

-- Gruppen-Rang (0–255) -> Rang der Gruppen-Rolle (0–2)
local function groupRoleRank(raw: number?): number
	return Staff.Rank(Staff.ResolveRole({ IsOwner = false, GroupRank = raw, Group = STAFF.Group }))
end

local function countKeys(t: { [any]: any }): number
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

local function noApi(err: any): boolean
	local text = string.lower(tostring(err))
	return IS_STUDIO
		and (
			string.find(text, "studio", 1, true) ~= nil
			or string.find(text, "publish", 1, true) ~= nil
			or string.find(text, "api services", 1, true) ~= nil
			or string.find(text, "403", 1, true) ~= nil
		)
end

-- AT_Mod_v1 mit "aus"-Schalter (Studio ohne API: leise nur im Speicher). Yieldet.
local function storeCall(fn: (DataStore) -> any): (boolean, any)
	if modOff then
		return false, "off"
	end
	local ok, result = pcall(function()
		return fn(DataStoreService:GetDataStore(Config.Tech.ModStore))
	end)
	if not ok then
		if noApi(result) then
			modOff = true
		else
			warn("[Staff] DataStore " .. tostring(Config.Tech.ModStore) .. ": " .. tostring(result))
		end
	end
	return ok, result
end

local function filterBroadcast(text: string, fromUserId: number): string?
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, fromUserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(result) == "string" and result ~= "" then
		return result
	end
	return nil
end

local function profileOf(p: Player): Plain?
	local ok, data = call("DataService", "Get", p)
	if not ok or type(data) ~= "table" then
		return nil
	end
	if type(data.Mod) ~= "table" then
		data.Mod = {}
	end
	return data
end

-- =====================================================================
-- BESITZER & GESPEICHERTE ROLLEN
-- =====================================================================
local function isOwner(p: Player): boolean
	local ok, result = call("AdminService", "IsAdmin", p)
	if ok then
		return result == true
	end
	return p:GetAttribute("IsAdmin") == true
end

local function isOwnerId(userId: number): boolean
	local online = Players:GetPlayerByUserId(userId)
	if online then
		return isOwner(online)
	end
	if has("AdminService", "IsOwnerId") then
		local ok, result = call("AdminService", "IsOwnerId", userId)
		return ok and result == true
	end
	return game.CreatorType == Enum.CreatorType.User and game.CreatorId ~= 0 and userId == game.CreatorId
end

local function storedRole(userId: number): string?
	local localMember = localMembers[userId]
	if localMember then
		return localMember.Role
	end
	local member = staffDoc.Members[idKey(userId)]
	return if member then member.Role else nil
end

local function storedRank(userId: number): number
	return Staff.Rank(storedRole(userId))
end

local function computeRole(p: Player): string?
	return Staff.ResolveRole({
		IsOwner = isOwner(p),
		Stored = storedRole(p.UserId),
		GroupRank = groupRank[p],
		Group = STAFF.Group,
	})
end

local function memberName(userId: number): string?
	local member = localMembers[userId] or staffDoc.Members[idKey(userId)]
	return if member and member.Name ~= "" then member.Name else nil
end

-- =====================================================================
-- REINE KERN-FUNKTIONEN (StaffTests)
-- =====================================================================

-- Team-Dokument prüfen und kopieren (nur gültige Einträge; nie mehr als DOC_SCAN_MAX lesen)
function Core.SanitizeDoc(raw: any): StaffDoc
	local doc: StaffDoc = { V = 1, Rev = 0, Members = {} }
	if type(raw) ~= "table" then
		return doc
	end
	if isInt(raw.Rev) and raw.Rev >= 0 then
		doc.Rev = raw.Rev
	end
	if type(raw.Members) == "table" then
		local scanned = 0
		for key, m in pairs(raw.Members) do
			scanned += 1
			if scanned > DOC_SCAN_MAX then
				break
			end
			if
				type(key) == "string"
				and #key <= 16
				and string.match(key, "^[1-9]%d*$") ~= nil
				and type(m) == "table"
				and (m.Role == "Admin" or m.Role == "Moderator")
			then
				doc.Members[key] = {
					Role = m.Role,
					Name = clip(m.Name, MAX_NAME),
					By = if isInt(m.By) then m.By else 0,
					ByName = clip(m.ByName, MAX_NAME),
					Since = if isInt(m.Since) and m.Since >= 0 then m.Since else 0,
				}
			end
		end
	end
	return doc
end

-- SetRole-Transform (§16.2 Nr. 3): Rechte mit dem FRISCHEN Dokument erneut prüfen (Handelnder UND Ziel).
-- change = { ActorId, ActorIsOwner, ActorGroupRank (0–2), TargetId, TargetIsOwner, TargetGroupRank (0–2),
--            Role ("Admin" | "Moderator" | nil = entfernen), Name, ByName, Now, Cfg }
-- Rückgabe (neues Dokument, nil) oder (nil, Lang-Schlüssel) = Abbruch (UpdateAsync schreibt dann nichts).
function Core.ApplyRole(raw: any, change: Plain): (StaffDoc?, string?)
	local doc = Core.SanitizeDoc(raw)
	local cfg = change.Cfg
	local members = doc.Members
	local function rankOf(userId: number, owner: boolean, group: number): number
		if owner then
			return OWNER_RANK
		end
		local member = members[idKey(userId)]
		local stored = if member then Staff.Rank(member.Role) else 0
		return math.max(stored, if Util.IsFinite(group) then group else 0)
	end
	local actorRank = rankOf(change.ActorId, change.ActorIsOwner == true, change.ActorGroupRank)
	local targetRank = rankOf(change.TargetId, change.TargetIsOwner == true, change.TargetGroupRank)
	local ok, key = Staff.CanSetRole(ROLE_BY_RANK[actorRank], targetRank, change.TargetIsOwner == true, change.Role, cfg)
	if not ok then
		return nil, key
	end
	local memberKey = idKey(change.TargetId)
	local current = members[memberKey]
	local currentRole = if current then current.Role else nil
	if currentRole == change.Role then
		return nil, "admin.role.same"
	end
	local maxMembers = if type(cfg) == "table" and isInt(cfg.MaxMembers) then cfg.MaxMembers else 100
	if change.Role ~= nil and current == nil and countKeys(members) >= maxMembers then
		return nil, "admin.role.full"
	end
	if change.Role ~= nil then
		members[memberKey] = {
			Role = change.Role,
			Name = clip(change.Name, MAX_NAME),
			By = if isInt(change.ActorId) then change.ActorId else 0,
			ByName = clip(change.ByName, MAX_NAME),
			Since = if isInt(change.Now) then change.Now else os.time(),
		}
	else
		members[memberKey] = nil
	end
	doc.Rev += 1
	return doc, nil
end

-- Ein Eintrag der Bann-Liste (BanIndex), geprüft und gekürzt; ungültig -> nil
function Core.CleanIndexEntry(raw: any): IndexEntry?
	if type(raw) ~= "table" then
		return nil
	end
	local untilT = raw.Until
	if not isInt(untilT) or (untilT ~= -1 and untilT < 1) then
		return nil
	end
	local by = if isInt(raw.By) then raw.By else 0
	local src = raw.Src
	return {
		Name = clip(raw.Name, MAX_NAME),
		Until = untilT,
		Reason = clip(raw.Reason, INDEX_REASON_MAX),
		By = by,
		ByName = clip(raw.ByName, MAX_NAME),
		T = if isInt(raw.T) and raw.T >= 0 then raw.T else 0,
		Src = if type(src) == "string" and SOURCES[src] then src elseif by == 0 then "Auto" else "Panel",
	}
end

function Core.SanitizeIndex(raw: any): IndexDoc
	local doc: IndexDoc = { V = 1, Rev = 0, Entries = {} }
	if type(raw) ~= "table" then
		return doc
	end
	if isInt(raw.Rev) and raw.Rev >= 0 then
		doc.Rev = raw.Rev
	end
	if raw.Imported == true then
		doc.Imported = true
	end
	if type(raw.Entries) == "table" then
		local scanned = 0
		for key, value in pairs(raw.Entries) do
			scanned += 1
			if scanned > DOC_SCAN_MAX then
				break
			end
			if type(key) == "string" and #key <= 16 and string.match(key, "^%-?[1-9]%d*$") ~= nil then
				local entry = Core.CleanIndexEntry(value)
				if entry then
					doc.Entries[key] = entry
				end
			end
		end
	end
	return doc
end

-- Abgelaufene Einträge raus, danach die ältesten über max. Gibt die Anzahl entfernter Einträge.
function Core.PruneIndex(doc: IndexDoc, now: number, max: number): number
	local removed = 0
	local keys: { string } = {}
	for key, entry in pairs(doc.Entries) do
		if entry.Until ~= -1 and entry.Until <= now then
			doc.Entries[key] = nil
			removed += 1
		else
			table.insert(keys, key)
		end
	end
	local limit = math.max(0, math.floor(if Util.IsFinite(max) then max else 500))
	if #keys > limit then
		table.sort(keys, function(a, b)
			local ta, tb = doc.Entries[a].T, doc.Entries[b].T
			if ta ~= tb then
				return ta < tb
			end
			return a < b
		end)
		for i = 1, #keys - limit do
			doc.Entries[keys[i]] = nil
			removed += 1
		end
	end
	return removed
end

-- Suche über aktive Einträge (Teilstring klein in Name/ByName/Reason oder exakte UserId), neueste zuerst.
-- Gibt (Liste von Kopien mit UserId und Left, Anzahl abgelaufener Einträge).
function Core.SearchIndex(entries: { [string]: IndexEntry }, query: any, now: number): ({ Plain }, number)
	local q = if type(query) == "string" then string.lower(clip(query, 30)) else ""
	local qId = if string.match(q, "^%d+$") then tonumber(q) else nil
	local list: { Plain } = {}
	local expired = 0
	for key, e in pairs(entries) do
		local userId = tonumber(key)
		if e.Until ~= -1 and e.Until <= now then
			expired += 1
		elseif userId then
			local hit = q == ""
				or (qId ~= nil and userId == qId)
				or string.find(string.lower(e.Name), q, 1, true) ~= nil
				or string.find(string.lower(e.ByName), q, 1, true) ~= nil
				or string.find(string.lower(e.Reason), q, 1, true) ~= nil
			if hit then
				table.insert(list, {
					UserId = userId,
					Name = if e.Name ~= "" then e.Name else key,
					Reason = e.Reason,
					By = e.By,
					ByName = e.ByName,
					T = e.T,
					Until = e.Until,
					Left = if e.Until == -1 then -1 else e.Until - now,
					Src = e.Src,
				})
			end
		end
	end
	table.sort(list, function(a, b)
		if a.T ~= b.T then
			return a.T > b.T
		end
		return a.UserId < b.UserId
	end)
	return list, expired
end

-- Seite aus einer Liste: (Einträge, Seite, Seiten) – Seite wird auf 1…Seiten geklemmt
function Core.PageOf(list: { any }, page: any, size: number): ({ any }, number, number)
	local per = math.max(1, math.floor(if Util.IsFinite(size) then size else 25))
	local pages = math.max(1, math.ceil(#list / per))
	local current = if isInt(page) then math.clamp(page, 1, pages) else 1
	local out: { any } = {}
	for i = (current - 1) * per + 1, math.min(#list, current * per) do
		table.insert(out, list[i])
	end
	return out, current, pages
end

-- Einmaliger Import aus dem Bann-Log (AntiCheatService.BanLog): je UserId entscheidet der NEUESTE Eintrag;
-- übernommen nur aktive, nicht abgelaufene Banns echter Spieler (UserId > 0).
function Core.ImportEntries(banLog: any, now: number): { [string]: IndexEntry }
	local out: { [string]: IndexEntry } = {}
	if type(banLog) ~= "table" then
		return out
	end
	local list: { Plain } = {}
	for i, entry in ipairs(banLog) do
		if i > DOC_SCAN_MAX then
			break
		end
		if type(entry) == "table" and isInt(entry.UserId) and isInt(entry.T) then
			table.insert(list, entry)
		end
	end
	table.sort(list, function(a, b)
		return a.T > b.T
	end)
	local seen: { [number]: boolean } = {}
	for _, entry in ipairs(list) do
		local userId = entry.UserId
		if not seen[userId] then
			seen[userId] = true
			local duration = if isInt(entry.Duration) then entry.Duration else -1
			local untilT = if duration == -1 then -1 else entry.T + duration
			if entry.Active == true and userId > 0 and (untilT == -1 or untilT > now) then
				local clean = Core.CleanIndexEntry({
					Name = entry.Name,
					Until = untilT,
					Reason = entry.Reason,
					By = entry.By,
					ByName = entry.ByName,
					T = entry.T,
					Src = "Import",
				})
				if clean then
					out[idKey(userId)] = clean
				end
			end
		end
	end
	return out
end

-- Abgleich mit Roblox: last = neuester Eintrag aus GetBanHistoryAsync { Ban, Start (Unix), Duration } oder nil
function Core.ReconcileState(entry: Plain, last: Plain?, now: number): string
	if type(entry) ~= "table" or type(last) ~= "table" or not Util.IsFinite(last.Start) then
		return "Unknown"
	end
	local duration = if Util.IsFinite(last.Duration) then last.Duration else -1
	if last.Ban == false then
		if last.Start > (tonumber(entry.T) or 0) then
			return "Unbanned" -- außerhalb des Spiels aufgehoben (z. B. Creator Hub)
		end
		return "Unknown"
	end
	if last.Ban == true then
		if duration == -1 or duration < 0 or last.Start + duration > now then
			return "Active"
		end
		return "Expired"
	end
	return "Unknown"
end

-- Request "StaffCommand": genau der Schlüssel Text, 2–300 Byte, ";" vorne, bekannter Befehl -> Text, sonst nil
function Core.CommandArg(arg: any): string?
	if type(arg) ~= "table" then
		return nil
	end
	local count = 0
	for key in pairs(arg) do
		count += 1
		if key ~= "Text" or count > 1 then
			return nil
		end
	end
	local text = arg.Text
	if type(text) ~= "string" or #text < 2 or #text > MAX_COMMAND or string.sub(text, 1, 1) ~= ";" then
		return nil
	end
	return if Staff.IsCommandText(text, ";") then text else nil
end

-- Rest des Befehls-Texts nach skip Wörtern (Befehl zählt mit), Leerzeichen bleiben wie getippt
function Core.Tail(raw: string, skip: number): string
	local text = string.sub(raw, 1, MAX_COMMAND)
	local pos = 1
	for _ = 1, skip do
		local _, stop = string.find(text, "%S+", pos)
		if not stop then
			return ""
		end
		pos = stop + 1
	end
	return trim(string.sub(text, pos))
end

-- NUR Studio-SelfTests: Rolle eines Spielers vorübergehend überschreiben ("Admin" | "Moderator" | "" = Spieler,
-- nil = aufheben). Kein Attribut, keine Nachricht, nichts gespeichert; live wirkungslos (false).
function Core.StudioRole(p: Player, role: string?): boolean
	if not IS_STUDIO or not isPlayer(p) or p.Parent ~= Players then
		return false
	end
	if role == nil then
		testRole[p] = nil
	elseif role == "" then
		testRole[p] = false
	elseif role == "Admin" or role == "Moderator" then
		testRole[p] = role
	else
		return false
	end
	return true
end

StaffService.Core = Core

-- =====================================================================
-- ROLLEN (nie yieldend)
-- =====================================================================
function StaffService.RoleOf(p: Player): string?
	if not isPlayer(p) then
		return nil
	end
	if IS_STUDIO then
		local override = testRole[p]
		if override ~= nil then
			return override or nil
		end
	end
	local cached = roleCache[p]
	if cached ~= nil then
		return cached or nil
	end
	return computeRole(p)
end

function StaffService.Rank(p: Player): number
	return Staff.Rank(StaffService.RoleOf(p))
end

function StaffService.IsStaff(p: Player): boolean
	return StaffService.Rank(p) >= 1
end

function StaffService.Can(p: Player, perm: string): boolean
	return Staff.Can(StaffService.RoleOf(p), perm, STAFF)
end

-- online: Rang des Spielers; offline: Besitzer 3, sonst gespeicherte Rolle (+ zuletzt bekannter Gruppen-Rang)
function StaffService.RankOfUserId(userId: number): number
	if not isInt(userId) then
		return 0
	end
	local online = Players:GetPlayerByUserId(userId)
	if online then
		return StaffService.Rank(online)
	end
	if isOwnerId(userId) then
		return OWNER_RANK
	end
	local cached = groupCache[userId]
	return math.max(storedRank(userId), if cached then cached.Rank else 0)
end

function StaffService.CanActOn(actor: Player, target: any): boolean
	if not isPlayer(actor) then
		return false
	end
	local actorRank = StaffService.Rank(actor)
	if isPlayer(target) then
		return Staff.CanActOn(actorRank, StaffService.Rank(target))
	elseif isInt(target) then
		return Staff.CanActOn(actorRank, StaffService.RankOfUserId(target))
	end
	return false
end

function StaffService.MoveExempt(p: Player): boolean
	if not isPlayer(p) then
		return false
	end
	return isOwner(p) or StaffService.Can(p, "Fly") or StaffService.Can(p, "Noclip")
end

-- Gruppen-Rolle (0–2) einer UserId, yieldet (GetGroupsAsync, 60 s Cache). (Rang, bekannt, roher Gruppen-Rang)
local function groupRoleAsync(userId: number): (number, boolean, number)
	if not groupEnabled() then
		return 0, true, 0
	end
	local online = Players:GetPlayerByUserId(userId)
	if online and groupLoaded[online] then
		local raw = groupRank[online] or 0
		return groupRoleRank(raw), true, raw
	end
	if userId <= 0 then
		return 0, true, 0
	end
	local cached = groupCache[userId]
	if cached and os.clock() - cached.At < GROUP_CACHE_SECONDS then
		return cached.Rank, true, cached.Raw
	end
	local ok, groups = pcall(function()
		return GroupService:GetGroupsAsync(userId)
	end)
	if not ok or type(groups) ~= "table" then
		return OWNER_RANK, false, 0 -- unbekannt = geschützt (§16.2 Nr. 2)
	end
	local raw = 0
	for i, info in ipairs(groups) do
		if i > 500 then
			break
		end
		if type(info) == "table" and info.Id == STAFF.Group.Id then
			raw = tonumber(info.Rank) or 0
			break
		end
	end
	if countKeys(groupCache) >= GROUP_CACHE_MAX then
		table.clear(groupCache)
	end
	local rank = groupRoleRank(raw)
	groupCache[userId] = { Rank = rank, Raw = raw, At = os.clock() }
	return rank, true, raw
end

local function groupCached(userId: number): boolean
	local cached = groupCache[userId]
	return not groupEnabled() or (cached ~= nil and os.clock() - cached.At < GROUP_CACHE_SECONDS)
end

-- §16.2 Nr. 2: Rang auch offline mit Gruppen-Rang. Yieldet. Fehler -> (3, false) = geschützt.
function StaffService.RankOfUserIdAsync(userId: number): (number, boolean)
	if not isInt(userId) or userId == 0 then
		return OWNER_RANK, false
	end
	local online = Players:GetPlayerByUserId(userId)
	if online then
		return StaffService.Rank(online), true
	end
	if isOwnerId(userId) then
		return OWNER_RANK, true
	end
	local group, known = groupRoleAsync(userId)
	if not known then
		return OWNER_RANK, false
	end
	return math.max(storedRank(userId), group), true
end

function StaffService.WaitReady(timeout: number): boolean
	local limit = if Util.IsFinite(timeout) then math.clamp(timeout, 0, 30) else 5
	local deadline = os.clock() + limit
	while not docReady and os.clock() < deadline do
		task.wait(0.1)
	end
	return docReady
end

local function roleReady(p: Player): boolean
	return docReady and (not groupEnabled() or groupLoaded[p] == true)
end

-- §16.2 Nr. 10: Team-Dokument UND Gruppen-Rang geladen (Server-Sperre soll Gruppen-Moderatoren nicht kicken)
function StaffService.WaitRole(p: Player, timeout: number): boolean
	if not isPlayer(p) then
		return false
	end
	local limit = if Util.IsFinite(timeout) then math.clamp(timeout, 0, 30) else 6
	local deadline = os.clock() + limit
	while not roleReady(p) and p.Parent == Players and os.clock() < deadline do
		task.wait(0.1)
	end
	return roleReady(p)
end

-- =====================================================================
-- SYSTEM-NACHRICHTEN (Effekt ChatSystem – nur an den Handelnden / einen bestraften Spieler)
-- =====================================================================
function StaffService.Say(p: Player, text: string, kind: string?, lines: { string }?)
	if not isPlayer(p) or p.Parent ~= Players or type(text) ~= "string" then
		return
	end
	local cleanLines: { string }? = nil
	if type(lines) == "table" then
		local out: { string } = {}
		for i, line in ipairs(lines) do
			if i > MAX_SAY_LINES then
				break
			end
			if type(line) == "string" then
				table.insert(out, truncate(line, MAX_SAY_LINE))
			end
		end
		cleanLines = if #out > 0 then out else nil
	end
	local data = {
		Text = truncate(text, MAX_SAY_TEXT),
		Kind = if type(kind) == "string" and SAY_KINDS[kind] then kind else "Info",
		Lines = cleanLines,
	}
	call("PlayerStateService", "Effect", p, "ChatSystem", 0, data)
end

function StaffService.SayKey(p: Player, key: string, args: { any }?, kind: string?)
	if not isPlayer(p) or type(key) ~= "string" then
		return
	end
	local text = if type(args) == "table" then L(p, key, table.unpack(args, 1, 8)) else L(p, key)
	StaffService.Say(p, text, kind)
end

local function sayResult(p: Player, ok: boolean, message: any)
	if type(message) == "string" and message ~= "" then
		StaffService.Say(p, message, if ok then "Ok" else "Err")
	end
end

-- Fehler von Staff.MatchTargets übersetzen (mehrdeutig: errArg = "<Text>|<Namen>")
local function targetError(p: Player, key: string?, arg: any): string
	local errKey = key or "admin.cmd.noTarget"
	local text = if type(arg) == "string" then arg else ""
	if errKey == "admin.cmd.ambiguous" then
		local what, names = string.match(text, "^(.-)|(.*)$")
		return L(p, errKey, what or text, names or "")
	end
	return L(p, errKey, text)
end

-- Begrüßung neuer Teammitglieder: kurz nach dem Beitritt verzögert (ChatTools muss geladen sein)
local function greet(p: Player, role: string)
	local wait = GREET_DELAY - (os.clock() - (joinedAt[p] or -math.huge))
	if wait <= 0 then
		StaffService.SayKey(p, "admin.role.youGot", { roleLabel(p, role) }, "Ok")
		return
	end
	task.delay(wait, function()
		if p.Parent == Players and roleCache[p] == role then
			StaffService.SayKey(p, "admin.role.youGot", { roleLabel(p, role) }, "Ok")
		end
	end)
end

-- =====================================================================
-- REFRESH (einziger Ort, der das Attribut "Role" setzt)
-- =====================================================================
function StaffService.Refresh(p: Player)
	if not isPlayer(p) or p.Parent ~= Players then
		return
	end
	local role = computeRole(p)
	roleCache[p] = role or false
	local raw = p:GetAttribute("Role")
	local old: string? = if type(raw) == "string" and Staff.RANK[raw] then raw else nil
	if role == old then
		return
	end
	p:SetAttribute("Role", role)
	local newRank, oldRank = Staff.Rank(role), Staff.Rank(old)
	if newRank > oldRank and role then
		if Staff.Can(role, "Fly", STAFF) and p:GetAttribute("CanFly") == nil then
			p:SetAttribute("CanFly", true)
		end
		if role ~= "Owner" then
			greet(p, role) -- Besitzer wird nie begrüßt
		end
	end
	call("AdminService", "SyncPowers", p) -- löscht Kräfte, die die neue Rolle nicht hat (auch bei Herabstufung)
	if newRank < oldRank then
		pcall(function()
			p.ReplicationFocus = nil -- Zuschauen (Server-Fokus) beenden
		end)
		if role then
			StaffService.SayKey(p, "admin.role.youGot", { roleLabel(p, role) }, "Info")
		else
			StaffService.SayKey(p, "admin.role.youLost", nil, "Info")
		end
	end
end

local function refreshAll()
	for _, p in ipairs(Players:GetPlayers()) do
		StaffService.Refresh(p)
	end
end

-- =====================================================================
-- MESSAGINGSERVICE "AT_Staff" (Sender wendet selbst an; Dedupe per Id)
-- =====================================================================
local function broadcast(message: Plain)
	if type(message.Id) == "string" then
		dedupe.Seen(message.Id) -- eigenes Echo verwerfen
	end
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:PublishAsync(Config.Tech.StaffTopic, message)
		end)
		if not ok and not publishWarned then
			publishWarned = true
			warn("[Staff] Senden an andere Server fehlgeschlagen (nur dieser Server): " .. tostring(err))
		end
	end)
end

local loadDoc: () -> ()

local function scheduleReload()
	if reloadPending or modOff then
		return
	end
	reloadPending = true
	task.delay(RELOAD_DELAY, function()
		reloadPending = false
		if not docLoading then
			loadDoc()
		end
	end)
end

local function banUntilText(p: Player, untilT: number): string
	if untilT == -1 then
		return L(p, "admin.ban2.forever")
	end
	return L(p, "admin.ban2.left", Format.Duration(untilT - os.time(), langOf(p)))
end

local function banReasonText(p: Player, reason: any): string
	return if type(reason) == "string" and reason ~= "" then reason else L(p, "admin.banDefault")
end

-- Gebannten Spieler hier hinauswerfen (Rückfall, falls BanAsync nicht gekickt hat). Besitzer nie.
local function applyKick(userId: number, reason: string, untilT: number)
	local p = Players:GetPlayerByUserId(userId)
	if not p or isOwner(p) then
		return
	end
	local text = L(p, "admin.ban2.kick", banUntilText(p, untilT), banReasonText(p, reason))
	pcall(function()
		p:Kick(text)
	end)
end

local function notifyReport(fromId: number?, fromName: string, targetName: string, reason: string, key: string)
	for _, p in ipairs(Players:GetPlayers()) do
		if p.UserId ~= fromId and StaffService.Can(p, "Reports") then
			local last = notifyAt[p]
			if not last or os.clock() - last >= (tonumber(STAFF.ReportNotifyGap) or 15) then
				notifyAt[p] = os.clock()
				local args = { fromName, targetName, L(p, "admin.reason." .. reason) }
				StaffService.SayKey(p, key, args, "Warn")
				call("PlayerStateService", "Notify", p, key, args, "Alarm")
				call("PlayerStateService", "Effect", p, "StaffDo", 0, { Do = "Report" })
			end
		end
	end
end

local function applyRoleMessage(msg: Plain)
	local key = idKey(msg.UserId)
	local newRole: string? = if msg.Role == "" then nil else msg.Role
	if msg.Rev > staffDoc.Rev then
		local old = staffDoc.Members[key]
		if newRole then
			staffDoc.Members[key] = {
				Role = newRole,
				Name = if old then old.Name else "",
				By = msg.By,
				ByName = if old then old.ByName else "",
				Since = os.time(),
			}
		else
			staffDoc.Members[key] = nil
		end
		staffDoc.Rev = msg.Rev
		scheduleReload() -- Namen/weitere Änderungen nachladen
	elseif msg.Rev < staffDoc.Rev or storedRole(msg.UserId) ~= newRole then
		scheduleReload() -- alte oder abweichende Nachricht: Dokument entscheidet (§16.2 Nr. 4)
	end
	local p = Players:GetPlayerByUserId(msg.UserId)
	if p then
		StaffService.Refresh(p)
	end
end

local function handleMessage(data: any)
	local msg = Staff.ValidateMsg(data, os.time())
	if not msg or dedupe.Seen(msg.Id) then
		return
	end
	if msg.Kind == "Role" then
		applyRoleMessage(msg)
	elseif msg.Kind == "Kick" then
		applyKick(msg.UserId, msg.Reason, msg.Until)
	elseif msg.Kind == "Report" then
		notifyReport(nil, msg.FromName, msg.TargetName, msg.Reason, "admin.rep.newOther")
	end
end

-- =====================================================================
-- TEAM-DOKUMENT (AT_Mod_v1 "Staff")
-- =====================================================================
loadDoc = function()
	if docLoading then
		return
	end
	docLoading = true
	local ok, raw = storeCall(function(store)
		return store:GetAsync(DOC_KEY)
	end)
	docLoading = false
	if ok then
		local fresh = Core.SanitizeDoc(raw)
		if fresh.Rev >= staffDoc.Rev then
			staffDoc = fresh
		else
			scheduleReload() -- Nachricht war neuer als der (gecachte) Lesestand
		end
		docLoaded = true
	end
	docReady = true
	refreshAll() -- verlorene Rollen-Nachrichten heilen
end

local function reloadDocJob()
	if docLoading or modOff then
		return
	end
	task.spawn(loadDoc)
end

-- =====================================================================
-- STUMMSCHALTEN
-- =====================================================================
local function isMutedId(userId: number): boolean
	local untilT = mutedUntil[userId]
	return untilT ~= nil and (untilT == -1 or untilT > os.time())
end

function StaffService.IsMuted(p: Player): boolean
	return isPlayer(p) and isMutedId(p.UserId)
end

-- CanSend auf allen Kanälen (auch Flüster-Kanälen) setzen
local function setCanSend(userId: number, can: boolean)
	local channels = TextChatService:FindFirstChild("TextChannels")
	if not channels then
		return
	end
	for _, channel in ipairs(channels:GetChildren()) do
		if channel:IsA("TextChannel") then
			for _, source in ipairs(channel:GetChildren()) do
				if source:IsA("TextSource") and source.UserId == userId then
					pcall(function()
						source.CanSend = can
					end)
				end
			end
		end
	end
end

-- Sprachchat (best effort): nur AudioDeviceInput direkt am Spieler; gemerkt, damit wir nur eigene freigeben
local function muteVoiceDevice(device: Instance): boolean
	if not device:IsA("AudioDeviceInput") then
		return false
	end
	if device:GetAttribute(VOICE_ATTR) == true then
		return true
	end
	local ok = pcall(function()
		local input: any = device
		input.Muted = true
		device:SetAttribute(VOICE_ATTR, true)
	end)
	return ok
end

local function muteVoice(p: Player): number
	local count = 0
	for _, child in ipairs(p:GetChildren()) do
		if muteVoiceDevice(child) then
			count += 1
		end
	end
	return count
end

local function restoreVoice(p: Player)
	for _, child in ipairs(p:GetChildren()) do
		if child:GetAttribute(VOICE_ATTR) == true then
			pcall(function()
				local input: any = child
				input.Muted = false
			end)
			child:SetAttribute(VOICE_ATTR, nil)
		end
	end
end

local function muteLeftText(p: Player, untilT: number): string
	if untilT == -1 then
		return L(p, "admin.mute.forever")
	end
	return Format.Duration(math.max(0, untilT - os.time()), langOf(p))
end

-- Stumm schalten: Speicher, CanSend, Sprachchat, Attribut, Profil (+ Nachricht an den Spieler). Gibt Anzahl Mikrofone.
local function applyMute(p: Player, untilT: number, byId: number, reason: string, tell: boolean): number
	mutedUntil[p.UserId] = untilT
	setCanSend(p.UserId, false)
	local voice = if STAFF.MuteVoice == true then muteVoice(p) else 0
	p:SetAttribute("MutedUntil", untilT)
	local data = profileOf(p)
	if data then
		data.Mod.MuteUntil = untilT
		data.Mod.MuteBy = byId
		data.Mod.MuteReason = reason
	end
	if tell then
		local args = { muteLeftText(p, untilT), reason }
		StaffService.SayKey(p, "admin.mute.you", args, "Warn")
		call("PlayerStateService", "Notify", p, "admin.mute.you", args, "Alarm")
	end
	return voice
end

local function clearMute(p: Player)
	mutedUntil[p.UserId] = nil
	setCanSend(p.UserId, true)
	restoreVoice(p)
	p:SetAttribute("MutedUntil", nil)
	local data = profileOf(p)
	if data then
		data.Mod.MuteUntil = nil
		data.Mod.MuteBy = nil
		data.Mod.MuteReason = nil
	end
end

-- 1 Hz (Scheduler, yieldet nie)
local function expireMutes()
	local now = os.time()
	local done: { number }? = nil
	for userId, untilT in pairs(mutedUntil) do
		if untilT ~= -1 and now >= untilT then
			done = done or {}
			table.insert(done :: { number }, userId)
		end
	end
	if not done then
		return
	end
	for _, userId in ipairs(done) do
		local p = Players:GetPlayerByUserId(userId)
		if p then
			clearMute(p)
			StaffService.SayKey(p, "admin.mute.youEnd", nil, "Ok")
		else
			mutedUntil[userId] = nil
		end
	end
end

-- Spielstand geladen: gespeicherte Stummschaltung weiter anwenden (still) bzw. abgelaufene löschen
local function applyStoredMute(p: Player, data: any)
	if p.Parent ~= Players or type(data) ~= "table" or type(data.Mod) ~= "table" then
		return
	end
	local mod = data.Mod
	local untilT = mod.MuteUntil
	if untilT == -1 or (isInt(untilT) and untilT > os.time()) then
		local reason = if type(mod.MuteReason) == "string" then mod.MuteReason else ""
		applyMute(p, untilT, if isInt(mod.MuteBy) then mod.MuteBy else 0, reason, false)
		StaffService.SayKey(p, "admin.mute.youStill", { muteLeftText(p, untilT) }, "Warn")
	elseif untilT ~= nil then
		mod.MuteUntil = nil
		mod.MuteBy = nil
		mod.MuteReason = nil
	end
end

local function cleanReason(actor: Player, value: any, maxChars: number): string?
	local text = clip(value, maxChars)
	if text == "" then
		return nil
	end
	return filterBroadcast(text, actor.UserId)
end

-- Ziele für Mute/Unmute: (Liste, Fehlertext?) inkl. Masse-Regel (all/others oder > 3 Ziele = MassTarget)
local function muteTargets(actor: Player, target: any): ({ Player }, string?)
	local list, key, arg = Staff.MatchTargets(target, Players:GetPlayers(), actor)
	if #list == 0 then
		return {}, targetError(actor, key, arg)
	end
	if (Staff.IsMass(target) or #list > MASS_LIST) and not StaffService.Can(actor, "MassTarget") then
		return {}, L(actor, "admin.cmd.mass")
	end
	local players: { Player } = {}
	for _, p in ipairs(list) do
		table.insert(players, p :: Player)
	end
	return players, nil
end

local function displayNames(list: { Player }): string
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

-- Admin-Aktion "Mute" (über AdminService.Run). args { Target, Duration?, Seconds?, Reason? }
function StaffService.Mute(actor: Player, args: any): (boolean, string)
	if not isPlayer(actor) or actor.Parent ~= Players then
		return false, ""
	end
	if type(args) ~= "table" then
		return false, L(actor, "core.invalid")
	end
	local targets, err = muteTargets(actor, args.Target)
	if err then
		return false, err
	end
	local role = StaffService.RoleOf(actor)
	local max = if role and STAFF.MuteMax then STAFF.MuteMax[role] else nil
	local limit = if Util.IsFinite(max) then max else 0
	local seconds: number?
	if args.Duration ~= nil then
		seconds = Staff.ParseDuration(args.Duration)
	elseif args.Seconds ~= nil then
		seconds = if isInt(args.Seconds) then args.Seconds else nil
	else
		-- ohne Dauer: Standard, auf das Rollen-Maximum gekürzt
		seconds = Staff.ParseDuration(STAFF.DefaultMute) or 600
		if limit ~= -1 and (seconds == -1 or (seconds :: number) > limit) then
			seconds = limit
		end
	end
	if seconds == nil or (seconds ~= -1 and (seconds :: number) < MIN_MUTE) then
		return false, L(actor, "admin.cmd.badDuration")
	end
	local secs = seconds :: number
	if limit ~= -1 and (secs == -1 or secs > limit) then
		return false, L(actor, "admin.cmd.maxDuration", Format.Duration(limit, langOf(actor)))
	end
	local reason = cleanReason(actor, args.Reason, MUTE_REASON_MAX)
	local untilT = if secs == -1 then -1 else os.time() + secs
	local done: { Player } = {}
	local skipped: { Player } = {}
	local voiced = 0
	local actorRank = StaffService.Rank(actor)
	for _, p in ipairs(targets) do
		if p ~= actor then
			if Staff.CanActOn(actorRank, StaffService.Rank(p)) then
				local text = reason or L(p, "admin.mute.defaultReason")
				voiced += applyMute(p, untilT, actor.UserId, text, true)
				table.insert(done, p)
			else
				table.insert(skipped, p)
			end
		end
	end
	if #done == 0 then
		if #skipped > 0 then
			return false, L(actor, "admin.cmd.rank", displayNames(skipped))
		end
		return false, L(actor, "admin.notSelf")
	end
	local duration = if secs == -1 then L(actor, "admin.mute.forever") else Format.Duration(secs, langOf(actor))
	local message = L(actor, "admin.mute.done", displayNames(done), duration)
	if voiced > 0 then
		message = L(actor, "admin.mute.voice", message)
	end
	if #skipped > 0 then
		message ..= " · " .. L(actor, "admin.cmd.skipped", #skipped)
	end
	return true, message
end

-- Admin-Aktion "Unmute". Undo-Regel §16.2 Nr. 5: nicht für sich selbst (außer Owner), Rang ≥ Rang des Stummschaltenden.
function StaffService.Unmute(actor: Player, args: any): (boolean, string)
	if not isPlayer(actor) or actor.Parent ~= Players then
		return false, ""
	end
	if type(args) ~= "table" then
		return false, L(actor, "core.invalid")
	end
	local targets, err = muteTargets(actor, args.Target)
	if err then
		return false, err
	end
	local actorRank = StaffService.Rank(actor)
	local actorIsOwner = isOwner(actor)
	local done: { Player } = {}
	local skipped: { Player } = {}
	local notMuted: { Player } = {}
	for _, p in ipairs(targets) do
		if mutedUntil[p.UserId] == nil then
			table.insert(notMuted, p)
		else
			local data = profileOf(p)
			local by = if data and isInt(data.Mod.MuteBy) then data.Mod.MuteBy else 0
			local punisherRank = 0
			if by ~= 0 then
				punisherRank = StaffService.RankOfUserIdAsync(by)
			end
			if Staff.CanUndo(actorRank, punisherRank, p == actor, actorIsOwner) then
				clearMute(p)
				StaffService.SayKey(p, "admin.mute.youEnd", nil, "Ok")
				table.insert(done, p)
			else
				table.insert(skipped, p)
			end
		end
	end
	if #done == 0 then
		if #skipped > 0 then
			return false, L(actor, "admin.cmd.rank", displayNames(skipped))
		end
		return false, L(actor, "admin.mute.notMuted", displayNames(notMuted))
	end
	local message = L(actor, "admin.mute.undone", displayNames(done))
	if #skipped > 0 then
		message ..= " · " .. L(actor, "admin.cmd.skipped", #skipped)
	end
	return true, message
end

-- =====================================================================
-- BANN-LISTE (W26): Ban_<id> (Durchsetzung) + BanIndex (Tab „Banns“)
-- =====================================================================
local function indexMax(): number
	return if isInt(STAFF.BanIndexMax) then STAFF.BanIndexMax else 500
end

-- Bann-Liste lesen (10 s Cache; Fehler -> letzter Stand). Yieldet.
local function loadIndexAsync(): IndexDoc
	if modOff then
		return localIndex
	end
	local cached = indexCache
	if cached and os.clock() - cached.At < INDEX_CACHE_SECONDS then
		return cached.Doc
	end
	local ok, raw = storeCall(function(store)
		return store:GetAsync(INDEX_KEY)
	end)
	if ok then
		local doc = Core.SanitizeIndex(raw)
		indexCache = { Doc = doc, At = os.clock() }
		return doc
	end
	return if cached then cached.Doc else localIndex
end

-- Bann-Liste ändern: mutate(doc) -> geändert? läuft im UpdateAsync-Transform (nie yielden). Danach wird immer
-- aufgeräumt (abgelaufen, BanIndexMax). Nichts geändert -> kein Schreiben. Yieldet.
local function updateIndexAsync(mutate: (IndexDoc) -> boolean): boolean
	if modOff then
		mutate(localIndex)
		Core.PruneIndex(localIndex, os.time(), indexMax())
		return true
	end
	local ok, result = storeCall(function(store)
		return store:UpdateAsync(INDEX_KEY, function(old)
			local doc = Core.SanitizeIndex(old)
			local changed = mutate(doc)
			local pruned = Core.PruneIndex(doc, os.time(), indexMax())
			if not changed and pruned == 0 then
				return nil -- nichts zu tun (UpdateAsync bricht ab)
			end
			doc.Rev += 1
			return doc
		end)
	end)
	if ok and type(result) == "table" then
		indexCache = { Doc = Core.SanitizeIndex(result), At = os.clock() }
	elseif not ok and modOff then
		mutate(localIndex)
		return true
	end
	return ok
end

-- Eigener Bann (AdminService Ban, Anti-Cheat): Ban_<id> + BanIndex + Kick-Nachricht an alle Server. Yieldet.
-- entry = { UserId, Until (-1 | Unix), Reason, By, ByName, Name, Src? }
function StaffService.AddBan(entry: any): boolean
	if type(entry) ~= "table" then
		return false
	end
	local userId = entry.UserId
	local now = os.time()
	local untilT = entry.Until
	if not isInt(userId) or userId == 0 or not isInt(untilT) or (untilT ~= -1 and untilT <= now) then
		return false
	end
	if untilT ~= -1 then
		untilT = math.min(untilT, now + TEN_YEARS)
	end
	local online = Players:GetPlayerByUserId(userId)
	local name = clip(entry.Name, MAX_NAME)
	if name == "" then
		name = if online then online.Name else idKey(userId)
	end
	local reason = truncate(if type(entry.Reason) == "string" then entry.Reason else "", BAN_REASON_MAX)
	local ban = {
		Until = untilT,
		Reason = reason,
		By = if isInt(entry.By) then entry.By else 0,
		ByName = clip(entry.ByName, MAX_NAME),
		T = now,
		Name = name,
	}
	local indexEntry = Core.CleanIndexEntry({
		Name = name,
		Until = untilT,
		Reason = reason,
		By = ban.By,
		ByName = ban.ByName,
		T = now,
		Src = entry.Src,
	})
	local key = idKey(userId)
	local stored = false
	if userId > 0 and not modOff then
		stored = storeCall(function(store)
			return store:UpdateAsync(BAN_PREFIX .. key, function()
				return ban
			end)
		end)
	end
	local memoryOnly = userId <= 0 or modOff
	if not stored then
		localBans[userId] = ban -- Studio-Testspieler / ohne Speicher / Schreibfehler: gilt wenigstens hier
	end
	if indexEntry then
		if memoryOnly then
			localIndex.Entries[key] = indexEntry
		else
			local function add(doc: IndexDoc): boolean
				doc.Entries[key] = indexEntry :: IndexEntry
				return true
			end
			task.spawn(function()
				if not updateIndexAsync(add) then
					warn(("[Staff] Bann-Liste: %s nicht eingetragen – neuer Versuch in %d s"):format(key, INDEX_RETRY_SECONDS))
					task.delay(INDEX_RETRY_SECONDS, function()
						if not updateIndexAsync(add) then
							warn("[Staff] Bann-Liste: " .. key .. " fehlt in BanIndex (Sperre gilt trotzdem)")
						end
					end)
				end
			end)
		end
	end
	-- Kick hier sofort, auf allen anderen Servern per Nachricht (Rückfall, falls BanAsync nicht gekickt hat)
	applyKick(userId, reason, untilT)
	if userId > 0 then
		broadcast({ Kind = "Kick", Id = newId("K"), UserId = userId, Reason = reason, Until = untilT })
	end
	return stored or memoryOnly
end

-- Sperre aus der eigenen Liste entfernen (Ban_<id> + BanIndex). why ∈ Unban | Reconcile | Expired. Yieldet.
function StaffService.RemoveBan(userId: number, why: string?): boolean
	if not isInt(userId) or userId == 0 then
		return false
	end
	local reason = if type(why) == "string" and REMOVE_WHY[why] then why else "Unban"
	local key = idKey(userId)
	localBans[userId] = nil
	localIndex.Entries[key] = nil
	if userId <= 0 or modOff then
		return true
	end
	local okBan = storeCall(function(store)
		return store:RemoveAsync(BAN_PREFIX .. key)
	end)
	local okIndex = updateIndexAsync(function(doc)
		if doc.Entries[key] ~= nil then
			doc.Entries[key] = nil
			return true
		end
		return false
	end)
	if reason ~= "Unban" then
		print(("[Staff] Bann-Liste: %s entfernt (%s)"):format(key, reason))
	end
	return okBan and okIndex
end

-- Eintrag für die Entbann-Regel (By, Until): BanIndex, sonst Ban_<id>. Yieldet.
function StaffService.BanEntry(userId: number): Plain?
	if not isInt(userId) or userId == 0 then
		return nil
	end
	local key = idKey(userId)
	local function withId(entry: any): Plain?
		local clean = Core.CleanIndexEntry(entry)
		if not clean then
			return nil
		end
		local out: Plain = table.clone(clean)
		out.UserId = userId
		return out
	end
	local memory = localIndex.Entries[key] or localBans[userId]
	if userId <= 0 or modOff then
		return withId(memory)
	end
	local doc = loadIndexAsync()
	local entry = doc.Entries[key]
	if entry then
		return withId(entry)
	end
	local ok, raw = storeCall(function(store)
		return store:GetAsync(BAN_PREFIX .. key)
	end)
	if ok and type(raw) == "table" then
		return withId(raw)
	end
	return withId(memory)
end

local function pruneExpiredAsync()
	if pruning then
		return
	end
	pruning = true
	pcall(updateIndexAsync, function()
		return false -- nur aufräumen (abgelaufene Einträge)
	end)
	pruning = false
end

-- Neuester Eintrag einer GetBanHistoryAsync-Seite -> { Ban, Start, Duration } (Start per DateTime, pcall)
local function newestBan(page: { any }): Plain?
	local best: Plain? = nil
	for i, e in ipairs(page) do
		if i > 100 then
			break
		end
		if type(e) == "table" then
			local ok, start = pcall(function()
				return DateTime.fromIsoDate(e.StartTime).UnixTimestamp
			end)
			if ok and Util.IsFinite(start) and (best == nil or start >= (best :: Plain).Start) then
				best = { Ban = e.Ban == true, Start = start, Duration = tonumber(e.Duration) or -1 }
			end
		end
	end
	return best
end

-- Abgleich mit Roblox (nur live): höchstens BanReconcile.PerRequest Ids ohne frischen Cache. Yieldet.
function StaffService.Reconcile(ids: any): { [number]: string }
	local out: { [number]: string } = {}
	if IS_STUDIO or modOff or type(ids) ~= "table" or reconciling then
		return out
	end
	reconciling = true
	local ok, err = pcall(function()
		local cfg = STAFF.BanReconcile or {}
		local perRequest = if isInt(cfg.PerRequest) then cfg.PerRequest else 5
		local cacheSeconds = if Util.IsFinite(cfg.CacheSeconds) then cfg.CacheSeconds else 600
		local doc = loadIndexAsync()
		local checked = 0
		for i, userId in ipairs(ids) do
			if i > RECONCILE_IDS_MAX then
				break
			end
			if isInt(userId) and userId > 0 then
				local cached = reconcileCache[userId]
				local entry = doc.Entries[idKey(userId)]
				if cached and os.clock() - cached.At < cacheSeconds then
					out[userId] = cached.State
				elseif entry and checked < perRequest then
					checked += 1
					local okPage, page = pcall(function()
						return Players:GetBanHistoryAsync(userId):GetCurrentPage()
					end)
					local state = "Unknown"
					if okPage and type(page) == "table" then
						state = Core.ReconcileState(entry, newestBan(page), os.time())
					end
					reconcileCache[userId] = { State = state, At = os.clock() }
					out[userId] = state
					if state == "Unbanned" then
						StaffService.RemoveBan(userId, "Reconcile")
					elseif state == "Expired" then
						StaffService.RemoveBan(userId, "Expired")
					end
				end
			end
		end
		if countKeys(reconcileCache) > indexMax() * 2 then
			for userId, cached in pairs(reconcileCache) do
				if os.clock() - cached.At >= cacheSeconds then
					reconcileCache[userId] = nil
				end
			end
		end
	end)
	reconciling = false
	if not ok then
		warn("[Staff] Abgleich mit Roblox fehlgeschlagen: " .. tostring(err))
	end
	return out
end

-- Tab „Banns“: args { Query?, Page? } -> { Entries, Total, Page, Pages, Reconciled }. Yieldet.
function StaffService.BanList(args: any): Plain
	local query = if type(args) == "table" and type(args.Query) == "string" then args.Query else ""
	local page = if type(args) == "table" then args.Page else 1
	local now = os.time()
	local doc = loadIndexAsync()
	local merged: { [string]: IndexEntry } = {}
	for key, entry in pairs(doc.Entries) do
		merged[key] = entry
	end
	if doc ~= localIndex then
		for key, entry in pairs(localIndex.Entries) do
			merged[key] = entry -- Studio-Testspieler / Schreibfehler
		end
	end
	local list, expired = Core.SearchIndex(merged, query, now)
	if expired > 0 and not modOff then
		task.spawn(pruneExpiredAsync)
	end
	local size = if isInt(STAFF.BanPageSize) then STAFF.BanPageSize else 25
	local entries, pageNo, pages = Core.PageOf(list, page, size)
	for _, e in ipairs(entries) do
		local cached = reconcileCache[e.UserId]
		e.State = if cached then cached.State else "Unknown"
	end
	return {
		Entries = entries,
		Total = #list,
		Page = pageNo,
		Pages = pages,
		Reconciled = not IS_STUDIO and not modOff,
	}
end

-- Einmaliger Import aus dem Bann-Log, wenn BanIndex noch nie importiert wurde (fehlt oder ohne Import-Marke).
-- Bestehende Einträge bleiben; für Importe kein Ban_<id> (Roblox setzt sie durch).
local function importIndexOnce()
	if modOff then
		return
	end
	local ok, raw = storeCall(function(store)
		return store:GetAsync(INDEX_KEY)
	end)
	if not ok or (type(raw) == "table" and raw.Imported == true) then
		return
	end
	local okLog, banLog = call("AntiCheatService", "BanLog")
	if not okLog or type(banLog) ~= "table" then
		return
	end
	local imported = Core.ImportEntries(banLog, os.time())
	local added = 0
	updateIndexAsync(function(doc)
		if doc.Imported == true then
			return false
		end
		added = 0
		for key, entry in pairs(imported) do
			if doc.Entries[key] == nil then
				doc.Entries[key] = entry
				added += 1
			end
		end
		doc.Imported = true
		return true
	end)
	if added > 0 then
		print(("[Staff] Bann-Liste: %d Banns aus dem Bann-Log übernommen"):format(added))
	end
end

-- Beim Beitritt: eigene Sperrliste durchsetzen (Fehler = erlauben). Besitzer nie. Yieldet.
local function enforceOwnBan(p: Player)
	if isOwner(p) then
		return
	end
	local userId = p.UserId
	local ban: any = localBans[userId]
	if ban == nil and userId > 0 and not modOff then
		local ok, raw = storeCall(function(store)
			return store:GetAsync(BAN_PREFIX .. idKey(userId))
		end)
		if ok and type(raw) == "table" then
			ban = raw
		end
	end
	if type(ban) ~= "table" or not isInt(ban.Until) then
		return
	end
	if ban.Until == -1 or ban.Until > os.time() then
		if p.Parent == Players then
			local text = L(p, "admin.ban2.kick", banUntilText(p, ban.Until), banReasonText(p, ban.Reason))
			pcall(function()
				p:Kick(text)
			end)
		end
	else
		task.spawn(StaffService.RemoveBan, userId, "Expired")
	end
end

-- =====================================================================
-- ROLLEN SETZEN & TEAM-LISTE (Admin-Aktionen SetRole / StaffList)
-- =====================================================================
local function findOnlineByName(name: string): Player?
	local lower = string.lower(name)
	for _, p in ipairs(Players:GetPlayers()) do
		if string.lower(p.Name) == lower then
			return p
		end
	end
	return nil
end

-- Ziel einer Rollen-Änderung: online zuerst, sonst UserId, sonst Name. (UserId?, Name, online?, Fehlertext?). Yieldet.
local function resolveRoleTarget(actor: Player, args: Plain): (number?, string, Player?, string?)
	local userId: any = args.UserId
	local name: any = args.Name
	local target = args.Target
	if type(target) == "string" and target ~= "" then
		if #target > 60 then
			return nil, "", nil, L(actor, "core.invalid")
		end
		if Staff.IsMass(target) or string.find(target, ",", 1, true) then
			return nil, "", nil, L(actor, "admin.oneTarget")
		end
		local list, key, arg = Staff.MatchTargets(target, Players:GetPlayers(), actor)
		if #list == 1 then
			local p = list[1] :: Player
			return p.UserId, p.Name, p, nil
		elseif key == "admin.cmd.ambiguous" then
			return nil, "", nil, targetError(actor, key, arg)
		end
		-- nicht hier: als UserId oder Name weiter
		if string.match(target, "^%d+$") then
			userId = tonumber(target)
		else
			name = target
		end
	end
	if userId ~= nil then
		if not isInt(userId) or userId == 0 then
			return nil, "", nil, L(actor, "core.invalid")
		end
		local online = Players:GetPlayerByUserId(userId)
		if online then
			return userId, online.Name, online, nil
		end
		if userId < 0 then
			return nil, "", nil, L(actor, "admin.role.notFound", idKey(userId)) -- Studio-Testspieler nur online
		end
		local known = memberName(userId)
		if known then
			return userId, known, nil, nil
		end
		if not lookupLimiter.Check(actor) then
			return nil, "", nil, L(actor, "admin.cmd.tooFast")
		end
		local ok, found = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		return userId, if ok and type(found) == "string" then clip(found, MAX_NAME) else idKey(userId), nil, nil
	end
	if isNameText(name) then
		local online = findOnlineByName(name)
		if online then
			return online.UserId, online.Name, online, nil
		end
		if not lookupLimiter.Check(actor) then
			return nil, "", nil, L(actor, "admin.cmd.tooFast")
		end
		local ok, found = pcall(function()
			return Players:GetUserIdFromNameAsync(name)
		end)
		if ok and isInt(found) and found > 0 then
			return found, name, nil, nil
		end
		return nil, "", nil, L(actor, "admin.role.notFound", name)
	end
	return nil, "", nil, L(actor, "admin.role.notFound", tostring(target or name or "?"))
end

local function roleError(actor: Player, key: string, targetName: string, newRole: string?): string
	if key == "admin.role.cantGrant" then
		return L(actor, key, roleLabel(actor, newRole or "None"))
	elseif key == "admin.role.cantRemove" then
		return L(actor, key, targetName)
	elseif key == "admin.role.same" then
		return L(actor, key, targetName, roleLabel(actor, newRole or "None"))
	elseif key == "admin.role.full" then
		return L(actor, key, tonumber(STAFF.MaxMembers) or 100)
	end
	return L(actor, key)
end

-- Admin-Aktion "SetRole" (über AdminService.Run). args { Target?, UserId?, Name?, Role = "Admin" | "Moderator" | "" }
function StaffService.SetRole(actor: Player, args: any): (boolean, string, any?)
	if not isPlayer(actor) or actor.Parent ~= Players then
		return false, ""
	end
	if type(args) ~= "table" then
		return false, L(actor, "core.invalid")
	end
	local roleArg = args.Role
	if roleArg ~= "Admin" and roleArg ~= "Moderator" and roleArg ~= "" then
		return false, L(actor, "admin.role.badRole")
	end
	local newRole: string? = if roleArg == "" then nil else roleArg
	if not roleLimiter.Check(actor) then
		return false, L(actor, "admin.cmd.tooFast")
	end
	local targetId, targetName, online, err = resolveRoleTarget(actor, args)
	if targetId == nil then
		return false, err or L(actor, "admin.role.notFound", "?")
	end
	if targetId == actor.UserId then
		return false, L(actor, "admin.role.self")
	end
	local targetIsOwner = isOwnerId(targetId)
	local targetGroup, rawGroup, targetRank
	if online then
		rawGroup = groupRank[online] or 0
		targetGroup = groupRoleRank(rawGroup)
		targetRank = StaffService.Rank(online)
	else
		if not groupCached(targetId) and not lookupLimiter.Check(actor) then
			return false, L(actor, "admin.cmd.tooFast")
		end
		local group, known, raw = groupRoleAsync(targetId)
		if not known then
			return false, L(actor, "admin.cmd.rankUnknown", targetName)
		end
		targetGroup, rawGroup = group, raw
		targetRank = if targetIsOwner then OWNER_RANK else math.max(storedRank(targetId), group)
	end
	local ok, key = Staff.CanSetRole(StaffService.RoleOf(actor), targetRank, targetIsOwner, newRole, STAFF)
	if not ok then
		return false, roleError(actor, key or "admin.role.badRole", targetName, newRole)
	end
	local stored = storedRole(targetId)
	if stored == newRole then
		if newRole == nil and targetGroup > 0 then
			return false, L(actor, "admin.role.group", targetName, rawGroup)
		end
		return false, roleError(actor, "admin.role.same", targetName, newRole)
	end
	local memoryOnly = targetId <= 0 or modOff
	if not memoryOnly then
		local change = {
			ActorId = actor.UserId,
			ActorIsOwner = isOwner(actor),
			ActorGroupRank = groupRoleRank(groupRank[actor]),
			TargetId = targetId,
			TargetIsOwner = targetIsOwner,
			TargetGroupRank = targetGroup,
			Role = newRole,
			Name = targetName,
			ByName = actor.Name,
			Now = os.time(),
			Cfg = STAFF,
		}
		local abortKey: string? = nil
		local okStore, result = storeCall(function(store)
			return store:UpdateAsync(DOC_KEY, function(old)
				local fresh, keyErr = Core.ApplyRole(old, change)
				abortKey = keyErr
				return fresh
			end)
		end)
		if not okStore and modOff then
			memoryOnly = true -- Studio ohne API: ab jetzt nur im Speicher
		elseif not okStore then
			return false, L(actor, "admin.role.saveFailed")
		elseif type(result) ~= "table" then
			return false, roleError(actor, abortKey or "admin.role.saveFailed", targetName, newRole)
		else
			local fresh = Core.SanitizeDoc(result)
			if fresh.Rev >= staffDoc.Rev then
				staffDoc = fresh
			end
			docLoaded = true
			broadcast({
				Kind = "Role",
				Id = newId("R"),
				UserId = targetId,
				Role = newRole or "",
				Rev = fresh.Rev,
				By = actor.UserId,
			})
		end
	end
	if memoryOnly then
		local maxMembers = tonumber(STAFF.MaxMembers) or 100
		if newRole and localMembers[targetId] == nil and countKeys(localMembers) >= maxMembers then
			return false, roleError(actor, "admin.role.full", targetName, newRole)
		end
		localMembers[targetId] = if newRole
			then {
				Role = newRole,
				Name = clip(targetName, MAX_NAME),
				By = actor.UserId,
				ByName = clip(actor.Name, MAX_NAME),
				Since = os.time(),
			}
			else nil
	end
	if online then
		StaffService.Refresh(online)
	end
	local text = L(
		actor,
		if newRole then "admin.role.granted" else "admin.role.removed",
		targetName,
		roleLabel(actor, newRole or "None")
	)
	if memoryOnly then
		text ..= " · " .. L(actor, "admin.role.studio")
	end
	return true, text, { UserId = targetId, Role = newRole or "" }
end

-- Admin-Aktion "StaffList": gespeicherte Mitglieder + online Besitzer/Gruppen-Rollen
function StaffService.List(actor: Player): (boolean, string, any?)
	if not isPlayer(actor) or actor.Parent ~= Players then
		return false, ""
	end
	local members: { Plain } = {}
	local seen: { [number]: boolean } = {}
	local function add(userId: number, member: Member)
		if seen[userId] then
			return
		end
		seen[userId] = true
		local online = Players:GetPlayerByUserId(userId)
		table.insert(members, {
			UserId = userId,
			Name = if member.Name ~= "" then member.Name elseif online then online.Name else idKey(userId),
			Role = member.Role,
			By = member.By,
			ByName = member.ByName,
			Since = member.Since,
			Online = online ~= nil,
			Source = "Store",
		})
	end
	for userId, member in pairs(localMembers) do
		add(userId, member)
	end
	for key, member in pairs(staffDoc.Members) do
		local userId = tonumber(key)
		if userId then
			add(userId, member)
		end
	end
	local stored = #members
	for _, p in ipairs(Players:GetPlayers()) do
		local role = StaffService.RoleOf(p)
		if role and not seen[p.UserId] then
			seen[p.UserId] = true
			table.insert(members, {
				UserId = p.UserId,
				Name = p.Name,
				Role = role,
				By = 0,
				ByName = "",
				Since = 0,
				Online = true,
				Source = if role == "Owner" then "Owner" else "Group",
			})
		end
	end
	table.sort(members, function(a, b)
		local ra, rb = Staff.Rank(a.Role), Staff.Rank(b.Role)
		if ra ~= rb then
			return ra > rb
		end
		return string.lower(a.Name) < string.lower(b.Name)
	end)
	return true,
		L(actor, "admin.team.loaded", #members),
		{
			Members = members,
			Count = stored,
			Max = tonumber(STAFF.MaxMembers) or 100,
			Local = modOff or not docLoaded,
			CanAdmins = StaffService.Can(actor, "ManageAdmins"),
			CanMods = StaffService.Can(actor, "ManageMods"),
		}
end

-- =====================================================================
-- MELDUNGEN (AntiCheatService nach dem Speichern)
-- =====================================================================
function StaffService.OnReport(report: any)
	if type(report) ~= "table" then
		return
	end
	local reason = if type(report.Reason) == "string" then report.Reason else "Other"
	if not table.find(Staff.REPORT_REASONS, reason) then
		reason = "Other"
	end
	local fromName = truncate(clip(report.FromName, MAX_NAME), MAX_NAME) -- ValidateMsg: ≤ 20 Byte
	local targetName = truncate(clip(report.Name, MAX_NAME), MAX_NAME)
	if fromName == "" then
		fromName = "?"
	end
	if targetName == "" then
		targetName = "?"
	end
	notifyReport(if isInt(report.From) then report.From else nil, fromName, targetName, reason, "admin.rep.new")
	if os.clock() - reportPublishAt >= REPORT_PUBLISH_GAP then
		reportPublishAt = os.clock()
		broadcast({
			Kind = "Report",
			Id = newId("P"),
			FromName = fromName,
			TargetName = targetName,
			Reason = reason,
		})
	end
end

-- =====================================================================
-- CHAT-BEFEHLE
-- =====================================================================
-- Admin-Aktion ausführen (einziges Tor: AdminService.Run, Log mit Via = "Chat")
local function exec(p: Player, action: string, args: Plain): (boolean, string, any?)
	local ok, success, message, data = call("AdminService", "Run", p, action, args, "Chat")
	if not ok then
		return false, L(p, "admin.unavailable", "AdminService"), nil
	end
	return success == true, if type(message) == "string" then message else "", data
end

local function execSay(p: Player, action: string, args: Plain): (boolean, any?)
	local ok, message, data = exec(p, action, args)
	sayResult(p, ok, message)
	return ok, data
end

local function optional(text: string): string?
	return if text ~= "" then text else nil
end

local function sayErr(p: Player, key: string, args: { any }?)
	StaffService.SayKey(p, key, args, "Err")
end

-- Text für ein Ziel, den MatchTargets sicher wiederfindet (UserId > 0, sonst exakter Name)
local function targetText(p: Player): string
	return if p.UserId > 0 then idKey(p.UserId) else p.Name
end

-- Genau ein Spieler auf diesem Server. (Spieler?, Fehlertext?)
local function single(p: Player, text: string, noSelf: boolean): (Player?, string?)
	if Staff.IsMass(text) then
		return nil, L(p, "admin.oneTarget")
	end
	local list, key, arg = Staff.MatchTargets(text, Players:GetPlayers(), p)
	if #list == 0 then
		return nil, targetError(p, key, arg)
	elseif #list > 1 then
		return nil, L(p, "admin.oneTarget")
	end
	local target = list[1] :: Player
	if noSelf and target == p then
		return nil, L(p, "admin.notSelf")
	end
	return target, nil
end

-- "/kick all confirm": Bestätigung innerhalb ConfirmSeconds (Wort am Anfang oder Ende, wird entfernt)
local function needConfirm(p: Player, key: string, args: { string }, at: number): boolean
	local seconds = tonumber(STAFF.ConfirmSeconds) or 15
	local index: number? = nil
	if args[#args] and CONFIRM_WORDS[string.lower(args[#args])] and #args >= at then
		index = #args
	elseif args[at] and CONFIRM_WORDS[string.lower(args[at])] then
		index = at
	end
	local pending = confirm[p]
	if index and pending and pending.Key == key and os.clock() - pending.At <= seconds then
		table.remove(args, index)
		confirm[p] = nil
		return true
	end
	confirm[p] = { Key = key, At = os.clock() }
	StaffService.SayKey(p, "admin.cmd.confirm", { seconds, "/" .. key .. " confirm" }, "Warn")
	return false
end

-- Gruppe eines Befehls für /cmds: "All" (Perm "" / persönlich) oder die kleinste Rolle eines Rechts, das man hat
local function helpGroup(def: Staff.Command, role: string?): string
	if def.Perm == "" or def.Personal == true then
		return "All"
	end
	local perms = { def.Perm }
	for _, perm in ipairs(def.AnyPerm or {}) do
		table.insert(perms, perm)
	end
	local best = OWNER_RANK
	for _, perm in ipairs(perms) do
		if Staff.Can(role, perm, STAFF) then
			local min = if Staff.LOCKED_OWNER[perm] then "Owner" else STAFF.Perms[perm]
			best = math.min(best, Staff.RANK[min] or OWNER_RANK)
		end
	end
	return ROLE_BY_RANK[best]
end

local function wrapWords(words: { string }, maxBytes: number): { string }
	local out: { string } = {}
	local line = ""
	for _, word in ipairs(words) do
		if line ~= "" and #line + 1 + #word > maxBytes then
			table.insert(out, line)
			line = word
		else
			line = if line == "" then word else line .. " " .. word
		end
	end
	if line ~= "" then
		table.insert(out, line)
	end
	return out
end

Handlers.cmds = function(p, args)
	local role = StaffService.RoleOf(p)
	if args[1] then
		local name = string.gsub(args[1], "^[/;]", "")
		local def = Staff.CommandByName(name)
		if not def or not Staff.VisibleCommand(def, role, STAFF) then
			sayErr(p, "admin.cmd.unknown", { args[1] })
			return
		end
		StaffService.SayKey(
			p,
			"admin.cmd.helpOne",
			{ L(p, "admin.cmd.u." .. def.Name), L(p, "admin.cmd.h." .. def.Name) },
			"Info"
		)
		return
	end
	local buckets: { [string]: { string } } = {}
	for _, def in ipairs(Staff.COMMANDS) do
		if Staff.VisibleCommand(def, role, STAFF) then
			local group = helpGroup(def, role)
			buckets[group] = buckets[group] or {}
			table.insert(buckets[group], "/" .. def.Name)
		end
	end
	local lines: { string } = {}
	for _, group in ipairs(HELP_GROUPS) do
		local list = buckets[group]
		if list then
			local label = if group == "All" then L(p, "admin.cmd.helpEveryone") else roleLabel(p, group)
			for _, chunk in ipairs(wrapWords(list, HELP_LINE)) do
				table.insert(lines, L(p, "admin.cmd.helpGroup", label, chunk))
			end
		end
	end
	table.insert(lines, L(p, "admin.cmd.helpMore"))
	local title = L(p, "admin.cmd.helpTitle", if role then roleLabel(p, role) else L(p, "admin.cmd.helpEveryone"))
	StaffService.Say(p, title, "Info", lines)
end

Handlers.report = function(p, args, raw)
	local list, key, arg = Staff.MatchTargets(args[1], Players:GetPlayers(), p)
	if #list == 0 then
		if key == "admin.cmd.ambiguous" then
			StaffService.Say(p, targetError(p, key, arg), "Err")
		else
			sayErr(p, "admin.rep.offline", { args[1] })
		end
		return
	end
	if Staff.IsMass(args[1]) or #list > 1 then
		sayErr(p, "admin.oneTarget")
		return
	end
	local target = list[1] :: Player
	if target == p then
		sayErr(p, "admin.notSelf")
		return
	end
	local reason = Staff.ReasonFromText(args[2])
	local note = optional(Core.Tail(raw, 2))
	local ok, reply = call("AntiCheatService", "SubmitReport", p, target.UserId, reason, note, "Chat")
	if not ok or type(reply) ~= "table" then
		sayErr(p, "admin.unavailable", { "AntiCheatService" })
		return
	end
	sayResult(p, reply.Ok == true, reply.Message)
end

Handlers.staff = function(p)
	local list: { { P: Player, Role: string } } = {}
	for _, other in ipairs(Players:GetPlayers()) do
		local role = StaffService.RoleOf(other)
		if role then
			table.insert(list, { P = other, Role = role })
		end
	end
	table.sort(list, function(a, b)
		local ra, rb = Staff.Rank(a.Role), Staff.Rank(b.Role)
		if ra ~= rb then
			return ra > rb
		end
		return string.lower(a.P.DisplayName) < string.lower(b.P.DisplayName)
	end)
	local lines: { string } = {}
	for i, entry in ipairs(list) do
		if i >= MAX_SAY_LINES then
			table.insert(lines, ("+%d"):format(#list - i + 1))
			break
		end
		table.insert(lines, L(p, "admin.cmd.staffLine", L(p, "admin.tag." .. entry.Role), entry.P.DisplayName))
	end
	if StaffService.Can(p, "TeamView") then
		local total = countKeys(staffDoc.Members) + countKeys(localMembers)
		table.insert(lines, L(p, "admin.cmd.staffTotal", total))
	end
	local title = if #list > 0 then L(p, "admin.cmd.staffTitle", #list) else L(p, "admin.cmd.staffNone")
	StaffService.Say(p, title, "Info", lines)
end

Handlers.mute = function(p, args, raw)
	local seconds = Staff.ParseDuration(args[2])
	local reason = optional(Core.Tail(raw, if seconds ~= nil then 3 else 2))
	if StaffService.Can(p, "Mute") then
		execSay(p, "Mute", { Target = args[1], Seconds = seconds, Reason = reason })
		return
	end
	-- ohne Recht: nur für mich stumm (nie geloggt)
	local target, err = single(p, args[1], true)
	if not target then
		StaffService.Say(p, err or "", "Err")
		return
	end
	local list = personal[p.UserId]
	if not list then
		list = {}
		personal[p.UserId] = list
	end
	if not list[target.UserId] and countKeys(list) >= PERSONAL_MAX then
		local oldest = next(list)
		if oldest ~= nil then
			list[oldest] = nil
		end
	end
	list[target.UserId] = true
	StaffService.SayKey(p, "admin.cmd.personalMute", { target.DisplayName }, "Ok")
end

Handlers.unmute = function(p, args)
	if StaffService.Can(p, "Mute") then
		execSay(p, "Unmute", { Target = args[1] })
		return
	end
	local target, err = single(p, args[1], true)
	if not target then
		StaffService.Say(p, err or "", "Err")
		return
	end
	local list = personal[p.UserId]
	if list then
		list[target.UserId] = nil
	end
	StaffService.SayKey(p, "admin.cmd.personalUnmute", { target.DisplayName }, "Ok")
end

Handlers.kick = function(p, args, raw)
	local who = args[1]
	if Staff.IsMass(who) then
		if not StaffService.Can(p, "KickAll") then
			sayErr(p, "admin.cmd.mass")
			return
		end
		if not needConfirm(p, "kick " .. string.lower(who), args, 2) then
			return
		end
		execSay(p, "KickAll", { Reason = optional(table.concat(args, " ", 2)) })
		return
	end
	execSay(p, "Kick", { Target = who, Reason = optional(Core.Tail(raw, 2)) })
end

Handlers.ban = function(p, args, raw)
	local who = args[1]
	if Staff.IsMass(who) then
		sayErr(p, "admin.cmd.massBan")
		return
	end
	local seconds = Staff.ParseDuration(args[2])
	local reasonFrom = 3
	if seconds == nil then
		-- ohne Dauer: Standard, auf das Rollen-Maximum gekürzt (zu lange Angaben lehnt AdminService ab)
		reasonFrom = 2
		seconds = Staff.ParseDuration(STAFF.DefaultBan) or 86400
		local role = StaffService.RoleOf(p)
		local max = if role and STAFF.TempBanMax then STAFF.TempBanMax[role] else nil
		if Util.IsFinite(max) and max ~= -1 and (seconds == -1 or (seconds :: number) > max) then
			seconds = max
		end
	end
	local payload: Plain = { Seconds = seconds, Reason = optional(Core.Tail(raw, reasonFrom)) }
	local list, key, arg = Staff.MatchTargets(who, Players:GetPlayers(), p)
	if #list > 0 then
		payload.Target = who
	elseif key == "admin.cmd.ambiguous" then
		StaffService.Say(p, targetError(p, key, arg), "Err")
		return
	elseif not StaffService.Can(p, "Ban") then
		sayErr(p, "admin.ban2.onlineOnly")
		return
	elseif string.match(who, "^%d+$") then
		payload.UserId = tonumber(who)
	elseif isNameText(who) then
		payload.Name = who
	else
		StaffService.Say(p, targetError(p, key, arg), "Err")
		return
	end
	execSay(p, "Ban", payload)
end

Handlers.unban = function(p, args, raw)
	local who = args[1]
	local payload: Plain = { Reason = optional(Core.Tail(raw, 2)) }
	if string.match(who, "^%d+$") then
		payload.UserId = tonumber(who)
	else
		payload.Name = who -- Auflösung (auch offline) im Server-Handler
	end
	execSay(p, "Unban", payload)
end

Handlers.warn = function(p, args, raw)
	execSay(p, "Warn", { Target = args[1], Text = Core.Tail(raw, 2) })
end

Handlers.tp = function(p, args)
	if args[2] then
		execSay(p, "TpTo", { Target = args[1], To = args[2] })
	else
		execSay(p, "Goto", { Target = args[1] })
	end
end

Handlers.bring = function(p, args)
	execSay(p, "Bring", { Target = args[1] })
end

Handlers.freeze = function(p, args)
	execSay(p, "Freeze", { Target = args[1], On = true })
end

Handlers.unfreeze = function(p, args)
	execSay(p, "Freeze", { Target = args[1], On = false })
end

Handlers.spectate = function(p, args)
	local target, err = single(p, args[1], true)
	if not target then
		StaffService.Say(p, err or "", "Err")
		return
	end
	local ok = execSay(p, "Spectate", { Target = targetText(target), On = true })
	if ok then
		call("PlayerStateService", "Effect", p, "StaffDo", 0, { Do = "Spectate", UserId = target.UserId })
	end
end

Handlers.unspectate = function(p)
	execSay(p, "Spectate", { On = false })
	call("PlayerStateService", "Effect", p, "StaffDo", 0, { Do = "Unspectate" })
end

Handlers.respawn = function(p, args)
	execSay(p, "Respawn", { Target = args[1] })
end

Handlers.logs = function(p, args)
	local count = LOGS_DEFAULT
	if args[1] then
		local n = tonumber(args[1])
		if not isInt(n) or (n :: number) < 1 then
			sayErr(p, "admin.cmd.badNumber", { args[1] })
			return
		end
		count = math.min(n :: number, LOGS_MAX)
	end
	local ok, message, data = exec(p, "AdminLog", {})
	if not ok or type(data) ~= "table" then
		sayResult(p, false, if message ~= "" then message else L(p, "core.error"))
		return
	end
	local lines: { string } = {}
	for i = 1, math.min(count, #data) do
		local e = data[i]
		if type(e) == "table" then
			local stamp = os.date("!%H:%M", math.floor(tonumber(e.T) or 0)) :: string
			local mark = if e.Ok == true then "✔" else "✖"
			table.insert(
				lines,
				L(
					p,
					"admin.cmd.logLine",
					stamp,
					clip(e.Name, 40),
					clip(e.Action, 40),
					mark .. " " .. clip(e.Msg, LOG_MSG_CHARS)
				)
			)
		end
	end
	StaffService.Say(p, L(p, "admin.cmd.logsTitle", #lines), "Info", lines)
end

Handlers.fly = function(p)
	local ok, message = exec(p, "SetPower", { Name = "CanFly", Value = true })
	if not ok then
		sayResult(p, false, message)
		return
	end
	call("PlayerStateService", "Effect", p, "StaffDo", 0, { Do = "Fly" })
	StaffService.SayKey(p, "admin.cmd.fly", nil, "Ok")
end

Handlers.noclip = function(p)
	local value = p:GetAttribute("AdminNoclip") ~= true
	local ok, message = exec(p, "SetPower", { Name = "AdminNoclip", Value = value })
	if not ok then
		sayResult(p, false, message)
		return
	end
	StaffService.SayKey(p, "admin.cmd.noclip", { L(p, if value then "admin.on" else "admin.off") }, "Ok")
end

-- /speed und /jump: <Spieler> <Wert|reset> [Sekunden]
local function giftHandler(field: string): Handler
	return function(p, args)
		local word = string.lower(args[2])
		if RESET_WORDS[word] then
			execSay(p, "GiveSpeed", { Target = args[1], Reset = true })
			return
		end
		local value = tonumber((string.gsub(args[2], ",", ".")))
		if not Util.IsFinite(value) then
			sayErr(p, "admin.cmd.badNumber", { args[2] })
			return
		end
		local seconds: number? = nil
		if args[3] then
			seconds = Staff.ParseDuration(args[3], 1)
			if seconds == nil then
				sayErr(p, "admin.cmd.badDuration")
				return
			end
			if seconds == -1 then
				seconds = 0 -- dauerhaft = bis zum Zurücksetzen
			end
		end
		local payload: Plain = { Target = args[1], Seconds = seconds }
		payload[field] = value
		execSay(p, "GiveSpeed", payload)
	end
end
Handlers.speed = giftHandler("Speed")
Handlers.jump = giftHandler("Jump")

Handlers.money = function(p, args)
	local amount = Staff.ParseAmount(args[2])
	if amount == nil or amount == 0 then
		sayErr(p, "admin.cmd.badAmount")
		return
	end
	execSay(p, "Give", { Target = args[1], Grant = { Credits = amount } })
end

Handlers.aky = function(p, args)
	local amount = Staff.ParseAmount(args[2])
	if amount == nil or amount == 0 then
		sayErr(p, "admin.cmd.badAmount")
		return
	end
	execSay(p, "GiveAky", { Target = args[1], Aky = amount })
end

Handlers.announce = function(p, args, raw)
	local global = GLOBAL_WORDS[string.lower(args[1])] == true
	local text = Core.Tail(raw, if global then 2 else 1)
	if text == "" then
		StaffService.SayKey(p, "admin.cmd.usage", { L(p, "admin.cmd.u.announce") }, "Info")
		return
	end
	execSay(p, "Announce", { Text = text, Global = global })
end

-- Recht, das ein /event-Eintrag braucht (nur für die Liste; der Server prüft beim Start selbst)
local function eventPerm(spec: Staff.EventSpec): { string }
	local kind = spec.Kind
	if spec.Type == "Market" then
		return { "MarketEvents" }
	elseif spec.Type == "World" then
		return { kind and STAFF.EventPerms[kind] or "WorldEvents" }
	elseif spec.Type == "Abuse" then
		return { kind and STAFF.EventPerms[kind] or "EconomyEvents" }
	end
	return { "FunEvents", "EconomyEvents", "WorldEvents" }
end

local function instrumentId(token: string?): number?
	if type(token) ~= "string" then
		return nil
	end
	local n = tonumber(token)
	if isInt(n) then
		return n
	end
	local upper = string.upper(token)
	for _, inst in ipairs(Config.Companies.Instruments) do
		if inst.Ticker == upper then
			return inst.Id
		end
	end
	return nil
end

Handlers.event = function(p, args)
	local role = StaffService.RoleOf(p)
	if not args[1] then
		local names: { string } = {}
		for _, name in ipairs(Staff.EventNames()) do
			local spec = Staff.EventSpec(name)
			if spec and Staff.CanAny(role, eventPerm(spec), STAFF) then
				table.insert(names, name)
			end
		end
		StaffService.SayKey(p, "admin.cmd.eventList", { table.concat(names, ", ") }, "Info")
		return
	end
	local spec = Staff.EventSpec(args[1])
	if not spec then
		sayErr(p, "admin.cmd.eventUnknown", { args[1] })
		return
	end
	local rest: { string } = {}
	local global = false
	for i = 2, #args do
		if GLOBAL_WORDS[string.lower(args[i])] then
			global = true
		else
			table.insert(rest, args[i])
		end
	end
	if spec.Type == "Abuse" then
		execSay(p, "Abuse", { Event = spec.Kind, Args = table.clone(spec.Args or {}), Global = global })
	elseif spec.Type == "World" then
		execSay(p, "WorldEvent", { Event = spec.Kind })
	elseif spec.Type == "Market" then
		local eventArgs: Plain = { Scope = "All" }
		local index = 1
		if spec.Inst then
			local id = instrumentId(rest[1])
			if not id then
				StaffService.SayKey(p, "admin.cmd.usage", { "/event " .. string.lower(args[1]) .. " <Ticker> [%]" }, "Info")
				return
			end
			eventArgs.Target = id
			eventArgs.Scope = "Inst"
			index = 2
		end
		if spec.Num and rest[index] then
			local n = tonumber((string.gsub(rest[index], "[%%,]", function(c)
				return if c == "," then "." else ""
			end)))
			if not Util.IsFinite(n) then
				sayErr(p, "admin.cmd.badNumber", { rest[index] })
				return
			end
			eventArgs[spec.Num] = n
		end
		execSay(p, "Abuse", { Event = spec.Kind, Args = eventArgs })
	else
		local stop = Staff.EventSpec(rest[1])
		local kind = stop and stop.Kind
		if not kind then
			sayErr(p, "admin.cmd.eventUnknown", { rest[1] or "?" })
			return
		end
		execSay(p, "AbuseStop", { Event = if kind == "BuildBoom" then "AdminBuildBoom" else kind })
	end
end

-- /mod, /admin, /unrank: online genau ein Treffer -> Target, sonst Ziffern -> UserId, sonst Name
local function roleHandler(role: string): Handler
	return function(p, args)
		local who = args[1]
		if Staff.IsMass(who) or string.find(who, ",", 1, true) then
			sayErr(p, "admin.oneTarget")
			return
		end
		local payload: Plain = { Role = role }
		local list, key, arg = Staff.MatchTargets(who, Players:GetPlayers(), p)
		if #list == 1 then
			payload.Target = who
		elseif key == "admin.cmd.ambiguous" then
			StaffService.Say(p, targetError(p, key, arg), "Err")
			return
		elseif string.match(who, "^%d+$") then
			payload.UserId = tonumber(who)
		elseif isNameText(who) then
			payload.Name = who
		else
			sayErr(p, "admin.role.notFound", { who })
			return
		end
		execSay(p, "SetRole", payload)
	end
end
Handlers.mod = roleHandler("Moderator")
Handlers.admin = roleHandler("Admin")
Handlers.unrank = roleHandler("")

Handlers.lock = function(p)
	execSay(p, "LockServer", { On = true })
end

Handlers.unlock = function(p)
	execSay(p, "LockServer", { On = false })
end

Handlers.shutdown = function(p, args)
	if not needConfirm(p, "shutdown", args, 1) then
		return
	end
	execSay(p, "Shutdown", { Confirm = true, Reason = optional(table.concat(args, " ")) })
end

-- Befehl parsen und ausführen. via = "Slash" (TextChatCommand) | "Semicolon" (Player.Chatted) | "Request"
function StaffService.Run(p: Player, raw: string, via: string)
	if not isPlayer(p) or p.Parent ~= Players or type(raw) ~= "string" then
		return
	end
	local def, args, prefix, name = Staff.ParseCommand(raw)
	if not def then
		if prefix == "/" and via == "Slash" then
			sayErr(p, "admin.cmd.unknown", { name or "?" })
		end
		return -- ";xyz" ist normaler Chat (wurde zugestellt)
	end
	local text = trim(string.sub(raw, 1, MAX_COMMAND))
	-- Doppel-Pfad-Dedupe (Player.Chatted + Request): gleicher Text innerhalb 1,5 s -> ignorieren
	local last = lastCmd[p]
	if last and last.Text == text and os.clock() - last.At < DUP_SECONDS then
		return
	end
	lastCmd[p] = { Text = text, At = os.clock() }
	if not cmdLimiter.Check(p) then
		sayErr(p, "admin.cmd.tooFast")
		return
	end
	local role = StaffService.RoleOf(p)
	if not Staff.VisibleCommand(def, role, STAFF) then
		if os.clock() - (deniedAt[p] or -math.huge) > DENIED_GAP then
			deniedAt[p] = os.clock()
			sayErr(p, "admin.cmd.denied")
		end
		return
	end
	if #args < (def.MinArgs or 0) then
		StaffService.SayKey(p, "admin.cmd.usage", { L(p, "admin.cmd.u." .. def.Name) }, "Info")
		return
	end
	local handler = Handlers[def.Name]
	if not handler then
		return
	end
	local ok, err = pcall(handler, p, args, text)
	if not ok then
		warn("[Staff] /" .. def.Name .. ": " .. tostring(err))
		sayErr(p, "admin.cmd.failed", { L(p, "core.error") })
	end
end

-- =====================================================================
-- TEXTCHATSERVICE (Befehle, Zustellung, Standard-/mute aus)
-- =====================================================================
-- ShouldDeliverCallback: läuft je Empfänger, darf NIE yielden oder werfen
local function deliver(message: TextChatMessage, recipient: TextSource): boolean
	local ok, result = pcall(function()
		local source = message.TextSource
		return Staff.ShouldDeliver({
			Text = message.Text,
			SenderId = if source then source.UserId else nil,
			RecipientId = recipient.UserId,
			MutedUntil = mutedUntil,
			Personal = personal,
			Now = os.time(),
		})
	end)
	return not ok or result ~= false
end

local function setupChat()
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		warn("[Staff] TextChatService aus – nur ;-Befehle über Player.Chatted")
		legacyChat = true
		return
	end
	-- 1) Roblox-Standard /mute und /unmute abschalten (wir ersetzen sie inkl. persönlichem Stummschalten)
	local defaults = TextChatService:FindFirstChild("TextChatCommands")
		or TextChatService:WaitForChild("TextChatCommands", 10)
	local function disableDefault(child: Instance)
		if child:IsA("TextChatCommand") and (child.Name == "RBXMuteCommand" or child.Name == "RBXUnmuteCommand") then
			pcall(function()
				child.Enabled = false
			end)
		end
	end
	if defaults then
		for _, child in ipairs(defaults:GetChildren()) do
			disableDefault(child)
		end
		defaults.ChildAdded:Connect(disableDefault)
	end
	-- 2) Eigene Befehle (Ordner "AT_StaffCommands" direkt unter TextChatService)
	local folder = TextChatService:FindFirstChild("AT_StaffCommands") or Instance.new("Folder")
	folder.Name = "AT_StaffCommands"
	folder.Parent = TextChatService
	for _, def in ipairs(Staff.COMMANDS) do
		local found = folder:FindFirstChild("AT_Cmd_" .. def.Name)
		local cmd: TextChatCommand = if found and found:IsA("TextChatCommand")
			then found :: any
			else Instance.new("TextChatCommand")
		cmd.Name = "AT_Cmd_" .. def.Name
		cmd.PrimaryAlias = "/" .. def.Name
		cmd.SecondaryAlias = if def.Alias then "/" .. def.Alias else ""
		cmd.AutocompleteVisible = true -- ChatTools blendet nicht erlaubte Befehle lokal aus
		cmd:SetAttribute("Perm", def.Perm) -- "" = alle
		cmd:SetAttribute("Personal", def.Personal == true)
		cmd.Parent = folder
		cmd.Triggered:Connect(function(source: TextSource, text: string)
			local p = if source then Players:GetPlayerByUserId(source.UserId) else nil
			if p then
				task.spawn(StaffService.Run, p, text, "Slash")
			end
		end)
	end
	-- 3) Zustellung: Stumm-Rückfall, persönliches Stumm, ;-Befehle nie an andere
	local channels = TextChatService:FindFirstChild("TextChannels") or TextChatService:WaitForChild("TextChannels", 10)
	local function install(channel: Instance)
		if channel:IsA("TextChannel") then
			channel.ShouldDeliverCallback = deliver
		end
	end
	if channels then
		for _, channel in ipairs(channels:GetChildren()) do
			install(channel)
		end
		channels.ChildAdded:Connect(install)
		channels.DescendantAdded:Connect(function(d)
			-- neue TextSource eines Stummen (z. B. Flüster-Kanal)
			if d:IsA("TextSource") and isMutedId(d.UserId) then
				pcall(function()
					d.CanSend = false
				end)
			end
		end)
	end
end

local function subscribe()
	local ok, err = pcall(function()
		MessagingService:SubscribeAsync(Config.Tech.StaffTopic, function(packet)
			local okMsg, errMsg = pcall(handleMessage, if type(packet) == "table" then packet.Data else nil)
			if not okMsg then
				warn("[Staff] Nachricht: " .. tostring(errMsg))
			end
		end)
	end)
	if not ok then
		warn("[Staff] SubscribeAsync fehlgeschlagen (Team-Sync nur über den 2-min-Abgleich): " .. tostring(err))
	end
end

-- =====================================================================
-- SPIELER
-- =====================================================================
local function loadGroupRank(p: Player)
	local ok, rank = pcall(function()
		return p:GetRankInGroup(STAFF.Group.Id)
	end)
	if ok and Util.IsFinite(rank) then
		groupRank[p] = rank
	end
	groupLoaded[p] = true
end

local function onStaffCommandRequest(p: Player, arg: any): Types.Reply
	local text = Core.CommandArg(arg)
	if not text then
		return { Ok = false, Message = L(p, "core.invalid") }
	end
	task.spawn(StaffService.Run, p, text, "Request")
	return { Ok = true } -- keine Message -> kein Toast; Rückmeldung kommt über ChatSystem
end

local function onPlayer(p: Player)
	if joinedAt[p] then
		return
	end
	joinedAt[p] = os.clock()
	StaffService.Refresh(p) -- Besitzer sofort (AdminService.IsAdmin yieldet nie)
	task.spawn(function()
		enforceOwnBan(p) -- yieldet (GetAsync); kickt bei aktiver Sperre
		if p.Parent ~= Players then
			return
		end
		if groupEnabled() then
			loadGroupRank(p)
		else
			groupLoaded[p] = true
		end
		StaffService.WaitReady(5)
		if p.Parent == Players then
			StaffService.Refresh(p)
		end
	end)
	p.Chatted:Connect(function(message)
		if type(message) == "string" and string.sub(message, 1, 1) == ";" then
			task.spawn(StaffService.Run, p, message, "Semicolon")
		end
	end)
	-- Mikrofon kommt später (Sprachchat): Stumme sofort mit stummschalten
	p.ChildAdded:Connect(function(child)
		if STAFF.MuteVoice == true and isMutedId(p.UserId) then
			muteVoiceDevice(child)
		end
	end)
end

local function onPlayerRemoving(p: Player)
	if mutedUntil[p.UserId] ~= nil then
		setCanSend(p.UserId, true)
		mutedUntil[p.UserId] = nil
	end
	personal[p.UserId] = nil
	groupRank[p] = nil
	groupLoaded[p] = nil
	roleCache[p] = nil
	testRole[p] = nil
	joinedAt[p] = nil
	lastCmd[p] = nil
	deniedAt[p] = nil
	notifyAt[p] = nil
	confirm[p] = nil
	cmdLimiter.Clear(p)
	roleLimiter.Clear(p)
	lookupLimiter.Clear(p)
end

-- =====================================================================
-- INIT / START
-- =====================================================================
function StaffService.Init(services: any)
	Services = services
	local admin = service("AdminService")
	local core = if type(admin) == "table" then admin.Core else nil
	if type(core) == "table" and type(core.NewDedupe) == "function" then
		dedupe = core.NewDedupe(200)
	end
	-- Request "StaffCommand" (Client-Rückfall für ;-Befehle), 6 pro 10 s – Registrierung in Init (§C3 Phase 2)
	local pss = services and services.PlayerStateService
	if pss and type(pss.Handle) == "function" then
		pss.Handle(
			"StaffCommand",
			onStaffCommandRequest,
			{ Rate = cmdRate[1] or 6, Per = cmdRate[2] or 10, NeedsReady = false }
		)
	else
		warn("[Staff] Request 'StaffCommand' konnte nicht registriert werden (PlayerStateService fehlt)")
	end
end

function StaffService.Start()
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	call("DataService", "OnProfileLoaded", function(p: Player, data: any)
		applyStoredMute(p, data)
	end)
	task.spawn(function()
		loadDoc()
		importIndexOnce()
	end)
	Scheduler.Every("StaffDoc", 1 / math.max(10, tonumber(STAFF.DocRefreshSeconds) or 120), reloadDocJob)
	Scheduler.Every("StaffMutes", 1, expireMutes)
	task.spawn(setupChat)
	task.spawn(subscribe)
end

-- nur für StaffTests (TextChatService aus?)
function StaffService.LegacyChat(): boolean
	return legacyChat
end

return StaffService
