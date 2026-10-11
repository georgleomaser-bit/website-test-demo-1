-- =====================================================================
--  CLUTCH CLASH – Ego-Kamera: Modi, FOV, Rückstoß, Wackeln, Zielfernrohr (Client/Modules/FpsCamera)
--  Besitzer: WP4 (Kampf Client). Vertrag: DESIGN.md C7.4, B11.1 (Rückstoß), B12 (Rutschen), B15.2/B15.3.
--
--  Prinzip: Das Roblox-Kameramodul dreht die Kamera (bei RenderPriority.Camera) und liest dafür jeden
--  Frame die aktuelle Kamera-Blickrichtung. Wir laufen bei Camera + 1, messen die Dreh-Änderung seit
--  unserem letzten Bild (= reine Blick-Eingabe), formen sie um (Empfindlichkeit Gamepad/Touch, Y-Invertieren,
--  Zielhilfe – NIE Maus) und setzen das Bild = Basis-Blick + Rückstoß-Feder + Wackeln.
--  -> Rückstoß und Wackeln "lecken" nie in die Basis: kein Drift. Pitch immer innerhalb ±80°.
--
--  Öffentliche API (C7.4):
--    FpsCamera.SetMode(mode)              "Lobby" | "Match" | "Range" | "Spectate" | "Menu"
--        Match/Range = LockFirstPerson (Zoom 0.5), Maus-Symbol aus, Reset-Knopf aus (nur Match)
--        Lobby = Classic (max. Config.Player.LobbyZoomMax), Spectate = Classic, Menu = Maus frei
--    FpsCamera.Kick(pitchDeg, yawDeg, recover?)   Rückstoß: 85 % erholen sich über recover s, 15 % bleiben
--    FpsCamera.SetAds(alpha, zoom)        ADS-Anteil 0..1 + Zoom (FOV = Einstellung / Zoom)
--    FpsCamera.AddLookDelta(dxRad, dyRad) Touch-Feuerknopf-Ziehen; Maus-Konvention (+dx rechts, +dy runter),
--                                         roh – Empfindlichkeit (SensTouch, ADS) wendet FpsCamera an
--    FpsCamera.Shake(intensity, duration) absolutes Wackeln (Einstellung "Kamerawackeln" skaliert)
--    FpsCamera.SetScope(on)               Zielfernrohr-Overlay, Viewmodel aus
--  Zusätzlich (WP4-intern, nil-sicher nutzbar):
--    FpsCamera.SetFovOffset(key, deg)     z. B. Rutschen +6 (wird beim Zielen ausgeblendet)
--    FpsCamera.Punch(deg)                 kurzer FOV-Stoß (Pop +3)
--    FpsCamera.Mode(): string             aktueller Modus
--  Einziger FOV-Besitzer: Einstellung Fov (70–100), ADS fov/zoom, Rutschen, Punch.
-- =====================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Spring = require(Shared:WaitForChild("Spring"))

local FpsCamera = {}

type Mode = "Lobby" | "Match" | "Range" | "Spectate" | "Menu"

local player = Players.LocalPlayer
local ctx: any = nil

-- ---------------------------------------------------------------------
-- 1) KONSTANTEN
-- ---------------------------------------------------------------------
local PITCH_LIMIT = math.rad(80)
local RECOIL_KEEP = 0.15 -- 15 % bleiben (Rückstoß kontrollieren = Skill), 85 % erholen sich
local EXTERNAL_JUMP = 1.2 -- rad pro Frame: größer = jemand anderes hat die Kamera gesetzt
local FOV_MIN, FOV_MAX = 70, 100
local LOOK_DELTA_CAP = 0.5 -- rad pro AddLookDelta-Aufruf
local SHAKE_DEG = 1.1 -- Grad bei Intensität 1
local DEFAULT_LOBBY_ZOOM = 14

-- ---------------------------------------------------------------------
-- 2) ZUSTAND
-- ---------------------------------------------------------------------
local mode: Mode = "Lobby"
local modeBeforeMenu: Mode = "Lobby"
local windowOpen = false

local adsAlpha = 0
local adsZoom = 1
local scopeOn = false

local fovOffsets: { [string]: number } = {}
local fovExtra = 0 -- geglättete Summe der Offsets
local punch = 0

local hasLast = false
local baseYaw, basePitch = 0, 0
local lastYaw, lastPitch = 0, 0
local pendingLook = Vector2.zero

