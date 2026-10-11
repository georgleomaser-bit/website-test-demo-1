-- =====================================================================
--  CLUTCH CLASH – Bot-Figuren (Server/Bot/BotRig)
--  Besitzer: WP6 (Bots & Training-Range). Vertrag: DESIGN.md B10.2, Muss-Regeln 2/10, C12.5/C12.6.
--  Normales Modul (kein Service), wird nur von BotService per require benutzt.
--
--  Ablauf:
--    * Start(): EINMAL Players:CreateHumanoidModelFromDescriptionAsync(leere HumanoidDescription, R15)
--      in pcall (in eigenem Thread, damit der Server-Start nicht wartet). Klappt das nicht: handgebautes
--      R6-Rig (6 Körperteile + Wurzel, Motor6D mit R6-Namen, Humanoid) – gleitet ohne Animation.
--    * Pool von Config.Bots.PoolSize (12) Klonen in ServerStorage.BotPool. Nie mehr Figuren als der Pool.
--    * Jeder Klon: Skripte entfernt (keine Standard-Animate/Health-Skripte; Animationen spielt der Client,
--      BotAnimator), Zustände Climbing/Swimming/Seated/Flying/Ragdoll/FallingDown/PlatformStanding aus,
--      Gesicht rbxasset://textures/face.png, Kollisionsgruppe "Bots", Standard-Namensanzeige aus,
--      Ausrichtung über AlignOrientation "BotFace" (Bot schaut beim Seitwärtslaufen aufs Ziel).
--
--  Öffentliche API (nur für BotService):
--    BotRig.Start()                    Vorlage + Pool bauen (yieldet nicht, arbeitet im Hintergrund)
--    BotRig.Acquire(rng): Model?       Figur aus dem Pool, frisch eingefärbt (nil = Pool leer)
--    BotRig.Activate(model)            nach dem Parenten: Netzwerk-Besitz Server (pcall)
--    BotRig.Release(model)             zurück in den Pool (alles zurückgesetzt)
--    BotRig.Align(model): AlignOrientation?
--    BotRig.IsR6(model): boolean
--    BotRig.Stats(): { Free: number, Used: number, Kind: string }
-- =====================================================================

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local BotRig = {}

local BOTS: any = Config.Bots
local POOL_SIZE: number = math.clamp(tonumber(BOTS.PoolSize) or 12, 1, 32)
local FACE: string = if type(BOTS.Face) == "string" then BOTS.Face else "rbxasset://textures/face.png"
local COLLISION_GROUP = "Bots"
local ALIGN_NAME = "BotFace"
local ATTACHMENT_NAME = "BotAlign"

-- Muss-Regel B10.2: diese Zustände sind bei Bots aus
local DISABLED_STATES: { Enum.HumanoidStateType } = {
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.Swimming,
	Enum.HumanoidStateType.Seated,
	Enum.HumanoidStateType.Flying,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.PlatformStanding,
}

-- Attribute, die beim Zurücklegen in den Pool gelöscht werden (setzen CombatService/BotService)
local CLEAR_ATTRIBUTES = {
	"CombatantId",
	"Ctx",
	"Team",
	"Alive",
	"Hp",
	"MaxHp",
	"IsBot",
	"Difficulty",
	"BaseSpeed",
	"BotName",
}

local poolFolder: Folder? = nil
local template: Model? = nil
local templateKind = "none" -- "R15" | "R6"
local building = false
local free: { Model } = {}
local used: { [Model]: boolean } = {}
local created = 0

-- ---------------------------------------------------------------------
-- HILFEN
-- ---------------------------------------------------------------------
local function getPoolFolder(): Folder
	local folder = poolFolder
	if folder and folder.Parent then
		return folder
	end
	local existing = ServerStorage:FindFirstChild("BotPool")
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = "BotPool"
		folder.Parent = ServerStorage
	end
	poolFolder = folder
	return folder :: Folder
end

local function palette(): { Color3 }
	local list: { Color3 } = {}
	local colors: any = Config.Colors
	local pal = if type(colors) == "table" then colors.Palette else nil
	if type(pal) == "table" then
		for key, color in pairs(pal) do
			-- "Tip" ist die Orange-Spitze der Blaster – nicht für Kleidung
			if key ~= "Tip" and typeof(color) == "Color3" then
				table.insert(list, color)
			end
		end
	end
	if #list == 0 then
		list = { Color3.fromRGB(244, 235, 221), Color3.fromRGB(154, 209, 212), Color3.fromRGB(247, 183, 200) }
	end
	-- feste Reihenfolge (pairs ist ungeordnet) -> Zufall bleibt reproduzierbar je rng
	table.sort(list, function(a, b)
		return a.R + a.G * 2 + a.B * 3 < b.R + b.G * 2 + b.B * 3
	end)
	return list
end

local PALETTE = palette()

