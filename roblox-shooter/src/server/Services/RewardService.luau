-- =====================================================================
--  CLUTCH CLASH – Belohnungen: Quests, Login-Kalender, Glücksrad, Spielzeit-Geschenke, Codes
--  (Server/Services/RewardService)
--  Besitzer: WP8 (Fortschritt). Vertrag: DESIGN.md C5.8 + B16.3 + B16.4 + C9.
--  Muster aus dem Meteor-Heist-RewardService (REUSE §1.3): Spielzeit pro UTC-Tag über alle Besuche,
--  3 Tagesquests mit Gratis-Tausch, Track() immer über pcall aufgerufen.
--
--  Öffentliche API (C5.8):
--    RewardService.Track(p, kind, amount, ctx?)   Quest-Fortschritt (nur Server). ctx { Mode?, Map?, Pvp? }
--    RewardService.FirstWinToday(p): boolean      true genau beim ersten Aufruf je UTC-Tag (markiert den Tag)
--  Zähl-Arten (kind): Match, Win, PvpWin, RoundWon, RoundFullHp, OvertimeRound, CrownDefence, Damage, Assist
--    (ProgressionService bei Match-Ende) · Elim, HeadElim, MeleeElim, SecondaryElim, SmgShotgunElim,
--    SlideElim, SplashElim, FfaStreak3, DummyHit (hier live aus CombatService) · Heal, Slide (WP3) ·
--    MasteryTier (ProgressionService) · Commend (CommunityService) · Level, NewWeapon, LoadoutEdit
--    (zusätzlich am Spielstand geprüft, 1×/s).
--  Request-Aktionen (C9): ClaimQuest id · RerollQuest index · ClaimLogin · SpinWheel · ClaimGift index (je 1/s)
--    · RedeemCode code (5/min).
--  State-Schlüssel: Quests, Login, Daily.
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Lang = require(Shared:WaitForChild("Lang"))
local Types = require(Shared:WaitForChild("Types"))
local ProgressMath = require(Shared:WaitForChild("ProgressMath"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local RewardService = {}
local Services: any = nil

type Reply = Types.Reply
type Quest = {
	Id: string,
	Kind: string,
	Goal: number,
	P: number,
	Claimed: boolean,
	Tier: string?,
	Maps: { [string]: boolean }?,
}

local P = Config.Progression
local Q = P.Quests

local LOG_GAP = 10
local MAX_TRACK = 1000000
local MAX_CODE_LEN = 20
local PLAY_TICK_MAX = 5 -- Sekunden: längere Lücken (Server-Hänger) zählen nicht
local PLAY_STATE_EVERY = 30 -- Spielzeit-State höchstens alle 30 s senden (Client zählt selbst weiter)
local MATCH_INFO_TTL = 5
local MATCH_INFO_MAX = 32
local DEFAULT_OWNED = { PopRifle = true, PipPistol = true, BoxingGloves = true, PopGrenade = true }
local DEFAULT_PRESET = { P = "PopRifle", S = "PipPistol", M = "BoxingGloves", U = "PopGrenade" }

-- Nachschlagen: Quest-Id -> Config-Eintrag
local questDefs: { [string]: { [string]: any } } = {}
for _, listName in ipairs({ "Daily", "Weekly", "Beginner" }) do
	for _, def in ipairs(Q[listName] or {}) do
		if type(def) == "table" and type(def.Id) == "string" then
			questDefs[def.Id] = def
		end
	end
end
local smgShotgun: { [string]: boolean } = {}
for _, key in ipairs(Q.SmgShotgunWeapons or {}) do
	smgShotgun[key] = true
end

-- Pro-Spieler-Tabellen (alle bei PlayerRemoving geleert)
local playStateAt: { [Player]: number } = {}
local ffaStreak: { [Player]: { Match: string, N: number } } = {}
local lastLogAt: { [string]: number } = {}
-- Match-Infos (Modus/Map) kurz zwischenspeichern: Ctx -> { At, Mode, Map }
local matchInfoCache: { [string]: { At: number, Mode: string?, Map: string? } } = {}

-- ---------------------------------------------------------------------
-- 0) HELFER
-- ---------------------------------------------------------------------
local function logError(where: string, err: any)
	local now = os.clock()
	if (lastLogAt[where] or -math.huge) + LOG_GAP <= now then
		lastLogAt[where] = now
		warn("[RewardService] " .. where .. ": " .. tostring(err))
	end
end

local function finite(n: any): boolean
	return Util.IsFinite(n)
end

local function num(v: any, default: number): number
	if finite(v) then
		return v
	end
	return default
end

local function try(service: string, fnName: string, ...: any): (boolean, any)
	local s = Services and Services[service]
	local fn = s and s[fnName]
	if type(fn) ~= "function" then
		return false, nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		logError(service .. "." .. fnName, result)
		return false, nil
	end
	return true, result
end

local function asPlayer(v: any): Player?
	if typeof(v) == "Instance" and v:IsA("Player") then
		return v :: any
	end
	return nil
end

local function isPlayer(p: any): boolean
	return typeof(p) == "Instance" and p:IsA("Player") and p.Parent == Players
end

local function dataOf(p: Player): Types.PlayerData?
	local dataService = Services and Services.DataService
	if not dataService or not isPlayer(p) then
		return nil
	end
	local ok, data = pcall(dataService.Get, p)
	if ok and type(data) == "table" then
		return data
	end
	return nil
end

local function langOf(p: Player): Types.Lang
	local ok, lang = try("PlayerStateService", "LangOf", p)
	if ok and (lang == "de" or lang == "en") then
		return lang
	end
	return Lang.For(p)
end

local function t(p: Player, key: string, ...: any): string
	return Lang.T(langOf(p), key, ...)
end

local function fail(p: Player, key: string, ...: any): Reply
	return { Ok = false, Message = t(p, key, ...) }
end

local function notify(p: Player, key: string, args: { any }?, kind: Types.NotifyKind?)
	try("PlayerStateService", "Notify", p, key, args, kind)
end

local function dirty(p: Player, ...: string)
	try("PlayerStateService", "MarkDirty", p, ...)
end

local function grant(p: Player, g: Types.Grant, reason: string): boolean
	local ok, result = try("ShopService", "Grant", p, g, reason)
	return ok and result == true
end

local function hasPass(p: Player, key: string): boolean
	local ok, result = try("MonetizationService", "HasPass", p, key)
	return ok and result == true
end

local function tableField(parent: { [string]: any }, key: string): { [string]: any }
	local value = parent[key]
	if type(value) ~= "table" then
		value = {}
		parent[key] = value
	end
	return value
end

local function describe(p: Player, reward: any): string
	local lang = langOf(p)
	return ProgressMath.DescribeReward(reward, function(key: string, ...: any): string
		return Lang.T(lang, key, ...)
	end, function(id: string): string
		local cosmetics = Config.Cosmetics
		local def = cosmetics and cosmetics.ById and cosmetics.ById[id]
		if type(def) == "table" and type(def.Name) == "table" then
			return Lang.Pick(lang, def.Name)
		end
		return id
	end)
end

-- Nur Währungs-/Boost-Felder einer Config-Belohnung als Grant (W = Rad-Gewicht fällt weg)
local function toGrant(reward: any): Types.Grant
	local g: Types.Grant = {}
	if type(reward) ~= "table" then
		return g
	end
	for _, field in ipairs({ "Coins", "Gems", "Keys", "Shards", "XpBoostSeconds" }) do
		local v = reward[field]
		if finite(v) and v > 0 then
			(g :: any)[field] = math.floor(v)
		end
	end
	if type(reward.Cosmetics) == "table" then
		g.Cosmetics = reward.Cosmetics
	end
	return g
end

local function serverIn(seconds: number): number
	return workspace:GetServerTimeNow() + math.max(0, seconds)
end

-- Sekunden bis zum nächsten UTC-Tag (00:00) bzw. bis Montag 00:00 UTC
local function secondsToNextDay(): number
	return 86400 - (os.time() % 86400)
end

local function secondsToNextWeek(): number
	local now = os.time()
	local day = math.floor(now / 86400)
	local weekday = ((day + 3) % 7) + 1 -- 1 = Montag … 7 = Sonntag
	return (8 - weekday) * 86400 - (now % 86400)
end

-- ---------------------------------------------------------------------
-- 1) QUEST-DATEN (Rotation pro UTC-Tag / ISO-Woche, deterministisch pro Spieler)
-- ---------------------------------------------------------------------
local function newQuest(def: { [string]: any }): Quest
	return { Id = def.Id, Kind = def.Kind, Goal = def.Goal, P = 0, Claimed = false, Tier = def.Tier }
