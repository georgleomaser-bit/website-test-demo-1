-- =====================================================================
--  AKYTEX TYCOON – Belohnungen: Quests (Tages/Wochen/Starter-Linie/Aufhol-Quest), Login-Kalender, Skyline-Pass,
--  Codes, Tutorial-Belohnungen, Rückkehr, Liga-Belohnung der Vorwoche (Server/Services/RewardService)
--  Besitzer: WP9 (Fortschritt, Tutorial, Sozial, Bestenlisten). Vertrag: DESIGN.md §C5.8, §C9 (Reward*), §C10 (State
--  "Quests", "Login", "Season"), §B9.7, §B9.9, §B11.1 (Liga-Belohnung beim ersten Join der Woche), §B2 (Funnel 17/18).
--  Muster: CC-RewardService (REUSE §1.3 PATTERN) – OHNE Glücksrad. Freie Zufälle (Quest-Auswahl) sind deterministisch
--  je Spieler/Tag und nie mit Robux/CR verknüpft. Kein bezahlter Serien-Retter.
--
--  Öffentliche API (§C5.8):
--    RewardService.Track(p, kind, amount, ctx?)          Quest-Fortschritt (nur Server, andere WPs per pcall)
--    RewardService.GrantSeasonXp(p, amount, reason)      Saison-XP (Deckel je Grund laut Config.Season)
--    RewardService.SeasonPremium(p): boolean             RewardService.GrantSeasonPremium(p): boolean
--    RewardService.AddSeasonTiers(p, n): number          gekaufte Stufen (zahlen nur Kosmetik, REUSE §7 #8)
--  Ergänzungen: RewardService.CurrentSeason(): { Id, Key, StartsAt, EndsAt, Tiers, TierXp, Rolling } ·
--    RewardService._Test = { Core, Forward, InternalKinds }
--  Track-Arten (Config.Progression.QuestKinds) und ihre Aufrufer: Collect/BuildFloor/RoomLevel/Hire/Efficiency/
--    Transfer/HelpBuild (TowerService) · Drive (VehicleService) · VisitTower (PlotService) · Pickup/BearOrbs
--    (EventService) · GiveRespekt (CommunityService) · TradeProtected/TradeProfit/PositiveDay/ReadNews/NewSector/
--    HoldThroughBell/EarningsTrade/Lesson/Bell (ProgressionService).
--  Request-Handler: RewardLogin, RewardQuest, RewardReroll, RewardSeason, RewardCode, RewardTutorial.
--  Effekt: QuestDone. Alle CR-Belohnungen über ShopService (Credit/Grant), alles oder nichts.
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Types = require(Shared:WaitForChild("Types"))
local Lang = require(Shared:WaitForChild("Lang"))
local Format = require(Shared:WaitForChild("Format"))
local ProgressMath = require(Shared:WaitForChild("ProgressMath"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local RewardService = {}
local Services: any = nil

type Reply = Types.Reply
type Data = { [string]: any }

local PCFG: any = Config.Progression
local SCFG: any = Config.Season
local RCFG: any = Config.Rewards
local QCFG: any = PCFG.Quests

local LOG_GAP = 10
local MAX_TRACK = 1000000
local MAX_SEEN = 32
local DAY_SECONDS = 86400
local LEAGUE_CHECK_EVERY = 60
local PLAY_TICK = math.max(10, math.floor(tonumber(RCFG.PlaytimeTick) or 60))

-- Arten, deren Erfolgs-Zähler ProgressionService.NoteStat führt (weitergereicht aus Track)
local FORWARD: { [string]: boolean } = {
	Collect = true,
	RoomLevel = true,
	Hire = true,
	Transfer = true,
	Drive = true,
	VisitTower = true,
	GiveRespekt = true,
	HelpBuild = true,
	Pickup = true,
	BearOrbs = true,
	Bell = true,
}
-- Arten, die WP9 selbst meldet (SelfTest "jede Quest-Art hat einen Tracker")
local INTERNAL_KINDS: { [string]: string } = {
	TradeProtected = "ProgressionService",
	TradeProfit = "ProgressionService",
	PositiveDay = "ProgressionService",
	ReadNews = "ProgressionService",
	NewSector = "ProgressionService",
	HoldThroughBell = "ProgressionService",
	EarningsTrade = "ProgressionService",
	Lesson = "ProgressionService",
	Bell = "ProgressionService",
	GiveRespekt = "CommunityService",
}

-- Pro-Spieler-Tabellen (alle bei PlayerRemoving geleert)
local readyClock: { [Player]: number } = {}
local playAcc: { [Player]: number } = {}
local leagueCheckedAt: { [Player]: number } = {}
local lastLogAt: { [string]: number } = {}

-- ---------------------------------------------------------------------
-- 1) HELFER
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

local function isPlayer(p: any): boolean
	return typeof(p) == "Instance" and p:IsA("Player") and p.Parent == Players
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

local function funnel(p: Player, step: number)
	call("MetricsService", "Funnel", p, step, PCFG.Tutorial.FunnelNames[step] or ("Step" .. step))
end

local function credits(n: number, lang: Types.Lang): string
	local ok, text = pcall(Format.Credits, n, lang)
	return if ok then text else tostring(math.floor(n))
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

local function today(): number
	return Util.UtcDay()
end

local function tableField(parent: Data, key: string): Data
	local t = parent[key]
	if type(t) ~= "table" then
		t = {}
		parent[key] = t
	end
	return t
end

-- ISO-UTC -> Unix-Sekunden (nil bei Fehler)
local isoCache: { [string]: number } = {}
local function isoToUnix(iso: any): number?
	if type(iso) ~= "string" then
		return nil
	end
	local cached = isoCache[iso]
	if cached then
		return cached
	end
	local ok, value = pcall(function()
		return DateTime.fromIsoDate(iso).UnixTimestamp
	end)
	if ok and finite(value) then
		isoCache[iso] = value
		return value
	end
	return nil
end

local function steadyIncome(p: Player): number
	local ok, info = call("TowerService", "Income", p)
	if ok and type(info) == "table" and finite(info.Steady) then
		return math.max(0, info.Steady)
	end
	return 0
end

-- einkommens-skalierte CR (Minuten Dauer-Einkommen ohne Zeitlich, mindestens min)
local function incomeCredits(p: Player, minutes: number, min: number): number
	return ProgressMath.Clamp(math.max(num(min, 0), steadyIncome(p) * num(minutes, 0) * 60))
end

-- Anzeigename eines Belohnungs-Teils aus den Config-Tabellen der Besitzer-WPs
local function itemName(kind: string, key: string, lang: Types.Lang): string
	local function pick(entry: any): string?
		if type(entry) == "table" and type(entry.Name) == "table" then
			return Lang.Pick(lang, entry.Name)
		end
		return nil
	end
	local function find(list: any): any
		if type(list) == "table" then
			for _, entry in ipairs(list) do
				if type(entry) == "table" and entry.Key == key then
					return entry
				end
			end
		end
		return nil
	end
	if kind == "Decor" then
		local decor = Config.Decor
		return pick(decor and decor.ByKey and decor.ByKey[key]) or key
	elseif kind == "Car" then
		return pick(find(Config.Vehicles and Config.Vehicles.Cars)) or key
	elseif kind == "Watch" then
		local life = Config.Lifestyle
		return pick(find(life and life.Watches)) or key
	elseif kind == "Accessory" then
		local life = Config.Lifestyle
		return pick(find(life and life.Accessories)) or key
	elseif kind == "Title" then
		return pick(PCFG.TitleByKey[key]) or key
	end
	-- Kosmetik: Fassaden, Neon, Lacke
	local tower = Config.Tower
	return pick(find(tower and tower.Skins))
		or pick(find(tower and tower.Neon))
		or pick(find(Config.Vehicles and Config.Vehicles.Paints))
		or key
end

-- Belohnung -> Grant (Turm-Seite), Saison-XP, Titel, Text
local function buildReward(p: Player, reward: any, earnedOnly: boolean?): (Types.Grant, number, string?, { string })
	local grant: Types.Grant = {}
	local parts: { string } = {}
	local lang = langOf(p)
	local seasonXp = 0
	local title: string? = nil
	if type(reward) ~= "table" then
		return grant, 0, nil, parts
	end
	local allowIncome = earnedOnly ~= false
	if allowIncome and type(reward.Credits) == "table" then
		local amount = incomeCredits(p, reward.Credits.Minutes, reward.Credits.Min)
		if amount > 0 then
			grant.Credits = amount
			table.insert(parts, Lang.T(lang, "prog.rw.credits", credits(amount, lang)))
		end
	end
	if type(reward.Decor) == "table" then
		local decor: { [string]: number } = {}
		for key, n in pairs(reward.Decor) do
			if type(key) == "string" and isInt(n) and n > 0 then
				decor[key] = n
				table.insert(parts, Lang.T(lang, "prog.rw.decor", itemName("Decor", key, lang)))
			end
		end
		if next(decor) then
			grant.Decor = decor
		end
	end
	for field, kind in pairs({ Cosmetics = "Cosmetic", Watches = "Watch", Cars = "Car", Accessories = "Accessory" }) do
		local list = reward[field]
		if type(list) == "table" and #list > 0 then
			local copy: { string } = {}
			for _, key in ipairs(list) do
				if type(key) == "string" then
					table.insert(copy, key)
					table.insert(parts, Lang.T(lang, "prog.rw." .. string.lower(kind), itemName(kind, key, lang)))
				end
			end
			(grant :: any)[field] = copy
		end
	end
	if allowIncome and isInt(reward.BoostX2) and reward.BoostX2 > 0 then
		grant.BoostX2 = reward.BoostX2
		local ok, text = pcall(Format.Duration, reward.BoostX2, lang)
		table.insert(parts, Lang.T(lang, "prog.rw.boost", if ok then text else tostring(reward.BoostX2)))
	end
	if allowIncome and isInt(reward.InstantTokens) and reward.InstantTokens > 0 then
		grant.InstantTokens = reward.InstantTokens
		table.insert(parts, Lang.T(lang, "prog.rw.instant", reward.InstantTokens))
	end
	if isInt(reward.SeasonXp) and reward.SeasonXp > 0 then
		seasonXp = reward.SeasonXp
		table.insert(parts, Lang.T(lang, "prog.rw.seasonXp", seasonXp))
	end
	if type(reward.Title) == "string" and reward.Title ~= "" then
		title = reward.Title
		table.insert(parts, Lang.T(lang, "prog.rw.title", itemName("Title", reward.Title, lang)))
	end
	return grant, seasonXp, title, parts
end

local function grantEmpty(grant: Types.Grant): boolean
	return next(grant :: any) == nil
end

-- alles oder nichts über ShopService.Grant (nur Turm-Seite)
local function applyGrant(p: Player, grant: Types.Grant, reason: string): boolean
	if grantEmpty(grant) then
		return true
	end
	local ok, granted = call("ShopService", "Grant", p, grant, reason)
	return ok and granted == true
end

-- ---------------------------------------------------------------------
-- 2) KERN (rein; SelfTests nutzen dieselben Funktionen)
-- ---------------------------------------------------------------------
local Core = {}

local function isTradeKind(kind: string?): boolean
	local def = kind and PCFG.QuestKindByKey[kind]
	return def ~= nil and (def.Cat == "Trade" or def.Cat == "Academy")
end
Core.IsTradeKind = isTradeKind

local function newQuest(def: any): Data
	return { Id = def.Id, P = 0, Done = false, Claimed = false, Seen = {} }
end

-- 3 Tagesquests deterministisch je Spieler/Tag (mindestens MinTradeDaily Handels-/Akademie-Quests)
function Core.PickDaily(userId: number, day: number): { string }
	local seed = Util.Hash(tostring(userId) .. ":" .. tostring(day))
	local picks = ProgressMath.QuestPick(seed, QCFG.Daily, QCFG.DailyCount)
	local trade = 0
	for _, def in ipairs(picks) do
		if isTradeKind(def.Kind) then
			trade += 1
		end
	end
	if trade < QCFG.MinTradeDaily and #picks > 0 then
		local pool = {}
		for _, def in ipairs(QCFG.Daily) do
			if isTradeKind(def.Kind) and not table.find(picks, def) then
				table.insert(pool, def)
			end
		end
		-- die letzte Nicht-Handels-Quest ersetzen
		for index = #picks, 1, -1 do
			if not isTradeKind(picks[index].Kind) then
				local extra = ProgressMath.QuestPick(seed + 7, pool, 1)[1]
				if extra then
					picks[index] = extra
				end
				break
			end
		end
	end
	local ids = {}
	for _, def in ipairs(picks) do
		table.insert(ids, def.Id)
	end
	return ids
end

function Core.PickWeekly(userId: number, week: number): { string }
	local seed = Util.Hash(tostring(userId) .. ":w" .. tostring(week))
	local ids = {}
	for _, def in ipairs(ProgressMath.QuestPick(seed, QCFG.Weekly, QCFG.WeeklyCount)) do
		table.insert(ids, def.Id)
	end
	return ids
end

-- Ersatz beim Neuwählen (deterministisch, nicht schon in der Liste, Handels-Garantie bleibt)
function Core.RerollPick(userId: number, day: number, list: { Data }, replaceId: string): string?
	local current: { [string]: boolean } = {}
	local tradeOthers = 0
	for _, q in ipairs(list) do
		current[q.Id] = true
		if q.Id ~= replaceId then
			local def = PCFG.QuestById[q.Id]
			if def and isTradeKind(def.Kind) then
				tradeOthers += 1
			end
		end
	end
	local needTrade = tradeOthers < QCFG.MinTradeDaily
	local pool = {}
	for _, def in ipairs(QCFG.Daily) do
		if not current[def.Id] and (not needTrade or isTradeKind(def.Kind)) then
			table.insert(pool, def)
		end
	end
	local seed = Util.Hash(tostring(userId) .. ":" .. tostring(day) .. ":r")
	local pick = ProgressMath.QuestPick(seed, pool, 1)[1]
	return if pick then pick.Id else nil
end

-- Track-Kontext gegen die Vorlage prüfen (Min-Werte)
function Core.FilterOk(def: any, ctx: { [string]: any }?): boolean
	if type(def.Min) == "table" then
		if type(ctx) ~= "table" then
			return false
		end
		for field, min in pairs(def.Min) do
			if not finite(ctx[field]) or ctx[field] < min then
				return false
			end
		end
	end
	return true
end

-- Fortschritt; Rückgabe: (geändert, gerade fertig)
function Core.Advance(q: Data, def: any, amount: number, ctx: { [string]: any }?): (boolean, boolean)
	if q.Done or q.Claimed then
		return false, false
	end
	if not Core.FilterOk(def, ctx) then
		return false, false
	end
	if def.Distinct then
		local value = if type(ctx) == "table" then ctx[def.Distinct] else nil
		if value == nil then
			return false, false
		end
		local key = tostring(value)
		if type(q.Seen) ~= "table" then
			q.Seen = {}
		end
		if q.Seen[key] then
			return false, false
		end
		local count = 0
		for _ in pairs(q.Seen) do
			count += 1
		end
		if count < MAX_SEEN then
			q.Seen[key] = true
		end
		q.P = num(q.P, 0) + 1
	else
		q.P = math.min(num(q.P, 0) + amount, MAX_TRACK)
	end
	if q.P >= def.Goal then
		q.P = def.Goal
		q.Done = true
		return true, true
	end
	return true, false
end

-- Login-Serie für heute berechnen (ohne zu buchen): neue Felder oder nil, wenn heute schon abgeholt
function Core.LoginStep(login: Data, day: number, week: number, club: boolean): Data?
	if login.LastDay == day then
		return nil
	end
	local cfg = RCFG.Login
	local nextState = table.clone(login)
	-- Wochen-Schutz auffüllen (1 je ISO-Woche, Club +1, höchstens FreezeMax gespeichert)
	if nextState.FreezeWeek ~= week then
		local add = cfg.FreezePerWeek + (if club then cfg.FreezeClubBonus else 0)
		nextState.Freeze = math.min(cfg.FreezeMax, num(nextState.Freeze, 0) + add)
		nextState.FreezeWeek = week
	end
	local last = num(nextState.LastDay, 0)
	local gap = day - last
	nextState.UsedFreeze = 0
	-- Serie geht weiter: gestern abgeholt oder die Lücke mit Serien-Schutz überbrückt (sonst neue Serie)
	local continues = last > 0 and gap == 1
	if last > 0 and gap > 1 and gap - 1 <= num(nextState.Freeze, 0) then
		nextState.Freeze -= gap - 1
		nextState.UsedFreeze = gap - 1
		continues = true
	end
	nextState.Streak = if continues then num(nextState.Streak, 0) + 1 else 1
	nextState.Best = math.max(num(nextState.Best, 0), nextState.Streak)
	nextState.Track = math.min(cfg.TrackMax, num(nextState.Track, 0) + 1)
	nextState.LastDay = day
	local dayIdx, cycle = ProgressMath.LoginDay(nextState.Streak)
	nextState.Cycle = cycle
	nextState.DayIdx = dayIdx
	return nextState
end

-- aktive Saison (inkl. Rolling-Folgesaisons)
function Core.SeasonAt(now: number): Data?
	local list = SCFG.Seasons
	if type(list) ~= "table" or #list == 0 then
		return nil
	end
	local first = list[1]
	local firstStart = isoToUnix(first.StartUtc)
	if firstStart and now < firstStart then
		return {
			Id = first.Id,
			Key = first.Key,
			Name = first.Name,
			StartsAt = firstStart,
			EndsAt = isoToUnix(first.EndUtc) or firstStart,
			Def = first,
			Rolling = false,
		}
	end
	-- dieselbe Regel wie Config.Shop.SeasonIdAt (WP10): laufende Saison, sonst die zuletzt begonnene
	local lastIndex = 1
	for i, s in ipairs(list) do
		local start, stop = isoToUnix(s.StartUtc), isoToUnix(s.EndUtc)
		if start and stop and now >= start and now < stop then
			return { Id = s.Id, Key = s.Key, Name = s.Name, StartsAt = start, EndsAt = stop, Def = s, Rolling = false }
		end
		if start and now >= start then
			lastIndex = i
		end
	end
	local last = list[lastIndex]
	local lastEnd = isoToUnix(last.EndUtc)
	if lastIndex < #list then
		-- Lücke bis zur nächsten festen Saison: die vorige gilt weiter, ehrliches Ende = Start der nächsten
		local nextStart = isoToUnix(list[lastIndex + 1].StartUtc)
		return {
			Id = last.Id,
			Key = last.Key,
			Name = last.Name,
			StartsAt = isoToUnix(last.StartUtc) or now,
			EndsAt = nextStart or lastEnd or now,
			Def = last,
			Rolling = false,
		}
	end
	local rolling = SCFG.Rolling
	if not lastEnd or type(rolling) ~= "table" or rolling.Enabled ~= true then
		return nil
	end
	local length = math.max(1, num(rolling.LengthDays, 28)) * DAY_SECONDS
	local k = math.clamp(math.floor((now - lastEnd) / length), 0, SCFG.MaxSeasons)
	local start = lastEnd + k * length
	local id = math.min(last.Id + 1 + k, math.max(last.Id, num(SCFG.MaxSeasons, 999)))
	return {
		Id = id,
		Key = "S" .. tostring(id),
		Name = nil,
		StartsAt = start,
		EndsAt = start + length,
		Def = last,
		Rolling = true,
	}
end

RewardService._Test = { Core = Core, Forward = FORWARD, InternalKinds = INTERNAL_KINDS }

-- ---------------------------------------------------------------------
-- 3) QUEST-ZUSTAND
-- ---------------------------------------------------------------------
local function questsOf(data: Data): Data
	return tableField(data, "Quests")
