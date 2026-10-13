-- =====================================================================
--  AKYTEX TYCOON – Stadt-Baukasten: Specs -> Instanzen (Server/World/CityKit)
--  Besitzer: WP7 (Stadt, Grafik, Fahrzeuge). Vertrag: DESIGN.md §A4 (Materialien, Future-Licht, Neon-Streifen, LED-Wände
--  als SurfaceGui), §B3 (Streaming-Modi je Model), §C14.3 (Asset-Plätze: gesetzte Id ersetzt das Code-Rezept).
--  Baut genau ein Spec (aus CityLayout) zu einem Teil (+ Licht, Schild, Prompt, Partikel, Mesh) – nie yieldend, damit
--  CityService viele davon pro Frame bauen kann. Lichter werden AUS angelegt (Attribut "Budget"): WorldLook schaltet
--  clientseitig nur die nächsten N je Grafikstufe ein (Licht-Budget §C16).
--
--  Öffentliche API (nur WP7):
--    CityKit.GroupModel(group, cityFolder): Model    Model der Gruppe (Streaming-Modus, LOD) – einmal je Gruppe
--    CityKit.Build(spec, model, group): Instance?    ein Spec bauen; Rückgabe = Teil bzw. Ausstellungs-Model
--    CityKit.PlaceAssets(group, model): { [string]: boolean }   gesetzte Asset-Plätze der Gruppe platzieren
--    CityKit.CountParts(root): number                BaseParts unterhalb root (Teilebudget)
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any
local Lang = require(Shared:WaitForChild("Lang")) :: any
local AssetSlot = require(Shared:WaitForChild("AssetSlot")) :: any
local VehicleModels = require(Shared:WaitForChild("VehicleModels")) :: any

local CityKit = {}

local FONT_DISPLAY = Font.new("rbxasset://fonts/families/BuilderExtended.json", Enum.FontWeight.Bold)
local FONT_BODY = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
local SIGN_PPS = 24 -- Pixel je Stud auf Schildern (große Schilder bleiben unter 2048 px)
local MAX_CANVAS = 2000

local subModels: { [any]: { [string]: Model } } = {} -- Gruppe -> Unter-Model-Name -> Model
local assetPlaced: { [any]: { [string]: boolean } } = {} -- Gruppe -> Asset-Platz -> gesetzt

local function modeOf(name: string): Enum.ModelStreamingMode
	if name == "Persistent" then
		return Enum.ModelStreamingMode.Persistent
	elseif name == "Atomic" then
		return Enum.ModelStreamingMode.Atomic
	end
	return Enum.ModelStreamingMode.Default
end

function CityKit.GroupModel(group: any, cityFolder: Instance): Model
	local district = cityFolder:FindFirstChild(group.District)
	if not district then
		local folder = Instance.new("Folder")
		folder.Name = group.District
		folder.Parent = cityFolder
		district = folder
	end
	local model = Instance.new("Model")
	model.Name = group.Key
	-- Streaming-Modus VOR dem Einhängen setzen (§B3)
	pcall(function()
		model.ModelStreamingMode = modeOf(group.Mode)
	end)
	if group.Lod then
		-- Skyline bleibt aus der Ferne sichtbar (in Studio verifizieren, §B3)
		pcall(function()
			(model :: any).LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh
		end)
	end
	model:SetAttribute("District", group.District)
	model.Parent = district
	subModels[group] = {}
	assetPlaced[group] = {}
	return model
end

local function subModel(group: any, model: Model, name: string, attrs: { [string]: any }?): Model
	local subs = subModels[group]
	if not subs then
		subs = {}
		subModels[group] = subs
	end
	local existing = subs[name]
	if existing and existing.Parent then
		if attrs then
			for key, value in pairs(attrs) do
				existing:SetAttribute(key, value)
			end
		end
		return existing
	end
	local sub = Instance.new("Model")
	sub.Name = name
	if attrs then
		for key, value in pairs(attrs) do
			sub:SetAttribute(key, value)
		end
	end
	sub.Parent = model
	subs[name] = sub
	return sub
end

-- ---------------------------------------------------------------------
-- DEKORATIONEN
-- ---------------------------------------------------------------------
local function addLight(part: BasePart, spec: any)
	local light: any
	if spec.Kind == "Spot" then
		local spot = Instance.new("SpotLight")
		spot.Angle = spec.Angle or 45
		spot.Face = spec.Face or Enum.NormalId.Front
		light = spot
	elseif spec.Kind == "Surface" then
		local surface = Instance.new("SurfaceLight")
		surface.Angle = spec.Angle or 90
		surface.Face = spec.Face or Enum.NormalId.Bottom
		light = surface
	else
		light = Instance.new("PointLight")
	end
	light.Range = math.clamp(spec.Range or 16, 0, 60)
	light.Brightness = spec.Brightness or 1
	light.Color = spec.Color or Color3.new(1, 1, 1)
	light.Shadows = spec.Shadows == true
	light.Enabled = false -- WorldLook schaltet im Budget ein
	if part:GetAttribute("ShopSpot") == nil then
		light:SetAttribute("Budget", true)
		if spec.NightOnly then
			light:SetAttribute("NightOnly", true)
		end
	end
	light.Parent = part
