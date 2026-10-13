-- =====================================================================
--  AKYTEX TYCOON – Licht, Tag/Nacht, Markt-Wetter, Crash/Rally, Licht-Budget (Client/Modules/WorldLook)
--  Besitzer: WP7 (Stadt, Grafik, Fahrzeuge). Vertrag: DESIGN.md §A4 (Tag/Nacht = Börsentag aus Clock, Markt-Wetter aus dem
--  Regime, Crash-/Rally-Tönung, Fensterlicht-Kaskade 0,05 s je Etage ab ClockTime 18,5, DoF nur in Menüs/Kamerafahrten),
--  §A7 #6/#7 (roter Himmel + Sirene, grüne Polarlichter + Fanfare), §B10.2, §C7.5 (WorldLook.SetOverride), §C16
--  (Lichter ≤ 6/16/32/64 je Grafikstufe), §0 Regel 16 (StreamingEnabled: alles über Attribute + DescendantAdded, nil-sicher).
--
--  Tageszeit: jeder Client rechnet aus workspace:GetServerTimeNow() (Clock) -> zwei Clients sind sekundengenau synchron.
--  Welt-Konventionen (Attribute, gesetzt von CityService/VehicleService/WP8):
--    Licht mit "Budget" = true      -> nur die nächsten N (Quality.Budget("Lights")) leuchten; "NightOnly" nur nachts
--    Teil mit "WindowLight" = Etage -> nachts warmes Fensterlicht, Kaskade von unten nach oben (0,05 s je Etage)
--    Model mit "Spin" = Grad/s      -> dreht sich lokal (Drehteller, Vitrinen, Leuchtturm), nur in der Nähe
--    Model mit "Bell" = true        -> schwingt bei der Glocke (Hook "Market:Bell")
--    Teil mit "LocalDoor" = "Vip"/"Club" -> nur für Spieler mit diesem Attribut offen (lokal)
--    ProximityPrompt mit "TextKey"/"ObjectKey" -> in die Spielersprache übersetzt
--
--  Öffentliche API (§C7.5):
--    WorldLook.SetOverride(kind?)   "Crash" | "Rally" | "Storm" | "Clouds" | "Clear" | "Day" | "Night" | "Golden" |
--                                   "Cinematic" (Tiefenschärfe für Kamerafahrten) | nil = automatisch
--  Zusätzlich: WorldLook.Weather(): string ("Clear"/"Clouds"/"Storm") · WorldLook.IsNight(): boolean ·
--    WorldLook.LightStats(): (aktiv, verwaltet) · WorldLook.Frame(dt) · WorldLook.Init(ctx) · WorldLook.Start()
-- =====================================================================

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local WorldLook = {}

local player = Players.LocalPlayer

type WindowEntry = {
	Part: BasePart,
	Level: number,
	Material: Enum.Material,
	Color: Color3,
	Transparency: number,
	Lit: boolean,
}
type Spinner = { Model: Model, Speed: number, Base: CFrame, Angle: number, Beam: Beam? }

local ctx: any = nil
local cfg: any = {}
local weatherCfg: any = {}
local lightsCfg: any = {}

local MAX_WINDOWS = 3000
local MAX_SPINNERS = 64
local MAX_PROMPTS = 400
local MAX_DOORS = 32
local WINDOW_STEP_LIMIT = 160 -- Fensteränderungen je Frame
local LOOK_HZ = 10
local SCAN_CHUNK = 2000

local override: string? = nil
local clockTime = 9
local nightFactor = 0
local isNight = false
local lookAccum = 0
local lightAccum = 0

-- Effekte (eigene, lokale Instanzen)
local atmosphere: Atmosphere? = nil
local colorCorrection: ColorCorrectionEffect? = nil
local bloom: BloomEffect? = nil
local dof: DepthOfFieldEffect? = nil
local clouds: Clouds? = nil
local stormCC: ColorCorrectionEffect? = nil -- Blitz-Flash

-- Markt-Wetter + Crash/Rally
local regime = 1
local frameCrash, frameRally = false, false
local eventMode: string? = nil -- "Crash" | "Rally" aus Hook "Market:Event"
local eventUntil = 0
local mode: string? = nil -- wirksamer Modus nach Override
local blend = { Crash = 0, Rally = 0, Cover = 0.2, Density = 0.5, Storm = 0 }
local lastMode: string? = nil
local nextLightning = 0
local flashUntil = 0

