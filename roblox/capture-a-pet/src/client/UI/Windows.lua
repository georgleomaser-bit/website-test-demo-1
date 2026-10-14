-- Popup windows (Shop, Index, Pets, ...). Dark rounded panel, big white title and a red X,
-- like the Pet Index reference. Only one window is open at a time.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Kit = require(script.Parent.Kit)

local Windows = {}

local player = Players.LocalPlayer
local screen
local registry = {}
local current = nil

function Windows.screen(): ScreenGui
	if screen then
		return screen
	end
	screen = Kit.new("ScreenGui", {
		Name = "CaptureAPetUI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local scale = Kit.new("UIScale", { Parent = screen })
	local function rescale()
		local camera = Workspace.CurrentCamera
		local size = camera and camera.ViewportSize or Vector2.new(1280, 720)
		scale.Scale = math.clamp(math.min(size.X / 1280, size.Y / 760), 0.55, 1.25)
	end
	local viewportConnection
	local function watchCamera()
		if viewportConnection then
			viewportConnection:Disconnect()
		end
		local camera = Workspace.CurrentCamera
		if camera then
			viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
		end
		rescale()
	end
	watchCamera()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	return screen
end

-- Usable screen size in UI units (after UIScale).
function Windows.uiSize(): Vector2
	local s = Windows.screen()
	local scale = s:FindFirstChildOfClass("UIScale")
	local camera = Workspace.CurrentCamera
	local size = camera and camera.ViewportSize or Vector2.new(1280, 720)
	return size / (scale and scale.Scale or 1)
end

function Windows.create(name: string, title: string, size: Vector2, titleColor: Color3?)
	local root = Windows.screen()
	local frame = Kit.panel({
		Name = name .. "Window",
		Size = UDim2.fromOffset(size.X, size.Y),
		Position = UDim2.fromScale(0.5, 0.5),
		Anchor = Vector2.new(0.5, 0.5),
		Color = Kit.Colors.Panel,
		Radius = 18,
		StrokeThickness = 4,
		Z = 20,
		Visible = false,
		Parent = root,
	})
	Kit.gradient(frame, Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 195, 230))
	local popScale = Kit.new("UIScale", { Parent = frame })
	Kit.label({
		Name = "Title",
		Text = title,
		Size = UDim2.new(1, -120, 0, 52),
		Position = UDim2.fromOffset(18, -18),
		XAlign = Enum.TextXAlignment.Left,
		Color = titleColor or Kit.Colors.White,
		StrokeThickness = 4,
		Z = 22,
		Parent = frame,
	})
	local api = { Frame = frame, Name = name }
	local close = Kit.button({
		Name = "Close",
		Text = "X",
		Color = Kit.Colors.Red,
		Size = UDim2.fromOffset(48, 48),
		Position = UDim2.new(1, 14, 0, -14),
		Anchor = Vector2.new(1, 0),
		Z = 23,
		Parent = frame,
	}, function()
		Windows.close()
	end)
	api.CloseButton = close
	local content = Kit.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -28, 1, -64),
		Position = UDim2.fromOffset(14, 48),
		ZIndex = 21,
		Parent = frame,
	})
	api.Content = content
	api.OnOpen = nil
	api.OnClose = nil
	function api.open()
		Windows.open(name)
	end
	api._pop = popScale
	registry[name] = api
	return api
end

function Windows.open(name: string)
	local api = registry[name]
	if not api then
		return
	end
	if current == api then
		Windows.close()
		return
	end
	if current then
		current.Frame.Visible = false
		if current.OnClose then
			current.OnClose()
		end
	end
	current = api
	api.Frame.Visible = true
	api._pop.Scale = 0.6
	Kit.tween(api._pop, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
	if api.OnOpen then
		api.OnOpen()
	end
end

-- Opens a window without toggling it closed when it is already open.
function Windows.show(name: string)
	if not Windows.isOpen(name) then
		Windows.open(name)
	end
end

function Windows.close()
	if current then
		local api = current
		current = nil
		api.Frame.Visible = false
		if api.OnClose then
			api.OnClose()
		end
	end
end

function Windows.isOpen(name: string): boolean
	return current ~= nil and current.Name == name
end

function Windows.get(name: string)
	return registry[name]
end

-- Scrolling grid helper used by several windows.
function Windows.scroll(parent: Instance, size: UDim2, position: UDim2)
	local scroll = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = size,
		Position = position,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Color3.fromRGB(200, 200, 230),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 21,
		Parent = parent,
	})
	Kit.padding(scroll, 6)
	return scroll
end

return Windows
