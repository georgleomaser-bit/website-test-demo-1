-- =====================================================================
--  CLUTCH CLASH – UI-BAUKASTEN im AKYTEX-Look (Client/Modules/UI)
--  Besitzer: WP10 (Client-Hülle). Basis: Meteor-Heist-UI-Kit (REUSE §11) + Shooter-Ergänzungen.
--  Stil: docs/STYLE-AKYTEX.md – dunkel, edel, klar (wie RIVALS / die AKYTEX-Trading-Seite).
--  Flächen aus UI.Theme (Glas-Fenster mit 1-px-Rahmen), Schrift aus UI.Fonts (Builder Sans,
--  Titel in Michroma, HUD-Zahlen in Titillium Web). Keine dicken schwarzen Konturen, keine 3D-Lippen,
--  kein Comic-Glanz. Bewegung iOS-artig: Öffnen 0.18 s Fade + Scale 0.96→1 (Quint Out), Schließen
--  0.14 s Quad In, Hover 0.12 s, Drücken = Feder auf 0.97 + kurzer Farbblitz.
--
--  Öffentliche API (REUSE §11 + C7.3/C7.4):
--    UI.Font, UI.Fonts, UI.Theme, UI.Root
--    UI.Init(ctxOrGui)                ScreenGui oder ctx (nimmt ctx.Gui) – Wurzel-UIScale, Toasts, Modal-Knopf
--    UI.Frame(dt)                     pro Frame (ruft Main.client aus dem einen PreRender-Loop)
--    UI.Create, UI.Corner, UI.Stroke, UI.TextStroke, UI.Gradient, UI.ButtonSequence, UI.FormatMult,
--    UI.FormatSteps, UI.Upper, UI.Label, UI.TextBox, UI.Button, UI.Badge, UI.SetBadge, UI.Section, UI.Row,
--    UI.Grid, UI.Card, UI.Panel, UI.Divider, UI.Bar, UI.SetBar, UI.Pulse, UI.Counter, UI.SetCounter,
--    UI.RedrawCounter, UI.Window, UI.OpenWindow, UI.CloseWindow, UI.ToggleWindow, UI.CloseAll
--    UI.IsAnyWindowOpen(): boolean    (Shooter: Kamera gibt die Maus frei, Kampf-Eingaben gesperrt)
--    UI.Toast(text, kind?), UI.SetToastTop(offset?)
--    UI.FetchPrice(id, infoType, cb), UI.WhenRandomItemsKnown(cb), UI.RandomItemsAllowed()
--    UI.Windows = { Register(name, open, close?), Open(name), Close(name?), IsOpen(name?), Toggle(name) }  (= ctx.Windows)
--  UI.Button(props, onClick): props wie bisher (Name, Size, Position, AnchorPoint, LayoutOrder, Parent,
--    Visible, ZIndex, Text, Sub, Color, MaxText, SubMax, Corner, Wrap, Silent; StrokeSize wird ignoriert)
--    + Variant = "Primary" (Standard, Accent) | "Secondary" | "Danger" | "Success" | "Ghost" | "Premium" | "Muted".
--    Color ohne Variant wählt die Variante über das Theme-Token (Accent/Blue/Orange = Primary, Down/Red = Danger,
--    Up/Green/Cash = Success, Warn/Yellow/Gold = Premium, Gray/Muted = Muted, Surface2/PanelLight/Hover = Secondary);
--    jede andere Farbe = volle Fläche in dieser Farbe. Rückgabe { Frame, Button, Label, Sub?, Stroke, SetText,
--    SetSub, SetColor, SetVariant }.
--  Fenster offen -> sichtbarer Modal-Knopf (Modal = true, gibt die Maus in der Ego-Sicht frei),
--  Hooks "WindowOpened"/"WindowClosed"(name). ProximityPrompt mit Attribut "Window" öffnet das Fenster.
--  Alte Schriften (FredokaOne/LuckiestGuy/Bangers/Gotham) werden in UI.Create/Label/TextBox automatisch
--  durch die AKYTEX-Schriften ersetzt; UI.Stroke(schwarz, dick) wird zum feinen 1-px-Border-Rahmen.
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