-- Rückstoß: kritisch gedämpfte Feder um 0 (x = Pitch rad, y = Yaw rad). Ein Kick = Geschwindigkeits-Stoß,
-- Spitze = 85 % des Kicks nach 1/ω s, zurück auf ~5 % nach RecoilRecover s. Die bleibenden 15 % wandern
-- weich (exponentiell, exakt summiert) in den Basis-Blick -> kein Drift.
local recoilSpring = Spring.new(Vector3.zero, 13, 1)
local pendingPerm = Vector3.zero
local permRate = 20
local windowPoll = 0

local shakeIntensity = 0
local shakeDuration = 0
local shakeUntil = 0
local shakeSeed = math.random() * 100

local originalMouseSens: number = 1
local appliedMouseSens: number? = nil
local appliedIcon: boolean? = nil
local settingsCache: { [string]: any }? = nil
local resetToken = 0
local zoomToken = 0

local scopeGui: ScreenGui? = nil
local scopeHole: Frame? = nil
local scopeStroke: UIStroke? = nil
local scopeBars: { Frame } = {}

-- ---------------------------------------------------------------------
-- 3) HELFER
-- ---------------------------------------------------------------------
local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function toYawPitch(look: Vector3): (number, number)
	return math.atan2(-look.X, -look.Z), math.asin(math.clamp(look.Y, -1, 1))
end

local function modules(): { [string]: any }
	return if ctx and type(ctx.Modules) == "table" then ctx.Modules else {}
end

local function settings(): { [string]: any }
	if settingsCache then
		return settingsCache
	end
	local result: { [string]: any } = {}
	local mod = modules().Settings
	if mod and type(mod.Get) == "function" then
		local ok, value = pcall(mod.Get)
		if ok and type(value) == "table" then
			result = value
		end
	elseif ctx and type(ctx.State) == "table" and type(ctx.State.Settings) == "table" then
		result = ctx.State.Settings
	end
	settingsCache = result
	return result
end

local function setting(key: string, default: any): any
	local value = settings()[key]
	if value == nil then
		local defaults = ctx and ctx.Config and ctx.Config.Client and ctx.Config.Client.DefaultSettings
		if type(defaults) == "table" and defaults[key] ~= nil then
			return defaults[key]
		end
		return default
	end
	return value
end

local function numberSetting(key: string, default: number, lo: number, hi: number): number
	local value = setting(key, default)
	if not finite(value) then
		return default
	end
	return math.clamp(value, lo, hi)
end

local function inputKind(): string
	local controls = modules().Controls
	if controls and type(controls.Input) == "function" then
		local ok, kind = pcall(controls.Input)
		if ok and type(kind) == "string" then
			return kind
		end
	end
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return "Touch"
	elseif last.Name:sub(1, 7) == "Gamepad" then
		return "Gamepad"
	end
	return "KBM"
end

local function armedMode(): boolean
	return mode == "Match" or mode == "Range"
end

local function anyWindowOpen(): boolean
	local ui = ctx and ctx.UI
	if ui and type(ui.IsAnyWindowOpen) == "function" then
		local ok, open = pcall(ui.IsAnyWindowOpen)
		if ok then
			return open == true
		end
	end
	local windows = ctx and ctx.Windows
	if windows and type(windows.IsOpen) == "function" then
		local ok, open = pcall(windows.IsOpen)
		if ok then
			return open == true
		end
	end
	return windowOpen
end

-- ADS-Empfindlichkeit (Einstellungen AdsMult / ScopeMult)
local function adsFactor(): number
	if scopeOn then
		return numberSetting("ScopeMult", 0.6, 0.2, 1.5)
	end
	local ads = numberSetting("AdsMult", 0.8, 0.2, 1.5)
	return 1 + (ads - 1) * adsAlpha
end

local function lobbyZoom(): number
	local value = ctx and ctx.Config and ctx.Config.Player and ctx.Config.Player.LobbyZoomMax
	return if finite(value) then value else DEFAULT_LOBBY_ZOOM
end

-- ---------------------------------------------------------------------
-- 4) MAUS, RESET-KNOPF, ZOOM
-- ---------------------------------------------------------------------
local function applyMouse()
	local armedNow = armedMode() and not windowOpen
	local iconOn = not armedNow
	if appliedIcon ~= iconOn then
		-- nur bei Zustandswechsel schreiben (andere Module dürfen das Symbol sonst frei setzen)
		appliedIcon = iconOn
		UserInputService.MouseIconEnabled = iconOn
	end
	local wanted = originalMouseSens
	if armedNow then
		wanted = originalMouseSens * (numberSetting("SensMouse", 0.5, 0.05, 2) / 0.5) * adsFactor()
	end
	if appliedMouseSens == nil or math.abs(wanted - appliedMouseSens) > 1e-3 then
		appliedMouseSens = wanted
		UserInputService.MouseDeltaSensitivity = wanted
	end