local function newPart(name: string, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanTouch = false
	return part
end

local function motor(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1
	m.Parent = part0
end

-- Handgebautes R6-Rig (Fallback): Kopf, Rumpf, 2 Arme, 2 Beine + unsichtbare Wurzel
local function buildR6(): Model
	local model = Instance.new("Model")
	model.Name = "Bot"
	local skin = Color3.fromRGB(244, 235, 221)
	local root = newPart("HumanoidRootPart", Vector3.new(2, 2, 1), skin)
	root.Transparency = 1
	root.CanCollide = false
	local torso = newPart("Torso", Vector3.new(2, 2, 1), skin)
	local head = newPart("Head", Vector3.new(2, 1, 1), skin)
	local headMesh = Instance.new("SpecialMesh")
	headMesh.MeshType = Enum.MeshType.Head
	headMesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	headMesh.Parent = head
	local leftArm = newPart("Left Arm", Vector3.new(1, 2, 1), skin)
	local rightArm = newPart("Right Arm", Vector3.new(1, 2, 1), skin)
	local leftLeg = newPart("Left Leg", Vector3.new(1, 2, 1), skin)
	local rightLeg = newPart("Right Leg", Vector3.new(1, 2, 1), skin)
	for _, p in { root, torso, head, leftArm, rightArm, leftLeg, rightLeg } do
		p.Parent = model
	end
	-- Standard-R6-Gelenke (Roblox-Werte)
	local rootC = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
	motor("RootJoint", root, torso, rootC, rootC)
	motor(
		"Neck",
		torso,
		head,
		CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
		CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
	)
	motor(
		"Right Shoulder",
		torso,
		rightArm,
		CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
	)
	motor(
		"Left Shoulder",
		torso,
		leftArm,
		CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)
	)
	motor(
		"Right Hip",
		torso,
		rightLeg,
		CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
	)
	motor(
		"Left Hip",
		torso,
		leftLeg,
		CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)
	)
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.Parent = model
	model.PrimaryPart = root
	model:PivotTo(CFrame.new(0, 3, 0))
	return model
end

