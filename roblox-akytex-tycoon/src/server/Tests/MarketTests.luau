-- =====================================================================
--  AKYTEX TYCOON – Selbsttests der Markt-Engine (Server/Tests/MarketTests)
--  Besitzer: WP3 (Markt-Engine). Vertrag: DESIGN.md §D WP3 "Tests"/"Abnahme", §C17; MARKET.md §19.
--  Läuft über SelfTestService (Studio, "[SelfTest] n/n PASS"). Jeder Test bekommt die Services-Tabelle.
--  Alle Tests bauen EIGENE, isolierte Wochen-Kontexte mit Test-Seeds (MarketService.TestContext) – der Live-Markt
--  wird nicht verändert. Lange Tests yielden zwischendurch (task.wait), damit der Server flüssig bleibt.
--  Abgedeckt: Noise-Vektoren §19.2 · Determinismus (zwei Instanzen, 10.000 Ticks, Random-Access == sequentiell,
--  Cursor == Random-Access) · Kerzen-Aggregation 1m aus 1s == Ring · Backfill/Stillstand-Ringe == live ·
--  Frame ≤ 900 B (43 = 439 B) · QuoteCodec-Rundreise/falsche Länge · Dividenden-Ex-Tick · Gerüchte-Bestätigung ·
--  News nie vor t_a · Wochenwechsel stetig · Berlin-Termine auf Tick genau · CancelAutoShow · Admin-Event (Rampe,
--  Abklingen, Pause) · Config/Lang · Live-Markt.
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Lang = require(Shared:WaitForChild("Lang"))
local QuoteCodec = require(Shared:WaitForChild("Market"):WaitForChild("QuoteCodec"))

local MarketFolder = script.Parent.Parent:WaitForChild("Market")
local Noise = require(MarketFolder:WaitForChild("Noise"))
local MarketClock = require(MarketFolder:WaitForChild("MarketClock"))
local CandleStore = require(MarketFolder:WaitForChild("CandleStore"))

local Tests = {}

type Plain = { [string]: any }

local TEST_SEED = 123456789
local TEST_WEEK = 41 -- Mo 2026-10-19 (Saison 1, Samstag = IPO 100)

local function eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(("%s erwartet %s, bekommen %s"):format(label or "Wert", tostring(expected), tostring(actual)), 2)
	end
end

local function market(services: any): any
	local svc = services and services.MarketService
	assert(svc and type(svc.TestContext) == "function", "MarketService fehlt")
	return svc
end

local function context(
	services: any,
	seed: number?,
	week: number?,
	bases: { [number]: number }?,
	cancelled: (boolean | number)?
): Plain
	return market(services).TestContext(seed or TEST_SEED, week or TEST_WEEK, bases, cancelled)
end

local function build(ctx: Plain, day: number)
	local guard = 0
	while ctx.Director:BuiltThrough() < day and guard < 200 do
		ctx.Director:EnsureBuilt(day, 16)
		guard += 1
		task.wait()
	end
end

-- ---------------------------------------------------------------------
Tests["Markt: Noise-Testvektoren MARKET §19.2"] = function()
	local vectors = {
		{ 123456, 1, 0, 0, 3076564673 },
		{ 123456, 1, 0, 1, 1222392628 },
		{ 123456, 1, 13, 7, 3917177298 },
		{ 987654321, 104, 5, 123456789, 4043101596 },
		{ 2147483647, 9, 9001, 86399, 2536699204 },
	}
	for _, v in ipairs(vectors) do
		eq(Noise.Hash4(v[1], v[2], v[3], v[4]), v[5], "hash4")
	end
	assert(math.abs(Noise.Uni(123456, 1, 0, 0) - 0.432637066114694) < 1e-12, "uni")
	eq(Noise.Mul32(0x9E3779B9, 0x846CA68B), Noise.Mul32(0x846CA68B, 0x9E3779B9), "mul32 kommutativ")
	eq(Noise.Mul32(4294967295, 4294967295), 1, "mul32((2^32 − 1)², mod 2^32) = 1")
end

