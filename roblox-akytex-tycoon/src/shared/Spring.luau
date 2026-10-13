--!strict
-- =====================================================================
--  AKYTEX TYCOON – Frame-unabhängige Feder (Shared/Spring)
--  Besitzer: WP1 (Kern & Plattform). CC-Kopie 1:1 (REUSE §3.2). Für UI-Federn (nur .X für Skalare),
--  Kamerafahrten, schwebende Roboter, Aufzug, Zähler (iOS-Bewegung, Spring.new(v, 25–30, 0.58)).
--
--  Öffentliche API (DESIGN.md §C6.1):
--    Spring.new(initial: Vector3, speed: number, damper: number): SpringObj
--    spring:Step(dt): Vector3        dt wird auf 0..1/30 geklemmt, intern feste Unterschritte (≤ 1/240 s)
--    spring:Impulse(v: Vector3)      addiert v zur Geschwindigkeit (z. B. Druck-Feedback)
--    spring:SetTarget(v: Vector3)    neues Ziel (Ruhelage)
--  Felder (lesbar/schreibbar): Position, Velocity, Target, Speed, Damper
--  speed = Eigenfrequenz (rad/s, größer = schneller), damper = Dämpfung (1 = kritisch, < 1 schwingt nach)
-- =====================================================================

local Spring = {}

export type SpringObj = {
	Position: Vector3,
	Velocity: Vector3,
	Target: Vector3,
	Speed: number,
	Damper: number,
	Step: (self: SpringObj, dt: number) -> Vector3,
	Impulse: (self: SpringObj, v: Vector3) -> (),
	SetTarget: (self: SpringObj, v: Vector3) -> (),
}

local MAX_DT = 1 / 30
local SUB_STEP = 1 / 240
local MAX_SUB_STEPS = 8 -- 1/30 ÷ 1/240

local function finite(n: number, fallback: number): number
	if n ~= n or n == math.huge or n == -math.huge then
		return fallback
	end
	return n
end

local function finiteVector(v: Vector3): boolean
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < math.huge
end

local function step(self: SpringObj, dt: number): Vector3
	local total = math.clamp(finite(dt, 0), 0, MAX_DT)
	if total <= 0 then
		return self.Position
	end
	local steps = math.clamp(math.ceil(total / SUB_STEP), 1, MAX_SUB_STEPS)
	local h = total / steps
	local speed = math.max(0, finite(self.Speed, 0))
	local damper = math.max(0, finite(self.Damper, 1))
	local k = speed * speed -- Federkonstante
	local c = 2 * damper * speed -- Dämpfung
	local position, velocity, target = self.Position, self.Velocity, self.Target
	for _ = 1, steps do
		-- semi-implizites Euler-Verfahren: stabil bei kleinen festen Schritten
		local acceleration = (target - position) * k - velocity * c
		velocity += acceleration * h
		position += velocity * h
	end
	if not (finiteVector(position) and finiteVector(velocity)) then
		-- Sicherheitsnetz: nie NaN in Kamera/UI schreiben
		position, velocity = target, Vector3.zero
	end
	self.Position = position
	self.Velocity = velocity
	return position
end

local function impulse(self: SpringObj, v: Vector3)
	if finiteVector(v) then
		self.Velocity += v
	end
end

local function setTarget(self: SpringObj, v: Vector3)
	if finiteVector(v) then
		self.Target = v
	end
end

function Spring.new(initial: Vector3, speed: number, damper: number): SpringObj
	local start = if finiteVector(initial) then initial else Vector3.zero
	local obj: SpringObj = {
		Position = start,
		Velocity = Vector3.zero,
		Target = start,
		Speed = math.max(0, finite(speed, 10)),
		Damper = math.max(0, finite(damper, 1)),
		Step = step,
		Impulse = impulse,
		SetTarget = setTarget,
	}
	return obj
end

return Spring
