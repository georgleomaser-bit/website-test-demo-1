--!strict
--!native
-- =====================================================================
--  AKYTEX TYCOON – Kurs, Quote und 1s-Kerze (Server/Market/PriceEngine)
--  Besitzer: WP3 (Markt-Engine). Vertrag: MARKET.md §5.1, §5.3, §5.4, §19.1; DESIGN.md §B6.1, §B6.3 (IPO-Klasse).
--  Eine Instanz je Woche (Wochen-Seed). Alle Geldwerte in ganzzahligen Cent.
--
--  ln P_i(t) = ln B_i + d_i·(t − t0) + E_i(t) + σ_i·( R(t)·(β·M + γ·S + ε·I − N0_i) + μ·W_i(t) )
--  ETF:  P(t) = B_ETF · exp( Mittel_k( ln P_k(t) − ln P_k(t0) ) )   (kein eigenes Rauschen)
--  1s-Kerze: O = Schluss der Vorsekunde, C = mid(t), H/L deterministisch aus dem Hash. H/L sind KANONISCH:
--  schon auf die Frame-Auflösung (0,01-%-Schritte, max. 255) gerundet – Order-Trigger (WP4), Frame und 1s-Ring
--  sehen damit exakt dieselbe Kerze ("was der Chart zeigt, hat die Order gesehen").
--  Live-Felder und Random-Access-Felder sind getrennt; ein Cursor hat eigene Felder (Offline-Abgleich).
--
--  Öffentliche API (nur WP3)
--    PriceEngine.new({ Seed, Week, Config, Specs = { Spec }, Env = { Offset(i, t, divFrom?), VolMul(t) } }): Engine
--    e:Step(t)                          alle Instrumente auf Tick t (Aktien zuerst, ETFs zuletzt)
--    e:Quote(i): (bid?, ask?, mid?)     e:Candle(i): (O, H, L, C, V, hiOff, loOff)?   e:HalfSpread(i): number
--    e:Regime(): number                 e:LiveTick(): number             e:NewsActive(i): boolean
--    e:MidAt(i, t, divFrom?): number    e:CandleAt(i, t): (O, H, L, C, V, hiOff, loOff)   e:RegimeAt(t): number
--    e:NewCursor(i, t0): Cursor         Cursor:Candle(t) -> (O, H, L, C) · Cursor:Seek(t)
--    e:AddInstrument(spec) · e:Has(i) · e:IsActive(i, t) · e:Ids(): { number }
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Noise = require(script.Parent:WaitForChild("Noise"))
local QuoteCodec = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Market"):WaitForChild("QuoteCodec"))

local PriceEngine = {}
PriceEngine.__index = PriceEngine

local FieldAt = Noise.FieldAt
local White = Noise.White

export type Spec = {
	Id: number,
	Etf: boolean,
	Base: number, -- Cent (Wochenbasis bzw. Eröffnungskurs)
	Origin: number, -- erster Tick des Instruments in dieser Woche
	Sigma: number,
	Sigma1s: number,
	SpreadBps: number,
	VolBase: number,
	Drift: number, -- je Tick
	SectorIdx: number,
	Members: { number }?,
	WildUntil: number?, -- IPO: bis hierhin Klasse Wild, danach Übergang über Blend Sekunden
	WildSigma: number?,
	WildSigma1s: number?,
	WildSpread: number?,
	Blend: number?,
}

type Field = Noise.Field
type Plain = { [string]: any }

type FieldSet = {
	M: Field,
	S: { Field },
	V: Field,
	I: { [number]: Field },
	MemoT: number,
	MemoM: number,
	MemoS: { number },
	MemoR: number,
}

type Inst = {
	Spec: Spec,
	LnBase: number,
	N0: number?,
	L0: { number }?, -- ETF: ln P der Mitglieder zum Wochenstart
	-- Live-Zustand (letzter Step)
	T: number,
	Mid: number,
	Log: number,
	O: number,
	H: number,
	L: number,
	C: number,
	V: number,
	HiOff: number,
	LoOff: number,
	Bid: number,
	Ask: number,
	News: boolean,
}

export type Env = {
	Offset: (i: number, t: number, divFrom: number?) -> (number, boolean),
	VolMul: (t: number) -> number,
}

