--[[
	Rewards (ModuleScript)
	Location: ReplicatedStorage/Shared/Config/Rewards

	Daily login rewards and collection-book milestones.

	Daily rewards follow a 7-day cycle. Claiming on consecutive UTC days grows
	the streak; missing a day resets it to day 1.

	Collection milestones are claimed manually once enough unique items have
	been discovered. Reward fields: Sparks, Gems, SkillPoints, Prisms,
	Chests = { [id] = n }
]]

local Rewards = {}

Rewards.Daily = {
	{ Day = 1, Text = "15 Gems", Reward = { Gems = 15 } },
	{ Day = 2, Text = "2 Spark Crates", Reward = { Chests = { starter = 2 } } },
	{ Day = 3, Text = "30 Gems", Reward = { Gems = 30 } },
	{ Day = 4, Text = "2 Neon Crates", Reward = { Chests = { neon = 2 } } },
	{ Day = 5, Text = "50 Gems + 1 Skill Point", Reward = { Gems = 50, SkillPoints = 1 } },
	{ Day = 6, Text = "3 Neon Crates", Reward = { Chests = { neon = 3 } } },
	{ Day = 7, Text = "100 Gems + 2 Skill Points + Prism Cache", Reward = { Gems = 100, SkillPoints = 2, Chests = { prism = 1 } } },
}

Rewards.Collection = {
	{ Id = "col_5", Count = 5, Text = "20 Gems", Reward = { Gems = 20 } },
	{ Id = "col_10", Count = 10, Text = "1 Skill Point + 2 Neon Crates", Reward = { SkillPoints = 1, Chests = { neon = 2 } } },
	{ Id = "col_20", Count = 20, Text = "75 Gems + Prism Cache", Reward = { Gems = 75, Chests = { prism = 1 } } },
	{ Id = "col_30", Count = 30, Text = "2 Skill Points", Reward = { SkillPoints = 2 } },
	{ Id = "col_40", Count = 40, Text = "200 Gems + 2 Prism Caches", Reward = { Gems = 200, Chests = { prism = 2 } } },
	{ Id = "col_50", Count = 50, Text = "3 Skill Points + 5 Prisms", Reward = { SkillPoints = 3, Prisms = 5 } },
	{ Id = "col_60", Count = 60, Text = "500 Gems + 3 Prism Caches", Reward = { Gems = 500, Chests = { prism = 3 } } },
	{ Id = "col_all", Count = -1, Text = "5 Skill Points + 25 Prisms", Reward = { SkillPoints = 5, Prisms = 25 } },
}

Rewards.CollectionById = {}
for _, m in ipairs(Rewards.Collection) do
	Rewards.CollectionById[m.Id] = m
end

return Rewards
