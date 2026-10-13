-- =====================================================================
--  AKYTEX TYCOON – Kerzen-Chart aus GUI-Frames, 60 FPS (Client/Modules/ChartView)
--  Besitzer: WP5 (Charts, Terminal, Markt-UI). Bibliothek (Main.client ruft nur Init, kein Start/Frame).
--  Vertrag: DESIGN.md §C7.5 (WP5), §B7.5 Renderer-Vertrag; MARKET.md §9.4, §10.4; REUSE.md §5.4.
--
--  Renderer-Vertrag (§B7.5), so umgesetzt:
--    * ein ungedrehter Wurzel-Frame mit ClipsDescendants; Preisfläche ≈ 72 %, Volumen ≈ 14 %, Indikator-Bereich
--      optional, rechte Achse 56 px, Zeitachse 18 px; KEIN CanvasGroup, kein TextScaled auf Achsen (BuilderMono, feste Größe)
--    * Pool beim new(): je Kerzen-Slot Körper + Docht + Volumen (+ Flächen-Streifen nur bei AreaFill) für N + 1 Slots
--      (N = 60 Handy / 90 / 120 PC je Grafikstufe), Achsen-Labels, Gitter, Alarm-Linien, Fadenkreuz – nie Instance.new
--      beim Ticken; ≤ 900 GuiObjects je Chart (Stats().Objects)
--    * Scale-Koordinaten x = (i − 0,5)/N, y = 1 − (p − lo)/(hi − lo); geschrieben wird nur bei Änderung (Cache je Slot)
--    * je Frame bewegt sich nur die Live-Kerze (alpha = 1 − e^(−12·dt)); der y-Bereich gleitet mit 1 − e^(−6·dt) –
--      als O(1)-Transformation eines Zwischen-Frames (Höhe/Lage), die Kerzen selbst bleiben stehen. Neu ausgelegt
--      (O(N)) wird höchstens 1×/s, wenn der Zielbereich die Referenz verlässt oder um > 5 % schrumpft (MARKET §10.4)
--    * neue Kerze = ältesten Slot recyceln + die Streifen-Container per Tween 0,25 s Quint Out um eine Slot-Breite
--      schieben (O(1))
--    * Linien (Kurs-Linie, SMA/EMA/Bollinger/VWAP, RSI/MACD/Stochastik/ATR) per Path2D (Laufzeit-Prüfung in Init,
--      in Studio verifizieren); sonst gedrehte Segment-Frames in Pixeln ÷ akkumulierte UIScale, auf das Plot-Rechteck
--      geklemmt (dann gleitet der y-Bereich nicht, sondern springt höchstens 1×/s – Segmente würden sonst verzerren)
--    * Fadenkreuz + OHLC-Pille: Maus (InputChanged), Touch (halten + ziehen), Steuerkreuz (MoveCrosshair)
--
--  Öffentliche API (§C7.5):
--    ChartView.new(parent, opts): View
--      opts { Candles: number, Volume: boolean, Pane: string?, Style: string, Labels: boolean,
--             AreaFill: boolean?, Smooth: boolean?, MaxLines: number?, ZIndex: number?,
--             OnPick: ((price) -> ())?, OnSwipe: ((dir) -> ())?, OnCrosshair: ((candle?) -> ())? }
--      Style "Candles" | "Hollow" | "Line" | "Area" | "HeikinAshi"; Pane "RSI" | "MACD" | "Stoch" | "ATR"
--    View:SetData(candles, tf)   View:PushQuote(close, tick, high?, low?, vol?)   View:SetIndicators(map)
--    View:SetStyle(s)   View:Step(dt)   View:Destroy()
--  Zusätzlich: View:SetAlerts({ {Px, Dir} })  View:SetMarks({ {Px, Color, Text} })  View:SetPlaceholder(text?)
--    View:SetPickMode(on)  View:MoveCrosshair(delta)  View:HideCrosshair()  View:Repaint()  View:SetVisible(on)
--    View:Stats(): { Objects, Path2D, Candles }   View:PriceRange(): (lo, hi)   View:Count(): number
--    ChartView.Init(ctx), ChartView.HasPath2D(): boolean, ChartView.Colors (Indikator-Farben aus js/chart.js)
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent:WaitForChild("UI"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Indicators = require(Shared:WaitForChild("Market"):WaitForChild("Indicators"))

-- selene: allow(undefined_variable)
local Path2DPoint = Path2DControlPoint

type Candle = Types.Candle

local ChartView = {}
ChartView.__index = ChartView

local Theme = UI.Theme
local WHITE = Color3.new(1, 1, 1)

-- Indikator-Farben exakt wie js/chart.js der Website (§B7.5)
ChartView.Colors = {
	SMA20 = Color3.fromHex("#f5b942"),
	SMA50 = Color3.fromHex("#4f8cff"),
	SMA200 = Color3.fromHex("#e056fd"),
	EMA9 = Color3.fromHex("#00d1b2"),
	EMA21 = Color3.fromHex("#ff7a45"),
	BB = Color3.fromHex("#7c8cff"),
	VWAP = Color3.fromHex("#ffd166"),
	RSI = Color3.fromHex("#b388ff"),
	MACD = Color3.fromHex("#4f8cff"),
	MACDSignal = Color3.fromHex("#ff7a45"),
	StochK = Color3.fromHex("#00d1b2"),
	StochD = Color3.fromHex("#ff7a45"),
	ATR = Color3.fromHex("#b388ff"),
}

local MAX_OBJECTS = 900 -- GuiObjects je Chart (Renderer-Vertrag)
local AXIS_W = 56
local AXIS_H = 18
local PRICE_LABELS = 8
local TIME_LABELS = 6
local MAX_ALERTS = 18
local MAX_MARKS = 8
local LIVE_K = 12 -- Live-Kerze: alpha = 1 − e^(−12·dt)
local RANGE_K = 6 -- y-Bereich: 1 − e^(−6·dt)
local REBASE_GAP = 1 -- höchstens 1× je Sekunde neu auslegen
local SHRINK_REBASE = 0.05 -- Zielbereich > 5 % kleiner als angezeigt -> neu skalieren (MARKET §10.4)
local PAD = 0.08 -- Rand oben/unten im Preisbereich
local SCROLL_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local HOLD_FOR_CROSSHAIR = 0.25 -- Touch: so lange halten -> Fadenkreuz statt Wischen
local SWIPE_MIN = 70 -- px
local SWIPE_TIME = 0.4
local DATA_KEEP_EXTRA = 220 -- Kerzen über N hinaus für das Aufwärmen der Indikatoren (SMA200)
local INDICATOR_GAP = 1 -- Indikatoren höchstens 1× je Sekunde neu rechnen (Kurse kommen mit 1 Hz)
local PANES = { RSI = true, MACD = true, Stoch = true, ATR = true }
local PANE_ORDER = { "RSI", "MACD", "Stoch", "ATR" }
local OVERLAY_ORDER = { "SMA20", "SMA50", "SMA200", "EMA9", "EMA21", "BB", "VWAP" }

local ctx: any = nil
local path2dOk = false
local path2dMax = 0

-- ---------------------------------------------------------------------
-- TYPEN
-- ---------------------------------------------------------------------
type Slot = {
	Body: Frame,
	Wick: Frame,
	Stroke: UIStroke,
	Vol: Frame?,
	Fill: Frame?,
	A: number,
	Bx: number,
	By: number,
	Bh: number,
	Wx: number,
	Wy: number,
	Wh: number,
	Vx: number,
	Vh: number,
	Fx: number,
	Fy: number,
	Color: Color3?,
	Hollow: boolean?,
	Shown: boolean,
}

type Line = {
	Key: string,
	Color: Color3,
	Thickness: number,
	Transparency: number,
	Pane: boolean,
	Values: { number? },
	Paths: { any },
	Segs: { Frame },
	Parent: Frame,
	Live: Line?, -- 2-Punkte-Segment vorletzte -> letzte Kerze (je Kurs O(1) statt O(N))
}

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function langNow(): string
	if ctx and type(ctx.Lang_) == "function" then
		local ok, lang = pcall(ctx.Lang_)
		if ok and (lang == "de" or lang == "en") then
			return lang
		end
	end
	return "en"
end

local function formatPrice(cents: number): string
	local format = ctx and ctx.Format
	if format and type(format.Price) == "function" then
		local ok, text = pcall(format.Price, cents, langNow())
		if ok and type(text) == "string" then
			return text
		end
	end
	return string.format("%.2f", cents / 100)
end

local function formatCompact(n: number): string
	local format = ctx and ctx.Format
	if format and type(format.Compact) == "function" then
		local ok, text = pcall(format.Compact, n, langNow())
		if ok and type(text) == "string" then
			return text
		end
	end
	return tostring(math.floor(n))
end

local function niceStep(span: number, count: number): number
	if span <= 0 or not finite(span) then
		return 1
	end
	local raw = span / math.max(1, count)
	local mag = 10 ^ math.floor(math.log10(raw))
	local norm = raw / mag
	local step = if norm < 1.5 then 1 elseif norm < 3 then 2 elseif norm < 7 then 5 else 10
	return step * mag
end

local function copyCandle(c: any): Candle?
	if type(c) ~= "table" then
		return nil
	end
	local t, o, h, l, cl, v = c.T, c.O, c.H, c.L, c.C, c.V
	if not (finite(t) and finite(o) and finite(h) and finite(l) and finite(cl)) or cl <= 0 then
		return nil
	end
	return {
		T = t,
		O = o,
		H = math.max(h, o, cl),
		L = math.min(l, o, cl),
		C = cl,
		V = if finite(v) then math.max(0, v) else 0,
	}
end

local function timeLabel(t: number, tfTicks: number): string
	local clock = ctx and ctx.Clock
	local epoch = if clock and type(clock.EPOCH) == "number" then clock.EPOCH else 1767571200
	if tfTicks >= 1200 and tfTicks < 8400 then
		local day = t // 1200
		if ctx then
			return ctx.T("term.axis.day", day % 504 + 1)
		end
		return "#" .. tostring(day % 504 + 1)
	end
	local unix = t + epoch
	local pattern: any = if tfTicks < 60 then "%H:%M:%S" else "%H:%M"
	local ok, text = pcall(os.date, pattern, unix)
	if ok and type(text) == "string" then
		return text
	end
	return tostring(t)
end

local function newFrame(props: { [string]: any }): Frame
	local base: { [string]: any } = { BackgroundTransparency = 1, BorderSizePixel = 0 }
	for k, v in pairs(props) do
		base[k] = v
	end
	return UI.Create("Frame", base)
end

local function newLabel(props: { [string]: any }): TextLabel
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		FontFace = UI.Faces.Mono,
		TextSize = 11,
		TextColor3 = Theme.Muted,
		Text = "",
		TextScaled = false,
	}
	for k, v in pairs(props) do
		base[k] = v
	end
	return UI.Create("TextLabel", base)
