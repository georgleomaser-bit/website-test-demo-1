-- Eier-Raub – Server
-- Baut die komplette Map (inkl. Design und Licht), verwaltet Basen, Laufband,
-- Kaufen, Klauen, Sperren, Einkommen, Speichern und das Admin-Panel.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage:WaitForChild("EierRaub"):WaitForChild("Config"))

local rng = Random.new()

local GREEN = Color3.fromRGB(90, 230, 120)
local RED = Color3.fromRGB(255, 90, 90)
local YELLOW = Color3.fromRGB(255, 215, 70)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local FONT = Enum.Font.FredokaOne

---------------------------------------------------------------------
-- Remotes
---------------------------------------------------------------------
local oldRemotes = ReplicatedStorage:FindFirstChild("EierRaubRemotes")
if oldRemotes then
	oldRemotes:Destroy()
end
local remotes = Instance.new("Folder")
remotes.Name = "EierRaubRemotes"

local function remote(class, name)
	local r = Instance.new(class)
	r.Name = name
	r.Parent = remotes
	return r
end

local notifyEvent = remote("RemoteEvent", "Notify") -- (text, color)
local announceEvent = remote("RemoteEvent", "Announce") -- (text, absender)
local effectEvent = remote("RemoteEvent", "Effect") -- (name)
local adminFunction = remote("RemoteFunction", "Admin") -- (aktion, args) -> ok, nachricht, daten
remotes.Parent = ReplicatedStorage

local function notify(plr: Player?, text: string, color: Color3?)
	if plr and plr.Parent then
		notifyEvent:FireClient(plr, text, color or WHITE)
	end
end

local function effect(plr: Player?, name: string)
	if plr and plr.Parent then
		effectEvent:FireClient(plr, name)
	end
end

---------------------------------------------------------------------
-- Bau-Helfer
---------------------------------------------------------------------
-- Die Standard-Baseplate aus der Studio-Vorlage würde mit unserer Wiese flackern
local templateBaseplate = workspace:FindFirstChild("Baseplate")
if templateBaseplate and templateBaseplate:IsA("BasePart") then
	templateBaseplate:Destroy()
end

local oldMap = workspace:FindFirstChild("EierRaubMap")
if oldMap then
	oldMap:Destroy()
end
local map = Instance.new("Folder")
map.Name = "EierRaubMap"
map.Parent = workspace

