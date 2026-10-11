--!strict
-- =====================================================================
--  CLUTCH CLASH – Flugbahnen (Shared/Ballistics)
--  Besitzer: WP3 (Kampf Server & Treffer-Mathematik). Vertrag: DESIGN.md C6.2, C11.
--  Reines Modul – Server-Projektile (ProjectileService) und Client-Visuals (CombatFX)
--  benutzen dieselbe Formel, damit die Kugel auf beiden Seiten gleich fliegt.
--  Schwerkraft g wirkt nach −Y (g = 0: gerader Flug, z. B. Raketen).
--
--  Öffentliche API:
--    Ballistics.Position(p0, v, g, t): Vector3                p0 + v·t + ½·(0, −g, 0)·t²
--    Ballistics.Step(p, v, g, dt): (Vector3, Vector3)          neue Position + neue Geschwindigkeit
--    Ballistics.Reflect(v, normal, restitution): Vector3
--        Abprall: Normal-Anteil umgedreht × restitution, Tangential-Anteil × Ballistics.TangentKeep.
--    Ballistics.TangentKeep = 0.8                              Reibung beim Abprall
-- =====================================================================

local Ballistics = {}

Ballistics.TangentKeep = 0.8

local function finiteOr(n: number, default: number): number
	if n ~= n or n == math.huge or n == -math.huge then
		return default
	end
	return n
end

function Ballistics.Position(p0: Vector3, v: Vector3, g: number, t: number): Vector3
	local time = math.max(0, finiteOr(t, 0))
	local grav = finiteOr(g, 0)
	return p0 + v * time + Vector3.new(0, -0.5 * grav * time * time, 0)
end

function Ballistics.Step(p: Vector3, v: Vector3, g: number, dt: number): (Vector3, Vector3)
	local step = math.max(0, finiteOr(dt, 0))
	local grav = finiteOr(g, 0)
	local newP = p + v * step + Vector3.new(0, -0.5 * grav * step * step, 0)
	local newV = v + Vector3.new(0, -grav * step, 0)
	return newP, newV
end

function Ballistics.Reflect(v: Vector3, normal: Vector3, restitution: number): Vector3
	local m = normal.Magnitude
	if m ~= m or m < 1e-6 then
		return v * math.clamp(finiteOr(restitution, 0), 0, 1)
	end
	local n = normal / m
	local e = math.clamp(finiteOr(restitution, 0), 0, 1)
	local vn = n * v:Dot(n)
	local vt = v - vn
	return vt * Ballistics.TangentKeep - vn * e
end

return Ballistics
