-- =====================================================================
--  CLUTCH CLASH – Bot-Gehirn (Server/Bot/BotBrain)
--  Besitzer: WP6 (Bots & Training-Range). Vertrag: DESIGN.md B10.3, C10 ("Bots"), C17 (Budgets).
--  Normales Modul (kein Service). BotService ruft Tick() 10× pro Sekunde je Bot (gestaffelt über
--  Lib/Scheduler). Pro Tick höchstens Config.Bots.MaxRaycastsPerTick (3) Strahlen, kein Yield.
--
--  Zustände (B10.3): Patrol -> Engage (strafen, Feuerstöße) -> Reposition (Deckungs-Knoten) ->
--    Retreat (HP < Rückzugs-HP, Heilen/Rauch) -> Push (Hard/Insane, Gegner lädt ≥ 0.4 s nach) ->
--    Zone (Overtime) -> Melee (Ziel ≤ 12 Studs, Nahkampfwaffe). Ziel "Idle" = stehen, nicht schießen.
--  Wahrnehmung: Sichtlinie Kopf -> Kopf, sonst Kopf -> Rumpf gegen Arena.MapParams; Rauch blockiert
--    analytisch (ProjectileService.IsSmoked). Blickkegel je Stufe, ≤ 14 Studs sieht er immer.
--  Schießen NUR über WeaponService.ServerFire/ServerMelee/ServerThrow/ServerUse (gleiche Munition,
--    Intervalle, Nachladen, Schaden wie Spieler). aim = Einheits-Richtung (wie im Fire-Paket).
--  Zielfehler: AimErr -> MinErr exponentiell mit τ, +LateralErrPerStud × Querbewegung des Ziels.
--  Rookie-Handicap: MissLeft Schüsse gehen mit ForceMiss absichtlich daneben (BotService setzt den Wert).
--  Navigation: A* (Bot/Pathfind) auf Arena.Nav, neu planen alle 2 s oder bei Zielwechsel,
--    Humanoid:MoveTo jeden Tick, Strafen über Humanoid:Move. Hängt fest (< 1 Stud in 1.5 s) ->
--    springen + neu planen, beim 2. Mal in Folge auf den nächsten Nav-Knoten setzen (nie > 3 s hängen).
--
--  Öffentliche API (nur für BotService):
--    BotBrain.new(c, difficulty, rng): Brain
--    BotBrain.Tick(brain, dt, env)            env = { Services, Now, Info, Graph, Params }
--    BotBrain.Reset(brain, now)               neue Runde / wiederbelebt
--    BotBrain.SetGoal(brain, goal)            { Kind = "Engage" | "Zone" | "Idle", Pos = Vector3? }
--    BotBrain.SetMisses(brain, n)             absichtliche Fehlschüsse für den Rest der Runde
--    BotBrain.Hear(brain, pos, now)           Schuss in Hörweite
--    BotBrain.Hurt(brain, attacker, now)      Schaden bekommen (Angreifer bekannt)
--    BotBrain.PathPoints(brain, graph): { Vector3 }   für das Admin-Pfad-Overlay
--    BotBrain.FireStep(brain, now)            jeden Frame: Schüsse zwischen den Takten (echte Feuerrate)
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))

local Pathfind = require(script.Parent:WaitForChild("Pathfind"))

local BotBrain = {}

local BOTS: any = Config.Bots
local PLAYER: any = Config.Player

local NEAR_SENSE = 14 -- so nah wird ein Gegner immer bemerkt (auch hinter dem Rücken)
local REACQUIRE_GAP = 0.6 -- Ziel so lange aus den Augen -> neue Reaktionszeit
local DECISION_WINDOW = 2 -- s: so oft wird über einen Deckungswechsel gewürfelt
local MAX_CANDIDATES = 4 -- Gegner, die pro Tick überhaupt geprüft werden
local HINT_SECONDS = 4 -- gehörte Schüsse / Treffer bleiben so lange interessant
local PATROL_REPICK = 4 -- s: Patrouillen-Ziel neu wählen
local ZONE_HOLD_RADIUS = 4.5 -- in der Zone: innerhalb dieses Radius stehen bleiben/strafen
local MOVE_SWITCH_EPS = 0.01
-- Schießen zwischen den 10-Hz-Takten (BotBrain.FireStep jeden Frame): so lange nach dem letzten Takt, der das
-- Ziel bestätigt hat, darf weitergeschossen werden (danach entscheidet erst wieder der nächste Takt)
local FIRE_GRACE = 0.16
local FIRE_RETRY = 0.01 -- abgelehnter Schuss (Frame-Raster, Nachladen): nächster Frame

-- ---------------------------------------------------------------------
-- TYPEN
-- ---------------------------------------------------------------------
export type Goal = { Kind: string, Pos: Vector3? }

export type Env = {
	Services: any,
	Now: number,
	Info: any, -- Types.ContextInfo des Kontexts
	Graph: Pathfind.Graph,
	Params: RaycastParams?,
}

export type Brain = {
	C: Types.Combatant,
	DiffName: string,
	D: any, -- Config.Bots.Difficulties[...]
	Rng: Random,
	Align: AlignOrientation?,
	FootOffset: number,
	State: string,
	Goal: Goal,
	-- Ziel & Gedächtnis
	Target: Types.Combatant?,
	Visible: boolean,
	VisibleRegion: string?,
	SeenAt: number,
	LastSeenPos: Vector3?,
	AcquiredAt: number,
	ReactAt: number,
	HintPos: Vector3?,
	HintAt: number,
	HurtAt: number,
	AttackerId: number?,
	-- Navigation
	Path: { number }?,
	PathIndex: number,
	PathDest: Vector3?,
	PathAt: number,
	PathVersion: number,
	UsingMove: boolean,
	MoveIntent: boolean,
	StuckPos: Vector3?,
	StuckAt: number,
	StuckCount: number,
	StrafeDir: number,
	StrafeUntil: number,
	SlideUntil: number,
	PatrolDest: Vector3?,
	PatrolAt: number,
	CoverPos: Vector3?,
	CoverUntil: number,
	NextDecisionAt: number,
	-- Kampf
	BurstLeft: number,
	NextShotAt: number,
	AimHead: boolean,
	MissLeft: number,
	MeleeMode: boolean,
	RetreatSince: number?,
	RetreatDone: boolean,
	TargetReloadSince: number?,
	NextUtilityAt: number,
	NextSwitchAt: number,
	LastAlive: boolean,
	LastSpeed: number,
	-- Feuer zwischen den Takten (FireStep)
	FireReady: boolean,
	FireAt: number,
	FireTarget: Types.Combatant?,
	FireDef: Types.WeaponDef?,
	FireEnv: Env?,
	Stopped: boolean,
}

