-- Grafik: helles, sattes Sonnenlicht wie in Simulator-Spielen.
-- Licht, Atmosphäre, Bloom (dezent), Sonnenstrahlen, Farbkorrektur, Himmel und Wolken.
-- Hinweis: Lighting.Technology = "Future" und Workspace.StreamingEnabled = false stehen in
-- default.project.json – Technology kann ein Script im laufenden Spiel nicht umstellen.
-- Wird in Main.server.luau VOR PlotService geladen.

local Lighting = game:GetService("Lighting")

local GraphicsService = {}

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

function GraphicsService.Init(_services)
	clearOld()
	applyLighting()
	buildEffects()
	buildClouds()
end

return GraphicsService
