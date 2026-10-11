-- =====================================================================
--  CLUTCH CLASH – Positions-Verlauf fürs Rückspulen (Server/Services/HistoryService)
--  Besitzer: WP3 (Kampf Server & Treffer-Mathematik). Vertrag: DESIGN.md C5.4, C10, B13.2.
--  Ringpuffer HistorySlots (24) × HistoryHz (30 Hz) = 0.8 s pro getracktem Combatant:
--  { t = workspace:GetServerTimeNow(), Root = HRP-CFrame, Head = Kopf-Position }.
--  Übungspuppen: nur neue Einträge, wenn sie sich bewegt haben (statisch = ein Eintrag reicht).
--  Ein Scheduler-Takt für alle (keine Schleife pro Spieler).
--
--  Öffentliche API:
--    HistoryService.Track(c)                        ab jetzt aufzeichnen (Revive/Register)
--    HistoryService.Untrack(c)                      vergessen (Pop/Unregister)
--    HistoryService.Sample(c, t): (CFrame?, Vector3?)            rootCF, headPos (gelerpt)
--    HistoryService.SampleWindow(c, t): { { Root, Head } }        T−0.075, T, T+0.075
--    HistoryService.Speed(c, t): number                           horizontal Studs/s
--  Ohne Verlauf (nicht getrackt) liefern Sample/Speed die aktuellen Live-Werte.
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Types"))
local Config = require(Shared:WaitForChild("Config"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local HistoryService = {}
local Services: any

type Combatant = Types.Combatant
type Ring = {
	Times: { number },
	Roots: { CFrame },
	Heads: { Vector3 },
	Count: number, -- belegte Einträge (≤ SLOTS)
	Last: number, -- Index des neuesten Eintrags (1..SLOTS)
	Static: boolean, -- Puppe: nur bei Bewegung neu schreiben
}

local COMBAT: any = Config.Combat
local SLOTS = math.clamp(math.floor(tonumber(COMBAT.HistorySlots) or 24), 2, 120)
local HZ = math.clamp(tonumber(COMBAT.HistoryHz) or 30, 1, 60)
local WINDOW = math.clamp(tonumber(COMBAT.RewindWindow) or 0.075, 0, 0.3)
local SPEED_SPAN = 0.1 -- Zeitspanne für die Tempo-Schätzung
local STATIC_EPS = 0.01 -- Puppe gilt als bewegt ab 0.01 Studs

local rings: { [Combatant]: Ring } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function partsAlive(c: Combatant): boolean
	return c.Root ~= nil and c.Root.Parent ~= nil and c.Head ~= nil and c.Head.Parent ~= nil
end

local function live(c: Combatant): (CFrame?, Vector3?)
	if partsAlive(c) then
		return c.Root.CFrame, c.Head.Position
	end
	return nil, nil
end

local function write(ring: Ring, t: number, root: CFrame, head: Vector3)
	local idx = (ring.Last % SLOTS) + 1
	ring.Times[idx] = t
	ring.Roots[idx] = root
	ring.Heads[idx] = head
	ring.Last = idx
	ring.Count = math.min(SLOTS, ring.Count + 1)
end

-- k = 0 neuester … Count−1 ältester
local function at(ring: Ring, k: number): (number, CFrame, Vector3)
	local idx = ((ring.Last - 1 - k) % SLOTS) + 1
	return ring.Times[idx], ring.Roots[idx], ring.Heads[idx]
end

local function sampleRing(ring: Ring, t: number): (CFrame, Vector3)
	local newerT, newerRoot, newerHead = at(ring, 0)
	if t >= newerT then
		return newerRoot, newerHead -- nicht in die Zukunft raten
	end
	for k = 1, ring.Count - 1 do
		local olderT, olderRoot, olderHead = at(ring, k)
		if olderT <= t then
			local span = newerT - olderT
			local alpha = if span > 1e-6 then (t - olderT) / span else 1
			return olderRoot:Lerp(newerRoot, alpha), olderHead:Lerp(newerHead, alpha)
		end
		newerT, newerRoot, newerHead = olderT, olderRoot, olderHead
	end
	return newerRoot, newerHead -- älter als der Puffer: ältester Eintrag
end

local function sampleAll(_dt: number)
	local t = now()
	for c, ring in pairs(rings) do
		if not partsAlive(c) then
			continue
		end
		local root = c.Root.CFrame
		local head = c.Head.Position
		if ring.Static and ring.Count > 0 then
			local _, lastRoot = at(ring, 0)
			if (lastRoot.Position - root.Position).Magnitude < STATIC_EPS then
				continue -- Puppe steht still
			end
		end
		write(ring, t, root, head)
	end
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICHE API
-- ---------------------------------------------------------------------
function HistoryService.Track(c: Combatant)
	if type(c) ~= "table" then
		return
	end
	local ring: Ring = {
		Times = table.create(SLOTS, 0),
		Roots = table.create(SLOTS, CFrame.identity),
		Heads = table.create(SLOTS, Vector3.zero),
		Count = 0,
		Last = 0,
		Static = c.Kind == "Dummy",
	}
	rings[c] = ring
	local root, head = live(c)
	if root and head then
		write(ring, now(), root, head)
	end
end

function HistoryService.Untrack(c: Combatant)
	if c ~= nil then
		rings[c] = nil
	end
end

function HistoryService.Sample(c: Combatant, t: number): (CFrame?, Vector3?)
	local ring = rings[c]
	if not ring or ring.Count == 0 or type(t) ~= "number" or t ~= t then
		return live(c)
	end
	return sampleRing(ring, t)
end

function HistoryService.SampleWindow(c: Combatant, t: number): { { Root: CFrame, Head: Vector3 } }
	local out: { { Root: CFrame, Head: Vector3 } } = {}
	for _, offset in ipairs({ -WINDOW, 0, WINDOW }) do
		local root, head = HistoryService.Sample(c, t + offset)
		if root and head then
			table.insert(out, { Root = root, Head = head })
		end
	end
	return out
end

function HistoryService.Speed(c: Combatant, t: number): number
	local ring = rings[c]
	if ring and ring.Count >= 2 and type(t) == "number" and t == t then
		local a = sampleRing(ring, t - SPEED_SPAN)
		local b = sampleRing(ring, t)
		local d = b.Position - a.Position
		return Vector3.new(d.X, 0, d.Z).Magnitude / SPEED_SPAN
	end
	if partsAlive(c) then
		local v = c.Root.AssemblyLinearVelocity
		return Vector3.new(v.X, 0, v.Z).Magnitude
	end
	return 0
end

-- Anzahl getrackter Combatants (Debug/SelfTest)
function HistoryService.Count(): number
	local n = 0
	for _ in pairs(rings) do
		n += 1
	end
	return n
end

function HistoryService.Init(services: any)
	Services = services
end

function HistoryService.Start()
	Scheduler.Every("History", HZ, sampleAll)
	-- Sicherheitsnetz: Puffer von Combatants, deren Modell verschwunden ist, nach 10 s wegräumen
	Scheduler.Every("HistoryPrune", 0.1, function()
		for c in pairs(rings) do
			if c.Model == nil or c.Model.Parent == nil then
				local stillRegistered = false
				local combat = Services and Services.CombatService
				if combat then
					local ok, found = pcall(combat.Get, c.Id)
					stillRegistered = ok and found == c
				end
				if not stillRegistered then
					rings[c] = nil
				end
			end
		end
	end)
end

return HistoryService
