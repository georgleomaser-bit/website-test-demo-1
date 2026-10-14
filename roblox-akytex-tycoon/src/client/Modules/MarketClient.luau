-- =====================================================================
--  AKYTEX TYCOON – Markt-Client: Frame dekodieren, Kerzen aus dem Strom, Historie, Lizenz-Filter
--  (Client/Modules/MarketClient)
--  Besitzer: WP5 (Charts, Terminal, Markt-UI). Vertrag: DESIGN.md §C7.5 (WP5-Teil), §C7.2 (Hooks "Quotes"/"Replay"),
--  §C8 (MarketFrame/Replay), §C9 (MktCandles), §B6.2 (Lizenz-Sätze), §B7.2/§B7.5 (Schichten, Indikatoren);
--  MARKET.md §9.4 (Client-Kerzen, Lücke > 2 Ticks -> Historie neu), §10.2 (Frame-Format).
--
--  Ablauf: Remote "MarketFrame" (1 Hz, buffer) -> QuoteCodec.DecodeFrame -> je Instrument die 1s-Kerze
--  (Open = Schluss des Vortick, Hoch/Tief aus HiOff/LoOff) -> in alle geladenen Kerzen-Reihen (1s/5s/1m/…)
--  einrechnen -> Hook "Quotes"(frame). Historie je (Instrument, Zeitrahmen) einmal per Request "MktCandles"
--  (eigener Token-Bucket unter dem Server-Bucket 6/2, höchstens 2 Anfragen gleichzeitig), danach live aus dem Strom.
--  Lücke im Tick-Zähler > 2: offene (verfolgte) Reihen werden neu angefordert, alle anderen verworfen.
--  Tagesbeginn je Wert: exakt aus dem Strom (Glocke miterlebt) oder aus der 1T-Historie (Hintergrund, niedrige
--  Priorität). Übungsaktie ACAD (Remote "Replay", nur Tutorial) -> Hook "Replay"(tick, close, phase).
--
--  Öffentliche API (§C7.5):
--    MarketClient.Frame(): Types.Frame?              letzter dekodierter Frame
--    MarketClient.Quote(i): (number?, number?)       Schluss (Cent), Veränderung seit Tagesbeginn als ANTEIL (0.0235)
--                                                    – nil, solange der Tagesbeginn noch unbekannt ist
--    MarketClient.Candles(i, tf, cb)                 cb(candles) einmalig: Historie + Strom, gecacht (nicht verändern!)
--    MarketClient.Instrument(i): Types.Instrument?   MarketClient.Allowed(i): boolean (Lizenz-Satz, gelistet)
--    MarketClient.Regime(): number
--  Zusätzlich: Track(i, tf, fn) -> trennen (fn bei jedem (Neu-)Laden), SeriesError(i, tf), NextSeq(), Row(i),
--    Ids(), AllowedIds(), Tick(),
--    BidAsk(i): (bid, ask, mid), Halted(i), Flags(), Candle1s(i), DayOpen(i), Spark(i), Sector(i),
--    Licence(), LicenceDef(idx?), LicenceName(idx?), Layer(), Perks(), Practice(), Init(ctx), Start()
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local QuoteCodec = require(Shared:WaitForChild("Market"):WaitForChild("QuoteCodec"))

local MarketClient = {}

type Candle = Types.Candle
type Frame = Types.Frame
type QuoteRow = Types.QuoteRow

type Series = {
	Key: string,
	I: number,
	Tf: string,
	Ticks: number,
	Candles: { Candle },
	Loaded: boolean,
	InFlight: boolean,
	Queued: boolean,
	Waiters: { (candles: { Candle }) -> () },
	Trackers: { [number]: (candles: { Candle }) -> () },
	TrackCount: number,
	AsOf: number,
	RetryAt: number,
	Fails: number,
	Error: string?,
	LastUse: number,
	Prefetch: boolean,
}

type Practice = { Tick: number, Close: number, Phase: number, At: number, Candles: { Candle } }

