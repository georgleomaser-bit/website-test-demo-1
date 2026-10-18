--[[
	ClientMain (LocalScript)
	Location: StarterPlayer/StarterPlayerScripts/ClientMain

	Client entry point. Builds the interface at runtime (StarterGui stays
	empty on purpose: building UI in code keeps every screen in version
	control and lets it adapt to any screen size), connects the remotes and
	applies the player's settings.

	Dependencies: StarterPlayerScripts/Client/* (State, ClientNet, Hud, ScreenManager,
	Notifications, Orbs, InputController, WorldFx, Screens/*), ReplicatedStorage/UI/*,
	ReplicatedStorage/Shared/*
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Client = script.Parent:WaitForChild("Client")
local Screens = Client:WaitForChild("Screens")
local UIFolder = ReplicatedStorage:WaitForChild("UI")

local UI = require(UIFolder.UIKit)
local Theme = require(UIFolder.Theme)
local SoundPlayer = require(UIFolder.SoundPlayer)
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))

local State = require(Client.State)
local ClientNet = require(Client.ClientNet)
local ScreenManager = require(Client.ScreenManager)
local Notifications = require(Client.Notifications)
local Hud = require(Client.Hud)
local Orbs = require(Client.Orbs)
local InputController = require(Client.InputController)
local WorldFx = require(Client.WorldFx)

local C = Theme.Colors

-- The game has no tools, so the backpack bar is hidden.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

-- Root ScreenGui and layers (bottom to top) -------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "ButtonAscensionUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 5
gui.Parent = playerGui

local layers = {}
for index, name in ipairs({ "Backdrop", "Hud", "Orbs", "Windows", "Fx", "Overlay", "Notifications" }) do
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ZIndex = index
	frame.Parent = gui
	layers[name] = frame
end

-- Backdrop: darkens the 3D world so the interface reads clearly.
local backdrop = layers.Backdrop
backdrop.BackgroundColor3 = C.Background
backdrop.BackgroundTransparency = 1 - GameConfig.Settings.BackgroundDim.Default
UI.gradient(backdrop, {
	Color = ColorSequence.new(Color3.fromRGB(40, 20, 70), C.Background),
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.5, 0.6),
		NumberSequenceKeypoint.new(1, 0.1),
	}),
	Rotation = 90,
})

local ctx = {
	Player = player,
	Gui = gui,
	Layers = layers,
	State = State,
	Net = ClientNet,
	Screens = ScreenManager,
	Notifications = Notifications,
	Hud = Hud,
}

-- Settings ------------------------------------------------------------------------------------
local screenObjects = {}
local function applySettings()
	local settings = State.get("Settings")
	if not settings then
		return
	end
	Theme.ReducedMotion = settings.ReducedMotion == true
	local scale = tonumber(settings.UIScale) or 1
	local scaleChanged = math.abs(scale - Theme.UserScale) > 1e-3
	Theme.UserScale = scale
	SoundPlayer.setVolumes(tonumber(settings.SFX) or 0.7, tonumber(settings.Music) or 0.4)
	backdrop.BackgroundTransparency = 1 - (tonumber(settings.BackgroundDim) or 0.35)
	if scaleChanged then
		Hud.layout()
		if Notifications.rescale then
			Notifications.rescale()
		end
		for _, screen in pairs(screenObjects) do
			screen.Window.Refit()
		end
	end
end
ctx.ApplySettings = applySettings

-- Build ---------------------------------------------------------------------------------------
Notifications.init(ctx)
Hud.init(ctx)
Orbs.init(ctx)

for _, id in ipairs({ "Shop", "Chests", "Inventory", "Collection", "Skills", "Quests", "Ascend", "Stats", "Settings" }) do
	local module = require(Screens:WaitForChild(id))
	local screen = module.new(ctx)
	screenObjects[id] = screen
	ScreenManager.register(id, screen)
end

InputController.init(ctx)
WorldFx.init(ctx)

-- Loading screen ---------------------------------------------------------------------------------
local loading = UI.frame({ Name = "Loading", ZIndex = 200, Parent = layers.Overlay })
loading.BackgroundTransparency = 0
loading.BackgroundColor3 = C.Background
-- Swallow input so presses can't reach the button and HUD hidden behind it.
loading.Active = true
local title = UI.label({
	Text = string.upper(GameConfig.GameName),
	Font = Theme.Fonts.Display,
	TextSize = 42,
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.45),
	Size = UDim2.new(1, 0, 0, 50),
	ZIndex = 201,
	Parent = loading,
})
UI.stroke(title, { Color = C.Accent, Thickness = 2, Text = true })
local loadingText = UI.label({
	Text = "Loading your progress…",
	TextColor3 = C.TextDim,
	TextXAlignment = Enum.TextXAlignment.Center,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.52),
	Size = UDim2.new(1, 0, 0, 24),
	ZIndex = 201,
	Parent = loading,
})
local spinner = UI.new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.58),
	Size = UDim2.fromOffset(36, 36),
	BackgroundTransparency = 1,
	ZIndex = 201,
	Corner = Theme.Radius.Pill,
	Parent = loading,
})
local spinnerStroke = UI.stroke(spinner, { Color = C.Accent, Thickness = 4 })
UI.gradient(spinnerStroke, {
	Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
	Rotation = 0,
})
local spin = RunService.RenderStepped:Connect(function(dt)
	spinner.Rotation = (spinner.Rotation + dt * 360) % 360
end)

task.delay(15, function()
	if not State.Ready then
		loadingText.Text = "Still loading… Roblox data services may be slow right now."
	end
end)

State.onReady(function()
	applySettings()
	SoundPlayer.startMusic()
	spin:Disconnect()
	local t = UI.tween(loading, { BackgroundTransparency = 1 }, Theme.Motion.Slow, true)
	title.Visible = false
	loadingText.Visible = false
	spinner.Visible = false
	if t then
		t.Completed:Wait()
	end
	loading:Destroy()
end)

-- Remotes ----------------------------------------------------------------------------------------
ClientNet.on("StateSync", function(kind, payload)
	State.apply(kind, payload)
end)
ClientNet.on("ClickResult", function(result)
	if type(result) == "table" and (result.Auto or result.Passive) and ScreenManager.isOpen() then
		return
	end
	Hud.onClickResult(result)
end)
ClientNet.on("Notify", Notifications.handle)
ClientNet.on("OrbSpawn", Orbs.spawn)
State.subscribe("Settings", applySettings)

-- The first snapshot may have arrived before this script connected; ask again if needed.
task.delay(2, function()
	if not State.Ready then
		ClientNet.action("RequestState")
	end
end)
