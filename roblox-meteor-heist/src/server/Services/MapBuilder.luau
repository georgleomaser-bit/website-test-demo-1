-- Baut die komplette Map per Code (wird von PlotService.Init EINMAL aufgerufen):
--   • knallgrüner Roblox-Noppenboden mit Block-Bäumen, Büschen, Zaun und unsichtbaren Randwänden
--   • EI-RENNEN: großes Nester-Feld in der Map-Mitte (kleine + große Nester, Speed-Pads, Renn-Nest)
--   • 8 OFFENE Basen (je 4 pro Seite, Eingang zum Nester-Feld) -> gebaut von BaseBuilder.luau
--  Stil: schlicht, bunt, blockig (Plastic + Noppen), wenig Neon, wenige Teile.
--   • großer Spawn-Platz mit SpawnLocation, Gratis-Zone, Bestenliste und der LAUFBAND-ZONE (Treadmills)
-- Rückgabe von MapBuilder.Build(): siehe Typ "MapResult" unten.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))
local BaseBuilder = require(script.Parent:WaitForChild("BaseBuilder"))

local MapBuilder = {}

export type NestFieldInfo = {
	Folder: Folder, -- Ordner "NestField" (Boden, Nester, Speed-Pads; Attribute = Grenzen der Kreaturen)
	Nests: { BasePart }, -- Teile "Nest" (Attribute NestSize, EggPoint, RaceNest)
}

export type FreeZone = {
	Center: Vector3, -- Mitte der Gratis-Zone, Y = Oberkante des Bodens dort
	Radius: number,
}

export type MapResult = {
	MapFolder: Folder,
	Plots: { any },
	NestField: NestFieldInfo, -- Map-Mitte: Ei-Rennen
	LobbySpawn: CFrame,
	LeaderboardCFrame: CFrame,
	FreeZone: FreeZone,
	TreadmillsFolder: Folder,
	TreadmillSpawn: CFrame, -- Zusatz: Teleport-Ziel für den Knopf "🏃 Laufbänder"
}

type TreadmillDef = {
	Id: string,
	Name: string,
	Price: number,
	Rate: number,
	Color: Color3,
	Rainbow: boolean?,
}

type SignLine = { Name: string, Text: string, Color: Color3, Height: number }

-- -------------------------------------------------------------------
-- MASSE & FARBEN (alle Angaben in Studs)
-- -------------------------------------------------------------------
-- Boden
local GROUND_SIZE = 1024
local GROUND_CENTER_Z = -80
local GROUND_COLOR = Color3.fromRGB(90, 200, 70)

-- Map-Rand (Zaun + unsichtbare Wände)
local EDGE_X = 168 -- Basen-Rückseite bei x = ±124, dahinter (rechts) der Meteor-Run (RunService)
local EDGE_MIN_Z = -406
local EDGE_MAX_Z = 256

-- Ei-Rennen (Nester-Feld in der Map-Mitte, Basen beginnen bei x = ±34)
local FIELD_HALF_X = 33
local FIELD_MIN_Z = -214 -- Spawn-Platz endet bei z = -226
local FIELD_MAX_Z = 246
local FIELD_TOP = 0.2
local FIELD_COLOR = Color3.fromRGB(130, 215, 85)
local NEST_COLOR = Color3.fromRGB(226, 186, 96) -- Stroh
local NEST_INNER_COLOR = Color3.fromRGB(160, 110, 55)
local NEST_GOLD_COLOR = Color3.fromRGB(255, 200, 40)
local NEST_SMALL_SIZE = 6
local NEST_BIG_SIZE = 14
local NEST_RACE_SIZE = 18
-- kleine Nester: 4 Reihen (x), von z = -195 bis 195 alle 15 Studs (vor den Basen bleibt ein Weg frei)
local SMALL_NEST_X = { -23, -14, 14, 23 }
local SMALL_NEST_MIN_Z = -195
local SMALL_NEST_MAX_Z = 195
local SMALL_NEST_STEP = 15
-- große Nester (X, Z): Mitte + weit weg am Ende; das LETZTE ist das Renn-Nest (Gold-Ei)
local BIG_NESTS = {
	Vector2.new(0, -140),
	Vector2.new(0, -50),
	Vector2.new(0, 40),
	Vector2.new(0, 130),
	Vector2.new(-36, 214),
	Vector2.new(36, 214),
	Vector2.new(0, 230),
}
-- Speed-Pads (X, Z): Mitte zwischen den großen Nestern + vor jedem Base-Eingang
local SPEED_PAD_SIZE = 5
local SPEED_PAD_COLOR = Color3.fromRGB(0, 170, 255)
local SPEED_PADS = {
	Vector2.new(0, -190),
	Vector2.new(0, -95),
	Vector2.new(0, -5),
	Vector2.new(0, 85),
	Vector2.new(0, 175),
	Vector2.new(-29.5, -135),
	Vector2.new(-29.5, -45),
	Vector2.new(-29.5, 45),
	Vector2.new(-29.5, 135),
	Vector2.new(29.5, -135),
	Vector2.new(29.5, -45),
	Vector2.new(29.5, 45),
	Vector2.new(29.5, 135),
}
-- Revier der Kreaturen (sie betreten nie eine Base und nie den Spawn-Platz)
local CREATURE_HALF_X = 29
local CREATURE_MIN_Z = -205
local CREATURE_MAX_Z = 240

