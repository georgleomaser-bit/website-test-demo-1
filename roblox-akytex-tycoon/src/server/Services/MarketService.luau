-- =====================================================================
--  AKYTEX TYCOON – Markt-Service: globaler deterministischer Markt (Server/Services/MarketService)
--  Besitzer: WP3 (Markt-Engine). Vertrag: DESIGN.md §C5.3, §C8 (MarketFrame/Market), §C9 (MktCandles, MktProfile,
--  MktCalendar, MktNews), §C10 (State "Market"), §C11.4 (Firewall), §B6, §B10.4, §B15.3; MARKET.md §3–§10, §17, §18.
--
--  Kurs = f(Wochen-Seed, 1-Hz-Tick, Event-Liste): jeder Server rechnet selbst -> alle Server zeigen dieselben Kurse.
--  Ablauf je Tick (Scheduler "Market", 1 Hz, ≤ 10 Nachhol-Ticks, Sprung bei > 60 s Stillstand):
--    1) News mit t_a == t + Market-Nachrichten (Event/Halt/Ipo) senden   2) PriceEngine.Step(t)
--    3) OnTick-Callbacks (Orders, WP4)   4) Kerzen-Ringe   5) Glocke/Kalender/Tagesschluss bei t % 1200 == 0
--    danach EIN Frame (neuester Tick) per FireAllClients(buffer).
--  Wochen-Kontext = { Seed, EventDirector, PriceEngine }; aktuelle Woche + Vorwoche (Historie/Offline ≤ 26 h).
--  Firewall (§C11.4): kennt keine Turm-/Shop-/Pass-Begriffe; zur Laufzeit nur PlayerStateService, OrderService,
--  ProgressionService (TradingPerks), MetricsService. Besitzer-Prüfung über das serverseitige Player-Attribut
--  "IsAdmin" (setzt AdminService, WP11) – AdminService selbst ist für Markt-Code tabu (nur OwnerTradeBlocked).
--
--  Öffentliche API (§C5.3)
--    Tick() · Quote(i) · Candle1s(i, t) · PriceAt(i, t) · NewCursor(i, t0) · Instrument(i) · ActiveIds() · IsHalted(i)
--    Regime() · DayIndex() · HalfSpread(i) · Dividends(t0, t1) · Calendar(days) · RecentNews(n) · FactNewsFor(i, t, w)
--    AdminWindowActive(t?) · AdminWindowsBetween(t0, t1) · AutoShowCancelled(week) · IsLocalMarket()
--    OnTick(cb) · OnNews(cb) · OnDayClose(cb) · Admin(action, args, by) · Stats()
--    zusätzlich: IsReady(): boolean (Seed geladen, Plan gebaut) · AuditStats() (Admin-Statistik Fill-Audit) ·
--    TestContext(seed, week, bases?, cancelled?) (nur SelfTests: isolierter Wochen-Kontext)
--  Hinweise für WP4: vor IsReady() liefern Quote/Candle1s nil und PriceAt den Startkurs – den Offline-Abgleich erst
--  starten, wenn IsReady() true ist. Zeitpunkte > Tick() werden auf Tick() begrenzt (nie Zukunft). Nach einem
--  Server-Stillstand > 60 s springt der Markt auf jetzt (OnTick feuert für die übersprungenen Ticks NICHT, nur die
--  verpassten OnDayClose) – Orders dieser Lücke gleicht WP4 wie offline über PriceAt/NewCursor ab.
--  State "Market" = { Week, Day, Regime, Halts = { ["<Id>"] = Until, ["0"] = ganzer Markt }, AdminWindow,
--  AutoShowCancelled } (String-Schlüssel wegen Remote-Serialisierung; nie der Seed).
-- =====================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Types = require(Shared:WaitForChild("Types"))
local Clock = require(Shared:WaitForChild("Clock"))
local Lang = require(Shared:WaitForChild("Lang"))
local QuoteCodec = require(Shared:WaitForChild("Market"):WaitForChild("QuoteCodec"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local MarketFolder = script.Parent.Parent:WaitForChild("Market")
local MarketClock = require(MarketFolder:WaitForChild("MarketClock"))
local MarketSeed = require(MarketFolder:WaitForChild("MarketSeed"))
local EventDirector = require(MarketFolder:WaitForChild("EventDirector"))
local PriceEngine = require(MarketFolder:WaitForChild("PriceEngine"))
local GlobalBus = require(MarketFolder:WaitForChild("GlobalBus"))
local CandleStore = require(MarketFolder:WaitForChild("CandleStore"))
local QuoteStream = require(MarketFolder:WaitForChild("QuoteStream"))
local MarketAudit = require(MarketFolder:WaitForChild("MarketAudit"))
local MarketAdmin = require(MarketFolder:WaitForChild("MarketAdmin"))

local MarketService = {}
local Services: any = nil

type Plain = { [string]: any }
type Ctx = {
	Week: number,
	Seed: number,
	Director: any,
	Engine: any,
	Bases: { [number]: number },
}

local cfg: any = Config.Market
local companies: any = Config.Companies
local newsCfg: any = Config.News

local DAY = MarketClock.DAY
local MAX_CALLBACKS = 64
local DAYCLOSE_WAIT = 3 -- s: so lange wartet der Tagesschluss auf die Tagesrendite (OrderService.OnDayResult)
local MAX_SKIPPED_DAYS = 72 -- nach einem Stillstand höchstens so viele Tagesschlüsse nachholen
local ERROR_LOG_EVERY = 10

-- Zustand -------------------------------------------------------------
local ready = false
local booting = false
local lastTick = 0
local ctxCur: Ctx? = nil
local ctxPrev: Ctx? = nil
local nextSeed: { Week: number, Seed: number, Tune: number }? = nil
local prefetching = false
local localMarket = false
local listings: { [number]: Plain } = {} -- alle bekannten Erstnotizen (Ipo_S + Plan + Admin)
local store = CandleStore.new(cfg)
local recent: { Types.NewsItem } = {}
local tickCallbacks: { (number) -> () } = {}
local newsCallbacks: { (Types.NewsItem) -> () } = {}
local dayCallbacks: { (number, number) -> () } = {}
local busEvents: { [string]: Plain } = {}
local busOrder: { string } = {}
local windows: { { number } } = {}
local cancelledWeeks: { [number]: boolean } = {}
local adminCooldown: { [number]: number } = {}
local pendingDay: { Day: number, Deadline: number, Sent: { [Player]: boolean } }? = nil
local tickMs = 0
local busPolling = false
local stateSig = ""
local errorAt: { [string]: number } = {}

-- ---------------------------------------------------------------------
-- HILFEN
-- ---------------------------------------------------------------------
local function logError(source: string, err: any)
	local now = os.clock()
	if now - (errorAt[source] or -math.huge) >= ERROR_LOG_EVERY then
		errorAt[source] = now
		warn(("[MarketService] %s: %s"):format(source, tostring(err)))
	end
end

local function service(name: string): any
	return if Services then Services[name] else nil
end

local function call(name: string, fn: string, ...: any): (boolean, any)
	local svc = service(name)
	local f = svc and svc[fn]
	if type(f) ~= "function" then
		return false, nil
	end
	return pcall(f, ...)
end

local function langOf(p: Player?): Types.Lang
	if p then
		local ok, lang = call("PlayerStateService", "LangOf", p)
		if ok and (lang == "de" or lang == "en") then
			return lang
		end
	end
	return "en"
end

local function reply(p: Player?, ok: boolean, key: string?, extra: Plain?, ...: any): Types.Reply
	local result: Types.Reply = { Ok = ok }
	if key then
		result.Message = Lang.T(langOf(p), key, ...)
	end
	if extra then
		for k, v in pairs(extra) do
			result[k] = v
		end
	end
	return result
end

local function fire(list: { any }, ...: any)
	for _, cb in ipairs(list) do
		task.spawn(function(...)
			local ok, err = pcall(cb, ...)
			if not ok then
				logError("Callback", err)
			end
		end, ...)
	end
end

local function register(list: { any }, cb: any)
	if type(cb) ~= "function" then
		return
	end
	if #list >= MAX_CALLBACKS then
		warn("[MarketService] zu viele Callbacks – ignoriert")
		return
	end
	table.insert(list, cb)
end

local function isInt(n: any): boolean
	return Util.IsFinite(n) and n % 1 == 0
end

-- exakte Schlüssel (§C9): nur erlaubte, Pflicht-Schlüssel vorhanden
local function exactKeys(arg: any, required: { string }, optional: { string }?): boolean
	if arg == nil then
		return #required == 0
	end
	if type(arg) ~= "table" then
		return false
	end
	local allowed: { [string]: boolean } = {}
	for _, key in ipairs(required) do
		if arg[key] == nil then
			return false
		end
		allowed[key] = true
	end
	for _, key in ipairs(optional or {}) do
		allowed[key] = true
	end
	local count = 0
	for key in pairs(arg) do
		count += 1
		if type(key) ~= "string" or not allowed[key] or count > 8 then
			return false
		end
	end
	return true
end

local function inst(i: number): Plain?
	return companies.ById and companies.ById[i] or nil
end

local function contextFor(t: number): Ctx?
	local week = MarketClock.WeekIndex(t)
	local cur = ctxCur
	if cur and cur.Week == week then
		return cur
	end
	local prev = ctxPrev
	if prev and prev.Week == week then
		return prev
	end
	return nil
end

local function ensureBuilt(ctx: Ctx, t: number)
	local day = MarketClock.DayIndex(t)
	if ctx.Director:BuiltThrough() < day then
		ctx.Director:EnsureBuilt(day)
	end
end

local function clampTick(t: number): number
	if not Util.IsFinite(t) then
		return lastTick
	end
	return math.min(math.floor(t), lastTick)
end

-- ---------------------------------------------------------------------
-- WOCHEN-KONTEXT
-- ---------------------------------------------------------------------
local function seasonOfWeek(week: number): number
	local pipeline = cfg.IpoPipeline
	return math.max(1, (week - pipeline.FirstWeek) // pipeline.SeasonWeeks + 1)
end

local function scheduledListing(id: number): number?
	local pipeline = cfg.IpoPipeline
	local entry: Plain? = nil
	for _, e in ipairs(cfg.Weekly) do
		if e.Kind == "Ipo" then
			entry = e
		end
	end
	if entry == nil then
		return nil
	end
	for season, ids in pairs(pipeline.Season) do
		for slot, pid in ipairs(ids) do
			if pid == id then
				local week = pipeline.FirstWeek + (season - 1) * pipeline.SeasonWeeks + (slot - 1)
				return MarketClock.WeeklyTick(week, entry.Dow, entry.HH, entry.MM)
			end
		end
	end
	return nil
end

local function inPipeline(id: number, week: number): boolean
	local ids = cfg.IpoPipeline.Season[seasonOfWeek(week)]
	if type(ids) ~= "table" then
		return false
	end
	return table.find(ids, id) ~= nil
end

local function specFor(ctx: Ctx, slot: Plain, base: number, origin: number, wildFrom: number?): Plain
	local cls = cfg.Classes[slot.Class] or cfg.Classes.Normal
	local wild = cfg.Classes[cfg.IpoPipeline.FirstDayClass] or cfg.Classes.Wild
	local spec: Plain = {
		Id = slot.Id,
		Etf = false,
		Base = base,
		Origin = origin,
		Sigma = cls.Sigma,
		Sigma1s = cls.Sigma1s,
		SpreadBps = cls.SpreadBps,
		VolBase = cls.VolBase,
		Drift = 0, -- die Fundament-Drift (mit Bewertungsanker) steckt im EventDirector-Beitrag
		SectorIdx = companies.SectorIndex[slot.Sector] or 1,
	}
	if wildFrom and wildFrom + DAY > MarketClock.WeekStart(ctx.Week) then
		spec.WildUntil = wildFrom + DAY
		spec.WildSigma = wild.Sigma
		spec.WildSigma1s = wild.Sigma1s
		spec.WildSpread = wild.SpreadBps
		spec.Blend = cfg.IpoPipeline.ClassBlend
	end
	return spec
end

local function autoShowCancelled(week: number): boolean
	return cancelledWeeks[week] == true
end

-- Baut einen Wochen-Kontext (Plan noch NICHT gebaut – siehe buildDays)
local function newContext(
	week: number,
	seed: number,
	bases: { [number]: number },
	tune: number,
	isolated: boolean?
): Ctx
	local weekStart = MarketClock.WeekStart(week)
	local season = seasonOfWeek(week)
	local slots: { Plain } = {}
	local weekListings: { [number]: Plain } = {}
	for _, entry in ipairs(companies.Instruments) do
		if entry.Class == "ETF" or entry.Set == "Tutorial" then
			continue
		end
		local base = bases[entry.Id] or entry.Start
		local origin, valOrigin = weekStart, weekStart
		if entry.Ipo then
			if (entry.Season or 1) > season then
				continue -- spätere Saison: noch nicht im Plan
			end
			local rec = listings[entry.Id]
			local sched = scheduledListing(entry.Id)
			if rec and rec.Tick < weekStart then
				base = bases[entry.Id] or rec.Open
			else
				base = entry.Start
				origin = math.huge
				valOrigin = if sched
						and sched >= weekStart
						and sched <= MarketClock.WeekEnd(week)
					then sched
					else math.huge
				if rec and rec.Tick >= weekStart and rec.Tick <= MarketClock.WeekEnd(week) then
					weekListings[entry.Id] = {
						T0 = rec.Tick,
						Issue = rec.Issue,
						Open = rec.Open,
						Pop = rec.Open / math.max(1, rec.Issue) - 1,
						Q = 0,
						By = rec.By or 0,
					}
				end
			end
		end
		table.insert(slots, {
			Id = entry.Id,
			Name = entry.Name,
			Class = entry.Class,
			Sector = entry.Sector,
			SectorIdx = companies.SectorIndex[entry.Sector] or 1,
			Start = entry.Start,
			DivBps = entry.DivBps,
			Base = base,
			ValBase = base,
			Ipo = entry.Ipo == true,
			Origin = origin,
			ValOrigin = valOrigin,
		})
	end
	local director = EventDirector.new({
		Seed = seed,
		Week = week,
		Config = cfg,
		Companies = companies,
		News = newsCfg,
		Slots = slots,
		NewsMeanGap = tune,
		Listings = {},
		IsCancelled = autoShowCancelled,
	})
	local ctx: Ctx = { Week = week, Seed = seed, Director = director, Engine = nil :: any, Bases = bases }
	local specs: { Plain } = {}
	for _, slot in ipairs(slots) do
		if slot.Origin ~= math.huge then
			local rec = listings[slot.Id]
			table.insert(specs, specFor(ctx, slot, slot.Base, slot.Origin, if rec then rec.Tick else nil))
		end
	end
	for _, entry in ipairs(companies.Instruments) do
		if entry.Class == "ETF" then
			local etfCls = cfg.Classes.ETF
			table.insert(specs, {
				Id = entry.Id,
				Etf = true,
				Base = bases[entry.Id] or entry.Start,
				Origin = weekStart,
				Sigma = 0,
				Sigma1s = etfCls.Sigma1s,
				SpreadBps = etfCls.SpreadBps,
				VolBase = etfCls.VolBase,
				Drift = 0,
				SectorIdx = 1,
				Members = entry.Members,
			})
		end
	end
	local engine = PriceEngine.new({
		Seed = seed,
		Week = week,
		Config = cfg,
		Specs = specs,
		Env = {
			Offset = function(i: number, t: number, divFrom: number?)
				return director:Offset(i, t, divFrom)
			end,
			VolMul = function(t: number)
				return director:VolMul(t)
			end,
		},
	})
	ctx.Engine = engine
	director:SetPriceHook(function(i: number, t: number, divFrom: number)
		return engine:MidAt(i, t, divFrom)
	end)
	director:SetListingHook(function(i: number, rec: Plain)
		local slot: Plain? = nil
		for _, s in ipairs(director:Slots()) do
			if s.Id == i then
				slot = s
			end
		end
		if slot then
			engine:AddInstrument(specFor(ctx, slot, rec.Open, rec.T0, rec.T0))
			if not isolated then
				store:Ensure(i)
			end
		end
		if not isolated and listings[i] == nil then
			listings[i] = { Tick = rec.T0, Issue = rec.Issue, Open = rec.Open, By = rec.By or 0 }
			local s = seasonOfWeek(MarketClock.WeekIndex(rec.T0))
			task.spawn(
				MarketSeed.SaveIpo,
				s,
				i,
				{ Tick = rec.T0, Issue = rec.Issue, Open = rec.Open, By = rec.By or 0 }
			)
		end
	end)
	for id, rec in pairs(weekListings) do
		director:AddListing(id, rec)
	end
	return ctx
end

-- Plan sequentiell bauen (Thread darf yielden): bis zum Börsentag `day`, je Häppchen ein task.wait()
local function buildDays(ctx: Ctx, day: number, yielding: boolean)
	local guard = 0
	while ctx.Director:BuiltThrough() < math.min(day, MarketClock.DayIndex(MarketClock.WeekEnd(ctx.Week))) do
		ctx.Director:EnsureBuilt(day, 8)
		guard += 1
		if yielding and guard % 2 == 0 then
			task.wait()
		end
		if guard > 200 then
			break
		end
	end
end

-- externe Events (Bus/Log) in einen Kontext übernehmen; carry = Event der Vorwoche, das hineinreicht
local function applyToContext(ctx: Ctx, ev: Plain): { number }
	local weekStart = MarketClock.WeekStart(ctx.Week)
	if ev.StartTick >= weekStart and ev.StartTick <= MarketClock.WeekEnd(ctx.Week) then
		return ctx.Director:AddExternal(ev, false)
	elseif ev.StartTick < weekStart and ev.Until >= weekStart then
		return ctx.Director:AddExternal(ev, true)
	end
	return {}
end

-- Wochenschluss einer Woche aus ihrem Kontext (alle Instrumente, Cent)
local function closesOf(ctx: Ctx): { [number]: number }
	local endTick = MarketClock.WeekEnd(ctx.Week)
	ensureBuilt(ctx, endTick)
	local closes: { [number]: number } = {}
	for _, i in ipairs(ctx.Engine:Ids()) do
		if ctx.Engine:IsActive(i, endTick) then
			closes[i] = ctx.Engine:MidAt(i, endTick)
		end
	end
	return closes
end

-- ---------------------------------------------------------------------
-- ADMIN-FENSTER, BUS-EVENTS
-- ---------------------------------------------------------------------
local function windowOf(ev: Plain): { number }?
	local kind = ev.Kind
	if kind == "CancelAutoShow" or kind == "Resume" then
		return nil
	end
	local admin = cfg.Admin
	local finish = ev.Until
	if kind == "Ipo" then
		finish = ev.Until + cfg.Halts.IpoSeconds
	end
	return { ev.StartTick - admin.Lead, finish + admin.WindowAfter }
end

local function addWindow(ev: Plain)
	local w = windowOf(ev)
	if w == nil then
		return
	end
	for _, existing in ipairs(windows) do
		if existing[1] == w[1] and existing[2] == w[2] then
			return
		end
	end
	table.insert(windows, w)
	table.sort(windows, function(a, b)
		return a[1] < b[1]
	end)
	while #windows > 400 do
		table.remove(windows, 1)
	end
end

local function autoShowTick(week: number): number?
	for _, entry in ipairs(cfg.Weekly) do
		if entry.Key == "AutoShow" then
			return MarketClock.WeeklyTick(week, entry.Dow, entry.HH, entry.MM)
		end
	end
	return nil
end

local function cancelLead(): number
	for _, entry in ipairs(cfg.Weekly) do
		if entry.Key == "AutoShow" then
			return entry.CancelLead or 10
		end
	end
	return 10
end

local function markAllDirty()
	for _, p in ipairs(Players:GetPlayers()) do
		call("PlayerStateService", "MarkDirty", p, "Market")
	end
end

local function allIds(): { number }
	local cur = ctxCur
	return if cur then cur.Engine:Ids() else {}
end

-- laufende 5s-/1m-Buckets ab liveStart exakt neu vorbelegen (nach verspätetem Event oder Stillstand-Sprung)
local function seedLive(ids: { number }, liveStart: number)
	local candleAt = function(id: number, t: number)
		local c = contextFor(t)
		if c then
			ensureBuilt(c, t)
			local o, h, l, cl, v = c.Engine:CandleAt(id, t)
			return o, h, l, cl, v
		end
		return 0, 0, 0, 0, 0
	end
	for _, i in ipairs(ids) do
		store:SeedPartial(i, liveStart, candleAt)
	end
end

local function onBusEvent(ev: Plain, late: boolean)
	if busEvents[ev.Id] then
		return
	end
	busEvents[ev.Id] = ev
	table.insert(busOrder, ev.Id)
	while #busOrder > (cfg.Bus.MaxEvents or 200) do
		local old = table.remove(busOrder, 1)
		if old then
			busEvents[old] = nil
		end
	end
	addWindow(ev)
	if ev.Kind == "CancelAutoShow" then
		local week = tonumber(ev.Target) or MarketClock.WeekIndex(ev.StartTick)
		local show = autoShowTick(week)
		if show and ev.StartTick <= show - cancelLead() then
			cancelledWeeks[week] = true
			markAllDirty()
		end
		return
	end
	local affected: { number } = {}
	local prev, cur = ctxPrev, ctxCur
	if prev then
		for _, i in ipairs(applyToContext(prev, ev)) do
			table.insert(affected, i)
		end
	end
	if cur then
		for _, i in ipairs(applyToContext(cur, ev)) do
			if not table.find(affected, i) then
				table.insert(affected, i)
			end
		end
	end
	if not ready then
		return
	end
	local now = lastTick
	if late and ev.StartTick <= now then
		-- verspätet: mit dem Original-Tick anwenden, betroffene Werte 10 s pausieren, Kerzen-Fenster neu rechnen (§8.4)
		local ids = table.clone(affected)
		if #ids > 0 then
			for _, entry in ipairs(companies.Instruments) do
				if entry.Class == "ETF" then
					table.insert(ids, entry.Id)
				end
			end
		end
		local ctx = contextFor(ev.StartTick)
		if ctx then
			ctx.Director:InvalidateDividends(affected, ev.StartTick)
		end
		if cur and #affected > 0 then
			local untilTick = now + 1 + cfg.Halts.LateSeconds
			cur.Director:AddLocalHalt(affected, now + 1, untilTick)
			if #affected >= #cur.Director:Slots() then
				Remotes.Market:FireAllClients("Halt", { Until = untilTick })
			else
				for _, i in ipairs(affected) do
					Remotes.Market:FireAllClients("Halt", { I = i, Until = untilTick })
				end
			end
		end
		if #ids > 0 then
			store:Rebuild(ids, ev.StartTick, now, now + 1)
			seedLive(ids, now + 1)
		end
	elseif ev.Kind ~= "Halt" and ev.Kind ~= "Resume" then
		-- Ankündigung (10 s Vorlauf): Countdown für alle
		Remotes.Market:FireAllClients("Event", {
			Kind = ev.Kind,
			Phase = "Warn",
			StartTick = ev.StartTick,
			Until = ev.Until,
			Scope = ev.Scope,
			Target = ev.Target,
			Admin = true,
		})
	end
	markAllDirty()
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICHE API (§C5.3)
-- ---------------------------------------------------------------------
function MarketService.IsReady(): boolean
	return ready
end

function MarketService.Tick(): number
	return lastTick
end

function MarketService.Quote(i: number): (number?, number?, number?)
	local cur = ctxCur
	if not ready or cur == nil then
		return nil, nil, nil
	end
	return cur.Engine:Quote(i)
end

function MarketService.Candle1s(i: number, t: number): (number?, number?, number?, number?, number?)
	if not ready or not isInt(i) then
		return nil, nil, nil, nil, nil
	end
	local tick = clampTick(t)
	local ctx = contextFor(tick)
	if ctx == nil or not ctx.Engine:IsActive(i, tick) then
		return nil, nil, nil, nil, nil
	end
	ensureBuilt(ctx, tick)
	local o, h, l, c, v = ctx.Engine:CandleAt(i, tick)
	return o, h, l, c, v
end

function MarketService.PriceAt(i: number, t: number): number
	local entry = inst(i)
	local fallback = if entry then entry.Start else 0
	if not ready or not isInt(i) then
		return fallback
	end
	local tick = clampTick(t)
	local ctx = contextFor(tick)
	if ctx == nil then
		-- älter als die Vorwoche: Wochenbasis der ältesten bekannten Woche
		local oldest = ctxPrev or ctxCur
		if oldest then
			return oldest.Bases[i] or fallback
		end
		return fallback
	end
	ensureBuilt(ctx, tick)
	return ctx.Engine:MidAt(i, tick)
end

function MarketService.NewCursor(i: number, t0: number)
	local cursor = { Week = -1, Inner = nil :: any }
	function cursor.Seek(self: any, t: number)
		local tick = clampTick(t)
		local ctx = contextFor(tick)
		if ctx == nil then
			ctx = ctxCur
		end
		if ctx then
			ensureBuilt(ctx, tick)
			self.Inner = ctx.Engine:NewCursor(i, tick)
			self.Week = ctx.Week
		end
	end
	function cursor.Candle(self: any, t: number): (number, number, number, number)
		local tick = clampTick(t)
		if self.Inner == nil or MarketClock.WeekIndex(tick) ~= self.Week then
			self:Seek(tick)
		end
		local inner = self.Inner
		if inner == nil then
			local p = MarketService.PriceAt(i, tick)
			return p, p, p, p
		end
		local ctx = contextFor(tick)
		if ctx then
			ensureBuilt(ctx, tick)
		end
		return inner:Candle(tick)
	end
	cursor:Seek(t0)
	return cursor
end

function MarketService.Instrument(i: number): Types.Instrument?
	local entry = inst(i)
	return entry :: any
end

function MarketService.ActiveIds(): { number }
	local out: { number } = {}
	local cur = ctxCur
	if cur == nil then
		return out
	end
	for _, i in ipairs(cur.Engine:Ids()) do
		if cur.Engine:IsActive(i, lastTick) then
			table.insert(out, i)
		end
	end
	table.sort(out)
	return out
end

function MarketService.IsHalted(i: number): boolean
	local cur = ctxCur
	if cur == nil then
		return true
	end
	local halted = cur.Director:Halted(i, lastTick)
	return halted
end

function MarketService.Regime(): number
	local cur = ctxCur
	return if cur and ready then cur.Engine:Regime() else 1
end

function MarketService.DayIndex(): number
	return MarketClock.DayIndex(lastTick)
end

function MarketService.HalfSpread(i: number): number
	local cur = ctxCur
	return if cur and ready then cur.Engine:HalfSpread(i) else 0
end

function MarketService.Dividends(t0: number, t1: number): { { I: number, Tick: number, Cents: number } }
	local out: { { I: number, Tick: number, Cents: number } } = {}
	if not ready or not Util.IsFinite(t0) or not Util.IsFinite(t1) then
		return out
	end
	local a, b = math.floor(t0), clampTick(t1)
	for _, ctx in ipairs({ ctxPrev, ctxCur } :: { Ctx? }) do
		if ctx then
			local ws, we = MarketClock.WeekStart(ctx.Week), MarketClock.WeekEnd(ctx.Week)
			local lo, hi = math.max(a, ws), math.min(b, we)
			if lo <= hi then
				ensureBuilt(ctx, hi)
				for _, d in ipairs(ctx.Director:Dividends(lo, hi)) do
					table.insert(out, { I = d.I, Tick = d.Tick, Cents = d.Cents })
				end
			end
		end
	end
	return out
end

local function weeklyItems(fromTick: number, toTick: number): { Types.CalendarItem }
	local out: { Types.CalendarItem } = {}
	local firstWeek = MarketClock.WeekIndex(fromTick)
	for week = firstWeek, firstWeek + 1 do
		for _, entry in ipairs(cfg.Weekly) do
			local t = MarketClock.WeeklyTick(week, entry.Dow, entry.HH, entry.MM)
			if t and t >= fromTick and t <= toTick then
				if entry.Kind == "Ipo" then
					local pipeline = cfg.IpoPipeline
					local offset = week - pipeline.FirstWeek
					if offset >= 0 then
						local ids = pipeline.Season[offset // pipeline.SeasonWeeks + 1]
						local id = if type(ids) == "table" then ids[offset % pipeline.SeasonWeeks + 1] else nil
						local rec = if id then listings[id] else nil
						-- geplant (oder schon vorausgebaut, aber noch nicht notiert): im Kalender zeigen
						if id and (rec == nil or rec.Tick > lastTick) then
							table.insert(
								out,
								{ T = if rec then rec.Tick else t, Kind = "Ipo", I = id, Key = "mkt.cal.Ipo" }
							)
						end
					end
				elseif entry.Key == "AutoShow" then
					if not autoShowCancelled(week) then
						table.insert(out, { T = t + (entry.Offset or 0), Kind = "Rally", Key = "mkt.cal.AutoShow" })
					end
				elseif entry.Key == "CrashFriday" then
					table.insert(out, { T = t, Kind = "Crash", Key = "mkt.cal.CrashFriday" })
				elseif entry.Key == "RallyWednesday" then
					table.insert(out, { T = t, Kind = "Rally", Key = "mkt.cal.RallyWednesday" })
				end
			end
		end
	end
	return out
end

function MarketService.Calendar(days: number): { Types.CalendarItem }
	local out: { Types.CalendarItem } = {}
	local cur = ctxCur
	if not ready or cur == nil then
		return out
	end
	local n = math.clamp(math.floor(tonumber(days) or 1), 1, 3)
	local fromTick = lastTick
	local toTick = (MarketClock.DayIndex(lastTick) + n) * DAY - 1
	for _, item in ipairs(cur.Director:Calendar(fromTick, toTick)) do
		table.insert(out, item)
	end
	for _, item in ipairs(weeklyItems(fromTick, fromTick + cfg.CalendarWeeklyDays * 86400)) do
		table.insert(out, item)
	end
	table.sort(out, function(a, b)
		if a.T ~= b.T then
			return a.T < b.T
		end
		return (a.I or 0) < (b.I or 0)
	end)
	return out
end

function MarketService.RecentNews(n: number): { Types.NewsItem }
	local count = math.clamp(math.floor(tonumber(n) or cfg.NewsKeep), 0, cfg.NewsKeep)
	local out: { Types.NewsItem } = {}
	for index = #recent, math.max(1, #recent - count + 1), -1 do
		table.insert(out, recent[index])
	end
	return out
end

function MarketService.FactNewsFor(i: number, t: number, window: number): Types.NewsItem?
	if not ready or not isInt(i) or not Util.IsFinite(window) then
		return nil
	end
	local tick = clampTick(t)
	local ctx = contextFor(tick)
	if ctx == nil then
		return nil
	end
	return ctx.Director:FactNewsFor(i, tick, math.clamp(window, 0, 3600))
end

function MarketService.AdminWindowActive(t: number?): boolean
	local tick = if t ~= nil and Util.IsFinite(t) then t else lastTick
	for _, w in ipairs(windows) do
		if tick >= w[1] and tick <= w[2] then
			return true
		elseif w[1] > tick then
			break
		end
	end
	return false
end

function MarketService.AdminWindowsBetween(t0: number, t1: number): { { number } }
	local out: { { number } } = {}
	if not Util.IsFinite(t0) or not Util.IsFinite(t1) then
		return out
	end
	for _, w in ipairs(windows) do
		if w[2] >= t0 and w[1] <= t1 then
			table.insert(out, { w[1], w[2] })
		end
	end
	return out
end

function MarketService.AutoShowCancelled(week: number): boolean
	return autoShowCancelled(week)
end

function MarketService.IsLocalMarket(): boolean
	return localMarket
end

function MarketService.OnTick(cb: (t: number) -> ())
	register(tickCallbacks, cb)
end

function MarketService.OnNews(cb: (n: Types.NewsItem) -> ())
	register(newsCallbacks, cb)
end

function MarketService.OnDayClose(cb: (day: number, t: number) -> ())
	register(dayCallbacks, cb)
end

function MarketService.AuditStats(): Plain
	return MarketAudit.Stats()
end

-- nur SelfTests/Debug: eigener, isolierter Wochen-Kontext (eigener Seed, keine globalen Nebenwirkungen)
function MarketService.TestContext(seed: number, week: number, bases: { [number]: number }?, cancelled: boolean?): Plain
	local ctx = newContext(week, seed, bases or {}, cfg.NewsMeanGap, true)
	if cancelled ~= nil then
		ctx.Director.IsCancelled = function(_week: number)
			return cancelled
		end
	end
	return ctx :: any
end

function MarketService.Stats(): {
	TickMs: number,
	BusOk: boolean,
	Events: number,
	Instruments: number,
	Ready: boolean,
	Local: boolean,
	Week: number,
	Day: number,
	Regime: number,
	BackfillPending: number,
	FrameBytes: number,
	AuditChecked: number,
	AuditFailed: number,
}
	local audit = MarketAudit.Stats()
	return {
		TickMs = math.round(tickMs * 1000) / 1000,
		BusOk = GlobalBus.Ok() and MarketSeed.Ok(),
		Events = #busOrder,
		Instruments = #MarketService.ActiveIds(),
		Ready = ready,
		Local = localMarket,
		Week = MarketClock.WeekIndex(lastTick),
		Day = MarketClock.DayIndex(lastTick),
		Regime = MarketService.Regime(),
		BackfillPending = store:Pending(),
		FrameBytes = QuoteStream.LastSize(),
		AuditChecked = audit.Checked,
		AuditFailed = audit.Failed,
	}
end

-- ---------------------------------------------------------------------
-- ADMIN (nur AdminService/EventService; Besitzer-Prüfung über Attribut IsAdmin)
-- ---------------------------------------------------------------------
local function filterText(text: string, userId: number): string?
	local okFilter, result = pcall(function()
		return TextService:FilterStringAsync(text, userId, Enum.TextFilterContext.PublicChat)
	end)
	if not okFilter or result == nil then
		return nil
	end
	local okText, clean = pcall(function()
		return (result :: TextFilterResult):GetNonChatStringForBroadcastAsync()
	end)
	if okText and type(clean) == "string" then
		return clean
	end
	return nil
end

local function inShowWindow(now: number): boolean
	local week = MarketClock.WeekIndex(now)
	local window = cfg.ShowWindow
	local from = MarketClock.WeeklyTick(week, window.Dow, window.HH, window.MM)
	local show = autoShowTick(week)
	return from ~= nil and show ~= nil and now >= from and now < show - cancelLead()
end

function MarketService.Admin(action: string, args: { [string]: any }, by: Player): (boolean, string)
	local lang = langOf(by)
	if typeof(by) ~= "Instance" or not by:IsA("Player") or by.Parent ~= Players then
		return false, Lang.T(lang, "mkt.admin.denied")
	end
	if by:GetAttribute("IsAdmin") ~= true then
		return false, Lang.T(lang, "mkt.admin.denied")
	end
	if not ready then
		return false, Lang.T(lang, "mkt.admin.notReady")
	end
	if type(action) ~= "string" then
		return false, Lang.T(lang, "mkt.admin.unknown")
	end
	local nowClock = os.clock()
	if nowClock - (adminCooldown[by.UserId] or -math.huge) < cfg.Admin.Cooldown then
		return false, Lang.T(lang, "mkt.admin.cooldown")
	end
	local week = MarketClock.WeekIndex(lastTick)
	local ev, errKey = MarketAdmin.Build(action, args, {
		Now = lastTick,
		ById = companies.ById,
		Listed = function(id: number)
			local rec = listings[id]
			if rec then
				return rec.Tick <= lastTick
			end
			local cur = ctxCur
			return cur ~= nil and inst(id) ~= nil and cur.Director:IsListed(id, lastTick)
		end,
		Taken = function(id: number)
			-- IPO schon gelistet ODER Erstnotiz bereits angesetzt (geplant/vorausgebaut)
			local cur = ctxCur
			return listings[id] ~= nil or (cur ~= nil and cur.Director:Listing(id) ~= nil)
		end,
		InPipeline = function(id: number)
			return inPipeline(id, week)
		end,
		Week = week,
		By = by.UserId,
		NewId = GlobalBus.NewId,
	})
	if ev == nil then
		return false, Lang.T(lang, errKey or "mkt.admin.badArgs")
	end
	adminCooldown[by.UserId] = nowClock
	if ev.Kind == "News" and ev.Text then
		local de = filterText(ev.Text.de, by.UserId)
		local en = filterText(ev.Text.en, by.UserId)
		if de == nil or en == nil then
			return false, Lang.T(lang, "mkt.admin.notFiltered")
		end
		ev.Text = { de = de, en = en }
	end
	-- Admin-Abuse vor 18:14:50 am Samstag sagt die automatische Samstags-Show ab (GlobalBus, §B10.4)
	if MarketAdmin.PRICE_KINDS[ev.Kind] and inShowWindow(lastTick) and not autoShowCancelled(week) then
		local cancel = MarketAdmin.Build("CancelAutoShow", { Target = week }, {
			Now = lastTick,
			ById = companies.ById,
			Listed = function()
				return false
			end,
			Taken = function()
				return false
			end,
			InPipeline = function()
				return false
			end,
			Week = week,
			By = by.UserId,
			NewId = GlobalBus.NewId,
		})
		if cancel then
			GlobalBus.Publish(cancel :: any)
		end
	end
	local ok, how = GlobalBus.Publish(ev :: any)
	if not ok then
		return false, Lang.T(lang, "mkt.admin.notDistributed")
	end
	call("MetricsService", "Custom", by, "MarketAdmin", nil, { Kind = ev.Kind })
	if how == "local" then
		return true, Lang.T(lang, "mkt.admin.local")
	end
	if ev.Kind == "CancelAutoShow" then
		return true, Lang.T(lang, "mkt.admin.cancelled")
	end
	return true, Lang.T(lang, "mkt.admin.ok", math.max(0, ev.StartTick - lastTick))
end

-- ---------------------------------------------------------------------
-- STATE "Market" (§C10) + Tagesschluss je Spieler
-- ---------------------------------------------------------------------
local function regimeRounded(): number
	return math.round(MarketService.Regime() * 100) / 100
end

local function weatherBucket(r: number): number
	local weather = cfg.Noise.Weather
	return if r < weather.Calm then 0 elseif r > weather.Storm then 2 else 1
end

local function marketState(): Plain
	local cur = ctxCur
	local halts: { [string]: number } = {}
	if cur and ready then
		halts = cur.Director:AnyHalt(lastTick)
	end
	local week = MarketClock.WeekIndex(lastTick)
	return {
		Week = week,
		Day = MarketClock.DayIndex(lastTick),
		Regime = regimeRounded(),
		Halts = halts,
		AdminWindow = MarketService.AdminWindowActive(),
		AutoShowCancelled = autoShowCancelled(week),
		Ready = ready,
	}
end

local function checkStateChange()
	local s = marketState()
	local parts: { string } = {
		tostring(s.Day),
		tostring(weatherBucket(s.Regime)),
		tostring(s.AdminWindow),
		tostring(s.AutoShowCancelled),
	}
	local keys: { string } = {}
	for key, untilTick in pairs(s.Halts) do
		table.insert(keys, key .. ":" .. tostring(untilTick))
	end
	table.sort(keys)
	table.insert(parts, table.concat(keys, ","))
	local sig = table.concat(parts, "|")
	if sig ~= stateSig then
		stateSig = sig
		markAllDirty()
	end
end

local function onDayResult(p: Player, r: Plain)
	if type(r) ~= "table" or typeof(p) ~= "Instance" or p.Parent ~= Players then
		return
	end
	if Util.IsFinite(r.Return) and Util.IsFinite(r.Day) then
		MarketAudit.NoteDay(p.UserId, r.Day, r.Return)
	end
	local pending = pendingDay
	if pending and r.Day == pending.Day and not pending.Sent[p] then
		pending.Sent[p] = true
		Remotes.Market:FireClient(p, "DayClose", {
			Day = pending.Day,
			Return = if Util.IsFinite(r.Return) then r.Return else nil,
		})
	end
end

local function flushDayClose(force: boolean)
	local pending = pendingDay
	if pending == nil then
		return
	end
	if not force and os.clock() < pending.Deadline then
		return
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if not pending.Sent[p] then
			pending.Sent[p] = true
			Remotes.Market:FireClient(p, "DayClose", { Day = pending.Day })
		end
	end
	pendingDay = nil
end

-- ---------------------------------------------------------------------
-- TICK-SCHLEIFE (nie yielden)
-- ---------------------------------------------------------------------
local function pushRecent(item: Types.NewsItem)
	table.insert(recent, item)
	while #recent > cfg.NewsKeep do
		table.remove(recent, 1)
	end
end

local function prefetchNext(week: number)
	if prefetching then
		return
	end
	prefetching = true
	task.spawn(function()
		local ok, err = pcall(function()
			local seed = MarketSeed.Load(week)
			local tune = MarketSeed.LoadTune(week, cfg.NewsMeanGap)
			for id, rec in pairs(MarketSeed.LoadIpos(seasonOfWeek(week))) do
				if listings[id] == nil then
					listings[id] = rec
				end
			end
			nextSeed = { Week = week, Seed = seed, Tune = tune }
		end)
		if not ok then
			logError("Prefetch", err)
		end
		prefetching = false
	end)
end

-- Wochenwechsel: false = noch nicht bereit (Tick wird später nachgeholt)
local function rollover(t: number): boolean
	local cur = ctxCur
	if cur == nil then
		return false
	end
	local week = MarketClock.WeekIndex(t)
	if week == cur.Week then
		return true
	end
	local pre = nextSeed
	if pre == nil or pre.Week ~= week then
		prefetchNext(week)
		return false
	end
	local closes = closesOf(cur)
	task.spawn(MarketSeed.SaveClose, cur.Week, closes)
	local fresh = newContext(week, pre.Seed, closes, pre.Tune)
	fresh.Director:EnsureBuilt(MarketClock.DayIndex(t))
	for _, id in ipairs(busOrder) do
		local ev = busEvents[id]
		if ev and ev.Kind ~= "CancelAutoShow" then
			applyToContext(fresh, ev)
		end
	end
	ctxPrev = cur
	ctxCur = fresh
	nextSeed = nil
	if not localMarket then
		task.spawn(MarketSeed.EnsureNext, week)
	end
	return true
end

local function advance(t: number): boolean
	if not rollover(t) then
		return false
	end
	local cur = ctxCur :: Ctx
	ensureBuilt(cur, t)
	local director = cur.Director
	-- 1) News mit t_a == t (nie früher) und Nachrichten dieses Ticks
	for _, item in ipairs(director:NewsIn(t - 1, t)) do
		pushRecent(item)
		Remotes.Market:FireAllClients("News", item)
		fire(newsCallbacks, item)
	end
	for _, m in ipairs(director:MessagesAt(t)) do
		Remotes.Market:FireAllClients(m.Kind, m.Data)
	end
	-- 2) Kurse
	cur.Engine:Step(t)
	-- 3) Orders & Co. (WP4) – nach Step, vor Kerzen/Frame
	fire(tickCallbacks, t)
	-- 4) Kerzen-Ringe
	for _, i in ipairs(cur.Engine:Ids()) do
		local o, h, l, c, v = cur.Engine:Candle(i)
		if o and h and l and c and v then
			store:Push(i, t, o, h, l, c, v)
		end
	end
	-- 5) Glocke, Kalender-Delta, Tagesschluss
	if t % DAY == 0 then
		local day = MarketClock.DayIndex(t)
		flushDayClose(true)
		Remotes.Market:FireAllClients("Bell", { Day = day })
		local fromDay = (day + 2) * DAY
		local delta = director:Calendar(fromDay, fromDay + DAY - 1)
		if #delta > 0 then
			Remotes.Market:FireAllClients("Calendar", delta)
		end
		pendingDay = { Day = day - 1, Deadline = os.clock() + DAYCLOSE_WAIT, Sent = {} }
		fire(dayCallbacks, day - 1, t)
	end
	-- Vorwoche frühzeitig holen (Seed der nächsten Woche, eingefrorener News-Takt)
	if MarketClock.WeekEnd(cur.Week) - t <= (cfg.Seed.PrefetchBefore or 3600) and nextSeed == nil then
		prefetchNext(cur.Week + 1)
	end
	return true
