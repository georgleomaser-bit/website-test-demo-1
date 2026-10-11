-- =====================================================================
--  CLUTCH CLASH – Arena-Plätze (Server/Services/ArenaService)
--  Besitzer: WP2 (Welt). Vertrag: DESIGN.md B9 (Slot-System), B8.1 (Templates, Nav-Graph,
--  Spawn-Prüfung), C12.6 (Kollisionsgruppen), C5.3 (API).
--
--  Init (läuft VOR LobbyBuilder, nach GraphicsService):
--    1) Kollisionsgruppen registrieren (ZUERST, vor jedem Map-Bau)
--    2) workspace.Arenas: Slot_1..Slot_8 (Folder, Attribute State/BuildId/MapKey) + Vault je Slot
--    3) jede Arena-Map einmal als Template: bauen -> Staging (0,3000,0) im Workspace (Nav-Graph,
--       Spawn-Prüfung) -> ServerStorage.MapTemplates (nicht repliziert)
--    4) Crown Ring (Slot 0) fest an Config.Maps.CrownOrigin (workspace.Arenas.Crown)
--  Start: Aufräumen über den Scheduler (alle Config.Server.CleanupEvery = 30 s).
--
--  Öffentliche API (C5.3):
--    ArenaService.Acquire(mapKey, mood?): Types.Arena?   Slot 1..8, warm bevorzugt (B9.2); alle belegt -> nil
--    ArenaService.Release(arena)                          Slot wird Free, Map bleibt (warm)
--    ArenaService.FreeSlots(): number
--    ArenaService.Crown(): Types.Arena                    fester Slot 0
--    ArenaService.Range(): Types.Arena                    Lobby-Range als Arena (Slot −1, Spawns leer, Vault ungenutzt)
--    ArenaService.MapsFor(modeKey, teamSize): { string }  sortiert; FFA ignoriert teamSize
--    ArenaService.LobbySpawn(): CFrame                    zufälliger Lobby-Spawn (Blick zur Duell-Halle)
--    ArenaService.Layout(mapKey): Types.MapLayout?
--    ArenaService.SlotStates(): { { Slot, State, MapKey? } }
--  WP2-intern (WorldTests/Debug):
--    ArenaService.Template(mapKey): { Model, Nav, Info, Report }?
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Config = require(Shared:WaitForChild("Config"))

local ServerRoot = script.Parent.Parent
local Scheduler = require(ServerRoot:WaitForChild("Lib"):WaitForChild("Scheduler"))
local World = ServerRoot:WaitForChild("World")
local MapKit = require(World:WaitForChild("MapKit"))
local NavBuilder = require(World:WaitForChild("NavBuilder"))
local LobbyLayout = require(World:WaitForChild("LobbyLayout"))

local ArenaService = {}

type SlotState = {
	Slot: number,
	Folder: Folder,
	Origin: CFrame,
	Vault: CFrame,
	State: string, -- "Free" | "Loading" | "Busy"
	MapKey: string?,
	Map: Model?,
	Arena: Types.Arena?,
	LastUsed: number,
}

export type Template = {
	Key: string,
	Model: Model,
	Nav: Types.NavGraph,
	Info: MapKit.BuildInfo,
	Report: NavBuilder.Report?,
}

-- Kollisionsgruppen (C12.6) und Paare, die NICHT kollidieren
local GROUPS = { "LobbyPlayers", "Combatants", "Bots", "Ghost", "ArenaBarrier", "FX" }
local NO_COLLIDE = {
	{ "LobbyPlayers", "LobbyPlayers" },
	{ "LobbyPlayers", "Combatants" },
	{ "LobbyPlayers", "Bots" },
	{ "LobbyPlayers", "Ghost" },
	{ "LobbyPlayers", "FX" },
	{ "Combatants", "Ghost" },
	{ "Combatants", "FX" },
	{ "Bots", "Ghost" },
	{ "Bots", "FX" },
}
-- Ghost und FX kollidieren mit gar nichts
local NOTHING_GROUPS = { "Ghost", "FX" }
local ALL_GROUPS = { "Default", "LobbyPlayers", "Combatants", "Bots", "Ghost", "ArenaBarrier", "FX" }

