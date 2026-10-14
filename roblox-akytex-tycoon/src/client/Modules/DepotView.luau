-- =====================================================================
--  AKYTEX TYCOON – Depot-Ansichten: Positionen, Orders, Alarme, Übersicht mit Gewinn-Transfer, Bots, Performance
--  (Client/Modules/DepotView)
--  Besitzer: WP5 (Charts, Terminal, Markt-UI). Vertrag: DESIGN.md §B7.1 (Tabs Positionen/Orders/Alarme), §B8.1–§B8.5
--  (Basis, Gewinn-Transfer „Verfügbar 1.240 AKY → 49.600 CR (Bau-Kurs 40)“, Starthilfe, Strategie-Bots), §B7.2 (Profi:
--  Performance-Analyse TWR/Drawdown/Skill-Score), §C9 (TradeCancel, TradeModify, AlertRemove, BotSet, BotToggle,
--  TradeRefill, DepotHistory, TowerTransfer), §C10 (State Depot, League).
--
--  Das Terminal hängt die Ansichten in seine Tabs (DepotView.Mount(parent, section)). Alle Zahlen live: Depotwert und
--  G/V aus dem letzten Frame (Geldkurse), Rest aus State "Depot"/"League". Zeilen sind gepoolt (kein Neuaufbau je Tick),
--  Texte werden nur bei Änderung geschrieben. Geld fließt nur AKY -> CR (Gewinn-Transfer über den Turm, §0.4);
--  die CR-Zahl ist eine Vorschau: floor(Abhebbar × Bau-Kurs / 100) – gebucht wird serverseitig.
--
--  Öffentliche API (WP5-intern):
--    DepotView.Mount(parent, section): { Frame, Refresh, Destroy }
--      section "Positions" | "Orders" | "Alerts" | "Overview" | "Bots" | "Performance"
--    DepotView.Open(section?)                    öffnet das Terminal auf dem Depot-Tab
--    DepotView.Nav(): number                     Depotwert live (Cent)
--    DepotView.Free(): number                    freies Geld (Cash − Reservierungen offener Kauf-Orders)
--    DepotView.Position(i): (qty, avgCents, freeQty)
--    DepotView.Init(ctx), DepotView.Start()
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = require(script.Parent:WaitForChild("UI"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PortfolioMath = require(Shared:WaitForChild("Market"):WaitForChild("PortfolioMath"))

local DepotView = {}

type View = {
	Section: string,
	Frame: ScrollingFrame,
	Alive: boolean,
	Rows: { any },
	Parts: { [string]: any },
	Update: (View) -> (),
}

local Theme = UI.Theme
local ROW_H = 52
local REFRESH_GAP = 0.25
local HISTORY_GAP = 10
local MAX_FILL_ROWS = 10

local ctx: any = nil
local views: { View } = {}
local pending = false
local history: { Fills: { any }, Nav: { any } }? = nil
local historyAt = -math.huge
local historyBusy = false

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function lang(): string
	return ctx.Lang_()
end

local function T(key: string, ...: any): string
	return ctx.T(key, ...)
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

local function depot(): { [string]: any }
	local d = ctx.State.Depot
	return if type(d) == "table" then d else {}
end

local function league(): { [string]: any }
	local l = ctx.State.League
	return if type(l) == "table" then l else {}
end

local function aky(cents: number, compact: boolean?): string
	local ok, text = pcall(ctx.Format.Aky, cents, lang(), compact)
	return if ok then text else tostring(math.floor(cents / 100))
end

local function price(cents: number): string
	local ok, text = pcall(ctx.Format.Price, cents, lang())
	return if ok then text else string.format("%.2f", cents / 100)
end

-- Zahl aus Freitext lesen – DE "1.234,56" und EN "1,234.56" ergeben beide 1234.56
local function parseNumber(text: string): number?
	local raw = string.gsub(text or "", "[^%d,%.]", "")
	if raw == "" then
		return nil
	end
	local lastComma = string.find(raw, ",[^,]*$")
	local lastDot = string.find(raw, "%.[^%.]*$")
	if lastComma and (not lastDot or lastComma > lastDot) then
		raw = string.gsub(raw, "%.", "")
		raw = string.gsub(raw, ",", ".")
	else
		raw = string.gsub(raw, ",", "")
	end
	local n = tonumber(raw)
	if n and n == n and n < 1e12 then
		return n
	end
	return nil
end

-- Dezimalzahl in Landesschreibweise (DE mit Komma)
local function decimal(v: number, places: number): string
	local text = string.format("%." .. places .. "f", v)
	if lang() == "de" then
		text = (string.gsub(text, "%.", ","))
	end
	return text
end

local function pct(fraction: number, digits: number?): string
	local ok, text = pcall(ctx.Format.Pct, fraction, lang(), digits or 2, true)
	return if ok then text else string.format("%+.2f %%", fraction * 100)
end

local function credits(n: number): string
	local ok, text = pcall(ctx.Format.Credits, n, lang())
	return if ok then text else tostring(math.floor(n))
end

local function setText(label: TextLabel, text: string)
	if label.Text ~= text then
		label.Text = text
	end
end

local function instOf(i: number): any
	local ok, inst = call("MarketClient", "Instrument", i)
	return if ok then inst else nil
end

local function tickerOf(i: number): string
	local inst = instOf(i)
	return if type(inst) == "table" then inst.Ticker else ("#" .. tostring(i))
end

local function bidOf(i: number): number?
	local ok, bid = call("MarketClient", "BidAsk", i)
	if ok and type(bid) == "number" then
		return bid
	end
	return nil
end

local function licenceDef(): { [string]: any }
	local ok, def = call("MarketClient", "LicenceDef")
	return if ok and type(def) == "table" then def else {}
end

local function perks(): { [string]: any }
	local ok, value = call("MarketClient", "Perks")
	return if ok and type(value) == "table" then value else {}
end

local function trading(): { [string]: any }
	local t = ctx.Config.Trading
	return if type(t) == "table" then t else {}
end

local function nextSeq(): number
	local ok, seq = call("MarketClient", "NextSeq")
	if ok and type(seq) == "number" then
		return seq
	end
	return (math.floor(os.time()) % 2097152) * 1024
end

local function sfx(role: string)
	call("Sfx", "Play", role)
end

-- ---------------------------------------------------------------------
-- DEPOT-RECHNUNG (gleiche Mathematik wie der Server: PortfolioMath)
-- ---------------------------------------------------------------------
function DepotView.Free(): number
	local d = depot()
	local cash = num(d.Cash, 0)
	local reserved = 0
	if type(d.Orders) == "table" then
		for _, order in ipairs(d.Orders) do
			if type(order) == "table" and order.Side == "B" then
				reserved += num(order.Res, 0)
			end
		end
	end
	return math.max(0, cash - reserved)
end

function DepotView.Nav(): number
	local d = depot()
	if type(d.Pos) ~= "table" then
		return num(d.Nav, num(d.Cash, 0))
	end
	local bids: { [number]: number } = {}
	for key in pairs(d.Pos) do
		local i = tonumber(key)
		if i then
			local bid = bidOf(i)
			if bid then
				bids[i] = bid
			end
		end
	end
	local ok, nav = pcall(PortfolioMath.Nav, { Cash = num(d.Cash, 0), Pos = d.Pos }, bids)
	if ok and type(nav) == "number" then
		return nav
	end
	return num(d.Nav, 0)
end

function DepotView.Position(i: number): (number, number, number)
	local pos = depot().Pos
	local p = type(pos) == "table" and pos[tostring(i)] or nil
	if type(p) ~= "table" then
		return 0, 0, 0
	end
	local q = num(p.Q, 0)
	local avg = if q > 0 then num(p.C, 0) / q else 0
	return q, avg, math.max(0, q - num(p.R, 0))
end

-- ---------------------------------------------------------------------
-- BAUSTEINE
-- ---------------------------------------------------------------------
local function newList(parent: Instance): ScrollingFrame
	return UI.Create("ScrollingFrame", {
		Name = "DepotList",
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
	}, {
		UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }),
		UI.Create("UIPadding", {
			PaddingLeft = UDim.new(0, 2),
			PaddingRight = UDim.new(0, 8),
			PaddingTop = UDim.new(0, 2),
			PaddingBottom = UDim.new(0, 8),
		}),
	})
