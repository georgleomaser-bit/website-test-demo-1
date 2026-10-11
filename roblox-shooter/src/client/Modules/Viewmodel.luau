-- =====================================================================
--  CLUTCH CLASH – Prozedurales Viewmodel (Client/Modules/Viewmodel)
--  Besitzer: WP4 (Kampf Client). Vertrag: DESIGN.md C7.4, B11.8, Muss-Regel 2 + 11.
--  Keine Animationen: Waffe (WeaponModels-Rezept, Skala 1.0) + Arme aus Blöcken (BodyColors,
--  Ärmel in Teamfarbe) liegen unter workspace.CurrentCamera, alle Teile verankert und nicht
--  kollidierend/abfragbar. Ein RenderStep bei Camera + 2 setzt alle CFrames per BulkMoveTo:
--    Hüfte↔ADS (Visier auf der Bildmitte), Sprint-/Rutsch-Pose, Bob, Sway (Feder aus Kamera-Drehung),
--    Sprung/Landung, Kick, Nachlade-Keyframes (Senken 20 % → Mag raus 20 % → Mag rein 30 % →
--    Repetieren 15 % → Heben 15 %), Ausrüsten 0.25 s, Inspizieren 1.2 s, Nahkampf-Schwünge,
--    Block-Pose, Trink-/Wurf-Pose, Wand-Rückzug (2.5-Stud-Ray), Charm-Pendel, Mündungsfeuer.
--  Budget: ≤ 30 Teile (Waffe ≤ 14 + Charm ≤ 8 + Arme 6 + Blitz 1).
--
--  Öffentliche API (C7.4):
--    Viewmodel.Equip(weaponKey, cos?)    cos = { Skin, Wrap, Charm } (Ids, "" = keins)
--    Viewmodel.Unequip()   Viewmodel.Fire()   Viewmodel.Reload(duration)   Viewmodel.Inspect()
--    Viewmodel.Swing(kind)               "Jab" | "Bonk" | "Slash" | "Throw" | "Drink" (unbekannt -> "Jab")
--    Viewmodel.SetAds(alpha)   Viewmodel.SetBlock(on)   Viewmodel.SetHidden(on)
--    Viewmodel.MuzzleCFrame(): CFrame?   Mündung im letzten Bild (nil = nicht sichtbar)
--  Zusätzlich: Viewmodel.HideFor(reason, on)  (mehrere Gründe: "Scope", "Popped", "External" …)
--              Viewmodel.CancelReload()       (Wechsel bricht die Nachlade-Animation ab)
-- =====================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Spring = require(Shared:WaitForChild("Spring"))
local WeaponModels = require(Shared:WaitForChild("WeaponModels"))

local Viewmodel = {}

local player = Players.LocalPlayer
local ctx: any = nil

type Hold = {
	Hip: CFrame,
	AdsDist: number?,
	Center: Vector3,
	Left: CFrame?, -- zweiter Handschuh / freie linke Hand
}
type Entry = { Part: BasePart, Offset: CFrame, Group: string }
type Key = { T: number, P: Vector3, R: Vector3 } -- Zeit 0..1, Versatz (Studs), Drehung (Grad)

-- ---------------------------------------------------------------------
-- 1) KONSTANTEN
-- ---------------------------------------------------------------------
local rad = math.rad
local EQUIP_TIME = 0.25
local INSPECT_TIME = 1.2
local WALL_RAY = 2.5
local MAX_PARTS = 30
local ARM_SKIN_DEFAULT = Color3.fromRGB(234, 184, 146)
local SLEEVE_DEFAULT = Color3.fromRGB(28, 32, 64)
local FLASH_COLOR = Color3.fromRGB(255, 232, 150)

local function ang(x: number, y: number, z: number): CFrame
	return CFrame.Angles(rad(x), rad(y), rad(z))
end

local HOLDS: { [string]: Hold } = {
	Rifle = { Hip = CFrame.new(0.78, -0.98, -1.3) * ang(0, -2, 0), AdsDist = 1.35, Center = Vector3.new(0, 0.45, -0.8) },
	Launcher = {
		Hip = CFrame.new(0.9, -1.0, -0.85) * ang(0, -2, 0),
		AdsDist = 1.25,
		Center = Vector3.new(0, 0.6, -0.5),
	},
	Pistol = { Hip = CFrame.new(0.7, -0.88, -1.5) * ang(0, -4, 0), AdsDist = 1.8, Center = Vector3.new(0, 0.35, -0.4) },
	Gloves = {
		Hip = CFrame.new(0.78, -0.95, -1.65) * ang(8, 6, -12),
		Center = Vector3.new(0, 0, -0.2),
		Left = CFrame.new(-0.78, -0.95, -1.65) * ang(8, -6, 12),
	},
	Hammer = { Hip = CFrame.new(0.95, -1.4, -1.55) * ang(-38, 12, 12), Center = Vector3.new(0, 1.0, 0) },
	Sword = { Hip = CFrame.new(0.9, -1.3, -1.45) * ang(-42, 8, 18), Center = Vector3.new(0, 0.8, 0) },
	Utility = {
		Hip = CFrame.new(0.72, -0.9, -1.35) * ang(5, -10, 0),
		Center = Vector3.new(0, 0.3, 0),
		Left = CFrame.new(-0.75, -1.45, -1.0) * ang(10, 10, 15),
	},
}

