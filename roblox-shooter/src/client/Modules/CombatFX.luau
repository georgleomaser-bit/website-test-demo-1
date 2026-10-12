-- =====================================================================
--  CLUTCH CLASH – Kampf-Effekte mit festen Vorräten (Client/Modules/CombatFX)
--  Besitzer: WP10 (Client-Hülle). Vertrag: DESIGN.md C7.4, C8 (FX-Buffer), C11, C17, ASSETS §5.
--
--  Alles wird beim Start EINMAL gebaut und danach nur noch umgestellt: ein Schuss erzeugt keine
--  neue Instanz (Abnahme 4). Tracer = Beam zwischen zwei Attachments, Treffer = Partikel-Stöße an
--  wiederverwendeten Attachments (≤ 8 Partikel pro Schuss), Lichter ≤ 4, Projektile als
--  Kugel-Teile mit Trail (BulkMoveTo, ein Frame-Schritt für alles). Reduzierte Effekte halbieren
--  Partikel und schalten Lichter aus.
--
--  Öffentliche API (C7.4):
--    CombatFX.Tracer(from, to, color?, tracerId?, team?)   tracerId -> CosmeticModels.TracerStyle(id, Teamfarbe)
--    CombatFX.Impact(pos, normal?, kind)          kind "Surface" | "Player" | "Head" | "Water"
--    CombatFX.Muzzle(cf, weaponKey)
--    CombatFX.Explosion(pos, radius)
--    CombatFX.Smoke(pos, radius, untilT)          untilT = workspace:GetServerTimeNow()-Zeit
--    CombatFX.Projectile(id, weaponKey, origin, velocity, gravity, t0)
--    CombatFX.RemoveProjectile(id)
--    CombatFX.Pop(pos, finisherId, color)         Finishers.Play (WP9), sonst Konfetti-Puff
--    CombatFX.Frame(dt) (aus dem einen PreRender-Loop), CombatFX.Init(ctx) / CombatFX.Start()
--  Hört selbst: Remote "FX" (Buffer der anderen Schützen), Hooks "Combat:Proj/Boom/Smoke",
--  "Match:Start"/"Combat:Armed" (Arena-Ursprung + Map für Abpraller).
--  Leuchtspur-Kosmetik (Vertrag Runde 2): eigene Schüsse = tracerId vom Aufrufer (WeaponClient: Armed.Tracer
--    bzw. State Cosmetics.Equipped.Tracer); fremde Schützen (FX-Slot) = Roster-Eintrag "Tracer" (Match:Start)
--    oder Armed.Tracers[slot], sonst WeaponClient.TracerOfSlot(slot) / Attribut "Tracer" am Combatant-Modell
--    (CombatService), sonst Config.Cosmetics.Defaults.Tracer. "Team"-Leuchtspuren färben nach Config.Colors.TeamA/TeamB (FFA: weiß).
--  Server-Abgleich eines Projektils (gleiche Id, z. B. Granaten-Abprall) aktualisiert das vorhandene statt
--  ein zweites zu zeigen; "Boom" mit Warn = roter Warnkreis bis zur Zeit Warn (Orbital-Schlag), keine Explosion.
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatFX = {}

local player = Players.LocalPlayer
local ctx: any = nil

local WHITE = Color3.new(1, 1, 1)
local TRACER_DEFAULT = Color3.fromRGB(255, 236, 150)
local HIDDEN_CF = CFrame.new(0, -4000, 0)
local TEX = {
	Gradient = "rbxasset://textures/gradient.png",
	Square = "rbxasset://textures/particles/SquareParticle.png",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Puff = "rbxasset://textures/explosion.png",
	Star = "rbxasset://textures/particles/sparkles_main.dds",
	Ring = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
	Glow = "rbxasset://textures/particles/explosion01_implosion_main.dds",
	Burst = "rbxasset://textures/glow.png",
	Fire = "rbxasset://textures/particles/explosion01_core_main.dds",
	DarkSmoke = "rbxasset://textures/particles/explosion01_smoke_main.dds",
	Dot = "rbxasset://textures/ui/traildot.png",
}

-- Grenzen (C17); echte Werte aus Config.Client.Pools
local poolSizes = { Tracers = 48, Impacts = 32, Lights = 4, Projectiles = 40 }
local IMPACT_ATTACHMENTS = 16 -- Partikel leben in Weltkoordinaten weiter -> 16 Halter reichen für 32 Treffer/s
local MUZZLES = 6
local EXPLOSIONS = 4
local SMOKES = 4
local POPS = 4
local WARNS = 4 -- Warnkreise (Orbital-Schlag)
local SLOT_REFRESH = 3 -- Leuchtspur/Team eines fremden Schützen so lange merken
local FX_RANGE = 450
local FINISHER_RANGE = 300
local PROJECTILE_LIFE = 6
local PROJECTILE_FASTFORWARD = 0.5
local PREDICT_MATCH_TIME = 0.6 -- eigenes Projektil-Echo vom Server so lange einem vorhergesagten zuordnen
local PREDICT_MATCH_DIST = 8

-- ---------------------------------------------------------------------
-- ZUSTAND
-- ---------------------------------------------------------------------
type Tracer = { Beam: Beam, A0: Attachment, A1: Attachment, Age: number, Life: number, Active: boolean }
type ImpactSlot = {
	Attachment: Attachment,
	Sparks: ParticleEmitter,
	Dust: ParticleEmitter,
	Puff: ParticleEmitter,
	Stars: ParticleEmitter,
	Ring: ParticleEmitter,
}
type MuzzleSlot = { Attachment: Attachment, Core: ParticleEmitter, Star: ParticleEmitter, Smoke: ParticleEmitter }
type ExplosionSlot = {
	Attachment: Attachment,
	Fire: ParticleEmitter,
	Wave: ParticleEmitter,
	Smoke: ParticleEmitter,
	Debris: ParticleEmitter,
}
type SmokeSlot = {
	Attachment: Attachment,
	Emitter: ParticleEmitter,
	Ball: Part,
	Until: number,
	Radius: number,
	Active: boolean,
}
type LightSlot = { Attachment: Attachment, Light: PointLight, Until: number, Active: boolean }
type Projectile = {
	Part: Part,
	Trail: Trail,
	Active: boolean,
	Id: string,
	Aliases: { string },
	Key: string,
	Pos: Vector3,
	Vel: Vector3,
	Gravity: number,
	Bounces: number,
	Restitution: number,
	Age: number,
	Life: number,
	Stopped: boolean,
	Local: boolean,
	SpawnedAt: number,
	Origin: Vector3,
}

