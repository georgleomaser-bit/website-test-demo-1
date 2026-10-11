-- =====================================================================
--  CLUTCH CLASH – Bot-Animationen (Client/Modules/BotAnimator)
--  Besitzer: WP6 (Bots & Training-Range). Vertrag: DESIGN.md B10.3 ("Animationen"), Muss-Regel 2.
--  Spielt auf allen Modellen mit Tag "Bot" LOKAL die Roblox-Standard-Animationen (idle 507766388,
--  walk 507777826, run 507767714, jump 507765000, fall 507767968) + toolnone 507768375 als Halte-Pose
--  für die Waffe. Keine eigenen Animationen. Der Server besitzt die Bots (Netzwerk) -> die Tracks
--  laufen nur auf diesem Client. R6-Fallback-Rigs gleiten ohne Animation (R15-IDs passen nicht).
--  Nur bis Config.Bots.AnimateDistance (260 Studs) zur Kamera, 10 Hz Zustandswahl, ein Heartbeat.
--
--  Öffentliche API (Modul-Form C7.1):
--    BotAnimator.Init(ctx)   BotAnimator.Start()
--    BotAnimator.Count(): number      animierte Bots gerade (Debug)
-- =====================================================================

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BotAnimator = {}

local TAG = "Bot"
local TICK = 0.1 -- 10 Hz
local FADE = 0.15
local IDLE_SPEED = 0.6 -- Studs/s darunter = stehen
local RUN_SPEED = 18 -- Studs/s darüber = rennen
local WALK_BASE = 16 -- Walk-Animation ist für 16 Studs/s gemacht
local RUN_BASE = 22
local MAX_BOTS = 32 -- Schutz (Server hat höchstens 12)

type BotAnim = {
	Model: Model,
	Humanoid: Humanoid?,
	Root: BasePart?,
	Animator: Animator?,
	Tracks: { [string]: AnimationTrack },
	Current: string?,
	Hold: AnimationTrack?,
	Active: boolean,
	Skip: boolean, -- R6-Fallback: nie animieren
	Conn: RBXScriptConnection?,
}

local ctx: any = nil
local config: any = nil
local animations: { [string]: Animation } = {}
local bots: { [Model]: BotAnim } = {}
local botCount = 0
local accumulator = 0
local heartbeat: RBXScriptConnection? = nil
local maxDistance = 260

-- ---------------------------------------------------------------------
-- HILFEN
-- ---------------------------------------------------------------------
local function animationFor(name: string): Animation?
	local existing = animations[name]
	if existing then
		return existing
	end
	local ids: any = config and config.Bots and config.Bots.Animations
	local id = if type(ids) == "table" then ids[name] else nil
	if type(id) ~= "string" or id == "" then
		return nil
	end
	local anim = Instance.new("Animation")
	anim.Name = "Bot" .. name
	anim.AnimationId = id
	animations[name] = anim
	return anim
end

local function stopAll(b: BotAnim)
	for _, track in b.Tracks do
		if track.IsPlaying then
			track:Stop(FADE)
		end
	end
	b.Current = nil
	b.Active = false
end

local function destroyTracks(b: BotAnim)
	for _, track in b.Tracks do
		pcall(function()
			track:Stop(0)
			track:Destroy()
		end)
	end
	table.clear(b.Tracks)
	b.Hold = nil
	b.Current = nil
	b.Active = false
end

-- Humanoid/Animator/Wurzel nachschlagen (Modelle replizieren evtl. stückweise)
local function resolve(b: BotAnim): boolean
	local model = b.Model
	if b.Humanoid == nil or b.Humanoid.Parent ~= model then
		b.Humanoid = model:FindFirstChildOfClass("Humanoid")
		b.Animator = nil
		destroyTracks(b)
	end
	local humanoid = b.Humanoid
	if humanoid == nil then
		return false
	end
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		b.Skip = true
		return false
	end
	if b.Root == nil or b.Root.Parent ~= model then
		local root = model:FindFirstChild("HumanoidRootPart")
		b.Root = if root and root:IsA("BasePart") then root else nil
	end
	if b.Animator == nil or b.Animator.Parent ~= humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator == nil then
			-- lokal angelegt: spielt nur auf diesem Client (gewollt)
			local created = Instance.new("Animator")
			created.Parent = humanoid
			animator = created
		end
		b.Animator = animator
		destroyTracks(b)
	end
	return b.Root ~= nil and b.Animator ~= nil
end

