--[[
	ObbyService (ModuleScript)
	Location: ServerScriptService/Services/ObbyService
	Depends on: Shared/Config/{Obby, GameConfig}, Shared/Format, Core/Net,
	            DataService, StatsService, EconomyService, SyncService,
	            SecurityService, Net

	A 15-stage obstacle course next to the plaza (east of it, rising into the
	sky). Players run it while their auto-presses and passive income keep
	earning in the background.

	Built at runtime unless Workspace already contains a model named "Obby"
	with Start, Checkpoint1..N-1 and Finish parts (then it is only wired up).

	Server-authoritative progress:
	  * The server samples every character's position (Obby.AntiCheat.SampleInterval)
	    instead of trusting any client message.
	  * Checkpoints only count in order, while alive, and only if the segment
	    took a plausible amount of time (distance / MaxTravelSpeed).
	  * A jump of more than TeleportDistance between two samples that the
	    server did not cause is flagged and freezes progress for a few seconds.
	  * Kill bricks and falling into the void send you back to your checkpoint.
	  * Rewards are paid here only; the client can merely ask to be moved to
	    its own saved checkpoint or back to the plaza (Action "ObbyTeleport").
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ObbyConfig = require(Shared.Config.Obby)
local Format = require(Shared.Format)
local Core = script.Parent.Parent.Core
local Net = require(Core.Net)
local Guard = require(Core.Guard)

local AC = ObbyConfig.AntiCheat
local REWARDS = ObbyConfig.Rewards
local COUNT = ObbyConfig.StageCount

local ObbyService = { Name = "ObbyService" }

local NEON_CYAN = Color3.fromRGB(77, 225, 255)
local NEON_RED = Color3.fromRGB(255, 55, 85)
local GOLD = Color3.fromRGB(255, 205, 64)
local PLAZA_SPAWN = CFrame.lookAt(Vector3.new(0, 4, 36), Vector3.new(0, 4, 0))
-- The root part is ~3 studs above the feet, so kill volumes reach a bit higher than they look.
local KILL_MARGIN = Vector3.new(1, 3.3, 1)
-- After the server moves a character, the owning client can still report old
-- positions for a moment; those are not treated as teleports or deaths.
local SERVER_MOVE_GRACE = 1

-- Course building -------------------------------------------------------------------------------

local function part(props: { [string]: any }): BasePart
	local className = props.ClassName or "Part"
	local p = Instance.new(className) :: BasePart
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in pairs(props) do
		if key ~= "ClassName" and key ~= "Parent" then
			(p :: any)[key] = value
		end
	end
	p.Parent = props.Parent
	return p
end

local function label(parent: BasePart, text: string, height: number, color: Color3?)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(260, 46)
	gui.StudsOffset = Vector3.new(0, height, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	local text_ = Instance.new("TextLabel")
	text_.BackgroundTransparency = 1
	text_.Size = UDim2.fromScale(1, 1)
	text_.Font = Enum.Font.BuilderSansBold
	text_.TextScaled = true
	text_.TextColor3 = color or Color3.new(1, 1, 1)
	text_.TextStrokeTransparency = 0.5
	text_.Text = text
	text_.Parent = gui
	gui.Parent = parent
end

--[[
	A cursor walks along +X: x is the far edge of the last thing placed, y the
	height of its top surface. Builders place obstacles and advance it.
]]
local Builder = {}
Builder.__index = Builder

function Builder.new(model: Model, startX: number, topY: number)
	local self = setmetatable({}, Builder)
	self.Model = model
	self.X = startX
	self.Y = topY
	self.Stage = 1
	self.Kill = {} :: { BasePart }
	self.Pads = {} :: { BasePart }
	self.Movers = {} :: { any }
	self.MinY = topY
	self.MaxY = topY
	return self
end

function Builder:color(): Color3
	return Color3.fromHSV((0.9 + self.Stage * 0.045) % 1, 0.55, 0.5)
end

function Builder:gap(distance: number)
	self.X += distance
end

function Builder:platform(length: number, rise: number?, width: number?, z: number?): BasePart
	self.Y += rise or 0
	self.MinY = math.min(self.MinY, self.Y)
	self.MaxY = math.max(self.MaxY, self.Y)
	local p = part({
		Name = "Platform",
		Size = Vector3.new(length, 1, width or 6),
		CFrame = CFrame.new(self.X + length / 2, self.Y - 0.5, z or 0),
		Color = self:color(),
		Parent = self.Model,
	})
	self.X += length
	return p
end

-- A neon strip lying on the surface just walked (offset measured back from the cursor).
function Builder:killStrip(fromX: number, length: number, width: number)
	local p = part({
		Name = "Kill",
		Size = Vector3.new(length, 0.6, width),
		CFrame = CFrame.new(fromX + length / 2, self.Y + 0.25, 0),
		Color = NEON_RED,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = self.Model,
	})
	table.insert(self.Kill, p)
	return p
end

-- Kill floor below a gap (visible lava).
function Builder:lava(fromX: number, length: number, width: number, depth: number)
	local p = part({
		Name = "Kill",
		Size = Vector3.new(length, 1, width),
		CFrame = CFrame.new(fromX + length / 2, self.Y - depth, 0),
		Color = NEON_RED,
		Material = Enum.Material.Neon,
		Parent = self.Model,
	})
	table.insert(self.Kill, p)
	return p
end

--[[
	A platform sliding between two points with a PrismaticConstraint servo, so
	Roblox physics carries players standing on it.
]]
function Builder:mover(size: Vector3, from: Vector3, travel: Vector3, period: number)
	local distance = travel.Magnitude
	local axis = travel.Unit
	local up = if math.abs(axis.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
	-- The constraint slides along the attachments' primary (X) axis.
	local frame = CFrame.fromMatrix(Vector3.zero, axis, (up - axis * up:Dot(axis)).Unit)
	local base = part({
		Name = "MoverBase",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(from),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Parent = self.Model,
	})
	local platform = part({
		Name = "Mover",
		Size = size,
		CFrame = CFrame.new(from),
		Color = NEON_CYAN,
		Material = Enum.Material.Neon,
		Anchored = false,
		Parent = self.Model,
	})
	local a0 = Instance.new("Attachment")
	a0.CFrame = frame
	a0.Parent = base
	local a1 = Instance.new("Attachment")
	a1.CFrame = frame
	a1.Parent = platform
	local prism = Instance.new("PrismaticConstraint")
	prism.Attachment0 = a0
	prism.Attachment1 = a1
	prism.ActuatorType = Enum.ActuatorType.Servo
	prism.ServoMaxForce = 1e8
	prism.Speed = distance / (period / 2)
	prism.LimitsEnabled = true
	prism.LowerLimit = 0
	prism.UpperLimit = distance
	prism.TargetPosition = 0
	prism.Parent = platform
	table.insert(self.Movers, { Constraint = prism, Distance = distance, Period = period, Part = platform })
	return platform
end

-- A bar spinning around a post (HingeConstraint motor). Touching the bar sends you back.
function Builder:spinner(center: Vector3, length: number, speed: number)
	part({
		Name = "SpinnerPost",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3, 2, 2),
		CFrame = CFrame.new(center + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(40, 36, 60),
		Parent = self.Model,
	})
	local hub = part({
		Name = "SpinnerHub",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(center + Vector3.new(0, 1.6, 0)),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Parent = self.Model,
	})
	local bar = part({
		Name = "Kill",
		Size = Vector3.new(length, 0.8, 0.8),
		CFrame = CFrame.new(center + Vector3.new(0, 1.6, 0)),
		Color = NEON_RED,
		Material = Enum.Material.Neon,
		Anchored = false,
		CanCollide = false,
		Parent = self.Model,
	})
	local vertical = CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, Vector3.xAxis)
	local a0 = Instance.new("Attachment")
	a0.CFrame = vertical
	a0.Parent = hub
	local a1 = Instance.new("Attachment")
	a1.CFrame = vertical
	a1.Parent = bar
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = a0
	hinge.Attachment1 = a1
	hinge.ActuatorType = Enum.ActuatorType.Motor
	hinge.AngularVelocity = speed
	hinge.MotorMaxTorque = 1e9
	hinge.MotorMaxAcceleration = 1e4
	hinge.Parent = bar
	table.insert(self.Kill, bar)
	table.insert(self.Movers, { Part = bar })
	return bar
end

function Builder:truss(height: number)
	local t = part({
		ClassName = "TrussPart",
		Name = "Truss",
		Size = Vector3.new(2, height, 2),
		CFrame = CFrame.new(self.X + 1, self.Y + height / 2, 0),
		Color = NEON_CYAN,
		Parent = self.Model,
	})
	self.X += 2
	self.Y += height
	self.MaxY = math.max(self.MaxY, self.Y)
	return t
end

-- Ends the current stage with a checkpoint (or the finish) pad.
function Builder:pad()
	self:gap(3)
	local finish = self.Stage == COUNT
	local size = if finish then 14 else 10
	local p = part({
		Name = if finish then "Finish" else "Checkpoint" .. self.Stage,
		Size = Vector3.new(size, 1, size),
		CFrame = CFrame.new(self.X + size / 2, self.Y - 0.5, 0),
		Color = if finish then GOLD else NEON_CYAN,
		Material = Enum.Material.Neon,
		Parent = self.Model,
	})
	p:SetAttribute("Stage", self.Stage)
	label(p, if finish then "🏆 FINISH" else `Stage {self.Stage} ✔ {ObbyConfig.StageNames[self.Stage + 1] or ""}`, 5, if finish then GOLD else nil)
	self.Pads[self.Stage] = p
	self.X += size
	self.Stage += 1
	return p
end

-- The 15 stages. Gaps stay jumpable with the default character (≤ 8 studs flat).
local STAGES = {
	function(b) -- First Steps
		for _ = 1, 4 do
			b:gap(4)
			b:platform(6)
		end
	end,
	function(b) -- Stairway
		for _ = 1, 5 do
			b:gap(3)
			b:platform(5, 2.5)
		end
	end,
	function(b) -- Hot Floor
		b:gap(3)
		local start = b.X
		b:platform(32)
		for _, offset in ipairs({ 7, 15, 23 }) do
			b:killStrip(start + offset, 2.5, 6)
		end
	end,
	function(b) -- Tightrope
		b:gap(3)
		b:platform(22, 0, 1.6)
		b:gap(3)
		b:platform(4)
		b:gap(3)
		b:platform(18, 0, 1.6)
	end,
	function(b) -- Ferry
		b:gap(3)
		b:platform(4)
		local gapStart = b.X
		b:gap(26)
		b:mover(Vector3.new(6, 1, 6), Vector3.new(gapStart + 3.5, b.Y - 0.5, 0), Vector3.new(19, 0, 0), 8)
		b:platform(4)
	end,
	function(b) -- Spinner
		b:gap(3)
		local start = b.X
		b:platform(16, 0, 16)
		b:spinner(Vector3.new(start + 8, b.Y, 0), 14, 1.4)
	end,
	function(b) -- Zigzag
		for i = 1, 5 do
			b:gap(3)
			b:platform(4, 1, 4, if i % 2 == 0 then 5 else -5)
		end
	end,
	function(b) -- Ladder
		b:gap(2)
		b:platform(6)
		b:truss(16)
		b:platform(8)
	end,
	function(b) -- Elevators
		b:gap(3)
		b:platform(4)
		b:gap(1)
		b:mover(Vector3.new(6, 1, 6), Vector3.new(b.X + 3, b.Y - 0.5, 0), Vector3.new(0, 10, 0), 7)
		b:gap(7)
		b:platform(4, 10)
		b:gap(1)
		b:mover(Vector3.new(6, 1, 6), Vector3.new(b.X + 3, b.Y - 0.5, 0), Vector3.new(0, 8, 0), 6)
		b:gap(7)
		b:platform(4, 8)
	end,
	function(b) -- Islands
		for _ = 1, 6 do
			b:gap(5)
			b:platform(3.5, 0.5, 3.5)
		end
	end,
	function(b) -- Double Spin
		b:gap(3)
		local start = b.X
		b:platform(30, 0, 12)
		b:spinner(Vector3.new(start + 9, b.Y, 0), 11, 1.6)
		b:spinner(Vector3.new(start + 21, b.Y, 0), 11, -1.9)
	end,
	function(b) -- Leap of Faith
		for _ = 1, 3 do
			b:gap(8)
			b:platform(6, -1)
		end
	end,
	function(b) -- Needle
		for _ = 1, 4 do
			b:gap(2.5)
			b:platform(10, 1, 1.4)
		end
	end,
	function(b) -- Lava Ferry
		b:gap(3)
		b:platform(4)
		local gapStart = b.X
		b:gap(24)
		b:lava(gapStart, 24, 14, 4)
		b:mover(Vector3.new(6, 1, 6), Vector3.new(gapStart + 3.5, b.Y - 0.5, 0), Vector3.new(17, 0, 0), 7)
		b:platform(4)
	end,
	function(b) -- Summit
		for _ = 1, 6 do
			b:gap(3)
			b:platform(4, 3, 4)
		end
	end,
}
assert(#STAGES == COUNT, "Obby.StageCount must match the number of stage builders")

function ObbyService:_build()
	local model = Instance.new("Model")
	model.Name = "Obby"

	-- Bridge from the plaza edge and the start pad (level with the plaza floor).
	part({ Name = "Bridge", Size = Vector3.new(10, 1, 6), CFrame = CFrame.new(113, -0.5, 0), Color = Color3.fromRGB(26, 24, 40), Parent = model })
	local start = part({
		Name = "Start",
		Size = Vector3.new(12, 1, 12),
		CFrame = CFrame.new(124, -0.5, 0),
		Color = Color3.fromRGB(26, 24, 40),
		Parent = model,
	})
	for _, z in ipairs({ -6.5, 6.5 }) do
		part({
			Name = "Gate",
			Size = Vector3.new(1, 12, 1),
			CFrame = CFrame.new(118, 6, z),
			Color = NEON_CYAN,
			Material = Enum.Material.Neon,
			Parent = model,
		})
	end
	part({ Name = "GateTop", Size = Vector3.new(1, 1, 14), CFrame = CFrame.new(118, 12.5, 0), Color = NEON_CYAN, Material = Enum.Material.Neon, Parent = model })
	label(start, `🏃 OBBY · {COUNT} stages · rewards every checkpoint`, 9, NEON_CYAN)

	local b = Builder.new(model, 130, 0)
	for _, build in ipairs(STAGES) do
		build(b)
		b:pad()
	end

	self.Model = model
	self.Start = start
	self.Pads = b.Pads
	self.Kill = b.Kill
	self.Movers = b.Movers
	self.Bounds = {
		Min = Vector3.new(100, b.MinY - 60, -40),
		Max = Vector3.new(b.X + 20, b.MaxY + 60, 40),
	}
	model.Parent = workspace

	for _, mover in ipairs(b.Movers) do
		pcall(function()
			mover.Part:SetNetworkOwner(nil)
		end)
	end
end

-- Wires up an existing Workspace.Obby built by hand in Studio.
function ObbyService:_adopt(model: Model)
	self.Model = model
	self.Start = model:FindFirstChild("Start") :: BasePart
	self.Pads = {}
	for stage = 1, COUNT - 1 do
		self.Pads[stage] = model:FindFirstChild("Checkpoint" .. stage) :: BasePart
	end
	self.Pads[COUNT] = model:FindFirstChild("Finish") :: BasePart
	self.Kill = {}
	self.Movers = {}
	local minY, maxY, minX, maxX = math.huge, -math.huge, math.huge, -math.huge
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "Kill" then
				table.insert(self.Kill, d)
			end
			minY = math.min(minY, d.Position.Y)
			maxY = math.max(maxY, d.Position.Y)
			minX = math.min(minX, d.Position.X)
			maxX = math.max(maxX, d.Position.X)
		end
	end
	self.Bounds = { Min = Vector3.new(minX - 20, minY - 60, -200), Max = Vector3.new(maxX + 20, maxY + 60, 200) }
	assert(self.Start and self.Pads[COUNT], "Workspace.Obby needs parts named Start, Checkpoint1.. and Finish")
end

-- Movers swing between their end points.
function ObbyService:_runMovers()
	for _, mover in ipairs(self.Movers) do
		local prism = mover.Constraint
		if prism then
			task.spawn(function()
				local atEnd = false
				while prism.Parent do
					task.wait(mover.Period / 2)
					atEnd = not atEnd
					prism.TargetPosition = if atEnd then mover.Distance else 0
				end
			end)
		end
	end
end

-- Lifecycle ----------------------------------------------------------------------------------------

function ObbyService:Init(services)
	self.Services = services
	Net.registerAction("ObbyTeleport", {
		Rate = ObbyConfig.TeleportRate,
		Handler = function(profile, payload)
			return self:Teleport(profile, payload.To)
		end,
	})
end

function ObbyService:Start()
	local existing = workspace:FindFirstChild("Obby")
	if existing and existing:IsA("Model") then
		self:_adopt(existing)
	else
		self:_build()
	end
	self:_runMovers()

	local debounce: { [Player]: number } = {}
	for _, kill in ipairs(self.Kill) do
		kill.Touched:Connect(function(hit)
			local character = hit.Parent
			local player = character and Players:GetPlayerFromCharacter(character)
			if not player or (debounce[player] and os.clock() - debounce[player] < 0.5) then
				return
			end
			debounce[player] = os.clock()
			local profile = self.Services.DataService:GetProfile(player)
			if profile then
				self:RespawnAtCheckpoint(profile)
			end
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		debounce[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(AC.SampleInterval)
			for _, profile in pairs(self.Services.DataService.Profiles) do
				local ok, err = pcall(self._sample, self, profile)
				if not ok then
					warn(`[ObbyService] Sample failed for {profile.UserId}: {err}`)
				end
			end
		end
	end)
end

function ObbyService:OnProfileLoaded(profile)
	local rt = profile.Runtime
	rt.Obby = { LastPos = nil, ReachedAt = os.clock(), SuspectUntil = 0, GraceUntil = 0 }
	local player = profile.Player
	player.CharacterAdded:Connect(function(character)
		self:_onCharacter(profile, character)
	end)
	if player.Character then
		self:_onCharacter(profile, player.Character)
	end
end

-- Respawning mid-run puts you back on your checkpoint.
function ObbyService:_onCharacter(profile, character: Model)
	local rt = profile.Runtime.Obby
	if rt then
		rt.LastPos = nil
	end
	if profile.Data.Obby.Stage <= 0 then
		return
	end
	task.spawn(function()
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if root and character.Parent and self.Services.DataService:GetProfile(profile.Player) == profile then
			self:_moveTo(profile, self:CheckpointCFrame(profile.Data.Obby.Stage))
		end
	end)
end

-- Positions --------------------------------------------------------------------------------------

-- Where a player stands for a stage (0 = start pad).
function ObbyService:CheckpointCFrame(stage: number): CFrame
	local pad = if stage <= 0 then self.Start else self.Pads[math.min(stage, COUNT)]
	local position = pad.Position + Vector3.new(0, pad.Size.Y / 2 + 3, 0)
	return CFrame.lookAt(position, position + Vector3.xAxis)
end

function ObbyService:_moveTo(profile, target: CFrame)
	local character = profile.Player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not root then
		return false
	end
	character:PivotTo(target)
	root.AssemblyLinearVelocity = Vector3.zero
	local rt = profile.Runtime.Obby
	if rt then
		rt.LastPos = target.Position
		rt.GraceUntil = os.clock() + SERVER_MOVE_GRACE
	end
	return true
end

function ObbyService:RespawnAtCheckpoint(profile)
	return self:_moveTo(profile, self:CheckpointCFrame(profile.Data.Obby.Stage))
end

local function inside(part: BasePart, position: Vector3, margin: Vector3): boolean
	local localPos = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2 + margin
	return math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y and math.abs(localPos.Z) <= half.Z
end

-- Standing on a pad: within its footprint and up to a few studs above it.
local function onPad(pad: BasePart, position: Vector3): boolean
	local localPos = pad.CFrame:PointToObjectSpace(position)
	local half = pad.Size / 2
	return math.abs(localPos.X) <= half.X + 0.5 and math.abs(localPos.Z) <= half.Z + 0.5 and localPos.Y >= 0 and localPos.Y <= half.Y + 6
end

function ObbyService:_inBounds(position: Vector3): boolean
	local min, max = self.Bounds.Min, self.Bounds.Max
	return position.X >= min.X and position.X <= max.X and position.Y >= min.Y and position.Y <= max.Y and position.Z >= min.Z and position.Z <= max.Z
end

-- Sampling and progress --------------------------------------------------------------------------


function ObbyService:_sample(profile)
	local rt = profile.Runtime.Obby
	local character = profile.Player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not rt or not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	local now = os.clock()
	local position = root.Position
	local grace = now < rt.GraceUntil

	-- Teleport detection (only movement the server did not cause).
	if rt.LastPos and not grace and (position - rt.LastPos).Magnitude > AC.TeleportDistance then
		rt.SuspectUntil = now + AC.SuspectSeconds
		if self:_inBounds(position) or self:_inBounds(rt.LastPos) then
			self.Services.SecurityService:Flag(profile.Player, "ObbyTeleport", `{math.floor((position - rt.LastPos).Magnitude)} studs`)
		end
	end
	rt.LastPos = position

	if grace or not self:_inBounds(position) then
		return
	end
	local data = profile.Data.Obby

	-- Void and kill bricks.
	local checkpoint = self:CheckpointCFrame(data.Stage)
	if position.Y < checkpoint.Position.Y - AC.VoidDepth - 3 then
		self:RespawnAtCheckpoint(profile)
		return
	end
	for _, kill in ipairs(self.Kill) do
		if inside(kill, position, KILL_MARGIN) then
			self:RespawnAtCheckpoint(profile)
			return
		end
	end

	-- Standing on the start pad (re)starts the clock for stage 1.
	if data.Stage == 0 and onPad(self.Start, position) then
		rt.ReachedAt = now
		return
	end

	local nextStage = data.Stage + 1
	local pad = self.Pads[nextStage]
	if not pad or not onPad(pad, position) then
		return
	end
	if now < rt.SuspectUntil then
		return
	end
	local from = if data.Stage == 0 then self.Start.Position else self.Pads[data.Stage].Position
	local minSeconds = math.max(AC.MinSegmentSeconds, (pad.Position - from).Magnitude / AC.MaxTravelSpeed)
	if now - rt.ReachedAt < minSeconds then
		self.Services.SecurityService:Flag(profile.Player, "ObbyTooFast", `stage {nextStage} in {Format.time(now - rt.ReachedAt)}`)
		rt.SuspectUntil = now + AC.SuspectSeconds
		return
	end
	rt.ReachedAt = now
	self:_reach(profile, nextStage)
end

function ObbyService:_reach(profile, stage: number)
	local data = profile.Data.Obby
	local economy = self.Services.EconomyService
	local base = self.Services.StatsService:GetBase(profile).clickValue
	data.Checkpoints += 1

	local gems = 0
	if stage > data.Best then
		data.Best = stage
		gems += if stage % 5 == 0 then REWARDS.MilestoneGems else REWARDS.FirstClearGems
	end

	local sparks, text
	if stage >= COUNT then
		data.Completions += 1
		data.Stage = 0
		sparks = base * REWARDS.FinishPresses
		gems += REWARDS.FinishGems
		if data.Completions == 1 then
			gems += REWARDS.FirstFinishGems
		end
		gems += REWARDS.CompletionMilestones[data.Completions] or 0
		text = `OBBY COMPLETE! (#{data.Completions})`
	else
		data.Stage = stage
		sparks = base * REWARDS.CheckpointPresses * stage
		text = `Stage {stage} cleared!`
	end

	economy:AddSparks(profile, sparks, "obby")
	if gems > 0 then
		economy:Add(profile, "Gems", gems, "obby")
	end
	self.Services.SyncService:MarkDirty(profile, "Obby")
	local reward = `+{Format.short(sparks)} ⚡` .. (if gems > 0 then ` +{gems} 💎` else "")
	self.Services.Net.notify(profile.Player, "Toast", {
		Icon = if stage >= COUNT then "🏆" else "🏁",
		Text = `{text} {reward}`,
	})
	if stage >= COUNT then
		task.delay(3, function()
			if self.Services.DataService:GetProfile(profile.Player) == profile then
				self:_moveTo(profile, PLAZA_SPAWN)
			end
		end)
	end
end

-- Action: move to your own checkpoint (or the start) or back to the plaza.
function ObbyService:Teleport(profile, rawTo: any)
	local to = Guard.oneOf(rawTo, { "checkpoint", "plaza" })
	if not to then
		return Net.fail("Invalid request.")
	end
	local humanoid = profile.Player.Character and profile.Player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return Net.fail("Wait until you have respawned.")
	end
	local target = if to == "plaza" then PLAZA_SPAWN else self:CheckpointCFrame(profile.Data.Obby.Stage)
	if not self:_moveTo(profile, target) then
		return Net.fail("Wait until you have respawned.")
	end
	if to == "checkpoint" then
		-- The clock for the next checkpoint starts again from here.
		profile.Runtime.Obby.ReachedAt = os.clock()
	end
	return Net.ok({ Stage = profile.Data.Obby.Stage })
end

return ObbyService
