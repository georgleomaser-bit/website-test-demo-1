-- Treadmills stand in every player's base. Stand on one to train Speed.
-- Gain = Speed per second before multipliers. Treadmills are bought in order with Cash.

local function c(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local Treadmills = {
	{ Name = "Wooden", Gain = 1, Cost = 0, Color = c(160, 110, 70) },
	{ Name = "Stone", Gain = 6, Cost = 300, Color = c(140, 140, 150) },
	{ Name = "Iron", Gain = 40, Cost = 4000, Color = c(190, 195, 205) },
	{ Name = "Gold", Gain = 300, Cost = 60000, Color = c(255, 200, 50) },
	{ Name = "Diamond", Gain = 2500, Cost = 1.2e6, Color = c(110, 230, 255) },
	{ Name = "Emerald", Gain = 25000, Cost = 3e7, Color = c(60, 220, 120) },
	{ Name = "Ruby", Gain = 3e5, Cost = 9e8, Color = c(230, 40, 70) },
	{ Name = "Galaxy", Gain = 4e6, Cost = 3e10, Color = c(130, 70, 255) },
}

-- The VIP treadmill (VIP game pass) trains at this many times your best owned treadmill.
Treadmills.VIPGainFactor = 3

return Treadmills
