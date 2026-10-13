--!strict
-- =====================================================================
--  AKYTEX TYCOON – Technische Indikatoren (Shared/Market/Indicators)
--  Besitzer: WP4 (Orders, Depot, Bots). Vertrag: DESIGN.md §C6.2, §B7.5, REUSE §5.2.
--  1:1-Port von js/indicators.js der AKYTEX-Website (gleiche Formeln, gleiche Warm-up-Regeln, gleiche Eigenheiten –
--  z. B. EMA-Start über den Index, ATR-Startsumme durch n), damit Client-Chart (WP5), Server-Bots (BotEngine) und
--  Tests exakt dieselben Werte sehen. Rein: lädt nichts -> mit der Luau-CLI testbar (tests/indicators.test.luau).
--
--  Ausgabe immer GLEICH LANG wie die Eingabe; Werte vor dem Warm-up sind nil (Liste mit Lücken -> mit
--  "for i = 1, #eingabe" lesen, nie mit ipairs/#ausgabe).
--
--  Öffentliche API (§C6.2):
--    Indicators.SMA(v, n): { number? }
--    Indicators.EMA(v, n): { number? }                         k = 2/(n+1), Start = SMA der ersten n Werte; nil wird übersprungen
--    Indicators.Bollinger(v, n?, mult?): { Mid, Upper, Lower }  Std 20 / 2 (Populations-Std wie die Website)
--    Indicators.RSI(v, n?): { number? }                         Std 14 (Wilder-Glättung)
--    Indicators.MACD(v, fast?, slow?, sig?): { Line, Signal, Hist }   Std 12 / 26 / 9
--    Indicators.VWAP(candles, period?): { number? }             je Periode zurückgesetzt (Std 1200 Ticks = 1 Börsentag)
--    Indicators.ATR(candles, n?): { number? }                   Std 14
--    Indicators.Stoch(candles, k?, d?): { K, D }                Std 14 / 3
--    Indicators.HeikinAshi(candles): { Candle }
--  candles = { { T, O, H, L, C, V } } (Types.Candle; Cent, Volumen in 10er-Lots).
-- =====================================================================

local Indicators = {}

export type Candle = { T: number, O: number, H: number, L: number, C: number, V: number }
export type Series = { number? }

local VWAP_PERIOD = 1200 -- "täglich" im Spiel = ein Börsentag (Website: 86.400 s echte Tage)

local function count(n: any, fallback: number): number
	if type(n) == "number" and n == n and n >= 1 and n < math.huge then
		return math.floor(n)
	end
	return fallback
end

local function num(v: any): number
	-- wie JavaScript: null/undefined zählen in Summen als 0
	return if type(v) == "number" and v == v then v else 0
end

-- ---------------------------------------------------------------------
-- Gleitende Durchschnitte
-- ---------------------------------------------------------------------
function Indicators.SMA(v: { number }, n: number): Series
	local len = #v
	local out: Series = table.create(len)
	local w = count(n, 1)
	local sum = 0
	for i = 1, len do
		sum += num(v[i])
		if i > w then
			sum -= num(v[i - w])
		end
		if i >= w then
			out[i] = sum / w
		end
	end
	return out
end

-- v darf nil-Lücken enthalten (MACD-Signal); der Start-Index zählt wie im Original über die Position
function Indicators.EMA(v: { number? }, n: number): Series
	local len = #v
	local out: Series = table.create(len)
	local w = count(n, 1)
	local k = 2 / (w + 1)
	local prev: number? = nil
	local sum = 0
	for i = 1, len do
		local value = v[i]
		if type(value) ~= "number" then
			continue
		end
		if prev == nil then
			sum += value
			if i >= w then
				prev = sum / w
				out[i] = prev
			end
			continue
		end
		local nextValue = value * k + (prev :: number) * (1 - k)
		prev = nextValue
		out[i] = nextValue
	end
	return out
end

-- Längen-Ermittlung für Listen mit nil-Lücken (MACD-Linie): höchster belegter Index
local function seriesLength(v: { number? }, hint: number): number
	return math.max(hint, #v)
end

function Indicators.Bollinger(v: { number }, n: number?, mult: number?): { Mid: Series, Upper: Series, Lower: Series }
	local w = count(n, 20)
	local m = if type(mult) == "number" and mult == mult then mult else 2
	local len = #v
	local mid = Indicators.SMA(v, w)
	local upper: Series = table.create(len)
	local lower: Series = table.create(len)
	for i = w, len do
		local center = mid[i] :: number
		local s = 0
		for j = i - w + 1, i do
			s += (num(v[j]) - center) ^ 2
		end
		local sd = math.sqrt(s / w)
		upper[i] = center + m * sd
		lower[i] = center - m * sd
	end
	return { Mid = mid, Upper = upper, Lower = lower }
end

function Indicators.RSI(v: { number }, n: number?): Series
	local w = count(n, 14)
	local len = #v
	local out: Series = table.create(len)
	local gain, loss = 0, 0
	-- JS-Index i = 1 … len−1  ->  Luau-Index i + 1
	for i = 1, len - 1 do
		local d = num(v[i + 1]) - num(v[i])
		local g = math.max(d, 0)
		local l = math.max(-d, 0)
		if i <= w then
			gain += g / w
			loss += l / w
			if i == w then
				out[i + 1] = if loss == 0 then 100 else 100 - 100 / (1 + gain / loss)
			end
		else
			gain = (gain * (w - 1) + g) / w
			loss = (loss * (w - 1) + l) / w
			out[i + 1] = if loss == 0 then 100 else 100 - 100 / (1 + gain / loss)
		end
	end
	return out
end

function Indicators.MACD(
	v: { number },
	fast: number?,
	slow: number?,
	sig: number?
): { Line: Series, Signal: Series, Hist: Series }
	local len = #v
	local f = Indicators.EMA(v, count(fast, 12))
	local s = Indicators.EMA(v, count(slow, 26))
	local line: Series = table.create(len)
	for i = 1, len do
		local a, b = f[i], s[i]
		if a ~= nil and b ~= nil then
			line[i] = a - b
		end
	end
	-- EMA über eine Liste mit Lücken: Länge explizit auf len halten
	local signal: Series = table.create(len)
	do
		local w = count(sig, 9)
		local k = 2 / (w + 1)
		local prev: number? = nil
		local sum = 0
		for i = 1, seriesLength(line, len) do
			local value = line[i]
			if value == nil then
				continue
			end
			if prev == nil then
				sum += value
				if i >= w then
					prev = sum / w
					signal[i] = prev
				end
				continue
			end
			local nextValue = value * k + (prev :: number) * (1 - k)
			prev = nextValue
			signal[i] = nextValue
		end
	end
	local hist: Series = table.create(len)
	for i = 1, len do
		local a, b = line[i], signal[i]
		if a ~= nil and b ~= nil then
			hist[i] = a - b
		end
	end
	return { Line = line, Signal = signal, Hist = hist }
end

-- ---------------------------------------------------------------------
-- Kerzen-Indikatoren
-- ---------------------------------------------------------------------
local function smoothNullable(values: Series, len: number, n: number): Series
	local out: Series = table.create(len)
	for i = n, len do
		local s = 0
		local ok = true
		for j = i - n + 1, i do
			local value = values[j]
			if value == nil then
				ok = false
				break
			end
			s += value
		end
		if ok then
			out[i] = s / n
		end
	end
	return out
end

function Indicators.Stoch(candles: { Candle }, k: number?, d: number?): { K: Series, D: Series }
	local len = #candles
	local n = count(k, 14)
	local smooth = count(d, 3)
	local raw: Series = table.create(len)
	for i = n, len do
		local hi, lo = -math.huge, math.huge
		for j = i - n + 1, i do
			local bar = candles[j]
			if bar.H > hi then
				hi = bar.H
			end
			if bar.L < lo then
				lo = bar.L
			end
		end
		raw[i] = if hi == lo then 50 else ((candles[i].C - lo) / (hi - lo)) * 100
	end
	local kk = smoothNullable(raw, len, smooth)
	return { K = kk, D = smoothNullable(kk, len, smooth) }
end

function Indicators.ATR(candles: { Candle }, n: number?): Series
	local len = #candles
	local w = count(n, 14)
	local out: Series = table.create(len)
	local prev: number? = nil
	-- JS-Index i = 1 … len−1 (Luau i + 1); Startsumme über i < n, geteilt durch n (Eigenheit des Originals)
	for i = 1, len - 1 do
		local bar = candles[i + 1]
		local pc = candles[i].C
		local tr = math.max(bar.H - bar.L, math.abs(bar.H - pc), math.abs(bar.L - pc))
		if i < w then
			prev = (prev or 0) + tr / w
			if i == w - 1 then
				out[i + 1] = prev
			end
		else
			local nextValue = ((prev or 0) * (w - 1) + tr) / w
			prev = nextValue
			out[i + 1] = nextValue
		end
	end
	return out
end

function Indicators.VWAP(candles: { Candle }, period: number?): Series
	local len = #candles
	local span = count(period, VWAP_PERIOD)
	local out: Series = table.create(len)
	local day: number? = nil
	local pv, vol = 0, 0
	for i = 1, len do
		local bar = candles[i]
		local d = math.floor(num(bar.T) / span)
		if d ~= day then
			day = d
			pv, vol = 0, 0
		end
		local tp = (bar.H + bar.L + bar.C) / 3
		pv += tp * num(bar.V)
		vol += num(bar.V)
		out[i] = if vol ~= 0 then pv / vol else tp
	end
	return out
end

function Indicators.HeikinAshi(candles: { Candle }): { Candle }
	local out: { Candle } = table.create(#candles)
	for i, bar in ipairs(candles) do
		local close = (bar.O + bar.H + bar.L + bar.C) / 4
		local open = if i == 1 then (bar.O + bar.C) / 2 else (out[i - 1].O + out[i - 1].C) / 2
		out[i] = {
			T = bar.T,
			O = open,
			C = close,
			H = math.max(bar.H, open, close),
			L = math.min(bar.L, open, close),
			V = bar.V,
		}
	end
	return out
end

return Indicators
