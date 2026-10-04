-- =====================================================================
--  HUD (immer sichtbar), im knalligen Simulator-Stil:
--   links:        ⭐ STARTER-PAKET (bis gekauft), 🛒 Shop, 👟 Angebot, 🔥 Rebirth, 🎁 Daily
--   rechts:       Icon-Knöpfe in 2 Spalten: 🎁 Geschenke, 🎡 Glücksrad, 📜 Aufgaben (mit Badges),
--                 👽 Index, 🏃 Laufbänder, 🏠 Home, (🛠️ Admin)
--   unten links:  👟 Schritte (gelb), 💵 Geld (grün), +$/s
--   oben:         Banner (Meteoritenschauer/Glück, 🥚 Egg Rush) bzw. Countdowns bis zum nächsten
--   unten Mitte:  Wegweiser (🏠 Base beim Tragen / 🥚 nächstes Ei im Egg Rush), Trage-Hinweis,
--                 Prompt-Hinweis an der Parade (E = Klauen gratis, F = Kaufen)
-- =====================================================================

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent:WaitForChild("UI"))

local Hud = {}

local player = Players.LocalPlayer
local ctx: any = nil
local Theme = UI.Theme
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local BANNER_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BANNER_HIDE_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local OFFER_GLOW_INFO = TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local CARRY_PULSE_INFO = TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local STARTER_WOBBLE_INFO = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

local NAV_INTERVAL = 1 / 30 -- Wegweiser-Pfeil 30x pro Sekunde drehen
local EGG_SCAN_INTERVAL = 0.25 -- so oft wird das nächste Ei gesucht
local HOME_SCAN_INTERVAL = 1 -- so oft wird die eigene Base gesucht (Position bleibt sonst gemerkt)
local CARRY_WARN = 15 -- ab so wenigen Sekunden wird die Trage-Zeit rot
local HOLD_SAFETY = 10 -- Sekunden: angehaltene Zähler laufen spätestens dann weiter

local stepsCounter: UI.Counter
local cashCounter: UI.Counter
local stepsScale: UIScale
local cashScale: UIScale
local cashLabelRef: TextLabel? = nil
local lastRebirths: number? = nil
local incomeLabel: TextLabel
local infoLabel: TextLabel
local offerButton: UI.Button? = nil
local starterButton: UI.Button? = nil
local starterSubText = "Super-Angebot!"
local dailyBadge: Frame
local giftBadge: Frame
local wheelBadge: Frame
local questBadge: Frame
local rightBar: Frame
local showerTint: ColorCorrectionEffect

local stepsMultText = "1"
local firstState = true
local holdCount = 0
local holdToken = 0

-- ---------------------------------------------------------------------
-- BANNER OBEN (Pillen nebeneinander, ploppen weich auf/zu)
-- ---------------------------------------------------------------------
type Pill = { Frame: Frame, Label: TextLabel, Scale: UIScale, Shown: boolean, Token: number }

local topBar: Frame
local eventPill: Pill
local eggPill: Pill
local showerNextPill: Pill
local eggNextPill: Pill

local function makePill(name: string, width: number, height: number, color: Color3?, order: number): Pill
	local banner = color ~= nil
	local frame: Frame = UI.Create("Frame", {
		Name = name,
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = if banner then WHITE else Theme.PanelDark,
		BackgroundTransparency = if banner then 0 else 0.15,
		Visible = false,
		LayoutOrder = order,
		ZIndex = 5,
		Parent = topBar,
	}, { UI.Corner(if banner then 14 else 15), UI.Stroke(BLACK, if banner then 3 else 2) })
	if color then
		UI.Create("UIGradient", { Rotation = 90, Color = UI.ButtonSequence(color), Parent = frame })
	end
	local scale: UIScale = UI.Create("UIScale", { Scale = 0, Parent = frame })
	local label = UI.Label({
		Position = UDim2.fromOffset(10, if banner then 4 else 3),
		Size = UDim2.new(1, -20, 1, if banner then -8 else -6),
		Text = "",
		TextColor3 = if banner then WHITE else Theme.SubText,
		MaxText = if banner then 22 else 16,
		Outline = if banner then 2 else 1,
		ZIndex = 6,
		Parent = frame,
	})
	return { Frame = frame, Label = label, Scale = scale, Shown = false, Token = 0 }
