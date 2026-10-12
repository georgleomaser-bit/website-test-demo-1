-- =====================================================================
--  CLUTCH CLASH – Blick-Replikation & 3rd-Person-Darstellung (Client/Modules/Replication)
--  Besitzer: WP4 (Kampf Client). Vertrag: DESIGN.md B14.8 (Client-Teil), C8 (Look/LookBatch), B11.1 (Zielfernrohr-Glanz).
--    Senden:     Look (UnreliableRemoteEvent, 4 Byte über Net.EncodeLook) mit ≤ 12 Hz, nur bei Pitch-Änderung > 1°
--                oder geänderten Flags, nur bewaffnet und nicht gepoppt.
--    Empfangen:  LookBatch (10 Hz pro Kontext) -> Neck-C0 (×0.5) und Waist-C0 (×0.15) der anderen (R15/R6),
--                weich nachgeführt, nur lokal (C0 wird nie vom Animator überschrieben).
--    Flags anderer: Nachladen kippt die Waffen-Schweißung lokal (sonst Schulter), Schwung dreht die Schulter,
--                Rutschen -> Staub, ADS mit Fernschuss -> Zielfernrohr-Glanz nach ScopeGlintAfter s (nur Gegner).
--    Eigener Character: toolnone 507768375 (Looped, Priority Action) solange bewaffnet.
--    BigHead-Bälle: Combatant-Modelle mit Attribut BigHead bekommen lokal eine große Kopf-Kugel.
--    Namensschilder (AKYTEX): Rahmen "Edge" der Server-Tafel lokal relativ zum Betrachter färben –
--                eigenes Team Accent, Gegner Down (der Server kennt nur Team 1/2).
--  Slot -> Combatant: Roster aus Match("Start"); sonst Attribut "Slot" am Modell (Range).
--
--  Öffentliche API (C7.4):
--    Replication.Flags(): number     aktuelle Net.LookFlags des lokalen Spielers
-- =====================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local Replication = {}

local player = Players.LocalPlayer
local ctx: any = nil

type Motors = { Neck: Motor6D?, Waist: Motor6D?, Shoulder: Motor6D? }
type Entry = {
	Slot: number,
	Model: Model?,
	Motors: Motors?,
	Pitch: number,
	Shown: number,
	AppliedPitch: number,
	Flags: number,
	AdsSince: number,
	SwingStart: number,
	Reload: number,
	AppliedArm: number,
	NextResolve: number,
	Glint: BillboardGui?,
	Dust: ParticleEmitter?,
	WeaponJoint: JointInstance?,
	JointTilted: boolean,
	WeaponScan: number,
}

-- ---------------------------------------------------------------------
-- 1) KONSTANTEN
-- ---------------------------------------------------------------------
local SEND_INTERVAL = 1 / 12
local NECK_MULT = 0.5
local WAIST_MULT = 0.15
local MAX_ENTRIES = 32
local CULL_DISTANCE = 250
local SWING_TIME = 0.3
local TOOLNONE_ID = "rbxassetid://507768375"
local GLOW_TEXTURE = "rbxasset://textures/glow.png"
local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local FLAGS = Net.LookFlags

-- ---------------------------------------------------------------------
-- 2) ZUSTAND
-- ---------------------------------------------------------------------
local remotes: { [string]: Instance } = {}
local armed = false
local popped = false
local sendAccum = 0
local lastSentPitch = 1000
local lastSentFlags = -1
local seq = 0
local lastBatchSeq = -1

local entries: { [number]: Entry } = {}
local slotToId: { [number]: number } = {}
local idTeam: { [number]: number } = {}
local myTeam = 0
local origC0: { [Instance]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local bigBalls: { [Model]: BasePart } = setmetatable({}, { __mode = "k" }) :: any
local bigHeadAccum = 0
type Tint = { Orig: Color3, Tint: Color3 }
local plateTints: { [UIStroke]: Tint } = setmetatable({}, { __mode = "k" }) :: any

local holdAnimation = Instance.new("Animation")
holdAnimation.AnimationId = TOOLNONE_ID
local holdTrack: AnimationTrack? = nil
local holdToken = 0

-- ---------------------------------------------------------------------
-- 3) HELFER
-- ---------------------------------------------------------------------
local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function modules(): { [string]: any }
	return if ctx and type(ctx.Modules) == "table" then ctx.Modules else {}
end

