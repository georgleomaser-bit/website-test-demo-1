-- =====================================================================
--  CLUTCH CLASH – Projektile (Server/Services/ProjectileService)
--  Besitzer: WP3 (Kampf Server & Treffer-Mathematik). Vertrag: DESIGN.md C5.4, C11, B11.2/B11.5/B11.7, B12.
--  Logische Projektile OHNE Parts auf dem Server: { Id, Owner, Def, P, V, G, Born, Bounces, Ctx, ShotId }
--  in einem Array pro Kontext, ≤ 40 pro Arena, ≤ 160 gesamt (ältestes fällt raus).
--  Ein EveryFrame-Schritt: Segment-Raycast alt -> neu gegen MapParams + analytische Hitboxen der Gegner
--  (Kugel-gegen-Strahl, Projektil-Radius 0.5).
--    Rakete: Direkttreffer -> Direct aufs Ziel, Splash auf andere; Wand -> Splash. Raketensprung (eigene Rakete
--            ≤ 4 Studs von den Füßen) -> Impulse 55 nach oben + AntiCheat-Gnade "Launch" 1.5 s.
--    Granate: Ballistics.Reflect (Restitution 0.35), max. 2 Abpraller, Zünder 2.0 s ab Wurf.
--    Rauch: platzt bei erster Landung (spätestens 2.0 s) -> Rauchkugel { P, R = 13, Until } (analytisch).
--    Explosion: über alle Combatants des Kontexts (keine Spatial Queries), Sichtlinie zum Mittelpunkt gegen
--               MapParams, linearer Abfall Damage.Splash, Selbstschaden × SelfMult.
--    Admin: Schwarzes Loch (Wirbel 4 s, Zug, 25/s, dann Implosion 150), Orbital-Schlag (Strike).
--  Clients: Combat("Proj"), Combat("Boom"), Combat("Smoke") an Context.Recipients().
--
--  Öffentliche API (C5.4):
--    ProjectileService.Spawn(owner, def, origin, velocity, age, shotId): number?
--    ProjectileService.ClearCtx(ctx)
--    ProjectileService.IsSmoked(ctx, a, b): boolean
--    ProjectileService.Count(): number
--  Ergänzung (Admin-Waffe Orbital-Laser, WeaponService):
--    ProjectileService.Strike(owner, def, pos, delay, radius, damage)
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Hitbox = require(Shared:WaitForChild("Hitbox"))
local Damage = require(Shared:WaitForChild("Damage"))
local Ballistics = require(Shared:WaitForChild("Ballistics"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))

local ProjectileService = {}
local Services: any

type Combatant = Types.Combatant
type WeaponDef = Types.WeaponDef
type Proj = {
	Id: number,
	Owner: Combatant,
	Def: WeaponDef,
	P: Vector3,
	V: Vector3,
	G: number,
	Born: number,
	Bounces: number,
	Ctx: string,
	ShotId: number,
	Resting: boolean,
}
type Smoke = { P: Vector3, R: number, Until: number }
type Vortex = { Id: number, Owner: Combatant, Def: WeaponDef, P: Vector3, Until: number, Next: number }
type Strike = { Owner: Combatant, Def: WeaponDef, P: Vector3, At: number, R: number, Damage: number }

local COMBAT: any = Config.Combat
local SERVER: any = Config.Server
local ADMIN: any = COMBAT.Admin or {}
local PER_ARENA = math.max(1, math.floor(tonumber(SERVER.MaxProjectilesPerArena) or 40))
local TOTAL_MAX = math.max(PER_ARENA, math.floor(tonumber(SERVER.MaxProjectilesTotal) or 160))
local PROJ_RADIUS = tonumber(COMBAT.ProjectileRadius) or 0.5
local MAX_FF = tonumber(COMBAT.MaxFastForward) or 0.15
local MAX_SMOKES = 12 -- pro Kontext
local MAX_VORTICES = 4
local MAX_STRIKES = 8
local REST_SPEED = 4 -- darunter bleibt eine Granate liegen
local SURFACE_OFFSET = 0.2

