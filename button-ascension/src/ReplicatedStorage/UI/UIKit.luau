--[[
	UIKit (ModuleScript)
	Location: ReplicatedStorage/UI/UIKit
	Depends on: UI/Theme, UI/SoundPlayer

	Declarative helpers and themed components used by every screen of the
	player UI and by the admin panel.

	UIKit.new(className, props, children)
	  * Normal keys are assigned as properties.
	  * Function values connect to the event of that name (e.g. Activated = fn).
	  * Extra keys: Corner, Stroke, Padding, Gradient, List, Grid, Aspect,
	    MinSize/MaxSize, TextMax, Scale, Children, Parent (assigned last).

	Components: label, frame, panel, button, progress, scroll, textbox, toggle,
	slider, segmented, window, confirm, prompt, attachTooltip.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local SoundPlayer = require(script.Parent.SoundPlayer)

local C = Theme.Colors
local F = Theme.Fonts
local S = Theme.TextSize

local UI = {}
UI.Theme = Theme

local SPECIAL = {
	Children = true,
	Corner = true,
	Stroke = true,
	Padding = true,
	Gradient = true,
	List = true,
	Grid = true,
	Aspect = true,
	MinSize = true,
	MaxSize = true,
	TextMax = true,
	Scale = true,
	Parent = true,
}

-- Low-level helpers ---------------------------------------------------------------

function UI.corner(inst: Instance, radius: number?): UICorner
	local c = Instance.new("UICorner")
	local r = radius or Theme.Radius.Medium
	c.CornerRadius = if r >= 999 then UDim.new(1, 0) else UDim.new(0, r)
	c.Parent = inst
	return c
end

function UI.stroke(inst: Instance, spec: any): UIStroke
	local s = Instance.new("UIStroke")
	if typeof(spec) == "Color3" then
		s.Color = spec
		s.Thickness = 1
	elseif type(spec) == "table" then
		s.Color = spec.Color or C.StrokeSoft
		s.Thickness = spec.Thickness or 1
		s.Transparency = spec.Transparency or 0
	else
		s.Color = C.StrokeSoft
		s.Thickness = 1
	end
	local textual = inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox")
	s.ApplyStrokeMode = if type(spec) == "table" and spec.Text then Enum.ApplyStrokeMode.Contextual
		elseif textual then Enum.ApplyStrokeMode.Border
		else Enum.ApplyStrokeMode.Contextual
	s.Parent = inst
	return s
end

function UI.padding(inst: Instance, spec: any): UIPadding
	local p = Instance.new("UIPadding")
	local l, r, t, b
	if type(spec) == "number" then
		l, r, t, b = spec, spec, spec, spec
	elseif type(spec) == "table" then
		if spec.X or spec.Y then
			l, r, t, b = spec.X or 0, spec.X or 0, spec.Y or 0, spec.Y or 0
		else
			l, r, t, b = spec[1] or 0, spec[2] or 0, spec[3] or 0, spec[4] or 0
		end
	end
	p.PaddingLeft = UDim.new(0, l or 0)
	p.PaddingRight = UDim.new(0, r or 0)
	p.PaddingTop = UDim.new(0, t or 0)
	p.PaddingBottom = UDim.new(0, b or 0)
	p.Parent = inst
	return p
end

function UI.gradient(inst: Instance, spec: any): UIGradient
	local g = Instance.new("UIGradient")
	if typeof(spec) == "ColorSequence" then
		g.Color = spec
		g.Rotation = 90
	elseif type(spec) == "table" then
		if spec.Color then
			g.Color = spec.Color
		end
		if spec.Transparency then
			g.Transparency = spec.Transparency
		end
		g.Rotation = spec.Rotation or 90
	end
	g.Parent = inst
	return g
end

local ALIGN_H = {
	Left = Enum.HorizontalAlignment.Left,
	Center = Enum.HorizontalAlignment.Center,
	Right = Enum.HorizontalAlignment.Right,
}
local ALIGN_V = {
	Top = Enum.VerticalAlignment.Top,
	Center = Enum.VerticalAlignment.Center,
	Bottom = Enum.VerticalAlignment.Bottom,
}

function UI.list(inst: Instance, spec: any): UIListLayout
	local l = Instance.new("UIListLayout")
	spec = spec or {}
	l.FillDirection = if spec.Dir == "X" then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	l.Padding = UDim.new(0, spec.Pad or 8)
	l.HorizontalAlignment = ALIGN_H[spec.HA or "Left"]
	l.VerticalAlignment = ALIGN_V[spec.VA or "Top"]
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = inst
	return l
end

function UI.grid(inst: Instance, spec: any): UIGridLayout
	local g = Instance.new("UIGridLayout")
	g.CellSize = spec.Cell or UDim2.fromOffset(100, 100)
	g.CellPadding = spec.Pad or UDim2.fromOffset(8, 8)
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.HorizontalAlignment = ALIGN_H[spec.HA or "Left"]
	g.Parent = inst
	return g
end

function UI.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local p = props or {}
	for key, value in pairs(p) do
		if not SPECIAL[key] then
			if type(value) == "function" then
				(inst :: any)[key]:Connect(value)
			else
				(inst :: any)[key] = value
			end
		end
	end
	if p.Corner then
		UI.corner(inst, if p.Corner == true then nil else p.Corner)
	end
	if p.Stroke then
		UI.stroke(inst, if p.Stroke == true then nil else p.Stroke)
	end
	if p.Padding then
		UI.padding(inst, p.Padding)
	end
	if p.Gradient then
		UI.gradient(inst, p.Gradient)
	end
	if p.List then
		UI.list(inst, if p.List == true then nil else p.List)
	end
	if p.Grid then
		UI.grid(inst, p.Grid)
	end
	if p.Aspect then
		local a = Instance.new("UIAspectRatioConstraint")
		a.AspectRatio = p.Aspect
		a.Parent = inst
	end
	if p.MinSize or p.MaxSize then
		local c = Instance.new("UISizeConstraint")
		c.MinSize = p.MinSize or Vector2.new(0, 0)
		c.MaxSize = p.MaxSize or Vector2.new(math.huge, math.huge)
		c.Parent = inst
	end
	if p.TextMax then
		local c = Instance.new("UITextSizeConstraint")
		c.MaxTextSize = p.TextMax
		c.Parent = inst
	end
	if p.Scale then
		local s = Instance.new("UIScale")
		s.Scale = p.Scale
		s.Parent = inst
	end
	for _, child in ipairs(p.Children or {}) do
		child.Parent = inst
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if p.Parent then
		inst.Parent = p.Parent
	end
	return inst
end

local function merge(defaults: { [string]: any }, props: { [string]: any }?): { [string]: any }
	local out = table.clone(defaults)
	for k, v in pairs(props or {}) do
		out[k] = v
	end
	return out
end
UI.merge = merge

-- Motion ---------------------------------------------------------------------------

-- Tweens unless reduced motion is on (then the end state is applied instantly).
function UI.tween(inst: Instance, goal: { [string]: any }, info: TweenInfo?, force: boolean?): Tween?
	if Theme.ReducedMotion and not force then
		for k, v in pairs(goal) do
			(inst :: any)[k] = v
		end
		return nil
	end
	local tween = TweenService:Create(inst, info or Theme.Motion.Normal, goal)
	tween:Play()
	return tween
end

-- Viewport / layering ----------------------------------------------------------------

function UI.viewport(): Vector2
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end

function UI.isCompact(): boolean
	local v = UI.viewport()
	return v.X < 900 or v.Y < 560
end

function UI.onViewportChanged(fn: () -> ()): RBXScriptConnection?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	return camera:GetPropertyChangedSignal("ViewportSize"):Connect(fn)
end

-- Scale that fits a base-size box into the viewport with margins.
function UI.fitScale(width: number, height: number, marginX: number?, marginY: number?): number
	local v = UI.viewport()
	local sx = (v.X * (marginX or 0.94)) / width
	local sy = (v.Y * (marginY or 0.88)) / height
	local fits = math.min(sx, sy)
	-- The UI Scale setting may shrink windows freely but never push them off-screen.
	return math.clamp(math.min(math.min(fits, 1.15) * Theme.UserScale, fits), 0.45, 1.6)
end

local overlayGui: ScreenGui? = nil
function UI.overlay(): ScreenGui
	if overlayGui and overlayGui.Parent then
		return overlayGui
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "UIKitOverlay"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	overlayGui = gui
	return gui
end

-- Components ---------------------------------------------------------------------------

function UI.label(props: { [string]: any }?): TextLabel
	return UI.new(
		"TextLabel",
		merge({
			BackgroundTransparency = 1,
			Font = F.Medium,
			TextColor3 = C.Text,
			TextSize = S.Body,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			Size = UDim2.new(1, 0, 0, 22),
			RichText = false,
		}, props)
	)
end

function UI.frame(props: { [string]: any }?): Frame
	return UI.new("Frame", merge({ BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, props))
end

function UI.panel(props: { [string]: any }?): Frame
	return UI.new(
		"Frame",
		merge({
			BackgroundColor3 = C.Panel,
			BorderSizePixel = 0,
			Corner = Theme.Radius.Medium,
			Stroke = { Color = C.StrokeSoft, Thickness = 1 },
		}, props)
	)
end

local VARIANTS = {
	primary = { Bg = C.Accent, Text = C.White, Stroke = Theme.lighten(C.Accent, 0.25) },
	secondary = { Bg = C.PanelLighter, Text = C.Text, Stroke = C.Stroke },
	ghost = { Bg = C.PanelLight, Text = C.TextDim, Stroke = C.StrokeSoft },
	success = { Bg = Color3.fromRGB(34, 170, 100), Text = C.White, Stroke = C.Success },
	danger = { Bg = Color3.fromRGB(200, 40, 60), Text = C.White, Stroke = C.Danger },
	gold = { Bg = C.Gold, Text = Color3.fromRGB(40, 28, 0), Stroke = Theme.lighten(C.Gold, 0.3) },
	cyan = { Bg = Color3.fromRGB(30, 150, 190), Text = C.White, Stroke = C.Accent2 },
	violet = { Bg = Color3.fromRGB(120, 60, 200), Text = C.White, Stroke = C.Accent3 },
}
UI.Variants = VARIANTS

local buttonMeta = setmetatable({}, { __mode = "k" })
local lastHoverSound = 0

local function applyVariant(button: TextButton, variant: string)
	local v = VARIANTS[variant] or VARIANTS.secondary
	local meta = buttonMeta[button]
	if meta then
		meta.Variant = variant
	end
	button.BackgroundColor3 = v.Bg
	button.TextColor3 = v.Text
	local stroke = button:FindFirstChild("Border")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Color = v.Stroke
	end
end

--[[
	props: Text, Icon, Variant, OnClick, Disabled, Tooltip, Sound, Radius, plus any
	TextButton property (Size, Position, AnchorPoint, LayoutOrder, Parent, TextSize...).
]]
function UI.button(props: { [string]: any }): TextButton
	local variant = props.Variant or "secondary"
	local onClick = props.OnClick
	local text = props.Text or ""
	if props.Icon then
		text = if text ~= "" then props.Icon .. "  " .. text else props.Icon
	end
	local clean = {}
	for k, v in pairs(props) do
		if k ~= "Variant" and k ~= "OnClick" and k ~= "Icon" and k ~= "Disabled" and k ~= "Tooltip" and k ~= "Sound" and k ~= "Radius" then
			clean[k] = v
		end
	end
	clean.Text = text
	local button = UI.new(
		"TextButton",
		merge({
			AutoButtonColor = false,
			BorderSizePixel = 0,
			Font = F.Bold,
			TextSize = S.Body,
			Size = UDim2.fromOffset(140, 40),
			Selectable = true,
		}, clean)
	)
	UI.corner(button, props.Radius or Theme.Radius.Small + 2)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Border"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 1
	stroke.Transparency = 0.2
	stroke.Parent = button
	local scale = Instance.new("UIScale")
	scale.Name = "PressScale"
	scale.Parent = button
	UI.gradient(button, {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 215)),
		Rotation = 90,
	})

	buttonMeta[button] = { Variant = variant, Hover = false }
	applyVariant(button, variant)

	local function hover(on: boolean)
		local meta = buttonMeta[button]
		if not meta then
			return
		end
		meta.Hover = on
		local v = VARIANTS[meta.Variant] or VARIANTS.secondary
		if button:GetAttribute("Disabled") then
			return
		end
		UI.tween(scale, { Scale = if on then 1.04 else 1 }, Theme.Motion.Fast)
		UI.tween(button, { BackgroundColor3 = if on then Theme.lighten(v.Bg, 0.1) else v.Bg }, Theme.Motion.Fast)
		if on and os.clock() - lastHoverSound > 0.06 then
			lastHoverSound = os.clock()
			SoundPlayer.play("UIHover")
		end
	end
	button.MouseEnter:Connect(function()
		hover(true)
	end)
	button.MouseLeave:Connect(function()
		hover(false)
	end)
	button.SelectionGained:Connect(function()
		hover(true)
	end)
	button.SelectionLost:Connect(function()
		hover(false)
	end)
	button.MouseButton1Down:Connect(function()
		if not button:GetAttribute("Disabled") then
			UI.tween(scale, { Scale = 0.95 }, Theme.Motion.Fast)
		end
	end)
	button.MouseButton1Up:Connect(function()
		local meta = buttonMeta[button]
		UI.tween(scale, { Scale = if meta and meta.Hover then 1.04 else 1 }, Theme.Motion.Fast)
	end)
	button.Activated:Connect(function()
		if button:GetAttribute("Disabled") then
			SoundPlayer.play("Error")
			return
		end
		SoundPlayer.play(props.Sound or "UIClick")
		if onClick then
			onClick(button)
		end
	end)
	if props.Disabled then
		UI.setEnabled(button, false)
	end
	if props.Tooltip then
		UI.attachTooltip(button, props.Tooltip)
	end
	return button
end

function UI.setEnabled(button: TextButton, enabled: boolean)
	button:SetAttribute("Disabled", not enabled)
	button.BackgroundTransparency = if enabled then 0 else 0.45
	button.TextTransparency = if enabled then 0 else 0.4
	local scale = button:FindFirstChild("PressScale")
	if scale and scale:IsA("UIScale") and not enabled then
		scale.Scale = 1
	end
end

function UI.setVariant(button: TextButton, variant: string)
	applyVariant(button, variant)
end

function UI.setText(button: TextButton, text: string, icon: string?)
	button.Text = if icon then icon .. "  " .. text else text
end

--[[ Progress bar. Returns { Frame, Fill, Label, Set(fraction, text?) } ]]
function UI.progress(props: { [string]: any })
	local frame = UI.new("Frame", {
		Name = props.Name or "Progress",
		Size = props.Size or UDim2.new(1, 0, 0, 14),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		BackgroundColor3 = props.Background or C.BackgroundAlt,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Corner = props.Radius or Theme.Radius.Pill,
		Stroke = { Color = C.StrokeSoft, Transparency = 0.3 },
		Parent = props.Parent,
	})
	local fill = UI.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = props.Color or C.Accent,
		BorderSizePixel = 0,
		Corner = props.Radius or Theme.Radius.Pill,
		Parent = frame,
	})
	UI.gradient(fill, { Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 210)), Rotation = 90 })
	local label = UI.label({
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = props.TextSize or S.Tiny,
		Font = F.Bold,
		ZIndex = 3,
		Parent = frame,
	})
	UI.stroke(label, { Color = C.Black, Thickness = 1, Transparency = 0.5, Text = true })
	local bar = { Frame = frame, Fill = fill, Label = label }
	function bar.Set(fraction: number, text: string?)
		local f = math.clamp(if fraction == fraction then fraction else 0, 0, 1)
		UI.tween(fill, { Size = UDim2.fromScale(f, 1) }, Theme.Motion.Normal)
		if text then
			label.Text = text
		end
	end
	function bar.SetColor(color: Color3)
		fill.BackgroundColor3 = color
	end
	return bar
