-- =====================================================================
--  AKYTEX TYCOON – Markt-Effekte: Glocke, „Gut gelesen!“, Tagesbilanz, G/V-Tick (Client/Modules/EffectsMarket)
--  Besitzer: WP5 (Charts, Terminal, Markt-UI). Vertrag: DESIGN.md §C7.4 (Effekte Bell, ReadWell, DayRecap – Daten
--  {Day, Return?, Transfer?}), §A7 #3 (Glocke bei Sonnenaufgang: Glocke schwingt, Lichtwelle über alle Ticker-Wände,
--  „Gewinn-Transfer wieder frei“, Tagesbilanz-Karte federt von rechts), §A7 #4 („Gut gelesen“: kleiner Chip + 10 XP),
--  §B7.6 + §0.3 Punkt 6 (ruhiges Feedback: Gewinn = grüner G/V-Tick + Profit-Arpeggio, Verlust = grauer Tick +
--  Lerntipp; kein Konfetti/Geldregen für einzelne Trades), §A4 (Sfx-Rollen MarketBell/Profit/Loss).
--
--  Auslöser: Remote "Market" Bell -> Hook "Market:Bell" -> Effects.Play("Bell") · Remote "Market" DayClose (je Spieler)
--  -> Hook "Market:DayClose" -> Effects.Play("DayRecap") · Server-Effekt "ReadWell" (OrderService) -> Effects.Play.
--  Je Börsentag höchstens eine Glocke und eine Tagesbilanz (doppelte Pakete werden ignoriert). Nach lokalem Abspielen
--  feuert das Modul den Hook "Effect:<Name>" (gleicher Vertrag wie bei Server-Effekten).
--  Reduzierte Effekte (Einstellung ReducedFx): keine Schwing-Animation, kürzere Einblendungen.
--
--  Öffentliche API:
--    Effekte (Registry §C7.4): "Bell", "ReadWell", "DayRecap"
--    EffectsMarket.TradeTick(pnlCents, anchor?)   ruhiger G/V-Tick nach einem Verkauf (Terminal, Übung)
--    EffectsMarket.Init(ctx), EffectsMarket.Start()
-- =====================================================================

local TweenService = game:GetService("TweenService")

local UI = require(script.Parent:WaitForChild("UI"))

local EffectsMarket = {}

local Theme = UI.Theme
local BELL_STAY = 3.4
local RECAP_STAY = 8
local READWELL_STAY = 2.6
local TICK_STAY = 1.6
local LOSS_TIP_GAP = 60
local IN_INFO = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SOFT_IN = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local OUT_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local SWING_INFO = TweenInfo.new(0.36, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 5, true)

local ctx: any = nil
local lastBellDay = -1
local lastRecapDay = -1
local lastLossTip = -math.huge
local bellToken = 0
local recapToken = 0
local readToken = 0

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function call(name: string, fnName: string, ...: any): (boolean, any)
	local modules = ctx and ctx.Modules
	local m = modules and modules[name]
	local fn = m and m[fnName]
	if type(fn) ~= "function" then
		return false, nil
	end
	return pcall(fn, ...)
end

local function T(key: string, ...: any): string
	return ctx.T(key, ...)
end

local function lang(): string
	return ctx.Lang_()
end

local function reduced(): boolean
	local ok, settings = call("Settings", "Get")
	if ok and type(settings) == "table" then
		return settings.ReducedFx == true
	end
	local s = ctx.State.Settings
	return type(s) == "table" and s.ReducedFx == true
end

local function hidden(): boolean
	local ok, value = call("Effects", "IsHidden")
	return ok and value == true
end

local function aky(cents: number, compact: boolean?): string
	local ok, text = pcall(ctx.Format.Aky, cents, lang(), compact)
	return if ok then text else tostring(math.floor(cents / 100))
end

local function pct(fraction: number): string
	local ok, text = pcall(ctx.Format.Pct, fraction, lang(), 2, true)
	return if ok then text else string.format("%+.2f %%", fraction * 100)
end

local function credits(n: number): string
	local ok, text = pcall(ctx.Format.Credits, n, lang())
	return if ok then text else tostring(math.floor(n))