-- Regen & Polarlichter (lokal)
local rainPart: Part? = nil
local rainEmitter: ParticleEmitter? = nil
local auroraFolder: Folder? = nil
local auroraBeams: { Beam } = {}

-- Welt-Register
local windows: { [BasePart]: WindowEntry } = {}
local windowCount = 0
local windowQueue: { { Entry: WindowEntry, At: number, Lit: boolean } } = {}
local windowsLit = false
local lights: { [Light]: boolean } = {}
local lightCount = 0
local activeLights = 0
local spinners: { [Model]: Spinner } = {}
local spinnerCount = 0
local prompts: { [ProximityPrompt]: boolean } = {}
local promptCount = 0
local doors: { [BasePart]: { CanCollide: boolean, Transparency: number } } = {}
local doorCount = 0
local bellModel: Model? = nil
local bellSwing = 0 -- verbleibende Schwing-Zeit
local bellRest: CFrame? = nil -- Modell-Pivot in Ruhe
local bellHinge: CFrame? = nil -- Aufhängung (oben)
local dofWanted = false

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function call(name: string, fnName: string, ...: any): (boolean, any)
	local modules = ctx and ctx.Modules
	local m = modules and modules[name]
	local fn = m and m[fnName]
	if type(fn) ~= "function" then
		return false, nil
	end
	return pcall(fn, ...)
end

local function settings(): { [string]: any }
	local ok, value = call("Settings", "Get")
	if ok and type(value) == "table" then
		return value
	end
	return {}
end

local function reducedFx(): boolean
	return settings().ReducedFx == true
end

local function budget(key: string, fallback: number): number
	local ok, value = call("Quality", "Budget", key)
	if ok and type(value) == "number" then
		return value
	end
	return fallback
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function lerpColor(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, math.clamp(t, 0, 1))
end

local function smoothstep(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

local function approach(current: number, target: number, dt: number, seconds: number): number
	if seconds <= 0 then
		return target
	end
	local alpha = 1 - math.exp(-dt * 3 / seconds)
	return current + (target - current) * alpha
end

local function now(): number
	return ctx.Clock.Now()
end

-- ---------------------------------------------------------------------
-- 1) EIGENE LIGHTING-INSTANZEN (Server-Instanzen übernehmen, sonst lokal anlegen)
-- ---------------------------------------------------------------------
local function ensureEffects()
	local found = Lighting:FindFirstChildOfClass("Atmosphere")
	if not found then
		local created = Instance.new("Atmosphere")
		created.Name = "AT_Atmosphere"
		created.Parent = Lighting
		found = created
	end
	atmosphere = found
	local cc = Lighting:FindFirstChild("AT_ColorCorrection")
	if not (cc and cc:IsA("ColorCorrectionEffect")) then
		local created = Instance.new("ColorCorrectionEffect")
		created.Name = "AT_ColorCorrection"
		created.Parent = Lighting
		cc = created
	end
	colorCorrection = cc :: ColorCorrectionEffect
	local bl = Lighting:FindFirstChildOfClass("BloomEffect")
	if bl then
		bloom = bl
	end
	local flash = Instance.new("ColorCorrectionEffect")
	flash.Name = "AT_LightningFlash"
	flash.Brightness = 0
	flash.Parent = Lighting
	stormCC = flash
	local depth = Instance.new("DepthOfFieldEffect")
	depth.Name = "AT_MenuDepth"
	depth.Enabled = false
	local d = cfg.DepthOfField or {}
	depth.FarIntensity = 0
	depth.NearIntensity = 0
	depth.FocusDistance = d.FocusDistance or 14
	depth.InFocusRadius = d.InFocusRadius or 22
	depth.Parent = Lighting
	dof = depth
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		local c = terrain:FindFirstChildOfClass("Clouds")
		if not c then
			local created = Instance.new("Clouds")
			created.Name = "AT_Clouds"
			created.Parent = terrain
			c = created
		end
		clouds = c
	end
end

-- ---------------------------------------------------------------------
-- 2) MODUS (Override > Crash/Rally > Wetter)
-- ---------------------------------------------------------------------
local function weatherOf(r: number): string
	if r > (weatherCfg.StormAbove or 1.2) then
		return "Storm"
	elseif r >= (weatherCfg.ClearBelow or 0.85) then
		return "Clouds"
	end
	return "Clear"
end

local function effectiveMode(): string
	if override == "Crash" or override == "Rally" then
		return override
	end
	if eventMode and now() < eventUntil then
		return eventMode
	end
	if frameCrash then
		return "Crash"
	elseif frameRally then
		return "Rally"
	end
	return "None"