end

function UI.scroll(props: { [string]: any }?): ScrollingFrame
	return UI.new(
		"ScrollingFrame",
		merge({
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 5,
			ScrollBarImageColor3 = C.Stroke,
			ScrollBarImageTransparency = 0.2,
			VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
			ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		}, props)
	)
end

--[[ props: Placeholder, Text, OnChanged(text), OnSubmit(text), MaxLength, + TextBox props ]]
function UI.textbox(props: { [string]: any }): TextBox
	local onChanged = props.OnChanged
	local onSubmit = props.OnSubmit
	local maxLength = props.MaxLength
	local clean = {}
	for k, v in pairs(props) do
		if k ~= "OnChanged" and k ~= "OnSubmit" and k ~= "Placeholder" and k ~= "MaxLength" then
			clean[k] = v
		end
	end
	local box = UI.new(
		"TextBox",
		merge({
			BackgroundColor3 = C.BackgroundAlt,
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			Font = F.Medium,
			TextSize = S.Body,
			TextColor3 = C.Text,
			PlaceholderColor3 = C.TextMuted,
			PlaceholderText = props.Placeholder or "",
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 38),
			Corner = Theme.Radius.Small + 2,
			Padding = { X = 12 },
		}, clean)
	)
	local stroke = UI.stroke(box, { Color = C.StrokeSoft })
	box.Focused:Connect(function()
		UI.tween(stroke, { Color = C.Accent2 }, Theme.Motion.Fast)
	end)
	box.FocusLost:Connect(function(enterPressed)
		UI.tween(stroke, { Color = C.StrokeSoft }, Theme.Motion.Fast)
		if enterPressed and onSubmit then
			onSubmit(box.Text)
		end
	end)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		if maxLength and #box.Text > maxLength then
			box.Text = string.sub(box.Text, 1, maxLength)
			return
		end
		if onChanged then
			onChanged(box.Text)
		end
	end)
	return box
