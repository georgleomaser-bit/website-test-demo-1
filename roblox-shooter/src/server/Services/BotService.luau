-- =====================================================================
--  CLUTCH CLASH – Bots (Server/Services/BotService)
--  Besitzer: WP6 (Bots & Training-Range). Vertrag: DESIGN.md C5.6, B10, C17.
--  Ehrliche [BOT]s: graues Namensschild, Tag "Bot", Attribut IsBot = true. Höchstens Config.Server.MaxBots (12)
--  pro Server und MaxBotsPerMatch (7) pro Kontext. Figuren aus dem Pool (Bot/BotRig), Gehirn Bot/BotBrain
--  (10 Hz gestaffelt über Lib/Scheduler, ≤ 3 Raycasts pro Tick), Wege über Bot/Pathfind (A* auf Arena.Nav).
--  Schießen ausschließlich über WeaponService (ServerFire/ServerMelee/ServerThrow/ServerUse).
--
--  Öffentliche API (C5.6):
--    BotService.Budget(): number                         freie Bot-Plätze auf diesem Server
--    BotService.Spawn(difficulty, ctx, team, slot, loadout?): Types.Combatant?
--    BotService.Despawn(c)
--    BotService.SetGoal(c, { Kind = "Engage" | "Zone" | "Idle", Pos = Vector3? })
--    BotService.DifficultyFor(players): string           adaptive Stufe (B10.3, verdeckt)
--    BotService.SetHandicap(c, missShots)                Fehlschüsse pro Runde (OnRoundStart setzt neu)
--    BotService.OnRoundStart(ctx)
--    BotService.RandomName(): string
--  Zusatz (nur Lesen, z. B. Admin-Panel/F8):
--    BotService.Count(ctx?): number                      aktive Bots (gesamt oder im Kontext)
--    BotService.List(): { { Id, Name, Difficulty, Ctx, Team, State } }
--
--  Hinweise:
--    * Spawn braucht den Kontext (CombatService.Context(ctx)) für Arena, Wege und Regeln. Ist er noch nicht
--      registriert, wartet die Figur unsichtbar in ServerStorage und wird beim ersten Tick nach der
--      Registrierung in die Arena gestellt (eine vorherige Teleport-Position bleibt erhalten).
--    * Rookie-Handicap: in den ersten 3 Matches eines Menschen gehen die ersten 2 Schüsse jeder Runde
--      absichtlich daneben (WeaponService.ServerFire mit ForceMiss). Automatisch, wenn ein Rookie-Gegner im
--      Kontext ist; SetHandicap setzt den Wert ausdrücklich (der größere Wert gilt).
--    * Range-Bots (Admin "Bot spawnen") verschwinden 2 s nach dem Pop wieder.
-- =====================================================================

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))
local Util = require(Shared:WaitForChild("Util"))

local ServerRoot = script.Parent.Parent
local Scheduler = require(ServerRoot:WaitForChild("Lib"):WaitForChild("Scheduler"))
local BotFolder = ServerRoot:WaitForChild("Bot")
local BotRig = require(BotFolder:WaitForChild("BotRig"))
local BotBrain = require(BotFolder:WaitForChild("BotBrain"))
local Pathfind = require(BotFolder:WaitForChild("Pathfind"))

local BotService = {}
local Services: any = nil

local BOTS: any = Config.Bots
local SERVER: any = Config.Server
local DIFFS: any = BOTS.Difficulties or {}
local ORDER: { string } = BOTS.Order or { "Rookie", "Easy", "Normal", "Hard", "Insane" }

local RANGE_CTX = "Range"
local RANGE_DESPAWN_DELAY = 2 -- s nach dem Pop
local WAIT_FOR_CONTEXT = 30 -- s: so lange darf ein Bot auf seinen Kontext warten, dann weg
local DEBUG_MAX_POINTS = 24
local DEBUG_REDRAW = 1 -- s
local HOLD_CF = CFrame.new(0, 3, 0)
local FALLBACK_LOADOUT: Types.Loadout =
	{ Primary = "PopRifle", Secondary = "PipPistol", Melee = "BoxingGloves", Utility = "PopGrenade" }