local HOLD_BY_KEY: { [string]: string } = {
	BoxingGloves = "Gloves",
	BonkHammer = "Hammer",
	LaserSword = "Sword",
	PopRocket = "Launcher",
	BlackHoleCannon = "Launcher",
	PopGrenade = "Utility",
	SmokeBomb = "Utility",
	MedFizz = "Utility",
	PipPistol = "Pistol",
	HandCannon = "Pistol",
	MiniScatter = "Pistol",
}

-- Schwung-Keyframes (Zeit relativ zur Dauer)
local function kf(t: number, px: number, py: number, pz: number, rx: number, ry: number, rz: number): Key
	return { T = t, P = Vector3.new(px, py, pz), R = Vector3.new(rx, ry, rz) }
end
local SWINGS: { [string]: { Duration: number, Keys: { Key } } } = {
	Bonk = {
		Duration = 0.85,
		Keys = {
			kf(0, 0, 0, 0, 0, 0, 0),
			kf(0.41, 0, 0.35, 0.3, 55, 0, -10),
			kf(0.59, -0.25, -0.15, -0.7, -75, 10, 15),
			kf(1, 0, 0, 0, 0, 0, 0),
		},
	},
	Slash = {
		Duration = 0.45,
		Keys = {
			kf(0, 0, 0, 0, 0, 0, 0),
			kf(0.25, 0.35, 0.15, 0.1, 20, 40, -60),
			kf(0.55, -0.6, -0.1, -0.5, -20, -50, 70),
			kf(1, 0, 0, 0, 0, 0, 0),
		},
	},
	Throw = {
		Duration = 0.5,
		Keys = {
			kf(0, 0, 0, 0, 0, 0, 0),
			kf(0.3, 0.1, -0.5, 0.3, -30, 10, 20),
			kf(0.7, 0.1, -0.5, 0.3, -30, 10, 20),
			kf(1, 0, 0, 0, 0, 0, 0),
		},
	},
	Drink = {
		Duration = 0.8,
		Keys = {
			kf(0, 0, 0, 0, 0, 0, 0),
			kf(0.3, -0.7, 0.6, 0.85, 70, 0, -20),
			kf(0.82, -0.7, 0.62, 0.85, 75, 0, -20),
			kf(1, 0, 0, 0, 0, 0, 0),
		},
	},
}
local JAB_TIME = 0.32

local INSPECT_KEYS: { { number } } = { -- t, Gier, Roll, "heranholen"
	{ 0, 0, 0, 0 },
	{ 0.15, 55, -25, 1 },
	{ 0.55, 62, -18, 1 },
	{ 0.7, -35, 30, 1 },
	{ 0.85, -38, 28, 1 },
	{ 1, 0, 0, 0 },
}

-- ---------------------------------------------------------------------
-- 2) ZUSTAND
-- ---------------------------------------------------------------------
local container: Model? = nil
local entries: { Entry } = {}
local partList: { BasePart } = {}
local cframeList: { CFrame } = {}
local flashPart: BasePart? = nil
local armParts: { [string]: BasePart } = {}

local weaponKey: string? = nil
local def: any = nil
local holdName = "Rifle"
local hold: Hold = HOLDS.Rifle
local pts: { [string]: CFrame } = {}
local hiddenFor: { [string]: boolean } = {}

local adsAlpha = 0
local blockTarget = false
local blockAlpha = 0
local equipStart = -10
local reloadStart = -10
local reloadDur = 0
local reloadSounds = 0
local inspectStart = -10
local swingKind: string? = nil
local swingStart = -10
local swingDur = 0
local jabLeft = false
local flashUntil = 0
local lastFire = -10