-- Basen baut BaseBuilder.luau (Maße, Slots, Stockwerke, Look). Hier nur die Holzfarbe der Block-Bäume.
local WOOD_COLOR = Color3.fromRGB(124, 92, 70) -- Reddish brown

-- Spawn-Platz (hinter dem Start-Hangar, -Z)
local PLAZA_MIN_Z = -398
local PLAZA_MAX_Z = -226
local PLAZA_HALF_X = 120
local PLAZA_TOP = 0.2
local PLAZA_CENTER = Vector3.new(0, PLAZA_TOP, (PLAZA_MIN_Z + PLAZA_MAX_Z) / 2)
local SPAWN_Z = -318
local FREE_ZONE_Z = -264
local FREE_ZONE_RADIUS = 22
local LEADERBOARD_POS = Vector3.new(-80, 13.4, -300) -- Mitte der Tafel (36 x 24)
local MONUMENT_POS = Vector3.new(80, PLAZA_TOP, -300)

-- Laufband-Zone (Treadmills) am hinteren Platzrand
local TREADMILL_SPACING = 14
local TREADMILL_BELT_Z = -366 -- Mitte der Laufflächen
local TREADMILL_DECK_TOP = 0.7
local TREADMILL_DECK_MIN_Z = -384
local TREADMILL_DECK_MAX_Z = -342
-- so schnell schiebt das Band den Spieler zurück (Config.TreadmillPush; muss deutlich unter Tempo 8 liegen)
local TREADMILL_PUSH = math.clamp(tonumber((Config :: any).TreadmillPush) or 6, 0, 7)
local TREADMILL_RAMP = 4 -- Rampe am Einstieg (hinten): vom Deck sanft hoch auf die Lauffläche
local TREADMILL_MATERIALS: { [string]: Enum.Material } = {
	Holz = Enum.Material.Wood,
	Stein = Enum.Material.Slate,
	Eisen = Enum.Material.DiamondPlate,
	Gold = Enum.Material.Foil,
	Diamant = Enum.Material.Glass,
	Galaxie = Enum.Material.Glass,
	Regenbogen = Enum.Material.SmoothPlastic,
}

local TREE_COLORS = {
	Color3.fromRGB(60, 170, 60),
	Color3.fromRGB(80, 190, 70),
	Color3.fromRGB(45, 150, 55),
	Color3.fromRGB(100, 200, 80),
}
local BUSH_COLOR = Color3.fromRGB(55, 160, 60)

local WHITE = Color3.new(1, 1, 1)

-- -------------------------------------------------------------------
-- BAU-HELFER
-- -------------------------------------------------------------------
-- Alle Teile werden gebaut, solange die Map noch NICHT im Workspace hängt (kein Nachrutschen,
-- ein einziger Replikations-Schub). Geschwindigkeiten der Treadmills werden erst danach gesetzt.
local pendingVelocities: { { Part: BasePart, Velocity: Vector3 } } = {}

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false -- nur Pads brauchen Touched (spart Physik-Arbeit)
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

-- Flache Scheibe (Zylinder mit senkrechter Achse), Unterkante auf bottomY
local function disc(name: string, center: Vector3, bottomY: number, height: number, diameter: number, props)
	local p = part(props)
	p.Name = name
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(height, diameter, diameter)
	p.CFrame = CFrame.new(center.X, bottomY + height / 2, center.Z) * CFrame.Angles(0, 0, math.rad(90))
	return p
end

-- Unsichtbarer Ankerpunkt für Schilder
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

-- Klassische Roblox-Noppen auf der Oberseite
local function studs(target: BasePart)
	target.TopSurface = Enum.SurfaceType.Studs
end

local function addLight(parent: Instance, color: Color3, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = parent
end

-- Mehrzeiliges Schild in Studs-Größe (wirkt wie ein echtes Schild in der Welt).
-- Aufbau wie bei MeteorFactory: BillboardGui > Frame "Frame" > TextLabels (UIListLayout)
local function worldSign(
	parent: Instance,
	guiName: string,
	widthStuds: number,
	heightStuds: number,
	offset: Vector3,
	maxDistance: number,
	lines: { SignLine }
): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = guiName
	gui.Size = UDim2.fromScale(widthStuds, heightStuds)
	gui.StudsOffset = offset
	gui.MaxDistance = maxDistance
	gui.LightInfluence = 0
	gui.Parent = parent

	local frame = Instance.new("Frame")
	frame.Name = "Frame"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = frame

	for order, line in ipairs(lines) do
		local label = Instance.new("TextLabel")
		label.Name = line.Name
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, line.Height)
		label.LayoutOrder = order
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = line.Color
		label.Text = line.Text
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = Color3.new(0, 0, 0)
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Parent = label
		label.Parent = frame
	end
	return gui
end

-- Liest Config.Treadmills zur LAUFZEIT und filtert kaputte Einträge raus
local function treadmillDefs(): { TreadmillDef }
	local list = (Config :: any).Treadmills
	local result: { TreadmillDef } = {}
	if type(list) ~= "table" then
		warn("[MapBuilder] Config.Treadmills fehlt – keine Laufbänder gebaut")
		return result
	end
	for _, def in ipairs(list) do
		if type(def) == "table" and type(def.Id) == "string" then
			table.insert(result, {
				Id = def.Id,
				Name = type(def.Name) == "string" and def.Name or def.Id,
				Price = tonumber(def.Price) or 0,
				Rate = tonumber(def.Rate) or 1,
				Color = typeof(def.Color) == "Color3" and def.Color or WHITE,
				Rainbow = def.Rainbow == true or def.Id == "Regenbogen",
			})
		end
	end
	return result