end

-- SetCore kann vor dem Laden der CoreScripts fehlschlagen -> mit Wiederholung (gebunden)
local function setResetButton(enabled: boolean)
	resetToken += 1
	local token = resetToken
	task.spawn(function()
		for _ = 1, 12 do
			if token ~= resetToken then
				return
			end
			local ok = pcall(function()
				StarterGui:SetCore("ResetButtonCallback", enabled)
			end)
			if ok then
				return
			end
			task.wait(0.5)
		end
	end)
end

-- Classic: kurz Mindest-Zoom setzen, damit die Kamera aus der Ego-Sicht herausfährt
local function zoomOut(distance: number, maxZoom: number)
	zoomToken += 1
	local token = zoomToken
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMaxZoomDistance = maxZoom
	player.CameraMinZoomDistance = math.min(distance, maxZoom)
	task.delay(0.15, function()
		if token == zoomToken then
			player.CameraMinZoomDistance = 0.5
		end
	end)
end

-- ---------------------------------------------------------------------
-- 5) ZIELFERNROHR-OVERLAY (Frame-Ring mit dicker UIStroke + Randbalken)
-- ---------------------------------------------------------------------
local function layoutScope()
	local gui = scopeGui
	local hole = scopeHole
	local stroke = scopeStroke
	local camera = workspace.CurrentCamera
	if not (gui and hole and stroke and camera) then
		return
	end
	local vp = camera.ViewportSize
	local d = math.floor(math.min(vp.X, vp.Y) * 0.92)
	hole.Size = UDim2.fromOffset(d, d)
	stroke.Thickness = math.ceil(d * 0.32)
	local half = d / 2
	-- links, rechts, oben, unten: alles außerhalb des Quadrats schwarz
	local bars = scopeBars
	if #bars == 4 then
		bars[1].Position = UDim2.fromOffset(0, 0)
		bars[1].Size = UDim2.new(0.5, -half + 1, 1, 0)
		bars[2].Position = UDim2.new(0.5, half - 1, 0, 0)
		bars[2].Size = UDim2.new(0.5, -half + 1, 1, 0)
		bars[3].Position = UDim2.fromOffset(0, 0)
		bars[3].Size = UDim2.new(1, 0, 0.5, -half + 1)
		bars[4].Position = UDim2.new(0, 0, 0.5, half - 1)
		bars[4].Size = UDim2.new(1, 0, 0.5, -half + 1)
	end
end

local function buildScope()
	local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
	if not playerGui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "CC_Scope"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = -1 -- unter dem HUD
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	local hole = Instance.new("Frame")
	hole.Name = "Lens"
	hole.AnchorPoint = Vector2.new(0.5, 0.5)
	hole.Position = UDim2.fromScale(0.5, 0.5)
	hole.BackgroundTransparency = 1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = hole
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = hole
	-- innerer Linsenrand
	local rim = Instance.new("Frame")
	rim.Name = "Rim"
	rim.AnchorPoint = Vector2.new(0.5, 0.5)
	rim.Position = UDim2.fromScale(0.5, 0.5)
	rim.Size = UDim2.fromScale(1, 1)
	rim.BackgroundTransparency = 1
	local rimCorner = Instance.new("UICorner")
	rimCorner.CornerRadius = UDim.new(0.5, 0)
	rimCorner.Parent = rim
	local rimStroke = Instance.new("UIStroke")
	rimStroke.Color = Color3.fromRGB(28, 32, 64)
	rimStroke.Thickness = 6
	rimStroke.Transparency = 0.2
	rimStroke.Parent = rim
	rim.Parent = hole
	-- Fadenkreuz-Linien (dünn, schwarz) + roter Punkt
	local function line(size: UDim2, pos: UDim2)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = size
		f.Position = pos
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BackgroundTransparency = 0.15
		f.Parent = hole
	end
	line(UDim2.new(1, 0, 0, 2), UDim2.fromScale(0.5, 0.5))
	line(UDim2.new(0, 2, 1, 0), UDim2.fromScale(0.5, 0.5))
	line(UDim2.new(0.18, 0, 0, 5), UDim2.fromScale(0.09, 0.5))
	line(UDim2.new(0.18, 0, 0, 5), UDim2.fromScale(0.91, 0.5))
	line(UDim2.new(0, 5, 0.18, 0), UDim2.fromScale(0.5, 0.91))
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(6, 6)
	dot.BorderSizePixel = 0
	dot.BackgroundColor3 = Color3.fromRGB(255, 59, 59)
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(0.5, 0)
	dotCorner.Parent = dot
	dot.Parent = hole
	hole.Parent = gui

	local bars: { Frame } = {}
	for i = 1, 4 do
		local bar = Instance.new("Frame")
		bar.Name = "Bar" .. i
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.Parent = gui
		bars[i] = bar
	end

	scopeGui = gui
	scopeHole = hole
	scopeStroke = stroke
	scopeBars = bars
	layoutScope()
	gui.Parent = playerGui
