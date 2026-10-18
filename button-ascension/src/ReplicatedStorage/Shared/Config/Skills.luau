--[[
	Skills (ModuleScript)
	Location: ReplicatedStorage/Shared/Config/Skills

	The skill tree. Nodes are placed on a grid (X right, Y down; the core is 0,0).
	Skill Points come from levelling up, achievements and collection milestones.
	Skills are permanent: they are NOT reset by Ascension (a Gem-priced respec
	refunds every point).

	Requires    = every listed node needs at least rank 1
	RequiresAny = at least one listed node needs rank 1
	Cost        = Skill Points for rank 1; each further rank costs Cost + CostStep * rank
	Effects     = per rank: { Stat, Add = n } adds n per rank; { Stat, Mult = n } multiplies by n per rank
]]

export type SkillEffect = { Stat: string, Add: number?, Mult: number? }
export type SkillNode = {
	Id: string,
	Name: string,
	Icon: string,
	Branch: string,
	Description: string,
	X: number,
	Y: number,
	MaxRank: number,
	Cost: number,
	CostStep: number,
	Requires: { string },
	RequiresAny: { string },
	Effects: { SkillEffect },
}

local Skills = {}

Skills.Branches = {
	Core = { Name = "Core", Color = Color3.fromRGB(255, 255, 255) },
	Strength = { Name = "Strength", Color = Color3.fromRGB(255, 92, 92) },
	Fortune = { Name = "Fortune", Color = Color3.fromRGB(74, 222, 128) },
	Wealth = { Name = "Wealth", Color = Color3.fromRGB(255, 205, 64) },
	Precision = { Name = "Precision", Color = Color3.fromRGB(80, 170, 255) },
	Special = { Name = "Special", Color = Color3.fromRGB(196, 125, 255) },
}

local function node(t)
	t.Requires = t.Requires or {}
	t.RequiresAny = t.RequiresAny or {}
	t.CostStep = t.CostStep or 0
	return t
end