end

local function effectiveWeather(): string
	if override == "Storm" or override == "Clouds" or override == "Clear" then
		return override
	end
	return weatherOf(regime)
end

-- ---------------------------------------------------------------------
-- 3) REGEN, BLITZE, POLARLICHTER
-- ---------------------------------------------------------------------
local function ensureRain()
	if rainPart and rainPart.Parent then
		return
	end
	local rain = weatherCfg.Rain or {}
	local part = Instance.new("Part")
	part.Name = "AT_Rain"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new((rain.Radius or 70) * 2, 1, (rain.Radius or 70) * 2)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/SquareParticle.png"
	emitter.Color = ColorSequence.new(rain.Color or Color3.fromRGB(190, 205, 230))
	emitter.Transparency = NumberSequence.new(0.35)
	emitter.Size = NumberSequence.new(0.06)
	emitter.Lifetime = NumberRange.new(0.6, 0.8)
	emitter.Speed = NumberRange.new(rain.Speed or 120)
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Orientation = Enum.ParticleOrientation.VelocityParallel
	emitter.Squash = NumberSequence.new(4) -- lange dünne Tropfen
	emitter.LightEmission = 0.2
	emitter.Rate = 0
	emitter.Parent = part
	part.Parent = workspace
	rainPart = part
	rainEmitter = emitter
end

local function setAurora(on: boolean)
	if not on then
		if auroraFolder then
			auroraFolder:Destroy()
		end
		auroraFolder = nil
		table.clear(auroraBeams)
		return
	end
	if auroraFolder and auroraFolder.Parent then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "AT_Aurora"
	local holder = Instance.new("Part")
	holder.Name = "AuroraAnchor"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(1, 1, 1)
	holder.CFrame = CFrame.new(0, 220, 0)
	holder.Parent = folder
	local colors = (cfg.Rally and cfg.Rally.Aurora) or { Color3.fromRGB(34, 197, 94), Color3.fromRGB(34, 211, 238) }
	for i = 1, 6 do
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(-420, (i - 3) * 14, -160 + i * 50)
		a0.Parent = holder
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(420, (3 - i) * 12, -120 + i * 44)
		a1.Parent = holder
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Texture = "rbxasset://textures/gradient.png"
		beam.TextureMode = Enum.TextureMode.Stretch
		beam.Width0 = 60
		beam.Width1 = 90
		beam.CurveSize0 = 120
		beam.CurveSize1 = -120
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.FaceCamera = false
		beam.Color = ColorSequence.new(colors[1], colors[2] or colors[1])
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.55),
			NumberSequenceKeypoint.new(0.7, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		beam.Parent = holder
		table.insert(auroraBeams, beam)
	end
	folder.Parent = workspace
	auroraFolder = folder
end

local function updateWeatherFx(dt: number, weather: string)
	local storm = weather == "Storm"
	blend.Storm = approach(blend.Storm, if storm then 1 else 0, dt, weatherCfg.BlendSeconds or 8)
	local camera = workspace.CurrentCamera
	local rate = 0
	if blend.Storm > 0.05 then
		ensureRain()
		rate = (weatherCfg.Rain and weatherCfg.Rain.Rate or 380) * blend.Storm * budget("Particles", 1)
	end
	local part = rainPart
	if part and camera then
		local rain = weatherCfg.Rain or {}
		part.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, rain.Height or 45, 0))
	end
	if rainEmitter then
		rainEmitter.Rate = if reducedFx() then rate * 0.5 else rate
	end
	-- harmlose Blitze (nur Licht, kein Schaden); ReducedFx: aus
	local t = os.clock()
	local flash = stormCC
	if flash then
		if storm and blend.Storm > 0.6 and not reducedFx() and t >= nextLightning then
			local gap = weatherCfg.Lightning or {}
			nextLightning = t + (gap.MinGap or 6) + math.random() * ((gap.MaxGap or 14) - (gap.MinGap or 6))
			flashUntil = t + (gap.Flash or 0.12)
		end
		local target = if t < flashUntil then 0.35 else 0
		flash.Brightness = if target > 0 then target else approach(flash.Brightness, 0, dt, 0.15)
	end
end

