--[[
	Loads the real shared modules from src/ReplicatedStorage/Shared inside a
	mock world and checks configuration integrity, loot maths and formatting.
]]

local Test = require("../harness/Test")

local describe, it = Test.describe, Test.it

local SHARED = "ReplicatedStorage.Shared"

-- A world with the Rojo project loaded but no scripts running.
local function sharedWorld(ctx, role: string?)
	return ctx.harness:createWorld({ role = role or "client", loadProject = true })
end

local function req(world, path: string)
	return world:requirePath(SHARED .. "." .. path)
end

local function isFinite(n): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

describe("Configuration", function()
	it("loads every config module", function(ctx)
		local world = sharedWorld(ctx)
		for _, name in ipairs({ "GameConfig", "Rarities", "Items", "Chests", "Skills", "Upgrades", "Ascension", "Achievements", "Quests", "Rewards", "Sounds" }) do
			local module = req(world, "Config." .. name)
			ctx.expect(type(module)).toBe("table")
		end
		for _, name in ipairs({ "Formulas", "Loot", "Format", "Util", "Signal", "Remotes" }) do
			ctx.expect(type(req(world, name))).toBe("table")
		end
	end)

	it("gives every weighted rarity of every crate a non-empty item pool", function(ctx)
		local world = sharedWorld(ctx)
		local Chests = req(world, "Config.Chests")
		local Items = req(world, "Config.Items")
		local Rarities = req(world, "Config.Rarities")
		ctx.expect(#Chests.List).toBeGreaterThan(0)
		for _, chest in ipairs(Chests.List) do
			for rarityId, weight in pairs(chest.Weights) do
				ctx.expect(Rarities.ById[rarityId]).toBeTruthy()
				if weight > 0 then
					local pool = Items.PoolByChest[chest.Id]
					ctx.expect(pool and pool[rarityId] and #pool[rarityId] or 0).toBeGreaterThan(0)
				end
			end
		end
		for _, item in ipairs(Items.List) do
			ctx.expect(Chests.ById[item.Chest]).toBeTruthy()
			ctx.expect(isFinite(item.Bonus)).toBe(true)
			ctx.expect(item.SellValue).toBeGreaterThanOrEqual(1)
		end
	end)

	it("keeps skill prerequisites, upgrades, achievements and quests consistent", function(ctx)
		local world = sharedWorld(ctx)
		local Skills = req(world, "Config.Skills")
		local Upgrades = req(world, "Config.Upgrades")
		local Achievements = req(world, "Config.Achievements")
		local Quests = req(world, "Config.Quests")
		local Chests = req(world, "Config.Chests")
		for _, node in ipairs(Skills.List) do
			for _, reqId in ipairs(node.Requires) do
				ctx.expect(Skills.ById[reqId]).toBeTruthy()
			end
			for _, reqId in ipairs(node.RequiresAny) do
				ctx.expect(Skills.ById[reqId]).toBeTruthy()
			end
			ctx.expect(node.MaxRank).toBeGreaterThanOrEqual(1)
		end
		for _, def in ipairs(Upgrades.List) do
			ctx.expect(def.MaxLevel).toBeGreaterThan(0)
			ctx.expect(isFinite(def.Value(0))).toBe(true)
			ctx.expect(isFinite(def.Value(def.MaxLevel))).toBe(true)
			ctx.expect(def.Value(def.MaxLevel) >= def.Value(1)).toBe(true)
		end
		local function checkReward(reward)
			for chestId in pairs(reward.Chests or {}) do
				ctx.expect(Chests.ById[chestId]).toBeTruthy()
			end
		end
		for _, a in ipairs(Achievements.List) do
			ctx.expect(a.Target).toBeGreaterThan(0)
			checkReward(a.Reward)
		end
		for _, q in ipairs(Quests.Daily) do
			checkReward(q.Reward)
		end
		for _, q in ipairs(Quests.Starter) do
			checkReward(q.Reward)
		end
	end)
end)

describe("Skill tree", function()
	it("is a large, well-formed tree that can be bought from the core outward", function(ctx)
		local world = sharedWorld(ctx)
		local Skills = req(world, "Config.Skills")
		ctx.expect(#Skills.List).toBeGreaterThanOrEqual(55)
		ctx.expect(#Skills.List).toBeLessThanOrEqual(70)
		-- Unique grid positions and positive costs.
		local cells = {}
		for _, node in ipairs(Skills.List) do
			local key = `{node.X},{node.Y}`
			ctx.expect(cells[key]).toBeNil()
			cells[key] = node.Id
			ctx.expect(node.Cost).toBeGreaterThan(0)
			ctx.expect(node.CostStep).toBeGreaterThanOrEqual(0)
			ctx.expect(Skills.Branches[node.Branch]).toBeTruthy()
			ctx.expect(#node.Effects).toBeGreaterThan(0)
		end
		-- Buying greedily from the core must eventually own every node: this proves that
		-- every node is reachable and that no prerequisites form a cycle.
		local owned = {}
		local count = 0
		repeat
			local progressed = false
			for _, node in ipairs(Skills.List) do
				if not owned[node.Id] and Skills.prerequisitesMet(node, owned) then
					owned[node.Id] = node.MaxRank
					count += 1
					progressed = true
				end
			end
		until not progressed
		ctx.expect(count).toBe(#Skills.List)
		-- Every main branch has a capstone and an ascended capstone further out.
		for _, id in ipairs({ "str_cap", "luck_cap", "wealth_cap", "crit_cap", "str_cap2", "luck_cap2", "wealth_cap2", "crit_cap2" }) do
			ctx.expect(Skills.ById[id]).toBeTruthy()
			ctx.expect(Skills.ById[id].MaxRank).toBe(1)
		end
		-- The full tree is a long-term goal, not something finished in a few sessions.
		local total = 0
		for _, node in ipairs(Skills.List) do
			total += Skills.totalCost(node, node.MaxRank)
		end
		ctx.expect(total).toBeGreaterThan(350)
		ctx.expect(total).toBeLessThan(600)
	end)

	it("reveals the tree step by step as nodes are bought", function(ctx)
		local world = sharedWorld(ctx)
		local Skills = req(world, "Config.Skills")
		local function counts(vis)
			local n = { visible = 0, teaser = 0, hidden = 0 }
			for _, state in pairs(vis) do
				n[state] += 1
			end
			return n
		end

		-- A fresh player sees the core and its four neighbours as "?" teasers only.
		local fresh = Skills.visibility({})
		ctx.expect(fresh.core).toBe("visible")
		for _, id in ipairs({ "str_1", "luck_1", "wealth_1", "crit_1" }) do
			ctx.expect(fresh[id]).toBe("teaser")
		end
		ctx.expect(fresh.str_2).toBe("hidden")
		ctx.expect(fresh.bridge_sl).toBe("hidden")
		ctx.expect(fresh.str_cap2).toBe("hidden")
		ctx.expect(counts(fresh).visible).toBe(1)
		ctx.expect(counts(fresh).teaser).toBe(4)

		-- Buying the core reveals its neighbours; the next ring becomes teasers.
		local afterCore = Skills.visibility({ core = 1 })
		ctx.expect(afterCore.str_1).toBe("visible")
		ctx.expect(afterCore.str_2).toBe("teaser")
		ctx.expect(afterCore.bridge_sl).toBe("teaser")
		ctx.expect(afterCore.str_5).toBe("hidden")
		ctx.expect(counts(afterCore).visible).toBe(5)

		-- Nodes with two parents stay a teaser until both are owned.
		ctx.expect(Skills.visibility({ core = 1, str_1 = 1 }).bridge_sl).toBe("teaser")
		ctx.expect(Skills.visibility({ core = 1, str_1 = 1, luck_1 = 1 }).bridge_sl).toBe("visible")

		-- "One of" prerequisites: one owned parent is enough.
		local any = Skills.visibility({ core = 1, str_1 = 1 })
		ctx.expect(any.str_4).toBe("visible")
		ctx.expect(any.spec_orb).toBe("teaser")
		ctx.expect(Skills.visibility({ core = 1, str_1 = 1, str_4 = 1 }).spec_orb).toBe("visible")

		-- Owning everything shows everything; a respec collapses it again.
		local all = {}
		for _, node in ipairs(Skills.List) do
			all[node.Id] = node.MaxRank
		end
		ctx.expect(counts(Skills.visibility(all)).visible).toBe(#Skills.List)
		ctx.expect(counts(Skills.visibility({})).visible).toBe(1)
	end)
end)

describe("Loot", function()
	it("normalises effective weights for any luck value", function(ctx)
		local world = sharedWorld(ctx)
		local Chests = req(world, "Config.Chests")
		local Loot = req(world, "Loot")
		for _, chest in ipairs(Chests.List) do
			for _, luck in ipairs({ 0, 0.5, 2, 10 }) do
				local total = 0
				for _, entry in ipairs(Loot.effectiveWeights(chest, luck)) do
					total += entry.Chance
				end
				ctx.expect(total).toBeCloseTo(1, 1e-9)
			end
		end
	end)

	it("matches expected odds over 20,000 simulated openings per crate", function(ctx)
		local world = sharedWorld(ctx)
		local Chests = req(world, "Config.Chests")
		local Loot = req(world, "Loot")
		local Random = world.baseEnv.Random
		local n = 20000
		for _, chest in ipairs(Chests.List) do
			local counts = Loot.simulate(Random.new(1234 + chest.Order), chest, 0, n, {})
			for _, entry in ipairs(Loot.effectiveWeights(chest, 0)) do
				local observed = (counts[entry.Rarity] or 0) / n
				local p = entry.Chance
				local tolerance = 5 * math.sqrt(p * (1 - p) / n) + 0.002
				if math.abs(observed - p) > tolerance then
					error(string.format("%s %s: observed %.4f, expected %.4f (±%.4f)", chest.Id, entry.Rarity, observed, p, tolerance))
				end
			end
		end
	end)

	it("guarantees Legendary or better when the pity threshold is reached", function(ctx)
		local world = sharedWorld(ctx)
		local Chests = req(world, "Config.Chests")
		local Loot = req(world, "Loot")
		local Rarities = req(world, "Config.Rarities")
		local Random = world.baseEnv.Random
		local legendaryIndex = Rarities.ById.Legendary.Index
		for _, chest in ipairs(Chests.List) do
			local threshold = chest.Pity and chest.Pity.Legendary
			if threshold then
				-- One opening before the threshold: the next roll must be Legendary+.
				local pity = { Legendary = threshold - 1 }
				local _, rarityId, triggered = Loot.roll(Random.new(1), chest, 0, pity, { Legendary = threshold })
				ctx.expect(Rarities.ById[rarityId].Index).toBeGreaterThanOrEqual(legendaryIndex)
				ctx.expect(triggered).toBe(true)
				ctx.expect(pity.Legendary).toBe(0)
				-- Over a long run the gap between Legendary+ drops never exceeds the threshold.
				local rng = Random.new(99)
				local state = {}
				local gap = 0
				for _ = 1, 3000 do
					local _, r = Loot.roll(rng, chest, 0, state, { Legendary = threshold })
					gap += 1
					if Rarities.ById[r].Index >= legendaryIndex then
						ctx.expect(gap).toBeLessThanOrEqual(threshold)
						gap = 0
					end
				end
			end
		end
	end)
end)

describe("Economy invariants", function()
	it("never lets a Gem-priced crate be resold for more Gems than it costs, even fully maxed", function(ctx)
		local world = sharedWorld(ctx)
		local Chests = req(world, "Config.Chests")
		local Items = req(world, "Config.Items")
		local Upgrades = req(world, "Config.Upgrades")
		local Skills = req(world, "Config.Skills")
		local Ascension = req(world, "Config.Ascension")
		local GameConfig = req(world, "Config.GameConfig")
		local Formulas = req(world, "Formulas")
		local Loot = req(world, "Loot")
		local GamePasses = req(world, "Config.GamePasses")

		-- Every upgrade, skill and perk maxed, the strongest luck and gem items equipped
		-- with plenty of copies, every Robux game pass owned, and every event running at once.
		local data = { Rebirths = 1000, Upgrades = {}, Skills = {}, Ascension = {}, Inventory = {}, Equipped = {}, Discovered = {}, Passes = {} }
		for index, pass in ipairs(GamePasses.List) do
			pass.GamePassId = 9000 + index
			data.Passes[pass.Key] = true
		end
		for _, def in ipairs(Upgrades.List) do
			data.Upgrades[def.Id] = def.MaxLevel
		end
		for _, def in ipairs(Skills.List) do
			data.Skills[def.Id] = def.MaxRank
		end
		for _, def in ipairs(Ascension.List) do
			data.Ascension[def.Id] = def.MaxLevel
		end
		local candidates = {}
		for _, item in ipairs(Items.List) do
			local stat = GameConfig.ItemStats[item.Stat].Stat
			if stat == "luck" or stat == "gemsPct" then
				table.insert(candidates, item)
			end
		end
		table.sort(candidates, function(a, b)
			return a.Bonus > b.Bonus
		end)
		for i = 1, math.min(GameConfig.Equip.MaxSlots, #candidates) do
			data.Equipped[i] = candidates[i].Id
			data.Inventory[candidates[i].Id] = 1000
		end
		local events = {}
		for id in pairs(GameConfig.Events.Definitions) do
			table.insert(events, id)
		end
		local stats = Formulas.computeStats(data, { Events = events })
		ctx.expect(stats.luck).toBeGreaterThan(0)

		local checked = 0
		for _, chest in ipairs(Chests.List) do
			if chest.Currency == "Gems" then
				checked += 1
				-- No discounts or bonus drops apply to Gem crates.
				ctx.expect(Formulas.chestPrice(chest, 0.6)).toBe(chest.Price)
				ctx.expect(Formulas.chestBonusChance(chest, 0.75)).toBe(0)
				-- Conservative: value every rarity at its most valuable item.
				local expected = 0
				for _, entry in ipairs(Loot.effectiveWeights(chest, stats.luck)) do
					local best = 0
					for _, itemId in ipairs(Items.PoolByChest[chest.Id][entry.Rarity]) do
						best = math.max(best, Formulas.sellValue(Items.ById[itemId], 1, stats.gemMultiplier))
					end
					expected += entry.Chance * best
				end
				print(`    {chest.Id}: resale ≤ {math.floor(expected)} of {chest.Price} Gems (luck +{math.floor(stats.luck * 100)}%, gems ×{stats.gemMultiplier})`)
				ctx.expect(expected).toBeLessThan(chest.Price)
			end
		end
		ctx.expect(checked).toBeGreaterThan(0)
	end)
end)

describe("Formulas and Format", function()
	it("computes finite stats for fresh and heavily progressed players", function(ctx)
		local world = sharedWorld(ctx)
		local Formulas = req(world, "Formulas")
		local Upgrades = req(world, "Config.Upgrades")
		local Skills = req(world, "Config.Skills")
		local Items = req(world, "Config.Items")
		local fresh = { Upgrades = {}, Ascension = {}, Skills = {}, Inventory = {}, Equipped = {}, Discovered = {}, Rebirths = 0 }
		local maxed = { Upgrades = {}, Ascension = {}, Skills = {}, Inventory = {}, Equipped = {}, Discovered = {}, Rebirths = 25 }
		for _, def in ipairs(Upgrades.List) do
			maxed.Upgrades[def.Id] = def.MaxLevel
		end
		for _, node in ipairs(Skills.List) do
			maxed.Skills[node.Id] = node.MaxRank
		end
		for i, item in ipairs(Items.List) do
			maxed.Inventory[item.Id] = 50
			maxed.Discovered[item.Id] = 1
			if i <= 8 then
				table.insert(maxed.Equipped, item.Id)
			end
		end
		for _, data in ipairs({ fresh, maxed }) do
			local stats = Formulas.computeStats(data, { Events = {}, FrenzyMultiplier = 1 })
			for key, value in pairs(stats) do
				if type(value) == "number" then
					if not isFinite(value) then
						error(string.format("stat %s is not finite: %s", key, tostring(value)))
					end
				end
			end
			ctx.expect(stats.clickValue).toBeGreaterThan(0)
		end
	end)

	it("computes stats from the server's default player data", function(ctx)
		local world = ctx.harness:createWorld({ role = "server", loadProject = true })
		local schemaPath = "ServerScriptService.Core.DataSchema"
		if not world:find(schemaPath) then
			ctx.log("DataSchema not present yet; skipping")
			return
		end
		local DataSchema = world:requirePath(schemaPath)
		local Formulas = world:requirePath(SHARED .. ".Formulas")
		local stats = Formulas.computeStats(DataSchema.default(), { Events = {}, FrenzyMultiplier = 1 })
		ctx.expect(isFinite(stats.clickValue)).toBe(true)
		ctx.expect(stats.clickValue).toBeGreaterThan(0)
	end)

	it("formats numbers like the UI expects", function(ctx)
		local world = sharedWorld(ctx)
		local Format = req(world, "Format")
		ctx.expect(Format.short(0)).toBe("0")
		ctx.expect(Format.short(999)).toBe("999")
		ctx.expect(Format.short(1000)).toBe("1K")
		ctx.expect(Format.short(1234567)).toBe("1.23M")
		ctx.expect(Format.short(-1500)).toBe("-1.5K")
		ctx.expect(Format.short(0 / 0)).toBe("0")
		ctx.expect(Format.short(math.huge)).toBe("∞")
		ctx.expect(Format.short(1e15)).toMatch("^1%a+$")
		ctx.expect(Format.short(1e100)).toMatch("e100$")
		ctx.expect(Format.commas(1234567)).toBe("1,234,567")
	end)
end)

return Test.collect()
