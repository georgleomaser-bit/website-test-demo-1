-- =====================================================================
--  CLUTCH CLASH – Waffen & Treffer-Prüfung (Server/Services/WeaponService)
--  Besitzer: WP3 (Kampf Server & Treffer-Mathematik). Vertrag: DESIGN.md C5.4, C10, C12.2, B11, B12.
--  Server ist Autorität für Munition, Treffer und Schaden. Der Client sendet nur Absichten:
--    Fire(shotId, weaponId, t, origin, aim, scale, targets)       -> komplette C10-Prüfung (billig -> teuer)
--    WeaponAction("Equip"|"Reload"|"Ads"|"Block"|"Melee"|"Throw"|"Use", …)
--  Remote-Hygiene (Muss-Regel 8): Rate-Limit -> typeof -> endlich/NaN -> Klemmen -> Zustand -> pcall.
--  Reject-Codes: TYPE, RATE, STATE, TIME, ORIGIN, HITBOX, LOS, RANGE (+ TARGET für ungültige Ziele, ohne Verdacht).
--  Verdacht über AntiCheatService.Add (Gewichte aus Config.Security.Weights), nie selbst kicken.
--  Admin-Kräfte (nur über AdminService.Power): AdminInfAmmo, AdminNoReload, AdminRapidFire (1–5),
--  AdminOneShot, AdminSilentAim. Admin-Waffen 101–104 nur für den Besitzer; Nutzung im Match -> MatchService.Taint.
--
--  Öffentliche API (C5.4):
--    WeaponService.SetLoadout(c, loadout)        Besitz/Slot/Regeln prüfen, Munition voll, Modelle, Combat("Armed")
--    WeaponService.ResetForRound(c)              alles voll (Rundenstart/Respawn)
--    WeaponService.Equip(c, slot)
--    WeaponService.ServerFire(c, aim, opts?): boolean      Bots: gleiche Mathematik, ohne Paket-Checks/Rückspulen
--    WeaponService.ServerMelee(c, target?): boolean
--    WeaponService.ServerThrow(c, aim, charge): boolean
--    WeaponService.ServerUse(c): boolean
--    WeaponService.GiveAdminWeapon(p, id): boolean
--    WeaponService.OnShot(cb)                    cb(c, def, hits, heads) nach jedem gewerteten Schuss
--  Ergänzungen:
--    WeaponService.Forget(c)                     Pro-Combatant-Zustand löschen (CombatService.Unregister)
--    WeaponService.TestFire(c, packet, opts): (boolean, string?)   synthetische Prüfung (CombatTests, DryRun)
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Spread = require(Shared:WaitForChild("Spread"))
local Hitbox = require(Shared:WaitForChild("Hitbox"))
local Damage = require(Shared:WaitForChild("Damage"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))

local WeaponService = {}
local Services: any

type Combatant = Types.Combatant
type WeaponDef = Types.WeaponDef
type SlotName = Types.SlotName
type AmmoState = Types.AmmoState
type HealState = { TickAt: number, Left: number, Per: number, Step: number }
type WState = {
	RecvLast: number, -- os.clock() des letzten angenommenen Schusses (Empfangsabstand)
	SwingId: number,
	SwingT: number,
	ThrowId: number,
	Heal: HealState?,
	AmmoFixAt: number, -- letzte Munitions-Korrektur (höchstens 2/s)
}
export type FirePacket = {
	ShotId: any,
	WeaponId: any,
	T: any,
	Origin: any,
	Aim: any,
	Scale: any,
	Targets: any,
}
export type FireOpts = { Recv: number, Now: number, Ping: number, DryRun: boolean? }
type PelletHit = { Target: Combatant, Damage: number, Head: boolean, Dist: number, Hits: number, Heads: number }

local COMBAT: any = Config.Combat
local PLAYER: any = Config.Player
local SECURITY: any = Config.Security
local DEBUG: any = Config.Debug
local ADMIN: any = COMBAT.Admin or {}
local WEIGHTS: any = SECURITY.Weights or {}
local SLOT_NAMES: { SlotName } = { "Primary", "Secondary", "Melee", "Utility" }
local PRIMARY: SlotName = "Primary"
local UTILITY: SlotName = "Utility"
local LIVE_PHASES = { Live = true, Overtime = true, SuddenDeath = true }
local MAX_SHOT_TIMES = 32
local MAX_TARGETS = 32
local PHASE_CACHE_SECONDS = 0.25
local TICK_HZ = 20
local HEAL_STEP = 0.25 -- +5 alle 0.25 s
local MISS_TRACE = 300 -- Tracer-Länge ohne Treffer (Studs)

local DEFAULT_RULES: Types.ContextRules = {
	DamageMult = 1,
	HeadOnly = false,
	HeadRadiusMult = 1,
	IntervalMult = 1,
	ReloadMult = 1,
	SpeedMult = 1,
	GravityLift = 0,
	RandomLoadout = false,
	Regen = false,
	UtilityMode = "Charges",
	FriendlyFire = false,
	IgnoreOwnership = true,
}

local function bucketCfg(name: string, cap: number, rate: number): (number, number)
	local b = SECURITY.Buckets and SECURITY.Buckets[name]
	if type(b) == "table" then
		return tonumber(b[1]) or cap, tonumber(b[2]) or rate
	end
	return cap, rate
end

local FIRE_CAP, FIRE_RATE = bucketCfg("Fire", 12, 20)
local ACTION_CAP, ACTION_RATE = bucketCfg("WeaponAction", 12, 12)
local fireBucket = Util.TokenBucket(FIRE_CAP, FIRE_RATE)
local actionBucket = Util.TokenBucket(ACTION_CAP, ACTION_RATE)

local wstates: { [Combatant]: WState } = {}
local active: { [Combatant]: boolean } = {} -- Combatants mit laufendem Nachladen/Block/Heilen
local shotCallbacks: { (Combatant, WeaponDef, number, number) -> () } = {}
local phaseCache: { [number]: { At: number, Live: boolean } } = {}
local tainted: { [number]: boolean } = {}
local taintedCount = 0

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function now(): number
	return workspace:GetServerTimeNow()
end

local function num(v: any, default: number): number
	if Util.IsFinite(v) then
		return v
	end
	return default
end

local function isInt(v: any): boolean
	return Util.IsFinite(v) and v % 1 == 0
end

local function call(serviceName: string, fnName: string, ...: any): (boolean, any)
	local service = Services and Services[serviceName]
	local fn = service and service[fnName]
	if type(fn) ~= "function" then
		return false, nil
	end
	return pcall(fn, ...)
end

local function combat(): any
	return Services.CombatService
end

local function stateOf(c: Combatant): WState
	local s = wstates[c]
	if not s then
		s = { RecvLast = 0, SwingId = 0, SwingT = 0, ThrowId = 0, Heal = nil, AmmoFixAt = 0 }
		wstates[c] = s
	end
	return s
end

local function contextOf(c: Combatant): Types.ContextInfo?
	return combat().Context(c.Ctx)
end

local function rulesOf(c: Combatant): Types.ContextRules
	local info = contextOf(c)
	return if info then info.Rules else DEFAULT_RULES
end

local function mapParamsOf(c: Combatant): RaycastParams?
	local info = contextOf(c)
	local arena: any = info and info.Arena
	local params = arena and arena.MapParams
	return if typeof(params) == "RaycastParams" then params else nil
end

local function defIn(c: Combatant, slot: SlotName): WeaponDef?
	local key = (c.Loadout :: any)[slot]
	return if type(key) == "string" then Config.Weapon(key) else nil
end

local function power(c: Combatant, name: string): any
	if not c.Player then
		return nil
	end
	return combat().Power(c, name)
end

local function rapidFactor(c: Combatant): number
	local f = power(c, "AdminRapidFire")
	if f == true then
		return 2
	end
	return if Util.IsFinite(f) then math.clamp(f, 1, 5) else 1
end

