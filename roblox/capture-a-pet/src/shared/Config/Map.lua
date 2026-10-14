-- World layout. The server builds the whole map from these numbers on start,
-- so the place file can stay empty.
--
--   z <  0 : hub with the six player bases (three on each side of the avenue)
--   z >= 0 : the run lane, split into four zones

local Map = {}

Map.GroundY = 0

Map.Hub = {
	Center = Vector3.new(0, 0, -300),
	Size = Vector3.new(560, 1, 640),
	Spawn = Vector3.new(0, 3, -40),
}

Map.Plot = {
	Size = Vector3.new(170, 1, 180),
	-- centers; plots face the avenue (x = 0)
	Centers = {
		Vector3.new(-125, 0, -120),
		Vector3.new(125, 0, -120),
		Vector3.new(-125, 0, -310),
		Vector3.new(125, 0, -310),
		Vector3.new(-125, 0, -500),
		Vector3.new(125, 0, -500),
	},
	PenColumns = 6,
	PenSpacing = 22,
	MaxPenSlots = 36,
}

Map.Lane = {
	StartZ = 20,
	ZoneLength = 700,
	Width = 110,
	WallHeight = 70,
}

function Map.zoneStartZ(zone: number): number
	return Map.Lane.StartZ + (zone - 1) * Map.Lane.ZoneLength
end

function Map.zoneAt(z: number): number?
	if z < Map.Lane.StartZ then
		return nil
	end
	local zone = math.floor((z - Map.Lane.StartZ) / Map.Lane.ZoneLength) + 1
	if zone > 4 then
		return 4
	end
	return zone
end

return Map
