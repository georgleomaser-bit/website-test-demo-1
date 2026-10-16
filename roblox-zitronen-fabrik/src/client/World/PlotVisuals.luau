--[[
	Alles Sichtbare rund um die eigene Fabrik (nur auf dem Client):
	- Kauf-Knöpfe grün (bezahlbar) / rot (zu teuer)
	- gelber Pfeil (Beam) zum nächsten Knopf
	- Anzeige über jedem roten Knopf (Level, Fortschritt, "DRÜCK MICH!")
	- Bau-Animation: neue Teile wachsen aus dem Boden
	- Kanalisation: Tresortür & Schlüssel nur für dich
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local State = require(script.Parent.Parent.State)
local Sound = require(script.Parent.Parent.Sound)

local PlotVisuals = {}

local player = Players.LocalPlayer
local GREEN = BrickColor.new("Lime green").Color
local RED = BrickColor.new("Really red").Color

local watchedPlot: Model? = nil
local connections: { RBXScriptConnection } = {}
local startedAt = os.clock()
local billboards: { [number]: any } = {}
local beam: Beam? = nil
local beamTarget: Attachment? = nil

--------------------------------------------------------------------------
-- Bau-Animation
--------------------------------------------------------------------------
local function animateModel(model: Instance)
	task.wait() -- warten, bis alles repliziert ist
	if not model.Parent then
		return
	end
	local parts = {}
	local minY = math.huge
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			minY = math.min(minY, d.Position.Y)
		end
	end
	if #parts == 0 or #parts > 400 then
		return
	end
	Sound.Play("Whoosh", 0.4, 1, 0.2)
	for _, part in ipairs(parts) do
		local target = part.CFrame
		local transparency = part.Transparency
		local delayTime = math.clamp((target.Position.Y - minY) * 0.025, 0, 0.6)
		part.CFrame = target - Vector3.new(0, 8, 0)
		part.Transparency = 1
		local info = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delayTime)
		TweenService:Create(part, info, { CFrame = target, Transparency = transparency }):Play()
	end
end

local function watchFolder(folder: Instance, recursiveUpgraders: boolean)
	table.insert(connections, folder.ChildAdded:Connect(function(child)
		if os.clock() - startedAt > 3 then
			task.spawn(animateModel, child)
		end
		if recursiveUpgraders then
			local upgraders = child:WaitForChild("Upgraders", 5)
			if upgraders then
				watchFolder(upgraders, false)
			end
		end
	end))
	if recursiveUpgraders then
		for _, lane in ipairs(folder:GetChildren()) do
			local upgraders = lane:FindFirstChild("Upgraders")
			if upgraders then
				watchFolder(upgraders, false)
			end
		end
	end
end

--------------------------------------------------------------------------
-- Anzeige über dem roten Knopf
--------------------------------------------------------------------------
local function makeBillboard(top: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = "LaneInfo"
	gui.Size = UDim2.fromScale(7, 3)
	gui.StudsOffset = Vector3.new(0, 4.2, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.Adornee = top
	gui.Parent = top
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.38)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.SourceSansBold
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0
	title.Parent = gui
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 0.22)
	back.Position = UDim2.fromScale(0, 0.42)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 22)
	back.BorderSizePixel = 0
	back.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.4, 0)
	corner.Parent = back
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(110, 255, 110)
	fill.BorderSizePixel = 0
	fill.Parent = back
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.4, 0)
	fillCorner.Parent = fill
	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.fromScale(1, 0.32)
	hint.Position = UDim2.fromScale(0, 0.68)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.SourceSansBold
	hint.TextScaled = true
	hint.TextColor3 = Color3.fromRGB(255, 230, 90)
	hint.TextStrokeTransparency = 0
	hint.Parent = gui
	return { Gui = gui, Title = title, Fill = fill, Hint = hint }
end

