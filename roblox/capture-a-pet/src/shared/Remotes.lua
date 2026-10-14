-- Creates (server) or waits for (client) every remote in one folder.
--
-- Client -> server
--   Action (RemoteFunction)  Action:InvokeServer(name, ...) -> (ok: boolean, message: string?)
-- Server -> client
--   State      full player state (save data + derived numbers), sent when something changes
--   Stats      small, frequent update: Speed, Cash
--   Notify     (text, kind) toast message
--   Hatched    (animalRecord) play the hatch reveal
--   Alarm      (info) someone is stealing your animal / your theft got stopped
--   Effect     (name, data) one-off visual effects (bait landed, guard caught you, ...)
--   Announce   (text, color) server-wide message (rare spawn, rare hatch)
--   Admin      (payload) admin panel data

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FUNCTIONS = { "Action" }
local EVENTS = { "State", "Stats", "Notify", "Hatched", "Alarm", "Effect", "Announce", "Admin" }

local Remotes = {}

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for _, name in ipairs(FUNCTIONS) do
		if not folder:FindFirstChild(name) then
			local f = Instance.new("RemoteFunction")
			f.Name = name
			f.Parent = folder
		end
	end
	for _, name in ipairs(EVENTS) do
		if not folder:FindFirstChild(name) then
			local e = Instance.new("RemoteEvent")
			e.Name = name
			e.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

for _, name in ipairs(FUNCTIONS) do
	Remotes[name] = folder:WaitForChild(name)
end
for _, name in ipairs(EVENTS) do
	Remotes[name] = folder:WaitForChild(name)
end

return Remotes
