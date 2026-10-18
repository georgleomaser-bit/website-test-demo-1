--[[
	Persistence: saving and rejoining, retries, DataStore outages, Studio
	without API access, session locks across servers (fresh, stale and stolen
	locks), schema migration, sanitising invalid data and shutdown saves.
]]

local Test = require("../harness/Test")
local Game = require("../helpers/Game")

local describe, it = Test.describe, Test.it

local STORE = Game.STORE
local USER = 2001
local KEY = Game.storeKey(USER)

local function kickedWith(server, userId: number, pattern: string): boolean
	for _, kick in ipairs(server.kicks) do
		if kick.userId == userId and string.find(kick.message or "", pattern) then
			return true
		end
	end
	return false
end

describe("Saving", function()
	it("saves on leave, releases the lock and restores the data in another server", function(ctx)
		local h = ctx.harness
		local a = Game.server(ctx, { jobId = "server-A" })
		local alice = Game.join(ctx, a, USER, "Alice")
		local data = Game.data(a, alice)
		data.Currencies.Sparks = 500
		data.Currencies.Gems = 7
		data.Inventory.paper_clip = 2
		data.Discovered.paper_clip = 1
		h:removePlayer(alice)
		h:advance(3)
		local record = h.backend:peek(STORE, KEY)
		ctx.expect(record).toBeTruthy()
		ctx.expect(record.Lock).toBeNil()
		ctx.expect(record.Data.Currencies.Sparks).toBe(500)
		ctx.expect(record.Data.Version).toBe(2)

		local b = Game.server(ctx, { jobId = "server-B" })
		local again = Game.join(ctx, b, USER, "Alice")
		local restored = Game.data(b, again)
		ctx.expect(restored.Currencies.Sparks).toBe(500)
		ctx.expect(restored.Currencies.Gems).toBe(7)
		ctx.expect(restored.Inventory.paper_clip).toBe(2)
		ctx.expect(restored.Meta.Sessions).toBe(2)
		ctx.expect(h.backend:peek(STORE, KEY).Lock.JobId).toBe("server-B")
	end)

	it("autosaves while playing and keeps the session lock fresh", function(ctx)
		local h = ctx.harness
		local a = Game.server(ctx, { jobId = "server-A" })
		local alice = Game.join(ctx, a, USER, "Alice")
		Game.data(a, alice).Currencies.Gems = 42
		h:advance(70)
		local record = h.backend:peek(STORE, KEY)
		ctx.expect(record.Data.Currencies.Gems).toBe(42)
		ctx.expect(record.Lock.JobId).toBe("server-A")
		ctx.expect(record.Lock.Time).toBeGreaterThan(h.scheduler:unixTime() - 15)
	end)

	it("saves every player when the server shuts down", function(ctx)
		local h = ctx.harness
		local a = Game.server(ctx, { jobId = "server-A" })
		local alice = Game.join(ctx, a, USER, "Alice")
		local bob = Game.join(ctx, a, USER + 1, "Bob")
		Game.data(a, alice).Currencies.Gems = 11
		Game.data(a, bob).Currencies.Gems = 22
		h:run(function()
			h:shutdown(a)
		end, 40)
		ctx.expect(h.backend:peek(STORE, KEY).Data.Currencies.Gems).toBe(11)
		ctx.expect(h.backend:peek(STORE, Game.storeKey(USER + 1)).Data.Currencies.Gems).toBe(22)
		ctx.expect(h.backend:peek(STORE, KEY).Lock).toBeNil()
	end)
end)