end

local function cell(parent: Instance, x: number, w: number, props: { [string]: any }?): TextLabel
	local base: { [string]: any } = {
		Position = UDim2.new(x, 0, 0, 0),
		Size = UDim2.new(w, 0, 1, 0),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.Mono,
		TextSize = 13,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		RichText = true,
		Text = "",
	}
	if props then
		for k, v in pairs(props) do
			base[k] = v
		end
	end
	base.Parent = parent
	return UI.Create("TextLabel", base)
end

local function logoChip(parent: Instance, i: number): Frame
	local inst = instOf(i)
	local okSector, sector = call("MarketClient", "Sector", i)
	local color = if okSector and type(sector) == "table" then sector.Color else Theme.Accent
	local chip: Frame = UI.Create("Frame", {
		Name = "Logo",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Parent = parent,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	UI.Create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.Display,
		TextSize = 13,
		TextColor3 = Color3.new(1, 1, 1),
		Text = if type(inst) == "table" and type(inst.Logo) == "table" then tostring(inst.Logo.Letter) else "?",
		Parent = chip,
	})
	return chip
end

local function emptyLabel(parent: Instance, order: number): TextLabel
	return UI.Create("TextLabel", {
		Name = "Empty",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.Body,
		TextSize = 14,
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		Text = "",
		LayoutOrder = order,
		Parent = parent,
	})
end

local function smallButton(parent: Instance, text: string, variant: string, order: number, onClick: () -> ()): any
	return UI.Button({
		Size = UDim2.fromOffset(96, 34),
		Text = text,
		Variant = variant,
		MaxText = 13,
		Corner = 9,
		LayoutOrder = order,
		Parent = parent,
	}, onClick)
end

-- ---------------------------------------------------------------------
-- ABSCHNITT: POSITIONEN
-- ---------------------------------------------------------------------
local function placeProtect(i: number)
	local bid = bidOf(i)
	if not bid then
		return
	end
	local protect = trading().Protect or { Sl = 0.08, Tp = 0.15 }
	local reply = ctx.RequestFull("TradePlace", {
		I = i,
		Side = "S",
		Type = "OCO",
		Pct = "Max",
		Stp = math.max(1, math.floor(bid * (1 - num(protect.Sl, 0.08)))),
		Tp = math.ceil(bid * (1 + num(protect.Tp, 0.15))),
		Seq = nextSeq(),
	})
	sfx(if reply.Ok then "UIClick" else "UIError")
end

local function hasProtection(i: number): boolean
	local orders = depot().Orders
	if type(orders) ~= "table" then
		return false
	end
	for _, order in ipairs(orders) do
		if type(order) == "table" and order.I == i and order.Side == "S" then
			if order.Type == "OCO" or order.Type == "STP" or order.Type == "TRL" then
				return true
			end
		end
	end
	return false
end

