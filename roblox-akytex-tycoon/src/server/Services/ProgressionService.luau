-- =====================================================================
--  AKYTEX TYCOON – Fortschritt: Trader-XP, Lizenzen + Prüfungen, Know-how, Ruf, Vermögen & Titel, Börsengang +
--  Vorstand, Akademie, Erfolge, Badges, Firmen-Album (Server/Services/ProgressionService)
--  Besitzer: WP9 (Fortschritt, Tutorial, Sozial, Bestenlisten). Vertrag: DESIGN.md §C5.8, §C9 (Prog*), §C10 (State
--  "Prog"), §B9.1–§B9.6, §B9.8, §B2 (Funnel 11/13/14), §A7 #8/#9/#11, §C11.4 (Firewall).
--
--  Robux-Firewall (§0.4): XP, Lizenz, Know-how, Ruf entstehen NUR aus eigenen Fills (OrderService.OnTrade),
--  Börsentagen (OnDayResult), Akademie und Prüfungen. TradingPerks/LicenceDef/Licence lesen NUR Prog.* (Robux-frei).
--  Aktien-Sterne (aus CR-Ausgaben) kaufen NUR Turm-/Lifestyle-Perks. Admins können Ruf nicht geben.
--
--  Öffentliche API (§C5.8):
--    ProgressionService.AddXp(p, base, reason, opts?): number    reason ∈ Config.Progression.XpSources (sonst 0)
--    ProgressionService.Licence(p): number                        ProgressionService.LicenceDef(p): Types.Licence
--    ProgressionService.TradingPerks(p): Types.TradingPerks       nur Lizenz + Know-how
--    ProgressionService.TraderFactor(p): (gesamt, Lizenz-Teil, Ruf-Teil)   Teile multiplikativ (1 + x)
--    ProgressionService.Level(p) · Ruf(p) (Stufe 0–10) · Stars(p) (freie ★) · Perk(p, branch) · IpoCount(p)
--    ProgressionService.Wealth(p) · Title(p) (Titel-Schlüssel) · AlbumSets(p) · Unlock(p, achId)
--    ProgressionService.AdminSetLicence(p, idx): boolean          ohne Prüfung, ruft OrderService.TaintWeek
--  Ergänzungen (abwärtskompatibel): NoteStat(p, stat, amount, mode?) (Erfolgs-Zähler; RewardService/CommunityService),
--    GrantTitle(p, key): boolean · ExamDone(p, task) · _Test = { Core, QuizKey }
--  Request-Handler: ProgLesson, ProgExam, ProgKnowHow, ProgKnowHowReset, ProgIpoPreview, ProgIpo, ProgPerk,
--    ProgRespec, ProgTitle.   State: "Prog". Effekte: IpoCeremony, LicenceUp, TitleUp, Achievement.
--  Player-Attribute: "Licence" (1–10), "Title" (Titel-Schlüssel, Client lokalisiert).
--  Signale: OrderService.OnTrade/OnDayResult/OnBell, MarketService.OnNews, TowerService.OnFloorBuilt/OnStageUp.
-- =====================================================================

local BadgeService = game:GetService("BadgeService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Types = require(Shared:WaitForChild("Types"))
local Lang = require(Shared:WaitForChild("Lang"))
local Clock = require(Shared:WaitForChild("Clock"))
local Format = require(Shared:WaitForChild("Format"))
local ProgressMath = require(Shared:WaitForChild("ProgressMath"))
local TowerMath = require(Shared:WaitForChild("TowerMath")) :: any
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local ProgressionService = {}
local Services: any = nil

type Reply = Types.Reply
type Data = { [string]: any }

local PCFG: any = Config.Progression
ProgressMath.Configure(PCFG)

local MAX_MONEY = 9e15
local LOG_GAP = 10
local WEALTH_HZ = 0.2 -- je Spieler alle 5 s: Vermögen, Höchstwerte, Erfolge, Badges
local CRASH_HZ = 1
local TICKER_PATTERN = "^%u%u%u%u?$"
local MAX_RECENT_BUYS = 64
local SECTOR_ETF = "ETF"

-- ---------------------------------------------------------------------
-- 0) QUIZ-LÖSUNGEN (nur Server – Config wird repliziert). Reihenfolge = Fragen der Lektion, Wert = richtige
--    Antwort (1-basiert). Texte: Lang/Progress "prog.les.<Id>.qN.aM" – beim Ändern beides anpassen!
-- ---------------------------------------------------------------------
local QUIZ_KEY: { [string]: { number } } = {
	L01 = { 1, 3 },
	L02 = { 1, 2, 1 },
	L03 = { 2, 1, 3 },
	L04 = { 1, 2, 1 },
	L05 = { 2, 3, 1 },
	L06 = { 1, 3, 1 },
	L07 = { 2, 1, 2 },
	L08 = { 1, 2, 1 },
	L09 = { 2, 1, 1 },
	L10 = { 1, 2, 1 },
	L11 = { 2, 1, 1 },
	L12 = { 2, 1, 2 },
	L13 = { 1, 1, 2 },
	L14 = { 1, 2, 1 },
	L15 = { 1, 1, 2 },
	L16 = { 1, 2, 2 },
}

-- Erfolgs-Zähler, die RewardService.Track/CommunityService weiterreichen (Art/Stat -> Stat)
local STAT_FROM: { [string]: string } = {
	Collect = "Collect",
	RoomLevel = "RoomLevels",
	Hire = "Hired",
	Transfer = "Transfers",
	Drive = "Drive",
	VisitTower = "Visits",
	GiveRespekt = "Respekt",
	HelpBuild = "HelpBuild",
	Pickup = "Pickups",
	BearOrbs = "BearOrbs",
	Bell = "Bell",
	RespektGot = "RespektGot",
	Invites = "Invites",
	WorldEvent = "WorldEvents",
	LoginStreak = "LoginStreak",
}

local TIER_LEVEL: { [string]: number } = { Bronze = 1, Silber = 2, Gold = 3, Diamant = 4 }

-- Pro-Spieler-Tabellen (alle bei PlayerRemoving geleert)
local wealthOf: { [Player]: number } = {}
local ipoTokens: { [Player]: { Token: string, Until: number } } = {}
local recentBuys: { [Player]: { [number]: number } } = {} -- Instrument -> Tick des letzten Kaufs
local sectorsToday: { [Player]: { Day: number, Set: { [string]: boolean } } } = {}
local crashWatch: { [Player]: { Nav0: number, Basis0: number, Until: number } } = {}
local lessonAt: { [Player]: { [string]: number } } = {}
local badgeBusy: { [Player]: { [string]: boolean } } = {}
local ipoBusy: { [Player]: boolean } = {}
local readyAt: { [Player]: number } = {}
local lastLogAt: { [string]: number } = {}

-- ---------------------------------------------------------------------
-- 1) HELFER
-- ---------------------------------------------------------------------
local function logError(where: string, err: any)
	local now = os.clock()
	if (lastLogAt[where] or -math.huge) + LOG_GAP <= now then
		lastLogAt[where] = now
		warn("[ProgressionService] " .. where .. ": " .. tostring(err))
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

-- optionaler Dienst über pcall: (ok, Ergebnisse …)
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

local function effect(p: Player, name: string, strength: number, data: any)
	call("PlayerStateService", "Effect", p, name, strength, data)
end

local function funnel(p: Player, step: number)
	local names = PCFG.Tutorial.FunnelNames
	call("MetricsService", "Funnel", p, step, names[step] or ("Step" .. step))
end

local function track(p: Player, kind: string, amount: number, ctx: { [string]: any }?)
	call("RewardService", "Track", p, kind, amount, ctx)
end

local function today(): number
	return Util.UtcDay()
end

local function exactKeys(arg: any, keys: { string }): boolean
	if type(arg) ~= "table" then
		return false
	end
	local allowed: { [string]: boolean } = {}
	for _, key in ipairs(keys) do
		allowed[key] = true
	end
	for key in pairs(arg) do
		if type(key) ~= "string" or not allowed[key] then
			return false
		end
	end
	for _, key in ipairs(keys) do
		if arg[key] == nil then
			return false
		end
	end
	return true
end

