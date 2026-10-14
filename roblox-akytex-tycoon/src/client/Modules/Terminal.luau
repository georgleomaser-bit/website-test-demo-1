-- =====================================================================
--  AKYTEX TYCOON – ΛKYTEX Terminal: drei Schichten, Handy/PC/Controller, Order-Ticket, Charts, Analyse
--  (Client/Modules/Terminal)
--  Besitzer: WP5 (Charts, Terminal, Markt-UI). Vertrag: DESIGN.md §B7.1–§B7.6 (komplett), §0.3 (Markt ≠ Glücksspiel:
--  Chips 10 % · 25 % · Max, Bestätigung ab 20 %, kein Hebel/keine Optionen), §B8.6 (Übungsaktie ACAD), §C7.3 (Fenster
--  "Terminal" als eigener Frame über Windows.Register), §C7.2 (Hook "Terminal:Instrument"), §C9 (TradePlace,
--  TradeBasket, TradeWatch, AlertSet, MktProfile, TutorialTrade), §C16 (≤ 900 GuiObjects je Chart, < 0,3 ms/Frame).
--
--  Schichten (Lizenz, §B7.2): Einfach (Azubi I–II: Firmen-Karten, Linien-Chart, Chips, „Schutz an“, Tiko-Ampel,
--  Glossar, Klumpen-Warnung) · ab Azubi III Kerzen + SMA/EMA · Trader (ab Trader I: alle Zeitrahmen, Indikatoren laut
--  §B7.5, Kalender, Sektor-Heatmap, Themen-Körbe, Nachzieh-Stopp, freier Betrag, Split 1×2) · Profi (ab Fondsmanager I:
--  Heikin-Ashi, Markttiefe + Umsätze „simuliert“, Fundamentaldaten, Analysten-Trefferquoten, Korrelation,
--  Performance-Analyse; Tiko-Ampel aus; Multi-Chart 2×2 über Know-how). Instrumente/Ordertypen/Indikatoren immer
--  lizenz-gefiltert (Azubi sieht nur 12 Werte + AKX36). Alles nur über Lizenz + Know-how, NIE über Robux (§0.4).
--  Layouts: PC (≥ 1100 × 680 px, Maus) = Watchlist links · Chart Mitte · Ticket + News rechts · Tabs unten;
--  Handy = Vollbild-Sheet mit 4 Tabs Chart · Order · Depot · News und fester Kauf/Verkauf-Leiste (Knöpfe ≥ 64 px echte
--  Pixel), Wischen wechselt den Wert; Controller = Steuerkreuz Watchlist/Fadenkreuz, LB/RB Zeitrahmen, A Kauf-Sheet,
--  X Verkauf-Sheet, Y Schutz-Paar, B zurück, rechter Stick Fadenkreuz (ContextActionService nur solange offen –
--  die Controls-Aktionsliste kennt diese Terminal-Knöpfe nicht, siehe Abweichungen im Bericht).
--
--  Öffentliche API (§C7.5):
--    Terminal.Open()   Terminal.OpenAt(instId)   Terminal.IsOpen()
--  Zusätzlich: Terminal.OpenTicket(instId, side) · Terminal.ShowTab(tab) · Terminal.OpenPractice() ·
--    Terminal.Selected(): number? · Terminal.Frame(dt) · Terminal.Init(ctx) · Terminal.Start()
-- =====================================================================

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent:WaitForChild("UI"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PortfolioMath = require(Shared:WaitForChild("Market"):WaitForChild("PortfolioMath"))

local Terminal = {}

local Theme = UI.Theme
local WHITE = Color3.new(1, 1, 1)

local ALL_TF = { "1s", "5s", "1m", "5m", "15m", "1T", "1W" }
local SIMPLE_TF = { "5s", "1m", "15m", "1T" }
local TYPES_BASE = { "MKT", "LMT", "STP", "TP", "OCO" }
local TYPE_KEY: { [string]: string } = {
	MKT = "trade.typeMKT",
	LMT = "trade.typeLMT",
	STP = "trade.typeSTP",
	TP = "trade.typeTP",
	OCO = "trade.typeOCO",
	TRL = "trade.typeTRL",
}
local EXPLAIN_KEY: { [string]: string } = {
	LMT = "trade.explainLMT",
	STP = "trade.explainSTP",
	TP = "trade.explainTP",
	OCO = "trade.explainOCO",
	TRL = "trade.explainTRL",
	MKT = "term.explainMKT",
}
local SELL_ONLY: { [string]: boolean } = { TP = true, OCO = true, TRL = true }
local PANE_INDICATORS: { [string]: boolean } = { RSI = true, MACD = true, Stoch = true, ATR = true }
local SECTOR_ETF: { [string]: number } = { T = 41, E = 42, M = 43, K = 44, G = 45, F = 46 }
local GLOSS_COUNT = 8
local GLOSS_EVERY = 12
local PC_MIN = Vector2.new(1100, 680)
local PAD_PRIORITY = Enum.ContextActionPriority.High.Value + 100
local PAD_ACTION = "AT5_TerminalPad"
local STICK_REPEAT = 0.12
local PROFILE_TTL = 30
local CALENDAR_EVERY = 5
local ANALYSIS_EVERY = 1
local OPEN_INFO = TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local SHEET_INFO = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local CLOSE_INFO = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local ctx: any = nil

-- Zustand, der Neuaufbauten überlebt
local sel: number? = nil
local listMode = "All" -- All | Watch | Depot
local watchIndex = 1
local phoneTab = "Chart"
local bottomTab = "Positions"
local phoneDepotTab = "Overview"
local phoneNewsTab = "News"
local chartMode = "Single" -- Single | Split | Multi
local ampelOn = true
local alarmMode = false
local ticket = {
	Type = "MKT",
	Chip = "10", -- "10" | "25" | "Max"
	Amount = "Chip", -- Chip | Qty | Aky
	AmountText = "",
	Lim = "",
	Stp = "",
	Tp = "",
	Trl = "5",
	Protect = true,
	Exp = "24H",
	Busy = false,
}

-- Oberfläche (wird bei jedem Neuaufbau ersetzt)
local ui: { [string]: any } = {}
local views: { { View: any, I: number, Tf: string, Untrack: () -> (), Stale: boolean?, Role: string? } } = {}
local layoutKind = "PC"
local builtKey = ""
local isOpen = false
local openToken = 0
local padBound = false
local stickX = 0
local stickClock = 0
local glossIndex = 1
local glossClock = 0
local calendarClock = 0
local analysisClock = 0
local profileCache: { [number]: { At: number, Profile: any } } = {}
local profileBusy: { [number]: boolean } = {}
local tape: { { T: number, C: number, V: number, Up: boolean } } = {}
local practiceWanted = false
local practiceBought = false
local practiceDoneAt = -math.huge
local pendingConfirm: { [string]: any }? = nil
local sheetSide: string? = nil
local correlation: { I: number, Ref: number, Value: number?, At: number }? = nil

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function T(key: string, ...: any): string
	return ctx.T(key, ...)
end

local function lang(): string
	return ctx.Lang_()
end

local function call(name: string, fnName: string, ...: any): (boolean, any, any, any)
	local modules = ctx and ctx.Modules
	local m = modules and modules[name]
	local fn = m and m[fnName]
	if type(fn) ~= "function" then
		return false, nil, nil, nil
	end
	return pcall(fn, ...)
end

local function num(v: any, fallback: number): number
	return if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then v else fallback
end

local function aky(cents: number, compact: boolean?): string
	local ok, text = pcall(ctx.Format.Aky, cents, lang(), compact)
	return if ok then text else tostring(math.floor(cents / 100))
end

local function price(cents: number): string
	local ok, text = pcall(ctx.Format.Price, cents, lang())
	return if ok then text else string.format("%.2f", cents / 100)
end

local function pct(fraction: number, digits: number?): string
	local ok, text = pcall(ctx.Format.Pct, fraction, lang(), digits or 2, true)
	return if ok then text else string.format("%+.2f %%", fraction * 100)
end

-- ganze Zahl mit Tausender-Trennung (DE 12.500 · EN 12,500) – Stückzahlen
local function int(n: number): string
	local ok, text = pcall(ctx.Format.Int, math.floor(num(n, 0)), lang())
	return if ok and type(text) == "string" then text else tostring(math.floor(num(n, 0)))
end

-- Dezimalzahl in Landesschreibweise (DE mit Komma)
local function decimal(v: number, places: number): string
	local text = string.format("%." .. places .. "f", num(v, 0))
	if lang() == "de" then
		text = (string.gsub(text, "%.", ","))
	end
	return text
end

local function setText(label: TextLabel?, text: string)
	if label and label.Text ~= text then
		label.Text = text
	end
end

local function sfx(role: string)
	call("Sfx", "Play", role)
end

local function state(): { [string]: any }
	return ctx.State
end

local function depot(): { [string]: any }
	local d = state().Depot
	return if type(d) == "table" then d else {}
end

local function settings(): { [string]: any }
	local ok, value = call("Settings", "Get")
	if ok and type(value) == "table" then
		return value
	end
	local s = state().Settings
	if type(s) == "table" then
		return s
	end
	local client = ctx.Config.Client
	return if type(client) == "table" and type(client.DefaultSettings) == "table" then client.DefaultSettings else {}
end

local function reducedFx(): boolean
	return settings().ReducedFx == true
end

local function licence(): number
	local ok, value = call("MarketClient", "Licence")
	return if ok and type(value) == "number" then value else 1
end

local function licenceDef(): { [string]: any }
	local ok, def = call("MarketClient", "LicenceDef")
	return if ok and type(def) == "table" then def else {}
end

local function layer(): string
	local ok, value = call("MarketClient", "Layer")
	return if ok and type(value) == "string" then value else "Simple"
end

local function perks(): { [string]: any }
	local ok, value = call("MarketClient", "Perks")
	return if ok and type(value) == "table" then value else {}
end

local function trading(): { [string]: any }
	local t = ctx.Config.Trading
	return if type(t) == "table" then t else {}
end

local function traderFrom(): number
	return math.floor(num(trading().TraderFrom, 4))
end

local function instOf(i: number?): any
	if type(i) ~= "number" then
		return nil
	end
	local ok, inst = call("MarketClient", "Instrument", i)
	return if ok then inst else nil
end

local function tickerOf(i: number?): string
	local inst = instOf(i)
	return if type(inst) == "table" then inst.Ticker else "–"
end

local function allowed(i: number?): boolean
	if type(i) ~= "number" then
		return false
	end
	local ok, value = call("MarketClient", "Allowed", i)
	return ok and value == true
end

local function quote(i: number): (number?, number?)
	local ok, close, change = call("MarketClient", "Quote", i)
	if ok then
		return close, change
	end
	return nil, nil
end

local function bidAsk(i: number): (number?, number?, number?)
	local ok, bid, ask, mid = call("MarketClient", "BidAsk", i)
	if ok then
		return bid, ask, mid
	end
	return nil, nil, nil
end

local function halted(i: number): boolean
	local ok, value = call("MarketClient", "Halted", i)
	return ok and value == true
end

local function nav(): number
	local ok, value = call("DepotView", "Nav")
	if ok and type(value) == "number" then
		return value
	end
	return num(depot().Nav, num(depot().Cash, 0))
end

local function freeCash(): number
	local ok, value = call("DepotView", "Free")
	if ok and type(value) == "number" then
		return value
	end
	return num(depot().Cash, 0)
end

local function position(i: number): (number, number, number)
	local ok, q, avg, free = call("DepotView", "Position", i)
	if ok and type(q) == "number" then
		return q, num(avg, 0), num(free, 0)
	end
	return 0, 0, 0
end

local function nextSeq(): number
	local ok, seq = call("MarketClient", "NextSeq")
	if ok and type(seq) == "number" then
		return seq
	end
	return (math.floor(os.time()) % 2097152) * 1024
end

local function quality(key: string, fallback: number): number
	local ok, value = call("Quality", "Budget", key)
	return if ok and type(value) == "number" then value else fallback
end

local function inputKind(): string
	local ok, value = call("Controls", "Input")
	if ok and type(value) == "string" then
		return value
	end
	return if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "Touch" else "KBM"
end

local function rootScale(): number
	return UI.ScaleOf(ctx.Gui)
end

local function touchMin(): number
	local client = ctx.Config.Client
	local min = if type(client) == "table" then num(client.TouchButtonMin, 64) else 64
	return math.ceil(min / math.max(0.1, rootScale()))
end

local function watchLists(): { { number } }
	local watch = depot().Watch
	return if type(watch) == "table" then watch else { {} }
end

local function heldIds(): { number }
	local out: { number } = {}
	local pos = depot().Pos
	if type(pos) == "table" then
		for key, p in pairs(pos) do
			local i = tonumber(key)
			if i and type(p) == "table" and num(p.Q, 0) > 0 then
				table.insert(out, i)
			end
		end
	end
	table.sort(out)
	return out
end

-- ---------------------------------------------------------------------
-- FREIGABEN NACH LIZENZ (§B7.2, §B7.3, §B7.5)
-- ---------------------------------------------------------------------
local function allowedTfs(): { string }
	return if licence() >= traderFrom() then ALL_TF else SIMPLE_TF
end

local function areaFill(): boolean
	return quality("AreaFill", 0) >= 1
end

local function allowedStyles(): { string }
	local l = licence()
	local out: { string } = {}
	if l >= 3 then
		table.insert(out, "Candles")
		table.insert(out, "Hollow")
	end
	table.insert(out, "Line")
	if areaFill() then
		table.insert(out, "Area")
	end
	if layer() == "Pro" then
		table.insert(out, "HeikinAshi")
	end
	return out
end

local function allowedTypes(): { string }
	local out = table.clone(TYPES_BASE)
	if licence() >= traderFrom() then
		table.insert(out, "TRL")
	end
	return out
end

local function indicatorNames(): { string }
	local client = ctx.Config.Client
	local names = type(client) == "table" and client.IndicatorNames or nil
	return if type(names) == "table"
		then names
		else { "SMA20", "SMA50", "SMA200", "EMA9", "EMA21", "BB", "VWAP", "RSI", "MACD", "Stoch", "ATR" }
end

local function allowedIndicators(): { string }
	local map = perks().Indicators
	local out: { string } = {}
	for _, name in ipairs(indicatorNames()) do
		if type(map) == "table" and map[name] == true then
			table.insert(out, name)
		end
	end
	return out
end

local function maxLines(): number
	return if layoutKind == "Phone" then 3 else 6
end

local function currentTf(): string
	local tf = settings().ChartTf
	local list = allowedTfs()
	if type(tf) == "string" and table.find(list, tf) then
		return tf
	end
	return if table.find(list, "1m") then "1m" else list[1]
end

local function currentStyle(): string
	local style = settings().ChartType
	local list = allowedStyles()
	if type(style) == "string" and table.find(list, style) then
		return style
	end
	return list[1]
end

-- wirksame Indikatoren: Einstellung ∩ Lizenz, höchstens maxLines (Handy 3 / PC 6), nur ein Indikator-Feld
local function indicatorMap(): { [string]: boolean }
	local wanted = settings().Indicators
	local out: { [string]: boolean } = {}
	if type(wanted) ~= "table" then
		return out
	end
	local count = 0
	local paneUsed = false
	for _, name in ipairs(allowedIndicators()) do
		if wanted[name] == true and count < maxLines() then
			if PANE_INDICATORS[name] then
				if not paneUsed then
					paneUsed = true
					out[name] = true
					count += 1
				end
			else
				out[name] = true
				count += 1
			end
		end
	end
	return out
end

local function ampelVisible(): boolean
	local l = layer()
	if l == "Pro" then
		return false
	elseif l == "Trader" then
		return ampelOn
	end
	return true
end

-- ---------------------------------------------------------------------
-- TICKET-RECHNUNG (PortfolioMath – exakt wie der Server)
-- ---------------------------------------------------------------------
local function parseNumber(text: string): number?
	local raw = string.gsub(text or "", "[^%d,%.]", "")
	if raw == "" then
		return nil
	end
	-- DE: "1.234,56" -> 1234.56 · EN: "1,234.56" -> 1234.56
	local lastComma = string.find(raw, ",[^,]*$")
	local lastDot = string.find(raw, "%.[^%.]*$")
	if lastComma and (not lastDot or lastComma > lastDot) then
		raw = string.gsub(raw, "%.", "")
		raw = string.gsub(raw, ",", ".")
	else
		raw = string.gsub(raw, ",", "")
	end
	local n = tonumber(raw)
	if n and n == n and n > 0 and n < 1e12 then
		return n
	end
	return nil
end

local function priceField(text: string): number?
	local n = parseNumber(text)
	return if n then math.max(1, math.floor(n * 100 + 0.5)) else nil
end

local function maxWeight(i: number): number?
	local inst = instOf(i)
	if type(inst) == "table" and inst.Class == "ETF" then
		return nil -- ETFs sind von der Klumpen-Grenze ausgenommen
	end
	return num(licenceDef().MaxWeight, 0.30)
end

local function posCap(i: number): number
	local inst = instOf(i)
	local bases = trading().LiquidityBase
	local base = if type(bases) == "table" and type(inst) == "table" then num(bases[inst.Class], 2e8) else 2e8
	return base * num(licenceDef().PosFactor, 0.01)
end

local function refPrice(side: string, otype: string, ask: number, bid: number): number
	if side == "B" then
		if otype == "LMT" then
			return priceField(ticket.Lim) or ask
		elseif otype == "STP" then
			return math.ceil((priceField(ticket.Stp) or ask) * num(trading().BuyStopReserve, 1.05))
		end
		return ask
	end
	return bid
end

-- Anteil des gewählten Chips am Depotwert – dieselbe Quelle wie der Server (Config.Trading.Chips)
local function chipFraction(): number
	local fraction = if ticket.Chip == "25" then 0.25 else 0.10
	local chips = trading().Chips
	if type(chips) == "table" then
		fraction = num(if ticket.Chip == "25" then chips[2] else chips[1], fraction)
	end
	return fraction
end

-- geschätzte Menge, Kosten/Erlös, Gebühr, Gewicht danach
local function estimate(side: string): { [string]: any }?
	local i = sel
	if not i then
		return nil
	end
	local bid, ask, mid = bidAsk(i)
	if not bid or not ask or not mid then
		return nil
	end
	local bps = num(licenceDef().FeeBps, 10)
	local minFee = num(trading().MinFeeCents, 100)
	local otype = ticket.Type
	local total = math.max(1, nav())
	local q, _, freeQ = position(i)
	local px = refPrice(side, otype, ask, bid)
	local qty = 0
	if ticket.Amount == "Qty" then
		qty = math.floor(parseNumber(ticket.AmountText) or 0)
	elseif ticket.Amount == "Aky" then
		local cents = math.floor((parseNumber(ticket.AmountText) or 0) * 100)
		if side == "B" then
			qty = PortfolioMath.AffordableQty(math.min(cents, freeCash()), px, bps, minFee)
		else
			qty = math.min(freeQ, math.floor(cents / math.max(1, bid)))
		end
	elseif side == "B" then
		local notional: number
		if ticket.Chip == "Max" then
			notional = freeCash()
			local weight = maxWeight(i)
			if weight then
				notional = math.min(notional, math.floor(weight * total) - q * bid)
			end
		else
			notional = math.floor(chipFraction() * total)
		end
		qty = PortfolioMath.AffordableQty(math.max(0, math.min(notional, freeCash())), px, bps, minFee)
		local capLeft = posCap(i) - q * px
		qty = math.min(qty, PortfolioMath.MaxQty(px, capLeft))
	else
		if ticket.Chip == "Max" then
			qty = freeQ
		else
			qty = math.min(freeQ, math.ceil(chipFraction() * total / math.max(1, bid)))
		end
	end
	qty = math.max(0, qty)
	local gross = qty * px
	local fee = if qty > 0 then PortfolioMath.Fee(gross, bps, minFee) else 0
	local result: { [string]: any } = { Qty = qty, Px = px, Fee = fee, Bid = bid, Ask = ask, Mid = mid }
	if side == "B" then
		result.Cost = PortfolioMath.BuyCost(qty, px, bps, minFee)
		result.Spread = qty * math.max(0, ask - mid)
		result.Weight = (q * bid + gross) / total
	else
		result.Proceeds = PortfolioMath.SellProceeds(qty, bid, bps, minFee)
		result.Weight = math.max(0, (q - qty) * bid) / total
	end
	return result
end

-- ---------------------------------------------------------------------
-- BAUSTEINE
-- ---------------------------------------------------------------------
local function frame(props: { [string]: any }): Frame
	local base: { [string]: any } = { BackgroundTransparency = 1, BorderSizePixel = 0 }
	for k, v in pairs(props) do
		base[k] = v
	end
	return UI.Create("Frame", base)
end

local function text(props: { [string]: any }): TextLabel
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		FontFace = UI.Faces.Body,
		TextSize = 14,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	}
	for k, v in pairs(props) do
		base[k] = v
	end
	return UI.Create("TextLabel", base)
