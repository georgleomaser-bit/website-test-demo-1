-- =====================================================================
--  CLUTCH CLASH – Look/LookBatch/FX (Server/Services/ReplicationService)
--  Besitzer: WP3 (Kampf Server & Treffer-Mathematik). Vertrag: DESIGN.md C5.4, C8, C12.2, B14.8.
--  * Look (C→S, 4 Byte, unreliable): Pitch + Flags + seq. 20/s, sonst still verworfen; ältere seq verworfen;
--    nur von bewaffneten Spielern; NIE für Autorität benutzt (nur Darstellung, AFK, Quests).
--  * LookBatch (S→C, ≤ 51 Byte): pro Kontext 10 Hz an Context.Recipients() (nur bei Änderung, sonst 1×/s).
--  * FX (S→C, ≤ 871 Byte): Tracer/Treffer/Schwung/Wurf pro Kontext gesammelt, 20 Hz, höchstens 58 Einträge
--    (ältere fallen raus); der Schütze bekommt seine eigenen Einträge nicht (er hat sie schon vorhergesagt).
--  * FireCtx: zuverlässiges Remote an alle Empfänger eines Kontexts (nie FireAllClients).
--
--  Öffentliche API (C5.4):
--    ReplicationService.QueueFx(ctx, kind, slot, weaponId, origin, endPos)
--    ReplicationService.FireCtx(ctx, remoteName, ...)
--    ReplicationService.LastInput(p): number         Server-Zeit der letzten Look/Fire/WeaponAction (AFK)
--    ReplicationService.Flags(p): number             letzte Look-Flags (Net.LookFlags)
--  Rutsch-Starts (Flag-Wechsel Slide) -> RewardService.Track(p, "Slide", 1) (pcall).
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Net = require(Shared:WaitForChild("Net"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))

local ReplicationService = {}
local Services: any

type Combatant = Types.Combatant
type FxEntry = { Kind: number, Slot: number, Weapon: number, O: Vector3, E: Vector3 }
type LookState = { Pitch: number, Flags: number, Seq: number, Ctx: string }

local SECURITY: any = Config.Security
local LOOK_BUCKET = if type(SECURITY.Buckets) == "table" and type(SECURITY.Buckets.Look) == "table"
	then SECURITY.Buckets.Look
	else { 20, 20 }
local LOOKBATCH_HZ = 10
local FX_HZ = 20
local LOOK_RESEND = 1.0 -- unveränderte LookBatch spätestens nach 1 s erneut (Paketverlust)
local SLIDE_FLAG = Net.LookFlags.Slide

local lookBucket = Util.TokenBucket(tonumber(LOOK_BUCKET[1]) or 20, tonumber(LOOK_BUCKET[2]) or 20)
local looks: { [Player]: LookState } = {}
local lastInput: { [Player]: number } = {}
local fxQueues: { [string]: { FxEntry } } = {}
local batchSeq: { [string]: number } = {}
local batchSig: { [string]: string } = {}
local batchAt: { [string]: number } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function call(serviceName: string, fnName: string, ...: any): (boolean, any)
	local service = Services and Services[serviceName]
	local fn = service and service[fnName]
	if type(fn) ~= "function" then
		return false, nil
	end
	return pcall(fn, ...)
end

local function combatantOf(p: Player): Combatant?
	local ok, c = call("CombatService", "OfPlayer", p)
	if ok and type(c) == "table" then
		return c
	end
	return nil
end

local function contextOf(ctx: string): Types.ContextInfo?
	local ok, info = call("CombatService", "Context", ctx)
	if ok and type(info) == "table" then
		return info
	end
	return nil
end

-- Empfänger eines Kontexts (nur echte, noch verbundene Spieler)
local function recipientsOf(info: Types.ContextInfo): { Player }
	if type(info.Recipients) ~= "function" then
		return {}
	end
	local ok, list = pcall(info.Recipients)
	if not ok or type(list) ~= "table" then
		return {}
	end
	local out: { Player } = {}
	for _, p in ipairs(list) do
		if typeof(p) == "Instance" and p:IsA("Player") and p.Parent == Players then
			table.insert(out, p :: any)
		end
	end
	return out