end

local function showPill(pill: Pill, show: boolean)
	if pill.Shown == show then
		return
	end
	pill.Shown = show
	pill.Token += 1
	local token = pill.Token
	if show then
		pill.Frame.Visible = true
		pill.Scale.Scale = 0.4
		TweenService:Create(pill.Scale, BANNER_INFO, { Scale = 1 }):Play()
	else
		local hide = TweenService:Create(pill.Scale, BANNER_HIDE_INFO, { Scale = 0 })
		hide.Completed:Connect(function()
			if pill.Token == token then
				pill.Frame.Visible = false
			end
		end)
		hide:Play()
	end
end

local function setPillText(pill: Pill, text: string)
	if pill.Label.Text ~= text then
		pill.Label.Text = text
	end
end

-- ---------------------------------------------------------------------
-- UNTEN MITTE: Wegweiser, Trage-Hinweis, Prompt-Hinweis (Liste: leere Teile rücken zusammen)
-- ---------------------------------------------------------------------
local navFrame: Frame
local navArrow: TextLabel
local navLabel: TextLabel
local carryHolder: Frame
local carryLabel: TextLabel
local carryScale: UIScale
local carryTween: Tween? = nil
local hintFrame: Frame
local hintLabel: TextLabel
local statusPill: Frame
local statusLabel: TextLabel

