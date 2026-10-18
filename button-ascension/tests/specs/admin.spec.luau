--[[
	Admin system: access control (including direct exploit calls to the Admin
	remote), Owner/Admin/Moderator differences, rank protection, limits,
	confirmation tokens, duplicate/malformed requests, rate limits, audit logs,
	the command parser, player management, offline edits and announcements.

	Studio test users (AdminConfig.StudioTestUsers, Studio only):
	  -1 Owner, -2 Admin, -3 Moderator, -4 normal player.
]]

local roblox = require("@lune/roblox")
local Test = require("../harness/Test")
local Game = require("../helpers/Game")

local describe, it = Test.describe, Test.it

local function studio(ctx)
	local server = Game.server(ctx, { isStudio = true })
	local owner = Game.join(ctx, server, -1, "Owner")
	local admin = Game.join(ctx, server, -2, "Admin")
	local mod = Game.join(ctx, server, -3, "Moderator")
	local player = Game.join(ctx, server, -4, "Player")
	return server, owner, admin, mod, player
end

local function auditHas(server, predicate): boolean
	local AuditLog = Game.service(server, "AuditLog")
	for _, entry in ipairs(AuditLog.recent(300)) do
		if predicate(entry) then
			return true
		end
	end
	return false
end

describe("Access", function()
	it("delivers the admin panel only to staff", function(ctx)
		local h = ctx.harness
		local server = Game.server(ctx, { isStudio = true })
		local owner, ownerClient = Game.join(ctx, server, -1, "Owner")
		local player, playerClient = Game.join(ctx, server, -4, "Player")
		h:advance(3)
		ctx.expect(owner.PlayerGui:FindFirstChild("AdminPanelGui")).toBeTruthy()
		ctx.expect(player.PlayerGui:FindFirstChild("AdminPanelGui")).toBeNil()
		ctx.expect(ownerClient:find("Players.Owner.PlayerGui.AdminPanelGui")).toBeTruthy()
		ctx.expect(playerClient:find("Players.Player.PlayerGui.AdminPanelGui")).toBeNil()
	end)

	it("makes the place creator Owner in live servers and nobody else", function(ctx)
		local server = Game.server(ctx, { creatorId = 3000 })
		local creator = Game.join(ctx, server, 3000, "Creator")
		local other = Game.join(ctx, server, 3001, "Other")
		ctx.expect(Game.admin(ctx, server, creator, "hello").data.Role).toBe("Owner")
		ctx.expect(Game.admin(ctx, server, other, "hello").err).toBe("Not authorized.")
		-- Studio test ids never count in live servers.
		local fake = Game.join(ctx, server, -1, "FakeOwner")
		ctx.expect(Game.admin(ctx, server, fake, "hello").ok).toBe(false)
	end)

	it("rejects every request from a normal player, however it is forged", function(ctx)
		local h = ctx.harness
		local server = Game.server(ctx, { creatorId = 3000 })
		local player = Game.join(ctx, server, 3001, "Mallory")
		local data = Game.data(server, player)
		local payloads = {
			{ Action = "economy.add", Args = { Target = 3001, Currency = "Gems", Amount = 1e9 }, RequestId = "aaaaaaaa1" },
			{ Action = "command", Args = { Text = "givecash me 1e12" }, RequestId = "aaaaaaaa2" },
			{ Action = "confirm", Args = { Token = "00000000-0000" }, RequestId = "aaaaaaaa3" },
			{ Action = "hello", RequestId = "aaaaaaaa4", Role = "Owner", IsAdmin = true },
			{ Action = "progression.grantRebirth", Args = { Target = "me", Count = 100 } },
			"economy.add",
			42,
			false,
		}
		local count = #payloads + 1
		for i = 1, count do
			-- The extra iteration sends nil (no payload at all).
			local result = h:exploitInvoke(server, player, "Admin", payloads[i])
			ctx.expect(result.ok).toBe(false)
			ctx.expect(result.err).toBe("Not authorized.")
		end
		ctx.expect(data.Currencies.Gems).toBe(0)
		ctx.expect(data.Currencies.Sparks).toBe(0)
		ctx.expect(data.Rebirths).toBe(0)
		local security = Game.service(server, "SecurityService")
		ctx.expect(security:GetCounts(3001).AdminRemoteUnauthorized).toBe(count)
		ctx.expect(auditHas(server, function(e)
			return e.AdminId == 3001 and e.Result == "denied"
		end)).toBe(true)
		ctx.expect(player.PlayerGui:FindFirstChild("AdminPanelGui")).toBeNil()
	end)

	it("rejects malformed and duplicate requests from staff", function(ctx)
		local h = ctx.harness
		local server, owner = studio(ctx)
		local noId = h:exploitInvoke(server, owner, "Admin", { Action = "hello" })
		ctx.expect(noId.err).toBe("Malformed request.")
		local first = Game.admin(ctx, server, owner, "economy.add", { Target = "me", Currency = "Gems", Amount = 5 }, "fixed-request-1")
		ctx.expect(first.ok).toBe(true)
		local replay = Game.admin(ctx, server, owner, "economy.add", { Target = "me", Currency = "Gems", Amount = 5 }, "fixed-request-1")
		ctx.expect(replay.duplicate).toBe(true)
		ctx.expect(Game.data(server, owner).Currencies.Gems).toBe(5)
		ctx.expect(Game.admin(ctx, server, owner, "launch.missiles").err).toBe("Unknown action.")
	end)
end)

