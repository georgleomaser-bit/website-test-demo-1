--[[
	RemoteEvents zwischen Server und Client.
	Der Server legt sie an, der Client wartet darauf.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local NAMES = {
	"Action", -- Client -> Server: (actionName, ...)
	"Sync", -- Server -> Client: Profil-Daten + berechnete Werte
	"Notify", -- Server -> Client: (text, style)
	"Effect", -- Server -> Client: (kind, data)
}

local folder: Folder

function Remotes.Init()
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild("Remotes")
		if existing then
			folder = existing :: Folder
		else
			folder = Instance.new("Folder")
			folder.Name = "Remotes"
			folder.Parent = ReplicatedStorage
		end
		for _, name in ipairs(NAMES) do
			if not folder:FindFirstChild(name) then
				local remote = Instance.new("RemoteEvent")
				remote.Name = name
				remote.Parent = folder
			end
		end
	else
		folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
		for _, name in ipairs(NAMES) do
			folder:WaitForChild(name)
		end
	end
end

function Remotes.Get(name: string): RemoteEvent
	if not folder then
		Remotes.Init()
	end
	return folder:FindFirstChild(name) :: RemoteEvent
end

return Remotes
