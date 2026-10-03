-- =====================================================================
--  HUD (immer sichtbar), im knalligen Simulator-Stil:
--   links:       große Knöpfe 🛒 Shop, 👟 Angebot, 🔥 Rebirth, 🎁 Daily
--   rechts:      quadratische Icon-Knöpfe 👽 Index, 🏃 Laufbänder, 🏠 Home, (🛠️ Admin)
--   unten links: 👟 Schritte (gelb), 💵 Geld (grün), +$/s
--   oben:        Event-Banner (Meteoritenschauer, Glück) bzw. Countdown zum nächsten Schauer
-- =====================================================================

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent:WaitForChild("UI"))

local Hud = {}

local player = Players.LocalPlayer
local ctx: any = nil
local Theme = UI.Theme

local BANNER_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BANNER_HIDE_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local OFFER_GLOW_INFO = TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local CARRY_PULSE_INFO = TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

local stepsCounter: UI.Counter
local cashCounter: UI.Counter
local stepsScale: UIScale
local cashScale: UIScale
local incomeLabel: TextLabel
local infoLabel: TextLabel
local offerButton: UI.Button? = nil
local dailyBadge: Frame
local rightBar: Frame
local carryLabel: TextLabel
local carryScale: UIScale
local carryTween: Tween? = nil
local eventBanner: Frame
local eventLabel: TextLabel
local eventShown = false
local showerPill: Frame
local showerLabel: TextLabel
local showerTint: ColorCorrectionEffect

local stepsMultText = "1"
local firstState = true

-- ---------------------------------------------------------------------
-- BAUEN
-- ---------------------------------------------------------------------
local function buildLeft()
	local bar = UI.Create("Frame", {
		Name = "LeftButtons",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(196, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = ctx.Gui,
	}, {
		UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 12) }),
	})

	UI.Button({
		Size = UDim2.new(1, 0, 0, 62),
		Text = "🛒 Shop",
		Color = Theme.Red,
		LayoutOrder = 1,
		MaxText = 30,
		Parent = bar,
	}, function()
		ctx.Windows.Toggle("Shop")
	end)

	-- Angebots-Knopf: 2x Schritte (nur wenn eingerichtet und noch nicht gekauft)
	local boots = ctx.Config.GamePassesByKey and ctx.Config.GamePassesByKey.SpeedBoots
	if boots then
		local offer = UI.Button({
			Size = UDim2.new(1, 0, 0, 74),
			Text = "👟 2x Schritte",
			Sub = "JETZT holen!",
			Color = Theme.Blue,
			LayoutOrder = 2,
			MaxText = 26,
			SubMax = 18,
			Visible = boots.Id ~= 0,
			Parent = bar,
		}, function()
			if boots.Id ~= 0 then
				MarketplaceService:PromptGamePassPurchase(player, boots.Id)
			end
		end)
		-- Goldener, pulsierender Rand -> fällt auf
		offer.Stroke.Color = Theme.Gold
		TweenService:Create(offer.Stroke, OFFER_GLOW_INFO, { Thickness = 5 }):Play()
		offerButton = offer
		UI.FetchPrice(boots.Id, Enum.InfoType.GamePass, function(price)
			if price then
				offer.SetSub("– NUR " .. price .. " R$ –")
			end
		end)
	end

	UI.Button({
		Size = UDim2.new(1, 0, 0, 62),
		Text = "🔥 Rebirth",
		Color = Theme.Orange,
		LayoutOrder = 3,
		MaxText = 30,
		Parent = bar,
	}, function()
		ctx.Windows.Toggle("Rebirth")
	end)

	local daily = UI.Button({
		Size = UDim2.new(1, 0, 0, 62),
		Text = "🎁 Daily",
		Color = Theme.Purple,
		LayoutOrder = 4,
		MaxText = 30,
		Parent = bar,
	}, function()
		ctx.Windows.Toggle("Daily")
	end)
	dailyBadge = UI.Badge(daily, "!")
end

-- Quadratischer Icon-Knopf rechts (Icon groß, Name klein darunter)
function Hud.AddRightButton(icon: string, caption: string, color: Color3, order: number, onClick: () -> ()): UI.Button
	return UI.Button({
		Size = UDim2.fromOffset(86, 86),
		Text = icon,
		Sub = caption,
		Color = color,
		LayoutOrder = order,
		MaxText = 40,
		SubMax = 15,
		Corner = 16,
		Parent = rightBar,
	}, onClick)
end