end

--[[ Toggle switch. props: Value, OnChange(value), Parent, Position, LayoutOrder ]]
function UI.toggle(props: { [string]: any })
	local value = props.Value == true
	local button = UI.new("TextButton", {
		Name = props.Name or "Toggle",
		Size = UDim2.fromOffset(54, 28),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = C.PanelLighter,
		Corner = Theme.Radius.Pill,
		Stroke = { Color = C.Stroke },
		Parent = props.Parent,
	})
	local knob = UI.new("Frame", {
		Size = UDim2.fromOffset(22, 22),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		BackgroundColor3 = C.Text,
		Corner = Theme.Radius.Pill,
		Parent = button,
	})
	local toggle = { Instance = button }
	local function render(animate: boolean)
		local goalPos = if value then UDim2.new(1, -25, 0.5, 0) else UDim2.new(0, 3, 0.5, 0)
		local goalColor = if value then C.Success else C.PanelLighter
		if animate then
			UI.tween(knob, { Position = goalPos }, Theme.Motion.Fast)
			UI.tween(button, { BackgroundColor3 = goalColor }, Theme.Motion.Fast)
		else
			knob.Position = goalPos
			button.BackgroundColor3 = goalColor
		end
	end
	function toggle.Set(v: boolean)
		value = v == true
		render(false)
	end
	button.Activated:Connect(function()
		value = not value
		render(true)
		SoundPlayer.play("UIClick")
		if props.OnChange then
			props.OnChange(value)
		end
	end)
	render(false)
	return toggle