local function licenceDefAt(idx: number): any
	local list = PCFG.Licences
	return list[math.clamp(math.floor(num(idx, 1)), 1, #list)]
end

local function companies(): any
	local c = Config.Companies
	return if type(c) == "table" then c else {}
end

local function instDef(i: number): any
	local byId = companies().ById
	return if type(byId) == "table" then byId[i] else nil
end

-- ---------------------------------------------------------------------
-- 2) KERN (rein, auf dem Spielstand; SelfTests nutzen dieselben Funktionen)
-- ---------------------------------------------------------------------
local Core = {}

local function asSet(t: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if type(t) ~= "table" then
		return out
	end
	for k, v in pairs(t) do
		if type(k) == "string" and v == true then
			out[k] = true
		elseif type(k) == "number" and type(v) == "string" then
			out[v] = true -- alte Liste {"A","B"} -> Menge
		end
	end
	return out
end

-- Spielstand-Teil Prog reparieren (nach DataService Migrate/Reconcile/Sanitize; nie Fortschritt erfinden)
function Core.Repair(data: Data)
	if type(data.Prog) ~= "table" then
		data.Prog = {}
	end
	local prog = data.Prog
	prog.Xp = ProgressMath.Clamp(num(prog.Xp, 0))
	prog.Licence = if isInt(prog.Licence) then math.clamp(prog.Licence, 1, #PCFG.Licences) else 1
	prog.Exams = asSet(prog.Exams)
	if type(prog.ExamProgress) ~= "table" then
		prog.ExamProgress = {}
	end
	local lessons: { [string]: number } = {}
	if type(prog.Lessons) == "table" then
		for id, value in pairs(prog.Lessons) do
			if type(id) == "string" and PCFG.LessonById[id] and isInt(value) then
				lessons[id] = math.clamp(value, 1, 2)
			end
		end
	end
	prog.Lessons = lessons
	local kh: { [string]: number } = {}
	if type(prog.KH) == "table" then
		for key, level in pairs(prog.KH) do
			local node = PCFG.NodeByKey[key]
			if node and isInt(level) and level > 0 then
				kh[key] = math.clamp(level, 0, node.Max)
			end
		end
	end
	prog.KH = kh
	prog.KHResetWeek = math.floor(num(prog.KHResetWeek, 0))
	prog.Ruf = math.max(0, math.floor(num(prog.Ruf, 0)))
	prog.RufDay = math.floor(num(prog.RufDay, 0))
	prog.RufToday = math.max(0, math.floor(num(prog.RufToday, 0)))
	prog.Title = if type(prog.Title) == "string" then prog.Title else ""
	prog.TitleOff = prog.TitleOff == true -- Spieler hat „Kein Titel“ gewählt (Vermögens-Titel nicht automatisch setzen)
	prog.Titles = asSet(prog.Titles)
	if prog.Title ~= "" and not prog.Titles[prog.Title] then
		prog.Title = ""
	end
	prog.Album = asSet(prog.Album)
	prog.Ach = asSet(prog.Ach)
	local stats: { [string]: number } = {}
	if type(prog.AchProgress) == "table" then
		for key, value in pairs(prog.AchProgress) do
			if type(key) == "string" and finite(value) and value >= 0 then
				stats[key] = math.min(value, MAX_MONEY)
			end
		end
	end
	prog.AchProgress = stats
	prog.Badges = asSet(prog.Badges)
	prog.XpDay = math.floor(num(prog.XpDay, 0))
	if type(prog.XpCounts) ~= "table" then
		prog.XpCounts = {}
	end
	if type(prog.AchPending) ~= "table" then
		prog.AchPending = {}
	end
	if type(prog.Prestige) ~= "table" then
		prog.Prestige = {}
	end
	local pr = prog.Prestige
	pr.Count = math.max(0, math.floor(num(pr.Count, 0)))
	pr.Stars = math.max(0, math.floor(num(pr.Stars, 0)))
	pr.Firmenwert = ProgressMath.Clamp(num(pr.Firmenwert, 0))
	pr.RespecFree = pr.RespecFree == true
	local perks: { [string]: number } = {}
	if type(pr.Perks) == "table" then
		for key, level in pairs(pr.Perks) do
			local def = PCFG.PerkByKey[key]
			if def and isInt(level) and level > 0 then
				perks[key] = math.clamp(level, 0, def.Max)
			end
		end
	end
	pr.Perks = perks
	if Core.StarsSpent(prog) > pr.Stars then
		pr.Perks = {} -- Config geändert: Sterne zurück (nie Sterne erfinden)
	end
	local tickers = {}
	if type(pr.Tickers) == "table" then
		for _, entry in ipairs(pr.Tickers) do
			if type(entry) == "table" and type(entry.T) == "string" and #tickers < PCFG.Prestige.TickerKeep then
				table.insert(tickers, { T = entry.T, At = math.floor(num(entry.At, 0)) })
			end
		end
	end
	pr.Tickers = tickers
	prog.KHSpent = Core.KhSpent(prog)
end

function Core.KhSpent(prog: Data): number
	local spent = 0
	for key, level in pairs(prog.KH or {}) do
		local node = PCFG.NodeByKey[key]
		if node then
			spent += node.Cost * level
		end
	end
	return spent
end

-- abgeschlossene Akademie-Serien (je 4 Lektionen)
function Core.Series(prog: Data): number
	local perSeries: { [number]: number } = {}
	for id in pairs(prog.Lessons or {}) do
		local lesson = PCFG.LessonById[id]
		if lesson then
			perSeries[lesson.Series] = (perSeries[lesson.Series] or 0) + 1
		end
	end
	local size = PCFG.KnowHow.SeriesSize
	local done = 0
	for _, n in pairs(perSeries) do
		if n >= size then
			done += 1
		end
	end
	return done
end

function Core.Level(prog: Data): number
	local level = ProgressMath.LevelFromXp(num(prog.Xp, 0))
	return level
end

function Core.KhTotal(prog: Data): number
	local total = ProgressMath.KnowHowTotal(Core.Level(prog), prog.Licence, Core.Series(prog))
	return math.min(total, PCFG.KnowHow.Max)
end

function Core.KhFree(prog: Data): number
	return math.max(0, Core.KhTotal(prog) - Core.KhSpent(prog))
end

function Core.StarsSpent(prog: Data): number
	local spent = 0
	local pr = prog.Prestige
	if type(pr) == "table" and type(pr.Perks) == "table" then
		for _, level in pairs(pr.Perks) do
			spent += math.max(0, math.floor(num(level, 0)))
		end
	end
	return spent
end

function Core.StarsFree(prog: Data): number
	local pr = prog.Prestige
	return math.max(0, (if type(pr) == "table" then num(pr.Stars, 0) else 0) - Core.StarsSpent(prog))
end

-- Ruf-Stufe inkl. Lizenz-Untergrenze
function Core.RufLevel(prog: Data): number
	return math.max(ProgressMath.RufLevel(prog.Ruf), ProgressMath.RufFloor(prog.Licence))
end

-- Werkzeuge NUR aus Lizenz + Know-how (Robux-frei, §0.4 c)
function Core.TradingPerks(prog: Data): Types.TradingPerks
	local licence = math.clamp(math.floor(num(prog.Licence, 1)), 1, #PCFG.Licences)
	local def = licenceDefAt(licence)
	local kh = prog.KH or {}
	local function level(key: string): number
		return math.max(0, math.floor(num(kh[key], 0)))
	end
	local function valueOf(key: string): number
		local node = PCFG.NodeByKey[key]
		local v = num(node.Base, 0) + num(node.Step, 1) * level(key)
		return math.min(v, num(node.Cap, v))
	end
	local botLevels: { [string]: number } = {}
	for _, node in ipairs(PCFG.KnowHow.Nodes) do
		if node.Preset then
			botLevels[node.Preset] = level(node.Key)
		end
	end
	local indicators: { [string]: boolean } = {}
	for name, from in pairs(PCFG.Indicators) do
		indicators[name] = licence >= from
	end
	local leads = PCFG.KnowHow.ResearchLead
	local research = math.clamp(level("Research"), 0, #leads - 1)
	return {
		Licence = licence,
		Layer = def.Layer,
		BotSlots = def.BotSlots,
		BotLevels = botLevels,
		Alerts = valueOf("Alerts"),
		Watchlists = valueOf("Watch"),
		Layouts = valueOf("Layouts"),
		Monitors = valueOf("Monitors"),
		ResearchLead = leads[research + 1],
		MultiChart = level("MultiChart") >= 1 and licence >= PCFG.NodeByKey.MultiChart.Licence,
		Risk = level("Risk"),
		Indicators = indicators,
	}
end

-- Tages-/Wochen-Zähler der XP-Deckel
local function capKey(reason: string, source: any): string
	return if source.Weekly then "wk:" .. reason else reason
end

function Core.XpRoom(prog: Data, reason: string, day: number, week: number): number
	local source = PCFG.XpSources[reason]
	if type(source) ~= "table" then
		return 0
	end
	if prog.XpDay ~= day then
		-- neuer UTC-Tag: Tages-Zähler leeren, Wochen-Zähler behalten
		local counts = prog.XpCounts or {}
		local keep: { [string]: any } = {}
		for key, value in pairs(counts) do
			if type(key) == "string" and string.sub(key, 1, 3) == "wk:" then
				keep[key] = value
			end
		end
		keep.wk = counts.wk
		prog.XpCounts = keep
		prog.XpDay = day
	end
	local counts = prog.XpCounts
	if counts.wk ~= week then
		for key in pairs(counts) do
			if type(key) == "string" and string.sub(key, 1, 3) == "wk:" then
				counts[key] = nil
			end
		end
		counts.wk = week
	end
	if source.Cap == nil then
		return math.huge
	end
	return math.max(0, source.Cap - num(counts[capKey(reason, source)], 0))
end

-- XP buchen (Deckel zählt Gutschriften, nicht Punkte). Rückgabe: gebuchte XP
function Core.AddXp(prog: Data, base: number, reason: string, mult: number, day: number, week: number): number
	local source = PCFG.XpSources[reason]
	if type(source) ~= "table" or not finite(base) or base <= 0 then
		return 0
	end
	if Core.XpRoom(prog, reason, day, week) < 1 then
		return 0
	end
	local amount = math.floor(math.min(base, PCFG.MaxXpGrant) * math.clamp(num(mult, 1), 1, PCFG.XpMultMax) + 0.5)
	if amount <= 0 then
		return 0
	end
	if source.Cap ~= nil then
		local key = capKey(reason, source)
		prog.XpCounts[key] = num(prog.XpCounts[key], 0) + 1
	end
	prog.Xp = ProgressMath.Clamp(num(prog.Xp, 0) + amount)
	return amount
end

-- Ruf-Punkte: capped = Börsentag-Punkte (Tagesdeckel), sonst Akademie/Prüfung (außerhalb des Deckels)
function Core.AddRuf(prog: Data, points: number, day: number, capped: boolean): number
	local pts = math.max(0, math.floor(num(points, 0)))
	if capped then
		if prog.RufDay ~= day then
			prog.RufDay = day
			prog.RufToday = 0
		end
		pts = math.min(pts, math.max(0, PCFG.Ruf.DailyCap - prog.RufToday))
		prog.RufToday += pts
	end
	prog.Ruf = math.max(0, math.floor(num(prog.Ruf, 0))) + pts
	return pts
end

-- Tageswechsel: Ruf-Abbau für Tage ohne zählenden Börsentag (max. 30), Rückgabe: Anzahl abgebauter Tage
function Core.DayRoll(data: Data, day: number): number
	local prog = data.Prog
	local last = math.floor(num(data.LastUtcDay, 0))
	if last <= 0 then
		data.LastUtcDay = day
		return 0
	end
	if day <= last then
		return 0
	end
	local missed = day - last
	if prog.RufDay == last then
		missed -= 1 -- der letzte bekannte Tag hatte einen zählenden Börsentag
	end
	missed = math.max(0, missed)
	if missed > 0 then
		prog.Ruf = ProgressMath.RufDecay(prog.Ruf, missed, ProgressMath.RufFloor(prog.Licence))
	end
	data.LastUtcDay = day
	return missed
end

function Core.BuyNode(prog: Data, key: string): (boolean, string, { any }?)
	local node = PCFG.NodeByKey[key]
	if not node then
		return false, "core.invalid", nil
	end
	local level = math.floor(num(prog.KH[key], 0))
	if level >= node.Max then
		return false, "prog.khMax", nil
	end
	local needLicence = node.Licence
	if type(node.LevelLicence) == "table" and node.LevelLicence[level + 1] then
		needLicence = node.LevelLicence[level + 1]
	end
	if prog.Licence < needLicence then
		return false, "prog.khLocked", { needLicence }
	end
	if Core.KhFree(prog) < node.Cost then
		return false, "prog.khNoPoints", nil
	end
	prog.KH[key] = level + 1
	prog.KHSpent = Core.KhSpent(prog)
	return true, "prog.khBought", { level + 1 }
end

function Core.ResetNodes(prog: Data, week: number): (boolean, string)
	if prog.KHResetWeek == week then
		return false, "prog.khResetUsed"
	end
	if next(prog.KH) == nil then
		return false, "prog.khResetEmpty"
	end
	prog.KH = {}
	prog.KHSpent = 0
	prog.KHResetWeek = week
	return true, "prog.khReset"
end

function Core.BuyPerk(prog: Data, key: string): (boolean, string, { any }?)
	local def = PCFG.PerkByKey[key]
	if not def then
		return false, "core.invalid", nil
	end
	local perks = prog.Prestige.Perks
	local level = math.floor(num(perks[key], 0))
	if level >= def.Max then
		return false, "prog.perkMax", nil
	end
	if Core.StarsFree(prog) < 1 then
		return false, "prog.perkNoStars", nil
	end
	perks[key] = level + 1
	return true, "prog.perkBought", { level + 1 }
end

function Core.Respec(prog: Data): (boolean, string)
	local pr = prog.Prestige
	if next(pr.Perks) == nil then
		return false, "prog.respecEmpty"
	end
	if pr.RespecFree then
		pr.RespecFree = false
	elseif pr.Stars >= PCFG.Prestige.RespecCost then
		pr.Stars -= PCFG.Prestige.RespecCost
	else
		return false, "prog.respecNoStars"
	end
	pr.Perks = {}
	return true, "prog.respecDone"
end

-- Perk-Tabelle für TowerService.ResetForIpo ({ [Ast] = Stufe, StartCredits = n })
function Core.PerkTable(prog: Data): { [string]: number }
	local out: { [string]: number } = {}
	for _, def in ipairs(PCFG.Prestige.Perks) do
		out[def.Key] = math.floor(num(prog.Prestige.Perks[def.Key], 0))
	end
	out.StartCredits = math.floor(num(PCFG.Prestige.StartCredits, 0))
	return out
end

-- Börsengang buchen (vor TowerService.ResetForIpo; Rückgabe: Sterne)
function Core.ApplyIpo(prog: Data, runSpend: number, ticker: string, now: number): number
	local pr = prog.Prestige
	local stars = ProgressMath.Stars(runSpend)
	pr.Count += 1
	pr.Stars = math.floor(num(pr.Stars, 0) + stars)
	pr.Firmenwert = ProgressMath.Clamp(num(pr.Firmenwert, 0) + PCFG.Prestige.FirmPct * math.max(0, num(runSpend, 0)))
	if pr.Count == PCFG.Prestige.RespecFreeAt then
		pr.RespecFree = true
	end
	table.insert(pr.Tickers, 1, { T = ticker, At = math.floor(now) })
	while #pr.Tickers > PCFG.Prestige.TickerKeep do
		table.remove(pr.Tickers)
	end
	return stars
end

function Core.CrownFor(count: number): string
	local key = ""
	for _, crown in ipairs(PCFG.Prestige.Crowns) do
		if count >= crown.Ipos then
			key = crown.Key
		end
	end
	return key
end

-- Album-Karte (true, Sektor-Satz-Sektor? wenn neu)
function Core.AlbumAdd(prog: Data, instId: number): (boolean, string?)
	local album = PCFG.Album
	local isCard = (instId >= album.IpoFrom and instId <= album.IpoTo) or table.find(album.Cards, instId) ~= nil
	if not isCard then
		return false, nil
	end
	local key = tostring(instId)
	if prog.Album[key] then
		return false, nil
	end
	local before = Core.AlbumSets(prog)
	prog.Album[key] = true
	if Core.AlbumSets(prog) > before then
		local def = instDef(instId)
		return true, if def then def.Sector else nil
	end
	return true, nil
end

-- vollständige Sektor-Sätze (alle Firmen eines Sektors, ohne ETFs/IPOs), höchstens MaxSets
function Core.AlbumSets(prog: Data): number
	local perSector: { [string]: { have: number, total: number } } = {}
	local list = companies().Instruments
	if type(list) ~= "table" then
		return 0
	end
	for _, inst in ipairs(list) do
		if type(inst) == "table" and inst.Class ~= SECTOR_ETF and inst.Ipo ~= true and inst.Set ~= "Tutorial" then
			local entry = perSector[inst.Sector]
			if not entry then
				entry = { have = 0, total = 0 }
				perSector[inst.Sector] = entry
			end
			entry.total += 1
			if prog.Album[tostring(inst.Id)] then
				entry.have += 1
			end
		end
	end
	local sets = 0
	for _, entry in pairs(perSector) do
		if entry.total > 0 and entry.have >= entry.total then
			sets += 1
		end
	end
	return math.min(sets, PCFG.Album.MaxSets)
end

function Core.AlbumCards(prog: Data): number
	local n = 0
	for _, id in ipairs(PCFG.Album.Cards) do
		if prog.Album[tostring(id)] then
			n += 1
		end
	end
	return n
end

-- Quiz prüfen: (richtig, gesamt) oder nil bei falscher Form
function Core.LessonResult(id: string, answers: any, key: { [string]: { number } }): (number?, number?)
	local lesson = PCFG.LessonById[id]
	local solution = key[id]
	if not lesson or not solution or type(answers) ~= "table" then
		return nil, nil
	end
	local total = #lesson.Quiz
	if #answers ~= total or #solution ~= total then
		return nil, nil
	end
	local correct = 0
	for q = 1, total do
		local a = answers[q]
		if not isInt(a) or a < 1 or a > lesson.Quiz[q] then
			return nil, nil
		end
		if a == solution[q] then
			correct += 1
		end
	end
	for k in pairs(answers) do
		if type(k) ~= "number" then
			return nil, nil
		end
	end
	return correct, total
end

-- Aufgaben der Lizenz idx: { {Key, Done} }
function Core.ExamTasks(prog: Data, idx: number): { { Key: string, Done: boolean } }
	local def = PCFG.Licences[idx]
	local out = {}
	if def then
		for _, task in ipairs(def.Exam) do
			table.insert(out, { Key = task, Done = prog.Exams[task] == true })
		end
	end
	return out
end

-- Lizenz-Aufstieg, Stufe für Stufe. Hat die neue Lizenz eine Prüfung (§B9.2), gilt sie damit als bestanden:
-- +250 XP ohne Verdoppler und +20 Ruf außerhalb des Deckels (§B9.1/§B9.4). Lizenzen ohne Prüfung (Trader II,
-- Fondsmanager II) steigen nur über die XP – ohne Prüfungs-Bonus.
-- setLicence(idx) meldet jede neue Stufe an OrderService.SetLicence (dort steigt die Basis). Rückgabe: neue Stufen
function Core.Promote(prog: Data, day: number, week: number, setLicence: (number) -> ()): { number }
	local promoted: { number } = {}
	local guard = 0
	while guard < #PCFG.Licences do
		guard += 1
		local target = ProgressMath.LicenceFor(prog.Xp, prog.Exams, PCFG.Licences)
		if target <= prog.Licence then
			break
		end
		local idx = prog.Licence + 1
		prog.Licence = idx
		setLicence(idx)
		local def = PCFG.Licences[idx]
		if type(def.Exam) == "table" and #def.Exam > 0 then
			Core.AddXp(prog, PCFG.XpSources.Exam.Xp, "Exam", 1, day, week)
			Core.AddRuf(prog, PCFG.Ruf.Exam, day, false)
		end
		Core.Stat(prog, "Licence", idx, "max")
		table.insert(promoted, idx)
	end
	return promoted
end

-- Admin-Lizenz (Admin-Panel): setzt die Stufe und meldet SetLicence + TaintWeek("AdminLicence") –
-- die Liga-Woche des Empfängers zählt danach nicht (§B11.1). report(fnName, arg) = OrderService-Aufruf
function Core.AdminLicence(prog: Data, idx: number, report: (string, any) -> ()): boolean
	if not isInt(idx) or idx < 1 or idx > #PCFG.Licences then
		return false
	end
	prog.Licence = idx
	Core.Stat(prog, "Licence", idx, "max")
	report("SetLicence", idx)
	report("TaintWeek", "AdminLicence")
	return true
end

-- Stat setzen: "add" (Summe) oder "max" (Höchstwert). Rückgabe: geändert?
function Core.Stat(prog: Data, stat: string, value: number, mode: string?): boolean
	if type(stat) ~= "string" or not finite(value) then
		return false
	end
	local stats = prog.AchProgress
	local old = num(stats[stat], 0)
	local new = if mode == "max" then math.max(old, value) else old + math.max(0, value)
	new = math.min(new, MAX_MONEY)
	if new ~= old then
		stats[stat] = new
		return true
	end
	return false
end

-- neu erreichte Erfolge (noch nicht in Ach)
function Core.NewAchievements(prog: Data): { any }
	local out = {}
	local stats = prog.AchProgress
	for _, entry in ipairs(PCFG.Achievements) do
		if not prog.Ach[entry.Id] and num(stats[entry.Stat], 0) >= entry.Goal then
			table.insert(out, entry)
		end
	end
	return out
end

-- Titel hinzufügen: true = neu
function Core.AddTitle(prog: Data, key: string): boolean
	if not PCFG.TitleByKey[key] or prog.Titles[key] then
		return false
	end
	prog.Titles[key] = true
	return true
end

-- Vermögen (§B9.5)
function Core.Wealth(parts: { [string]: number }, bauKurs: number): number
	local v = num(parts.Credits, 0)
		+ num(parts.TowerValue, 0)
		+ num(parts.Firm, 0)
		+ num(parts.Collection, 0)
		+ math.max(0, num(parts.NavCents, 0)) / 100 * math.max(0, num(bauKurs, 0))
	return ProgressMath.Clamp(v)
end

ProgressionService._Test = { Core = Core, QuizKey = QUIZ_KEY }

-- ---------------------------------------------------------------------
-- 3) ZUGRIFF
-- ---------------------------------------------------------------------
local function progOf(p: Player): (Data?, Data?)
	local data = dataOf(p)
	if not data then
		return nil, nil
	end
	if type(data.Prog) ~= "table" or type(data.Prog.Prestige) ~= "table" or type(data.Prog.KH) ~= "table" then
		Core.Repair(data)
	end
	return data.Prog, data
end

local function setAttributes(p: Player, prog: Data)
	if not isPlayer(p) then
		return
	end
	if p:GetAttribute("Licence") ~= prog.Licence then
		p:SetAttribute("Licence", prog.Licence)
	end
	if p:GetAttribute("Title") ~= prog.Title then
		p:SetAttribute("Title", prog.Title)
	end
end

-- XP-Verdoppler (gratis für alle): Power-Hour täglich 19:00 Berlin (60 min) oder Admin-XP-Rausch
local function powerHourInfo(): (boolean, number)
	local now = os.time()
	local ph = PCFG.PowerHour
	local offset = 3600
	local ok, value = pcall(Clock.BerlinOffset, now)
	if ok and finite(value) then
		offset = value
	end
	local localSeconds = (now + offset) % 86400
	local start = ph.Hour * 3600 + ph.Minute * 60
	local stop = start + ph.Minutes * 60
	if localSeconds >= start and localSeconds < stop then
		return true, now + (stop - localSeconds)
	end
	return false, 0
end

local function xpRushActive(): boolean
	local ok, list = call("EventService", "Active")
	if not ok or type(list) ~= "table" then
		return false
	end
	local now = os.time()
	for _, ev in ipairs(list) do
		if type(ev) == "table" and ev.Kind == PCFG.XpRushKind and num(ev.Until, 0) > now then
			return true
		end
	end
	return false
end

local function xpMult(): number
	local mult = 1
	if powerHourInfo() then
		mult = math.max(mult, PCFG.PowerHour.Mult)
	end
	if xpRushActive() then
		mult = math.max(mult, 2)
	end
	return math.min(mult, PCFG.XpMultMax)
end

-- ---------------------------------------------------------------------
-- 4) ERFOLGE, BADGES, TITEL
-- ---------------------------------------------------------------------
local function steadyIncome(p: Player): number
	local ok, info = call("TowerService", "Income", p)
	if ok and type(info) == "table" and finite(info.Steady) then
		return math.max(0, info.Steady)
	end
	return 0
end

-- einkommens-skalierte CR-Belohnung (Minuten Dauer-Einkommen ohne Zeitlich, mindestens min)
local function incomeCredits(p: Player, minutes: number, min: number): number
	return ProgressMath.Clamp(math.max(num(min, 0), steadyIncome(p) * num(minutes, 0) * 60))
end

local function grantTitle(p: Player, prog: Data, key: string, announce: boolean): boolean
	if not Core.AddTitle(prog, key) then
		return false
	end
	local def = PCFG.TitleByKey[key]
	effect(p, "TitleUp", 1, { Title = key, Fanfare = def.Fanfare == true })
	if announce then
		call("CommunityService", "Announce", "prog.titleAnnounce", { p.DisplayName, def.Name })
	end
	markDirty(p, "Prog")
	return true
end

local function grantAchievementReward(p: Player, prog: Data, entry: any): boolean
	local reward = entry.Reward or {}
	local okAll = true
	if reward.Minutes then
		local amount = incomeCredits(p, reward.Minutes, reward.Min or 0)
		if amount > 0 then
			local ok, credited = call("ShopService", "Credit", p, amount, "Achievement")
			okAll = okAll and ok and credited == true
		end
	end
	if reward.Decor then
		local ok, granted = call("ShopService", "Grant", p, { Decor = { [reward.Decor] = 1 } }, "Achievement")
		okAll = okAll and ok and granted == true
	end
	if reward.Cosmetic then
		local ok, granted = call("ShopService", "Grant", p, { Cosmetics = { reward.Cosmetic } }, "Achievement")
		okAll = okAll and ok and granted == true
	end
	if reward.Title then
		grantTitle(p, prog, reward.Title, false)
	end
	return okAll
end

local function unlockAchievement(p: Player, prog: Data, entry: any)
	if prog.Ach[entry.Id] then
		return
	end
	prog.Ach[entry.Id] = true
	if not grantAchievementReward(p, prog, entry) then
		prog.AchPending[entry.Id] = true -- Shop (noch) nicht erreichbar: später nachbuchen
	end
	effect(p, "Achievement", 1, { Id = entry.Id })
	call("MetricsService", "Custom", p, "Achievement", 1, { Id = entry.Id })
	markDirty(p, "Prog")
end

local function retryPendingRewards(p: Player, prog: Data)
	for id in pairs(prog.AchPending) do
		local entry = PCFG.AchievementById[id]
		if entry and not grantAchievementReward(p, prog, entry) then
			return -- Shop weiter nicht erreichbar
		end
		prog.AchPending[id] = nil
	end
end

local function checkAchievements(p: Player, prog: Data)
	for _, entry in ipairs(Core.NewAchievements(prog)) do
		unlockAchievement(p, prog, entry)
	end
end

local function badgeStat(prog: Data, stat: string): number
	if stat == "Joined" then
		return 1
	end
	return num(prog.AchProgress[stat], 0)
end

local function awardBadges(p: Player, prog: Data)
	if p.UserId <= 0 then
		return -- Studio-Testspieler: keine Badges
	end
	local busy = badgeBusy[p]
	if not busy then
		busy = {}
		badgeBusy[p] = busy
	end
	for _, badge in ipairs(PCFG.Badges) do
		if badge.Id > 0 and not prog.Badges[badge.Key] and not busy[badge.Key] then
			if badgeStat(prog, badge.Stat) >= badge.Min then
				busy[badge.Key] = true
				local userId, badgeId, key = p.UserId, badge.Id, badge.Key
				task.spawn(function()
					local ok, err = pcall(function()
						return BadgeService:AwardBadgeAsync(userId, badgeId)
					end)
					local current = busy
					if ok then
						local live = if p.Parent == Players then progOf(p) else nil
						if live then
							live.Badges[key] = true
							markDirty(p, "Prog")
						end
					else
						logError("AwardBadgeAsync " .. key, err)
					end
					current[key] = nil
				end)
			end
		end
	end
end

local function updateWealthTitle(p: Player, prog: Data, wealth: number)
	local key = ProgressMath.WealthTitle(wealth)
	local isNew = false
	-- alle erreichten Vermögens-Titel besitzen (Sprung über mehrere Stufen -> nur der höchste wird gefeiert)
	for _, entry in ipairs(PCFG.Titles.Wealth) do
		if wealth >= entry.Min and not prog.Titles[entry.Key] then
			prog.Titles[entry.Key] = true
			if entry.Key == key and entry.Key ~= "Starter" then
				isNew = true
			end
		end
	end
	if isNew then
		local def = PCFG.TitleByKey[key]
		effect(p, "TitleUp", 1, { Title = key, Fanfare = def.Fanfare == true })
		call("CommunityService", "Announce", "prog.titleAnnounce", { p.DisplayName, def.Name })
	end
	-- Anzeige folgt automatisch dem höchsten Vermögens-Titel, solange kein Sonder-Titel und nicht „Kein Titel“ gewählt ist
	local current = prog.Title
	local isWealthTitle = prog.TitleOff ~= true
		and (current == "" or (PCFG.TitleByKey[current] and PCFG.TitleByKey[current].Min ~= nil))
	if isWealthTitle and current ~= key then
		prog.Title = key
		isNew = true
	end
	if isNew then
		setAttributes(p, prog)
		markDirty(p, "Prog")
	end
end

-- ---------------------------------------------------------------------
-- 5) LIZENZ-AUFSTIEG (Zeremonie §A7 #9)
-- ---------------------------------------------------------------------
local function checkLicence(p: Player, prog: Data)
	local promoted = Core.Promote(prog, today(), Util.IsoWeek(), function(idx: number)
		call("OrderService", "SetLicence", p, idx)
	end)
	for _, idx in ipairs(promoted) do
		local def = licenceDefAt(idx)
		effect(p, "LicenceUp", 1, { Licence = idx, Key = def.Key, Basis = def.Basis, BauKurs = def.BauKurs })
		call("CommunityService", "Announce", "prog.licenceAnnounce", { p.DisplayName, def.Name })
		call("MetricsService", "Progression", p, "Licence", "Complete", idx)
		if idx >= 2 then
			funnel(p, 14)
		end
		if idx >= PCFG.LicenceLegend then
			grantTitle(p, prog, "Legend", false)
			-- goldenes Terminal-Theme bucht refreshMaxStats (auch nach, falls der Shop gerade fehlt); das Auto
			-- „Singularity“ schaltet VehicleService über die Lizenz frei
		end
	end
	setAttributes(p, prog)
end

-- ---------------------------------------------------------------------
-- 6) ÖFFENTLICHE API
-- ---------------------------------------------------------------------
function ProgressionService.AddXp(p: Player, base: number, reason: string, opts: { NoMult: boolean? }?): number
	if not isPlayer(p) or type(reason) ~= "string" then
		return 0
	end
	local source = PCFG.XpSources[reason]
	if type(source) ~= "table" then
		logError("AddXp", "unbekannter Grund " .. reason .. " (nur Config.Progression.XpSources)")
		return 0
	end
	local prog = progOf(p)
	if not prog then
		return 0
	end
	local noMult = source.NoMult == true or (type(opts) == "table" and opts.NoMult == true)
	local before = Core.Level(prog)
	local gained = Core.AddXp(prog, base, reason, if noMult then 1 else xpMult(), today(), Util.IsoWeek())
	if gained <= 0 then
		return 0
	end
	local after = Core.Level(prog)
	if after > before then
		notify(p, "prog.levelUp", { after }, "Success")
		call("MetricsService", "Progression", p, "TraderLevel", "Complete", after)
	end
	checkLicence(p, prog)
	markDirty(p, "Prog")
	return gained
end

function ProgressionService.Licence(p: Player): number
	local prog = progOf(p)
	return if prog then prog.Licence else 1
end

function ProgressionService.LicenceDef(p: Player): Types.Licence
	return licenceDefAt(ProgressionService.Licence(p))
end

function ProgressionService.TradingPerks(p: Player): Types.TradingPerks
	local prog = progOf(p)
	if not prog then
		return Core.TradingPerks({ Licence = 1, KH = {} })
	end
	return Core.TradingPerks(prog)
end

function ProgressionService.TraderFactor(p: Player): (number, number, number)
	local prog = progOf(p)
	if not prog then
		return 1, 1, 1
	end
	return ProgressMath.TraderFactor(licenceDefAt(prog.Licence).TowerBonus, Core.RufLevel(prog))
end

function ProgressionService.Level(p: Player): number
	local prog = progOf(p)
	return if prog then Core.Level(prog) else 1
end

function ProgressionService.Ruf(p: Player): number
	local prog = progOf(p)
	return if prog then Core.RufLevel(prog) else 0
end

function ProgressionService.Stars(p: Player): number
	local prog = progOf(p)
	return if prog then Core.StarsFree(prog) else 0
end

function ProgressionService.Perk(p: Player, branch: string): number
	local prog = progOf(p)
	if not prog or type(branch) ~= "string" then
		return 0
	end
	return math.floor(num(prog.Prestige.Perks[branch], 0))
end

function ProgressionService.IpoCount(p: Player): number
	local prog = progOf(p)
	return if prog then prog.Prestige.Count else 0
end

function ProgressionService.Wealth(p: Player): number
	return wealthOf[p] or 0
end

function ProgressionService.Title(p: Player): string
	local prog = progOf(p)
	return if prog then prog.Title else ""
end

function ProgressionService.AlbumSets(p: Player): number
	local prog = progOf(p)
	return if prog then Core.AlbumSets(prog) else 0
end

function ProgressionService.Unlock(p: Player, achId: string)
	if not isPlayer(p) or type(achId) ~= "string" then
		return
	end
	local entry = PCFG.AchievementById[achId]
	local prog = progOf(p)
	if entry and prog then
		unlockAchievement(p, prog, entry)
	end
end

function ProgressionService.GrantTitle(p: Player, key: string): boolean
	if not isPlayer(p) or type(key) ~= "string" then
		return false
	end
	local prog = progOf(p)
	if not prog then
		return false
	end
	return grantTitle(p, prog, key, false)
end

-- Erfolgs-Zähler (andere WPs über RewardService.Track bzw. direkt): mode "add" (Standard) oder "max"
function ProgressionService.NoteStat(p: Player, stat: string, amount: number, mode: string?)
	if not isPlayer(p) or type(stat) ~= "string" or not finite(amount) then
		return
	end
	local mapped = STAT_FROM[stat]
	if not mapped then
		return
	end
	local prog = progOf(p)
	if not prog then
		return
	end
	if Core.Stat(prog, mapped, math.clamp(amount, 0, 1e9), mode) then
		checkAchievements(p, prog)
		markDirty(p, "Prog")
	end
end

-- Prüfungs-Aufgabe erfüllt (nur Server-Signale; Rückgabe: neu erfüllt?)
local function examDone(p: Player, prog: Data, task: string): boolean
	if not PCFG.ExamByKey[task] or prog.Exams[task] then
		return false
	end
	prog.Exams[task] = true
	notify(p, "prog.examTaskDone", { T(p, "prog.exam." .. task) }, "Success")
	checkLicence(p, prog)
	markDirty(p, "Prog")
	return true
end

function ProgressionService.ExamDone(p: Player, task: string): boolean
	if not isPlayer(p) or type(task) ~= "string" then
		return false
	end
	local prog = progOf(p)
	return prog ~= nil and examDone(p, prog, task)
end

function ProgressionService.AdminSetLicence(p: Player, idx: number): boolean
	if not isPlayer(p) then
		return false
	end
	local prog = progOf(p)
	if not prog then
		return false
	end
	local ok = Core.AdminLicence(prog, idx, function(fnName: string, arg: any)
		if fnName == "SetLicence" then
			call("OrderService", "SetLicence", p, arg)
		elseif fnName == "TaintWeek" then
			call("OrderService", "TaintWeek", p, arg) -- Admin-Gabe: Liga-Woche des Empfängers zählt nicht
		end
	end)
	if not ok then
		return false
	end
	local def = licenceDefAt(idx)
	effect(p, "LicenceUp", 1, { Licence = idx, Key = def.Key, Basis = def.Basis, BauKurs = def.BauKurs, Admin = true })
	setAttributes(p, prog)
	markDirty(p, "Prog")
	return true
end

-- ---------------------------------------------------------------------
-- 7) SIGNALE: TRADES, BÖRSENTAGE, GLOCKE, NEWS, TURM
-- ---------------------------------------------------------------------
local function ensureDay(p: Player, data: Data)
	local day = today()
	if data.LastUtcDay ~= day then
		Core.DayRoll(data, day)
		markDirty(p, "Prog")
	end
end

local function sectorOf(i: number): string?
	local def = instDef(i)
	if not def or def.Class == SECTOR_ETF or def.Set == "Tutorial" then
		return nil
	end
	return def.Sector
end

local function heldSectors(data: Data): number
	local depot = data.Depot
	local pos = if type(depot) == "table" then depot.Pos else nil
	local seen: { [string]: boolean } = {}
	local n = 0
	if type(pos) == "table" then
		for key, position in pairs(pos) do
			local i = tonumber(key)
			if i and type(position) == "table" and num(position.Q, 0) > 0 then
				local sector = sectorOf(i)
				if sector and not seen[sector] then
					seen[sector] = true
					n += 1
				end
			end
		end
	end
	return n
end

local function holdsAny(data: Data): boolean
	local depot = data.Depot
	if type(depot) ~= "table" or type(depot.Pos) ~= "table" then
		return false
	end
	for _, position in pairs(depot.Pos) do
		if type(position) == "table" and num(position.Q, 0) > 0 then
			return true
		end
	end
	return false
end

local function holds(data: Data, i: number): boolean
	local depot = data.Depot
	local pos = if type(depot) == "table" and type(depot.Pos) == "table" then depot.Pos[tostring(i)] else nil
	return type(pos) == "table" and num(pos.Q, 0) > 0
end

local function watches(data: Data, i: number): boolean
	local depot = data.Depot
	if type(depot) ~= "table" or type(depot.Watch) ~= "table" then
		return false
	end
	for _, list in ipairs(depot.Watch) do
		if type(list) == "table" and table.find(list, i) then
			return true
		end
	end
	return false
end

local function albumAdd(p: Player, prog: Data, i: number)
	local isNew, setSector = Core.AlbumAdd(prog, i)
	if not isNew then
		return
	end
	Core.Stat(prog, "AlbumCards", Core.AlbumCards(prog), "max")
	Core.Stat(prog, "AlbumSets", Core.AlbumSets(prog), "max")
	local def = instDef(i)
	if setSector then
		local sectorName = setSector
		for _, sector in ipairs(companies().Sectors or {}) do
			if sector.Key == setSector and type(sector.Name) == "table" then
				sectorName = Lang.Pick(langOf(p), sector.Name)
			end
		end
		notify(p, "prog.albumSet", { sectorName }, "Success")
	elseif def then
		notify(p, "prog.albumCard", { def.Ticker }, "Info")
	end
end

local function onTrade(p: Player, fill: Types.FillInfo)
	if not isPlayer(p) or type(fill) ~= "table" then
		return
	end
	local prog, data = progOf(p)
	if not prog or not data then
		return
	end
	ensureDay(p, data)
	local i = fill.I
	if fill.Side == "B" then
		albumAdd(p, prog, i)
		if fill.Bot then
			markDirty(p, "Prog")
			return -- Bots handeln still: keine XP, keine Quests, keine Prüfungen
		end
		-- jüngste Käufe (für "★★★-Analyst" und Quartalszahlen-Quests), begrenzt
		local buys = recentBuys[p]
		if not buys then
			buys = {}
			recentBuys[p] = buys
		end
		buys[i] = fill.Tick
		local count = 0
		for _ in pairs(buys) do
			count += 1
		end
		if count > MAX_RECENT_BUYS then
			local oldestI, oldestT = nil, math.huge
			for inst, t in pairs(buys) do
				if t < oldestT then
					oldestI, oldestT = inst, t
				end
			end
			if oldestI then
				buys[oldestI] = nil
			end
		end
		if fill.Protected then
			examDone(p, prog, "ProtectPair")
		end
		local held = heldSectors(data)
		Core.Stat(prog, "Sectors", held, "max")
		if held >= PCFG.Exam.Sectors then
			examDone(p, prog, "Sectors3")
		end
		-- "Kaufe in einem neuen Sektor": erster Kauf je Sektor und UTC-Tag
		local sector = sectorOf(i)
		if sector then
			local day = today()
			local entry = sectorsToday[p]
			if not entry or entry.Day ~= day then
				entry = { Day = day, Set = {} }
				sectorsToday[p] = entry
			end
			if not entry.Set[sector] then
				entry.Set[sector] = true
				track(p, "NewSector", 1, { Sector = sector })
			end
		end
		-- "Kaufe nach einer guten Nachricht": Fakten-Nachricht in Kaufrichtung ≤ 60 s vorher
		local okNews, news = call("MarketService", "FactNewsFor", i, fill.Tick, PCFG.Exam.GoodNewsSeconds)
		if okNews and type(news) == "table" and num(news.Dir, 0) > 0 then
			examDone(p, prog, "BuyAfterGood")
		end
		local flags = data.Flags
		if type(flags) == "table" and flags.FirstLiveTrade ~= true then
			flags.FirstLiveTrade = true
			funnel(p, 11)
			markDirty(p, "Flags")
		end
	elseif fill.Side == "S" and not fill.Bot then
		local trading = Config.Trading or {}
		local counting = num(fill.PctNav, 0) >= num(trading.MinTradePct, 0.02)
			and num(fill.HeldS, 0) >= num(trading.MinHoldSeconds, 60)
		if counting then
			ProgressionService.AddXp(p, PCFG.XpSources.Trade.Xp, "Trade")
			Core.Stat(prog, "Trades", 1)
			if num(fill.Pnl, 0) > 0 then
				ProgressionService.AddXp(p, PCFG.XpSources.TradeProfit.Xp, "TradeProfit")
				Core.Stat(prog, "ProfitTrades", 1)
				track(p, "TradeProfit", 1, { I = i })
				if fill.Protected then
					examDone(p, prog, "ProtectedProfit")
				end
			end
			if fill.Protected then
				ProgressionService.AddXp(p, PCFG.XpSources.TradeProtected.Xp, "TradeProtected")
				Core.Stat(prog, "ProtectedTrades", 1)
				track(p, "TradeProtected", 1, { I = i })
			end
		end
		if fill.ReadWell then
			ProgressionService.AddXp(p, PCFG.XpSources.ReadWell.Xp, "ReadWell")
			Core.Stat(prog, "ReadWell", 1)
			examDone(p, prog, "BuyAfterGood")
		end
	end
	checkAchievements(p, prog)
	markDirty(p, "Prog")
end

local function checkLeagueExams(p: Player, prog: Data, data: Data)
	local ok, stats = call("OrderService", "LeagueStats", p)
	local league = data.League
	local exam = PCFG.Exam
	local tierLevel = 0
	if ok and type(stats) == "table" then
		if
			not stats.Tainted
			and num(stats.SkillScore, 0) >= exam.SkillMin
			and num(stats.Days, 0) >= exam.SkillMinDays
		then
			examDone(p, prog, "Skill500")
		end
		if stats.Qualified then
			local score = num(stats.SkillScore, 0)
			for _, tier in ipairs((Config.Trading or {}).League and Config.Trading.League.Tiers or {}) do
				if score >= num(tier.Min, math.huge) then
					tierLevel = math.max(tierLevel, TIER_LEVEL[tier.Key] or 0)
				end
			end
		end
	end
	if type(league) == "table" then
		if league.LastQualified == true and num(league.LastScore, 0) >= exam.SkillMin then
			examDone(p, prog, "Skill500")
		end
		tierLevel = math.max(tierLevel, TIER_LEVEL[league.LastTier] or 0)
		-- Drawdown-Aufgabe aus der laufenden Woche: mindestens DrawdownMinDays zählende Börsentage, nicht getaintet
		local returns = league.Returns
		if
			type(returns) == "table"
			and #returns >= exam.DrawdownMinDays
			and num(league.Days, 0) >= exam.DrawdownMinDays
			and league.Tainted ~= true
		then
			if
				ProgressMath.MaxDrawdown(returns) < exam.DrawdownMax
				and ProgressMath.AvgDaily(returns) >= exam.AvgDailyMin
			then
				examDone(p, prog, "LowDrawdown")
			end
		end
	end
	if tierLevel >= 3 then
		examDone(p, prog, "LeagueGold")
	end
	if tierLevel >= 4 then
		examDone(p, prog, "LeagueDiamond")
	end
	Core.Stat(prog, "LeagueTier", tierLevel, "max")
end

-- Saison-XP je zählendem Börsentag (Config.Season.XpSources.CountingDay.Xp, Standard 25)
local function countingDaySeasonXp(): number
	local season = Config.Season
	local sources = if type(season) == "table" then season.XpSources else nil
	local entry = if type(sources) == "table" then sources.CountingDay else nil
	return if type(entry) == "table" then num(entry.Xp, 25) else 25
end

local function onDayResult(p: Player, result: Types.DayResult)
	if not isPlayer(p) or type(result) ~= "table" then
		return
	end
	local prog, data = progOf(p)
	if not prog or not data then
		return
	end
	ensureDay(p, data)
	if result.Qualifying then
		local r = num(result.Return, 0)
		local ruf = PCFG.Ruf
		local points = ruf.DayBase
			+ (if r > 0 then ruf.DayPositive else 0)
			+ (if r >= ruf.StrongReturn then ruf.DayStrong else 0)
		Core.AddRuf(prog, points, today(), true)
		call("RewardService", "GrantSeasonXp", p, countingDaySeasonXp(), "CountingDay")
		if r > 0 then
			ProgressionService.AddXp(p, PCFG.XpSources.PositiveDay.Xp, "PositiveDay")
			Core.Stat(prog, "PositiveDays", 1)
			local run = num(prog.AchProgress.PosRun, 0) + 1
			prog.AchProgress.PosRun = run
			Core.Stat(prog, "PosStreak", run, "max")
			track(p, "PositiveDay", 1, { Return = r })
		else
			prog.AchProgress.PosRun = 0
		end
	end
	checkLeagueExams(p, prog, data)
	checkAchievements(p, prog)
	markDirty(p, "Prog")
end

local function inBellZone(p: Player): boolean
	local character = p.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local ok, cf = call("CityService", "Anchor", "BellZone")
	local center: Vector3
	if ok and typeof(cf) == "CFrame" then
		center = cf.Position
	else
		local zones = (Config.City or {}).Zones
		local plaza = zones and zones.Plaza
		if not plaza then
			return false
		end
		center = plaza.Center
	end
	local radius = 18
	local zones = (Config.City or {}).Zones
	if zones and zones.Plaza and finite(zones.Plaza.BellZoneRadius) then
		radius = zones.Plaza.BellZoneRadius
	end
	local offset = root.Position - center
	return Vector2.new(offset.X, offset.Z).Magnitude <= radius + 2 and math.abs(offset.Y) < 40
end

local function onBell(p: Player)
	if not isPlayer(p) then
		return
	end
	local data = dataOf(p)
	if not data then
		return
	end
	if holdsAny(data) then
		track(p, "HoldThroughBell", 1, nil)
	end
	if inBellZone(p) then
		track(p, "Bell", 1, nil) -- RewardService zählt Quest + Erfolg (NoteStat "Bell")
	end
end

local READ_NEWS_KINDS: { [string]: boolean } = { Macro = true, Sector = true, Crash = true, Rally = true, Ipo = true }

local function onNews(n: Types.NewsItem)
	if type(n) ~= "table" or type(n.Kind) ~= "string" then
		return
	end
	local isCrash = n.Kind == "Crash"
	local isEarnings = n.Kind == "Earnings" and n.I ~= nil and finite(n.Dir) and n.Dir ~= 0
	local exam = PCFG.Exam
	for _, p in ipairs(Players:GetPlayers()) do
		local ok, ready = call("PlayerStateService", "IsReady", p)
		if not ok or ready ~= true then
			continue
		end
		local data = dataOf(p)
		if not data then
			continue
		end
		-- "Lies Eilmeldungen": Nachrichten, die auch die News-Karte zeigen würde (§B7.4)
		local relevant = READ_NEWS_KINDS[n.Kind] == true
		if not relevant and n.I ~= nil and num(n.Band, 0) >= 2 then
			relevant = holds(data, n.I) or watches(data, n.I)
		end
		if relevant then
			track(p, "ReadNews", 1, { Kind = n.Kind })
		end
		-- Crash-Prüfung: investiert in den Crash (≥ 10 % des Depotwerts), Ergebnis nach dem Fenster
		if isCrash and not crashWatch[p] then
			local okNav, nav = call("OrderService", "Nav", p)
			local depot = data.Depot
			local cash = if type(depot) == "table" then num(depot.Cash, 0) else 0
			if okNav and finite(nav) and nav > 0 and (nav - cash) / nav >= exam.CrashMinExposure then
				local prog = progOf(p)
				local failTick = if prog then num(prog.ExamProgress.CrashFail, -math.huge) else -math.huge
				local okTick, tick = call("MarketService", "Tick")
				local nowTick = if okTick and finite(tick) then tick else 0
				if nowTick - failTick >= exam.RetryTicks then
					crashWatch[p] = {
						Nav0 = nav,
						Basis0 = if type(depot) == "table" then num(depot.Basis, 0) else 0,
						Until = os.clock() + exam.CrashSeconds,
					}
				end
			end
		end
		-- "★★★-Analyst bei Quartalszahlen": Kauf ≤ 5 min vor den Zahlen, Zahlen in Kaufrichtung, noch gehalten
		if isEarnings then
			local buys = recentBuys[p]
			local t = buys and buys[n.I :: number]
			if
				t
				and finite(n.T)
				and t <= n.T
				and n.T - t <= exam.EarningsLeadSeconds
				and holds(data, n.I :: number)
			then
				buys[n.I :: number] = nil
				local prog = progOf(p)
				if prog then
					Core.Stat(prog, "EarningsTrades", 1)
					track(p, "EarningsTrade", 1, { I = n.I })
					if (n.Dir :: number) > 0 then
						examDone(p, prog, "Analyst3")
					end
					checkAchievements(p, prog)
					markDirty(p, "Prog")
				end
			end
		end
	end
end

local function crashTick()
	local now = os.clock()
	for p, watch in pairs(crashWatch) do
		if p.Parent ~= Players then
			crashWatch[p] = nil
		elseif now >= watch.Until then
			crashWatch[p] = nil
			local prog, data = progOf(p)
			local okNav, nav = call("OrderService", "Nav", p)
			if prog and data and okNav and finite(nav) and watch.Nav0 > 0 then
				-- Basis-Erhöhung (Lizenz-Aufstieg) ist ein Fluss, kein Gewinn -> herausrechnen
				local depot = data.Depot
				local basisNow = if type(depot) == "table" then num(depot.Basis, watch.Basis0) else watch.Basis0
				local adjusted = nav - math.max(0, basisNow - watch.Basis0)
				local loss = 1 - adjusted / watch.Nav0
				if loss < PCFG.Exam.CrashMaxLoss then
					Core.Stat(prog, "CrashSurvived", 1)
					examDone(p, prog, "CrashSurvive")
					notify(p, "prog.crashSurvived", nil, "Success")
				elseif not prog.Exams.CrashSurvive then
					local okTick, tick = call("MarketService", "Tick")
					prog.ExamProgress.CrashFail = if okTick and finite(tick) then tick else 0
					notify(p, "prog.examCrashFailed", nil, "Info")
				end
				checkAchievements(p, prog)
				markDirty(p, "Prog")
			end
		end
	end
end

local function onStage(p: Player, stage: number)
	if not isPlayer(p) or not finite(stage) then
		return
	end
	local prog = progOf(p)
	if prog then
		Core.Stat(prog, "Stage", stage, "max")
		checkAchievements(p, prog)
		awardBadges(p, prog)
		markDirty(p, "Prog")
	end
end

local function onFloor(p: Player, floor: number, stage: number)
	if not isPlayer(p) or not finite(floor) then
		return
	end
	local prog = progOf(p)
	if prog then
		Core.Stat(prog, "Floors", floor, "max")
		if finite(stage) then
			Core.Stat(prog, "Stage", stage, "max")
		end
		checkAchievements(p, prog)
		awardBadges(p, prog)
		markDirty(p, "Prog")
	end
end

-- ---------------------------------------------------------------------
-- 8) PERIODISCH JE SPIELER (alle 5 s, gestaffelt): Vermögen, Höchstwerte, Erfolge, Badges, Anzeige
-- ---------------------------------------------------------------------
local function countKeys(t: any): number
	local n = 0
	if type(t) == "table" then
		for _, v in pairs(t) do
			if v == true or (finite(v) and v > 0) then
				n += 1
			end
		end
	end
	return n