local VAULT_SIZE = Vector3.new(20, 10, 20)
local SPAWN_BOX = Vector3.new(1.98, 5, 1.98) -- B8: Box 2×5×2 über jedem Spawn (minimal kleiner: berührende Flächen zählen nicht)
local MAX_SLOTS = 8 -- Koordinaten-Formel B9.1 kennt 8 Plätze

local layouts: { [string]: Types.MapLayout } = {}
local templates: { [string]: Template } = {}
local slots: { SlotState } = {}
local crownArena: Types.Arena? = nil
local rangeArena: Types.Arena? = nil
local arenasFolder: Folder? = nil
local templatesFolder: Folder? = nil
local buildCounter = 0
local rng = Random.new()
local stopCleanup: (() -> ())? = nil

-- ---------------------------------------------------------------------
-- Hilfen
-- ---------------------------------------------------------------------
local function server(): { [string]: any }
	return Config.Server or {}
end

local function num(value: any, default: number): number
	local n = tonumber(value)
	if n == nil or n ~= n then
		return default
	end
	return n
end

local function defaultKillY(): number
	return num(Config.Maps.DefaultKillY, num(Config.Player and Config.Player.KillY, -40))
end

local function defaultZoneRadius(): number
	local modes = Config.Modes
	local match = modes and modes.Match
	return num(match and match.ZoneRadius, 8)
end

local function slotCount(): number
	return math.clamp(math.floor(num(server().ArenaSlots, MAX_SLOTS)), 1, MAX_SLOTS)
end

-- B9.1: X = ((i−1) % 4 − 1.5) × 4000 -> {−6000, −2000, 2000, 6000}; Z = (i ≤ 4) and −4000 or 4000; Y = 0
local function slotOrigin(i: number): CFrame
	local spacing = num(server().SlotSpacing, 4000)
	local rowZ = num(server().SlotRowZ, 4000)
	local x = (((i - 1) % 4) - 1.5) * spacing
	local z = if i <= 4 then -rowZ else rowZ
	return CFrame.new(x, 0, z)
end

local function setFolderState(slot: SlotState)
	slot.Folder:SetAttribute("State", slot.State)
	slot.Folder:SetAttribute("MapKey", slot.MapKey or "")
	slot.Folder:SetAttribute("BuildId", if slot.Arena then slot.Arena.BuildId else 0)
end

-- ---------------------------------------------------------------------
-- 1) Kollisionsgruppen (C12.6) – ZUERST
-- ---------------------------------------------------------------------
local function registerCollisionGroups()
	for _, name in ipairs(GROUPS) do
		local ok, err = pcall(function()
			if not workspace:IsCollisionGroupRegistered(name) then
				workspace:RegisterCollisionGroup(name)
			end
		end)
		if not ok then
			warn("[ArenaService] Kollisionsgruppe " .. name .. " nicht registriert: " .. tostring(err))
		end
	end
	local function off(a: string, b: string)
		local ok, err = pcall(function()
			workspace:CollisionGroupSetCollidable(a, b, false)
		end)
		if not ok then
			warn(("[ArenaService] Kollision %s/%s: %s"):format(a, b, tostring(err)))
		end
	end
	for _, pair in ipairs(NO_COLLIDE) do
		off(pair[1], pair[2])
	end
	for _, group in ipairs(NOTHING_GROUPS) do
		for _, other in ipairs(ALL_GROUPS) do
			off(group, other)
		end
	end
end

-- ---------------------------------------------------------------------
-- 2) Layouts laden (World/Maps/<Key>.luau)
-- ---------------------------------------------------------------------
local function loadLayouts()
	local mapsFolder = World:WaitForChild("Maps")
	local defs = Config.Maps.Maps or {}
	for key in pairs(defs) do
		local module = mapsFolder:FindFirstChild(key)
		if not module or not module:IsA("ModuleScript") then
			warn("[ArenaService] Map-Datei fehlt: World/Maps/" .. key)
			continue
		end
		local ok, layout = pcall(require, module)
		if not ok or type(layout) ~= "table" then
			warn("[ArenaService] Map " .. key .. " konnte nicht geladen werden: " .. tostring(layout))
			continue
		end
		if layout.Key ~= key then
			warn(("[ArenaService] Map-Datei %s hat Key %s"):format(key, tostring(layout.Key)))
		end
		layouts[key] = layout
	end
end

