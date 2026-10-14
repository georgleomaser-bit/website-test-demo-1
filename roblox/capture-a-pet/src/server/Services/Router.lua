-- Single entry point for client requests (Remotes.Action). Every handler validates its own
-- arguments; the router adds rate limiting and error isolation.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local Router = {}

local handlers = {}
local buckets = {} -- [player] = { tokens, last }

local MAX_TOKENS = 25
local REFILL_PER_SECOND = 12

local function allow(player: Player): boolean
	local now = os.clock()
	local bucket = buckets[player]
	if not bucket then
		bucket = { Tokens = MAX_TOKENS, Last = now }
		buckets[player] = bucket
	end
	bucket.Tokens = math.min(MAX_TOKENS, bucket.Tokens + (now - bucket.Last) * REFILL_PER_SECOND)
	bucket.Last = now
	if bucket.Tokens < 1 then
		return false
	end
	bucket.Tokens -= 1
	return true
end

function Router.register(name: string, handler)
	assert(handlers[name] == nil, "duplicate action " .. name)
	handlers[name] = handler
end

function Router.Init(services)
	Router.Services = services
end

function Router.Start()
	local DataService = Router.Services.DataService
	Remotes.Action.OnServerInvoke = function(player: Player, name, ...)
		if type(name) ~= "string" then
			return false, "Bad request"
		end
		local handler = handlers[name]
		if not handler then
			return false, "Unknown action"
		end
		if not allow(player) then
			return false, "Slow down!"
		end
		if not DataService.isLoaded(player) then
			return false, "Still loading..."
		end
		local ok, success, message = pcall(handler, player, ...)
		if not ok then
			warn("[Router] action", name, "failed:", success)
			return false, "Something went wrong"
		end
		return success == true, message
	end
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

return Router