end

local function computeWealth(p: Player, prog: Data, data: Data): number
	local okCr, balance = call("ShopService", "Balance", p)
	local cr = if okCr and finite(balance) then balance else num(data.Credits, 0)
	local okTv, towerValue = call("TowerService", "TowerValue", p)
	local okCars, cars = call("VehicleService", "CollectionValue", p)
	local okLife, life = call("LifestyleService", "CollectionValue", p)
	local okNav, nav = call("OrderService", "Nav", p)
	-- Vehicle-/LifestyleService liefern die Summe der Kaufpreise; zum Vermögen zählen davon 50 % (§B9.5)
	local prices = (if okCars and finite(cars) then cars else 0) + (if okLife and finite(life) then life else 0)
	return Core.Wealth({
		Credits = cr,
		TowerValue = if okTv and finite(towerValue) then towerValue else 0,
		Firm = prog.Prestige.Firmenwert,
		Collection = math.max(0, prices) * num(PCFG.WealthCollectionPct, 0.5),
		NavCents = if okNav and finite(nav) then nav else 0,
	}, licenceDefAt(prog.Licence).BauKurs)
end

local function refreshMaxStats(p: Player, prog: Data, data: Data)
	local okFloors, floors = call("TowerService", "Floors", p)
	if okFloors and finite(floors) then
		Core.Stat(prog, "Floors", floors, "max")
	end
	local okStage, stage = call("TowerService", "Stage", p)
	if okStage and finite(stage) then
		Core.Stat(prog, "Stage", stage, "max")
	end
	local tower = data.Tower
	if type(tower) == "table" then
		Core.Stat(prog, "Eff", num(tower.Eff, 0), "max")
	end
	Core.Stat(prog, "Ipos", prog.Prestige.Count, "max")
	Core.Stat(prog, "Licence", prog.Licence, "max")
	local lessons, perfect = 0, 0
	for _, value in pairs(prog.Lessons) do
		lessons += 1
		if value >= 2 then
			perfect += 1
		end
	end
	Core.Stat(prog, "Lessons", lessons, "max")
	Core.Stat(prog, "Perfect", perfect, "max")
	Core.Stat(prog, "KHSpent", Core.KhSpent(prog), "max")
	Core.Stat(prog, "AlbumCards", Core.AlbumCards(prog), "max")
	Core.Stat(prog, "AlbumSets", Core.AlbumSets(prog), "max")
	local garage = data.Garage
	Core.Stat(prog, "Cars", countKeys(if type(garage) == "table" then garage.Cars else nil), "max")
	local life = data.Life
	Core.Stat(prog, "Watches", countKeys(if type(life) == "table" then life.Watches else nil), "max")
	local storage = data.Storage
	Core.Stat(prog, "DecorKinds", countKeys(if type(storage) == "table" then storage.Decor else nil), "max")
	local login = data.Login
	if type(login) == "table" then
		Core.Stat(prog, "LoginStreak", num(login.Best, 0), "max")
	end
	-- Börsen-Legende: goldenes Terminal-Theme nachbuchen, falls der Shop beim Aufstieg nicht erreichbar war
	local cosmetic = PCFG.LegendCosmetic
	if prog.Licence >= PCFG.LicenceLegend and type(cosmetic) == "string" then
		local purchases = data.Purchases
		local owned = if type(purchases) == "table" then purchases.Cosmetics else nil
		local has = type(owned) == "table" and (owned[cosmetic] == true or table.find(owned, cosmetic) ~= nil)
		if not has then
			call("ShopService", "Grant", p, { Cosmetics = { cosmetic } }, "Achievement")
		end
	end
	-- Tutorial-Übung (ACAD) lief mit "Schutz an" -> Aufgabe "Setze ein Schutz-Paar" erfüllt (§B2 ~7:00)
	if not prog.Exams.ProtectPair then
		local okTut, state = call("OrderService", "TutorialState", p)
		if okTut and state == "Done" then
			examDone(p, prog, "ProtectPair")
		end
	end