end

-- ---------------------------------------------------------------------
-- 6) FOV (einziger Besitzer)
-- ---------------------------------------------------------------------
local function applyFov(camera: Camera, dt: number)
	local base = numberSetting("Fov", 80, FOV_MIN, FOV_MAX)
	local target = 0
	for _, deg in pairs(fovOffsets) do
		target += deg
	end
	local k = 1 - math.exp(-dt * 12)
	fovExtra += (target - fovExtra) * k
	punch *= math.exp(-dt * 9)
	if math.abs(punch) < 1e-3 then
		punch = 0
	end
	local fov = base
	if armedMode() then
		local zoom = math.max(1, adsZoom)
		fov = base / (1 + (zoom - 1) * adsAlpha) + fovExtra * (1 - adsAlpha) + punch
	elseif mode ~= "Menu" then
		fov = base + punch
	else
		fov = camera.FieldOfView
	end
	fov = math.clamp(fov, 1, 120)
	if math.abs(camera.FieldOfView - fov) > 0.01 then
		camera.FieldOfView = fov
	end
end

-- ---------------------------------------------------------------------
-- 7) WACKELN (absolut, nie in der Basis)
-- ---------------------------------------------------------------------
local function shakeOffsets(now: number): (number, number, number)
	if now >= shakeUntil or shakeIntensity <= 0 then
		return 0, 0, 0
	end
	local scale = numberSetting("Shake", 1, 0, 1)
	if scale <= 0 then
		return 0, 0, 0
	end
	local fade = math.clamp((shakeUntil - now) / math.max(shakeDuration, 1e-3), 0, 1)
	local amp = math.rad(SHAKE_DEG) * shakeIntensity * scale * fade * fade
	local t = now * 22
	return math.noise(t, shakeSeed, 0) * amp, math.noise(shakeSeed, t, 0) * amp, math.noise(0, shakeSeed, t) * amp * 1.3
end

-- ---------------------------------------------------------------------
-- 8) KAMERA-SCHRITT (RenderPriority.Camera + 1)
-- ---------------------------------------------------------------------
local function aimAssistFilter(dt: number, look: Vector2, kind: string): Vector2
	if kind ~= "Gamepad" and kind ~= "Touch" then
		return look -- nie Maus
	end
	local assist = modules().AimAssist
	if assist and type(assist.Filter) == "function" then
		local ok, result = pcall(assist.Filter, dt, look, kind)
		if ok and typeof(result) == "Vector2" and result.X == result.X and result.Y == result.Y then
			return result
		end
	end
	return look
end