local anchor: Part? = nil
local folder: Folder? = nil
local tracers: { Tracer } = {}
local tracerNext = 1
local tracersActive = 0
local impacts: { ImpactSlot } = {}
local impactNext = 1
local impactWindowStart = 0
local impactWindowCount = 0
local muzzles: { MuzzleSlot } = {}
local muzzleNext = 1
local explosions: { ExplosionSlot } = {}
local explosionNext = 1
local smokes: { SmokeSlot } = {}
local lights: { LightSlot } = {}
local pops: { ParticleEmitter } = {}
local popAttachments: { Attachment } = {}
local popNext = 1
local projectiles: { Projectile } = {}
local projectileById: { [string]: Projectile } = {}
local projectilesActive = 0
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}
local tracerSeqs: { NumberSequence } = {}
local tracerStyles: { [string]: any } = {}
local arenaOrigin = Vector3.zero
local arenaMap: Instance? = nil
local myCombatId = player.UserId
local myTeam = 0
local matchFfa = false
local ownTracer: string? = nil -- Armed.Tracer (falls der Server ihn schickt)
type SlotLook = { Tracer: string?, Team: number?, At: number }
type RosterLook = { Id: number?, Team: number?, Tracer: string? }
local rosterBySlot: { [number]: RosterLook } = {}
local slotLooks: { [number]: SlotLook } = {}
type WarnSlot = { Part: Part, Until: number, Active: boolean }
local warns: { WarnSlot } = {}
local warnNext = 1
local rayParams = RaycastParams.new()
local cosmeticModels: any = nil
local ballistics: any = nil

-- ---------------------------------------------------------------------
-- HILFEN
-- ---------------------------------------------------------------------
local function setting(key: string): any
	local module = ctx and ctx.Modules and ctx.Modules.Settings
	if module and type(module.Get) == "function" then
		local ok, settings = pcall(module.Get)
		if ok and type(settings) == "table" then
			return settings[key]
		end
	end
	return nil
end

local function reduced(): boolean
	return setting("ReducedFx") == true
end

local function count(n: number): number
	if reduced() then
		return math.max(1, math.floor(n / 2))
	end
	return n
end

local function camPos(): Vector3?
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position or nil
end

local function near(pos: Vector3, range: number): boolean
	local cam = camPos()
	return cam == nil or (cam - pos).Magnitude <= range
end

local function sfx(role: string, pos: Vector3?, opts: any?)
	local module = ctx and ctx.Modules and ctx.Modules.Sfx
	if module and type(module.Play) == "function" then
		pcall(module.Play, role, pos, opts)
	end
end

local function weaponDef(key: string?): any
	if type(key) ~= "string" or not ctx then
		return nil
	end
	local config = ctx.Config
	if type(config.Weapon) == "function" then
		local ok, def = pcall(config.Weapon, key)
		if ok then
			return def
		end
	end
	return nil
end

local function weaponDefById(id: number): any
	local config = ctx and ctx.Config
	if config and type(config.WeaponById) == "function" then
		local ok, def = pcall(config.WeaponById, id)
		if ok then
			return def
		end
	end
	return nil
end

-- Schuss-Sound einer Waffe: def.Sound (Rolle), sonst nach Art/Slot geraten
local function shotRole(def: any): string?
	if type(def) ~= "table" then
		return nil
	end
	local sfxModule = ctx.Modules.Sfx
	if type(def.Sound) == "string" and sfxModule and type(sfxModule.Has) == "function" and sfxModule.Has(def.Sound) then
		return def.Sound
	end
	if def.Kind == "Melee" then
		return "MeleeSwing"
	elseif def.Kind == "Throwable" or def.Kind == "Consumable" then
		return "Throw"
	elseif def.Kind == "Projectile" then
		return "RocketLaunch"
	elseif def.Slot == "Secondary" then
		return "PistolShot"
	elseif (def.Pellets or 1) > 1 then
		return "ShotgunShot"
	end
	return "RifleShot"
end

local function attachment(name: string): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Parent = anchor
	return a
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.LightInfluence = 0
	e.Enabled = true
	for key, value in pairs(props) do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

local function seq(a: number, b: number, c: number?): NumberSequence
	if c then
		return NumberSequence.new({
			NumberSequenceKeypoint.new(0, a),
			NumberSequenceKeypoint.new(0.4, b),
			NumberSequenceKeypoint.new(1, c),
		})
	end
	return NumberSequence.new(a, b)
end

-- ---------------------------------------------------------------------
-- AUFBAU (einmal)
-- ---------------------------------------------------------------------
local function buildTracers()
	-- Ausblend-Stufen vorberechnet (keine neuen NumberSequences pro Frame)
	for i = 0, 5 do
		local t = i / 5
		table.insert(
			tracerSeqs,
			NumberSequence.new({
				NumberSequenceKeypoint.new(0, math.min(1, 0.05 + t)),
				NumberSequenceKeypoint.new(1, math.min(1, 0.35 + t)),
			})
		)
	end
	for i = 1, poolSizes.Tracers do
		local a0 = attachment("T0_" .. i)
		local a1 = attachment("T1_" .. i)
		local beam = Instance.new("Beam")
		beam.Name = "Tracer"
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Texture = TEX.Gradient
		beam.TextureMode = Enum.TextureMode.Stretch
		beam.Segments = 1
		beam.Width0 = 0.12
		beam.Width1 = 0.05
		beam.Color = ColorSequence.new(TRACER_DEFAULT)
		beam.Transparency = tracerSeqs[1]
		beam.Enabled = false
		beam.Parent = anchor
		table.insert(tracers, { Beam = beam, A0 = a0, A1 = a1, Age = 0, Life = 0.07, Active = false })
	end
end

local function buildImpacts()
	for i = 1, IMPACT_ATTACHMENTS do
		local a = attachment("Impact_" .. i)
		table.insert(impacts, {
			Attachment = a,
			Sparks = emitter(a, {
				Texture = TEX.Square,
				Color = ColorSequence.new(Color3.fromRGB(255, 240, 120), Color3.fromRGB(255, 170, 40)),
				LightEmission = 1,
				Size = seq(0.12, 0),
				Lifetime = NumberRange.new(0.2, 0.35),
				Speed = NumberRange.new(15, 25),
				SpreadAngle = Vector2.new(40, 40),
				Acceleration = Vector3.new(0, -40, 0),
				Drag = 3,
				EmissionDirection = Enum.NormalId.Top,
			}),
			Dust = emitter(a, {
				Texture = TEX.Smoke,
				Color = ColorSequence.new(Color3.fromRGB(220, 215, 205)),
				Size = seq(0.4, 1.2),
				Transparency = seq(0.4, 1),
				Lifetime = NumberRange.new(0.35, 0.45),
				Speed = NumberRange.new(2, 4),
				SpreadAngle = Vector2.new(30, 30),
				EmissionDirection = Enum.NormalId.Top,
				Rotation = NumberRange.new(0, 360),
			}),
			Puff = emitter(a, {
				Texture = TEX.Puff,
				Color = ColorSequence.new(WHITE),
				LightEmission = 0.3,
				Size = seq(0.5, 1.6, 0),
				Transparency = seq(0.05, 0.3, 1),
				Lifetime = NumberRange.new(0.25, 0.4),
				Speed = NumberRange.new(3, 6),
				SpreadAngle = Vector2.new(180, 180),
				Drag = 6,
				Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-120, 120),
			}),
			Stars = emitter(a, {
				Texture = TEX.Star,
				Color = ColorSequence.new(WHITE),
				LightEmission = 0.8,
				Size = seq(0.9, 0),
				Lifetime = NumberRange.new(0.35, 0.55),
				Speed = NumberRange.new(6, 11),
				SpreadAngle = Vector2.new(180, 180),
				Acceleration = Vector3.new(0, -10, 0),
				Drag = 3,
				RotSpeed = NumberRange.new(-260, 260),
			}),
			Ring = emitter(a, {
				Texture = TEX.Ring,
				Color = ColorSequence.new(Color3.fromRGB(255, 230, 80)),
				LightEmission = 1,
				Size = seq(0.4, 3.2),
				Transparency = seq(0.1, 1),
				Lifetime = NumberRange.new(0.25, 0.25),
				Speed = NumberRange.new(0, 0),
				Orientation = Enum.ParticleOrientation.FacingCamera,
			}),
		})
	end
