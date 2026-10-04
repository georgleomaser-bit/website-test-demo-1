-- Grafik: helles, sattes Sonnenlicht wie in Simulator-Spielen.
-- Licht, Atmosphäre, Bloom (dezent), Sonnenstrahlen, Farbkorrektur, Himmel und Wolken.
-- Hinweis: Lighting.Technology = "Future" und Workspace.StreamingEnabled = false stehen in
-- default.project.json – Technology kann ein Script im laufenden Spiel nicht umstellen.
-- Wird in Main.server.luau VOR PlotService geladen.
--
-- NACHT: GraphicsService.SetNight(isNight, bloodMoon?, fadeTime?) blendet weich zwischen Tag und
-- Nacht um (Uhrzeit, Licht, Atmosphäre, Wolken, Farbton). Nachts sind Mond und Sterne zu sehen und die
-- Laternen der Basen leuchten (PointLight "NightLight"). Blutmond = roter Himmel.
-- Wann es Nacht wird, entscheidet NightService (Config.Night).

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local GraphicsService = {}

-- Uhrzeit: Tag 14 Uhr, Nacht kurz vor Mitternacht (Mond + Sterne)
local DAY_CLOCK = 14
local NIGHT_CLOCK = 23.9
local LANTERN_RANGE = 24
local LANTERN_BRIGHTNESS = 1.8
local LANTERN_COLOR = Color3.fromRGB(255, 210, 130)

-- Aussehen je Tageszeit (Lighting, Atmosphäre, Farbkorrektur, Wolken)
type Look = {
	Lighting: { [string]: any },
	Atmosphere: { [string]: any },
	Color: { [string]: any },
	Clouds: { [string]: any },
}
local LOOKS: { [string]: Look } = {
	Day = {
		Lighting = {
			Brightness = 2.5,
			Ambient = Color3.fromRGB(45, 45, 55),
			OutdoorAmbient = Color3.fromRGB(135, 135, 150),
			ColorShift_Top = Color3.fromRGB(255, 248, 235),
			ExposureCompensation = 0,
		},
		Atmosphere = {
			Density = 0.27,
			Color = Color3.fromRGB(200, 225, 255),
			Decay = Color3.fromRGB(120, 160, 220),
			Glare = 0.15,
			Haze = 0.8,
		},
		Color = { TintColor = Color3.new(1, 1, 1), Saturation = 0.2 },
		Clouds = { Cover = 0.55, Color = Color3.new(1, 1, 1) },
	},
	Night = {
		Lighting = {
			Brightness = 1.2,
			Ambient = Color3.fromRGB(50, 55, 90),
			OutdoorAmbient = Color3.fromRGB(90, 100, 150),
			ColorShift_Top = Color3.fromRGB(170, 190, 255),
			ExposureCompensation = 0.25,
		},
		Atmosphere = {
			Density = 0.32,
			Color = Color3.fromRGB(70, 80, 130),
			Decay = Color3.fromRGB(30, 35, 80),
			Glare = 0,
			Haze = 1.2,
		},
		Color = { TintColor = Color3.fromRGB(215, 225, 255), Saturation = 0.1 },
		Clouds = { Cover = 0.3, Color = Color3.fromRGB(70, 75, 110) },
	},
	Blood = {
		Lighting = {
			Brightness = 1.4,
			Ambient = Color3.fromRGB(95, 35, 40),
			OutdoorAmbient = Color3.fromRGB(150, 70, 70),
			ColorShift_Top = Color3.fromRGB(255, 120, 110),
			ExposureCompensation = 0.25,
		},
		Atmosphere = {
			Density = 0.34,
			Color = Color3.fromRGB(170, 50, 50),
			Decay = Color3.fromRGB(90, 10, 20),
			Glare = 0.1,
			Haze = 1.5,
		},
		Color = { TintColor = Color3.fromRGB(255, 185, 180), Saturation = 0.15 },
		Clouds = { Cover = 0.35, Color = Color3.fromRGB(120, 40, 45) },
	},
}

local lookName = "Day"
local running: { Tween } = {}

-- Diese Effekte bauen wir selbst -> alte/doppelte Versionen vorher entfernen (sonst addieren sie sich)
local OWN_CLASSES = { "Atmosphere", "Sky", "BloomEffect", "SunRaysEffect", "ColorCorrectionEffect" }

local function clearOld()
	for _, child in ipairs(Lighting:GetChildren()) do
		if table.find(OWN_CLASSES, child.ClassName) then
			child:Destroy()
		end
	end
end

local function applyLighting()
	Lighting.ClockTime = 14 -- Nachmittag: Sonne hoch, kurze Schatten
	Lighting.GeographicLatitude = 35
	Lighting.Brightness = 2.5
	Lighting.ExposureCompensation = 0
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
	Lighting.Ambient = Color3.fromRGB(45, 45, 55)
	Lighting.OutdoorAmbient = Color3.fromRGB(135, 135, 150)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 248, 235) -- leicht warmes Sonnenlicht
	Lighting.ColorShift_Bottom = Color3.new(0, 0, 0)
end