end

local function sanitizeList(list: any, valid: (string) -> boolean): { Data }
	local out = {}
	if type(list) ~= "table" then
		return out
	end
	for _, q in ipairs(list) do
		if type(q) == "table" and type(q.Id) == "string" and valid(q.Id) then
			q.P = math.max(0, num(q.P, 0))
			q.Done = q.Done == true
			q.Claimed = q.Claimed == true
			if type(q.Seen) ~= "table" then
				q.Seen = {}
			end
			table.insert(out, q)
		end
	end
	return out
end

local dailyIds: { [string]: boolean } = {}
for _, def in ipairs(QCFG.Daily) do
	dailyIds[def.Id] = true
end
local weeklyIds: { [string]: boolean } = {}
for _, def in ipairs(QCFG.Weekly) do
	weeklyIds[def.Id] = true
end

-- Tages-/Wochenwechsel (true = geändert)
local function ensureQuests(p: Player, data: Data): boolean
	local quests = questsOf(data)
	local changed = false
	local day = today()
	if quests.Day ~= day then
		quests.Day = day
		quests.Daily = {}
		for _, id in ipairs(Core.PickDaily(p.UserId, day)) do
			table.insert(quests.Daily, newQuest(PCFG.QuestById[id]))
		end
		quests.Rerolled = false
		changed = true
	else
		quests.Daily = sanitizeList(quests.Daily, function(id)
			return dailyIds[id] == true
		end)
	end
	local week = Util.IsoWeek()
	if quests.Week ~= week then
		quests.Week = week
		quests.Weekly = {}
		for _, id in ipairs(Core.PickWeekly(p.UserId, week)) do
			table.insert(quests.Weekly, newQuest(PCFG.QuestById[id]))
		end
		changed = true
	else
		quests.Weekly = sanitizeList(quests.Weekly, function(id)
			return weeklyIds[id] == true
		end)
	end
	if not isInt(quests.Starter) or quests.Starter < 1 then
		quests.Starter = 1
	end
	quests.Starter = math.min(quests.Starter, #QCFG.StarterLine + 1)
	if type(quests.StarterDone) ~= "table" then
		quests.StarterDone = {}
	end
	quests.StarterP = math.max(0, num(quests.StarterP, 0))
	if type(quests.StarterSeen) ~= "table" then
		quests.StarterSeen = {}
	end
	if quests.Comeback ~= nil and (type(quests.Comeback) ~= "table" or quests.Comeback.Claimed == true) then
		quests.Comeback = nil
	end
	return changed
end

local function questText(p: Player, def: any): string
	local lang = langOf(p)
	local goal = def.Goal
	local goalText = if def.Kind == "Drive"
		then Format.Int(math.floor(goal / 1000 + 0.5), lang)
		else Format.Int(goal, lang)
	if type(def.Text) == "string" then
		return Lang.T(lang, def.Text, goalText)
	end
	return Lang.T(lang, "prog.qk." .. tostring(def.Kind), goalText)
end

local function questDone(p: Player, def: any)
	call("PlayerStateService", "Effect", p, "QuestDone", 1, { Id = def.Id })
	notify(p, "prog.questDone", { questText(p, def) }, "Success")
end

local function starterDef(quests: Data): any
	return QCFG.StarterLine[quests.Starter]
end

-- ---------------------------------------------------------------------
-- 4) ÖFFENTLICHE API
-- ---------------------------------------------------------------------
function RewardService.Track(p: Player, kind: string, amount: number, ctx: { [string]: any }?)
	if not isPlayer(p) or type(kind) ~= "string" or #kind > 40 then
		return
	end
	local value = if finite(amount) then math.clamp(amount, 0, MAX_TRACK) else 1
	if value <= 0 then
		return
	end
	if FORWARD[kind] then
		call("ProgressionService", "NoteStat", p, kind, value, nil)
	end
	if not PCFG.QuestKindByKey[kind] then
		return -- nur Erfolgs-/Protokoll-Art (z. B. CarBuy)
	end
	local data = dataOf(p)
	if not data then
		return
	end
	local changed = ensureQuests(p, data)
	local quests = questsOf(data)
	for _, list in ipairs({ quests.Daily, quests.Weekly }) do
		for _, q in ipairs(list) do
			local def = PCFG.QuestById[q.Id]
			if def and def.Kind == kind then
				local moved, finished = Core.Advance(q, def, value, ctx)
				changed = changed or moved
				if finished then
					questDone(p, def)
				end
			end
		end
	end
	local comeback = quests.Comeback
	if type(comeback) == "table" then
		local def = QCFG.Comeback
		if def.Kind == kind then
			local moved, finished = Core.Advance(comeback, def, value, ctx)
			changed = changed or moved
			if finished then
				questDone(p, def)
			end
		end
	end
	local sdef = starterDef(quests)
	if sdef and sdef.Kind == kind and sdef.Check == nil then
		local state =
			{ P = quests.StarterP, Done = quests.StarterP >= sdef.Goal, Claimed = false, Seen = quests.StarterSeen }
		local moved, finished = Core.Advance(state, sdef, value, ctx)
		if moved then
			quests.StarterP = state.P
			quests.StarterSeen = state.Seen
			changed = true
		end
		if finished then
			questDone(p, sdef)
		end
	end
	if changed then
		markDirty(p, "Quests")
	end
