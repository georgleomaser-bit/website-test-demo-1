-- =====================================================================
--  AKYTEX TYCOON – Luau-CLI-Test für Server/Market/Noise (ohne Roblox)
--  Besitzer: WP3 (Markt-Engine). DESIGN.md §D WP3 "Tests": Testvektoren MARKET §19.2 exakt, mul32 gegen eine
--  unabhängige Referenz (8-Bit-Zerlegung), Feld-Statistik (Mittel ≈ 0, Varianz ≈ 1), Random-Access == sequentiell,
--  White ≈ N(0, 1), Determinismus (gleiche Eingabe -> gleiche Zahl).
--  Start (im Projektordner):  <scratchpad>/luau-build/luau tests/noise.test.luau
-- =====================================================================

local Noise = require("../src/server/Market/Noise")

local passed, failed = 0, 0
local failures: { string } = {}

local function check(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		table.insert(failures, name .. ": " .. tostring(err))
	end
end

local function eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(("%s erwartet %s, bekommen %s"):format(label or "Wert", tostring(expected), tostring(actual)), 2)
	end
end

local function near(actual: number, expected: number, tolerance: number, label: string?)
	if math.abs(actual - expected) > tolerance then
		error(("%s erwartet ≈%s, bekommen %s"):format(label or "Wert", tostring(expected), tostring(actual)), 2)
	end
end

-- unabhängige Referenz: (a · b) mod 2^32 über 8-Bit-Stücke (alle Zwischenwerte < 2^53)
local function refMul32(a: number, b: number): number
	local result = 0
	for i = 0, 3 do
		local ai = (a // 256 ^ i) % 256
		if ai ~= 0 then
			for j = 0, 3 - i do
				local bj = (b // 256 ^ j) % 256
				result = (result + (ai * bj % 256 ^ (4 - i - j)) * 256 ^ (i + j)) % 4294967296
			end
		end
	end
	return result
end

-- kleiner eigener LCG nur für Testeingaben (nicht im Spiel)
local lcgState = 12345
local function nextU32(): number
	lcgState = (lcgState * 1103515245 + 12345) % 2147483648
	local hi = lcgState
	lcgState = (lcgState * 1103515245 + 12345) % 2147483648
	return (hi * 2 + lcgState % 2) % 4294967296
end

-- ---------------------------------------------------------------------
check("Testvektoren MARKET §19.2 (hash4 + uni)", function()
	local vectors = {
		{ 123456, 1, 0, 0, 3076564673, 0.432637066114694 },
		{ 123456, 1, 0, 1, 1222392628, -0.430779075250030 },
		{ 123456, 1, 13, 7, 3917177298, 0.824077823199332 },
		{ 987654321, 104, 5, 123456789, 4043101596, 0.882715893909335 },
		{ 2147483647, 9, 9001, 86399, 2536699204, 0.181242616847157 },
	}
	for _, v in ipairs(vectors) do
		eq(Noise.Hash4(v[1], v[2], v[3], v[4]), v[5], "hash4" .. table.concat({ v[1], v[2], v[3], v[4] }, ","))
		near(Noise.Uni(v[1], v[2], v[3], v[4]), v[6], 1e-12, "uni")
	end
end)

check("mul32 == Referenz (Randwerte + 20.000 Zufallspaare)", function()
	local edges =
		{ 0, 1, 2, 65535, 65536, 65537, 0x7FEB352D, 0x846CA68B, 0x9E3779B9, 2147483647, 2147483648, 4294967295 }
	for _, a in ipairs(edges) do
		for _, b in ipairs(edges) do
			eq(Noise.Mul32(a, b), refMul32(a, b), ("mul32(%d, %d)"):format(a, b))
		end
	end
	for _ = 1, 20000 do
		local a, b = nextU32(), nextU32()
		local got = Noise.Mul32(a, b)
		if got ~= refMul32(a, b) then
			error(("mul32(%d, %d) = %d, Referenz %d"):format(a, b, got, refMul32(a, b)))
		end
	end
end)

check("h32 bleibt 32-Bit und ist deterministisch", function()
	for _ = 1, 2000 do
		local x = nextU32()
		local h = Noise.H32(x)
		assert(h >= 0 and h < 4294967296 and h % 1 == 0, "h32 außerhalb 32 Bit")
		eq(Noise.H32(x), h, "h32 deterministisch")
	end
	eq(Noise.H32(0), 0, "h32(0)")
end)

check("Uni in [−1, 1), Rnd in [0, 1)", function()
	for k = 1, 5000 do
		local u = Noise.Uni(777, 3, k, k * 7)
		local r = Noise.Rnd(777, 3, k, k * 7)
		assert(u >= -1 and u < 1, "Uni außerhalb")
		assert(r >= 0 and r < 1, "Rnd außerhalb")
	end
end)

check("Feld: Mittel ≈ 0, Varianz ≈ 1 (200.000 Ticks)", function()
	local f = Noise.NewField(123456, 1)
	local n = 200000
	local s, s2 = 0, 0
	for t = 0, n - 1 do
		local v = Noise.FieldAt(f, t)
		s += v
		s2 += v * v
	end
	local mean = s / n
	local std = math.sqrt(s2 / n - mean * mean)
	near(mean, 0, 0.35, "Mittel")
	near(std, 1, 0.35, "Std")
end)

check("Feld: Random-Access == sequentiell (bitgleich)", function()
	local seqField = Noise.NewField(42, 117)
	local values: { number } = {}
	for t = 1000, 6000 do
		values[t] = Noise.FieldAt(seqField, t)
	end
	local ra = Noise.NewField(42, 117)
	for _ = 1, 3000 do
		local t = 1000 + nextU32() % 5001
		eq(Noise.FieldAt(ra, t), values[t], "Feld bei " .. t)
	end
end)

check("Teil-Oktaven-Feld (Regime) normiert und stetig", function()
	local f = Noise.NewField(9, 2, 10, 14)
	local s2, n = 0, 0
	local prev = Noise.FieldAt(f, 0)
	local maxStep = 0
	for t = 1, 100000 do
		local v = Noise.FieldAt(f, t)
		s2 += v * v
		n += 1
		maxStep = math.max(maxStep, math.abs(v - prev))
		prev = v
	end
	assert(math.sqrt(s2 / n) < 2.5, "Regime-Feld zu groß")
	assert(maxStep < 0.05, "Regime-Feld springt")
end)

check("White ≈ N(0, 1) und deterministisch", function()
	local n = 30000
	local s, s2 = 0, 0
	for t = 1, n do
		local w = Noise.White(5, 201, t)
		s += w
		s2 += w * w
		assert(w > -3 and w < 3, "White außerhalb (−3, 3)")
	end
	near(s / n, 0, 0.05, "Mittel")
	near(math.sqrt(s2 / n), 1, 0.05, "Std")
	eq(Noise.White(5, 201, 99), Noise.White(5, 201, 99), "deterministisch")
end)

check("Gauss: Varianz ≈ 1", function()
	local n = 20000
	local s2 = 0
	for k = 1, n do
		local g = Noise.Gauss(11, 0xEA1, k, 3)
		s2 += g * g
	end
	near(math.sqrt(s2 / n), 1, 0.05, "Std")
end)

-- ---------------------------------------------------------------------
for _, failure in ipairs(failures) do
	print("FAIL " .. failure)
end
print(("noise.test: %d/%d PASS"):format(passed, passed + failed))
if failed > 0 then
	error(("%d Test(s) fehlgeschlagen"):format(failed))
end
