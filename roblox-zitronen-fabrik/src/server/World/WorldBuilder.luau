--[[
	Baut die ganze Welt aus Roblox-Blöcken:
	Insel, Lobby (Zorp + UFO, Evolution-Portal, Obby-Zitronenbaum, Bestenliste,
	Kanaldeckel), Kanalisation mit Hebel-Rätsel und die 6 Fabrik-Grundstücke.

	Ist schon eine Welt vorhanden (z. B. in Studio "gebacken"), wird sie benutzt.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Build = require(script.Parent.Build)
local PlotBuilder = require(script.Parent.PlotBuilder)

local C = Build.C
local L = Config.Layout

local WorldBuilder = {}

local function plotCFrame(index: number): CFrame
	local angle = math.rad((index - 1) * 360 / Config.MaxPlots)
	local pos = Vector3.new(math.cos(angle) * L.PlotRadius, 1, math.sin(angle) * L.PlotRadius)
	return CFrame.lookAt(pos, Vector3.new(0, 1, 0))
end
WorldBuilder.PlotCFrame = plotCFrame

-- Punkt auf dem Platz bei Winkel (Grad) und Radius, Blick zur Mitte
local function plazaCFrame(angleDeg: number, radius: number, y: number?): CFrame
	local a = math.rad(angleDeg)
	local pos = Vector3.new(math.cos(a) * radius, y or 0.8, math.sin(a) * radius)
	return CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0))
end

--------------------------------------------------------------------------
-- Licht & Himmel
--------------------------------------------------------------------------
function WorldBuilder.SetupLighting(lighting: Lighting)
	lighting.ClockTime = 14
	lighting.GeographicLatitude = 20
	lighting.Brightness = 2.5
	lighting.GlobalShadows = true
	lighting.Ambient = Color3.fromRGB(70, 70, 80)
	lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 135)
	lighting.EnvironmentDiffuseScale = 0.6
	lighting.EnvironmentSpecularScale = 0.6

	if not lighting:FindFirstChildOfClass("Sky") then
		local sky = Instance.new("Sky")
		sky.Name = "Sky"
		sky.SunAngularSize = 14
		sky.Parent = lighting
	end
	if not lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.25
		atmosphere.Offset = 0.1
		atmosphere.Color = Color3.fromRGB(199, 220, 255)
		atmosphere.Decay = Color3.fromRGB(110, 140, 190)
		atmosphere.Glare = 0.2
		atmosphere.Haze = 1
		atmosphere.Parent = lighting
	end
	if not lighting:FindFirstChild("Bloom") then
		local bloom = Instance.new("BloomEffect")
		bloom.Name = "Bloom"
		bloom.Intensity = 0.6
		bloom.Size = 24
		bloom.Threshold = 1.6
		bloom.Parent = lighting
	end
	if not lighting:FindFirstChild("SunRays") then
		local rays = Instance.new("SunRaysEffect")
		rays.Name = "SunRays"
		rays.Intensity = 0.06
		rays.Spread = 0.6
		rays.Parent = lighting
	end
	if not lighting:FindFirstChild("ColorCorrection") then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "ColorCorrection"
		cc.Saturation = 0.12
		cc.Contrast = 0.05
		cc.Parent = lighting
	end
end

-- Wasser rund um die Insel (nur zur Laufzeit möglich)
function WorldBuilder.SetupTerrain(terrain: Terrain)
	if terrain:GetAttribute("ZitronenWater") then
		return
	end
	terrain:SetAttribute("ZitronenWater", true)
	terrain.WaterColor = Color3.fromRGB(40, 150, 200)
	terrain.WaterTransparency = 0.6
	terrain.WaterWaveSize = 0.12
	terrain.WaterWaveSpeed = 8
	terrain.WaterReflectance = 0.6
	local size = (L.IslandRadius + 600) * 2
	terrain:FillBlock(CFrame.new(0, -22, 0), Vector3.new(size, 8, size), Enum.Material.Sand)
	terrain:FillBlock(CFrame.new(0, -10, 0), Vector3.new(size, 16, size), Enum.Material.Water)
end

