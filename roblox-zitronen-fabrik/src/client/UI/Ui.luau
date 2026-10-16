--[[
	Kleine UI-Bausteine im Roblox-Standard-Look:
	dunkle Panels, abgerundete Ecken, kräftige Standardfarben, Source-Sans-Schrift.
]]

local TweenService = game:GetService("TweenService")

local Ui = {}

Ui.Font = Enum.Font.SourceSansBold
Ui.FontRegular = Enum.Font.SourceSans

Ui.Colors = {
	Panel = Color3.fromRGB(32, 34, 37),
	PanelLight = Color3.fromRGB(52, 55, 60),
	Row = Color3.fromRGB(44, 47, 51),
	RowAlt = Color3.fromRGB(38, 40, 44),
	Text = Color3.fromRGB(255, 255, 255),
	SubText = Color3.fromRGB(190, 195, 200),
	Green = Color3.fromRGB(0, 176, 64),
	Red = Color3.fromRGB(215, 45, 45),
	Blue = Color3.fromRGB(0, 120, 215),
	Yellow = Color3.fromRGB(245, 205, 48),
	Orange = Color3.fromRGB(218, 133, 65),
	Purple = Color3.fromRGB(140, 60, 220),
	Pink = Color3.fromRGB(230, 70, 160),
	Grey = Color3.fromRGB(105, 108, 114),
	Gold = Color3.fromRGB(255, 200, 30),
	Cash = Color3.fromRGB(110, 255, 110),
}

function Ui.Corner(parent: GuiObject, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = parent
	return corner
end

function Ui.Stroke(parent: GuiObject, thickness: number?, color: Color3?, transparency: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness or 2
	stroke.Color = color or Color3.new(0, 0, 0)
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function Ui.Padding(parent: GuiObject, px: number)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, px)
	pad.PaddingBottom = UDim.new(0, px)
	pad.PaddingLeft = UDim.new(0, px)
	pad.PaddingRight = UDim.new(0, px)
	pad.Parent = parent
	return pad
end

function Ui.List(parent: GuiObject, padding: number?, horizontal: boolean?)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, padding or 6)
	layout.FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
	layout.Parent = parent
	return layout
end

function Ui.Frame(parent: Instance?, props): Frame
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Ui.Colors.Panel
	for k, v in pairs(props or {}) do
		(frame :: any)[k] = v
	end
	frame.Parent = parent
	return frame
end

function Ui.Label(parent: Instance?, text: string, props): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Ui.Font
	label.Text = text
	label.TextColor3 = Ui.Colors.Text
	label.TextSize = 20
	label.TextStrokeTransparency = 0.6
	label.TextWrapped = true
	for k, v in pairs(props or {}) do
		(label :: any)[k] = v
	end
	label.Parent = parent
	return label
end

-- Knopf mit kleinem "Drück"-Effekt
function Ui.Button(parent: Instance?, text: string, color: Color3, props, onClick: (() -> ())?): TextButton
	local button = Instance.new("TextButton")
	button.AutoButtonColor = true
	button.BorderSizePixel = 0
	button.BackgroundColor3 = color
	button.Font = Ui.Font
	button.Text = text
	button.TextColor3 = Ui.Colors.Text
	button.TextSize = 20
	button.TextStrokeTransparency = 0.5
	button.TextWrapped = true
	for k, v in pairs(props or {}) do
		(button :: any)[k] = v
	end
	Ui.Corner(button, 8)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.93 }):Play()
	end)
	local function release()
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	if onClick then
		button.Activated:Connect(onClick)
	end
	button.Parent = parent
	return button
end

function Ui.ProgressBar(parent: Instance?, props, fillColor: Color3?)
	local back = Ui.Frame(parent, props)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 22)
	Ui.Corner(back, 6)
	local fill = Ui.Frame(back, {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = fillColor or Ui.Colors.Green,
	})
	Ui.Corner(fill, 6)
	local text = Ui.Label(back, "", {
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		TextSize = 16,
		TextStrokeTransparency = 0.3,
		ZIndex = 3,
	})
	return back, fill, text
end

function Ui.SetProgress(fill: Frame, fraction: number)
	fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
end

function Ui.Tween(instance: Instance, time: number, goal, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local tween = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	tween:Play()
	return tween
end

-- Einfaches Ein/Aus mit Farbe (Einstellungen)
function Ui.Toggle(parent: Instance?, text: string, initial: boolean, onChange: (boolean) -> ()): Frame
	local row = Ui.Frame(parent, { Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = Ui.Colors.Row })
	Ui.Corner(row, 8)
	Ui.Label(row, text, {
		Size = UDim2.new(1, -110, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 20,
	})
	local state = initial
	local button
	local function refresh()
		button.Text = state and "AN" or "AUS"
		button.BackgroundColor3 = state and Ui.Colors.Green or Ui.Colors.Red
	end
	button = Ui.Button(row, "", Ui.Colors.Green, {
		Size = UDim2.fromOffset(84, 32),
		Position = UDim2.new(1, -94, 0.5, -16),
	}, function()
		state = not state
		refresh()
		onChange(state)
	end)
	refresh()
	return row
end

return Ui
