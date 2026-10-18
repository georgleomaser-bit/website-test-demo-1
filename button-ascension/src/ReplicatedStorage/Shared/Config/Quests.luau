--[[
	Quests (ModuleScript)
	Location: ReplicatedStorage/Shared/Config/Quests

	Two kinds of quests:
	  * Daily quests: DailyCount quests are drawn from the Daily pool each UTC day
	    (deterministically per player). Targets scale with the player's progress.
	  * Starter path: a fixed sequence that teaches the core loop to new players.

	Kinds (progress events reported by server services):
	  Clicks, Crits, ChestsOpened, UpgradesBought, Combo (max value), GoldenClicks,
	  OrbsCollected, ItemsSold, SparksEarned, PlayMinutes.
	Check kinds (evaluated against current data, starter path only):
	  ReachLevel, RunSparks, Equip, SkillUnlocked, Rebirth.

	Reward fields: Sparks, Gems, SkillPoints, Prisms, Chests = { [id] = n }
]]

local Quests = {}

Quests.DailyCount = 3

-- Target = ceil(Base * (1 + ScalePerRebirth * min(rebirths, 20))) for normal quests.
-- Quests with ClickScaled = true use Base * current click value (snapshotted).
Quests.Daily = {
	{ Id = "press", Kind = "Clicks", Text = "Press the button %s times", Base = 400, ScalePerRebirth = 0.15, Reward = { Gems = 15 } },
	{ Id = "crits", Kind = "Crits", Text = "Land %s critical presses", Base = 30, ScalePerRebirth = 0.15, Reward = { Gems = 15 } },
	{ Id = "crates", Kind = "ChestsOpened", Text = "Open %s crates", Base = 6, ScalePerRebirth = 0.1, Reward = { Gems = 20 } },
	{ Id = "upgrades", Kind = "UpgradesBought", Text = "Buy %s upgrade levels", Base = 12, ScalePerRebirth = 0.05, Reward = { Gems = 15 } },
	{ Id = "combo", Kind = "Combo", Text = "Reach a %s press combo", Base = 60, ScalePerRebirth = 0.1, Reward = { Gems = 20 }, Max = 400 },
	{ Id = "golden", Kind = "GoldenClicks", Text = "Trigger %s golden presses", Base = 1, ScalePerRebirth = 0.05, Reward = { Gems = 25 } },
	{ Id = "orbs", Kind = "OrbsCollected", Text = "Collect %s bonus orbs", Base = 2, ScalePerRebirth = 0.05, Reward = { Gems = 20 } },
	{ Id = "sell", Kind = "ItemsSold", Text = "Sell %s items", Base = 5, ScalePerRebirth = 0.1, Reward = { Gems = 10, Chests = { starter = 2 } } },
	{ Id = "earn", Kind = "SparksEarned", Text = "Earn %s Sparks", Base = 1500, ClickScaled = true, Reward = { Gems = 20 } },
	{ Id = "playtime", Kind = "PlayMinutes", Text = "Play for %s minutes", Base = 15, ScalePerRebirth = 0, Reward = { Gems = 15, Chests = { neon = 1 } } },
}

-- Bonus for completing (claiming) every daily quest.
Quests.DailyBonus = { Gems = 40, Chests = { prism = 1 } }

Quests.Starter = {
	{ Id = "s_press", Kind = "Clicks", Text = "Press the button 25 times", Target = 25, Reward = { Sparks = 100 } },
	{ Id = "s_upgrade", Kind = "UpgradesBought", Text = "Buy your first upgrade in the Shop", Target = 1, Reward = { Chests = { starter = 1 } } },
	{ Id = "s_crate", Kind = "ChestsOpened", Text = "Open a crate", Target = 1, Reward = { Gems = 10 } },
	{ Id = "s_equip", Kind = "Equip", Text = "Equip an item from your Inventory", Target = 1, Reward = { Chests = { starter = 2 } } },
	{ Id = "s_level", Kind = "ReachLevel", Text = "Reach level 5", Target = 5, Reward = { SkillPoints = 1 } },
	{ Id = "s_skill", Kind = "SkillUnlocked", Text = "Unlock a skill in the Skill Tree", Target = 1, Reward = { Gems = 20 } },
	{ Id = "s_combo", Kind = "Combo", Text = "Reach a 50 press combo", Target = 50, Reward = { Chests = { neon = 1 } } },
	{ Id = "s_orb", Kind = "OrbsCollected", Text = "Tap a bonus orb when it appears", Target = 1, Reward = { Gems = 15 } },
	{ Id = "s_run", Kind = "RunSparks", Text = "Earn 1M Sparks in this run", Target = 1e6, Reward = { Gems = 50 } },
	{ Id = "s_ascend", Kind = "Rebirth", Text = "Ascend for the first time", Target = 1, Reward = { Gems = 100, Chests = { prism = 1 } } },
}

Quests.DailyById = {}
for _, q in ipairs(Quests.Daily) do
	Quests.DailyById[q.Id] = q
end
Quests.StarterById = {}
for index, q in ipairs(Quests.Starter) do
	q.Index = index
	Quests.StarterById[q.Id] = q
end

-- Kinds whose progress keeps the highest value instead of summing.
Quests.MaxKinds = { Combo = true }
-- Kinds evaluated from current data instead of events (starter path only).
Quests.CheckKinds = { ReachLevel = true, RunSparks = true, Equip = true, SkillUnlocked = true, Rebirth = true }

return Quests