local carrying = false
local carryStartedAt = 0
local promptHintKind: string? = nil
local mapFolder: Instance? = nil
local groundFolder: Instance? = nil
local myPlot: Model? = nil
local homePos: Vector3? = nil
local nearestEgg: BasePart? = nil
local lastNavKey = math.huge -- erzwingt das erste Schreiben

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

	-- ⭐ STARTER-PAKET: auffällig (Gold, wackelt), solange nicht gekauft und eingerichtet
	local starter = ctx.Config.ProductsByKey and ctx.Config.ProductsByKey.StarterPack
	if starter then
		local button = UI.Button({
			Size = UDim2.new(1, 0, 0, 76),
			Text = "⭐ STARTER-PAKET",
			Sub = "Super-Angebot!",
			Color = Theme.Gold,
			LayoutOrder = 0,
			MaxText = 24,
			SubMax = 17,
			Visible = false, -- erst zeigen, wenn der State sagt: noch nicht gekauft
			Parent = bar,
		}, function()
			-- nur einmal kaufbar: Windows sperrt den Knopf bis zur Antwort (kein Doppelkauf per Doppelklick)
			ctx.Windows.BuyStarter()
		end)
		button.Stroke.Color = Color3.fromRGB(255, 255, 255)
		TweenService:Create(button.Stroke, OFFER_GLOW_INFO, { Thickness = 5 }):Play()
		button.Button.Rotation = -2.5
		TweenService:Create(button.Button, STARTER_WOBBLE_INFO, { Rotation = 2.5 }):Play()
		starterButton = button
		UI.FetchPrice(starter.Id, Enum.InfoType.Product, function(price)
			if price then
				starterSubText = "🔥 NUR " .. price .. " R$ 🔥"
				button.SetSub(starterSubText)
			end
		end)
	end

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
	-- 2 Spalten: so passen alle Knöpfe auch auf kleine Handy-Bildschirme
	rightBar = UI.Create("Frame", {
		Name = "RightButtons",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(86 * 2 + 10, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = ctx.Gui,
	}, {
		UI.Create("UIGridLayout", {
			CellSize = UDim2.fromOffset(86, 86),
			CellPadding = UDim2.fromOffset(10, 10),
			FillDirection = Enum.FillDirection.Horizontal,
			FillDirectionMaxCells = 2,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local gifts = Hud.AddRightButton("🎁", "Geschenke", Theme.Purple, 1, function()
		ctx.Windows.Toggle("Gifts")
	end)
	giftBadge = UI.Badge(gifts, "")
	local wheel = Hud.AddRightButton("🎡", "Glücksrad", Color3.fromRGB(255, 110, 190), 2, function()
		ctx.Windows.Toggle("Wheel")
	end)
	wheelBadge = UI.Badge(wheel, "")
	local quests = Hud.AddRightButton("📜", "Aufgaben", Theme.Cyan, 3, function()
		ctx.Windows.Toggle("Quests")
	end)
	questBadge = UI.Badge(quests, "")
	Hud.AddRightButton("👽", "Index", Theme.Green, 4, function()
		ctx.Windows.Toggle("Index")
	end)
	Hud.AddRightButton("🏃", "Laufbänder", Theme.Blue, 5, function()
		ctx.Windows.Toggle("Treadmills")
	end)
	Hud.AddRightButton("🏠", "Home", Color3.fromRGB(255, 180, 30), 6, function()
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
	cashLabelRef = cashLabel
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
	topBar = UI.Create("Frame", {
		Name = "TopBanners",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(860, 42),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = ctx.Gui,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
	})
	eventPill = makePill("EventBanner", 440, 42, Color3.fromRGB(255, 110, 30), 1)
	eggPill = makePill("EggRushBanner", 400, 42, Color3.fromRGB(255, 200, 40), 2)
	showerNextPill = makePill("NextShower", 250, 30, nil, 3)
	eggNextPill = makePill("NextEggRush", 250, 30, nil, 4)

	showerTint = UI.Create("ColorCorrectionEffect", {
		Name = "ShowerTint",
		Enabled = false,
		TintColor = Color3.fromRGB(255, 200, 170),
		Saturation = 0.2,
		Parent = game:GetService("Lighting"),
	})
end

local function buildBottom()
	local stack = UI.Create("Frame", {
		Name = "BottomCenter",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -80), -- darunter liegt die Werkzeug-Leiste von Roblox
		Size = UDim2.fromOffset(700, 260),
		BackgroundTransparency = 1,
		Parent = ctx.Gui,
	}, {
		UI.Create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, 6),
		}),
	})

	-- Status (👻 Umhang)
	statusPill = UI.Create("Frame", {
		Name = "Status",
		Size = UDim2.fromOffset(300, 32),
		BackgroundColor3 = Theme.PanelDark,
		BackgroundTransparency = 0.1,
		Visible = false,
		LayoutOrder = 0,
		Parent = stack,
	}, { UI.Corner(16), UI.Stroke(BLACK, 2) })
	statusLabel = UI.Label({
		Position = UDim2.fromOffset(10, 3),
		Size = UDim2.new(1, -20, 1, -6),
		Text = "",
		TextColor3 = Color3.fromRGB(200, 210, 255),
		MaxText = 18,
		Outline = 2,
		Parent = statusPill,
	})

	-- Wegweiser: Pfeil + Entfernung (Base beim Tragen, nächstes Ei im Egg Rush)
	navFrame = UI.Create("Frame", {
		Name = "Navigator",
		Size = UDim2.fromOffset(440, 46),
		BackgroundColor3 = Theme.PanelDark,
		BackgroundTransparency = 0.1,
		Visible = false,
		LayoutOrder = 1,
		Parent = stack,
	}, { UI.Corner(14), UI.Stroke(BLACK, 3) })
	navArrow = UI.Label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 28, 0.5, 0),
		Size = UDim2.fromOffset(40, 40),
		Text = "⬆️",
		MaxText = 34,
		Parent = navFrame,
	})
	navLabel = UI.Label({
		Position = UDim2.fromOffset(54, 5),
		Size = UDim2.new(1, -64, 1, -10),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 22,
		Outline = 2,
		Parent = navFrame,
	})

	-- Trage-Hinweis (pulsiert; im Halter, damit das Pulsieren die Liste nicht verschiebt)
	carryHolder = UI.Create("Frame", {
		Name = "Carry",
		Size = UDim2.fromOffset(620, 48),
		BackgroundTransparency = 1,
		Visible = false,
		LayoutOrder = 2,
		Parent = stack,
	})
	carryScale = UI.Create("UIScale")
	carryLabel = UI.Label({
		Size = UDim2.fromScale(1, 1),
		Text = "🏃 BRING DIE BEUTE IN DEINE BASE!",
		TextColor3 = Theme.Yellow,
		MaxText = 34,
		Outline = 3,
		Parent = carryHolder,
	})
	carryScale.Parent = carryLabel

	-- Prompt-Hinweis an der Parade / an Eiern am Boden
	hintFrame = UI.Create("Frame", {
		Name = "PromptHint",
		Size = UDim2.fromOffset(680, 40),
		BackgroundColor3 = Theme.PanelDark,
		BackgroundTransparency = 0.12,
		Visible = false,
		LayoutOrder = 3,
		Parent = stack,
	}, { UI.Corner(12), UI.Stroke(BLACK, 2) })
	hintLabel = UI.Label({
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 1, -8),
		Text = "",
		MaxText = 18,
		Outline = 2,
		Parent = hintFrame,
	})
