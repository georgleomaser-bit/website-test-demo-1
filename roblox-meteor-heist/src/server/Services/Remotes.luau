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
	-- Server -> Client: Effekte (name, strength, data) – z.B. "Shake", "Steps", "Deliver", "Hatch",
	-- "FloorBuilt"/"LookUpgrade" (Modul Base), "RaceStart" (Effects + NestField), "Run…" (MeteorRun), "NightCrate" (Night)
	Effect = make("RemoteEvent", "Effect") :: RemoteEvent,
	-- Client -> Server: "Rebirth", "Daily", "Collect", "Home", "Treadmills", "BuyTreadmill", "BuyGadget",
	-- "BuyFloor", "BuyBaseLook", "GoRun", "ClaimGift", "Spin", "ClaimQuest", "RerollQuest"
	Request = make("RemoteFunction", "Request") :: RemoteFunction,
	Admin = make("RemoteFunction", "Admin") :: RemoteFunction, -- Client -> Server: Admin-Aktionen (geprüft!)
	-- 🤝 Handel (TradeService): Client -> Server (Aktion, Wert) / Server -> Client (Art, Daten)
	Trade = make("RemoteFunction", "Trade") :: RemoteFunction,
	TradeEvent = make("RemoteEvent", "TradeEvent") :: RemoteEvent,
}
