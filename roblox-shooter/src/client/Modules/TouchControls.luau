-- =====================================================================
--  CLUTCH CLASH – Eigene Touch-Knöpfe (Client/Modules/TouchControls)
--  Besitzer: WP10 (Client-Hülle). Vertrag: DESIGN.md C7.4, B15.1, B15.2 (Auto-Feuer), REUSE §12.
--
--  Liegt in der UNSKALIERTEN ctx.TouchGui (ScreenInsets = DeviceSafeInsets): jeder Knopf ist
--  mindestens Config.Client.TouchButtonMin (64) Pixel groß – auch bei Knopfgröße 90 % – und nichts
--  liegt unter der Notch. Roblox-Stick und Roblox-Sprungknopf bleiben (B15.1 "Standard"); unsere
--  Knöpfe sitzen über/neben dem Sprungknopf.
--    großer FEUER-Knopf rechts (ziehen = zielen über FpsCamera.AddLookDelta) + kleiner links,
--    ZIELEN (umschalten), NACHLADEN, RUTSCHEN, UTILITY, Slot-Leiste (4 Icons, aktives Icon tippen =
--    letzte Waffe), oben rechts Scoreboard/Loadout/Inspizieren/Menü, BEREIT in der Vorbereitung.
--  Linkshänder spiegelt alles, Knopfgröße 90–130 % (Einstellungen). Automatisch sprinten bei Stick ≥ 0.9.
--  Alle Knöpfe speisen Aktionen über Controls.Emit ein (andere Module hören nur Controls).
--
--  Öffentliche API (C7.4):
--    TouchControls.Show(set)          "Match" | "Range" | "Lobby" | "None"
--    TouchControls.SetAutoFire(on)    Auto-Feuer-Anzeige/-Zustand (Standard aus Einstellung "auto")
--  Zusätzlich: TouchControls.IsAutoFire(): boolean, TouchControls.SetSlots(loadout, equipped, charges),
--    TouchControls.SetAmmo(mag, max, reloading, progress?) (Munition am FEUER-Knopf),
--    TouchControls.Frame(dt), TouchControls.Init(ctx), TouchControls.Start()
-- =====================================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent:WaitForChild("UI"))

local TouchControls = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)
local DISK = "rbxasset://textures/ui/Input/Disk_padded.png"
local RING = "rbxasset://textures/ui/Input/Ring_padded.png"
local AIM_ICON = "rbxasset://textures/ui/Input/AimStrafeButtonRegular.png"

local SLOT_NAMES = { "Primary", "Secondary", "Melee", "Utility" }
local SLOT_ACTIONS = { "Slot1", "Slot2", "Slot3", "Slot4" }

type TouchButton = {
	Name: string,
	Root: ImageButton,
	Ring: ImageLabel,
	Label: TextLabel,
	Base: number, -- Größe bei 100 %
	Sets: { [string]: boolean },
	Visible: boolean,
	Pressed: boolean,
	Color: Color3,
}

