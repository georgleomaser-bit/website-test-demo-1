--[[
	Kleine Bau-Helfer für Parts, Schilder und Lichter.
	Alles im klassischen Roblox-Stil: Blöcke, Standardfarben, Standardmaterialien.
]]

local Build = {}

-- Klassischer Roblox-Look: Noppen oben, Löcher unten
local TOP = Enum.SurfaceType.Studs
local BOTTOM = Enum.SurfaceType.Inlet

-- Standard-Roblox-Schrift für Schilder
Build.FONT = Enum.Font.SourceSansBold

-- Standard-Roblox-Farbe über den BrickColor-Namen, z. B. C("Bright yellow")
function Build.C(name: string): Color3
	return BrickColor.new(name :: any).Color
end

local ORDER = { "Shape", "Size", "CFrame" }
local SKIP = { ClassName = true, Shape = true, Size = true, CFrame = true, Parent = true }

function Build.Part(parent: Instance?, props): BasePart
	local part = Instance.new(props.ClassName or "Part")
	part.Anchored = true
	part.TopSurface = TOP
	part.BottomSurface = BOTTOM
	part.Material = Enum.Material.Plastic
	for _, key in ipairs(ORDER) do
		if props[key] ~= nil then
			part[key] = props[key]
		end
	end
	for key, value in pairs(props) do
		if not SKIP[key] then
			part[key] = value
		end
	end
	part.Parent = parent
	return part
end

-- Quader
function Build.Block(parent, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, extra)
	local props = {
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material or Enum.Material.Plastic,
	}
	if extra then
		for k, v in pairs(extra) do
			props[k] = v
		end
	end
	return Build.Part(parent, props)
end

-- Stehender Zylinder (Achse nach oben). cf = Mittelpunkt
function Build.Cylinder(parent, name: string, height: number, diameter: number, cf: CFrame, color: Color3, material: Enum.Material?, extra)
	local props = {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = cf * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material or Enum.Material.Plastic,
	}
	if extra then
		for k, v in pairs(extra) do
			props[k] = v
		end
	end
	return Build.Part(parent, props)
end

-- Liegender Zylinder entlang der lokalen X-Achse von cf
function Build.CylinderX(parent, name: string, length: number, diameter: number, cf: CFrame, color: Color3, material: Enum.Material?, extra)
	local props = {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, diameter, diameter),
		CFrame = cf,
		Color = color,
		Material = material or Enum.Material.Plastic,
	}
	if extra then
		for k, v in pairs(extra) do
			props[k] = v
		end
	end
	return Build.Part(parent, props)
end

function Build.Ball(parent, name: string, diameter: number, cf: CFrame, color: Color3, material: Enum.Material?, extra)
	local props = {
		Name = name,
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(diameter, diameter, diameter),
		CFrame = cf,
		Color = color,
		Material = material or Enum.Material.Plastic,
	}
	if extra then
		for k, v in pairs(extra) do
			props[k] = v
		end
	end
	return Build.Part(parent, props)
end

function Build.Wedge(parent, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?)
	return Build.Part(parent, {
		ClassName = "WedgePart",
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material or Enum.Material.Plastic,
	})
end

-- Zitronenform: Block mit Kugel-Mesh (Ellipsoid)
function Build.Egg(parent, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, extra)
	local part = Build.Block(parent, name, size, cf, color, material, extra)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

function Build.Model(parent: Instance?, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

function Build.Folder(parent: Instance?, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

function Build.NoCollide(part: BasePart): BasePart
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	return part
end

function Build.Light(part: BasePart, color: Color3, range: number, brightness: number?)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness or 1.5
	light.Shadows = false
	light.Parent = part
	return light
end

function Build.Sparkles(part: BasePart, color: Color3, rate: number?)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Sparkles"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Rate = rate or 8
	emitter.Speed = NumberRange.new(1, 3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = part
	return emitter
end

-- Text-Schild auf einer Seite eines Parts (dicke weiße Schrift mit schwarzem Rand)
function Build.Sign(part: BasePart, face: Enum.NormalId, text: string, opts)
	opts = opts or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = opts.Name or "SignGui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = opts.PixelsPerStud or 30
	gui.LightInfluence = 0
	gui.Brightness = 1.2
	gui.Parent = part

	if opts.Background then
		local bg = Instance.new("Frame")
		bg.Name = "Background"
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundColor3 = opts.Background
		bg.BorderSizePixel = 0
		bg.Parent = gui
	end

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(0.92, 0.86)
	label.Position = UDim2.fromScale(0.04, 0.07)
	label.BackgroundTransparency = 1
	label.FontFace = Font.fromEnum(opts.Font or Build.FONT)
	label.Text = text
	label.TextScaled = true
	label.TextWrapped = true
	label.RichText = opts.RichText or false
	label.TextColor3 = opts.TextColor or Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = opts.NoStroke and 1 or 0
	label.Parent = gui
	return gui, label
end

-- Schwebendes Namensschild über einem Part
function Build.Billboard(part: BasePart, text: string, opts)
	opts = opts or {}
	local gui = Instance.new("BillboardGui")
	gui.Name = opts.Name or "Billboard"
	gui.Size = opts.Size or UDim2.fromScale(10, 2.5)
	gui.StudsOffset = opts.Offset or Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = opts.AlwaysOnTop or false
	gui.MaxDistance = opts.MaxDistance or 150
	gui.LightInfluence = 0
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = Font.fromEnum(opts.Font or Build.FONT)
	label.Text = text
	label.TextScaled = true
	label.RichText = opts.RichText or false
	label.TextColor3 = opts.TextColor or Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	return gui, label
end

function Build.Prompt(part: BasePart, actionText: string, objectText: string, opts)
	opts = opts or {}
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = opts.Name or "Prompt"
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = opts.HoldDuration or 0
	prompt.MaxActivationDistance = opts.Distance or 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = opts.KeyCode or Enum.KeyCode.E
	prompt.Parent = part
	return prompt
end

-- Mischt eine Farbe Richtung Grau/Schwarz/Weiß
function Build.Shade(color: Color3, amount: number, target: Color3?): Color3
	return color:Lerp(target or Color3.new(0, 0, 0), amount)
end

return Build
