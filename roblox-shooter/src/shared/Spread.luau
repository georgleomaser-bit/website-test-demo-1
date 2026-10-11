--!strict
-- =====================================================================
--  CLUTCH CLASH – Streuung (Shared/Spread)
--  Besitzer: WP3 (Kampf Server & Treffer-Mathematik). Vertrag: DESIGN.md C6.2, B11.1, C10.
--  Reines Modul: keine Dienste, kein Zufall von Roblox – Client und Server rechnen
--  mit derselben Ganzzahl-Mathematik (bit32) exakt dieselben Strahlen.
--
--  Öffentliche API:
--    Spread.Seed(salt, shotId): number
--        ganzzahlig 1..2^31-1, deterministisch. salt = Combatant.Salt (vom Server, Combat("Armed")),
--        shotId = fortlaufende Schuss-Nummer des Clients. NIE einen Client-Seed benutzen.
--    Spread.Directions(aim, def, scaleDeg, seed): { Vector3 }
--        genau def.Pellets Einheitsvektoren, gleichmäßig in einem Kegel mit Halbwinkel scaleDeg um aim.
--        scaleDeg <= 0 -> alle Strahlen = aim.
--    Spread.Bloom(def, shotTimes, t): number
--        min(BloomMax, BloomPerShot × Kettenlänge). shotTimes = Zeitstempel der VORHERIGEN Schüsse
--        (ein Eintrag gleich t wird ignoriert). Kette reißt bei Abstand > Interval × 1.6.
--    Spread.MinScale(def, adsOk, speed, airborne): number
--        Untergrenze des Server-Spreads (C10 Schritt 7): (adsOk ? SpreadAds : SpreadHip)
--        + (speed > Config.Combat.MovingSpeed ? SpreadMove : 0) + (airborne ? SpreadAir : 0).
--        Ohne Bloom (der Server nimmt max(Client-Anspruch, MinScale)).
--    Spread.MaxBloomChain                  Obergrenze der Kettenlänge (Schleifen-Grenze)
--  Ergänzungen von WP3 (Besitzer-Wunsch docs/SKILL-WUENSCHE.md – Client und Server rechnen gleich):
--    Spread.Chain(def, shotTimes, t): number       Anzahl vorheriger Schüsse in der laufenden Kette
--    Spread.FirstShot(def, shotTimes, t): number   def.FirstShotMult beim ersten Schuss einer Kette, sonst 1
--    Spread.Recoil(def, index, seed?): (pitchDeg, yawDeg)
--        Rückstoß des index-ten Schusses der Kette (1 = erster). Mit def.RecoilPattern fest und lernbar,
--        sonst RecoilPitch hoch + RecoilYaw zufällig ± (aus seed deterministisch).
--
--  Client-Formel (B11.1, WP4): lerp(SpreadHip, SpreadAds, adsAlpha) + Move + Air + Bloom (+ Rutschen).
--  Solange das Zielen noch nicht "fertig" ist (AdsTime − 0.1 s), rechnet der Server mit SpreadHip.
-- =====================================================================

local Types = require(script.Parent:WaitForChild("Types"))

local Spread = {}

local TWO32 = 4294967296
local TWO16 = 65536
local TAU = math.pi * 2

Spread.MaxBloomChain = 64

-- Startwerte = Config.Combat (zur Laufzeit von dort gelesen, damit es nur EINE Quelle gibt)
local movingSpeed = 10

do
	local ok, combat = pcall(function()
		return require(script.Parent:WaitForChild("Config"):WaitForChild("Combat"))
	end)
	if ok and type(combat) == "table" then
		local value = (combat :: any).MovingSpeed
		if type(value) == "number" and value == value and value >= 0 and value < math.huge then
			movingSpeed = value
		end
	end
end

-- ---------------------------------------------------------------------
-- 1) GANZZAHL-HELFER (exakt, ohne Genauigkeitsverlust über 2^53)
-- ---------------------------------------------------------------------

-- beliebige Zahl -> 0..2^32-1 (NaN/unendlich -> 0)
local function toU32(n: number): number
	if n ~= n or n == math.huge or n == -math.huge then
		return 0
	end
	return math.floor(n) % TWO32
end

-- (a × b) mod 2^32, a und b in 0..2^32-1
local function mul32(a: number, b: number): number
	local bl = b % TWO16
	local bh = (b - bl) / TWO16
	return (a * bl + ((a * bh) % TWO16) * TWO16) % TWO32
end

-- murmur3 fmix32 – verteilt benachbarte Werte gut
local function fmix32(h: number): number
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 0x85EBCA6B)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = mul32(h, 0xC2B2AE35)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h
end

-- xorshift32: nächster Zustand (nie 0, wenn der Start nicht 0 ist)
local function xorshift(x: number): number
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	return x
end

local function finiteOr(n: number, default: number): number
	if n ~= n or n == math.huge or n == -math.huge then
		return default
	end
	return n
end

-- ---------------------------------------------------------------------
-- 2) SEED
-- ---------------------------------------------------------------------
function Spread.Seed(salt: number, shotId: number): number
	local s = toU32(salt)
	local n = toU32(shotId)
	local h = bit32.bxor(fmix32(bit32.bxor(s, 0x5BD1E995)), mul32(n, 0x9E3779B1))
	h = fmix32(h)
	h = bit32.band(h, 0x7FFFFFFF)
	if h == 0 then
		h = 1
	end
	return h
end

-- ---------------------------------------------------------------------
-- 3) RICHTUNGEN
-- ---------------------------------------------------------------------
local FALLBACK_AIM = Vector3.new(0, 0, -1)