end

local function panel(props: { [string]: any }): Frame
	local base: { [string]: any } = {
		BackgroundColor3 = Theme.Bg2,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
	}
	for k, v in pairs(props) do
		base[k] = v
	end
	return UI.Create("Frame", base, { UI.Corner(12), UI.Stroke(nil, 1) })
end

local function logo(parent: Instance, i: number, size: number, at: UDim2?): Frame
	local inst = instOf(i)
	local ok, sector = call("MarketClient", "Sector", i)
	local color = if ok and type(sector) == "table" then sector.Color else Theme.Accent
	local shape = if type(inst) == "table" and type(inst.Logo) == "table" then inst.Logo.Shape else "Circle"
	local holder = frame({
		Name = "Logo",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = at or UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(size, size),
		Parent = parent,
	})
	local body = frame({
		Name = "Shape",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(if shape == "Diamond" then 0.72 else 1, if shape == "Diamond" then 0.72 else 1),
		Rotation = if shape == "Diamond" then 45 else 0,
		BackgroundTransparency = 0,
		BackgroundColor3 = color,
		Parent = holder,
	})
	UI.Create("UICorner", {
		CornerRadius = if shape == "Circle"
			then UDim.new(0.5, 0)
			elseif shape == "Hex" then UDim.new(0.3, 0)
			else UDim.new(0.2, 0),
		Parent = body,
	})
	UI.Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(color:Lerp(WHITE, 0.18), color:Lerp(Color3.new(0, 0, 0), 0.22)),
		Parent = body,
	})
	text({
		Size = UDim2.fromScale(1, 1),
		FontFace = UI.Faces.Display,
		TextSize = math.floor(size * 0.45),
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = if type(inst) == "table" and type(inst.Logo) == "table" then tostring(inst.Logo.Letter) else "?",
		ZIndex = 2,
		Parent = holder,
	})
	return holder
end

local function chip(parent: Instance, label: string, color: Color3, order: number?): Frame
	local c = UI.Chip(parent, label, color)
	if order then
		c.LayoutOrder = order
	end
	return c
end

local function rowList(parent: Instance, padding: number?, horizontal: boolean?): UIListLayout
	return UI.Create("UIListLayout", {
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, padding or 6),
		VerticalAlignment = if horizontal then Enum.VerticalAlignment.Center else Enum.VerticalAlignment.Top,
		Parent = parent,
	})
end

local function scroller(parent: Instance, props: { [string]: any }?): ScrollingFrame
	local base: { [string]: any } = {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Muted,
		ScrollBarImageTransparency = 0.3,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = parent,
	}
	if props then
		for k, v in pairs(props) do
			base[k] = v
		end
	end
	return UI.Create("ScrollingFrame", base)
end

-- ---------------------------------------------------------------------
-- VORWÄRTS-DEKLARATIONEN
-- ---------------------------------------------------------------------
local selectInst: (i: number) -> ()
local refreshAll: () -> ()
local rebuild: () -> ()
local closeSheet: () -> ()

-- ---------------------------------------------------------------------
-- ORDER SENDEN (+ Bestätigung ab 20 %, Gewinn-/Verlust-Feedback §B7.6)
-- ---------------------------------------------------------------------
local function send(arg: { [string]: any })
	if ticket.Busy then
		return
	end
	ticket.Busy = true
	task.spawn(function()
		local reply = ctx.RequestFull("TradePlace", arg)
		ticket.Busy = false
		if reply.Ok then
			local fill = reply.Fill
			if type(fill) == "table" then
				sfx(if fill.Side == "B" then "Buy" else "Sell")
				if fill.Side == "S" and type(fill.Pnl) == "number" then
					call("EffectsMarket", "TradeTick", fill.Pnl, ui.SellButton and ui.SellButton.Frame or nil)
				end
			else
				sfx("UIClick")
			end
		else
			sfx("UIError")
		end
		refreshAll()
	end)
end

local function showConfirm(arg: { [string]: any }, weight: number)
	pendingConfirm = arg
	local sheet = ui.Sheet
	if not sheet then
		send(arg)
		pendingConfirm = nil
		return
	end
	sheetSide = nil
	setText(sheet.Title, T("trade.confirmSpread"))
	setText(sheet.Body, T("term.confirm.share", pct(weight, 0), tickerOf(arg.I)))
	sheet.Chips.Frame.Visible = false
	sheet.Yes.SetText(T("term.confirm.yes"))
	sheet.No.SetText(T("term.confirm.no"))
	sheet.Root.Visible = true
	sheet.Scale.Scale = 0.96
	TweenService:Create(sheet.Scale, OPEN_INFO, { Scale = 1 }):Play()
end

local function buildArg(side: string): ({ [string]: any }?, { [string]: any }?)
	local i = sel
	if not i then
		ctx.Toast(T("term.selectInst"), "Info")
		return nil, nil
	end
	if not allowed(i) then
		ctx.Toast(T("trade.notLicensed"), "Error")
		return nil, nil
	end
	if halted(i) then
		ctx.Toast(T("trade.halted"), "Info")
		return nil, nil
	end
	local otype = ticket.Type
	if side == "B" and SELL_ONLY[otype] then
		ctx.Toast(T("term.sellOnly"), "Info")
		return nil, nil
	end
	if side == "B" and otype == "STP" and licence() < traderFrom() then
		ctx.Toast(T("trade.typeLocked"), "Info")
		return nil, nil
	end
	local est = estimate(side)
	if not est then
		ctx.Toast(T("mkt.notReady"), "Info")
		return nil, nil
	end
	local arg: { [string]: any } = { I = i, Side = side, Type = otype, Seq = nextSeq() }
	if ticket.Amount == "Chip" then
		arg.Pct = if ticket.Chip == "Max" then "Max" elseif ticket.Chip == "25" then 25 else 10
	else
		if est.Qty < 1 then
			ctx.Toast(T("term.qtyInvalid"), "Error")
			return nil, nil
		end
		arg.Qty = est.Qty
	end
	if otype == "LMT" then
		arg.Lim = priceField(ticket.Lim)
	elseif otype == "STP" then
		arg.Stp = priceField(ticket.Stp)
	elseif otype == "TP" then
		arg.Tp = priceField(ticket.Tp)
	elseif otype == "OCO" then
		arg.Stp = priceField(ticket.Stp)
		arg.Tp = priceField(ticket.Tp)
	elseif otype == "TRL" then
		local trl = parseNumber(ticket.Trl)
		if trl then
			local bounds = trading().TrailBps or {}
			arg.Trl = math.clamp(math.floor(trl * 100 + 0.5), num(bounds.Min, 50), num(bounds.Max, 2000))
		end
	end
	for _, key in ipairs({ "Lim", "Stp", "Tp", "Trl" }) do
		local need = (key == "Lim" and otype == "LMT")
			or (key == "Stp" and (otype == "STP" or otype == "OCO"))
			or (key == "Tp" and (otype == "TP" or otype == "OCO"))
			or (key == "Trl" and otype == "TRL")
		if need and arg[key] == nil then
			ctx.Toast(T("term.priceInvalid"), "Error")
			return nil, nil
		end
	end
	if side == "B" and (otype == "MKT" or otype == "LMT") and ticket.Protect then
		arg.Protect = true
	end
	if otype ~= "MKT" then
		arg.Exp = if ticket.Exp == "DAY" then "DAY" else "24H"
	elseif side == "B" then
		arg.MaxPx = math.ceil(est.Ask * 1.02) -- Schutzgrenze: Kurs schlechter -> Ablehnung, nie alter Preis
	else
		arg.MinPx = math.max(1, math.floor(est.Bid * 0.98))
	end
	return arg, est
end

local function place(side: string)
	local arg, est = buildArg(side)
	if not arg or not est then
		return
	end
	local confirmAbove = num(trading().ConfirmAbove, 0.20)
	if side == "B" and num(est.Weight, 0) >= confirmAbove then
		showConfirm(arg, est.Weight)
		return
	end
	send(arg)
end

-- Schutz-Paar für die gehaltene Position (Controller Y / Knopf)
local function protectPosition()
	local i = sel
	if not i then
		return
	end
	local q, _, freeQ = position(i)
	if q <= 0 or freeQ <= 0 then
		ticket.Protect = not ticket.Protect
		ctx.Toast(T(if ticket.Protect then "term.protect" else "term.protectOff"), "Info")
		refreshAll()
		return
	end
	local bid = bidAsk(i)
	if not bid then
		return
	end
	local protect = trading().Protect or { Sl = 0.08, Tp = 0.15 }
	send({
		I = i,
		Side = "S",
		Type = "OCO",
		Pct = "Max",
		Stp = math.max(1, math.floor(bid * (1 - num(protect.Sl, 0.08)))),
		Tp = math.ceil(bid * (1 + num(protect.Tp, 0.15))),
		Exp = "24H",
		Seq = nextSeq(),
	})
end

-- ---------------------------------------------------------------------
-- SHEET (Controller-Kauf/-Verkauf und Bestätigung)
-- ---------------------------------------------------------------------
local function openSheet(side: string)
	local sheet = ui.Sheet
	if not sheet then
		return
	end
	pendingConfirm = nil
	sheetSide = side
	setText(sheet.Title, T(if side == "B" then "term.sheet.buy" else "term.sheet.sell", tickerOf(sel)))
	sheet.Chips.Frame.Visible = true
	sheet.Chips.Set(ticket.Chip)
	sheet.Yes.SetText(T("term.sheet.confirm"))
	sheet.Yes.SetVariant(if side == "B" then "Success" else "Danger")
	sheet.No.SetText(T("term.confirm.no"))
	local est = estimate(side)
	setText(sheet.Body, if est then T("term.qtyPreview", int(est.Qty), price(est.Px)) else "")
	sheet.Root.Visible = true
	sheet.Scale.Scale = 0.96
	TweenService:Create(sheet.Scale, OPEN_INFO, { Scale = 1 }):Play()
end

closeSheet = function()
	local sheet = ui.Sheet
	pendingConfirm = nil
	sheetSide = nil
	if sheet then
		sheet.Root.Visible = false
	end
end

local function confirmSheet()
	local pending = pendingConfirm
	if pending then
		closeSheet()
		send(pending)
		return
	end
	local side = sheetSide
	closeSheet()
	if side then
		local arg = buildArg(side)
		if arg then
			send(arg)
		end
	end
end

local function sheetChip(delta: number)
	local sheet = ui.Sheet
	if not sheet or not sheetSide then
		return
	end
	local order = { "10", "25", "Max" }
	local index = table.find(order, ticket.Chip) or 1
	index = math.clamp(index + delta, 1, #order)
	ticket.Chip = order[index]
	ticket.Amount = "Chip"
	sheet.Chips.Set(ticket.Chip)
	local est = estimate(sheetSide)
	setText(sheet.Body, if est then T("term.qtyPreview", int(est.Qty), price(est.Px)) else "")
end

local function buildSheet(parent: Instance)
	local root = frame({
		Name = "Sheet",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0.45,
		BackgroundColor3 = Color3.new(0, 0, 0),
		Visible = false,
		Active = true,
		ZIndex = 60,
		Parent = parent,
	})
	local box = panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(440, 230),
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0.02,
		ZIndex = 61,
		Parent = root,
	})
	local scale = UI.Create("UIScale", { Parent = box })
	local title = text({
		Position = UDim2.fromOffset(20, 16),
		Size = UDim2.new(1, -40, 0, 26),
		FontFace = UI.Faces.Display,
		TextSize = 18,
		ZIndex = 62,
		Parent = box,
	})
	local body = text({
		Position = UDim2.fromOffset(20, 48),
		Size = UDim2.new(1, -40, 0, 40),
		TextWrapped = true,
		TextColor3 = Theme.Text2,
		ZIndex = 62,
		Parent = box,
	})
	local chipsHolder = frame({ Position = UDim2.fromOffset(20, 96), Size = UDim2.new(1, -40, 0, 36), Parent = box })
	local chips = UI.Segmented(chipsHolder, {
		{ Key = "10", Text = T("term.chip10") },
		{ Key = "25", Text = T("term.chip25") },
		{ Key = "Max", Text = T("trade.chipMax") },
	}, function(key: string)
		ticket.Chip = key
		ticket.Amount = "Chip"
		local side = sheetSide
		if side then
			local est = estimate(side)
			setText(body, if est then T("term.qtyPreview", int(est.Qty), price(est.Px)) else "")
		end
	end)
	local hint = text({
		Position = UDim2.new(0, 20, 1, -84),
		Size = UDim2.new(1, -40, 0, 18),
		TextSize = 12,
		TextColor3 = Theme.Muted,
		Text = T("term.sheet.padHint"),
		ZIndex = 62,
		Parent = box,
	})
	local yes = UI.Button({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 20, 1, -16),
		Size = UDim2.new(0.5, -26, 0, 48),
		Text = T("term.sheet.confirm"),
		Variant = "Success",
		MaxText = 16,
		ZIndex = 62,
		Parent = box,
	}, confirmSheet)
	local no = UI.Button({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -16),
		Size = UDim2.new(0.5, -26, 0, 48),
		Text = T("term.confirm.no"),
		Variant = "Secondary",
		MaxText = 16,
		ZIndex = 62,
		Parent = box,
	}, function()
		closeSheet()
	end)
	ui.Sheet = {
		Root = root,
		Box = box,
		Scale = scale,
		Title = title,
		Body = body,
		Chips = chips,
		Hint = hint,
		Yes = yes,
		No = no,
	}
end

-- ---------------------------------------------------------------------
-- WATCHLIST / FIRMEN-KARTEN
-- ---------------------------------------------------------------------
local function listIds(): { number }
	if listMode == "Depot" then
		local out: { number } = {}
		for _, i in ipairs(heldIds()) do
			if instOf(i) then
				table.insert(out, i)
			end
		end
		return out
	elseif listMode == "Watch" then
		local lists = watchLists()
		local list = lists[watchIndex] or {}
		local out: { number } = {}
		for _, i in ipairs(list) do
			if type(i) == "number" and allowed(i) then
				table.insert(out, i)
			end
		end
		return out
	end
	local ok, ids = call("MarketClient", "AllowedIds")
	return if ok and type(ids) == "table" then ids else {}
end

local function toggleWatch(i: number)
	local lists = watchLists()
	local count = math.max(1, math.floor(num(perks().Watchlists, 1)))
	local index = math.clamp(watchIndex, 1, count)
	local current = table.clone(lists[index] or {})
	local found = table.find(current, i)
	if found then
		table.remove(current, found)
	else
		local maxIds = num((trading().Watch or {}).MaxIds, 12)
		if #current >= maxIds then
			ctx.Toast(T("term.watch.full", maxIds), "Error")
			return
		end
		table.insert(current, i)
	end
	task.spawn(function()
		local reply = ctx.RequestFull("TradeWatch", { List = index, Ids = current })
		sfx(if reply.Ok then "UIClick" else "UIError")
	end)
end

local function isWatched(i: number): boolean
	for _, list in ipairs(watchLists()) do
		if type(list) == "table" and table.find(list, i) then
			return true
		end
	end
	return false
