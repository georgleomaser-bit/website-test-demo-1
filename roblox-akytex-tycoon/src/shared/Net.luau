--!strict
-- =====================================================================
--  AKYTEX TYCOON – Netzwerk: Remote-Liste (Shared/Net)
--  Besitzer: WP1 (Kern & Plattform). Vertrag: DESIGN.md §C6.1 + §C8 (CC-Muster, ohne Look/FX-Codecs –
--  die Markt-Buffer kodiert WP3 in Shared/Market/QuoteCodec).
--
--  Öffentliche API:
--    Net.RemoteList                             alle Remotes { Name, Class } (Server erzeugt sie: Services/Remotes)
--    Net.GetRemotes(): { [string]: Instance }   Client: ReplicatedStorage.Remotes, WaitForChild je Name ≤ 10 s,
--                                               gecacht NUR wenn vollständig (sonst beim nächsten Aufruf erneut)
--    Net.Has(name): boolean                     steht der Name in der Liste?
--  Remotes werden auf dem Client erst NACH Init+Start aller Module verbunden (§C7.1).
-- =====================================================================

local Net = {}

export type RemoteClass = "RemoteEvent" | "RemoteFunction" | "UnreliableRemoteEvent"
export type RemoteSpec = { Name: string, Class: RemoteClass }

-- ---------------------------------------------------------------------
-- 1) REMOTES (§C8) – Reihenfolge egal, Namen sind der Vertrag
-- ---------------------------------------------------------------------
Net.RemoteList = {
	{ Name = "Notify", Class = "RemoteEvent" }, -- S→C (text ≤ 500, kind) – bereits lokalisiert
	{ Name = "State", Class = "RemoteEvent" }, -- S→C (partial, full) – Sticky-Merge, Flush 0,2 s, voll alle 20 s
	{ Name = "Effect", Class = "RemoteEvent" }, -- S→C (name, strength, data?) – Name aus §C7.4
	{ Name = "Request", Class = "RemoteFunction" }, -- C→S (action, arg?) → Reply (§C9), global 8/s
	{ Name = "Admin", Class = "RemoteFunction" }, -- C→S (action, args?) → {Ok, Message, Data}, 12/s VOR der Prüfung
	{ Name = "MarketFrame", Class = "RemoteEvent" }, -- S→C buffer 9 + 10·n Byte, 1 Hz, zuverlässig (MARKET §10.2)
	{ Name = "Market", Class = "RemoteEvent" }, -- S→C (kind, data): News, Event, Halt, Bell, Ipo, Calendar, DayClose
	{ Name = "World", Class = "RemoteEvent" }, -- S→C (kind, data): Pickups, PickupGone, Event, Bear, Parade
	{ Name = "Replay", Class = "RemoteEvent" }, -- S→C buffer 9 Byte (Tutorial-ACAD an einen Spieler)
	{ Name = "GrantCash", Class = "RemoteEvent" }, -- Honeypot – unser Code feuert ihn NIE (WP11 setzt den Handler)
} :: { RemoteSpec }

local REMOTE_WAIT = 10
local cachedRemotes: { [string]: Instance }? = nil

local byName: { [string]: RemoteSpec } = {}
for _, spec in ipairs(Net.RemoteList) do
	assert(byName[spec.Name] == nil, "[Net] Doppelter Remote-Name: " .. spec.Name)
	byName[spec.Name] = spec
end

function Net.Has(name: string): boolean
	return type(name) == "string" and byName[name] ~= nil
end

-- Alle Remotes als Tabelle Name -> Instanz. Wartet je Name höchstens 10 s (fehlende -> warn, ausgelassen).
-- Yieldet beim ersten Aufruf auf dem Client – nur aus Init/Start bzw. eigenen Threads aufrufen.
function Net.GetRemotes(): { [string]: Instance }
	if cachedRemotes then
		return cachedRemotes
	end
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local result: { [string]: Instance } = {}
	local folder = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage:WaitForChild("Remotes", REMOTE_WAIT)
	if not folder then
		warn("[Net] Ordner ReplicatedStorage.Remotes fehlt")
		return result
	end
	local complete = true
	for _, spec in ipairs(Net.RemoteList) do
		local remote = folder:FindFirstChild(spec.Name) or folder:WaitForChild(spec.Name, REMOTE_WAIT)
		if remote and remote:IsA(spec.Class) then
			result[spec.Name] = remote
		else
			complete = false
			warn("[Net] Remote fehlt: " .. spec.Name .. " (" .. spec.Class .. ")")
		end
	end
	if complete then
		cachedRemotes = result -- nur vollständige Ergebnisse merken (sonst später nochmal versuchen)
	end
	return result
end

return Net