local swaySpring = Spring.new(Vector3.zero, 12, 0.62)
local moveSpring = Spring.new(Vector3.zero, 10, 0.55)
local kickPos = Spring.new(Vector3.zero, 22, 0.65)
local kickRot = Spring.new(Vector3.zero, 20, 0.6)
local charmSpring = Spring.new(Vector3.zero, 9, 0.22)
local bobPhase = 0
local groundAlpha = 1
local sprintAlpha = 0
local slideAlpha = 0
local wallPull = 0
local lastYaw, lastPitch = 0, 0
local hasLastLook = false
local wasGrounded = true
local lastVelY = 0
local muzzleCF: CFrame? = nil
local magLocal: CFrame? = nil
local excludeFor: Model? = nil

local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
wallParams.IgnoreWater = true

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

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function easeOutBack(t: number): number
	t = math.clamp(t, 0, 1)
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

local function around(center: Vector3, cf: CFrame): CFrame
	return CFrame.new(center) * cf * CFrame.new(-center)
end

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function sampleKeys(keys: { Key }, t: number): CFrame
	t = math.clamp(t, 0, 1)
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t <= b.T then
			local u = smooth((t - a.T) / math.max(b.T - a.T, 1e-4))
			local p = a.P:Lerp(b.P, u)
			local r = a.R:Lerp(b.R, u)
			return CFrame.new(p) * ang(r.X, r.Y, r.Z)
		end
	end
	return CFrame.identity
end

local function sfx(role: string, speed: number?)
	call("Sfx", "Play", role, nil, if speed then { Speed = speed } else nil)
end

local function prepPart(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
end

local function holdFor(key: string, d: any): string
	local byKey = HOLD_BY_KEY[key]
	if byKey then
		return byKey
	end
	if type(d) == "table" then
		if d.Kind == "Melee" then
			return "Hammer"
		elseif d.Slot == "Utility" or d.Kind == "Throwable" or d.Kind == "Consumable" then
			return "Utility"
		elseif d.Slot == "Secondary" then
			return "Pistol"
		end
	end
	return "Rifle"
end

local function armColors(): (Color3, Color3)
	local skin = ARM_SKIN_DEFAULT
	local character = player.Character
	if character then
		local colors = character:FindFirstChildOfClass("BodyColors")
		if colors then
			skin = colors.RightArmColor3
		else
			local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
			if hand and hand:IsA("BasePart") then
				skin = hand.Color
			end
		end
	end
	local sleeve = SLEEVE_DEFAULT
	local team = call("WeaponClient", "Team")
	local colors = ctx and ctx.Config and ctx.Config.Colors
	if colors and team == 1 and typeof(colors.TeamA) == "Color3" then
		sleeve = colors.TeamA
	elseif colors and team == 2 and typeof(colors.TeamB) == "Color3" then
		sleeve = colors.TeamB
	end
	return skin, sleeve
end

local function cosmeticModels(): any
	local module = Shared:FindFirstChild("CosmeticModels")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			return result
		end
	end
	return nil
end

local function isHidden(): boolean
	return next(hiddenFor) ~= nil
end

local function applyParent()
	local c = container
	if not c then
		return
	end
	local camera = workspace.CurrentCamera
	local parent: Instance? = if isHidden() then nil else camera
	if c.Parent ~= parent then
		c.Parent = parent
	end
end

-- ---------------------------------------------------------------------
-- 4) AUFBAU
-- ---------------------------------------------------------------------
local function addEntry(part: BasePart, offset: CFrame, group: string)
	if #entries >= MAX_PARTS then
		part:Destroy()
		return
	end
	prepPart(part)
	table.insert(entries, { Part = part, Offset = offset, Group = group })
	table.insert(partList, part)
	table.insert(cframeList, CFrame.identity)
end

-- Waffen-Modell übernehmen: Teile relativ zum Griff, Punkte aus den Attachments
local function adoptWeapon(model: Model, group: string, readPoints: boolean)
	local pivot = model.WorldPivot
	local primary = model.PrimaryPart
	if readPoints and primary then
		table.clear(pts)
		for _, child in ipairs(primary:GetChildren()) do
			if child:IsA("Attachment") then
				pts[child.Name] = pivot:ToObjectSpace(child.WorldCFrame)
			end
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local g = group
			local offset = pivot:ToObjectSpace(d.CFrame)
			if group == "Weapon" and d.Name == "Mag" then
				g = "Mag"
				if magLocal == nil then
					magLocal = offset
				end
			end
			addEntry(d, offset, g)
		elseif d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
end

