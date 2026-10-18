--[[
	Game.luau — helpers shared by the game specs.

	Every helper drives the REAL server code through the same remotes a
	client (or an exploiter) would use. Profiles are only read directly to
	assert results or to arrange a scenario quickly.
]]

local Game = {}

local requestCounter = 0

function Game.server(ctx, options)
	return ctx.harness:createServer(options)
end

-- Joins a player and waits until their profile has loaded.
function Game.join(ctx, server, userId: number, name: string, extra: { [string]: any }?)
	local opts = { userId = userId, name = name, displayName = name }
	for k, v in pairs(extra or {}) do
		opts[k] = v
	end
	local player, client = ctx.harness:addPlayer(server, opts)
	local DataService = Game.service(server, "DataService")
	for _ = 1, 100 do
		if DataService:GetProfile(player) or player.Parent == nil then
			break
		end
		ctx.harness:advance(0.25)
	end
	ctx.harness:advance(0.5)
	return player, client
end

function Game.service(server, name: string)
	local path = if string.find(name, "^Admin") or name == "AuditLog" or name == "PlayerResolver"
		then "ServerScriptService.Admin." .. name
		else "ServerScriptService.Services." .. name
	return server:requirePath(path)
end

function Game.core(server, name: string)
	return server:requirePath("ServerScriptService.Core." .. name)
end

function Game.shared(world, path: string)
	return world:requirePath("ReplicatedStorage.Shared." .. path)
end

function Game.profile(server, player)
	return Game.service(server, "DataService"):GetProfile(player)
end

function Game.data(server, player)
	local profile = Game.profile(server, player)
	return profile and profile.Data
end

-- A player action exactly as the client sends it (or an exploiter could).
function Game.action(ctx, server, player, name: any, payload: any)
	return ctx.harness:exploitInvoke(server, player, "Action", name, payload)
end

function Game.nextRequestId(): string
	requestCounter += 1
	return string.format("req-%08d-test", requestCounter)
end

-- An admin request through the Admin RemoteFunction.
function Game.admin(ctx, server, player, action: string, args: any?, requestId: string?)
	return ctx.harness:exploitInvoke(server, player, "Admin", {
		Action = action,
		Args = args or {},
		RequestId = requestId or Game.nextRequestId(),
	})
end

function Game.command(ctx, server, player, text: string)
	return Game.admin(ctx, server, player, "command", { Text = text })
end

-- Fires n presses spaced so they count as a combo and stay under the rate limit.
function Game.press(ctx, server, player, n: number, spacing: number?)
	for _ = 1, n do
		ctx.harness:exploitFire(server, player, "Click")
		ctx.harness:advance(spacing or 0.1)
	end
	ctx.harness:advance(0.2)
end

-- Grants currency directly (test arrangement only) and syncs it to the client.
function Game.give(server, player, currency: string, amount: number)
	local profile = Game.profile(server, player)
	profile.Data.Currencies[currency] += amount
	Game.service(server, "SyncService"):MarkDirty(profile, "Currencies")
end

function Game.storeKey(userId: number): string
	return "Player_" .. tostring(userId)
end

Game.STORE = "ButtonAscension_PlayerData"

return Game
