-- =====================================================================
--  AKYTEX TYCOON – Event-Effekte (Client/Modules/EffectsEvent)
--  Besitzer: WP11 (Admin, Events, Anti-Cheat). Vertrag: DESIGN.md §C7.4 (frozen Registry: MoneyRain, BullParade, Bear,
--  GoldenBull, SkyShow, Fireworks, BossAppear, AbuseBanner, BellMoment – ein Effekt = ein Besitzer), §A7 #6/#7
--  (Crash-Alarm: Bär, Rally: goldener Bulle), §B10 (Sky-Show, Feuerwerk, Bullen-Parade, Geldregen, Glocken-Moment),
--  §B15.3 (Admin-Abuse-Banner, Boss-Auftritt mit getweenter Winke-Pose), §0 Regel 2 (keine Animationen: Tweens/CFrames).
--
--  Effekte (Daten {Seconds, Plot?, UserId?, Text?, …} vom Server über PlayerStateService.Effect/EffectAll):
--    "AbuseBanner" {Kind, Seconds, Mult?, Until?, Sector?}  Glas-Banner oben (Golden Hour, XP-Rausch, Bau-Boom,
--                                                            Samstags-Show/Auto-Show, Alle in den Börsensaal …)
--    "MoneyRain"   {Seconds}            Banner + Neon-Münzen-Schauer um die Kamera (die echten Münzen sind Pickups)
--    "BullParade"  {Seconds, UserId, Name, Until}   Dank-Banner „Danke, <Name>!“ (ohne Robux-Betrag) + Fanfare
--    "Bear"        {Phase = "Arrive" | "Success" | "Leave", Goal?}   Crash-Alarm-Banner / Erfolg
--    "GoldenBull"  {Phase = "Run" | "Touch", Seconds?}               Rally-Banner / Bullen-Bonus-Blitz
--    "SkyShow"     {Seconds, Admin?, Finale?}   Fassaden-Lichtshow (Beams über allen Plots) + Feuerwerks-Beams
--    "Fireworks"   {Seconds, Plot?, UserId?}    20-s-Feuerwerk über dem Tower des Käufers (sonst über der Plaza)
--    "BossAppear"  {Seconds, UserId, Name}      Banner + Winke-Pose der Besitzer-Avatare auf dem Börsensaal-Dach
--    "BellMoment"  {Seconds, Count?, Mult?, Show?}   goldene Glocken-Welle an der Glocken-Zone + Blitz
--  Ruhig nach §0.3: kein Blinken, keine Münz-Kaskade pro Trade; Partikel nach Quality.Budget("Particles") und ReducedFx.
--  Läuft im EINEN PreRender-Loop: EventsClient.Frame ruft EffectsEvent.Step(dt) auf.
--
--  Öffentliche API:
--    EffectsEvent.Step(dt)          EffectsEvent.Init(ctx) · EffectsEvent.Start()
-- =====================================================================

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent:WaitForChild("UI"))

local EffectsEvent = {}

local player = Players.LocalPlayer
local ctx: any = nil
local Theme = UI.Theme

local GOLD = Color3.fromRGB(250, 204, 21)
local COSMIC1 = Color3.fromRGB(59, 91, 219)
local COSMIC2 = Color3.fromRGB(124, 92, 255)
local COSMIC3 = Color3.fromRGB(179, 107, 255)
local WHITE = Color3.new(1, 1, 1)

local TEX_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_SQUARE = "rbxasset://textures/particles/SquareParticle.png"
local TEX_RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds"
local TEX_GLOW = "rbxasset://textures/particles/explosion01_implosion_main.dds"
local TEX_BEAM = "rbxasset://textures/gradient.png"

local BANNER_SECONDS = 6
local BANNER_QUEUE = 4
local SHOW_BEAMS_MAX = 10
local FIREWORK_GAP = 0.7
local MAX_SHOWS = 4
local BOSS_WAVE_SPEED = 3.2

