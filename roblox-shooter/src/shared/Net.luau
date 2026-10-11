--!strict
-- =====================================================================
--  CLUTCH CLASH – Netzwerk: Remote-Liste + Buffer-Codecs (Shared/Net)
--  Besitzer: WP1 (Core & Plattform). Vertrag: DESIGN.md C6.1 + C8.
--
--  Öffentliche API:
--    Net.RemoteList                      alle Remotes { Name, Class } (Server erzeugt sie: Services/Remotes)
--    Net.GetRemotes(): { [string]: Instance }   Client: WaitForChild je Name (10 s), gecacht
--    Net.EncodeLook(pitchDeg, flags, seq): buffer           4 Byte: i8 pitch, u8 flags, u16 seq
--    Net.DecodeLook(b): (pitch, flags, seq)?                nil bei falscher Größe / pitch außerhalb ±80
--    Net.EncodeLookBatch(seq, entries): buffer              u16 seq, u8 n, n × (u8 slot, i8 pitch, u8 flags)
--    Net.DecodeLookBatch(b): (seq, entries)?
--    Net.EncodeFx(entries, origin): buffer                  u8 n, n × (u8 kind, u8 slot, u8 weapon, i16×3, i16×3)
--    Net.DecodeFx(b, origin): entries?                      Positionen relativ zum Arena-Ursprung ×10
--    Net.LookFlags = { Ads = 1, Sprint = 2, Slide = 4, Reload = 8, Block = 16, Air = 32, Swing = 64 }
--  Alle Zahlen werden vor dem Schreiben geklemmt/gerundet (nie Fehler beim Kodieren, auch bei NaN).
-- =====================================================================

local Net = {}

export type RemoteClass = "RemoteEvent" | "RemoteFunction" | "UnreliableRemoteEvent"
export type RemoteSpec = { Name: string, Class: RemoteClass }
export type LookEntry = { Slot: number, Pitch: number, Flags: number }
export type FxEntry = { Kind: number, Slot: number, Weapon: number, O: Vector3, E: Vector3 }

-- ---------------------------------------------------------------------
-- 1) REMOTES (C8) – Reihenfolge egal, Namen sind der Vertrag
-- ---------------------------------------------------------------------
Net.RemoteList = {
	{ Name = "Notify", Class = "RemoteEvent" }, -- S→C (text, kind) – bereits lokalisiert
	{ Name = "State", Class = "RemoteEvent" }, -- S→C (partial, full) – Sticky-Merge
	{ Name = "Effect", Class = "RemoteEvent" }, -- S→C (name, strength, data?)
	{ Name = "Request", Class = "RemoteFunction" }, -- C→S (action, arg?) → Reply (C9)
	{ Name = "Admin", Class = "RemoteFunction" }, -- C→S (action, args?) → {Ok, Message, Data}
	{ Name = "Match", Class = "RemoteEvent" }, -- S→C (kind, data) – nur an Empfänger des Matches
	{ Name = "Combat", Class = "RemoteEvent" }, -- S→C (op, data)
	{ Name = "Fire", Class = "RemoteEvent" }, -- C→S (shotId, weaponId, t, origin, aim, scale, targets)
	{ Name = "WeaponAction", Class = "RemoteEvent" }, -- C→S (action, a..e)
	{ Name = "Look", Class = "UnreliableRemoteEvent" }, -- C→S buffer 4 Byte
	{ Name = "LookBatch", Class = "UnreliableRemoteEvent" }, -- S→C buffer ≤ 51 Byte
	{ Name = "FX", Class = "UnreliableRemoteEvent" }, -- S→C buffer ≤ 871 Byte
	{ Name = "GrantCoins", Class = "RemoteEvent" }, -- Honeypot – unser Code feuert ihn NIE
} :: { RemoteSpec }

Net.LookFlags = { Ads = 1, Sprint = 2, Slide = 4, Reload = 8, Block = 16, Air = 32, Swing = 64 }