local function call(moduleName: string, fnName: string, ...: any): any
	local mod = modules()[moduleName]
	if mod and type(mod[fnName]) == "function" then
		local ok, result = pcall(mod[fnName], ...)
		if ok then
			return result
		end
	end
	return nil
end

local function has(flags: number, bit: number): boolean
	return bit32.band(flags, bit) ~= 0
end

local function glintAfter(): number
	local combat = ctx and ctx.Config and ctx.Config.Combat
	return if combat and finite(combat.ScopeGlintAfter) then combat.ScopeGlintAfter else 0.3
end

local function motorC0(motor: Motor6D): CFrame
	local orig = origC0[motor]
	if not orig then
		orig = motor.C0
		origC0[motor] = orig
	end
	return orig
end

local function restoreMotor(motor: Motor6D?)
	if motor and origC0[motor] then
		motor.C0 = origC0[motor]
	end
end

local function findMotors(model: Model): Motors
	local function motor(parentName: string, name: string): Motor6D?
		local parent = model:FindFirstChild(parentName)
		local m = parent and parent:FindFirstChild(name)
		return if m and m:IsA("Motor6D") then m else nil
	end
	local neck = motor("Head", "Neck") or motor("Torso", "Neck")
	local waist = motor("UpperTorso", "Waist")
	local shoulder = motor("RightUpperArm", "RightShoulder") or motor("Torso", "Right Shoulder")
	return { Neck = neck, Waist = waist, Shoulder = shoulder }
end

-- Combatant-Modell zu einer Id (Spieler direkt, Bots/Puppen über das Register von WeaponClient)
local function modelOfId(id: number): Model?
	if id > 0 or (id < 0 and id >= -999) then
		local p = Players:GetPlayerByUserId(id)
		if p and p.Character then
			return p.Character
		end
	end
	local m = call("WeaponClient", "ModelOf", id)
	if typeof(m) == "Instance" and m:IsA("Model") then
		return m
	end
	return nil
end

local function modelOfSlot(slot: number): Model?
	local id = slotToId[slot]
	if id then
		return modelOfId(id)
	end
	-- Ohne Roster (Range): Attribut "Slot" am Combatant-Modell
	local list = call("WeaponClient", "Combatants")
	if type(list) == "table" then
		for _, m in ipairs(list) do
			if typeof(m) == "Instance" and m:IsA("Model") and m:GetAttribute("Slot") == slot then
				return m
			end
		end
	end
	return nil
end

local function isEnemyModel(model: Model): boolean
	local team = model:GetAttribute("Team")
	if not finite(team) then
		local id = model:GetAttribute("CombatantId")
		team = if finite(id) then idTeam[id :: number] else nil
	end
	if not finite(team) or myTeam == 0 then
		return true
	end
	return team ~= myTeam
end

-- sichtbares Waffen-Modell im Character (CharacterService schaltet per Transparenz um)
local function visibleWeapon(model: Model): Model?
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Model") and d:GetAttribute("WeaponKey") ~= nil then
			local primary = d.PrimaryPart
			if primary and primary.Transparency < 1 then
				return d
			end
		end
	end
	return nil
end

-- ---------------------------------------------------------------------
-- 4) EINTRÄGE
-- ---------------------------------------------------------------------
local function clearEntry(e: Entry)
	local motors = e.Motors
	if motors and e.Model and e.Model.Parent then
		restoreMotor(motors.Neck)
		restoreMotor(motors.Waist)
		restoreMotor(motors.Shoulder)
	end
	local joint = e.WeaponJoint
	if joint and joint.Parent and origC0[joint] then
		(joint :: any).C0 = origC0[joint]
	end
	if e.Glint then
		e.Glint:Destroy()
	end
	if e.Dust then
		e.Dust:Destroy()
	end
end

local function clearAll()
	for slot, e in pairs(entries) do
		clearEntry(e)
		entries[slot] = nil
	end
	lastBatchSeq = -1
end

local function entryFor(slot: number): Entry?
	local e = entries[slot]
	if e then
		return e
	end
	local count = 0
	for _ in pairs(entries) do
		count += 1
	end
	if count >= MAX_ENTRIES then
		return nil
	end
	e = {
		Slot = slot,
		Model = nil,
		Motors = nil,
		Pitch = 0,
		Shown = 0,
		AppliedPitch = 0,
		Flags = 0,
		AdsSince = 0,
		SwingStart = -10,
		Reload = 0,
		AppliedArm = 0,
		NextResolve = 0,
		Glint = nil,
		Dust = nil,
		WeaponJoint = nil,
		JointTilted = false,
		WeaponScan = 0,
	}
	entries[slot] = e
	return e