-- ---------------------------------------------------------------------
-- 4) LICHT-LOOK (10 Hz): Tag/Nacht-Mischung + Crash/Rally + Wetter
-- ---------------------------------------------------------------------
local function applyLook(dt: number)
	local day = cfg.Day
	local night = cfg.Night
	if type(day) ~= "table" or type(night) ~= "table" then
		return
	end
	local n = nightFactor
	if override == "Day" then
		n = 0
	elseif override == "Night" then
		n = 1
	end
	Lighting.Ambient = lerpColor(day.Ambient, night.Ambient, n)
	Lighting.OutdoorAmbient = lerpColor(day.OutdoorAmbient, night.OutdoorAmbient, n)
	Lighting.Brightness = lerp(day.Brightness, night.Brightness, n)
	Lighting.ColorShift_Top = lerpColor(day.ColorShiftTop, night.ColorShiftTop, n)
	Lighting.ExposureCompensation = lerp(day.ExposureCompensation or 0, night.ExposureCompensation or 0, n)

	local blendSeconds = if reducedFx() then 0.3 else (cfg.BlendSeconds or 4)
	mode = effectiveMode()
	blend.Crash = approach(blend.Crash, if mode == "Crash" then 1 else 0, dt, blendSeconds)
	blend.Rally = approach(blend.Rally, if mode == "Rally" then 1 else 0, dt, blendSeconds)
	local atmo = atmosphere
	if atmo then
		local a, b = day.Atmosphere, night.Atmosphere
		atmo.Density = lerp(a.Density, b.Density, n) + 0.06 * blend.Storm
		atmo.Haze = lerp(a.Haze, b.Haze, n) + 0.8 * blend.Storm
		atmo.Glare = lerp(a.Glare, b.Glare, n)
		atmo.Offset = lerp(a.Offset, b.Offset, n)
		local color = a.Color
		local crashAtmo = cfg.Crash and cfg.Crash.Atmosphere
		if typeof(crashAtmo) == "Color3" then
			color = lerpColor(color, crashAtmo, blend.Crash)
		end
		atmo.Color = color
		atmo.Decay = lerpColor(a.Decay, b.Decay, n)
	end
	local cc = colorCorrection
	if cc then
		local base = cfg.ColorCorrection or {}
		local crash = cfg.Crash or {}
		local rally = cfg.Rally or {}
		local tint = base.Tint or Color3.new(1, 1, 1)
		tint = lerpColor(tint, crash.Tint or tint, blend.Crash)
		tint = lerpColor(tint, rally.Tint or tint, blend.Rally)
		if override == "Golden" and cfg.Golden then
			tint = cfg.Golden.Tint
		end
		cc.TintColor = tint
		cc.Saturation = (base.Saturation or 0.05)
			+ ((crash.Saturation or -0.15) - (base.Saturation or 0.05)) * blend.Crash
			+ ((rally.Saturation or 0.12) - (base.Saturation or 0.05)) * blend.Rally
			- 0.08 * blend.Storm
		cc.Contrast = (base.Contrast or 0.08)
			+ ((crash.Contrast or 0.14) - (base.Contrast or 0.08)) * blend.Crash
			+ ((rally.Contrast or 0.1) - (base.Contrast or 0.08)) * blend.Rally
	end
	local bl = bloom
	if bl and cfg.Bloom then
		bl.Intensity = cfg.Bloom.Intensity + 0.15 * n
	end
	-- Wolken nach Markt-Wetter
	local weather = effectiveWeather()
	local c = clouds
	if c then
		local cover = weatherCfg.Cover or {}
		local density = weatherCfg.Density or {}
		local colors = weatherCfg.CloudColor or {}
		blend.Cover = approach(blend.Cover, (cover :: any)[weather] or 0.3, dt, weatherCfg.BlendSeconds or 8)
		blend.Density = approach(blend.Density, (density :: any)[weather] or 0.6, dt, weatherCfg.BlendSeconds or 8)
		c.Cover = blend.Cover
		c.Density = blend.Density
		if colors.Clear and colors.Storm then
			c.Color = lerpColor(colors.Clear, colors.Storm, blend.Storm)
		end
	end
	-- Polarlichter (Rally) ein/aus
	setAurora(blend.Rally > 0.05 and not reducedFx())
	for _, beam in ipairs(auroraBeams) do
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 1 - 0.45 * blend.Rally),
			NumberSequenceKeypoint.new(0.7, 1 - 0.45 * blend.Rally),
			NumberSequenceKeypoint.new(1, 1),
		})
	end
	-- Sirene/Fanfare einmal beim Wechsel (§B10.2)
	if mode ~= lastMode then
		if mode == "Crash" then
			call("Sfx", "Play", "CrashAlarm") -- Ticker-Wände färbt das Modul Ticker bei Crash selbst rot
		elseif mode == "Rally" then
			call("Sfx", "Play", "RallyFanfare")
		end
		lastMode = mode
	end
