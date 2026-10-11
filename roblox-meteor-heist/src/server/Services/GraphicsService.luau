-- Grafik: klares, helles Simulator-Licht wie in Steal a Brainrot / Pet Simulator.
-- Licht, Atmosphäre (kaum Dunst), Bloom (sehr schwach), Farbkorrektur (leicht), blauer Himmel, weiße Wolken.
-- Keine Sonnenstrahlen (SunRays) – die machen den Look nur milchig.
-- Hinweis: Lighting.Technology = "ShadowMap" (klassischer Roblox-Look, scharfe Sonnenschatten, schnell auf
-- Handys und mit vielen Spielern) und Workspace.StreamingEnabled = false stehen in default.project.json –
-- Technology kann ein Script im laufenden Spiel nicht umstellen.
-- Wird in Main.server.luau VOR PlotService geladen.
--
-- NACHT: GraphicsService.SetNight(isNight, bloodMoon?, fadeTime?) blendet weich zwischen Tag und
-- Nacht um (Uhrzeit, Licht, Atmosphäre, Wolken, Farbton). Nachts sind Mond und Sterne zu sehen und die
-- Laternen der Basen leuchten (PointLight "NightLight"). Blutmond = roter Himmel.
-- Nacht und Blutmond: stimmungsvoll, aber klar (wenig Dunst, helles Umgebungslicht -> nichts wird matschig).
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
			Brightness = 3,
			Ambient = Color3.fromRGB(95, 95, 105),
			OutdoorAmbient = Color3.fromRGB(150, 150, 160),
			ColorShift_Top = Color3.fromRGB(255, 250, 240),
			ExposureCompensation = 0,
		},
		-- kaum Dunst: weit sichtbar, satte Farben bis zum Horizont
		Atmosphere = {
			Density = 0.15,
			Color = Color3.fromRGB(199, 225, 255),
			Decay = Color3.fromRGB(110, 150, 220),
			Glare = 0,
			Haze = 0,
		},
		Color = { TintColor = Color3.new(1, 1, 1), Saturation = 0.12 },
		Clouds = { Cover = 0.5, Color = Color3.new(1, 1, 1) },
	},
	Night = {
		Lighting = {
			Brightness = 1.4,
			Ambient = Color3.fromRGB(60, 65, 105),
			OutdoorAmbient = Color3.fromRGB(105, 115, 170),
			ColorShift_Top = Color3.fromRGB(170, 190, 255),
			ExposureCompensation = 0.3,
		},
		Atmosphere = {
			Density = 0.25,
			Color = Color3.fromRGB(70, 85, 140),
			Decay = Color3.fromRGB(35, 40, 90),
			Glare = 0,
			Haze = 0.4,
		},
		Color = { TintColor = Color3.fromRGB(210, 222, 255), Saturation = 0.05 },
		Clouds = { Cover = 0.3, Color = Color3.fromRGB(85, 95, 135) },
	},
	Blood = {
		Lighting = {
			Brightness = 1.4,
			Ambient = Color3.fromRGB(110, 45, 50),
			OutdoorAmbient = Color3.fromRGB(170, 85, 85),
			ColorShift_Top = Color3.fromRGB(255, 120, 110),
			ExposureCompensation = 0.3,
		},
		Atmosphere = {
			Density = 0.26,
			Color = Color3.fromRGB(180, 55, 55),
			Decay = Color3.fromRGB(100, 15, 25),
			Glare = 0,
			Haze = 0.5,
		},
		Color = { TintColor = Color3.fromRGB(255, 190, 185), Saturation = 0.12 },
		Clouds = { Cover = 0.35, Color = Color3.fromRGB(150, 50, 55) },
	},
}

local lookName = "Day"
local running: { Tween } = {}

-- Diese Effekte bauen wir selbst -> alte/doppelte Versionen vorher entfernen (sonst addieren sie sich).
-- SunRaysEffect bauen wir nicht mehr, alte (z.B. aus Studio) fliegen trotzdem raus.
local OWN_CLASSES = { "Atmosphere", "Sky", "BloomEffect", "SunRaysEffect", "ColorCorrectionEffect" }

local function clearOld()
	for _, child in ipairs(Lighting:GetChildren()) do
		if table.find(OWN_CLASSES, child.ClassName) then
			child:Destroy()
		end
	end
end

-- Tag-Werte kommen aus LOOKS.Day (eine Quelle für Start und Sonnenaufgang)
local function setAll(target: Instance, props: { [string]: any })
	for key, value in pairs(props) do
		(target :: any)[key] = value
	end
end

local function applyLighting()
	Lighting.ClockTime = DAY_CLOCK -- Nachmittag: Sonne hoch, kurze Schatten
	Lighting.GeographicLatitude = 35
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 0.25 -- wenig Spiegelung: Plastik wirkt matt und bunt (Roblox-Look)
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.2 -- klare, kurze Schatten
	Lighting.ColorShift_Bottom = Color3.new(0, 0, 0)
	setAll(Lighting, LOOKS.Day.Lighting)
end

local function buildEffects()
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "MH_Atmosphere"
	atmosphere.Offset = 0.25
	setAll(atmosphere, LOOKS.Day.Atmosphere)
	atmosphere.Parent = Lighting

	local sky = Instance.new("Sky") -- Standard-Himmel von Roblox (blau mit Wolken)
	sky.Name = "MH_Sky"
	sky.SunAngularSize = 16
	sky.MoonAngularSize = 11
	sky.StarCount = 3000
	sky.CelestialBodiesShown = true
	sky.Parent = Lighting

	local bloom = Instance.new("BloomEffect") -- sehr schwach: nur die wenigen Neon-Teile glimmen etwas
	bloom.Name = "MH_Bloom"
	bloom.Intensity = 0.25
	bloom.Size = 18
	bloom.Threshold = 2
	bloom.Parent = Lighting

	-- (keine SunRaysEffect mehr: Sonnenstrahlen machen das Bild milchig)

	local colorCorrection = Instance.new("ColorCorrectionEffect") -- leicht knalligere Farben
	colorCorrection.Name = "MH_ColorCorrection"
	colorCorrection.Brightness = 0.02
	colorCorrection.Contrast = 0.05
	setAll(colorCorrection, LOOKS.Day.Color)
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
	clouds.Density = 0.6 -- weiße Schäfchenwolken, blauer Himmel bleibt sichtbar
	setAll(clouds, LOOKS.Day.Clouds)
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

-- Laternen der Basen (Neon-Würfel "LanternLamp" von BaseBuilder) bekommen ein Licht für die Nacht
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