end

local function buildList(ids: { string }): { Quest }
	local list: { Quest } = {}
	for _, id in ipairs(ids) do
		local def = questDefs[id]
		if def then
			table.insert(list, newQuest(def))
		end
	end
	return list
end

local function sanitizeList(list: any): boolean
	if type(list) ~= "table" or #list == 0 then
		return false
	end
	for _, q in ipairs(list) do
		if type(q) ~= "table" or type(q.Id) ~= "string" or type(q.Kind) ~= "string" or not finite(q.Goal) then
			return false
		end
		q.P = math.clamp(num(q.P, 0), 0, q.Goal)
		q.Claimed = q.Claimed == true
	end
	return true
end

-- Gibt true zurück, wenn sich etwas geändert hat (neuer Tag / neue Woche / repariert)
local function ensureQuests(p: Player, data: Types.PlayerData): boolean
	local q = tableField(data, "Quests")
	local changed = false
	local today = Util.UtcDay()
	if q.Day ~= today or not sanitizeList(q.Daily) then
		local ids = ProgressMath.PickDaily(Q.Daily, Q.DailyTiers, ProgressMath.Seed(today, p.UserId))
		q.Daily = buildList(ids)
		q.Day = today
		q.Rerolls = num(Q.FreeRerolls, 1) + (if hasPass(p, "VIP") then num(Q.VipRerolls, 1) else 0)
		q.DailyBonus = false
		changed = true
	end
	local week = Util.IsoWeek()
	if q.Week ~= week or not sanitizeList(q.Weekly) then
		local ids = ProgressMath.PickWeekly(Q.Weekly, Q.WeeklyCount, ProgressMath.Seed(week, p.UserId))
		q.Weekly = buildList(ids)
		q.Week = week
		q.WeeklyChest = false
		changed = true
	end
	local beginner = tableField(q, "Beginner")
	beginner.Step = math.clamp(math.floor(num(beginner.Step, 1)), 1, #Q.Beginner + 1)
	beginner.P = math.max(0, num(beginner.P, 0))
	q.Rerolls = math.max(0, math.floor(num(q.Rerolls, 0)))
	return changed
end

local function questText(p: Player, id: string, goal: number): string
	return t(p, "prog.q." .. id, goal)
end

-- Modus/Map aus dem Kampf-Kontext "M<id>" (MatchService.Info, kurz zwischengespeichert)
local function matchInfoOf(ctxName: any): (string?, string?)
	if type(ctxName) ~= "string" or string.sub(ctxName, 1, 1) ~= "M" then
		return nil, nil
	end
	local now = os.clock()
	local cached = matchInfoCache[ctxName]
	if cached and now - cached.At <= MATCH_INFO_TTL then
		return cached.Mode, cached.Map
	end
	local id = tonumber(string.sub(ctxName, 2))
	local mode, map = nil, nil
	if id then
		local ok, info = try("MatchService", "Info", id)
		if ok and type(info) == "table" then
			mode = if type(info.Mode) == "string" then info.Mode else nil
			map = if type(info.Map) == "string" then info.Map else nil
		end
	end
	-- Speicher begrenzen: bei Überlauf alles verwerfen (billig, selten)
	local count = 0
	for _ in pairs(matchInfoCache) do
		count += 1
	end
	if count >= MATCH_INFO_MAX then
		table.clear(matchInfoCache)
	end
	matchInfoCache[ctxName] = { At = now, Mode = mode, Map = map }
	return mode, map
end

-- Kontext für Filter vervollständigen (Modus/Map des aktuellen Matches des Spielers)
local function resolveCtx(p: Player, ctx: { [string]: any }?): { [string]: any }
	local out: { [string]: any } = {}
	if type(ctx) == "table" then
		for k, v in pairs(ctx) do
			out[k] = v
		end
	end
	if out.Mode == nil or out.Map == nil then
		local okId, matchId = try("MatchService", "MatchOf", p)
		if okId and finite(matchId) then
			local mode, map = matchInfoOf("M" .. tostring(matchId))
			out.Mode = out.Mode or mode
			out.Map = out.Map or map
		end
	end
	return out
end

local function filterOk(def: { [string]: any }?, ctx: { [string]: any }): boolean
	if not def then
		return true
	end
	if def.Pvp and ctx.Pvp ~= true then
		return false
	end
	local filter = def.Filter
	if type(filter) == "table" then
		if filter.Mode ~= nil and ctx.Mode ~= filter.Mode then
			return false
		end
		if filter.Map ~= nil and ctx.Map ~= filter.Map then
			return false
		end
	end
	return true
end

local function needsCtx(kind: string, list: { Quest }, beginnerDef: { [string]: any }?): boolean
	for _, q in ipairs(list) do
		local def = questDefs[q.Id]
		if (q.Kind == kind or (kind == "Match" and q.Kind == "DifferentMaps")) and def and (def.Filter or def.Pvp) then
			return true
		end
	end
	return beginnerDef ~= nil and beginnerDef.Kind == kind and beginnerDef.Filter ~= nil
end

-- ---------------------------------------------------------------------
-- 2) ANFÄNGER-KETTE: zustandsbasierte Schritte (Level, neue Waffe, Loadout bearbeitet)
-- ---------------------------------------------------------------------
local function ownsNewWeapon(data: Types.PlayerData): boolean
	local weapons = data.Weapons
	local owned = type(weapons) == "table" and weapons.Owned or nil
	if type(owned) ~= "table" then
		return false
	end
	for key, value in pairs(owned) do
		if value == true then
			local def = Config.Weapon(key)
			local free = if def then def.Free == true else DEFAULT_OWNED[key] == true
			if not free then
				return true
			end
		end
	end
	return false