end

function RewardService.CurrentSeason(): { [string]: any }?
	local s = Core.SeasonAt(os.time())
	if not s then
		return nil
	end
	return {
		Id = s.Id,
		Key = s.Key,
		StartsAt = s.StartsAt,
		EndsAt = s.EndsAt,
		Tiers = s.Def.Tiers,
		TierXp = s.Def.TierXp,
		Rolling = s.Rolling,
	}
end

-- Saison-Daten auf die aktive Saison bringen (Wechsel = neuer Pass)
local function seasonOf(data: Data): (Data, Data?)
	local season = tableField(data, "Season")
	local current = Core.SeasonAt(os.time())
	if not current then
		return season, nil
	end
	if season.Id ~= current.Id then
		season.Id = current.Id
		season.Xp = 0
		season.BoughtXp = 0
		season.ClaimedFree = {}
		season.ClaimedPremium = {}
		season.Counts = {}
		local passSeasons = type(data.Purchases) == "table" and data.Purchases.PassSeasons or nil
		season.Premium = type(passSeasons) == "table"
			and (passSeasons[tostring(current.Id)] == true or passSeasons[current.Id] == true)
	end
	season.Xp = math.max(0, num(season.Xp, 0))
	season.BoughtXp = math.clamp(num(season.BoughtXp, 0), 0, season.Xp)
	season.Premium = season.Premium == true
	if type(season.ClaimedFree) ~= "table" then
		season.ClaimedFree = {}
	end
	if type(season.ClaimedPremium) ~= "table" then
		season.ClaimedPremium = {}
	end
	if type(season.Counts) ~= "table" then
		season.Counts = {}
	end
	return season, current
