--!strict
-- =====================================================================
--  AKYTEX TYCOON – Deterministischer Tagesplan & Event-Beiträge (Server/Market/EventDirector)
--  Besitzer: WP3 (Markt-Engine). Vertrag: MARKET.md §5.4, §6.1–§6.6, §8.4, §17; DESIGN.md §B6.1, §B6.3, §B10.4, §B15.3.
--  Eine Instanz je Woche ("Wochen-Kontext"). Der Plan entsteht zustandslos aus Seed + Börsentag (kein Random-Objekt);
--  wegen der Bewertungs-Bremse werden die Tage ab Wochenstart SEQUENTIELL gebaut und gecacht.
--  Der Server kennt den Plan, schickt aber nie Zukünftiges: News gehen erst bei t_a hinaus (MarketService).
--
--  Kursbeitrag E_i(t) = Σ abgeschlossene, dauerhafte Anteile (Präfix-Summen) + Σ aktive Beiträge (Rampe/Rückbildung)
--                     + Dividenden-Abschläge (Ex-Tick) + bedingte Beiträge (Samstags-Show) + externe Admin-Events.
--  Formen: 1 News mit Übertreibung · 2 Rampe auf Dauerwert · 3 Crash/Rallye (Fall + Teil-Erholung) ·
--          4 Admin-Beule (Rampe, Abklingen auf 0, Normalisieren blendet aus)
--
--  Öffentliche API (nur Server, nur innerhalb WP3)
--    EventDirector.new(params): Director
--    d:EnsureBuilt(day, maxDays?): boolean        baut sequentiell bis zum Börsentag (globaler Index), höchstens maxDays
--    d:BuiltThrough(): number                       d:SetPriceHook(fn(i, t, divFrom) -> midCents)
--    d:Offset(i, t, divFrom?): (number, boolean)    Log-Beitrag, News aktiv?
--    d:VolMul(t): number                            Volatilitäts-Faktor (Crash/Rallye/Admin), Produkt, geklemmt
--    d:Halted(i, t): (boolean, number)              Handelspause? (+ Ende)
--    d:CrashRally(t): (boolean, boolean)            Crash/Rallye aktiv (Frame-Flags)
--    d:NewsIn(t0, t1): { NewsItem }                 veröffentlichte News mit t0 < T ≤ t1 (Plan + extern, gefiltert)
--    d:MessagesAt(t): { {Kind, Data} }              Market-Remote-Nachrichten dieses Ticks (Event/Halt/Ipo)
--    d:Dividends(t0, t1): { {I, Tick, Cents} }      Ex-Ticks im Bereich (nur Vergangenheit sinnvoll)
--    d:ExDay(i, t): boolean                         Ex-Tag-Flag (Börsentag mit Dividende, bis einschließlich Ex-Tick)
--    d:Calendar(t0, t1): { CalendarItem }           Termine im Bereich (nur geplante Arten, nie zufällige News)
--    d:Profile(i, now, leadSeconds): { … }          Fundamentaldaten + Analysten (Trefferquote live gemessen)
--    d:FactNewsFor(i, t, window): NewsItem?         letzte Fakten-News (Fakt/Bestätigung/Dementi/Zahlen) zu i
--    d:AddExternal(ev, carry?): { number }          Admin-Event (GlobalBus) anwenden -> betroffene Ids
--    d:AddLocalHalt(ids?, from, untilTick)          serverlokale Pause (verspätetes Bus-Event, §8.4)
--    d:AddListing(i, rec) · d:Listing(i) · d:IsListed(i, t) · d:Drift(i) · d:Quality(i) · d:Slots()
--    d:CondOk(cond, t?) · d:AutoShowCut(): number?   Samstags-Show-Absage gilt ab dem Start-Tick des Bus-Events
--    d:Windows(): { {From, To} }                    Admin-Fenster aus externen Events
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Noise = require(script.Parent:WaitForChild("Noise"))
local MarketClock = require(script.Parent:WaitForChild("MarketClock"))
local Dividends = require(script.Parent:WaitForChild("Dividends"))

local EventDirector = {}
EventDirector.__index = EventDirector

type NewsItem = Types.NewsItem
type CalendarItem = Types.CalendarItem

-- Formen
local SHAPE_NEWS = 1
local SHAPE_RAMP = 2
local SHAPE_CRASH = 3
local SHAPE_BUMP = 4

-- Hash-Kanäle (fest, nie ändern – sonst ändert sich jeder Plan)
local CH_DAY = 0xDA7 -- globaler Tages-Strom
local CH_INST = 0x1000 -- + Id: Firmen-Strom
local CH_Q = 0x51A -- Qualität q
local CH_EARN = 0xEA1 -- Quartals-Überraschung z
local CH_EARN_PRE = 0xEA2 -- synthetische Vor-Quartale
local CH_ANALYST = 0xA7A
local CH_MACRO = 0xAC0
local CH_SENS = 0x5E5
local CH_IPO = 0x1F0
local CH_FUND = 0xF00D

local TWO32 = 4294967296

export type Effect = {
	S0: number, -- Sortier-Tick (Veröffentlichung)
	T1: number, -- Beginn der Kursreaktion
	Shape: number,
	J: number,
	O: number, -- Übertreibung
	A: number, -- Rampe bzw. Fall
	B: number, -- Rückbildung/Erholung/Abklingen
	R: number, -- Erholungs-Anteil (Crash)
	F: number, -- Dauerwert nach End
	End: number,
	News: boolean,
	Val: boolean,
	Cond: string?,
	Kill: number?,
	SubAt: number?, -- Übertrag aus der Vorwoche: Beitrag relativ zu diesem Tick (Wochenschluss)
	Start0: number, -- ursprünglicher Start (für Normalisieren über den Wochenwechsel)
}

export type VolShape = {
	S0: number,
	T1: number,
	End: number,
	Kind: number, -- 1 Warn (linear) · 2 Crash (Fall -> Spitze -> 1) · 3 Admin-Vol (Rampe/Halten/Rampe) · 4 Admin-Beule
	A: number,
	B: number,
	V0: number,
	V1: number,
	Peak: number,
	Cond: string?,
	Kill: number?,
}

export type Halt = { All: boolean, I: number?, From: number, Until: number, Cond: string?, Ext: boolean }

export type Slot = {
	Id: number,
	Name: string,
	Class: string,
	Sector: string,
	SectorIdx: number,
	Start: number,
	DivBps: number,
	Base: number, -- Wochenbasis in Cent (Wochenschluss der Vorwoche bzw. Eröffnungskurs)
	ValBase: number, -- Basis für die Bewertungs-Bremse (beim Anlegen der Woche fest, nie durch Admin-IPOs verändert)
	Ipo: boolean,
	Origin: number, -- ab diesem Tick zählt das Instrument (Wochenstart oder Erstnotiz)
	ValOrigin: number, -- ab diesem Tick zählen Sprünge für die Bewertungs-Bremse (unabhängig von Admin-IPOs)
}

export type Listing = { T0: number, Issue: number, Open: number, Pop: number, Q: number, By: number }

type Msg = { T: number, Kind: string, Data: { [string]: any }, Cond: string? }
type Plain = { [string]: any }

local function smooth(x: number): number
	if x <= 0 then
		return 0
	elseif x >= 1 then
		return 1
	end
	return x * x * (3 - 2 * x)
end

local function sign(x: number): number
	return if x < 0 then -1 else 1
end

-- erster Index k mit list[k] > value (0, wenn keiner ≤ value); list aufsteigend
local function upperBound(list: { number }, value: number, lo: number?): number
	local a, b = lo or 1, #list
	if b == 0 or list[b] <= value then
		return b
	end
	while a <= b do
		local m = (a + b) // 2
		if list[m] <= value then
			a = m + 1
		else
			b = m - 1
		end
	end
	return a - 1
end

-- ---------------------------------------------------------------------
-- KONSTRUKTOR
-- params = { Seed, Week, Config (Config.Market), Companies (Config.Companies), News (Config.News),
--            Slots { Slot }, NewsMeanGap, Listings { [id] = Listing }, IsCancelled: (week) -> boolean }
-- ---------------------------------------------------------------------
function EventDirector.new(params: Plain)
	local cfg = params.Config
	local self = setmetatable({}, EventDirector) :: any
	self.Seed = math.floor(params.Seed) % 2147483648
	self.Week = params.Week
	self.WeekStart = MarketClock.WeekStart(params.Week)
	self.WeekEnd = MarketClock.WeekEnd(params.Week)
	self.FirstDay = MarketClock.DayIndex(self.WeekStart)
	self.LastDay = MarketClock.DayIndex(self.WeekEnd)
	self.Cfg = cfg
	self.Companies = params.Companies
	self.NewsCfg = params.News
	self.Gap = math.clamp(tonumber(params.NewsMeanGap) or cfg.NewsMeanGap or 1500, 300, 6000)
	self.IsCancelled = params.IsCancelled
	self.Delay = cfg.Delay
	self.Tau = cfg.Tau
	self.OverDecay = cfg.Overshoot.Decay
	self.OverSpan = cfg.Overshoot.Span
	self.MaxSpan = 0 -- längste gemessene Plan-Wirkung (End − S0), wächst beim Einsortieren
	self.MaxVolSpan = math.max(3700, (cfg.Admin.MaxSpan or 3600) + 600)
	self.PriceHook = nil :: ((number, number, number) -> number)?

	self.SlotList = {} :: { Slot }
	self.SlotById = {} :: { [number]: Slot }
	self.Q = {} :: { [number]: number }
	self.DriftT = {} :: { [number]: number }
	self.Rate = {} :: { [number]: { [number]: number } } -- Drift je Tick, je Börsentag der Woche (0…503)
	self.Cum = {} :: { [number]: { [number]: number } } -- aufgelaufene Drift (log) zum Tagesbeginn
	self.CumAll = {} :: { [number]: number }
	self.DriftSum = {} :: { [number]: number } -- Drift seit ValOrigin (für die Bewertung)
	self.OriginDrift = {} :: { [number]: number }
	self.Val = {} :: { [number]: number }
	self.Eff = {} :: { [number]: { Effect } }
	self.EffS0 = {} :: { [number]: { number } }
	self.Pre = {} :: { [number]: { number } }
	self.Pend = {} :: { [number]: { Effect } }
	self.CondEff = {} :: { [number]: { Effect } }
	self.Div = {} :: { [number]: { Plain } }
	self.DivT = {} :: { [number]: { number } }
	self.DivCum = {} :: { [number]: { [number]: number } }
	self.DivDone = {} :: { [number]: number }
	self.Ext = {} :: { [number]: { Effect } }
	self.OriginK = {} :: { [number]: number }
	for _, slot in ipairs(params.Slots :: { Slot }) do
		table.insert(self.SlotList, slot)
		self.SlotById[slot.Id] = slot
		local q = Noise.Uni(self.Seed, CH_Q, slot.Id, 0)
		self.Q[slot.Id] = q
		self.DriftT[slot.Id] = (cfg.Drift.Base + cfg.Drift.Quality * q) / MarketClock.DAY
		self.Rate[slot.Id] = {}
		self.Cum[slot.Id] = {}
		self.CumAll[slot.Id] = 0
		self.DriftSum[slot.Id] = 0
		self.Val[slot.Id] = 0
		self.Eff[slot.Id] = {}
		self.EffS0[slot.Id] = {}
		self.Pre[slot.Id] = { [0] = 0 } :: any
		self.Pend[slot.Id] = {}
		self.CondEff[slot.Id] = {}
		self.Div[slot.Id] = {}
		self.DivT[slot.Id] = {}
		self.DivCum[slot.Id] = { [0] = 0 } :: any
		self.DivDone[slot.Id] = 0
		self.Ext[slot.Id] = {}
		self.OriginK[slot.Id] = 0
	end
	self.Listings = {} :: { [number]: Listing }
	for id, rec in pairs((params.Listings or {}) :: { [number]: Listing }) do
		self.Listings[id] = rec
	end

	self.News = {} :: { Plain } -- Plan-News (sortiert nach T), Einträge { Item, Cond?, DivOf? }
	self.NewsT = {} :: { number }
	self.PendNews = {} :: { Plain }
	self.ExtNews = {} :: { Plain }
	self.Vol = {} :: { VolShape }
	self.VolS0 = {} :: { number }
	self.Halts = {} :: { Halt }
	self.Msgs = {} :: { Msg }
	self.MsgT = {} :: { number }
	self.ExtMsgs = {} :: { Msg }
	self.CrashSpans = {} :: { { number } } -- { von, bis, 1 = Crash / 2 = Rallye, Cond? }
	self.DayData = {} :: { [number]: Plain }
	self.Built = self.FirstDay - 1
	self.LastCrashT = -math.huge
	self.WindowList = {} :: { { number } }
	self.NewsSeq = {} :: { [number]: number }
	return self
