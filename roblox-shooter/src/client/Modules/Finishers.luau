-- =====================================================================
--  CLUTCH CLASH – Finisher-Effekte beim Pop (Client/Modules/Finishers)
--  Besitzer: WP9 (Wirtschaft, Monetarisierung, Kosmetik). Vertrag: DESIGN.md B19 + C7.4 + C17.
--  8 Builder (Config.Cosmetics.Finishers). Regeln je Effekt: ≤ 25 Teile/Partikel, ≤ 2.5 s,
--  > 300 Studs von der Kamera = gar nicht abspielen, höchstens 4 gleichzeitig (sonst nur Konfetti).
--  Teile kommen aus einem Pool (werden wiederverwendet), alle nicht abfragbar/berührbar (Muss-Regel 11).
--  ReducedFx (Einstellung) halbiert die Stückzahlen. Kein Blut, nur Spielzeug-Konfetti (Muss-Regel 12).
--
--  Öffentliche API:
--    Finishers.Play(id, pos, color)      CombatFX.Pop ruft das auf (Fallback Konfetti)
--    Finishers.Preview(id)               Locker-Vorschau vor dem eigenen Charakter
--    Finishers.Active(): number
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))

local Finishers = {}
local ctx: any = nil

local HIDE_DISTANCE = 300
local MAX_ACTIVE = math.max(1, tonumber(Config.Client and Config.Client.Pools and Config.Client.Pools.Finishers) or 4)
local MAX_PARTS_PER_EFFECT = 25
local POOL_MAX = MAX_ACTIVE * MAX_PARTS_PER_EFFECT
local MAX_DURATION = 2.5
local DEFAULT_ID = "F_Confetti"

local TEX_SQUARE = "rbxasset://textures/particles/SquareParticle.png" -- ASSETS.md VERIFIED
local TEX_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_PUFF = "rbxasset://textures/explosion.png"

local rgb = Color3.fromRGB
local GOLD = rgb(255, 200, 40)
local PALETTE = {
	rgb(255, 90, 90),
	rgb(255, 200, 40),
	rgb(90, 220, 120),
	rgb(70, 170, 255),
	rgb(200, 110, 255),
	rgb(255, 120, 200),
}
local RAINBOW = {
	rgb(255, 70, 70),
	rgb(255, 160, 40),
	rgb(255, 235, 70),
	rgb(80, 220, 110),
	rgb(70, 160, 255),
	rgb(120, 90, 255),
	rgb(200, 90, 255),
}

local folder: Folder? = nil
local emitterPart: Part? = nil
local emitters: { [string]: ParticleEmitter } = {}
local freeParts: { Part } = {}
local createdParts = 0
local active = 0
local rng = Random.new()

-- ---------------------------------------------------------------------
-- 1) POOL & EMITTER
-- ---------------------------------------------------------------------
local function ensureFolder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "CC_Finishers"
	created.Parent = workspace
	folder = created
	return created
end

local function reducedFx(): boolean
	local modules = ctx and ctx.Modules
	local settings = modules and modules.Settings
	if settings and type(settings.Get) == "function" then
		local ok, values = pcall(settings.Get)
		return ok and type(values) == "table" and values.ReducedFx == true
	end
	return false
end

local function count(n: number): number
	return if reducedFx() then math.max(1, math.floor(n / 2)) else n
end

local function acquire(shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part?
	local p = table.remove(freeParts)
	if p == nil then
		if createdParts >= POOL_MAX then
			return nil -- Budget voll: dieses Stück einfach weglassen
		end
		createdParts += 1
		local created = Instance.new("Part")
		created.Anchored = true
		created.CanQuery = false
		created.CanTouch = false
		created.CanCollide = false
		created.Massless = true
		created.CastShadow = false
		created.TopSurface = Enum.SurfaceType.Smooth
		created.BottomSurface = Enum.SurfaceType.Smooth
		p = created
	end
	local part = p :: Part
	part.Shape = shape
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Transparency = 0
	part.Parent = ensureFolder()
	return part
end

local function release(part: Part)
	part.Parent = nil
	if #freeParts < POOL_MAX then
		table.insert(freeParts, part)
	else
		part:Destroy()
	end
end

local function makeEmitter(name: string, texture: string, props: { [string]: any }): ParticleEmitter
	local holder = emitterPart :: Part
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Parent = holder
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Texture = texture
	emitter.Enabled = false
	emitter.Rate = 0
	for key, value in pairs(props) do
		(emitter :: any)[key] = value
	end
	emitter.Parent = attachment
	emitters[name] = emitter
	return emitter
end

local function ensureEmitters()
	if emitterPart and emitterPart.Parent then
		return
	end
	local part = Instance.new("Part")
	part.Name = "FinisherEmitters"
	part.Anchored = true
	part.CanQuery = false
	part.CanTouch = false
	part.CanCollide = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.Parent = ensureFolder()
	emitterPart = part
	makeEmitter("Confetti", TEX_SQUARE, {
		Lifetime = NumberRange.new(1.2, 1.8),
		Speed = NumberRange.new(14, 26),
		SpreadAngle = Vector2.new(60, 60),
		Acceleration = Vector3.new(0, -30, 0),
		Drag = 2,
		RotSpeed = NumberRange.new(-360, 360),
		Rotation = NumberRange.new(0, 360),
		Size = NumberSequence.new(0.35),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.8, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		EmissionDirection = Enum.NormalId.Top,
	})
	makeEmitter("Sparkle", TEX_SPARKLE, {
		Lifetime = NumberRange.new(0.6, 1.0),
		Speed = NumberRange.new(3, 8),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) }),
		LightEmission = 1,
	})
	makeEmitter("Puff", TEX_PUFF, {
		Lifetime = NumberRange.new(0.6, 0.9),
		Speed = NumberRange.new(4, 9),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		LightEmission = 0.3,
	})