-- ---------------------------------------------------------------------
-- KLEINE HELFER
-- ---------------------------------------------------------------------
local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function unitOr(v: Vector3, fallback: Vector3): Vector3
	local m = v.Magnitude
	if m < 1e-4 or m ~= m then
		return fallback
	end
	return v / m
end

local function between(rng: Random, pair: any, fallbackMin: number, fallbackMax: number): number
	local lo = if type(pair) == "table" and type(pair[1]) == "number" then pair[1] else fallbackMin
	local hi = if type(pair) == "table" and type(pair[2]) == "number" then pair[2] else fallbackMax
	if hi < lo then
		lo, hi = hi, lo
	end
	return lo + (hi - lo) * rng:NextNumber()
end

local function num(v: any, default: number): number
	if type(v) == "number" and v == v then
		return v
	end
	return default
end

local function weaponDef(key: string?): Types.WeaponDef?
	if type(key) ~= "string" then
		return nil
	end
	local ok, def = pcall(Config.Weapon, key)
	if ok then
		return def
	end
	return nil
end

local function equippedDef(c: Types.Combatant): Types.WeaponDef?
	local loadout: any = c.Loadout
	return weaponDef(if loadout then loadout[c.Equipped] else nil)
end

local function slotDef(c: Types.Combatant, slot: Types.SlotName): Types.WeaponDef?
	local loadout: any = c.Loadout
	return weaponDef(if loadout then loadout[slot] else nil)
end

local function ammoOf(c: Types.Combatant, slot: Types.SlotName): Types.AmmoState?
	local ammo: any = c.Ammo
	if type(ammo) ~= "table" then
		return nil
	end
	local state = ammo[slot]
	if type(state) == "table" then
		return state
	end
	return nil
end

-- Abweichung in einem Kegel mit halbem Öffnungswinkel maxDeg (gleichmäßig über die Kreisfläche)
local function deviate(dir: Vector3, maxDeg: number, rng: Random): Vector3
	if maxDeg <= 0 then
		return dir
	end
	local angle = math.rad(maxDeg) * math.sqrt(rng:NextNumber())
	local spin = rng:NextNumber() * math.pi * 2
	local up = if math.abs(dir.Y) < 0.98 then Vector3.yAxis else Vector3.xAxis
	local right = dir:Cross(up).Unit
	local up2 = right:Cross(dir).Unit
	local offset = (right * math.cos(spin) + up2 * math.sin(spin)) * math.tan(angle)
	return (dir + offset).Unit
end

-- wie CombatService.IsEnemy: Puppen sind für alle Ziel, Team 0 = jeder gegen jeden (FFA),
-- sonst verschiedene Teams oder Friendly Fire im Kontext
local function isEnemy(c: Types.Combatant, o: Types.Combatant, friendlyFire: boolean): boolean
	if o == c or o.Id == c.Id then
		return false
	end
	if o.Kind == "Dummy" then
		return true
	end
	if c.Team == 0 or o.Team == 0 or o.Team ~= c.Team then
		return true
	end
	return friendlyFire
end

local function alive(o: Types.Combatant?): boolean
	if o == nil then
		return false
	end
	local root, head = o.Root, o.Head
	return o.Alive == true and root ~= nil and root.Parent ~= nil and head ~= nil and head.Parent ~= nil
end

local function smoked(env: Env, ctx: string, a: Vector3, b: Vector3): boolean
	local projectiles = env.Services.ProjectileService
	if not projectiles or type(projectiles.IsSmoked) ~= "function" then
		return false
	end
	local ok, result = pcall(projectiles.IsSmoked, ctx, a, b)
	return ok and result == true
end

local function footY(b: Brain): number
	return b.C.Root.Position.Y - b.FootOffset
end

-- ---------------------------------------------------------------------
-- ERZEUGEN / ZURÜCKSETZEN
-- ---------------------------------------------------------------------
function BotBrain.new(c: Types.Combatant, difficulty: string, rng: Random): Brain
	local diffs: any = BOTS.Difficulties
	local d = diffs[difficulty] or diffs.Normal
	local humanoid = c.Humanoid
	local root = c.Root
	local footOffset = 3
	if humanoid then
		if humanoid.RigType == Enum.HumanoidRigType.R6 then
			footOffset = root.Size.Y / 2 + 2 -- R6: Beine 2 hoch, HipHeight 0
		else
			footOffset = root.Size.Y / 2 + humanoid.HipHeight
		end
	end
	local alignInstance = root:FindFirstChild("BotFace")
	local brain: Brain = {
		C = c,
		DiffName = difficulty,
		D = d,
		Rng = rng,
		Align = if alignInstance and alignInstance:IsA("AlignOrientation") then alignInstance else nil,
		FootOffset = footOffset,
		State = "Patrol",
		Goal = { Kind = "Engage" },
		Target = nil,
		Visible = false,
		VisibleRegion = nil,
		SeenAt = -math.huge,
		LastSeenPos = nil,
		AcquiredAt = 0,
		ReactAt = 0,
		HintPos = nil,
		HintAt = -math.huge,
		HurtAt = -math.huge,
		AttackerId = nil,
		Path = nil,
		PathIndex = 1,
		PathDest = nil,
		PathAt = -math.huge,
		PathVersion = 0,
		UsingMove = false,
		MoveIntent = false,
		StuckPos = nil,
		StuckAt = 0,
		StuckCount = 0,
		StrafeDir = if rng:NextNumber() < 0.5 then -1 else 1,
		StrafeUntil = 0,
		SlideUntil = 0,
		PatrolDest = nil,
		PatrolAt = -math.huge,
		CoverPos = nil,
		CoverUntil = 0,
		NextDecisionAt = 0,
		BurstLeft = 0,
		NextShotAt = 0,
		AimHead = false,
		MissLeft = 0,
		MeleeMode = false,
		RetreatSince = nil,
		RetreatDone = false,
		TargetReloadSince = nil,
		NextUtilityAt = 0,
		NextSwitchAt = 0,
		LastAlive = c.Alive,
		LastSpeed = -1,
		FireReady = false,
		FireAt = -math.huge,
		FireTarget = nil,
		FireDef = nil,
		FireEnv = nil,
		Stopped = false,
	}
	return brain
end

function BotBrain.Reset(b: Brain, now: number)
	b.State = "Patrol"
	b.Target = nil
	b.Visible = false
	b.VisibleRegion = nil
	b.SeenAt = -math.huge
	b.LastSeenPos = nil
	b.HintPos = nil
	b.HintAt = -math.huge
	b.HurtAt = -math.huge
	b.AttackerId = nil
	b.Path = nil
	b.PathDest = nil
	b.PathAt = -math.huge
	b.StuckPos = nil
	b.StuckAt = now
	b.StuckCount = 0
	b.StrafeUntil = now
	b.SlideUntil = 0
	b.PatrolDest = nil
	b.PatrolAt = -math.huge
	b.CoverPos = nil
	b.CoverUntil = 0
	b.NextDecisionAt = now + DECISION_WINDOW
	b.BurstLeft = 0
	b.NextShotAt = now
	b.MeleeMode = false
	b.RetreatSince = nil
	b.RetreatDone = false
	b.TargetReloadSince = nil
	b.NextUtilityAt = now + num(BOTS.UtilityRollSeconds, 3)
	b.NextSwitchAt = now
	b.LastSpeed = -1
	b.FireReady = false
	b.FireTarget = nil