local projs: { [string]: { Proj } } = {}
local smokes: { [string]: { Smoke } } = {}
local vortices: { [string]: { Vortex } } = {}
local strikes: { [string]: { Strike } } = {}
local total = 0
local nextId = 0

local function now(): number
	return workspace:GetServerTimeNow()
end

local function num(v: any, default: number): number
	if Util.IsFinite(v) then
		return v
	end
	return default
end

local function call(serviceName: string, fnName: string, ...: any): (boolean, any)
	local service = Services and Services[serviceName]
	local fn = service and service[fnName]
	if type(fn) ~= "function" then
		return false, nil
	end
	return pcall(fn, ...)
end

local function newId(): number
	nextId = (nextId % 2147483646) + 1
	return nextId
end

local function contextOf(ctx: string): Types.ContextInfo?
	return Services.CombatService.Context(ctx)
end

local function mapParams(info: Types.ContextInfo): RaycastParams?
	local arena: any = info.Arena
	local params = arena and arena.MapParams
	if typeof(params) == "RaycastParams" then
		return params
	end
	return nil
end

local function fireCtx(ctx: string, op: string, data: { [string]: any })
	call("ReplicationService", "FireCtx", ctx, "Combat", op, data)
end

local function partsAlive(c: Combatant): boolean
	return c.Alive and c.Root.Parent ~= nil and c.Head.Parent ~= nil
end

local function headRadius(info: Types.ContextInfo): number
	return num(COMBAT.HeadRadius, 0.8) * num(info.Rules.HeadRadiusMult, 1)
end

-- Sichtlinie a -> b nur gegen die Map (Glas blockiert, Barrieren nicht – MapParams)
local function clearLine(params: RaycastParams?, a: Vector3, b: Vector3): boolean
	if not params then
		return true
	end
	local d = b - a
	if d.Magnitude < 1e-3 then
		return true
	end
	return workspace:Raycast(a, d, params) == nil
end

-- Impuls an einen Combatant (Spieler: Client setzt die Geschwindigkeit; Bots: Server direkt)
local function impulse(c: Combatant, v: Vector3, graceKind: "Impulse" | "Launch", seconds: number)
	if not Util.IsFiniteVector(v) then
		return
	end
	if c.Player then
		call("AntiCheatService", "Grace", c.Player, graceKind, seconds, num(COMBAT.ImpulseMaxSpeed, 95))
		Remotes.Combat:FireClient(c.Player, "Impulse", { V = v })
	elseif c.Kind == "Bot" and c.Root.Parent and not c.Root.Anchored then
		c.Root.AssemblyLinearVelocity = v
	end
end

local function feetOf(c: Combatant): Vector3
	local hip = if c.Humanoid then c.Humanoid.HipHeight else 2
	return c.Root.Position - Vector3.new(0, c.Root.Size.Y / 2 + hip, 0)
end

-- ---------------------------------------------------------------------
-- EXPLOSIONEN
-- ---------------------------------------------------------------------
local function splashDamage(
	ctx: string,
	owner: Combatant,
	def: WeaponDef,
	pos: Vector3,
	exclude: Combatant?,
	kind: "Splash" | "Admin",
	fixed: number?
)
	local info = contextOf(ctx)
	if not info then
		return
	end
	local proj: any = def.Projectile or {}
	local radius = num(proj.Radius, 0)
	local params = mapParams(info)
	local mult = num(info.Rules.DamageMult, 1)
	local combat = Services.CombatService
	for _, c in ipairs(combat.InCtx(ctx)) do
		if c == exclude or not partsAlive(c) then
			continue
		end
		if c ~= owner and not combat.IsEnemy(owner, c) then
			continue
		end
		local dist = Hitbox.PointDistance(pos, c.Root.CFrame, c.Head.Position)
		if dist >= radius then
			continue
		end
		if not clearLine(params, pos, c.Root.Position) then
			continue -- Sichtlinie zum Mittelpunkt blockiert
		end
		local amount = if fixed then fixed else Damage.Splash(def, dist)
		amount *= mult
		if c == owner then
			amount *= num(proj.SelfMult, 0)
		end
		if amount > 0 then
			combat.ApplyDamage(owner, c, amount, {
				WeaponKey = def.Key,
				Head = false,
				Kind = kind,
				Dist = dist,
				From = pos,
			})
		end
	end