end

-- ---------------------------------------------------------------------
-- PROMPT-HINWEIS (Prompts meldet, welche Art Prompt gerade sichtbar ist)
-- ---------------------------------------------------------------------
-- "Touch" (Handy/Tablet), "Gamepad" (Controller) oder "Keyboard" (PC) – nach der letzten Eingabe,
-- vor der ersten Eingabe nach dem Gerät geraten
local function inputStyle(): string
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return "Touch"
	elseif last.Name:sub(1, 7) == "Gamepad" then
		return "Gamepad"
	elseif last == Enum.UserInputType.Keyboard or last.Name:sub(1, 5) == "Mouse" then
		return "Keyboard"
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Gamepad"
	end
	return "Keyboard"
end
Hud.InputStyle = inputStyle

local function hintText(kind: string, state: any): string
	local style = inputStyle()
	local grabKey = if style == "Gamepad" then "[X] halten" elseif style == "Touch" then "Halten" else "[E] halten"
	local buyKey = if style == "Gamepad" then "[Y]" elseif style == "Touch" then "Tippen" else "[F]"
	local full = state ~= nil
		and (tonumber(state.UsedSlots) or 0) >= (tonumber(state.Slots) or math.huge)
		and state.HasPlot ~= false
	if full then
		return "📦 Deine Base ist voll – verkauf erst etwas!"
	end
	if kind == "Parade" then
		if carrying then
			return "🏃 Erst heimbringen!   💵 " .. buyKey .. " = KAUFEN geht trotzdem"
		end
		return "🦹 " .. grabKey .. " = KLAUEN (gratis, selbst heimtragen!)   💵 " .. buyKey .. " = KAUFEN"
	elseif kind == "Ground" then
		if carrying then
			return "🏃 Du trägst schon etwas – erst heimbringen!"
		end
		return "🥚 " .. grabKey .. " = SCHNAPPEN – dann schnell in deine Base!"
	elseif kind == "Free" then
		return "🎁 "
			.. (if style == "Keyboard" then "[E]" else grabKey)
			.. " = HOLEN – fliegt direkt in deine Base!"
	end
	return ""
end

local function updateHint()
	local kind = promptHintKind
	local text = if kind then hintText(kind, ctx.State) else ""
	local show = text ~= ""
	if hintFrame.Visible ~= show then
		hintFrame.Visible = show
	end
	if show and hintLabel.Text ~= text then
		hintLabel.Text = text
	end
end

-- kind: "Parade" (Alien-Parade), "Ground" (Ei am Boden), "Free" (Gratis-Zone) oder nil
function Hud.SetPromptHint(kind: string?)
	if kind ~= promptHintKind then
		promptHintKind = kind
		updateHint()
	end
end

