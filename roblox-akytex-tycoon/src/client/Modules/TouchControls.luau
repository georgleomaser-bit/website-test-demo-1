-- =====================================================================
--  AKYTEX TYCOON – Eigene Touch-Knöpfe (Client/Modules/TouchControls)
--  Besitzer: WP2 (Client-Plattform & UI-Kit). Vertrag: DESIGN.md §C7.5. Muster: CC-TouchControls (REUSE §1.4 PATTERN).
--
--  Liegt in der UNSKALIERTEN ctx.TouchGui (ScreenInsets = DeviceSafeInsets): jeder Knopf ist mindestens
--  Config.Client.TouchButtonMin (64) Pixel groß – auch bei Knopfgröße 90 % – und nichts liegt unter der Notch.
--  Roblox-Stick und Roblox-Sprungknopf bleiben (Sprung = im Auto aussteigen); unsere Knöpfe sitzen über/neben dem
--  Sprungknopf:
--    Set "World":    SPRINT (halten; automatisch ab Stick-Auslenkung 0,9) · REAKTION (tippen -> Aktion "React")
--    Set "Vehicle":  BOOST (halten, groß) · HANDBREMSE (halten)
--    Set "Terminal": keine Welt-Knöpfe (das Terminal hat eigene Kauf-/Verkauf-Leiste ≥ 64 px)
--    Set "None":     alles aus
--  Linkshänder spiegelt alles, Knopfgröße 90–130 % (Einstellungen). Alle Knöpfe speisen Aktionen über
--  Controls.Emit ein (andere Module hören nur Controls). Fenster offen oder Fotomodus -> Knöpfe weg.
--  AKYTEX-Look: dunkle Glas-Scheiben (Bg2, halb durchsichtig) mit feinem Ring; gedrückt = heller + Accent-Ring + Feder 0.94.
--
--  Öffentliche API (§C7.5):
--    TouchControls.Show(set)          "World" | "Vehicle" | "Terminal" | "None"
--  Zusätzlich: TouchControls.Current(): string, TouchControls.Init(ctx), TouchControls.Start()
--  Standard-Sets kommen automatisch aus den Hooks ("Vehicle:Enter/Exit", Terminal-Fenster); Show überschreibt.
-- =====================================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent:WaitForChild("UI"))

local TouchControls = {}

local player = Players.LocalPlayer
local Theme = UI.Theme
local WHITE = Color3.new(1, 1, 1)
local GLASS = Theme.Bg2 -- Scheiben-Fläche
local GLASS_T = 0.38 -- normal halb durchsichtig (Welt bleibt sichtbar)
local GLASS_T_DOWN = 0.12 -- gedrückt / aktiv
local RING_IDLE = Theme.Text2
local RING_IDLE_T = 0.55
local PRESS_SCALE = 0.94
local SETS = { World = true, Vehicle = true, Terminal = true, None = true }

type TouchButton = {
	Name: string,
	Root: ImageButton,
	Ring: UIStroke,
	Scale: UIScale,
	Label: TextLabel,
	Base: number, -- Größe bei 100 %
	Sets: { [string]: boolean },
	Visible: boolean,
	Pressed: boolean,
	Color: Color3,
	TextKey: string,
}

local ctx: any = nil
local holder: Frame? = nil
local buttons: { [string]: TouchButton } = {}
local autoSet = "World" -- aus den Hooks
local manualSet: string? = nil -- per Show gesetzt (bis zum nächsten Hook-Wechsel)
local inVehicle = false
local photoMode = false
local sprintFromStick = false
local moveConn: RBXScriptConnection? = nil
local touchCfg = {
	ButtonSize = 76,
	BigSize = 96,
	SmallSize = 64,
	Margin = 16,
	AutoSprint = 0.9,
}
local minSize = 64

-- ---------------------------------------------------------------------
-- HILFEN
-- ---------------------------------------------------------------------
local function T(key: string, ...: any): string
	if ctx and type(ctx.T) == "function" then
		return ctx.T(key, ...)
	end
	return key