-- Grenzen der Pakete
Net.LookSize = 4
Net.MaxPitch = 80
Net.MaxLookBatch = 16 -- 3 + 16 × 3 = 51 Byte
Net.MaxFx = 58 -- 1 + 58 × 15 = 871 Byte
Net.FxScale = 10 -- Positionen ×10 als i16 (±3276 Studs um den Arena-Ursprung)

local REMOTE_WAIT = 10
local cachedRemotes: { [string]: Instance }? = nil

-- Alle Remotes als Tabelle Name -> Instanz. Wartet je Name höchstens 10 s (fehlende -> warn, ausgelassen).
function Net.GetRemotes(): { [string]: Instance }
	if cachedRemotes then
		return cachedRemotes
	end
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local result: { [string]: Instance } = {}
	local folder = ReplicatedStorage:WaitForChild("Remotes", REMOTE_WAIT)
	if not folder then
		warn("[Net] Ordner ReplicatedStorage.Remotes fehlt")
		return result
	end
	local complete = true
	for _, spec in ipairs(Net.RemoteList) do
		local remote = folder:FindFirstChild(spec.Name) or folder:WaitForChild(spec.Name, REMOTE_WAIT)
		if remote and remote:IsA(spec.Class) then
			result[spec.Name] = remote
		else
			complete = false
			warn("[Net] Remote fehlt: " .. spec.Name .. " (" .. spec.Class .. ")")
		end
	end
	if complete then
		cachedRemotes = result -- nur vollständige Ergebnisse merken (sonst später nochmal versuchen)
	end
	return result
end

-- ---------------------------------------------------------------------
-- 2) QUANTISIERUNG
-- ---------------------------------------------------------------------
local function finite(n: any): number
	if typeof(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
		return 0
	end
	return n
end

-- auf ganze Zahl runden und in [lo, hi] klemmen
local function intIn(n: any, lo: number, hi: number): number
	return math.clamp(math.floor(finite(n) + 0.5), lo, hi)
end

local function pitchByte(pitch: any): number
	return intIn(pitch, -Net.MaxPitch, Net.MaxPitch)
end

-- Bitmaske auf 0..255 (nur ganze, nicht negative Werte)
local function flagsByte(flags: any): number
	return bit32.band(intIn(flags, 0, 255), 0xFF)
end

local function writeVec(b: buffer, offset: number, v: Vector3, origin: Vector3)
	local rel = v - origin
	buffer.writei16(b, offset, intIn(rel.X * Net.FxScale, -32768, 32767))
	buffer.writei16(b, offset + 2, intIn(rel.Y * Net.FxScale, -32768, 32767))
	buffer.writei16(b, offset + 4, intIn(rel.Z * Net.FxScale, -32768, 32767))
end

local function readVec(b: buffer, offset: number, origin: Vector3): Vector3
	local x = buffer.readi16(b, offset) / Net.FxScale
	local y = buffer.readi16(b, offset + 2) / Net.FxScale
	local z = buffer.readi16(b, offset + 4) / Net.FxScale
	return origin + Vector3.new(x, y, z)
end

local function safeVector(v: any): Vector3
	if typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z then
		return v
	end
	return Vector3.zero
end

-- ---------------------------------------------------------------------
-- 3) LOOK (C→S, 4 Byte): i8 pitchDeg, u8 flags, u16 seq
-- ---------------------------------------------------------------------
function Net.EncodeLook(pitchDeg: number, flags: number, seq: number): buffer
	local b = buffer.create(Net.LookSize)
	buffer.writei8(b, 0, pitchByte(pitchDeg))
	buffer.writeu8(b, 1, flagsByte(flags))
	buffer.writeu16(b, 2, math.floor(finite(seq)) % 65536)
	return b
end

function Net.DecodeLook(b: buffer): (number, number, number)?
	if typeof(b) ~= "buffer" or buffer.len(b) ~= Net.LookSize then
		return nil
	end
	local pitch = buffer.readi8(b, 0)
	if pitch < -Net.MaxPitch or pitch > Net.MaxPitch then
		return nil
	end
	return pitch, buffer.readu8(b, 1), buffer.readu16(b, 2)
