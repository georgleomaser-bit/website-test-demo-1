--[[
	Skills (ModuleScript)
	Location: ReplicatedStorage/Shared/Config/Skills

	The skill tree. Nodes are placed on a grid (X right, Y down; the core is 0,0).
	Skill Points come from levelling up, achievements and collection milestones.
	Skills are permanent: they are NOT reset by Ascension (a Gem-priced respec
	refunds every point).

	Layout: four main branches grow outward from the core (Strength up,
	Fortune right, Wealth down, Precision left), each ending in a capstone and,
	further out, an ascended capstone ("_cap2"). Bridge nodes sit between two
	branches near the core, and Special nodes grow along the diagonals.

	The tree reveals itself as it is bought (see Skills.visibility): only the
	core, owned nodes and nodes whose prerequisites are met are shown in full;
	the next ring appears as "?" silhouettes and everything further out stays
	hidden until the player gets closer.

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
		Requires = { "luck_1" }, Description = "+3% bonus item chance from Spark crates per rank.",
		Effects = { { Stat = "chestBonus", Add = 0.03 } } }),
	node({ Id = "luck_3", Name = "Rare Instinct", Icon = "🔎", Branch = "Fortune", X = 2, Y = -1, MaxRank = 3, Cost = 2,
		Requires = { "luck_1" }, Description = "+20% Luck per rank.",
		Effects = { { Stat = "luck", Add = 0.2 } } }),
	node({ Id = "luck_4", Name = "Crate Connoisseur", Icon = "🏷️", Branch = "Fortune", X = 3, Y = 0, MaxRank = 3, Cost = 2,
		Requires = { "luck_2" }, Description = "-5% Spark crate prices per rank.",
		Effects = { { Stat = "chestDiscount", Add = 0.05 } } }),
	node({ Id = "luck_5", Name = "Golden Touch", Icon = "🌟", Branch = "Fortune", X = 2, Y = 1, MaxRank = 3, Cost = 2,
		Requires = { "luck_1" }, Description = "+25% golden press chance per rank.",
		Effects = { { Stat = "goldenPct", Add = 0.25 } } }),
	node({ Id = "luck_6", Name = "Pity Breaker", Icon = "🧿", Branch = "Fortune", X = 3, Y = -1, MaxRank = 2, Cost = 3,
		Requires = { "luck_3" }, Description = "Crate pity triggers 10% sooner per rank.",
		Effects = { { Stat = "pityReduction", Add = 0.1 } } }),
	node({ Id = "luck_cap", Name = "Fortune's Favorite", Icon = "🎰", Branch = "Fortune", X = 4, Y = 0, MaxRank = 1, Cost = 8,
		Requires = { "luck_4", "luck_6" }, Description = "+75% Luck and +5% Spark crate bonus item chance.",
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

	-- Bridges (between two branches, next to the core) -------------------------------
	node({ Id = "bridge_sl", Name = "Lucky Punch", Icon = "🥊", Branch = "Special", X = 1, Y = -1, MaxRank = 2, Cost = 2, CostStep = 1,
		Requires = { "str_1", "luck_1" }, Description = "+10% Click Power and +15% golden press chance per rank.",
		Effects = { { Stat = "clickPct", Add = 0.1 }, { Stat = "goldenPct", Add = 0.15 } } }),
	node({ Id = "bridge_sc", Name = "Precise Strikes", Icon = "🎳", Branch = "Special", X = -1, Y = -1, MaxRank = 2, Cost = 2, CostStep = 1,
		Requires = { "str_1", "crit_1" }, Description = "+10% Click Power and +1% Crit Chance per rank.",
		Effects = { { Stat = "clickPct", Add = 0.1 }, { Stat = "critChance", Add = 0.01 } } }),
	node({ Id = "bridge_wl", Name = "Fortune Flow", Icon = "🌊", Branch = "Special", X = 1, Y = 1, MaxRank = 2, Cost = 2, CostStep = 1,
		Requires = { "wealth_1", "luck_1" }, Description = "+10% Sparks and +15% passive income per rank.",
		Effects = { { Stat = "sparksPct", Add = 0.1 }, { Stat = "passivePct", Add = 0.15 } } }),
	node({ Id = "bridge_wc", Name = "Steady Income", Icon = "📈", Branch = "Special", X = -1, Y = 1, MaxRank = 2, Cost = 2, CostStep = 1,
		Requires = { "wealth_1", "crit_1" }, Description = "+15% passive income and +10% XP per rank.",
		Effects = { { Stat = "passivePct", Add = 0.15 }, { Stat = "xpPct", Add = 0.1 } } }),

	-- Strength, outer ring (up) --------------------------------------------------------
	node({ Id = "str_7", Name = "Rhythm Keeper", Icon = "🥁", Branch = "Strength", X = 1, Y = -3, MaxRank = 2, Cost = 2, CostStep = 1,
		Requires = { "str_4" }, Description = "+0.2s combo window per rank.",
		Effects = { { Stat = "comboWindow", Add = 0.2 } } }),
	node({ Id = "str_8", Name = "Endless Chain", Icon = "⛓️", Branch = "Strength", X = -1, Y = -4, MaxRank = 2, Cost = 3, CostStep = 1,
		Requires = { "str_6" }, Description = "+100 combo cap per rank.",
		Effects = { { Stat = "comboCap", Add = 100 } } }),
	node({ Id = "str_10", Name = "Aftershock", Icon = "🌋", Branch = "Strength", X = 1, Y = -4, MaxRank = 2, Cost = 3, CostStep = 1,
		Requires = { "str_7" }, Description = "+150% streak burst rewards per rank.",
		Effects = { { Stat = "streakPct", Add = 1.5 } } }),
	node({ Id = "str_9", Name = "Iron Knuckles", Icon = "🦾", Branch = "Strength", X = 0, Y = -5, MaxRank = 3, Cost = 3, CostStep = 1,
		Requires = { "str_cap" }, Description = "+50% Click Power per rank.",
		Effects = { { Stat = "clickPct", Add = 0.5 } } }),
	node({ Id = "str_11", Name = "Overdrive", Icon = "🚀", Branch = "Strength", X = -1, Y = -5, MaxRank = 1, Cost = 6,
		Requires = { "str_8" }, Description = "Click Power ×1.25.",
		Effects = { { Stat = "clickMult", Mult = 1.25 } } }),
	node({ Id = "str_12", Name = "Unbreakable", Icon = "🛡️", Branch = "Strength", X = 0, Y = -6, MaxRank = 1, Cost = 8,
		Requires = { "str_9", "str_11" }, Description = "Click Power ×1.5.",
		Effects = { { Stat = "clickMult", Mult = 1.5 } } }),
	node({ Id = "str_cap2", Name = "Earthshaker", Icon = "🌍", Branch = "Strength", X = 0, Y = -7, MaxRank = 1, Cost = 12,
		Requires = { "str_12" }, Description = "Click Power ×2.5 and +200% streak bursts. Every press shakes the world.",
		Effects = { { Stat = "clickMult", Mult = 2.5 }, { Stat = "streakPct", Add = 2 } } }),

	-- Fortune, outer ring (right) -------------------------------------------------------
	node({ Id = "luck_7", Name = "Gilded Fingers", Icon = "🪙", Branch = "Fortune", X = 3, Y = 1, MaxRank = 3, Cost = 2, CostStep = 1,
		Requires = { "luck_5" }, Description = "+25% golden press chance per rank.",
		Effects = { { Stat = "goldenPct", Add = 0.25 } } }),
	node({ Id = "luck_8", Name = "Second Chance", Icon = "🎲", Branch = "Fortune", X = 4, Y = -1, MaxRank = 2, Cost = 3, CostStep = 1,
		Requires = { "luck_6" }, Description = "Crate pity triggers 5% sooner per rank.",
		Effects = { { Stat = "pityReduction", Add = 0.05 } } }),
	node({ Id = "luck_10", Name = "Bargain Sense", Icon = "🛍️", Branch = "Fortune", X = 5, Y = 0, MaxRank = 2, Cost = 4, CostStep = 1,
		Requires = { "luck_cap" }, Description = "-5% Spark crate prices per rank.",
		Effects = { { Stat = "chestDiscount", Add = 0.05 } } }),
	node({ Id = "luck_11", Name = "Bonus Hunter", Icon = "🧲", Branch = "Fortune", X = 5, Y = -1, MaxRank = 2, Cost = 4, CostStep = 1,
		Requires = { "luck_8" }, Description = "+3% bonus item chance from Spark crates per rank.",
		Effects = { { Stat = "chestBonus", Add = 0.03 } } }),
	node({ Id = "luck_12", Name = "Jackpot Aura", Icon = "💫", Branch = "Fortune", X = 6, Y = 0, MaxRank = 1, Cost = 8,
		Requires = { "luck_10", "luck_11" }, Description = "Golden press chance ×1.5 and +25% more.",
		Effects = { { Stat = "goldenMult", Mult = 1.5 }, { Stat = "goldenPct", Add = 0.25 } } }),
	node({ Id = "luck_cap2", Name = "Lady Luck", Icon = "👑", Branch = "Fortune", X = 7, Y = 0, MaxRank = 1, Cost = 12,
		Requires = { "luck_12" }, Description = "+30% Luck and golden press chance ×1.5. Fortune bows to you.",
		Effects = { { Stat = "luck", Add = 0.3 }, { Stat = "goldenMult", Mult = 1.5 } } }),

	-- Wealth, outer ring (down) ----------------------------------------------------------
	node({ Id = "wealth_6", Name = "Compound Interest", Icon = "🧮", Branch = "Wealth", X = 1, Y = 3, MaxRank = 3, Cost = 2, CostStep = 1,
		Requires = { "wealth_3" }, Description = "+25% passive income per rank.",
		Effects = { { Stat = "passivePct", Add = 0.25 } } }),
	node({ Id = "wealth_7", Name = "Sleepwalker", Icon = "😴", Branch = "Wealth", X = -1, Y = 3, MaxRank = 2, Cost = 3, CostStep = 1,
		Requires = { "wealth_4" }, Description = "+2 hours offline earnings and +10% offline rate per rank.",
		Effects = { { Stat = "offlineHours", Add = 2 }, { Stat = "offlineRate", Add = 0.1 } } }),
	node({ Id = "wealth_9", Name = "Power Plant", Icon = "🏭", Branch = "Wealth", X = 1, Y = 4, MaxRank = 1, Cost = 5,
		Requires = { "wealth_6" }, Description = "Passive income ×1.25.",
		Effects = { { Stat = "passiveMult", Mult = 1.25 } } }),
	node({ Id = "wealth_8", Name = "Golden Reserve", Icon = "🏛️", Branch = "Wealth", X = 0, Y = 5, MaxRank = 3, Cost = 3, CostStep = 1,
		Requires = { "wealth_cap" }, Description = "+25% Sparks per rank.",
		Effects = { { Stat = "sparksPct", Add = 0.25 } } }),
	node({ Id = "wealth_10", Name = "Reactor Core", Icon = "☢️", Branch = "Wealth", X = 1, Y = 5, MaxRank = 2, Cost = 4, CostStep = 1,
		Requires = { "wealth_9" }, Description = "+50% passive income per rank.",
		Effects = { { Stat = "passivePct", Add = 0.5 } } }),
	node({ Id = "wealth_11", Name = "Spark Vault", Icon = "🗝️", Branch = "Wealth", X = 0, Y = 6, MaxRank = 1, Cost = 8,
		Requires = { "wealth_8", "wealth_10" }, Description = "All Sparks ×1.25.",
		Effects = { { Stat = "sparksMult", Mult = 1.25 } } }),
	node({ Id = "wealth_cap2", Name = "Infinite Economy", Icon = "♾️", Branch = "Wealth", X = 0, Y = 7, MaxRank = 1, Cost = 12,
		Requires = { "wealth_11" }, Description = "All Sparks ×2 and passive income ×1.5. Money makes money.",
		Effects = { { Stat = "sparksMult", Mult = 2 }, { Stat = "passiveMult", Mult = 1.5 } } }),

	-- Precision, outer ring (left) -------------------------------------------------------
	node({ Id = "crit_5", Name = "Hair Trigger", Icon = "🔫", Branch = "Precision", X = -3, Y = -1, MaxRank = 3, Cost = 2, CostStep = 1,
		Requires = { "crit_3" }, Description = "+2% Crit Chance per rank.",
		Effects = { { Stat = "critChance", Add = 0.02 } } }),
	node({ Id = "crit_6", Name = "Brutal Force", Icon = "🔨", Branch = "Precision", X = -3, Y = 1, MaxRank = 3, Cost = 3, CostStep = 1,
		Requires = { "crit_4" }, Description = "+0.5× crit multiplier per rank.",
		Effects = { { Stat = "critPower", Add = 0.5 } } }),
	node({ Id = "crit_7", Name = "Eagle Eye", Icon = "🦅", Branch = "Precision", X = -4, Y = -1, MaxRank = 2, Cost = 4, CostStep = 1,
		Requires = { "crit_5" }, Description = "+3% Crit Chance per rank.",
		Effects = { { Stat = "critChance", Add = 0.03 } } }),
	node({ Id = "crit_8", Name = "Deadeye", Icon = "🎯", Branch = "Precision", X = -5, Y = 0, MaxRank = 2, Cost = 4, CostStep = 1,
		Requires = { "crit_cap" }, Description = "+1× crit multiplier per rank.",
		Effects = { { Stat = "critPower", Add = 1 } } }),
	node({ Id = "crit_10", Name = "Perfect Timing", Icon = "⌛", Branch = "Precision", X = -5, Y = -1, MaxRank = 2, Cost = 3, CostStep = 1,
		Requires = { "crit_7" }, Description = "+0.2s combo window per rank.",
		Effects = { { Stat = "comboWindow", Add = 0.2 } } }),
	node({ Id = "crit_11", Name = "Executioner", Icon = "⚔️", Branch = "Precision", X = -6, Y = 0, MaxRank = 1, Cost = 8,
		Requires = { "crit_8", "crit_10" }, Description = "+5% Crit Chance and +1.5× crit multiplier.",
		Effects = { { Stat = "critChance", Add = 0.05 }, { Stat = "critPower", Add = 1.5 } } }),
	node({ Id = "crit_cap2", Name = "Singularity Strike", Icon = "🌀", Branch = "Precision", X = -7, Y = 0, MaxRank = 1, Cost = 12,
		Requires = { "crit_11" }, Description = "+5% Crit Chance and +3× crit multiplier. Every crit tears space.",
		Effects = { { Stat = "critChance", Add = 0.05 }, { Stat = "critPower", Add = 3 } } }),

	-- Special, outer diagonals ------------------------------------------------------------
	node({ Id = "spec_prism2", Name = "Prism Resonance", Icon = "🔶", Branch = "Special", X = -3, Y = -3, MaxRank = 3, Cost = 4, CostStep = 1,
		Requires = { "spec_prism" }, Description = "+10% Prisms per ascension per rank.",
		Effects = { { Stat = "prismPct", Add = 0.1 } } }),
	node({ Id = "spec_orb2", Name = "Orb Storm", Icon = "🌪️", Branch = "Special", X = 3, Y = -3, MaxRank = 2, Cost = 3, CostStep = 1,
		Requires = { "spec_orb" }, Description = "Bonus orbs appear 20% more often and give +25% rewards per rank.",
		Effects = { { Stat = "orbRate", Add = 0.2 }, { Stat = "orbPct", Add = 0.25 } } }),
	node({ Id = "spec_xp2", Name = "Scholar's Focus", Icon = "🎓", Branch = "Special", X = -3, Y = 3, MaxRank = 2, Cost = 4, CostStep = 2,
		Requires = { "spec_xp" }, Description = "All XP ×1.25 per rank.",
		Effects = { { Stat = "xpMult", Mult = 1.25 } } }),
	node({ Id = "spec_hoard", Name = "Golden Hoard", Icon = "🏺", Branch = "Special", X = 3, Y = 3, MaxRank = 1, Cost = 6,
		RequiresAny = { "spec_slot", "luck_7", "wealth_6" }, Description = "Golden press chance ×1.25 and +3% bonus item chance from Spark crates.",
		Effects = { { Stat = "goldenMult", Mult = 1.25 }, { Stat = "chestBonus", Add = 0.03 } } }),
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

-- Every prerequisite id of a node (Requires and RequiresAny).
function Skills.prerequisiteIds(n: SkillNode): { string }
	local ids = table.clone(n.Requires)
	for _, id in ipairs(n.RequiresAny) do
		table.insert(ids, id)
	end
	return ids
end

export type Visibility = "visible" | "teaser" | "hidden"

--[[
	How much of the tree a player sees, so it builds itself up as it is bought:
	  visible  the core, owned nodes, and nodes whose prerequisites are met
	  teaser   the next ring: not visible, but connected to a visible node
	           (shown only as a "?" silhouette, without name, effect or cost)
	  hidden   everything further out, including its connector lines
	Pure function; used by the Skills screen and the tests.
]]
function Skills.visibility(owned: { [string]: number }): { [string]: Visibility }
	local result: { [string]: Visibility } = {}
	for _, n in ipairs(Skills.List) do
		if n.Id == "core" or (owned[n.Id] or 0) > 0 or Skills.prerequisitesMet(n, owned) then
			result[n.Id] = "visible"
		end
	end
	for _, n in ipairs(Skills.List) do
		if not result[n.Id] then
			result[n.Id] = "hidden"
			for _, id in ipairs(Skills.prerequisiteIds(n)) do
				if result[id] == "visible" then
					result[n.Id] = "teaser"
					break
				end
			end
		end
	end
	return result
end

return Skills