end

-- ---------------------------------------------------------------------
-- AUFBAU
-- ---------------------------------------------------------------------
function ChartView.new(parent: Instance, opts: { [string]: any }?): any
	local o = opts or {}
	local self = setmetatable({}, ChartView) :: any
	local n = math.clamp(math.floor(tonumber(o.Candles) or 60), 10, 120)
	self.N = n
	self.Labels = o.Labels ~= false
	self.VolumeOn = o.Volume ~= false
	self.AreaAlloc = o.AreaFill == true
	self.Smooth = o.Smooth ~= false
	self.MaxLines = math.clamp(math.floor(tonumber(o.MaxLines) or 6), 0, 8)
	self.Style = if type(o.Style) == "string" then o.Style else "Candles"
	self.OnPick = o.OnPick
	self.OnSwipe = o.OnSwipe
	self.OnCrosshair = o.OnCrosshair
	self.Z = math.floor(tonumber(o.ZIndex) or 1)
	self.Objects = 0
	self.Alive = true
	self.Visible = true
	self.Conns = {} :: { RBXScriptConnection }
	self.Tweens = {} :: { Tween }
	self.Data = {} :: { Candle }
	self.Source = {} :: { Candle }
	self.Seq0 = 0
	self.Base = 0
	self.TfTicks = 60
	self.LastTick = 0
	self.Lines = {} :: { Line }
	self.IndMap = {} :: { [string]: boolean }
	self.PaneKind = if type(o.Pane) == "string" and PANES[o.Pane] then o.Pane else nil
	self.IndDirty = false
	self.IndAt = 0
	self.RefLo, self.RefHi = 0, 1
	self.Lo, self.Hi = 0, 1
	self.TLo, self.THi = 0, 1
	self.RebaseAt = -math.huge
	self.NeedRebase = true
	self.VolRef = 1
	self.PaneLo, self.PaneHi = 0, 100
	self.Live = { O = 0, H = 0, L = 0, C = 0 }
	self.Shown = { O = 0, H = 0, L = 0, C = 0 }
	self.Alerts = {} :: { { Px: number, Dir: string } }
	self.Marks = {} :: { { Px: number, Color: Color3, Text: string } }
	self.Cross = nil :: number?
	self.CrossY = nil :: number?
	self.PickMode = false
	self.Scale = 1
	self.ScaleAt = -math.huge
	self.YScale = 1
	self.YPos = 0
	self.VMaxTarget = 1

	local z = self.Z
	local root = newFrame({
		Name = "ChartView",
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		ZIndex = z,
		Parent = parent,
	})
	self.Root = root
	local axisW = if self.Labels then AXIS_W else 0
	local axisH = if self.Labels then AXIS_H else 0
	self.AxisW, self.AxisH = axisW, axisH

	local plot = newFrame({
		Name = "Plot",
		Size = UDim2.new(1, -axisW, 1, -axisH),
		ZIndex = z,
		Parent = root,
	})
	self.Plot = plot
	-- Preisfläche (Clip) -> YFrame (Transformation des y-Bereichs) -> XStrip (Laufband)
	local pricePlot = newFrame({ Name = "Price", ClipsDescendants = true, ZIndex = z, Parent = plot })
	self.PricePlot = pricePlot
	local gridStrip = newFrame({ Name = "GridX", Size = UDim2.fromScale(1, 1), ZIndex = z, Parent = pricePlot })
	self.GridStrip = gridStrip
	local yFrame = newFrame({ Name = "Y", Size = UDim2.fromScale(1, 1), ZIndex = z, Parent = pricePlot })
	self.YFrame = yFrame
	local xStrip = newFrame({ Name = "X", Size = UDim2.fromScale(1, 1), ZIndex = z + 1, Parent = yFrame })
	self.XStrip = xStrip
	-- Volumen
	local volPlot = newFrame({ Name = "Volume", ClipsDescendants = true, ZIndex = z, Parent = plot })
	self.VolPlot = volPlot
	local volStrip = newFrame({ Name = "X", Size = UDim2.fromScale(1, 1), ZIndex = z, Parent = volPlot })
	self.VolStrip = volStrip
	-- Indikator-Bereich (RSI/MACD/…)
	local panePlot = newFrame({ Name = "Pane", ClipsDescendants = true, Visible = false, ZIndex = z, Parent = plot })
	self.PanePlot = panePlot
	local paneStrip = newFrame({ Name = "X", Size = UDim2.fromScale(1, 1), ZIndex = z + 1, Parent = panePlot })
	self.PaneStrip = paneStrip
	self.Objects += 9

	-- Slots (N + 1: einer gleitet beim Schieben links hinaus)
	self.Slots = {} :: { Slot }
	local bodyW = 0.7 / n
	for k = 1, n + 1 do
		local fill: Frame? = nil
		if self.AreaAlloc then
			local f = newFrame({
				Name = "Fill",
				AnchorPoint = Vector2.new(0.5, 0),
				Size = UDim2.new(1 / n, 1, 3, 0),
				BackgroundColor3 = Theme.Accent,
				BackgroundTransparency = 0.55,
				Visible = false,
				ZIndex = z,
				Parent = xStrip,
			})
			UI.Create("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.35),
					NumberSequenceKeypoint.new(0.3, 0.92),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Parent = f,
			})
			fill = f
			self.Objects += 1
		end
		local wick = newFrame({
			Name = "Wick",
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.new(0, 1, 0, 0),
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.Up,
			Visible = false,
			ZIndex = z + 1,
			Parent = xStrip,
		})
		local body = newFrame({
			Name = "Body",
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.new(bodyW, 0, 0, 1),
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.Up,
			Visible = false,
			ZIndex = z + 2,
			Parent = xStrip,
		})
		local stroke = UI.Create("UIStroke", {
			Thickness = 1,
			Color = Theme.Up,
			Enabled = false,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Parent = body,
		})
		local vol: Frame? = nil
		if self.VolumeOn then
			vol = newFrame({
				Name = "Vol",
				AnchorPoint = Vector2.new(0.5, 1),
				Size = UDim2.new(bodyW, 0, 0, 0),
				BackgroundTransparency = 0.35,
				BackgroundColor3 = Theme.Up,
				Visible = false,
				ZIndex = z,
				Parent = volStrip,
			})
			self.Objects += 1
		end
		self.Objects += 2
		local slot: Slot = {
			Body = body,
			Wick = wick,
			Stroke = stroke,
			Vol = vol,
			Fill = fill,
			A = -1,
			Bx = -1,
			By = -1,
			Bh = -1,
			Wx = -1,
			Wy = -1,
			Wh = -1,
			Vx = -1,
			Vh = -1,
			Fx = -1,
			Fy = -1,
			Color = nil,
			Hollow = nil,
			Shown = false,
		}
		self.Slots[k] = slot
	end

	-- Gitter + Achsen
	self.GridY = {} :: { Frame }
	self.PriceLabels = {} :: { TextLabel }
	self.GridX = {} :: { Frame }
	self.TimeLabels = {} :: { { Label: TextLabel, A: number } }
	if self.Labels then
		for _ = 1, PRICE_LABELS do
			table.insert(
				self.GridY,
				newFrame({
					Name = "GridY",
					AnchorPoint = Vector2.new(0, 0.5),
					Size = UDim2.new(1, 0, 0, 1),
					BackgroundTransparency = 0.45,
					BackgroundColor3 = Theme.Border,
					Visible = false,
					ZIndex = z,
					Parent = yFrame,
				})
			)
		end
		for _ = 1, TIME_LABELS do
			table.insert(
				self.GridX,
				newFrame({
					Name = "GridX",
					AnchorPoint = Vector2.new(0.5, 0),
					Size = UDim2.new(0, 1, 1, 0),
					BackgroundTransparency = 0.55,
					BackgroundColor3 = Theme.Border,
					Visible = false,
					ZIndex = z,
					Parent = gridStrip,
				})
			)
		end
		self.Objects += PRICE_LABELS + TIME_LABELS
		local axisY = newFrame({
			Name = "AxisY",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			ClipsDescendants = true,
			ZIndex = z,
			Parent = root,
		})
		self.AxisY = axisY
		local axisYFrame = newFrame({ Name = "Y", Size = UDim2.fromScale(1, 1), ZIndex = z, Parent = axisY })
		self.AxisYFrame = axisYFrame
		for _ = 1, PRICE_LABELS do
			table.insert(
				self.PriceLabels,
				newLabel({
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.fromOffset(6, 0),
					Size = UDim2.new(1, -8, 0, 14),
					TextXAlignment = Enum.TextXAlignment.Left,
					Visible = false,
					ZIndex = z + 1,
					Parent = axisYFrame,
				})
			)
		end
		local axisX = newFrame({
			Name = "AxisX",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, -axisW, 0, axisH),
			ClipsDescendants = true,
			ZIndex = z,
			Parent = root,
		})
		local axisXStrip = newFrame({ Name = "X", Size = UDim2.fromScale(1, 1), ZIndex = z, Parent = axisX })
		self.AxisXStrip = axisXStrip
		for _ = 1, TIME_LABELS do
			table.insert(self.TimeLabels, {
				Label = newLabel({
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromOffset(64, 14),
					Position = UDim2.fromScale(0, 0.5),
					Visible = false,
					ZIndex = z + 1,
					Parent = axisXStrip,
				}),
				A = -1,
			})
		end
		self.Objects += 4 + PRICE_LABELS + TIME_LABELS
		-- Letzter Kurs: Linie + Pille an der Achse
		self.LastLine = newFrame({
			Name = "LastLine",
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundTransparency = 0.45,
			BackgroundColor3 = Theme.Up,
			Visible = false,
			ZIndex = z + 3,
			Parent = yFrame,
		})
		local pill = newLabel({
			Name = "LastPill",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(2, 0),
			Size = UDim2.new(1, -2, 0, 16),
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.Up,
			TextColor3 = WHITE,
			FontFace = UI.Faces.MonoBold,
			Visible = false,
			ZIndex = z + 4,
			Parent = axisYFrame,
		})
		UI.Create("UICorner", { CornerRadius = UDim.new(0, 4), Parent = pill })
		self.LastPill = pill
		-- Fadenkreuz
		self.CrossV = newFrame({
			Name = "CrossV",
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.new(0, 1, 1, 0),
			BackgroundTransparency = 0.35,
			BackgroundColor3 = Theme.Text2,
			Visible = false,
			ZIndex = z + 6,
			Parent = plot,
		})
		self.CrossH = newFrame({
			Name = "CrossH",
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundTransparency = 0.35,
			BackgroundColor3 = Theme.Text2,
			Visible = false,
			ZIndex = z + 6,
			Parent = plot,
		})
		local ohlc = newLabel({
			Name = "Ohlc",
			Position = UDim2.fromOffset(6, 4),
			Size = UDim2.new(1, -12, 0, 16),
			BackgroundTransparency = 0.15,
			BackgroundColor3 = Theme.Bg2,
			TextColor3 = Theme.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			RichText = true,
			Visible = false,
			ZIndex = z + 7,
			Parent = plot,
		})
		UI.Create("UIPadding", { PaddingLeft = UDim.new(0, 6), Parent = ohlc })
		UI.Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = ohlc })
		self.Ohlc = ohlc
		local crossPill = newLabel({
			Name = "CrossPill",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(2, 0),
			Size = UDim2.new(1, -2, 0, 16),
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.Surface2,
			TextColor3 = Theme.Text,
			Visible = false,
			ZIndex = z + 8,
			Parent = axisY,
		})
		UI.Create("UICorner", { CornerRadius = UDim.new(0, 4), Parent = crossPill })
		self.CrossPill = crossPill
		self.Objects += 7
	end

	-- Alarm-Linien (Know-how-Basis 3, max. 18) und Markierungen (Einstand, Order-Preise) – gepoolt
	self.AlertPool = {} :: { { Line: Frame, Tag: TextLabel } }
	self.MarkPool = {} :: { { Line: Frame, Tag: TextLabel } }
	local function makeMarker(pool: { any }, count: number, color: Color3)
		for _ = 1, count do
			local line = newFrame({
				Name = "Marker",
				AnchorPoint = Vector2.new(0, 0.5),
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundTransparency = 0.2,
				BackgroundColor3 = color,
				Visible = false,
				ZIndex = z + 3,
				Parent = yFrame,
			})
			local tag = newLabel({
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -4, 0, -1),
				Size = UDim2.fromOffset(120, 12),
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = color,
				TextSize = 10,
				Visible = self.Labels,
				ZIndex = z + 3,
				Parent = line,
			})
			table.insert(pool, { Line = line, Tag = tag })
			self.Objects += 2
		end
	end
	if self.Labels then
		-- Welt-Monitore (ohne Beschriftung) brauchen keine Alarm-/Order-Linien -> Objekt-Budget sparen
		makeMarker(self.AlertPool, MAX_ALERTS, Theme.Warn)
		makeMarker(self.MarkPool, MAX_MARKS, Theme.Accent)
	end

	-- Platzhalter ("Historie lädt …")
	self.Placeholder = UI.Create("TextLabel", {
		Name = "Placeholder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.new(1, -20, 0, 20),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.Body,
		TextSize = 14,
		TextColor3 = Theme.Muted,
		Text = "",
		Visible = false,
		ZIndex = z + 9,
		Parent = root,
	})
	self.Objects += 1

	-- Linien: Kurs-Linie (statischer Teil + Live-Segment)
	self.PriceLine = self:_newLine("Price", Theme.Accent, 2, 0, false)
	self.LiveSeg = self:_newLine("Live", Theme.Accent, 2, 0, false)

	self:_layout()
	self:_bindInput()
	table.insert(
		self.Conns,
		plot:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if not path2dOk then
				self.NeedRebase = true -- Segmente sind in Pixeln
			end
		end)
	)
	return self