end

local CAPS: { [string]: number } = {
	CountingDay = (SCFG.XpSources.CountingDay or {}).Cap or 12,
	Respekt = (SCFG.XpSources.Respekt or {}).Cap or 5,
}

function RewardService.GrantSeasonXp(p: Player, amount: number, reason: string)
	if not isPlayer(p) or not finite(amount) or amount <= 0 or type(reason) ~= "string" then
		return
	end
	local data = dataOf(p)
	if not data then
		return
	end
	local season, current = seasonOf(data)
	if not current then
		return
	end
	local counts = season.Counts
	local day = today()
	if counts.Day ~= day then
		table.clear(counts)
		counts.Day = day
	end
	local cap = CAPS[reason]
	if cap then
		if num(counts[reason], 0) >= cap then
			return
		end
		counts[reason] = num(counts[reason], 0) + 1
	end
	local maxXp = current.Def.Tiers * current.Def.TierXp
	local before = season.Xp
	local add = math.floor(math.min(amount, SCFG.MaxGrant))
	season.Xp = math.min(maxXp, season.Xp + add)
	-- Saison-XP aus einem Robux-Kauf (ShopService-Grund "Robux…") zählt wie gekaufte Stufen: nur Kosmetik (REUSE §7 #8)
	if string.sub(reason, 1, 5) == "Robux" then
		season.BoughtXp = math.min(season.Xp, num(season.BoughtXp, 0) + (season.Xp - before))
	elseif before + add > maxXp and num(season.BoughtXp, 0) > 0 then
		-- Pass voll, aber weiter verdient: verdiente XP ersetzt gekaufte (sonst blieben Stufen 41–50 nach +10 gekauften
		-- Stufen für immer „nur gekauft“ und zahlten nie CR/Boost/Token – Käufer dürfen nicht schlechter stehen)
		season.BoughtXp = math.max(0, num(season.BoughtXp, 0) - (before + add - maxXp))
	end
	markDirty(p, "Season")
end

function RewardService.SeasonPremium(p: Player): boolean
	local data = isPlayer(p) and dataOf(p) or nil
	if not data then
		return false
	end
	local season = seasonOf(data)
	return season.Premium == true
end

function RewardService.GrantSeasonPremium(p: Player): boolean
	if not isPlayer(p) then
		return false
	end
	local data = dataOf(p)
	if not data then
		return false
	end
	local season, current = seasonOf(data)
	if not current then
		return false
	end
	season.Premium = true
	notify(p, "prog.season.premiumOn", nil, "Success")
	markDirty(p, "Season")
	return true
end

-- gekaufte Stufen: Saison-XP + Merker (zahlen nur Kosmetik, bis die Stufe mit verdienter XP erreicht ist)
function RewardService.AddSeasonTiers(p: Player, n: number): number
	if not isPlayer(p) or not isInt(n) or n < 1 or n > 50 then
		return 0
	end
	local data = dataOf(p)
	if not data then
		return 0
	end
	local season, current = seasonOf(data)
	if not current then
		return 0
	end
	local def = current.Def
	local maxXp = def.Tiers * def.TierXp
	local before = season.Xp
	season.Xp = math.min(maxXp, season.Xp + n * def.TierXp)
	season.BoughtXp = math.min(season.Xp, num(season.BoughtXp, 0) + (season.Xp - before))
	markDirty(p, "Season")
	return ProgressMath.SeasonTier(season.Xp, def.TierXp, def.Tiers)
end

-- ---------------------------------------------------------------------
-- 5) ANFRAGEN
-- ---------------------------------------------------------------------
local function findQuest(list: { Data }, id: string): Data?
	for _, q in ipairs(list) do
		if q.Id == id then
			return q
		end
	end
	return nil
end

local function dailyCredits(p: Player, def: any): number
	local minutes = QCFG.TierMinutes[def.Tier] or QCFG.TierMinutes[1]
	return incomeCredits(p, minutes, QCFG.DailyMinCredits)