-- ---------------------------------------------------------------------
-- 3) Ordner, Slots, Vaults
-- ---------------------------------------------------------------------
-- Geschlossene Box 20×10×20 (Gruppe Ghost), Mitte = Vault-CFrame
local function buildVault(parent: Instance, center: Vector3): CFrame
	local model = Instance.new("Model")
	model.Name = "Vault"
	local half = VAULT_SIZE / 2
	local t = 1
	local pieces = {
		{ Vector3.new(0, -half.Y - t / 2, 0), Vector3.new(VAULT_SIZE.X + 2 * t, t, VAULT_SIZE.Z + 2 * t) },
		{ Vector3.new(0, half.Y + t / 2, 0), Vector3.new(VAULT_SIZE.X + 2 * t, t, VAULT_SIZE.Z + 2 * t) },
		{ Vector3.new(-half.X - t / 2, 0, 0), Vector3.new(t, VAULT_SIZE.Y, VAULT_SIZE.Z + 2 * t) },
		{ Vector3.new(half.X + t / 2, 0, 0), Vector3.new(t, VAULT_SIZE.Y, VAULT_SIZE.Z + 2 * t) },
		{ Vector3.new(0, 0, -half.Z - t / 2), Vector3.new(VAULT_SIZE.X, VAULT_SIZE.Y, t) },
		{ Vector3.new(0, 0, half.Z + t / 2), Vector3.new(VAULT_SIZE.X, VAULT_SIZE.Y, t) },
	}
	for _, piece in ipairs(pieces) do
		local p = MapKit.part({
			Name = "VaultWall",
			CFrame = CFrame.new(center + piece[1]),
			Size = piece[2],
			Color = MapKit.Color("Charcoal"),
			CanQuery = false,
			CastShadow = false,
		})
		p.CollisionGroup = "Ghost"
		p.Parent = model
	end
	model.Parent = parent
	return CFrame.new(center)
end

local function setupFolders()
	local old = workspace:FindFirstChild("Arenas")
	if old then
		old:Destroy()
	end
	local arenas = Instance.new("Folder")
	arenas.Name = "Arenas"
	local depth = num(server().VaultDepth, 250)
	for i = 1, slotCount() do
		local origin = slotOrigin(i)
		local f = Instance.new("Folder")
		f.Name = "Slot_" .. i
		f:SetAttribute("Slot", i)
		local vault = buildVault(f, origin.Position + Vector3.new(0, -depth, 0))
		local slot: SlotState = {
			Slot = i,
			Folder = f,
			Origin = origin,
			Vault = vault,
			State = "Free",
			MapKey = nil,
			Map = nil,
			Arena = nil,
			LastUsed = 0,
		}
		setFolderState(slot)
		f.Parent = arenas
		slots[i] = slot
	end
	arenas.Parent = workspace
	arenasFolder = arenas

	local oldTemplates = ServerStorage:FindFirstChild("MapTemplates")
	if oldTemplates then
		oldTemplates:Destroy()
	end
	local tf = Instance.new("Folder")
	tf.Name = "MapTemplates"
	tf.Parent = ServerStorage
	templatesFolder = tf
end

