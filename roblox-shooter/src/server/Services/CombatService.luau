-- =====================================================================
--  CLUTCH CLASH – Kampf-Kern (Server/Services/CombatService)
--  Besitzer: WP3 (Kampf Server & Treffer-Mathematik). Vertrag: DESIGN.md C5.4, B13, C8 (Combat-Ops).
--  Registry aller Combatants (Spieler, Bots, Puppen) und Kontexte ("M<id>", "Range"),
--  Leben (nur serverseitig, gespiegelt im Attribut Hp), Spawn-Schutz, Block-Faktor (Laserschwert),
--  Assists (≥ 25 Schaden in 8 s), Pop-Gutschrift (letzter Schadensverursacher ≤ 8 s), Todes-Rückblick (≤ 12 Treffer),
--  Eliminate -> CharacterService.Pop (wir schreiben NIE Humanoid.Health = 0), Signale für andere Pakete.
--  Takt 5 Hz: Sturz unter KillY = Pop, fehlende Teile = Fallback-Pop, FFA-Regeneration.
--
--  Öffentliche API (C5.4):
--    CombatService.NewCombatant(p): Combatant           p = { Kind, Player?, Model, Ctx, Team, Slot, Name, Loadout, Difficulty?, MaxHp? }
--    CombatService.Register(c) / Unregister(c)          Attribute CombatantId/Ctx/Team/Alive/Hp, Salt, Combat("Armed"/"Disarmed")
--    CombatService.Get(id) / OfPlayer(p) / InCtx(ctx)
--    CombatService.RegisterContext(info) / UnregisterContext(ctx) / Context(ctx)
--    CombatService.ApplyDamage(attacker?, victim, amount, info): (dealt, killed)
--    CombatService.Heal(c, amount): number
--    CombatService.Eliminate(victim, info)
--    CombatService.Revive(c, at, shieldSeconds?)
--    CombatService.SetShield(c, seconds)
--    CombatService.ResetRound(ctx) / Recap(victimId) / RoundDamage(ctx) / TeamHp(ctx, team)
--    CombatService.OnDamage(cb) / OnElimination(cb)
--  Ergänzungen (für WP3-Services, von außen optional):
--    CombatService.Members(ctx): { Combatant }          LIVE-Liste (nicht verändern!) für heiße Schleifen
--    CombatService.Rebind(c, model)                     neuer Character für einen bestehenden Combatant
--    CombatService.SendArmed(c)                         Combat("Armed") erneut senden (z. B. neues Loadout)
--    CombatService.Power(c, name): any                  Admin-Kraft (nur Spieler, über AdminService.Power)
--    CombatService.IsEnemy(a, b): boolean
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))

local CombatService = {}
local Services: any

type Combatant = Types.Combatant
type ContextInfo = Types.ContextInfo
type DamageInfo = Types.DamageInfo
type ElimInfo = Types.ElimInfo
type RecapHit = Types.RecapHit
type RecapData = Types.RecapData
type SlotName = Types.SlotName

type HitLog = { Id: number, D: number, T: number }
type Extra = {
	DamageLog: { HitLog }, -- erhaltener Schaden dieses Lebens (Assists)
	Taken: { RecapHit }, -- Rückblick dieses Lebens
	HurtAt: number, -- letzter Schaden überhaupt (Regeneration)
}
type PairStat = { D: number, Hits: number, Heads: number }

local COMBAT: any = Config.Combat
local PLAYER: any = Config.Player
local SLOT_NAMES: { SlotName } = { "Primary", "Secondary", "Melee", "Utility" }
local MAX_DAMAGE_LOG = 32
local MAX_MEMBERS = 64 -- Obergrenze pro Kontext (Roster 32 + Puppen)
local DUMMY_ID_START = -5000
local BOT_ID_START = -1000
local BOT_ID_FLOOR = -4999

-- ---------------------------------------------------------------------
-- ZUSTAND
-- ---------------------------------------------------------------------
local byId: { [number]: Combatant } = {}
local byPlayer: { [Player]: Combatant } = {}
local members: { [string]: { Combatant } } = {}
local contexts: { [string]: ContextInfo } = {}
local extras: { [Combatant]: Extra } = {}
local roundDamage: { [string]: { [number]: number } } = {}
local pairDamage: { [string]: { [number]: { [number]: PairStat } } } = {}
local recaps: { [number]: RecapData } = {}
local recapCtx: { [number]: string } = {}
local damageCallbacks: { (Combatant?, Combatant, number, DamageInfo) -> () } = {}
local elimCallbacks: { (Combatant, Combatant?, ElimInfo) -> () } = {}

