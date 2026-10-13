-- =====================================================================
--  AKYTEX TYCOON – UI-BAUKASTEN im AKYTEX-Look (Client/Modules/UI)
--  Besitzer: WP2 (Client-Plattform & UI-Kit). Basis: CC-UI-Kit 1:1 (REUSE §4) + AT-Neuteile (§C7.5, REUSE §4.10/§4.11).
--  Stil: dunkles Glas wie die AKYTEX-Website – Flächen aus UI.Theme (Glas-Fenster mit 1-px-Rahmen), Schrift aus
--  UI.Fonts (Enum, Builder Sans/Michroma/Titillium) und UI.Faces (FontFace: BuilderExtended = Anzeige/Titel,
--  BuilderMono = alle Preise/Zahlen ohne Zittern, BuilderSans = Fließtext; Rückfall Michroma/TitilliumWeb/BuilderSans).
--  Bewegung iOS-artig: Öffnen 0.26 s Quint Out + 8 px Gleiten, Schließen 0.14 s Quad In, Hover 0.12 s,
--  Drücken = Feder auf 0.97 + kurzer Farbblitz, Loslassen 0.3 s Back Out, Zähler alpha = 1 − e^(−7t) ≤ 30 Hz.
--
--  Öffentliche API (REUSE §4 + §C7.3 + §C7.5):
--    UI.Font, UI.Fonts, UI.Faces { Display, Mono, Body, DisplayRegular, MonoBold, BodyBold }, UI.Theme, UI.Root
--    UI.Init(ctxOrGui), UI.Start(), UI.Frame(dt)       (Frame kommt aus dem einen PreRender-Loop von Main.client)
--    UI.Create, UI.Corner, UI.Stroke, UI.TextStroke, UI.Gradient, UI.ButtonSequence, UI.FormatMult, UI.FormatSteps,
--    UI.Upper, UI.Label, UI.TextBox, UI.Button, UI.Badge, UI.SetBadge, UI.Section, UI.Row, UI.Grid, UI.Card, UI.Panel,
--    UI.Divider, UI.Bar, UI.SetBar, UI.Pulse, UI.Counter, UI.SetCounter, UI.RedrawCounter
--    UI.Window, UI.Sheet(title, height), UI.OpenWindow, UI.CloseWindow, UI.ToggleWindow, UI.CloseAll, UI.IsAnyWindowOpen
--    UI.Windows = { Register(name, open, close?), Open(name), Close(name?), IsOpen(name?), Toggle(name) }  (= ctx.Windows)
--    UI.Toast(text, kind?), UI.SetToastTop(offset?)
--    UI.FetchPrice(id, infoType, cb), UI.WhenRandomItemsKnown(cb), UI.RandomItemsAllowed()
--  Neu für AT (§C7.5):
--    UI.Segmented(parent, options, onChange): { Frame, Set(key, silent?), Get() }
--    UI.PriceTag(label, cents, change?)          Preis + ▲/▼ + Prozent (Up/Down, Farbenblind-Modus)
--    UI.Sparkline(parent, n): { Frame, Set(points) }
--    UI.Ticker(parent): { Frame, SetRows(rows), SetSpeed(pxPerSecond) }     Laufband (gepoolte Labels, O(1) je Frame)
--    UI.Chip, UI.StatTile, UI.RowCard, UI.RowActions, UI.Slider, UI.Cycler, UI.NavItem   (aus CC AdminPanel gehoben)
--  Zusätzlich: UI.CurrencyIcon(parent, "CR" | "AKY", size), UI.SetColorblind(on), UI.UpColor(), UI.DownColor(),
--    UI.TrendColor(change), UI.TrendArrow(change), UI.ScaleOf(inst), UI.ColorHex(color)
--  UI.Button(props, onClick): props Name, Size, Position, AnchorPoint, LayoutOrder, Parent, Visible, ZIndex, Text, Sub,
--    Variant ("Primary" | "Secondary" | "Danger" | "Success" | "Ghost" | "Premium" | "Muted"), Color, MaxText, SubMax,
--    Corner, Wrap, Silent, Face. Rückgabe { Frame, Button, Label, Sub?, Stroke, SetText, SetSub, SetColor, SetVariant }.
--  Fenster offen -> sichtbarer Modal-Knopf (gibt die Maus frei), Hooks "WindowOpened"/"WindowClosed"(name), Blur
--  "AkytexTycoonWindowBlur". ProximityPrompt mit Attribut "Window" öffnet das registrierte Fenster.
-- =====================================================================

local Lighting = game:GetService("Lighting")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UI = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

-- ---------------------------------------------------------------------
-- SCHRIFTEN
-- Enum-Schriften (UI.Fonts) für alles, was .Font nutzt; FontFace-Familien (UI.Faces) für Titel, Zahlen, Text.
-- ---------------------------------------------------------------------
UI.Font = Enum.Font.BuilderSansBold
UI.Fonts = {
	Main = Enum.Font.BuilderSansBold, -- Knöpfe, Labels
	Body = Enum.Font.BuilderSans, -- Fließtext, Beschreibungen
	Strong = Enum.Font.BuilderSansExtraBold, -- große Zahlen/Titel in Karten
	Heading = Enum.Font.Michroma, -- Rückfall für Titel
	Number = Enum.Font.TitilliumWeb, -- Rückfall für Zahlen
	Banner = Enum.Font.Michroma, -- große Ansagen
	Pop = Enum.Font.BuilderSansExtraBold,
}

local FACE_DISPLAY = "rbxasset://fonts/families/BuilderExtended.json"
local FACE_MONO = "rbxasset://fonts/families/BuilderMono.json"
local BODY_FAMILY = Font.fromEnum(Enum.Font.BuilderSans).Family

UI.Faces = {
	Display = Font.new(FACE_DISPLAY, Enum.FontWeight.Bold), -- Logo, Fenstertitel, große Zahlen (≈ Unbounded)
	DisplayRegular = Font.new(FACE_DISPLAY, Enum.FontWeight.Regular),
	Mono = Font.new(FACE_MONO, Enum.FontWeight.Regular), -- Preise, G/V, Achsen (tabellarische Ziffern)
	MonoBold = Font.new(FACE_MONO, Enum.FontWeight.Bold),
	Body = Font.new(BODY_FAMILY, Enum.FontWeight.Regular), -- Fließtext
	BodyBold = Font.new(BODY_FAMILY, Enum.FontWeight.Bold),
}
-- Rückfall, falls BuilderExtended/BuilderMono auf einem Gerät fehlen (Prüfung in UI.Init)
local FACE_FALLBACK: { [string]: Font } = {
	Display = Font.fromEnum(Enum.Font.Michroma),
	DisplayRegular = Font.fromEnum(Enum.Font.Michroma),
	Mono = Font.fromEnum(Enum.Font.TitilliumWeb),
	MonoBold = Font.new(Font.fromEnum(Enum.Font.TitilliumWeb).Family, Enum.FontWeight.Bold),
	Body = Font.fromEnum(Enum.Font.BuilderSans),
	BodyBold = Font.fromEnum(Enum.Font.BuilderSansBold),
}
local FACE_CHECK_TEXT = "ÄÖÜß Λ 0123456789"
local FACE_CHECK_WAIT = 0.6 -- so lange darf die Prüfung den Start höchstens aufhalten

-- ---------------------------------------------------------------------
-- FARBEN (DESIGN §A4, exakt CC-UI.Theme)
-- ---------------------------------------------------------------------
local AKY = {
	Bg = Color3.fromRGB(11, 15, 23), -- #0b0f17
	Bg2 = Color3.fromRGB(15, 20, 29), -- #0f141d
	Surface = Color3.fromRGB(18, 24, 36), -- #121824 (Panel)
	Surface2 = Color3.fromRGB(26, 33, 48), -- #1a2130 (Karte)
	Hover = Color3.fromRGB(31, 40, 56), -- #1f2838
	Border = Color3.fromRGB(31, 41, 55), -- #1f2937
	Text = Color3.fromRGB(230, 236, 245), -- #e6ecf5
	Text2 = Color3.fromRGB(170, 180, 195), -- #aab4c3
	Muted = Color3.fromRGB(125, 136, 154), -- #7d889a
	Accent = Color3.fromRGB(79, 140, 255), -- #4f8cff
	AccentDeep = Color3.fromRGB(41, 98, 255), -- #2962ff
	Up = Color3.fromRGB(34, 197, 94), -- #22c55e
	Down = Color3.fromRGB(239, 68, 68), -- #ef4444
	Warn = Color3.fromRGB(234, 179, 8), -- #eab308
}
UI.Theme = {
	Bg = AKY.Bg,
	Bg2 = AKY.Bg2,
	Surface = AKY.Surface,
	Surface2 = AKY.Surface2,
	Hover = AKY.Hover,
	Border = AKY.Border,
	Text = AKY.Text,
	Text2 = AKY.Text2,
	Muted = AKY.Muted,
	Accent = AKY.Accent,
	AccentDeep = AKY.AccentDeep,
	Up = AKY.Up,
	Down = AKY.Down,
	Warn = AKY.Warn,
	-- Alias-Schlüssel (CC-Kompatibilität)
	Panel = AKY.Surface,
	PanelDark = AKY.Bg,
	PanelLight = AKY.Surface2,
	SubText = AKY.Text2,
	Black = BLACK,
	Yellow = AKY.Warn,
	Cash = AKY.Up,
	Red = AKY.Down,
	Blue = AKY.Accent,
	Green = AKY.Up,
	Gray = AKY.Muted,
	-- Akzente
	Orange = Color3.fromRGB(245, 158, 11), -- #f59e0b
	Purple = Color3.fromRGB(139, 92, 246), -- #8b5cf6
	Pink = Color3.fromRGB(236, 72, 153), -- #ec4899
	Gold = Color3.fromRGB(250, 204, 21), -- #facc15 (nur Kronen, Glocke, Hall-of-Fame)
	Cyan = Color3.fromRGB(34, 211, 238), -- #22d3ee
	-- Space-Set (Nacht/Hero-Momente) + Logo
	Space = Color3.fromRGB(3, 4, 10), -- #03040a
	SpaceAccent = Color3.fromRGB(124, 156, 255), -- #7c9cff
	Cosmic1 = Color3.fromRGB(59, 91, 219), -- #3b5bdb
	Cosmic2 = Color3.fromRGB(124, 92, 255), -- #7c5cff
	Cosmic3 = Color3.fromRGB(179, 107, 255), -- #b36bff
	SpaceGold = Color3.fromRGB(255, 207, 110), -- #ffcf6e
	LogoRing = Color3.fromRGB(110, 162, 242), -- #6ea2f2
	LogoLetters = Color3.fromRGB(234, 241, 255), -- #eaf1ff
}
local Theme = UI.Theme

-- Farbenblind-Modus (Einstellung "Colorblind"): Up/Down -> Accent/Orange, ▲/▼ bleiben immer sichtbar
local colorblind = false

-- Bewegung (iOS-artig, wie AKYTEX --ease-ios) – einmal angelegt und immer wiederverwendet
local HOVER_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_INFO = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out) -- leichte Feder
local OPEN_FADE_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local OPEN_SCALE_INFO = TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local SHEET_OPEN_INFO = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local CLOSE_INFO = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local SHEET_CLOSE_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local BLUR_IN_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local BLUR_OUT_INFO = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local COUNTER_FLASH_INFO = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
local BAR_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local PULSE_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local FOCUS_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SEGMENT_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TOAST_GROW_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local TOAST_IN_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TOAST_OUT_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local COUNTER_INTERVAL = 1 / 30 -- Zahlen höchstens 30x pro Sekunde neu schreiben
local COUNTER_POP_GAP = 0.15 -- so oft höchstens ein Aufploppen pro Zähler
local PRESS_SCALE = 0.97 -- gedrückter Knopf (Feder)
local HOVER_LIGHTEN = 0.08 -- Hover: Fläche etwas heller
local PRESS_LIGHTEN = 0.16 -- Drücken: kurzer Farbblitz
local BLUR_SIZE = 9 -- leichter Weichzeichner hinter offenen Fenstern (AKYTEX 8–10)
local WINDOW_SLIDE = 8 -- Fenster gleiten aus so vielen Pixeln von unten herein
local WINDOW_PAD = 10 -- Rand der Animations-Fläche (Platz für den weichen Schatten)
local WINDOW_HEADER = 58 -- Höhe des Fenster-Kopfs (Titel + ✕)
local SHEET_MAX_WIDTH = 760 -- Bottom-Sheet auf großen Bildschirmen höchstens so breit
local SHEET_DRAG_CLOSE = 80 -- so weit nach unten ziehen = Sheet schließen
local TOAST_WIDTH = 640 -- Breite der Toast-Spalte (eine Pill ist höchstens so breit)
local TOAST_PAD_X = 16
local TOAST_DOT = 8
local TOAST_DOT_GAP = 10
local TOAST_MIN_HEIGHT = 36
local TOAST_GAP = 6
local TOAST_SLIDE = 8 -- Toasts gleiten aus 8 px darüber herein
local MAX_TOASTS = 5
local MAX_TOAST_POOL = 8 -- so viele fertige Toasts werden zum Wiederverwenden aufgehoben
local RANDOM_STATE_WAIT = 30 -- so lange auf den Server-Wert "RandomAllowed" warten, dann PolicyService selbst fragen
local HOVER_SOUND_GAP = 0.08 -- Hover-Ton höchstens so oft
local FINE_STROKE_T = 0.5 -- feine Text-Kontur über der 3D-Welt (AKYTEX: 1 px, Transparenz 0.35–0.5)
local TICKER_SPEED = 42 -- Laufband: Pixel pro Sekunde (vor UIScale) ≈ Website-Loop
local TICKER_GAP = 28 -- Abstand zwischen zwei Laufband-Einträgen
local TICKER_MAX_ROWS = 64 -- mehr Einträge zeigt ein Laufband nie (Pool-Grenze)
local MAX_SPARK_POINTS = 240 -- Sparkline-Pool-Grenze