end

local function rocketJump(owner: Combatant, def: WeaponDef, pos: Vector3)
	local proj: any = def.Projectile
	if def.AdminOnly or not proj or proj.Fuse ~= nil or num(proj.SelfMult, 0) <= 0 then
		return
	end
	if not partsAlive(owner) then
		return
	end
	local jump: any = COMBAT.RocketJump or {}
	local feet = feetOf(owner)
	if (pos - feet).Magnitude > num(jump.Radius, 4) then
		return
	end
	local current = owner.Root.AssemblyLinearVelocity
	local away = Vector3.new(feet.X - pos.X, 0, feet.Z - pos.Z)
	local push = if away.Magnitude > 0.05 then away.Unit * 12 else Vector3.zero
	local v = Vector3.new(current.X, 0, current.Z) + push + Vector3.new(0, num(jump.Up, 55), 0)
	impulse(owner, v, "Launch", num(COMBAT.ImpulseGrace, 1.5))
end

local function explode(p: Proj, pos: Vector3, direct: Combatant?)
	local def = p.Def
	local proj: any = def.Projectile or {}
	local info = contextOf(p.Ctx)
	if not info then
		return
	end
	local combat = Services.CombatService
	if direct and partsAlive(direct) then
		local amount = num(proj.Direct, def.Damage) * num(info.Rules.DamageMult, 1)
		if amount > 0 then
			combat.ApplyDamage(p.Owner, direct, amount, {
				WeaponKey = def.Key,
				Head = false,
				Kind = "Splash",
				Dist = (pos - p.P).Magnitude,
				From = p.P,
			})
		end
	end
	splashDamage(p.Ctx, p.Owner, def, pos, direct, "Splash", nil)
	rocketJump(p.Owner, def, pos)
	fireCtx(p.Ctx, "Boom", { Id = p.Id, P = pos, R = num(proj.Radius, 0), W = def.Id })
end

local function addSmoke(ctx: string, pos: Vector3, def: WeaponDef)
	local smoke: any = def.Smoke or {}
	local list = smokes[ctx]
	if not list then
		list = {}
		smokes[ctx] = list
	end
	local entry: Smoke = { P = pos, R = num(smoke.Radius, 13), Until = now() + num(smoke.Duration, 9) }
	table.insert(list, entry)
	while #list > MAX_SMOKES do
		table.remove(list, 1)
	end
	fireCtx(ctx, "Smoke", { P = entry.P, R = entry.R, Until = entry.Until })
end

local function addVortex(p: Proj, pos: Vector3)
	local list = vortices[p.Ctx]
	if not list then
		list = {}
		vortices[p.Ctx] = list
	end
	local untilT = now() + num(ADMIN.VortexTime, 4)
	table.insert(list, { Id = p.Id, Owner = p.Owner, Def = p.Def, P = pos, Until = untilT, Next = now() })
	while #list > MAX_VORTICES do
		table.remove(list, 1)
	end
	fireCtx(p.Ctx, "Boom", {
		Id = p.Id,
		P = pos,
		R = num(ADMIN.VortexPullRadius, 25),
		W = p.Def.Id,
		Vortex = untilT,
	})
end

-- Aufprall je nach Art: true = Projektil ist fertig
local function impact(p: Proj, pos: Vector3, normal: Vector3, direct: Combatant?): boolean
	local def = p.Def
	local proj: any = def.Projectile or {}
	local surface = pos + normal * SURFACE_OFFSET
	if def.Smoke then
		addSmoke(p.Ctx, surface, def)
		return true
	end
	if def.Key == "BlackHoleCannon" then
		addVortex(p, surface)
		return true
	end
	if proj.Fuse ~= nil then
		return false -- Granate: Abprall regelt der Schritt
	end
	explode(p, surface, direct)
	return true
