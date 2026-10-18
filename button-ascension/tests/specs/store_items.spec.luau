--[[
	The owner's own store items from the Creator Hub: OP CLICKER (the OP Auto
	Clicker pass) and nine items that give exactly what their names say. They
	were created as game passes; the server confirms the kind with Roblox and
	also handles them as developer products if that is what they are.
]]

local roblox = require("@lune/roblox")
local Test = require("../harness/Test")
local Game = require("../helpers/Game")

local describe, it = Test.describe, Test.it

local IDS = {
	starter_pack = 2037646106,
	op_sparks_200k = 2039811962,
	sparks_60k = 2036914125,
	sparks_30k = 2037322132,
	boost_lucky_hour = 2039895926,
	boost_spark_surge = 2038198094,
	op_gems_15k = 2036932058,
	gems_600 = 2039937934,
	gems_120 = 2039541981,
}
local OP_CLICKER = 2038330114
local USER = 7701

local function ownedAll()
	local owned = { [OP_CLICKER] = true }
	for _, id in pairs(IDS) do
		owned[id] = true
	end
	return owned
end

local function statsOf(server, player)
	return Game.service(server, "StatsService"):Get(Game.profile(server, player))
end

describe("Owner's store items", function()
	it("has every Creator Hub ID in the right place", function(ctx)
		local server = Game.server(ctx)
		local GamePasses = Game.shared(server, "Config.GamePasses")
		local DevProducts = Game.shared(server, "Config.DevProducts")
		ctx.expect(GamePasses.ByKey.op_auto_clicker.GamePassId).toBe(OP_CLICKER)
		ctx.expect(GamePasses.ByKey.op_auto_clicker.HubName).toBe("OP CLICKER")
		local seen = { [OP_CLICKER] = true }
		for key, id in pairs(IDS) do
			local product = DevProducts.ByKey[key]
			ctx.expect(product).toBeTruthy()
			ctx.expect(product.GamePassId).toBe(id)
			ctx.expect(type(product.HubName)).toBe("string")
			ctx.expect(seen[id]).toBeNil()
			seen[id] = true
		end
	end)

	it("gives what each name says, once, when the passes are owned", function(ctx)
		local h = ctx.harness
		local server = Game.server(ctx, { marketplace = { owned = { [USER] = ownedAll() } } })
		local player = Game.join(ctx, server, USER, "Buyer")
		h:advance(3)
		local data = Game.data(server, player)
		-- Sparks: 25,000 (Starter Pack) + 30,000 + 60,000 + 200,000, plus what the
		-- OP CLICKER's auto presses earned in the meantime.
		ctx.expect(data.Currencies.Sparks).toBeGreaterThanOrEqual(315000)
		ctx.expect(data.Currencies.Sparks).toBeLessThan(316000)
		-- Gems: 150 (Starter Pack) + 120 + 600 + 15,000.
		ctx.expect(data.Currencies.Gems).toBe(15870)
		-- Starter Pack crates: 3 of the best unlocked Spark crate.
		local crates = 0
		for _, count in pairs(data.Chests) do
			crates += count
		end
		ctx.expect(crates).toBe(3)
		-- One hour of Lucky Hour and of Spark Surge.
		ctx.expect(data.Boosts.boost_lucky_hour).toBeGreaterThan(3590)
		ctx.expect(data.Boosts.boost_spark_surge).toBeGreaterThan(3590)
		for key in pairs(IDS) do
			ctx.expect(data.PassRewards[key]).toBe(true)
		end
		-- OP CLICKER: +15 auto presses per second; boosts: +100% Luck, ×2 Sparks.
		local stats = statsOf(server, player)
		local plain = table.clone(data)
		plain.Passes = {}
		plain.Boosts = {}
		local base = Game.shared(server, "Formulas").computeStats(plain, { Events = {} })
		ctx.expect(stats.autoRate).toBe(base.autoRate + 15)
		ctx.expect(math.abs(stats.luck - base.luck - 1)).toBeLessThan(1e-9)
		ctx.expect(math.abs(stats.sparksMultiplier / base.sparksMultiplier - 2)).toBeLessThan(1e-9)

		-- Rejoining never pays the one-time rewards again.
		h:removePlayer(player)
		h:advance(5)
		local again = Game.join(ctx, server, USER, "Buyer")
		h:advance(3)
		local after = Game.data(server, again)
		ctx.expect(after.Currencies.Sparks).toBeLessThan(320000)
		ctx.expect(after.Currencies.Gems).toBe(15870)
	end)

	it("grants a pass bought in the game right away, and only once", function(ctx)
		local h = ctx.harness
		local server = Game.server(ctx)
		local player = Game.join(ctx, server, USER, "Buyer")
		h:advance(2)
		local data = Game.data(server, player)
		local market = server.services.MarketplaceService
		h:fire(market, "PromptGamePassPurchaseFinished", player, IDS.sparks_30k, true)
		h:advance(1)
		ctx.expect(data.Currencies.Sparks).toBe(30000)
		-- A cancelled prompt or a repeated event grants nothing more.
		h:fire(market, "PromptGamePassPurchaseFinished", player, IDS.sparks_30k, true)
		h:fire(market, "PromptGamePassPurchaseFinished", player, IDS.gems_600, false)
		h:advance(1)
		ctx.expect(data.Currencies.Sparks).toBe(30000)
		ctx.expect(data.Currencies.Gems).toBe(0)
		-- A client cannot fake it.
		local forged = Game.action(ctx, server, player, "BuyPass", { Id = IDS.gems_600 })
		ctx.expect(forged.ok).toBe(false)
		ctx.expect(data.Currencies.Gems).toBe(0)
	end)

	it("sells an item as a developer product when Roblox says it is one", function(ctx)
		local h = ctx.harness
		local server = Game.server(ctx, {
			marketplace = { info = { [IDS.gems_600] = { Kind = "product", Name = "Gems 600", Price = 99 } } },
		})
		local player, client = Game.join(ctx, server, USER, "Buyer")
		h:advance(3)
		local RobuxSale = Game.shared(server, "RobuxSale")
		local DevProducts = Game.shared(server, "Config.DevProducts")
		local kind, id = RobuxSale.of(DevProducts.ByKey.gems_600)
		ctx.expect(kind).toBe("product")
		ctx.expect(id).toBe(IDS.gems_600)
		local granted = roblox.Enum.ProductPurchaseDecision.PurchaseGranted
		local function buy(purchaseId: string)
			return h:processReceipt(server, { PlayerId = USER, ProductId = IDS.gems_600, PurchaseId = purchaseId, CurrencySpent = 99, CurrencyType = "Robux" })
		end
		-- Repeatable as a product, but each receipt counts once.
		ctx.expect(buy("p-1")).toBe(granted)
		ctx.expect(buy("p-2")).toBe(granted)
		ctx.expect(buy("p-2")).toBe(granted)
		ctx.expect(Game.data(server, player).Currencies.Gems).toBe(1200)

		-- The store opens the developer-product prompt for it.
		local gui = client:find("Players.Buyer.PlayerGui.ButtonAscensionUI")
		h:click(h:findDescendant(gui, "NavRail", "Frame"):FindFirstChild("Store"))
		h:advance(1)
		local window = h:findDescendant(gui, "Store", "Frame")
		h:click(h:findDescendant(window, "gems_600", "Frame"):FindFirstChild("Buy"))
		h:advance(0.5)
		local last = client.prompts[#client.prompts]
		ctx.expect(last.kind).toBe("product")
		ctx.expect(last.id).toBe(IDS.gems_600)
		-- And the game-pass prompt for the items that are passes.
		h:click(h:findDescendant(window, "gems_120", "Frame"):FindFirstChild("Buy"))
		h:advance(0.5)
		last = client.prompts[#client.prompts]
		ctx.expect(last.kind).toBe("gamepass")
		ctx.expect(last.id).toBe(IDS.gems_120)
	end)

	it("shows owned one-time items and items that are not for sale yet", function(ctx)
		local h = ctx.harness
		local server = Game.server(ctx, { marketplace = { owned = { [USER] = { [IDS.gems_120] = true } } } })
		local _, client = Game.join(ctx, server, USER, "Buyer")
		h:advance(3)
		client.marketplace.info[IDS.sparks_60k] = { Kind = "pass", Name = "Spark 60000", ForSale = false }
		local gui = client:find("Players.Buyer.PlayerGui.ButtonAscensionUI")
		h:click(h:findDescendant(gui, "NavRail", "Frame"):FindFirstChild("Store"))
		h:advance(1)
		local window = h:findDescendant(gui, "Store", "Frame")
		ctx.expect(h:findDescendant(window, "gems_120", "Frame"):FindFirstChild("Buy").Text).toMatch("Owned")
		ctx.expect(h:findDescendant(window, "sparks_60k", "Frame"):FindFirstChild("Buy").Text).toMatch("Not for sale")
		local prompts = #client.prompts
		h:click(h:findDescendant(window, "sparks_60k", "Frame"):FindFirstChild("Buy"))
		h:click(h:findDescendant(window, "gems_120", "Frame"):FindFirstChild("Buy"))
		h:advance(0.5)
		ctx.expect(#client.prompts).toBe(prompts)
	end)

	it("keeps one-time rewards through saving and a full admin reset", function(ctx)
		local h = ctx.harness
		local server = Game.server(ctx, { isStudio = true, marketplace = { owned = { [-4] = { [IDS.gems_600] = true } } } })
		local owner = Game.join(ctx, server, -1, "Owner")
		local player = Game.join(ctx, server, -4, "Player")
		h:advance(3)
		local data = Game.data(server, player)
		ctx.expect(data.PassRewards.gems_600).toBe(true)
		local DataSchema = server:requirePath("ServerScriptService.Core.DataSchema")
		local clean = DataSchema.sanitize({ Version = 2, PassRewards = { gems_600 = true, made_up = true } })
		ctx.expect(clean.PassRewards.gems_600).toBe(true)
		ctx.expect(clean.PassRewards.made_up).toBeNil()
		local ask = Game.admin(ctx, server, owner, "progression.reset", { Target = "Player", Scope = "all" })
		ctx.expect(Game.admin(ctx, server, owner, "confirm", { Token = ask.token }).ok).toBe(true)
		h:advance(2)
		-- The reward is not granted a second time after the reset.
		ctx.expect(data.PassRewards.gems_600).toBe(true)
		ctx.expect(data.Currencies.Gems).toBe(0)
	end)
end)

return Test.collect()
