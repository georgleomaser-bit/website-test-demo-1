--[[
	Fuzzing: every player action and the admin remote receive thousands of
	random, malformed and hostile payloads. No handler may throw (Net and
	AdminService would hide that behind a generic error, so the server log is
	checked too), nothing may be granted, and the server keeps working.
]]

local Test = require("../harness/Test")
local Game = require("../helpers/Game")

local describe, it = Test.describe, Test.it

local ACTIONS = {
	"BuyUpgrade",
	"OpenChest",
	"Equip",
	"Unequip",
	"EquipBest",
	"Favorite",
	"Sell",
	"SellDuplicates",
	"Fuse",
	"UnlockSkill",
	"ResetSkills",
	"Rebirth",
	"BuyAscension",
	"ClaimCollection",
	"ClaimDaily",
	"ClaimQuest",
	"ClaimQuestBonus",
	"ClaimStarter",
	"ClaimOrb",
	"UpdateSettings",
	"RequestState",
	"GetLeaderboards",
	"ObbyTeleport",
	"TutorialSeen",
	"TutorialSkip",
	"TutorialRestart",
}

-- Small deterministic generator (the test runner has no Roblox Random).
local function makeRng(seed: number)
	local state = seed
	local rng = {}
	function rng:NextNumber(min: number?, max: number?): number
		state = (state * 1103515245 + 12345) % 2147483648
		local f = state / 2147483648
		if min and max then
			return min + (max - min) * f
		end
		return f
	end
	function rng:NextInteger(min: number, max: number): number
		return math.floor(self:NextNumber(min, max + 1 - 1e-9))
	end
	return rng
end

local KEYS = { "Id", "Amount", "Mode", "State", "Index", "Key", "Value", "MaxRarity", "Target", "Currency", "Item", "Chest", "Count", "Text", "Token", "Scope", "Reason", "Message" }

local function randomValue(rng, depth: number)
	local kind = rng:NextInteger(1, 12)
	if kind == 1 then
		return rng:NextInteger(-1e6, 1e6)
	elseif kind == 2 then
		return rng:NextNumber(-1e300, 1e300)
	elseif kind == 3 then
		return ({ 0 / 0, math.huge, -math.huge, 2 ^ 53, -0.5, 1e308 })[rng:NextInteger(1, 6)]
	elseif kind == 4 then
		return string.rep("x", rng:NextInteger(0, 400))
	elseif kind == 5 then
		return ({ "starter", "paper_clip", "core", "click_power", "max", "buy", "owned", "Sparks", "me", "#1", "all", "SFX" })[rng:NextInteger(1, 12)]
	elseif kind == 6 then
		return rng:NextNumber() < 0.5
	elseif kind == 7 and depth < 3 then
		local t = {}
		for _ = 1, rng:NextInteger(0, 4) do
			t[KEYS[rng:NextInteger(1, #KEYS)]] = randomValue(rng, depth + 1)
		end
		return t
	elseif kind == 8 and depth < 3 then
		local t = {}
		for i = 1, rng:NextInteger(0, 5) do
			t[i] = randomValue(rng, depth + 1)
		end
		return t
	elseif kind == 9 then
		return "\0\255" .. string.char(rng:NextInteger(0, 255))
	end
	return nil
end

local function randomPayload(rng)
	if rng:NextNumber() < 0.15 then
		return randomValue(rng, 2)
	end
	local payload = {}
	for _ = 1, rng:NextInteger(0, 5) do
		payload[KEYS[rng:NextInteger(1, #KEYS)]] = randomValue(rng, 1)
	end
	return payload
end

local function failures(world): string
	local out = {}
	for _, entry in ipairs(world.logs) do
		if string.find(entry.text, "failed for", 1, true) or string.find(entry.text, "Request failed", 1, true) or string.find(entry.text, "failed:", 1, true) then
			table.insert(out, entry.text)
		end
	end
	return table.concat(out, "\n")
end

describe("Fuzzing", function()
	it("survives random payloads on every player action without throwing or granting anything", function(ctx)
		local h = ctx.harness
		local server = Game.server(ctx)
		local player = Game.join(ctx, server, 8001, "Fuzzer")
		local rng = makeRng(1234)
		local data = Game.data(server, player)
		local reached = 0
		for _ = 1, 40 do
			for _, action in ipairs(ACTIONS) do
				local result = Game.action(ctx, server, player, action, randomPayload(rng))
				ctx.expect(type(result)).toBe("table")
				if not result.rateLimited then
					reached += 1
				end
			end
			-- Also garbage action names and Click arguments.
			Game.action(ctx, server, player, randomValue(rng, 2), randomPayload(rng))
			h:exploitFire(server, player, "Click", randomValue(rng, 1), randomValue(rng, 1))
			-- Let every rate-limit bucket refill so the payloads reach the handlers.
			h:advance(6)
		end
		ctx.expect(reached).toBeGreaterThan(800)
		h:advance(2)
		ctx.expect(failures(server)).toBe("")
		-- Nothing was bought or unlocked: the fuzzer had no currency to spend.
		ctx.expect(data.Currencies.Prisms).toBe(0)
		ctx.expect(data.Rebirths).toBe(0)
		ctx.expect(next(data.Upgrades)).toBeNil()
		ctx.expect(next(data.Skills)).toBeNil()
		ctx.expect(next(data.Inventory)).toBeNil()
		-- The server still works normally afterwards.
		h:advance(30)
		Game.give(server, player, "Sparks", 100)
		ctx.expect(Game.action(ctx, server, player, "BuyUpgrade", { Id = "click_power", Amount = 1 }).ok).toBe(true)
	end)

	it("survives random admin payloads from staff and outsiders", function(ctx)
		local h = ctx.harness
		local server = Game.server(ctx, { isStudio = true })
		local owner = Game.join(ctx, server, -1, "Owner")
		local outsider = Game.join(ctx, server, -4, "Outsider")
		local rng = makeRng(99)
		local AdminActions = Game.service(server, "AdminActions")
		local names = {}
		for name in pairs(AdminActions.Definitions) do
			table.insert(names, name)
		end
		table.sort(names)
		local reachedAdmin = 0
		for _ = 1, 12 do
			for _, name in ipairs(names) do
				local args = randomPayload(rng)
				if type(args) == "table" and rng:NextNumber() < 0.5 then
					args.Target = ({ "Outsider", "Owner", "#-4", -4, "me", "nobody", "#99999" })[rng:NextInteger(1, 7)]
				end
				local result = Game.admin(ctx, server, owner, name, args)
				ctx.expect(type(result)).toBe("table")
				if not (result.err and string.find(result.err, "Slow down", 1, true)) then
					reachedAdmin += 1
				end
				h:advance(0.5)
				local denied = h:exploitInvoke(server, outsider, "Admin", { Action = name, Args = args, RequestId = Game.nextRequestId() })
				ctx.expect(denied.err).toBe("Not authorized.")
			end
			Game.command(ctx, server, owner, tostring(randomValue(rng, 2)))
			h:advance(25)
		end
		ctx.expect(reachedAdmin).toBeGreaterThan(#names * 8)
		ctx.expect(failures(server)).toBe("")
		ctx.expect(Game.data(server, outsider)).toBeTruthy()
	end)
end)

return Test.collect()
