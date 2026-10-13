-- =====================================================================
--  AKYTEX TYCOON – Offline-Abgleich: Orders 24 h, Bots 12 h, Dividenden, Alarme, Auto-Transfers
--  (Server/Market/CatchUp)
--  Besitzer: WP4 (Orders, Depot, Bots). Vertrag: DESIGN.md §B8.2 (Auto-Transfer je verpasstem Börsentag, max. 72),
--  §B8.5 (Bots offline 12 h), §C16 (Offline-Abgleich im Hintergrund), MARKET.md §11.5.
--
--  Prinzip: dieselbe Funktion wie online (OrderEngine.Step je Tick) über den verpassten Zeitraum, chronologisch.
--  Ganze Minuten, in denen keine Order und kein Alarm eines Werts auslösen KANN (OrderEngine.CanTrigger mit dem
--  exakten Minuten-Hoch/-Tief und dem halben Spread der Minute), werden übersprungen – Nachzieh-Stopps werden dann
--  mit dem Minuten-Hoch nachgeführt (identisch zu 60 Einzel-Kerzen ohne Auslösung). Bots, Börsentag-Schluss und
--  Dividenden laufen an ihren exakten Ticks. Ergebnis: dieselben Fills wie online (Abnahme WP4 #4).
--  Kerzen kommen sequentiell aus Cursors (MarketService.NewCursor); Minuten-Hoch/-Tief sicher abgeschlossener
--  Minuten werden server-weit gecacht (für alle Spieler gemeinsam).
--
--  Öffentliche API:
--    CatchUp.Run(d, env, toTick, opts): Report        yieldet über opts.Yield (Budget opts.BudgetMs je Scheibe)
--      opts = { Cursor = (i, t0) -> cursor?, Candle = ((i, t) -> (o, h, l, c)?)?, Yield = (() -> ())?,
--               BudgetMs = number?, Now = (() -> number)?, Target = (() -> number)?, Abort = (() -> boolean)? }
--      Target (optional) liefert während des Abgleichs immer wieder den aktuellen Markt-Tick: der Abgleich läuft,
--      bis d.LastTick == Target() ist (ohne Yield zwischen letzter Prüfung und Rückkehr).
--    Report = { Fills, Dividends, Alerts, Expired, Transfers, Days, Bots = { { Preset, Pct } }, Jumped: boolean,
--               Ticks: number, Aborted: boolean }
--    CatchUp.Window(d, toTick): (from, winEnd, botsUntil)   Zeitfenster laut Config.Trading (24 h / 12 h)
--    CatchUp.ClearCache()
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Clock = require(Shared:WaitForChild("Clock"))
local Portfolio = require(script.Parent:WaitForChild("Portfolio"))
local OrderEngine = require(script.Parent:WaitForChild("OrderEngine"))
local BotEngine = require(script.Parent:WaitForChild("BotEngine"))

local CatchUp = {}

type Depot = { [string]: any }
type Env = OrderEngine.Env
type Candle = { number } -- { o, h, l, c }
export type Report = {
	Fills: number,
	Dividends: number,
	Alerts: number,
	Expired: number,
	Transfers: number,
	Days: number,
	Bots: { { Preset: string, Pct: number } },
	Jumped: boolean,
	Ticks: number,
	Aborted: boolean,
}

local DAY = Clock.DAY_TICKS
local MINUTE_CACHE_MAX = 60000
local MAX_ROUNDS = 50 -- Target-Nachlauf: höchstens so oft neu ansetzen (danach läuft der Rest live nach)
local ABORT = "CatchUpAbort" -- Abbruch-Kennung (Spieler hat das Spiel verlassen)

local minuteCache: { [number]: { [number]: { number } } } = {} -- [inst][minute] = { hMax, lMin }
local minuteCount = 0

local function trading(): { [string]: any }
	local t = Config.Trading
	return if type(t) == "table" then t else {}
end

local function num(v: any, fallback: number): number
	if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then
		return v
	end
	return fallback
end

function CatchUp.ClearCache()
	table.clear(minuteCache)
	minuteCount = 0
end

function CatchUp.Window(d: Depot, toTick: number): (number, number, number)
	local cfg = trading()
	local last = math.floor(num(d.LastTick, 0))
	local from = last + 1
	local winEnd = math.min(toTick, last + math.floor(num(cfg.OfflineOrderHours, 24) * 3600))
	local botsUntil = math.min(toTick, last + math.floor(num(cfg.OfflineBotHours, 12) * 3600))
	return from, winEnd, botsUntil
end

-- ---------------------------------------------------------------------
-- Kerzen-Quelle: je Wert ein Cursor (sequentiell billig), Seek nur bei Sprüngen
-- ---------------------------------------------------------------------
type Source = {
	Cursors: { [number]: any },
	Pos: { [number]: number },
	Opts: { [string]: any },
}

local function candleAt(src: Source, i: number, t: number): (number?, number?, number?, number?)
	local cur = src.Cursors[i]
	if cur == nil and src.Opts.Cursor then
		local ok, made = pcall(src.Opts.Cursor, i, t)
		if ok and made then
			cur = made
			src.Cursors[i] = made
			src.Pos[i] = t
		else
			src.Cursors[i] = false
			cur = false
		end
	end
	if cur then
		if src.Pos[i] ~= t then
			local okSeek = pcall(function()
				cur:Seek(t)
			end)
			if not okSeek then
				return nil, nil, nil, nil
			end
		end
		local ok, o, h, l, c = pcall(function()
			return cur:Candle(t)
		end)
		src.Pos[i] = t + 1
		if ok and type(o) == "number" then
			return o, h, l, c
		end
		return nil, nil, nil, nil
	end
	if src.Opts.Candle then
		local ok, o, h, l, c = pcall(src.Opts.Candle, i, t)
		if ok and type(o) == "number" then
			return o, h, l, c
		end
	end
	return nil, nil, nil, nil
end

-- Kerzen der Ticks a … b (eine Minute oder ein Teil davon) + Hoch/Tief
local function loadCandles(src: Source, i: number, a: number, b: number): ({ Candle? }, number, number)
	local list: { Candle? } = {}
	local hMax, lMin = -math.huge, math.huge
	for t = a, b do
		local o, h, l, c = candleAt(src, i, t)
		if type(o) == "number" and type(h) == "number" and type(l) == "number" and type(c) == "number" then
			list[t - a + 1] = { o, h, l, c }
			if h > hMax then
				hMax = h
			end
			if l < lMin then
				lMin = l
			end
		end
	end
	return list, hMax, lMin
end

local function cacheMinute(i: number, minute: number, hMax: number, lMin: number)
	if minuteCount >= MINUTE_CACHE_MAX then
		CatchUp.ClearCache()
	end
	local perInst = minuteCache[i]
	if not perInst then
		perInst = {}
		minuteCache[i] = perInst
	end
	if perInst[minute] == nil then
		perInst[minute] = { hMax, lMin }
		minuteCount += 1
	end
end

-- ---------------------------------------------------------------------
-- Ein Zeitraum [from, to] chronologisch
-- ---------------------------------------------------------------------
local function runRange(d: Depot, env: Env, from: number, to: number, src: Source, slice: () -> ())
	local divCache: { [number]: { { [string]: number } } } = {}
	local function divsAt(t: number): { { [string]: number } }?
		local day = t // DAY
		local list = divCache[day]
		if list == nil then
			local ok, result = pcall(env.Dividends, day * DAY, day * DAY + DAY - 1)
			list = if ok and type(result) == "table" then result else {}
			divCache[day] = list
		end
		for _, div in ipairs(list :: any) do
			if div.Tick == t then
				return list
			end
		end
		return nil
	end

	local t = from
	while t <= to do
		local minute = t // 60
		local mStart = minute * 60
		local mEnd = math.min(to, mStart + 59)
		local complete = mEnd == mStart + 59 and mEnd < env.CacheBefore

		-- 1) Welche Werte müssen in dieser Minute Tick für Tick laufen?
		local arrays: { [number]: { Candle? } } = {}
		local summary: { [number]: { number } } = {}
		local need: { [number]: boolean } = {}
		local hsOf: { [number]: number } = {}
		local function prepare(i: number)
			if summary[i] then
				return
			end
			hsOf[i] = OrderEngine.HalfSpread(env, i, mStart)
			local cached = complete and minuteCache[i] and minuteCache[i][minute]
			if cached then
				summary[i] = cached
			else
				local list, hMax, lMin = loadCandles(src, i, mStart, mEnd)
				arrays[i] = list
				summary[i] = { hMax, lMin }
				if complete and hMax > -math.huge then
					cacheMinute(i, minute, hMax, lMin)
				end
			end
		end
		local function ensureArray(i: number)
			if arrays[i] == nil then
				arrays[i] = (loadCandles(src, i, mStart, mEnd))
			end
		end
		for _, i in ipairs(OrderEngine.ActiveInstruments(d)) do
			prepare(i)
			local s = summary[i]
			if s[1] > -math.huge and OrderEngine.CanTrigger(d, i, s[1], s[2], hsOf[i]) then
				need[i] = true
				ensureArray(i)
			end
		end

		-- 2) Ticks der Minute
		local stepCtx = {
			Candle = function(_i: number): (number?, number?, number?, number?)
				return nil, nil, nil, nil
			end,
			Divs = nil :: any,
		}
		for tt = t, mEnd do
			local divs = divsAt(tt)
			local anyNeed = next(need) ~= nil
			if tt % 60 == 0 or tt % DAY == 0 or anyNeed or divs ~= nil then
				stepCtx.Candle = function(i: number): (number?, number?, number?, number?)
					if not need[i] then
						return nil, nil, nil, nil
					end
					local list = arrays[i]
					local candle = list and list[tt - mStart + 1]
					if candle then
						return candle[1], candle[2], candle[3], candle[4]
					end
					return nil, nil, nil, nil
				end
				stepCtx.Divs = divs
				OrderEngine.Step(d, env, tt, stepCtx)
				-- neue Orders mitten in der Minute (Bots, Klammern): ab dem nächsten Tick einzeln prüfen
				for _, i in ipairs(OrderEngine.ActiveInstruments(d)) do
					if not need[i] then
						prepare(i)
						ensureArray(i)
						-- bisherige Ticks dieser Minute (bis einschließlich tt) als "ohne Auslösung" nachführen
						local list = arrays[i]
						local hMax = -math.huge
						for k = mStart, tt do
							local candle = list and list[k - mStart + 1]
							if candle and candle[2] > hMax then
								hMax = candle[2]
							end
						end
						if hMax > -math.huge then
							OrderEngine.SkipMinute(d, i, hMax, hsOf[i])
						end
						need[i] = true
					end
				end
			else
				d.LastTick = tt
			end
		end

		-- 3) Werte ohne Einzelprüfung: Nachzieh-Stopps mit dem Minuten-Hoch nachführen
		for i, s in pairs(summary) do
			if not need[i] and s[1] > -math.huge then
				OrderEngine.SkipMinute(d, i, s[1], hsOf[i])
			end
		end
		d.LastTick = mEnd
		t = mEnd + 1
		slice()
	end