end

local function frameSource(cur: Ctx): QuoteStream.Source
	local engine, director = cur.Engine, cur.Director
	local t = lastTick
	local anyHalt = next(director:AnyHalt(t)) ~= nil
	local crash, rally = director:CrashRally(t)
	local ids: { number } = {}
	for _, i in ipairs(engine:Ids()) do
		if engine:IsActive(i, t) then
			table.insert(ids, i)
		end
	end
	table.sort(ids)
	return {
		Ids = ids,
		Candle = function(i: number)
			return engine:Candle(i)
		end,
		Halted = function(i: number): boolean
			local halted = director:Halted(i, t)
			return halted
		end,
		News = function(i: number): boolean
			return engine:NewsActive(i)
		end,
		ExDay = function(i: number): boolean
			return director:ExDay(i, t)
		end,
		WeekHigh = function(i: number): number
			return store:WeekHigh(i)
		end,
		Regime = engine:Regime(),
		AnyHalt = anyHalt,
		Admin = MarketService.AdminWindowActive(t),
		Crash = crash,
		Rally = rally,
	}
end

local function marketJob()
	if not ready then
		return
	end
	local started = os.clock()
	local target = Clock.Tick()
	local catch = cfg.CatchUp
	if target - lastTick > catch.JumpAfter then
		-- Stillstand: auf jetzt springen, Kerzen-Fenster neu rechnen, verpasste Tagesschlüsse nachholen
		local from = lastTick + 1
		local firstDay = MarketClock.DayIndex(from - 1) + 1
		local lastDay = MarketClock.DayIndex(target - 1)
		local cur = ctxCur
		if cur and MarketClock.WeekIndex(target - 1) == cur.Week then
			ensureBuilt(cur, target - 1)
			lastTick = target - 1
			store:Rebuild(allIds(), from, target - 1, target)
			seedLive(allIds(), target)
			for day = math.max(firstDay, lastDay - MAX_SKIPPED_DAYS + 1), lastDay do
				fire(dayCallbacks, day - 1, day * DAY)
			end
		elseif cur then
			lastTick = math.max(lastTick, MarketClock.WeekEnd(cur.Week))
		end
	end
	local steps = 0
	while lastTick < target and steps < catch.MaxTicksPerRun do
		local t = lastTick + 1
		local ok, result = pcall(advance, t)
		if not ok then
			logError("Tick " .. t, result)
			lastTick = t -- defekten Tick nicht endlos wiederholen
		elseif result == false then
			break -- Wochenwechsel wartet auf den Seed
		else
			lastTick = t
		end
		steps += 1
	end
	local cur = ctxCur
	if steps > 0 and cur then
		local okFrame, err = pcall(function()
			QuoteStream.Broadcast(Remotes.MarketFrame, lastTick, frameSource(cur))
		end)
		if not okFrame then
			logError("Frame", err)
		end
		checkStateChange()
	end
	flushDayClose(false)
	local spent = os.clock() - started
	tickMs = tickMs * 0.9 + spent * 1000 * 0.1
