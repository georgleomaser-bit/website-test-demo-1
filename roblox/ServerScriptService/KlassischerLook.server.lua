--[[
	KlassischerLook  ·  Script  →  ServerScriptService

	Gibt deinem Spiel den typischen Roblox-Look:
	  • Licht: hell, kräftige Farben, klare Schatten – kein Dunst, kein Glanz
	  • Himmel: der Standard-Roblox-Himmel mit Sonne und Wolken
	  • Noppen: Studs oben und Löcher (Inlets) unten an allen Blöcken
	  • Baseplate: die grüne Noppen-Platte
	  • Avatare: klotzige Standard-Körper (Kleidung und Hüte bleiben)

	Alles kannst du unten bei EINSTELLUNGEN an- und ausschalten.
	Ein Teil soll keine Noppen bekommen? Gib ihm das Attribut "KeineNoppen" (Haken an).

	Das Script ändert nichts dauerhaft an deinem Place. Es wirkt, sobald das Spiel läuft
	(also nach "Play"). Weggeräumte Sachen (eigener Himmel, Dunst) landen in ServerStorage.
]]

local EINSTELLUNGEN = {
	Licht = true,
	Himmel = true,
	Noppen = true,
	GlattZuPlastik = true, -- Noppen sieht man nur auf Plastik: SmoothPlastic wird zu Plastic
	Baseplate = true, -- färbt die "Baseplate" um oder baut eine, wenn keine da ist
	BaseplateFarbe = BrickColor.new("Bright green"),
	KlotzigeAvatare = true,
	StandardGesicht = false, -- true = alle bekommen das klassische Lächeln
}

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

--------------------------------------------------------------------------------
-- Licht
--------------------------------------------------------------------------------

local function klassischesLicht()
	Lighting.LightingStyle = Enum.LightingStyle.Soft
	Lighting.Brightness = 2
	Lighting.ClockTime = 14
	Lighting.GeographicLatitude = 41.73
	Lighting.Ambient = Color3.fromRGB(70, 70, 70)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 140)
	Lighting.ColorShift_Top = Color3.new(0, 0, 0)
	Lighting.ColorShift_Bottom = Color3.new(0, 0, 0)
	Lighting.EnvironmentDiffuseScale = 0
	Lighting.EnvironmentSpecularScale = 0
	Lighting.ExposureCompensation = 0
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.2
	Lighting.FogStart = 0
	Lighting.FogEnd = 100000

	-- Bloom, Unschärfe, Farbfilter & Co. aus, Dunst weg
	for _, objekt in Lighting:GetChildren() do
		if objekt:IsA("PostEffect") then
			objekt.Enabled = false
		elseif objekt:IsA("Atmosphere") then
			objekt.Parent = ServerStorage
		end
	end
end

--------------------------------------------------------------------------------
-- Himmel
--------------------------------------------------------------------------------

local function klassischerHimmel()
	for _, objekt in Lighting:GetChildren() do
		if objekt:IsA("Sky") then
			objekt.Parent = ServerStorage
		end
	end

	-- Ein neuer Sky ohne eigene Bilder ist der Standard-Roblox-Himmel
	local himmel = Instance.new("Sky")
	himmel.Name = "KlassischerHimmel"
	himmel.Parent = Lighting
end

--------------------------------------------------------------------------------
-- Noppen
--------------------------------------------------------------------------------

-- Avatare, NPCs und was sie in der Hand halten bekommen keine Noppen
local function gehoertZuFigur(teil: Instance): boolean
	local modell = teil:FindFirstAncestorOfClass("Model")
	while modell do
		if modell:FindFirstChildOfClass("Humanoid") then
			return true
		end
		modell = modell:FindFirstAncestorOfClass("Model")
	end
	return false
end

