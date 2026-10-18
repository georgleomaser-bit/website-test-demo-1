--[[
	Robux monetization: game passes (GamePassService) and developer products
	(ProductService / ProcessReceipt). Ownership and rewards are decided by the
	server only; the client can merely open Roblox's purchase prompt.

	The mock MarketplaceService (tests/harness/Services.luau) reports the
	owned passes from the world option `marketplace.owned`, can fail on demand
	(`marketplace.failures`) and records purchase prompts in `world.prompts`.
	Harness:processReceipt calls the server's ProcessReceipt callback.
]]

local Test = require("../harness/Test")
local Game = require("../helpers/Game")

local describe, it = Test.describe, Test.it

local PASS_IDS = {
	auto_clicker = 1001,
	op_auto_clicker = 1002,
	double_sparks = 1003,
	triple_sparks = 1004,
	double_gems = 1005,
	lucky = 1006,
	super_luck = 1007,
	fast_crates = 1008,
	vip = 1009,
}
local PRODUCT_IDS = {
	gems_small = 2001,
	gems_medium = 2002,
	gems_large = 2003,
	sparks_rush = 2004,
	crate_bundle = 2005,
	op_crate = 2006,
	mega_op_crate = 2007,
	ultra_op_crate = 2008,
}

-- Pastes test IDs into a world's config, like the owner does in Studio.
local function configure(world)
	local GamePasses = Game.shared(world, "Config.GamePasses")
	for key, id in pairs(PASS_IDS) do
		GamePasses.ByKey[key].GamePassId = id
	end
	local DevProducts = Game.shared(world, "Config.DevProducts")
	for key, id in pairs(PRODUCT_IDS) do
		DevProducts.ByKey[key].ProductId = id
	end
end

local function liveServer(ctx, owned)
	local server = Game.server(ctx, { marketplace = { owned = owned or {} } })
	configure(server)
	return server
end

local function statsOf(server, player)
	return Game.service(server, "StatsService"):Get(Game.profile(server, player))
end

-- Stats of the same data without any passes or boosts.
local function baseStats(server, player)
	local data = table.clone(Game.data(server, player))
	data.Passes = {}
	data.Boosts = {}
	return Game.shared(server, "Formulas").computeStats(data, { Events = {} })
end

local function receipt(userId: number, productKey: string, purchaseId: string)
	return { PlayerId = userId, ProductId = PRODUCT_IDS[productKey], PurchaseId = purchaseId, CurrencySpent = 99, CurrencyType = "Robux" }
end

local function stored(h, userId: number)
	return h.backend:peek(Game.STORE, Game.storeKey(userId))
end