end

local function frameJob()
	if not ready then
		return
	end
	local cur = ctxCur
	if cur then
		-- Plan vorausbauen (mindestens 2 Börsentage), höchstens 1 Tag je Frame
		local wanted = MarketClock.DayIndex(lastTick) + 2
		if cur.Director:BuiltThrough() < wanted then
			cur.Director:EnsureBuilt(wanted, 1)
		end
	end
	if store:Pending() > 0 then
		store:Work(cfg.Backfill.FrameMs)
	end
end

local function busJob()
	if not ready or busPolling then
		return
	end
	busPolling = true
	task.spawn(function()
		local ok, err = pcall(GlobalBus.Poll)
		if not ok then
			logError("Bus-Poll", err)
		end
		busPolling = false
	end)
end

-- ---------------------------------------------------------------------
-- START (Hintergrund-Thread): Seed, Wochenbasis, Plan, Bus, Backfill
-- ---------------------------------------------------------------------
local function loadListings(week: number)
	local season = seasonOfWeek(week)
	for s = 1, season do
		for id, rec in pairs(MarketSeed.LoadIpos(s)) do
			listings[id] = rec
		end
	end
end

local function boot()
	booting = true
	local now = Clock.Tick()
	local week = MarketClock.WeekIndex(now)
	local seed, isLocal = MarketSeed.Load(week)
	localMarket = isLocal
	if not isLocal then
		task.spawn(MarketSeed.EnsureNext, week)
		loadListings(week)
	end
	local tune = MarketSeed.LoadTune(week, cfg.NewsMeanGap)
	local weekStart = MarketClock.WeekStart(week)
	local bases = MarketSeed.LoadClose(week - 1)
	local needPrev = not isLocal and (bases == nil or now - weekStart < cfg.Bus.ExpirySeconds)
	if needPrev then
		local prevSeed = MarketSeed.Peek(week - 1)
		if prevSeed then
			local prevBases = MarketSeed.LoadClose(week - 2) or {}
			local prevTune = MarketSeed.LoadTune(week - 1, cfg.NewsMeanGap)
			local prev = newContext(week - 1, prevSeed, prevBases, prevTune)
			buildDays(prev, MarketClock.DayIndex(MarketClock.WeekEnd(week - 1)), true)
			ctxPrev = prev
			if bases == nil then
				bases = closesOf(prev)
				task.spawn(MarketSeed.SaveClose, week - 1, bases :: { [number]: number })
			end
		end
	end
	local cur = newContext(week, seed, bases or {}, tune)
	ctxCur = cur
	-- Admin-Log der Woche (Admin-Fenster älter als der Bus) + Bus starten (liefert Events der letzten 26 h)
	if not isLocal then
		for _, ev in ipairs(GlobalBus.LoadLog(week)) do
			addWindow(ev)
			if ev.Kind == "CancelAutoShow" then
				onBusEvent(ev, false)
			end
		end
	end
	buildDays(cur, MarketClock.DayIndex(Clock.Tick()) + 1, true)
	GlobalBus.Start(onBusEvent, { Local = isLocal, Now = Clock.Tick })
	-- Live-Start: laufende 5s/1m-Kerzen exakt vorbelegen, Backfill einplanen, Schleife starten
	local liveStart = Clock.Tick()
	if MarketClock.WeekIndex(liveStart) ~= cur.Week then
		liveStart = MarketClock.WeekEnd(cur.Week) -- extrem langer Start über den Wochenwechsel: ab Wochenende nachholen
	end
	buildDays(cur, MarketClock.DayIndex(liveStart) + 1, true)
	local ids = cur.Engine:Ids()
	local candleAt = function(id: number, t: number)
		local c = contextFor(t)
		if c then
			ensureBuilt(c, t)
			local o, h, l, cl, v = c.Engine:CandleAt(id, t)
			return o, h, l, cl, v
		end
		local p = MarketService.PriceAt(id, t)
		return p, p, p, p, 0
	end
	lastTick = liveStart - 1
	-- vor "ready": die Schleife darf die laufenden Buckets noch nicht anfassen (sie holt die Zwischenzeit danach nach)
	for index, id in ipairs(ids) do
		store:SeedPartial(id, liveStart, candleAt)
		if index % 8 == 0 then
			task.wait()
		end
	end
	for _, item in ipairs(cur.Director:LatestNews(lastTick, cfg.NewsKeep)) do
		table.insert(recent, 1, item)
	end
	store:Plan(function(id: number, t0: number)
		return MarketService.NewCursor(id, t0)
	end, ids, liveStart)
	ready = true
	booting = false
	markAllDirty()
	print(
		("[MarketService] Markt läuft – Woche %d, %d Instrumente%s"):format(
			week,
			#ids,
			if isLocal then " (Lokaler Testmarkt)" else ""
		)
	)
