-- Tiny UI toolkit: chunky cartoon style (thick dark outlines, rounded panels, bouncy buttons)
-- matching the reference screenshots.

local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local Kit = {}

Kit.Font = Enum.Font.FredokaOne
Kit.Colors = {
	Panel = Color3.fromRGB(28, 32, 58),
	PanelLight = Color3.fromRGB(44, 50, 86),
	PanelDark = Color3.fromRGB(18, 20, 38),
	Outline = Color3.fromRGB(14, 14, 24),
	Green = Color3.fromRGB(88, 220, 70),
	GreenDark = Color3.fromRGB(40, 150, 40),
	Blue = Color3.fromRGB(60, 160, 255),
	BlueDark = Color3.fromRGB(30, 100, 210),
	Red = Color3.fromRGB(240, 60, 60),
	RedDark = Color3.fromRGB(170, 30, 40),
	Yellow = Color3.fromRGB(255, 210, 60),
	YellowDark = Color3.fromRGB(215, 150, 20),
	Purple = Color3.fromRGB(170, 90, 255),
	PurpleDark = Color3.fromRGB(110, 50, 200),
	Orange = Color3.fromRGB(255, 150, 50),
	OrangeDark = Color3.fromRGB(210, 95, 20),
	Pink = Color3.fromRGB(255, 90, 170),
	White = Color3.fromRGB(255, 255, 255),
	Gray = Color3.fromRGB(120, 125, 140),
	Money = Color3.fromRGB(110, 255, 90),
}

function Kit.new(className: string, props, children)
	local inst = Instance.new(className)
	for key, value in pairs(props or {}) do
		if key ~= "Parent" then
			(inst :: any)[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function Kit.corner(parent: Instance, radius: number?)
	return Kit.new("UICorner", { CornerRadius = UDim.new(0, radius or 12), Parent = parent })
end

function Kit.stroke(parent: Instance, thickness: number?, color: Color3?, mode: Enum.ApplyStrokeMode?)
	return Kit.new("UIStroke", {
		Thickness = thickness or 3,
		Color = color or Kit.Colors.Outline,
		ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

function Kit.gradient(parent: Instance, top: Color3, bottom: Color3)
	return Kit.new("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = 90,
		Parent = parent,
	})
end

function Kit.padding(parent: Instance, px: number)
	return Kit.new("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		Parent = parent,
	})
end

function Kit.list(parent: Instance, padding: number?, horizontal: boolean?, align)
	return Kit.new("UIListLayout", {
		Padding = UDim.new(0, padding or 6),
		FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Parent = parent,
	})
end

-- Outlined cartoon text.
function Kit.label(props)
	local label = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Kit.Font,
		TextColor3 = props.Color or Kit.Colors.White,
		TextScaled = props.TextSize == nil,
		TextSize = props.TextSize or 14,
		Text = props.Text or "",
		RichText = true,
		TextXAlignment = props.XAlign or Enum.TextXAlignment.Center,
		TextYAlignment = props.YAlign or Enum.TextYAlignment.Center,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.Anchor or Vector2.new(),
		LayoutOrder = props.Order or 0,
		Name = props.Name or "Label",
		ZIndex = props.Z or 1,
		Parent = props.Parent,
	})
	if props.Stroke ~= false then
		Kit.stroke(label, props.StrokeThickness or 2.5, props.StrokeColor)
	end
	if props.MaxTextSize then
		Kit.new("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize, Parent = label })
	end
	return label
end

local clickSound
local function playClick()
	if not clickSound then
		clickSound = Instance.new("Sound")
		clickSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
		clickSound.Volume = 0.35
		clickSound.Parent = SoundService
	end
	SoundService:PlayLocalSound(clickSound)
end

-- Chunky button with a darker bottom edge and a bounce on press.
function Kit.button(props, onClick)
	local color = props.Color or Kit.Colors.Green
	local dark = props.Dark or color:Lerp(Color3.new(0, 0, 0), 0.35)
	local holder = Kit.new("Frame", {
		Name = props.Name or "Button",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromOffset(120, 44),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.Anchor or Vector2.new(),
		LayoutOrder = props.Order or 0,
		ZIndex = props.Z or 1,
		Parent = props.Parent,
	})
	local shadow = Kit.new("Frame", {
		Name = "Shadow",
		BackgroundColor3 = dark,
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.fromOffset(0, 4),
		ZIndex = holder.ZIndex,
		Parent = holder,
	})
	Kit.corner(shadow, props.Radius or 12)
	Kit.stroke(shadow, 3)
	local button = Kit.new("TextButton", {
		Name = "Face",
		AutoButtonColor = false,
		BackgroundColor3 = color,
		Size = UDim2.new(1, 0, 1, 0),
		Text = "",
		ZIndex = holder.ZIndex + 1,
		Parent = holder,
	})
	Kit.corner(button, props.Radius or 12)
	Kit.stroke(button, 3, nil, Enum.ApplyStrokeMode.Border)
	Kit.gradient(button, Color3.new(1, 1, 1), Color3.fromRGB(215, 215, 215))
	local label = Kit.label({
		Text = props.Text or "",
		Size = UDim2.new(1, -10, 1, -6),
		Position = UDim2.fromScale(0.5, 0.5),
		Anchor = Vector2.new(0.5, 0.5),
		Z = holder.ZIndex + 2,
		Parent = button,
		MaxTextSize = props.MaxTextSize or 30,
	})
	local pressTween = TweenInfo.new(0.07)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(button, pressTween, { Position = UDim2.fromOffset(0, 3) }):Play()
	end)
	local function release()
		TweenService:Create(button, pressTween, { Position = UDim2.fromOffset(0, 0) }):Play()
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	button.Activated:Connect(function()
		playClick()
		if onClick then
			onClick()
		end
	end)
	local api = { Holder = holder, Button = button, Label = label, Shadow = shadow }
	function api.setColor(c: Color3)
		button.BackgroundColor3 = c
		shadow.BackgroundColor3 = c:Lerp(Color3.new(0, 0, 0), 0.35)
	end
	function api.setText(t: string)
		label.Text = t
	end
	return api
end

function Kit.panel(props)
	local frame = Kit.new("Frame", {
		Name = props.Name or "Panel",
		BackgroundColor3 = props.Color or Kit.Colors.Panel,
		BackgroundTransparency = props.Transparency or 0,
		Size = props.Size or UDim2.fromOffset(200, 100),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.Anchor or Vector2.new(),
		LayoutOrder = props.Order or 0,
		ZIndex = props.Z or 1,
		Visible = props.Visible ~= false,
		Parent = props.Parent,
	})
	Kit.corner(frame, props.Radius or 14)
	if props.Stroke ~= false then
		Kit.stroke(frame, props.StrokeThickness or 3, props.StrokeColor)
	end
	return frame
end

function Kit.hex(c: Color3): string
	return "#" .. c:ToHex()
end

function Kit.tween(inst: Instance, seconds: number, goal, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local tween = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	tween:Play()
	return tween
end

Kit.playClick = playClick

return Kit