local function makeArmPart(name: string, color: Color3, size: Vector3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function destroyContainer()
	if container then
		container:Destroy()
	end
	container = nil
	table.clear(entries)
	table.clear(partList)
	table.clear(cframeList)
	table.clear(armParts)
	flashPart = nil
	muzzleCF = nil
	magLocal = nil
end

-- ---------------------------------------------------------------------
-- 5) POSEN
-- ---------------------------------------------------------------------
local function reloadPose(p: number): (CFrame, CFrame, number)
	if p <= 0 or p >= 1 then
		return CFrame.identity, CFrame.identity, 0
	end
	-- Senken (0–0.2), halten, Heben (0.85–1)
	local a = if p < 0.2 then smooth(p / 0.2) elseif p < 0.85 then 1 else 1 - smooth((p - 0.85) / 0.15)
	local pose = around(hold.Center, CFrame.new(0.05 * a, -0.18 * a, 0.12 * a) * ang(12 * a, -10 * a, 28 * a))
	-- Magazin raus (0.2–0.4) und rein (0.4–0.7) – stetig: beide treffen sich unten
	local magPose = CFrame.identity
	if p >= 0.2 and p < 0.4 then
		local m = smooth((p - 0.2) / 0.2)
		magPose = CFrame.new(0, -1.3 * m, 0.15 * m) * ang(-20 * m, 0, 0)
	elseif p >= 0.4 and p < 0.7 then
		local q = 1 - smooth((p - 0.4) / 0.3)
		magPose = CFrame.new(0, -1.3 * q, 0.15 * q) * ang(-20 * q, 0, 0)
	end
	-- Repetieren (0.7–0.85)
	if p >= 0.7 and p < 0.85 then
		local r = math.sin(math.pi * (p - 0.7) / 0.15)
		pose *= CFrame.new(0, 0, 0.1 * r) * ang(6 * r, 0, 0)
	end
	-- linke Hand greift das Magazin (0.15–0.75)
	local w = 0
	if p >= 0.15 and p < 0.75 then
		w = smooth((p - 0.15) / 0.08) * (1 - smooth((p - 0.67) / 0.08))
	end
	return pose, magPose, w
end

local function inspectPose(p: number): CFrame
	if p <= 0 or p >= 1 then
		return CFrame.identity
	end
	local keys = INSPECT_KEYS
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if p <= b[1] then
			local u = smooth((p - a[1]) / (b[1] - a[1]))
			local yaw = a[2] + (b[2] - a[2]) * u
			local roll = a[3] + (b[3] - a[3]) * u
			local bring = a[4] + (b[4] - a[4]) * u
			return CFrame.new(-0.35 * bring, 0.08 * bring, 0.25 * bring) * around(hold.Center, ang(0, yaw, roll))
		end
	end
	return CFrame.identity
end

local function jabPose(p: number): CFrame
	local k = if p < 0.35 then 1 - (1 - p / 0.35) ^ 3 else 1 - smooth((p - 0.35) / 0.65)
	return CFrame.new(0, 0.1 * k, -0.95 * k) * ang(8 * k, 0, 0)
end

