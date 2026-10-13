-- =====================================================================
--  AKYTEX TYCOON – Strategie-Bots: Sparplan, Trend, Dividende, Dip-Käufer (Server/Market/BotEngine)
--  Besitzer: WP4 (Orders, Depot, Bots). Vertrag: DESIGN.md §B8.5, §0.4 (nur Lizenz + Know-how, nie Robux),
--  MARKET.md §15. Reines Daten-Modul: entscheidet 1× je Minute (t % 60 == 0) auf 1m-Schlusskursen
--  (Schluss der Minute M = PriceAt(i, 60·M + 59)) und handelt über DIESELBE OrderEngine mit Flag "Bot"
--  -> online = offline (Offline-Abgleich höchstens 12 h, env.BotsUntil).
--
--  Regeln:
--    * Plätze: TradingPerks.BotSlots (Lizenz) · Presets ab Lizenz (Config.Trading.Bots[*].Licence)
--    * Kapital je Bot: Bot-Stufe (Know-how BotLvl.<Preset>, 0 … 4) -> 10/15/20/25/30 % des Depotwerts
--      (Capital-Presets: höchstens der eingestellte Anteil); alle Bots zusammen ≤ 30 % (prüft OrderService bei BotSet)
--    * Tagesverlust-Bremse −5 % des Tageskapitals -> pausiert bis zur nächsten Glocke; Not-Aus = BotToggle
--    * Lohn 0,02 % des verwalteten Kapitals je Börsentag (AKY-Senke, OrderEngine.CloseDay ruft PayWages)
--  Bot-Platz (Types.BotSlot + Zusatzfelder): { Preset, Pct, Target?, On, Paused, DayNav, DayVal, DayFlow, Day, Last,
--  Q = { [instId-String] = Stück des Bots } }.
--
--  Öffentliche API:
--    BotEngine.Decide(d, env, t)                  alle Bots eines Depots (von OrderEngine.Step aufgerufen)
--    BotEngine.PayWages(d, env, t)                Lohn am Börsentag-Schluss
--    BotEngine.Value(d, env, t, slot): number     Wert der Bot-Bestände (Bid)
--    BotEngine.Capital(env, slot): number         Kapitalanteil (Bruch) des Bots
--    BotEngine.Preset(key) · BotEngine.Unlocked(env, key): boolean · BotEngine.NewSlot(preset, pct, target)
--    BotEngine.DividendTargets(env): { number }   die 6 Zahler mit der höchsten Dividende (Lizenz-gefiltert)
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Clock = require(Shared:WaitForChild("Clock"))
local MarketShared = Shared:WaitForChild("Market")
local PortfolioMath = require(MarketShared:WaitForChild("PortfolioMath"))
local Indicators = require(MarketShared:WaitForChild("Indicators"))
local Portfolio = require(script.Parent:WaitForChild("Portfolio"))
local OrderEngine = require(script.Parent:WaitForChild("OrderEngine"))

local BotEngine = {}

type Depot = { [string]: any }
type Slot = { [string]: any }
type Env = OrderEngine.Env

local DAY = Clock.DAY_TICKS
local CLOSE_CACHE_MAX = 30000
local INST_IDS_FALLBACK = 46

local closeCache: { [number]: { [number]: number } } = {}
local closeCount = 0

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

function BotEngine.Preset(key: string): { [string]: any }?
	local presets = trading().Bots
	local preset = type(presets) == "table" and presets[key] or nil
	return if type(preset) == "table" then preset else nil
end

function BotEngine.Unlocked(env: Env, key: string): boolean
	local preset = BotEngine.Preset(key)
	return preset ~= nil and env.Licence.Index >= num(preset.Licence, 99)
end

function BotEngine.NewSlot(preset: string, pct: number, target: number?): Slot
	return {
		Preset = preset,
		Pct = pct,
		Target = target,
		On = true,
		Paused = false,
		DayNav = 0,
		DayVal = 0,
		DayFlow = 0,
		Day = -1,
		Last = -1,
		Q = {},
	}
