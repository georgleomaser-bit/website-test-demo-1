-- =====================================================================
--  CLUTCH CLASH – Lobby „Clutch Plaza“ bauen (Server/Services/LobbyBuilder)
--  Besitzer: WP2 (Welt). Vertrag: DESIGN.md B2 (Zonen), B3.2 (Pads), B16.9 (Tafeln), B20.2
--  (Kisten-Automat), C5.3 (API). Koordinaten in World/LobbyLayout. Teilebudget ≤ 2.500 inkl.
--  Crown Ring (baut ArenaService fest an Config.Maps.CrownOrigin) und Range.
--  Die ganze Lobby wird UNPARENTED gebaut und dann EINMAL nach workspace.Lobby geparentet.
--
--  Öffentliche API (C5.3):
--    LobbyBuilder.Pads(): { { Id, Mode, Part, Center, SeatsA, SeatsB } }   (FFA: alle Sitze in SeatsA)
--    LobbyBuilder.RangeZone(): (CFrame, Vector3)
--    LobbyBuilder.RangeDummySpots(): { { Pos: Vector3, Moving: boolean } }    Pos = Boden-Punkt (Y 0)
--    LobbyBuilder.CrownLine(): { Vector3 }                                    6 Kreise (Boden-Punkt)
--    LobbyBuilder.CrownBoard(): BasePart                                      SurfaceGui "KingBoard":
--                                                                             ImageLabel "Avatar", Labels "Name", "Streak"
--    LobbyBuilder.Boards(): { [string]: BasePart }   "Wins","Elims","BestStreak","TotalXP","WeeklyWins","CrownBest"
--                                                    je SurfaceGui "Board" mit "Title" und leeren Rahmen "Row1".."Row10"
--    LobbyBuilder.VipZone(): (CFrame, Vector3)
--    LobbyBuilder.CrateMachine(): Model
--    LobbyBuilder.BotBooth(): { { Pos: Vector3, Difficulty: string } }
--  Welt-Attribute für andere Pakete:
--    Pad-Parts: Mode, PadId (Rest schreibt WP5) · Kiosk-/Regal-/Automat-Prompts: Window (+ Tab beim Automaten)
--    Bot-Kabinen-Prompts: Practice = "<Stufe>" · Part "VipDoor" (Server CanCollide=true; VIP-Clients lokal aus)
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Lang = require(Shared:WaitForChild("Lang"))

local World = script.Parent.Parent:WaitForChild("World")
local MapKit = require(World:WaitForChild("MapKit"))
local Layout = require(World:WaitForChild("LobbyLayout"))

local LobbyBuilder = {}
local Services: any = nil

export type PadInfo = {
	Id: number,
	Mode: string,
	Part: BasePart,
	Center: Vector3,
	SeatsA: { Vector3 },
	SeatsB: { Vector3 },
}

local V = Vector3.new
local NEON = Enum.Material.Neon
local WHITE = Color3.new(1, 1, 1)
local P = MapKit.part
local C = MapKit.Color

local root: Folder? = nil
local pads: { PadInfo } = {}
local boards: { [string]: BasePart } = {}
local crownBoard: BasePart? = nil
local crateMachine: Model? = nil
local dummySpots: { { Pos: Vector3, Moving: boolean } } = {}
local booth: { { Pos: Vector3, Difficulty: string } } = {}
local built = false

-- ---------------------------------------------------------------------
-- Helfer
-- ---------------------------------------------------------------------
-- Zweisprachiger Welt-Text ("DUELLE / DUELS"); gleich in beiden Sprachen -> nur einmal
local function bi(key: string, ...: any): string
	local de = Lang.T("de", key, ...)
	local en = Lang.T("en", key, ...)
	if de == en then
		return de
	end
	return de .. " / " .. en
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Reine Optik: keine Kollision, keine Abfragen, kein Schatten
local function deco(props: { [string]: any }): Part
	props.CanCollide = false
	props.CanQuery = false
	props.CastShadow = false
	return P(props)
end

local function prompt(parent: BasePart, attrs: { [string]: string }, action: string, object: string): ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "Prompt"
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 10
	pp.RequiresLineOfSight = false
	pp.ActionText = action
	pp.ObjectText = object
	for key, value in pairs(attrs) do
		pp:SetAttribute(key, value)
	end
	pp.Parent = parent
	return pp
end

-- Schild-Tafel (Teil + SurfaceGui vorne)
local function signBoard(
	parent: Instance,
	name: string,
	cf: CFrame,
	size: Vector3,
	text: string,
	color: Color3,
	textColor: Color3?
): Part
	local board = P({ Name = name, CFrame = cf, Size = size, Color = color, Parent = parent })
	MapKit.sign(board, Enum.NormalId.Front, { { Text = text, Color = textColor or WHITE } })
	return board
end

-- ---------------------------------------------------------------------
-- 1) Boden, Unterseite, Wege, Rand
-- ---------------------------------------------------------------------
local function buildGround(parent: Folder)
	local ground = folder("Ground", parent)
	for _, def in ipairs(Layout.Floor) do
		P({ Name = def.Name, CFrame = CFrame.new(def.Pos), Size = def.Size, Color = C("Lawn"), Parent = ground })
	end
	-- Unterseite der schwebenden Stadt (Stufen nach unten, nur Optik)
	local navy = C("NavyLight")
	deco({ Name = "Underside", CFrame = CFrame.new(-30, -4, 0), Size = V(196, 6, 216), Color = navy, Parent = ground })
	deco({ Name = "Underside", CFrame = CFrame.new(-30, -10, 0), Size = V(160, 6, 180), Color = navy, Parent = ground })
	deco({ Name = "Underside", CFrame = CFrame.new(-30, -16, 0), Size = V(100, 6, 110), Color = navy, Parent = ground })
	deco({ Name = "Underside", CFrame = CFrame.new(-165, -4, 0), Size = V(66, 6, 108), Color = navy, Parent = ground })
	deco({ Name = "Underside", CFrame = CFrame.new(100, -4, -67.5), Size = V(56, 6, 81), Color = navy, Parent = ground })
	deco({ Name = "Underside", CFrame = CFrame.new(100, -4, 67.5), Size = V(56, 6, 81), Color = navy, Parent = ground })
	-- Wege + Platz + Duell-Hallen-Boden
	for _, path in ipairs(Layout.Paths) do
		deco({ Name = "Path", CFrame = CFrame.new(path.Pos), Size = path.Size, Color = path.Color, Parent = ground })
	end
	MapKit.cyl({ Name = "PlazaDisc", Color = C("Cream"), CanCollide = false, CanQuery = false, Parent = ground }, V(0, 0.035, 0), 0.07, 44)
	deco({
		Name = "DuelFloor",
		CFrame = CFrame.new(Layout.DuelFloor.Pos),
		Size = Layout.DuelFloor.Size,
		Color = C("Navy"),
		Parent = ground,
	})
	deco({ Name = "RangeFloor", CFrame = CFrame.new(-66, 0.04, 0), Size = V(8, 0.08, 112), Color = C("Navy"), Parent = ground })
end

