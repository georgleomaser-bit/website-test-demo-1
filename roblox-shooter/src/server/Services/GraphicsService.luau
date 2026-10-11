-- =====================================================================
--  CLUTCH CLASH – Lobby-Licht (Server/Services/GraphicsService)
--  Besitzer: WP2 (Welt). Vertrag: DESIGN.md A4 (Licht), B8.2 (Stimmung "Day"), C5.3.
--  Basis: Meteor-Heist-GraphicsService, gekürzt (REUSE §1.3): clearOld, applyLighting,
--  buildEffects, buildClouds. Instanz-Namen mit Präfix CC_.
--
--  Ein Server hostet Lobby + mehrere Arenen, Lighting ist aber global: der Server setzt
--  EINMAL in Init den Lobby-Look (Config.Maps.LobbyMood = "Day") und ändert Lighting danach
--  NIE wieder. Match-Stimmungen setzt der Client lokal (WP2 ArenaLook, eigene CC_Mood*-Instanzen).
--  Lighting.Technology = ShadowMap steht in default.project.json (Skripte können es nicht ändern).
--
--  Öffentliche API (C5.3):
--    GraphicsService.ApplyLobbyLook()   einmal in Init; weitere Aufrufe werden ignoriert (warn)
-- =====================================================================

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local GraphicsService = {}

local applied = false

-- Diese Effekte bauen wir selbst -> alte/doppelte Versionen vorher entfernen (sonst addieren sie sich)
local OWN_CLASSES = { "Atmosphere", "Sky", "BloomEffect", "SunRaysEffect", "ColorCorrectionEffect" }

-- Fallback, falls Config.Maps fehlt (Werte = B8.2 "Day")
local FALLBACK_DAY = {
	ClockTime = 14,
	Ambient = Color3.fromRGB(140, 140, 150),
	OutdoorAmbient = Color3.fromRGB(150, 150, 160),
	Atmosphere = {
		Density = 0.32,
		Haze = 1.0,
		Color = Color3.fromRGB(199, 210, 230),
		Decay = Color3.fromRGB(106, 112, 125),
		Glare = 0,
		Offset = 0.25,
	},
	Bloom = { Intensity = 0.5, Size = 24, Threshold = 1.6 },
	ColorCorrection = { Saturation = 0.15, Contrast = 0.05, Brightness = 0, TintColor = Color3.new(1, 1, 1) },
}

local function lobbyMood(): any
	local maps = Config.Maps
	local moods = maps and maps.Moods
	local key = (maps and maps.LobbyMood) or "Day"
	local mood = moods and moods[key]
	if type(mood) ~= "table" then
		warn("[GraphicsService] Stimmung '" .. tostring(key) .. "' fehlt in Config.Maps.Moods – nehme Standard")
		return FALLBACK_DAY
	end
	return mood
end

local function clearOld()
	for _, child in ipairs(Lighting:GetChildren()) do
		if table.find(OWN_CLASSES, child.ClassName) then
			child:Destroy()
		end
	end
end

local function applyLighting(mood: any)
	Lighting.ClockTime = mood.ClockTime
	Lighting.Ambient = mood.Ambient
	Lighting.OutdoorAmbient = mood.OutdoorAmbient
	Lighting.Brightness = 2.6 -- helles Roblox-Plastik-Licht
	Lighting.GeographicLatitude = 35
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 0.25 -- wenig Spiegelung: Plastik wirkt matt und bunt
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.2
	Lighting.ColorShift_Top = Color3.fromRGB(255, 250, 240)
	Lighting.ColorShift_Bottom = Color3.new(0, 0, 0)
	Lighting.ExposureCompensation = 0
end

local function buildEffects(mood: any)
	local atmo = mood.Atmosphere
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "CC_Atmosphere"
	atmosphere.Density = atmo.Density -- ≥ 0.32: fremde Welten verschwinden im Dunst (B9.4)
	atmosphere.Haze = atmo.Haze
	atmosphere.Color = atmo.Color
	atmosphere.Decay = atmo.Decay
	atmosphere.Glare = atmo.Glare
	atmosphere.Offset = atmo.Offset
	atmosphere.Parent = Lighting

	local sky = Instance.new("Sky") -- Standard-Himmel von Roblox (blau, Sonne, nachts Sterne)
	sky.Name = "CC_Sky"
	sky.SunAngularSize = 16
	sky.MoonAngularSize = 11
	sky.StarCount = 3000
	sky.CelestialBodiesShown = true
	sky.Parent = Lighting

	local bloomDef = mood.Bloom
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "CC_Bloom"
	bloom.Intensity = bloomDef.Intensity
	bloom.Size = bloomDef.Size
	bloom.Threshold = bloomDef.Threshold
	bloom.Parent = Lighting

	local ccDef = mood.ColorCorrection
	local colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "CC_ColorCorrection"
	colorCorrection.Saturation = ccDef.Saturation
	colorCorrection.Contrast = ccDef.Contrast
	colorCorrection.Brightness = ccDef.Brightness
	colorCorrection.TintColor = ccDef.TintColor
	colorCorrection.Parent = Lighting
end

local function buildClouds()
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if not terrain then
		return
	end
	local clouds = terrain:FindFirstChildOfClass("Clouds")
	if not clouds then
		local created = Instance.new("Clouds")
		created.Name = "CC_Clouds"
		created.Parent = terrain
		clouds = created
	end
	if clouds then
		clouds.Cover = 0.5
		clouds.Density = 0.6 -- weiße Schäfchenwolken, blauer Himmel bleibt sichtbar
		clouds.Color = Color3.new(1, 1, 1)
		clouds.Enabled = true
	end
end

-- Einmal in Init: Lobby-Look "Day". Danach Lighting nie mehr serverseitig ändern.
function GraphicsService.ApplyLobbyLook()
	if applied then
		warn("[GraphicsService] ApplyLobbyLook wurde schon ausgeführt – Lighting bleibt unverändert")
		return
	end
	applied = true
	local mood = lobbyMood()
	clearOld()
	applyLighting(mood)
	buildEffects(mood)
	buildClouds()
end

function GraphicsService.Init(_services: any)
	GraphicsService.ApplyLobbyLook()
end

function GraphicsService.Start() end

return GraphicsService
