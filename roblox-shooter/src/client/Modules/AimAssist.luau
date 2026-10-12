-- =====================================================================
--  CLUTCH CLASH – Zielhilfe für Touch & Gamepad (Client/Modules/AimAssist)
--  Besitzer: WP4 (Kampf Client). Vertrag: DESIGN.md B15.2, C7.4. Werte: Config.Client.AimAssist.
--  NIE mit Maus: Filter gibt bei "KBM" (oder wenn Controls.Input() "KBM" meldet) die Eingabe unverändert zurück.
--  Nur sichtbare Gegner (Sichtlinien-Ray gegen die Kontext-Map, nicht durch Rauch-Kugeln aus Combat("Smoke")),
--  höchstens Range (70) Studs entfernt.
--    Reibung:      Blick-Eingabe × Friction (0.55), wenn das Fadenkreuz ≤ Cone° (3.5 Gamepad / 4.5 Touch) am Gegner ist
--    Magnetismus:  nur bei Bewegung oder Blick-Eingabe, max. Magnet °/s (4 / 5) zum Torso, kein Einrasten
--    Stärke:       Einstellung AimAssist 0..1 (× RankedMult in Ranked, v1.1)
--
--  Öffentliche API (C7.4):
--    AimAssist.Filter(dt, look: Vector2, input: "Gamepad" | "Touch"): Vector2
--        look = Blick-Änderung dieses Frames in rad, Maus-Konvention (+x rechts, +y runter)
--  Zusätzlich (für WeaponClient: Touch-Auto-Feuer, Admin-Triggerbot):
--    AimAssist.TargetUnderCrosshair(range?): (Model?, ("Head" | "Body")?)   sichtbarer Gegner genau unter dem Fadenkreuz
--    AimAssist.IsVisible(model): boolean
--    AimAssist.SmokeBlocks(a, b): boolean       Strecke a→b läuft durch eine aktive Rauch-Kugel
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Hitbox = require(Shared:WaitForChild("Hitbox"))

local AimAssist = {}

local player = Players.LocalPlayer
local ctx: any = nil

type Smoke = { P: Vector3, R: number, Until: number }

local MAX_SMOKES = 16
local LOS_INTERVAL = 0.1 -- Sichtlinie pro Ziel höchstens 10× pro Sekunde
local DEFAULTS = {
	Gamepad = { Cone = 3.5, Friction = 0.55, Magnet = 4 },
	Touch = { Cone = 4.5, Friction = 0.55, Magnet = 5 },
	Range = 70,
	RankedMult = 0.5,
}

local smokes: { Smoke } = {}
local losCache: { [Model]: { T: number, Visible: boolean } } = setmetatable({}, { __mode = "k" }) :: any
-- Nur IncludeInstances (wie ArenaService.MapParams/WeaponClient): FilterType "Include" mit leerer
-- FilterDescendantsInstances-Liste würde alles herausfiltern
local mapParams = RaycastParams.new()
mapParams.IgnoreWater = true
local mapInstance: Instance? = nil
local ranked = false

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function toYawPitch(look: Vector3): (number, number)
	return math.atan2(-look.X, -look.Z), math.asin(math.clamp(look.Y, -1, 1))
end

local function modules(): { [string]: any }
	return if ctx and type(ctx.Modules) == "table" then ctx.Modules else {}
end

local function config(): any
	local client = ctx and ctx.Config and ctx.Config.Client
	local aa = client and client.AimAssist
	return if type(aa) == "table" then aa else DEFAULTS
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function strength(): number
	local value: any = nil
	local settingsMod = modules().Settings
	if settingsMod and type(settingsMod.Get) == "function" then
		local ok, s = pcall(settingsMod.Get)
		if ok and type(s) == "table" then
			value = s.AimAssist
		end
	end
	if not finite(value) then
		value = 1
	end
	local s = math.clamp(value, 0, 1)
	if ranked then
		local mult = config().RankedMult
		s *= if finite(mult) then mult else 0.5
	end
	return s
end

local function weaponClient(): any
	return modules().WeaponClient
end

local function enemies(): { Model }
	local wc = weaponClient()
	if wc and type(wc.Enemies) == "function" then
		local ok, list = pcall(wc.Enemies)
		if ok and type(list) == "table" then
			return list
		end
	end
	return {}
end