end

-- Fraktionen der Bereiche (Preis/Volumen/Indikator) setzen
function ChartView._layout(self: any)
	local pane = self.PaneKind ~= nil
	local priceF, volTop, volF, paneTop, paneF
	if pane and self.VolumeOn then
		priceF, volTop, volF, paneTop, paneF = 0.58, 0.61, 0.12, 0.76, 0.24
	elseif pane then
		priceF, volTop, volF, paneTop, paneF = 0.72, 1, 0, 0.76, 0.24
	elseif self.VolumeOn then
		priceF, volTop, volF, paneTop, paneF = 0.80, 0.84, 0.16, 1, 0
	else
		priceF, volTop, volF, paneTop, paneF = 0.97, 1, 0, 1, 0
	end
	self.PriceF = priceF
	self.PricePlot.Size = UDim2.fromScale(1, priceF)
	self.VolPlot.Position = UDim2.fromScale(0, volTop)
	self.VolPlot.Size = UDim2.fromScale(1, volF)
	self.VolPlot.Visible = self.VolumeOn
	self.PanePlot.Position = UDim2.fromScale(0, paneTop)
	self.PanePlot.Size = UDim2.fromScale(1, paneF)
	self.PanePlot.Visible = pane
	if self.AxisY then
		-- Achsen-Spalte = Höhe der Preisfläche (Wurzel minus Zeitachse)
		self.AxisY.Size = UDim2.new(0, self.AxisW, priceF, -priceF * self.AxisH)
	end
end

-- ---------------------------------------------------------------------
-- LINIEN (Path2D oder Segment-Rückfall)
-- ---------------------------------------------------------------------
function ChartView._newLine(
	self: any,
	key: string,
	color: Color3,
	thickness: number,
	transparency: number,
	pane: boolean
)
	local line: Line = {
		Key = key,
		Color = color,
		Thickness = thickness,
		Transparency = transparency,
		Pane = pane,
		Values = {},
		Paths = {},
		Segs = {},
		Parent = if pane then self.PaneStrip else self.XStrip,
		Live = nil,
	}
	return line
end

function ChartView._releaseLine(self: any, line: Line)
	local live = line.Live
	if live then
		self:_releaseLine(live)
		line.Live = nil
	end
	for _, path in ipairs(line.Paths) do
		path:Destroy()
		self.Objects -= 1
	end
	table.clear(line.Paths)
	for _, seg in ipairs(line.Segs) do
		seg:Destroy()
		self.Objects -= 1
	end
	table.clear(line.Segs)
end