end

function EventDirector.SetPriceHook(self: any, fn: (number, number, number) -> number)
	self.PriceHook = fn
end

function EventDirector.BuiltThrough(self: any): number
	return self.Built
end

function EventDirector.Slots(self: any): { Slot }
	return self.SlotList
end

function EventDirector.Quality(self: any, i: number): number
	return self.Q[i] or 0
end

-- Drift steckt im Beitrag (Offset); die PriceEngine bekommt Drift = 0. Hier nur zur Anzeige: Grund-Drift je Tick.
function EventDirector.Drift(self: any, i: number): number
	return self.DriftT[i] or 0
end

-- aufgelaufene Fundament-Drift (log) bei Tick t relativ zum Wochenstart; nil, wenn der Tag noch nicht gebaut ist
local function driftAt(self: any, i: number, t: number): number?
	local d = MarketClock.DayIndex(t) - self.FirstDay
	local rates = self.Rate[i]
	local rate = rates and rates[d]
	if rate == nil then
		return nil
	end
	return self.Cum[i][d] + rate * (t - (self.FirstDay + d) * MarketClock.DAY)
end

function EventDirector.DriftOffset(self: any, i: number, t: number): number
	local slot = self.SlotById[i]
	if slot == nil then
		return 0
	end
	local now = driftAt(self, i, t)
	if now == nil then
		return 0
	end
	local origin = slot.Origin
	if origin <= self.WeekStart then
		return now
	end
	local base = self.OriginDrift[i]
	if base == nil then
		base = driftAt(self, i, origin)
		if base == nil then
			return 0
		end
		self.OriginDrift[i] = base
	end
	return now - base
end

function EventDirector.Listing(self: any, i: number): Listing?
	return self.Listings[i]
end

function EventDirector.IsListed(self: any, i: number, t: number): boolean
	local slot = self.SlotById[i]
	if not slot then
		return false
	end
	if not slot.Ipo then
		return true
	end
	local rec = self.Listings[i]
	return rec ~= nil and t >= rec.T0
end

function EventDirector.AddListing(self: any, i: number, rec: Listing)
	self.Listings[i] = rec
	local slot = self.SlotById[i]
	if slot then
		slot.Origin = rec.T0
		slot.Base = rec.Open
		self.OriginK[i] = upperBound(self.EffS0[i], rec.T0 - 1)
		self.OriginDrift[i] = nil
	end
	local hook = self.ListingHook
	if type(hook) == "function" then
		hook(i, rec)
	end
end

-- MarketService meldet sich hier an, um neue Erstnotizen in die PriceEngine zu übernehmen
function EventDirector.SetListingHook(self: any, fn: (number, Listing) -> ())
	self.ListingHook = fn
end

-- ---------------------------------------------------------------------
-- ZUFALL (zustandslos aus Seed): globaler Tages-Strom und Firmen-Ströme mit festen Blöcken
-- ---------------------------------------------------------------------
function EventDirector.R(self: any, day: number, k: number): number
	return Noise.Hash4(self.Seed, CH_DAY, day, k) / TWO32
end

function EventDirector.RI(self: any, i: number, day: number, k: number): number
	return Noise.Hash4(self.Seed, CH_INST + i, day, k) / TWO32
end

-- Klasse für den PLAN (News-Faktor, Crash-Beta): immer die eigene Klasse, damit der Plan nie davon abhängt, ob/wann
-- ein Admin-IPO bekannt wurde (Determinismus). Die Wild-Volatilität am ersten Börsentag macht die PriceEngine.
local function classOf(self: any, slot: Slot, _t: number): Plain
	local classes = self.Cfg.Classes
	return classes[slot.Class] or classes.Normal
end

local function bandOf(self: any, u: number): number
	local acc = 0
	for index, band in ipairs(self.Cfg.Bands) do
		acc += band.P
		if u <= acc then
			return index
		end
	end
	return #self.Cfg.Bands
end

-- Stärke-Band aus einem Log-Sprung (für Crash, Zahlen, Admin): Grenzen der Bänder der Klasse Normal
local function bandFromMove(self: any, move: number): number
	local a = math.abs(move)
	local bands = self.Cfg.Bands
	for index = #bands, 1, -1 do
		if a >= bands[index].Lo then
			return index
		end
	end
	return 1
end

-- Bewertung C = ln(Wochenbasis / Startkurs) + Drift seit Wochenstart + dauerhafte Sprünge der Woche (Plan)
local function valuation(self: any, slot: Slot): number
	local base = math.max(1, slot.ValBase)
	local start = math.max(1, slot.Start)
	return math.log(base / start) + self.DriftSum[slot.Id] + self.Val[slot.Id]
end

local function posProb(self: any, slot: Slot, _dayStart: number): number
	local brake = self.Cfg.Brake
	local c = valuation(self, slot)
	local p = brake.PosBase
	for _, step in ipairs(brake.Steps) do
		if c > step.Above then
			p = step.PosP
		elseif c < -step.Above then
			p = 1 - step.PosP
		end
	end
	return p
end

-- ---------------------------------------------------------------------
-- PLAN-BAUSTEINE
-- ---------------------------------------------------------------------
local function newEffect(s0: number, t1: number, shape: number, j: number, a: number, b: number): Effect
	return {
		S0 = s0,
		T1 = t1,
		Shape = shape,
		J = j,
		O = 0,
		A = a,
		B = b,
		R = 0,
		F = j,
		End = t1 + a + b,
		News = true,
		Val = true,
		Cond = nil,
		Kill = nil,
		SubAt = nil,
		Start0 = s0,
	}
end

local function pushNews(list: { Plain }, t: number, kind: string, key: string, args: Plain, extra: Plain?): Plain
	local item: Plain = { T = t, Kind = kind, Key = key, Args = args }
	if extra then
		for k, v in pairs(extra) do
			item[k] = v
		end
	end
	local wrap: Plain = { Item = item }
	table.insert(list, wrap)
	return wrap
end

function EventDirector.NewsArgsName(self: any, i: number): string
	local slot = self.SlotById[i]
	return if slot then slot.Name else tostring(i)
end

