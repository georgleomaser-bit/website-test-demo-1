-- Latest player state from the server plus a Changed signal for the UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local State = {
	Data = nil,
	Derived = nil,
	ServerOffset = 0, -- server os.time() - local os.time()
}

local changed = Instance.new("BindableEvent")
local statsChanged = Instance.new("BindableEvent")
State.Changed = changed.Event -- full state arrived
State.StatsChanged = statsChanged.Event -- Speed / Cash / task progress changed

function State.now(): number
	return os.time() + State.ServerOffset
end

function State.ready(): boolean
	return State.Data ~= nil
end

function State.action(name: string, ...): (boolean, string?)
	local ok, success, message = pcall(function(...)
		return Remotes.Action:InvokeServer(name, ...)
	end, ...)
	if not ok then
		return false, "Connection problem"
	end
	return success, message
end

Remotes.State.OnClientEvent:Connect(function(state)
	State.Data = state.Data
	State.Derived = state.Derived
	State.ServerOffset = state.Derived.Now - os.time()
	changed:Fire()
	statsChanged:Fire()
end)

Remotes.Stats.OnClientEvent:Connect(function(stats)
	if not State.Data then
		return
	end
	State.Data.Speed = stats.Speed
	State.Data.Cash = stats.Cash
	if stats.Tasks then
		State.Data.Tasks.List = stats.Tasks
	end
	statsChanged:Fire()
end)

return State