describe("Roles and permissions", function()
	it("gives Owner, Admin and Moderator different powers", function(ctx)
		local server, owner, admin, mod, player = studio(ctx)
		local target = { Target = "Player", Currency = "Gems", Amount = 1000 }
		ctx.expect(Game.admin(ctx, server, mod, "economy.add", target).err).toMatch("does not have permission")
		ctx.expect(Game.admin(ctx, server, admin, "economy.add", target).ok).toBe(true)
		ctx.expect(Game.data(server, player).Currencies.Gems).toBe(1000)

		local huge = { Target = "Player", Currency = "Sparks", Amount = 1e16 }
		ctx.expect(Game.admin(ctx, server, admin, "economy.add", huge).err).toMatch("limit")
		ctx.expect(Game.admin(ctx, server, owner, "economy.add", huge).ok).toBe(true)

		ctx.expect(Game.admin(ctx, server, admin, "progression.reset", { Target = "Player", Scope = "all" }).err).toMatch("does not have permission")
		ctx.expect(Game.admin(ctx, server, admin, "server.announce", { Message = "hi", Scope = "global" }).err).toMatch("game%-wide")
		ctx.expect(Game.admin(ctx, server, mod, "server.announce", { Message = "hi", Scope = "server" }).ok).toBe(true)
		ctx.expect(Game.admin(ctx, server, mod, "items.grant", { Target = "Player", Item = "paper_clip" }).ok).toBe(false)
		ctx.expect(Game.admin(ctx, server, mod, "players.freeze", { Target = "Player" }).ok).toBe(true)

		local hello = Game.admin(ctx, server, mod, "hello")
		ctx.expect(hello.data.Role).toBe("Moderator")
		local names = {}
		for _, cmd in ipairs(hello.data.Commands) do
			names[cmd.Name] = true
		end
		ctx.expect(names.kick).toBe(true)
		ctx.expect(names.givecash).toBeNil()
	end)

	it("protects staff of equal or higher rank from punitive actions", function(ctx)
		local server, owner, admin, mod = studio(ctx)
		ctx.expect(Game.admin(ctx, server, admin, "players.kick", { Target = "Owner", Reason = "test" }).err).toMatch("equal or higher")
		ctx.expect(Game.admin(ctx, server, mod, "players.freeze", { Target = "Admin" }).err).toMatch("equal or higher")
		ctx.expect(Game.admin(ctx, server, admin, "economy.remove", { Target = "Admin", Currency = "Gems", Amount = 1 }).ok).toBe(true)
		ctx.expect(Game.admin(ctx, server, owner, "players.freeze", { Target = "Admin" }).ok).toBe(true)
		ctx.expect(owner).toBeTruthy()
	end)
end)