-- AKYTEX-Look (docs/STYLE-AKYTEX.md): moderne, klare Schrift. Builder Sans ist Robloxs eigene
-- UI-Schrift (lokal vorhanden, Umlaute ok); Überschriften/Logo breit und technisch (Michroma),
-- HUD-Zahlen (Munition, Timer, Punkte) im Shooter-Stil (Titillium Web).
UI.Font = Enum.Font.BuilderSansBold
UI.Fonts = {
	Main = Enum.Font.BuilderSansBold, -- Knöpfe, Labels
	Body = Enum.Font.BuilderSans, -- Fließtext, Beschreibungen
	Strong = Enum.Font.BuilderSansExtraBold, -- große Zahlen/Titel in Karten
	Heading = Enum.Font.Michroma, -- Fenstertitel, Logo, Banner
	Number = Enum.Font.TitilliumWeb, -- HUD-Zahlen (Munition, Timer, Score)
	Banner = Enum.Font.Michroma, -- große Ansagen (MATCH POINT, CLUTCH!)
	Pop = Enum.Font.BuilderSansExtraBold, -- "HEADSHOT!"/"POP!"
}

-- AKYTEX-Farben (wie die Trading-Seite, Dark Mode): dunkle Glas-Flächen, Blau als Akzent,
-- Grün = Sieg/Gewinn, Rot = Niederlage/Schaden, Gelb = Warnung. Alte Schlüssel bleiben erhalten
-- (andere Module nutzen sie) und zeigen auf die passenden AKYTEX-Farben.
local AKY = {
	Bg = Color3.fromRGB(11, 15, 23), -- #0b0f17
	Bg2 = Color3.fromRGB(15, 20, 29), -- #0f141d
	Surface = Color3.fromRGB(18, 24, 36), -- #121824 (Panel)
	Surface2 = Color3.fromRGB(26, 33, 48), -- #1a2130 (Karte/Panel-2)
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
	-- AKYTEX-Schlüssel (neu)
	Bg = AKY.Bg,
	Bg2 = AKY.Bg2,
	Surface = AKY.Surface,
	Surface2 = AKY.Surface2,
	Hover = AKY.Hover,
	Border = AKY.Border,
	Text2 = AKY.Text2,
	Muted = AKY.Muted,
	Accent = AKY.Accent,
	AccentDeep = AKY.AccentDeep,
	Up = AKY.Up,
	Down = AKY.Down,
	Warn = AKY.Warn,
	-- bisherige Schlüssel -> AKYTEX-Farben
	Panel = AKY.Surface,
	PanelDark = AKY.Bg,
	PanelLight = AKY.Surface2,
	Text = AKY.Text,
	SubText = AKY.Text2,
	Black = BLACK,
	Yellow = AKY.Warn,
	Cash = AKY.Up,
	Red = AKY.Down,
	Blue = AKY.Accent,
	Green = AKY.Up,
	Orange = Color3.fromRGB(245, 158, 11), -- #f59e0b
	Purple = Color3.fromRGB(139, 92, 246), -- #8b5cf6
	Pink = Color3.fromRGB(236, 72, 153), -- #ec4899
	Gray = AKY.Muted,
	Gold = Color3.fromRGB(250, 204, 21), -- #facc15
	Cyan = Color3.fromRGB(34, 211, 238), -- #22d3ee
}
local Theme = UI.Theme

-- Bewegung (iOS-artig, wie AKYTEX --ease-ios) – einmal angelegt und immer wiederverwendet
local HOVER_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_INFO = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out) -- leichte Feder
local OPEN_FADE_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local OPEN_SCALE_INFO = TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local CLOSE_INFO = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local BLUR_IN_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local BLUR_OUT_INFO = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local COUNTER_FLASH_INFO = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
local BAR_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local PULSE_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local FOCUS_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
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
local ctx: any = nil -- gemeinsamer Rucksack (nach UI.Init mit ctx gesetzt; für Hooks/Sfx/State)
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

-- 1-px-Rahmen (AKYTEX). Schwarz/ohne Farbe = Border-Token; farbige Rahmen (Seltenheit, Team) bleiben,
-- werden aber höchstens 2 px dick. Alte Aufrufe UI.Stroke(BLACK, 3) werden so automatisch fein.
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