--------------------------------------------------------------------------
-- Bäume & Kleinkram
--------------------------------------------------------------------------
local function blockyTree(parent, cf: CFrame, rng: Random, lemons: boolean)
	local model = Build.Model(parent, lemons and "LemonTree" or "Tree")
	local height = rng:NextNumber(7, 11)
	Build.Block(model, "Trunk", Vector3.new(2, height, 2), cf * CFrame.new(0, height / 2, 0), C("Reddish brown"), Enum.Material.Wood)
	local leafColor = lemons and C("Bright green") or (rng:NextNumber() < 0.5 and C("Earth green") or C("Dark green"))
	local w = rng:NextNumber(8, 11)
	Build.Block(model, "Leaves", Vector3.new(w, 6, w), cf * CFrame.new(0, height + 2, 0), leafColor, Enum.Material.Plastic)
	Build.Block(model, "LeavesTop", Vector3.new(w - 3.5, 3, w - 3.5), cf * CFrame.new(0, height + 6.5, 0), leafColor, Enum.Material.Plastic)
	if lemons then
		for i = 1, 6 do
			local a = math.rad(i * 60 + rng:NextNumber(0, 30))
			local r = w / 2 + 0.2
			Build.Egg(model, "Lemon", Vector3.new(1.4, 1, 1), cf * CFrame.new(math.cos(a) * r, height + rng:NextNumber(0.5, 3.5), math.sin(a) * r), C("Bright yellow"), Enum.Material.Plastic)
		end
	end
	return model
end
WorldBuilder.BlockyTree = blockyTree

local function rock(parent, cf: CFrame, rng: Random)
	local s = rng:NextNumber(2, 5)
	Build.Block(parent, "Rock", Vector3.new(s * 1.4, s, s * 1.2), cf * CFrame.new(0, s / 2 - 0.4, 0) * CFrame.Angles(0, rng:NextNumber(0, 6.28), math.rad(rng:NextNumber(-8, 8))), C("Medium stone grey"), Enum.Material.Slate)
end

local function lampPost(parent, cf: CFrame)
	local model = Build.Model(parent, "Lamp")
	Build.Block(model, "Post", Vector3.new(0.8, 10, 0.8), cf * CFrame.new(0, 5, 0), C("Black"), Enum.Material.Metal)
	local head = Build.Block(model, "Head", Vector3.new(2, 1.6, 2), cf * CFrame.new(0, 10.6, 0), C("Pastel yellow"), Enum.Material.Neon)
	Build.Block(model, "Cap", Vector3.new(2.6, 0.5, 2.6), cf * CFrame.new(0, 11.6, 0), C("Black"), Enum.Material.Metal)
	Build.Light(head, Color3.fromRGB(255, 230, 170), 22, 1.2)
	return model
end
WorldBuilder.LampPost = lampPost

local function bench(parent, cf: CFrame)
	local model = Build.Model(parent, "Bench")
	Build.Block(model, "Seat", Vector3.new(8, 0.6, 2.4), cf * CFrame.new(0, 2, 0), C("Brown"), Enum.Material.WoodPlanks)
	Build.Block(model, "Back", Vector3.new(8, 2, 0.5), cf * CFrame.new(0, 3.4, 1.0), C("Brown"), Enum.Material.WoodPlanks)
	Build.Block(model, "LegL", Vector3.new(0.6, 2, 2), cf * CFrame.new(-3.4, 1, 0), C("Black"), Enum.Material.Metal)
	Build.Block(model, "LegR", Vector3.new(0.6, 2, 2), cf * CFrame.new(3.4, 1, 0), C("Black"), Enum.Material.Metal)
end

local function signBoard(parent, name: string, cf: CFrame, size: Vector2, text: string, color: Color3)
	local model = Build.Model(parent, name)
	local h = 4 + size.Y
	Build.Block(model, "PostL", Vector3.new(0.8, h, 0.8), cf * CFrame.new(-size.X / 2 + 0.8, h / 2, 0.2), C("Brown"), Enum.Material.Wood)
	Build.Block(model, "PostR", Vector3.new(0.8, h, 0.8), cf * CFrame.new(size.X / 2 - 0.8, h / 2, 0.2), C("Brown"), Enum.Material.Wood)
	local board = Build.Block(model, "Board", Vector3.new(size.X, size.Y, 0.6), cf * CFrame.new(0, 4 + size.Y / 2 - 0.5, -0.3), color, Enum.Material.Plastic)
	Build.Sign(board, Enum.NormalId.Front, text, { RichText = true })
	return model, board
end
WorldBuilder.SignBoard = signBoard