local function updateBillboards(plot: Model)
	local data = State.Data
	local lanes = plot:FindFirstChild("Lanes")
	local states = plot:FindFirstChild("LaneState")
	if not data or not lanes or not states then
		return
	end
	local now = workspace:GetServerTimeNow()
	for i, laneCfg in ipairs(Config.Lanes) do
		local lane = lanes:FindFirstChild("Lane" .. i)
		local panel = lane and lane:FindFirstChild("Panel")
		local top = panel and panel:FindFirstChild("Top") :: BasePart?
		local entry = billboards[i]
		if entry and (not top or entry.Gui.Parent ~= top) then
			entry.Gui:Destroy()
			billboards[i] = nil
			entry = nil
		end
		if top then
			if not entry then
				entry = makeBillboard(top)
				billboards[i] = entry
			end
			local state = states:FindFirstChild("Lane" .. i)
			local level = state and state:GetAttribute("Level") or 0
			local manager = state and state:GetAttribute("Manager")
			local running = state and state:GetAttribute("Running")
			local cycle = state and state:GetAttribute("CycleTime") or 1
			local start = state and state:GetAttribute("CycleStart") or now
			local revenue = state and state:GetAttribute("Revenue") or 0
			entry.Title.Text = laneCfg.Emoji .. " Lv " .. Format.Int(level) .. "  ·  " .. Format.Cash(revenue)
			local progress = 0
			if running and cycle > 0 then
				progress = manager and (((now - start) % cycle) / cycle) or math.clamp((now - start) / cycle, 0, 1)
				if manager and cycle < 0.3 then
					progress = 1
				end
			end
			entry.Fill.Size = UDim2.fromScale(progress, 1)
			if manager then
				entry.Hint.Text = "🤖 läuft automatisch"
				entry.Hint.TextColor3 = Color3.fromRGB(150, 220, 255)
			elseif running then
				entry.Hint.Text = "presst… " .. Format.Cycle(math.max(0, start + cycle - now))
				entry.Hint.TextColor3 = Color3.fromRGB(255, 255, 255)
			else
				entry.Hint.Text = (math.floor(os.clock() * 3) % 2 == 0) and "🔴 DRÜCK MICH! 🔴" or "🔴 DRÜCK MICH!"
				entry.Hint.TextColor3 = Color3.fromRGB(255, 230, 90)
			end
		end
	end
end

--------------------------------------------------------------------------
-- Knöpfe einfärben + Pfeil
--------------------------------------------------------------------------
local function updatePads(plot: Model)
	local buttons = plot:FindFirstChild("Buttons")
	if not buttons then
		return nil
	end
	local cash = State.Cash()
	local best: BasePart? = nil
	local bestCost = math.huge
	for _, pad in ipairs(buttons:GetChildren()) do
		local part = pad:FindFirstChild("Pad") :: BasePart?
		local cost = pad:GetAttribute("Cost")
		if part and type(cost) == "number" then
			local affordable = cash >= cost
			part.Color = affordable and GREEN or RED
			local label = part:FindFirstChild("Label")
			local price = label and label:FindFirstChild("Price") :: TextLabel?
			if price then
				price.TextColor3 = affordable and Color3.fromRGB(120, 255, 120) or Color3.fromRGB(255, 110, 110)
			end
			if cost < bestCost then
				bestCost = cost
				best = part
			end
		end
	end
	return best, best and cash >= bestCost
end

