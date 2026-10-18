--[[
	WorldService (ModuleScript)
	Location: ServerScriptService/Services/WorldService
	Depends on: Shared/Remotes, Shared/Format, Shared/Config/GameConfig, ClickService

	Builds the 3D lobby at runtime if Workspace has no model named "Arena":
	a dark neon plaza with a giant button, a spawn pad, pillars and a sign.
	To use your own map, add a Model named "Arena" (with a SpawnLocation) to
	Workspace and this service leaves it untouched.

	Also publishes server activity every second through ReplicatedStorage/
	ServerState attributes (ServerCPS, ServerPresses, Players), which clients
	use to pulse the giant button so everyone sees each other's presses.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Format)

local WorldService = {
	Name = "WorldService",
	ServerPresses = 0,
}

local ACCENT = GameConfig.Stages[1].Accent
local DARK = Color3.fromRGB(14, 14, 22)
local PANEL = Color3.fromRGB(26, 24, 40)

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in pairs(props) do
		(p :: any)[key] = value
	end
	return p
end

local VERTICAL = CFrame.Angles(0, 0, math.rad(90))

function WorldService:Init(services)
	self.Services = services
end

function WorldService:Start()
	if not workspace:FindFirstChild("Arena") then
		self:_build()
		self:_lighting()
	end
	local state = Remotes.serverState()
	task.spawn(function()
		while true do
			task.wait(1)
			local click = self.Services.ClickService
			local cps = click.ServerClicksThisSecond
			click.ServerClicksThisSecond = 0
			self.ServerPresses += cps
			state:SetAttribute("ServerCPS", cps)
			state:SetAttribute("ServerPresses", self.ServerPresses)
			state:SetAttribute("Players", #Players:GetPlayers())
			if self.StatsLabel then
				self.StatsLabel.Text = `⚡ {cps}/s  ·  {Format.commas(self.ServerPresses)} presses in this server`
			end
		end
	end)
end

function WorldService:_build()
	local arena = Instance.new("Model")
	arena.Name = "Arena"

	part({ Name = "Floor", Size = Vector3.new(220, 2, 220), CFrame = CFrame.new(0, -1, 0), Color = DARK }).Parent = arena
	part({
		Name = "Plaza",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 96, 96),
		CFrame = CFrame.new(0, 0.1, 0) * VERTICAL,
		Color = PANEL,
	}).Parent = arena

	local ring = Instance.new("Model")
	ring.Name = "NeonRing"
	local segments = 72
	local radius = 48
	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		part({
			Name = "Segment",
			Size = Vector3.new(2 * math.pi * radius / segments + 0.1, 0.3, 0.8),
			CFrame = CFrame.new(0, 0.3, 0) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -radius),
			Color = ACCENT,
			Material = Enum.Material.Neon,
			CanCollide = false,
		}).Parent = ring
	end
	ring.Parent = arena

	local button = Instance.new("Model")
	button.Name = "GiantButton"
	part({
		Name = "Pedestal",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(6, 30, 30),
		CFrame = CFrame.new(0, 3, 0) * VERTICAL,
		Color = Color3.fromRGB(32, 30, 50),
		Material = Enum.Material.Metal,
	}).Parent = button
	part({
		Name = "Rim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.7, 31, 31),
		CFrame = CFrame.new(0, 6.1, 0) * VERTICAL,
		Color = ACCENT,
		Material = Enum.Material.Neon,
		CanCollide = false,
	}).Parent = button
	local cap = part({
		Name = "Cap",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3.4, 23, 23),
		CFrame = CFrame.new(0, 7.8, 0) * VERTICAL,
		Color = ACCENT,
		Material = Enum.Material.Neon,
	})
	cap:SetAttribute("BaseY", 7.8)
	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Color = ACCENT
	light.Range = 45
	light.Brightness = 2
	light.Parent = cap
	cap.Parent = button

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ServerStats"
	billboard.Size = UDim2.fromOffset(420, 60)
	billboard.StudsOffset = Vector3.new(0, 9, 0)
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.MaxDistance = 220
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.BuilderSansBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.6
	label.Text = "⚡ 0/s"
	label.Parent = billboard
	billboard.Parent = cap
	self.StatsLabel = label
	button.PrimaryPart = cap
	button.Parent = arena

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = CFrame.lookAt(Vector3.new(0, 0.6, 36), Vector3.new(0, 0.6, 0))
	spawn.Color = PANEL
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = arena

	for i = 1, 10 do
		local angle = (i / 10) * math.pi * 2
		local base = CFrame.new(0, 0, 0) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 16, -78)
		part({ Name = "Pillar", Size = Vector3.new(5, 32, 5), CFrame = base, Color = Color3.fromRGB(22, 22, 34) }).Parent = arena
		part({
			Name = "PillarStrip",
			Size = Vector3.new(1, 30, 0.4),
			CFrame = base * CFrame.new(0, 0, 2.6),
			Color = if i % 2 == 0 then ACCENT else Color3.fromRGB(77, 225, 255),
			Material = Enum.Material.Neon,
			CanCollide = false,
		}).Parent = arena
	end

	local sign = part({
		Name = "Sign",
		Size = Vector3.new(70, 14, 1),
		CFrame = CFrame.lookAt(Vector3.new(0, 30, -92), Vector3.new(0, 30, 0)),
		Color = DARK,
	})
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.LightInfluence = 0
	surface.PixelsPerStud = 20
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 1)
	title.Font = Enum.Font.Michroma
	title.TextScaled = true
	title.Text = string.upper(GameConfig.GameName)
	title.TextColor3 = Color3.new(1, 1, 1)
	local stroke = Instance.new("UIStroke")
	stroke.Color = ACCENT
	stroke.Thickness = 3
	stroke.Parent = title
	title.Parent = surface
	surface.Parent = sign
	sign.Parent = arena

	arena.Parent = workspace
end

function WorldService:_lighting()
	Lighting.ClockTime = 0
	Lighting.Brightness = 1.5
	Lighting.Ambient = Color3.fromRGB(30, 30, 46)
	Lighting.OutdoorAmbient = Color3.fromRGB(40, 36, 60)
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.32
		atmosphere.Offset = 0.2
		atmosphere.Color = Color3.fromRGB(70, 50, 110)
		atmosphere.Decay = Color3.fromRGB(30, 15, 60)
		atmosphere.Glare = 0
		atmosphere.Haze = 1.2
		atmosphere.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("BloomEffect") then
		local bloom = Instance.new("BloomEffect")
		bloom.Intensity = 0.9
		bloom.Size = 28
		bloom.Threshold = 0.95
		bloom.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("ColorCorrectionEffect") then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Contrast = 0.08
		cc.Saturation = 0.12
		cc.TintColor = Color3.fromRGB(240, 235, 255)
		cc.Parent = Lighting
	end
end

return WorldService