--------------------------------------------------------------------------
-- Insel
--------------------------------------------------------------------------
local function buildIsland(world: Instance)
	local island = Build.Folder(world, "Island")
	local r = L.IslandRadius

	-- Klassische Baseplate (grün mit Noppen) und Sandrand
	Build.Block(island, "Ground", Vector3.new(r * 2, 12, r * 2), CFrame.new(0, -6, 0), C("Bright green"), Enum.Material.Plastic)
	Build.Block(island, "Beach", Vector3.new(r * 2 + 80, 12, r * 2 + 80), CFrame.new(0, -6.8, 0), C("Brick yellow"), Enum.Material.Plastic)

	-- Wege vom Platz zu jeder Fabrik
	local pathLength = (L.PlotRadius - L.PlotSize / 2) - (L.PlazaRadius - 6) + 2
	local pathMid = (L.PlazaRadius - 6) + pathLength / 2
	for i = 1, Config.MaxPlots do
		local angle = (i - 1) * 360 / Config.MaxPlots
		local cf = plazaCFrame(angle, pathMid, 0.3)
		Build.Block(island, "Path" .. i, Vector3.new(26, 1, pathLength), cf, C("Dark stone grey"), Enum.Material.Plastic)
		Build.Block(island, "PathEdgeL" .. i, Vector3.new(1.5, 1.2, pathLength), cf * CFrame.new(-13.75, 0.1, 0), C("White"), Enum.Material.Plastic)
		Build.Block(island, "PathEdgeR" .. i, Vector3.new(1.5, 1.2, pathLength), cf * CFrame.new(13.75, 0.1, 0), C("White"), Enum.Material.Plastic)
		for k = -1, 1, 2 do
			lampPost(island, plazaCFrame(angle, pathMid - 20, 0.8) * CFrame.new(k * 16, 0, 0))
			lampPost(island, plazaCFrame(angle, pathMid + 20, 0.8) * CFrame.new(k * 16, 0, 0))
		end
	end

	-- Bäume und Steine außerhalb von Fabriken, Platz und Wegen
	local rng = Random.new(1337)
	local deco = Build.Folder(island, "Nature")
	local placed = 0
	local tries = 0
	local half = L.PlotSize / 2 + 8
	while placed < 70 and tries < 4000 do
		tries += 1
		local a = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(L.PlazaRadius * 1.45, r - 12)
		local pos = Vector3.new(math.cos(a) * dist, 0, math.sin(a) * dist)
		local ok = true
		for i = 1, Config.MaxPlots do
			local local3 = plotCFrame(i):PointToObjectSpace(Vector3.new(pos.X, 1, pos.Z))
			if math.abs(local3.X) < half and math.abs(local3.Z) < half then
				ok = false
				break
			end
			-- Weg-Korridor
			local pathAngle = math.rad((i - 1) * 360 / Config.MaxPlots)
			local dir = Vector3.new(math.cos(pathAngle), 0, math.sin(pathAngle))
			local along = pos:Dot(dir)
			local side = (pos - dir * along).Magnitude
			if along > 0 and along < L.PlotRadius and side < 24 then
				ok = false
				break
			end
		end
		if ok then
			placed += 1
			local cf = CFrame.new(pos)
			if placed % 6 == 0 then
				rock(deco, cf, rng)
			else
				blockyTree(deco, cf, rng, placed % 3 == 0)
			end
		end
	end
end

