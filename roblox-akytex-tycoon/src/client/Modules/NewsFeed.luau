-- =====================================================================
--  AKYTEX TYCOON – Eilmeldungen: News-Karte („Dynamic Island“), News-Liste, Tiko-Ampel, Termine (Client/Modules/NewsFeed)
--  Besitzer: WP5 (Charts, Terminal, Markt-UI). Vertrag: DESIGN.md §B7.4 (Karte, Drosselung, Tiko-Ampel, Liste 50),
--  §0.3 Punkt 5 (kein Kauf-Knopf, kein Blinken, kein Countdown), §C15 (Client lokalisiert News), §C7.5 (NewsFeed.Recent),
--  §B1 (Pille „nächster Termin der Watchlist“); MARKET.md §6.1/§6.2 (8 s Lesefenster, Stärke-Wörter).
--
--  Karte gleitet oben in der Mitte ein, NUR wenn: Wert gehalten oder auf der Watchlist UND Stärke ≥ „deutlich“, oder
--  Makro/Sektor/Crash/Rallye/IPO (+ Warnstufe, Admin-Eilmeldung). Höchstens 1 Karte je 30 s (Rest nur in der Liste).
--  Einstellung „NewsCards“: Normal · Quiet (Ruhemodus: nur Crash/Rallye; die Glocke zeigt EffectsMarket) · Off.
--  Inhalt: Art-Chip, Quellen-Sterne, Sektor-Chip, Schlagzeile mit fettem Stärke-Wort, ruhiger Balken „Händler lesen …“
--  (8 s ab Veröffentlichung), danach „Markt reagiert“. Knöpfe nur „Zum Chart“ und „×“ – KEIN Kauf-Knopf.
--  Tiko-Ampel (für die Schicht „Einfach“, optional „Trader“; das Terminal entscheidet): Fakten-News -> nach 20 s
--  grün/rot (Richtung der Meldung), Gerücht/„wie erwartet“ -> „?“ mit einem Erklär-Satz.
--  Liste endlich: letzte 50 (kein endloser Feed). Seed beim Start über Request "MktNews", danach Hook "Market:News".
--  Termine: Request "MktCalendar" { Days = 1 } (Start, Glocke, Kalender-Delta) -> Hud-Pille "Earnings".
--
--  Öffentliche API (§C7.5):
--    NewsFeed.Recent(): { Types.NewsItem }            neueste zuerst, höchstens 50 (Kopie)
--  Zusätzlich: NewsFeed.Text(item, plain?): string (lokalisiert, RichText mit fettem Stärke-Wort, plain = ohne Markup)
--    NewsFeed.KindLabel(item) · NewsFeed.Ampel(item): (state, text) · NewsFeed.LatestFor(instId, factOnly?)
--    NewsFeed.Mount(parent, opts?): { Frame, Refresh, SetFilter, Destroy }   (Listen für Terminal/Handy-Tab)
--    NewsFeed.Calendar(): { Types.CalendarItem }      kommende Termine (sortiert)
--    NewsFeed.Tick(), NewsFeed.Init(ctx), NewsFeed.Start()
-- =====================================================================

local TweenService = game:GetService("TweenService")

local UI = require(script.Parent:WaitForChild("UI"))

local NewsFeed = {}

type Item = { [string]: any }
type ListRow = {
	Frame: TextButton,
	Time: TextLabel,
	Kind: TextLabel,
	Head: TextLabel,
	Dot: Frame,
	Item: Item?,
	Lang: string,
}
type ListView = {
	Frame: ScrollingFrame,
	Rows: { ListRow },
	Filter: ((Item) -> boolean)?,
	Max: number,
	Alive: boolean,
	Empty: TextLabel,
}

local Theme = UI.Theme
local MAX_ITEMS = 50
local CARD_GAP = 30 -- höchstens 1 Karte je 30 s (§B7.4)
local CARD_MAX_AGE = 20 -- ältere Meldungen (z. B. Seed beim Beitritt) bekommen keine Karte
local CARD_STAY = 7 -- nach dem Lesefenster noch so lange sichtbar
local AMPEL_AFTER = 20 -- Tiko-Ampel zeigt die Richtung 20 s nach der Meldung
local CARD_W = 540
local CARD_H = 112
local CARD_TOP = 74 -- unter Ticker-Leiste + Pillen
local CALENDAR_REFRESH = 300
local PILL_REFRESH = 5
local IN_INFO = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local OUT_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local FACT_KINDS: { [string]: boolean } = { Fact = true, Confirm = true, Deny = true, Earnings = true }
local CARD_KINDS: { [string]: boolean } = { Macro = true, Sector = true, Ipo = true, Admin = true }
local CRASH_KINDS: { [string]: boolean } = { Crash = true, Rally = true, Warn = true }