end

local function emit(name: string, pos: Vector3, n: number, colors: { Color3 })
	ensureEmitters()
	local emitter = emitters[name]
	local holder = emitterPart
	if emitter == nil or holder == nil then
		return
	end
	holder.CFrame = CFrame.new(pos)
	local keypoints = {}
	local steps = math.min(#colors, 8)
	for i = 1, steps do
		local t = if steps == 1 then 0 else (i - 1) / (steps - 1)
		table.insert(keypoints, ColorSequenceKeypoint.new(t, colors[i]))
	end
	if #keypoints == 1 then
		table.insert(keypoints, ColorSequenceKeypoint.new(1, colors[1]))
	end
	emitter.Color = ColorSequence.new(keypoints)
	emitter:Emit(math.clamp(count(n), 1, MAX_PARTS_PER_EFFECT))
end

-- ---------------------------------------------------------------------
-- 2) EFFEKT-LAUF: Teile + Tweens sammeln, nach der Dauer alles zurück in den Pool
-- ---------------------------------------------------------------------
type Run = { Parts: { Part }, Tweens: { Tween }, Budget: number }

local function newRun(): Run
	return { Parts = {}, Tweens = {}, Budget = MAX_PARTS_PER_EFFECT }
end

local function spawnPart(
	run: Run,
	shape: Enum.PartType,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part?
	if run.Budget <= 0 then
		return nil
	end
	local part = acquire(shape, size, cf, color, material)
	if part then
		run.Budget -= 1
		table.insert(run.Parts, part)
	end
	return part
end

local function tween(
	run: Run,
	inst: Instance,
	seconds: number,
	props: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?,
	delay: number?
)
	local info = TweenInfo.new(
		seconds,
		style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out,
		0,
		false,
		delay or 0
	)
	local t = TweenService:Create(inst, info, props)
	table.insert(run.Tweens, t)
	t:Play()
end

local function finish(run: Run, seconds: number)
	task.delay(math.min(seconds, MAX_DURATION), function()
		for _, t in ipairs(run.Tweens) do
			t:Cancel()
		end
		for _, p in ipairs(run.Parts) do
			release(p)
		end
		active = math.max(0, active - 1)
	end)
end

local function randomDir(): Vector3
	local v = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.2, 1), rng:NextNumber(-1, 1))
	return if v.Magnitude > 0.01 then v.Unit else Vector3.yAxis
end

local BALL = Enum.PartType.Ball
local BLOCK = Enum.PartType.Block
local CYL = Enum.PartType.Cylinder
local NEON = Enum.Material.Neon
local FOIL = Enum.Material.Foil

-- ---------------------------------------------------------------------
-- 3) DIE 8 BUILDER: (run, pos, color) -> Dauer in Sekunden
-- ---------------------------------------------------------------------
local Builders: { [string]: (Run, Vector3, Color3) -> number } = {}

Builders.F_Confetti = function(_run, pos, color)
	local colors = table.clone(PALETTE)
	table.insert(colors, 1, color)
	emit("Confetti", pos, 24, colors)
	return 0.1
end