end

local function weeklyCredits(p: Player): number
	return incomeCredits(p, QCFG.WeeklyHours * 60, QCFG.WeeklyMinCredits)
end

local function handleQuest(p: Player, arg: any): Reply
	if not exactKeys(arg, { "Id" }) or type(arg.Id) ~= "string" or #arg.Id > 8 then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	ensureQuests(p, data)
	local quests = questsOf(data)
	local lang = langOf(p)
	-- Starter-Linie
	local sdef = starterDef(quests)
	if sdef and sdef.Id == arg.Id then
		if quests.StarterP < sdef.Goal then
			return fail(p, "prog.questNotDone")
		end
		local ok, credited = call("ShopService", "Credit", p, sdef.Credits, "Quest")
		if not ok or credited ~= true then
			return fail(p, "prog.grantFailed")
		end
		if sdef.Title then
			call("ProgressionService", "GrantTitle", p, sdef.Title)
		end
		quests.StarterDone[sdef.Id] = true
		quests.Starter += 1
		quests.StarterP = 0
		quests.StarterSeen = {}
		markDirty(p, "Quests")
		local message = T(p, "prog.starterDone", quests.Starter - 1, credits(sdef.Credits, lang))
		if quests.Starter > #QCFG.StarterLine then
			message ..= " " .. T(p, "prog.starterAll")
		end
		return { Ok = true, Message = message }
	end
	-- Aufhol-Quest
	local comeback = quests.Comeback
	if type(comeback) == "table" and comeback.Id == arg.Id then
		if not comeback.Done then
			return fail(p, "prog.questNotDone")
		end
		local def = QCFG.Comeback
		local amount = incomeCredits(p, def.Minutes, def.MinCredits)
		local ok, credited = call("ShopService", "Credit", p, amount, "Quest")
		if not ok or credited ~= true then
			return fail(p, "prog.grantFailed")
		end
		comeback.Claimed = true
		quests.Comeback = nil
		markDirty(p, "Quests")
		return { Ok = true, Message = T(p, "prog.questClaimed", credits(amount, lang), 0) }
	end
	-- Tages-/Wochenquests
	local weekly = false
	local q = findQuest(quests.Daily, arg.Id)
	if not q then
		q = findQuest(quests.Weekly, arg.Id)
		weekly = q ~= nil
	end
	if not q then
		return fail(p, "prog.questUnknown")
	end
	if q.Claimed then
		return fail(p, "prog.questClaimedAlready")
	end
	if not q.Done then
		return fail(p, "prog.questNotDone")
	end
	local def = PCFG.QuestById[q.Id]
	local amount = if weekly then weeklyCredits(p) else dailyCredits(p, def)
	local ok, credited = call("ShopService", "Credit", p, amount, "Quest")
	if not ok or credited ~= true then
		return fail(p, "prog.grantFailed")
	end
	q.Claimed = true
	local seasonXp = if weekly then QCFG.WeeklySeasonXp else QCFG.DailySeasonXp
	RewardService.GrantSeasonXp(p, seasonXp, if weekly then "WeeklyQuest" else "DailyQuest")
	local kind = PCFG.QuestKindByKey[def.Kind]
	if weekly then
		if kind and kind.Cat == "Trade" then
			call("ProgressionService", "AddXp", p, PCFG.XpSources.WeeklyQuest.Xp, "WeeklyQuest", nil)
		end
	elseif isTradeKind(def.Kind) then
		call("ProgressionService", "AddXp", p, PCFG.XpSources.DailyQuest.Xp, "DailyQuest", nil)
	end
	markDirty(p, "Quests")
	return { Ok = true, Message = T(p, "prog.questClaimed", credits(amount, lang), seasonXp) }
end

local function handleReroll(p: Player, arg: any): Reply
	if not exactKeys(arg, { "Id" }) or type(arg.Id) ~= "string" or #arg.Id > 8 then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	ensureQuests(p, data)
	local quests = questsOf(data)
	if quests.Rerolled == true then
		return fail(p, "prog.rerollUsed")
	end
	local q = findQuest(quests.Daily, arg.Id)
	if not q then
		return fail(p, "prog.questUnknown")
	end
	if q.Done or q.Claimed then
		return fail(p, "prog.rerollClaimed")
	end
	local newId = Core.RerollPick(p.UserId, quests.Day, quests.Daily, q.Id)
	if not newId then
		return fail(p, "prog.rerollNone")
	end
	local def = PCFG.QuestById[newId]
	for index, entry in ipairs(quests.Daily) do
		if entry == q then
			quests.Daily[index] = newQuest(def)
		end
	end
	quests.Rerolled = true
	markDirty(p, "Quests")
	return { Ok = true, Message = T(p, "prog.rerollDone", questText(p, def)), Id = newId }
end

local function handleLogin(p: Player, arg: any): Reply
	if not emptyArg(arg) then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	local login = tableField(data, "Login")
	local day = today()
	local okClub, club = call("MonetizationService", "IsClub", p)
	local nextState = Core.LoginStep(login, day, Util.IsoWeek(), okClub and club == true)
	if not nextState then
		return fail(p, "prog.loginAlready")
	end
	local cfg = RCFG.Login
	local reward = cfg.Cycle[nextState.DayIdx]
	if nextState.DayIdx == #cfg.Cycle and nextState.Cycle >= 2 and reward.Repeat then
		reward = reward.Repeat
	end
	local grant, seasonXp, _title, parts = buildReward(p, reward, true)
	-- 28er-Spur (einmalig je Meilenstein)
	local trackParts: { string } = {}
	local trackGrant: Types.Grant? = nil
	if nextState.Track ~= num(login.Track, 0) then
		for _, milestone in ipairs(cfg.Track) do
			if milestone.Day == nextState.Track then
				local g, _, _, tp = buildReward(p, milestone, true)
				trackGrant = g
				trackParts = tp
			end
		end
	end
	if not applyGrant(p, grant, "Login") then
		return fail(p, "prog.grantFailed")
	end
	if trackGrant and not applyGrant(p, trackGrant, "Login") then
		trackParts = {}
		nextState.Track = num(login.Track, 0) -- Meilenstein bleibt offen, Tag zählt erneut beim nächsten Login
	end
	-- buchen
	local usedFreeze = num(nextState.UsedFreeze, 0)
	nextState.UsedFreeze = nil
	nextState.DayIdx = nil
	for key, value in pairs(nextState) do
		login[key] = value
	end
	if seasonXp > 0 then
		RewardService.GrantSeasonXp(p, seasonXp, "Login")
	end
	call("ProgressionService", "NoteStat", p, "LoginStreak", login.Best, "max")
	markDirty(p, "Login")
	local dayIdx = ProgressMath.LoginDay(login.Streak)
	local lang = langOf(p)
	local message = T(p, "prog.loginClaimed", dayIdx, table.concat(parts, Lang.T(lang, "prog.rw.sep")))
	if usedFreeze > 0 then
		message ..= " " .. T(p, "prog.loginFreeze", login.Freeze)
	end
	if #trackParts > 0 then
		message ..= " " .. T(p, "prog.loginTrack", login.Track, table.concat(trackParts, Lang.T(lang, "prog.rw.sep")))
	end
	return { Ok = true, Message = message, Streak = login.Streak, Day = dayIdx }
end

local function rewardFor(def: any, track: string, tier: number): any
	local list = if track == "Premium" then def.Premium else def.Free
	if type(list) ~= "table" then
		return nil
	end
	for _, reward in ipairs(list) do
		if reward.Tier == tier then
			return reward
		end
	end
	return nil
end

