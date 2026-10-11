-- =====================================================================
--  CLUTCH CLASH – Admin-Panel, Server-Seite (Server/Services/AdminService)
--  Besitzer: WP7 (Sicherheit, Admin, Live-Balance). Vertrag: DESIGN.md B25 (komplett), C5.7, C12.2, C14,
--  docs/ADMIN-WUENSCHE.md. MH-Rahmen (REUSE §5/§6).
--
--  NUR DER BESITZER IST ADMIN (B25.1, exakt):
--    Live:   game.CreatorType == User and player.UserId == game.CreatorId and game.CreatorId ~= 0
--    Studio: RunService:IsStudio() and Config.Admin.StudioIsAdmin and (UserId > 0 or UserId == -1)
--            -> Player2 (-2) ist NIE Admin (Ablehnungspfad testbar). Keine AdminUserIds, kein Kauf, keine Gruppen.
--  Ergebnis gecacht -> Attribute IsAdmin (+ CanFly). JEDE Aktion wird hier erneut geprüft:
--  Rate-Limit 12/s VOR der Admin-Prüfung, Ablehnung nur einmal pro Spieler im Log.
--
--  Admin-RemoteFunction "Admin": (action, args) -> { Ok, Message, Data }  (alle Aktionen B25.3, 9 Reiter)
--  Fairness (B25.2): Kraft oder Admin-Waffe im Match -> MatchService.Taint(id); Attribut "TaintedMatch" am Admin
--  (rotes "TAINTED / Admin-Show"-Schild im HUD, AdminTools/MatchUI lesen es).
--  Ansagen (MH-Stil): gefiltert (PublicChat -> GetNonChatStringForBroadcastAsync, Filter-Fehler = abgelehnt),
--  lokal oder global über MessagingService "CC_Global" (Fehler -> lokal). Admin-Abuse synchron:
--  Until = workspace:GetServerTimeNow() + Sekunden. Empfänger prüft jedes Feld.
--
--  Öffentliche API (C5.7):
--    AdminService.IsAdmin(p): boolean
--    AdminService.Power(p, name): any          nil, wenn kein Admin oder Attribut nicht gesetzt
--    AdminService.EventMult(kind): number      "Xp" | "Coins" – Admin-Abuse-Event, sonst 1
--    AdminService.IsServerLocked(): boolean
-- =====================================================================

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
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
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local AdminService = {}
local Services: any = nil

local SEC: any = Config.Security
local DEFAULT_GRAVITY = 196.2
local MAX_NAME = 40
local MAX_REASON = 200
local MAX_LIST = 100
local GRAVITY_FORCE = "CC_LobbyGravity"
local GRAVITY_ATTACH = "CC_LobbyGravityAtt"
local ADMIN_WEAPON_MIN, ADMIN_WEAPON_MAX = 101, 104

-- Kräfte (B25.3): "bool" = an/aus, sonst { Min, Max } aus Config.Security.Powers
local POWERS: { [string]: string } = {
	AdminAimbot = "bool",
	AdminSilentAim = "bool",
	AdminTriggerbot = "bool",
	AdminESP = "bool",
	CanFly = "bool",
	AdminNoclip = "bool",
	AdminSpeed = "Speed",
	AdminJump = "Jump",
	AdminGod = "bool",
	AdminInvisible = "bool",
	AdminInfAmmo = "bool",
	AdminNoReload = "bool",
	AdminRapidFire = "RapidFire",
	AdminOneShot = "bool",
}
-- Kräfte, die ein Match "tainten" (B25.2). CanFly ist Standard für Admins -> zählt erst beim Losfliegen.
local TAINT_POWERS: { string } = {
	"AdminAimbot",
	"AdminSilentAim",
	"AdminTriggerbot",
	"AdminESP",
	"AdminGod",
	"AdminOneShot",
	"AdminRapidFire",
	"AdminInfAmmo",
	"AdminNoReload",
	"AdminSpeed",
	"AdminJump",
	"AdminNoclip",
	"AdminInvisible",
}
-- Aktionen, die nicht ins Output geloggt werden (Abfragen, F8-Anzeige pollt jede Sekunde)
local QUIET: { [string]: boolean } = {
	GetPlayers = true,
	ServerInfo = true,
	Matches = true,
	GetBalance = true,
	GetStats = true,
	Flags = true,
	Reports = true,
	BanList = true,
	PlayerData = true,
	Receipts = true,
}

type Action = (admin: Player, args: { [string]: any }) -> (boolean, string, any?)
type EventState = { Until: number, Coins2: boolean, Xp2: boolean }

-- ---------------------------------------------------------------------
-- ZUSTAND (Pro-Spieler-Tabellen werden bei PlayerRemoving geleert)
-- ---------------------------------------------------------------------
local rate = SEC.Rates and SEC.Rates.Admin or { 12, 1 }
local limiter = Util.RateLimiter(rate[1] or 12, rate[2] or 1)
local adminCache: { [Player]: boolean } = {}
local warnedDenied: { [Player]: boolean } = {}
local joinedAt: { [Player]: number } = {}
local taintedFor: { [Player]: number } = {}
local frozenLobby: { [Player]: boolean } = {}
local invisConn: { [Player]: RBXScriptConnection } = {}

local serverLocked = false
local startedAt = os.clock()
local event: EventState? = nil
local lobbyGravity = DEFAULT_GRAVITY
local lobbyMood: string? = nil
local mutatorUntil: number? = nil -- os.time() – globaler Mutator-Override läuft ab

local Actions: { [string]: Action } = {}

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
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

local function num(value: any, default: number, min: number, max: number): number
	local n = tonumber(value)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return default
	end
	return math.clamp(n, min, max)
end

local function textLength(text: string): number?
	return utf8.len(text)
end

-- Auf höchstens maxBytes kürzen, ohne ein UTF-8-Zeichen zu zerschneiden (Roblox-Grenzen zählen Bytes)
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

