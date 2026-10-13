-- =====================================================================
--  AKYTEX TYCOON – Alle Remotes (Server/Services/Remotes)
--  Besitzer: WP1 (Kern & Plattform). Vertrag: DESIGN.md §C5.2 + §C8 (CC-Kopie 1:1, neue Felderliste).
--  Erstellt idempotent jedes Remote aus Net.RemoteList unter ReplicatedStorage.Remotes. Kein Service
--  (steht nicht in der Lader-Reihenfolge; Main.server lädt es ZUERST, Clients warten darauf):
--    local Remotes = require(script.Parent:WaitForChild("Remotes"))
--    Remotes.Market:FireAllClients(kind, data)     -- getypte Felder je Remote
--    Remotes[name]                                  -- dynamisch
--  "GrantCash" ist ein Honeypot: hier nur erzeugt, den Handler setzt WP11 (AntiCheatService). Unser Code feuert ihn NIE.
--  Falsche Klasse unter dem Namen -> warn + ersetzen; falsches Objekt "Remotes" -> in "Remotes_Alt" umbenennen.
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

export type Remotes = {
	Notify: RemoteEvent,
	State: RemoteEvent,
	Effect: RemoteEvent,
	Request: RemoteFunction,
	Admin: RemoteFunction,
	MarketFrame: RemoteEvent,
	Market: RemoteEvent,
	World: RemoteEvent,
	Replay: RemoteEvent,
	GrantCash: RemoteEvent,
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
