--[[
	SecurityService (ModuleScript)
	Location: ServerScriptService/Services/SecurityService

	Records suspicious client behaviour (malformed remote calls, unknown
	actions, click floods, unauthorised admin requests). Flags are kept in a
	bounded in-memory ring buffer that the Admin Panel can display, and are
	written to the server output with rate limiting so a flood cannot spam
	the logs. Nothing here punishes players automatically; admins decide.
]]

local Players = game:GetService("Players")

local MAX_RECENT = 300
local OUTPUT_PER_MINUTE = 6

local SecurityService = {
	Name = "SecurityService",
	Recent = {} :: { any },
	Counts = {} :: { [number]: { [string]: number } },
	TotalFlags = 0,
}

local outputBudget: { [number]: { count: number, windowStart: number } } = {}

function SecurityService:Init(services)
	self.Services = services
	Players.PlayerRemoving:Connect(function(player)
		outputBudget[player.UserId] = nil
	end)
end

local function record(self, player: Player, severity: string, reason: string, detail: any)
	local userId = player.UserId
	local counts = self.Counts[userId]
	if not counts then
		counts = {}
		self.Counts[userId] = counts
	end
	counts[reason] = (counts[reason] or 0) + 1

	if severity == "note" then
		return
	end
	self.TotalFlags += 1
	local entry = {
		Time = os.time(),
		UserId = userId,
		Name = player.Name,
		Reason = reason,
		Detail = string.sub(tostring(detail), 1, 120),
		Count = counts[reason],
	}
	table.insert(self.Recent, entry)
	if #self.Recent > MAX_RECENT then
		table.remove(self.Recent, 1)
	end

	local now = os.clock()
	local budget = outputBudget[userId]
	if not budget or now - budget.windowStart > 60 then
		budget = { count = 0, windowStart = now }
		outputBudget[userId] = budget
	end
	budget.count += 1
	if budget.count <= OUTPUT_PER_MINUTE then
		warn(`[Security] {player.Name} ({userId}) {reason}: {entry.Detail} (x{counts[reason]})`)
	end
end

-- Suspicious behaviour worth an admin's attention.
function SecurityService:Flag(player: Player, reason: string, detail: any?)
	record(self, player, "flag", reason, detail)
end

-- Expected-but-noteworthy behaviour (e.g. a rate-limited request). Counted only.
function SecurityService:Note(player: Player, reason: string, detail: any?)
	record(self, player, "note", reason, detail)
end

function SecurityService:GetRecent(limit: number?)
	local n = math.min(limit or 50, #self.Recent)
	local out = {}
	for i = #self.Recent, #self.Recent - n + 1, -1 do
		table.insert(out, self.Recent[i])
	end
	return out
end

function SecurityService:GetCounts(userId: number)
	return self.Counts[userId] or {}
end

return SecurityService
