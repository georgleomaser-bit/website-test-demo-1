--[[
	ClientNet (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/ClientNet
	Depends on: ReplicatedStorage/Shared/Remotes

	Thin wrapper around the remotes. Actions only send intent (which upgrade,
	which crate, how many); the server computes and validates everything.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local ClientNet = {}

local actionRemote = Remotes.func("Action")
local clickRemote = Remotes.event("Click")
local inFlight: { [string]: boolean } = {}

-- Invokes a server action. Never throws; returns { ok, err?, ... }.
function ClientNet.action(name: string, payload: { [string]: any }?): { [string]: any }
	local ok, result = pcall(function()
		return actionRemote:InvokeServer(name, payload or {})
	end)
	if not ok then
		return { ok = false, err = "Connection problem. Please try again." }
	end
	if type(result) ~= "table" then
		return { ok = false, err = "Unexpected response from the server." }
	end
	return result
end

-- Like action(), but ignores a second call while the first is still running
-- (prevents double purchases from double taps).
function ClientNet.once(key: string, name: string, payload: { [string]: any }?): { [string]: any }?
	if inFlight[key] then
		return nil
	end
	inFlight[key] = true
	local result = ClientNet.action(name, payload)
	inFlight[key] = nil
	return result
end

function ClientNet.click()
	clickRemote:FireServer()
end

function ClientNet.on(eventName: string, handler: (...any) -> ()): RBXScriptConnection
	return Remotes.event(eventName).OnClientEvent:Connect(handler)
end

return ClientNet
