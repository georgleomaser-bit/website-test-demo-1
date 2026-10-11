-- =====================================================================
--  UI-BAUKASTEN im knalligen Roblox-Simulator-Stil (Steal a Brainrot / Pet Simulator)
--  Schrift überall FredokaOne mit schwarzer Kontur. Knöpfe: Volltonfarbe mit Verlauf, dicke
--  schwarze Kontur, dunklere 3D-Kante unten ("Lippe"), Glanz-Streifen und Feder-Effekt
--  (größer beim Drüberfahren, Stauchen + Einsinken beim Drücken). Fenster: helle blaue Fläche,
--  dicke Kontur, Titel in GROSSBUCHSTABEN, rotes X; gehen federnd auf und zeichnen die Welt
--  dahinter leicht weich. Meldungen (Toasts) ohne Kasten: großer farbiger Text mit dicker Kontur,
--  ploppt oben in der Mitte auf und verblasst. Dazu flüssig hochzählende Zahlen (kurzes Aufploppen
--  + Farbblitz bei Zuwachs) und getweente Balken.
--  Alle anderen Client-Module bauen ihre Oberfläche hiermit.
-- =====================================================================

local MarketplaceService = game:GetService("MarketplaceService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local UI = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

-- Die Simulator-Schrift (rund, dick, gut lesbar) – für ALLE Texte
UI.Font = Enum.Font.FredokaOne

-- Helle, kräftige Farben. Fensterflächen sind hellblau: weißer Text braucht darauf immer
-- eine schwarze Kontur (UI.TextStroke bzw. Outline = 2 in UI.Label).
UI.Theme = {
	Panel = Color3.fromRGB(70, 170, 255),
	PanelDark = Color3.fromRGB(35, 115, 230),
	PanelLight = Color3.fromRGB(120, 205, 255),
	Text = WHITE,
	SubText = Color3.fromRGB(235, 245, 255),
	Black = BLACK,
	Yellow = Color3.fromRGB(255, 220, 50),
	Cash = Color3.fromRGB(110, 255, 100),
	Red = Color3.fromRGB(255, 65, 75),
	Blue = Color3.fromRGB(40, 100, 245), -- kräftiges Königsblau: hebt sich vom hellblauen Fenster ab
	Green = Color3.fromRGB(70, 210, 80),
	Orange = Color3.fromRGB(255, 145, 35),
	Purple = Color3.fromRGB(175, 85, 255),
	Pink = Color3.fromRGB(255, 85, 195),
	Gray = Color3.fromRGB(120, 125, 145),
	Gold = Color3.fromRGB(255, 200, 40),
	Cyan = Color3.fromRGB(60, 220, 255),
}

-- Tween-Einstellungen (einmal angelegt und immer wiederverwendet)
local HOVER_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PRESS_INFO = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SQUASH_RELEASE_INFO = TweenInfo.new(0.45, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
local GLOW_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local OPEN_FADE_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local OPEN_POP_INFO = TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local BLUR_IN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BLUR_OUT_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local COUNTER_FLASH_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
local BAR_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PULSE_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TOAST_GROW_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TOAST_RISE_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TOAST_POP_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TOAST_FADE_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TOAST_OUT_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local COUNTER_INTERVAL = 1 / 30 -- Zahlen höchstens 30x pro Sekunde neu schreiben
local COUNTER_POP_GAP = 0.15 -- so oft höchstens ein Aufploppen pro Zähler
local BUTTON_LIP = 4 -- so viele Pixel dunklere 3D-Kante ("Lippe") unter jedem Knopf
local LIP_DARKEN = 0.45 -- Lippe = Knopffarbe, so viel Richtung Schwarz
local BUTTON_NORMAL = UDim2.new(1, 0, 1, -BUTTON_LIP) -- Knopf-Fläche (darunter schaut die Lippe raus)
local BUTTON_SQUASH = UDim2.new(1.07, 0, 0.86, -BUTTON_LIP) -- gedrückter Knopf: breiter + flacher
local BUTTON_UP = UDim2.new(0.5, 0, 0.5, -BUTTON_LIP / 2)
local BUTTON_DOWN = UDim2.new(0.5, 0, 0.5, BUTTON_LIP / 2) -- gedrückt: sinkt auf die Lippe
local BUTTON_PRESSED_TINT = Color3.fromRGB(215, 215, 215) -- gedrückt: Knopf etwas dunkler
local SHINE_NORMAL = 0.8 -- Glanz-Streifen (Durchsichtigkeit)
local SHINE_HOVER = 0.55 -- Maus drüber: Glanz heller
local BLUR_SIZE = 6 -- dezenter Weichzeichner hinter offenen Fenstern
local WINDOW_SLIDE = 36 -- Fenster gleiten aus so vielen Pixeln von unten herein
local WINDOW_STROKE = 5 -- dicke schwarze Fenster-Kontur (passt genau in den Rand der Animations-Fläche)
local TOAST_WIDTH = 680
local TOAST_TEXT_WIDTH = TOAST_WIDTH - 24
local TOAST_MIN_HEIGHT = 34
local TOAST_GAP = 2
local TOAST_RISE = 10 -- Toasts ploppen aus so vielen Pixeln weiter unten auf (und steigen beim Gehen hoch)
local MAX_TOASTS = 5
local MAX_TOAST_POOL = 8 -- so viele fertige Toasts werden zum Wiederverwenden aufgehoben

-- Gotham-Schriften (alter Look) werden automatisch durch FredokaOne ersetzt
local GOTHAM_FONTS: { [Enum.Font]: boolean } = {
	[Enum.Font.Gotham] = true,
	[Enum.Font.GothamMedium] = true,
	[Enum.Font.GothamBold] = true,
	[Enum.Font.GothamBlack] = true,
}

local root: ScreenGui? = nil
UI.Root = nil :: ScreenGui? -- die ScreenGui der Oberfläche (nach UI.Init gesetzt)

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

-- Dicke Kontur um einen Rahmen/Knopf
function UI.Stroke(color: Color3?, thickness: number?): UIStroke
	return UI.Create("UIStroke", {
		Color = color or BLACK,
		Thickness = thickness or 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

-- Schwarzer Rand um Schrift (gut lesbar auf jedem Hintergrund)
function UI.TextStroke(thickness: number?): UIStroke
	return UI.Create("UIStroke", { Thickness = thickness or 2, Color = BLACK })
end

-- Farbverlauf von oben nach unten
function UI.Gradient(top: Color3, bottom: Color3, rotation: number?): UIGradient
	return UI.Create("UIGradient", { Rotation = rotation or 90, Color = ColorSequence.new(top, bottom) })
end

-- Knallige Verlaufsfarbe für einen Knopf: oben heller, unten dunkler
function UI.ButtonSequence(color: Color3): ColorSequence
	return ColorSequence.new(color:Lerp(WHITE, 0.28), color:Lerp(BLACK, 0.18))
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

-- Kleine Schritte-Mengen mit einer Nachkommastelle (2.5 statt 2), große wie gewohnt (3.1M)
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

function UI.Label(props: { [string]: any }): TextLabel
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = UI.Font,
		TextColor3 = WHITE,
		TextScaled = true,
		Text = "",
	}
	for key, value in pairs(props) do
		if key ~= "MaxText" and key ~= "Outline" then
			base[key] = value
		end
	end
	if GOTHAM_FONTS[base.Font] then
		base.Font = UI.Font
	end
	local children: { Instance } = { UI.Create("UITextSizeConstraint", { MaxTextSize = props.MaxText or 28 }) }
	if props.Outline then
		table.insert(children, UI.TextStroke(props.Outline))
	end
	return UI.Create("TextLabel", base, children)
end

function UI.TextBox(props: { [string]: any }): TextBox
	local base: { [string]: any } = {
		BackgroundColor3 = UI.Theme.PanelDark,
		Font = UI.Font,
		TextColor3 = WHITE,
		PlaceholderColor3 = Color3.fromRGB(165, 205, 255), -- blasser als echter Text
		TextScaled = true,
		ClearTextOnFocus = false,
		Text = "",
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	if GOTHAM_FONTS[base.Font] then
		base.Font = UI.Font
	end
	return UI.Create("TextBox", base, {
		UI.Corner(8),
		UI.Stroke(BLACK, 2),
		UI.Create("UITextSizeConstraint", { MaxTextSize = 18 }),
		UI.Create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
	})
end

-- ---------------------------------------------------------------------
-- KNÖPFE (Halter-Rahmen für das Layout + federnder Knopf in der Mitte)
-- Aufbau: Halter (unsichtbar) -> "Lip" (dunklere 3D-Kante, schaut unten ein paar Pixel raus)
--         + "Button" (die Knopf-Fläche mit Verlauf, Kontur, Glanz und Text)
-- props: Size, Position, AnchorPoint, LayoutOrder, Parent, Visible, ZIndex,
--        Text, Sub (kleine zweite Zeile), Color, MaxText, SubMax, Corner, StrokeSize, Wrap
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
}

function UI.Button(props: { [string]: any }, onClick: (() -> ())?): Button
	local cornerRadius: number = props.Corner or 12
	local strokeSize: number = props.StrokeSize or 3
	local z: number = props.ZIndex or 1
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
	local currentColor: Color3 = props.Color or UI.Theme.Orange

	-- 3D-Kante: dunklere Kopie der unteren Knopfhälfte, liegt hinter der Fläche und schaut unten raus
	-- (nur die untere Hälfte, damit sie beim Stauchen oben nicht hervorblitzt)
	local lip: Frame = UI.Create("Frame", {
		Name = "Lip",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, 0.62),
		BackgroundColor3 = currentColor:Lerp(BLACK, LIP_DARKEN),
		ZIndex = z - 1,
		Parent = holder,
	}, { UI.Corner(cornerRadius), UI.Stroke(BLACK, strokeSize) })

	local gradient: UIGradient = UI.Create("UIGradient", {
		Rotation = 90,
		Color = UI.ButtonSequence(currentColor),
	})
	local scale: UIScale = UI.Create("UIScale")
	local outline = UI.Stroke(BLACK, strokeSize)
	local btn: TextButton = UI.Create("TextButton", {
		Name = "Button",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = BUTTON_UP,
		Size = BUTTON_NORMAL,
		BackgroundColor3 = WHITE,
		AutoButtonColor = false,
		Text = "",
		ZIndex = z,
		Parent = holder,
	}, { UI.Corner(cornerRadius), gradient, outline, scale })

	-- Glanz-Streifen oben (macht den "Bonbon"-Look der Simulator-Knöpfe; wird beim Drüberfahren heller)
	local shine: Frame = UI.Create("Frame", {
		Name = "Shine",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 3),
		Size = UDim2.new(1, -8, 0.4, -2),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = SHINE_NORMAL,
		ZIndex = z,
		Parent = btn,
	}, { UI.Corner(math.max(2, cornerRadius - 3)) })

	local hasSub = props.Sub ~= nil
	local main = UI.Label({
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, hasSub and 0.06 or 0.12, 0),
		Size = UDim2.new(1, -12, hasSub and 0.58 or 0.76, 0),
		Text = props.Text or "",
		TextWrapped = props.Wrap == true,
		MaxText = props.MaxText or 24,
		Outline = 2,
		ZIndex = z + 1,
		Parent = btn,
	})
	local sub: TextLabel? = nil
	if hasSub then
		sub = UI.Label({
			Name = "Sub",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.62, 0),
			Size = UDim2.new(1, -12, 0.32, 0),
			Text = props.Sub,
			MaxText = props.SubMax or 16,
			Outline = 2,
			ZIndex = z + 1,
			Parent = btn,
		})
	end

	-- Feder-Effekt: Maus drüber = etwas größer + hellerer Glanz, drücken = kleiner + gestaucht
	-- (breit/flach), sinkt auf die Lippe und wird etwas dunkler, loslassen = federt elastisch zurück
	local hovering = false
	local pressed = false
	local shineTarget = SHINE_NORMAL
	local function spring(target: number, info: TweenInfo)
		TweenService:Create(scale, info, { Scale = target }):Play()
	end
	local function setShine(transparency: number)
		if shineTarget ~= transparency then
			shineTarget = transparency
			TweenService:Create(shine, GLOW_INFO, { BackgroundTransparency = transparency }):Play()
		end
	end
	local function setPressed(on: boolean)
		if pressed ~= on then
			pressed = on
			TweenService:Create(btn, GLOW_INFO, { BackgroundColor3 = if on then BUTTON_PRESSED_TINT else WHITE }):Play()
		end
	end
	btn.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseMovement then
			hovering = true
			spring(1.06, HOVER_INFO)
			setShine(SHINE_HOVER)
		elseif kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			spring(0.93, PRESS_INFO)
			TweenService:Create(btn, PRESS_INFO, { Size = BUTTON_SQUASH, Position = BUTTON_DOWN }):Play()
			setPressed(true)
		end
	end)
	btn.InputEnded:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			TweenService:Create(btn, SQUASH_RELEASE_INFO, { Size = BUTTON_NORMAL, Position = BUTTON_UP }):Play()
			setPressed(false)
		end
		if kind == Enum.UserInputType.MouseButton1 then
			spring(if hovering then 1.06 else 1, RELEASE_INFO)
		elseif kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch then
			-- Maus raus bzw. Finger weg: zurück auf normale Größe
			hovering = false
			spring(1, RELEASE_INFO)
			setShine(SHINE_NORMAL)
			setPressed(false)
		end
	end)

	-- Klick: Fehler im Callback brechen die Oberfläche nicht, Doppelklicks werden ignoriert
	local busy = false
	btn.Activated:Connect(function()
		if busy or not onClick then
			return
		end
		busy = true
		local callback = onClick :: () -> ()
		task.spawn(function()
			local ok, err = pcall(callback)
			if not ok then
				warn("[UI] " .. tostring(err))
			end
			busy = false
		end)
	end)

	local result: Button = {
		Frame = holder,
		Button = btn,
		Label = main,
		Sub = sub,
		Stroke = outline,
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
			if color ~= currentColor then
				currentColor = color
				gradient.Color = UI.ButtonSequence(color)
				lip.BackgroundColor3 = color:Lerp(BLACK, LIP_DARKEN)
			end
		end,
	}
	return result