local function positionRow(view: View, index: number): any
	local card = UI.RowCard(view.Frame, 10 + index, ROW_H)
	local button: TextButton = UI.Create("TextButton", {
		Name = "Hit",
		Size = UDim2.new(1, -210, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		Parent = card,
	})
	local row = {
		Card = card,
		I = 0,
		Logo = nil :: Frame?,
		Name = cell(card, 0, 0.3, {
			Position = UDim2.new(0, 46, 0, 0),
			Size = UDim2.new(0.26, -46, 1, 0),
			FontFace = UI.Faces.BodyBold,
		}),
		Qty = cell(card, 0.26, 0.12),
		Avg = cell(card, 0.38, 0.14, { TextColor3 = Theme.Text2 }),
		Now = cell(card, 0.52, 0.14),
		Pnl = cell(card, 0.66, 0.2),
		Actions = UI.RowActions(card, 200),
		Sell = nil :: any,
		Protect = nil :: any,
	}
	button.Activated:Connect(function()
		if row.I > 0 then
			call("Terminal", "OpenAt", row.I)
		end
	end)
	row.Sell = smallButton(row.Actions, T("term.pos.sell"), "Danger", 1, function()
		if row.I > 0 then
			call("Terminal", "OpenTicket", row.I, "S")
		end
	end)
	row.Protect = smallButton(row.Actions, T("term.pos.protect"), "Secondary", 2, function()
		if row.I > 0 then
			placeProtect(row.I)
		end
	end)
	return row
end

local function updatePositions(view: View)
	local d = depot()
	local list: { { I: number, Q: number, C: number, Value: number } } = {}
	if type(d.Pos) == "table" then
		for key, p in pairs(d.Pos) do
			local i = tonumber(key)
			if i and type(p) == "table" and num(p.Q, 0) > 0 then
				local bid = bidOf(i) or (num(p.C, 0) / math.max(1, num(p.Q, 1)))
				table.insert(list, { I = i, Q = num(p.Q, 0), C = num(p.C, 0), Value = num(p.Q, 0) * bid })
			end
		end
	end
	table.sort(list, function(a, b)
		return a.Value > b.Value
	end)
	local header = view.Parts.Header
	if not header then
		local frame: Frame = UI.Create("Frame", {
			Name = "Header",
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
			Parent = view.Frame,
		})
		local cols = {
			{ "term.col.inst", 0, 0.26, 46 },
			{ "term.col.qty", 0.26, 0.12, 0 },
			{ "term.col.cost", 0.38, 0.14, 0 },
			{ "term.col.price", 0.52, 0.14, 0 },
			{ "term.col.pnl", 0.66, 0.2, 0 },
		}
		local labels = {}
		for _, col in ipairs(cols) do
			local label = cell(frame, col[2], col[3], {
				Position = UDim2.new(col[2], col[4], 0, 0),
				TextSize = 11,
				TextColor3 = Theme.Muted,
				FontFace = UI.Faces.BodyBold,
			})
			table.insert(labels, { Label = label, Key = col[1] })
		end
		header = { Frame = frame, Labels = labels }
		view.Parts.Header = header
		view.Parts.Empty = emptyLabel(view.Frame, 2)
	end
	for _, entry in ipairs(header.Labels) do
		setText(entry.Label, UI.Upper(T(entry.Key)))
	end
	header.Frame.Visible = #list > 0
	view.Parts.Empty.Visible = #list == 0
	setText(view.Parts.Empty, if d.Syncing then T("trade.syncing") else T("term.pos.empty"))
	for index, entry in ipairs(list) do
		local row = view.Rows[index]
		if not row then
			row = positionRow(view, index)
			view.Rows[index] = row
		end
		if row.I ~= entry.I then
			row.I = entry.I
			if row.Logo then
				row.Logo:Destroy()
			end
			row.Logo = logoChip(row.Card, entry.I)
		end
		local inst = instOf(entry.I)
		setText(row.Name, if type(inst) == "table" then inst.Ticker else tickerOf(entry.I))
		local okQty, qtyText = pcall(ctx.Format.Int, entry.Q, lang())
		setText(row.Qty, if okQty and type(qtyText) == "string" then qtyText else tostring(entry.Q))
		local avg = entry.C / math.max(1, entry.Q)
		setText(row.Avg, price(math.floor(avg + 0.5)))
		local bid = entry.Value / math.max(1, entry.Q)
		setText(row.Now, price(math.floor(bid + 0.5)))
		local pnl = entry.Value - entry.C
		local frac = if entry.C > 0 then pnl / entry.C else 0
		local color = UI.ColorHex(UI.TrendColor(pnl))
		setText(
			row.Pnl,
			string.format(
				'<font color="%s">%s %s (%s)</font>',
				color,
				UI.TrendArrow(pnl),
				aky(math.floor(pnl + 0.5), true),
				pct(frac)
			)
		)
		row.Sell.SetText(T("term.pos.sell"))
		row.Protect.SetText(T("term.pos.protect"))
		row.Protect.Frame.Visible = not hasProtection(entry.I)
		row.Card.Visible = true
	end
	for index = #list + 1, #view.Rows do
		view.Rows[index].Card.Visible = false
	end
end

-- ---------------------------------------------------------------------
-- ABSCHNITT: ORDERS (Streichen, Ändern)
-- ---------------------------------------------------------------------
local TYPE_KEY: { [string]: string } = {
	MKT = "trade.typeMKT",
	LMT = "trade.typeLMT",
	STP = "trade.typeSTP",
	TP = "trade.typeTP",
	OCO = "trade.typeOCO",
	TRL = "trade.typeTRL",
}

local function orderPrices(order: any): string
	local parts: { string } = {}
	if type(order.Lim) == "number" then
		table.insert(parts, T("term.ord.lim", price(order.Lim)))
	end
	if type(order.Stp) == "number" then
		table.insert(parts, T("term.ord.stp", price(order.Stp)))
	end
	if type(order.Tp) == "number" then
		table.insert(parts, T("term.ord.tp", price(order.Tp)))
	end
	if type(order.Trl) == "number" then
		table.insert(parts, T("term.ord.trl", pct(order.Trl / 10000, 1)))
	end
	return table.concat(parts, " · ")
end

local function orderRow(view: View, index: number): any
	local card: Frame = UI.RowCard(view.Frame, 10 + index, ROW_H)
	local row = {
		Card = card,
		Order = nil :: any,
		Title = cell(card, 0, 0.36, {
			Position = UDim2.new(0, 12, 0, 6),
			Size = UDim2.new(0.42, -12, 0, 20),
			FontFace = UI.Faces.BodyBold,
		}),
		Prices = cell(card, 0, 0.42, {
			Position = UDim2.new(0, 12, 0, 26),
			Size = UDim2.new(0.42, -12, 0, 18),
			TextSize = 12,
			TextColor3 = Theme.Text2,
		}),
		Exp = cell(card, 0.42, 0.2, { TextSize = 12, TextColor3 = Theme.Muted }),
		Actions = UI.RowActions(card, 200),
		Edit = nil :: any,
		Cancel = nil :: any,
		Editor = nil :: Frame?,
	}
	row.Edit = smallButton(row.Actions, T("term.ord.edit"), "Secondary", 1, function()
		local order = row.Order
		if not order then
			return
		end
		local editor = row.Editor
		if editor then
			editor:Destroy()
			row.Editor = nil
			card.Size = UDim2.new(1, 0, 0, ROW_H)
			return
		end
		-- kleiner Editor: je Preisfeld ein Eingabefeld + Speichern
		card.Size = UDim2.new(1, 0, 0, ROW_H + 48)
		local holder: Frame = UI.Create("Frame", {
			Name = "Editor",
			Position = UDim2.new(0, 12, 0, ROW_H),
			Size = UDim2.new(1, -24, 0, 40),
			BackgroundTransparency = 1,
			Parent = card,
		}, {
			UI.Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 8),
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		row.Editor = holder
		local boxes: { [string]: TextBox } = {}
		local fields = { "Lim", "Stp", "Tp", "Trl" }
		for order_, key in ipairs(fields) do
			local value = order[key]
			if type(value) == "number" then
				local text = if key == "Trl" then decimal(value / 100, 1) else price(value)
				boxes[key] = UI.TextBox({
					Size = UDim2.fromOffset(110, 32),
					Text = text,
					PlaceholderText = T("term.ord.field." .. key),
					LayoutOrder = order_,
					Parent = holder,
				})
			end
		end
		smallButton(holder, T("term.ord.save"), "Primary", 10, function()
			local arg: { [string]: any } = { OrderId = order.Id, Seq = nextSeq() }
			for key, box in pairs(boxes) do
				local n = parseNumber(box.Text)
				if not n or n <= 0 then
					ctx.Toast(T("term.priceInvalid"), "Error")
					return
				end
				if key == "Trl" then
					arg.Trl = math.clamp(math.floor(n * 100 + 0.5), 50, 2000)
				else
					arg[key] = math.floor(n * 100 + 0.5)
				end
			end
			local reply = ctx.RequestFull("TradeModify", arg)
			if reply.Ok then
				holder:Destroy()
				row.Editor = nil
				card.Size = UDim2.new(1, 0, 0, ROW_H)
			end
		end)
	end)
	row.Cancel = smallButton(row.Actions, T("term.ord.cancel"), "Danger", 2, function()
		local order = row.Order
		if order then
			local reply = ctx.RequestFull("TradeCancel", { OrderId = order.Id, Seq = nextSeq() })
			sfx(if reply.Ok then "UIClick" else "UIError")
		end
	end)
	return row
end

local function updateOrders(view: View)
	local d = depot()
	local orders: { any } = {}
	if type(d.Orders) == "table" then
		for _, order in ipairs(d.Orders) do
			if type(order) == "table" and type(order.Id) == "number" then
				table.insert(orders, order)
			end
		end
	end
	if not view.Parts.Empty then
		view.Parts.Empty = emptyLabel(view.Frame, 1)
		view.Parts.Count = UI.Create("TextLabel", {
			Name = "Count",
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
			FontFace = UI.Faces.Body,
			TextSize = 12,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 2,
			Parent = view.Frame,
		})
	end
	view.Parts.Empty.Visible = #orders == 0
	setText(view.Parts.Empty, T("term.ord.empty"))
	local maxOrders = num(licenceDef().MaxOrders, 5)
	setText(view.Parts.Count, T("term.ord.count", #orders, maxOrders))
	local now = 0
	local okTick, tick = pcall(ctx.Clock.Tick)
	if okTick and type(tick) == "number" then
		now = tick
	end
	for index, order in ipairs(orders) do
		local row = view.Rows[index]
		if not row then
			row = orderRow(view, index)
			view.Rows[index] = row
		end
		if row.Order and row.Order.Id ~= order.Id and row.Editor then
			row.Editor:Destroy()
			row.Editor = nil
			row.Card.Size = UDim2.new(1, 0, 0, ROW_H)
		end
		row.Order = order
		local sideText = T(if order.Side == "B" then "term.side.B" else "term.side.S")
		local typeText = T(TYPE_KEY[order.Type] or "trade.typeMKT")
		if order.Type == "STP" and order.Side == "B" then
			typeText = T("trade.typeBuyStop")
		end
		local okQ, qText = pcall(ctx.Format.Int, math.floor(num(order.Q, 0)), lang())
		local title = string.format(
			"%s · %s %s · %s",
			tickerOf(order.I),
			sideText,
			typeText,
			if okQ and type(qText) == "string" then qText else tostring(num(order.Q, 0))
		)
		if type(order.Bot) == "number" then
			title ..= " · " .. T("term.ord.bot")
		end
		setText(row.Title, title)
		setText(row.Prices, orderPrices(order))
		local left = num(order.Exp, 0) - now
		setText(row.Exp, if left > 0 then T("term.ord.expires", ctx.Format.Duration(left, lang())) else "")
		local editable = type(order.Bot) ~= "number" and order.Type ~= "MKT"
		row.Edit.Frame.Visible = editable
		row.Cancel.Frame.Visible = type(order.Bot) ~= "number"
		row.Edit.SetText(T("term.ord.edit"))
		row.Cancel.SetText(T("term.ord.cancel"))
		row.Card.Visible = true
	end
	for index = #orders + 1, #view.Rows do
		local row = view.Rows[index]
		row.Card.Visible = false
		row.Order = nil
	end
end

-- ---------------------------------------------------------------------
-- ABSCHNITT: ALARME
-- ---------------------------------------------------------------------
local function updateAlerts(view: View)
	local d = depot()
	local alerts: { any } = {}
	if type(d.Alerts) == "table" then
		for _, alert in ipairs(d.Alerts) do
			if type(alert) == "table" and type(alert.Id) == "number" then
				table.insert(alerts, alert)
			end
		end
	end
	if not view.Parts.Hint then
		view.Parts.Hint = UI.Create("TextLabel", {
			Name = "Hint",
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundTransparency = 1,
			FontFace = UI.Faces.Body,
			TextSize = 13,
			TextColor3 = Theme.Muted,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 1,
			Parent = view.Frame,
		})
	end
	local limit = math.floor(num(perks().Alerts, 3))
	setText(view.Parts.Hint, T("term.alarm.count", #alerts, limit) .. " · " .. T("term.alert.hint"))
	for index, alert in ipairs(alerts) do
		local row = view.Rows[index]
		if not row then
			local card: Frame = UI.RowCard(view.Frame, 10 + index, 44)
			row = {
				Card = card,
				Alert = nil :: any,
				Text = cell(card, 0, 0.6, { Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(0.6, -12, 1, 0) }),
				Actions = UI.RowActions(card, 110),
				Remove = nil :: any,
			}
			local current = row
			row.Remove = smallButton(row.Actions, T("term.alert.remove"), "Secondary", 1, function()
				local entry = current.Alert
				if entry then
					local reply = ctx.RequestFull("AlertRemove", { Id = entry.Id })
					sfx(if reply.Ok then "UIClick" else "UIError")
				end
			end)
			view.Rows[index] = row
		end
		row.Alert = alert
		local color = UI.ColorHex(if alert.Dir == "Up" then UI.UpColor() else UI.DownColor())
		setText(
			row.Text,
			string.format(
				'%s  <font color="%s">%s</font>  %s',
				tickerOf(alert.I),
				color,
				if alert.Dir == "Up" then "▲" else "▼",
				price(num(alert.Px, 0))
			)
		)
		row.Remove.SetText(T("term.alert.remove"))
		row.Card.Visible = true
	end
	for index = #alerts + 1, #view.Rows do
		view.Rows[index].Card.Visible = false
		view.Rows[index].Alert = nil
	end
end

-- ---------------------------------------------------------------------
-- ABSCHNITT: ÜBERSICHT (Depotwert, Basis, Gewinn-Transfer, Starthilfe, Auto-Transfer)
-- ---------------------------------------------------------------------
local function transferStatus(): (string, boolean)
	local d = depot()
	if d.Syncing then
		return T("trade.syncing"), false
	end
	local withdrawable = num(d.Withdrawable, 0)
	local basis = num(d.Basis, 0)
	local nav = DepotView.Nav()
	local threshold = num((trading().Transfer or {}).Threshold, 1.02)
	if d.TransferReady == true and withdrawable > 0 then
		local rate = num(licenceDef().BauKurs, 40)
		local cr = math.floor(withdrawable * rate / 100)
		local rateText = credits(rate)
		return T("trade.transferAvail", aky(withdrawable, true), credits(cr) .. " CR", rateText), true
	end
	if basis > 0 and nav < basis * threshold then
		return T("trade.transferBelow"), false
	end
	if withdrawable > 0 then
		return T("trade.transferUsed"), false
	end
	return T("trade.transferNone"), false
end

local function buildOverview(view: View)
	local frame = view.Frame
	local grid: Frame = UI.Create("Frame", {
		Name = "Tiles",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = frame,
	}, {
		UI.Create("UIGridLayout", {
			CellSize = UDim2.new(0.25, -8, 0, 64),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local tiles = {
		Value = UI.StatTile(grid, T("term.depot.value"), 1),
		Cash = UI.StatTile(grid, T("term.depot.cash"), 2),
		Basis = UI.StatTile(grid, T("term.depot.basis"), 3),
		Return = UI.StatTile(grid, T("term.depot.return"), 4),
	}
	view.Parts.Tiles = tiles
	view.Parts.TileGrid = grid
	-- Gewinn-Transfer-Karte
	local transfer = UI.Card({
		Name = "Transfer",
		Size = UDim2.new(1, 0, 0, 118),
		LayoutOrder = 2,
		Parent = frame,
	})
	view.Parts.TransferTitle = UI.Label({
		Position = UDim2.fromOffset(14, 10),
		Size = UDim2.new(1, -28, 0, 20),
		Text = "",
		Face = "Display",
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 16,
		Parent = transfer,
	})
	view.Parts.TransferText = UI.Create("TextLabel", {
		Position = UDim2.fromOffset(14, 34),
		Size = UDim2.new(1, -28, 0, 20),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.Mono,
		TextSize = 15,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Text = "",
		Parent = transfer,
	})
	view.Parts.RateText = UI.Create("TextLabel", {
		Position = UDim2.fromOffset(14, 56),
		Size = UDim2.new(1, -28, 0, 16),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.Body,
		TextSize = 12,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		Parent = transfer,
	})
	view.Parts.TransferButton = UI.Button({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -10),
		Size = UDim2.fromOffset(230, 36),
		Text = T("trade.transferButton"),
		Variant = "Success",
		MaxText = 15,
		Corner = 10,
		Parent = transfer,
	}, function()
		local reply = ctx.RequestFull("TowerTransfer", {})
		sfx(if reply.Ok then "CashRegister" else "UIError")
	end)
	view.Parts.AutoButton = UI.Button({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -10),
		Size = UDim2.fromOffset(250, 36),
		Text = "",
		Variant = "Secondary",
		MaxText = 13,
		Corner = 10,
		Parent = transfer,
	}, function()
		local current = depot().AutoTransfer ~= false
		-- Einstellung und Depot können auseinanderlaufen (z. B. anderes Gerät): steht die Einstellung schon auf dem
		-- Zielwert, würde Settings.Set nichts senden -> dann direkt an das Depot (WP4)
		local okGet, settings = call("Settings", "Get")
		local already = okGet and type(settings) == "table" and settings.AutoTransfer == not current
		local okSet = not already and call("Settings", "Set", "AutoTransfer", not current)
		if not okSet then
			task.spawn(ctx.RequestFull, "TradeAuto", { On = not current })
		end
	end)
	-- Starthilfe (Rettungsschirm, §B8.4)
	local refill = UI.Card({
		Name = "Refill",
		Size = UDim2.new(1, 0, 0, 60),
		LayoutOrder = 3,
		Visible = false,
		Parent = frame,
	})
	view.Parts.Refill = refill
	view.Parts.RefillText = UI.Create("TextLabel", {
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -190, 1, 0),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.Body,
		TextSize = 13,
		TextWrapped = true,
		TextColor3 = Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		Parent = refill,
	})
	view.Parts.RefillButton = UI.Button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(160, 36),
		Text = T("trade.refillButton"),
		Variant = "Primary",
		MaxText = 15,
		Corner = 10,
		Parent = refill,
	}, function()
		local reply = ctx.RequestFull("TradeRefill", {})
		sfx(if reply.Ok then "CashRegister" else "UIError")
	end)
	view.Parts.Footer = UI.Create("TextLabel", {
		Name = "Disclaimer",
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.Body,
		TextSize = 11,
		TextWrapped = true,
		TextColor3 = Theme.Muted,
		Text = "",
		LayoutOrder = 9,
		Parent = frame,
	})
end

local function updateOverview(view: View)
	if not view.Parts.Tiles then
		buildOverview(view)
	end
	local d = depot()
	local tiles = view.Parts.Tiles
	local nav = DepotView.Nav()
	local basis = num(d.Basis, 0)
	setText(tiles.Value, aky(nav, true))
	setText(tiles.Cash, aky(DepotView.Free(), true))
	setText(tiles.Basis, aky(basis, true))
	local ret = if basis > 0 then nav / basis - 1 else 0
	setText(tiles.Return, pct(ret))
	tiles.Return.TextColor3 = UI.TrendColor(ret)
	-- Kachel-Überschriften (Sprache)
	for key, label in pairs(tiles) do
		local caption = label.Parent and label.Parent:FindFirstChild("Caption")
		if caption and caption:IsA("TextLabel") then
			local textKey = ({
				Value = "term.depot.value",
				Cash = "term.depot.cash",
				Basis = "term.depot.basis",
				Return = "term.depot.return",
			})[key]
			if textKey then
				setText(caption, T(textKey))
			end
		end
	end
	setText(view.Parts.TransferTitle, UI.Upper(T("trade.transferButton")))
	local text, ready = transferStatus()
	setText(view.Parts.TransferText, text)
	setText(view.Parts.RateText, T("trade.bauKurs", credits(num(licenceDef().BauKurs, 40))))
	view.Parts.TransferButton.SetText(T("trade.transferButton"))
	view.Parts.TransferButton.SetVariant(if ready then "Success" else "Muted")
	view.Parts.AutoButton.SetText(T(if d.AutoTransfer ~= false then "trade.autoOn" else "trade.autoOff"))
	local refillReady = d.RefillReady == true
	view.Parts.Refill.Visible = refillReady
	if refillReady then
		local target = math.floor(basis * num((trading().Refill or {}).To, 0.5))
		setText(view.Parts.RefillText, T("term.depot.refillHint", aky(math.max(0, target - nav), true)))
		view.Parts.RefillButton.SetText(T("trade.refillButton"))
	end
	setText(view.Parts.Footer, T("core.disclaimer"))
end

-- ---------------------------------------------------------------------
-- ABSCHNITT: STRATEGIE-BOTS (§B8.5 – nur Lizenz + Know-how, nie Robux)
-- ---------------------------------------------------------------------
local function botPresets(): { string }
	local order = trading().BotOrder
	return if type(order) == "table" then order else { "Sparplan", "Trend", "Dividend", "Dip" }
end

local function botDef(preset: string): { [string]: any }?
	local bots = trading().Bots
	local def = type(bots) == "table" and bots[preset] or nil
	return if type(def) == "table" then def else nil
end

local function botTargets(def: { [string]: any }): { number }
	local out: { number } = {}
	local okIds, ids = call("MarketClient", "AllowedIds")
	if not okIds or type(ids) ~= "table" then
		return out
	end
	for _, i in ipairs(ids) do
		local inst = instOf(i)
		if type(inst) == "table" then
			local isEtf = inst.Class == "ETF"
			if (def.Target == "ETF" and isEtf) or (def.Target == "Inst" and not isEtf) then
				table.insert(out, i)
			end
		end
	end
	return out
end

local function openBotEditor(row: any, slotIndex: number)
	if row.Editor then
		row.Editor:Destroy()
		row.Editor = nil
		row.Card.Size = UDim2.new(1, 0, 0, 92)
		return
	end
	local licence = 1
	local okLic, value = call("MarketClient", "Licence")
	if okLic and type(value) == "number" then
		licence = value
	end
	local unlocked: { string } = {}
	for _, preset in ipairs(botPresets()) do
		local def = botDef(preset)
		if def and num(def.Licence, 99) <= licence then
			table.insert(unlocked, preset)
		end
	end
	if #unlocked == 0 then
		return
	end
	local existing = depot().Bots
	local current = type(existing) == "table" and existing[slotIndex] or nil
	local preset = if type(current) == "table" and table.find(unlocked, current.Preset)
		then current.Preset
		else unlocked[1]
	row.Card.Size = UDim2.new(1, 0, 0, 92 + 150)
	local holder: Frame = UI.Create("Frame", {
		Name = "Editor",
		Position = UDim2.fromOffset(12, 92),
		Size = UDim2.new(1, -24, 0, 144),
		BackgroundTransparency = 1,
		Parent = row.Card,
	}, {
		UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }),
	})
	row.Editor = holder
	local names: { string } = {}
	for _, key in ipairs(unlocked) do
		local def = botDef(key)
		table.insert(names, if def then ctx.Lang.Pick(lang(), def.Name) else key)
	end
	local cycler = UI.Cycler(holder, T("term.bot.pick"), names, UDim2.new(1, 0, 0, 34))
	cycler.Button.Frame.LayoutOrder = 1
	cycler.Set(names[table.find(unlocked, preset) or 1])
	local sliderHolder: Frame = UI.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = holder,
	})
	local targetHolder: Frame = UI.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = holder,
	})
	local slider: any = nil
	local target: any = nil
	local targetIds: { number } = {}
	local function rebuild()
		for _, child in ipairs(sliderHolder:GetChildren()) do
			child:Destroy()
		end
		for _, child in ipairs(targetHolder:GetChildren()) do
			child:Destroy()
		end
		local def = botDef(preset)
		if not def then
			return
		end
		local lo, hi = math.floor(num(def.Min, 0.05) * 100 + 0.5), math.floor(num(def.Max, 0.3) * 100 + 0.5)
		local start = math.floor(num(def.Default, 0.1) * 100 + 0.5)
		if type(current) == "table" and current.Preset == preset and type(current.Pct) == "number" then
			start = math.floor(current.Pct * 100 + 0.5)
		end
		slider = UI.Slider(sliderHolder, 1, T("term.bot.param." .. tostring(def.Param)), lo, hi, start, function() end)
		slider.Frame.Size = UDim2.fromScale(1, 1)
		target = nil
		targetIds = {}
		if def.Target == "ETF" or def.Target == "Inst" then
			targetIds = botTargets(def)
			local labels: { string } = {}
			for _, i in ipairs(targetIds) do
				table.insert(labels, tickerOf(i))
			end
			target = UI.Cycler(targetHolder, T("term.bot.targetPick"), labels, UDim2.fromScale(1, 1))
			local wanted = if type(current) == "table" and current.Preset == preset
				then current.Target
				else def.DefaultTarget
			if type(wanted) == "number" and table.find(targetIds, wanted) then
				target.Set(tickerOf(wanted))
			end
		end
	end
	cycler.OnChange = function(name: string?)
		local index = table.find(names, name or "")
		if index then
			preset = unlocked[index]
			rebuild()
		end
	end
	rebuild()
	smallButton(holder, T("term.bot.save"), "Primary", 4, function()
		local def = botDef(preset)
		if not def or not slider then
			return
		end
		local arg: { [string]: any } = { Slot = slotIndex, Preset = preset, Pct = slider.Get() / 100 }
		if target then
			local chosen = target.Get()
			for _, i in ipairs(targetIds) do
				if tickerOf(i) == chosen then
					arg.Target = i
				end
			end
			if def.Target == "Inst" and arg.Target == nil then
				ctx.Toast(T("trade.botTarget"), "Error")
				return
			end
		end
		local reply = ctx.RequestFull("BotSet", arg)
		if reply.Ok then
			holder:Destroy()
			row.Editor = nil
			row.Card.Size = UDim2.new(1, 0, 0, 92)
		end
	end)