-- ---------------------------------------------------------------------
-- 6) BILD-SCHRITT (RenderPriority.Camera + 2)
-- ---------------------------------------------------------------------
local function onRender(dt: number)
	local c = container
	local camera = workspace.CurrentCamera
	if not c or not camera or c.Parent == nil or #partList == 0 then
		muzzleCF = nil
		return
	end
	local now = os.clock()
	local cam = camera.CFrame

	-- Kamera-Drehrate -> Sway
	local look = cam.LookVector
	local yaw, pitch = math.atan2(-look.X, -look.Z), math.asin(math.clamp(look.Y, -1, 1))
	if not hasLastLook then
		hasLastLook = true
		lastYaw, lastPitch = yaw, pitch
	end
	local safeDt = math.max(dt, 1 / 240)
	local yawRate = wrapAngle(yaw - lastYaw) / safeDt
	local pitchRate = (pitch - lastPitch) / safeDt
	lastYaw, lastPitch = yaw, pitch
	local swayScale = 1 - 0.75 * adsAlpha
	swaySpring:SetTarget(
		Vector3.new(math.clamp(pitchRate * 0.012, -0.14, 0.14), math.clamp(yawRate * 0.012, -0.16, 0.16), 0) * swayScale
	)
	local sway = swaySpring:Step(dt)

	-- Bewegung
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local speed, velY, grounded = 0, 0, true
	if humanoid and root and root:IsA("BasePart") then
		local v = root.AssemblyLinearVelocity
		speed = Vector3.new(v.X, 0, v.Z).Magnitude
		velY = v.Y
		grounded = humanoid.FloorMaterial ~= Enum.Material.Air
		if excludeFor ~= character then
			excludeFor = character
			wallParams.ExcludeInstances = { character :: Model, camera }
		end
	end
	if grounded and not wasGrounded then
		moveSpring:Impulse(Vector3.new(0, -math.clamp(-lastVelY * 0.03, 0, 2), 0))
	end
	wasGrounded = grounded
	lastVelY = velY
	local gk = 1 - math.exp(-dt * 10)
	groundAlpha += ((if grounded then 1 else 0) - groundAlpha) * gk

	local sprinting = call("Movement", "IsSprinting") == true
	local sliding = call("Movement", "IsSliding") == true
	local firingRecently = now - lastFire < 0.2
	local sprintWant = sprinting and adsAlpha < 0.1 and not firingRecently and swingKind == nil
	sprintAlpha += ((if sprintWant then 1 else 0) - sprintAlpha) * (1 - math.exp(-dt * 9))
	slideAlpha += ((if sliding then 1 else 0) - slideAlpha) * (1 - math.exp(-dt * 10))

	local bobAmp = math.clamp(speed / 16, 0, 1.7) * groundAlpha * (1 - 0.85 * adsAlpha) * (1 - 0.7 * slideAlpha)
	if speed > 0.5 and grounded then
		bobPhase = (bobPhase + dt * speed * (0.6 + 0.15 * sprintAlpha)) % (math.pi * 4)
	end
	local bob = CFrame.new(math.sin(bobPhase) * 0.035 * bobAmp, math.sin(bobPhase * 2) * 0.03 * bobAmp, 0)
		* ang(0, 0, math.sin(bobPhase) * 1.2 * bobAmp)

	moveSpring:SetTarget(Vector3.new(0, math.clamp(-velY * 0.006, -0.14, 0.14), 0))
	local move = moveSpring:Step(dt)

	-- Kick
	local kp = kickPos:Step(dt)
	local kr = kickRot:Step(dt)

	-- Wand-Rückzug (2.5-Stud-Ray)
	local wallTarget = 0
	local hit = workspace:Raycast(cam.Position, look * WALL_RAY, wallParams)
	if hit then
		wallTarget = math.clamp((WALL_RAY - hit.Distance) / WALL_RAY, 0, 1)
	end
	wallPull += (wallTarget - wallPull) * (1 - math.exp(-dt * 14))

	-- Block
	blockAlpha += ((if blockTarget then 1 else 0) - blockAlpha) * (1 - math.exp(-dt * 16))

	-- Grund-Pose: Hüfte ↔ ADS (Visier auf der Bildmitte)
	local base = hold.Hip
	local sight = pts.Sight
	if hold.AdsDist and sight and adsAlpha > 0 then
		local adsCF = CFrame.new(0, 0, -(hold.AdsDist :: number)) * CFrame.new(-sight.Position)
		base = base:Lerp(adsCF, smooth(adsAlpha))
	end

	-- Animations-Posen
	local pose = CFrame.identity
	local magPose = CFrame.identity
	local leftToMag = 0
	local leftPose = CFrame.identity
	local equipT = (now - equipStart) / EQUIP_TIME
	if equipT < 1 then
		local e = 1 - easeOutBack(equipT)
		pose *= CFrame.new(0, -0.9 * e, 0.25 * e) * ang(-50 * e, 10 * e, 25 * e)
	end
	if reloadDur > 0 then
		local p = (now - reloadStart) / reloadDur
		if p >= 1 then
			reloadDur = 0
		else
			local rp, mp, w = reloadPose(p)
			pose *= rp
			magPose = mp
			leftToMag = w
			if reloadSounds == 0 and p >= 0.25 then
				reloadSounds = 1
				sfx("MagOut")
			elseif reloadSounds == 1 and p >= 0.62 then
				reloadSounds = 2
				sfx("MagIn")
			elseif reloadSounds == 2 and p >= 0.74 then
				reloadSounds = 3
				sfx("Equip", 1.3)
			end
		end
	end
	local inspectP = (now - inspectStart) / INSPECT_TIME
	if inspectP > 0 and inspectP < 1 then
		pose *= inspectPose(inspectP)
	end
	if swingKind then
		local p = (now - swingStart) / math.max(swingDur, 1e-3)
		if p >= 1 then
			swingKind = nil
		elseif swingKind == "Jab" then
			if holdName == "Gloves" and jabLeft then
				leftPose = jabPose(p)
			else
				pose *= jabPose(p)
			end
		else
			local swing = SWINGS[swingKind]
			if swing then
				pose *= around(hold.Center, sampleKeys(swing.Keys, p))
			end
		end
	end
	if blockAlpha > 0.001 then
		local b = blockAlpha
		pose *= CFrame.new(-0.55 * b, 0.35 * b, -0.1 * b) * ang(15 * b, -20 * b, 75 * b)
	end
	-- Sprint-/Rutsch-Pose, Wand-Rückzug
	local sprintPose = CFrame.new(-0.12 * sprintAlpha, -0.12 * sprintAlpha, 0.05 * sprintAlpha)
		* ang(-14 * sprintAlpha, 32 * sprintAlpha, 8 * sprintAlpha)
	local slidePose = ang(0, 0, 12 * slideAlpha)
	local wallPose = CFrame.new(0, -0.1 * wallPull, 0.9 * wallPull) * ang(35 * wallPull, 10 * wallPull, 0)

	local swayCF = ang(math.deg(sway.X), math.deg(sway.Y), math.deg(sway.Y) * 0.6)
		* CFrame.new(-sway.Y * 0.4, sway.X * 0.3, 0)
	local kickCF = CFrame.new(kp.X, kp.Y, kp.Z) * ang(math.deg(kr.X), math.deg(kr.Y), math.deg(kr.Z))
	local shared = sprintPose * slidePose * bob * swayCF * CFrame.new(move) * wallPose

	local weaponCF = cam * base * shared * kickCF * pose
	local magCF = weaponCF * magPose
	local leftCF = if hold.Left then cam * (hold.Left :: CFrame) * shared * leftPose else weaponCF

	-- Charm-Pendel
	charmSpring:SetTarget(
		Vector3.new(math.clamp(-sway.X * 3 + move.Y * 2, -0.9, 0.9), 0, math.clamp(sway.Y * 3, -0.9, 0.9))
	)
	local cs = charmSpring:Step(dt)
	local charmPoint = pts.Charm or CFrame.identity
	local charmCF = weaponCF * charmPoint * ang(math.deg(cs.X), 0, math.deg(cs.Z))

	-- Hände & Arme
	local gripCF = weaponCF * (pts.Grip or CFrame.identity)
	local supportCF = if hold.Left then leftCF else weaponCF * (pts.Support or CFrame.new(0, 0, -0.8))
	if leftToMag > 0 and magLocal then
		local magHand = magCF * (magLocal :: CFrame) * CFrame.new(0, -0.2, 0)
		supportCF = supportCF:Lerp(magHand, leftToMag)
	end
	local rightElbow = (cam * CFrame.new(0.95, -1.95, 0.35)).Position
	local leftElbow = (cam * CFrame.new(-0.75, -1.95, 0.25)).Position

	local function armCF(hand: Vector3, elbow: Vector3, fraction: number): CFrame
		local center = hand + (elbow - hand) * fraction
		if (hand - center).Magnitude < 1e-3 then
			return CFrame.new(center)
		end
		return CFrame.lookAt(center, hand)
	end

	-- Teile füllen
	local flashOn = now < flashUntil
	for i, e in ipairs(entries) do
		local g = e.Group
		local cf: CFrame
		if g == "Mag" then
			cf = magCF * e.Offset
		elseif g == "Left" then
			cf = leftCF * e.Offset
		elseif g == "Charm" then
			cf = charmCF * e.Offset
		elseif g == "Flash" then
			cf = weaponCF * (pts.Muzzle or CFrame.identity) * CFrame.new(0, 0, -0.15)
			local t = if flashOn then 0.05 else 1
			if e.Part.Transparency ~= t then
				e.Part.Transparency = t
			end
		elseif g == "RHand" then
			cf = gripCF
		elseif g == "LHand" then
			cf = supportCF
		elseif g == "RFore" then
			cf = armCF(gripCF.Position, rightElbow, 0.36)
		elseif g == "RSleeve" then
			cf = armCF(gripCF.Position, rightElbow, 0.8)
		elseif g == "LFore" then
			cf = armCF(supportCF.Position, leftElbow, 0.36)
		elseif g == "LSleeve" then
			cf = armCF(supportCF.Position, leftElbow, 0.8)
		else
			cf = weaponCF * e.Offset
		end
		cframeList[i] = cf
	end
	-- Arm-Längen an den Abstand Hand ↔ Ellbogen anpassen (nur bei spürbarer Änderung)
	local function fitArm(foreName: string, sleeveName: string, hand: Vector3, elbow: Vector3)
		local len = math.clamp((elbow - hand).Magnitude, 0.6, 3)
		local fore = armParts[foreName]
		local sleeve = armParts[sleeveName]
		if fore and math.abs(fore.Size.Z - len * 0.72) > 0.05 then
			fore.Size = Vector3.new(fore.Size.X, fore.Size.Y, len * 0.72)
		end
		if sleeve and math.abs(sleeve.Size.Z - len * 0.45) > 0.05 then
			sleeve.Size = Vector3.new(sleeve.Size.X, sleeve.Size.Y, len * 0.45)
		end
	end
	fitArm("RFore", "RSleeve", gripCF.Position, rightElbow)
	fitArm("LFore", "LSleeve", supportCF.Position, leftElbow)

	workspace:BulkMoveTo(partList, cframeList, Enum.BulkMoveMode.FireCFrameChanged)
	muzzleCF = weaponCF * (pts.Muzzle or CFrame.identity)