end

local function resolve(e: Entry, now: number): Model?
	local m = e.Model
	if m and m.Parent then
		return m
	end
	if now < e.NextResolve then
		return nil
	end
	e.NextResolve = now + 1
	if e.Glint then
		e.Glint:Destroy()
		e.Glint = nil
	end
	if e.Dust then
		e.Dust:Destroy()
		e.Dust = nil
	end
	e.WeaponJoint = nil
	local model = modelOfSlot(e.Slot)
	if model == player.Character then
		model = nil -- eigener Character: kein Neigen (Ego-Sicht)
	end
	e.Model = model
	e.Motors = if model then findMotors(model) else nil
	e.AppliedPitch = 0
	e.AppliedArm = 0
	return model
end

-- ---------------------------------------------------------------------
-- 5) LOOKBATCH EMPFANGEN
-- ---------------------------------------------------------------------
local function onLookBatch(b: any)
	if typeof(b) ~= "buffer" then
		return
	end
	local batchSeq, list = Net.DecodeLookBatch(b)
	if batchSeq == nil then
		return
	end
	if lastBatchSeq >= 0 then
		local diff = (batchSeq - lastBatchSeq) % 65536
		if diff == 0 or diff > 32768 then
			return -- älteres oder doppeltes Paket
		end
	end
	lastBatchSeq = batchSeq
	local now = os.clock()
	for _, item in ipairs(list) do
		local e = entryFor(item.Slot)
		if e then
			e.Pitch = math.clamp(item.Pitch, -80, 80)
			local old = e.Flags
			local new = item.Flags
			if has(new, FLAGS.Ads) and not has(old, FLAGS.Ads) then
				e.AdsSince = now
			end
			if has(new, FLAGS.Swing) and not has(old, FLAGS.Swing) then
				e.SwingStart = now
			end
			e.Flags = new
		end
	end
end

-- ---------------------------------------------------------------------
-- 6) DARSTELLUNG ANDERER (PreRender)
-- ---------------------------------------------------------------------
local function ensureGlint(e: Entry, weapon: Model): BillboardGui?
	if e.Glint and e.Glint.Parent then
		return e.Glint
	end
	local primary = weapon.PrimaryPart
	if not primary then
		return nil
	end
	local sight = primary:FindFirstChild("Sight")
	local gui = Instance.new("BillboardGui")
	gui.Name = "CC_ScopeGlint"
	gui.Size = UDim2.fromScale(3, 3)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Enabled = false
	gui.Adornee = if sight and sight:IsA("Attachment") then sight else primary
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Image = GLOW_TEXTURE
	image.ImageColor3 = Color3.fromRGB(255, 250, 220)
	image.Parent = gui
	gui.Parent = primary
	e.Glint = gui
	return gui
end

local function ensureDust(e: Entry, model: Model): ParticleEmitter?
	if e.Dust and e.Dust.Parent then
		return e.Dust
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "CC_RemoteDust"
	attachment.Position = Vector3.new(0, -2.6, 0.4)
	attachment.Parent = root
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = DUST_TEXTURE
	emitter.Color = ColorSequence.new(Color3.fromRGB(240, 232, 220))
	emitter.Lifetime = NumberRange.new(0.35, 0.6)
	emitter.Speed = NumberRange.new(2, 5)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.EmissionDirection = Enum.NormalId.Back
	emitter.Size = NumberSequence.new(0.6, 1.8)
	emitter.Transparency = NumberSequence.new(0.35, 1)
	emitter.Rate = 30
	emitter.Enabled = false
	emitter.Parent = attachment
	-- Attachment mit aufräumen
	emitter.Destroying:Connect(function()
		attachment:Destroy()
	end)
	e.Dust = emitter
	return emitter
end

-- Gelenk zwischen Hand und sichtbarer Waffe (Weld/Motor6D mit C0) – sonst nil (dann kippt die Schulter)
local function weaponJoint(model: Model): JointInstance?
	local weapon = visibleWeapon(model)
	local primary = weapon and weapon.PrimaryPart
	if not primary then
		return nil
	end
	local hand = model:FindFirstChild("RightHand") or model:FindFirstChild("Right Arm")
	for _, holder in ipairs({ primary, hand }) do
		if holder then
			for _, child in ipairs((holder :: Instance):GetChildren()) do
				if
					(child:IsA("Weld") or child:IsA("Motor6D"))
					and ((child :: Weld).Part0 == primary or (child :: Weld).Part1 == primary)
				then
					return child :: JointInstance
				end
			end
		end
	end
	return nil