end

function BotBrain.SetGoal(b: Brain, goal: Goal)
	local kind = if type(goal) == "table" then goal.Kind else nil
	if kind ~= "Engage" and kind ~= "Zone" and kind ~= "Idle" then
		kind = "Engage"
	end
	local pos = if type(goal) == "table" and typeof(goal.Pos) == "Vector3" then goal.Pos else nil
	if kind == "Zone" and pos == nil then
		kind = "Engage"
	end
	b.Goal = { Kind = kind :: string, Pos = pos }
	b.Path = nil
end

function BotBrain.SetMisses(b: Brain, n: number)
	b.MissLeft = math.max(0, math.floor(num(n, 0)))
end

function BotBrain.Hear(b: Brain, pos: Vector3, now: number)
	b.HintPos = pos
	b.HintAt = now
end

function BotBrain.Hurt(b: Brain, attacker: Types.Combatant?, now: number)
	b.HurtAt = now
	if attacker and attacker.Root and attacker.Root.Parent then
		b.AttackerId = attacker.Id
		b.HintPos = attacker.Root.Position
		b.HintAt = now
	end
end

-- ---------------------------------------------------------------------
-- WAHRNEHMUNG (≤ MaxRaycastsPerTick Strahlen)
-- ---------------------------------------------------------------------
type Budget = { Left: number }

local function aware(b: Brain, o: Types.Combatant, now: number): boolean
	if b.AttackerId == o.Id and now - b.HurtAt < 2.5 then
		return true
	end
	if b.Target == o and now - b.SeenAt < num(BOTS.Memory, 4) then
		return true
	end
	local hint = b.HintPos
	if hint and now - b.HintAt < 1.5 and (hint - o.Root.Position).Magnitude < 10 then
		return true
	end
	return false
end

-- Sichtbar? -> "Head" | "Body" | nil
local function visibleRegion(b: Brain, env: Env, o: Types.Combatant, budget: Budget): string?
	local c = b.C
	local eye = c.Head.Position
	local headPos = o.Head.Position
	local toHead = headPos - eye
	local dist = toHead.Magnitude
	if dist > num(BOTS.MaxSight, 400) then
		return nil
	end
	if dist > NEAR_SENSE and not aware(b, o, env.Now) then
		local look = flat(c.Root.CFrame.LookVector)
		local to = flat(toHead)
		if look.Magnitude > 0.01 and to.Magnitude > 0.01 then
			local cosAngle = math.clamp(look.Unit:Dot(to.Unit), -1, 1)
			if math.deg(math.acos(cosAngle)) > num(b.D.Fov, 120) / 2 then
				return nil
			end
		end
	end
	local params = env.Params
	if smoked(env, c.Ctx, eye, headPos) then
		return nil
	end
	if params == nil then
		return "Head" -- ohne Map-Parameter keine Sichtprüfung möglich (sollte nie passieren)
	end
	if budget.Left <= 0 then
		return nil
	end
	budget.Left -= 1
	if workspace:Raycast(eye, toHead, params) == nil then
		return "Head"
	end
	if budget.Left <= 0 then
		return nil
	end
	local body = o.Root.Position
	if smoked(env, c.Ctx, eye, body) then
		return nil
	end
	budget.Left -= 1
	if workspace:Raycast(eye, body - eye, params) == nil then
		return "Body"
	end
	return nil
end

local function enemiesOf(b: Brain, env: Env): { Types.Combatant }
	local combat = env.Services.CombatService
	if not combat then
		return {}
	end
	local ok, all = pcall(combat.InCtx, b.C.Ctx)
	if not ok or type(all) ~= "table" then
		return {}
	end
	local rules = env.Info and env.Info.Rules
	local friendlyFire = type(rules) == "table" and rules.FriendlyFire == true
	local result: { Types.Combatant } = {}
	for _, o in all do
		if type(o) == "table" and alive(o) and isEnemy(b.C, o, friendlyFire) then
			table.insert(result, o)
		end
	end
	return result
end

