--!strict
--!native
-- =====================================================================
--  AKYTEX TYCOON – Deterministisches Hashing & Value-Noise (Server/Market/Noise)
--  Besitzer: WP3 (Markt-Engine). Vertrag: MARKET.md §5.2 (1:1), §19.2 (Testvektoren), DESIGN.md §D WP3.
--  Kein Random, kein math.random: identisch auf allen Servern und Roblox-Versionen, zustandslos (Random-Access).
--  Luau-Zahlen sind Doubles (exakt bis 2^53) -> 32-Bit-Multiplikation per 16-Bit-Split.
--  Rein: lädt keine Roblox-Dienste -> mit der Luau-CLI testbar (tests/noise.test.luau). Liegt NUR im Server.
--
--  Öffentliche API
--    Noise.Mul32(a, b): number            (a · b) mod 2^32
--    Noise.H32(x): number                 "lowbias32" (Wellons)
--    Noise.Hash4(a, b, c, d): number      h32-Kette ab 0x9E3779B9 (= Python-Referenz hcomb)
--    Noise.Uni(seed, fid, k, n): number   gleichverteilt in [−1, 1)
--    Noise.Rnd(seed, a, b, c): number     gleichverteilt in [0, 1)
--    Noise.Gauss(seed, a, b, c): number   ≈ N(0, 1): Summe von 3 Uniforms (Var = 1)
--    Noise.White(seed, fid, t): number    MARKET §5.2 whiteAt (Kanäle 9001/9002/9003)
--    Noise.NewField(seed, fid, kMin?, kMax?): Field     Oktaven kMin…kMax (Standard 1…14), Varianz 1
--    Noise.FieldAt(f, t): number          sequentiell billig (14 Lerps), Hashes nur beim Gitterwechsel
--    Noise.K, Noise.P0, Noise.PERIOD, Noise.AMP
--  Live-Felder und Random-Access-Felder sind GETRENNTE Field-Objekte (Caches stören sich nicht).
-- =====================================================================

local Noise = {}

local band = bit32.band
local bxor = bit32.bxor
local rshift = bit32.rshift

local TWO16 = 65536
local TWO32 = 4294967296

-- ---------------------------------------------------------------------
-- 1) HASH
-- ---------------------------------------------------------------------
local function mul32(a: number, b: number): number
	local aHi, aLo = rshift(a, 16), band(a, 0xFFFF)
	local bHi, bLo = rshift(b, 16), band(b, 0xFFFF)
	local mid = (aHi * bLo + aLo * bHi) % TWO16
	return (mid * TWO16 + aLo * bLo) % TWO32
end

-- Multiplikation mit den festen lowbias32-Konstanten (gleiche Mathematik wie mul32, vorgerechnete Hälften)
local C1_HI, C1_LO = rshift(0x7FEB352D, 16), band(0x7FEB352D, 0xFFFF)
local C2_HI, C2_LO = rshift(0x846CA68B, 16), band(0x846CA68B, 0xFFFF)

local function h32(input: number): number
	local x = bxor(input, rshift(input, 16))
	local hi, lo = rshift(x, 16), band(x, 0xFFFF)
	x = (((hi * C1_LO + lo * C1_HI) % TWO16) * TWO16 + lo * C1_LO) % TWO32
	x = bxor(x, rshift(x, 15))
	hi, lo = rshift(x, 16), band(x, 0xFFFF)
	x = (((hi * C2_LO + lo * C2_HI) % TWO16) * TWO16 + lo * C2_LO) % TWO32
	return bxor(x, rshift(x, 16))
end

local function hash4(a: number, b: number, c: number, d: number): number
	local h = h32(bxor(0x9E3779B9, a))
	h = h32(bxor(h, b))
	h = h32(bxor(h, c))
	return h32(bxor(h, d))
end

local function uni(seed: number, fid: number, k: number, n: number): number
	return hash4(seed, fid, k, n) / 2147483648 - 1
end

Noise.Mul32 = mul32
Noise.H32 = h32
Noise.Hash4 = hash4
Noise.Uni = uni

function Noise.Rnd(seed: number, a: number, b: number, c: number): number
	return hash4(seed, a, b, c) / TWO32
end

function Noise.Gauss(seed: number, a: number, b: number, c: number): number
	-- Summe von 3 Uniforms in [−1, 1): Varianz 3 · 1/3 = 1, Bereich (−3, 3)
	return uni(seed, a, b, c) + uni(seed, a, b + 7919, c) + uni(seed, a, b + 15887, c)
end

function Noise.White(seed: number, fid: number, t: number): number
	return uni(seed, fid, 9001, t) + uni(seed, fid, 9002, t) + uni(seed, fid, 9003, t)
end

-- ---------------------------------------------------------------------
-- 2) VALUE-NOISE (14 Oktaven, Perioden 2 s … 16.384 s, Amplitude √Periode, oberste zwei ×0,6)
-- ---------------------------------------------------------------------
local K, P0 = 14, 2
local PERIOD: { number } = table.create(K)
local AMP: { number } = table.create(K)
for k = 1, K do
	PERIOD[k] = P0 * 2 ^ (k - 1)
	AMP[k] = math.sqrt(PERIOD[k]) * (if k == K then 0.6 elseif k == K - 1 then 0.6 else 1)
end

Noise.K = K
Noise.P0 = P0
Noise.PERIOD = PERIOD
Noise.AMP = AMP

export type Field = {
	Seed: number,
	Id: number,
	KMin: number,
	KMax: number,
	Norm: number,
	Ph: { number },
	N: { number },
	V0: { number },
	V1: { number },
}

-- Var(uni) = 1/3, Mittel der Lerp-Varianz = 2/3 -> INV_NORM wie MARKET §5.2 (für Teil-Oktaven entsprechend)
local function invNorm(kMin: number, kMax: number): number
	local sumSq = 0
	for k = kMin, kMax do
		sumSq += AMP[k] ^ 2
	end
	return 1 / math.sqrt(sumSq * (2 / 3) * (1 / 3))
end

function Noise.NewField(seed: number, fid: number, kMin: number?, kMax: number?): Field
	local lo = math.clamp(math.floor(kMin or 1), 1, K)
	local hi = math.clamp(math.floor(kMax or K), lo, K)
	local f: Field = {
		Seed = seed,
		Id = fid,
		KMin = lo,
		KMax = hi,
		Norm = invNorm(lo, hi),
		Ph = table.create(K, 0),
		N = table.create(K, -1),
		V0 = table.create(K, 0),
		V1 = table.create(K, 0),
	}
	for k = lo, hi do
		f.Ph[k] = hash4(seed, fid, k - 1, 777) % PERIOD[k] -- Phasenversatz; Oktaven-Index im Hash 0-basiert
		f.N[k] = -1
	end
	return f
end

-- Sequentiell (Live, Offline-Abgleich) praktisch nur Lerps; Random-Access rechnet beim Sprung 2 Hashes je Oktave
function Noise.FieldAt(f: Field, t: number): number
	local sum = 0
	local seed, id = f.Seed, f.Id
	local ph, nn, v0, v1 = f.Ph, f.N, f.V0, f.V1
	for k = f.KMin, f.KMax do
		local u = (t + ph[k]) / PERIOD[k]
		local n = u // 1
		if n ~= nn[k] then
			v0[k] = if n == nn[k] + 1 then v1[k] else uni(seed, id, k - 1, n)
			v1[k] = uni(seed, id, k - 1, n + 1)
			nn[k] = n
		end
		sum += AMP[k] * (v0[k] + (v1[k] - v0[k]) * (u - n))
	end
	return sum * f.Norm
end

return Noise