type Banner = { Title: string, Sub: string, Color: Color3, Until: number?, Seconds: number }
type Show = {
	Kind: string, -- "Sky" | "Fireworks"
	Until: number,
	Next: number,
	Center: Vector3,
	Spread: number,
	Height: number,
	Parts: { Instance },
	Beams: { { Beam: Beam, Phase: number } },
}

-- ---------------------------------------------------------------------
-- ZUSTAND
-- ---------------------------------------------------------------------
local overlay: ScreenGui? = nil
local fxFolder: Folder? = nil
local bannerFrame: Frame? = nil
local bannerTitle: TextLabel? = nil
local bannerSub: TextLabel? = nil
local bannerBar: Frame? = nil
local bannerScale: UIScale? = nil
local bannerQueue: { Banner } = {}
local bannerCurrent: Banner? = nil
local bannerShownAt = 0
local shows: { Show } = {}
local rainPart: Part? = nil
local rainEmitter: ParticleEmitter? = nil
local rainUntil = 0
local rainSoundAt = 0
local boss: { Motors: { { Motor: Motor6D, Base: CFrame } }, Until: number, Phase: number }? = nil

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function T(key: string, ...: any): string
	if ctx and type(ctx.T) == "function" then
		return ctx.T(key, ...)
	end
	return key
end

local function module(name: string): any
	local modules = ctx and ctx.Modules
	return if type(modules) == "table" then modules[name] else nil
end

local function tryModule(name: string, fnName: string, ...: any): (boolean, any)
	local m = module(name)
	local fn = if type(m) == "table" then m[fnName] else nil
	if type(fn) ~= "function" then
		return false, nil
	end
	return pcall(fn, ...)
end

local function num(value: any, default: number): number
	return if type(value) == "number"
			and value == value
			and value ~= math.huge
			and value ~= -math.huge
		then value
		else default
end

local function now(): number
	local clock = ctx and ctx.Clock
	if clock and type(clock.Now) == "function" then
		local ok, value = pcall(clock.Now)
		if ok and type(value) == "number" then
			return value
		end
	end
	return workspace:GetServerTimeNow()
end

local function lang(): string
	if ctx and type(ctx.Lang_) == "function" then
		return ctx.Lang_()
	end
	return "en"
end

local function reducedFx(): boolean
	local ok, settings = tryModule("Settings", "Get")
	return ok and type(settings) == "table" and settings.ReducedFx == true
end

local function particleFactor(): number
	local ok, value = tryModule("Quality", "Budget", "Particles")
	local factor = if ok and type(value) == "number" then value else 1
	if reducedFx() then
		factor *= 0.4
	end
	return math.clamp(factor, 0.1, 1)
end

local function sfx(role: string, pos: Vector3?, opts: any?)
	tryModule("Sfx", "Play", role, pos, opts)
end

local function flash(color: Color3, text: string?)
	local effects = module("Effects")
	if effects and type(effects.Flash) == "function" then
		pcall(effects.Flash, color, text)
	end
end

local function plazaCenter(): Vector3
	local city = ctx and ctx.Config and ctx.Config.City
	local zones = city and city.Zones
	local plaza = zones and zones.Plaza
	if plaza and typeof(plaza.Center) == "Vector3" then
		return plaza.Center
	end
	return Vector3.zero
end

local function plotCFrame(plot: number?): CFrame?
	if type(plot) ~= "number" then
		return nil
	end
	local city = ctx and ctx.Config and ctx.Config.City
	if city and type(city.PlotCFrame) == "function" then
		local ok, cf = pcall(city.PlotCFrame, plot)
		if ok and typeof(cf) == "CFrame" then
			return cf
		end
	end
	return nil
end

local function plotSites(): { CFrame }
	local out: { CFrame } = {}
	local plots = math.floor(num(ctx and ctx.Config and ctx.Config.Server and ctx.Config.Server.Plots, 10))
	for k = 1, plots do
		local cf = plotCFrame(k)
		if cf then
			table.insert(out, cf)
		end
	end
	return out