end

-- ---------------------------------------------------------------------
-- 7) ÖFFENTLICHE API
-- ---------------------------------------------------------------------
function Viewmodel.Equip(key: string, cos: { Skin: string, Wrap: string, Charm: string }?)
	if type(key) ~= "string" or key == "" then
		Viewmodel.Unequip()
		return
	end
	destroyContainer()
	local config = ctx and ctx.Config
	local d: any = nil
	if config and type(config.Weapon) == "function" then
		local ok, result = pcall(config.Weapon, key)
		if ok then
			d = result
		end
	end
	weaponKey = key
	def = d
	holdName = holdFor(key, d)
	hold = HOLDS[holdName] or HOLDS.Rifle
	adsAlpha = 0
	blockTarget = false
	blockAlpha = 0
	reloadDur = 0
	inspectStart = -10
	swingKind = nil
	kickPos.Position, kickPos.Velocity = Vector3.zero, Vector3.zero
	kickRot.Position, kickRot.Velocity = Vector3.zero, Vector3.zero

	local c = Instance.new("Model")
	c.Name = "CC_Viewmodel"
	container = c

	local skin = cos and type(cos.Skin) == "string" and cos.Skin or nil
	local recipeKey = if type(d) == "table"
			and type(d.Model) == "string"
			and WeaponModels.HasRecipe(d.Model)
		then d.Model
		else key
	local cosmetics = cosmeticModels()

	local function buildOne(): Model
		local model = WeaponModels.Build(recipeKey, { Skin = skin, Scale = 1, Viewmodel = true })
		local wrap = cos and type(cos.Wrap) == "string" and cos.Wrap or ""
		if wrap ~= "" and cosmetics and type(cosmetics.ApplyWrap) == "function" then
			pcall(cosmetics.ApplyWrap, model, wrap)
		end
		return model
	end

	local weapon = buildOne()
	weapon.Parent = c
	adoptWeapon(weapon, "Weapon", true)
	if holdName == "Gloves" then
		local second = buildOne()
		second.Name = "Left"
		second.Parent = c
		adoptWeapon(second, "Left", false)
	end

	-- Charm am Charm-Attachment
	local charmId = cos and type(cos.Charm) == "string" and cos.Charm or ""
	if charmId ~= "" and cosmetics and type(cosmetics.BuildCharm) == "function" then
		local ok, charm = pcall(cosmetics.BuildCharm, charmId)
		if ok and typeof(charm) == "Instance" and charm:IsA("Model") then
			charm.Parent = c
			-- Aufhängepunkt: Attachment "Hook" am PrimaryPart (CosmeticModels), sonst der Pivot
			local hook = charm:FindFirstChild("Hook", true)
			local pivot = if hook and hook:IsA("Attachment") then CFrame.new(hook.WorldPosition) else charm:GetPivot()
			for _, part in ipairs(charm:GetDescendants()) do
				if part:IsA("BasePart") then
					addEntry(part, pivot:ToObjectSpace(part.CFrame), "Charm")
				elseif part:IsA("JointInstance") or part:IsA("WeldConstraint") then
					part:Destroy()
				end
			end
		end
	end

	-- Arme (Blöcke in Körperfarbe, Ärmel in Teamfarbe)
	local skinColor, sleeveColor = armColors()
	local arms = Instance.new("Model")
	arms.Name = "Arms"
	arms.Parent = c
	local function arm(name: string, color: Color3, size: Vector3, hidden: boolean)
		local part = makeArmPart(name, color, size)
		if hidden then
			part.Transparency = 1
		end
		part.Parent = arms
		armParts[name] = part
		addEntry(part, CFrame.identity, name)
	end
	local glovesHideHands = holdName == "Gloves"
	arm("RHand", skinColor, Vector3.new(0.34, 0.3, 0.42), glovesHideHands)
	arm("LHand", skinColor, Vector3.new(0.34, 0.3, 0.42), glovesHideHands)
	arm("RFore", skinColor, Vector3.new(0.34, 0.34, 1.2), false)
	arm("LFore", skinColor, Vector3.new(0.34, 0.34, 1.2), false)
	arm("RSleeve", sleeveColor, Vector3.new(0.46, 0.46, 0.8), false)
	arm("LSleeve", sleeveColor, Vector3.new(0.46, 0.46, 0.8), false)

	-- Mündungsblitz (ein Teil, nur Transparenz wird umgeschaltet – keine Instanz pro Schuss)
	if holdName ~= "Gloves" and holdName ~= "Hammer" and holdName ~= "Sword" and holdName ~= "Utility" then
		local flash = Instance.new("Part")
		flash.Name = "Flash"
		flash.Shape = Enum.PartType.Ball
		flash.Size = Vector3.new(0.38, 0.38, 0.38)
		flash.Material = Enum.Material.Neon
		flash.Color = FLASH_COLOR
		flash.Transparency = 1
		flash.Parent = c
		flashPart = flash
		addEntry(flash, CFrame.identity, "Flash")
	end

	equipStart = os.clock()
	hasLastLook = false
	applyParent()
	sfx("Equip")