end

local function editedLoadout(data: Types.PlayerData): boolean
	local loadouts = data.Loadouts
	local presets = type(loadouts) == "table" and loadouts.Presets or nil
	if type(presets) ~= "table" then
		return false
	end
	local default = Config.Weapons and Config.Weapons.DefaultLoadout
	local base = if type(default) == "table"
		then { P = default.Primary, S = default.Secondary, M = default.Melee, U = default.Utility }
		else DEFAULT_PRESET
	for _, preset in ipairs(presets) do
		if type(preset) == "table" then
			for slot, key in pairs(base) do
				if preset[slot] ~= nil and preset[slot] ~= key then
					return true
				end
			end
		end
	end
	return false
end

local function beginnerDef(data: Types.PlayerData): { [string]: any }?
	local q = data.Quests
	local beginner = type(q) == "table" and q.Beginner or nil
	local step = if type(beginner) == "table" then math.floor(num(beginner.Step, 1)) else 1
	return Q.Beginner[step]
end

-- Zustands-Schritte nachziehen; true = Fortschritt geändert
local function refreshBeginnerState(p: Player, data: Types.PlayerData): boolean
	local def = beginnerDef(data)
	if not def then
		return false
	end
	local beginner = tableField(tableField(data, "Quests"), "Beginner")
	local value: number? = nil
	if def.Kind == "Level" then
		value = math.floor(num(data.Level, 1))
	elseif def.Kind == "NewWeapon" then
		value = if ownsNewWeapon(data) then 1 else 0
	elseif def.Kind == "LoadoutEdit" then
		value = if editedLoadout(data) then 1 else 0
	end
	if value == nil then
		return false
	end
	local newP = math.min(def.Goal, math.max(num(beginner.P, 0), value))
	if newP ~= beginner.P then
		local wasDone = num(beginner.P, 0) >= def.Goal
		beginner.P = newP
		if newP >= def.Goal and not wasDone then
			notify(p, "prog.questDone", { questText(p, def.Id, def.Goal) }, "Success")
		end
		return true
	end
	return false