end

local function buildMuzzles()
	for i = 1, MUZZLES do
		local a = attachment("Muzzle_" .. i)
		table.insert(muzzles, {
			Attachment = a,
			Core = emitter(a, {
				Texture = TEX.Glow,
				Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 150, 40)),
				LightEmission = 1,
				Size = seq(0.9, 0),
				Lifetime = NumberRange.new(0.04, 0.07),
				Speed = NumberRange.new(0, 0),
				LockedToPart = true,
			}),
			Star = emitter(a, {
				Texture = TEX.Burst,
				Color = ColorSequence.new(Color3.fromRGB(255, 240, 180)),
				LightEmission = 1,
				Size = seq(1.0, 0.2),
				Lifetime = NumberRange.new(0.05, 0.06),
				Speed = NumberRange.new(0, 0),
				Rotation = NumberRange.new(0, 360),
				LockedToPart = true,
			}),
			Smoke = emitter(a, {
				Texture = TEX.Smoke,
				Color = ColorSequence.new(Color3.fromRGB(235, 235, 235)),
				Size = seq(0.3, 1.1),
				Transparency = seq(0.55, 1),
				Lifetime = NumberRange.new(0.35, 0.5),
				Speed = NumberRange.new(1.5, 3),
				SpreadAngle = Vector2.new(15, 15),
				EmissionDirection = Enum.NormalId.Front,
				Rotation = NumberRange.new(0, 360),
			}),
		})
	end
end

local function buildExplosions()
	for i = 1, EXPLOSIONS do
		local a = attachment("Explosion_" .. i)
		table.insert(explosions, {
			Attachment = a,
			Fire = emitter(a, {
				Texture = TEX.Fire,
				Color = ColorSequence.new(WHITE),
				LightEmission = 0.6,
				Size = seq(2, 6, 3),
				Transparency = seq(0, 0.2, 1),
				Lifetime = NumberRange.new(0.35, 0.55),
				Speed = NumberRange.new(4, 12),
				SpreadAngle = Vector2.new(180, 180),
				Drag = 4,
				Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-90, 90),
			}),
			Wave = emitter(a, {
				Texture = TEX.Ring,
				Color = ColorSequence.new(Color3.fromRGB(255, 220, 160)),
				LightEmission = 1,
				Size = seq(1, 18),
				Transparency = seq(0.1, 1),
				Lifetime = NumberRange.new(0.35, 0.35),
				Speed = NumberRange.new(0, 0),
			}),
			Smoke = emitter(a, {
				Texture = TEX.DarkSmoke,
				Color = ColorSequence.new(WHITE),
				Size = seq(3, 8),
				Transparency = seq(0.2, 1),
				Lifetime = NumberRange.new(0.9, 1.4),
				Speed = NumberRange.new(2, 6),
				SpreadAngle = Vector2.new(180, 180),
				Acceleration = Vector3.new(0, 3, 0),
				Drag = 2,
				Rotation = NumberRange.new(0, 360),
			}),
			Debris = emitter(a, {
				Texture = TEX.Square,
				Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(90, 80, 70)),
				LightEmission = 0.5,
				Size = seq(0.35, 0.1),
				Lifetime = NumberRange.new(0.5, 0.9),
				Speed = NumberRange.new(20, 38),
				SpreadAngle = Vector2.new(180, 180),
				Acceleration = Vector3.new(0, -60, 0),
				RotSpeed = NumberRange.new(-300, 300),
			}),
		})
	end
end

local function buildSmokes()
	local parent = folder
	for i = 1, SMOKES do
		local a = attachment("Smoke_" .. i)
		local ball = Instance.new("Part")
		ball.Name = "SmokeBall"
		ball.Shape = Enum.PartType.Ball
		ball.Anchored = true
		ball.CanCollide = false
		ball.CanQuery = false
		ball.CanTouch = false
		ball.CastShadow = false
		ball.Material = Enum.Material.SmoothPlastic
		ball.Color = Color3.fromRGB(205, 208, 214)
		ball.Transparency = 1
		ball.Size = Vector3.new(1, 1, 1)
		ball.CFrame = HIDDEN_CF
		ball.Parent = parent
		table.insert(smokes, {
			Attachment = a,
			Emitter = emitter(a, {
				Texture = TEX.Smoke,
				Color = ColorSequence.new(Color3.fromRGB(215, 218, 224)),
				Size = seq(5, 11),
				Transparency = seq(0.15, 0.3, 1),
				Lifetime = NumberRange.new(2.5, 3.5),
				Speed = NumberRange.new(1, 3),
				SpreadAngle = Vector2.new(180, 180),
				Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-20, 20),
				Enabled = false,
			}),
			Ball = ball,
			Until = 0,
			Radius = 0,
			Active = false,
		})
	end
end

local function buildLights()
	for i = 1, poolSizes.Lights do
		local a = attachment("Light_" .. i)
		local light = Instance.new("PointLight")
		light.Enabled = false
		light.Shadows = false
		light.Brightness = 6
		light.Range = 14
		light.Parent = a
		table.insert(lights, { Attachment = a, Light = light, Until = 0, Active = false })
	end
end