end

-- Roter Kreis mit "!" oben rechts an einem Knopf (z.B. Tagesbonus bereit)
-- (rechts verankert: längere Texte wie "4:59" wachsen als Pille nach links, nicht aus dem Bild)
function UI.Badge(target: Button, text: string?): Frame
	local badge: Frame = UI.Create("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 8, 0, 6),
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = UI.Theme.Red,
		Visible = false,
		ZIndex = target.Button.ZIndex + 2,
		Parent = target.Button,
	}, { UI.Corner(14), UI.Stroke(BLACK, 2), UI.Create("UIScale", { Name = "Pulse" }) })
	UI.Label({
		Name = "Text",
		Position = UDim2.fromOffset(3, 2),
		Size = UDim2.new(1, -6, 1, -4),
		Text = text or "!",
		MaxText = 20,
		Outline = 2,
		ZIndex = target.Button.ZIndex + 3,
		Parent = badge,
	})
	return badge
end

local BADGE_PULSE_INFO = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
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
		local width = if chars <= 1 then 28 else math.min(76, 12 + chars * 10)
		badge.Size = UDim2.fromOffset(width, 28)
	end
	local wanted = color or UI.Theme.Red
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
		local newTween = TweenService:Create(scale, BADGE_PULSE_INFO, { Scale = 1.22 })
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
function UI.Section(parent: Instance, text: string, order: number, color: Color3?): TextLabel
	return UI.Label({
		Size = UDim2.new(1, 0, 0, 30),
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color or UI.Theme.Yellow,
		LayoutOrder = order,
		MaxText = 24,
		Outline = 2.5,
		Parent = parent,
	})
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
			Padding = UDim.new(0, 6),
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
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		UI.Create("UIPadding", {
			PaddingLeft = UDim.new(0, 3),
			PaddingTop = UDim.new(0, 3),
			PaddingBottom = UDim.new(0, 3),
		}),
	})