end

local function updateBots(view: View)
	local slots = math.floor(num(perks().BotSlots, num(licenceDef().BotSlots, 0)))
	local bots = depot().Bots
	if not view.Parts.Hint then
		view.Parts.Hint = UI.Create("TextLabel", {
			Name = "Hint",
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundTransparency = 1,
			FontFace = UI.Faces.Body,
			TextSize = 12,
			TextColor3 = Theme.Muted,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 1,
			Parent = view.Frame,
		})
	end
	setText(
		view.Parts.Hint,
		if slots <= 0 then T("term.bot.none") else T("trade.botWage") .. " · " .. T("trade.botTotal")
	)
	for index = 1, slots do
		local row = view.Rows[index]
		if not row then
			local card: Frame = UI.Card({
				Name = "Bot",
				Size = UDim2.new(1, 0, 0, 92),
				LayoutOrder = 10 + index,
				Parent = view.Frame,
			})
			row = {
				Card = card,
				Editor = nil :: Frame?,
				Title = UI.Label({
					Position = UDim2.fromOffset(14, 8),
					Size = UDim2.new(1, -240, 0, 20),
					Text = "",
					Face = "Display",
					TextXAlignment = Enum.TextXAlignment.Left,
					MaxText = 15,
					Parent = card,
				}),
				Desc = UI.Create("TextLabel", {
					Position = UDim2.fromOffset(14, 30),
					Size = UDim2.new(1, -240, 0, 34),
					BackgroundTransparency = 1,
					FontFace = UI.Faces.Body,
					TextSize = 12,
					TextWrapped = true,
					TextColor3 = Theme.Text2,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					Text = "",
					Parent = card,
				}),
				Status = UI.Create("TextLabel", {
					Position = UDim2.fromOffset(14, 66),
					Size = UDim2.new(1, -240, 0, 18),
					BackgroundTransparency = 1,
					FontFace = UI.Faces.Mono,
					TextSize = 12,
					TextColor3 = Theme.Muted,
					TextXAlignment = Enum.TextXAlignment.Left,
					RichText = true,
					Text = "",
					Parent = card,
				}),
				Toggle = nil :: any,
				Change = nil :: any,
			}
			local current = row
			local slotIndex = index
			row.Toggle = UI.Button({
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 12),
				Size = UDim2.fromOffset(104, 34),
				Text = "",
				Variant = "Secondary",
				MaxText = 13,
				Corner = 9,
				Parent = card,
			}, function()
				local list = depot().Bots
				local slot = type(list) == "table" and list[slotIndex] or nil
				if type(slot) ~= "table" then
					openBotEditor(current, slotIndex)
					return
				end
				local reply = ctx.RequestFull("BotToggle", { Slot = slotIndex, On = slot.On ~= true })
				sfx(if reply.Ok then "UIClick" else "UIError")
			end)
			row.Change = UI.Button({
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -124, 0, 12),
				Size = UDim2.fromOffset(104, 34),
				Text = "",
				Variant = "Ghost",
				MaxText = 13,
				Corner = 9,
				Parent = card,
			}, function()
				openBotEditor(current, slotIndex)
			end)
			view.Rows[index] = row
		end
		local slot = type(bots) == "table" and bots[index] or nil
		if type(slot) == "table" and type(slot.Preset) == "string" then
			local def = botDef(slot.Preset)
			setText(
				row.Title,
				T("term.bot.slot", index) .. " · " .. (if def then ctx.Lang.Pick(lang(), def.Name) else slot.Preset)
			)
			setText(row.Desc, if def then ctx.Lang.Pick(lang(), def.Desc) else "")
			local status: string
			if slot.Paused == true then
				status = string.format('<font color="%s">%s</font>', UI.ColorHex(Theme.Warn), T("term.bot.paused"))
			elseif slot.On == true then
				status = string.format('<font color="%s">%s</font>', UI.ColorHex(UI.UpColor()), T("term.bot.running"))
			else
				status = T("term.bot.stopped")
			end
			status ..= "  ·  " .. T("term.bot.share", pct(num(slot.Pct, 0), 0))
			if type(slot.Target) == "number" then
				status ..= "  ·  " .. T("term.bot.target", tickerOf(slot.Target))
			end
			setText(row.Status, status)
			row.Toggle.SetText(T(if slot.On == true then "term.bot.off" else "term.bot.on"))
			row.Toggle.SetVariant(if slot.On == true then "Danger" else "Success")
			row.Change.SetText(T("term.bot.change"))
			row.Change.Frame.Visible = true
		else
			setText(row.Title, T("term.bot.slot", index) .. " · " .. T("term.bot.empty"))
			setText(row.Desc, T("term.bot.emptyHint"))
			setText(row.Status, "")
			row.Toggle.SetText(T("term.bot.pick"))
			row.Toggle.SetVariant("Primary")
			row.Change.Frame.Visible = false
		end
		row.Card.Visible = true
	end
	for index = slots + 1, #view.Rows do
		view.Rows[index].Card.Visible = false
	end
	-- gesperrte Strategien zeigen (Lernziel), nie kaufbar
	if not view.Parts.Locked then
		view.Parts.Locked = UI.Create("TextLabel", {
			Name = "Locked",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			FontFace = UI.Faces.Body,
			TextSize = 12,
			TextWrapped = true,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 99,
			Parent = view.Frame,
		})
	end
	local licence = 1
	local okLic, value = call("MarketClient", "Licence")
	if okLic and type(value) == "number" then
		licence = value
	end
	local locked: { string } = {}
	for _, preset in ipairs(botPresets()) do
		local def = botDef(preset)
		if def and num(def.Licence, 99) > licence then
			local okName, licName = call("MarketClient", "LicenceName", def.Licence)
			table.insert(
				locked,
				ctx.Lang.Pick(lang(), def.Name) .. " – " .. T("term.bot.locked", if okName then licName else "?")
			)
		end
	end
	setText(view.Parts.Locked, table.concat(locked, "\n"))