Skills.List = {
	node({ Id = "core", Name = "Awakening", Icon = "✦", Branch = "Core", X = 0, Y = 0, MaxRank = 1, Cost = 1,
		Description = "+10% Sparks. The first step of every button legend.",
		Effects = { { Stat = "sparksPct", Add = 0.1 } } }),

	-- Strength (up) ----------------------------------------------------------------
	node({ Id = "str_1", Name = "Firm Press", Icon = "👊", Branch = "Strength", X = 0, Y = -1, MaxRank = 5, Cost = 1,
		Requires = { "core" }, Description = "+15% Click Power per rank.",
		Effects = { { Stat = "clickPct", Add = 0.15 } } }),
	node({ Id = "str_2", Name = "Heavy Hands", Icon = "🦍", Branch = "Strength", X = 0, Y = -2, MaxRank = 3, Cost = 2,
		Requires = { "str_1" }, Description = "+25% Click Power per rank.",
		Effects = { { Stat = "clickPct", Add = 0.25 } } }),
	node({ Id = "str_3", Name = "Combo Engine", Icon = "🔗", Branch = "Strength", X = -1, Y = -2, MaxRank = 2, Cost = 2,
		Requires = { "str_1" }, Description = "+50 combo cap per rank.",
		Effects = { { Stat = "comboCap", Add = 50 } } }),
	node({ Id = "str_4", Name = "Momentum", Icon = "⏱️", Branch = "Strength", X = 1, Y = -2, MaxRank = 2, Cost = 2,
		Requires = { "str_1" }, Description = "+0.3s combo window per rank.",
		Effects = { { Stat = "comboWindow", Add = 0.3 } } }),
	node({ Id = "str_5", Name = "Titan Grip", Icon = "🗿", Branch = "Strength", X = 0, Y = -3, MaxRank = 1, Cost = 4,
		Requires = { "str_2" }, Description = "Click Power ×1.5.",
		Effects = { { Stat = "clickMult", Mult = 1.5 } } }),
	node({ Id = "str_6", Name = "Streak Master", Icon = "🔥", Branch = "Strength", X = -1, Y = -3, MaxRank = 2, Cost = 3,
		Requires = { "str_3" }, Description = "+100% streak burst rewards per rank.",
		Effects = { { Stat = "streakPct", Add = 1.0 } } }),
	node({ Id = "str_cap", Name = "Button Crusher", Icon = "💢", Branch = "Strength", X = 0, Y = -4, MaxRank = 1, Cost = 8,
		Requires = { "str_5" }, Description = "Click Power ×2. The button fears you.",
		Effects = { { Stat = "clickMult", Mult = 2 } } }),

	-- Fortune (right) --------------------------------------------------------------
	node({ Id = "luck_1", Name = "Four-Leaf", Icon = "🍀", Branch = "Fortune", X = 1, Y = 0, MaxRank = 5, Cost = 1,
		Requires = { "core" }, Description = "+10% Luck per rank.",
		Effects = { { Stat = "luck", Add = 0.1 } } }),
	node({ Id = "luck_2", Name = "Treasure Nose", Icon = "👃", Branch = "Fortune", X = 2, Y = 0, MaxRank = 3, Cost = 2,
		Requires = { "luck_1" }, Description = "+3% bonus item chance from crates per rank.",
		Effects = { { Stat = "chestBonus", Add = 0.03 } } }),
	node({ Id = "luck_3", Name = "Rare Instinct", Icon = "🔎", Branch = "Fortune", X = 2, Y = -1, MaxRank = 3, Cost = 2,
		Requires = { "luck_1" }, Description = "+20% Luck per rank.",
		Effects = { { Stat = "luck", Add = 0.2 } } }),
	node({ Id = "luck_4", Name = "Crate Connoisseur", Icon = "🏷️", Branch = "Fortune", X = 3, Y = 0, MaxRank = 3, Cost = 2,
		Requires = { "luck_2" }, Description = "-5% crate prices per rank.",
		Effects = { { Stat = "chestDiscount", Add = 0.05 } } }),
	node({ Id = "luck_5", Name = "Golden Touch", Icon = "🌟", Branch = "Fortune", X = 2, Y = 1, MaxRank = 3, Cost = 2,
		Requires = { "luck_1" }, Description = "+25% golden press chance per rank.",
		Effects = { { Stat = "goldenPct", Add = 0.25 } } }),
	node({ Id = "luck_6", Name = "Pity Breaker", Icon = "🧿", Branch = "Fortune", X = 3, Y = -1, MaxRank = 2, Cost = 3,
		Requires = { "luck_3" }, Description = "Crate pity triggers 10% sooner per rank.",
		Effects = { { Stat = "pityReduction", Add = 0.1 } } }),
	node({ Id = "luck_cap", Name = "Fortune's Favorite", Icon = "🎰", Branch = "Fortune", X = 4, Y = 0, MaxRank = 1, Cost = 8,
		Requires = { "luck_4", "luck_6" }, Description = "+75% Luck and +5% bonus item chance.",
		Effects = { { Stat = "luck", Add = 0.75 }, { Stat = "chestBonus", Add = 0.05 } } }),

	-- Wealth (down) -----------------------------------------------------------------
	node({ Id = "wealth_1", Name = "Pocket Change", Icon = "💰", Branch = "Wealth", X = 0, Y = 1, MaxRank = 5, Cost = 1,
		Requires = { "core" }, Description = "+10% Sparks per rank.",
		Effects = { { Stat = "sparksPct", Add = 0.1 } } }),
	node({ Id = "wealth_2", Name = "Dynamo", Icon = "🔋", Branch = "Wealth", X = 0, Y = 2, MaxRank = 4, Cost = 1,
		Requires = { "wealth_1" }, Description = "+25% passive income per rank.",
		Effects = { { Stat = "passivePct", Add = 0.25 } } }),
	node({ Id = "wealth_3", Name = "Gem Polisher", Icon = "💎", Branch = "Wealth", X = 1, Y = 2, MaxRank = 3, Cost = 2,
		Requires = { "wealth_1" }, Description = "+15% Gems from every source per rank.",
		Effects = { { Stat = "gemsPct", Add = 0.15 } } }),
	node({ Id = "wealth_4", Name = "Night Shift", Icon = "🌙", Branch = "Wealth", X = -1, Y = 2, MaxRank = 2, Cost = 2,
		Requires = { "wealth_1" }, Description = "+2 hours offline earnings and +10% offline rate per rank.",
		Effects = { { Stat = "offlineHours", Add = 2 }, { Stat = "offlineRate", Add = 0.1 } } }),
	node({ Id = "wealth_5", Name = "Overclock", Icon = "⚙️", Branch = "Wealth", X = 0, Y = 3, MaxRank = 3, Cost = 3,
		Requires = { "wealth_2" }, Description = "+1 auto press per second per rank.",
		Effects = { { Stat = "autoRate", Add = 1 } } }),
	node({ Id = "wealth_cap", Name = "Golden Economy", Icon = "🏦", Branch = "Wealth", X = 0, Y = 4, MaxRank = 1, Cost = 8,
		Requires = { "wealth_5" }, Description = "All Sparks ×1.75.",
		Effects = { { Stat = "sparksMult", Mult = 1.75 } } }),

	-- Precision (left) ---------------------------------------------------------------
	node({ Id = "crit_1", Name = "Steady Aim", Icon = "🎯", Branch = "Precision", X = -1, Y = 0, MaxRank = 5, Cost = 1,
		Requires = { "core" }, Description = "+2% Crit Chance per rank.",
		Effects = { { Stat = "critChance", Add = 0.02 } } }),
	node({ Id = "crit_2", Name = "Overload", Icon = "⚡", Branch = "Precision", X = -2, Y = 0, MaxRank = 4, Cost = 2,
		Requires = { "crit_1" }, Description = "+0.5× crit multiplier per rank.",
		Effects = { { Stat = "critPower", Add = 0.5 } } }),
	node({ Id = "crit_3", Name = "Critical Mass", Icon = "☢️", Branch = "Precision", X = -2, Y = -1, MaxRank = 3, Cost = 2,
		Requires = { "crit_1" }, Description = "+3% Crit Chance per rank.",
		Effects = { { Stat = "critChance", Add = 0.03 } } }),
	node({ Id = "crit_4", Name = "Lethal Precision", Icon = "🗡️", Branch = "Precision", X = -3, Y = 0, MaxRank = 1, Cost = 4,
		Requires = { "crit_2" }, Description = "+1.5× crit multiplier.",
		Effects = { { Stat = "critPower", Add = 1.5 } } }),
	node({ Id = "crit_cap", Name = "Supercritical", Icon = "💥", Branch = "Precision", X = -4, Y = 0, MaxRank = 1, Cost = 8,
		Requires = { "crit_4", "crit_3" }, Description = "+10% Crit Chance and +2× crit multiplier.",
		Effects = { { Stat = "critChance", Add = 0.1 }, { Stat = "critPower", Add = 2 } } }),

	-- Special (diagonals) ------------------------------------------------------------
	node({ Id = "spec_slot", Name = "Collector's Satchel", Icon = "🎒", Branch = "Special", X = 2, Y = 2, MaxRank = 2, Cost = 4, CostStep = 2,
		RequiresAny = { "wealth_3", "luck_5" }, Description = "+1 equip slot per rank.",
		Effects = { { Stat = "equipSlots", Add = 1 } } }),
	node({ Id = "spec_xp", Name = "Fast Learner", Icon = "📘", Branch = "Special", X = -2, Y = 2, MaxRank = 4, Cost = 1,
		RequiresAny = { "wealth_4", "crit_2" }, Description = "+25% XP per rank.",
		Effects = { { Stat = "xpPct", Add = 0.25 } } }),
	node({ Id = "spec_prism", Name = "Prism Attunement", Icon = "🔷", Branch = "Special", X = -2, Y = -2, MaxRank = 3, Cost = 3,
		RequiresAny = { "str_3", "crit_3" }, Description = "+15% Prisms per ascension per rank.",
		Effects = { { Stat = "prismPct", Add = 0.15 } } }),
	node({ Id = "spec_orb", Name = "Orb Magnet", Icon = "🔮", Branch = "Special", X = 2, Y = -2, MaxRank = 2, Cost = 2,
		RequiresAny = { "str_4", "luck_3" }, Description = "Bonus orbs appear 20% more often and give +25% rewards per rank.",
		Effects = { { Stat = "orbRate", Add = 0.2 }, { Stat = "orbPct", Add = 0.25 } } }),
}