local function onCamera(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local scriptable = camera.CameraType == Enum.CameraType.Scriptable
	if not scriptable then
		applyFov(camera, dt)
	end
	-- Fenster, die am Hook vorbei geöffnet/geschlossen wurden, trotzdem erkennen (2 Hz)
	windowPoll += dt
	if windowPoll >= 0.5 then
		windowPoll = 0
		local open = anyWindowOpen()
		if open ~= windowOpen then
			windowOpen = open
		end
		if mode == "Menu" and not open then
			FpsCamera.SetMode(modeBeforeMenu)
		end
	end
	applyMouse()
	if not armedMode() or scriptable or windowOpen then
		hasLast = false
		pendingLook = Vector2.zero
		pendingPerm = Vector3.zero
		recoilSpring.Position = Vector3.zero
		recoilSpring.Velocity = Vector3.zero
		return
	end

	local cur = camera.CFrame
	local yaw, pitch = toYawPitch(cur.LookVector)
	if not hasLast then
		hasLast = true
		baseYaw, basePitch = yaw, math.clamp(pitch, -PITCH_LIMIT, PITCH_LIMIT)
		lastYaw, lastPitch = yaw, pitch
	end
	local dYaw = wrapAngle(yaw - lastYaw)
	local dPitch = pitch - lastPitch
	if math.abs(dYaw) > EXTERNAL_JUMP or math.abs(dPitch) > EXTERNAL_JUMP then
		-- fremd gesetzt (Teleport, Respawn, Admin): übernehmen statt umrechnen
		baseYaw, basePitch = yaw, math.clamp(pitch, -PITCH_LIMIT, PITCH_LIMIT)
		dYaw, dPitch = 0, 0
	end

	-- Blick-Eingabe in Maus-Konvention (+x rechts, +y runter)
	local kind = inputKind()
	local look = Vector2.new(-dYaw, -dPitch)
	local factor = adsFactor()
	if kind == "Gamepad" then
		look *= (numberSetting("SensPad", 0.5, 0.05, 2) / 0.5) * factor
	elseif kind == "Touch" then
		look *= (numberSetting("SensTouch", 0.6, 0.05, 2) / 0.6) * factor
	end
	if pendingLook ~= Vector2.zero then
		look += pendingLook * (numberSetting("SensTouch", 0.6, 0.05, 2) / 0.6) * factor
		pendingLook = Vector2.zero
		if kind == "KBM" then
			kind = "Touch" -- Feuerknopf-Ziehen ist immer Touch
		end
	end
	if setting("InvertY", false) == true then
		look = Vector2.new(look.X, -look.Y)
	end
	look = aimAssistFilter(dt, look, kind)

	baseYaw = wrapAngle(baseYaw - look.X)
	basePitch = math.clamp(basePitch - look.Y, -PITCH_LIMIT, PITCH_LIMIT)

	-- bleibender Rückstoß-Anteil weich in die Basis (Summe exakt)
	if pendingPerm ~= Vector3.zero then
		local move = pendingPerm * (1 - math.exp(-dt * permRate))
		if pendingPerm.Magnitude < 1e-6 then
			move = pendingPerm
		end
		pendingPerm -= move
		basePitch = math.clamp(basePitch + move.X, -PITCH_LIMIT, PITCH_LIMIT)
		baseYaw = wrapAngle(baseYaw + move.Y)
	end
	-- federnder Anteil
	local r = recoilSpring:Step(dt)
	if r.Magnitude < 1e-6 and recoilSpring.Velocity.Magnitude < 1e-5 then
		recoilSpring.Position = Vector3.zero
		recoilSpring.Velocity = Vector3.zero
		r = Vector3.zero
	end

	local now = os.clock()
	local sp, sy, sr = shakeOffsets(now)
	local renderPitch = math.clamp(basePitch + r.X + sp, -PITCH_LIMIT, PITCH_LIMIT)
	local renderYaw = wrapAngle(baseYaw + r.Y + sy)
	camera.CFrame = CFrame.new(cur.Position) * CFrame.fromOrientation(renderPitch, renderYaw, sr)
	lastYaw, lastPitch = renderYaw, renderPitch
end

-- ---------------------------------------------------------------------
-- 9) ÖFFENTLICHE API
-- ---------------------------------------------------------------------
function FpsCamera.SetMode(newMode: Mode)
	if
		newMode ~= "Lobby"
		and newMode ~= "Match"
		and newMode ~= "Range"
		and newMode ~= "Spectate"
		and newMode ~= "Menu"
	then
		return
	end
	if newMode == "Menu" then
		if mode ~= "Menu" then
			modeBeforeMenu = mode
		end
		mode = "Menu"
		hasLast = false
		applyMouse()
		return
	end
	local previous = mode
	mode = newMode
	hasLast = false
	if newMode == "Match" or newMode == "Range" then
		zoomToken += 1
		player.CameraMaxZoomDistance = 0.5
		player.CameraMinZoomDistance = 0.5
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		setResetButton(newMode ~= "Match")
	else
		FpsCamera.SetScope(false)
		adsAlpha = 0
		adsZoom = 1
		table.clear(fovOffsets)
		if newMode == "Lobby" then
			if previous ~= "Lobby" then
				zoomOut(10, lobbyZoom())
			end
			setResetButton(true)
		else -- Spectate
			if previous == "Match" or previous == "Range" then
				zoomOut(8, lobbyZoom())
			end
		end
	end
	applyMouse()
end

function FpsCamera.Mode(): string
	return mode
end