local SLOTS: { Types.SlotName } = { "Primary", "Secondary", "Melee", "Utility" }

type Entry = {
	C: Types.Combatant,
	Model: Model,
	Brain: BotBrain.Brain,
	Difficulty: string,
	Handicap: number?, -- ausdrücklich gesetzt (SetHandicap), Schüsse pro Runde
	Removed: boolean,
	Placed: boolean, -- steht in der Arena (Workspace)
	SpawnedAt: number,
	DespawnAt: number?,
	DebugFolder: Folder?,
	DebugVersion: number,
	DebugAt: number,
}

local entries: { [Types.Combatant]: Entry } = {}
local list: { Entry } = {}
local listDirty = false
local rng = Random.new()
local botsFolder: Folder? = nil
local debugRoot: Folder? = nil

-- ---------------------------------------------------------------------
-- HILFEN
-- ---------------------------------------------------------------------
local function now(): number
	return workspace:GetServerTimeNow()
end

local function num(v: any, default: number): number
	if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then
		return v
	end
	return default
end

local function maxBots(): number
	return math.min(math.floor(num(SERVER.MaxBots, 12)), math.floor(num(BOTS.PoolSize, 12)))
end

local function maxPerMatch(): number
	return math.floor(num(SERVER.MaxBotsPerMatch, 7))
end

local function rebuildList()
	if not listDirty then
		return
	end
	listDirty = false
	local fresh: { Entry } = {}
	for _, entry in entries do
		if not entry.Removed then
			table.insert(fresh, entry)
		end
	end
	list = fresh
end

local function activeCount(ctx: string?): number
	local n = 0
	for _, entry in entries do
		if not entry.Removed and (ctx == nil or entry.C.Ctx == ctx) then
			n += 1
		end
	end
	return n
end

local function service(name: string): any
	return if Services then Services[name] else nil
end

-- Aufruf einer optionalen/fremden Service-Funktion in pcall (nil, wenn nicht vorhanden)
local function call(serviceName: string, fnName: string, ...: any): (boolean, ...any)
	local s = service(serviceName)
	local fn = if s then s[fnName] else nil
	if type(fn) ~= "function" then
		return false, nil
	end
	return pcall(fn, ...)
end

local function contextOf(ctx: string): any
	local ok, info = call("CombatService", "Context", ctx)
	if ok and type(info) == "table" then
		return info
	end
	return nil
end

local function getBotsFolder(): Folder
	local folder = botsFolder
	if folder and folder.Parent == workspace then
		return folder
	end
	local existing = workspace:FindFirstChild("Bots")
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = "Bots"
		folder.Parent = workspace
	end
	botsFolder = folder
	return folder :: Folder
end

local function waitingFolder(): Folder
	local existing = ServerStorage:FindFirstChild("BotWaiting")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "BotWaiting"
	folder.Parent = ServerStorage
	return folder
end

-- Bots einer Match-Arena wohnen im Slot-Ordner (workspace.Arenas.Slot_i, NICHT in der Map -> MapParams
-- treffen sie nicht; ArenaLook versteckt sie mit dem Slot). Range/Crown/sonst: workspace.Bots.
local function parentFor(arena: any): Instance
	local model = if type(arena) == "table" then arena.Model else nil
	if typeof(model) == "Instance" then
		local parent = (model :: Instance).Parent
		if parent and parent ~= workspace and string.match(parent.Name, "^Slot_%d+$") then
			local slot = tonumber(string.match(parent.Name, "%d+")) or 0
			if slot >= 1 then
				return parent
			end
		end
	end
	return getBotsFolder()
end