local DAY = 1200
local MAX_KEEP = 320 -- so viele Kerzen je Reihe (Chart ≤ 120 + Aufwärmen der Indikatoren)
local RECENT_1S = 16 -- letzte 1s-Kerzen je Wert (nach dem Laden der Historie nachrechnen)
local SPARK_STEP = 10 -- Ticks zwischen zwei Sparkline-Punkten
local SPARK_MAX = 48
local BUCKET_CAP = 5 -- eigener Anfrage-Bucket (Server: 6 Kapazität, 2/s)
local BUCKET_RATE = 1.8
local MAX_IN_FLIGHT = 2
local RETRY_BASE = 2.5 -- Sekunden bis zum nächsten Versuch (wächst bis RETRY_MAX)
local RETRY_MAX = 20
local IDLE_DROP = 180 -- nicht verfolgte Reihen nach so vielen Sekunden ohne Nutzung verwerfen
local PRACTICE_STALE = 4 -- ohne Replay-Paket so lange -> Übung nicht mehr aktiv
local PRACTICE_KEEP = 240
local REMOTE_RETRIES = 6
local REMOTE_RETRY_GAP = 5

local SET_RANK: { [string]: number } = { Azubi = 1, Trader = 2, Fonds = 3 }
-- Indikatoren ab Lizenz (§B7.5): SMA/EMA Azubi III · Bollinger Trader I · RSI Trader II · MACD/VWAP Trader III ·
-- Stochastik/ATR Fondsmanager I
local INDICATOR_FROM: { [string]: number } = {
	SMA20 = 3,
	SMA50 = 3,
	SMA200 = 3,
	EMA9 = 3,
	EMA21 = 3,
	BB = 4,
	RSI = 5,
	MACD = 6,
	VWAP = 6,
	Stoch = 7,
	ATR = 7,
}

local ctx: any = nil
local companies: any = {}
local marketCfg: any = {}
local lastFrame: Frame? = nil
local lastTick = 0
local rows: { [number]: QuoteRow } = {}
local activeIds: { number } = {}
local prevClose: { [number]: number } = {}
local live1s: { [number]: Candle } = {}
local recent: { [number]: { Candle } } = {}
local recentHead: { [number]: number } = {}
local dayOpen: { [number]: number } = {}
local dayOpenDay: { [number]: number } = {}
local spark: { [number]: { number } } = {}
local series: { [string]: Series } = {}
local seriesByInst: { [number]: { Series } } = {}
local tokens = BUCKET_CAP
local tokenClock = os.clock()
local inFlight = 0
local trackIdCounter = 0
local practice: Practice? = nil
local connected: { [string]: boolean } = {}
local errorAt: { [string]: number } = {}

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function logOnce(source: string, err: any)
	local now = os.clock()
	if now - (errorAt[source] or -math.huge) >= 10 then
		errorAt[source] = now
		warn(("[MarketClient] %s: %s"):format(source, tostring(err)))
	end
end

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function state(): { [string]: any }
	local s = ctx and ctx.State
	return if type(s) == "table" then s else {}
end

local function tfTicks(tf: string): number?
	local ticks = (QuoteCodec.TF :: any)[tf]
	if type(ticks) == "number" and ticks >= 1 then
		return ticks
	end
	return nil
end

local function instOf(i: number): any
	local byId = companies.ById
	return if type(byId) == "table" then byId[i] else nil
end

-- ---------------------------------------------------------------------
-- LIZENZ, SCHICHT, WERKZEUGE (nur Lizenz + Know-how, nie Robux – §0.4)
-- ---------------------------------------------------------------------
function MarketClient.Licence(): number
	local prog = state().Prog
	local idx = if type(prog) == "table" then prog.Licence else nil
	if type(idx) == "number" and idx == idx then
		return math.clamp(math.floor(idx), 1, 10)
	end
	return 1
end

function MarketClient.LicenceDef(idx: number?): { [string]: any }
	local index = math.clamp(math.floor(tonumber(idx) or MarketClient.Licence()), 1, 10)
	local config = ctx and ctx.Config
	local progression = config and config.Progression
	local list = type(progression) == "table" and progression.Licences or nil
	local def = type(list) == "table" and list[index] or nil
	if type(def) == "table" and type(def.Set) == "string" and type(def.Layer) == "string" then
		return def
	end
	local trading = config and config.Trading
	local fallback = type(trading) == "table" and trading.LicenceFallback or nil
	local entry = type(fallback) == "table" and fallback[index] or nil
	if type(entry) == "table" then
		return entry
	end
	return {
		Key = "Azubi1",
		Set = "Azubi",
		Layer = "Simple",
		FeeBps = 10,
		MaxWeight = 0.30,
		MaxOrders = 5,
		PosFactor = 0.01,
		BotSlots = 0,
		BauKurs = 40,
		Basis = 2500000,
	}
end