local function latency(c: Combatant): number
	local p = c.Player
	if not p then
		return 0
	end
	local ok, ping = pcall(p.GetNetworkPing, p)
	return if ok and Util.IsFinite(ping) then math.clamp(ping, 0, 0.25) else 0
end

local function sendCombat(c: Combatant, op: string, data: { [string]: any })
	local p = c.Player
	if p and p.Parent == Players then
		Remotes.Combat:FireClient(p, op, data)
	end
end

local function sendAmmo(c: Combatant, slot: SlotName)
	local ammo = c.Ammo[slot]
	if not ammo then
		return
	end
	local def = defIn(c, slot)
	local r = if def and def.Slot == "Utility" then ammo.CooldownUntil else ammo.ReloadUntil
	sendCombat(c, "Ammo", { S = slot, M = ammo.Mag, R = r, C = ammo.Charges })
end

-- Ein Match gilt als "tainted", sobald der Besitzer Kräfte/Admin-Waffen benutzt (B25.2)
local function taint(c: Combatant, reason: string)
	local info = contextOf(c)
	local id = info and info.MatchId
	if not id or tainted[id] then
		return
	end
	tainted[id] = true
	taintedCount += 1
	if taintedCount > 200 then
		table.clear(tainted)
		taintedCount = 0
		tainted[id] = true
	end
	call("MatchService", "Taint", id, reason)
end

-- Kontext in Live-Phase? (Range/Tests ohne MatchId immer)
local function contextLive(c: Combatant): boolean
	local info = contextOf(c)
	if not info then
		return false
	end
	local id = info.MatchId
	if id == nil then
		return true
	end
	local clock = os.clock()
	local cached = phaseCache[id]
	if cached and clock - cached.At < PHASE_CACHE_SECONDS then
		return cached.Live
	end
	local live = true -- ohne MatchService (oder ohne Phase) nicht blockieren
	local okPhase, phase = call("MatchService", "Phase", id) -- günstig (WP5-Ergänzung), sonst Info(id).Phase
	if not (okPhase and type(phase) == "string") then
		local ok, result = call("MatchService", "Info", id)
		phase = if ok and type(result) == "table" then result.Phase else nil
	end
	if type(phase) == "string" then
		live = LIVE_PHASES[phase] == true
	end
	phaseCache[id] = { At = clock, Live = live }
	return live
end

local function partsAlive(c: Combatant): boolean
	return c.Alive and c.Root.Parent ~= nil and c.Head.Parent ~= nil
end

local function headRadius(rules: Types.ContextRules): number
	return num(COMBAT.HeadRadius, 0.8) * num(rules.HeadRadiusMult, 1)
end

local function airborne(c: Combatant): boolean
	local h = c.Humanoid
	if not h then
		return false
	end
	local serverAir = h.FloorMaterial == Enum.Material.Air
	if not c.Player then
		return serverAir
	end
	-- Untergrenze großzügig: nur wenn Server UND Client "in der Luft" sagen
	local ok, flags = call("ReplicationService", "Flags", c.Player)
	local clientAir = ok and type(flags) == "number" and bit32.band(flags, 32) ~= 0
	return serverAir and clientAir
end

local function pushShotTime(c: Combatant, t: number)
	table.insert(c.ShotTimes, t)
	while #c.ShotTimes > MAX_SHOT_TIMES do
		table.remove(c.ShotTimes, 1)
	end
end

local function shotsInLastSecond(c: Combatant, t: number): number
	local n = 0
	for i = #c.ShotTimes, 1, -1 do
		local st = c.ShotTimes[i]
		if t - st < 1 and t - st >= 0 then
			n += 1
		elseif t - st >= 1 then
			break
		end
	end
	return n
end

local function finishReload(c: Combatant, slot: SlotName)
	local ammo = c.Ammo[slot]
	local def = defIn(c, slot)
	if ammo and def then
		ammo.Mag = def.Mag
		ammo.ReloadUntil = 0
		ammo.BurstLeft = 0
	end
end

local function endBlock(c: Combatant)
	if not c.Blocking then
		return
	end
	c.Blocking = false
	local def: any = defIn(c, "Melee")
	local block = def and def.Melee and def.Melee.Block
	c.BlockCooldownUntil = now() + num(block and block.Cooldown, 3)
end

local function impulse(c: Combatant, v: Vector3)
	if not Util.IsFiniteVector(v) then
		return
	end
	if c.Player then
		call(
			"AntiCheatService",
			"Grace",
			c.Player,
			"Impulse",
			num(COMBAT.ImpulseGrace, 1.5),
			num(COMBAT.ImpulseMaxSpeed, 95)
		)
		Remotes.Combat:FireClient(c.Player, "Impulse", { V = v })
	elseif c.Kind == "Bot" and c.Root.Parent and not c.Root.Anchored then
		c.Root.AssemblyLinearVelocity = v
	end
end

local function fireShotCallbacks(c: Combatant, def: WeaponDef, hits: number, heads: number)
	for _, cb in ipairs(shotCallbacks) do
		task.defer(function()
			local ok, err = pcall(cb, c, def, hits, heads)
			if not ok then
				warn("[WeaponService] OnShot-Callback: " .. tostring(err))
			end
		end)
	end
end

local function queueFx(c: Combatant, kind: number, weaponId: number, origin: Vector3, endPos: Vector3)
	call("ReplicationService", "QueueFx", c.Ctx, kind, c.Slot, weaponId, origin, endPos)
end

-- Ende eines Strahls ohne Spieler-Treffer (Wand oder max. Tracer-Länge)
local function missEnd(params: RaycastParams?, origin: Vector3, dir: Vector3, range: number): Vector3
	local length = math.min(range, MISS_TRACE)
	if params then
		local hit = workspace:Raycast(origin, dir * range, params)
		if hit then
			return hit.Position
		end
	end
	return origin + dir * length
end

-- Sichtlinie a -> b gegen die Map, um `shorten` vor b gekürzt (Glas blockiert, Barrieren nicht)
local function lineClear(params: RaycastParams?, a: Vector3, b: Vector3, shorten: number): boolean
	if not params then
		return true
	end
	local d = b - a
	local len = d.Magnitude - shorten
	if len <= 0.05 then
		return true
	end
	return workspace:Raycast(a, d.Unit * len, params) == nil
end

-- ---------------------------------------------------------------------
-- REJECT-LOG & VERDACHT
-- ---------------------------------------------------------------------
local AC_REASON = {
	TYPE = { "Type", "Type" },
	RATE = { "Rate", "Rate" },
	STATE = { "State", nil },
	TIME = { "Time", nil },
	ORIGIN = { "Origin", "Origin" },
	HITBOX = { "Hitbox", nil },
	LOS = { "Los", "Los" },
	RANGE = { "Range", nil },
}

local function noteReject(c: Combatant, code: string, shotId: any, opts: FireOpts?)
	if opts and opts.DryRun then
		return
	end
	local p = c.Player
	if not p then
		return
	end
	local entry = AC_REASON[code]
	if entry then
		local weightKey = entry[2]
		local points = if weightKey then num(WEIGHTS[weightKey], 0) else 0
		call(
			"AntiCheatService",
			"Add",
			p,
			entry[1],
			points,
			{ Code = code, Shot = if isInt(shotId) then shotId else 0 }
		)
	end
	if DEBUG.LogRejects == true or c.IsAdmin then
		sendCombat(c, "Reject", { Shot = if isInt(shotId) then shotId else 0, Why = code })
	end
end

-- Munitions-Korrektur nach einem STATE-Reject (höchstens 2/s)
local function ammoFix(c: Combatant, opts: FireOpts?)
	if opts and opts.DryRun then
		return
	end
	local s = stateOf(c)
	local clock = os.clock()
	if clock - s.AmmoFixAt >= 0.5 then
		s.AmmoFixAt = clock
		sendAmmo(c, c.Equipped)
	end
end