end

local function swingCurve(t: number): number
	if t <= 0 or t >= 1 then
		return 0
	end
	if t < 0.35 then
		return math.sin((t / 0.35) * math.pi * 0.5) * 70
	end
	local u = (t - 0.35) / 0.65
	return 70 * (1 - u) - 15 * math.sin(u * math.pi)
end

local function updateEntry(e: Entry, model: Model, dt: number, now: number, camPos: Vector3)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) or (root.Position - camPos).Magnitude > CULL_DISTANCE then
		return
	end
	local motors = e.Motors
	if not motors then
		return
	end
	-- Neigung (weich)
	e.Shown += (e.Pitch - e.Shown) * (1 - math.exp(-dt * 14))
	if math.abs(e.Shown - e.AppliedPitch) > 0.25 then
		e.AppliedPitch = e.Shown
		local p = math.rad(e.Shown)
		local neck = motors.Neck
		if neck and neck.Parent then
			local orig = motorC0(neck)
			neck.C0 = CFrame.new(orig.Position) * CFrame.Angles(p * NECK_MULT, 0, 0) * orig.Rotation
		end
		local waist = motors.Waist
		if waist and waist.Parent then
			local orig = motorC0(waist)
			waist.C0 = CFrame.new(orig.Position) * CFrame.Angles(p * WAIST_MULT, 0, 0) * orig.Rotation
		end
	end

	-- Nachladen (Waffen-Schweißung kippen) und Schwung (Schulter)
	local reloading = has(e.Flags, FLAGS.Reload)
	e.Reload += ((if reloading then 1 else 0) - e.Reload) * (1 - math.exp(-dt * 10))
	if reloading and e.WeaponJoint == nil and now >= e.WeaponScan then
		e.WeaponScan = now + 1
		e.WeaponJoint = weaponJoint(model)
	end
	local swingDeg = swingCurve((now - e.SwingStart) / SWING_TIME)
	local blockDeg = if has(e.Flags, FLAGS.Block) then 35 else 0
	local shoulderReload = e.Reload
	local joint = e.WeaponJoint
	if joint and joint.Parent then
		-- bevorzugt: Waffen-Schweißung lokal kippen
		local orig = origC0[joint]
		if not orig then
			orig = (joint :: any).C0
			origC0[joint] = orig
		end
		local tilt = e.Reload
		if tilt > 0.002 or e.JointTilted then
			(joint :: any).C0 = (orig :: CFrame) * CFrame.Angles(math.rad(-35) * tilt, 0, math.rad(25) * tilt)
			e.JointTilted = tilt > 0.002
		end
		shoulderReload = 0
	end
	local armDeg = swingDeg + blockDeg
	local armValue = armDeg + shoulderReload * 100
	local shoulder = motors.Shoulder
	if shoulder and shoulder.Parent and math.abs(armValue - e.AppliedArm) > 0.3 then
		e.AppliedArm = armValue
		local orig = motorC0(shoulder)
		shoulder.C0 = CFrame.new(orig.Position)
			* CFrame.Angles(math.rad(armDeg) + math.rad(-20) * shoulderReload, 0, math.rad(15) * shoulderReload)
			* orig.Rotation
	end

	-- Rutsch-Staub
	local sliding = has(e.Flags, FLAGS.Slide)
	if sliding or e.Dust then
		local dust = ensureDust(e, model)
		if dust and dust.Enabled ~= sliding then
			dust.Enabled = sliding
		end
	end

	-- Zielfernrohr-Glanz (nur Gegner, nur Fernschuss, nach ScopeGlintAfter s ADS)
	local glintOn = false
	if has(e.Flags, FLAGS.Ads) and now - e.AdsSince >= glintAfter() and isEnemyModel(model) then
		local weapon = visibleWeapon(model)
		if weapon and weapon:GetAttribute("WeaponKey") == "Longshot" then
			local gui = ensureGlint(e, weapon)
			if gui then
				glintOn = true
				local pulse = 2.6 + math.sin(now * 9) * 0.5
				gui.Size = UDim2.fromScale(pulse, pulse)
			end
		end
	end
	if e.Glint and e.Glint.Enabled ~= glintOn then
		e.Glint.Enabled = glintOn
	end
end

