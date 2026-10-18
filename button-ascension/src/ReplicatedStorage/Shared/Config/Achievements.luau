--[[
	Achievements (ModuleScript)
	Location: ReplicatedStorage/Shared/Config/Achievements

	Achievements unlock automatically when a tracked statistic reaches its
	target. Rewards are granted by the server on unlock.

	Stat refers to a key of the player's Stats table, or one of the computed
	values: "Rebirths", "Level", "ItemsDiscovered", "SkillRanks".
	Reward fields: Gems, SkillPoints, Chests = { [chestId] = count }
]]

export type Achievement = {
	Id: string,
	Name: string,
	Icon: string,
	Description: string,
	Stat: string,
	Target: number,
	Reward: { Gems: number?, SkillPoints: number?, Chests: { [string]: number }? },
	Order: number,
}

local Achievements = {}

-- stylua: ignore
local LIST = {
	{ "press_100",      "First Steps",        "👆", "Press the button 100 times.",               "TotalClicks",       100,       { Gems = 10 } },
	{ "press_1k",       "Getting the Hang",   "👆", "Press the button 1,000 times.",             "TotalClicks",       1000,      { Gems = 25, SkillPoints = 1 } },
	{ "press_10k",      "Button Enthusiast",  "👆", "Press the button 10,000 times.",            "TotalClicks",       10000,     { Gems = 75, SkillPoints = 1 } },
	{ "press_100k",     "Button Devotee",     "👆", "Press the button 100,000 times.",           "TotalClicks",       100000,    { Gems = 250, SkillPoints = 2 } },
	{ "press_1m",       "Button Legend",      "🏆", "Press the button 1,000,000 times.",         "TotalClicks",       1000000,   { Gems = 1000, SkillPoints = 3 } },

	{ "sparks_1k",      "Spark of Hope",      "⚡", "Earn 1,000 Sparks in total.",               "LifetimeSparks",    1e3,       { Gems = 10 } },
	{ "sparks_1m",      "Millionaire",        "⚡", "Earn 1 million Sparks in total.",           "LifetimeSparks",    1e6,       { Gems = 50, Chests = { neon = 2 } } },
	{ "sparks_1b",      "Billionaire",        "⚡", "Earn 1 billion Sparks in total.",           "LifetimeSparks",    1e9,       { Gems = 150, SkillPoints = 2 } },
	{ "sparks_1t",      "Trillionaire",       "⚡", "Earn 1 trillion Sparks in total.",          "LifetimeSparks",    1e12,      { Gems = 400, SkillPoints = 3 } },
	{ "sparks_1qa",     "Beyond Counting",    "🌌", "Earn 1 quadrillion Sparks in total.",       "LifetimeSparks",    1e15,      { Gems = 1000, SkillPoints = 5 } },

	{ "crate_1",        "Unboxing Day",       "📦", "Open your first crate.",                    "ChestsOpened",      1,         { Gems = 5 } },
	{ "crate_50",       "Crate Collector",    "📦", "Open 50 crates.",                           "ChestsOpened",      50,        { Gems = 40, Chests = { neon = 1 } } },
	{ "crate_500",      "Crate Hoarder",      "🎁", "Open 500 crates.",                          "ChestsOpened",      500,       { Gems = 150, SkillPoints = 2 } },
	{ "crate_5000",     "Crate Tycoon",       "🎁", "Open 5,000 crates.",                        "ChestsOpened",      5000,      { Gems = 600, SkillPoints = 3 } },

	{ "discover_10",    "Curious Mind",       "📖", "Discover 10 different items.",              "ItemsDiscovered",   10,        { Gems = 25, SkillPoints = 1 } },
	{ "discover_30",    "Archivist",          "📖", "Discover 30 different items.",              "ItemsDiscovered",   30,        { Gems = 100, SkillPoints = 2 } },
	{ "discover_60",    "Museum Curator",     "🏛️", "Discover 60 different items.",              "ItemsDiscovered",   60,        { Gems = 400, SkillPoints = 3 } },

	{ "legendary_1",    "Legendary!",         "🌟", "Find a Legendary item.",                    "LegendariesFound",  1,         { Gems = 50 } },
	{ "mythic_1",       "Myth Made Real",     "🐉", "Find a Mythic item.",                       "MythicsFound",      1,         { Gems = 200, SkillPoints = 1 } },
	{ "secret_1",       "Secret Keeper",      "🤫", "Find a Secret item.",                       "SecretsFound",      1,         { Gems = 1000, SkillPoints = 3 } },

	{ "crit_100",       "Critical Thinker",   "🎯", "Land 100 critical presses.",                "TotalCrits",        100,       { Gems = 15 } },
	{ "crit_10k",       "Crit Machine",       "🎯", "Land 10,000 critical presses.",             "TotalCrits",        10000,     { Gems = 150, SkillPoints = 2 } },
	{ "combo_100",      "Combo Starter",      "🔥", "Reach a 100 press combo.",                  "HighestCombo",      100,       { Gems = 20 } },
	{ "combo_500",      "Combo Fiend",        "🔥", "Reach a 500 press combo.",                  "HighestCombo",      500,       { Gems = 100, SkillPoints = 1 } },
	{ "golden_10",      "Golden Fingers",     "🌟", "Trigger 10 golden presses.",                "GoldenClicks",      10,        { Gems = 50 } },

	{ "rebirth_1",      "Ascended",           "🔷", "Ascend for the first time.",                "Rebirths",          1,         { Gems = 100, SkillPoints = 2 } },
	{ "rebirth_5",      "Seasoned Ascender",  "🔷", "Ascend 5 times.",                           "Rebirths",          5,         { Gems = 300, SkillPoints = 3 } },
	{ "rebirth_10",     "Singular",           "🌌", "Ascend 10 times.",                          "Rebirths",          10,        { Gems = 800, SkillPoints = 5 } },

	{ "upgrade_25",     "Tinkerer",           "🔧", "Buy 25 upgrade levels.",                    "UpgradesPurchased", 25,        { Gems = 20 } },
	{ "upgrade_250",    "Engineer",           "🔧", "Buy 250 upgrade levels.",                   "UpgradesPurchased", 250,       { Gems = 100, SkillPoints = 1 } },
	{ "skills_10",      "Branching Out",      "🌳", "Invest 10 Skill Points.",                   "SkillRanks",        10,        { Gems = 50 } },
	{ "level_25",       "Experienced",        "📈", "Reach level 25.",                           "Level",             25,        { Gems = 100, Chests = { prism = 1 } } },
	{ "quests_10",      "Quest Taker",        "📜", "Complete 10 daily quests.",                 "QuestsCompleted",   10,        { Gems = 75 } },
	{ "orbs_25",        "Orb Catcher",        "🔮", "Collect 25 bonus orbs.",                    "OrbsCollected",     25,        { Gems = 60 } },
}

Achievements.List = {} :: { Achievement }
Achievements.ById = {} :: { [string]: Achievement }

for index, row in ipairs(LIST) do
	local id, name, icon, description, stat, target, reward = table.unpack(row)
	local def: Achievement = {
		Id = id,
		Name = name,
		Icon = icon,
		Description = description,
		Stat = stat,
		Target = target,
		Reward = reward,
		Order = index,
	}
	assert(Achievements.ById[id] == nil, "Duplicate achievement " .. id)
	table.insert(Achievements.List, def)
	Achievements.ById[id] = def
end

function Achievements.get(id: string): Achievement?
	return Achievements.ById[id]
end

return Achievements
