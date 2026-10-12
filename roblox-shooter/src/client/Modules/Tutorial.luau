-- =====================================================================
--  CLUTCH CLASH – Erste Minuten / FTUE (Client/Modules/Tutorial)
--  Besitzer: WP5 (Match-UI). Vertrag: DESIGN.md B1.1 (Funnel-Schritte über Request/Server), C7.4.
--
--  Schritt 1: Willkommens-Karten ("Duelle!", "Alles erspielbar", "Fair: kein Pay-to-Win") mit
--    "ERSTES DUELL!" (Request "TutorialStart") und "Überspringen" (TutorialFlag "Skipped");
--    beim Zeigen TutorialFlag "Welcome" (Funnel 2). Nur wenn Flags.Tutorial ~= true.
--  Schritt 2: im Tutorial-Match (Match:Start Tutorial = true) je Runde eine Hinweis-Karte
--    (Bewegen/Zielen+Schießen · Nachladen/Wechseln · Rutschen), passend zum Gerät.
--  Schritt 4/5: nach dem Tutorial-Match TutorialFlag "Done", dann Pfeil-Tour Locker → Shop → Pads
--    (Leuchtpfeil + Leitstrahl, lokal), am Ende TutorialFlag "TourDone" (Funnel 8).
--  Funnel 3–7 meldet MatchService, 1 MetricsService, 9–11 WP8/WP9.
--
--  Stil: docs/STYLE-AKYTEX.md – Glas-Karten mit Akzent-Streifen, Titel Michroma, Primär-Knopf Accent,
--  "Überspringen" als Ghost; Leuchtpfeil + Leitstrahl der Tour in der Akzentfarbe.
--
--  Öffentliche API: Tutorial.ShowWelcome(), Tutorial.StartTour(), Tutorial.Init(ctx), Tutorial.Start()
-- =====================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent:WaitForChild("UI"))

local Tutorial = {}

local player = Players.LocalPlayer
local ctx: any = nil

local HINT_SECONDS = 6
local TOUR_STEP_TIMEOUT = 90

local welcome: Frame? = nil
local hintCard: Frame? = nil
local hintText: TextLabel? = nil
local hintToken = 0
local tourCard: Frame? = nil
local tourText: TextLabel? = nil
local welcomeShown = false
local tutorialMatch = false
local tutorialFinished = false
local inMatch = false
local touring = false
local tourStep = 0
local tourStepAt = 0
local tourParts: { Instance } = {}
local tourBeam: Beam? = nil
local tourConn: RBXScriptConnection? = nil
local flagsKnown = false

local function T(key: string, ...: any): string
	return if ctx then ctx.T(key, ...) else key
end

local function flags(): any
	local f = ctx.State and ctx.State.Flags
	return if type(f) == "table" then f else nil
end

local function request(action: string, arg: any?)
	task.spawn(function()
		ctx.Request(action, arg)
	end)
end

local function inputKind(): string
	local controls = ctx.Modules and ctx.Modules.Controls
	if controls and type(controls.Input) == "function" then
		local ok, kind = pcall(controls.Input)
		if ok and type(kind) == "string" then
			return kind
		end
	end
	return "KBM"
end

local function tourCfg(): any
	local modes = ctx.Config.Modes
	return if modes and type(modes.Tutorial) == "table" then modes.Tutorial else {}
end

-- ---------------------------------------------------------------------
-- 1) WILLKOMMEN (3 Karten)
-- ---------------------------------------------------------------------
local function hideWelcome()
	if welcome then
		welcome.Visible = false
	end
end