-- ---------------------------------------------------------------------
-- SPREAD-UNTERGRENZE (C10 Schritt 7)
-- ---------------------------------------------------------------------
local function minScaleFor(c: Combatant, def: WeaponDef, t: number, speed: number, air: boolean): number
	local adsTime = num(def.AdsTime, 0.15)
	local grace = num(COMBAT.AdsGrace, 0.1)
	local walk = num(PLAYER.Walk, 16)
	local adsSpeedOk = speed <= walk * num(def.AdsMoveMult, 1) * 1.3 + 2
	local hipMin = Spread.MinScale(def, false, speed, air)
	local adsMin = Spread.MinScale(def, true, speed, air)
	local scale: number
	if c.Ads and adsSpeedOk and t - c.AdsSince >= adsTime - grace then
		scale = adsMin -- Zielen fertig
	elseif c.Ads and adsSpeedOk then
		-- Übergang: großzügig wie der Client überblendet (nie strenger als ein ehrlicher Client)
		local alpha = if adsTime > 0 then math.clamp((t - c.AdsSince + grace) / adsTime, 0, 1) else 1
		scale = hipMin + (adsMin - hipMin) * alpha
		local settle = (def :: any).AdsSettleSpread
		if Util.IsFinite(settle) then
			scale = math.min(scale, settle + (hipMin - num(def.SpreadHip, 0)))
		end
	else
		scale = hipMin
	end
	return math.max(0, scale * Spread.FirstShot(def, c.ShotTimes, t))
end

-- ---------------------------------------------------------------------
-- INTERVALL (C10 Schritt 4) – gemeinsam für Spieler und Bots
-- ---------------------------------------------------------------------
-- Rückgabe: ok, Grund-Abstand (für den Empfangsabstand)
local function intervalCheck(c: Combatant, def: WeaponDef, t: number, tolerance: number, f: number): (boolean, number)
	local rules = rulesOf(c)
	local mult = num(rules.IntervalMult, 1)
	local ammo = c.Ammo[c.Equipped]
	local salvoGap = num(def.Interval, 0.5) * mult / f
	local since = t - c.LastShotT
	local first = c.LastShotT <= 0
	if def.FireMode == "Burst" and def.BurstCount and def.BurstInterval then
		local newSalvo = first or since >= salvoGap * tolerance
		if newSalvo then
			ammo.BurstLeft = math.max(0, def.BurstCount - 1)
			return true, salvoGap
		end
		local burstGap = def.BurstInterval / f
		if ammo.BurstLeft <= 0 or since < burstGap * tolerance then
			return false, burstGap
		end
		ammo.BurstLeft -= 1
		return true, burstGap
	end
	if not first and since < salvoGap * tolerance then
		return false, salvoGap
	end
	return true, salvoGap
end

local function perSecondOk(c: Combatant, def: WeaponDef, t: number, f: number): boolean
	local rules = rulesOf(c)
	local interval = math.max(0.01, num(def.Interval, 0.5) * num(rules.IntervalMult, 1))
	local rate = if def.FireMode == "Burst" and def.BurstCount then def.BurstCount / interval else 1 / interval
	local limit = (rate * num(COMBAT.PerSecondFactor, 1.15) + 1) * f
	return shotsInLastSecond(c, t) + 1 <= limit
end

-- ---------------------------------------------------------------------
-- ADMIN-WAFFEN (B11.7)
-- ---------------------------------------------------------------------
local function orbitalStrike(c: Combatant, def: WeaponDef, origin: Vector3, aim: Vector3)
	local params = mapParamsOf(c)
	local range = num(ADMIN.OrbitalRay, def.Range)
	local pos = origin + aim * range
	if params then
		local hit = workspace:Raycast(origin, aim * range, params)
		if hit then
			pos = hit.Position
		end
	end
	queueFx(c, 1, def.Id, origin, pos)
	call(
		"ProjectileService",
		"Strike",
		c,
		def,
		pos,
		num(ADMIN.OrbitalDelay, 1),
		num(ADMIN.OrbitalRadius, 10),
		num(ADMIN.OrbitalDamage, 999)
	)
end

local function lightningChain(c: Combatant, def: WeaponDef, first: Combatant)
	local cs = combat()
	local params = mapParamsOf(c)
	local jumps = math.floor(num(ADMIN.LightningJumps, 4))
	local reach = num(ADMIN.LightningJumpRange, 20)
	local damage = num(ADMIN.LightningDamage, 80) * num(rulesOf(c).DamageMult, 1)
	local hitSet: { [Combatant]: boolean } = { [first] = true }
	local from = first
	for _ = 1, jumps do
		local best: Combatant? = nil
		local bestDist = reach
		for _, other in ipairs(cs.Members(c.Ctx)) do
			if hitSet[other] or other == c or not partsAlive(other) or not cs.IsEnemy(c, other) then
				continue
			end
			local d = (other.Root.Position - from.Root.Position).Magnitude
			if d <= bestDist and lineClear(params, from.Root.Position, other.Root.Position, 0.5) then
				best = other
				bestDist = d
			end
		end
		if not best then
			break
		end
		hitSet[best] = true
		queueFx(c, 2, def.Id, from.Root.Position, best.Root.Position)
		cs.ApplyDamage(c, best, damage, { -- Treffer-Bestätigung kommt über OnDamage (Kind "Admin")
			WeaponKey = def.Key,
			Head = false,
			Kind = "Admin",
			Dist = bestDist,
			From = from.Root.Position,
		})
		from = best
	end
end

