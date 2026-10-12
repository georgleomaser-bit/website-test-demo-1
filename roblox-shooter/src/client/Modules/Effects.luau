-- =====================================================================
--  CLUTCH CLASH – Bildschirm-Effekte vom Server (Client/Modules/Effects)
--  Besitzer: WP10 (Client-Hülle). Basis: Meteor-Heist-Effects (REUSE §1.4, announce/adminWarn 1:1).
--
--  Remote "Effect"(name, strength, data) -> Effects.Play:
--    "Announce"  {Text, UserId, Name}  Besitzer-Ansage oben in der Mitte: rundes Kopfbild, Name in Accent-Blau +
--                selbst gezeichneter blauer Haken, ":" und weißer Text – OHNE Kasten, gleitet weich ein, ~8 s.
--                Ohne UserId/Name (lokalisierte System-Ansage von CommunityService.Announce) = Toast "Announce"
--                (kein falscher "Admin"-Haken).
--    "AdminWarn" {Text}                Hinweis in der Bildschirmmitte: Titel Michroma in Down + Unterstrich
--    "Confetti"  (strength = Menge)    Konfetti-Kanonen links/rechts
--    "LevelUp"   {Level, Rewards}      "LEVEL 12!" + Blitz + Konfetti + Jingle (Belohnungskarte macht WP8)
--    "CoinFly"   (strength = Coins)    Münzen fliegen zum Coin-Zähler im HUD
--    "Shake"     (strength)            Kamera wackeln (Einstellung "Kamerawackeln" 0–100 %)
--    "CrateFound", "PartyBoost", "Event", "Friend", "Mutator"  lokalisierte Lobby-Hinweise (Toast)
--  Bausteine: Effects.Burst / Ring / Puff (Welt), Effects.Shake, Effects.Flash(color, text?)
--  Effects.SetHidden(on) / Effects.IsHidden() für den Foto-Modus.
--  AKYTEX-Look (docs/STYLE-AKYTEX.md): Builder Sans / Michroma, feine Kontur statt dicker schwarzer,
--  Level-Up = Akzent-Rand-Glühen + Michroma-Titel mit Unterstrich (kein weißer Vollbild-Blitz).
--  Öffentliche API (C7.4): Effects.Play(name, strength, data?), Effects.SetHidden(on)
-- =====================================================================

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent:WaitForChild("UI"))

local Effects = {}

local player = Players.LocalPlayer
local ctx: any = nil
local fxFolder: Folder? = nil
local overlay: ScreenGui? = nil -- eigene Ebene (ohne UIScale -> Pixel = Bildschirm-Pixel)
local hidden = false

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local function T(key: string, ...: any): string
	if ctx and type(ctx.T) == "function" then
		return ctx.T(key, ...)
	end
	return key
end

local function sfx(role: string, pos: Vector3?, opts: any?)
	local module = ctx and ctx.Modules and ctx.Modules.Sfx
	if module and type(module.Play) == "function" then
		pcall(module.Play, role, pos, opts)
	end
end

local function setting(key: string): any
	local module = ctx and ctx.Modules and ctx.Modules.Settings
	if module and type(module.Get) == "function" then
		local ok, settings = pcall(module.Get)
		if ok and type(settings) == "table" then
			return settings[key]
		end
	end
	return nil
end

-- ---------------------------------------------------------------------
-- WELT-BAUSTEINE (MH): Funken, Druckwelle, Puff – Reichweiten-Grenze + Licht-Budget
-- ---------------------------------------------------------------------
local BURST_RANGE = 450
local FLASH_INFO = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SHELL_INFO = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLASH_WINDOW = 0.25
local MAX_FLASHES = 3
local flashWindowStart = 0
local flashCount = 0

local function reducedFx(): boolean
	return setting("ReducedFx") == true
end

local function localPart(props: { [string]: any }): Part
	local base: { [string]: any } = {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	return UI.Create("Part", base)
end

local function makeEmitter(color: Color3, parent: Instance, big: boolean): ParticleEmitter
	return UI.Create("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(color:Lerp(WHITE, 0.45), color),
		LightEmission = 0.4,
		LightInfluence = 0,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, big and 1.4 or 0.8),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.7, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(0.5, big and 1.2 or 0.7),
		Speed = NumberRange.new(big and 16 or 8, big and 34 or 16),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -28, 0),
		Drag = 2,
		RotSpeed = NumberRange.new(-220, 220),
		Rate = 0,
		Parent = parent,
	})
end

local function inRange(position: Vector3): boolean
	local camera = workspace.CurrentCamera
	return not camera or (camera.CFrame.Position - position).Magnitude <= BURST_RANGE
end