end

-- ---------------------------------------------------------------------
-- 3) TRACK (B16.3) – nur serverseitig, nie yielden (außer MatchService.Info-Lesen, kein Yield)
-- ---------------------------------------------------------------------
local function advance(p: Player, q: Quest, amount: number): boolean
	if q.Claimed or q.P >= q.Goal then
		return false
	end
	q.P = math.min(q.Goal, q.P + amount)
	if q.P >= q.Goal then
		notify(p, "prog.questDone", { questText(p, q.Id, q.Goal) }, "Success")
	end
	return true
end

function RewardService.Track(p: Player, kind: string, amount: number, ctx: { [string]: any }?)
	if type(kind) ~= "string" or #kind > 32 then
		return
	end
	local n = if finite(amount) then math.clamp(amount, 0, MAX_TRACK) else 0
	local data = dataOf(p)
	if not data then
		return
	end
	local changed = ensureQuests(p, data)
	local q = data.Quests
	local bdef = beginnerDef(data)
	if kind == "Level" or kind == "NewWeapon" or kind == "LoadoutEdit" then
		-- Zustands-Arten: am Spielstand prüfen; "LoadoutEdit" darf WP9 zusätzlich direkt melden
		if refreshBeginnerState(p, data) then
			changed = true
		end
		if kind == "LoadoutEdit" and n > 0 and bdef and bdef.Kind == "LoadoutEdit" then
			local beginner = tableField(q, "Beginner")
			if num(beginner.P, 0) < bdef.Goal then
				beginner.P = math.min(bdef.Goal, num(beginner.P, 0) + n)
				if beginner.P >= bdef.Goal then
					notify(p, "prog.questDone", { questText(p, bdef.Id, bdef.Goal) }, "Success")
				end
				changed = true
			end
		end
		if changed then
			dirty(p, "Quests")
		end
		return
	end
	if n <= 0 then
		if changed then
			dirty(p, "Quests")
		end
		return
	end
	local all: { Quest } = {}
	for _, entry in ipairs(q.Daily) do
		table.insert(all, entry)
	end
	for _, entry in ipairs(q.Weekly) do
		table.insert(all, entry)
	end
	local full = if needsCtx(kind, all, bdef) then resolveCtx(p, ctx) else (ctx or {})
	for _, entry in ipairs(all) do
		if entry.Kind == kind and filterOk(questDefs[entry.Id], full) then
			if advance(p, entry, n) then
				changed = true
			end
		elseif
			kind == "Match"
			and entry.Kind == "DifferentMaps"
			and type(full.Map) == "string"
			and not entry.Claimed
		then
			-- Wochenquest "verschiedene Maps": Set der gespielten Maps (Text-Schlüssel)
			local maps = entry.Maps
			if type(maps) ~= "table" then
				maps = {}
				entry.Maps = maps
			end
			if not maps[full.Map] then
				local count = 0
				for _ in pairs(maps) do
					count += 1
				end
				if count < 32 then
					maps[full.Map] = true
					if advance(p, entry, 1) then
						changed = true
					end
				end
			end
		end
	end
	if bdef and bdef.Kind == kind and filterOk(bdef, full) then
		local beginner = tableField(q, "Beginner")
		if num(beginner.P, 0) < bdef.Goal then
			beginner.P = math.min(bdef.Goal, num(beginner.P, 0) + n)
			if beginner.P >= bdef.Goal then
				notify(p, "prog.questDone", { questText(p, bdef.Id, bdef.Goal) }, "Success")
			end
			changed = true
		end
	end
	if changed then
		dirty(p, "Quests")
	end
end

-- Live aus dem Kampf: Pop-Arten (Quests zählen auch gegen Bots, B10.3)
local function onElimination(victim: any, killer: any, info: any)
	if type(victim) ~= "table" or type(killer) ~= "table" or killer == victim or type(info) ~= "table" then
		return
	end
	-- Opfer-Spieler: FFA-Serie endet
	local victimPlayer = asPlayer(victim.Player)
	if victim.Kind == "Player" and victimPlayer then
		ffaStreak[victimPlayer] = nil
	end
	local p = asPlayer(killer.Player)
	if killer.Kind ~= "Player" or not p or victim.Kind == "Dummy" then
		return
	end
	local ctxName = killer.Ctx
	if type(ctxName) ~= "string" or string.sub(ctxName, 1, 1) ~= "M" then
		return
	end
	local mode, map = matchInfoOf(ctxName)
	local ctx = { Mode = mode, Map = map, Pvp = victim.Kind == "Player" }
	local def = Config.Weapon(tostring(info.WeaponKey))
	local slot = def and def.Slot
	RewardService.Track(p, "Elim", 1, ctx)
	if info.Head == true then
		RewardService.Track(p, "HeadElim", 1, ctx)
	end
	if info.Melee == true or slot == "Melee" then
		RewardService.Track(p, "MeleeElim", 1, ctx)
	end
	if slot == "Secondary" then
		RewardService.Track(p, "SecondaryElim", 1, ctx)
	end
	if smgShotgun[tostring(info.WeaponKey)] then
		RewardService.Track(p, "SmgShotgunElim", 1, ctx)
	end
	if info.KillerSliding == true then
		RewardService.Track(p, "SlideElim", 1, ctx)
	end
	if info.Splash == true then
		RewardService.Track(p, "SplashElim", 1, ctx)
	end
	if mode == "FFA" then
		local streak = ffaStreak[p]
		if not streak or streak.Match ~= ctxName then
			streak = { Match = ctxName, N = 0 }
			ffaStreak[p] = streak
		end
		streak.N += 1
		if streak.N == 3 then
			RewardService.Track(p, "FfaStreak3", 1, ctx)
		end
	end
