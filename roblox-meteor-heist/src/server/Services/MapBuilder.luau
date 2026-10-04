-- Baut die komplette Map per Code (wird von PlotService.Init EINMAL aufgerufen):
--   • knallgrüner Roblox-Noppenboden mit Block-Bäumen, Büschen, Zaun und unsichtbaren Randwänden
--   • langes LAUFBAND (Förderband) durch die Map-Mitte, Meteore kommen aus dem Portal am Spawn-Platz
--   • 8 OFFENE Basen (je 4 pro Seite, Eingang zum Band, 80 x 90 Studs): bunter Noppenboden, niedriger
--     weißer Rand an Seiten + hinten, vorne offen mit Laser-Sperre; 18 UNSICHTBARE Slot-Anker
--     (locker verteilt), Collect-Pad, Lock-Pad, Laternen, Block-Bäume und Namensschild
--  Stil: schlicht, bunt, blockig (Plastic + Noppen), wenig Neon, wenige Teile.
--   • großer Spawn-Platz mit SpawnLocation, Gratis-Zone, Bestenliste und der LAUFBAND-ZONE (Treadmills)
-- Rückgabe von MapBuilder.Build(): siehe Typ "MapResult" unten.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))

local MapBuilder = {}

export type BeltInfo = {
	Part: BasePart,
	Start: Vector3, -- Mittellinie auf der Bandoberfläche am Startende
	Dir: Vector3, -- Einheitsvektor (Laufrichtung der Meteore)
	Length: number,
	Width: number,
	TopY: number, -- Höhe der Bandoberfläche
}

export type FreeZone = {
	Center: Vector3, -- Mitte der Gratis-Zone, Y = Oberkante des Bodens dort
	Radius: number,
}

export type MapResult = {
	MapFolder: Folder,
	Plots: { any },
	Belt: BeltInfo,
	LobbySpawn: CFrame,
	LeaderboardCFrame: CFrame,
	FreeZone: FreeZone,
	TreadmillsFolder: Folder,
	TreadmillSpawn: CFrame, -- Zusatz: Teleport-Ziel für den Knopf "🏃 Laufbänder"
}

type TreadmillDef = {
	Id: string,
	Name: string,
	Required: number,
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

-- Laufband (Förderband) entlang +Z durch die Map-Mitte
local BELT_LENGTH = 440
local BELT_WIDTH = 14
local BELT_FRAME_TOP = 0.8 -- Oberkante des Unterbaus
local BELT_TOP = 1.2 -- Oberkante der Lauffläche (hier liegen die Meteore auf)
local BELT_DEFAULT_SPEED = 9 -- falls Config.BeltSpeed fehlt
local CROSSINGS = { -90, 0, 90 } -- Lücken im Geländer zum Überqueren (genau zwischen den Basen)
local CROSSING_WIDTH = 10
local PORTAL_LENGTH = 16
local PORTAL_HEIGHT = 14

-- Basen: offen (nur niedriger Rand an Seiten + hinten), vorne offen mit Laser-Sperre.
-- Lokales Koordinatensystem einer Base: -Z = Eingang (zeigt zum Band), X = Breite, Z = Tiefe.
local PLOT_WIDTH = 80 -- lokales X (entlang der Welt-Z-Achse)
local PLOT_DEPTH = 90 -- lokales Z (entlang der Welt-X-Achse) -> 7200 Studs² (alt 72x72 = 5184, ca. 1,4x)
local HALF_X = PLOT_WIDTH / 2
local HALF_Z = PLOT_DEPTH / 2
local PLOT_X = 79 -- Abstand Basis-Mitte <-> Bandmitte (Eingang bei x = ±34, Rückseite bei x = ±124)
local PLOT_Z = { -135, -45, 45, 135 } -- 10 Studs Lücke zwischen den Basen
local PLOT_FLOOR_TOP = 1
local FENCE_HEIGHT = 2 -- niedriger Rand (drüberspringen geht – Schutz macht der Lock-Rauswurf)
local FENCE_THICK = 1
local BARRIER_HEIGHT = 10
-- Kräftige Roblox-Plastikfarben (Bright red, Bright orange, Bright yellow, ...)
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
local FENCE_COLOR = Color3.fromRGB(242, 243, 243) -- Institutional white
local WOOD_COLOR = Color3.fromRGB(124, 92, 70) -- Reddish brown
-- Unsichtbare Slot-Anker: versetztes Raster (5-4-5-4 = 18), Reihe 1 nahe Eingang (Slot 1-5),
-- Reihe 4 hinten (Slot 15-18). Abstand 13 Studs, dazu etwas Zufall (fester Seed: alle Basen gleich)
-- -> auch nach dem Wackeln noch mind. ~10 Studs zwischen zwei Aliens (Footprint max. 8x8).
local SLOT_ROWS = {
	{ Z = -14, Count = 5 },
	{ Z = -1, Count = 4 },
	{ Z = 12, Count = 5 },
	{ Z = 25, Count = 4 },
}
local SLOT_SPACING = 13
local SLOT_JITTER = 1 -- Studs Zufalls-Versatz je Richtung
local SLOT_YAW = math.rad(12) -- leicht verdreht (wirkt lockerer)
local SLOT_SEED = 4711
-- Anker-Kasten vom Boden bis 3 Studs hoch: wer hindurchläuft, sammelt Geld ein (Touched),
-- PlotService.SlotTopCFrame nimmt die Unterkante (= Bodenhöhe)
local SLOT_ANCHOR_SIZE = Vector3.new(6, 3, 6)

-- Spawn-Platz (hinter dem Bandstart, -Z)
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
local TREADMILL_PUSH = 14 -- so schnell schiebt das Band den Spieler zurück
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
-- ein einziger Replikations-Schub). Geschwindigkeiten der Bänder werden erst danach gesetzt.
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