describe("Economy, items and progression tools", function()
	it("adds, removes and sets currency through core validation", function(ctx)
		local server, owner, _, _, player = studio(ctx)
		local data = Game.data(server, player)
		ctx.expect(Game.admin(ctx, server, owner, "economy.add", { Target = "Player", Currency = "Sparks", Amount = 500 }).ok).toBe(true)
		ctx.expect(Game.admin(ctx, server, owner, "economy.remove", { Target = "Player", Currency = "Sparks", Amount = 200 }).ok).toBe(true)
		ctx.expect(data.Currencies.Sparks).toBe(300)
		ctx.expect(Game.admin(ctx, server, owner, "economy.remove", { Target = "Player", Currency = "Sparks", Amount = 1e6 }).ok).toBe(true)
		ctx.expect(data.Currencies.Sparks).toBe(0)
		ctx.expect(Game.admin(ctx, server, owner, "economy.set", { Target = "Player", Currency = "Prisms", Amount = 12 }).ok).toBe(true)
		ctx.expect(data.Currencies.Prisms).toBe(12)
		for _, bad in ipairs({ -5, 0 / 0, math.huge, "12" }) do
			ctx.expect(Game.admin(ctx, server, owner, "economy.set", { Target = "Player", Currency = "Gems", Amount = bad }).ok).toBe(false)
		end
		ctx.expect(Game.admin(ctx, server, owner, "economy.add", { Target = "Player", Currency = "Robux", Amount = 5 }).ok).toBe(false)
		ctx.expect(Game.admin(ctx, server, owner, "economy.add", { Target = "Nobody", Currency = "Gems", Amount = 5 }).ok).toBe(false)
	end)

	it("grants and removes items and crates, and runs test drops without changing odds", function(ctx)
		local server, owner, _, _, player = studio(ctx)
		local data = Game.data(server, player)
		ctx.expect(Game.admin(ctx, server, owner, "items.grant", { Target = "Player", Item = "paper_clip", Amount = 3 }).ok).toBe(true)
		ctx.expect(data.Inventory.paper_clip).toBe(3)
		ctx.expect(data.Discovered.paper_clip).toBeTruthy()
		ctx.expect(Game.admin(ctx, server, owner, "items.grant", { Target = "Player", Item = "infinite_money" }).err).toMatch("Unknown item")
		ctx.expect(Game.admin(ctx, server, owner, "items.remove", { Target = "Player", Item = "paper_clip", Amount = 1 }).ok).toBe(true)
		ctx.expect(data.Inventory.paper_clip).toBe(2)
		ctx.expect(Game.admin(ctx, server, owner, "chests.grant", { Target = "Player", Chest = "neon", Amount = 2 }).ok).toBe(true)
		ctx.expect(data.Chests.neon).toBe(2)

		local before = Game.data(server, owner).Stats.ChestsOpened
		local sim = Game.admin(ctx, server, owner, "items.simulate", { Chest = "starter", Count = 10000 })
		ctx.expect(sim.ok).toBe(true)
		local total = 0
		for _, n in pairs(sim.data.Counts) do
			total += n
		end
		ctx.expect(total).toBe(10000)
		ctx.expect(Game.data(server, owner).Stats.ChestsOpened).toBe(before)

		local forced = Game.admin(ctx, server, owner, "items.forceRoll", { Target = "Player", Chest = "neon", Rarity = "Mythic" })
		ctx.expect(forced.ok).toBe(true)
		ctx.expect(forced.data.Rarity).toBe("Mythic")
		ctx.expect(data.Inventory.neon_dragon).toBe(1)
	end)

	it("grants upgrades, skills, ascensions, levels and skill points", function(ctx)
		local server, owner, _, _, player = studio(ctx)
		local data = Game.data(server, player)
		ctx.expect(Game.admin(ctx, server, owner, "progression.setUpgrade", { Target = "Player", Upgrade = "click_power", Level = 50 }).ok).toBe(true)
		ctx.expect(data.Upgrades.click_power).toBe(50)
		ctx.expect(Game.admin(ctx, server, owner, "progression.setUpgrade", { Target = "Player", Upgrade = "click_power", Level = 5000 }).ok).toBe(false)
		ctx.expect(Game.admin(ctx, server, owner, "progression.unlockSkill", { Target = "Player", Skill = "core" }).ok).toBe(true)
		ctx.expect(data.Skills.core).toBe(1)
		ctx.expect(Game.admin(ctx, server, owner, "progression.grantRebirth", { Target = "Player", Count = 2 }).ok).toBe(true)
		ctx.expect(data.Rebirths).toBe(2)
		ctx.expect(data.Currencies.Prisms).toBeGreaterThan(0)
		ctx.expect(Game.admin(ctx, server, owner, "progression.grantLevels", { Target = "Player", Count = 4 }).ok).toBe(true)
		ctx.expect(data.Level).toBe(5)
		ctx.expect(Game.admin(ctx, server, owner, "progression.grantSkillPoints", { Target = "Player", Amount = 7 }).ok).toBe(true)
	end)
end)