describe("Game passes", function()
	it("loads owned passes on join and applies them on the server", function(ctx)
		local h = ctx.harness
		local server = liveServer(ctx, { [7001] = { [PASS_IDS.auto_clicker] = true, [PASS_IDS.double_sparks] = true } })
		local player = Game.join(ctx, server, 7001, "Buyer")
		h:advance(2)
		local data = Game.data(server, player)
		ctx.expect(data.Passes.auto_clicker).toBe(true)
		ctx.expect(data.Passes.double_sparks).toBe(true)
		ctx.expect(data.Passes.lucky).toBeNil()
		local stats = statsOf(server, player)
		ctx.expect(stats.autoRate).toBe(5)
		ctx.expect(stats.clickValue).toBe(baseStats(server, player).clickValue * 2)
		-- The server presses on its own at the pass rate.
		local before = data.Stats.AutoClicks
		h:advance(10)
		local pressed = data.Stats.AutoClicks - before
		ctx.expect(pressed).toBeGreaterThanOrEqual(45)
		ctx.expect(pressed).toBeLessThanOrEqual(55)
	end)

	it("adds auto clicker passes on top of the upgrade cap and stacks the OP passes", function(ctx)
		local server = liveServer(ctx, {
			[7002] = {
				[PASS_IDS.auto_clicker] = true,
				[PASS_IDS.op_auto_clicker] = true,
				[PASS_IDS.double_sparks] = true,
				[PASS_IDS.triple_sparks] = true,
				[PASS_IDS.double_gems] = true,
				[PASS_IDS.lucky] = true,
				[PASS_IDS.super_luck] = true,
				[PASS_IDS.vip] = true,
			},
		})
		local player = Game.join(ctx, server, 7002, "Whale")
		ctx.harness:advance(2)
		local profile = Game.profile(server, player)
		local Upgrades = Game.shared(server, "Config.Upgrades")
		local GameConfig = Game.shared(server, "Config.GameConfig")
		profile.Data.Upgrades.auto_presser = Upgrades.ById.auto_presser.MaxLevel
		Game.service(server, "StatsService"):Invalidate(profile)
		local stats = statsOf(server, player)
		local base = baseStats(server, player)
		-- Pass presses come on top of the (capped) upgrade rate, beyond the cap.
		ctx.expect(stats.autoRate).toBe(base.autoRate + 20)
		ctx.expect(stats.autoRate).toBeGreaterThan(GameConfig.AutoClick.MaxRate)
		-- ×2 × ×3 × VIP ×1.25 = ×7.5 Sparks; ×2 × ×1.25 Gems; +200% Luck.
		ctx.expect(math.abs(stats.sparksMultiplier / base.sparksMultiplier - 7.5)).toBeLessThan(1e-9)
		ctx.expect(math.abs(stats.gemMultiplier / base.gemMultiplier - 2.5)).toBeLessThan(1e-9)
		ctx.expect(math.abs(stats.luck - base.luck - 2)).toBeLessThan(1e-9)
		ctx.expect(math.abs(stats.xpMultiplier / base.xpMultiplier - 1.25)).toBeLessThan(1e-9)
	end)

	it("grants a pass the moment Roblox reports the purchase and keeps it for the session", function(ctx)
		local h = ctx.harness
		local server = liveServer(ctx)
		local player = Game.join(ctx, server, 7003, "Shopper")
		h:advance(2)
		local data = Game.data(server, player)
		local market = server.services.MarketplaceService
		h:fire(market, "PromptGamePassPurchaseFinished", player, PASS_IDS.lucky, false)
		h:fire(market, "PromptGamePassPurchaseFinished", player, 999999, true)
		h:advance(1)
		ctx.expect(next(data.Passes)).toBeNil()

		h:fire(market, "PromptGamePassPurchaseFinished", player, PASS_IDS.fast_crates, true)
		h:advance(5)
		ctx.expect(data.Passes.fast_crates).toBe(true)
		ctx.expect(stored(h, 7003).Data.Passes.fast_crates).toBe(true)
		-- Roblox's ownership answer can lag behind a fresh purchase; it must not undo it.
		local GamePassService = Game.service(server, "GamePassService")
		h:run(function()
			GamePassService:Refresh(Game.profile(server, player))
		end)
		ctx.expect(data.Passes.fast_crates).toBe(true)

		-- Fast Crates: up to 20 crates per opening instead of 10.
		data.Chests.starter = 25
		ctx.expect(Game.action(ctx, server, player, "OpenChest", { Id = "starter", Amount = 21, Mode = "owned" }).ok).toBe(false)
		h:advance(1)
		local opened = Game.action(ctx, server, player, "OpenChest", { Id = "starter", Amount = 20, Mode = "owned" })
		ctx.expect(opened.ok).toBe(true)
		ctx.expect(data.Chests.starter).toBe(5)
	end)

	it("keeps the last saved ownership when Roblox can't answer, and drops refunded passes", function(ctx)
		local h = ctx.harness
		ctx.allowScriptErrors()
		local server = liveServer(ctx, { [7004] = { [PASS_IDS.double_gems] = true } })
		local player = Game.join(ctx, server, 7004, "Returner")
		h:advance(2)
		ctx.expect(Game.data(server, player).Passes.double_gems).toBe(true)
		h:removePlayer(player)
		h:advance(5)

		-- Roblox is down on the next join: the stored answer stays.
		server.marketplace.owned[7004] = nil
		server.marketplace.failures = 1000
		local again = Game.join(ctx, server, 7004, "Returner")
		h:advance(90)
		ctx.expect(Game.data(server, again).Passes.double_gems).toBe(true)
		ctx.expect(statsOf(server, again).gemMultiplier).toBe(baseStats(server, again).gemMultiplier * 2)

		-- Once Roblox answers again, a refunded pass is removed.
		server.marketplace.failures = 0
		h:run(function()
			Game.service(server, "GamePassService"):Refresh(Game.profile(server, again))
		end)
		ctx.expect(Game.data(server, again).Passes.double_gems).toBeNil()
	end)

	it("does nothing for passes that are not set up yet", function(ctx)
		local h = ctx.harness
		local server = Game.server(ctx, { marketplace = { owned = { [7005] = { [1003] = true } } } })
		local player = Game.join(ctx, server, 7005, "Early")
		h:advance(2)
		local profile = Game.profile(server, player)
		ctx.expect(next(profile.Data.Passes)).toBeNil()
		-- Even a stored flag has no effect while the pass has no GamePassId.
		profile.Data.Passes.triple_sparks = true
		Game.service(server, "StatsService"):Invalidate(profile)
		ctx.expect(statsOf(server, player).clickValue).toBe(baseStats(server, player).clickValue)
		h:fire(server.services.MarketplaceService, "PromptGamePassPurchaseFinished", player, 0, true)
		h:advance(1)
		ctx.expect(profile.Data.Passes.double_sparks).toBeNil()
	end)

	it("can't be granted by anything a client sends", function(ctx)
		local h = ctx.harness
		local server = liveServer(ctx)
		local player, client = Game.join(ctx, server, 7006, "Hacker")
		configure(client)
		h:advance(2)
		local data = Game.data(server, player)
		-- A fake purchase signal on the client's own MarketplaceService stays on the client.
		local clientMarket = client.services.MarketplaceService
		ctx.expect(clientMarket).toBeTruthy()
		h:fire(clientMarket, "PromptGamePassPurchaseFinished", client:find("Players.Hacker"), PASS_IDS.triple_sparks, true)
		-- Made-up actions and payloads.
		for _, name in ipairs({ "BuyPass", "GrantPass", "ProcessReceipt", "BuyProduct", "Purchase" }) do
			local result = Game.action(ctx, server, player, name, { Id = PASS_IDS.triple_sparks, ProductId = PRODUCT_IDS.gems_large, Key = "triple_sparks" })
			ctx.expect(result.ok).toBe(false)
		end
		h:exploitFire(server, player, "Click", { Pass = "triple_sparks", Gems = 1e9 })
		h:advance(3)
		ctx.expect(next(data.Passes)).toBeNil()
		ctx.expect(next(data.Boosts)).toBeNil()
		-- The forged press counts as a normal press; a rare golden press may pay up to
		-- 6 Gems, but never the 1e9 the payload asked for.
		ctx.expect(data.Currencies.Gems).toBeLessThanOrEqual(6)
	end)
end)