Tests["Markt: Determinismus zwei Instanzen 10.000 Ticks, Random-Access == sequentiell"] = function(services)
	local a = context(services)
	local b = context(services)
	local start = MarketClock.WeekStart(TEST_WEEK) + 120 * MarketClock.DAY
	build(a, MarketClock.DayIndex(start + 10000) + 1)
	build(b, MarketClock.DayIndex(start + 10000) + 1)
	local ids = { 1, 3, 9, 13, 28, 31, 40, 41 }
	local mismatches = 0
	for t = start, start + 9999 do
		a.Engine:Step(t)
		b.Engine:Step(t)
		for _, i in ipairs(ids) do
			local _, _, m1 = a.Engine:Quote(i)
			local _, _, m2 = b.Engine:Quote(i)
			if m1 ~= m2 then
				mismatches += 1
			end
		end
		if (t - start) % 400 == 0 then
			task.wait()
		end
	end
	eq(mismatches, 0, "Abweichungen zwischen zwei Instanzen")
	-- Random-Access (dritte Instanz, rückwärts, gestreut) == sequentiell (Instanz a, letzter Stand + Stichproben)
	local c = context(services)
	build(c, MarketClock.DayIndex(start + 10000) + 1)
	for k = 0, 300 do
		local t = start + 9999 - k * 33
		for _, i in ipairs(ids) do
			if c.Engine:MidAt(i, t) ~= a.Engine:MidAt(i, t) then
				mismatches += 1
			end
		end
	end
	local _, _, live = a.Engine:Quote(9)
	eq(c.Engine:MidAt(9, start + 9999), live, "Random-Access == letzter Live-Kurs")
	eq(mismatches, 0, "Random-Access-Abweichungen")
	-- Cursor (Offline-Abgleich) == Random-Access, inklusive Seek-Sprünge
	local cursor = c.Engine:NewCursor(13, start + 500)
	for t = start + 500, start + 900 do
		local o, h, l, cl = cursor:Candle(t)
		local o2, h2, l2, c2 = a.Engine:CandleAt(13, t)
		if o ~= o2 or h ~= h2 or l ~= l2 or cl ~= c2 then
			mismatches += 1
		end
	end
	cursor:Seek(start + 5000)
	local o, h, l, cl = cursor:Candle(start + 5000)
	local o2, h2, l2, c2 = a.Engine:CandleAt(13, start + 5000)
	eq(mismatches, 0, "Cursor-Abweichungen")
	assert(o == o2 and h == h2 and l == l2 and cl == c2, "Cursor nach Seek")
end