end

-- -------------------------------------------------------------------
-- ALTES ZEUG WEG
-- -------------------------------------------------------------------
local function clearOld()
	for _, child in ipairs(workspace:GetChildren()) do
		if child.Name == "Baseplate" or child.Name == "MeteorHeistMap" or child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end
end

-- -------------------------------------------------------------------
-- BODEN + RAND
-- -------------------------------------------------------------------
local function buildGround(map: Folder)
	local ground = part({
		Name = "Ground",
		Size = Vector3.new(GROUND_SIZE, 1, GROUND_SIZE),
		Position = Vector3.new(0, -0.5, GROUND_CENTER_Z),
		Material = Enum.Material.Plastic,
		Color = GROUND_COLOR,
		Parent = map,
	})
	studs(ground)

	-- Unsichtbare Randwände (durchsichtige Teile verdecken die Kamera nicht)
	local lengthZ = EDGE_MAX_Z - EDGE_MIN_Z
	local centerZ = (EDGE_MAX_Z + EDGE_MIN_Z) / 2
	for _, data in ipairs({
		{ Vector3.new(-EDGE_X - 2, 60, centerZ), Vector3.new(4, 120, lengthZ + 8) },
		{ Vector3.new(EDGE_X + 2, 60, centerZ), Vector3.new(4, 120, lengthZ + 8) },
		{ Vector3.new(0, 60, EDGE_MIN_Z - 2), Vector3.new(EDGE_X * 2 + 8, 120, 4) },
		{ Vector3.new(0, 60, EDGE_MAX_Z + 2), Vector3.new(EDGE_X * 2 + 8, 120, 4) },
	}) do
		part({
			Name = "Boundary",
			Position = data[1],
			Size = data[2],
			Transparency = 1,
			CastShadow = false,
			Parent = map,
		})
	end
end

-- -------------------------------------------------------------------
-- EI-RENNEN: großes Nester-Feld in der Map-Mitte (zwischen den Basen x = ±34)
--   viele kleine Nester (nah an den Basen), wenige große (Mitte / weit weg), Speed-Pads.
--   Attribute: Nester (Teil "Nest") NestSize = "Small"/"Big", EggPoint = Ei-Unterkante, RaceNest = true
--   (entferntestes großes Nest, dort erscheint das Gold-Ei); Ordner "NestField": Grenzen für die
--   Kreaturen (MinX, MaxX, MinZ, MaxZ). Der Server (MeteorService, FieldService) liest alles von hier.
-- -------------------------------------------------------------------
local function buildNest(parent: Instance, x: number, z: number, big: boolean, race: boolean): Part
	local diameter = if race then NEST_RACE_SIZE elseif big then NEST_BIG_SIZE else NEST_SMALL_SIZE
	local height = if big then 1.6 else 1
	local center = Vector3.new(x, 0, z)
	local nest = disc("Nest", center, FIELD_TOP, height, diameter, {
		Material = Enum.Material.Plastic,
		Color = if race then NEST_GOLD_COLOR else NEST_COLOR,
		Parent = parent,
	})
	studs(nest)
	-- Mulde (dunkleres Stroh), steht minimal höher -> kein Flackern
	disc("NestInner", center, FIELD_TOP, height + 0.1, diameter * 0.66, {
		Material = Enum.Material.Plastic,
		Color = NEST_INNER_COLOR,
		CanCollide = false,
		CastShadow = false,
		Parent = parent,
	})
	nest:SetAttribute("NestSize", if big then "Big" else "Small")
	nest:SetAttribute("EggPoint", Vector3.new(x, FIELD_TOP + height + 0.1, z))
	if big then
		-- 4 Strohhalme (Blöcke) schräg am Rand
		for i = 0, 3 do
			local angle = i * math.pi / 2 + math.pi / 4
			local r = diameter / 2 - 0.6
			part({
				Name = "Straw",
				Size = Vector3.new(1, 3.4, 1),
				CFrame = CFrame.new(x + math.cos(angle) * r, FIELD_TOP + height + 0.8, z + math.sin(angle) * r)
					* CFrame.Angles(0, -angle, math.rad(-25)),
				Material = Enum.Material.Plastic,
				Color = NEST_COLOR,
				CanCollide = false,
				Parent = parent,
			})
		end
		-- Lichtsäule (schaltet der Server ein, solange ein Ei drin liegt)
		local bottom = Instance.new("Attachment")
		bottom.Name = "PillarBottom"
		bottom.Position = Vector3.new(height / 2, 0, 0) -- (Zylinder liegt gekippt: lokales X = oben)
		bottom.Parent = nest
		local top = Instance.new("Attachment")
		top.Name = "PillarTop"
		top.Position = Vector3.new(height / 2 + 40, 0, 0)
		top.Parent = nest
		local beam = Instance.new("Beam")
		beam.Name = "NestPillar"
		beam.Attachment0 = bottom
		beam.Attachment1 = top
		beam.Width0 = diameter * 0.5
		beam.Width1 = diameter * 0.3
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Segments = 1
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(0.6, 0.8),
			NumberSequenceKeypoint.new(1, 1),
		})
		beam.Enabled = false
		beam.Parent = nest
	end
	if race then
		nest:SetAttribute("RaceNest", true)
		-- Zielflagge (schwarz-weiß) neben dem Nest
		local poleX = x + diameter / 2 + 2
		part({
			Name = "RacePole",
			Size = Vector3.new(0.6, 14, 0.6),
			Position = Vector3.new(poleX, FIELD_TOP + 7, z),
			Material = Enum.Material.Plastic,
			Color = WHITE,
			Parent = parent,
		})
		for i = 0, 1 do
			part({
				Name = "RaceFlag",
				Size = Vector3.new(0.2, 2, 2.5),
				CFrame = CFrame.new(poleX, FIELD_TOP + 12.5 - i * 2, z + 1.25 + (i * 2.5)),
				Material = Enum.Material.Plastic,
				Color = if i == 0 then Color3.fromRGB(27, 42, 53) else WHITE,
				CanCollide = false,
				CastShadow = false,
				Parent = parent,
			})
		end
	end
	return nest