end

-- Kapitalanteil (Bruch des Depotwerts): Bot-Stufe aus Know-how, Capital-Presets höchstens der eingestellte Anteil
function BotEngine.Capital(env: Env, slot: Slot): number
	local cfg = trading()
	local levels = env.Perks and env.Perks.BotLevels
	local level = math.clamp(math.floor(num(type(levels) == "table" and levels[slot.Preset], 0)), 0, 4)
	local caps = cfg.BotCapital
	local cap = num(type(caps) == "table" and caps[level + 1], 0.10)
	local preset = BotEngine.Preset(slot.Preset)
	if preset and preset.Param == "Capital" then
		cap = math.min(cap, num(slot.Pct, cap))
	end
	return math.clamp(cap, 0, num(cfg.BotTotalPct, 0.30))
end

-- 1m-Schlusskurs der Minute "minute" (gecacht für Minuten, die sicher abgeschlossen sind)
local function closeOf(env: Env, i: number, minute: number): number?
	local perInst = closeCache[i]
	local cached = perInst and perInst[minute]
	if cached then
		return cached
	end
	local px = env.PriceAt(i, minute * 60 + 59)
	if type(px) ~= "number" or px <= 0 then
		return nil
	end
	if minute * 60 + 59 < env.CacheBefore then
		if closeCount >= CLOSE_CACHE_MAX then
			table.clear(closeCache)
			closeCount = 0
		end
		perInst = closeCache[i]
		if not perInst then
			perInst = {}
			closeCache[i] = perInst
		end
		perInst[minute] = px
		closeCount += 1
	end
	return px
end

-- Bot-Bestände nie größer als die echte Position (Spieler kann von Hand verkaufen)
local function syncHoldings(d: Depot, slot: Slot)
	if type(slot.Q) ~= "table" then
		slot.Q = {}
		return
	end
	for key, qty in pairs(slot.Q) do
		local id = tonumber(key)
		local have = if id then Portfolio.PosQty(d, id) else 0
		if have <= 0 then
			slot.Q[key] = nil
		elseif qty > have then
			slot.Q[key] = have
		end
	end
end

function BotEngine.Value(_d: Depot, env: Env, t: number, slot: Slot): number
	local value = 0
	if type(slot.Q) ~= "table" then
		return 0
	end
	for key, qty in pairs(slot.Q) do
		local id = tonumber(key)
		if id and qty > 0 then
			local bid = OrderEngine.EngineQuote(env, id, t)
			value += qty * (if type(bid) == "number" then bid else 0)
		end
	end
	return value
end

local function held(slot: Slot, i: number): number
	return if type(slot.Q) == "table" then math.floor(num(slot.Q[tostring(i)], 0)) else 0
end

local function heldCount(slot: Slot): number
	local n = 0
	if type(slot.Q) == "table" then
		for _, qty in pairs(slot.Q) do
			if qty > 0 then
				n += 1
			end
		end
	end
	return n
end

-- Kauf für höchstens "budget" Cent (Bot-Kapital und freies Geld), nie unter der Mindest-Ordergröße
local function botBuy(d: Depot, env: Env, t: number, slotIndex: number, i: number, budget: number, protect: boolean)
	local cfg = trading()
	if not OrderEngine.InstAllowed(env, i) or env.Halted(i) then
		return nil
	end
	local amount = math.min(math.floor(budget), Portfolio.Free(d))
	if amount < num(cfg.BotMinOrderCents, 10000) then
		return nil
	end
	local bid, ask = OrderEngine.EngineQuote(env, i, t)
	if type(bid) ~= "number" or type(ask) ~= "number" then
		return nil
	end
	local capLeft = OrderEngine.PosCap(env, i) - Portfolio.PosQty(d, i) * ask
	local qty = math.min(
		PortfolioMath.AffordableQty(amount, ask, env.Licence.FeeBps, num(cfg.MinFeeCents, 100)),
		PortfolioMath.MaxQty(ask, capLeft)
	)
	if qty < 1 then
		return nil
	end
	local result = OrderEngine.BuyNow(d, env, t, i, qty, ask, bid, protect, slotIndex, "Bot")
	return if result.Ok then result else nil