local function buildPops()
	local colors = { Color3.fromRGB(255, 220, 50), Color3.fromRGB(255, 85, 195), Color3.fromRGB(60, 220, 255) }
	for i = 1, POPS do
		local a = attachment("Pop_" .. i)
		table.insert(popAttachments, a)
		table.insert(
			pops,
			emitter(a, {
				Texture = TEX.Square,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, colors[1]),
					ColorSequenceKeypoint.new(0.5, colors[2]),
					ColorSequenceKeypoint.new(1, colors[3]),
				}),
				LightEmission = 0.4,
				Size = seq(0.45, 0.25),
				Lifetime = NumberRange.new(0.8, 1.4),
				Speed = NumberRange.new(10, 22),
				SpreadAngle = Vector2.new(180, 180),
				Acceleration = Vector3.new(0, -30, 0),
				Drag = 1.5,
				Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-400, 400),
			})
		)
	end
end

local function buildWarns()
	local parent = folder
	for i = 1, WARNS do
		local part = Instance.new("Part")
		part.Name = "StrikeWarn_" .. i
		part.Shape = Enum.PartType.Cylinder
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(239, 68, 68) -- AKYTEX Down
		part.Transparency = 1
		part.Size = Vector3.new(0.2, 4, 4)
		part.CFrame = HIDDEN_CF
		part.Parent = parent
		table.insert(warns, { Part = part, Until = 0, Active = false })
	end
end

-- Roter Warnkreis am Boden bis zur Server-Zeit untilT (Orbital-Schlag: "Boom" mit Warn kommt VOR dem Einschlag)
local function showWarn(pos: Vector3, radius: number, untilT: number)
	if #warns == 0 or not near(pos, FX_RANGE) then
		return
	end
	local slot = warns[warnNext]
	warnNext = warnNext % #warns + 1
	local r = math.clamp(radius, 2, 60)
	slot.Active = true
	slot.Until = untilT
	slot.Part.Size = Vector3.new(0.2, r * 2, r * 2)
	slot.Part.CFrame = CFrame.new(pos + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	slot.Part.Transparency = 0.6
end

local function buildProjectiles()
	local parent = folder
	for i = 1, poolSizes.Projectiles do
		local part = Instance.new("Part")
		part.Name = "Projectile_" .. i
		part.Shape = Enum.PartType.Ball
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Size = Vector3.new(0.7, 0.7, 0.7)
		part.CFrame = HIDDEN_CF
		part.Parent = parent
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.25, 0)
		a0.Parent = part
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.25, 0)
		a1.Parent = part
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Texture = TEX.Gradient
		trail.LightEmission = 0.8
		trail.LightInfluence = 0
		trail.Lifetime = 0.25
		trail.FaceCamera = true
		trail.Transparency = seq(0.2, 1)
		trail.Enabled = false
		trail.Parent = part
		table.insert(projectiles, {
			Part = part,
			Trail = trail,
			Active = false,
			Id = "",
			Aliases = {},
			Key = "",
			Pos = Vector3.zero,
			Vel = Vector3.zero,
			Gravity = 0,
			Bounces = 0,
			Restitution = 0.35,
			Age = 0,
			Life = PROJECTILE_LIFE,
			Stopped = false,
			Local = true,
			SpawnedAt = 0,
			Origin = Vector3.zero,
		})
	end
end

-- ---------------------------------------------------------------------
-- LICHTER (≤ 4, aus bei Reduzierten Effekten)
-- ---------------------------------------------------------------------
local function flashLight(pos: Vector3, color: Color3, range: number, seconds: number)
	if reduced() or not near(pos, 200) then
		return
	end
	local chosen: LightSlot? = nil
	for _, slot in ipairs(lights) do
		if not slot.Active then
			chosen = slot
			break
		end
	end
	if not chosen then
		return
	end
	chosen.Active = true
	chosen.Until = os.clock() + seconds
	chosen.Attachment.WorldPosition = pos
	chosen.Light.Color = color
	chosen.Light.Range = range
	chosen.Light.Enabled = true
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICH: TRACER, TREFFER, MÜNDUNG
-- ---------------------------------------------------------------------
local function allowImpact(): boolean
	local now = os.clock()
	if now - impactWindowStart >= 1 then
		impactWindowStart = now
		impactWindowCount = 0
	end
	impactWindowCount += 1
	return impactWindowCount <= poolSizes.Impacts
end

local function defaultTracer(): string?
	local config = ctx and ctx.Config
	local cosmetics = config and config.Cosmetics
	local defaults = cosmetics and cosmetics.Defaults
	local id = type(defaults) == "table" and defaults.Tracer or nil
	return if type(id) == "string" and id ~= "" then id else nil
end

-- Teamfarbe für "Team"-Leuchtspuren (FFA/Range/ohne Team: nil -> weiß)
local function teamColor(team: number?): Color3?
	if matchFfa or type(team) ~= "number" then
		return nil
	end
	local config = ctx and ctx.Config
	local colors = config and config.Colors
	if type(colors) ~= "table" then
		return nil
	end
	local color = if team == 1 then colors.TeamA elseif team == 2 then colors.TeamB else nil
	return if typeof(color) == "Color3" then color else nil
end

local function tracerStyle(tracerId: string?, team: number?): any
	if type(tracerId) ~= "string" or tracerId == "" or not cosmeticModels then
		return nil
	end
	local tint = teamColor(team)
	local key = tracerId .. "|" .. (if tint then tostring(team) else "-")
	local cached = tracerStyles[key]
	if cached ~= nil then
		return cached or nil
	end
	local ok, style = pcall(cosmeticModels.TracerStyle, tracerId, tint)
	if ok and type(style) == "table" and typeof(style.Color) == "ColorSequence" then
		tracerStyles[key] = style
		return style
	end
	tracerStyles[key] = false
	return nil
end

function CombatFX.Tracer(from: Vector3, to: Vector3, color: Color3?, tracerId: string?, team: number?)
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" or #tracers == 0 then
		return
	end
	if not near(from, FX_RANGE) and not near(to, FX_RANGE) then
		return
	end
	local tracer = tracers[tracerNext]
	tracerNext = tracerNext % #tracers + 1
	if not tracer.Active then
		tracersActive += 1
	end
	tracer.Active = true
	tracer.Age = 0
	tracer.Life = 0.07
	tracer.A0.WorldPosition = from
	tracer.A1.WorldPosition = to
	local beam = tracer.Beam
	-- ohne Team-Angabe (eigener Schuss vom WeaponClient): eigenes Team aus "Armed"
	local id = tracerId
	if id == nil and team == nil then
		id = ownTracer or defaultTracer()
	end
	local style = if typeof(color) == "Color3" then nil else tracerStyle(id, if team ~= nil then team else myTeam)
	if typeof(color) == "Color3" then
		beam.Color = ColorSequence.new(color)
		beam.Width0, beam.Width1 = 0.12, 0.05
		beam.Texture = TEX.Gradient
	elseif style then
		beam.Color = style.Color
		beam.Width0 = tonumber(style.Width0) or 0.12
		beam.Width1 = tonumber(style.Width1) or 0.05
		local texture = style.Texture
		beam.Texture = if type(texture) == "string" and texture ~= "" then texture else TEX.Gradient
	else
		beam.Color = ColorSequence.new(TRACER_DEFAULT)
		beam.Width0, beam.Width1 = 0.12, 0.05
		beam.Texture = TEX.Gradient
	end
	beam.Transparency = tracerSeqs[1]
	beam.Enabled = true
	-- Funkel-Leuchtspuren (z. B. "Seifenblase"): zwei kleine Sterne am Ende (aus dem Treffer-Budget)
	if style and style.Sparkle == true and not reduced() and #impacts > 0 and near(to, 150) and allowImpact() then
		local slot = impacts[impactNext]
		impactNext = impactNext % #impacts + 1
		slot.Attachment.WorldCFrame = CFrame.new(to)
		slot.Stars.Color = style.Color
		slot.Stars:Emit(2)
	end