-- Pfad-Punkte setzen; points = { {x, y} } in Strip-Scale
function ChartView._drawPath(self: any, line: Line, points: { { number } })
	local count = #points
	if path2dOk then
		local chunk = math.max(2, path2dMax)
		local needed = if count >= 2 then math.ceil((count - 1) / (chunk - 1)) else 0
		while #line.Paths < needed do
			local okPath, path = pcall(Instance.new, "Path2D")
			if not okPath then
				break
			end
			path.Thickness = line.Thickness
			path.Color3 = line.Color
			path.Transparency = line.Transparency
			path.ZIndex = self.Z + 2
			path.Parent = line.Parent
			table.insert(line.Paths, path)
			self.Objects += 1
		end
		for index, path in ipairs(line.Paths) do
			if index <= needed then
				local from = (index - 1) * (chunk - 1) + 1
				local to = math.min(count, from + chunk - 1)
				local cps = table.create(to - from + 1)
				for k = from, to do
					local p = points[k]
					table.insert(cps, Path2DPoint.new(UDim2.fromScale(p[1], p[2])))
				end
				pcall(path.SetControlPoints, path, cps)
				if not path.Visible then
					path.Visible = true
				end
				if path.Color3 ~= line.Color then
					path.Color3 = line.Color
				end
			elseif path.Visible then
				path.Visible = false
			end
		end
		return
	end
	-- Rückfall: gedrehte Segment-Frames in Pixeln, Budget beachten
	local strip: Frame = line.Parent
	local size = strip.AbsoluteSize
	local scale = self:_scale()
	local w, h = size.X / scale, size.Y / scale
	-- sichtbares Rechteck in Strip-Koordinaten (gedrehte Frames werden nicht geclippt -> selbst klemmen)
	local sy = if line.Pane then 1 else math.max(self.YScale or 1, 1e-6)
	local py = if line.Pane then 0 else (self.YPos or 0)
	local yMin, yMax = -py / sy, (1 - py) / sy
	local sx = strip.Position.X.Scale
	local xMin, xMax = -sx, 1 - sx
	local need = math.max(0, count - 1)
	local budget = MAX_OBJECTS - self.Objects + #line.Segs
	local step = 1
	if need > budget and budget > 0 then
		step = math.ceil(need / budget)
	elseif budget <= 0 then
		need = 0
	end
	local used = 0
	local k = 1
	while k < count and used < budget do
		local nextK = math.min(count, k + step)
		local p1, p2 = points[k], points[nextK]
		if p2[1] < xMin or p1[1] > xMax then
			k = nextK
			continue
		end
		used += 1
		local seg = line.Segs[used]
		if not seg then
			seg = newFrame({
				Name = "Seg",
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = line.Transparency,
				BackgroundColor3 = line.Color,
				ZIndex = self.Z + 2,
				Parent = strip,
			})
			table.insert(line.Segs, seg)
			self.Objects += 1
		end
		-- im Plot-Rechteck klemmen (Drehung hebelt ClipsDescendants aus)
		local x1, x2 = math.clamp(p1[1], xMin, xMax), math.clamp(p2[1], xMin, xMax)
		local y1 = math.clamp(p1[2], yMin, yMax)
		local y2 = math.clamp(p2[2], yMin, yMax)
		local dx, dy = (x2 - x1) * w, (y2 - y1) * h
		local length = math.sqrt(dx * dx + dy * dy)
		seg.Position = UDim2.fromScale((x1 + x2) / 2, (y1 + y2) / 2)
		seg.Size = UDim2.fromOffset(length + 1, line.Thickness)
		seg.Rotation = math.deg(math.atan2(dy, dx))
		seg.BackgroundColor3 = line.Color
		seg.Visible = true
		k = nextK
	end
	for index = used + 1, #line.Segs do
		local seg = line.Segs[index]
		if seg.Visible then
			seg.Visible = false
		end
	end
end

function ChartView._hideLine(self: any, line: Line)
	local live = line.Live
	if live then
		self:_hideLine(live)
	end
	for _, path in ipairs(line.Paths) do
		if path.Visible then
			path.Visible = false
		end
	end
	for _, seg in ipairs(line.Segs) do
		if seg.Visible then
			seg.Visible = false
		end
	end
end

function ChartView._scale(self: any): number
	local now = os.clock()
	if now - self.ScaleAt > 1 then
		self.ScaleAt = now
		self.Scale = UI.ScaleOf(self.Root)
	end
	return self.Scale
end

-- ---------------------------------------------------------------------
-- KOORDINATEN
-- ---------------------------------------------------------------------
function ChartView._x(self: any, a: number): number
	return (a - self.Base + 0.5) / self.N
end

function ChartView._y(self: any, p: number): number
	local range = self.RefHi - self.RefLo
	if range <= 0 then
		return 0.5
	end
	return (self.RefHi - p) / range
end

function ChartView._lastA(self: any): number
	return self.Seq0 + #self.Data - 1
end

function ChartView._stripX(self: any): number
	-- Live-Kerze (lastA) steht bei (N − 0,5)/N
	return -(self:_lastA() - self.Base - self.N + 1) / self.N
end

function ChartView._candleAt(self: any, a: number): Candle?
	return self.Source[a - self.Seq0 + 1]
end

-- ---------------------------------------------------------------------
-- BEREICH (Ziel, Referenz, Transformation)
-- ---------------------------------------------------------------------
function ChartView._targetRange(self: any)
	local source = self.Source
	local count = #source
	local lo, hi = math.huge, -math.huge
	local first = math.max(1, count - self.N + 1)
	for k = first, count do
		local c = source[k]
		if c.L < lo then
			lo = c.L
		end
		if c.H > hi then
			hi = c.H
		end
	end
	-- Overlay-Linien (Bollinger usw.) mit einbeziehen, damit sie nicht abgeschnitten werden
	for _, line in ipairs(self.Lines) do
		if not line.Pane then
			for k = first, count do
				local v = line.Values[k]
				if v then
					if v < lo then
						lo = v
					end
					if v > hi then
						hi = v
					end
				end
			end
		end
	end
	if lo == math.huge then
		lo, hi = 0, 1
	end
	local mid = (lo + hi) / 2
	local span = math.max(hi - lo, math.max(1, mid * 0.004))
	self.TLo = mid - span / 2 - span * PAD
	self.THi = mid + span / 2 + span * PAD
	-- Volumen-Referenz
	local vmax = 0
	for k = first, count do
		local v = source[k].V
		if v > vmax then
			vmax = v
		end
	end
	self.VMaxTarget = math.max(1, vmax)
end

function ChartView._applyTransform(self: any)
	local lo, hi = self.Lo, self.Hi
	local span = hi - lo
	if span <= 0 then
		return
	end
	local sy = (self.RefHi - self.RefLo) / span
	local py = (hi - self.RefHi) / span
	if self.YScale ~= sy or self.YPos ~= py then
		self.YScale, self.YPos = sy, py
		local size = UDim2.fromScale(1, sy)
		local pos = UDim2.fromScale(0, py)
		self.YFrame.Size = size
		self.YFrame.Position = pos
		if self.AxisYFrame then
			self.AxisYFrame.Size = size
			self.AxisYFrame.Position = pos
		end
	end
end

-- ---------------------------------------------------------------------
-- SLOTS
-- ---------------------------------------------------------------------
function ChartView._slotFor(self: any, a: number): Slot
	return self.Slots[(a % (self.N + 1)) + 1]
end

function ChartView._paintSlot(self: any, slot: Slot, a: number, o: number, h: number, l: number, c: number, v: number)
	local style = self.Style
	local candleStyle = style == "Candles" or style == "Hollow" or style == "HeikinAshi"
	local range = self.RefHi - self.RefLo
	if range <= 0 then
		return
	end
	local x = self:_x(a)
	local up = c >= o
	local color = if up then UI.UpColor() else UI.DownColor()
	if slot.A ~= a then
		slot.A = a
	end
	if candleStyle then
		local top = math.max(o, c)
		local by = (self.RefHi - top) / range
		local bh = math.abs(o - c) / range
		local wy = (self.RefHi - h) / range
		local wh = (h - l) / range
		if slot.Bx ~= x or slot.By ~= by or slot.Bh ~= bh then
			slot.Bx, slot.By, slot.Bh = x, by, bh
			slot.Body.Position = UDim2.fromScale(x, by)
			slot.Body.Size = UDim2.new(0.7 / self.N, 0, bh, 1)
		end
		if slot.Wx ~= x or slot.Wy ~= wy or slot.Wh ~= wh then
			slot.Wx, slot.Wy, slot.Wh = x, wy, wh
			slot.Wick.Position = UDim2.fromScale(x, wy)
			slot.Wick.Size = UDim2.new(0, 1, wh, 1)
		end
		local hollow = style == "Hollow" and up
		if slot.Color ~= color or slot.Hollow ~= hollow then
			slot.Color = color
			slot.Hollow = hollow
			slot.Body.BackgroundColor3 = color
			slot.Body.BackgroundTransparency = if hollow then 1 else 0
			slot.Stroke.Color = color
			slot.Stroke.Enabled = hollow
			slot.Wick.BackgroundColor3 = color
		end
		if not slot.Body.Visible then
			slot.Body.Visible = true
			slot.Wick.Visible = true
		end
	elseif slot.Body.Visible then
		slot.Body.Visible = false
		slot.Wick.Visible = false
	end
	local fill = slot.Fill
	if fill then
		local want = style == "Area"
		if want then
			local fy = (self.RefHi - c) / range
			if slot.Fx ~= x or slot.Fy ~= fy then
				slot.Fx, slot.Fy = x, fy
				fill.Position = UDim2.fromScale(x, fy)
			end
		end
		if fill.Visible ~= want then
			fill.Visible = want
		end
	end
	local vol = slot.Vol
	if vol then
		local vh = math.clamp(v / math.max(1, self.VolRef), 0, 1)
		if slot.Vx ~= x or slot.Vh ~= vh then
			slot.Vx, slot.Vh = x, vh
			vol.Position = UDim2.fromScale(x, 1)
			vol.Size = UDim2.new(0.7 / self.N, 0, vh, 0)
		end
		if vol.BackgroundColor3 ~= color then
			vol.BackgroundColor3 = color
		end
		if not vol.Visible then
			vol.Visible = true
		end
	end
	slot.Shown = true
end