function FpsCamera.Kick(pitchDeg: number, yawDeg: number, recover: number?)
	if not (finite(pitchDeg) and finite(yawDeg)) then
		return
	end
	local p = math.rad(math.clamp(pitchDeg, -20, 20))
	local y = -math.rad(math.clamp(yawDeg, -20, 20)) -- +yawDeg = nach rechts
	local seconds = if finite(recover) then math.clamp(recover :: number, 0.1, 2) else 0.35
	-- kritisch gedämpft: x(t) = v0·t·e^(−ωt) -> Spitze v0/(ω·e) nach 1/ω, ~5 % Rest nach 4.7/ω
	local omega = math.clamp(4.7 / seconds, 6, 30)
	recoilSpring.Speed = omega
	recoilSpring.Damper = 1
	local kick = Vector3.new(p, y, 0)
	recoilSpring:Impulse(kick * (1 - RECOIL_KEEP) * omega * math.exp(1))
	pendingPerm += kick * RECOIL_KEEP
	permRate = omega * 1.5
end

function FpsCamera.SetAds(alpha: number, zoom: number)
	adsAlpha = if finite(alpha) then math.clamp(alpha, 0, 1) else 0
	adsZoom = if finite(zoom) then math.clamp(zoom, 1, 10) else 1
end

function FpsCamera.AddLookDelta(dxRad: number, dyRad: number)
	if not (finite(dxRad) and finite(dyRad)) then
		return
	end
	pendingLook += Vector2.new(
		math.clamp(dxRad, -LOOK_DELTA_CAP, LOOK_DELTA_CAP),
		math.clamp(dyRad, -LOOK_DELTA_CAP, LOOK_DELTA_CAP)
	)
end

function FpsCamera.Shake(intensity: number, duration: number)
	if not (finite(intensity) and finite(duration)) or intensity <= 0 or duration <= 0 then
		return
	end
	local now = os.clock()
	local remaining = if now < shakeUntil
		then shakeIntensity * (shakeUntil - now) / math.max(shakeDuration, 1e-3)
		else 0
	shakeIntensity = math.clamp(math.max(intensity, remaining), 0, 4)
	shakeDuration = math.clamp(duration, 0.05, 3)
	shakeUntil = now + shakeDuration
	shakeSeed = math.random() * 100
end

function FpsCamera.SetScope(on: boolean)
	local want = on == true
	if want == scopeOn then
		return
	end
	scopeOn = want
	if scopeGui then
		scopeGui.Enabled = want
	end
	local viewmodel = modules().Viewmodel
	if viewmodel then
		if type(viewmodel.HideFor) == "function" then
			pcall(viewmodel.HideFor, "Scope", want)
		elseif type(viewmodel.SetHidden) == "function" then
			pcall(viewmodel.SetHidden, want)
		end
	end
end

function FpsCamera.SetFovOffset(key: string, deg: number)
	if type(key) ~= "string" then
		return
	end
	if not finite(deg) or deg == 0 then
		fovOffsets[key] = nil
	else
		fovOffsets[key] = math.clamp(deg, -30, 30)
	end
end

function FpsCamera.Punch(deg: number)
	if finite(deg) then
		punch = math.clamp(punch + deg, -15, 15)
	end
end

-- ---------------------------------------------------------------------
-- 10) MODUL-FORM
-- ---------------------------------------------------------------------
function FpsCamera.Init(context: any)
	ctx = context
	originalMouseSens = UserInputService.MouseDeltaSensitivity
	if not finite(originalMouseSens) or originalMouseSens <= 0 then
		originalMouseSens = 1
	end
	buildScope()
end

function FpsCamera.Start()
	local hooks = ctx and ctx.Hooks
	if hooks and type(hooks.On) == "function" then
		hooks.On("Settings", function()
			settingsCache = nil
		end)
		hooks.On("State", function(_state: any, changed: any)
			if type(changed) == "table" and changed.Settings then
				settingsCache = nil
			end
		end)
		hooks.On("WindowOpened", function()
			windowOpen = true
			applyMouse()
		end)
		hooks.On("WindowClosed", function()
			task.defer(function()
				windowOpen = anyWindowOpen()
				applyMouse()
			end)
		end)
	end
	local function watchCamera(camera: Camera?)
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutScope)
			layoutScope()
		end
	end
	watchCamera(workspace.CurrentCamera)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		hasLast = false
		watchCamera(workspace.CurrentCamera)
	end)
	player.CharacterAdded:Connect(function()
		hasLast = false
	end)

	RunService:BindToRenderStep("CC_FpsCamera", Enum.RenderPriority.Camera.Value + 1, onCamera)
	FpsCamera.SetMode("Lobby")
end

return FpsCamera
