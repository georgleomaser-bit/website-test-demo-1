--[[
	Upgrades (ModuleScript)
	Location: ReplicatedStorage/Shared/Config/Upgrades

	Shop upgrades bought with Sparks. These are reset on Ascension (except where
	an Ascension perk keeps them). Cost for level L -> L+1 is
	    BaseCost * Growth ^ L
	Value(level) returns the total stat contribution at that level.
	Mode "add" sums into the stat; Mode "mult" multiplies it.
	Display controls how the preview is formatted:
	    "flat"  -> +12        "pct" -> +40%       "mult" -> x2.50
	    "cps"   -> 4.5/s      "chance" -> 12.0%   "persec" -> +1.2K/s
]]

export type Upgrade = {
	Id: string,
	Name: string,
	Icon: string,
	Description: string,
	Tier: number,
	Order: number,
	MaxLevel: number,
	BaseCost: number,
	Growth: number,
	Currency: string,
	Stat: string,
	Mode: string,
	Display: string,
	Value: (level: number) -> number,
}

local Upgrades = {}

Upgrades.Tiers = {
	{ Tier = 1, Name = "Tier I — Fundamentals", Requirement = nil },
	{ Tier = 2, Name = "Tier II — Engineering", Requirement = { Level = 8 } },
	{ Tier = 3, Name = "Tier III — Mastery", Requirement = { Rebirths = 1 } },
}

Upgrades.List = {
	{
		Id = "click_power",
		Name = "Reinforced Switch",
		Icon = "👆",
		Description = "Adds base power to every press. Power per level doubles every 25 levels.",
		Tier = 1,
		Order = 1,
		MaxLevel = 500,
		BaseCost = 15,
		Growth = 1.15,
		Currency = "Sparks",
		Stat = "clickFlat",
		Mode = "add",
		Display = "flat",
		Value = function(level: number): number
			local total = 0
			-- closed form of sum_{i=1..level} 2^floor(i/25)
			local full = math.floor(level / 25)
			for block = 0, full - 1 do
				local count = if block == 0 then 24 else 25
				total += count * 2 ^ block
			end
			local start = if full == 0 then 1 else full * 25
			total += (level - start + 1) * 2 ^ full
			return if level <= 0 then 0 else total
		end,
	},
	{
		Id = "generator",
		Name = "Spark Generator",
		Icon = "🔋",
		Description = "Produces Sparks every second, even while you rest.",
		Tier = 1,
		Order = 2,
		MaxLevel = 300,
		BaseCost = 60,
		Growth = 1.16,
		Currency = "Sparks",
		Stat = "passiveFlat",
		Mode = "add",
		Display = "persec",
		Value = function(level: number): number
			return 1.5 * level * 1.06 ^ level
		end,
	},
	{
		Id = "amplifier",
		Name = "Amplifier",
		Icon = "📢",
		Description = "Multiplies ALL Sparks you earn by ×1.1 per level.",
		Tier = 1,
		Order = 3,
		MaxLevel = 60,
		BaseCost = 400,
		Growth = 1.6,
		Currency = "Sparks",
		Stat = "sparksMult",
		Mode = "mult",
		Display = "mult",
		Value = function(level: number): number
			return 1.1 ^ level
		end,
	},
	{
		Id = "precision",
		Name = "Precision Sensor",
		Icon = "🎯",
		Description = "+1% critical press chance per level.",
		Tier = 1,
		Order = 4,
		MaxLevel = 40,
		BaseCost = 200,
		Growth = 1.45,
		Currency = "Sparks",
		Stat = "critChance",
		Mode = "add",
		Display = "chance",
		Value = function(level: number): number
			return 0.01 * level
		end,
	},
	{
		Id = "auto_presser",
		Name = "Auto-Presser",
		Icon = "🤖",
		Description = "A tiny robot that presses the button for you (+0.5 presses/s per level).",
		Tier = 2,
		Order = 5,
		MaxLevel = 20,
		BaseCost = 1500,
		Growth = 2.0,
		Currency = "Sparks",
		Stat = "autoRate",
		Mode = "add",
		Display = "cps",
		Value = function(level: number): number
			return 0.5 * level
		end,
	},
	{
		Id = "fortune",
		Name = "Fortune Coil",
		Icon = "🍀",
		Description = "+4% Luck per level. Luck improves crate rarity odds.",
		Tier = 2,
		Order = 6,
		MaxLevel = 50,
		BaseCost = 800,
		Growth = 1.5,
		Currency = "Sparks",
		Stat = "luck",
		Mode = "add",
		Display = "pct",
		Value = function(level: number): number
			return 0.04 * level
		end,
	},
	{
		Id = "overload",
		Name = "Overload Capacitor",
		Icon = "💥",
		Description = "+0.25× critical press multiplier per level.",
		Tier = 2,
		Order = 7,
		MaxLevel = 20,
		BaseCost = 5000,
		Growth = 1.7,
		Currency = "Sparks",
		Stat = "critPower",
		Mode = "add",
		Display = "flatx",
		Value = function(level: number): number
			return 0.25 * level
		end,
	},
	{
		Id = "treasure_sense",
		Name = "Treasure Sense",
		Icon = "🧭",
		Description = "+1.5% chance per level for a crate to drop a bonus item.",
		Tier = 3,
		Order = 8,
		MaxLevel = 30,
		BaseCost = 5e5,
		Growth = 1.6,
		Currency = "Sparks",
		Stat = "chestBonus",
		Mode = "add",
		Display = "chance",
		Value = function(level: number): number
			return 0.015 * level
		end,
	},
	{
		Id = "lucky_star",
		Name = "Lucky Star",
		Icon = "🌟",
		Description = "+10% golden press chance per level.",
		Tier = 3,
		Order = 9,
		MaxLevel = 30,
		BaseCost = 3e5,
		Growth = 1.55,
		Currency = "Sparks",
		Stat = "goldenPct",
		Mode = "add",
		Display = "pct",
		Value = function(level: number): number
			return 0.1 * level
		end,
	},
	{
		Id = "scholar",
		Name = "Scholar's Lens",
		Icon = "📘",
		Description = "+10% XP from every source per level.",
		Tier = 3,
		Order = 10,
		MaxLevel = 40,
		BaseCost = 2e5,
		Growth = 1.5,
		Currency = "Sparks",
		Stat = "xpPct",
		Mode = "add",
		Display = "pct",
		Value = function(level: number): number
			return 0.1 * level
		end,
	},
}

Upgrades.ById = {}
for _, def in ipairs(Upgrades.List) do
	Upgrades.ById[def.Id] = def
end
table.sort(Upgrades.List, function(a, b)
	return a.Order < b.Order
end)

-- Buy amount options shown in the shop. "max" buys as many as affordable.
Upgrades.BuyAmounts = { 1, 10, "max" }

function Upgrades.get(id: string): Upgrade?
	return Upgrades.ById[id]
end

function Upgrades.tierInfo(tier: number)
	return Upgrades.Tiers[tier]
end

return Upgrades