local function buildEdges(parent: Folder)
	local fence = folder("Fence", parent)
	local barriers = folder("Barriers", parent)
	local postColors = { C("Pink"), C("Mint"), C("Lilac"), C("Sand") }
	local postCount = 0
	for index, edge in ipairs(Layout.Edges) do
		local a, b = edge[1], edge[2]
		local delta = b - a
		local length = delta.Magnitude
		local dir = delta.Unit
		local mid = (a + b) / 2
		local alongX = math.abs(dir.X) > 0.5
		-- Barriere 60 hoch (alle Kanten), 1 Stud über die Enden hinaus
		local size = if alongX then V(length + 2, Layout.BarrierHeight, 2) else V(2, Layout.BarrierHeight, length + 2)
		MapKit.barrier(barriers, CFrame.new(mid.X, Layout.BarrierHeight / 2, mid.Z), size)
		-- Sichtbarer Zaun nur am Hauptboden (Range-Kanten haben Wände)
		if index <= 5 then
			local railSize = if alongX then V(length, 0.4, 0.4) else V(0.4, 0.4, length)
			P({ Name = "Rail", CFrame = CFrame.new(mid.X, 1.3, mid.Z), Size = railSize, Color = C("Cream"), Parent = fence })
			P({ Name = "Rail", CFrame = CFrame.new(mid.X, 2.6, mid.Z), Size = railSize, Color = C("Cream"), Parent = fence })
			local posts = math.max(1, math.floor(length / 10))
			for i = 0, posts do
				local p = a + dir * (length * i / posts)
				postCount += 1
				P({
					Name = "Post",
					CFrame = CFrame.new(p.X, Layout.FenceHeight / 2 + 0.1, p.Z),
					Size = V(0.9, Layout.FenceHeight + 0.2, 0.9),
					Color = postColors[(postCount % #postColors) + 1],
					Parent = fence,
				})
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- 2) Spawn-Platz: Brunnen, SpawnLocations, Wegweiser
-- ---------------------------------------------------------------------
local function confettiEmitter(parent: BasePart, rate: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Confetti"
	emitter.Texture = "rbxasset://textures/particles/SquareParticle.png"
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(2.5, 3.5)
	emitter.Speed = NumberRange.new(9, 13)
	emitter.SpreadAngle = Vector2.new(30, 30)
	emitter.Acceleration = V(0, -9, 0)
	emitter.Drag = 0.6
	emitter.Size = NumberSequence.new(0.35)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-180, 180)
	emitter.LightEmission = 0.2
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 210, 40)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 220, 110)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(60, 170, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 60, 170)),
	})
	emitter.Parent = parent
end

local function buildPlaza(parent: Folder)
	local plaza = folder("Plaza", parent)
	local f = Layout.Fountain
	MapKit.cyl({ Name = "FountainBasin", Color = C("Mint"), Parent = plaza }, V(f.X, 0.75, f.Z), 1.5, 8)
	MapKit.cyl({
		Name = "FountainWater",
		Color = C("Water"),
		Transparency = 0.15,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
		Parent = plaza,
	}, V(f.X, 1.45, f.Z), 0.2, 7)
	MapKit.cyl({ Name = "FountainColumn", Color = C("Water"), Parent = plaza }, V(f.X, 2, f.Z), 4, 4)
	local top = deco({ Name = "FountainTop", CFrame = CFrame.new(f.X, 4.2, f.Z), Size = V(1, 0.4, 1), Transparency = 1, Parent = plaza })
	confettiEmitter(top, 4)

	local spawnFolder = folder("Spawns", plaza)
	local spawnColors = { C("Pink"), C("Mint"), C("Lilac"), C("Sand"), C("Pink"), C("Mint") }
	for i, pos in ipairs(Layout.Spawns) do
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "Spawn" .. i
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.AllowTeamChangeOnTouch = false
		spawn.Duration = 0 -- kein ForceField
		spawn.Size = V(6, 1, 6)
		spawn.CFrame = CFrame.new(pos.X, -0.3, pos.Z)
		spawn.Color = spawnColors[i]
		spawn.Material = Enum.Material.SmoothPlastic
		spawn.TopSurface = Enum.SurfaceType.Smooth
		spawn.BottomSurface = Enum.SurfaceType.Smooth
		spawn.CanTouch = true -- SpawnLocation braucht Touched nicht für Neutral, schadet aber nicht
		spawn.Parent = spawnFolder
	end

	-- Wegweiser am Platzrand (je Weg ein Schild, beidseitig beschriftet)
	local signs = {
		{ Pos = V(8, 0, -24), Key = "world.sign.duels", Look = V(0, 0, 1) },
		{ Pos = V(-8, 0, 24), Key = "world.sign.shop", Look = V(0, 0, -1) },
		{ Pos = V(-24, 0, -8), Key = "world.sign.training", Look = V(1, 0, 0) },
		{ Pos = V(24, 0, 8), Key = "world.sign.crown", Look = V(-1, 0, 0) },
	}
	for _, s in ipairs(signs) do
		P({ Name = "SignPost", CFrame = CFrame.new(s.Pos.X, 2.5, s.Pos.Z), Size = V(0.6, 5, 0.6), Color = C("Charcoal"), Parent = plaza })
		local at = V(s.Pos.X, 5.6, s.Pos.Z)
		local board = P({
			Name = "SignBoard",
			CFrame = CFrame.lookAt(at, at + s.Look),
			Size = V(7, 1.8, 0.3),
			Color = C("Navy"),
			Parent = plaza,
		})
		MapKit.sign(board, Enum.NormalId.Front, { { Text = bi(s.Key), Color = C("Yellow") } })
		MapKit.sign(board, Enum.NormalId.Back, { { Text = bi(s.Key), Color = C("Yellow") } }, { Name = "SignBack" })
	end
end

-- ---------------------------------------------------------------------
-- 3) Duell-Halle: Torbogen, 9 Pads, Block-Schriftzug
-- ---------------------------------------------------------------------
local function seatCircle(parent: Instance, pos: Vector3)
	MapKit.cyl({
		Name = "Seat",
		Color = WHITE,
		Material = NEON,
		Transparency = 0.15,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
		Parent = parent,
	}, pos + V(0, 0.03, 0), 0.06, Layout.SeatRadius * 2)
end

local function strip(parent: Instance, cf: CFrame, size: Vector3, color: Color3)
	deco({ Name = "Strip", CFrame = cf, Size = size, Color = color, Material = NEON, Parent = parent })
end

local RAINBOW = {
	Color3.fromRGB(255, 70, 70),
	Color3.fromRGB(255, 160, 50),
	Color3.fromRGB(255, 225, 60),
	Color3.fromRGB(90, 220, 110),
	Color3.fromRGB(60, 170, 255),
	Color3.fromRGB(170, 90, 255),
}

