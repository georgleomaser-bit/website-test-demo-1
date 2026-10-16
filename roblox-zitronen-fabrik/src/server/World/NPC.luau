--[[
	NPCs im Roblox-Standard-Look: Manager (Brainrot-Style-Namen) und Zorp der Alien.
	Nutzt den normalen R15-Körper; falls das nicht klappt, ein Klötzchen-Männchen.
]]

local Players = game:GetService("Players")

local Build = require(script.Parent.Build)

local C = Build.C

local NPC = {}

local ANIM_IDLE = "rbxassetid://507766388"
local ANIM_WAVE = "rbxassetid://507770239"
local ANIM_CHEER = "rbxassetid://507770677"

local SKIN = Color3.fromRGB(255, 204, 153)

local function weldTo(head: BasePart, part: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = part
	weld.Parent = part
end

local Hats = {}

function Hats.Lemon(model: Model, head: BasePart)
	local lemon = Build.Egg(model, "HatLemon", Vector3.new(2.2, 1.6, 1.6), head.CFrame * CFrame.new(0, 1.3, 0), C("New Yeller"), Enum.Material.Plastic)
	local leaf = Build.Block(model, "HatLeaf", Vector3.new(0.8, 0.2, 0.5), head.CFrame * CFrame.new(0.3, 2.1, 0) * CFrame.Angles(0, 0, math.rad(25)), C("Bright green"), Enum.Material.Plastic)
	weldTo(head, lemon)
	weldTo(head, leaf)
end

function Hats.Cap(model: Model, head: BasePart)
	local cap = Build.Cylinder(model, "HatCap", 0.7, 1.5, head.CFrame * CFrame.new(0, 0.85, 0), C("Bright red"), Enum.Material.Plastic)
	local brim = Build.Block(model, "HatBrim", Vector3.new(1.3, 0.15, 0.9), head.CFrame * CFrame.new(0, 0.55, -0.85), C("Bright red"), Enum.Material.Plastic)
	weldTo(head, cap)
	weldTo(head, brim)
end

function Hats.Helmet(model: Model, head: BasePart)
	local helmet = Build.Ball(model, "HatHelmet", 1.7, head.CFrame * CFrame.new(0, 0.6, 0), C("New Yeller"), Enum.Material.Plastic)
	local brim = Build.Cylinder(model, "HatBrim", 0.15, 2, head.CFrame * CFrame.new(0, 0.55, 0), C("New Yeller"), Enum.Material.Plastic)
	weldTo(head, helmet)
	weldTo(head, brim)
end

function Hats.Goggles(model: Model, head: BasePart)
	local band = Build.Block(model, "Band", Vector3.new(1.35, 0.3, 1.35), head.CFrame * CFrame.new(0, 0.25, 0), C("Really black"), Enum.Material.Plastic)
	weldTo(head, band)
	for _, x in ipairs({ -0.3, 0.3 }) do
		local lens = Build.CylinderX(model, "Lens", 0.25, 0.5, head.CFrame * CFrame.new(x, 0.25, -0.7) * CFrame.Angles(0, math.rad(90), 0), C("Cyan"), Enum.Material.Neon)
		weldTo(head, lens)
	end
	local hair = Build.Block(model, "Hair", Vector3.new(1.4, 0.5, 1.4), head.CFrame * CFrame.new(0, 0.75, 0.05), C("White"), Enum.Material.Plastic)
	weldTo(head, hair)
end

function Hats.TopHat(model: Model, head: BasePart)
	local hat = Build.Cylinder(model, "HatTop", 1.4, 1.2, head.CFrame * CFrame.new(0, 1.3, 0), C("Really black"), Enum.Material.Plastic)
	local brim = Build.Cylinder(model, "HatBrim", 0.15, 1.9, head.CFrame * CFrame.new(0, 0.65, 0), C("Really black"), Enum.Material.Plastic)
	local band = Build.Cylinder(model, "HatBand", 0.25, 1.25, head.CFrame * CFrame.new(0, 0.85, 0), C("Gold"), Enum.Material.Foil)
	weldTo(head, hat)
	weldTo(head, brim)
	weldTo(head, band)
end

function Hats.Antenna(model: Model, head: BasePart)
	for _, x in ipairs({ -0.35, 0.35 }) do
		local stick = Build.Block(model, "Antenna", Vector3.new(0.12, 1.1, 0.12), head.CFrame * CFrame.new(x, 1.05, 0) * CFrame.Angles(0, 0, math.rad(-x * 40)), C("Lime green"), Enum.Material.Plastic)
		local ball = Build.Ball(model, "AntennaBall", 0.4, head.CFrame * CFrame.new(x * 1.6, 1.65, 0), C("Lime green"), Enum.Material.Neon)
		weldTo(head, stick)
		weldTo(head, ball)
	end
end

function Hats.Alien(model: Model, head: BasePart)
	Hats.Antenna(model, head)
	for _, x in ipairs({ -0.28, 0.28 }) do
		local eye = Build.Egg(model, "AlienEye", Vector3.new(0.45, 0.6, 0.2), head.CFrame * CFrame.new(x, 0.1, -0.62), C("Really black"), Enum.Material.Plastic)
		weldTo(head, eye)
	end
end

local function nameTag(head: BasePart, name: string, title: string?, color: Color3?)
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	gui.Size = UDim2.fromScale(8, 2)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 0.6)
	label.BackgroundTransparency = 1
	label.FontFace = Font.fromEnum(Build.FONT)
	label.Text = name
	label.TextScaled = true
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	if title then
		local sub = Instance.new("TextLabel")
		sub.Size = UDim2.fromScale(1, 0.4)
		sub.Position = UDim2.fromScale(0, 0.6)
		sub.BackgroundTransparency = 1
		sub.FontFace = Font.fromEnum(Build.FONT)
		sub.Text = title
		sub.TextScaled = true
		sub.TextColor3 = Color3.fromRGB(255, 230, 120)
		sub.TextStrokeTransparency = 0
		sub.Parent = gui
	end
