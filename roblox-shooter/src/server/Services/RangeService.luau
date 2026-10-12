-- =====================================================================
--  CLUTCH CLASH – Training / Schießstand (Server/Services/RangeService)
--  Besitzer: WP6 (Bots & Training-Range). Vertrag: DESIGN.md C5.6, B2 (Range-Teil), C9 ("RangeWeapon").
--
--  Ablauf:
--    * Kontext "Range" (CombatService.RegisterContext) mit IgnoreOwnership = true: jede Waffe gratis testbar.
--    * Zone 4 Hz (LobbyBuilder.RangeZone): betreten -> Combatant (Team 1, Combat("Armed") über Register),
--      verlassen -> Unregister. Alle Spieler sind Team 1 und FriendlyFire ist aus -> sie treffen sich nie.
--      Wer in einem Match ist (MatchService.MatchOf) oder in einem anderen Kontext kämpft, wird nicht bewaffnet.
--    * 24 statische Puppen + 2 Schiene-Puppen (LobbyBuilder.RangeDummySpots), Team 2, 150 HP, 3 s ohne
--      Schaden -> wieder voll; gepoppte Puppen stehen nach 3 s wieder. Schiene-Puppen: unverankert,
--      Netzwerk-Besitz Server, LinearVelocity ±8 Studs/s, Wechsel an den Enden (±5) bzw. spätestens alle 2 s.
--    * Request "RangeWeapon" {Slot, Key} (4/s): Waffe für die Range wählen. In der Range sofort ausgerüstet,
--      sonst Teleport an die Schusslinie ("Gratis testen" aus dem Shop, PLAY -> Training) bzw. gemerkt.
--    * Eigener Pop in der Range (z. B. Raketen-Splash) -> nach 1.5 s an der Schusslinie zurück.
--
--  Öffentliche API (C5.6):
--    RangeService.IsInRange(p): boolean
--    RangeService.SetWeapon(p, slot, key)
--    RangeService.Members(): { Player }
-- =====================================================================

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Lang = require(Shared:WaitForChild("Lang"))
local Types = require(Shared:WaitForChild("Types"))

local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local RangeService = {}
local Services: any = nil

local CTX = "Range"
local PLAYER_TEAM = 1
local DUMMY_TEAM = 2
local LEAVE_MARGIN = 2 -- Studs Puffer beim Verlassen (kein Flackern an der Kante)
local MAX_PLAYER_SLOTS = 32
local MAX_KEY_LEN = 40

local BOTS: any = Config.Bots
local RANGE: any = BOTS.Range or {}
local DUMMY_HP = math.max(1, tonumber(RANGE.DummyHp) or 150)
local REGEN_AFTER = math.max(0, tonumber(RANGE.DummyRegenAfter) or 3)
local RAIL_SPEED = tonumber(RANGE.RailSpeed) or 8
local RAIL_FLIP = math.max(0.2, tonumber(RANGE.RailFlip) or 2)
local RAIL_AMPLITUDE = math.max(1, tonumber(RANGE.RailAmplitude) or 5)
local SCAN_HZ = math.max(1, tonumber(RANGE.ScanHz) or 4)
local PLAYER_REVIVE = math.max(0.2, tonumber(RANGE.PlayerReviveDelay) or 1.5)
local DUMMY_SLOT_BASE = math.floor(tonumber(RANGE.DummySlotBase) or 200)

-- Fallback-Koordinaten aus B2 (nur falls LobbyBuilder fehlt)
local FALLBACK_ZONE_CF = CFrame.new(-131, 10, 0)
local FALLBACK_ZONE_SIZE = Vector3.new(138, 40, 112)
local FALLBACK_FIRING_X = -66
local LANES = { -35, -21, -7, 7, 21, 35 }
local DUMMY_X = { -81, -96, -126, -166 }
local RAIL_X = -110

local SLOT_NAMES: { [string]: boolean } = { Primary = true, Secondary = true, Melee = true, Utility = true }
local SLOTS: { Types.SlotName } = { "Primary", "Secondary", "Melee", "Utility" }
local FALLBACK_LOADOUT: Types.Loadout =
	{ Primary = "PopRifle", Secondary = "PipPistol", Melee = "BoxingGloves", Utility = "PopGrenade" }