-- Text-Label. MaxText = größte Schriftgröße (TextScaled), Outline = feine Kontur (Text über der Welt).
function UI.Label(props: { [string]: any }): TextLabel
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = UI.Fonts.Main,
		TextColor3 = Theme.Text,
		TextScaled = true,
		Text = "",
	}
	for key, value in pairs(props) do
		if key ~= "MaxText" and key ~= "Outline" then
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

-- Theme-Token -> Variante (Reihenfolge egal: gleiche Werte führen zur selben Variante)
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
		Font = UI.Fonts.Main,
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
			Font = UI.Fonts.Main,
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

	-- Klick: Fehler im Callback brechen die Oberfläche nicht, Doppelklicks werden ignoriert
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
-- (rechts verankert: längere Texte wie "4:59" wachsen als Pille nach links, nicht aus dem Bild)
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
		Font = UI.Fonts.Main,
		TextColor3 = WHITE,
		MaxText = 15,
		ZIndex = target.Button.ZIndex + 3,
		Parent = badge,
	})
	return badge
end

local BADGE_PULSE_INFO = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local badgePulses: { [Frame]: Tween } = {}

-- Badge setzen: text nil/"" = ausblenden. pulse = sanft pulsieren (z.B. "abholbereit").
-- Schreibt nur bei Änderungen (wird jede Sekunde aufgerufen).
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
		Font = UI.Fonts.Main,
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
		Font = UI.Fonts.Main,
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

-- Kurzes "Aufploppen" (z.B. wenn Coins reinkommen) – weich, ohne Überschwingen
function UI.Pulse(scale: UIScale, amount: number?)
	scale.Scale = 1 + (amount or 0.1)
	TweenService:Create(scale, PULSE_INFO, { Scale = 1 }):Play()
end

-- ---------------------------------------------------------------------
-- FLÜSSIG ZÄHLENDE ZAHLEN (Coins, Gems, Schlüssel)
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
	TweenService:Create(label, COUNTER_FLASH_INFO, { TextColor3 = if up then Theme.Up else Theme.Down }):Play()
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

-- Schreibt den Text sofort neu (z.B. wenn sich das Format geändert hat)
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
-- FENSTER (immer nur eins offen; Glas-Panel, Titel in Michroma, schlichtes ✕)
-- Der Inhalt steckt nur WÄHREND des Auf-/Zugehens in einer CanvasGroup (für das weiche Einblenden).
-- Danach hängt er in einem normalen Frame: Eine CanvasGroup malt bei jeder kleinen Änderung
-- (Text, Balken, Scrollen) ihren ganzen Inhalt neu und macht Schrift auf Handys unscharf.
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
	Title: string,
}