Tests["Markt: Kerzen-Aggregation 1m aus 1s == Ring, Frame 439 B"] = function(services)
	local ctx = context(services)
	local start = MarketClock.WeekStart(TEST_WEEK) + 33 * MarketClock.DAY + 600 -- Minutengrenze
	build(ctx, MarketClock.DayIndex(start) + 1)
	local store = CandleStore.new(Config.Market)
	local i = 9
	for t = start, start + 239 do
		ctx.Engine:Step(t)
		local o, h, l, c, v = ctx.Engine:Candle(i)
		store:Push(i, t, o, h, l, c, v)
	end
	local _, _, _, s1 = QuoteCodec.DecodeCandles(store:Get(i, 1) :: buffer)
	local _, _, _, m1 = QuoteCodec.DecodeCandles(store:Get(i, 60) :: buffer)
	assert(s1 and m1, "Kerzen dekodierbar")
	local agg = QuoteCodec.Aggregate(s1 :: any, 60)
	local compared = 0
	for _, x in ipairs(agg) do
		for _, y in ipairs(m1 :: any) do
			if y.T == x.T and x.T >= (s1 :: any)[1].T and x.T + 59 <= (s1 :: any)[#(s1 :: any)].T then
				compared += 1
				eq(x.O, y.O, "Open")
				eq(x.C, y.C, "Close")
				assert(math.abs(x.H - y.H) <= x.H * 0.0001 + 1, "High (Auflösung 0,01 %)")
				assert(math.abs(x.L - y.L) <= x.L * 0.0001 + 1, "Low (Auflösung 0,01 %)")
				assert(math.abs(x.V - y.V) <= 60, "Umsatz (Rundung Ø je Sekunde)")
			end
		end
	end
	assert(compared >= 1, "mindestens eine volle Minute verglichen")
	local rows = {}
	for _, id in ipairs(ctx.Engine:Ids()) do
		local _, _, _, c, v, hiOff, loOff = ctx.Engine:Candle(id)
		if c then
			table.insert(rows, { Id = id, Flags = 0, Close = c, HiOff = hiOff, LoOff = loOff, Vol = v })
		end
	end
	eq(#rows, 43, "43 Instrumente im Frame")
	local frame = QuoteCodec.EncodeFrame(start, 0, 1, rows)
	eq(buffer.len(frame), 439, "Frame-Größe")
	local decoded = QuoteCodec.DecodeFrame(frame)
	assert(decoded and #decoded.Rows == 43, "Frame-Rundreise")
	local short = buffer.create(438)
	buffer.copy(short, 0, frame, 0, 438)
	eq(QuoteCodec.DecodeFrame(short), nil, "falsche Länge -> nil")
end

Tests["Markt: Backfill/Stillstand-Ringe == durchgehend live (1s, 5s, 1m)"] = function(services)
	local ctx = context(services)
	local i = 9
	local live = MarketClock.WeekStart(TEST_WEEK) + 6 * MarketClock.DAY + 37 -- nicht 5s-/minuten-ausgerichtet
	build(ctx, MarketClock.DayIndex(live) + 1)
	local function candleAt(id: number, t: number)
		local o, h, l, c, v = ctx.Engine:CandleAt(id, t)
		return o, h, l, c, v
	end
	local cursorFn = function(id: number, t0: number)
		return ctx.Engine:NewCursor(id, t0)
	end
	-- Referenz: 40 min durchgehend live geschoben
	local ref = CandleStore.new(Config.Market)
	local refCursor = ctx.Engine:NewCursor(i, live - 2400)
	for t = live - 2400, live + 10 do
		local o, h, l, c, v = refCursor:Full(t)
		ref:Push(i, t, o, h, l, c, v)
		if t % 600 == 0 then
			task.wait()
		end
	end
	local function same(a: any, b: any, tf: number, label: string)
		local _, _, _, ca = QuoteCodec.DecodeCandles(a:Get(i, tf) :: buffer)
		local _, _, _, cb = QuoteCodec.DecodeCandles(b:Get(i, tf) :: buffer)
		assert(ca and cb, label .. ": dekodierbar")
		local byT: { [number]: any } = {}
		for _, c in ipairs(ca :: any) do
			byT[c.T] = c
		end
		local compared = 0
		for _, c in ipairs(cb :: any) do
			local r = byT[c.T]
			if r and c.T >= live - 2400 + 60 then
				compared += 1
				assert(c.C > 0, ("%s tf=%d: Lücke bei %d"):format(label, tf, c.T - live))
				assert(
					r.O == c.O and r.H == c.H and r.L == c.L and r.C == c.C and r.V == c.V,
					("%s tf=%d: Kerze bei %d weicht ab"):format(label, tf, c.T - live)
				)
			end
		end
		assert(compared >= 30, ("%s tf=%d: zu wenig verglichen (%d)"):format(label, tf, compared))
	end
	-- Boot: laufende Buckets vorbelegen, Backfill einplanen, Live läuft parallel
	local boot = CandleStore.new(Config.Market)
	boot:SeedPartial(i, live, candleAt)
	boot:Plan(cursorFn, { i }, live)
	assert(boot:Missing(i, live - 120), "Backfill offen -> Historie gilt als unvollständig")
	boot:Prioritize(i)
	for t = live, live + 10 do
		ctx.Engine:Step(t)
		local o, h, l, c, v = ctx.Engine:Candle(i)
		boot:Push(i, t, o :: number, h :: number, l :: number, c :: number, v :: number)
		boot:Work(2)
	end
	local guard = 0
	while not boot:Work(4) and guard < 5000 do
		guard += 1
		if guard % 20 == 0 then
			task.wait()
		end
	end
	assert(not boot:Missing(i, live - 24 * 3600), "nach dem Backfill vollständig")
	for _, tf in ipairs({ 1, 5, 60 }) do
		same(ref, boot, tf, "Boot")
	end
	-- Stillstand: live bis live−400, Sprung auf live−23 (Rebuild + SeedPartial wie MarketService)
	local stall = CandleStore.new(Config.Market)
	stall:Plan(cursorFn, {}, live) -- nur Cursor-Quelle setzen (keine Aufträge)
	local stallCursor = ctx.Engine:NewCursor(i, live - 2400)
	for t = live - 2400, live - 400 do
		local o, h, l, c, v = stallCursor:Full(t)
		stall:Push(i, t, o, h, l, c, v)
	end
	local target = live - 23
	stall:Rebuild({ i }, live - 399, target - 1, target)
	stall:SeedPartial(i, target, candleAt)
	for t = target, live + 10 do
		local o, h, l, c, v = ctx.Engine:CandleAt(i, t)
		stall:Push(i, t, o, h, l, c, v)
		stall:Work(2)
	end
	guard = 0
	while not stall:Work(4) and guard < 5000 do
		guard += 1
		if guard % 20 == 0 then
			task.wait()
		end
	end
	for _, tf in ipairs({ 1, 5, 60 }) do
		same(ref, stall, tf, "Stillstand")
	end
end

Tests["Markt: Dividenden-Ex-Tick senkt den Kurs um den Betrag"] = function(services)
	local ctx = context(services)
	local ws = MarketClock.WeekStart(TEST_WEEK)
	build(ctx, MarketClock.DayIndex(ws) + 12)
	local divs = ctx.Director:Dividends(ws, ws + 12 * MarketClock.DAY)
	assert(#divs > 0, "Dividenden im Plan")
	for k = 1, math.min(#divs, 20) do
		local d = divs[k]
		local before = ctx.Engine:MidAt(d.I, d.Tick, d.Tick)
		local after = ctx.Engine:MidAt(d.I, d.Tick)
		assert(math.abs((before - after) - d.Cents) <= 1, ("Abschlag %d statt %d"):format(before - after, d.Cents))
		eq(MarketClock.Minute(d.Tick), Config.Market.Dividend.Minute, "Ex-Tick um :19")
	end
end

Tests["Markt: Gerücht wird nach 120 s bestätigt/dementiert, Kurs erst nach dem Lesefenster"] = function(services)
	local ctx = context(services)
	local ws = MarketClock.WeekStart(TEST_WEEK)
	build(ctx, MarketClock.DayIndex(ws) + 2)
	local news = ctx.Director:NewsIn(ws, ws + 2 * MarketClock.DAY)
	local rumor, fact = nil, nil
	for _, n in ipairs(news) do
		if n.Kind == "Rumor" and rumor == nil then
			rumor = n
		elseif n.Kind == "Fact" and n.Band and n.Band >= 2 and fact == nil then
			fact = n
		end
	end
	assert(rumor, "kein Gerücht gefunden")
	local resolved = nil
	for _, n in ipairs(ctx.Director:NewsIn(rumor.T, rumor.T + Config.Market.RumorResolve)) do
		if (n.Kind == "Confirm" or n.Kind == "Deny") and n.I == rumor.I then
			resolved = n
		end
	end
	assert(resolved, "keine Auflösung")
	eq(resolved.T - rumor.T, Config.Market.RumorResolve, "Auflösung nach 120 s")
	assert(fact, "keine Fakten-News")
	local o0 = ctx.Director:Offset(fact.I, fact.T)
	local oDelay = ctx.Director:Offset(fact.I, fact.T + Config.Market.Delay)
	local oAfter = ctx.Director:Offset(fact.I, fact.T + Config.Market.Delay + Config.Market.Tau)
	assert(math.abs(oDelay - o0) < 0.002, "vor Ablauf des Lesefensters keine Reaktion")
	assert((oAfter - o0) * fact.Dir > 0, "Reaktion in Richtung der Schlagzeile")
end

Tests["Markt: News kommen nie vor t_a (NewsIn je Tick)"] = function(services)
	local ctx = context(services)
	local ws = MarketClock.WeekStart(TEST_WEEK)
	build(ctx, MarketClock.DayIndex(ws) + 1)
	local count = 0
	for t = ws + 1, ws + MarketClock.DAY do
		for _, n in ipairs(ctx.Director:NewsIn(t - 1, t)) do
			eq(n.T, t, "News-Zeitpunkt")
			count += 1
		end
	end
	assert(count > 10, "zu wenige News an einem Börsentag: " .. count)
	for _, n in ipairs(ctx.Director:LatestNews(ws + 600, 50)) do
		assert(n.T <= ws + 600, "LatestNews enthält Zukunft")
	end
end

Tests["Markt: Wochenwechsel stetig (Basis = Wochenschluss)"] = function(services)
	local week = TEST_WEEK
	local a = context(services, TEST_SEED, week)
	local weekEnd = MarketClock.WeekEnd(week)
	build(a, MarketClock.DayIndex(weekEnd))
	local closes: { [number]: number } = {}
	for _, i in ipairs(a.Engine:Ids()) do
		if a.Engine:IsActive(i, weekEnd) then
			closes[i] = a.Engine:MidAt(i, weekEnd)
		end
	end
	local b = context(services, 987654321, week + 1, closes)
	build(b, MarketClock.DayIndex(weekEnd + 1))
	for _, i in ipairs({ 1, 9, 13, 28, 40 }) do
		local p0 = closes[i]
		local p1 = b.Engine:MidAt(i, weekEnd + 1)
		assert(p0 and p0 > 0, "Wochenschluss vorhanden")
		assert(math.abs(math.log(p1 / p0)) < 0.004, ("Sprung am Wochenwechsel bei %d: %d -> %d"):format(i, p0, p1))
	end
end

Tests["Markt: Berlin-Termine auf Tick genau (Sommer-/Winterzeit)"] = function(services)
	-- unabhängig mit Python zoneinfo("Europe/Berlin") berechnet
	eq(MarketClock.WeeklyTick(41, 5, 19, 0), 25203600, "Crash-Freitag 23.10.2026 19:00 MESZ")
	eq(MarketClock.WeeklyTick(42, 5, 19, 0), 25812000, "Crash-Freitag 30.10.2026 19:00 MEZ")
	eq(MarketClock.WeeklyTick(41, 3, 19, 0), 25030800, "Rally-Mittwoch 21.10.2026")
	eq(MarketClock.WeeklyTick(41, 6, 18, 15), 25287300, "Samstags-Show 24.10.2026 18:15")
	eq(MarketClock.WeeklyTick(41, 6, 17, 0), 25282800, "IPO 24.10.2026 17:00")
	-- der Plan setzt den Crash-Freitag genau dorthin (Warnung 3 min vorher)
	local ctx = context(services)
	build(ctx, MarketClock.DayIndex(25203600) + 1)
	local found = false
	for _, n in ipairs(ctx.Director:NewsIn(25203600 - 1, 25203600)) do
		if n.Kind == "Crash" and n.Key == "news.weekly.CrashFriday" then
			found = true
		end
	end
	assert(found, "Crash-Freitag-Schlagzeile genau um 19:00 Berlin")
	local warned = false
	for _, n in ipairs(ctx.Director:NewsIn(25203600 - 181, 25203600 - 180)) do
		if n.Kind == "Warn" then
			warned = true
		end
	end
	assert(warned, "Warnung 3 min vorher")
	local listing = ctx.Director:Listing(100)
	assert(listing and listing.T0 == 25282800, "IPO 100 notiert Samstag 17:00 Berlin")
end

Tests["Markt: CancelAutoShow sagt die Samstags-Rallye ab"] = function(services)
	local show = MarketClock.WeeklyTick(TEST_WEEK, 6, 18, 15) :: number
	local on = context(services, TEST_SEED, TEST_WEEK, nil, false)
	local off = context(services, TEST_SEED, TEST_WEEK, nil, true)
	build(on, MarketClock.DayIndex(show) + 1)
	build(off, MarketClock.DayIndex(show) + 1)
	local sector = Config.Companies.Sectors[(TEST_WEEK % 6) + 1].Key
	local target = 0
	for _, entry in ipairs(Config.Companies.Instruments) do
		if entry.Sector == sector and not entry.Ipo and entry.Class ~= "ETF" then
			target = entry.Id
			break
		end
	end
	assert(target > 0, "Firma im Sektor der Woche")
	local t = show + 30 + Config.Market.Delay + 120
	local up = on.Engine:MidAt(target, t)
	local base = off.Engine:MidAt(target, t)
	assert(up > base * 1.03, ("Show-Rallye wirkt (%d vs %d)"):format(up, base))
	eq(off.Engine:MidAt(target, show - 600), on.Engine:MidAt(target, show - 600), "vor der Show identisch")
	local showNews = false
	for _, n in ipairs(off.Director:NewsIn(show, show + 60)) do
		if n.Key == "news.weekly.AutoShow" then
			showNews = true
		end
	end
	assert(not showNews, "abgesagte Show schickt keine Schlagzeile")
	-- Absage mitten in der Warnphase: gilt erst ab ihrem Start-Tick (vorher wie geplant, danach wie abgesagt)
	local warnAt = show + 30 - Config.Market.CrashRally.WarnSeconds
	local cutAt = warnAt + 60
	local mid = context(services, TEST_SEED, TEST_WEEK, nil, cutAt)
	build(mid, MarketClock.DayIndex(show) + 1)
	eq(mid.Engine:MidAt(target, cutAt - 1), on.Engine:MidAt(target, cutAt - 1), "vor dem Absage-Tick wie geplant")
	eq(mid.Engine:MidAt(target, t), off.Engine:MidAt(target, t), "nach dem Ausblenden wie abgesagt")
	local worst = 0
	for k = cutAt - 5, cutAt + 70 do
		local a, b = mid.Engine:MidAt(target, k - 1), mid.Engine:MidAt(target, k)
		worst = math.max(worst, math.abs(math.log(b / a)))
	end
	assert(worst < 0.01, ("kein Kurssprung beim Ausblenden (größter 1s-Schritt %.4f)"):format(worst))
	local crash, rally = mid.Director:CrashRally(cutAt - 1)
	assert(rally and not crash, "Warnphase vor der Absage zeigt die Rallye")
	local _, rallyAfter = mid.Director:CrashRally(cutAt)
	assert(not rallyAfter, "nach der Absage keine Rallye-Flagge")
end

Tests["Markt: Admin-Crash (Rampe, Abklingen, 10-s-Pause, Admin-Fenster), Normalisieren"] = function(services)
	local ctx = context(services)
	local ws = MarketClock.WeekStart(TEST_WEEK)
	local x = ws + 90 * MarketClock.DAY + 300
	build(ctx, MarketClock.DayIndex(x) + 2)
	local before = ctx.Engine:MidAt(1, x - 1)
	local ids = ctx.Director:AddExternal({
		Id = "selftest1",
		Kind = "Crash",
		Scope = "All",
		Strength = 0.3,
		Ramp = 60,
		Decay = 600,
		StartTick = x,
		Until = x + 660,
		By = 0,
		Warn = 0,
	}, false)
	eq(#ids, 36, "alle 36 Firmen betroffen")
	local low = ctx.Engine:MidAt(1, x + 60)
	assert(low < before * 0.85, "Crash wirkt nach der Rampe")
	local back = ctx.Engine:MidAt(1, x + 700)
	assert(math.abs(math.log(back / before)) < 0.12, "klingt zum Modellkurs zurück")
	assert((ctx.Director:Halted(1, x + 5)), "10-s-Handelspause bei Aktivierung")
	assert(not (ctx.Director:Halted(1, x + 30)), "Pause vorbei")
	local windows = ctx.Director:Windows()
	assert(#windows == 1 and windows[1][2] >= x + 660 + 600, "Admin-Fenster bis +10 min nach Abklingen")
	-- Normalisieren blendet eine laufende Rallye über 60 s aus
	local y = x + 3000
	ctx.Director:AddExternal({
		Id = "selftest2",
		Kind = "Rally",
		Scope = "All",
		Strength = 0.4,
		Ramp = 60,
		Decay = 1800,
		StartTick = y,
		Until = y + 1860,
		By = 0,
		Warn = 0,
	}, false)
	local model = context(services)
	build(model, MarketClock.DayIndex(y) + 2)
	ctx.Director:AddExternal({
		Id = "selftest3",
		Kind = "Normalize",
		Scope = "All",
		Strength = 0,
		Ramp = 1,
		Decay = 1,
		StartTick = y + 100,
		Until = y + 160,
		By = 0,
	}, false)
	eq(ctx.Engine:MidAt(1, y + 200), model.Engine:MidAt(1, y + 200), "nach Normalisieren = Modellkurs")
end

Tests["Markt: Config & Lang vollständig"] = function()
	local errors = {}
	for _, name in ipairs({ "Market", "Companies", "News" }) do
		local child = (Config :: any)[name]
		for _, message in ipairs(child.Validate(Config)) do
			table.insert(errors, message)
		end
	end
	assert(#errors == 0, table.concat(errors, " | "))
	local missing = {}
	local function walk(value: any, depth: number)
		if depth > 5 then
			return
		end
		if type(value) == "string" and string.sub(value, 1, 5) == "news." then
			if not Lang.Has(value) then
				table.insert(missing, value)
			end
		elseif type(value) == "table" then
			for _, child in pairs(value) do
				walk(child, depth + 1)
			end
		end
	end
	walk(Config.News, 0)
	assert(#missing == 0, "Lang fehlt: " .. table.concat(missing, ", "))
	for _, key in ipairs({ "mkt.invalid", "mkt.unknownInst", "mkt.notReady", "mkt.admin.ok", "mkt.cal.Earnings" }) do
		assert(Lang.Has(key), "Lang fehlt: " .. key)
	end
end

Tests["Markt: Live-Markt läuft (Frame, Quote, Kalender, Request-Form)"] = function(services)
	local svc = market(services)
	local waited = 0
	while not svc.IsReady() and waited < 20 do
		task.wait(0.5)
		waited += 0.5
	end
	assert(svc.IsReady(), "Markt nach 20 s nicht bereit")
	local t0 = svc.Tick()
	task.wait(2.2)
	assert(svc.Tick() > t0, "Markt-Tick läuft")
	local bid, ask, mid = svc.Quote(1)
	assert(bid and ask and mid and bid < ask and bid <= mid and mid <= ask, "Quote plausibel")
	eq(svc.PriceAt(1, svc.Tick()), mid, "PriceAt(jetzt) == Quote-mid")
	assert(svc.PriceAt(1, svc.Tick() + 1000) == mid, "Zukunft wird auf jetzt begrenzt")
	local ids = svc.ActiveIds()
	assert(#ids >= 43, "mindestens 43 aktive Instrumente")
	assert(type(svc.Calendar(3)) == "table", "Kalender")
	assert(#svc.RecentNews(50) <= 50, "News-Liste endlich")
	local stats = svc.Stats()
	assert(type(stats.TickMs) == "number" and type(stats.BusOk) == "boolean", "Stats-Form")
	assert(svc.Instrument(250) and svc.Instrument(250).Set == "Tutorial", "ACAD bekannt")
	assert(not table.find(ids, 250), "ACAD nie im Frame")
	-- Service-Cursor hat die Form, die CandleStore (Backfill/Rebuild) und CatchUp brauchen: Full + LastMid + Candle
	local tc = svc.Tick() - 120
	local cursor = svc.NewCursor(1, tc)
	assert(type(cursor.Full) == "function" and type(cursor.LastMid) == "number", "NewCursor: Full + LastMid")
	local o, h, l, c, v = cursor:Full(tc)
	assert(type(v) == "number" and c > 0 and l <= math.min(o, c) and h >= math.max(o, c), "NewCursor:Full plausibel")
	eq(cursor.LastMid, c, "LastMid = Schluss des letzten Ticks")
	local ro, rh, rl, rc = svc.Candle1s(1, tc + 1)
	local co, ch, cl, cc = cursor:Candle(tc + 1)
	assert(ro == co and rh == ch and rl == cl and rc == cc, "Cursor-Kerze == Candle1s (Random-Access)")
end

Tests["Markt: OnTick(t) sieht Tick t (Kerze, Dividenden, Pause)"] = function(services)
	local svc = market(services)
	local waited = 0
	while not svc.IsReady() and waited < 20 do
		task.wait(0.5)
		waited += 0.5
	end
	assert(svc.IsReady(), "Markt nach 20 s nicht bereit")
	local result: Plain? = nil
	svc.OnTick(function(t: number)
		if result ~= nil then
			return -- Callback bleibt registriert; nur der erste Tick wird geprüft
		end
		local _, _, _, close = svc.Candle1s(1, t)
		local _, _, mid = svc.Quote(1)
		result = { Tick = svc.Tick(), T = t, Close = close, Mid = mid, Halted = svc.IsHalted(1, t) }
	end)
	local guard = 0
	while result == nil and guard < 40 do
		task.wait(0.1)
		guard += 1
	end
	local r = result :: Plain
	assert(r ~= nil, "OnTick feuert")
	eq(r.Tick, r.T, "Tick() == t im Callback")
	assert(r.Close ~= nil and r.Close == r.Mid, "Candle1s(i, t) im Callback = Kerze von t (Schluss == Quote-mid)")
	assert(type(r.Halted) == "boolean", "IsHalted(i, t)")
end

return Tests