local function buildRight()
	rightBar = UI.Create("Frame", {
		Name = "RightButtons",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(86, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = ctx.Gui,
	}, {
		UI.Create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 10),
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
		}),
	})
	Hud.AddRightButton("👽", "Index", Theme.Green, 1, function()
		ctx.Windows.Toggle("Index")
	end)
	Hud.AddRightButton("🏃", "Laufbänder", Theme.Blue, 2, function()
		ctx.Windows.Toggle("Treadmills")
	end)
	Hud.AddRightButton("🏠", "Home", Color3.fromRGB(255, 180, 30), 3, function()
		ctx.Request("Home")
	end)
end

local function buildStats()
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	-- Auf dem Handy liegt unten links der Lauf-Stick -> Anzeige oben links
	local stats = UI.Create("Frame", {
		Name = "Stats",
		AnchorPoint = if touchOnly then Vector2.new(0, 0) else Vector2.new(0, 1),
		Position = if touchOnly then UDim2.fromOffset(14, 6) else UDim2.new(0, 16, 1, -14),
		Size = UDim2.fromOffset(380, 156),
		BackgroundTransparency = 1,
		Parent = ctx.Gui,
	})
	stepsScale = UI.Create("UIScale")
	local stepsLabel = UI.Label({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 46),
		Text = "👟 0",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Yellow,
		MaxText = 40,
		Outline = 3,
		Parent = stats,
	})
	stepsScale.Parent = stepsLabel
	cashScale = UI.Create("UIScale")
	local cashLabel = UI.Label({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(0, 76),
		Size = UDim2.new(1, 0, 0, 52),
		Text = "💵 $0",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Cash,
		MaxText = 46,
		Outline = 3,
		Parent = stats,
	})
	cashScale.Parent = cashLabel
	incomeLabel = UI.Label({
		Position = UDim2.fromOffset(2, 104),
		Size = UDim2.new(1, 0, 0, 24),
		Text = "+$0/s",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(190, 255, 170),
		MaxText = 22,
		Outline = 2,
		Parent = stats,
	})
	infoLabel = UI.Label({
		Position = UDim2.fromOffset(2, 130),
		Size = UDim2.new(1, 0, 0, 22),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.SubText,
		MaxText = 18,
		Outline = 2,
		Parent = stats,
	})

	local Util = ctx.Util
	stepsCounter = UI.Counter(stepsLabel, function(value: number): string
		return "👟 " .. Util.FormatNumber(value) .. "  (x" .. stepsMultText .. ")"
	end)
	cashCounter = UI.Counter(cashLabel, function(value: number): string
		return "💵 " .. Util.FormatCash(value)
	end)
end

local function buildTop()
	eventBanner = UI.Create("Frame", {
		Name = "EventBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -60),
		Size = UDim2.fromOffset(560, 42),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Visible = false,
		ZIndex = 5,
		Parent = ctx.Gui,
	}, {
		UI.Corner(14),
		UI.Stroke(Color3.new(0, 0, 0), 3),
		UI.Create("UIGradient", { Rotation = 90, Color = UI.ButtonSequence(Color3.fromRGB(255, 110, 30)) }),
	})
	eventLabel = UI.Label({
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 1, -8),
		Text = "",
		MaxText = 22,
		Outline = 2,
		ZIndex = 6,
		Parent = eventBanner,
	})
	showerPill = UI.Create("Frame", {
		Name = "NextShower",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(380, 30),
		BackgroundColor3 = Theme.PanelDark,
		BackgroundTransparency = 0.15,
		Visible = false,
		Parent = ctx.Gui,
	}, { UI.Corner(15), UI.Stroke(Color3.new(0, 0, 0), 2) })
	showerLabel = UI.Label({
		Position = UDim2.fromOffset(10, 3),
		Size = UDim2.new(1, -20, 1, -6),
		Text = "",
		TextColor3 = Theme.SubText,
		MaxText = 16,
		Outline = 1,
		Parent = showerPill,
	})

	-- Trage-Hinweis unten in der Mitte (pulsiert)
	carryScale = UI.Create("UIScale")
	carryLabel = UI.Label({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -120),
		Size = UDim2.fromOffset(600, 50),
		Text = "🏃 BRING DIE BEUTE IN DEINE BASE!",
		TextColor3 = Theme.Yellow,
		Visible = false,
		MaxText = 34,
		Outline = 3,
		Parent = ctx.Gui,
	})
	carryScale.Parent = carryLabel

	showerTint = UI.Create("ColorCorrectionEffect", {
		Name = "ShowerTint",
		Enabled = false,
		TintColor = Color3.fromRGB(255, 200, 170),
		Saturation = 0.2,
		Parent = game:GetService("Lighting"),
	})