end

-- Anfänger-Schritt 1: Puppe im Schießstand treffen
local function onDamage(attacker: any, victim: any, dealt: number, _info: any)
	if
		type(attacker) == "table"
		and type(victim) == "table"
		and victim.Kind == "Dummy"
		and attacker.Kind == "Player"
	then
		local p = asPlayer(attacker.Player)
		if p and finite(dealt) and dealt > 0 then
			RewardService.Track(p, "DummyHit", 1)
		end
	end
end

-- ---------------------------------------------------------------------
-- 4) QUESTS EINLÖSEN / TAUSCHEN (C9)
-- ---------------------------------------------------------------------
local function findQuest(list: { Quest }, id: string): Quest?
	for _, q in ipairs(list) do
		if q.Id == id then
			return q
		end
	end
	return nil
end

local function allClaimed(list: { Quest }): boolean
	if #list == 0 then
		return false
	end
	for _, q in ipairs(list) do
		if not q.Claimed then
			return false
		end
	end
	return true
end

local function handleClaimQuest(p: Player, arg: any): Reply
	if type(arg) ~= "string" or #arg > 32 then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	if ensureQuests(p, data) then
		dirty(p, "Quests")
	end
	local q = data.Quests

	-- Tagesquest
	local daily = findQuest(q.Daily, arg)
	if daily then
		if daily.Claimed then
			return fail(p, "prog.questClaimed")
		elseif daily.P < daily.Goal then
			return fail(p, "prog.questNotDone")
		end
		local reward = Q.DailyRewards[daily.Tier or "Easy"] or Q.DailyRewards.Easy
		daily.Claimed = true
		if not grant(p, { Coins = reward.Coins }, "Quest_" .. daily.Id) then
			daily.Claimed = false
			return fail(p, "core.error")
		end
		try("ProgressionService", "AddPassXp", p, reward.PassXp, "Quest")
		local shown = { Coins = reward.Coins, PassXp = reward.PassXp }
		if allClaimed(q.Daily) and not q.DailyBonus then
			q.DailyBonus = true
			notify(p, "prog.dailyBonus", nil, "Event")
			dirty(p, "Daily")
		end
		dirty(p, "Quests")
		return { Ok = true, Reward = shown, Message = t(p, "prog.rewardGot", describe(p, shown)) }
	end

	-- Wochenquest
	local weekly = findQuest(q.Weekly, arg)
	if weekly then
		if weekly.Claimed then
			return fail(p, "prog.questClaimed")
		elseif weekly.P < weekly.Goal then
			return fail(p, "prog.questNotDone")
		end
		local reward = Q.WeeklyReward
		weekly.Claimed = true
		if not grant(p, { Coins = reward.Coins }, "Quest_" .. weekly.Id) then
			weekly.Claimed = false
			return fail(p, "core.error")
		end
		try("ProgressionService", "AddPassXp", p, reward.PassXp, "Quest")
		local shown: { [string]: any } = { Coins = reward.Coins, PassXp = reward.PassXp }
		if allClaimed(q.Weekly) and not q.WeeklyChest then
			q.WeeklyChest = true
			local chest = toGrant(Q.WeeklyChest)
			if grant(p, chest, "WeeklyChest") then
				notify(p, "prog.weeklyChest", { describe(p, chest) }, "Event")
			end
		end
		dirty(p, "Quests")
		return { Ok = true, Reward = shown, Message = t(p, "prog.rewardGot", describe(p, shown)) }
	end

	-- Anfänger-Kette (nur der aktuelle Schritt)
	local bdef = beginnerDef(data)
	if bdef and bdef.Id == arg then
		local beginner = tableField(q, "Beginner")
		refreshBeginnerState(p, data)
		if num(beginner.P, 0) < bdef.Goal then
			return fail(p, "prog.questNotDone")
		end
		local step = math.floor(num(beginner.Step, 1))
		beginner.Step = step + 1
		beginner.P = 0
		if not grant(p, { Coins = bdef.Coins }, "Beginner" .. step) then
			beginner.Step = step
			beginner.P = bdef.Goal
			return fail(p, "core.error")
		end
		local shown: { [string]: any } = { Coins = bdef.Coins }
		if finite(bdef.FreePick) and bdef.FreePick > 0 then
			data.FreeWeaponPicks = math.max(0, num(data.FreeWeaponPicks, 0)) + bdef.FreePick
			shown.FreePick = bdef.FreePick
			dirty(p, "FreeWeaponPicks", "Weapons")
			notify(p, "prog.freePick", nil, "Event")
		end
		try("MetricsService", "Progression", p, "Beginner", "Complete", step)
		refreshBeginnerState(p, data)
		dirty(p, "Quests")
		return { Ok = true, Reward = shown, Message = t(p, "prog.rewardGot", describe(p, shown)) }
	end
	return fail(p, "prog.questUnknown")