end

local function addGui(part: BasePart, spec: any)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = spec.Face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	local size = part.Size
	local longest = math.max(size.X, size.Y, size.Z)
	gui.PixelsPerStud = math.min(SIGN_PPS, MAX_CANVAS / math.max(1, longest))
	gui.LightInfluence = 0
	gui.Brightness = 2.2
	gui.MaxDistance = spec.MaxDistance or 600
	gui.ClipsDescendants = true
	gui.ResetOnSpawn = false
	local holder = Instance.new("Frame")
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundColor3 = spec.Background or Color3.fromRGB(11, 15, 23)
	holder.BackgroundTransparency = if spec.Background then 0 else 1
	holder.BorderSizePixel = 0
	holder.Parent = gui
	local main = Instance.new("TextLabel")
	main.Name = "Text"
	main.BackgroundTransparency = 1
	main.Size = if spec.Sub then UDim2.fromScale(0.92, 0.6) else UDim2.fromScale(0.94, 0.8)
	main.Position = if spec.Sub then UDim2.fromScale(0.04, 0.06) else UDim2.fromScale(0.03, 0.1)
	main.FontFace = if spec.Display == false then FONT_BODY else FONT_DISPLAY
	main.Text = spec.Text
	main.TextColor3 = spec.Color
	main.TextScaled = true
	main.Parent = holder
	if spec.Sub then
		local sub = Instance.new("TextLabel")
		sub.Name = "Sub"
		sub.BackgroundTransparency = 1
		sub.Size = UDim2.fromScale(0.92, 0.28)
		sub.Position = UDim2.fromScale(0.04, 0.68)
		sub.FontFace = FONT_BODY
		sub.Text = spec.Sub
		sub.TextColor3 = spec.SubColor or Color3.fromRGB(230, 236, 245)
		sub.TextScaled = true
		sub.Parent = holder
	end
	gui.Parent = part
end

local function addPrompt(part: BasePart, spec: any)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Prompt"
	-- Startwert Englisch; WorldLook übersetzt clientseitig (Attribute TextKey/ObjectKey)
	prompt.ActionText = Lang.T("en", spec.TextKey)
	prompt.ObjectText = if spec.ObjectKey then Lang.T("en", spec.ObjectKey) else ""
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = spec.Hold or 0
	prompt.MaxActivationDistance = spec.Distance or 10
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OneGlobally
	prompt:SetAttribute("TextKey", spec.TextKey)
	if spec.ObjectKey then
		prompt:SetAttribute("ObjectKey", spec.ObjectKey)
	end
	if spec.Window then
		prompt:SetAttribute("Window", spec.Window) -- UI-Kit öffnet das registrierte Fenster (§C7.3)
	end
	if spec.Tab then
		prompt:SetAttribute("Tab", spec.Tab)
	end
	if spec.Action then
		prompt:SetAttribute("Action", spec.Action) -- serverseitige Aktion (CityService)
	end
	prompt.Parent = part
end

local function addEmitter(part: BasePart, spec: any)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = spec.Texture
	emitter.Rate = spec.Rate
	emitter.Lifetime = spec.Lifetime
	emitter.Speed = spec.Speed
	emitter.Size = spec.Size
	emitter.Color = spec.Color
	if spec.Transparency then
		emitter.Transparency = spec.Transparency
	end
	emitter.LightEmission = spec.LightEmission or 0
	emitter.SpreadAngle = spec.Spread or Vector2.zero
	emitter.Acceleration = spec.Acceleration or Vector3.zero
	emitter.EmissionDirection = spec.Face or Enum.NormalId.Top
	emitter.Parent = part
end