end

-- ---------------------------------------------------------------------
-- ANFRAGEN (§C9)
-- ---------------------------------------------------------------------
local function validInst(i: any): boolean
	if not isInt(i) then
		return false
	end
	local cur = ctxCur
	return cur ~= nil and cur.Engine:Has(i) and cur.Engine:IsActive(i, lastTick)
end

local function handleCandles(p: Player, arg: any): Types.Reply
	if not exactKeys(arg, { "I", "Tf" }) or not isInt(arg.I) or type(arg.Tf) ~= "string" then
		return reply(p, false, "mkt.invalid")
	end
	local tf = QuoteCodec.TF[arg.Tf]
	if tf == nil then
		return reply(p, false, "mkt.invalid")
	end
	if not ready then
		return reply(p, false, "mkt.notReady")
	end
	if not validInst(arg.I) then
		return reply(p, false, "mkt.unknownInst")
	end
	local buf = store:Get(arg.I, tf)
	if buf == nil then
		return reply(p, false, "mkt.historyLoading")
	end
	return { Ok = true, Buf = buf }
end

local function researchLead(p: Player): number
	local research = cfg.Research
	local minutes = research.BaseLeadMinutes
	local ok, perks = call("ProgressionService", "TradingPerks", p)
	if ok and type(perks) == "table" and Util.IsFinite(perks.ResearchLead) then
		local lead = perks.ResearchLead
		minutes = if lead > 10 then lead / 60 else lead -- Minuten (2/3/5) oder Sekunden
	end
	return math.clamp(minutes, research.BaseLeadMinutes, research.MaxLeadMinutes) * 60