-- Einzeiliges Schild in Pixelgröße (wie bisher bei Collect/Lock/Basis-Namen)
local function billboard(parent: Instance, size: UDim2, offset: Vector3, maxDistance: number): (BillboardGui, TextLabel)
	local gui = Instance.new("BillboardGui")
	gui.Size = size
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
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4 -- dicke Kontur (Roblox-Schild-Stil)
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	label.Parent = gui
	return gui, label
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
				Required = tonumber(def.Required) or 0,
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
-- LAUFBAND (Förderband) + PORTALE
-- -------------------------------------------------------------------
-- Gehäuse über einem Bandende. inward = +1: Öffnung zeigt nach +Z (Start), -1: nach -Z (Ende).
-- Die leuchtende Portal-Fläche sitzt direkt am Bandende: dort tauchen die Meteore auf bzw. verschwinden.
local function buildPortal(parent: Instance, name: string, bandEndZ: number, inward: number, color: Color3)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	local outerZ = bandEndZ - inward * 2 -- Ende des Unterbaus
	local openZ = bandEndZ + inward * PORTAL_LENGTH
	local centerZ = (outerZ + openZ) / 2
	local length = math.abs(openZ - outerZ)
	local housing = Color3.fromRGB(52, 54, 66)

	for _, s in ipairs({ -1, 1 }) do
		part({
			Name = "Wall",
			Size = Vector3.new(2.4, PORTAL_HEIGHT, length),
			Position = Vector3.new(s * 10.2, PORTAL_HEIGHT / 2, centerZ),
			Material = Enum.Material.Metal,
			Color = housing,
			Parent = model,
		})
		part({
			Name = "SideGlow",
			Size = Vector3.new(0.6, PORTAL_HEIGHT - BELT_FRAME_TOP, 0.6),
			Position = Vector3.new(s * 9.2, (PORTAL_HEIGHT + BELT_FRAME_TOP) / 2, openZ),
			Material = Enum.Material.Neon,
			Color = color,
			CanCollide = false,
			CastShadow = false,
			Parent = model,
		})
	end
	part({
		Name = "Roof",
		Size = Vector3.new(22.8, 2, length),
		Position = Vector3.new(0, PORTAL_HEIGHT + 1, centerZ),
		Material = Enum.Material.Metal,
		Color = housing,
		Parent = model,
	})
	part({
		Name = "TopGlow",
		Size = Vector3.new(18, 0.8, 0.6),
		Position = Vector3.new(0, PORTAL_HEIGHT - 0.4, openZ),
		Material = Enum.Material.Neon,
		Color = color,
		CanCollide = false,
		CastShadow = false,
		Parent = model,
	})
	local plane = part({
		Name = "PortalPlane",
		Size = Vector3.new(18, PORTAL_HEIGHT - BELT_FRAME_TOP, 0.4),
		Position = Vector3.new(0, (PORTAL_HEIGHT + BELT_FRAME_TOP) / 2, bandEndZ - inward * 0.3),
		Material = Enum.Material.Neon,
		Color = color,
		CanCollide = false, -- wer auf dem Band mitfährt, fällt hinten raus statt festzuklemmen
		CanQuery = false,
		CastShadow = false,
		Parent = model,
	})
	addLight(plane, color, 22, 2)
	return model