end

-- ---------------------------------------------------------------------
-- 5) FENSTERLICHT-KASKADE
-- ---------------------------------------------------------------------
local function setWindow(entry: WindowEntry, lit: boolean)
	local part = entry.Part
	if not part.Parent or entry.Lit == lit then
		return
	end
	entry.Lit = lit
	if lit then
		local custom = part:GetAttribute("LitColor")
		part.Material = Enum.Material.Neon
		part.Color = if typeof(custom) == "Color3" then custom else (cfg.WindowLit or Color3.fromRGB(255, 214, 150))
		part.Transparency = math.min(entry.Transparency, 0.2)
	else
		part.Material = entry.Material
		part.Color = entry.Color
		part.Transparency = entry.Transparency
	end
end

local function addWindow(part: BasePart)
	if windows[part] or windowCount >= MAX_WINDOWS then
		return
	end
	local level = part:GetAttribute("WindowLight")
	local entry: WindowEntry = {
		Part = part,
		Level = if type(level) == "number" then math.max(0, level) else 0,
		Material = part.Material,
		Color = part.Color,
		Transparency = part.Transparency,
		Lit = false,
	}
	windows[part] = entry
	windowCount += 1
	if windowsLit then
		setWindow(entry, true) -- nachts hereingestreamt: sofort an
	end
end

local function removeWindow(part: BasePart)
	if windows[part] then
		windows[part] = nil
		windowCount -= 1
	end
end

local function scheduleWindows(lit: boolean)
	windowsLit = lit
	table.clear(windowQueue)
	local t = os.clock()
	local step = if reducedFx() then 0 else (cfg.WindowCascade or 0.05)
	for _, entry in pairs(windows) do
		table.insert(windowQueue, { Entry = entry, At = t + (if lit then entry.Level * step else 0), Lit = lit })
	end
	table.sort(windowQueue, function(a, b)
		return a.At > b.At -- vom Ende abarbeiten (pop)
	end)
end

local function processWindows()
	local t = os.clock()
	local done = 0
	while #windowQueue > 0 and done < WINDOW_STEP_LIMIT do
		local item = windowQueue[#windowQueue]
		if item.At > t then
			break
		end
		windowQueue[#windowQueue] = nil
		setWindow(item.Entry, item.Lit)
		done += 1
	end
end

-- ---------------------------------------------------------------------
-- 6) LICHT-BUDGET (2 Hz): nur die nächsten N Lichter leuchten
-- ---------------------------------------------------------------------
local function lightPosition(light: Light): Vector3?
	local parent = light.Parent
	if parent and parent:IsA("BasePart") then
		return parent.Position
	elseif parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	return nil
end

local function manageLights()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local origin = camera.CFrame.Position
	local n = math.max(0, math.floor(budget("Lights", 16)))
	local candidates: { { Light: Light, D: number } } = {}
	for light in pairs(lights) do
		if not light.Parent then
			lights[light] = nil
			lightCount -= 1
			continue
		end
		local wanted = light:GetAttribute("Budget") == true and (light:GetAttribute("NightOnly") ~= true or isNight)
		local pos = wanted and lightPosition(light) or nil
		if pos then
			table.insert(candidates, { Light = light, D = (pos - origin).Magnitude })
		elseif light.Enabled then
			light.Enabled = false
		end
	end
	table.sort(candidates, function(a, b)
		return a.D < b.D
	end)
	activeLights = 0
	for index, item in ipairs(candidates) do
		local on = index <= n and item.D < 600
		if item.Light.Enabled ~= on then
			item.Light.Enabled = on
		end
		if on then
			activeLights += 1
		end
	end
end

local function addLight(light: Light)
	if lights[light] or lightCount >= (lightsCfg.MaxManaged or 600) then
		return
	end
	if light:GetAttribute("Budget") == nil then
		return -- nicht verwaltet (z. B. Laden-Spot: CityLife)
	end
	lights[light] = true
	lightCount += 1
	light.Enabled = false
end

-- ---------------------------------------------------------------------
-- 7) DREHENDE AUSSTELLUNGSSTÜCKE, GLOCKE
-- ---------------------------------------------------------------------
local function addSpinner(model: Model)
	if spinners[model] or spinnerCount >= MAX_SPINNERS then
		return
	end
	local speed = model:GetAttribute("Spin")
	if type(speed) ~= "number" then
		return
	end
	local okPivot, base = pcall(function(): CFrame
		local pivot = model:GetPivot()
		local center, size = model:GetBoundingBox()
		if (pivot.Position - center.Position).Magnitude > size.Magnitude then
			-- Kein sinnvoller Drehpunkt (z. B. Weltursprung): Mitte der Bounding-Box, nur Verschiebung
			return CFrame.new(center.Position)
		end
		return pivot
	end)
	if not okPivot then
		return
	end
	local spinner: Spinner = { Model = model, Speed = speed, Base = base, Angle = 0, Beam = nil }
	if model:GetAttribute("Beam") == true then
		-- Leuchtturm-Lichtkegel (lokal)
		local primary = model:FindFirstChildWhichIsA("BasePart")
		if primary then
			local a0 = Instance.new("Attachment")
			a0.Name = "AT_BeamA"
			a0.Parent = primary
			local a1 = Instance.new("Attachment")
			a1.Name = "AT_BeamB"
			a1.Position = Vector3.new(0, -4, -120)
			a1.Parent = primary
			local beam = Instance.new("Beam")
			beam.Attachment0 = a0
			beam.Attachment1 = a1
			beam.Width0 = 2
			beam.Width1 = 34
			beam.Texture = "rbxasset://textures/gradient.png"
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.FaceCamera = true
			beam.Color = ColorSequence.new(Color3.fromRGB(255, 226, 170))
			beam.Transparency =
				NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
			beam.Enabled = false
			beam.Parent = primary
			spinner.Beam = beam
		end
	end
	spinners[model] = spinner
	spinnerCount += 1