local function unitAim(aim: Vector3): Vector3
	local m = aim.Magnitude
	if m ~= m or m < 1e-6 or m == math.huge then
		return FALLBACK_AIM
	end
	return aim / m
end

function Spread.Directions(aim: Vector3, def: Types.WeaponDef, scaleDeg: number, seed: number): { Vector3 }
	local pellets = math.clamp(math.floor(finiteOr(def.Pellets, 1)), 1, 32)
	local a = unitAim(aim)
	local scale = math.clamp(finiteOr(scaleDeg, 0), 0, 89)
	local dirs: { Vector3 } = table.create(pellets)
	if scale <= 0 then
		for i = 1, pellets do
			dirs[i] = a
		end
		return dirs
	end
	-- Orthonormalbasis um die Zielrichtung
	local helper = if math.abs(a.Y) < 0.99 then Vector3.yAxis else Vector3.xAxis
	local right = a:Cross(helper).Unit
	local up = right:Cross(a)
	local maxAngle = math.rad(scale)
	local state = toU32(seed)
	if state == 0 then
		state = 0x6D2B79F5
	end
	for i = 1, pellets do
		state = xorshift(state)
		local u1 = state / TWO32
		state = xorshift(state)
		local u2 = state / TWO32
		-- gleichmäßig über die Kegel-Kappe (Fläche ~ Winkel²) -> sqrt
		local theta = maxAngle * math.sqrt(u1)
		local phi = TAU * u2
		local s = math.sin(theta)
		local offset = right * (math.cos(phi) * s) + up * (math.sin(phi) * s)
		dirs[i] = (a * math.cos(theta) + offset).Unit
	end
	return dirs
end

-- ---------------------------------------------------------------------
-- 4) BLOOM
-- ---------------------------------------------------------------------
function Spread.Chain(def: Types.WeaponDef, shotTimes: { number }, t: number): number
	local gapLimit = math.max(0, finiteOr(def.Interval, 0)) * 1.6
	local chain = 0
	local now = finiteOr(t, 0)
	local prev = now
	local count = #shotTimes
	local stop = math.max(1, count - Spread.MaxBloomChain * 2)
	for i = count, stop, -1 do
		local st = shotTimes[i]
		if type(st) == "number" and st == st then
			local gap = prev - st
			if prev == now and math.abs(gap) < 1e-4 then
				continue -- derselbe Schuss (schon eingetragen) zählt nicht
			end
			if gap < 0 then
				continue -- spätere Einträge ignorieren
			end
			if gap > gapLimit then
				break
			end
			chain += 1
			prev = st
			if chain >= Spread.MaxBloomChain then
				break
			end
		end
	end
	return chain
end

function Spread.Bloom(def: Types.WeaponDef, shotTimes: { number }, t: number): number
	local perShot = finiteOr(def.BloomPerShot, 0)
	local maxBloom = finiteOr(def.BloomMax, 0)
	if perShot <= 0 or maxBloom <= 0 then
		return 0
	end
	return math.min(maxBloom, perShot * Spread.Chain(def, shotTimes, t))
end

function Spread.FirstShot(def: Types.WeaponDef, shotTimes: { number }, t: number): number
	local mult = (def :: any).FirstShotMult
	if type(mult) ~= "number" or mult ~= mult or mult >= 1 or mult < 0 then
		return 1
	end
	if Spread.Chain(def, shotTimes, t) > 0 then
		return 1
	end
	return mult
end

function Spread.Recoil(def: Types.WeaponDef, index: number, seed: number?): (number, number)
	local pitch = math.max(0, finiteOr(def.RecoilPitch, 0))
	local yaw = math.max(0, finiteOr(def.RecoilYaw, 0))
	local n = math.max(1, math.floor(finiteOr(index, 1)))
	local pattern = (def :: any).RecoilPattern
	if type(pattern) == "table" and #pattern > 0 then
		local len = math.min(#pattern, Spread.MaxBloomChain)
		local loopFrom = math.clamp(math.floor(finiteOr((def :: any).RecoilLoopFrom or 1, 1)), 1, len)
		local i = n
		if i > len then
			local loopLen = len - loopFrom + 1
			i = loopFrom + ((i - len - 1) % loopLen)
		end
		local step = pattern[i]
		if type(step) == "table" then
			local p = finiteOr(tonumber(step[1]) or 1, 1)
			local y = math.clamp(finiteOr(tonumber(step[2]) or 0, 0), -1.5, 1.5)
			return pitch * p, yaw * y
		end
	end
	-- ohne Muster: zufälliger Seitenkick ±RecoilYaw, aus seed + index deterministisch
	local state = toU32((seed or 0) + n * 0x9E37)
	if state == 0 then
		state = 0x6D2B79F5
	end
	state = xorshift(xorshift(state))
	return pitch, yaw * ((state / TWO32) * 2 - 1)
end

-- ---------------------------------------------------------------------
-- 5) SERVER-UNTERGRENZE
-- ---------------------------------------------------------------------
function Spread.MinScale(def: Types.WeaponDef, adsOk: boolean, speed: number, airborne: boolean): number
	local base = if adsOk then finiteOr(def.SpreadAds, 0) else finiteOr(def.SpreadHip, 0)
	local v = finiteOr(speed, 0)
	if v > movingSpeed then
		base += finiteOr(def.SpreadMove, 0)
	end
	if airborne then
		base += finiteOr(def.SpreadAir, 0)
	end
	return math.max(0, base)
end

return Spread