local ctx: any = nil
local items: { Item } = {}
local seen: { [number]: boolean } = {}
local lists: { ListView } = {}
local calendar: { Item } = {}
local lastCardAt = -math.huge
local cardItem: Item? = nil
local cardToken = 0
local calendarAt = -math.huge
local pillClock = 0
local listDirty = false

-- Karten-Oberfläche
local card: Frame? = nil
local cardScale: UIScale? = nil
local cardStripe: Frame? = nil
local cardKind: TextLabel? = nil
local cardSector: TextLabel? = nil
local cardHead: TextLabel? = nil
local cardBarFill: Frame? = nil
local cardBarText: TextLabel? = nil
local cardChart: any = nil

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function lang(): string
	return ctx.Lang_()
end

local function call(name: string, fnName: string, ...: any): (boolean, any, any)
	local modules = ctx and ctx.Modules
	local m = modules and modules[name]
	local fn = m and m[fnName]
	if type(fn) ~= "function" then
		return false, nil, nil
	end
	return pcall(fn, ...)
end

local function escape(text: string): string
	local out = string.gsub(text, "&", "&amp;")
	out = string.gsub(out, "<", "&lt;")
	out = string.gsub(out, ">", "&gt;")
	return out
end

local function nowTick(): number
	local ok, tick = pcall(ctx.Clock.Tick)
	return if ok and type(tick) == "number" then tick else 0
end

local function settings(): { [string]: any }
	local ok, value = call("Settings", "Get")
	if ok and type(value) == "table" then
		return value
	end
	local s = ctx.State.Settings
	return if type(s) == "table" then s else {}
end

local function depot(): { [string]: any }
	local d = ctx.State.Depot
	return if type(d) == "table" then d else {}
end

local function held(i: number): boolean
	local pos = depot().Pos
	local p = type(pos) == "table" and pos[tostring(i)] or nil
	return type(p) == "table" and type(p.Q) == "number" and p.Q > 0
end

local function watched(i: number): boolean
	local watch = depot().Watch
	if type(watch) ~= "table" then
		return false
	end
	for _, list in ipairs(watch) do
		if type(list) == "table" and table.find(list, i) then
			return true
		end
	end
	return false
end

local function readDelay(): number
	local market = ctx.Config and ctx.Config.Market
	local delay = type(market) == "table" and market.Delay or nil
	return if type(delay) == "number" and delay > 0 then delay else 8
end

local function ageOf(item: Item): number
	return math.max(0, ctx.Clock.Now() - ctx.Clock.UnixOf(item.T or 0))
end

local function instName(i: number?): (string?, string?)
	if type(i) ~= "number" then
		return nil, nil
	end
	local ok, inst = call("MarketClient", "Instrument", i)
	if ok and type(inst) == "table" then
		return inst.Ticker, inst.Name
	end
	return nil, nil
end

local function formatValue(key: string, value: any): string
	local l = lang()
	if type(value) == "number" then
		if key == "amt" and value % 1 ~= 0 then
			local ok, text = pcall(ctx.Format.Price, math.round(value * 100), l)
			return if ok then text else tostring(value)
		end
		local ok, text = pcall(ctx.Format.Int, value, l)
		return if ok then text else tostring(value)
	elseif type(value) == "string" then
		if ctx.Lang.Has(value) then
			return ctx.Lang.T(l, value)
		end
		return value
	end
	return ""
end