-- ---------------------------------------------------------------------
-- 4) Arena-Objekt
-- ---------------------------------------------------------------------
local function worldCFrames(origin: CFrame, list: { CFrame }): { CFrame }
	local out: { CFrame } = table.create(#list)
	for _, cf in ipairs(list) do
		table.insert(out, origin * cf)
	end
	return out
end

local function mapParams(model: Instance): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.IncludeInstances = { model }
	return params
end

local function makeArena(
	slot: number,
	key: string,
	buildId: number,
	model: Model,
	origin: CFrame,
	vault: CFrame,
	nav: Types.NavGraph,
	layout: Types.MapLayout
): Types.Arena
	local a, b, ffa = MapKit.SpawnCFrames(layout)
	return {
		Slot = slot,
		Key = key,
		BuildId = buildId,
		Model = model,
		Origin = origin,
		Spawns = { A = worldCFrames(origin, a), B = worldCFrames(origin, b), FFA = worldCFrames(origin, ffa) },
		Zone = origin:PointToWorldSpace(layout.Zone),
		ZoneRadius = layout.ZoneRadius or defaultZoneRadius(),
		KillY = origin.Y + (layout.KillY or defaultKillY()),
		Vault = vault,
		Nav = nav,
		MapParams = mapParams(model),
	}
end

-- ---------------------------------------------------------------------
-- 5) Templates (Staging -> Nav + Spawn-Prüfung -> ServerStorage)
-- ---------------------------------------------------------------------
local function buildTemplate(key: string, layout: Types.MapLayout): Template?
	local ok, model, info = pcall(MapKit.Build, layout)
	if not ok then
		warn("[ArenaService] Map " .. key .. " konnte nicht gebaut werden: " .. tostring(model))
		return nil
	end
	local staging = CFrame.new(Config.Maps.StagingOrigin or Vector3.new(0, 3000, 0))
	model:PivotTo(staging)
	model.Parent = workspace
	local nav: Types.NavGraph = { Nodes = {}, Edges = {} }
	local report: NavBuilder.Report? = nil
	local okNav, navResult, navReport = pcall(NavBuilder.Build, model, layout, staging)
	if okNav then
		nav = navResult
		report = navReport
	else
		warn("[ArenaService] Nav-Graph " .. key .. " fehlgeschlagen: " .. tostring(navResult))
	end
	local blocked = NavBuilder.SpawnBlockers(model, layout, staging, SPAWN_BOX)
	if #blocked > 0 then
		warn(("[ArenaService] %s: Spawns blockiert: %s"):format(key, table.concat(blocked, ", ")))
	end
	model.Parent = templatesFolder
	model:PivotTo(CFrame.new())
	model.Name = key
	return { Key = key, Model = model, Nav = nav, Info = info, Report = report }
end

local function buildTemplates()
	local keys: { string } = {}
	for key in pairs(layouts) do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local def = Config.Maps.Maps[key]
		if def and not def.Fixed then
			local template = buildTemplate(key, layouts[key])
			if template then
				templates[key] = template
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- 6) Crown Ring (Slot 0) fest in der Lobby
-- ---------------------------------------------------------------------
local function emptyArena(slot: number, key: string, origin: CFrame, vault: CFrame): Types.Arena
	local model = Instance.new("Model")
	model.Name = "Map"
	return {
		Slot = slot,
		Key = key,
		BuildId = 0,
		Model = model,
		Origin = origin,
		Spawns = { A = {}, B = {}, FFA = {} },
		Zone = origin.Position,
		ZoneRadius = 0,
		KillY = origin.Y + defaultKillY(),
		Vault = vault,
		Nav = { Nodes = {}, Edges = {} },
		MapParams = mapParams(model),
	}
end

local function buildCrown()
	local origin = CFrame.new(Config.Maps.CrownOrigin or Vector3.new(95, -6, 0))
	local depth = num(server().VaultDepth, 250)
	local crownFolder = Instance.new("Folder")
	crownFolder.Name = "Crown"
	crownFolder:SetAttribute("Slot", 0)
	crownFolder:SetAttribute("State", "Busy")
	crownFolder:SetAttribute("MapKey", "CrownRing")
	crownFolder:SetAttribute("BuildId", 0)
	local vault = buildVault(crownFolder, Vector3.new(origin.X, -depth, origin.Z))
	crownFolder.Parent = arenasFolder

	local layout = layouts.CrownRing
	if not layout then
		warn("[ArenaService] Crown Ring: Map-Datei fehlt – Crown-Modus ohne Arena")
		crownArena = emptyArena(0, "CrownRing", origin, vault)
		return
	end
	local ok, model, crownInfo = pcall(MapKit.Build, layout)
	if not ok then
		warn("[ArenaService] Crown Ring konnte nicht gebaut werden: " .. tostring(model))
		crownArena = emptyArena(0, "CrownRing", origin, vault)
		return
	end
	model:PivotTo(origin)
	model:SetAttribute("BuildId", 0)
	model.Parent = crownFolder -- EINMAL parenten
	local nav: Types.NavGraph = { Nodes = {}, Edges = {} }
	local okNav, navResult, navReport = pcall(NavBuilder.Build, model, layout, origin)
	if okNav then
		nav = navResult
		model:SetAttribute("NavNodes", navReport.Nodes)
	else
		warn("[ArenaService] Nav-Graph CrownRing fehlgeschlagen: " .. tostring(navResult))
	end
	model:SetAttribute("PartCount", crownInfo.Parts)
	local blocked = NavBuilder.SpawnBlockers(model, layout, origin, SPAWN_BOX)
	if #blocked > 0 then
		warn("[ArenaService] CrownRing: Spawns blockiert: " .. table.concat(blocked, ", "))
	end
	crownArena = makeArena(0, "CrownRing", 0, model, origin, vault, nav, layout)