local ctx: any = nil
local holder: Frame? = nil
local buttons: { [string]: TouchButton } = {}
local slotButtons: { TouchButton } = {}
local currentSet = "Lobby"
local autoFire = false
local autoFireOverride: boolean? = nil
local adsOn = false
local readyVisible = false
local sprintFromStick = false
local equippedSlot = "Primary"
local slotLoadout: { [string]: string } = {}
local touchCfg = {
	FireSize = 116,
	SmallFireSize = 76,
	ButtonSize = 72,
	SlotSize = 66,
	SmallSize = 64,
	Margin = 16,
	LookPerPixel = 0.0065,
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

local function emit(action: string, state: string)
	local c = controls()
	if c and type(c.Emit) == "function" then
		pcall(c.Emit, action, state, "touch:" .. action)
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

-- ---------------------------------------------------------------------
-- KNOPF-BAUSTEIN (runde Scheibe + Ring, Text in der Mitte)
-- ---------------------------------------------------------------------
local function makeButton(
	name: string,
	base: number,
	color: Color3,
	text: string,
	sets: { string },
	maxText: number?
): TouchButton
	local parent = holder
	local root: ImageButton = UI.Create("ImageButton", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(base, base),
		BackgroundTransparency = 1,
		Image = DISK,
		ImageColor3 = color,
		ImageTransparency = 0.25,
		AutoButtonColor = false,
		Visible = false,
		Parent = parent,
	})
	local ring: ImageLabel = UI.Create("ImageLabel", {
		Name = "Ring",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = RING,
		ImageColor3 = WHITE,
		ImageTransparency = 0.1,
		Parent = root,
	})
	local label = UI.Label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.5),
		Text = text,
		MaxText = maxText or 22,
		Outline = 2,
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
		Label = label,
		Base = base,
		Sets = setMap,
		Visible = false,
		Pressed = false,
		Color = color,
	}
	buttons[name] = button
	return button
end

local function setPressed(button: TouchButton, on: boolean)
	button.Pressed = on
	button.Root.ImageTransparency = if on then 0.05 else 0.25
	button.Ring.ImageColor3 = if on then Color3.fromRGB(255, 230, 80) else WHITE
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

-- FEUER: halten = feuern, dabei ziehen = zielen (Blick-Delta an die FpsCamera)
local function bindFire(button: TouchButton)
	local activeInput: InputObject? = nil
	local last = Vector2.zero
	button.Root.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Touch or activeInput then
			return
		end
		activeInput = input
		last = Vector2.new(input.Position.X, input.Position.Y)
		setPressed(button, true)
		emit("Fire", "Begin")
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if input ~= activeInput then
			return
		end
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		local delta = pos - last
		last = pos
		if delta.Magnitude < 0.01 then
			return
		end
		local camera = ctx and ctx.Modules and ctx.Modules.FpsCamera
		if camera and type(camera.AddLookDelta) == "function" then
			local sens = tonumber(settings().SensTouch) or 0.6
			local k = touchCfg.LookPerPixel * sens
			pcall(camera.AddLookDelta, delta.X * k, delta.Y * k)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input == activeInput then
			activeInput = nil
			setPressed(button, false)
			emit("Fire", "End")
		end
	end)
end

-- ---------------------------------------------------------------------
-- AUFBAU
-- ---------------------------------------------------------------------
local autoBadge: TextLabel? = nil
local ammoLabel: TextLabel? = nil