-- Alte Schriften (Comic-Look) -> AKYTEX-Schriften
local LEGACY_FONTS: { [Enum.Font]: Enum.Font } = {
	[Enum.Font.FredokaOne] = UI.Fonts.Main,
	[Enum.Font.LuckiestGuy] = UI.Fonts.Heading,
	[Enum.Font.Bangers] = UI.Fonts.Banner,
	[Enum.Font.Gotham] = UI.Fonts.Body,
	[Enum.Font.GothamMedium] = UI.Fonts.Main,
	[Enum.Font.GothamBold] = UI.Fonts.Main,
	[Enum.Font.GothamBlack] = UI.Fonts.Strong,
}

local root: ScreenGui? = nil
local ctx: any = nil -- gemeinsamer Rucksack (nach UI.Init mit ctx gesetzt; für Hooks/Sfx/State/Format)
UI.Root = nil :: ScreenGui? -- die ScreenGui der Oberfläche (nach UI.Init gesetzt)

-- Optionale Sounds über Sfx (fehlt das Modul, passiert einfach nichts)
local lastHoverSound = 0
local function playUiSound(role: string)
	local modules = ctx and ctx.Modules
	local sfx = modules and modules.Sfx
	if sfx and type(sfx.Play) == "function" then
		pcall(sfx.Play, role)
	end
end

local function fireHook(name: string, ...: any)
	local hooks = ctx and ctx.Hooks
	if hooks and type(hooks.Fire) == "function" then
		hooks.Fire(name, ...)
	end
end

local function sameColor(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) < 0.004 and math.abs(a.G - b.G) < 0.004 and math.abs(a.B - b.B) < 0.004
end

local function luminance(c: Color3): number
	return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end

-- Alter Standard-Akzent (Orange) -> AKYTEX-Akzent (für Balken, Bildlaufleisten, Unterstriche)
local function accentOf(color: Color3?): Color3
	if typeof(color) ~= "Color3" or sameColor(color, Theme.Orange) then
		return Theme.Accent
	end
	return color
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

-- ---------------------------------------------------------------------
-- FARB-HELFER (Trend, Farbenblind-Modus)
-- ---------------------------------------------------------------------
function UI.SetColorblind(on: boolean)
	colorblind = on == true
end

function UI.UpColor(): Color3
	return if colorblind then Theme.Accent else Theme.Up
end

function UI.DownColor(): Color3
	return if colorblind then Theme.Orange else Theme.Down
end

-- Farbe zu einer Veränderung (positiv Up, negativ Down, 0 Muted)
function UI.TrendColor(change: number?): Color3
	local n = tonumber(change) or 0
	if n ~= n or n == 0 then
		return Theme.Muted
	end
	return if n > 0 then UI.UpColor() else UI.DownColor()
end

function UI.TrendArrow(change: number?): string
	local n = tonumber(change) or 0
	if n ~= n or n == 0 then
		return "–"
	end
	return if n > 0 then "▲" else "▼"
end

-- "#rrggbb" für RichText
function UI.ColorHex(color: Color3): string
	return string.format(
		"#%02x%02x%02x",
		math.clamp(math.floor(color.R * 255 + 0.5), 0, 255),
		math.clamp(math.floor(color.G * 255 + 0.5), 0, 255),
		math.clamp(math.floor(color.B * 255 + 0.5), 0, 255)
	)
end

-- Aufsummierte UIScale über einer GUI (AbsoluteSize ist nach der Skalierung, Offsets davor)
function UI.ScaleOf(inst: Instance): number
	local factor = 1
	local current: Instance? = inst
	local guard = 0
	while current and guard < 64 do
		guard += 1
		local scale = current:FindFirstChildOfClass("UIScale")
		if scale then
			factor *= scale.Scale
		end
		if current:IsA("LayerCollector") then
			break
		end
		current = current.Parent
	end
	if factor <= 0 or factor ~= factor then
		return 1
	end
	return factor
end