--------------------------------------------------------------------------
-- Lobby / Platz
--------------------------------------------------------------------------
local function buildObbyTree(lobby: Instance)
	local model = Build.Model(lobby, "ObbyTree")
	local base = CFrame.new(0, 0.8, 0)
	Build.Cylinder(model, "Trunk", 62, 10, base * CFrame.new(0, 31, 0), C("Reddish brown"), Enum.Material.Wood)
	Build.Cylinder(model, "Roots", 2, 16, base * CFrame.new(0, 1, 0), C("Reddish brown"), Enum.Material.Wood)
	Build.Block(model, "Canopy", Vector3.new(20, 10, 20), base * CFrame.new(0, 65, 0), C("Bright green"), Enum.Material.Plastic)
	Build.Block(model, "CanopyTop", Vector3.new(14, 4, 14), base * CFrame.new(0, 72, 0), C("Bright green"), Enum.Material.Plastic)
	for i = 1, 8 do
		local a = math.rad(i * 45 + 20)
		Build.Egg(model, "Lemon" .. i, Vector3.new(2.6, 2, 2), base * CFrame.new(math.cos(a) * 10.8, 62 + (i % 3), math.sin(a) * 10.8), C("Bright yellow"), Enum.Material.Plastic)
	end

	-- Spirale aus Sprung-Plattformen
	local platforms = Build.Folder(model, "Platforms")
	local count = 19
	local colors = { C("Bright red"), C("Bright orange"), C("Bright yellow"), C("Lime green"), C("Bright blue"), C("Bright violet") }
	for i = 1, count do
		local a = math.rad(200 + i * 30)
		local y = 4 + (i - 1) * 3.5
		local size = (i % 5 == 0) and Vector3.new(4, 1, 4) or Vector3.new(5, 1, 5)
		Build.Block(platforms, "Step" .. i, size, base * CFrame.new(math.cos(a) * 18, y, math.sin(a) * 18) * CFrame.Angles(0, -a, 0), colors[(i - 1) % #colors + 1], (i % 4 == 0) and Enum.Material.Neon or Enum.Material.Plastic)
	end

	local golden = Build.Egg(model, "GoldenLemon", Vector3.new(4, 3, 3), base * CFrame.new(0, 76, 0), Color3.fromRGB(255, 215, 0), Enum.Material.Neon)
	Build.Light(golden, Color3.fromRGB(255, 220, 80), 16, 2)
	Build.Sparkles(golden, Color3.fromRGB(255, 230, 90), 10)
	Build.Prompt(golden, "Pflücken", "Goldene Zitrone", { Name = "GoldenPrompt", Distance = 10 })

	signBoard(lobby, "ObbySign", plazaCFrame(345, 24) * CFrame.Angles(0, math.pi, 0), Vector2.new(14, 5), "🍋 ZITRONEN-OBBY 🍋\nKlettere hoch und pflücke die goldene Zitrone! (1× am Tag)", C("Bright orange"))
end

local function buildZorp(lobby: Instance)
	local model = Build.Model(lobby, "Zorp")
	local cf = plazaCFrame(30, 82)
	-- Landeplatz
	Build.Cylinder(model, "Pad", 0.4, 24, cf * CFrame.new(0, 0.2, 0), C("Dark stone grey"), Enum.Material.DiamondPlate)
	Build.Cylinder(model, "PadRing", 0.5, 26, cf * CFrame.new(0, 0.1, 0), C("Lime green"), Enum.Material.Neon)
	-- UFO
	local ufo = Build.Model(model, "UFO")
	local ufoCF = cf * CFrame.new(0, 19, 0)
	Build.Cylinder(ufo, "Disc", 3, 28, ufoCF, C("Medium stone grey"), Enum.Material.Metal)
	Build.Cylinder(ufo, "DiscBottom", 2, 16, ufoCF * CFrame.new(0, -2, 0), C("Dark stone grey"), Enum.Material.Metal)
	Build.Ball(ufo, "Dome", 13, ufoCF * CFrame.new(0, 2.5, 0), C("Pastel light blue"), Enum.Material.Glass, { Transparency = 0.35 })
	for i = 1, 10 do
		local a = math.rad(i * 36)
		local bulb = Build.Ball(ufo, "Light" .. i, 1.6, ufoCF * CFrame.new(math.cos(a) * 13, 0, math.sin(a) * 13), i % 2 == 0 and C("Lime green") or C("New Yeller"), Enum.Material.Neon)
		Build.NoCollide(bulb)
	end
	local beam = Build.Cylinder(model, "Beam", 17, 9, cf * CFrame.new(0, 9, 0), C("Lime green"), Enum.Material.Neon, { Transparency = 0.75 })
	Build.NoCollide(beam)
	Build.Light(beam, Color3.fromRGB(120, 255, 120), 18, 1)

	-- Hier steht zur Laufzeit Zorp (NPC)
	local spot = Build.Block(model, "ZorpSpot", Vector3.new(2, 1, 1), cf * CFrame.new(0, 0.5, -6), C("Lime green"), Enum.Material.Plastic, { Transparency = 1 })
	Build.NoCollide(spot)
	local promptPart = Build.Block(model, "PromptPart", Vector3.new(4, 6, 4), cf * CFrame.new(0, 3, -6), C("Lime green"), Enum.Material.Plastic, { Transparency = 1, CanCollide = false })
	Build.Prompt(promptPart, "Mit Zorp reden", "🛸 Rebirth & Alien-Kräfte", { Name = "ZorpPrompt", Distance = 14 })

	signBoard(model, "ZorpSign", cf * CFrame.new(-16, 0, 2), Vector2.new(12, 5), "🛸 ZORP\nRebirth & Alien-Investoren", C("Bright violet"))
end

local function buildPortal(lobby: Instance)
	local model = Build.Model(lobby, "Portal")
	local cf = plazaCFrame(150, 85)
	Build.Block(model, "Base", Vector3.new(26, 1.4, 12), cf * CFrame.new(0, 0.7, 0), C("Black"), Enum.Material.Slate)
	local ringCF = cf * CFrame.new(0, 12.5, 0)
	for i = 0, 19 do
		local a = math.rad(i * 18)
		Build.Block(model, "Ring" .. i, Vector3.new(3.6, 2.6, 2.4), ringCF * CFrame.new(math.cos(a) * 10, math.sin(a) * 10, 0) * CFrame.Angles(0, 0, a + math.rad(90)), i % 2 == 0 and C("Royal purple") or C("Bright violet"), Enum.Material.Neon)
	end
	local swirl = Build.CylinderX(model, "Swirl", 0.6, 18, ringCF * CFrame.Angles(0, math.rad(90), 0), C("Royal purple"), Enum.Material.ForceField)
	swirl.CanCollide = false
	Build.Sparkles(swirl, Color3.fromRGB(200, 120, 255), 20)
	Build.Light(swirl, Color3.fromRGB(170, 90, 255), 30, 2)
	local promptPart = Build.Block(model, "PromptPart", Vector3.new(6, 6, 6), cf * CFrame.new(0, 3, -4), C("Royal purple"), Enum.Material.Plastic, { Transparency = 1, CanCollide = false })
	Build.Prompt(promptPart, "Evolution ansehen", "🌀 Frucht-Evolution", { Name = "PortalPrompt", Distance = 14 })
	local _, board = signBoard(model, "PortalSign", cf * CFrame.new(-19, 0, 0), Vector2.new(12, 4.5), "🌀 FRUCHT-EVOLUTION 🌀", C("Royal purple"))
	board.Name = "StatusBoard"
end

local function buildLeaderboard(lobby: Instance)
	local model = Build.Model(lobby, "Leaderboard")
	local cf = plazaCFrame(90, 92)
	Build.Block(model, "PostL", Vector3.new(1.5, 26, 1.5), cf * CFrame.new(-15, 13, 0.6), C("Black"), Enum.Material.Metal)
	Build.Block(model, "PostR", Vector3.new(1.5, 26, 1.5), cf * CFrame.new(15, 13, 0.6), C("Black"), Enum.Material.Metal)
	local board = Build.Block(model, "Board", Vector3.new(28, 20, 1), cf * CFrame.new(0, 15, 0), C("Really black"), Enum.Material.Plastic)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BoardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 25
	gui.LightInfluence = 0
	gui.Parent = board

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0.14, 0)
	title.BackgroundColor3 = C("Bright yellow")
	title.BorderSizePixel = 0
	title.FontFace = Font.fromEnum(Build.FONT)
	title.Text = "🏆 REICHSTE FABRIKEN 🏆"
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0
	title.Parent = gui

	local list = Instance.new("Frame")
	list.Name = "List"
	list.Size = UDim2.new(0.96, 0, 0.82, 0)
	list.Position = UDim2.new(0.02, 0, 0.16, 0)
	list.BackgroundTransparency = 1
	list.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.01, 0)
	layout.Parent = list
	for i = 1, 10 do
		local row = Instance.new("TextLabel")
		row.Name = "Row" .. i
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0.09, 0)
		row.BackgroundColor3 = i % 2 == 0 and Color3.fromRGB(40, 40, 50) or Color3.fromRGB(55, 55, 70)
		row.BorderSizePixel = 0
		row.FontFace = Font.fromEnum(Build.FONT)
		row.Text = i .. ".  ---"
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = i == 1 and Color3.fromRGB(255, 215, 0) or (i == 2 and Color3.fromRGB(220, 220, 230) or (i == 3 and Color3.fromRGB(230, 150, 80) or Color3.new(1, 1, 1)))
		row.TextStrokeTransparency = 0
		row.Parent = list
	end
