--[[
	RateLimiter (ModuleScript)
	Location: ServerScriptService/Core/RateLimiter

	Token-bucket rate limiter keyed by any value (usually a UserId or a
	"UserId:action" string). Each bucket holds up to `capacity` tokens and
	refills at `refillPerSecond`. A request that cannot take a token is denied.
]]

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable(
	{} :: { capacity: number, refill: number, buckets: { [any]: { tokens: number, last: number } } },
	RateLimiter
))

function RateLimiter.new(capacity: number, refillPerSecond: number): RateLimiter
	return setmetatable({
		capacity = capacity,
		refill = refillPerSecond,
		buckets = {},
	}, RateLimiter)
end

function RateLimiter:allow(key: any, cost: number?): boolean
	local now = os.clock()
	local bucket = self.buckets[key]
	if not bucket then
		bucket = { tokens = self.capacity, last = now }
		self.buckets[key] = bucket
	else
		local elapsed = now - bucket.last
		bucket.tokens = math.min(self.capacity, bucket.tokens + elapsed * self.refill)
		bucket.last = now
	end
	local need = cost or 1
	if bucket.tokens >= need then
		bucket.tokens -= need
		return true
	end
	return false
end

-- Remaining tokens (after refill) without consuming any.
function RateLimiter:peek(key: any): number
	local bucket = self.buckets[key]
	if not bucket then
		return self.capacity
	end
	local elapsed = os.clock() - bucket.last
	return math.min(self.capacity, bucket.tokens + elapsed * self.refill)
end

function RateLimiter:reset(key: any)
	self.buckets[key] = nil
end

return RateLimiter