local function buildWelcome()
	local theme = UI.Theme
	-- abgedunkelter Hintergrund (Bg), darauf Titel in Michroma mit Akzent-Unterstrich und drei Glas-Karten
	local frame = UI.Create("Frame", {
		Name = "TutorialWelcome",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = theme.Bg,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 60,
		Parent = ctx.Gui,
	})
	local title = UI.Label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.1, 0),
		Size = UDim2.fromOffset(700, 44),
		Text = T("match.tutorial.welcome"),
		Font = UI.Fonts.Heading,
		MaxText = 32,
		TextColor3 = theme.Text,
		ZIndex = 61,
		Parent = frame,
	})
	UI.Create("Frame", {
		Name = "Underline",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 6),
		Size = UDim2.fromOffset(72, 3),
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		ZIndex = 61,
		Parent = title,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local row = UI.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromOffset(720, 230),
		BackgroundTransparency = 1,
		ZIndex = 61,
		Parent = frame,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 16),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	-- Akzentfarben nur als Streifen oben (Duelle Accent, erspielbar Up, fair Warn)
	local cards = {
		{ "match.tutorial.card1Title", "match.tutorial.card1Text", theme.Accent, "⚔" },
		{ "match.tutorial.card2Title", "match.tutorial.card2Text", theme.Up, "🔓" },
		{ "match.tutorial.card3Title", "match.tutorial.card3Text", theme.Warn, "⚖" },
	}
	for i, card in ipairs(cards) do
		local c = UI.Create("Frame", {
			LayoutOrder = i,
			Size = UDim2.fromOffset(224, 230),
			BackgroundColor3 = theme.Surface,
			BackgroundTransparency = 0.06,
			BorderSizePixel = 0,
			ZIndex = 62,
			Parent = row,
		}, { UI.Corner(14), UI.Stroke(nil, 1) })
		UI.Create("Frame", {
			Name = "Accent",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 0),
			Size = UDim2.new(1, -28, 0, 3),
			BackgroundColor3 = card[3],
			BorderSizePixel = 0,
			ZIndex = 63,
			Parent = c,
		}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		UI.Label({
			Position = UDim2.fromOffset(0, 16),
			Size = UDim2.new(1, 0, 0, 46),
			Text = card[4],
			MaxText = 40,
			TextColor3 = card[3],
			ZIndex = 63,
			Parent = c,
		})
		UI.Label({
			Position = UDim2.fromOffset(14, 70),
			Size = UDim2.new(1, -28, 0, 30),
			Text = UI.Upper(T(card[1])),
			Font = UI.Fonts.Strong,
			MaxText = 20,
			TextColor3 = theme.Text,
			ZIndex = 63,
			Parent = c,
		})
		UI.Label({
			Position = UDim2.fromOffset(16, 108),
			Size = UDim2.new(1, -32, 0, 108),
			Text = T(card[2]),
			Font = UI.Fonts.Body,
			MaxText = 16,
			TextColor3 = theme.Text2,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 63,
			Parent = c,
		})
	end
	UI.Button({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.72, 0),
		Size = UDim2.fromOffset(320, 64),
		Text = T("match.tutorial.start"),
		Variant = "Primary",
		MaxText = 26,
		ZIndex = 62,
		Parent = frame,
	}, function()
		hideWelcome()
		local reply = ctx.Request("TutorialStart")
		if reply == nil then
			-- Start ging nicht (z. B. Arenen voll): Karten bleiben erreichbar über das PLAY-Menü
			welcomeShown = false
		end
	end)
	UI.Button({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.72, 76),
		Size = UDim2.fromOffset(200, 44),
		Text = T("match.tutorial.skip"),
		Variant = "Ghost",
		MaxText = 18,
		ZIndex = 62,
		Parent = frame,
	}, function()
		hideWelcome()
		ctx.Request("TutorialFlag", "Skipped")
	end)
	welcome = frame
end

function Tutorial.ShowWelcome()
	if inMatch or welcomeShown then
		return
	end
	welcomeShown = true
	if welcome then
		welcome.Visible = true
	end
	request("TutorialFlag", "Welcome")
end