-- BigHead-Bälle (Mutator BigHeads): Attribut BigHead am Combatant-Modell
local function updateBigHeads()
	local list = call("WeaponClient", "Combatants")
	if type(list) ~= "table" then
		list = {}
	end
	local seen: { [Model]: boolean } = {}
	for _, m in ipairs(list) do
		if typeof(m) == "Instance" and m:IsA("Model") and m ~= player.Character then
			local flag = m:GetAttribute("BigHead")
			local head = m:FindFirstChild("Head")
			if flag and flag ~= 0 and head and head:IsA("BasePart") then
				seen[m] = true
				local ball = bigBalls[m]
				if not (ball and ball.Parent) then
					local mult = if finite(flag) then math.clamp(flag :: number, 1, 3) else 1.6
					local d = 1.6 * mult
					local part = Instance.new("Part")
					part.Name = "CC_BigHead"
					part.Shape = Enum.PartType.Ball
					part.Size = Vector3.new(d, d, d)
					part.Color = head.Color
					part.Material = Enum.Material.SmoothPlastic
					part.CanCollide = false
					part.CanQuery = false
					part.CanTouch = false
					part.CastShadow = false
					part.Massless = true
					part.CFrame = head.CFrame
					local face = head:FindFirstChildOfClass("Decal")
					if face then
						face:Clone().Parent = part
					end
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = head
					weld.Part1 = part
					weld.Parent = part
					part.Parent = m
					bigBalls[m] = part
				end
			end
		end
	end
	for m, ball in pairs(bigBalls) do
		if not seen[m] then
			ball:Destroy()
			bigBalls[m] = nil
		end
	end
end

-- Namensschild-Rahmen relativ zum Betrachter (nur lokal; Server-Änderungen überschreiben, 1 Hz neu)
local function themeColor(key: string, fallback: Color3): Color3
	local ui = ctx and ctx.UI
	local theme = ui and ui.Theme
	local c = if type(theme) == "table" then theme[key] else nil
	return if typeof(c) == "Color3" then c else fallback
end

local function tintPlates()
	local list = call("WeaponClient", "Combatants")
	if type(list) ~= "table" or not armed then
		list = {}
	end
	local accent = themeColor("Accent", Color3.fromRGB(79, 140, 255))
	local down = themeColor("Down", Color3.fromRGB(239, 68, 68))
	local seen: { [UIStroke]: boolean } = {}
	for _, m in ipairs(list) do
		if typeof(m) == "Instance" and m:IsA("Model") and m ~= player.Character then
			local head = m:FindFirstChild("Head") or m.PrimaryPart
			local gui = head and head:FindFirstChild("CC_Nameplate")
			local edge = gui and gui:FindFirstChild("Edge", true)
			if edge and edge:IsA("UIStroke") then
				local want = if isEnemyModel(m) then down else accent
				local entry = plateTints[edge]
				if not entry or edge.Color ~= entry.Tint then
					entry = { Orig = edge.Color, Tint = want }
					plateTints[edge] = entry
				end
				entry.Tint = want
				if edge.Color ~= want then
					edge.Color = want
				end
				seen[edge] = true
			end
		end
	end
	-- nicht mehr im Kampf: Server-Farbe zurück (falls der Server sie inzwischen nicht selbst geändert hat)
	for edge, entry in pairs(plateTints) do
		if not seen[edge] then
			if edge.Parent and edge.Color == entry.Tint then
				edge.Color = entry.Orig
			end
			plateTints[edge] = nil
		end
	end
end

local function onRender(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local now = os.clock()
	local camPos = camera.CFrame.Position
	for _, e in pairs(entries) do
		local model = resolve(e, now)
		if model then
			updateEntry(e, model, dt, now, camPos)
		end
	end
	bigHeadAccum += dt
	if bigHeadAccum >= 1 then
		bigHeadAccum = 0
		updateBigHeads()
		tintPlates()
	end
end

-- ---------------------------------------------------------------------
-- 7) EIGENER CHARACTER: toolnone + Look senden
-- ---------------------------------------------------------------------
local function stopHold()
	holdToken += 1
	if holdTrack then
		holdTrack:Stop(0.2)
		holdTrack:Destroy()
		holdTrack = nil
	end
end

local function playHold()
	stopHold()
	local token = holdToken
	task.spawn(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 5)
		if token ~= holdToken or not (animator and animator:IsA("Animator")) then
			return
		end
		local ok, track = pcall(function()
			return animator:LoadAnimation(holdAnimation)
		end)
		if ok and track and token == holdToken then
			track.Looped = true
			track.Priority = Enum.AnimationPriority.Action
			track:Play(0.15)
			holdTrack = track
		end
	end)