end

local function buildList(parent: Instance, onPick: ((i: number) -> ())?): { [string]: any }
	local simple = layer() == "Simple"
	local rowH = if simple then 64 else 52
	local holder = frame({ Name = "List", Size = UDim2.fromScale(1, 1), Parent = parent })
	local modes = UI.Segmented(holder, {
		{ Key = "All", Text = T("term.list.all") },
		{ Key = "Watch", Text = T("term.list.watchShort") },
		{ Key = "Depot", Text = T("term.list.depot") },
	}, function(key: string)
		listMode = key
		refreshAll()
	end)
	modes.Set(listMode)
	modes.Frame.Size = UDim2.new(1, 0, 0, 32)
	local watchCycler = UI.Button({
		Name = "WatchIndex",
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(1, 0, 0, 28),
		Text = "",
		Variant = "Ghost",
		MaxText = 13,
		Corner = 8,
		Parent = holder,
	}, function()
		local count = math.max(1, math.floor(num(perks().Watchlists, 1)))
		watchIndex = (watchIndex % count) + 1
		refreshAll()
	end)
	local list = scroller(holder, {
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 1, -40),
	})
	rowList(list, 6)
	UI.Create("UIPadding", { PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), Parent = list })
	local empty = text({
		Name = "Empty",
		Size = UDim2.new(1, 0, 0, 40),
		TextWrapped = true,
		TextSize = 13,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 0,
		Visible = false,
		Parent = list,
	})
	return {
		Holder = holder,
		Modes = modes,
		WatchCycler = watchCycler,
		List = list,
		Empty = empty,
		Rows = {},
		RowH = rowH,
		Simple = simple,
		OnPick = onPick,
		SparkClock = 0,
	}
end

local function listRow(view: { [string]: any }, index: number): { [string]: any }
	local rowH = view.RowH
	local button: TextButton = UI.Create("TextButton", {
		Name = "Row",
		Size = UDim2.new(1, 0, 0, rowH),
		BackgroundColor3 = Theme.Surface2,
		BackgroundTransparency = 0.15,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = index,
		Parent = view.List,
	}, { UI.Corner(10) })
	local stroke = UI.Create("UIStroke", {
		Color = Theme.Border,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = button,
	})
	local stripe = frame({
		Name = "Stripe",
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(0, 3, 1, -16),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Accent,
		Parent = button,
	})
	UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = stripe })
	local tickerLabel = text({
		Position = UDim2.fromOffset(46, if view.Simple then 8 else 6),
		Size = UDim2.new(0.45, -46, 0, 18),
		FontFace = UI.Faces.BodyBold,
		TextSize = 15,
		Parent = button,
	})
	local nameLabel = text({
		Position = UDim2.fromOffset(46, if view.Simple then 28 else 25),
		Size = UDim2.new(0.5, -46, 0, 14),
		TextSize = 11,
		TextColor3 = Theme.Muted,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = button,
	})
	local priceLabel = text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -30, 0, if view.Simple then 8 else 6),
		Size = UDim2.new(0.4, 0, 0, 18),
		FontFace = UI.Faces.MonoBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = button,
	})
	local changeLabel = text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -30, 0, if view.Simple then 28 else 25),
		Size = UDim2.new(0.4, 0, 0, 14),
		FontFace = UI.Faces.Mono,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		RichText = true,
		Parent = button,
	})
	local sparkHolder = frame({
		Name = "Spark",
		Position = UDim2.new(0.45, 0, 0, 6),
		Size = UDim2.new(0.18, 0, 0, 22),
		Parent = button,
	})
	local spark = UI.Sparkline(sparkHolder, 30)
	local mood = frame({
		Name = "Mood",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 46, 1, -8),
		Size = UDim2.fromOffset(8, 8),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Muted,
		Visible = view.Simple,
		Parent = button,
	})
	UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = mood })
	local moodText = text({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 58, 1, -4),
		Size = UDim2.new(0.6, -58, 0, 14),
		TextSize = 11,
		TextColor3 = Theme.Muted,
		Visible = view.Simple,
		Parent = button,
	})
	local star: TextButton = UI.Create("TextButton", {
		Name = "Star",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.fromOffset(24, 28),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.BodyBold,
		TextSize = 18,
		TextColor3 = Theme.Muted,
		Text = "☆",
		Parent = button,
	})
	local row = {
		Button = button,
		Stroke = stroke,
		Stripe = stripe,
		Ticker = tickerLabel,
		Name = nameLabel,
		Price = priceLabel,
		Change = changeLabel,
		Spark = spark,
		Mood = mood,
		MoodText = moodText,
		Star = star,
		Logo = nil :: Frame?,
		I = 0,
	}
	button.Activated:Connect(function()
		if row.I > 0 then
			sfx("UIClick")
			if view.OnPick then
				view.OnPick(row.I)
			else
				selectInst(row.I)
			end
		end
	end)
	star.Activated:Connect(function()
		if row.I > 0 then
			toggleWatch(row.I)
		end
	end)
	return row
end

local function updateList(view: { [string]: any }?, sparks: boolean)
	if not view then
		return
	end
	local ids = listIds()
	local watchCount = math.max(1, math.floor(num(perks().Watchlists, 1)))
	view.WatchCycler.Frame.Visible = listMode == "Watch" and watchCount > 1
	view.WatchCycler.SetText(T("term.list.watch", math.clamp(watchIndex, 1, watchCount)) .. "  ▸")
	local offset = if listMode == "Watch" and watchCount > 1 then 72 else 40
	if view.List.Position.Y.Offset ~= offset then
		view.List.Position = UDim2.fromOffset(0, offset)
		view.List.Size = UDim2.new(1, 0, 1, -offset)
	end
	view.Empty.Visible = #ids == 0
	setText(
		view.Empty,
		if listMode == "Watch"
			then T("term.watch.empty")
			elseif listMode == "Depot" then T("term.pos.empty")
			else T("mkt.notReady") -- noch kein Kurs-Frame (Beitritt, Markt startet)
	)
	for index, i in ipairs(ids) do
		local row = view.Rows[index]
		if not row then
			row = listRow(view, index)
			view.Rows[index] = row
		end
		local inst = instOf(i)
		if row.I ~= i then
			row.I = i
			if row.Logo then
				row.Logo:Destroy()
			end
			row.Logo = logo(row.Button, i, if view.Simple then 34 else 30, UDim2.new(0, 8, 0.5, 0))
			local ok, sector = call("MarketClient", "Sector", i)
			row.Stripe.BackgroundColor3 = if ok and type(sector) == "table" then sector.Color else Theme.Accent
			row.Spark.Set(table.create(0))
			sparks = true
		end
		setText(row.Ticker, if type(inst) == "table" then inst.Ticker else "?")
		setText(row.Name, if type(inst) == "table" then inst.Name else "")
		local close, change = quote(i)
		setText(row.Price, if close then price(close) else "–")
		if change then
			setText(
				row.Change,
				string.format(
					'<font color="%s">%s %s</font>',
					UI.ColorHex(UI.TrendColor(change)),
					UI.TrendArrow(change),
					pct(change)
				)
			)
		else
			setText(row.Change, "")
		end
		if sparks then
			local okSpark, points = call("MarketClient", "Spark", i)
			if okSpark and type(points) == "table" then
				row.Spark.Set(points)
			end
		end
		if view.Simple then
			-- Stimmungspunkt: Tiko-Ampel der letzten Meldung, sonst Tagestrend
			local okNews, item = call("NewsFeed", "LatestFor", i, true)
			local stateName = "none"
			if okNews and item then
				local okAmpel, value = call("NewsFeed", "Ampel", item)
				if okAmpel and type(value) == "string" then
					stateName = value
				end
			end
			local moodColor = Theme.Muted
			local moodKey = "term.mood.flat"
			if stateName == "up" or (stateName == "none" and change and change > 0.002) then
				moodColor, moodKey = UI.UpColor(), "term.mood.up"
			elseif stateName == "down" or (stateName == "none" and change and change < -0.002) then
				moodColor, moodKey = UI.DownColor(), "term.mood.down"
			elseif stateName == "rumor" or stateName == "expected" then
				moodColor, moodKey = Theme.Warn, "term.mood.unclear"
			end
			row.Mood.BackgroundColor3 = moodColor
			setText(row.MoodText, T(moodKey))
		end
		local watchedNow = isWatched(i)
		row.Star.Text = if watchedNow then "★" else "☆"
		row.Star.TextColor3 = if watchedNow then Theme.Gold else Theme.Muted
		local active = i == sel
		row.Stroke.Color = if active then Theme.Accent else Theme.Border
		row.Button.BackgroundColor3 = if active then Theme.Hover else Theme.Surface2
		row.Button.Visible = true
	end
	for index = #ids + 1, #view.Rows do
		local row = view.Rows[index]
		row.Button.Visible = false
	end
end

-- ---------------------------------------------------------------------
-- INSTRUMENT-KOPF
-- ---------------------------------------------------------------------
local function buildInstHeader(parent: Instance, compact: boolean): { [string]: any }
	local holder =
		frame({ Name = "InstHeader", Size = UDim2.new(1, 0, 0, if compact then 54 else 62), Parent = parent })
	local logoHolder = frame({ Size = UDim2.fromOffset(44, 44), Position = UDim2.new(0, 0, 0.5, -22), Parent = holder })
	local tickerLabel = text({
		Position = UDim2.fromOffset(54, 4),
		Size = UDim2.new(0.45, -54, 0, 24),
		FontFace = UI.Faces.Display,
		TextSize = if compact then 18 else 20,
		Parent = holder,
	})
	local nameLabel = text({
		Position = UDim2.fromOffset(54, if compact then 28 else 30),
		Size = UDim2.new(0.45, -54, 0, 16),
		TextSize = 12,
		TextColor3 = Theme.Text2,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = holder,
	})
	local chips = frame({
		Position = UDim2.fromOffset(54, if compact then 44 else 48),
		Size = UDim2.new(0.6, -54, 0, 14),
		Parent = holder,
	})
	rowList(chips, 6, true)
	local priceLabel = text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 2),
		Size = UDim2.new(0.5, 0, 0, 28),
		FontFace = UI.Faces.MonoBold,
		TextSize = if compact then 22 else 26,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = holder,
	})
	local changeLabel = text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, if compact then 30 else 32),
		Size = UDim2.new(0.5, 0, 0, 16),
		FontFace = UI.Faces.Mono,
		TextSize = 13,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = holder,
	})
	local spreadLabel = text({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, if compact then 44 else 48),
		Size = UDim2.new(0.5, 0, 0, 14),
		FontFace = UI.Faces.Mono,
		TextSize = 11,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = holder,
	})
	return {
		Holder = holder,
		LogoHolder = logoHolder,
		Logo = nil :: Frame?,
		Ticker = tickerLabel,
		Name = nameLabel,
		Chips = chips,
		ChipKey = "",
		Price = priceLabel,
		Change = changeLabel,
		Spread = spreadLabel,
		I = 0,
	}
end