-- ---------------------------------------------------------------------
-- GRUNDBAUSTEINE
-- ---------------------------------------------------------------------
function UI.Create(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for key, value in pairs(props) do
			if key == "Parent" then
				parent = value
			elseif key == "Font" and LEGACY_FONTS[value] then
				(inst :: any).Font = LEGACY_FONTS[value]
			else
				(inst :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in ipairs(children) do
			child.Parent = inst
		end
	end
	inst.Parent = parent
	return inst
end

function UI.Corner(radius: number?): UICorner
	return UI.Create("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

-- 1-px-Rahmen (AKYTEX). Schwarz/ohne Farbe = Border-Token; farbige Rahmen bleiben, höchstens 2 px dick.
function UI.Stroke(color: Color3?, thickness: number?): UIStroke
	local plain = color == nil or sameColor(color :: Color3, BLACK)
	return UI.Create("UIStroke", {
		Color = if plain then Theme.Border else color,
		Thickness = if plain then 1 else math.clamp(thickness or 1, 1, 2),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

-- Feine dunkle Text-Kontur (nur für Text über der 3D-Welt nötig; AKYTEX: 1–1.5 px, halb durchsichtig)
function UI.TextStroke(thickness: number?): UIStroke
	return UI.Create("UIStroke", {
		Thickness = math.clamp(thickness or 1, 1, 1.5),
		Color = BLACK,
		Transparency = FINE_STROKE_T,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

-- Farbverlauf von oben nach unten
function UI.Gradient(top: Color3, bottom: Color3, rotation: number?): UIGradient
	return UI.Create("UIGradient", { Rotation = rotation or 90, Color = ColorSequence.new(top, bottom) })
end

-- Dezenter Verlauf einer Füllfarbe (AKYTEX: kaum sichtbar, kein Bonbon-Glanz)
function UI.ButtonSequence(color: Color3): ColorSequence
	return ColorSequence.new(color:Lerp(WHITE, 0.07), color:Lerp(BLACK, 0.05))
end

-- 1.25 -> "1.25", 2 -> "2", 2.5 -> "2.5"
function UI.FormatMult(value: number?): string
	local n = tonumber(value) or 1
	if n ~= n or n <= 0 then
		return "1"
	end
	local text = string.format("%.2f", n)
	text = text:gsub("0+$", "")
	text = text:gsub("%.$", "")
	return text
end

-- Kleine Mengen mit einer Nachkommastelle (2.5 statt 2), große wie gewohnt (3.1M)
function UI.FormatSteps(value: number, formatNumber: (number) -> string): string
	local n = tonumber(value) or 0
	if n ~= n then
		return "0"
	end
	if math.abs(n) < 100 and math.floor(n) ~= n then
		local text = string.format("%.1f", n)
		text = text:gsub("%.0$", "")
		return text
	end
	return formatNumber(n)
end

-- Text in GROSSBUCHSTABEN (Titel, Knopf-Wörter). Auch ä/ö/ü -> Ä/Ö/Ü; Emojis bleiben, wie sie sind.
local UMLAUT_UPPER: { [string]: string } = { ["ä"] = "Ä", ["ö"] = "Ö", ["ü"] = "Ü" }
function UI.Upper(text: string): string
	local upper = string.gsub(string.upper(text), "\195[\164\182\188]", UMLAUT_UPPER)
	return upper
end

-- Text-Label. MaxText = größte Schriftgröße (TextScaled), Outline = feine Kontur, Face = Schlüssel aus UI.Faces.
function UI.Label(props: { [string]: any }): TextLabel
	local face = props.Face
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		TextColor3 = Theme.Text,
		TextScaled = true,
		Text = "",
	}
	if type(face) == "string" and UI.Faces[face] then
		base.FontFace = UI.Faces[face]
	elseif typeof(props.FontFace) ~= "Font" then
		base.Font = UI.Fonts.Main
	end
	for key, value in pairs(props) do
		if key ~= "MaxText" and key ~= "Outline" and key ~= "Face" and not (key == "Font" and base.FontFace) then
			base[key] = value
		end
	end
	local children: { Instance } = { UI.Create("UITextSizeConstraint", { MaxTextSize = props.MaxText or 28 }) }
	if props.Outline then
		table.insert(children, UI.TextStroke(1))
	end
	return UI.Create("TextLabel", base, children)
end

-- Eingabefeld: Surface2, 1-px-Rahmen, Fokus = Akzent-Rahmen
function UI.TextBox(props: { [string]: any }): TextBox
	local base: { [string]: any } = {
		BackgroundColor3 = Theme.Surface2,
		Font = UI.Fonts.Body,
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.Muted,
		TextScaled = true,
		ClearTextOnFocus = false,
		Text = "",
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	local stroke: UIStroke = UI.Create("UIStroke", {
		Color = Theme.Border,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
	local box: TextBox = UI.Create("TextBox", base, {
		UI.Corner(10),
		stroke,
		UI.Create("UITextSizeConstraint", { MaxTextSize = 18 }),
		UI.Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
	})
	box.Focused:Connect(function()
		TweenService:Create(stroke, FOCUS_INFO, { Color = Theme.Accent }):Play()
	end)
	box.FocusLost:Connect(function()
		TweenService:Create(stroke, FOCUS_INFO, { Color = Theme.Border }):Play()
	end)
	return box
end

-- ---------------------------------------------------------------------
-- KNÖPFE (Halter-Rahmen für das Layout + Knopf-Fläche darin)
-- Aufbau: Halter (unsichtbar, Name = props.Name) -> "Button" (Fläche, Ecke 10–12, 1-px-Rahmen,
--         UIScale für die Feder) -> "Label" (+ "Sub", kleine zweite Zeile)
-- ---------------------------------------------------------------------
export type Button = {
	Frame: Frame,
	Button: TextButton,
	Label: TextLabel,
	Sub: TextLabel?,
	Stroke: UIStroke,
	SetText: (text: string) -> (),
	SetSub: (text: string) -> (),
	SetColor: (color: Color3) -> (),
	SetVariant: (variant: string) -> (),
}

type Look = {
	Bg: Color3,
	BgT: number,
	Hover: Color3,
	HoverT: number,
	Text: Color3,
	Sub: Color3,
	SubT: number,
	Stroke: Color3,
	StrokeT: number,
}

local VARIANTS: { [string]: boolean } = {
	Primary = true,
	Secondary = true,
	Danger = true,
	Success = true,
	Ghost = true,
	Premium = true,
	Muted = true,
}

-- Theme-Token -> Variante
local COLOR_VARIANTS: { { Color: Color3, Variant: string } } = {
	{ Color = Theme.Accent, Variant = "Primary" },
	{ Color = Theme.AccentDeep, Variant = "Primary" },
	{ Color = Theme.Orange, Variant = "Primary" }, -- alter Standard-Knopf
	{ Color = Theme.Down, Variant = "Danger" },
	{ Color = Theme.Up, Variant = "Success" },
	{ Color = Theme.Warn, Variant = "Premium" },
	{ Color = Theme.Gold, Variant = "Premium" },
	{ Color = Theme.Muted, Variant = "Muted" },
	{ Color = Theme.Surface2, Variant = "Secondary" },
	{ Color = Theme.Surface, Variant = "Secondary" },
	{ Color = Theme.Hover, Variant = "Secondary" },
	{ Color = Theme.Bg, Variant = "Secondary" },
	{ Color = Theme.Bg2, Variant = "Secondary" },
}

local function variantFor(variant: any, color: any): (string, Color3?)
	if type(variant) == "string" and VARIANTS[variant] then
		return variant, nil
	end
	if typeof(color) ~= "Color3" then
		return "Primary", nil
	end
	for _, entry in ipairs(COLOR_VARIANTS) do
		if sameColor(color, entry.Color) then
			return entry.Variant, nil
		end
	end
	return "Custom", color
end

local function lookFor(variant: string, custom: Color3?): Look
	if variant == "Secondary" then
		return {
			Bg = Theme.Surface2,
			BgT = 0,
			Hover = Theme.Hover,
			HoverT = 0,
			Text = Theme.Text,
			Sub = Theme.Text2,
			SubT = 0,
			Stroke = Theme.Border,
			StrokeT = 0,
		}
	elseif variant == "Muted" then
		return {
			Bg = Theme.Surface2,
			BgT = 0.25,
			Hover = Theme.Hover,
			HoverT = 0,
			Text = Theme.Muted,
			Sub = Theme.Muted,
			SubT = 0.2,
			Stroke = Theme.Border,
			StrokeT = 0,
		}
	elseif variant == "Ghost" then
		return {
			Bg = Theme.Hover,
			BgT = 1,
			Hover = Theme.Hover,
			HoverT = 0,
			Text = Theme.Text2,
			Sub = Theme.Muted,
			SubT = 0,
			Stroke = Theme.Border,
			StrokeT = 1,
		}
	elseif variant == "Premium" then
		-- Fläche weiß × dezenter Verlauf Warn -> Orange (UIGradient am Knopf)
		return {
			Bg = WHITE,
			BgT = 0,
			Hover = WHITE,
			HoverT = 0,
			Text = Theme.Bg,
			Sub = Theme.Bg2,
			SubT = 0.15,
			Stroke = Theme.Warn:Lerp(WHITE, 0.35),
			StrokeT = 0.55,
		}
	end
	local fill = if variant == "Danger"
		then Theme.Down
		elseif variant == "Success" then Theme.Up
		elseif variant == "Custom" and custom then custom
		else Theme.Accent
	local dark = luminance(fill) > 0.62 -- helle Fläche -> dunkle Schrift
	local text = if dark then Theme.Bg else WHITE
	return {
		Bg = fill,
		BgT = 0,
		Hover = fill:Lerp(WHITE, HOVER_LIGHTEN),
		HoverT = 0,
		Text = text,
		Sub = text,
		SubT = 0.22,
		Stroke = fill:Lerp(WHITE, 0.25),
		StrokeT = 0.6,
	}
end

function UI.Button(props: { [string]: any }, onClick: (() -> ())?): Button
	local cornerRadius: number = math.clamp(tonumber(props.Corner) or 12, 6, 14)
	local z: number = props.ZIndex or 1
	local silent = props.Silent == true
	local holder: Frame = UI.Create("Frame", {
		Name = props.Name or "Button",
		Size = props.Size or UDim2.fromOffset(120, 40),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Visible = props.Visible ~= false,
		BackgroundTransparency = 1,
		ZIndex = z,
		Parent = props.Parent,
	})
	local variant, custom = variantFor(props.Variant, props.Color)
	local look = lookFor(variant, custom)

	local scale: UIScale = UI.Create("UIScale")
	local stroke: UIStroke = UI.Create("UIStroke", {
		Color = look.Stroke,
		Transparency = look.StrokeT,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
	local gradient: UIGradient = UI.Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Theme.Warn, Theme.Orange),
		Enabled = variant == "Premium",
	})
	local btn: TextButton = UI.Create("TextButton", {
		Name = "Button",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = look.Bg,
		BackgroundTransparency = look.BgT,
		AutoButtonColor = false,
		Text = "",
		ZIndex = z,
		Parent = holder,
	}, { UI.Corner(cornerRadius), stroke, gradient, scale })

	local hasSub = props.Sub ~= nil
	local main = UI.Label({
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, if hasSub then 0.08 else 0.16, 0),
		Size = UDim2.new(1, -14, if hasSub then 0.52 else 0.68, 0),
		Text = props.Text or "",
		TextWrapped = props.Wrap == true,
		Face = props.Face,
		TextColor3 = look.Text,
		MaxText = props.MaxText or 22,
		ZIndex = z + 1,
		Parent = btn,
	})
	local sub: TextLabel? = nil
	if hasSub then
		sub = UI.Label({
			Name = "Sub",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.6, 0),
			Size = UDim2.new(1, -14, 0.3, 0),
			Text = props.Sub,
			TextColor3 = look.Sub,
			TextTransparency = look.SubT,
			MaxText = props.SubMax or 15,
			ZIndex = z + 1,
			Parent = btn,
		})
	end

	-- Zustände: Hover (+8 % heller), Drücken (Feder 0.97 + kurzer Farbblitz), Loslassen (federt zurück)
	local hovering = false
	local pressed = false
	local function surface(): (Color3, number)
		local filled = variant ~= "Secondary" and variant ~= "Muted" and variant ~= "Ghost"
		if pressed then
			if filled then
				return look.Bg:Lerp(WHITE, PRESS_LIGHTEN), look.BgT
			end
			return look.Hover:Lerp(WHITE, 0.05), 0
		end
		if hovering then
			return look.Hover, look.HoverT
		end
		return look.Bg, look.BgT
	end
	local function repaint(info: TweenInfo)
		local color, transparency = surface()
		TweenService:Create(btn, info, { BackgroundColor3 = color, BackgroundTransparency = transparency }):Play()
		local strokeT = if hovering or pressed then math.max(0, look.StrokeT - 0.35) else look.StrokeT
		TweenService:Create(stroke, info, { Transparency = strokeT }):Play()
	end
	local function spring(target: number, info: TweenInfo)
		TweenService:Create(scale, info, { Scale = target }):Play()
	end
	local function setHover(on: boolean)
		if hovering == on then
			return
		end
		hovering = on
		if not on then
			pressed = false
			spring(1, RELEASE_INFO)
		end
		repaint(HOVER_INFO)
	end
	local function setPressed(on: boolean)
		if pressed == on then
			return
		end
		pressed = on
		spring(if on then PRESS_SCALE else 1, if on then PRESS_INFO else RELEASE_INFO)
		repaint(if on then PRESS_INFO else HOVER_INFO)
	end
	btn.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseMovement then
			setHover(true)
			local now = os.clock()
			if not silent and now - lastHoverSound >= HOVER_SOUND_GAP then
				lastHoverSound = now
				playUiSound("UIHover")
			end
		elseif kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			setPressed(true)
		end
	end)
	btn.InputEnded:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 then
			setPressed(false)
		elseif kind == Enum.UserInputType.Touch then
			setPressed(false)
			setHover(false)
		elseif kind == Enum.UserInputType.MouseMovement then
			setHover(false)
		end
	end)
	-- Controller-Auswahl wie Hover
	btn.SelectionGained:Connect(function()
		setHover(true)
	end)
	btn.SelectionLost:Connect(function()
		setHover(false)
	end)

	-- Klick: Fehler im Callback brechen die Oberfläche nicht, Doppelklicks werden ignoriert (nur UX – Server bleibt idempotent)
	local busy = false
	btn.Activated:Connect(function()
		if busy or not onClick then
			return
		end
		busy = true
		if not silent then
			playUiSound("UIClick")
		end
		local callback = onClick :: () -> ()
		task.spawn(function()
			local ok, err = pcall(callback)
			if not ok then
				warn("[UI] " .. tostring(err))
			end
			busy = false
		end)
	end)

	local function applyLook(newVariant: string, newCustom: Color3?)
		if newVariant == variant and newCustom == custom then
			return
		end
		variant, custom = newVariant, newCustom
		look = lookFor(variant, custom)
		gradient.Enabled = variant == "Premium"
		stroke.Color = look.Stroke
		main.TextColor3 = look.Text
		local subLabel = sub
		if subLabel then
			subLabel.TextColor3 = look.Sub
			subLabel.TextTransparency = look.SubT
		end
		repaint(HOVER_INFO)
	end

	local result: Button = {
		Frame = holder,
		Button = btn,
		Label = main,
		Sub = sub,
		Stroke = stroke,
		SetText = function(text: string)
			if main.Text ~= text then
				main.Text = text
			end
		end,
		SetSub = function(text: string)
			if sub and sub.Text ~= text then
				sub.Text = text
			end
		end,
		SetColor = function(color: Color3)
			local newVariant, newCustom = variantFor(nil, color)
			applyLook(newVariant, newCustom)
		end,
		SetVariant = function(name: string)
			local newVariant, newCustom = variantFor(name, nil)
			applyLook(newVariant, newCustom)
		end,
	}
	return result
end

-- Kleiner roter Punkt/Pille oben rechts an einem Knopf (z.B. Belohnung bereit)
function UI.Badge(target: Button, text: string?): Frame
	local badge: Frame = UI.Create("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 6, 0, 4),
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = Theme.Down,
		Visible = false,
		ZIndex = target.Button.ZIndex + 2,
		Parent = target.Button,
	}, {
		UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		UI.Create("UIStroke", { Color = Theme.Bg, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		UI.Create("UIScale", { Name = "Pulse" }),
	})
	UI.Label({
		Name = "Text",
		Position = UDim2.fromOffset(3, 2),
		Size = UDim2.new(1, -6, 1, -4),
		Text = text or "!",
		TextColor3 = WHITE,
		MaxText = 15,
		ZIndex = target.Button.ZIndex + 3,
		Parent = badge,
	})
	return badge
end

local BADGE_PULSE_INFO = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local badgePulses: { [Frame]: Tween } = {}

-- Badge setzen: text nil/"" = ausblenden. pulse = sanft pulsieren. Schreibt nur bei Änderungen.
function UI.SetBadge(badge: Frame, text: string?, color: Color3?, pulse: boolean?)
	local show = text ~= nil and text ~= ""
	if badge.Visible ~= show then
		badge.Visible = show
	end
	local label = badge:FindFirstChild("Text")
	if show and label and label:IsA("TextLabel") and label.Text ~= text then
		local value = text :: string
		label.Text = value
		local chars = utf8.len(value) or #value
		local width = if chars <= 1 then 22 else math.min(64, 10 + chars * 8)
		badge.Size = UDim2.fromOffset(width, 22)
	end
	local wanted = color or Theme.Down
	if badge.BackgroundColor3 ~= wanted then
		badge.BackgroundColor3 = wanted
	end
	local scale = badge:FindFirstChild("Pulse")
	if not scale or not scale:IsA("UIScale") then
		return
	end
	local tween = badgePulses[badge]
	local wantPulse = show and pulse == true
	if wantPulse and not tween then
		scale.Scale = 1
		local newTween = TweenService:Create(scale, BADGE_PULSE_INFO, { Scale = 1.15 })
		badgePulses[badge] = newTween
		newTween:Play()
		-- Badge zerstört: Puls-Eintrag aufräumen (starke Tabelle, kein schwacher Schlüssel – REUSE §7 #4)
		badge.Destroying:Once(function()
			local running = badgePulses[badge]
			if running then
				running:Cancel()
				badgePulses[badge] = nil
			end
		end)
	elseif not wantPulse and tween then
		tween:Cancel()
		badgePulses[badge] = nil
		scale.Scale = 1
	end
end

-- ---------------------------------------------------------------------
-- LAYOUT-HELFER (für Fenster-Inhalte)
-- ---------------------------------------------------------------------
-- Abschnitts-Titel: kleiner Akzent-Streifen links (Farbe = color oder Accent), Text in Text2
function UI.Section(parent: Instance, text: string, order: number, color: Color3?): TextLabel
	local label = UI.Label({
		Size = UDim2.new(1, 0, 0, 28),
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Text2,
		LayoutOrder = order,
		MaxText = 17,
		Parent = parent,
	})
	UI.Create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingTop = UDim.new(0, 6), Parent = label })
	UI.Create("Frame", {
		Name = "Accent",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -12, 0.5, 0),
		Size = UDim2.fromOffset(3, 14),
		BackgroundColor3 = accentOf(color),
		BorderSizePixel = 0,
		Parent = label,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	return label
end

function UI.Row(parent: Instance, order: number, height: number?): Frame
	return UI.Create("Frame", {
		Size = UDim2.new(1, 0, 0, height or 40),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	})
end

function UI.Grid(parent: Instance, order: number, cellX: number, cellY: number): Frame
	return UI.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	}, {
		UI.Create("UIGridLayout", {
			CellSize = UDim2.fromOffset(cellX, cellY),
			CellPadding = UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		UI.Create("UIPadding", {
			PaddingLeft = UDim.new(0, 2),
			PaddingTop = UDim.new(0, 2),
			PaddingBottom = UDim.new(0, 2),
		}),
	})
end

-- Karte: Surface2, Ecke 12, 1-px-Border-Rahmen
function UI.Card(props: { [string]: any }): Frame
	local base: { [string]: any } = { BackgroundColor3 = Theme.Surface2, BorderSizePixel = 0 }
	for key, value in pairs(props) do
		base[key] = value
	end
	return UI.Create("Frame", base, { UI.Corner(12), UI.Stroke(nil, 1) })
end

-- Glas-Fläche für HUD-Elemente über der Welt (Surface, leicht durchsichtig, 1-px-Rahmen)
function UI.Panel(props: { [string]: any }): Frame
	local base: { [string]: any } = {
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	return UI.Create("Frame", base, { UI.Corner(12), UI.Stroke(nil, 1) })
end

-- 1-px-Trennlinie (Border)
function UI.Divider(parent: Instance, order: number?): Frame
	return UI.Create("Frame", {
		Name = "Divider",
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Theme.Border,
		BorderSizePixel = 0,
		LayoutOrder = order or 0,
		Parent = parent,
	})
end

-- ---------------------------------------------------------------------
-- FORTSCHRITTSBALKEN (Füllung gleitet weich; Standard = Accent)
-- ---------------------------------------------------------------------
export type Bar = { Frame: Frame, Fill: Frame, Text: TextLabel, Ratio: number }

function UI.Bar(props: { [string]: any }): Bar
	local color = accentOf(props.Color)
	local back: Frame = UI.Create("Frame", {
		Size = props.Size or UDim2.new(1, 0, 0, 24),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = Theme.Bg2,
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }), UI.Stroke(nil, 1) })
	local fill: Frame = UI.Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Parent = back,
	}, {
		UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		UI.Create("UIGradient", { Rotation = 90, Color = UI.ButtonSequence(color) }),
	})
	local text = UI.Label({
		Size = UDim2.fromScale(1, 1),
		Text = "",
		MaxText = props.MaxText or 16,
		Outline = 1,
		ZIndex = 2,
		Parent = back,
	})
	return { Frame = back, Fill = fill, Text = text, Ratio = 0 }
end

function UI.SetBar(bar: Bar, ratio: number, text: string?)
	if ratio ~= ratio then
		ratio = 0
	end
	ratio = math.clamp(ratio, 0, 1)
	if text and bar.Text.Text ~= text then
		bar.Text.Text = text
	end
	if math.abs(ratio - bar.Ratio) > 0.001 then
		bar.Ratio = ratio
		TweenService:Create(bar.Fill, BAR_INFO, { Size = UDim2.fromScale(ratio, 1) }):Play()
	end
end

-- Kurzes "Aufploppen" (z.B. wenn CR reinkommen) – weich, ohne Überschwingen
function UI.Pulse(scale: UIScale, amount: number?)
	scale.Scale = 1 + (amount or 0.1)
	TweenService:Create(scale, PULSE_INFO, { Scale = 1 }):Play()
end

-- ---------------------------------------------------------------------
-- FLÜSSIG ZÄHLENDE ZAHLEN (CR, Depotwert, Tresor) – "Rollziffern" wie auf der Website
-- ---------------------------------------------------------------------
export type Counter = {
	Label: TextLabel,
	Format: (number) -> string,
	Target: number,
	Shown: number,
	Text: string,
	Scale: UIScale?, -- UIScale am Label (falls vorhanden): ploppt bei Zuwachs kurz auf
	Color: Color3, -- eigentliche Schriftfarbe (Farbblitz kehrt dahin zurück)
	PopAt: number,
}

local counters: { Counter } = {}
local counterClock = 0

function UI.Counter(target: TextLabel, format: (number) -> string): Counter
	local counter: Counter = {
		Label = target,
		Format = format,
		Target = 0,
		Shown = 0,
		Text = format(0),
		Scale = target:FindFirstChildOfClass("UIScale"),
		Color = target.TextColor3,
		PopAt = 0,
	}
	target.Text = counter.Text
	table.insert(counters, counter)
	-- Label zerstört: Zähler aus der Liste nehmen (sonst wächst sie mit jedem neu gebauten Fenster)
	target.Destroying:Once(function()
		local index = table.find(counters, counter)
		if index then
			table.remove(counters, index)
		end
	end)
	return counter
end

-- Kurzer Farbblitz (Up bei Zuwachs, Down bei Abnahme) + Aufploppen bei Zuwachs
local function popCounter(counter: Counter, up: boolean)
	local now = os.clock()
	if now - counter.PopAt < COUNTER_POP_GAP then
		return
	end
	counter.PopAt = now
	local label = counter.Label
	label.TextColor3 = counter.Color
	TweenService:Create(label, COUNTER_FLASH_INFO, { TextColor3 = if up then UI.UpColor() else UI.DownColor() }):Play()
	local scale = counter.Scale
	if up and scale then
		UI.Pulse(scale, 0.08)
	end
end

-- instant = true: sofort anzeigen (z.B. beim ersten Laden)
function UI.SetCounter(counter: Counter, value: number, instant: boolean?)
	if type(value) ~= "number" or value ~= value then
		return
	end
	if not instant and value ~= counter.Target then
		popCounter(counter, value > counter.Target)
	end
	counter.Target = value
	if instant then
		counter.Shown = value
		UI.RedrawCounter(counter)
	end
end

-- Schreibt den Text sofort neu (z.B. wenn sich das Format/die Sprache geändert hat)
function UI.RedrawCounter(counter: Counter)
	local text = counter.Format(counter.Shown)
	counter.Text = text
	counter.Label.Text = text
end

local function stepCounters(dt: number)
	counterClock += dt
	if counterClock < COUNTER_INTERVAL then
		return
	end
	local alpha = 1 - math.exp(-counterClock * 7)
	counterClock = 0
	for _, counter in ipairs(counters) do
		local target = counter.Target
		if counter.Shown ~= target then
			local diff = target - counter.Shown
			if math.abs(diff) <= math.max(0.5, math.abs(target) * 0.0002) then
				counter.Shown = target
			else
				counter.Shown += diff * alpha
			end
			local text = counter.Format(counter.Shown)
			if text ~= counter.Text then
				counter.Text = text
				counter.Label.Text = text
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- FENSTER + BOTTOM-SHEETS (immer nur eins offen; Glas-Panel, Titel in BuilderExtended, schlichtes ✕)
-- Der Inhalt steckt nur WÄHREND des Auf-/Zugehens in einer CanvasGroup (für das weiche Einblenden).
-- Danach hängt er in einem normalen Frame: Eine CanvasGroup malt bei jeder kleinen Änderung
-- (Text, Balken, Scrollen) ihren ganzen Inhalt neu und macht Schrift auf Handys unscharf (REUSE §7 #34).
-- ---------------------------------------------------------------------
export type Window = {
	Group: Frame, -- Halter (Position, Größe, sichtbar ja/nein)
	Fader: CanvasGroup, -- nur während der Animation benutzt
	Panel: Frame, -- der eigentliche Fensterinhalt
	Shadow: Frame, -- weicher Schatten hinter dem Panel (wandert mit in die CanvasGroup)
	Scale: UIScale,
	Content: ScrollingFrame,
	IsOpen: boolean,
	Token: number,
	OnOpen: (() -> ())?,
	OnClose: (() -> ())?,
	Title: string,
	Kind: string, -- "Window" | "Sheet"
	RestPos: UDim2, -- Position im offenen Zustand
	HiddenPos: UDim2, -- Startposition beim Öffnen / Ziel beim Schließen
	TitleLabel: TextLabel,
}

-- Registrierte Fenster (§C7.3): Name -> öffnen/schließen. Ein UI.Window, das während open() aufgeht,
-- wird automatisch mit dem Namen verknüpft (dann meldet auch das ✕ das Schließen richtig).
type WindowEntry = {
	Name: string,
	OpenFn: () -> (),
	CloseFn: (() -> ())?,
	Win: Window?,
	Flag: boolean, -- offen (für Fenster ohne verknüpftes UI.Window, z. B. das Terminal)
	Announced: boolean, -- "WindowOpened" schon gefeuert
}

local windows: { Window } = {}
local registry: { [string]: WindowEntry } = {}
local entryOfWin: { [Window]: WindowEntry } = {}
local openingName: string? = nil
local warnedUnknown: { [string]: boolean } = {}
local blur: BlurEffect? = nil
local modalButton: TextButton? = nil

local function entryIsOpen(entry: WindowEntry): boolean
	local win = entry.Win
	if win then
		return win.IsOpen
	end
	return entry.Flag
end

-- true, sobald irgendein Fenster offen ist (UI.Window/Sheet oder registriertes Fremd-Fenster)
function UI.IsAnyWindowOpen(): boolean
	for _, win in ipairs(windows) do
		if win.IsOpen then
			return true
		end
	end
	for _, entry in pairs(registry) do
		if entryIsOpen(entry) then
			return true
		end
	end
	return false
end

-- Welt hinter offenen Fenstern weichzeichnen (lokaler BlurEffect, nach dem Schließen wieder weg)
-- + Modal-Knopf: solange ein Fenster offen ist, gibt er die Maus frei (auch bei Shift-Lock)
local function updateWindowState()
	local open = UI.IsAnyWindowOpen()
	local modal = modalButton
	if modal and modal.Visible ~= open then
		modal.Visible = open
	end
	if open then
		UserInputService.MouseIconEnabled = true
		local effect = blur
		if not effect or effect.Parent == nil then
			effect = UI.Create("BlurEffect", { Name = "AkytexTycoonWindowBlur", Size = 0, Parent = Lighting })
			blur = effect
		end
		if effect then
			TweenService:Create(effect, BLUR_IN_INFO, { Size = BLUR_SIZE }):Play()
		end
	else
		local effect = blur
		if not effect then
			return
		end
		local fade = TweenService:Create(effect, BLUR_OUT_INFO, { Size = 0 })
		fade.Completed:Once(function()
			-- inzwischen wieder ein Fenster offen? Dann bleibt er
			if blur == effect and not UI.IsAnyWindowOpen() then
				blur = nil
				effect:Destroy()
			end
		end)
		fade:Play()
	end
end

-- Zustand eines registrierten Fensters setzen und die Hooks genau einmal pro Wechsel feuern
local function announceEntry(entry: WindowEntry)
	local open = entryIsOpen(entry)
	if open and not entry.Announced then
		entry.Announced = true
		fireHook("WindowOpened", entry.Name)
	elseif not open and entry.Announced then
		entry.Announced = false
		fireHook("WindowClosed", entry.Name)
	end
end

-- Inhalt (+ Schatten) für die Animation in die CanvasGroup hängen
local function beginFade(win: Window)
	if win.Panel.Parent ~= win.Fader then
		win.Shadow.Parent = win.Fader
		win.Panel.Parent = win.Fader
	end
	win.Fader.Visible = true
end

-- Animation fertig: Inhalt zurück in den normalen Frame, CanvasGroup aus
local function endFade(win: Window)
	win.Shadow.Parent = win.Group
	win.Panel.Parent = win.Group
	win.Fader.Visible = false
end

function UI.CloseWindow(win: Window)
	if not win.IsOpen then
		return
	end
	win.IsOpen = false
	win.Token += 1
	local token = win.Token
	beginFade(win)
	local sheet = win.Kind == "Sheet"
	local info = if sheet then SHEET_CLOSE_INFO else CLOSE_INFO
	if not sheet then
		TweenService:Create(win.Scale, CLOSE_INFO, { Scale = 0.97 }):Play()
	end
	TweenService:Create(win.Group, info, { Position = win.HiddenPos }):Play()
	local fade = TweenService:Create(win.Fader, info, { GroupTransparency = 1 })
	fade.Completed:Connect(function()
		if win.Token == token then
			win.Group.Visible = false
			endFade(win)
		end
	end)
	fade:Play()
	local entry = entryOfWin[win]
	if entry then
		announceEntry(entry)
	else
		fireHook("WindowClosed", win.Title)
	end
	updateWindowState()
	local onClose = win.OnClose
	if onClose then
		task.spawn(onClose)
	end
end

-- Registrierte Fremd-Fenster (ohne UI.Window) schließen, wenn ein anderes Fenster aufgeht
local function closeOtherEntries(except: WindowEntry?)
	for _, entry in pairs(registry) do
		if entry ~= except and entry.Win == nil and entry.Flag then
			entry.Flag = false
			local closeFn = entry.CloseFn
			if closeFn then
				local ok, err = pcall(closeFn)
				if not ok then
					warn("[UI] Fenster " .. entry.Name .. " schließen: " .. tostring(err))
				end
			end
			announceEntry(entry)
		end
	end
end

function UI.OpenWindow(win: Window)
	-- Wird das Fenster gerade über Windows.Open(name) geöffnet? Dann mit dem Namen verknüpfen.
	local pending = openingName
	if pending and not entryOfWin[win] then
		local entry = registry[pending]
		if entry and entry.Win == nil then
			entry.Win = win
			entry.Flag = false
			entryOfWin[win] = entry
		end
	end
	for _, other in ipairs(windows) do
		if other ~= win then
			UI.CloseWindow(other)
		end
	end
	closeOtherEntries(entryOfWin[win])
	if win.IsOpen then
		return
	end
	win.IsOpen = true
	win.Token += 1
	local token = win.Token
	beginFade(win)
	local sheet = win.Kind == "Sheet"
	if not win.Group.Visible then
		win.Fader.GroupTransparency = 1
		win.Scale.Scale = if sheet then 1 else 0.96
		win.Group.Position = win.HiddenPos
		win.Group.Visible = true
	end
	local fade = TweenService:Create(win.Fader, OPEN_FADE_INFO, { GroupTransparency = 0 })
	fade.Completed:Connect(function()
		if win.Token == token and win.IsOpen then
			endFade(win)
		end
	end)
	fade:Play()
	-- weich aufgehen (Quint Out, kein Überschwingen) und ein paar Pixel von unten hereingleiten
	if sheet then
		TweenService:Create(win.Group, SHEET_OPEN_INFO, { Position = win.RestPos }):Play()
	else
		TweenService:Create(win.Scale, OPEN_SCALE_INFO, { Scale = 1 }):Play()
		TweenService:Create(win.Group, OPEN_SCALE_INFO, { Position = win.RestPos }):Play()
	end
	local entry = entryOfWin[win]
	if entry then
		announceEntry(entry)
	else
		fireHook("WindowOpened", win.Title)
	end
	updateWindowState()
	if win.OnOpen then
		task.spawn(win.OnOpen)
	end
end

function UI.ToggleWindow(win: Window)
	if win.IsOpen then
		UI.CloseWindow(win)
	else
		UI.OpenWindow(win)
	end
end

function UI.CloseAll()
	for _, win in ipairs(windows) do
		UI.CloseWindow(win)
	end
	closeOtherEntries(nil)
	updateWindowState()
end

-- Gemeinsamer Aufbau von Fenster und Sheet
local function buildWindow(title: string, width: number, height: number, color: Color3?, kind: string): Window
	assert(root, "UI.Init zuerst aufrufen")
	local accent = accentOf(color)
	local sheet = kind == "Sheet"
	local restPos = if sheet then UDim2.new(0.5, 0, 1, WINDOW_PAD) else UDim2.fromScale(0.5, 0.5)
	local hiddenPos = if sheet
		then UDim2.new(0.5, 0, 1, height + WINDOW_PAD * 2)
		else UDim2.new(0.5, 0, 0.5, WINDOW_SLIDE)
	local group: Frame = UI.Create("Frame", {
		Name = if sheet then "Sheet" else "Window",
		AnchorPoint = if sheet then Vector2.new(0.5, 1) else Vector2.new(0.5, 0.5),
		Position = hiddenPos,
		Size = if sheet then UDim2.new(1, 0, 0, height + WINDOW_PAD) else UDim2.fromOffset(width, height),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 10,
		Parent = root,
	})
	if sheet then
		UI.Create("UISizeConstraint", { MaxSize = Vector2.new(SHEET_MAX_WIDTH, math.huge), Parent = group })
	end
	local scale: UIScale = UI.Create("UIScale", { Scale = if sheet then 1 else 0.96, Parent = group })
	local fader: CanvasGroup = UI.Create("CanvasGroup", {
		Name = "Fader",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Visible = false,
		Parent = group,
	})
	-- weicher Schatten: zwei dunkle Flächen hinter dem Panel (leicht versetzt nach unten)
	local shadow: Frame = UI.Create("Frame", {
		Name = "Shadow",
		Position = UDim2.fromOffset(WINDOW_PAD - 4, WINDOW_PAD),
		Size = UDim2.new(1, -WINDOW_PAD * 2 + 8, 1, -WINDOW_PAD * 2 + 6),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = group,
	}, { UI.Corner(20) })
	UI.Create("Frame", {
		Name = "Soft",
		Position = UDim2.fromOffset(-4, -2),
		Size = UDim2.new(1, 8, 1, 8),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = shadow,
	}, { UI.Corner(24) })
	local panel: Frame = UI.Create("Frame", {
		Name = "Panel",
		Position = UDim2.fromOffset(WINDOW_PAD, WINDOW_PAD),
		Size = UDim2.new(1, -WINDOW_PAD * 2, 1, -WINDOW_PAD * 2),
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = group,
	}, { UI.Corner(if sheet then 20 else 16), UI.Stroke(nil, 1) })
	local headerTop = if sheet then 10 else 0
	local header: Frame = UI.Create("Frame", {
		Name = "Header",
		Position = UDim2.fromOffset(0, headerTop),
		Size = UDim2.new(1, 0, 0, WINDOW_HEADER),
		BackgroundTransparency = 1,
		Active = sheet, -- Sheet: der Kopf ist die Zieh-Fläche
		Parent = panel,
	})
	if sheet then
		-- Greifer oben in der Mitte (wie iOS-Bottom-Sheets der Website)
		UI.Create("Frame", {
			Name = "Grabber",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 7),
			Size = UDim2.fromOffset(40, 4),
			BackgroundColor3 = Theme.Muted,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Parent = panel,
		}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	end
	-- Titel in GROSSBUCHSTABEN (BuilderExtended, 18–22 px)
	local titleLabel = UI.Label({
		Name = "Title",
		Position = UDim2.fromOffset(20, 12),
		Size = UDim2.new(1, -84, 0, 26),
		Text = UI.Upper(title),
		Face = "Display",
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 20,
		Parent = header,
	})
	UI.Create("Frame", {
		Name = "Underline",
		Position = UDim2.fromOffset(20, 42),
		Size = UDim2.fromOffset(28, 2),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Parent = header,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	UI.Create("Frame", {
		Name = "Divider",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Theme.Border,
		BorderSizePixel = 0,
		Parent = header,
	})
	local contentTop = headerTop + WINDOW_HEADER + 10
	local content: ScrollingFrame = UI.Create("ScrollingFrame", {
		Name = "Content",
		Position = UDim2.fromOffset(16, contentTop),
		Size = UDim2.new(1, -24, 1, -(contentTop + 10 + (if sheet then WINDOW_PAD else 0))),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Muted,
		ScrollBarImageTransparency = 0.3,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = panel,
	}, {
		UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
		UI.Create("UIPadding", {
			PaddingLeft = UDim.new(0, 2),
			PaddingRight = UDim.new(0, 12),
			PaddingTop = UDim.new(0, 2),
			PaddingBottom = UDim.new(0, 12),
		}),
	})
	local win: Window = {
		Group = group,
		Fader = fader,
		Panel = panel,
		Shadow = shadow,
		Scale = scale,
		Content = content,
		IsOpen = false,
		Token = 0,
		OnOpen = nil,
		OnClose = nil,
		Title = title,
		Kind = kind,
		RestPos = restPos,
		HiddenPos = hiddenPos,
		TitleLabel = titleLabel,
	}
	-- Schließen: schlichtes ✕ (Ghost-Knopf, Hover = Hover-Fläche)
	UI.Button({
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 11),
		Size = UDim2.fromOffset(36, 36),
		Text = "✕",
		Variant = "Ghost",
		MaxText = 18,
		Corner = 10,
		Parent = header,
	}, function()
		local entry = entryOfWin[win]
		if entry and ctx and ctx.Windows then
			ctx.Windows.Close(entry.Name)
		else
			UI.CloseWindow(win)
		end
	end)
	if sheet then
		-- Nach unten ziehen schließt das Sheet (Touch und Maus), sonst federt es zurück
		local dragInput: InputObject? = nil
		local dragStart = 0
		local dragConn: RBXScriptConnection? = nil
		local endConn: RBXScriptConnection? = nil
		local function stopDrag(closeIt: boolean)
			dragInput = nil
			if dragConn then
				dragConn:Disconnect()
				dragConn = nil
			end
			if endConn then
				endConn:Disconnect()
				endConn = nil
			end
			if not win.IsOpen then
				return
			end
			if closeIt then
				local entry = entryOfWin[win]
				if entry and ctx and ctx.Windows then
					ctx.Windows.Close(entry.Name)
				else
					UI.CloseWindow(win)
				end
			else
				TweenService:Create(group, SHEET_OPEN_INFO, { Position = win.RestPos }):Play()
			end
		end
		header.InputBegan:Connect(function(input: InputObject)
			local kindIn = input.UserInputType
			if dragInput or not win.IsOpen then
				return
			end
			if kindIn ~= Enum.UserInputType.Touch and kindIn ~= Enum.UserInputType.MouseButton1 then
				return
			end
			dragInput = input
			dragStart = input.Position.Y
			dragConn = UserInputService.InputChanged:Connect(function(changed: InputObject)
				local active = dragInput
				if not active then
					return
				end
				local follows = changed == active
					or (
						active.UserInputType == Enum.UserInputType.MouseButton1
						and changed.UserInputType == Enum.UserInputType.MouseMovement
					)
				if not follows then
					return
				end
				local delta = math.max(0, (changed.Position.Y - dragStart) / UI.ScaleOf(group))
				group.Position = UDim2.new(0.5, 0, 1, WINDOW_PAD + delta)
			end)
			endConn = UserInputService.InputEnded:Connect(function(ended: InputObject)
				if ended ~= dragInput then
					return
				end
				local delta = (ended.Position.Y - dragStart) / UI.ScaleOf(group)
				stopDrag(delta >= SHEET_DRAG_CLOSE)
			end)
		end)
	end
	table.insert(windows, win)
	return win
end

-- Glas-Fenster: Surface (Transparenz 0.08), Ecke 16, 1-px-Border, weicher Schatten dahinter,
-- Kopf mit Titel (BuilderExtended, GROSS) + Akzent-Unterstrich und schlichtem ✕ rechts.
function UI.Window(title: string, width: number, height: number, color: Color3?): Window
	return buildWindow(title, width, height, color, "Window")
end

-- Bottom-Sheet (Handy-Stil der Website): volle Breite (≤ 760 px), gleitet von unten herein,
-- Greifer + Ziehen nach unten schließt. Gleiche Fenster-Regeln (immer nur eins offen, Blur, Hooks).
function UI.Sheet(title: string, height: number): Window
	local h = math.clamp(tonumber(height) or 420, 160, 900)
	return buildWindow(title, SHEET_MAX_WIDTH, h, nil, "Sheet")
end

-- ---------------------------------------------------------------------
-- WINDOWS-REGISTRY (§C7.3) = ctx.Windows
-- Fensternamen (frozen): Terminal, Tower, Shop, Quests, Academy, Season, Boards, Social, Garage, Boutique,
-- Prestige, Settings, Admin, Calendar, WelcomeBack. Immer nur ein Fenster offen.
-- ---------------------------------------------------------------------
local Windows = {}
UI.Windows = Windows

function Windows.Register(name: string, open: () -> (), close: (() -> ())?)
	if type(name) ~= "string" or type(open) ~= "function" then
		warn("[UI] Windows.Register: Name (string) und open-Funktion erwartet")
		return
	end
	local old = registry[name]
	if old and old.Win then
		entryOfWin[old.Win] = nil
	end
	registry[name] = { Name = name, OpenFn = open, CloseFn = close, Win = nil, Flag = false, Announced = false }
end

function Windows.IsOpen(name: string?): boolean
	if name == nil then
		return UI.IsAnyWindowOpen()
	end
	local entry = registry[name]
	return entry ~= nil and entryIsOpen(entry)
end

function Windows.Close(name: string?)
	if name == nil then
		for _, entry in pairs(registry) do
			Windows.Close(entry.Name)
		end
		UI.CloseAll()
		return
	end
	local entry = registry[name]
	if not entry or not entryIsOpen(entry) then
		return
	end
	local closeFn = entry.CloseFn
	if closeFn then
		local ok, err = pcall(closeFn)
		if not ok then
			warn("[UI] Fenster " .. name .. " schließen: " .. tostring(err))
		end
	end
	local win = entry.Win
	if win and win.IsOpen then
		UI.CloseWindow(win)
	end
	entry.Flag = false
	announceEntry(entry)
	updateWindowState()
end

function Windows.Open(name: string)
	local entry = registry[name]
	if not entry then
		if not warnedUnknown[name] then
			warnedUnknown[name] = true
			warn("[UI] Fenster nicht registriert: " .. tostring(name))
		end
		return
	end
	-- andere registrierte Fenster zu (nur eins gleichzeitig)
	for _, other in pairs(registry) do
		if other ~= entry and entryIsOpen(other) then
			Windows.Close(other.Name)
		end
	end
	-- auch unregistrierte UI.Window/Sheets (z. B. Multiplikator-Aufschlüsselung) schließen
	for _, win in ipairs(windows) do
		if win.IsOpen and not entryOfWin[win] then
			UI.CloseWindow(win)
		end
	end
	openingName = name
	local ok, err = pcall(entry.OpenFn)
	openingName = nil
	if not ok then
		warn("[UI] Fenster " .. name .. " öffnen: " .. tostring(err))
		return
	end
	if entry.Win == nil then
		entry.Flag = true -- Fremd-Fenster ohne UI.Window: offen, bis Windows.Close(name) kommt
	end
	announceEntry(entry)
	updateWindowState()
end

function Windows.Toggle(name: string)
	if Windows.IsOpen(name) then
		Windows.Close(name)
	else
		Windows.Open(name)
	end
end

-- ---------------------------------------------------------------------
-- TOASTS: schlanke Pill oben in der Mitte (Surface + 1-px-Rahmen, farbiger Punkt je Art),
-- gleitet 8 px herein und blendet aus; gestapelt (neueste unten). Normale Frames + kleiner Vorrat.
-- ---------------------------------------------------------------------
type ToastEntry = {
	Container: Frame, -- Platzhalter in der Liste (wächst/schrumpft -> andere rutschen weich nach)
	Inner: Frame, -- die Pill; bewegt sich, ohne die Liste zu verschieben
	Corner: UICorner,
	Stroke: UIStroke,
	Dot: Frame,
	Label: TextLabel,
	Height: number,
	Leaving: boolean,
	Token: number,
	Kind: string,
}

-- Punkt-Farbe je Art (Info/Ansage = Accent, Erfolg = Up, Fehler/Alarm = Down, Event = Warn)
local TOAST_DOTS: { [string]: Color3 } = {
	Info = Theme.Accent,
	Success = Theme.Up,
	Error = Theme.Down,
	Event = Theme.Warn,
	Alarm = Theme.Down,
	Announce = Theme.Accent,
}

-- Rahmen je Art (wichtige Meldungen mit farbigem Rahmen)
local TOAST_STROKES: { [string]: Color3 } = {
	Alarm = Theme.Down,
	Announce = Theme.Accent,
}

-- Schriftgröße je Art (Alarm etwas größer)
local TOAST_TEXT_SIZE: { [string]: number } = {
	Info = 17,
	Success = 17,
	Error = 17,
	Event = 17,
	Announce = 18,
	Alarm = 19,
}

-- Zu viele Toasts: zuerst fliegt der älteste mit der KLEINSTEN Wichtigkeit raus.
local TOAST_PRIORITY: { [string]: number } = {
	Info = 1,
	Event = 1,
	Success = 2,
	Error = 2,
	Announce = 2,
	Alarm = 3,
}

local TOAST_BG_T = 0.04 -- Pill fast deckend
local toastHolder: Frame? = nil
local TOAST_TOP = 14 -- Meldungen stehen so weit unter dem oberen Rand
local toastCount = 0
local activeToasts: { ToastEntry } = {}
local toastPool: { ToastEntry } = {}

-- Position der Pill im Platzhalter (oben Mitte; offsetY < 0 = darüber)
local function toastPosition(offsetY: number): UDim2
	return UDim2.new(0.5, 0, 0, offsetY)
end

local function newToastEntry(): ToastEntry
	local container: Frame = UI.Create("Frame", {
		Name = "Toast",
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
	})
	local corner: UICorner = UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) })
	local stroke: UIStroke = UI.Create("UIStroke", {
		Color = Theme.Border,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
	local inner: Frame = UI.Create("Frame", {
		Name = "Inner",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(200, TOAST_MIN_HEIGHT),
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = TOAST_BG_T,
		BorderSizePixel = 0,
		Parent = container,
	}, { corner, stroke })
	local dot: Frame = UI.Create("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, TOAST_PAD_X, 0.5, 0),
		Size = UDim2.fromOffset(TOAST_DOT, TOAST_DOT),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Parent = inner,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local label: TextLabel = UI.Create("TextLabel", {
		Name = "Text",
		Position = UDim2.fromOffset(TOAST_PAD_X + TOAST_DOT + TOAST_DOT_GAP, 0),
		Size = UDim2.new(1, -(TOAST_PAD_X * 2 + TOAST_DOT + TOAST_DOT_GAP), 1, 0),
		BackgroundTransparency = 1,
		Font = UI.Fonts.Main,
		TextColor3 = Theme.Text,
		TextSize = 17,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		Parent = inner,
	})
	return {
		Container = container,
		Inner = inner,
		Corner = corner,
		Stroke = stroke,
		Dot = dot,
		Label = label,
		Height = TOAST_MIN_HEIGHT,
		Leaving = false,
		Token = 0,
		Kind = "Info",
	}
end

-- Welcher Toast soll weichen? Der älteste mit der kleinsten Wichtigkeit.
local function toastToDrop(): ToastEntry
	local drop = activeToasts[1]
	local lowest = math.huge
	for _, entry in ipairs(activeToasts) do
		local priority = TOAST_PRIORITY[entry.Kind] or 1
		if priority < lowest then
			drop, lowest = entry, priority
		end
	end
	return drop
end

-- Ein-/Ausblenden (Pill, Rahmen, Punkt, Text). shown = sichtbar. Gibt den Tween des Texts zurück.
local function fadeToast(entry: ToastEntry, info: TweenInfo, shown: boolean): Tween
	TweenService:Create(entry.Inner, info, { BackgroundTransparency = if shown then TOAST_BG_T else 1 }):Play()
	TweenService:Create(entry.Stroke, info, { Transparency = if shown then 0 else 1 }):Play()
	TweenService:Create(entry.Dot, info, { BackgroundTransparency = if shown then 0 else 1 }):Play()
	local textTween = TweenService:Create(entry.Label, info, { TextTransparency = if shown then 0 else 1 })
	textTween:Play()
	return textTween
end

local function hideToastNow(entry: ToastEntry)
	entry.Inner.BackgroundTransparency = 1
	entry.Stroke.Transparency = 1
	entry.Dot.BackgroundTransparency = 1
	entry.Label.TextTransparency = 1
end

local function removeToast(entry: ToastEntry)
	if entry.Leaving then
		return
	end
	entry.Leaving = true
	local token = entry.Token
	local index = table.find(activeToasts, entry)
	if index then
		table.remove(activeToasts, index)
	end
	-- gleitet etwas hoch und blendet aus, danach rutschen die anderen nach
	TweenService:Create(entry.Inner, TOAST_OUT_INFO, { Position = toastPosition(-TOAST_SLIDE * 0.75) }):Play()
	local fade = fadeToast(entry, TOAST_OUT_INFO, false)
	fade.Completed:Connect(function()
		if entry.Token ~= token then
			return
		end
		local shrink = TweenService:Create(entry.Container, TOAST_GROW_INFO, { Size = UDim2.new(1, 0, 0, 0) })
		shrink.Completed:Connect(function()
			if entry.Token ~= token then
				return
			end
			-- fertig -> aufheben und später wiederverwenden
			entry.Container.Parent = nil
			if #toastPool < MAX_TOAST_POOL then
				table.insert(toastPool, entry)
			else
				entry.Container:Destroy()
			end
		end)
		shrink:Play()
	end)
end

-- Meldungen tiefer setzen, solange oben etwas anderes steht (Ticker-Leiste, Pillen, Terminal-Kopf).
-- nil = wieder an die normale Stelle.
function UI.SetToastTop(offset: number?)
	local holder = toastHolder
	if holder then
		local y = if type(offset) == "number" and offset == offset then math.clamp(offset, 0, 600) else TOAST_TOP
		holder.Position = UDim2.new(0.5, 0, 0, y)
	end
end

function UI.Toast(text: string, kind: string?)
	local holder = toastHolder
	if not holder or type(text) ~= "string" or text == "" then
		return
	end
	toastCount += 1
	local key = if kind and TOAST_DOTS[kind] then kind else "Info"
	local entry = table.remove(toastPool) or newToastEntry()
	entry.Token += 1
	entry.Leaving = false
	entry.Kind = key
	local token = entry.Token
	-- Größe passend zum Text: kurze Meldungen = schmale Pill, lange brechen um (dann Ecke 14)
	local textSize = TOAST_TEXT_SIZE[key] or 17
	local chrome = TOAST_PAD_X * 2 + TOAST_DOT + TOAST_DOT_GAP
	local maxText = TOAST_WIDTH - chrome
	local bounds = TextService:GetTextSize(text, textSize, UI.Fonts.Main, Vector2.new(maxText, 1000))
	local width = math.min(TOAST_WIDTH, math.ceil(bounds.X) + chrome + 2)
	local height = math.max(TOAST_MIN_HEIGHT, math.ceil(bounds.Y) + 16)
	local multiLine = bounds.Y > textSize * 1.6
	entry.Height = height
	entry.Label.Text = text
	entry.Label.TextSize = textSize
	entry.Label.TextColor3 = Theme.Text
	entry.Dot.BackgroundColor3 = TOAST_DOTS[key]
	entry.Stroke.Color = TOAST_STROKES[key] or Theme.Border
	entry.Corner.CornerRadius = if multiLine then UDim.new(0, 14) else UDim.new(0.5, 0)
	entry.Inner.Size = UDim2.fromOffset(width, height)
	entry.Inner.Position = toastPosition(-TOAST_SLIDE)
	entry.Container.Size = UDim2.new(1, 0, 0, 0)
	entry.Container.LayoutOrder = toastCount
	hideToastNow(entry)
	entry.Container.Parent = holder
	table.insert(activeToasts, entry)
	TweenService:Create(entry.Container, TOAST_GROW_INFO, { Size = UDim2.new(1, 0, 0, height + TOAST_GAP) }):Play()
	TweenService:Create(entry.Inner, TOAST_IN_INFO, { Position = toastPosition(0) }):Play()
	fadeToast(entry, TOAST_IN_INFO, true)
	while #activeToasts > MAX_TOASTS do
		removeToast(toastToDrop())
	end
	if key == "Error" or key == "Alarm" then
		playUiSound("UIError")
	end
	task.delay((key == "Announce" or key == "Event") and 7 or 4, function()
		if entry.Token == token then
			removeToast(entry)
		end
	end)
end

-- ---------------------------------------------------------------------
-- PREISE (Robux) aus dem Marktplatz – einmal laden, dann merken (Id 0 = nicht eingerichtet -> nil)
-- ---------------------------------------------------------------------
local priceCache: { [number]: number } = {}
local priceWaiting: { [number]: { (number?) -> () } } = {}

function UI.FetchPrice(id: number, infoType: Enum.InfoType, callback: (number?) -> ())
	if type(id) ~= "number" or id == 0 then
		task.spawn(callback, nil)
		return
	end
	local cached = priceCache[id]
	if cached then
		task.spawn(callback, cached)
		return
	end
	local waiting = priceWaiting[id]
	if waiting then
		table.insert(waiting, callback)
		return
	end
	priceWaiting[id] = { callback }
	task.spawn(function()
		local ok, info = pcall(MarketplaceService.GetProductInfoAsync, MarketplaceService, id, infoType)
		local price = if ok and type(info) == "table" then tonumber(info.PriceInRobux) else nil
		if price then
			priceCache[id] = price
		end
		local list = priceWaiting[id] or {}
		priceWaiting[id] = nil
		for _, cb in ipairs(list) do
			task.spawn(cb, price)
		end
	end)
end

-- ---------------------------------------------------------------------
-- LÄNDER-REGEL "Paid Random Items" (fail-closed, für spätere Produkte): Server-State "RandomAllowed",
-- nach 30 s ohne Server-Wert PolicyService selbst fragen. Im Zweifel/bei Fehler: NICHT erlaubt.
-- ---------------------------------------------------------------------
local randomAllowed: boolean? = nil
local randomWaiting: { (boolean) -> () } = {}
local randomStarted = false

local function resolveRandom(allowed: boolean)
	randomAllowed = allowed
	if #randomWaiting == 0 then
		return
	end
	local waiting = randomWaiting
	randomWaiting = {}
	for _, cb in ipairs(waiting) do
		task.spawn(cb, allowed)
	end
end

local function stateRandom(): boolean?
	local state = ctx and ctx.State
	if type(state) == "table" and type(state.RandomAllowed) == "boolean" then
		return state.RandomAllowed
	end
	return nil
end

function UI.WhenRandomItemsKnown(callback: (allowed: boolean) -> ())
	local known = stateRandom()
	if known ~= nil then
		randomAllowed = known
	end
	if randomAllowed ~= nil then
		task.spawn(callback, randomAllowed)
		return
	end
	table.insert(randomWaiting, callback)
	if randomStarted then
		return
	end
	randomStarted = true
	task.delay(RANDOM_STATE_WAIT, function()
		if randomAllowed ~= nil then
			return
		end
		local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, Players.LocalPlayer)
		if randomAllowed == nil then
			resolveRandom(ok and type(info) == "table" and info.ArePaidRandomItemsRestricted == false)
		end
	end)
end

-- true/false, oder nil solange die Antwort noch nicht da ist
function UI.RandomItemsAllowed(): boolean?
	local known = stateRandom()
	if known ~= nil then
		return known
	end
	return randomAllowed
end

-- =====================================================================
-- AT-NEUTEILE (§C7.5, REUSE §4.10/§4.11)
-- =====================================================================

-- ---------------------------------------------------------------------
-- WÄHRUNGS-SYMBOLE (DESIGN §0.1): CR = grüner Sechskant-Chip, AKY = blaue Münze mit „Λ“ – nur Frames, keine Bilder
-- ---------------------------------------------------------------------
local function hexagon(parent: Instance, color: Color3, scale: number, z: number): Frame
	local holder: Frame = UI.Create("Frame", {
		Name = "Hex",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(scale, scale),
		BackgroundTransparency = 1,
		ZIndex = z,
		Parent = parent,
	})
	-- drei gedrehte Rechtecke (Breite W, Höhe W·tan30°) ergeben zusammen ein regelmäßiges Sechseck
	for _, rotation in ipairs({ 0, 60, 120 }) do
		UI.Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.866, 0.5),
			Rotation = rotation,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = z,
			Parent = holder,
		})
	end
	return holder