function ChartView._hideSlot(_self: any, slot: Slot)
	if not slot.Shown then
		return
	end
	slot.Shown = false
	slot.A = -1
	slot.Body.Visible = false
	slot.Wick.Visible = false
	if slot.Vol then
		slot.Vol.Visible = false
	end
	if slot.Fill then
		slot.Fill.Visible = false
	end
end

-- ---------------------------------------------------------------------
-- NEU AUSLEGEN (O(N), höchstens 1×/s)
-- ---------------------------------------------------------------------
function ChartView._rebase(self: any)
	self.RebaseAt = os.clock()
	self.NeedRebase = false
	self:_targetRange()
	local span = self.THi - self.TLo
	self.RefLo = self.TLo - span * 0.5
	self.RefHi = self.THi + span * 0.5
	if not self.Smooth or not path2dOk or self.Lo >= self.Hi then
		self.Lo, self.Hi = self.TLo, self.THi
	end
	self.VolRef = self.VMaxTarget or 1
	self.Base = self:_lastA() - self.N
	-- laufende Schiebe-Tweens zielen auf die alte Basis -> abbrechen, Lage direkt setzen
	for _, tween in ipairs(self.Tweens) do
		tween:Cancel()
	end
	table.clear(self.Tweens)
	self.XStrip.Position = UDim2.fromScale(self:_stripX(), 0)
	self.GridStrip.Position = self.XStrip.Position
	self.VolStrip.Position = self.XStrip.Position
	self.PaneStrip.Position = self.XStrip.Position
	if self.AxisXStrip then
		self.AxisXStrip.Position = self.XStrip.Position
	end
	self:_applyTransform()
	self:_relayoutAll()
end

function ChartView._relayoutAll(self: any)
	local lastA = self:_lastA()
	local firstA = lastA - self.N + 1
	for _, slot in ipairs(self.Slots) do
		slot.A = -1
	end
	for a = firstA, lastA do
		local c = self:_candleAt(a)
		local slot = self:_slotFor(a)
		if c then
			if a == lastA and self.Smooth then
				local s = self.Shown
				self:_paintSlot(slot, a, s.O, s.H, s.L, s.C, c.V)
			else
				self:_paintSlot(slot, a, c.O, c.H, c.L, c.C, c.V)
			end
		end
	end
	for _, slot in ipairs(self.Slots) do
		if slot.A < firstA or slot.A > lastA or self:_candleAt(slot.A) == nil then
			self:_hideSlot(slot)
		end
	end
	self:_drawLines()
	self:_drawAxes()
	self:_drawMarkers()
	self:_drawLast()
end

function ChartView._drawAxes(self: any)
	if not self.Labels then
		return
	end
	local step = niceStep(self.THi - self.TLo, 4)
	local first = math.ceil(self.RefLo / step) * step
	local index = 0
	local level = first
	while level <= self.RefHi and index < PRICE_LABELS do
		index += 1
		local y = self:_y(level)
		local grid = self.GridY[index]
		grid.Position = UDim2.fromScale(0, y)
		grid.Visible = true
		local label = self.PriceLabels[index]
		label.Position = UDim2.new(0, 6, y, 0)
		label.Text = formatPrice(level)
		label.Visible = true
		level += step
	end
	for k = index + 1, PRICE_LABELS do
		self.GridY[k].Visible = false
		self.PriceLabels[k].Visible = false
	end
	-- Zeit-Labels: Kerzen mit a % step == 0
	local tstep = math.max(1, math.floor(self.N / 5 + 0.5))
	local lastA = self:_lastA()
	local firstA = lastA - self.N + 1
	local a = lastA - (lastA % tstep)
	local used = 0
	while a >= firstA and used < TIME_LABELS do
		local c = self:_candleAt(a)
		if c then
			used += 1
			local entry = self.TimeLabels[used]
			entry.A = a
			local x = self:_x(a)
			entry.Label.Position = UDim2.fromScale(x, 0.5)
			entry.Label.Text = timeLabel(c.T, self.TfTicks)
			entry.Label.Visible = true
			local grid = self.GridX[used]
			grid.Position = UDim2.fromScale(x, 0)
			grid.Visible = true
		end
		a -= tstep
	end
	for k = used + 1, TIME_LABELS do
		self.TimeLabels[k].A = -1
		self.TimeLabels[k].Label.Visible = false
		self.GridX[k].Visible = false
	end
end

-- neue Kerze: höchstens ein Zeit-Label neu vergeben (O(1))
function ChartView._advanceTimeLabel(self: any, a: number)
	if not self.Labels then
		return
	end
	local tstep = math.max(1, math.floor(self.N / 5 + 0.5))
	if a % tstep ~= 0 then
		return
	end
	local oldest, oldestA = nil, math.huge
	for index, entry in ipairs(self.TimeLabels) do
		if entry.A < oldestA then
			oldest, oldestA = index, entry.A
		end
	end
	if not oldest then
		return
	end
	local c = self:_candleAt(a)
	if not c then
		return
	end
	local entry = self.TimeLabels[oldest]
	entry.A = a
	local x = self:_x(a)
	entry.Label.Position = UDim2.fromScale(x, 0.5)
	entry.Label.Text = timeLabel(c.T, self.TfTicks)
	entry.Label.Visible = true
	local grid = self.GridX[oldest]
	grid.Position = UDim2.fromScale(x, 0)
	grid.Visible = true
end

function ChartView._drawMarkers(self: any)
	local range = self.RefHi - self.RefLo
	for index, entry in ipairs(self.AlertPool) do
		local alert = self.Alerts[index]
		if alert and range > 0 then
			entry.Line.Position = UDim2.fromScale(0, self:_y(alert.Px))
			entry.Tag.Text = (if alert.Dir == "Up" then "▲ " else "▼ ") .. formatPrice(alert.Px)
			entry.Line.Visible = true
		else
			entry.Line.Visible = false
		end
	end
	for index, entry in ipairs(self.MarkPool) do
		local mark = self.Marks[index]
		if mark and range > 0 then
			entry.Line.Position = UDim2.fromScale(0, self:_y(mark.Px))
			entry.Line.BackgroundColor3 = mark.Color
			entry.Tag.TextColor3 = mark.Color
			entry.Tag.Text = mark.Text
			entry.Line.Visible = true
		else
			entry.Line.Visible = false
		end
	end
end

function ChartView._drawLast(self: any)
	if not self.Labels or not self.LastLine then
		return
	end
	local count = #self.Source
	local last = self.Source[count]
	if not last then
		self.LastLine.Visible = false
		self.LastPill.Visible = false
		return
	end
	local shown = self.Shown
	local price = if self.Smooth then shown.C else last.C
	local prev = self.Source[count - 1]
	local ref = if prev then prev.C else last.O
	local color = UI.TrendColor(last.C - ref)
	if last.C == ref then
		color = Theme.Accent
	end
	local y = self:_y(price)
	self.LastLine.Position = UDim2.fromScale(0, y)
	if self.LastLine.BackgroundColor3 ~= color then
		self.LastLine.BackgroundColor3 = color
		self.LastPill.BackgroundColor3 = color
	end
	self.LastLine.Visible = true
	self.LastPill.Position = UDim2.new(0, 2, y, 0)
	local text = formatPrice(last.C)
	if self.LastPill.Text ~= text then
		self.LastPill.Text = text
	end
	self.LastPill.Visible = true
end

-- Linien neu zeichnen (O(N); bei neuer Kerze, Neu-Auslegen, Indikator-Wechsel)
function ChartView._drawLines(self: any)
	local lastA = self:_lastA()
	local firstA = lastA - self.N + 1
	local style = self.Style
	local lineStyle = style == "Line" or style == "Area"
	-- Kurs-Linie: statischer Teil bis zur vorletzten Kerze, Live-Segment separat
	if lineStyle and #self.Source >= 2 then
		local color = Theme.Accent
		self.PriceLine.Color = color
		self.LiveSeg.Color = color
		local points: { { number } } = {}
		for a = math.max(firstA, self.Seq0), lastA - 1 do
			local c = self:_candleAt(a)
			if c then
				table.insert(points, { self:_x(a), self:_y(c.C) })
			end
		end
		if #points >= 2 then
			self:_drawPath(self.PriceLine, points)
		else
			self:_hideLine(self.PriceLine)
		end
		self:_drawLiveSegment()
	else
		self:_hideLine(self.PriceLine)
		self:_hideLine(self.LiveSeg)
	end
	-- Indikatoren: statischer Teil bis zur vorletzten Kerze (ändert sich nur bei neuer Kerze), Live-Segment separat
	for _, line in ipairs(self.Lines) do
		local points: { { number } } = {}
		for a = math.max(firstA, self.Seq0), lastA - 1 do
			local v = line.Values[a - self.Seq0 + 1]
			if v and finite(v) then
				local y = if line.Pane then self:_paneY(v) else self:_y(v)
				table.insert(points, { self:_x(a), y })
			end
		end
		if #points >= 2 then
			self:_drawPath(line, points)
		else
			for _, path in ipairs(line.Paths) do
				path.Visible = false
			end
			for _, seg in ipairs(line.Segs) do
				seg.Visible = false
			end
		end
	end
	self:_drawLiveIndicators()
end