end

local function settings(): { [string]: any }
	local module = ctx and ctx.Modules and ctx.Modules.Settings
	if module and type(module.Get) == "function" then
		local ok, value = pcall(module.Get)
		if ok and type(value) == "table" then
			return value
		end
	end
	local config = ctx and ctx.Config
	return config and config.Client and config.Client.DefaultSettings or {}
end

local function controls(): any
	return ctx and ctx.Modules and ctx.Modules.Controls
end

local function emit(action: string, state: string, source: string?)
	local c = controls()
	if c and type(c.Emit) == "function" then
		pcall(c.Emit, action, state, source or ("touch:" .. action))
	end
end

local function tap(action: string)
	emit(action, "Begin")
	emit(action, "End")
end

local function isTouch(): boolean
	local c = controls()
	if c and type(c.Input) == "function" then
		local ok, kind = pcall(c.Input)
		if ok then
			return kind == "Touch"
		end
	end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function scaled(base: number): number
	local scale = tonumber(settings().ButtonScale) or 1
	return math.max(minSize, math.floor(base * math.clamp(scale, 0.9, 1.3) + 0.5))
end

local function currentSet(): string
	return manualSet or autoSet
end

-- ---------------------------------------------------------------------
-- KNOPF-BAUSTEIN (runde Glas-Scheibe + feiner Ring, Text in der Mitte)
-- ---------------------------------------------------------------------
local function makeButton(name: string, base: number, color: Color3, textKey: string, sets: { string }): TouchButton
	local ring: UIStroke = UI.Create("UIStroke", {
		Name = "Ring",
		Color = RING_IDLE,
		Transparency = RING_IDLE_T,
		Thickness = 1.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
	local scale: UIScale = UI.Create("UIScale")
	local root: ImageButton = UI.Create("ImageButton", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(base, base),
		BackgroundColor3 = color,
		BackgroundTransparency = GLASS_T,
		Image = "",
		AutoButtonColor = false,
		Visible = false,
		Parent = holder,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }), ring, scale })
	local label = UI.Label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.36),
		Text = T(textKey),
		TextColor3 = WHITE,
		MaxText = 16,
		Outline = 1,
		Parent = root,
	})
	local setMap: { [string]: boolean } = {}
	for _, s in ipairs(sets) do
		setMap[s] = true
	end
	local button: TouchButton = {
		Name = name,
		Root = root,
		Ring = ring,
		Scale = scale,
		Label = label,
		Base = base,
		Sets = setMap,
		Visible = false,
		Pressed = false,
		Color = color,
		TextKey = textKey,
	}
	buttons[name] = button
	return button
end

local function paint(button: TouchButton)
	local lit = button.Pressed
	button.Root.BackgroundTransparency = if lit then GLASS_T_DOWN else GLASS_T
	button.Ring.Color = if lit then Theme.Accent else RING_IDLE
	button.Ring.Transparency = if lit then 0 else RING_IDLE_T
	button.Ring.Thickness = if lit then 2 else 1.5
	button.Scale.Scale = if lit then PRESS_SCALE else 1
end

local function setPressed(button: TouchButton, on: boolean)
	if button.Pressed ~= on then
		button.Pressed = on
		paint(button)
	end
end

-- Halten-Knopf: Begin beim Drücken, End beim Loslassen (auch wenn der Finger rausrutscht)
local function bindHold(button: TouchButton, action: string)
	local activeInput: InputObject? = nil
	button.Root.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Touch or activeInput then
			return
		end
		activeInput = input
		setPressed(button, true)
		emit(action, "Begin")
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input == activeInput then
			activeInput = nil
			setPressed(button, false)
			emit(action, "End")
		end
	end)
	-- Knopf verschwindet während des Haltens (Fenster geht auf): sauber loslassen
	button.Root:GetPropertyChangedSignal("Visible"):Connect(function()
		if not button.Root.Visible and activeInput then
			activeInput = nil
			setPressed(button, false)
			emit(action, "End")
		end
	end)