end

local function arenaOrigin(info: Types.ContextInfo): Vector3
	local arena: any = info.Arena
	if arena and typeof(arena.Origin) == "CFrame" then
		return arena.Origin.Position
	end
	return Vector3.zero
end

-- ---------------------------------------------------------------------
-- LOOK (C→S)
-- ---------------------------------------------------------------------
local function onLook(p: Player, b: any)
	if not lookBucket.Take(p) then
		return -- 20/s, Rest still verwerfen
	end
	if typeof(b) ~= "buffer" or buffer.len(b) ~= Net.LookSize then
		return
	end
	local pitch, flags, seq = Net.DecodeLook(b)
	if pitch == nil then
		return
	end
	local c = combatantOf(p)
	if not c then
		return -- nur bewaffnete Spieler
	end
	local state = looks[p]
	if state and state.Ctx == c.Ctx then
		local diff = (seq - state.Seq) % 65536
		if diff == 0 or diff >= 32768 then
			return -- älter oder doppelt
		end
	end
	local before = if state then state.Flags else 0
	if bit32.band(flags, SLIDE_FLAG) ~= 0 and bit32.band(before, SLIDE_FLAG) == 0 then
		call("RewardService", "Track", p, "Slide", 1)
	end
	looks[p] = { Pitch = pitch, Flags = flags, Seq = seq, Ctx = c.Ctx }
	lastInput[p] = now()
end

