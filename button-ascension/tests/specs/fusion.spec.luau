--[[
	Item variants and fusing: Golden / Rainbow versions of every item, the
	server-side Fuse action (3 copies -> 1 of the next variant), natural
	variant drops from crates, the Robux Rainbow Chest, save-data
	sanitising for variant ids, and the client's fuse button and variant cards.
]]

local Test = require("../harness/Test")
local Game = require("../helpers/Game")

local describe, it = Test.describe, Test.it

local function setup(ctx, userId: number?)
	local server = Game.server(ctx)
	local player, client = Game.join(ctx, server, userId or 7401, "Fuser")
	return server, player, client
end

local function sync(server, player, ...)
	Game.service(server, "SyncService"):MarkDirty(Game.profile(server, player), ...)
end

describe("Item catalogue", function()
	it("has two Secret items per crate and Golden/Rainbow versions of every item", function(ctx)
		local server = Game.server(ctx)
		local Items = Game.shared(server, "Config.Items")
		local Chests = Game.shared(server, "Config.Chests")
		ctx.expect(Items.Count).toBe(#Items.List)
		ctx.expect(Items.Count).toBe(81)
		for _, chest in ipairs(Chests.List) do
			ctx.expect(#Items.PoolByChest[chest.Id].Secret).toBe(2)
		end
		for _, item in ipairs(Items.List) do
			ctx.expect(item.Variant).toBeNil()
			local golden = Items.ById[item.Id .. ":golden"]
			local rainbow = Items.ById[item.Id .. ":rainbow"]
			ctx.expect(golden.Name).toBe("Golden " .. item.Name)
			ctx.expect(rainbow.Name).toBe("Rainbow " .. item.Name)
			ctx.expect(golden.Base).toBe(item.Id)
			ctx.expect(rainbow.RarityIndex).toBe(item.RarityIndex)
		end
	end)
end)

describe("Fusing", function()
	it("turns three copies into the next variant, up to Rainbow", function(ctx)
		local server, player = setup(ctx)
		local data = Game.data(server, player)
		local Formulas = Game.shared(server, "Formulas")
		data.Inventory.paper_clip = 7
		data.Discovered.paper_clip = 1
		local discoveredBefore = Formulas.discoveredCount(data)

		local first = Game.action(ctx, server, player, "Fuse", { Id = "paper_clip", Amount = 1 })
		ctx.expect(first.ok).toBe(true)
		ctx.expect(first.Result).toBe("paper_clip:golden")
		ctx.expect(data.Inventory.paper_clip).toBe(4)
		ctx.expect(data.Inventory["paper_clip:golden"]).toBe(1)
		ctx.expect(data.Discovered["paper_clip:golden"]).toBeTruthy()
		-- Variants are tracked but don't count as new collection entries.
		ctx.expect(Formulas.discoveredCount(data)).toBe(discoveredBefore)

		ctx.harness:advance(1)
		ctx.expect(Game.action(ctx, server, player, "Fuse", { Id = "paper_clip", Amount = "max" }).Fused).toBe(1)
		ctx.expect(data.Inventory.paper_clip).toBe(1)
		ctx.expect(data.Inventory["paper_clip:golden"]).toBe(2)
		ctx.harness:advance(1)
		local tooFew = Game.action(ctx, server, player, "Fuse", { Id = "paper_clip", Amount = 1 })
		ctx.expect(tooFew.ok).toBe(false)
		ctx.expect(tooFew.err).toMatch("need 3")

		data.Inventory["paper_clip:golden"] = 3
		ctx.harness:advance(1)
		local rainbow = Game.action(ctx, server, player, "Fuse", { Id = "paper_clip:golden", Amount = 1 })
		ctx.expect(rainbow.Result).toBe("paper_clip:rainbow")
		ctx.expect(data.Inventory["paper_clip:golden"]).toBeNil()
		ctx.expect(data.Stats.ItemsFused).toBe(3)
		ctx.expect(data.Stats.RainbowsFound).toBe(1)

		data.Inventory["paper_clip:rainbow"] = 3
		ctx.harness:advance(1)
		local beyond = Game.action(ctx, server, player, "Fuse", { Id = "paper_clip:rainbow", Amount = 1 })
		ctx.expect(beyond.ok).toBe(false)
		ctx.expect(data.Inventory["paper_clip:rainbow"]).toBe(3)
		ctx.harness:advance(3)
		ctx.expect(data.Achievements.fuse_1).toBeTruthy()
		ctx.expect(data.Achievements.rainbow_1).toBeTruthy()
	end)

	it("protects favourites and gives the fused item the equipped copies' slot", function(ctx)
		local server, player = setup(ctx)
		local data = Game.data(server, player)
		data.Inventory.arcade_stick = 3
		data.Inventory.spare_cog = 4
		data.Equipped = { "spare_cog", "arcade_stick" }
		data.Favorites.arcade_stick = true
		local blocked = Game.action(ctx, server, player, "Fuse", { Id = "arcade_stick", Amount = 1 })
		ctx.expect(blocked.ok).toBe(false)
		ctx.expect(blocked.err).toMatch("Unfavorite")
		ctx.expect(data.Inventory.arcade_stick).toBe(3)

		data.Favorites.arcade_stick = nil
		ctx.harness:advance(1)
		ctx.expect(Game.action(ctx, server, player, "Fuse", { Id = "arcade_stick", Amount = 1 }).ok).toBe(true)
		ctx.expect(data.Inventory.arcade_stick).toBeNil()
		ctx.expect(data.Equipped[2]).toBe("arcade_stick:golden")
		-- A copy is left over: it stays equipped and the Golden one is not added.
		ctx.harness:advance(1)
		ctx.expect(Game.action(ctx, server, player, "Fuse", { Id = "spare_cog", Amount = 1 }).ok).toBe(true)
		ctx.expect(data.Inventory.spare_cog).toBe(1)
		ctx.expect(data.Equipped[1]).toBe("spare_cog")
		ctx.expect(table.find(data.Equipped, "spare_cog:golden")).toBeNil()
		local stats = Game.service(server, "StatsService"):Get(Game.profile(server, player))
		ctx.expect(#data.Equipped).toBeLessThanOrEqual(stats.equipSlots)
	end)

	it("rejects forged and malformed fuse requests", function(ctx)
		local h = ctx.harness
		local server, player = setup(ctx)
		local data = Game.data(server, player)
		data.Inventory.paper_clip = 5
		local payloads = {
			{ Id = "paper_clip", Amount = 0 },
			{ Id = "paper_clip", Amount = -1 },
			{ Id = "paper_clip", Amount = 1.5 },
			{ Id = "paper_clip", Amount = 2 },
			{ Id = "paper_clip", Amount = 1e9 },
			{ Id = "paper_clip", Amount = "all" },
			{ Id = "paper_clip", Amount = 0 / 0 },
			{ Id = "paper_clip:rainbow", Amount = 1 },
			{ Id = "paper_clip:diamond", Amount = 1 },
			{ Id = "first_button", Amount = 1 },
			{ Id = { "paper_clip" }, Amount = 1 },
			{ Amount = 1 },
		}
		for _, payload in ipairs(payloads) do
			local result = Game.action(ctx, server, player, "Fuse", payload)
			ctx.expect(result.ok).toBe(false)
			h:advance(0.6)
		end
		ctx.expect(data.Inventory.paper_clip).toBe(5)
		ctx.expect(data.Inventory["paper_clip:golden"]).toBeNil()
		ctx.expect(data.Stats.ItemsFused).toBe(0)
	end)
end)

describe("Variant drops", function()
	it("drops Golden and Rainbow items at their natural rates and never auto-sells them", function(ctx)
		local h = ctx.harness
		local server, player = setup(ctx)
		local profile = Game.profile(server, player)
		local data = profile.Data
		local ChestService = Game.service(server, "ChestService")
		local Chests = Game.shared(server, "Config.Chests")
		local Items = Game.shared(server, "Config.Items")
		data.Settings.AutoSell = 3
		local counts = { normal = 0, golden = 0, rainbow = 0 }
		local thresholds = Chests.ById.starter.Pity
		h:run(function()
			for _ = 1, 400 do
				for _, result in ipairs(ChestService:RollMany(profile, Chests.ById.starter, 10)) do
					local item = Items.ById[result.Item]
					counts[item.Variant or "normal"] += 1
					if item.Variant then
						ctx.expect(result.AutoSold).toBeNil()
					end
				end
				-- Pity still counts rarities only and never runs past its threshold.
				ctx.expect(data.Pity.starter.Legendary).toBeLessThan(thresholds.Legendary)
			end
		end)
		local total = counts.normal + counts.golden + counts.rainbow
		ctx.expect(total).toBeGreaterThanOrEqual(4000)
		-- 1.5% Golden ≈ 60 of 4000; 0.15% Rainbow ≈ 6.
		ctx.expect(counts.golden).toBeGreaterThan(30)
		ctx.expect(counts.golden).toBeLessThan(100)
		ctx.expect(counts.rainbow).toBeLessThan(20)
		ctx.expect(counts.golden + counts.rainbow).toBeLessThan(120)
	end)
end)

describe("Rainbow Chest", function()
	local PRODUCT_ID = 3001

	it("grants exactly one Rainbow Epic-or-better item per receipt", function(ctx)
		local h = ctx.harness
		local server = Game.server(ctx)
		Game.shared(server, "Config.DevProducts").ByKey.rainbow_chest.ProductId = PRODUCT_ID
		local player = Game.join(ctx, server, 7402, "Rainbow")
		local data = Game.data(server, player)
		local Items = Game.shared(server, "Config.Items")
		local receipt = { PlayerId = 7402, ProductId = PRODUCT_ID, PurchaseId = "rainbow-1" }
		ctx.expect(h:processReceipt(server, receipt).Name).toBe("PurchaseGranted")
		local owned = {}
		for id, count in pairs(data.Inventory) do
			for _ = 1, count do
				table.insert(owned, id)
			end
		end
		ctx.expect(#owned).toBe(1)
		local item = Items.ById[owned[1]]
		ctx.expect(item.Variant).toBe("rainbow")
		ctx.expect(item.RarityIndex).toBeGreaterThanOrEqual(4)
		ctx.expect(data.Stats.RainbowsFound).toBe(1)
		ctx.expect(h:processReceipt(server, receipt).Name).toBe("PurchaseGranted")
		ctx.expect(data.Stats.RainbowsFound).toBe(1)
		ctx.expect(h.backend:peek(Game.STORE, Game.storeKey(7402)).Data.Stats.RainbowsFound).toBe(1)
	end)

	it("always rolls Rainbow, Epic or better, with a real Secret chance", function(ctx)
		local h = ctx.harness
		local server, player = setup(ctx, 7403)
		local profile = Game.profile(server, player)
		local ChestService = Game.service(server, "ChestService")
		local Items = Game.shared(server, "Config.Items")
		local secrets = 0
		h:run(function()
			for _ = 1, 300 do
				local item = Items.ById[ChestService:OpenRobuxCrate(profile, "rainbow_chest")[1].Item]
				ctx.expect(item.Variant).toBe("rainbow")
				ctx.expect(item.RarityIndex).toBeGreaterThanOrEqual(4)
				if item.Rarity == "Secret" then
					secrets += 1
				end
			end
		end)
		-- 5% Secret before Luck ≈ 15 of 300.
		ctx.expect(secrets).toBeGreaterThan(3)
		ctx.expect(secrets).toBeLessThan(40)
	end)
end)

describe("Saving", function()
	it("keeps variant items, equipped variants and variant discoveries when sanitising", function(ctx)
		local server = Game.server(ctx)
		local DataSchema = server:requirePath("ServerScriptService.Core.DataSchema")
		local clean = DataSchema.sanitize({
			Version = 2,
			Inventory = { ["paper_clip:golden"] = 2, ["paper_clip:rainbow"] = 1, ["made_up:golden"] = 3 },
			Equipped = { "paper_clip:rainbow" },
			Discovered = { ["paper_clip:golden"] = 5, ["paper_clip:rainbow"] = 6 },
			Stats = { ItemsFused = 4, RainbowsFound = 1 },
		})
		ctx.expect(clean.Inventory["paper_clip:golden"]).toBe(2)
		ctx.expect(clean.Inventory["paper_clip:rainbow"]).toBe(1)
		ctx.expect(clean.Inventory["made_up:golden"]).toBeNil()
		ctx.expect(clean.LegacyInventory["made_up:golden"]).toBe(3)
		ctx.expect(clean.Equipped[1]).toBe("paper_clip:rainbow")
		ctx.expect(clean.Discovered["paper_clip:rainbow"]).toBe(6)
		ctx.expect(clean.Stats.ItemsFused).toBe(4)
	end)
end)

describe("Fusing in the interface", function()
	it("fuses from the inventory detail panel and shows the variant on its card", function(ctx)
		local h = ctx.harness
		local server, player, client = setup(ctx, 7404)
		local data = Game.data(server, player)
		data.Inventory.paper_clip = 3
		data.Discovered.paper_clip = 1
		sync(server, player, "Inventory", "Discovered")
		h:advance(3)
		local gui = client:find("Players.Fuser.PlayerGui.ButtonAscensionUI")
		h:click(h:findDescendant(gui, "NavRail", "Frame"):FindFirstChild("Inventory"))
		h:advance(1)
		local window = h:findDescendant(gui, "Inventory", "Frame")
		h:click(h:findDescendant(window, "ItemCard", "TextButton"))
		h:advance(0.5)
		local fuseButton = h:findDescendant(window, "Fuse", "TextButton")
		ctx.expect(fuseButton.Text).toMatch("Golden")
		-- The tutorial's "Equip" button is still there under its usual text.
		ctx.expect(h:findByText(window, "Equip", "TextButton")).toBeTruthy()
		h:click(fuseButton)
		h:advance(2)
		ctx.expect(data.Inventory["paper_clip:golden"]).toBe(1)
		ctx.expect(data.Inventory.paper_clip).toBeNil()
		local marks = h:queryDescendants(window, function(d)
			return d.name == "VariantMark"
		end)
		local visible = 0
		for _, mark in ipairs(marks) do
			if mark.Visible then
				visible += 1
			end
		end
		ctx.expect(visible).toBe(1)
	end)
end)

return Test.collect()