end

local function bindTap(button: TouchButton, fn: () -> ())
	button.Root.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		setPressed(button, true)
		fn()
		task.delay(0.12, function()
			setPressed(button, false)
		end)
	end)
end

-- ---------------------------------------------------------------------
-- AUFBAU
-- ---------------------------------------------------------------------
local function build()
	local cfg = touchCfg
	local sprint = makeButton("Sprint", cfg.ButtonSize, GLASS, "ui.touch.sprint", { "World" })
	bindHold(sprint, "Sprint")
	local react = makeButton("React", cfg.SmallSize, GLASS, "ui.touch.react", { "World" })
	bindTap(react, function()
		tap("React")
	end)
	local boost = makeButton("Boost", cfg.BigSize, Theme.Accent, "ui.touch.boost", { "Vehicle" })
	bindHold(boost, "Boost")
	local brake = makeButton("Handbrake", cfg.ButtonSize, GLASS, "ui.touch.handbrake", { "Vehicle" })
	bindHold(brake, "Handbrake")
end

-- ---------------------------------------------------------------------
-- LAYOUT (über dem Roblox-Sprungknopf, Linkshänder gespiegelt)
-- ---------------------------------------------------------------------
local function place(button: TouchButton?, x: number, y: number, mirror: boolean, width: number)
	if not button then
		return
	end
	local size = scaled(button.Base)
	button.Root.Size = UDim2.fromOffset(size, size)
	local px = if mirror then x else width - x
	button.Root.Position = UDim2.fromOffset(px, y)
end

local function layout()
	local frame = holder
	if not frame then
		return
	end
	local size = frame.AbsoluteSize
	local w, h = size.X, size.Y
	if w < 10 or h < 10 then
		return
	end
	local mirror = settings().LeftHanded == true
	local m = touchCfg.Margin
	-- Roblox-Sprungknopf: klein (70 px, rechts 25 / unten 20) auf kleinen Schirmen, sonst 120 px (rechts 170 / unten 210)
	local smallScreen = math.min(w, h) <= 500
	local jumpTop = if smallScreen then h - 90 else h - 210
	local jumpCenterX = if smallScreen then 60 else 110 -- Abstand vom rechten Rand
	local gap = 12
	-- x-Werte sind Abstände vom rechten Rand (Mitte des Knopfs); bei Linkshändern vom linken
	local btn = scaled(touchCfg.ButtonSize)
	local big = scaled(touchCfg.BigSize)
	local small = scaled(touchCfg.SmallSize)
	-- Welt: SPRINT direkt über dem Sprungknopf, REAKTION links daneben
	local sprintY = jumpTop - gap - btn / 2
	place(buttons.Sprint, jumpCenterX, sprintY, mirror, w)
	place(buttons.React, jumpCenterX + btn / 2 + gap + small / 2, sprintY + (btn - small) / 2, mirror, w)
	-- Auto: BOOST groß über dem Sprungknopf, HANDBREMSE links daneben auf Daumenhöhe
	local boostY = jumpTop - gap - big / 2
	place(buttons.Boost, math.max(m + big / 2, jumpCenterX), boostY, mirror, w)
	place(buttons.Handbrake, jumpCenterX + big / 2 + gap + btn / 2, boostY + (big - btn) / 2, mirror, w)
end

-- ---------------------------------------------------------------------
-- SICHTBARKEIT
-- ---------------------------------------------------------------------
local function windowOpen(): boolean
	local ui = ctx and ctx.UI
	if ui and type(ui.IsAnyWindowOpen) == "function" then
		local ok, open = pcall(ui.IsAnyWindowOpen)
		return ok and open == true
	end
	return false
end