end

-- ---------------------------------------------------------------------
-- 7) Slot leeren / Aufräumen
-- ---------------------------------------------------------------------
local function clearSlot(slot: SlotState)
	local map = slot.Map
	slot.Map = nil
	slot.MapKey = nil
	slot.Arena = nil
	if map then
		map:Destroy()
	end
	setFolderState(slot)
end

-- Freie Slots mit Map, länger als IdleMapSeconds ungenutzt, werden geleert, solange mehr als
-- KeepWarmMaps warme freie Slots existieren (älteste zuerst).
local function cleanup()
	local warm: { SlotState } = {}
	for _, slot in ipairs(slots) do
		if slot.State == "Free" and slot.Map ~= nil then
			table.insert(warm, slot)
		end
	end
	local keep = math.max(0, math.floor(num(server().KeepWarmMaps, 3)))
	if #warm <= keep then
		return
	end
	table.sort(warm, function(a, b)
		return a.LastUsed < b.LastUsed
	end)
	local idle = num(server().IdleMapSeconds, 180)
	local now = os.clock()
	local excess = #warm - keep
	for _, slot in ipairs(warm) do
		if excess <= 0 then
			break
		end
		if now - slot.LastUsed >= idle then
			clearSlot(slot)
			excess -= 1
		end
	end
end

-- ---------------------------------------------------------------------
-- Öffentliche API (C5.3)
-- ---------------------------------------------------------------------
-- B9.2: (1) freier Slot mit genau dieser Map -> sofort; (2) freier Slot ohne Map; (3) am längsten
-- unbenutzter freier Slot -> alte Map zerstören. Klonen, PivotTo, BuildId VOR dem Parenten, EINMAL parenten.
function ArenaService.Acquire(mapKey: string, mood: string?): Types.Arena?
	if type(mapKey) ~= "string" then
		return nil
	end
	local template = templates[mapKey]
	local layout = layouts[mapKey]
	if not template or not layout then
		warn("[ArenaService] Acquire: unbekannte oder feste Map " .. tostring(mapKey))
		return nil
	end
	local warmSlot: SlotState? = nil
	local emptySlot: SlotState? = nil
	local oldestSlot: SlotState? = nil
	for _, slot in ipairs(slots) do
		if slot.State == "Free" then
			if slot.MapKey == mapKey and slot.Arena ~= nil and slot.Map ~= nil and slot.Map.Parent ~= nil then
				if warmSlot == nil or slot.LastUsed > (warmSlot :: SlotState).LastUsed then
					warmSlot = slot
				end
			elseif slot.Map == nil then
				if emptySlot == nil then
					emptySlot = slot
				end
			elseif oldestSlot == nil or slot.LastUsed < (oldestSlot :: SlotState).LastUsed then
				oldestSlot = slot
			end
		end
	end

	local chosen = warmSlot or emptySlot or oldestSlot
	if chosen == nil then
		return nil -- alle belegt -> Warteschlange hält (B3.1)
	end
	local slot = chosen :: SlotState
	local moodKey = if type(mood) == "string" then mood else ""
	if slot == warmSlot and slot.Arena then
		slot.State = "Busy"
		slot.LastUsed = os.clock()
		slot.Folder:SetAttribute("Mood", moodKey)
		setFolderState(slot)
		return slot.Arena
	end

	if slot.Map then
		clearSlot(slot)
	end
	slot.State = "Loading"
	setFolderState(slot)
	buildCounter += 1
	local clone = template.Model:Clone()
	clone.Name = "Map"
	clone:PivotTo(slot.Origin)
	clone:SetAttribute("BuildId", buildCounter)
	clone:SetAttribute("MapKey", mapKey)
	local arena = makeArena(slot.Slot, mapKey, buildCounter, clone, slot.Origin, slot.Vault, template.Nav, layout)
	slot.Map = clone
	slot.MapKey = mapKey
	slot.Arena = arena
	slot.Folder:SetAttribute("BuildId", buildCounter)
	slot.Folder:SetAttribute("MapKey", mapKey)
	slot.Folder:SetAttribute("Mood", moodKey)
	clone.Parent = slot.Folder -- EINMAL parenten
	slot.State = "Busy"
	slot.LastUsed = os.clock()
	setFolderState(slot)
	return arena