local function burst(position: Vector3, color: Color3, amount: number, flash: boolean)
	local folder = fxFolder
	if not folder or hidden or not inRange(position) then
		return
	end
	if reducedFx() then
		flash = false
		amount *= 0.5
	end
	if flash then
		local t = os.clock()
		if t - flashWindowStart > FLASH_WINDOW then
			flashWindowStart = t
			flashCount = 0
		end
		flashCount += 1
		if flashCount > MAX_FLASHES then
			flash = false
			amount *= 0.5
		end
	end
	local holder = localPart({
		Name = "Burst",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
		CFrame = CFrame.new(position),
		Parent = folder,
	})
	local emitter = makeEmitter(color, holder, flash)
	emitter:Emit(math.clamp(math.floor(amount), 1, 120))
	if flash then
		local light: PointLight = UI.Create("PointLight", {
			Color = color,
			Range = 26,
			Brightness = 8,
			Shadows = false,
			Parent = holder,
		})
		TweenService:Create(light, FLASH_INFO, { Brightness = 0, Range = 6 }):Play()
		local shell = localPart({
			Name = "Flash",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1, 1, 1),
			Material = Enum.Material.Neon,
			Color = color,
			Transparency = 0.2,
			CFrame = CFrame.new(position),
			Parent = folder,
		})
		TweenService:Create(shell, SHELL_INFO, { Size = Vector3.new(13, 13, 13), Transparency = 1 }):Play()
		Debris:AddItem(shell, 0.5)
	end
	Debris:AddItem(holder, 2)
end

local function ring(position: Vector3, color: Color3, size: number, time: number)
	local folder = fxFolder
	if not folder or hidden or not inRange(position) then
		return
	end
	local cf = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	local wave = localPart({
		Name = "Shockwave",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, 1, 1),
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = 0.25,
		CFrame = cf,
		Parent = folder,
	})
	local info = TweenInfo.new(time, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	TweenService:Create(wave, info, { Size = Vector3.new(0.05, size, size), Transparency = 1 }):Play()
	Debris:AddItem(wave, time + 0.05)
end

local function puff(position: Vector3, color: Color3, amount: number)
	local folder = fxFolder
	if not folder or hidden or not inRange(position) then
		return
	end
	local holder = localPart({
		Name = "Puff",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
		CFrame = CFrame.new(position),
		Parent = folder,
	})
	local poof: ParticleEmitter = UI.Create("ParticleEmitter", {
		Texture = "rbxasset://textures/explosion.png",
		Color = ColorSequence.new(WHITE, color:Lerp(WHITE, 0.3)),
		LightEmission = 0.3,
		LightInfluence = 0,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(0.35, 1.5),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(0.7, 0.25),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(0.4, 0.7),
		Speed = NumberRange.new(7, 13),
		SpreadAngle = Vector2.new(80, 10),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -8, 0),
		Drag = 5,
		RotSpeed = NumberRange.new(-120, 120),
		Rotation = NumberRange.new(0, 360),
		Rate = 0,
		Parent = holder,
	})
	local count = math.clamp(math.floor(amount * 0.7), 1, 20)
	if reducedFx() then
		count = math.max(1, math.floor(count / 2))
	end
	poof:Emit(count)
	Debris:AddItem(holder, 1)
end

-- ---------------------------------------------------------------------
-- WACKELN: im Kampf über FpsCamera.Shake (Rotation), sonst MH-Kameraversatz (weich, dezent)
-- ---------------------------------------------------------------------
local SHAKE_TIME = 0.4
local SHAKE_SCALE = 0.55
local SHAKE_MAX = 1.2
local SHAKE_FREQ = 18
local shakeStrength = 0
local shakeClock = 0
local shakeLeft = 0
local shakeHumanoid: Humanoid? = nil

local function shake(strength: number)
	if type(strength) ~= "number" or strength ~= strength or strength <= 0 then
		return
	end
	local mult = setting("Shake")
	if type(mult) == "number" then
		strength *= math.clamp(mult, 0, 1)
	end
	if strength <= 0.001 then
		return
	end
	local camera = ctx and ctx.Modules and ctx.Modules.FpsCamera
	local weapon = ctx and ctx.Modules and ctx.Modules.WeaponClient
	local armed = false
	if weapon and type(weapon.IsArmed) == "function" then
		local ok, value = pcall(weapon.IsArmed)
		armed = ok and value == true
	end
	if armed and camera and type(camera.Shake) == "function" then
		pcall(camera.Shake, math.min(strength, 2), SHAKE_TIME)
		return
	end
	strength = math.min(strength * SHAKE_SCALE, SHAKE_MAX)
	local current = if shakeLeft > 0 then shakeStrength * (shakeLeft / SHAKE_TIME) else 0
	if strength >= current then
		shakeStrength = strength
		shakeLeft = SHAKE_TIME
	end