local function buildPad(def: any, parent: Folder): PadInfo
	local c = def.Pos :: Vector3
	local size = Layout.PadSize
	local top = size.Y
	local padFolder = folder("Pad" .. def.Id, parent)
	local part: BasePart
	local seatsA: { Vector3 } = {}
	local seatsB: { Vector3 } = {}
	if def.Ffa then
		part = MapKit.cyl({ Name = "Pad", Color = def.Color }, V(c.X, top / 2, c.Z), top, Layout.FfaPadDiameter)
		MapKit.cyl({
			Name = "PadRim",
			Color = def.Color,
			Material = NEON,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
			Parent = padFolder,
		}, V(c.X, top / 2 - 0.05, c.Z), top - 0.1, Layout.FfaPadDiameter + 0.8)
		for k = 0, def.Seats - 1 do
			local angle = math.rad(k * 360 / def.Seats)
			local seat = V(c.X + math.cos(angle) * Layout.FfaSeatRing, top, c.Z + math.sin(angle) * Layout.FfaSeatRing)
			table.insert(seatsA, seat)
			seatCircle(padFolder, seat)
		end
	else
		part = P({ Name = "Pad", CFrame = CFrame.new(c.X, top / 2, c.Z), Size = size, Color = def.Color })
		local y = top + 0.025
		local hz = size.Z / 2 - 0.25
		local teamA = Config.Colors.TeamA
		local teamB = Config.Colors.TeamB
		-- Hälfte A (X −10..0) orange, Hälfte B (X 0..10) blau: Neon-Rand als „U“
		strip(padFolder, CFrame.new(c.X - 5, y, c.Z - hz), V(10, 0.05, 0.5), teamA)
		strip(padFolder, CFrame.new(c.X - 5, y, c.Z + hz), V(10, 0.05, 0.5), teamA)
		strip(padFolder, CFrame.new(c.X - size.X / 2 + 0.25, y, c.Z), V(0.5, 0.05, size.Z), teamA)
		strip(padFolder, CFrame.new(c.X + 5, y, c.Z - hz), V(10, 0.05, 0.5), teamB)
		strip(padFolder, CFrame.new(c.X + 5, y, c.Z + hz), V(10, 0.05, 0.5), teamB)
		strip(padFolder, CFrame.new(c.X + size.X / 2 - 0.25, y, c.Z), V(0.5, 0.05, size.Z), teamB)
		deco({ Name = "Divider", CFrame = CFrame.new(c.X, y, c.Z), Size = V(0.3, 0.05, size.Z - 1), Color = WHITE, Parent = padFolder })
		for _, dz in ipairs(Layout.SeatOffsets[def.Seats] or { 0 }) do
			local a = V(c.X - 5, top, c.Z + dz)
			local b = V(c.X + 5, top, c.Z + dz)
			table.insert(seatsA, a)
			table.insert(seatsB, b)
			seatCircle(padFolder, a)
			seatCircle(padFolder, b)
		end
		if def.Mode == "Mutator" then
			-- Regenbogen-Neon-Rand (außen um das Pad)
			local segment = size.X / 3
			for i = 0, 2 do
				local x = c.X - size.X / 2 + segment * (i + 0.5)
				strip(padFolder, CFrame.new(x, top / 2, c.Z - size.Z / 2 - 0.3), V(segment, top, 0.6), RAINBOW[i + 1])
				strip(padFolder, CFrame.new(x, top / 2, c.Z + size.Z / 2 + 0.3), V(segment, top, 0.6), RAINBOW[6 - i])
			end
		end
	end
	part.Name = "Pad"
	part:SetAttribute("Mode", def.Mode)
	part:SetAttribute("PadId", def.Id)
	part.Parent = padFolder
	return { Id = def.Id, Mode = def.Mode, Part = part, Center = V(c.X, top, c.Z), SeatsA = seatsA, SeatsB = seatsB }
end