end

-- ---------------------------------------------------------------------
-- ABSCHNITT: PERFORMANCE (Profi: TWR, Drawdown, Skill-Score; alle: Trefferquote, Liga)
-- ---------------------------------------------------------------------
local function requestHistory()
	if historyBusy or os.clock() - historyAt < HISTORY_GAP then
		return
	end
	historyBusy = true
	historyAt = os.clock()
	task.spawn(function()
		local reply = ctx.RequestFull("DepotHistory", {}, true)
		historyBusy = false
		if reply.Ok then
			history = {
				Fills = if type(reply.Fills) == "table" then reply.Fills else {},
				Nav = if type(reply.Nav) == "table" then reply.Nav else {},
			}
			DepotView.Refresh()
		end
	end)
end

local function dayReturns(): ({ number }, { number })
	local returns: { number } = {}
	local navs: { number } = {}
	local h = history
	if not h then
		return returns, navs
	end
	for _, entry in ipairs(h.Nav) do
		if type(entry) == "table" then
			local navStart, navEnd, flow = num(entry[2], 0), num(entry[3], 0), num(entry[4], 0)
			if navStart > 0 then
				local ok, r = pcall(PortfolioMath.DayReturn, navStart, navEnd, flow)
				if ok and type(r) == "number" then
					table.insert(returns, r)
				end
			end
			table.insert(navs, navEnd)
		end
	end
	return returns, navs