end

local function dayOfWeek(day: any): number
	if type(day) == "number" and day == day then
		return math.floor(day) % 504 + 1
	end
	local ok, tick = pcall(ctx.Clock.Tick)
	return if ok then (tick // 1200) % 504 + 1 else 1
end

local function label(props: { [string]: any }): TextLabel
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		FontFace = UI.Faces.Body,
		TextSize = 14,
		TextColor3 = Theme.Text,
		Text = "",
	}
	for k, v in pairs(props) do
		base[k] = v
	end
	return UI.Create("TextLabel", base)
end

-- ---------------------------------------------------------------------
-- GLOCKE (Börsentag-Beginn, §A7 #3)
-- ---------------------------------------------------------------------
local bellUi: { [string]: any }? = nil

local function buildBell(): { [string]: any }
	local root: Frame = UI.Create("Frame", {
		Name = "MarketBell",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -220),
		Size = UDim2.fromOffset(460, 150),
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 45,
		Parent = ctx.Gui,
	}, {
		UI.Corner(20),
		UI.Create("UIStroke", { Color = Theme.Gold, Thickness = 1, Transparency = 0.35 }),
	})
	local scale = UI.Create("UIScale", { Parent = root })
	-- goldene Glocke aus Frames (Krone, Kuppel, Rand, Klöppel) – schwingt um den Aufhängepunkt oben
	local pivot: Frame = UI.Create("Frame", {
		Name = "Bell",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(70, 18),
		Size = UDim2.fromOffset(84, 110),
		BackgroundTransparency = 1,
		ZIndex = 46,
		Parent = root,
	})
	local swing: Frame = UI.Create("Frame", {
		Name = "Swing",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 46,
		Parent = pivot,
	})
	UI.Create("Frame", {
		Name = "Crown",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(18, 14),
		BackgroundColor3 = Theme.Gold,
		BorderSizePixel = 0,
		ZIndex = 47,
		Parent = swing,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })
	UI.Create("Frame", {
		Name = "Dome",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(60, 70),
		BackgroundColor3 = Theme.Gold,
		BorderSizePixel = 0,
		ZIndex = 47,
		Parent = swing,
	}, {
		UI.Create("UICorner", { CornerRadius = UDim.new(0.48, 0) }),
		UI.Gradient(Theme.SpaceGold, Theme.Gold:Lerp(Color3.new(0, 0, 0), 0.25), 0),
	})
	UI.Create("Frame", {
		Name = "Rim",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 66),
		Size = UDim2.fromOffset(84, 16),
		BackgroundColor3 = Theme.Gold,
		BorderSizePixel = 0,
		ZIndex = 48,
		Parent = swing,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	UI.Create("Frame", {
		Name = "Clapper",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Theme.SpaceGold,
		BorderSizePixel = 0,
		ZIndex = 47,
		Parent = swing,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local title = label({
		Position = UDim2.fromOffset(130, 22),
		Size = UDim2.new(1, -150, 0, 30),
		FontFace = UI.Faces.Display,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 46,
		Parent = root,
	})
	local sub = label({
		Position = UDim2.fromOffset(130, 58),
		Size = UDim2.new(1, -150, 0, 24),
		FontFace = UI.Faces.BodyBold,
		TextSize = 17,
		TextColor3 = UI.UpColor(),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 46,
		Parent = root,
	})
	local tagline = label({
		Position = UDim2.fromOffset(130, 96),
		Size = UDim2.new(1, -150, 0, 18),
		FontFace = UI.Faces.DisplayRegular,
		TextSize = 12,
		TextColor3 = Theme.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 46,
		Parent = root,
	})
	return { Root = root, Scale = scale, Swing = swing, Title = title, Sub = sub, Tagline = tagline }
end

local function playBell(_strength: number, data: any)
	local day = if type(data) == "table" then data.Day else nil
	local dayKey = if type(day) == "number" then day else -2
	if dayKey == lastBellDay and dayKey ~= -2 then
		return
	end
	lastBellDay = dayKey
	call("Sfx", "Play", "MarketBell")
	call("Sfx", "Duck", 0.4, 2)
	call("Ticker", "Wave", Theme.Gold)
	if hidden() then
		return
	end
	if not bellUi then
		bellUi = buildBell()
	end
	local b = bellUi :: { [string]: any }
	bellToken += 1
	local token = bellToken
	b.Title.Text = T("term.bell.title", dayOfWeek(day))
	b.Sub.Text = T("term.bell.sub")
	b.Tagline.Text = T("core.bellTagline")
	b.Sub.TextColor3 = UI.UpColor()
	local root: Frame = b.Root
	local rest = UDim2.new(0.5, 0, 0, 84)
	root.Visible = true
	local quick = reduced()
	if quick then
		root.Position = rest
		b.Scale.Scale = 1
		b.Swing.Rotation = 0
	else
		root.Position = UDim2.new(0.5, 0, 0, -220)
		b.Scale.Scale = 0.92
		TweenService:Create(root, IN_INFO, { Position = rest }):Play()
		TweenService:Create(b.Scale, IN_INFO, { Scale = 1 }):Play()
		b.Swing.Rotation = -16
		TweenService:Create(b.Swing, SWING_INFO, { Rotation = 16 }):Play()
	end
	task.delay(if quick then BELL_STAY * 0.6 else BELL_STAY, function()
		if bellToken ~= token then
			return
		end
		local out = TweenService:Create(root, OUT_INFO, { Position = UDim2.new(0.5, 0, 0, -220) })
		out.Completed:Once(function()
			if bellToken == token then
				root.Visible = false
				b.Swing.Rotation = 0
			end
		end)
		out:Play()
	end)
end

-- ---------------------------------------------------------------------
-- TAGESBILANZ (federt von rechts herein)
-- ---------------------------------------------------------------------
local recapUi: { [string]: any }? = nil

local function hideRecap()
	local r = recapUi
	if not r or not r.Root.Visible then
		return
	end
	recapToken += 1
	local token = recapToken
	local root: Frame = r.Root
	local out = TweenService:Create(root, OUT_INFO, { Position = UDim2.new(1, 360, 0.5, 0) })
	out.Completed:Once(function()
		if recapToken == token then
			root.Visible = false
		end
	end)
	out:Play()
end

local function buildRecap(): { [string]: any }
	local root: Frame = UI.Create("Frame", {
		Name = "DayRecap",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 360, 0.5, 0),
		Size = UDim2.fromOffset(330, 196),
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 44,
		Parent = ctx.Gui,
	}, { UI.Corner(18), UI.Stroke(nil, 1) })
	local title = label({
		Position = UDim2.fromOffset(18, 14),
		Size = UDim2.new(1, -70, 0, 24),
		FontFace = UI.Faces.Display,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 45,
		Parent = root,
	})
	local day = label({
		Position = UDim2.fromOffset(18, 40),
		Size = UDim2.new(1, -36, 0, 16),
		TextSize = 12,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 45,
		Parent = root,
	})
	local caption = label({
		Position = UDim2.fromOffset(18, 66),
		Size = UDim2.new(1, -36, 0, 16),
		FontFace = UI.Faces.BodyBold,
		TextSize = 12,
		TextColor3 = Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 45,
		Parent = root,
	})
	local value = label({
		Position = UDim2.fromOffset(18, 84),
		Size = UDim2.new(1, -36, 0, 34),
		FontFace = UI.Faces.MonoBold,
		TextSize = 28,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 45,
		Parent = root,
	})
	local transfer = label({
		Position = UDim2.fromOffset(18, 124),
		Size = UDim2.new(1, -36, 0, 36),
		FontFace = UI.Faces.Mono,
		TextSize = 12,
		TextWrapped = true,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 45,
		Parent = root,
	})
	local tip = label({
		Position = UDim2.new(0, 18, 1, -26),
		Size = UDim2.new(1, -36, 0, 16),
		TextSize = 11,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 45,
		Parent = root,
	})
	UI.Button({
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(32, 32),
		Text = "✕",
		Variant = "Ghost",
		MaxText = 16,
		Corner = 10,
		ZIndex = 46,
		Parent = root,
	}, hideRecap)
	return {
		Root = root,
		Title = title,
		Day = day,
		Caption = caption,
		Value = value,
		Transfer = transfer,
		Tip = tip,
	}
end

local function transferLine(data: any): string
	local depot = ctx.State.Depot
	depot = if type(depot) == "table" then depot else {}
	if type(data) == "table" and type(data.Transfer) == "number" and data.Transfer > 0 then
		return T("term.recap.transfer", aky(data.Transfer, true))
	end
	local withdrawable = if type(depot.Withdrawable) == "number" then depot.Withdrawable else 0
	if depot.TransferReady == true and withdrawable > 0 then
		local okDef, def = call("MarketClient", "LicenceDef")
		local rate = if okDef and type(def) == "table" and type(def.BauKurs) == "number" then def.BauKurs else 40
		return T(
			"trade.transferAvail",
			aky(withdrawable, true),
			credits(math.floor(withdrawable * rate / 100)) .. " CR",
			credits(rate)
		)
	end
	if depot.AutoTransfer ~= false then
		return T("trade.autoOn")
	end
	return T("term.bell.sub")
end

local function playRecap(_strength: number, data: any)
	local day = if type(data) == "table" then data.Day else nil
	local dayKey = if type(day) == "number" then day else -2
	if dayKey == lastRecapDay and dayKey ~= -2 then
		return
	end
	lastRecapDay = dayKey
	if hidden() then
		return
	end
	if not recapUi then
		recapUi = buildRecap()
	end
	local r = recapUi :: { [string]: any }
	recapToken += 1
	local token = recapToken
	r.Title.Text = UI.Upper(T("term.recap.title"))
	r.Day.Text = T("term.recap.day", dayOfWeek(day))
	r.Caption.Text = T("term.recap.return")
	local ret = if type(data) == "table" then data.Return else nil
	if type(ret) == "number" and ret == ret then
		r.Value.Text = string.format(
			'<font color="%s">%s %s</font>',
			UI.ColorHex(UI.TrendColor(ret)),
			UI.TrendArrow(ret),
			pct(ret)
		)
		r.Value.TextSize = 28
	else
		r.Value.Text = T("term.recap.none")
		r.Value.TextSize = 15
	end
	r.Transfer.Text = transferLine(data)
	r.Tip.Text = T("term.recap.tip")
	local root: Frame = r.Root
	local rest = UDim2.new(1, -24, 0.5, 0)
	root.Visible = true
	if reduced() then
		root.Position = rest
	else
		root.Position = UDim2.new(1, 360, 0.5, 0)
		TweenService:Create(root, IN_INFO, { Position = rest }):Play()
	end
	task.delay(RECAP_STAY, function()
		if recapToken == token then
			hideRecap()
		end
	end)
end

-- ---------------------------------------------------------------------
-- „GUT GELESEN!“ (kleiner Chip, §A7 #4)
-- ---------------------------------------------------------------------
local readUi: { [string]: any }? = nil

local function playReadWell(_strength: number, data: any)
	if hidden() then
		return
	end
	if not readUi then
		local root: Frame = UI.Create("Frame", {
			Name = "ReadWell",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -150),
			Size = UDim2.fromOffset(0, 40),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = Theme.Surface,
			BackgroundTransparency = 0.04,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 46,
			Parent = ctx.Gui,
		}, {
			UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			UI.Create("UIStroke", { Color = UI.UpColor(), Thickness = 1, Transparency = 0.3 }),
			UI.Create("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) }),
		})
		local text = label({
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			FontFace = UI.Faces.BodyBold,
			TextSize = 16,
			RichText = true,
			ZIndex = 47,
			Parent = root,
		})
		readUi = { Root = root, Text = text, Scale = UI.Create("UIScale", { Parent = root }) }
	end
	local r = readUi :: { [string]: any }
	readToken += 1
	local token = readToken
	local ticker = if type(data) == "table" and type(data.Ticker) == "string" then data.Ticker else ""
	r.Text.Text = string.format(
		'<font color="%s">✓ %s</font>  %s',
		UI.ColorHex(UI.UpColor()),
		T("term.readWell"),
		T("term.readWell.sub", ticker)
	)
	local root: Frame = r.Root
	root.Visible = true
	root.Position = UDim2.new(0.5, 0, 1, -130)
	r.Scale.Scale = 0.9
	TweenService:Create(root, SOFT_IN, { Position = UDim2.new(0.5, 0, 1, -150) }):Play()
	TweenService:Create(r.Scale, SOFT_IN, { Scale = 1 }):Play()
	call("Sfx", "Play", "Notify")
	task.delay(READWELL_STAY, function()
		if readToken ~= token then
			return
		end
		local out = TweenService:Create(root, OUT_INFO, { Position = UDim2.new(0.5, 0, 1, -170) })
		out.Completed:Once(function()
			if readToken == token then
				root.Visible = false
			end
		end)
		out:Play()
	end)
end

-- ---------------------------------------------------------------------
-- G/V-TICK NACH EINEM VERKAUF (ruhig, §0.3 Punkt 6)
-- ---------------------------------------------------------------------
function EffectsMarket.TradeTick(pnl: number, anchor: GuiObject?)
	if type(pnl) ~= "number" or pnl ~= pnl then
		return
	end
	local profit = pnl > 0
	call("Sfx", "Play", if profit then "Profit" else "Loss")
	if not profit then
		local now = os.clock()
		if now - lastLossTip >= LOSS_TIP_GAP then
			lastLossTip = now
			ctx.Toast(T("trade.lossTip"), "Info")
		end
	end
	if hidden() then
		return
	end
	local gui: ScreenGui = ctx.Gui
	local scale = UI.ScaleOf(gui)
	local origin = gui.AbsolutePosition
	local start: Vector2
	if typeof(anchor) == "Instance" and anchor:IsA("GuiObject") and anchor.Parent then
		local pos = anchor.AbsolutePosition + anchor.AbsoluteSize * Vector2.new(0.5, 0)
		start = (pos - origin) / scale
	else
		start = (gui.AbsoluteSize * Vector2.new(0.5, 0.62)) / scale
	end
	local color = if profit then UI.UpColor() else Theme.Muted
	local text = (if profit then "+" else "") .. aky(math.floor(pnl + 0.5), true)
	local tickLabel = label({
		Name = "PnlTick",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(start.X, start.Y),
		Size = UDim2.fromOffset(240, 28),
		FontFace = UI.Faces.MonoBold,
		TextSize = 22,
		TextColor3 = color,
		Text = text,
		ZIndex = 48,
		Parent = gui,
	})
	UI.Create("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Transparency = 0.6, Parent = tickLabel })
	local rise = if reduced() then 12 else 46
	TweenService:Create(
		tickLabel,
		TweenInfo.new(TICK_STAY, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(start.X, start.Y - rise), TextTransparency = 1 }
	):Play()
	task.delay(TICK_STAY + 0.1, function()
		tickLabel:Destroy()
	end)
end

-- ---------------------------------------------------------------------
-- START
-- ---------------------------------------------------------------------
function EffectsMarket.Init(context: any)
	ctx = context
	local Effects = ctx.Modules.Effects
	if Effects then
		Effects.Register("Bell", playBell)
		Effects.Register("ReadWell", playReadWell)
		Effects.Register("DayRecap", playRecap)
	end
	local hooks = ctx.Hooks
	-- Glocke kommt als Markt-Nachricht an alle (kein Server-Effekt) -> lokal abspielen + Hook wie bei Server-Effekten
	hooks.On("Market:Bell", function(data)
		local before = lastBellDay
		if Effects then
			Effects.Play("Bell", 1, data)
		else
			playBell(1, data)
		end
		if lastBellDay ~= before then
			hooks.Fire("Effect:Bell", 1, data)
		end
	end)
	hooks.On("Market:DayClose", function(data)
		local before = lastRecapDay
		if Effects then
			Effects.Play("DayRecap", 1, data)
		else
			playRecap(1, data)
		end
		if lastRecapDay ~= before then
			hooks.Fire("Effect:DayRecap", 1, data)
		end
	end)
end

function EffectsMarket.Start() end

return EffectsMarket