describe("Confirmation of destructive actions", function()
	it("requires a single-use token from the same admin before resetting", function(ctx)
		local h = ctx.harness
		local server, owner, admin, _, player = studio(ctx)
		local data = Game.data(server, player)
		data.Currencies.Gems = 50
		local first = Game.admin(ctx, server, admin, "economy.reset", { Target = "Player" })
		ctx.expect(first.needsConfirm).toBe(true)
		ctx.expect(type(first.token)).toBe("string")
		ctx.expect(data.Currencies.Gems).toBe(50)

		local stolen = Game.admin(ctx, server, owner, "confirm", { Token = first.token })
		ctx.expect(stolen.ok).toBe(false)
		local confirmed = Game.admin(ctx, server, admin, "confirm", { Token = first.token })
		ctx.expect(confirmed.ok).toBe(true)
		ctx.expect(data.Currencies.Gems).toBe(0)
		ctx.expect(Game.admin(ctx, server, admin, "confirm", { Token = first.token }).ok).toBe(false)

		data.Currencies.Gems = 9
		h:advance(30)
		local again = Game.admin(ctx, server, admin, "economy.reset", { Target = "Player" })
		h:advance(60)
		ctx.expect(Game.admin(ctx, server, admin, "confirm", { Token = again.token }).err).toMatch("expired")
		ctx.expect(data.Currencies.Gems).toBe(9)
		ctx.expect(auditHas(server, function(e)
			return e.Action == "economy.reset" and e.Result == "confirm_required"
		end)).toBe(true)
	end)

	it("resets a chosen progression scope only after confirmation", function(ctx)
		local server, owner, _, _, player = studio(ctx)
		local data = Game.data(server, player)
		data.Upgrades.click_power = 10
		data.Inventory.paper_clip = 1
		local ask = Game.admin(ctx, server, owner, "progression.reset", { Target = "Player", Scope = "upgrades" })
		ctx.expect(ask.needsConfirm).toBe(true)
		ctx.expect(data.Upgrades.click_power).toBe(10)
		ctx.expect(Game.admin(ctx, server, owner, "confirm", { Token = ask.token }).ok).toBe(true)
		ctx.expect(data.Upgrades.click_power).toBeNil()
		ctx.expect(data.Inventory.paper_clip).toBe(1)
	end)
end)

describe("Player management", function()
	it("freezes, unfreezes, teleports, respawns and kicks with a reason", function(ctx)
		local h = ctx.harness
		local server, owner, _, _, player = studio(ctx)
		h:advance(2)
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		local root = player.Character:FindFirstChild("HumanoidRootPart")
		ctx.expect(Game.admin(ctx, server, owner, "players.freeze", { Target = "Player" }).ok).toBe(true)
		ctx.expect(humanoid.WalkSpeed).toBe(0)
		ctx.expect(root.Anchored).toBe(true)
		ctx.expect(Game.admin(ctx, server, owner, "players.unfreeze", { Target = "Player" }).ok).toBe(true)
		ctx.expect(humanoid.WalkSpeed).toBe(16)
		ctx.expect(root.Anchored).toBe(false)

		player.Character:PivotTo(roblox.CFrame.new(100, 5, 100))
		ctx.expect(Game.admin(ctx, server, owner, "players.teleportTo", { Target = "Player" }).ok).toBe(true)
		local distance = (owner.Character:GetPivot().Position - player.Character:GetPivot().Position).Magnitude
		ctx.expect(distance).toBeLessThan(10)

		ctx.expect(Game.admin(ctx, server, owner, "players.kick", { Target = "Player" }).err).toMatch("reason")
		ctx.expect(Game.admin(ctx, server, owner, "players.kick", { Target = "Player", Reason = "Spamming the button" }).ok).toBe(true)
		h:advance(1)
		local kicked = false
		for _, k in ipairs(server.kicks) do
			if k.userId == -4 and string.find(k.message, "Spamming the button", 1, true) then
				kicked = true
			end
		end
		ctx.expect(kicked).toBe(true)
	end)
end)

