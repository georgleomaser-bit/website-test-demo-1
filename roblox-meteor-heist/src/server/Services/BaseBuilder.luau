-- Baut die Basen (von MapBuilder.Build aufgerufen) und ändert sie zur Laufzeit (PlotService):
--   • 8 OFFENE Basen (je 4 pro Seite, Eingang zur Parade, 80 x 90 Studs): bunter Noppenboden, niedriger
--     Rand an Seiten + hinten, vorne offen mit Laser-Sperre, großer Lock-Knopf, Geld-Pad, Namensschild
--   • Slot-Anker (unsichtbar): 18 im Erdgeschoss + je 6 auf Stockwerk 2 und 3 (immer da, Nummern fest)
--   • STOCKWERKE (Config.BaseFloors): offene Plattformen über dem hinteren Teil, Treppe hoch.
--     Nur gebaut, wenn gekauft (SetFloors)
--   • BASE-LOOK (Config.BaseLooks, Stufe 1-5): Zaun, Laternen, Torbogen, Fahnen, Bodenrand (SetLook)
-- Lokales System einer Base: -Z = Eingang (zur Parade), X = Breite, Z = Tiefe.
-- Stil: schlicht, bunt, blockig (Plastic + Noppen), wenig Neon, wenige Teile.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local BaseBuilder = {}

-- -------------------------------------------------------------------
-- MASSE & FARBEN (Studs)
-- -------------------------------------------------------------------
local PLOT_WIDTH = 80 -- lokales X
local PLOT_DEPTH = 90 -- lokales Z
local HALF_X = PLOT_WIDTH / 2
local HALF_Z = PLOT_DEPTH / 2
local PLOT_X = 79 -- Abstand Basis-Mitte <-> Map-Mitte (Eingang bei x = ±34, Rückseite bei x = ±124)
local PLOT_Z = { -135, -45, 45, 135 } -- 10 Studs Lücke zwischen den Basen
local PLOT_FLOOR_TOP = 1
local FENCE_HEIGHT = 2 -- niedriger Rand (drüberspringen geht – Schutz macht der Lock-Rauswurf)
local FENCE_THICK = 1
local BARRIER_HEIGHT = 10
local POST_SIZE = 1.4 -- Laser-Pfosten an beiden Seiten des Eingangs
local LASER_BEAMS = 5 -- so viele Laser-Streifen zeichnet der Client
local POST_X = 40 - POST_SIZE / 2 + 0.1 -- Pfosten-Mitte (außen 0,1 über den Zaun -> kein Flackern)
local GATE_Z = -45 + 0.6 -- Laser-Sperre + Pfosten (vor der Zaun-Stirnseite)

-- Stockwerke: Abstand von Boden zu Boden, Rand oben, Platte
local FLOOR_GAP = 16
local FLOOR_THICK = 1
local RIM_HEIGHT = 1.5
local STAIR_WIDTH = 6
local PILLAR = 2

local PLOT_COLORS = {
	Color3.fromRGB(196, 40, 28),
	Color3.fromRGB(218, 133, 65),
	Color3.fromRGB(245, 205, 48),
	Color3.fromRGB(75, 151, 75),
	Color3.fromRGB(13, 105, 172),
	Color3.fromRGB(4, 175, 236),
	Color3.fromRGB(107, 50, 124),
	Color3.fromRGB(255, 102, 204),
}
local WOOD_COLOR = Color3.fromRGB(124, 92, 70)
local TREE_COLORS = {
	Color3.fromRGB(60, 170, 60),
	Color3.fromRGB(80, 190, 70),
	Color3.fromRGB(45, 150, 55),
	Color3.fromRGB(100, 200, 80),
}
local FLAG_COLORS = {
	Color3.fromRGB(196, 40, 28),
	Color3.fromRGB(245, 205, 48),
	Color3.fromRGB(13, 105, 172),
	Color3.fromRGB(75, 151, 75),
	Color3.fromRGB(255, 102, 204),
}
local WHITE = Color3.new(1, 1, 1)

-- Unsichtbare Slot-Anker im Erdgeschoss: versetztes Raster (5-4-5-4 = 18), Reihe 1 nahe Eingang.
-- Abstand 13 Studs + etwas Zufall (fester Seed: alle Basen gleich).
local SLOT_ROWS = {
	{ Z = -14, Count = 5 },
	{ Z = -1, Count = 4 },
	{ Z = 12, Count = 5 },
	{ Z = 25, Count = 4 },
}
local SLOT_SPACING = 13
local SLOT_JITTER = 1
local SLOT_YAW = math.rad(12)
local SLOT_SEED = 4711
-- Anker-Kasten vom Boden bis 3 Studs hoch: durchlaufen = Geld einsammeln (Touched),
-- PlotService.SlotTopCFrame nimmt die Unterkante (= Bodenhöhe)
local SLOT_ANCHOR_SIZE = Vector3.new(6, 3, 6)