local rng = Random.new()
local nextBotId = BOT_ID_START
local nextDummyId = DUMMY_ID_START

local function now(): number
	return workspace:GetServerTimeNow()
end

local function num(v: any, default: number): number
	if Util.IsFinite(v) then
		return v
	end
	return default
end

-- Optionalen Dienst aufrufen (fehlt er oder wirft er -> nil)
local function call(serviceName: string, fnName: string, ...: any): (boolean, any)
	local service = Services and Services[serviceName]
	local fn = service and service[fnName]
	if type(fn) ~= "function" then
		return false, nil
	end
	return pcall(fn, ...)
end

local function sendCombat(c: Combatant, op: string, data: { [string]: any })
	local p = c.Player
	if p and p.Parent == Players then
		Remotes.Combat:FireClient(p, op, data)
	end
end

local function extraOf(c: Combatant): Extra
	local e = extras[c]
	if not e then
		e = { DamageLog = {}, Taken = {}, HurtAt = 0 }
		extras[c] = e
	end
	return e
end

local function setAttr(c: Combatant, name: string, value: any)
	local model = c.Model
	if model and model.Parent then
		model:SetAttribute(name, value)
	end
end

local function hpAttr(c: Combatant)
	setAttr(c, "Hp", math.max(0, math.ceil(c.Hp - 1e-6)))
end

local function stampAttributes(c: Combatant)
	setAttr(c, "CombatantId", c.Id)
	setAttr(c, "Ctx", c.Ctx)
	setAttr(c, "Team", c.Team)
	setAttr(c, "Alive", c.Alive)
	setAttr(c, "MaxHp", c.MaxHp)
	hpAttr(c)
end

local function weaponDef(key: string?): Types.WeaponDef?
	if type(key) ~= "string" then
		return nil
	end
	return Config.Weapon(key)
end

-- Munition eines Slots auf Anfang (voll)
local function freshAmmo(key: string): Types.AmmoState
	local def = weaponDef(key)
	local mag = if def then def.Mag else 0
	local charges = if def and def.Charges then def.Charges else 1
	return { Mag = mag, ReloadUntil = 0, Charges = charges, CooldownUntil = 0, BurstLeft = 0 }
end

local function cleanLoadout(loadout: any): Types.Loadout
	local default: any = Config.Weapons.DefaultLoadout or {}
	local out: any = {}
	for _, slot in ipairs(SLOT_NAMES) do
		local key = if type(loadout) == "table" then loadout[slot] else nil
		local def = weaponDef(key)
		if not def or def.Slot ~= slot then
			key = default[slot]
		end
		out[slot] = key
	end
	return out :: Types.Loadout
end

local function isAdminPlayer(p: Player?): boolean
	if not p then
		return false
	end
	local ok, result = call("AdminService", "IsAdmin", p)
	if ok then
		return result == true
	end
	return p:GetAttribute("IsAdmin") == true
end

-- ---------------------------------------------------------------------
-- HELFER (öffentlich, für die WP3-Services)
-- ---------------------------------------------------------------------
function CombatService.Power(c: Combatant, name: string): any
	local p = c and c.Player
	if not p then
		return nil
	end
	local ok, value = call("AdminService", "Power", p, name)
	if ok then
		return value
	end
	return nil
end

function CombatService.IsEnemy(a: Combatant, b: Combatant): boolean
	if a == b then
		return false
	end
	if a.Kind == "Dummy" or b.Kind == "Dummy" then
		return true -- Puppen sind für alle Ziel
	end
	if a.Team == 0 or b.Team == 0 or a.Team ~= b.Team then
		return true -- Team 0 = jeder gegen jeden (FFA)
	end
	local info = contexts[a.Ctx]
	return info ~= nil and info.Rules.FriendlyFire == true
end

function CombatService.Members(ctx: string): { Combatant }
	return members[ctx] or {}
end