local function handleSeason(p: Player, arg: any): Reply
	if
		not exactKeys(arg, { "Tier", "Track" })
		or not isInt(arg.Tier)
		or (arg.Track ~= "Free" and arg.Track ~= "Premium")
	then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	local season, current = seasonOf(data)
	if not current then
		return fail(p, "prog.season.ended")
	end
	local def = current.Def
	local tier = arg.Tier
	if tier < 1 or tier > def.Tiers then
		return fail(p, "core.invalid")
	end
	local reward = rewardFor(def, arg.Track, tier)
	if not reward then
		return fail(p, "prog.season.none")
	end
	if ProgressMath.SeasonTier(season.Xp, def.TierXp, def.Tiers) < tier then
		return fail(p, "prog.season.locked")
	end
	if arg.Track == "Premium" and not season.Premium then
		return fail(p, "prog.season.premiumNeeded")
	end
	local claimed = if arg.Track == "Premium" then season.ClaimedPremium else season.ClaimedFree
	local key = tostring(tier)
	if claimed[key] then
		return fail(p, "prog.season.already")
	end
	-- Stufe nur gekauft (nicht mit verdienter XP erreicht): einkommenswirksame Teile zahlen erst später (REUSE §7 #8)
	local earnedTier = ProgressMath.SeasonTier(season.Xp - num(season.BoughtXp, 0), def.TierXp, def.Tiers)
	local earned = tier <= earnedTier
	if not earned then
		for field in pairs(SCFG.EarnedOnlyFields) do
			if reward[field] ~= nil then
				return fail(p, "prog.season.boughtOnly")
			end
		end
	end
	local grant, _seasonXp, title, parts = buildReward(p, reward, earned)
	if not applyGrant(p, grant, "Season") then
		return fail(p, "prog.grantFailed")
	end
	if title then
		call("ProgressionService", "GrantTitle", p, title)
	end
	claimed[key] = true
	markDirty(p, "Season")
	return {
		Ok = true,
		Message = T(p, "prog.season.claimed", tier, table.concat(parts, Lang.T(langOf(p), "prog.rw.sep"))),
	}
end

local function handleCode(p: Player, arg: any): Reply
	if not exactKeys(arg, { "Code" }) or type(arg.Code) ~= "string" or #arg.Code > RCFG.CodeMaxLength * 3 then
		return fail(p, "core.invalid")
	end
	local raw = string.gsub(arg.Code, "%s+", "")
	if #raw < 1 or #raw > RCFG.CodeMaxLength then
		return fail(p, "prog.code.bad")
	end
	local code = string.upper(raw)
	if not string.match(code, "^[%w_]+$") then
		return fail(p, "prog.code.bad")
	end
	local entry = (RCFG.Codes or {})[code]
	if type(entry) ~= "table" or type(entry.Grant) ~= "table" then
		return fail(p, "prog.code.bad")
	end
	if entry.Expires ~= nil then
		local expires = isoToUnix(entry.Expires)
		if not expires or os.time() >= expires then
			return fail(p, "prog.code.expired")
		end
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	local login = tableField(data, "Login")
	local used = tableField(login, "Codes")
	if used[code] then
		return fail(p, "prog.code.used")
	end
	-- Firewall: Codes geben NUR CR oder Kosmetik
	local grant: Types.Grant = {}
	local lang = langOf(p)
	local parts: { string } = {}
	if isInt(entry.Grant.Credits) and entry.Grant.Credits > 0 then
		grant.Credits = math.min(entry.Grant.Credits, 1e14 - 1)
		table.insert(parts, Lang.T(lang, "prog.rw.credits", credits(grant.Credits :: number, lang)))
	end
	if type(entry.Grant.Cosmetics) == "table" and #entry.Grant.Cosmetics > 0 then
		local list: { string } = {}
		for _, key in ipairs(entry.Grant.Cosmetics) do
			if type(key) == "string" then
				table.insert(list, key)
				table.insert(parts, Lang.T(lang, "prog.rw.cosmetic", itemName("Cosmetic", key, lang)))
			end
		end
		if #list > 0 then
			grant.Cosmetics = list
		end
	end
	if grantEmpty(grant) then
		return fail(p, "prog.code.bad")
	end
	if not applyGrant(p, grant, "Code") then
		return fail(p, "prog.grantFailed")
	end
	-- Liste begrenzt: nur Einträge entfernen, die nie wieder einlösbar sind (Code gestrichen oder abgelaufen) –
	-- ein noch gültiger Code bleibt immer vermerkt (kein zweites Einlösen)
	local count = 0
	for _ in pairs(used) do
		count += 1
	end
	if count >= RCFG.CodesKeep then
		local now = os.time()
		local stale: { string } = {}
		for key in pairs(used) do
			local known = type(key) == "string" and (RCFG.Codes or {})[key] or nil
			local expires = if type(known) == "table" then isoToUnix(known.Expires) else nil
			if type(known) ~= "table" or (expires ~= nil and now >= expires) then
				table.insert(stale, key)
			end
		end
		for _, key in ipairs(stale) do
			used[key] = nil
		end
	end
	used[code] = true
	call("MetricsService", "Custom", p, "CodeRedeemed", 1, { Code = code })
	return { Ok = true, Message = T(p, "prog.code.ok", table.concat(parts, Lang.T(lang, "prog.rw.sep"))) }
end

local function handleTutorial(p: Player, arg: any): Reply
	if not exactKeys(arg, { "Step" }) or not isInt(arg.Step) then
		return fail(p, "core.invalid")
	end
	local step = arg.Step
	local cfg = PCFG.Tutorial
	if step ~= cfg.SkipStep and (step < 1 or step > cfg.Steps) then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	local flags = tableField(data, "Flags")
	local claimed = tableField(flags, "TutClaim")
	local gained = 0
	local function claim(s: number)
		local key = tostring(s)
		local xp = cfg.Xp[s]
		if xp and not claimed[key] then
			claimed[key] = true
			local ok, value = call("ProgressionService", "AddXp", p, xp, "Tutorial", { NoMult = true })
			if ok and finite(value) then
				gained += value
			end
		end
	end
	local before = math.floor(num(flags.TutStep, 0))
	if step == cfg.SkipStep then
		-- "Tutorial überspringen" gibt dieselben Belohnungen: alle Schritt-XP und die Mini-Prüfung
		-- „Setze ein Schutz-Paar“, die sonst die Übungs-Order mit „Schutz an“ erfüllt (§B2 ~7:00)
		for s = 1, cfg.Steps do
			claim(s)
		end
		flags.TutStep = math.max(before, cfg.Steps)
		call("ProgressionService", "ExamDone", p, "ProtectPair")
	else
		flags.TutStep = math.max(before, step)
		for s = 1, step do
			claim(s)
		end
		if step >= cfg.Steps and before < cfg.Steps then
			funnel(p, 17)
		end
	end
	markDirty(p, "Flags", "Social") -- Social.CanPromptNotify hängt am Tutorial-Fortschritt
	if gained > 0 then
		return { Ok = true, Message = Lang.T(langOf(p), "tut.reward", gained), Xp = gained }
	end
	return { Ok = true, Xp = 0 }
end

-- ---------------------------------------------------------------------
-- 6) STARTER-CHECKS, LIGA-BELOHNUNG, SPIELZEIT, RÜCKKEHR
-- ---------------------------------------------------------------------
local function checkValue(p: Player, data: Data, check: string): number
	if check == "Floors" then
		local ok, floors = call("TowerService", "Floors", p)
		if ok and finite(floors) then
			return floors
		end
		local tower = data.Tower
		return if type(tower) == "table" and type(tower.Floors) == "table" then #tower.Floors else 0
	elseif check == "Eff" then
		local tower = data.Tower
		return if type(tower) == "table" then num(tower.Eff, 0) else 0
	elseif check == "Licence" then
		local ok, licence = call("ProgressionService", "Licence", p)
		return if ok and finite(licence) then licence else 1
	elseif check == "Lessons" then
		local prog = data.Prog
		local n = 0
		if type(prog) == "table" and type(prog.Lessons) == "table" then
			for _ in pairs(prog.Lessons) do
				n += 1
			end
		end
		return n
	elseif check == "RoomKinds" then
		local tower = data.Tower
		local seen: { [string]: boolean } = {}
		local n = 0
		if type(tower) == "table" and type(tower.Floors) == "table" then
			for _, floor in ipairs(tower.Floors) do
				local room = if type(floor) == "table" then floor.R else nil
				if type(room) == "string" and room ~= "" and not seen[room] then
					seen[room] = true
					n += 1
				end
			end
		end
		return n
	elseif check == "BotOn" then
		local depot = data.Depot
		if type(depot) == "table" and type(depot.Bots) == "table" then
			for _, bot in pairs(depot.Bots) do
				if type(bot) == "table" and bot.On == true then
					return 1
				end
			end
		end
		return 0
	elseif check == "LeagueDays" then
		local ok, stats = call("OrderService", "LeagueStats", p)
		local days = if ok and type(stats) == "table" then num(stats.Days, 0) else 0
		local league = data.League
		return math.max(days, if type(league) == "table" then num(league.Days, 0) else 0)
	elseif check == "Wealth" then
		local ok, wealth = call("ProgressionService", "Wealth", p)
		return if ok and finite(wealth) then wealth else 0
	end
	return 0