-- nur die Live-Segmente der Indikatoren (bei jedem neuen Kurs derselben Kerze)
function ChartView._drawLiveIndicators(self: any)
	local lastA = self:_lastA()
	local count = #self.Source
	for _, line in ipairs(self.Lines) do
		local live = line.Live
		if not live then
			live = self:_newLine(line.Key .. "Live", line.Color, line.Thickness, line.Transparency, line.Pane)
			line.Live = live
		end
		local liveLine = live :: Line
		local v1 = line.Values[count - 1]
		local v2 = line.Values[count]
		if v1 and v2 and finite(v1) and finite(v2) then
			local y1 = if line.Pane then self:_paneY(v1) else self:_y(v1)
			local y2 = if line.Pane then self:_paneY(v2) else self:_y(v2)
			self:_drawPath(liveLine, { { self:_x(lastA - 1), y1 }, { self:_x(lastA), y2 } })
		else
			self:_hideLine(liveLine)
		end
	end
end

function ChartView._drawLiveSegment(self: any)
	local count = #self.Source
	if count < 2 then
		self:_hideLine(self.LiveSeg)
		return
	end
	local lastA = self:_lastA()
	local prev = self.Source[count - 1]
	local price = if self.Smooth then self.Shown.C else self.Source[count].C
	self:_drawPath(self.LiveSeg, {
		{ self:_x(lastA - 1), self:_y(prev.C) },
		{ self:_x(lastA), self:_y(price) },
	})
end

function ChartView._paneY(self: any, v: number): number
	local span = self.PaneHi - self.PaneLo
	if span <= 0 then
		return 0.5
	end
	return math.clamp(0.06 + 0.88 * (self.PaneHi - v) / span, 0, 1)
end

-- ---------------------------------------------------------------------
-- INDIKATOREN
-- ---------------------------------------------------------------------
-- keepPane: Bereich des Indikator-Felds beibehalten (Live-Neuberechnung derselben Kerze – der statische Teil
-- wurde mit diesem Bereich gezeichnet, ein neuer Bereich käme erst mit der nächsten Kerze)
function ChartView._computeIndicators(self: any, keepPane: boolean?)
	self.IndDirty = false
	self.IndAt = os.clock()
	local source = self.Source
	local count = #source
	if count == 0 or #self.Lines == 0 then
		return
	end
	local closes = table.create(count)
	for k = 1, count do
		closes[k] = source[k].C
	end
	local bb: any = nil
	local macd: any = nil
	local stoch: any = nil
	for _, line in ipairs(self.Lines) do
		local key = line.Key
		local values: { number? } = {}
		if key == "SMA20" then
			values = Indicators.SMA(closes, 20)
		elseif key == "SMA50" then
			values = Indicators.SMA(closes, 50)
		elseif key == "SMA200" then
			values = Indicators.SMA(closes, 200)
		elseif key == "EMA9" then
			values = Indicators.EMA(closes, 9)
		elseif key == "EMA21" then
			values = Indicators.EMA(closes, 21)
		elseif key == "VWAP" then
			values = Indicators.VWAP(source)
		elseif key == "BBU" or key == "BBM" or key == "BBL" then
			bb = bb or Indicators.Bollinger(closes, 20, 2)
			values = if key == "BBU" then bb.Upper elseif key == "BBM" then bb.Mid else bb.Lower
		elseif key == "RSI" then
			values = Indicators.RSI(closes, 14)
		elseif key == "MACD" or key == "MACDSignal" then
			macd = macd or Indicators.MACD(closes, 12, 26, 9)
			values = if key == "MACD" then macd.Line else macd.Signal
		elseif key == "StochK" or key == "StochD" then
			stoch = stoch or Indicators.Stoch(source, 14, 3)
			values = if key == "StochK" then stoch.K else stoch.D
		elseif key == "ATR" then
			values = Indicators.ATR(source, 14)
		end
		line.Values = values
	end
	-- Bereich des Indikator-Felds
	local pane = self.PaneKind
	if keepPane and self.PaneHi > self.PaneLo then
		return
	end
	if pane == "RSI" or pane == "Stoch" then
		self.PaneLo, self.PaneHi = 0, 100
	elseif pane then
		local lo, hi = math.huge, -math.huge
		local first = math.max(1, count - self.N + 1)
		for _, line in ipairs(self.Lines) do
			if line.Pane then
				for k = first, count do
					local v = line.Values[k]
					if v then
						lo = math.min(lo, v)
						hi = math.max(hi, v)
					end
				end
			end
		end
		if lo == math.huge then
			lo, hi = 0, 1
		end
		if pane == "MACD" then
			local m = math.max(math.abs(lo), math.abs(hi), 1e-6)
			lo, hi = -m, m
		elseif hi - lo < 1e-6 then
			hi = lo + 1
		end
		self.PaneLo, self.PaneHi = lo, hi
	end
end

function ChartView._paneGuides(self: any)
	local guides = self.PaneGuides
	if not guides then
		guides = {}
		for _ = 1, 3 do
			table.insert(
				guides,
				newFrame({
					Name = "Guide",
					AnchorPoint = Vector2.new(0, 0.5),
					Size = UDim2.new(1, 0, 0, 1),
					BackgroundColor3 = Theme.Border,
					BackgroundTransparency = 0.2,
					Visible = false,
					ZIndex = self.Z,
					Parent = self.PanePlot,
				})
			)
			self.Objects += 1
		end
		self.PaneGuides = guides
	end
	local levels: { number } = {}
	if self.PaneKind == "RSI" then
		levels = { 30, 50, 70 }
	elseif self.PaneKind == "Stoch" then
		levels = { 20, 50, 80 }
	elseif self.PaneKind == "MACD" then
		levels = { 0 }
	end
	for index, guide in ipairs(guides) do
		local level = levels[index]
		if level then
			guide.Position = UDim2.fromScale(0, self:_paneY(level))
			guide.Visible = true
		else
			guide.Visible = false
		end
	end
end

-- ---------------------------------------------------------------------
-- EINGABE (Fadenkreuz, Wischen, Alarm setzen)
-- ---------------------------------------------------------------------
function ChartView._bindInput(self: any)
	if not self.Labels then
		return
	end
	local plot: Frame = self.Plot
	plot.Active = true
	local touchStart: InputObject? = nil
	local touchPos = Vector2.zero
	local touchAt = 0
	local touchCross = false
	table.insert(
		self.Conns,
		plot.InputBegan:Connect(function(input: InputObject)
			local kind = input.UserInputType
			if kind == Enum.UserInputType.MouseButton1 then
				if self.PickMode and self.OnPick then
					local price = self:PriceAtScreen(input.Position.Y)
					if price then
						task.spawn(self.OnPick, price)
					end
				end
			elseif kind == Enum.UserInputType.Touch then
				touchStart = input
				touchPos = Vector2.new(input.Position.X, input.Position.Y)
				touchAt = os.clock()
				touchCross = false
			end
		end)
	)
	table.insert(
		self.Conns,
		plot.InputChanged:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				self:_crossAt(input.Position.X, input.Position.Y)
			end
		end)
	)
	table.insert(
		self.Conns,
		plot.MouseLeave:Connect(function()
			self:HideCrosshair()
		end)
	)
	table.insert(
		self.Conns,
		UserInputService.InputChanged:Connect(function(input: InputObject)
			if input ~= touchStart then
				return
			end
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			if not touchCross and os.clock() - touchAt >= HOLD_FOR_CROSSHAIR then
				touchCross = true
			end
			if touchCross then
				self:_crossAt(pos.X, pos.Y)
			end
		end)
	)
	table.insert(
		self.Conns,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if input ~= touchStart then
				return
			end
			touchStart = nil
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			local delta = pos - touchPos
			local quick = os.clock() - touchAt <= SWIPE_TIME
			if touchCross then
				task.delay(1.5, function()
					if self.Alive and touchStart == nil then
						self:HideCrosshair()
					end
				end)
			elseif quick and math.abs(delta.X) >= SWIPE_MIN and math.abs(delta.Y) < math.abs(delta.X) * 0.6 then
				if self.OnSwipe then
					task.spawn(self.OnSwipe, if delta.X < 0 then 1 else -1)
				end
			elseif quick and delta.Magnitude < 12 and self.PickMode and self.OnPick then
				local price = self:PriceAtScreen(pos.Y)
				if price then
					task.spawn(self.OnPick, price)
				end
			end
		end)
	)
end

-- Preis an einer Bildschirm-Höhe (angezeigter Bereich)
function ChartView.PriceAtScreen(self: any, screenY: number): number?
	local plot: Frame = self.PricePlot
	local top = plot.AbsolutePosition.Y
	local height = plot.AbsoluteSize.Y
	if height <= 1 then
		return nil
	end
	local frac = (screenY - top) / height
	if frac < 0 or frac > 1 then
		return nil
	end
	return math.max(1, math.floor(self.Hi - frac * (self.Hi - self.Lo) + 0.5))
end

function ChartView._crossAt(self: any, screenX: number, screenY: number)
	if not self.Labels or #self.Source == 0 then
		return
	end
	local plot: Frame = self.Plot
	local size = plot.AbsoluteSize
	if size.X <= 1 then
		return
	end
	local rel = math.clamp((screenX - plot.AbsolutePosition.X) / size.X, 0, 0.9999)
	local slotIndex = math.floor(rel * self.N)
	local a = self:_lastA() - (self.N - 1 - slotIndex)
	if self:_candleAt(a) == nil then
		a = math.max(self.Seq0, a)
	end
	self.Cross = a
	self.CrossY = screenY
	self:_drawCross()
end