end

function CombatFX.Impact(pos: Vector3, normal: Vector3?, kind: string)
	if typeof(pos) ~= "Vector3" or #impacts == 0 or not near(pos, FX_RANGE) or not allowImpact() then
		return
	end
	local slot = impacts[impactNext]
	impactNext = impactNext % #impacts + 1
	local up = if typeof(normal) == "Vector3" and normal.Magnitude > 0.01 then normal.Unit else Vector3.yAxis
	-- Attachment so drehen, dass "oben" (Top) entlang der Flächennormale zeigt
	slot.Attachment.WorldCFrame = CFrame.lookAt(pos, pos + up) * CFrame.Angles(-math.pi / 2, 0, 0)
	if kind == "Head" then
		slot.Puff.Color = ColorSequence.new(Color3.fromRGB(255, 245, 160))
		slot.Stars.Color = ColorSequence.new(Color3.fromRGB(255, 225, 60))
		slot.Puff:Emit(count(2))
		slot.Stars:Emit(count(4))
		slot.Ring:Emit(1)
	elseif kind == "Player" then
		slot.Puff.Color = ColorSequence.new(WHITE)
		slot.Stars.Color = ColorSequence.new(WHITE)
		slot.Puff:Emit(count(3))
		slot.Stars:Emit(count(2))
	elseif kind == "Water" then
		slot.Dust.Color = ColorSequence.new(Color3.fromRGB(200, 230, 255))
		slot.Dust:Emit(count(5))
		sfx("Water", pos)
	else
		slot.Dust.Color = ColorSequence.new(Color3.fromRGB(220, 215, 205))
		slot.Sparks:Emit(count(5))
		slot.Dust:Emit(count(2))
	end
end

function CombatFX.Muzzle(cf: CFrame, weaponKey: string)
	if typeof(cf) ~= "CFrame" or #muzzles == 0 or not near(cf.Position, FX_RANGE) then
		return
	end
	local slot = muzzles[muzzleNext]
	muzzleNext = muzzleNext % #muzzles + 1
	slot.Attachment.WorldCFrame = cf
	local def = weaponDef(weaponKey)
	local big = type(def) == "table" and ((def.Pellets or 1) > 1 or def.Kind == "Projectile")
	slot.Core.Size = if big then seq(1.4, 0) else seq(0.9, 0)
	slot.Core:Emit(1)
	slot.Star:Emit(1)
	if not reduced() then
		slot.Smoke:Emit(1)
	end
	flashLight(cf.Position, Color3.fromRGB(255, 190, 90), 12, 0.05)
end

-- ---------------------------------------------------------------------
-- EXPLOSION, RAUCH, POP
-- ---------------------------------------------------------------------
function CombatFX.Explosion(pos: Vector3, radius: number)
	if typeof(pos) ~= "Vector3" then
		return
	end
	local r = if type(radius) == "number" and radius == radius then math.clamp(radius, 2, 40) else 10
	sfx("Explosion", pos)
	local cam = camPos()
	if cam then
		local dist = (cam - pos).Magnitude
		if dist < r * 3 then
			local effects = ctx and ctx.Modules and ctx.Modules.Effects
			if effects and type(effects.Shake) == "function" then
				pcall(effects.Shake, math.clamp(1.4 * (1 - dist / (r * 3)), 0.1, 1.4))
			end
		end
	end
	if #explosions == 0 or not near(pos, FX_RANGE) then
		return
	end
	local slot = explosions[explosionNext]
	explosionNext = explosionNext % #explosions + 1
	slot.Attachment.WorldPosition = pos
	local scale = r / 10
	slot.Fire.Size = seq(2 * scale, 6 * scale, 3 * scale)
	slot.Wave.Size = seq(1, r * 1.8)
	slot.Fire:Emit(count(8))
	slot.Wave:Emit(1)
	slot.Smoke:Emit(count(5))
	slot.Debris:Emit(count(10))
	flashLight(pos, Color3.fromRGB(255, 160, 60), math.clamp(r * 2, 10, 40), 0.18)
end

function CombatFX.Smoke(pos: Vector3, radius: number, untilT: number)
	if typeof(pos) ~= "Vector3" or type(untilT) ~= "number" or #smokes == 0 then
		return
	end
	local r = if type(radius) == "number" and radius == radius then math.clamp(radius, 2, 30) else 13
	local chosen: SmokeSlot? = nil
	for _, slot in ipairs(smokes) do
		if not slot.Active then
			chosen = slot
			break
		end
	end
	if not chosen then
		-- alle belegt: die, die am frühesten endet, wird umgesetzt
		for _, slot in ipairs(smokes) do
			if not chosen or slot.Until < chosen.Until then
				chosen = slot
			end
		end
	end
	if not chosen then
		return
	end
	chosen.Active = true
	chosen.Until = untilT
	chosen.Radius = r
	chosen.Attachment.WorldPosition = pos
	chosen.Emitter.Rate = if reduced() then 6 else 12
	chosen.Emitter.Enabled = true
	chosen.Ball.Size = Vector3.new(r * 2, r * 1.6, r * 2)
	chosen.Ball.CFrame = CFrame.new(pos)
	chosen.Ball.Transparency = 0.3
end

function CombatFX.Pop(pos: Vector3, finisherId: string, color: Color3)
	if typeof(pos) ~= "Vector3" or not near(pos, FINISHER_RANGE) then
		return
	end
	local tint = if typeof(color) == "Color3" then color else Color3.fromRGB(255, 220, 50)
	local finishers = ctx and ctx.Modules and ctx.Modules.Finishers
	if finishers and type(finishers.Play) == "function" and type(finisherId) == "string" and finisherId ~= "" then
		local ok, err = pcall(finishers.Play, finisherId, pos, tint)
		if ok then
			return
		end
		warn("[CombatFX] Finisher " .. finisherId .. ": " .. tostring(err))
	end
	-- Rückfall: Konfetti-Puff (wie der Standard-Finisher)
	if #pops == 0 then
		return
	end
	local index = popNext
	popNext = popNext % #pops + 1
	popAttachments[index].WorldPosition = pos
	pops[index]:Emit(count(24))
	local slot = impacts[impactNext]
	if slot then
		impactNext = impactNext % #impacts + 1
		slot.Attachment.WorldCFrame = CFrame.new(pos)
		slot.Puff.Color = ColorSequence.new(tint:Lerp(WHITE, 0.4))
		slot.Puff:Emit(count(6))
	end