local function armedPayload(c: Combatant): { [string]: any }
	local info = contexts[c.Ctx]
	local rules: any = info and info.Rules or {}
	local arena: any = info and info.Arena
	local ammo: { [string]: { Mag: number, Charges: number } } = {}
	for _, slot in ipairs(SLOT_NAMES) do
		local state = c.Ammo[slot]
		if state then
			ammo[slot] = { Mag = state.Mag, Charges = state.Charges }
		end
	end
	return {
		Id = c.Id,
		Ctx = c.Ctx,
		Salt = c.Salt,
		Team = c.Team,
		Slot = c.Slot,
		Loadout = table.clone(c.Loadout),
		Origin = if arena and typeof(arena.Origin) == "CFrame" then arena.Origin.Position else Vector3.zero,
		Map = if arena then arena.Model else nil,
		Rules = {
			SpeedMult = rules.SpeedMult,
			GravityLift = rules.GravityLift,
			HeadRadiusMult = rules.HeadRadiusMult,
			AllowedSlots = rules.AllowedSlots,
			UtilityMode = rules.UtilityMode,
			IgnoreOwnership = rules.IgnoreOwnership,
		},
		Ammo = ammo,
	}
end

function CombatService.SendArmed(c: Combatant)
	if byId[c.Id] == c then
		sendCombat(c, "Armed", armedPayload(c))
	end
end

-- ---------------------------------------------------------------------
-- REGISTRY
-- ---------------------------------------------------------------------
local function allocId(kind: Types.CombatantKind, p: Player?): number
	if kind == "Player" and p then
		return p.UserId
	end
	if kind == "Dummy" then
		for _ = 1, 10000 do
			nextDummyId -= 1
			if nextDummyId < -9999 then
				nextDummyId = DUMMY_ID_START - 1
			end
			if not byId[nextDummyId] then
				return nextDummyId
			end
		end
	else
		for _ = 1, 4000 do
			nextBotId -= 1
			if nextBotId < BOT_ID_FLOOR then
				nextBotId = BOT_ID_START - 1
			end
			if not byId[nextBotId] then
				return nextBotId
			end
		end
	end
	error("[CombatService] keine freie Combatant-Id")
end

local function findParts(model: Model): (BasePart, BasePart, Humanoid?)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		root = model.PrimaryPart
	end
	if not root then
		root = model:FindFirstChildWhichIsA("BasePart", true)
	end
	if not root then
		error("[CombatService] Modell ohne Teile: " .. model:GetFullName())
	end
	local head = model:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		head = root
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return root :: BasePart, head :: BasePart, humanoid
end

function CombatService.NewCombatant(p: {
	Kind: Types.CombatantKind,
	Player: Player?,
	Model: Model,
	Ctx: string,
	Team: number,
	Slot: number,
	Name: string,
	Loadout: Types.Loadout,
	Difficulty: string?,
	MaxHp: number?,
}): Combatant
	assert(type(p) == "table" and typeof(p.Model) == "Instance", "[CombatService] NewCombatant: Model fehlt")
	local root, head, humanoid = findParts(p.Model)
	local maxHp = math.max(1, num(p.MaxHp, num(PLAYER.MaxHp, 100)))
	local loadout = cleanLoadout(p.Loadout)
	local ammo: { [SlotName]: Types.AmmoState } = {}
	for _, slot in ipairs(SLOT_NAMES) do
		ammo[slot] = freshAmmo((loadout :: any)[slot])
	end
	local c: Combatant = {
		Id = allocId(p.Kind, p.Player),
		Kind = p.Kind,
		Player = p.Player,
		Name = if type(p.Name) == "string" then string.sub(p.Name, 1, 40) else "?",
		Model = p.Model,
		Root = root,
		Head = head,
		Humanoid = humanoid,
		Ctx = tostring(p.Ctx),
		Team = math.floor(num(p.Team, 0)),
		Slot = math.clamp(math.floor(num(p.Slot, 1)), 0, 255),
		Hp = maxHp,
		MaxHp = maxHp,
		Alive = true,
		ShieldUntil = 0,
		Loadout = loadout,
		Equipped = "Primary",
		EquipReadyAt = 0,
		Ammo = ammo,
		Ads = false,
		AdsSince = 0,
		Blocking = false,
		BlockUntil = 0,
		BlockCooldownUntil = 0,
		HealUntil = 0,
		Salt = 0,
		LastShotId = 0,
		LastShotT = 0,
		ShotTimes = {},
		LastDamagerId = nil,
		LastDamageAt = 0,
		Difficulty = p.Difficulty,
		IsAdmin = isAdminPlayer(p.Player),
	}
	-- Erlaubter Start-Slot (Mutator "Nur Nahkampf" usw.)
	local info = contexts[c.Ctx]
	local allowed = info and info.Rules.AllowedSlots
	if allowed and not allowed.Primary then
		for _, slot in ipairs(SLOT_NAMES) do
			if allowed[slot] then
				c.Equipped = slot
				break
			end
		end
	end
	return c
