--!strict
-- =====================================================================
--  AKYTEX TYCOON – Kerzen-Ringe & Historie (Server/Market/CandleStore)
--  Besitzer: WP3 (Markt-Engine). Vertrag: MARKET.md §9.1–§9.3, §10.3; DESIGN.md §C16 (Backfill ≤ 2 ms/Frame).
--  Je Instrument drei buffer-Ringe (10 Byte je Kerze, QuoteCodec-Datensatz): 1s × 300 · 5s × 360 · 1m × 1440.
--  Die laufende 5s-/1m-Kerze steht immer schon im Ring (wird jede Sekunde überschrieben).
--  5m/15m/1T/1W werden aus dem 1m-Ring aggregiert (QuoteCodec.Aggregate). Antworten werden je
--  (Instrument, Zeitrahmen, letzte Kerze) EINMAL kodiert und für alle Spieler wiederverwendet.
--  Backfill beim Start: letzte 6 h exakt mit 1 Hz, 6–24 h aus 10-s-Stichproben (nur Anzeige, Orders nutzen sie nie);
--  Aufträge laufen über einen Frame-Takt mit Zeitbudget. Rebuild(…) rechnet Fenster nach verspäteten Events neu.
--
--  Öffentliche API (nur WP3)
--    CandleStore.new(config): Store
--    s:Push(i, t, o, h, l, c, v)                 1s-Kerze (live) in alle Ringe
--    s:Get(i, tf): buffer?                       Kerzen-Antwort (QuoteCodec 8 + 10·n), gecacht
--    s:Plan(cursorFn, ids, liveStart)            Backfill-Aufträge anlegen (cursorFn(i, t0) -> Cursor)
--    s:SeedPartial(i, liveStart, candleAt)       laufende 5s-/1m-Kerze exakt vorbelegen (vor dem ersten Push)
--    s:Rebuild(ids, from, to, liveStart?)        Fenster neu rechnen (vorne in die Warteschlange)
--    s:Work(budgetMs): boolean                   Aufträge abarbeiten; true = nichts mehr zu tun
--    s:Pending(): number · s:WeekHigh(i): number · s:Range(i): (lo, hi) · s:Clear()
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuoteCodec = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Market"):WaitForChild("QuoteCodec"))

local CandleStore = {}
CandleStore.__index = CandleStore

type Plain = { [string]: any }
type Partial = { B: number, O: number, H: number, L: number, C: number, V: number }
type Ring = { Buf: buffer, Cap: number, Tf: number, Head: number, P: Partial? }
type Rings = { S1: Ring, S5: Ring, M1: Ring, Cache: { [number]: { Key: number, Buf: buffer } }, WH: { number } }
type Task = {
	I: number,
	From: number,
	To: number, -- einschließlich
	Exact: boolean,
	T: number,
	Cursor: any,
	Agg5: Partial?,
	AggM: Partial?,
	Live: number,
}

local TF_S1, TF_S5, TF_M1 = 1, 5, 60
local MAX_TASKS = 4000

local function newRing(cap: number, tf: number): Ring
	return { Buf = buffer.create(cap * QuoteCodec.RECORD), Cap = cap, Tf = tf, Head = -1, P = nil }
end

function CandleStore.new(config: Plain)
	local self = setmetatable({}, CandleStore) :: any
	self.Cfg = config
	self.Rings = {} :: { [number]: Rings }
	self.Tasks = {} :: { Task }
	self.CursorFn = nil :: ((number, number) -> any)?
	self.History = config.History.Candles
	return self
end

function CandleStore.Ensure(self: any, i: number): Rings
	local r = self.Rings[i]
	if r == nil then
		local rings = self.Cfg.Rings
		r = {
			S1 = newRing(rings.S1, TF_S1),
			S5 = newRing(rings.S5, TF_S5),
			M1 = newRing(rings.M1, TF_M1),
			Cache = {},
			WH = { -1, 0 },
		}
		self.Rings[i] = r
	end
	return r :: Rings
end

function CandleStore.Clear(self: any)
	table.clear(self.Rings)
	table.clear(self.Tasks)
end