end

local function refreshStarter(p: Player, data: Data): boolean
	local quests = questsOf(data)
	local def = starterDef(quests)
	if not def or def.Check == nil then
		return false
	end
	local value = math.clamp(checkValue(p, data, def.Check), 0, def.Goal)
	if value ~= quests.StarterP then
		local wasDone = quests.StarterP >= def.Goal
		quests.StarterP = value
		if value >= def.Goal and not wasDone then
			questDone(p, def)
		end
		return true
	end
	return false
end

local TIER_DECOR: { [string]: string } =
	{ Bronze = "TrophyBronze", Silber = "TrophySilver", Gold = "TrophyGold", Diamant = "TrophyDiamond" }

-- Liga-Belohnung der Vorwoche beim ersten Join der Folgewoche (§B11.1)
local function checkLeagueReward(p: Player, data: Data)
	call("OrderService", "LeagueStats", p) -- rollt die Woche (Last* der Vorwoche)
	local league = data.League
	if type(league) ~= "table" then
		return
	end
	local lastWeek = num(league.LastWeek, 0)
	local tier = league.LastTier
	if lastWeek <= 0 or num(league.LastGrantedWeek, 0) >= lastWeek then
		return
	end
	if type(tier) ~= "string" or not TIER_DECOR[tier] then
		league.LastGrantedWeek = lastWeek -- keine Stufe erreicht: nichts zu vergeben
		return
	end
	local grant: Types.Grant = { Decor = { [TIER_DECOR[tier]] = 1 } }
	if not applyGrant(p, grant, "League") then
		return -- später erneut (Shop nicht erreichbar)
	end
	league.LastGrantedWeek = lastWeek
	if type(league.Trophies) ~= "table" then
		league.Trophies = {}
	end
	table.insert(league.Trophies, { W = lastWeek, T = tier })
	while #league.Trophies > 52 do
		table.remove(league.Trophies, 1)
	end
	call("ProgressionService", "GrantTitle", p, "League" .. tier)
	call("ProgressionService", "AddXp", p, PCFG.LeagueXp[tier] or 0, "League", { NoMult = true })
	RewardService.GrantSeasonXp(p, (SCFG.XpSources.League or {})[tier] or 0, "League")
	local tierName = { de = Lang.T("de", "prog.tier." .. tier), en = Lang.T("en", "prog.tier." .. tier) }
	notify(p, "prog.league.reward", { T(p, "prog.tier." .. tier), PCFG.LeagueXp[tier] or 0 }, "Success")
	call("CommunityService", "Announce", "prog.league.announce", { p.DisplayName, tierName })
	markDirty(p, "League")
end

local function playtimeTick()
	local season = SCFG.XpSources.Playtime
	local day = today()
	for _, p in ipairs(Players:GetPlayers()) do
		local okReady, ready = call("PlayerStateService", "IsReady", p)
		if not okReady or ready ~= true then
			continue
		end
		local data = dataOf(p)
		if not data then
			continue
		end
		local acc = (playAcc[p] or 0) + PLAY_TICK
		local minutes = 0
		while acc >= 60 and minutes < 10 do
			acc -= 60
			minutes += 1
		end
		playAcc[p] = acc
		local seasonData = seasonOf(data)
		if seasonData.PlayDay ~= day then
			seasonData.PlayDay = day
			seasonData.PlayToday = 0
		end
		for _ = 1, minutes do
			if num(seasonData.PlayToday, 0) < season.MaxMinutes then
				seasonData.PlayToday = num(seasonData.PlayToday, 0) + 1
				if seasonData.PlayToday % season.Minutes == 0 then
					RewardService.GrantSeasonXp(p, season.Xp, "Playtime")
				end
			end
		end
		-- Funnel 17 "TenMinutes": erste Sitzung ≥ 9:30 min
		local since = readyClock[p]
		if since and num(data.Sessions, 0) <= 1 and os.clock() - since >= PCFG.Tutorial.TenMinutesSeconds then
			funnel(p, 17)
		end
		-- Liga-Wochenwechsel während der Sitzung
		local checked = leagueCheckedAt[p] or 0
		if os.clock() - checked >= LEAGUE_CHECK_EVERY then
			leagueCheckedAt[p] = os.clock()
			checkLeagueReward(p, data)
		end
		if ensureQuests(p, data) then
			markDirty(p, "Quests")
		end
	end
end

-- Starter-Schritte mit Zustands-Prüfung (Etagen, Lizenz, …) alle 5 s je Spieler, gestaffelt
local function starterTick(p: Player)
	if not isPlayer(p) then
		return
	end
	local okReady, ready = call("PlayerStateService", "IsReady", p)
	if not okReady or ready ~= true then
		return
	end
	local data = dataOf(p)
	if data and refreshStarter(p, data) then
		markDirty(p, "Quests")
	end
end

local function winBack(p: Player, data: Data)
	local ok, savedAt = call("DataService", "LastSavedAt", p)
	if not ok or not finite(savedAt) or savedAt <= 0 then
		return
	end
	local away = os.time() - savedAt
	local cfg = RCFG.WinBack
	if away < cfg.Days * DAY_SECONDS then
		return
	end
	local grant: Types.Grant = { BoostX2 = cfg.BoostX2 }
	local long = away >= cfg.LongDays * DAY_SECONDS
	if long then
		grant.Cosmetics = table.clone(cfg.LongCosmetics)
	end
	if not applyGrant(p, grant, "WinBack") then
		return
	end
	local quests = questsOf(data)
	quests.Comeback = newQuest(QCFG.Comeback)
	notify(p, if long then "prog.winbackLong" else "prog.winback", nil, "Success")
	markDirty(p, "Quests")
end

local function onReady(p: Player)
	local data = dataOf(p)
	if not data then
		return
	end
	readyClock[p] = os.clock()
	ensureQuests(p, data)
	seasonOf(data)
	-- Funnel 18: Rückkehr an einem späteren Tag
	local flags = tableField(data, "Flags")
	local created = num(data.Created, 0)
	if flags.Day2 ~= true and num(data.Sessions, 0) >= 2 and created > 0 and today() > Util.UtcDay(created) then
		flags.Day2 = true
		funnel(p, 18)
		markDirty(p, "Flags")
	end
	winBack(p, data)
	leagueCheckedAt[p] = os.clock()
	checkLeagueReward(p, data)
	refreshStarter(p, data)
	markDirty(p, "Quests", "Login", "Season")