-- Gemeinsame Vorbereitung der Vorlage (R15 oder R6)
local function prepareTemplate(model: Model, kind: string)
	model.Name = "Bot"
	-- keine Skripte (Animate/Health): Animationen spielt der Client (BotAnimator), HP verwaltet CombatService
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("Accessory") or d:IsA("Clothing") or d:IsA("ShirtGraphic") then
			d:Destroy()
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
		humanoid.MaxHealth = 100
		humanoid.Health = 100
		humanoid.UseJumpPower = false
		humanoid.JumpHeight = 7.2
		humanoid.WalkSpeed = 16
		humanoid.AutoRotate = true
		if humanoid:FindFirstChildOfClass("Animator") == nil then
			Instance.new("Animator").Parent = humanoid
		end
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		model.PrimaryPart = root
		if root:FindFirstChild(ATTACHMENT_NAME) == nil then
			local attachment = Instance.new("Attachment")
			attachment.Name = ATTACHMENT_NAME
			attachment.Parent = root
			local align = Instance.new("AlignOrientation")
			align.Name = ALIGN_NAME
			align.Mode = Enum.OrientationAlignmentMode.OneAttachment
			align.Attachment0 = attachment
			align.MaxTorque = 1e7
			align.Responsiveness = 30
			align.RigidityEnabled = false
			align.Enabled = false
			align.Parent = root
		end
	end
	-- Gesicht (ASSETS.md: rbxasset://textures/face.png)
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local face = head:FindFirstChild("face")
		if not (face and face:IsA("Decal")) then
			if face then
				face:Destroy()
			end
			local decal = Instance.new("Decal")
			decal.Name = "face"
			decal.Face = Enum.NormalId.Front
			decal.Parent = head
			face = decal
		end
		(face :: Decal).Texture = FACE
	end
	model:SetAttribute("RigKind", kind)
end

local function setTemplate(model: Model, kind: string)
	prepareTemplate(model, kind)
	template = model
	templateKind = kind
end

local function ensureTemplate(): Model
	local t = template
	if t then
		return t
	end
	-- Notfall (Pool wird angefragt, bevor die Async-Vorlage fertig ist): R6 sofort bauen
	local r6 = buildR6()
	setTemplate(r6, "R6")
	return r6
end

-- Kollisionsgruppe "Bots" (von ArenaService.Init registriert, C12.6)
local function applyCollisionGroup(model: Model)
	local okRegistered, registered = pcall(function()
		return PhysicsService:IsCollisionGroupRegistered(COLLISION_GROUP)
	end)
	if not (okRegistered and registered) then
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = COLLISION_GROUP
		end
	end
end

local function setStates(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	for _, state in DISABLED_STATES do
		humanoid:SetStateEnabled(state, false)
	end
end

-- Zufällige Farben aus Config.Colors.Palette: Haut (Kopf, Arme, Hände), Oberteil (Rumpf), Hose (Beine)
local function dress(model: Model, rng: Random)
	local count = #PALETTE
	local skin = PALETTE[rng:NextInteger(1, count)]
	local shirt = PALETTE[rng:NextInteger(1, count)]
	local pants = PALETTE[rng:NextInteger(1, count)]
	local tries = 0
	while (shirt == skin or pants == shirt) and tries < 6 do
		shirt = PALETTE[rng:NextInteger(1, count)]
		pants = PALETTE[rng:NextInteger(1, count)]
		tries += 1
	end
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			local name = d.Name
			if name == "Head" or string.find(name, "Arm") or string.find(name, "Hand") then
				d.Color = skin
			elseif string.find(name, "Torso") then
				d.Color = shirt
			elseif string.find(name, "Leg") or string.find(name, "Foot") then
				d.Color = pants
			end
		end
	end
	local bodyColors = model:FindFirstChildOfClass("BodyColors")
	if bodyColors == nil then
		bodyColors = Instance.new("BodyColors")
		bodyColors.Parent = model
	end
	local bc = bodyColors :: BodyColors
	bc.HeadColor3 = skin
	bc.LeftArmColor3 = skin
	bc.RightArmColor3 = skin
	bc.TorsoColor3 = shirt
	bc.LeftLegColor3 = pants
	bc.RightLegColor3 = pants
end

local function resetModel(model: Model)
	for _, name in CLEAR_ATTRIBUTES do
		model:SetAttribute(name, nil)
	end
	CollectionService:RemoveTag(model, "Bot")
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.AssemblyLinearVelocity = Vector3.zero
			d.AssemblyAngularVelocity = Vector3.zero
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 16
		humanoid.AutoRotate = true
		humanoid.Jump = false
		humanoid.Health = humanoid.MaxHealth
	end
	local align = BotRig.Align(model)
	if align then
		align.Enabled = false
	end
end

local function newClone(): Model
	local clone = ensureTemplate():Clone()
	created += 1
	clone:SetAttribute("PoolIndex", created)
	return clone
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICH
-- ---------------------------------------------------------------------
function BotRig.Start()
	if building then
		return
	end
	building = true
	getPoolFolder()
	task.spawn(function()
		-- B10.2: einmal beim Boot, in pcall; Fallback R6
		local ok, result = pcall(function()
			local description = Instance.new("HumanoidDescription")
			return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
		end)
		if ok and typeof(result) == "Instance" and result:IsA("Model") then
			local model = result :: Model
			if model:FindFirstChild("HumanoidRootPart") and model:FindFirstChild("Head") then
				if template == nil then
					setTemplate(model, "R15")
				end
			else
				warn("[BotRig] R15-Vorlage unvollständig – nutze R6-Fallback")
				model:Destroy()
			end
		else
			warn(
				"[BotRig] CreateHumanoidModelFromDescriptionAsync fehlgeschlagen – R6-Fallback: " .. tostring(result)
			)
		end
		ensureTemplate()
		-- Pool auffüllen (höchstens POOL_SIZE Figuren insgesamt)
		local folder = getPoolFolder()
		while created < POOL_SIZE do
			local clone = newClone()
			setStates(clone)
			clone.Parent = folder
			table.insert(free, clone)
		end
	end)
end

function BotRig.Acquire(rng: Random): Model?
	local model: Model? = nil
	while #free > 0 and model == nil do
		local candidate = table.remove(free) :: Model
		if candidate and candidate:FindFirstChild("HumanoidRootPart") and candidate:FindFirstChild("Head") then
			model = candidate
		elseif candidate then
			-- kaputt (z. B. Teil zerstört) -> verwerfen, Platz für einen neuen Klon
			candidate:Destroy()
			created -= 1
		end
	end
	if model == nil and created < POOL_SIZE then
		model = newClone()
	end
	if model == nil then
		return nil
	end
	local m = model :: Model
	used[m] = true
	resetModel(m)
	setStates(m)
	applyCollisionGroup(m)
	dress(m, rng)
	return m
end

function BotRig.Activate(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
	-- Zustände nach dem Parenten erneut setzen (sicher ist sicher)
	setStates(model)
end

function BotRig.Release(model: Model)
	if not used[model] then
		-- nicht aus dem Pool -> einfach weg
		if model.Parent ~= getPoolFolder() then
			model:Destroy()
		end
		return
	end
	used[model] = nil
	if model:FindFirstChild("HumanoidRootPart") == nil or model:FindFirstChild("Head") == nil then
		model:Destroy()
		created -= 1
		return
	end
	resetModel(model)
	model.Parent = getPoolFolder()
	model:PivotTo(CFrame.new(0, 3, 0))
	table.insert(free, model)
end

function BotRig.Align(model: Model): AlignOrientation?
	local root = model:FindFirstChild("HumanoidRootPart")
	local align = if root then root:FindFirstChild(ALIGN_NAME) else nil
	if align and align:IsA("AlignOrientation") then
		return align
	end
	return nil
end

function BotRig.IsR6(model: Model): boolean
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R6
end

function BotRig.Stats(): { Free: number, Used: number, Kind: string }
	local usedCount = 0
	for _ in used do
		usedCount += 1
	end
	return { Free = #free, Used = usedCount, Kind = templateKind }
end

return BotRig
