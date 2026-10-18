--[[
	Obby: the course is built, checkpoints count only in order and at a
	plausible speed, rewards are paid once per checkpoint per run, kill bricks
	and the void send you back, progress survives rejoining, the teleport
	action only goes to your own checkpoint, and auto-presses keep earning.

	The harness has no physics, so tests move the character the way the
	owning client would: by setting the HumanoidRootPart position step by step.
]]

local roblox = require("@lune/roblox")
local Test = require("../harness/Test")
local Game = require("../helpers/Game")

local describe, it = Test.describe, Test.it
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local USER = 9301

local function rootOf(player)
	return player.Character:FindFirstChild("HumanoidRootPart")
end

local function standPoint(pad)
	return pad.Position + Vector3.new(0, pad.Size.Y / 2 + 3, 0)
end

-- Moves the root in straight steps at `speed` studs/s (sampled every 0.1 s),
-- rising above the course on the way so kill bricks are not crossed.
local function travel(h, player, target: Vector3, speed: number)
	local root = rootOf(player)
	local from = root.Position
	local high = math.max(from.Y, target.Y) + 12
	local waypoints = { Vector3.new(from.X, high, from.Z), Vector3.new(target.X, high, target.Z), target }
	local position = from
	for _, waypoint in ipairs(waypoints) do
		local delta = waypoint - position
		local steps = math.max(1, math.ceil(delta.Magnitude / (speed * 0.1)))
		for i = 1, steps do
			root.CFrame = CFrame.new(position + delta * (i / steps))
			h:advance(0.1)
		end
		position = waypoint
	end
	h:advance(0.3)
end

local function setup(ctx)
	local server = Game.server(ctx)
	local player = Game.join(ctx, server, USER, "Runner")
	local obby = Game.service(server, "ObbyService")
	return server, player, obby
end

local function goToStart(h, player, obby)
	travel(h, player, standPoint(obby.Start), 25)
	h:advance(0.5)
end