local function applyVisibility()
	local touch = isTouch()
	local menu = windowOpen()
	local set = currentSet()
	for _, button in pairs(buttons) do
		local visible = touch and not menu and not photoMode and button.Sets[set] == true
		if button.Visible ~= visible then
			button.Visible = visible
			button.Root.Visible = visible
		end
	end
	-- Auto-Sprint endet, sobald der Sprint-Knopf nicht mehr gilt
	if sprintFromStick and (set ~= "World" or not touch or menu) then
		sprintFromStick = false
		emit("Sprint", "End", "touch:stick")
	end
end

function TouchControls.Show(set: string)
	if not SETS[set] then
		warn("[TouchControls] Unbekanntes Set: " .. tostring(set))
		return
	end
	manualSet = set
	applyVisibility()
end

function TouchControls.Current(): string
	return currentSet()
end

local function setAuto(set: string)
	autoSet = set
	manualSet = nil -- ein echter Zustandswechsel hebt eine manuelle Wahl auf
	applyVisibility()
end

local function refreshAuto()
	local windows = ctx and ctx.Windows
	local terminal = false
	if windows and type(windows.IsOpen) == "function" then
		local ok, open = pcall(windows.IsOpen, "Terminal")
		terminal = ok and open == true
	end
	if terminal then
		setAuto("Terminal")
	elseif inVehicle then
		setAuto("Vehicle")
	else
		setAuto("World")
	end
end

local function relabel()
	for _, button in pairs(buttons) do
		button.Label.Text = T(button.TextKey)
	end
end

-- Automatisch sprinten, wenn der Stick ≥ AutoSprint ausgelenkt ist (ereignisgesteuert, kein Frame-Loop)
local function watchHumanoid(character: Model)
	if moveConn then
		moveConn:Disconnect()
		moveConn = nil
	end
	sprintFromStick = false
	local hum = character:WaitForChild("Humanoid", 10)
	if not hum or not hum:IsA("Humanoid") then
		return
	end
	local humanoid = hum :: Humanoid
	moveConn = humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function()
		if not isTouch() or currentSet() ~= "World" or windowOpen() then
			if sprintFromStick then
				sprintFromStick = false
				emit("Sprint", "End", "touch:stick")
			end
			return
		end
		local want = humanoid.MoveDirection.Magnitude >= touchCfg.AutoSprint
		if want ~= sprintFromStick then
			sprintFromStick = want
			emit("Sprint", if want then "Begin" else "End", "touch:stick")
		end
	end)
end

function TouchControls.Init(context: any)
	ctx = context
	local config = ctx.Config
	local client = config and config.Client
	if client then
		if type(client.TouchButtonMin) == "number" then
			minSize = math.max(44, client.TouchButtonMin)
		end
		if type(client.Touch) == "table" then
			for key, value in pairs(client.Touch) do
				if type(value) == "number" and (touchCfg :: any)[key] ~= nil then
					(touchCfg :: any)[key] = value
				end
			end
		end
	end
	local frame: Frame = UI.Create("Frame", {
		Name = "TouchControls",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = ctx.TouchGui,
	})
	holder = frame
	build()
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)

	local hooks = ctx.Hooks
	hooks.On("Input", applyVisibility)
	hooks.On("Settings", function()
		relabel()
		layout()
		applyVisibility()
	end)
	hooks.On("WindowOpened", refreshAuto)
	hooks.On("WindowClosed", refreshAuto)
	hooks.On("Vehicle:Enter", function()
		inVehicle = true
		refreshAuto()
	end)
	hooks.On("Vehicle:Exit", function()
		inVehicle = false
		refreshAuto()
	end)
	hooks.On("PhotoMode", function(on)
		photoMode = on == true
		applyVisibility()
	end)
end

function TouchControls.Start()
	layout()
	relabel()
	applyVisibility()
	player.CharacterAdded:Connect(function(character)
		task.spawn(watchHumanoid, character)
	end)
	if player.Character then
		task.spawn(watchHumanoid, player.Character)
	end
end

return TouchControls
