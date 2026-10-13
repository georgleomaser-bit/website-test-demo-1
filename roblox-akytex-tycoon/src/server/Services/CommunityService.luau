-- =====================================================================
--  AKYTEX TYCOON – Sozial ohne Chat: Ansagen, Freunde-Bonus, Respekt, Reaktionen, Zeigen-Karte, Einladen,
--  Gruppe, Benachrichtigungs-Opt-in (Server/Services/CommunityService)
--  Besitzer: WP9 (Fortschritt, Tutorial, Sozial, Bestenlisten). Vertrag: DESIGN.md §C5.8, §C9 (Social*, NotifyOptIn),
--  §C10 (State "Social"), §B11.3–§B11.5, §B11.9, §C11.2 (Alt-Farming: AccountAge ≥ 3 Tage + 10 min Sitzung,
--  Einladungs-Belohnungen max. 10/Woche), REUSE §1.3 (CC-CommunityService PATTERN: Announce, Freunde).
--
--  Öffentliche API (§C5.8):
--    CommunityService.Announce(key, args?, filter?)   System-Ansage, je Empfänger lokalisiert (Effekt "Announce" ohne
--                                                     UserId -> Toast, REUSE §7 #6). args-Elemente dürfen {de, en} sein.
--    CommunityService.FriendsInServer(p): number      Freunde im Server (IsFriendsWithAsync 1× je Paar/Sitzung, gecacht)
--    CommunityService.RespektActive(p): number        aktive Respekt-Boni (je +0,01 Perm, max. 20; TowerService)
--  Request-Handler: SocialRespekt, SocialReact, SocialShow, SocialInvited, NotifyOptIn.   State: "Social".
--  Player-Attribute: "React" ("Art:n", Client zeigt die Blase), "ShowCard" (Zeigen-Karte, Client zeigt 6 s),
--    "Group" (Namensschild-Rahmen).
--  Einladungs-Gutschriften für Einlader, die gerade nicht im Server sind: DataStore Config.Tech.GlobalStore,
--  Schlüssel "Ref_<UserId>" { Week, N, Pending } (Abholung beim nächsten Beitritt, keine HTTP-Prüfung).
-- =====================================================================

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Types = require(Shared:WaitForChild("Types"))
local Lang = require(Shared:WaitForChild("Lang"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local CommunityService = {}
local Services: any = nil

type Reply = Types.Reply
type Data = { [string]: any }

local PCFG: any = Config.Progression
local SOCIAL: any = PCFG.Social
local SECURITY: any = Config.Security or {}
local MAX_ARGS = 8
local LOG_GAP = 10
local REFERRAL_EVERY = 30
local REFERRAL_CLAIM_EVERY = 600
local MAX_TEXT = 500

-- Pro-Spieler-Tabellen (alle bei PlayerRemoving geleert)
local sessionStart: { [Player]: number } = {}
local friendCache: { [Player]: { [number]: boolean } } = {}
local friendBusy: { [Player]: { [number]: boolean } } = {}
local respektActive: { [Player]: { number } } = {}
local reactCounter: { [Player]: number } = {}
local showCounter: { [Player]: number } = {}
local refClaimAt: { [Player]: number } = {}
local lastLogAt: { [string]: number } = {}
local refStore: DataStore? = nil
local refStoreFailed = false

-- ---------------------------------------------------------------------
-- 1) HELFER
-- ---------------------------------------------------------------------
local function logError(where: string, err: any)
	local now = os.clock()
	if (lastLogAt[where] or -math.huge) + LOG_GAP <= now then
		lastLogAt[where] = now
		warn("[CommunityService] " .. where .. ": " .. tostring(err))
	end
end

local function finite(n: any): boolean
	return Util.IsFinite(n)
end

local function num(v: any, default: number): number
	return if Util.IsFinite(v) then v else default
end

local function isInt(v: any): boolean
	return Util.IsFinite(v) and v % 1 == 0
end

local function call(name: string, fnName: string, ...: any): (boolean, ...any)
	local svc = Services and Services[name]
	local fn = svc and svc[fnName]
	if type(fn) ~= "function" then
		return false
	end
	local results = table.pack(pcall(fn, ...))
	if not results[1] then
		logError(name .. "." .. fnName, results[2])
		return false
	end
	return true, table.unpack(results, 2, results.n)
end

local function dataOf(p: Player): Data?
	local ok, data = call("DataService", "Get", p)
	if ok and type(data) == "table" then
		return data
	end
	return nil
end

local function langOf(p: Player): Types.Lang
	local ok, lang = call("PlayerStateService", "LangOf", p)
	if ok and (lang == "de" or lang == "en") then
		return lang
	end
	return "en"
end

local function T(p: Player, key: string, ...: any): string
	return Lang.T(langOf(p), key, ...)
end

local function fail(p: Player, key: string, ...: any): Reply
	return { Ok = false, Message = T(p, key, ...) }
end

local function notify(p: Player, key: string, args: { any }?, kind: Types.NotifyKind?)
	call("PlayerStateService", "Notify", p, key, args, kind)
end

local function markDirty(p: Player, ...: string)
	call("PlayerStateService", "MarkDirty", p, ...)
end

local function emptyArg(arg: any): boolean
	return arg == nil or (type(arg) == "table" and next(arg) == nil)
end

local function exactKeys(arg: any, keys: { string }): boolean
	if type(arg) ~= "table" then
		return false
	end
	local allowed: { [string]: boolean } = {}
	for _, key in ipairs(keys) do
		allowed[key] = true
		if arg[key] == nil then
			return false
		end
	end
	for key in pairs(arg) do
		if type(key) ~= "string" or not allowed[key] then
			return false
		end
	end
	return true
end

local function socialOf(data: Data): Data
	local social = data.Social
	if type(social) ~= "table" then
		social = {}
		data.Social = social
	end
	if type(social.RespektGiven) ~= "table" then
		social.RespektGiven = {}
	end
	social.RespektDay = math.floor(num(social.RespektDay, 0))
	social.ReferredBy = math.floor(num(social.ReferredBy, 0))
	social.ReferralDone = social.ReferralDone == true
	social.ReferralWeek = math.floor(num(social.ReferralWeek, 0))
	social.ReferralCount = math.max(0, math.floor(num(social.ReferralCount, 0)))
	social.Group = social.Group == true
	return social
end

-- Studio: AccountAge-Prüfung übersprungen (§C17), Mindest-Sitzung verkürzt (Test → 2 Players)
local function studioSkip(): boolean
	return RunService:IsStudio() and Config.Studio and Config.Studio.SkipAccountAge == true
end

local function accountAgeOk(p: Player): boolean
	if studioSkip() then
		return true
	end
	return p.AccountAge >= num(SECURITY.AccountAgeMin, 3)
end

local function sessionOk(p: Player): boolean
	local need = if studioSkip() then num(SOCIAL.SessionMinStudio, 30) else num(SECURITY.SessionMinForSocial, 600)
	local start = sessionStart[p]
	return start ~= nil and os.clock() - start >= need
end

-- ---------------------------------------------------------------------
-- 2) ANSAGEN
-- ---------------------------------------------------------------------
function CommunityService.Announce(key: string, args: { any }?, filter: ((Player) -> boolean)?)
	if type(key) ~= "string" or key == "" then
		return
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local pass = true
		if filter then
			local ok, result = pcall(filter, p)
			pass = ok and result == true
		end
		if pass then
			local lang = langOf(p)
			local resolved = {}
			if type(args) == "table" then
				for i = 1, math.min(#args, MAX_ARGS) do
					local value = args[i]
					if type(value) == "table" then
						resolved[i] = Lang.Pick(lang, value)
					elseif type(value) == "number" or type(value) == "string" then
						resolved[i] = value
					else
						resolved[i] = tostring(value)
					end
				end
			end
			local text = Lang.T(lang, key, table.unpack(resolved, 1, #resolved))
			-- ohne UserId/Name = System-Ansage (Toast), kein Besitzer-Haken (REUSE §7 #6)
			call("PlayerStateService", "Effect", p, "Announce", 1, { Text = string.sub(text, 1, MAX_TEXT) })
		end
	end
end

-- ---------------------------------------------------------------------
-- 3) FREUNDE (IsFriendsWithAsync 1× je Paar und Sitzung, im Hintergrund)
-- ---------------------------------------------------------------------
local function isFriends(p: Player, userId: number): boolean?
	local ok, result = pcall(function()
		local subject: any = p
		local method = subject.IsFriendsWithAsync
		if type(method) == "function" then
			return method(subject, userId)
		end
		return subject:IsFriendsWith(userId)
	end)
	if not ok then
		-- Methode fehlt in dieser Engine-Version -> ältere Variante versuchen
		local okOld, old = pcall(function()
			local subject: any = p
			return subject:IsFriendsWith(userId)
		end)
		if okOld then
			return old == true
		end
		logError("IsFriendsWithAsync", result)
		return nil
	end
	return result == true
end

local function checkPair(a: Player, b: Player)
	if a == b or a.UserId <= 0 or b.UserId <= 0 then
		return -- Studio-Testspieler sind keine Freunde
	end
	local cacheA = friendCache[a]
	local busyA = friendBusy[a]
	if not cacheA or not busyA or cacheA[b.UserId] ~= nil or busyA[b.UserId] then
		return
	end
	busyA[b.UserId] = true
	task.spawn(function()
		local result = isFriends(a, b.UserId)
		busyA[b.UserId] = nil
		if result ~= nil and friendCache[a] == cacheA then
			cacheA[b.UserId] = result
			local cacheB = friendCache[b]
			if cacheB then
				cacheB[a.UserId] = result -- Freundschaft ist gegenseitig: ein Aufruf je Paar
			end
			if result then
				markDirty(a, "Social")
				markDirty(b, "Social")
			end
		end
	end)
end

function CommunityService.FriendsInServer(p: Player): number
	local cache = friendCache[p]
	if not cache then
		return 0
	end
	local n = 0
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= p and cache[other.UserId] == true then
			n += 1
		end
	end
	return n
end

-- ---------------------------------------------------------------------
-- 4) RESPEKT (§B11.3)
-- ---------------------------------------------------------------------
local function pruneRespekt(p: Player): { number }
	local list = respektActive[p]
	if not list then
		list = {}
		respektActive[p] = list
	end
	local now = os.clock()
	for i = #list, 1, -1 do
		if list[i] <= now then
			table.remove(list, i)
		end
	end
	return list
end

function CommunityService.RespektActive(p: Player): number
	if typeof(p) ~= "Instance" or not respektActive[p] then
		return 0
	end
	return math.min(#pruneRespekt(p), SOCIAL.RespektMax)
end

local function eventActive(kind: string): boolean
	local ok, list = call("EventService", "Active")
	if not ok or type(list) ~= "table" then
		return false
	end
	local now = os.time()
	for _, ev in ipairs(list) do
		if type(ev) == "table" and ev.Kind == kind and num(ev.Until, 0) > now then
			return true
		end
	end
	return false
end

local function roomCount(p: Player, room: string): number
	local ok, n = call("TowerService", "RoomCount", p, room)
	return if ok and finite(n) then n else 0
end

local function nearTower(giver: Player, owner: Player): boolean
	local okVisit, visiting = call("PlotService", "VisitingOf", giver)
	if okVisit and visiting == owner.UserId then
		return true
	end
	local okPlot, plot = call("PlotService", "PlotOf", owner)
	if not okPlot or not isInt(plot) then
		return false
	end
	local okCf, cf = call("PlotService", "PlotCFrame", plot)
	local character = giver.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not okCf or typeof(cf) ~= "CFrame" or not root or not root:IsA("BasePart") then
		return false
	end
	local offset = root.Position - cf.Position
	return Vector2.new(offset.X, offset.Z).Magnitude <= SOCIAL.RespektRange
end

local function weekRespekt(social: Data): number
	if social.RespektWeek ~= Util.IsoWeek() then
		return 0
	end
	return math.max(0, math.floor(num(social.RespektGot, 0)))
end

-- Saison-XP für den Besucher (Config.Season.XpSources.Respekt.Xp, Standard 25)
local function respektSeasonXp(): number
	local season = Config.Season
	local sources = if type(season) == "table" then season.XpSources else nil
	local entry = if type(sources) == "table" then sources.Respekt else nil
	return if type(entry) == "table" then num(entry.Xp, 25) else 25
end

local function handleRespekt(p: Player, arg: any): Reply
	if not exactKeys(arg, { "UserId" }) or not isInt(arg.UserId) then
		return fail(p, "core.invalid")
	end
	local owner = Players:GetPlayerByUserId(arg.UserId)
	if not owner or owner == p then
		return fail(p, "soc.respektNoOwner")
	end
	if not accountAgeOk(p) then
		return fail(p, "soc.respektAge", num(SECURITY.AccountAgeMin, 3))
	end
	if not sessionOk(p) then
		return fail(p, "soc.respektSession")
	end
	local data, ownerData = dataOf(p), dataOf(owner)
	if not data or not ownerData then
		return fail(p, "core.loading")
	end
	if not nearTower(p, owner) then
		return fail(p, "soc.respektFar")
	end
	local social = socialOf(data)
	local day = Util.UtcDay()
	if social.RespektDay ~= day then
		social.RespektDay = day
		social.RespektGiven = {}
	end
	local key = tostring(owner.UserId)
	if social.RespektGiven[key] == day then
		return fail(p, "soc.respektAlready")
	end
	social.RespektGiven[key] = day
	-- Besitzer: +0,01 Perm je Respekt für 1 h (Lounge 2 h); Marketing-Studio und Sky-Show zählen doppelt
	local weight = 1
	if roomCount(owner, "Marketing") > 0 then
		weight = 2
	end
	if eventActive(SOCIAL.SkyShowKind) then
		weight *= 2
	end
	local hours = if roomCount(owner, "Lounge") > 0 then SOCIAL.LoungeHours else SOCIAL.RespektHours
	local list = pruneRespekt(owner)
	for _ = 1, weight do
		table.insert(list, os.clock() + hours * 3600)
	end
	table.sort(list)
	while #list > SOCIAL.RespektMax do
		table.remove(list, 1) -- die ältesten laufen zuerst ab
	end
	local ownerSocial = socialOf(ownerData)
	local week = Util.IsoWeek()
	if ownerSocial.RespektWeek ~= week then
		ownerSocial.RespektWeek = week
		ownerSocial.RespektGot = 0
	end
	ownerSocial.RespektGot = math.floor(num(ownerSocial.RespektGot, 0)) + weight
	call("ProgressionService", "NoteStat", owner, "RespektGot", 1, nil)
	call("LeaderboardService", "Submit", owner)
	notify(owner, "soc.respektGot", { p.DisplayName }, "Success")
	-- Besucher: +25 Saison-XP (max. 5/Tag) + Quest/Erfolg
	call("RewardService", "GrantSeasonXp", p, respektSeasonXp(), "Respekt")
	call("RewardService", "Track", p, "GiveRespekt", 1, { Owner = owner.UserId })
	markDirty(p, "Social")
	markDirty(owner, "Social")
	return { Ok = true, Message = T(p, "soc.respektSent", owner.DisplayName) }
end

-- ---------------------------------------------------------------------
-- 5) REAKTIONEN & ZEIGEN-KARTE (ohne Chat; Attribute replizieren an alle Clients)
-- ---------------------------------------------------------------------
local reactionKeys: { [string]: boolean } = {}
for _, entry in ipairs(SOCIAL.Reactions) do
	reactionKeys[entry.Key] = true
end

local function handleReact(p: Player, arg: any): Reply
	if not exactKeys(arg, { "Kind" }) or type(arg.Kind) ~= "string" or not reactionKeys[arg.Kind] then
		return fail(p, "core.invalid")
	end
	local n = (reactCounter[p] or 0) % 1000 + 1
	reactCounter[p] = n
	p:SetAttribute("React", arg.Kind .. ":" .. tostring(n))
	return { Ok = true }
end

local TIER_ORDER = { "Bronze", "Silber", "Gold", "Diamant" }

local function leagueTier(stats: any): string
	if type(stats) ~= "table" or stats.Qualified ~= true then
		return "None"
	end
	local tier = "None"
	local trading = Config.Trading
	local tiers = if type(trading) == "table" and type(trading.League) == "table" then trading.League.Tiers else nil
	if type(tiers) == "table" then
		for _, entry in ipairs(tiers) do
			if type(entry) == "table" and num(stats.SkillScore, 0) >= num(entry.Min, math.huge) then
				tier = entry.Key
			end
		end
	end
	return tier
end

local function handleShow(p: Player, arg: any): Reply
	if not emptyArg(arg) then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	local okStage, stage = call("TowerService", "Stage", p)
	local okLic, licence = call("ProgressionService", "Licence", p)
	local okStats, stats = call("OrderService", "LeagueStats", p)
	local okTitle, title = call("ProgressionService", "Title", p)
	local garage = data.Garage
	local car = if type(garage) == "table" and type(garage.Active) == "string" then garage.Active else ""
	local skill = if okStats and type(stats) == "table" then math.floor(num(stats.SkillScore, 0)) else 0
	local tier = leagueTier(if okStats then stats else nil)
	if tier == "None" then
		local league = data.League
		local last = if type(league) == "table" then league.LastTier else nil
		if type(last) == "string" and table.find(TIER_ORDER, last) then
			tier = last
		end
	end
	local n = (showCounter[p] or 0) % 1000 + 1
	showCounter[p] = n
	-- kompakt: Stufe|Lizenz|Skill-Score|Liga-Stufe|Titel|Auto|Zähler – KEIN Trade-G/V (§B11.5)
	local card = table.concat({
		tostring(if okStage and finite(stage) then math.floor(stage) else 1),
		tostring(if okLic and finite(licence) then math.floor(licence) else 1),
		tostring(skill),
		tier,
		if okTitle and type(title) == "string" then title else "",
		car,
		tostring(n),
	}, "|")
	p:SetAttribute("ShowCard", card)
	return { Ok = true, Message = T(p, "soc.showSent") }
end

local function handleInvited(p: Player, arg: any): Reply
	if not emptyArg(arg) then
		return fail(p, "core.invalid")
	end
	call("MetricsService", "Custom", p, "InvitePrompted", 1, nil)
	return { Ok = true }
end

local function handleOptIn(p: Player, arg: any): Reply
	if not exactKeys(arg, { "Result" }) or type(arg.Result) ~= "boolean" then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	local notif = data.Notif
	if type(notif) ~= "table" then
		notif = {}
		data.Notif = notif
	end
	notif.LastPrompt = os.time()
	notif.OptIn = arg.Result
	call("MetricsService", "Custom", p, "NotifyOptIn", if arg.Result then 1 else 0, nil)
	markDirty(p, "Social")
	return { Ok = true }
end

-- ---------------------------------------------------------------------
-- 6) EINLADEN (§B11.4): Neuling erreicht Etage 10 + 10 min -> beide Boost x2 30 min + Neon "Partner"
-- ---------------------------------------------------------------------
local function store(): DataStore?
	if refStore or refStoreFailed then
		return refStore
	end
	local name = (Config.Tech or {}).GlobalStore or "AT_Global"
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(name)
	end)
	if ok then
		refStore = result
	else
		refStoreFailed = true
		logError("GetDataStore", result)
	end
	return refStore
end

local function referralReward(): Types.Grant
	local cfg = SOCIAL.Referral
	return { BoostX2 = cfg.BoostSeconds, Cosmetics = { cfg.Neon } }
end

-- Einlader im Server: Wochen-Deckel aus seinem Spielstand
local function rewardInviter(inviter: Player, n: number): number
	local data = dataOf(inviter)
	if not data then
		return 0
	end
	local social = socialOf(data)
	local week = Util.IsoWeek()
	if social.ReferralWeek ~= week then
		social.ReferralWeek = week
		social.ReferralCount = 0
	end
	local room = math.max(0, SOCIAL.Referral.WeeklyMax - social.ReferralCount)
	local count = math.min(n, room)
	if count <= 0 then
		return 0
	end
	local grant = referralReward()
	grant.BoostX2 = (grant.BoostX2 :: number) * count
	local ok, granted = call("ShopService", "Grant", inviter, grant, "Referral")
	if not ok or granted ~= true then
		return 0
	end
	social.ReferralCount += count
	call("ProgressionService", "NoteStat", inviter, "Invites", count, nil)
	notify(inviter, "soc.inviteReward", { count }, "Success")
	markDirty(inviter, "Social")
	return count
end

-- Einlader nicht im Server: Gutschrift im DataStore vormerken (Wochen-Deckel beim Schreiben)
local function queueInviter(inviterId: number)
	local ds = store()
	if not ds then
		return
	end
	local key = (PCFG.Boards.ReferralKeyPrefix or "Ref_") .. tostring(inviterId)
	local week = Util.IsoWeek()
	task.spawn(function()
		local ok, err = pcall(function()
			ds:UpdateAsync(key, function(old: any)
				local entry = if type(old) == "table" then old else {}
				if entry.Week ~= week then
					entry.Week = week
					entry.N = 0
				end
				if num(entry.N, 0) >= SOCIAL.Referral.WeeklyMax then
					return nil -- Deckel erreicht: nichts ändern
				end
				entry.N = num(entry.N, 0) + 1
				entry.Pending = math.clamp(num(entry.Pending, 0) + 1, 0, SOCIAL.Referral.WeeklyMax * 4)
				return entry
			end)
		end)
		if not ok then
			logError("Referral UpdateAsync", err)
		end
	end)
end

-- Grant fehlgeschlagen: Gutschrift zurücklegen (kein Verlust)
local function queueInviterBack(userId: number, n: number)
	local ds = store()
	if not ds then
		return
	end
	local key = (PCFG.Boards.ReferralKeyPrefix or "Ref_") .. tostring(userId)
	task.spawn(function()
		local ok, err = pcall(function()
			ds:UpdateAsync(key, function(old: any)
				local entry = if type(old) == "table" then old else {}
				entry.Pending = math.clamp(num(entry.Pending, 0) + n, 0, SOCIAL.Referral.WeeklyMax * 4)
				return entry
			end)
		end)
		if not ok then
			logError("Referral zurücklegen", err)
		end
	end)
end

-- beim Beitritt (und alle 10 min): vorgemerkte Gutschriften abholen
local function claimQueued(p: Player)
	if p.UserId <= 0 then
		return
	end
	local ds = store()
	if not ds then
		return
	end
	local key = (PCFG.Boards.ReferralKeyPrefix or "Ref_") .. tostring(p.UserId)
	task.spawn(function()
		local pending = 0
		local ok, err = pcall(function()
			ds:UpdateAsync(key, function(old: any)
				if type(old) ~= "table" or num(old.Pending, 0) <= 0 then
					pending = 0
					return nil
				end
				pending = math.floor(num(old.Pending, 0))
				old.Pending = 0
				return old
			end)
		end)
		if not ok then
			logError("Referral claim", err)
			return
		end
		if pending > 0 and p.Parent == Players then
			local data = dataOf(p)
			if not data then
				return
			end
			-- der Wochen-Deckel wurde schon beim Vormerken geprüft
			local grant = referralReward()
			grant.BoostX2 = (grant.BoostX2 :: number) * pending
			local okGrant, granted = call("ShopService", "Grant", p, grant, "Referral")
			if okGrant and granted == true then
				call("ProgressionService", "NoteStat", p, "Invites", pending, nil)
				notify(p, "soc.inviteReward", { pending }, "Success")
				markDirty(p, "Social")
			else
				queueInviterBack(p.UserId, pending)
			end
		end
	end)
end

local function checkReferral(p: Player)
	local data = dataOf(p)
	if not data then
		return
	end
	local social = socialOf(data)
	if social.ReferralDone or social.ReferredBy <= 0 then
		return
	end
	local okFloors, floors = call("TowerService", "Floors", p)
	if not okFloors or not finite(floors) or floors < SOCIAL.Referral.Floor then
		return
	end
	local played = num(data.Playtime, 0) + (os.clock() - (sessionStart[p] or os.clock()))
	if played < SOCIAL.Referral.PlayMinutes * 60 then
		return
	end
	local ok, granted = call("ShopService", "Grant", p, referralReward(), "Referral")
	if not ok or granted ~= true then
		return
	end
	social.ReferralDone = true
	notify(p, "soc.inviteNewbie", nil, "Success")
	markDirty(p, "Social")
	local inviter = Players:GetPlayerByUserId(social.ReferredBy)
	if inviter then
		rewardInviter(inviter, 1)
	else
		queueInviter(social.ReferredBy)
	end
end

local function readReferral(p: Player, data: Data)
	local social = socialOf(data)
	if social.ReferredBy > 0 or num(data.Sessions, 0) > 1 then
		return
	end
	local ok, joinData = pcall(function()
		return p:GetJoinData()
	end)
	if not ok or type(joinData) ~= "table" then
		return
	end
	local inviterId = joinData.ReferredByPlayerId
	if isInt(inviterId) and inviterId > 0 and inviterId ~= p.UserId then
		social.ReferredBy = inviterId
		call("MetricsService", "Custom", p, "Referred", 1, nil)
		markDirty(p, "Social")
	end
end

-- ---------------------------------------------------------------------
-- 7) GRUPPE (IsInGroupAsync, pcall): Community-Krone + Namensschild-Rahmen, kein Einkommen
-- ---------------------------------------------------------------------
local function checkGroup(p: Player)
	local groupId = SOCIAL.GroupId
	if not isInt(groupId) or groupId <= 0 or p.UserId <= 0 then
		return
	end
	task.spawn(function()
		local ok, result = pcall(function()
			local subject: any = p
			local method = subject.IsInGroupAsync
			if type(method) == "function" then
				return method(subject, groupId)
			end
			return subject:IsInGroup(groupId)
		end)
		if not ok then
			logError("IsInGroupAsync", result)
			return
		end
		if p.Parent ~= Players then
			return
		end
		local data = dataOf(p)
		if data then
			local social = socialOf(data)
			social.Group = result == true
			p:SetAttribute("Group", social.Group)
			markDirty(p, "Social", "Life")
		end
	end)