-- Stockwerke (Index 1 = Stockwerk 2). MinZ/MaxZ = Plattform (lokal), Stairs = Treppe darunter
-- (X-Mitte, Start-Z unten, End-Z oben), Gap = offene Seite im vorderen Rand für die Treppe, Slots = (X, Z)
type StoryDef = {
	MinZ: number,
	StairX: number,
	StairFromZ: number,
	StairToZ: number,
	GapMinX: number,
	GapMaxX: number,
	Slots: { Vector2 },
}
local STORIES: { StoryDef } = {
	{
		MinZ = 2,
		StairX = -35.5,
		StairFromZ = -18,
		StairToZ = 2,
		GapMinX = -HALF_X,
		GapMaxX = -32.5,
		Slots = {
			Vector2.new(-22, 12),
			Vector2.new(0, 12),
			Vector2.new(22, 12),
			Vector2.new(-22, 32),
			Vector2.new(0, 32),
			Vector2.new(22, 32),
		},
	},
	{
		MinZ = 20,
		StairX = 35.5,
		StairFromZ = 4,
		StairToZ = 20,
		GapMinX = 32.5,
		GapMaxX = HALF_X,
		Slots = {
			Vector2.new(-22, 28),
			Vector2.new(0, 28),
			Vector2.new(22, 28),
			Vector2.new(-22, 39),
			Vector2.new(0, 39),
			Vector2.new(22, 39),
		},
	},
}

-- Base-Look je Stufe (1-5): Zaunfarbe/-material, Lampenfarbe, Torbogen, Fahnen, Bodenrand
type LookStyle = {
	Fence: Color3,
	FenceMat: Enum.Material,
	Cap: Color3?, -- Leuchtkante oben auf dem Zaun (nur Stufe 5)
	Lamp: Color3,
	Arch: Color3?,
	ArchMat: Enum.Material,
	Flags: number,
	Trim: Color3?,
	Lanterns: number,
}
local LOOKS: { LookStyle } = {
	{
		Fence = Color3.fromRGB(242, 243, 243),
		FenceMat = Enum.Material.Plastic,
		Lamp = Color3.fromRGB(255, 220, 120),
		ArchMat = Enum.Material.Plastic,
		Flags = 0,
		Lanterns = 2,
	},
	{
		Fence = Color3.fromRGB(160, 110, 70),
		FenceMat = Enum.Material.Wood,
		Lamp = Color3.fromRGB(255, 220, 120),
		Arch = Color3.fromRGB(124, 92, 70),
		ArchMat = Enum.Material.Wood,
		Flags = 0,
		Lanterns = 4,
	},
	{
		Fence = Color3.fromRGB(150, 150, 160),
		FenceMat = Enum.Material.Slate,
		Lamp = Color3.fromRGB(255, 200, 90),
		Arch = Color3.fromRGB(130, 130, 140),
		ArchMat = Enum.Material.Slate,
		Flags = 2,
		Trim = Color3.fromRGB(110, 110, 120),
		Lanterns = 4,
	},
	{
		Fence = Color3.fromRGB(120, 210, 255),
		FenceMat = Enum.Material.SmoothPlastic,
		Lamp = Color3.fromRGB(110, 230, 255),
		Arch = Color3.fromRGB(90, 190, 255),
		ArchMat = Enum.Material.SmoothPlastic,
		Flags = 4,
		Trim = Color3.fromRGB(80, 170, 240),
		Lanterns = 6,
	},
	{
		Fence = Color3.fromRGB(255, 200, 40),
		FenceMat = Enum.Material.SmoothPlastic,
		Cap = Color3.fromRGB(255, 240, 150),
		Lamp = Color3.fromRGB(255, 230, 90),
		Arch = Color3.fromRGB(255, 190, 30),
		ArchMat = Enum.Material.SmoothPlastic,
		Flags = 6,
		Trim = Color3.fromRGB(255, 210, 60),
		Lanterns = 6,
	},
}

-- -------------------------------------------------------------------
-- BAU-HELFER
-- -------------------------------------------------------------------
local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false -- nur Pads brauchen Touched
	for key, value in pairs(props) do
		if key ~= "Parent" then
			(p :: any)[key] = value
		end
	end
	p.Parent = props.Parent
	return p
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function anchorPart(name: string, cframe: CFrame, parent: Instance): Part
	return part({
		Name = name,
		Size = Vector3.new(1, 1, 1),
		CFrame = cframe,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
		Parent = parent,
	})
end