end

local function removeSpinner(model: Model)
	if spinners[model] then
		spinners[model] = nil
		spinnerCount -= 1
	end
end

local function updateSpinners(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local origin = camera.CFrame.Position
	local radius = (ctx.Config.City and ctx.Config.City.Life and ctx.Config.City.Life.SpinRadius) or 260
	local reduced = reducedFx()
	for model, spinner in pairs(spinners) do
		if not model.Parent then
			removeSpinner(model)
			continue
		end
		local near = (spinner.Base.Position - origin).Magnitude < (if spinner.Beam then 1200 else radius)
		if spinner.Beam then
			spinner.Beam.Enabled = isNight
		end
		if near and not reduced then
			spinner.Angle = (spinner.Angle + math.rad(spinner.Speed) * dt) % (2 * math.pi)
			model:PivotTo(spinner.Base * CFrame.Angles(0, spinner.Angle, 0))
		end
	end
end

local function setBell(model: Model?)
	bellModel = model
	bellRest, bellHinge = nil, nil
	bellSwing = 0
	if not model then
		return
	end
	local ok, cf, size = pcall(function(): (CFrame, Vector3)
		return model:GetBoundingBox()
	end)
	if ok then
		bellRest = model:GetPivot()
		bellHinge = (cf :: CFrame) * CFrame.new(0, (size :: Vector3).Y / 2, 0)
	end
end

local function updateBell(dt: number)
	local model = bellModel
	local rest, hinge = bellRest, bellHinge
	if bellSwing <= 0 or not model or not model.Parent or not rest or not hinge then
		return
	end
	bellSwing = math.max(0, bellSwing - dt)
	if bellSwing <= 0 then
		model:PivotTo(rest)
		return
	end
	local amplitude = math.rad(18) * (bellSwing / 3) -- gedämpft ausschwingen
	local angle = math.sin((3 - bellSwing) * 7) * amplitude
	model:PivotTo(hinge * CFrame.Angles(angle, 0, 0) * hinge:Inverse() * rest)
end

-- ---------------------------------------------------------------------
-- 8) LOKALE TÜREN, PROMPT-TEXTE
-- ---------------------------------------------------------------------
local function doorOpenFor(kind: any): boolean
	if kind == "Vip" then
		return player:GetAttribute("Vip") == true
	elseif kind == "Club" then
		return player:GetAttribute("Club") == true
	end
	return false
end

local function applyDoor(part: BasePart)
	local original = doors[part]
	if not original then
		return
	end
	if doorOpenFor(part:GetAttribute("LocalDoor")) then
		part.CanCollide = false
		part.CanQuery = false
		part.Transparency = 0.85
	else
		part.CanCollide = original.CanCollide
		part.CanQuery = true
		part.Transparency = original.Transparency
	end