end

function CombatService.Register(c: Combatant)
	assert(type(c) == "table" and type(c.Id) == "number", "[CombatService] Register: Combatant erwartet")
	local old = byId[c.Id]
	if old and old ~= c then
		CombatService.Unregister(old)
	end
	if c.Player then
		local previous = byPlayer[c.Player]
		if previous and previous ~= c then
			CombatService.Unregister(previous)
		end
	end
	local list = members[c.Ctx]
	if not list then
		list = {}
		members[c.Ctx] = list
	end
	if not table.find(list, c) then
		if #list >= MAX_MEMBERS then
			warn(("[CombatService] Kontext %s ist voll (%d)"):format(c.Ctx, MAX_MEMBERS))
			return
		end
		table.insert(list, c)
	end
	byId[c.Id] = c
	if c.Player then
		byPlayer[c.Player] = c
	end
	c.Salt = rng:NextInteger(1, 2147483646)
	c.LastShotId = 0
	c.LastShotT = 0
	table.clear(c.ShotTimes)
	extraOf(c)
	stampAttributes(c)
	if c.Alive then
		Services.HistoryService.Track(c)
	end

	-- Figur: Kollisionsgruppe, Tempo, 3rd-Person-Waffen (B14.8)
	local info = contexts[c.Ctx]
	local speedMult = if info then num(info.Rules.SpeedMult, 1) else 1
	call("CharacterService", "Arm", c)
	call("CharacterService", "SetBaseSpeed", c, num(PLAYER.Walk, 16) * speedMult)
	call("CharacterService", "BuildGunVisuals", c)
	call("CharacterService", "ShowSlot", c, c.Equipped)

	sendCombat(c, "Armed", armedPayload(c))
end

function CombatService.Unregister(c: Combatant)
	if type(c) ~= "table" then
		return
	end
	local registered = byId[c.Id] == c
	if registered then
		byId[c.Id] = nil
	end
	if c.Player and byPlayer[c.Player] == c then
		byPlayer[c.Player] = nil
	end
	local list = members[c.Ctx]
	if list then
		local index = table.find(list, c)
		if index then
			table.remove(list, index)
		end
	end
	extras[c] = nil
	recaps[c.Id] = nil
	recapCtx[c.Id] = nil
	Services.HistoryService.Untrack(c)
	call("WeaponService", "Forget", c)
	if not registered then
		return
	end
	setAttr(c, "CombatantId", nil)
	setAttr(c, "Ctx", nil)
	setAttr(c, "Team", nil)
	setAttr(c, "Alive", nil)
	setAttr(c, "Hp", nil)
	setAttr(c, "MaxHp", nil)
	setAttr(c, "ShieldUntil", nil)
	call("CharacterService", "Disarm", c)
	sendCombat(c, "Disarmed", {})
end

function CombatService.Get(id: number): Combatant?
	return byId[id]
end

function CombatService.OfPlayer(p: Player): Combatant?
	return byPlayer[p]
end

function CombatService.InCtx(ctx: string): { Combatant }
	local list = members[ctx]
	return if list then table.clone(list) else {}
end

-- Neuer Character für einen bestehenden Combatant (Fallback-Respawn im Match)
function CombatService.Rebind(c: Combatant, model: Model)
	local ok, root, head, humanoid = pcall(findParts, model)
	if not ok then
		warn("[CombatService] Rebind: " .. tostring(root))
		return
	end
	c.Model = model
	c.Root = root
	c.Head = head
	c.Humanoid = humanoid
	if byId[c.Id] == c then
		stampAttributes(c)
		if c.Alive then
			Services.HistoryService.Track(c)
		end
	end
end