local function buildDuelHall(parent: Folder)
	local hall = folder("DuelHall", parent)
	-- Torbogen mit Schild „DUELLE / DUELS“
	local s = Layout.DuelSign
	P({ Name = "ArchPost", CFrame = CFrame.new(s.X - 21, 8.5, s.Z), Size = V(2, 17, 2), Color = C("Lilac"), Parent = hall })
	P({ Name = "ArchPost", CFrame = CFrame.new(s.X + 21, 8.5, s.Z), Size = V(2, 17, 2), Color = C("Lilac"), Parent = hall })
	local board = signBoard(hall, "DuelSign", CFrame.lookAt(s, s + V(0, 0, 1)), V(40, 6, 1), bi("world.sign.duels"), C("Navy"), C("Yellow"))
	MapKit.sign(board, Enum.NormalId.Back, { { Text = bi("world.sign.duels"), Color = C("Yellow") } }, { Name = "SignBack" })
	deco({ Name = "ArchTrim", CFrame = CFrame.new(s.X, s.Y + 3.3, s.Z), Size = V(44, 0.6, 1.4), Color = C("Pink"), Parent = hall })

	-- Pads
	local padFolder = folder("Pads", hall)
	table.clear(pads)
	for _, def in ipairs(Layout.Pads) do
		table.insert(pads, buildPad(def, padFolder))
	end

	-- Großer Block-Schriftzug „CLUTCH CLASH“ (Spielzeug-Buchstabenklötze vor einer Wand)
	local l = Layout.Letters
	P({ Name = "LetterWall", CFrame = CFrame.new(l.X, l.Y, -109.5), Size = V(84, 14, 1), Color = C("Navy"), Parent = hall })
	P({ Name = "LetterLeg", CFrame = CFrame.new(l.X - 38, 4.5, -109.5), Size = V(3, 9, 1), Color = C("Charcoal"), Parent = hall })
	P({ Name = "LetterLeg", CFrame = CFrame.new(l.X + 38, 4.5, -109.5), Size = V(3, 9, 1), Color = C("Charcoal"), Parent = hall })
	local text = "CLUTCH CLASH"
	local colors = { C("Pink"), C("Mint"), C("Lilac"), C("Sand"), C("Orange"), C("Blue") }
	local count = #text
	local colorIndex = 0
	for i = 1, count do
		local ch = string.sub(text, i, i)
		if ch ~= " " then
			colorIndex += 1
			local x = l.X + (i - (count + 1) / 2) * 6.6
			local cube = P({
				Name = "LetterBlock",
				CFrame = CFrame.new(x, l.Y, -106),
				Size = V(6, 6, 6),
				Color = colors[(colorIndex - 1) % #colors + 1],
				Parent = hall,
			})
			MapKit.surfaceLetter(cube, ch, { Enum.NormalId.Back })
		end
	end
end

-- ---------------------------------------------------------------------
-- 4) Crown Ring: Tribünen, Herausforderer-Linie, Königs-Tafel
-- ---------------------------------------------------------------------
local function buildCrownArea(parent: Folder)
	local area = folder("CrownArea", parent)
	local standColors = { C("Lilac"), C("Pink"), C("Lilac"), C("Pink") }
	for i, stand in ipairs(Layout.CrownStands) do
		P({ Name = "Stand", CFrame = CFrame.new(stand.Pos), Size = stand.Size, Color = standColors[i], Parent = area })
	end
	-- Schild über der Nord-Tribüne (Blick nach Süden über die Grube)
	local signPos = V(95, 9, -35)
	P({ Name = "SignPost", CFrame = CFrame.new(80, 6, -35.5), Size = V(1, 6, 1), Color = C("Charcoal"), Parent = area })
	P({ Name = "SignPost", CFrame = CFrame.new(110, 6, -35.5), Size = V(1, 6, 1), Color = C("Charcoal"), Parent = area })
	local crownSign = signBoard(area, "CrownSign", CFrame.lookAt(signPos, signPos + V(0, 0, 1)), V(32, 4, 0.6), bi("world.sign.crown"), C("Navy"), C("Gold"))
	MapKit.sign(crownSign, Enum.NormalId.Back, { { Text = bi("world.sign.crown"), Color = C("Gold") } }, { Name = "SignBack" })

	-- Herausforderer-Linie: 6 Neon-Kreise r 1.6
	for _, pos in ipairs(Layout.CrownLine) do
		MapKit.cyl({
			Name = "ChallengerSpot",
			Color = C("Gold"),
			Material = NEON,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
			Parent = area,
		}, V(pos.X, 0.05, pos.Z), 0.1, Layout.SeatRadius * 2)
	end
	local lineSignPos = V(58, 4.5, -14)
	P({ Name = "SignPost", CFrame = CFrame.new(58, 1.8, -14), Size = V(0.6, 3.6, 0.6), Color = C("Charcoal"), Parent = area })
	signBoard(area, "ChallengerSign", CFrame.lookAt(lineSignPos, lineSignPos + V(-1, 0, 0)), V(9, 1.8, 0.3), bi("world.sign.challengers"), C("Navy"), C("Gold"))

	-- Königs-Tafel 20×10 bei (128,10,0), Blick nach Westen
	local def = Layout.CrownBoard
	local cf = CFrame.lookAt(def.Pos, def.Pos + def.Look)
	local boardPart = P({ Name = "CrownBoard", CFrame = cf, Size = def.Size, Color = C("Navy"), Parent = area })
	P({ Name = "BoardLeg", CFrame = cf * CFrame.new(-8, -5, 0.8), Size = V(1, 10, 1), Color = C("Charcoal"), Parent = area })
	P({ Name = "BoardLeg", CFrame = cf * CFrame.new(8, -5, 0.8), Size = V(1, 10, 1), Color = C("Charcoal"), Parent = area })
	deco({ Name = "BoardTrim", CFrame = cf * CFrame.new(0, 5.3, 0), Size = V(21, 0.6, 1.6), Color = C("Gold"), Parent = area })

	local gui = Instance.new("SurfaceGui")
	gui.Name = "KingBoard"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.MaxDistance = 400
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0.05, 0.04)
	title.Size = UDim2.fromScale(0.9, 0.22)
	title.Font = Enum.Font.LuckiestGuy
	title.TextScaled = true
	title.TextColor3 = C("Gold")
	title.Text = "👑 " .. bi("world.crown.king")
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Thickness = 5
	titleStroke.Parent = title
	title.Parent = gui
	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.BackgroundColor3 = C("NavyLight")
	avatar.BorderSizePixel = 0
	avatar.Position = UDim2.fromScale(0.05, 0.3)
	avatar.Size = UDim2.fromScale(0.3, 0.62)
	avatar.Image = ""
	avatar.ScaleType = Enum.ScaleType.Fit
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.12, 0)
	corner.Parent = avatar
	avatar.Parent = gui
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.fromScale(0.39, 0.32)
	nameLabel.Size = UDim2.fromScale(0.58, 0.3)
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = WHITE
	nameLabel.Text = bi("world.crown.empty")
	local nameStroke = Instance.new("UIStroke")
	nameStroke.Thickness = 4
	nameStroke.Parent = nameLabel
	nameLabel.Parent = gui
	local streak = Instance.new("TextLabel")
	streak.Name = "Streak"
	streak.BackgroundTransparency = 1
	streak.Position = UDim2.fromScale(0.39, 0.64)
	streak.Size = UDim2.fromScale(0.58, 0.26)
	streak.Font = Enum.Font.FredokaOne
	streak.TextScaled = true
	streak.TextColor3 = C("Yellow")
	streak.Text = ""
	local streakStroke = Instance.new("UIStroke")
	streakStroke.Thickness = 4
	streakStroke.Parent = streak
	streak.Parent = gui
	gui.Parent = boardPart
	crownBoard = boardPart

	-- Krone über der Tafel (Spielzeug-Krone aus Teilen)
	local crownCf = cf * CFrame.new(0, 8, 0)
	MapKit.cyl({ Name = "CrownBase", Color = C("Gold"), Material = Enum.Material.Foil, CastShadow = false, Parent = area }, crownCf.Position, 1.6, 6)
	for i = 0, 4 do
		local angle = math.rad(i * 72)
		local pos = crownCf.Position + V(math.cos(angle) * 2.4, 1.6, math.sin(angle) * 2.4)
		deco({ Name = "CrownSpike", CFrame = CFrame.new(pos), Size = V(1, 1.8, 1), Color = C("Gold"), Parent = area })
		MapKit.ball({ Name = "CrownGem", Color = RAINBOW[(i % #RAINBOW) + 1], Material = NEON, CanCollide = false, CanQuery = false, CastShadow = false, Parent = area }, pos + V(0, 1.2, 0), 0.8)
	end
end

-- ---------------------------------------------------------------------
-- 5) Training / Range (Model "Range")
-- ---------------------------------------------------------------------
local function buildRange(parent: Folder): Model
	local r = Layout.Range
	local model = Instance.new("Model")
	model.Name = Layout.RangeName
	local laneLength = r.DividerFromX - r.DividerToX
	local laneMidX = (r.DividerFromX + r.DividerToX) / 2

	-- Bahnen (Deko-Boden abwechselnd), Trenner 1 hoch
	for i, z in ipairs(r.Lanes) do
		deco({
			Name = "Lane",
			CFrame = CFrame.new(laneMidX, 0.03, z),
			Size = V(laneLength, 0.06, 13),
			Color = if i % 2 == 0 then C("Sand") else C("Cream"),
			Parent = model,
		})
		local label = deco({ Name = "LaneNumber", CFrame = CFrame.new(-68.5, 0.07, z), Size = V(3, 0.05, 3), Color = C("Navy"), Parent = model })
		MapKit.sign(label, Enum.NormalId.Top, { { Text = tostring(i), Color = C("Yellow") } }, { Name = "LaneSign" })
		-- Bullseye an der Rückwand
		local tx = r.BackX + 1.2
		for k, d in ipairs({ 8, 5, 2 }) do
			deco({
				Name = "Target",
				Shape = Enum.PartType.Cylinder,
				CFrame = CFrame.new(tx + k * 0.1, 6, z),
				Size = V(0.3, d, d),
				Color = if k % 2 == 1 then C("Red") else WHITE,
				Parent = model,
			})
		end
	end
	for _, z in ipairs(r.Dividers) do
		P({ Name = "Divider", CFrame = CFrame.new(laneMidX, 0.5, z), Size = V(laneLength, 1, 0.6), Color = C("Charcoal"), Parent = model })
	end
	-- Schusslinie (Blick nach −X)
	strip(model, CFrame.new(r.ShootX, 0.09, 0), V(0.6, 0.05, 112), C("Yellow"))
	-- Entfernungs-Pfosten am Nord-Rand
	for i, x in ipairs(r.DummyX) do
		local post = P({ Name = "DistancePost", CFrame = CFrame.new(x, 2, -45), Size = V(1, 4, 1), Color = C("Charcoal"), Parent = model })
		local board = P({
			Name = "DistanceSign",
			CFrame = CFrame.lookAt(V(x, 4.8, -45), V(x + 1, 4.8, -45)),
			Size = V(5, 1.4, 0.3),
			Color = C("Navy"),
			Parent = model,
		})
		MapKit.sign(board, Enum.NormalId.Front, { { Text = bi("world.sign.distance", r.DummyDistances[i]), Color = WHITE } })
		post:SetAttribute("Distance", r.DummyDistances[i])
		deco({ Name = "DistanceLine", CFrame = CFrame.new(x, 0.08, 0), Size = V(0.4, 0.05, 84), Color = C("PureWhite"), Parent = model })
	end
	-- Schienen der zwei beweglichen Puppen
	for _, lane in ipairs(r.RailLanes) do
		local z = r.Lanes[lane]
		deco({
			Name = "Rail",
			CFrame = CFrame.new(r.RailX, 0.1, z),
			Size = V(0.8, 0.1, r.RailSwing * 2 + 2),
			Color = C("Steel"),
			Material = Enum.Material.Foil,
			Parent = model,
		})
	end
	-- Rückwand + Seitenwände
	P({ Name = "BackWall", CFrame = CFrame.new(r.BackX, 10, 0), Size = V(2, 20, 112), Color = C("Mint"), Parent = model })
	P({ Name = "SideWall", CFrame = CFrame.new(-165, 5, -56.5), Size = V(70, 10, 1), Color = C("Lilac"), Parent = model })
	P({ Name = "SideWall", CFrame = CFrame.new(-165, 5, 56.5), Size = V(70, 10, 1), Color = C("Lilac"), Parent = model })
	deco({ Name = "WallCap", CFrame = CFrame.new(r.BackX, 20.3, 0), Size = V(2.4, 0.6, 112.4), Color = C("Charcoal"), Parent = model })
	-- Torbogen „TRAINING“ über der Schusslinie (Schild nach Osten)
	P({ Name = "GantryPost", CFrame = CFrame.new(-62, 6, -20), Size = V(1.5, 12, 1.5), Color = C("Charcoal"), Parent = model })
	P({ Name = "GantryPost", CFrame = CFrame.new(-62, 6, 20), Size = V(1.5, 12, 1.5), Color = C("Charcoal"), Parent = model })
	local beamPos = V(-62, 13.5, 0)
	local beam = signBoard(model, "TrainingSign", CFrame.lookAt(beamPos, beamPos + V(1, 0, 0)), V(42, 3, 1.5), bi("world.sign.training"), C("Navy"), C("Yellow"))
	MapKit.sign(beam, Enum.NormalId.Back, { { Text = bi("world.sign.training"), Color = C("Yellow") } }, { Name = "SignBack" })

	-- Bot-Duell-Kabine: 4 Pads mit Prompt-Attribut Practice = "<Stufe>"
	table.clear(booth)
	local boothFolder = folder("BotBooth", model)
	for i, x in ipairs(r.BoothX) do
		local difficulty = r.BoothDifficulties[i]
		local color = r.BoothColors[i]
		local pad = P({
			Name = "BoothPad",
			CFrame = CFrame.new(x, r.BoothPadSize.Y / 2, r.BoothZ),
			Size = r.BoothPadSize,
			Color = color,
			Parent = boothFolder,
		})
		pad:SetAttribute("Practice", difficulty)
		prompt(pad, { Practice = difficulty }, bi("world.prompt.practice"), bi("world.diff." .. difficulty))
		strip(boothFolder, CFrame.new(x, r.BoothPadSize.Y + 0.03, r.BoothZ), V(3.2, 0.05, 3.2), color:Lerp(WHITE, 0.3))
		local signPos = V(x, 3.2, r.BoothZ + 3.5)
		P({ Name = "BoothPost", CFrame = CFrame.new(x, 1.3, r.BoothZ + 3.5), Size = V(0.5, 2.6, 0.5), Color = C("Charcoal"), Parent = boothFolder })
		signBoard(boothFolder, "BoothSign", CFrame.lookAt(signPos, signPos + V(0, 0, -1)), V(6, 1.4, 0.3), bi("world.diff." .. difficulty), color, WHITE)
		table.insert(booth, { Pos = V(x, r.BoothPadSize.Y, r.BoothZ), Difficulty = difficulty })
	end
	local boothMidX = (r.BoothX[1] + r.BoothX[#r.BoothX]) / 2
	for _, corner in ipairs({ { -18, -5 }, { 18, -5 }, { -18, 6 }, { 18, 6 } }) do
		P({
			Name = "CanopyPost",
			CFrame = CFrame.new(boothMidX + corner[1], 5, r.BoothZ + corner[2]),
			Size = V(0.8, 10, 0.8),
			Color = C("Lilac"),
			Parent = boothFolder,
		})
	end
	P({ Name = "CanopyRoof", CFrame = CFrame.new(boothMidX, 10.3, r.BoothZ + 0.5), Size = V(38, 0.6, 12.5), Color = C("Pink"), Parent = boothFolder })
	local canopySign = V(boothMidX, 9, r.BoothZ - 5.4)
	signBoard(boothFolder, "BoothTitle", CFrame.lookAt(canopySign, canopySign + V(0, 0, -1)), V(30, 2, 0.4), bi("world.sign.botBooth"), C("Navy"), C("Yellow"))

	-- Waffen-Regal (öffnet das Training-Fenster)
	local rackDef = r.Rack
	local rack = P({ Name = "WeaponRack", CFrame = CFrame.new(rackDef.Pos), Size = rackDef.Size, Color = C("Wood"), Material = Enum.Material.WoodPlanks, Parent = model })
	prompt(rack, { Window = "Training" }, bi("world.prompt.open"), bi("world.sign.rack"))
	local rackTop = rackDef.Pos + V(0, rackDef.Size.Y / 2 + 1.2, 0)
	signBoard(model, "RackSign", CFrame.lookAt(rackTop, rackTop + V(0, 0, 1)), V(14, 2, 0.4), bi("world.sign.rack"), C("Navy"), C("Yellow"))
	-- Spielzeug-Blaster an der Wand (orange Spitze, Muss-Regel 12)
	local blasterColors = { C("Pink"), C("Mint"), C("Lilac"), C("Blue") }
	for i = 1, 4 do
		local x = rackDef.Pos.X - 10.5 + (i - 1) * 7
		local y = rackDef.Pos.Y + (if i % 2 == 0 then 1 else -1)
		local z = rackDef.Pos.Z + rackDef.Size.Z / 2 + 0.5
		deco({ Name = "ToyBlaster", CFrame = CFrame.new(x, y, z), Size = V(4, 1, 0.8), Color = blasterColors[i], Parent = model })
		deco({ Name = "ToyBlasterTip", CFrame = CFrame.new(x - 2.3, y, z), Size = V(0.6, 0.8, 0.7), Color = C("Tip"), Parent = model })
		deco({ Name = "ToyBlasterGrip", CFrame = CFrame.new(x + 0.8, y - 0.9, z), Size = V(0.7, 1.2, 0.6), Color = C("Charcoal"), Parent = model })
	end

	-- Puppen-Plätze (Boden-Punkte) für WP6 RangeService
	table.clear(dummySpots)
	for _, z in ipairs(r.Lanes) do
		for _, x in ipairs(r.DummyX) do
			table.insert(dummySpots, { Pos = V(x, 0, z), Moving = false })
		end
	end
	for _, lane in ipairs(r.RailLanes) do
		table.insert(dummySpots, { Pos = V(r.RailX, 0, r.Lanes[lane]), Moving = true })
	end

	model.WorldPivot = CFrame.new((r.ZoneMin.X + r.ZoneMax.X) / 2, 0, (r.ZoneMin.Z + r.ZoneMax.Z) / 2)
	model.Parent = parent
	return model
end

-- ---------------------------------------------------------------------
-- 6) Shop-Straße: Kiosk-Buden + Kisten-Automat
-- ---------------------------------------------------------------------
local function buildKiosk(def: any, parent: Folder)
	local model = Instance.new("Model")
	model.Name = "Kiosk_" .. def.Window
	local pos = def.Pos :: Vector3
	local base = CFrame.lookAt(V(pos.X, 0, pos.Z), V(0, 0, 0)) -- Front zur Platz-Mitte
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end
	local color = def.Color :: Color3
	local roof = def.Roof :: Color3
	P({ Name = "Plinth", CFrame = at(0, 0.2, 0), Size = V(8.4, 0.4, 6.4), Color = C("Charcoal"), Parent = model })
	P({ Name = "Back", CFrame = at(0, 4.1, 2.5), Size = V(8, 7.4, 1), Color = color:Lerp(WHITE, 0.35), Parent = model })
	P({ Name = "Post", CFrame = at(-3.6, 4.1, -2.6), Size = V(0.8, 7.4, 0.8), Color = WHITE, Parent = model })
	P({ Name = "Post", CFrame = at(3.6, 4.1, -2.6), Size = V(0.8, 7.4, 0.8), Color = WHITE, Parent = model })
	P({ Name = "Side", CFrame = at(-3.6, 1.9, 0.4), Size = V(0.8, 3, 4.2), Color = color, Parent = model })
	P({ Name = "Side", CFrame = at(3.6, 1.9, 0.4), Size = V(0.8, 3, 4.2), Color = color, Parent = model })
	local counter = P({ Name = "Counter", CFrame = at(0, 1.9, -2.3), Size = V(6.4, 3, 1.2), Color = color, Parent = model })
	P({ Name = "Roof", CFrame = at(0, 8.1, 0), Size = V(9, 0.6, 7), Color = roof, Parent = model })
	MapKit.wedge({ Name = "Awning", CFrame = at(0, 7.2, -4.3), Size = V(9, 1.2, 2), Color = color, CastShadow = false, Parent = model })
	local signCf = at(0, 9.3, -2.9)
	local sign = P({ Name = "KioskSign", CFrame = signCf, Size = V(7.5, 1.8, 0.3), Color = C("Navy"), Parent = model })
	MapKit.sign(sign, Enum.NormalId.Front, { { Text = bi(def.Label), Color = C("Yellow") } })
	prompt(counter, { Window = def.Window }, bi("world.prompt.open"), bi(def.Label))
	model.WorldPivot = base
	model.Parent = parent
end

local function buildCrateMachine(parent: Folder): Model
	local def = Layout.Crate
	local model = Instance.new("Model")
	model.Name = "CrateMachine"
	local base = CFrame.lookAt(V(def.Pos.X, 0, def.Pos.Z), V(def.Pos.X, 0, def.Pos.Z - 1)) -- Front nach Norden
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end
	local foot = P({ Name = "Base", CFrame = at(0, 1.5, 0), Size = V(12, 3, 12), Color = C("Lilac"), Parent = model })
	for _, c in ipairs({ { -5.5, -5.5 }, { 5.5, -5.5 }, { -5.5, 5.5 }, { 5.5, 5.5 } }) do
		P({ Name = "Pillar", CFrame = at(c[1], 7.5, c[2]), Size = V(1, 9, 1), Color = C("Pink"), Parent = model })
	end
	P({
		Name = "Glass",
		CFrame = at(0, 7.5, 0),
		Size = V(10, 9, 10),
		Color = WHITE,
		Material = Enum.Material.Glass,
		Transparency = 0.5,
		Parent = model,
	})
	deco({ Name = "Crate", CFrame = at(0, 5.5, 0) * CFrame.Angles(0, math.rad(20), 0), Size = V(4, 4, 4), Color = C("Sand"), Parent = model })
	deco({ Name = "CrateBand", CFrame = at(0, 5.5, 0) * CFrame.Angles(0, math.rad(20), 0), Size = V(4.2, 0.6, 4.2), Color = C("NeonPink"), Material = NEON, Parent = model })
	P({ Name = "Cap", CFrame = at(0, 13, 0), Size = V(12, 2, 12), Color = C("Pink"), Parent = model })
	MapKit.ball({ Name = "Topper", Color = C("Yellow"), CastShadow = false, Parent = model }, at(0, 15.2, 0).Position, 2.6)
	local sign = P({ Name = "CrateSign", CFrame = at(0, 13, -6.2), Size = V(10, 1.6, 0.3), Color = C("Navy"), Parent = model })
	MapKit.sign(sign, Enum.NormalId.Front, { { Text = bi("world.sign.crates"), Color = C("Yellow") } })
	local pp = prompt(foot, { Window = "Shop", Tab = "Crates" }, bi("world.prompt.open"), bi("world.sign.crates"))
	pp.UIOffset = Vector2.new(0, 40)
	model.WorldPivot = base
	model.Parent = parent
	return model
end

local function buildShopStreet(parent: Folder)
	local street = folder("ShopStreet", parent)
	for _, def in ipairs(Layout.Kiosks) do
		buildKiosk(def, street)
	end
	crateMachine = buildCrateMachine(street)
end

-- ---------------------------------------------------------------------
-- 7) Bestenlisten-Tafeln (leere SurfaceGui "Board" mit 10 Zeilen-Rahmen, Titel zweisprachig)
-- ---------------------------------------------------------------------
local function boardGui(part: BasePart, title: string)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Board"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.MaxDistance = 300
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.fromScale(0.04, 0.02)
	titleLabel.Size = UDim2.fromScale(0.92, 0.14)
	titleLabel.Font = Enum.Font.LuckiestGuy
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = C("Yellow")
	titleLabel.Text = title
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 5
	stroke.Parent = titleLabel
	titleLabel.Parent = gui
	local rowHeight = 0.078
	for i = 1, Layout.BoardRows do
		local row = Instance.new("Frame")
		row.Name = "Row" .. i
		row.Position = UDim2.fromScale(0.04, 0.18 + (i - 1) * (rowHeight + 0.004))
		row.Size = UDim2.fromScale(0.92, rowHeight)
		row.BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(40, 46, 88) else Color3.fromRGB(52, 60, 110)
		row.BackgroundTransparency = 0.1
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.25, 0)
		corner.Parent = row
		row.Parent = gui
	end
	gui.Parent = part
end

local function buildBoards(parent: Folder)
	local boardFolder = folder("Boards", parent)
	table.clear(boards)
	for i, key in ipairs(Layout.BoardKeys) do
		local x = Layout.BoardX[i]
		local pos = V(x, Layout.BoardY, Layout.BoardZ)
		local cf = CFrame.lookAt(pos, pos + V(0, 0, -1)) -- Blick nach Norden
		local part = P({ Name = "Board_" .. key, CFrame = cf, Size = Layout.BoardSize, Color = C("Navy"), Parent = boardFolder })
		part:SetAttribute("Board", key)
		P({ Name = "BoardPost", CFrame = cf * CFrame.new(-9, -1, 0.9), Size = V(1, 14, 1), Color = C("Charcoal"), Parent = boardFolder })
		P({ Name = "BoardPost", CFrame = cf * CFrame.new(9, -1, 0.9), Size = V(1, 14, 1), Color = C("Charcoal"), Parent = boardFolder })
		deco({ Name = "BoardCap", CFrame = cf * CFrame.new(0, 6.4, 0), Size = V(21, 0.8, 1.6), Color = C("Pink"), Parent = boardFolder })
		boardGui(part, bi("world.board." .. key))
		boards[key] = part
	end
end

-- ---------------------------------------------------------------------
-- 8) VIP-Balkon mit Wendeltreppe hinter der VIP-Tür
-- ---------------------------------------------------------------------
local function buildVip(parent: Folder)
	local vip = folder("Vip", parent)
	local def = Layout.Vip
	local plat = def.Platform
	P({ Name = "VipPlatform", CFrame = CFrame.new(plat.Pos), Size = plat.Size, Color = C("Lilac"), Parent = vip })
	local top = plat.Pos.Y + plat.Size.Y / 2
	local bottom = plat.Pos.Y - plat.Size.Y / 2
	local hx, hz = plat.Size.X / 2, plat.Size.Z / 2
	local cx, cz = plat.Pos.X, plat.Pos.Z
	-- Stützen: östliche Reihe bei x −60, damit Pad P5 (x −58..−38) frei bleibt
	for _, c in ipairs({ { -hx + 2, -hz + 2 }, { 10, -hz + 2 }, { -hx + 2, hz - 2 }, { 10, hz - 2 } }) do
		P({ Name = "VipPillar", CFrame = CFrame.new(cx + c[1], bottom / 2, cz + c[2]), Size = V(1.5, bottom, 1.5), Color = WHITE, Parent = vip })
	end
	-- Glas-Geländer (Süd-Seite mit Lücke für die Treppe)
	local glass = { Material = Enum.Material.Glass, Transparency = 0.45, Color = WHITE }
	local function rail(cf: CFrame, size: Vector3)
		P({ Name = "VipRail", CFrame = cf, Size = size, Color = glass.Color, Material = glass.Material, Transparency = glass.Transparency, Parent = vip })
	end
	local t = def.Tower
	rail(CFrame.new(cx, top + 1.5, cz - hz + 0.25), V(plat.Size.X, 3, 0.5))
	rail(CFrame.new(cx - hx + 0.25, top + 1.5, cz), V(0.5, 3, plat.Size.Z))
	rail(CFrame.new(cx + hx - 0.25, top + 1.5, cz), V(0.5, 3, plat.Size.Z))
	local southZ = cz + hz - 0.25
	local leftLen = t.MinX - (cx - hx)
	local rightLen = (cx + hx) - t.MaxX
	rail(CFrame.new(cx - hx + leftLen / 2, top + 1.5, southZ), V(leftLen, 3, 0.5))
	rail(CFrame.new(cx + hx - rightLen / 2, top + 1.5, southZ), V(rightLen, 3, 0.5))
	deco({ Name = "VipTrim", CFrame = CFrame.new(cx, top - 0.3, cz + hz + 0.1), Size = V(plat.Size.X + 0.4, 0.6, 0.4), Color = C("Gold"), Material = Enum.Material.Foil, Parent = vip })
	deco({ Name = "VipTrim", CFrame = CFrame.new(cx, top - 0.3, cz - hz - 0.1), Size = V(plat.Size.X + 0.4, 0.6, 0.4), Color = C("Gold"), Material = Enum.Material.Foil, Parent = vip })
	local vipSign = V(cx - 12, bottom - 1.4, cz + hz + 0.3)
	signBoard(vip, "VipSign", CFrame.lookAt(vipSign, vipSign + V(0, 0, 1)), V(10, 2.4, 0.3), bi("world.sign.vip"), C("Navy"), C("Gold"))
	-- Sofas
	for _, x in ipairs({ cx - 8, cx + 8 }) do
		P({ Name = "SofaSeat", CFrame = CFrame.new(x, top + 0.6, cz - 6), Size = V(8, 1.2, 3), Color = C("Pink"), Parent = vip })
		P({ Name = "SofaBack", CFrame = CFrame.new(x, top + 1.8, cz - 7.7), Size = V(8, 2.4, 0.6), Color = C("Pink"), Parent = vip })
	end

	-- Treppenturm: Wände bis Y 15 (Rückwand nur bis unter den Balkon), Tür vorne
	local tower = folder("VipTower", vip)
	local midZ = (t.MinZ + t.MaxZ) / 2
	local depth = t.MaxZ - t.MinZ
	P({ Name = "TowerWall", CFrame = CFrame.new(t.MinX + 0.5, t.Top / 2, midZ), Size = V(1, t.Top, depth), Color = C("Lilac"), Parent = tower })
	P({ Name = "TowerWall", CFrame = CFrame.new(t.MaxX - 0.5, t.Top / 2, midZ), Size = V(1, t.Top, depth), Color = C("Lilac"), Parent = tower })
	local innerW = (t.MaxX - t.MinX) - 2
	P({ Name = "TowerBack", CFrame = CFrame.new((t.MinX + t.MaxX) / 2, bottom / 2, t.MinZ + 0.5), Size = V(innerW, bottom, 1), Color = C("Lilac"), Parent = tower })
	local door = def.Door
	local doorHalf = door.Size.X / 2
	local frontZ = door.Pos.Z
	local leftW = (door.Pos.X - doorHalf) - (t.MinX + 1)
	local rightW = (t.MaxX - 1) - (door.Pos.X + doorHalf)
	if leftW > 0.05 then
		P({ Name = "TowerFront", CFrame = CFrame.new(t.MinX + 1 + leftW / 2, t.Top / 2, frontZ), Size = V(leftW, t.Top, 1), Color = C("Lilac"), Parent = tower })
	end
	if rightW > 0.05 then
		P({ Name = "TowerFront", CFrame = CFrame.new(t.MaxX - 1 - rightW / 2, t.Top / 2, frontZ), Size = V(rightW, t.Top, 1), Color = C("Lilac"), Parent = tower })
	end
	local lintelH = t.Top - door.Size.Y
	P({
		Name = "TowerLintel",
		CFrame = CFrame.new(door.Pos.X, door.Size.Y + lintelH / 2, frontZ),
		Size = V(door.Size.X, lintelH, 1),
		Color = C("Lilac"),
		Parent = tower,
	})
	local vipDoor = P({ Name = "VipDoor", CFrame = CFrame.new(door.Pos), Size = door.Size, Color = C("Gold"), Material = Enum.Material.Foil, Parent = vip })
	vipDoor.CanCollide = true -- Server: zu. VIP-Clients schalten lokal CanCollide aus (WP9).
	MapKit.sign(vipDoor, Enum.NormalId.Back, { { Text = bi("world.sign.vipOnly"), Color = C("Navy") } })
	-- Wendeltreppe: 14 Stufen à 1 Stud, 30° pro Stufe, letzte Stufe zeigt nach −Z auf den Balkon
	local center = def.StairCenter
	MapKit.cyl({ Name = "StairColumn", Color = WHITE, Parent = tower }, V(center.X, t.Top / 2, center.Z), t.Top, def.StairInner * 2)
	for i = 0, def.StairSteps - 1 do
		local theta = math.rad(240 + 30 * i)
		local last = i == def.StairSteps - 1
		local outer = if last then def.StairOuter + 1 else def.StairOuter
		local radial = outer - def.StairInner
		local mid = def.StairInner + radial / 2
		local cf = CFrame.new(center.X, i + 0.5, center.Z) * CFrame.Angles(0, -theta, 0) * CFrame.new(mid, 0, 0)
		P({ Name = "Step", CFrame = cf, Size = V(radial, 1, 2.1), Color = if i % 2 == 0 then C("Pink") else C("Mint"), Parent = tower })
	end
end

-- ---------------------------------------------------------------------
-- 9) Deko: Bäume, Laternen, Bänke, Ballons, Blumenbeete
-- ---------------------------------------------------------------------
local function tree(parent: Instance, x: number, z: number, scale: number, leaf: Color3)
	P({ Name = "TreeTrunk", CFrame = CFrame.new(x, 2.5 * scale, z), Size = V(1.2, 5, 1.2) * scale, Color = C("Bark"), Parent = parent })
	P({ Name = "TreeLeaves", CFrame = CFrame.new(x, 6.5 * scale, z), Size = V(5, 4, 5) * scale, Color = leaf, Parent = parent })
	P({ Name = "TreeLeaves", CFrame = CFrame.new(x, 9.3 * scale, z), Size = V(3.4, 2.6, 3.4) * scale, Color = leaf:Lerp(WHITE, 0.15), Parent = parent })