describe("DataStore failures", function()
	it("retries transient failures while loading", function(ctx)
		local h = ctx.harness
		ctx.allowScriptErrors()
		h.backend:poke(STORE, KEY, { Schema = 2, Data = { Version = 2, Currencies = { Sparks = 1234, Gems = 0, Prisms = 0 } } })
		h.backend:failNext("UpdateAsync", 3)
		local a = Game.server(ctx)
		local alice = Game.join(ctx, a, USER, "Alice")
		h:advance(10)
		ctx.expect(kickedWith(a, USER, ".")).toBe(false)
		ctx.expect(Game.data(a, alice).Currencies.Sparks).toBe(1234)
	end)

	it("kicks instead of playing on empty data when loading keeps failing", function(ctx)
		local h = ctx.harness
		ctx.allowScriptErrors()
		h.backend:poke(STORE, KEY, { Schema = 2, Data = { Version = 2, Currencies = { Sparks = 999, Gems = 0, Prisms = 0 } } })
		h.backend:failNext("UpdateAsync", 50)
		local a = Game.server(ctx)
		h:addPlayer(a, { userId = USER, name = "Alice" })
		h:advance(60)
		ctx.expect(kickedWith(a, USER, "not responding")).toBe(true)
		-- The real progress was never overwritten.
		ctx.expect(h.backend:peek(STORE, KEY).Data.Currencies.Sparks).toBe(999)
	end)

	it("retries failed saves and reports them", function(ctx)
		local h = ctx.harness
		ctx.allowScriptErrors()
		local a = Game.server(ctx)
		local alice = Game.join(ctx, a, USER, "Alice")
		Game.data(a, alice).Currencies.Gems = 5
		h.backend:failNext("UpdateAsync", 2)
		h:removePlayer(alice)
		h:advance(15)
		ctx.expect(h.backend:peek(STORE, KEY).Data.Currencies.Gems).toBe(5)
		local status = Game.service(a, "DataService"):GetStatus()
		ctx.expect(status.SaveFailures).toBeGreaterThanOrEqual(2)
	end)

	it("uses a clearly labelled temporary profile in Studio without API access and never writes", function(ctx)
		local h = ctx.harness
		ctx.allowScriptErrors()
		h.backend:setUnavailable("StudioAccessToApisNotAllowed: Studio access to API services is not allowed.")
		local a = Game.server(ctx, { isStudio = true })
		local alice, client = Game.join(ctx, a, USER, "Alice")
		local profile = Game.profile(a, alice)
		ctx.expect(profile.Temporary).toBe(true)
		local State = client:requirePath("Players.Alice.PlayerScripts.Client.State")
		h:advance(2)
		ctx.expect(State.Data.Derived.Persistent).toBe(false)
		h:removePlayer(alice)
		h:advance(5)
		ctx.expect(#h.backend:keys(STORE)).toBe(0)
	end)
end)

describe("Session locking", function()
	it("refuses a second server while the first holds a fresh lock", function(ctx)
		local h = ctx.harness
		local a = Game.server(ctx, { jobId = "server-A" })
		local alice = Game.join(ctx, a, USER, "Alice")
		Game.data(a, alice).Currencies.Gems = 3
		local b = Game.server(ctx, { jobId = "server-B" })
		h:addPlayer(b, { userId = USER, name = "Alice" })
		h:advance(45)
		ctx.expect(kickedWith(b, USER, "still being saved")).toBe(true)
		ctx.expect(h.backend:peek(STORE, KEY).Lock.JobId).toBe("server-A")
		ctx.expect(Game.profile(a, alice)).toBeTruthy()
	end)

	it("waits for the other server to finish saving, then loads the newest data", function(ctx)
		local h = ctx.harness
		local a = Game.server(ctx, { jobId = "server-A" })
		local alice = Game.join(ctx, a, USER, "Alice")
		Game.data(a, alice).Currencies.Gems = 64
		local b = Game.server(ctx, { jobId = "server-B" })
		local bAlice = h:addPlayer(b, { userId = USER, name = "Alice" })
		h:advance(2)
		h:removePlayer(alice)
		h:advance(15)
		ctx.expect(kickedWith(b, USER, ".")).toBe(false)
		ctx.expect(Game.data(b, bAlice).Currencies.Gems).toBe(64)
	end)

	it("takes over a stale lock left behind by a crashed server", function(ctx)
		local h = ctx.harness
		h.backend:poke(STORE, KEY, {
			Schema = 2,
			Data = { Version = 2, Currencies = { Sparks = 0, Gems = 9, Prisms = 0 } },
			Lock = { JobId = "crashed-server", PlaceId = 1, Time = h.scheduler:unixTime() - 1000 },
		})
		local b = Game.server(ctx, { jobId = "server-B" })
		local alice = Game.join(ctx, b, USER, "Alice")
		ctx.expect(Game.data(b, alice).Currencies.Gems).toBe(9)
		ctx.expect(h.backend:peek(STORE, KEY).Lock.JobId).toBe("server-B")
	end)

	it("stops saving and removes the player if another server took the lock", function(ctx)
		local h = ctx.harness
		ctx.allowScriptErrors()
		local a = Game.server(ctx, { jobId = "server-A" })
		local alice = Game.join(ctx, a, USER, "Alice")
		Game.data(a, alice).Currencies.Gems = 1
		local record = h.backend:peek(STORE, KEY)
		record.Lock = { JobId = "server-Z", PlaceId = 1, Time = h.scheduler:unixTime() }
		record.Data = { Version = 2, Currencies = { Sparks = 0, Gems = 500, Prisms = 0 } }
		h.backend:poke(STORE, KEY, record)
		h:advance(70)
		ctx.expect(kickedWith(a, USER, "another server")).toBe(true)
		local after = h.backend:peek(STORE, KEY)
		ctx.expect(after.Data.Currencies.Gems).toBe(500)
		ctx.expect(after.Lock.JobId).toBe("server-Z")
	end)
end)

describe("Schema and validation", function()
	it("migrates version 1 data to the current schema", function(ctx)
		local h = ctx.harness
		h.backend:poke(STORE, KEY, {
			Schema = 1,
			Data = {
				Version = 1,
				Currencies = { Sparks = 50 },
				Inventory = { "paper_clip", "paper_clip", "rusty_bolt" },
				Settings = { Volume = 0.2 },
			},
		})
		local a = Game.server(ctx)
		local alice = Game.join(ctx, a, USER, "Alice")
		local data = Game.data(a, alice)
		ctx.expect(data.Version).toBe(2)
		ctx.expect(data.Inventory.paper_clip).toBe(2)
		ctx.expect(data.Inventory.rusty_bolt).toBe(1)
		ctx.expect(data.Settings.Music).toBe(0.2)
		ctx.expect(data.Settings.SFX).toBe(0.2)
		ctx.expect(data.Discovered.paper_clip).toBeTruthy()
		h:removePlayer(alice)
		h:advance(3)
		ctx.expect(h.backend:peek(STORE, KEY).Data.Version).toBe(2)
		ctx.expect(h.backend:peek(STORE, KEY).Schema).toBe(2)
	end)

	it("sanitises tampered or corrupted values", function(ctx)
		local h = ctx.harness
		ctx.allowScriptErrors()
		h.backend:poke(STORE, KEY, {
			Schema = 2,
			Data = {
				Version = 2,
				Currencies = { Sparks = -50, Gems = "lots", Prisms = 3.5 },
				Level = 1e9,
				SkillPoints = -4,
				Upgrades = { click_power = 99999, hack_upgrade = 5 },
				Skills = { core = 99, made_up = 1 },
				Inventory = { paper_clip = -3, ghost_item = 4, rusty_bolt = 2.7 },
				Equipped = { "golden_plug", "rusty_bolt", "rusty_bolt", 7 },
				Settings = { SFX = 9, ReducedMotion = "yes" },
				Quests = "broken",
				Stats = { TotalClicks = -10 },
			},
		})
		local a = Game.server(ctx)
		local alice = Game.join(ctx, a, USER, "Alice")
		local data = Game.data(a, alice)
		ctx.expect(data.Currencies.Sparks).toBe(0)
		ctx.expect(data.Currencies.Gems).toBe(0)
		ctx.expect(data.Currencies.Prisms).toBe(3.5)
		ctx.expect(data.Level).toBe(1000)
		ctx.expect(data.SkillPoints).toBe(0)
		ctx.expect(data.Upgrades.click_power).toBe(500)
		ctx.expect(data.Upgrades.hack_upgrade).toBeNil()
		ctx.expect(data.Skills.core).toBe(1)
		ctx.expect(data.Skills.made_up).toBeNil()
		ctx.expect(data.Inventory.paper_clip).toBeNil()
		ctx.expect(data.Inventory.rusty_bolt).toBe(2)
		ctx.expect(data.LegacyInventory.ghost_item).toBe(4)
		ctx.expect(data.Equipped).toEqual({ "rusty_bolt" })
		ctx.expect(data.Settings.SFX).toBe(1)
		ctx.expect(data.Settings.ReducedMotion).toBe(false)
		ctx.expect(#data.Quests.Daily).toBe(3)
		ctx.expect(data.Stats.TotalClicks).toBe(0)
	end)

	it("refuses to touch data written by a newer game version", function(ctx)
		local h = ctx.harness
		local future = { Schema = 99, Data = { Version = 99, Currencies = { Sparks = 7 } } }
		h.backend:poke(STORE, KEY, future)
		local a = Game.server(ctx)
		h:addPlayer(a, { userId = USER, name = "Alice" })
		h:advance(5)
		ctx.expect(kickedWith(a, USER, "newer version")).toBe(true)
		ctx.expect(h.backend:peek(STORE, KEY)).toEqual(future)
	end)

	it("refuses to overwrite an unreadable record", function(ctx)
		local h = ctx.harness
		h.backend:poke(STORE, KEY, "this is not a table")
		local a = Game.server(ctx)
		h:addPlayer(a, { userId = USER, name = "Alice" })
		h:advance(5)
		ctx.expect(kickedWith(a, USER, "protect")).toBe(true)
		ctx.expect(h.backend:peek(STORE, KEY)).toBe("this is not a table")
	end)
end)

describe("Offline earnings", function()
	it("grants a capped share of passive income for time away", function(ctx)
		local h = ctx.harness
		h.backend:poke(STORE, KEY, {
			Schema = 2,
			Data = {
				Version = 2,
				Currencies = { Sparks = 0, Gems = 0, Prisms = 0 },
				Upgrades = { generator = 10 },
				Meta = { LastSeen = h.scheduler:unixTime() - 3600, LastSave = 0, Created = 0, Sessions = 1 },
			},
		})
		local a = Game.server(ctx)
		local alice = Game.join(ctx, a, USER, "Alice")
		local data = Game.data(a, alice)
		local stats = Game.service(a, "StatsService"):GetBase(Game.profile(a, alice))
		local expected = stats.passivePerSec * 3600 * stats.offlineRate
		ctx.expect(data.Stats.OfflineEarned).toBeCloseTo(expected, expected * 0.02)
	end)
end)

return Test.collect()