function MarketClient.LicenceName(idx: number?): string
	local index = math.clamp(math.floor(tonumber(idx) or MarketClient.Licence()), 1, 10)
	local def = MarketClient.LicenceDef(index)
	local name = def.Name
	if type(name) == "table" and ctx and ctx.Lang then
		local text = ctx.Lang.Pick(ctx.Lang_(), name)
		if type(text) == "string" and text ~= "" then
			return text
		end
	end
	if ctx then
		return ctx.T("term.lic." .. tostring(index))
	end
	return tostring(index)
end

function MarketClient.Layer(): string
	local layer = MarketClient.LicenceDef().Layer
	if layer == "Trader" or layer == "Pro" then
		return layer
	end
	return "Simple"
end

-- TradingPerks-Ersatz: kommt der Server-Wert mit (State Prog.Tools = ProgressionService Core.TradingPerks), gilt er;
-- sonst aus Lizenz + Know-how. (Prog.Perks ist der Vorstands-Perk-Baum des Börsengangs – NICHT die Werkzeuge.)
function MarketClient.Perks(): { [string]: any }
	local prog = state().Prog
	local raw = if type(prog) == "table" then prog.Tools else nil
	if type(raw) == "table" and type(raw.Indicators) == "table" then
		return raw
	end
	local licence = MarketClient.Licence()
	local def = MarketClient.LicenceDef(licence)
	local kh: { [string]: any } = {}
	if type(prog) == "table" then
		if type(prog.KnowHow) == "table" then
			kh = prog.KnowHow
		elseif type(prog.KH) == "table" then
			kh = prog.KH
		end
	end
	local function level(key: string): number
		local v = kh[key]
		return if finite(v) then math.max(0, math.floor(v)) else 0
	end
	local indicators: { [string]: boolean } = {}
	for name, from in pairs(INDICATOR_FROM) do
		indicators[name] = licence >= from
	end
	local botLevels: { [string]: number } = {}
	for _, preset in ipairs({ "Sparplan", "Trend", "Dividend", "Dip" }) do
		botLevels[preset] = level("BotLvl." .. preset)
	end
	return {
		Licence = licence,
		Layer = MarketClient.Layer(),
		BotSlots = if finite(def.BotSlots) then def.BotSlots else 0,
		BotLevels = botLevels,
		Alerts = math.min(18, 3 + 3 * level("Alerts")),
		Watchlists = math.min(5, 1 + level("Watch")),
		Layouts = 1 + level("Layouts"),
		Monitors = level("Monitors"),
		ResearchLead = 2 + (if level("Research") >= 2 then 3 elseif level("Research") >= 1 then 1 else 0),
		MultiChart = level("MultiChart") >= 1 and licence >= 7,
		Risk = level("Risk"),
		Indicators = indicators,
	}
end

-- ---------------------------------------------------------------------
-- INSTRUMENTE
-- ---------------------------------------------------------------------
function MarketClient.Instrument(i: number): any
	if type(i) ~= "number" then
		return nil
	end
	return instOf(i)
end

function MarketClient.Allowed(i: number): boolean
	local inst = MarketClient.Instrument(i)
	if type(inst) ~= "table" or inst.Set == "Tutorial" then
		return false
	end
	if inst.Ipo == true and rows[i] == nil then
		return false -- IPO erst ab Erstnotiz (im Frame)
	end
	local rank = SET_RANK[MarketClient.LicenceDef().Set] or 1
	return (SET_RANK[inst.Set] or 3) <= rank
end

-- erlaubte Werte, sortiert: ETFs zuerst (AKX36 vorn), dann nach Id
function MarketClient.AllowedIds(): { number }
	local out: { number } = {}
	local list = companies.Instruments
	if type(list) ~= "table" then
		return out
	end
	for _, inst in ipairs(list) do
		if type(inst) == "table" and type(inst.Id) == "number" and MarketClient.Allowed(inst.Id) then
			table.insert(out, inst.Id)
		end
	end
	table.sort(out, function(a: number, b: number): boolean
		local ia, ib = instOf(a), instOf(b)
		local ca = if ia and ia.Class == "ETF" then 0 else 1
		local cb = if ib and ib.Class == "ETF" then 0 else 1
		if ca ~= cb then
			return ca < cb
		end
		return a < b
	end)
	return out
end