local function updateInstHeader(h: { [string]: any }?)
	if not h then
		return
	end
	local i = sel
	if not i then
		setText(h.Ticker, T("term.selectInst"))
		return
	end
	local inst = instOf(i)
	if h.I ~= i then
		h.I = i
		if h.Logo then
			h.Logo:Destroy()
		end
		h.Logo = logo(h.LogoHolder, i, 44, UDim2.new(0, 0, 0.5, 0))
	end
	setText(h.Ticker, if type(inst) == "table" then inst.Ticker else "?")
	setText(h.Name, if type(inst) == "table" then inst.Name else "")
	local close, change = quote(i)
	setText(h.Price, if close then price(close) .. " AKY" else T("mkt.notReady"))
	if change then
		setText(
			h.Change,
			string.format(
				'<font color="%s">%s %s</font>  <font color="%s">%s</font>',
				UI.ColorHex(UI.TrendColor(change)),
				UI.TrendArrow(change),
				pct(change),
				UI.ColorHex(Theme.Muted),
				T("term.today")
			)
		)
	else
		setText(h.Change, "")
	end
	local bid, ask = bidAsk(i)
	setText(h.Spread, if bid and ask then T("term.bidAsk", price(bid), price(ask)) else "")
	-- Chips (Klasse, Sektor, Flags) nur bei Änderung neu
	local row = nil
	local okRow, value = call("MarketClient", "Row", i)
	if okRow then
		row = value
	end
	local flags = if type(row) == "table" then row.Flags else 0
	local isHalted = halted(i)
	local key = tostring(i) .. ":" .. tostring(flags) .. ":" .. tostring(isHalted) .. ":" .. lang()
	if key ~= h.ChipKey then
		h.ChipKey = key
		for _, child in ipairs(h.Chips:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local order = 0
		local function add(label: string, color: Color3)
			order += 1
			chip(h.Chips, label, color, order)
		end
		if type(inst) == "table" then
			add(T("mkt.class." .. tostring(inst.Class)), Theme.Text2)
			local okSector, sector = call("MarketClient", "Sector", i)
			if okSector and type(sector) == "table" then
				add(sector.Name, sector.Color)
			end
		end
		if isHalted then
			add(T("mkt.halted"), UI.DownColor())
		end
		if bit32.band(flags, 2) ~= 0 then
			add(T("term.flag.news"), Theme.Warn)
		end
		if bit32.band(flags, 4) ~= 0 then
			add(T("term.flag.exDay"), Theme.Purple)
		end
		if bit32.band(flags, 8) ~= 0 then
			add(T("mkt.profile.weekHigh"), UI.UpColor())
		end
	end
end

-- ---------------------------------------------------------------------
-- CHART-BEREICH (Werkzeugleiste + ChartView-Instanzen)
-- ---------------------------------------------------------------------
local function untrackAll()
	for _, entry in ipairs(views) do
		entry.Untrack()
		entry.View:Destroy()
	end
	table.clear(views)
end

local function chartLib(): any
	local modules = ctx.Modules
	return modules and modules.ChartView
end

local function trackView(entry: { View: any, I: number, Tf: string, Untrack: () -> (), Stale: boolean?, Role: string? })
	entry.Untrack()
	local view = entry.View
	view:SetData({}, entry.Tf)
	view:SetPlaceholder(T("mkt.historyLoading"))
	local ok, untrack = call("MarketClient", "Track", entry.I, entry.Tf, function(candles)
		if view.Alive then
			view:SetData(candles, entry.Tf)
			if #candles == 0 then
				view:SetPlaceholder(T("term.noData"))
			end
		end
	end)
	entry.Untrack = if ok and type(untrack) == "function" then untrack else function() end
end

local function chartMarks()
	local i = sel
	local main = views[1]
	if not main or not i then
		return
	end
	local alerts: { any } = {}
	local d = depot()
	if type(d.Alerts) == "table" then
		for _, alert in ipairs(d.Alerts) do
			if type(alert) == "table" and alert.I == i then
				table.insert(alerts, { Px = alert.Px, Dir = alert.Dir })
			end
		end
	end
	local marks: { any } = {}
	local q, avg = position(i)
	if q > 0 and avg > 0 then
		table.insert(marks, { Px = avg, Color = Theme.Text2, Text = T("term.mark.cost", price(math.floor(avg + 0.5))) })
	end
	if type(d.Orders) == "table" then
		for _, order in ipairs(d.Orders) do
			if type(order) == "table" and order.I == i then
				if type(order.Lim) == "number" then
					table.insert(marks, { Px = order.Lim, Color = Theme.Accent, Text = T("trade.typeLMT") })
				end
				if type(order.Stp) == "number" then
					table.insert(marks, { Px = order.Stp, Color = UI.DownColor(), Text = T("trade.typeSTP") })
				end
				if type(order.Tp) == "number" then
					table.insert(marks, { Px = order.Tp, Color = UI.UpColor(), Text = T("trade.typeTP") })
				end
			end
		end
	end
	for index, entry in ipairs(views) do
		if entry.I == i then
			entry.View:SetAlerts(alerts)
			entry.View:SetMarks(marks)
		elseif index > 1 then
			entry.View:SetAlerts({})
			entry.View:SetMarks({})
		end
	end
end

local function onPickPrice(pricePick: number)
	if not alarmMode then
		return
	end
	local i = sel
	if not i then
		return
	end
	local close = quote(i)
	local dir = if close and pricePick < close then "Down" else "Up"
	alarmMode = false
	refreshAll()
	task.spawn(function()
		local reply = ctx.RequestFull("AlertSet", { I = i, Px = pricePick, Dir = dir })
		sfx(if reply.Ok then "UIClick" else "UIError")
	end)
end

local function swipe(dir: number)
	local ids = listIds()
	if #ids == 0 then
		return
	end
	local index = table.find(ids, sel or -1) or 0
	index = ((index - 1 + dir) % #ids) + 1
	selectInst(ids[index])
end

local function multiIds(): { number }
	local out: { number } = {}
	if sel then
		table.insert(out, sel)
	end
	for _, i in ipairs(listIds()) do
		if #out >= 4 then
			break
		end
		if not table.find(out, i) then
			table.insert(out, i)
		end
	end
	local ok, ids = call("MarketClient", "AllowedIds")
	if ok and type(ids) == "table" then
		for _, i in ipairs(ids) do
			if #out >= 4 then
				break
			end
			if not table.find(out, i) then
				table.insert(out, i)
			end
		end
	end
	return out
end

local function buildCharts()
	untrackAll()
	local host: Frame? = ui.ChartHost
	local lib = chartLib()
	if not host or not lib or not sel then
		return
	end
	for _, child in ipairs(host:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local mode = chartMode
	if layoutKind == "Phone" or licence() < traderFrom() then
		mode = "Single"
	end
	if mode == "Multi" and not perks().MultiChart then
		mode = "Single"
	end
	local style = currentStyle()
	local tf = currentTf()
	local indicators = indicatorMap()
	local candles = if layoutKind == "Phone" then 60 else math.clamp(quality("Candles", 90), 60, 120)
	local function add(
		slot: Frame,
		i: number,
		tfUse: string,
		n: number,
		labels: boolean,
		interactive: boolean,
		role: string?
	)
		local view = lib.new(slot, {
			Candles = n,
			Volume = true,
			Style = style,
			Labels = labels,
			AreaFill = areaFill(),
			MaxLines = maxLines(),
			OnPick = if interactive then onPickPrice else nil,
			OnSwipe = if interactive and layoutKind == "Phone" then swipe else nil,
		})
		view:SetIndicators(if interactive then indicators else {})
		view:SetPickMode(interactive and alarmMode)
		local entry = { View = view, I = i, Tf = tfUse, Untrack = function() end, Role = role or "Main" }
		table.insert(views, entry)
		trackView(entry)
	end
	if mode == "Single" then
		local slot = frame({ Size = UDim2.fromScale(1, 1), Parent = host })
		add(slot, sel, tf, candles, true, true)
	elseif mode == "Split" then
		local left = frame({ Size = UDim2.new(0.5, -4, 1, 0), Parent = host })
		local right = frame({ Position = UDim2.new(0.5, 4, 0, 0), Size = UDim2.new(0.5, -4, 1, 0), Parent = host })
		add(left, sel, tf, math.min(candles, 90), true, true)
		local second = if tf == "1T" then "15m" else "1T"
		add(right, sel, second, 60, true, false, "Second")
	else
		local ids = multiIds()
		for index, i in ipairs(ids) do
			local col = (index - 1) % 2
			local rowIndex = (index - 1) // 2
			local slot = frame({
				Position = UDim2.new(
					col * 0.5,
					if col == 1 then 4 else 0,
					rowIndex * 0.5,
					if rowIndex == 1 then 4 else 0
				),
				Size = UDim2.new(0.5, -4, 0.5, -4),
				Parent = host,
			})
			add(slot, i, tf, 60, true, index == 1)
		end
	end
	chartMarks()
end

local function buildToolbar(parent: Instance, compact: boolean): { [string]: any }
	local holder = frame({ Name = "Toolbar", Size = UDim2.new(1, 0, 0, 70), Parent = parent })
	local tfHolder = frame({ Size = UDim2.new(if compact then 1 else 0.58, -4, 0, 32), Parent = holder })
	local tfOptions: { any } = {}
	for _, tf in ipairs(allowedTfs()) do
		table.insert(tfOptions, { Key = tf, Text = T("term.tf." .. tf) })
	end
	local tfSeg = UI.Segmented(tfHolder, tfOptions, function(key: string)
		call("Settings", "Set", "ChartTf", key)
	end)
	tfSeg.Frame.Size = UDim2.fromScale(1, 1)
	tfSeg.Set(currentTf())
	local styleHolder = frame({
		Position = if compact then UDim2.fromOffset(0, 36) else UDim2.new(0.58, 4, 0, 0),
		Size = if compact then UDim2.new(1, 0, 0, 30) else UDim2.new(0.42, -4, 0, 32),
		Parent = holder,
	})
	local styleOptions: { any } = {}
	for _, style in ipairs(allowedStyles()) do
		table.insert(styleOptions, { Key = style, Text = T("term.style." .. style) })
	end
	local styleSeg = UI.Segmented(styleHolder, styleOptions, function(key: string)
		call("Settings", "Set", "ChartType", key)
	end)
	styleSeg.Frame.Size = UDim2.fromScale(1, 1)
	styleSeg.Set(currentStyle())
	-- Indikatoren + Alarm + Split/Multi
	local indRow = scroller(holder, {
		Position = UDim2.fromOffset(0, if compact then 70 else 38),
		Size = UDim2.new(1, 0, 0, 30),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0,
	})
	rowList(indRow, 6, true)
	if compact then
		holder.Size = UDim2.new(1, 0, 0, 102)
	end
	local chips: { [string]: any } = {}
	local chipColors: { [string]: Color3 } = {}
	local order = 0
	for _, name in ipairs(allowedIndicators()) do
		order += 1
		local color = (chartLib() and chartLib().Colors[name])
			or ((chartLib() and chartLib().Colors.RSI) or Theme.Accent)
		local b = UI.Button({
			Name = name,
			Size = UDim2.fromOffset(if string.len(name) > 4 then 76 else 62, 26),
			Text = T("term.ind." .. name),
			Variant = "Secondary",
			MaxText = 12,
			Corner = 8,
			LayoutOrder = order,
			Parent = indRow,
		}, function()
			local current = settings().Indicators
			local on = type(current) == "table" and current[name] == true
			if not on then
				local active = indicatorMap()
				local count = 0
				for _ in pairs(active) do
					count += 1
				end
				if count >= maxLines() then
					ctx.Toast(T("term.ind.max", maxLines()), "Info")
					return
				end
				-- nur ein Indikator-Feld (RSI/MACD/Stoch/ATR)
				if PANE_INDICATORS[name] and type(current) == "table" then
					for other in pairs(PANE_INDICATORS) do
						if other ~= name and current[other] == true then
							call("Settings", "Set", "Indicators." .. other, false)
						end
					end
				end
			end
			call("Settings", "Set", "Indicators." .. name, not on)
		end)
		b.Stroke.Color = color
		chips[name] = b
		chipColors[name] = color
	end
	order += 1
	local alarm = UI.Button({
		Name = "Alarm",
		Size = UDim2.fromOffset(110, 26),
		Text = T("term.alarm"),
		Variant = "Ghost",
		MaxText = 12,
		Corner = 8,
		LayoutOrder = order,
		Parent = indRow,
	}, function()
		alarmMode = not alarmMode
		for _, entry in ipairs(views) do
			entry.View:SetPickMode(alarmMode and entry.I == sel)
		end
		if alarmMode then
			ctx.Toast(T("term.alarm.mode"), "Info")
		end
		refreshAll()
	end)
	local split: any = nil
	if layoutKind == "PC" and licence() >= traderFrom() then
		order += 1
		split = UI.Button({
			Name = "Split",
			Size = UDim2.fromOffset(70, 26),
			Text = T("term.split"),
			Variant = "Ghost",
			MaxText = 12,
			Corner = 8,
			LayoutOrder = order,
			Parent = indRow,
		}, function()
			if chartMode == "Single" then
				chartMode = "Split"
			elseif chartMode == "Split" and perks().MultiChart then
				chartMode = "Multi"
			else
				chartMode = "Single"
			end
			buildCharts()
			refreshAll()
		end)
	end
	return {
		Holder = holder,
		Tf = tfSeg,
		Style = styleSeg,
		Chips = chips,
		ChipColors = chipColors,
		Alarm = alarm,
		Split = split,
	}
end

local function updateToolbar(tb: { [string]: any }?)
	if not tb then
		return
	end
	tb.Tf.Set(currentTf())
	tb.Style.Set(currentStyle())
	local active = indicatorMap()
	for name, b in pairs(tb.Chips) do
		b.SetVariant(if active[name] then "Primary" else "Secondary")
		-- Rahmen in der Linienfarbe des Indikators (wie js/chart.js) – SetVariant setzt den Rahmen zurück
		local color = tb.ChipColors and tb.ChipColors[name]
		if color and b.Stroke.Color ~= color then
			b.Stroke.Color = color
		end
	end
	local alerts = depot().Alerts
	local count = if type(alerts) == "table" then #alerts else 0
	tb.Alarm.SetText(if alarmMode then T("term.alarm.cancel") else T("term.alarm.short", count, num(perks().Alerts, 3)))
	tb.Alarm.SetVariant(if alarmMode then "Premium" else "Ghost")
	if tb.Split then
		tb.Split.SetText(
			if chartMode == "Single"
				then T("term.split")
				elseif chartMode == "Split" then T("term.multi")
				else T("term.single")
		)
	end
end

-- ---------------------------------------------------------------------
-- ORDER-TICKET
-- ---------------------------------------------------------------------
local function buildTicket(parent: Instance, withButtons: boolean): { [string]: any }
	local list = scroller(parent)
	rowList(list, 8)
	UI.Create("UIPadding", { PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8), Parent = list })
	local holding = text({
		Name = "Holding",
		Size = UDim2.new(1, 0, 0, 34),
		TextWrapped = true,
		RichText = true,
		FontFace = UI.Faces.Mono,
		TextSize = 12,
		TextColor3 = Theme.Text2,
		LayoutOrder = 1,
		Parent = list,
	})
	local typeButton = UI.Button({
		Name = "Type",
		Size = UDim2.new(1, 0, 0, 34),
		Text = "",
		Variant = "Secondary",
		MaxText = 14,
		Corner = 10,
		LayoutOrder = 2,
		Parent = list,
	}, function()
		local types = allowedTypes()
		local index = table.find(types, ticket.Type) or 1
		ticket.Type = types[(index % #types) + 1]
		local i = sel
		if i then
			local bid, _, mid = bidAsk(i)
			local protect = trading().Protect or { Sl = 0.08, Tp = 0.15 }
			if bid and mid then
				ticket.Lim = price(mid)
				ticket.Stp = price(math.floor(bid * (1 - num(protect.Sl, 0.08))))
				ticket.Tp = price(math.ceil(bid * (1 + num(protect.Tp, 0.15))))
			end
		end
		refreshAll()
	end)
	local explain = text({
		Name = "Explain",
		Size = UDim2.new(1, 0, 0, 30),
		TextWrapped = true,
		TextSize = 12,
		TextColor3 = Theme.Muted,
		LayoutOrder = 3,
		Parent = list,
	})
	-- Preisfelder
	local fields: { [string]: TextBox } = {}
	local fieldRows: { [string]: Frame } = {}
	for index, key in ipairs({ "Lim", "Stp", "Tp", "Trl" }) do
		local rowFrame = frame({ Name = key, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 3 + index, Parent = list })
		text({
			Size = UDim2.new(0.45, 0, 1, 0),
			TextSize = 13,
			TextColor3 = Theme.Text2,
			Text = T("term.field." .. key),
			Parent = rowFrame,
		})
		local box = UI.TextBox({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0.55, 0, 1, 0),
			Text = (ticket :: any)[key],
			FontFace = UI.Faces.Mono,
			Parent = rowFrame,
		})
		box.FocusLost:Connect(function()
			(ticket :: any)[key] = box.Text
			refreshAll()
		end)
		fields[key] = box
		fieldRows[key] = rowFrame
	end
	-- Betrag: Chips 10 % · 25 % · Max (+ freier Betrag ab Trader)
	local chipHolder = frame({ Name = "Chips", Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 10, Parent = list })
	local chips = UI.Segmented(chipHolder, {
		{ Key = "10", Text = T("term.chip10") },
		{ Key = "25", Text = T("term.chip25") },
		{ Key = "Max", Text = T("trade.chipMax") },
	}, function(key: string)
		ticket.Chip = key
		ticket.Amount = "Chip"
		refreshAll()
	end)
	chips.Frame.Size = UDim2.fromScale(1, 1)
	local amountRow = frame({ Name = "Amount", Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 11, Parent = list })
	local amountMode = UI.Button({
		Size = UDim2.new(0.42, -4, 1, 0),
		Text = "",
		Variant = "Ghost",
		MaxText = 12,
		Corner = 8,
		Parent = amountRow,
	}, function()
		ticket.Amount = if ticket.Amount == "Qty" then "Aky" elseif ticket.Amount == "Aky" then "Chip" else "Qty"
		refreshAll()
	end)
	local amountBox = UI.TextBox({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.58, 0, 1, 0),
		Text = ticket.AmountText,
		PlaceholderText = "",
		FontFace = UI.Faces.Mono,
		Parent = amountRow,
	})
	amountBox.FocusLost:Connect(function()
		ticket.AmountText = amountBox.Text
		if ticket.Amount == "Chip" and amountBox.Text ~= "" then
			ticket.Amount = "Qty"
		end
		refreshAll()
	end)
	-- Schutz an (−8 % / +15 %), Laufzeit
	local protect = UI.Button({
		Name = "Protect",
		Size = UDim2.new(1, 0, 0, 32),
		Text = "",
		Variant = "Secondary",
		MaxText = 13,
		Corner = 10,
		LayoutOrder = 12,
		Parent = list,
	}, function()
		ticket.Protect = not ticket.Protect
		refreshAll()
	end)
	local expHolder = frame({ Name = "Exp", Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 13, Parent = list })
	local exp = UI.Segmented(expHolder, {
		{ Key = "24H", Text = T("trade.exp24") },
		{ Key = "DAY", Text = T("trade.expDay") },
	}, function(key: string)
		ticket.Exp = key
	end)
	exp.Frame.Size = UDim2.fromScale(1, 1)
	exp.Set(ticket.Exp)
	local preview = text({
		Name = "Preview",
		Size = UDim2.new(1, 0, 0, 34),
		TextWrapped = true,
		FontFace = UI.Faces.Mono,
		TextSize = 12,
		RichText = true,
		LayoutOrder = 14,
		Parent = list,
	})
	local cluster = text({
		Name = "Cluster",
		Size = UDim2.new(1, 0, 0, 30),
		TextWrapped = true,
		TextSize = 12,
		TextColor3 = Theme.Warn,
		Visible = false,
		LayoutOrder = 15,
		Parent = list,
	})
	local buy: any = nil
	local sell: any = nil
	if withButtons then
		local buttons = frame({ Name = "Buttons", Size = UDim2.new(1, 0, 0, 50), LayoutOrder = 16, Parent = list })
		buy = UI.Button({
			Size = UDim2.new(0.5, -4, 1, 0),
			Text = T("trade.buy"),
			Variant = "Success",
			MaxText = 18,
			Face = "Display",
			Parent = buttons,
		}, function()
			place("B")
		end)
		sell = UI.Button({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0.5, -4, 1, 0),
			Text = T("trade.sell"),
			Variant = "Danger",
			MaxText = 18,
			Face = "Display",
			Parent = buttons,
		}, function()
			place("S")
		end)
		ui.BuyButton = buy
		ui.SellButton = sell
	end
	-- Tiko-Ampel + Glossar
	local ampel = panel({ Name = "Ampel", Size = UDim2.new(1, 0, 0, 52), LayoutOrder = 17, Parent = list })
	local ampelDot = frame({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Muted,
		Parent = ampel,
	})
	UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = ampelDot })
	local ampelSymbol = text({
		Size = UDim2.fromScale(1, 1),
		FontFace = UI.Faces.BodyBold,
		TextSize = 12,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = ampelDot,
	})
	local ampelTitle = text({
		Position = UDim2.fromOffset(40, 6),
		Size = UDim2.new(1, -50, 0, 16),
		FontFace = UI.Faces.BodyBold,
		TextSize = 12,
		TextColor3 = Theme.Text2,
		Parent = ampel,
	})
	local ampelText = text({
		Position = UDim2.fromOffset(40, 22),
		Size = UDim2.new(1, -50, 0, 26),
		TextWrapped = true,
		TextSize = 12,
		Parent = ampel,
	})
	local ampelToggle = UI.Button({
		Name = "AmpelToggle",
		Size = UDim2.new(1, 0, 0, 26),
		Text = "",
		Variant = "Ghost",
		MaxText = 12,
		Corner = 8,
		LayoutOrder = 18,
		Parent = list,
	}, function()
		ampelOn = not ampelOn
		refreshAll()
	end)
	local gloss = text({
		Name = "Gloss",
		Size = UDim2.new(1, 0, 0, 30),
		TextWrapped = true,
		TextSize = 12,
		TextColor3 = Theme.Muted,
		LayoutOrder = 19,
		Parent = list,
	})
	return {
		List = list,
		Holding = holding,
		Type = typeButton,
		Explain = explain,
		Fields = fields,
		FieldRows = fieldRows,
		Chips = chips,
		AmountRow = amountRow,
		AmountMode = amountMode,
		AmountBox = amountBox,
		Protect = protect,
		ExpHolder = expHolder,
		Exp = exp,
		Preview = preview,
		Cluster = cluster,
		Buy = buy,
		Sell = sell,
		Ampel = ampel,
		AmpelDot = ampelDot,
		AmpelSymbol = ampelSymbol,
		AmpelTitle = ampelTitle,
		AmpelText = ampelText,
		AmpelToggle = ampelToggle,
		Gloss = gloss,
	}
end

local function updateAmpel(t: { [string]: any })
	local visible = ampelVisible() and sel ~= nil
	t.Ampel.Visible = visible
	t.AmpelToggle.Visible = layer() == "Trader"
	t.AmpelToggle.SetText(T(if ampelOn then "term.ampel.hide" else "term.ampel.show"))
	if not visible or not sel then
		return
	end
	local okItem, item = call("NewsFeed", "LatestFor", sel, true)
	local stateName, message = "none", T("term.ampel.none")
	if okItem and item then
		local ok, s, m = call("NewsFeed", "Ampel", item)
		if ok and type(s) == "string" then
			stateName = s
			if type(m) == "string" then
				message = m
			end
		end
	end
	local color = Theme.Muted
	local symbol = "•"
	if stateName == "up" then
		color, symbol = UI.UpColor(), "▲"
	elseif stateName == "down" then
		color, symbol = UI.DownColor(), "▼"
	elseif stateName == "rumor" or stateName == "expected" then
		color, symbol = Theme.Warn, "?"
	elseif stateName == "wait" then
		color, symbol = Theme.Accent, "…"
	end
	t.AmpelDot.BackgroundColor3 = color
	setText(t.AmpelSymbol, symbol)
	setText(t.AmpelTitle, T("term.ampel.title"))
	setText(t.AmpelText, message)
end

