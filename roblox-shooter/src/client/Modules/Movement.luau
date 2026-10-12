-- =====================================================================
--  CLUTCH CLASH – Bewegung: Sprint, Rutschen, Rutsch-Sprung, Doppelsprung, Schwerkraft-Lift, Impulse
--  (Client/Modules/Movement)
--  Besitzer: WP4 (Kampf Client). Vertrag: DESIGN.md B12, C7.4, C12.3 (Budget), SKILL-WUENSCHE (Slide-Hop).
--  Bewegung läuft auf dem Client (eigene Physik, Netzwerk-Besitzer). Werte aus Config.Player.
--    Gehen    = BaseSpeed (Server-Attribut) × MoveMult der Waffe (× AdsMoveMult beim Zielen, × Block 0.65)
--    Sprinten = BaseSpeed × Sprint/Walk × MoveMult; kein Schießen (WeaponClient ruft StopSprint, 0.12 s Sperre)
--    Rutschen = aus Sprint (Tempo ≥ 18) + Rutsch-Taste: 32 -> exponentiell 14 in 0.75 s, Kamera −1.6, FOV +6,
--               Cooldown 1.0 s. KEINE Hitbox-Änderung. Lokaler Staub-Trail.
--    Rutsch-Sprung: Sprung im Rutschen behält 90 % horizontal (max. 30).
--    Slide-Hop: Landen mit gehaltener/kurz zuvor gedrückter Rutsch-Taste kettet ein neues Rutschen mit dem
--               mitgebrachten Tempo (ohne Cooldown, ohne Auffüllen – Obergrenze JumpCap, klingt ab).
--    Luftsteuerung: Schwung bleibt in der Luft, Richtung begrenzt lenkbar (Air-Strafe) – auch bei normalen
--               Sprüngen: Lenken AIR_STRAFE_TURN °/s, Gegenlenken bremst, ohne Eingabe bleibt der Schwung.
--    Wand-Absprung: Sprung-Taste in der Luft an einer Wand (≤ 2.6 Studs) = einmal pro Luftzeit weg von der
--               Wand + WALL_KICK_HEIGHT hoch (≤ 26 Studs/s horizontal).
--    Kante hochziehen (Mantle): in der Luft gegen niedrige Deckung (Kante 1.0–2.6 Studs über den Füßen,
--               Platz darüber) -> einmal pro Luftzeit sauber hoch. Der HRP bleibt dabei über der Kante (Noclip-Prüfung).
--    Doppelsprung: nur mit Melee.AirJump (BoxingGloves): 1 Luftsprung Höhe 6, Richtung neu wählbar.
--    GravityLift: VectorForce hebt den Anteil frac der Schwerkraft auf (Mutatoren, z. B. MoonJump).
--  Budget des Anti-Cheats (C12.3): 32 × SpeedMult × 1.15 + 6 – Rutschen (32) und Slide-Hop (≤ 30) bleiben darunter.
--  Höhe: Config.Security.SkillAirJumps = 2 erlaubt Sprung + Wand-Absprung + Doppelsprung (7.2 × 3 + 3 Studs).
--
--  Öffentliche API (C7.4):
--    Movement.ApplyImpulse(v: Vector3)     Rückstoß/Raketensprung (auch aus Combat("Impulse"))
--    Movement.SetGravityLift(frac: number) 0..0.95
--    Movement.IsSliding(): boolean
--  Zusätzlich: Movement.IsSprinting(), Movement.StopSprint(), Movement.IsAirborne(), Movement.Speed()
-- =====================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Movement = {}

local player = Players.LocalPlayer
local ctx: any = nil

-- Air = Schwung eines normalen Sprungs/Wand-Absprungs (begrenzte Luftsteuerung, endet bei der Landung,
-- kettet kein Rutschen); sonst Rutsch-Sprung/Impuls-Schwung (Slide-Hop möglich)
type Carry = { Dir: Vector3, Speed: number, Air: boolean? }