describe("Command bar", function()
	it("parses commands, resolves players safely and validates arguments", function(ctx)
		local server, owner = studio(ctx)
		local alice = Game.join(ctx, server, -5, "Alice")
		Game.join(ctx, server, -6, "Alan")
		local ok = Game.command(ctx, server, owner, "/admin givecash Alice 1.5k")
		ctx.expect(ok.ok).toBe(true)
		ctx.expect(Game.data(server, alice).Currencies.Sparks).toBe(1500)
		ctx.expect(Game.command(ctx, server, owner, "givecash al 10").err).toMatch("ambiguous")
		ctx.expect(Game.command(ctx, server, owner, "givecash Alice lots").err).toMatch("not a valid number")
		ctx.expect(Game.command(ctx, server, owner, "givecash").err).toMatch("Usage")
		ctx.expect(Game.command(ctx, server, owner, "launch").err).toMatch("Unknown command")
		ctx.expect(Game.command(ctx, server, owner, "help").message).toMatch("givecash")
		ctx.expect(Game.command(ctx, server, owner, "help kick").message).toMatch("reason")
		ctx.expect(Game.command(ctx, server, owner, "giveitem @alice paper_clip 2").ok).toBe(true)
		ctx.expect(Game.data(server, alice).Inventory.paper_clip).toBe(2)
		ctx.expect(Game.command(ctx, server, owner, "givechest Alice not_a_crate").err).toMatch("Unknown crate")
		ctx.expect(Game.command(ctx, server, owner, "stats Alice").ok).toBe(true)
		ctx.expect(Game.command(ctx, server, owner, "players").message).toMatch("Alice")
		local reset = Game.command(ctx, server, owner, "resetprogress Alice")
		ctx.expect(reset.needsConfirm).toBe(true)
		ctx.expect(Game.command(ctx, server, owner, `kick #{-5} "Too much fun"`).ok).toBe(true)
	end)
end)

