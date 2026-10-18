--[[
	BigButton (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/BigButton
	Depends on: ReplicatedStorage/UI/{UIKit,Theme,Effects,SoundPlayer},
	            ReplicatedStorage/Shared/{Format, Config/GameConfig}, Client/ClientNet

	The PRESS button (bottom right of the HUD). Pressing it gives instant local feedback
	(squash, shockwave, sparks, sound) and fires the Click remote; the
	floating reward number appears when the server's ClickResult arrives, so
	what the player sees is always what the server actually awarded.

	Input: mouse and touch press on InputBegan (instant), gamepad via the
	selected button's Activated event or InputController (R2/L2).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UIFolder = ReplicatedStorage:WaitForChild("UI")
local UI = require(UIFolder.UIKit)
local Theme = require(UIFolder.Theme)
local Effects = require(UIFolder.Effects)
local SoundPlayer = require(UIFolder.SoundPlayer)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local GameConfig = require(Shared.Config.GameConfig)

local ClientNet = require(script.Parent.ClientNet)

local C = Theme.Colors
local BigButton = {}
BigButton.__index = BigButton

local DEFAULT_SIZE = 300
local MAX_LOCAL_CPS = 25
local rng = Random.new()

-- size: diameter in pixels before HUD scaling (default 300).
function BigButton.new(parent: GuiObject, fxLayer: GuiObject, size: number?)
	local self = setmetatable({}, BigButton)
	local SIZE = size or DEFAULT_SIZE
	local k = SIZE / DEFAULT_SIZE
	self.Size = SIZE
	self.FxLayer = fxLayer
	self.LastPress = 0
	self.Presses = {}
	self.Pressed = Instance.new("BindableEvent")

	local holder = UI.frame({
		Name = "BigButton",
		Size = UDim2.fromOffset(SIZE, SIZE),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Parent = parent,
	})
	self.Instance = holder
	local squash = Instance.new("UIScale")
	squash.Name = "Squash"
	squash.Parent = holder
	self.Squash = squash

	local function circle(name: string, scale: number, color: Color3, z: number, offsetY: number?)
		return UI.new("Frame", {
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, offsetY or 0),
			Size = UDim2.fromScale(scale, scale),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = z,
			Corner = Theme.Radius.Pill,
			Parent = holder,
		})
	end

	-- Soft glow made of stacked translucent strokes.
	self.Glows = {}
	for i, spec in ipairs({ { 1.0, 16, 0.86 }, { 0.95, 10, 0.75 }, { 0.9, 5, 0.6 } }) do
		local ring = circle("Glow" .. i, spec[1], C.Black, 1)
		ring.BackgroundTransparency = 1
		local stroke = UI.stroke(ring, { Color = C.Accent, Thickness = spec[2], Transparency = spec[3] })
		table.insert(self.Glows, { Stroke = stroke, Base = spec[3] })
	end

	local base = circle("Base", 0.86, Color3.fromRGB(24, 18, 36), 2, 6)
	UI.stroke(base, { Color = Color3.fromRGB(60, 40, 80), Thickness = 3 })
	local skirt = circle("Skirt", 0.78, C.AccentSoft, 3, 10)
	self.Skirt = skirt

	local cap = UI.new("TextButton", {
		Name = "Cap",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -4),
		Size = UDim2.fromScale(0.76, 0.76),
		BackgroundColor3 = C.Accent,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 4,
		Selectable = true,
		Corner = Theme.Radius.Pill,
		Parent = holder,
	})
	self.Cap = cap
	self.CapGradient = UI.gradient(cap, {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(235, 235, 235)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 150, 160)),
		}),
		Rotation = 90,
	})
	self.CapStroke = UI.stroke(cap, { Color = Theme.lighten(C.Accent, 0.35), Thickness = 3 })

	UI.new("Frame", {
		Name = "Gloss",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.08),
		Size = UDim2.fromScale(0.66, 0.34),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.55,
		ZIndex = 5,
		Corner = Theme.Radius.Pill,
		Gradient = {
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
			Rotation = 90,
		},
		Parent = cap,
	})
	local label = UI.label({
		Name = "Label",
		Text = "PRESS",
		Font = Theme.Fonts.Display,
		TextSize = math.max(16, math.floor(34 * k + 0.5)),
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, math.max(20, math.floor(40 * k))),
		Position = UDim2.fromScale(0, 0.38),
		ZIndex = 6,
		Parent = cap,
	})
	UI.stroke(label, { Color = C.Black, Thickness = 2, Transparency = 0.55, Text = true })
	self.ValueLabel = UI.label({
		Name = "Value",
		Text = "+1 ⚡",
		Font = Theme.Fonts.Heading,
		TextSize = math.max(12, math.floor(20 * k + 0.5)),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(255, 240, 210),
		Size = UDim2.new(1, 0, 0, math.max(14, math.floor(24 * k))),
		Position = UDim2.fromScale(0, 0.57),
		ZIndex = 6,
		Parent = cap,
	})
	UI.stroke(self.ValueLabel, { Color = C.Black, Thickness = 1.5, Transparency = 0.5, Text = true })

	cap.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			self:Press()
		end
	end)
	cap.Activated:Connect(function(input)
		if input and string.find(input.UserInputType.Name, "Gamepad") then
			self:Press()
		end
	end)

	local clock = 0
	RunService.RenderStepped:Connect(function(dt)
		if Theme.ReducedMotion then
			return
		end
		clock += dt
		local pulse = math.sin(clock * 2.2) * 0.06
		for i, glow in ipairs(self.Glows) do
			glow.Stroke.Transparency = math.clamp(glow.Base - pulse * (1 + i * 0.3), 0, 1)
		end
	end)

	self:SetStage(1)
	return self