-- Regeln des Range-Kontexts (Types.ContextRules)
local RULES: Types.ContextRules = {
	DamageMult = 1,
	HeadOnly = false,
	HeadRadiusMult = 1,
	IntervalMult = 1,
	ReloadMult = 1,
	SpeedMult = 1,
	GravityLift = 0,
	AllowedSlots = nil,
	ForcedLoadout = nil,
	RandomLoadout = false,
	Regen = true,
	UtilityMode = "Cooldown",
	FriendlyFire = false,
	IgnoreOwnership = true,
}

type Member = {
	C: Types.Combatant,
	Character: Model,
	Since: number,
	ReviveAt: number?,
}

type Dummy = {
	Index: number,
	Model: Model,
	Root: BasePart,
	Parts: { BasePart },
	Home: CFrame,
	Moving: boolean,
	Distance: number,
	C: Types.Combatant?,
	LastHit: number,
	ReviveAt: number?,
	Dir: number,
	FlipAt: number,
	Velocity: LinearVelocity?,
}

local members: { [Player]: Member } = {}
local memberList: { Player } = {}
local choices: { [Player]: { [string]: string } } = {} -- gewählte Range-Waffen je Platz (Sitzung)
local greeted: { [Player]: boolean } = {}
local charConns: { [Player]: RBXScriptConnection } = {}
local dummies: { Dummy } = {}
local dummyOf: { [Types.Combatant]: Dummy } = {}
local dummyFolder: Folder? = nil
local arena: any = nil
local contextReady = false
local zoneCF: CFrame = FALLBACK_ZONE_CF
local zoneSize: Vector3 = FALLBACK_ZONE_SIZE
local floorY = 0
local rng = Random.new()

-- ---------------------------------------------------------------------
-- HILFEN
-- ---------------------------------------------------------------------
local function now(): number
	return workspace:GetServerTimeNow()
end

local function call(serviceName: string, fnName: string, ...: any): (boolean, ...any)
	local s = if Services then Services[serviceName] else nil
	local fn = if s then s[fnName] else nil
	if type(fn) ~= "function" then
		return false, nil
	end
	return pcall(fn, ...)
end

local function langOf(p: Player): Types.Lang
	local ok, lang = call("PlayerStateService", "LangOf", p)
	if ok and (lang == "de" or lang == "en") then
		return lang
	end
	local okFor, langFor = pcall(Lang.For, p)
	if okFor and (langFor == "de" or langFor == "en") then
		return langFor
	end
	return "en"
end

local function tr(p: Player, key: string, ...: any): string
	return Lang.T(langOf(p), key, ...)
end

local function weaponDef(key: any): Types.WeaponDef?
	if type(key) ~= "string" then
		return nil
	end
	local ok, def = pcall(Config.Weapon, key)
	if ok and type(def) == "table" then
		return def
	end
	return nil
end

-- In der Range erlaubt: jede aktive Nicht-Admin-Waffe im passenden Platz
local function rangeWeaponOk(key: any, slot: string): boolean
	local def = weaponDef(key)
	return def ~= nil and def.Slot == slot and def.Enabled ~= false and def.AdminOnly ~= true
end

local function defaultLoadout(): Types.Loadout
	local weapons: any = Config.Weapons
	local base: any = if type(weapons) == "table" then weapons.DefaultLoadout else nil
	local result: any = {}
	for _, slot in SLOTS do
		local key = if type(base) == "table" then base[slot] else nil
		result[slot] = if type(key) == "string" then key else (FALLBACK_LOADOUT :: any)[slot]
	end
	return result
end

local function rebuildMemberList()
	local fresh: { Player } = {}
	for p in members do
		table.insert(fresh, p)
	end
	memberList = fresh
end

local function inZone(pos: Vector3, margin: number): boolean
	local localPos = zoneCF:PointToObjectSpace(pos)
	local half = zoneSize / 2
	local halfY = math.max(half.Y, 20)
	return math.abs(localPos.X) <= half.X + margin
		and math.abs(localPos.Z) <= half.Z + margin
		and math.abs(localPos.Y) <= halfY + margin
end