end

local function stepShake(dt: number)
	if shakeLeft <= 0 then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= shakeHumanoid and shakeHumanoid and shakeHumanoid.Parent then
		shakeHumanoid.CameraOffset = Vector3.zero
	end
	shakeHumanoid = humanoid
	shakeLeft -= dt
	if not humanoid then
		return
	end
	if shakeLeft <= 0 then
		humanoid.CameraOffset = Vector3.zero
		return
	end
	local fade = shakeLeft / SHAKE_TIME
	local power = shakeStrength * fade * fade
	shakeClock += dt * SHAKE_FREQ
	humanoid.CameraOffset = Vector3.new(math.noise(shakeClock, 0.5), math.noise(0.5, shakeClock), 0) * power
end

-- ---------------------------------------------------------------------
-- MÜNZFLUG zum Coin-Zähler (fester Vorrat von 16)
-- ---------------------------------------------------------------------
type Coin = { Label: TextLabel, Busy: boolean }
local COIN_COUNT = 16
local COIN_OUT_INFO = TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local coinPool: { Coin } = {}

local function buildCoins()
	local gui = overlay
	if not gui then
		return
	end
	for _ = 1, COIN_COUNT do
		local coinLabel: TextLabel = UI.Create("TextLabel", {
			Name = "Coin",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(34, 34),
			BackgroundTransparency = 1,
			Text = "🪙",
			TextScaled = true,
			Font = UI.Fonts.Main,
			Visible = false,
			ZIndex = 30,
			Parent = gui,
		})
		table.insert(coinPool, { Label = coinLabel, Busy = false })
	end
end

local function flyCoins(amount: number)
	local gui = overlay
	local camera = workspace.CurrentCamera
	local hud = ctx and ctx.Modules and ctx.Modules.Hud
	if not gui or hidden or not camera or #coinPool == 0 or not hud or type(hud.CoinAnchor) ~= "function" then
		return
	end
	local ok, target = pcall(hud.CoinAnchor)
	if not ok or typeof(target) ~= "Vector2" then
		return
	end
	local goal = UDim2.fromOffset(target.X, target.Y)
	local size = gui.AbsoluteSize
	local start = Vector2.new(size.X / 2, size.Y * 0.55)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local point, onScreen = camera:WorldToScreenPoint(root.Position)
		if onScreen then
			start = Vector2.new(point.X, point.Y)
		end
	end
	local count = math.clamp(math.floor(3 + math.log10(math.max(amount, 1)) * 1.5), 4, 12)
	local launched = 0
	for _, coin in ipairs(coinPool) do
		if launched >= count then
			break
		end
		if not coin.Busy then
			launched += 1
			coin.Busy = true
			local coinLabel = coin.Label
			local angle = math.random() * math.pi * 2
			local spread = 40 + math.random() * 70
			local midX = start.X + math.cos(angle) * spread
			local midY = start.Y + math.sin(angle) * spread * 0.7 - 30
			coinLabel.Position = UDim2.fromOffset(start.X, start.Y)
			coinLabel.Size = UDim2.fromOffset(14, 14)
			coinLabel.Rotation = math.random(-40, 40)
			coinLabel.Visible = true
			local out = TweenService:Create(coinLabel, COIN_OUT_INFO, {
				Position = UDim2.fromOffset(midX, midY),
				Size = UDim2.fromOffset(34, 34),
				Rotation = coinLabel.Rotation + math.random(-120, 120),
			})
			local delay = launched * 0.04
			out.Completed:Once(function()
				local flyInfo = TweenInfo.new(
					0.4 + math.random() * 0.15,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.In,
					0,
					false,
					delay
				)
				local fly = TweenService:Create(coinLabel, flyInfo, {
					Position = goal,
					Size = UDim2.fromOffset(20, 20),
					Rotation = 0,
				})
				fly.Completed:Once(function()
					coinLabel.Visible = false
					coin.Busy = false
					if not hidden and type(hud.PulseCoins) == "function" then
						pcall(hud.PulseCoins, 0.06)
					end
					sfx("UIHover", nil, { Speed = 1.2 + math.random() * 0.4 })
				end)
				fly:Play()
			end)
			out:Play()
		end
	end
end

-- ---------------------------------------------------------------------
-- KONFETTI (MH): Kanonen links und rechts unten, Wurfparabel, Drehen + Flattern
-- ---------------------------------------------------------------------
local MAX_CONFETTI = 140
local CONFETTI_GRAVITY = 1500
local confettiAlive = 0

