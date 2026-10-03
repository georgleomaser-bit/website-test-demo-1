-- Erstellt alle RemoteEvents/RemoteFunctions in ReplicatedStorage.Remotes
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:FindFirstChild("Remotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
end

local function make(className: string, name: string)
	local existing = folder:FindFirstChild(name)
	if existing then
		return existing
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = folder
	return remote
end

return {
	Notify = make("RemoteEvent", "Notify") :: RemoteEvent, -- Server -> Client: Toast-Nachricht
	State = make("RemoteEvent", "State") :: RemoteEvent, -- Server -> Client: Cash, Einkommen, ...
	Effect = make("RemoteEvent", "Effect") :: RemoteEvent, -- Server -> Client: Effekte (Kamera-Wackeln etc.)
	Request = make("RemoteFunction", "Request") :: RemoteFunction, -- Client -> Server: Rebirth, Speed, Daily
	Admin = make("RemoteFunction", "Admin") :: RemoteFunction, -- Client -> Server: Admin-Aktionen (geprüft!)
}