-- ---------------------------------------------------------------------
-- WEGWEISER
-- ---------------------------------------------------------------------
local function findMyPlot(): Model?
	local plot = myPlot
	if plot and plot.Parent and plot:GetAttribute("OwnerUserId") == player.UserId then
		return plot
	end
	myPlot = nil
	local map = mapFolder
	local plots = map and map:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	for _, child in ipairs(plots:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("OwnerUserId") == player.UserId then
			myPlot = child
			return child
		end
	end
	return nil
end

local function eggRushActive(): boolean
	local untilTime = tonumber(ReplicatedStorage:GetAttribute("EggRushUntil")) or 0
	return untilTime > workspace:GetServerTimeNow()
end

-- Nächstes Ei am Boden, das man schnappen kann (GrabPrompt an)
local function scanEggs(rootPos: Vector3)
	nearestEgg = nil
	local folder = groundFolder
	if not folder then
		return
	end
	local best = math.huge
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			local prompt = child:FindFirstChild("GrabPrompt")
			if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled then
				local dist = (child.Position - rootPos).Magnitude
				if dist < best then
					best = dist
					nearestEgg = child
				end
			end
		end
	end
end

local function setNavVisible(show: boolean)
	if navFrame.Visible ~= show then
		navFrame.Visible = show
	end
end

local navClock = 0
local eggClock = EGG_SCAN_INTERVAL
local homeClock = HOME_SCAN_INTERVAL
local function stepNav(dt: number)
	navClock += dt
	eggClock += dt
	homeClock += dt
	if navClock < NAV_INTERVAL then
		return
	end
	navClock = 0
	local camera = workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not camera or not root or not root:IsA("BasePart") then
		setNavVisible(false)
		return
	end
	local rootPos = root.Position
	local target: Vector3? = nil
	local home = false
	if carrying then
		-- Basen bewegen sich nicht: Position nur ab und zu neu holen (kein CFrame pro Frame)
		if homeClock >= HOME_SCAN_INTERVAL then
			homeClock = 0
			local plot = findMyPlot()
			homePos = if plot then plot:GetPivot().Position else nil
		end
		target = homePos
		home = true
	elseif eggRushActive() then
		if eggClock >= EGG_SCAN_INTERVAL then
			eggClock = 0
			scanEggs(rootPos)
		end
		local egg = nearestEgg
		if egg and egg.Parent then
			target = egg.Position
		end
	end
	if not target then
		setNavVisible(false)
		return
	end
	local rel = Vector3.new(target.X - rootPos.X, 0, target.Z - rootPos.Z)
	local distance = math.floor(rel.Magnitude)
	-- Pfeil relativ zur Blickrichtung der Kamera (oben = geradeaus)
	local _, yaw = camera.CFrame:ToEulerAnglesYXZ()
	navArrow.Rotation = (180 - math.deg(math.atan2(-rel.X, -rel.Z) - yaw)) % 360 - 180 -- -180..180
	-- Text nur neu schreiben, wenn sich Meter oder Sekunden geändert haben
	local left = 0
	local key
	if home then
		-- echte Trage-Zeit vom Server (lange Heimwege, z.B. Meteor-Run-Ei, bekommen mehr Zeit)
		local timeout = tonumber(player:GetAttribute("CarryTimeout")) or tonumber(ctx.Config.CarryTimeout) or 60
		left = math.clamp(math.ceil(timeout - (os.clock() - carryStartedAt)), 0, 999)
		key = distance * 1000 + left
	else
		key = -1 - distance
	end
	if key ~= lastNavKey then
		lastNavKey = key
		if home then
			navLabel.Text = ("🏠 Base: %d m   ⏱️ %d s"):format(distance, left)
			navLabel.TextColor3 = if left <= CARRY_WARN then Color3.fromRGB(255, 120, 120) else WHITE
		else
			navLabel.Text = ("🥚 Nächstes Ei: %d m – schnell!"):format(distance)
			navLabel.TextColor3 = Theme.Yellow
		end
	end
	setNavVisible(true)
end

-- ---------------------------------------------------------------------
-- BADGES (rechte Knöpfe)
-- ---------------------------------------------------------------------
local function updateBadges(state: any)
	local Util = ctx.Util
	local summary = ctx.Rewards.Summary(state)
	if summary.GiftsReady > 0 then
		UI.SetBadge(giftBadge, tostring(summary.GiftsReady), Theme.Red, true)
	elseif summary.NextGiftIn then
		UI.SetBadge(giftBadge, Util.FormatTime(math.ceil(summary.NextGiftIn)), Theme.PanelLight, false)
	else
		UI.SetBadge(giftBadge, nil)
	end
	local spins = summary.Spins + (if summary.FreeReady then 1 else 0)
	if spins > 0 then
		UI.SetBadge(
			wheelBadge,
			if spins > 99 then "99+" else tostring(spins),
			if summary.FreeReady then Theme.Green else Theme.Red,
			summary.FreeReady
		)
	else
		UI.SetBadge(wheelBadge, nil)
	end
	if summary.QuestsReady > 0 then
		UI.SetBadge(questBadge, tostring(summary.QuestsReady), Theme.Red, true)
	else
		UI.SetBadge(questBadge, nil)
	end
end

-- ---------------------------------------------------------------------
-- AKTUALISIEREN
-- ---------------------------------------------------------------------
local function setCarrying(now: boolean)
	if now == carrying then
		return
	end
	carrying = now
	if now then
		carryStartedAt = os.clock()
	end
	carryHolder.Visible = now
	if carryTween then
		carryTween:Cancel()
		carryTween = nil
	end
	carryScale.Scale = 1
	if now then
		local tween = TweenService:Create(carryScale, CARRY_PULSE_INFO, { Scale = 1.08 })
		tween:Play()
		carryTween = tween
	end
end

-- ⭐ Starter-Paket-Knopf: zeigen, solange nicht gekauft und eingerichtet. Läuft gerade ein Kauf,
-- steht "⏳" darauf (ein zweiter Klick wäre ein zweiter Kauf – Windows.BuyStarter ignoriert ihn).
local function updateStarter(state: any)
	local starter = starterButton
	if not starter or not state then
		return
	end
	local product = ctx.Config.ProductsByKey.StarterPack
	local show = product ~= nil and product.Id ~= 0 and state.StarterBought == false
	if starter.Frame.Visible ~= show then
		starter.Frame.Visible = show
	end
	starter.SetSub(if ctx.Windows.StarterPending() then "⏳ Kauf läuft..." else starterSubText)
end

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
	-- Beim Glücksrad bleiben die Zähler kurz stehen (zählen hoch, wenn das Rad steht)
	if holdCount == 0 or firstState then
		UI.SetCounter(stepsCounter, tonumber(state.Steps) or 0, firstState)
		UI.SetCounter(cashCounter, tonumber(state.Cash) or 0, firstState)
	end
	firstState = false

	-- 🔥 Rebirth geschafft? -> Bildschirm-Blitz (nur wenn die Zahl steigt, nicht beim ersten Laden)
	local rebirths = tonumber(state.Rebirths) or 0
	if lastRebirths ~= nil and rebirths > lastRebirths and ctx.Effects and ctx.Effects.RebirthFlash then
		ctx.Effects.RebirthFlash()
	end
	lastRebirths = rebirths

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
	updateStarter(state)
	dailyBadge.Visible = state.DailyReady == true
	updateBadges(state)

	setCarrying(state.Carrying == true)
	updateHint()
end

-- Zähler anhalten (true) / weiterlaufen lassen (false). Verschachtelbar, mit Sicherheits-Zeit.
function Hud.HoldCounters(on: boolean)
	if on then
		holdCount += 1
		holdToken += 1
		local token = holdToken
		task.delay(HOLD_SAFETY, function()
			if holdToken == token and holdCount > 0 then
				holdCount = 0
				if ctx.State then
					Hud.Refresh(ctx.State)
				end
			end
		end)
	elseif holdCount > 0 then
		holdCount -= 1
		if holdCount == 0 and ctx.State then
			Hud.Refresh(ctx.State)
		end
	end
end

-- Jede Sekunde: Banner + Countdowns + Badges
function Hud.Tick()
	local Util = ctx.Util
	local now = workspace:GetServerTimeNow()
	local showerUntil = tonumber(ReplicatedStorage:GetAttribute("ShowerUntil")) or 0
	local luckUntil = tonumber(ReplicatedStorage:GetAttribute("LuckUntil")) or 0
	local luckMult = tonumber(ReplicatedStorage:GetAttribute("LuckMult")) or 1
	local nextShower = tonumber(ReplicatedStorage:GetAttribute("NextShowerAt")) or 0
	local rushUntil = tonumber(ReplicatedStorage:GetAttribute("EggRushUntil")) or 0
	local nextRush = tonumber(ReplicatedStorage:GetAttribute("NextEggRushAt")) or 0

	local parts = {}
	if showerUntil > now then
		table.insert(parts, "🌠 SCHAUER " .. Util.FormatTime(showerUntil - now) .. " • KEINE LOCKS")
	end
	if luckUntil > now and luckMult > 1 then
		table.insert(parts, "🍀 " .. UI.FormatMult(luckMult) .. "x GLÜCK " .. Util.FormatTime(luckUntil - now))
	end
	local eventShown = #parts > 0
	if eventShown then
		setPillText(eventPill, table.concat(parts, "   "))
	end
	showPill(eventPill, eventShown)

	local rush = rushUntil > now
	if rush then
		setPillText(eggPill, "🥚 EGG RUSH " .. Util.FormatTime(rushUntil - now) .. " • schnapp dir die Eier!")
	end
	showPill(eggPill, rush)

	local showShowerNext = showerUntil <= now and nextShower > now
	if showShowerNext then
		setPillText(showerNextPill, "🌠 Schauer in " .. Util.FormatTime(nextShower - now))
	end
	showPill(showerNextPill, showShowerNext)
	local showRushNext = not rush and nextRush > now
	if showRushNext then
		setPillText(eggNextPill, "🥚 Egg Rush in " .. Util.FormatTime(nextRush - now))
	end
	showPill(eggNextPill, showRushNext)
	showerTint.Enabled = showerUntil > now

	-- 👻 Umhang aktiv?
	local cloakUntil = tonumber(player:GetAttribute("CloakedUntil")) or 0
	local cloaked = cloakUntil > now
	if cloaked then
		local text = "👻 Unsichtbar – noch " .. math.ceil(cloakUntil - now) .. " s"
		if statusLabel.Text ~= text then
			statusLabel.Text = text
		end
	end
	if statusPill.Visible ~= cloaked then
		statusPill.Visible = cloaked
	end

	local state = ctx.State
	if state then
		updateBadges(state)
		updateStarter(state)
	end
	-- Eingabegerät gewechselt (Tastatur <-> Handy/Controller)? Hinweis neu schreiben
	updateHint()
end

-- Die Map ist da (vom Server gebaut): Wegweiser kann Basen und Eier finden
function Hud.SetMap(map: Instance)
	mapFolder = map
	task.spawn(function()
		groundFolder = map:WaitForChild("GroundMeteors", 60)
	end)
end

-- Banner-Leiste oben: andere Module (z.B. Night) hängen eigene Pillen an (LayoutOrder = Platz)
function Hud.TopBar(): Frame?
	return topBar
end

-- Kleines Aufploppen, wenn Schritte oder Geld reinkommen
function Hud.PulseSteps()
	UI.Pulse(stepsScale, 0.08)
end

function Hud.PulseCash(amount: number?)
	UI.Pulse(cashScale, amount or 0.14)
end

-- Bildschirm-Punkt des 💵-Symbols am Geld-Zähler (Ziel der fliegenden Münzen), nil = nicht sichtbar
function Hud.CashAnchor(): Vector2?
	local label = cashLabelRef
	if not label or not label.Visible or not ctx.Gui.Enabled then
		return nil
	end
	local size = label.AbsoluteSize
	return label.AbsolutePosition + Vector2.new(size.Y * 0.5, size.Y * 0.5)
end

function Hud.Init(context: any)
	ctx = context
	buildLeft()
	buildRight()
	buildStats()
	buildTop()
	buildBottom()
	RunService.RenderStepped:Connect(stepNav)
	player.CharacterAdded:Connect(function()
		nearestEgg = nil
		homeClock = HOME_SCAN_INTERVAL
	end)
end

return Hud