end

local function botSell(d: Depot, env: Env, t: number, slotIndex: number, slot: Slot, i: number, qty: number)
	local q = math.min(qty, held(slot, i))
	if q < 1 then
		return nil
	end
	-- eigene Schutz-Orders reservieren die Stück -> zuerst streichen
	OrderEngine.CancelBotOrders(d, slotIndex, i)
	local available = Portfolio.PosQty(d, i) - Portfolio.ReservedQty(d, i)
	q = math.min(q, available)
	if q < 1 then
		return nil
	end
	local bid = OrderEngine.EngineQuote(env, i, t)
	if type(bid) ~= "number" or env.Halted(i) then
		return nil
	end
	local result = OrderEngine.SellNow(d, env, t, i, q, bid, slotIndex, "Bot")
	return if result.Ok then result else nil
end

-- ---------------------------------------------------------------------
-- PRESETS
-- ---------------------------------------------------------------------
local function runSparplan(d: Depot, env: Env, t: number, slotIndex: number, slot: Slot, preset: any, headroom: number)
	local day = t // DAY
	if slot.Last == day then
		return
	end
	slot.Last = day -- einmal je Börsentag (auch wenn gerade nichts gekauft werden kann)
	local target = slot.Target
	if
		type(target) ~= "number"
		or OrderEngine.ClassOf(env, target) ~= "ETF"
		or not OrderEngine.InstAllowed(env, target)
	then
		target = math.floor(num(preset.DefaultTarget, 40))
	end
	local pct = math.clamp(num(slot.Pct, num(preset.Default, 0.10)), num(preset.Min, 0.05), num(preset.Max, 0.20))
	local budget = math.min(math.floor(pct * Portfolio.Free(d)), headroom)
	botBuy(d, env, t, slotIndex, target :: number, budget, false)
end

local function smaPair(
	env: Env,
	i: number,
	minute: number,
	fast: number,
	slow: number
): (number?, number?, number?, number?)
	-- Schlusskurse der Minuten minute − slow … minute − 1 (slow + 1 Werte: jetzt und eine Minute vorher)
	local closes: { number } = table.create(slow + 1)
	for k = slow, 0, -1 do
		local px = closeOf(env, i, minute - 1 - k)
		if not px then
			return nil, nil, nil, nil
		end
		table.insert(closes, px)
	end
	local f = Indicators.SMA(closes, fast)
	local s = Indicators.SMA(closes, slow)
	local n = #closes
	return f[n], s[n], f[n - 1], s[n - 1]
end