-- ---------------------------------------------------------------------
-- 1) KONSTANTEN (Startwerte = Config.Player, zur Laufzeit von dort gelesen)
-- ---------------------------------------------------------------------
local DEFAULT_PLAYER = {
	Walk = 16,
	Sprint = 22,
	JumpHeight = 7.2,
	AirJumpHeight = 6,
	SprintToFire = 0.12,
	Slide = {
		MinSpeed = 18,
		Start = 32,
		End = 14,
		Time = 0.75,
		Cooldown = 1.0,
		JumpKeep = 0.9,
		JumpCap = 30,
		CamDrop = 1.6,
		FovKick = 6,
		SpreadAdd = 1,
	},
}
local SLIDE_DECAY = math.log(20) -- nach Time s sind 95 % des Überschusses weg
local SLIDE_BUFFER = 0.15 -- Rutsch-Taste so lange vorher gedrückt zählt noch
local HOP_WINDOW = 0.2 -- Slide-Hop: Taste bis zu 0.2 s vor der Landung
local GROUND_CARRY = 0.12 -- so lange bleibt der Schwung nach der Landung (Zeit für den Hop)
local COYOTE = 0.12 -- Rutsch-Sprung kurz nach Rutsch-Ende
local SLIDE_TURN = math.rad(70) -- rad/s Lenken im Rutschen
local AIR_TURN = math.rad(150) -- rad/s Luftsteuerung
local AIR_DRAG = 0.18 -- 1/s Abbau des Schwungs in der Luft
local AIR_JUMP_DELAY = 0.1 -- Luftsprung frühestens 0.1 s nach dem Abheben
local AIR_STRAFE_TURN = math.rad(260) -- rad/s Lenken bei normalen Sprüngen (Roblox-Standard: sofort)
local AIR_BRAKE = 40 -- Studs/s² Abbremsen beim Gegenlenken in der Luft
local AIR_ACCEL = 40 -- Studs/s² Beschleunigen in der Luft bis Gehtempo (Sprung aus dem Stand)
local AIR_FREE_SPEED = 6 -- darunter ist kaum Schwung da: Richtung frei
local WALL_KICK_REACH = 2.6 -- Abstand HRP-Mitte -> Wand
local WALL_KICK_HEIGHT = 5 -- Studs hoch
local WALL_KICK_OUT = 18 -- Studs/s weg von der Wand
local WALL_KICK_KEEP = 0.85 -- Anteil des Tempos entlang der Wand
local WALL_KICK_MAX = 26 -- horizontale Obergrenze (Anti-Cheat-Budget 42.8)
local MANTLE_REACH = 2.2 -- Wand vor den Beinen (ab HRP-Mitte)
local MANTLE_MIN = 1.0 -- Kante mindestens so hoch über den Füßen (darunter: normaler Schritt)
local MANTLE_MAX = 2.6 -- höchstens: HRP-Mitte (Füße + ~3) bleibt über der Kante
local MANTLE_CLEAR = 1.2 -- so weit über die Kante heben
local MANTLE_FORWARD = 10 -- Studs/s nach vorn auf die Deckung
local IMPULSE_MAX = 95
local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

-- ---------------------------------------------------------------------
-- 2) ZUSTAND
-- ---------------------------------------------------------------------
local armed = false
local haveArmed = false -- Combat("Armed") erhalten
local rules: { [string]: any } = {}
local character: Model? = nil
local humanoid: Humanoid? = nil
local root: BasePart? = nil
local liftForce: VectorForce? = nil
local dust: ParticleEmitter? = nil

local gravityLift = 0
local sprintHeld = false
local sprintToggled = false
local sprinting = false
local sprintSuppressUntil = 0
local slideHeld = false
local slideQueuedAt = -10
local sliding = false
local slideStart = -10
local slideS0 = 32
local slideDir = Vector3.new(0, 0, -1)
local slideSpeed = 0
local lastSlideStart = -10
local slideEndAt = -10
local slideSpeedAtEnd = 0
local carry: Carry? = nil
local airJumpsUsed = 0
local wallKickUsed = false
local mantleUsed = false
local wasGrounded = true
local leftGroundAt = -10
local landedAt = -10
local lastJumpReq = -10
local camDropAlpha = 0
local appliedWalk: number? = nil
local appliedJump: number? = nil
local restored = true
local moveParams = RaycastParams.new() -- Wand-/Kanten-Strahlen (ohne eigene Figur und Kamera)
moveParams.FilterType = Enum.RaycastFilterType.Exclude
moveParams.IgnoreWater = true

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

local function cfgPlayer(): any
	local p = ctx and ctx.Config and ctx.Config.Player
	return if type(p) == "table" then p else DEFAULT_PLAYER
end

local function cfgNum(tbl: any, key: string, default: number): number
	local value = if type(tbl) == "table" then tbl[key] else nil
	return if finite(value) then value else default
end

local function slideCfg(key: string): number
	local p = cfgPlayer()
	return cfgNum(p.Slide, key, (DEFAULT_PLAYER.Slide :: any)[key])
end

local function setting(key: string): any
	local mod = modules().Settings
	if mod and type(mod.Get) == "function" then
		local ok, s = pcall(mod.Get)
		if ok and type(s) == "table" then
			return s[key]
		end
	end
	return nil
end

