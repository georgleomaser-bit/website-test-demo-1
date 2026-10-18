--[[
	Remotes (ModuleScript)
	Location: ReplicatedStorage/Shared/Remotes

	Single source of truth for every RemoteEvent / RemoteFunction.
	The server calls Remotes.init() once at startup, which creates
	ReplicatedStorage/Remotes and ReplicatedStorage/ServerState. Clients use
	Remotes.event(name) / Remotes.func(name), which wait for the instance.

	Direction and responsibility:
	  Click        (client -> server)  a manual press. No arguments are trusted.
	  ClickResult  (server -> client)  result of a press for effects/floaters.
	  StateSync    (server -> client)  full snapshot or partial patch of the player's own data.
	  Notify       (server -> client)  toasts, discoveries, announcements, level ups.
	  OrbSpawn     (server -> client)  a bonus orb the player may claim.
	  AdminPush    (server -> admin)   live updates for the admin panel (admins only).
	  Action       (client -> server)  RemoteFunction for every player action (validated, rate limited).
	  Admin        (client -> server)  RemoteFunction for admin requests (permission checked per call).

	The server never calls InvokeClient.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

Remotes.FolderName = "Remotes"
Remotes.StateFolderName = "ServerState"

Remotes.Events = {
	Click = "Click",
	ClickResult = "ClickResult",
	StateSync = "StateSync",
	Notify = "Notify",
	OrbSpawn = "OrbSpawn",
	AdminPush = "AdminPush",
}

Remotes.Functions = {
	Action = "Action",
	Admin = "Admin",
}

local function getFolder(): Folder
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(Remotes.FolderName)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = Remotes.FolderName
			folder.Parent = ReplicatedStorage
		end
		return folder :: Folder
	end
	local folder = ReplicatedStorage:WaitForChild(Remotes.FolderName, 60)
	assert(folder, "Remotes folder did not replicate. Is the server running Main?")
	return folder :: Folder
end

-- Server only: creates every remote and the ServerState folder. Idempotent.
function Remotes.init()
	assert(RunService:IsServer(), "Remotes.init must be called on the server")
	local folder = getFolder()
	for _, name in pairs(Remotes.Events) do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	for _, name in pairs(Remotes.Functions) do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
	end
	if not ReplicatedStorage:FindFirstChild(Remotes.StateFolderName) then
		local state = Instance.new("Folder")
		state.Name = Remotes.StateFolderName
		state.Parent = ReplicatedStorage
	end
end

function Remotes.event(name: string): RemoteEvent
	assert(Remotes.Events[name], "Unknown RemoteEvent " .. tostring(name))
	local folder = getFolder()
	local remote = if RunService:IsServer() then folder:FindFirstChild(name) else folder:WaitForChild(name, 60)
	assert(remote and remote:IsA("RemoteEvent"), "RemoteEvent missing: " .. name)
	return remote :: RemoteEvent
end

function Remotes.func(name: string): RemoteFunction
	assert(Remotes.Functions[name], "Unknown RemoteFunction " .. tostring(name))
	local folder = getFolder()
	local remote = if RunService:IsServer() then folder:FindFirstChild(name) else folder:WaitForChild(name, 60)
	assert(remote and remote:IsA("RemoteFunction"), "RemoteFunction missing: " .. name)
	return remote :: RemoteFunction
end

-- Folder whose attributes hold replicated server-wide state (events, server CPS).
function Remotes.serverState(): Folder
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(Remotes.StateFolderName)
		assert(folder, "Remotes.init has not run")
		return folder :: Folder
	end
	local folder = ReplicatedStorage:WaitForChild(Remotes.StateFolderName, 60)
	assert(folder, "ServerState did not replicate")
	return folder :: Folder
end

return Remotes