-- Datensatz eines Buckets schreiben (O = Schluss des Vorgängers, im Datensatz implizit)
local function writeBucket(ring: Ring, bucket: number, p: Partial)
	local hiOff = QuoteCodec.HiOff(p.O, p.C, p.H)
	local loOff = QuoteCodec.LoOff(p.O, p.C, p.L)
	QuoteCodec.WriteRecord(ring.Buf, bucket % ring.Cap, p.C, hiOff, loOff, p.V / ring.Tf)
end

local function zeroBuckets(ring: Ring, fromBucket: number, toBucket: number)
	if toBucket < fromBucket then
		return
	end
	local first = math.max(fromBucket, toBucket - ring.Cap + 1)
	for b = first, toBucket do
		QuoteCodec.WriteRecord(ring.Buf, b % ring.Cap, 0, 0, 0, 0)
	end
end

-- Live-Aggregation in einen Ring (laufender Bucket wird überschrieben)
local function feed(ring: Ring, t: number, o: number, h: number, l: number, c: number, v: number)
	local bucket = t // ring.Tf
	local p = ring.P
	if p and p.B == bucket then
		if h > p.H then
			p.H = h
		end
		if l < p.L then
			p.L = l
		end
		p.C = c
		p.V += v
	else
		if ring.Head >= 0 and bucket > ring.Head + 1 then
			zeroBuckets(ring, ring.Head + 1, bucket - 1)
		end
		p = { B = bucket, O = o, H = h, L = l, C = c, V = v }
		ring.P = p
	end
	writeBucket(ring, bucket, p :: Partial)
	if bucket > ring.Head then
		ring.Head = bucket
	end
end

function CandleStore.Push(self: any, i: number, t: number, o: number, h: number, l: number, c: number, v: number)
	local r = self:Ensure(i)
	feed(r.S1, t, o, h, l, c, v)
	feed(r.S5, t, o, h, l, c, v)
	feed(r.M1, t, o, h, l, c, v)
end

-- laufende 5s-/1m-Kerze vor dem ersten Live-Push exakt aus den Sekunden davor vorbelegen
function CandleStore.SeedPartial(
	self: any,
	i: number,
	liveStart: number,
	candleAt: (number, number) -> (number, number, number, number, number)
)
	local r = self:Ensure(i)
	if r.S1.Head >= 0 and liveStart - 1 > r.S1.Head then
		zeroBuckets(r.S1, r.S1.Head + 1, liveStart - 1) -- Stillstand: alte Ring-Inhalte nicht als neue Kerzen zeigen
	end
	for _, ring in ipairs({ r.S5, r.M1 }) do
		local liveBucket = liveStart // ring.Tf
		local bucketStart = liveBucket * ring.Tf
		if ring.Head >= 0 and liveBucket - 1 > ring.Head then
			zeroBuckets(ring, ring.Head + 1, liveBucket - 1)
		end
		ring.P = nil
		if bucketStart < liveStart then
			local p: Partial? = nil
			for t = bucketStart, liveStart - 1 do
				local o, h, l, c, v = candleAt(i, t)
				if p == nil then
					p = { B = liveBucket, O = o, H = h, L = l, C = c, V = v }
				else
					local q = p :: Partial
					q.H = math.max(q.H, h)
					q.L = math.min(q.L, l)
					q.C = c
					q.V += v
				end
			end
			ring.P = p
			if p then
				writeBucket(ring, p.B, p)
				ring.Head = math.max(ring.Head, p.B)
			end
		end
	end
	r.Cache = {}
end

-- ---------------------------------------------------------------------
-- ANTWORTEN (gecacht je Instrument/Zeitrahmen/letzter Kerze)
-- ---------------------------------------------------------------------
local function ringAnswer(self: any, i: number, ring: Ring): buffer?
	if ring.Head < 0 then
		return nil
	end
	local n = math.min(self.History, ring.Cap - 1) + 1
	local firstBucket = ring.Head - n + 1
	return QuoteCodec.EncodeCandles(i, ring.Tf, firstBucket * ring.Tf, ring.Buf, firstBucket % ring.Cap, n)