end

-- ---------------------------------------------------------------------
-- 8) STATE "Social" (§C10)
-- ---------------------------------------------------------------------
local function socialState(p: Player): { [string]: any }
	local data = dataOf(p)
	if not data then
		return { RespektActive = 0, Friends = 0 }
	end
	local social = socialOf(data)
	local day = Util.UtcDay()
	local givenToday = 0
	if social.RespektDay == day then
		for _, value in pairs(social.RespektGiven) do
			if value == day then
				givenToday += 1
			end
		end
	end
	local given: { [string]: boolean } = {}
	if social.RespektDay == day then
		for key, value in pairs(social.RespektGiven) do
			if value == day then
				given[key] = true
			end
		end
	end
	local notif = if type(data.Notif) == "table" then data.Notif else {}
	local flags = if type(data.Flags) == "table" then data.Flags else {}
	local okStage, stage = call("TowerService", "Stage", p)
	local stageNow = if okStage and finite(stage) then stage else 1
	local lastPrompt = num(notif.LastPrompt, 0)
	local tutStep = math.floor(num(flags.TutStep, 0))
	local tutorialDone = flags.Done == true or flags.Skipped == true
	return {
		RespektGivenToday = givenToday,
		RespektGiven = given,
		RespektActive = CommunityService.RespektActive(p),
		RespektWeek = weekRespekt(social),
		Friends = CommunityService.FriendsInServer(p),
		ReferredBy = social.ReferredBy,
		ReferralDone = social.ReferralDone,
		ReferralCount = if social.ReferralWeek == Util.IsoWeek() then social.ReferralCount else 0,
		ReferralMax = SOCIAL.Referral.WeeklyMax,
		Group = social.Group,
		GroupId = SOCIAL.GroupId,
		InviteAllowed = stageNow >= SOCIAL.InviteFromStage,
		SocialReady = accountAgeOk(p) and sessionOk(p),
		NotifLastPrompt = lastPrompt,
		NotifOptIn = notif.OptIn == true,
		CanPromptNotify = (tutorialDone or tutStep >= num(Config.Notifications.PromptAfterStep, 17))
			and os.time() - lastPrompt >= SOCIAL.NotifyRepromptDays * 86400,
	}
