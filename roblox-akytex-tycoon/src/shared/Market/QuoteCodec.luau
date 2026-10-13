--!strict
-- =====================================================================
--  AKYTEX TYCOON – Binär-Kodierung für Kurse, Kerzen und Replay (Shared/Market/QuoteCodec)
--  Besitzer: WP3 (Markt-Engine). Vertrag: DESIGN.md §C6.2, §C8 (MarketFrame/Replay), MARKET.md §9.1, §9.2, §10.2.
--  Rein: lädt keine Roblox-Dienste und kein anderes Modul -> mit der Luau-CLI testbar (tests/quotecodec.test.luau).
--  Kodieren klemmt immer (NaN/±inf/zu groß -> Grenzwert), wirft nie einen Fehler. Dekodieren prüft die Länge
--  exakt (falsche Länge -> nil).
--
--  Formate
--    Frame (MarketFrame, 1 Hz, FireAllClients):  9 + 10·n Byte
--      Kopf  u8 Version | u32 Tick | u8 Flags | u8 Regime (R·100, geklemmt 0…255) | u8 n | u8 reserviert
--      Zeile u8 Id | u8 Flags | u32 Close (Cent) | u8 HiOff | u8 LoOff (0,01-%-Einheiten, geklemmt 255) | u16 Vol (10er-Lots)
--      Frame-Flags: Bit0 Halt irgendwo · Bit1 Admin-Event aktiv · Bit2 Crash · Bit3 Rallye
--      Zeilen-Flags: Bit0 Halt · Bit1 News aktiv · Bit2 Ex-Tag · Bit3 Wochen-Hoch (Hoch der letzten 1W-Kerze = 140 min)
--    Kerzen-Datensatz (Server-Ring, 10 Byte):  u32 Close | u16 HiOff | u16 LoOff | u16 Vol
--      Open = Close des Vorgänger-Datensatzes, Zeit implizit (Index). HiOff/LoOff = Abstand zu max/min(O, C) in 0,01 %
--      (Hoch aufgerundet, Tief abgerundet -> der dekodierte Docht umfasst den echten immer). Vol = Ø je Sekunde in
--      10er-Lots (überlauffest); DecodeCandles liefert Vol × tf zurück.
--    Kerzen-Antwort (MktCandles):  8 + 10·n Byte
--      Kopf  u8 Instrument | u16 tf (Ticks je Kerze) | u32 Tick des ERSTEN Datensatzes | u8 Version
--      Der erste Datensatz liefert nur den Eröffnungskurs (= Schluss der Vorkerze): n Datensätze -> n − 1 Kerzen.
--      Datensätze mit Close = 0 sind Lücken (Historie lädt noch) und werden beim Dekodieren übersprungen.
--    Replay (Tutorial-ACAD): 9 Byte  u32 Tick | u32 Close | u8 Phase
--
--  Öffentliche API (§C6.2 + Helfer)
--    QuoteCodec.EncodeFrame(tick, flags, regime, rows): buffer          QuoteCodec.DecodeFrame(b): Frame?
--    QuoteCodec.EncodeCandles(inst, tf, startTick, ring, from, n): buffer
--    QuoteCodec.DecodeCandles(b): (inst, tf, startTick, { Candle })    -- nil bei falscher Länge
--    QuoteCodec.EncodeReplay(tick, close, phase): buffer                QuoteCodec.DecodeReplay(b): (tick, close, phase)
--    QuoteCodec.TF: { [Timeframe]: Ticks }   1s=1 · 5s=5 · 1m=60 · 5m=300 · 15m=900 · 1T=1200 · 1W=8400
--    QuoteCodec.Aggregate(src, tfTicks): { Candle }                     MARKET §9.2 (Bucket = T // tf · tf)
--    Helfer: HiOff(o, c, h) · LoOff(o, c, l) · HiFrom(o, c, off) · LoFrom(o, c, off) · WriteRecord(ring, index, close,
--      hiOff, loOff, vol) · ReadRecord(ring, index) · EncodeRecords(inst, tf, startTick, candles, openRef) ·
--      Spread(mid, spreadBps, regime): (bid, ask) · FRAME_FLAGS · ROW_FLAGS · VERSION
-- =====================================================================

local QuoteCodec = {}

-- Typen identisch zu Shared/Types (hier lokal, damit das Modul ohne Roblox-require testbar bleibt)
export type QuoteRow = { Id: number, Flags: number, Close: number, HiOff: number, LoOff: number, Vol: number }
export type Frame = { Version: number, Tick: number, Flags: number, Regime: number, Rows: { QuoteRow } }
export type Candle = { T: number, O: number, H: number, L: number, C: number, V: number }

QuoteCodec.VERSION = 1
QuoteCodec.HEADER = 9 -- Frame-Kopf
QuoteCodec.ROW = 10 -- Frame-Zeile
QuoteCodec.CANDLE_HEADER = 8 -- Kopf einer Kerzen-Antwort
QuoteCodec.RECORD = 10 -- Kerzen-Datensatz
QuoteCodec.REPLAY = 9
QuoteCodec.MAX_ROWS = 255

QuoteCodec.FRAME_FLAGS = { Halt = 1, Admin = 2, Crash = 4, Rally = 8 }
QuoteCodec.ROW_FLAGS = { Halt = 1, News = 2, ExDay = 4, WeekHigh = 8 }

QuoteCodec.TF = {
	["1s"] = 1,
	["5s"] = 5,
	["1m"] = 60,
	["5m"] = 300,
	["15m"] = 900,
	["1T"] = 1200,
	["1W"] = 8400,
}

local U8 = 255
local U16 = 65535
local U32 = 4294967295
local HUGE = math.huge

-- ---------------------------------------------------------------------
-- 1) KLEMMEN (nie Fehler – auch nicht bei NaN, ±inf oder falschem Typ)
-- ---------------------------------------------------------------------
local function int(value: any, lo: number, hi: number): number
	if type(value) ~= "number" or value ~= value then
		return lo
	end
	if value >= HUGE then
		return hi
	end
	if value <= -HUGE then
		return lo
	end
	local r = math.round(value)
	if r < lo then
		return lo
	elseif r > hi then
		return hi
	end
	return r