local function runTrend(d: Depot, env: Env, t: number, slotIndex: number, slot: Slot, preset: any, headroom: number)
	local target = slot.Target
	if type(target) ~= "number" or not OrderEngine.InstAllowed(env, target) then
		return
	end
	local fast = math.floor(num(preset.Fast, 20))
	local slow = math.floor(num(preset.Slow, 50))
	local fNow, sNow, fPrev, sPrev = smaPair(env, target, t // 60, fast, slow)
	if not (fNow and sNow and fPrev and sPrev) then
		return
	end
	local have = held(slot, target)
	if have > 0 then
		if fNow < sNow then
			botSell(d, env, t, slotIndex, slot, target, have) -- Rückkreuzen -> raus
		end
	elseif fPrev <= sPrev and fNow > sNow then
		botBuy(d, env, t, slotIndex, target, headroom, true) -- frisches Aufwärts-Kreuzen -> rein + Schutz-Paar
	end
end

function BotEngine.DividendTargets(env: Env): { number }
	local ids: { number } = {}
	if env.ActiveIds then
		local ok, list = pcall(env.ActiveIds)
		if ok and type(list) == "table" then
			ids = list
		end
	end
	if #ids == 0 then
		for i = 1, INST_IDS_FALLBACK do
			table.insert(ids, i)
		end
	end
	local candidates: { { Id: number, Bps: number } } = {}
	for _, i in ipairs(ids) do
		local bps = env.DivBps(i)
		if bps > 0 and OrderEngine.InstAllowed(env, i) and OrderEngine.ClassOf(env, i) ~= "ETF" then
			table.insert(candidates, { Id = i, Bps = bps })
		end
	end
	table.sort(candidates, function(a, b)
		if a.Bps ~= b.Bps then
			return a.Bps > b.Bps
		end
		return a.Id < b.Id
	end)
	local divPreset = BotEngine.Preset("Dividend")
	local count = math.floor(num(divPreset and divPreset.Count, 6))
	local out: { number } = {}
	for k = 1, math.min(count, #candidates) do
		table.insert(out, candidates[k].Id)
	end
	return out
end

local function runDividend(
	d: Depot,
	env: Env,
	t: number,
	slotIndex: number,
	slot: Slot,
	preset: any,
	capitalCents: number
)
	local day = t // DAY
	if slot.Last == day then
		return
	end
	slot.Last = day
	local targets = BotEngine.DividendTargets(env)
	if #targets == 0 then
		return
	end
	local inSet: { [number]: boolean } = {}
	for _, i in ipairs(targets) do
		inSet[i] = true
	end
	-- 1) Werte außerhalb der Zielliste verkaufen
	for key, qty in pairs(table.clone(slot.Q)) do
		local id = tonumber(key)
		if id and not inSet[id] and qty > 0 then
			botSell(d, env, t, slotIndex, slot, id, qty)
		end
	end
	-- 2) auf gleiche Gewichte ausgleichen (erst ab Rebalance-Abweichung)
	local per = math.floor(capitalCents / #targets)
	local band = num(preset.Rebalance, 0.10)
	local minOrder = num(trading().BotMinOrderCents, 10000)
	for _, i in ipairs(targets) do
		local bid, ask = OrderEngine.EngineQuote(env, i, t)
		if type(bid) == "number" and type(ask) == "number" then
			local value = held(slot, i) * bid
			local diff = per - value
			if math.abs(diff) > band * per and math.abs(diff) >= minOrder then
				if diff > 0 then
					botBuy(d, env, t, slotIndex, i, diff, false)
				else
					botSell(d, env, t, slotIndex, slot, i, math.floor(-diff / bid))
				end
			end
		end
	end
end

local function runDip(
	d: Depot,
	env: Env,
	t: number,
	slotIndex: number,
	slot: Slot,
	preset: any,
	capitalCents: number,
	headroom: number
)
	local watch = env.Watch
	if type(watch) ~= "table" or #watch == 0 then
		return
	end
	local slots = math.floor(num(preset.Slots, 3))
	if heldCount(slot) >= slots then
		return
	end
	local drop = math.clamp(num(slot.Pct, num(preset.Default, 0.05)), num(preset.Min, 0.03), num(preset.Max, 0.08))
	local dayStart = (t // DAY) * DAY
	for _, i in ipairs(watch) do
		if heldCount(slot) >= slots then
			break
		end
		if held(slot, i) == 0 and OrderEngine.InstAllowed(env, i) then
			local open = env.PriceAt(i, dayStart - 1)
			local now = closeOf(env, i, t // 60 - 1)
			local before = if t - 61 >= dayStart then closeOf(env, i, t // 60 - 2) else open
			if type(open) == "number" and open > 0 and now and before then
				local changeNow = now / open - 1
				local changeBefore = before / open - 1
				-- nur beim Unterschreiten der Schwelle (kein Nachkaufen nach einem Stopp ohne neue Erholung)
				if changeNow <= -drop and changeBefore > -drop then
					local budget = math.min(math.floor(capitalCents / slots), headroom)
					local result = botBuy(d, env, t, slotIndex, i, budget, false)
					if result and result.Fill then
						local stopPct = num(preset.Stop, 0.08)
						local stp = math.max(1, math.floor(result.Fill.Px * (1 - stopPct)))
						OrderEngine.AttachStop(d, t, i, result.Fill.Q, stp, slotIndex)
						headroom -= result.Fill.Q * result.Fill.Px
					end
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- ENTSCHEIDUNG (1× je Minute)
-- ---------------------------------------------------------------------
function BotEngine.Decide(d: Depot, env: Env, t: number)
	if type(d.Bots) ~= "table" or #d.Bots == 0 then
		return
	end
	if env.BotsUntil ~= nil and t > env.BotsUntil and t <= (env.BotsFrom or math.huge) then
		return -- Offline-Abgleich: Bots handeln höchstens 12 h nach dem Verlassen
	end
	local cfg = trading()
	local day = t // DAY
	local nav: number? = nil
	local slotsAllowed = math.floor(num(env.Perks and env.Perks.BotSlots, env.Licence.BotSlots))
	for slotIndex, slot in ipairs(d.Bots) do
		local preset = BotEngine.Preset(slot.Preset)
		if not preset then
			continue
		end
		syncHoldings(d, slot)
		nav = nav or OrderEngine.NavAt(d, env, t)
		local capital = BotEngine.Capital(env, slot)
		local value = BotEngine.Value(d, env, t, slot)
		if slot.Day ~= day then
			-- neuer Börsentag: Tageskapital festhalten, Bremse lösen
			slot.Day = day
			slot.DayVal = value
			slot.DayFlow = 0
			slot.DayNav = math.floor(capital * (nav :: number))
			slot.Paused = false
		end
		if slot.On ~= true or slot.Paused == true then
			continue
		end
		if slotIndex > slotsAllowed or env.Licence.Index < num(preset.Licence, 99) then
			continue -- Platz/Preset (noch) nicht freigeschaltet: ruht, behält Bestände
		end
		-- Tagesverlust-Bremse (−5 % des Tageskapitals)
		local pnl = value + math.floor(num(slot.DayFlow, 0)) - math.floor(num(slot.DayVal, 0))
		local dayNav = math.floor(num(slot.DayNav, 0))
		if dayNav > 0 and pnl <= num(cfg.BotDayStop, -0.05) * dayNav then
			slot.Paused = true
			env.Emit("BotPaused", { Slot = slotIndex, Preset = slot.Preset })
			continue
		end
		local capitalCents = math.floor(capital * (nav :: number))
		local headroom = math.max(0, capitalCents - value)
		local key = slot.Preset
		if key == "Sparplan" then
			runSparplan(d, env, t, slotIndex, slot, preset, headroom)
		elseif key == "Trend" then
			runTrend(d, env, t, slotIndex, slot, preset, headroom)
		elseif key == "Dividend" then
			runDividend(d, env, t, slotIndex, slot, preset, capitalCents)
		elseif key == "Dip" then
			runDip(d, env, t, slotIndex, slot, preset, capitalCents, headroom)
		end
		nav = nil -- nach Trades neu bewerten (Gebühren)
	end
end

-- Lohn: 0,02 % des verwalteten Kapitals (Bot-Bestände zum Bid) je Börsentag, nie aus reserviertem Geld
function BotEngine.PayWages(d: Depot, env: Env, t: number)
	if type(d.Bots) ~= "table" then
		return
	end
	local bps = num(trading().BotWageBps, 2)
	for _, slot in ipairs(d.Bots) do
		if BotEngine.Preset(slot.Preset) then
			syncHoldings(d, slot)
			local value = BotEngine.Value(d, env, t, slot)
			if value > 0 then
				local wage = math.ceil(value * bps / 10000)
				local take = math.min(wage, Portfolio.Free(d))
				if take > 0 then
					Portfolio.Debit(d, take, "BotWage")
				end
			end
		end
	end
end

OrderEngine.UseBots(BotEngine)

return BotEngine