end

local function localPart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	for key, value in pairs(props) do
		(p :: any)[key] = value
	end
	p.Parent = fxFolder
	return p
end

local function emitter(
	parent: Instance,
	texture: string,
	color: ColorSequence,
	props: { [string]: any }
): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Color = color
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Enabled = false
	e.Rate = 0
	for key, value in pairs(props) do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

-- ---------------------------------------------------------------------
-- BANNER (Glas-Karte oben Mitte, eine nach der anderen)
-- ---------------------------------------------------------------------
local function buildBanner()
	local parent = overlay
	if not parent then
		return
	end
	local frame = UI.Create("Frame", {
		Name = "AT_EventBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 132),
		Size = UDim2.fromOffset(520, 78),
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 20,
		Parent = parent,
	}, { UI.Corner(16), UI.Stroke(nil, 1) })
	local scale = UI.Create("UIScale", { Scale = 1, Parent = frame })
	local bar = UI.Create("Frame", {
		Name = "Bar",
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.new(0, 4, 1, -28),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		ZIndex = 21,
		Parent = frame,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local title = UI.Create("TextLabel", {
		Name = "Title",
		Position = UDim2.fromOffset(30, 10),
		Size = UDim2.new(1, -44, 0, 30),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.Display,
		TextSize = 22,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
		ZIndex = 21,
		Parent = frame,
	})
	local sub = UI.Create("TextLabel", {
		Name = "Sub",
		Position = UDim2.fromOffset(30, 42),
		Size = UDim2.new(1, -44, 0, 24),
		BackgroundTransparency = 1,
		FontFace = UI.Faces.Body,
		TextSize = 15,
		TextColor3 = Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
		ZIndex = 21,
		Parent = frame,
	})
	bannerFrame, bannerTitle, bannerSub, bannerBar, bannerScale = frame, title, sub, bar, scale
end

local function countdown(untilT: number?): string
	if type(untilT) ~= "number" then
		return ""
	end
	local left = math.max(0, untilT - now())
	local format = ctx and ctx.Format
	if format and type(format.Duration) == "function" then
		local ok, text = pcall(format.Duration, left, lang())
		if ok and type(text) == "string" then
			return text
		end
	end
	return ("%d:%02d"):format(math.floor(left / 60), math.floor(left % 60))
end

local function showBanner(b: Banner)
	local frame, title, sub, bar, scale = bannerFrame, bannerTitle, bannerSub, bannerBar, bannerScale
	if not frame or not title or not sub or not bar or not scale then
		return
	end
	bannerCurrent = b
	bannerShownAt = os.clock()
	title.Text = b.Title
	sub.Text = if b.Until then ("%s · %s"):format(b.Sub, countdown(b.Until)) else b.Sub
	bar.BackgroundColor3 = b.Color
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = b.Color
		stroke.Transparency = 0.5
	end
	frame.Visible = true
	frame.Position = UDim2.new(0.5, 0, 0, 108)
	scale.Scale = 0.96
	TweenService:Create(frame, TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 132),
	}):Play()
	TweenService:Create(scale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
end

local function hideBanner()
	local frame = bannerFrame
	bannerCurrent = nil
	if not frame then
		return
	end
	local tween = TweenService:Create(frame, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(0.5, 0, 0, 112),
	})
	tween.Completed:Once(function()
		if bannerCurrent == nil then
			frame.Visible = false
		end
	end)
	tween:Play()
end

local function queueBanner(title: string, sub: string, color: Color3, untilT: number?, seconds: number?)
	local b: Banner = {
		Title = title,
		Sub = sub,
		Color = color,
		Until = untilT,
		Seconds = math.clamp(num(seconds, BANNER_SECONDS), 3, 10),
	}
	if bannerCurrent == nil then
		showBanner(b)
		return
	end
	table.insert(bannerQueue, b)
	while #bannerQueue > BANNER_QUEUE do
		table.remove(bannerQueue, 1)
	end
end