local function addStroke(label: GuiObject, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness
	stroke.Color = Color3.new(0, 0, 0)
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
end

-- Schild in Studs-Größe (wächst mit der Entfernung mit wie ein echtes Schild)
local function bigLabel(
	parent: Instance,
	width: number,
	height: number,
	offset: Vector3,
	maxDistance: number
): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(width, height)
	gui.StudsOffset = offset
	gui.MaxDistance = maxDistance
	gui.LightInfluence = 0
	gui.Parent = parent
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = WHITE
	addStroke(label, 4)
	label.Parent = gui
	return label
end

-- Blockiger Roblox-Baum: Stamm + großer Blätterblock + kleiner Block obendrauf (3 Teile)
local function blockTree(parent: Instance, cf: CFrame, scale: number, color: Color3)
	local trunkHeight = 6 * scale
	local trunkWidth = 2 * scale
	part({
		Name = "Trunk",
		Size = Vector3.new(trunkWidth, trunkHeight, trunkWidth),
		CFrame = cf * CFrame.new(0, trunkHeight / 2, 0),
		Material = Enum.Material.Plastic,
		Color = WOOD_COLOR,
		Parent = parent,
	})
	local leafWidth, leafHeight = 8 * scale, 5 * scale
	local leaves = part({
		Name = "Leaves",
		Size = Vector3.new(leafWidth, leafHeight, leafWidth),
		CFrame = cf * CFrame.new(0, trunkHeight + leafHeight / 2, 0),
		Material = Enum.Material.Plastic,
		Color = color,
		CanCollide = false,
		Parent = parent,
	})
	leaves.TopSurface = Enum.SurfaceType.Studs
	local topWidth, topHeight = 5 * scale, 3 * scale
	local crown = part({
		Name = "Leaves",
		Size = Vector3.new(topWidth, topHeight, topWidth),
		CFrame = cf * CFrame.new(0, trunkHeight + leafHeight + topHeight / 2, 0),
		Material = Enum.Material.Plastic,
		Color = color,
		CanCollide = false,
		Parent = parent,
	})
	crown.TopSurface = Enum.SurfaceType.Studs
end

-- Laterne: Pfosten + leuchtender Würfel. Nur Würfel namens "LanternLamp" bekommen nachts ein Licht
-- (GraphicsService) – die Extra-Laternen heißen "LanternGlow" (Lichter-Budget).
local function lantern(parent: Instance, cf: CFrame, postColor: Color3, lampColor: Color3, lampName: string)
	local height = 6
	part({
		Name = "LanternPost",
		Size = Vector3.new(0.8, height, 0.8),
		CFrame = cf * CFrame.new(0, height / 2, 0),
		Material = Enum.Material.Plastic,
		Color = postColor,
		Parent = parent,
	})
	part({
		Name = lampName,
		Size = Vector3.new(1.6, 1.6, 1.6),
		CFrame = cf * CFrame.new(0, height + 0.8, 0),
		Material = Enum.Material.Neon,
		Color = lampColor,
		CanCollide = false,
		CastShadow = false,
		Parent = parent,
	})
end

-- Fahne: Stange + Tuch
local function flag(parent: Instance, cf: CFrame, color: Color3, height: number)
	part({
		Name = "FlagPole",
		Size = Vector3.new(0.5, height, 0.5),
		CFrame = cf * CFrame.new(0, height / 2, 0),
		Material = Enum.Material.Plastic,
		Color = WHITE,
		CastShadow = false,
		Parent = parent,
	})
	part({
		Name = "Flag",
		Size = Vector3.new(3.4, 2.2, 0.2),
		CFrame = cf * CFrame.new(1.95, height - 1.3, 0),
		Material = Enum.Material.Plastic,
		Color = color,
		CanCollide = false,
		CastShadow = false,
		Parent = parent,
	})
end

-- Lokale Positionen (X, Z, Drehung) der 18 Erdgeschoss-Anker in Slot-Reihenfolge
local function groundLayout(): { { X: number, Z: number, Yaw: number } }
	local rng = Random.new(SLOT_SEED)
	local list = {}
	for _, row in ipairs(SLOT_ROWS) do
		for i = 1, row.Count do
			local x = (i - (row.Count + 1) / 2) * SLOT_SPACING
			table.insert(list, {
				X = x + rng:NextNumber(-SLOT_JITTER, SLOT_JITTER),
				Z = row.Z + rng:NextNumber(-SLOT_JITTER, SLOT_JITTER),
				Yaw = rng:NextNumber(-SLOT_YAW, SLOT_YAW),
			})
		end
	end
	return list
end

-- Wie viele Stockwerke es geben kann (Erdgeschoss + gebaute Layouts, begrenzt durch Config.BaseFloors)
function BaseBuilder.MaxFloors(): number
	local defs = (Config :: any).BaseFloors
	local count = type(defs) == "table" and #defs or 0
	return 1 + math.min(count, #STORIES)
end

-- Bodenhöhe (lokal) eines Stockwerks (1 = Erdgeschoss)
function BaseBuilder.FloorTop(floor: number): number
	return PLOT_FLOOR_TOP + (floor - 1) * FLOOR_GAP
end

-- Obergrenze für PlotService.IsInside (lokales Y): höchster gebauter Boden + Luft zum Springen
local function topY(floors: number): number
	return 40 + (floors - 1) * FLOOR_GAP
end

-- -------------------------------------------------------------------
-- EINE BASE
-- -------------------------------------------------------------------
local function buildPlot(index: number, cf: CFrame, color: Color3, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model:SetAttribute("PlotIndex", index)
	model:SetAttribute("OwnerUserId", 0)
	model:SetAttribute("LockedUntil", 0)
	model:SetAttribute("BaseFloors", 1)
	model:SetAttribute("BaseLook", 1)

	local top = PLOT_FLOOR_TOP
	-- Boden: kräftige Plastikfarbe mit Noppen. BaseFloor = hier dürfen Fallen stehen (GadgetService)
	local floorPart = part({
		Name = "Floor",
		Size = Vector3.new(PLOT_WIDTH, top, PLOT_DEPTH),
		CFrame = cf * CFrame.new(0, top / 2, 0),
		Material = Enum.Material.Plastic,
		Color = color,
		Parent = model,
	})
	floorPart.TopSurface = Enum.SurfaceType.Studs
	floorPart:SetAttribute("BaseFloor", true)
	model.PrimaryPart = floorPart

	-- Niedriger Rand: hinten über die ganze Breite, Seiten enden STUMPF an der Rückwand (kein Z-Fighting)
	local fences: { BasePart } = {}
	local function fence(name: string, size: Vector3, offset: CFrame)
		local p = part({
			Name = name,
			Size = size,
			CFrame = cf * offset,
			Material = Enum.Material.Plastic,
			Color = LOOKS[1].Fence,
			Parent = model,
		})
		p.TopSurface = Enum.SurfaceType.Studs
		table.insert(fences, p)
	end
	local fenceY = top + FENCE_HEIGHT / 2
	fence(
		"BackFence",
		Vector3.new(PLOT_WIDTH, FENCE_HEIGHT, FENCE_THICK),
		CFrame.new(0, fenceY, HALF_Z - FENCE_THICK / 2)
	)
	local sideLength = PLOT_DEPTH - FENCE_THICK
	for _, s in ipairs({ -1, 1 }) do
		fence(
			"SideFence",
			Vector3.new(FENCE_THICK, FENCE_HEIGHT, sideLength),
			CFrame.new(s * (HALF_X - FENCE_THICK / 2), fenceY, -FENCE_THICK / 2)
		)
	end

	-- Laser-Sperre vorne: Barrier = Kraftfeld (PlotService), die Laser-Streifen zeichnet der Client
	-- zwischen den beiden Pfosten (fahren beim Sperren sichtbar zu).
	local barrier = part({
		Name = "Barrier",
		Size = Vector3.new(PLOT_WIDTH - 2 * POST_SIZE - 0.2, BARRIER_HEIGHT, 0.4),
		CFrame = cf * CFrame.new(0, top + BARRIER_HEIGHT / 2, GATE_Z),
		Material = Enum.Material.ForceField,
		Color = Color3.fromRGB(255, 40, 40),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
		Parent = model,
	})
	barrier:SetAttribute("Beams", LASER_BEAMS)
	for _, s in ipairs({ -1, 1 }) do
		local post = part({
			Name = s < 0 and "LaserPostL" or "LaserPostR",
			Size = Vector3.new(POST_SIZE, BARRIER_HEIGHT, POST_SIZE),
			CFrame = cf * CFrame.new(s * POST_X, top + BARRIER_HEIGHT / 2, GATE_Z),
			Material = Enum.Material.Plastic,
			Color = Color3.fromRGB(60, 60, 70),
			Parent = model,
		})
		post.TopSurface = Enum.SurfaceType.Studs
		-- rote Linse innen (zeigt zur Mitte)
		part({
			Name = "Lens",
			Size = Vector3.new(0.2, BARRIER_HEIGHT - 1, 0.6),
			CFrame = post.CFrame * CFrame.new(-s * (POST_SIZE / 2 + 0.1), 0, 0),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 60, 60),
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
			Parent = model,
		})
	end
	-- großer Countdown mitten über dem Eingang (für Diebe gut sichtbar)
	local barrierLabel = bigLabel(barrier, 14, 3.5, Vector3.new(0, BARRIER_HEIGHT / 2 + 1, 0), 220)
	barrierLabel.Text = ""

	-- Unsichtbare Slot-Anker (Reihenfolge = Slot-Nummer): erst Erdgeschoss, dann Stockwerk 2, 3.
	-- CanTouch: durchlaufen = Geld einsammeln (PlotService), CanQuery aus (Fallen-Strahl, Prompts).
	local slots: { BasePart } = {}
	local function addSlot(localCf: CFrame)
		local number = #slots + 1
		slots[number] = part({
			Name = "Slot" .. number,
			Size = SLOT_ANCHOR_SIZE,
			CFrame = cf * localCf,
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = true,
			CastShadow = false,
			Parent = model,
		})
		return number
	end
	for _, spot in ipairs(groundLayout()) do
		addSlot(CFrame.new(spot.X, top + SLOT_ANCHOR_SIZE.Y / 2, spot.Z) * CFrame.Angles(0, spot.Yaw, 0))
	end
	local groundCount = #slots
	local floorSlots: { [number]: { number } } = {}
	local rng = Random.new(SLOT_SEED + 1)
	for i, story in ipairs(STORIES) do
		local floor = i + 1
		local def = (Config :: any).BaseFloors and (Config :: any).BaseFloors[i]
		local want = math.clamp(math.floor(tonumber(def and def.Slots) or #story.Slots), 0, #story.Slots)
		local list = {}
		local y = BaseBuilder.FloorTop(floor) + SLOT_ANCHOR_SIZE.Y / 2
		for n = 1, want do
			local spot = story.Slots[n]
			local yaw = rng:NextNumber(-SLOT_YAW, SLOT_YAW)
			table.insert(list, addSlot(CFrame.new(spot.X, y, spot.Y) * CFrame.Angles(0, yaw, 0)))
		end
		floorSlots[floor] = list
	end

	-- Geld-Pad vorne links
	local collectPad = part({
		Name = "CollectPad",
		Size = Vector3.new(12, 0.3, 7),
		CFrame = cf * CFrame.new(-22, top + 0.15, -36),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(60, 220, 90),
		CanCollide = false,
		CanTouch = true,
		CastShadow = false,
		Parent = model,
	})
	local collectLabel = bigLabel(collectPad, 9, 2.4, Vector3.new(0, 3.5, 0), 120)
	collectLabel.Text = "💰 $0"

	-- Großer Lock-Knopf vorne rechts: Sockel (begehbar) + roter Knopf (drückt sich ein, PlotService)
	local socket = part({
		Name = "LockSocket",
		Size = Vector3.new(8, 0.6, 8),
		CFrame = cf * CFrame.new(22, top + 0.3, -36),
		Material = Enum.Material.Plastic,
		Color = Color3.fromRGB(60, 60, 70),
		Parent = model,
	})
	socket.TopSurface = Enum.SurfaceType.Studs
	local buttonUp = cf * CFrame.new(22, top + 0.6 + 0.7, -36)
	local lockPad = part({
		Name = "LockPad",
		Size = Vector3.new(5.5, 1.4, 5.5),
		CFrame = buttonUp,
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(230, 60, 60),
		CanCollide = false,
		CanTouch = true,
		Parent = model,
	})
	lockPad.TopSurface = Enum.SurfaceType.Studs
	local lockLabel = bigLabel(lockPad, 10, 3, Vector3.new(0, 4.5, 0), 160)
	lockLabel.Text = "🔒 LOCK"

	-- Deko: Laternen + Look-Teile (SetLook), blockige Bäume hinten in den Ecken
	folder("Look", model)
	local deco = folder("Deco", model)
	for _, s in ipairs({ -1, 1 }) do
		blockTree(deco, cf * CFrame.new(s * 33, top, 38), 0.9, TREE_COLORS[(index + s) % #TREE_COLORS + 1])
	end

	-- Großes Namensschild über dem Eingang: Avatar-Kopf + Name (PlotService setzt Bild + Text)
	local signPart = anchorPart("Sign", cf * CFrame.new(0, top + 21, -HALF_Z + 2), model)
	local signGui = Instance.new("BillboardGui")
	signGui.Name = "NameSign"
	signGui.Size = UDim2.fromScale(30, 7)
	signGui.MaxDistance = 400
	signGui.LightInfluence = 0
	signGui.Parent = signPart
	local board = Instance.new("Frame")
	board.Name = "Board"
	board.Size = UDim2.fromScale(1, 1)
	board.BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.35)
	board.BackgroundTransparency = 0.1
	board.Parent = signGui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = board
	local boardStroke = Instance.new("UIStroke")
	boardStroke.Thickness = 4
	boardStroke.Color = Color3.new(0, 0, 0)
	boardStroke.Parent = board
	local signImage = Instance.new("ImageLabel")
	signImage.Name = "Avatar"
	signImage.AnchorPoint = Vector2.new(0, 0.5)
	signImage.Position = UDim2.new(0.02, 0, 0.5, 0)
	signImage.Size = UDim2.fromScale(0.85, 0.85)
	signImage.SizeConstraint = Enum.SizeConstraint.RelativeYY
	signImage.BackgroundColor3 = WHITE
	signImage.BackgroundTransparency = 0.2
	signImage.Image = ""
	signImage.Parent = board
	local imageCorner = Instance.new("UICorner")
	imageCorner.CornerRadius = UDim.new(0.25, 0)
	imageCorner.Parent = signImage
	local signLabel = Instance.new("TextLabel")
	signLabel.Name = "Name"
	signLabel.BackgroundTransparency = 1
	signLabel.Position = UDim2.fromScale(0.27, 0.1)
	signLabel.Size = UDim2.fromScale(0.7, 0.8)
	signLabel.Font = Enum.Font.FredokaOne
	signLabel.TextScaled = true
	signLabel.TextColor3 = WHITE
	signLabel.Text = "Freie Base"
	addStroke(signLabel, 3)
	signLabel.Parent = board

	folder("Floors", model)
	folder("CashPads", model)
	local meteorFolder = folder("Meteors", model)
	model.Parent = parent

	local plot = {
		Index = index,
		Model = model,
		CFrame = cf,
		-- HalfSize = größere Hälfte (alter Code); genau: HalfSizeX (Breite) / HalfSizeZ (Tiefe), lokal
		HalfSize = math.max(HALF_X, HALF_Z),
		HalfSizeX = HALF_X,
		HalfSizeZ = HALF_Z,
		Color = color,
		Owner = nil :: Player?,
		Slots = slots,
		GroundSlots = groundCount, -- Slots 1..GroundSlots liegen im Erdgeschoss
		FloorSlots = floorSlots, -- [2] = { 19..24 }, [3] = { 25..30 }
		MeteorParts = {} :: { [number]: Instance },
		CashPads = {} :: { [number]: BasePart },
		MeteorFolder = meteorFolder,
		CollectPad = collectPad,
		CollectLabel = collectLabel,
		LockPad = lockPad,
		LockPadUp = buttonUp, -- Ruhelage des Knopfs (gedrückt = 0,9 tiefer)
		LockLabel = lockLabel,
		Barrier = barrier,
		BarrierLabel = barrierLabel,
		SignLabel = signLabel,
		SignImage = signImage,
		Fences = fences,
		Floors = 1, -- gebaute Stockwerke (SetFloors)
		Look = 0, -- gebaute Look-Stufe (SetLook)
		TopY = topY(1),
		LockedUntil = 0,
		-- Spawn: vorne in der Mitte zwischen Geld-Pad und Lock-Knopf
		SpawnCFrame = cf * CFrame.new(0, top + 3, -30),
		-- Rauswurf: 8 Studs vor dem Eingang auf der Wiese
		EntranceCFrame = cf * CFrame.new(0, 4, -HALF_Z - 8),
	}
	BaseBuilder.SetLook(plot, 1)
	return plot
end

-- Alle Basen (Ordner "Plots" – der Client sucht ihn!)
function BaseBuilder.BuildPlots(map: Instance): { any }
	local plotsFolder = folder("Plots", map)
	local maxPlots = math.clamp(math.floor(tonumber((Config :: any).MaxPlots) or 8), 1, 2 * #PLOT_Z)
	local plots = {}
	for _, side in ipairs({ -1, 1 }) do
		for _, z in ipairs(PLOT_Z) do
			local index = #plots + 1
			if index > maxPlots then
				break
			end
			local center = Vector3.new(side * PLOT_X, 0, z)
			-- Eingang (lokales -Z) zeigt zur Parade in der Mitte
			local cf = CFrame.lookAt(center, center + Vector3.new(-side, 0, 0))
			table.insert(plots, buildPlot(index, cf, PLOT_COLORS[(index - 1) % #PLOT_COLORS + 1], plotsFolder))
		end
	end
	return plots
end

-- -------------------------------------------------------------------
-- STOCKWERKE
-- -------------------------------------------------------------------
local function lookStyle(plot): LookStyle
	return LOOKS[math.clamp(tonumber(plot.Look) or 1, 1, #LOOKS)]
end

-- Ein Stockwerk: Platte mit Noppen, niedriger Rand (vorne mit Lücke für die Treppe), 4 Pfeiler, Treppe
local function buildStory(plot, floor: number, parent: Instance)
	local story = STORIES[floor - 1]
	local cf = plot.CFrame
	local style = lookStyle(plot)
	local model = Instance.new("Model")
	model.Name = "Floor" .. floor
	local floorTop = BaseBuilder.FloorTop(floor)
	local belowTop = BaseBuilder.FloorTop(floor - 1)
	local depth = HALF_Z - story.MinZ
	local midZ = (story.MinZ + HALF_Z) / 2

	local plate = part({
		Name = "Floor",
		Size = Vector3.new(PLOT_WIDTH, FLOOR_THICK, depth),
		CFrame = cf * CFrame.new(0, floorTop - FLOOR_THICK / 2, midZ),
		Material = Enum.Material.Plastic,
		Color = plot.Color:Lerp(WHITE, 0.15),
		Parent = model,
	})
	plate.TopSurface = Enum.SurfaceType.Studs
	plate:SetAttribute("BaseFloor", true)

	local rimY = floorTop + RIM_HEIGHT / 2
	local function rim(size: Vector3, offset: Vector3)
		local p = part({
			Name = "Rim",
			Size = size,
			CFrame = cf * CFrame.new(offset),
			Material = style.FenceMat,
			Color = style.Fence,
			Parent = model,
		})
		p.TopSurface = Enum.SurfaceType.Studs
	end
	rim(Vector3.new(PLOT_WIDTH, RIM_HEIGHT, FENCE_THICK), Vector3.new(0, rimY, HALF_Z - FENCE_THICK / 2))
	for _, s in ipairs({ -1, 1 }) do
		rim(
			Vector3.new(FENCE_THICK, RIM_HEIGHT, depth - FENCE_THICK * 2),
			Vector3.new(s * (HALF_X - FENCE_THICK / 2), rimY, midZ)
		)
	end
	-- vorne: Rand überall außer über der Treppe
	local frontZ = story.MinZ + FENCE_THICK / 2
	local fromX = if story.GapMinX <= -HALF_X then story.GapMaxX else -HALF_X
	local toX = if story.GapMinX <= -HALF_X then HALF_X else story.GapMinX
	rim(Vector3.new(toX - fromX, RIM_HEIGHT, FENCE_THICK), Vector3.new((fromX + toX) / 2, rimY, frontZ))

	-- Pfeiler an den Ecken (stehen auf dem Boden darunter)
	local pillarHeight = floorTop - FLOOR_THICK - belowTop
	for _, s in ipairs({ -1, 1 }) do
		for _, z in ipairs({ story.MinZ + PILLAR / 2 + 0.5, HALF_Z - PILLAR / 2 - 1.5 }) do
			part({
				Name = "Pillar",
				Size = Vector3.new(PILLAR, pillarHeight, PILLAR),
				CFrame = cf * CFrame.new(s * (HALF_X - PILLAR / 2 - 1), belowTop + pillarHeight / 2, z),
				Material = style.FenceMat,
				Color = style.Fence,
				Parent = model,
			})
		end
	end

	-- Treppe: 1 Stud hohe Stufen (Klötze bis zum Boden darunter), oberste Stufe = Bodenhöhe oben
	local steps = math.floor(FLOOR_GAP + 0.5)
	local run = (story.StairToZ - story.StairFromZ) / steps
	local stepColor = plot.Color:Lerp(Color3.new(0, 0, 0), 0.25)
	for i = 1, steps do
		local height = i * (FLOOR_GAP / steps)
		local z = story.StairFromZ + (i - 0.5) * run
		local step = part({
			Name = "Step",
			Size = Vector3.new(STAIR_WIDTH, height, math.abs(run)),
			CFrame = cf * CFrame.new(story.StairX, belowTop + height / 2, z),
			Material = Enum.Material.Plastic,
			Color = if i % 2 == 0 then stepColor else stepColor:Lerp(WHITE, 0.15),
			Parent = model,
		})
		step.TopSurface = Enum.SurfaceType.Studs
	end
	model.Parent = parent
	return model
end

-- Baut genau "count" Stockwerke (1 = nur Erdgeschoss). Fremde/alte Stockwerke werden entfernt.
function BaseBuilder.SetFloors(plot, count: number)
	count = math.clamp(math.floor(tonumber(count) or 1), 1, BaseBuilder.MaxFloors())
	local container = plot.Model:FindFirstChild("Floors")
	if not container then
		container = folder("Floors", plot.Model)
	end
	for floor = 2, #STORIES + 1 do
		local existing = container:FindFirstChild("Floor" .. floor)
		if floor <= count and not existing then
			buildStory(plot, floor, container)
		elseif floor > count and existing then
			existing:Destroy()
		end
	end
	plot.Floors = count
	plot.TopY = topY(count)
	plot.Model:SetAttribute("BaseFloors", count)
end

-- -------------------------------------------------------------------
-- BASE-LOOK (rein optisch)
-- -------------------------------------------------------------------
local function setLookParts(plot, style: LookStyle)
	for _, fencePart in ipairs(plot.Fences) do
		fencePart.Material = style.FenceMat
		fencePart.Color = style.Fence
	end
	local container = plot.Model:FindFirstChild("Floors")
	if container then
		for _, p in ipairs(container:GetDescendants()) do
			if p:IsA("BasePart") and (p.Name == "Rim" or p.Name == "Pillar") then
				p.Material = style.FenceMat
				p.Color = style.Fence
			end
		end
	end
end

function BaseBuilder.SetLook(plot, level: number)
	level = math.clamp(math.floor(tonumber(level) or 1), 1, #LOOKS)
	if plot.Look == level then
		return
	end
	plot.Look = level
	plot.Model:SetAttribute("BaseLook", level)
	local style = LOOKS[level]
	setLookParts(plot, style)

	local old = plot.Model:FindFirstChild("Look")
	if old then
		old:Destroy()
	end
	local look = folder("Look", plot.Model)
	local cf = plot.CFrame
	local top = PLOT_FLOOR_TOP
	local postColor = if level >= 3 then style.Fence else WOOD_COLOR

	-- Laternen: vorne in den Ecken, ab Stufe 2 auch vorne an den Seiten, ab Stufe 4 hinten
	local spots = {
		Vector2.new(35.5, -41),
		Vector2.new(38.2, -25),
		Vector2.new(12, 41.5),
	}
	for i = 1, math.min(#spots, math.ceil(style.Lanterns / 2)) do
		for _, s in ipairs({ -1, 1 }) do
			local lampName = if i == 1 then "LanternLamp" else "LanternGlow"
			lantern(look, cf * CFrame.new(s * spots[i].X, top, spots[i].Y), postColor, style.Lamp, lampName)
		end
	end

	-- Stufe 5: Leuchtkante auf dem Zaun
	if style.Cap then
		for _, fencePart in ipairs(plot.Fences) do
			part({
				Name = "FenceCap",
				Size = Vector3.new(fencePart.Size.X, 0.3, fencePart.Size.Z),
				CFrame = fencePart.CFrame * CFrame.new(0, fencePart.Size.Y / 2 + 0.15, 0),
				Material = Enum.Material.Neon,
				Color = style.Cap,
				CanCollide = false,
				CastShadow = false,
				Parent = look,
			})
		end
	end

	-- Bodenrand (ab Stufe 3): flache Leiste innen am Rand (hinten + Seiten)
	if style.Trim then
		local trimY = top + 0.1
		local inner = FENCE_THICK + 0.75
		for _, data in ipairs({
			{ Vector3.new(PLOT_WIDTH - 2 * FENCE_THICK, 0.2, 1.5), Vector3.new(0, trimY, HALF_Z - inner) },
			{ Vector3.new(1.5, 0.2, PLOT_DEPTH - 2 * FENCE_THICK - 3), Vector3.new(-(HALF_X - inner), trimY, -1.5) },
			{ Vector3.new(1.5, 0.2, PLOT_DEPTH - 2 * FENCE_THICK - 3), Vector3.new(HALF_X - inner, trimY, -1.5) },
		}) do
			local p = part({
				Name = "Trim",
				Size = data[1],
				CFrame = cf * CFrame.new(data[2]),
				Material = Enum.Material.Plastic,
				Color = style.Trim,
				CanQuery = false,
				CastShadow = false,
				Parent = look,
			})
			p.TopSurface = Enum.SurfaceType.Studs
		end
	end

	-- Torbogen über dem Eingang (ab Stufe 2): zwei Säulen außen neben dem Zaun + Balken
	local archColor = style.Arch
	if archColor then
		local archHeight = 11 + level
		for _, s in ipairs({ -1, 1 }) do
			local pillar = part({
				Name = "ArchPillar",
				Size = Vector3.new(2, archHeight, 2),
				CFrame = cf * CFrame.new(s * (HALF_X + 1.5), archHeight / 2, -HALF_Z + 1),
				Material = style.ArchMat,
				Color = archColor,
				Parent = look,
			})
			pillar.TopSurface = Enum.SurfaceType.Studs
		end
		local beam = part({
			Name = "ArchBeam",
			Size = Vector3.new(PLOT_WIDTH + 7, 2, 2.4),
			CFrame = cf * CFrame.new(0, archHeight + 1, -HALF_Z + 1),
			Material = style.ArchMat,
			Color = archColor,
			Parent = look,
		})
		beam.TopSurface = Enum.SurfaceType.Studs
		if level >= 4 then
			part({
				Name = "ArchGlow",
				Size = Vector3.new(PLOT_WIDTH + 7.2, 0.4, 2.6),
				CFrame = beam.CFrame * CFrame.new(0, -0.6, 0),
				Material = Enum.Material.Neon,
				Color = style.Lamp,
				CanCollide = false,
				CastShadow = false,
				Parent = look,
			})
		end
		-- Stufe 5: zwei Fahnen oben auf dem Torbogen
		if style.Flags >= 6 then
			for _, s in ipairs({ -1, 1 }) do
				flag(look, beam.CFrame * CFrame.new(s * (HALF_X - 6), 1, 0), FLAG_COLORS[(plot.Index + s) % 5 + 1], 7)
			end
		end
	end

	-- Fahnen: hinten auf dem Zaun (ab Stufe 3), auf den Laser-Pfosten (ab Stufe 4)
	if style.Flags >= 2 then
		for _, s in ipairs({ -1, 1 }) do
			local base = cf * CFrame.new(s * 20, top + FENCE_HEIGHT, HALF_Z - FENCE_THICK / 2)
			flag(look, base, FLAG_COLORS[(plot.Index + s + 2) % 5 + 1], 10)
		end
	end
	if style.Flags >= 4 then
		for _, s in ipairs({ -1, 1 }) do
			local base = cf * CFrame.new(s * POST_X, top + BARRIER_HEIGHT, GATE_Z)
			flag(look, base, FLAG_COLORS[(plot.Index + s + 4) % 5 + 1], 4)
		end
	end
end

-- -------------------------------------------------------------------
-- GELD-FELDER (eins vor jedem besetzten Slot)
-- -------------------------------------------------------------------
-- Kleines grünes Feld 5 Studs vor dem Slot (Richtung Eingang) mit Betrag-Schild. Gibt (Feld, Label) zurück.
function BaseBuilder.MakeCashPad(plot, slot: number): (BasePart?, TextLabel?)
	local anchor = plot.Slots[slot]
	if not anchor then
		return nil, nil
	end
	local floorCf = anchor.CFrame * CFrame.new(0, -anchor.Size.Y / 2, 0)
	local pad = part({
		Name = "CashPad" .. slot,
		Size = Vector3.new(4, 0.2, 2.2),
		CFrame = floorCf * CFrame.new(0, 0.1, -5.6),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(70, 210, 90),
		CanCollide = false,
		CanQuery = false,
		CanTouch = true,
		CastShadow = false,
	})
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(4.5, 1.3)
	gui.StudsOffset = Vector3.new(0, 1, 0)
	gui.MaxDistance = 45
	gui.LightInfluence = 0
	gui.Parent = pad
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(140, 255, 120)
	label.Text = ""
	addStroke(label, 2)
	label.Parent = gui
	local container = plot.Model:FindFirstChild("CashPads")
	if not container then
		container = folder("CashPads", plot.Model)
	end
	pad.Parent = container
	return pad, label
end

return BaseBuilder