-- ---------------------------------------------------------------------
-- SCHUSS-PRÜFUNG (C10)
-- ---------------------------------------------------------------------
local function processFire(c: Combatant, packet: FirePacket, opts: FireOpts): (boolean, string?)
	local cs = combat()
	local shotId, weaponId, t = packet.ShotId, packet.WeaponId, packet.T
	local origin, aim, claim, targets = packet.Origin, packet.Aim, packet.Scale, packet.Targets

	-- 1) TYPE
	local def = defIn(c, c.Equipped)
	local typeOk = isInt(shotId)
		and shotId >= 0
		and shotId < 2147483647
		and isInt(weaponId)
		and Util.IsFinite(t)
		and Util.IsFiniteVector(origin)
		and Util.IsFiniteVector(aim)
		and Util.IsFinite(claim)
		and claim >= 0
		and claim <= num(COMBAT.MaxScale, 30)
		and type(targets) == "table"
		and def ~= nil
		and def.Id == weaponId
		and (def.Kind == "Hitscan" or def.Kind == "Projectile")
	if typeOk then
		local mag = (aim :: Vector3).Magnitude
		local tol = num(COMBAT.AimNormTol, 0.01)
		typeOk = mag >= 1 - tol and mag <= 1 + tol
	end
	if typeOk then
		local n = #targets
		local expected = if (def :: WeaponDef).Kind == "Projectile" then 0 else (def :: WeaponDef).Pellets
		typeOk = n == expected and n <= MAX_TARGETS
		if typeOk then
			for i = 1, n do
				if not isInt(targets[i]) then
					typeOk = false
					break
				end
			end
		end
	end
	if typeOk and (def :: WeaponDef).AdminOnly and not c.IsAdmin then
		typeOk = false
	end
	if not typeOk then
		noteReject(c, "TYPE", shotId, opts)
		return false, "TYPE"
	end
	local d = def :: WeaponDef
	local tShot = t :: number
	local o = origin :: Vector3
	local a = (aim :: Vector3).Unit

	-- 2) RATE (Eimer; Admin RapidFire f: Kapazität und Nachfüllung × f = 1/f Marke pro Schuss)
	local f = rapidFactor(c)
	if not fireBucket.Take(c.Player or c, 1 / f) then
		noteReject(c, "RATE", shotId, opts)
		return false, "RATE"
	end

	-- 3) STATE
	local maxGap = math.floor(num(COMBAT.ShotIdGap, 4))
	if shotId <= c.LastShotId or shotId > c.LastShotId + maxGap then
		noteReject(c, "STATE", shotId, opts)
		return false, "STATE"
	end
	if not c.Alive or not contextLive(c) or c.EquipReadyAt > tShot or c.Blocking or c.HealUntil > tShot then
		noteReject(c, "STATE", shotId, opts)
		return false, "STATE"
	end
	local ammo = c.Ammo[c.Equipped]
	if ammo.ReloadUntil > 0 then
		if ammo.ReloadUntil > tShot then
			noteReject(c, "STATE", shotId, opts)
			ammoFix(c, opts)
			return false, "STATE"
		end
		finishReload(c, c.Equipped)
	end
	local infAmmo = power(c, "AdminInfAmmo") and true or false
	if not infAmmo then
		if ammo.Mag <= 0 then
			noteReject(c, "STATE", shotId, opts)
			ammoFix(c, opts)
			return false, "STATE"
		end
		ammo.Mag -= 1
	end
	c.LastShotId = shotId :: number

	-- 4) RATE (Intervall, Empfangsabstand, Schüsse pro Sekunde)
	local tolerance = num(COMBAT.IntervalTolerance, 0.75)
	local okInterval, gapBase = intervalCheck(c, d, tShot, tolerance, f)
	local s = stateOf(c)
	if okInterval and s.RecvLast > 0 and opts.Recv - s.RecvLast < gapBase * num(COMBAT.RecvTolerance, 0.5) then
		okInterval = false
	end
	if okInterval and not perSecondOk(c, d, tShot, f) then
		okInterval = false
	end
	if not okInterval then
		noteReject(c, "RATE", shotId, opts)
		return false, "RATE"
	end
	-- Untergrenze braucht die Kette VOR diesem Schuss (Erster-Schuss-Genauigkeit)
	local speedT = Services.HistoryService.Speed(c, tShot)
	local air = airborne(c)
	local minScale = minScaleFor(c, d, tShot, speedT, air)
	c.LastShotT = tShot
	pushShotTime(c, tShot)
	s.RecvLast = opts.Recv
	if c.ShieldUntil > opts.Now and not opts.DryRun then
		cs.SetShield(c, 0) -- Spawn-Schutz endet beim ersten Schuss
	end
	if infAmmo then
		taint(c, "AdminInfAmmo")
	end
	if f > 1 then
		taint(c, "AdminRapidFire")
	end
	if d.AdminOnly then
		taint(c, "AdminWeapon")
	end

	-- 5) TIME
	local age = opts.Now - tShot
	if
		age < num(COMBAT.AgeMin, -0.05)
		or age > num(COMBAT.AgeMax, 1)
		or age > opts.Ping + num(COMBAT.PingSlack, 0.35)
	then
		noteReject(c, "TIME", shotId, opts)
		return false, "TIME"
	end

	local silent = power(c, "AdminSilentAim") and true or false
	local params = mapParamsOf(c)

	-- 6) ORIGIN
	if not silent then
		local _, headPos = Services.HistoryService.Sample(c, tShot)
		if headPos then
			local allowed = num(COMBAT.OriginTol, 4)
				+ speedT * math.min(math.max(age, 0), num(COMBAT.OriginSpeedCap, 0.4))
			if (o - headPos).Magnitude > allowed or not lineClear(params, headPos, o, 0) then
				noteReject(c, "ORIGIN", shotId, opts)
				return false, "ORIGIN"
			end
		end
	else
		taint(c, "AdminSilentAim")
	end

	-- 7) SPREAD: Server rechnet dieselben Strahlen
	local scale = math.max(claim :: number, minScale)
	local dirs = Spread.Directions(a, d, scale, Spread.Seed(c.Salt, shotId :: number))

	if d.Kind == "Projectile" then
		if not opts.DryRun then
			local proj: any = d.Projectile
			call(
				"ProjectileService",
				"Spawn",
				c,
				d,
				o,
				dirs[1] * num(proj and proj.Speed, 100),
				math.max(0, age),
				shotId
			)
			fireShotCallbacks(c, d, 0, 0)
		end
		return true, nil
	end
	if d.Key == "OrbitalLaser" then
		if not opts.DryRun then
			orbitalStrike(c, d, o, dirs[1])
			fireShotCallbacks(c, d, 0, 0)
		end
		return true, nil
	end

	-- 8) pro Strahl mit Ziel: HITBOX, LOS, RANGE
	local rules = rulesOf(c)
	local headR = headRadius(rules)
	local tol = num(COMBAT.HitTol, 0.35)
	local rewindT = math.clamp(tShot - num(COMBAT.InterpDelay, 0.1), opts.Now - num(COMBAT.MaxRewind, 0.38), opts.Now)
	local shorten = num(COMBAT.LosShorten, 0.75)
	local results: { [Combatant]: PelletHit } = {}
	local order: { Combatant } = {}
	local claimed, accepted = 0, 0
	local firstCode: string? = nil
	local hits, heads = 0, 0
	local fx: { { Kind: number, E: Vector3 } } = {}

	for i, dir in ipairs(dirs) do
		local id = targets[i]
		if id == 0 then
			if not opts.DryRun then
				table.insert(fx, { Kind = 1, E = missEnd(params, o, dir, d.Range) })
			end
			continue
		end
		claimed += 1
		local target: Combatant? = cs.Get(id)
		if not target or target.Ctx ~= c.Ctx or not partsAlive(target) or not cs.IsEnemy(c, target) then
			firstCode = firstCode or "TARGET" -- inzwischen gepoppt/ungültig: still verwerfen
			continue
		end
		local region: ("Head" | "Body")? = nil
		local dist: number? = nil
		if silent then
			region = "Head"
			dist = (target.Head.Position - o).Magnitude
		else
			for _, w in ipairs(Services.HistoryService.SampleWindow(target, rewindT)) do
				region, dist = Hitbox.Ray(o, dir, d.Range, w.Root, w.Head, headR, tol)
				if region then
					break
				end
			end
			if not region or not dist then
				firstCode = firstCode or "HITBOX"
				noteReject(c, "HITBOX", shotId, opts)
				continue
			end
			if dist > d.Range then
				firstCode = firstCode or "RANGE"
				noteReject(c, "RANGE", shotId, opts)
				continue
			end
			if not lineClear(params, o, o + dir * dist, shorten) then
				firstCode = firstCode or "LOS"
				noteReject(c, "LOS", shotId, opts)
				continue
			end
		end
		local hitRegion: "Head" | "Body" = region :: any
		local hitDist = dist :: number
		accepted += 1
		if target.ShieldUntil > opts.Now then
			continue -- Spawn-Schutz: Treffer zählt, macht aber keinen Schaden
		end
		local dmg = Damage.Compute(d, hitDist, hitRegion, rules)
		local entry = results[target]
		if not entry then
			entry = { Target = target, Damage = 0, Head = false, Dist = hitDist, Hits = 0, Heads = 0 }
			results[target] = entry
			table.insert(order, target)
		end
		entry.Damage += dmg
		entry.Hits += 1
		entry.Dist = math.min(entry.Dist, hitDist)
		hits += 1
		if hitRegion == "Head" then
			entry.Head = true
			entry.Heads += 1
			heads += 1
		end
		if not opts.DryRun then
			table.insert(fx, { Kind = 2, E = o + dir * hitDist })
		end
	end

	if opts.DryRun then
		if claimed > 0 and accepted == 0 then
			return false, firstCode
		end
		return true, firstCode
	end

	-- 9) Schaden, Rückmeldung, FX, Statistik
	local oneShot = power(c, "AdminOneShot") and true or false
	for _, target in ipairs(order) do
		local r = results[target]
		local amount = r.Damage
		if oneShot then
			amount = target.Hp + 1
			taint(c, "AdminOneShot")
		end
		local dealt, killed = cs.ApplyDamage(c, target, amount, {
			WeaponKey = d.Key,
			Head = r.Head,
			Kind = "Hitscan",
			Dist = r.Dist,
			From = o,
		})
		sendCombat(c, "Hit", { T = target.Id, D = math.floor(dealt + 0.5), H = r.Head, K = killed, S = shotId })
		if d.Key == "LightningRifle" then
			lightningChain(c, d, target)
		end
	end
	for _, e in ipairs(fx) do
		queueFx(c, e.Kind, d.Id, o, e.E)
	end
	fireShotCallbacks(c, d, hits, heads)
	if claimed > 0 and accepted == 0 then
		return false, firstCode
	end
	return true, firstCode