end

-- 1m-Ring als Kerzenliste (Lücken = nil-frei übersprungen), älteste zuerst
local function minuteCandles(ring: Ring, minutes: number): { QuoteCodec.Candle }
	local out: { QuoteCodec.Candle } = {}
	if ring.Head < 0 then
		return out
	end
	local n = math.min(minutes, ring.Cap - 1)
	local first = ring.Head - n + 1
	local prev = select(1, QuoteCodec.ReadRecord(ring.Buf, (first - 1) % ring.Cap))
	for b = first, ring.Head do
		local close, hiOff, loOff, vol = QuoteCodec.ReadRecord(ring.Buf, b % ring.Cap)
		if close > 0 and prev > 0 then
			table.insert(out, {
				T = b * ring.Tf,
				O = prev,
				H = QuoteCodec.HiFrom(prev, close, hiOff),
				L = QuoteCodec.LoFrom(prev, close, loOff),
				C = close,
				V = vol * ring.Tf,
			})
		end
		prev = close
	end
	return out
end

function CandleStore.Get(self: any, i: number, tf: number): buffer?
	local r = self.Rings[i]
	if r == nil then
		return nil
	end
	local ring: Ring = if tf == TF_S1 then r.S1 elseif tf == TF_S5 then r.S5 else r.M1
	local head = ring.Head
	local key = head
	local cached = r.Cache[tf]
	if cached and cached.Key == key and head >= 0 then
		return cached.Buf
	end
	local buf: buffer?
	if tf == TF_S1 or tf == TF_S5 or tf == TF_M1 then
		buf = ringAnswer(self, i, ring)
	else
		local per = math.max(1, tf // TF_M1)
		local minutes = math.min(r.M1.Cap - 1, per * (self.History + 1))
		local agg = QuoteCodec.Aggregate(minuteCandles(r.M1, minutes), tf)
		while #agg > self.History do
			table.remove(agg, 1)
		end
		if #agg == 0 then
			buf = nil
		else
			-- dicht machen: fehlende Buckets als Lücke (Close 0), damit Zeit = Start + k · tf stimmt
			local dense: { QuoteCodec.Candle } = {}
			local firstT = agg[1].T
			local index = 1
			local t = firstT
			local guard = 0
			while index <= #agg and guard < 2000 do -- gebunden
				guard += 1
				local c = agg[index]
				if c.T == t then
					table.insert(dense, c)
					index += 1
				else
					table.insert(dense, { T = t, O = 0, H = 0, L = 0, C = 0, V = 0 })
				end
				t += tf
			end
			buf = QuoteCodec.EncodeRecords(i, tf, firstT - tf, dense, agg[1].O)
		end
	end
	if buf then
		r.Cache[tf] = { Key = key, Buf = buf }
	end
	return buf
end

-- Hoch/Tief der letzten 1W-Kerze (140 × 1m) – Frame-Flag "Wochen-Hoch" und Firmenprofil
function CandleStore.Range(self: any, i: number): (number, number)
	local r = self.Rings[i]
	if r == nil then
		return 0, 0
	end
	local candles = minuteCandles(r.M1, self.Cfg.WeekHighCandles)
	local hi, lo = 0, math.huge
	for _, c in ipairs(candles) do
		if c.H > hi then
			hi = c.H
		end
		if c.L < lo then
			lo = c.L
		end
	end
	return hi, if lo == math.huge then 0 else lo
end

function CandleStore.WeekHigh(self: any, i: number): number
	local r = self.Rings[i]
	if r == nil then
		return 0
	end
	local minute = r.M1.Head
	if r.WH[1] ~= minute then
		local hi = self:Range(i)
		r.WH = { minute, hi }
	end
	return r.WH[2]
end

-- ---------------------------------------------------------------------
-- BACKFILL / REBUILD (Aufträge mit Zeitbudget)
-- ---------------------------------------------------------------------
function CandleStore.Pending(self: any): number
	return #self.Tasks
end

local function addTask(self: any, task: Task, front: boolean)
	if #self.Tasks >= MAX_TASKS then
		table.remove(self.Tasks)
	end
	if front then
		table.insert(self.Tasks, 1, task)
	else
		table.insert(self.Tasks, task)
	end
end

local function newTask(i: number, from: number, to: number, exact: boolean, live: number): Task
	return { I = i, From = from, To = to, Exact = exact, T = from, Cursor = nil, Agg5 = nil, AggM = nil, Live = live }
end

-- Aufteilung: zuerst die letzten 30 min exakt (Charts sofort brauchbar), dann bis 6 h exakt, dann 6–24 h Stichproben.
-- Der exakte Teil reicht bis liveStart − 1 (1s-Ring); die laufenden 5s-/1m-Buckets gehören SeedPartial/Live.
function CandleStore.Plan(self: any, cursorFn: (number, number) -> any, ids: { number }, liveStart: number)
	self.CursorFn = cursorFn
	local cfg = self.Cfg.Backfill
	local liveMinute = (liveStart // TF_M1) * TF_M1
	local exactFrom = liveMinute - math.floor(cfg.ExactHours * 3600 / TF_M1) * TF_M1
	local sampleFrom = liveMinute - math.floor(cfg.SampleHours * 3600 / TF_M1) * TF_M1
	local quick = math.max(exactFrom, liveMinute - 1800)
	for _, i in ipairs(ids) do
		self:Ensure(i)
		if liveStart - 1 >= quick then
			addTask(self, newTask(i, quick, liveStart - 1, true, liveStart), false)
		end
	end
	for _, i in ipairs(ids) do
		if quick - 1 >= exactFrom then
			addTask(self, newTask(i, exactFrom, quick - 1, true, liveStart), false)
		end
	end
	for _, i in ipairs(ids) do
		if exactFrom - 1 >= sampleFrom then
			addTask(self, newTask(i, sampleFrom, exactFrom - 1, false, liveStart), false)
		end
	end
end

-- Fenster neu rechnen (verspätetes Event, Stillstand): ganze Minuten, vorne in die Warteschlange
function CandleStore.Rebuild(self: any, ids: { number }, from: number, to: number, liveStart: number?)
	if self.CursorFn == nil then
		return
	end
	local live = liveStart or (to + 1)
	local liveMinute = (live // TF_M1) * TF_M1
	local ringStart = liveMinute - (self.Cfg.Rings.M1 - 1) * TF_M1
	local a = math.max((from // TF_M1) * TF_M1, ringStart)
	local b = math.min(to, live - 1) -- laufende 5s-/1m-Buckets überspringt stepTask (SeedPartial/Live)
	if b < a then
		return
	end
	local exactLimit = liveMinute - math.floor(self.Cfg.Backfill.ExactHours * 3600 / TF_M1) * TF_M1
	for _, i in ipairs(ids) do
		if self.Rings[i] then
			if a < exactLimit then
				addTask(self, newTask(i, a, math.min(b, exactLimit - 1), false, live), true)
			end
			if b >= math.max(a, exactLimit) then
				addTask(self, newTask(i, math.max(a, exactLimit), b, true, live), true)
			end
		end
	end
end

local function finishBucket(ring: Ring, p: Partial)
	writeBucket(ring, p.B, p)
	if p.B > ring.Head and ring.P == nil then
		ring.Head = p.B
	end
end

local function aggregate(agg: Partial?, bucket: number, o: number, h: number, l: number, c: number, v: number): Partial
	if agg and agg.B == bucket then
		if h > agg.H then
			agg.H = h
		end
		if l < agg.L then
			agg.L = l
		end
		agg.C = c
		agg.V += v
		return agg
	end
	return { B = bucket, O = o, H = h, L = l, C = c, V = v }
end

-- einen Auftrag um ein Stück weiterführen; true = fertig
local function stepTask(self: any, task: Task, deadline: number): boolean
	local r = self.Rings[task.I]
	if r == nil then
		return true
	end
	local cursorFn = self.CursorFn
	if cursorFn == nil then
		return true
	end
	if task.Cursor == nil then
		task.Cursor = cursorFn(task.I, task.T)
	end
	local cursor = task.Cursor
	-- Schreibgrenzen: nie über neuere Live-Kerzen (Ring läuft weiter, während der Auftrag über Frames verteilt läuft),
	-- nie in die laufenden 5s-/1m-Buckets (die gehören SeedPartial und dem Live-Takt)
	local s1From = math.max(task.Live, r.S1.Head + 1) - r.S1.Cap
	local s5From = math.max(task.Live // TF_S5, r.S5.Head + 1) - r.S5.Cap
	local mFrom = math.max(task.Live // TF_M1, r.M1.Head + 1) - r.M1.Cap
	local s5Live = task.Live // TF_S5
	local mLive = task.Live // TF_M1
	local count = 0
	if task.Exact then
		while task.T <= task.To do
			local t = task.T
			local o, h, l, c, v = cursor:Full(t)
			if t >= s1From then
				QuoteCodec.WriteRecord(
					r.S1.Buf,
					t % r.S1.Cap,
					c,
					QuoteCodec.HiOff(o, c, h),
					QuoteCodec.LoOff(o, c, l),
					v
				)
				if t > r.S1.Head and r.S1.P == nil then
					r.S1.Head = t
				end
			end
			local b5 = t // TF_S5
			if b5 >= s5From and b5 < s5Live then
				local prev5 = task.Agg5
				if prev5 and prev5.B ~= b5 then
					finishBucket(r.S5, prev5)
				end
				task.Agg5 = aggregate(task.Agg5, b5, o, h, l, c, v)
			end
			local bm = t // TF_M1
			if bm >= mFrom and bm < mLive then
				local prevM = task.AggM
				if prevM and prevM.B ~= bm then
					finishBucket(r.M1, prevM)
				end
				task.AggM = aggregate(task.AggM, bm, o, h, l, c, v)
			end
			task.T = t + 1
			count += 1
			if count % 32 == 0 and os.clock() >= deadline then
				break
			end
		end
		if task.T > task.To then
			if task.Agg5 then
				finishBucket(r.S5, task.Agg5 :: Partial)
			end
			if task.AggM then
				finishBucket(r.M1, task.AggM :: Partial)
			end
			r.Cache = {}
			return true
		end
		return false
	end
	-- Stichproben: je Minute alle SampleStep s eine 1s-Kerze; Eröffnung = exakter Schluss vor der Minute,
	-- Schluss = exakter Schluss der Minute (letzte Stichprobe liegt auf Sekunde 59)
	local step = math.max(1, self.Cfg.Backfill.SampleStep)
	while task.T <= task.To do
		local minuteStart = (task.T // TF_M1) * TF_M1
		cursor:Seek(minuteStart)
		local open = cursor.LastMid
		local minuteIndex = minuteStart // TF_M1
		local p: Partial = { B = minuteIndex, O = open, H = open, L = open, C = open, V = 0 }
		local s = minuteStart + step - 1
		while s <= minuteStart + TF_M1 - 1 do
			local _, h, l, c, v = cursor:Full(s)
			if h > p.H then
				p.H = h
			end
			if l < p.L then
				p.L = l
			end
			p.C = c
			p.V += v * step
			s += step
		end
		if minuteIndex >= math.max(mLive, r.M1.Head + 1) - r.M1.Cap and minuteIndex < mLive then
			finishBucket(r.M1, p)
		end
		task.T = minuteStart + TF_M1
		count += 1
		if count % 4 == 0 and os.clock() >= deadline then
			break
		end
	end
	if task.T > task.To then
		r.Cache = {}
		return true
	end
	return false
end

function CandleStore.Work(self: any, budgetMs: number): boolean
	local deadline = os.clock() + math.max(0.0002, budgetMs / 1000)
	local guard = 0
	while #self.Tasks > 0 and os.clock() < deadline and guard < 64 do -- gebunden
		guard += 1
		local task = self.Tasks[1]
		local ok, done = pcall(stepTask, self, task, deadline)
		if not ok or done then
			if not ok then
				warn("[CandleStore] Backfill-Fehler: " .. tostring(done))
			end
			table.remove(self.Tasks, 1)
		end
	end
	return #self.Tasks == 0
end

return CandleStore