local function noppenDran(objekt: Instance)
	if not objekt:IsA("Part") or objekt.Shape ~= Enum.PartType.Block then
		return
	end
	if objekt:GetAttribute("KeineNoppen") or gehoertZuFigur(objekt) then
		return
	end

	if EINSTELLUNGEN.GlattZuPlastik and objekt.Material == Enum.Material.SmoothPlastic then
		objekt.Material = Enum.Material.Plastic
	end
	objekt.TopSurface = Enum.SurfaceType.Studs
	objekt.BottomSurface = Enum.SurfaceType.Inlet
end

local function ueberallNoppen()
	for _, objekt in workspace:GetDescendants() do
		noppenDran(objekt)
	end
	-- Teile, die später dazukommen, auch
	workspace.DescendantAdded:Connect(noppenDran)
end

--------------------------------------------------------------------------------
-- Baseplate
--------------------------------------------------------------------------------

local function klassischeBaseplate()
	local gefunden = workspace:FindFirstChild("Baseplate")
	local platte: BasePart
	if gefunden and gefunden:IsA("BasePart") then
		platte = gefunden
	else
		platte = Instance.new("Part")
		platte.Name = "Baseplate"
		platte.Size = Vector3.new(512, 20, 512)
		platte.Position = Vector3.new(0, -10, 0)
		platte.Anchored = true
		platte.Locked = true
		platte.Parent = workspace
	end

	platte.BrickColor = EINSTELLUNGEN.BaseplateFarbe
	platte.Material = Enum.Material.Plastic
	if platte:IsA("Part") then
		platte.TopSurface = Enum.SurfaceType.Studs
		platte.BottomSurface = Enum.SurfaceType.Inlet
	end

	-- Das Gitter-Muster der neuen Studio-Vorlage ausblenden
	for _, kind in platte:GetChildren() do
		if kind:IsA("Decal") then
			kind.Transparency = 1
		end
	end
end

--------------------------------------------------------------------------------
-- Klotzige Avatare
--------------------------------------------------------------------------------

local function klotzigMachen(figur: Model)
	local humanoid = figur:FindFirstChildOfClass("Humanoid")
	if not humanoid or figur:GetAttribute("Klotzig") then
		return
	end
	figur:SetAttribute("Klotzig", true)

	local ok, fehler = pcall(function()
		local beschreibung = humanoid:GetAppliedDescription()
		-- 0 heißt: Standard-Klotzteil statt Avatar-Paket
		beschreibung.Head = 0
		beschreibung.Torso = 0
		beschreibung.LeftArm = 0
		beschreibung.RightArm = 0
		beschreibung.LeftLeg = 0
		beschreibung.RightLeg = 0
		beschreibung.BodyTypeScale = 0
		beschreibung.ProportionScale = 0
		beschreibung.HeightScale = 1
		beschreibung.WidthScale = 1
		beschreibung.DepthScale = 1
		beschreibung.HeadScale = 1
		if EINSTELLUNGEN.StandardGesicht then
			beschreibung.Face = 0
		end
		humanoid:ApplyDescriptionAsync(beschreibung)
	end)
	if not ok then
		warn("[KlassischerLook] Avatar konnte nicht klotzig gemacht werden:", fehler)
	end
end

local function spielerBeobachten(spieler: Player)
	spieler.CharacterAppearanceLoaded:Connect(klotzigMachen)
	if spieler.Character and spieler:HasAppearanceLoaded() then
		task.spawn(klotzigMachen, spieler.Character)
	end
end

--------------------------------------------------------------------------------
-- Los geht's
--------------------------------------------------------------------------------

if EINSTELLUNGEN.Licht then
	klassischesLicht()
end
if EINSTELLUNGEN.Himmel then
	klassischerHimmel()
end
if EINSTELLUNGEN.Baseplate then
	klassischeBaseplate()
end
if EINSTELLUNGEN.Noppen then
	ueberallNoppen()
end
if EINSTELLUNGEN.KlotzigeAvatare then
	Players.PlayerAdded:Connect(spielerBeobachten)
	for _, spieler in Players:GetPlayers() do
		spielerBeobachten(spieler)
	end
end