end

function Viewmodel.Unequip()
	destroyContainer()
	weaponKey = nil
	def = nil
	reloadDur = 0
	swingKind = nil
	blockTarget = false
end

function Viewmodel.Fire()
	if not container then
		return
	end
	local now = os.clock()
	lastFire = now
	inspectStart = -10
	local d = def
	local pitchDeg = if type(d) == "table" and finite(d.RecoilPitch) then d.RecoilPitch else 0.5
	local yawDeg = if type(d) == "table" and finite(d.RecoilYaw) then d.RecoilYaw else 0.15
	local scale = 1 - 0.6 * adsAlpha
	local strength = math.clamp(pitchDeg, 0.1, 5)
	kickPos:Impulse(Vector3.new(0, 0.25 * strength, 3.2 + 1.6 * strength) * scale)
	kickRot:Impulse(
		Vector3.new(
			rad(40 + 22 * strength),
			(math.random() * 2 - 1) * rad(30 * yawDeg),
			(math.random() * 2 - 1) * rad(60 * yawDeg)
		) * scale
	)
	-- Mündungsfeuer: CombatFX, sonst eigener Blitz-Teil
	local fx = modules().CombatFX
	if fx and type(fx.Muzzle) == "function" and muzzleCF and weaponKey then
		pcall(fx.Muzzle, muzzleCF, weaponKey)
	elseif flashPart then
		flashUntil = now + 0.05
	end