end

-- Karte mit hellerem Hintergrund und schwarzer Kontur
function UI.Card(props: { [string]: any }): Frame
	local base: { [string]: any } = { BackgroundColor3 = UI.Theme.PanelLight }
	for key, value in pairs(props) do
		base[key] = value
	end
	return UI.Create("Frame", base, { UI.Corner(12), UI.Stroke(BLACK, 2) })
end

-- ---------------------------------------------------------------------
-- FORTSCHRITTSBALKEN (Füllung gleitet weich)
-- ---------------------------------------------------------------------
export type Bar = { Frame: Frame, Fill: Frame, Text: TextLabel, Ratio: number }

function UI.Bar(props: { [string]: any }): Bar
	local color: Color3 = props.Color or UI.Theme.Orange
	local back: Frame = UI.Create("Frame", {
		Size = props.Size or UDim2.new(1, 0, 0, 30),
		Position = props.Position or UDim2.new(),
		BackgroundColor3 = UI.Theme.PanelDark:Lerp(BLACK, 0.4), -- dunkle Rinne: die bunte Füllung leuchtet darauf
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	}, { UI.Corner(10), UI.Stroke(BLACK, 3) })
	local fill: Frame = UI.Create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = WHITE,
		Parent = back,
	}, { UI.Corner(10), UI.Create("UIGradient", { Rotation = 90, Color = UI.ButtonSequence(color) }) })
	local text = UI.Label({
		Size = UDim2.fromScale(1, 1),
		Text = "",
		MaxText = props.MaxText or 18,
		Outline = 2,
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

-- Kurzes "Aufploppen" (z.B. wenn Geld reinkommt)
function UI.Pulse(scale: UIScale, amount: number?)
	scale.Scale = 1 + (amount or 0.12)
	TweenService:Create(scale, PULSE_INFO, { Scale = 1 }):Play()
end

-- ---------------------------------------------------------------------
-- FLÜSSIG ZÄHLENDE ZAHLEN (Geld, Schritte)
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
local COUNTER_UP_COLOR = Color3.fromRGB(255, 255, 255)
local COUNTER_DOWN_COLOR = Color3.fromRGB(255, 110, 110)

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

-- Kurzer Farbblitz (weiß bei Zuwachs, rot bei Abnahme) + Aufploppen bei Zuwachs
local function popCounter(counter: Counter, up: boolean)
	local now = os.clock()
	if now - counter.PopAt < COUNTER_POP_GAP then
		return
	end
	counter.PopAt = now
	local label = counter.Label
	label.TextColor3 = counter.Color
	TweenService:Create(label, COUNTER_FLASH_INFO, { TextColor3 = if up then COUNTER_UP_COLOR else COUNTER_DOWN_COLOR })
		:Play()
	local scale = counter.Scale
	if up and scale then
		UI.Pulse(scale, 0.1)
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

-- Schreibt den Text sofort neu (z.B. wenn sich der Multiplikator in der Anzeige geändert hat)
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
-- FENSTER (immer nur eins offen; öffnen = Ploppen + Einblenden)
-- Der Inhalt steckt nur WÄHREND des Auf-/Zugehens in einer CanvasGroup (für das weiche Einblenden).
-- Danach hängt er in einem normalen Frame: Eine CanvasGroup malt bei jeder kleinen Änderung
-- (Text, Balken, Scrollen) ihren ganzen Inhalt neu und macht Schrift auf Handys unscharf.
-- ---------------------------------------------------------------------
export type Window = {
	Group: Frame, -- Halter (Position, Größe, sichtbar ja/nein)
	Fader: CanvasGroup, -- nur während der Animation benutzt
	Panel: Frame, -- der eigentliche Fensterinhalt
	Scale: UIScale,
	Content: ScrollingFrame,
	IsOpen: boolean,
	Token: number,
	OnOpen: (() -> ())?,
}

local windows: { Window } = {}
local blur: BlurEffect? = nil

local function anyWindowOpen(): boolean
	for _, win in ipairs(windows) do
		if win.IsOpen then
			return true
		end
	end
	return false
end

-- Welt hinter offenen Fenstern weichzeichnen (lokaler BlurEffect, nach dem Schließen wieder weg)
local function updateBlur()
	if anyWindowOpen() then
		local effect = blur
		if not effect or effect.Parent == nil then
			effect = UI.Create("BlurEffect", { Name = "MeteorHeistWindowBlur", Size = 0, Parent = Lighting })
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
			if blur == effect and not anyWindowOpen() then
				blur = nil
				effect:Destroy()
			end
		end)
		fade:Play()
	end
end

-- Inhalt für die Animation in die CanvasGroup hängen
local function beginFade(win: Window)
	if win.Panel.Parent ~= win.Fader then
		win.Panel.Parent = win.Fader
	end
	win.Fader.Visible = true
end

-- Animation fertig: Inhalt zurück in den normalen Frame, CanvasGroup aus
local function endFade(win: Window)
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
	TweenService:Create(win.Scale, CLOSE_INFO, { Scale = 0.86 }):Play()
	TweenService:Create(win.Group, CLOSE_INFO, { Position = UDim2.new(0.5, 0, 0.5, WINDOW_SLIDE * 0.6) }):Play()
	local fade = TweenService:Create(win.Fader, CLOSE_INFO, { GroupTransparency = 1 })
	fade.Completed:Connect(function()
		if win.Token == token then
			win.Group.Visible = false
			endFade(win)
		end
	end)
	fade:Play()
	updateBlur()
end

function UI.OpenWindow(win: Window)
	for _, other in ipairs(windows) do
		if other ~= win then
			UI.CloseWindow(other)
		end
	end
	if win.IsOpen then
		return
	end
	win.IsOpen = true
	win.Token += 1
	local token = win.Token
	beginFade(win)
	if not win.Group.Visible then
		win.Fader.GroupTransparency = 1
		win.Scale.Scale = 0.7
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
	-- federnd aufgehen (Back-Easing schießt etwas über 1 hinaus) und von unten hereingleiten
	TweenService:Create(win.Scale, OPEN_POP_INFO, { Scale = 1 }):Play()
	TweenService:Create(win.Group, OPEN_POP_INFO, { Position = UDim2.fromScale(0.5, 0.5) }):Play()
	updateBlur()
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
end

function UI.Window(title: string, width: number, height: number, color: Color3?): Window
	assert(root, "UI.Init zuerst aufrufen")
	local accent = color or UI.Theme.Orange
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
	local scale: UIScale = UI.Create("UIScale", { Scale = 0.86, Parent = group })
	local fader: CanvasGroup = UI.Create("CanvasGroup", {
		Name = "Fader",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Visible = false,
		Parent = group,
	})
	-- helle, kräftig blaue Fläche mit dicker schwarzer Kontur (Rand = Konturdicke, damit die
	-- Kontur beim Ein-/Ausblenden in der CanvasGroup nicht abgeschnitten wird)
	local panel = UI.Create("Frame", {
		Name = "Panel",
		Position = UDim2.fromOffset(WINDOW_STROKE, WINDOW_STROKE),
		Size = UDim2.new(1, -WINDOW_STROKE * 2, 1, -WINDOW_STROKE * 2),
		BackgroundColor3 = WHITE,
		Parent = group,
	}, {
		UI.Corner(20),
		UI.Stroke(BLACK, WINDOW_STROKE),
		UI.Gradient(UI.Theme.Panel:Lerp(WHITE, 0.12), UI.Theme.PanelDark),
	})
	local header = UI.Create("Frame", {
		Name = "Header",
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(1, -20, 0, 50),
		BackgroundColor3 = WHITE,
		Parent = panel,
	}, {
		UI.Corner(14),
		UI.Stroke(BLACK, 3),
		UI.Create("UIGradient", { Rotation = 90, Color = UI.ButtonSequence(accent) }),
	})
	-- Titel in GROSSBUCHSTABEN mit dicker Kontur
	UI.Label({
		Position = UDim2.fromOffset(14, 4),
		Size = UDim2.new(1, -78, 1, -8),
		Text = UI.Upper(title),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 34,
		Outline = 4,
		Parent = header,
	})
	local content: ScrollingFrame = UI.Create("ScrollingFrame", {
		Name = "Content",
		Position = UDim2.fromOffset(12, 70),
		Size = UDim2.new(1, -24, 1, -82),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = accent,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = panel,
	}, {
		UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
		UI.Create("UIPadding", {
			PaddingLeft = UDim.new(0, 3),
			PaddingRight = UDim.new(0, 12),
			PaddingTop = UDim.new(0, 3),
			PaddingBottom = UDim.new(0, 10),
		}),
	})
	local win: Window = {
		Group = group,
		Fader = fader,
		Panel = panel,
		Scale = scale,
		Content = content,
		IsOpen = false,
		Token = 0,
		OnOpen = nil,
	}
	-- Schließen: rotes Quadrat mit weißem X
	UI.Button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -5, 0.5, 0),
		Size = UDim2.fromOffset(42, 42),
		Text = "X",
		Color = UI.Theme.Red,
		MaxText = 28,
		Corner = 8,
		Parent = header,
	}, function()
		UI.CloseWindow(win)
	end)
	table.insert(windows, win)
	return win
