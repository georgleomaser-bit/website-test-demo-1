-- The run lane is split into four themed zones. The farther you run, the rarer and
-- bigger the animals, the faster the guards and the longer the eggs take to hatch.

local Zones = {
	{
		Id = 1,
		Name = "Sunny Meadow",
		Floor = Color3.fromRGB(110, 205, 70),
		FloorAlt = Color3.fromRGB(95, 190, 60),
		Wall = Color3.fromRGB(205, 120, 95),
		WallTop = Color3.fromRGB(90, 185, 70),
		Accent = Color3.fromRGB(255, 230, 90),
		GuardSpeed = 24,
		GuardColor = Color3.fromRGB(120, 90, 60),
		EggColor = Color3.fromRGB(250, 240, 200),
		EggHatchSeconds = 30,
	},
	{
		Id = 2,
		Name = "Red Canyon",
		Floor = Color3.fromRGB(230, 190, 120),
		FloorAlt = Color3.fromRGB(220, 175, 105),
		Wall = Color3.fromRGB(190, 95, 70),
		WallTop = Color3.fromRGB(235, 200, 130),
		Accent = Color3.fromRGB(255, 120, 60),
		GuardSpeed = 42,
		GuardColor = Color3.fromRGB(150, 70, 40),
		EggColor = Color3.fromRGB(255, 170, 90),
		EggHatchSeconds = 75,
	},
	{
		Id = 3,
		Name = "Frost Peaks",
		Floor = Color3.fromRGB(225, 240, 255),
		FloorAlt = Color3.fromRGB(205, 225, 250),
		Wall = Color3.fromRGB(120, 160, 210),
		WallTop = Color3.fromRGB(245, 250, 255),
		Accent = Color3.fromRGB(120, 220, 255),
		GuardSpeed = 66,
		GuardColor = Color3.fromRGB(90, 130, 190),
		EggColor = Color3.fromRGB(170, 230, 255),
		EggHatchSeconds = 180,
	},
	{
		Id = 4,
		Name = "Lava Rift",
		Floor = Color3.fromRGB(70, 55, 60),
		FloorAlt = Color3.fromRGB(85, 60, 60),
		Wall = Color3.fromRGB(45, 35, 40),
		WallTop = Color3.fromRGB(255, 100, 30),
		Accent = Color3.fromRGB(255, 80, 20),
		GuardSpeed = 100,
		GuardColor = Color3.fromRGB(60, 20, 20),
		EggColor = Color3.fromRGB(255, 90, 50),
		EggHatchSeconds = 420,
	},
}

return Zones