end

-- ---------------------------------------------------------------------
-- AKTUALISIEREN
-- ---------------------------------------------------------------------
function Hud.Refresh(state: any)
	if not state then
		return
	end
	local Util = ctx.Util
	local mult = UI.FormatMult(state.StepsMult)
	if mult ~= stepsMultText then
		stepsMultText = mult
		UI.RedrawCounter(stepsCounter)
	end
	UI.SetCounter(stepsCounter, tonumber(state.Steps) or 0, firstState)
	UI.SetCounter(cashCounter, tonumber(state.Cash) or 0, firstState)
	firstState = false

	local income = "+" .. Util.FormatCash(tonumber(state.Income) or 0) .. "/s"
	local pending = tonumber(state.Pending) or 0
	local autoCollect = state.Passes and state.Passes.AutoCollect == true
	if pending >= 1 and not autoCollect then
		income ..= "   🏦 " .. Util.FormatCash(pending) .. " abholen!"
	end
	if incomeLabel.Text ~= income then
		incomeLabel.Text = income
	end
	local info = ("☄️ %d/%d    🏃 %d    🔥 %d"):format(
		math.floor(tonumber(state.UsedSlots) or 0),
		math.floor(tonumber(state.Slots) or 0),
		math.floor(tonumber(state.Speed) or 16),
		math.floor(tonumber(state.Rebirths) or 0)
	)
	if infoLabel.Text ~= info then
		infoLabel.Text = info
	end

	local offer = offerButton
	if offer then
		local boots = ctx.Config.GamePassesByKey.SpeedBoots
		local owned = state.Passes and state.Passes.SpeedBoots == true
		offer.Frame.Visible = boots ~= nil and boots.Id ~= 0 and not owned
	end
	dailyBadge.Visible = state.DailyReady == true

	local carrying = state.Carrying == true
	if carrying ~= carryLabel.Visible then
		carryLabel.Visible = carrying
		if carryTween then
			carryTween:Cancel()
			carryTween = nil
		end
		carryScale.Scale = 1
		if carrying then
			local tween = TweenService:Create(carryScale, CARRY_PULSE_INFO, { Scale = 1.08 })
			tween:Play()
			carryTween = tween
		end
	end
end

-- Jede Sekunde: Event-Banner + Countdown zum nächsten Schauer
function Hud.Tick()
	local Util = ctx.Util
	local now = workspace:GetServerTimeNow()
	local showerUntil = tonumber(ReplicatedStorage:GetAttribute("ShowerUntil")) or 0
	local luckUntil = tonumber(ReplicatedStorage:GetAttribute("LuckUntil")) or 0
	local luckMult = tonumber(ReplicatedStorage:GetAttribute("LuckMult")) or 1
	local nextShower = tonumber(ReplicatedStorage:GetAttribute("NextShowerAt")) or 0
	local parts = {}
	if showerUntil > now then
		table.insert(parts, "🌠 METEORITENSCHAUER " .. Util.FormatTime(showerUntil - now) .. " • KEINE LOCKS")
	end
	if luckUntil > now and luckMult > 1 then
		table.insert(parts, "🍀 " .. UI.FormatMult(luckMult) .. "x GLÜCK " .. Util.FormatTime(luckUntil - now))
	end
	local show = #parts > 0
	eventLabel.Text = table.concat(parts, "   ")
	if show ~= eventShown then
		eventShown = show
		if show then
			eventBanner.Visible = true
			TweenService:Create(eventBanner, BANNER_INFO, { Position = UDim2.new(0.5, 0, 0, 6) }):Play()
		else
			local hide = TweenService:Create(eventBanner, BANNER_HIDE_INFO, { Position = UDim2.new(0.5, 0, 0, -60) })
			hide.Completed:Connect(function()
				if not eventShown then
					eventBanner.Visible = false
				end
			end)
			hide:Play()
		end
	end
	showerPill.Visible = not show and nextShower > now
	if showerPill.Visible then
		showerLabel.Text = "🌠 Nächster Meteoritenschauer in " .. Util.FormatTime(nextShower - now)
	end
	showerTint.Enabled = showerUntil > now
end

-- Kleines Aufploppen, wenn Schritte oder Geld reinkommen
function Hud.PulseSteps()
	UI.Pulse(stepsScale, 0.08)
end

function Hud.PulseCash()
	UI.Pulse(cashScale, 0.14)
end

function Hud.Init(context: any)
	ctx = context
	buildLeft()
	buildRight()
	buildStats()
	buildTop()
end

return Hud