local function updateBeam(target: BasePart?, affordable: boolean?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or not target or not State.Setting("Guide") or (root.Position - target.Position).Magnitude < 8 then
		if beam then
			beam.Enabled = false
		end
		return
	end
	local fromAttachment = root:FindFirstChild("GuideFrom") :: Attachment?
	if not fromAttachment then
		local a = Instance.new("Attachment")
		a.Name = "GuideFrom"
		a.Position = Vector3.new(0, -2.5, 0)
		a.Parent = root
		fromAttachment = a
	end
	local toAttachment = target:FindFirstChild("GuideTo") :: Attachment?
	if not toAttachment then
		local a = Instance.new("Attachment")
		a.Name = "GuideTo"
		a.Position = Vector3.new(0, 0.5, 0)
		a.Parent = target
		toAttachment = a
	end
	if not beam or not beam.Parent then
		local b = Instance.new("Beam")
		b.Name = "GuideBeam"
		b.Width0 = 0.6
		b.Width1 = 0.6
		b.FaceCamera = true
		b.LightEmission = 0.6
		b.Segments = 12
		b.CurveSize0 = 0
		b.CurveSize1 = 0
		b.Parent = workspace:FindFirstChild("ClientConveyorItems") or workspace
		beam = b
	end
	local b = beam :: Beam
	b.Attachment0 = fromAttachment
	b.Attachment1 = toAttachment
	b.Color = ColorSequence.new(affordable and Color3.fromRGB(255, 220, 40) or Color3.fromRGB(255, 255, 255))
	b.Transparency = NumberSequence.new(affordable and 0.15 or 0.55)
	b.Enabled = true
	beamTarget = toAttachment
end

--------------------------------------------------------------------------
-- Eigene Fabrik beobachten
--------------------------------------------------------------------------
local function watchPlot(plot: Model?)
	if watchedPlot == plot then
		return
	end
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	table.clear(connections)
	for _, entry in pairs(billboards) do
		entry.Gui:Destroy()
	end
	table.clear(billboards)
	watchedPlot = plot
	if not plot then
		return
	end
	for _, name in ipairs({ "Decor", "Buttons" }) do
		local folder = plot:FindFirstChild(name)
		if folder then
			watchFolder(folder, false)
		end
	end
	local lanes = plot:FindFirstChild("Lanes")
	if lanes then
		watchFolder(lanes, true)
	end
end

-- Knopf-Druck-Animation
function PlotVisuals.PressAnimation(laneIndex: number)
	local plot = State.Plot()
	local lanes = plot and plot:FindFirstChild("Lanes")
	local lane = lanes and lanes:FindFirstChild("Lane" .. laneIndex)
	local panel = lane and lane:FindFirstChild("Panel")
	local button = panel and panel:FindFirstChild("PressButton") :: BasePart?
	if not button then
		return
	end
	local original = button:GetAttribute("OriginalCFrame") :: CFrame?
	if not original then
		original = button.CFrame
		button:SetAttribute("OriginalCFrame", original)
	end
	local base = original :: CFrame
	button.CFrame = base - Vector3.new(0, 0.3, 0)
	TweenService:Create(button, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = base }):Play()
end

-- Tresor in der Kanalisation für diesen Spieler öffnen
function PlotVisuals.OpenVault()
	local world = workspace:FindFirstChild("World")
	local sewer = world and world:FindFirstChild("Sewer")
	local door = sewer and sewer:FindFirstChild("VaultDoor") :: BasePart?
	if door then
		TweenService:Create(door, TweenInfo.new(1.2, Enum.EasingStyle.Quad), { CFrame = door.CFrame + Vector3.new(0, -11.5, 0) }):Play()
		task.delay(1.2, function()
			door.CanCollide = false
			door.Transparency = 1
		end)
	end
end

-- Schlüssel ausblenden, wenn man ihn schon hat
local function updateKey()
	local data = State.Data
	if not data then
		return
	end
	local secrets = data.Profile.Secrets
	local world = workspace:FindFirstChild("World")
	local sewer = world and world:FindFirstChild("Sewer")
	local vault = sewer and sewer:FindFirstChild("Vault")
	if not vault then
		return
	end
	local hide = secrets.UfoKey or secrets.UfoKeyDelivered
	for _, name in ipairs({ "UfoKey", "KeyRing" }) do
		local part = vault:FindFirstChild(name) :: BasePart?
		if part then
			part.Transparency = hide and 1 or 0
			for _, d in ipairs(part:GetDescendants()) do
				if d:IsA("ProximityPrompt") then
					d.Enabled = not hide
				elseif d:IsA("ParticleEmitter") or d:IsA("PointLight") then
					d.Enabled = not hide
				end
			end
		end
	end
end

function PlotVisuals.Start()
	startedAt = os.clock()
	State.Changed.Event:Connect(updateKey)
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		local plot = State.Plot()
		watchPlot(plot)
		if not plot then
			if beam then
				beam.Enabled = false
			end
			return
		end
		updateBillboards(plot)
		acc += dt
		if acc >= 0.2 then
			acc = 0
			local target, affordable = updatePads(plot)
			updateBeam(target, affordable)
		end
	end)
end

PlotVisuals.BeamTarget = function()
	return beamTarget
end

return PlotVisuals