describe("Obby course", function()
	it("builds 14 checkpoints and a finish next to the plaza", function(ctx)
		local server, _, obby = setup(ctx)
		local Obby = Game.shared(server, "Config.Obby")
		ctx.expect(#obby.Pads).toBe(Obby.StageCount)
		ctx.expect(obby.Pads[Obby.StageCount].Name).toBe("Finish")
		ctx.expect(obby.Pads[1].Name).toBe("Checkpoint1")
		ctx.expect(#obby.Kill).toBeGreaterThan(5)
		-- Every stage climbs or moves away from the plaza.
		for stage = 2, Obby.StageCount do
			ctx.expect(obby.Pads[stage].Position.X).toBeGreaterThan(obby.Pads[stage - 1].Position.X)
		end
		ctx.expect(server:find("Workspace.Obby")).toBeTruthy()
	end)

	it("counts checkpoints in order and pays each one once per run", function(ctx)
		local h = ctx.harness
		local server, player, obby = setup(ctx)
		local data = Game.data(server, player)
		goToStart(h, player, obby)
		travel(h, player, standPoint(obby.Pads[1]), 16)
		ctx.expect(data.Obby.Stage).toBe(1)
		ctx.expect(data.Obby.Best).toBe(1)
		ctx.expect(data.Obby.Checkpoints).toBe(1)
		ctx.expect(data.Currencies.Gems).toBe(5)
		local sparks = data.Currencies.Sparks
		ctx.expect(sparks).toBeGreaterThanOrEqual(25)

		-- Standing on it longer, or coming back, pays nothing more.
		h:advance(3)
		travel(h, player, standPoint(obby.Pads[1]) + Vector3.new(-8, 0, 0), 16)
		travel(h, player, standPoint(obby.Pads[1]), 16)
		ctx.expect(data.Obby.Checkpoints).toBe(1)
		ctx.expect(data.Currencies.Gems).toBe(5)

		-- Skipping checkpoint 2 does not count; checkpoint 2 then does.
		travel(h, player, standPoint(obby.Pads[3]), 16)
		ctx.expect(data.Obby.Stage).toBe(1)
		travel(h, player, standPoint(obby.Pads[2]), 16)
		ctx.expect(data.Obby.Stage).toBe(2)
	end)

	it("ignores teleports and impossibly fast runs and flags them", function(ctx)
		local h = ctx.harness
		local server, player, obby = setup(ctx)
		local data = Game.data(server, player)
		local security = Game.service(server, "SecurityService")
		goToStart(h, player, obby)

		-- Straight teleport onto checkpoint 1.
		rootOf(player).CFrame = CFrame.new(standPoint(obby.Pads[1]))
		h:advance(1)
		ctx.expect(data.Obby.Stage).toBe(0)
		ctx.expect(security:GetCounts(USER).ObbyTeleport or 0).toBeGreaterThanOrEqual(1)

		-- Small steps, but far faster than anyone can run.
		goToStart(h, player, obby)
		h:advance(5)
		local target = standPoint(obby.Pads[1])
		local root = rootOf(player)
		local from = root.Position
		for i = 1, 3 do
			root.CFrame = CFrame.new(from:Lerp(target, i / 3))
			h:advance(0.1)
		end
		h:advance(0.5)
		ctx.expect(data.Obby.Stage).toBe(0)
		ctx.expect(security:GetCounts(USER).ObbyTooFast or 0).toBeGreaterThanOrEqual(1)
		ctx.expect(data.Currencies.Gems).toBe(0)

		-- Running it properly afterwards still works.
		goToStart(h, player, obby)
		h:advance(5)
		travel(h, player, standPoint(obby.Pads[1]), 16)
		ctx.expect(data.Obby.Stage).toBe(1)
	end)

	it("sends you back to your checkpoint from kill bricks and the void, but only counts the living", function(ctx)
		local h = ctx.harness
		local server, player, obby = setup(ctx)
		local data = Game.data(server, player)
		data.Obby.Stage = 2
		data.Obby.Best = 2
		local checkpoint = standPoint(obby.Pads[2])
		-- Stage 3 ("Hot Floor") has kill strips lying on its walkway.
		local strip
		for _, kill in ipairs(obby.Kill) do
			if kill.Position.X > obby.Pads[2].Position.X and kill.Position.X < obby.Pads[3].Position.X then
				strip = kill
				break
			end
		end
		ctx.expect(strip).toBeTruthy()
		travel(h, player, strip.Position + Vector3.new(0, 3, 0), 16)
		ctx.expect((rootOf(player).Position - checkpoint).Magnitude).toBeLessThan(1)

		h:advance(2)
		rootOf(player).CFrame = CFrame.new(checkpoint + Vector3.new(10, -60, 0))
		h:advance(0.5)
		ctx.expect((rootOf(player).Position - checkpoint).Magnitude).toBeLessThan(1)

		-- A dead character standing on the next pad does not count.
		h:advance(2)
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		travel(h, player, standPoint(obby.Pads[3]) + Vector3.new(0, 4, 0), 16)
		humanoid.Health = 0
		rootOf(player).CFrame = CFrame.new(standPoint(obby.Pads[3]))
		h:advance(0.5)
		ctx.expect(data.Obby.Stage).toBe(2)
		-- After respawning, the new character is put back on checkpoint 2.
		h:advance(8)
		ctx.expect((rootOf(player).Position - checkpoint).Magnitude).toBeLessThan(1)
	end)

	it("saves progress and puts you back on your checkpoint after rejoining", function(ctx)
		local h = ctx.harness
		local server, player, obby = setup(ctx)
		goToStart(h, player, obby)
		travel(h, player, standPoint(obby.Pads[1]), 16)
		ctx.expect(Game.data(server, player).Obby.Stage).toBe(1)
		h:removePlayer(player)
		h:advance(5)
		ctx.expect(h.backend:peek(Game.STORE, Game.storeKey(USER)).Data.Obby.Stage).toBe(1)
		local again = Game.join(ctx, server, USER, "Runner")
		h:advance(2)
		ctx.expect(Game.data(server, again).Obby.Best).toBe(1)
		ctx.expect((rootOf(again).Position - standPoint(obby.Pads[1])).Magnitude).toBeLessThan(1)
	end)

	it("finishes a run, pays the finish rewards, resets the run and returns you to the plaza", function(ctx)
		local h = ctx.harness
		local server, player, obby = setup(ctx)
		local Obby = Game.shared(server, "Config.Obby")
		local data = Game.data(server, player)
		data.Obby.Stage = Obby.StageCount - 1
		data.Obby.Best = Obby.StageCount - 1
		h:advance(1)
		ctx.expect(Game.action(ctx, server, player, "ObbyTeleport", { To = "checkpoint" }).ok).toBe(true)
		h:advance(3)
		travel(h, player, standPoint(obby.Pads[Obby.StageCount]), 16)
		ctx.expect(data.Obby.Completions).toBe(1)
		ctx.expect(data.Obby.Stage).toBe(0)
		ctx.expect(data.Obby.Best).toBe(Obby.StageCount)
		local R = Obby.Rewards
		ctx.expect(data.Currencies.Gems).toBe(R.MilestoneGems + R.FinishGems + R.FirstFinishGems)
		h:advance(4)
		ctx.expect(rootOf(player).Position.X).toBeLessThan(20)
	end)

	it("only teleports to your own checkpoint or the plaza", function(ctx)
		local h = ctx.harness
		local server, player, obby = setup(ctx)
		local data = Game.data(server, player)
		ctx.expect(Game.action(ctx, server, player, "ObbyTeleport", { To = "checkpoint" }).ok).toBe(true)
		ctx.expect((rootOf(player).Position - standPoint(obby.Start)).Magnitude).toBeLessThan(1)
		h:advance(5)
		for _, forged in ipairs({ { To = "finish" }, { To = 14 }, { Stage = 14, To = "checkpoint" } }) do
			Game.action(ctx, server, player, "ObbyTeleport", forged)
			h:advance(5)
		end
		ctx.expect(data.Obby.Stage).toBe(0)
		ctx.expect((rootOf(player).Position - standPoint(obby.Start)).Magnitude).toBeLessThan(1)
		ctx.expect(Game.action(ctx, server, player, "ObbyTeleport", { To = "plaza" }).ok).toBe(true)
		ctx.expect(rootOf(player).Position.X).toBeLessThan(20)
	end)

	it("keeps auto-pressing while you run the course", function(ctx)
		local h = ctx.harness
		local server, player, obby = setup(ctx)
		local data = Game.data(server, player)
		data.Upgrades.auto_presser = 10
		Game.service(server, "StatsService"):Invalidate(Game.profile(server, player))
		local before = data.Stats.AutoClicks
		goToStart(h, player, obby)
		travel(h, player, standPoint(obby.Pads[1]), 16)
		travel(h, player, standPoint(obby.Pads[2]), 16)
		ctx.expect(data.Obby.Stage).toBe(2)
		ctx.expect(data.Stats.AutoClicks - before).toBeGreaterThan(10)
		ctx.expect(data.Stats.TotalClicks).toBe(0)
	end)
end)

return Test.collect()