local function horizontal(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatLook(): Vector3
	local camera = workspace.CurrentCamera
	local look = if camera then horizontal(camera.CFrame.LookVector) else Vector3.new(0, 0, -1)
	return if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
end

-- Richtung a mit höchstens maxAngle (rad) zu b drehen (beide horizontal, Einheitsvektoren)
local function turnToward(a: Vector3, b: Vector3, maxAngle: number): Vector3
	local dot = math.clamp(a:Dot(b), -1, 1)
	local angle = math.acos(dot)
	if angle <= maxAngle or angle < 1e-4 then
		return b
	end
	local t = maxAngle / angle
	local mixed = a:Lerp(b, t)
	if mixed.Magnitude < 1e-3 then
		return a
	end
	return mixed.Unit
end

local function currentDef(): any
	local wc = modules().WeaponClient
	if wc and type(wc.Current) == "function" then
		local ok, _key, d = pcall(wc.Current)
		if ok and type(d) == "table" then
			return d
		end
	end
	return nil
end

local function adsAlpha(): number
	local value = call("WeaponClient", "AdsAlpha")
	return if finite(value) then math.clamp(value, 0, 1) else 0
end

local function isFlying(h: Humanoid): boolean
	return h.PlatformStand or h.Sit or player:GetAttribute("Flying") == true
end

-- BaseSpeed setzt der Server als Attribut (CharacterService.SetBaseSpeed); Admin-Kraft AdminSpeed zählt
local function baseSpeed(): number
	if player:GetAttribute("IsAdmin") == true then
		local admin = player:GetAttribute("AdminSpeed")
		if finite(admin) then
			return math.clamp(admin, 1, 150)
		end
	end
	local value = character and character:GetAttribute("BaseSpeed")
	if not finite(value) then
		value = player:GetAttribute("BaseSpeed")
	end
	if finite(value) then
		return math.clamp(value :: number, 1, 150)
	end
	local walk = cfgNum(cfgPlayer(), "Walk", 16)
	local mult = if finite(rules.SpeedMult) then rules.SpeedMult else 1
	return walk * mult
end

local function jumpHeight(): number
	if player:GetAttribute("IsAdmin") == true then
		local admin = player:GetAttribute("AdminJump")
		if finite(admin) then
			return math.clamp(admin, 0, 100)
		end
	end
	return cfgNum(cfgPlayer(), "JumpHeight", 7.2)
end

local function airJumpsAllowed(): number
	local d = currentDef()
	if d and type(d.Melee) == "table" and d.Melee.AirJump == true then
		return 1
	end
	if finite(rules.AirJumps) then
		return math.clamp(math.floor(rules.AirJumps), 0, 3)
	end
	return 0
end

-- ---------------------------------------------------------------------
-- 4) CHARACTER-TEILE (Lift-Kraft, Staub)
-- ---------------------------------------------------------------------
local function attachCharacter(char: Model)
	character = char
	local camera = workspace.CurrentCamera
	moveParams.ExcludeInstances = if camera then { char, camera } else { char }
	humanoid = nil
	root = nil
	liftForce = nil
	dust = nil
	appliedWalk = nil
	appliedJump = nil
	sliding = false
	carry = nil
	task.spawn(function()
		local h = char:WaitForChild("Humanoid", 10)
		local r = char:WaitForChild("HumanoidRootPart", 10)
		if character ~= char or not (h and h:IsA("Humanoid") and r and r:IsA("BasePart")) then
			return
		end
		humanoid = h
		root = r
		h.UseJumpPower = false
		local attachment = Instance.new("Attachment")
		attachment.Name = "CC_MoveAtt"
		attachment.Parent = r
		local force = Instance.new("VectorForce")
		force.Name = "CC_Lift"
		force.Attachment0 = attachment
		force.RelativeTo = Enum.ActuatorRelativeTo.World
		force.ApplyAtCenterOfMass = true
		force.Force = Vector3.zero
		force.Enabled = false
		force.Parent = r
		liftForce = force
		local feet = Instance.new("Attachment")
		feet.Name = "CC_DustAtt"
		feet.Position = Vector3.new(0, -2.6, 0.4)
		feet.Parent = r
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "CC_SlideDust"
		emitter.Texture = DUST_TEXTURE
		emitter.Color = ColorSequence.new(Color3.fromRGB(240, 232, 220))
		emitter.Lifetime = NumberRange.new(0.35, 0.6)
		emitter.Speed = NumberRange.new(2, 5)
		emitter.SpreadAngle = Vector2.new(35, 35)
		emitter.EmissionDirection = Enum.NormalId.Back
		emitter.Size = NumberSequence.new(0.6, 1.8)
		emitter.Transparency = NumberSequence.new(0.35, 1)
		emitter.Rate = 40
		emitter.Enabled = false
		emitter.Parent = feet
		dust = emitter
	end)
end

