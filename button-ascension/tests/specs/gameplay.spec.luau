--[[
	Gameplay: new players, pressing, upgrades, crates, inventory, skills,
	ascension, quests, achievements, orbs and settings — plus forged and
	malformed requests for each, sent straight to the server remotes.
]]

local Test = require("../harness/Test")
local Game = require("../helpers/Game")

local describe, it = Test.describe, Test.it

local function setup(ctx)
	local server = Game.server(ctx)
	local player, client = Game.join(ctx, server, 1001, "Alice")
	return server, player, client
end

describe("New player", function()
	it("gets default data, leaderstats, daily quests and a full snapshot", function(ctx)
		local server, player, client = setup(ctx)
		local data = Game.data(server, player)
		ctx.expect(data).toBeTruthy()
		ctx.expect(data.Currencies.Sparks).toBe(0)
		ctx.expect(data.Level).toBe(1)
		ctx.expect(data.Rebirths).toBe(0)
		ctx.expect(#data.Quests.Daily).toBe(3)
		ctx.expect(data.Quests.StarterIndex).toBe(1)
		ctx.expect(player:FindFirstChild("leaderstats")).toBeTruthy()
		local State = client:requirePath("Players.Alice.PlayerScripts.Client.State")
		ctx.harness:advance(2)
		ctx.expect(State.Ready).toBe(true)
		ctx.expect(State.Data.Derived.Stats.clickValue).toBe(1)
		ctx.expect(State.Data.Derived.Persistent).toBe(true)
	end)
end)

describe("Pressing", function()
	it("awards server-computed Sparks, XP and stats and ignores forged arguments", function(ctx)
		local server, player = setup(ctx)
		for _ = 1, 20 do
			-- An exploiter can attach anything; the server must ignore it.
			ctx.harness:exploitFire(server, player, "Click", { Amount = 1e30, Crit = true }, 999999)
			ctx.harness:advance(0.1)
		end
		ctx.harness:advance(0.5)
		local data = Game.data(server, player)
		ctx.expect(data.Stats.TotalClicks).toBe(20)
		-- Base value 1, combo up to +20%, a few possible crits (×3): far below any forged amount.
		ctx.expect(data.Currencies.Sparks).toBeGreaterThanOrEqual(20)
		ctx.expect(data.Currencies.Sparks).toBeLessThan(200)
		ctx.expect(data.XP + (data.Level - 1)).toBeGreaterThan(0)
		ctx.expect(data.Stats.HighestCombo).toBe(20)
	end)

	it("caps instant click floods with the token bucket and flags them", function(ctx)
		local server, player = setup(ctx)
		ctx.harness:advance(3)
		for _ = 1, 200 do
			ctx.harness:exploitFire(server, player, "Click")
		end
		ctx.harness:advance(1.2)
		ctx.harness:exploitFire(server, player, "Click")
		ctx.harness:advance(0.2)
		local data = Game.data(server, player)
		ctx.expect(data.Stats.TotalClicks).toBeLessThanOrEqual(32)
		local security = Game.service(server, "SecurityService")
		ctx.expect(security:GetCounts(player.UserId).ClickFlood or 0).toBeGreaterThanOrEqual(1)
	end)

	it("bursts a streak only every 50 chained presses, even once the combo is capped", function(ctx)
		local server, player = setup(ctx)
		local data = Game.data(server, player)
		local rt = Game.profile(server, player).Runtime
		local CLICK = Game.shared(server, "Config.GameConfig").Click
		-- Pretend a very long chain already hit the hard combo limit.
		rt.Combo = CLICK.HardComboLimit
		rt.StreakCount = 0
		rt.LastClick = math.huge
		Game.press(ctx, server, player, CLICK.StreakEvery - 1)
		ctx.expect(rt.Combo).toBe(CLICK.HardComboLimit)
		ctx.expect(data.Stats.StreakBursts).toBe(0)
		Game.press(ctx, server, player, 1)
		ctx.expect(data.Stats.StreakBursts).toBe(1)
	end)

	it("ignores presses before the profile has loaded", function(ctx)
		local server = Game.server(ctx)
		local player = ctx.harness:addPlayer(server, { userId = 1009, name = "Early" })
		ctx.harness:exploitFire(server, player, "Click")
		ctx.harness:advance(3)
		local data = Game.data(server, player)
		ctx.expect(data.Stats.TotalClicks).toBe(0)
	end)
end)

describe("Upgrades", function()
	it("rejects purchases without funds, unknown ids, bad amounts and locked tiers", function(ctx)
		local server, player = setup(ctx)
		local cases = {
			{ "BuyUpgrade", { Id = "click_power", Amount = 1 }, "Not enough" },
			{ "BuyUpgrade", { Id = "free_money", Amount = 1 }, "Unknown upgrade" },
			{ "BuyUpgrade", { Id = "click_power", Amount = 1000 }, "Invalid amount" },
			{ "BuyUpgrade", { Id = "click_power", Amount = -5 }, "Invalid amount" },
			{ "BuyUpgrade", { Id = 5, Amount = 1 }, "Unknown upgrade" },
			{ "BuyUpgrade", "not a table", "Bad request" },
		}
		for _, case in ipairs(cases) do
			local result = Game.action(ctx, server, player, case[1], case[2])
			ctx.expect(result.ok).toBe(false)
			ctx.expect(result.err).toMatch(case[3])
			ctx.harness:advance(0.3)
		end
		Game.give(server, player, "Sparks", 1e9)
		local locked = Game.action(ctx, server, player, "BuyUpgrade", { Id = "auto_presser", Amount = 1 })
		ctx.expect(locked.ok).toBe(false)
		ctx.expect(locked.err).toMatch("level 8")
		ctx.expect(Game.data(server, player).Upgrades.auto_presser).toBeNil()
	end)

	it("charges the server price and raises the level; MAX buys as many as affordable", function(ctx)
		local server, player = setup(ctx)
		local Formulas = Game.shared(server, "Formulas")
		local Upgrades = Game.shared(server, "Config.Upgrades")
		local def = Upgrades.ById.click_power
		Game.give(server, player, "Sparks", 1000)
		local result = Game.action(ctx, server, player, "BuyUpgrade", { Id = "click_power", Amount = 1, Price = 0 })
		ctx.expect(result.ok).toBe(true)
		local data = Game.data(server, player)
		ctx.expect(data.Upgrades.click_power).toBe(1)
		ctx.expect(data.Currencies.Sparks).toBe(1000 - Formulas.upgradeLevelCost(def, 0))
		local expectedCount = Formulas.maxAffordable(def, 1, data.Currencies.Sparks)
		local maxResult = Game.action(ctx, server, player, "BuyUpgrade", { Id = "click_power", Amount = "max" })
		ctx.expect(maxResult.ok).toBe(true)
		ctx.expect(maxResult.Count).toBe(expectedCount)
		ctx.expect(data.Upgrades.click_power).toBe(1 + expectedCount)
		ctx.expect(data.Currencies.Sparks).toBeGreaterThanOrEqual(0)
		-- The new click value is reflected in the stats sent to the client.
		local StatsService = Game.service(server, "StatsService")
		ctx.expect(StatsService:Get(Game.profile(server, player)).clickBase).toBe(1 + def.Value(1 + expectedCount))
	end)
end)

describe("Crates", function()
	it("validates crate id, amount, mode, stage lock and funds", function(ctx)
		local server, player = setup(ctx)
		local bad = {
			{ { Id = "starter", Amount = 1, Mode = "buy" }, "Not enough" },
			{ { Id = "starter", Amount = 1, Mode = "owned" }, "don't have" },
			{ { Id = "starter", Amount = 11, Mode = "buy" }, "Invalid amount" },
			{ { Id = "starter", Amount = 0.5, Mode = "buy" }, "Invalid amount" },
			{ { Id = "starter", Amount = 1, Mode = "free" }, "Invalid request" },
			{ { Id = "golden_vault", Amount = 1, Mode = "buy" }, "Unknown crate" },
			{ { Id = "plasma", Amount = 1, Mode = "buy" }, "Unlocks at" },
		}
		for _, case in ipairs(bad) do
			local result = Game.action(ctx, server, player, "OpenChest", case[1])
			ctx.expect(result.ok).toBe(false)
			ctx.expect(result.err).toMatch(case[2])
			ctx.harness:advance(0.6)
		end
	end)

	it("rolls on the server, applies the items and ignores forged rarities", function(ctx)
		local server, player = setup(ctx)
		Game.give(server, player, "Sparks", 10000)
		local result = Game.action(ctx, server, player, "OpenChest", { Id = "starter", Amount = 10, Mode = "buy", Rarity = "Secret", Item = "first_button" })
		ctx.expect(result.ok).toBe(true)
		ctx.expect(#result.Results).toBeGreaterThanOrEqual(10)
		local data = Game.data(server, player)
		ctx.expect(data.Currencies.Sparks).toBe(10000 - 2500)
		ctx.expect(data.Stats.ChestsOpened).toBe(10)
		local total = 0
		for id, count in pairs(data.Inventory) do
			total += count
			ctx.expect(data.Discovered[id]).toBeTruthy()
		end
		ctx.expect(total).toBe(#result.Results)
		ctx.expect(data.Pity.starter).toBeTruthy()
	end)

	it("guarantees a Legendary or better when pity is reached", function(ctx)
		local server, player = setup(ctx)
		local data = Game.data(server, player)
		data.Pity.starter = { Legendary = 79, Mythic = 0 }
		data.Chests.starter = 1
		local result = Game.action(ctx, server, player, "OpenChest", { Id = "starter", Amount = 1, Mode = "owned" })
		ctx.expect(result.ok).toBe(true)
		local Rarities = Game.shared(server, "Config.Rarities")
		ctx.expect(Rarities.index(result.Results[1].Rarity)).toBeGreaterThanOrEqual(5)
		ctx.expect(result.Results[1].Pity).toBe(true)
		ctx.expect(data.Pity.starter.Legendary).toBe(0)
	end)

	it("auto-sells duplicates up to the chosen rarity when enabled", function(ctx)
		local server, player = setup(ctx)
		local data = Game.data(server, player)
		ctx.expect(Game.action(ctx, server, player, "UpdateSettings", { Key = "AutoSell", Value = 3 }).ok).toBe(true)
		local Items = Game.shared(server, "Config.Items")
		-- Own one of every starter item so every drop is a duplicate.
		for _, item in ipairs(Items.List) do
			if item.Chest == "starter" then
				data.Inventory[item.Id] = 1
				data.Discovered[item.Id] = 1
			end
		end
		data.Chests.starter = 10
		local result = Game.action(ctx, server, player, "OpenChest", { Id = "starter", Amount = 10, Mode = "owned" })
		ctx.expect(result.ok).toBe(true)
		local sold = 0
		for _, r in ipairs(result.Results) do
			local item = Items.ById[r.Item]
			if item.RarityIndex <= 3 then
				ctx.expect(r.AutoSold).toBeGreaterThan(0)
				sold += 1
			end
		end
		ctx.expect(data.Stats.ItemsSold).toBe(sold)
	end)
end)

describe("Inventory", function()
	it("equips only owned items within the slot limit and sells safely", function(ctx)
		local server, player = setup(ctx)
		local data = Game.data(server, player)
		ctx.expect(Game.action(ctx, server, player, "Equip", { Id = "golden_plug" }).ok).toBe(false)
		data.Inventory.paper_clip = 3
		data.Inventory.rusty_bolt = 1
		data.Inventory.aa_battery = 1
		data.Inventory.light_bulb = 1
		for _, id in ipairs({ "paper_clip", "rusty_bolt", "aa_battery" }) do
			local r = Game.action(ctx, server, player, "Equip", { Id = id })
			ctx.expect(r.ok).toBe(true)
		end
		local full = Game.action(ctx, server, player, "Equip", { Id = "light_bulb" })
		ctx.expect(full.ok).toBe(false)
		ctx.expect(full.err).toMatch("slots are full")
		ctx.expect(Game.action(ctx, server, player, "Equip", { Id = "paper_clip" }).err).toMatch("Already")

		ctx.expect(Game.action(ctx, server, player, "Favorite", { Id = "paper_clip", State = true }).ok).toBe(true)
		local favSell = Game.action(ctx, server, player, "Sell", { Id = "paper_clip", Amount = 1 })
		ctx.expect(favSell.ok).toBe(false)
		ctx.expect(Game.action(ctx, server, player, "Sell", { Id = "rusty_bolt", Amount = 5 }).ok).toBe(false)
		ctx.expect(Game.action(ctx, server, player, "Sell", { Id = "rusty_bolt", Amount = -1 }).ok).toBe(false)
		local sold = Game.action(ctx, server, player, "Sell", { Id = "rusty_bolt", Amount = 1 })
		ctx.expect(sold.ok).toBe(true)
		ctx.expect(data.Inventory.rusty_bolt).toBeNil()
		ctx.expect(table.find(data.Equipped, "rusty_bolt")).toBeNil()
		ctx.expect(data.Currencies.Gems).toBe(sold.Gems)
		ctx.harness:advance(1)
		-- Favourites are kept by Sell duplicates.
		data.Inventory.aa_battery = 4
		local dupes = Game.action(ctx, server, player, "SellDuplicates", { MaxRarity = 2 })
		ctx.expect(dupes.ok).toBe(true)
		ctx.expect(data.Inventory.aa_battery).toBe(1)
		ctx.expect(data.Inventory.paper_clip).toBe(3)
	end)

	it("makes extra copies strengthen an equipped item", function(ctx)
		local server, player = setup(ctx)
		local data = Game.data(server, player)
		local StatsService = Game.service(server, "StatsService")
		local profile = Game.profile(server, player)
		data.Inventory.paper_clip = 1
		Game.action(ctx, server, player, "Equip", { Id = "paper_clip" })
		local one = StatsService:Get(profile).clickMultiplier
		data.Inventory.paper_clip = 11
		StatsService:Invalidate(profile)
		local eleven = StatsService:Get(profile).clickMultiplier
		ctx.expect(eleven).toBeGreaterThan(one)
	end)
end)

describe("Skill tree", function()
	it("enforces skill points and prerequisites", function(ctx)
		local server, player = setup(ctx)
		local data = Game.data(server, player)
		ctx.expect(Game.action(ctx, server, player, "UnlockSkill", { Id = "core" }).err).toMatch("Not enough Skill Points")
		data.SkillPoints = 10
		ctx.expect(Game.action(ctx, server, player, "UnlockSkill", { Id = "str_1" }).err).toMatch("connected skill")
		ctx.expect(Game.action(ctx, server, player, "UnlockSkill", { Id = "core" }).ok).toBe(true)
		ctx.expect(Game.action(ctx, server, player, "UnlockSkill", { Id = "core" }).err).toMatch("maxed")
		ctx.expect(Game.action(ctx, server, player, "UnlockSkill", { Id = "str_1" }).ok).toBe(true)
		ctx.expect(data.Skills.str_1).toBe(1)
		ctx.expect(data.SkillPoints).toBe(8)
		-- Respec refunds every point for Gems.
		ctx.harness:advance(6)
		ctx.expect(Game.action(ctx, server, player, "ResetSkills", {}).ok).toBe(false)
		data.Currencies.Gems = 500
		ctx.harness:advance(6)
		local reset = Game.action(ctx, server, player, "ResetSkills", {})
		ctx.expect(reset.ok).toBe(true)
		ctx.expect(data.SkillPoints).toBe(10)
		ctx.expect(next(data.Skills)).toBeNil()
	end)
end)

describe("Ascension", function()
	it("refuses early, then resets only the run and keeps permanent progress", function(ctx)
		local server, player = setup(ctx)
		local data = Game.data(server, player)
		ctx.expect(Game.action(ctx, server, player, "Rebirth", {}).ok).toBe(false)
		data.Currencies.Sparks = 5e6
		data.Currencies.Gems = 77
		data.Stats.SparksThisRun = 3e6
		data.Upgrades.click_power = 40
		data.Upgrades.generator = 12
		data.Inventory.paper_clip = 2
		data.Skills.core = 1
		data.Level = 9
		ctx.harness:advance(6)
		local result = Game.action(ctx, server, player, "Rebirth", {})
		ctx.expect(result.ok).toBe(true)
		ctx.expect(result.Prisms).toBeGreaterThanOrEqual(3)
		ctx.expect(data.Rebirths).toBe(1)
		ctx.expect(data.Currencies.Sparks).toBe(0)
		ctx.expect(next(data.Upgrades)).toBeNil()
		ctx.expect(data.Stats.SparksThisRun).toBe(0)
		ctx.expect(data.Currencies.Gems).toBe(77)
		ctx.expect(data.Currencies.Prisms).toBe(result.Prisms)
		ctx.expect(data.Inventory.paper_clip).toBe(2)
		ctx.expect(data.Skills.core).toBe(1)
		ctx.expect(data.Level).toBe(9)
		-- Stage 2 unlocks the Plasma Crate.
		local Formulas = Game.shared(server, "Formulas")
		ctx.expect(Formulas.stageFor(data.Rebirths).Id).toBe(2)
		-- Prism shop
		local buy = Game.action(ctx, server, player, "BuyAscension", { Id = "eternal_power" })
		ctx.expect(buy.ok).toBe(true)
		ctx.expect(data.Ascension.eternal_power).toBe(1)
	end)

	it("keeps Auto-Presser with Loyal Robots and grants Head Start sparks", function(ctx)
		local server, player = setup(ctx)
		local data = Game.data(server, player)
		data.Ascension.keep_auto = 1
		data.Ascension.head_start = 2
		data.Upgrades.auto_presser = 6
		data.Stats.SparksThisRun = 3e6
		Game.service(server, "StatsService"):Invalidate(Game.profile(server, player))
		local result = Game.action(ctx, server, player, "Rebirth", {})
		ctx.expect(result.ok).toBe(true)
		ctx.expect(data.Upgrades.auto_presser).toBe(6)
		ctx.expect(data.Currencies.Sparks).toBe(4000)
	end)
end)

describe("Quests, achievements and daily rewards", function()
	it("tracks the starter path and pays rewards once", function(ctx)
		local server, player = setup(ctx)
		local data = Game.data(server, player)
		local early = Game.action(ctx, server, player, "ClaimStarter", {})
		ctx.expect(early.ok).toBe(false)
		Game.press(ctx, server, player, 25)
		ctx.expect(data.Quests.StarterProgress).toBe(25)
		local claim = Game.action(ctx, server, player, "ClaimStarter", {})
		ctx.expect(claim.ok).toBe(true)
		ctx.expect(data.Quests.StarterIndex).toBe(2)
		ctx.expect(data.Stats.LifetimeSparks).toBeGreaterThanOrEqual(100)
	end)

	it("pays a daily quest only when complete and only once", function(ctx)
		local server, player = setup(ctx)
		local data = Game.data(server, player)
		local q = data.Quests.Daily[1]
		ctx.expect(Game.action(ctx, server, player, "ClaimQuest", { Index = 1 }).ok).toBe(false)
		ctx.expect(Game.action(ctx, server, player, "ClaimQuest", { Index = 9 }).ok).toBe(false)
		q.Progress = q.Target
		local gemsBefore = data.Currencies.Gems
		ctx.expect(Game.action(ctx, server, player, "ClaimQuest", { Index = 1 }).ok).toBe(true)
		ctx.expect(data.Currencies.Gems).toBeGreaterThan(gemsBefore - 1)
		ctx.harness:advance(1)
		ctx.expect(Game.action(ctx, server, player, "ClaimQuest", { Index = 1 }).err).toMatch("Already")
		ctx.expect(Game.action(ctx, server, player, "ClaimQuestBonus", {}).ok).toBe(false)
	end)

	it("unlocks achievements automatically from stats", function(ctx)
		local server, player = setup(ctx)
		local data = Game.data(server, player)
		data.Stats.TotalClicks = 99
		Game.press(ctx, server, player, 1)
		ctx.harness:advance(2)
		ctx.expect(data.Achievements.press_100).toBeTruthy()
		ctx.expect(data.Currencies.Gems).toBeGreaterThanOrEqual(10)
	end)

	it("lets the daily login reward be claimed once per UTC day", function(ctx)
		local server, player = setup(ctx)
		local data = Game.data(server, player)
		local first = Game.action(ctx, server, player, "ClaimDaily", {})
		ctx.expect(first.ok).toBe(true)
		ctx.expect(first.Streak).toBe(1)
		ctx.expect(data.Currencies.Gems).toBeGreaterThanOrEqual(15)
		ctx.harness:advance(3)
		ctx.expect(Game.action(ctx, server, player, "ClaimDaily", {}).ok).toBe(false)
	end)
end)

describe("Bonus orbs", function()
	it("only accepts the orb the server offered, once", function(ctx)
		local server, player, client = setup(ctx)
		local offered = nil
		local remote = client:find("ReplicatedStorage.Remotes.OrbSpawn")
		remote.OnClientEvent:Connect(function(info)
			offered = info
		end)
		for _ = 1, 80 do
			if offered then
				break
			end
			ctx.harness:advance(1)
		end
		ctx.expect(offered).toBeTruthy()
		ctx.expect(Game.action(ctx, server, player, "ClaimOrb", { Id = offered.Id + 1 }).ok).toBe(false)
		local ok = Game.action(ctx, server, player, "ClaimOrb", { Id = offered.Id })
		ctx.expect(ok.ok).toBe(true)
		ctx.expect(ok.Reward.Type).toBeTruthy()
		ctx.harness:advance(3)
		ctx.expect(Game.action(ctx, server, player, "ClaimOrb", { Id = offered.Id }).ok).toBe(false)
		ctx.expect(Game.data(server, player).Stats.OrbsCollected).toBe(1)
	end)
end)

describe("Settings and request validation", function()
	it("validates every setting and rejects unknown actions", function(ctx)
		local server, player = setup(ctx)
		ctx.expect(Game.action(ctx, server, player, "UpdateSettings", { Key = "SFX", Value = 0.3 }).ok).toBe(true)
		ctx.expect(Game.action(ctx, server, player, "UpdateSettings", { Key = "SFX", Value = 7 }).ok).toBe(false)
		ctx.expect(Game.action(ctx, server, player, "UpdateSettings", { Key = "ReducedMotion", Value = "yes" }).ok).toBe(false)
		ctx.expect(Game.action(ctx, server, player, "UpdateSettings", { Key = "IsAdmin", Value = true }).ok).toBe(false)
		ctx.expect(Game.data(server, player).Settings.SFX).toBe(0.3)
		ctx.expect(Game.action(ctx, server, player, "GiveMeEverything", {}).ok).toBe(false)
		ctx.expect(Game.action(ctx, server, player, 12345, {}).ok).toBe(false)
		ctx.expect(Game.action(ctx, server, player, string.rep("x", 500), {}).ok).toBe(false)
		local security = Game.service(server, "SecurityService")
		ctx.expect(security:GetCounts(player.UserId).UnknownAction).toBeGreaterThanOrEqual(1)
	end)

	it("rate limits action spam", function(ctx)
		local server, player = setup(ctx)
		local limited = 0
		for _ = 1, 30 do
			local r = Game.action(ctx, server, player, "ClaimDaily", {})
			if r.rateLimited then
				limited += 1
			end
		end
		ctx.expect(limited).toBeGreaterThan(20)
	end)
end)

return Test.collect()