local function newFieldSet(seed: number, octLo: number, octHi: number): FieldSet
	local s: { Field } = {}
	for index = 1, 6 do
		s[index] = Noise.NewField(seed, 10 + index)
	end
	return {
		M = Noise.NewField(seed, 1),
		S = s,
		V = Noise.NewField(seed, 2, octLo, octHi),
		I = {},
		MemoT = -math.huge,
		MemoM = 0,
		MemoS = table.create(6, 0),
		MemoR = 1,
	}
end

function PriceEngine.new(params: Plain)
	local cfg = params.Config
	local self = setmetatable({}, PriceEngine) :: any
	self.Seed = math.floor(params.Seed) % 2147483648
	self.Week = params.Week
	self.Cfg = cfg
	self.Env = params.Env :: Env
	local noise = cfg.Noise
	self.Beta = noise.Beta
	self.Gamma = noise.Gamma
	self.Eps = noise.Eps
	self.Micro = noise.Micro
	self.RegK = noise.RegimeK
	self.RegLo = noise.RegimeRange[1]
	self.RegHi = noise.RegimeRange[2]
	self.MinCents = cfg.Price.MinCents
	self.MaxCents = cfg.Price.MaxCents
	self.EdgeTicks = cfg.Activity.EdgeMinutes * 60
	self.EdgeMult = cfg.Activity.EdgeMult
	self.DayTicks = cfg.DayTicks
	local oct = noise.RegimeOctaves
	self.OctLo, self.OctHi = oct[1], oct[2]
	self.Live = newFieldSet(self.Seed, oct[1], oct[2])
	self.RA = newFieldSet(self.Seed, oct[1], oct[2])
	self.Insts = {} :: { [number]: Inst }
	self.Stocks = {} :: { number }
	self.Etfs = {} :: { number }
	self.LiveT = -math.huge
	self.LiveR = 1
	for _, spec in ipairs(params.Specs :: { Spec }) do
		self:AddInstrument(spec)
	end
	return self
end

function PriceEngine.AddInstrument(self: any, spec: Spec)
	local i = spec.Id
	local fresh = self.Insts[i] == nil
	self.Insts[i] = {
		Spec = spec,
		LnBase = math.log(math.max(1, spec.Base) / 100),
		N0 = nil,
		L0 = nil,
		T = -math.huge,
		Mid = 0,
		Log = 0,
		O = 0,
		H = 0,
		L = 0,
		C = 0,
		V = 0,
		HiOff = 0,
		LoOff = 0,
		Bid = 0,
		Ask = 0,
		News = false,
	}
	if fresh then
		if spec.Etf then
			table.insert(self.Etfs, i)
		else
			table.insert(self.Stocks, i)
			table.sort(self.Stocks)
		end
	end
end

function PriceEngine.Has(self: any, i: number): boolean
	return self.Insts[i] ~= nil
end

function PriceEngine.IsActive(self: any, i: number, t: number): boolean
	local inst = self.Insts[i]
	return inst ~= nil and t >= inst.Spec.Origin
end

function PriceEngine.Ids(self: any): { number }
	local out: { number } = {}
	for _, i in ipairs(self.Stocks) do
		table.insert(out, i)
	end
	for _, i in ipairs(self.Etfs) do
		table.insert(out, i)
	end
	return out
end

function PriceEngine.LiveTick(self: any): number
	return self.LiveT
end

-- ---------------------------------------------------------------------
-- FELDER & REGIME (gemeinsame Felder je Tick einmal; Memo je Feldsatz)
-- ---------------------------------------------------------------------
local function shared(self: any, fs: FieldSet, t: number)
	if fs.MemoT ~= t then
		fs.MemoT = t
		fs.MemoM = FieldAt(fs.M, t)
		for index = 1, 6 do
			fs.MemoS[index] = FieldAt(fs.S[index], t)
		end
		local r = math.exp(self.RegK * FieldAt(fs.V, t)) * self.Env.VolMul(t)
		fs.MemoR = math.clamp(r, self.RegLo, self.RegHi)
	end
end

local function firmField(self: any, fs: FieldSet, i: number): Field
	local f = fs.I[i]
	if f == nil then
		f = Noise.NewField(self.Seed, 100 + i)
		fs.I[i] = f
	end
	return f
end