local function updateTicket(t: { [string]: any }?)
	if not t then
		return
	end
	local i = sel
	local l = layer()
	local trader = licence() >= traderFrom()
	-- Bestand
	if i then
		local q, avg = position(i)
		if q > 0 then
			local bid = bidAsk(i) or avg
			local pnl = q * bid - q * avg
			setText(
				t.Holding,
				T("term.holding", int(q), price(math.floor(avg + 0.5)))
					.. "\n"
					.. string.format(
						'<font color="%s">%s</font>',
						UI.ColorHex(UI.TrendColor(pnl)),
						T("term.pnl", aky(math.floor(pnl + 0.5), true), pct(if avg > 0 then pnl / (q * avg) else 0))
					)
			)
		else
			setText(t.Holding, T("term.noHolding") .. "\n" .. T("term.free", aky(freeCash(), true)))
		end
	else
		setText(t.Holding, T("term.selectInst"))
	end
	-- Ordertyp nur aus der Lizenz-Liste
	if not table.find(allowedTypes(), ticket.Type) then
		ticket.Type = "MKT"
	end
	t.Type.SetText(T("term.type") .. ": " .. T(TYPE_KEY[ticket.Type] or "trade.typeMKT") .. "  ▸")
	setText(t.Explain, T(EXPLAIN_KEY[ticket.Type] or "term.explainMKT"))
	local otype = ticket.Type
	local need = {
		Lim = otype == "LMT",
		Stp = otype == "STP" or otype == "OCO",
		Tp = otype == "TP" or otype == "OCO",
		Trl = otype == "TRL",
	}
	for key, rowFrame in pairs(t.FieldRows) do
		rowFrame.Visible = need[key] == true
		local box: TextBox = t.Fields[key]
		if not box:IsFocused() then
			local value = (ticket :: any)[key]
			if box.Text ~= value then
				box.Text = value
			end
		end
	end
	t.Chips.Set(ticket.Chip)
	t.AmountRow.Visible = trader
	if not trader and ticket.Amount ~= "Chip" then
		ticket.Amount = "Chip"
	end
	t.AmountMode.SetText(
		if ticket.Amount == "Qty"
			then T("term.amount.qty")
			elseif ticket.Amount == "Aky" then T("term.amount.aky")
			else T("term.amount.chip")
	)
	t.AmountBox.PlaceholderText = T(if ticket.Amount == "Aky" then "term.amount.akyHint" else "term.amount.qtyHint")
	local protectable = otype == "MKT" or otype == "LMT"
	t.Protect.Frame.Visible = protectable
	t.Protect.SetText(if ticket.Protect then T("trade.protectOn") else T("term.protectOff"))
	t.Protect.SetVariant(if ticket.Protect then "Primary" else "Secondary")
	t.ExpHolder.Visible = otype ~= "MKT"
	t.Exp.Set(ticket.Exp)
	-- Kosten-Vorschau (Kauf) bzw. Erlös (Verkauf bei Schutz-Ordern)
	local side = if SELL_ONLY[otype] then "S" else "B"
	local est = estimate(side)
	if est and est.Qty > 0 then
		if side == "B" then
			setText(
				t.Preview,
				T("trade.costPreview", aky(est.Cost), aky(est.Fee))
					.. "\n"
					.. T("term.qtyPreview", int(est.Qty), price(est.Px))
					.. " · "
					.. T("term.spread", aky(est.Spread))
			)
		else
			setText(
				t.Preview,
				T("term.proceeds", aky(est.Proceeds), aky(est.Fee))
					.. "\n"
					.. T("term.qtyPreview", int(est.Qty), price(est.Px))
			)
		end
	elseif est then
		setText(t.Preview, T(if side == "S" then "term.noShares" else "term.qtyZero"))
	else
		setText(t.Preview, T("mkt.notReady"))
	end
	-- Klumpen-Warnung (Risiko-Büro L2: ab 15 %)
	if i then
		local q = position(i)
		local bid = bidAsk(i) or 0
		local weight = q * bid / math.max(1, nav())
		local threshold = if num(perks().Risk, 0) >= 2 then 0.15 else num(trading().ConfirmAbove, 0.20)
		local show = weight >= threshold and instOf(i) and instOf(i).Class ~= "ETF"
		t.Cluster.Visible = show == true
		if show then
			setText(t.Cluster, T("term.cluster", pct(weight, 0):gsub("^%+", ""), tickerOf(i)))
		end
	else
		t.Cluster.Visible = false
	end
	-- Knöpfe
	local blocked = i == nil or halted(i) or not allowed(i)
	if t.Buy then
		t.Buy.SetText(T("trade.buy"))
		t.Sell.SetText(T("trade.sell"))
		t.Buy.SetVariant(if blocked or SELL_ONLY[otype] then "Muted" else "Success")
		t.Sell.SetVariant(if blocked then "Muted" else "Danger")
	end
	updateAmpel(t)
	t.Gloss.Visible = l == "Simple"
	if l == "Simple" then
		setText(t.Gloss, T("term.gloss." .. tostring(glossIndex)))
	end
end

-- ---------------------------------------------------------------------
-- KALENDER (ab Trader I)
-- ---------------------------------------------------------------------
local function buildCalendar(parent: Instance): { [string]: any }
	local list = scroller(parent)
	rowList(list, 4)
	local hint = text({
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 12,
		TextColor3 = Theme.Muted,
		LayoutOrder = 0,
		Parent = list,
	})
	return { List = list, Hint = hint, Rows = {} }
end

local function updateCalendar(c: { [string]: any }?)
	if not c then
		return
	end
	if licence() < traderFrom() then
		setText(c.Hint, T("term.cal.locked"))
		for _, row in ipairs(c.Rows) do
			row.Frame.Visible = false
		end
		return
	end
	local ok, items = call("NewsFeed", "Calendar")
	items = if ok and type(items) == "table" then items else {}
	setText(c.Hint, if #items == 0 then T("term.cal.empty") else T("term.cal.hint"))
	local okTick, tick = pcall(ctx.Clock.Tick)
	local now = if okTick then tick else 0
	local shown = 0
	local held = heldIds()
	for _, item in ipairs(items) do
		if shown >= 30 then
			break
		end
		shown += 1
		local row = c.Rows[shown]
		if not row then
			local rowFrame = UI.RowCard(c.List, shown, 32)
			row = {
				Frame = rowFrame,
				When = text({
					Position = UDim2.fromOffset(10, 0),
					Size = UDim2.new(0.22, -10, 1, 0),
					FontFace = UI.Faces.Mono,
					TextSize = 12,
					TextColor3 = Theme.Accent,
					Parent = rowFrame,
				}),
				What = text({
					Position = UDim2.new(0.22, 0, 0, 0),
					Size = UDim2.new(0.78, -10, 1, 0),
					TextSize = 13,
					RichText = true,
					Parent = rowFrame,
				}),
			}
			c.Rows[shown] = row
		end
		local left = math.max(0, num(item.T, now) - now)
		local okDur, dur = pcall(ctx.Format.Duration, left, lang())
		setText(row.When, T("term.cal.in", if okDur then dur else tostring(left)))
		local label = T(tostring(item.Key))
		if type(item.I) == "number" then
			local ticker = tickerOf(item.I)
			local mine = table.find(held, item.I) ~= nil or isWatched(item.I)
			label = string.format(
				"<b>%s</b> · %s%s",
				ticker,
				label,
				if mine then string.format('  <font color="%s">★</font>', UI.ColorHex(Theme.Gold)) else ""
			)
		end
		setText(row.What, label)
		row.Frame.Visible = true
	end
	for index = shown + 1, #c.Rows do
		c.Rows[index].Frame.Visible = false
	end
end

-- ---------------------------------------------------------------------
-- ANALYSE (Glossar · Markt-Stimmung · Heatmap · Körbe · Profil · Korrelation · Markttiefe · Umsätze)
-- ---------------------------------------------------------------------
local function moodScore(): (number, number)
	local ok, ids = call("MarketClient", "Ids")
	ids = if ok and type(ids) == "table" then ids else {}
	local up, count, sum = 0, 0, 0
	for _, i in ipairs(ids) do
		if i >= 1 and i <= 36 then
			local _, change = quote(i)
			if change then
				count += 1
				sum += change
				if change > 0 then
					up += 1
				end
			end
		end
	end
	local okRegime, regime = call("MarketClient", "Regime")
	local r = if okRegime and type(regime) == "number" then regime else 1
	if count == 0 then
		return 50, r
	end
	local breadth = up / count
	local avg = sum / count
	return math.clamp(50 + 900 * avg + 40 * (breadth - 0.5) - 12 * (r - 1), 0, 100), r
end

local function buildAnalysis(parent: Instance): { [string]: any }
	local list = scroller(parent)
	rowList(list, 10)
	UI.Create("UIPadding", { PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 10), Parent = list })
	local a: { [string]: any } = { List = list }
	-- Markt-Stimmung (Angst & Gier aus dem Frame) + Wetter
	UI.Section(list, T("term.moodTitle"), 1)
	local mood = panel({ Size = UDim2.new(1, 0, 0, 56), LayoutOrder = 2, Parent = list })
	local bar = UI.Bar({
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.new(1, -24, 0, 18),
		Parent = mood,
	})
	a.MoodBar = bar
	a.MoodText = text({
		Position = UDim2.fromOffset(12, 32),
		Size = UDim2.new(1, -24, 0, 18),
		TextSize = 12,
		TextColor3 = Theme.Text2,
		Parent = mood,
	})
	local l = layer()
	if l == "Simple" then
		UI.Section(list, T("term.glossTitle"), 3)
		local glossList = text({
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			TextSize = 13,
			TextColor3 = Theme.Text2,
			LayoutOrder = 4,
			Parent = list,
		})
		a.GlossList = glossList
		UI.Section(list, T("term.analysis.more"), 5)
		a.Locked = text({
			Size = UDim2.new(1, 0, 0, 22),
			TextSize = 12,
			TextColor3 = Theme.Muted,
			LayoutOrder = 6,
			Text = T("term.analysis.locked", T("term.lic.4")),
			Parent = list,
		})
		return a
	end
	-- Sektor-Heatmap 6×6 (Trader+)
	UI.Section(list, T("term.heatmap"), 10)
	local heat = frame({ Size = UDim2.new(1, 0, 0, 6 * 34), LayoutOrder = 11, Parent = list })
	local cells: { { Frame: Frame, Label: TextLabel, I: number } } = {}
	local companies = ctx.Config.Companies
	local sectors = type(companies) == "table" and companies.Sectors or {}
	for col, sector in ipairs(sectors) do
		local members: { number } = {}
		for _, inst in ipairs(companies.Instruments or {}) do
			if inst.Sector == sector.Key and not inst.Ipo and inst.Id <= 36 then
				table.insert(members, inst.Id)
			end
		end
		for rowIndex, i in ipairs(members) do
			if rowIndex > 6 then
				break
			end
			local cellFrame = frame({
				Position = UDim2.new((col - 1) / 6, 2, (rowIndex - 1) / 6, 2),
				Size = UDim2.new(1 / 6, -4, 1 / 6, -4),
				BackgroundTransparency = 0.3,
				BackgroundColor3 = Theme.Surface2,
				Parent = heat,
			})
			UI.Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = cellFrame })
			local label = text({
				Size = UDim2.fromScale(1, 1),
				FontFace = UI.Faces.MonoBold,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Center,
				RichText = true,
				Parent = cellFrame,
			})
			local button: TextButton = UI.Create("TextButton", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "",
				Parent = cellFrame,
			})
			button.Activated:Connect(function()
				if allowed(i) then
					selectInst(i)
				end
			end)
			table.insert(cells, { Frame = cellFrame, Label = label, I = i })
		end
	end
	a.Cells = cells
	-- Themen-Körbe (ab Trader I)
	UI.Section(list, T("term.basket"), 12)
	local baskets = type(companies) == "table" and companies.Baskets or {}
	local order = 12
	for _, basket in ipairs(baskets) do
		order += 1
		local card = UI.RowCard(list, order, 44)
		local names: { string } = {}
		for _, member in ipairs(basket.Members or {}) do
			table.insert(names, tickerOf(member))
		end
		text({
			Position = UDim2.fromOffset(12, 4),
			Size = UDim2.new(1, -200, 0, 18),
			FontFace = UI.Faces.BodyBold,
			TextSize = 13,
			Text = ctx.Lang.Pick(lang(), basket.Name),
			Parent = card,
		})
		text({
			Position = UDim2.fromOffset(12, 22),
			Size = UDim2.new(1, -200, 0, 16),
			FontFace = UI.Faces.Mono,
			TextSize = 11,
			TextColor3 = Theme.Muted,
			Text = table.concat(names, " · "),
			Parent = card,
		})
		local actions = UI.RowActions(card, 180)
		for index, value in ipairs({ 10, 25 }) do
			UI.Button({
				Size = UDim2.fromOffset(84, 30),
				Text = T("term.basket.buy", if value == 10 then T("term.chip10") else T("term.chip25")),
				Variant = "Success",
				MaxText = 12,
				Corner = 8,
				LayoutOrder = index,
				Parent = actions,
			}, function()
				local reply = ctx.RequestFull("TradeBasket", { Basket = basket.Key, Pct = value, Seq = nextSeq() })
				sfx(if reply.Ok then "Buy" else "UIError")
			end)
		end
	end
	if l ~= "Pro" then
		order += 1
		a.Locked = text({
			Size = UDim2.new(1, 0, 0, 22),
			TextSize = 12,
			TextColor3 = Theme.Muted,
			LayoutOrder = order,
			Text = T("term.analysis.locked", T("term.lic.7")),
			Parent = list,
		})
		return a
	end
	-- Profi: Firmenprofil, Analysten, Korrelation, Markttiefe, Umsätze
	UI.Section(list, T("term.profile"), 40)
	a.Profile = text({
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		RichText = true,
		FontFace = UI.Faces.Mono,
		TextSize = 12,
		TextColor3 = Theme.Text2,
		LayoutOrder = 41,
		Parent = list,
	})
	a.Correlation = text({
		Size = UDim2.new(1, 0, 0, 20),
		FontFace = UI.Faces.Mono,
		TextSize = 12,
		TextColor3 = Theme.Text2,
		LayoutOrder = 42,
		Parent = list,
	})
	UI.Section(list, T("term.depth") .. " · " .. T("term.simulated"), 43)
	local depth = frame({ Size = UDim2.new(1, 0, 0, 6 * 18 + 4), LayoutOrder = 44, Parent = list })
	local depthRows: { { Bid: TextLabel, Ask: TextLabel, BidBar: Frame, AskBar: Frame } } = {}
	for k = 1, 6 do
		local y = (k - 1) * 18
		local bidBar = frame({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(0.5, -2, 0, y + 2),
			Size = UDim2.new(0, 0, 0, 14),
			BackgroundTransparency = 0.7,
			BackgroundColor3 = UI.UpColor(),
			Parent = depth,
		})
		local askBar = frame({
			Position = UDim2.new(0.5, 2, 0, y + 2),
			Size = UDim2.new(0, 0, 0, 14),
			BackgroundTransparency = 0.7,
			BackgroundColor3 = UI.DownColor(),
			Parent = depth,
		})
		local bidLabel = text({
			Position = UDim2.new(0, 0, 0, y),
			Size = UDim2.new(0.5, -6, 0, 18),
			FontFace = UI.Faces.Mono,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 2,
			Parent = depth,
		})
		local askLabel = text({
			Position = UDim2.new(0.5, 6, 0, y),
			Size = UDim2.new(0.5, -6, 0, 18),
			FontFace = UI.Faces.Mono,
			TextSize = 11,
			ZIndex = 2,
			Parent = depth,
		})
		table.insert(depthRows, { Bid = bidLabel, Ask = askLabel, BidBar = bidBar, AskBar = askBar })
	end
	a.Depth = depthRows
	UI.Section(list, T("term.trades") .. " · " .. T("term.simulated"), 45)
	a.Tape = text({
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		RichText = true,
		FontFace = UI.Faces.Mono,
		TextSize = 11,
		TextColor3 = Theme.Text2,
		LayoutOrder = 46,
		Parent = list,
	})
	return a
end

local function requestProfile(i: number)
	local cached = profileCache[i]
	if (cached and os.clock() - cached.At < PROFILE_TTL) or profileBusy[i] then
		return
	end
	profileBusy[i] = true
	task.spawn(function()
		local reply = ctx.RequestFull("MktProfile", { I = i }, true)
		profileBusy[i] = nil
		if reply.Ok and type(reply.Profile) == "table" then
			profileCache[i] = { At = os.clock(), Profile = reply.Profile }
		else
			profileCache[i] = { At = os.clock() - PROFILE_TTL + 5, Profile = nil }
		end
	end)
end