local function headRadius(): number
	local mult = 1
	local wc = weaponClient()
	if wc and type(wc.Rules) == "function" then
		local ok, rules = pcall(wc.Rules)
		if ok and type(rules) == "table" and finite(rules.HeadRadiusMult) then
			mult = rules.HeadRadiusMult
		end
	end
	local combat = ctx and ctx.Config and ctx.Config.Combat
	local base = if combat and finite(combat.HeadRadius) then combat.HeadRadius else 0.8
	return base * mult
end

local function hitTol(): number
	local combat = ctx and ctx.Config and ctx.Config.Combat
	return if combat and finite(combat.HitTol) then combat.HitTol else 0.35
end

local function rootAndHead(model: Model): (BasePart?, BasePart?)
	local root = model:FindFirstChild("HumanoidRootPart")
	local head = model:FindFirstChild("Head")
	if root and root:IsA("BasePart") and head and head:IsA("BasePart") then
		return root, head
	end
	return nil, nil
end

-- ---------------------------------------------------------------------
-- RAUCH (analytische Kugeln, wie beim Server)
-- ---------------------------------------------------------------------
function AimAssist.SmokeBlocks(a: Vector3, b: Vector3): boolean
	if #smokes == 0 then
		return false
	end
	local now = serverNow()
	local seg = b - a
	local len2 = seg:Dot(seg)
	for _, s in ipairs(smokes) do
		if s.Until > now then
			local t = if len2 > 1e-6 then math.clamp((s.P - a):Dot(seg) / len2, 0, 1) else 0
			local closest = a + seg * t
			if (s.P - closest).Magnitude <= s.R then
				return true
			end
		end
	end
	return false
end

local function purgeSmokes()
	local now = serverNow()
	for i = #smokes, 1, -1 do
		if smokes[i].Until <= now then
			table.remove(smokes, i)
		end
	end
end

-- ---------------------------------------------------------------------
-- SICHTLINIE (gegen die Map des Kontexts, gecacht)
-- ---------------------------------------------------------------------
local function lineClear(from: Vector3, to: Vector3): boolean
	if not mapInstance then
		return true
	end
	local dir = to - from
	local dist = dir.Magnitude
	if dist < 0.5 then
		return true
	end
	local hit = workspace:Raycast(from, dir.Unit * math.max(dist - 0.5, 0.1), mapParams)
	return hit == nil
end

function AimAssist.IsVisible(model: Model): boolean
	local root, head = rootAndHead(model)
	local camera = workspace.CurrentCamera
	if not (root and head and camera) then
		return false
	end
	local camPos = camera.CFrame.Position
	if AimAssist.SmokeBlocks(camPos, root.Position) and AimAssist.SmokeBlocks(camPos, head.Position) then
		return false
	end
	local now = os.clock()
	local cached = losCache[model]
	if cached and now - cached.T < LOS_INTERVAL then
		return cached.Visible
	end
	local visible = lineClear(camPos, root.Position) or lineClear(camPos, head.Position)
	losCache[model] = { T = now, Visible = visible }
	return visible
end