-- ---------------------------------------------------------------------
-- TEXTE
-- ---------------------------------------------------------------------
function NewsFeed.Text(item: Item, plain: boolean?): string
	if type(item) ~= "table" then
		return ""
	end
	local l = lang()
	if type(item.Text) == "table" then
		local body = ctx.Lang.Pick(l, item.Text)
		local text = ctx.T("news.admin") .. ": " .. body
		return if plain then text else escape(text)
	end
	local template = ctx.Lang.T(l, if type(item.Key) == "string" then item.Key else "news.admin")
	local args = if type(item.Args) == "table" then item.Args else {}
	if not plain then
		template = escape(template)
	end
	local text = string.gsub(template, "{(%a+)}", function(key: string): string
		local value = formatValue(key, args[key])
		if plain then
			return value
		end
		if key == "band" then
			return "<b>" .. escape(value) .. "</b>"
		end
		return escape(value)
	end)
	return text
end

function NewsFeed.KindLabel(item: Item): string
	local kind = if type(item) == "table" and type(item.Kind) == "string" then item.Kind else "Fact"
	local label = ctx.T("term.kind." .. kind)
	if kind == "Rumor" and type(item.Stars) == "number" then
		label ..= " " .. string.rep("★", math.clamp(math.floor(item.Stars), 1, 3))
	end
	return label
end

-- Tiko-Ampel: state "wait" | "up" | "down" | "rumor" | "expected" | "none"
function NewsFeed.Ampel(item: Item?): (string, string)
	if type(item) ~= "table" then
		return "none", ctx.T("term.ampel.none")
	end
	local kind = item.Kind
	if kind == "Rumor" then
		return "rumor", ctx.T("term.ampel.rumor")
	elseif kind == "AsExpected" then
		return "expected", ctx.T("term.ampel.expected")
	elseif FACT_KINDS[kind] and type(item.Dir) == "number" and item.Dir ~= 0 then
		if ageOf(item) < AMPEL_AFTER then
			return "wait", ctx.T("term.ampel.wait")
		end
		if item.Dir > 0 then
			return "up", ctx.T("term.ampel.up")
		end
		return "down", ctx.T("term.ampel.down")
	end
	return "none", ctx.T("term.ampel.none")
end

-- neueste Meldung zu einem Wert (factOnly: nur Fakten/Gerücht/„wie erwartet“ – für die Ampel)
function NewsFeed.LatestFor(i: number, factOnly: boolean?): Item?
	for _, item in ipairs(items) do
		if item.I == i then
			if not factOnly or FACT_KINDS[item.Kind] or item.Kind == "Rumor" or item.Kind == "AsExpected" then
				return item
			end
		end
	end
	return nil
end

function NewsFeed.Recent(): { Item }
	return table.clone(items)
end