end

local function buildManhole(lobby: Instance)
	local model = Build.Model(lobby, "Manhole")
	local cf = plazaCFrame(210, 80)
	Build.Cylinder(model, "Cover", 0.4, 7, cf * CFrame.new(0, 0.2, 0), C("Dark stone grey"), Enum.Material.DiamondPlate)
	Build.Cylinder(model, "Rim", 0.3, 8, cf * CFrame.new(0, 0.15, 0), C("Black"), Enum.Material.Metal)
	-- Absperrung
	for i = 0, 3 do
		local a = math.rad(i * 90 + 45)
		Build.Block(model, "Cone" .. i, Vector3.new(1.2, 2.4, 1.2), cf * CFrame.new(math.cos(a) * 6, 1.2, math.sin(a) * 6), C("Bright orange"), Enum.Material.Plastic)
	end
	local promptPart = Build.Block(model, "PromptPart", Vector3.new(4, 3, 4), cf * CFrame.new(0, 1.5, 0), C("Black"), Enum.Material.Plastic, { Transparency = 1, CanCollide = false })
	Build.Prompt(promptPart, "Hinabsteigen", "🕳️ Kanalisation", { Name = "ManholePrompt", Distance = 10 })
	signBoard(model, "ManholeSign", cf * CFrame.new(0, 0, 9), Vector2.new(12, 4), "🚧 KANALISATION 🚧\nBetreten auf eigene Gefahr…", C("Bright orange"))
end

local function buildInfoBoard(lobby: Instance)
	local cf = plazaCFrame(270, 90)
	local _, board = signBoard(lobby, "InfoBoard", cf, Vector2.new(22, 12),
		"<b>🍋 SO SPIELST DU 🍋</b>\n1. Lauf in deine Fabrik\n2. Tritt auf grüne Knöpfe = kaufen\n3. Drück den roten Knopf = Zitronen pressen\n4. Kauf Manager = läuft von allein\n5. Rebirth bei Zorp dem Alien 🛸",
		C("Bright blue"))
	board.Name = "Board"
end