end

local function updatePerformance(view: View)
	requestHistory()
	local layer = "Simple"
	local okLayer, value = call("MarketClient", "Layer")
	if okLayer and type(value) == "string" then
		layer = value
	end
	local pro = layer == "Pro"
	if not view.Parts.Grid then
		local grid: Frame = UI.Create("Frame", {
			Name = "Tiles",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = 1,
			Parent = view.Frame,
		}, {
			UI.Create("UIGridLayout", {
				CellSize = UDim2.new(0.25, -8, 0, 64),
				CellPadding = UDim2.fromOffset(8, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local keys = {
			"term.perf.trades",
			"term.perf.hit",
			"term.perf.best",
			"term.perf.tier",
			"term.perf.twr",
			"term.perf.dd",
			"trade.skillScore",
			"trade.avgDaily",
		}
		local tiles: { [string]: TextLabel } = {}
		for index, key in ipairs(keys) do
			tiles[key] = UI.StatTile(grid, T(key), index)
		end
		view.Parts.Grid = grid
		view.Parts.Tiles = tiles
		local sparkCard = UI.Card({
			Name = "NavCurve",
			Size = UDim2.new(1, 0, 0, 90),
			LayoutOrder = 2,
			Parent = view.Frame,
		})
		view.Parts.SparkTitle = UI.Create("TextLabel", {
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(1, -24, 0, 16),
			BackgroundTransparency = 1,
			FontFace = UI.Faces.BodyBold,
			TextSize = 12,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "",
			Parent = sparkCard,
		})
		local sparkHolder: Frame = UI.Create("Frame", {
			Position = UDim2.fromOffset(12, 26),
			Size = UDim2.new(1, -24, 1, -34),
			BackgroundTransparency = 1,
			Parent = sparkCard,
		})
		view.Parts.Spark = UI.Sparkline(sparkHolder, 72)
		view.Parts.FillsTitle = UI.Section(view.Frame, "", 3)
		view.Parts.Fills = {}
		for index = 1, MAX_FILL_ROWS do
			local card: Frame = UI.RowCard(view.Frame, 10 + index, 34)
			table.insert(view.Parts.Fills, {
				Card = card,
				Text = cell(card, 0, 1, {
					Position = UDim2.fromOffset(12, 0),
					Size = UDim2.new(1, -24, 1, 0),
					TextSize = 12,
				}),
			})
			card.Visible = false
		end
	end
	local tiles = view.Parts.Tiles
	for key, label in pairs(tiles) do
		local caption = label.Parent and label.Parent:FindFirstChild("Caption")
		if caption and caption:IsA("TextLabel") then
			setText(caption, T(key))
		end
	end
	local stats = depot().Stats
	stats = if type(stats) == "table" then stats else {}
	local wins, losses = num(stats.Wins, 0), num(stats.Losses, 0)
	setText(tiles["term.perf.trades"], tostring(math.floor(num(stats.Trades, 0))))
	setText(tiles["term.perf.hit"], if wins + losses > 0 then pct(wins / (wins + losses), 0) else "–")
	setText(tiles["term.perf.best"], if num(stats.BestPct, 0) ~= 0 then pct(num(stats.BestPct, 0)) else "–")
	local l = league()
	local tier = if type(l.Tier) == "string" then l.Tier else "None"
	setText(tiles["term.perf.tier"], T("trade.tier" .. (if tier == "None" then "None" else tier)))
	local returns, navs = dayReturns()
	local twr = 0
	local dd = 0
	if #returns > 0 then
		local okTwr, valueTwr = pcall(PortfolioMath.Twr, returns)
		twr = if okTwr and type(valueTwr) == "number" then valueTwr else 0
		local okDd, valueDd = pcall(PortfolioMath.MaxDrawdown, returns)
		dd = if okDd and type(valueDd) == "number" then valueDd else 0
	end
	-- Profi-Kennzahlen nur in der Profi-Schicht (§B7.2)
	for _, key in ipairs({ "term.perf.twr", "term.perf.dd", "trade.skillScore", "trade.avgDaily" }) do
		local tile = tiles[key]
		if tile.Parent and tile.Parent:IsA("GuiObject") then
			tile.Parent.Visible = pro
		end
	end
	if pro then
		setText(tiles["term.perf.twr"], if #returns > 0 then pct(twr) else "–")
		tiles["term.perf.twr"].TextColor3 = UI.TrendColor(twr)
		setText(tiles["term.perf.dd"], if #returns > 0 then pct(-dd) else "–")
		setText(tiles["trade.skillScore"], tostring(math.floor(num(l.SkillScore, 0))))
		local avg = num(l.AvgDailyBp, 0) / 10000
		setText(tiles["trade.avgDaily"], pct(avg))
		tiles["trade.avgDaily"].TextColor3 = UI.TrendColor(avg)
	end
	setText(view.Parts.SparkTitle, UI.Upper(T("term.perf.curve")))
	view.Parts.Spark.Set(navs)
	setText(view.Parts.FillsTitle, T("term.perf.fills"))
	local fills = if history then history.Fills else {}
	local shown = 0
	for index = #fills, 1, -1 do
		if shown >= MAX_FILL_ROWS then
			break
		end
		local fill = fills[index]
		if type(fill) == "table" then
			shown += 1
			local row = view.Parts.Fills[shown]
			local side = T(if fill[3] == "B" or fill[3] == 1 then "term.side.B" else "term.side.S")
			local text = string.format(
				"%s · %s %d × %s",
				tickerOf(num(fill[2], 0)),
				side,
				num(fill[4], 0),
				price(num(fill[5], 0))
			)
			local pnl = fill[7]
			if type(pnl) == "number" and pnl ~= 0 then
				text ..= string.format(
					'  <font color="%s">%s %s</font>',
					UI.ColorHex(UI.TrendColor(pnl)),
					UI.TrendArrow(pnl),
					aky(pnl, true)
				)
			end
			setText(row.Text, text)
			row.Card.Visible = true
		end
	end
	for index = shown + 1, MAX_FILL_ROWS do
		view.Parts.Fills[index].Card.Visible = false
	end
end

-- ---------------------------------------------------------------------
-- MONTIEREN / AKTUALISIEREN
-- ---------------------------------------------------------------------
local UPDATERS: { [string]: (View) -> () } = {
	Positions = updatePositions,
	Orders = updateOrders,
	Alerts = updateAlerts,
	Overview = updateOverview,
	Bots = updateBots,
	Performance = updatePerformance,
}

local function onScreen(inst: Instance): boolean
	local current: Instance? = inst
	local guard = 0
	while current and guard < 32 do
		guard += 1
		if current:IsA("GuiObject") then
			if not current.Visible then
				return false
			end
		elseif current:IsA("LayerCollector") then
			return current.Enabled
		end
		current = current.Parent
	end
	return false
end

local function updateView(view: View)
	if not view.Alive then
		return
	end
	local ok, err = pcall(view.Update, view)
	if not ok then
		warn("[DepotView] " .. view.Section .. ": " .. tostring(err))
	end
end

function DepotView.Refresh()
	for _, view in ipairs(views) do
		if view.Alive and onScreen(view.Frame) then
			updateView(view)
		end
	end
end

local function schedule()
	if pending then
		return
	end
	pending = true
	task.delay(REFRESH_GAP, function()
		pending = false
		DepotView.Refresh()
	end)
end

function DepotView.Mount(parent: Instance, section: string): { [string]: any }
	local update = UPDATERS[section] or updatePositions
	local view: View = {
		Section = if UPDATERS[section] then section else "Positions",
		Frame = newList(parent),
		Alive = true,
		Rows = {},
		Parts = {},
		Update = update,
	}
	table.insert(views, view)
	updateView(view)
	return {
		Frame = view.Frame,
		Refresh = function()
			updateView(view)
		end,
		Destroy = function()
			view.Alive = false
			local index = table.find(views, view)
			if index then
				table.remove(views, index)
			end
			view.Frame:Destroy()
		end,
	}
end

function DepotView.Open(section: string?)
	call("Terminal", "Open")
	call("Terminal", "ShowTab", section or "Overview")
end

function DepotView.Init(context: any)
	ctx = context
	local hooks = ctx.Hooks
	hooks.On("State", function(_state, changed)
		if type(changed) ~= "table" then
			return
		end
		if changed.Depot or changed.League or changed.Prog then
			schedule()
		end
	end)
	hooks.On("Quotes", function()
		schedule() -- G/V und Depotwert live (1 Hz)
	end)
	hooks.On("Settings", schedule)
end

function DepotView.Start() end

return DepotView