local function confettiPiece(gui: ScreenGui, x: number, y: number, vx: number, vy: number, color: Color3)
	local screen = gui.AbsoluteSize
	local tUp = vy / CONFETTI_GRAVITY
	local peak = y - vy * vy / (2 * CONFETTI_GRAVITY)
	local fallDistance = screen.Y + 30 - peak
	local tDown = math.sqrt(2 * fallDistance / CONFETTI_GRAVITY) * 1.9
	local life = tUp + tDown
	local width, height = math.random(8, 14), math.random(10, 16)
	local holder: Frame = UI.Create("Frame", {
		Size = UDim2.fromOffset(0, 0),
		Position = UDim2.fromOffset(x, y),
		BackgroundTransparency = 1,
		ZIndex = 25,
		Parent = gui,
	})
	local piece: Frame = UI.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Rotation = math.random(0, 360),
		ZIndex = 25,
		Parent = holder,
	})
	if math.random() < 0.35 then
		UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = piece })
	end
	TweenService:Create(
		holder,
		TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(x + vx * 0.9, y) }
	):Play()
	TweenService:Create(piece, TweenInfo.new(life, Enum.EasingStyle.Linear), {
		Rotation = piece.Rotation + math.random(-720, 720),
	}):Play()
	TweenService:Create(
		piece,
		TweenInfo.new(0.18 + math.random() * 0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Size = UDim2.fromOffset(math.max(2, width * 0.15), height) }
	):Play()
	local up = TweenService:Create(
		piece,
		TweenInfo.new(tUp, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(0, peak - y) }
	)
	up.Completed:Once(function()
		local down = TweenService:Create(
			piece,
			TweenInfo.new(tDown, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.fromOffset(0, screen.Y + 30 - y) }
		)
		down.Completed:Once(function()
			confettiAlive -= 1
			holder:Destroy()
		end)
		down:Play()
	end)
	up:Play()
end

local function confetti(amount: number)
	local gui = overlay
	if not gui or hidden then
		return
	end
	local colors = { UI.Theme.Yellow, UI.Theme.Green, UI.Theme.Blue, UI.Theme.Purple, UI.Theme.Red, UI.Theme.Pink }
	local mult = math.clamp(tonumber(amount) or 1, 0.3, 3)
	if amount <= 0 then
		mult = 1
	end
	local count = math.floor(32 * mult)
	if reducedFx() then
		count = math.floor(count / 2)
	end
	count = math.min(count, MAX_CONFETTI - confettiAlive)
	local screen = gui.AbsoluteSize
	if screen.Y < 10 or count <= 0 then
		return
	end
	for i = 1, count do
		confettiAlive += 1
		local left = i % 2 == 0
		local x = if left then screen.X * 0.04 else screen.X * 0.96
		local y = screen.Y + 10
		local rise = screen.Y * (0.35 + math.random() * 0.5)
		local vy = math.sqrt(2 * CONFETTI_GRAVITY * rise)
		local vx = (screen.X * (0.12 + math.random() * 0.4)) * (if left then 1 else -1)
		confettiPiece(gui, x, y, vx, vy, colors[math.random(1, #colors)])
	end
end

-- ---------------------------------------------------------------------
-- GROSSER BLITZ MIT TEXT (Level-Up, Sieg …) – MH-RebirthFlash
-- ---------------------------------------------------------------------
local FLASH_FADE_INFO = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLASH_POP_INFO = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local FLASH_OUT_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.1)
local flashBusy = false

-- Akzent-Glühen an den Bildrändern + zentrierter Titel (Michroma) mit Unterstrich und feinem Glow
function Effects.Flash(color: Color3, text: string?)
	local gui = overlay
	if not gui or hidden or flashBusy then
		return
	end
	flashBusy = true
	local tint = if typeof(color) == "Color3" then color else UI.Theme.Accent
	local glow: Frame = UI.Create("Frame", {
		Name = "BigFlash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = tint,
		BackgroundTransparency = if reducedFx() then 0.8 else 0.55,
		BorderSizePixel = 0,
		ZIndex = 40,
		Parent = gui,
	}, {
		-- Mitte durchsichtig, Ränder farbig (Vignette statt weißem Vollbild)
		UI.Create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.3, 0.85),
				NumberSequenceKeypoint.new(0.7, 0.85),
				NumberSequenceKeypoint.new(1, 0),
			}),
		}),
	})
	local label: TextLabel? = nil
	if text and text ~= "" then
		local textScale: UIScale = UI.Create("UIScale", { Scale = 0.9 })
		local newLabel = UI.Label({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.4),
			Size = UDim2.fromOffset(640, 80),
			Text = text,
			Font = UI.Fonts.Banner,
			TextColor3 = WHITE,
			MaxText = 64,
			ZIndex = 41,
			Parent = gui,
		})
		textScale.Parent = newLabel
		local glowStroke: UIStroke = UI.Create("UIStroke", {
			Color = tint,
			Thickness = 3,
			Transparency = 0.6,
			LineJoinMode = Enum.LineJoinMode.Round,
			Parent = newLabel,
		})
		local line: Frame = UI.Create("Frame", {
			Name = "Underline",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, 4),
			Size = UDim2.fromOffset(96, 3),
			BackgroundColor3 = tint,
			BorderSizePixel = 0,
			ZIndex = 41,
			Parent = newLabel,
		}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		newLabel.TextTransparency = 1
		TweenService:Create(newLabel, FLASH_POP_INFO, { TextTransparency = 0 }):Play()
		TweenService:Create(textScale, FLASH_POP_INFO, { Scale = 1 }):Play()
		TweenService:Create(glowStroke, FLASH_OUT_INFO, { Transparency = 1 }):Play()
		TweenService:Create(line, FLASH_OUT_INFO, { BackgroundTransparency = 1 }):Play()
		label = newLabel
	end
	TweenService:Create(glow, FLASH_FADE_INFO, { BackgroundTransparency = 1 }):Play()
	task.delay(1.6, function()
		glow:Destroy()
		if label then
			label:Destroy()
		end
		flashBusy = false
	end)
	if label then
		TweenService:Create(label, FLASH_OUT_INFO, { TextTransparency = 1 }):Play()
	end