end

-- ---------------------------------------------------------------------
-- TOASTS im Steal-a-Brainrot-Stil: KEIN Kasten – großer farbiger Text mit dicker schwarzer Kontur,
-- oben in der Mitte gestapelt (neueste unten), ploppt auf, steigt beim Gehen hoch und verblasst.
-- Normale Frames (keine CanvasGroup) + ein kleiner Vorrat, der wiederverwendet wird.
-- ---------------------------------------------------------------------
type ToastEntry = {
	Container: Frame, -- Platzhalter in der Liste (wächst/schrumpft -> andere rutschen weich nach)
	Inner: Frame, -- trägt den Text; bewegt sich + ploppt (UIScale), ohne die Liste zu verschieben
	Scale: UIScale,
	Label: TextLabel,
	LabelStroke: UIStroke,
	Height: number,
	Leaving: boolean,
	Token: number,
	Kind: string,
}

-- Textfarbe je Art
local TOAST_COLORS: { [string]: Color3 } = {
	Info = WHITE,
	Success = Color3.fromRGB(90, 255, 90),
	Error = Color3.fromRGB(255, 80, 80),
	Event = Color3.fromRGB(255, 205, 45),
	Alarm = Color3.fromRGB(255, 45, 45),
	Announce = Color3.fromRGB(110, 210, 255),
}