-- ---------------------------------------------------------------------
-- KONTEXTE
-- ---------------------------------------------------------------------
function CombatService.RegisterContext(info: ContextInfo)
	assert(
		type(info) == "table" and type(info.Ctx) == "string",
		"[CombatService] RegisterContext: ContextInfo erwartet"
	)
	contexts[info.Ctx] = info
	if not members[info.Ctx] then
		members[info.Ctx] = {}
	end
	roundDamage[info.Ctx] = roundDamage[info.Ctx] or {}
	pairDamage[info.Ctx] = pairDamage[info.Ctx] or {}
end

function CombatService.UnregisterContext(ctx: string)
	local list = members[ctx]
	if list then
		for _, c in ipairs(table.clone(list)) do
			CombatService.Unregister(c)
		end
	end
	call("ProjectileService", "ClearCtx", ctx)
	CombatService.ResetRound(ctx)
	members[ctx] = nil
	contexts[ctx] = nil
	roundDamage[ctx] = nil
	pairDamage[ctx] = nil
end

function CombatService.Context(ctx: string): ContextInfo?
	return contexts[ctx]
end

-- ---------------------------------------------------------------------
-- SCHADEN
-- ---------------------------------------------------------------------
local BYPASS_KINDS = { Void = true, Fallback = true } -- Sturz/Fallback gehen durch Schild und God

local function blockFactor(victim: Combatant, info: DamageInfo): number
	if not victim.Blocking or now() > victim.BlockUntil then
		return 1
	end
	if info.Kind ~= "Hitscan" and info.Kind ~= "Splash" and info.Kind ~= "Melee" then
		return 1
	end
	local def: any = weaponDef(victim.Loadout.Melee)
	local block = def and def.Melee and def.Melee.Block
	if not block or victim.Equipped ~= "Melee" then
		return 1
	end
	if typeof(info.From) ~= "Vector3" or not victim.Root.Parent then
		return 1
	end
	local toSource = info.From - victim.Root.Position
	local flat = Vector3.new(toSource.X, 0, toSource.Z)
	local look = victim.Root.CFrame.LookVector
	local lookFlat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 or lookFlat.Magnitude < 1e-3 then
		return num(block.Mult, 1)
	end
	local cosAngle = flat.Unit:Dot(lookFlat.Unit)
	if cosAngle >= math.cos(math.rad(num(block.Cone, 75))) then
		return math.clamp(num(block.Mult, 1), 0, 1)
	end
	return 1
end

local function logPair(ctx: string, attackerId: number, victimId: number, dealt: number, head: boolean)
	local byAttacker = pairDamage[ctx]
	if not byAttacker then
		return
	end
	local row = byAttacker[attackerId]
	if not row then
		row = {}
		byAttacker[attackerId] = row
	end
	local stat = row[victimId]
	if not stat then
		stat = { D = 0, Hits = 0, Heads = 0 }
		row[victimId] = stat
	end
	stat.D += dealt
	stat.Hits += 1
	if head then
		stat.Heads += 1
	end
end

local function resolveKiller(victim: Combatant, attacker: Combatant?): Combatant?
	if attacker and attacker ~= victim then
		return attacker
	end
	local window = num(COMBAT.KillCreditWindow, 8)
	if victim.LastDamagerId and now() - victim.LastDamageAt <= window then
		local other = byId[victim.LastDamagerId]
		if other and other ~= victim then
			return other
		end
	end
	return nil
end

local function assistsFor(victim: Combatant, killerId: number?): { number }
	local e = extras[victim]
	if not e then
		return {}
	end
	local window = num(COMBAT.AssistWindow, 8)
	local need = num(COMBAT.AssistDamage, 25)
	local t = now()
	local sums: { [number]: number } = {}
	for _, hit in ipairs(e.DamageLog) do
		if t - hit.T <= window and hit.Id ~= victim.Id and hit.Id ~= killerId then
			sums[hit.Id] = (sums[hit.Id] or 0) + hit.D
		end
	end
	local out: { number } = {}
	for id, total in pairs(sums) do
		if total >= need then
			table.insert(out, id)
		end
	end
	table.sort(out)
	return out
end

local function isSliding(c: Combatant?): boolean
	if not c or not c.Player then
		return false
	end
	local ok, flags = call("ReplicationService", "Flags", c.Player)
	return ok and type(flags) == "number" and bit32.band(flags, 4) ~= 0
