-- =====================================================================
--  AKYTEX TYCOON – Luau-CLI-Test für Shared/Market/QuoteCodec (ohne Roblox)
--  Besitzer: WP3 (Markt-Engine). DESIGN.md §D WP3 "Tests": Rundreisen (Frame, Kerzen, Replay), falsche Länge -> nil,
--  Klemmen statt Fehler (NaN, ±inf, zu groß, falscher Typ), Frame-Größe 9 + 10·n (43 = 439 B, 47 = 479 B, ≤ 900 B),
--  Ring-Kopie mit Umbruch, Aggregation MARKET §9.2.
--  Start (im Projektordner):  <scratchpad>/luau-build/luau tests/quotecodec.test.luau
-- =====================================================================

local QuoteCodec = require("../src/shared/Market/QuoteCodec")

local passed, failed = 0, 0
local failures: { string } = {}

local function check(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		table.insert(failures, name .. ": " .. tostring(err))
	end
end

local function eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(("%s erwartet %s, bekommen %s"):format(label or "Wert", tostring(expected), tostring(actual)), 2)
	end
end

local function rows(n: number): { QuoteCodec.QuoteRow }
	local list: { QuoteCodec.QuoteRow } = {}
	for i = 1, n do
		table.insert(list, {
			Id = i,
			Flags = i % 16,
			Close = 1000 + i * 37,
			HiOff = i % 200,
			LoOff = (i * 3) % 200,
			Vol = i * 100,
		})
	end
	return list
end

-- ---------------------------------------------------------------------
check("Frame: Rundreise exakt", function()
	local list = rows(43)
	local b = QuoteCodec.EncodeFrame(25203600, 5, 1.27, list)
	local frame = QuoteCodec.DecodeFrame(b)
	assert(frame, "DecodeFrame nil")
	eq(frame.Version, QuoteCodec.VERSION, "Version")
	eq(frame.Tick, 25203600, "Tick")
	eq(frame.Flags, 5, "Flags")
	eq(frame.Regime, 1.27, "Regime")
	eq(#frame.Rows, 43, "Zeilen")
	for i, r in ipairs(frame.Rows) do
		local src = list[i]
		eq(r.Id, src.Id, "Id")
		eq(r.Flags, src.Flags, "Flags")
		eq(r.Close, src.Close, "Close")
		eq(r.HiOff, src.HiOff, "HiOff")
		eq(r.LoOff, src.LoOff, "LoOff")
		eq(r.Vol, src.Vol, "Vol")
	end
end)

check("Frame-Größe 9 + 10·n (43 = 439 B, 47 = 479 B, ≤ 900 B)", function()
	eq(buffer.len(QuoteCodec.EncodeFrame(1, 0, 1, rows(43))), 439, "43 Instrumente")
	eq(buffer.len(QuoteCodec.EncodeFrame(1, 0, 1, rows(47))), 479, "47 Instrumente")
	eq(buffer.len(QuoteCodec.EncodeFrame(1, 0, 1, {})), 9, "leer")
	assert(buffer.len(QuoteCodec.EncodeFrame(1, 0, 1, rows(83))) <= 900, "83 Instrumente ≤ 900 B")
end)

check("Frame: falsche Länge -> nil", function()
	local b = QuoteCodec.EncodeFrame(7, 0, 1, rows(3))
	local short = buffer.create(buffer.len(b) - 1)
	buffer.copy(short, 0, b, 0, buffer.len(b) - 1)
	eq(QuoteCodec.DecodeFrame(short), nil, "zu kurz")
	local long = buffer.create(buffer.len(b) + 1)
	buffer.copy(long, 0, b, 0, buffer.len(b))
	eq(QuoteCodec.DecodeFrame(long), nil, "zu lang")
	eq(QuoteCodec.DecodeFrame(buffer.create(5)), nil, "unter Kopfgröße")
	eq(QuoteCodec.DecodeFrame("kein buffer" :: any), nil, "falscher Typ")
end)

check("Frame: klemmt statt Fehler (NaN, ±inf, negativ, zu groß, falscher Typ)", function()
	local nan = 0 / 0
	local bad: { any } = {
		{ Id = 300, Flags = -5, Close = math.huge, HiOff = nan, LoOff = 999, Vol = 1e9 },
		{ Id = nan, Flags = "x", Close = -10, HiOff = -1, LoOff = -math.huge, Vol = nan },
		"keine Tabelle",
	}
	local b = QuoteCodec.EncodeFrame(nan, math.huge, -3, bad :: any)
	local frame = QuoteCodec.DecodeFrame(b)
	assert(frame, "Frame trotz Müll dekodierbar")
	eq(frame.Tick, 0, "Tick NaN -> 0")
	eq(frame.Flags, 255, "Flags inf -> 255")
	eq(frame.Regime, 0, "Regime negativ -> 0")
	local r1, r2 = frame.Rows[1], frame.Rows[2]
	eq(r1.Id, 255, "Id geklemmt")
	eq(r1.Flags, 0, "Flags geklemmt")
	eq(r1.Close, 4294967295, "Close inf -> u32 max")
	eq(r1.HiOff, 0, "HiOff NaN -> 0")
	eq(r1.LoOff, 255, "LoOff geklemmt")
	eq(r1.Vol, 65535, "Vol geklemmt")
	eq(r2.Id, 0, "Id NaN -> 0")
	eq(r2.Close, 0, "Close negativ -> 0")
	eq(#frame.Rows, 3, "drei Zeilen (falscher Typ = Nullzeile)")
	-- Regime-Rundung
	local f2 = QuoteCodec.DecodeFrame(QuoteCodec.EncodeFrame(1, 0, 9.99, {}))
	assert(f2 and f2.Regime == 2.55, "Regime über 2,55 geklemmt")
end)

check("Docht-Abstände: dekodierter Docht umfasst den echten", function()
	for k = 1, 500 do
		local o = 5000 + (k * 37) % 4000
		local c = o + ((k * 13) % 41) - 20
		local h = math.max(o, c) + (k % 17)
		local l = math.min(o, c) - (k % 23)
		local hi = QuoteCodec.HiOff(o, c, h)
		local lo = QuoteCodec.LoOff(o, c, l)
		local hDec = QuoteCodec.HiFrom(o, c, hi)
		local lDec = QuoteCodec.LoFrom(o, c, lo)
		assert(hDec >= h, ("Hoch %d < %d"):format(hDec, h))
		assert(lDec <= l, ("Tief %d > %d"):format(lDec, l))
		assert(hDec - h <= math.max(o, c) * 0.0001 + 1, "Hoch-Abweichung zu groß")
		assert(l - lDec <= math.min(o, c) * 0.0001 + 1, "Tief-Abweichung zu groß")
	end
	eq(QuoteCodec.HiOff(100, 100, 50), 0, "Hoch unter Körper -> 0")
	eq(QuoteCodec.LoOff(0, 0, 0), 0, "Basis 0 -> 0")
end)

check("Kerzen: Ring-Kopie mit Umbruch + Rundreise", function()
	local cap = 10
	local ring = buffer.create(cap * QuoteCodec.RECORD)
	-- Kerzen Index 0…14 (Umbruch), Close steigt, Docht/Umsatz bekannt
	for index = 0, 14 do
		QuoteCodec.WriteRecord(ring, index % cap, 10000 + index * 10, 5, 7, 3)
	end
	-- letzte 6 Datensätze (Index 9…14) ab Bucket 9, tf = 60
	local b = QuoteCodec.EncodeCandles(12, 60, 9 * 60, ring, 9 % cap, 6)
	eq(buffer.len(b), 8 + 10 * 6, "Länge 8 + 10·n")
	local inst, tf, start, candles = QuoteCodec.DecodeCandles(b)
	eq(inst, 12, "Instrument")
	eq(tf, 60, "tf")
	eq(start, 540, "Start")
	assert(candles, "Kerzen nil")
	eq(#candles, 5, "n − 1 Kerzen (erste = Eröffnungsreferenz)")
	for k, c in ipairs(candles) do
		eq(c.T, 540 + k * 60, "Zeit")
		eq(c.O, 10000 + (8 + k) * 10, "Open = Close davor")
		eq(c.C, 10000 + (9 + k) * 10, "Close")
		eq(c.V, 3 * 60, "Umsatz = Ø je Sekunde × tf")
		assert(c.H >= math.max(c.O, c.C) and c.L <= math.min(c.O, c.C), "Docht umfasst Körper")
	end
end)

check("Kerzen: Lücken (Close 0) werden übersprungen, falsche Länge -> nil", function()
	local ring = buffer.create(5 * QuoteCodec.RECORD)
	QuoteCodec.WriteRecord(ring, 0, 100, 0, 0, 1)
	QuoteCodec.WriteRecord(ring, 1, 0, 0, 0, 0)
	QuoteCodec.WriteRecord(ring, 2, 105, 0, 0, 1)
	QuoteCodec.WriteRecord(ring, 3, 110, 0, 0, 1)
	local _, _, _, candles = QuoteCodec.DecodeCandles(QuoteCodec.EncodeCandles(1, 1, 0, ring, 0, 4))
	assert(candles, "nil")
	eq(#candles, 1, "nur Kerze 3 hat Vorgänger und Wert")
	eq(candles[1].O, 105, "Open nach Lücke")
	local odd = buffer.create(8 + 15)
	eq(select(1, QuoteCodec.DecodeCandles(odd)), nil, "falsche Länge")
	eq(select(1, QuoteCodec.DecodeCandles(buffer.create(3))), nil, "unter Kopfgröße")
	-- Klemmen beim Kodieren
	local clamped = QuoteCodec.EncodeCandles(999, 0 / 0, -5, ring, 0 / 0, 1e9)
	eq(buffer.len(clamped), 8 + 10 * 5, "n auf Kapazität geklemmt")
end)

check("EncodeRecords (aggregierte Zeitrahmen) Rundreise", function()
	local candles: { QuoteCodec.Candle } = {
		{ T = 1200, O = 1000, H = 1050, L = 990, C = 1040, V = 6000 },
		{ T = 2400, O = 1040, H = 1041, L = 900, C = 905, V = 12000 },
	}
	local b = QuoteCodec.EncodeRecords(5, 1200, 0, candles, 1000)
	local inst, tf, start, out = QuoteCodec.DecodeCandles(b)
	eq(inst, 5, "inst")
	eq(tf, 1200, "tf")
	eq(start, 0, "start")
	assert(out and #out == 2, "2 Kerzen")
	eq(out[1].T, 1200, "T1")
	eq(out[2].T, 2400, "T2")
	eq(out[1].O, 1000, "O1")
	eq(out[2].C, 905, "C2")
	assert(out[1].H >= 1050 and out[1].H <= 1051, "H1")
	assert(out[2].L <= 900 and out[2].L >= 899, "L2")
	eq(out[1].V, 6000, "V1")
end)

check("Replay: 9 Byte Rundreise, falsche Länge -> nil", function()
	local b = QuoteCodec.EncodeReplay(123456, 11500, 2)
	eq(buffer.len(b), 9, "9 Byte")
	local t, c, p = QuoteCodec.DecodeReplay(b)
	eq(t, 123456, "Tick")
	eq(c, 11500, "Close")
	eq(p, 2, "Phase")
	eq(select(1, QuoteCodec.DecodeReplay(buffer.create(8))), nil, "falsche Länge")
	local t2, c2, p2 = QuoteCodec.DecodeReplay(QuoteCodec.EncodeReplay(-1, 0 / 0, 999))
	eq(t2, 0, "Tick geklemmt")
	eq(c2, 0, "Close NaN")
	eq(p2, 255, "Phase geklemmt")
end)

check("TF-Tabelle", function()
	eq(QuoteCodec.TF["1s"], 1)
	eq(QuoteCodec.TF["5s"], 5)
	eq(QuoteCodec.TF["1m"], 60)
	eq(QuoteCodec.TF["5m"], 300)
	eq(QuoteCodec.TF["15m"], 900)
	eq(QuoteCodec.TF["1T"], 1200)
	eq(QuoteCodec.TF["1W"], 8400)
end)

check("Aggregate (MARKET §9.2): O erste, H max, L min, C letzte, V Summe", function()
	local src: { QuoteCodec.Candle } = {}
	for t = 0, 179 do
		table.insert(src, { T = t, O = 100 + t, H = 102 + t, L = 99 + t, C = 101 + t, V = 2 })
	end
	local m1 = QuoteCodec.Aggregate(src, 60)
	eq(#m1, 3, "3 Minuten")
	eq(m1[1].T, 0, "T")
	eq(m1[2].T, 60, "T2")
	eq(m1[1].O, 100, "O")
	eq(m1[1].H, 161, "H")
	eq(m1[1].L, 99, "L")
	eq(m1[1].C, 160, "C")
	eq(m1[1].V, 120, "V")
	eq(#QuoteCodec.Aggregate({}, 60), 0, "leer")
	-- Quelle bleibt unverändert
	eq(src[1].H, 102, "Quelle unverändert")
end)

check("Spread: Geld < Brief, gleiche Formel wie Server", function()
	local bid, ask = QuoteCodec.Spread(10000, 8, 1)
	eq(ask - bid, 8, "8 bps von 100,00")
	eq(bid, 9996, "bid")
	local b2, a2 = QuoteCodec.Spread(60, 4, 0.5)
	eq(a2 - b2, 1, "Mindest-Spread 1 Cent")
end)

-- ---------------------------------------------------------------------
for _, failure in ipairs(failures) do
	print("FAIL " .. failure)
end
print(("quotecodec.test: %d/%d PASS"):format(passed, passed + failed))
if failed > 0 then
	error(("%d Test(s) fehlgeschlagen"):format(failed))
end