end

-- Speed-Pad: flache Platte mit Blitz, Berühren = kurz schneller (FieldService)
local function buildSpeedPad(parent: Instance, x: number, z: number)
	local pad = part({
		Name = "SpeedPad",
		Size = Vector3.new(SPEED_PAD_SIZE, 0.3, SPEED_PAD_SIZE),
		Position = Vector3.new(x, FIELD_TOP + 0.15, z),
		Material = Enum.Material.SmoothPlastic,
		Color = SPEED_PAD_COLOR,
		CanCollide = false,
		CanTouch = true,
		CastShadow = false,
		Parent = parent,
	})
	pad:SetAttribute("SpeedPad", true)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Icon"
	gui.Face = Enum.NormalId.Top
	gui.CanvasSize = Vector2.new(100, 100)
	gui.LightInfluence = 0
	gui.Parent = pad
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "⚡"
	label.TextColor3 = WHITE
	label.Parent = gui
end

local function buildNestField(map: Folder): NestFieldInfo
	local field = folder("NestField", map) -- Name wird von Server und Client gesucht!
	field:SetAttribute("MinX", -CREATURE_HALF_X)
	field:SetAttribute("MaxX", CREATURE_HALF_X)
	field:SetAttribute("MinZ", CREATURE_MIN_Z)
	field:SetAttribute("MaxZ", CREATURE_MAX_Z)

	-- Noppenboden des Felds (etwas helleres Grün als die Wiese)
	local floorPart = part({
		Name = "Floor",
		Size = Vector3.new(FIELD_HALF_X * 2, FIELD_TOP, FIELD_MAX_Z - FIELD_MIN_Z),
		Position = Vector3.new(0, FIELD_TOP / 2, (FIELD_MIN_Z + FIELD_MAX_Z) / 2),
		Material = Enum.Material.Plastic,
		Color = FIELD_COLOR,
		Parent = field,
	})
	studs(floorPart)

	local nestsFolder = folder("Nests", field)
	local nests: { BasePart } = {}
	-- kleine Nester: 4 Reihen nah an den Basen, über die ganze Länge
	for _, x in ipairs(SMALL_NEST_X) do
		local z = SMALL_NEST_MIN_Z
		while z <= SMALL_NEST_MAX_Z do
			table.insert(nests, buildNest(nestsFolder, x, z, false, false))
			z += SMALL_NEST_STEP
		end
	end
	-- große Nester: Mitte + weit weg am Ende (das letzte ist das Renn-Nest)
	for i, pos in ipairs(BIG_NESTS) do
		table.insert(nests, buildNest(nestsFolder, pos.X, pos.Y, true, i == #BIG_NESTS))
	end

	local padsFolder = folder("SpeedPads", field)
	for _, pos in ipairs(SPEED_PADS) do
		buildSpeedPad(padsFolder, pos.X, pos.Y)
	end

	-- Schild am Anfang des Felds (vom Spawn-Platz aus zu sehen)
	local signAnchor = anchorPart("TitleSign", CFrame.new(0, 16, FIELD_MIN_Z + 4), field)
	worldSign(signAnchor, "Sign", 36, 9, Vector3.zero, 700, {
		{ Name = "Title", Text = "🥚 EI-RENNEN", Color = Color3.fromRGB(255, 220, 80), Height = 0.6 },
		{ Name = "Hint", Text = "Schnapp dir Eier! Achtung: Monster!", Color = WHITE, Height = 0.4 },
	})

	return {
		Folder = field,
		Nests = nests,
	}
end

-- -------------------------------------------------------------------
-- BLOCK-BAUM (Deko; die Basen baut BaseBuilder)
-- -------------------------------------------------------------------
-- Blockiger Roblox-Baum: Stamm + großer Blätterblock + kleiner Block obendrauf (3 Teile).
-- cf = Bodenpunkt (Stamm-Unterkante), scale = Größe
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

-- -------------------------------------------------------------------
-- SPAWN-PLATZ (SpawnLocation, Gratis-Zone, Bestenliste, Denkmal)
-- -------------------------------------------------------------------
local function buildPlaza(map: Folder): (CFrame, CFrame, FreeZone)
	local plaza = folder("Plaza", map)

	local floorPart = part({
		Name = "Floor",
		Size = Vector3.new(PLAZA_HALF_X * 2, PLAZA_TOP, PLAZA_MAX_Z - PLAZA_MIN_Z),
		Position = Vector3.new(0, PLAZA_TOP / 2, PLAZA_CENTER.Z),
		Material = Enum.Material.Plastic,
		Color = Color3.fromRGB(205, 212, 225),
		Parent = plaza,
	})
	studs(floorPart)

	-- Große SpawnLocation mit Leuchtrand
	part({
		Name = "SpawnRim",
		Size = Vector3.new(30, 0.6, 30),
		Position = Vector3.new(0, PLAZA_TOP + 0.3, SPAWN_Z),
		Material = Enum.Material.Plastic,
		Color = Color3.fromRGB(13, 105, 172),
		CastShadow = false,
		Parent = plaza,
	})
	local spawnTop = PLAZA_TOP + 0.8
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(26, 0.8, 26)
	spawn.Position = Vector3.new(0, spawnTop - 0.4, SPAWN_Z)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Color = Color3.fromRGB(255, 200, 60)
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.AllowTeamChangeOnTouch = false
	spawn.Parent = plaza
	local lobbySpawn = CFrame.lookAt(
		Vector3.new(0, spawnTop + 3.5, SPAWN_Z),
		Vector3.new(0, spawnTop + 3.5, -214) -- Blick zum Nester-Feld
	)

	-- Gratis-Zone: Landeplatz mit gelb-schwarzem Ring (hier landen Gratis- und Admin-Meteore)
	local zoneCenter = Vector3.new(0, 0, FREE_ZONE_Z)
	disc("FreeZoneRing", zoneCenter, PLAZA_TOP, 0.2, FREE_ZONE_RADIUS * 2 + 6, {
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(255, 205, 40),
		CastShadow = false,
		Parent = plaza,
	})
	disc("FreeZoneEdge", zoneCenter, PLAZA_TOP, 0.25, FREE_ZONE_RADIUS * 2 + 2, {
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(28, 28, 32),
		CastShadow = false,
		Parent = plaza,
	})
	local zoneTop = PLAZA_TOP + 0.3
	local zonePad = disc("FreeZone", zoneCenter, PLAZA_TOP, 0.3, FREE_ZONE_RADIUS * 2, {
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(80, 50, 150),
		CastShadow = false,
		Parent = plaza,
	})
	zonePad:SetAttribute("Radius", FREE_ZONE_RADIUS)
	local zoneSign = anchorPart("FreeZoneSign", CFrame.new(0, 15, FREE_ZONE_Z), plaza)
	worldSign(zoneSign, "Sign", 30, 7, Vector3.zero, 400, {
		{ Name = "Title", Text = "🎁 GRATIS-ZONE 🎁", Color = Color3.fromRGB(120, 255, 120), Height = 0.6 },
		{ Name = "Hint", Text = "👑 Hier landen Admin-Meteore!", Color = WHITE, Height = 0.4 },
	})

	-- Ständer für die Bestenliste (die Tafel selbst baut LeaderboardService an LeaderboardCFrame)
	local boardCF = CFrame.lookAt(LEADERBOARD_POS, Vector3.new(PLAZA_CENTER.X, LEADERBOARD_POS.Y, PLAZA_CENTER.Z))
	local boardBottom = LEADERBOARD_POS.Y - 12
	local standColor = Color3.fromRGB(45, 40, 60)
	part({
		Name = "LeaderboardBase",
		Size = Vector3.new(42, boardBottom - PLAZA_TOP, 6),
		CFrame = boardCF * CFrame.new(0, -12 - (boardBottom - PLAZA_TOP) / 2, 0),
		Material = Enum.Material.SmoothPlastic,
		Color = standColor,
		Parent = plaza,
	})
	for _, s in ipairs({ -1, 1 }) do
		part({
			Name = "LeaderboardPillar",
			Size = Vector3.new(2, 26, 2),
			CFrame = boardCF * CFrame.new(s * 19.5, 1, 0),
			Material = Enum.Material.SmoothPlastic,
			Color = standColor,
			Parent = plaza,
		})
	end
	part({
		Name = "LeaderboardCap",
		Size = Vector3.new(42, 1.2, 3),
		CFrame = boardCF * CFrame.new(0, 14.6, 0),
		Material = Enum.Material.Plastic,
		Color = Color3.fromRGB(255, 190, 40),
		CastShadow = false,
		Parent = plaza,
	})

	-- Meteor-Denkmal (Gegenstück zur Bestenliste)
	disc("MonumentBase", MONUMENT_POS, PLAZA_TOP, 3, 14, {
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(90, 90, 105),
		Parent = plaza,
	})
	local rockCenter = MONUMENT_POS + Vector3.new(0, 3 + 5, 0)
	part({
		Name = "MonumentRock",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(10, 10, 10),
		Position = rockCenter,
		Material = Enum.Material.CrackedLava,
		Color = Color3.fromRGB(110, 70, 60),
		Parent = plaza,
	})
	part({
		Name = "MonumentRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 17, 17),
		CFrame = CFrame.new(rockCenter) * CFrame.Angles(math.rad(20), 0, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Plastic,
		Color = Color3.fromRGB(255, 140, 40),
		CanCollide = false,
		CastShadow = false,
		Parent = plaza,
	})

	return lobbySpawn, boardCF, { Center = Vector3.new(0, zoneTop, FREE_ZONE_Z), Radius = FREE_ZONE_RADIUS }
end

-- -------------------------------------------------------------------
-- LAUFBAND-ZONE (Treadmills zum Schritte-Farmen)
-- -------------------------------------------------------------------
-- Ein Laufband: lokales -Z = Laufrichtung des Spielers, vorne Konsole + Bogen mit Schild.
-- Das Band schiebt den Spieler nach hinten (+Z lokal) -> man muss laufen, um draufzubleiben.
local function buildTreadmill(def: TreadmillDef, order: number, total: number, base: CFrame, parent: Instance)
	local model = Instance.new("Model")
	model.Name = def.Id
	model:SetAttribute("TreadmillId", def.Id)
	model:SetAttribute("Order", order)
	model:SetAttribute("Price", def.Price)
	model:SetAttribute("Rate", def.Rate)

	local color = def.Color
	local material = TREADMILL_MATERIALS[def.Id] or Enum.Material.Metal
	local topTier = order > total - 3 -- die obersten 3 Stufen leuchten extra

	local function glowPart(props): Part
		props.Material = Enum.Material.Neon
		props.Color = color
		props.CastShadow = false
		props.Parent = model
		local p = part(props)
		if def.Rainbow then
			p:SetAttribute("Rainbow", true) -- Client färbt durch
		end
		return p
	end

	part({
		Name = "Chassis",
		Size = Vector3.new(10.4, 0.6, 22),
		CFrame = base * CFrame.new(0, 0.3, 0),
		Material = material,
		Color = color:Lerp(Color3.new(0, 0, 0), 0.35),
		Parent = model,
	})
	local belt = part({
		Name = "Belt",
		Size = Vector3.new(8, 0.3, 20),
		CFrame = base * CFrame.new(0, 0.65, 0),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(32, 32, 38),
		CanCollide = true,
		CanQuery = true, -- Humanoid findet den Boden per Raycast
		Parent = model,
	})
	local backward = -base.LookVector
	belt:SetAttribute("BeltDir", backward)
	belt:SetAttribute("BeltSpeed", TREADMILL_PUSH)
	table.insert(pendingVelocities, { Part = belt, Velocity = backward * TREADMILL_PUSH })
	model.PrimaryPart = belt

	-- Einstieg hinten (+Z lokal): Keil-Rampe vom Deck hoch auf die Lauffläche. Wer stehen bleibt, wird vom
	-- Band hierher geschoben und rutscht sanft aufs Deck (keine Kante, kein Absturz). Die hohe Seite des Keils
	-- (+Z des Keils) liegt am Band, die flache Kante (-Z des Keils = LookVector) zeigt vom Band weg.
	local beltTop = 0.8 -- Oberkante Lauffläche über dem Deck (0.65 + 0.3 / 2)
	local ramp = Instance.new("WedgePart")
	ramp.Name = "Ramp"
	ramp.Anchored = true
	ramp.CanTouch = false
	ramp.TopSurface = Enum.SurfaceType.Smooth
	ramp.BottomSurface = Enum.SurfaceType.Smooth
	ramp.Size = Vector3.new(8, beltTop, TREADMILL_RAMP)
	local rampCenter = base * CFrame.new(0, beltTop / 2, 10 + TREADMILL_RAMP / 2)
	ramp.CFrame = CFrame.lookAt(rampCenter.Position, rampCenter.Position + base.LookVector * -1)
	ramp.Material = Enum.Material.Metal
	ramp.Color = color:Lerp(Color3.new(0, 0, 0), 0.35)
	ramp.Parent = model

	-- Leuchtende Seitenrahmen
	for _, s in ipairs({ -1, 1 }) do
		glowPart({
			Name = "SideFrame",
			Size = Vector3.new(1.2, 0.9, 21),
			CFrame = base * CFrame.new(s * 4.6, 1.05, 0),
		})
	end

	-- Konsole vorne (man läuft dagegen) + unsichtbare Stoppwand gegen Drüberspringen
	part({
		Name = "Console",
		Size = Vector3.new(8, 3.6, 1.2),
		CFrame = base * CFrame.new(0, 2.4, -10.6),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(40, 40, 48),
		Parent = model,
	})
	local screen = glowPart({
		Name = "Screen",
		Size = Vector3.new(5, 1.4, 0.15),
		CFrame = base * CFrame.new(0, 3.2, -9.925),
		CanCollide = false,
	})
	screen.CanQuery = false
	part({
		Name = "FrontStop",
		Size = Vector3.new(8.4, 12, 0.6),
		CFrame = base * CFrame.new(0, 6, -10.5),
		Transparency = 1,
		CastShadow = false,
		CanQuery = false, -- nur Wand (keine Kamera-/Klick-Treffer), Kollision bleibt
		Parent = model,
	})

	-- Bogen: jede Stufe etwas höher (sieht aus wie eine Treppe von Holz bis Regenbogen)
	local archHeight = 8 + (order - 1) * 1.2
	for _, s in ipairs({ -1, 1 }) do
		part({
			Name = "Pillar",
			Size = Vector3.new(1.2, archHeight, 1.2),
			CFrame = base * CFrame.new(s * 5.6, archHeight / 2, -11.6),
			Material = material,
			Color = color,
			Parent = model,
		})
	end
	local beam = glowPart({
		Name = "Arch",
		Size = Vector3.new(12.4, 1.2, 1.2),
		CFrame = base * CFrame.new(0, archHeight + 0.6, -11.6),
	})
	if topTier then
		addLight(beam, color, 18, 1.6)
	end

	local free = def.Price <= 0
	worldSign(beam, "Sign", 14, 5.2, Vector3.new(0, 3.4, 0), 160, {
		{ Name = "NameLabel", Text = def.Name, Color = color:Lerp(WHITE, 0.45), Height = 0.42 },
		{
			Name = "RateLabel",
			Text = "+" .. Util.FormatNumber(def.Rate) .. " 👟",
			Color = Color3.fromRGB(255, 230, 90),
			Height = 0.3,
		},
		{
			-- Preis (der Client schreibt "Gekauft" / "Dein bestes" darüber, sobald er weiß, was dir gehört)
			Name = "PriceLabel",
			Text = free and "Gratis" or Util.FormatCash(def.Price),
			Color = free and Color3.fromRGB(120, 255, 120) or Color3.fromRGB(255, 220, 90),
			Height = 0.28,
		},
	})

	model.Parent = parent
	return model
end

local function buildTreadmills(map: Folder): (Folder, CFrame)
	local zone = folder("TreadmillZone", map) -- Deko (Boden, Schild)
	local treadmills = folder("Treadmills", map) -- NUR die Laufband-Models
	local defs = treadmillDefs()
	local count = #defs

	local deckWidth = math.max(1, count - 1) * TREADMILL_SPACING + 10.4 + 16
	local deckDepth = TREADMILL_DECK_MAX_Z - TREADMILL_DECK_MIN_Z
	local deckCenterZ = (TREADMILL_DECK_MAX_Z + TREADMILL_DECK_MIN_Z) / 2
	local deck = part({
		Name = "Deck",
		Size = Vector3.new(deckWidth, TREADMILL_DECK_TOP - PLAZA_TOP, deckDepth),
		Position = Vector3.new(0, (TREADMILL_DECK_TOP + PLAZA_TOP) / 2, deckCenterZ),
		Material = Enum.Material.Plastic,
		Color = Color3.fromRGB(55, 65, 95),
		Parent = zone,
	})
	studs(deck)
	-- (früher: Leuchtleiste an der Deck-Kante – lag mit ihrer Außenfläche genau in der Deck-Fläche
	-- und flackerte; weggelassen)
	local zoneSign = anchorPart("ZoneSign", CFrame.new(0, 30, TREADMILL_DECK_MIN_Z + 4), zone)
	worldSign(zoneSign, "Sign", 56, 11, Vector3.zero, 500, {
		{ Name = "Title", Text = "🏃 LAUFBÄNDER 👟", Color = Color3.fromRGB(255, 220, 60), Height = 0.6 },
		{ Name = "Hint", Text = "Laufband kaufen, drauf laufen = schneller!", Color = WHITE, Height = 0.4 },
	})

	for order, def in ipairs(defs) do
		local x = (order - (count + 1) / 2) * TREADMILL_SPACING
		local origin = Vector3.new(x, TREADMILL_DECK_TOP, TREADMILL_BELT_Z)
		-- Laufrichtung des Spielers = -Z (weg vom Platz), Einstieg von der Platzseite
		local base = CFrame.lookAt(origin, origin - Vector3.zAxis)
		buildTreadmill(def, order, count, base, treadmills)
	end

	local spawnY = TREADMILL_DECK_TOP + 3.5
	local spawnCF =
		CFrame.lookAt(Vector3.new(0, spawnY, TREADMILL_DECK_MAX_Z - 5), Vector3.new(0, spawnY, TREADMILL_BELT_Z))
	treadmills:SetAttribute("SpawnCFrame", spawnCF)
	return treadmills, spawnCF
end

-- -------------------------------------------------------------------
-- DEKO (Block-Bäume, Büsche, Zaun) – bewusst sparsam
-- -------------------------------------------------------------------
local function tree(parent: Instance, x: number, z: number, scale: number, color: Color3)
	blockTree(parent, CFrame.new(x, 0, z), scale, color)
end

-- Busch = grüner Noppen-Block (halb im Boden)
local function bush(parent: Instance, x: number, z: number, size: number)
	local p = part({
		Name = "Bush",
		Size = Vector3.new(size, size * 0.6, size),
		Position = Vector3.new(x, size * 0.25, z),
		Material = Enum.Material.Plastic,
		Color = BUSH_COLOR,
		CanCollide = false,
		CastShadow = false,
		Parent = parent,
	})
	p.TopSurface = Enum.SurfaceType.Studs
end

local function buildFence(parent: Instance)
	local color = Color3.fromRGB(245, 240, 228)
	-- Ecken im Kreis, damit jeder Eckpfosten nur einmal gebaut wird
	local corners = {
		Vector3.new(-EDGE_X, 0, EDGE_MIN_Z),
		Vector3.new(EDGE_X, 0, EDGE_MIN_Z),
		Vector3.new(EDGE_X, 0, EDGE_MAX_Z),
		Vector3.new(-EDGE_X, 0, EDGE_MAX_Z),
	}
	for i, a in ipairs(corners) do
		local b = corners[i % #corners + 1]
		local length = (b - a).Magnitude
		local sideCF = CFrame.lookAt((a + b) / 2, b)
		for _, height in ipairs({ 1.4, 2.8 }) do
			part({
				Name = "FenceRail",
				Size = Vector3.new(0.5, 0.5, length),
				CFrame = sideCF + Vector3.new(0, height, 0),
				Material = Enum.Material.Wood,
				Color = color,
				CastShadow = false,
				Parent = parent,
			})
		end
		local posts = math.max(1, math.floor(length / 55 + 0.5))
		for p = 0, posts - 1 do
			local pos = a:Lerp(b, p / posts)
			part({
				Name = "FencePost",
				Size = Vector3.new(1, 3.8, 1),
				Position = pos + Vector3.new(0, 1.9, 0),
				Material = Enum.Material.Wood,
				Color = color,
				CastShadow = false,
				Parent = parent,
			})
		end
	end
end

local function buildDeco(map: Folder)
	local deco = folder("Deco", map)
	local rng = Random.new(20261003) -- fester Seed: jeder Server sieht gleich aus
	local function treeColor(): Color3
		return TREE_COLORS[rng:NextInteger(1, #TREE_COLORS)]
	end

	buildFence(deco)

	-- Bäume AUSSERHALB des Zauns (Horizont), gleichmäßig verteilt
	local strips = {
		{ -EDGE_X - 45, -EDGE_X - 12, EDGE_MIN_Z, EDGE_MAX_Z, 7, true },
		{ EDGE_X + 12, EDGE_X + 45, EDGE_MIN_Z, EDGE_MAX_Z, 7, true },
		{ -EDGE_X + 10, EDGE_X - 10, EDGE_MAX_Z + 10, EDGE_MAX_Z + 40, 5, false },
		{ -EDGE_X + 10, EDGE_X - 10, EDGE_MIN_Z - 40, EDGE_MIN_Z - 10, 5, false },
	}
	for _, strip in ipairs(strips) do
		local x0, x1, z0, z1, count, alongZ = strip[1], strip[2], strip[3], strip[4], strip[5], strip[6]
		for i = 1, count do
			local t = (i - 1 + rng:NextNumber(0.2, 0.8)) / count
			local x, z
			if alongZ then
				x = rng:NextNumber(x0, x1)
				z = z0 + (z1 - z0) * t
			else
				x = x0 + (x1 - x0) * t
				z = rng:NextNumber(z0, z1)
			end
			tree(deco, x, z, rng:NextNumber(1.1, 1.5), treeColor())
		end
	end

	-- Hinter den LINKEN Basen (zwischen Rand x = -124 und Zaun x = -168). Rechts liegt dort der Meteor-Run.
	for _, z in ipairs({ -135, -45, 45, 135 }) do
		tree(deco, -146 + rng:NextNumber(-4, 4), z + rng:NextNumber(-10, 10), rng:NextNumber(0.9, 1.2), treeColor())
	end
	for _, z in ipairs({ -90, 0, 90 }) do
		bush(deco, -146 + rng:NextNumber(-6, 6), z, rng:NextNumber(4, 6))
	end

	-- Hinter dem Ziel-Tor (+Z)
	for _, s in ipairs({ -1, 1 }) do
		tree(deco, s * 60, 240, 1.1, treeColor())
		tree(deco, s * 120, 236, 1, treeColor())
		bush(deco, s * 35, 242, 5)
		bush(deco, s * 90, 246, 4.5)
	end

	-- Spawn-Platz: Ecken + Ränder
	for _, s in ipairs({ -1, 1 }) do
		tree(deco, s * 108, PLAZA_MIN_Z + 10, 1.2, treeColor())
		tree(deco, s * 108, PLAZA_MAX_Z - 12, 1.1, treeColor())
		bush(deco, s * 112, -335, 5)
		bush(deco, s * 112, -275, 5.5)
		bush(deco, s * 70, PLAZA_MIN_Z + 6, 4.5)
	end

	-- Zwischen Platz und Basen
	for _, s in ipairs({ -1, 1 }) do
		bush(deco, s * 60, -195, 4.5)
		bush(deco, s * 98, -210, 5)
	end
end

-- -------------------------------------------------------------------
-- ÖFFENTLICH
-- -------------------------------------------------------------------
-- Baut die komplette Map in workspace.MeteorHeistMap (alte Map/Baseplate/SpawnLocations werden entfernt).
function MapBuilder.Build(): MapResult
	clearOld()
	table.clear(pendingVelocities)

	local map = Instance.new("Folder")
	map.Name = "MeteorHeistMap"

	buildGround(map)
	local nestField = buildNestField(map)
	local plots = BaseBuilder.BuildPlots(map) -- Basen: siehe BaseBuilder.luau
	local lobbySpawn, leaderboardCF, freeZone = buildPlaza(map)
	local treadmillsFolder, treadmillSpawn = buildTreadmills(map)
	buildDeco(map)

	map.Parent = workspace

	-- Erst im Workspace: Treadmill-Geschwindigkeiten setzen (verankerte Teile schieben Spieler)
	for _, item in ipairs(pendingVelocities) do
		item.Part.AssemblyLinearVelocity = item.Velocity
	end
	table.clear(pendingVelocities)

	return {
		MapFolder = map,
		Plots = plots,
		NestField = nestField,
		LobbySpawn = lobbySpawn,
		LeaderboardCFrame = leaderboardCF,
		FreeZone = freeZone,
		TreadmillsFolder = treadmillsFolder,
		TreadmillSpawn = treadmillSpawn,
	}
end

return MapBuilder
