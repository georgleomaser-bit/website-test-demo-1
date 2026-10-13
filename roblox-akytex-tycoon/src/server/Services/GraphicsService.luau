-- =====================================================================
--  AKYTEX TYCOON – Future-Licht-Grundausstattung (Server/Services/GraphicsService)
--  Besitzer: WP7 (Stadt, Grafik, Fahrzeuge). Vertrag: DESIGN.md §C5.6 (GraphicsService.Apply einmal in Init, danach nie
--  wieder serverseitig), §A4 (Licht-Werte), REUSE §1.3 PATTERN (clearOld eigener Instanzen – kein doppeltes Bloom).
--  Lighting.Technology = Future steht in default.project.json (RobloxScriptSecurity – Skripte setzen es NICHT).
--  Der Server legt den Tag-Startwert an; Tag/Nacht (= Börsentag), Markt-Wetter, Crash/Rally und Tiefenschärfe rechnet
--  jeder Client selbst (Client/Modules/WorldLook) – alle synchron über workspace:GetServerTimeNow().
--
--  Öffentliche API (§C5.6):
--    GraphicsService.Apply()      einmal in Init (weitere Aufrufe ändern nichts)
--  Instanz-Namen: "AT_Atmosphere", "AT_Sky", "AT_Bloom", "AT_SunRays", "AT_ColorCorrection", "AT_Clouds".
-- =====================================================================

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any
local Clock = require(Shared:WaitForChild("Clock"))

local GraphicsService = {}

local PREFIX = "[GraphicsService] "
-- diese Effekte bauen wir selbst -> alte/doppelte Versionen vorher entfernen (sonst addieren sie sich)
local OWN_CLASSES = {
	"Atmosphere",
	"Sky",
	"BloomEffect",
	"SunRaysEffect",
	"ColorCorrectionEffect",
	"DepthOfFieldEffect",
}

local applied = false

-- Rückfall, falls Config.City.Look fehlt (gleiche Werte wie §A4)
local FALLBACK = {
	Day = {
		Ambient = Color3.fromRGB(92, 98, 112),
		OutdoorAmbient = Color3.fromRGB(128, 136, 152),
		Brightness = 2.4,
		ColorShiftTop = Color3.fromRGB(255, 246, 232),
		ExposureCompensation = 0,
		Atmosphere = {
			Density = 0.30,
			Haze = 1.2,
			Color = Color3.fromRGB(199, 214, 255),
			Decay = Color3.fromRGB(106, 122, 154),
			Glare = 0.2,
			Offset = 0.25,
		},
	},
	Bloom = { Intensity = 0.55, Size = 24, Threshold = 1.5 },
	SunRays = { Intensity = 0.04, Spread = 0.6 },
	ColorCorrection = { Contrast = 0.08, Saturation = 0.05, Brightness = 0, Tint = Color3.new(1, 1, 1) },
	Sky = { StarCount = 3000, SunAngularSize = 12, MoonAngularSize = 9 },
	Shadows = { Softness = 0.15, Latitude = 41 },
}

local function look(): any
	local city = Config.City
	local value = type(city) == "table" and city.Look or nil
	if type(value) ~= "table" or type(value.Day) ~= "table" then
		warn(PREFIX .. "Config.City.Look fehlt – nehme Standardwerte")
		return FALLBACK
	end
	return value
end

local function clearOld()
	for _, child in ipairs(Lighting:GetChildren()) do
		if table.find(OWN_CLASSES, child.ClassName) then
			child:Destroy()
		end
	end
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		for _, child in ipairs(terrain:GetChildren()) do
			if child:IsA("Clouds") then
				child:Destroy()
			end
		end
	end
end

local function applyLighting(values: any)
	local day = values.Day
	local shadows = values.Shadows or FALLBACK.Shadows
	Lighting.Ambient = day.Ambient
	Lighting.OutdoorAmbient = day.OutdoorAmbient
	Lighting.Brightness = day.Brightness
	Lighting.ColorShift_Top = day.ColorShiftTop
	Lighting.ColorShift_Bottom = Color3.new(0, 0, 0)
	Lighting.ExposureCompensation = day.ExposureCompensation or 0
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = shadows.Softness
	Lighting.GeographicLatitude = shadows.Latitude
	-- Startwert = aktuelle Tageszeit des Börsentags (Clients übernehmen sofort selbst)
	local ok, clockTime = pcall(function(): number
		return Clock.ClockTime(Clock.Now() - Clock.EPOCH)
	end)
	Lighting.ClockTime = if ok and type(clockTime) == "number" then clockTime else 9
end

local function buildEffects(values: any)
	local atmo = values.Day.Atmosphere
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "AT_Atmosphere"
	atmosphere.Density = atmo.Density
	atmosphere.Haze = atmo.Haze
	atmosphere.Color = atmo.Color
	atmosphere.Decay = atmo.Decay
	atmosphere.Glare = atmo.Glare
	atmosphere.Offset = atmo.Offset
	atmosphere.Parent = Lighting

	local skyDef = values.Sky or FALLBACK.Sky
	local sky = Instance.new("Sky") -- Standard-Himmel (eingebaute Texturen, ASSETS.md §6), nachts Sterne
	sky.Name = "AT_Sky"
	sky.StarCount = skyDef.StarCount
	sky.SunAngularSize = skyDef.SunAngularSize
	sky.MoonAngularSize = skyDef.MoonAngularSize
	sky.CelestialBodiesShown = true
	sky.Parent = Lighting

	local bloomDef = values.Bloom or FALLBACK.Bloom
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "AT_Bloom"
	bloom.Intensity = bloomDef.Intensity
	bloom.Size = bloomDef.Size
	bloom.Threshold = bloomDef.Threshold
	bloom.Parent = Lighting

	local raysDef = values.SunRays or FALLBACK.SunRays
	local rays = Instance.new("SunRaysEffect")
	rays.Name = "AT_SunRays"
	rays.Intensity = raysDef.Intensity
	rays.Spread = raysDef.Spread
	rays.Parent = Lighting

	local ccDef = values.ColorCorrection or FALLBACK.ColorCorrection
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "AT_ColorCorrection"
	cc.Contrast = ccDef.Contrast
	cc.Saturation = ccDef.Saturation
	cc.Brightness = ccDef.Brightness
	cc.TintColor = ccDef.Tint
	cc.Parent = Lighting
end

local function buildClouds()
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if not terrain then
		return
	end
	local weather = Config.City and Config.City.Weather
	local clouds = Instance.new("Clouds")
	clouds.Name = "AT_Clouds"
	clouds.Cover = if type(weather) == "table" then weather.Cover.Clear else 0.2
	clouds.Density = if type(weather) == "table" then weather.Density.Clear else 0.5
	clouds.Color = Color3.new(1, 1, 1)
	clouds.Enabled = true
	clouds.Parent = terrain
end

function GraphicsService.Apply()
	if applied then
		return -- nur einmal (§C5.6): danach ändert der Server Lighting nie wieder
	end
	applied = true
	local values = look()
	clearOld()
	local ok, err = pcall(function()
		applyLighting(values)
		buildEffects(values)
		buildClouds()
	end)
	if not ok then
		warn(PREFIX .. "Licht konnte nicht vollständig gesetzt werden: " .. tostring(err))
	end
end

function GraphicsService.Init(_services: any)
	GraphicsService.Apply()
end

function GraphicsService.Start() end

return GraphicsService