end

-- Abwesenheit länger als das Order-Fenster: Rest überspringen (alle Orders sind dann abgelaufen)
local function jump(d: Depot, env: Env, winEnd: number, toTick: number)
	OrderEngine.Expire(d, env, toTick)
	local rec = Portfolio.CurrentDay(d)
	if rec then
		rec[3] = OrderEngine.NavAt(d, env, winEnd)
		rec[6] = 0 -- unvollständiger Zeitraum zählt nie für die Liga
	end
	d.LastTick = toTick
	Portfolio.OpenDay(d, toTick // DAY, OrderEngine.NavAt(d, env, toTick), next(d.Pos) ~= nil)
end

function CatchUp.Run(d: Depot, env: Env, toTick: number, opts: { [string]: any }): Report
	local report: Report = {
		Fills = 0,
		Dividends = 0,
		Alerts = 0,
		Expired = 0,
		Transfers = 0,
		Days = 0,
		Bots = {},
		Jumped = false,
		Ticks = 0,
		Aborted = false,
	}
	local budget = num(opts.BudgetMs, 2) / 1000
	local clock: () -> number = if type(opts.Now) == "function" then opts.Now else os.clock
	local sliceStart = clock()
	local function slice()
		if opts.Yield and clock() - sliceStart >= budget then
			opts.Yield()
			sliceStart = clock()
			-- Spieler weg? Abbrechen – der Stand ist an jeder Minutengrenze vollständig (LastTick = Minutenende),
			-- der nächste Beitritt rechnet genau dort weiter.
			if type(opts.Abort) == "function" and opts.Abort() then
				error(ABORT, 0)
			end
		end
	end

	local src: Source = { Cursors = {}, Pos = {}, Opts = opts }
	local startLast = math.floor(num(d.LastTick, 0))
	local _, firstWinEnd, firstBotsUntil = CatchUp.Window(d, toTick)
	-- Bot-Bilanz: Wert am Anfang merken, Geldflüsse der Bot-Fills über den ganzen Zeitraum mitschreiben
	local botStart: { [number]: number } = {}
	local botCash: { [number]: number } = {}
	if type(d.Bots) == "table" then
		for index, slot in ipairs(d.Bots) do
			if BotEngine.Preset(slot.Preset) then
				botStart[index] = BotEngine.Value(d, env, startLast, slot)
				botCash[index] = 0
			end
		end
	end

	-- Ereignisse zählen, dann an die eigentliche Env weiterreichen
	local transfers = 0
	local transferCfg = trading().Transfer
	local maxTransfers = math.floor(num(type(transferCfg) == "table" and transferCfg.MaxOfflineDays, 72))
	env.NoAutoTransfer = if maxTransfers <= 0 then true else nil
	local innerEmit = env.Emit
	env.Emit = function(kind: string, data: any)
		if kind == "Fill" then
			report.Fills += 1
			local f = data.Fill
			local slotIndex = data.BotSlot
			if f and type(slotIndex) == "number" and botCash[slotIndex] ~= nil then
				local cash = f.Q * f.Px
				botCash[slotIndex] += if f.Side == "B" then -(cash + f.Fee) else cash - f.Fee
			end
		elseif kind == "Dividend" then
			report.Dividends += math.floor(num(data.Cents, 0))
		elseif kind == "Alert" then
			report.Alerts += 1
		elseif kind == "Expired" then
			report.Expired += 1
		elseif kind == "Transfer" then
			report.Transfers += math.floor(num(data.Cents, 0))
			transfers += 1
			if transfers >= maxTransfers then
				env.NoAutoTransfer = true -- höchstens 72 verpasste Börsentage (§B8.2)
			end
		elseif kind == "DayResult" then
			report.Days += 1
		end
		innerEmit(kind, data)
	end

	-- Bots offline höchstens 12 h; Ticks NACH dem Beitritt (toTick) sind Online-Zeit -> Bots entscheiden wieder
	env.BotsUntil = firstBotsUntil
	env.BotsFrom = toTick
	local ok, err = pcall(function()
		local rounds = 0
		local target = toTick
		while rounds < MAX_ROUNDS do
			rounds += 1
			local last = math.floor(num(d.LastTick, 0))
			if last >= target then
				break
			end
			local winEnd = math.min(target, firstWinEnd)
			if last + 1 <= winEnd then
				runRange(d, env, last + 1, winEnd, src, slice)
			end
			if math.floor(num(d.LastTick, 0)) < target then
				if winEnd < target then
					jump(d, env, winEnd, target)
					report.Jumped = true
				end
			end
			-- Markt ist inzwischen weitergelaufen? -> Rest ebenfalls nachholen (wieder mit denselben Fenstern)
			if type(opts.Target) == "function" then
				local okTarget, now = pcall(opts.Target)
				if okTarget and type(now) == "number" and now > target then
					target = now
					if report.Jumped then
						firstWinEnd = target -- nach einem Sprung ist das Fenster der Rest bis jetzt
					end
				end
			end
		end
	end)
	env.Emit = innerEmit
	env.BotsUntil = nil
	env.BotsFrom = nil
	env.NoAutoTransfer = nil
	if not ok and err ~= ABORT then
		warn("[CatchUp] Abgleich abgebrochen: " .. tostring(err))
	end
	report.Aborted = not ok and err == ABORT
	report.Ticks = math.max(0, math.floor(num(d.LastTick, 0)) - startLast)

	-- Bot-Bilanz in Prozent des Startkapitals (Wert am Anfang bzw. Tageskapital)
	if type(d.Bots) == "table" then
		local endTick = math.floor(num(d.LastTick, 0))
		for index, slot in ipairs(d.Bots) do
			local startValue = botStart[index]
			if startValue ~= nil and (slot.On == true or startValue > 0) then
				local endValue = BotEngine.Value(d, env, endTick, slot)
				local base = math.max(startValue, math.floor(num(slot.DayNav, 0)), 1)
				local pct = (endValue + (botCash[index] or 0) - startValue) / base
				table.insert(report.Bots, { Preset = slot.Preset, Pct = math.floor(pct * 10000 + 0.5) / 10000 })
			end
		end
	end
	return report
end

return CatchUp