-- Klasse am Tick t (IPO: Wild am ersten Börsentag, danach linearer Übergang -> kein Kurssprung)
local function classAt(spec: Spec, t: number): (number, number, number)
	local wildUntil = spec.WildUntil
	if wildUntil == nil then
		return spec.Sigma, spec.Sigma1s, spec.SpreadBps
	end
	local blend = spec.Blend or 300
	local w = if t < wildUntil then 1 else math.clamp(1 - (t - wildUntil) / blend, 0, 1)
	if w <= 0 then
		return spec.Sigma, spec.Sigma1s, spec.SpreadBps
	end
	local ws = spec.WildSigma or spec.Sigma
	local ws1 = spec.WildSigma1s or spec.Sigma1s
	local wsp = spec.WildSpread or spec.SpreadBps
	return spec.Sigma + (ws - spec.Sigma) * w,
		spec.Sigma1s + (ws1 - spec.Sigma1s) * w,
		spec.SpreadBps + (wsp - spec.SpreadBps) * w
end

local function noiseLevel(self: any, fs: FieldSet, i: number, sector: number, t: number): number
	return self.Beta * fs.MemoM + self.Gamma * fs.MemoS[sector] + self.Eps * FieldAt(firmField(self, fs, i), t)
end

-- N0 = Rauschwert beim Ursprung (eigener Feldsatz, damit Live/RA-Caches unberührt bleiben)
local function n0Of(self: any, inst: Inst): number
	local n0 = inst.N0
	if n0 ~= nil then
		return n0
	end
	local spec = inst.Spec
	local t = spec.Origin
	local fs = newFieldSet(self.Seed, self.OctLo, self.OctHi)
	fs.MemoT = t
	fs.MemoM = FieldAt(fs.M, t)
	for index = 1, 6 do
		fs.MemoS[index] = FieldAt(fs.S[index], t)
	end
	local value = noiseLevel(self, fs, spec.Id, spec.SectorIdx, t)
	inst.N0 = value
	return value
end

-- Log-Mid einer Aktie (unrundet) + News-aktiv-Flag
local function stockLog(self: any, fs: FieldSet, inst: Inst, t: number, divFrom: number?): (number, boolean)
	local spec = inst.Spec
	shared(self, fs, t)
	local sigma = classAt(spec, t)
	local level = noiseLevel(self, fs, spec.Id, spec.SectorIdx, t) - n0Of(self, inst)
	local offset, news = self.Env.Offset(spec.Id, t, divFrom)
	local micro = self.Micro * White(self.Seed, 200 + spec.Id, t)
	return inst.LnBase + spec.Drift * (t - spec.Origin) + offset + sigma * (fs.MemoR * level + micro), news
end