local function stepBanner()
	local current = bannerCurrent
	if not current then
		return
	end
	local sub = bannerSub
	if sub and current.Until then
		sub.Text = ("%s · %s"):format(current.Sub, countdown(current.Until))
	end
	if os.clock() - bannerShownAt >= current.Seconds then
		local nextBanner = table.remove(bannerQueue, 1)
		if nextBanner then
			showBanner(nextBanner)
		else
			hideBanner()
		end
	end
end

local function sectorName(key: any): string
	local companies = ctx and ctx.Config and ctx.Config.Companies
	local sectors = companies and companies.Sectors
	if type(sectors) == "table" then
		for _, entry in ipairs(sectors) do
			if type(entry) == "table" and entry.Key == key then
				local name = entry.Name
				if type(name) == "table" then
					return tostring(name[lang()] or name.de or key)
				end
				return tostring(name or key)
			end
		end
	end
	return tostring(key or "?")
end

-- ---------------------------------------------------------------------
-- SHOWS (Sky-Show-Beams, Feuerwerk)
-- ---------------------------------------------------------------------
local function clearShow(show: Show)
	for _, inst in ipairs(show.Parts) do
		inst:Destroy()
	end
	table.clear(show.Parts)
	table.clear(show.Beams)
end

local function addShow(show: Show)
	table.insert(shows, show)
	while #shows > MAX_SHOWS do
		local old = table.remove(shows, 1)
		if old then
			clearShow(old)
		end
	end
end