end

local function handleProfile(p: Player, arg: any): Types.Reply
	if not exactKeys(arg, { "I" }) or not isInt(arg.I) then
		return reply(p, false, "mkt.invalid")
	end
	if not ready then
		return reply(p, false, "mkt.notReady")
	end
	local i = arg.I
	local entry = inst(i)
	local cur = ctxCur
	if entry == nil or cur == nil or entry.Set == "Tutorial" then
		return reply(p, false, "mkt.unknownInst")
	end
	local profile: Plain
	if entry.Class == "ETF" then
		profile = { I = i, Etf = true, Members = entry.Members }
	else
		local isPipeline = entry.Ipo == true and inPipeline(i, cur.Week)
		if not validInst(i) and not isPipeline then
			return reply(p, false, "mkt.unknownInst")
		end
		local built = cur.Director:Profile(i, lastTick, researchLead(p))
		if built == nil then
			return reply(p, false, "mkt.unknownInst")
		end
		profile = built
	end
	local _, _, mid = cur.Engine:Quote(i)
	local hi, lo = store:Range(i)
	profile.Ticker = entry.Ticker
	profile.Class = entry.Class
	profile.Mid = mid
	profile.WeekHigh = hi
	profile.WeekLow = lo
	if mid and profile.Eps and profile.Eps > 0 then
		profile.Pe = math.round(mid / profile.Eps * 10) / 10
	end
	return { Ok = true, Profile = profile }
