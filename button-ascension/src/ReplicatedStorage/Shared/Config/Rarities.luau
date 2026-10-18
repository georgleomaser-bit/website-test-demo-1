--[[
	Rarities (ModuleScript)
	Location: ReplicatedStorage/Shared/Config/Rarities

	Rarity tiers in ascending order. Index is used for comparisons, luck scaling
	and sorting. SellGems and Bonus are the base values for tier-1 items; crate
	tier multipliers are applied in Items.
]]

export type Rarity = {
	Id: string,
	Index: number,
	Name: string,
	Color: Color3,
	Glow: Color3,
	SellGems: number,
	Bonus: number,
	LuckPower: number,
}

local Rarities = {}

Rarities.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

Rarities.ById = {
	Common = {
		Id = "Common",
		Index = 1,
		Name = "Common",
		Color = Color3.fromRGB(176, 186, 204),
		Glow = Color3.fromRGB(120, 130, 150),
		SellGems = 1,
		Bonus = 0.02,
		LuckPower = 0,
	},
	Uncommon = {
		Id = "Uncommon",
		Index = 2,
		Name = "Uncommon",
		Color = Color3.fromRGB(74, 222, 128),
		Glow = Color3.fromRGB(30, 140, 70),
		SellGems = 3,
		Bonus = 0.04,
		LuckPower = 0.2,
	},
	Rare = {
		Id = "Rare",
		Index = 3,
		Name = "Rare",
		Color = Color3.fromRGB(64, 156, 255),
		Glow = Color3.fromRGB(20, 80, 190),
		SellGems = 8,
		Bonus = 0.08,
		LuckPower = 0.5,
	},
	Epic = {
		Id = "Epic",
		Index = 4,
		Name = "Epic",
		Color = Color3.fromRGB(176, 92, 255),
		Glow = Color3.fromRGB(100, 30, 190),
		SellGems = 25,
		Bonus = 0.15,
		LuckPower = 0.8,
	},
	Legendary = {
		Id = "Legendary",
		Index = 5,
		Name = "Legendary",
		Color = Color3.fromRGB(255, 180, 40),
		Glow = Color3.fromRGB(200, 110, 0),
		SellGems = 100,
		Bonus = 0.3,
		LuckPower = 1.0,
	},
	Mythic = {
		Id = "Mythic",
		Index = 6,
		Name = "Mythic",
		Color = Color3.fromRGB(255, 64, 112),
		Glow = Color3.fromRGB(190, 0, 60),
		SellGems = 500,
		Bonus = 0.6,
		LuckPower = 1.1,
	},
	Secret = {
		Id = "Secret",
		Index = 7,
		Name = "Secret",
		Color = Color3.fromRGB(255, 255, 255),
		Glow = Color3.fromRGB(255, 120, 255),
		SellGems = 3000,
		Bonus = 1.5,
		LuckPower = 0.6,
	},
}

-- Rainbow used to render Secret items.
Rarities.SecretGradient = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 120)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 210, 80)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 255, 170)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 170, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 100, 255)),
})

function Rarities.get(id: string): Rarity?
	return Rarities.ById[id]
end

function Rarities.index(id: string): number
	local r = Rarities.ById[id]
	return if r then r.Index else 0
end

function Rarities.byIndex(index: number): Rarity?
	local id = Rarities.Order[index]
	return if id then Rarities.ById[id] else nil
end

return Rarities