local function buildEffects()
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "MH_Atmosphere"
	atmosphere.Density = 0.27
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(200, 225, 255)
	atmosphere.Decay = Color3.fromRGB(120, 160, 220)
	atmosphere.Glare = 0.15
	atmosphere.Haze = 0.8
	atmosphere.Parent = Lighting

	local sky = Instance.new("Sky") -- Standard-Himmel von Roblox (blau mit Wolken)
	sky.Name = "MH_Sky"
	sky.SunAngularSize = 16
	sky.MoonAngularSize = 11
	sky.StarCount = 3000
	sky.CelestialBodiesShown = true
	sky.Parent = Lighting

	local bloom = Instance.new("BloomEffect") -- dezent: nur Neon leuchtet etwas über
	bloom.Name = "MH_Bloom"
	bloom.Intensity = 0.6
	bloom.Size = 24
	bloom.Threshold = 1.8
	bloom.Parent = Lighting

	local sunRays = Instance.new("SunRaysEffect")
	sunRays.Name = "MH_SunRays"
	sunRays.Intensity = 0.05
	sunRays.Spread = 0.7
	sunRays.Parent = Lighting

	local colorCorrection = Instance.new("ColorCorrectionEffect") -- knalligere Farben
	colorCorrection.Name = "MH_ColorCorrection"
	colorCorrection.Brightness = 0.03
	colorCorrection.Contrast = 0.08
	colorCorrection.Saturation = 0.2
	colorCorrection.TintColor = Color3.new(1, 1, 1)
	colorCorrection.Parent = Lighting
end

local function buildClouds()
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if not terrain then
		return
	end
	local clouds = terrain:FindFirstChildOfClass("Clouds")
	if not clouds then
		clouds = Instance.new("Clouds")
		clouds.Name = "MH_Clouds"
		clouds.Parent = terrain
	end
	clouds.Cover = 0.55
	clouds.Density = 0.7
	clouds.Color = Color3.new(1, 1, 1)
	clouds.Enabled = true
end

-- -------------------------------------------------------------------
-- NACHT
-- -------------------------------------------------------------------
local function stopTweens()
	for _, tween in ipairs(running) do
		tween:Cancel()
	end
	table.clear(running)
end

local function play(target: Instance?, info: TweenInfo, props: { [string]: any })
	if not target then
		return
	end
	local tween = TweenService:Create(target, info, props)
	table.insert(running, tween)
	tween:Play()
end

-- Laternen der Basen (Neon-Würfel "LanternLamp" von MapBuilder) bekommen ein Licht für die Nacht
local function lanternLights(): { PointLight }
	local lights: { PointLight } = {}
	local map = workspace:FindFirstChild("MeteorHeistMap")
	if not map then
		return lights
	end
	for _, inst in ipairs(map:GetDescendants()) do
		if inst.Name == "LanternLamp" and inst:IsA("BasePart") then
			local light = inst:FindFirstChild("NightLight")
			if not light then
				local created = Instance.new("PointLight")
				created.Name = "NightLight"
				created.Color = LANTERN_COLOR
				created.Range = LANTERN_RANGE
				created.Brightness = 0
				created.Shadows = false
				created.Enabled = false
				created.Parent = inst
				light = created
			end
			if light and light:IsA("PointLight") then
				table.insert(lights, light)
			end
		end
	end
	return lights
end

-- Weich zwischen Tag, Nacht und Blutmond umblenden (fadeTime Sekunden, Standard 10)
function GraphicsService.SetNight(isNight: boolean, bloodMoon: boolean?, fadeTime: number?)
	local target = if not isNight then "Day" elseif bloodMoon then "Blood" else "Night"
	if target == lookName then
		return
	end
	local wasDay = lookName == "Day"
	lookName = target
	stopTweens()
	local look = LOOKS[target]
	local seconds = math.clamp(tonumber(fadeTime) or 10, 0.1, 60)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	-- Uhrzeit läuft immer VORWÄRTS: Sonnenuntergang 14 -> 23.9, Sonnenaufgang 0 -> 14
	local lightingProps = table.clone(look.Lighting)
	if target == "Day" then
		if Lighting.ClockTime > 18 then
			Lighting.ClockTime = 0 -- Mitternacht -> weiter über den Sonnenaufgang
		end
		lightingProps.ClockTime = DAY_CLOCK
	elseif wasDay then
		lightingProps.ClockTime = NIGHT_CLOCK
	end
	play(Lighting, info, lightingProps)
	play(Lighting:FindFirstChild("MH_Atmosphere"), info, look.Atmosphere)
	play(Lighting:FindFirstChild("MH_ColorCorrection"), info, look.Color)
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	play(terrain and terrain:FindFirstChildOfClass("Clouds"), info, look.Clouds)

	-- Laternen: nachts an (weich heller), tagsüber aus
	for _, light in ipairs(lanternLights()) do
		if isNight then
			light.Enabled = true
			play(light, info, {
				Brightness = LANTERN_BRIGHTNESS,
				Color = if bloodMoon then Color3.fromRGB(255, 120, 100) else LANTERN_COLOR,
			})
		else
			local tween = TweenService:Create(light, info, { Brightness = 0 })
			table.insert(running, tween)
			tween.Completed:Connect(function(state)
				if state == Enum.PlaybackState.Completed then
					light.Enabled = false
				end
			end)
			tween:Play()
		end
	end
end

function GraphicsService.IsNightLook(): boolean
	return lookName ~= "Day"
end

function GraphicsService.Init(_services)
	clearOld()
	applyLighting()
	buildEffects()
	buildClouds()
end

return GraphicsService