-- ---------------------------------------------------------------------
-- 5) RUTSCHEN
-- ---------------------------------------------------------------------
local function startSlide(now: number, s0: number, chained: boolean)
	local r = root
	if not r then
		return
	end
	local vel = horizontal(r.AssemblyLinearVelocity)
	local dir = if vel.Magnitude > 2 then vel.Unit else flatLook()
	sliding = true
	slideStart = now
	slideDir = dir
	slideS0 = math.clamp(s0, slideCfg("End"), math.max(slideCfg("Start"), slideCfg("JumpCap")))
	slideSpeed = slideS0
	if not chained then
		lastSlideStart = now
	end
	slideQueuedAt = -10
	carry = nil
	sprinting = false
	local v = r.AssemblyLinearVelocity
	r.AssemblyLinearVelocity = Vector3.new(dir.X * slideS0, math.min(v.Y, 0), dir.Z * slideS0)
	call("Sfx", "Play", "MeleeSwing", nil, { Volume = 0.35, Speed = 0.7 })
end

local function endSlide(now: number)
	if not sliding then
		return
	end
	sliding = false
	slideEndAt = now
	slideSpeedAtEnd = slideSpeed
end

local function wantsSlide(now: number): boolean
	return now - slideQueuedAt <= SLIDE_BUFFER
end

-- ---------------------------------------------------------------------
-- 5b) WAND & KANTE (Wand-Absprung, Mantle) – nur feste Map-Teile, nie Figuren
-- ---------------------------------------------------------------------
local function solid(part: Instance): boolean
	if not part:IsA("BasePart") or not part.CanCollide then
		return false
	end
	local model = part:FindFirstAncestorOfClass("Model")
	return not (model and (model:FindFirstChildOfClass("Humanoid") or model:GetAttribute("CombatantId") ~= nil))
end

-- nächste fast senkrechte Wand um den HRP (horizontale Normale) oder nil
local function wallNormal(r: BasePart, h: Humanoid): Vector3?
	local look = flatLook()
	local right = Vector3.new(-look.Z, 0, look.X)
	local dirs = { look, -look, right, -right }
	local md = horizontal(h.MoveDirection)
	if md.Magnitude > 0.1 then
		table.insert(dirs, 1, md.Unit)
	end
	local flat = horizontal(r.AssemblyLinearVelocity)
	if flat.Magnitude > 1 then
		table.insert(dirs, 1, flat.Unit)
	end
	local best: Vector3? = nil
	local bestDist = math.huge
	for _, dir in ipairs(dirs) do
		local hit = workspace:Raycast(r.Position, dir * WALL_KICK_REACH, moveParams)
		if hit and math.abs(hit.Normal.Y) < 0.35 and solid(hit.Instance) and hit.Distance < bestDist then
			local n = horizontal(hit.Normal)
			if n.Magnitude > 0.1 then
				best = n.Unit
				bestDist = hit.Distance
			end
		end
	end
	return best
end

-- Kante hochziehen: true, wenn ausgelöst
local function tryMantle(h: Humanoid, r: BasePart, md: Vector3): boolean
	if md.Magnitude < 0.1 then
		return false
	end
	local fwd = md.Unit
	if fwd:Dot(flatLook()) < 0.3 then
		return false -- nur nach vorn (kein versehentliches Hochziehen beim Rückwärtslaufen)
	end
	local vel = r.AssemblyLinearVelocity
	if vel.Y < -30 then
		return false -- fällt schon zu schnell
	end
	-- Füße: R15 = HRP-Hälfte + HipHeight; R6 (toleriert) hat HipHeight 0 -> Beine 2 Studs
	local legs0 = if h.RigType == Enum.HumanoidRigType.R6 then 2 else h.HipHeight
	local feetY = r.Position.Y - (r.Size.Y / 2 + legs0)
	-- 1) Wand vor den Beinen
	local legs = Vector3.new(r.Position.X, feetY + 0.9, r.Position.Z)
	local wall = workspace:Raycast(legs, fwd * MANTLE_REACH, moveParams)
	if not wall or math.abs(wall.Normal.Y) > 0.35 or not solid(wall.Instance) then
		return false
	end
	-- 2) Oberkante knapp hinter der Vorderseite (von oben nach unten)
	local probe = wall.Position + fwd * 0.6
	local top = feetY + MANTLE_MAX + 0.6
	local down =
		workspace:Raycast(Vector3.new(probe.X, top, probe.Z), Vector3.new(0, -(MANTLE_MAX + 0.4), 0), moveParams)
	if not down or down.Normal.Y < 0.7 or not solid(down.Instance) then
		return false
	end
	local rise = down.Position.Y - feetY
	if rise < MANTLE_MIN or rise > MANTLE_MAX then
		return false
	end
	-- 3) Platz: über der Kante frei (Kopf) und die Wand endet wirklich (kein Hochziehen an hohen Wänden)
	if workspace:Raycast(down.Position + Vector3.new(0, 0.2, 0), Vector3.new(0, 5, 0), moveParams) then
		return false
	end
	local above = Vector3.new(r.Position.X, down.Position.Y + 1.5, r.Position.Z)
	if workspace:Raycast(above, fwd * (MANTLE_REACH + 0.8), moveParams) then
		return false
	end
	local g = workspace.Gravity * (1 - gravityLift)
	local vy = math.sqrt(2 * math.max(g, 1) * (rise + MANTLE_CLEAR))
	local speed = math.max(horizontal(vel).Magnitude, MANTLE_FORWARD)
	r.AssemblyLinearVelocity = Vector3.new(fwd.X * speed, math.max(vel.Y, vy), fwd.Z * speed)
	carry = { Dir = fwd, Speed = speed, Air = true }
	call("Sfx", "Play", "MeleeSwing", nil, { Volume = 0.3, Speed = 0.9 })
	return true