end

-- ---------------------------------------------------------------------
-- BOTS: ServerFire (gleiche Mathematik, ohne Paket-Checks/Rückspulen)
-- ---------------------------------------------------------------------
local function rotateAway(aim: Vector3, degrees: number, rng: Random): Vector3
	local helper = if math.abs(aim.Y) < 0.99 then Vector3.yAxis else Vector3.xAxis
	local axis = aim:Cross(helper).Unit
	local spin = CFrame.fromAxisAngle(aim, rng:NextNumber(0, math.pi * 2))
	axis = spin:VectorToWorldSpace(axis)
	return CFrame.fromAxisAngle(axis, math.rad(degrees)):VectorToWorldSpace(aim).Unit
end

local missRng = Random.new()

function WeaponService.ServerFire(c: Combatant, aim: Vector3, opts: { ForceMiss: boolean? }?): boolean
	if type(c) ~= "table" or not Util.IsFiniteVector(aim) or aim.Magnitude < 1e-3 then
		return false
	end
	if not partsAlive(c) or not contextLive(c) then
		return false
	end
	local def = defIn(c, c.Equipped)
	if not def or (def.Kind ~= "Hitscan" and def.Kind ~= "Projectile") then
		return false
	end
	local t = now()
	local ammo = c.Ammo[c.Equipped]
	if c.EquipReadyAt > t or c.Blocking or c.HealUntil > t then
		return false
	end
	if ammo.ReloadUntil > 0 then
		if ammo.ReloadUntil > t then
			return false
		end
		finishReload(c, c.Equipped)
	end
	if ammo.Mag <= 0 then
		WeaponService.Reload(c)
		return false
	end
	local okInterval = intervalCheck(c, def, t, 1, 1)
	if not okInterval then
		return false
	end
	ammo.Mag -= 1
	c.LastShotId += 1
	local shotId = c.LastShotId
	local speed = Services.HistoryService.Speed(c, t)
	local air = airborne(c)
	local scale = minScaleFor(c, def, t, speed, air) + Spread.Bloom(def, c.ShotTimes, t)
	c.LastShotT = t
	pushShotTime(c, t)
	local forceMiss = opts ~= nil and opts.ForceMiss == true
	local dirAim = aim.Unit
	if forceMiss then
		dirAim = rotateAway(dirAim, missRng:NextNumber(4, 8), missRng)
	end
	local origin = c.Head.Position
	local dirs = Spread.Directions(dirAim, def, scale, Spread.Seed(c.Salt, shotId))
	local cs = combat()
	if def.Kind == "Projectile" then
		local proj: any = def.Projectile
		call("ProjectileService", "Spawn", c, def, origin, dirs[1] * num(proj and proj.Speed, 100), 0, shotId)
		fireShotCallbacks(c, def, 0, 0)
		if ammo.Mag <= 0 then
			WeaponService.Reload(c)
		end
		return true
	end
	local rules = rulesOf(c)
	local params = mapParamsOf(c)
	local headR = headRadius(rules)
	local tol = num(COMBAT.HitTol, 0.35)
	local results: { [Combatant]: PelletHit } = {}
	local order: { Combatant } = {}
	local hits, heads = 0, 0
	for _, dir in ipairs(dirs) do
		local wall = if params then workspace:Raycast(origin, dir * def.Range, params) else nil
		local wallDist = if wall then (wall.Position - origin).Magnitude else def.Range
		local best: Combatant? = nil
		local bestDist = wallDist
		local bestRegion: ("Head" | "Body")? = nil
		if not forceMiss then
			for _, other in ipairs(cs.Members(c.Ctx)) do
				if other == c or not partsAlive(other) or not cs.IsEnemy(c, other) then
					continue
				end
				local region, dist =
					Hitbox.Ray(origin, dir, def.Range, other.Root.CFrame, other.Head.Position, headR, tol)
				if region and dist and dist < bestDist then
					best, bestDist, bestRegion = other, dist, region
				end
			end
		end
		if best and bestRegion then
			if best.ShieldUntil <= t then
				local entry = results[best]
				if not entry then
					entry = { Target = best, Damage = 0, Head = false, Dist = bestDist, Hits = 0, Heads = 0 }
					results[best] = entry
					table.insert(order, best)
				end
				entry.Damage += Damage.Compute(def, bestDist, bestRegion, rules)
				entry.Hits += 1
				hits += 1
				if bestRegion == "Head" then
					entry.Head = true
					entry.Heads += 1
					heads += 1
				end
			end
			queueFx(c, 2, def.Id, origin, origin + dir * bestDist)
		else
			queueFx(
				c,
				1,
				def.Id,
				origin,
				if wall then wall.Position else origin + dir * math.min(def.Range, MISS_TRACE)
			)
		end
	end
	for _, target in ipairs(order) do
		local r = results[target]
		cs.ApplyDamage(c, target, r.Damage, {
			WeaponKey = def.Key,
			Head = r.Head,
			Kind = "Hitscan",
			Dist = r.Dist,
			From = origin,
		})
	end
	fireShotCallbacks(c, def, hits, heads)
	if ammo.Mag <= 0 then
		WeaponService.Reload(c)
	end
	return true
end

-- ---------------------------------------------------------------------
-- NAHKAMPF (B11.4, C10 "Nahkampf")
-- ---------------------------------------------------------------------
local function meleeReach(
	c: Combatant,
	def: WeaponDef,
	target: Combatant,
	headPos: Vector3,
	aim: Vector3,
	rewindT: number?
): boolean
	local melee: any = def.Melee or {}
	local maxDist = num(melee.Range, def.Range) + num(COMBAT.MeleeRangeSlack, 1.5)
	local maxAngle = num(melee.Cone, 70) / 2 + num(COMBAT.MeleeConeSlack, 10)
	local cosMax = math.cos(math.rad(math.min(maxAngle, 180)))
	local params = mapParamsOf(c)
	local windows: { { Root: CFrame, Head: Vector3 } }
	if rewindT then
		windows = Services.HistoryService.SampleWindow(target, rewindT)
	else
		windows = { { Root = target.Root.CFrame, Head = target.Head.Position } }
	end
	for _, w in ipairs(windows) do
		if Hitbox.PointDistance(headPos, w.Root, w.Head) <= maxDist then
			local body = Hitbox.BodyCFrame(w.Root).Position
			local best = -1
			for _, point in ipairs({ body, w.Head, w.Root.Position }) do
				local to = point - headPos
				if to.Magnitude < 1e-3 then
					best = 1
					break
				end
				best = math.max(best, to.Unit:Dot(aim))
			end
			if best >= cosMax and lineClear(params, headPos, w.Root.Position, 0.75) then
				return true
			end
		end
	end
	return false
end

local function applyMelee(c: Combatant, def: WeaponDef, target: Combatant, swingId: number)
	local cs = combat()
	if not c.Alive or not partsAlive(target) or cs.Get(target.Id) ~= target or cs.Get(c.Id) ~= c then
		return
	end
	local rules = rulesOf(c)
	local amount = Damage.Compute(def, 0, "Body", rules)
	if power(c, "AdminOneShot") then
		amount = target.Hp + 1
		taint(c, "AdminOneShot")
	end
	local dealt, killed = cs.ApplyDamage(c, target, amount, {
		WeaponKey = def.Key,
		Head = false,
		Kind = "Melee",
		Dist = (target.Root.Position - c.Root.Position).Magnitude,
		From = c.Root.Position,
	})
	sendCombat(c, "Hit", { T = target.Id, D = math.floor(dealt + 0.5), H = false, K = killed, S = swingId })
	local melee: any = def.Melee or {}
	local knock = melee.Knockback
	if dealt > 0 and typeof(knock) == "Vector3" and target.Alive then
		local flat = target.Root.Position - c.Root.Position
		flat = Vector3.new(flat.X, 0, flat.Z)
		local dir = if flat.Magnitude > 0.05
			then flat.Unit
			else Vector3.new(c.Root.CFrame.LookVector.X, 0, c.Root.CFrame.LookVector.Z).Unit
		impulse(target, dir * knock.X + Vector3.new(0, knock.Y, 0))
	end