local function etfL0(self: any, inst: Inst): { number }
	local l0 = inst.L0
	if l0 then
		return l0
	end
	local members = inst.Spec.Members or {}
	local list: { number } = table.create(#members, 0)
	local fs = newFieldSet(self.Seed, self.OctLo, self.OctHi)
	for index, member in ipairs(members) do
		local m = self.Insts[member]
		if m then
			list[index] = (stockLog(self, fs, m, inst.Spec.Origin))
		end
	end
	inst.L0 = list
	return list
end

local function etfLog(self: any, fs: FieldSet, inst: Inst, t: number, memberLog: { [number]: number }?): number
	local members = inst.Spec.Members or {}
	local l0 = etfL0(self, inst)
	local sum, n = 0, 0
	for index, member in ipairs(members) do
		local m = self.Insts[member]
		if m then
			local value = if memberLog then memberLog[member] else nil
			if value == nil then
				value = (stockLog(self, fs, m, t))
			end
			sum += (value :: number) - l0[index]
			n += 1
		end
	end
	return inst.LnBase + (if n > 0 then sum / n else 0)
end

local function toCents(self: any, logMid: number): number
	local v = math.exp(logMid) * 100
	if v ~= v then
		return self.MinCents
	end
	return math.clamp(math.round(v), self.MinCents, self.MaxCents)
end

-- kanonische 1s-Kerze aus O (Vorsekunde) und C
local function candle(
	self: any,
	i: number,
	t: number,
	o: number,
	c: number,
	r: number,
	sigma1s: number,
	volBase: number,
	news: boolean
): (number, number, number, number, number, number, number)
	local s = math.max(1e-5, sigma1s)
	local rawH = math.max(o, c) * (1 + math.abs(White(self.Seed, 300 + i, t)) * s * 0.6)
	local rawL = math.min(o, c) * (1 - math.abs(White(self.Seed, 400 + i, t)) * s * 0.6)
	local hiOff = math.min(255, QuoteCodec.HiOff(o, c, rawH))
	local loOff = math.min(255, QuoteCodec.LoOff(o, c, rawL))
	local h = QuoteCodec.HiFrom(o, c, hiOff)
	local l = QuoteCodec.LoFrom(o, c, loOff)
	local second = t % self.DayTicks
	local edge = if second < self.EdgeTicks or second >= self.DayTicks - self.EdgeTicks then self.EdgeMult else 1
	local move = if o > 0 and c > 0 then math.abs(math.log(c / o)) else 0
	local v = volBase
		* r
		* (0.5 + (Noise.Uni(self.Seed, 500 + i, 0, t) + 1) / 2)
		* (1 + 6 * move / s)
		* (if news then 3 else 1)
		* edge
	return o, h, l, c, math.clamp(math.round(v / 10), 0, 65535), hiOff, loOff
end

-- ---------------------------------------------------------------------
-- LIVE
-- ---------------------------------------------------------------------
function PriceEngine.Step(self: any, t: number)
	local fs: FieldSet = self.Live
	shared(self, fs, t)
	local r = fs.MemoR
	local logs: { [number]: number } = {}
	local cont = self.LiveT == t - 1
	for _, i in ipairs(self.Stocks) do
		local inst: Inst = self.Insts[i]
		local spec = inst.Spec
		if t < spec.Origin then
			continue
		end
		local lm, news = stockLog(self, fs, inst, t)
		logs[i] = lm
		local mid = toCents(self, lm)
		local prev = if cont and inst.T == t - 1 then inst.Mid else self:MidAt(i, t - 1)
		local _, sigma1s, spreadBps = classAt(spec, t)
		local o, h, l, c, v, hiOff, loOff = candle(self, i, t, prev, mid, r, sigma1s, spec.VolBase, news)
		local bid, ask = QuoteCodec.Spread(mid, spreadBps, r)
		inst.T, inst.Mid, inst.Log = t, mid, lm
		inst.O, inst.H, inst.L, inst.C, inst.V, inst.HiOff, inst.LoOff = o, h, l, c, v, hiOff, loOff
		inst.Bid, inst.Ask = bid, ask
		inst.News = news
	end
	for _, i in ipairs(self.Etfs) do
		local inst: Inst = self.Insts[i]
		local spec = inst.Spec
		if t < spec.Origin then
			continue
		end
		local lm = etfLog(self, fs, inst, t, logs)
		local mid = toCents(self, lm)
		local prev = if cont and inst.T == t - 1 then inst.Mid else self:MidAt(i, t - 1)
		local o, h, l, c, v, hiOff, loOff = candle(self, i, t, prev, mid, r, spec.Sigma1s, spec.VolBase, false)
		local bid, ask = QuoteCodec.Spread(mid, spec.SpreadBps, r)
		inst.T, inst.Mid, inst.Log = t, mid, lm
		inst.O, inst.H, inst.L, inst.C, inst.V, inst.HiOff, inst.LoOff = o, h, l, c, v, hiOff, loOff
		inst.Bid, inst.Ask = bid, ask
	end
	self.LiveT = t
	self.LiveR = r
end

function PriceEngine.Quote(self: any, i: number): (number?, number?, number?)
	local inst = self.Insts[i]
	if inst == nil or inst.T ~= self.LiveT then
		return nil, nil, nil
	end
	return inst.Bid, inst.Ask, inst.Mid
end

function PriceEngine.HalfSpread(self: any, i: number): number
	local inst = self.Insts[i]
	if inst == nil or inst.T ~= self.LiveT then
		return 0
	end
	return inst.Ask - inst.Mid
end

function PriceEngine.Candle(self: any, i: number): (number?, number?, number?, number?, number?, number?, number?)
	local inst = self.Insts[i]
	if inst == nil or inst.T ~= self.LiveT then
		return nil, nil, nil, nil, nil, nil, nil
	end
	return inst.O, inst.H, inst.L, inst.C, inst.V, inst.HiOff, inst.LoOff
end

function PriceEngine.Regime(self: any): number
	return self.LiveR
end

function PriceEngine.NewsActive(self: any, i: number): boolean
	local inst = self.Insts[i]
	return inst ~= nil and inst.T == self.LiveT and inst.News
end

-- ---------------------------------------------------------------------
-- RANDOM-ACCESS (Historie, Offline-Abgleich, Fill-Audit) – rechnet exakt dasselbe wie Step
-- ---------------------------------------------------------------------
function PriceEngine.RegimeAt(self: any, t: number): number
	local fs: FieldSet = self.RA
	shared(self, fs, t)
	return fs.MemoR
end

function PriceEngine.LogAt(self: any, i: number, t: number, divFrom: number?): (number, boolean)
	local inst: Inst? = self.Insts[i]
	if inst == nil then
		return 0, false
	end
	local spec = inst.Spec
	if t < spec.Origin then
		return inst.LnBase, false
	end
	if divFrom == nil and inst.T == t and self.LiveT == t then
		return inst.Log, false
	end
	local fs: FieldSet = self.RA
	if spec.Etf then
		return etfLog(self, fs, inst, t, nil), false
	end
	return stockLog(self, fs, inst, t, divFrom)
end

function PriceEngine.MidAt(self: any, i: number, t: number, divFrom: number?): number
	local inst: Inst? = self.Insts[i]
	if inst == nil then
		return 0
	end
	if divFrom == nil and inst.T == t and self.LiveT == t then
		return inst.Mid
	end
	local lm = self:LogAt(i, t, divFrom)
	return toCents(self, lm)
end

function PriceEngine.CandleAt(self: any, i: number, t: number): (number, number, number, number, number, number, number)
	local inst: Inst? = self.Insts[i]
	if inst == nil then
		return 0, 0, 0, 0, 0, 0, 0
	end
	if inst.T == t and self.LiveT == t then
		return inst.O, inst.H, inst.L, inst.C, inst.V, inst.HiOff, inst.LoOff
	end
	local spec = inst.Spec
	local prev = self:MidAt(i, t - 1)
	local lm, news = self:LogAt(i, t)
	local mid = toCents(self, lm)
	local r = self:RegimeAt(t)
	local _, sigma1s = classAt(spec, t)
	return candle(self, i, t, prev, mid, r, if spec.Etf then spec.Sigma1s else sigma1s, spec.VolBase, news)
end

-- ---------------------------------------------------------------------
-- CURSOR (sequentiell billig, eigene Felder; Offline-Abgleich WP4, Backfill)
-- ---------------------------------------------------------------------
function PriceEngine.NewCursor(self: any, i: number, t0: number)
	local engine = self
	local fs = newFieldSet(self.Seed, self.OctLo, self.OctHi)
	local cursor = { LastT = -math.huge, LastMid = 0, Id = i }

	local function mid(t: number): (number, boolean)
		local inst: Inst? = engine.Insts[i]
		if inst == nil then
			return 0, false
		end
		local spec = inst.Spec
		if t < spec.Origin then
			return toCents(engine, inst.LnBase), false
		end
		if spec.Etf then
			return toCents(engine, etfLog(engine, fs, inst, t, nil)), false
		end
		local lm, news = stockLog(engine, fs, inst, t)
		return toCents(engine, lm), news
	end

	function cursor.Seek(selfCursor: any, t: number)
		selfCursor.LastT = t - 1
		selfCursor.LastMid = (mid(t - 1))
	end

	-- volle Kerze (mit Umsatz und Dochtabständen) – für den Backfill
	function cursor.Full(selfCursor: any, t: number): (number, number, number, number, number, number, number)
		if selfCursor.LastT ~= t - 1 then
			selfCursor:Seek(t)
		end
		local o = selfCursor.LastMid
		local c, news = mid(t)
		local inst: Inst? = engine.Insts[i]
		selfCursor.LastT = t
		selfCursor.LastMid = c
		if inst == nil then
			return o, o, o, o, 0, 0, 0
		end
		local spec = inst.Spec
		shared(engine, fs, t)
		local _, sigma1s = classAt(spec, t)
		return candle(engine, i, t, o, c, fs.MemoR, if spec.Etf then spec.Sigma1s else sigma1s, spec.VolBase, news)
	end

	function cursor.Candle(selfCursor: any, t: number): (number, number, number, number)
		local o, h, l, c = selfCursor:Full(t)
		return o, h, l, c
	end

	cursor:Seek(t0)
	return cursor
end

return PriceEngine