end

-- ---------------------------------------------------------------------
-- 6) SPRUNG-ANFRAGE (Rutsch-Sprung, Wand-Absprung, Doppelsprung)
-- ---------------------------------------------------------------------
local function onJumpRequest()
	local h, r = humanoid, root
	if not (armed and h and r) or isFlying(h) then
		return
	end
	local now = os.clock()
	if now - lastJumpReq < 0.18 then
		return
	end
	lastJumpReq = now
	local grounded = h.FloorMaterial ~= Enum.Material.Air
	local fromSlide = sliding or (now - slideEndAt <= COYOTE and slideSpeedAtEnd > 0)
	if grounded and fromSlide then
		-- Rutsch-Sprung: 90 % horizontal behalten (max. 30); den Sprung selbst macht der Humanoid
		local speed = if sliding then slideSpeed else slideSpeedAtEnd
		local keep = math.min(speed * slideCfg("JumpKeep"), slideCfg("JumpCap"))
		endSlide(now)
		slideSpeedAtEnd = 0
		carry = { Dir = slideDir, Speed = keep }
		landedAt = now -- Boden-Fenster, bis der Humanoid abhebt
		local v = r.AssemblyLinearVelocity
		r.AssemblyLinearVelocity = Vector3.new(slideDir.X * keep, v.Y, slideDir.Z * keep)
		return
	end
	-- Wand-Absprung: einmal pro Luftzeit, vor dem Doppelsprung
	if not grounded and not wallKickUsed and now - leftGroundAt >= AIR_JUMP_DELAY then
		local n = wallNormal(r, h)
		-- nur bewusst: in die Wand gedrückt oder auf sie zu geflogen (nicht beim Entlanglaufen mit gehaltenem Sprung)
		local pushing = n ~= nil
			and (horizontal(r.AssemblyLinearVelocity):Dot(-n) > 2 or horizontal(h.MoveDirection):Dot(-n) > 0.3)
		if n and pushing then
			wallKickUsed = true
			endSlide(now)
			local g = workspace.Gravity * (1 - gravityLift)
			local vy = math.sqrt(2 * math.max(g, 1) * WALL_KICK_HEIGHT)
			local flat = horizontal(r.AssemblyLinearVelocity)
			local along = flat - n * flat:Dot(n)
			local out = along * WALL_KICK_KEEP + n * WALL_KICK_OUT
			if out.Magnitude > WALL_KICK_MAX then
				out = out.Unit * WALL_KICK_MAX
			end
			r.AssemblyLinearVelocity = Vector3.new(out.X, vy, out.Z)
			if out.Magnitude > 0.1 then
				carry = { Dir = out.Unit, Speed = out.Magnitude, Air = true }
			end
			call("Sfx", "Play", "MeleeSwing", nil, { Volume = 0.4, Speed = 1.2 })
			return
		end
	end
	if not grounded and now - leftGroundAt >= AIR_JUMP_DELAY and airJumpsUsed < airJumpsAllowed() then
		airJumpsUsed += 1
		local g = workspace.Gravity * (1 - gravityLift)
		local vy = math.sqrt(2 * math.max(g, 1) * cfgNum(cfgPlayer(), "AirJumpHeight", 6))
		local v = r.AssemblyLinearVelocity
		local flat = horizontal(v)
		local md = horizontal(h.MoveDirection)
		local speed = math.max(flat.Magnitude, h.WalkSpeed)
		local newFlat = if md.Magnitude > 0.1 then md.Unit * speed else flat
		r.AssemblyLinearVelocity = Vector3.new(newFlat.X, vy, newFlat.Z)
		local c = carry
		if c and newFlat.Magnitude > 0.1 then
			c.Dir = newFlat.Unit
			if c.Air then
				c.Speed = newFlat.Magnitude -- Doppelsprung wählt Richtung UND Tempo neu (Ausweich-Tool)
			end
		end
		call("Sfx", "Play", "MeleeSwing", nil, { Volume = 0.4, Speed = 1.4 })
	end