end

-- ---------------------------------------------------------------------
-- PROJEKTILE (Kugeln/Raketen/Granaten; Server rechnet den Schaden)
-- ---------------------------------------------------------------------
local function projectileLook(def: any): (Color3, number, Enum.Material)
	local proj = type(def) == "table" and def.Projectile or nil
	if type(def) == "table" and (def.Kind == "Throwable" or def.Slot == "Utility") then
		if type(def.Smoke) == "table" then
			return Color3.fromRGB(200, 205, 215), 0.6, Enum.Material.SmoothPlastic
		end
		return Color3.fromRGB(90, 200, 90), 0.6, Enum.Material.SmoothPlastic
	end
	local radius = proj and tonumber(proj.Radius) or 0
	if radius > 0 then
		return Color3.fromRGB(255, 120, 0), 0.9, Enum.Material.Neon -- Rakete/Kanone (orange Spitze)
	end
	return Color3.fromRGB(150, 230, 255), 0.6, Enum.Material.Neon
end

local function freeProjectile(): Projectile?
	for _, p in ipairs(projectiles) do
		if not p.Active then
			return p
		end
	end
	-- alle belegt: das älteste fällt raus
	local oldest: Projectile? = nil
	for _, p in ipairs(projectiles) do
		if not oldest or p.SpawnedAt < oldest.SpawnedAt then
			oldest = p
		end
	end
	if oldest then
		CombatFX.RemoveProjectile(oldest.Id)
	end
	return oldest
end

local function spawnProjectile(
	id: string,
	weaponKey: string,
	origin: Vector3,
	velocity: Vector3,
	gravity: number,
	t0: number,
	isLocal: boolean
): Projectile?
	local p = freeProjectile()
	if not p then
		return nil
	end
	local def = weaponDef(weaponKey)
	local proj = type(def) == "table" and def.Projectile or nil
	local color, size, material = projectileLook(def)
	local age = math.clamp(workspace:GetServerTimeNow() - t0, 0, PROJECTILE_FASTFORWARD)
	local g = if type(gravity) == "number" and gravity == gravity then gravity else 0
	local pos = origin
	local vel = velocity
	if ballistics and age > 0 then
		pos, vel = ballistics.Step(origin, velocity, g, age) -- um die Laufzeit vorgespult (C11)
	end
	p.Active = true
	p.Id = id
	table.clear(p.Aliases)
	p.Key = weaponKey
	p.Pos = pos
	p.Vel = vel
	p.Gravity = g
	p.Bounces = proj and tonumber(proj.Bounces) or 0
	p.Restitution = proj and tonumber(proj.Restitution) or 0.35
	p.Age = age
	local life = proj and tonumber(proj.Lifetime) or PROJECTILE_LIFE
	local fuse = proj and tonumber(proj.Fuse)
	if fuse then
		life = math.min(life, fuse + 0.3)
	end
	p.Life = math.clamp(life, 0.2, 12)
	p.Stopped = false
	p.Local = isLocal
	p.SpawnedAt = os.clock()
	p.Origin = origin
	p.Part.Color = color
	p.Part.Material = material
	p.Part.Size = Vector3.new(size, size, size)
	p.Part.CFrame = CFrame.new(pos)
	p.Trail.Color = ColorSequence.new(color:Lerp(WHITE, 0.4), color)
	p.Trail.Enabled = not reduced()
	projectileById[id] = p
	projectilesActive += 1
	return p
end

function CombatFX.Projectile(
	id: string,
	weaponKey: string,
	origin: Vector3,
	velocity: Vector3,
	gravity: number,
	t0: number
)
	if typeof(origin) ~= "Vector3" or typeof(velocity) ~= "Vector3" then
		return
	end
	local key = tostring(id)
	if projectileById[key] then
		CombatFX.RemoveProjectile(key)
	end
	local start = if type(t0) == "number" and t0 == t0 then t0 else workspace:GetServerTimeNow()
	spawnProjectile(key, tostring(weaponKey), origin, velocity, gravity, start, true)
end

function CombatFX.RemoveProjectile(id: string)
	local key = tostring(id)
	local p = projectileById[key]
	if not p then
		return
	end
	projectileById[p.Id] = nil
	for _, alias in ipairs(p.Aliases) do
		projectileById[alias] = nil
	end
	table.clear(p.Aliases)
	if p.Active then
		p.Active = false
		projectilesActive -= 1
	end
	p.Trail.Enabled = false
	p.Part.CFrame = HIDDEN_CF
end

-- Server-Echo: eigenes Projektil (schon vorhergesagt) nur verknüpfen, fremdes neu zeigen
local function onServerProjectile(data: any)
	if type(data) ~= "table" or typeof(data.O) ~= "Vector3" or typeof(data.V) ~= "Vector3" then
		return
	end
	local serverId = "S" .. tostring(data.Id)
	-- Server-Abgleich desselben Projektils (Granate prallt ab / bleibt liegen): vorhandenes übernehmen,
	-- sonst läge nach jedem Abprall eine zweite Kopie in der Welt
	local existing = projectileById[serverId]
	if existing and existing.Active then
		existing.Pos = data.O
		existing.Vel = data.V
		existing.Gravity = tonumber(data.G) or existing.Gravity
		existing.Stopped = data.V.Magnitude < 0.05
		existing.Part.CFrame = CFrame.new(data.O)
		return
	end
	local def = weaponDefById(tonumber(data.W) or 0)
	local key = if type(def) == "table" and type(def.Key) == "string" then def.Key else ""
	if tonumber(data.Own) == myCombatId then
		local now = os.clock()
		for _, p in ipairs(projectiles) do
			if
				p.Active
				and p.Local
				and now - p.SpawnedAt <= PREDICT_MATCH_TIME
				and (p.Key == key or key == "")
				and (p.Origin - data.O).Magnitude <= PREDICT_MATCH_DIST
				and #p.Aliases == 0
			then
				table.insert(p.Aliases, serverId)
				projectileById[serverId] = p
				return
			end
		end
	end
	if not near(data.O, FX_RANGE + 200) then
		return
	end
	local t0 = if type(data.T) == "number" then data.T else workspace:GetServerTimeNow()
	local p = spawnProjectile(serverId, key, data.O, data.V, tonumber(data.G) or 0, t0, false)
	if p and type(def) == "table" then
		local role = shotRole(def)
		if role then
			sfx(role, data.O)
		end
	end
end

