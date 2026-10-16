--[[
	Baut eine Fabrik (Grundstück) und alles, was darauf gekauft werden kann:
	Linien mit Maschine + Förderband + Verkauf, Maschinen-Bögen (Upgrader),
	Deko und die Kauf-Knöpfe.

	Lokale Koordinaten einer Fabrik: Ursprung = Mitte auf Bodenhöhe,
	-Z zeigt zum Platz (vorne), +Z nach hinten.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Build = require(script.Parent.Build)

local C = Build.C
local L = Config.Layout
local WHITE = Color3.new(1, 1, 1)

local PlotBuilder = {}

PlotBuilder.PlotColors = { "Bright red", "Bright blue", "Lime green", "Bright orange", "Bright violet", "Toothpaste" }

local function origin(plot: Model): CFrame
	return plot:GetAttribute("Origin") :: CFrame
end

function PlotBuilder.LaneCFrame(plotCF: CFrame, laneIndex: number): CFrame
	return plotCF * CFrame.new(Config.LaneX(laneIndex), 0, 0)
end

local function smallTree(parent, cf: CFrame, lemons: boolean)
	local model = Build.Model(parent, "Tree")
	Build.Block(model, "Trunk", Vector3.new(1.6, 8, 1.6), cf * CFrame.new(0, 4, 0), C("Reddish brown"), Enum.Material.Wood)
	Build.Block(model, "Leaves", Vector3.new(7, 5, 7), cf * CFrame.new(0, 9.5, 0), C("Bright green"), Enum.Material.Plastic)
	Build.Block(model, "LeavesTop", Vector3.new(4, 2.5, 4), cf * CFrame.new(0, 13.2, 0), C("Bright green"), Enum.Material.Plastic)
	if lemons then
		for i = 1, 5 do
			local a = math.rad(i * 72)
			Build.Egg(model, "Lemon", Vector3.new(1.3, 1, 1), cf * CFrame.new(math.cos(a) * 3.7, 8.5 + (i % 2) * 1.5, math.sin(a) * 3.7), C("Bright yellow"), Enum.Material.Plastic)
		end
	end
	return model
end

local function crate(parent, cf: CFrame, size: number)
	local part = Build.Block(parent, "Crate", Vector3.new(size, size, size), cf * CFrame.new(0, size / 2, 0), C("Brown"), Enum.Material.WoodPlanks)
	return part
end

--------------------------------------------------------------------------
-- Grundstück
--------------------------------------------------------------------------
function PlotBuilder.BuildBase(parent: Instance, index: number, plotCF: CFrame): Model
	local plot = Build.Model(nil, "Plot" .. index)
	plot:SetAttribute("Index", index)
	plot:SetAttribute("Origin", plotCF)
	plot:SetAttribute("OwnerId", 0)
	plot:SetAttribute("OwnerName", "")
	plot:SetAttribute("Fruit", 1)
	plot:SetAttribute("Decor", 0)

	local accent = C(PlotBuilder.PlotColors[(index - 1) % #PlotBuilder.PlotColors + 1])
	plot:SetAttribute("Accent", accent)
	local size = L.PlotSize
	local half = size / 2

	local base = Build.Block(plot, "Base", Vector3.new(size, 1, size), plotCF * CFrame.new(0, -0.5, 0), C("Medium stone grey"), Enum.Material.Plastic)
	plot.PrimaryPart = base

	-- Bordsteine
	local curb = Build.Folder(plot, "Curb")
	Build.Block(curb, "Back", Vector3.new(size, 0.6, 1.5), plotCF * CFrame.new(0, 0.3, half - 0.75), accent, Enum.Material.Plastic)
	Build.Block(curb, "Left", Vector3.new(1.5, 0.6, size), plotCF * CFrame.new(-half + 0.75, 0.3, 0), accent, Enum.Material.Plastic)
	Build.Block(curb, "Right", Vector3.new(1.5, 0.6, size), plotCF * CFrame.new(half - 0.75, 0.3, 0), accent, Enum.Material.Plastic)
	local frontLen = (size - 34) / 2
	Build.Block(curb, "FrontL", Vector3.new(frontLen, 0.6, 1.5), plotCF * CFrame.new(-17 - frontLen / 2, 0.3, -half + 0.75), accent, Enum.Material.Plastic)
	Build.Block(curb, "FrontR", Vector3.new(frontLen, 0.6, 1.5), plotCF * CFrame.new(17 + frontLen / 2, 0.3, -half + 0.75), accent, Enum.Material.Plastic)

	-- Eingang mit Besitzer-Schild
	local gate = Build.Model(plot, "Gate")
	Build.Block(gate, "PillarL", Vector3.new(3, 17, 3), plotCF * CFrame.new(-17, 8.5, -half + 1.5), accent, Enum.Material.Plastic)
	Build.Block(gate, "PillarR", Vector3.new(3, 17, 3), plotCF * CFrame.new(17, 8.5, -half + 1.5), accent, Enum.Material.Plastic)
	Build.Ball(gate, "BallL", 3.4, plotCF * CFrame.new(-17, 18.5, -half + 1.5), C("Bright yellow"), Enum.Material.Plastic)
	Build.Ball(gate, "BallR", 3.4, plotCF * CFrame.new(17, 18.5, -half + 1.5), C("Bright yellow"), Enum.Material.Plastic)
	local board = Build.Block(gate, "OwnerBoard", Vector3.new(31, 5, 1.4), plotCF * CFrame.new(0, 14.5, -half + 1.5), C("Bright yellow"), Enum.Material.Plastic)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Name = face == Enum.NormalId.Front and "OwnerGui" or "OwnerGuiBack"
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		gui.Parent = board
		local image = Instance.new("ImageLabel")
		image.Name = "Avatar"
		image.Size = UDim2.fromScale(0.15, 0.9)
		image.Position = UDim2.fromScale(0.02, 0.05)
		image.BackgroundColor3 = WHITE
		image.Image = ""
		image.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.2, 0)
		corner.Parent = image
		local label = Instance.new("TextLabel")
		label.Name = "OwnerText"
		label.Size = UDim2.fromScale(0.8, 0.9)
		label.Position = UDim2.fromScale(0.19, 0.05)
		label.BackgroundTransparency = 1
		label.FontFace = Font.fromEnum(Build.FONT)
		label.Text = "🍋 Freie Fabrik"
		label.TextScaled = true
		label.TextColor3 = WHITE
		label.TextStrokeTransparency = 0
		label.Parent = gui
	end

	local spawnPart = Build.Block(plot, "Spawn", Vector3.new(2, 1, 2), plotCF * CFrame.new(L.SpawnPos.X, 3, L.SpawnPos.Z) * CFrame.Angles(0, math.pi, 0), WHITE, Enum.Material.Plastic, { Transparency = 1 })
	Build.NoCollide(spawnPart)

	Build.Folder(plot, "Lanes")
	Build.Folder(plot, "Buttons")
	Build.Folder(plot, "Decor")
	Build.Folder(plot, "Managers")
	Build.Folder(plot, "Placeholders")
	local states = Build.Folder(plot, "LaneState")
	for i = 1, #Config.Lanes do
		local state = Instance.new("Configuration")
		state.Name = "Lane" .. i
		state:SetAttribute("Index", i)
		state:SetAttribute("Unlocked", false)
		state:SetAttribute("Level", 0)
		state:SetAttribute("Manager", false)
		state:SetAttribute("Upgraders", 0)
		state:SetAttribute("Running", false)
		state:SetAttribute("CycleStart", 0)
		state:SetAttribute("CycleTime", Config.Lanes[i].CycleTime)
		state:SetAttribute("Revenue", 0)
		state.Parent = states
		PlotBuilder.BuildPlaceholder(plot, i)
	end

	plot.Parent = parent
	return plot
end

function PlotBuilder.SetOwner(plot: Model, userId: number, displayName: string?)
	plot:SetAttribute("OwnerId", userId)
	plot:SetAttribute("OwnerName", displayName or "")
	local gate = plot:FindFirstChild("Gate")
	local board = gate and gate:FindFirstChild("OwnerBoard")
	if not board then
		return
	end
	for _, gui in ipairs(board:GetChildren()) do
		if gui:IsA("SurfaceGui") then
			local label = gui:FindFirstChild("OwnerText") :: TextLabel?
			local image = gui:FindFirstChild("Avatar") :: ImageLabel?
			if label then
				label.Text = userId ~= 0 and ("🍋 " .. (displayName or "?") .. "s Fabrik") or "🍋 Freie Fabrik"
			end
			if image then
				image.Image = userId ~= 0 and ("rbxthumb://type=AvatarHeadShot&id=" .. userId .. "&w=150&h=150") or ""
			end
		end
	end
end

--------------------------------------------------------------------------
-- Gesperrte Linie (Platzhalter)
--------------------------------------------------------------------------
function PlotBuilder.BuildPlaceholder(plot: Model, laneIndex: number)
	local folder = plot:FindFirstChild("Placeholders")
	if not folder or folder:FindFirstChild("Lane" .. laneIndex) then
		return
	end
	local laneCfg = Config.Lanes[laneIndex]
	local cf = PlotBuilder.LaneCFrame(origin(plot), laneIndex)
	local model = Build.Model(folder, "Lane" .. laneIndex)
	local color = laneCfg.Color
	local length = 150
	local zMid = 10
	Build.Block(model, "EdgeL", Vector3.new(0.6, 0.15, length), cf * CFrame.new(-13.7, 0.08, zMid), color, Enum.Material.Neon)
	Build.Block(model, "EdgeR", Vector3.new(0.6, 0.15, length), cf * CFrame.new(13.7, 0.08, zMid), color, Enum.Material.Neon)
	Build.Block(model, "EdgeF", Vector3.new(28, 0.15, 0.6), cf * CFrame.new(0, 0.08, zMid - length / 2), color, Enum.Material.Neon)
	Build.Block(model, "EdgeB", Vector3.new(28, 0.15, 0.6), cf * CFrame.new(0, 0.08, zMid + length / 2), color, Enum.Material.Neon)
	Build.Block(model, "Post", Vector3.new(0.8, 7, 0.8), cf * CFrame.new(0, 3.5, 20), C("Brown"), Enum.Material.Wood)
	local board = Build.Block(model, "Board", Vector3.new(14, 6, 0.5), cf * CFrame.new(0, 8, 20), color, Enum.Material.Plastic)
	Build.Sign(board, Enum.NormalId.Front, "🔒 " .. laneCfg.Emoji .. " " .. laneCfg.Name .. "\nKaufen am Knopf vorne", {})
	Build.Sign(board, Enum.NormalId.Back, "🔒 " .. laneCfg.Emoji .. " " .. laneCfg.Name, { Name = "SignGuiBack" })
	-- Baustellen-Hütchen
	for k = -1, 1, 2 do
		Build.Block(model, "Cone", Vector3.new(1.2, 2.2, 1.2), cf * CFrame.new(k * 6, 1.1, 20), C("Bright orange"), Enum.Material.Plastic)
	end
end

--------------------------------------------------------------------------
-- Maschinen (je Linie ein eigenes Gebäude)
--------------------------------------------------------------------------
local Machines = {}

function Machines.Stand(model, cf: CFrame, laneCfg)
	local z = L.MachineZ
	Build.Block(model, "Counter", Vector3.new(16, 4, 6), cf * CFrame.new(0, 2, z - 5), C("Brown"), Enum.Material.WoodPlanks)
	Build.Block(model, "CounterTop", Vector3.new(17, 0.6, 7), cf * CFrame.new(0, 4.3, z - 5), C("Bright yellow"), Enum.Material.Plastic)
	local front = Build.Block(model, "CounterSign", Vector3.new(10, 2.4, 0.3), cf * CFrame.new(0, 2.4, z - 8.1), C("Bright yellow"), Enum.Material.Plastic)
	Build.Sign(front, Enum.NormalId.Front, "🍋 LIMO 🍋", {})
	for _, x in ipairs({ -7.6, 7.6 }) do
		Build.Block(model, "PostF", Vector3.new(0.8, 9.5, 0.8), cf * CFrame.new(x, 4.75, z - 7.5), WHITE, Enum.Material.Wood)
		Build.Block(model, "PostB", Vector3.new(0.8, 9.5, 0.8), cf * CFrame.new(x, 4.75, z + 1), WHITE, Enum.Material.Wood)
	end
	for k = 0, 7 do
		local x = -7 + k * 2
		Build.Block(model, "Stripe" .. k, Vector3.new(2, 0.5, 10.5), cf * CFrame.new(x, 9.9, z - 3.2) * CFrame.Angles(math.rad(-12), 0, 0), k % 2 == 0 and C("Bright yellow") or WHITE, Enum.Material.Plastic)
	end
	local roofSign = Build.Block(model, "RoofSign", Vector3.new(14, 3, 0.5), cf * CFrame.new(0, 12.6, z - 8), C("Bright yellow"), Enum.Material.Plastic)
	Build.Sign(roofSign, Enum.NormalId.Front, laneCfg.Emoji .. " " .. string.upper(laneCfg.Name), {})
	for i = 1, 6 do
		Build.Egg(model, "Lemon" .. i, Vector3.new(1.4, 1.05, 1.05), cf * CFrame.new(-5 + i * 1.6, 5.1, z - 4 + (i % 2) * 0.8), C("Bright yellow"), Enum.Material.Plastic)
	end
	Build.Block(model, "Hatch", Vector3.new(4, 2.2, 0.2), cf * CFrame.new(0, 3, z - 8.05), C("Really black"), Enum.Material.Plastic)
	smallTree(model, cf * CFrame.new(-5, 0, z + 9), true)
	crate(model, cf * CFrame.new(5, 0, z + 8), 3)
	crate(model, cf * CFrame.new(5.4, 3, z + 8.3), 2.4)
	Build.Block(model, "Pitcher", Vector3.new(1.2, 1.8, 1.2), cf * CFrame.new(6.5, 5.5, z - 5), C("Pastel yellow"), Enum.Material.Glass, { Transparency = 0.2 })
end

function Machines.Delivery(model, cf: CFrame, laneCfg)
	local z = L.MachineZ
	Build.Block(model, "Building", Vector3.new(18, 11, 14), cf * CFrame.new(0, 5.5, z + 1), C("Bright red"), Enum.Material.Brick)
	Build.Block(model, "Roof", Vector3.new(19, 1, 15), cf * CFrame.new(0, 11.5, z + 1), C("Dark stone grey"), Enum.Material.Concrete)
	Build.Block(model, "Door", Vector3.new(10, 7, 0.3), cf * CFrame.new(0, 3.5, z - 6.1), C("Medium stone grey"), Enum.Material.Metal)
	for k = 1, 4 do
		Build.Block(model, "DoorLine" .. k, Vector3.new(10, 0.15, 0.1), cf * CFrame.new(0, 1.4 * k + 0.3, z - 6.3), C("Dark stone grey"), Enum.Material.Metal)
	end
	Build.Block(model, "Hatch", Vector3.new(4, 2.4, 0.2), cf * CFrame.new(0, 2.4, z - 6.35), C("Really black"), Enum.Material.Plastic)
	local sign = Build.Block(model, "Sign", Vector3.new(15, 2.6, 0.4), cf * CFrame.new(0, 9.2, z - 6.3), C("Bright blue"), Enum.Material.Plastic)
	Build.Sign(sign, Enum.NormalId.Front, laneCfg.Emoji .. " " .. string.upper(laneCfg.Name), {})
	Build.Cylinder(model, "BigBottle", 7, 3.6, cf * CFrame.new(0, 15.5, z + 1), C("Bright yellow"), Enum.Material.Glass, { Transparency = 0.15 })
	Build.Cylinder(model, "BottleNeck", 2.2, 1.5, cf * CFrame.new(0, 20.1, z + 1), C("Bright yellow"), Enum.Material.Glass, { Transparency = 0.15 })
	Build.Cylinder(model, "BottleCap", 0.7, 1.8, cf * CFrame.new(0, 21.5, z + 1), C("Bright red"), Enum.Material.Plastic)
	for i = 0, 2 do
		crate(model, cf * CFrame.new(-7 + i * 2.8, 0, z + 11), 2.4)
	end
end

function Machines.Depot(model, cf: CFrame, laneCfg)
	local z = L.MachineZ
	Build.Block(model, "Hall", Vector3.new(18, 12, 15), cf * CFrame.new(0, 6, z + 1), C("Sand blue"), Enum.Material.Metal)
	Build.Block(model, "RoofL", Vector3.new(10.4, 1, 16), cf * CFrame.new(-4.5, 14, z + 1) * CFrame.Angles(0, 0, math.rad(25)), C("Dark stone grey"), Enum.Material.Metal)
	Build.Block(model, "RoofR", Vector3.new(10.4, 1, 16), cf * CFrame.new(4.5, 14, z + 1) * CFrame.Angles(0, 0, math.rad(-25)), C("Dark stone grey"), Enum.Material.Metal)
	Build.Block(model, "Gable", Vector3.new(16, 3, 14.6), cf * CFrame.new(0, 12.6, z + 1), C("Sand blue"), Enum.Material.Metal)
	Build.Block(model, "Door", Vector3.new(9, 8, 0.3), cf * CFrame.new(0, 4, z - 6.6), C("Bright yellow"), Enum.Material.Metal)
	Build.Block(model, "Hatch", Vector3.new(4, 2.4, 0.2), cf * CFrame.new(0, 2.4, z - 6.85), C("Really black"), Enum.Material.Plastic)
	local sign = Build.Block(model, "Sign", Vector3.new(14, 2.6, 0.4), cf * CFrame.new(0, 10, z - 6.7), C("Bright green"), Enum.Material.Plastic)
	Build.Sign(sign, Enum.NormalId.Front, laneCfg.Emoji .. " " .. string.upper(laneCfg.Name), {})
	Build.Cylinder(model, "Silo", 16, 5, cf * CFrame.new(-6, 8, z + 12), C("Institutional white"), Enum.Material.Metal)
	Build.Ball(model, "SiloTop", 5, cf * CFrame.new(-6, 16, z + 12), C("Bright green"), Enum.Material.Metal)
	Build.Block(model, "Pallet", Vector3.new(4, 0.5, 4), cf * CFrame.new(5, 0.25, z + 12), C("Brown"), Enum.Material.WoodPlanks)
	Build.Block(model, "Box1", Vector3.new(3.4, 3, 3.4), cf * CFrame.new(5, 2, z + 12), C("Brick yellow"), Enum.Material.Cardboard)
end

function Machines.Lab(model, cf: CFrame, laneCfg)
	local z = L.MachineZ
	Build.Block(model, "Building", Vector3.new(16, 10, 14), cf * CFrame.new(0, 5, z + 1), C("Institutional white"), Enum.Material.Plastic)
	Build.Block(model, "Stripe", Vector3.new(16.2, 1, 14.2), cf * CFrame.new(0, 9, z + 1), C("Bright blue"), Enum.Material.Plastic)
	Build.Block(model, "Window", Vector3.new(13, 2, 0.2), cf * CFrame.new(0, 6.6, z - 6.05), C("Pastel light blue"), Enum.Material.Glass, { Transparency = 0.2 })
	Build.Ball(model, "Dome", 9, cf * CFrame.new(0, 10, z + 1), C("Pastel light blue"), Enum.Material.Glass, { Transparency = 0.4 })
	Build.Block(model, "Hatch", Vector3.new(4, 2.4, 0.2), cf * CFrame.new(0, 2.4, z - 6.05), C("Really black"), Enum.Material.Plastic)
	local sign = Build.Block(model, "Sign", Vector3.new(12, 2.4, 0.4), cf * CFrame.new(0, 11.4, z - 5.8), C("Bright blue"), Enum.Material.Plastic)
	Build.Sign(sign, Enum.NormalId.Front, laneCfg.Emoji .. " " .. string.upper(laneCfg.Name), {})
	local liquids = { C("Lime green"), C("Toothpaste"), C("Hot pink") }
	for i, x in ipairs({ -10.5, 10.5 }) do
		Build.Cylinder(model, "Tube" .. i, 8, 2.6, cf * CFrame.new(x, 4, z - 2), WHITE, Enum.Material.Glass, { Transparency = 0.55 })
		local liquid = Build.Cylinder(model, "Liquid" .. i, 6, 2, cf * CFrame.new(x, 3.2, z - 2), liquids[i], Enum.Material.Neon)
		Build.NoCollide(liquid)
		Build.Cylinder(model, "TubeCap" .. i, 0.6, 3, cf * CFrame.new(x, 8.2, z - 2), C("Dark stone grey"), Enum.Material.Metal)
	end
	local glow = Build.Ball(model, "Core", 3, cf * CFrame.new(0, 10, z + 1), liquids[3], Enum.Material.Neon)
	Build.NoCollide(glow)
	Build.Light(glow, liquids[3], 14, 1)
end

function Machines.Stocks(model, cf: CFrame, laneCfg)
	local z = L.MachineZ
	Build.Block(model, "Steps1", Vector3.new(18, 0.6, 3), cf * CFrame.new(0, 0.3, z - 7), C("Institutional white"), Enum.Material.Marble)
	Build.Block(model, "Steps2", Vector3.new(16, 1.2, 2), cf * CFrame.new(0, 0.6, z - 5.5), C("Institutional white"), Enum.Material.Marble)
	Build.Block(model, "Building", Vector3.new(16, 10, 11), cf * CFrame.new(0, 6, z + 2.5), C("Institutional white"), Enum.Material.Marble)
	for _, x in ipairs({ -6.5, -2.6, 2.6, 6.5 }) do
		Build.Cylinder(model, "Column", 9, 1.5, cf * CFrame.new(x, 5.7, z - 4.6), WHITE, Enum.Material.Marble)
	end
	Build.Block(model, "Beam", Vector3.new(18, 1.5, 4), cf * CFrame.new(0, 10.9, z - 4), C("Institutional white"), Enum.Material.Marble)
	Build.Block(model, "Roof1", Vector3.new(14, 1.5, 15), cf * CFrame.new(0, 12.3, z + 1), C("Institutional white"), Enum.Material.Marble)
	Build.Block(model, "Roof2", Vector3.new(8, 1.5, 15), cf * CFrame.new(0, 13.8, z + 1), C("Institutional white"), Enum.Material.Marble)
	Build.Block(model, "Hatch", Vector3.new(4, 2.6, 0.2), cf * CFrame.new(0, 2.5, z - 2.95), C("Really black"), Enum.Material.Plastic)
	local sign = Build.Block(model, "Sign", Vector3.new(14, 1.4, 0.3), cf * CFrame.new(0, 10.9, z - 6.1), C("Gold"), Enum.Material.Plastic)
	Build.Sign(sign, Enum.NormalId.Front, laneCfg.Emoji .. " " .. string.upper(laneCfg.Name), {})

	-- Kurs-Bildschirm
	local screen = Build.Block(model, "Screen", Vector3.new(12, 6, 0.6), cf * CFrame.new(0, 18, z + 2), C("Really black"), Enum.Material.Plastic)
	Build.Block(model, "ScreenPole", Vector3.new(0.8, 3, 0.8), cf * CFrame.new(0, 14.5, z + 2), C("Dark stone grey"), Enum.Material.Metal)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "ChartGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = screen
	local heights = { 0.25, 0.35, 0.3, 0.5, 0.45, 0.65, 0.6, 0.85 }
	for i, hgt in ipairs(heights) do
		local bar = Instance.new("Frame")
		bar.Name = "Bar" .. i
		bar.AnchorPoint = Vector2.new(0, 1)
		bar.Size = UDim2.fromScale(0.09, hgt)
		bar.Position = UDim2.fromScale(0.04 + (i - 1) * 0.12, 0.95)
		bar.BackgroundColor3 = (i > 1 and hgt < heights[i - 1]) and Color3.fromRGB(255, 70, 70) or Color3.fromRGB(70, 255, 110)
		bar.BorderSizePixel = 0
		bar.Parent = gui
	end
	local up = Instance.new("TextLabel")
	up.Size = UDim2.fromScale(0.4, 0.3)
	up.Position = UDim2.fromScale(0.04, 0.04)
	up.BackgroundTransparency = 1
	up.FontFace = Font.fromEnum(Build.FONT)
	up.Text = "🍋 +420%"
	up.TextScaled = true
	up.TextColor3 = Color3.fromRGB(70, 255, 110)
	up.TextXAlignment = Enum.TextXAlignment.Left
	up.Parent = gui
end

function Machines.Space(model, cf: CFrame, laneCfg)
	local z = L.MachineZ
	Build.Cylinder(model, "Base", 2, 17, cf * CFrame.new(0, 1, z + 2), C("Dark stone grey"), Enum.Material.DiamondPlate)
	Build.Ball(model, "Dome", 14, cf * CFrame.new(0, 2, z + 2), C("Pastel light blue"), Enum.Material.Glass, { Transparency = 0.5 })
	for i = 1, 3 do
		local a = math.rad(i * 120)
		local plantCF = cf * CFrame.new(math.cos(a) * 3, 0, z + 2 + math.sin(a) * 3)
		Build.Block(model, "Stem" .. i, Vector3.new(0.4, 4, 0.4), plantCF * CFrame.new(0, 4, 0), C("Lime green"), Enum.Material.Neon)
		Build.Ball(model, "AlienFruit" .. i, 1.6, plantCF * CFrame.new(0, 6.4, 0), C("Royal purple"), Enum.Material.Neon)
	end
	Build.Block(model, "Tunnel", Vector3.new(5, 5, 6), cf * CFrame.new(0, 2.5, z - 5.5), C("Medium stone grey"), Enum.Material.Metal)
	Build.Block(model, "Hatch", Vector3.new(3.6, 2.6, 0.2), cf * CFrame.new(0, 2.5, z - 8.55), C("Really black"), Enum.Material.Plastic)
	Build.Block(model, "Antenna", Vector3.new(0.6, 12, 0.6), cf * CFrame.new(7, 6, z + 10), C("Medium stone grey"), Enum.Material.Metal)
	local tip = Build.Ball(model, "AntennaTip", 1.4, cf * CFrame.new(7, 12.5, z + 10), C("Really red"), Enum.Material.Neon)
	Build.Light(tip, Color3.fromRGB(255, 60, 60), 10, 1)
	Build.CylinderX(model, "Dish", 0.4, 5, cf * CFrame.new(7, 9, z + 10) * CFrame.Angles(0, math.rad(90), math.rad(35)), WHITE, Enum.Material.Metal)
	local sign = Build.Block(model, "Sign", Vector3.new(14, 2.4, 0.4), cf * CFrame.new(0, 6.3, z - 8.4), C("Bright violet"), Enum.Material.Plastic)
	Build.Sign(sign, Enum.NormalId.Front, laneCfg.Emoji .. " " .. string.upper(laneCfg.Name), {})
	-- kleine Rakete
	Build.Cylinder(model, "Rocket", 7, 2.4, cf * CFrame.new(-7, 4.5, z + 10), WHITE, Enum.Material.Plastic)
	Build.Ball(model, "RocketNose", 2.4, cf * CFrame.new(-7, 8, z + 10), C("Really red"), Enum.Material.Plastic)
	for i = 0, 2 do
		local a = math.rad(i * 120)
		Build.Block(model, "Fin" .. i, Vector3.new(0.3, 2, 1.6), cf * CFrame.new(-7 + math.cos(a) * 1.4, 1.5, z + 10 + math.sin(a) * 1.4) * CFrame.Angles(0, -a, 0), C("Really red"), Enum.Material.Plastic)
	end
end

--------------------------------------------------------------------------
-- Verkaufsstelle am Bandende + Deko je Thema
--------------------------------------------------------------------------
local SellerProps = {}

function SellerProps.Stand(model, cf: CFrame)
	Build.Block(model, "Table", Vector3.new(4, 3, 3), cf * CFrame.new(0, 1.5, 0), C("Brown"), Enum.Material.WoodPlanks)
	Build.Block(model, "Register", Vector3.new(2.4, 1.6, 1.8), cf * CFrame.new(0, 3.8, 0), C("Medium stone grey"), Enum.Material.Metal)
	Build.Block(model, "Display", Vector3.new(1.8, 0.8, 0.2), cf * CFrame.new(0, 5, -0.6), C("Lime green"), Enum.Material.Neon)
end

function SellerProps.Delivery(model, cf: CFrame)
	Build.Block(model, "Cargo", Vector3.new(5, 4.6, 6.5), cf * CFrame.new(0, 3.3, 1.2), WHITE, Enum.Material.Plastic)
	Build.Block(model, "Stripe", Vector3.new(5.1, 0.8, 6.6), cf * CFrame.new(0, 3.3, 1.2), C("Bright red"), Enum.Material.Plastic)
	Build.Block(model, "Cab", Vector3.new(5, 3.4, 3), cf * CFrame.new(0, 2.7, -3.6), C("Bright red"), Enum.Material.Plastic)
	Build.Block(model, "Windshield", Vector3.new(4.4, 1.4, 0.2), cf * CFrame.new(0, 3.5, -5.15), C("Pastel light blue"), Enum.Material.Glass)
	for _, p in ipairs({ { -2.6, -3.4 }, { 2.6, -3.4 }, { -2.6, 2.8 }, { 2.6, 2.8 } }) do
		Build.CylinderX(model, "Wheel", 0.8, 2, cf * CFrame.new(p[1], 1, p[2]), C("Really black"), Enum.Material.Plastic)
	end
end

function SellerProps.Depot(model, cf: CFrame)
	Build.Block(model, "Pallet", Vector3.new(4.5, 0.5, 4.5), cf * CFrame.new(0, 0.25, 0), C("Brown"), Enum.Material.WoodPlanks)
	Build.Block(model, "BoxA", Vector3.new(2, 2, 2), cf * CFrame.new(-1, 1.5, -1), C("Brick yellow"), Enum.Material.Cardboard)
	Build.Block(model, "BoxB", Vector3.new(2, 2, 2), cf * CFrame.new(1, 1.5, 1), C("Brick yellow"), Enum.Material.Cardboard)
	Build.Block(model, "BoxC", Vector3.new(2, 2, 2), cf * CFrame.new(0, 3.5, 0), C("Brick yellow"), Enum.Material.Cardboard)
end

function SellerProps.Lab(model, cf: CFrame)
	Build.Block(model, "Terminal", Vector3.new(3, 4, 2), cf * CFrame.new(0, 2, 0), C("Institutional white"), Enum.Material.Plastic)
	Build.Block(model, "Screen", Vector3.new(2.4, 1.6, 0.2), cf * CFrame.new(0, 3, -1.05), C("Cyan"), Enum.Material.Neon)
end

function SellerProps.Stocks(model, cf: CFrame)
	for i = 0, 5 do
		local row = i < 3 and 0 or 1
		local col = i % 3
		Build.Block(model, "GoldBar" .. i, Vector3.new(1.2, 0.6, 2.2), cf * CFrame.new(-1.3 + col * 1.3 + row * 0.65, 0.3 + row * 0.6, 0), C("Gold"), Enum.Material.Foil)
	end
end

function SellerProps.Space(model, cf: CFrame)
	Build.Cylinder(model, "Teleporter", 0.6, 5, cf * CFrame.new(0, 0.3, 0), C("Bright violet"), Enum.Material.Neon)
	local ring = Build.Cylinder(model, "TeleRing", 0.3, 4, cf * CFrame.new(0, 3, 0), C("Royal purple"), Enum.Material.ForceField)
	Build.NoCollide(ring)
end

local function buildBelt(model, cf: CFrame, laneCfg)
	local beltLen = L.BeltStartZ - L.BeltEndZ
	local zMid = (L.BeltStartZ + L.BeltEndZ) / 2
	local belt = Build.Block(model, "Belt", Vector3.new(6, 1, beltLen), cf * CFrame.new(0, L.BeltY - 0.5, zMid), C("Really black"), Enum.Material.Plastic)
	belt:SetAttribute("BeltLength", beltLen)
	Build.Block(model, "RailL", Vector3.new(0.6, 1.4, beltLen), cf * CFrame.new(-3.3, L.BeltY - 0.2, zMid), C("Medium stone grey"), Enum.Material.Metal)
	Build.Block(model, "RailR", Vector3.new(0.6, 1.4, beltLen), cf * CFrame.new(3.3, L.BeltY - 0.2, zMid), C("Medium stone grey"), Enum.Material.Metal)
	Build.Block(model, "StripeL", Vector3.new(0.65, 0.3, beltLen), cf * CFrame.new(-3.3, L.BeltY + 0.35, zMid), laneCfg.Color, Enum.Material.Plastic)
	Build.Block(model, "StripeR", Vector3.new(0.65, 0.3, beltLen), cf * CFrame.new(3.3, L.BeltY + 0.35, zMid), laneCfg.Color, Enum.Material.Plastic)
	Build.CylinderX(model, "RollerStart", 6.2, 1.4, cf * CFrame.new(0, L.BeltY - 0.6, L.BeltStartZ), C("Dark stone grey"), Enum.Material.Metal)
	Build.CylinderX(model, "RollerEnd", 6.2, 1.4, cf * CFrame.new(0, L.BeltY - 0.6, L.BeltEndZ), C("Dark stone grey"), Enum.Material.Metal)
	local z = L.BeltEndZ + 4
	while z < L.BeltStartZ - 2 do
		for _, x in ipairs({ -2.4, 2.4 }) do
			Build.Block(model, "Leg", Vector3.new(0.8, L.BeltY - 1, 0.8), cf * CFrame.new(x, (L.BeltY - 1) / 2, z), C("Dark stone grey"), Enum.Material.Metal)
		end
		z += 12
	end
end

local function buildSeller(model, cf: CFrame, laneCfg)
	local z = L.SellerZ
	local seller = Build.Model(model, "Seller")
	Build.Block(seller, "Floor", Vector3.new(10, 0.6, 10), cf * CFrame.new(0, 0.3, z), C("Dark stone grey"), Enum.Material.Metal)
	local glow = Build.Block(seller, "Glow", Vector3.new(8, 0.2, 8), cf * CFrame.new(0, 0.65, z), C("Lime green"), Enum.Material.Neon)
	Build.NoCollide(glow)
	Build.Block(seller, "WallBack", Vector3.new(10, 3, 1), cf * CFrame.new(0, 1.5, z - 4.5), laneCfg.Color, Enum.Material.Plastic)
	Build.Block(seller, "WallL", Vector3.new(1, 3, 10), cf * CFrame.new(-4.5, 1.5, z), laneCfg.Color, Enum.Material.Plastic)
	Build.Block(seller, "WallR", Vector3.new(1, 3, 10), cf * CFrame.new(4.5, 1.5, z), laneCfg.Color, Enum.Material.Plastic)
	Build.Block(seller, "WallFront", Vector3.new(8, 2.2, 1), cf * CFrame.new(0, 1.1, z + 4.5), laneCfg.Color, Enum.Material.Plastic)
	Build.Block(seller, "SignPost", Vector3.new(0.6, 7, 0.6), cf * CFrame.new(0, 3.5, z - 5.4), C("Dark stone grey"), Enum.Material.Metal)
	local sign = Build.Block(seller, "Sign", Vector3.new(9, 2.6, 0.4), cf * CFrame.new(0, 7.5, z - 5.4), C("Lime green"), Enum.Material.Plastic)
	Build.Sign(sign, Enum.NormalId.Back, "💵 VERKAUF 💵", {})
	Build.Sign(sign, Enum.NormalId.Front, "💵 VERKAUF 💵", { Name = "SignGuiFront" })
	local props = SellerProps[laneCfg.Theme]
	if props then
		local propModel = Build.Model(model, "SellerProps")
		props(propModel, cf * CFrame.new(10.5, 0, z))
	end
end

local function buildPanel(model, cf: CFrame, laneCfg)
	local p = L.PanelOffset
	local panel = Build.Model(model, "Panel")
	Build.Block(panel, "Stand", Vector3.new(3, 3.6, 3), cf * CFrame.new(p.X, 1.8, p.Z), C("Dark stone grey"), Enum.Material.Metal)
	local top = Build.Block(panel, "Top", Vector3.new(3.6, 0.5, 3.6), cf * CFrame.new(p.X, 3.85, p.Z), laneCfg.Color, Enum.Material.Plastic)
	top.Name = "Top"
	Build.Cylinder(panel, "ButtonBase", 0.4, 2.8, cf * CFrame.new(p.X, 4.25, p.Z), C("Really black"), Enum.Material.Plastic)
	local button = Build.Cylinder(panel, "PressButton", 0.7, 2.2, cf * CFrame.new(p.X, 4.6, p.Z), C("Really red"), Enum.Material.Neon)
	local click = Instance.new("ClickDetector")
	click.Name = "Click"
	click.MaxActivationDistance = 40
	click.Parent = button
	Build.Prompt(button, "Pressen!", laneCfg.Emoji .. " " .. laneCfg.Name, { Name = "PressPrompt", Distance = 10 })
end

--------------------------------------------------------------------------
-- Linie bauen
--------------------------------------------------------------------------
function PlotBuilder.BuildLane(plot: Model, laneIndex: number): Model
	local laneCfg = Config.Lanes[laneIndex]
	local lanes = plot:FindFirstChild("Lanes")
	local existing = lanes:FindFirstChild("Lane" .. laneIndex)
	if existing then
		return existing
	end
	local placeholder = (plot:FindFirstChild("Placeholders") :: Folder):FindFirstChild("Lane" .. laneIndex)
	if placeholder then
		placeholder:Destroy()
	end

	local cf = PlotBuilder.LaneCFrame(origin(plot), laneIndex)
	local model = Build.Model(nil, "Lane" .. laneIndex)
	model:SetAttribute("Index", laneIndex)

	local floorColor = Build.Shade(laneCfg.Color, 0.55, WHITE)
	Build.Block(model, "Floor", Vector3.new(28, 0.2, 152), cf * CFrame.new(0, 0.1, 10), floorColor, Enum.Material.Plastic)

	local machine = Build.Model(model, "Machine")
	local builder = Machines[laneCfg.Theme]
	if builder then
		builder(machine, cf, laneCfg)
	end
	buildBelt(model, cf, laneCfg)
	buildSeller(model, cf, laneCfg)
	buildPanel(model, cf, laneCfg)
	Build.Folder(model, "Upgraders")

	model.Parent = lanes
	return model
end

--------------------------------------------------------------------------
-- Maschinen-Bogen (Upgrader) über dem Band
--------------------------------------------------------------------------
function PlotBuilder.BuildUpgrader(plot: Model, laneIndex: number, upgraderIndex: number): Model?
	local lane = (plot:FindFirstChild("Lanes") :: Folder):FindFirstChild("Lane" .. laneIndex)
	if not lane then
		return nil
	end
	local folder = lane:FindFirstChild("Upgraders")
	local name = "Upgrader" .. upgraderIndex
	if folder:FindFirstChild(name) then
		return folder[name]
	end
	local laneCfg = Config.Lanes[laneIndex]
	local info = laneCfg.Upgraders[upgraderIndex]
	local cf = PlotBuilder.LaneCFrame(origin(plot), laneIndex) * CFrame.new(0, 0, L.UpgraderZ[upgraderIndex])
	local model = Build.Model(nil, name)
	local metal = C("Dark stone grey")

	for _, x in ipairs({ -4.7, 4.7 }) do
		Build.Block(model, "Pillar", Vector3.new(1.4, 9, 3), cf * CFrame.new(x, 4.5, 0), metal, Enum.Material.Metal)
		Build.Block(model, "Box", Vector3.new(2.4, 3.4, 3.8), cf * CFrame.new(x, 2.2, 0), info.Color, Enum.Material.Plastic)
		local light = Build.Ball(model, "Light", 0.9, cf * CFrame.new(x, 4.3, -1.95), C("Lime green"), Enum.Material.Neon)
		Build.NoCollide(light)
	end
	local beam = Build.Block(model, "Beam", Vector3.new(11, 2.8, 3.4), cf * CFrame.new(0, 10.3, 0), info.Color, Enum.Material.Plastic)
	local text = info.Name .. "  ×" .. info.Mult
	Build.Sign(beam, Enum.NormalId.Front, text, { PixelsPerStud = 25 })
	Build.Sign(beam, Enum.NormalId.Back, text, { Name = "SignGuiBack", PixelsPerStud = 25 })
	local scanner = Build.Block(model, "Scanner", Vector3.new(8, 0.3, 2.6), cf * CFrame.new(0, 8.75, 0), info.Color, Enum.Material.Neon)
	Build.NoCollide(scanner)
	Build.Sparkles(scanner, info.Color, 10)
	Build.Light(scanner, info.Color, 10, 1)
	local top = Build.Cylinder(model, "TopLamp", 1, 1.6, cf * CFrame.new(0, 12.2, 0), C("New Yeller"), Enum.Material.Neon)
	Build.NoCollide(top)

	model.Parent = folder
	return model
end

--------------------------------------------------------------------------
-- Deko
--------------------------------------------------------------------------
local Decor = {}

function Decor.fence(model, cf: CFrame)
	local half = L.PlotSize / 2 - 2
	local wood = C("Brown")
	local function side(name, from: Vector3, to: Vector3)
		local delta = to - from
		local length = delta.Magnitude
		local mid = (from + to) / 2
		local rot = CFrame.lookAt(Vector3.zero, delta)
		for _, h in ipairs({ 1.6, 3.2 }) do
			Build.Block(model, name .. "Rail", Vector3.new(0.4, 0.5, length), cf * CFrame.new(mid + Vector3.new(0, h, 0)) * rot, wood, Enum.Material.WoodPlanks)
		end
		local count = math.floor(length / 10)
		for k = 0, count do
			local p = from + delta * (k / math.max(count, 1))
			Build.Block(model, name .. "Post", Vector3.new(0.8, 4.2, 0.8), cf * CFrame.new(p + Vector3.new(0, 2.1, 0)), C("Reddish brown"), Enum.Material.Wood)
		end
	end
	side("Back", Vector3.new(-half, 0, half), Vector3.new(half, 0, half))
	side("Left", Vector3.new(-half, 0, -half), Vector3.new(-half, 0, half))
	side("Right", Vector3.new(half, 0, -half), Vector3.new(half, 0, half))
	side("FrontL", Vector3.new(-half, 0, -half), Vector3.new(-20, 0, -half))
	side("FrontR", Vector3.new(20, 0, -half), Vector3.new(half, 0, -half))
end

function Decor.flowers(model, cf: CFrame)
	local colors = { C("Hot pink"), C("New Yeller"), C("Really red"), C("Lavender"), C("White"), C("Bright orange") }
	local n = 0
	for _, side in ipairs({ -1, 1 }) do
		local centerX = side * 55
		Build.Block(model, "Planter", Vector3.new(66, 1.2, 4), cf * CFrame.new(centerX, 0.6, -89), C("Brown"), Enum.Material.WoodPlanks)
		Build.Block(model, "Soil", Vector3.new(64.5, 0.3, 3), cf * CFrame.new(centerX, 1.3, -89), C("Reddish brown"), Enum.Material.Ground)
		for k = 0, 15 do
			n += 1
			local x = centerX - 30 + k * 4
			Build.Block(model, "Stem", Vector3.new(0.3, 1.4, 0.3), cf * CFrame.new(x, 2, -89), C("Bright green"), Enum.Material.Plastic)
			Build.Ball(model, "Bloom", 1.1, cf * CFrame.new(x, 2.9, -89), colors[n % #colors + 1], Enum.Material.Plastic)
		end
	end
end

function Decor.lamps(model, cf: CFrame)
	local spots = { { -24, -86 }, { 24, -86 }, { -92, -40 }, { 92, -40 }, { -92, 40 }, { 92, 40 }, { -92, 88 }, { 92, 88 } }
	for i, s in ipairs(spots) do
		local lamp = Build.Model(model, "Lamp" .. i)
		local base = cf * CFrame.new(s[1], 0, s[2])
		Build.Block(lamp, "Post", Vector3.new(0.8, 10, 0.8), base * CFrame.new(0, 5, 0), C("Black"), Enum.Material.Metal)
		local head = Build.Block(lamp, "Head", Vector3.new(2, 1.6, 2), base * CFrame.new(0, 10.6, 0), C("Pastel yellow"), Enum.Material.Neon)
		Build.Block(lamp, "Cap", Vector3.new(2.6, 0.5, 2.6), base * CFrame.new(0, 11.6, 0), C("Black"), Enum.Material.Metal)
		Build.Light(head, Color3.fromRGB(255, 230, 170), 24, 1.2)
	end
end

function Decor.palms(model, cf: CFrame)
	for i, s in ipairs({ { -88, -88 }, { 88, -88 }, { -89, 89 }, { 89, 89 } }) do
		local palm = Build.Model(model, "Palm" .. i)
		local base = cf * CFrame.new(s[1], 0, s[2])
		local lean = (i % 2 == 0) and 1 or -1
		local top = base
		for k = 0, 5 do
			local segCF = base * CFrame.new(lean * k * 0.35, 1 + k * 2, 0) * CFrame.Angles(0, 0, math.rad(-lean * k * 2))
			Build.Block(palm, "Trunk" .. k, Vector3.new(1.6 - k * 0.1, 2.1, 1.6 - k * 0.1), segCF, C("Brown"), Enum.Material.Wood)
			top = segCF
		end
		local crown = top * CFrame.new(0, 1.4, 0)
		for k = 0, 5 do
			local a = math.rad(k * 60)
			Build.Block(palm, "Leaf" .. k, Vector3.new(1.4, 0.3, 7), crown * CFrame.Angles(0, a, 0) * CFrame.new(0, -0.6, 3.2) * CFrame.Angles(math.rad(18), 0, 0), C("Bright green"), Enum.Material.Plastic)
		end
		Build.Ball(palm, "Coconut1", 1, crown * CFrame.new(0.6, -0.8, 0.4), C("Reddish brown"), Enum.Material.Plastic)
		Build.Ball(palm, "Coconut2", 1, crown * CFrame.new(-0.5, -0.8, -0.4), C("Reddish brown"), Enum.Material.Plastic)
	end
end

function Decor.fountain(model, cf: CFrame)
	local base = cf * CFrame.new(-55, 0, -76)
	Build.Cylinder(model, "Basin", 2, 15, base * CFrame.new(0, 1, 0), C("Medium stone grey"), Enum.Material.Plastic)
	local water = Build.Cylinder(model, "Water", 0.3, 13, base * CFrame.new(0, 2.05, 0), C("Bright bluish green"), Enum.Material.Glass, { Transparency = 0.25 })
	Build.NoCollide(water)
	Build.Cylinder(model, "Pillar", 6, 2, base * CFrame.new(0, 4, 0), C("Medium stone grey"), Enum.Material.Plastic)
	Build.Cylinder(model, "Bowl", 1, 6, base * CFrame.new(0, 7.3, 0), C("Medium stone grey"), Enum.Material.Plastic)
	local lemon = Build.Egg(model, "Lemon", Vector3.new(4, 3, 3), base * CFrame.new(0, 9.5, 0) * CFrame.Angles(0, 0, math.rad(20)), C("Bright yellow"), Enum.Material.Plastic)
	local spray = Instance.new("ParticleEmitter")
	spray.Name = "Spray"
	spray.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	spray.Color = ColorSequence.new(Color3.fromRGB(120, 200, 255))
	spray.Size = NumberSequence.new(0.5)
	spray.Lifetime = NumberRange.new(1, 1.4)
	spray.Rate = 30
	spray.Speed = NumberRange.new(8, 11)
	spray.SpreadAngle = Vector2.new(25, 25)
	spray.Acceleration = Vector3.new(0, -25, 0)
	spray.Parent = lemon
end

function Decor.statue(model, cf: CFrame)
	local base = cf * CFrame.new(55, 0, -76)
	Build.Block(model, "Pedestal", Vector3.new(8, 4, 8), base * CFrame.new(0, 2, 0), C("Institutional white"), Enum.Material.Marble)
	Build.Block(model, "PedestalTop", Vector3.new(9, 0.6, 9), base * CFrame.new(0, 4.3, 0), C("Gold"), Enum.Material.Foil)
	local lemonCF = base * CFrame.new(0, 10, 0) * CFrame.Angles(0, 0, math.rad(25))
	local lemon = Build.Egg(model, "GiantLemon", Vector3.new(12, 9, 9), lemonCF, C("New Yeller"), Enum.Material.Plastic)
	Build.Egg(model, "TipA", Vector3.new(2, 1.6, 1.6), lemonCF * CFrame.new(6, 0, 0), C("New Yeller"), Enum.Material.Plastic)
	Build.Egg(model, "TipB", Vector3.new(2, 1.6, 1.6), lemonCF * CFrame.new(-6, 0, 0), C("New Yeller"), Enum.Material.Plastic)
	Build.Block(model, "Leaf", Vector3.new(3, 0.3, 1.6), lemonCF * CFrame.new(-5, 3.8, 0) * CFrame.Angles(0, 0, math.rad(30)), C("Bright green"), Enum.Material.Plastic)
	Build.Sparkles(lemon, Color3.fromRGB(255, 240, 120), 6)
	local plaque = Build.Block(model, "Plaque", Vector3.new(6, 1.6, 0.2), base * CFrame.new(0, 2.2, -4.1), C("Gold"), Enum.Material.Foil)
	Build.Sign(plaque, Enum.NormalId.Front, "KÖNIG DER ZITRONEN", {})
end

function PlotBuilder.BuildDecor(plot: Model, decorIndex: number): Model?
	local info = Config.Decor[decorIndex]
	local folder = plot:FindFirstChild("Decor")
	if not info or not folder or folder:FindFirstChild(info.Id) then
		return nil
	end
	local model = Build.Model(nil, info.Id)
	local fn = Decor[info.Id]
	if fn then
		fn(model, origin(plot))
	end
	model.Parent = folder
	return model
end

--------------------------------------------------------------------------
-- Kauf-Knöpfe
--------------------------------------------------------------------------
function PlotBuilder.CreatePad(plot: Model, padId: string, localPos: Vector3, title: string, cost: number, kind: string, laneIndex: number?): Model
	local buttons = plot:FindFirstChild("Buttons")
	local existing = buttons:FindFirstChild(padId)
	if existing then
		existing:Destroy()
	end
	local cf = origin(plot) * CFrame.new(localPos.X, 0, localPos.Z)
	local model = Build.Model(nil, padId)
	model:SetAttribute("PadId", padId)
	model:SetAttribute("Cost", cost)
	model:SetAttribute("Kind", kind)
	model:SetAttribute("LaneIndex", laneIndex or 0)
	model:SetAttribute("Title", title)

	Build.Block(model, "Ring", Vector3.new(5.6, 0.5, 5.6), cf * CFrame.new(0, 0.25, 0), C("Really black"), Enum.Material.Plastic)
	local pad = Build.Block(model, "Pad", Vector3.new(4.6, 0.6, 4.6), cf * CFrame.new(0, 0.55, 0), C("Lime green"), Enum.Material.Neon)
	model.PrimaryPart = pad

	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromScale(9, 3.2)
	gui.StudsOffset = Vector3.new(0, 3.6, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.Parent = pad
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.fromScale(1, 0.55)
	titleLabel.BackgroundTransparency = 1
	titleLabel.FontFace = Font.fromEnum(Build.FONT)
	titleLabel.Text = title
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = WHITE
	titleLabel.TextStrokeTransparency = 0
	titleLabel.Parent = gui
	local price = Instance.new("TextLabel")
	price.Name = "Price"
	price.Size = UDim2.fromScale(1, 0.45)
	price.Position = UDim2.fromScale(0, 0.55)
	price.BackgroundTransparency = 1
	price.FontFace = Font.fromEnum(Build.FONT)
	price.Text = "$" .. tostring(cost)
	price.TextScaled = true
	price.TextColor3 = Color3.fromRGB(120, 255, 120)
	price.TextStrokeTransparency = 0
	price.Parent = gui

	model.Parent = buttons
	return model
end

--------------------------------------------------------------------------
-- Alles Gekaufte entfernen (Rebirth / Spieler geht)
--------------------------------------------------------------------------
function PlotBuilder.Clear(plot: Model)
	for _, folderName in ipairs({ "Lanes", "Buttons", "Decor", "Managers" }) do
		local folder = plot:FindFirstChild(folderName)
		if folder then
			folder:ClearAllChildren()
		end
	end
	for i = 1, #Config.Lanes do
		PlotBuilder.BuildPlaceholder(plot, i)
		local state = (plot:FindFirstChild("LaneState") :: Folder):FindFirstChild("Lane" .. i)
		if state then
			state:SetAttribute("Unlocked", false)
			state:SetAttribute("Level", 0)
			state:SetAttribute("Manager", false)
			state:SetAttribute("Upgraders", 0)
			state:SetAttribute("Running", false)
			state:SetAttribute("CycleStart", 0)
			state:SetAttribute("Revenue", 0)
		end
	end
	plot:SetAttribute("Decor", 0)
end

return PlotBuilder