end

-- ---------------------------------------------------------------------
-- 7) PHYSIK-SCHRITT (PreSimulation: nach dem ControlModule, vor der Physik)
-- ---------------------------------------------------------------------
local function setWalk(h: Humanoid, value: number)
	if appliedWalk == nil or math.abs((appliedWalk :: number) - value) > 0.01 then
		appliedWalk = value
		h.WalkSpeed = value
	end
end

local function restoreDefaults()
	local h = humanoid
	if h then
		h.WalkSpeed = cfgNum(cfgPlayer(), "Walk", 16)
		h.JumpHeight = cfgNum(cfgPlayer(), "JumpHeight", 7.2)
		h.CameraOffset = Vector3.zero
	end
	appliedWalk = nil
	appliedJump = nil
	sliding = false
	carry = nil
	sprinting = false
	sprintToggled = false
	camDropAlpha = 0
	if liftForce then
		liftForce.Enabled = false
	end
	if dust then
		dust.Enabled = false
	end
	call("FpsCamera", "SetFovOffset", "Slide", 0)
	restored = true
end

local function step(dt: number)
	local h, r = humanoid, root
	if not (h and r) or h.Health <= 0 then
		return
	end
	if not armed then
		if not restored then
			restoreDefaults()
		end
		return
	end
	restored = false
	if isFlying(h) then
		return
	end
	local now = os.clock()
	local grounded = h.FloorMaterial ~= Enum.Material.Air
	if grounded and not wasGrounded then
		landedAt = now
		airJumpsUsed = 0
		wallKickUsed = false
		mantleUsed = false
		local c = carry
		if c and c.Air then
			carry = nil -- normaler Sprung: am Boden gilt wieder die normale Steuerung
		elseif c then
			-- Slide-Hop: Rutsch-Taste gehalten oder kurz vor der Landung gedrückt
			if slideHeld or now - slideQueuedAt <= HOP_WINDOW then
				startSlide(now, math.min(c.Speed, slideCfg("JumpCap")), true)
			end
		end
	elseif not grounded and wasGrounded then
		leftGroundAt = now
		-- normaler Sprung/Kante: Schwung mitnehmen (begrenzte Luftsteuerung statt Roblox-Sofortlenkung)
		if carry == nil and not sliding then
			local flat = horizontal(r.AssemblyLinearVelocity)
			carry = {
				Dir = if flat.Magnitude > 0.5 then flat.Unit else flatLook(),
				Speed = flat.Magnitude,
				Air = true,
			}
		end
	end
	wasGrounded = grounded

	-- Kante hochziehen (einmal pro Luftzeit)
	if not grounded and not mantleUsed and not sliding and now - leftGroundAt > 0.05 then
		if tryMantle(h, r, horizontal(h.MoveDirection)) then
			mantleUsed = true
		end
	end

	-- Tempo-Werte
	local d = currentDef()
	local moveMult = if d and finite(d.MoveMult) then d.MoveMult else 1
	local adsMult = if d and finite(d.AdsMoveMult) then d.AdsMoveMult else 1
	local ads = adsAlpha()
	local blocking = call("WeaponClient", "IsBlocking") == true
	local blockMult = 1
	if blocking and d and type(d.Melee) == "table" and type(d.Melee.Block) == "table" then
		blockMult = cfgNum(d.Melee.Block, "MoveMult", 0.65)
	end
	local p = cfgPlayer()
	local base = baseSpeed()
	local walk = base * moveMult * (1 + (adsMult - 1) * ads) * blockMult
	local sprintSpeed = base * (cfgNum(p, "Sprint", 22) / math.max(cfgNum(p, "Walk", 16), 1)) * moveMult

	-- Sprint-Absicht
	local md = horizontal(h.MoveDirection)
	local forward = md.Magnitude > 0.1 and md.Unit:Dot(flatLook()) > 0.5
	local touchAuto = call("Controls", "Input") == "Touch" and h.MoveDirection.Magnitude >= 0.9
	local intent = sprintHeld or sprintToggled or touchAuto
	if ads > 0.05 or blocking then
		sprintToggled = false
		intent = false
	end
	sprinting = intent and forward and not sliding and now >= sprintSuppressUntil

	-- Rutschen starten
	if not sliding and grounded and wantsSlide(now) then
		local speedNow = horizontal(r.AssemblyLinearVelocity).Magnitude
		-- "aus Sprint (Tempo ≥ 18)": Schwelle skaliert mit langsameren Mutatoren (BaseSpeed < Walk)
		local minSlide = slideCfg("MinSpeed") * math.min(1, base / math.max(cfgNum(p, "Walk", 16), 1)) - 0.5
		if (sprinting or carry ~= nil) and speedNow >= minSlide and now - lastSlideStart >= slideCfg("Cooldown") then
			startSlide(now, slideCfg("Start"), false)
		end
	end

	if sliding then
		local e = now - slideStart
		local finish = slideCfg("End")
		local duration = math.max(slideCfg("Time"), 0.1)
		slideSpeed = finish + (slideS0 - finish) * math.exp(-SLIDE_DECAY / duration * e)
		if md.Magnitude > 0.1 then
			slideDir = turnToward(slideDir, md.Unit, SLIDE_TURN * dt)
		end
		if e >= duration then
			endSlide(now)
		elseif not grounded and now - leftGroundAt > 0.15 then
			-- über eine Kante gerutscht: Schwung in die Luft mitnehmen
			carry = { Dir = slideDir, Speed = slideSpeed }
			endSlide(now)
		else
			setWalk(h, slideSpeed)
			h:Move(slideDir, false)
		end
	end
	if not sliding then
		local c = carry
		if c and c.Air then
			if grounded then
				carry = nil
			else
				-- Air-Strafe: lenkbar, aber begrenzt; Gegenlenken bremst; ohne Eingabe bleibt der Schwung
				if md.Magnitude > 0.1 then
					local wish = md.Unit
					if c.Speed < AIR_FREE_SPEED then
						c.Dir = wish
						c.Speed = math.min(walk, c.Speed + AIR_ACCEL * dt)
					elseif c.Dir:Dot(wish) < -0.3 then
						c.Speed = math.max(0, c.Speed - AIR_BRAKE * dt)
					else
						c.Dir = turnToward(c.Dir, wish, AIR_STRAFE_TURN * dt)
						if c.Speed < walk then
							c.Speed = math.min(walk, c.Speed + AIR_ACCEL * dt)
						end
					end
				else
					c.Speed *= math.exp(-AIR_DRAG * dt)
				end
				setWalk(h, math.min(c.Speed, IMPULSE_MAX))
				h:Move(c.Dir, false)
			end
		elseif c then
			if grounded and now - landedAt > GROUND_CARRY then
				carry = nil
			else
				if not grounded then
					c.Speed *= math.exp(-AIR_DRAG * dt)
				end
				if md.Magnitude > 0.1 then
					c.Dir = turnToward(c.Dir, md.Unit, AIR_TURN * dt)
				end
				if c.Speed <= walk + 0.5 then
					-- Schwung aufgebraucht: in der Luft weiter mit begrenzter Luftsteuerung, am Boden normal
					carry = if grounded then nil else { Dir = c.Dir, Speed = c.Speed, Air = true }
				else
					setWalk(h, math.min(c.Speed, IMPULSE_MAX))
					h:Move(c.Dir, false)
				end
			end
		end
		if carry == nil then
			setWalk(h, if sprinting then sprintSpeed else walk)
		end
	end

	-- Sprunghöhe
	local jh = jumpHeight()
	if appliedJump == nil or math.abs((appliedJump :: number) - jh) > 0.01 then
		appliedJump = jh
		h.UseJumpPower = false
		h.JumpHeight = jh
	end

	-- Kamera −1.6 beim Rutschen (CameraOffset), FOV +6
	local target = if sliding then 1 else 0
	camDropAlpha += (target - camDropAlpha) * (1 - math.exp(-dt * 14))
	local offset = Vector3.new(0, -slideCfg("CamDrop") * camDropAlpha, 0)
	if (h.CameraOffset - offset).Magnitude > 0.005 then
		h.CameraOffset = offset
	end
	call("FpsCamera", "SetFovOffset", "Slide", if sliding then slideCfg("FovKick") else 0)

	-- Schwerkraft-Lift
	local force = liftForce
	if force then
		local on = gravityLift > 0
		if force.Enabled ~= on then
			force.Enabled = on
		end
		if on then
			local f = Vector3.new(0, r.AssemblyMass * workspace.Gravity * gravityLift, 0)
			if (force.Force - f).Magnitude > 0.5 then
				force.Force = f
			end
		end
	end

	-- Staub-Trail
	local emitter = dust
	if emitter then
		local on = sliding and grounded
		if emitter.Enabled ~= on then
			emitter.Enabled = on
			emitter.Rate = if setting("ReducedFx") == true then 18 else 40
		end
	end