Skills.ById = {}
for _, n in ipairs(Skills.List) do
	assert(Skills.ById[n.Id] == nil, "Duplicate skill " .. n.Id)
	Skills.ById[n.Id] = n
end
for _, n in ipairs(Skills.List) do
	for _, req in ipairs(n.Requires) do
		assert(Skills.ById[req], `Skill {n.Id} requires unknown {req}`)
	end
	for _, req in ipairs(n.RequiresAny) do
		assert(Skills.ById[req], `Skill {n.Id} requires unknown {req}`)
	end
end

function Skills.get(id: string): SkillNode?
	return Skills.ById[id]
end

-- Cost in Skill Points to go from currentRank to currentRank + 1.
function Skills.costFor(n: SkillNode, currentRank: number): number
	return n.Cost + n.CostStep * currentRank
end

-- Total points invested in a node at a given rank (used for respec refunds).
function Skills.totalCost(n: SkillNode, rank: number): number
	local total = 0
	for r = 0, rank - 1 do
		total += Skills.costFor(n, r)
	end
	return total
end

-- Returns true when the prerequisites of a node are met for the given skills table.
function Skills.prerequisitesMet(n: SkillNode, owned: { [string]: number }): boolean
	for _, req in ipairs(n.Requires) do
		if (owned[req] or 0) < 1 then
			return false
		end
	end
	if #n.RequiresAny > 0 then
		local any = false
		for _, req in ipairs(n.RequiresAny) do
			if (owned[req] or 0) >= 1 then
				any = true
				break
			end
		end
		if not any then
			return false
		end
	end
	return true
end

return Skills