local function skyBeams(show: Show)
	local sites = plotSites()
	local factor = particleFactor()
	local count = math.clamp(math.floor(#sites * factor + 0.5), 2, SHOW_BEAMS_MAX)
	for i = 1, math.min(count, #sites) do
		local site = sites[i]
		local base = localPart({ CFrame = CFrame.new(site.Position + Vector3.new(0, 2, 0)) })
		local top = localPart({ CFrame = CFrame.new(site.Position + Vector3.new(0, 260, 0)) })
		local a0 = Instance.new("Attachment")
		a0.Parent = base
		local a1 = Instance.new("Attachment")
		a1.Parent = top
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Texture = TEX_BEAM
		beam.TextureMode = Enum.TextureMode.Stretch
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.FaceCamera = true
		beam.Width0 = 6
		beam.Width1 = 2
		beam.Color = ColorSequence.new(COSMIC1, COSMIC3)
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		beam.Parent = base
		table.insert(show.Parts, base)
		table.insert(show.Parts, top)
		table.insert(show.Beams, { Beam = beam, Phase = i * 0.6 })
	end
end

local function burst(show: Show)
	local factor = particleFactor()
	local rng = math.random
	local center = show.Center
	local pos = center
		+ Vector3.new((rng() * 2 - 1) * show.Spread, show.Height + rng() * 30, (rng() * 2 - 1) * show.Spread)
	local holder = localPart({ CFrame = CFrame.new(pos) })
	local palette = { Theme.Accent, Theme.Up, GOLD, COSMIC2, COSMIC3, Color3.fromRGB(34, 211, 238) }
	local c1 = palette[rng(1, #palette)]
	local c2 = palette[rng(1, #palette)]
	local spark = emitter(holder, TEX_SPARKLE, ColorSequence.new(c1, c2), {
		Lifetime = NumberRange.new(1.2, 2),
		Speed = NumberRange.new(28, 46),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 2.4,
		Acceleration = Vector3.new(0, -12, 0),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 2.4),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.7, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})
	local bits = emitter(holder, TEX_SQUARE, ColorSequence.new(c2, WHITE), {
		Lifetime = NumberRange.new(1.4, 2.4),
		Speed = NumberRange.new(16, 30),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 1.6,
		Acceleration = Vector3.new(0, -18, 0),
		Size = NumberSequence.new(0.5),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-180, 180),
	})
	local glow = emitter(holder, TEX_GLOW, ColorSequence.new(c1), {
		Lifetime = NumberRange.new(0.35, 0.5),
		Speed = NumberRange.new(0, 0),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 6),
			NumberSequenceKeypoint.new(1, 22),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})
	spark:Emit(math.floor(60 * factor) + 10)
	bits:Emit(math.floor(40 * factor) + 6)
	glow:Emit(1)
	-- echter Lichtblitz (Future-Licht färbt Glasfassaden/Dächer in der Burst-Farbe), nur im Licht-Budget hoher Stufen
	local okBudget, lights = tryModule("Quality", "Budget", "Lights")
	if okBudget and type(lights) == "number" and lights >= 32 and not reducedFx() then
		local flashLight = Instance.new("PointLight")
		flashLight.Color = c1
		flashLight.Range = 60
		flashLight.Brightness = 5
		flashLight.Shadows = false
		flashLight.Parent = holder
		TweenService:Create(
			flashLight,
			TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Brightness = 0, Range = 24 }
		):Play()
	end
	if math.random() < 0.5 then
		sfx("Whoosh", pos, { Volume = 0.35, Speed = 1.4 + math.random() * 0.4 })
	end
	task.delay(3, function()
		holder:Destroy()
	end)
end

local function stepShows()
	local t = os.clock()
	local i = 1
	while i <= #shows do
		local show = shows[i]
		if t >= show.Until then
			clearShow(show)
			table.remove(shows, i)
		else
			for _, entry in ipairs(show.Beams) do
				local phase = t * 0.9 + entry.Phase
				local mix = (math.sin(phase) + 1) * 0.5
				local color = COSMIC1:Lerp(COSMIC3, mix)
				entry.Beam.Color = ColorSequence.new(color, Theme.Accent:Lerp(GOLD, mix))
				entry.Beam.Width0 = 4 + math.sin(phase * 1.7) * 2
				local tilt = math.sin(phase * 0.5) * 40
				local a1 = entry.Beam.Attachment1
				if a1 then
					a1.Position = Vector3.new(tilt, 0, math.cos(phase * 0.4) * 40)
				end
			end
			if t >= show.Next then
				show.Next = t + FIREWORK_GAP / particleFactor() * (0.7 + math.random() * 0.6)
				burst(show)
			end
			i += 1
		end
	end
end

-- ---------------------------------------------------------------------
-- GELDREGEN (Münz-Schauer um die Kamera)
-- ---------------------------------------------------------------------
local function startRain(seconds: number)
	rainUntil = os.clock() + seconds
	if not rainPart then
		local holder = localPart({ Size = Vector3.new(90, 1, 90), CFrame = CFrame.new(0, 80, 0) })
		holder.Name = "AT_RainCloud"
		local e = emitter(holder, TEX_SPARKLE, ColorSequence.new(Theme.Up, GOLD), {
			Lifetime = NumberRange.new(2.4, 3.2),
			Speed = NumberRange.new(26, 34),
			EmissionDirection = Enum.NormalId.Bottom,
			SpreadAngle = Vector2.new(6, 6),
			Size = NumberSequence.new(1.2),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-120, 120),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.1),
				NumberSequenceKeypoint.new(1, 0.6),
			}),
		})
		rainPart = holder
		rainEmitter = e
	end
	local e = rainEmitter
	if e then
		e.Rate = math.floor(28 * particleFactor()) + 4
		e.Enabled = true
	end
end

local function stepRain()
	local e = rainEmitter
	local holder = rainPart
	if not e or not holder then
		return
	end
	local t = os.clock()
	if t >= rainUntil then
		if e.Enabled then
			e.Enabled = false
		end
		return
	end
	local camera = workspace.CurrentCamera
	if camera then
		local pos = camera.CFrame.Position
		holder.CFrame = CFrame.new(pos.X, pos.Y + 60, pos.Z)
	end
	if t >= rainSoundAt and t < rainUntil - 2 then
		rainSoundAt = t + 0.5 + math.random() * 0.9
		sfx("MoneyRain", nil, { Volume = 0.25 })
	end
end