local function loadTrack(b: BotAnim, name: string, looped: boolean, priority: Enum.AnimationPriority): AnimationTrack?
	local existing = b.Tracks[name]
	if existing then
		return existing
	end
	local animator = b.Animator
	local anim = animationFor(name)
	if animator == nil or anim == nil then
		return nil
	end
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if not ok or track == nil then
		return nil
	end
	track.Looped = looped
	track.Priority = priority
	b.Tracks[name] = track
	return track
end

local function play(b: BotAnim, name: string, speed: number)
	local looped = name ~= "Jump"
	local track = loadTrack(b, name, looped, Enum.AnimationPriority.Core)
	if track == nil then
		return
	end
	if b.Current ~= name then
		local old = if b.Current then b.Tracks[b.Current] else nil
		if old and old.IsPlaying then
			old:Stop(FADE)
		end
		track:Play(FADE)
		b.Current = name
	elseif not track.IsPlaying and looped then
		track:Play(FADE)
	end
	track:AdjustSpeed(speed)
end

local function chooseState(humanoid: Humanoid, root: BasePart): (string, number)
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Jumping then
		return "Jump", 1
	end
	if state == Enum.HumanoidStateType.Freefall then
		return "Fall", 1
	end
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	if speed < IDLE_SPEED then
		return "Idle", 1
	end
	if speed < RUN_SPEED then
		return "Walk", math.clamp(speed / WALK_BASE, 0.4, 1.6)
	end
	return "Run", math.clamp(speed / RUN_BASE, 0.6, 1.8)
end

-- ---------------------------------------------------------------------
-- VERWALTUNG
-- ---------------------------------------------------------------------
local function remove(model: Model)
	local b = bots[model]
	if b == nil then
		return
	end
	bots[model] = nil
	botCount -= 1
	if b.Conn then
		b.Conn:Disconnect()
	end
	destroyTracks(b)
end

local function add(instance: Instance)
	if not instance:IsA("Model") or bots[instance] or botCount >= MAX_BOTS then
		return
	end
	local model = instance :: Model
	local b: BotAnim = {
		Model = model,
		Humanoid = nil,
		Root = nil,
		Animator = nil,
		Tracks = {},
		Current = nil,
		Hold = nil,
		Active = false,
		Skip = false,
		Conn = nil,
	}
	b.Conn = model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			remove(model)
		end
	end)
	bots[model] = b
	botCount += 1
end

local function update(b: BotAnim, camPos: Vector3)
	if b.Skip then
		return
	end
	local model = b.Model
	if not model:IsDescendantOf(workspace) then
		if b.Active then
			stopAll(b)
		end
		return
	end
	if not resolve(b) then
		return
	end
	local humanoid = b.Humanoid :: Humanoid
	local root = b.Root :: BasePart
	local alive = model:GetAttribute("Alive") ~= false
	local near = (root.Position - camPos).Magnitude <= maxDistance
	if not alive or not near then
		if b.Active then
			stopAll(b)
		end
		return
	end
	b.Active = true
	-- Halte-Pose für die Waffe (toolnone), über den Lauf-Animationen
	local hold = b.Hold or loadTrack(b, "ToolNone", true, Enum.AnimationPriority.Action)
	b.Hold = hold
	if hold and not hold.IsPlaying then
		hold:Play(FADE)
	end
	local name, speed = chooseState(humanoid, root)
	play(b, name, speed)
end

local function step(dt: number)
	accumulator += dt
	if accumulator < TICK then
		return
	end
	accumulator = 0
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local camPos = camera.CFrame.Position
	for _, b in bots do
		local ok, err = pcall(update, b, camPos)
		if not ok then
			-- kaputter Bot (z. B. halb repliziert): nächstes Mal neu auflösen
			b.Humanoid = nil
			warn("[BotAnimator] " .. tostring(err))
		end
	end
end

-- ---------------------------------------------------------------------
-- MODUL-FORM (C7.1)
-- ---------------------------------------------------------------------
function BotAnimator.Init(context: any)
	ctx = context
	config = if type(ctx) == "table" and ctx.Config then ctx.Config else nil
	if config == nil then
		local ok, result = pcall(function()
			return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")) :: any
		end)
		if ok then
			config = result
		end
	end
	local distance = config and config.Bots and config.Bots.AnimateDistance
	if type(distance) == "number" and distance > 0 then
		maxDistance = distance
	end
end

function BotAnimator.Start()
	if heartbeat then
		return
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance: Instance)
		if instance:IsA("Model") then
			remove(instance)
		end
	end)
	for _, instance in CollectionService:GetTagged(TAG) do
		add(instance)
	end
	heartbeat = RunService.Heartbeat:Connect(step)
end

function BotAnimator.Count(): number
	local n = 0
	for _, b in bots do
		if b.Active then
			n += 1
		end
	end
	return n
end

return BotAnimator