local function stepProjectiles(dt: number)
	if projectilesActive <= 0 then
		return
	end
	table.clear(moveParts)
	table.clear(moveCFrames)
	local n = 0
	local params = rayParams
	for _, p in ipairs(projectiles) do
		if p.Active then
			p.Age += dt
			if p.Age >= p.Life then
				CombatFX.RemoveProjectile(p.Id)
			elseif not p.Stopped then
				local newPos, newVel
				if ballistics then
					newPos, newVel = ballistics.Step(p.Pos, p.Vel, p.Gravity, dt)
				else
					newVel = p.Vel - Vector3.new(0, p.Gravity * dt, 0)
					newPos = p.Pos + p.Vel * dt
				end
				local delta = newPos - p.Pos
				local hit = if arenaMap and delta.Magnitude > 1e-4 then workspace:Raycast(p.Pos, delta, params) else nil
				if hit then
					if p.Bounces > 0 and ballistics then
						p.Bounces -= 1
						p.Vel = ballistics.Reflect(newVel, hit.Normal, p.Restitution)
						p.Pos = hit.Position + hit.Normal * 0.3
					else
						p.Pos = hit.Position + hit.Normal * 0.3
						p.Vel = Vector3.zero
						p.Stopped = true -- liegt, bis "Boom" kommt oder die Lebenszeit abläuft
					end
				else
					p.Pos = newPos
					p.Vel = newVel
				end
				n += 1
				moveParts[n] = p.Part
				local look = if p.Vel.Magnitude > 0.1 then CFrame.lookAt(p.Pos, p.Pos + p.Vel) else CFrame.new(p.Pos)
				moveCFrames[n] = look
			end
		end
	end
	if n > 0 then
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- ---------------------------------------------------------------------
-- FX-BUFFER (Tracer anderer Schützen, 20 Hz pro Kontext)
-- ---------------------------------------------------------------------
-- Combatant-Modell eines FX-Slots: Roster-Id -> Spieler-Character / WeaponClient.ModelOf,
-- sonst Attribut "Slot" an den bekannten Combatants (Range ohne Roster)
local function modelForSlot(slot: number, id: number?): Model?
	if id and id > 0 then
		local p = Players:GetPlayerByUserId(id)
		if p and p.Character then
			return p.Character
		end
	end
	local weapon = ctx and ctx.Modules and ctx.Modules.WeaponClient
	if not weapon then
		return nil
	end
	if id and type(weapon.ModelOf) == "function" then
		local ok, model = pcall(weapon.ModelOf, id)
		if ok and typeof(model) == "Instance" and model:IsA("Model") then
			return model
		end
	end
	if type(weapon.Combatants) == "function" then
		local ok, list = pcall(weapon.Combatants)
		if ok and type(list) == "table" then
			for _, model in ipairs(list) do
				if typeof(model) == "Instance" and model:IsA("Model") and model:GetAttribute("Slot") == slot then
					return model
				end
			end
		end
	end
	return nil
end

-- Leuchtspur-Id + Team eines fremden Schützen (Roster/Armed.Tracers, sonst Modell-Attribute); kurz gemerkt
local function shooterLook(slot: number): (string?, number?)
	local now = os.clock()
	local cached = slotLooks[slot]
	if cached and now - cached.At < SLOT_REFRESH then
		return cached.Tracer, cached.Team
	end
	local entry = rosterBySlot[slot]
	local tracer = entry and entry.Tracer
	local team = entry and entry.Team
	-- Vertrag mit WP3/G3: WeaponClient.TracerOfSlot(slot) liest das Attribut "Tracer" des Schützen-Modells
	local weapon = ctx and ctx.Modules and ctx.Modules.WeaponClient
	if tracer == nil and weapon and type(weapon.TracerOfSlot) == "function" then
		local ok, id = pcall(weapon.TracerOfSlot, slot)
		if ok and type(id) == "string" and id ~= "" then
			tracer = id
		end
	end
	if tracer == nil or team == nil then
		local model = modelForSlot(slot, entry and entry.Id)
		if model then
			local attrTracer = model:GetAttribute("Tracer")
			if tracer == nil and type(attrTracer) == "string" and attrTracer ~= "" then
				tracer = attrTracer
			end
			local attrTeam = model:GetAttribute("Team")
			if team == nil and type(attrTeam) == "number" then
				team = attrTeam
			end
		end
	end
	slotLooks[slot] = { Tracer = tracer, Team = team, At = now }
	return tracer, team
end

local function onFx(b: any)
	if typeof(b) ~= "buffer" or not ctx then
		return
	end
	local ok, entries = pcall(ctx.Net.DecodeFx, b, arenaOrigin)
	if not ok or type(entries) ~= "table" then
		return
	end
	local fxCount = 0
	for _, entry in ipairs(entries) do
		fxCount += 1
		if fxCount > 58 then
			break
		end
		local def = weaponDefById(entry.Weapon)
		local key = if type(def) == "table" and type(def.Key) == "string" then def.Key else ""
		local o: Vector3, e: Vector3 = entry.O, entry.E
		if entry.Kind == 1 or entry.Kind == 2 then
			local tracerId, team = shooterLook(entry.Slot)
			CombatFX.Tracer(o, e, nil, tracerId or defaultTracer(), team or -1)
			CombatFX.Impact(e, (o - e), if entry.Kind == 2 then "Player" else "Surface")
			if (e - o).Magnitude > 0.5 then
				CombatFX.Muzzle(CFrame.lookAt(o, e), key)
			end
			local role = shotRole(def)
			if role then
				sfx(role, o)
			end
		elseif entry.Kind == 3 then
			sfx("MeleeSwing", o)
			if (e - o).Magnitude > 0.5 then
				sfx("MeleeHit", e)
				CombatFX.Impact(e, o - e, "Player")
			end
		elseif entry.Kind == 4 then
			sfx("Throw", o)
		end
	end
end