end

-- ---------------------------------------------------------------------
-- BEWEGUNG
-- ---------------------------------------------------------------------
local function syncClients(p: Proj)
	fireCtx(p.Ctx, "Proj", {
		Id = p.Id,
		Own = p.Owner.Id,
		Shot = p.ShotId,
		W = p.Def.Id,
		O = p.P,
		V = p.V,
		G = p.G,
		T = now(),
	})
end

local function collidesWithCombatants(def: WeaponDef): boolean
	local proj: any = def.Projectile
	return proj ~= nil and proj.Fuse == nil -- Raketen/Admin-Kugeln ja, Granaten/Rauch fliegen durch
end

-- Ein Schritt; true = entfernen
local function step(p: Proj, dt: number): boolean
	local info = contextOf(p.Ctx)
	if not info then
		return true
	end
	local def = p.Def
	local proj: any = def.Projectile or {}
	local age = now() - p.Born
	if proj.Fuse ~= nil and age >= num(proj.Fuse, 2) then
		if def.Smoke then
			addSmoke(p.Ctx, p.P, def)
		else
			explode(p, p.P, nil)
		end
		return true
	end
	if age >= num(proj.Lifetime, 4) and proj.Fuse == nil then
		if def.Key == "BlackHoleCannon" then
			addVortex(p, p.P)
		end
		return true
	end
	if p.Resting then
		return false
	end

	local newP, newV = Ballistics.Step(p.P, p.V, p.G, dt)
	local seg = newP - p.P
	local len = seg.Magnitude
	if len < 1e-5 then
		p.V = newV
		return false
	end
	local params = mapParams(info)
	local mapHit = if params then workspace:Raycast(p.P, seg, params) else nil
	local mapDist = if mapHit then (mapHit.Position - p.P).Magnitude else math.huge

	if collidesWithCombatants(def) then
		local combat = Services.CombatService
		local best: Combatant? = nil
		local bestDist = math.huge
		local headR = headRadius(info)
		for _, c in ipairs(combat.Members(p.Ctx)) do
			if c == p.Owner or not partsAlive(c) or not combat.IsEnemy(p.Owner, c) then
				continue
			end
			local region, d = Hitbox.Ray(p.P, seg, len, c.Root.CFrame, c.Head.Position, headR, PROJ_RADIUS)
			if region and d and d < bestDist then
				best = c
				bestDist = d
			end
		end
		if best and bestDist <= mapDist then
			local hitPos = p.P + seg.Unit * bestDist
			return impact(p, hitPos, -seg.Unit, best)
		end
	end

	if mapHit then
		if impact(p, mapHit.Position, mapHit.Normal, nil) then
			return true
		end
		-- Granate: abprallen oder liegen bleiben
		local frac = math.clamp(mapDist / len, 0, 1)
		local vHit = p.V + (newV - p.V) * frac
		local maxBounces = math.floor(num(proj.Bounces, 0))
		local bounced = Ballistics.Reflect(vHit, mapHit.Normal, num(proj.Restitution, 0.35))
		p.P = mapHit.Position + mapHit.Normal * SURFACE_OFFSET
		if p.Bounces < maxBounces and bounced.Magnitude >= REST_SPEED then
			p.Bounces += 1
			p.V = bounced
		else
			p.V = Vector3.zero
			p.G = 0
			p.Resting = true
		end
		syncClients(p)
		return false
	end

	p.P = newP
	p.V = newV
	return false
end

