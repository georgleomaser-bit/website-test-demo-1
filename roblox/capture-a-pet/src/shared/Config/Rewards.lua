-- Daily login streak, playtime gifts, daily tasks, expeditions and codes.
--
-- Reward entries:
--   { Type = "Cash", IncomeSeconds = n, Min = n }  cash worth n seconds of your income (at least Min)
--   { Type = "Speed", TrainSeconds = n, Min = n }  Speed worth n seconds of your best treadmill
--   { Type = "Bait", Amount = n }
--   { Type = "Boost", Boost = "Training" | "Cash" | "Luck", Seconds = n }
--   { Type = "Animal", Id = "Animal Id", Aura = auraIndex? }

local Rewards = {}

Rewards.DailyClaimCooldownHours = 20
Rewards.DailyStreakResetHours = 48

Rewards.Daily = {
	{ { Type = "Cash", IncomeSeconds = 300, Min = 500 }, { Type = "Bait", Amount = 2 } },
	{ { Type = "Boost", Boost = "Training", Seconds = 600 } },
	{ { Type = "Cash", IncomeSeconds = 900, Min = 2000 }, { Type = "Bait", Amount = 3 } },
	{ { Type = "Boost", Boost = "Luck", Seconds = 900 } },
	{ { Type = "Cash", IncomeSeconds = 1800, Min = 8000 }, { Type = "Boost", Boost = "Cash", Seconds = 900 } },
	{ { Type = "Bait", Amount = 6 }, { Type = "Speed", TrainSeconds = 600, Min = 5000 } },
	{ { Type = "Animal", Id = "Golden Stag", Aura = 3 }, { Type = "Cash", IncomeSeconds = 3600, Min = 25000 } },
}

-- Gifts unlock after this many minutes in the current session.
Rewards.Playtime = {
	{ Minutes = 1, Reward = { Type = "Cash", IncomeSeconds = 60, Min = 100 } },
	{ Minutes = 3, Reward = { Type = "Bait", Amount = 1 } },
	{ Minutes = 6, Reward = { Type = "Boost", Boost = "Training", Seconds = 300 } },
	{ Minutes = 10, Reward = { Type = "Cash", IncomeSeconds = 300, Min = 1000 } },
	{ Minutes = 15, Reward = { Type = "Boost", Boost = "Luck", Seconds = 600 } },
	{ Minutes = 20, Reward = { Type = "Bait", Amount = 3 } },
	{ Minutes = 30, Reward = { Type = "Boost", Boost = "Cash", Seconds = 900 } },
	{ Minutes = 45, Reward = { Type = "Speed", TrainSeconds = 900, Min = 10000 } },
	{ Minutes = 60, Reward = { Type = "Animal", Id = "Sphinx Cat", Aura = 2 } },
}

-- Three tasks are picked every day. Relative goals are scaled to your progress when picked.
Rewards.TaskPool = {
	{ Kind = "Train", Text = "Train %s Speed", TrainSeconds = 240, Min = 200 },
	{ Kind = "EarnCash", Text = "Earn $%s", IncomeSeconds = 600, Min = 1000 },
	{ Kind = "Tame", Text = "Tame %s animals", Count = 8 },
	{ Kind = "TameRare", Text = "Tame %s Rare or better animals", Count = 2 },
	{ Kind = "DeliverEgg", Text = "Bring %s wild eggs home", Count = 3 },
	{ Kind = "Hatch", Text = "Hatch %s eggs", Count = 3 },
	{ Kind = "Bait", Text = "Lure guards with %s Glow Baits", Count = 3 },
	{ Kind = "Aura", Text = "Bring home an egg with an aura", Count = 1 },
}
Rewards.TasksPerDay = 3
Rewards.TaskReward = { { Type = "Cash", IncomeSeconds = 900, Min = 3000 }, { Type = "Bait", Amount = 2 } }
Rewards.AllTasksReward = { { Type = "Boost", Boost = "Luck", Seconds = 1200 }, { Type = "Boost", Boost = "Cash", Seconds = 1200 } }

-- Expedition: bring one wild egg home from each of the four zones. Rewards grow every level.
Rewards.Expedition = function(level: number)
	return {
		{ Type = "Cash", IncomeSeconds = 1200 + 300 * level, Min = 10000 },
		{ Type = "Bait", Amount = 3 + level },
		{ Type = "Boost", Boost = "Luck", Seconds = 600 + 60 * math.min(level, 20) },
	}
end

-- Index rewards: discovering every animal of a zone, and overall milestones.
Rewards.IndexZone = {
	{ { Type = "Cash", IncomeSeconds = 1800, Min = 20000 }, { Type = "Boost", Boost = "Luck", Seconds = 1800 } },
	{ { Type = "Cash", IncomeSeconds = 1800, Min = 2e6 }, { Type = "Boost", Boost = "Luck", Seconds = 1800 } },
	{ { Type = "Cash", IncomeSeconds = 1800, Min = 2e9 }, { Type = "Boost", Boost = "Luck", Seconds = 1800 } },
	{ { Type = "Cash", IncomeSeconds = 1800, Min = 2e12 }, { Type = "Animal", Id = "Oni Tiger", Aura = 4 } },
}
Rewards.IndexMilestones = {
	{ Count = 5, Reward = { { Type = "Bait", Amount = 3 } } },
	{ Count = 10, Reward = { { Type = "Boost", Boost = "Cash", Seconds = 900 } } },
	{ Count = 20, Reward = { { Type = "Cash", IncomeSeconds = 3600, Min = 1e5 } } },
	{ Count = 30, Reward = { { Type = "Boost", Boost = "Luck", Seconds = 3600 } } },
	{ Count = 40, Reward = { { Type = "Animal", Id = "Volcano Dragon", Aura = 5 } } },
}

-- Codes are case-insensitive. Each can be redeemed once per player.
Rewards.Codes = {
	RELEASE = { { Type = "Cash", IncomeSeconds = 600, Min = 2500 }, { Type = "Bait", Amount = 3 } },
	SPEED = { { Type = "Boost", Boost = "Training", Seconds = 900 } },
	LUCKY = { { Type = "Boost", Boost = "Luck", Seconds = 900 } },
	TAMER = { { Type = "Animal", Id = "Gray Wolf", Aura = 2 } },
}

-- Glow bait shop price grows with how far you have come so it stays meaningful.
Rewards.BaitPriceIncomeSeconds = 45
Rewards.BaitPriceMin = 250
Rewards.MaxBait = 30
Rewards.MaxBaitWithPass = 99
Rewards.BaitBagDaily = 10

return Rewards