end

function UI.CurrencyIcon(parent: Instance, kind: string, size: number?): Frame
	local px = math.clamp(tonumber(size) or 20, 8, 128)
	local icon: Frame = UI.Create("Frame", {
		Name = "Currency" .. tostring(kind),
		Size = UDim2.fromOffset(px, px),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local z = 2
	if parent:IsA("GuiObject") then
		z = parent.ZIndex + 1
	end
	icon.ZIndex = z
	if kind == "AKY" then
		local coin: Frame = UI.Create("Frame", {
			Name = "Coin",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.Accent,
			BorderSizePixel = 0,
			ZIndex = z,
			Parent = icon,
		}, {
			UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			UI.Create("UIStroke", {
				Color = Theme.Accent:Lerp(WHITE, 0.45),
				Thickness = 1,
				Transparency = 0.2,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
			UI.Gradient(Theme.Accent:Lerp(WHITE, 0.12), Theme.AccentDeep, 90),
		})
		-- „Λ“ aus zwei gedrehten Strichen (keine Schrift nötig)
		local strokes = { { 0.415, 0.5, -66.97 }, { 0.585, 0.5, 66.97 } }
		for _, spec in ipairs(strokes) do
			UI.Create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(spec[1], spec[2]),
				Size = UDim2.fromScale(0.44, 0.11),
				Rotation = spec[3],
				BackgroundColor3 = WHITE,
				BorderSizePixel = 0,
				ZIndex = z + 1,
				Parent = coin,
			}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		end
	else
		hexagon(icon, Theme.Up, 1, z)
		hexagon(icon, Theme.Up:Lerp(BLACK, 0.38), 0.62, z + 1)
		hexagon(icon, Theme.Up:Lerp(WHITE, 0.15), 0.34, z + 2)
	end
	return icon
end

-- ---------------------------------------------------------------------
-- SEGMENTED CONTROL (Zeitrahmen, Chart-Typ, Tabs): Bg2-Schiene, gleitende Markierung (0.22 s Quint Out)
-- options: { string } oder { { Key = string, Text = string } }. onChange(key) nur bei Benutzer-Klick.
-- ---------------------------------------------------------------------
export type Segmented = {
	Frame: Frame,
	Set: (key: string, silent: boolean?) -> (),
	Get: () -> string?,
}

function UI.Segmented(parent: Instance, options: { any }, onChange: ((key: string) -> ())?): Segmented
	local items: { { Key: string, Text: string } } = {}
	for _, option in ipairs(options or {}) do
		if type(option) == "string" then
			table.insert(items, { Key = option, Text = option })
		elseif type(option) == "table" and type(option.Key) == "string" then
			table.insert(items, { Key = option.Key, Text = tostring(option.Text or option.Key) })
		end
	end
	local count = math.max(1, #items)
	local frame: Frame = UI.Create("Frame", {
		Name = "Segmented",
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = Theme.Bg2,
		BorderSizePixel = 0,
		Parent = parent,
	}, { UI.Corner(10), UI.Stroke(nil, 1) })
	local marker: Frame = UI.Create("Frame", {
		Name = "Marker",
		Position = UDim2.new(0, 3, 0, 3),
		Size = UDim2.new(1 / count, -6, 1, -6),
		BackgroundColor3 = Theme.Surface2,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = frame,
	}, {
		UI.Corner(8),
		UI.Create("UIStroke", { Color = Theme.Accent, Thickness = 1, Transparency = 0.35 }),
	})
	local labels: { TextButton } = {}
	local selected: string? = if items[1] then items[1].Key else nil
	local function paint(instant: boolean)
		local index = 1
		for i, item in ipairs(items) do
			if item.Key == selected then
				index = i
			end
		end
		local goal = UDim2.new((index - 1) / count, 3, 0, 3)
		if instant then
			marker.Position = goal
		else
			TweenService:Create(marker, SEGMENT_INFO, { Position = goal }):Play()
		end
		for i, button in ipairs(labels) do
			local on = items[i] and items[i].Key == selected
			local label = button:FindFirstChild("Text")
			if label and label:IsA("TextLabel") then
				label.TextColor3 = if on then Theme.Text else Theme.Text2
			end
		end
	end
	for i, item in ipairs(items) do
		local button: TextButton = UI.Create("TextButton", {
			Name = item.Key,
			Position = UDim2.fromScale((i - 1) / count, 0),
			Size = UDim2.fromScale(1 / count, 1),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 2,
			Parent = frame,
		})
		UI.Label({
			Name = "Text",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -8, 0.56, 0),
			Text = item.Text,
			Face = "MonoBold",
			TextColor3 = Theme.Text2,
			MaxText = 15,
			ZIndex = 3,
			Parent = button,
		})
		button.Activated:Connect(function()
			if selected == item.Key then
				return
			end
			selected = item.Key
			playUiSound("UIClick")
			paint(false)
			if onChange then
				task.spawn(function()
					local ok, err = pcall(onChange, item.Key)
					if not ok then
						warn("[UI] Segmented: " .. tostring(err))
					end
				end)
			end
		end)
		table.insert(labels, button)
	end
	paint(true)
	return {
		Frame = frame,
		Set = function(key: string, _silent: boolean?)
			for _, item in ipairs(items) do
				if item.Key == key then
					if selected ~= key then
						selected = key
						paint(false)
					end
					return
				end
			end
		end,
		Get = function(): string?
			return selected
		end,
	}
end

-- ---------------------------------------------------------------------
-- PREIS-ETIKETT: "123,45  ▲ +2,35 %" (Preis in Text, Veränderung in Up/Down + Pfeil). Schreibt nur bei Änderung.
-- ---------------------------------------------------------------------
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

local function formatPct(fraction: number): string
	local format = ctx and ctx.Format
	if format and type(format.Pct) == "function" then
		local ok, text = pcall(format.Pct, fraction, langNow(), 2, true)
		if ok and type(text) == "string" then
			return text
		end
	end
	return string.format("%+.2f %%", fraction * 100)
end

function UI.PriceTag(label: TextLabel, cents: number, change: number?)
	if typeof(label) ~= "Instance" or not label:IsA("TextLabel") then
		return
	end
	local price = tonumber(cents)
	if not price or price ~= price then
		return
	end
	local text: string
	local delta = tonumber(change)
	if delta and delta == delta then
		local color = UI.ColorHex(UI.TrendColor(delta))
		text = string.format(
			'%s  <font color="%s">%s %s</font>',
			formatPrice(price),
			color,
			UI.TrendArrow(delta),
			formatPct(delta)
		)
	else
		text = formatPrice(price)
	end
	if not label.RichText then
		label.RichText = true
	end
	if label.Text ~= text then
		label.Text = text
	end
end

-- ---------------------------------------------------------------------
-- SPARKLINE (Mini-Linie): n-1 gepoolte Segment-Frames, Koordinaten aus dem Seitenverhältnis (skalierungsfest)
-- ---------------------------------------------------------------------
export type Sparkline = { Frame: Frame, Set: (points: { number }) -> () }

function UI.Sparkline(parent: Instance, n: number): Sparkline
	local slots = math.clamp(math.floor(tonumber(n) or 30), 2, MAX_SPARK_POINTS)
	local frame: Frame = UI.Create("Frame", {
		Name = "Sparkline",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = false,
		Parent = parent,
	})
	local segments: { Frame } = {}
	for i = 1, slots - 1 do
		segments[i] = UI.Create("Frame", {
			Name = "Seg",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.new(0, 0, 0, 1.5),
			BackgroundColor3 = Theme.Muted,
			BorderSizePixel = 0,
			Visible = false,
			Parent = frame,
		})
	end
	local points: { number } = {}
	local function render()
		local size = frame.AbsoluteSize
		local w, h = size.X, size.Y
		local m = math.min(#points, slots)
		if w < 2 or h < 2 or m < 2 then
			for _, seg in ipairs(segments) do
				if seg.Visible then
					seg.Visible = false
				end
			end
			return
		end
		local lo, hi = math.huge, -math.huge
		for i = 1, m do
			local v = points[i]
			if v < lo then
				lo = v
			end
			if v > hi then
				hi = v
			end
		end
		local range = hi - lo
		local color = if points[m] >= points[1] then UI.UpColor() else UI.DownColor()
		local function yOf(v: number): number
			if range <= 0 then
				return 0.5
			end
			return 0.92 - (v - lo) / range * 0.84
		end
		for i = 1, slots - 1 do
			local seg = segments[i]
			if i < m then
				local x1, x2 = (i - 1) / (m - 1), i / (m - 1)
				local y1, y2 = yOf(points[i]), yOf(points[i + 1])
				local dxPx, dyPx = (x2 - x1) * w, (y2 - y1) * h
				local length = math.sqrt(dxPx * dxPx + dyPx * dyPx)
				local position = UDim2.fromScale((x1 + x2) / 2, (y1 + y2) / 2)
				local sizeUdim = UDim2.new(length / w, 1, 0, 1.5)
				local rotation = math.deg(math.atan2(dyPx, dxPx))
				if seg.Position ~= position then
					seg.Position = position
				end
				if seg.Size ~= sizeUdim then
					seg.Size = sizeUdim
				end
				if math.abs(seg.Rotation - rotation) > 0.01 then
					seg.Rotation = rotation
				end
				if seg.BackgroundColor3 ~= color then
					seg.BackgroundColor3 = color
				end
				if not seg.Visible then
					seg.Visible = true
				end
			elseif seg.Visible then
				seg.Visible = false
			end
		end
	end
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(render)
	return {
		Frame = frame,
		Set = function(newPoints: { number })
			table.clear(points)
			if type(newPoints) == "table" then
				local start = math.max(1, #newPoints - slots + 1)
				for i = start, #newPoints do
					local v = tonumber(newPoints[i])
					if v and v == v and v ~= math.huge and v ~= -math.huge then
						table.insert(points, v)
					end
				end
			end
			render()
		end,
	}
end

-- ---------------------------------------------------------------------
-- LAUFBAND (Ticker): gepoolte RichText-Labels in einem ungedrehten Clip-Frame; je Frame wird nur der
-- Container verschoben, der erste Eintrag wandert ans Ende (O(1)). Maus darüber = Pause (wie die Website).
-- rows: { { Ticker = string, Price = number (Cent), Change = number (Anteil) } } oder { { Text = string } }
-- ---------------------------------------------------------------------
export type Ticker = {
	Frame: Frame,
	SetRows: (rows: { any }) -> (),
	SetSpeed: (pxPerSecond: number) -> (),
}

type TickerState = {
	Clip: Frame,
	Track: Frame,
	Labels: { TextLabel },
	Count: number,
	Offset: number,
	Speed: number,
	Paused: boolean,
	NextOrder: number,
	ScaleAt: number,
	Scale: number,
	Alive: boolean,
}

local tickers: { TickerState } = {}

local function tickerText(row: any): string
	if type(row) ~= "table" then
		return ""
	end
	if type(row.Text) == "string" then
		return row.Text
	end
	local ticker = tostring(row.Ticker or "?")
	local price = tonumber(row.Price)
	local change = tonumber(row.Change)
	local parts = { string.format('<font color="%s">%s</font>', UI.ColorHex(Theme.Text), ticker) }
	if price and price == price then
		table.insert(parts, string.format('<font color="%s">%s</font>', UI.ColorHex(Theme.Text2), formatPrice(price)))
	end
	if change and change == change then
		table.insert(
			parts,
			string.format(
				'<font color="%s">%s %s</font>',
				UI.ColorHex(UI.TrendColor(change)),
				UI.TrendArrow(change),
				formatPct(change)
			)
		)
	end
	return table.concat(parts, "  ")
end

function UI.Ticker(parent: Instance): Ticker
	local clip: Frame = UI.Create("Frame", {
		Name = "Ticker",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = parent,
	})
	local track: Frame = UI.Create("Frame", {
		Name = "Track",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = clip,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, TICKER_GAP),
		}),
	})
	local state: TickerState = {
		Clip = clip,
		Track = track,
		Labels = {},
		Count = 0,
		Offset = 0,
		Speed = TICKER_SPEED,
		Paused = false,
		NextOrder = 0,
		ScaleAt = -math.huge,
		Scale = 1,
		Alive = true,
	}
	clip.MouseEnter:Connect(function()
		state.Paused = true
	end)
	clip.MouseLeave:Connect(function()
		state.Paused = false
	end)
	table.insert(tickers, state)
	clip.Destroying:Once(function()
		state.Alive = false
		local index = table.find(tickers, state)
		if index then
			table.remove(tickers, index)
		end
	end)
	return {
		Frame = clip,
		SetRows = function(rows: { any })
			local list = if type(rows) == "table" then rows else {}
			local count = math.min(#list, TICKER_MAX_ROWS)
			for i = 1, count do
				local label = state.Labels[i]
				if not label then
					state.NextOrder += 1
					label = UI.Create("TextLabel", {
						Name = "Item",
						Size = UDim2.fromScale(0, 1),
						AutomaticSize = Enum.AutomaticSize.X,
						BackgroundTransparency = 1,
						FontFace = UI.Faces.Mono,
						TextSize = 14,
						RichText = true,
						TextColor3 = Theme.Text,
						Text = "",
						LayoutOrder = state.NextOrder,
						Parent = track,
					})
					state.Labels[i] = label
				end
				local text = tickerText(list[i])
				if label.Text ~= text then
					label.Text = text
				end
				if not label.Visible then
					label.Visible = true
				end
			end
			for i = count + 1, #state.Labels do
				local label = state.Labels[i]
				if label.Visible then
					label.Visible = false
				end
			end
			state.Count = count
		end,
		SetSpeed = function(pxPerSecond: number)
			local v = tonumber(pxPerSecond)
			if v and v == v then
				state.Speed = math.clamp(v, 0, 400)
			end
		end,
	}
end

local function stepTickers(dt: number)
	local now = os.clock()
	for _, state in ipairs(tickers) do
		if state.Alive and state.Count > 0 and not state.Paused and state.Speed > 0 then
			local clip = state.Clip
			if now - state.ScaleAt > 1 then
				state.ScaleAt = now
				state.Scale = UI.ScaleOf(clip)
			end
			local scale = state.Scale
			local clipWidth = clip.AbsoluteSize.X / scale
			local trackWidth = state.Track.AbsoluteSize.X / scale
			if clip.Visible and clip.AbsoluteSize.X > 2 and trackWidth > clipWidth then
				state.Offset -= state.Speed * dt
				-- erster sichtbarer Eintrag ganz draußen? -> ans Ende hängen (eine Verschiebung, kein Neuaufbau)
				local first: TextLabel? = nil
				local firstOrder = math.huge
				for _, label in ipairs(state.Labels) do
					if label.Visible and label.LayoutOrder < firstOrder then
						first, firstOrder = label, label.LayoutOrder
					end
				end
				if first then
					local width = first.AbsoluteSize.X / scale + TICKER_GAP
					if -state.Offset >= width then
						state.NextOrder += 1
						first.LayoutOrder = state.NextOrder
						state.Offset += width
					end
				end
				state.Track.Position = UDim2.fromOffset(math.floor(state.Offset + 0.5), 0)
			elseif state.Offset ~= 0 then
				state.Offset = 0
				state.Track.Position = UDim2.fromOffset(0, 0)
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- AUS DEM CC-ADMINPANEL GEHOBEN (REUSE §4.10): Chip, StatTile, RowCard, RowActions, Slider, Cycler, NavItem
-- ---------------------------------------------------------------------
-- Kleine Pill (voll rund), z. B. "VERDIENT"/"GEKAUFT" im Multiplikator-Sheet oder "ADMIN" in einer Zeile
function UI.Chip(parent: Instance, text: string, color: Color3, props: { [string]: any }?): Frame
	local tint = if typeof(color) == "Color3" then color else Theme.Accent
	local frame: Frame = UI.Create("Frame", {
		Name = "Chip",
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = tint,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		Parent = parent,
	}, {
		UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		UI.Create("UIStroke", {
			Color = tint,
			Thickness = 1,
			Transparency = 0.45,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		UI.Create("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }),
	})
	UI.Create("TextLabel", {
		Name = "Text",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = UI.Fonts.Main,
		TextSize = 12,
		TextColor3 = tint:Lerp(WHITE, 0.25),
		Text = text,
		Parent = frame,
	})
	if props then
		for key, value in pairs(props) do
			(frame :: any)[key] = value
		end
	end
	return frame
end

-- Kennzahl-Kachel (Dashboard): kleine Überschrift (Muted) + große Zahl (BuilderMono). Rückgabe = Wert-Label.
function UI.StatTile(parent: Instance, caption: string, order: number): TextLabel
	local card = UI.Card({ Size = UDim2.fromScale(1, 1), LayoutOrder = order, Parent = parent })
	UI.Label({
		Name = "Caption",
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 0, 16),
		Text = caption,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 13,
		Parent = card,
	})
	return UI.Label({
		Name = "Value",
		Position = UDim2.fromOffset(12, 26),
		Size = UDim2.new(1, -24, 0, 28),
		Text = "–",
		Face = "MonoBold",
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 24,
		Parent = card,
	})
end

-- Zeilen-Karte (Listen): Surface2, Ecke 10, 1-px-Rahmen, Hover = Hover-Fläche
function UI.RowCard(parent: Instance, order: number, height: number): Frame
	local card: Frame = UI.Create("Frame", {
		Name = "Row",
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = Theme.Surface2,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Parent = parent,
	}, { UI.Corner(10), UI.Stroke(nil, 1) })
	card.MouseEnter:Connect(function()
		TweenService:Create(card, HOVER_INFO, { BackgroundColor3 = Theme.Hover }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(card, HOVER_INFO, { BackgroundColor3 = Theme.Surface2 }):Play()
	end)
	return card
end

-- Knopf-Spalte rechts in einer Zeilen-Karte
function UI.RowActions(card: Frame, width: number): Frame
	return UI.Create("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.new(0, width, 1, -12),
		BackgroundTransparency = 1,
		Parent = card,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
	})
end

export type Slider = { Set: (value: number) -> (), Get: () -> number, Frame: Frame }

-- Schieberegler: Wert wird beim Loslassen geschickt (spart Anfragen). Schiene Bg2 + Rahmen, Füllung Accent,
-- weißer Knopf; die ganze Zeile ist Greif-Fläche (Handy). Globale Eingabe nur WÄHREND des Ziehens verbunden.
function UI.Slider(
	parent: Instance,
	order: number,
	title: string,
	min: number,
	max: number,
	default: number,
	onRelease: (number) -> ()
): Slider
	local row: Frame = UI.Create("Frame", {
		Name = "Slider",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	UI.Label({
		Size = UDim2.new(0.26, 0, 1, 0),
		Text = title,
		TextColor3 = Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 15,
		Parent = row,
	})
	local track: TextButton = UI.Create("TextButton", {
		Name = "Track",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.28, 0, 0.5, 0),
		Size = UDim2.new(0.56, 0, 0, 32),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Parent = row,
	})
	local rail: Frame = UI.Create("Frame", {
		Name = "Rail",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = Theme.Bg2,
		BorderSizePixel = 0,
		Parent = track,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }), UI.Stroke(nil, 1) })
	local fill: Frame = UI.Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Parent = rail,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local knob: Frame = UI.Create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = track,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }), UI.Stroke(Theme.Accent, 2) })
	local valueLabel = UI.Label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0.14, 0, 1, 0),
		Text = "",
		Face = "Mono",
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxText = 20,
		Parent = row,
	})
	local lo = math.min(min, max)
	local hi = math.max(min, max)
	local value = math.clamp(math.floor((tonumber(default) or lo) + 0.5), lo, hi)
	local function show()
		local ratio = math.clamp((value - lo) / math.max(1, hi - lo), 0, 1)
		fill.Size = UDim2.fromScale(ratio, 1)
		knob.Position = UDim2.fromScale(ratio, 0.5)
		valueLabel.Text = tostring(value)
	end
	local function setFromX(x: number)
		local width = math.max(1, rail.AbsoluteSize.X)
		local ratio = math.clamp((x - rail.AbsolutePosition.X) / width, 0, 1)
		value = math.floor(lo + ratio * (hi - lo) + 0.5)
		show()
	end
	local dragInput: InputObject? = nil
	local moveConn: RBXScriptConnection? = nil
	local endConn: RBXScriptConnection? = nil
	local function stopDrag()
		dragInput = nil
		if moveConn then
			moveConn:Disconnect()
			moveConn = nil
		end
		if endConn then
			endConn:Disconnect()
			endConn = nil
		end
	end
	track.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if dragInput or (kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch) then
			return
		end
		dragInput = input
		setFromX(input.Position.X)
		moveConn = UserInputService.InputChanged:Connect(function(changed)
			local active = dragInput
			if not active then
				return
			end
			if
				changed == active
				or (
					active.UserInputType == Enum.UserInputType.MouseButton1
					and changed.UserInputType == Enum.UserInputType.MouseMovement
				)
			then
				setFromX(changed.Position.X)
			end
		end)
		endConn = UserInputService.InputEnded:Connect(function(ended)
			if ended ~= dragInput then
				return
			end
			stopDrag()
			task.spawn(onRelease, value)
		end)
	end)
	row.Destroying:Once(stopDrag)
	show()
	return {
		Frame = row,
		Set = function(newValue: number)
			value = math.clamp(math.floor((tonumber(newValue) or value) + 0.5), lo, hi)
			show()
		end,
		Get = function(): number
			return value
		end,
	}