-- ---------------------------------------------------------------------
-- FRAME (aus dem einen PreRender-Loop von Main.client)
-- ---------------------------------------------------------------------
function CombatFX.Frame(dt: number)
	if tracersActive > 0 then
		for _, tracer in ipairs(tracers) do
			if tracer.Active then
				tracer.Age += dt
				local t = tracer.Age / tracer.Life
				if t >= 1 then
					tracer.Active = false
					tracer.Beam.Enabled = false
					tracersActive -= 1
				else
					tracer.Beam.Transparency = tracerSeqs[math.clamp(math.floor(t * 5) + 1, 1, #tracerSeqs)]
				end
			end
		end
	end
	local now = os.clock()
	for _, slot in ipairs(lights) do
		if slot.Active and now >= slot.Until then
			slot.Active = false
			slot.Light.Enabled = false
		end
	end
	local serverNow = workspace:GetServerTimeNow()
	for _, slot in ipairs(smokes) do
		if slot.Active then
			local left = slot.Until - serverNow
			if left <= 0 then
				slot.Active = false
				slot.Emitter.Enabled = false
				slot.Ball.Transparency = 1
				slot.Ball.CFrame = HIDDEN_CF
			elseif left < 1 then
				slot.Emitter.Enabled = false
				slot.Ball.Transparency = 0.3 + 0.7 * (1 - left)
			end
		end
	end
	for _, slot in ipairs(warns) do
		if slot.Active then
			local left = slot.Until - serverNow
			if left <= 0 then
				slot.Active = false
				slot.Part.Transparency = 1
				slot.Part.CFrame = HIDDEN_CF
			else
				slot.Part.Transparency = 0.45 + 0.3 * (0.5 + 0.5 * math.sin(now * 14)) -- pulsiert
			end
		end
	end
	stepProjectiles(dt)
end

-- ---------------------------------------------------------------------
-- START
-- ---------------------------------------------------------------------
local function setArena(origin: any, map: any)
	if typeof(origin) == "Vector3" then
		arenaOrigin = origin
	end
	if typeof(map) == "Instance" then
		arenaMap = map
		rayParams.FilterType = Enum.RaycastFilterType.Include
		rayParams.IncludeInstances = { map }
	end
end

local function clearAll()
	for _, p in ipairs(projectiles) do
		if p.Active then
			CombatFX.RemoveProjectile(p.Id)
		end
	end
	for _, slot in ipairs(smokes) do
		slot.Active = false
		slot.Emitter.Enabled = false
		slot.Ball.Transparency = 1
		slot.Ball.CFrame = HIDDEN_CF
	end
	for _, slot in ipairs(warns) do
		slot.Active = false
		slot.Part.Transparency = 1
		slot.Part.CFrame = HIDDEN_CF
	end
end

function CombatFX.Init(context: any)
	ctx = context
	local config = ctx.Config
	local pools = config and config.Client and config.Client.Pools
	if type(pools) == "table" then
		for key in pairs(poolSizes) do
			local value = pools[key]
			if type(value) == "number" and value >= 1 then
				poolSizes[key] = math.clamp(math.floor(value), 1, 128)
			end
		end
	end
	local client = config and config.Client
	if client then
		FX_RANGE = tonumber(client.FxRange) or FX_RANGE
		FINISHER_RANGE = tonumber(client.FinisherRange) or FINISHER_RANGE
	end
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local ballisticsModule = shared and shared:FindFirstChild("Ballistics")
	if ballisticsModule and ballisticsModule:IsA("ModuleScript") then
		local ok, result = pcall(require, ballisticsModule)
		ballistics = if ok then result else nil
	end
	local cosmeticModule = shared and shared:FindFirstChild("CosmeticModels")
	if cosmeticModule and cosmeticModule:IsA("ModuleScript") then
		local ok, result = pcall(require, cosmeticModule)
		cosmeticModels = if ok
				and type(result) == "table"
				and type(result.TracerStyle) == "function"
			then result
			else nil
	end

	local newFolder = Instance.new("Folder")
	newFolder.Name = "ClutchClashCombatFX"
	newFolder.Parent = workspace
	folder = newFolder
	local newAnchor = Instance.new("Part")
	newAnchor.Name = "FxAnchor"
	newAnchor.Anchored = true
	newAnchor.CanCollide = false
	newAnchor.CanQuery = false
	newAnchor.CanTouch = false
	newAnchor.CastShadow = false
	newAnchor.Transparency = 1
	newAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
	newAnchor.CFrame = CFrame.new() -- im Ursprung: Attachment.Position == Weltposition
	newAnchor.Parent = newFolder
	anchor = newAnchor
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.ExcludeInstances = { newFolder }

	buildTracers()
	buildImpacts()
	buildMuzzles()
	buildExplosions()
	buildSmokes()
	buildLights()
	buildPops()
	buildWarns()
	buildProjectiles()

	local hooks = ctx.Hooks
	hooks.On("Match:Start", function(data)
		setArena(data.Origin, nil)
		matchFfa = data.Mode == "FFA"
		table.clear(rosterBySlot)
		table.clear(slotLooks)
		if type(data.Roster) == "table" then
			for _, entry in ipairs(data.Roster) do
				local slot = type(entry) == "table" and tonumber(entry.Slot) or nil
				if slot then
					rosterBySlot[slot] = {
						Id = tonumber(entry.Id),
						Team = tonumber(entry.Team),
						Tracer = if type(entry.Tracer) == "string" and entry.Tracer ~= "" then entry.Tracer else nil,
					}
				end
			end
		end
	end)
	hooks.On("Combat:Armed", function(data)
		myCombatId = tonumber(data.Id) or player.UserId
		myTeam = tonumber(data.Team) or 0
		ownTracer = if type(data.Tracer) == "string" and data.Tracer ~= "" then data.Tracer else nil
		table.clear(slotLooks)
		if data.Ctx == "Range" then
			matchFfa = false
		end
		-- optional: Leuchtspuren der anderen im Kontext { [slot] = tracerId }
		if type(data.Tracers) == "table" then
			for slot, id in pairs(data.Tracers) do
				local n = tonumber(slot)
				if n and type(id) == "string" and id ~= "" then
					local entry = rosterBySlot[n] or {}
					entry.Tracer = id
					rosterBySlot[n] = entry
				end
			end
		end
		setArena(data.Origin, data.Map)
	end)
	hooks.On("Match:Closed", function()
		table.clear(rosterBySlot)
		table.clear(slotLooks)
		matchFfa = false
	end)
	hooks.On("Combat:Disarmed", clearAll)
	hooks.On("Match:Closed", clearAll)
	hooks.On("Combat:Proj", onServerProjectile)
	hooks.On("Combat:Boom", function(data)
		if type(data) ~= "table" then
			return
		end
		if type(data.Warn) == "number" and typeof(data.P) == "Vector3" then
			-- Vorwarnung (Orbital-Schlag): nur Warnkreis, der echte Einschlag kommt als eigenes "Boom"
			showWarn(data.P, tonumber(data.R) or 10, data.Warn)
			return
		end
		CombatFX.RemoveProjectile("S" .. tostring(data.Id))
		if typeof(data.P) == "Vector3" then
			CombatFX.Explosion(data.P, tonumber(data.R) or 10)
		end
	end)
	hooks.On("Combat:Smoke", function(data)
		if type(data) == "table" and typeof(data.P) == "Vector3" then
			CombatFX.Smoke(data.P, tonumber(data.R) or 13, tonumber(data.Until) or 0)
		end
	end)
	local fxRemote = ctx.Remotes and ctx.Remotes.FX
	if fxRemote and fxRemote:IsA("UnreliableRemoteEvent") then
		fxRemote.OnClientEvent:Connect(onFx)
	end
end

function CombatFX.Start() end

return CombatFX