end

local function buildBelt(map: Folder): BeltInfo
	local deco = folder("BeltDeco", map)
	local startZ = -BELT_LENGTH / 2
	local endZ = BELT_LENGTH / 2
	local halfW = BELT_WIDTH / 2

	-- Unterbau
	part({
		Name = "Frame",
		Size = Vector3.new(BELT_WIDTH + 4, BELT_FRAME_TOP, BELT_LENGTH + 4),
		Position = Vector3.new(0, BELT_FRAME_TOP / 2, 0),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(58, 60, 70),
		Parent = deco,
	})

	-- Lauffläche (dunkel; die Streifen-Animation macht der Client)
	local beltHeight = BELT_TOP - BELT_FRAME_TOP + 0.2
	local belt = part({
		Name = "Belt",
		Size = Vector3.new(BELT_WIDTH, beltHeight, BELT_LENGTH),
		Position = Vector3.new(0, BELT_TOP - beltHeight / 2, 0),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(36, 36, 42),
		Parent = map,
	})
	local start = Vector3.new(0, BELT_TOP, startZ)
	local dir = Vector3.new(0, 0, 1)
	belt:SetAttribute("BeltStart", start)
	belt:SetAttribute("BeltDir", dir)
	belt:SetAttribute("BeltLength", BELT_LENGTH)
	belt:SetAttribute("BeltWidth", BELT_WIDTH)
	local speed = tonumber((Config :: any).BeltSpeed) or BELT_DEFAULT_SPEED
	belt:SetAttribute("BeltSpeed", speed)
	-- Wer aufs Band springt, fährt mit den Meteoren mit
	table.insert(pendingVelocities, { Part = belt, Velocity = dir * speed })

	-- Abschnitte zwischen den Überquerungs-Lücken
	local segments: { { number } } = {}
	local z = startZ
	for _, crossing in ipairs(CROSSINGS) do
		table.insert(segments, { z, crossing - CROSSING_WIDTH / 2 })
		z = crossing + CROSSING_WIDTH / 2
	end
	table.insert(segments, { z, endZ })

	local yellow = Color3.fromRGB(255, 205, 40)
	local black = Color3.fromRGB(28, 28, 32)
	local lipTop = BELT_TOP + 0.3
	local lipHeight = lipTop - BELT_FRAME_TOP
	local railBottom = lipTop
	local railTop = railBottom + 2.4
	for _, segment in ipairs(segments) do
		local z0, z1 = segment[1], segment[2]
		for _, s in ipairs({ -1, 1 }) do
			-- gelb-schwarze Kanten
			part({
				Name = "EdgeYellow",
				Size = Vector3.new(1, lipHeight, z1 - z0),
				Position = Vector3.new(s * (halfW + 0.5), BELT_FRAME_TOP + lipHeight / 2, (z0 + z1) / 2),
				Material = Enum.Material.SmoothPlastic,
				Color = yellow,
				CastShadow = false,
				Parent = deco,
			})
			part({
				Name = "EdgeBlack",
				Size = Vector3.new(1, lipHeight, z1 - z0),
				Position = Vector3.new(s * (halfW + 1.5), BELT_FRAME_TOP + lipHeight / 2, (z0 + z1) / 2),
				Material = Enum.Material.SmoothPlastic,
				Color = black,
				CastShadow = false,
				Parent = deco,
			})
			-- Geländer aus Glas (in den Portalen übernehmen die Wände)
			local r0 = math.max(z0, startZ + PORTAL_LENGTH)
			local r1 = math.min(z1, endZ - PORTAL_LENGTH)
			if r1 - r0 > 1 then
				part({
					Name = "RailGlass",
					Size = Vector3.new(0.3, railTop - railBottom, r1 - r0),
					Position = Vector3.new(s * (halfW + 1.5), (railBottom + railTop) / 2, (r0 + r1) / 2),
					Material = Enum.Material.Glass,
					Color = Color3.fromRGB(170, 220, 255),
					Transparency = 0.6,
					CastShadow = false,
					Parent = deco,
				})
				part({
					Name = "RailTop",
					Size = Vector3.new(0.7, 0.4, r1 - r0),
					Position = Vector3.new(s * (halfW + 1.5), railTop + 0.2, (r0 + r1) / 2),
					Material = Enum.Material.Metal,
					Color = Color3.fromRGB(200, 205, 215),
					CastShadow = false,
					Parent = deco,
				})
			end
		end
	end

	-- Leuchtende Pfosten an den Überquerungs-Lücken
	for _, crossing in ipairs(CROSSINGS) do
		for _, s in ipairs({ -1, 1 }) do
			for _, e in ipairs({ -1, 1 }) do
				part({
					Name = "CrossingPost",
					Size = Vector3.new(0.8, railTop + 0.4 - BELT_FRAME_TOP, 0.8),
					Position = Vector3.new(
						s * (halfW + 1.5),
						(BELT_FRAME_TOP + railTop + 0.4) / 2,
						crossing + e * (CROSSING_WIDTH / 2 + 0.4)
					),
					Material = Enum.Material.Neon,
					Color = yellow,
					CastShadow = false,
					Parent = deco,
				})
			end
		end
	end

	-- Leuchtende Akzente unten am Unterbau
	for _, s in ipairs({ -1, 1 }) do
		part({
			Name = "Glow",
			Size = Vector3.new(0.25, 0.25, BELT_LENGTH + 4),
			Position = Vector3.new(s * (halfW + 2.12), 0.45, 0),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(0, 210, 255),
			CanCollide = false,
			CastShadow = false,
			Parent = deco,
		})
	end

	-- Portale: Start (am Spawn-Platz) und Ende
	buildPortal(deco, "StartPortal", startZ, 1, Color3.fromRGB(150, 70, 255))
	buildPortal(deco, "EndPortal", endZ, -1, Color3.fromRGB(255, 70, 50))

	local titleAnchor = anchorPart("TitleSign", CFrame.new(0, PORTAL_HEIGHT + 9, startZ + PORTAL_LENGTH / 2), deco)
	worldSign(titleAnchor, "Sign", 46, 11, Vector3.zero, 700, {
		{ Name = "Title", Text = "☄️ METEOR HEIST ☄️", Color = Color3.fromRGB(255, 170, 60), Height = 0.62 },
		-- geräteneutral (am Handy gibt es keine E/F-Tasten): halten = klauen, kurz = kaufen
		{
			Name = "Hint",
			Text = "😈 Halten = Klauen (gratis) • 🛒 Kaufen = Lieferung",
			Color = WHITE,
			Height = 0.38,
		},
	})

	return {
		Part = belt,
		Start = start,
		Dir = dir,
		Length = BELT_LENGTH,
		Width = BELT_WIDTH,
		TopY = BELT_TOP,
	}