end

local function buildDeco(parent: Folder)
	local decoFolder = folder("Deco", parent)
	local leafA = Color3.fromRGB(110, 200, 110)
	local leafB = Color3.fromRGB(150, 215, 120)
	local trees = {
		{ 21, -21 },
		{ -21, -21 },
		{ 21, 21 },
		{ -21, 21 },
		{ -115, -90 },
		{ -115, 80 },
		{ 115, 85 },
		{ 110, -95 },
		{ 60, -38 },
		{ -60, -38 },
		{ 60, 40 },
		{ -60, 40 },
		{ 110, -40 },
		{ 110, 40 },
	}
	for i, t in ipairs(trees) do
		tree(decoFolder, t[1], t[2], if i % 3 == 0 then 1.25 else 1, if i % 2 == 0 then leafA else leafB)
	end
	-- Laternen entlang der Wege
	local lamps = { { 7, -36 }, { -7, -36 }, { 7, 30 }, { -7, 30 }, { -36, 7 }, { -36, -7 }, { 36, 7 }, { 36, -7 } }
	for _, l in ipairs(lamps) do
		P({ Name = "LampPost", CFrame = CFrame.new(l[1], 3.5, l[2]), Size = V(0.5, 7, 0.5), Color = C("Charcoal"), Parent = decoFolder })
		MapKit.ball({ Name = "LampGlow", Color = C("Cream"), Material = NEON, CanCollide = false, CanQuery = false, CastShadow = false, Parent = decoFolder }, V(l[1], 7.5, l[2]), 1.4)
	end
	-- Bänke um den Platz
	for i = 0, 3 do
		local angle = math.rad(45 + i * 90)
		local pos = V(math.cos(angle) * 24, 0, math.sin(angle) * 24)
		local cf = CFrame.lookAt(pos, V(0, 0, 0))
		P({ Name = "BenchSeat", CFrame = cf * CFrame.new(0, 1, 0), Size = V(5, 0.4, 1.6), Color = C("Wood"), Material = Enum.Material.WoodPlanks, Parent = decoFolder })
		P({ Name = "BenchBack", CFrame = cf * CFrame.new(0, 1.9, 0.7), Size = V(5, 1.4, 0.3), Color = C("Wood"), Material = Enum.Material.WoodPlanks, Parent = decoFolder })
		P({ Name = "BenchFoot", CFrame = cf * CFrame.new(0, 0.4, 0), Size = V(4, 0.8, 1), Color = C("Charcoal"), Parent = decoFolder })
	end
	-- Blumenbeete am Brunnen
	local flowerColors = { C("Pink"), C("Yellow"), C("Lilac"), C("Red") }
	for i = 0, 5 do
		local angle = math.rad(30 + i * 60)
		local pos = V(math.cos(angle) * 9, 0, math.sin(angle) * 9)
		P({ Name = "Planter", CFrame = CFrame.lookAt(pos + V(0, 0.5, 0), V(0, 0.5, 0)), Size = V(3, 1, 1.6), Color = C("Terracotta"), Parent = decoFolder })
		for k = -1, 1 do
			local flowerPos = CFrame.lookAt(pos, V(0, 0, 0)) * CFrame.new(k, 1.4, 0)
			MapKit.ball({ Name = "Flower", Color = flowerColors[((i + k) % #flowerColors) + 1], CanCollide = false, CanQuery = false, CastShadow = false, Parent = decoFolder }, flowerPos.Position, 0.8)
		end
	end
	-- Ballons über dem Platz (schweben, nur Optik)
	local balloonColors = { C("Red"), C("Yellow"), C("Blue"), C("Pink"), C("Mint"), C("Lilac") }
	for i = 0, 5 do
		local angle = math.rad(i * 60 + 15)
		local pos = V(math.cos(angle) * 12, 22 + (i % 3) * 2.5, math.sin(angle) * 12)
		MapKit.ball({ Name = "Balloon", Color = balloonColors[i + 1], CanCollide = false, CanQuery = false, CastShadow = false, Parent = decoFolder }, pos, 3)
		deco({ Name = "BalloonString", CFrame = CFrame.new(pos - V(0, 3.5, 0)), Size = V(0.1, 4, 0.1), Color = WHITE, Parent = decoFolder })
	end
end

-- ---------------------------------------------------------------------
-- Bauen
-- ---------------------------------------------------------------------
local function build()
	if built then
		return
	end
	built = true
	local old = workspace:FindFirstChild(Layout.FolderName)
	if old then
		old:Destroy()
	end
	local lobby = Instance.new("Folder")
	lobby.Name = Layout.FolderName
	buildGround(lobby)
	buildEdges(lobby)
	buildPlaza(lobby)
	buildDuelHall(lobby)
	buildCrownArea(lobby)
	buildRange(lobby)
	buildShopStreet(lobby)
	buildBoards(lobby)
	buildVip(lobby)
	buildDeco(lobby)

	-- Teilebudget (inkl. Crown Ring, den ArenaService fest eingebaut hat)
	local parts = MapKit.Count(lobby)
	local crownParts = 0
	if Services and Services.ArenaService then
		local ok, crown = pcall(Services.ArenaService.Crown)
		if ok and crown and crown.Model then
			crownParts = MapKit.Count(crown.Model)
		end
	end
	local total = parts + crownParts
	lobby:SetAttribute("PartCount", total)
	if total > Layout.PartBudget then
		warn(("[LobbyBuilder] Lobby hat %d Teile – Budget %d überschritten"):format(total, Layout.PartBudget))
	end
	lobby.Parent = workspace -- EINMAL parenten (ein Replikations-Schub)
	root = lobby
end

-- ---------------------------------------------------------------------
-- Öffentliche API (C5.3)
-- ---------------------------------------------------------------------
function LobbyBuilder.Pads(): { PadInfo }
	return pads
end

function LobbyBuilder.RangeZone(): (CFrame, Vector3)
	local r = Layout.Range
	local size = r.ZoneMax - r.ZoneMin
	return CFrame.new((r.ZoneMin + r.ZoneMax) / 2), size
end

function LobbyBuilder.RangeDummySpots(): { { Pos: Vector3, Moving: boolean } }
	return dummySpots
end

function LobbyBuilder.CrownLine(): { Vector3 }
	return table.clone(Layout.CrownLine)
end

function LobbyBuilder.CrownBoard(): BasePart
	return crownBoard :: BasePart
end

function LobbyBuilder.Boards(): { [string]: BasePart }
	return boards
end

function LobbyBuilder.VipZone(): (CFrame, Vector3)
	local plat = Layout.Vip.Platform
	local top = plat.Pos.Y + plat.Size.Y / 2
	return CFrame.new(plat.Pos.X, top + 5, plat.Pos.Z), V(plat.Size.X, 10, plat.Size.Z)
end

function LobbyBuilder.CrateMachine(): Model
	return crateMachine :: Model
end

function LobbyBuilder.BotBooth(): { { Pos: Vector3, Difficulty: string } }
	return booth
end

-- Ordner der Lobby (für WorldTests/Debug)
function LobbyBuilder.Root(): Folder?
	return root
end

function LobbyBuilder.Init(services: any)
	Services = services
	build()
end

function LobbyBuilder.Start() end

return LobbyBuilder