end

function CombatService.ApplyDamage(
	attacker: Combatant?,
	victim: Combatant,
	amount: number,
	info: DamageInfo
): (number, boolean)
	if type(victim) ~= "table" or not victim.Alive or byId[victim.Id] ~= victim then
		return 0, false
	end
	if not Util.IsFinite(amount) or amount <= 0 or type(info) ~= "table" then
		return 0, false
	end
	local t = now()
	local bypass = BYPASS_KINDS[info.Kind] == true
	if not bypass then
		if victim.ShieldUntil > t then
			return 0, false -- Spawn-Schutz
		end
		if CombatService.Power(victim, "AdminGod") then
			return 0, false
		end
		if attacker and attacker ~= victim and not CombatService.IsEnemy(attacker, victim) then
			return 0, false -- kein Eigenbeschuss im Team
		end
		amount *= blockFactor(victim, info)
	end
	local dealt = math.min(amount, victim.Hp)
	if dealt <= 0 then
		return 0, false
	end
	victim.Hp -= dealt
	if victim.Hp < 1e-6 then
		victim.Hp = 0
	end
	hpAttr(victim)

	local e = extraOf(victim)
	e.HurtAt = t
	victim.HealUntil = 0 -- Heil-Limo bricht ab (WeaponService prüft HurtAt)
	if attacker and attacker ~= victim then
		victim.LastDamagerId = attacker.Id
		victim.LastDamageAt = t
		table.insert(e.DamageLog, { Id = attacker.Id, D = dealt, T = t })
		if #e.DamageLog > MAX_DAMAGE_LOG then
			table.remove(e.DamageLog, 1)
		end
		local round = roundDamage[victim.Ctx]
		if round then
			round[attacker.Id] = (round[attacker.Id] or 0) + dealt
		end
		logPair(victim.Ctx, attacker.Id, victim.Id, dealt, info.Head)
	end
	table.insert(e.Taken, {
		W = tostring(info.WeaponKey),
		D = math.floor(dealt + 0.5),
		H = info.Head == true,
		Dist = math.floor(num(info.Dist, 0) + 0.5),
		T = t,
	})
	local recapMax = math.max(1, math.floor(num(COMBAT.RecapMax, 12)))
	while #e.Taken > recapMax do
		table.remove(e.Taken, 1)
	end

	sendCombat(victim, "Hurt", {
		D = math.floor(dealt + 0.5),
		F = if typeof(info.From) == "Vector3" then info.From else victim.Root.Position,
		H = info.Head == true,
		Hp = math.max(0, math.ceil(victim.Hp - 1e-6)),
	})
	for _, cb in ipairs(damageCallbacks) do
		task.defer(function()
			local ok, err = pcall(cb, attacker, victim, dealt, info)
			if not ok then
				warn("[CombatService] OnDamage-Callback: " .. tostring(err))
			end
		end)
	end

	if victim.Hp <= 0 then
		local killer = resolveKiller(victim, attacker)
		local killerId = if killer then killer.Id else nil
		CombatService.Eliminate(victim, {
			WeaponKey = tostring(info.WeaponKey),
			Head = info.Head == true,
			Kind = info.Kind,
			KillerId = killerId,
			Assists = assistsFor(victim, killerId),
			Pos = victim.Root.Position,
			KillerSliding = isSliding(killer),
			Melee = info.Kind == "Melee",
			Splash = info.Kind == "Splash",
			Void = info.Kind == "Void",
		})
		return dealt, true
	end
	return dealt, false
end

function CombatService.Heal(c: Combatant, amount: number): number
	if type(c) ~= "table" or not c.Alive or not Util.IsFinite(amount) or amount <= 0 then
		return 0
	end
	local healed = math.min(amount, c.MaxHp - c.Hp)
	if healed <= 0 then
		return 0
	end
	local before = math.ceil(c.Hp - 1e-6)
	c.Hp += healed
	local after = math.ceil(c.Hp - 1e-6)
	if after ~= before then
		hpAttr(c)
		sendCombat(c, "Heal", { Hp = after })
	end
	return healed
end