end

local function playerTick(p: Player)
	if not isPlayer(p) then
		return
	end
	local okReady, ready = call("PlayerStateService", "IsReady", p)
	if not okReady or ready ~= true then
		return
	end
	local prog, data = progOf(p)
	if not prog or not data then
		return
	end
	ensureDay(p, data)
	local before = table.clone(prog.AchProgress)
	refreshMaxStats(p, prog, data)
	local wealth = computeWealth(p, prog, data)
	local old = wealthOf[p]
	wealthOf[p] = wealth
	Core.Stat(prog, "Wealth", wealth, "max")
	if old ~= wealth then
		call("PlayerStateService", "SetLeaderstat", p, "Vermögen", wealth)
		call("LeaderboardService", "Submit", p)
	end
	updateWealthTitle(p, prog, wealth)
	checkLeagueExams(p, prog, data)
	checkAchievements(p, prog)
	awardBadges(p, prog)
	retryPendingRewards(p, prog)
	local changed = old ~= wealth
	if not changed then
		for key, value in pairs(prog.AchProgress) do
			if before[key] ~= value then
				changed = true
				break
			end
		end
	end
	if changed then
		markDirty(p, "Prog")
	end
end

-- ---------------------------------------------------------------------
-- 9) STATE "Prog" (§C10)
-- ---------------------------------------------------------------------
local function progState(p: Player): { [string]: any }
	local prog, data = progOf(p)
	if not prog or not data then
		return {
			Xp = 0,
			Level = 1,
			Licence = 1,
			Exams = {},
			KnowHow = {},
			KH = 0,
			Ruf = 0,
			RufPts = 0,
			Title = "",
			Titles = {},
			Album = {},
			Ach = {},
			Stars = 0,
			Perks = {},
			Ipos = 0,
		}
	end
	local level, progress = ProgressMath.LevelFromXp(prog.Xp)
	local nextIdx = math.min(prog.Licence + 1, #PCFG.Licences)
	local titles = {}
	for key in pairs(prog.Titles) do
		table.insert(titles, key)
	end
	table.sort(titles)
	local total, licPart, rufPart =
		ProgressMath.TraderFactor(licenceDefAt(prog.Licence).TowerBonus, Core.RufLevel(prog))
	local ph, phUntil = powerHourInfo()
	local tickers = {}
	for i = 1, math.min(5, #prog.Prestige.Tickers) do
		table.insert(tickers, prog.Prestige.Tickers[i].T)
	end
	local rufLevel = Core.RufLevel(prog)
	local thresholds = PCFG.Ruf.Thresholds
	return {
		Xp = prog.Xp,
		Level = level,
		LevelProgress = progress,
		NextLevelXp = ProgressMath.XpForLevel(math.min(level + 1, PCFG.MaxLevel)),
		Licence = prog.Licence,
		Exams = prog.Exams,
		ExamTasks = if prog.Licence < #PCFG.Licences then Core.ExamTasks(prog, nextIdx) else {},
		NextLicenceXp = if prog.Licence < #PCFG.Licences then PCFG.Licences[nextIdx].Xp else 0,
		CrashFail = num(prog.ExamProgress.CrashFail, 0),
		Lessons = prog.Lessons,
		KnowHow = prog.KH,
		KH = Core.KhFree(prog),
		KHTotal = Core.KhTotal(prog),
		KHSpent = Core.KhSpent(prog),
		KHResetFree = prog.KHResetWeek ~= Util.IsoWeek(),
		Ruf = rufLevel,
		RufPts = prog.Ruf,
		RufToday = if prog.RufDay == today() then prog.RufToday else 0,
		RufNext = thresholds[math.min(ProgressMath.RufLevel(prog.Ruf) + 1, #thresholds)],
		Factor = { Total = total, Licence = licPart, Ruf = rufPart },
		Title = prog.Title,
		Titles = titles,
		Album = prog.Album,
		AlbumSets = Core.AlbumSets(prog),
		Ach = prog.Ach,
		AchProgress = prog.AchProgress,
		Badges = prog.Badges,
		Stars = Core.StarsFree(prog),
		StarsTotal = prog.Prestige.Stars,
		Perks = prog.Prestige.Perks,
		Ipos = prog.Prestige.Count,
		Firm = prog.Prestige.Firmenwert,
		Tickers = tickers,
		RespecFree = prog.Prestige.RespecFree,
		Wealth = wealthOf[p] or 0,
		Tools = Core.TradingPerks(prog),
		PowerHour = ph,
		PowerHourUntil = phUntil,
		XpMult = xpMult(),
	}
end

-- ---------------------------------------------------------------------
-- 10) ANFRAGEN (§C9)
-- ---------------------------------------------------------------------
local function handleLesson(p: Player, arg: any): Reply
	if not exactKeys(arg, { "Id", "Answers" }) or type(arg.Id) ~= "string" or type(arg.Answers) ~= "table" then
		return fail(p, "core.invalid")
	end
	local lesson = PCFG.LessonById[arg.Id]
	if not lesson then
		return fail(p, "prog.lessonUnknown")
	end
	local prog, data = progOf(p)
	if not prog or not data then
		return fail(p, "core.loading")
	end
	-- Mindest-Lesezeit zwischen zwei Abgaben derselben Lektion (gegen Durchklicken)
	local stamps = lessonAt[p]
	if not stamps then
		stamps = {}
		lessonAt[p] = stamps
	end
	local now = os.clock()
	local gap = lesson.Cards * PCFG.Academy.MinCardSeconds
	if stamps[lesson.Id] and now - stamps[lesson.Id] < gap then
		return fail(p, "prog.lessonTooFast")
	end
	local correct, total = Core.LessonResult(lesson.Id, arg.Answers, QUIZ_KEY)
	if not correct or not total then
		return fail(p, "core.invalid")
	end
	stamps[lesson.Id] = now
	local pass = correct >= math.ceil(total * PCFG.Academy.PassRatio)
	if not pass then
		return { Ok = false, Message = T(p, "prog.lessonFail", correct, total), Correct = correct, Total = total }
	end
	ensureDay(p, data)
	local perfect = correct == total
	local before = prog.Lessons[lesson.Id]
	local firstEver = next(prog.Lessons) == nil
	local gained = 0
	if before == nil then
		gained += ProgressionService.AddXp(p, PCFG.XpSources.LessonFirst.Xp, "LessonFirst")
	else
		gained += ProgressionService.AddXp(p, PCFG.XpSources.LessonRepeat.Xp, "LessonRepeat")
	end
	if perfect and before ~= 2 then
		gained += ProgressionService.AddXp(p, PCFG.XpSources.LessonPerfect.Xp, "LessonPerfect")
	end
	prog.Lessons[lesson.Id] = math.max(num(before, 0), if perfect then 2 else 1)
	if firstEver then
		Core.AddRuf(prog, PCFG.Ruf.FirstLesson, today(), false)
	end
	if lesson.Id == "L01" and before == nil then
		funnel(p, 13)
	end
	for _, task in ipairs(PCFG.ExamTasks) do
		if task.Source == "Lesson" and task.Lesson == lesson.Id and perfect then
			examDone(p, prog, task.Key)
		end
	end
	track(p, "Lesson", 1, { Id = lesson.Id })
	refreshMaxStats(p, prog, data)
	checkLicence(p, prog)
	checkAchievements(p, prog)
	markDirty(p, "Prog")
	local key = if perfect then "prog.lessonPerfect" else "prog.lessonDone"
	return {
		Ok = true,
		Message = T(p, key, correct, total, gained),
		Correct = correct,
		Total = total,
		Xp = gained,
		Perfect = perfect,
	}
end

local function handleExam(p: Player, arg: any): Reply
	if not exactKeys(arg, { "Licence" }) or not isInt(arg.Licence) then
		return fail(p, "core.invalid")
	end
	local prog = progOf(p)
	if not prog then
		return fail(p, "core.loading")
	end
	if prog.Licence >= #PCFG.Licences then
		return fail(p, "prog.examMax")
	end
	local idx = arg.Licence
	if idx ~= prog.Licence + 1 then
		return fail(p, "prog.examWrongLicence")
	end
	local def = PCFG.Licences[idx]
	local tasks = Core.ExamTasks(prog, idx)
	local lang = langOf(p)
	if prog.Xp < def.Xp then
		local reply = fail(p, "prog.examNeedXp", Format.Int(def.Xp - prog.Xp, lang), Lang.Pick(lang, def.Name))
		reply.Tasks = tasks
		return reply
	end
	for _, task in ipairs(tasks) do
		if not task.Done then
			local reply = fail(p, "prog.examTasks")
			reply.Tasks = tasks
			return reply
		end
	end
	checkLicence(p, prog)
	markDirty(p, "Prog")
	return { Ok = true, Message = T(p, "prog.examPassed", Lang.Pick(lang, def.Name)), Passed = true, Tasks = tasks }
end

local function handleKnowHow(p: Player, arg: any): Reply
	if not exactKeys(arg, { "Node" }) or type(arg.Node) ~= "string" or #arg.Node > 40 then
		return fail(p, "core.invalid")
	end
	local prog = progOf(p)
	if not prog then
		return fail(p, "core.loading")
	end
	local ok, key, args = Core.BuyNode(prog, arg.Node)
	if not ok then
		if key == "prog.khLocked" and args then
			local lang = langOf(p)
			return fail(p, key, Lang.Pick(lang, licenceDefAt(args[1]).Name))
		end
		return fail(p, key)
	end
	markDirty(p, "Prog")
	return {
		Ok = true,
		Message = T(p, key, T(p, "prog.kh." .. arg.Node), (args :: { any })[1]),
		Level = prog.KH[arg.Node],
	}
end

local function handleKnowHowReset(p: Player, arg: any): Reply
	if arg ~= nil and (type(arg) ~= "table" or next(arg) ~= nil) then
		return fail(p, "core.invalid")
	end
	local prog = progOf(p)
	if not prog then
		return fail(p, "core.loading")
	end
	local ok, key = Core.ResetNodes(prog, Util.IsoWeek())
	if not ok then
		return fail(p, key)
	end
	markDirty(p, "Prog")
	return { Ok = true, Message = T(p, key) }
end

-- Initialen des Tower-Namens (Wortbausteine) als Ticker-Rückfall
local function fallbackTicker(p: Player, data: Data, blocked: (string) -> boolean): string
	local tower = data.Tower
	local names = (Config.Tower or {}).Names
	local letters = ""
	if type(tower) == "table" and type(tower.Name) == "table" and type(names) == "table" then
		local adj = names.Adj and names.Adj[tower.Name.A]
		local noun = names.Noun and names.Noun[tower.Name.N]
		for _, part in ipairs({ adj, noun }) do
			local text = if type(part) == "table" then (part.de or part.en) else part
			if type(text) == "string" then
				local first = string.match(text, "%a")
				if first then
					letters ..= string.upper(first)
				end
			end
		end
	end
	if #letters < 2 then
		local name = string.gsub(string.upper(p.Name), "[^A-Z]", "")
		letters = string.sub(name .. "TW", 1, 2)
	end
	local candidate = letters .. "T"
	if not blocked(candidate) then
		return candidate
	end
	for code = string.byte("A"), string.byte("Z") do
		local guess = letters .. "T" .. string.char(code)
		if not blocked(guess) then
			return guess
		end
	end
	return "TWR" .. string.char(string.byte("A") + (p.UserId % 26 + 26) % 26)
end

local tickerBlockSet: { [string]: boolean } = {}
for _, word in ipairs(PCFG.TickerBlock) do
	tickerBlockSet[word] = true
end

local function tickerBlocked(ticker: string): boolean
	if tickerBlockSet[ticker] then
		return true
	end
	for _, inst in ipairs(companies().Instruments or {}) do
		if type(inst) == "table" and inst.Ticker == ticker then
			return true
		end
	end
	return false
end

-- Börsengang erlaubt? (ok, Grund-Schlüssel, Argumente)
local function ipoEligible(p: Player, prog: Data): (boolean, string?, { any }?)
	local okFloors, floors = call("TowerService", "Floors", p)
	local floorCount = if okFloors and finite(floors) then floors else 0
	if floorCount < PCFG.Prestige.MinFloor then
		return false, "prog.ipoNotYet", { PCFG.Prestige.MinFloor }
	end
	local nextIpo = prog.Prestige.Count + 1
	if licenceDefAt(prog.Licence).MaxIpo < nextIpo then
		-- kleinste Lizenz, die diesen Börsengang erlaubt
		for i, def in ipairs(PCFG.Licences) do
			if def.MaxIpo >= nextIpo then
				return false, "prog.ipoLicence", { nextIpo, i }
			end
		end
		return false, "prog.ipoLicence", { nextIpo, #PCFG.Licences }
	end
	return true, nil, nil
end

local function estimateSeconds(prog: Data): number
	local blitz = math.floor(num(prog.Prestige.Perks.Blitzstart, 0))
	local blitzFloors = 0
	local blitzDef = PCFG.PerkByKey.Blitzstart
	if blitz > 0 and blitzDef and blitzDef.Floors then
		blitzFloors = blitzDef.Floors[math.min(blitz, #blitzDef.Floors)] or 0
	end
	local tempo = math.floor(num(prog.Prestige.Perks.Tempo, 0))
	local tempoDef = PCFG.PerkByKey.Tempo
	local speed = math.max(0.25, 1 - num(tempoDef and tempoDef.Step, 0.10) * tempo)
	-- Ziel: erste Etage der Vorschau-Stufe (Stufe 7 = Etage 18) aus Config.Tower.Stages, sonst der Config-Rückfall
	local target = math.floor(num(PCFG.Prestige.EstimateFloors, 18))
	local stages = (Config.Tower or {}).Stages
	local stageDef = if type(stages) == "table" then stages[PCFG.Prestige.EstimateStage or 7] else nil
	if type(stageDef) == "table" and isInt(stageDef.First) then
		target = stageDef.First
	end
	local total = 0
	for n = blitzFloors + 1, target do
		local ok, seconds = pcall(TowerMath.BuildSeconds, n, speed)
		if ok and finite(seconds) then
			total += seconds
		end
	end
	return math.floor(total * PCFG.Prestige.EstimateFactor)
end

local function handleIpoPreview(p: Player, arg: any): Reply
	if arg ~= nil and (type(arg) ~= "table" or next(arg) ~= nil) then
		return fail(p, "core.invalid")
	end
	local prog, data = progOf(p)
	if not prog or not data then
		return fail(p, "core.loading")
	end
	local okStage, stage = call("TowerService", "Stage", p)
	if not okStage or not finite(stage) or stage < PCFG.Prestige.PreviewStage then
		return fail(p, "prog.ipoPreviewStage", PCFG.Prestige.PreviewStage)
	end
	local okSpend, spend = call("TowerService", "RunSpend", p)
	local runSpend = if okSpend and finite(spend) then spend else 0
	local eligible, reason, args = ipoEligible(p, prog)
	local lang = langOf(p)
	local reasonText: string? = nil
	if reason == "prog.ipoLicence" and args then
		reasonText = T(p, reason, args[1], Lang.Pick(lang, licenceDefAt(args[2]).Name))
	elseif reason then
		reasonText = T(p, reason, table.unpack(args or {}))
	end
	local token = HttpService:GenerateGUID(false)
	ipoTokens[p] = { Token = token, Until = os.clock() + PCFG.Prestige.TokenSeconds }
	local nextCount = prog.Prestige.Count + 1
	return {
		Ok = true,
		Token = token,
		Stars = ProgressMath.Stars(runSpend),
		RunSpend = runSpend,
		Firm = ProgressMath.Clamp(PCFG.Prestige.FirmPct * runSpend),
		Count = prog.Prestige.Count,
		Next = nextCount,
		Crown = Core.CrownFor(nextCount),
		Perm = PCFG.Prestige.PermStep,
		Eligible = eligible,
		Reason = reasonText,
		EstimateSeconds = estimateSeconds(prog),
		Suggest = fallbackTicker(p, data, tickerBlocked),
	}
end

-- TextService-Filter: true = Text darf öffentlich gezeigt werden (Fehler = nein)
local function filterOk(p: Player, text: string): boolean
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, p.UserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	return ok and result == text
end

local function handleIpo(p: Player, arg: any): Reply
	if not exactKeys(arg, { "Ticker", "Token" }) or type(arg.Ticker) ~= "string" or type(arg.Token) ~= "string" then
		return fail(p, "core.invalid")
	end
	if #arg.Ticker > 8 or #arg.Token > 64 then
		return fail(p, "core.invalid")
	end
	if ipoBusy[p] then
		return fail(p, "core.tooFast")
	end
	local token = ipoTokens[p]
	if not token or token.Token ~= arg.Token or os.clock() > token.Until then
		return fail(p, "prog.ipoToken")
	end
	local prog, data = progOf(p)
	if not prog or not data then
		return fail(p, "core.loading")
	end
	local eligible, reason, args = ipoEligible(p, prog)
	if not eligible then
		if reason == "prog.ipoLicence" and args then
			return fail(p, reason, args[1], Lang.Pick(langOf(p), licenceDefAt(args[2]).Name))
		end
		return fail(p, reason or "prog.ipoFailed", table.unpack(args or {}))
	end
	local wanted = string.upper(arg.Ticker)
	if not string.match(wanted, TICKER_PATTERN) then
		return fail(p, "prog.ipoTicker")
	end
	ipoBusy[p] = true
	local ticker = wanted
	local replaced = false
	if tickerBlocked(wanted) or not filterOk(p, wanted) then
		ticker = fallbackTicker(p, data, tickerBlocked)
		replaced = true
	end
	ipoBusy[p] = nil
	-- nach dem Filter (yield): Zustand neu prüfen, Token verbrauchen
	if p.Parent ~= Players then
		return { Ok = false }
	end
	local again = ipoTokens[p]
	if not again or again.Token ~= arg.Token then
		return fail(p, "prog.ipoToken")
	end
	ipoTokens[p] = nil
	prog, data = progOf(p)
	if not prog or not data then
		return fail(p, "core.loading")
	end
	if not ipoEligible(p, prog) then
		return fail(p, "prog.ipoFailed")
	end
	local okSpend, spend = call("TowerService", "RunSpend", p)
	local runSpend = if okSpend and finite(spend) then spend else 0
	local snapshot = Util.DeepCopy(prog.Prestige)
	local stars = Core.ApplyIpo(prog, runSpend, ticker, os.time())
	local okReset, reset = call("TowerService", "ResetForIpo", p, Core.PerkTable(prog))
	if not okReset or reset ~= true then
		prog.Prestige = snapshot -- alles oder nichts
		return fail(p, "prog.ipoFailed")
	end
	local count = prog.Prestige.Count
	if type(data.Stats) == "table" then
		data.Stats.Ipos = math.floor(num(data.Stats.Ipos, 0)) + 1
	end
	Core.Stat(prog, "Ipos", count, "max")
	for _, step in ipairs(PCFG.Prestige.TitleSteps) do
		if count >= step.Ipos then
			grantTitle(p, prog, step.Title, false)
		end
	end
	call("LeaderboardService", "AddIpo", p, ticker)
	call("LeaderboardService", "Submit", p)
	call("MetricsService", "Progression", p, "Ipo", "Complete", count)
	-- eine Meldung, ein Weg: der Effekt zeigt dem Spieler die Zeremonie und allen anderen das Server-Banner
	call("PlayerStateService", "EffectAll", "IpoCeremony", 1, {
		Ticker = ticker,
		UserId = p.UserId,
		Name = p.DisplayName,
		Count = count,
		Stars = stars,
		Crown = Core.CrownFor(count),
	})
	checkAchievements(p, prog)
	awardBadges(p, prog)
	markDirty(p, "Prog")
	local message = T(p, "prog.ipoDone", ticker, stars)
	if replaced then
		message = T(p, "prog.ipoBlocked", ticker) .. " " .. message
	end
	return { Ok = true, Message = message, Ticker = ticker, Stars = stars, Count = count }
end

local function handlePerk(p: Player, arg: any): Reply
	if not exactKeys(arg, { "Branch" }) or type(arg.Branch) ~= "string" or #arg.Branch > 40 then
		return fail(p, "core.invalid")
	end
	local prog = progOf(p)
	if not prog then
		return fail(p, "core.loading")
	end
	local ok, key, args = Core.BuyPerk(prog, arg.Branch)
	if not ok then
		return fail(p, key)
	end
	local def = PCFG.PerkByKey[arg.Branch]
	local level = (args :: { any })[1]
	if def.Title and level >= def.Max then
		grantTitle(p, prog, def.Title, false) -- Vorstand Lifestyle 5: Titel "CEO" (Uhr schaltet LifestyleService frei)
	end
	markDirty(p, "Prog")
	return { Ok = true, Message = T(p, key, T(p, "prog.perk." .. arg.Branch), level), Level = level }
end

local function handleRespec(p: Player, arg: any): Reply
	if arg ~= nil and (type(arg) ~= "table" or next(arg) ~= nil) then
		return fail(p, "core.invalid")
	end
	local prog = progOf(p)
	if not prog then
		return fail(p, "core.loading")
	end
	local ok, key = Core.Respec(prog)
	if not ok then
		return fail(p, key)
	end
	markDirty(p, "Prog")
	return { Ok = true, Message = T(p, key) }
end

local function handleTitle(p: Player, arg: any): Reply
	if not exactKeys(arg, { "Id" }) or type(arg.Id) ~= "string" or #arg.Id > 40 then
		return fail(p, "core.invalid")
	end
	local prog = progOf(p)
	if not prog then
		return fail(p, "core.loading")
	end
	if arg.Id ~= "" and not prog.Titles[arg.Id] then
		return fail(p, "prog.titleUnknown")
	end
	prog.Title = arg.Id
	prog.TitleOff = arg.Id == "" -- „Kein Titel“ bleibt stehen (sonst setzte der 5-s-Takt den Vermögens-Titel zurück)
	setAttributes(p, prog)
	markDirty(p, "Prog")
	local def = PCFG.TitleByKey[arg.Id]
	local name = if def then Lang.Pick(langOf(p), def.Name) else T(p, "prog.titleNone")
	return { Ok = true, Message = T(p, "prog.titleSet", name) }
end

-- ---------------------------------------------------------------------
-- 11) LEBENSZYKLUS
-- ---------------------------------------------------------------------
local function onReady(p: Player)
	local prog, data = progOf(p)
	if not prog or not data then
		return
	end
	Core.Repair(data)
	prog = data.Prog
	readyAt[p] = os.clock()
	ensureDay(p, data)
	Core.Stat(prog, "Licence", prog.Licence, "max")
	setAttributes(p, prog)
	-- Die Depot-Basis gleicht OrderService beim Beitritt selbst aus Prog.Licence ab (kein Doppel-Aufruf hier)
	checkLicence(p, prog)
	task.defer(playerTick, p)
	markDirty(p, "Prog")
end

local function onPlayerRemoving(p: Player)
	wealthOf[p] = nil
	ipoTokens[p] = nil
	recentBuys[p] = nil
	sectorsToday[p] = nil
	crashWatch[p] = nil
	lessonAt[p] = nil
	badgeBusy[p] = nil
	ipoBusy[p] = nil
	readyAt[p] = nil
end

function ProgressionService.Init(services: any)
	Services = services
	local pss = services.PlayerStateService
	if not pss then
		warn("[ProgressionService] PlayerStateService fehlt – keine Anfragen/State")
		return
	end
	pss.Provide("Prog", progState)
	pss.Handle("ProgLesson", handleLesson, { Rate = 1, Per = 1 })
	pss.Handle("ProgExam", handleExam, { Rate = 1, Per = 1 })
	pss.Handle("ProgKnowHow", handleKnowHow, { Rate = 2, Per = 1 })
	pss.Handle("ProgKnowHowReset", handleKnowHowReset, { Rate = 1, Per = 60 })
	pss.Handle("ProgIpoPreview", handleIpoPreview, { Rate = 1, Per = 1 })
	pss.Handle("ProgIpo", handleIpo, { Rate = 1, Per = 10 })
	pss.Handle("ProgPerk", handlePerk, { Rate = 2, Per = 1 })
	pss.Handle("ProgRespec", handleRespec, { Rate = 2, Per = 1 })
	pss.Handle("ProgTitle", handleTitle, { Rate = 2, Per = 1 })
end

function ProgressionService.Start()
	call("PlayerStateService", "OnReady", onReady)
	call("OrderService", "OnTrade", onTrade)
	call("OrderService", "OnDayResult", onDayResult)
	call("OrderService", "OnBell", onBell)
	call("MarketService", "OnNews", onNews)
	call("TowerService", "OnFloorBuilt", onFloor)
	call("TowerService", "OnStageUp", onStage)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	Scheduler.Staggered("ProgressionPlayers", WEALTH_HZ, function()
		return Players:GetPlayers()
	end, function(p: Player)
		playerTick(p)
	end)
	Scheduler.Every("ProgressionCrash", CRASH_HZ, crashTick)
	if RunService:IsStudio() then
		local problems = PCFG.Validate and PCFG.Validate(Config) or {}
		for i = 1, math.min(#problems, 10) do
			warn("[ProgressionService] " .. tostring(problems[i]))
		end
	end
end

return ProgressionService