end

function ArenaService.Release(arena: Types.Arena)
	if type(arena) ~= "table" then
		return
	end
	local slot = slots[arena.Slot]
	if not slot or slot.Arena ~= arena then
		return -- Crown/Range oder schon ersetzt: nichts zu tun
	end
	slot.State = "Free"
	slot.LastUsed = os.clock()
	setFolderState(slot)
end

function ArenaService.FreeSlots(): number
	local count = 0
	for _, slot in ipairs(slots) do
		if slot.State == "Free" then
			count += 1
		end
	end
	return count
end

function ArenaService.Crown(): Types.Arena
	if crownArena == nil then
		local origin = CFrame.new(Config.Maps.CrownOrigin or Vector3.new(95, -6, 0))
		crownArena = emptyArena(0, "CrownRing", origin, CFrame.new(origin.X, -250, origin.Z))
	end
	return crownArena :: Types.Arena
end

function ArenaService.Range(): Types.Arena
	local cached = rangeArena
	if cached and cached.Model.Parent ~= nil then
		return cached
	end
	local r = LobbyLayout.Range
	local center = (r.ZoneMin + r.ZoneMax) / 2
	local origin = CFrame.new(center.X, 0, center.Z)
	local vault = CFrame.new(center.X, -num(server().VaultDepth, 250), center.Z)
	local lobby = workspace:FindFirstChild(LobbyLayout.FolderName)
	local model = lobby and lobby:FindFirstChild(LobbyLayout.RangeName)
	if not model or not model:IsA("Model") then
		-- Lobby noch nicht gebaut: vorläufiges Objekt (nicht gecacht)
		return emptyArena(-1, "Range", origin, vault)
	end
	local arena = emptyArena(-1, "Range", origin, vault)
	arena.Model = model
	arena.MapParams = mapParams(model)
	rangeArena = arena
	return arena
end

function ArenaService.MapsFor(modeKey: string, teamSize: number): { string }
	local out: { string } = {}
	if type(modeKey) ~= "string" then
		return out
	end
	local size = tonumber(teamSize) or 0
	for key, def in pairs(Config.Maps.Maps or {}) do
		if type(def.Modes) == "table" and table.find(def.Modes, modeKey) then
			local sizeOk = modeKey == "FFA" or size <= 0 or table.find(def.TeamSizes or {}, size) ~= nil
			local available = if def.Fixed then crownArena ~= nil and key == "CrownRing" else templates[key] ~= nil
			if sizeOk and available then
				table.insert(out, key)
			end
		end
	end
	table.sort(out)
	return out
end

function ArenaService.LobbySpawn(): CFrame
	local spawns = LobbyLayout.Spawns
	local p = spawns[rng:NextInteger(1, #spawns)]
	local pos = p + Vector3.new(0, 3, 0)
	local hall = LobbyLayout.DuelFloor.Pos
	return CFrame.lookAt(pos, Vector3.new(hall.X, pos.Y, hall.Z)) -- Blick zur Duell-Halle (FTUE)
end

function ArenaService.Layout(mapKey: string): Types.MapLayout?
	if type(mapKey) ~= "string" then
		return nil
	end
	return layouts[mapKey]
end

function ArenaService.SlotStates(): { { Slot: number, State: string, MapKey: string? } }
	local out: { { Slot: number, State: string, MapKey: string? } } = {}
	for _, slot in ipairs(slots) do
		table.insert(out, { Slot = slot.Slot, State = slot.State, MapKey = slot.MapKey })
	end
	return out
end

function ArenaService.Template(mapKey: string): Template?
	return templates[mapKey]
end

function ArenaService.Init(_services: any)
	registerCollisionGroups() -- ZUERST (C12.6)
	loadLayouts()
	setupFolders()
	buildTemplates()
	buildCrown()
end

function ArenaService.Start()
	if stopCleanup then
		return
	end
	local every = math.max(1, num(server().CleanupEvery, 30))
	stopCleanup = Scheduler.Every("ArenaCleanup", 1 / every, function()
		cleanup()
	end)
end

return ArenaService