end

local function onPlayerRemoving(p: Player)
	readyClock[p] = nil
	playAcc[p] = nil
	leagueCheckedAt[p] = nil
end

-- ---------------------------------------------------------------------
-- 7) STATE (§C10)
-- ---------------------------------------------------------------------
local function questView(p: Player, q: Data, def: any, credit: number, seasonXp: number, xp: number): { [string]: any }
	local kind = PCFG.QuestKindByKey[def.Kind]
	return {
		Id = q.Id,
		Kind = def.Kind,
		Cat = if kind then kind.Cat else "Tower",
		Goal = def.Goal,
		P = math.min(num(q.P, 0), def.Goal),
		Done = q.Done == true,
		Claimed = q.Claimed == true,
		Text = questText(p, def),
		Tier = def.Tier,
		Credits = credit,
		SeasonXp = seasonXp,
		Xp = xp,
	}
end

local function questsState(p: Player): { [string]: any }
	local data = dataOf(p)
	if not data then
		return { Daily = {}, Weekly = {}, Starter = false, Comeback = false }
	end
	ensureQuests(p, data)
	local quests = questsOf(data)
	local daily, weekly = {}, {}
	for _, q in ipairs(quests.Daily) do
		local def = PCFG.QuestById[q.Id]
		if def then
			local xp = if isTradeKind(def.Kind) then PCFG.XpSources.DailyQuest.Xp else 0
			local view = questView(p, q, def, dailyCredits(p, def), QCFG.DailySeasonXp, xp)
			-- Neu wählen offen: der Ersatz steht vorher fest und wird angezeigt (kein Zufall, kein Kauf, §B9.7)
			if quests.Rerolled ~= true and not q.Done and not q.Claimed then
				local swapId = Core.RerollPick(p.UserId, quests.Day, quests.Daily, q.Id)
				local swapDef = swapId and PCFG.QuestById[swapId]
				view.Swap = if swapDef then questText(p, swapDef) else false
			else
				view.Swap = false
			end
			table.insert(daily, view)
		end
	end
	local weekCredits = weeklyCredits(p)
	for _, q in ipairs(quests.Weekly) do
		local def = PCFG.QuestById[q.Id]
		if def then
			local kind = PCFG.QuestKindByKey[def.Kind]
			local xp = if kind and kind.Cat == "Trade" then PCFG.XpSources.WeeklyQuest.Xp else 0
			table.insert(weekly, questView(p, q, def, weekCredits, QCFG.WeeklySeasonXp, xp))
		end
	end
	local starter: any = false
	local sdef = starterDef(quests)
	if sdef then
		starter = {
			Index = quests.Starter,
			Total = #QCFG.StarterLine,
			Id = sdef.Id,
			Goal = sdef.Goal,
			P = math.min(quests.StarterP, sdef.Goal),
			Done = quests.StarterP >= sdef.Goal,
			Credits = sdef.Credits,
			Title = sdef.Title,
			Check = sdef.Check,
			Kind = sdef.Kind,
		}
	end
	local comeback: any = false
	if type(quests.Comeback) == "table" then
		local def = QCFG.Comeback
		comeback = questView(p, quests.Comeback, def, incomeCredits(p, def.Minutes, def.MinCredits), 0, 0)
	end
	local now = os.time()
	return {
		Day = quests.Day,
		Daily = daily,
		Rerolled = quests.Rerolled == true,
		Week = quests.Week,
		Weekly = weekly,
		Starter = starter,
		Comeback = comeback,
		DayEndsAt = (math.floor(now / DAY_SECONDS) + 1) * DAY_SECONDS,
		WeekEndsAt = (math.floor((now / DAY_SECONDS + 3) / 7) + 1) * 7 * DAY_SECONDS - 3 * DAY_SECONDS,
	}
end

local function loginState(p: Player): { [string]: any }
	local data = dataOf(p)
	if not data then
		return { Claimable = false, Streak = 0 }
	end
	local login = tableField(data, "Login")
	local day = today()
	local preview = Core.LoginStep(login, day, Util.IsoWeek(), false)
	local now = os.time()
	return {
		LastDay = num(login.LastDay, 0),
		Today = day,
		Claimable = preview ~= nil,
		Streak = num(login.Streak, 0),
		Best = num(login.Best, 0),
		Freeze = num(login.Freeze, 0),
		Track = num(login.Track, 0),
		NextDay = if preview then preview.DayIdx else ProgressMath.LoginDay(math.max(1, num(login.Streak, 1))),
		NextCycle = if preview then preview.Cycle else num(login.Cycle, 1),
		WillReset = preview ~= nil and preview.Streak == 1 and num(login.Streak, 0) > 1,
		NextAt = (math.floor(now / DAY_SECONDS) + 1) * DAY_SECONDS,
	}
end

local function seasonState(p: Player): { [string]: any }
	local data = dataOf(p)
	if not data then
		return { Id = 0, Xp = 0, Tier = 0, Premium = false }
	end
	local season, current = seasonOf(data)
	if not current then
		return { Id = 0, Xp = 0, Tier = 0, Premium = false, Ended = true }
	end
	local def = current.Def
	local index = table.find(SCFG.Seasons, def) or #SCFG.Seasons
	return {
		Id = current.Id,
		Key = current.Key,
		Name = current.Name or false,
		Rolling = current.Rolling,
		StartsAt = current.StartsAt,
		EndsAt = current.EndsAt,
		Xp = season.Xp,
		Tier = ProgressMath.SeasonTier(season.Xp, def.TierXp, def.Tiers),
		EarnedTier = ProgressMath.SeasonTier(season.Xp - num(season.BoughtXp, 0), def.TierXp, def.Tiers),
		Tiers = def.Tiers,
		TierXp = def.TierXp,
		Premium = season.Premium,
		ClaimedFree = season.ClaimedFree,
		ClaimedPremium = season.ClaimedPremium,
		PlayToday = num(season.PlayToday, 0),
		SeasonIndex = index, -- Index in Config.Season.Seasons (Rolling nutzt die Spuren der letzten Saison)
	}
end

-- ---------------------------------------------------------------------
-- 8) INIT / START
-- ---------------------------------------------------------------------
function RewardService.Init(services: any)
	Services = services
	local pss = services.PlayerStateService
	if not pss then
		warn("[RewardService] PlayerStateService fehlt – keine Anfragen/State")
		return
	end
	pss.Provide("Quests", questsState)
	pss.Provide("Login", loginState)
	pss.Provide("Season", seasonState)
	pss.Handle("RewardLogin", handleLogin, { Rate = 2, Per = 1 })
	pss.Handle("RewardQuest", handleQuest, { Rate = 2, Per = 1 })
	pss.Handle("RewardReroll", handleReroll, { Rate = 2, Per = 1 })
	pss.Handle("RewardSeason", handleSeason, { Rate = 2, Per = 1 })
	pss.Handle("RewardCode", handleCode, { Rate = 3, Per = 60 })
	pss.Handle("RewardTutorial", handleTutorial, { Rate = 2, Per = 1 })
end

function RewardService.Start()
	call("PlayerStateService", "OnReady", onReady)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	Scheduler.Every("RewardPlaytime", 1 / PLAY_TICK, playtimeTick)
	Scheduler.Staggered("RewardStarter", 0.2, function()
		return Players:GetPlayers()
	end, function(p: Player)
		starterTick(p)
	end)
end

return RewardService