local function profileText(i: number): string
	local cached = profileCache[i]
	local p = cached and cached.Profile
	if type(p) ~= "table" then
		requestProfile(i)
		return T("term.profile.loading")
	end
	local lines: { string } = {}
	if p.Etf then
		table.insert(lines, T("term.etfMembers", if type(p.Members) == "table" then #p.Members else 0))
	else
		if type(p.Revenue) == "number" then
			table.insert(lines, T("mkt.profile.revenue") .. ": " .. decimal(p.Revenue, 1) .. " " .. T("term.unit.bn"))
		end
		if type(p.Growth) == "table" then
			local parts: { string } = {}
			for _, g in ipairs(p.Growth) do
				if type(g) == "number" then
					table.insert(
						parts,
						string.format('<font color="%s">%s</font>', UI.ColorHex(UI.TrendColor(g)), pct(g, 1))
					)
				end
			end
			table.insert(lines, T("mkt.profile.growth") .. ": " .. table.concat(parts, "  "))
		end
		if type(p.Eps) == "number" then
			local epsText = if p.Eps < 0 then T("mkt.profile.loss") else price(p.Eps)
			table.insert(lines, T("mkt.profile.eps") .. ": " .. epsText)
		end
		if type(p.Pe) == "number" then
			table.insert(lines, T("mkt.profile.pe") .. ": " .. decimal(p.Pe, 1))
		end
		if type(p.DivBps) == "number" and p.DivBps > 0 then
			table.insert(lines, T("mkt.profile.divYield") .. ": " .. pct(p.DivBps / 10000, 1):gsub("^%+", ""))
		end
		local okTick, tick = pcall(ctx.Clock.Tick)
		local now = if okTick then tick else 0
		if type(p.NextEarnings) == "table" and type(p.NextEarnings.T) == "number" then
			local okDur, dur = pcall(ctx.Format.Duration, math.max(0, p.NextEarnings.T - now), lang())
			table.insert(lines, T("mkt.profile.nextEarnings") .. ": " .. T("term.cal.in", if okDur then dur else "?"))
		end
		if type(p.Consensus) == "string" then
			table.insert(lines, T("mkt.profile.consensus") .. ": " .. T(p.Consensus))
		end
		if type(p.Issue) == "number" then
			table.insert(lines, T("mkt.profile.issuePrice") .. ": " .. price(p.Issue))
		end
		if type(p.Quality) == "string" then
			table.insert(lines, T("mkt.profile.prospect") .. ": " .. T(p.Quality))
		end
		if type(p.Analysts) == "table" and #p.Analysts > 0 then
			table.insert(lines, "<b>" .. T("mkt.profile.analysts") .. "</b>")
			for _, analyst in ipairs(p.Analysts) do
				if type(analyst) == "table" then
					local verdict = if analyst.Verdict == 1
						then T("mkt.verdict.beat")
						elseif analyst.Verdict == -1 then T("mkt.verdict.miss")
						else T("mkt.verdict.none")
					table.insert(
						lines,
						string.format(
							"%s · %s · %s",
							tostring(analyst.Name),
							T("mkt.profile.hitRate", num(analyst.Hits, 0), num(analyst.N, 0)),
							verdict
						)
					)
				end
			end
		end
	end
	if type(p.WeekHigh) == "number" and p.WeekHigh > 0 then
		table.insert(
			lines,
			T("mkt.profile.weekHigh")
				.. ": "
				.. price(p.WeekHigh)
				.. " · "
				.. T("mkt.profile.weekLow")
				.. ": "
				.. price(num(p.WeekLow, 0))
		)
	end
	return table.concat(lines, "\n")
end

local function correlationText(i: number): string
	local inst = instOf(i)
	if type(inst) ~= "table" then
		return ""
	end
	local ref = if inst.Class == "ETF" then 40 else (SECTOR_ETF[inst.Sector] or 40)
	if ref == i then
		return ""
	end
	local c = correlation
	if not c or c.I ~= i or c.Ref ~= ref or os.clock() - c.At > 30 then
		local entry = { I = i, Ref = ref, Value = nil :: number?, At = os.clock() }
		correlation = entry
		local a: { any }? = nil
		local b: { any }? = nil
		local function compute()
			if not a or not b then
				return
			end
			local byT: { [number]: number } = {}
			for _, candle in ipairs(b) do
				byT[candle.T] = candle.C
			end
			local xs, ys = {}, {}
			local prevA, prevB = nil, nil
			for index = math.max(1, #a - 60), #a do
				local candle = a[index]
				local cb = byT[candle.T]
				if cb and prevA and prevB and prevA > 0 and prevB > 0 then
					table.insert(xs, math.log(candle.C / prevA))
					table.insert(ys, math.log(cb / prevB))
				end
				prevA, prevB = candle.C, cb
			end
			local n = #xs
			if n < 10 then
				return
			end
			local mx, my = 0, 0
			for k = 1, n do
				mx += xs[k]
				my += ys[k]
			end
			mx /= n
			my /= n
			local sxy, sxx, syy = 0, 0, 0
			for k = 1, n do
				local dx, dy = xs[k] - mx, ys[k] - my
				sxy += dx * dy
				sxx += dx * dx
				syy += dy * dy
			end
			if sxx > 0 and syy > 0 then
				entry.Value = sxy / math.sqrt(sxx * syy)
			end
		end
		call("MarketClient", "Candles", i, "1m", function(list)
			a = list
			compute()
		end)
		call("MarketClient", "Candles", ref, "1m", function(list)
			b = list
			compute()
		end)
	end
	local current = correlation
	if current and current.Value then
		return T("term.correlation", tickerOf(ref), decimal(current.Value, 2))
	end
	return T("term.correlation", tickerOf(ref), "…")
end

local function depthHash(i: number, tick: number, k: number): number
	local h = bit32.bxor(i * 73856093, tick * 19349663, k * 83492791)
	return (h % 1000) / 1000
end

local function updateAnalysis(a: { [string]: any }?)
	if not a then
		return
	end
	local score, regime = moodScore()
	UI.SetBar(a.MoodBar, score / 100, string.format("%d", math.floor(score + 0.5)))
	local moodKey = if score < 35 then "term.mood.fear" elseif score > 65 then "term.mood.greed" else "term.mood.neutral"
	local weatherCfg = (ctx.Config.Market or {}).Noise
	local weather = type(weatherCfg) == "table" and weatherCfg.Weather or { Calm = 0.85, Storm = 1.2 }
	local weatherKey = if regime < num(weather.Calm, 0.85)
		then "mkt.regime.calm"
		elseif regime > num(weather.Storm, 1.2) then "mkt.regime.storm"
		else "mkt.regime.normal"
	setText(a.MoodText, T(moodKey) .. " · " .. T(weatherKey))
	if a.GlossList then
		local lines: { string } = {}
		for k = 1, GLOSS_COUNT do
			table.insert(lines, "• " .. T("term.gloss." .. k))
		end
		setText(a.GlossList, table.concat(lines, "\n"))
	end
	if a.Cells then
		for _, cellEntry in ipairs(a.Cells) do
			local _, change = quote(cellEntry.I)
			local value = change or 0
			local intensity = math.clamp(math.abs(value) / 0.04, 0.1, 1)
			local color = if value >= 0 then UI.UpColor() else UI.DownColor()
			cellEntry.Frame.BackgroundColor3 = Theme.Surface2:Lerp(color, intensity)
			setText(
				cellEntry.Label,
				string.format("%s\n%s", tickerOf(cellEntry.I), if change then pct(change, 1) else "–")
			)
		end
	end
	local i = sel
	if a.Profile and i then
		setText(a.Profile, profileText(i))
		setText(a.Correlation, correlationText(i))
	end
	if a.Depth and i then
		local bid, ask, mid = bidAsk(i)
		local okRow, row = call("MarketClient", "Row", i)
		local okTick, tick = call("MarketClient", "Tick")
		if bid and ask and mid and okRow and type(row) == "table" then
			local step = math.max(1, math.floor(mid * 0.0005 + 0.5))
			local base = math.max(20, num(row.Vol, 50) * 10 / 4)
			local now = if okTick and type(tick) == "number" then tick else 0
			local maxSize = 1
			local sizes: { { number } } = {}
			for k = 1, 6 do
				local sb = math.floor(base * (0.6 + 0.9 * depthHash(i, now, k)) * (1 + 0.15 * k))
				local sa = math.floor(base * (0.6 + 0.9 * depthHash(i, now, k + 17)) * (1 + 0.15 * k))
				sizes[k] = { sb, sa }
				maxSize = math.max(maxSize, sb, sa)
			end
			for k, entry in ipairs(a.Depth) do
				local s = sizes[k]
				setText(entry.Bid, string.format("%d  %s", s[1], price(bid - (k - 1) * step)))
				setText(entry.Ask, string.format("%s  %d", price(ask + (k - 1) * step), s[2]))
				entry.BidBar.Size = UDim2.new(0.5 * s[1] / maxSize, -2, 0, 14)
				entry.AskBar.Size = UDim2.new(0.5 * s[2] / maxSize, -2, 0, 14)
				entry.BidBar.BackgroundColor3 = UI.UpColor()
				entry.AskBar.BackgroundColor3 = UI.DownColor()
			end
		end
		local lines: { string } = {}
		for index = #tape, 1, -1 do
			local entry = tape[index]
			table.insert(
				lines,
				string.format(
					'<font color="%s">%s</font>  %s  ×%d',
					UI.ColorHex(if entry.Up then UI.UpColor() else UI.DownColor()),
					T(if entry.Up then "term.side.B" else "term.side.S"),
					price(entry.C),
					math.max(1, math.floor(entry.V * 10))
				)
			)
		end
		setText(a.Tape, table.concat(lines, "\n"))
	end
end

-- ---------------------------------------------------------------------
-- ÜBUNG ACAD (§B8.6)
-- ---------------------------------------------------------------------
local function practice(): any
	local ok, p = call("MarketClient", "Practice")
	return if ok then p else nil
end

local function practiceActive(): boolean
	if practice() ~= nil then
		return true
	end
	if os.clock() - practiceDoneAt < 5 then
		return true
	end
	return practiceWanted and depot().Tutorial ~= "Done"
end

-- Übungs-Kauf/-Verkauf der ACAD (Knopf und Controller-A); blockiert bis zur Server-Antwort
local practiceBusy = false
local function practiceTrade(action: string)
	if practiceBusy then
		return
	end
	practiceBusy = true
	local reply = ctx.RequestFull("TutorialTrade", { Action = action })
	practiceBusy = false
	if not reply.Ok then
		sfx("UIError")
		return
	end
	if action == "Buy" then
		practiceBought = true
		sfx("Buy")
	else
		sfx("Sell")
		if type(reply.Pnl) == "number" then
			call("EffectsMarket", "TradeTick", reply.Pnl, nil)
		end
		practiceWanted = false
		practiceDoneAt = os.clock()
	end
	refreshAll()
end

local function buildPractice(parent: Instance): { [string]: any }
	local root = frame({
		Name = "Practice",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0.04,
		BackgroundColor3 = Theme.Surface,
		Visible = false,
		Active = true,
		ZIndex = 50,
		Parent = parent,
	})
	UI.Create("UICorner", { CornerRadius = UDim.new(0, 14), Parent = root })
	local title = text({
		Position = UDim2.fromOffset(20, 14),
		Size = UDim2.new(0.6, 0, 0, 28),
		FontFace = UI.Faces.Display,
		TextSize = 20,
		ZIndex = 51,
		Parent = root,
	})
	local label = UI.Chip(root, "", Theme.Warn, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 18),
		ZIndex = 51,
	})
	local news = panel({
		Position = UDim2.fromOffset(20, 50),
		Size = UDim2.new(1, -40, 0, 74),
		BackgroundColor3 = Theme.Bg2,
		ZIndex = 51,
		Parent = root,
	})
	local newsText = text({
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -28, 0, 36),
		TextWrapped = true,
		RichText = true,
		TextSize = 16,
		ZIndex = 52,
		Parent = news,
	})
	local barBack = frame({
		Position = UDim2.new(0, 14, 1, -24),
		Size = UDim2.new(0.6, 0, 0, 6),
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Surface2,
		ZIndex = 52,
		Parent = news,
	})
	UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = barBack })
	local barFill = frame({
		Size = UDim2.fromScale(0, 1),
		BackgroundTransparency = 0.2,
		BackgroundColor3 = Theme.Accent,
		ZIndex = 53,
		Parent = barBack,
	})
	UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = barFill })
	local barText = text({
		Position = UDim2.new(0.6, 24, 1, -30),
		Size = UDim2.new(0.4, -38, 0, 18),
		TextSize = 12,
		TextColor3 = Theme.Muted,
		ZIndex = 52,
		Parent = news,
	})
	local chartHost = frame({
		Position = UDim2.fromOffset(20, 132),
		Size = UDim2.new(1, -40, 1, -132 - 150),
		ZIndex = 51,
		Parent = root,
	})
	local tiko = text({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 20, 1, -104),
		Size = UDim2.new(1, -40, 0, 40),
		TextWrapped = true,
		FontFace = UI.Faces.BodyBold,
		TextSize = 15,
		TextColor3 = Theme.Accent,
		ZIndex = 51,
		Parent = root,
	})
	local hint = text({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 20, 1, -86),
		Size = UDim2.new(1, -40, 0, 18),
		TextSize = 12,
		TextColor3 = Theme.Muted,
		ZIndex = 51,
		Parent = root,
	})
	local h = math.max(54, touchMin())
	local buy = UI.Button({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 20, 1, -16),
		Size = UDim2.new(0.5, -26, 0, h),
		Text = T("term.acad.buy"),
		Variant = "Success",
		Face = "Display",
		MaxText = 20,
		ZIndex = 52,
		Parent = root,
	}, function()
		practiceTrade("Buy")
	end)
	local sell = UI.Button({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -16),
		Size = UDim2.new(0.5, -26, 0, h),
		Text = T("term.acad.sell"),
		Variant = "Danger",
		Face = "Display",
		MaxText = 20,
		ZIndex = 52,
		Parent = root,
	}, function()
		practiceTrade("Sell")
	end)
	return {
		Root = root,
		Title = title,
		Label = label,
		NewsText = newsText,
		BarFill = barFill,
		BarText = barText,
		ChartHost = chartHost,
		Tiko = tiko,
		Hint = hint,
		Buy = buy,
		Sell = sell,
		View = nil :: any,
		LastTick = 0,
		Count = 0,
	}
end

local function updatePractice(pr: { [string]: any }?)
	if not pr then
		return
	end
	local active = practiceActive()
	if pr.Root.Visible ~= active then
		pr.Root.Visible = active
		if ui.BottomBar then
			ui.BottomBar.Visible = not active
		end
	end
	if not active then
		return
	end
	setText(pr.Title, T("term.acad.title"))
	local labelText = pr.Label:FindFirstChild("Text")
	if labelText and labelText:IsA("TextLabel") then
		labelText.Text = UI.Upper(T("trade.tutLabel"))
	end
	setText(pr.NewsText, T("term.news.breaking") .. ": " .. T("term.acad.news"))
	pr.Buy.SetText(T("term.acad.buy"))
	pr.Sell.SetText(T("term.acad.sell"))
	local p = practice()
	local phase = if p then num(p.Phase, 0) else 0
	local done = depot().Tutorial == "Done" or os.clock() - practiceDoneAt < 5
	-- Chart der Übungsaktie (1s-Kerzen aus dem Replay-Strom)
	local lib = chartLib()
	if lib and not pr.View then
		pr.View = lib.new(pr.ChartHost, {
			Candles = 60,
			Volume = false,
			Style = "Line",
			Labels = true,
			AreaFill = areaFill(),
			MaxLines = 0,
		})
		pr.LastTick = 0
		pr.Count = 0
	end
	local view = pr.View
	if view and p and type(p.Candles) == "table" then
		if pr.Count == 0 or #p.Candles < pr.Count then
			view:SetData(p.Candles, 1)
			pr.Count = #p.Candles
			local last = p.Candles[#p.Candles]
			pr.LastTick = if last then last.T else 0
		else
			for _, candle in ipairs(p.Candles) do
				if candle.T > pr.LastTick then
					view:PushQuote(candle.C, candle.T, candle.H, candle.L, 0)
					pr.LastTick = candle.T
				end
			end
			pr.Count = #p.Candles
		end
	elseif view and not p and pr.Count == 0 then
		view:SetPlaceholder(T("mkt.historyLoading"))
	end
	-- Lese-Balken (Phase 1 = Händler lesen, ab Phase 2 reagiert der Markt)
	local delay = num((trading().Tutorial or {}).ReadSeconds, 8)
	if phase <= 0 then
		pr.BarFill.Size = UDim2.fromScale(0, 1)
		setText(pr.BarText, "")
	elseif phase == 1 then
		local newsAt = num((trading().Tutorial or {}).NewsAt, 2)
		local elapsed = 0
		if p and p.Candles[1] then
			elapsed = math.max(0, p.Tick - p.Candles[1].T - newsAt)
		end
		pr.BarFill.Size = UDim2.fromScale(math.clamp(elapsed / delay, 0, 1), 1)
		setText(pr.BarText, T("trade.readingBar"))
	else
		pr.BarFill.Size = UDim2.fromScale(1, 1)
		setText(pr.BarText, T("trade.marketReacts"))
	end
	local step = if done then 4 elseif practiceBought then 3 elseif phase >= 1 then 2 else 1
	setText(pr.Tiko, "Tiko: " .. T("term.acad.step" .. step))
	setText(pr.Hint, if practiceBought then T("term.acad.auto") else T("term.acad.protect"))
	pr.Buy.SetVariant(if practiceBought or done then "Muted" else "Success")
	pr.Sell.SetVariant(if practiceBought and not done then "Danger" else "Muted")
end

-- ---------------------------------------------------------------------
-- TABS (PC unten, Handy Depot/News)
-- ---------------------------------------------------------------------
local function tabContent(container: Frame, key: string): Frame?
	local holder = container:FindFirstChild("Tab_" .. key)
	if holder and holder:IsA("Frame") then
		return holder
	end
	local newHolder = frame({ Name = "Tab_" .. key, Size = UDim2.fromScale(1, 1), Visible = false, Parent = container })
	if
		key == "Positions"
		or key == "Orders"
		or key == "Alerts"
		or key == "Overview"
		or key == "Bots"
		or key == "Performance"
	then
		local ok, handle = call("DepotView", "Mount", newHolder, key)
		if ok and type(handle) == "table" then
			ui.Mounts = ui.Mounts or {}
			table.insert(ui.Mounts, handle)
		end
	elseif key == "Calendar" then
		ui.Calendar = buildCalendar(newHolder)
	elseif key == "Analysis" then
		ui.Analysis = buildAnalysis(newHolder)
	elseif key == "News" then
		local ok, handle = call("NewsFeed", "Mount", newHolder, {
			Filter = function(item: any): boolean
				return type(item.I) ~= "number" or allowed(item.I)
			end,
		})
		if ok and type(handle) == "table" then
			ui.Mounts = ui.Mounts or {}
			table.insert(ui.Mounts, handle)
		end
	end
	return newHolder
end

local function showTab(container: Frame?, key: string)
	if not container then
		return
	end
	local target = tabContent(container, key)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Frame") and string.sub(child.Name, 1, 4) == "Tab_" then
			child.Visible = child == target
		end
	end
	if key == "Calendar" then
		calendarClock = CALENDAR_EVERY
	elseif key == "Analysis" then
		analysisClock = ANALYSIS_EVERY
	end
	call("DepotView", "Refresh")
	call("NewsFeed", "Tick")
end

local function bottomTabs(): { any }
	local out: { any } = {
		{ Key = "Positions", Text = T("term.tab.Positions") },
		{ Key = "Orders", Text = T("term.tab.Orders") },
		{ Key = "Alerts", Text = T("term.tab.Alerts") },
		{ Key = "Overview", Text = T("term.tab.Depot") },
	}
	if num(perks().BotSlots, 0) > 0 then
		table.insert(out, { Key = "Bots", Text = T("term.tab.Bots") })
	end
	table.insert(out, { Key = "Performance", Text = T("term.tab.Performance") })
	if licence() >= traderFrom() then
		table.insert(out, { Key = "Calendar", Text = T("term.tab.Calendar") })
	end
	table.insert(out, { Key = "Analysis", Text = T("term.tab.Analysis") })
	return out
end

-- ---------------------------------------------------------------------
-- LAYOUT PC
-- ---------------------------------------------------------------------
local function buildHeader(root: Frame, compact: boolean)
	local header = frame({ Name = "Header", Size = UDim2.new(1, 0, 0, 48), Parent = root })
	ui.Header = header
	local title = text({
		Position = UDim2.fromOffset(18, 0),
		Size = UDim2.fromOffset(if compact then 160 else 210, 48),
		FontFace = UI.Faces.Display,
		TextSize = if compact then 15 else 18,
		Text = T("term.title"),
		Parent = header,
	})
	UI.Create("UIGradient", {
		Color = ColorSequence.new(Theme.LogoLetters, Theme.LogoRing),
		Parent = title,
	})
	local chips = frame({
		Position = UDim2.fromOffset(if compact then 180 else 236, 0),
		Size = UDim2.new(0, 340, 1, 0),
		Parent = header,
	})
	rowList(chips, 6, true)
	ui.HeaderChips = chips
	ui.HeaderChipKey = ""
	if not compact then
		local band = frame({
			Position = UDim2.new(0, 590, 0, 10),
			Size = UDim2.new(1, -650, 0, 28),
			BackgroundTransparency = 0.4,
			BackgroundColor3 = Theme.Bg2,
			Parent = header,
		})
		UI.Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = band })
		local inner = frame({ Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -16, 1, 0), Parent = band })
		local ok, handle = call("Ticker", "Attach", inner)
		if ok and type(handle) == "table" then
			ui.Band = handle
		end
	end
	UI.Button({
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(
			math.max(38, if compact then touchMin() * 0.7 else 38),
			math.max(38, if compact then touchMin() * 0.7 else 38)
		),
		Text = "✕",
		Variant = "Ghost",
		MaxText = 18,
		Corner = 10,
		Parent = header,
	}, function()
		ctx.Windows.Close("Terminal")
	end)
	UI.Create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Theme.Border,
		BorderSizePixel = 0,
		Parent = header,
	})