end

local function startSwing(c: Combatant, def: WeaponDef, target: Combatant?, swingId: number)
	local melee: any = def.Melee or {}
	local headPos = c.Head.Position
	local look = c.Root.CFrame.LookVector
	queueFx(c, 3, def.Id, headPos, headPos + look * num(melee.Range, 6))
	if not target then
		return
	end
	local windup = num(melee.Windup, 0)
	if windup > 0 then
		task.delay(windup, applyMelee, c, def, target, swingId) -- BonkHammer: Ausholzeit serverseitig abwarten
	else
		applyMelee(c, def, target, swingId)
	end
end

local function meleeReady(c: Combatant, t: number, tolerance: number): (boolean, WeaponDef?)
	if c.Equipped ~= "Melee" or not partsAlive(c) or c.Blocking or c.HealUntil > t or c.EquipReadyAt > t then
		return false, nil
	end
	local def = defIn(c, "Melee")
	if not def or def.Kind ~= "Melee" or not contextLive(c) then
		return false, nil
	end
	local s = stateOf(c)
	local interval = num(def.Interval, 0.5) * num(rulesOf(c).IntervalMult, 1) / rapidFactor(c)
	if s.SwingT > 0 and t - s.SwingT < interval * tolerance then
		return false, nil
	end
	return true, def
end

function WeaponService.ServerMelee(c: Combatant, target: Combatant?): boolean
	if type(c) ~= "table" then
		return false
	end
	local t = now()
	local ok, def = meleeReady(c, t, 1)
	if not ok or not def then
		return false
	end
	local s = stateOf(c)
	s.SwingT = t
	s.SwingId += 1
	local valid: Combatant? = nil
	if target and partsAlive(target) and target.Ctx == c.Ctx and combat().IsEnemy(c, target) then
		local look = c.Root.CFrame.LookVector
		if meleeReach(c, def, target, c.Head.Position, look, nil) then
			valid = target
		end
	end
	startSwing(c, def, valid, s.SwingId)
	return true
end

-- ---------------------------------------------------------------------
-- UTILITY: Werfen & Benutzen (B11.5)
-- ---------------------------------------------------------------------
local function utilityReady(c: Combatant, _def: WeaponDef, t: number): boolean
	local ammo = c.Ammo[UTILITY]
	if not ammo then
		return false
	end
	if power(c, "AdminInfAmmo") then
		taint(c, "AdminInfAmmo")
		return true
	end
	if rulesOf(c).UtilityMode == "Cooldown" then
		return ammo.CooldownUntil <= t
	end
	return ammo.Charges > 0
end

local function consumeUtility(c: Combatant, def: WeaponDef)
	local ammo = c.Ammo[UTILITY]
	if not ammo or power(c, "AdminInfAmmo") then
		return
	end
	if rulesOf(c).UtilityMode == "Cooldown" then
		ammo.CooldownUntil = now() + num(def.Cooldown, 10)
	else
		ammo.Charges = math.max(0, ammo.Charges - 1)
	end
	sendAmmo(c, "Utility")
end

local function doThrow(
	c: Combatant,
	def: WeaponDef,
	origin: Vector3,
	aim: Vector3,
	charge: number,
	age: number,
	throwId: number
)
	local proj: any = def.Projectile or {}
	local tap = num(proj.Speed, 70)
	local full = num(COMBAT.ThrowChargedSpeed, 90)
	local speed = tap + (full - tap) * math.clamp(charge, 0, 1)
	consumeUtility(c, def)
	call("ProjectileService", "Spawn", c, def, origin, aim * speed, age, throwId)
	queueFx(c, 4, def.Id, origin, origin + aim * 4)
end

local function throwReady(c: Combatant, t: number): (boolean, WeaponDef?)
	local def = defIn(c, "Utility")
	if not def or def.Kind ~= "Throwable" or not partsAlive(c) or not contextLive(c) then
		return false, nil
	end
	if c.Blocking or c.HealUntil > t then
		return false, nil
	end
	return utilityReady(c, def, t), def
end

function WeaponService.ServerThrow(c: Combatant, aim: Vector3, charge: number): boolean
	if type(c) ~= "table" or not Util.IsFiniteVector(aim) or aim.Magnitude < 1e-3 then
		return false
	end
	local t = now()
	local ok, def = throwReady(c, t)
	if not ok or not def then
		return false
	end
	local s = stateOf(c)
	s.ThrowId += 1
	doThrow(c, def, c.Head.Position, aim.Unit, num(charge, 0), 0, s.ThrowId)
	return true
end

local function startHeal(c: Combatant, def: WeaponDef)
	local heal: any = def.Heal or {}
	local t = now()
	local useTime = num(heal.UseTime, 0.8)
	local duration = math.max(HEAL_STEP, num(heal.Duration, 2.5))
	local ticks = math.max(1, math.floor(duration / HEAL_STEP + 0.5))
	consumeUtility(c, def)
	c.HealUntil = t + useTime - latency(c) -- trinken: kein Schießen (Client-Uhr läuft um den Ping voraus)
	stateOf(c).Heal = {
		TickAt = t + useTime + HEAL_STEP,
		Left = ticks,
		Per = num(heal.Amount, 50) / ticks,
		Step = duration / ticks,
	}
	active[c] = true
end

function WeaponService.ServerUse(c: Combatant): boolean
	if type(c) ~= "table" then
		return false
	end
	local t = now()
	local def = defIn(c, "Utility")
	if not def or def.Kind ~= "Consumable" or not partsAlive(c) or not contextLive(c) then
		return false
	end
	if c.HealUntil > t or stateOf(c).Heal ~= nil or c.Blocking or not utilityReady(c, def, t) then
		return false
	end
	startHeal(c, def)
	return true
end

-- ---------------------------------------------------------------------
-- LOADOUT, AUSRÜSTEN, NACHLADEN
-- ---------------------------------------------------------------------
local function owns(c: Combatant, def: WeaponDef): boolean
	if def.Free or c.Kind ~= "Player" or not c.Player then
		return true
	end
	local ok, data = call("DataService", "Get", c.Player)
	if not ok or type(data) ~= "table" then
		return false
	end
	local weapons = data.Weapons
	local owned = type(weapons) == "table" and weapons.Owned
	return type(owned) == "table" and owned[def.Key] == true
end

local function keyAllowed(c: Combatant, slot: SlotName, key: any, rules: Types.ContextRules, forced: boolean): boolean
	if type(key) ~= "string" then
		return false
	end
	local def = Config.Weapon(key)
	if not def or def.Slot ~= slot or not def.Enabled then
		return false
	end
	if def.AdminOnly then
		return c.IsAdmin and slot == "Primary"
	end
	if forced or rules.IgnoreOwnership then
		return true
	end
	return owns(c, def)
end

local function freshAmmo(def: WeaponDef?): AmmoState
	return {
		Mag = if def then def.Mag else 0,
		ReloadUntil = 0,
		Charges = if def and def.Charges then def.Charges else 1,
		CooldownUntil = 0,
		BurstLeft = 0,
	}
end

local function firstAllowedSlot(c: Combatant, prefer: SlotName): SlotName
	local allowed = rulesOf(c).AllowedSlots
	if not allowed or allowed[prefer] then
		return prefer
	end
	for _, slot in ipairs(SLOT_NAMES) do
		if allowed[slot] then
			return slot
		end
	end
	return prefer