local function perceive(b: Brain, env: Env, enemies: { Types.Combatant })
	local c = b.C
	local now = env.Now
	local myPos = c.Root.Position
	-- Kandidaten nach Priorität: aktuelles Ziel, Angreifer, dann die nächsten; Puppen nur als Notlösung
	local scored: { { O: Types.Combatant, S: number } } = {}
	for _, o in enemies do
		local score = (o.Root.Position - myPos).Magnitude
		if o == b.Target then
			score -= 15
		end
		if o.Id == b.AttackerId and now - b.HurtAt < 3 then
			score -= 20
		end
		if o.Kind == "Dummy" then
			score += 200
		end
		table.insert(scored, { O = o, S = score })
	end
	table.sort(scored, function(x, y)
		return x.S < y.S
	end)
	local budget: Budget = { Left = math.clamp(math.floor(num(BOTS.MaxRaycastsPerTick, 3)), 1, 3) }
	local found: Types.Combatant? = nil
	local region: string? = nil
	for i = 1, math.min(#scored, MAX_CANDIDATES) do
		if budget.Left <= 0 then
			break
		end
		local o = scored[i].O
		local r = visibleRegion(b, env, o, budget)
		if r then
			found = o
			region = r
			break
		end
	end
	if found then
		local target = found :: Types.Combatant
		if target ~= b.Target or now - b.SeenAt > REACQUIRE_GAP then
			-- neu erfasst: Reaktionszeit + voller Zielfehler
			b.AcquiredAt = now
			b.ReactAt = now + num(b.D.Reaction, 0.4) * (0.85 + b.Rng:NextNumber() * 0.3)
			b.BurstLeft = 0
			b.MeleeMode = false
		end
		b.Target = target
		b.Visible = true
		b.VisibleRegion = region
		b.SeenAt = now
		b.LastSeenPos = target.Root.Position
	else
		b.Visible = false
		b.VisibleRegion = nil
		local target = b.Target
		if target and (not alive(target) or now - b.SeenAt > num(BOTS.Memory, 4)) then
			b.Target = nil
		end
	end
end

-- ---------------------------------------------------------------------
-- BEWEGUNG
-- ---------------------------------------------------------------------
local function face(b: Brain, dir: Vector3?)
	local humanoid = b.C.Humanoid
	if not humanoid then
		return
	end
	local align = b.Align
	if dir and flat(dir).Magnitude > 0.05 and align then
		local look = flat(dir).Unit
		if humanoid.AutoRotate then
			humanoid.AutoRotate = false
		end
		align.CFrame = CFrame.lookAt(Vector3.zero, look)
		if not align.Enabled then
			align.Enabled = true
		end
	else
		if not humanoid.AutoRotate then
			humanoid.AutoRotate = true
		end
		if align and align.Enabled then
			align.Enabled = false
		end
	end
end

-- isNode: point ist ein Nav-Knoten (Boden-Oberkante) -> Stufen hoch erkennen und springen
local function useMoveTo(b: Brain, point: Vector3, isNode: boolean?)
	local humanoid = b.C.Humanoid
	if not humanoid then
		return
	end
	if b.UsingMove then
		humanoid:Move(Vector3.zero, false)
		b.UsingMove = false
	end
	humanoid:MoveTo(point)
	b.MoveIntent = flat(point - b.C.Root.Position).Magnitude > 1
	-- Stufe/Kante hoch (Nav-Kanten bis 4.5 Studs Höhenunterschied) -> springen
	if isNode then
		local rise = point.Y - footY(b)
		if rise > 1.2 and flat(point - b.C.Root.Position).Magnitude < 7 then
			humanoid.Jump = true
		end
	end
end

local function useMove(b: Brain, dir: Vector3)
	local humanoid = b.C.Humanoid
	if not humanoid then
		return
	end
	if not b.UsingMove then
		humanoid:MoveTo(b.C.Root.Position) -- laufendes MoveTo beenden
		b.UsingMove = true
	end
	humanoid:Move(dir, false)
	b.MoveIntent = dir.Magnitude > MOVE_SWITCH_EPS
end

local function stop(b: Brain)
	useMove(b, Vector3.zero)
	b.MoveIntent = false
end

-- Einem Pfad zum Ziel folgen (A* auf dem Nav-Graph; ohne Graph direkt)
local function followTo(b: Brain, env: Env, dest: Vector3)
	local g = env.Graph
	local pos = b.C.Root.Position
	if Pathfind.Empty(g) then
		useMoveTo(b, dest)
		return
	end
	local now = env.Now
	local replan = b.Path == nil
		or b.PathDest == nil
		or ((b.PathDest :: Vector3) - dest).Magnitude > math.max(g.Spacing * 1.5, 6)
		or now - b.PathAt >= num(BOTS.RepathSeconds, 2)
	if replan then
		local path = Pathfind.Path(g, pos, dest)
		b.Path = path
		b.PathDest = dest
		b.PathAt = now
		b.PathIndex = 1
		b.PathVersion += 1
		if path and #path >= 2 then
			-- erster Knoten liegt hinter uns? Dann gleich zum zweiten
			local p1, p2 = g.P[path[1]], g.P[path[2]]
			if flat(p2 - pos).Magnitude <= flat(p2 - p1).Magnitude + 0.5 then
				b.PathIndex = 2
			end
		end
	end
	local path = b.Path
	if path then
		local reach = num(BOTS.WaypointReach, 2.5)
		for _ = 1, 4 do
			if b.PathIndex > #path then
				break
			end
			local wp = g.P[path[b.PathIndex]]
			if flat(wp - pos).Magnitude <= reach then
				b.PathIndex += 1
			else
				break
			end
		end
		if b.PathIndex <= #path then
			useMoveTo(b, g.P[path[b.PathIndex]], true)
			return
		end
	end
	useMoveTo(b, dest)
end

-- Seitwärts zum Ziel laufen (Strafen) und dabei den Abstand halten
local function strafe(b: Brain, env: Env, targetPos: Vector3, desired: number)
	local c = b.C
	local pos = c.Root.Position
	local now = env.Now
	local d = b.D
	local to = flat(targetPos - pos)
	local dist = to.Magnitude
	local dir = unitOr(to, flat(c.Root.CFrame.LookVector))
	local perp = Vector3.new(-dir.Z, 0, dir.X)
	if now >= b.StrafeUntil then
		b.StrafeDir = -b.StrafeDir
		b.StrafeUntil = now + between(b.Rng, { d.StrafeMin, d.StrafeMax }, 0.8, 1.5)
		-- Bewegungs-Technik: springen oder rutschen
		if b.Rng:NextNumber() * 100 < num(d.MoveTech, 0) then
			if b.Rng:NextNumber() < 0.5 and c.Humanoid then
				(c.Humanoid :: Humanoid).Jump = true
			else
				b.SlideUntil = now + num(BOTS.Slide and BOTS.Slide.Time, 0.75)
			end
		end
	end
	local approach = 0
	if dist > desired * 1.35 then
		approach = 1
	elseif dist < desired * 0.6 then
		approach = -0.8
	end
	local move = perp * b.StrafeDir + dir * approach
	move = unitOr(move, Vector3.zero)
	local g = env.Graph
	local foot = footY(b)
	if move.Magnitude > 0 and not Pathfind.IsWalkable(g, pos + move * 3, foot) then
		b.StrafeDir = -b.StrafeDir
		move = perp * b.StrafeDir
		if not Pathfind.IsWalkable(g, pos + move * 3, foot) then
			move = Vector3.zero
		end
	end
	useMove(b, move)
end

-- Hängt fest? -> springen + neu planen; beim UnstickAfter-ten Mal in Folge auf einen Nav-Knoten setzen
local function checkStuck(b: Brain, env: Env)
	local c = b.C
	local now = env.Now
	local pos = c.Root.Position
	if not b.MoveIntent or b.StuckPos == nil then
		b.StuckPos = pos
		b.StuckAt = now
		if not b.MoveIntent then
			b.StuckCount = 0
		end
		return
	end
	if now - b.StuckAt < num(BOTS.StuckSeconds, 1.5) then
		return
	end
	local moved = flat(pos - (b.StuckPos :: Vector3)).Magnitude
	b.StuckPos = pos
	b.StuckAt = now
	if moved >= num(BOTS.StuckMinMove, 1) then
		b.StuckCount = 0
		return
	end
	b.StuckCount += 1
	-- nächsten Wegpunkt merken (für das Umsetzen), dann neu planen
	local waypoint: Vector3? = nil
	local path = b.Path
	if path and b.PathIndex <= #path and not Pathfind.Empty(env.Graph) then
		waypoint = env.Graph.P[path[b.PathIndex]]
	end
	b.Path = nil
	b.StrafeDir = -b.StrafeDir
	if c.Humanoid then
		(c.Humanoid :: Humanoid).Jump = true
	end
	if b.StuckCount < num(BOTS.UnstickAfter, 2) then
		return
	end
	b.StuckCount = 0
	-- auf einen sinnvollen Knoten setzen (≤ 3 s nach Beginn des Hängens): nächster Wegpunkt des Pfads,
	-- sonst der nächste Knoten bzw. – steht er schon darauf – ein Nachbar Richtung Ziel
	local g = env.Graph
	local targetPos: Vector3? = waypoint
	if targetPos == nil and not Pathfind.Empty(g) then
		local idx, dist = Pathfind.Nearest(g, pos)
		if idx then
			targetPos = g.P[idx]
			if dist < 1.5 then
				local goal = b.PathDest
				local bestScore = math.huge
				for _, n in g.Adj[idx] do
					local p = g.P[n]
					local score = if goal then (p - goal).Magnitude else b.Rng:NextNumber()
					if score < bestScore then
						bestScore = score
						targetPos = p
					end
				end
			end
		end
	end
	if targetPos == nil then
		return
	end
	local look = flat(c.Root.CFrame.LookVector)
	local cf = CFrame.lookAt(
		(targetPos :: Vector3) + Vector3.new(0, b.FootOffset + 0.5, 0),
		(targetPos :: Vector3) + Vector3.new(0, b.FootOffset + 0.5, 0) + unitOr(look, Vector3.zAxis)
	)
	local character = env.Services.CharacterService
	local ok = false
	if character and type(character.Teleport) == "function" then
		ok = pcall(character.Teleport, c, cf)
	end
	if not ok then
		c.Model:PivotTo(cf)
	end
end

local function applySpeed(b: Brain, env: Env, sprint: boolean)
	local c = b.C
	local humanoid = c.Humanoid
	if not humanoid then
		return
	end
	local d = b.D
	local rules = env.Info and env.Info.Rules
	local ruleSpeed = if rules then num(rules.SpeedMult, 1) else 1
	local def = equippedDef(c)
	local moveMult = if def then num(def.MoveMult, 1) else 1
	if c.Ads and def then
		moveMult = num(def.AdsMoveMult, moveMult)
	end
	local base = num(PLAYER.Walk, 16)
	if sprint and not c.Ads then
		base = num(PLAYER.Sprint, 22)
	end
	local speed = base * num(d.SpeedMult, 1) * ruleSpeed * moveMult
	local now = env.Now
	if now < b.SlideUntil then
		local slide: any = BOTS.Slide or {}
		local total = num(slide.Time, 0.75)
		local a = math.clamp((b.SlideUntil - now) / total, 0, 1)
		local slideSpeed = (num(slide.End, 14) + (num(slide.Start, 32) - num(slide.End, 14)) * a) * ruleSpeed
		speed = math.max(speed, slideSpeed)
	end
	-- nur bei Änderung schreiben (auch wenn jemand anderes WalkSpeed gesetzt hat, z. B. SetBaseSpeed)
	if math.abs(speed - humanoid.WalkSpeed) > 0.05 then
		humanoid.WalkSpeed = speed
	end
	b.LastSpeed = speed
end

-- ---------------------------------------------------------------------
-- ZIELE FÜR DIE BEWEGUNG
-- ---------------------------------------------------------------------
local function desiredDistance(def: Types.WeaponDef?): number
	if def == nil then
		return 25
	end
	if def.Kind == "Melee" then
		return 2
	end
	if def.Kind == "Projectile" then
		return 30
	end
	return math.clamp(num(def.FalloffStart, 40) * 0.7, 8, 70)
end

local function pickCover(b: Brain, env: Env, threat: Vector3?, near: boolean): Vector3?
	local g = env.Graph
	if Pathfind.Empty(g) then
		return nil
	end
	local pos = b.C.Root.Position
	local nodes = Pathfind.NodesNear(g, pos, if near then 28 else 40, true)
	if #nodes == 0 then
		nodes = Pathfind.NodesNear(g, pos, 24, false)
	end
	local best: Vector3? = nil
	local bestScore = -math.huge
	local desired = desiredDistance(equippedDef(b.C))
	for i = 1, math.min(#nodes, 60) do
		local p = g.P[nodes[i]]
		local score = -flat(p - pos).Magnitude * 0.4 + b.Rng:NextNumber() * 4
		if threat then
			local dThreat = flat(p - threat).Magnitude
			if near then
				-- Deckungswechsel: im Wunschabstand bleiben
				score -= math.abs(dThreat - desired) * 0.5
			else
				-- Rückzug: möglichst weit weg vom Gegner
				score += dThreat
			end
		end
		if score > bestScore then
			bestScore = score
			best = p
		end
	end
	return best
end

local function patrolDestination(b: Brain, env: Env, enemies: { Types.Combatant }): Vector3?
	local now = env.Now
	if b.HintPos and now - b.HintAt < HINT_SECONDS then
		return b.HintPos
	end
	if b.LastSeenPos and now - b.SeenAt < num(BOTS.Memory, 4) then
		return b.LastSeenPos
	end
	if b.PatrolDest and now - b.PatrolAt < PATROL_REPICK then
		local dest = b.PatrolDest :: Vector3
		if flat(dest - b.C.Root.Position).Magnitude > 4 then
			return dest
		end
	end
	b.PatrolAt = now
	local g = env.Graph
	-- Umweg (je Stufe "Wander") -> zufälliger Knoten, sonst ungefähr in Richtung des nächsten Gegners
	if not Pathfind.Empty(g) and b.Rng:NextNumber() < num(b.D.Wander, 0.2) then
		for _ = 1, 6 do
			local idx = b.Rng:NextInteger(1, g.Count)
			if g.Comp[idx] ~= 0 then
				b.PatrolDest = g.P[idx]
				return b.PatrolDest
			end
		end
	end
	local myPos = b.C.Root.Position
	local nearest: Types.Combatant? = nil
	local nearestD = math.huge
	for _, o in enemies do
		if o.Kind ~= "Dummy" then
			local d = (o.Root.Position - myPos).Magnitude
			if d < nearestD then
				nearest = o
				nearestD = d
			end
		end
	end
	if nearest then
		local spread = 6 + num(b.D.Wander, 0.2) * 20
		local offset = Vector3.new((b.Rng:NextNumber() - 0.5) * 2 * spread, 0, (b.Rng:NextNumber() - 0.5) * 2 * spread)
		b.PatrolDest = nearest.Root.Position + offset
		return b.PatrolDest
	end
	b.PatrolDest = nil
	return nil
end

-- ---------------------------------------------------------------------
-- ZUSTAND WÄHLEN
-- ---------------------------------------------------------------------
local function targetReloading(target: Types.Combatant, now: number): boolean
	local ammo = ammoOf(target, target.Equipped)
	return ammo ~= nil and num(ammo.ReloadUntil, 0) > now
end

local function decide(b: Brain, env: Env)
	local c = b.C
	local now = env.Now
	local d = b.D
	local target = b.Target
	local goal = b.Goal.Kind
	if goal == "Idle" then
		b.State = "Idle"
		return
	end
	local dist = if target then (target.Root.Position - c.Root.Position).Magnitude else math.huge
	-- Nahkampf (Ziel ≤ 12 Studs und Nahkampfwaffe)
	if target and b.Visible and dist <= num(BOTS.MeleeRange, 12) and slotDef(c, "Melee") ~= nil then
		if not b.MeleeMode then
			local prim = ammoOf(c, "Primary")
			local dry = prim ~= nil and (num(prim.Mag, 1) <= 0 or num(prim.ReloadUntil, 0) > now)
			b.MeleeMode = dry or b.Rng:NextNumber() < num(d.MeleeChance, 0.3)
		end
		if b.MeleeMode then
			b.State = "Melee"
			return
		end
	elseif dist > num(BOTS.MeleeRange, 12) + 2 then
		b.MeleeMode = false
	end
	if goal == "Zone" then
		b.State = "Zone"
		return
	end
	-- Rückzug / Heilen
	local retreatHp = num(d.RetreatHp, 0)
	if retreatHp > 0 and target and c.Hp < retreatHp and not b.RetreatDone then
		b.RetreatSince = b.RetreatSince or now
		if now - (b.RetreatSince :: number) < num(BOTS.RetreatMaxSeconds, 4) then
			b.State = "Retreat"
			return
		end
		b.RetreatDone = true -- genug versteckt: wieder kämpfen
	elseif c.Hp >= retreatHp + 25 then
		b.RetreatSince = nil
		b.RetreatDone = false
	end
	-- Drängen (Hard/Insane): Gegner lädt seit ≥ PushDelay nach
	if d.Push and target and now - b.SeenAt < num(BOTS.Memory, 4) then
		if targetReloading(target, now) then
			b.TargetReloadSince = b.TargetReloadSince or now
			if now - (b.TargetReloadSince :: number) >= num(BOTS.PushDelay, 0.4) then
				b.State = "Push"
				return
			end
		else
			b.TargetReloadSince = nil
		end
	end
	if target and b.Visible then
		-- Entscheidungsfenster: Deckung wechseln?
		if now >= b.NextDecisionAt then
			b.NextDecisionAt = now + DECISION_WINDOW
			if b.Rng:NextNumber() < num(d.Reposition, 0) then
				local cover = pickCover(b, env, target.Root.Position, true)
				if cover then
					b.CoverPos = cover
					b.CoverUntil = now + 3
				end
			end
		end
		if b.CoverPos and now < b.CoverUntil then
			b.State = "Reposition"
		else
			b.CoverPos = nil
			b.State = "Engage"
		end
		return
	end
	b.State = "Patrol"
end

-- ---------------------------------------------------------------------
-- WAFFEN & SCHIESSEN
-- ---------------------------------------------------------------------
local function chooseSlot(b: Brain, now: number): Types.SlotName
	local c = b.C
	if b.State == "Melee" then
		return "Melee"
	end
	local prim = ammoOf(c, "Primary")
	local sec = ammoOf(c, "Secondary")
	local primDry = prim ~= nil and (num(prim.Mag, 1) <= 0 or num(prim.ReloadUntil, 0) > now)
	local secOk = sec ~= nil and num(sec.Mag, 0) > 0 and num(sec.ReloadUntil, 0) <= now
	local target = b.Target
	local dist = if target then (target.Root.Position - c.Root.Position).Magnitude else math.huge
	if c.Equipped == "Secondary" then
		-- zurück zur Primärwaffe, wenn die Sekundär leer ist oder kein Gegner zu sehen ist
		if not secOk or not b.Visible then
			return "Primary"
		end
		return "Secondary"
	end
	if primDry and b.D.QuickSwap and b.Visible and dist < 45 and secOk then
		return "Secondary"
	end
	-- Fernschuss/Rakete auf kurze Distanz: lieber Pistole
	local primDef = slotDef(c, "Primary")
	if primDef and b.Visible and dist < 9 and secOk then
		if primDef.Kind == "Projectile" or num(primDef.AdsZoom, 1) >= 3 then
			return "Secondary"
		end
	end
	return "Primary"
end

local function currentError(b: Brain, target: Types.Combatant, dir: Vector3, now: number): number
	local d = b.D
	local minErr = num(d.MinErr, 1.5)
	local maxErr = num(d.AimErr, 5)
	local tau = math.max(num(d.Tau, 0.6), 0.05)
	local base = minErr + (maxErr - minErr) * math.exp(-(now - b.AcquiredAt) / tau)
	-- Querbewegung des Ziels (horizontal, senkrecht zur Blickrichtung)
	local v = flat(target.Root.AssemblyLinearVelocity)
	local fd = flat(dir)
	local lateral = 0
	if fd.Magnitude > 1e-3 then
		local u = fd.Unit
		lateral = (v - u * v:Dot(u)).Magnitude
	end
	if lateral ~= lateral then
		lateral = 0
	end
	return base + num(BOTS.LateralErrPerStud, 0.15) * lateral
end

-- Ein Schuss über WeaponService.ServerFire (gleiche Munition/Intervalle/Streuung wie Spieler).
-- now = Server-Zeit dieses Aufrufs (Takt oder FireStep-Frame).
local function fireAt(b: Brain, env: Env, target: Types.Combatant, def: Types.WeaponDef, now: number)
	local c = b.C
	local d = b.D
	local weapons = env.Services.WeaponService
	if not weapons then
		return
	end
	if now < b.NextShotAt then
		return
	end
	if b.BurstLeft <= 0 then
		-- neuer Feuerstoß: Kopf oder Körper?
		if def.FireMode == "Auto" then
			b.BurstLeft = math.floor(between(b.Rng, d.Burst, 3, 6) + 0.5)
		elseif def.FireMode == "Burst" then
			b.BurstLeft = math.max(1, math.floor(num(def.BurstCount, 3)))
		else
			b.BurstLeft = 1
		end
		b.AimHead = b.Rng:NextNumber() * 100 < num(d.HeadChance, 10)
	end
	local origin = c.Head.Position
	local aimPoint: Vector3
	if b.AimHead and b.VisibleRegion ~= "Body" then
		aimPoint = target.Head.Position
	else
		aimPoint = target.Root.Position
	end
	local projectile: any = def.Projectile
	if def.Kind == "Projectile" and projectile then
		-- Vorhalt (je Stufe) + auf die Füße zielen (Splash)
		local speed = math.max(num(projectile.Speed, 120), 1)
		local travel = (aimPoint - origin).Magnitude / speed
		aimPoint = target.Root.Position
			- Vector3.new(0, 2.5, 0)
			+ target.Root.AssemblyLinearVelocity * travel * num(d.Lead, 0.5)
	end
	local dir = unitOr(aimPoint - origin, c.Root.CFrame.LookVector)
	local err = currentError(b, target, dir, now)
	dir = deviate(dir, err, b.Rng)
	local forceMiss = b.MissLeft > 0
	local ok, fired = pcall(weapons.ServerFire, c, dir, if forceMiss then { ForceMiss = true } else nil)
	if ok and fired == true then
		if forceMiss then
			b.MissLeft -= 1
		end
		b.BurstLeft -= 1
		local rules = env.Info and env.Info.Rules
		local intervalMult = if rules then num(rules.IntervalMult, 1) else 1
		if b.BurstLeft <= 0 then
			if def.FireMode == "Auto" then
				b.NextShotAt = now + between(b.Rng, d.BurstPause, 0.25, 0.45)
			else
				b.NextShotAt = now + num(def.Interval, 0.3) * intervalMult + between(b.Rng, d.ClickDelay, 0.05, 0.15)
			end
		elseif def.FireMode == "Burst" then
			b.NextShotAt = now + num(def.BurstInterval, 0.07)
		else
			b.NextShotAt = now + num(def.Interval, 0.1) * intervalMult
		end
	else
		-- nicht geschossen: Nachladen/Ausrüsten abwarten, sonst (Intervall knapp verfehlt – Frame-Raster)
		-- im nächsten Frame nochmal (FireStep). Der Server (ServerFire) bleibt die einzige Instanz, die zählt.
		local ammo = ammoOf(c, c.Equipped)
		local waitUntil = now + FIRE_RETRY
		if ammo and num(ammo.ReloadUntil, 0) > waitUntil then
			waitUntil = num(ammo.ReloadUntil, 0)
		end
		if num(c.EquipReadyAt, 0) > waitUntil then
			waitUntil = num(c.EquipReadyAt, 0)
		end
		b.NextShotAt = waitUntil
	end
end

local function useUtility(b: Brain, env: Env)
	local c = b.C
	local now = env.Now
	if now < b.NextUtilityAt then
		return
	end
	b.NextUtilityAt = now + num(BOTS.UtilityRollSeconds, 3)
	if b.MissLeft > 0 then
		return -- Rookie-Handicap: keine Granaten, solange die Fehlschüsse laufen
	end
	local def = slotDef(c, "Utility")
	local ammo = ammoOf(c, "Utility")
	if def == nil or ammo == nil then
		return
	end
	if num(ammo.Charges, 0) <= 0 and num(ammo.CooldownUntil, 0) > now then
		return
	end
	if b.Rng:NextNumber() * 100 >= num(b.D.UtilityChance, 0) then
		return
	end
	local weapons = env.Services.WeaponService
	if not weapons then
		return
	end
	local target = b.Target
	if def.Kind == "Consumable" then
		-- Heil-Limo: nur verletzt und ohne Gegner im Blick (oder auf dem Rückzug)
		if c.Hp <= 60 and (not b.Visible or b.State == "Retreat") then
			pcall(weapons.ServerUse, c)
		end
		return
	end
	if def.Kind ~= "Throwable" or target == nil then
		return
	end
	local projectile: any = def.Projectile
	local gravity = if projectile then num(projectile.Gravity, 90) else 90
	local isSmoke = def.Smoke ~= nil
	local origin = c.Head.Position
	local goalPos: Vector3
	if isSmoke then
		-- Rauch nur auf dem Rückzug / wenn verletzt: zwischen uns und den Gegner
		if not (b.State == "Retreat" or c.Hp < 50) then
			return
		end
		local toward = unitOr(flat(target.Root.Position - c.Root.Position), flat(c.Root.CFrame.LookVector))
		goalPos = c.Root.Position + toward * 7
	else
		local aimAt = b.LastSeenPos or target.Root.Position
		local dist = flat(aimAt - c.Root.Position).Magnitude
		if dist < 12 or dist > 55 then
			return
		end
		goalPos = aimAt
	end
	-- Wurfbogen: volle Ladung (90 Studs/s), Winkel aus der Wurfweite
	local speed = 90
	local horizontal = flat(goalPos - origin)
	local range = horizontal.Magnitude
	local s = math.clamp(gravity * range / (speed * speed), 0, 0.99)
	local angle = 0.5 * math.asin(s)
	local flatDir = unitOr(horizontal, flat(c.Root.CFrame.LookVector))
	local aim = unitOr(flatDir * math.cos(angle) + Vector3.yAxis * math.sin(angle), flatDir)
	pcall(weapons.ServerThrow, c, aim, 1)
end

local function combat(b: Brain, env: Env)
	local c = b.C
	local now = env.Now
	b.FireReady = false -- nur der Schuss-Zweig unten gibt FireStep wieder frei
	local weapons = env.Services.WeaponService
	if not weapons then
		return
	end
	-- Waffe wählen
	local slot = chooseSlot(b, now)
	if slot ~= c.Equipped and now >= b.NextSwitchAt then
		b.NextSwitchAt = now + num(BOTS.SwitchCooldown, 0.8)
		pcall(weapons.Equip, c, slot)
		b.BurstLeft = 0
	end
	if b.State == "Idle" then
		return
	end
	useUtility(b, env)
	local target = b.Target
	if target == nil or not b.Visible or not alive(target) then
		if c.Ads then
			c.Ads = false
		end
		return
	end
	if now < b.ReactAt or now < num(c.EquipReadyAt, 0) then
		return
	end
	local def = equippedDef(c)
	if def == nil then
		return
	end
	local dist = (target.Root.Position - c.Root.Position).Magnitude
	-- Zielen mit Visier auf Distanz (je Stufe)
	local wantAds = b.D.UseAds == true and def.Kind == "Hitscan" and num(def.AdsZoom, 1) > 1.05 and dist > 25
	if wantAds ~= c.Ads then
		c.Ads = wantAds
		c.AdsSince = now
	end
	if def.Kind == "Melee" then
		local melee: any = def.Melee
		local range = if melee then num(melee.Range, 6) else 6
		if dist <= range + 1 and now >= b.NextShotAt then
			local forceMiss = b.MissLeft > 0
			local ok, swung = pcall(weapons.ServerMelee, c, if forceMiss then nil else target)
			if ok and swung == true then
				if forceMiss then
					b.MissLeft -= 1
				end
				b.NextShotAt = now + num(def.Interval, 0.5) + between(b.Rng, b.D.ClickDelay, 0.05, 0.15)
			else
				b.NextShotAt = now + 0.05
			end
		end
		return
	end
	if def.Kind == "Hitscan" or def.Kind == "Projectile" then
		if dist <= num(def.Range, 500) then
			-- Schnelle Waffen (z. B. BuzzSMG 0.065 s) schießen öfter als 10× pro Sekunde: FireStep feuert
			-- zwischen den Takten jeden Frame nach, sobald NextShotAt erreicht ist (echte Feuerrate)
			b.FireReady = true
			b.FireAt = now
			b.FireTarget = target
			b.FireDef = def
			b.FireEnv = env
			fireAt(b, env, target, def, now)
		end
	end
end

-- ---------------------------------------------------------------------
-- TICK (10 Hz je Bot)
-- ---------------------------------------------------------------------
function BotBrain.Tick(b: Brain, _dt: number, env: Env)
	local c = b.C
	local model = c.Model
	local root = c.Root
	local humanoid = c.Humanoid
	if not c.Alive or model.Parent == nil or root.Parent == nil or humanoid == nil then
		b.LastAlive = false
		b.FireReady = false
		return
	end
	local now = env.Now
	if not b.LastAlive then
		-- gerade wiederbelebt (Revive): frischer Kopf, Netzwerk-Besitz zurück an den Server
		b.LastAlive = true
		BotBrain.Reset(b, now)
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
	if root.Anchored then
		-- eingefroren (Prep) oder im Vault: nicht laufen, nicht schießen, Waffe wählen erlaubt
		b.MoveIntent = false
		b.FireReady = false
		b.StuckPos = nil
		local weapons = env.Services.WeaponService
		if weapons and c.Equipped ~= "Primary" and now >= b.NextSwitchAt then
			b.NextSwitchAt = now + num(BOTS.SwitchCooldown, 0.8)
			pcall(weapons.Equip, c, "Primary")
		end
		return
	end

	local enemies = enemiesOf(b, env)
	perceive(b, env, enemies)
	decide(b, env)

	local target = b.Target
	local state = b.State
	local def = equippedDef(c)
	local sprint = false
	if state == "Idle" then
		stop(b)
		face(b, if target and b.Visible then target.Root.Position - root.Position else nil)
	elseif state == "Melee" and target then
		useMoveTo(b, target.Root.Position)
		face(b, target.Root.Position - root.Position)
		sprint = true
	elseif state == "Zone" then
		local zone = b.Goal.Pos :: Vector3
		if flat(zone - root.Position).Magnitude > ZONE_HOLD_RADIUS then
			followTo(b, env, zone)
			sprint = not b.Visible
		elseif target and b.Visible then
			-- in der Zone bleiben: nur seitwärts, keine Annäherung (Wunschabstand = aktueller Abstand)
			strafe(b, env, target.Root.Position, flat(target.Root.Position - root.Position).Magnitude)
		else
			stop(b)
		end
		face(b, if target and b.Visible then target.Root.Position - root.Position else nil)
	elseif state == "Retreat" and target then
		if b.CoverPos == nil or now >= b.CoverUntil then
			b.CoverPos = pickCover(b, env, target.Root.Position, false)
				or (root.Position - unitOr(flat(target.Root.Position - root.Position), Vector3.zAxis) * 15)
			b.CoverUntil = now + 2.5
		end
		followTo(b, env, b.CoverPos :: Vector3)
		face(b, if b.Visible then target.Root.Position - root.Position else nil)
		sprint = not b.Visible
	elseif state == "Push" and target then
		followTo(b, env, if b.Visible then target.Root.Position else (b.LastSeenPos or target.Root.Position))
		face(b, if b.Visible then target.Root.Position - root.Position else nil)
		sprint = not b.Visible
	elseif state == "Reposition" and b.CoverPos then
		if flat((b.CoverPos :: Vector3) - root.Position).Magnitude <= num(BOTS.WaypointReach, 2.5) then
			b.CoverUntil = 0 -- angekommen
		end
		followTo(b, env, b.CoverPos :: Vector3)
		face(b, if target and b.Visible then target.Root.Position - root.Position else nil)
	elseif state == "Engage" and target then
		local desired = desiredDistance(def)
		local dist = flat(target.Root.Position - root.Position).Magnitude
		if dist > desired * 2 + 10 then
			-- weit weg: über den Graphen annähern, dabei aufs Ziel schauen
			followTo(b, env, target.Root.Position)
		else
			strafe(b, env, target.Root.Position, desired)
		end
		face(b, target.Root.Position - root.Position)
	else
		-- Patrol
		local dest = patrolDestination(b, env, enemies)
		if dest then
			followTo(b, env, dest)
			sprint = true
		else
			stop(b)
		end
		-- Vorzielen (PreAim): auf die letzte bekannte Stelle schauen
		if b.D.PreAim and b.LastSeenPos and now - b.SeenAt < num(BOTS.Memory, 4) then
			face(b, (b.LastSeenPos :: Vector3) - root.Position)
		elseif b.HintPos and now - b.HintAt < 1.5 then
			face(b, (b.HintPos :: Vector3) - root.Position)
		else
			face(b, nil)
		end
	end
	applySpeed(b, env, sprint)
	checkStuck(b, env)
	combat(b, env)
end

-- Jeden Frame (BotService, Scheduler.EveryFrame): weiterschießen, solange der letzte Takt Ziel + Waffe
-- bestätigt hat (FireReady, ≤ FIRE_GRACE alt) und NextShotAt erreicht ist. So erreichen Bots die echte
-- Feuerrate jeder Waffe (statt höchstens 1 Schuss pro 100-ms-Takt). Keine Sichtlinien-Strahlen hier
-- (Raycast-Budget bleibt beim Takt), kein Yield.
function BotBrain.FireStep(b: Brain, now: number)
	if not b.FireReady or b.Stopped or now < b.NextShotAt then
		return
	end
	local env = b.FireEnv
	local target = b.FireTarget
	local def = b.FireDef
	local c = b.C
	if env == nil or target == nil or def == nil or now - b.FireAt > FIRE_GRACE then
		b.FireReady = false
		return
	end
	local current = equippedDef(c)
	if not c.Alive or c.Root.Parent == nil or c.Root.Anchored or not alive(target) then
		b.FireReady = false
		return
	end
	if current == nil or current.Key ~= def.Key then
		b.FireReady = false -- Waffe gewechselt: der nächste Takt entscheidet neu
		return
	end
	if b.State == "Idle" or b.State == "Melee" or now < b.ReactAt then
		return
	end
	fireAt(b, env, target, current, now)
end

-- Welt-Punkte des aktuellen Pfads (für das Admin-Overlay "Bot-Wege zeigen")
function BotBrain.PathPoints(b: Brain, graph: Pathfind.Graph): { Vector3 }
	local points: { Vector3 } = {}
	local path = b.Path
	if path == nil or graph.Count == 0 then
		return points
	end
	for i = b.PathIndex, math.min(#path, b.PathIndex + 23) do
		local p = graph.P[path[i]]
		if p then
			table.insert(points, p)
		end
	end
	return points
end

return BotBrain