end

--[[
	Slider with − / + buttons (for gamepad and precise input).
	props: Min, Max, Step, Value, OnChange(value), OnCommit(value), Format(value) -> string, Width
	OnChange fires continuously while dragging; OnCommit once the drag ends or a − / + press lands.
]]
function UI.slider(props: { [string]: any })
	local min, max, step = props.Min or 0, props.Max or 1, props.Step or 0.05
	local value = math.clamp(props.Value or min, min, max)
	local width = props.Width or 260
	local root = UI.frame({
		Name = props.Name or "Slider",
		Size = UDim2.fromOffset(width, 30),
		LayoutOrder = props.LayoutOrder,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Parent = props.Parent,
	})
	local slider = { Instance = root }
	local minus, plus
	local track = UI.new("TextButton", {
		Name = "Track",
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.new(1, -110, 0, 8),
		Position = UDim2.new(0, 34, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = C.PanelLighter,
		Corner = Theme.Radius.Pill,
		Selectable = false,
		Parent = root,
	})
	local fill = UI.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.Accent2,
		Corner = Theme.Radius.Pill,
		Parent = track,
	})
	local knob = UI.new("Frame", {
		Size = UDim2.fromOffset(18, 18),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		BackgroundColor3 = C.Text,
		Corner = Theme.Radius.Pill,
		Stroke = { Color = C.Accent2, Thickness = 2 },
		Parent = track,
	})
	local valueLabel = UI.label({
		Size = UDim2.fromOffset(44, 30),
		Position = UDim2.new(1, -44, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = F.Bold,
		TextSize = S.Small,
		TextColor3 = C.TextDim,
		Parent = root,
	})
	local function render()
		local f = (value - min) / (max - min)
		fill.Size = UDim2.fromScale(f, 1)
		knob.Position = UDim2.fromScale(f, 0.5)
		valueLabel.Text = if props.Format then props.Format(value) else tostring(value)
	end
	local function set(v: number, fire: boolean)
		local stepped = math.floor((v - min) / step + 0.5) * step + min
		local clamped = math.clamp(stepped, min, max)
		if math.abs(clamped - value) < 1e-9 then
			return
		end
		value = clamped
		render()
		if fire and props.OnChange then
			props.OnChange(value)
		end
	end
	function slider.Set(v: number)
		value = math.clamp(v, min, max)
		render()
	end
	function slider.Get(): number
		return value
	end
	local dragging = false
	local function commit()
		if props.OnCommit then
			props.OnCommit(value)
		end
	end
	local function fromInput(x: number)
		local absPos = track.AbsolutePosition.X
		local absSize = math.max(1, track.AbsoluteSize.X)
		set(min + (max - min) * math.clamp((x - absPos) / absSize, 0, 1), true)
	end
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			fromInput(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			fromInput(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			commit()
		end
	end)
	minus = UI.button({
		Text = "−",
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Variant = "ghost",
		TextSize = 18,
		OnClick = function()
			set(value - step, true)
			commit()
		end,
		Parent = root,
	})
	plus = UI.button({
		Text = "+",
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(1, -72, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Variant = "ghost",
		TextSize = 18,
		OnClick = function()
			set(value + step, true)
			commit()
		end,
		Parent = root,
	})
	slider.Minus, slider.Plus = minus, plus
	render()
	return slider
end

--[[ Segmented control. props: Options = { { Id, Text } }, Value, OnChange(id), ButtonWidth ]]
function UI.segmented(props: { [string]: any })
	local root = UI.new("Frame", {
		Name = props.Name or "Segmented",
		BackgroundColor3 = C.BackgroundAlt,
		-- Buttons + 4 px gaps between them + 4 px padding on each side.
		Size = props.Size or UDim2.fromOffset(#props.Options * (props.ButtonWidth or 70) + (#props.Options - 1) * 4 + 8, 34),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		Corner = Theme.Radius.Small + 2,
		Stroke = { Color = C.StrokeSoft },
		Padding = 4,
		List = { Dir = "X", Pad = 4, VA = "Center" },
		Parent = props.Parent,
	})
	local control = { Instance = root, Buttons = {} }
	local current = props.Value
	local function render()
		for id, button in pairs(control.Buttons) do
			UI.setVariant(button, if id == current then "primary" else "ghost")
		end
	end
	for index, option in ipairs(props.Options) do
		local button = UI.button({
			Text = option.Text,
			Size = UDim2.new(0, props.ButtonWidth or 70, 1, 0),
			LayoutOrder = index,
			TextSize = S.Small,
			Variant = "ghost",
			OnClick = function()
				current = option.Id
				render()
				if props.OnChange then
					props.OnChange(option.Id)
				end
			end,
			Parent = root,
		})
		control.Buttons[option.Id] = button
	end
	function control.Set(id)
		current = id
		render()
	end
	function control.Get()
		return current
	end
	render()
	return control
end

-- Tooltip ----------------------------------------------------------------------------------

local tooltip: Frame? = nil
local tooltipLabel: TextLabel? = nil
local tooltipOwner: Instance? = nil

local function ensureTooltip()
	if tooltip and tooltip.Parent then
		return
	end
	tooltip = UI.new("Frame", {
		Name = "Tooltip",
		BackgroundColor3 = C.BackgroundAlt,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		Visible = false,
		ZIndex = 200,
		Corner = Theme.Radius.Small,
		Stroke = { Color = C.Stroke },
		Padding = { X = 10, Y = 8 },
		MaxSize = Vector2.new(320, 400),
		Parent = UI.overlay(),
	})
	tooltipLabel = UI.label({
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		TextWrapped = true,
		RichText = true,
		TextSize = S.Small,
		ZIndex = 201,
		Parent = tooltip,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(300, 400), Parent = tooltipLabel })
end

local function positionTooltip()
	if not tooltip or not tooltip.Visible then
		return
	end
	local mouse = UserInputService:GetMouseLocation()
	local v = UI.viewport()
	local size = tooltip.AbsoluteSize
	local x = math.min(mouse.X + 16, v.X - size.X - 8)
	local y = math.min(mouse.Y + 16, v.Y - size.Y - 8)
	tooltip.Position = UDim2.fromOffset(x, y)
end

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		positionTooltip()
	end
end)

function UI.showTooltip(owner: Instance, text: string)
	ensureTooltip()
	tooltipOwner = owner
	local tip = tooltip :: Frame
	local label = tooltipLabel :: TextLabel
	label.Text = text
	tip.Visible = true
	if owner:IsA("GuiObject") and GuiService.SelectedObject == owner then
		local pos = owner.AbsolutePosition
		tip.Position = UDim2.fromOffset(pos.X + owner.AbsoluteSize.X + 8, pos.Y)
	else
		positionTooltip()
	end
end

function UI.hideTooltip(owner: Instance?)
	if tooltip and (owner == nil or owner == tooltipOwner) then
		tooltip.Visible = false
		tooltipOwner = nil
	end
end

-- provider: a string or a function returning a (rich text) string.
function UI.attachTooltip(gui: GuiObject, provider: any)
	local function text(): string?
		if type(provider) == "function" then
			return provider()
		end
		return provider
	end
	local function show()
		local t = text()
		if t and t ~= "" then
			UI.showTooltip(gui, t)
		end
	end
	gui.MouseEnter:Connect(show)
	gui.SelectionGained:Connect(show)
	gui.MouseLeave:Connect(function()
		UI.hideTooltip(gui)
	end)
	gui.SelectionLost:Connect(function()
		UI.hideTooltip(gui)
	end)
	gui.AncestryChanged:Connect(function()
		if not gui:IsDescendantOf(game) then
			UI.hideTooltip(gui)
		end
	end)
end

-- Windows ---------------------------------------------------------------------------------

--[[
	A modal window with a dimmed backdrop, header and body.
	props: Parent, Name, Title, Subtitle, Icon, Size (Vector2 base size),
	       CompactSize (Vector2 for small screens), Accent, Palette, OnClose
	Returns { Root, Panel, Body, Header, Open(), Close(), Toggle(), IsOpen(), SetTitle(), Opened, Closed }
]]
function UI.window(props: { [string]: any })
	local palette = props.Palette or C
	local accent = props.Accent or palette.Accent or C.Accent
	local base = props.Size or Vector2.new(920, 600)
	local compactBase = props.CompactSize or Vector2.new(760, 470)

	local root = UI.frame({
		Name = props.Name or "Window",
		Visible = false,
		ZIndex = 10,
		Parent = props.Parent,
	})
	local dim = UI.new("TextButton", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Black,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
		ZIndex = 10,
		Parent = root,
	})
	local panel = UI.new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(base.X, base.Y),
		BackgroundColor3 = palette.Panel or C.Panel,
		BorderSizePixel = 0,
		ZIndex = 11,
		Active = true,
		Corner = Theme.Radius.Large,
		Stroke = { Color = palette.Stroke or C.Stroke, Thickness = 1.5 },
		Parent = root,
	})
	UI.gradient(panel, {
		Color = ColorSequence.new(Theme.lighten(palette.Panel or C.Panel, 0.06), palette.Panel or C.Panel),
		Rotation = 90,
	})
	local fit = Instance.new("UIScale")
	fit.Name = "Fit"
	fit.Parent = panel

	-- Accent line along the top edge.
	UI.new("Frame", {
		Name = "AccentLine",
		Size = UDim2.new(0.4, 0, 0, 3),
		Position = UDim2.new(0.3, 0, 0, 0),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		ZIndex = 12,
		Corner = Theme.Radius.Pill,
		Gradient = {
			Color = ColorSequence.new(accent),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Rotation = 0,
		},
		Parent = panel,
	})

	local header = UI.frame({ Name = "Header", Size = UDim2.new(1, 0, 0, 64), ZIndex = 12, Parent = panel })
	UI.padding(header, { 22, 16, 12, 0 })
	local icon = UI.label({
		Name = "Icon",
		Text = props.Icon or "",
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.fromOffset(0, 2),
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 12,
		Parent = header,
	})
	local title = UI.label({
		Name = "Title",
		Text = props.Title or "",
		Font = F.Heading,
		TextSize = S.Title,
		Size = UDim2.new(1, -120, 0, 28),
		Position = UDim2.fromOffset(if props.Icon then 48 else 0, 0),
		ZIndex = 12,
		Parent = header,
	})
	local subtitle = UI.label({
		Name = "Subtitle",
		Text = props.Subtitle or "",
		TextColor3 = palette.TextDim or C.TextDim,
		TextSize = S.Small,
		Size = UDim2.new(1, -120, 0, 18),
		Position = UDim2.fromOffset(if props.Icon then 48 else 0, 28),
		ZIndex = 12,
		Parent = header,
	})
	if not props.Icon then
		icon.Visible = false
	end

	local window: { [string]: any } = {
		Root = root,
		Panel = panel,
		Header = header,
		Opened = Instance.new("BindableEvent"),
		Closed = Instance.new("BindableEvent"),
	}
	local open = false

	local close = UI.button({
		Name = "Close",
		Text = "✕",
		Size = UDim2.fromOffset(40, 40),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Variant = "ghost",
		TextSize = 18,
		ZIndex = 13,
		OnClick = function()
			window.Close()
		end,
		Parent = header,
	})
	window.CloseButton = close

	local body = UI.frame({
		Name = "Body",
		Size = UDim2.new(1, -36, 1, -82),
		Position = UDim2.fromOffset(18, 70),
		ZIndex = 12,
		Parent = panel,
	})
	window.Body = body

	local function refit()
		local compact = UI.isCompact()
		local size = if compact then compactBase else base
		panel.Size = UDim2.fromOffset(size.X, size.Y)
		fit.Scale = UI.fitScale(size.X, size.Y)
		root:SetAttribute("Compact", compact)
	end
	refit()
	UI.onViewportChanged(refit)
	window.Refit = refit

	function window.SetTitle(text: string, sub: string?)
		title.Text = text
		if sub then
			subtitle.Text = sub
		end
	end

	function window.IsOpen(): boolean
		return open
	end

	function window.Open()
		if open then
			return
		end
		open = true
		refit()
		root.Visible = true
		dim.BackgroundTransparency = 1
		local targetScale = fit.Scale
		fit.Scale = targetScale * 0.92
		UI.tween(fit, { Scale = targetScale }, Theme.Motion.Pop)
		UI.tween(dim, { BackgroundTransparency = 0.45 }, Theme.Motion.Normal)
		SoundPlayer.play("UIOpen")
		window.Opened:Fire()
		if UserInputService.GamepadEnabled then
			task.defer(function()
				if open then
					GuiService:Select(body)
				end
			end)
		end
	end

	function window.Close()
		if not open then
			return
		end
		open = false
		UI.hideTooltip()
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(root) then
			GuiService.SelectedObject = nil
		end
		local t = UI.tween(fit, { Scale = fit.Scale * 0.94 }, Theme.Motion.Fast)
		UI.tween(dim, { BackgroundTransparency = 1 }, Theme.Motion.Fast)
		if t then
			t.Completed:Wait()
		end
		-- Reopened during the close animation: stay open and don't report a close.
		if open then
			return
		end
		root.Visible = false
		window.Closed:Fire()
		if props.OnClose then
			props.OnClose()
		end
	end

	function window.Toggle()
		if open then
			window.Close()
		else
			window.Open()
		end
	end

	dim.Activated:Connect(function()
		window.Close()
	end)

	return window