describe("Safeguards", function()
	it("rate limits punitive actions and records everything in the audit log", function(ctx)
		local server, owner = studio(ctx)
		local limited = 0
		for _ = 1, 12 do
			local r = Game.admin(ctx, server, owner, "players.freeze", { Target = "Player" })
			if r.err and string.find(r.err, "rate limited", 1, true) then
				limited += 1
			end
		end
		ctx.expect(limited).toBeGreaterThan(0)
		Game.admin(ctx, server, owner, "economy.add", { Target = "Player", Currency = "Gems", Amount = 25 })
		ctx.expect(auditHas(server, function(e)
			return e.Action == "economy.add"
				and e.AdminId == -1
				and e.TargetId == -4
				and e.Result == "success"
				and string.find(e.Params, "Amount=25", 1, true) ~= nil
				and type(e.Time) == "number"
		end)).toBe(true)
		ctx.expect(auditHas(server, function(e)
			return e.Result == "rate_limited"
		end)).toBe(true)
		local logs = Game.admin(ctx, server, owner, "logs.recent", { Filter = "economy" })
		ctx.expect(#logs.data.Entries).toBeGreaterThan(0)
	end)

	it("edits offline players only when the role allows it and no session holds the data", function(ctx)
		local h = ctx.harness
		local server, owner, admin = studio(ctx)
		local offline = Game.join(ctx, server, 4242, "Sleeper")
		h:removePlayer(offline)
		h:advance(3)
		ctx.expect(Game.admin(ctx, server, owner, "economy.add", { Target = "#4242", Currency = "Gems", Amount = 50 }).ok).toBe(true)
		ctx.expect(h.backend:peek(Game.STORE, Game.storeKey(4242)).Data.Currencies.Gems).toBe(50)
		ctx.expect(Game.admin(ctx, server, admin, "economy.add", { Target = "#4242", Currency = "Gems", Amount = 50 }).err).toMatch("cannot edit offline")
		local inspect = Game.admin(ctx, server, admin, "players.inspect", { Target = "#4242" })
		ctx.expect(inspect.ok).toBe(true)
		ctx.expect(inspect.data.Currencies.Gems).toBe(50)

		local record = h.backend:peek(Game.STORE, Game.storeKey(4242))
		record.Lock = { JobId = "some-other-server", PlaceId = 1, Time = h.scheduler:unixTime() }
		h.backend:poke(Game.STORE, Game.storeKey(4242), record)
		local refused = Game.admin(ctx, server, owner, "economy.add", { Target = "#4242", Currency = "Gems", Amount = 50 })
		ctx.expect(refused.ok).toBe(false)
		ctx.expect(refused.err).toMatch("another server")
		ctx.expect(h.backend:peek(Game.STORE, Game.storeKey(4242)).Data.Currencies.Gems).toBe(50)
	end)
end)

describe("Announcements and events", function()
	it("filters announcements, labels the scope and delivers game-wide ones to other servers", function(ctx)
		local h = ctx.harness
		local a = Game.server(ctx, { creatorId = 3000, jobId = "server-A" })
		local creator = Game.join(ctx, a, 3000, "Creator")
		local _, listenerA = Game.join(ctx, a, 3001, "ListenerA")
		local b = Game.server(ctx, { creatorId = 3000, jobId = "server-B" })
		local _, listenerB = Game.join(ctx, b, 3002, "ListenerB")
		local received = { A = {}, B = {} }
		listenerA:find("ReplicatedStorage.Remotes.Notify").OnClientEvent:Connect(function(kind, data)
			if kind == "Announcement" then
				table.insert(received.A, data)
			end
		end)
		listenerB:find("ReplicatedStorage.Remotes.Notify").OnClientEvent:Connect(function(kind, data)
			if kind == "Announcement" then
				table.insert(received.B, data)
			end
		end)
		ctx.expect(Game.admin(ctx, a, creator, "server.announce", { Message = "Server event soon", Scope = "server" }).ok).toBe(true)
		h:advance(1)
		ctx.expect(#received.A).toBe(1)
		ctx.expect(received.A[1].Scope).toBe("server")
		ctx.expect(#received.B).toBe(0)

		h:advance(40)
		ctx.expect(Game.admin(ctx, a, creator, "server.announce", { Message = "Hello everyone", Scope = "global" }).ok).toBe(true)
		h:advance(2)
		ctx.expect(#received.B).toBe(1)
		ctx.expect(received.B[1].Scope).toBe("global")

		h:advance(40)
		h.backend:failFilterNext(1)
		local failed = Game.admin(ctx, a, creator, "server.announce", { Message = "Unfiltered?", Scope = "server" })
		ctx.expect(failed.ok).toBe(false)
		ctx.expect(failed.err).toMatch("filtering")
	end)

	it("starts and stops server events that change player stats", function(ctx)
		local server, owner, _, _, player = studio(ctx)
		local StatsService = Game.service(server, "StatsService")
		local profile = Game.profile(server, player)
		local before = StatsService:Get(profile).clickValue
		ctx.expect(Game.admin(ctx, server, owner, "server.eventStart", { Event = "spark_surge", Duration = 120 }).ok).toBe(true)
		ctx.expect(StatsService:Get(profile).clickValue).toBe(before * 2)
		ctx.expect(Game.admin(ctx, server, owner, "server.eventStop", { Event = "spark_surge" }).ok).toBe(true)
		ctx.expect(StatsService:Get(profile).clickValue).toBe(before)
		ctx.expect(Game.admin(ctx, server, owner, "server.eventStart", { Event = "chaos", Duration = 120 }).ok).toBe(false)
	end)
end)

return Test.collect()