local function pick(list: { string }, u: number): string
	return list[math.clamp(1 + math.floor(u * #list), 1, #list)]
end

-- Quartalszahlen eines Börsentags (rein aus den Regeln + Hash, unabhängig von der Bremse)
function EventDirector.EarningsFor(self: any, day: number): { Plain }
	local cache = self.EarnCache
	if cache == nil then
		cache = {}
		self.EarnCache = cache
	end
	local hit = cache[day]
	if hit then
		return hit
	end
	local cfg = self.Cfg
	local earn = cfg.Earnings
	local dayStart = MarketClock.DayStart(day)
	local list: { Plain } = {}
	local ids: { number } = {}
	for _, slot in ipairs(self.SlotList) do
		if (day + slot.Id) % earn.EveryDays == 0 then
			table.insert(ids, slot.Id)
		end
	end
	table.sort(ids)
	local analysts = cfg.Analysts
	for index, id in ipairs(ids) do
		local slot = self.SlotById[id]
		local minute = earn.Slots[((index - 1) // 3) % #earn.Slots + 1]
		local t = dayStart + minute * 60
		local q = self.Q[id] or 0
		local s = earn.SurpriseQ * q + earn.SurpriseZ * Noise.Gauss(self.Seed, CH_EARN, id, day)
		local cls = classOf(self, slot, t)
		local j = math.clamp(earn.JumpPerS * s * cls.NewsFactor, -earn.JumpMax, earn.JumpMax)
		local verdicts: { { number } } = {}
		local used: { [number]: boolean } = {}
		local n = math.min(earn.Covering, #analysts)
		local k = 0
		while #verdicts < n and k < 64 do -- gebunden: höchstens 64 Versuche
			k += 1
			local a = 1 + Noise.Hash4(self.Seed, CH_ANALYST, id * 4096 + day % 4096, k) % #analysts
			if not used[a] then
				used[a] = true
				local right = Noise.Rnd(self.Seed, CH_ANALYST + 1, id * 64 + a, day) < analysts[a].Accuracy
				table.insert(verdicts, { a, if right then sign(s) else -sign(s) })
			end
		end
		local growth = cfg.Fundamentals.GrowthBase + cfg.Fundamentals.GrowthQ * q
		table.insert(list, {
			I = id,
			T = t,
			Minute = minute,
			S = s,
			J = j,
			Verdicts = verdicts,
			Cons = if growth > 0.005 then "Up" elseif growth < -0.005 then "Down" else "Flat",
		})
	end
	cache[day] = list
	return list
end

function EventDirector.MacroKind(self: any, day: number): string
	local kinds = self.Cfg.Macro.Kinds
	return pick(kinds, self:R(day, 1))
end

-- ---------------------------------------------------------------------
-- BUILD DAY (sequentiell; nur aus Seed, Woche, Basis, Config, eingefrorenem News-Takt)
-- ---------------------------------------------------------------------
function EventDirector.BuildDay(self: any, day: number)
	local cfg = self.Cfg
	local newsCfg = self.NewsCfg
	local delay, tau = self.Delay, self.Tau
	local dayStart = MarketClock.DayStart(day)
	local nextStart = dayStart + MarketClock.DAY
	local dayInWeek = day - self.FirstDay
	local created: { [number]: { Effect } } = {}
	local news: { Plain } = {}
	local msgs: { Msg } = {}
	local data: Plain = { Earnings = {}, Macro = nil, Dividends = {} }
	self.DayData[day] = data

	-- 0) Fundament-Drift dieses Börsentags mit Bewertungsanker (Ornstein-Uhlenbeck je Tag):
	--    Rate = Base + Quality · q − Revert · C  (je Börsentag), C = Bewertung zum Tagesbeginn. Ohne Anker würde die
	--    Drift über 504 Börsentage je Woche exponentiell wachsen; so bleibt der Kurs um Start · e^((Base+Quality·q)/Revert).
	local driftCfg = cfg.Drift
	for _, slot in ipairs(self.SlotList) do
		local i = slot.Id
		local c = valuation(self, slot)
		local rate = driftCfg.Base + driftCfg.Quality * (self.Q[i] or 0) - (driftCfg.Revert or 0) * c
		rate = math.clamp(rate, -(driftCfg.MaxRate or 0.02), driftCfg.MaxRate or 0.02)
		self.Rate[i][dayInWeek] = rate / MarketClock.DAY
		self.Cum[i][dayInWeek] = self.CumAll[i]
		self.CumAll[i] += rate
		if dayStart >= slot.ValOrigin then
			self.DriftSum[i] += rate
		elseif nextStart > slot.ValOrigin then
			self.DriftSum[i] += rate * (nextStart - slot.ValOrigin) / MarketClock.DAY
		end
	end

	local function addEffect(i: number, e: Effect)
		local list = created[i]
		if list == nil then
			list = {}
			created[i] = list
		end
		table.insert(list, e)
	end

	local function addVol(v: VolShape)
		table.insert(self.Vol, v)
		table.insert(self.VolS0, v.S0)
	end

	-- 1) Quartalszahlen (+ Vorschau für Termine, deren Vorschau in diesen Tag fällt) und Dividenden
	local earn = cfg.Earnings
	local previewLead = earn.PreviewMinutes * 60
	for _, e in ipairs(self:EarningsFor(day)) do
		table.insert(data.Earnings, e)
		local slot = self.SlotById[e.I]
		local name = slot.Name
		if math.abs(e.J) > 1e-9 then
			local eff = newEffect(e.T, e.T + delay, SHAPE_RAMP, e.J, tau, 0)
			addEffect(e.I, eff)
		end
		local key = if math.abs(e.J) < earn.InlineBelow
			then newsCfg.Earnings.Inline
			elseif e.J > 0 then newsCfg.Earnings.Beat
			else newsCfg.Earnings.Miss
		local band = bandFromMove(self, e.J)
		pushNews(news, e.T, "Earnings", key, { name = name, band = newsCfg.Bands[band] }, {
			I = e.I,
			Band = band,
			-- "im Rahmen der Erwartungen": keine Richtung (Tiko-Ampel neutral, kein "Gut gelesen")
			Dir = if math.abs(e.J) < earn.InlineBelow then 0 else sign(e.J),
		})
		if e.T - previewLead >= dayStart then
			pushNews(news, e.T - previewLead, "Earnings", newsCfg.Earnings.Preview, {
				name = name,
				min = string.format("%02d", e.Minute),
				cons = newsCfg.Cons[e.Cons],
			}, { I = e.I })
		end
		local exTick = Dividends.ExTick(e.I, day, slot.DivBps, cfg)
		if exTick then
			local divList = self.Div[e.I]
			table.insert(divList, { Tick = exTick, Bps = slot.DivBps, Cents = nil, LogF = nil, K = #divList + 1 })
			table.insert(self.DivT[e.I], exTick)
			if exTick >= slot.ValOrigin then
				-- Bewertung sieht den Dividenden-Abschlag (Nennrendite, preisunabhängig -> deterministisch)
				self.Val[e.I] += math.log(1 - slot.DivBps / 10000)
			end
			table.insert(data.Dividends, { I = e.I, Tick = exTick })
			local wrap = pushNews(news, exTick, "Dividend", newsCfg.Dividend, { name = name }, { I = e.I })
			wrap.DivOf = e.I
		end
	end
	if day + 1 <= self.LastDay then
		for _, e in ipairs(self:EarningsFor(day + 1)) do
			if e.T - previewLead < nextStart then
				pushNews(news, e.T - previewLead, "Earnings", newsCfg.Earnings.Preview, {
					name = self.SlotById[e.I].Name,
					min = string.format("%02d", e.Minute),
					cons = newsCfg.Cons[e.Cons],
				}, { I = e.I })
			end
		end
	end

	-- 2) Makro (:02 Konsens, :10 Ergebnis über die Matrix)
	do
		local macro = cfg.Macro
		local kind = self:MacroKind(day)
		local consU = self:R(day, 2)
		local cons = if consU < 0.4 then "Up" elseif consU < 0.8 then "Down" else "Flat"
		local s = math.clamp(Noise.Gauss(self.Seed, CH_MACRO, day, 0), -macro.SurpriseMax, macro.SurpriseMax)
		local tMacro = dayStart + macro.Minute * 60
		local keys = newsCfg.Macro[kind]
		pushNews(news, dayStart + macro.PreviewMinute * 60, "Macro", keys.Preview, { cons = newsCfg.Cons[cons] })
		data.Macro = { Kind = kind, T = tMacro, S = s }
		if math.abs(s) < macro.FlatBelow then
			pushNews(news, tMacro, "Macro", keys.AsExpected, {}, { Dir = 1 })
		else
			local factors = cfg.Matrix[kind]
			for _, slot in ipairs(self.SlotList) do
				local f = factors[slot.Sector] or 0
				if f ~= 0 then
					local j = macro.BaseJump * f * s * classOf(self, slot, tMacro).NewsFactor
					addEffect(slot.Id, newEffect(tMacro, tMacro + delay, SHAPE_RAMP, j, tau, 0))
				end
			end
			local band = math.clamp(math.floor((math.abs(s) - macro.FlatBelow) * 2) + 1, 1, 4)
			pushNews(
				news,
				tMacro,
				"Macro",
				if s > 0 then keys.Higher else keys.Lower,
				{ band = newsCfg.Bands[band] },
				{ Band = band, Dir = sign(s) }
			)
		end
	end

	-- 3) Firmen-News (Poisson je Firma, eigener Hash-Strom je Id, feste Zufalls-Blöcke je News)
	local kinds = cfg.Kinds
	local rumorCfg = cfg.Rumor
	local quietFrom = self.WeekEnd - cfg.QuietEnd
	for _, slot in ipairs(self.SlotList) do
		local i = slot.Id
		local p = posProb(self, slot, dayStart)
		local n = 0
		local t = -self.Gap * math.log(1 - self:RI(i, day, 1))
		while t < MarketClock.DAY and n < 64 do -- gebunden: höchstens 64 News je Firma und Tag
			local ta = dayStart + math.floor(t)
			local base = 16 * (n + 1)
			n += 1
			local function u(k: number): number
				return self:RI(i, day, base + k)
			end
			if ta <= quietFrom then
				local cls = classOf(self, slot, ta)
				local b = bandOf(self, u(2))
				local bandCfg = cfg.Bands[b]
				local mag = bandCfg.Lo + (bandCfg.Hi - bandCfg.Lo) * u(3)
				local dir = if u(4) < p then 1 else -1
				local j0 = dir * mag * cls.NewsFactor
				local kindU = u(1)
				local kind = if kindU < kinds.Fact
					then "Fact"
					elseif kindU < kinds.Fact + kinds.Rumor then "Rumor"
					else "AsExpected"
				local resolveAt = ta + cfg.RumorResolve
				if kind == "Rumor" and resolveAt + delay + tau > self.WeekEnd then
					kind = "Fact"
				end
				local sectorProducts = newsCfg.Products[slot.Sector] or newsCfg.Products.T
				local buyerId = 1 + math.floor(u(9) * 36) % 36
				if buyerId == i then
					buyerId = buyerId % 36 + 1
				end
				local args: Plain = {
					name = slot.Name,
					band = newsCfg.Bands[b],
					product = pick(sectorProducts, u(8)),
					buyer = self:NewsArgsName(buyerId),
					amt = math.max(1, math.round((0.5 + u(10)) * b * b * 2)),
				}
				local dirKey = if dir > 0 then "Up" else "Down"
				if kind == "Fact" then
					local e = newEffect(ta, ta + delay, SHAPE_NEWS, j0, tau, self.OverDecay)
					e.O = cfg.Overshoot.Max * u(5)
					e.End = ta + delay + tau + self.OverSpan
					addEffect(i, e)
					pushNews(news, ta, "Fact", pick(newsCfg.Fact[dirKey], u(7)), args, { I = i, Band = b, Dir = dir })
				elseif kind == "Rumor" then
					local mix = rumorCfg.StarsMix
					local su = u(6)
					local stars = if su < mix[1] then 1 elseif su < mix[1] + mix[2] then 2 else 3
					local confirmed = u(11) < rumorCfg.Confirm[stars]
					addEffect(i, newEffect(ta, ta + delay, SHAPE_RAMP, 0.5 * j0, tau, 0))
					local second =
						newEffect(resolveAt, resolveAt + delay, SHAPE_RAMP, if confirmed then 0.5 * j0 else -j0, tau, 0)
					addEffect(i, second)
					args.stars = newsCfg.Stars[stars]
					pushNews(news, ta, "Rumor", pick(newsCfg.Rumor[dirKey], u(7)), args, {
						I = i,
						Band = b,
						Stars = stars,
						Dir = dir,
					})
					pushNews(
						news,
						resolveAt,
						if confirmed then "Confirm" else "Deny",
						if confirmed then newsCfg.Confirm else newsCfg.Deny,
						{ name = slot.Name },
						{ I = i, Band = b, Stars = stars, Dir = if confirmed then dir else -dir }
					)
				else
					addEffect(i, newEffect(ta, ta + delay, SHAPE_RAMP, -j0, tau, 0))
					pushNews(news, ta, "AsExpected", pick(newsCfg.AsExpected[dirKey], u(7)), args, {
						I = i,
						Band = b,
						Dir = dir,
					})
				end
			end
			t += -self.Gap * math.log(1 - u(12))
		end
	end

	-- 4) Sektor-News & Themen (globaler Strom, Ø alle 10 min)
	do
		local sec = cfg.Sector
		local k = 100
		local t = -sec.MeanGap * math.log(1 - self:R(day, k))
		local count = 0
		local sectors = self.Companies.Sectors
		while t < MarketClock.DAY and count < 32 do -- gebunden
			count += 1
			local ta = dayStart + math.floor(t)
			local base = 100 + 16 * count
			local function g(j: number): number
				return self:R(day, base + j)
			end
			if ta <= quietFrom then
				if g(1) < sec.ThemeShare then
					local theme = pick(cfg.Themes, g(2))
					local lu = g(3)
					local level = if lu < 0.5 then 1 elseif lu < 0.85 then 2 else 3
					local mult = sec.ThemeMult[level]
					local factors = cfg.Matrix[theme]
					local tone = 0
					for _, factor in pairs(factors) do
						tone += factor
					end
					for _, slot in ipairs(self.SlotList) do
						local f = factors[slot.Sector] or 0
						if f ~= 0 then
							local sens = sec.Sensitivity[1]
								+ (sec.Sensitivity[2] - sec.Sensitivity[1])
									* Noise.Rnd(self.Seed, CH_SENS, slot.Id, day * 64 + count)
							local j = cfg.Macro.BaseJump * f * mult * classOf(self, slot, ta).NewsFactor * sens
							addEffect(slot.Id, newEffect(ta, ta + delay, SHAPE_RAMP, j, tau, 0))
						end
					end
					pushNews(news, ta, "Sector", newsCfg.Theme[theme], { band = newsCfg.Bands[level] }, {
						Band = level,
						Dir = sign(tone),
					})
				else
					local sIndex = math.clamp(1 + math.floor(g(2) * #sectors), 1, #sectors)
					local sectorKey = sectors[sIndex].Key
					local b = bandOf(self, g(3))
					local bandCfg = cfg.Bands[b]
					local mag = bandCfg.Lo + (bandCfg.Hi - bandCfg.Lo) * g(4)
					local dir = if g(5) < cfg.Brake.PosBase then 1 else -1
					for _, slot in ipairs(self.SlotList) do
						if slot.Sector == sectorKey then
							local sens = sec.Sensitivity[1]
								+ (sec.Sensitivity[2] - sec.Sensitivity[1])
									* Noise.Rnd(self.Seed, CH_SENS, slot.Id, day * 64 + count)
							local j = dir * mag * classOf(self, slot, ta).NewsFactor * sens
							addEffect(slot.Id, newEffect(ta, ta + delay, SHAPE_RAMP, j, tau, 0))
						end
					end
					pushNews(
						news,
						ta,
						"Sector",
						if dir > 0 then newsCfg.Sector.Up else newsCfg.Sector.Down,
						{ sector = newsCfg.Sectors[sectorKey], band = newsCfg.Bands[b] },
						{ Sector = sectorKey, Band = b, Dir = dir }
					)
				end
			end
			t += -sec.MeanGap * math.log(1 - g(15))
		end
	end

	-- gemeinsamer Baustein: Crash/Rallye mit Warnphase (Plan, Wochen-Termin oder bedingte Samstags-Show)
	local function crashRally(spec: Plain)
		local cr = cfg.CrashRally
		local tw, tc = spec.Warn, spec.Main
		local t1 = tc + delay
		local fall, recover, share = spec.Fall, spec.Recover, spec.Share
		local isCrash = spec.Crash
		local maxBand = 1
		for _, slot in ipairs(self.SlotList) do
			if spec.Sector == nil or slot.Sector == spec.Sector then
				local cls = classOf(self, slot, tc)
				local move = math.min(cr.MaxMove, spec.Strength * cls.CrashBeta)
				local j = if isCrash then math.log(1 - move) else math.log(1 + move)
				local e = newEffect(tw, t1, SHAPE_CRASH, j, fall, recover)
				e.R = share
				e.F = j * (1 - share)
				e.End = t1 + fall + recover
				e.Val = spec.Val
				e.Cond = spec.Cond
				if spec.Cond then
					table.insert(self.CondEff[slot.Id], e)
				else
					addEffect(slot.Id, e)
				end
				maxBand = math.max(maxBand, bandFromMove(self, move * 0.5))
			end
		end
		local warnShape: VolShape = {
			S0 = tw,
			T1 = tw,
			End = t1,
			Kind = 1,
			A = math.max(1, t1 - tw),
			B = 0,
			V0 = cr.WarnRegime[1],
			V1 = cr.WarnRegime[2],
			Peak = cr.WarnRegime[2],
			Cond = spec.Cond,
			Kill = nil,
		}
		local runShape: VolShape = {
			S0 = tw,
			T1 = t1,
			End = t1 + fall + recover,
			Kind = 2,
			A = fall,
			B = recover,
			V0 = cr.WarnRegime[2],
			V1 = 1,
			Peak = cr.PeakRegime,
			Cond = spec.Cond,
			Kill = nil,
		}
		if tw < t1 then
			addVol(warnShape)
		end
		addVol(runShape)
		table.insert(self.CrashSpans, { tw, t1 + fall + recover, if isCrash then 1 else 2, spec.Cond })
		local warnKeys = if spec.Sector
			then { newsCfg.Warn.Sector }
			elseif isCrash then newsCfg.Warn.Crash
			else newsCfg.Warn.Rally
		local warnCount = if tw < tc then math.min(#warnKeys, math.max(1, (tc - tw) // 60)) else 0
		for index = 1, warnCount do
			local wrap = pushNews(news, tw + (index - 1) * 60, "Warn", warnKeys[index], {
				sector = if spec.Sector then newsCfg.Sectors[spec.Sector] else nil,
			}, { Sector = spec.Sector, Dir = if isCrash then -1 else 1 })
			wrap.Cond = spec.Cond
		end
		local mainWrap = pushNews(
			news,
			tc,
			if isCrash then "Crash" else "Rally",
			spec.Key,
			{ band = newsCfg.Bands[maxBand], sector = if spec.Sector then newsCfg.Sectors[spec.Sector] else nil },
			{ Sector = spec.Sector, Band = maxBand, Dir = if isCrash then -1 else 1 }
		)
		mainWrap.Cond = spec.Cond
		local kindName = if isCrash then "Crash" else "Rally"
		local untilTick = t1 + fall + recover
		local base: Plain =
			{ Kind = kindName, StartTick = tw, Until = untilTick, Scope = spec.Sector and "Sector" or "All" }
		if spec.Sector then
			base.Target = spec.Sector
		end
		local function msg(t: number, phase: string)
			local d: Plain = { Phase = phase }
			for k, v in pairs(base) do
				d[k] = v
			end
			table.insert(msgs, { T = t, Kind = "Event", Data = d, Cond = spec.Cond })
		end
		msg(tw, "Warn")
		msg(t1, "Run")
		msg(untilTick, "End")
	end

	-- 5) unangekündigte Crashs/Rallyes (Ø alle 3,5 h, mit Warnphase; nie in den letzten Tagen der Woche)
	do
		local cr = cfg.CrashRally
		local k = 900
		local t = -(1 / cr.Rate) * math.log(1 - self:R(day, k))
		local count = 0
		while t < MarketClock.DAY and count < 4 do -- gebunden
			count += 1
			local base = 900 + 16 * count
			local function g(j: number): number
				return self:R(day, base + j)
			end
			local tw = dayStart + math.floor(t)
			local blocked = dayInWeek >= MarketClock.DAYS_PER_WEEK - cr.QuietEndDays or tw - self.LastCrashT < cr.MinGap
			if not blocked then
				for _, entry in ipairs(cfg.Weekly) do
					if entry.Kind ~= "Ipo" then
						local wt = MarketClock.WeeklyTick(self.Week, entry.Dow, entry.HH, entry.MM)
						if wt and math.abs(wt - tw) < cr.MinGap then
							blocked = true
						end
					end
				end
			end
			if not blocked then
				local isCrash = g(1) < cr.CrashShare
				local range = if isCrash then cr.CrashDrop else cr.RallyRise
				crashRally({
					Warn = tw,
					Main = tw + cr.WarnSeconds,
					Crash = isCrash,
					Strength = range[1] + (range[2] - range[1]) * g(2),
					Fall = math.floor(cr.FallSeconds[1] + (cr.FallSeconds[2] - cr.FallSeconds[1]) * g(3)),
					Recover = math.floor(cr.RecoverSeconds[1] + (cr.RecoverSeconds[2] - cr.RecoverSeconds[1]) * g(4)),
					Share = cr.RecoverShare[1] + (cr.RecoverShare[2] - cr.RecoverShare[1]) * g(5),
					Key = if isCrash then newsCfg.Crash.All else newsCfg.Rally.All,
					Val = true,
				})
				self.LastCrashT = tw
			end
			t += -(1 / cr.Rate) * math.log(1 - g(15))
		end
	end

	-- 6) Wochen-Termine (Berlin-Zeit): Crash-Freitag, Rally-Mittwoch, Samstags-Show (bedingt), IPO-Erstnotiz
	local sectorOfWeek = self.Companies.Sectors[(self.Week % 6) + 1].Key
	for _, entry in ipairs(cfg.Weekly) do
		local wt = MarketClock.WeeklyTick(self.Week, entry.Dow, entry.HH, entry.MM)
		if wt == nil then
			continue
		end
		if entry.Kind == "Ipo" then
			local id = self:ScheduledIpo()
			if id then
				local prospectAt = wt - cfg.IpoPipeline.ProspectLead
				if prospectAt >= dayStart and prospectAt < nextStart and prospectAt >= self.WeekStart then
					self:IpoProspectNews(news, id, prospectAt, "IpoSched:" .. id .. ":" .. wt)
				end
				if wt >= dayStart and wt < nextStart then
					self:IpoListingPlan(news, msgs, id, wt, "IpoSched:" .. id .. ":" .. wt)
				end
			end
		else
			local main = wt + (entry.Offset or 0)
			local warn = main - cfg.CrashRally.WarnSeconds
			if warn >= dayStart and warn < nextStart and main + 1800 < self.WeekEnd then
				local isCrash = entry.Kind == "Crash"
				crashRally({
					Warn = warn,
					Main = main,
					Crash = isCrash,
					Strength = entry.Strength,
					Fall = 90,
					Recover = 900,
					Share = entry.Recover or 0.5,
					Sector = if entry.Scope == "Sector" then sectorOfWeek else nil,
					Key = newsCfg.Weekly[entry.Key] or (if isCrash then newsCfg.Crash.All else newsCfg.Rally.All),
					Val = false,
					Cond = if entry.Cancelable then "AutoShow" else nil,
				})
			end
		end
	end

	-- 7) einsortieren: Wirkungen (mit Überhang aus dem Vortag) nach S0, News nach T
	for _, slot in ipairs(self.SlotList) do
		local i = slot.Id
		local list: { Effect } = created[i] or {}
		for _, e in ipairs(self.Pend[i]) do
			table.insert(list, e)
		end
		table.sort(list, function(a: Effect, b: Effect)
			if a.S0 ~= b.S0 then
				return a.S0 < b.S0
			end
			return a.T1 < b.T1
		end)
		local keep: { Effect } = {}
		local eff, s0s, pre = self.Eff[i], self.EffS0[i], self.Pre[i]
		for _, e in ipairs(list) do
			if e.S0 < nextStart then
				table.insert(eff, e)
				table.insert(s0s, e.S0)
				pre[#eff] = (pre[#eff - 1] or 0) + e.F
				if e.End - e.S0 > self.MaxSpan then
					self.MaxSpan = e.End - e.S0
				end
			else
				table.insert(keep, e)
			end
		end
		self.Pend[i] = keep
		local createdHere = created[i]
		if createdHere then
			for _, e in ipairs(createdHere) do
				if e.Val and e.S0 >= slot.ValOrigin then
					self.Val[i] += e.F
				end
			end
		end
		if slot.Ipo then
			local rec = self.Listings[i]
			if rec then
				self.OriginK[i] = upperBound(s0s, rec.T0 - 1)
			end
		end
	end
	for _, wrap in ipairs(self.PendNews) do
		table.insert(news, wrap)
	end
	table.sort(news, function(a: Plain, b: Plain)
		return a.Item.T < b.Item.T
	end)
	local keepNews: { Plain } = {}
	for _, wrap in ipairs(news) do
		if wrap.Item.T < nextStart then
			local seq = (self.NewsSeq[day] or 0) + 1
			self.NewsSeq[day] = seq
			wrap.Item.Id = day * 512 + seq
			table.insert(self.News, wrap)
			table.insert(self.NewsT, wrap.Item.T)
		else
			table.insert(keepNews, wrap)
		end
	end
	self.PendNews = keepNews
	table.sort(msgs, function(a: Msg, b: Msg)
		return a.T < b.T
	end)
	for _, m in ipairs(msgs) do
		self:InsertMsg(m, false)
	end
	self.Built = day
end

function EventDirector.InsertMsg(self: any, m: Msg, external: boolean)
	local list = if external then self.ExtMsgs else self.Msgs
	if external then
		local index = #list + 1
		while index > 1 and list[index - 1].T > m.T do
			index -= 1
		end
		table.insert(list, index, m)
		return
	end
	local times = self.MsgT
	local index = upperBound(times, m.T) + 1
	table.insert(list, index, m)
	table.insert(times, index, m.T)
end

-- Saison/Woche -> geplantes IPO dieser Woche (oder nil)
function EventDirector.ScheduledIpo(self: any): number?
	local pipeline = self.Cfg.IpoPipeline
	local offset = self.Week - pipeline.FirstWeek
	if offset < 0 then
		return nil
	end
	local season = offset // pipeline.SeasonWeeks + 1
	local slotInSeason = offset % pipeline.SeasonWeeks + 1
	local ids = pipeline.Season[season]
	local id = if type(ids) == "table" then ids[slotInSeason] else nil
	if id and self.SlotById[id] then
		return id
	end
	return nil
end

function EventDirector.IpoQuality(self: any, id: number): (number, number)
	local pipeline = self.Cfg.IpoPipeline
	local q = Noise.Uni(self.Seed, CH_IPO, id, 0)
	local z = Noise.Gauss(self.Seed, CH_IPO + 1, id, 0)
	local pop =
		math.clamp(pipeline.PopBase + pipeline.PopQuality * q + pipeline.PopNoise * z, pipeline.Pop[1], pipeline.Pop[2])
	return q, pop
end

function EventDirector.IpoProspectNews(self: any, news: { Plain }, id: number, t: number, cond: string?)
	local slot = self.SlotById[id]
	local wrap = pushNews(news, t, "Ipo", self.NewsCfg.Ipo.Prospect, {
		name = slot.Name,
		sector = self.NewsCfg.Sectors[slot.Sector],
	}, { I = id, Sector = slot.Sector })
	wrap.Cond = cond
	wrap.Always = true -- Prospekt erscheint vor der Erstnotiz
end

-- Erstnotiz: 60-s-Auktion (Handelspause), danach Eröffnung = Ausgabepreis · (1 + pop)
function EventDirector.IpoListingPlan(self: any, news: { Plain }, msgs: { Msg }, id: number, t0: number, cond: string?)
	local slot = self.SlotById[id]
	local q, pop = self:IpoQuality(id)
	local issue = slot.Start
	local open = math.clamp(math.round(issue * (1 + pop)), self.Cfg.Price.MinCents, self.Cfg.Price.MaxCents)
	if self.Listings[id] == nil then
		self:AddListing(id, { T0 = t0, Issue = issue, Open = open, Pop = pop, Q = q, By = 0 })
	end
	local secs = self.Cfg.Halts.IpoSeconds
	table.insert(self.Halts, { All = false, I = id, From = t0, Until = t0 + secs, Cond = cond, Ext = false })
	local listingWrap = pushNews(news, t0, "Ipo", self.NewsCfg.Ipo.Listing, { name = slot.Name, secs = secs }, {
		I = id,
	})
	listingWrap.Cond = cond
	local band = bandFromMove(self, pop)
	local openWrap = pushNews(
		news,
		t0 + secs,
		"Ipo",
		if pop >= 0 then self.NewsCfg.Ipo.OpenUp else self.NewsCfg.Ipo.OpenDown,
		{ name = slot.Name, band = self.NewsCfg.Bands[band] },
		{ I = id, Band = band, Dir = sign(pop) }
	)
	openWrap.Cond = cond
	table.insert(msgs, { T = t0, Kind = "Ipo", Data = { I = id, Phase = "Listing", T0 = t0 }, Cond = cond })
	table.insert(msgs, { T = t0 + secs, Kind = "Ipo", Data = { I = id, Phase = "Open", T0 = t0 }, Cond = cond })
	table.insert(msgs, {
		T = t0,
		Kind = "Halt",
		Data = { I = id, Until = t0 + secs },
		Cond = cond,
	})
end

function EventDirector.EnsureBuilt(self: any, day: number, maxDays: number?): boolean
	local target = math.min(day, self.LastDay)
	local budget = maxDays or math.huge
	while self.Built < target and budget > 0 do
		self:BuildDay(self.Built + 1)
		budget -= 1
	end
	return self.Built >= target
end

-- ---------------------------------------------------------------------
-- BEDINGUNGEN (Samstags-Show abgesagt? geplantes IPO schon per Admin gelistet?)
-- ---------------------------------------------------------------------
-- Samstags-Show abgesagt? -> Tick, ab dem die Absage gilt (Start-Tick des CancelAutoShow-Bus-Events, auf allen Servern
-- gleich), −∞ = immer abgesagt (Selbsttest/IsCancelled), nil = findet statt.
function EventDirector.AutoShowCut(self: any): number?
	local fn = self.CancelAt
	if type(fn) == "function" then
		local ok, at = pcall(fn, self.Week)
		if ok and type(at) == "number" then
			return at
		end
		return nil
	end
	local legacy = self.IsCancelled
	if type(legacy) == "function" then
		local ok, cancelled = pcall(legacy, self.Week)
		if ok and cancelled == true then
			return -math.huge
		end
	end
	return nil
end

-- t (optional): Bedingung zu diesem Tick. Eine Show-Absage gilt erst ab ihrem Start-Tick (Warnphase davor bleibt
-- Geschichte: gleiche Kurse/Kerzen auf allen Servern, kein Rückwirken auf schon gesendete Ticks).
function EventDirector.CondOk(self: any, cond: string?, t: number?): boolean
	if cond == nil then
		return true
	end
	if cond == "AutoShow" then
		local cut = self:AutoShowCut()
		if cut == nil then
			return true
		end
		return t ~= nil and t < cut
	end
	local id, t0 = string.match(cond, "^IpoSched:(%d+):(%d+)$")
	if id and t0 then
		local rec = self.Listings[tonumber(id) :: number]
		return rec == nil or rec.T0 == tonumber(t0)
	end
	return true
end

-- ---------------------------------------------------------------------
-- AUSWERTUNG EINER WIRKUNG
-- ---------------------------------------------------------------------
local function rawEffect(self: any, e: Effect, t: number): number
	local value: number
	if t >= e.End then
		value = e.F
	else
		local x = t - e.T1
		if x < 0 then
			value = 0
		elseif e.Shape == SHAPE_NEWS then
			local tau = e.A
			if x <= tau then
				value = e.J * (1 + e.O) * smooth(x / tau)
			else
				value = e.J * (1 + e.O) - e.J * e.O * (1 - math.exp(-(x - tau) / e.B))
			end
		elseif e.Shape == SHAPE_RAMP then
			value = e.J * smooth(x / e.A)
		elseif e.Shape == SHAPE_CRASH then
			if x < e.A then
				value = e.J * smooth(x / e.A)
			else
				value = e.J - e.R * e.J * smooth((x - e.A) / e.B)
			end
		else -- SHAPE_BUMP
			if x < e.A then
				value = e.J * smooth(x / e.A)
			else
				value = e.J * (1 - smooth((x - e.A) / e.B))
			end
		end
	end
	local kill = e.Kill
	if kill and t >= kill then
		local fade = 1 - smooth((t - kill) / self.Cfg.Admin.NormalizeSeconds)
		value *= fade
	end
	return value
end

-- Beitrag einer Wirkung; Überträge aus der Vorwoche zählen relativ zum Wochenschluss (der steckt schon in der Basis)
local function evalEffect(self: any, e: Effect, t: number): number
	local value = rawEffect(self, e, t)
	local subAt = e.SubAt
	if subAt then
		value -= rawEffect(self, e, subAt)
	end
	return value
end

-- Summe aller Plan-Wirkungen + bedingte + Dividenden + externe; zweiter Wert: News-Rampe aktiv
function EventDirector.Offset(self: any, i: number, t: number, divFrom: number?): (number, boolean)
	local eff = self.Eff[i]
	if eff == nil then
		return 0, false
	end
	local s0s = self.EffS0[i]
	local pre = self.Pre[i]
	local n = upperBound(s0s, t)
	local k0 = upperBound(s0s, t - self.MaxSpan)
	local kOrigin = self.OriginK[i] or 0
	if k0 < kOrigin then
		k0 = kOrigin
	end
	local sum = (pre[k0] or 0) - (pre[kOrigin] or 0)
	local active = false
	for k = k0 + 1, n do
		local e = eff[k]
		if t >= e.End then
			sum += e.F -- abgeschlossen (Plan-Wirkungen haben weder Kill noch Sub)
		else
			sum += evalEffect(self, e, t)
			if e.News and t <= e.T1 + e.A then
				active = true
			end
		end
	end
	local slot = self.SlotById[i]
	local origin = if slot then slot.Origin else -math.huge
	sum += EventDirector.DriftOffset(self, i, t)
	local cond = self.CondEff[i]
	if #cond > 0 then
		for _, e in ipairs(cond) do
			if e.S0 <= t and e.S0 >= origin and self:CondOk(e.Cond, t) then
				sum += evalEffect(self, e, t)
				if t <= e.T1 + e.A then
					active = true
				end
			end
		end
	end
	local ext = self.Ext[i]
	if #ext > 0 then
		for _, e in ipairs(ext) do
			if e.S0 <= t and e.S0 >= origin then
				sum += evalEffect(self, e, t)
				if e.News and t <= e.T1 + e.A then
					active = true
				end
			end
		end
	end
	local divTicks = self.DivT[i]
	if #divTicks > 0 then
		local limit = if divFrom then math.min(t, divFrom - 1) else t
		local k = upperBound(divTicks, limit)
		if k > 0 then
			if k > self.DivDone[i] then
				EventDirector.ResolveDividends(self, i, k)
			end
			sum += self.DivCum[i][k]
		end
	end
	return sum, active
end

-- Dividenden-Beträge lazy und der Reihe nach: mid im Ex-Tick OHNE diese (und spätere) Dividende (keine Rekursion,
-- weil frühere Dividenden schon aufgelöst sind). Präfix-Summen der Log-Abschläge für schnelle Abfragen.
function EventDirector.ResolveDividends(self: any, i: number, upTo: number)
	local hook = self.PriceHook
	local list = self.Div[i]
	local cum = self.DivCum[i]
	local done = self.DivDone[i]
	for k = done + 1, math.min(upTo, #list) do
		local d = list[k]
		local mid = if hook then hook(i, d.Tick, d.Tick) else 0
		local cents = Dividends.PerShare(mid, d.Bps)
		d.LogF = Dividends.LogDrop(mid, cents)
		d.Cents = cents
		cum[k] = cum[k - 1] + d.LogF
		self.DivDone[i] = k
	end
end

function EventDirector.ResolveDividend(self: any, i: number, target: Plain): number
	local k = target.K or 0
	if k > self.DivDone[i] then
		EventDirector.ResolveDividends(self, i, k)
	end
	return target.LogF or 0
end

-- nach verspäteten Admin-Events: Dividenden-Beträge ab einem Tick neu rechnen
function EventDirector.InvalidateDividends(self: any, ids: { number }, fromTick: number)
	for _, i in ipairs(ids) do
		local ticks = self.DivT[i]
		if ticks then
			local keep = upperBound(ticks, fromTick - 1)
			if self.DivDone[i] > keep then
				self.DivDone[i] = keep
			end
			for k = keep + 1, #self.Div[i] do
				local d = self.Div[i][k]
				d.LogF = nil
				d.Cents = nil
			end
		end
	end
end

function EventDirector.Dividends(self: any, t0: number, t1: number): { Plain }
	local out: { Plain } = {}
	for _, slot in ipairs(self.SlotList) do
		local ticks = self.DivT[slot.Id]
		if ticks and #ticks > 0 then
			local first = upperBound(ticks, t0 - 1) + 1
			local last = upperBound(ticks, t1)
			if last >= first then
				if last > self.DivDone[slot.Id] then
					EventDirector.ResolveDividends(self, slot.Id, last)
				end
				for k = first, last do
					local d = self.Div[slot.Id][k]
					if (d.Cents or 0) > 0 and self:IsListed(slot.Id, d.Tick) then
						table.insert(out, { I = slot.Id, Tick = d.Tick, Cents = d.Cents })
					end
				end
			end
		end
	end
	table.sort(out, function(a: Plain, b: Plain)
		if a.Tick ~= b.Tick then
			return a.Tick < b.Tick
		end
		return a.I < b.I
	end)
	return out
end

-- Ex-Tag-Flag: an einem Börsentag mit Dividende, bis einschließlich Ex-Tick
function EventDirector.ExDay(self: any, i: number, t: number): boolean
	local ticks = self.DivT[i]
	if ticks == nil or #ticks == 0 then
		return false
	end
	local tick = ticks[upperBound(ticks, t - 1) + 1]
	return tick ~= nil and MarketClock.DayIndex(tick) == MarketClock.DayIndex(t)
end

-- ---------------------------------------------------------------------
-- VOLATILITÄT, PAUSEN, CRASH-FLAGS
-- ---------------------------------------------------------------------
local function evalVol(self: any, v: VolShape, t: number): number
	if t < v.S0 or t >= v.End then
		return 1
	end
	local value: number
	if v.Kind == 1 then
		value = v.V0 + (v.V1 - v.V0) * math.clamp((t - v.S0) / v.A, 0, 1)
	elseif v.Kind == 2 then
		local x = t - v.T1
		if x < 0 then
			value = v.V0
		elseif x < v.A then
			value = v.V0 + (v.Peak - v.V0) * smooth(x / v.A)
		else
			value = v.Peak + (v.V1 - v.Peak) * smooth((x - v.A) / v.B)
		end
	elseif v.Kind == 3 then
		local up = smooth((t - v.T1) / v.A)
		local down = 1 - smooth((t - (v.End - v.A)) / v.A)
		value = 1 + (v.Peak - 1) * math.min(up, down)
	else
		local x = t - v.T1
		if x < 0 then
			value = 1
		elseif x < v.A then
			value = 1 + (v.Peak - 1) * smooth(x / v.A)
		else
			value = v.Peak + (1 - v.Peak) * smooth((x - v.A) / v.B)
		end
	end
	local kill = v.Kill
	if kill and t >= kill then
		local fade = 1 - smooth((t - kill) / self.Cfg.Admin.NormalizeSeconds)
		value = 1 + (value - 1) * fade
	end
	return value
end

function EventDirector.VolMul(self: any, t: number): number
	local s0s = self.VolS0
	local n = upperBound(s0s, t)
	local k = upperBound(s0s, t - self.MaxVolSpan)
	local mul = 1
	for index = k + 1, n do
		local v = self.Vol[index]
		if t < v.End then
			local cut = if v.Cond == "AutoShow" then self:AutoShowCut() else nil
			if cut ~= nil and t >= cut then
				-- abgesagte Show: Warn-Volatilität über NormalizeSeconds ausblenden (kein Kurssprung)
				local fade = 1 - smooth((t - cut) / self.Cfg.Admin.NormalizeSeconds)
				if fade > 0 then
					mul *= 1 + (evalVol(self, v, t) - 1) * fade
				end
			elseif self:CondOk(v.Cond, t) then
				mul *= evalVol(self, v, t)
			end
		end
	end
	return mul
end

function EventDirector.Halted(self: any, i: number, t: number): (boolean, number)
	local halted, untilTick = false, 0
	for _, h in ipairs(self.Halts) do
		if t >= h.From and t < h.Until and (h.All or h.I == i) and self:CondOk(h.Cond, t) then
			halted = true
			if h.Until > untilTick then
				untilTick = h.Until
			end
		end
	end
	return halted, untilTick
end

function EventDirector.AnyHalt(self: any, t: number): { [string]: number }
	local out: { [string]: number } = {}
	for _, h in ipairs(self.Halts) do
		if t >= h.From and t < h.Until and self:CondOk(h.Cond, t) then
			local key = if h.All then "0" else tostring(h.I)
			if (out[key] or 0) < h.Until then
				out[key] = h.Until
			end
		end
	end
	return out
end

function EventDirector.AddLocalHalt(self: any, ids: { number }?, from: number, untilTick: number)
	if ids == nil then
		table.insert(self.Halts, { All = true, I = nil, From = from, Until = untilTick, Cond = nil, Ext = true })
		return
	end
	for _, i in ipairs(ids) do
		table.insert(self.Halts, { All = false, I = i, From = from, Until = untilTick, Cond = nil, Ext = true })
	end
end

function EventDirector.CrashRally(self: any, t: number): (boolean, boolean)
	local crash, rally = false, false
	for _, span in ipairs(self.CrashSpans) do
		if t >= span[1] and t < span[2] and self:CondOk(span[4] :: any, t) then
			if span[3] == 1 then
				crash = true
			else
				rally = true
			end
		end
	end
	return crash, rally
end

-- ---------------------------------------------------------------------
-- NEWS & NACHRICHTEN (nur Veröffentlichtes; nie Zukünftiges)
-- ---------------------------------------------------------------------
local function copyItem(item: Plain): Plain
	local out: Plain = table.clone(item)
	out.Args = table.clone(item.Args)
	return out
end

function EventDirector.Visible(self: any, wrap: Plain): boolean
	if not self:CondOk(wrap.Cond, wrap.Item.T) then
		return false
	end
	local item = wrap.Item
	if item.I and not wrap.Always and not self:IsListed(item.I, item.T) then
		return false
	end
	return true
end

function EventDirector.Finish(self: any, wrap: Plain): Plain
	local item = copyItem(wrap.Item)
	local divOf = wrap.DivOf
	if divOf then
		local cents = 0
		for _, d in ipairs(self.Div[divOf] or {}) do
			if d.Tick == item.T then
				if d.LogF == nil then
					self:ResolveDividend(divOf, d)
				end
				cents = d.Cents or 0
				break
			end
		end
		item.Args.amt = cents / 100
	end
	return item
end

function EventDirector.NewsIn(self: any, t0: number, t1: number): { NewsItem }
	local out: { NewsItem } = {}
	local times = self.NewsT
	local first = upperBound(times, t0) + 1
	for index = first, #times do
		local wrap = self.News[index]
		if wrap.Item.T > t1 then
			break
		end
		if self:Visible(wrap) then
			local finished = self:Finish(wrap)
			if not (finished.Kind == "Dividend" and (finished.Args.amt or 0) <= 0) then
				table.insert(out, finished :: any)
			end
		end
	end
	for _, wrap in ipairs(self.ExtNews) do
		local t = wrap.Item.T
		if t > t0 and t <= t1 then
			table.insert(out, copyItem(wrap.Item) :: any)
		end
	end
	table.sort(out, function(a: any, b: any)
		if a.T ~= b.T then
			return a.T < b.T
		end
		return a.Id < b.Id
	end)
	return out
end

function EventDirector.LatestNews(self: any, t: number, n: number): { NewsItem }
	local out: { NewsItem } = {}
	local times = self.NewsT
	local index = upperBound(times, t)
	local scanned = 0
	while index >= 1 and #out < n and scanned < 2000 do -- gebunden
		scanned += 1
		local wrap = self.News[index]
		if self:Visible(wrap) then
			local finished = self:Finish(wrap)
			if not (finished.Kind == "Dividend" and (finished.Args.amt or 0) <= 0) then
				table.insert(out, finished :: any)
			end
		end
		index -= 1
	end
	for _, wrap in ipairs(self.ExtNews) do
		if wrap.Item.T <= t then
			table.insert(out, copyItem(wrap.Item) :: any)
		end
	end
	table.sort(out, function(a: any, b: any)
		if a.T ~= b.T then
			return a.T > b.T
		end
		return a.Id > b.Id
	end)
	while #out > n do
		table.remove(out)
	end
	return out
end

local FACT_KINDS = { Fact = true, Confirm = true, Deny = true, Earnings = true }

function EventDirector.FactNewsFor(self: any, i: number, t: number, window: number): NewsItem?
	local times = self.NewsT
	local index = upperBound(times, t)
	local scanned = 0
	while index >= 1 and scanned < 4000 do -- gebunden
		scanned += 1
		local wrap = self.News[index]
		local item = wrap.Item
		if item.T < t - window then
			break
		end
		if item.I == i and FACT_KINDS[item.Kind] and item.Dir ~= nil and item.Dir ~= 0 and self:Visible(wrap) then
			return self:Finish(wrap) :: any
		end
		index -= 1
	end
	return nil
end

function EventDirector.MessagesAt(self: any, t: number): { Plain }
	local out: { Plain } = {}
	local times = self.MsgT
	local index = upperBound(times, t - 1) + 1
	while index <= #times and times[index] == t do
		local m = self.Msgs[index]
		if self:CondOk(m.Cond, t) then
			table.insert(out, { Kind = m.Kind, Data = m.Data })
		end
		index += 1
	end
	for _, m in ipairs(self.ExtMsgs) do
		if m.T == t then
			table.insert(out, { Kind = m.Kind, Data = m.Data })
		elseif m.T > t then
			break
		end
	end
	return out
end

-- ---------------------------------------------------------------------
-- KALENDER (nur geplante Arten; Firmen-News/Gerüchte/Crashs ohne Termin erscheinen NIE vorab)
-- ---------------------------------------------------------------------
function EventDirector.Calendar(self: any, t0: number, t1: number): { CalendarItem }
	local out: { CalendarItem } = {}
	local first = math.max(MarketClock.DayIndex(t0), self.FirstDay)
	local last = math.min(MarketClock.DayIndex(t1), self.LastDay)
	for day = first, last do
		for _, e in ipairs(self:EarningsFor(day)) do
			if e.T >= t0 and e.T <= t1 and self:IsListed(e.I, e.T) then
				table.insert(out, { T = e.T, Kind = "Earnings", I = e.I, Key = "mkt.cal.Earnings" })
				local slot = self.SlotById[e.I]
				local exTick = Dividends.ExTick(e.I, day, slot.DivBps, self.Cfg)
				if exTick and exTick >= t0 and exTick <= t1 then
					table.insert(out, { T = exTick, Kind = "Dividend", I = e.I, Key = "mkt.cal.Dividend" })
				end
			end
		end
		local tMacro = MarketClock.DayStart(day) + self.Cfg.Macro.Minute * 60
		if tMacro >= t0 and tMacro <= t1 then
			table.insert(out, { T = tMacro, Kind = "Macro", Key = "mkt.cal.Macro." .. self:MacroKind(day) })
		end
	end
	table.sort(out, function(a: CalendarItem, b: CalendarItem)
		if a.T ~= b.T then
			return a.T < b.T
		end
		return (a.I or 0) < (b.I or 0)
	end)
	return out
end

-- ---------------------------------------------------------------------
-- FIRMENPROFIL (Fundamentaldaten aus q + Quartalen dieser Woche; Analysten-Trefferquote live gemessen)
-- ---------------------------------------------------------------------
function EventDirector.AnalystStats(self: any, now: number): { { number } }
	local window = self.Cfg.AnalystWindow
	local count = #self.Cfg.Analysts
	local hits: { { number } } = {}
	for a = 1, count do
		hits[a] = { 0, 0 }
	end
	local day = math.min(MarketClock.DayIndex(now), self.Built)
	local remaining = count
	local scanned = 0
	while day >= self.FirstDay and remaining > 0 and scanned < MarketClock.DAYS_PER_WEEK do
		scanned += 1
		local list = self:EarningsFor(day)
		for index = #list, 1, -1 do
			local e = list[index]
			if e.T <= now then
				local actual = sign(e.J)
				for _, v in ipairs(e.Verdicts) do
					local h = hits[v[1]]
					if h[2] < window then
						h[2] += 1
						if v[2] == actual then
							h[1] += 1
						end
						if h[2] == window then
							remaining -= 1
						end
					end
				end
			end
		end
		day -= 1
	end
	return hits
end

function EventDirector.Profile(self: any, i: number, now: number, leadSeconds: number): Plain?
	local slot = self.SlotById[i]
	if not slot then
		return nil
	end
	local cfg = self.Cfg
	local fund = cfg.Fundamentals
	local q = self.Q[i] or 0
	local revenue0 = fund.Revenue[1] + (fund.Revenue[2] - fund.Revenue[1]) * Noise.Rnd(CH_FUND, i, 0, 0)
	local pe0 = fund.Pe[slot.Class] or fund.Pe.Normal
	local eps = slot.Start / pe0 -- Cent je Aktie (negativ = Verlust)
	local growth: { number } = {}
	-- vier synthetische Vor-Quartale (aus dem Seed) + die Quartale dieser Woche bis jetzt
	for m = 4, 1, -1 do
		local s = cfg.Earnings.SurpriseQ * q + cfg.Earnings.SurpriseZ * Noise.Gauss(self.Seed, CH_EARN_PRE, i, m)
		table.insert(growth, fund.GrowthBase + fund.GrowthQ * q + fund.GrowthS * s)
		eps += math.abs(eps) * fund.EpsS * s
	end
	local nextEarnings: Plain? = nil
	local day = self.FirstDay
	local lastDay = math.min(MarketClock.DayIndex(now) + 3, self.LastDay)
	while day <= lastDay do
		for _, e in ipairs(self:EarningsFor(day)) do
			if e.I == i then
				if e.T <= now then
					table.insert(growth, fund.GrowthBase + fund.GrowthQ * q + fund.GrowthS * e.S)
					eps += math.abs(eps) * fund.EpsS * e.S
				elseif nextEarnings == nil then
					nextEarnings = e
				end
			end
		end
		day += 1
	end
	while #growth > 4 do
		table.remove(growth, 1)
	end
	local revenue = revenue0
	for _, g in ipairs(growth) do
		revenue *= 1 + g
	end
	local stats = self:AnalystStats(now)
	local analysts: { Plain } = {}
	local verdictOf: { [number]: number } = {}
	local consensus: string? = nil
	if nextEarnings then
		if now >= nextEarnings.T - leadSeconds then
			for _, v in ipairs(nextEarnings.Verdicts) do
				verdictOf[v[1]] = v[2]
			end
		end
		if now >= nextEarnings.T - cfg.Earnings.PreviewMinutes * 60 then
			consensus = nextEarnings.Cons
		end
	end
	for index, analyst in ipairs(cfg.Analysts) do
		table.insert(analysts, {
			Name = analyst.Name,
			Hits = stats[index][1],
			N = stats[index][2],
			Verdict = verdictOf[index] or 0,
		})
	end
	local nextDividend = 0
	if slot.DivBps > 0 and nextEarnings then
		nextDividend = MarketClock.DayStart(MarketClock.DayIndex(nextEarnings.T)) + cfg.Dividend.Minute * 60
	end
	local profile: Plain = {
		I = i,
		Revenue = math.round(revenue * 10) / 10,
		Growth = growth,
		Eps = math.round(eps),
		DivBps = slot.DivBps,
		NextEarnings = if nextEarnings then { T = nextEarnings.T, Minute = nextEarnings.Minute } else nil,
		NextDividend = nextDividend,
		Consensus = consensus,
		Analysts = analysts,
	}
	if slot.Ipo then
		local rec = self.Listings[i]
		local ipoQ = self:IpoQuality(i) -- Prospekt-Qualität aus dem Wochen-Seed (Skill: korreliert mit dem pop)
		profile.Issue = slot.Start
		profile.Listing = if rec then rec.T0 else nil
		profile.Quality = if ipoQ > 0.33
			then "mkt.profile.quality.good"
			elseif ipoQ < -0.33 then "mkt.profile.quality.weak"
			else "mkt.profile.quality.mid"
	end
	return profile
end

-- ---------------------------------------------------------------------
-- EXTERNE EVENTS (GlobalBus; Felder sind bereits validiert und geklemmt)
-- ev: { Id, Kind, Scope, Target, Strength, Ramp, Decay, StartTick, Until, Text, By, Warn?, Band?, Dir? }
-- carry = true: Event aus der Vorwoche, das in diese Woche hineinreicht (Beitrag relativ zum Wochenschluss)
-- ---------------------------------------------------------------------
function EventDirector.Targets(self: any, ev: Plain, at: number): { number }
	local out: { number } = {}
	for _, slot in ipairs(self.SlotList) do
		local hit = false
		if ev.Scope == "All" then
			hit = true
		elseif ev.Scope == "Sector" then
			hit = slot.Sector == ev.Target
		elseif ev.Scope == "Inst" then
			hit = slot.Id == ev.Target
		end
		if hit and self:IsListed(slot.Id, at) then
			table.insert(out, slot.Id)
		end
	end
	return out
end

local function insertSorted(list: { Effect }, e: Effect)
	local index = #list + 1
	while index > 1 and list[index - 1].S0 > e.S0 do
		index -= 1
	end
	table.insert(list, index, e)
end

function EventDirector.InsertVol(self: any, v: VolShape)
	local index = upperBound(self.VolS0, v.S0) + 1
	table.insert(self.Vol, index, v)
	table.insert(self.VolS0, index, v.S0)
end

function EventDirector.AddExtNews(
	self: any,
	t: number,
	kind: string,
	key: string,
	args: Plain,
	extra: Plain?,
	idSalt: number
)
	local item: Plain = { Id = 2 ^ 40 + t * 16 + (idSalt % 16), T = t, Kind = kind, Key = key, Args = args }
	if extra then
		for k, v in pairs(extra) do
			item[k] = v
		end
	end
	local index = #self.ExtNews + 1
	while index > 1 and self.ExtNews[index - 1].Item.T > t do
		index -= 1
	end
	table.insert(self.ExtNews, index, { Item = item })
end

function EventDirector.AddExternal(self: any, ev: Plain, carry: boolean?): { number }
	local cfg = self.Cfg
	local admin = cfg.Admin
	local newsCfg = self.NewsCfg
	local kind = ev.Kind
	local start = ev.StartTick
	local salt = (self.ExtSalt or 0) + 1
	self.ExtSalt = salt
	local affected: { number } = {}
	local untilTick = ev.Until

	local function window(to: number)
		table.insert(self.WindowList, { start - admin.Lead, to + admin.WindowAfter })
	end

	local function haltAll(ids: { number }, secs: number)
		if ev.Scope == "All" then
			table.insert(
				self.Halts,
				{ All = true, I = nil, From = start, Until = start + secs, Cond = nil, Ext = true }
			)
		else
			for _, i in ipairs(ids) do
				table.insert(
					self.Halts,
					{ All = false, I = i, From = start, Until = start + secs, Cond = nil, Ext = true }
				)
			end
		end
	end

	if kind == "Crash" or kind == "Rally" or kind == "Pump" or kind == "Dump" then
		local down = kind == "Crash" or kind == "Dump"
		local strength = math.clamp(ev.Strength, admin.Strength[1], admin.Strength[2])
		local j = if down then math.log(1 - strength) else math.log(1 + strength)
		local warn = math.max(0, ev.Warn or 0)
		local t1 = start + warn
		affected = self:Targets(ev, start)
		for _, i in ipairs(affected) do
			local e = newEffect(start, t1, SHAPE_BUMP, j, ev.Ramp, ev.Decay)
			e.F = 0
			e.News = true
			e.Val = false
			if carry then
				e.SubAt = self.WeekStart - 1
				e.S0 = self.WeekStart
			end
			insertSorted(self.Ext[i], e)
		end
		if not carry then
			self:InsertVol({
				S0 = start,
				T1 = t1,
				End = t1 + ev.Ramp + ev.Decay,
				Kind = 4,
				A = ev.Ramp,
				B = ev.Decay,
				V0 = 1,
				V1 = 1,
				Peak = admin.PeakRegime,
				Cond = nil,
				Kill = nil,
			})
			table.insert(self.CrashSpans, { start, t1 + ev.Ramp + ev.Decay, if down then 1 else 2 })
			haltAll(affected, cfg.Halts.AdminSeconds)
			local key = newsCfg.AdminMove[kind]
			local name = if ev.Scope == "Inst" then self:NewsArgsName(ev.Target) else nil
			self:AddExtNews(start, "Admin", key, { name = name }, {
				I = if ev.Scope == "Inst" then ev.Target else nil,
				Sector = if ev.Scope == "Sector" then ev.Target else nil,
				Dir = if down then -1 else 1,
			}, salt)
			local base: Plain = {
				Kind = kind,
				StartTick = start,
				Until = untilTick,
				Scope = ev.Scope,
				Target = ev.Target,
				Admin = true,
			}
			local function msg(t: number, phase: string)
				local d: Plain = { Phase = phase }
				for k, v in pairs(base) do
					d[k] = v
				end
				self:InsertMsg({ T = t, Kind = "Event", Data = d }, true)
			end
			msg(t1, "Run")
			msg(t1 + ev.Ramp + ev.Decay, "End")
			window(t1 + ev.Ramp + ev.Decay)
		end
	elseif kind == "News" then
		affected = self:Targets(ev, start)
		local band = math.clamp(math.floor(ev.Band or 2), 1, 4)
		local dir = if (ev.Dir or 1) < 0 then -1 else 1
		local bandCfg = cfg.Bands[band]
		local mid = (bandCfg.Lo + bandCfg.Hi) / 2
		local t1 = start + self.Delay
		for _, i in ipairs(affected) do
			local slot = self.SlotById[i]
			local j = dir * mid * classOf(self, slot, start).NewsFactor
			local e = newEffect(start, t1, SHAPE_BUMP, j, self.Tau, admin.NewsDecay)
			e.F = 0
			e.Val = false
			if carry then
				e.SubAt = self.WeekStart - 1
				e.S0 = self.WeekStart
			end
			insertSorted(self.Ext[i], e)
		end
		if not carry then
			haltAll(affected, cfg.Halts.AdminSeconds)
			self:AddExtNews(start, "Admin", newsCfg.Admin, {}, {
				I = if ev.Scope == "Inst" then ev.Target else nil,
				Sector = if ev.Scope == "Sector" then ev.Target else nil,
				Band = band,
				Dir = dir,
				Text = ev.Text,
			}, salt)
			window(t1 + self.Tau + admin.NewsDecay)
		end
	elseif kind == "Vol" then
		if not carry then
			local mult = math.clamp(ev.Strength, admin.Vol[1], admin.Vol[2])
			self:InsertVol({
				S0 = start,
				T1 = start,
				End = untilTick,
				Kind = 3,
				A = admin.VolRamp,
				B = 0,
				V0 = 1,
				V1 = 1,
				Peak = mult,
				Cond = nil,
				Kill = nil,
			})
			self:AddExtNews(start, "Admin", newsCfg.AdminMove.Vol, {}, { Dir = if mult >= 1 then -1 else 1 }, salt)
			self:InsertMsg({
				T = start,
				Kind = "Event",
				Data = { Kind = "Vol", Phase = "Run", StartTick = start, Until = untilTick, Admin = true },
			}, true)
			self:InsertMsg({
				T = untilTick,
				Kind = "Event",
				Data = { Kind = "Vol", Phase = "End", StartTick = start, Until = untilTick, Admin = true },
			}, true)
			window(untilTick)
		end
	elseif kind == "Halt" then
		-- Pause gilt auch über den Wochenwechsel weiter (Übertrag ohne neue Schlagzeile)
		if ev.Scope == "Inst" then
			affected = { ev.Target }
			table.insert(self.Halts, { All = false, I = ev.Target, From = start, Until = untilTick, Ext = true })
		else
			table.insert(self.Halts, { All = true, I = nil, From = start, Until = untilTick, Ext = true })
		end
		if not carry then
			local secs = untilTick - start
			if ev.Scope == "Inst" then
				self:AddExtNews(start, "Halt", newsCfg.Halt.Inst, {
					name = self:NewsArgsName(ev.Target),
					secs = secs,
				}, { I = ev.Target }, salt)
			else
				self:AddExtNews(start, "Halt", newsCfg.Halt.All, { secs = secs }, nil, salt)
			end
			self:InsertMsg({
				T = start,
				Kind = "Halt",
				Data = { I = if ev.Scope == "Inst" then ev.Target else nil, Until = untilTick },
			}, true)
			window(untilTick)
		end
	elseif kind == "Resume" then
		if not carry then
			for _, h in ipairs(self.Halts) do
				if h.Ext and h.From <= start and h.Until > start then
					if ev.Scope ~= "Inst" or h.I == ev.Target then
						h.Until = start
					end
				end
			end
			if ev.Scope == "Inst" then
				self:AddExtNews(start, "Resume", newsCfg.Resume.Inst, {
					name = self:NewsArgsName(ev.Target),
				}, { I = ev.Target }, salt)
			else
				self:AddExtNews(start, "Resume", newsCfg.Resume.All, {}, nil, salt)
			end
			self:InsertMsg({
				T = start,
				Kind = "Halt",
				Data = { I = if ev.Scope == "Inst" then ev.Target else nil, Until = start },
			}, true)
		end
	elseif kind == "Normalize" then
		for _, slot in ipairs(self.SlotList) do
			for _, e in ipairs(self.Ext[slot.Id]) do
				if e.Start0 < start and e.End > start and (e.Kill == nil or e.Kill > start) then
					e.Kill = start
					table.insert(affected, slot.Id)
				end
			end
		end
		for _, v in ipairs(self.Vol) do
			if v.Kind >= 3 and v.S0 < start and v.End > start and (v.Kill == nil or v.Kill > start) then
				v.Kill = start
			end
		end
		if not carry then
			self:AddExtNews(start, "Admin", newsCfg.AdminMove.Normalize, {}, { Dir = 1 }, salt)
			self:InsertMsg({
				T = start,
				Kind = "Event",
				Data = {
					Kind = "Normalize",
					Phase = "Run",
					StartTick = start,
					Until = start + admin.NormalizeSeconds,
					Admin = true,
				},
			}, true)
			window(start + admin.NormalizeSeconds)
		end
	elseif kind == "Ipo" then
		local id = ev.Target
		if type(id) == "number" and self.SlotById[id] and self.Listings[id] == nil and not carry then
			local t0 = untilTick
			local news: { Plain } = {}
			local msgs: { Msg } = {}
			self:IpoProspectNews(news, id, start, nil)
			self:IpoListingPlan(news, msgs, id, t0, nil)
			local rec = self.Listings[id]
			if rec then
				rec.By = ev.By or 0
			end
			for _, wrap in ipairs(news) do
				local item = wrap.Item
				self:AddExtNews(item.T, item.Kind, item.Key, item.Args, {
					I = item.I,
					Band = item.Band,
					Dir = item.Dir,
					Sector = item.Sector,
				}, salt)
			end
			for _, m in ipairs(msgs) do
				self:InsertMsg(m, true)
			end
			self:InsertMsg({ T = start, Kind = "Ipo", Data = { I = id, Phase = "Prospect", T0 = t0 } }, true)
			affected = { id }
			window(t0 + cfg.Halts.IpoSeconds)
		end
	end
	return affected
end

function EventDirector.Windows(self: any): { { number } }
	return self.WindowList
end

return EventDirector