describe("Developer products", function()
	it("grants a product once, saves it first and ignores repeated receipts", function(ctx)
		local h = ctx.harness
		local server = liveServer(ctx)
		local player = Game.join(ctx, server, 7101, "Buyer")
		local data = Game.data(server, player)
		local decision = h:processReceipt(server, receipt(7101, "gems_medium", "purchase-1"))
		ctx.expect(decision.Name).toBe("PurchaseGranted")
		ctx.expect(data.Currencies.Gems).toBe(550)
		local saved = stored(h, 7101).Data
		ctx.expect(saved.Currencies.Gems).toBe(550)
		ctx.expect(saved.Receipts[1]).toBe("purchase-1")
		-- Roblox retrying the same receipt must not pay out again.
		ctx.expect(h:processReceipt(server, receipt(7101, "gems_medium", "purchase-1")).Name).toBe("PurchaseGranted")
		ctx.expect(data.Currencies.Gems).toBe(550)
		-- A new purchase of the same product is a new receipt.
		ctx.expect(h:processReceipt(server, receipt(7101, "gems_small", "purchase-2")).Name).toBe("PurchaseGranted")
		ctx.expect(data.Currencies.Gems).toBe(650)
		-- The crate bundle gives the best unlocked Spark crate (Neon Crate at the first stage).
		ctx.expect(h:processReceipt(server, receipt(7101, "crate_bundle", "purchase-3")).Name).toBe("PurchaseGranted")
		ctx.expect(data.Chests.neon).toBe(5)
	end)

	it("waits (NotProcessedYet) when the buyer is not here, unknown, or their data is not loaded", function(ctx)
		local h = ctx.harness
		ctx.allowScriptErrors()
		local server = liveServer(ctx)
		ctx.expect(h:processReceipt(server, receipt(7102, "gems_small", "absent-1")).Name).toBe("NotProcessedYet")
		local player = Game.join(ctx, server, 7103, "Here")
		local unknown = { PlayerId = 7103, ProductId = 424242, PurchaseId = "unknown-1" }
		ctx.expect(h:processReceipt(server, unknown).Name).toBe("NotProcessedYet")
		ctx.expect(Game.data(server, player).Currencies.Gems).toBe(0)

		-- Another server still holds this player's data: nothing is granted here.
		h.backend:poke(Game.STORE, Game.storeKey(7104), {
			Schema = 2,
			Data = { Version = 2, Currencies = { Sparks = 0, Gems = 0, Prisms = 0 } },
			Lock = { JobId = "other-server", PlaceId = 1, Time = h.scheduler:unixTime() },
		})
		h:addPlayer(server, { userId = 7104, name = "Locked" })
		ctx.expect(h:processReceipt(server, receipt(7104, "gems_large", "locked-1")).Name).toBe("NotProcessedYet")
		ctx.expect(stored(h, 7104).Data.Currencies.Gems).toBe(0)
	end)

	it("never grants in a temporary session that can't save", function(ctx)
		local h = ctx.harness
		ctx.allowScriptErrors()
		h.backend:setUnavailable("StudioAccessToApisNotAllowed: Studio access to API services is not allowed.")
		local server = Game.server(ctx, { isStudio = true })
		configure(server)
		local player = Game.join(ctx, server, 7105, "Studio")
		ctx.expect(Game.profile(server, player).Temporary).toBe(true)
		ctx.expect(h:processReceipt(server, receipt(7105, "gems_large", "temp-1")).Name).toBe("NotProcessedYet")
		ctx.expect(Game.data(server, player).Currencies.Gems).toBe(0)
	end)

	it("does not confirm a purchase whose save failed and grants it only once on the retry", function(ctx)
		local h = ctx.harness
		ctx.allowScriptErrors()
		local server = liveServer(ctx)
		local player = Game.join(ctx, server, 7106, "Unlucky")
		local data = Game.data(server, player)
		h.backend:failNext("UpdateAsync", 4)
		ctx.expect(h:processReceipt(server, receipt(7106, "gems_small", "retry-1")).Name).toBe("NotProcessedYet")
		ctx.expect(data.Currencies.Gems).toBe(100)
		-- The DataStore works again; Roblox retries the same receipt.
		ctx.expect(h:processReceipt(server, receipt(7106, "gems_small", "retry-1")).Name).toBe("PurchaseGranted")
		ctx.expect(data.Currencies.Gems).toBe(100)
		ctx.expect(stored(h, 7106).Data.Currencies.Gems).toBe(100)
	end)

	it("runs Sparks Rush only while playing, stacks its time and lets it expire", function(ctx)
		local h = ctx.harness
		local server = liveServer(ctx)
		local player = Game.join(ctx, server, 7107, "Rusher")
		ctx.expect(h:processReceipt(server, receipt(7107, "sparks_rush", "rush-1")).Name).toBe("PurchaseGranted")
		local data = Game.data(server, player)
		ctx.expect(statsOf(server, player).sparksMultiplier).toBe(baseStats(server, player).sparksMultiplier * 3)
		ctx.expect(h:processReceipt(server, receipt(7107, "sparks_rush", "rush-2")).Name).toBe("PurchaseGranted")
		ctx.expect(data.Boosts.sparks_rush).toBeGreaterThan(1790)
		-- Base stats (quest targets, offline earnings) ignore the timed boost.
		local StatsService = Game.service(server, "StatsService")
		ctx.expect(StatsService:GetBase(Game.profile(server, player)).sparksMultiplier).toBe(baseStats(server, player).sparksMultiplier)

		h:advance(60)
		local left = data.Boosts.sparks_rush
		ctx.expect(left).toBeLessThan(1750)
		ctx.expect(left).toBeGreaterThan(1720)
		-- Offline time does not use the boost up.
		h:removePlayer(player)
		h:advance(600)
		local again = Game.join(ctx, server, 7107, "Rusher")
		local dataAgain = Game.data(server, again)
		ctx.expect(dataAgain.Boosts.sparks_rush).toBeGreaterThan(left - 30)
		-- It expires after the remaining play time.
		h:advance(dataAgain.Boosts.sparks_rush + 5)
		ctx.expect(dataAgain.Boosts.sparks_rush).toBeNil()
		ctx.expect(statsOf(server, again).sparksMultiplier).toBe(baseStats(server, again).sparksMultiplier)
	end)
end)