-- Schusslinie: Ostrand der Zone minus 2 Studs (X = −64), Blick nach −X, zufällige Bahn
local function firingLineCF(): CFrame
	local east = zoneCF:PointToWorldSpace(Vector3.new(zoneSize.X / 2, 0, 0)).X
	local x = math.min(east - 2, FALLBACK_FIRING_X + 2)
	local z = LANES[rng:NextInteger(1, #LANES)]
	local pos = Vector3.new(x, floorY + 3, z)
	return CFrame.lookAt(pos, pos + Vector3.new(-1, 0, 0))
end

local function characterParts(char: Model?): (BasePart?, Humanoid?, BasePart?)
	if char == nil then
		return nil, nil, nil
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local head = char:FindFirstChild("Head")
	return if root and root:IsA("BasePart") then root else nil,
		humanoid,
		if head and head:IsA("BasePart") then head else nil
end

-- ---------------------------------------------------------------------
-- PUPPEN BAUEN (Init)
-- ---------------------------------------------------------------------
local DISTANCE_COLORS: { Color3 } = {
	Color3.fromRGB(154, 209, 212), -- 15 Studs  Mint
	Color3.fromRGB(242, 213, 154), -- 30        Sand
	Color3.fromRGB(185, 167, 242), -- 60        Lila
	Color3.fromRGB(247, 183, 200), -- 100       Pink
}
local RAIL_COLOR = Color3.fromRGB(255, 145, 35)

local function colorFor(distance: number, moving: boolean): Color3
	if moving then
		return RAIL_COLOR
	end
	local list: any = RANGE.DummyDistances or { 15, 30, 60, 100 }
	local best, bestD = 1, math.huge
	for i, d in ipairs(list) do
		local diff = math.abs((tonumber(d) or 0) - distance)
		if diff < bestD then
			best = i
			bestD = diff
		end
	end
	return DISTANCE_COLORS[math.clamp(best, 1, #DISTANCE_COLORS)]
end

local function newPart(name: string, shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanTouch = false
	return part
end

-- Boden unter einem Punkt finden (Lobby ist zu diesem Zeitpunkt gebaut)
local function groundBelow(pos: Vector3): number
	local params = RaycastParams.new()
	-- klassische Form (FilterType + FilterDescendantsInstances), nicht mit Include/ExcludeInstances mischen
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	if dummyFolder then
		table.insert(exclude, dummyFolder :: Folder)
	end
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true
	local hit = workspace:Raycast(pos + Vector3.new(0, 8, 0), Vector3.new(0, -30, 0), params)
	if hit then
		return hit.Position.Y
	end
	return if pos.Y <= 1.5 then pos.Y else pos.Y - 3
end

-- Puppe = Sockel + Stange + Rumpf ("HumanoidRootPart", trägt die analytische Hitbox) + Kopf.
-- Maße wie ein Standard-Character: Wurzel-Mitte 3 über dem Boden, Kopf 4.6 (Hitbox-Kugel r 0.8 + 0.35).
local function buildDummy(index: number, ground: Vector3, moving: boolean, distance: number, parent: Instance): Dummy
	local model = Instance.new("Model")
	model.Name = string.format("Dummy_%02d", index)
	local facing = CFrame.lookAt(ground, ground + Vector3.new(1, 0, 0)) -- schaut zur Schusslinie (+X)
	local color = colorFor(distance, moving)
	local upright = CFrame.Angles(0, 0, math.rad(90)) -- Zylinder-Achse senkrecht
	local base = newPart(
		"Base",
		Enum.PartType.Cylinder,
		Vector3.new(0.4, 3, 3),
		facing * CFrame.new(0, 0.2, 0) * upright,
		Color3.fromRGB(43, 43, 51)
	)
	local pole = newPart(
		"Pole",
		Enum.PartType.Cylinder,
		Vector3.new(1.8, 0.5, 0.5),
		facing * CFrame.new(0, 1.3, 0) * upright,
		Color3.fromRGB(235, 238, 245)
	)
	local root =
		newPart("HumanoidRootPart", Enum.PartType.Block, Vector3.new(2, 2, 1), facing * CFrame.new(0, 3, 0), color)
	local head = newPart(
		"Head",
		Enum.PartType.Ball,
		Vector3.new(1.6, 1.6, 1.6),
		facing * CFrame.new(0, 4.6, 0),
		Color3.fromRGB(244, 235, 221)
	)
	local parts: { BasePart } = { base, pole, root, head }
	for _, part in parts do
		part.Parent = model
	end
	model.PrimaryPart = root
	model:SetAttribute("IsDummy", true)
	model:SetAttribute("MaxHp", DUMMY_HP)
	model:SetAttribute("Distance", distance)
	model:SetAttribute("Moving", moving)
	CollectionService:AddTag(model, "RangeDummy") -- Training (Lebensbalken)
	CollectionService:AddTag(model, "Dummy") -- andere Client-Module (Schadenszahlen, Admin-ESP)

	local velocity: LinearVelocity? = nil
	if moving then
		-- Schiene: unverankert, schwebt (Vektor-Geschwindigkeit hält Y), bleibt aufrecht, schleift nirgends
		for _, part in parts do
			part.Anchored = false
			part.CanCollide = false
			if part ~= root then
				part.Massless = true
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = part
				weld.Parent = part
			end
		end
		local attachment = Instance.new("Attachment")
		attachment.Name = "RailAttach"
		attachment.Parent = root
		local lv = Instance.new("LinearVelocity")
		lv.Attachment0 = attachment
		lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		lv.RelativeTo = Enum.ActuatorRelativeTo.World
		lv.MaxForce = 1e6
		lv.VectorVelocity = Vector3.zero
		lv.Parent = root
		local align = Instance.new("AlignOrientation")
		align.Mode = Enum.OrientationAlignmentMode.OneAttachment
		align.Attachment0 = attachment
		align.RigidityEnabled = true
		align.CFrame = facing.Rotation
		align.Parent = root
		velocity = lv
	else
		for _, part in parts do
			part.Anchored = true
		end
	end
	model.Parent = parent
	return {
		Index = index,
		Model = model,
		Root = root,
		Parts = parts,
		Home = root.CFrame,
		Moving = moving,
		Distance = distance,
		C = nil,
		LastHit = -math.huge,
		ReviveAt = nil,
		Dir = 1,
		FlipAt = 0,
		Velocity = velocity,
	}
end

local function buildRail(ground: Vector3, parent: Instance)
	local rail = newPart(
		"Rail",
		Enum.PartType.Block,
		Vector3.new(0.6, 0.2, RAIL_AMPLITUDE * 2 + 3),
		CFrame.new(ground + Vector3.new(0, 0.1, 0)),
		Color3.fromRGB(43, 43, 51)
	)
	rail.Anchored = true
	rail.CanCollide = false
	rail.CanQuery = false
	rail.Material = Enum.Material.Metal
	rail.Parent = parent
end

local function dummySpots(): { { Pos: Vector3, Moving: boolean } }
	local ok, spots = call("LobbyBuilder", "RangeDummySpots")
	local result: { { Pos: Vector3, Moving: boolean } } = {}
	if ok and type(spots) == "table" then
		for _, spot in spots do
			if type(spot) == "table" and typeof(spot.Pos) == "Vector3" then
				table.insert(result, { Pos = spot.Pos, Moving = spot.Moving == true })
			end
			if #result >= 40 then
				break
			end
		end
	end
	if #result > 0 then
		return result
	end
	-- Fallback B2: 6 Bahnen × 4 Entfernungen + 2 Schiene-Puppen (Bahn 3 und 4)
	for _, z in LANES do
		for _, x in DUMMY_X do
			table.insert(result, { Pos = Vector3.new(x, 0, z), Moving = false })
		end
	end
	table.insert(result, { Pos = Vector3.new(RAIL_X, 0, LANES[3]), Moving = true })
	table.insert(result, { Pos = Vector3.new(RAIL_X, 0, LANES[4]), Moving = true })
	return result
end

local function buildDummies()
	local folder = Instance.new("Folder")
	folder.Name = "RangeDummies"
	dummyFolder = folder
	local firingX = math.min(zoneCF:PointToWorldSpace(Vector3.new(zoneSize.X / 2, 0, 0)).X - 4, FALLBACK_FIRING_X)
	for index, spot in dummySpots() do
		local groundY = groundBelow(spot.Pos)
		local ground = Vector3.new(spot.Pos.X, groundY, spot.Pos.Z)
		local distance = math.max(0, math.floor(firingX - spot.Pos.X + 0.5))
		local dummy = buildDummy(index, ground, spot.Moving, distance, folder)
		if spot.Moving then
			buildRail(ground, folder)
		end
		table.insert(dummies, dummy)
	end
	folder.Parent = workspace
	for _, d in dummies do
		if d.Moving then
			pcall(function()
				d.Root:SetNetworkOwner(nil)
			end)
		end
	end
end

-- ---------------------------------------------------------------------
-- KONTEXT & ARENA
-- ---------------------------------------------------------------------
local function fallbackArena(): any
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	if dummyFolder then
		table.insert(exclude, dummyFolder :: Folder)
	end
	local bots = workspace:FindFirstChild("Bots")
	if bots then
		table.insert(exclude, bots)
	end
	params.FilterDescendantsInstances = exclude
	return {
		Slot = -1,
		Key = "Range",
		BuildId = 0,
		Model = dummyFolder or Instance.new("Model"),
		Origin = CFrame.new(zoneCF.Position.X, floorY, zoneCF.Position.Z),
		Spawns = { A = {}, B = {}, FFA = {} },
		Zone = Vector3.new(zoneCF.Position.X, floorY, zoneCF.Position.Z),
		ZoneRadius = 0,
		KillY = -40,
		Vault = CFrame.new(zoneCF.Position.X, floorY - 250, zoneCF.Position.Z),
		Nav = { Nodes = {}, Edges = {} },
		MapParams = params,
	}
end

local function ensureContext(): boolean
	if contextReady then
		return true
	end
	local combat = Services and Services.CombatService
	if not combat then
		return false
	end
	if arena == nil then
		local ok, result = call("ArenaService", "Range")
		arena = if ok and type(result) == "table" then result else fallbackArena()
	end
	local info: Types.ContextInfo = {
		Ctx = CTX,
		Arena = arena,
		Rules = RULES,
		Recipients = function(): { Player }
			return table.clone(memberList)
		end,
		MatchId = nil,
	}
	local ok, err = pcall(combat.RegisterContext, info)
	if not ok then
		warn("[RangeService] RegisterContext fehlgeschlagen: " .. tostring(err))
		return false
	end
	contextReady = true
	return true
end

local function registerDummies()
	local combat = Services and Services.CombatService
	if not combat or not contextReady then
		return
	end
	local loadout = defaultLoadout()
	for _, d in dummies do
		if d.C == nil then
			local ok, c = pcall(combat.NewCombatant, {
				Kind = "Dummy",
				Player = nil,
				Model = d.Model,
				Ctx = CTX,
				Team = DUMMY_TEAM,
				Slot = DUMMY_SLOT_BASE + d.Index,
				Name = string.format("Dummy %d", d.Distance),
				Loadout = table.clone(loadout),
				MaxHp = DUMMY_HP,
			})
			if ok and type(c) == "table" then
				-- Register trackt die Puppe auch gleich im HistoryService (statisch, solange sie steht)
				local okReg = pcall(combat.Register, c)
				if okReg then
					d.C = c
					dummyOf[c] = d
				end
			else
				warn("[RangeService] Puppe " .. d.Index .. " nicht registriert: " .. tostring(c))
				break
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- SPIELER BEWAFFNEN / ENTWAFFNEN
-- ---------------------------------------------------------------------
local function loadoutFor(p: Player): Types.Loadout
	local result: any = defaultLoadout()
	local ok, lo = call("ShopService", "GetLoadout", p, RULES)
	if ok and type(lo) == "table" then
		for _, slot in SLOTS do
			if rangeWeaponOk(lo[slot], slot) then
				result[slot] = lo[slot]
			end
		end
	end
	local choice = choices[p]
	if choice then
		for slot, key in choice do
			if rangeWeaponOk(key, slot) then
				result[slot] = key
			end
		end
	end
	return result
end

local function freeSlot(): number
	local used: { [number]: boolean } = {}
	local ok, all = call("CombatService", "InCtx", CTX)
	if ok and type(all) == "table" then
		for _, c in all do
			if type(c) == "table" and type(c.Slot) == "number" then
				used[c.Slot] = true
			end
		end
	end
	for _, m in members do
		used[m.C.Slot] = true
	end
	for i = 1, MAX_PLAYER_SLOTS do
		if not used[i] then
			return i
		end
	end
	return MAX_PLAYER_SLOTS
end

local function busyElsewhere(p: Player, isMember: boolean): boolean
	local okMatch, matchId = call("MatchService", "MatchOf", p)
	if okMatch and matchId ~= nil then
		return true
	end
	local okC, c = call("CombatService", "OfPlayer", p)
	if okC and type(c) == "table" and c.Ctx ~= CTX then
		return true
	end
	if not isMember then
		local okV, inVault = call("CharacterService", "InVault", p)
		if okV and inVault == true then
			return true
		end
	end
	return false
end

local function isReady(p: Player): boolean
	local ok, ready = call("PlayerStateService", "IsReady", p)
	if ok and ready == false then
		return false
	end
	return true
end

local function disarm(p: Player)
	local m = members[p]
	if m == nil then
		return
	end
	members[p] = nil
	rebuildMemberList()
	call("CharacterService", "ClearGunVisuals", m.C)
	call("HistoryService", "Untrack", m.C)
	call("CombatService", "Unregister", m.C)
end

local function arm(p: Player, char: Model): boolean
	local combat = Services and Services.CombatService
	if not combat or not ensureContext() then
		return false
	end
	local root, humanoid, head = characterParts(char)
	if root == nil or humanoid == nil or head == nil or humanoid.Health <= 0 then
		return false
	end
	local loadout = loadoutFor(p)
	local ok, c = pcall(combat.NewCombatant, {
		Kind = "Player",
		Player = p,
		Model = char,
		Ctx = CTX,
		Team = PLAYER_TEAM,
		Slot = freeSlot(),
		Name = p.DisplayName,
		Loadout = loadout,
	})
	if not ok or type(c) ~= "table" then
		warn("[RangeService] NewCombatant fehlgeschlagen: " .. tostring(c))
		return false
	end
	local combatant = c :: Types.Combatant
	-- Munition vor der Registrierung setzen (Register sendet Combat("Armed") samt Munition)
	call("WeaponService", "SetLoadout", combatant, loadout)
	local okReg, errReg = pcall(combat.Register, combatant)
	if not okReg then
		warn("[RangeService] Register fehlgeschlagen: " .. tostring(errReg))
		call("CombatService", "Unregister", combatant)
		return false
	end
	members[p] = { C = combatant, Character = char, Since = now(), ReviveAt = nil }
	rebuildMemberList()
	-- Register hat getrackt, die Gruppe "Combatants" gesetzt, BaseSpeed (Walk) und Waffen-Modelle gebaut
	if not greeted[p] then
		greeted[p] = true
		call("PlayerStateService", "Notify", p, "bot.range.enter", nil, "Info")
	end
	return true
end

local function teleportToRange(p: Player): boolean
	local char = p.Character
	local root, humanoid = characterParts(char)
	if char == nil or root == nil or humanoid == nil or humanoid.Health <= 0 then
		return false
	end
	local cf = firingLineCF()
	local ok = call("CharacterService", "Teleport", p, cf)
	if not ok then
		call("AntiCheatService", "NoteTeleport", p, cf)
		char:PivotTo(cf)
	end
	return true
end

-- Waffe anwenden: "Equipped" (in der Range), "Teleported" (gleich da), "Saved" (gemerkt, z. B. im Match).
-- Hinweis: der Server wechselt bei Spielern NIE selbst den ausgerüsteten Platz (der Client würde davon nichts
-- erfahren und seine Schüsse mit der falschen Waffen-Id schicken) – nach dem Tausch hält man wie bei jedem
-- frischen Combat("Armed") die Primärwaffe und wechselt selbst (Taste 1–4).
local function applyWeapon(p: Player, slot: Types.SlotName, key: string): string
	local choice = choices[p]
	if choice == nil then
		choice = {}
		choices[p] = choice
	end
	(choice :: { [string]: string })[slot] = key
	local m = members[p]
	if m then
		local char = p.Character
		if not (m.C.Alive and char and char == m.Character) then
			return "Saved" -- gepoppt: gilt beim nächsten Betreten
		end
		-- a) direkt tauschen: WeaponService.SetLoadout prüft, füllt Munition, baut die Modelle und sendet
		--    Combat("Armed") neu. Vorher auf den Primär-Platz (= Zustand eines frischen "Armed").
		local weapons = Services and Services.WeaponService
		if weapons and type(weapons.SetLoadout) == "function" then
			call("WeaponService", "Equip", m.C, "Primary")
			local okSet = pcall(weapons.SetLoadout, m.C, loadoutFor(p))
			local current: any = m.C.Loadout
			if okSet and type(current) == "table" and current[slot] == key then
				return "Equipped"
			end
		end
		-- b) sonst neu bewaffnen = frischer Combatant mit dem neuen Loadout (Disarmed -> Armed)
		disarm(p)
		if arm(p, char) then
			return "Equipped"
		end
		return "Saved"
	end
	if busyElsewhere(p, false) then
		return "Saved"
	end
	if teleportToRange(p) then
		return "Teleported"
	end
	return "Saved"
end

local function revivePlayer(p: Player, m: Member)
	m.ReviveAt = nil
	local ok = call("CombatService", "Revive", m.C, firingLineCF())
	if not ok then
		-- ohne Revive geht es nicht weiter -> sauber entwaffnen
		disarm(p)
	end
end

-- ---------------------------------------------------------------------
-- TAKTE
-- ---------------------------------------------------------------------
local function scanZone()
	local t = now()
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local m = members[p]
		if m and (char == nil or char ~= m.Character or m.Character.Parent == nil) then
			disarm(p)
			m = nil
		end
		if m then
			local member = m :: Member
			if not member.C.Alive then
				-- gepoppt (Vault): nicht als "verlassen" werten, nach kurzer Zeit an der Schusslinie zurück
				if member.ReviveAt == nil then
					member.ReviveAt = t + PLAYER_REVIVE
				elseif t >= (member.ReviveAt :: number) then
					revivePlayer(p, member)
				end
				if busyElsewhere(p, true) then
					disarm(p)
				end
			else
				local root = characterParts(char)
				if root == nil or busyElsewhere(p, true) or not inZone(root.Position, LEAVE_MARGIN) then
					disarm(p)
				end
			end
		elseif char then
			local root, humanoid = characterParts(char)
			if
				root
				and humanoid
				and humanoid.Health > 0
				and inZone(root.Position, 0)
				and isReady(p)
				and not busyElsewhere(p, false)
			then
				arm(p, char)
			end
		end
	end
end

local function dummyJob()
	local t = now()
	for _, d in dummies do
		local c = d.C
		if c then
			if not c.Alive then
				if d.ReviveAt == nil then
					d.ReviveAt = t + REGEN_AFTER
				elseif t >= (d.ReviveAt :: number) then
					d.ReviveAt = nil
					call("CombatService", "Revive", c, d.Home)
					-- Pose exakt wiederherstellen (Revive/Unpop setzt +3 Y und entankert)
					d.Model:PivotTo(d.Home)
					for _, part in d.Parts do
						part.Anchored = not d.Moving
					end
					if d.Moving then
						d.Root.AssemblyLinearVelocity = Vector3.zero
						d.Dir = 1
						d.FlipAt = t + RAIL_FLIP
						pcall(function()
							d.Root:SetNetworkOwner(nil)
						end)
					end
					if c.Alive and c.Hp < c.MaxHp then
						call("CombatService", "Heal", c, c.MaxHp - c.Hp)
					end
					d.LastHit = t
				end
			elseif c.Hp < c.MaxHp and t - d.LastHit >= REGEN_AFTER then
				call("CombatService", "Heal", c, c.MaxHp - c.Hp)
			end
		end
	end
end

local function railJob()
	local t = now()
	for _, d in dummies do
		local lv = d.Velocity
		if d.Moving and lv then
			local c = d.C
			if d.Root.Anchored or (c and not c.Alive) then
				lv.VectorVelocity = Vector3.zero
			else
				local pos = d.Root.Position
				local home = d.Home.Position
				local offset = pos.Z - home.Z
				-- Wechsel am Ende der Schiene (±Amplitude) oder spätestens nach RailFlip Sekunden
				if offset * d.Dir >= RAIL_AMPLITUDE or t >= d.FlipAt then
					d.Dir = -d.Dir
					d.FlipAt = t + RAIL_FLIP
				end
				-- Abdrift (X/Y) sanft korrigieren, entlang Z fahren
				local vx = math.clamp((home.X - pos.X) * 4, -8, 8)
				local vy = math.clamp((home.Y - pos.Y) * 4, -8, 8)
				lv.VectorVelocity = Vector3.new(vx, vy, d.Dir * RAIL_SPEED)
				-- weit weggedriftet (z. B. Raketen-Stoß) -> zurück auf die Schiene
				if (Vector3.new(pos.X, pos.Y, home.Z) - Vector3.new(home.X, home.Y, home.Z)).Magnitude > 6 then
					d.Model:PivotTo(d.Home)
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- REQUEST "RangeWeapon" {Slot, Key}
-- ---------------------------------------------------------------------
local function onRangeWeapon(p: Player, arg: any): Types.Reply
	if type(arg) ~= "table" then
		return { Ok = false, Message = tr(p, "bot.range.badWeapon") }
	end
	local slot, key = arg.Slot, arg.Key
	if type(slot) ~= "string" or not SLOT_NAMES[slot] then
		return { Ok = false, Message = tr(p, "bot.range.badSlot") }
	end
	if type(key) ~= "string" or #key == 0 or #key > MAX_KEY_LEN then
		return { Ok = false, Message = tr(p, "bot.range.badWeapon") }
	end
	local def = weaponDef(key)
	if def == nil or def.AdminOnly == true then
		return { Ok = false, Message = tr(p, "bot.range.badWeapon") }
	end
	if def.Slot ~= slot then
		return { Ok = false, Message = tr(p, "bot.range.badSlot") }
	end
	if def.Enabled == false then
		return { Ok = false, Message = tr(p, "bot.range.disabled") }
	end
	local result = applyWeapon(p, slot :: Types.SlotName, key)
	if result == "Saved" then
		return { Ok = true, Message = tr(p, "bot.range.saved", Lang.Pick(langOf(p), def.Name)) }
	end
	return { Ok = true, Status = result }
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICHE API (C5.6)
-- ---------------------------------------------------------------------
function RangeService.IsInRange(p: Player): boolean
	return members[p] ~= nil
end

function RangeService.SetWeapon(p: Player, slot: Types.SlotName, key: string)
	if typeof(p) ~= "Instance" or not p:IsA("Player") then
		return
	end
	if type(slot) ~= "string" or not SLOT_NAMES[slot] or not rangeWeaponOk(key, slot) then
		return
	end
	applyWeapon(p, slot, key)
end

function RangeService.Members(): { Player }
	return table.clone(memberList)
end

-- ---------------------------------------------------------------------
-- LEBENSZYKLUS
-- ---------------------------------------------------------------------
local function onPlayerAdded(p: Player)
	if charConns[p] then
		charConns[p]:Disconnect()
	end
	charConns[p] = p.CharacterRemoving:Connect(function()
		disarm(p)
	end)
end

local function onPlayerRemoving(p: Player)
	disarm(p)
	local conn = charConns[p]
	if conn then
		conn:Disconnect()
	end
	charConns[p] = nil
	choices[p] = nil
	greeted[p] = nil
end

function RangeService.Init(services: any)
	Services = services
	local ok, cf, size = call("LobbyBuilder", "RangeZone")
	if ok and typeof(cf) == "CFrame" and typeof(size) == "Vector3" then
		zoneCF = cf
		zoneSize = size
	end
	-- Boden-Oberkante an der Schusslinie messen (die Lobby steht schon). Die Unterkante der Zone (Y −2) ist
	-- NICHT der Boden – sonst landet man beim Teleport mit der Wurzel bei Y 1, die Beine im Boden.
	local east = zoneCF:PointToWorldSpace(Vector3.new(zoneSize.X / 2, 0, 0)).X
	floorY = groundBelow(Vector3.new(math.min(east - 2, FALLBACK_FIRING_X + 2), 0, 0))
	if floorY < -5 or floorY > 5 then
		floorY = 0 -- Boden-Oberkante der Lobby (B2)
	end
	buildDummies()
end

function RangeService.Start()
	if ensureContext() then
		registerDummies()
	end

	call("CombatService", "OnDamage", function(_attacker: any, victim: any, _dealt: any, _info: any)
		if type(victim) == "table" and victim.Ctx == CTX then
			local d = dummyOf[victim]
			if d then
				d.LastHit = now()
			end
		end
	end)
	call("CombatService", "OnElimination", function(victim: any, _killer: any, _info: any)
		if type(victim) ~= "table" or victim.Ctx ~= CTX then
			return
		end
		local d = dummyOf[victim]
		if d then
			d.ReviveAt = now() + REGEN_AFTER
			return
		end
		local p = victim.Player
		local m = if p then members[p] else nil
		if p and m and m.C == victim then
			m.ReviveAt = now() + PLAYER_REVIVE
			call("PlayerStateService", "Notify", p, "bot.range.popped", nil, "Info")
		end
	end)

	call("PlayerStateService", "Handle", "RangeWeapon", onRangeWeapon, { Rate = 4, Per = 1 })

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end

	Scheduler.Every("RangeZone", SCAN_HZ, function()
		if not contextReady and ensureContext() then
			registerDummies()
		end
		scanZone()
	end)
	Scheduler.Every("RangeDummies", 4, dummyJob)
	Scheduler.Every("RangeRails", 10, railJob)
end

return RangeService