end

-- ---------------------------------------------------------------------
-- 8) ÖFFENTLICHE API
-- ---------------------------------------------------------------------
function Movement.ApplyImpulse(v: Vector3)
	local h, r = humanoid, root
	if typeof(v) ~= "Vector3" or not (finite(v.X) and finite(v.Y) and finite(v.Z)) or not (h and r) then
		return
	end
	if v.Magnitude > IMPULSE_MAX then
		v = v.Unit * IMPULSE_MAX
	end
	local now = os.clock()
	endSlide(now)
	local newV = r.AssemblyLinearVelocity + v
	if newV.Magnitude > IMPULSE_MAX then
		newV = newV.Unit * IMPULSE_MAX
	end
	r.AssemblyLinearVelocity = newV
	if v.Y > 5 then
		h:ChangeState(Enum.HumanoidStateType.Freefall)
		leftGroundAt = now
		wasGrounded = false
	end
	local flat = horizontal(newV)
	if flat.Magnitude > h.WalkSpeed + 2 then
		carry = { Dir = flat.Unit, Speed = flat.Magnitude }
		landedAt = now -- Boden-Schwung-Fenster ab jetzt
	end
end

function Movement.SetGravityLift(frac: number)
	gravityLift = if finite(frac) then math.clamp(frac, 0, 0.95) else 0
