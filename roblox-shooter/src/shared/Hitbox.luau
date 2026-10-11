--!strict
-- =====================================================================
--  CLUTCH CLASH – Analytische Hitboxen (Shared/Hitbox)
--  Besitzer: WP3 (Kampf Server & Treffer-Mathematik). Vertrag: DESIGN.md C6.2, B13.2, C10.
--  Reines Modul. Feste Größe für JEDEN Avatar – nur aus HRP-CFrame + Kopf-Position:
--    Kopf   = Kugel um head, Radius headRadius (+ tol)
--    Körper = OBB aus root × CFrame.new(BodyOffset), Halbmaße BodyHalf (+ tol je Achse)
--  Region = näherer Eintrittspunkt; der Kopf gewinnt einen Gleichstand innerhalb HeadTieBreak (0.5 Studs).
--
--  Öffentliche API:
--    Hitbox.Ray(origin, dir, range, root, head, headRadius, tol): (("Head" | "Body")?, number?)
--        Strahl gegen beide Formen; Rückgabe Region + Entfernung des Eintrittspunkts (<= range), sonst nil.
--        Liegt origin schon in einer Form, ist die Entfernung 0.
--    Hitbox.PointDistance(p, root, head): number
--        Abstand von p zum nächsten Hitbox-Punkt (Kopf-Radius HeadRadius, Körper ohne Toleranz), >= 0.
--    Hitbox.BodyCFrame(root): CFrame      Mitte der Körper-OBB
--  Werte (HeadRadius, BodyOffset, BodyHalf, HeadTieBreak) kommen aus Config.Combat.
-- =====================================================================

local Hitbox = {}

-- Startwerte = Config.Combat (zur Laufzeit von dort gelesen)
local headRadiusBase = 0.8
local bodyOffset = Vector3.new(0, -1, 0)
local bodyHalf = Vector3.new(1.5, 2.0, 0.8)
local headTieBreak = 0.5

do
	local ok, combat = pcall(function()
		return require(script.Parent:WaitForChild("Config"):WaitForChild("Combat"))
	end)
	if ok and type(combat) == "table" then
		local c = combat :: any
		if type(c.HeadRadius) == "number" and c.HeadRadius > 0 then
			headRadiusBase = c.HeadRadius
		end
		if typeof(c.BodyOffset) == "Vector3" then
			bodyOffset = c.BodyOffset
		end
		if typeof(c.BodyHalf) == "Vector3" then
			bodyHalf = c.BodyHalf
		end
		if type(c.HeadTieBreak) == "number" and c.HeadTieBreak >= 0 then
			headTieBreak = c.HeadTieBreak
		end
	end
end

local EPS = 1e-9

local function finite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function finiteVec(v: Vector3): boolean
	return finite(v.X) and finite(v.Y) and finite(v.Z)
end

function Hitbox.BodyCFrame(root: CFrame): CFrame
	return root * CFrame.new(bodyOffset)
end

-- Strahl (Einheitsrichtung d) gegen Kugel: Eintrittsentfernung oder nil
local function raySphere(o: Vector3, d: Vector3, center: Vector3, radius: number): number?
	local oc = o - center
	local b = oc:Dot(d)
	local c = oc:Dot(oc) - radius * radius
	if c <= 0 then
		return 0 -- Ursprung liegt in der Kugel
	end
	if b > 0 then
		return nil -- Kugel liegt hinter dem Ursprung
	end
	local disc = b * b - c
	if disc < 0 then
		return nil
	end
	return math.max(0, -b - math.sqrt(disc))
end

-- eine Achse des Slab-Tests: neues (tmin, tmax) oder nil, wenn der Strahl die Platte verfehlt
local function slab(ov: number, dv: number, hv: number, tmin: number, tmax: number): (number?, number)
	if math.abs(dv) < EPS then
		if ov < -hv or ov > hv then
			return nil, tmax
		end
		return tmin, tmax
	end
	local t1 = (-hv - ov) / dv
	local t2 = (hv - ov) / dv
	if t1 > t2 then
		t1, t2 = t2, t1
	end
	if t1 > tmin then
		tmin = t1
	end
	if t2 < tmax then
		tmax = t2
	end
	if tmin > tmax then
		return nil, tmax
	end
	return tmin, tmax
end

-- Strahl gegen OBB (Slab-Test im lokalen Raum, ohne Tabellen): Eintrittsentfernung oder nil
local function rayBox(o: Vector3, d: Vector3, box: CFrame, half: Vector3): number?
	local lo = box:PointToObjectSpace(o)
	local ld = box:VectorToObjectSpace(d)
	local tmin: number? = -math.huge
	local tmax = math.huge
	tmin, tmax = slab(lo.X, ld.X, half.X, tmin :: number, tmax)
	if tmin == nil then
		return nil
	end
	tmin, tmax = slab(lo.Y, ld.Y, half.Y, tmin, tmax)
	if tmin == nil then
		return nil
	end
	tmin, tmax = slab(lo.Z, ld.Z, half.Z, tmin, tmax)
	if tmin == nil or tmax < 0 then
		return nil
	end
	return math.max(0, tmin)
end

function Hitbox.Ray(
	origin: Vector3,
	dir: Vector3,
	range: number,
	root: CFrame,
	head: Vector3,
	headRadius: number,
	tol: number
): (("Head" | "Body")?, number?)
	if not (finiteVec(origin) and finiteVec(dir) and finiteVec(head) and finite(range)) then
		return nil, nil
	end
	local m = dir.Magnitude
	if m < 1e-6 then
		return nil, nil
	end
	local d = dir / m
	local extra = if finite(tol) then math.max(0, tol) else 0
	local r = (if finite(headRadius) then math.max(0, headRadius) else headRadiusBase) + extra
	local maxDist = math.max(0, range)

	local tHead = raySphere(origin, d, head, r)
	if tHead and tHead > maxDist then
		tHead = nil
	end
	local half = bodyHalf + Vector3.new(extra, extra, extra)
	local tBody = rayBox(origin, d, Hitbox.BodyCFrame(root), half)
	if tBody and tBody > maxDist then
		tBody = nil
	end

	if tHead and tBody then
		if tHead <= tBody + headTieBreak then
			return "Head", tHead
		end
		return "Body", tBody
	elseif tHead then
		return "Head", tHead
	elseif tBody then
		return "Body", tBody
	end
	return nil, nil
end

function Hitbox.PointDistance(p: Vector3, root: CFrame, head: Vector3): number
	if not (finiteVec(p) and finiteVec(head)) then
		return math.huge
	end
	local headDist = math.max(0, (p - head).Magnitude - headRadiusBase)
	local box = Hitbox.BodyCFrame(root)
	local lp = box:PointToObjectSpace(p)
	local cx = math.clamp(lp.X, -bodyHalf.X, bodyHalf.X)
	local cy = math.clamp(lp.Y, -bodyHalf.Y, bodyHalf.Y)
	local cz = math.clamp(lp.Z, -bodyHalf.Z, bodyHalf.Z)
	local bodyDist = (lp - Vector3.new(cx, cy, cz)).Magnitude
	return math.min(headDist, bodyDist)
end

return Hitbox