end

local function num(value: any): number
	if type(value) ~= "number" or value ~= value or value == HUGE or value == -HUGE then
		return 0
	end
	return value
end

-- ---------------------------------------------------------------------
-- 2) DOCHT-ABSTÄNDE (0,01-%-Einheiten relativ zu max/min(O, C))
-- ---------------------------------------------------------------------
function QuoteCodec.HiOff(o: number, c: number, h: number): number
	local base = math.max(num(o), num(c))
	local high = num(h)
	if base <= 0 or high <= base then
		return 0
	end
	return int(math.ceil((high / base - 1) * 10000 - 1e-9), 0, U16)
end

function QuoteCodec.LoOff(o: number, c: number, l: number): number
	local base = math.min(num(o), num(c))
	local low = num(l)
	if base <= 0 or low >= base then
		return 0
	end
	return int(math.ceil((1 - low / base) * 10000 - 1e-9), 0, U16)
end

function QuoteCodec.HiFrom(o: number, c: number, off: number): number
	local base = math.max(num(o), num(c))
	return math.round(base * (1 + math.max(0, num(off)) / 10000))
end

function QuoteCodec.LoFrom(o: number, c: number, off: number): number
	local base = math.min(num(o), num(c))
	return math.max(0, math.round(base * (1 - math.clamp(num(off), 0, 10000) / 10000)))
end

-- Geld-/Brief-Kurs aus mid (Cent), Spread in Basispunkten und Regime (gleiche Formel wie der Server, MARKET §5.3)
function QuoteCodec.Spread(mid: number, spreadBps: number, regime: number): (number, number)
	local m = math.max(0, math.round(num(mid)))
	local spread = math.max(1, math.round(m * math.max(0, num(spreadBps)) * math.max(0, num(regime)) / 10000))
	local bid = m - spread // 2
	return bid, bid + spread
end