function ChartView._drawCross(self: any)
	local a = self.Cross
	if not a or not self.Labels then
		return
	end
	local c = self:_candleAt(a)
	if not c then
		self:HideCrosshair()
		return
	end
	local slotIndex = a - (self:_lastA() - self.N + 1)
	self.CrossV.Position = UDim2.fromScale((slotIndex + 0.5) / self.N, 0)
	self.CrossV.Visible = true
	local plot: Frame = self.Plot
	local y = self.CrossY
	local price: number? = nil
	if y then
		price = self:PriceAtScreen(y)
	end
	if not price then
		price = c.C
		y = nil
	end
	local pricePlot: Frame = self.PricePlot
	local frac = (self.Hi - (price :: number)) / math.max(1e-9, self.Hi - self.Lo)
	local yPlot = frac * pricePlot.AbsoluteSize.Y / math.max(1, plot.AbsoluteSize.Y)
	self.CrossH.Position = UDim2.fromScale(0, math.clamp(yPlot, 0, 1))
	self.CrossH.Visible = true
	self.CrossPill.Position = UDim2.new(0, 2, math.clamp(frac, 0, 1), 0)
	self.CrossPill.Text = formatPrice(price :: number)
	self.CrossPill.Visible = true
	local up = UI.ColorHex(UI.TrendColor(c.C - c.O))
	local text = string.format(
		'<font color="%s">%s</font>',
		up,
		if ctx
			then ctx.T(
				"term.ohlc",
				formatPrice(c.O),
				formatPrice(c.H),
				formatPrice(c.L),
				formatPrice(c.C),
				formatCompact(c.V * 10)
			)
			else formatPrice(c.C)
	)
	self.Ohlc.Text = text
	self.Ohlc.Visible = true
	if self.OnCrosshair then
		task.spawn(self.OnCrosshair, c)
	end
end

function ChartView.HideCrosshair(self: any)
	self.Cross = nil
	self.CrossY = nil
	if self.Labels and self.CrossV then
		self.CrossV.Visible = false
		self.CrossH.Visible = false
		self.CrossPill.Visible = false
		self.Ohlc.Visible = false
	end
	if self.OnCrosshair then
		task.spawn(self.OnCrosshair, nil)
	end
end

-- Steuerkreuz: Fadenkreuz kerzenweise bewegen
function ChartView.MoveCrosshair(self: any, delta: number)
	if #self.Source == 0 or not self.Labels then
		return
	end
	local lastA = self:_lastA()
	local a = self.Cross or lastA
	if self.Cross ~= nil then
		a += math.floor(delta)
	end
	a = math.clamp(a, math.max(self.Seq0, lastA - self.N + 1), lastA)
	self.Cross = a
	self.CrossY = nil
	self:_drawCross()
end

function ChartView.SetPickMode(self: any, on: boolean)
	self.PickMode = on == true
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICH
-- ---------------------------------------------------------------------
function ChartView.SetPlaceholder(self: any, text: string?)
	local label: TextLabel = self.Placeholder
	local show = type(text) == "string" and text ~= ""
	if show and label.Text ~= text then
		label.Text = text :: string
	end
	if label.Visible ~= show then
		label.Visible = show
	end
end