-- bester Gegner im Kegel um die Blickrichtung (Torso oder Kopf), sichtbar
local function bestTarget(coneDeg: number, range: number): (Model?, Vector3?)
	local camera = workspace.CurrentCamera
	if not camera then
		return nil, nil
	end
	local camPos = camera.CFrame.Position
	local look = camera.CFrame.LookVector
	local cosCone = math.cos(math.rad(coneDeg))
	local best: Model? = nil
	local bestPoint: Vector3? = nil
	local bestDot = cosCone
	for _, model in ipairs(enemies()) do
		local root, head = rootAndHead(model)
		if root and head then
			local torso = root.Position
			local offset = torso - camPos
			local dist = offset.Magnitude
			if dist > 1 and dist <= range then
				local dot = look:Dot(offset / dist)
				local headOffset = head.Position - camPos
				local headDot = if headOffset.Magnitude > 1 then look:Dot(headOffset.Unit) else -1
				local d = math.max(dot, headDot)
				if d >= bestDot and AimAssist.IsVisible(model) then
					best = model
					bestPoint = torso
					bestDot = d
				end
			end
		end
	end
	return best, bestPoint
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICH
-- ---------------------------------------------------------------------
function AimAssist.Filter(dt: number, look: Vector2, input: "Gamepad" | "Touch"): Vector2
	if typeof(look) ~= "Vector2" then
		return Vector2.zero
	end
	if input ~= "Gamepad" and input ~= "Touch" then
		return look -- nie Maus
	end
	local controls = modules().Controls
	if controls and type(controls.Input) == "function" then
		local ok, kind = pcall(controls.Input)
		if ok and kind == "KBM" and input ~= "Touch" then
			return look
		end
	end
	local wc = weaponClient()
	if not (wc and type(wc.IsArmed) == "function" and wc.IsArmed()) then
		return look
	end
	local s = strength()
	if s <= 0 or not finite(dt) or dt <= 0 then
		return look
	end
	local cfg = config()
	local entry = cfg[input] or DEFAULTS[input]
	local cone = if finite(entry.Cone) then entry.Cone else DEFAULTS[input].Cone
	local friction = if finite(entry.Friction) then math.clamp(entry.Friction, 0, 1) else 0.55
	local magnet = if finite(entry.Magnet) then math.max(entry.Magnet, 0) else DEFAULTS[input].Magnet
	local range = if finite(cfg.Range) then cfg.Range else DEFAULTS.Range

	local target, point = bestTarget(cone, range)
	if not (target and point) then
		return look
	end
	local hadInput = look.Magnitude > 1e-6
	-- Reibung
	local result = look * (1 - (1 - friction) * s)
	-- Magnetismus (nur bei Bewegung oder Blick-Eingabe)
	local moving = false
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.MoveDirection.Magnitude > 0.1 then
		moving = true
	end
	if (moving or hadInput) and magnet > 0 then
		local camera = workspace.CurrentCamera
		if camera then
			local camPos = camera.CFrame.Position
			local tYaw, tPitch = toYawPitch((point - camPos).Unit)
			local cYaw, cPitch = toYawPitch(camera.CFrame.LookVector)
			local pull = Vector2.new(-wrapAngle(tYaw - cYaw), -(tPitch - cPitch))
			local maxStep = math.rad(magnet) * s * dt
			if pull.Magnitude > maxStep then
				pull = pull.Unit * maxStep
			end
			result += pull
		end
	end
	return result
end

function AimAssist.TargetUnderCrosshair(range: number?): (Model?, ("Head" | "Body")?)
	local camera = workspace.CurrentCamera
	if not camera then
		return nil, nil
	end
	local maxRange = if finite(range) then math.clamp(range :: number, 1, 2000) else 300
	local origin = camera.CFrame.Position
	local dir = camera.CFrame.LookVector
	local radius = headRadius()
	local tol = hitTol()
	local best: Model? = nil
	local bestRegion: ("Head" | "Body")? = nil
	local bestDist = maxRange
	for _, model in ipairs(enemies()) do
		local root, head = rootAndHead(model)
		if root and head then
			local region, dist = Hitbox.Ray(origin, dir, bestDist, root.CFrame, head.Position, radius, tol)
			if region and dist and dist <= bestDist then
				local hitPoint = origin + dir * dist
				if lineClear(origin, hitPoint) and not AimAssist.SmokeBlocks(origin, hitPoint) then
					best = model
					bestRegion = region
					bestDist = dist
				end
			end
		end
	end
	return best, bestRegion
end

-- ---------------------------------------------------------------------
-- MODUL-FORM
-- ---------------------------------------------------------------------
local function onArmed(info: any)
	if type(info) ~= "table" then
		return
	end
	table.clear(smokes)
	table.clear(losCache)
	local map = info.Map
	if typeof(map) == "Instance" then
		mapInstance = map
		mapParams.IncludeInstances = { map }
	else
		mapInstance = nil
	end
	local rules = info.Rules
	ranked = type(rules) == "table" and rules.Ranked == true
end

local function onDisarmed()
	table.clear(smokes)
	table.clear(losCache)
	mapInstance = nil
	ranked = false
end

function AimAssist.Init(context: any)
	ctx = context
end

function AimAssist.Start()
	local hooks = ctx and ctx.Hooks
	if not (hooks and type(hooks.On) == "function") then
		return
	end
	hooks.On("Armed", onArmed)
	hooks.On("Disarmed", onDisarmed)
	hooks.On("Combat:Smoke", function(data: any)
		if type(data) ~= "table" or typeof(data.P) ~= "Vector3" or not finite(data.R) or not finite(data.Until) then
			return
		end
		purgeSmokes()
		if #smokes >= MAX_SMOKES then
			table.remove(smokes, 1)
		end
		table.insert(smokes, { P = data.P, R = math.clamp(data.R, 0, 60), Until = data.Until })
	end)
end

return AimAssist