local function build()
	local cfg = touchCfg
	local fire =
		makeButton("Fire", cfg.FireSize, Color3.fromRGB(255, 70, 70), T("ui.touch.fire"), { "Match", "Range" }, 26)
	bindFire(fire)
	autoBadge = UI.Label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -18),
		Size = UDim2.fromOffset(64, 18),
		Text = "AUTO",
		TextColor3 = Color3.fromRGB(120, 255, 120),
		MaxText = 16,
		Outline = 2,
		Visible = false,
		Parent = fire.Root,
	})
	fire.Label.Position = UDim2.fromScale(0.5, 0.4)
	ammoLabel = UI.Label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.74),
		Size = UDim2.fromScale(0.6, 0.24),
		Text = "",
		Font = UI.Fonts.Number,
		MaxText = 22,
		Outline = 2,
		Parent = fire.Root,
	})
	local small = makeButton(
		"FireSmall",
		cfg.SmallFireSize,
		Color3.fromRGB(255, 70, 70),
		T("ui.touch.fire"),
		{ "Match", "Range" }
	)
	bindFire(small)
	local ads = makeButton("Ads", cfg.ButtonSize, Color3.fromRGB(60, 140, 255), T("ui.touch.ads"), { "Match", "Range" })
	ads.Label.Position = UDim2.fromScale(0.5, 0.72)
	ads.Label.Size = UDim2.fromScale(0.8, 0.3)
	UI.Create("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.38),
		Size = UDim2.fromScale(0.42, 0.42),
		BackgroundTransparency = 1,
		Image = AIM_ICON,
		Parent = ads.Root,
	})
	bindTap(ads, function()
		-- Touch: immer umschalten (B15.1)
		adsOn = not adsOn
		emit("Ads", if adsOn then "Begin" else "End")
		ads.Ring.ImageColor3 = if adsOn then Color3.fromRGB(255, 230, 80) else WHITE
	end)
	local reload = makeButton("Reload", cfg.ButtonSize, Color3.fromRGB(255, 170, 40), T("ui.touch.reload"), {
		"Match",
		"Range",
	})
	bindTap(reload, function()
		tap("Reload")
	end)
	local slide =
		makeButton("Slide", cfg.ButtonSize, Color3.fromRGB(150, 110, 255), T("ui.touch.slide"), { "Match", "Range" })
	bindHold(slide, "Slide")
	local utility =
		makeButton("Utility", cfg.ButtonSize, Color3.fromRGB(70, 210, 120), T("ui.touch.utility"), { "Match", "Range" })
	bindHold(utility, "Utility")
	local ready = makeButton("Ready", cfg.ButtonSize + 8, Color3.fromRGB(70, 210, 80), T("ui.touch.ready"), { "Match" })
	bindTap(ready, function()
		tap("Ready")
	end)
	-- kleine Knöpfe oben rechts
	local smallButtons = {
		{ "Scoreboard", "📋", { "Match" } },
		{ "Loadout", "🎒", { "Match", "Range" } },
		{ "Inspect", "🔍", { "Match", "Range" } },
		{ "Menu", "⚙️", { "Match", "Range" } },
	}
	for _, spec in ipairs(smallButtons) do
		local action = spec[1] :: string
		local b =
			makeButton(action, cfg.SmallSize, Color3.fromRGB(40, 45, 70), spec[2] :: string, spec[3] :: { string }, 30)
		if action == "Scoreboard" then
			bindHold(b, action) -- Scoreboard nur solange gedrückt
		else
			bindTap(b, function()
				tap(action)
			end)
		end
	end
	-- Slot-Leiste (aktives Icon tippen = letzte Waffe)
	for i = 1, 4 do
		local b = makeButton("Slot" .. i, cfg.SlotSize, Color3.fromRGB(30, 34, 55), "", { "Match", "Range" }, 18)
		bindTap(b, function()
			if SLOT_NAMES[i] == equippedSlot then
				tap("LastWeapon")
			else
				tap(SLOT_ACTIONS[i])
			end
		end)
		table.insert(slotButtons, b)
	end
end