end

function WeaponService.Equip(c: Combatant, slot: SlotName)
	if type(c) ~= "table" or not table.find(SLOT_NAMES, slot) then
		return
	end
	local allowed = rulesOf(c).AllowedSlots
	if allowed and not allowed[slot] then
		sendCombat(c, "Equip", { S = c.Equipped })
		return
	end
	local def = defIn(c, slot)
	if not def then
		sendCombat(c, "Equip", { S = c.Equipped })
		return
	end
	if c.Equipped == slot then
		return
	end
	local current = c.Ammo[c.Equipped]
	if current and current.ReloadUntil > 0 then
		current.ReloadUntil = 0 -- Wechsel bricht Nachladen ab
		sendAmmo(c, c.Equipped)
	end
	endBlock(c)
	c.Equipped = slot
	c.Ads = false
	c.EquipReadyAt = math.max(0, now() + num(def.Equip, 0.3) - latency(c))
	call("CharacterService", "ShowSlot", c, slot)
end

function WeaponService.Reload(c: Combatant): boolean
	if type(c) ~= "table" or not c.Alive then
		return false
	end
	local slot = c.Equipped
	local def = defIn(c, slot)
	local ammo = c.Ammo[slot]
	if not def or not ammo or (def.Kind ~= "Hitscan" and def.Kind ~= "Projectile") then
		return false
	end
	if ammo.Mag >= def.Mag or ammo.ReloadUntil > 0 then
		return false
	end
	if power(c, "AdminNoReload") then
		taint(c, "AdminNoReload")
		finishReload(c, slot)
		sendAmmo(c, slot)
		return true
	end
	local mult = num(rulesOf(c).ReloadMult, 1)
	ammo.ReloadUntil = now() + num(def.Reload, 2) * mult - latency(c)
	ammo.BurstLeft = 0
	active[c] = true
	return true
end

function WeaponService.SetLoadout(c: Combatant, loadout: Types.Loadout)
	if type(c) ~= "table" then
		return
	end
	local rules = rulesOf(c)
	local forced = rules.ForcedLoadout
	local source: any = if forced then forced else loadout
	local default: any = Config.Weapons.DefaultLoadout or {}
	local clean: any = {}
	for _, slot in ipairs(SLOT_NAMES) do
		local key = if type(source) == "table" then source[slot] else nil
		if not keyAllowed(c, slot, key, rules, forced ~= nil) then
			key = default[slot]
		end
		clean[slot] = key
	end
	c.Loadout = clean :: Types.Loadout
	for _, slot in ipairs(SLOT_NAMES) do
		c.Ammo[slot] = freshAmmo(defIn(c, slot))
	end
	c.Blocking = false
	c.Ads = false
	c.Equipped = firstAllowedSlot(c, c.Equipped)
	local cs = combat()
	if cs.Get(c.Id) == c then
		call("CharacterService", "BuildGunVisuals", c)
		cs.SendArmed(c)
	end
end

function WeaponService.ResetForRound(c: Combatant)
	if type(c) ~= "table" then
		return
	end
	for _, slot in ipairs(SLOT_NAMES) do
		c.Ammo[slot] = freshAmmo(defIn(c, slot))
	end
	c.Blocking = false
	c.BlockUntil = 0
	c.BlockCooldownUntil = 0
	c.HealUntil = 0
	c.Ads = false
	table.clear(c.ShotTimes)
	local s = stateOf(c)
	s.Heal = nil
	c.Equipped = firstAllowedSlot(c, c.Equipped)
	call("CharacterService", "ShowSlot", c, c.Equipped)
	for _, slot in ipairs(SLOT_NAMES) do
		sendAmmo(c, slot)
	end
end

function WeaponService.GiveAdminWeapon(p: Player, id: number): boolean
	if typeof(p) ~= "Instance" or not p:IsA("Player") or not isInt(id) then
		return false
	end
	local okAdmin, isAdmin = call("AdminService", "IsAdmin", p)
	if not (okAdmin and isAdmin == true) then
		return false -- verweigert für Nicht-Admins
	end
	local def = Config.WeaponById(id)
	if not def or not def.AdminOnly or def.Slot ~= "Primary" then
		return false
	end
	local c: Combatant? = combat().OfPlayer(p)
	if not c then
		return false -- nur im aktuellen Kontext (Match/Range)
	end
	c.IsAdmin = true
	local loadout: any = table.clone(c.Loadout)
	loadout.Primary = def.Key
	c.Loadout = loadout
	c.Ammo[PRIMARY] = freshAmmo(def)
	if c.Equipped ~= "Primary" then
		WeaponService.Equip(c, "Primary")
	else
		c.EquipReadyAt = now()
	end
	call("CharacterService", "BuildGunVisuals", c)
	combat().SendArmed(c)
	taint(c, "AdminWeapon")
	return true
end

function WeaponService.OnShot(cb: (c: Combatant, def: WeaponDef, hits: number, heads: number) -> ())
	if type(cb) == "function" then
		table.insert(shotCallbacks, cb)
	end
end

function WeaponService.Forget(c: Combatant)
	wstates[c] = nil
	active[c] = nil
	if not c.Player then
		fireBucket.Clear(c) -- Bots/Puppen/Tests: Eimer hängt am Combatant selbst
		actionBucket.Clear(c)
	end
end

function WeaponService.TestFire(c: Combatant, packet: FirePacket, opts: FireOpts): (boolean, string?)
	local o: FireOpts = {
		Recv = num(opts and opts.Recv, os.clock()),
		Now = num(opts and opts.Now, now()),
		Ping = num(opts and opts.Ping, 0.05),
		DryRun = if opts and opts.DryRun ~= nil then opts.DryRun else true,
	}
	return processFire(c, packet, o)
end

-- ---------------------------------------------------------------------
-- REMOTES
-- ---------------------------------------------------------------------
local function onFire(p: Player, shotId: any, weaponId: any, t: any, origin: any, aim: any, scale: any, targets: any)
	local c: Combatant? = combat().OfPlayer(p)
	if not c then
		return -- nicht bewaffnet (Lobby)
	end
	local packet: FirePacket = {
		ShotId = shotId,
		WeaponId = weaponId,
		T = t,
		Origin = origin,
		Aim = aim,
		Scale = scale,
		Targets = targets,
	}
	local opts: FireOpts = { Recv = os.clock(), Now = now(), Ping = num(p:GetNetworkPing(), 0) }
	local ok, err = pcall(function()
		processFire(c, packet, opts)
	end)
	if not ok then
		warn("[WeaponService] Fire-Fehler: " .. tostring(err))
	end
end

-- t aus WeaponAction wie C10 Schritt 5 prüfen
local function timeOk(p: Player, t: any): boolean
	if not Util.IsFinite(t) then
		return false
	end
	local age = now() - t
	return age >= num(COMBAT.AgeMin, -0.05)
		and age <= num(COMBAT.AgeMax, 1)
		and age <= num(p:GetNetworkPing(), 0) + num(COMBAT.PingSlack, 0.35)
end

local ACTIONS: { [string]: (p: Player, c: Combatant, a: any, b: any, cc: any, d: any, e: any) -> () } = {}

ACTIONS.Equip = function(_p, c, slotIndex)
	if not isInt(slotIndex) or slotIndex < 1 or slotIndex > 4 then
		noteReject(c, "TYPE", 0, nil)
		return
	end
	WeaponService.Equip(c, SLOT_NAMES[slotIndex])
end

ACTIONS.Reload = function(_p, c)
	WeaponService.Reload(c)
end

ACTIONS.Ads = function(p, c, on, t)
	if type(on) ~= "boolean" then
		return
	end
	if on and not c.Ads then
		local nowT = now()
		local back = math.min(num(p:GetNetworkPing(), 0) + 0.1, 0.5)
		local claimed = if Util.IsFinite(t) then t else nowT
		c.AdsSince = math.clamp(claimed, nowT - back, nowT)
	end
	c.Ads = on
