--!strict
-- =====================================================================
--  CLUTCH CLASH – Schadensrechnung (Shared/Damage)
--  Besitzer: WP3 (Kampf Server & Treffer-Mathematik). Vertrag: DESIGN.md C6.2, B11.1.
--  Reines Modul – Server (Wertung) und Client (Vorschau, Training-DPS) rechnen identisch.
--
--  Öffentliche API:
--    Damage.Compute(def, dist, region, rules?): number
--        base = lerp(Damage, Damage × MinMult, clamp((dist − FalloffStart) / (FalloffEnd − FalloffStart), 0, 1))
--        × (Kopf: HeadMult, Körper: 1.0) × rules.DamageMult; rules.HeadOnly -> Körper = 0.
--        Schrot-Waffen: Wert gilt pro Schrot (der Server summiert die Treffer).
--    Damage.Splash(def, dist): number
--        linear SplashMax (Mitte) -> SplashMin (Rand bei Projectile.Radius), außerhalb 0.
--        Selbstschaden (SelfMult) und rules.DamageMult rechnet der Aufrufer.
--    Damage.Falloff(def, dist): number      nur der Abfall-Faktor 0..1 (0 = voller Schaden)
--  Werte werden NICHT gerundet (die Anzeige rundet).
-- =====================================================================

local Types = require(script.Parent:WaitForChild("Types"))

local Damage = {}

local function finiteOr(n: number?, default: number): number
	if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
		return default
	end
	return n
end

local function lerp(a: number, b: number, alpha: number): number
	return a + (b - a) * alpha
end

function Damage.Falloff(def: Types.WeaponDef, dist: number): number
	local d = math.max(0, finiteOr(dist, 0))
	local s = finiteOr(def.FalloffStart, 0)
	local e = finiteOr(def.FalloffEnd, s)
	if e <= s then
		return if d >= e and d > s then 1 else 0
	end
	return math.clamp((d - s) / (e - s), 0, 1)
end

function Damage.Compute(
	def: Types.WeaponDef,
	dist: number,
	region: "Head" | "Body",
	rules: Types.ContextRules?
): number
	local damage = math.max(0, finiteOr(def.Damage, 0))
	local minMult = finiteOr(def.MinMult, 1)
	local base = lerp(damage, damage * minMult, Damage.Falloff(def, dist))
	if region == "Head" then
		base *= math.max(0, finiteOr(def.HeadMult, 1))
	elseif rules and rules.HeadOnly then
		return 0
	end
	if rules then
		base *= math.max(0, finiteOr(rules.DamageMult, 1))
	end
	return math.max(0, base)
end

function Damage.Splash(def: Types.WeaponDef, dist: number): number
	local proj = def.Projectile
	if not proj then
		return 0
	end
	local radius = finiteOr(proj.Radius, 0)
	local d = math.max(0, finiteOr(dist, math.huge))
	if radius <= 0 or d >= radius then
		return 0
	end
	local maxDamage = math.max(0, finiteOr(proj.SplashMax, 0))
	local minDamage = math.max(0, finiteOr(proj.SplashMin, 0))
	return lerp(maxDamage, minDamage, d / radius)
end

return Damage