end

function BigButton:SetStage(stageId: number, frenzy: boolean?)
	local stage = GameConfig.Stages[stageId] or GameConfig.Stages[1]
	local accent = if frenzy then C.Gold else stage.Accent
	local dark = if frenzy then Color3.fromRGB(150, 100, 0) else stage.AccentDark
	self.Accent = accent
	UI.tween(self.Cap, { BackgroundColor3 = accent }, Theme.Motion.Slow)
	UI.tween(self.Skirt, { BackgroundColor3 = dark }, Theme.Motion.Slow)
	self.CapStroke.Color = Theme.lighten(accent, 0.35)
	for _, glow in ipairs(self.Glows) do
		glow.Stroke.Color = accent
	end
end

function BigButton:SetValueText(clickValue: number)
	self.ValueLabel.Text = "+" .. Format.short(clickValue, true) .. " ⚡"
end

function BigButton:Center(): Vector2
	local cap = self.Cap
	local layer = self.FxLayer
	return cap.AbsolutePosition + cap.AbsoluteSize / 2 - layer.AbsolutePosition
end

function BigButton:Press()
	local now = os.clock()
	-- Local cap keeps the UI honest; the server enforces the real limit.
	local recent = self.Presses
	while #recent > 0 and now - recent[1] > 1 do
		table.remove(recent, 1)
	end
	if #recent >= MAX_LOCAL_CPS then
		return
	end
	table.insert(recent, now)
	self.LastPress = now

	ClientNet.click()
	self.Pressed:Fire()

	local squash = self.Squash
	if Theme.ReducedMotion then
		squash.Scale = 1
	else
		squash.Scale = 0.93
		UI.tween(squash, { Scale = 1 }, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
		self.Cap.Position = UDim2.new(0.5, 0, 0.5, 4)
		UI.tween(self.Cap, { Position = UDim2.new(0.5, 0, 0.5, -4) }, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
	end
	local center = self:Center()
	Effects.ring(self.FxLayer, center, self.Accent or C.Accent, self.Size * 1.15)
	Effects.burst(self.FxLayer, center, self.Accent or C.Accent, 6, self.Size * 0.57)
	SoundPlayer.play("Click", { Pitch = 0.95 + math.min(#recent, 20) * 0.012 + rng:NextNumber(-0.02, 0.02) })
end

-- Floating number for a server-confirmed press.
function BigButton:ShowResult(result, showNumbers: boolean)
	local center = self:Center()
	local size = self.Size
	-- Numbers float up and to the left, into the open screen above the button.
	local pos = center + Vector2.new(rng:NextNumber(-size * 0.9, size * 0.1), rng:NextNumber(-size * 0.75, -size * 0.45))
	if showNumbers then
		if result.Crit then
			Effects.floatText(self.FxLayer, pos, "CRIT! +" .. Format.short(result.Amount, true), C.Gold, { Size = 34, Rise = 120, Duration = 1.1 })
		else
			Effects.floatText(self.FxLayer, pos, "+" .. Format.short(result.Amount, true), C.Text, { Size = 26 })
		end
	end
	if result.Crit then
		Effects.burst(self.FxLayer, center, C.Gold, 10, size * 0.67)
		SoundPlayer.play("Crit")
	end
	if result.Streak then
		Effects.floatText(self.FxLayer, center + Vector2.new(-size * 0.6, -size * 0.95), `STREAK ×{result.Combo}!  +{Format.short(result.Streak, true)}`, C.Accent2, { Size = 30, Rise = 70, Duration = 1.4 })
		Effects.ring(self.FxLayer, center, C.Accent2, size * 1.8)
		SoundPlayer.play("Streak")
	end
	if result.Golden then
		Effects.burst(self.FxLayer, center, C.Gold, 26, size)
		Effects.ring(self.FxLayer, center, C.Gold, size * 2.2)
		SoundPlayer.play("Golden")
	end
end

-- Aggregated auto-press / passive income for the last second.
function BigButton:ShowIncome(result, showNumbers: boolean)
	if not showNumbers then
		return
	end
	local center = self:Center()
	local size = self.Size
	if result.Auto and result.Auto > 0 then
		Effects.floatText(self.FxLayer, center + Vector2.new(-size * 0.2, -size * 0.7), "🤖 +" .. Format.short(result.Auto, true), C.Accent2, { Size = 18, Rise = 60, Duration = 1.0 })
	end
	if result.Passive and result.Passive > 0 then
		Effects.floatText(self.FxLayer, center + Vector2.new(-size * 0.8, -size * 0.45), "🔋 +" .. Format.short(result.Passive, true), C.Sparks, { Size = 18, Rise = 60, Duration = 1.0 })
	end
end

return BigButton