end

local function levelUp(data: any)
	local level = type(data) == "table" and tonumber(data.Level) or nil
	local text = if level then T("ui.levelUp", math.floor(level)) else T("ui.levelUpShort")
	Effects.Flash(UI.Theme.Accent, text)
	confetti(2)
	shake(0.4)
	sfx("LevelUp")
end

-- ---------------------------------------------------------------------
-- BESITZER-ANSAGE (MH 1:1): Kopfbild, Name in Blau + Haken, ":" und Text – ohne Kasten
-- ---------------------------------------------------------------------
local ANNOUNCE_BLUE = UI.Theme.Accent -- Name + Haken in Accent-Blau (AKYTEX)
local ANNOUNCE_TIME = 8
local ANNOUNCE_MAX_QUEUE = 5
local ANNOUNCE_AVATAR = 64
local ANNOUNCE_NAME_SIZE = 28
local ANNOUNCE_BADGE = 24
local ANNOUNCE_Y = 14
local ANNOUNCE_IN = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local ANNOUNCE_FADE_IN = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local ANNOUNCE_FONT = UI.Fonts.Main
local ANNOUNCE_OUT = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local THUMB_CACHE_MAX = 64

type AnnounceUI = {
	Group: CanvasGroup,
	Scale: UIScale,
	Avatar: ImageLabel,
	Name: TextLabel,
	Badge: Frame,
	Colon: TextLabel,
	Text: TextLabel,
}
local announceUI: AnnounceUI? = nil
local announceQueue: { any } = {}
local announceBusy = false
local thumbCache: { [number]: string } = {}
local thumbCount = 0