end

local function handleRerollQuest(p: Player, arg: any): Reply
	if not finite(arg) or arg % 1 ~= 0 then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	ensureQuests(p, data)
	local q = data.Quests
	local index = math.floor(arg)
	local current: Quest? = q.Daily[index]
	if not current then
		return fail(p, "core.invalid")
	end
	if current.Claimed or current.P >= current.Goal then
		return fail(p, "prog.rerollDone")
	end
	-- neue Quest derselben Stufe, die heute noch nicht in der Liste steht
	local inList: { [string]: boolean } = {}
	for _, entry in ipairs(q.Daily) do
		inList[entry.Id] = true
	end
	local candidates: { { [string]: any } } = {}
	for _, def in ipairs(Q.Daily) do
		if not inList[def.Id] and def.Tier == current.Tier then
			table.insert(candidates, def)
		end
	end
	if #candidates == 0 then
		for _, def in ipairs(Q.Daily) do
			if not inList[def.Id] then
				table.insert(candidates, def)
			end
		end
	end
	if #candidates == 0 then
		return fail(p, "prog.rerollNone")
	end
	local free = q.Rerolls > 0
	if free then
		q.Rerolls -= 1
	else
		local okSpend, spent = try("ShopService", "Spend", p, "Coins", Q.RerollCoins, "QuestReroll")
		if not okSpend or spent ~= true then
			return fail(p, "prog.rerollNoCoins", Q.RerollCoins)
		end
	end
	local def = candidates[Random.new():NextInteger(1, #candidates)]
	local replacement = newQuest(def)
	replacement.Tier = current.Tier or def.Tier
	q.Daily[index] = replacement
	dirty(p, "Quests")
	return { Ok = true, Message = t(p, "prog.rerolled", questText(p, def.Id, def.Goal)) }
end

-- ---------------------------------------------------------------------
-- 5) LOGIN-KALENDER (B16.4)
-- ---------------------------------------------------------------------
local function ownsCosmetic(p: Player, id: string): boolean
	local ok, owns = try("ShopService", "OwnsCosmetic", p, id)
	return ok and owns == true
end

local function handleClaimLogin(p: Player, _arg: any): Reply
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	local login = tableField(data, "Login")
	local cfg = P.Login
	local before = {
		LastDay = login.LastDay,
		CalDay = login.CalDay,
		Streak = login.Streak,
		Best = login.Best,
		FreezeWeek = login.FreezeWeek,
	}
	local result =
		ProgressMath.LoginStep(login :: any, Util.UtcDay(), Util.IsoWeek(), #cfg.Calendar, num(cfg.FreezesPerWeek, 1))
	if not result then
		return fail(p, "prog.loginDone")
	end
	local reward = cfg.Calendar[result.CalDay]
	local g = toGrant(reward)
	local shown: { [string]: any } = toGrant(reward)
	local items: { string } = {}
	if result.NewCycle and not login.CatGiven and type(cfg.FirstCycleCharm) == "string" then
		table.insert(items, cfg.FirstCycleCharm)
	end
	if
		result.Streak >= num(cfg.OnFireDays, 7)
		and type(cfg.OnFireTitle) == "string"
		and not ownsCosmetic(p, cfg.OnFireTitle)
	then
		table.insert(items, cfg.OnFireTitle)
	end
	if #items > 0 then
		g.Cosmetics = items
		shown.Cosmetics = items
	end
	if not grant(p, g, "Login" .. result.CalDay) then
		-- zurückrollen, damit der Spieler es nochmal versuchen kann
		for key, value in pairs(before) do
			login[key] = value
		end
		return fail(p, "core.error")
	end
	if result.NewCycle and table.find(items, cfg.FirstCycleCharm) then
		login.CatGiven = true
	end
	try("ProgressionService", "AddPassXp", p, num(cfg.PassXp, 0), "Login")
	shown.PassXp = num(cfg.PassXp, 0)
	if result.UsedFreeze then
		notify(p, "prog.loginFreeze", nil, "Info")
	end
	dirty(p, "Login")
	return {
		Ok = true,
		Reward = shown,
		Day = result.CalDay,
		Streak = result.Streak,
		Message = t(p, "prog.loginGot", result.CalDay, describe(p, shown)),
	}
end

-- ---------------------------------------------------------------------
-- 6) GLÜCKSRAD (B16.4) – nur Gratis-Drehs, Quoten = Config (Summe 100 %)
-- ---------------------------------------------------------------------
local function wheelDaily(data: Types.PlayerData): { [string]: any }
	local daily = tableField(data, "Daily")
	local today = Util.UtcDay()
	if daily.WheelDay ~= today then
		daily.WheelDay = today
		daily.WheelSpins = 0
	end
	return daily
end

local function spinsLeft(p: Player, data: Types.PlayerData): number
	local daily = wheelDaily(data)
	local w = P.Wheel
	local total = num(w.FreeSpins, 1)
	if hasPass(p, "VIP") then
		total += num(w.VipSpins, 1)
	end
	local q = data.Quests
	if type(q) == "table" and q.DailyBonus == true and q.Day == Util.UtcDay() then
		total += num(w.AllDailiesSpins, 1)
	end
	return math.max(0, total - math.max(0, num(daily.WheelSpins, 0)))
end

local function handleSpinWheel(p: Player, _arg: any): Reply
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	ensureQuests(p, data)
	if spinsLeft(p, data) <= 0 then
		return fail(p, "prog.wheelNone")
	end
	local prizes = P.Wheel.Prizes
	local prize = Util.WeightedPick(prizes, function(entry: any): number
		return num(entry.W, 0)
	end, Random.new())
	if type(prize) ~= "table" then
		return fail(p, "core.error")
	end
	local daily = wheelDaily(data)
	daily.WheelSpins = math.max(0, num(daily.WheelSpins, 0)) + 1
	local g = toGrant(prize)
	if not grant(p, g, "Wheel") then
		daily.WheelSpins -= 1
		return fail(p, "core.error")
	end
	dirty(p, "Daily")
	return {
		Ok = true,
		Reward = g,
		Index = table.find(prizes, prize) or 1,
		Message = t(p, "prog.rewardGot", describe(p, g)),
	}
end

-- ---------------------------------------------------------------------
-- 7) SPIELZEIT-GESCHENKE (pro UTC-Tag über alle Besuche, MH-Fix §14.1 #7)
-- ---------------------------------------------------------------------
local function playDaily(data: Types.PlayerData): { [string]: any }
	local daily = tableField(data, "Daily")
	local today = Util.UtcDay()
	if daily.PlayDay ~= today then
		daily.PlayDay = today
		daily.PlaySec = 0
		daily.Gifts = {}
	end
	tableField(daily, "Gifts")
	daily.PlaySec = math.max(0, num(daily.PlaySec, 0))
	return daily
end

local function handleClaimGift(p: Player, arg: any): Reply
	local cfg = P.Playtime
	if not finite(arg) or arg % 1 ~= 0 or arg < 1 or arg > #cfg.Minutes then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	local index = math.floor(arg)
	local daily = playDaily(data)
	local key = tostring(index)
	if daily.Gifts[key] then
		return fail(p, "prog.giftClaimed")
	end
	local needed = cfg.Minutes[index] * 60
	if daily.PlaySec < needed then
		return fail(p, "prog.giftWait", Util.FormatTime(needed - daily.PlaySec))
	end
	local g = toGrant(cfg.Rewards[index])
	daily.Gifts[key] = true
	if not grant(p, g, "Playtime" .. index) then
		daily.Gifts[key] = nil
		return fail(p, "core.error")
	end
	dirty(p, "Daily")
	return { Ok = true, Reward = g, Message = t(p, "prog.rewardGot", describe(p, g)) }
end

local function playTick(dt: number)
	local step = math.clamp(dt, 0, PLAY_TICK_MAX)
	local now = os.clock()
	for _, p in ipairs(Players:GetPlayers()) do
		local okReady, ready = try("PlayerStateService", "IsReady", p)
		local data = if okReady and ready == true then dataOf(p) else nil
		if data then
			local daily = playDaily(data)
			local before = daily.PlaySec
			daily.PlaySec = before + step
			-- Schwelle überschritten -> sofort melden, sonst nur alle 30 s
			local crossed = false
			for i, minutes in ipairs(P.Playtime.Minutes) do
				local limit = minutes * 60
				if before < limit and daily.PlaySec >= limit and not daily.Gifts[tostring(i)] then
					crossed = true
					notify(p, "prog.giftReady", nil, "Success")
				end
			end
			if crossed or now - (playStateAt[p] or -math.huge) >= PLAY_STATE_EVERY then
				playStateAt[p] = now
				dirty(p, "Daily")
			end
			if refreshBeginnerState(p, data) then
				dirty(p, "Quests")
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- 8) ERSTER SIEG DES TAGES + CODES
-- ---------------------------------------------------------------------
function RewardService.FirstWinToday(p: Player): boolean
	local data = dataOf(p)
	if not data then
		return false
	end
	local daily = tableField(data, "Daily")
	local today = Util.UtcDay()
	if daily.FirstWinDay == today then
		return false
	end
	daily.FirstWinDay = today
	dirty(p, "Daily")
	return true