-- ---------------------------------------------------------------------
-- 3) FRAME (MARKET §10.2)
-- ---------------------------------------------------------------------
function QuoteCodec.EncodeFrame(tick: number, flags: number, regime: number, rows: { QuoteRow }): buffer
	local list: { QuoteRow } = if type(rows) == "table" then rows else {}
	local n = math.min(#list, QuoteCodec.MAX_ROWS)
	local b = buffer.create(QuoteCodec.HEADER + QuoteCodec.ROW * n)
	buffer.writeu8(b, 0, QuoteCodec.VERSION)
	buffer.writeu32(b, 1, int(tick, 0, U32))
	buffer.writeu8(b, 5, int(flags, 0, U8))
	buffer.writeu8(b, 6, int(num(regime) * 100, 0, U8))
	buffer.writeu8(b, 7, n)
	buffer.writeu8(b, 8, 0)
	local o = QuoteCodec.HEADER
	for index = 1, n do
		local r: any = list[index]
		if type(r) ~= "table" then
			r = {}
		end
		buffer.writeu8(b, o, int(r.Id, 0, U8))
		buffer.writeu8(b, o + 1, int(r.Flags, 0, U8))
		buffer.writeu32(b, o + 2, int(r.Close, 0, U32))
		buffer.writeu8(b, o + 6, int(r.HiOff, 0, U8))
		buffer.writeu8(b, o + 7, int(r.LoOff, 0, U8))
		buffer.writeu16(b, o + 8, int(r.Vol, 0, U16))
		o += QuoteCodec.ROW
	end
	return b
end

function QuoteCodec.DecodeFrame(b: buffer): Frame?
	if typeof(b) ~= "buffer" then
		return nil
	end
	local len = buffer.len(b)
	if len < QuoteCodec.HEADER then
		return nil
	end
	local n = buffer.readu8(b, 7)
	if len ~= QuoteCodec.HEADER + QuoteCodec.ROW * n then
		return nil
	end
	local rows: { QuoteRow } = table.create(n)
	local o = QuoteCodec.HEADER
	for index = 1, n do
		rows[index] = {
			Id = buffer.readu8(b, o),
			Flags = buffer.readu8(b, o + 1),
			Close = buffer.readu32(b, o + 2),
			HiOff = buffer.readu8(b, o + 6),
			LoOff = buffer.readu8(b, o + 7),
			Vol = buffer.readu16(b, o + 8),
		}
		o += QuoteCodec.ROW
	end
	return {
		Version = buffer.readu8(b, 0),
		Tick = buffer.readu32(b, 1),
		Flags = buffer.readu8(b, 5),
		Regime = buffer.readu8(b, 6) / 100,
		Rows = rows,
	}
end

-- ---------------------------------------------------------------------
-- 4) KERZEN-DATENSÄTZE (Ring) UND KERZEN-ANTWORT
-- ---------------------------------------------------------------------
function QuoteCodec.WriteRecord(ring: buffer, index: number, close: number, hiOff: number, loOff: number, vol: number)
	local o = index * QuoteCodec.RECORD
	if o < 0 or o + QuoteCodec.RECORD > buffer.len(ring) then
		return
	end
	buffer.writeu32(ring, o, int(close, 0, U32))
	buffer.writeu16(ring, o + 4, int(hiOff, 0, U16))
	buffer.writeu16(ring, o + 6, int(loOff, 0, U16))
	buffer.writeu16(ring, o + 8, int(vol, 0, U16))
end

function QuoteCodec.ReadRecord(ring: buffer, index: number): (number, number, number, number)
	local o = index * QuoteCodec.RECORD
	if o < 0 or o + QuoteCodec.RECORD > buffer.len(ring) then
		return 0, 0, 0, 0
	end
	return buffer.readu32(ring, o),
		buffer.readu16(ring, o + 4),
		buffer.readu16(ring, o + 6),
		buffer.readu16(ring, o + 8)
end

local function writeCandleHeader(b: buffer, inst: number, tf: number, startTick: number)
	buffer.writeu8(b, 0, int(inst, 0, U8))
	buffer.writeu16(b, 1, int(tf, 1, U16))
	buffer.writeu32(b, 3, int(startTick, 0, U32))
	buffer.writeu8(b, 7, QuoteCodec.VERSION)
end

-- Kopie aus einem Ring (Kapazität = buffer.len(ring) / 10): n Datensätze ab Index from (mit Umbruch), keine Neu-Kodierung
function QuoteCodec.EncodeCandles(
	inst: number,
	tf: number,
	startTick: number,
	ring: buffer,
	from: number,
	n: number
): buffer
	local cap = if typeof(ring) == "buffer" then buffer.len(ring) // QuoteCodec.RECORD else 0
	local count = if cap > 0 then int(n, 0, cap) else 0
	local b = buffer.create(QuoteCodec.CANDLE_HEADER + QuoteCodec.RECORD * count)
	writeCandleHeader(b, inst, tf, startTick)
	if count == 0 then
		return b
	end
	local first = int(from, -U32, U32) % cap
	local part = math.min(count, cap - first)
	buffer.copy(b, QuoteCodec.CANDLE_HEADER, ring, first * QuoteCodec.RECORD, part * QuoteCodec.RECORD)
	if part < count then
		buffer.copy(b, QuoteCodec.CANDLE_HEADER + part * QuoteCodec.RECORD, ring, 0, (count - part) * QuoteCodec.RECORD)
	end
	return b
end