-- ---------------------------------------------------------------------
-- LAYOUT (über dem Roblox-Sprungknopf, Linkshänder gespiegelt)
-- ---------------------------------------------------------------------
local function place(button: TouchButton, x: number, y: number, mirror: boolean, width: number)
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
	local jumpLeft = if smallScreen then w - 95 else w - 170
	local fire = scaled(touchCfg.FireSize)
	local btn = scaled(touchCfg.ButtonSize)
	local gap = 10
	-- x-Werte sind Abstände vom rechten Rand (Mitte des Knopfs); bei Linkshändern vom linken
	local fireX = m + fire / 2 + 6
	local fireY = jumpTop - gap - fire / 2
	place(buttons.Fire, fireX, fireY, mirror, w)
	place(buttons.Reload, fireX + fire / 2 + gap + btn / 2, fireY + fire / 2 - btn / 2, mirror, w)
	local adsY = fireY - fire / 2 - gap - btn / 2
	place(buttons.Ads, fireX + fire / 2 - btn / 2, adsY, mirror, w)
	place(buttons.Utility, fireX + fire / 2 + gap + btn / 2, adsY, mirror, w)
	local slideX = (w - jumpLeft) + gap + btn / 2
	place(buttons.Slide, slideX, h - m - btn / 2, mirror, w)
	local readySize = scaled(touchCfg.ButtonSize + 8)
	place(
		buttons.Ready,
		fireX + fire / 2 + gap + btn + gap + readySize / 2,
		fireY + fire / 2 - readySize / 2,
		mirror,
		w
	)
	-- kleiner Feuerknopf auf der anderen Seite, oberhalb des Sticks
	local smallFire = scaled(touchCfg.SmallFireSize)
	place(buttons.FireSmall, w - (m + smallFire / 2 + 10), h * 0.6, mirror, w)
	-- oben rechts: Menü, Scoreboard, Loadout in einer Reihe (die Mitte bleibt frei für Timer/Score)
	local small = scaled(touchCfg.SmallSize)
	for i, name in ipairs({ "Menu", "Scoreboard", "Loadout" }) do
		place(buttons[name], m + small / 2 + (i - 1) * (small + 8), 8 + small / 2, mirror, w)
	end
	-- Inspizieren links oben unter der Lebensanzeige
	place(buttons.Inspect, w - (m + small / 2), 108 + small / 2, mirror, w)
	-- Slot-Leiste unten Mitte
	local slot = scaled(touchCfg.SlotSize)
	local totalW = 4 * slot + 3 * 8
	for i, b in ipairs(slotButtons) do
		local cx = w / 2 - totalW / 2 + slot / 2 + (i - 1) * (slot + 8)
		local s = scaled(b.Base)
		b.Root.Size = UDim2.fromOffset(s, s)
		b.Root.Position = UDim2.fromOffset(if mirror then w - cx else cx, h - m - slot / 2)
	end
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
	for name, button in pairs(buttons) do
		local visible = touch and not menu and button.Sets[currentSet] == true
		if name == "Ready" then
			visible = visible and readyVisible
		end
		if button.Visible ~= visible then
			button.Visible = visible
			button.Root.Visible = visible
		end
	end
	if autoBadge then
		autoBadge.Visible = autoFire
	end
end

function TouchControls.Show(set: string)
	if set ~= "Match" and set ~= "Range" and set ~= "Lobby" and set ~= "None" then
		warn("[TouchControls] Unbekanntes Set: " .. tostring(set))
		return
	end
	if set ~= currentSet then
		currentSet = set
		if adsOn then
			adsOn = false
			emit("Ads", "End")
			local ads = buttons.Ads
			if ads then
				ads.Ring.ImageColor3 = WHITE
			end
		end
	end
	applyVisibility()
end

-- Auto-Feuer: "auto" = an bei Touch in Casual (B15.2), "on"/"off" fest; SetAutoFire überschreibt (z. B. Ranked)
local function computeAutoFire(): boolean
	if autoFireOverride ~= nil then
		return autoFireOverride
	end
	local mode = settings().AutoFire
	if mode == "on" then
		return true
	elseif mode == "off" then
		return false
	end
	return isTouch()
end

function TouchControls.SetAutoFire(on: boolean)
	autoFireOverride = on == true
	autoFire = autoFireOverride
	applyVisibility()
end

function TouchControls.IsAutoFire(): boolean
	return autoFire
end

local function weaponShort(key: string?): string
	if type(key) ~= "string" or key == "" then
		return ""
	end
	local config = ctx and ctx.Config
	if config and type(config.Weapon) == "function" then
		local ok, def = pcall(config.Weapon, key)
		if ok and type(def) == "table" and type(def.Short) == "string" then
			return def.Short
		end
	end
	return key
end

function TouchControls.SetSlots(loadout: { [string]: string }, equipped: string, charges: { [string]: number })
	if type(loadout) == "table" then
		slotLoadout = loadout
	end
	if type(equipped) == "string" then
		equippedSlot = equipped
	end
	for i, b in ipairs(slotButtons) do
		local name = SLOT_NAMES[i]
		local text = weaponShort(slotLoadout[name])
		local charge = type(charges) == "table" and charges[name] or nil
		if name == "Utility" and type(charge) == "number" then
			text ..= " x" .. charge
		end
		b.Label.Text = text
		local active = name == equippedSlot
		b.Ring.ImageColor3 = if active then Color3.fromRGB(255, 230, 80) else WHITE
		b.Root.ImageTransparency = if active then 0.05 else 0.35
	end
