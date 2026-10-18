--[[
	Multiplayer and performance: several clients playing at once with full
	collections, isolation between players, server-wide effects and timing.
]]

local Test = require("../harness/Test")
local Game = require("../helpers/Game")

local describe, it = Test.describe, Test.it

describe("Multiplayer", function()
	it("keeps each player's data isolated", function(ctx)
		local server = Game.server(ctx)
		local alice = Game.join(ctx, server, 6001, "Alice")
		local bob = Game.join(ctx, server, 6002, "Bob")
		Game.give(server, alice, "Sparks", 1000)
		ctx.expect(Game.action(ctx, server, alice, "BuyUpgrade", { Id = "click_power", Amount = 1 }).ok).toBe(true)
		-- Bob cannot spend Alice's money or touch her items by naming them.
		ctx.expect(Game.action(ctx, server, bob, "BuyUpgrade", { Id = "click_power", Amount = 1, UserId = 6001 }).ok).toBe(false)
		Game.press(ctx, server, alice, 10)
		local a, b = Game.data(server, alice), Game.data(server, bob)
		ctx.expect(a.Upgrades.click_power).toBe(1)
		ctx.expect(b.Upgrades.click_power).toBeNil()
		ctx.expect(b.Stats.TotalClicks).toBe(0)
		ctx.expect(a.Stats.TotalClicks).toBe(10)
	end)

	it("runs 8 players with full collections and auto-presses for 3 minutes", function(ctx)
		local h = ctx.harness
		local server = Game.server(ctx)
		local Items = Game.shared(server, "Config.Items")
		local players = {}
		for i = 1, 8 do
			local player = Game.join(ctx, server, 7000 + i, "Player" .. i)
			local data = Game.data(server, player)
			for _, item in ipairs(Items.List) do
				data.Inventory[item.Id] = 1000
				data.Discovered[item.Id] = 1
			end
			data.Upgrades.auto_presser = 20
			data.Upgrades.generator = 100
			data.Level = 20
			table.insert(players, player)
		end
		for _, player in ipairs(players) do
			ctx.expect(Game.action(ctx, server, player, "EquipBest", {}).ok).toBe(true)
		end
		local started = os.clock()
		for _ = 1, 180 do
			for _, player in ipairs(players) do
				h:exploitFire(server, player, "Click")
			end
			h:advance(1)
		end
		local elapsed = os.clock() - started
		for _, player in ipairs(players) do
			local data = Game.data(server, player)
			ctx.expect(data.Stats.AutoClicks).toBeGreaterThan(1500)
			ctx.expect(data.Stats.TotalClicks).toBe(180)
			ctx.expect(#data.Equipped).toBe(3)
			ctx.expect(data.Currencies.Sparks).toBeGreaterThan(0)
		end
		-- 8 players × 3 virtual minutes must stay cheap to simulate (generous bound).
		ctx.expect(elapsed).toBeLessThan(60)
	end)

	it("shares server activity with every client", function(ctx)
		local h = ctx.harness
		local server = Game.server(ctx)
		local alice = Game.join(ctx, server, 6101, "Alice")
		local _, bobClient = Game.join(ctx, server, 6102, "Bob")
		for _ = 1, 5 do
			h:exploitFire(server, alice, "Click")
		end
		h:advance(2.5)
		local state = bobClient:find("ReplicatedStorage.ServerState")
		ctx.expect(state:GetAttribute("ServerPresses")).toBe(5)
		ctx.expect(state:GetAttribute("Players")).toBe(2)
	end)
end)

return Test.collect()