-- ---------------------------------------------------------------------
-- POP / REVIVE (B13.3)
-- ---------------------------------------------------------------------
local function buildRecap(victim: Combatant, killer: Combatant?, weaponKey: string): RecapData
	local e = extras[victim]
	local taken: { RecapHit } = {}
	if e then
		for i, hit in ipairs(e.Taken) do
			taken[i] = table.clone(hit)
		end
	end
	local dealt: PairStat? = nil
	if killer then
		local byAttacker = pairDamage[victim.Ctx]
		local row = byAttacker and byAttacker[victim.Id]
		dealt = row and row[killer.Id]
	end
	return {
		KillerId = if killer then killer.Id else nil,
		KillerName = if killer then killer.Name else "",
		KillerHp = if killer then math.max(0, math.ceil(killer.Hp - 1e-6)) else 0,
		WeaponKey = weaponKey,
		Taken = taken,
		DealtToKiller = if dealt then math.floor(dealt.D + 0.5) else 0,
		DealtHits = if dealt then dealt.Hits else 0,
		DealtHeads = if dealt then dealt.Heads else 0,
	}
end

function CombatService.Eliminate(victim: Combatant, info: ElimInfo)
	if type(victim) ~= "table" or not victim.Alive then
		return
	end
	local elim: any = if type(info) == "table" then table.clone(info) else {}
	if type(elim.WeaponKey) ~= "string" then
		elim.WeaponKey = "Void"
	end
	if type(elim.Kind) ~= "string" then
		elim.Kind = "Fallback"
	end
	local killer: Combatant? = nil
	if type(elim.KillerId) == "number" then
		killer = byId[elim.KillerId]
	else
		killer = resolveKiller(victim, nil)
		elim.KillerId = if killer then killer.Id else nil
	end
	if killer == victim then
		killer = nil
		elim.KillerId = nil
	end
	if type(elim.Assists) ~= "table" then
		elim.Assists = assistsFor(victim, elim.KillerId)
	end
	if typeof(elim.Pos) ~= "Vector3" then
		elim.Pos = if victim.Root.Parent then victim.Root.Position else Vector3.zero
	end
	elim.Head = elim.Head == true

	victim.Alive = false
	victim.Hp = 0
	victim.Blocking = false
	victim.HealUntil = 0
	setAttr(victim, "Alive", false)
	hpAttr(victim)
	Services.HistoryService.Untrack(victim)

	recaps[victim.Id] = buildRecap(victim, killer, elim.WeaponKey)
	recapCtx[victim.Id] = victim.Ctx

	if victim.Player then
		call("AntiCheatService", "Exempt", victim.Player, 2)
	end
	call("CharacterService", "Pop", victim)

	-- Live-Balance-Statistik (nur Pops durch Menschen)
	if killer and killer.Kind == "Player" then
		call("BalanceService", "Stat", "Kill", elim.WeaponKey, 1)
		if elim.Head then
			call("BalanceService", "Stat", "Head", elim.WeaponKey, 1)
		end
	end

	for _, cb in ipairs(elimCallbacks) do
		task.defer(function()
			local ok, err = pcall(cb, victim, killer, elim)
			if not ok then
				warn("[CombatService] OnElimination-Callback: " .. tostring(err))
			end
		end)
	end
end

function CombatService.Revive(c: Combatant, at: CFrame, shieldSeconds: number?)
	if type(c) ~= "table" or typeof(at) ~= "CFrame" then
		return
	end
	c.Hp = c.MaxHp
	c.Alive = true
	c.Blocking = false
	c.BlockUntil = 0
	c.HealUntil = 0
	c.LastDamagerId = nil
	c.LastDamageAt = 0
	table.clear(c.ShotTimes)
	local e = extraOf(c)
	table.clear(e.DamageLog)
	table.clear(e.Taken)
	e.HurtAt = 0
	setAttr(c, "Alive", true)
	hpAttr(c)
	call("CharacterService", "Unpop", c, at)
	if byId[c.Id] == c then
		Services.HistoryService.Track(c)
	end
	call("WeaponService", "ResetForRound", c)
	if Util.IsFinite(shieldSeconds) and (shieldSeconds :: number) > 0 then
		CombatService.SetShield(c, shieldSeconds :: number)
	else
		c.ShieldUntil = 0
		setAttr(c, "ShieldUntil", nil)
	end
end

