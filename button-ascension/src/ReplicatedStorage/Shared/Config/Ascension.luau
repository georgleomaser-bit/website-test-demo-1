--[[
	Ascension (ModuleScript)
	Location: ReplicatedStorage/Shared/Config/Ascension

	Permanent upgrades bought with Prisms (earned by ascending).
	These are NEVER reset. Cost for level L -> L+1 is
	    ceil(BaseCost * Growth ^ L)
]]

export type AscensionUpgrade = {
	Id: string,
	Name: string,
	Icon: string,
	Description: string,
	Order: number,
	MaxLevel: number,
	BaseCost: number,
	Growth: number,
	Stat: string,
	Mode: string,
	Display: string,
	Value: (level: number) -> number,
}

local Ascension = {}

Ascension.List = {
	{
		Id = "eternal_power",
		Name = "Eternal Power",
		Icon = "♾️",
		Description = "+25% Sparks from every source per level. Permanent.",
		Order = 1,
		MaxLevel = 100,
		BaseCost = 2,
		Growth = 1.3,
		Stat = "sparksMult",
		Mode = "mult",
		Display = "mult",
		Value = function(level: number): number
			return 1 + 0.25 * level
		end,
	},
	{
		Id = "head_start",
		Name = "Head Start",
		Icon = "🏁",
		Description = "Begin every run with bonus Sparks.",
		Order = 2,
		MaxLevel = 8,
		BaseCost = 3,
		Growth = 2,
		Stat = "startSparks",
		Mode = "add",
		Display = "flat",
		Value = function(level: number): number
			return if level <= 0 then 0 else 500 * 8 ^ (level - 1)
		end,
	},
	{
		Id = "keep_auto",
		Name = "Loyal Robots",
		Icon = "🤖",
		Description = "Keep your Auto-Presser levels when you ascend.",
		Order = 3,
		MaxLevel = 1,
		BaseCost = 12,
		Growth = 1,
		Stat = "keepAuto",
		Mode = "add",
		Display = "unlock",
		Value = function(level: number): number
			return level
		end,
	},
	{
		Id = "prism_luck",
		Name = "Prismatic Luck",
		Icon = "🍀",
		Description = "+10% Luck per level.",
		Order = 4,
		MaxLevel = 20,
		BaseCost = 3,
		Growth = 1.5,
		Stat = "luck",
		Mode = "add",
		Display = "pct",
		Value = function(level: number): number
			return 0.1 * level
		end,
	},
	{
		Id = "extra_slot",
		Name = "Deep Pockets",
		Icon = "🎒",
		Description = "+1 item equip slot per level.",
		Order = 5,
		MaxLevel = 3,
		BaseCost = 10,
		Growth = 3,
		Stat = "equipSlots",
		Mode = "add",
		Display = "flat",
		Value = function(level: number): number
			return level
		end,
	},
	{
		Id = "prism_yield",
		Name = "Prism Refinery",
		Icon = "🔷",
		Description = "+10% Prisms from every ascension per level.",
		Order = 6,
		MaxLevel = 25,
		BaseCost = 4,
		Growth = 1.45,
		Stat = "prismPct",
		Mode = "add",
		Display = "pct",
		Value = function(level: number): number
			return 0.1 * level
		end,
	},
	{
		Id = "crate_discount",
		Name = "Crate Broker",
		Icon = "🏷️",
		Description = "-3% Spark crate prices per level.",
		Order = 7,
		MaxLevel = 10,
		BaseCost = 5,
		Growth = 1.6,
		Stat = "chestDiscount",
		Mode = "add",
		Display = "pct",
		Value = function(level: number): number
			return 0.03 * level
		end,
	},
	{
		Id = "night_owl",
		Name = "Night Owl",
		Icon = "🦉",
		Description = "+1 hour of offline earnings and +5% offline rate per level.",
		Order = 8,
		MaxLevel = 6,
		BaseCost = 4,
		Growth = 1.7,
		Stat = "offlineHours",
		Mode = "add",
		Display = "hours",
		Value = function(level: number): number
			return level
		end,
	},
	{
		Id = "combo_mastery",
		Name = "Combo Mastery",
		Icon = "🔥",
		Description = "+20 combo cap per level.",
		Order = 9,
		MaxLevel = 5,
		BaseCost = 6,
		Growth = 2,
		Stat = "comboCap",
		Mode = "add",
		Display = "flat",
		Value = function(level: number): number
			return 20 * level
		end,
	},
}

Ascension.ById = {}
for _, def in ipairs(Ascension.List) do
	Ascension.ById[def.Id] = def
end
table.sort(Ascension.List, function(a, b)
	return a.Order < b.Order
end)

-- Night Owl also raises the offline rate; Formulas reads this.
Ascension.OfflineRatePerNightOwl = 0.05

function Ascension.get(id: string): AscensionUpgrade?
	return Ascension.ById[id]
end

return Ascension
