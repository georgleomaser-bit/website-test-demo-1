--[[
	Fenster-Verwaltung: immer nur ein Fenster offen, mit Titelleiste und X.
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Ui = require(script.Parent.Ui)

local Windows = {}

Windows.Root = nil :: Frame?
Windows.OnOpen = Instance.new("BindableEvent") -- (name)

local registry: { [string]: any } = {}
local current: string? = nil

function Windows.Create(name: string, title: string, color: Color3, size: Vector2)
	assert(Windows.Root, "Windows.Root fehlt")
	local frame = Ui.Frame(Windows.Root, {
		Name = name .. "Window",
		Size = UDim2.fromOffset(size.X, size.Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 10),
		BackgroundColor3 = Ui.Colors.Panel,
		BackgroundTransparency = 0.04,
		Visible = false,
		ZIndex = 10,
		Active = true,
	})
	Ui.Corner(frame, 12)
	Ui.Stroke(frame, 3, Color3.new(0, 0, 0), 0.2)
	local scale = Instance.new("UIScale")
	scale.Parent = frame

	local bar = Ui.Frame(frame, {
		Name = "TitleBar",
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundColor3 = color,
		ZIndex = 11,
	})
	Ui.Corner(bar, 12)
	-- untere Ecken der Titelleiste gerade machen
	Ui.Frame(bar, { Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -14), BackgroundColor3 = color, ZIndex = 11 })
	Ui.Label(bar, title, {
		Name = "Title",
		Size = UDim2.new(1, -120, 1, 0),
		Position = UDim2.fromOffset(16, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 30,
		TextStrokeTransparency = 0.3,
		ZIndex = 12,
	})
	local close = Ui.Button(bar, "X", Ui.Colors.Red, {
		Name = "Close",
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.new(1, -46, 0, 5),
		TextSize = 26,
		ZIndex = 13,
	}, function()
		Windows.Close()
	end)
	Ui.Stroke(close, 2, Color3.new(0, 0, 0), 0.3)

	local content = Ui.Frame(frame, {
		Name = "Content",
		Size = UDim2.new(1, -24, 1, -68),
		Position = UDim2.fromOffset(12, 58),
		BackgroundTransparency = 1,
		ZIndex = 11,
	})

	local window = {
		Name = name,
		Frame = frame,
		Content = content,
		Scale = scale,
		Refresh = nil :: (() -> ())?,
		Update = nil :: ((number) -> ())?,
		OnOpen = nil :: (() -> ())?,
	}
	registry[name] = window
	return window
end

-- Scrollbare Liste im Fenster
function Windows.ScrollList(parent: Instance, props): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = Color3.fromRGB(200, 200, 200)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ZIndex = 11
	for k, v in pairs(props or {}) do
		(scroll :: any)[k] = v
	end
	Ui.List(scroll, 6)
	local pad = Instance.new("UIPadding")
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = scroll
	scroll.Parent = parent
	return scroll
end

function Windows.Get(name: string)
	return registry[name]
end

function Windows.IsOpen(name: string): boolean
	return current == name
end

function Windows.Current(): string?
	return current
end

function Windows.Close()
	if not current then
		return
	end
	local window = registry[current]
	current = nil
	if window then
		window.Frame.Visible = false
	end
end

function Windows.Open(name: string)
	local window = registry[name]
	if not window then
		return
	end
	if current == name then
		return
	end
	Windows.Close()
	current = name
	window.Frame.Visible = true
	window.Scale.Scale = 0.85
	Ui.Tween(window.Scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	if window.OnOpen then
		window.OnOpen()
	end
	if window.Refresh then
		window.Refresh()
	end
	Windows.OnOpen:Fire(name)
end

function Windows.Toggle(name: string)
	if current == name then
		Windows.Close()
	else
		Windows.Open(name)
	end
end

function Windows.Start()
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		if not current then
			return
		end
		local window = registry[current]
		if not window then
			return
		end
		if window.Update then
			window.Update(dt)
		end
		acc += dt
		if acc >= 0.25 then
			acc = 0
			if window.Refresh then
				window.Refresh()
			end
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			Windows.Close()
		end
	end)
end

return Windows