-- feine Kontur für Text über der Welt (AKYTEX: 1 px, halb durchsichtig)
local function textStroke(parent: Instance)
	UI.Create("UIStroke", {
		Thickness = 1,
		Color = BLACK,
		Transparency = 0.45,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

local function buildAnnounce(): AnnounceUI?
	local gui = overlay
	if not gui then
		return nil
	end
	local group: CanvasGroup = UI.Create("CanvasGroup", {
		Name = "OwnerAnnounce",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, ANNOUNCE_Y),
		Size = UDim2.new(0.86, 0, 0, 96),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Visible = false,
		ZIndex = 30,
		Parent = gui,
	})
	local scale: UIScale = UI.Create("UIScale", { Scale = 1, Parent = group })
	local avatar: ImageLabel = UI.Create("ImageLabel", {
		Name = "Avatar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		Size = UDim2.fromOffset(ANNOUNCE_AVATAR, ANNOUNCE_AVATAR),
		BackgroundColor3 = UI.Theme.Surface2,
		Image = "",
		ZIndex = 31,
		Parent = group,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	UI.Create("UIStroke", {
		Thickness = 1.5,
		Color = ANNOUNCE_BLUE,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = avatar,
	})
	local nameLabel: TextLabel = UI.Create("TextLabel", {
		Name = "Name",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, ANNOUNCE_AVATAR + 14, 0.5, 0),
		Size = UDim2.fromOffset(100, 44),
		BackgroundTransparency = 1,
		Font = ANNOUNCE_FONT,
		TextSize = ANNOUNCE_NAME_SIZE,
		TextColor3 = ANNOUNCE_BLUE,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 31,
		Parent = group,
	})
	textStroke(nameLabel)
	-- Haken-Badge (selbst gezeichnet): zwei gedrehte blaue Quadrate = Zackenkreis, weißer Haken
	local badge: Frame = UI.Create("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(ANNOUNCE_BADGE, ANNOUNCE_BADGE),
		BackgroundTransparency = 1,
		ZIndex = 31,
		Parent = group,
	})
	for _, rotation in ipairs({ 0, 45 }) do
		UI.Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.78, 0.78),
			Rotation = rotation,
			BackgroundColor3 = ANNOUNCE_BLUE,
			BorderSizePixel = 0,
			ZIndex = 31,
			Parent = badge,
		}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.2, 0) }) })
	end
	UI.Create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = UI.Fonts.Strong,
		Text = "✓",
		TextScaled = true,
		TextColor3 = WHITE,
		ZIndex = 32,
		Parent = badge,
	})
	local colon: TextLabel = UI.Create("TextLabel", {
		Name = "Colon",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(14, 44),
		BackgroundTransparency = 1,
		Font = ANNOUNCE_FONT,
		TextSize = ANNOUNCE_NAME_SIZE,
		Text = ":",
		TextColor3 = UI.Theme.Text2,
		ZIndex = 31,
		Parent = group,
	})
	textStroke(colon)
	local text: TextLabel = UI.Create("TextLabel", {
		Name = "Text",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Font = ANNOUNCE_FONT,
		TextScaled = true,
		TextWrapped = true,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 31,
		Parent = group,
	})
	UI.Create("UITextSizeConstraint", { MaxTextSize = 34, MinTextSize = 14, Parent = text })
	textStroke(text)
	return {
		Group = group,
		Scale = scale,
		Avatar = avatar,
		Name = nameLabel,
		Badge = badge,
		Colon = colon,
		Text = text,
	}
end

local function headshot(userId: number): string
	local cached = thumbCache[userId]
	if cached then
		return cached
	end
	if userId <= 0 then
		return ""
	end
	local ok, image = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)
	if ok and type(image) == "string" then
		if thumbCount >= THUMB_CACHE_MAX then
			table.clear(thumbCache)
			thumbCount = 0
		end
		thumbCache[userId] = image
		thumbCount += 1
		return image
	end
	return ""
end

local function layoutAnnounce(ui: AnnounceUI, name: string)
	local nameWidth = TextService:GetTextSize(name, ANNOUNCE_NAME_SIZE, ANNOUNCE_FONT, Vector2.new(1000, 100)).X + 4
	local x = ANNOUNCE_AVATAR + 14
	ui.Name.Size = UDim2.fromOffset(nameWidth, 44)
	x += nameWidth + 6
	ui.Badge.Position = UDim2.new(0, x, 0.5, 0)
	x += ANNOUNCE_BADGE + 2
	ui.Colon.Position = UDim2.new(0, x, 0.5, 0)
	x += 18
	ui.Text.Position = UDim2.new(0, x, 0.5, 0)
	ui.Text.Size = UDim2.new(1, -x - 4, 1, -4)
end

local function showNextAnnounce()
	local ui = announceUI
	if not ui then
		return
	end
	announceBusy = true
	while #announceQueue > 0 do
		local data = table.remove(announceQueue, 1)
		local name = string.sub(tostring(data.Name or "Admin"), 1, 40)
		ui.Name.Text = name
		ui.Text.Text = tostring(data.Text)
		ui.Avatar.Image = headshot(tonumber(data.UserId) or 0)
		layoutAnnounce(ui, name)
		ui.Group.Visible = not hidden
		ui.Group.GroupTransparency = 1
		ui.Group.Position = UDim2.new(0.5, 0, 0, ANNOUNCE_Y - 8)
		ui.Scale.Scale = 0.96
		TweenService:Create(ui.Group, ANNOUNCE_FADE_IN, { GroupTransparency = 0 }):Play()
		TweenService:Create(ui.Group, ANNOUNCE_IN, { Position = UDim2.new(0.5, 0, 0, ANNOUNCE_Y) }):Play()
		TweenService:Create(ui.Scale, ANNOUNCE_IN, { Scale = 1 }):Play()
		sfx("Countdown", nil, { Speed = 1.5 })
		task.wait(ANNOUNCE_TIME)
		local out = TweenService:Create(ui.Group, ANNOUNCE_OUT, { GroupTransparency = 1 })
		out:Play()
		out.Completed:Wait()
		ui.Group.Visible = false
		task.wait(0.2)
	end
	announceBusy = false
end