local function folder(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local decoFolder = folder("Deko", map)
local basesFolder = folder("Bases", map)
local eggsFolder = folder("Eggs", map)
local beltFolder = folder("Laufband", map)

local function makePart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	local parent = props.Parent or decoFolder
	props.Parent = nil
	if props.Shape then
		p.Shape = props.Shape
		props.Shape = nil
	end
	for k, v in props do
		p[k] = v
	end
	p.Parent = parent
	return p
end

-- Stehender Zylinder (Roblox-Zylinder liegen standardmäßig auf der X-Achse)
local function cylinder(props, cf: CFrame, height: number, diameter: number)
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(height, diameter, diameter)
	props.CFrame = cf * CFrame.Angles(0, 0, math.rad(90))
	return makePart(props)
end

local function ball(props, pos: Vector3, diameter: number)
	props.Shape = Enum.PartType.Ball
	props.Size = Vector3.one * diameter
	props.CFrame = CFrame.new(pos)
	return makePart(props)
end

local function makeLabel(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextColor3 = WHITE
	l.TextStrokeTransparency = 0.3
	l.TextScaled = true
	l.Size = UDim2.fromScale(1, 0.25)
	for k, v in props do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local function addGradient(label, colors: { Color3 })
	local keypoints = {}
	for i, c in colors do
		table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / math.max(#colors - 1, 1), c))
	end
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(keypoints)
	g:SetAttribute("Animated", true) -- der Client lässt den Verlauf wandern
	g.Parent = label
	label.TextColor3 = WHITE
	return g
end

local function surfaceGui(part, face, pixelsPerStud)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = pixelsPerStud or 40
	sg.LightInfluence = 0
	sg.Parent = part
	return sg
end

local function billboard(parent, size: UDim2, offset: Vector3, maxDistance: number?)
	local bb = Instance.new("BillboardGui")
	bb.Size = size
	bb.StudsOffset = offset
	bb.MaxDistance = maxDistance or 80
	bb.LightInfluence = 0
	bb.Parent = parent
	return bb
end

---------------------------------------------------------------------
-- Licht & Atmosphäre
---------------------------------------------------------------------
Lighting.ClockTime = 14.5
Lighting.Brightness = 2.4
Lighting.Ambient = Color3.fromRGB(105, 105, 120)
Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 155)
Lighting.EnvironmentDiffuseScale = 0.5
Lighting.EnvironmentSpecularScale = 0.6
Lighting.GlobalShadows = true

local function lightingEffect(class, name, props)
	local e = Lighting:FindFirstChild(name) or Instance.new(class)
	e.Name = name
	for k, v in props do
		e[k] = v
	end
	e.Parent = Lighting
end

lightingEffect("Atmosphere", "EierRaubAtmosphaere", {
	Density = 0.28,
	Offset = 0.1,
	Color = Color3.fromRGB(200, 222, 255),
	Decay = Color3.fromRGB(120, 145, 200),
	Glare = 0.2,
	Haze = 1.2,
})
lightingEffect("BloomEffect", "EierRaubBloom", { Intensity = 0.7, Size = 28, Threshold = 1.5 })
lightingEffect("ColorCorrectionEffect", "EierRaubFarben", { Saturation = 0.2, Contrast = 0.07, Brightness = 0.02 })
lightingEffect("SunRaysEffect", "EierRaubSonne", { Intensity = 0.06, Spread = 0.6 })

---------------------------------------------------------------------
-- Welt: Boden, Wege, Bäume, Lampen
---------------------------------------------------------------------
local CONV_START, CONV_END = -165, 165
local BELT_TOP = 1

makePart({
	Name = "Wiese",
	Size = Vector3.new(600, 2, 600),
	Position = Vector3.new(0, -1, 0),
	Color = Color3.fromRGB(100, 175, 85),
	Material = Enum.Material.Grass,
})
makePart({
	Name = "Weg",
	Size = Vector3.new(380, 0.2, 48),
	Position = Vector3.new(0, 0.1, 0),
	Color = Color3.fromRGB(200, 195, 185),
	Material = Enum.Material.Pavement,
})
-- Bordsteine
for _, z in { -24.3, 24.3 } do
	makePart({
		Name = "Bordstein",
		Size = Vector3.new(380, 0.5, 0.6),
		Position = Vector3.new(0, 0.25, z),
		Color = Color3.fromRGB(150, 150, 155),
		Material = Enum.Material.Concrete,
	})
end

local function tree(pos: Vector3, s: number)
	local trunkHeight = 7 * s
	cylinder({
		Name = "Stamm",
		Color = Color3.fromRGB(110, 75, 45),
		Material = Enum.Material.Wood,
	}, CFrame.new(pos + Vector3.new(0, trunkHeight / 2, 0)), trunkHeight, 1.6 * s)
	local greens = { Color3.fromRGB(70, 160, 70), Color3.fromRGB(90, 185, 80), Color3.fromRGB(60, 140, 65) }
	for i = 1, 3 do
		local offset = Vector3.new(rng:NextNumber(-1.5, 1.5) * s, trunkHeight + (i - 1) * 1.6 * s, rng:NextNumber(-1.5, 1.5) * s)
		ball({ Name = "Krone", Color = greens[i], Material = Enum.Material.Grass }, pos + offset, (7.5 - i) * s)
	end
end

local treeRng = Random.new(42)
local placedTrees = 0
while placedTrees < 80 do
	local x = treeRng:NextNumber(-290, 290)
	local z = treeRng:NextNumber(-290, 290)
	if math.abs(x) > 205 or math.abs(z) > 100 then
		tree(Vector3.new(x, 0, z), treeRng:NextNumber(0.8, 1.4))
		placedTrees += 1
	end
end

-- Blumen auf der Wiese
local flowerColors = {
	Color3.fromRGB(255, 120, 160),
	Color3.fromRGB(255, 230, 90),
	Color3.fromRGB(170, 120, 255),
	Color3.fromRGB(255, 255, 255),
}
for _ = 1, 120 do
	local x = treeRng:NextNumber(-280, 280)
	local z = treeRng:NextNumber(-280, 280)
	if math.abs(x) > 195 or math.abs(z) > 95 then
		ball({
			Name = "Blume",
			Color = flowerColors[treeRng:NextInteger(1, #flowerColors)],
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			CastShadow = false,
		}, Vector3.new(x, 0.35, z), 0.8)
	end
end

local function lamp(pos: Vector3)
	cylinder(
		{ Name = "Laternenmast", Color = Color3.fromRGB(45, 45, 55), Material = Enum.Material.Metal },
		CFrame.new(pos + Vector3.new(0, 4.5, 0)),
		9,
		0.6
	)
	local bulb = ball({
		Name = "Laternenlicht",
		Color = Color3.fromRGB(255, 225, 160),
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, pos + Vector3.new(0, 9.4, 0), 1.6)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 210, 150)
	light.Range = 18
	light.Brightness = 1.5
	light.Parent = bulb
end

for _, x in { -150, -75, 0, 75, 150 } do
	lamp(Vector3.new(x, 0, -21.5))
	lamp(Vector3.new(x, 0, 21.5))
end

local spawn = Instance.new("SpawnLocation")
spawn.Name = "Spawn"
spawn.Anchored = true
spawn.Neutral = true
spawn.Size = Vector3.new(8, 0.4, 8)
spawn.Position = Vector3.new(0, 0.4, 14)
spawn.Color = Color3.fromRGB(255, 255, 255)
spawn.Material = Enum.Material.SmoothPlastic
spawn.Transparency = 0.3
spawn.CanCollide = false
spawn.Duration = 0
spawn.Parent = decoFolder

---------------------------------------------------------------------
-- Laufband, Ei-Maschine, Recycler
---------------------------------------------------------------------
local beltLength = CONV_END - CONV_START
makePart({
	Name = "Band",
	Size = Vector3.new(beltLength, 1, 10),
	Position = Vector3.new(0, 0.5, 0),
	Color = Color3.fromRGB(40, 40, 48),
	Material = Enum.Material.Rubber,
	Parent = beltFolder,
})
for _, z in { -5.4, 5.4 } do
	makePart({
		Name = "Schiene",
		Size = Vector3.new(beltLength, 1.6, 0.8),
		Position = Vector3.new(0, 0.8, z),
		Color = Color3.fromRGB(255, 200, 40),
		Material = Enum.Material.Metal,
		Parent = beltFolder,
	})
	-- Warnstreifen
	for x = CONV_START + 2, CONV_END - 2, 6 do
		makePart({
			Name = "Warnstreifen",
			Size = Vector3.new(2, 1.62, 0.82),
			CFrame = CFrame.new(x, 0.8, z) * CFrame.Angles(0, 0, math.rad(35)),
			Color = Color3.fromRGB(30, 30, 30),
			CanCollide = false,
			Parent = beltFolder,
		})
	end
end

-- Lamellen, die der Client bewegt (sieht aus wie ein laufendes Band)
local SLAT_SPACING = 6
local slatFolder = folder("Lamellen", beltFolder)
slatFolder:SetAttribute("Start", CONV_START)
slatFolder:SetAttribute("Length", beltLength)
slatFolder:SetAttribute("Spacing", SLAT_SPACING)
slatFolder:SetAttribute("Speed", Config.ConveyorSpeed)
for i = 0, math.floor(beltLength / SLAT_SPACING) - 1 do
	makePart({
		Name = "Lamelle",
		Size = Vector3.new(0.5, 0.12, 9.4),
		Position = Vector3.new(CONV_START + i * SLAT_SPACING, BELT_TOP + 0.06, 0),
		Color = Color3.fromRGB(70, 70, 82),
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = slatFolder,
	}):SetAttribute("Index", i)
end

local function machine(name: string, x: number, color: Color3, title: string)
	local body = makePart({
		Name = name,
		Size = Vector3.new(20, 13, 18),
		Position = Vector3.new(x, 6.5, 0),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
	})
	makePart({
		Name = name .. "Dach",
		Size = Vector3.new(22, 1.2, 20),
		Position = Vector3.new(x, 13.6, 0),
		Color = color:Lerp(BLACK, 0.3),
	})
	local dome = ball({
		Name = name .. "Kuppel",
		Color = Color3.fromRGB(180, 230, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.45,
	}, Vector3.new(x, 15, 0), 11)
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Rate = 6
	sparkle.Lifetime = NumberRange.new(1.5, 2.5)
	sparkle.Speed = NumberRange.new(1, 3)
	sparkle.Size = NumberSequence.new(0.6)
	sparkle.LightEmission = 1
	sparkle.Color = ColorSequence.new(YELLOW)
	sparkle.Parent = dome
	-- Öffnung zum Band
	local side = x < 0 and 1 or -1
	makePart({
		Name = name .. "Tunnel",
		Size = Vector3.new(0.4, 7, 10),
		Position = Vector3.new(x + side * 10.05, 4.5, 0),
		Color = BLACK,
		Material = Enum.Material.Neon,
		Transparency = 0.2,
	})
	makePart({
		Name = name .. "Rahmen",
		Size = Vector3.new(0.8, 1, 12),
		Position = Vector3.new(x + side * 10.2, 8.5, 0),
		Color = YELLOW,
		Material = Enum.Material.Neon,
	})
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local sg = surfaceGui(body, face, 30)
		makeLabel(sg, {
			Text = title,
			Size = UDim2.fromScale(0.9, 0.35),
			Position = UDim2.fromScale(0.05, 0.12),
		})
	end
	return body
end

machine("EiMaschine", CONV_START - 10, Color3.fromRGB(235, 80, 80), "🥚 EI-MASCHINE")
machine("Recycler", CONV_END + 10, Color3.fromRGB(70, 170, 110), "♻️ RECYCLER")

-- Schwebendes Logo über der Mitte
local logoPart = makePart({
	Name = "Logo",
	Size = Vector3.new(1, 1, 1),
	Position = Vector3.new(0, 26, 0),
	Transparency = 1,
	CanCollide = false,
	CanQuery = false,
	CanTouch = false,
})
local logo = billboard(logoPart, UDim2.fromOffset(520, 130), Vector3.zero, 400)
local logoLabel = makeLabel(logo, { Text = "🥚 EIER-RAUB 🥚", Size = UDim2.fromScale(1, 1), TextStrokeTransparency = 0 })
addGradient(logoLabel, { Color3.fromRGB(255, 220, 80), Color3.fromRGB(255, 120, 60), Color3.fromRGB(255, 220, 80) })

---------------------------------------------------------------------
-- Basen
---------------------------------------------------------------------
local BASE_COLORS = {
	Color3.fromRGB(255, 99, 99),
	Color3.fromRGB(255, 165, 60),
	Color3.fromRGB(250, 215, 70),
	Color3.fromRGB(110, 205, 90),
	Color3.fromRGB(70, 200, 220),
	Color3.fromRGB(85, 135, 255),
	Color3.fromRGB(170, 105, 255),
	Color3.fromRGB(255, 110, 200),
}
local HALF_W, HALF_D = 32, 30
local SLOT_OFFSETS = {}
for _, z in { 20, 7 } do
	for _, x in { -24, -12, 0, 12, 24 } do
		table.insert(SLOT_OFFSETS, Vector3.new(x, 0, z))
	end
end
local SLOT_COUNT = math.clamp(Config.SlotsPerBase, 1, #SLOT_OFFSETS)

type Slot = {
	index: number,
	top: CFrame,
	plateLabel: TextLabel,
	egg: BasePart?,
	incoming: BasePart?,
	stolen: BasePart?,
	stored: number,
}

type Base = {
	index: number,
	model: Model,
	cf: CFrame,
	color: Color3,
	owner: Player?,
	lockedUntil: number,
	slots: { Slot },
	barrier: BasePart,
	lockPad: BasePart,
	lockLabel: TextLabel,
	signName: TextLabel,
	signStatus: TextLabel,
	spawnCFrame: CFrame,
	ejectCFrame: CFrame,
}

local bases: { Base } = {}
local profiles = {} -- [Player] = profil
local eggData = {} -- [BasePart] = daten

local collectFromSlot, tryLock -- werden weiter unten gesetzt

local function buildBase(index: number, cf: CFrame, color: Color3): Base
	local model = Instance.new("Model")
	model.Name = "Basis" .. index
	model:SetAttribute("Index", index)

	local function at(x, y, z)
		return cf * CFrame.new(x, y, z)
	end
	local dark = color:Lerp(BLACK, 0.35)
	local light = color:Lerp(WHITE, 0.6)

	makePart({ Name = "Boden", Size = Vector3.new(64, 1, 60), CFrame = at(0, 0.5, 0), Color = light, Parent = model })
	makePart({
		Name = "Teppich",
		Size = Vector3.new(58, 0.1, 44),
		CFrame = at(0, 1.05, 6),
		Color = color:Lerp(WHITE, 0.3),
		Material = Enum.Material.Fabric,
		Parent = model,
	})
	-- Eingangsweg
	makePart({
		Name = "Eingang",
		Size = Vector3.new(14, 0.1, 14),
		CFrame = at(0, 1.05, -22),
		Color = color:Lerp(WHITE, 0.15),
		Material = Enum.Material.Pavement,
		Parent = model,
	})

	local function wall(name, sx, sz, x, z)
		makePart({ Name = name, Size = Vector3.new(sx, 6, sz), CFrame = at(x, 4, z), Color = dark, Parent = model })
		makePart({
			Name = name .. "Glas",
			Size = Vector3.new(sx, 4, sz),
			CFrame = at(x, 9, z),
			Color = color:Lerp(WHITE, 0.5),
			Material = Enum.Material.Glass,
			Transparency = 0.55,
			Parent = model,
		})
		makePart({
			Name = name .. "Kante",
			Size = Vector3.new(sx + 0.1, 0.4, sz + 0.2),
			CFrame = at(x, 11.2, z),
			Color = color,
			Material = Enum.Material.Neon,
			Parent = model,
		})
	end
	wall("WandHinten", 64, 1, 0, HALF_D - 0.5)
	wall("WandLinks", 1, 60, -(HALF_W - 0.5), 0)
	wall("WandRechts", 1, 60, HALF_W - 0.5, 0)
	wall("WandVorneL", 24, 1, -20, -(HALF_D - 0.5))
	wall("WandVorneR", 24, 1, 20, -(HALF_D - 0.5))

	-- Säulen am Eingang und in den Ecken
	for _, p in { { -9.2, -29.5 }, { 9.2, -29.5 }, { -31.5, -29.5 }, { 31.5, -29.5 }, { -31.5, 29.5 }, { 31.5, 29.5 } } do
		makePart({ Name = "Saeule", Size = Vector3.new(2.4, 13, 2.4), CFrame = at(p[1], 7.5, p[2]), Color = WHITE, Parent = model })
		makePart({
			Name = "SaeulenLicht",
			Size = Vector3.new(2.7, 0.6, 2.7),
			CFrame = at(p[1], 14.2, p[2]),
			Color = color,
			Material = Enum.Material.Neon,
			Parent = model,
		})
	end

	-- Schild über dem Eingang
	local sign = makePart({
		Name = "Schild",
		Size = Vector3.new(20, 4, 0.8),
		CFrame = at(0, 16.4, -29.5),
		Color = Color3.fromRGB(30, 30, 40),
		Parent = model,
	})
	makePart({
		Name = "SchildRahmen",
		Size = Vector3.new(20.6, 4.6, 0.6),
		CFrame = at(0, 16.4, -29.3),
		Color = color,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	local sg = surfaceGui(sign, Enum.NormalId.Front, 30)
	local signName = makeLabel(sg, { Text = "Freie Basis", Size = UDim2.fromScale(0.94, 0.55), Position = UDim2.fromScale(0.03, 0.05) })
	local signStatus = makeLabel(sg, {
		Text = "",
		Size = UDim2.fromScale(0.94, 0.35),
		Position = UDim2.fromScale(0.03, 0.6),
		TextColor3 = GREEN,
	})

	-- Sperr-Barriere
	local barrier = makePart({
		Name = "Barriere",
		Size = Vector3.new(16.4, 12, 0.6),
		CFrame = at(0, 7, -29.5),
		Color = Color3.fromRGB(255, 60, 60),
		Material = Enum.Material.ForceField,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = model,
	})

	-- Sperr-Knopf
	makePart({
		Name = "SperrSockel",
		Size = Vector3.new(6, 0.3, 6),
		CFrame = at(24, 1.1, -22),
		Color = Color3.fromRGB(60, 60, 70),
		Parent = model,
	})
	local lockPad = cylinder({
		Name = "SperrKnopf",
		Color = Color3.fromRGB(255, 60, 60),
		Material = Enum.Material.Neon,
		Parent = model,
	}, at(24, 1.4, -22), 0.4, 4.6)
	local lockBB = billboard(lockPad, UDim2.fromOffset(170, 50), Vector3.new(0, 3, 0), 60)
	local lockLabel = makeLabel(lockBB, { Text = "🔒 SPERREN", Size = UDim2.fromScale(1, 1) })

	local base: Base = {
		index = index,
		model = model,
		cf = cf,
		color = color,
		owner = nil,
		lockedUntil = 0,
		slots = {},
		barrier = barrier,
		lockPad = lockPad,
		lockLabel = lockLabel,
		signName = signName,
		signStatus = signStatus,
		spawnCFrame = at(0, 4, -18),
		ejectCFrame = at(0, 4, -40),
	}

	lockPad.Touched:Connect(function(hit)
		local plr = Players:GetPlayerFromCharacter(hit.Parent)
		if plr then
			tryLock(base, plr)
		end
	end)

	-- Plätze für Eier
	for i = 1, SLOT_COUNT do
		local o = SLOT_OFFSETS[i]
		cylinder(
			{ Name = "Sockel", Color = Color3.fromRGB(235, 235, 240), Material = Enum.Material.Marble, Parent = model },
			at(o.X, 1.8, o.Z),
			1.6,
			5
		)
		cylinder({ Name = "SockelRing", Color = color, Material = Enum.Material.Neon, Parent = model }, at(o.X, 2.1, o.Z), 0.3, 5.3)
		cylinder({ Name = "SockelPlatte", Color = WHITE, Parent = model }, at(o.X, 2.7, o.Z), 0.2, 4.4)

		local plate = makePart({
			Name = "Kasse",
			Size = Vector3.new(5, 0.3, 2.6),
			CFrame = at(o.X, 1.15, o.Z - 4.6),
			Color = Color3.fromRGB(70, 230, 110),
			Material = Enum.Material.Neon,
			Parent = model,
		})
		local plateTop = surfaceGui(plate, Enum.NormalId.Top, 30)
		makeLabel(
			plateTop,
			{ Text = "$", Size = UDim2.fromScale(1, 1), TextColor3 = Color3.fromRGB(20, 90, 40), TextStrokeTransparency = 1 }
		)
		local plateBB = billboard(plate, UDim2.fromOffset(120, 34), Vector3.new(0, 1.4, 0), 45)
		local plateLabel = makeLabel(plateBB, { Text = "", Size = UDim2.fromScale(1, 1), TextColor3 = GREEN })

		local slot: Slot = {
			index = i,
			top = at(o.X, 2.8, o.Z),
			plateLabel = plateLabel,
			egg = nil,
			incoming = nil,
			stolen = nil,
			stored = 0,
		}
		base.slots[i] = slot

		plate.Touched:Connect(function(hit)
			local plr = Players:GetPlayerFromCharacter(hit.Parent)
			if plr and base.owner == plr then
				collectFromSlot(base, slot)
			end
		end)
	end

	model.Parent = basesFolder
	return base
end

do
	local index = 0
	for _, side in { 1, -1 } do
		for _, x in { -112.5, -37.5, 37.5, 112.5 } do
			index += 1
			local center = Vector3.new(x, 0, side * 57)
			local cf = CFrame.lookAt(center, center + Vector3.new(0, 0, -side))
			bases[index] = buildBase(index, cf, BASE_COLORS[index])
		end
	end
end

local function isInside(base: Base, pos: Vector3): boolean
	local p = base.cf:PointToObjectSpace(pos)
	return math.abs(p.X) <= HALF_W and math.abs(p.Z) <= HALF_D and p.Y > -5 and p.Y < 30
end

local function isLocked(base: Base): boolean
	return os.clock() < base.lockedUntil
end

---------------------------------------------------------------------
-- Server-Zustand (Events vom Admin-Panel)
---------------------------------------------------------------------
local state = {
	luck = 1,
	luckEnds = 0,
	incomeMult = 1,
	incomeEnds = 0,
	hatchMult = 1,
	hatchEnds = 0,
	spawnInterval = Config.SpawnInterval,
}

local function publishState()
	map:SetAttribute("Luck", state.luck)
	map:SetAttribute("LuckEnds", state.luckEnds)
	map:SetAttribute("IncomeMult", state.incomeMult)
	map:SetAttribute("IncomeEnds", state.incomeEnds)
	map:SetAttribute("HatchMult", state.hatchMult)
	map:SetAttribute("HatchEnds", state.hatchEnds)
	map:SetAttribute("SpawnInterval", state.spawnInterval)
end
publishState()

---------------------------------------------------------------------
-- Geld & Statistik
---------------------------------------------------------------------
local function setMoney(plr: Player, value: number)
	local prof = profiles[plr]
	if not prof then
		return
	end
	prof.money = math.max(0, math.floor(value))
	local ls = plr:FindFirstChild("leaderstats")
	local geld = ls and ls:FindFirstChild("Geld")
	if geld then
		geld.Value = prof.money
	end
end

local function addMoney(plr: Player, delta: number)
	local prof = profiles[plr]
	if prof then
		setMoney(plr, prof.money + delta)
	end
end

local function updateEggCount(base: Base)
	local owner = base.owner
	if not owner then
		return
	end
	local count = 0
	for _, s in base.slots do
		if s.egg then
			count += 1
		end
	end
	local ls = owner:FindFirstChild("leaderstats")
	local eier = ls and ls:FindFirstChild("Eier")
	if eier then
		eier.Value = count
	end
end

local function updatePlate(slot: Slot)
	if slot.stored >= 1 then
		slot.plateLabel.Text = Config.formatMoney(slot.stored)
	else
		slot.plateLabel.Text = ""
	end
end

collectFromSlot = function(base: Base, slot: Slot)
	if slot.stored < 1 or not base.owner then
		return
	end
	local amount = math.floor(slot.stored)
	slot.stored -= amount
	addMoney(base.owner, amount)
	updatePlate(slot)
	effect(base.owner, "cash")
end

tryLock = function(base: Base, plr: Player)
	if base.owner ~= plr or isLocked(base) then
		return
	end
	base.lockedUntil = os.clock() + Config.LockDuration
	notify(plr, "🔒 Basis für " .. Config.LockDuration .. " Sekunden gesperrt!", GREEN)
	effect(plr, "lock")
end

---------------------------------------------------------------------
-- Eier
---------------------------------------------------------------------
local applyMutationLook, applyCreatureLook, updateInfo

local function fmtTime(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	if s >= 60 then
		return string.format("%d:%02d", s // 60, s % 60)
	end
	return s .. "s"
end

-- Funkeln + Regenbogen für Mutationen
function applyMutationLook(egg: BasePart, mut: string?)
	local m = Config.getMutation(mut)
	if not m then
		return
	end
	if not egg:FindFirstChild("MutationSparkles") then
		local sp = Instance.new("Sparkles")
		sp.Name = "MutationSparkles"
		sp.SparkleColor = m.color
		sp.Parent = egg
	end
	if m.id == "Regenbogen" then
		egg:SetAttribute("Rainbow", true)
	end
end

-- Kleines Deko-Teil, das fest am Ei klebt (bewegt sich beim Tragen mit)
local function decor(egg: BasePart, name: string, props, offset: CFrame, sphereMesh: boolean?)
	local p = Instance.new("Part")
	p.Name = name
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	if props.Shape then
		p.Shape = props.Shape
		props.Shape = nil
	end
	for k, v in props do
		p[k] = v
	end
	if sphereMesh then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.CFrame = egg.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = egg
	weld.Part1 = p
	weld.Parent = p
	p.Parent = egg
	return p
end

-- Verwandelt ein Ei in ein geschlüpftes Tierchen in seiner Schale
function applyCreatureLook(egg: BasePart, d)
	if egg:FindFirstChild("Schale") then
		return
	end
	local def = Config.EggsById[d.id]
	local rar = Config.Rarities[def.rarity]
	local w, h = egg.Size.X, egg.Size.Y
	local shellColor, shellMaterial = def.color, def.material or Enum.Material.SmoothPlastic
	local bodyColor = def.creatureColor or def.color
	local rad = math.rad

	egg.Color = bodyColor
	egg.Material = rar.order >= 5 and Enum.Material.Neon or Enum.Material.SmoothPlastic

	-- Untere Schalenhälfte mit Zacken
	decor(egg, "Schale", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.38 * h, 1.08 * w, 1.08 * w),
		Color = shellColor,
		Material = shellMaterial,
	}, CFrame.new(0, -0.31 * h, 0) * CFrame.Angles(0, 0, rad(90)))
	for i = 0, 7 do
		decor(egg, "Zacke", {
			Size = Vector3.new(0.17 * w, 0.17 * w, 0.06 * w),
			Color = shellColor,
			Material = shellMaterial,
		}, CFrame.Angles(0, rad(i * 45), 0) * CFrame.new(0, -0.1 * h, -0.52 * w) * CFrame.Angles(0, 0, rad(45)))
	end

	-- Gesicht
	for _, side in { -1, 1 } do
		decor(
			egg,
			"Auge",
			{ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.22 * w, Color = WHITE },
			CFrame.new(side * 0.17 * w, 0.17 * h, -0.4 * w)
		)
		decor(
			egg,
			"Pupille",
			{ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.12 * w, Color = Color3.fromRGB(20, 20, 25) },
			CFrame.new(side * 0.17 * w, 0.18 * h, -0.49 * w)
		)
		decor(egg, "Wange", {
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.1 * w,
			Color = Color3.fromRGB(255, 140, 160),
		}, CFrame.new(side * 0.3 * w, 0.05 * h, -0.4 * w))
		decor(egg, "Fluegel", {
			Size = Vector3.new(0.14 * w, 0.36 * h, 0.42 * w),
			Color = bodyColor:Lerp(BLACK, 0.18),
		}, CFrame.new(side * 0.5 * w, -0.02 * h, 0.02 * w) * CFrame.Angles(0, 0, side * rad(-15)), true)
	end
	decor(egg, "Schnabel", {
		Size = Vector3.new(0.18 * w, 0.1 * h, 0.18 * w),
		Color = Color3.fromRGB(255, 150, 40),
	}, CFrame.new(0, 0.03 * h, -0.47 * w) * CFrame.Angles(0, rad(45), 0))

	-- Kopfschmuck: Feder oder (ab Legendär) Krone
	if rar.order >= 4 then
		decor(egg, "Krone", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.14 * h, 0.42 * w, 0.42 * w),
			Color = Color3.fromRGB(255, 205, 50),
			Material = Enum.Material.Foil,
		}, CFrame.new(0, 0.53 * h, 0) * CFrame.Angles(0, 0, rad(90)))
		decor(egg, "KronenJuwel", {
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.14 * w,
			Color = rar.color,
			Material = Enum.Material.Neon,
		}, CFrame.new(0, 0.53 * h, -0.2 * w))
	else
		decor(egg, "Feder", {
			Size = Vector3.new(0.1 * w, 0.26 * h, 0.1 * w),
			Color = bodyColor:Lerp(BLACK, 0.25),
		}, CFrame.new(0, 0.55 * h, 0.05 * w) * CFrame.Angles(rad(-20), 0, 0), true)
	end
end

-- Aktualisiert das Schild über dem Ei/Tier
function updateInfo(egg: BasePart, d)
	local info = egg:FindFirstChild("Info")
	if not info then
		return
	end
	local def = Config.EggsById[d.id]
	local m = Config.getMutation(d.mut)
	local mutLabel = info:FindFirstChild("Mutation")
	mutLabel.Visible = m ~= nil
	if m then
		mutLabel.Text = "✨ " .. m.name .. " x" .. m.mult
		mutLabel.TextColor3 = m.color
	end
	info:FindFirstChild("EggName").Text = d.hatched and def.creature or def.name
	local income = Config.formatMoney(Config.getIncome(d.id, d.mut)) .. "/s"
	info:FindFirstChild("Income").Text = d.hatched and income or ("🐣 " .. income)
	local status = info:FindFirstChild("Status")
	status.Visible = not d.hatched
	if not d.hatched then
		local hatchTime = Config.getHatchTime(d.id)
		if d.state == "placed" then
			status.Text = "🥚 Schlüpft in " .. fmtTime(hatchTime - d.progress)
		else
			status.Text = "⏳ Brutzeit " .. fmtTime(hatchTime - d.progress)
		end
	end
end

local function makeEgg(id: string, mut: string?, hatched: boolean?, progress: number?): BasePart
	local def = Config.EggsById[id]
	local rar = Config.Rarities[def.rarity]

	local egg = Instance.new("Part")
	egg.Name = "Egg"
	egg.Size = Config.EggBaseSize * rar.scale
	egg.Color = def.color
	egg.Material = def.material or Enum.Material.SmoothPlastic
	egg.Anchored = true
	egg.CanCollide = false
	egg.CanTouch = false
	egg.TopSurface = Enum.SurfaceType.Smooth
	egg.BottomSurface = Enum.SurfaceType.Smooth
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = egg

	egg:SetAttribute("EggId", id)
	egg:SetAttribute("Mutation", mut or "")
	egg:SetAttribute("OwnerId", 0)
	egg:SetAttribute("Hatching", false)
	if def.rainbow then
		egg:SetAttribute("Rainbow", true)
	end

	-- Leuchten & Partikel je nach Seltenheit
	if rar.order >= 3 then
		local light = Instance.new("PointLight")
		light.Color = rar.color
		light.Range = 6 + rar.order * 1.5
		light.Brightness = 1.2
		light.Parent = egg
	end
	if rar.order >= 4 then
		local p = Instance.new("ParticleEmitter")
		p.Rate = 4 + rar.order * 2
		p.Lifetime = NumberRange.new(0.8, 1.6)
		p.Speed = NumberRange.new(0.5, 2)
		p.SpreadAngle = Vector2.new(180, 180)
		p.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
		p.LightEmission = 1
		p.Color =
			ColorSequence.new(rar.gradient and rar.gradient[1] or rar.color, rar.gradient and rar.gradient[#rar.gradient] or rar.color)
		p.Parent = egg
	end
	applyMutationLook(egg, mut)

	-- Info-Schild über dem Ei
	local bb = billboard(egg, UDim2.fromOffset(220, 124), Vector3.new(0, egg.Size.Y / 2 + 3, 0), 55)
	bb.Name = "Info"
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = bb

	makeLabel(bb, { Name = "Mutation", Text = "", Size = UDim2.fromScale(1, 0.15), Visible = false, LayoutOrder = 1 })
	makeLabel(bb, { Name = "EggName", Text = def.name, Size = UDim2.fromScale(1, 0.22), LayoutOrder = 2 })
	local rarLabel = makeLabel(bb, {
		Name = "Rarity",
		Text = rar.name,
		TextColor3 = rar.color,
		Size = UDim2.fromScale(1, 0.16),
		LayoutOrder = 3,
	})
	if rar.gradient then
		addGradient(rarLabel, rar.gradient)
	end
	makeLabel(bb, { Name = "Income", Text = "", TextColor3 = GREEN, Size = UDim2.fromScale(1, 0.15), LayoutOrder = 4 })
	makeLabel(bb, {
		Name = "Price",
		Text = Config.formatMoney(Config.getPrice(id, mut)),
		TextColor3 = YELLOW,
		Size = UDim2.fromScale(1, 0.15),
		LayoutOrder = 5,
		Visible = false,
	})
	makeLabel(bb, {
		Name = "Status",
		Text = "",
		TextColor3 = Color3.fromRGB(255, 235, 180),
		Size = UDim2.fromScale(1, 0.15),
		LayoutOrder = 6,
	})

	local d = { id = id, mut = mut, state = "new", ownerId = 0, hatched = hatched == true, progress = progress or 0 }
	eggData[egg] = d
	if d.hatched then
		applyCreatureLook(egg, d)
	end
	updateInfo(egg, d)
	return egg
end

local function destroyEgg(egg: BasePart)
	eggData[egg] = nil
	egg:Destroy()
end

local function setPriceVisible(egg: BasePart, visible: boolean)
	local info = egg:FindFirstChild("Info")
	local price = info and info:FindFirstChild("Price")
	if price then
		price.Visible = visible
	end
end

local function clearPrompts(egg: BasePart)
	for _, c in egg:GetChildren() do
		if c:IsA("ProximityPrompt") then
			c:Destroy()
		end
	end
end

local function addPrompt(egg: BasePart, action: string, object: string, hold: number, audience: string, distance: number, callback)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.MaxActivationDistance = distance
	p.RequiresLineOfSight = false
	p:SetAttribute("Audience", audience) -- "all", "owner" oder "others" (Client blendet passend ein)
	p.Triggered:Connect(callback)
	p.Parent = egg
	return p
end

local function findFreeSlot(base: Base): number?
	for i, s in base.slots do
		if not s.egg and not s.incoming and not s.stolen then
			return i
		end
	end
	return nil
end

local function getRoot(plr: Player): (BasePart?, Humanoid?)
	local char = plr.Character
	if not char then
		return nil, nil
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	return root, hum
end

local stealEgg, sellEgg

-- Klauen/Verkaufen-Prompts für ein Ei, das auf einem Brutplatz steht
local function setPlacedPrompts(egg: BasePart)
	local d = eggData[egg]
	clearPrompts(egg)
	local name = Config.getDisplayName(d.id, d.mut, d.hatched)
	local sellValue = math.floor(Config.getPrice(d.id, d.mut) * Config.SellFactor)
	addPrompt(egg, "Klauen", name, Config.StealHoldTime, "others", 8, function(plr)
		stealEgg(plr, egg)
	end)
	addPrompt(egg, "Verkaufen", "+" .. Config.formatMoney(sellValue), 1, "owner", 8, function(plr)
		sellEgg(plr, egg)
	end)
end

local function placeEgg(egg: BasePart, base: Base, idx: number)
	local d = eggData[egg]
	local slot = base.slots[idx]
	for _, c in egg:GetChildren() do
		if c:IsA("WeldConstraint") then
			c:Destroy()
		end
	end
	egg.Anchored = true
	egg.Massless = false
	egg.CFrame = slot.top * CFrame.new(0, egg.Size.Y / 2, 0)
	d.state = "placed"
	d.base = base
	d.slot = idx
	d.ownerId = base.owner and base.owner.UserId or 0
	egg:SetAttribute("OwnerId", d.ownerId)
	slot.egg = egg
	if slot.incoming == egg then
		slot.incoming = nil
	end
	setPriceVisible(egg, false)
	egg:SetAttribute("Hatching", not d.hatched)
	setPlacedPrompts(egg)
	updateInfo(egg, d)
	updateEggCount(base)
end

-- Schalensplitter + Funken beim Schlüpfen
local function hatchBurst(egg: BasePart, shellColor: Color3)
	local burst = Instance.new("ParticleEmitter")
	burst.Rate = 0
	burst.Lifetime = NumberRange.new(0.6, 1.2)
	burst.Speed = NumberRange.new(8, 16)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	burst.LightEmission = 1
	burst.Color = ColorSequence.new(YELLOW, WHITE)
	burst.Parent = egg
	burst:Emit(40)
	Debris:AddItem(burst, 2)
	for _ = 1, 6 do
		local shard = Instance.new("Part")
		shard.Name = "Splitter"
		shard.Size = Vector3.new(0.5, 0.15, 0.5)
		shard.Color = shellColor
		shard.CanQuery = false
		shard.CanTouch = false
		shard.CFrame = egg.CFrame * CFrame.new(rng:NextNumber(-0.5, 0.5), egg.Size.Y * 0.3, rng:NextNumber(-0.5, 0.5))
		shard.Parent = decoFolder
		shard.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(14, 22), rng:NextNumber(-12, 12))
		shard.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-10, 10), rng:NextNumber(-10, 10), rng:NextNumber(-10, 10))
		Debris:AddItem(shard, 2.5)
	end
end

-- Das Ei schlüpft: Tier erscheint, Überraschungs-Mutation wird gewürfelt
local function hatchEgg(egg: BasePart)
	local d = eggData[egg]
	if not d or d.hatched then
		return
	end
	d.hatched = true
	d.progress = Config.getHatchTime(d.id)
	local surprise = false
	if not d.mut then
		d.mut = Config.rollMutation(state.luck, rng)
		surprise = d.mut ~= nil
	end
	egg:SetAttribute("Mutation", d.mut or "")
	egg:SetAttribute("Hatching", false)
	egg:SetAttribute("Hatched", true)
	local def = Config.EggsById[d.id]
	hatchBurst(egg, def.color)
	applyMutationLook(egg, d.mut)
	applyCreatureLook(egg, d)
	updateInfo(egg, d)
	if d.state == "placed" then
		setPlacedPrompts(egg)
	end

	local owner = d.base and d.base.owner
	local creature = Config.getCreatureName(d.id, d.mut)
	if owner then
		notify(owner, "🐣 Dein " .. def.name .. " ist geschlüpft: " .. creature .. "!", YELLOW)
		effect(owner, "hatch")
		local m = Config.getMutation(d.mut)
		if surprise and m then
			notify(owner, "🌟 ÜBERRASCHUNG! " .. m.name .. "-Mutation – x" .. m.mult .. " Geld!", m.color)
		end
		local rar = Config.Rarities[def.rarity]
		if rar.order >= 5 or (m and m.mult >= 10) then
			announceEvent:FireAllClients(owner.DisplayName .. " hat " .. creature .. " ausgebrütet!", "Brutstation")
		end
	end
end

local function walkTo(egg: BasePart, target: Vector3)
	local distance = (target - egg.Position).Magnitude
	local duration = math.max(distance / Config.EggWalkSpeed, 0.05)
	TweenService:Create(egg, TweenInfo.new(duration, Enum.EasingStyle.Linear), { CFrame = CFrame.new(target) }):Play()
	task.wait(duration)
end

local buyEgg

local function spawnConveyorEgg(id: string, mut: string?, startX: number?, fromSky: boolean?)
	local egg = makeEgg(id, mut)
	local y = BELT_TOP + 0.12 + egg.Size.Y / 2
	local x = startX or CONV_START
	local d = eggData[egg]
	d.state = "conveyor"
	setPriceVisible(egg, true)
	updateInfo(egg, d)
	addPrompt(egg, "Kaufen", Config.formatMoney(Config.getPrice(id, mut)), 0.25, "all", 12, function(plr)
		buyEgg(plr, egg)
	end)

	local function roll()
		if eggData[egg] ~= d or d.state ~= "conveyor" then
			return
		end
		local duration = (CONV_END - x) / Config.ConveyorSpeed
		local tween = TweenService:Create(egg, TweenInfo.new(duration, Enum.EasingStyle.Linear), { CFrame = CFrame.new(CONV_END, y, 0) })
		d.tween = tween
		tween.Completed:Connect(function(playbackState)
			if playbackState == Enum.PlaybackState.Completed and eggData[egg] == d and d.state == "conveyor" then
				destroyEgg(egg)
			end
		end)
		tween:Play()
	end

	if fromSky then
		egg.CFrame = CFrame.new(x, 45, 0)
		egg.Parent = eggsFolder
		local drop = TweenService:Create(egg, TweenInfo.new(0.8, Enum.EasingStyle.Bounce), { CFrame = CFrame.new(x, y, 0) })
		d.tween = drop
		drop.Completed:Connect(roll)
		drop:Play()
	else
		egg.CFrame = CFrame.new(x, y, 0)
		egg.Parent = eggsFolder
		roll()
	end

	local rar = Config.Rarities[Config.EggsById[id].rarity]
	if rar.order >= 5 then
		announceEvent:FireAllClients(
			"Ein " .. rar.name .. "es Ei ist auf dem Laufband: " .. Config.getDisplayName(id, mut) .. "!",
			"Ei-Maschine"
		)
	end
	return egg
end

buyEgg = function(plr: Player, egg: BasePart)
	local d = eggData[egg]
	local prof = profiles[plr]
	if not d or d.state ~= "conveyor" or not prof then
		return
	end
	local base = prof.base
	if not base then
		notify(plr, "Du hast keine Basis (Server ist voll).", RED)
		return
	end
	local price = Config.getPrice(d.id, d.mut)
	if prof.money < price then
		notify(plr, "Nicht genug Geld! Du brauchst " .. Config.formatMoney(price) .. ".", RED)
		effect(plr, "error")
		return
	end
	local idx = findFreeSlot(base)
	if not idx then
		notify(plr, "Deine Basis ist voll! Verkaufe zuerst ein Ei.", RED)
		effect(plr, "error")
		return
	end

	addMoney(plr, -price)
	d.state = "walking"
	d.ownerId = plr.UserId
	egg:SetAttribute("OwnerId", plr.UserId)
	if d.tween then
		d.tween:Cancel()
		d.tween = nil
	end
	clearPrompts(egg)
	setPriceVisible(egg, false)
	local slot = base.slots[idx]
	slot.incoming = egg
	notify(plr, "Gekauft: " .. Config.getDisplayName(d.id, d.mut, d.hatched) .. "! Es läuft zu deiner Basis.", GREEN)
	effect(plr, "buy")

	task.spawn(function()
		local h = egg.Size.Y / 2
		local entrance = base.cf * CFrame.new(0, 0, -36)
		walkTo(egg, Vector3.new(entrance.X, BELT_TOP + h, entrance.Z))
		if eggData[egg] ~= d or base.owner ~= plr then
			return
		end
		walkTo(egg, (slot.top * CFrame.new(0, h, 0)).Position)
		if eggData[egg] == d and d.state == "walking" and slot.incoming == egg and base.owner == plr then
			placeEgg(egg, base, idx)
		end
	end)
end

sellEgg = function(plr: Player, egg: BasePart)
	local d = eggData[egg]
	if not d or d.state ~= "placed" or d.base.owner ~= plr then
		return
	end
	local base = d.base
	local slot = base.slots[d.slot]
	local amount = math.floor(Config.getPrice(d.id, d.mut) * Config.SellFactor)
	collectFromSlot(base, slot)
	slot.egg = nil
	addMoney(plr, amount)
	notify(plr, "Verkauft: " .. Config.getDisplayName(d.id, d.mut, d.hatched) .. " für " .. Config.formatMoney(amount), YELLOW)
	effect(plr, "cash")
	destroyEgg(egg)
	updateEggCount(base)
end

---------------------------------------------------------------------
-- Klauen
---------------------------------------------------------------------
local function walkSpeedFor(plr: Player): number
	local prof = profiles[plr]
	return prof and prof.walkSpeed or Config.NormalWalkSpeed
end

-- Beendet das Tragen und gibt die Ei-Daten zurück
local function endCarry(plr: Player)
	local prof = profiles[plr]
	local egg = prof and prof.carrying
	if not egg then
		return nil, nil
	end
	prof.carrying = nil
	plr:SetAttribute("Carrying", nil)
	local _, hum = getRoot(plr)
	if hum then
		hum.WalkSpeed = walkSpeedFor(plr)
	end
	if egg.Parent then
		for _, c in egg:GetChildren() do
			if c:IsA("WeldConstraint") then
				c:Destroy()
			end
		end
		egg.Anchored = true
	end
	return egg, eggData[egg]
end

local function returnEgg(plr: Player, reason: string?)
	local egg, d = endCarry(plr)
	if not egg then
		return
	end
	if reason then
		notify(plr, reason, RED)
	end
	if not d then
		return
	end
	local base = d.fromBase
	local slot = base.slots[d.fromSlot]
	if slot.stolen == egg then
		slot.stolen = nil
	end
	local owner = base.owner
	if egg.Parent and owner and owner.UserId == d.fromOwnerId and not slot.egg and not slot.incoming then
		placeEgg(egg, base, d.fromSlot)
		notify(owner, "✅ Dein " .. Config.getDisplayName(d.id, d.mut, d.hatched) .. " ist zurück!", GREEN)
	else
		destroyEgg(egg)
	end
end

local function deliverEgg(plr: Player)
	local prof = profiles[plr]
	local base = prof and prof.base
	if not base then
		return
	end
	local idx = findFreeSlot(base)
	if not idx then
		returnEgg(plr, "Deine Basis ist voll – das Ei ist zurückgeflogen!")
		return
	end
	local egg, d = endCarry(plr)
	if not egg or not d then
		return
	end
	local fromSlot = d.fromBase.slots[d.fromSlot]
	if fromSlot.stolen == egg then
		fromSlot.stolen = nil
	end
	placeEgg(egg, base, idx)
	local name = Config.getDisplayName(d.id, d.mut, d.hatched)
	notify(plr, "🎉 " .. name .. " erfolgreich geklaut!", GREEN)
	effect(plr, "success")
	local victim = d.fromBase.owner
	if victim and victim.UserId == d.fromOwnerId then
		notify(victim, "😡 " .. plr.DisplayName .. " hat dein " .. name .. " geklaut!", RED)
		effect(victim, "alarm")
	end
end

stealEgg = function(plr: Player, egg: BasePart)
	local d = eggData[egg]
	local prof = profiles[plr]
	if not d or d.state ~= "placed" or not prof or prof.carrying then
		return
	end
	local base = d.base
	if base.owner == plr then
		return
	end
	if not prof.base then
		notify(plr, "Du brauchst eine eigene Basis zum Klauen.", RED)
		return
	end
	if isLocked(base) then
		notify(plr, "🔒 Diese Basis ist gesperrt!", RED)
		effect(plr, "error")
		return
	end
	local root, hum = getRoot(plr)
	if not root or not hum or hum.Health <= 0 then
		return
	end
	if (root.Position - egg.Position).Magnitude > 16 then
		return
	end

	local slot = base.slots[d.slot]
	collectFromSlot(base, slot) -- das gesammelte Geld bleibt beim Besitzer
	slot.egg = nil
	slot.stolen = egg
	d.state = "carried"
	d.fromBase = base
	d.fromSlot = d.slot
	d.fromOwnerId = d.ownerId
	clearPrompts(egg)

	egg.CFrame = root.CFrame * CFrame.new(0, 3.2 + egg.Size.Y / 2, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = egg
	weld.Parent = egg
	egg.Massless = true
	egg.Anchored = false

	prof.carrying = egg
	hum.WalkSpeed = Config.CarryWalkSpeed
	local name = Config.getDisplayName(d.id, d.mut, d.hatched)
	plr:SetAttribute("Carrying", name)
	updateEggCount(base)

	notify(plr, "Du hast " .. name .. " geschnappt! Bring es in deine Basis!", YELLOW)
	effect(plr, "steal")
	if base.owner then
		notify(base.owner, "⚠️ " .. plr.DisplayName .. " klaut dein " .. name .. "! Hau ihn mit dem Schläger!", RED)
		effect(base.owner, "alarm")
	end
end

---------------------------------------------------------------------
-- Schläger
---------------------------------------------------------------------
local function knockback(attacker: Player, victim: Player, vroot: BasePart, dir: Vector3)
	local att = Instance.new("Attachment")
	att.Parent = vroot
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.MaxForce = 1e6
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VectorVelocity = dir * Config.BatKnockback + Vector3.new(0, 28, 0)
	lv.Parent = vroot
	Debris:AddItem(lv, 0.18)
	Debris:AddItem(att, 0.18)
	effect(victim, "hit")

	local vprof = profiles[victim]
	if vprof and vprof.carrying then
		returnEgg(victim, "💥 " .. attacker.DisplayName .. " hat dich erwischt – das Ei ist weg!")
		notify(attacker, "💪 Ei zurückerobert!", GREEN)
		effect(attacker, "success")
	end
end

local function makeBat(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Schläger"
	tool.ToolTip = "Hau Diebe weg!"
	tool.CanBeDropped = false
	tool.RequiresHandle = true

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.5, 4.6, 0.5)
	handle.Color = Color3.fromRGB(160, 110, 60)
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	local tip = Instance.new("Part")
	tip.Name = "Spitze"
	tip.Size = Vector3.new(0.9, 1.6, 0.9)
	tip.Color = Color3.fromRGB(140, 90, 45)
	tip.Material = Enum.Material.Wood
	tip.CanCollide = false
	tip.Massless = true
	tip.CFrame = handle.CFrame * CFrame.new(0, 2, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = tip
	weld.Parent = tip
	tip.Parent = tool

	local swing = Instance.new("Sound")
	swing.Name = "Swing"
	swing.SoundId = "rbxasset://sounds/swordslash.wav"
	swing.Volume = 0.6
	swing.Parent = handle

	local idleGrip = CFrame.new(0, -1.6, 0)
	tool.Grip = idleGrip
	local last = 0

	tool.Activated:Connect(function()
		local char = tool.Parent
		local plr = Players:GetPlayerFromCharacter(char)
		if not plr or os.clock() - last < Config.BatCooldown then
			return
		end
		last = os.clock()
		swing:Play()
		tool.Grip = idleGrip * CFrame.Angles(math.rad(-75), 0, 0)
		task.delay(0.25, function()
			tool.Grip = idleGrip
		end)

		local root = getRoot(plr)
		if not root then
			return
		end
		for _, other in Players:GetPlayers() do
			if other ~= plr then
				local oroot, ohum = getRoot(other)
				if oroot and ohum and ohum.Health > 0 then
					local offset = oroot.Position - root.Position
					local dist = offset.Magnitude
					if dist > 0 and dist <= Config.BatRange and offset.Unit:Dot(root.CFrame.LookVector) > 0.1 then
						knockback(plr, other, oroot, offset.Unit)
					end
				end
			end
		end
	end)

	return tool
end

---------------------------------------------------------------------
-- Speichern
---------------------------------------------------------------------
local store = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[Eier-Raub] DataStore nicht verfügbar – Spielstände werden nicht gespeichert:", result)
	end
end

local function dataKey(plr: Player)
	return "spieler_" .. plr.UserId
end

local function loadData(plr: Player)
	if not store then
		return false, nil
	end
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return store:GetAsync(dataKey(plr))
		end)
		if ok then
			return true, result
		end
		warn("[Eier-Raub] Laden fehlgeschlagen (Versuch " .. attempt .. "):", result)
		task.wait(1)
	end
	return false, nil
end

local function snapshot(plr: Player)
	local prof = profiles[plr]
	if not prof then
		return nil
	end
	local eggs = {}
	local money = prof.money
	local base = prof.base
	if base and base.owner == plr then
		for _, s in base.slots do
			local e = s.egg or s.incoming
			local d = e and eggData[e]
			if d then
				table.insert(eggs, { i = d.id, m = d.mut, h = d.hatched, p = math.floor(d.progress) })
			end
			money += math.floor(s.stored)
		end
	end
	return { v = 1, money = money, eggs = eggs }
end

local function writeData(plr: Player, data)
	local prof = profiles[plr]
	if not store or not data or (prof and not prof.loaded) then
		return
	end
	local ok, err = pcall(function()
		store:SetAsync(dataKey(plr), data, { plr.UserId })
	end)
	if not ok then
		warn("[Eier-Raub] Speichern fehlgeschlagen:", err)
	end
end

---------------------------------------------------------------------
-- Admins
---------------------------------------------------------------------
local function isAdmin(plr: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if table.find(Config.Admins, plr.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return plr.UserId == game.CreatorId
	end
	local ok, rank = pcall(function()
		return plr:GetRankInGroup(game.CreatorId)
	end)
	return ok and rank == 255
end

---------------------------------------------------------------------
-- Spieler betreten / verlassen
---------------------------------------------------------------------
local function clearBase(base: Base)
	for _, slot in base.slots do
		if slot.egg then
			destroyEgg(slot.egg)
		end
		if slot.incoming then
			destroyEgg(slot.incoming)
		end
		slot.egg = nil
		slot.incoming = nil
		slot.stolen = nil
		slot.stored = 0
		updatePlate(slot)
	end
	updateEggCount(base)
end

local function restoreEggs(plr: Player, eggs)
	local prof = profiles[plr]
	local base = prof and prof.base
	if not base or type(eggs) ~= "table" then
		return
	end
	for _, e in eggs do
		if type(e) == "table" and Config.EggsById[e.i] then
			local idx = findFreeSlot(base)
			if not idx then
				break
			end
			local mut = Config.getMutation(e.m) and e.m or nil
			local egg = makeEgg(e.i, mut, e.h == true, tonumber(e.p) or 0)
			egg.Parent = eggsFolder
			placeEgg(egg, base, idx)
		end
	end
end

local function onCharacter(plr: Player, char: Model)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if not hum or not root then
		return
	end
	hum.WalkSpeed = walkSpeedFor(plr)
	hum.Died:Connect(function()
		local prof = profiles[plr]
		if prof and prof.carrying then
			returnEgg(plr, "Du bist gestorben – das Ei ist zurück beim Besitzer.")
		end
	end)
	local prof = profiles[plr]
	if prof and prof.base then
		task.wait()
		if char.Parent then
			char:PivotTo(prof.base.spawnCFrame)
		end
	end
	local backpack = plr:FindFirstChildOfClass("Backpack")
	if backpack and not backpack:FindFirstChild("Schläger") and not char:FindFirstChild("Schläger") then
		makeBat().Parent = backpack
	end
end

local function onPlayerAdded(plr: Player)
	local base: Base? = nil
	for _, b in bases do
		if not b.owner then
			base = b
			break
		end
	end

	local prof = {
		money = Config.StartMoney,
		base = base,
		carrying = nil,
		loaded = false,
		walkSpeed = Config.NormalWalkSpeed,
	}
	profiles[plr] = prof
	if base then
		base.owner = plr
		plr:SetAttribute("BaseIndex", base.index)
	end
	if isAdmin(plr) then
		plr:SetAttribute("IsAdmin", true)
	end

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local geld = Instance.new("NumberValue")
	geld.Name = "Geld"
	geld.Value = prof.money
	geld.Parent = ls
	local eier = Instance.new("IntValue")
	eier.Name = "Eier"
	eier.Parent = ls
	ls.Parent = plr

	plr.CharacterAdded:Connect(function(char)
		onCharacter(plr, char)
	end)
	if plr.Character then
		task.spawn(onCharacter, plr, plr.Character)
	end

	local ok, data = loadData(plr)
	if profiles[plr] ~= prof or not plr.Parent then
		return
	end
	prof.loaded = ok or not store
	if ok and type(data) == "table" then
		setMoney(plr, tonumber(data.money) or Config.StartMoney)
		restoreEggs(plr, data.eggs)
		notify(plr, "Willkommen zurück, " .. plr.DisplayName .. "! 🥚", GREEN)
	else
		setMoney(plr, Config.StartMoney)
		notify(plr, "Willkommen bei Eier-Raub, " .. plr.DisplayName .. "! 🥚", GREEN)
	end
	if not ok and store then
		notify(plr, "⚠️ Spielstand konnte nicht geladen werden – Fortschritt wird diesmal nicht gespeichert.", RED)
	end
	if not base then
		notify(plr, "Alle Basen sind belegt – du kannst nur zuschauen.", RED)
	end
end

local function onPlayerRemoving(plr: Player)
	local prof = profiles[plr]
	if not prof then
		return
	end
	if prof.carrying then
		returnEgg(plr)
	end
	local data = snapshot(plr)
	local base = prof.base
	if base and base.owner == plr then
		clearBase(base)
		base.owner = nil
		base.lockedUntil = 0
	end
	task.spawn(function()
		writeData(plr, data)
	end)
	profiles[plr] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, plr in Players:GetPlayers() do
	task.spawn(onPlayerAdded, plr)
end

game:BindToClose(function()
	local pending = 0
	for _, plr in Players:GetPlayers() do
		local data = snapshot(plr)
		pending += 1
		task.spawn(function()
			writeData(plr, data)
			pending -= 1
		end)
	end
	local started = os.clock()
	while pending > 0 and os.clock() - started < 25 do
		task.wait(0.1)
	end
end)

task.spawn(function()
	while true do
		task.wait(Config.AutoSaveInterval)
		for _, plr in Players:GetPlayers() do
			local data = snapshot(plr)
			task.spawn(writeData, plr, data)
		end
	end
end)

---------------------------------------------------------------------
-- Admin-Panel (Server-Seite) – jede Aktion wird hier geprüft
---------------------------------------------------------------------
local function num(value, min: number, max: number): number?
	local n = tonumber(value)
	if not n or n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	return math.clamp(n, min, max)
end

local function target(args): Player?
	return Players:GetPlayerByUserId(tonumber(args and args.target) or 0)
end

local adminActions = {}

adminActions.getState = function(_admin, _args)
	local list = {}
	for _, p in Players:GetPlayers() do
		local prof = profiles[p]
		local eggs = 0
		if prof and prof.base then
			for _, s in prof.base.slots do
				if s.egg then
					eggs += 1
				end
			end
		end
		table.insert(list, {
			userId = p.UserId,
			name = p.Name,
			displayName = p.DisplayName,
			money = prof and prof.money or 0,
			eggs = eggs,
			base = prof and prof.base and prof.base.index or 0,
			locked = prof and prof.base and isLocked(prof.base) or false,
		})
	end
	return true, "", { players = list, state = state }
end

adminActions.giveMoney = function(_admin, args)
	local t = target(args)
	local amount = num(args.amount, -1e15, 1e15)
	if not t or not amount or not profiles[t] then
		return false, "Spieler oder Betrag ungültig"
	end
	addMoney(t, amount)
	notify(t, "🎁 Ein Admin hat dir " .. Config.formatMoney(amount) .. " gegeben!", GREEN)
	effect(t, "cash")
	return true, t.DisplayName .. " hat " .. Config.formatMoney(amount) .. " bekommen"
end

adminActions.setMoney = function(_admin, args)
	local t = target(args)
	local amount = num(args.amount, 0, 1e15)
	if not t or not amount or not profiles[t] then
		return false, "Spieler oder Betrag ungültig"
	end
	setMoney(t, amount)
	return true, "Geld von " .. t.DisplayName .. " = " .. Config.formatMoney(amount)
end

adminActions.spawnEgg = function(_admin, args)
	local id = args.id
	if type(id) ~= "string" or not Config.EggsById[id] then
		return false, "Unbekanntes Ei"
	end
	local mut = Config.getMutation(args.mut) and args.mut or nil
	local name = Config.getDisplayName(id, mut)
	if args.where == "base" then
		local t = target(args)
		local prof = t and profiles[t]
		if not prof or not prof.base then
			return false, "Spieler hat keine Basis"
		end
		local idx = findFreeSlot(prof.base)
		if not idx then
			return false, "Basis von " .. t.DisplayName .. " ist voll"
		end
		local egg = makeEgg(id, mut, args.hatched == true)
		egg.Parent = eggsFolder
		placeEgg(egg, prof.base, idx)
		name = Config.getDisplayName(id, mut, args.hatched == true)
		notify(t, "🎁 Ein Admin hat dir " .. name .. " geschenkt!", GREEN)
		effect(t, "success")
		return true, name .. " → Basis von " .. t.DisplayName
	end
	spawnConveyorEgg(id, mut, CONV_START + 10 + rng:NextNumber() * 40, true)
	return true, name .. " aufs Laufband gesetzt"
end

adminActions.eggRain = function(admin, args)
	local count = num(args.count, 1, 40) or 15
	local luck = num(args.luck, 1, 1000) or 25
	announceEvent:FireAllClients("🌧️ EIERREGEN! Schnell zum Laufband!", admin.DisplayName)
	task.spawn(function()
		for _ = 1, count do
			spawnConveyorEgg(Config.rollEgg(luck, rng), nil, rng:NextNumber(CONV_START + 10, CONV_END - 60), true)
			task.wait(0.3)
		end
	end)
	return true, math.floor(count) .. " Eier regnen herab"
end

adminActions.luck = function(admin, args)
	local mult = num(args.mult, 1, 100) or 1
	local minutes = num(args.minutes, 0, 120) or 5
	state.luck = mult
	state.luckEnds = workspace:GetServerTimeNow() + minutes * 60
	publishState()
	if mult > 1 then
		announceEvent:FireAllClients("🍀 Glück x" .. mult .. " für " .. minutes .. " Minuten!", admin.DisplayName)
	end
	return true, "Glück = x" .. mult
end

adminActions.incomeBoost = function(admin, args)
	local mult = num(args.mult, 1, 100) or 1
	local minutes = num(args.minutes, 0, 120) or 5
	state.incomeMult = mult
	state.incomeEnds = workspace:GetServerTimeNow() + minutes * 60
	publishState()
	if mult > 1 then
		announceEvent:FireAllClients("💰 Geld x" .. mult .. " für " .. minutes .. " Minuten!", admin.DisplayName)
	end
	return true, "Einkommen = x" .. mult
end

adminActions.hatchAll = function(_admin, args)
	local t = nil
	if not args.all then
		t = target(args)
		if not t then
			return false, "Erst einen Spieler auswählen"
		end
	end
	local n = 0
	for egg, d in eggData do
		if d.state == "placed" and not d.hatched and (not t or (d.base and d.base.owner == t)) then
			hatchEgg(egg)
			n += 1
		end
	end
	return true, n .. " Eier sofort geschlüpft"
end

adminActions.hatchBoost = function(admin, args)
	local mult = num(args.mult, 1, 100) or 1
	local minutes = num(args.minutes, 0, 120) or 5
	state.hatchMult = mult
	state.hatchEnds = workspace:GetServerTimeNow() + minutes * 60
	publishState()
	if mult > 1 then
		announceEvent:FireAllClients("🐣 Brüten x" .. mult .. " so schnell für " .. minutes .. " Minuten!", admin.DisplayName)
	end
	return true, "Brut-Tempo = x" .. mult
end

adminActions.spawnRate = function(_admin, args)
	local interval = num(args.interval, 0.3, 30)
	if not interval then
		return false, "Ungültiger Wert"
	end
	state.spawnInterval = interval
	publishState()
	return true, "Neues Ei alle " .. interval .. " s"
end

adminActions.clearConveyor = function(_admin, _args)
	local n = 0
	for egg, d in eggData do
		if d.state == "conveyor" then
			if d.tween then
				d.tween:Cancel()
			end
			destroyEgg(egg)
			n += 1
		end
	end
	return true, n .. " Eier vom Band entfernt"
end

adminActions.lockBase = function(_admin, args)
	local t = target(args)
	local prof = t and profiles[t]
	if not prof or not prof.base then
		return false, "Spieler hat keine Basis"
	end
	if args.lock then
		prof.base.lockedUntil = os.clock() + (num(args.seconds, 1, 3600) or Config.LockDuration)
		return true, "Basis von " .. t.DisplayName .. " gesperrt"
	end
	prof.base.lockedUntil = 0
	return true, "Basis von " .. t.DisplayName .. " entsperrt"
end

adminActions.clearBase = function(_admin, args)
	local t = target(args)
	local prof = t and profiles[t]
	if not prof or not prof.base then
		return false, "Spieler hat keine Basis"
	end
	clearBase(prof.base)
	return true, "Basis von " .. t.DisplayName .. " geleert"
end

adminActions.resetData = function(_admin, args)
	local t = target(args)
	local prof = t and profiles[t]
	if not prof then
		return false, "Spieler nicht gefunden"
	end
	if prof.carrying then
		returnEgg(t)
	end
	if prof.base then
		clearBase(prof.base)
	end
	setMoney(t, Config.StartMoney)
	task.spawn(writeData, t, snapshot(t))
	notify(t, "Dein Spielstand wurde von einem Admin zurückgesetzt.", RED)
	return true, "Spielstand von " .. t.DisplayName .. " zurückgesetzt"
end

adminActions.teleportTo = function(admin, args)
	local t = target(args)
	local troot = t and getRoot(t)
	if not troot or not admin.Character then
		return false, "Spieler nicht erreichbar"
	end
	admin.Character:PivotTo(troot.CFrame * CFrame.new(0, 0, 4))
	return true, "Zu " .. t.DisplayName .. " teleportiert"
end

adminActions.bring = function(admin, args)
	local t = target(args)
	local aroot = getRoot(admin)
	if not t or not t.Character or not aroot then
		return false, "Spieler nicht erreichbar"
	end
	t.Character:PivotTo(aroot.CFrame * CFrame.new(0, 0, -4))
	return true, t.DisplayName .. " hergeholt"
end

adminActions.speed = function(_admin, args)
	local t = target(args)
	local value = num(args.value, 0, 200)
	local prof = t and profiles[t]
	if not prof or not value then
		return false, "Ungültig"
	end
	prof.walkSpeed = value
	local _, hum = getRoot(t)
	if hum and not prof.carrying then
		hum.WalkSpeed = value
	end
	return true, "Tempo von " .. t.DisplayName .. " = " .. value
end

adminActions.kick = function(admin, args)
	local t = target(args)
	if not t then
		return false, "Spieler nicht gefunden"
	end
	if t == admin then
		return false, "Du kannst dich nicht selbst kicken"
	end
	t:Kick("Du wurdest von einem Admin aus Eier-Raub entfernt.")
	return true, t.DisplayName .. " wurde gekickt"
end

adminActions.announce = function(admin, args)
	local text = args.text
	if type(text) ~= "string" or #text == 0 or #text > 200 then
		return false, "Text fehlt oder ist zu lang (max. 200 Zeichen)"
	end
	local ok, filtered = pcall(function()
		local result = TextService:FilterStringAsync(text, admin.UserId)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		return false, "Textfilter nicht erreichbar"
	end
	announceEvent:FireAllClients(filtered, admin.DisplayName)
	return true, "Durchsage gesendet"
end

adminFunction.OnServerInvoke = function(plr: Player, action, args)
	if not isAdmin(plr) then
		return false, "Keine Admin-Rechte"
	end
	local handler = type(action) == "string" and adminActions[action]
	if not handler then
		return false, "Unbekannte Aktion"
	end
	if type(args) ~= "table" then
		args = {}
	end
	local ok, success, message, data = pcall(handler, plr, args)
	if not ok then
		warn("[Eier-Raub] Admin-Aktion fehlgeschlagen:", success)
		return false, "Fehler: " .. tostring(success)
	end
	return success, message, data
end

---------------------------------------------------------------------
-- Schleifen
---------------------------------------------------------------------
-- Laufband: neue Eier
task.spawn(function()
	while true do
		spawnConveyorEgg(Config.rollEgg(state.luck, rng))
		task.wait(state.spawnInterval)
	end
end)

-- Einkommen: jede Sekunde
task.spawn(function()
	while true do
		task.wait(1)
		local mult = state.incomeMult
		for _, base in bases do
			local owner = base.owner
			if owner then
				local total = 0
				for _, slot in base.slots do
					local egg = slot.egg
					local d = egg and eggData[egg]
					if egg and d then
						if d.hatched then
							local income = Config.getIncome(d.id, d.mut) * mult
							slot.stored += income
							total += income
						else
							-- Ei brütet noch: kein Geld, aber Fortschritt
							d.progress += state.hatchMult
							if d.progress >= Config.getHatchTime(d.id) then
								hatchEgg(egg)
							else
								updateInfo(egg, d)
							end
						end
					end
					updatePlate(slot)
				end
				owner:SetAttribute("Income", total)
			end
		end
	end
end)

-- Diebe, Sperren, Schilder, Events
task.spawn(function()
	while true do
		task.wait(0.15)

		for plr, prof in profiles do
			local egg = prof.carrying
			if egg then
				local root, hum = getRoot(plr)
				if not egg.Parent or not root or not hum or hum.Health <= 0 then
					returnEgg(plr, "Das Ei ist zurück beim Besitzer.")
				elseif prof.base and isInside(prof.base, root.Position) then
					deliverEgg(plr)
				end
			end
		end

		local now = os.clock()
		for _, base in bases do
			local locked = now < base.lockedUntil
			local owner = base.owner
			if locked and owner then
				for _, other in Players:GetPlayers() do
					if other ~= owner then
						local root = getRoot(other)
						if root and isInside(base, root.Position) and other.Character then
							other.Character:PivotTo(base.ejectCFrame)
							notify(other, "🔒 Diese Basis ist gesperrt!", RED)
						end
					end
				end
			end

			base.barrier.Transparency = locked and 0.25 or 1
			base.signName.Text = owner and (owner.DisplayName .. "s Basis") or "Freie Basis"
			if locked then
				local remaining = math.ceil(base.lockedUntil - now)
				base.signStatus.Text = "🔒 GESPERRT " .. remaining .. "s"
				base.signStatus.TextColor3 = RED
				base.lockLabel.Text = "🔒 " .. remaining .. "s"
				base.lockPad.Color = Color3.fromRGB(120, 120, 130)
			else
				base.signStatus.Text = owner and "🔓 OFFEN" or ""
				base.signStatus.TextColor3 = GREEN
				base.lockLabel.Text = "🔒 SPERREN"
				base.lockPad.Color = Color3.fromRGB(255, 60, 60)
			end
		end

		local serverNow = workspace:GetServerTimeNow()
		if state.luck > 1 and serverNow > state.luckEnds then
			state.luck = 1
			publishState()
			announceEvent:FireAllClients("Das Glücks-Event ist vorbei.", "Server")
		end
		if state.incomeMult > 1 and serverNow > state.incomeEnds then
			state.incomeMult = 1
			publishState()
			announceEvent:FireAllClients("Das Geld-Event ist vorbei.", "Server")
		end
		if state.hatchMult > 1 and serverNow > state.hatchEnds then
			state.hatchMult = 1
			publishState()
			announceEvent:FireAllClients("Das Brut-Event ist vorbei.", "Server")
		end
	end
end)

print("[Eier-Raub] Server gestartet – " .. #bases .. " Basen, " .. #Config.Eggs .. " Eier.")