local function buildLobby(world: Instance)
	local lobby = Build.Folder(world, "Lobby")

	-- Platz aus Blöcken (klassisch eckig)
	Build.Block(lobby, "Plaza", Vector3.new(L.PlazaRadius * 2, 1, L.PlazaRadius * 2), CFrame.new(0, 0.3, 0) * CFrame.Angles(0, math.rad(45), 0), C("Medium stone grey"), Enum.Material.Plastic)
	Build.Block(lobby, "PlazaRing", Vector3.new(76, 1, 76), CFrame.new(0, 0.32, 0), C("White"), Enum.Material.Plastic)
	Build.Block(lobby, "PlazaInner", Vector3.new(70, 1, 70), CFrame.new(0, 0.34, 0), C("Bright yellow"), Enum.Material.Plastic)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = plazaCFrame(330, 50, 0.6) * CFrame.Angles(0, math.pi, 0)
	spawn.Color = C("Bright yellow")
	spawn.Material = Enum.Material.Plastic
	spawn.TopSurface = Enum.SurfaceType.Studs
	spawn.BottomSurface = Enum.SurfaceType.Inlet
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = lobby

	buildObbyTree(lobby)
	buildZorp(lobby)
	buildPortal(lobby)
	buildLeaderboard(lobby)
	buildManhole(lobby)
	buildInfoBoard(lobby)

	local deco = Build.Folder(lobby, "Deco")
	for i = 0, 11 do
		local angle = i * 30 + 15
		if i % 2 == 1 then
			lampPost(deco, plazaCFrame(angle, L.PlazaRadius - 8))
		else
			bench(deco, plazaCFrame(angle, L.PlazaRadius - 10))
		end
	end
	-- Blumenkübel um die Mitte
	for i = 0, 5 do
		local cf = plazaCFrame(i * 60 + 30, 30)
		Build.Block(deco, "Planter", Vector3.new(6, 2, 6), cf * CFrame.new(0, 1, 0), C("Brown"), Enum.Material.WoodPlanks)
		Build.Block(deco, "Bush", Vector3.new(5, 3, 5), cf * CFrame.new(0, 3, 0), C("Earth green"), Enum.Material.Plastic)
		Build.Ball(deco, "Flower", 1.4, cf * CFrame.new(1, 4.6, 0.5), C("Hot pink"), Enum.Material.Plastic)
		Build.Ball(deco, "Flower", 1.4, cf * CFrame.new(-1.2, 4.6, -0.8), C("New Yeller"), Enum.Material.Plastic)
	end

	-- Titel-Schild über dem Spawn
	local titleCF = plazaCFrame(330, 82)
	local title = Build.Block(lobby, "TitleSign", Vector3.new(40, 8, 1), titleCF * CFrame.new(0, 22, 0), C("Bright yellow"), Enum.Material.Plastic)
	Build.Sign(title, Enum.NormalId.Front, "🍋 ZITRONEN-FABRIK TYCOON 🍋", {})
	Build.Sign(title, Enum.NormalId.Back, "🍋 ZITRONEN-FABRIK TYCOON 🍋", { Name = "SignGuiBack" })
	Build.Block(lobby, "TitlePostL", Vector3.new(1.5, 22, 1.5), titleCF * CFrame.new(-19, 11, 0), C("Black"), Enum.Material.Metal)
	Build.Block(lobby, "TitlePostR", Vector3.new(1.5, 22, 1.5), titleCF * CFrame.new(19, 11, 0), C("Black"), Enum.Material.Metal)

	-- Pickup-Ordner für Events
	Build.Folder(world, "Pickups")
end

--------------------------------------------------------------------------
-- Kanalisation (Labyrinth unter dem Platz)
--------------------------------------------------------------------------
-- # Wand · . Gang · S Start · R/B/G/Y Hebel · D Tresortür (führt nach Osten in den Tresor)
WorldBuilder.SewerMap = {
	"###########",
	"#S....#..R#",
	"#.###.#.###",
	"#...#...#.#",
	"###.#####.#",
	"#B#.....#.#",
	"#.#.###.#.#",
	"#.....#...D",
	"#.#####.###",
	"#....G#..Y#",
	"###########",
}
WorldBuilder.SewerCell = 12

local LEVER_COLORS = {
	R = { Name = "Rot", Color = "Really red" },
	B = { Name = "Blau", Color = "Really blue" },
	G = { Name = "Grün", Color = "Lime green" },
	Y = { Name = "Gelb", Color = "New Yeller" },
}