end

local function blockyFallback(colors): Model
	local model = Instance.new("Model")
	local function part(name, size, offset, color)
		local p = Build.Block(model, name, size, CFrame.new(offset), color, Enum.Material.Plastic)
		return p
	end
	local torso = part("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), colors.Torso)
	part("Left Arm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 3, 0), colors.Skin)
	part("Right Arm", Vector3.new(1, 2, 1), Vector3.new(1.5, 3, 0), colors.Skin)
	part("Left Leg", Vector3.new(1, 2, 1), Vector3.new(-0.5, 1, 0), colors.Legs)
	part("Right Leg", Vector3.new(1, 2, 1), Vector3.new(0.5, 1, 0), colors.Legs)
	local head = part("Head", Vector3.new(2, 1, 1), Vector3.new(0, 4.5, 0), colors.Skin)
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head
	model.PrimaryPart = torso
	return model
end

-- Erstellt einen NPC. groundCF = Stelle auf dem Boden, Blickrichtung = LookVector
function NPC.Create(parent: Instance, name: string, opts): Model
	opts = opts or {}
	local colors = {
		Skin = opts.Skin or SKIN,
		Torso = opts.Shirt or C("Bright blue"),
		Legs = opts.Pants or C("Dark stone grey"),
	}

	local model: Model? = nil
	local ok, result = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		desc.HeadColor = colors.Skin
		desc.LeftArmColor = colors.Skin
		desc.RightArmColor = colors.Skin
		desc.TorsoColor = colors.Torso
		desc.LeftLegColor = colors.Legs
		desc.RightLegColor = colors.Legs
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if ok and result then
		model = result
	else
		model = blockyFallback(colors)
	end
	local npc = model :: Model
	npc.Name = name

	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart?
	local head = npc:FindFirstChild("Head") :: BasePart?

	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.BreakJointsOnDeath = false
	end
	for _, d in ipairs(npc:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	if root then
		root.Anchored = true
	end

	-- Auf den Boden stellen
	local height = 3
	if humanoid and root then
		height = humanoid.HipHeight + root.Size.Y / 2
	end
	npc:PivotTo((opts.CFrame or CFrame.new()) * CFrame.new(0, height, 0))

	if head and opts.Hat and Hats[opts.Hat] then
		pcall(Hats[opts.Hat], npc, head)
	end
	if head then
		nameTag(head, name, opts.Title, opts.NameColor)
	end

	npc.Parent = parent

	-- Animation (Standard-Roblox-Animationen)
	if humanoid then
		task.spawn(function()
			local animator = humanoid:FindFirstChildOfClass("Animator")
			if not animator then
				animator = Instance.new("Animator")
				animator.Parent = humanoid
			end
			local anim = Instance.new("Animation")
			anim.AnimationId = opts.Animation or ANIM_IDLE
			local okLoad, track = pcall(function()
				return (animator :: Animator):LoadAnimation(anim)
			end)
			if okLoad and track then
				track.Looped = true
				track:Play()
			end
		end)
	end
	return npc
end

-- Kurze Jubel-/Wink-Animation abspielen (Tracks werden wiederverwendet)
local trackCache: { [Instance]: { [string]: AnimationTrack } } = setmetatable({}, { __mode = "k" }) :: any

function NPC.PlayOnce(npc: Model, kind: string)
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local cache = trackCache[animator]
	if not cache then
		cache = {}
		trackCache[animator] = cache
	end
	local track = cache[kind]
	if not track then
		local anim = Instance.new("Animation")
		anim.AnimationId = kind == "wave" and ANIM_WAVE or ANIM_CHEER
		local ok, loaded = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if not ok or not loaded then
			return
		end
		loaded.Priority = Enum.AnimationPriority.Action
		cache[kind] = loaded
		track = loaded
	end
	track:Play()
end

return NPC