local function announce(data: any)
	if type(data) ~= "table" or type(data.Text) ~= "string" or data.Text == "" then
		return
	end
	-- System-Ansage ohne Absender (CommunityService.Announce schickt nur {Text}): schlanke Pill statt
	-- Besitzer-Banner – sonst stünde dort "Admin" mit blauem Haken, obwohl kein Mensch spricht
	local userId = tonumber(data.UserId) or 0
	if userId <= 0 and (type(data.Name) ~= "string" or data.Name == "") then
		UI.Toast(data.Text, "Announce")
		return
	end
	if not announceUI then
		announceUI = buildAnnounce()
	end
	if #announceQueue >= ANNOUNCE_MAX_QUEUE then
		table.remove(announceQueue, 1) -- die älteste wartende Ansage fällt weg
	end
	table.insert(announceQueue, data)
	if not announceBusy then
		task.spawn(showNextAnnounce)
	end
end

-- ---------------------------------------------------------------------
-- ADMIN-WARNUNG (MH 1:1): riesige rote Überschrift + weißer Text, dicke Kontur, ohne Kasten
-- ---------------------------------------------------------------------
local WARN_TIME = 7
local WARN_RED = UI.Theme.Down
local WARN_IN = TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local WARN_OUT = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local warnToken = 0
local warnFrame: Frame? = nil
local warnTitle: TextLabel? = nil
local warnText: TextLabel? = nil
local warnScale: UIScale? = nil