end

local function handleRedeemCode(p: Player, arg: any): Reply
	if type(arg) ~= "string" or #arg == 0 or #arg > MAX_CODE_LEN + 8 then
		return fail(p, "core.invalid")
	end
	local code = string.upper((string.gsub(arg, "%s", "")))
	if #code == 0 or #code > MAX_CODE_LEN or string.find(code, "[^%w_%-]") then
		return fail(p, "prog.codeInvalid")
	end
	local def = P.Codes[code]
	if type(def) ~= "table" then
		return fail(p, "prog.codeInvalid")
	end
	if def.Expires ~= nil then
		local expires = ProgressMath.ParseIsoUtc(def.Expires)
		if expires and os.time() >= expires then
			return fail(p, "prog.codeExpired")
		end
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	local codes = tableField(data, "Codes")
	if codes[code] ~= nil then
		return fail(p, "prog.codeUsed")
	end
	local g = toGrant(def.Grant)
	codes[code] = os.time()
	if not grant(p, g, "Code_" .. code) then
		codes[code] = nil
		return fail(p, "core.error")
	end
	try("MetricsService", "Custom", p, "CodeRedeemed", 1, { Code = code })
	return { Ok = true, Reward = g, Message = t(p, "prog.codeOk", describe(p, g)) }
end