-- Neu-Kodierung aggregierter Kerzen (5m … 1W): openRef = Schluss vor der ersten Kerze (Eröffnungsreferenz)
function QuoteCodec.EncodeRecords(
	inst: number,
	tf: number,
	startTick: number,
	candles: { Candle },
	openRef: number
): buffer
	local list: { Candle } = if type(candles) == "table" then candles else {}
	local n = #list
	local tfTicks = int(tf, 1, U16)
	local b = buffer.create(QuoteCodec.CANDLE_HEADER + QuoteCodec.RECORD * (n + 1))
	writeCandleHeader(b, inst, tfTicks, startTick)
	local function put(k: number, close: number, hiOff: number, loOff: number, vol: number)
		local o = QuoteCodec.CANDLE_HEADER + k * QuoteCodec.RECORD
		buffer.writeu32(b, o, int(close, 0, U32))
		buffer.writeu16(b, o + 4, int(hiOff, 0, U16))
		buffer.writeu16(b, o + 6, int(loOff, 0, U16))
		buffer.writeu16(b, o + 8, int(vol, 0, U16))
	end
	put(0, openRef, 0, 0, 0)
	for k = 1, n do
		local c: any = list[k]
		if type(c) ~= "table" then
			put(k, 0, 0, 0, 0)
		else
			put(k, c.C, QuoteCodec.HiOff(c.O, c.C, c.H), QuoteCodec.LoOff(c.O, c.C, c.L), num(c.V) / tfTicks)
		end
	end
	return b
end

function QuoteCodec.DecodeCandles(b: buffer): (number?, number?, number?, { Candle }?)
	if typeof(b) ~= "buffer" then
		return nil, nil, nil, nil
	end
	local len = buffer.len(b)
	if len < QuoteCodec.CANDLE_HEADER or (len - QuoteCodec.CANDLE_HEADER) % QuoteCodec.RECORD ~= 0 then
		return nil, nil, nil, nil
	end
	local n = (len - QuoteCodec.CANDLE_HEADER) // QuoteCodec.RECORD
	local inst = buffer.readu8(b, 0)
	local tf = math.max(1, buffer.readu16(b, 1))
	local startTick = buffer.readu32(b, 3)
	local candles: { Candle } = table.create(math.max(0, n - 1))
	local prevClose = if n > 0 then buffer.readu32(b, QuoteCodec.CANDLE_HEADER) else 0
	for k = 1, n - 1 do
		local o = QuoteCodec.CANDLE_HEADER + k * QuoteCodec.RECORD
		local close = buffer.readu32(b, o)
		if close > 0 and prevClose > 0 then
			local hiOff = buffer.readu16(b, o + 4)
			local loOff = buffer.readu16(b, o + 6)
			table.insert(candles, {
				T = startTick + k * tf,
				O = prevClose,
				H = QuoteCodec.HiFrom(prevClose, close, hiOff),
				L = QuoteCodec.LoFrom(prevClose, close, loOff),
				C = close,
				V = buffer.readu16(b, o + 8) * tf,
			})
		end
		prevClose = close
	end
	return inst, tf, startTick, candles
end

-- ---------------------------------------------------------------------
-- 5) REPLAY (Tutorial-Übungsaktie, ein Spieler)
-- ---------------------------------------------------------------------
function QuoteCodec.EncodeReplay(tick: number, close: number, phase: number): buffer
	local b = buffer.create(QuoteCodec.REPLAY)
	buffer.writeu32(b, 0, int(tick, 0, U32))
	buffer.writeu32(b, 4, int(close, 0, U32))
	buffer.writeu8(b, 8, int(phase, 0, U8))
	return b
end

function QuoteCodec.DecodeReplay(b: buffer): (number?, number?, number?)
	if typeof(b) ~= "buffer" or buffer.len(b) ~= QuoteCodec.REPLAY then
		return nil, nil, nil
	end
	return buffer.readu32(b, 0), buffer.readu32(b, 4), buffer.readu8(b, 8)
end

-- ---------------------------------------------------------------------
-- 6) AGGREGATION (identisch Server & Client, MARKET §9.2 / market.js aggregate())
-- ---------------------------------------------------------------------
function QuoteCodec.Aggregate(src: { Candle }, tfTicks: number): { Candle }
	local out: { Candle } = {}
	if type(src) ~= "table" then
		return out
	end
	local tf = int(tfTicks, 1, U32)
	local current: Candle? = nil
	for _, c in ipairs(src) do
		if type(c) ~= "table" then
			continue
		end
		local bucket = (num(c.T) // tf) * tf
		local cur = current
		if cur and cur.T == bucket then
			if c.H > cur.H then
				cur.H = c.H
			end
			if c.L < cur.L then
				cur.L = c.L
			end
			cur.C = c.C
			cur.V += num(c.V)
		else
			local fresh: Candle = { T = bucket, O = c.O, H = c.H, L = c.L, C = c.C, V = num(c.V) }
			table.insert(out, fresh)
			current = fresh
		end
	end
	return out
end

return QuoteCodec