end

-- ---------------------------------------------------------------------
-- 4) LOOKBATCH (S→C, ≤ 51 Byte): u16 seq, u8 n, n × (u8 slot, i8 pitch, u8 flags)
-- ---------------------------------------------------------------------
function Net.EncodeLookBatch(seq: number, entries: { LookEntry }): buffer
	local n = math.min(#entries, Net.MaxLookBatch)
	local b = buffer.create(3 + n * 3)
	buffer.writeu16(b, 0, math.floor(finite(seq)) % 65536)
	buffer.writeu8(b, 2, n)
	for i = 1, n do
		local e = entries[i]
		local offset = 3 + (i - 1) * 3
		buffer.writeu8(b, offset, intIn(e.Slot, 0, 255))
		buffer.writei8(b, offset + 1, pitchByte(e.Pitch))
		buffer.writeu8(b, offset + 2, flagsByte(e.Flags))
	end
	return b
end

function Net.DecodeLookBatch(b: buffer): (number, { LookEntry })?
	if typeof(b) ~= "buffer" or buffer.len(b) < 3 then
		return nil
	end
	local n = buffer.readu8(b, 2)
	if n > Net.MaxLookBatch or buffer.len(b) ~= 3 + n * 3 then
		return nil
	end
	local entries: { LookEntry } = table.create(n)
	for i = 1, n do
		local offset = 3 + (i - 1) * 3
		entries[i] = {
			Slot = buffer.readu8(b, offset),
			Pitch = math.clamp(buffer.readi8(b, offset + 1), -Net.MaxPitch, Net.MaxPitch),
			Flags = buffer.readu8(b, offset + 2),
		}
	end
	return buffer.readu16(b, 0), entries
end

-- ---------------------------------------------------------------------
-- 5) FX (S→C, ≤ 871 Byte): u8 n, n × (u8 kind, u8 slot, u8 weapon, i16×3 origin, i16×3 end)
--    kind 1 = Tracer + Flächen-Treffer, 2 = Tracer + Spieler-Treffer, 3 = Nahkampf-Schwung, 4 = Wurf
--    Mehr als 58 Einträge: die ältesten (vorne in der Liste) fallen raus.
-- ---------------------------------------------------------------------
local FX_ENTRY = 15

function Net.EncodeFx(entries: { FxEntry }, origin: Vector3): buffer
	local base = safeVector(origin)
	local total = #entries
	local n = math.min(total, Net.MaxFx)
	local first = total - n + 1 -- nur die neuesten n
	local b = buffer.create(1 + n * FX_ENTRY)
	buffer.writeu8(b, 0, n)
	for i = 0, n - 1 do
		local e = entries[first + i]
		local offset = 1 + i * FX_ENTRY
		buffer.writeu8(b, offset, intIn(e.Kind, 0, 255))
		buffer.writeu8(b, offset + 1, intIn(e.Slot, 0, 255))
		buffer.writeu8(b, offset + 2, intIn(e.Weapon, 0, 255))
		writeVec(b, offset + 3, safeVector(e.O), base)
		writeVec(b, offset + 9, safeVector(e.E), base)
	end
	return b
end

function Net.DecodeFx(b: buffer, origin: Vector3): { FxEntry }?
	if typeof(b) ~= "buffer" or buffer.len(b) < 1 then
		return nil
	end
	local n = buffer.readu8(b, 0)
	if n > Net.MaxFx or buffer.len(b) ~= 1 + n * FX_ENTRY then
		return nil
	end
	local base = safeVector(origin)
	local entries: { FxEntry } = table.create(n)
	for i = 0, n - 1 do
		local offset = 1 + i * FX_ENTRY
		entries[i + 1] = {
			Kind = buffer.readu8(b, offset),
			Slot = buffer.readu8(b, offset + 1),
			Weapon = buffer.readu8(b, offset + 2),
			O = readVec(b, offset + 3, base),
			E = readVec(b, offset + 9, base),
		}
	end
	return entries
end

return Net