-- ---------------------------------------------------------------------
-- BOSS-AUFTRITT (getweente Winke-Pose, rein lokal)
-- ---------------------------------------------------------------------
local function startBoss(seconds: number)
	task.spawn(function()
		local world = workspace:FindFirstChild("AT_EventWorld") or workspace:WaitForChild("AT_EventWorld", 10)
		local show = world and (world:FindFirstChild("AT_BossShow") or world:WaitForChild("AT_BossShow", 15))
		if not show then
			return
		end
		local motors: { { Motor: Motor6D, Base: CFrame } } = {}
		for _, d in ipairs(show:GetDescendants()) do
			if d:IsA("Motor6D") and (d.Name == "RightShoulder" or d.Name == "Right Shoulder") then
				table.insert(motors, { Motor = d, Base = d.C0 })
			end
			if #motors >= 8 then
				break
			end
		end
		boss = { Motors = motors, Until = os.clock() + seconds, Phase = 0 }
	end)
end

local function stepBoss(dt: number)
	local b = boss
	if not b then
		return
	end
	local t = os.clock()
	if t >= b.Until then
		for _, entry in ipairs(b.Motors) do
			if entry.Motor.Parent then
				entry.Motor.C0 = entry.Base
			end
		end
		boss = nil
		return
	end
	b.Phase += dt * BOSS_WAVE_SPEED
	for i, entry in ipairs(b.Motors) do
		if entry.Motor.Parent then
			local wave = math.sin(b.Phase + i * 0.4) * 0.35
			-- Arm hoch (≈ 150°) und hin und her winken
			entry.Motor.C0 = entry.Base * CFrame.Angles(0, 0, math.rad(150) + wave)
		end
	end
end

-- ---------------------------------------------------------------------
-- GLOCKEN-MOMENT (Welle an der Glocken-Zone)
-- ---------------------------------------------------------------------
local function bellWave()
	local center = workspace:GetAttribute("AT_BellZone")
	local pos: Vector3 = if typeof(center) == "Vector3" then center else plazaCenter()
	local holder = localPart({ CFrame = CFrame.new(pos + Vector3.new(0, 1, 0)) })
	local ring = emitter(holder, TEX_RING, ColorSequence.new(GOLD), {
		Lifetime = NumberRange.new(1.4, 1.4),
		Speed = NumberRange.new(0, 0),
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 4),
			NumberSequenceKeypoint.new(1, 70),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})
	ring.Acceleration = Vector3.zero
	ring:Emit(1)
	task.delay(0.35, function()
		if ring.Parent then
			ring:Emit(1)
		end
	end)
	local sparks = emitter(holder, TEX_SPARKLE, ColorSequence.new(GOLD, WHITE), {
		Lifetime = NumberRange.new(1, 1.8),
		Speed = NumberRange.new(10, 22),
		SpreadAngle = Vector2.new(60, 60),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -6, 0),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.6),
			NumberSequenceKeypoint.new(1, 0),
		}),
	})
	sparks:Emit(math.floor(40 * particleFactor()) + 8)
	task.delay(3, function()
		holder:Destroy()
	end)
end

-- ---------------------------------------------------------------------
-- EFFEKT-HANDLER
-- ---------------------------------------------------------------------
local BANNER_COLORS: { [string]: Color3 } = {
	GoldenHour = GOLD,
	XpRush = Theme.Accent,
	BuildBoom = Theme.Warn,
	SaturdayShow = COSMIC2,
	AutoShow = COSMIC2,
	AllToHall = Theme.Accent,
}