Builders.F_PixelBurst = function(run, pos, color)
	for i = 1, count(16) do
		local c = if i % 3 == 0 then color else PALETTE[(i % #PALETTE) + 1]
		local part = spawnPart(run, BLOCK, Vector3.new(0.5, 0.5, 0.5), CFrame.new(pos), c, NEON)
		if part then
			local target = pos + randomDir() * rng:NextNumber(6, 10)
			tween(
				run,
				part,
				0.8,
				{ CFrame = CFrame.new(target) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0) }
			)
			tween(run, part, 0.4, { Transparency = 1 }, nil, nil, 0.8)
		end
	end
	return 1.3
end

Builders.F_IceCube = function(run, pos, _color)
	local cube =
		spawnPart(run, BLOCK, Vector3.new(0.5, 0.5, 0.5), CFrame.new(pos), rgb(170, 225, 255), Enum.Material.Glass)
	if cube then
		cube.Transparency = 0.35
		tween(run, cube, 0.25, { Size = Vector3.new(4, 6, 4) }, Enum.EasingStyle.Back)
		tween(run, cube, 0.3, { Transparency = 1 }, nil, nil, 1.3)
	end
	for _ = 1, count(8) do
		local shard =
			spawnPart(run, BLOCK, Vector3.new(0.7, 0.7, 0.7), CFrame.new(pos), rgb(200, 240, 255), Enum.Material.Glass)
		if shard then
			shard.Transparency = 1
			tween(run, shard, 0.05, { Transparency = 0.3 }, nil, nil, 1.25)
			tween(
				run,
				shard,
				0.6,
				{ CFrame = CFrame.new(pos + randomDir() * 7) * CFrame.Angles(1, 2, 0), Transparency = 1 },
				nil,
				nil,
				1.3
			)
		end
	end
	return 2.0
end

Builders.F_BalloonFloat = function(run, pos, color)
	for i = 1, count(5) do
		local offset = Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(0, 1.5), rng:NextNumber(-2, 2))
		local start = pos + offset
		local c = if i == 1 then color else PALETTE[(i % #PALETTE) + 1]
		local balloon =
			spawnPart(run, BALL, Vector3.new(1.4, 1.7, 1.4), CFrame.new(start), c, Enum.Material.SmoothPlastic)
		local string_ = spawnPart(
			run,
			CYL,
			Vector3.new(2, 0.06, 0.06),
			CFrame.new(start - Vector3.new(0, 1.8, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			rgb(240, 240, 240)
		)
		local rise = Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(14, 20), rng:NextNumber(-2, 2))
		local duration = rng:NextNumber(1.8, 2.2)
		if balloon then
			tween(
				run,
				balloon,
				duration,
				{ CFrame = CFrame.new(start + rise), Transparency = 0.6 },
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.In
			)
		end
		if string_ then
			tween(run, string_, duration, {
				CFrame = CFrame.new(start + rise - Vector3.new(0, 1.8, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				Transparency = 1,
			}, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
		end
	end
	return 2.3
end

Builders.F_GoldStatue = function(run, pos, _color)
	local base = pos - Vector3.new(0, 2.6, 0)
	local pieces = {
		{ BLOCK, Vector3.new(0.9, 2, 0.9), Vector3.new(-0.5, 1, 0) },
		{ BLOCK, Vector3.new(0.9, 2, 0.9), Vector3.new(0.5, 1, 0) },
		{ BLOCK, Vector3.new(2, 2, 1), Vector3.new(0, 3, 0) },
		{ BLOCK, Vector3.new(0.9, 2, 0.9), Vector3.new(-1.5, 3, 0) },
		{ BLOCK, Vector3.new(0.9, 2, 0.9), Vector3.new(1.5, 3, 0) },
		{ BALL, Vector3.new(1.3, 1.3, 1.3), Vector3.new(0, 4.7, 0) },
		{ CYL, Vector3.new(0.4, 3.2, 3.2), Vector3.new(0, -0.2, 0) },
	}
	for _, spec in ipairs(pieces) do
		local cf = CFrame.new(base + spec[3])
		if spec[1] == CYL then
			cf *= CFrame.Angles(0, 0, math.rad(90))
		end
		local part = spawnPart(run, spec[1], spec[2], cf, GOLD, FOIL)
		if part then
			part.Transparency = 0.6
			tween(run, part, 0.25, { Transparency = 0 })
			tween(run, part, 0.4, { Transparency = 1 }, nil, nil, 2.0)
		end
	end
	emit("Sparkle", pos + Vector3.new(0, 1.5, 0), 12, { GOLD, rgb(255, 245, 180) })
	return 2.45
end

Builders.F_RainbowPuff = function(run, pos, _color)
	emit("Puff", pos, 8, { rgb(255, 255, 255), rgb(255, 230, 250) })
	local n = count(7)
	for i = 1, n do
		local angle = (i / n) * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0.4, math.sin(angle))
		local part =
			spawnPart(run, BALL, Vector3.new(0.9, 0.9, 0.9), CFrame.new(pos), RAINBOW[((i - 1) % #RAINBOW) + 1], NEON)
		if part then
			tween(run, part, 0.9, { CFrame = CFrame.new(pos + dir * 7), Size = Vector3.new(1.8, 1.8, 1.8) })
			tween(run, part, 0.4, { Transparency = 1 }, nil, nil, 0.9)
		end
	end
	return 1.4
end

Builders.F_DuckRain = function(run, pos, _color)
	for _ = 1, count(12) do -- 12 Enten × 2 Teile = 24 ≤ 25
		local start = pos + Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(12, 18), rng:NextNumber(-6, 6))
		local landing = Vector3.new(start.X, pos.Y - 2.5, start.Z)
		local spin = CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
		local body = spawnPart(run, BALL, Vector3.new(1.3, 1.1, 1.3), CFrame.new(start) * spin, rgb(255, 215, 60))
		local head = spawnPart(
			run,
			BALL,
			Vector3.new(0.8, 0.8, 0.8),
			CFrame.new(start + Vector3.new(0, 0.8, 0)) * spin,
			rgb(255, 215, 60)
		)
		local fall = rng:NextNumber(1.3, 1.8)
		if body then
			tween(
				run,
				body,
				fall,
				{ CFrame = CFrame.new(landing) * spin },
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In
			)
			tween(run, body, 0.3, { Transparency = 1 }, nil, nil, fall)
		end
		if head then
			tween(
				run,
				head,
				fall,
				{ CFrame = CFrame.new(landing + Vector3.new(0, 0.8, 0)) * spin },
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In
			)
			tween(run, head, 0.3, { Transparency = 1 }, nil, nil, fall)
		end
	end
	return 2.3
end

Builders.F_CrownConfetti = function(run, pos, _color)
	local top = pos + Vector3.new(0, 4, 0)
	local parts: { { Part: Part, Offset: Vector3 } } = {}
	local function add(
		shape: Enum.PartType,
		size: Vector3,
		offset: Vector3,
		color: Color3,
		material: Enum.Material,
		rot: CFrame?
	)
		local part = spawnPart(run, shape, size, CFrame.new(pos + offset) * (rot or CFrame.identity), color, material)
		if part then
			table.insert(parts, { Part = part, Offset = offset })
		end
	end
	add(CYL, Vector3.new(0.8, 2.4, 2.4), Vector3.zero, GOLD, FOIL, CFrame.Angles(0, 0, math.rad(90)))
	for i = 1, 4 do
		local angle = (i / 4) * math.pi * 2
		add(BLOCK, Vector3.new(0.4, 1, 0.4), Vector3.new(math.cos(angle) * 0.9, 0.8, math.sin(angle) * 0.9), GOLD, FOIL)
	end
	add(BALL, Vector3.new(0.5, 0.5, 0.5), Vector3.new(0, 0, -1.2), rgb(255, 50, 90), NEON)
	for _, entry in ipairs(parts) do
		local part, offset = entry.Part, entry.Offset
		local rot = if part.Shape == CYL then CFrame.Angles(0, 0, math.rad(90)) else CFrame.identity
		tween(run, part, 0.6, { CFrame = CFrame.new(top + offset) * rot }, Enum.EasingStyle.Back)
		tween(run, part, 0.4, { Transparency = 1 }, nil, nil, 1.7)
	end
	emit("Confetti", top, 18, { GOLD, rgb(255, 240, 150), rgb(255, 255, 255) })
	return 2.2
end

-- ---------------------------------------------------------------------
-- 4) ÖFFENTLICH
-- ---------------------------------------------------------------------
local function farFromCamera(pos: Vector3): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - pos).Magnitude > HIDE_DISTANCE
end

function Finishers.Play(id: string, pos: Vector3, color: Color3)
	if not Util.IsFiniteVector(pos) or farFromCamera(pos) then
		return -- > 300 Studs: ausgeblendet
	end
	local tint = if typeof(color) == "Color3" then color else PALETTE[1]
	if active >= MAX_ACTIVE then
		emit("Confetti", pos, 12, { tint, PALETTE[2], PALETTE[4] }) -- Budget voll: nur Konfetti
		return
	end
	local builder = Builders[if type(id) == "string" then id else DEFAULT_ID] or Builders[DEFAULT_ID]
	active += 1
	local run = newRun()
	local ok, duration = pcall(builder, run, pos, tint)
	if not ok then
		warn("[Finishers] " .. tostring(id) .. ": " .. tostring(duration))
		duration = 0.1
	end
	finish(run, tonumber(duration) or MAX_DURATION)
end

function Finishers.Preview(id: string)
	local player = ctx and ctx.Player or Players.LocalPlayer
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	local pos: Vector3
	if root and root:IsA("BasePart") then
		pos = root.Position + root.CFrame.LookVector * 9 + Vector3.new(0, 1, 0)
	elseif camera then
		pos = camera.CFrame.Position + camera.CFrame.LookVector * 14
	else
		return
	end
	Finishers.Play(id, pos, Config.Colors and Config.Colors.TeamA or PALETTE[1])
end

function Finishers.Active(): number
	return active
end

function Finishers.Init(c: any)
	ctx = c
end

function Finishers.Start()
	-- Pool/Emitter erst beim ersten Effekt anlegen (spart Teile, solange niemand gepoppt wird)
end

return Finishers
