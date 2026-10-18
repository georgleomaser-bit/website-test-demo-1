--[[
	Tutorial (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Tutorial
	Depends on: ReplicatedStorage/UI/{UIKit,Theme,SoundPlayer}, ReplicatedStorage/Shared/Config/Tutorial,
	            Client/{State,ClientNet,ScreenManager,Hud}

	Shows the first-time tutorial: a coach card at the top of the screen, plus
	an arrow and a glowing ring on the HUD element the step is about. The
	SERVER decides when a step is done (TutorialService); this module only
	draws the current step from the synced "Tutorial" section and sends
	intents: "seen" (opening the quests, pressing Got it!) and "skip".
	Replaying is started from Settings.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UIFolder = ReplicatedStorage:WaitForChild("UI")
local UI = require(UIFolder.UIKit)
local Theme = require(UIFolder.Theme)
local SoundPlayer = require(UIFolder.SoundPlayer)
local TutorialConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Tutorial"))

local State = require(script.Parent.State)
local ClientNet = require(script.Parent.ClientNet)
local ScreenManager = require(script.Parent.ScreenManager)

local C = Theme.Colors
local F = Theme.Fonts

local Tutorial: { [string]: any } = {}

local function currentStep()
	local state = State.get("Tutorial")
	if not state or state.Done then
		return nil
	end
	return TutorialConfig.Steps[state.Step]
end

function Tutorial.init(ctx)
	local hud = ctx.Hud
	local overlay = ctx.Layers.Overlay

	-- Coach card (top centre; the top of the screen is free now that the HUD is at the bottom).
	local card = UI.new("Frame", {
		Name = "TutorialCard",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(470, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 50,
		Corner = Theme.Radius.Medium,
		Stroke = { Color = C.Accent2, Thickness = 2 },
		Padding = 12,
		List = { Dir = "Y", Pad = 6 },
		Parent = overlay,
	})
	Tutorial.Card = card
	local scale = Instance.new("UIScale")
	scale.Parent = card
	local counter = UI.label({
		Name = "Counter",
		Text = "",
		Font = F.Bold,
		TextSize = 12,
		TextColor3 = C.Accent2,
		Size = UDim2.new(1, 0, 0, 14),
		LayoutOrder = 1,
		ZIndex = 51,
		Parent = card,
	})
	local title = UI.label({
		Name = "Title",
		Text = "",
		Font = F.Heading,
		TextSize = 18,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 2,
		ZIndex = 51,
		Parent = card,
	})
	local body = UI.label({
		Name = "Body",
		Text = "",
		TextSize = 14,
		TextWrapped = true,
		TextColor3 = C.TextDim,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, 18),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		ZIndex = 51,
		Parent = card,
	})
	local buttons = UI.frame({
		Name = "Buttons",
		Size = UDim2.new(1, 0, 0, 32),
		LayoutOrder = 4,
		ZIndex = 51,
		List = { Dir = "X", Pad = 8, HA = "Right", VA = "Center" },
		Parent = card,
	})
	local gotIt = UI.button({
		Name = "GotIt",
		Text = "Got it!",
		Variant = "primary",
		Size = UDim2.fromOffset(110, 30),
		TextSize = 14,
		LayoutOrder = 2,
		ZIndex = 52,
		Visible = false,
		OnClick = function()
			local step = currentStep()
			if step and step.Kind == "seen" then
				ClientNet.action("TutorialSeen", { Step = step.Id })
			end
		end,
		Parent = buttons,
	})
	UI.button({
		Name = "Skip",
		Text = "Skip tutorial",
		Variant = "ghost",
		Size = UDim2.fromOffset(120, 30),
		TextSize = 13,
		LayoutOrder = 1,
		ZIndex = 52,
		OnClick = function()
			ClientNet.action("TutorialSkip", {})
		end,
		Parent = buttons,
	})

	-- Pointer and highlight ring around the target element.
	local ring = UI.new("Frame", {
		Name = "TutorialRing",
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 48,
		Corner = Theme.Radius.Medium,
		Stroke = { Color = C.Gold, Thickness = 3 },
		Parent = overlay,
	})
	ring.Active = false
	local arrow = UI.label({
		Name = "TutorialArrow",
		Text = "▼",
		Font = F.Heading,
		TextSize = 34,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(40, 40),
		Visible = false,
		ZIndex = 49,
		Parent = overlay,
	})
	UI.stroke(arrow, { Color = C.Black, Thickness = 2, Transparency = 0.3, Text = true })
	Tutorial.Ring = ring
	Tutorial.Arrow = arrow

	local shownStep: string? = nil
	local function refresh()
		local step = currentStep()
		card.Visible = step ~= nil
		if not step then
			shownStep = nil
			ring.Visible = false
			arrow.Visible = false
			return
		end
		counter.Text = `TUTORIAL · STEP {step.Index}/{#TutorialConfig.Steps}`
		title.Text = step.Title
		body.Text = step.Text
		gotIt.Visible = step.Final == true
		if shownStep ~= step.Id then
			shownStep = step.Id
			if not Theme.ReducedMotion then
				scale.Scale = 0.9
				UI.tween(scale, { Scale = 1 }, Theme.Motion.Pop)
			end
			if step.Index > 1 then
				SoundPlayer.play("Reveal")
			end
		end
	end

	-- "Look at the quests" completes when the quests are actually opened.
	local function onScreen(current: string?)
		local step = currentStep()
		if step and step.Id == "quests" and current == "Quests" then
			ClientNet.action("TutorialSeen", { Step = "quests" })
		end
	end
	ScreenManager.Changed:Connect(onScreen)

	-- Follow the target every frame (layouts move when the window size changes).
	local clock = 0
	RunService.RenderStepped:Connect(function(dt)
		clock += dt
		local step = currentStep()
		local target = step and hud.target(step.Target)
		-- While a window is open the HUD is covered: only the card stays.
		local show = target ~= nil and target.Visible and not ScreenManager.isOpen()
		ring.Visible = show
		arrow.Visible = show
		card.Position = UDim2.new(0.5, 0, 0, if ScreenManager.isOpen() then 8 else 70)
		if not show or not target then
			return
		end
		local origin = overlay.AbsolutePosition
		local pos = target.AbsolutePosition - origin
		local size = target.AbsoluteSize
		ring.Position = UDim2.fromOffset(pos.X - 6, pos.Y - 6)
		ring.Size = UDim2.fromOffset(size.X + 12, size.Y + 12)
		local bob = if Theme.ReducedMotion then 0 else math.sin(clock * 5) * 6
		arrow.Position = UDim2.fromOffset(pos.X + size.X / 2, pos.Y - 8 + bob)
	end)

	local function fitWidth()
		card.Size = UDim2.fromOffset(math.min(470, UI.viewport().X - 32), 0)
	end
	fitWidth()
	UI.onViewportChanged(fitWidth)

	State.subscribe("Tutorial", refresh)
	State.onReady(refresh)
end

-- Starts the tutorial again (Settings → Replay tutorial).
function Tutorial.replay()
	return ClientNet.action("TutorialRestart", {})
end

return Tutorial