-- ---------------------------------------------------------------------
-- BAUEN
-- ---------------------------------------------------------------------
local function buildCar(spec: any, parent: Instance): Instance?
	local ok, model = pcall(VehicleModels.Build, spec.Car)
	if not ok or typeof(model) ~= "Instance" then
		warn("[CityKit] Ausstellungsauto " .. tostring(spec.Car) .. ": " .. tostring(model))
		return nil
	end
	local car = model :: Model
	car.Name = "Display_" .. tostring(spec.Car)
	car:PivotTo(spec.CFrame)
	for _, part in ipairs(car:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			if part:IsA("VehicleSeat") then
				part.Disabled = true -- Ausstellungsstück: niemand setzt sich hinein
			end
		end
	end
	car:SetAttribute("Display", true)
	car.Parent = parent
	return car
end

function CityKit.Build(spec: any, model: Model, group: any): Instance?
	if spec.Asset then
		local placed = assetPlaced[group]
		if placed and placed[spec.Asset] then
			return nil -- Asset-Mesh ersetzt das Rezept
		end
	end
	local parent: Instance = model
	if spec.Sub then
		parent = subModel(group, model, spec.Sub, spec.SubAttrs)
	end
	if spec.Car then
		return buildCar(spec, parent)
	end
	local part: BasePart
	if spec.Class == "WedgePart" then
		part = Instance.new("WedgePart")
	elseif spec.Class == "Seat" then
		local seat = Instance.new("Seat")
		part = seat
	elseif spec.Class == "SpawnLocation" then
		local spawn = Instance.new("SpawnLocation")
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Enabled = true
		spawn.AllowTeamChangeOnTouch = false
		part = spawn
	else
		local p = Instance.new("Part")
		p.Shape = spec.Shape or Enum.PartType.Block
		part = p
	end
	part.Name = spec.Name
	part.Size = Vector3.new(math.max(0.05, spec.Size.X), math.max(0.05, spec.Size.Y), math.max(0.05, spec.Size.Z))
	part.CFrame = spec.CFrame
	part.Color = spec.Color
	part.Material = spec.Material
	part.Transparency = spec.Transparency or 0
	part.Reflectance = spec.Reflectance or 0
	part.Anchored = true
	local collide = spec.Collide ~= false
	part.CanCollide = collide
	part.CanQuery = collide or spec.Prompt ~= nil
	part.CanTouch = spec.Class == "Seat" -- Hocker: Hinsetzen durch Berühren
	part.CastShadow = spec.Shadow ~= false and part.Transparency < 0.9
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if spec.Attrs then
		for key, value in pairs(spec.Attrs) do
			part:SetAttribute(key, value)
		end
	end
	if spec.Mesh then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = spec.Mesh.Type
		mesh.Scale = spec.Mesh.Scale
		mesh.Parent = part
	end
	if spec.Light then
		addLight(part, spec.Light)
	end
	if spec.Gui then
		addGui(part, spec.Gui)
	end
	if spec.Prompt then
		addPrompt(part, spec.Prompt)
	end
	if spec.Emitter then
		addEmitter(part, spec.Emitter)
	end
	if parent ~= model and parent:IsA("Model") and #parent:GetChildren() == 0 then
		-- Drehpunkt eines Untermodells = Mitte seines ersten Teils (Drehteller/Vitrine/Leuchtturm), nur Verschiebung
		parent.WorldPivot = CFrame.new(part.Position)
	end
	part.Parent = parent
	return part
end

-- Gesetzte Asset-Plätze (Config.City.Assets) der Gruppe als Mesh platzieren; deren Rezept-Specs entfallen dann
function CityKit.PlaceAssets(group: any, model: Model): { [string]: boolean }
	local placed = assetPlaced[group] or {}
	assetPlaced[group] = placed
	local assets = Config.City and Config.City.Assets
	if type(assets) ~= "table" then
		return placed
	end
	for key, cf in pairs(group.AssetCFrames) do
		local slot = assets[key]
		if slot and AssetSlot.IsSet(slot) and not placed[key] then
			local ok, result = pcall(AssetSlot.Mesh, AssetSlot.KeyOf("City", key), slot, function(): Instance
				local empty = Instance.new("Model")
				empty.Name = "Recipe"
				return empty
			end)
			if ok and typeof(result) == "Instance" and result.Name ~= "Recipe" then
				local inst = result :: Instance
				if inst:IsA("Model") then
					inst:PivotTo(cf * inst:GetPivot())
				elseif inst:IsA("BasePart") then
					inst.CFrame = cf * inst.CFrame
				end
				for _, part in ipairs(inst:GetDescendants()) do
					if part:IsA("BasePart") then
						part.Anchored = true
					end
				end
				inst.Name = "Asset_" .. key
				inst.Parent = model
				placed[key] = true
			elseif ok and typeof(result) == "Instance" then
				(result :: Instance):Destroy()
			end
		end
	end
	return placed
end

function CityKit.CountParts(root: Instance): number
	local n = 0
	for _, inst in ipairs(root:GetDescendants()) do
		if inst:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

return CityKit