-- Registrierte Fenster (C7.3): Name -> öffnen/schließen. Ein UI.Window, das während open() aufgeht,
-- wird automatisch mit dem Namen verknüpft (dann meldet auch das ✕ das Schließen richtig).
type WindowEntry = {
	Name: string,
	OpenFn: () -> (),
	CloseFn: (() -> ())?,
	Win: Window?,
	Flag: boolean, -- offen (für Fenster ohne verknüpftes UI.Window)
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

-- true, sobald irgendein Fenster offen ist (UI.Window oder registriertes Fremd-Fenster)
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
-- + Modal-Knopf: solange ein Fenster offen ist, gibt er die Maus in der Ego-Sicht frei
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
			effect = UI.Create("BlurEffect", { Name = "ClutchClashWindowBlur", Size = 0, Parent = Lighting })
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
	TweenService:Create(win.Scale, CLOSE_INFO, { Scale = 0.97 }):Play()
	TweenService:Create(win.Group, CLOSE_INFO, { Position = UDim2.new(0.5, 0, 0.5, WINDOW_SLIDE * 0.75) }):Play()
	local fade = TweenService:Create(win.Fader, CLOSE_INFO, { GroupTransparency = 1 })
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
	if not win.Group.Visible then
		win.Fader.GroupTransparency = 1
		win.Scale.Scale = 0.96
		win.Group.Position = UDim2.new(0.5, 0, 0.5, WINDOW_SLIDE)
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
	TweenService:Create(win.Scale, OPEN_SCALE_INFO, { Scale = 1 }):Play()
	TweenService:Create(win.Group, OPEN_SCALE_INFO, { Position = UDim2.fromScale(0.5, 0.5) }):Play()
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

-- Glas-Fenster: Surface (Transparenz 0.08), Ecke 16, 1-px-Border, weicher Schatten dahinter,
-- Kopf mit Titel (Michroma, GROSS) + Akzent-Unterstrich links und schlichtem ✕ (Ghost) rechts.
-- color = Akzent des Fensters (Unterstrich, Bildlaufleiste); Standard Accent.
function UI.Window(title: string, width: number, height: number, color: Color3?): Window
	assert(root, "UI.Init zuerst aufrufen")
	local accent = accentOf(color)
	local group: Frame = UI.Create("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, height),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 10,
		Parent = root,
	})
	local scale: UIScale = UI.Create("UIScale", { Scale = 0.96, Parent = group })
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
	}, { UI.Corner(16), UI.Stroke(nil, 1) })
	local header: Frame = UI.Create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, WINDOW_HEADER),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	-- Titel in GROSSBUCHSTABEN (Michroma, 18–22 px)
	UI.Label({
		Name = "Title",
		Position = UDim2.fromOffset(20, 12),
		Size = UDim2.new(1, -84, 0, 26),
		Text = UI.Upper(title),
		Font = UI.Fonts.Heading,
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
	local content: ScrollingFrame = UI.Create("ScrollingFrame", {
		Name = "Content",
		Position = UDim2.fromOffset(16, WINDOW_HEADER + 10),
		Size = UDim2.new(1, -24, 1, -(WINDOW_HEADER + 20)),
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
		Title = title,
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
		UI.CloseWindow(win)
	end)
	table.insert(windows, win)
	return win
end

-- ---------------------------------------------------------------------
-- WINDOWS-REGISTRY (C7.3) = ctx.Windows
-- Namen: "Play" (WP5), "Shop", "Locker" (WP9), "Quests", "Pass", "Daily" (WP8), "Settings" (WP10),
-- "Training" (WP6), "Admin" (WP7). Immer nur ein Fenster offen.
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
-- gleitet 8 px herein und blendet aus; gestapelt (neueste unten). Normale Frames (keine CanvasGroup)
-- + ein kleiner Vorrat, der wiederverwendet wird.
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

-- Meldungen tiefer setzen, solange oben etwas anderes steht (z.B. Runden-Timer im Match).
-- nil = wieder an die normale Stelle.
function UI.SetToastTop(offset: number?)
	local holder = toastHolder
	if holder then
		holder.Position = UDim2.new(0.5, 0, 0, offset or TOAST_TOP)
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
-- LÄNDER-REGEL "Paid Random Items" (B20.2): Dürfen wir bezahlte Zufallsitems zeigen?
-- Quelle 1: Server-State "RandomAllowed" (gecacht, inkl. Debug/Admin-Simulation).
-- Quelle 2 (nur falls der Server nach 30 s nichts sagt): PolicyService selbst fragen.
-- Im Zweifel/bei Fehler: NICHT zeigen.
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

-- ---------------------------------------------------------------------
-- START
-- ---------------------------------------------------------------------
local MATCH_TOAST_TOP = 116 -- im Match unter der Score-/Timer-Leiste von MatchUI (oben Mitte, 6 + 100 px)

function UI.Frame(dt: number)
	stepCounters(dt)
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

	-- Modal-Knopf: sichtbar, solange ein Fenster offen ist -> Roblox gibt die Maus frei (Ego-Sicht)
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

	-- Kiosk-Prompts in der Lobby (Attribut "Window") öffnen dasselbe Fenster wie der HUD-Knopf
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
		-- Im Match steht oben in der Mitte die Score-/Timer-Leiste (MatchUI): Meldungen darunter
		hooks.On("World", function(world)
			UI.SetToastTop(if world == "Match" or world == "Crown" then MATCH_TOAST_TOP else nil)
		end)
	end
end

function UI.Start() end

return UI
