-- =====================================================================
--  AKYTEX TYCOON – Effekt-Registry + Kern-Effekte (Client/Modules/Effects)
--  Besitzer: WP2 (Client-Plattform & UI-Kit). Vertrag: DESIGN.md §C7.4 (frozen Registry), §C7.5. Basis: CC-Effects
--  (announce/adminWarn/Konfetti/Münzflug 1:1, REUSE §1.4) + Register/Play.
--
--  Remote "Effect"(name, strength, data) -> Main.client -> Effects.Play -> danach Hook "Effect:<Name>".
--  Ein Effekt = ein Besitzer (CC-Fix „eine Meldung, ein Weg“): Kern-Effekte gehören diesem Modul, alle anderen
--  registriert ihr Besitzer-Modul in seinem Init mit Effects.Register(name, fn(strength, data)).
--  Kern-Effekte (WP2):
--    "Announce"  {Text, UserId, Name}  Besitzer-Ansage oben in der Mitte: rundes Kopfbild, Name in Accent + selbst
--                gezeichneter Haken, ":" und Text – ohne Kasten, ~8 s. Ohne UserId/Name (System-Ansage von
--                CommunityService.Announce) = Toast "Announce" (kein falscher Haken, REUSE §7 #6).
--    "AdminWarn" {Text}                Hinweis in der Bildschirmmitte: Titel in Down + Unterstrich
--    "Confetti"  (strength = Menge)    Konfetti-Kanonen links/rechts (nur Meilensteine – §0.3 Punkt 6)
--    "CoinFly"   (strength = CR)       grüne CR-Chips fliegen zum CR-Zähler im HUD (Tresor einsammeln)
--    "Flash"     {Color?, Text?, Key?, Args?}  Akzent-Glühen an den Rändern + zentrierter Titel (BuilderExtended)
--    "Shake"     (strength)            Kamera wackeln (Einstellung "Kamerawackeln" 0–100 %, ReducedFx dämpft)
--    "Toast"     {Text? | Key?, Args?, Kind?}  lokalisierte Meldung als Toast
--  Frozen Namen anderer Besitzer (§C7.4): Bell, ReadWell, DayRecap (WP5) · BuildDone, StageUp, TransferTube, Collect,
--  Crane (WP8) · Reveal (WP7) · IpoCeremony, LicenceUp, TitleUp, QuestDone, Achievement (WP9) · MoneyRain, BullParade,
--  Bear, GoldenBull, SkyShow, Fireworks, BossAppear, AbuseBanner, BellMoment (WP11).
--
--  Öffentliche API (§C7.5):
--    Effects.Register(name, fn)   Effects.Play(name, strength, data?)   Effects.SetHidden(on)
--  Zusätzlich: Effects.IsHidden(), Effects.Overlay(): ScreenGui? (unskalierte Effekt-Ebene für andere Besitzer),
--    Effects.Flash(color, text?), Effects.Burst(pos, color, amount, flash?), Effects.Ring(pos, color, size, time?),
--    Effects.Puff(pos, color, amount), Effects.Shake(strength), Effects.Confetti(amount?), Effects.Frame(dt),
--    Effects.Init(ctx), Effects.Start()
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

-- Kern-Effekte (gehören diesem Modul) und eingefrorene Namen der anderen Besitzer (§C7.4)
local CORE: { [string]: boolean } = {
	Announce = true,
	AdminWarn = true,
	Confetti = true,
	CoinFly = true,
	Flash = true,
	Shake = true,
	Toast = true,
}
local FROZEN: { [string]: string } = {
	Bell = "WP5",
	ReadWell = "WP5",
	DayRecap = "WP5",
	BuildDone = "WP8",
	StageUp = "WP8",
	TransferTube = "WP8",
	Collect = "WP8",
	Crane = "WP8",
	Reveal = "WP7",
	IpoCeremony = "WP9",
	LicenceUp = "WP9",
	TitleUp = "WP9",
	QuestDone = "WP9",
	Achievement = "WP9",
	MoneyRain = "WP11",
	BullParade = "WP11",
	Bear = "WP11",
	GoldenBull = "WP11",
	SkyShow = "WP11",
	Fireworks = "WP11",
	BossAppear = "WP11",
	AbuseBanner = "WP11",
	BellMoment = "WP11",
}

local registered: { [string]: (number, any) -> () } = {}
local warnedName: { [string]: boolean } = {}

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

local function reducedFx(): boolean
	return setting("ReducedFx") == true
end

-- Partikel-Faktor der Grafikstufe (Low 0.3 … Ultra 1)
local function particleFactor(): number
	local quality = ctx and ctx.Modules and ctx.Modules.Quality
	if quality and type(quality.Budget) == "function" then
		local ok, value = pcall(quality.Budget, "Particles")
		if ok and type(value) == "number" and value == value then
			return math.clamp(value, 0, 1)
		end
	end
	return 1
end

-- Farbe aus Daten: Color3 oder Theme-Token ("Accent", "Up", "Down", "Warn", "Gold" …)
local function colorFrom(value: any, fallback: Color3): Color3
	if typeof(value) == "Color3" then
		return value
	end
	if type(value) == "string" then
		local token = (UI.Theme :: any)[value]
		if typeof(token) == "Color3" then
			return token
		end
	end
	return fallback
end

-- Text aus Daten: fertiger Text (Server hat lokalisiert) oder Lang-Schlüssel + Argumente
local function textFrom(data: any): string?
	if type(data) ~= "table" then
		return nil
	end
	if type(data.Text) == "string" and data.Text ~= "" then
		return string.sub(data.Text, 1, 500)
	end
	if type(data.Key) == "string" and data.Key ~= "" then
		local args = if type(data.Args) == "table" then data.Args else {}
		local ok, text = pcall(T, data.Key, table.unpack(args, 1, math.min(#args, 16)))
		if ok and type(text) == "string" then
			return text
		end
	end
	return nil
end

-- ---------------------------------------------------------------------
-- WELT-BAUSTEINE: Funken, Druckwelle, Puff – Reichweiten-Grenze + Licht-Budget
-- ---------------------------------------------------------------------
local BURST_RANGE = 450
local FLASH_INFO = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SHELL_INFO = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLASH_WINDOW = 0.25
local MAX_FLASHES = 3
local flashWindowStart = 0
local flashCount = 0

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
	if not folder or hidden or typeof(position) ~= "Vector3" or not inRange(position) then
		return
	end
	amount *= particleFactor()
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
	if not folder or hidden or typeof(position) ~= "Vector3" or not inRange(position) then
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
	if not folder or hidden or typeof(position) ~= "Vector3" or not inRange(position) then
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
		Texture = "rbxasset://textures/particles/smoke_main.dds",
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
	local count = math.clamp(math.floor(amount * 0.7 * particleFactor()), 1, 20)
	if reducedFx() then
		count = math.max(1, math.floor(count / 2))
	end
	poof:Emit(count)
	Debris:AddItem(holder, 1)
end

-- ---------------------------------------------------------------------
-- WACKELN: weicher Kameraversatz über Humanoid.CameraOffset (dezent, abklingend)
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
	if reducedFx() then
		strength *= 0.3
	end
	if strength <= 0.001 then
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
-- CR-FLUG zum CR-Zähler (fester Vorrat aus Sechskant-Chips)
-- ---------------------------------------------------------------------
type Coin = { Holder: Frame, Busy: boolean }
local COIN_OUT_INFO = TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local coinPool: { Coin } = {}

local function buildCoins()
	local gui = overlay
	if not gui then
		return
	end
	local count = 16
	local config = ctx and ctx.Config
	local pools = config and config.Client and config.Client.Pools
	if pools and type(pools.CoinFly) == "number" then
		count = math.clamp(math.floor(pools.CoinFly), 4, 32)
	end
	for _ = 1, count do
		local holder: Frame = UI.Create("Frame", {
			Name = "Coin",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(28, 28),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 30,
			Parent = gui,
		})
		local icon = UI.CurrencyIcon(holder, "CR", 28)
		icon.Size = UDim2.fromScale(1, 1)
		table.insert(coinPool, { Holder = holder, Busy = false })
	end
end

local function hudCall(fnName: string, ...: any): (boolean, any)
	local hud = ctx and ctx.Modules and ctx.Modules.Hud
	local fn = hud and hud[fnName]
	if type(fn) ~= "function" then
		return false, nil
	end
	return pcall(fn, ...)
end

local function flyCoins(amount: number)
	local gui = overlay
	local camera = workspace.CurrentCamera
	if not gui or hidden or not camera or #coinPool == 0 then
		return
	end
	local ok, target = hudCall("CreditsAnchor")
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
	local count = math.clamp(math.floor(3 + math.log10(math.max(amount, 1)) * 1.5), 4, #coinPool)
	if reducedFx() then
		count = math.max(3, math.floor(count / 2))
	end
	sfx("CashRegister")
	local launched = 0
	for _, coin in ipairs(coinPool) do
		if launched >= count then
			break
		end
		if not coin.Busy then
			launched += 1
			coin.Busy = true
			local holder = coin.Holder
			local angle = math.random() * math.pi * 2
			local spread = 40 + math.random() * 70
			local midX = start.X + math.cos(angle) * spread
			local midY = start.Y + math.sin(angle) * spread * 0.7 - 30
			holder.Position = UDim2.fromOffset(start.X, start.Y)
			holder.Size = UDim2.fromOffset(12, 12)
			holder.Rotation = math.random(-40, 40)
			holder.Visible = true
			local out = TweenService:Create(holder, COIN_OUT_INFO, {
				Position = UDim2.fromOffset(midX, midY),
				Size = UDim2.fromOffset(28, 28),
				Rotation = holder.Rotation + math.random(-120, 120),
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
				local fly = TweenService:Create(holder, flyInfo, {
					Position = goal,
					Size = UDim2.fromOffset(16, 16),
					Rotation = 0,
				})
				fly.Completed:Once(function()
					holder.Visible = false
					coin.Busy = false
					if not hidden then
						hudCall("PulseCredits", 0.06)
					end
				end)
				fly:Play()
			end)
			out:Play()
		end
	end
end

-- ---------------------------------------------------------------------
-- KONFETTI: Kanonen links und rechts unten, Wurfparabel, Drehen + Flattern (nur Meilensteine)
-- ---------------------------------------------------------------------
local CONFETTI_GRAVITY = 1500
local maxConfetti = 140
local confettiAlive = 0

local function confettiPiece(gui: ScreenGui, x: number, y: number, vx: number, vy: number, color: Color3)
	local screen = gui.AbsoluteSize
	local tUp = vy / CONFETTI_GRAVITY
	local peak = y - vy * vy / (2 * CONFETTI_GRAVITY)
	local fallDistance = screen.Y + 30 - peak
	local tDown = math.sqrt(2 * math.max(1, fallDistance) / CONFETTI_GRAVITY) * 1.9
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
	local theme = UI.Theme
	local colors = { theme.Accent, theme.Up, theme.Gold, theme.Cosmic2, theme.Cosmic3, theme.Cyan }
	local mult = math.clamp(tonumber(amount) or 1, 0.3, 3)
	local count = math.floor(32 * mult * math.max(0.4, particleFactor()))
	if reducedFx() then
		count = math.floor(count / 2)
	end
	count = math.min(count, maxConfetti - confettiAlive)
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
-- GROSSER BLITZ MIT TEXT (Meilensteine): Akzent-Glühen an den Rändern + Titel in BuilderExtended
-- ---------------------------------------------------------------------
local FLASH_FADE_INFO = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLASH_POP_INFO = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local FLASH_OUT_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.1)
local flashBusy = false

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
			Size = UDim2.new(0.8, 0, 0, 80),
			Text = text,
			Face = "Display",
			TextColor3 = WHITE,
			MaxText = 56,
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
		TweenService:Create(newLabel, FLASH_OUT_INFO, { TextTransparency = 1 }):Play()
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
end

-- ---------------------------------------------------------------------
-- BESITZER-ANSAGE (CC 1:1): Kopfbild, Name in Accent + Haken, ":" und Text – ohne Kasten
-- ---------------------------------------------------------------------
local ANNOUNCE_BLUE = UI.Theme.Accent
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
	local guard = 0
	while #announceQueue > 0 and guard < 64 do
		guard += 1
		local data = table.remove(announceQueue, 1)
		local name = string.sub(tostring(data.Name or "Admin"), 1, 40)
		ui.Name.Text = name
		ui.Text.Text = string.sub(tostring(data.Text), 1, 500)
		ui.Avatar.Image = headshot(tonumber(data.UserId) or 0)
		layoutAnnounce(ui, name)
		ui.Group.Visible = not hidden
		ui.Group.GroupTransparency = 1
		ui.Group.Position = UDim2.new(0.5, 0, 0, ANNOUNCE_Y - 8)
		ui.Scale.Scale = 0.96
		TweenService:Create(ui.Group, ANNOUNCE_FADE_IN, { GroupTransparency = 0 }):Play()
		TweenService:Create(ui.Group, ANNOUNCE_IN, { Position = UDim2.new(0.5, 0, 0, ANNOUNCE_Y) }):Play()
		TweenService:Create(ui.Scale, ANNOUNCE_IN, { Scale = 1 }):Play()
		sfx("Notify")
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
	-- System-Ansage ohne Absender: schlanke Pill statt Besitzer-Banner (sonst stünde dort ein falscher Haken)
	local userId = tonumber(data.UserId) or 0
	if userId <= 0 and (type(data.Name) ~= "string" or data.Name == "") then
		UI.Toast(string.sub(data.Text, 1, 500), "Announce")
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
-- ADMIN-WARNUNG (CC 1:1): große Überschrift in Down + weißer Text, feine Kontur, ohne Kasten
-- ---------------------------------------------------------------------
local WARN_TIME = 7
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
	local title = UI.Label({
		Size = UDim2.new(1, 0, 0, 44),
		Text = "",
		Face = "Display",
		TextColor3 = UI.Theme.Down,
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
		BackgroundColor3 = UI.Theme.Down,
		BorderSizePixel = 0,
		ZIndex = 41,
		Parent = frame,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local text = UI.Label({
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.new(1, 0, 1, -64),
		Text = "",
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
	local message = textFrom(data)
	if not message then
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
	text.Text = message
	frame.Visible = not hidden
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
-- ÖFFENTLICH: Registry + Abspielen
-- ---------------------------------------------------------------------
function Effects.Register(name: string, fn: (strength: number, data: any) -> ())
	if type(name) ~= "string" or name == "" or type(fn) ~= "function" then
		warn("[Effects] Register: Name (string) und Funktion erwartet")
		return
	end
	if CORE[name] then
		warn("[Effects] " .. name .. " ist ein Kern-Effekt von WP2 und kann nicht neu registriert werden")
		return
	end
	if registered[name] then
		warn("[Effects] " .. name .. " ist schon registriert – ein Effekt hat genau einen Besitzer (§C7.4)")
		return
	end
	if not FROZEN[name] and not warnedName[name] then
		warnedName[name] = true
		warn("[Effects] " .. name .. " steht nicht in der eingefrorenen Liste §C7.4 (Vertrags-Prüfer meldet das)")
	end
	registered[name] = fn
end

function Effects.Play(name: string, strength: number, data: any?)
	if type(name) ~= "string" then
		return
	end
	local amount = tonumber(strength) or 0
	if amount ~= amount or amount == math.huge or amount == -math.huge then
		amount = 0
	end
	if name == "Announce" then
		announce(data)
	elseif name == "AdminWarn" then
		adminWarn(data)
	elseif name == "Confetti" then
		confetti(if amount > 0 then amount else 1)
	elseif name == "CoinFly" then
		flyCoins(math.max(1, amount))
	elseif name == "Flash" then
		local tint = colorFrom(type(data) == "table" and data.Color or nil, UI.Theme.Accent)
		Effects.Flash(tint, textFrom(data))
	elseif name == "Shake" then
		shake(amount)
	elseif name == "Toast" then
		local message = textFrom(data)
		if message then
			local kind = if type(data) == "table" and type(data.Kind) == "string" then data.Kind else "Info"
			UI.Toast(message, kind)
		end
	else
		local fn = registered[name]
		if fn then
			local ok, err = pcall(fn, amount, data)
			if not ok then
				warn(("[Effects] %s: %s"):format(name, tostring(err)))
			end
		elseif not warnedName[name] then
			-- Besitzer-Modul (noch) nicht geladen: einmal melden, dann still ignorieren
			warnedName[name] = true
			warn("[Effects] Kein Besitzer für Effekt " .. name .. " geladen – wird ignoriert")
		end
	end
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

-- Unskalierte Effekt-Ebene (Pixel = Bildschirm-Pixel) für Effekte anderer Besitzer
function Effects.Overlay(): ScreenGui?
	return overlay
end

-- Foto-Modus: Overlay (CR-Flug, Konfetti, Ansagen) aus
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
	local config = ctx and ctx.Config
	local pools = config and config.Client and config.Client.Pools
	if pools and type(pools.Confetti) == "number" then
		maxConfetti = math.clamp(math.floor(pools.Confetti), 20, 300)
	end
	local folder = Instance.new("Folder")
	folder.Name = "AkytexTycoonClientFX"
	folder.Parent = workspace
	fxFolder = folder
	overlay = UI.Create("ScreenGui", {
		Name = "AkytexTycoonFX",
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