end

local function handleCalendar(p: Player, arg: any): Types.Reply
	if not exactKeys(arg, { "Days" }) or not isInt(arg.Days) or arg.Days < 1 or arg.Days > 3 then
		return reply(p, false, "mkt.invalid")
	end
	if not ready then
		return reply(p, false, "mkt.notReady")
	end
	return { Ok = true, Items = MarketService.Calendar(arg.Days) }
end

local function handleNews(p: Player, arg: any): Types.Reply
	if not exactKeys(arg, {}) then
		return reply(p, false, "mkt.invalid")
	end
	return { Ok = true, Items = MarketService.RecentNews(cfg.NewsKeep) }
end

-- ---------------------------------------------------------------------
-- INIT / START
-- ---------------------------------------------------------------------
function MarketService.Init(services: any)
	Services = services
	local pss = service("PlayerStateService")
	if pss then
		pss.Provide("Market", function(_p: Player)
			return marketState()
		end)
		local buckets = cfg.Buckets
		pss.Handle("MktCandles", handleCandles, { Bucket = buckets.MktCandles })
		pss.Handle("MktProfile", handleProfile, { Bucket = buckets.MktProfile })
		pss.Handle("MktCalendar", handleCalendar, { Bucket = buckets.MktCalendar })
		pss.Handle("MktNews", handleNews, { Rate = cfg.NewsRate[1], Per = cfg.NewsRate[2] })
	else
		warn("[MarketService] PlayerStateService fehlt – keine Markt-Anfragen")
	end
