--[[
	Net (ModuleScript)
	Location: ServerScriptService/Core/Net
	Depends on: Shared/Remotes, Core/Guard, Core/RateLimiter

	Server networking hub.
	  * Net.registerAction(name, def) registers a handler for the "Action"
	    RemoteFunction. Every call is validated (action name, payload type),
	    rate limited per player and per action, requires a loaded profile and
	    runs inside pcall so a failing handler can never break the remote.
	  * Net.notify / Net.notifyAll send UI notifications.
	  * Net.fire / Net.fireAll send any server -> client RemoteEvent.

	Handlers receive (profile, payload) and return Net.ok({...}) or Net.fail("message").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local Guard = require(script.Parent.Guard)
local RateLimiter = require(script.Parent.RateLimiter)

export type ActionDef = {
	Handler: (profile: any, payload: { [any]: any }) -> { [string]: any }?,
	Rate: { Capacity: number, Refill: number }?,
}

local Net = {}

local services = nil
local actions: { [string]: ActionDef } = {}
local limiters: { [string]: any } = {}
-- Shared budget across every action, so spreading spam over many actions does not help.
local globalLimiter = RateLimiter.new(40, 20)

function Net.ok(t: { [string]: any }?)
	local result = t or {}
	result.ok = true
	return result
end

function Net.fail(message: string, extra: { [string]: any }?)
	local result = extra or {}
	result.ok = false
	result.err = message
	return result
end

function Net.registerAction(name: string, def: ActionDef)
	assert(actions[name] == nil, "Action registered twice: " .. name)
	local rate = def.Rate or { Capacity = 10, Refill = 4 }
	limiters[name] = RateLimiter.new(rate.Capacity, rate.Refill)
	actions[name] = def
end

local function handleAction(player: Player, actionName: any, payload: any)
	local security = services.SecurityService
	if type(actionName) ~= "string" or #actionName > 40 then
		security:Flag(player, "MalformedAction", typeof(actionName))
		return Net.fail("Bad request.")
	end
	local def = actions[actionName]
	if not def then
		security:Flag(player, "UnknownAction", string.sub(actionName, 1, 40))
		return Net.fail("Bad request.")
	end
	local body = Guard.payload(payload)
	if body == nil then
		security:Flag(player, "MalformedPayload", actionName)
		return Net.fail("Bad request.")
	end
	if not globalLimiter:allow(player.UserId) or not limiters[actionName]:allow(player.UserId) then
		security:Note(player, "RateLimited", actionName)
		return Net.fail("You're doing that too fast.", { rateLimited = true })
	end
	local profile = services.DataService:GetProfile(player)
	if not profile then
		return Net.fail("Your data is still loading.")
	end
	local ok, result = pcall(def.Handler, profile, body)
	if not ok then
		warn(`[Net] Action {actionName} failed for {player.Name} ({player.UserId}): {result}`)
		return Net.fail("Something went wrong. Please try again.")
	end
	if type(result) ~= "table" then
		return Net.ok()
	end
	return result
end

function Net.init(serviceTable)
	services = serviceTable
	Remotes.func("Action").OnServerInvoke = handleAction
	Players.PlayerRemoving:Connect(function(player)
		globalLimiter:reset(player.UserId)
		for _, limiter in pairs(limiters) do
			limiter:reset(player.UserId)
		end
	end)
end

function Net.onEvent(name: string, handler: (Player, ...any) -> ())
	Remotes.event(name).OnServerEvent:Connect(function(player, ...)
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(`[Net] Event {name} handler failed for {player.Name}: {err}`)
		end
	end)
end

function Net.fire(player: Player, name: string, ...: any)
	if player.Parent == Players then
		Remotes.event(name):FireClient(player, ...)
	end
end

function Net.fireAll(name: string, ...: any)
	Remotes.event(name):FireAllClients(...)
end

--[[
	Notification kinds understood by the client (Notifications controller):
	  Toast        { Text, Icon?, Color? }
	  Error        { Text }
	  LevelUp      { Level, SkillPoints, Chest? }
	  Discovery    { Item }
	  Achievement  { Id }
	  Announcement { Text, From, Scope }
	  Event        { Id, Started, EndsAt }
	  Reward       { Title, Text }
	  Stage        { Stage }
	  Offline      { Amount, Seconds }
	  Warning      { Text }
	  Rare         { Player, Item }
]]
function Net.notify(player: Player, kind: string, data: { [string]: any }?)
	Net.fire(player, "Notify", kind, data or {})
end

function Net.notifyAll(kind: string, data: { [string]: any }?)
	Net.fireAll("Notify", kind, data or {})
end

return Net