end

local function updateHeader()
	local chips: Frame? = ui.HeaderChips
	if not chips then
		return
	end
	local okFlags, flags = call("MarketClient", "Flags")
	local flagsKey = if okFlags and type(flags) == "table"
		then tostring(flags.Halt) .. tostring(flags.Crash) .. tostring(flags.Rally) .. tostring(flags.Admin)
		else ""
	local _, regime = moodScore()
	local weatherKey = if regime < 0.85 then "calm" elseif regime > 1.2 then "storm" else "normal"
	local key = flagsKey .. weatherKey .. layer() .. tostring(licence()) .. lang() .. tostring(practiceActive())
	if key == ui.HeaderChipKey then
		return
	end
	ui.HeaderChipKey = key
	for _, child in ipairs(chips:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local order = 0
	local function add(label: string, color: Color3)
		order += 1
		chip(chips, label, color, order)
	end
	local okLic, licName = call("MarketClient", "LicenceName")
	add(
		T("term.layer." .. layer()) .. " · " .. (if okLic and type(licName) == "string" then licName else ""),
		Theme.Accent
	)
	local marketHalted = false
	local market = state().Market
	if type(market) == "table" and type(market.Halts) == "table" then
		local all = market.Halts["0"]
		local okTick, tick = call("MarketClient", "Tick")
		marketHalted = type(all) == "number" and okTick and type(tick) == "number" and all > tick
	end
	add(if marketHalted then T("mkt.halted") else T("mkt.open"), if marketHalted then UI.DownColor() else UI.UpColor())
	add(T("mkt.regime." .. weatherKey), Theme.Text2)
	if okFlags and type(flags) == "table" then
		if flags.Crash then
			add(T("term.kind.Crash"), UI.DownColor())
		elseif flags.Rally then
			add(T("term.kind.Rally"), UI.UpColor())
		end
		if flags.Admin then
			add(T("term.kind.Admin"), Theme.Warn)
		end
	end
	if practiceActive() then
		add(UI.Upper(T("trade.tutLabel")), Theme.Warn)
	end
end

local function buildPC(root: Frame)
	buildHeader(root, false)
	local body =
		frame({ Name = "Body", Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 1, -70), Parent = root })
	-- links: Watchlist / Firmen-Karten
	local left =
		frame({ Name = "Left", Position = UDim2.fromOffset(12, 8), Size = UDim2.new(0, 236, 1, -12), Parent = body })
	ui.List = buildList(left, nil)
	-- Mitte: Instrument, Werkzeuge, Chart
	local center = frame({
		Name = "Center",
		Position = UDim2.fromOffset(256, 8),
		Size = UDim2.new(1, -256 - 316, 0, 412),
		Parent = body,
	})
	ui.InstHeader = buildInstHeader(center, false)
	local toolHolder = frame({ Position = UDim2.fromOffset(0, 66), Size = UDim2.new(1, 0, 0, 70), Parent = center })
	ui.Toolbar = buildToolbar(toolHolder, false)
	local chartPanel = panel({
		Name = "ChartPanel",
		Position = UDim2.fromOffset(0, 140),
		Size = UDim2.new(1, 0, 1, -140),
		Parent = center,
	})
	ui.ChartHost = frame({ Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 1, -16), Parent = chartPanel })
	-- unten: Tabs
	local bottom = frame({
		Name = "Bottom",
		Position = UDim2.fromOffset(256, 428),
		Size = UDim2.new(1, -256 - 316, 1, -432),
		Parent = body,
	})
	local tabsHolder = frame({ Size = UDim2.new(1, 0, 0, 30), Parent = bottom })
	local tabs = UI.Segmented(tabsHolder, bottomTabs(), function(key: string)
		bottomTab = key
		showTab(ui.BottomContent, key)
	end)
	tabs.Frame.Size = UDim2.fromScale(1, 1)
	ui.BottomTabs = tabs
	ui.BottomContent = frame({ Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 1, -36), Parent = bottom })
	-- rechts: Ticket + News
	local right = frame({
		Name = "Right",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 8),
		Size = UDim2.new(0, 300, 1, -12),
		Parent = body,
	})
	local ticketPanel = panel({ Size = UDim2.new(1, 0, 0.64, -4), Parent = right })
	local ticketInner =
		frame({ Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -14, 1, -16), Parent = ticketPanel })
	ui.Ticket = buildTicket(ticketInner, true)
	local newsPanel = panel({ Position = UDim2.new(0, 0, 0.64, 4), Size = UDim2.new(1, 0, 0.36, -4), Parent = right })
	text({
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 0, 18),
		FontFace = UI.Faces.BodyBold,
		TextSize = 12,
		TextColor3 = Theme.Muted,
		Text = UI.Upper(T("term.news")),
		Parent = newsPanel,
	})
	local newsHolder =
		frame({ Position = UDim2.fromOffset(8, 28), Size = UDim2.new(1, -12, 1, -34), Parent = newsPanel })
	local okNews, handle = call("NewsFeed", "Mount", newsHolder, {
		Max = 20,
		Filter = function(item: any): boolean
			return type(item.I) ~= "number" or allowed(item.I)
		end,
	})
	if okNews and type(handle) == "table" then
		ui.Mounts = ui.Mounts or {}
		table.insert(ui.Mounts, handle)
	end
	-- Fußzeile: Disclaimer (§A2)
	text({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -2),
		Size = UDim2.new(1, -32, 0, 18),
		TextSize = 11,
		TextColor3 = Theme.Muted,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = T("core.disclaimer"),
		Parent = root,
	})
	-- Übung über Mitte + rechts
	local practiceHolder = frame({
		Position = UDim2.fromOffset(256, 56),
		Size = UDim2.new(1, -268, 1, -82),
		ZIndex = 50,
		Parent = root,
	})
	ui.Practice = buildPractice(practiceHolder)
	buildSheet(root)
	local valid = false
	for _, tab in ipairs(bottomTabs()) do
		if tab.Key == bottomTab then
			valid = true
		end
	end
	if not valid then
		bottomTab = "Positions"
	end
	tabs.Set(bottomTab)
	showTab(ui.BottomContent, bottomTab)
end

-- ---------------------------------------------------------------------
-- LAYOUT HANDY
-- ---------------------------------------------------------------------
local function buildPicker(root: Frame)
	local overlay = frame({
		Name = "Picker",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0.02,
		BackgroundColor3 = Theme.Surface,
		Visible = false,
		Active = true,
		ZIndex = 55,
		Parent = root,
	})
	local inner =
		frame({ Position = UDim2.fromOffset(16, 64), Size = UDim2.new(1, -32, 1, -80), ZIndex = 56, Parent = overlay })
	text({
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -120, 0, 44),
		FontFace = UI.Faces.Display,
		TextSize = 20,
		Text = T("term.selectInst"),
		ZIndex = 56,
		Parent = overlay,
	})
	UI.Button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 8),
		Size = UDim2.fromOffset(math.max(48, touchMin() * 0.8), math.max(48, touchMin() * 0.8)),
		Text = "✕",
		Variant = "Ghost",
		MaxText = 20,
		ZIndex = 57,
		Parent = overlay,
	}, function()
		overlay.Visible = false
	end)
	ui.Picker = overlay
	ui.PickerList = buildList(inner, function(i: number)
		overlay.Visible = false
		selectInst(i)
	end)
end

local function phoneSubTabs(container: Frame, options: { any }, current: string, onPick: (string) -> ()): any
	local holder = frame({ Size = UDim2.new(1, 0, 0, 34), Parent = container })
	local seg = UI.Segmented(holder, options, function(key: string)
		onPick(key)
	end)
	seg.Frame.Size = UDim2.fromScale(1, 1)
	seg.Set(current)
	return seg
end

local function buildPhone(root: Frame)
	local touch = touchMin()
	buildHeader(root, true)
	-- Instrument-Auswahl (Tippen = Liste, Wischen im Chart = nächster Wert)
	local top =
		frame({ Name = "Top", Position = UDim2.fromOffset(12, 52), Size = UDim2.new(1, -24, 0, 58), Parent = root })
	ui.InstHeader = buildInstHeader(top, true)
	local pick: TextButton = UI.Create("TextButton", {
		Size = UDim2.new(0.5, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		Parent = top,
	})
	pick.Activated:Connect(function()
		if ui.Picker then
			ui.Picker.Visible = true
			updateList(ui.PickerList, true)
		end
	end)
	local tabsHolder = frame({ Position = UDim2.fromOffset(12, 114), Size = UDim2.new(1, -24, 0, 40), Parent = root })
	local tabs = UI.Segmented(tabsHolder, {
		{ Key = "Chart", Text = T("term.tab.Chart") },
		{ Key = "Order", Text = T("term.tab.Order") },
		{ Key = "Depot", Text = T("term.tab.Depot") },
		{ Key = "News", Text = T("term.tab.News") },
	}, function(key: string)
		phoneTab = key
		refreshAll()
	end)
	tabs.Frame.Size = UDim2.fromScale(1, 1)
	tabs.Set(phoneTab)
	ui.PhoneTabs = tabs
	local barH = touch + 46
	local content = frame({
		Name = "Content",
		Position = UDim2.fromOffset(12, 160),
		Size = UDim2.new(1, -24, 1, -160 - barH - 8),
		Parent = root,
	})
	ui.PhoneContent = content
	-- Chart-Tab
	local chartTab = frame({ Name = "PTab_Chart", Size = UDim2.fromScale(1, 1), Parent = content })
	ui.Toolbar = buildToolbar(chartTab, true)
	local chartPanel = panel({
		Position = UDim2.fromOffset(0, 106),
		Size = UDim2.new(1, 0, 1, -106),
		Parent = chartTab,
	})
	ui.ChartHost = frame({ Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 1, -12), Parent = chartPanel })
	-- Order-Tab
	local orderTab = frame({ Name = "PTab_Order", Size = UDim2.fromScale(1, 1), Visible = false, Parent = content })
	ui.Ticket = buildTicket(orderTab, false)
	-- Depot-Tab
	local depotTab = frame({ Name = "PTab_Depot", Size = UDim2.fromScale(1, 1), Visible = false, Parent = content })
	local depotContent =
		frame({ Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40), Parent = depotTab })
	ui.DepotContent = depotContent
	local depotOptions: { any } = {
		{ Key = "Overview", Text = T("term.tab.Overview") },
		{ Key = "Positions", Text = T("term.tab.Positions") },
		{ Key = "Orders", Text = T("term.tab.Orders") },
		{ Key = "Alerts", Text = T("term.tab.Alerts") },
	}
	if num(perks().BotSlots, 0) > 0 then
		table.insert(depotOptions, { Key = "Bots", Text = T("term.tab.Bots") })
	end
	table.insert(depotOptions, { Key = "Performance", Text = T("term.tab.Performance") })
	local depotKeys: { [string]: boolean } = {}
	for _, option in ipairs(depotOptions) do
		depotKeys[option.Key] = true
	end
	if not depotKeys[phoneDepotTab] then
		phoneDepotTab = "Overview"
	end
	phoneSubTabs(depotTab, depotOptions, phoneDepotTab, function(key: string)
		phoneDepotTab = key
		showTab(depotContent, key)
	end)
	showTab(depotContent, phoneDepotTab)
	-- News-Tab (+ Kalender/Analyse)
	local newsTab = frame({ Name = "PTab_News", Size = UDim2.fromScale(1, 1), Visible = false, Parent = content })
	local newsContent = frame({ Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40), Parent = newsTab })
	ui.NewsContent = newsContent
	local newsOptions: { any } = { { Key = "News", Text = T("term.tab.News") } }
	if licence() >= traderFrom() then
		table.insert(newsOptions, { Key = "Calendar", Text = T("term.tab.Calendar") })
	end
	table.insert(newsOptions, { Key = "Analysis", Text = T("term.tab.Analysis") })
	local newsKeys: { [string]: boolean } = {}
	for _, option in ipairs(newsOptions) do
		newsKeys[option.Key] = true
	end
	if not newsKeys[phoneNewsTab] then
		phoneNewsTab = "News"
	end
	phoneSubTabs(newsTab, newsOptions, phoneNewsTab, function(key: string)
		phoneNewsTab = key
		showTab(newsContent, key)
	end)
	showTab(newsContent, phoneNewsTab)
	-- feste Kauf/Verkauf-Leiste im Daumenbereich (Knöpfe ≥ 64 echte Pixel)
	local bar = frame({
		Name = "TradeBar",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -8),
		Size = UDim2.new(1, -24, 0, barH),
		Parent = root,
	})
	ui.BottomBar = bar
	local preview = text({
		Size = UDim2.new(0.55, 0, 0, 16),
		FontFace = UI.Faces.Mono,
		TextSize = 12,
		TextColor3 = Theme.Text2,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = bar,
	})
	ui.BarPreview = preview
	local chipHolder = frame({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.45, 0, 0, 36),
		Parent = bar,
	})
	local chips = UI.Segmented(chipHolder, {
		{ Key = "10", Text = T("term.chip10") },
		{ Key = "25", Text = T("term.chip25") },
		{ Key = "Max", Text = T("trade.chipMax") },
	}, function(key: string)
		ticket.Chip = key
		ticket.Amount = "Chip"
		refreshAll()
	end)
	chips.Frame.Size = UDim2.fromScale(1, 1)
	ui.BarChips = chips
	ui.BuyButton = UI.Button({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(0.5, -5, 0, touch),
		Text = T("trade.buy"),
		Variant = "Success",
		Face = "Display",
		MaxText = 22,
		Parent = bar,
	}, function()
		place("B")
	end)
	ui.SellButton = UI.Button({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.new(0.5, -5, 0, touch),
		Text = T("trade.sell"),
		Variant = "Danger",
		Face = "Display",
		MaxText = 22,
		Parent = bar,
	}, function()
		place("S")
	end)
	buildPicker(root)
	local practiceHolder = frame({
		Position = UDim2.fromOffset(12, 52),
		Size = UDim2.new(1, -24, 1, -60),
		ZIndex = 50,
		Parent = root,
	})
	ui.Practice = buildPractice(practiceHolder)
	buildSheet(root)
end

local function updatePhone()
	local content: Frame? = ui.PhoneContent
	if not content then
		return
	end
	for _, child in ipairs(content:GetChildren()) do
		if child:IsA("Frame") then
			child.Visible = child.Name == "PTab_" .. phoneTab
		end
	end
	if ui.PhoneTabs then
		ui.PhoneTabs.Set(phoneTab)
	end
	if ui.BarChips then
		ui.BarChips.Set(ticket.Chip)
	end
	local otype = ticket.Type
	local side = if SELL_ONLY[otype] then "S" else "B"
	local est = estimate(side)
	if ui.BarPreview then
		setText(
			ui.BarPreview,
			if est
					and est.Qty > 0
					and side == "B"
				then T("trade.costPreview", aky(est.Cost, true), aky(est.Fee))
				elseif est and est.Qty > 0 then T("term.proceeds", aky(est.Proceeds, true), aky(est.Fee))
				else ""
		)
	end
	local blocked = sel == nil or (sel ~= nil and (halted(sel) or not allowed(sel)))
	if ui.BuyButton then
		ui.BuyButton.SetVariant(if blocked or SELL_ONLY[otype] then "Muted" else "Success")
		ui.SellButton.SetVariant(if blocked then "Muted" else "Danger")
	end
end