function MarketClient.Sector(i: number): { Key: string, Name: string, Color: Color3 }?
	local inst = MarketClient.Instrument(i)
	if type(inst) ~= "table" then
		return nil
	end
	local sectors = companies.Sectors
	if type(sectors) == "table" then
		for _, sector in ipairs(sectors) do
			if type(sector) == "table" and sector.Key == inst.Sector then
				local name = sector.Key
				if ctx and ctx.Lang and type(sector.Name) == "table" then
					name = ctx.Lang.Pick(ctx.Lang_(), sector.Name)
				end
				return { Key = sector.Key, Name = name, Color = sector.Color }
			end
		end
	end
	local etfName = if ctx then ctx.T("term.sector.etf") else "ETF"
	return { Key = "X", Name = etfName, Color = Color3.fromRGB(79, 140, 255) }
end

-- ---------------------------------------------------------------------
-- KURSE
-- ---------------------------------------------------------------------
function MarketClient.Frame(): Frame?
	return lastFrame
end

function MarketClient.Tick(): number
	return lastTick
end

function MarketClient.Row(i: number): QuoteRow?
	return rows[i]
end

function MarketClient.Ids(): { number }
	return activeIds
end

function MarketClient.Regime(): number
	local frame = lastFrame
	if frame and finite(frame.Regime) and frame.Regime > 0 then
		return frame.Regime
	end
	local market = state().Market
	if type(market) == "table" and finite(market.Regime) and market.Regime > 0 then
		return market.Regime
	end
	return 1
end

function MarketClient.DayOpen(i: number): number?
	local day = lastTick // DAY
	if dayOpenDay[i] == day then
		return dayOpen[i]
	end
	return nil
end

function MarketClient.Quote(i: number): (number?, number?)
	local row = rows[i]
	if not row then
		return nil, nil
	end
	local open = MarketClient.DayOpen(i)
	if open and open > 0 then
		return row.Close, (row.Close - open) / open
	end
	return row.Close, nil
end

-- Geld/Brief aus mid (gleiche Formel wie der Server, Spread je Klasse × Regime)
function MarketClient.BidAsk(i: number): (number?, number?, number?)
	local row = rows[i]
	local inst = MarketClient.Instrument(i)
	if not row or type(inst) ~= "table" then
		return nil, nil, nil
	end
	local classes = marketCfg.Classes
	local class = type(classes) == "table" and classes[inst.Class] or nil
	local bps = if type(class) == "table" and finite(class.SpreadBps) then class.SpreadBps else 8
	local bid, ask = QuoteCodec.Spread(row.Close, bps, MarketClient.Regime())
	return bid, ask, row.Close
end

function MarketClient.Halted(i: number): boolean
	local row = rows[i]
	if row and bit32.band(row.Flags, QuoteCodec.ROW_FLAGS.Halt) ~= 0 then
		return true
	end
	local market = state().Market
	local halts = type(market) == "table" and market.Halts or nil
	if type(halts) == "table" then
		local all = halts["0"]
		local one = halts[tostring(i)]
		if (finite(all) and all > lastTick) or (finite(one) and one > lastTick) then
			return true
		end
	end
	return false
end

function MarketClient.Flags(): { Halt: boolean, Admin: boolean, Crash: boolean, Rally: boolean }
	local flags = if lastFrame then lastFrame.Flags else 0
	local f = QuoteCodec.FRAME_FLAGS
	return {
		Halt = bit32.band(flags, f.Halt) ~= 0,
		Admin = bit32.band(flags, f.Admin) ~= 0,
		Crash = bit32.band(flags, f.Crash) ~= 0,
		Rally = bit32.band(flags, f.Rally) ~= 0,
	}
end

function MarketClient.Candle1s(i: number): Candle?
	return live1s[i]
end

-- Mini-Kurve für Watchlist/Karten: Stichproben (alle 10 Ticks) + aktueller Schluss
function MarketClient.Spark(i: number): { number }
	local samples = spark[i]
	local out: { number } = {}
	if samples then
		for _, v in ipairs(samples) do
			table.insert(out, v)
		end
	end
	local row = rows[i]
	if row then
		table.insert(out, row.Close)
	end
	return out
end

-- Sequenznummer für Trade-Anfragen (TradePlace/Cancel/Modify/Basket): monoton und über Sitzungen hinweg
-- verschieden (Server merkt sich die letzten 32 im Depot) – Basis = Server-Sekunde · 1024, höchstens 2^31
local seqLast = 0
function MarketClient.NextSeq(): number
	local now = if ctx and ctx.Clock then ctx.Clock.Now() else os.time()
	local base = (math.floor(now) % 2097152) * 1024
	seqLast = math.max(seqLast + 1, base)
	if seqLast > 2 ^ 31 then
		seqLast = base
	end
	return seqLast