end

-- ---------------------------------------------------------------------
-- 9) LEBENSZYKLUS
-- ---------------------------------------------------------------------
local function onPlayerAdded(p: Player)
	sessionStart[p] = os.clock()
	friendCache[p] = friendCache[p] or {}
	friendBusy[p] = friendBusy[p] or {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= p and friendCache[other] then
			checkPair(p, other)
		end
	end
end

local function onReady(p: Player)
	local data = dataOf(p)
	if not data then
		return
	end
	local social = socialOf(data)
	p:SetAttribute("Group", social.Group)
	readReferral(p, data)
	checkGroup(p)
	refClaimAt[p] = os.clock()
	claimQueued(p)
	markDirty(p, "Social")
end

local function onPlayerRemoving(p: Player)
	sessionStart[p] = nil
	friendCache[p] = nil
	friendBusy[p] = nil
	respektActive[p] = nil
	reactCounter[p] = nil
	showCounter[p] = nil
	refClaimAt[p] = nil
	for _, cache in pairs(friendCache) do
		cache[p.UserId] = nil
	end
	-- Freunde-Bonus der anderen ändert sich
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= p then
			markDirty(other, "Social")
		end
	end
end

local function referralTick()
	for _, p in ipairs(Players:GetPlayers()) do
		local ok, ready = call("PlayerStateService", "IsReady", p)
		if ok and ready == true then
			checkReferral(p)
			if os.clock() - (refClaimAt[p] or 0) >= REFERRAL_CLAIM_EVERY then
				refClaimAt[p] = os.clock()
				claimQueued(p)
			end
		end
	end
end

function CommunityService.Init(services: any)
	Services = services
	local pss = services.PlayerStateService
	if not pss then
		warn("[CommunityService] PlayerStateService fehlt – keine Anfragen/State")
		return
	end
	pss.Provide("Social", socialState)
	pss.Handle("SocialRespekt", handleRespekt, { Rate = 1, Per = 1 })
	pss.Handle("SocialReact", handleReact, { Rate = 2, Per = 1 })
	pss.Handle("SocialShow", handleShow, { Rate = 1, Per = 60 })
	pss.Handle("SocialInvited", handleInvited, { Rate = 1, Per = 10 })
	pss.Handle("NotifyOptIn", handleOptIn, { Rate = 1, Per = 10 })
end

function CommunityService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, p)
	end
	call("PlayerStateService", "OnReady", onReady)
	Scheduler.Every("CommunityReferral", 1 / REFERRAL_EVERY, referralTick)
end

return CommunityService