-- ---------------------------------------------------------------------
-- 9) STATE + BEITRITT
-- ---------------------------------------------------------------------
local function provideAll()
	try("PlayerStateService", "Provide", "Quests", function(p: Player): any
		local data = dataOf(p)
		if not data then
			return false
		end
		ensureQuests(p, data)
		local q = data.Quests
		local beginner = q.Beginner
		local bdef = beginnerDef(data)
		return {
			Daily = q.Daily,
			Weekly = q.Weekly,
			Rerolls = q.Rerolls,
			RerollCoins = Q.RerollCoins,
			DailyBonus = q.DailyBonus == true,
			WeeklyChest = q.WeeklyChest == true,
			Beginner = {
				Step = beginner.Step,
				Total = #Q.Beginner,
				P = num(beginner.P, 0),
				Id = bdef and bdef.Id or "",
				Goal = bdef and bdef.Goal or 0,
				Coins = bdef and bdef.Coins or 0,
				FreePick = bdef and bdef.FreePick or 0,
				Done = bdef == nil,
			},
			DayEndsAt = serverIn(secondsToNextDay()),
			WeekEndsAt = serverIn(secondsToNextWeek()),
		}
	end)
	try("PlayerStateService", "Provide", "Login", function(p: Player): any
		local data = dataOf(p)
		if not data then
			return false
		end
		local login = tableField(data, "Login")
		local today = Util.UtcDay()
		local length = #P.Login.Calendar
		local calDay = math.clamp(math.floor(num(login.CalDay, 0)), 0, length)
		return {
			CalDay = calDay,
			NextDay = (calDay % length) + 1,
			Streak = num(login.Streak, 0),
			Best = num(login.Best, 0),
			CanClaim = login.LastDay ~= today,
			CatGiven = login.CatGiven == true,
		}
	end)
	try("PlayerStateService", "Provide", "Daily", function(p: Player): any
		local data = dataOf(p)
		if not data then
			return false
		end
		local daily = playDaily(data)
		local today = Util.UtcDay()
		return {
			FirstWinDone = daily.FirstWinDay == today,
			SpinsLeft = spinsLeft(p, data),
			PlaySec = daily.PlaySec,
			PlayAt = workspace:GetServerTimeNow(), -- Client zählt ab hier selbst weiter
			Gifts = daily.Gifts,
			BotCoins = if daily.BotCoinsDay == today then num(daily.BotCoins, 0) else 0,
			BotCap = P.Coins.BotDailyCap,
			DayEndsAt = serverIn(secondsToNextDay()),
		}
	end)
end

local function onReady(p: Player)
	local data = dataOf(p)
	if not data then
		return
	end
	ensureQuests(p, data)
	refreshBeginnerState(p, data)
	local login = tableField(data, "Login")
	if login.LastDay ~= Util.UtcDay() then
		task.delay(4, function()
			if isPlayer(p) then
				notify(p, "prog.loginReady", nil, "Event")
			end
		end)
	end
	dirty(p, "Quests", "Login", "Daily")
end

-- Tageswechsel (auch für Spieler, die über Mitternacht bleiben) + Debug-SkipDay
local lastDay = -1
local lastWeek = -1
local function dayTick()
	local today, week = Util.UtcDay(), Util.IsoWeek()
	local rolled = today ~= lastDay or week ~= lastWeek
	lastDay, lastWeek = today, week
	if not rolled then
		return
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local data = dataOf(p)
		if data then
			ensureQuests(p, data)
			playDaily(data)
			wheelDaily(data)
			dirty(p, "Quests", "Login", "Daily")
		end
	end
end

local function onPlayerRemoving(p: Player)
	playStateAt[p] = nil
	ffaStreak[p] = nil
end

-- ---------------------------------------------------------------------
-- 10) INIT / START
-- ---------------------------------------------------------------------
function RewardService.Init(services: any)
	Services = services
end

function RewardService.Start()
	provideAll()
	try("PlayerStateService", "Handle", "ClaimQuest", handleClaimQuest)
	try("PlayerStateService", "Handle", "RerollQuest", handleRerollQuest)
	try("PlayerStateService", "Handle", "ClaimLogin", handleClaimLogin, { Rate = 1, Per = 1 })
	try("PlayerStateService", "Handle", "SpinWheel", handleSpinWheel, { Rate = 1, Per = 1 })
	try("PlayerStateService", "Handle", "ClaimGift", handleClaimGift, { Rate = 1, Per = 1 })
	try("PlayerStateService", "Handle", "RedeemCode", handleRedeemCode, { Rate = 5, Per = 60 })
	try("PlayerStateService", "OnReady", onReady)
	try("CombatService", "OnElimination", onElimination)
	try("CombatService", "OnDamage", onDamage)
	lastDay, lastWeek = Util.UtcDay(), Util.IsoWeek()
	Scheduler.Every("RewardPlaytime", 1, playTick)
	Scheduler.Every("RewardDay", 0.5, dayTick)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return RewardService