end

-- ---------------------------------------------------------------------
-- KERZEN-REIHEN (Historie + Strom)
-- ---------------------------------------------------------------------
local function seriesKey(i: number, tf: string): string
	return tostring(i) .. ":" .. tf
end

local function getSeries(i: number, tf: string): Series?
	local ticks = tfTicks(tf)
	if not ticks then
		return nil
	end
	local key = seriesKey(i, tf)
	local s = series[key]
	if not s then
		local fresh: Series = {
			Key = key,
			I = i,
			Tf = tf,
			Ticks = ticks,
			Candles = {},
			Loaded = false,
			InFlight = false,
			Queued = false,
			Waiters = {},
			Trackers = {},
			TrackCount = 0,
			AsOf = 0,
			RetryAt = 0,
			Fails = 0,
			Error = nil,
			LastUse = os.clock(),
			Prefetch = false,
		}
		series[key] = fresh
		local list = seriesByInst[i]
		if not list then
			list = {}
			seriesByInst[i] = list
		end
		table.insert(list, fresh)
		s = fresh
	end
	return s
end

local function dropSeries(s: Series)
	series[s.Key] = nil
	local list = seriesByInst[s.I]
	if list then
		local index = table.find(list, s)
		if index then
			table.remove(list, index)
		end
		if #list == 0 then
			seriesByInst[s.I] = nil
		end
	end
end