local function buildWarn()
	local gui = overlay
	if not gui or warnFrame then
		return
	end
	local frame: Frame = UI.Create("Frame", {
		Name = "AdminWarn",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.new(0.7, 0, 0, 170),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 40,
		Parent = gui,
	}, {
		UI.Create("UISizeConstraint", { MinSize = Vector2.new(300, 0), MaxSize = Vector2.new(820, 400) }),
	})
	local scale: UIScale = UI.Create("UIScale", { Scale = 1, Parent = frame })
	-- Titel in Michroma (Down) mit Unterstrich, Text weiß mit feiner Kontur – ohne Kasten
	local title = UI.Label({
		Size = UDim2.new(1, 0, 0, 44),
		Text = "",
		Font = UI.Fonts.Banner,
		TextColor3 = WARN_RED,
		MaxText = 34,
		Outline = 1,
		ZIndex = 41,
		Parent = frame,
	})
	UI.Create("Frame", {
		Name = "Underline",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 50),
		Size = UDim2.fromOffset(84, 3),
		BackgroundColor3 = WARN_RED,
		BorderSizePixel = 0,
		ZIndex = 41,
		Parent = frame,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local text = UI.Label({
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.new(1, 0, 1, -64),
		Text = "",
		Font = UI.Fonts.Main,
		TextColor3 = WHITE,
		TextWrapped = true,
		MaxText = 30,
		Outline = 1,
		ZIndex = 41,
		Parent = frame,
	})
	warnFrame, warnTitle, warnText, warnScale = frame, title, text, scale
end

local function adminWarn(data: any)
	if type(data) ~= "table" or type(data.Text) ~= "string" or data.Text == "" then
		return
	end
	buildWarn()
	local frame, title, text, scale = warnFrame, warnTitle, warnText, warnScale
	if not frame or not title or not text or not scale then
		return
	end
	warnToken += 1
	local token = warnToken
	title.Text = T("ui.adminWarn")
	text.Text = data.Text
	frame.Visible = true
	scale.Scale = 0.94
	title.TextTransparency = 0
	text.TextTransparency = 0
	TweenService:Create(scale, WARN_IN, { Scale = 1 }):Play()
	shake(0.5)
	sfx("UIError")
	task.delay(WARN_TIME, function()
		if warnToken ~= token then
			return
		end
		TweenService:Create(title, WARN_OUT, { TextTransparency = 1 }):Play()
		TweenService:Create(text, WARN_OUT, { TextTransparency = 1 }):Play()
		local out = TweenService:Create(scale, WARN_OUT, { Scale = 0.96 })
		out.Completed:Once(function()
			if warnToken == token then
				frame.Visible = false
			end
		end)
		out:Play()
	end)
end

-- ---------------------------------------------------------------------
-- LOBBY-HINWEISE (Kisten-Fund, Party-Boost, Admin-Event, Freund, Mutator)
-- ---------------------------------------------------------------------
local function cosmeticName(id: any): string
	if type(id) ~= "string" then
		return "?"
	end
	local config = ctx and ctx.Config
	local cosmetics = config and config.Cosmetics
	local def = nil
	if cosmetics and type(cosmetics.Get) == "function" then
		local ok, value = pcall(cosmetics.Get, id)
		def = ok and value or nil
	end
	if type(def) == "table" and type(def.Name) == "table" then
		local ok, text = pcall(ctx.Lang.Pick, ctx.Lang_(), def.Name)
		if ok and type(text) == "string" then
			return text
		end
	end
	return id
end

local function minutesLeft(untilT: any): number
	if type(untilT) ~= "number" then
		return 0
	end
	return math.max(0, math.ceil((untilT - workspace:GetServerTimeNow()) / 60))
end

local function lobbyNotice(name: string, data: any)
	if type(data) ~= "table" then
		return
	end
	if name == "CrateFound" then
		-- Shop (WP9) zeigt denselben Fund schon als Toast (Hook "Effect:CrateFound") – nur ohne Shop hier
		local modules = ctx and ctx.Modules
		if modules and modules.Shop then
			return
		end
		local who = string.sub(tostring(data.Name or "?"), 1, 40)
		local rarity = tostring(data.Rarity or "")
		local rarityText = T("ui.rarity." .. rarity)
		if rarityText == "ui.rarity." .. rarity then
			rarityText = rarity
		end
		UI.Toast(T("ui.crateFound", who, rarityText, cosmeticName(data.ItemId)), "Event")
	elseif name == "PartyBoost" then
		UI.Toast(T("ui.partyBoost", string.sub(tostring(data.Name or "?"), 1, 40), minutesLeft(data.Until)), "Event")
		confetti(0.6)
	elseif name == "Event" then
		local parts: { string } = {}
		if data.Coins2 then
			table.insert(parts, T("ui.event.coins"))
		end
		if data.Xp2 then
			table.insert(parts, T("ui.event.xp"))
		end
		UI.Toast(T("ui.event", table.concat(parts, " + "), minutesLeft(data.Until)), "Event")
		confetti(1)
	elseif name == "Friend" then
		UI.Toast(T("ui.friendJoined", string.sub(tostring(data.Name or "?"), 1, 40)), "Info")
	elseif name == "Mutator" then
		local key = tostring(data.Key or "")
		local config = ctx and ctx.Config
		local modes = config and config.Modes
		local mutators = modes and modes.Mutators
		local def = type(mutators) == "table" and mutators[key] or nil
		local label = key
		if type(def) == "table" and type(def.Name) == "table" then
			local ok, text = pcall(ctx.Lang.Pick, ctx.Lang_(), def.Name)
			if ok and type(text) == "string" then
				label = text
			end
		end
		UI.Toast(T("ui.mutatorToday", label), "Event")
	end
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICH
-- ---------------------------------------------------------------------
function Effects.Play(name: string, strength: number, data: any?)
	if type(name) ~= "string" then
		return
	end
	local amount = tonumber(strength) or 0
	if amount ~= amount then
		amount = 0
	end
	if name == "Announce" then
		announce(data)
	elseif name == "AdminWarn" or name == "Warn" then
		adminWarn(data)
	elseif name == "Confetti" then
		confetti(if amount > 0 then amount else 1)
	elseif name == "LevelUp" then
		levelUp(data)
	elseif name == "CoinFly" then
		flyCoins(math.max(1, amount))
	elseif name == "Shake" then
		shake(amount)
	elseif name == "CrateFound" or name == "PartyBoost" or name == "Event" or name == "Friend" or name == "Mutator" then
		lobbyNotice(name, data)
	end
	-- "Balance" übernimmt Main.client über den LiveBalance-StringValue; Unbekanntes wird ignoriert
end

function Effects.Burst(position: Vector3, color: Color3, amount: number, flash: boolean?)
	burst(position, color, amount, flash == true)
end

function Effects.Ring(position: Vector3, color: Color3, size: number, time: number?)
	ring(position, color, size, time or 0.6)
end

function Effects.Puff(position: Vector3, color: Color3, amount: number)
	puff(position, color, amount)
end

function Effects.Shake(strength: number)
	shake(strength)
end

function Effects.Confetti(amount: number?)
	confetti(amount or 1)
end

function Effects.IsHidden(): boolean
	return hidden
end

-- Foto-Modus: Overlay (Münzen, Konfetti, Ansagen) aus
function Effects.SetHidden(on: boolean)
	hidden = on == true
	if overlay then
		overlay.Enabled = not hidden
	end
end

function Effects.Frame(dt: number)
	stepShake(dt)
end

function Effects.Init(context: any)
	ctx = context
	local folder = Instance.new("Folder")
	folder.Name = "ClutchClashClientFX"
	folder.Parent = workspace
	fxFolder = folder
	overlay = UI.Create("ScreenGui", {
		Name = "ClutchClashFX",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	buildCoins()
	player.CharacterAdded:Connect(function()
		shakeLeft = 0
		shakeHumanoid = nil
	end)
end

function Effects.Start() end

return Effects