local function buildSewer(world: Instance)
	local sewer = Build.Folder(world, "Sewer")
	local origin = CFrame.new(L.SewerOrigin)
	local cell = WorldBuilder.SewerCell
	local map = WorldBuilder.SewerMap
	local rows = #map
	local cols = #map[1]
	local wallH = 12

	local function cellCF(row: number, col: number, y: number): CFrame
		return origin * CFrame.new((col - (cols + 1) / 2) * cell, y, (row - (rows + 1) / 2) * cell)
	end

	-- Boden & Decke (Tresor im Osten mit eingerechnet)
	local width = (cols + 3) * cell
	local depth = rows * cell
	Build.Block(sewer, "Floor", Vector3.new(width, 2, depth), origin * CFrame.new(1.5 * cell, -1, 0), C("Dark stone grey"), Enum.Material.Slate)
	Build.Block(sewer, "Ceiling", Vector3.new(width, 2, depth), origin * CFrame.new(1.5 * cell, wallH + 1, 0), C("Black"), Enum.Material.Concrete)
	-- Grüner Schleim-Kanal in der Mitte des Bodens
	local walls = Build.Folder(sewer, "Walls")
	local levers = Build.Folder(sewer, "Levers")

	for row = 1, rows do
		local line = map[row]
		for col = 1, cols do
			local ch = string.sub(line, col, col)
			if ch == "#" then
				Build.Block(walls, "Wall", Vector3.new(cell, wallH, cell), cellCF(row, col, wallH / 2), (row + col) % 2 == 0 and C("Dark stone grey") or C("Medium stone grey"), Enum.Material.Brick)
			elseif ch == "S" then
				local ladder = Build.Model(sewer, "Start")
				Build.Block(ladder, "LadderL", Vector3.new(0.5, wallH, 0.5), cellCF(row, col, wallH / 2) * CFrame.new(-1.5, 0, -cell / 2 + 0.6), C("Medium stone grey"), Enum.Material.Metal)
				Build.Block(ladder, "LadderR", Vector3.new(0.5, wallH, 0.5), cellCF(row, col, wallH / 2) * CFrame.new(1.5, 0, -cell / 2 + 0.6), C("Medium stone grey"), Enum.Material.Metal)
				for k = 1, 5 do
					Build.Block(ladder, "Rung", Vector3.new(3, 0.3, 0.3), cellCF(row, col, k * 2) * CFrame.new(0, 0, -cell / 2 + 0.6), C("Medium stone grey"), Enum.Material.Metal)
				end
				local arrival = Build.Block(ladder, "Arrival", Vector3.new(2, 1, 2), cellCF(row, col, 0.5), C("Lime green"), Enum.Material.Plastic, { Transparency = 1, CanCollide = false })
				Build.NoCollide(arrival)
				local exitPart = Build.Block(ladder, "ExitPart", Vector3.new(3, 4, 1), cellCF(row, col, 2) * CFrame.new(0, 0, -cell / 2 + 1.2), C("Lime green"), Enum.Material.Plastic, { Transparency = 1, CanCollide = false })
				Build.Prompt(exitPart, "Nach oben klettern", "🪜 Zurück zum Platz", { Name = "ExitPrompt", Distance = 10 })
				local lamp = Build.Block(ladder, "Lamp", Vector3.new(1, 1, 1), cellCF(row, col, wallH - 1.5), C("Lime green"), Enum.Material.Neon)
				Build.Light(lamp, Color3.fromRGB(150, 255, 150), 24, 1.5)

				-- Wandbild mit dem Hinweis (Farben setzt der Server zur Laufzeit)
				-- an der Westwand der Startzelle, Vorderseite zeigt nach Osten
				local mural = Build.Block(sewer, "Mural", Vector3.new(cell - 2, 6, 0.4), cellCF(row, col, 6) * CFrame.new(-cell / 2 + 0.25, 0, 0) * CFrame.Angles(0, math.rad(-90), 0), C("Black"), Enum.Material.Plastic)
				local gui = Instance.new("SurfaceGui")
				gui.Name = "MuralGui"
				gui.Face = Enum.NormalId.Front
				gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
				gui.PixelsPerStud = 20
				gui.LightInfluence = 0
				gui.Parent = mural
				local caption = Instance.new("TextLabel")
				caption.Name = "Caption"
				caption.Size = UDim2.fromScale(1, 0.35)
				caption.BackgroundTransparency = 1
				caption.FontFace = Font.fromEnum(Build.FONT)
				caption.Text = "Die Ratten flüstern…"
				caption.TextScaled = true
				caption.TextColor3 = Color3.new(1, 1, 1)
				caption.TextStrokeTransparency = 0
				caption.Parent = gui
				for k = 1, 4 do
					local square = Instance.new("Frame")
					square.Name = "Color" .. k
					square.Size = UDim2.fromScale(0.18, 0.5)
					square.Position = UDim2.fromScale(0.04 + (k - 1) * 0.24, 0.42)
					square.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
					square.BorderSizePixel = 0
					square.Parent = gui
					local corner = Instance.new("UICorner")
					corner.CornerRadius = UDim.new(0.2, 0)
					corner.Parent = square
				end
			elseif LEVER_COLORS[ch] then
				local info = LEVER_COLORS[ch]
				local lever = Build.Model(levers, "Lever" .. info.Name)
				lever:SetAttribute("Color", info.Name)
				local base = cellCF(row, col, 0)
				Build.Block(lever, "Plate", Vector3.new(4, 4, 0.6), base * CFrame.new(0, 4, -cell / 2 + 0.4), C("Dark stone grey"), Enum.Material.Metal)
				local handle = Build.Block(lever, "Handle", Vector3.new(0.6, 3.5, 0.6), base * CFrame.new(0, 5.4, -cell / 2 + 1) * CFrame.Angles(math.rad(-30), 0, 0), C(info.Color), Enum.Material.Neon)
				handle.Name = "Handle"
				Build.Ball(lever, "Knob", 1.2, base * CFrame.new(0, 7, -cell / 2 + 1.9), C(info.Color), Enum.Material.Neon)
				Build.Light(handle, C(info.Color), 16, 1.2)
				local prompt = Build.Prompt(handle, "Ziehen", "Hebel (" .. info.Name .. ")", { Name = "LeverPrompt", Distance = 10 })
				prompt:SetAttribute("Color", info.Name)
			elseif ch == "D" then
				local door = Build.Block(sewer, "VaultDoor", Vector3.new(cell, wallH, cell), cellCF(row, col, wallH / 2), C("Dark stone grey"), Enum.Material.DiamondPlate)
				local sign = Build.Block(sewer, "VaultSign", Vector3.new(0.4, 3, 8), cellCF(row, col, 8) * CFrame.new(-cell / 2 - 0.25, 0, 0), C("Black"), Enum.Material.Plastic)
				Build.Sign(sign, Enum.NormalId.Left, "🔒 TRESOR", {})
				door:SetAttribute("IsVaultDoor", true)
			end
			if ch ~= "#" and (row + col) % 4 == 0 then
				local glow = Build.Block(sewer, "Glow", Vector3.new(1.2, 0.4, 1.2), cellCF(row, col, wallH - 0.2), C("Lime green"), Enum.Material.Neon)
				Build.Light(glow, Color3.fromRGB(120, 255, 120), 18, 0.8)
			end
		end
	end

	-- Tresor-Raum östlich der Tür
	local doorRow = 8
	local vault = Build.Model(sewer, "Vault")
	local vaultCenter = cellCF(doorRow, cols + 2, 0)
	Build.Block(vault, "WallN", Vector3.new(cell * 2, wallH, 1), vaultCenter * CFrame.new(0, wallH / 2, -cell * 1.5), C("Dark stone grey"), Enum.Material.Brick)
	Build.Block(vault, "WallS", Vector3.new(cell * 2, wallH, 1), vaultCenter * CFrame.new(0, wallH / 2, cell * 1.5), C("Dark stone grey"), Enum.Material.Brick)
	Build.Block(vault, "WallE", Vector3.new(1, wallH, cell * 3), vaultCenter * CFrame.new(cell + 0.5, wallH / 2, 0), C("Dark stone grey"), Enum.Material.Brick)
	Build.Block(vault, "Pedestal", Vector3.new(3, 3, 3), vaultCenter * CFrame.new(0, 1.5, 0), C("Gold"), Enum.Material.Marble)
	local key = Build.Block(vault, "UfoKey", Vector3.new(0.6, 2.4, 1.2), vaultCenter * CFrame.new(0, 4.6, 0), C("Lime green"), Enum.Material.Neon)
	Build.Ball(vault, "KeyRing", 1.4, vaultCenter * CFrame.new(0, 6.2, 0), C("Lime green"), Enum.Material.Neon)
	Build.Sparkles(key, Color3.fromRGB(150, 255, 150), 12)
	Build.Light(key, Color3.fromRGB(120, 255, 120), 20, 2)
	Build.Prompt(key, "Nehmen", "🛸 UFO-Schlüssel", { Name = "KeyPrompt", Distance = 10, HoldDuration = 0.5 })
end

--------------------------------------------------------------------------
-- Alles bauen
--------------------------------------------------------------------------
function WorldBuilder.Build(workspaceRoot: Instance, lighting: Lighting?)
	local existing = workspaceRoot:FindFirstChild("World")
	if existing then
		return existing
	end
	if lighting then
		WorldBuilder.SetupLighting(lighting)
	end

	local world = Build.Folder(nil, "World")
	buildIsland(world)
	buildLobby(world)
	buildSewer(world)

	local plots = Build.Folder(world, "Plots")
	for i = 1, Config.MaxPlots do
		PlotBuilder.BuildBase(plots, i, plotCFrame(i))
	end

	world.Parent = workspaceRoot
	return world
end

return WorldBuilder