end

-- Modal dialogs -----------------------------------------------------------------------------

local function dialog(props: { [string]: any }, withInput: boolean): (boolean, string?)
	local palette = props.Palette or C
	local gui = UI.overlay()
	local root = UI.frame({ Name = "Dialog", ZIndex = 150, Parent = gui })
	local dim = UI.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Black,
		BackgroundTransparency = 0.4,
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
		ZIndex = 150,
		Parent = root,
	})
	local height = if withInput then 250 else 210
	local box = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(440, height),
		BackgroundColor3 = palette.Panel or C.Panel,
		ZIndex = 151,
		Active = true,
		Corner = Theme.Radius.Large,
		Stroke = { Color = if props.Danger then C.Danger else (palette.Stroke or C.Stroke), Thickness = 1.5 },
		Padding = 20,
		Scale = UI.fitScale(440, height, 0.9, 0.8),
		Parent = root,
	})
	UI.label({
		Text = props.Title or "Are you sure?",
		Font = F.Heading,
		TextSize = S.Heading + 2,
		Size = UDim2.new(1, 0, 0, 28),
		ZIndex = 152,
		TextColor3 = if props.Danger then Theme.lighten(C.Danger, 0.2) else C.Text,
		Parent = box,
	})
	UI.label({
		Text = props.Message or "",
		TextColor3 = palette.TextDim or C.TextDim,
		TextSize = S.Body,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, 70),
		Position = UDim2.fromOffset(0, 36),
		ZIndex = 152,
		Parent = box,
	})
	local input: TextBox? = nil
	if withInput then
		input = UI.textbox({
			Placeholder = props.Placeholder or "",
			Text = props.Default or "",
			MaxLength = props.MaxLength or 200,
			Size = UDim2.new(1, 0, 0, 38),
			Position = UDim2.fromOffset(0, 112),
			ZIndex = 152,
			Parent = box,
		})
	end
	local thread = coroutine.running()
	local finished = false
	local function finish(result: boolean)
		if finished then
			return
		end
		finished = true
		local text = if input then input.Text else nil
		root:Destroy()
		task.spawn(thread, result, text)
	end
	local confirm = UI.button({
		Text = props.ConfirmText or "Confirm",
		Variant = if props.Danger then "danger" else "primary",
		Size = UDim2.new(0.5, -6, 0, 42),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		ZIndex = 152,
		OnClick = function()
			if props.RequireText and input and string.lower(input.Text) ~= string.lower(props.RequireText) then
				SoundPlayer.play("Error")
				return
			end
			finish(true)
		end,
		Parent = box,
	})
	local cancel = UI.button({
		Text = props.CancelText or "Cancel",
		Variant = "ghost",
		Size = UDim2.new(0.5, -6, 0, 42),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		ZIndex = 152,
		OnClick = function()
			finish(false)
		end,
		Parent = box,
	})
	dim.Activated:Connect(function()
		finish(false)
	end)
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = cancel
	end
	if input and not UserInputService.GamepadEnabled then
		input:CaptureFocus()
	end
	local _ = confirm
	local result, text = coroutine.yield()
	return result, text
end

--[[ Yields until the player answers. props: Title, Message, ConfirmText, CancelText, Danger ]]
function UI.confirm(props: { [string]: any }): boolean
	local result = dialog(props, props.RequireText ~= nil)
	return result
end

--[[ Yields; returns the entered text or nil if cancelled. props: Title, Message, Placeholder, Default, MaxLength ]]
function UI.prompt(props: { [string]: any }): string?
	local ok, text = dialog(props, true)
	if ok then
		return text
	end
	return nil
end

return UI