end

function MarketService.Start()
	-- Tagesrendite (für DayClose je Spieler + Ausreißer-Statistik) und Fill-Audit über die Signale von WP4
	call("OrderService", "OnDayResult", onDayResult)
	call("OrderService", "OnTrade", function(p: Player, f: Plain)
		if type(f) ~= "table" then
			return
		end
		MarketAudit.VerifyFill(f, {
			CandleAt = function(i: number, t: number)
				local o, h, l, c = MarketService.Candle1s(i, t)
				return o, h, l, c
			end,
			Quote = function(i: number, t: number)
				local tick = clampTick(t)
				local ctx = contextFor(tick)
				if ctx == nil or not ctx.Engine:IsActive(i, tick) then
					return nil, nil
				end
				local bid, ask = ctx.Engine:QuoteAt(i, tick)
				return bid, ask
			end,
		})
		local _ = p
	end)
	Players.PlayerRemoving:Connect(function(p: Player)
		adminCooldown[p.UserId] = nil
		MarketAudit.Clear(p.UserId)
		local pending = pendingDay
		if pending then
			pending.Sent[p] = nil
		end
	end)
	Scheduler.Every("Market", 1, marketJob)
	Scheduler.EveryFrame("MarketBackfill", frameJob)
	Scheduler.Every("MarketBus", 1 / math.max(1, cfg.Bus.PollSeconds), busJob)
	if not booting and not ready then
		task.spawn(function()
			local ok, err = xpcall(boot, debug.traceback)
			if not ok then
				booting = false
				warn("[MarketService] Start fehlgeschlagen: " .. tostring(err))
			end
		end)
	end
	local _ = RunService
end

return MarketService