end

-- Munition direkt am FEUER-Knopf (auf Touch zeigt CombatHud keine eigene Munitionsanzeige)
function TouchControls.SetAmmo(mag: number, max: number, reloading: boolean, reloadProgress: number?)
	local label = ammoLabel
	if not label or type(mag) ~= "number" or type(max) ~= "number" then
		return
	end
	local text: string
	if max <= 0 then
		text = ""
	elseif reloading then
		local p = if type(reloadProgress) == "number" then math.clamp(reloadProgress, 0, 1) else 0
		text = string.rep("•", 1 + math.floor(p * 4))
	else
		text = tostring(math.max(0, math.floor(mag)))
	end
	if label.Text ~= text then
		label.Text = text
	end
	label.TextColor3 = if mag <= 0 and not reloading and max > 0 then Color3.fromRGB(255, 80, 80) else WHITE
end

local function relabel()
	local map = {
		Fire = "ui.touch.fire",
		FireSmall = "ui.touch.fire",
		Ads = "ui.touch.ads",
		Reload = "ui.touch.reload",
		Slide = "ui.touch.slide",
		Utility = "ui.touch.utility",
		Ready = "ui.touch.ready",
	}
	for name, key in pairs(map) do
		local b = buttons[name]
		if b then
			b.Label.Text = T(key)
		end
	end
end

-- Jeder Frame (nur Touch im Kampf): automatisch sprinten, wenn der Stick ≥ 0.9 ausgelenkt ist
function TouchControls.Frame(_dt: number)
	if currentSet ~= "Match" and currentSet ~= "Range" then
		if sprintFromStick then
			sprintFromStick = false
			emit("Sprint", "End")
		end
		return
	end
	if not isTouch() then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local magnitude = humanoid and humanoid.MoveDirection.Magnitude or 0
	local want = magnitude >= 0.9
	if want ~= sprintFromStick then
		sprintFromStick = want
		emit("Sprint", if want then "Begin" else "End")
	end
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
				if type(value) == "number" and touchCfg[key] ~= nil then
					touchCfg[key] = value
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
	autoFire = computeAutoFire()
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)

	local hooks = ctx.Hooks
	hooks.On("Input", function()
		autoFire = computeAutoFire()
		applyVisibility()
	end)
	hooks.On("Settings", function()
		autoFire = computeAutoFire()
		relabel()
		layout()
		applyVisibility()
	end)
	hooks.On("WindowOpened", applyVisibility)
	hooks.On("WindowClosed", applyVisibility)
	-- Standard-Sets aus den Spiel-Ereignissen (WeaponClient darf jederzeit Show aufrufen)
	local armedSet = "Match"
	hooks.On("Armed", function(info)
		local isRange = type(info) == "table" and info.Ctx == "Range"
		armedSet = if isRange then "Range" else "Match"
		TouchControls.Show(armedSet)
	end)
	hooks.On("Disarmed", function()
		readyVisible = false
		TouchControls.Show("Lobby")
	end)
	hooks.On("LocalPopped", function()
		TouchControls.Show("None")
	end)
	hooks.On("LocalRevived", function()
		TouchControls.Show(armedSet)
	end)
	hooks.On("Match:Prep", function()
		readyVisible = true
		applyVisibility()
	end)
	hooks.On("Match:Live", function()
		readyVisible = false
		applyVisibility()
	end)
	hooks.On("Match:Closed", function()
		readyVisible = false
		applyVisibility()
	end)
end

function TouchControls.Start()
	layout()
	relabel()
	applyVisibility()
end

return TouchControls