-- ---------------------------------------------------------------------
-- ADMIN: WIRBEL & ORBITAL-SCHLAG
-- ---------------------------------------------------------------------
local function stepVortex(ctx: string, v: Vortex, t: number): boolean
	local info = contextOf(ctx)
	if not info then
		return true
	end
	if t >= v.Until then
		-- Implosion
		local proj: any = v.Def.Projectile or {}
		splashDamage(ctx, v.Owner, v.Def, v.P, nil, "Admin", num(proj.SplashMax, 150))
		fireCtx(ctx, "Boom", { Id = v.Id, P = v.P, R = num(proj.Radius, 18), W = v.Def.Id })
		return true
	end
	if t < v.Next then
		return false
	end
	local hz = math.max(1, num(ADMIN.VortexHz, 4))
	v.Next = t + 1 / hz
	local combat = Services.CombatService
	local pullRadius = num(ADMIN.VortexPullRadius, 25)
	local damageRadius = num(ADMIN.VortexDamageRadius, 18)
	local pull = num(ADMIN.VortexPull, 28)
	local tickDamage = num(ADMIN.VortexDps, 25) / hz * num(info.Rules.DamageMult, 1)
	for _, c in ipairs(combat.InCtx(ctx)) do
		if c == v.Owner or not partsAlive(c) or not combat.IsEnemy(v.Owner, c) then
			continue
		end
		local offset = v.P - c.Root.Position
		local dist = offset.Magnitude
		if dist <= pullRadius and dist > 0.5 then
			impulse(c, offset.Unit * pull + Vector3.new(0, 6, 0), "Impulse", 1 / hz + 0.5)
		end
		if dist <= damageRadius then
			combat.ApplyDamage(v.Owner, c, tickDamage, {
				WeaponKey = v.Def.Key,
				Head = false,
				Kind = "Admin",
				Dist = dist,
				From = v.P,
			})
		end
	end
	return false
end

local function stepStrike(ctx: string, s: Strike, t: number): boolean
	if t < s.At then
		return false
	end
	local info = contextOf(ctx)
	if not info then
		return true
	end
	local combat = Services.CombatService
	for _, c in ipairs(combat.InCtx(ctx)) do
		if c == s.Owner or not partsAlive(c) or not combat.IsEnemy(s.Owner, c) then
			continue
		end
		local d = c.Root.Position - s.P
		local horizontal = Vector3.new(d.X, 0, d.Z).Magnitude
		if horizontal <= s.R then
			combat.ApplyDamage(s.Owner, c, s.Damage, {
				WeaponKey = s.Def.Key,
				Head = false,
				Kind = "Admin",
				Dist = horizontal,
				From = s.P + Vector3.new(0, 200, 0),
			})
		end
	end
	fireCtx(ctx, "Boom", { Id = 0, P = s.P, R = s.R, W = s.Def.Id })
	return true
end

function ProjectileService.Strike(
	owner: Combatant,
	def: WeaponDef,
	pos: Vector3,
	delay: number,
	radius: number,
	damage: number
)
	if type(owner) ~= "table" or not Util.IsFiniteVector(pos) then
		return
	end
	local ctx = owner.Ctx
	local list = strikes[ctx]
	if not list then
		list = {}
		strikes[ctx] = list
	end
	local at = now() + math.clamp(num(delay, 1), 0, 10)
	table.insert(list, { Owner = owner, Def = def, P = pos, At = at, R = num(radius, 10), Damage = num(damage, 999) })
	while #list > MAX_STRIKES do
		table.remove(list, 1)
	end
	fireCtx(ctx, "Boom", { Id = 0, P = pos, R = num(radius, 10), W = def.Id, Warn = at }) -- roter Warnkreis
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICHE API
-- ---------------------------------------------------------------------
local function dropOldestGlobal()
	local oldestCtx: string? = nil
	local oldestBorn = math.huge
	for ctx, list in pairs(projs) do
		local first = list[1]
		if first and first.Born < oldestBorn then
			oldestBorn = first.Born
			oldestCtx = ctx
		end
	end
	if oldestCtx then
		table.remove(projs[oldestCtx], 1)
		total -= 1
	end
end