-- ---------------------------------------------------------------------
-- 2) HINWEIS-KARTEN im Tutorial-Match
-- ---------------------------------------------------------------------
-- Glas-Karte mit Akzent-Streifen links (Hinweise im Tutorial-Match, Pfeil-Tour)
local function glassCard(name: string, props: { [string]: any }): Frame
	local theme = UI.Theme
	local base: { [string]: any } = {
		Name = name,
		BackgroundColor3 = theme.Surface,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Visible = false,
		Parent = ctx.Gui,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	local card = UI.Create("Frame", base, { UI.Corner(14), UI.Stroke(nil, 1) })
	UI.Create("Frame", {
		Name = "Accent",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(0, 3, 1, -24),
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		ZIndex = (base.ZIndex or 1) + 1,
		Parent = card,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	return card
end

local function buildHint()
	local theme = UI.Theme
	local card = glassCard("TutorialHint", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -178),
		Size = UDim2.fromOffset(520, 84),
		ZIndex = 35,
	})
	hintText = UI.Label({
		Position = UDim2.fromOffset(20, 8),
		Size = UDim2.new(1, -36, 1, -16),
		Text = "",
		Font = UI.Fonts.Main,
		MaxText = 20,
		TextColor3 = theme.Text,
		TextWrapped = true,
		ZIndex = 36,
		Parent = card,
	})
	hintCard = card
end

local function showHint(round: number)
	local card, label = hintCard, hintText
	if not card or not label then
		return
	end
	local index = math.clamp(round, 1, 3)
	local suffix = if inputKind() == "Touch" then "Touch" elseif inputKind() == "Gamepad" then "Pad" else ""
	label.Text = T("match.tutorial.hint" .. index .. suffix)
	card.Visible = true
	hintToken += 1
	local token = hintToken
	task.delay(HINT_SECONDS, function()
		if token == hintToken and card then
			card.Visible = false
		end
	end)
end

-- ---------------------------------------------------------------------
-- 3) PFEIL-TOUR (Locker → Shop → Pads)
-- ---------------------------------------------------------------------
local function clearTourWorld()
	for _, inst in ipairs(tourParts) do
		inst:Destroy()
	end
	table.clear(tourParts)
	tourBeam = nil
end

local function finishTour()
	touring = false
	clearTourWorld()
	if tourConn then
		tourConn:Disconnect()
		tourConn = nil
	end
	if tourCard then
		tourCard.Visible = false
	end
	request("TutorialFlag", "TourDone")
	ctx.Toast(T("match.tutorial.tourDone"), "Success")
end

local function tourTargets(): { { Key: string, Pos: Vector3 } }
	local list = tourCfg().TourTargets
	return if type(list) == "table" then list else {}
end

local function stepText(key: string): string
	if key == "Shop" then
		local weaponKey = tourCfg().TourWeapon or "BuzzSMG"
		local def = ctx.Config.Weapon and ctx.Config.Weapon(weaponKey)
		local name = if def then ctx.Lang.Pick(ctx.Lang_(), def.Name) else weaponKey
		local price = if def then def.Price else 0
		return T("match.tutorial.tour.Shop", name, price)
	end
	return T("match.tutorial.tour." .. key)
end

local function buildArrow(pos: Vector3): BasePart
	-- Leuchtpfeil aus Parts (Keil nach unten + Stiel), lokal, nicht abfragbar
	local model = Instance.new("Model")
	model.Name = "TourArrow"
	local function part(className: string, size: Vector3): BasePart
		local p = Instance.new(className) :: BasePart
		p.Size = size
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = UI.Theme.Accent
		p.Parent = model
		return p
	end
	local stem = part("Part", Vector3.new(1.2, 3, 1.2))
	local tip = part("WedgePart", Vector3.new(1.2, 2.4, 2.8))
	stem.CFrame = CFrame.new(pos + Vector3.new(0, 10.5, 0))
	tip.CFrame = CFrame.new(pos + Vector3.new(0, 7.8, 0)) * CFrame.Angles(math.rad(180), 0, 0)
	local attachment = Instance.new("Attachment")
	attachment.Name = "BeamEnd"
	attachment.Position = Vector3.new(0, -1.5, 0)
	attachment.Parent = stem
	model.Parent = workspace
	table.insert(tourParts, model)
	-- Wippen (lokal, eine Tween-Schleife je Schritt)
	local info = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(stem, info, { CFrame = stem.CFrame + Vector3.new(0, 1.2, 0) }):Play()
	TweenService:Create(tip, info, { CFrame = tip.CFrame + Vector3.new(0, 1.2, 0) }):Play()
	return stem
end