describe("Robux crates", function()
	it("opens a Robux crate on purchase with its guaranteed rarity, once per receipt", function(ctx)
		local h = ctx.harness
		local server = liveServer(ctx)
		local player = Game.join(ctx, server, 7301, "Opener")
		local data = Game.data(server, player)
		local Items = Game.shared(server, "Config.Items")
		local Rarities = Game.shared(server, "Config.Rarities")
		local decision = h:processReceipt(server, receipt(7301, "ultra_op_crate", "crate-1"))
		ctx.expect(decision.Name).toBe("PurchaseGranted")
		local total, best = 0, 0
		for id, count in pairs(data.Inventory) do
			total += count
			best = math.max(best, Rarities.index(Items.ById[id].Rarity))
		end
		ctx.expect(total).toBe(1)
		ctx.expect(best).toBeGreaterThanOrEqual(Rarities.index("Mythic"))
		ctx.expect(data.Stats.ChestsOpened).toBe(1)
		-- Saved before the receipt was confirmed; a retried receipt opens nothing new.
		ctx.expect(stored(h, 7301).Data.Stats.ChestsOpened).toBe(1)
		ctx.expect(h:processReceipt(server, receipt(7301, "ultra_op_crate", "crate-1")).Name).toBe("PurchaseGranted")
		ctx.expect(data.Stats.ChestsOpened).toBe(1)
	end)

	it("always meets the rarity floor and only uses items from unlocked crates", function(ctx)
		local h = ctx.harness
		local server = liveServer(ctx)
		local player = Game.join(ctx, server, 7302, "Roller")
		local profile = Game.profile(server, player)
		local ChestService = Game.service(server, "ChestService")
		local Chests = Game.shared(server, "Config.Chests")
		local Items = Game.shared(server, "Config.Items")
		local Rarities = Game.shared(server, "Config.Rarities")
		local Formulas = Game.shared(server, "Formulas")
		local floors = { op_crate = "Epic", mega_op_crate = "Legendary", ultra_op_crate = "Mythic" }
		local secrets = 0
		h:run(function()
			for chestId, floor in pairs(floors) do
				for _ = 1, 150 do
					local results = ChestService:OpenRobuxCrate(profile, chestId)
					ctx.expect(#results).toBe(1)
					local item = Items.ById[results[1].Item]
					ctx.expect(Rarities.index(item.Rarity)).toBeGreaterThanOrEqual(Rarities.index(floor))
					-- Never an item from a crate of a stage the player hasn't reached.
					ctx.expect(Formulas.chestUnlocked(Chests.ById[item.Chest], profile.Data)).toBe(true)
					if chestId == "ultra_op_crate" and item.Rarity == "Secret" then
						secrets += 1
					end
				end
			end
		end)
		-- 8% Secret chance: about 12 in 150 openings.
		ctx.expect(secrets).toBeGreaterThan(2)
		ctx.expect(secrets).toBeLessThan(30)
	end)

	it("can't be opened through the normal crate action", function(ctx)
		local server = liveServer(ctx)
		local player = Game.join(ctx, server, 7303, "Sneaky")
		local data = Game.data(server, player)
		Game.give(server, player, "Sparks", 1e12)
		Game.give(server, player, "Gems", 1e6)
		for _, mode in ipairs({ "buy", "owned" }) do
			local result = Game.action(ctx, server, player, "OpenChest", { Id = "ultra_op_crate", Amount = 1, Mode = mode })
			ctx.expect(result.ok).toBe(false)
			ctx.harness:advance(1)
		end
		ctx.expect(next(data.Inventory)).toBeNil()
		ctx.expect(data.Stats.ChestsOpened).toBe(0)
	end)

	it("plays the opening animation on the buyer's screen", function(ctx)
		local h = ctx.harness
		local server = liveServer(ctx)
		local _, client = Game.join(ctx, server, 7304, "Viewer")
		configure(client)
		h:advance(3)
		ctx.expect(h:processReceipt(server, receipt(7304, "op_crate", "show-1")).Name).toBe("PurchaseGranted")
		h:advance(1)
		local gui = client:find("Players.Viewer.PlayerGui.ButtonAscensionUI")
		local overlay = h:findDescendant(gui, "ChestOpening", "TextButton")
		ctx.expect(overlay).toBeTruthy()
		h:advance(6)
		h:click(h:findByText(overlay, "Continue", "TextButton"))
		h:advance(1)
		ctx.expect(h:findDescendant(gui, "ChestOpening", "TextButton")).toBeNil()
	end)

	it("defines every crate sound with a bundled fallback and sane volumes", function(ctx)
		local server = Game.server(ctx)
		local Sounds = Game.shared(server, "Config.Sounds")
		for _, name in ipairs({ "CrateTick", "CrateWhoosh", "CrateBoom", "CrateChime", "CrateSparkle", "CrateFanfare", "CrateJackpot" }) do
			local def = Sounds[name]
			ctx.expect(def).toBeTruthy()
			ctx.expect(string.sub(def.Id, 1, 17)).toBe("rbxasset://sounds")
			ctx.expect(type(def.Custom)).toBe("string")
			ctx.expect(def.Volume).toBeLessThanOrEqual(0.7)
		end
		for _, rarity in ipairs({ "Epic", "Legendary", "Mythic" }) do
			ctx.expect(#Sounds.CrateFanfares[rarity].Notes).toBeGreaterThan(2)
		end
	end)
end)

describe("Store screen", function()
	it("lists passes and products and opens Roblox's purchase prompts", function(ctx)
		local h = ctx.harness
		local server = liveServer(ctx)
		local player, client = Game.join(ctx, server, 7201, "Alice")
		configure(client)
		client.marketplace.prices[PASS_IDS.auto_clicker] = 129
		h:advance(3)
		local gui = client:find("Players.Alice.PlayerGui.ButtonAscensionUI")
		h:click(h:findDescendant(gui, "NavRail", "Frame"):FindFirstChild("Store"))
		h:advance(1)
		local window = h:findDescendant(gui, "Store", "Frame")
		ctx.expect(window).toBeTruthy()

		local passCard = h:findDescendant(window, "auto_clicker", "Frame")
		local passBuy = passCard:FindFirstChild("Buy")
		ctx.expect(passBuy.Text).toMatch("R%$ 129")
		h:click(passBuy)
		h:advance(0.5)
		local last = client.prompts[#client.prompts]
		ctx.expect(last.kind).toBe("gamepass")
		ctx.expect(last.id).toBe(PASS_IDS.auto_clicker)

		h:click(h:findDescendant(window, "gems_small", "Frame"):FindFirstChild("Buy"))
		h:advance(0.5)
		last = client.prompts[#client.prompts]
		ctx.expect(last.kind).toBe("product")
		ctx.expect(last.id).toBe(PRODUCT_IDS.gems_small)

		-- After the server grants the pass, the card shows it as owned.
		h:fire(server.services.MarketplaceService, "PromptGamePassPurchaseFinished", player, PASS_IDS.auto_clicker, true)
		h:advance(2)
		ctx.expect(passBuy.Text).toMatch("Owned")
		local prompts = #client.prompts
		h:click(passBuy)
		h:advance(0.5)
		ctx.expect(#client.prompts).toBe(prompts)
	end)

	it("hides passes and products that are not set up in live games", function(ctx)
		local h = ctx.harness
		local server = Game.server(ctx)
		local _, client = Game.join(ctx, server, 7202, "Bob")
		h:advance(3)
		local gui = client:find("Players.Bob.PlayerGui.ButtonAscensionUI")
		h:click(h:findDescendant(gui, "NavRail", "Frame"):FindFirstChild("Store"))
		h:advance(1)
		local window = h:findDescendant(gui, "Store", "Frame")
		-- Not set up (ID 0): hidden. The owner's configured items: shown.
		ctx.expect(h:findDescendant(window, "auto_clicker", "Frame").Visible).toBe(false)
		ctx.expect(h:findDescendant(window, "gems_small", "Frame").Visible).toBe(false)
		ctx.expect(h:findDescendant(window, "op_auto_clicker", "Frame").Visible).toBe(true)
		ctx.expect(h:findDescendant(window, "gems_600", "Frame").Visible).toBe(true)
		ctx.expect(h:findByText(window, "No passes available yet.", "TextLabel").Visible).toBe(false)
	end)
end)

return Test.collect()