function ChartView._rebuildSource(self: any)
	if self.Style == "HeikinAshi" and #self.Data > 0 then
		local ok, ha = pcall(Indicators.HeikinAshi, self.Data)
		self.Source = if ok and type(ha) == "table" and #ha == #self.Data then ha else self.Data
	else
		self.Source = self.Data
	end
	local last = self.Source[#self.Source]
	if last then
		self.Live.O, self.Live.H, self.Live.L, self.Live.C = last.O, last.H, last.L, last.C
	end
end

function ChartView.SetData(self: any, candles: { Candle }, tf: any)
	if not self.Alive then
		return
	end
	local ticks = tonumber(tf)
	if not ticks and type(tf) == "string" then
		local map = { ["1s"] = 1, ["5s"] = 5, ["1m"] = 60, ["5m"] = 300, ["15m"] = 900, ["1T"] = 1200, ["1W"] = 8400 }
		ticks = map[tf]
	end
	self.TfTicks = math.max(1, math.floor(ticks or 60))
	local data: { Candle } = {}
	if type(candles) == "table" then
		local keep = self.N + DATA_KEEP_EXTRA
		for k = math.max(1, #candles - keep + 1), #candles do
			local c = copyCandle(candles[k])
			if c and (#data == 0 or c.T > data[#data].T) then
				table.insert(data, c)
			end
		end
	end
	self.Data = data
	self.Seq0 = 0
	local last = data[#data]
	self.LastTick = if last then last.T else 0
	self:_rebuildSource()
	local src = self.Source[#self.Source]
	if src then
		self.Shown.O, self.Shown.H, self.Shown.L, self.Shown.C = src.O, src.H, src.L, src.C
	end
	self.Lo, self.Hi = 0, 0
	self:_computeIndicators()
	self:HideCrosshair()
	if #data == 0 then
		for _, slot in ipairs(self.Slots) do
			self:_hideSlot(slot)
		end
		self:_hideLine(self.PriceLine)
		self:_hideLine(self.LiveSeg)
		for _, line in ipairs(self.Lines) do
			self:_hideLine(line)
		end
		return
	end
	self:SetPlaceholder(nil)
	self:_rebase()
	if self.PaneKind then
		self:_paneGuides()
	end
end

-- Neuer Kurs (1s-Kerze aus dem Frame): gleicher Bucket -> Live-Kerze, neuer Bucket -> neue Kerze (O(1))
function ChartView.PushQuote(self: any, close: number, tick: number, high: number?, low: number?, vol: number?)
	if not self.Alive or not finite(close) or close <= 0 or not finite(tick) then
		return
	end
	local data = self.Data
	local last = data[#data]
	if not last then
		return -- ohne Historie keine erfundenen Kerzen
	end
	local h = if finite(high) then math.max(high :: number, close) else close
	local l = if finite(low) then math.min(low :: number, close) else close
	local v = if finite(vol) then math.max(0, vol :: number) else 0
	local bucket = (tick // self.TfTicks) * self.TfTicks
	if bucket == last.T then
		if tick <= self.LastTick then
			last.C = close -- schon gezählt: nur den Schluss nachziehen
		else
			last.H = math.max(last.H, h)
			last.L = math.min(last.L, l)
			last.C = close
			last.V += v
		end
		self.LastTick = math.max(self.LastTick, tick)
		if self.Style == "HeikinAshi" then
			self:_rebuildSource()
		else
			self.Live.O, self.Live.H, self.Live.L, self.Live.C = last.O, last.H, last.L, last.C
		end
		self.IndDirty = #self.Lines > 0
		if not self.Smooth then
			self:_snapLive()
		end
		return
	elseif bucket < last.T then
		return
	end
	-- neue Kerze: Vorgänger endgültig zeichnen
	local prevA = self:_lastA()
	local prevSource = self.Source[#self.Source]
	if prevSource then
		self.Shown.O, self.Shown.H, self.Shown.L, self.Shown.C = prevSource.O, prevSource.H, prevSource.L, prevSource.C
		local slot = self:_slotFor(prevA)
		self:_paintSlot(slot, prevA, prevSource.O, prevSource.H, prevSource.L, prevSource.C, prevSource.V)
	end
	local open = last.C
	table.insert(data, {
		T = bucket,
		O = open,
		H = math.max(open, h),
		L = math.min(open, l),
		C = close,
		V = v,
	})
	self.LastTick = tick
	if #data > self.N + DATA_KEEP_EXTRA then
		table.remove(data, 1)
		self.Seq0 += 1
	end
	self:_rebuildSource()
	local src = self.Source[#self.Source]
	self.Shown.O, self.Shown.H, self.Shown.L, self.Shown.C = src.O, src.O, src.O, src.O
	if not self.Smooth then
		self.Shown.H, self.Shown.L, self.Shown.C = src.H, src.L, src.C
	end
	local lastA = self:_lastA()
	-- ältester Slot wird recycelt: neuer Index lastA
	local slot = self:_slotFor(lastA)
	self:_paintSlot(slot, lastA, self.Shown.O, self.Shown.H, self.Shown.L, self.Shown.C, src.V)
	-- Streifen um eine Slot-Breite schieben
	if lastA - self.Base > self.N + 400 then
		self.NeedRebase = true -- Koordinaten zu groß -> beim nächsten Step neu auslegen
	end
	local goal = UDim2.fromScale(self:_stripX(), 0)
	local strips = { self.XStrip, self.GridStrip, self.VolStrip, self.PaneStrip, self.AxisXStrip }
	for _, tween in ipairs(self.Tweens) do
		tween:Cancel()
	end
	table.clear(self.Tweens)
	for _, strip in ipairs(strips) do
		if strip then
			if self.Smooth then
				local tween = TweenService:Create(strip, SCROLL_INFO, { Position = goal })
				table.insert(self.Tweens, tween)
				tween:Play()
			else
				strip.Position = goal
			end
		end
	end
	self:_advanceTimeLabel(lastA)
	-- Ziel-Bereich und Linien (einmal je neuer Kerze)
	self:_targetRange()
	if self.THi > self.RefHi or self.TLo < self.RefLo then
		self.NeedRebase = true
	end
	if self.VMaxTarget > self.VolRef * 1.15 or self.VMaxTarget < self.VolRef * 0.6 then
		self.NeedRebase = true
	end
	if #self.Lines > 0 then
		self:_computeIndicators()
	end
	self:_drawLines()
	if self.Cross then
		self:_drawCross()
	end
end

-- ohne Glätten (Welt-Monitore): Live-Kerze sofort zeichnen
function ChartView._snapLive(self: any)
	local live = self.Live
	local s = self.Shown
	s.O, s.H, s.L, s.C = live.O, live.H, live.L, live.C
	local lastA = self:_lastA()
	local src = self.Source[#self.Source]
	if src then
		self:_paintSlot(self:_slotFor(lastA), lastA, s.O, s.H, s.L, s.C, src.V)
	end
	if self.Style == "Line" or self.Style == "Area" then
		self:_drawLiveSegment()
	end
	self:_drawLast()
end

function ChartView.SetIndicators(self: any, map: { [string]: boolean }?)
	local want = if type(map) == "table" then map else {}
	self.IndMap = table.clone(want)
	for _, line in ipairs(self.Lines) do
		self:_releaseLine(line)
	end
	table.clear(self.Lines)
	local budget = self.MaxLines
	local colors = ChartView.Colors
	for _, key in ipairs(OVERLAY_ORDER) do
		if want[key] and budget > 0 then
			budget -= 1
			if key == "BB" then
				table.insert(self.Lines, self:_newLine("BBU", colors.BB, 1, 0.15, false))
				table.insert(self.Lines, self:_newLine("BBM", colors.BB, 1, 0.55, false))
				table.insert(self.Lines, self:_newLine("BBL", colors.BB, 1, 0.15, false))
			else
				table.insert(self.Lines, self:_newLine(key, (colors :: any)[key], 1.5, 0, false))
			end
		end
	end
	local pane: string? = nil
	for _, key in ipairs(PANE_ORDER) do
		if want[key] and budget > 0 and pane == nil then
			pane = key
			budget -= 1
		end
	end
	if pane == "RSI" then
		table.insert(self.Lines, self:_newLine("RSI", colors.RSI, 1.5, 0, true))
	elseif pane == "MACD" then
		table.insert(self.Lines, self:_newLine("MACD", colors.MACD, 1.5, 0, true))
		table.insert(self.Lines, self:_newLine("MACDSignal", colors.MACDSignal, 1.5, 0, true))
	elseif pane == "Stoch" then
		table.insert(self.Lines, self:_newLine("StochK", colors.StochK, 1.5, 0, true))
		table.insert(self.Lines, self:_newLine("StochD", colors.StochD, 1.5, 0, true))
	elseif pane == "ATR" then
		table.insert(self.Lines, self:_newLine("ATR", colors.ATR, 1.5, 0, true))
	end
	if pane ~= self.PaneKind then
		self.PaneKind = pane
		self:_layout()
	end
	self:_computeIndicators()
	if pane then
		self:_paneGuides()
	elseif self.PaneGuides then
		for _, guide in ipairs(self.PaneGuides) do
			guide.Visible = false
		end
	end
	if #self.Data > 0 then
		self:_rebase()
	end
end

function ChartView.SetStyle(self: any, style: string)
	local valid = { Candles = true, Hollow = true, Line = true, Area = true, HeikinAshi = true }
	if not valid[style] then
		return
	end
	if style == "Area" and not self.AreaAlloc then
		style = "Line" -- Fläche nur mit vorbereiteten Streifen (High/Ultra)
	end
	if self.Style == style then
		return
	end
	self.Style = style
	self:_rebuildSource()
	local src = self.Source[#self.Source]
	if src then
		self.Shown.O, self.Shown.H, self.Shown.L, self.Shown.C = src.O, src.H, src.L, src.C
	end
	if #self.Lines > 0 then
		self:_computeIndicators()
	end
	if #self.Data > 0 then
		self:_rebase()
	end
end

function ChartView.SetAlerts(self: any, list: { any }?)
	local clean: { { Px: number, Dir: string } } = {}
	if type(list) == "table" then
		for _, alert in ipairs(list) do
			if type(alert) == "table" and finite(alert.Px) and #clean < MAX_ALERTS then
				table.insert(clean, { Px = alert.Px, Dir = if alert.Dir == "Up" then "Up" else "Down" })
			end
		end
	end
	self.Alerts = clean
	self:_drawMarkers()
end

function ChartView.SetMarks(self: any, list: { any }?)
	local clean: { { Px: number, Color: Color3, Text: string } } = {}
	if type(list) == "table" then
		for _, mark in ipairs(list) do
			if type(mark) == "table" and finite(mark.Px) and #clean < MAX_MARKS then
				table.insert(clean, {
					Px = mark.Px,
					Color = if typeof(mark.Color) == "Color3" then mark.Color else Theme.Accent,
					Text = if type(mark.Text) == "string" then mark.Text else "",
				})
			end
		end
	end
	self.Marks = clean
	self:_drawMarkers()
end

-- Farben neu (Farbenblind-Modus)
function ChartView.Repaint(self: any)
	for _, slot in ipairs(self.Slots) do
		slot.Color = nil
	end
	if #self.Data > 0 then
		self:_relayoutAll()
	end
end

function ChartView.SetVisible(self: any, on: boolean)
	self.Visible = on == true
	if self.Root.Visible ~= self.Visible then
		self.Root.Visible = self.Visible
	end
end

function ChartView.Count(self: any): number
	return #self.Data
end

function ChartView.PriceRange(self: any): (number, number)
	return self.Lo, self.Hi
end

function ChartView.Stats(self: any): { [string]: any }
	return { Objects = self.Objects, Path2D = path2dOk, Candles = self.N }
end

-- Je Frame (Terminal/Monitors): nur Live-Kerze + y-Transformation (O(1)); Neu-Auslegen höchstens 1×/s
function ChartView.Step(self: any, dt: number)
	if not self.Alive or not self.Visible or #self.Data == 0 then
		return
	end
	local now = os.clock()
	if self.IndDirty and now - self.IndAt >= INDICATOR_GAP then
		self:_computeIndicators(true)
		self:_drawLiveIndicators()
	end
	if now - self.RebaseAt >= REBASE_GAP then
		self:_targetRange()
		local shownSpan = self.Hi - self.Lo
		local targetSpan = self.THi - self.TLo
		local outside = self.THi > self.RefHi or self.TLo < self.RefLo
		local tooWide = (self.RefHi - self.RefLo) > 3.2 * targetSpan
		local shrink = shownSpan > 0 and targetSpan < shownSpan * (1 - SHRINK_REBASE)
		if self.NeedRebase or outside or tooWide or (not path2dOk and shrink) then
			self:_rebase()
		else
			self.RebaseAt = now
		end
	end
	-- y-Bereich gleitet (nur mit Path2D; Segmente würden verzerren)
	if self.Smooth and path2dOk then
		local a = 1 - math.exp(-RANGE_K * math.max(0, dt))
		local lo = self.Lo + (self.TLo - self.Lo) * a
		local hi = self.Hi + (self.THi - self.Hi) * a
		if math.abs(lo - self.Lo) > 1e-4 or math.abs(hi - self.Hi) > 1e-4 then
			self.Lo, self.Hi = lo, hi
			self:_applyTransform()
		end
	end
	-- Live-Kerze gleitet zum neuesten Kurs (keine erfundenen Zwischenkurse: Ziel = echter Schluss)
	if self.Smooth then
		local live = self.Live
		local s = self.Shown
		local a = 1 - math.exp(-LIVE_K * math.max(0, dt))
		local moved = false
		local function ease(cur: number, target: number): number
			local nextValue = cur + (target - cur) * a
			if math.abs(target - nextValue) < 0.05 then
				nextValue = target
			end
			if nextValue ~= cur then
				moved = true
			end
			return nextValue
		end
		s.O = ease(s.O, live.O)
		s.H = ease(s.H, live.H)
		s.L = ease(s.L, live.L)
		s.C = ease(s.C, live.C)
		if moved then
			local lastA = self:_lastA()
			local src = self.Source[#self.Source]
			self:_paintSlot(
				self:_slotFor(lastA),
				lastA,
				s.O,
				math.max(s.H, s.O, s.C),
				math.min(s.L, s.O, s.C),
				s.C,
				src.V
			)
			if self.Style == "Line" or self.Style == "Area" then
				self:_drawLiveSegment()
			end
			self:_drawLast()
		end
	end
end

function ChartView.Destroy(self: any)
	if not self.Alive then
		return
	end
	self.Alive = false
	for _, conn in ipairs(self.Conns) do
		conn:Disconnect()
	end
	table.clear(self.Conns)
	for _, tween in ipairs(self.Tweens) do
		tween:Cancel()
	end
	table.clear(self.Tweens)
	self.Root:Destroy()
end

-- ---------------------------------------------------------------------
-- BIBLIOTHEK
-- ---------------------------------------------------------------------
function ChartView.HasPath2D(): boolean
	return path2dOk
end

function ChartView.Init(context: any)
	ctx = context
	local ok, result = pcall(function(): number
		if Path2DPoint == nil then
			return 0
		end
		local path = Instance.new("Path2D")
		path:SetControlPoints({
			Path2DPoint.new(UDim2.fromScale(0, 0)),
			Path2DPoint.new(UDim2.fromScale(1, 1)),
		})
		local max = path:GetMaxControlPoints()
		path:Destroy()
		return max
	end)
	if ok and type(result) == "number" and result >= 2 then
		path2dOk = true
		path2dMax = math.min(result, 512)
	else
		path2dOk = false
		path2dMax = 0
		warn("[ChartView] Path2D nicht verfügbar – Linien als Segment-Frames (Rückfall)")
	end
end

return ChartView