-- ---------------------------------------------------------------------
-- LOOKBATCH (S→C, 10 Hz pro Kontext)
-- ---------------------------------------------------------------------
local function sendLookBatches(_dt: number)
	local byCtx: { [string]: { { Slot: number, Pitch: number, Flags: number } } } = {}
	for p, state in pairs(looks) do
		local c = combatantOf(p)
		if not c or c.Ctx ~= state.Ctx then
			continue
		end
		if not c.Alive then
			continue
		end
		local list = byCtx[c.Ctx]
		if not list then
			list = {}
			byCtx[c.Ctx] = list
		end
		if #list < Net.MaxLookBatch then
			table.insert(list, { Slot = c.Slot, Pitch = state.Pitch, Flags = state.Flags })
		end
	end
	local t = now()
	for ctx, entries in pairs(byCtx) do
		local info = contextOf(ctx)
		if not info then
			continue
		end
		table.sort(entries, function(a, b)
			return a.Slot < b.Slot
		end)
		local sigParts = table.create(#entries)
		for i, e in ipairs(entries) do
			sigParts[i] = ("%d:%d:%d"):format(e.Slot, e.Pitch, e.Flags)
		end
		local sig = table.concat(sigParts, ",")
		if sig == batchSig[ctx] and t - (batchAt[ctx] or 0) < LOOK_RESEND then
			continue
		end
		batchSig[ctx] = sig
		batchAt[ctx] = t
		local seq = ((batchSeq[ctx] or 0) + 1) % 65536
		batchSeq[ctx] = seq
		local packet = Net.EncodeLookBatch(seq, entries)
		for _, p in ipairs(recipientsOf(info)) do
			Remotes.LookBatch:FireClient(p, packet)
		end
	end
	-- Zähler verschwundener Kontexte wegräumen
	for ctx in pairs(batchSig) do
		if not byCtx[ctx] and not contextOf(ctx) then
			batchSig[ctx] = nil
			batchAt[ctx] = nil
			batchSeq[ctx] = nil
		end
	end
end

-- ---------------------------------------------------------------------
-- FX (S→C, 20 Hz pro Kontext)
-- ---------------------------------------------------------------------
function ReplicationService.QueueFx(
	ctx: string,
	kind: number,
	slot: number,
	weaponId: number,
	origin: Vector3,
	endPos: Vector3
)
	if type(ctx) ~= "string" or not Util.IsFiniteVector(origin) or not Util.IsFiniteVector(endPos) then
		return
	end
	local queue = fxQueues[ctx]
	if not queue then
		queue = {}
		fxQueues[ctx] = queue
	end
	table.insert(queue, {
		Kind = math.clamp(math.floor(tonumber(kind) or 1), 0, 255),
		Slot = math.clamp(math.floor(tonumber(slot) or 0), 0, 255),
		Weapon = math.clamp(math.floor(tonumber(weaponId) or 0), 0, 255),
		O = origin,
		E = endPos,
	})
	while #queue > Net.MaxFx do
		table.remove(queue, 1) -- ältere fallen raus
	end
end

local function flushFx(_dt: number)
	for ctx, queue in pairs(fxQueues) do
		if #queue == 0 then
			continue
		end
		fxQueues[ctx] = {}
		local info = contextOf(ctx)
		if not info then
			fxQueues[ctx] = nil
			continue
		end
		local origin = arenaOrigin(info)
		local slotsInBatch: { [number]: boolean } = {}
		for _, e in ipairs(queue) do
			slotsInBatch[e.Slot] = true
		end
		local shared: buffer? = nil
		for _, p in ipairs(recipientsOf(info)) do
			local c = combatantOf(p)
			local own = if c and c.Ctx == ctx then c.Slot else nil
			if own and slotsInBatch[own] then
				-- eigene Einträge auslassen
				local filtered: { FxEntry } = {}
				for _, e in ipairs(queue) do
					if e.Slot ~= own then
						table.insert(filtered, e)
					end
				end
				if #filtered > 0 then
					Remotes.FX:FireClient(p, Net.EncodeFx(filtered, origin))
				end
			else
				if not shared then
					shared = Net.EncodeFx(queue, origin)
				end
				Remotes.FX:FireClient(p, shared)
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- ZUVERLÄSSIG AN DEN KONTEXT
-- ---------------------------------------------------------------------
function ReplicationService.FireCtx(ctx: string, remoteName: string, ...: any)
	local info = contextOf(ctx)
	if not info then
		return
	end
	local remote = Remotes[remoteName]
	if typeof(remote) ~= "Instance" or not remote:IsA("RemoteEvent") then
		warn("[ReplicationService] FireCtx: unbekanntes RemoteEvent " .. tostring(remoteName))
		return
	end
	for _, p in ipairs(recipientsOf(info)) do
		remote:FireClient(p, ...)
	end
end

function ReplicationService.LastInput(p: Player): number
	return lastInput[p] or 0
end

function ReplicationService.Flags(p: Player): number
	local state = looks[p]
	return if state then state.Flags else 0
end

-- ---------------------------------------------------------------------
-- LEBENSZYKLUS
-- ---------------------------------------------------------------------
function ReplicationService.Init(services: any)
	Services = services
end

function ReplicationService.Start()
	Remotes.Look.OnServerEvent:Connect(onLook)
	-- Fire/WeaponAction zählen als Eingabe (AFK) – die Prüfung macht WeaponService
	Remotes.Fire.OnServerEvent:Connect(function(p: Player)
		lastInput[p] = now()
	end)
	Remotes.WeaponAction.OnServerEvent:Connect(function(p: Player)
		lastInput[p] = now()
	end)
	Players.PlayerAdded:Connect(function(p: Player)
		lastInput[p] = now()
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		lastInput[p] = lastInput[p] or now()
	end
	Players.PlayerRemoving:Connect(function(p: Player)
		looks[p] = nil
		lastInput[p] = nil
		lookBucket.Clear(p)
	end)
	Scheduler.Every("LookBatch", LOOKBATCH_HZ, sendLookBatches)
	Scheduler.Every("FX", FX_HZ, flushFx)
end

return ReplicationService