function ProjectileService.Spawn(
	owner: Combatant,
	def: WeaponDef,
	origin: Vector3,
	velocity: Vector3,
	age: number,
	shotId: number
): number?
	if type(owner) ~= "table" or type(def) ~= "table" or type(def.Projectile) ~= "table" then
		return nil
	end
	if not Util.IsFiniteVector(origin) or not Util.IsFiniteVector(velocity) then
		return nil
	end
	local ctx = owner.Ctx
	if not contextOf(ctx) then
		return nil
	end
	local list = projs[ctx]
	if not list then
		list = {}
		projs[ctx] = list
	end
	while #list >= PER_ARENA do
		table.remove(list, 1) -- ältestes fällt raus
		total -= 1
	end
	while total >= TOTAL_MAX do
		dropOldestGlobal()
	end
	local a = math.clamp(num(age, 0), 0, 1)
	local p: Proj = {
		Id = newId(),
		Owner = owner,
		Def = def,
		P = origin,
		V = velocity,
		G = num(def.Projectile.Gravity, 0),
		Born = now() - a,
		Bounces = 0,
		Ctx = ctx,
		ShotId = math.floor(num(shotId, 0)),
		Resting = false,
	}
	fireCtx(ctx, "Proj", {
		Id = p.Id,
		Own = owner.Id,
		Shot = p.ShotId,
		W = def.Id,
		O = origin,
		V = velocity,
		G = p.G,
		T = p.Born,
	})
	-- um min(Alter, 0.15) vorspulen (mit Kollision)
	local ff = math.min(a, MAX_FF)
	if ff > 0 and step(p, ff) then
		return p.Id
	end
	table.insert(list, p)
	total += 1
	return p.Id
end

function ProjectileService.ClearCtx(ctx: string)
	local list = projs[ctx]
	if list then
		total -= #list
	end
	projs[ctx] = nil
	smokes[ctx] = nil
	vortices[ctx] = nil
	strikes[ctx] = nil
	if total < 0 then
		total = 0
	end
end

function ProjectileService.IsSmoked(ctx: string, a: Vector3, b: Vector3): boolean
	local list = smokes[ctx]
	if not list or not Util.IsFiniteVector(a) or not Util.IsFiniteVector(b) then
		return false
	end
	local t = now()
	local ab = b - a
	local lenSq = ab:Dot(ab)
	for _, s in ipairs(list) do
		if s.Until > t then
			local alpha = if lenSq > 1e-9 then math.clamp((s.P - a):Dot(ab) / lenSq, 0, 1) else 0
			local closest = a + ab * alpha
			if (s.P - closest).Magnitude <= s.R then
				return true
			end
		end
	end
	return false
end

function ProjectileService.Count(): number
	return total
end

-- ---------------------------------------------------------------------
-- TAKT (jeden Frame)
-- ---------------------------------------------------------------------
local function frame(dt: number)
	local t = now()
	for ctx, list in pairs(projs) do
		for i = #list, 1, -1 do
			local p = list[i]
			local ok, remove = pcall(step, p, dt)
			if not ok then
				warn("[ProjectileService] Schritt-Fehler: " .. tostring(remove))
				remove = true
			end
			if projs[ctx] ~= list then
				break -- Kontext wurde währenddessen geleert (ClearCtx)
			end
			if remove and list[i] == p then
				table.remove(list, i)
				total -= 1
			end
		end
		if projs[ctx] == list and #list == 0 then
			projs[ctx] = nil
		end
	end
	for ctx, list in pairs(smokes) do
		for i = #list, 1, -1 do
			if list[i].Until <= t then
				table.remove(list, i)
			end
		end
		if #list == 0 then
			smokes[ctx] = nil
		end
	end
	for ctx, list in pairs(vortices) do
		for i = #list, 1, -1 do
			local v = list[i]
			if stepVortex(ctx, v, t) and list[i] == v then
				table.remove(list, i)
			end
		end
		if #list == 0 then
			vortices[ctx] = nil
		end
	end
	for ctx, list in pairs(strikes) do
		for i = #list, 1, -1 do
			local s = list[i]
			if stepStrike(ctx, s, t) and list[i] == s then
				table.remove(list, i)
			end
		end
		if #list == 0 then
			strikes[ctx] = nil
		end
	end
	if total < 0 then
		total = 0
	end
end

function ProjectileService.Init(services: any)
	Services = services
end

function ProjectileService.Start()
	Scheduler.EveryFrame("Projectiles", frame)
end

return ProjectileService