function CombatService.SetShield(c: Combatant, seconds: number)
	if type(c) ~= "table" then
		return
	end
	local s = math.clamp(num(seconds, 0), 0, 60)
	c.ShieldUntil = if s > 0 then now() + s else 0
	setAttr(c, "ShieldUntil", if s > 0 then c.ShieldUntil else nil) -- Schimmer-Effekt (Client)
end

-- ---------------------------------------------------------------------
-- RUNDEN-LOGS
-- ---------------------------------------------------------------------
function CombatService.ResetRound(ctx: string)
	if roundDamage[ctx] then
		roundDamage[ctx] = {}
	end
	if pairDamage[ctx] then
		pairDamage[ctx] = {}
	end
	for id, rc in pairs(recapCtx) do
		if rc == ctx then
			recaps[id] = nil
			recapCtx[id] = nil
		end
	end
	local list = members[ctx]
	if list then
		for _, c in ipairs(list) do
			local e = extras[c]
			if e then
				table.clear(e.DamageLog)
				table.clear(e.Taken)
			end
		end
	end
end

function CombatService.Recap(victimId: number): RecapData?
	return recaps[victimId]
end

function CombatService.RoundDamage(ctx: string): { [number]: number }
	local round = roundDamage[ctx]
	return if round then table.clone(round) else {}
end

function CombatService.TeamHp(ctx: string, team: number): number
	local total = 0
	for _, c in ipairs(members[ctx] or {}) do
		if c.Alive and c.Team == team then
			total += c.Hp
		end
	end
	return total
end

-- ---------------------------------------------------------------------
-- SIGNALE
-- ---------------------------------------------------------------------
function CombatService.OnDamage(cb: (attacker: Combatant?, victim: Combatant, dealt: number, info: DamageInfo) -> ())
	if type(cb) == "function" then
		table.insert(damageCallbacks, cb)
	end
end

function CombatService.OnElimination(cb: (victim: Combatant, killer: Combatant?, info: ElimInfo) -> ())
	if type(cb) == "function" then
		table.insert(elimCallbacks, cb)
	end
end

-- ---------------------------------------------------------------------
-- TAKT 5 Hz: KillY, fehlende Teile, Regeneration
-- ---------------------------------------------------------------------
local function voidPop(c: Combatant, kind: "Void" | "Fallback")
	local pos = if c.Root.Parent then c.Root.Position else Vector3.zero
	CombatService.ApplyDamage(nil, c, c.Hp + 1, {
		WeaponKey = kind,
		Head = false,
		Kind = kind,
		Dist = 0,
		From = pos,
	})
end

local function tick(dt: number)
	local t = now()
	local regenDelay = num(PLAYER.Regen and PLAYER.Regen.Delay, 5)
	local regenRate = num(PLAYER.Regen and PLAYER.Regen.Rate, 12)
	for ctx, list in pairs(members) do
		local info = contexts[ctx]
		local arena: any = info and info.Arena
		local killY = if arena and Util.IsFinite(arena.KillY) then arena.KillY else nil
		local regen = info ~= nil and info.Rules.Regen == true
		for _, c in ipairs(table.clone(list)) do
			if not c.Alive then
				continue
			end
			local root, head = c.Root, c.Head
			local humanoid = c.Humanoid
			if not root.Parent or not head.Parent or (humanoid and (not humanoid.Parent or humanoid.Health <= 0)) then
				voidPop(c, "Fallback") -- Kopf/HRP/Humanoid weg (C12.5)
				continue
			end
			if killY and c.Kind ~= "Dummy" and root.Position.Y < killY then
				voidPop(c, "Void") -- Sturz unter KillY = Pop
				continue
			end
			if regen and c.Hp < c.MaxHp then
				local e = extraOf(c)
				if t - e.HurtAt >= regenDelay then
					CombatService.Heal(c, regenRate * dt)
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- LEBENSZYKLUS
-- ---------------------------------------------------------------------
function CombatService.Init(services: any)
	Services = services
end

function CombatService.Start()
	Scheduler.Every("CombatTick", num(COMBAT.KillYHz, 5), tick)
	Players.PlayerRemoving:Connect(function(p: Player)
		-- erst nach den anderen PlayerRemoving-Handlern (MatchService ersetzt ggf. durch einen Bot)
		task.defer(function()
			local c = byPlayer[p]
			if c then
				CombatService.Unregister(c)
			end
			byPlayer[p] = nil
		end)
	end)
end

return CombatService
