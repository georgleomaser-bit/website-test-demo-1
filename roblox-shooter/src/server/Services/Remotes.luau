-- =====================================================================
--  CLUTCH CLASH – Alle Remotes (Server/Services/Remotes)
--  Besitzer: WP1 (Core & Plattform). Vertrag: DESIGN.md C5.2 + C8.
--  Erstellt idempotent jedes Remote aus Net.RemoteList unter ReplicatedStorage.Remotes
--  (MH-Muster make(className, name)). Kein Service (steht nicht in der Lader-Reihenfolge):
--    local Remotes = require(script.Parent:WaitForChild("Remotes"))
--    Remotes.Fire.OnServerEvent:Connect(...)     -- getypte Felder je Remote
--    Remotes[name]                               -- dynamisch (z. B. ReplicationService.FireCtx)
--  "GrantCoins" ist ein Honeypot: hier nur erzeugt, den Handler setzt WP7 (AntiCheatService).
--  Unser Code feuert ihn NIE.
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

export type Remotes = {
	Notify: RemoteEvent,
	State: RemoteEvent,
	Effect: RemoteEvent,
	Request: RemoteFunction,
	Admin: RemoteFunction,
	Match: RemoteEvent,
	Combat: RemoteEvent,
	Fire: RemoteEvent,
	WeaponAction: RemoteEvent,
	Look: UnreliableRemoteEvent,
	LookBatch: UnreliableRemoteEvent,
	FX: UnreliableRemoteEvent,
	GrantCoins: RemoteEvent,
	[string]: any,
}

local folder = ReplicatedStorage:FindFirstChild("Remotes")
if folder and not folder:IsA("Folder") then
	-- falsches Objekt mit dem Namen (z. B. von Hand angelegt) -> umbenennen statt Fehler
	folder.Name = "Remotes_Alt"
	folder = nil
end
if not folder then
	local created = Instance.new("Folder")
	created.Name = "Remotes"
	created.Parent = ReplicatedStorage
	folder = created
end

local function make(className: string, name: string): Instance
	local existing = (folder :: Instance):FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	elseif existing then
		warn(
			("[Remotes] %s hat die falsche Klasse (%s statt %s) – wird ersetzt"):format(
				name,
				existing.ClassName,
				className
			)
		)
		existing:Destroy()
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = folder
	return remote
end

local remotes: { [string]: any } = {}
for _, spec in ipairs(Net.RemoteList) do
	remotes[spec.Name] = make(spec.Class, spec.Name)
end

return (remotes :: any) :: Remotes
