--[[
	Moderation: staff roles an Owner hands out in the game, and bans.
	Live servers here are created with creatorId = OWNER, so that user is Owner
	through place ownership (AdminConfig.AutoOwnerForCreator).
]]

local Test = require("../harness/Test")
local Game = require("../helpers/Game")

local describe, it = Test.describe, Test.it

local STORE = "ButtonAscension_Moderation"
local OWNER, ALICE, BOB, CARL = 3000, 3101, 3102, 3103

local function live(ctx, jobId: string?)
	return Game.server(ctx, { creatorId = OWNER, jobId = jobId })
end

local function kickedWith(server, userId: number, pattern: string): boolean
	for _, kick in ipairs(server.kicks) do
		if kick.userId == userId and string.find(kick.message or "", pattern, 1, true) then
			return true
		end
	end
	return false
end

local function hasPanel(player): boolean
	return player.PlayerGui:FindFirstChild("AdminPanelGui") ~= nil
end

-- Runs a destructive admin action through its confirmation step.
local function confirmed(ctx, server, admin, action: string, args)
	local ask = Game.admin(ctx, server, admin, action, args)
	if not ask.needsConfirm then
		return ask
	end
	return Game.admin(ctx, server, admin, "confirm", { Token = ask.token })
end

describe("Staff roles given in the game", function()
	it("lets the Owner make a player Moderator, who can then kick, freeze and ban", function(ctx)
		local h = ctx.harness
		local server = live(ctx)
		local owner = Game.join(ctx, server, OWNER, "Owner")
		local alice = Game.join(ctx, server, ALICE, "Alice")
		local bob = Game.join(ctx, server, BOB, "Bob")
		ctx.expect(hasPanel(alice)).toBe(false)
		ctx.expect(Game.admin(ctx, server, alice, "hello").err).toBe("Not authorized.")

		local ask = Game.admin(ctx, server, owner, "staff.setRole", { Target = "Alice", Role = "moderator" })
		ctx.expect(ask.needsConfirm).toBe(true)
		ctx.expect(ask.summary).toMatch("ban")
		ctx.expect(hasPanel(alice)).toBe(false)
		ctx.expect(Game.admin(ctx, server, owner, "confirm", { Token = ask.token }).ok).toBe(true)
		h:advance(2)

		ctx.expect(hasPanel(alice)).toBe(true)
		ctx.expect(Game.admin(ctx, server, alice, "hello").data.Role).toBe("Moderator")
		ctx.expect(h.backend:peek(STORE, "StaffRoles")[tostring(ALICE)].Role).toBe("Moderator")
		-- Moderator powers: freeze, kick, ban. Not the economy, not roles.
		ctx.expect(Game.admin(ctx, server, alice, "players.freeze", { Target = "Bob" }).ok).toBe(true)
		ctx.expect(Game.admin(ctx, server, alice, "economy.add", { Target = "Bob", Currency = "Gems", Amount = 5 }).ok).toBe(false)
		ctx.expect(Game.admin(ctx, server, alice, "staff.setRole", { Target = "Bob", Role = "admin" }).ok).toBe(false)
		ctx.expect(confirmed(ctx, server, alice, "players.ban", { Target = "Bob", Duration = "1d", Reason = "Testing bans" }).ok).toBe(true)
		h:advance(1)
		ctx.expect(kickedWith(server, BOB, "banned")).toBe(true)
		ctx.expect(bob.Parent).toBeNil()
	end)

	it("applies roles in every server within seconds, and takes them away again", function(ctx)
		local h = ctx.harness
		local a = live(ctx, "server-A")
		local b = live(ctx, "server-B")
		local owner = Game.join(ctx, a, OWNER, "Owner")
		local carl = Game.join(ctx, b, CARL, "Carl")
		h:advance(2)

		-- Carl is not in server A: the exact username is looked up through Roblox.
		local result = confirmed(ctx, a, owner, "staff.setRole", { Target = "Carl", Role = "admin" })
		ctx.expect(result.ok).toBe(true)
		ctx.expect(result.message).toMatch("every server")
		h:advance(3)
		ctx.expect(hasPanel(carl)).toBe(true)
		ctx.expect(Game.admin(ctx, b, carl, "hello").data.Role).toBe("Admin")

		ctx.expect(Game.admin(ctx, a, owner, "staff.removeRole", { Target = "#" .. CARL }).ok).toBe(true)
		h:advance(3)
		ctx.expect(hasPanel(carl)).toBe(false)
		ctx.expect(Game.admin(ctx, b, carl, "hello").err).toBe("Not authorized.")

		-- Given again, the role is there when Carl joins a brand-new server.
		ctx.expect(confirmed(ctx, a, owner, "staff.setRole", { Target = "#" .. CARL, Role = "moderator" }).ok).toBe(true)
		h:removePlayer(carl)
		h:advance(5)
		local c = live(ctx, "server-C")
		local carlAgain = Game.join(ctx, c, CARL, "Carl")
		h:advance(2)
		ctx.expect(hasPanel(carlAgain)).toBe(true)
		ctx.expect(Game.admin(ctx, c, carlAgain, "hello").data.Role).toBe("Moderator")
	end)

	it("lets only Owners hand out roles, never Owner itself, and never changes config roles", function(ctx)
		local h = ctx.harness
		local server = Game.server(ctx, { isStudio = true })
		local owner = Game.join(ctx, server, -1, "Owner")
		local admin = Game.join(ctx, server, -2, "Admin")
		local player = Game.join(ctx, server, -4, "Player")
		ctx.expect(Game.admin(ctx, server, admin, "staff.setRole", { Target = "Player", Role = "moderator" }).err).toMatch("permission")
		ctx.expect(Game.admin(ctx, server, owner, "staff.setRole", { Target = "Player", Role = "owner" }).err).toMatch("Choose a role")
		local fixed = confirmed(ctx, server, owner, "staff.setRole", { Target = "Admin", Role = "moderator" })
		ctx.expect(fixed.ok).toBe(false)
		ctx.expect(fixed.err).toMatch("AdminConfig")
		ctx.expect(Game.admin(ctx, server, owner, "staff.removeRole", { Target = "Admin" }).err).toMatch("AdminConfig")
		-- A normal player firing the remote directly is refused and nothing is stored.
		local forged = h:exploitInvoke(server, player, "Admin", { Action = "staff.setRole", Args = { Target = "me", Role = "admin" }, RequestId = Game.nextRequestId() })
		ctx.expect(forged.err).toBe("Not authorized.")
		ctx.expect(h.backend:peek(STORE, "StaffRoles")).toBeNil()
		ctx.expect(hasPanel(player)).toBe(false)
	end)

	it("works for the session only in Studio without API access", function(ctx)
		local h = ctx.harness
		ctx.allowScriptErrors()
		h.backend:setUnavailable("StudioAccessToApisNotAllowed: Studio access to API services is not allowed.")
		local server = Game.server(ctx, { isStudio = true })
		local owner = Game.join(ctx, server, -1, "Owner")
		local player = Game.join(ctx, server, -4, "Player")
		local result = confirmed(ctx, server, owner, "staff.setRole", { Target = "Player", Role = "moderator" })
		ctx.expect(result.ok).toBe(true)
		ctx.expect(result.message).toMatch("temporary Studio session")
		h:advance(2)
		ctx.expect(hasPanel(player)).toBe(true)
	end)

	it("supports the command bar", function(ctx)
		local h = ctx.harness
		local server = live(ctx)
		local owner = Game.join(ctx, server, OWNER, "Owner")
		local alice = Game.join(ctx, server, ALICE, "Alice")
		local ask = Game.command(ctx, server, owner, "/admin mod Alice")
		ctx.expect(ask.needsConfirm).toBe(true)
		ctx.expect(Game.admin(ctx, server, owner, "confirm", { Token = ask.token }).ok).toBe(true)
		h:advance(2)
		ctx.expect(hasPanel(alice)).toBe(true)
		ctx.expect(Game.command(ctx, server, owner, "/admin staff").message).toMatch("Moderator: @Alice")
		ctx.expect(Game.command(ctx, server, owner, "/admin removerole Alice").ok).toBe(true)
	end)
end)