-- eine 1s-Kerze in eine Reihe einrechnen (Bucket = T // tf · tf, Open = Schluss der Vorkerze)
local function applyCandle(s: Series, c: Candle)
	if c.T <= s.AsOf then
		return -- steckt schon in der Historie
	end
	local list = s.Candles
	local bucket = (c.T // s.Ticks) * s.Ticks
	local last = list[#list]
	if last and last.T == bucket then
		if c.H > last.H then
			last.H = c.H
		end
		if c.L < last.L then
			last.L = c.L
		end
		last.C = c.C
		last.V += c.V
	elseif last == nil or bucket > last.T then
		local open = if last then last.C else c.O
		table.insert(list, {
			T = bucket,
			O = open,
			H = math.max(open, c.H),
			L = math.min(open, c.L),
			C = c.C,
			V = c.V,
		})
		if #list > MAX_KEEP then
			table.remove(list, 1)
		end
	end
end

local function notifyLoaded(s: Series)
	local waiters = s.Waiters
	s.Waiters = {}
	for _, fn in ipairs(waiters) do
		local ok, err = pcall(fn, s.Candles)
		if not ok then
			logOnce("Candles-Callback", err)
		end
	end
	for _, fn in pairs(s.Trackers) do
		local ok, err = pcall(fn, s.Candles)
		if not ok then
			logOnce("Track-Callback", err)
		end
	end
end

local function onHistory(s: Series, candles: { Candle })
	-- Tagesbeginn aus der 1T-Historie (letzte Kerze = laufender Börsentag)
	if s.Tf == "1T" then
		local last = candles[#candles]
		if last and last.T // DAY == lastTick // DAY and last.O > 0 and dayOpenDay[s.I] ~= last.T // DAY then
			dayOpen[s.I] = last.O
			dayOpenDay[s.I] = last.T // DAY
		end
	end
	-- Sparkline mit echten 1m-Schlusskursen vorbelegen
	if s.Tf == "1m" then
		local samples: { number } = {}
		for index = math.max(1, #candles - SPARK_MAX + 1), #candles do
			table.insert(samples, candles[index].C)
		end
		if #samples >= 2 then
			spark[s.I] = samples
		end
	end
	while #candles > MAX_KEEP do
		table.remove(candles, 1)
	end
	s.Candles = candles
	local last = candles[#candles]
	s.AsOf = math.max(lastTick, if last then last.T else 0)
	-- 1s-Kerzen, die nach dem Stand der Antwort kamen, nachrechnen
	local ring = recent[s.I]
	if ring then
		local head = recentHead[s.I] or 0
		local ordered: { Candle } = {}
		for k = 1, #ring do
			local c = ring[((head + k - 1) % #ring) + 1]
			if c and c.T > s.AsOf then
				table.insert(ordered, c)
			end
		end
		table.sort(ordered, function(a: Candle, b: Candle): boolean
			return a.T < b.T
		end)
		local asOf = s.AsOf
		for _, c in ipairs(ordered) do
			applyCandle(s, c)
			asOf = math.max(asOf, c.T)
		end
		s.AsOf = asOf
	end
	s.Loaded = true
	s.Error = nil
	s.Fails = 0
	s.Prefetch = false -- Vorab-Ladung erledigt: darf nach IDLE_DROP wieder verworfen werden
	s.LastUse = os.clock()
	notifyLoaded(s)
end

local function refillTokens()
	local now = os.clock()
	tokens = math.min(BUCKET_CAP, tokens + (now - tokenClock) * BUCKET_RATE)
	tokenClock = now
end

local function sendRequest(s: Series)
	s.InFlight = true
	s.Queued = false
	inFlight += 1
	tokens -= 1
	task.spawn(function()
		local ok, reply = pcall(function()
			return ctx.RequestFull("MktCandles", { I = s.I, Tf = s.Tf }, true)
		end)
		inFlight = math.max(0, inFlight - 1)
		s.InFlight = false
		if series[s.Key] ~= s then
			return -- inzwischen verworfen
		end
		if ok and type(reply) == "table" and reply.Ok and typeof(reply.Buf) == "buffer" then
			local inst, tf, _, candles = QuoteCodec.DecodeCandles(reply.Buf)
			if inst == s.I and tf == s.Ticks and candles then
				onHistory(s, candles)
				return
			end
		end
		s.Fails += 1
		s.RetryAt = os.clock() + math.min(RETRY_MAX, RETRY_BASE * s.Fails)
		local message = if ok and type(reply) == "table" and type(reply.Message) == "string" then reply.Message else nil
		s.Error = message or (if ctx then ctx.T("mkt.historyLoading") else nil)
		s.Queued = true -- erneut versuchen, solange jemand wartet oder verfolgt
	end)
end

-- Anfrage-Pumpe: verfolgte Reihen zuerst, dann wartende, dann Vorab-Ladungen (Tagesbeginn) nur mit Reserve
local function pump()
	if not ctx then
		return
	end
	refillTokens()
	local now = os.clock()
	local guard = 0
	while inFlight < MAX_IN_FLIGHT and tokens >= 1 and guard < 8 do
		guard += 1
		local best: Series? = nil
		local bestScore = -math.huge
		for _, s in pairs(series) do
			if s.Queued and not s.InFlight and now >= s.RetryAt then
				local wanted = s.TrackCount > 0 or #s.Waiters > 0
				if not wanted and not s.Prefetch then
					s.Queued = false
				else
					local score = (if s.TrackCount > 0 then 1000 else 0)
						+ (if #s.Waiters > 0 then 500 else 0)
						- s.Fails * 10
						- (now - s.LastUse) * 0.01
					if s.Prefetch and not wanted then
						score -= 2000 -- nur mit Reserve
					end
					if score > bestScore then
						best, bestScore = s, score
					end
				end
			end
		end
		local chosen = best
		if not chosen then
			return
		end
		if bestScore < -1000 and tokens < BUCKET_CAP - 1 then
			return -- Vorab-Ladung nur, wenn der Bucket fast voll ist
		end
		sendRequest(chosen)
	end
end

local function queue(s: Series)
	s.LastUse = os.clock()
	if s.InFlight then
		return
	end
	s.Queued = true
	task.defer(pump)
end

function MarketClient.Candles(i: number, tf: string, cb: (candles: { Candle }) -> ())
	if type(i) ~= "number" or type(tf) ~= "string" or type(cb) ~= "function" then
		return
	end
	local s = getSeries(i, tf)
	if not s then
		return
	end
	s.LastUse = os.clock()
	s.Prefetch = false
	if s.Loaded then
		local ok, err = pcall(cb, s.Candles)
		if not ok then
			logOnce("Candles-Callback", err)
		end
		return
	end
	table.insert(s.Waiters, cb)
	queue(s)
end

-- Reihe "offen halten": fn(candles) bei jedem Laden und Neu-Laden (Lücke > 2 Ticks). Rückgabe = trennen.
function MarketClient.Track(i: number, tf: string, fn: (candles: { Candle }) -> ()): () -> ()
	local s = if type(i) == "number" and type(tf) == "string" then getSeries(i, tf) else nil
	if not s or type(fn) ~= "function" then
		return function() end
	end
	local entry = s :: Series
	trackIdCounter += 1
	local id = trackIdCounter
	entry.Trackers[id] = fn
	entry.TrackCount += 1
	entry.Prefetch = false
	entry.LastUse = os.clock()
	if entry.Loaded then
		local ok, err = pcall(fn, entry.Candles)
		if not ok then
			logOnce("Track-Callback", err)
		end
	else
		queue(entry)
	end
	return function()
		if entry.Trackers[id] then
			entry.Trackers[id] = nil
			entry.TrackCount = math.max(0, entry.TrackCount - 1)
			entry.LastUse = os.clock()
		end
	end
end

-- Fehlertext einer Reihe (für den Platzhalter im Chart) – nil, wenn alles gut ist
function MarketClient.SeriesError(i: number, tf: string): string?
	local s = series[seriesKey(i, tf)]
	return if s and not s.Loaded then s.Error else nil
end

-- ---------------------------------------------------------------------
-- FRAME-VERARBEITUNG
-- ---------------------------------------------------------------------
local function pushRecent(i: number, c: Candle)
	local ring = recent[i]
	if not ring then
		ring = {}
		recent[i] = ring
	end
	local head = ((recentHead[i] or 0) % RECENT_1S) + 1
	recentHead[i] = head
	local slot = ring[head]
	if slot then
		slot.T, slot.O, slot.H, slot.L, slot.C, slot.V = c.T, c.O, c.H, c.L, c.C, c.V
	else
		ring[head] = { T = c.T, O = c.O, H = c.H, L = c.L, C = c.C, V = c.V }
	end
end

local function needDayOpen(i: number)
	local s = getSeries(i, "1T")
	if s and not s.Loaded and not s.InFlight and not s.Queued and s.TrackCount == 0 and #s.Waiters == 0 then
		s.Prefetch = true
		s.Queued = true
	end
end

local function onGap()
	for _, s in pairs(series) do
		if s.Loaded then
			if s.TrackCount > 0 then
				s.Loaded = false
				s.Queued = true
				s.RetryAt = 0
			else
				dropSeries(s)
			end
		end
	end
	table.clear(prevClose)
end

local function onFrame(payload: any)
	if typeof(payload) ~= "buffer" then
		return
	end
	local frame = QuoteCodec.DecodeFrame(payload)
	if not frame then
		return
	end
	if frame.Tick <= lastTick then
		return -- alt oder doppelt
	end
	local gap = if lastTick > 0 then frame.Tick - lastTick else 1
	if gap > 2 then
		onGap()
	end
	local consecutive = gap == 1
	local day = frame.Tick // DAY
	local newRows: { [number]: QuoteRow } = {}
	local ids: { number } = table.create(#frame.Rows)
	for _, row in ipairs(frame.Rows) do
		local i = row.Id
		newRows[i] = row
		table.insert(ids, i)
		local c = row.Close
		local before = prevClose[i]
		local o = if consecutive and before and before > 0 then before else c
		local candle = live1s[i]
		if not candle then
			candle = { T = 0, O = 0, H = 0, L = 0, C = 0, V = 0 }
			live1s[i] = candle
		end
		candle.T = frame.Tick
		candle.O = o
		candle.C = c
		candle.H = math.max(QuoteCodec.HiFrom(o, c, row.HiOff), o, c)
		candle.L = math.min(QuoteCodec.LoFrom(o, c, row.LoOff), o, c)
		candle.V = row.Vol
		pushRecent(i, candle)
		-- Tagesbeginn: Glocke im Strom miterlebt -> exakt (Open der ersten Sekunde = Schluss des Vortags)
		if dayOpenDay[i] ~= day then
			if consecutive and before and before > 0 and (frame.Tick - 1) // DAY < day then
				dayOpen[i] = before
				dayOpenDay[i] = day
			else
				needDayOpen(i)
			end
		end
		-- in alle geladenen Reihen dieses Werts
		local list = seriesByInst[i]
		if list then
			for _, s in ipairs(list) do
				if s.Loaded then
					applyCandle(s, candle)
					s.AsOf = math.max(s.AsOf, frame.Tick)
				end
			end
		end
		-- Sparkline-Stichprobe
		if frame.Tick % SPARK_STEP == 0 then
			local samples = spark[i]
			if not samples then
				samples = {}
				spark[i] = samples
			end
			table.insert(samples, c)
			if #samples > SPARK_MAX then
				table.remove(samples, 1)
			end
		end
		prevClose[i] = c
	end
	-- nicht mehr gelistete Werte vergessen
	for i in pairs(rows) do
		if newRows[i] == nil then
			prevClose[i] = nil
			live1s[i] = nil
		end
	end
	table.sort(ids)
	rows = newRows
	activeIds = ids
	lastTick = frame.Tick
	lastFrame = frame
	-- ungenutzte Reihen aufräumen
	local now = os.clock()
	for _, s in pairs(series) do
		if s.TrackCount == 0 and #s.Waiters == 0 and not s.Prefetch and not s.InFlight then
			if now - s.LastUse > IDLE_DROP then
				dropSeries(s)
			end
		end
	end
	pump()
	ctx.Hooks.Fire("Quotes", frame)
end

-- ---------------------------------------------------------------------
-- ÜBUNGSAKTIE ACAD (Remote "Replay")
-- ---------------------------------------------------------------------
local function notePractice(tick: number, close: number, phase: number)
	if not finite(tick) or not finite(close) or close <= 0 then
		return
	end
	local p = practice
	if p == nil or tick < p.Tick - 5 or os.clock() - p.At > PRACTICE_STALE * 3 then
		p = { Tick = 0, Close = close, Phase = 0, At = 0, Candles = {} }
		practice = p
	end
	local pr = p :: Practice
	if tick <= pr.Tick then
		pr.At = os.clock()
		return
	end
	local last = pr.Candles[#pr.Candles]
	local open = if last then last.C else close
	table.insert(pr.Candles, {
		T = tick,
		O = open,
		H = math.max(open, close),
		L = math.min(open, close),
		C = close,
		V = 0,
	})
	if #pr.Candles > PRACTICE_KEEP then
		table.remove(pr.Candles, 1)
	end
	pr.Tick = tick
	pr.Close = close
	pr.Phase = phase
	pr.At = os.clock()
end

local function onReplay(payload: any)
	local tick, close, phase = QuoteCodec.DecodeReplay(payload)
	if type(tick) ~= "number" or type(close) ~= "number" then
		return
	end
	notePractice(tick, close, phase or 0)
	ctx.Hooks.Fire("Replay", tick, close, phase or 0)
end

-- laufende Übung (nil, wenn seit PRACTICE_STALE s kein Paket kam)
function MarketClient.Practice(): Practice?
	local p = practice
	if p and os.clock() - p.At <= PRACTICE_STALE then
		return p
	end
	return nil
end

-- ---------------------------------------------------------------------
-- START
-- ---------------------------------------------------------------------
local function connectRemotes(): boolean
	local remotes = ctx.Remotes or {}
	local done = true
	local frameRemote = remotes.MarketFrame
	if not connected.MarketFrame then
		if frameRemote and frameRemote:IsA("RemoteEvent") then
			connected.MarketFrame = true
			frameRemote.OnClientEvent:Connect(function(payload)
				local ok, err = pcall(onFrame, payload)
				if not ok then
					logOnce("Frame", err)
				end
			end)
		else
			done = false
		end
	end
	local replayRemote = remotes.Replay
	if not connected.Replay then
		if replayRemote and replayRemote:IsA("RemoteEvent") then
			connected.Replay = true
			replayRemote.OnClientEvent:Connect(function(payload)
				local ok, err = pcall(onReplay, payload)
				if not ok then
					logOnce("Replay", err)
				end
			end)
		else
			done = false
		end
	end
	return done
end

function MarketClient.Init(context: any)
	ctx = context
	local config = ctx.Config or {}
	companies = if type(config.Companies) == "table" then config.Companies else {}
	marketCfg = if type(config.Market) == "table" then config.Market else {}
	-- Pakete, die Main.client als Rückfall feuert (vor unserer Verbindung), ebenfalls mitschreiben
	ctx.Hooks.On("Replay", function(tick, close, phase)
		if type(tick) == "number" and type(close) == "number" then
			notePractice(tick, close, if type(phase) == "number" then phase else 0)
		end
	end)
end

function MarketClient.Start()
	-- erst NACH dem Start aller Module verbinden (Main.client verbindet seine Remotes synchron danach) –
	-- so liegen alle Hook-Listener schon bereit, wenn der erste Frame kommt
	task.defer(function()
		if connectRemotes() then
			return
		end
		for _ = 1, REMOTE_RETRIES do
			task.wait(REMOTE_RETRY_GAP)
			local ok, remotes = pcall(ctx.Net.GetRemotes)
			if ok and type(remotes) == "table" then
				for name, remote in pairs(remotes) do
					ctx.Remotes[name] = remote
				end
			end
			if connectRemotes() then
				return
			end
		end
		warn("[MarketClient] MarketFrame/Replay fehlen – keine Kurse")
	end)
end

return MarketClient