end

function Viewmodel.Reload(duration: number)
	if not container or not finite(duration) or duration <= 0 then
		return
	end
	reloadStart = os.clock()
	reloadDur = math.clamp(duration, 0.2, 8)
	reloadSounds = 0
	inspectStart = -10
end

function Viewmodel.CancelReload()
	reloadDur = 0
end

function Viewmodel.Inspect()
	if not container then
		return
	end
	local now = os.clock()
	if reloadDur > 0 or swingKind or adsAlpha > 0.05 or now - equipStart < EQUIP_TIME then
		return
	end
	inspectStart = now
end

function Viewmodel.Swing(kind: string)
	if not container then
		return
	end
	local k = if type(kind) == "string" and (kind == "Jab" or SWINGS[kind] ~= nil) then kind else "Jab"
	inspectStart = -10
	swingKind = k
	swingStart = os.clock()
	if k == "Jab" then
		swingDur = JAB_TIME
		jabLeft = not jabLeft
	else
		local swing = SWINGS[k]
		swingDur = swing.Duration
		if k == "Drink" and type(def) == "table" and type(def.Heal) == "table" and finite(def.Heal.UseTime) then
			swingDur = math.clamp(def.Heal.UseTime, 0.3, 3)
		end
	end
end

function Viewmodel.SetAds(alpha: number)
	adsAlpha = if finite(alpha) then math.clamp(alpha, 0, 1) else 0
	if adsAlpha > 0.05 then
		inspectStart = -10
	end
end

function Viewmodel.SetBlock(on: boolean)
	blockTarget = on == true
	if blockTarget then
		inspectStart = -10
	end
end

function Viewmodel.HideFor(reason: string, on: boolean)
	if type(reason) ~= "string" then
		return
	end
	if on then
		hiddenFor[reason] = true
	else
		hiddenFor[reason] = nil
	end
	applyParent()
end

function Viewmodel.SetHidden(on: boolean)
	Viewmodel.HideFor("External", on == true)
end

function Viewmodel.MuzzleCFrame(): CFrame?
	if not container or container.Parent == nil then
		return nil
	end
	return muzzleCF
end

-- ---------------------------------------------------------------------
-- 8) MODUL-FORM
-- ---------------------------------------------------------------------
function Viewmodel.Init(context: any)
	ctx = context
end

function Viewmodel.Start()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		hasLastLook = false
		applyParent()
	end)
	player.CharacterAdded:Connect(function()
		hasLastLook = false
	end)
	RunService:BindToRenderStep("CC_Viewmodel", Enum.RenderPriority.Camera.Value + 2, onRender)
end

return Viewmodel