local function spawnFor(arena: any, team: number, slot: number): CFrame
	if type(arena) == "table" then
		local spawns = arena.Spawns
		if type(spawns) == "table" then
			local listOf: any = if team == 1 then spawns.A elseif team == 2 then spawns.B else spawns.FFA
			if type(listOf) ~= "table" or #listOf == 0 then
				listOf = spawns.FFA
			end
			if type(listOf) == "table" and #listOf > 0 then
				local cf = listOf[((math.max(slot, 1) - 1) % #listOf) + 1]
				if typeof(cf) == "CFrame" then
					return cf + Vector3.new(0, 3, 0)
				end
			end
		end
		if typeof(arena.Origin) == "CFrame" then
			local spread = Vector3.new((slot % 4) * 3 - 4.5, 3, 0)
			return arena.Origin + spread
		end
	end
	return CFrame.new(0, 10, 0)
end

local function validDifficulty(difficulty: any): string
	if type(difficulty) == "string" and DIFFS[difficulty] ~= nil then
		return difficulty
	end
	return "Normal"
end

local function enabledWeapon(key: any, slot: Types.SlotName): boolean
	if type(key) ~= "string" then
		return false
	end
	local ok, def = pcall(Config.Weapon, key)
	if not ok or type(def) ~= "table" then
		return false
	end
	return def.Slot == slot and def.Enabled ~= false and def.AdminOnly ~= true
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

local function sanitizeLoadout(loadout: any): Types.Loadout?
	if type(loadout) ~= "table" then
		return nil
	end
	local fallback: any = defaultLoadout()
	local result: any = {}
	for _, slot in SLOTS do
		local key = loadout[slot]
		result[slot] = if enabledWeapon(key, slot) then key else fallback[slot]
	end
	return result
end

-- Rookie/Easy: Gratis-Set; ab Normal gewichtet zufällig (LoadoutWeights); Mutator-Regeln gehen vor
local function pickLoadout(difficulty: string, rules: any): Types.Loadout
	if type(rules) == "table" and type(rules.ForcedLoadout) == "table" then
		local forced = sanitizeLoadout(rules.ForcedLoadout)
		if forced then
			return forced
		end
	end
	local randomAll = type(rules) == "table" and rules.RandomLoadout == true
	local freeOnly: any = BOTS.FreeOnly or {}
	if freeOnly[difficulty] and not randomAll then
		return defaultLoadout()
	end
	local weapons: any = Config.Weapons
	local all: any = if type(weapons) == "table" then weapons.List else nil
	local weights: any = BOTS.LoadoutWeights or {}
	local result: any = defaultLoadout()
	if type(all) ~= "table" then
		return result
	end
	for _, slot in SLOTS do
		local candidates: { any } = {}
		for _, def in all do
			if type(def) == "table" and def.Slot == slot and enabledWeapon(def.Key, slot) then
				local w = if randomAll then 1 else num(weights[def.Key], 0)
				if w > 0 then
					table.insert(candidates, { Key = def.Key, W = w })
				end
			end
		end
		local picked = Util.WeightedPick(candidates, function(item: any): number
			return item.W
		end, rng)
		if picked then
			result[slot] = picked.Key
		end
	end
	return result
end

-- ---------------------------------------------------------------------
-- MENSCHEN-DATEN (Progression optional über pcall, Fallback DataService)
-- ---------------------------------------------------------------------
local function dataOf(p: Player): any
	local ok, data = call("DataService", "Get", p)
	if ok and type(data) == "table" then
		return data
	end
	return nil
end

local function isRookie(p: Player): boolean
	local ok, result = call("ProgressionService", "IsRookie", p)
	if ok and type(result) == "boolean" then
		return result
	end
	local data = dataOf(p)
	local stats = if data then data.Stats else nil
	local matches = if type(stats) == "table" then num(stats.Matches, 0) else 0
	return matches < num(BOTS.RookieMatches, 3)
end

local function mmrOf(p: Player): number
	local ok, result = call("ProgressionService", "Mmr", p)
	if ok and type(result) == "number" and result == result then
		return result
	end
	local data = dataOf(p)
	return if data then num(data.Mmr, 1000) else 1000
end

local function botTierOf(p: Player): number
	local data = dataOf(p)
	local range = math.floor(num(BOTS.Adaptive and BOTS.Adaptive.Range, 1))
	local tier = if data then math.floor(num(data.BotTier, 0)) else 0
	return math.clamp(tier, -range, range)
end

local function tierIndex(name: string): number
	for i, n in ORDER do
		if n == name then
			return i
		end
	end
	return 3
end

-- Automatischer Rookie-Handicap: ein menschlicher Gegner im Kontext ist in seinen ersten Matches
local function autoHandicap(entry: Entry): number
	local ok, all = call("CombatService", "InCtx", entry.C.Ctx)
	if not ok or type(all) ~= "table" then
		return 0
	end
	for _, o in all do
		if type(o) == "table" and o.Kind == "Player" and o.Player and (o.Team ~= entry.C.Team or o.Team == 0) then
			if isRookie(o.Player) then
				return math.max(0, math.floor(num(BOTS.RookieMissShots, 2)))
			end
		end
	end
	return 0
end

local function handicapFor(entry: Entry): number
	return math.max(entry.Handicap or 0, autoHandicap(entry))
end

-- ---------------------------------------------------------------------
-- NAMENSSCHILD
-- ---------------------------------------------------------------------
local function fallbackNameplate(model: Model, name: string)
	local head = model:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local old = head:FindFirstChild("BotNameplate")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "BotNameplate"
	gui.Size = UDim2.fromOffset(160, 26)
	gui.StudsOffset = Vector3.new(0, 2.4, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = if typeof(BOTS.NameplateColor) == "Color3"
		then BOTS.NameplateColor
		else Color3.fromRGB(190, 190, 200)
	label.TextStrokeTransparency = 0.3
	label.Text = "[BOT] " .. name
	label.Parent = gui
	gui.Parent = head
end

local function setNameplate(model: Model, name: string, difficulty: string, team: number)
	local d = DIFFS[difficulty] or {}
	local levels = d.Level
	local lo = if type(levels) == "table" then math.floor(num(levels[1], 1)) else 1
	local hi = if type(levels) == "table" then math.floor(num(levels[2], lo)) else lo
	local level = rng:NextInteger(math.min(lo, hi), math.max(lo, hi))
	local ok = call("CharacterService", "SetNameplate", model, {
		Name = name,
		Level = level,
		Title = "",
		Team = team,
		IsBot = true,
	})
	if not ok then
		fallbackNameplate(model, name)
	end
end

-- ---------------------------------------------------------------------
-- PFAD-OVERLAY (Admin-Debug "Bot-Wege zeigen" = Config.Debug.BotPaths)
-- ---------------------------------------------------------------------
local function clearDebug(entry: Entry)
	local folder = entry.DebugFolder
	if folder then
		folder:Destroy()
		entry.DebugFolder = nil
	end
	entry.DebugVersion = -1
end

local function drawDebug(entry: Entry, graph: Pathfind.Graph, t: number)
	local debugCfg: any = Config.Debug
	if not (type(debugCfg) == "table" and debugCfg.BotPaths == true) then
		if entry.DebugFolder then
			clearDebug(entry)
		end
		return
	end
	if entry.DebugVersion == entry.Brain.PathVersion and t - entry.DebugAt < DEBUG_REDRAW then
		return
	end
	entry.DebugVersion = entry.Brain.PathVersion
	entry.DebugAt = t
	local root = debugRoot
	if root == nil or root.Parent ~= workspace then
		local folder = Instance.new("Folder")
		folder.Name = "BotPaths"
		folder.Parent = workspace
		debugRoot = folder
		root = folder
	end
	local folder = entry.DebugFolder
	if folder == nil or folder.Parent == nil then
		local f = Instance.new("Folder")
		f.Name = entry.C.Name
		f.Parent = root
		entry.DebugFolder = f
		folder = f
	end
	local points = BotBrain.PathPoints(entry.Brain, graph)
	local parts = (folder :: Folder):GetChildren()
	for i = 1, DEBUG_MAX_POINTS do
		local part = parts[i]
		local point = points[i]
		if point then
			if not (part and part:IsA("BasePart")) then
				local ball = Instance.new("Part")
				ball.Shape = Enum.PartType.Ball
				ball.Size = Vector3.new(0.8, 0.8, 0.8)
				ball.Material = Enum.Material.Neon
				ball.Color = if i == 1 then Color3.fromRGB(255, 220, 50) else Color3.fromRGB(60, 220, 255)
				ball.Anchored = true
				ball.CanCollide = false
				ball.CanQuery = false
				ball.CanTouch = false
				ball.CastShadow = false
				ball.Parent = folder
				part = ball
			end
			(part :: BasePart).Position = point + Vector3.new(0, 0.6, 0)
		elseif part then
			part:Destroy()
		end
	end
end

-- ---------------------------------------------------------------------
-- ENTFERNEN
-- ---------------------------------------------------------------------
local function removeEntry(entry: Entry)
	if entry.Removed then
		return
	end
	entry.Removed = true
	entries[entry.C] = nil
	listDirty = true
	clearDebug(entry)
	local c = entry.C
	call("CharacterService", "ClearGunVisuals", c)
	call("HistoryService", "Untrack", c)
	call("CombatService", "Unregister", c)
	local head = entry.Model:FindFirstChild("Head")
	local plate = if head then head:FindFirstChild("BotNameplate") else nil
	if plate then
		plate:Destroy()
	end
	BotRig.Release(entry.Model)
end

-- In die Arena stellen (sobald der Kontext existiert)
local function place(entry: Entry, info: any)
	local model = entry.Model
	local arena = info.Arena
	if (model:GetPivot().Position - HOLD_CF.Position).Magnitude < 1 then
		model:PivotTo(spawnFor(arena, entry.C.Team, entry.C.Slot))
	end
	model.Parent = parentFor(arena)
	BotRig.Activate(model)
	entry.Placed = true
end

-- ---------------------------------------------------------------------
-- TAKT
-- ---------------------------------------------------------------------
local function tick(entry: Entry, dt: number)
	if entry.Removed then
		return
	end
	local c = entry.C
	local model = entry.Model
	if model.Parent == nil or model:FindFirstChild("HumanoidRootPart") == nil then
		removeEntry(entry)
		return
	end
	local info = contextOf(c.Ctx)
	if info == nil then
		if entry.Placed then
			-- Kontext ist weg (Match vorbei, ohne Despawn) -> aufräumen
			removeEntry(entry)
		end
		return
	end
	if not entry.Placed then
		place(entry, info)
	end
	local arena = info.Arena
	local graph = Pathfind.ForArena(arena)
	local params: RaycastParams? = nil
	if type(arena) == "table" and typeof(arena.MapParams) == "RaycastParams" then
		params = arena.MapParams
	end
	local t = now()
	BotBrain.Tick(entry.Brain, dt, {
		Services = Services,
		Now = t,
		Info = info,
		Graph = graph,
		Params = params,
	})
	drawDebug(entry, graph, t)
end

local function housekeeping()
	local t = now()
	for _, entry in list do
		if not entry.Removed then
			if entry.DespawnAt and t >= entry.DespawnAt then
				removeEntry(entry)
			elseif not entry.Placed and t - entry.SpawnedAt > WAIT_FOR_CONTEXT then
				warn("[BotService] Kontext " .. tostring(entry.C.Ctx) .. " kam nie – Bot entfernt")
				removeEntry(entry)
			end
		end
	end
	local debugCfg: any = Config.Debug
	if debugRoot and not (type(debugCfg) == "table" and debugCfg.BotPaths == true) then
		debugRoot:Destroy()
		debugRoot = nil
	end
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICHE API (C5.6)
-- ---------------------------------------------------------------------
function BotService.Budget(): number
	return math.max(0, maxBots() - activeCount(nil))
end

function BotService.RandomName(): string
	local names: { string } = BOTS.Names or {}
	if #names == 0 then
		return "Bot"
	end
	local used: { [string]: boolean } = {}
	for _, entry in entries do
		if not entry.Removed then
			used[entry.C.Name] = true
		end
	end
	local freeNames: { string } = {}
	for _, n in names do
		if not used[n] then
			table.insert(freeNames, n)
		end
	end
	local pool = if #freeNames > 0 then freeNames else names
	return pool[rng:NextInteger(1, #pool)]
end

function BotService.Spawn(
	difficulty: string,
	ctx: string,
	team: number,
	slot: number,
	loadout: Types.Loadout?
): Types.Combatant?
	if type(ctx) ~= "string" or ctx == "" then
		return nil
	end
	local combat = service("CombatService")
	if not combat then
		return nil
	end
	team = math.floor(num(team, 2))
	slot = math.clamp(math.floor(num(slot, 1)), 1, 255)
	local diffName = validDifficulty(difficulty)
	if BotService.Budget() <= 0 then
		return nil
	end
	if activeCount(ctx) >= maxPerMatch() then
		return nil
	end
	local model = BotRig.Acquire(rng)
	if model == nil then
		return nil
	end
	local info = contextOf(ctx)
	local rules = if info then info.Rules else nil
	local chosen = sanitizeLoadout(loadout) or pickLoadout(diffName, rules)
	local name = BotService.RandomName()

	model.Name = "Bot_" .. name
	model:SetAttribute("IsBot", true)
	model:SetAttribute("Difficulty", diffName)
	model:SetAttribute("BotName", name)
	model:SetAttribute("Ctx", ctx)
	model:SetAttribute("Team", team)
	model:SetAttribute("Alive", true)
	CollectionService:AddTag(model, "Bot")
	if info then
		model:PivotTo(spawnFor(info.Arena, team, slot))
		model.Parent = parentFor(info.Arena)
		BotRig.Activate(model)
	else
		model:PivotTo(HOLD_CF)
		model.Parent = waitingFolder()
	end

	local okNew, c = pcall(combat.NewCombatant, {
		Kind = "Bot",
		Player = nil,
		Model = model,
		Ctx = ctx,
		Team = team,
		Slot = slot,
		Name = name,
		Loadout = chosen,
		Difficulty = diffName,
	})
	if not okNew or type(c) ~= "table" then
		warn("[BotService] NewCombatant fehlgeschlagen: " .. tostring(c))
		BotRig.Release(model)
		return nil
	end
	local combatant = c :: Types.Combatant
	combatant.Difficulty = diffName
	-- Munition vor der Registrierung (Register sendet den Zustand), dann eintragen
	call("WeaponService", "SetLoadout", combatant, chosen)
	local okReg, errReg = pcall(combat.Register, combatant)
	if not okReg then
		warn("[BotService] Register fehlgeschlagen: " .. tostring(errReg))
		call("CombatService", "Unregister", combatant)
		BotRig.Release(model)
		return nil
	end
	-- Register hat schon getrackt (HistoryService), die Gruppe "Bots" gesetzt und die Waffen-Modelle gebaut
	setNameplate(model, name, diffName, team)
	local d = DIFFS[diffName] or {}
	local ruleSpeed = if type(rules) == "table" then num(rules.SpeedMult, 1) else 1
	call("CharacterService", "SetBaseSpeed", combatant, num(Config.Player.Walk, 16) * num(d.SpeedMult, 1) * ruleSpeed)
	call("WeaponService", "Equip", combatant, "Primary")

	local t = now()
	local entry: Entry = {
		C = combatant,
		Model = model,
		Brain = BotBrain.new(combatant, diffName, Random.new(rng:NextInteger(1, 2 ^ 30))),
		Difficulty = diffName,
		Handicap = nil,
		Removed = false,
		Placed = info ~= nil,
		SpawnedAt = t,
		DespawnAt = nil,
		DebugFolder = nil,
		DebugVersion = -1,
		DebugAt = 0,
	}
	BotBrain.Reset(entry.Brain, t)
	entries[combatant] = entry
	listDirty = true
	BotBrain.SetMisses(entry.Brain, handicapFor(entry))
	return combatant
end

function BotService.Despawn(c: Types.Combatant)
	if type(c) ~= "table" then
		return
	end
	local entry = entries[c]
	if entry then
		removeEntry(entry)
	end
end

function BotService.SetGoal(c: Types.Combatant, goal: { Kind: string, Pos: Vector3? })
	local entry = if type(c) == "table" then entries[c] else nil
	if entry and not entry.Removed then
		BotBrain.SetGoal(entry.Brain, goal)
	end
end

function BotService.SetHandicap(c: Types.Combatant, missShots: number)
	local entry = if type(c) == "table" then entries[c] else nil
	if entry and not entry.Removed then
		entry.Handicap = math.max(0, math.floor(num(missShots, 0)))
		BotBrain.SetMisses(entry.Brain, handicapFor(entry))
	end
end

function BotService.OnRoundStart(ctx: string)
	local t = now()
	rebuildList()
	for _, entry in list do
		if not entry.Removed and entry.C.Ctx == ctx then
			BotBrain.Reset(entry.Brain, t)
			BotBrain.SetGoal(entry.Brain, { Kind = "Engage" })
			BotBrain.SetMisses(entry.Brain, handicapFor(entry))
		end
	end
end

-- B10.3 adaptiv (verdeckt): Rookie solange Stats.Matches < 3; sonst nach MMR (< 900 Easy, 900–1150 Normal,
-- > 1150 Hard) ± Data.BotTier (−1..+1, mind. Easy). Team: Durchschnitt. Insane nie adaptiv.
function BotService.DifficultyFor(players: { Player }): string
	if type(players) ~= "table" or #players == 0 then
		return "Normal"
	end
	local tiers: any = BOTS.MmrTiers or {}
	local easyBelow = num(tiers.Easy, 900)
	local hardAbove = num(tiers.Hard, 1150)
	local sum, count = 0, 0
	for _, p in players do
		if typeof(p) == "Instance" and p:IsA("Player") then
			local idx
			if isRookie(p) then
				idx = tierIndex("Rookie")
			else
				local mmr = mmrOf(p)
				local base = if mmr < easyBelow then "Easy" elseif mmr <= hardAbove then "Normal" else "Hard"
				idx = math.clamp(tierIndex(base) + botTierOf(p), tierIndex("Easy"), tierIndex("Hard"))
			end
			sum += idx
			count += 1
		end
	end
	if count == 0 then
		return "Normal"
	end
	local idx = math.clamp(math.floor(sum / count + 0.5), 1, tierIndex("Hard"))
	return ORDER[idx] or "Normal"
end

function BotService.Count(ctx: string?): number
	return activeCount(ctx)
end

function BotService.List(): { { [string]: any } }
	local result: { { [string]: any } } = {}
	for _, entry in entries do
		if not entry.Removed then
			table.insert(result, {
				Id = entry.C.Id,
				Name = entry.C.Name,
				Difficulty = entry.Difficulty,
				Ctx = entry.C.Ctx,
				Team = entry.C.Team,
				State = entry.Brain.State,
			})
		end
	end
	return result
end

-- ---------------------------------------------------------------------
-- LEBENSZYKLUS
-- ---------------------------------------------------------------------
function BotService.Init(services: any)
	Services = services
end

function BotService.Start()
	BotRig.Start()

	-- Signale aus dem Kampf (WP3) – optional, ohne sie kämpfen Bots trotzdem
	call("CombatService", "OnElimination", function(victim: any, _killer: any, _info: any)
		local entry = if type(victim) == "table" then entries[victim] else nil
		if entry and not entry.Removed and victim.Ctx == RANGE_CTX then
			entry.DespawnAt = now() + RANGE_DESPAWN_DELAY
		end
	end)
	call("CombatService", "OnDamage", function(attacker: any, victim: any, _dealt: any, _info: any)
		local entry = if type(victim) == "table" then entries[victim] else nil
		if entry and not entry.Removed then
			BotBrain.Hurt(entry.Brain, if type(attacker) == "table" then attacker else nil, now())
		end
	end)
	call("WeaponService", "OnShot", function(shooter: any, _def: any, _hits: any, _heads: any)
		if type(shooter) ~= "table" or shooter.Root == nil then
			return
		end
		local hear = num(BOTS.HearRange, 80)
		local pos = shooter.Root.Position
		local t = now()
		for _, entry in list do
			local c = entry.C
			if not entry.Removed and c ~= shooter and c.Ctx == shooter.Ctx and c.Alive and c.Root then
				if (c.Root.Position - pos).Magnitude <= hear and (shooter.Team ~= c.Team or c.Team == 0) then
					BotBrain.Hear(entry.Brain, pos, t)
				end
			end
		end
	end)

	Scheduler.Staggered("Bots", math.max(1, num(BOTS.TickHz, 10)), function()
		rebuildList()
		return list
	end, tick)
	Scheduler.Every("BotsHousekeeping", 1, function()
		rebuildList()
		housekeeping()
	end)
	-- Spieler-bezogene Tabellen gibt es hier nicht (Bots gehören keinem Spieler) -> kein PlayerRemoving nötig.
end

return BotService