end

function Movement.IsSliding(): boolean
	return sliding
end

function Movement.IsSprinting(): boolean
	return sprinting
end

function Movement.StopSprint()
	sprintToggled = false
	sprinting = false
	local p = cfgPlayer()
	sprintSuppressUntil = os.clock() + math.max(cfgNum(p, "SprintToFire", 0.12), 0.12) + 0.1
end

function Movement.IsAirborne(): boolean
	local h = humanoid
	if not h then
		return false
	end
	return h.FloorMaterial == Enum.Material.Air
end

function Movement.Speed(): number
	local r = root
	return if r then horizontal(r.AssemblyLinearVelocity).Magnitude else 0
end

-- ---------------------------------------------------------------------
-- 9) MODUL-FORM
-- ---------------------------------------------------------------------
local function onArmed(info: any)
	haveArmed = true
	armed = true
	rules = if type(info) == "table" and type(info.Rules) == "table" then info.Rules else {}
	Movement.SetGravityLift(if finite(rules.GravityLift) then rules.GravityLift else 0)
	lastSlideStart = -10
	airJumpsUsed = 0
end

local function onDisarmed()
	haveArmed = false
	armed = false
	rules = {}
	gravityLift = 0
	if not restored then
		restoreDefaults()
	end
end

local function bindInput()
	local controls = modules().Controls
	if controls and type(controls.Bind) == "function" then
		controls.Bind("Sprint", function(state: string)
			if state == "Begin" then
				sprintHeld = true
				if setting("SprintToggle") == true then
					sprintToggled = not sprintToggled
				end
			elseif state == "End" then
				sprintHeld = false
			end
		end)
		controls.Bind("Slide", function(state: string)
			if state == "Begin" then
				slideHeld = true
				slideQueuedAt = os.clock()
			elseif state == "End" then
				slideHeld = false
			end
		end)
		return
	end
	-- Ersatz ohne Controls-Modul (nur Tastatur, damit Studio-Tests trotzdem laufen)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftShift then
			sprintHeld = true
		elseif input.KeyCode == Enum.KeyCode.C or input.KeyCode == Enum.KeyCode.LeftControl then
			slideHeld = true
			slideQueuedAt = os.clock()
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.LeftShift then
			sprintHeld = false
		elseif input.KeyCode == Enum.KeyCode.C or input.KeyCode == Enum.KeyCode.LeftControl then
			slideHeld = false
		end
	end)
end

function Movement.Init(context: any)
	ctx = context
end

function Movement.Start()
	local hooks = ctx and ctx.Hooks
	if hooks and type(hooks.On) == "function" then
		hooks.On("Armed", onArmed)
		hooks.On("Disarmed", onDisarmed)
		hooks.On("LocalPopped", function()
			armed = false -- gepoppt: zuschauen, keine Bewegungs-Tech
		end)
		hooks.On("LocalRevived", function()
			armed = haveArmed
		end)
		hooks.On("Combat:Impulse", function(data: any)
			if type(data) == "table" and typeof(data.V) == "Vector3" then
				Movement.ApplyImpulse(data.V)
			end
		end)
	end
	bindInput()
	UserInputService.JumpRequest:Connect(onJumpRequest)
	if player.Character then
		attachCharacter(player.Character)
	end
	player.CharacterAdded:Connect(attachCharacter)
	RunService.PreSimulation:Connect(step)
end

return Movement