end

export type Cycler = {
	Get: () -> string?,
	Set: (value: string?) -> (),
	OnChange: ((string?) -> ())?,
	Button: Button,
}

-- Knopf, der beim Klicken durch eine Liste schaltet ("Grafik: Hoch")
function UI.Cycler(parent: Instance, title: string, options: { string }, size: UDim2, emptyLabel: string?): Cycler
	local list: { string } = table.clone(options or {})
	if emptyLabel then
		table.insert(list, 1, "")
	end
	local index = 1
	local function label(): string
		local value = list[index]
		if value == nil or value == "" then
			return ("%s: %s"):format(title, emptyLabel or "-")
		end
		return ("%s: %s"):format(title, value)
	end
	local state: Cycler
	local btn = UI.Button({
		Size = size,
		Text = label(),
		Variant = "Secondary",
		MaxText = 15,
		Corner = 10,
		Parent = parent,
	}, function()
		if #list == 0 then
			return
		end
		index = (index % #list) + 1
		state.Button.SetText(label())
		if state.OnChange then
			task.spawn(state.OnChange, state.Get())
		end
	end)
	state = {
		Get = function(): string?
			local value = list[index]
			if value == nil or value == "" then
				return nil
			end
			return value
		end,
		Set = function(value: string?)
			local found = table.find(list, value or "")
			if found then
				index = found
				btn.SetText(label())
			end
		end,
		OnChange = nil,
		Button = btn,
	}
	return state
end

export type NavItem = { Button: TextButton, SetActive: (on: boolean) -> (), SetText: (text: string) -> () }

-- Reiter in der Seitenleiste: transparent, Hover-Fläche; aktiv = Surface2 + Akzent-Strich links + heller Text
function UI.NavItem(parent: Instance, text: string, order: number, onClick: () -> ()): NavItem
	local active = false
	local btn: TextButton = UI.Create("TextButton", {
		Name = "Tab",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Theme.Hover,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Parent = parent,
	}, { UI.Corner(10) })
	local bar: Frame = UI.Create("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(3, 18),
		BackgroundColor3 = Theme.Accent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = btn,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local label = UI.Label({
		Name = "Label",
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -20, 1, 0),
		Text = text,
		TextColor3 = Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 15,
		Parent = btn,
	})
	local function paint(hover: boolean)
		local goal = if active
			then { BackgroundColor3 = Theme.Surface2, BackgroundTransparency = 0 }
			elseif hover then { BackgroundColor3 = Theme.Hover, BackgroundTransparency = 0.2 }
			else { BackgroundColor3 = Theme.Hover, BackgroundTransparency = 1 }
		TweenService:Create(btn, HOVER_INFO, goal):Play()
		TweenService:Create(bar, HOVER_INFO, { BackgroundTransparency = if active then 0 else 1 }):Play()
		label.TextColor3 = if active then Theme.Text else Theme.Text2
	end
	btn.MouseEnter:Connect(function()
		paint(true)
	end)
	btn.MouseLeave:Connect(function()
		paint(false)
	end)
	btn.Activated:Connect(function()
		playUiSound("UIClick")
		local ok, err = pcall(onClick)
		if not ok then
			warn("[UI] NavItem: " .. tostring(err))
		end
	end)
	return {
		Button = btn,
		SetActive = function(on: boolean)
			active = on == true
			paint(false)
		end,
		SetText = function(newText: string)
			if label.Text ~= newText then
				label.Text = newText
			end
		end,
	}
end

-- ---------------------------------------------------------------------
-- START
-- ---------------------------------------------------------------------
function UI.Frame(dt: number)
	stepCounters(dt)
	stepTickers(dt)
end

-- Prüft, ob BuilderExtended/BuilderMono mit Umlauten + „Λ“ messbar sind; sonst Rückfall-Schriften.
-- Läuft höchstens FACE_CHECK_WAIT Sekunden, bevor der Rest der Oberfläche gebaut wird.
local function checkFaces()
	local results: { [string]: boolean } = {}
	local pending = 0
	for key, face in pairs(UI.Faces) do
		if FACE_FALLBACK[key] then
			pending += 1
			task.spawn(function()
				local ok, bounds = pcall(function()
					local params = Instance.new("GetTextBoundsParams")
					params.Text = FACE_CHECK_TEXT
					params.Font = face
					params.Size = 20
					params.Width = 2000
					return TextService:GetTextBoundsAsync(params)
				end)
				results[key] = ok and typeof(bounds) == "Vector2" and bounds.X > 1
				pending -= 1
			end)
		end
	end
	local deadline = os.clock() + FACE_CHECK_WAIT
	local guard = 0
	while pending > 0 and os.clock() < deadline and guard < 100 do
		guard += 1
		task.wait(0.03)
	end
	for key, okFace in pairs(results) do
		if not okFace then
			UI.Faces[key] = FACE_FALLBACK[key]
			warn("[UI] Schrift " .. key .. " nicht verfügbar – Rückfall wird benutzt")
		end
	end
end

function UI.Init(ctxOrGui: any)
	local screenGui: ScreenGui? = nil
	if typeof(ctxOrGui) == "Instance" and ctxOrGui:IsA("ScreenGui") then
		screenGui = ctxOrGui
	elseif type(ctxOrGui) == "table" then
		ctx = ctxOrGui
		local gui = ctxOrGui.Gui
		if typeof(gui) == "Instance" and gui:IsA("ScreenGui") then
			screenGui = gui
		end
	end
	assert(screenGui, "UI.Init: ScreenGui oder ctx mit Gui erwartet")
	if root == screenGui then
		return -- schon initialisiert
	end
	root = screenGui
	UI.Root = screenGui
	checkFaces()

	-- Alles passend zur Bildschirmgröße skalieren (Handy bis großer Monitor)
	local rootScale: UIScale = UI.Create("UIScale", { Name = "RootScale", Parent = screenGui })
	local cameraConnection: RBXScriptConnection? = nil
	local function updateScale()
		local camera = workspace.CurrentCamera
		if camera then
			local size = camera.ViewportSize
			rootScale.Scale = math.clamp(math.min(size.X / 1280, size.Y / 760), 0.55, 1.15)
		end
	end
	local function bindCamera()
		if cameraConnection then
			cameraConnection:Disconnect()
			cameraConnection = nil
		end
		local camera = workspace.CurrentCamera
		if camera then
			cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
		end
		updateScale()
	end
	bindCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)

	-- Meldungen oben in der Mitte
	toastHolder = UI.Create("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, TOAST_TOP),
		Size = UDim2.fromOffset(TOAST_WIDTH, 320),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = screenGui,
	}, {
		UI.Create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	})

	-- Modal-Knopf: sichtbar, solange ein Fenster offen ist -> Roblox gibt die Maus frei (Shift-Lock)
	modalButton = UI.Create("TextButton", {
		Name = "WindowModal",
		Size = UDim2.fromOffset(1, 1),
		Position = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		Modal = true,
		Visible = false,
		Parent = screenGui,
	})

	-- Pulte/Kioske in der Welt (Attribut "Window") öffnen dasselbe Fenster wie der HUD-Knopf
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		if who ~= Players.LocalPlayer then
			return
		end
		local name = prompt:GetAttribute("Window")
		if type(name) == "string" and name ~= "" then
			Windows.Open(name)
		end
	end)

	local hooks = ctx and ctx.Hooks
	if hooks and type(hooks.On) == "function" then
		-- Server-Wert "RandomAllowed" kommt mit dem State -> wartende Rückfragen beantworten
		hooks.On("State", function()
			local known = stateRandom()
			if known ~= nil then
				resolveRandom(known)
			end
		end)
		-- Farbenblind-Modus aus den Einstellungen
		hooks.On("Settings", function(settings)
			if type(settings) == "table" then
				UI.SetColorblind(settings.Colorblind == true)
			end
		end)
	end
end

function UI.Start() end

return UI