-- ---------------------------------------------------------------------
-- AUSWAHL, KURSE, AKTUALISIEREN
-- ---------------------------------------------------------------------
local function defaultSelection(): number?
	local held = heldIds()
	local best, bestValue = nil, -1
	for _, i in ipairs(held) do
		if allowed(i) then
			local q = position(i)
			local close = quote(i) or 0
			if q * close > bestValue then
				best, bestValue = i, q * close
			end
		end
	end
	if best then
		return best
	end
	if allowed(40) then
		return 40
	end
	local ok, ids = call("MarketClient", "AllowedIds")
	if ok and type(ids) == "table" then
		return ids[1]
	end
	return nil
end

selectInst = function(i: number)
	if type(i) ~= "number" or not instOf(i) then
		return
	end
	local changed = sel ~= i
	sel = i
	if changed then
		table.clear(tape)
		alarmMode = false
		local bid, _, mid = bidAsk(i)
		local protect = trading().Protect or { Sl = 0.08, Tp = 0.15 }
		if bid and mid then
			ticket.Lim = price(mid)
			ticket.Stp = price(math.floor(bid * (1 - num(protect.Sl, 0.08))))
			ticket.Tp = price(math.ceil(bid * (1 + num(protect.Tp, 0.15))))
		end
		ctx.Hooks.Fire("Terminal:Instrument", i)
		if isOpen then
			buildCharts()
		end
	end
	refreshAll()
end

refreshAll = function()
	if not isOpen then
		return
	end
	updateHeader()
	updateInstHeader(ui.InstHeader)
	updateToolbar(ui.Toolbar)
	updateTicket(ui.Ticket)
	updateList(ui.List, false)
	if ui.Picker and ui.Picker.Visible then
		updateList(ui.PickerList, false)
	end
	updatePhone()
	updatePractice(ui.Practice)
	chartMarks()
	if ui.BottomTabs then
		ui.BottomTabs.Set(bottomTab)
	end
end

local function onQuotes(frameData: any)
	if not isOpen then
		return
	end
	-- Kurse in die Charts (Live-Kerze gleitet in ChartView.Step)
	for _, entry in ipairs(views) do
		local okCandle, candle = call("MarketClient", "Candle1s", entry.I)
		if okCandle and type(candle) == "table" then
			entry.View:PushQuote(candle.C, candle.T, candle.H, candle.L, candle.V)
		end
	end
	-- Umsätze (simuliert) des gewählten Werts
	local i = sel
	if i then
		local okCandle, candle = call("MarketClient", "Candle1s", i)
		if okCandle and type(candle) == "table" then
			table.insert(tape, { T = candle.T, C = candle.C, V = candle.V, Up = candle.C >= candle.O })
			while #tape > 12 do
				table.remove(tape, 1)
			end
		end
	end
	local tick = if type(frameData) == "table" then frameData.Tick else 0
	updateHeader()
	updateInstHeader(ui.InstHeader)
	updateTicket(ui.Ticket)
	updateList(ui.List, tick % 5 == 0)
	if ui.Picker and ui.Picker.Visible then
		updateList(ui.PickerList, tick % 5 == 0)
	end
	updatePhone()
end

-- ---------------------------------------------------------------------
-- ÖFFNEN / SCHLIESSEN / NEUAUFBAU
-- ---------------------------------------------------------------------
local function decideLayout(): string
	local camera = workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local kind = inputKind()
	if kind == "Touch" or size.X < PC_MIN.X or size.Y < PC_MIN.Y then
		return "Phone"
	end
	return "PC"
end

local function buildKey(): string
	return table.concat({
		decideLayout(),
		layer(),
		tostring(licence() >= traderFrom()),
		tostring(math.floor(quality("Candles", 90))),
		tostring(areaFill()),
		tostring(num(perks().BotSlots, 0) > 0),
		tostring(perks().MultiChart == true),
		lang(),
	}, "|")
end

local function destroyUi()
	untrackAll()
	if ui.Practice and ui.Practice.View then
		ui.Practice.View:Destroy()
	end
	if ui.Mounts then
		for _, handle in ipairs(ui.Mounts) do
			pcall(handle.Destroy)
		end
	end
	if ui.Band then
		pcall(ui.Band.Destroy)
	end
	if ui.Root then
		ui.Root:Destroy()
	end
	ui = {}
end

rebuild = function()
	local wasVisible = ui.Root ~= nil and ui.Root.Visible
	destroyUi()
	layoutKind = decideLayout()
	builtKey = buildKey()
	local phone = layoutKind == "Phone"
	local root = UI.Create("Frame", {
		Name = "Terminal",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = if phone then UDim2.fromScale(1, 1) else UDim2.fromOffset(1180, 700),
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Visible = wasVisible,
		Active = true,
		ZIndex = 12,
		Parent = ctx.Gui,
	}, {
		UI.Corner(if phone then 0 else 18),
		UI.Stroke(nil, 1),
	})
	ui.Root = root
	ui.Scale = UI.Create("UIScale", { Parent = root })
	if phone then
		buildPhone(root)
	else
		buildPC(root)
	end
	if not sel or not allowed(sel) then
		local i = defaultSelection()
		if i then
			sel = i
		end
	end
	buildCharts()
end

local function bindPad()
	if padBound then
		return
	end
	padBound = true
	ContextActionService:BindActionAtPriority(
		PAD_ACTION,
		function(_, inputState, input)
			if UserInputService:GetFocusedTextBox() then
				return Enum.ContextActionResult.Pass
			end
			local key = input.KeyCode
			if key == Enum.KeyCode.Thumbstick2 then
				stickX = if math.abs(input.Position.X) > 0.5 then math.sign(input.Position.X) else 0
				return Enum.ContextActionResult.Sink
			end
			if inputState ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Sink
			end
			local sheetOpen = ui.Sheet and ui.Sheet.Root.Visible
			if key == Enum.KeyCode.ButtonA then
				if sheetOpen then
					confirmSheet()
				elseif practiceActive() then
					task.spawn(practiceTrade, if practiceBought then "Sell" else "Buy")
				else
					openSheet("B")
				end
			elseif key == Enum.KeyCode.ButtonX then
				if not sheetOpen then
					openSheet("S")
				end
			elseif key == Enum.KeyCode.ButtonY then
				if not sheetOpen then
					protectPosition()
				end
			elseif key == Enum.KeyCode.ButtonB then
				if sheetOpen then
					closeSheet()
				elseif ui.Picker and ui.Picker.Visible then
					ui.Picker.Visible = false
				else
					ctx.Windows.Close("Terminal")
				end
			elseif key == Enum.KeyCode.DPadUp or key == Enum.KeyCode.DPadDown then
				if not sheetOpen then
					swipe(if key == Enum.KeyCode.DPadUp then -1 else 1)
				end
			elseif key == Enum.KeyCode.DPadLeft or key == Enum.KeyCode.DPadRight then
				local dir = if key == Enum.KeyCode.DPadLeft then -1 else 1
				if sheetOpen then
					sheetChip(dir)
				elseif views[1] then
					views[1].View:MoveCrosshair(dir)
				end
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		PAD_PRIORITY,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.ButtonX,
		Enum.KeyCode.ButtonY,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.DPadUp,
		Enum.KeyCode.DPadDown,
		Enum.KeyCode.DPadLeft,
		Enum.KeyCode.DPadRight,
		Enum.KeyCode.Thumbstick2
	)
end

local function unbindPad()
	if not padBound then
		return
	end
	padBound = false
	stickX = 0
	ContextActionService:UnbindAction(PAD_ACTION)
end

local function showRoot()
	if builtKey ~= buildKey() or not ui.Root then
		rebuild()
	end
	local root: Frame = ui.Root
	isOpen = true
	openToken += 1
	root.Visible = true
	local phone = layoutKind == "Phone"
	local rest = UDim2.fromScale(0.5, 0.5)
	if reducedFx() then
		root.Position = rest
		ui.Scale.Scale = 1
	elseif phone then
		root.Position = UDim2.new(0.5, 0, 1.5, 0)
		ui.Scale.Scale = 1
		TweenService:Create(root, SHEET_INFO, { Position = rest }):Play()
	else
		root.Position = UDim2.new(0.5, 0, 0.5, 8)
		ui.Scale.Scale = 0.96
		TweenService:Create(root, OPEN_INFO, { Position = rest }):Play()
		TweenService:Create(ui.Scale, OPEN_INFO, { Scale = 1 }):Play()
	end
	bindPad()
	call("TouchControls", "Show", "Terminal")
	if not sel then
		local i = defaultSelection()
		if i then
			selectInst(i)
		end
	end
	for _, entry in ipairs(views) do
		entry.View:SetVisible(true)
		if entry.Stale then
			-- geschlossen liefen keine Kurse in den Chart: einmal aus der (weiter gepflegten) Reihe nachladen
			entry.Stale = false
			local view = entry.View
			call("MarketClient", "Candles", entry.I, entry.Tf, function(candles)
				if view.Alive and #candles > 0 then
					view:SetData(candles, entry.Tf)
				end
			end)
		end
	end
	refreshAll()
	call("DepotView", "Refresh")
end

local function hideRoot()
	isOpen = false
	for _, entry in ipairs(views) do
		entry.Stale = true -- ab jetzt laufen keine Kurse mehr in die Charts
	end
	unbindPad()
	closeSheet()
	alarmMode = false
	openToken += 1
	local token = openToken
	local root: Frame? = ui.Root
	if not root then
		return
	end
	if ui.Picker then
		ui.Picker.Visible = false
	end
	local function finish()
		if openToken == token and root.Parent then
			root.Visible = false
			for _, entry in ipairs(views) do
				entry.View:SetVisible(false)
			end
		end
	end
	if reducedFx() then
		finish()
		return
	end
	local phone = layoutKind == "Phone"
	local goal = if phone then UDim2.new(0.5, 0, 1.5, 0) else UDim2.new(0.5, 0, 0.5, 8)
	local tween = TweenService:Create(root, CLOSE_INFO, { Position = goal })
	if not phone then
		TweenService:Create(ui.Scale, CLOSE_INFO, { Scale = 0.97 }):Play()
	end
	tween.Completed:Once(finish)
	tween:Play()
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICH
-- ---------------------------------------------------------------------
function Terminal.Open()
	ctx.Windows.Open("Terminal")
end

function Terminal.IsOpen(): boolean
	return ctx.Windows.IsOpen("Terminal")
end

function Terminal.OpenAt(instId: number)
	if type(instId) ~= "number" then
		Terminal.Open()
		return
	end
	if not Terminal.IsOpen() then
		Terminal.Open()
	end
	if allowed(instId) then
		selectInst(instId)
	else
		ctx.Toast(T("trade.notLicensed"), "Info")
	end
	if layoutKind == "Phone" then
		phoneTab = "Chart"
		refreshAll()
	end
end

function Terminal.OpenTicket(instId: number, side: string?)
	Terminal.OpenAt(instId)
	if side == "S" then
		ticket.Type = "MKT"
		ticket.Chip = "Max"
		ticket.Amount = "Chip"
	end
	if layoutKind == "Phone" then
		phoneTab = "Order"
	end
	refreshAll()
end

function Terminal.ShowTab(tab: string)
	if layoutKind == "Phone" then
		local depotTabs =
			{ Overview = true, Positions = true, Orders = true, Alerts = true, Bots = true, Performance = true }
		if depotTabs[tab] then
			phoneTab = "Depot"
			phoneDepotTab = tab
			showTab(ui.DepotContent, tab)
		elseif tab == "News" or tab == "Calendar" or tab == "Analysis" then
			phoneTab = "News"
			phoneNewsTab = tab
			showTab(ui.NewsContent, tab)
		elseif tab == "Chart" or tab == "Order" then
			phoneTab = tab
		end
	else
		bottomTab = tab
		showTab(ui.BottomContent, tab)
	end
	refreshAll()
end

-- Übung mit der Übungsaktie ACAD (Tutorial §B2/§B8.6)
function Terminal.OpenPractice()
	practiceWanted = true
	practiceBought = false
	Terminal.Open()
	if depot().Tutorial ~= "Running" then
		task.spawn(function()
			local reply = ctx.RequestFull("TutorialTrade", { Action = "Start" })
			if not reply.Ok then
				practiceWanted = false
			end
			refreshAll()
		end)
	end
	refreshAll()
end

function Terminal.Selected(): number?
	return sel
end

function Terminal.Frame(dt: number)
	if not isOpen then
		return
	end
	for _, entry in ipairs(views) do
		entry.View:Step(dt)
	end
	local pr = ui.Practice
	if pr and pr.View and pr.Root.Visible then
		pr.View:Step(dt)
	end
	if stickX ~= 0 then
		stickClock += dt
		if stickClock >= STICK_REPEAT then
			stickClock = 0
			if views[1] then
				views[1].View:MoveCrosshair(stickX)
			end
		end
	end
	glossClock += dt
	if glossClock >= GLOSS_EVERY then
		glossClock = 0
		glossIndex = (glossIndex % GLOSS_COUNT) + 1
		if ui.Ticket then
			setText(ui.Ticket.Gloss, T("term.gloss." .. tostring(glossIndex)))
		end
	end
	calendarClock += dt
	if calendarClock >= CALENDAR_EVERY then
		calendarClock = 0
		updateCalendar(ui.Calendar)
	end
	analysisClock += dt
	if analysisClock >= ANALYSIS_EVERY then
		analysisClock = 0
		updateAnalysis(ui.Analysis)
		updatePractice(ui.Practice)
		-- Fehlerzustand: lädt die Historie nicht (Markt öffnet gleich, Server-Limit …), die Server-Meldung zeigen
		-- statt endlos „Historie lädt …“ (MarketClient versucht es mit wachsendem Abstand weiter)
		for _, entry in ipairs(views) do
			if entry.View.Alive and entry.View:Count() == 0 then
				local okErr, err = call("MarketClient", "SeriesError", entry.I, entry.Tf)
				if okErr and type(err) == "string" and err ~= "" then
					entry.View:SetPlaceholder(err)
				end
			end
		end
	end
end

function Terminal.Init(context: any)
	ctx = context
	ctx.Windows.Register("Terminal", showRoot, hideRoot)
	local hooks = ctx.Hooks
	hooks.On("Quotes", onQuotes)
	hooks.On("Replay", function()
		if isOpen then
			updatePractice(ui.Practice)
		end
	end)
	hooks.On("State", function(_state, changed)
		if not isOpen or type(changed) ~= "table" then
			return
		end
		if changed.Prog then
			if builtKey ~= buildKey() then
				rebuild()
			end
			if sel and not allowed(sel) then
				local i = defaultSelection()
				if i then
					selectInst(i)
				end
			end
		end
		if changed.Depot or changed.Prog or changed.Market then
			refreshAll()
		end
	end)
	hooks.On("Settings", function()
		if not isOpen then
			return
		end
		if builtKey ~= buildKey() then
			rebuild()
			refreshAll()
			return
		end
		local style = currentStyle()
		local indicators = indicatorMap()
		local needReload = false
		for index, entry in ipairs(views) do
			entry.View:SetStyle(style)
			entry.View:SetIndicators(if index == 1 then indicators else {})
			entry.View:Repaint()
			if index == 1 and entry.Tf ~= currentTf() then
				needReload = true
			end
		end
		if needReload then
			-- Zeitrahmen gewechselt: dieselben gepoolten Charts behalten, nur die Reihe neu verfolgen (kein Neuaufbau
			-- von ~900 Frames je Chart -> der Wechsel bleibt flüssig, Historie kommt aus dem MarketClient-Cache)
			local tf = currentTf()
			for _, entry in ipairs(views) do
				local want = if entry.Role == "Second" then (if tf == "1T" then "15m" else "1T") else tf
				if entry.Tf ~= want then
					entry.Tf = want
					entry.Stale = false
					trackView(entry)
				end
			end
			chartMarks()
		end
		refreshAll()
	end)
	hooks.On("Quality", function()
		if isOpen and builtKey ~= buildKey() then
			rebuild()
			refreshAll()
		end
	end)
	hooks.On("Input", function()
		if isOpen and decideLayout() ~= layoutKind then
			rebuild()
			refreshAll()
		end
	end)
	hooks.On("Market:News", function()
		if isOpen then
			updateTicket(ui.Ticket)
		end
	end)
	-- Tasten: 1–7 Zeitrahmen, LB/RB Zeitrahmen weiter, C/Select Chart-Typ (Controls, Kontext "Terminal")
	local ALL_KEYS: { [Enum.KeyCode]: number } = {
		[Enum.KeyCode.One] = 1,
		[Enum.KeyCode.Two] = 2,
		[Enum.KeyCode.Three] = 3,
		[Enum.KeyCode.Four] = 4,
		[Enum.KeyCode.Five] = 5,
		[Enum.KeyCode.Six] = 6,
		[Enum.KeyCode.Seven] = 7,
	}
	call("Controls", "Bind", "ChartTf", function(inputState: string, input: InputObject?)
		if inputState ~= "Begin" or not isOpen then
			return
		end
		local list = allowedTfs()
		local current = table.find(list, currentTf()) or 1
		local target: string? = nil
		if input then
			local index = ALL_KEYS[input.KeyCode]
			if index then
				local wanted = ALL_TF[index]
				if table.find(list, wanted) then
					target = wanted
				else
					ctx.Toast(T("term.tf.locked", T("term.lic.4")), "Info")
					return
				end
			elseif input.KeyCode == Enum.KeyCode.ButtonL1 then
				target = list[math.max(1, current - 1)]
			elseif input.KeyCode == Enum.KeyCode.ButtonR1 then
				target = list[math.min(#list, current + 1)]
			end
		end
		if target and target ~= currentTf() then
			call("Settings", "Set", "ChartTf", target)
		end
	end)
	call("Controls", "Bind", "ChartType", function(inputState: string)
		if inputState ~= "Begin" or not isOpen then
			return
		end
		local list = allowedStyles()
		local index = table.find(list, currentStyle()) or 1
		call("Settings", "Set", "ChartType", list[(index % #list) + 1])
	end)
end

function Terminal.Start()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if isOpen and decideLayout() ~= layoutKind then
				rebuild()
				refreshAll()
			end
		end)
	end
end

return Terminal