end

local function addDoor(part: BasePart)
	if doors[part] or doorCount >= MAX_DOORS then
		return
	end
	doors[part] = { CanCollide = part.CanCollide, Transparency = part.Transparency }
	doorCount += 1
	applyDoor(part)
end

local function localizePrompt(prompt: ProximityPrompt)
	local key = prompt:GetAttribute("TextKey")
	if type(key) == "string" then
		prompt.ActionText = ctx.T(key)
	end
	local objectKey = prompt:GetAttribute("ObjectKey")
	if type(objectKey) == "string" then
		prompt.ObjectText = ctx.T(objectKey)
	end
end

local function addPrompt(prompt: ProximityPrompt)
	if prompts[prompt] or promptCount >= MAX_PROMPTS then
		return
	end
	if prompt:GetAttribute("TextKey") == nil then
		return
	end
	prompts[prompt] = true
	promptCount += 1
	localizePrompt(prompt)
end

-- ---------------------------------------------------------------------
-- 9) WELT-SCAN (StreamingEnabled: kommt/geht jederzeit)
-- ---------------------------------------------------------------------
local function consider(inst: Instance)
	if inst:IsA("BasePart") then
		if inst:GetAttribute("WindowLight") ~= nil then
			addWindow(inst)
		end
		if inst:GetAttribute("LocalDoor") ~= nil then
			addDoor(inst)
		end
	elseif inst:IsA("Light") then
		addLight(inst)
	elseif inst:IsA("Model") then
		if inst:GetAttribute("Spin") ~= nil then
			addSpinner(inst)
		end
		if inst:GetAttribute("Bell") == true then
			setBell(inst)
		end
	elseif inst:IsA("ProximityPrompt") then
		addPrompt(inst)
	end
end

local function forget(inst: Instance)
	if inst:IsA("BasePart") then
		removeWindow(inst)
		if doors[inst] then
			doors[inst] = nil
			doorCount -= 1
		end
	elseif inst:IsA("Light") then
		if lights[inst] then
			lights[inst] = nil
			lightCount -= 1
		end
	elseif inst:IsA("Model") then
		removeSpinner(inst)
		if inst == bellModel then
			setBell(nil)
		end
	elseif inst:IsA("ProximityPrompt") then
		if prompts[inst] then
			prompts[inst] = nil
			promptCount -= 1
		end
	end
end

local function scan()
	local ok, list = pcall(function()
		return workspace:GetDescendants()
	end)
	if not ok or type(list) ~= "table" then
		return
	end
	for index, inst in ipairs(list) do
		consider(inst)
		if index % SCAN_CHUNK == 0 then
			task.wait()
		end
	end
end

-- ---------------------------------------------------------------------
-- 10) TIEFENSCHÄRFE (Menüs, Kamerafahrten)
-- ---------------------------------------------------------------------
local function updateDof()
	local depth = dof
	if not depth then
		return
	end
	local windowOpen = false
	local okOpen, anyOpen = call("UI", "IsAnyWindowOpen")
	if okOpen then
		windowOpen = anyOpen == true
	end
	local want = (windowOpen or override == "Cinematic") and budget("DoF", 0) >= 1 and not reducedFx()
	if want == dofWanted then
		return
	end
	dofWanted = want
	local d = cfg.DepthOfField or {}
	if want then
		depth.Enabled = true
	end
	local tween = TweenService:Create(depth, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		FarIntensity = if want then (d.FarIntensity or 0.28) else 0,
		NearIntensity = if want then (d.NearIntensity or 0.2) else 0,
	})
	tween.Completed:Once(function()
		if not dofWanted then
			depth.Enabled = false
		end
	end)
	tween:Play()
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICHE API
-- ---------------------------------------------------------------------
function WorldLook.SetOverride(kind: string?)
	local valid = {
		Crash = true,
		Rally = true,
		Storm = true,
		Clouds = true,
		Clear = true,
		Day = true,
		Night = true,
		Golden = true,
		Cinematic = true,
	}
	if kind ~= nil and not valid[kind] then
		warn("[WorldLook] unbekannter Override: " .. tostring(kind))
		return
	end
	override = kind
	if kind == "Crash" then
		call("Ticker", "SetTint", (cfg.Crash and cfg.Crash.Tint) or Color3.fromRGB(239, 68, 68))
	else
		call("Ticker", "SetTint", nil)
	end
	updateDof()
end