end

ACTIONS.Block = function(_p, c, on, t)
	if type(on) ~= "boolean" then
		return
	end
	if not on then
		endBlock(c)
		return
	end
	local def: any = defIn(c, "Melee")
	local block = def and def.Melee and def.Melee.Block
	local nowT = now()
	if not block or c.Equipped ~= "Melee" or not c.Alive or c.Blocking or c.BlockCooldownUntil > nowT then
		return -- nur Laserschwert und ohne Abklingzeit
	end
	if t ~= nil and not Util.IsFinite(t) then
		return
	end
	c.Blocking = true
	c.BlockUntil = nowT + num(block.Max, 1.5)
	active[c] = true
end

ACTIONS.Melee = function(p, c, swingId, t, aim, targetId)
	if not isInt(swingId) or not Util.IsFiniteVector(aim) or (targetId ~= nil and not isInt(targetId)) then
		noteReject(c, "TYPE", swingId, nil)
		return
	end
	local mag = aim.Magnitude
	local tol = num(COMBAT.AimNormTol, 0.01)
	if mag < 1 - tol or mag > 1 + tol then
		noteReject(c, "TYPE", swingId, nil)
		return
	end
	if not timeOk(p, t) then
		noteReject(c, "TIME", swingId, nil)
		return
	end
	local s = stateOf(c)
	if swingId <= s.SwingId or swingId > s.SwingId + 8 then
		noteReject(c, "STATE", swingId, nil)
		return
	end
	local ready, def = meleeReady(c, t, num(COMBAT.IntervalTolerance, 0.75))
	if not ready or not def then
		noteReject(c, "RATE", swingId, nil)
		return
	end
	s.SwingId = swingId
	s.SwingT = t
	if c.ShieldUntil > now() then
		combat().SetShield(c, 0)
	end
	local target: Combatant? = nil
	if targetId and targetId ~= 0 then
		local cs = combat()
		local other: Combatant? = cs.Get(targetId)
		if other and other.Ctx == c.Ctx and partsAlive(other) and cs.IsEnemy(c, other) then
			local nowT = now()
			local rewindT = math.clamp(t - num(COMBAT.InterpDelay, 0.1), nowT - num(COMBAT.MaxRewind, 0.38), nowT)
			local _, headPos = Services.HistoryService.Sample(c, t)
			if meleeReach(c, def, other, headPos or c.Head.Position, aim.Unit, rewindT) then
				target = other
			else
				noteReject(c, "HITBOX", swingId, nil)
			end
		end
	end
	startSwing(c, def, target, swingId)
end

ACTIONS.Throw = function(p, c, throwId, t, origin, aim, charge)
	if
		not isInt(throwId)
		or not Util.IsFiniteVector(origin)
		or not Util.IsFiniteVector(aim)
		or not Util.IsFinite(charge)
		or charge < 0
		or charge > 1
	then
		noteReject(c, "TYPE", throwId, nil)
		return
	end
	local mag = aim.Magnitude
	if mag < 0.99 or mag > 1.01 then
		noteReject(c, "TYPE", throwId, nil)
		return
	end
	if not timeOk(p, t) then
		noteReject(c, "TIME", throwId, nil)
		return
	end
	local s = stateOf(c)
	if throwId <= s.ThrowId then
		noteReject(c, "STATE", throwId, nil)
		return
	end
	local nowT = now()
	local ok, def = throwReady(c, nowT)
	if not ok or not def then
		noteReject(c, "STATE", throwId, nil)
		sendAmmo(c, "Utility")
		return
	end
	-- Ursprung wie C10 Schritt 6
	local age = math.max(0, nowT - t)
	local _, headPos = Services.HistoryService.Sample(c, t)
	if headPos then
		local speed = Services.HistoryService.Speed(c, t)
		local allowed = num(COMBAT.OriginTol, 4) + speed * math.min(age, num(COMBAT.OriginSpeedCap, 0.4))
		if (origin - headPos).Magnitude > allowed or not lineClear(mapParamsOf(c), headPos, origin, 0) then
			noteReject(c, "ORIGIN", throwId, nil)
			return
		end
	end
	s.ThrowId = throwId
	doThrow(c, def, origin, aim.Unit, charge, age, throwId)
end

ACTIONS.Use = function(p, c, t)
	if t ~= nil and not timeOk(p, t) then
		noteReject(c, "TIME", 0, nil)
		return
	end
	if not WeaponService.ServerUse(c) then
		sendAmmo(c, "Utility")
	end
end

local function onAction(p: Player, action: any, a: any, b: any, cc: any, d: any, e: any)
	if not actionBucket.Take(p) then
		return
	end
	if type(action) ~= "string" then
		return
	end
	local handler = ACTIONS[action]
	if not handler then
		return
	end
	local c: Combatant? = combat().OfPlayer(p)
	if not c then
		return
	end
	local ok, err = pcall(handler, p, c, a, b, cc, d, e)
	if not ok then
		warn("[WeaponService] WeaponAction " .. action .. ": " .. tostring(err))
	end
end

-- ---------------------------------------------------------------------
-- TAKT 20 Hz: Nachlade-Ende, Block-Ende, Heilen über Zeit
-- ---------------------------------------------------------------------
local function tick(_dt: number)
	local t = now()
	local cs = combat()
	for c in pairs(active) do
		if cs.Get(c.Id) ~= c then
			active[c] = nil
			continue
		end
		local busy = false
		for _, slot in ipairs(SLOT_NAMES) do
			local ammo = c.Ammo[slot]
			if ammo and ammo.ReloadUntil > 0 then
				if t >= ammo.ReloadUntil then
					finishReload(c, slot)
					sendAmmo(c, slot)
				else
					busy = true
				end
			end
		end
		if c.Blocking then
			if t >= c.BlockUntil or not c.Alive or c.Equipped ~= "Melee" then
				endBlock(c)
			else
				busy = true
			end
		end
		local s = wstates[c]
		local heal = s and s.Heal
		if s and heal then
			if not c.Alive then
				s.Heal = nil
			elseif t >= heal.TickAt then
				local healed = cs.Heal(c, heal.Per)
				if healed > 0 and c.Player then
					call("RewardService", "Track", c.Player, "Heal", healed)
				end
				heal.Left -= 1
				heal.TickAt += heal.Step
				if heal.Left <= 0 then
					s.Heal = nil
				else
					busy = true
				end
			else
				busy = true
			end
		end
		if not busy then
			active[c] = nil
		end
	end
	-- Phasen-Cache klein halten
	local clock = os.clock()
	for id, entry in pairs(phaseCache) do
		if clock - entry.At > 10 then
			phaseCache[id] = nil
		end
	end
end

-- ---------------------------------------------------------------------
-- LEBENSZYKLUS
-- ---------------------------------------------------------------------
function WeaponService.Init(services: any)
	Services = services
end

function WeaponService.Start()
	Remotes.Fire.OnServerEvent:Connect(onFire)
	Remotes.WeaponAction.OnServerEvent:Connect(onAction)
	Scheduler.Every("Weapons", TICK_HZ, tick)
	-- Heil-Limo bricht bei Schaden ab; Treffer-Bestätigung für Splash/Admin-Schaden
	local cs = combat()
	cs.OnDamage(function(attacker: Combatant?, victim: Combatant, dealt: number, info: Types.DamageInfo)
		local s = wstates[victim]
		if s and s.Heal then
			s.Heal = nil
			victim.HealUntil = 0
		end
		if attacker and attacker ~= victim and attacker.Player and (info.Kind == "Splash" or info.Kind == "Admin") then
			sendCombat(attacker, "Hit", {
				T = victim.Id,
				D = math.floor(dealt + 0.5),
				H = false,
				K = not victim.Alive,
				S = 0,
			})
		end
	end)
	Players.PlayerRemoving:Connect(function(p: Player)
		fireBucket.Clear(p)
		actionBucket.Clear(p)
	end)
end

return WeaponService