describe("Bans", function()
	it("bans across servers, keeps the player out and mirrors the ban to Roblox", function(ctx)
		local h = ctx.harness
		local a = live(ctx, "server-A")
		local b = live(ctx, "server-B")
		local owner = Game.join(ctx, a, OWNER, "Owner")
		Game.join(ctx, a, ALICE, "Alice")
		Game.join(ctx, b, BOB, "Bob")
		h:advance(2)

		ctx.expect(confirmed(ctx, a, owner, "players.ban", { Target = "Alice", Duration = "1d", Reason = "Spamming the chat" }).ok).toBe(true)
		h:advance(1)
		ctx.expect(kickedWith(a, ALICE, "You are banned from")).toBe(true)
		local stored = h.backend:peek(STORE, "Bans")[tostring(ALICE)]
		ctx.expect(stored.Reason).toBe("Spamming the chat")
		ctx.expect(stored.Until - stored.At).toBe(86400)
		local call = h.backend.banApiCalls[1]
		ctx.expect(call.Kind).toBe("ban")
		ctx.expect(call.Config.UserIds[1]).toBe(ALICE)
		ctx.expect(call.Config.Duration).toBe(86400)

		-- Bob is in server B; the ban reaches him there.
		ctx.expect(confirmed(ctx, a, owner, "players.ban", { Target = "Bob", Duration = "perm", Reason = "Exploiting" }).ok).toBe(true)
		h:advance(3)
		ctx.expect(kickedWith(b, BOB, "permanently")).toBe(true)
		ctx.expect(h.backend.banApiCalls[2].Config.Duration).toBe(-1)

		-- Rejoining any server does not help.
		Game.join(ctx, b, ALICE, "Alice")
		ctx.expect(kickedWith(b, ALICE, "You are banned from")).toBe(true)
		local fresh = live(ctx, "server-C")
		Game.join(ctx, fresh, BOB, "Bob")
		ctx.expect(kickedWith(fresh, BOB, "Exploiting")).toBe(true)
	end)

	it("limits Moderators to 7 days and protects equal or higher staff", function(ctx)
		local h = ctx.harness
		local server = live(ctx)
		local owner = Game.join(ctx, server, OWNER, "Owner")
		local alice = Game.join(ctx, server, ALICE, "Alice")
		local bob = Game.join(ctx, server, BOB, "Bob")
		Game.join(ctx, server, CARL, "Carl")
		ctx.expect(confirmed(ctx, server, owner, "staff.setRole", { Target = "Alice", Role = "moderator" }).ok).toBe(true)
		ctx.expect(confirmed(ctx, server, owner, "staff.setRole", { Target = "Bob", Role = "moderator" }).ok).toBe(true)
		h:advance(2)

		ctx.expect(Game.admin(ctx, server, alice, "players.ban", { Target = "Carl", Duration = "perm", Reason = "x" }).err).toMatch("at most 7 days")
		ctx.expect(Game.admin(ctx, server, alice, "players.ban", { Target = "Carl", Duration = "8d", Reason = "x" }).err).toMatch("at most 7 days")
		ctx.expect(Game.admin(ctx, server, alice, "players.ban", { Target = "Owner", Duration = "1d", Reason = "x" }).err).toMatch("equal or higher rank")
		ctx.expect(Game.admin(ctx, server, alice, "players.ban", { Target = "Bob", Duration = "1d", Reason = "x" }).err).toMatch("equal or higher rank")
		ctx.expect(Game.admin(ctx, server, alice, "players.ban", { Target = "Carl", Duration = "soon", Reason = "x" }).err).toMatch("30m, 12h, 7d")

		-- An Owner's ban cannot be lifted by a Moderator.
		ctx.expect(confirmed(ctx, server, owner, "players.ban", { Target = "Carl", Duration = "perm", Reason = "Cheating" }).ok).toBe(true)
		ctx.expect(Game.admin(ctx, server, bob, "players.unban", { Target = "#" .. CARL }).err).toMatch("higher%-ranked")
		ctx.expect(Game.admin(ctx, server, owner, "players.unban", { Target = "#" .. CARL }).ok).toBe(true)
		local last = h.backend.banApiCalls[#h.backend.banApiCalls]
		ctx.expect(last.Kind).toBe("unban")
		ctx.expect(last.Config.UserIds[1]).toBe(CARL)
		ctx.expect(h.backend:peek(STORE, "Bans")[tostring(CARL)]).toBeNil()
	end)

	it("lets players back in when a ban expires", function(ctx)
		local h = ctx.harness
		local server = live(ctx)
		local owner = Game.join(ctx, server, OWNER, "Owner")
		Game.join(ctx, server, ALICE, "Alice")
		ctx.expect(confirmed(ctx, server, owner, "players.ban", { Target = "Alice", Duration = "2m", Reason = "Cool down" }).ok).toBe(true)
		h:advance(5)
		Game.join(ctx, server, ALICE, "Alice")
		ctx.expect(#server.kicks).toBe(2)
		h:advance(130)
		local alice = Game.join(ctx, server, ALICE, "Alice")
		ctx.expect(alice.Parent).toBeTruthy()
		ctx.expect(#server.kicks).toBe(2)
		ctx.expect(Game.admin(ctx, server, owner, "players.bans").message).toBe("Nobody is banned.")
	end)

	it("bans offline players by #UserId or exact username", function(ctx)
		local h = ctx.harness
		local server = live(ctx)
		local owner = Game.join(ctx, server, OWNER, "Owner")
		h.backend.userNames[4444] = "Ghost"
		local byId = confirmed(ctx, server, owner, "players.ban", { Target = "#4444", Duration = "7d", Reason = "Alt account" })
		ctx.expect(byId.ok).toBe(true)
		ctx.expect(h.backend:peek(STORE, "Bans")["4444"].Name).toBe("@Ghost (#4444)")
		h.backend.userNames[5555] = "Shadow"
		ctx.expect(confirmed(ctx, server, owner, "players.ban", { Target = "@Shadow", Duration = "1h", Reason = "Alt account" }).ok).toBe(true)
		ctx.expect(h.backend:peek(STORE, "Bans")["5555"]).toBeTruthy()
		ctx.expect(Game.admin(ctx, server, owner, "players.ban", { Target = "NoSuchUser", Duration = "1h", Reason = "x" }).err).toMatch("No Roblox user")
		Game.join(ctx, server, 4444, "Ghost")
		ctx.expect(kickedWith(server, 4444, "Alt account")).toBe(true)
		ctx.expect(Game.command(ctx, server, owner, "/admin bans").message).toMatch("2 banned")
	end)

	it("keeps enforcing its own list when Roblox's Ban API fails, and refuses forged requests", function(ctx)
		local h = ctx.harness
		local server = live(ctx)
		local owner = Game.join(ctx, server, OWNER, "Owner")
		local alice = Game.join(ctx, server, ALICE, "Alice")
		Game.join(ctx, server, BOB, "Bob")
		local forged = h:exploitInvoke(server, alice, "Admin", {
			Action = "players.ban",
			Args = { Target = "Bob", Duration = "perm", Reason = "lol" },
			RequestId = Game.nextRequestId(),
		})
		ctx.expect(forged.err).toBe("Not authorized.")
		ctx.expect(h.backend:peek(STORE, "Bans")).toBeNil()

		h.backend.banApiError = "HTTP 500 (Internal Server Error)"
		local result = Game.command(ctx, server, owner, "/admin ban Bob 1d Being rude")
		ctx.expect(result.needsConfirm).toBe(true)
		local done = Game.admin(ctx, server, owner, "confirm", { Token = result.token })
		ctx.expect(done.ok).toBe(true)
		ctx.expect(done.message).toMatch("did not accept")
		ctx.expect(kickedWith(server, BOB, "Being rude")).toBe(true)
	end)
end)

describe("Moderation tab", function()
	local function boxWithPlaceholder(h, root, text: string)
		for _, box in ipairs(h:queryDescendants(root, function(st)
			return st.className == "TextBox"
		end)) do
			if string.find(box.PlaceholderText, text, 1, true) then
				return box
			end
		end
		return nil
	end

	it("lets an Owner give a role and ban a player from the admin panel", function(ctx)
		local h = ctx.harness
		local server = Game.server(ctx, { isStudio = true })
		local _, client = Game.join(ctx, server, -1, "Owner")
		local player = Game.join(ctx, server, -4, "Player")
		local victim = Game.join(ctx, server, -5, "Victim")
		h:advance(4)
		local playerGui = client:find("Players.Owner.PlayerGui")
		local panelGui = client:find("Players.Owner.PlayerGui.AdminPanelGui")
		h:click(h:findDescendant(panelGui, "AdminToggle", "TextButton"))
		h:advance(1)
		h:click(h:findDescendant(panelGui, "Moderation", "TextButton"))
		h:advance(2)
		local tabFrame = h:findDescendant(panelGui, "Moderation", "Frame")
		ctx.expect(h:findByText(tabFrame, "Ban a player")).toBeTruthy()
		ctx.expect(h:findByText(tabFrame, "Staff roles")).toBeTruthy()

		-- Give the Moderator role (the staff target box is the second "name, @username" box).
		local boxes = {}
		for _, box in ipairs(h:queryDescendants(tabFrame, function(st)
			return st.className == "TextBox"
		end)) do
			if string.find(box.PlaceholderText, "@username", 1, true) then
				table.insert(boxes, box)
			end
		end
		ctx.expect(#boxes).toBe(2)
		h:typeInto(boxes[2], "Player")
		h:click(h:findByText(tabFrame, "Give role", "TextButton"))
		h:advance(1)
		h:click(h:findByText(playerGui, "Confirm", "TextButton"))
		h:advance(3)
		ctx.expect(player.PlayerGui:FindFirstChild("AdminPanelGui")).toBeTruthy()

		-- Ban with the default length (1 day) and a reason.
		h:typeInto(boxes[1], "Victim")
		h:typeInto(boxWithPlaceholder(h, tabFrame, "Shown to the player"), "Griefing")
		h:click(h:findByText(tabFrame, "🚫 Ban", "TextButton"))
		h:advance(1)
		h:click(h:findByText(playerGui, "Confirm", "TextButton"))
		h:advance(3)
		ctx.expect(kickedWith(server, -5, "Griefing")).toBe(true)
		ctx.expect(victim.Parent).toBeNil()
		ctx.expect(h:findByText(tabFrame, "Victim")).toBeTruthy()
	end)

	it("shows Moderators the ban tools but not the staff tools", function(ctx)
		local h = ctx.harness
		local server = Game.server(ctx, { isStudio = true })
		local _, client = Game.join(ctx, server, -3, "Moderator")
		h:advance(4)
		local panelGui = client:find("Players.Moderator.PlayerGui.AdminPanelGui")
		h:click(h:findDescendant(panelGui, "AdminToggle", "TextButton"))
		h:advance(1)
		h:click(h:findDescendant(panelGui, "Moderation", "TextButton"))
		h:advance(2)
		local tabFrame = h:findDescendant(panelGui, "Moderation", "Frame")
		ctx.expect(h:findByText(tabFrame, "up to 7 days")).toBeTruthy()
		ctx.expect(h:findByText(tabFrame, "Permanent")).toBeNil()
		ctx.expect(h:findByText(tabFrame, "Staff roles")).toBeNil()
	end)
end)

return Test.collect()