local function showTourStep()
	clearTourWorld()
	local targets = tourTargets()
	local target = targets[tourStep]
	if not target then
		finishTour()
		return
	end
	tourStepAt = os.clock()
	local stem = buildArrow(target.Pos)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then
		local a0 = Instance.new("Attachment")
		a0.Name = "TourBeamStart"
		a0.Parent = root
		table.insert(tourParts, a0)
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = stem:FindFirstChild("BeamEnd") :: Attachment
		beam.Color = ColorSequence.new(UI.Theme.Accent)
		beam.Transparency = NumberSequence.new(0.35)
		beam.Width0 = 0.5
		beam.Width1 = 0.5
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.Segments = 12
		beam.Parent = root
		table.insert(tourParts, beam)
		tourBeam = beam
	end
	if tourText then
		tourText.Text = stepText(target.Key)
	end
	if tourCard then
		tourCard.Visible = true
	end
end

local function nextTourStep()
	tourStep += 1
	showTourStep()
end

local function buildTourCard()
	local theme = UI.Theme
	local card = glassCard("TutorialTour", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 90),
		Size = UDim2.fromOffset(560, 92),
		ZIndex = 34,
	})
	tourText = UI.Label({
		Position = UDim2.fromOffset(20, 8),
		Size = UDim2.new(1, -176, 1, -16),
		Text = "",
		Font = UI.Fonts.Main,
		MaxText = 20,
		TextColor3 = theme.Text,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 35,
		Parent = card,
	})
	UI.Button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(136, 50),
		Text = T("match.tutorial.next"),
		Variant = "Primary",
		MaxText = 18,
		ZIndex = 35,
		Parent = card,
	}, function()
		if touring then
			nextTourStep()
		end
	end)
	tourCard = card
end

function Tutorial.StartTour()
	if touring or inMatch then
		return
	end
	local f = flags()
	if f and f.TourDone == true then
		return
	end
	touring = true
	tourStep = 1
	showTourStep()
	if tourConn then
		tourConn:Disconnect()
	end
	local accum = 0
	tourConn = RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < 0.25 or not touring then
			return
		end
		accum = 0
		local target = tourTargets()[tourStep]
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not target then
			return
		end
		if root and root:IsA("BasePart") then
			local d = Vector3.new(root.Position.X - target.Pos.X, 0, root.Position.Z - target.Pos.Z)
			if d.Magnitude <= (tourCfg().TourRadius or 12) then
				nextTourStep()
				return
			end
			-- neue Figur: Leitstrahl neu anhängen
			if tourBeam and tourBeam.Parent ~= root then
				showTourStep()
			end
		end
		if os.clock() - tourStepAt > TOUR_STEP_TIMEOUT then
			nextTourStep()
		end
	end)
end

-- ---------------------------------------------------------------------
-- 4) INIT / START
-- ---------------------------------------------------------------------
local function checkWelcome()
	local f = flags()
	if not f then
		return
	end
	flagsKnown = true
	if f.Tutorial ~= true and not welcomeShown and not inMatch then
		Tutorial.ShowWelcome()
	end
end

function Tutorial.Init(context: any)
	ctx = context
	buildWelcome()
	buildHint()
	buildTourCard()
end

function Tutorial.Start()
	local hooks = ctx.Hooks
	hooks.On("State", function(_state, changed)
		if type(changed) == "table" and (changed.Flags or changed.Full) and not flagsKnown then
			checkWelcome()
		end
	end)
	hooks.On("Match:Found", function()
		inMatch = true
		hideWelcome()
	end)
	hooks.On("Match:Start", function(data)
		inMatch = true
		hideWelcome()
		tutorialMatch = type(data) == "table" and data.Tutorial == true
		if touring then
			touring = false
			clearTourWorld()
			if tourCard then
				tourCard.Visible = false
			end
		end
	end)
	hooks.On("Match:Prep", function(data)
		if tutorialMatch and type(data) == "table" then
			showHint(tonumber(data.Round) or 1)
		end
	end)
	hooks.On("Match:End", function()
		if tutorialMatch then
			tutorialFinished = true
			request("TutorialFlag", "Done")
		end
	end)
	hooks.On("Match:Closed", function()
		inMatch = false
		if hintCard then
			hintCard.Visible = false
		end
		if tutorialFinished then
			tutorialFinished = false
			tutorialMatch = false
			task.delay(1.5, Tutorial.StartTour)
		end
		tutorialMatch = false
	end)
	-- State schon da (Module starten nach dem ersten State)?
	if ctx.State and type(ctx.State.Flags) == "table" then
		task.defer(checkWelcome)
	end
end

return Tutorial
