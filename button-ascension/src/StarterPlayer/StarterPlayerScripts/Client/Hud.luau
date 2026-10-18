--[[
	Hud (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Hud
	Depends on: ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format,Formulas,Util,Config/*},
	            Client/{State,ClientNet,ScreenManager,BigButton}

	Always-visible interface. Everything sits at the BOTTOM of the screen so the
	middle stays free for running around the world and the obby:
	  * Dock (bottom centre), rows from the bottom: navigation (Shop, Crates,
	    Inventory, Skills, Collection, Quests, Ascend, Stats, Store (Robux),
	    Settings, with notification badges); Sparks, Gems, Prisms, level + XP,
	    ascension progress; obby progress with ▶ / 🏠 buttons and live stat
	    chips; active boost timers; the "not saving" warning.
	  * PRESS button with combo meter and income rates (bottom right; on touch
	    screens it sits above Roblox's jump button).
	  * Quest card (right side) — the only element not at the bottom.
	Layout scales with the viewport and the UI Scale setting; small screens
	use a compact layout (icon-only navigation, quest card behind a toggle).
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local UIFolder = ReplicatedStorage:WaitForChild("UI")
local UI = require(UIFolder.UIKit)
local Theme = require(UIFolder.Theme)
local Effects = require(UIFolder.Effects)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Util = require(Shared.Util)
local Config = Shared.Config
local GameConfig = require(Config.GameConfig)
local Upgrades = require(Config.Upgrades)
local Skills = require(Config.Skills)
local Quests = require(Config.Quests)
local Rewards = require(Config.Rewards)
local Items = require(Config.Items)
local Ascension = require(Config.Ascension)
local DevProducts = require(Config.DevProducts)
local ObbyConfig = require(Config.Obby)

local State = require(script.Parent.State)
local ClientNet = require(script.Parent.ClientNet)
local ScreenManager = require(script.Parent.ScreenManager)
local BigButton = require(script.Parent.BigButton)

local C = Theme.Colors
local F = Theme.Fonts

local Hud: { [string]: any } = {}

local NAV = {
	{ Id = "Shop", Icon = "🛒", Text = "Shop" },
	{ Id = "Chests", Icon = "🎁", Text = "Crates" },
	{ Id = "Inventory", Icon = "🎒", Text = "Items" },
	{ Id = "Skills", Icon = "🌳", Text = "Skills" },
	{ Id = "Collection", Icon = "📖", Text = "Book" },
	{ Id = "Quests", Icon = "📜", Text = "Quests" },
	{ Id = "Ascend", Icon = "🔷", Text = "Ascend" },
	{ Id = "Stats", Icon = "🏆", Text = "Stats" },
	{ Id = "Store", Icon = "💰", Text = "Store" },
	{ Id = "Settings", Icon = "⚙️", Text = "Settings" },
}

-- Base sizes (pixels at HUD scale 1).
local DOCK_WIDTH = 770
local DOCK_HEIGHT = 220
local PRESS_SIZE = 180
local NAV_BUTTON = Vector2.new(64, 56)

local scales: { UIScale } = {}

local function addScale(inst: Instance): UIScale
	local s = Instance.new("UIScale")
	s.Name = "HudScale"
	s.Parent = inst
	table.insert(scales, s)
	return s
end

-- Currency pill ------------------------------------------------------------------------

local function pill(parent: Instance, currency: string, width: number, order: number, big: boolean)
	local frame = UI.new("Frame", {
		Name = currency,
		Size = UDim2.fromOffset(width, if big then 54 else 44),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.08,
		LayoutOrder = order,
		Corner = Theme.Radius.Pill,
		Stroke = { Color = Theme.darken(Theme.currencyColor(currency), 0.45), Thickness = 1.5 },
		Parent = parent,
	})
	UI.label({
		Name = "Icon",
		Text = Theme.currencyIcon(currency),
		TextSize = if big then 26 else 20,
		Size = UDim2.fromOffset(if big then 46 else 38, if big then 54 else 44),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = frame,
	})
	local value = UI.label({
		Name = "Value",
		Text = "0",
		Font = F.Heading,
		TextSize = if big then 26 else 19,
		TextColor3 = Theme.currencyColor(currency),
		Size = UDim2.new(1, if big then -54 else -44, 1, 0),
		Position = UDim2.fromOffset(if big then 46 else 38, 0),
		Parent = frame,
	})
	UI.attachTooltip(frame, function()
		local def = GameConfig.Currencies[currency]
		return `<b>{def.Icon} {def.Name}: {Format.commas(State.currency(currency))}</b>\n{def.Description}`
	end)
	return { Frame = frame, Value = value, Displayed = 0 }
end

-- Construction ---------------------------------------------------------------------------

function Hud.init(ctx)
	Hud.Ctx = ctx
	local layer = ctx.Layers.Hud
	local fx = ctx.Layers.Fx

	-- Bottom dock ---------------------------------------------------------------------------
	-- Everything except the quest card lives at the bottom, so the middle of the screen
	-- stays free for the 3D world and the obby. Rows, bottom to top: navigation,
	-- currencies + level + ascension, info strip (obby, stats), boosts, save warning.
	local dock = UI.frame({
		Name = "Dock",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(DOCK_WIDTH, DOCK_HEIGHT),
		List = { Dir = "Y", Pad = 6, HA = "Center", VA = "Bottom" },
		Parent = layer,
	})
	Hud.Dock = dock
	Hud.TopBar = dock
	-- Scaled separately in Hud.layout so the dock always fits beside the PRESS button.
	Hud.DockScale = Instance.new("UIScale")
	Hud.DockScale.Parent = dock

	Hud.SaveBadge = UI.label({
		Name = "SaveBadge",
		Text = "⚠ Not saving (temporary session)",
		TextSize = 13,
		Font = F.Bold,
		TextColor3 = C.Warning,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 1,
		Visible = false,
		Parent = dock,
	})
	UI.stroke(Hud.SaveBadge, { Color = C.Black, Transparency = 0.5, Text = true })

	-- Active boosts as timer pills (filled by Hud.refreshBoosts).
	local boosts = UI.frame({
		Name = "BoostsCard",
		Size = UDim2.new(1, 0, 0, 26),
		LayoutOrder = 2,
		Visible = false,
		List = { Dir = "X", Pad = 6, HA = "Center", VA = "Center" },
		Parent = dock,
	})
	Hud.BoostsCard = boosts
	Hud.BoostLines = {}

	-- Info strip: obby progress and live stat chips.
	local info = UI.frame({
		Name = "Chips",
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 3,
		List = { Dir = "X", Pad = 6, HA = "Center", VA = "Center" },
		Parent = dock,
	})
	local obbyChip = UI.new("Frame", {
		Name = "ObbyChip",
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.1,
		LayoutOrder = 0,
		Corner = Theme.Radius.Pill,
		Stroke = { Color = C.Accent2, Thickness = 1.5, Transparency = 0.3 },
		Padding = { X = 4 },
		List = { Dir = "X", Pad = 4, VA = "Center" },
		Parent = info,
	})
	Hud.ObbyChip = obbyChip
	Hud.ObbyLabel = UI.label({
		Name = "ObbyLabel",
		Text = `🏃 Obby 0/{ObbyConfig.StageCount}`,
		Font = F.Bold,
		TextSize = 14,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		LayoutOrder = 1,
		Padding = { X = 6 },
		Parent = obbyChip,
	})
	local function obbyTeleport(to: string)
		local result = ClientNet.once("obby", "ObbyTeleport", { To = to })
		if result and not result.ok then
			ctx.Notifications.result(result)
		end
	end
	Hud.ObbyGo = UI.button({
		Name = "ObbyGo",
		Text = "▶",
		Variant = "primary",
		Size = UDim2.fromOffset(32, 24),
		TextSize = 13,
		LayoutOrder = 2,
		OnClick = function()
			obbyTeleport("checkpoint")
		end,
		Parent = obbyChip,
	})
	UI.attachTooltip(Hud.ObbyGo, "Go to your obby checkpoint. Your auto-presses keep earning while you run!")
	Hud.ObbyHome = UI.button({
		Name = "ObbyHome",
		Text = "🏠",
		Variant = "ghost",
		Size = UDim2.fromOffset(32, 24),
		TextSize = 13,
		LayoutOrder = 3,
		OnClick = function()
			obbyTeleport("plaza")
		end,
		Parent = obbyChip,
	})
	UI.attachTooltip(Hud.ObbyHome, "Back to the plaza (your obby checkpoint is kept).")

	Hud.Chips = {}
	for index, spec in ipairs({
		{ "Crit", "🎯" },
		{ "Luck", "🍀" },
		{ "Auto", "🤖" },
		{ "Multi", "✖️" },
	}) do
		local chip = UI.label({
			Name = spec[1],
			Text = spec[2],
			Font = F.Bold,
			TextSize = 14,
			TextColor3 = C.TextDim,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 28),
			BackgroundColor3 = C.Panel,
			BackgroundTransparency = 0.15,
			LayoutOrder = index,
			Corner = Theme.Radius.Pill,
			Padding = { X = 12 },
			Parent = info,
		})
		Hud.Chips[spec[1]] = chip
	end
	UI.attachTooltip(Hud.Chips.Crit, "Chance for a critical press and its multiplier.")
	UI.attachTooltip(Hud.Chips.Luck, "Luck improves the rarity odds of every crate.")
	UI.attachTooltip(Hud.Chips.Auto, "Automatic presses per second and what they earn. They keep going while you run around or do the obby.")
	UI.attachTooltip(Hud.Chips.Multi, "Total Sparks multiplier from upgrades, skills, items, ascensions and boosts.")

	-- Currencies, level and ascension progress.
	local row = UI.frame({
		Name = "Row",
		Size = UDim2.new(1, 0, 0, 54),
		LayoutOrder = 4,
		List = { Dir = "X", Pad = 8, HA = "Center", VA = "Center" },
		Parent = dock,
	})
	Hud.Pills = {
		Sparks = pill(row, "Sparks", 210, 1, true),
		Gems = pill(row, "Gems", 124, 2, false),
		Prisms = pill(row, "Prisms", 108, 3, false),
	}
	local levelFrame = UI.new("Frame", {
		Name = "Level",
		Size = UDim2.fromOffset(136, 44),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.08,
		LayoutOrder = 4,
		Corner = Theme.Radius.Pill,
		Stroke = { Color = C.Stroke, Thickness = 1.5 },
		Parent = row,
	})
	Hud.LevelLabel = UI.label({
		Text = "Lv 1",
		Font = F.Heading,
		TextSize = 16,
		Size = UDim2.new(1, -24, 0, 20),
		Position = UDim2.fromOffset(14, 3),
		Parent = levelFrame,
	})
	Hud.XPBar = UI.progress({
		Size = UDim2.new(1, -28, 0, 10),
		Position = UDim2.fromOffset(14, 26),
		Color = C.Accent3,
		Parent = levelFrame,
	})
	UI.attachTooltip(levelFrame, function()
		local p = State.progress()
		return `<b>Level {p.Level}</b>\nXP {Format.commas(p.XP)} / {Format.commas(p.XPRequired)}\nEvery level grants a Skill Point; every 5th level also grants a crate.`
	end)
	local ascend = UI.new("TextButton", {
		Name = "AscendCard",
		Size = UDim2.fromOffset(150, 44),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.08,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = 5,
		Selectable = true,
		Corner = Theme.Radius.Pill,
		Stroke = { Color = Theme.darken(C.Prisms, 0.35), Thickness = 1.5 },
		Parent = row,
	})
	Hud.AscendTitle = UI.label({
		Text = "🔷 Ascension",
		Font = F.Heading,
		TextSize = 14,
		Size = UDim2.new(1, -24, 0, 20),
		Position = UDim2.fromOffset(14, 3),
		Parent = ascend,
	})
	Hud.AscendBar = UI.progress({ Size = UDim2.new(1, -28, 0, 10), Position = UDim2.fromOffset(14, 26), Color = C.Prisms, Parent = ascend })
	Hud.AscendInfoText = ""
	UI.attachTooltip(ascend, function()
		return `<b>Next Ascension</b>\n{Hud.AscendInfoText}`
	end)
	ascend.Activated:Connect(function()
		ScreenManager.open("Ascend")
	end)

	-- Navigation (a horizontal dock; the frame keeps its old name "NavRail").
	local rail = UI.frame({
		Name = "NavRail",
		Size = UDim2.new(1, 0, 0, 62),
		LayoutOrder = 5,
		List = { Dir = "X", Pad = 6, HA = "Center", VA = "Center" },
		Parent = dock,
	})
	Hud.Rail = rail
	Hud.NavButtons = {}
	for index, nav in ipairs(NAV) do
		local button = UI.new("TextButton", {
			Name = nav.Id,
			Size = UDim2.fromOffset(NAV_BUTTON.X, NAV_BUTTON.Y),
			BackgroundColor3 = C.Panel,
			BackgroundTransparency = 0.1,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = index,
			Selectable = true,
			Corner = Theme.Radius.Medium + 2,
			Parent = rail,
		})
		local stroke = UI.stroke(button, { Color = C.StrokeSoft, Thickness = 1.5 })
		local scale = Instance.new("UIScale")
		scale.Parent = button
		local icon = UI.label({
			Name = "Icon",
			Text = nav.Icon,
			TextSize = 24,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 32),
			Position = UDim2.fromOffset(0, 4),
			Parent = button,
		})
		local text = UI.label({
			Name = "Text",
			Text = nav.Text,
			TextSize = 11,
			Font = F.Bold,
			TextColor3 = C.TextDim,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 14),
			Position = UDim2.fromOffset(0, 38),
			Parent = button,
		})
		local badge = UI.new("TextLabel", {
			Name = "Badge",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 4, 0, -4),
			Size = UDim2.fromOffset(20, 20),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = C.Accent,
			Text = "",
			TextColor3 = C.White,
			Font = F.Heading,
			TextSize = 12,
			Visible = false,
			ZIndex = 3,
			Corner = Theme.Radius.Pill,
			Padding = { X = 5 },
			Parent = button,
		})
		button.MouseEnter:Connect(function()
			UI.tween(scale, { Scale = 1.08 }, Theme.Motion.Fast)
		end)
		button.MouseLeave:Connect(function()
			UI.tween(scale, { Scale = 1 }, Theme.Motion.Fast)
		end)
		button.SelectionGained:Connect(function()
			UI.tween(scale, { Scale = 1.08 }, Theme.Motion.Fast)
		end)
		button.SelectionLost:Connect(function()
			UI.tween(scale, { Scale = 1 }, Theme.Motion.Fast)
		end)
		button.Activated:Connect(function()
			ScreenManager.toggle(nav.Id)
		end)
		UI.attachTooltip(button, nav.Text)
		Hud.NavButtons[nav.Id] = { Button = button, Stroke = stroke, Badge = badge, Text = text, Icon = icon }
	end
	ScreenManager.Changed:Connect(function(current)
		for id, nav in pairs(Hud.NavButtons) do
			local active = id == current
			nav.Stroke.Color = if active then C.Accent else C.StrokeSoft
			nav.Stroke.Thickness = if active then 2.5 else 1.5
			nav.Button.BackgroundColor3 = if active then C.PanelLight else C.Panel
		end
	end)

	-- PRESS button (bottom right) -------------------------------------------------------------
	local press = UI.frame({
		Name = "Center",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -10),
		Size = UDim2.fromOffset(PRESS_SIZE + 30, PRESS_SIZE + 62),
		Parent = layer,
	})
	Hud.Center = press
	addScale(press)
	Hud.RateLabel = UI.label({
		Name = "Rates",
		Text = "",
		TextSize = 13,
		Font = F.Bold,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 18),
		Parent = press,
	})
	UI.stroke(Hud.RateLabel, { Color = C.Black, Transparency = 0.4, Text = true })
	local combo = UI.frame({ Name = "Combo", Size = UDim2.new(1, -20, 0, 36), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 20), Parent = press })
	Hud.ComboLabel = UI.label({
		Text = "COMBO 0",
		Font = F.Heading,
		TextSize = 15,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 18),
		Parent = combo,
	})
	UI.stroke(Hud.ComboLabel, { Color = C.Black, Transparency = 0.5, Text = true })
	Hud.ComboBar = UI.progress({ Size = UDim2.new(1, 0, 0, 8), Position = UDim2.fromOffset(0, 22), Color = C.Accent, Parent = combo })
	local buttonHolder = UI.frame({
		Name = "ButtonHolder",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(PRESS_SIZE, PRESS_SIZE),
		Parent = press,
	})
	Hud.Button = BigButton.new(buttonHolder, fx, PRESS_SIZE)
	ctx.BigButton = Hud.Button

	-- Quest card (right side; the only HUD element not at the bottom) ---------------------------
	local right = UI.frame({
		Name = "RightColumn",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.4, 0),
		Size = UDim2.fromOffset(270, 116),
		List = { Dir = "Y", Pad = 10, HA = "Right", VA = "Center" },
		Parent = layer,
	})
	Hud.Right = right
	addScale(right)

	local goal = UI.new("TextButton", {
		Name = "GoalCard",
		Size = UDim2.fromOffset(270, 116),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = 1,
		Selectable = true,
		Corner = Theme.Radius.Medium,
		Stroke = { Color = C.StrokeSoft, Thickness = 1.5 },
		Padding = 12,
		Parent = right,
	})
	Hud.GoalCard = goal
	Hud.GoalTitle = UI.label({ Text = "🎯 Next goal", Font = F.Heading, TextSize = 16, Size = UDim2.new(1, 0, 0, 20), Parent = goal })
	Hud.GoalText = UI.label({
		Text = "",
		TextSize = 14,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = C.TextDim,
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, 24),
		Parent = goal,
	})
	Hud.GoalBar = UI.progress({ Size = UDim2.new(1, -90, 0, 12), Position = UDim2.fromOffset(0, 72), Color = C.Success, Parent = goal })
	Hud.GoalClaim = UI.button({
		Text = "Claim",
		Variant = "success",
		Size = UDim2.fromOffset(80, 30),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 63),
		TextSize = 14,
		Visible = false,
		OnClick = function()
			local result = ClientNet.once("starter", "ClaimStarter")
			if result then
				ctx.Notifications.result(result, "Reward claimed!")
			end
		end,
		Parent = goal,
	})
	goal.Activated:Connect(function()
		ScreenManager.open("Quests")
	end)

	-- Compact toggle for the quest card on small screens.
	Hud.SideToggle = UI.button({
		Name = "SideToggle",
		Text = "📋",
		Size = UDim2.fromOffset(44, 44),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 70),
		Variant = "ghost",
		Visible = false,
		OnClick = function()
			right.Visible = not right.Visible
		end,
		Parent = layer,
	})

	-- Wiring ------------------------------------------------------------------------------------------
	Hud.layout()
	UI.onViewportChanged(Hud.layout)

	State.subscribe({ "Currencies", "Progress", "Derived", "Stats" }, Hud.refreshTop)
	State.subscribe({ "Derived", "Stats", "Progress" }, Hud.refreshCenter)
	State.subscribe({ "Quests", "Progress", "Stats", "Derived", "Equipped", "Skills" }, Hud.refreshGoal)
	State.subscribe("Obby", Hud.refreshObby)
	State.subscribe({ "*" }, Hud.scheduleBadges)
	State.onReady(function()
		Hud.refreshTop()
		Hud.refreshCenter()
		Hud.refreshGoal()
		Hud.refreshObby()
		Hud.scheduleBadges()
	end)

	RunService.RenderStepped:Connect(Hud.step)
	task.spawn(function()
		while true do
			task.wait(0.5)
			Hud.refreshBoosts()
		end
	end)
end

-- Layout ----------------------------------------------------------------------------------------

function Hud.layout()
	local v = UI.viewport()
	local compact = UI.isCompact()
	local touch = UserInputService.TouchEnabled
	local fit = math.min(v.X / 1280, v.Y / 720)
	local base = math.clamp(fit, 0.55, 1.25)
	if compact then
		base = math.max(base, 0.62)
	end
	-- The UI Scale setting may always shrink the HUD, but only enlarge it while it still fits.
	local scale = math.min(base * Theme.UserScale, math.max(base, fit))
	for _, s in ipairs(scales) do
		s.Scale = scale
	end
	local inset = GuiService:GetGuiInset()
	local margin = 10

	-- PRESS: bottom right. Touch screens keep Roblox's jump button (bottom right) free.
	local jumpReserve = if touch then 140 else 0
	Hud.Center.Position = UDim2.new(1, -14, 1, -(margin + jumpReserve))
	local pressWidth = (PRESS_SIZE + 30) * scale

	-- Phones: icon-only navigation buttons.
	local navHeight = if compact then 46 else NAV_BUTTON.Y
	for _, nav in pairs(Hud.NavButtons) do
		nav.Text.Visible = not compact
		nav.Button.Size = UDim2.fromOffset(NAV_BUTTON.X, navHeight)
		nav.Icon.Position = UDim2.fromOffset(0, if compact then 7 else 4)
	end
	Hud.Rail.Size = UDim2.new(1, 0, 0, navHeight + 6)

	-- Dock: centred in the space beside the PRESS button (or the jump button), shrunk to fit.
	local rightReserve = if touch then 120 else pressWidth + 14 + margin
	local available = math.max(100, v.X - margin - rightReserve)
	Hud.DockScale.Scale = math.min(scale, available / DOCK_WIDTH)
	Hud.Dock.Position = UDim2.new(0, margin + available / 2, 1, -margin)

	-- Quest card: right side; on phones it hides behind a toggle under the top bar.
	Hud.Right.Visible = not compact
	Hud.SideToggle.Visible = compact
	if compact then
		Hud.Right.AnchorPoint = Vector2.new(1, 0)
		Hud.Right.Position = UDim2.new(1, -10, 0, inset.Y + 60)
		Hud.SideToggle.Position = UDim2.new(1, -10, 0, inset.Y + 8)
	else
		Hud.Right.AnchorPoint = Vector2.new(1, 0.5)
		Hud.Right.Position = UDim2.new(1, -14, 0.4, 0)
	end
	Hud.RateLabel.Visible = not compact
end

-- The HUD element a tutorial step points at ("press", "nav:Shop", "quests", "obby").
function Hud.target(key: string): GuiObject?
	if key == "press" then
		return Hud.Button.Cap
	elseif key == "quests" then
		return if Hud.Right.Visible then Hud.GoalCard else Hud.SideToggle
	elseif key == "obby" then
		return Hud.ObbyGo
	end
	local navId = string.match(key, "^nav:(.+)$")
	local nav = navId and Hud.NavButtons[navId]
	return if nav then nav.Button else nil
end

-- Refresh ------------------------------------------------------------------------------------

function Hud.refreshTop()
	local stats = State.stats()
	local progress = State.progress()
	if stats then
		local perSecond = stats.autoRate * stats.clickValue + stats.passivePerSec
		Hud.RateLabel.Text = `+{Format.short(stats.clickValue, true)} / press  ·  +{Format.short(perSecond, true)}/s auto`
		Hud.Button:SetValueText(stats.clickValue)
	end
	Hud.LevelLabel.Text = `Lv {progress.Level}`
	Hud.XPBar.Set(progress.XP / math.max(1, progress.XPRequired))
	local derived = State.get("Derived")
	Hud.SaveBadge.Visible = derived ~= nil and derived.Persistent == false
	local stage = Formulas.stageFor(progress.Rebirths)
	local frenzy = derived and derived.FrenzyEndsAt and derived.FrenzyEndsAt > workspace:GetServerTimeNow()
	local key = tostring(stage.Id) .. tostring(frenzy)
	if Hud.StageKey ~= key then
		Hud.StageKey = key
		Hud.Button:SetStage(stage.Id, frenzy == true)
	end
end

function Hud.refreshCenter()
	local stats = State.stats()
	if not stats then
		return
	end
	Hud.Chips.Crit.Text = `🎯 {Format.pct(stats.critChance)} · ×{Util.round(stats.critMultiplier, 2)}`
	Hud.Chips.Luck.Text = `🍀 +{Format.pct(stats.luck)}`
	Hud.Chips.Auto.Text = `🤖 {Util.round(stats.autoRate, 1)}/s · +{Format.short(stats.autoRate * stats.clickValue, true)}⚡`
	Hud.Chips.Multi.Text = `✖️ {Format.mult(stats.sparksMultiplier * stats.clickMultiplier)}`
	Hud.Chips.Auto.Visible = stats.autoRate > 0

	local data = State.view()
	local requirement = Formulas.rebirthRequirement(data.Rebirths)
	local run = data.Stats.SparksThisRun or 0
	local prisms = Formulas.rebirthPrisms(run, data.Rebirths, stats.prismMultiplier)
	Hud.AscendBar.Set(run / requirement, "")
	local progressText = `{Format.short(run)} / {Format.short(requirement)} Sparks this run`
	if prisms > 0 then
		Hud.AscendTitle.Text = "🔷 Ready!"
		Hud.AscendTitle.TextColor3 = C.Prisms
		Hud.AscendInfoText = `{progressText}\nReady! Ascend now for +{prisms} 🔷`
	else
		local nextStage = Formulas.nextStage(data.Rebirths)
		Hud.AscendTitle.Text = `🔷 {math.floor(math.min(1, run / requirement) * 100)}%`
		Hud.AscendTitle.TextColor3 = C.Text
		Hud.AscendInfoText = progressText
			.. "\n"
			.. (if nextStage then `Next stage: {nextStage.Name} ({nextStage.Rebirths} asc.)` else "All stages unlocked")
	end
end

local function questSummary()
	local quests = State.get("Quests")
	if not quests then
		return nil
	end
	local step = Quests.Starter[quests.StarterIndex]
	if step then
		return {
			Title = `🎯 Starter path {quests.StarterIndex}/{#Quests.Starter}`,
			Text = step.Text,
			Progress = quests.StarterProgress / step.Target,
			Label = `{Format.short(quests.StarterProgress)} / {Format.short(step.Target)}`,
			Claimable = quests.StarterProgress >= step.Target,
		}
	end
	local done, claimable = 0, false
	for _, q in ipairs(quests.Daily or {}) do
		if q.Claimed then
			done += 1
		elseif q.Progress >= q.Target then
			claimable = true
		end
	end
	return {
		Title = "📜 Daily quests",
		Text = if claimable then "A quest is ready to claim!" else `{done}/{#(quests.Daily or {})} claimed today`,
		Progress = done / math.max(1, #(quests.Daily or {})),
		Label = `{done}/{#(quests.Daily or {})}`,
		Claimable = false,
	}
end

function Hud.refreshGoal()
	local summary = questSummary()
	if not summary then
		return
	end
	Hud.GoalTitle.Text = summary.Title
	Hud.GoalText.Text = summary.Text
	Hud.GoalBar.Set(summary.Progress, summary.Label)
	Hud.GoalClaim.Visible = summary.Claimable
end

function Hud.refreshObby()
	local obby = State.get("Obby")
	local stage = if obby then obby.Stage else 0
	local done = if obby then obby.Completions else 0
	Hud.ObbyLabel.Text = `🏃 Obby {stage}/{ObbyConfig.StageCount}` .. (if done > 0 then `  🏆{done}` else "")
end

function Hud.refreshBoosts()
	local lines = {}
	local now = workspace:GetServerTimeNow()
	local derived = State.get("Derived")
	if derived and derived.FrenzyEndsAt and derived.FrenzyEndsAt > now then
		table.insert(lines, { `🔥 Frenzy ×{derived.FrenzyMultiplier or 1}`, derived.FrenzyEndsAt - now, C.Gold })
	end
	-- Boosts bought with Robux (their timer only runs while playing).
	for _, product in ipairs(DevProducts.List) do
		local endsAt = derived and derived.BoostEndsAt and derived.BoostEndsAt[product.Key]
		if product.Boost and type(endsAt) == "number" and endsAt > now then
			local amount = if product.Boost.Add then `+{math.floor(product.Boost.Add * 100 + 0.5)}%` else `×{product.Boost.Mult}`
			table.insert(lines, { `{product.Icon} {product.Name} {amount}`, endsAt - now, product.Color })
		end
	end
	local serverState = ReplicatedStorage:FindFirstChild("ServerState")
	if serverState then
		for _, id in ipairs(GameConfig.Events.Order) do
			local endsAt = serverState:GetAttribute("Event_" .. id)
			if type(endsAt) == "number" and endsAt > now then
				local def = GameConfig.Events.Definitions[id]
				table.insert(lines, { `{def.Icon} {def.Name} · {def.Description}`, endsAt - now, def.Color })
			end
		end
	end
	Hud.BoostsCard.Visible = #lines > 0
	for i, line in ipairs(lines) do
		local label = Hud.BoostLines[i]
		if not label then
			label = UI.label({
				TextSize = 13,
				Font = F.Bold,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 24),
				BackgroundColor3 = C.Panel,
				BackgroundTransparency = 0.1,
				Corner = Theme.Radius.Pill,
				Padding = { X = 10 },
				LayoutOrder = i,
				Parent = Hud.BoostsCard,
			})
			Hud.BoostLines[i] = label
		end
		label.Visible = true
		label.Text = `{line[1]}  ({Format.clock(line[2])})`
		label.TextColor3 = line[3]
	end
	for i = #lines + 1, #Hud.BoostLines do
		Hud.BoostLines[i].Visible = false
	end
	-- Frenzy start/end changes the button colour.
	Hud.refreshTop()
end

-- Badges ----------------------------------------------------------------------------------

local badgePending = false
function Hud.scheduleBadges()
	if badgePending then
		return
	end
	badgePending = true
	task.delay(0.4, function()
		badgePending = false
		Hud.refreshBadges()
	end)
end

local function setBadge(id: string, value: any)
	local nav = Hud.NavButtons[id]
	if not nav then
		return
	end
	if value == nil or value == false or value == 0 then
		nav.Badge.Visible = false
	else
		nav.Badge.Visible = true
		nav.Badge.Text = if type(value) == "number" then (if value > 99 then "99+" else tostring(value)) else "!"
	end
end

function Hud.refreshBadges()
	if not State.Ready then
		return
	end
	local data = State.view()
	local stats = State.stats()
	local sparks = State.currency("Sparks")

	local shop = false
	for _, def in ipairs(Upgrades.List) do
		local level = data.Upgrades[def.Id] or 0
		if level < def.MaxLevel and Formulas.upgradeUnlocked(def, data) and Formulas.upgradeLevelCost(def, level) <= sparks then
			shop = true
			break
		end
	end
	setBadge("Shop", shop)

	local crates = 0
	for _, n in pairs(State.get("Chests") or {}) do
		crates += n
	end
	setBadge("Chests", crates)

	local sp = State.progress().SkillPoints
	local skills = false
	for _, node in ipairs(Skills.List) do
		local rank = data.Skills[node.Id] or 0
		if rank < node.MaxRank and Skills.prerequisitesMet(node, data.Skills) and Skills.costFor(node, rank) <= sp then
			skills = true
			break
		end
	end
	setBadge("Skills", skills)

	local discovered = Formulas.discoveredCount(data)
	local claimedBook = State.get("CollectionClaimed") or {}
	local book = 0
	for _, m in ipairs(Rewards.Collection) do
		local need = if m.Count < 0 then Items.Count else m.Count
		if not claimedBook[m.Id] and discovered >= need then
			book += 1
		end
	end
	setBadge("Collection", book)

	local quests = State.get("Quests") or {}
	local questCount = 0
	for _, q in ipairs(quests.Daily or {}) do
		if not q.Claimed and q.Progress >= q.Target then
			questCount += 1
		end
	end
	local step = Quests.Starter[quests.StarterIndex or 1]
	if step and (quests.StarterProgress or 0) >= step.Target then
		questCount += 1
	end
	local daily = State.get("Daily")
	if daily and daily.LastClaimDay ~= Util.dayNumber(Util.serverTime()) then
		questCount += 1
	end
	setBadge("Quests", questCount)

	local ascend = false
	if stats then
		local requirement = Formulas.rebirthRequirement(data.Rebirths)
		ascend = (data.Stats.SparksThisRun or 0) >= requirement
		if not ascend then
			local prisms = State.currency("Prisms")
			for _, def in ipairs(Ascension.List) do
				local level = data.Ascension[def.Id] or 0
				if level < def.MaxLevel and Formulas.ascensionCost(def, level) <= prisms then
					ascend = true
					break
				end
			end
		end
	end
	setBadge("Ascend", ascend)
end

-- Per-frame: animated counters and combo decay ------------------------------------------------------

local accumulator = 0
function Hud.step(dt: number)
	accumulator += dt
	if accumulator < 1 / 30 then
		return
	end
	local step = accumulator
	accumulator = 0
	for currency, p in pairs(Hud.Pills) do
		local target = State.currency(currency)
		local shown = p.Displayed
		if Theme.ReducedMotion or shown <= 0 or target <= 0 or target / math.max(shown, 1e-9) > 1e3 or target < shown * 0.5 then
			shown = target
		else
			shown += (target - shown) * math.min(1, step * 10)
			if math.abs(target - shown) < math.max(1, target * 1e-4) then
				shown = target
			end
		end
		p.Displayed = shown
		local text = Format.short(shown)
		if p.Value.Text ~= text then
			p.Value.Text = text
		end
	end

	local stats = State.stats()
	if stats and Hud.Combo then
		local elapsed = os.clock() - (Hud.ComboAt or 0)
		if elapsed > stats.comboWindow and Hud.Combo > 0 then
			Hud.Combo = 0
			Hud.ComboLabel.Text = "COMBO 0"
			Hud.ComboLabel.TextColor3 = C.TextDim
			Hud.ComboBar.Set(0, "")
		end
	end
end

-- Server results ------------------------------------------------------------------------------------

function Hud.onClickResult(result)
	if type(result) ~= "table" then
		return
	end
	local settings = State.get("Settings") or {}
	local showNumbers = settings.FloatingNumbers ~= false
	if result.Auto or result.Passive then
		Hud.Button:ShowIncome(result, showNumbers)
		return
	end
	Hud.Button:ShowResult(result, showNumbers)
	local stats = State.stats()
	Hud.Combo = result.Combo or 0
	Hud.ComboAt = os.clock()
	if stats then
		local cap = stats.comboCap
		Hud.ComboLabel.Text = `COMBO {Hud.Combo}  ·  {Format.mult(result.ComboMult or 1)}`
		Hud.ComboLabel.TextColor3 = if Hud.Combo >= cap then C.Gold else C.Text
		Hud.ComboBar.Set(math.min(1, Hud.Combo / cap), "")
	end
	if result.Crit and settings.ScreenShake ~= false then
		Effects.shake(Hud.Ctx.Layers.Hud, 5, 0.15)
	end
	if result.Golden then
		Hud.Ctx.Notifications.golden(result.Golden)
	end
end

return Hud
