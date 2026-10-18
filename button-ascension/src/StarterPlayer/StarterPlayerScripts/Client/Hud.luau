--[[
	Hud (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Hud
	Depends on: ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format,Formulas,Util,Config/*},
	            Client/{State,ClientNet,ScreenManager,BigButton}

	Always-visible interface:
	  * Top bar: Sparks (per press / per second), Gems, Prisms, level + XP.
	  * Navigation rail: Shop, Crates, Inventory, Skills, Collection, Quests,
	    Ascend, Stats, Settings — with notification badges.
	  * Centre: the big button, combo meter and live stat chips.
	  * Right column: ascension progress, current goal, active boosts.
	Layout scales with the viewport and the UI Scale setting; small screens
	use a compact layout (icon-only rail, collapsible side cards).
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
	{ Id = "Settings", Icon = "⚙️", Text = "Settings" },
}

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

	-- Top bar -------------------------------------------------------------------------------
	local top = UI.frame({
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(760, 86),
		Parent = layer,
	})
	Hud.TopBar = top
	addScale(top)
	local row = UI.frame({ Name = "Row", Size = UDim2.new(1, 0, 0, 54), List = { Dir = "X", Pad = 10, HA = "Center", VA = "Center" }, Parent = top })
	Hud.Pills = {
		Sparks = pill(row, "Sparks", 250, 1, true),
		Gems = pill(row, "Gems", 140, 2, false),
		Prisms = pill(row, "Prisms", 120, 3, false),
	}
	local levelFrame = UI.new("Frame", {
		Name = "Level",
		Size = UDim2.fromOffset(150, 44),
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
		TextSize = 17,
		Size = UDim2.new(1, -24, 0, 22),
		Position = UDim2.fromOffset(14, 3),
		Parent = levelFrame,
	})
	Hud.XPBar = UI.progress({
		Size = UDim2.new(1, -28, 0, 10),
		Position = UDim2.fromOffset(14, 27),
		Color = C.Accent3,
		Parent = levelFrame,
	})
	UI.attachTooltip(levelFrame, function()
		local p = State.progress()
		return `<b>Level {p.Level}</b>\nXP {Format.commas(p.XP)} / {Format.commas(p.XPRequired)}\nEvery level grants a Skill Point; every 5th level also grants a crate.`
	end)
	Hud.RateLabel = UI.label({
		Name = "Rates",
		Text = "",
		TextSize = 14,
		Font = F.Bold,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 60),
		Parent = top,
	})
	UI.stroke(Hud.RateLabel, { Color = C.Black, Transparency = 0.5, Text = true })
	Hud.SaveBadge = UI.label({
		Name = "SaveBadge",
		Text = "⚠ Not saving (temporary session)",
		TextSize = 13,
		Font = F.Bold,
		TextColor3 = C.Warning,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.fromOffset(0, 80),
		Visible = false,
		Parent = top,
	})

	-- Navigation rail ------------------------------------------------------------------------
	local rail = UI.frame({
		Name = "NavRail",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(84, #NAV * 76),
		List = { Dir = "Y", Pad = 6, HA = "Left", VA = "Center" },
		Parent = layer,
	})
	Hud.Rail = rail
	-- Scaled separately in Hud.layout so the rail always fits below the Roblox top bar.
	Hud.RailScale = Instance.new("UIScale")
	Hud.RailScale.Parent = rail
	Hud.NavButtons = {}
	for index, nav in ipairs(NAV) do
		local button = UI.new("TextButton", {
			Name = nav.Id,
			Size = UDim2.fromOffset(72, 70),
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
			TextSize = 28,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 38),
			Position = UDim2.fromOffset(0, 6),
			Parent = button,
		})
		local text = UI.label({
			Name = "Text",
			Text = nav.Text,
			TextSize = 12,
			Font = F.Bold,
			TextColor3 = C.TextDim,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 16),
			Position = UDim2.fromOffset(0, 46),
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
			UI.tween(scale, { Scale = 1.06 }, Theme.Motion.Fast)
		end)
		button.MouseLeave:Connect(function()
			UI.tween(scale, { Scale = 1 }, Theme.Motion.Fast)
		end)
		button.SelectionGained:Connect(function()
			UI.tween(scale, { Scale = 1.06 }, Theme.Motion.Fast)
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

	-- Centre ------------------------------------------------------------------------------------
	local center = UI.frame({
		Name = "Center",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.54),
		Size = UDim2.fromOffset(460, 470),
		Parent = layer,
	})
	Hud.Center = center
	addScale(center)
	local buttonHolder = UI.frame({ Name = "ButtonHolder", Size = UDim2.fromOffset(460, 340), Parent = center })
	Hud.Button = BigButton.new(buttonHolder, fx)
	ctx.BigButton = Hud.Button

	local combo = UI.frame({ Name = "Combo", Size = UDim2.fromOffset(320, 44), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 340), Parent = center })
	Hud.ComboLabel = UI.label({
		Text = "COMBO 0",
		Font = F.Heading,
		TextSize = 18,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 22),
		Parent = combo,
	})
	UI.stroke(Hud.ComboLabel, { Color = C.Black, Transparency = 0.5, Text = true })
	Hud.ComboBar = UI.progress({ Size = UDim2.new(1, 0, 0, 10), Position = UDim2.fromOffset(0, 26), Color = C.Accent, Parent = combo })

	local chips = UI.frame({
		Name = "Chips",
		Size = UDim2.fromOffset(460, 32),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 396),
		List = { Dir = "X", Pad = 8, HA = "Center", VA = "Center" },
		Parent = center,
	})
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
			Parent = chips,
		})
		Hud.Chips[spec[1]] = chip
	end
	UI.attachTooltip(Hud.Chips.Crit, "Chance for a critical press and its multiplier.")
	UI.attachTooltip(Hud.Chips.Luck, "Luck improves the rarity odds of every crate.")
	UI.attachTooltip(Hud.Chips.Auto, "Automatic presses per second (Auto-Presser upgrade).")
	UI.attachTooltip(Hud.Chips.Multi, "Total Sparks multiplier from upgrades, skills, items, ascensions and boosts.")

	-- Right column -------------------------------------------------------------------------------
	local right = UI.frame({
		Name = "RightColumn",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(270, 420),
		List = { Dir = "Y", Pad = 10, HA = "Right", VA = "Center" },
		Parent = layer,
	})
	Hud.Right = right
	addScale(right)

	local function card(name: string, order: number, height: number)
		return UI.new("TextButton", {
			Name = name,
			Size = UDim2.fromOffset(270, height),
			BackgroundColor3 = C.Panel,
			BackgroundTransparency = 0.1,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = order,
			Selectable = true,
			Corner = Theme.Radius.Medium,
			Stroke = { Color = C.StrokeSoft, Thickness = 1.5 },
			Padding = 12,
			Parent = right,
		})
	end

	local ascend = card("AscendCard", 1, 92)
	Hud.AscendTitle = UI.label({ Text = "🔷 Next Ascension", Font = F.Heading, TextSize = 16, Size = UDim2.new(1, 0, 0, 20), Parent = ascend })
	Hud.AscendBar = UI.progress({ Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 28), Color = C.Prisms, Parent = ascend })
	Hud.AscendInfo = UI.label({ Text = "", TextSize = 13, TextColor3 = C.TextDim, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 48), Parent = ascend })
	ascend.Activated:Connect(function()
		ScreenManager.open("Ascend")
	end)

	local goal = card("GoalCard", 2, 116)
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

	local boosts = card("BoostsCard", 3, 40)
	boosts.AutomaticSize = Enum.AutomaticSize.Y
	UI.list(boosts, { Dir = "Y", Pad = 4 })
	Hud.BoostsCard = boosts
	Hud.BoostsTitle = UI.label({ Text = "⚡ Active boosts", Font = F.Heading, TextSize = 16, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 0, Parent = boosts })
	Hud.BoostLines = {}

	-- Compact toggle for side cards on small screens.
	Hud.SideToggle = UI.button({
		Name = "SideToggle",
		Text = "📋",
		Size = UDim2.fromOffset(44, 44),
		AnchorPoint = Vector2.new(1, 0.5),
		-- Above the side cards, so it stays reachable while they are shown.
		Position = UDim2.new(1, -10, 0.5, -130),
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
	State.subscribe({ "*" }, Hud.scheduleBadges)
	State.onReady(function()
		Hud.refreshTop()
		Hud.refreshCenter()
		Hud.refreshGoal()
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
	Hud.TopBar.Position = UDim2.new(0.5, 0, 0, inset.Y + 6)
	-- Phones: icon-only, shorter buttons so all nine fit the screen height.
	local buttonHeight = if compact then 50 else 70
	for _, nav in pairs(Hud.NavButtons) do
		nav.Text.Visible = not compact
		nav.Button.Size = UDim2.fromOffset(if compact then 58 else 72, buttonHeight)
	end
	local railHeight = #NAV * (buttonHeight + 6)
	Hud.Rail.Size = UDim2.fromOffset(84, railHeight)
	-- Centre the rail in the area below the inset and shrink it if it would not fit there.
	Hud.Rail.Position = UDim2.new(0, 14, 0.5, inset.Y / 2)
	Hud.RailScale.Scale = math.min(scale, math.max(0.3, (v.Y - inset.Y - 16) / railHeight))
	Hud.RateLabel.Visible = not compact
	Hud.Right.Visible = not compact
	Hud.SideToggle.Visible = compact
	Hud.Chips.Multi.Parent.Visible = not compact or v.Y > 420
	Hud.Center.Position = UDim2.fromScale(0.5, if compact then 0.58 else 0.54)
end

-- Refresh ------------------------------------------------------------------------------------

function Hud.refreshTop()
	local stats = State.stats()
	local progress = State.progress()
	if stats then
		Hud.RateLabel.Text = `+{Format.short(stats.clickValue, true)} per press  ·  +{Format.short(stats.passivePerSec, true)}/s passive`
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
	Hud.Chips.Auto.Text = `🤖 {Util.round(stats.autoRate, 1)}/s`
	Hud.Chips.Multi.Text = `✖️ {Format.mult(stats.sparksMultiplier * stats.clickMultiplier)}`
	Hud.Chips.Auto.Visible = stats.autoRate > 0

	local data = State.view()
	local requirement = Formulas.rebirthRequirement(data.Rebirths)
	local run = data.Stats.SparksThisRun or 0
	local prisms = Formulas.rebirthPrisms(run, data.Rebirths, stats.prismMultiplier)
	Hud.AscendBar.Set(run / requirement, `{Format.short(run)} / {Format.short(requirement)}`)
	if prisms > 0 then
		Hud.AscendInfo.Text = `Ready! Ascend now for +{prisms} 🔷`
		Hud.AscendInfo.TextColor3 = C.Prisms
	else
		local nextStage = Formulas.nextStage(data.Rebirths)
		Hud.AscendInfo.Text = if nextStage then `Next stage: {nextStage.Name} ({nextStage.Rebirths} asc.)` else "All stages unlocked"
		Hud.AscendInfo.TextColor3 = C.TextDim
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

function Hud.refreshBoosts()
	local lines = {}
	local now = workspace:GetServerTimeNow()
	local derived = State.get("Derived")
	if derived and derived.FrenzyEndsAt and derived.FrenzyEndsAt > now then
		table.insert(lines, { `🔥 Frenzy ×{derived.FrenzyMultiplier or 1}`, derived.FrenzyEndsAt - now, C.Gold })
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
			label = UI.label({ TextSize = 13, Font = F.Bold, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = i, Parent = Hud.BoostsCard })
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