local function onAbuseBanner(_strength: number, data: any)
	if type(data) ~= "table" or type(data.Kind) ~= "string" then
		return
	end
	local kind = data.Kind
	local color = BANNER_COLORS[kind] or Theme.Accent
	local untilT = if type(data.Until) == "number" then data.Until else nil
	local sub: string
	if kind == "GoldenHour" then
		sub = T("evt.banner.GoldenHourSub", ("%g"):format(num(data.Mult, 2)))
	elseif kind == "XpRush" then
		sub = T("evt.banner.XpRushSub")
	elseif kind == "BuildBoom" then
		sub = T("evt.banner.BuildBoomSub")
	elseif kind == "SaturdayShow" or kind == "AutoShow" then
		sub = T("evt.banner.ShowSub", sectorName(data.Sector))
		sfx("RallyFanfare", nil, nil)
		tryModule("Sfx", "Duck", 0.5, 3)
	elseif kind == "AllToHall" then
		sub = T("evt.banner.AllToHallSub")
	else
		sub = ""
	end
	local titleKey = ({
		GoldenHour = "evt.banner.GoldenHour",
		XpRush = "evt.banner.XpRush",
		BuildBoom = "evt.banner.BuildBoom",
		SaturdayShow = "evt.banner.SaturdayShow",
		AutoShow = "evt.banner.AutoShow",
		AllToHall = "evt.banner.AllToHall",
	})[kind] or "evt.banner.Generic"
	if kind ~= "SaturdayShow" and kind ~= "AutoShow" then
		sfx("Notify", nil, nil)
	end
	queueBanner(T(titleKey), sub, color, untilT, nil)
end

local function onMoneyRain(_strength: number, data: any)
	local seconds = math.clamp(num(type(data) == "table" and data.Seconds, 120), 5, 300)
	queueBanner(T("evt.banner.MoneyRain"), T("evt.banner.MoneyRainSub"), Theme.Up, now() + seconds, nil)
	startRain(seconds)
	sfx("MoneyRain", nil, nil)
end

local function onBullParade(_strength: number, data: any)
	if type(data) ~= "table" then
		return
	end
	local name = if type(data.Name) == "string" then data.Name else "?"
	local untilT = if type(data.Until) == "number" then data.Until else now() + num(data.Seconds, 900)
	queueBanner(T("evt.paradeBanner", name), T("evt.banner.ParadeSub"), GOLD, untilT, 8)
	sfx("RallyFanfare", nil, nil)
end

local function onBear(_strength: number, data: any)
	local phase = type(data) == "table" and data.Phase or "Arrive"
	if phase == "Arrive" then
		queueBanner(T("evt.banner.Bear"), T("evt.banner.BearSub", math.floor(num(data.Goal, 0))), Theme.Down, nil, 8)
		sfx("CrashAlarm", nil, nil)
	elseif phase == "Success" then
		queueBanner(T("evt.banner.BearCalm"), T("evt.banner.BearCalmSub"), Theme.Up, nil, 6)
		flash(Theme.Up, nil)
		sfx("Achievement", nil, nil)
	end
end

local function onGoldenBull(_strength: number, data: any)
	local phase = type(data) == "table" and data.Phase or "Run"
	if phase == "Run" then
		queueBanner(T("evt.banner.GoldenBull"), T("evt.banner.GoldenBullSub"), GOLD, nil, 7)
		sfx("RallyFanfare", nil, nil)
	elseif phase == "Touch" then
		flash(GOLD, T("evt.bullBonus"))
		sfx("LevelUp", nil, nil)
	end
end

local function onSkyShow(_strength: number, data: any)
	local seconds = math.clamp(num(type(data) == "table" and data.Seconds, 75), 5, 600)
	local finale = type(data) == "table" and data.Finale == true
	local show: Show = {
		Kind = "Sky",
		Until = os.clock() + seconds,
		Next = os.clock() + 1.5,
		Center = plazaCenter(),
		Spread = 120,
		Height = 140,
		Parts = {},
		Beams = {},
	}
	skyBeams(show)
	addShow(show)
	queueBanner(
		T(if finale then "evt.banner.Finale" else "evt.banner.SkyShow"),
		T(if finale then "evt.banner.FinaleSub" else "evt.banner.SkyShowSub"),
		COSMIC3,
		nil,
		6
	)
	sfx("RallyFanfare", nil, { Volume = 0.6 })
end