-- Freitext säubern: String, getrimmt, 1..max Zeichen (UTF-8), sonst nil
local function cleanText(value: any, max: number): string?
	if type(value) ~= "string" then
		return nil
	end
	local text = string.gsub(value, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	local len = textLength(text)
	if not len or len < 1 or len > max then
		return nil
	end
	return text
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

local function combatantOf(p: Player): any
	local ok, c = call("CombatService", "OfPlayer", p)
	return if ok and type(c) == "table" then c else nil
end

local function matchOf(p: Player): number?
	local ok, id = call("MatchService", "MatchOf", p)
	return if ok and Util.IsFinite(id) then id else nil
end

local function effect(p: Player, name: string, strength: number, data: any?)
	if not call("PlayerStateService", "Effect", p, name, strength, data) then
		Remotes.Effect:FireClient(p, name, strength, data)
	end
end

local function effectAll(name: string, strength: number, data: any?, filter: ((Player) -> boolean)?)
	if has("PlayerStateService", "EffectAll") then
		call("PlayerStateService", "EffectAll", name, strength, data, filter)
		return
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if filter == nil or filter(p) then
			Remotes.Effect:FireClient(p, name, strength, data)
		end
	end
end

local function notifyAll(key: string, args: { any }?, kind: Types.NotifyKind?)
	if has("PlayerStateService", "NotifyAll") then
		call("PlayerStateService", "NotifyAll", key, args, kind)
		return
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local text = Lang.T(langOf(p), key, table.unpack(args or {}))
		Remotes.Notify:FireClient(p, text, kind or "Event")
	end
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

local function isOwnerId(userId: number): boolean
	return game.CreatorType == Enum.CreatorType.User and game.CreatorId ~= 0 and userId == game.CreatorId
end

-- ---------------------------------------------------------------------
-- BESITZER-PRÜFUNG (B25.1)
-- ---------------------------------------------------------------------
local function computeAdmin(p: Player): boolean
	local cfg: any = Config.Admin or {}
	if cfg.OwnerIsAdmin ~= false and isOwnerId(p.UserId) then
		return true
	end
	if RunService:IsStudio() and cfg.StudioIsAdmin == true then
		if p.UserId > 0 or p.UserId == -1 then
			return true
		end
		-- Optional alle Studio-Testspieler – Player2 (-2) bleibt trotzdem IMMER normaler Spieler
		return cfg.StudioAllPlayersAdmin == true and p.UserId ~= -2
	end
	return false
end

function AdminService.IsAdmin(p: Player): boolean
	if typeof(p) ~= "Instance" or not p:IsA("Player") then
		return false
	end
	local cached = adminCache[p]
	if cached == nil then
		cached = computeAdmin(p)
		if p.Parent then
			adminCache[p] = cached
		end
	end
	return cached
end

function AdminService.Power(p: Player, name: string): any
	if type(name) ~= "string" or not AdminService.IsAdmin(p) then
		return nil
	end
	return p:GetAttribute(name)
end

function AdminService.EventMult(kind: "Xp" | "Coins"): number
	local e = event
	if not e or workspace:GetServerTimeNow() >= e.Until then
		return 1
	end
	if kind == "Xp" and e.Xp2 then
		return 2
	elseif kind == "Coins" and e.Coins2 then
		return 2
	end
	return 1
end

function AdminService.IsServerLocked(): boolean
	return serverLocked
end

-- ---------------------------------------------------------------------
-- ZIELE ("me", "all", "others", Name, Präfix, UserId)
-- ---------------------------------------------------------------------
local function resolveTargets(admin: Player, text: any): { Player }
	if type(text) == "number" then
		text = tostring(text)
	end
	if type(text) ~= "string" then
		return { admin }
	end
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	local lower = string.lower(text)
	if lower == "" or lower == "me" then
		return { admin }
	end
	if lower == "all" then
		return Players:GetPlayers()
	end
	if lower == "others" then
		local list: { Player } = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= admin then
				table.insert(list, p)
			end
		end
		return list
	end
	local userId = tonumber(text)
	if userId and userId % 1 == 0 then
		local byId = Players:GetPlayerByUserId(userId)
		if byId then
			return { byId }
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if string.lower(p.Name) == lower or string.lower(p.DisplayName) == lower then
			return { p }
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if
			string.sub(string.lower(p.Name), 1, #lower) == lower
			or string.sub(string.lower(p.DisplayName), 1, #lower) == lower
		then
			return { p }
		end
	end
	return {}
end

local function resolveOne(admin: Player, text: any): (Player?, string?)
	local list = resolveTargets(admin, text)
	if #list == 0 then
		return nil, L(admin, "admin.noTarget")
	elseif #list > 1 then
		return nil, L(admin, "admin.oneTarget")
	end
	return list[1], nil
end

-- Andere Admins/Besitzer sind vor Kick/Bann geschützt
local function protectedPlayer(p: Player): boolean
	return isOwnerId(p.UserId) or AdminService.IsAdmin(p)
end

-- ---------------------------------------------------------------------
-- TAINT (B25.2)
-- ---------------------------------------------------------------------
local function taintMatch(id: number, reason: string): boolean
	local ok = call("MatchService", "Taint", id, reason)
	return ok == true
end

-- Admin nutzt eine Kraft: ist er in einem Match -> Match tainten (einmal pro Match)
local function taintIfInMatch(admin: Player, reason: string): boolean
	local id = matchOf(admin)
	if not id then
		return false
	end
	if taintedFor[admin] ~= id then
		if taintMatch(id, reason) then
			taintedFor[admin] = id
			admin:SetAttribute("TaintedMatch", id)
		end
	end
	return true
end

-- Admin wirkt auf einen Spieler in einem Match (Poppen, Heilen, Einfrieren, Herholen) -> dieses Match tainten
local function taintTargetMatch(target: Player, reason: string)
	local id = matchOf(target)
	if id then
		taintMatch(id, reason)
	end
end

local function powerActive(p: Player, name: string): boolean
	local value = p:GetAttribute(name)
	return value ~= nil and value ~= false
end

local function holdsAdminWeapon(p: Player): boolean
	local c = combatantOf(p)
	if not c or type(c.Loadout) ~= "table" then
		return false
	end
	local def: any = Config.Weapon(c.Loadout.Primary)
	return def ~= nil and def.AdminOnly == true
end

-- 1 Hz: Kräfte/Admin-Waffen im Match -> Taint; Attribut TaintedMatch pflegen
local function monitorTaint()
	for _, p in ipairs(Players:GetPlayers()) do
		if adminCache[p] == true then
			local id = matchOf(p)
			if not id then
				if p:GetAttribute("TaintedMatch") ~= nil then
					p:SetAttribute("TaintedMatch", nil)
				end
				taintedFor[p] = nil
			elseif taintedFor[p] ~= id then
				if p:GetAttribute("TaintedMatch") ~= nil then
					p:SetAttribute("TaintedMatch", nil) -- Schild vom alten Match weg
				end
				local reason: string? = nil
				for _, name in ipairs(TAINT_POWERS) do
					if powerActive(p, name) then
						reason = name
						break
					end
				end
				if not reason and holdsAdminWeapon(p) then
					reason = "AdminWeapon"
				end
				if reason then
					taintIfInMatch(p, reason)
				else
					-- schon von anderer Stelle getaintet (z. B. WeaponService bei Admin-Waffen)?
					local okInfo, info = call("MatchService", "Info", id)
					if okInfo and type(info) == "table" and info.Tainted == true then
						taintedFor[p] = id
						p:SetAttribute("TaintedMatch", id)
					end
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- UNSICHTBAR, EINFRIEREN, TELEPORT, LOBBY-SCHWERKRAFT
-- ---------------------------------------------------------------------
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
		-- später angehängte Teile (Waffen-Modell, Namensschild) ebenfalls verstecken
		invisConn[p] = character.DescendantAdded:Connect(function(d)
			setPartInvisible(d, true)
		end)
	end
end

local function freezeLobby(p: Player, on: boolean)
	local root = rootOf(p)
	if not root then
		return
	end
	if on then
		frozenLobby[p] = true
	else
		frozenLobby[p] = nil
	end
	root.Anchored = on
	if not on then
		pcall(function()
			root:SetNetworkOwner(p)
		end)
	end
end

local function teleport(p: Player, cf: CFrame)
	if call("CharacterService", "Teleport", p, cf) then
		return
	end
	local character = p.Character
	if character then
		pcall(function()
			character:PivotTo(cf)
		end)
	end
	call("AntiCheatService", "NoteTeleport", p, cf)
end

local function updateLobbyGravity()
	local g = workspace.Gravity
	local active = lobbyGravity < g - 0.5
	for _, p in ipairs(Players:GetPlayers()) do
		local root = rootOf(p)
		if root then
			local force = root:FindFirstChild(GRAVITY_FORCE)
			local want = active and combatantOf(p) == nil
			if want then
				local attachment = root:FindFirstChild(GRAVITY_ATTACH)
				if not attachment or not attachment:IsA("Attachment") then
					local created = Instance.new("Attachment")
					created.Name = GRAVITY_ATTACH
					created.Parent = root
					attachment = created
				end
				local vf: VectorForce
				if force and force:IsA("VectorForce") then
					vf = force
				else
					vf = Instance.new("VectorForce")
					vf.Name = GRAVITY_FORCE
					vf.RelativeTo = Enum.ActuatorRelativeTo.World
					vf.ApplyAtCenterOfMass = true
					vf.Attachment0 = attachment :: Attachment
					vf.Parent = root
				end
				local wanted = Vector3.new(0, root.AssemblyMass * (g - lobbyGravity), 0)
				if (vf.Force - wanted).Magnitude > 1 then
					vf.Force = wanted
				end
			elseif force then
				force:Destroy()
				local attachment = root:FindFirstChild(GRAVITY_ATTACH)
				if attachment then
					attachment:Destroy()
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- GLOBALE NACHRICHTEN (MessagingService "CC_Global", jedes Feld wird geprüft)
-- ---------------------------------------------------------------------
local function showAnnouncement(text: string, userId: number, name: string)
	effectAll("Announce", 0, { Text = text, UserId = userId, Name = name })
end

local function boostText(coins2: boolean, xp2: boolean): string
	local parts: { string } = {}
	if coins2 then
		table.insert(parts, "2x Coins")
	end
	if xp2 then
		table.insert(parts, "2x XP")
	end
	return table.concat(parts, " + ")
end

local function startEvent(untilT: number, coins2: boolean, xp2: boolean)
	event = { Until = untilT, Coins2 = coins2, Xp2 = xp2 }
	-- Clients zeigen Banner/Toast mit Restzeit selbst (Effects "Event"); das Ende kennen sie über Until
	effectAll("Event", 1, { Kind = "AdminAbuse", Until = untilT, Coins2 = coins2, Xp2 = xp2 })
	local minutes = math.max(1, math.floor((untilT - workspace:GetServerTimeNow()) / 60 + 0.5))
	print(("[Admin] Admin-Abuse: %s für %d Minuten"):format(boostText(coins2, xp2), minutes))
end

local function mutatorValid(key: any): boolean
	local mutators = Config.Modes and Config.Modes.Mutators
	return type(key) == "string" and type(mutators) == "table" and mutators[key] ~= nil
end

local function applyMutator(key: string?, untilT: number?)
	call("MatchService", "SetMutatorOverride", key)
	mutatorUntil = if key then untilT else nil
	local okActive, active = call("MatchService", "ActiveMutator")
	effectAll("Mutator", 1, { Key = if okActive and type(active) == "string" then active else (key or "") })
end

local function handleGlobal(message: any)
	if type(message) ~= "table" then
		return
	end
	local kind = message.Kind
	if kind == "Announce" then
		local text = cleanText(message.Text, (SEC.AnnounceMax or 200) * 2)
		local name = cleanText(message.Name, MAX_NAME)
		local userId = message.UserId
		if text and name and Util.IsFinite(userId) and userId % 1 == 0 then
			showAnnouncement(text, userId, name)
		end
	elseif kind == "AdminAbuse" then
		local now = workspace:GetServerTimeNow()
		local maxSeconds = (tonumber(SEC.AdminAbuseMaxMinutes) or 60) * 60 + 30
		local untilT = message.Until
		local coins2, xp2 = message.Coins2 == true, message.Xp2 == true
		if Util.IsFinite(untilT) and untilT > now and untilT <= now + maxSeconds and (coins2 or xp2) then
			startEvent(untilT, coins2, xp2)
		end
	elseif kind == "Mutator" then
		local key = message.Key
		local untilT = message.Until
		if key == nil or key == "" then
			applyMutator(nil, nil)
		elseif mutatorValid(key) and Util.IsFinite(untilT) and untilT > os.time() then
			applyMutator(key, untilT)
		end
	end
end

-- Global senden; Fehler -> wenigstens auf diesem Server
local function publishGlobal(message: { [string]: any }): boolean
	local ok, err = pcall(function()
		MessagingService:PublishAsync(Config.Tech.MessagingTopic, message)
	end)
	if not ok then
		warn("[Admin] Global senden fehlgeschlagen: " .. tostring(err))
		handleGlobal(message)
	end
	return ok
end

-- ---------------------------------------------------------------------
-- GRANT-PRÜFUNG (Geben)
-- ---------------------------------------------------------------------
local function allWeaponKeys(): { string }
	local out: { string } = {}
	local list = Config.Weapons and Config.Weapons.List
	if type(list) == "table" then
		for _, def in ipairs(list) do
			if type(def) == "table" and type(def.Key) == "string" and not def.AdminOnly then
				table.insert(out, def.Key)
			end
		end
	end
	return out
end

local function allCosmeticIds(): { string }
	local out: { string } = {}
	local byId = Config.Cosmetics and Config.Cosmetics.ById
	if type(byId) == "table" then
		for id in pairs(byId) do
			if type(id) == "string" then
				table.insert(out, id)
			end
		end
	end
	table.sort(out)
	return out
end

local function sanitizeGrant(raw: any): Types.Grant?
	if type(raw) ~= "table" then
		return nil
	end
	local grant: { [string]: any } = {}
	for _, currency in ipairs({ "Coins", "Gems", "Keys", "Shards" }) do
		local v = raw[currency]
		if Util.IsFinite(v) and v >= 1 then
			grant[currency] = math.floor(math.min(v, 1e9))
		end
	end
	if Util.IsFinite(raw.FreeWeaponPicks) and raw.FreeWeaponPicks >= 1 then
		grant.FreeWeaponPicks = math.floor(math.min(raw.FreeWeaponPicks, 10))
	end
	if Util.IsFinite(raw.PassTiers) and raw.PassTiers >= 1 then
		grant.PassTiers = math.floor(math.min(raw.PassTiers, 100))
	end
	if Util.IsFinite(raw.XpBoostSeconds) and raw.XpBoostSeconds >= 1 then
		grant.XpBoostSeconds = math.floor(math.min(raw.XpBoostSeconds, 7 * 86400))
	end
	if raw.PassPremium == true then
		grant.PassPremium = true
	end
	if type(raw.Weapons) == "table" then
		local list: { string } = {}
		for i, key in ipairs(raw.Weapons) do
			if i > 64 then
				break
			end
			local def: any = if type(key) == "string" then Config.Weapon(key) else nil
			if def and not def.AdminOnly then
				table.insert(list, key)
			end
		end
		if #list > 0 then
			grant.Weapons = list
		end
	end
	if type(raw.Cosmetics) == "table" then
		local byId = Config.Cosmetics and Config.Cosmetics.ById or {}
		local list: { string } = {}
		for i, id in ipairs(raw.Cosmetics) do
			if i > 512 then
				break
			end
			if type(id) == "string" and byId[id] ~= nil then
				table.insert(list, id)
			end
		end
		if #list > 0 then
			grant.Cosmetics = list
		end
	end
	if next(grant) == nil then
		return nil
	end
	return grant :: any
end

local function grantTo(targets: { Player }, grant: Types.Grant, reason: string): { Player }
	local done: { Player } = {}
	for _, p in ipairs(targets) do
		local ok, result = call("ShopService", "Grant", p, grant, reason)
		if ok and result == true then
			table.insert(done, p)
		end
	end
	return done
end

-- =====================================================================
-- AKTIONEN – Reiter SPIELER
-- =====================================================================
Actions.GetPlayers = function(_admin, _args)
	local list: { { [string]: any } } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local okLevel, level = call("ProgressionService", "LevelOf", p)
		local okScore, score = call("AntiCheatService", "Score", p)
		table.insert(list, {
			UserId = p.UserId,
			Name = p.Name,
			DisplayName = p.DisplayName,
			Level = if okLevel and Util.IsFinite(level) then level else (p:GetAttribute("Level") or 1),
			PingMs = p:GetAttribute("PingMs") or 0,
			MatchId = matchOf(p) or 0,
			Suspicion = if okScore and Util.IsFinite(score) then score else 0,
			IsAdmin = AdminService.IsAdmin(p),
			Minutes = math.floor((os.clock() - (joinedAt[p] or os.clock())) / 60),
		})
	end
	return true, "OK", list
end

Actions.Kick = function(admin, args)
	local targets = resolveTargets(admin, args.Target)
	local raw = cleanText(args.Reason, MAX_REASON)
	local filtered = if raw then filterBroadcast(raw, admin.UserId) else nil
	local kicked: { Player } = {}
	for _, p in ipairs(targets) do
		if p ~= admin and not protectedPlayer(p) then
			table.insert(kicked, p)
			p:Kick(filtered or L(p, "admin.kickDefault"))
		end
	end
	if #kicked == 0 then
		return false, L(admin, if #targets > 0 then "admin.notSelf" else "admin.noTarget")
	end
	return true, L(admin, "admin.kicked", names(kicked))
end

Actions.Ban = function(admin, args)
	local presets = SEC.BanPresets or {}
	local seconds = if type(args.Duration) == "string" then presets[args.Duration] else nil
	if not Util.IsFinite(seconds) then
		return false, L(admin, "admin.banDuration")
	end
	local ids: { number } = {}
	local namesById: { [number]: string } = {}
	local onlineById: { [number]: Player } = {}
	if args.UserId ~= nil then
		local id = tonumber(args.UserId)
		if not id or id % 1 ~= 0 then
			return false, L(admin, "core.invalid")
		end
		table.insert(ids, id)
		local online = Players:GetPlayerByUserId(id)
		namesById[id] = if online then online.Name else tostring(id)
		if online then
			onlineById[id] = online
		end
	else
		for _, p in ipairs(resolveTargets(admin, args.Target)) do
			table.insert(ids, p.UserId)
			namesById[p.UserId] = p.Name
			onlineById[p.UserId] = p
		end
	end
	local valid: { number } = {}
	local lastError = L(admin, "admin.noTarget")
	for _, id in ipairs(ids) do
		local online = onlineById[id]
		if id == admin.UserId then
			lastError = L(admin, "admin.notSelf")
		elseif isOwnerId(id) or (online and AdminService.IsAdmin(online)) then
			lastError = L(admin, "admin.notOwner")
		elseif id <= 0 then
			lastError = L(admin, "admin.studioUser")
		elseif #valid < 50 then
			table.insert(valid, id)
		end
	end
	if #valid == 0 then
		return false, lastError
	end
	local reason = cleanText(args.Reason, SEC.BanDisplayMax or 400) or L(admin, "admin.banDefault")
	local evidence: { string } =
		{ ("Gebannt von %s (%d), %s"):format(admin.Name, admin.UserId, tostring(args.Duration)) }
	for _, id in ipairs(valid) do
		local online = onlineById[id]
		if online then
			local okSnap, snap = call("AntiCheatService", "Snapshot", online)
			if okSnap and type(snap) == "table" then
				table.insert(
					evidence,
					("%s: Kopf %s%%, Genauigkeit %s%%, Pops/min %s, Punkte %s"):format(
						online.Name,
						tostring(snap.HeadPct),
						tostring(snap.Accuracy),
						tostring(snap.PopsPerMin),
						tostring(snap.Score)
					)
				)
			end
		end
	end
	local duration = if seconds == -1 then -1 else math.max(60, math.floor(seconds))
	local ok, err = pcall(function()
		Players:BanAsync({
			UserIds = valid,
			Duration = duration,
			DisplayReason = truncate(reason, SEC.BanDisplayMax or 400),
			PrivateReason = truncate(table.concat(evidence, " | "), SEC.BanPrivateMax or 1000),
			ApplyToUniverse = true,
			ExcludeAltAccounts = false,
		})
	end)
	if not ok then
		return false, L(admin, "admin.banFailed", tostring(err))
	end
	local bannedNames: { string } = {}
	for _, id in ipairs(valid) do
		table.insert(bannedNames, namesById[id] or tostring(id))
		call("AntiCheatService", "LogBan", {
			UserId = id,
			Name = namesById[id] or tostring(id),
			Reason = reason,
			Duration = duration,
			By = admin.UserId,
			ByName = admin.Name,
			T = os.time(),
			Active = true,
			Auto = false,
		})
	end
	return true, L(admin, "admin.banned", tostring(args.Duration), table.concat(bannedNames, ", "))
end

Actions.Unban = function(admin, args)
	local id = tonumber(args.UserId)
	if not id or id % 1 ~= 0 then
		return false, L(admin, "core.invalid")
	end
	if id <= 0 then
		return false, L(admin, "admin.studioUser")
	end
	local ok, err = pcall(function()
		Players:UnbanAsync({ UserIds = { id }, ApplyToUniverse = true })
	end)
	if not ok then
		return false, L(admin, "admin.unbanFailed", tostring(err))
	end
	call("AntiCheatService", "MarkUnbanned", id)
	return true, L(admin, "admin.unbanned", id)
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

Actions.Warn = function(admin, args)
	local max = SEC.WarnMax or 150
	local text = cleanText(args.Text, max)
	if not text then
		return false, L(admin, "admin.textLen", max)
	end
	local filtered = filterBroadcast(text, admin.UserId)
	if not filtered then
		return false, L(admin, "admin.filterDown")
	end
	local warned: { Player } = {}
	local targets = resolveTargets(admin, args.Target)
	for _, p in ipairs(targets) do
		if p ~= admin or #targets == 1 then
			effect(p, "AdminWarn", 1, { Text = filtered })
			table.insert(warned, p)
			local okData, data = call("DataService", "Get", p)
			if okData and type(data) == "table" then
				if type(data.Mod) ~= "table" then
					data.Mod = { Warnings = 0, HardKicks = {} }
				end
				data.Mod.Warnings = (tonumber(data.Mod.Warnings) or 0) + 1
			end
		end
	end
	if #warned == 0 then
		return false, L(admin, "admin.noTarget")
	end
	return true, L(admin, "admin.warned", names(warned))
end

Actions.Freeze = function(admin, args)
	local on = args.On ~= false
	local done: { Player } = {}
	for _, p in ipairs(resolveTargets(admin, args.Target)) do
		local c = combatantOf(p)
		if c then
			call("CharacterService", "Freeze", c, on)
		else
			freezeLobby(p, on)
		end
		p:SetAttribute("AdminFrozen", if on then true else nil)
		if on then
			taintTargetMatch(p, "AdminFreeze")
		end
		table.insert(done, p)
	end
	if #done == 0 then
		return false, L(admin, "admin.noTarget")
	end
	return true, L(admin, if on then "admin.frozen" else "admin.unfrozen", names(done))
end

Actions.Bring = function(admin, args)
	local root = rootOf(admin)
	if not root then
		return false, L(admin, "admin.noCharacter")
	end
	local done: { Player } = {}
	for _, p in ipairs(resolveTargets(admin, args.Target)) do
		if p ~= admin and p.Character then
			local i = #done
			local offset = CFrame.new(((i % 5) - 2) * 3, 0, -5 - math.floor(i / 5) * 3)
			taintTargetMatch(p, "AdminBring")
			teleport(p, root.CFrame * offset)
			table.insert(done, p)
		end
	end
	if #done == 0 then
		return false, L(admin, "admin.noTarget")
	end
	return true, L(admin, "admin.brought", names(done))
end

Actions.Goto = function(admin, args)
	local target, err = resolveOne(admin, args.Target)
	if not target then
		return false, err or ""
	end
	local root = rootOf(target)
	if not root or target == admin then
		return false, L(admin, "admin.noTarget")
	end
	teleport(admin, root.CFrame * CFrame.new(0, 0, 4))
	return true, L(admin, "admin.went", target.DisplayName)
end

Actions.Pop = function(admin, args)
	local done: { Player } = {}
	local skipped: { Player } = {}
	for _, p in ipairs(resolveTargets(admin, args.Target)) do
		local c = combatantOf(p)
		if c and c.Alive == true then
			taintTargetMatch(p, "AdminPop")
			local pos = if typeof(c.Root) == "Instance" then (c.Root :: BasePart).Position else Vector3.zero
			local info: Types.ElimInfo =
				{ WeaponKey = "Admin", Head = false, Kind = "Admin", KillerId = nil, Assists = {}, Pos = pos }
			if call("CombatService", "Eliminate", c, info) then
				table.insert(done, p)
			end
		else
			table.insert(skipped, p)
		end
	end
	if #done == 0 then
		return false, L(admin, "admin.notInCombat", names(skipped))
	end
	return true, L(admin, "admin.popped", names(done))
end

Actions.Heal = function(admin, args)
	local done: { Player } = {}
	local skipped: { Player } = {}
	for _, p in ipairs(resolveTargets(admin, args.Target)) do
		local c = combatantOf(p)
		if c and c.Alive == true then
			taintTargetMatch(p, "AdminHeal")
			if call("CombatService", "Heal", c, tonumber(c.MaxHp) or 100) then
				table.insert(done, p)
			end
		else
			table.insert(skipped, p)
		end
	end
	if #done == 0 then
		return false, L(admin, "admin.notInCombat", names(skipped))
	end
	return true, L(admin, "admin.healed", names(done))
end

Actions.Give = function(admin, args)
	local grant = sanitizeGrant(args.Grant)
	if not grant then
		return false, L(admin, "admin.giveEmpty")
	end
	if not has("ShopService", "Grant") then
		return false, L(admin, "admin.unavailable", "ShopService")
	end
	local done = grantTo(resolveTargets(admin, args.Target), grant, "Admin")
	if #done == 0 then
		return false, L(admin, "admin.noTarget")
	end
	return true, L(admin, "admin.given", names(done))
end

Actions.GiveXp = function(admin, args)
	local amount = math.floor(num(args.Amount, 0, 0, 1e7))
	if amount < 1 then
		return false, L(admin, "core.invalid")
	end
	if not has("ProgressionService", "AddXp") then
		return false, L(admin, "admin.unavailable", "ProgressionService")
	end
	local done: { Player } = {}
	for _, p in ipairs(resolveTargets(admin, args.Target)) do
		if call("ProgressionService", "AddXp", p, amount, "Admin", { NoMult = true }) then
			table.insert(done, p)
		end
	end
	if #done == 0 then
		return false, L(admin, "admin.noTarget")
	end
	return true, L(admin, "admin.xpGiven", amount, names(done))
end

-- Level setzen: höher = über AddXp (mit Level-Belohnungen), niedriger = Spielstand direkt (Belege bleiben)
Actions.SetLevel = function(admin, args)
	local okPM, ProgressMath = pcall(require, Shared:FindFirstChild("ProgressMath") :: ModuleScript)
	if not okPM or type(ProgressMath) ~= "table" then
		return false, L(admin, "admin.unavailable", "ProgressMath")
	end
	pcall(ProgressMath.Configure, Config.Progression)
	local maxLevel = tonumber(ProgressMath.MaxLevel()) or 100
	local level = math.floor(num(args.Level, 0, 0, maxLevel))
	if level < 1 then
		return false, L(admin, "core.invalid")
	end
	local target = ProgressMath.TotalForLevel(level)
	local done: { Player } = {}
	for _, p in ipairs(resolveTargets(admin, args.Target)) do
		local okData, data = call("DataService", "Get", p)
		if okData and type(data) == "table" then
			local current = tonumber(data.Level) or 1
			local total = tonumber(data.TotalXP) or 0
			if level > current and target > total then
				if call("ProgressionService", "AddXp", p, target - total, "AdminSetLevel", { NoMult = true }) then
					table.insert(done, p)
				end
			else
				data.Level = level
				data.XP = 0
				data.TotalXP = target
				p:SetAttribute("Level", level)
				call("PlayerStateService", "SetLeaderstat", p, "Level", level)
				call("PlayerStateService", "MarkDirty", p)
				table.insert(done, p)
			end
		end
	end
	if #done == 0 then
		return false, L(admin, "admin.noTarget")
	end
	return true, L(admin, "admin.levelSet", level, names(done))
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
	local stats = if type(data.Stats) == "table" then data.Stats else {}
	local summary = {
		UserId = target.UserId,
		Name = target.Name,
		Coins = data.Coins,
		Gems = data.Gems,
		Keys = data.Keys,
		Shards = data.Shards,
		Level = data.Level,
		XP = data.XP,
		TotalXP = data.TotalXP,
		Mmr = data.Mmr,
		Matches = stats.Matches,
		Wins = stats.Wins,
		Elims = stats.Elims,
		Headshots = stats.Headshots,
		BestStreak = stats.BestStreak,
		Weapons = count(type(data.Weapons) == "table" and data.Weapons.Owned),
		Cosmetics = count(type(data.Cosmetics) == "table" and data.Cosmetics.Owned),
		RobuxSpent = type(data.Purchases) == "table" and data.Purchases.RobuxSpent or 0,
		Receipts = count(type(data.Purchases) == "table" and data.Purchases.Receipts),
		Warnings = type(data.Mod) == "table" and data.Mod.Warnings or 0,
		HardKicks = count(type(data.Mod) == "table" and data.Mod.HardKicks),
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
				table.insert(out, { Id = tostring(r.Id), T = tonumber(r.T) or 0 })
			end
		end
	end
	return true, L(admin, "admin.receipts", #out, target.DisplayName), out
end

local function productExists(key: any): boolean
	local products = Config.Shop and Config.Shop.Products
	if type(key) ~= "string" or type(products) ~= "table" then
		return false
	end
	for _, product in ipairs(products) do
		if type(product) == "table" and product.Key == key then
			return true
		end
	end
	return false
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
-- AKTIONEN – Reiter KRÄFTE (eigene Attribute; Server ehrt sie nur bei IsAdmin)
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
			value = args.Value ~= false -- CanFly ist Standard (an); aus = false
		end
	else
		local limits = SEC.Powers and SEC.Powers[kind]
		local lo = if type(limits) == "table" then tonumber(limits.Min) or 0 else 0
		local hi = if type(limits) == "table" then tonumber(limits.Max) or 100 else 100
		if Util.IsFinite(args.Value) then
			local v = math.clamp(args.Value, lo, hi)
			-- Grundwert = "aus" (Tempo 16, Sprung 7.2, Feuerrate ×1)
			if v > lo + 0.001 then
				value = if kind == "Jump" then math.floor(v * 10 + 0.5) / 10 else math.floor(v * 100 + 0.5) / 100
			end
		end
	end
	admin:SetAttribute(name, value)
	if name == "AdminInvisible" then
		setInvisible(admin, value == true)
	end
	local inMatch = false
	if value ~= nil and value ~= false then
		inMatch = taintIfInMatch(admin, name)
	end
	local shown = if value == nil or value == false
		then L(admin, "admin.off")
		elseif value == true then L(admin, "admin.on")
		else tostring(value)
	local message = L(admin, "admin.powerSet", name, shown)
	if inMatch then
		message ..= " · " .. L(admin, "admin.tainted")
	end
	return true, message, { Name = name, Value = value }
end

-- =====================================================================
-- AKTIONEN – Reiter WAFFEN & ITEMS
-- =====================================================================
Actions.GiveAll = function(admin, args)
	if not has("ShopService", "Grant") then
		return false, L(admin, "admin.unavailable", "ShopService")
	end
	local grant: Types.Grant = { Weapons = allWeaponKeys(), Cosmetics = allCosmeticIds() }
	local done = grantTo(resolveTargets(admin, args.Target), grant, "AdminAll")
	if #done == 0 then
		return false, L(admin, "admin.noTarget")
	end
	return true, L(admin, "admin.allGiven", names(done))
end

Actions.AdminWeapon = function(admin, args)
	local id = tonumber(args.Id)
	if not id or id % 1 ~= 0 or id < ADMIN_WEAPON_MIN or id > ADMIN_WEAPON_MAX then
		return false, L(admin, "admin.badWeapon")
	end
	local def: any = Config.WeaponById(id)
	if not def or def.AdminOnly ~= true then
		return false, L(admin, "admin.badWeapon")
	end
	local ok, given = call("WeaponService", "GiveAdminWeapon", admin, id)
	if not ok or given ~= true then
		return false, L(admin, "admin.weaponFailed")
	end
	local message = L(admin, "admin.weaponGiven", Lang.Pick(langOf(admin), def.Name or { de = def.Key, en = def.Key }))
	if taintIfInMatch(admin, "AdminWeapon") then
		message ..= " · " .. L(admin, "admin.tainted")
	end
	return true, message
end

-- =====================================================================
-- AKTIONEN – Reiter MATCH & SERVER
-- =====================================================================
local function matchRow(info: any): { [string]: any }?
	if type(info) ~= "table" or not Util.IsFinite(info.MatchId) then
		return nil
	end
	local players: { string } = {}
	if type(info.Players) == "table" then
		for _, name in ipairs(info.Players) do
			table.insert(players, tostring(name))
		end
	end
	local score: { number } = {}
	if type(info.Score) == "table" then
		for _, v in ipairs(info.Score) do
			table.insert(score, tonumber(v) or 0)
		end
	end
	return {
		MatchId = info.MatchId,
		Slot = tonumber(info.Slot) or 0,
		Mode = tostring(info.Mode or "?"),
		Map = tostring(info.Map or "?"),
		Phase = tostring(info.Phase or "?"),
		Score = score,
		Players = players,
		Bots = tonumber(info.Bots) or 0,
		Tainted = info.Tainted == true,
	}
end

Actions.Matches = function(admin, _args)
	local ok, list = call("MatchService", "List")
	if not ok then
		return false, L(admin, "admin.unavailable", "MatchService")
	end
	local out: { any } = {}
	if type(list) == "table" then
		for _, entry in ipairs(list) do
			local info: any = entry
			if Util.IsFinite(entry) then
				local okInfo, result = call("MatchService", "Info", entry)
				info = if okInfo then result else nil
			elseif type(entry) == "table" and entry.Phase == nil and Util.IsFinite(entry.MatchId) then
				local okInfo, result = call("MatchService", "Info", entry.MatchId)
				info = if okInfo and type(result) == "table" then result else entry
			end
			local row = matchRow(info)
			if row then
				table.insert(out, row)
			end
		end
	end
	return true, L(admin, "admin.matches", #out), out
end

Actions.EndMatch = function(admin, args)
	local id = tonumber(args.MatchId)
	if not id or id % 1 ~= 0 then
		return false, L(admin, "core.invalid")
	end
	if not call("MatchService", "End", id, "Admin") then
		return false, L(admin, "admin.unavailable", "MatchService")
	end
	return true, L(admin, "admin.matchEnded", id)
end

local function difficultyValid(name: any): boolean
	local list = Config.Bots and Config.Bots.Difficulties
	return type(name) == "string" and type(list) == "table" and list[name] ~= nil
end

local function parseUserIds(raw: any): { number }
	local out: { number } = {}
	if type(raw) == "string" then
		for part in string.gmatch(raw, "[^,%s]+") do
			local id = tonumber(part)
			if id and id % 1 == 0 then
				table.insert(out, id)
			end
			if #out >= 16 then
				break
			end
		end
	elseif type(raw) == "table" then
		for i, v in ipairs(raw) do
			if i > 16 then
				break
			end
			local id = tonumber(v)
			if id and id % 1 == 0 then
				table.insert(out, id)
			end
		end
	end
	return out
end

Actions.StartMatch = function(admin, args)
	local modes = Config.Modes and Config.Modes.Modes
	local modeKey = args.Mode
	local mode = if type(modes) == "table" and type(modeKey) == "string" then modes[modeKey] else nil
	if type(mode) ~= "table" then
		return false, L(admin, "admin.badMode")
	end
	local teamCount = math.floor(tonumber(mode.Teams) or 2)
	local ffa = teamCount == 0
	local teamSize = math.max(1, math.floor(tonumber(mode.TeamSize) or 1))
	local capacity = if ffa then math.max(2, math.floor(tonumber(mode.MaxPlayers) or 8)) else teamCount * teamSize
	-- Map: leer = Zufall; sonst muss sie den Modus können
	local map: string? = nil
	if type(args.Map) == "string" and args.Map ~= "" then
		local maps = Config.Maps and Config.Maps.Maps
		local def = if type(maps) == "table" then maps[args.Map] else nil
		local fits = type(def) == "table" and type(def.Modes) == "table" and table.find(def.Modes, modeKey) ~= nil
		if not fits then
			return false, L(admin, "admin.badMap")
		end
		map = args.Map
	end
	local moods = Config.Maps and Config.Maps.Moods
	local mood = if type(args.Mood) == "string" and type(moods) == "table" and moods[args.Mood] then args.Mood else nil
	local mutator = if mutatorValid(args.Mutator) then args.Mutator else nil
	-- Menschen: UserIds (leer = ich), nur wer nicht schon in einem Match ist
	local humans: { Player } = {}
	local ids = parseUserIds(args.UserIds)
	if #ids == 0 then
		ids = { admin.UserId }
	end
	for _, id in ipairs(ids) do
		local p = Players:GetPlayerByUserId(id)
		if p and not table.find(humans, p) and matchOf(p) == nil and #humans < capacity then
			table.insert(humans, p)
		end
	end
	if #humans == 0 then
		return false, L(admin, "admin.noTarget")
	end
	local difficulty = args.BotDifficulty
	if not difficultyValid(difficulty) then
		local ok, picked = call("BotService", "DifficultyFor", humans)
		difficulty = if ok and difficultyValid(picked) then picked else "Normal"
	end
	local free = capacity - #humans
	local fillTo = if ffa then math.floor(tonumber(mode.FillTo) or capacity) - #humans else free
	local botCount = if Util.IsFinite(args.Bots)
		then math.clamp(math.floor(args.Bots), 0, free)
		else math.clamp(fillTo, 0, free)
	local teams: { { any } } = {}
	if ffa then
		local list: { any } = {}
		for _, p in ipairs(humans) do
			table.insert(list, p)
		end
		for _ = 1, botCount do
			table.insert(list, { Bot = true, Difficulty = difficulty })
		end
		if #list < 2 then
			table.insert(list, { Bot = true, Difficulty = difficulty })
		end
		teams = { list }
	else
		for t = 1, math.max(2, teamCount) do
			teams[t] = {}
		end
		for i, p in ipairs(humans) do
			table.insert(teams[((i - 1) % #teams) + 1], p)
		end
		local function smallest(): { any }?
			local best: { any }? = nil
			for _, team in ipairs(teams) do
				if #team < teamSize and (best == nil or #team < #best) then
					best = team
				end
			end
			return best
		end
		for _ = 1, botCount do
			local team = smallest()
			if not team then
				break
			end
			table.insert(team, { Bot = true, Difficulty = difficulty })
		end
		for _, team in ipairs(teams) do
			if #team == 0 then -- jedes Team braucht mindestens einen
				table.insert(team, { Bot = true, Difficulty = difficulty })
			end
		end
	end
	for _, p in ipairs(humans) do
		call("QueueService", "Leave", p)
	end
	local spec: Types.MatchSpec = {
		Mode = modeKey,
		Teams = teams :: any,
		Map = map,
		Mood = mood,
		Mutator = mutator,
		AdminStarted = true,
	}
	local ok, id = call("MatchService", "Create", spec)
	if not ok or not Util.IsFinite(id) then
		return false, L(admin, "admin.matchFailed")
	end
	return true, L(admin, "admin.matchStarted", id)
end

Actions.SpawnBot = function(admin, args)
	local difficulty = if difficultyValid(args.Difficulty) then args.Difficulty else "Normal"
	local c = combatantOf(admin)
	if not c or type(c.Ctx) ~= "string" then
		return false, L(admin, "admin.needCtx")
	end
	local used: { [number]: boolean } = {}
	local okList, list = call("CombatService", "InCtx", c.Ctx)
	if okList and type(list) == "table" then
		for _, other in ipairs(list) do
			if type(other) == "table" and Util.IsFinite(other.Slot) then
				used[other.Slot] = true
			end
		end
	end
	local slot: number? = nil
	for s = 1, 32 do
		if not used[s] then
			slot = s
			break
		end
	end
	if not slot then
		return false, L(admin, "admin.botFailed")
	end
	local myTeam = tonumber(c.Team) or 1
	local team = if myTeam == 0 then 0 elseif myTeam == 1 then 2 else 1
	local ok, bot = call("BotService", "Spawn", difficulty, c.Ctx, team, slot, nil)
	if not ok or type(bot) ~= "table" then
		return false, L(admin, "admin.botFailed")
	end
	local root = rootOf(admin)
	if root then
		call("CharacterService", "Teleport", bot, root.CFrame * CFrame.new(0, 0, -10) * CFrame.Angles(0, math.pi, 0))
	end
	taintIfInMatch(admin, "AdminSpawnBot")
	return true, L(admin, "admin.botSpawned", difficulty)
end

Actions.FillPads = function(admin, _args)
	if not call("QueueService", "ForceFillPads") then
		return false, L(admin, "admin.unavailable", "QueueService")
	end
	return true, L(admin, "admin.padsFilled")
end

Actions.LockServer = function(admin, args)
	serverLocked = args.On == true
	workspace:SetAttribute("ServerLocked", if serverLocked then true else nil)
	return true, L(admin, if serverLocked then "admin.locked" else "admin.unlockedServer")
end

Actions.KickAll = function(admin, args)
	local raw = cleanText(args.Reason, MAX_REASON)
	local filtered = if raw then filterBroadcast(raw, admin.UserId) else nil
	local count = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= admin and not protectedPlayer(p) then
			count += 1
			p:Kick(filtered or L(p, "admin.kickAllDefault"))
		end
	end
	return true, L(admin, "admin.kickedAll", count)
end

Actions.ServerInfo = function(admin, _args)
	local schedulerStats = Scheduler.Stats()
	local total = schedulerStats._Total
	local jobs: { { [string]: any } } = {}
	for name, stat in pairs(schedulerStats) do
		if name ~= "_Total" then
			table.insert(jobs, { Name = name, AvgMs = stat.AvgMs, MaxMs = stat.MaxMs })
		end
	end
	table.sort(jobs, function(a, b)
		return a.AvgMs > b.AvgMs
	end)
	while #jobs > 6 do
		table.remove(jobs)
	end
	local okSlots, slots = call("ArenaService", "SlotStates")
	local slotList: { any } = {}
	if okSlots and type(slots) == "table" then
		for _, s in ipairs(slots) do
			if type(s) == "table" then
				table.insert(slotList, { Slot = s.Slot, State = tostring(s.State), MapKey = s.MapKey })
			end
		end
	end
	local okFree, freeSlots = call("ArenaService", "FreeSlots")
	local okProj, projectiles = call("ProjectileService", "Count")
	local memoryOk, memory = pcall(function()
		return Stats:GetTotalMemoryUsageMb()
	end)
	local e = event
	local data = {
		Players = #Players:GetPlayers(),
		MaxPlayers = Players.MaxPlayers,
		Bots = #CollectionService:GetTagged("Bot"),
		FreeSlots = if okFree and Util.IsFinite(freeSlots) then freeSlots else nil,
		Slots = slotList,
		Projectiles = if okProj and Util.IsFinite(projectiles) then projectiles else 0,
		HeartbeatMs = if total then total.AvgMs else 0,
		HeartbeatMaxMs = if total then total.MaxMs else 0,
		Jobs = jobs,
		MemoryMb = if memoryOk and Util.IsFinite(memory) then math.floor(memory) else 0,
		Uptime = math.floor(os.clock() - startedAt),
		Version = Config.Version,
		JobId = if game.JobId ~= "" then game.JobId else "Studio",
		Locked = serverLocked,
		Balance = select(2, call("BalanceService", "Version")) or 0,
		Event = if e and workspace:GetServerTimeNow() < e.Until
			then { Until = e.Until, Coins2 = e.Coins2, Xp2 = e.Xp2 }
			else nil,
		Studio = RunService:IsStudio(),
	}
	return true, L(admin, "admin.serverInfo"), data
end

-- =====================================================================
-- AKTIONEN – Reiter EVENTS
-- =====================================================================
Actions.Announce = function(admin, args)
	local max = SEC.AnnounceMax or 200
	local text = cleanText(args.Text, max)
	if not text then
		return false, L(admin, "admin.textLen", max)
	end
	local filtered = filterBroadcast(text, admin.UserId)
	if not filtered then
		return false, L(admin, "admin.filterDown")
	end
	local message = {
		Kind = "Announce",
		Text = filtered,
		UserId = admin.UserId,
		Name = string.sub(admin.DisplayName, 1, MAX_NAME),
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

Actions.AdminAbuse = function(admin, args)
	local maxMinutes = tonumber(SEC.AdminAbuseMaxMinutes) or 60
	local minutes = math.floor(num(args.Minutes, 5, 1, maxMinutes))
	local coins2, xp2 = args.Coins2 == true, args.Xp2 == true
	if not coins2 and not xp2 then
		return false, L(admin, "admin.abuseNeedBoost")
	end
	local message = {
		Kind = "AdminAbuse",
		Until = workspace:GetServerTimeNow() + minutes * 60,
		Coins2 = coins2,
		Xp2 = xp2,
	}
	if args.Global == true then
		if publishGlobal(message) then
			return true, L(admin, "admin.abuseGlobal", minutes)
		end
		return true, L(admin, "admin.globalFailed")
	end
	handleGlobal(message)
	return true, L(admin, "admin.abuseSet", minutes)
end

Actions.Mutator = function(admin, args)
	local key = args.Key
	if key == "" then
		key = nil
	end
	if key ~= nil and not mutatorValid(key) then
		return false, L(admin, "admin.badMutator")
	end
	if args.Global == true then
		local hours = tonumber(SEC.MutatorGlobalHours) or 24
		local untilT = os.time() + math.floor(hours * 3600)
		local stored = { Key = key, Until = if key then untilT else 0 }
		local okStore = pcall(function()
			local store = DataStoreService:GetDataStore(Config.Tech.LiveStore)
			store:UpdateAsync("Mutator", function()
				return stored
			end)
		end)
		if not okStore then
			warn("[Admin] Globaler Mutator konnte nicht gespeichert werden (Studio ohne API?)")
		end
		local message = { Kind = "Mutator", Key = key, Until = untilT }
		if not publishGlobal(message) then
			return true, L(admin, "admin.globalFailed")
		end
	else
		applyMutator(key, nil)
	end
	if key then
		return true, L(admin, "admin.mutatorSet", key)
	end
	return true, L(admin, "admin.mutatorCleared")
end

Actions.Confetti = function(admin, _args)
	for _, p in ipairs(Players:GetPlayers()) do
		local root = rootOf(p)
		effect(p, "Confetti", 1, if root then { Pos = root.Position } else nil)
	end
	return true, L(admin, "admin.confetti")
end

Actions.LobbyGravity = function(admin, args)
	local limits = SEC.LobbyGravity or { Min = 50, Max = DEFAULT_GRAVITY }
	local value = num(args.Value, DEFAULT_GRAVITY, limits.Min or 50, limits.Max or DEFAULT_GRAVITY)
	lobbyGravity = math.floor(value * 10 + 0.5) / 10
	workspace:SetAttribute("LobbyGravity", if lobbyGravity < DEFAULT_GRAVITY - 0.05 then lobbyGravity else nil)
	updateLobbyGravity()
	return true, L(admin, "admin.gravity", tostring(lobbyGravity))
end

Actions.LobbyLook = function(admin, args)
	local moods = Config.Maps and Config.Maps.Moods
	local mood = args.Mood
	if type(mood) ~= "string" or type(moods) ~= "table" or moods[mood] == nil then
		return false, L(admin, "admin.badMood")
	end
	lobbyMood = mood
	workspace:SetAttribute("LobbyMood", mood)
	-- Licht ist nur client-lokal (GraphicsService ändert Lighting nach dem Boot nie wieder)
	effectAll("LobbyLook", 1, { Mood = mood }, function(p)
		return matchOf(p) == nil
	end)
	return true, L(admin, "admin.lobbyLook", mood)
end

-- =====================================================================
-- AKTIONEN – Reiter BALANCE (Live)
-- =====================================================================
local function balance(): any
	return service("BalanceService")
end

Actions.GetBalance = function(admin, _args)
	local ok, data = call("BalanceService", "GetBalance")
	if not ok or type(data) ~= "table" then
		return false, L(admin, "admin.unavailable", "BalanceService")
	end
	return true, L(admin, "admin.balance", tonumber(data.Version) or 0), data
end

Actions.SetField = function(admin, args)
	if not balance() then
		return false, L(admin, "admin.unavailable", "BalanceService")
	end
	local value = tonumber(args.Value)
	local ok, applied, result = call("BalanceService", "SetField", args.Weapon, args.Field, value)
	if not ok or applied ~= true then
		return false, L(admin, "admin.badField")
	end
	return true, L(admin, "admin.fieldSet", tostring(args.Weapon), tostring(args.Field), tostring(result))
end

Actions.SaveBalance = function(admin, _args)
	local ok, saved, version, localOnly = call("BalanceService", "Save", admin)
	if not ok or saved ~= true then
		return false, L(admin, "admin.saveFailed")
	end
	if localOnly then
		return true, L(admin, "admin.savedLocal", version)
	end
	return true, L(admin, "admin.saved", version)
end

Actions.Revert = function(admin, args)
	local version = tonumber(args.Version)
	if not version then
		return false, L(admin, "core.invalid")
	end
	local ok, reverted, newVersion = call("BalanceService", "Revert", version, admin)
	if not ok or reverted ~= true then
		return false, L(admin, "admin.noVersion")
	end
	return true, L(admin, "admin.reverted", math.floor(version), tonumber(newVersion) or 0)
end

Actions.ResetWeapon = function(admin, args)
	local ok, done = call("BalanceService", "ResetWeapon", args.Weapon)
	if not ok or done ~= true then
		return false, L(admin, "admin.badField")
	end
	return true, L(admin, "admin.weaponReset", tostring(args.Weapon))
end

Actions.SetEnabled = function(admin, args)
	local on = args.On == true
	local ok, done = call("BalanceService", "SetEnabled", args.Weapon, on, admin)
	if not ok or done ~= true then
		return false, L(admin, "admin.saveFailed")
	end
	return true, L(admin, if on then "admin.enabled" else "admin.disabled", tostring(args.Weapon))
end

-- =====================================================================
-- AKTIONEN – Reiter STATISTIK
-- =====================================================================
Actions.GetStats = function(admin, args)
	local days = if tonumber(args.Days) == 7 then 7 else 1
	local ok, data = call("BalanceService", "GetStats", days)
	if not ok or type(data) ~= "table" then
		return false, L(admin, "admin.unavailable", "BalanceService")
	end
	return true, L(admin, "admin.stats", days), data
end

-- =====================================================================
-- AKTIONEN – Reiter MODERATION
-- =====================================================================
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
	return true, L(admin, "admin.reports", #list), list
end

-- =====================================================================
-- AKTIONEN – Reiter DEBUG
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
	local allowed: boolean? = nil
	if args.Allowed == true then
		allowed = true
	elseif args.Allowed == false then
		allowed = false
	end
	if not call("MonetizationService", "SetPolicyOverride", admin, allowed) then
		return false, L(admin, "admin.unavailable", "MonetizationService")
	end
	local label = if allowed == true
		then L(admin, "admin.policyAllowed")
		elseif allowed == false then L(admin, "admin.policyRestricted")
		else L(admin, "admin.policyAuto")
	return true, L(admin, "admin.policy", label)
end

Actions.SkipDay = function(admin, _args)
	if not RunService:IsStudio() then
		return false, L(admin, "admin.studioOnly")
	end
	local offset = Util.GetDayOffset() + 1
	Util.SetDayOffset(offset)
	return true, L(admin, "admin.daySkipped", offset)
end

Actions.UnlockAll = function(admin, _args)
	if not has("ShopService", "Grant") then
		return false, L(admin, "admin.unavailable", "ShopService")
	end
	local grant: Types.Grant = { Weapons = allWeaponKeys(), Cosmetics = allCosmeticIds() }
	local ok, result = call("ShopService", "Grant", admin, grant, "AdminUnlockAll")
	if not ok or result ~= true then
		return false, L(admin, "core.error")
	end
	local message = L(admin, "admin.unlockedAll")
	-- Taint-frei nur in Studio; live zählt es als Admin-Kraft im laufenden Match
	if not RunService:IsStudio() and taintIfInMatch(admin, "AdminUnlockAll") then
		message ..= " · " .. L(admin, "admin.tainted")
	end
	return true, message
end

Actions.SetDebug = function(admin, args)
	local debug: any = Config.Debug
	for _, key in ipairs({ "ShowHitboxes", "LogRejects", "BotPaths" }) do
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
		L(admin, "admin.debugSet", onOff(debug.ShowHitboxes), onOff(debug.LogRejects), onOff(debug.BotPaths)),
		{
			ShowHitboxes = debug.ShowHitboxes == true,
			LogRejects = debug.LogRejects == true,
			BotPaths = debug.BotPaths == true,
		}
end

Actions.RunSelfTest = function(admin, _args)
	local ok, passed, total = call("SelfTestService", "Run")
	if not ok then
		return false, L(admin, "admin.unavailable", "SelfTestService")
	end
	return (tonumber(passed) or 0) == (tonumber(total) or -1),
		L(admin, "admin.selfTest", tonumber(passed) or 0, tonumber(total) or 0)
end

-- =====================================================================
-- LEBENSZYKLUS
-- =====================================================================
local function dispatch(p: Player, action: any, args: any): { Ok: boolean, Message: string?, Data: any? }
	-- Spam-Bremse ZUERST (auch für Nicht-Admins, sonst fluten Exploiter das Server-Log)
	if not limiter.Check(p) then
		return { Ok = false, Message = L(p, "core.tooFast") }
	end
	if not AdminService.IsAdmin(p) then
		if not warnedDenied[p] then
			warnedDenied[p] = true
			warn(("[Admin] Unerlaubter Zugriff von %s (%d)"):format(p.Name, p.UserId))
		end
		return { Ok = false, Message = L(p, "admin.denied") }
	end
	if type(action) ~= "string" or #action > 40 or not Actions[action] then
		return { Ok = false, Message = L(p, "core.unknownAction") }
	end
	local cleanArgs: { [string]: any } = if type(args) == "table" then args else {}
	local ok, success, message, data = pcall(Actions[action], p, cleanArgs)
	if not ok then
		warn(("[Admin] Fehler bei %s: %s"):format(action, tostring(success)))
		return { Ok = false, Message = L(p, "admin.error", tostring(success)) }
	end
	if not QUIET[action] then
		print(("[Admin] %s -> %s: %s"):format(p.Name, action, tostring(message)))
	end
	return { Ok = success == true, Message = if type(message) == "string" then message else nil, Data = data }
end

local function tick()
	-- Admin-Abuse vorbei?
	local e = event
	if e and workspace:GetServerTimeNow() >= e.Until then
		event = nil
		notifyAll("admin.abuseEnd", nil, "Event")
	end
	-- globaler Mutator abgelaufen?
	if mutatorUntil and os.time() >= mutatorUntil then
		applyMutator(nil, nil)
	end
	monitorTaint()
	if lobbyGravity < DEFAULT_GRAVITY - 0.05 or workspace:GetAttribute("LobbyGravity") ~= nil then
		updateLobbyGravity()
	end
end

local function onReady(p: Player)
	local e = event
	if e and workspace:GetServerTimeNow() < e.Until then
		effect(p, "Event", 1, { Kind = "AdminAbuse", Until = e.Until, Coins2 = e.Coins2, Xp2 = e.Xp2 })
	end
	if lobbyMood then
		effect(p, "LobbyLook", 1, { Mood = lobbyMood })
	end
end

function AdminService.Init(services: any)
	Services = services
end

function AdminService.Start()
	local function onCharacter(p: Player, _character: Model)
		frozenLobby[p] = nil
		if p:GetAttribute("AdminFrozen") ~= nil then
			p:SetAttribute("AdminFrozen", nil)
		end
		if AdminService.IsAdmin(p) and p:GetAttribute("AdminInvisible") == true then
			task.defer(setInvisible, p, true)
		end
	end
	local function onPlayer(p: Player)
		joinedAt[p] = joinedAt[p] or os.clock()
		if AdminService.IsAdmin(p) then
			p:SetAttribute("IsAdmin", true)
			p:SetAttribute("CanFly", true)
		elseif serverLocked then
			p:Kick(L(p, "admin.lockedKick"))
			return
		end
		p.CharacterAdded:Connect(function(character)
			onCharacter(p, character)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayer, p)
	end
	Players.PlayerRemoving:Connect(function(p)
		limiter.Clear(p)
		adminCache[p] = nil
		warnedDenied[p] = nil
		joinedAt[p] = nil
		taintedFor[p] = nil
		frozenLobby[p] = nil
		local conn = invisConn[p]
		if conn then
			conn:Disconnect()
		end
		invisConn[p] = nil
	end)
	call("PlayerStateService", "OnReady", onReady)

	Remotes.Admin.OnServerInvoke = dispatch

	Scheduler.Every("AdminTick", 1, tick)

	-- Global: Ansagen, Admin-Abuse, Mutator (Sender empfängt auch selbst)
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
	-- Globaler Mutator-Override, der beim Start noch läuft
	task.spawn(function()
		local ok, stored = pcall(function()
			return DataStoreService:GetDataStore(Config.Tech.LiveStore):GetAsync("Mutator")
		end)
		if ok and type(stored) == "table" and mutatorValid(stored.Key) then
			if Util.IsFinite(stored.Until) and stored.Until > os.time() then
				applyMutator(stored.Key, stored.Until)
			end
		end
	end)
end

return AdminService