end

-- -------------------------------------------------------------------
-- BASEN
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

-- Einfache Laterne: Holzpfosten + leuchtender Würfel (kein PointLight -> spart Leistung)
local function lantern(parent: Instance, cf: CFrame)
	local height = 6
	part({
		Name = "LanternPost",
		Size = Vector3.new(0.8, height, 0.8),
		CFrame = cf * CFrame.new(0, height / 2, 0),
		Material = Enum.Material.Plastic,
		Color = WOOD_COLOR,
		Parent = parent,
	})
	part({
		Name = "LanternLamp",
		Size = Vector3.new(1.6, 1.6, 1.6),
		CFrame = cf * CFrame.new(0, height + 0.8, 0),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 220, 120),
		CanCollide = false,
		CastShadow = false,
		Parent = parent,
	})
end

-- Lokale Positionen (X, Z, Drehung) der 18 Slot-Anker in Slot-Reihenfolge
local function slotLayout(): { { X: number, Z: number, Yaw: number } }
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

local function buildPlot(index: number, cf: CFrame, color: Color3, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	model:SetAttribute("PlotIndex", index)
	model:SetAttribute("OwnerUserId", 0)
	model:SetAttribute("LockedUntil", 0)

	local top = PLOT_FLOOR_TOP
	-- Boden: kräftige Plastikfarbe mit Noppen (klassischer Roblox-Look)
	local floorPart = part({
		Name = "Floor",
		Size = Vector3.new(PLOT_WIDTH, top, PLOT_DEPTH),
		CFrame = cf * CFrame.new(0, top / 2, 0),
		Material = Enum.Material.Plastic,
		Color = color,
		Parent = model,
	})
	floorPart.TopSurface = Enum.SurfaceType.Studs
	model.PrimaryPart = floorPart

	-- Niedriger weißer Rand: hinten über die ganze Breite, Seiten enden STUMPF an der Rückwand
	-- (keine überlappenden Teile mit gleichen Außenflächen -> kein Flackern/Z-Fighting).
	-- Alles steht AUF dem Boden (Unterkante = Bodenoberkante).
	local function fence(name: string, size: Vector3, offset: CFrame)
		local p = part({
			Name = name,
			Size = size,
			CFrame = cf * offset,
			Material = Enum.Material.Plastic,
			Color = FENCE_COLOR,
			Parent = model,
		})
		p.TopSurface = Enum.SurfaceType.Studs
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

	-- Laser-Sperre vorne (PlotService macht sie sichtbar, solange die Base gesperrt ist).
	-- Etwas schmaler als der Innenraum: berührt die Seitenränder nicht (kein Flackern).
	local barrier = part({
		Name = "Barrier",
		Size = Vector3.new(PLOT_WIDTH - 2 * FENCE_THICK - 0.2, BARRIER_HEIGHT, 0.4),
		CFrame = cf * CFrame.new(0, top + BARRIER_HEIGHT / 2, -HALF_Z + 0.3),
		Material = Enum.Material.ForceField,
		Color = Color3.fromRGB(255, 40, 40),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
		Parent = model,
	})

	-- 18 unsichtbare Slot-Anker (Reihenfolge = Slot-Nummer). Keine sichtbaren Pads mehr.
	-- CanTouch: durchlaufen = Geld einsammeln (PlotService), CanQuery aus (Fallen-Strahl, Prompts).
	local slots: { BasePart } = {}
	for slotNumber, spot in ipairs(slotLayout()) do
		slots[slotNumber] = part({
			Name = "Slot" .. slotNumber,
			Size = SLOT_ANCHOR_SIZE,
			CFrame = cf * CFrame.new(spot.X, top + SLOT_ANCHOR_SIZE.Y / 2, spot.Z) * CFrame.Angles(0, spot.Yaw, 0),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = true,
			CastShadow = false,
			Parent = model,
		})
	end

	-- Collect- und Lock-Pad vorne links/rechts (Spawn-Punkt liegt dazwischen)
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
	local _, collectLabel = billboard(collectPad, UDim2.new(0, 200, 0, 50), Vector3.new(0, 4, 0), 90)
	collectLabel.Text = "💰 $0"

	local lockPad = part({
		Name = "LockPad",
		Size = Vector3.new(10, 0.3, 7),
		CFrame = cf * CFrame.new(22, top + 0.15, -36),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(230, 60, 60),
		CanCollide = false,
		CanTouch = true,
		CastShadow = false,
		Parent = model,
	})
	local _, lockLabel = billboard(lockPad, UDim2.new(0, 200, 0, 50), Vector3.new(0, 4, 0), 90)
	lockLabel.Text = "🔒 LOCK"

	-- Deko: Laternen vorne in den Ecken, blockige Bäume hinten in den Ecken (weit weg von allen Slots)
	local deco = folder("Deco", model)
	for _, s in ipairs({ -1, 1 }) do
		lantern(deco, cf * CFrame.new(s * 35.5, top, -41))
		blockTree(deco, cf * CFrame.new(s * 33, top, 38), 0.9, TREE_COLORS[(index + s) % #TREE_COLORS + 1])
	end

	-- Namensschild über dem Eingang (großes Roblox-Schild)
	local signPart = anchorPart("Sign", cf * CFrame.new(0, top + 11, -HALF_Z + 2), model)
	local _, signLabel = billboard(signPart, UDim2.new(0, 360, 0, 70), Vector3.zero, 320)
	signLabel.Text = "Freie Base"
	signLabel.TextColor3 = color:Lerp(WHITE, 0.2)

	local meteorFolder = folder("Meteors", model)
	model.Parent = parent

	return {
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
		MeteorParts = {} :: { [number]: Instance },
		MeteorFolder = meteorFolder,
		CollectPad = collectPad,
		CollectLabel = collectLabel,
		LockPad = lockPad,
		LockLabel = lockLabel,
		Barrier = barrier,
		SignLabel = signLabel,
		LockedUntil = 0,
		-- Spawn: vorne in der Mitte zwischen Collect- und Lock-Pad, weit weg von Rand und Slots
		SpawnCFrame = cf * CFrame.new(0, top + 3, -30),
		-- Rauswurf: 8 Studs vor dem Eingang auf der Wiese (zwischen Band-Geländer bei x = ±8.5 und Base)
		EntranceCFrame = cf * CFrame.new(0, 4, -HALF_Z - 8),
	}
end

local function buildPlots(map: Folder): { any }
	local plotsFolder = folder("Plots", map) -- Name wird vom Client gesucht!
	local maxPlots = math.clamp(math.floor(tonumber((Config :: any).MaxPlots) or 8), 1, 2 * #PLOT_Z)
	local plots = {}
	for _, side in ipairs({ -1, 1 }) do
		for _, z in ipairs(PLOT_Z) do
			local index = #plots + 1
			if index > maxPlots then
				break
			end
			local center = Vector3.new(side * PLOT_X, 0, z)
			-- Eingang (lokales -Z) zeigt zum Band in der Mitte
			local cf = CFrame.lookAt(center, center + Vector3.new(-side, 0, 0))
			table.insert(plots, buildPlot(index, cf, PLOT_COLORS[(index - 1) % #PLOT_COLORS + 1], plotsFolder))
		end
	end
	return plots
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
		Vector3.new(0, spawnTop + 3.5, -BELT_LENGTH / 2) -- Blick zum Laufband
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
	model:SetAttribute("Required", def.Required)
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
		Parent = model,
	})
	local backward = -base.LookVector
	belt:SetAttribute("BeltDir", backward)
	belt:SetAttribute("BeltSpeed", TREADMILL_PUSH)
	table.insert(pendingVelocities, { Part = belt, Velocity = backward * TREADMILL_PUSH })
	model.PrimaryPart = belt

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

	local unlocked = def.Required <= 0
	worldSign(beam, "Sign", 14, 5.2, Vector3.new(0, 3.4, 0), 160, {
		{ Name = "NameLabel", Text = def.Name, Color = color:Lerp(WHITE, 0.45), Height = 0.42 },
		{
			Name = "RateLabel",
			Text = "+" .. Util.FormatNumber(def.Rate) .. " 👟",
			Color = Color3.fromRGB(255, 230, 90),
			Height = 0.3,
		},
		{
			Name = "LockLabel",
			Text = unlocked and "✅ Für alle frei" or ("🔒 ab " .. Util.FormatNumber(def.Required) .. " 👟"),
			Color = unlocked and Color3.fromRGB(120, 255, 120) or Color3.fromRGB(255, 130, 130),
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
		{ Name = "Hint", Text = "Drauf laufen = Schritte = schneller!", Color = WHITE, Height = 0.4 },
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

	-- Am Bandende (+Z)
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
	local belt = buildBelt(map)
	local plots = buildPlots(map)
	local lobbySpawn, leaderboardCF, freeZone = buildPlaza(map)
	local treadmillsFolder, treadmillSpawn = buildTreadmills(map)
	buildDeco(map)

	map.Parent = workspace

	-- Erst im Workspace: Förderband-Geschwindigkeiten setzen (verankerte Teile schieben Spieler)
	for _, item in ipairs(pendingVelocities) do
		item.Part.AssemblyLinearVelocity = item.Velocity
	end
	table.clear(pendingVelocities)

	return {
		MapFolder = map,
		Plots = plots,
		Belt = belt,
		LobbySpawn = lobbySpawn,
		LeaderboardCFrame = leaderboardCF,
		FreeZone = freeZone,
		TreadmillsFolder = treadmillsFolder,
		TreadmillSpawn = treadmillSpawn,
	}
end

return MapBuilder