end

function Replication.Flags(): number
	local flags = 0
	if call("WeaponClient", "IsAds") == true then
		flags += FLAGS.Ads
	end
	if call("Movement", "IsSprinting") == true then
		flags += FLAGS.Sprint
	end
	if call("Movement", "IsSliding") == true then
		flags += FLAGS.Slide
	end
	if call("WeaponClient", "IsReloading") == true then
		flags += FLAGS.Reload
	end
	if call("WeaponClient", "IsBlocking") == true then
		flags += FLAGS.Block
	end
	if call("Movement", "IsAirborne") == true then
		flags += FLAGS.Air
	end
	if call("WeaponClient", "IsSwinging") == true then
		flags += FLAGS.Swing
	end
	return flags
end

local function onHeartbeat(dt: number)
	if not armed or popped then
		return
	end
	sendAccum += dt
	if sendAccum < SEND_INTERVAL then
		return
	end
	sendAccum = math.min(sendAccum - SEND_INTERVAL, SEND_INTERVAL)
	local camera = workspace.CurrentCamera
	local look = remotes.Look
	if not (camera and look and look:IsA("UnreliableRemoteEvent")) then
		return
	end
	local pitch = math.floor(math.deg(math.asin(math.clamp(camera.CFrame.LookVector.Y, -1, 1))) + 0.5)
	pitch = math.clamp(pitch, -80, 80)
	local flags = Replication.Flags()
	if math.abs(pitch - lastSentPitch) > 1 or flags ~= lastSentFlags then
		seq = (seq + 1) % 65536
		lastSentPitch = pitch
		lastSentFlags = flags
		look:FireServer(Net.EncodeLook(pitch, flags, seq))
	end
end

-- ---------------------------------------------------------------------
-- 8) MODUL-FORM
-- ---------------------------------------------------------------------
local function onArmed(info: any)
	armed = true
	popped = false
	lastSentPitch = 1000
	lastSentFlags = -1
	if type(info) == "table" and finite(info.Team) then
		myTeam = info.Team
	end
	playHold()
end

local function onDisarmed()
	armed = false
	popped = false
	stopHold()
	clearAll()
end

function Replication.Init(context: any)
	ctx = context
	if ctx and type(ctx.Remotes) == "table" then
		remotes = ctx.Remotes
	else
		remotes = Net.GetRemotes()
	end
end

function Replication.Start()
	local hooks = ctx and ctx.Hooks
	if hooks and type(hooks.On) == "function" then
		hooks.On("Armed", onArmed)
		hooks.On("Disarmed", onDisarmed)
		hooks.On("LocalPopped", function()
			popped = true
			stopHold()
		end)
		hooks.On("LocalRevived", function()
			popped = false
			if armed then
				playHold()
			end
		end)
		hooks.On("Match:Start", function(data: any)
			clearAll()
			table.clear(slotToId)
			table.clear(idTeam)
			if type(data) ~= "table" then
				return
			end
			if finite(data.MyTeam) then
				myTeam = data.MyTeam
			end
			if type(data.Roster) == "table" then
				for _, r in ipairs(data.Roster) do
					if type(r) == "table" and finite(r.Slot) and finite(r.Id) then
						slotToId[r.Slot] = r.Id
						if finite(r.Team) then
							idTeam[r.Id] = r.Team
						end
					end
				end
			end
		end)
		hooks.On("Match:Left", function(data: any)
			if type(data) ~= "table" or not finite(data.Id) then
				return
			end
			for slot, id in pairs(slotToId) do
				if id == data.Id then
					local e = entries[slot]
					if e then
						clearEntry(e)
						entries[slot] = nil
					end
				end
			end
		end)
		hooks.On("Match:Closed", function()
			clearAll()
			table.clear(slotToId)
			table.clear(idTeam)
		end)
	end
	local batch = remotes.LookBatch
	if batch and batch:IsA("UnreliableRemoteEvent") then
		batch.OnClientEvent:Connect(onLookBatch)
	end
	player.CharacterAdded:Connect(function()
		holdTrack = nil
		if armed and not popped then
			playHold()
		end
	end)
	RunService.Heartbeat:Connect(onHeartbeat)
	RunService.PreRender:Connect(onRender)
end

return Replication