function WorldLook.Weather(): string
	return effectiveWeather()
end

function WorldLook.IsNight(): boolean
	return isNight
end

function WorldLook.LightStats(): (number, number)
	return activeLights, lightCount
end

function WorldLook.Frame(dt: number)
	-- Tageszeit (stetig, aus der Server-Zeit)
	local t = now() - ctx.Clock.EPOCH
	local ok, value = pcall(ctx.Clock.ClockTime, t)
	clockTime = if ok and type(value) == "number" then value else clockTime
	if override == "Golden" and cfg.Golden then
		clockTime = cfg.Golden.ClockTime
	elseif override == "Day" then
		clockTime = 12
	elseif override == "Night" then
		clockTime = 23
	end
	Lighting.ClockTime = clockTime
	-- Nacht-Anteil: Dämmerung 17 -> 20, Morgen 4,5 -> 7
	local ct = clockTime
	local evening = smoothstep(17, 20, ct)
	local morning = 1 - smoothstep(4.5, 7, ct)
	nightFactor = if ct >= 12 then evening else morning
	local onAt = cfg.WindowOnAt or 18.5
	local offAt = cfg.WindowOffAt or 6.2
	local nightNow = ct >= onAt or ct < offAt
	if override == "Night" then
		nightNow = true
	elseif override == "Day" or override == "Golden" then
		nightNow = false
	end
	if nightNow ~= isNight then
		isNight = nightNow
		scheduleWindows(nightNow)
		lightAccum = math.huge -- Laternen sofort umschalten
	end
	processWindows()

	lookAccum += dt
	if lookAccum >= 1 / LOOK_HZ then
		local step = lookAccum
		lookAccum = 0
		applyLook(step)
		updateWeatherFx(step, effectiveWeather())
	end
	lightAccum += dt
	if lightAccum >= 1 / (lightsCfg.ManageHz or 2) then
		lightAccum = 0
		manageLights()
	end
	updateSpinners(dt)
	updateBell(dt)
end

function WorldLook.Init(context: any)
	ctx = context
	local city = ctx.Config.City or {}
	cfg = city.Look or {}
	weatherCfg = city.Weather or {}
	lightsCfg = city.Lights or {}
	ensureEffects()
	local hooks = ctx.Hooks
	hooks.On("Quotes", function(frame: any)
		if type(frame) ~= "table" then
			return
		end
		if type(frame.Regime) == "number" and frame.Regime == frame.Regime then
			regime = frame.Regime
		end
		local flags = if type(frame.Flags) == "number" then frame.Flags else 0
		frameCrash = bit32.band(flags, 4) ~= 0 -- QuoteCodec.FRAME_FLAGS.Crash
		frameRally = bit32.band(flags, 8) ~= 0 -- QuoteCodec.FRAME_FLAGS.Rally
	end)
	hooks.On("Market:Event", function(data: any)
		if type(data) ~= "table" or (data.Kind ~= "Crash" and data.Kind ~= "Rally") then
			return
		end
		if data.Phase == "End" then
			if eventMode == data.Kind then
				eventMode = nil
				eventUntil = 0
			end
			return
		end
		eventMode = data.Kind
		local untilTick = if type(data.Until) == "number" then data.Until else 0
		local untilUnix = ctx.Clock.UnixOf(untilTick)
		eventUntil = if untilUnix > now() then untilUnix else now() + 300
	end)
	hooks.On("Market:Bell", function()
		if bellModel and not reducedFx() then
			bellSwing = 3
		end
	end)
	hooks.On("WindowOpened", updateDof)
	hooks.On("WindowClosed", function()
		task.defer(updateDof)
	end)
	hooks.On("Quality", function()
		lightAccum = math.huge
		updateDof()
	end)
	hooks.On("Settings", function()
		for prompt in pairs(prompts) do
			if prompt.Parent then
				localizePrompt(prompt)
			end
		end
		updateDof()
	end)
	player:GetAttributeChangedSignal("Vip"):Connect(function()
		for part in pairs(doors) do
			applyDoor(part)
		end
	end)
	player:GetAttributeChangedSignal("Club"):Connect(function()
		for part in pairs(doors) do
			applyDoor(part)
		end
	end)
end

function WorldLook.Start()
	workspace.DescendantAdded:Connect(function(inst: Instance)
		consider(inst)
	end)
	workspace.DescendantRemoving:Connect(function(inst: Instance)
		forget(inst)
	end)
	task.spawn(scan)
end

return WorldLook