-- Schriftgröße je Art (wichtige Meldungen größer)
local TOAST_TEXT_SIZE: { [string]: number } = {
	Info = 24,
	Success = 26,
	Error = 26,
	Event = 26,
	Announce = 28,
	Alarm = 32,
}

-- Zu viele Toasts: zuerst fliegt der älteste mit der KLEINSTEN Wichtigkeit raus.
-- So verdrängen Ansagen an alle ("Event") nie den eigenen Diebstahl-Alarm oder eine Fehlermeldung.
local TOAST_PRIORITY: { [string]: number } = {
	Info = 1,
	Event = 1,
	Success = 2,
	Error = 2,
	Announce = 2,
	Alarm = 3,
}

local toastHolder: Frame? = nil
local TOAST_TOP = 56 -- Meldungen stehen so weit unter dem oberen Rand (unter der Banner-Leiste)
local toastCount = 0
local activeToasts: { ToastEntry } = {}
local toastPool: { ToastEntry } = {}

-- Position des Texts im Platzhalter (Mitte, damit das Aufploppen aus der Mitte kommt)
local function toastPosition(height: number, offsetY: number): UDim2
	return UDim2.new(0.5, 0, 0, height / 2 + offsetY)
end

local function newToastEntry(): ToastEntry
	local container: Frame = UI.Create("Frame", {
		Name = "Toast",
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
	})
	local toastScale: UIScale = UI.Create("UIScale", { Scale = 1 })
	local inner: Frame = UI.Create("Frame", {
		Name = "Inner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(1, 0, 0, TOAST_MIN_HEIGHT),
		BackgroundTransparency = 1,
		Parent = container,
	}, { toastScale })
	local stroke: UIStroke = UI.Create("UIStroke", {
		Color = BLACK,
		Thickness = 3,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
	local label: TextLabel = UI.Create("TextLabel", {
		Name = "Text",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, TOAST_TEXT_WIDTH, 1, 0),
		BackgroundTransparency = 1,
		Font = UI.Font,
		TextColor3 = WHITE,
		TextSize = 24,
		TextWrapped = true,
		Text = "",
		Parent = inner,
	}, { stroke })
	return {
		Container = container,
		Inner = inner,
		Scale = toastScale,
		Label = label,
		LabelStroke = stroke,
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

-- Ein-/Ausblenden über die Transparenz von Text + Kontur. Gibt den Tween des Texts zurück.
local function fadeToast(entry: ToastEntry, info: TweenInfo, transparency: number): Tween
	local textTween = TweenService:Create(entry.Label, info, { TextTransparency = transparency })
	TweenService:Create(entry.LabelStroke, info, { Transparency = transparency }):Play()
	textTween:Play()
	return textTween
end

local function setToastTransparency(entry: ToastEntry, transparency: number)
	entry.Label.TextTransparency = transparency
	entry.LabelStroke.Transparency = transparency
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
	-- steigt etwas hoch und verblasst, danach rutschen die anderen nach
	TweenService:Create(entry.Inner, TOAST_OUT_INFO, { Position = toastPosition(entry.Height, -TOAST_RISE * 2) }):Play()
	local fade = fadeToast(entry, TOAST_OUT_INFO, 1)
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

-- Meldungen tiefer setzen, solange oben etwas anderes steht (z.B. die Meteor-Run-Anzeige).
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
	local key = if kind and TOAST_COLORS[kind] then kind else "Info"
	local entry = table.remove(toastPool) or newToastEntry()
	entry.Token += 1
	entry.Leaving = false
	entry.Kind = key
	local token = entry.Token
	-- Höhe passend zum Text (lange Meldungen brechen um, statt winzig zu werden)
	local textSize = TOAST_TEXT_SIZE[key] or 24
	local bounds = TextService:GetTextSize(text, textSize, UI.Font, Vector2.new(TOAST_TEXT_WIDTH, 1000))
	local height = math.max(TOAST_MIN_HEIGHT, math.ceil(bounds.Y) + 10)
	entry.Height = height
	entry.Label.Text = text
	entry.Label.TextSize = textSize
	entry.Label.TextColor3 = TOAST_COLORS[key]
	entry.LabelStroke.Thickness = if key == "Alarm" then 4 else 3
	entry.Inner.Size = UDim2.new(1, 0, 0, height)
	entry.Inner.Position = toastPosition(height, TOAST_RISE)
	entry.Container.Size = UDim2.new(1, 0, 0, 0)
	entry.Container.LayoutOrder = toastCount
	entry.Scale.Scale = 0.5
	setToastTransparency(entry, 1)
	entry.Container.Parent = holder
	table.insert(activeToasts, entry)
	TweenService:Create(entry.Container, TOAST_GROW_INFO, { Size = UDim2.new(1, 0, 0, height + TOAST_GAP) }):Play()
	-- ploppt auf (schießt etwas über die volle Größe hinaus) und rutscht dabei an seinen Platz
	TweenService:Create(entry.Inner, TOAST_RISE_INFO, { Position = toastPosition(height, 0) }):Play()
	TweenService:Create(entry.Scale, TOAST_POP_INFO, { Scale = 1 }):Play()
	fadeToast(entry, TOAST_FADE_INFO, 0)
	while #activeToasts > MAX_TOASTS do
		removeToast(toastToDrop())
	end
	task.delay((kind == "Announce" or kind == "Event") and 7 or 4, function()
		if entry.Token == token then
			removeToast(entry)
		end
	end)
end

-- ---------------------------------------------------------------------
-- PREISE (Robux) aus dem Marktplatz – einmal laden, dann merken
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
-- LÄNDER-REGEL "Paid Random Items": Dürfen wir Zufalls-Käufe (Zufalls-Ei, Glücksrad-Drehs) zeigen?
-- Einmal fragen, dann merken. Im Zweifel/bei Fehler: NICHT zeigen.
-- ---------------------------------------------------------------------
local randomAllowed: boolean? = nil
local randomWaiting: { (boolean) -> () } = {}
local randomStarted = false

function UI.WhenRandomItemsKnown(callback: (allowed: boolean) -> ())
	if randomAllowed ~= nil then
		task.spawn(callback, randomAllowed)
		return
	end
	table.insert(randomWaiting, callback)
	if randomStarted then
		return
	end
	randomStarted = true
	task.spawn(function()
		local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, Players.LocalPlayer)
		local allowed = ok and type(info) == "table" and info.ArePaidRandomItemsRestricted == false
		randomAllowed = allowed
		local waiting = randomWaiting
		randomWaiting = {}
		for _, cb in ipairs(waiting) do
			task.spawn(cb, allowed)
		end
	end)
end

-- true/false, oder nil solange die Antwort noch nicht da ist
function UI.RandomItemsAllowed(): boolean?
	return randomAllowed
end

-- ---------------------------------------------------------------------
-- START
-- ---------------------------------------------------------------------
function UI.Init(screenGui: ScreenGui)
	root = screenGui
	UI.Root = screenGui

	-- Alles passend zur Bildschirmgröße skalieren (Handy bis großer Monitor)
	local rootScale: UIScale = UI.Create("UIScale", { Parent = screenGui })
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

	-- Meldungen oben in der Mitte (unter der Banner-Leiste des HUD)
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

	RunService.RenderStepped:Connect(stepCounters)
end

return UI