local function onFireworks(_strength: number, data: any)
	local seconds = math.clamp(num(type(data) == "table" and data.Seconds, 20), 3, 60)
	local cf = plotCFrame(type(data) == "table" and data.Plot or nil)
	local center = if cf then cf.Position else plazaCenter()
	addShow({
		Kind = "Fireworks",
		Until = os.clock() + seconds,
		Next = os.clock() + 0.3,
		Center = center,
		Spread = if cf then 40 else 90,
		Height = if cf then 170 else 120,
		Parts = {},
		Beams = {},
	})
end

local function onBossAppear(_strength: number, data: any)
	local seconds = math.clamp(num(type(data) == "table" and data.Seconds, 120), 10, 300)
	local name = if type(data) == "table" and type(data.Name) == "string" then data.Name else "?"
	queueBanner(T("evt.banner.Boss", name), T("evt.banner.BossSub"), Theme.Accent, now() + seconds, 7)
	sfx("RallyFanfare", nil, nil)
	startBoss(seconds)
end

local function onBellMoment(_strength: number, data: any)
	local show = type(data) == "table" and data.Show == true
	bellWave()
	sfx("MarketBell", nil, nil)
	if show then
		queueBanner(T("evt.banner.BellShow"), T("evt.banner.BellShowSub"), GOLD, nil, 5)
	else
		local mult = num(type(data) == "table" and data.Mult, 1.2)
		flash(GOLD, T("evt.banner.BellMoment", ("%g"):format(mult)))
	end
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICHE API + LEBENSZYKLUS
-- ---------------------------------------------------------------------
function EffectsEvent.Step(dt: number)
	stepBanner()
	stepShows()
	stepRain()
	stepBoss(dt)
end

function EffectsEvent.Init(context: any)
	ctx = context
	local folder = Instance.new("Folder")
	folder.Name = "AT_EventFX"
	folder.Parent = workspace
	fxFolder = folder
	local Effects = module("Effects")
	local shared: any = nil
	if Effects and type(Effects.Overlay) == "function" then
		local ok, result = pcall(Effects.Overlay)
		if ok and typeof(result) == "Instance" and result:IsA("ScreenGui") then
			shared = result
		end
	end
	if not shared then
		shared = UI.Create("ScreenGui", {
			Name = "AkytexTycoonEventFX",
			ResetOnSpawn = false,
			IgnoreGuiInset = false,
			DisplayOrder = 5,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			Parent = player:WaitForChild("PlayerGui"),
		})
	end
	overlay = shared
	buildBanner()
	if Effects and type(Effects.Register) == "function" then
		Effects.Register("AbuseBanner", onAbuseBanner)
		Effects.Register("MoneyRain", onMoneyRain)
		Effects.Register("BullParade", onBullParade)
		Effects.Register("Bear", onBear)
		Effects.Register("GoldenBull", onGoldenBull)
		Effects.Register("SkyShow", onSkyShow)
		Effects.Register("Fireworks", onFireworks)
		Effects.Register("BossAppear", onBossAppear)
		Effects.Register("BellMoment", onBellMoment)
	else
		warn("[EffectsEvent] Effects-Registry fehlt – Event-Effekte inaktiv")
	end
end

function EffectsEvent.Start()
	local hooks = ctx and ctx.Hooks
	if hooks and type(hooks.On) == "function" then
		-- Foto-Modus: Shows bleiben (Welt), nur das Banner verschwindet mit dem Overlay (Effects.SetHidden)
		hooks.On("PhotoMode", function(on: any)
			if on == true and bannerFrame then
				bannerFrame.Visible = false
				bannerCurrent = nil
				table.clear(bannerQueue)
			end
		end)
	end
	player.CharacterAdded:Connect(function()
		-- Regen-Wolke folgt der Kamera; nichts zu tun außer sicherstellen, dass sie noch existiert
		if rainPart and not rainPart.Parent then
			rainPart = nil
			rainEmitter = nil
		end
	end)
end

return EffectsEvent
