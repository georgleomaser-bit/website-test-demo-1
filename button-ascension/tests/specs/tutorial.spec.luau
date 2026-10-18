--[[
	Tutorial: steps complete only from real actions decided by the server,
	"seen" intents are accepted only for the active "seen" step, skipping is
	saved, replaying works and the reward is paid once. Players saved before
	the tutorial existed never see it.
]]

local Test = require("../harness/Test")
local Game = require("../helpers/Game")

local describe, it = Test.describe, Test.it

local USER = 9401

local function stepId(server, player): string?
	local Tutorial = Game.shared(server, "Config.Tutorial")
	local state = Game.data(server, player).Tutorial
	if state.Done then
		return nil
	end
	return Tutorial.Steps[state.Step].Id
end

describe("Tutorial", function()
	it("walks a new player through every step from real actions and pays the reward once", function(ctx)
		local h = ctx.harness
		local server = Game.server(ctx)
		local player = Game.join(ctx, server, USER, "Newbie")
		local data = Game.data(server, player)
		ctx.expect(stepId(server, player)).toBe("press")

		Game.press(ctx, server, player, 10)
		h:advance(1)
		ctx.expect(stepId(server, player)).toBe("upgrade")

		Game.give(server, player, "Sparks", 100)
		ctx.expect(Game.action(ctx, server, player, "BuyUpgrade", { Id = "click_power", Amount = 1 }).ok).toBe(true)
		h:advance(1)
		ctx.expect(stepId(server, player)).toBe("crate")

		data.Chests.starter = 1
		ctx.expect(Game.action(ctx, server, player, "OpenChest", { Id = "starter", Amount = 1, Mode = "owned" }).ok).toBe(true)
		h:advance(1)
		ctx.expect(stepId(server, player)).toBe("equip")

		local itemId = next(data.Inventory)
		ctx.expect(Game.action(ctx, server, player, "Equip", { Id = itemId }).ok).toBe(true)
		h:advance(1)
		ctx.expect(stepId(server, player)).toBe("quests")

		ctx.expect(Game.action(ctx, server, player, "TutorialSeen", { Step = "quests" }).ok).toBe(true)
		h:advance(1)
		ctx.expect(stepId(server, player)).toBe("obby")

		-- Reaching checkpoint 1 through the real reward path.
		local obby = Game.service(server, "ObbyService")
		obby:_reach(Game.profile(server, player), 1)
		h:advance(1)
		ctx.expect(stepId(server, player)).toBe("auto")

		local gemsBefore = data.Currencies.Gems
		ctx.expect(Game.action(ctx, server, player, "TutorialSeen", { Step = "auto" }).ok).toBe(true)
		h:advance(1)
		ctx.expect(data.Tutorial.Done).toBe(true)
		ctx.expect(data.Tutorial.Skipped).toBe(false)
		ctx.expect(data.Currencies.Gems - gemsBefore).toBe(50)

		-- Replaying from Settings works, but pays nothing the second time.
		h:advance(15)
		ctx.expect(Game.action(ctx, server, player, "TutorialRestart", {}).ok).toBe(true)
		ctx.expect(stepId(server, player)).toBe("press")
		local tutorial = Game.service(server, "TutorialService")
		tutorial:_begin(Game.profile(server, player), 7)
		h:advance(1)
		local gems = data.Currencies.Gems
		ctx.expect(Game.action(ctx, server, player, "TutorialSeen", { Step = "auto" }).ok).toBe(true)
		ctx.expect(data.Tutorial.Done).toBe(true)
		ctx.expect(data.Currencies.Gems).toBe(gems)
	end)

	it("only accepts 'seen' for the active look-at step and never for real-action steps", function(ctx)
		local h = ctx.harness
		local server = Game.server(ctx)
		local player = Game.join(ctx, server, USER, "Newbie")
		for _, forged in ipairs({ { Step = "quests" }, { Step = "press" }, { Step = "auto" }, { Step = 5 }, {} }) do
			ctx.expect(Game.action(ctx, server, player, "TutorialSeen", forged).ok).toBe(false)
			h:advance(1)
		end
		ctx.expect(stepId(server, player)).toBe("press")
		-- Auto-presses do not count as pressing the button yourself.
		local data = Game.data(server, player)
		data.Upgrades.auto_presser = 20
		Game.service(server, "StatsService"):Invalidate(Game.profile(server, player))
		h:advance(5)
		ctx.expect(data.Stats.AutoClicks).toBeGreaterThan(10)
		ctx.expect(stepId(server, player)).toBe("press")
	end)

	it("saves a skip and keeps it after rejoining", function(ctx)
		local h = ctx.harness
		local server = Game.server(ctx)
		local player = Game.join(ctx, server, USER, "Newbie")
		ctx.expect(Game.action(ctx, server, player, "TutorialSkip", {}).ok).toBe(true)
		local state = Game.data(server, player).Tutorial
		ctx.expect(state.Done).toBe(true)
		ctx.expect(state.Skipped).toBe(true)
		ctx.expect(state.Rewarded).toBe(false)
		h:removePlayer(player)
		h:advance(5)
		local again = Game.join(ctx, server, USER, "Newbie")
		ctx.expect(Game.data(server, again).Tutorial.Done).toBe(true)
	end)

	it("does not start for players saved before the tutorial existed", function(ctx)
		local h = ctx.harness
		h.backend:poke(Game.STORE, Game.storeKey(USER), {
			Schema = 2,
			Data = { Version = 2, Currencies = { Sparks = 500, Gems = 0, Prisms = 0 }, Meta = { Sessions = 12 } },
		})
		local server = Game.server(ctx)
		local player = Game.join(ctx, server, USER, "Veteran")
		ctx.expect(Game.data(server, player).Tutorial.Done).toBe(true)
	end)
end)

return Test.collect()