-- ---------------------------------------------------------------------
-- KARTE („Dynamic Island“)
-- ---------------------------------------------------------------------
local function buildCard()
	local root: Frame = UI.Create("Frame", {
		Name = "NewsCard",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -CARD_H - 20),
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 40,
		Parent = ctx.Gui,
	}, {
		UI.Corner(18),
		UI.Stroke(nil, 1),
		UI.Create("UISizeConstraint", { MaxSize = Vector2.new(CARD_W, CARD_H) }),
	})
	cardScale = UI.Create("UIScale", { Parent = root })
	cardStripe = UI.Create("Frame", {
		Name = "Stripe",
		Position = UDim2.fromOffset(10, 14),
		Size = UDim2.new(0, 3, 1, -28),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		ZIndex = 41,
		Parent = root,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	cardKind = UI.Create("TextLabel", {
		Name = "Kind",
		Position = UDim2.fromOffset(22, 10),
		Size = UDim2.new(0.5, -22, 0, 16),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.MonoBold,
		TextSize = 12,
		TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		ZIndex = 41,
		Parent = root,
	})
	cardSector = UI.Create("TextLabel", {
		Name = "Sector",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -52, 0, 10),
		Size = UDim2.new(0.5, -60, 0, 16),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.BodyBold,
		TextSize = 12,
		TextColor3 = Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
		ZIndex = 41,
		Parent = root,
	})
	cardHead = UI.Create("TextLabel", {
		Name = "Headline",
		Position = UDim2.fromOffset(22, 30),
		Size = UDim2.new(1, -44, 0, 40),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.Body,
		TextSize = 16,
		TextWrapped = true,
		RichText = true,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
		ZIndex = 41,
		Parent = root,
	})
	local bar: Frame = UI.Create("Frame", {
		Name = "Bar",
		Position = UDim2.new(0, 22, 1, -26),
		Size = UDim2.new(1, -178, 0, 6),
		BackgroundColor3 = Theme.Bg2,
		BorderSizePixel = 0,
		ZIndex = 41,
		Parent = root,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	cardBarFill = UI.Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Accent,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		ZIndex = 42,
		Parent = bar,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	cardBarText = UI.Create("TextLabel", {
		Name = "BarText",
		Position = UDim2.new(0, 22, 1, -20),
		Size = UDim2.new(1, -178, 0, 16),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.Body,
		TextSize = 12,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		ZIndex = 41,
		Parent = root,
	})
	cardChart = UI.Button({
		Name = "ToChart",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -10),
		Size = UDim2.fromOffset(128, 32),
		Text = ctx.T("term.news.toChart"),
		Variant = "Secondary",
		MaxText = 14,
		Corner = 10,
		ZIndex = 43,
		Parent = root,
	}, function()
		local item = cardItem
		if item and type(item.I) == "number" then
			call("Terminal", "OpenAt", item.I)
		end
		NewsFeed.HideCard()
	end)
	UI.Button({
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 6),
		Size = UDim2.fromOffset(32, 32),
		Text = "✕",
		Variant = "Ghost",
		MaxText = 16,
		Corner = 10,
		ZIndex = 43,
		Parent = root,
	}, function()
		NewsFeed.HideCard()
	end)
	card = root
end

function NewsFeed.HideCard()
	local root = card
	if not root or not root.Visible then
		return
	end
	cardToken += 1
	local token = cardToken
	local tween = TweenService:Create(root, OUT_INFO, { Position = UDim2.new(0.5, 0, 0, -CARD_H - 20) })
	tween.Completed:Once(function()
		if cardToken == token then
			root.Visible = false
			cardItem = nil
		end
	end)
	tween:Play()
end

local function kindColor(item: Item): Color3
	local kind = item.Kind
	if kind == "Crash" or (kind == "Warn" and (item.Dir or 0) < 0) then
		return UI.DownColor()
	elseif kind == "Rally" then
		return UI.UpColor()
	elseif kind == "Admin" then
		return Theme.Warn
	elseif kind == "Rumor" then
		return Theme.Purple
	end
	return Theme.Accent
end

local function showCard(item: Item)
	if not card then
		buildCard()
	end
	local root = card :: Frame
	cardItem = item
	cardToken += 1
	local token = cardToken
	local color = kindColor(item)
	local sectorText = ""
	local sectorColor = Theme.Text2
	if type(item.I) == "number" then
		local okSector, sector = call("MarketClient", "Sector", item.I)
		local ticker = instName(item.I)
		if okSector and type(sector) == "table" then
			sectorText = (ticker or "") .. " · " .. tostring(sector.Name)
			sectorColor = sector.Color
		end
	elseif type(item.Sector) == "string" then
		local sectors = ctx.Config.Companies and ctx.Config.Companies.Sectors
		if type(sectors) == "table" then
			for _, sector in ipairs(sectors) do
				if sector.Key == item.Sector then
					sectorText = ctx.Lang.Pick(lang(), sector.Name)
					sectorColor = sector.Color
				end
			end
		end
	end
	if cardStripe then
		cardStripe.BackgroundColor3 = color
	end
	if cardKind then
		cardKind.Text = UI.Upper(ctx.T("term.news.breaking") .. " · " .. NewsFeed.KindLabel(item))
		cardKind.TextColor3 = color
	end
	if cardSector then
		cardSector.Text = sectorText
		cardSector.TextColor3 = sectorColor
	end
	if cardHead then
		cardHead.Text = NewsFeed.Text(item, false)
	end
	local allowed = false
	if type(item.I) == "number" then
		local ok, value = call("MarketClient", "Allowed", item.I)
		allowed = ok and value == true
	end
	cardChart.Frame.Visible = allowed
	cardChart.SetText(ctx.T("term.news.toChart"))
	-- ruhiger Lese-Balken (8 s ab Veröffentlichung), danach „Markt reagiert“
	local delay = readDelay()
	local age = ageOf(item)
	local fill = cardBarFill :: Frame
	local barText = cardBarText :: TextLabel
	fill.BackgroundColor3 = color
	if age < delay then
		fill.Size = UDim2.fromScale(math.clamp(age / delay, 0, 1), 1)
		barText.Text = ctx.T("trade.readingBar")
		local reading = TweenService:Create(
			fill,
			TweenInfo.new(delay - age, Enum.EasingStyle.Linear),
			{ Size = UDim2.fromScale(1, 1) }
		)
		reading.Completed:Once(function()
			if cardToken == token then
				barText.Text = ctx.T("trade.marketReacts")
			end
		end)
		reading:Play()
	else
		fill.Size = UDim2.fromScale(1, 1)
		barText.Text = ctx.T("trade.marketReacts")
	end
	-- einblenden: von oben gleiten, leichte Feder über die Skalierung (kein CanvasGroup)
	root.Visible = true
	root.Position = UDim2.new(0.5, 0, 0, -CARD_H - 20)
	if cardScale then
		cardScale.Scale = 0.96
		TweenService:Create(cardScale, IN_INFO, { Scale = 1 }):Play()
	end
	TweenService:Create(root, IN_INFO, { Position = UDim2.new(0.5, 0, 0, CARD_TOP) }):Play()
	call("Sfx", "Play", "Notify")
	task.delay(math.max(0, delay - age) + CARD_STAY, function()
		if cardToken == token then
			NewsFeed.HideCard()
		end
	end)
end

local function eligible(item: Item): boolean
	local mode = settings().NewsCards
	if mode == "Off" then
		return false
	end
	local kind = item.Kind
	if mode == "Quiet" then
		return CRASH_KINDS[kind] == true
	end
	if CRASH_KINDS[kind] or CARD_KINDS[kind] then
		return true
	end
	local i = item.I
	if type(i) == "number" and (held(i) or watched(i)) and type(item.Band) == "number" and item.Band >= 2 then
		return true
	end
	return false
end

-- ---------------------------------------------------------------------
-- LISTEN
-- ---------------------------------------------------------------------
local function timeAgo(item: Item): string
	local age = ageOf(item)
	if age < 60 then
		return ctx.T("term.news.now")
	elseif age < 3600 then
		return ctx.T("term.news.ago", ctx.T("term.minutes", math.floor(age / 60)))
	end
	local ok, text = pcall(ctx.Format.Duration, age, lang())
	return ctx.T("term.news.ago", if ok then text else tostring(math.floor(age)))
end

local function ampelColor(stateName: string): Color3
	if stateName == "up" then
		return UI.UpColor()
	elseif stateName == "down" then
		return UI.DownColor()
	elseif stateName == "rumor" or stateName == "expected" then
		return Theme.Warn
	end
	return Theme.Muted
end

local function newRow(view: ListView, order: number)
	local frame: TextButton = UI.Create("TextButton", {
		Name = "News",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Surface2,
		BackgroundTransparency = 0.2,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Parent = view.Frame,
	}, {
		UI.Corner(10),
		UI.Create("UIPadding", {
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 10),
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 8),
		}),
		UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }),
	})
	local top: Frame = UI.Create("Frame", {
		Name = "Top",
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = frame,
	})
	local dot: Frame = UI.Create("Frame", {
		Name = "Ampel",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(8, 8),
		BackgroundColor3 = Theme.Muted,
		BorderSizePixel = 0,
		Visible = false,
		Parent = top,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local kind: TextLabel = UI.Create("TextLabel", {
		Name = "Kind",
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(0.6, -14, 1, 0),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.MonoBold,
		TextSize = 11,
		TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		Parent = top,
	})
	local time: TextLabel = UI.Create("TextLabel", {
		Name = "Time",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.4, 0, 1, 0),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.Mono,
		TextSize = 11,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "",
		Parent = top,
	})
	local head: TextLabel = UI.Create("TextLabel", {
		Name = "Head",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		FontFace = UI.Faces.Body,
		TextSize = 14,
		TextWrapped = true,
		RichText = true,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		LayoutOrder = 2,
		Parent = frame,
	})
	local row: ListRow = { Frame = frame, Time = time, Kind = kind, Head = head, Dot = dot, Item = nil, Lang = "" }
	frame.Activated:Connect(function()
		local item = row.Item
		if item and type(item.I) == "number" then
			call("Terminal", "OpenAt", item.I)
		end
	end)
	table.insert(view.Rows, row)
end

local function refreshView(view: ListView)
	if not view.Alive then
		return
	end
	local shown = 0
	for _, item in ipairs(items) do
		if shown >= view.Max then
			break
		end
		local filter = view.Filter
		local pass = true
		if filter then
			local ok, value = pcall(filter, item)
			pass = ok and value == true
		end
		if pass then
			shown += 1
			if not view.Rows[shown] then
				newRow(view, shown)
			end
			local row = view.Rows[shown]
			local l = lang()
			if row.Item ~= item or row.Lang ~= l then
				-- Texte nur bei neuem Eintrag oder Sprachwechsel neu bauen
				row.Item = item
				row.Lang = l
				row.Head.Text = NewsFeed.Text(item, false)
				local kindText = UI.Upper(NewsFeed.KindLabel(item))
				local ticker = instName(item.I)
				if ticker then
					kindText ..= " · " .. ticker
				end
				row.Kind.Text = kindText
				row.Kind.TextColor3 = kindColor(item)
			end
			local ago = timeAgo(item)
			if row.Time.Text ~= ago then
				row.Time.Text = ago
			end
			local stateName = NewsFeed.Ampel(item)
			local showDot = stateName ~= "none"
			row.Dot.Visible = showDot
			if showDot then
				row.Dot.BackgroundColor3 = ampelColor(stateName)
			end
			if not row.Frame.Visible then
				row.Frame.Visible = true
			end
		end
	end
	for index = shown + 1, #view.Rows do
		local row = view.Rows[index]
		row.Item = nil
		if row.Frame.Visible then
			row.Frame.Visible = false
		end
	end
	view.Empty.Visible = shown == 0
	view.Empty.Text = ctx.T("term.news.empty")
end

function NewsFeed.Mount(parent: Instance, opts: { [string]: any }?): { [string]: any }
	local o = opts or {}
	local frame: ScrollingFrame = UI.Create("ScrollingFrame", {
		Name = "NewsList",
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
		UI.Create("UIPadding", { PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }),
	})
	local empty: TextLabel = UI.Create("TextLabel", {
		Name = "Empty",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.Body,
		TextSize = 14,
		TextColor3 = Theme.Muted,
		Text = "",
		LayoutOrder = 0,
		Parent = frame,
	})
	local view: ListView = {
		Frame = frame,
		Rows = {},
		Filter = if type(o.Filter) == "function" then o.Filter else nil,
		Max = math.clamp(math.floor(tonumber(o.Max) or MAX_ITEMS), 1, MAX_ITEMS),
		Alive = true,
		Empty = empty,
	}
	table.insert(lists, view)
	refreshView(view)
	return {
		Frame = frame,
		Refresh = function()
			refreshView(view)
		end,
		SetFilter = function(fn: ((Item) -> boolean)?)
			view.Filter = fn
			refreshView(view)
		end,
		Destroy = function()
			view.Alive = false
			local index = table.find(lists, view)
			if index then
				table.remove(lists, index)
			end
			frame:Destroy()
		end,
	}
end

-- sichtbar = alle GUI-Vorfahren sichtbar (Tabs blenden ganze Container aus)
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

local function refreshLists()
	listDirty = false
	for _, view in ipairs(lists) do
		if view.Alive and onScreen(view.Frame) then
			refreshView(view)
		else
			listDirty = true
		end
	end
end

-- ---------------------------------------------------------------------
-- NEWS EINSORTIEREN
-- ---------------------------------------------------------------------
local function valid(item: any): boolean
	return type(item) == "table"
		and type(item.Id) == "number"
		and type(item.T) == "number"
		and type(item.Key) == "string"
		and type(item.Kind) == "string"
end

local function insert(item: Item): boolean
	if not valid(item) or seen[item.Id] then
		return false
	end
	seen[item.Id] = true
	local index = #items + 1
	for k, other in ipairs(items) do
		if item.T > other.T or (item.T == other.T and item.Id > other.Id) then
			index = k
			break
		end
	end
	table.insert(items, index, item)
	while #items > MAX_ITEMS do
		local removed = table.remove(items)
		if removed then
			seen[removed.Id] = nil
		end
	end
	return true
end

local function onNews(item: any)
	if not insert(item) then
		return
	end
	local now = os.clock()
	if now - lastCardAt >= CARD_GAP and ageOf(item) <= CARD_MAX_AGE and eligible(item) then
		lastCardAt = now
		showCard(item)
	end
	refreshLists()
end

-- ---------------------------------------------------------------------
-- TERMINE (Kalender) + Hud-Pille „Earnings“
-- ---------------------------------------------------------------------
local function setCalendar(list: any, merge: boolean)
	if type(list) ~= "table" then
		return
	end
	local byKey: { [string]: Item } = {}
	local out: { Item } = {}
	local now = nowTick()
	local function add(entry: any)
		if type(entry) == "table" and type(entry.T) == "number" and type(entry.Key) == "string" and entry.T >= now then
			local key = tostring(entry.T) .. ":" .. tostring(entry.Kind) .. ":" .. tostring(entry.I or 0)
			if not byKey[key] then
				byKey[key] = entry
				table.insert(out, entry)
			end
		end
	end
	if merge then
		for _, entry in ipairs(calendar) do
			add(entry)
		end
	end
	for _, entry in ipairs(list) do
		add(entry)
	end
	table.sort(out, function(a: Item, b: Item): boolean
		if a.T ~= b.T then
			return a.T < b.T
		end
		return (a.I or 0) < (b.I or 0)
	end)
	while #out > 120 do
		table.remove(out)
	end
	calendar = out
end

local function requestCalendar()
	calendarAt = os.clock()
	task.spawn(function()
		local reply = ctx.RequestFull("MktCalendar", { Days = 1 }, true)
		if reply.Ok then
			setCalendar(reply.Items, false)
		end
	end)
end

function NewsFeed.Calendar(): { Item }
	local now = nowTick()
	local out: { Item } = {}
	for _, entry in ipairs(calendar) do
		if entry.T >= now then
			table.insert(out, entry)
		end
	end
	return out
end

local function updatePill()
	local now = nowTick()
	local nextItem: Item? = nil
	for _, entry in ipairs(calendar) do
		if entry.Kind == "Earnings" and entry.T > now and type(entry.I) == "number" then
			if held(entry.I) or watched(entry.I) then
				nextItem = entry
				break
			end
		end
	end
	if nextItem then
		local ticker = instName(nextItem.I) or "?"
		call("Hud", "SetPill", "Earnings", ctx.T("term.pill.earnings", ticker), ctx.Clock.UnixOf(nextItem.T))
	else
		call("Hud", "SetPill", "Earnings", nil, nil)
	end
end

-- ---------------------------------------------------------------------
-- TAKT
-- ---------------------------------------------------------------------
function NewsFeed.Tick()
	if listDirty then
		refreshLists()
	else
		-- „vor x min“ und Ampel-Wechsel (20 s) aktualisieren – nur sichtbare Listen
		for _, view in ipairs(lists) do
			if view.Alive and onScreen(view.Frame) then
				refreshView(view)
			end
		end
	end
	pillClock += 1
	if pillClock >= PILL_REFRESH then
		pillClock = 0
		updatePill()
	end
	if os.clock() - calendarAt >= CALENDAR_REFRESH then
		requestCalendar()
	end
end

function NewsFeed.Init(context: any)
	ctx = context
	local hooks = ctx.Hooks
	hooks.On("Market:News", function(item)
		local ok, err = pcall(onNews, item)
		if not ok then
			warn("[NewsFeed] " .. tostring(err))
		end
	end)
	hooks.On("Market:Calendar", function(delta)
		setCalendar(delta, true)
	end)
	hooks.On("Market:Bell", function()
		task.delay(2, requestCalendar)
	end)
	hooks.On("Settings", function()
		refreshLists()
		if cardChart then
			cardChart.SetText(ctx.T("term.news.toChart"))
		end
	end)
	hooks.On("State", function(_state, changed)
		if type(changed) == "table" and (changed.Depot or changed.Prog) then
			listDirty = true
		end
	end)
end

function NewsFeed.Start()
	task.delay(3, function()
		local reply = ctx.RequestFull("MktNews", {}, true)
		if reply.Ok and type(reply.Items) == "table" then
			for _, item in ipairs(reply.Items) do
				insert(item)
			end
			refreshLists()
		end
		requestCalendar()
	end)
end

return NewsFeed
