-- =====================================================================
--  CLUTCH CLASH – Selbsttests Welt (Server/Tests/WorldTests)
--  Besitzer: WP2 (Welt). Vertrag: DESIGN.md D/WP2 (Tests), C18 (SelfTest-Pflichten), B8, B9.
--  Gibt { [testName]: (Services) -> () } zurück; jeder Fehler = FAIL (SelfTestService, WP1).
--  Prüft je Map: Teilebudget, Spawn-Freiheit (Box 2×5×2 über jedem Spawn trifft nichts),
--  Nav-Erreichbarkeit (BFS, Zone + alle Spawns), Punktsymmetrie (gespiegelte Teilemittelpunkte);
--  dazu Lobby ≤ 2.500 Teile, Acquire/Release-Zyklus (warmer Slot, 9. Acquire -> nil), MapsFor, Stimmungen.
--  Prüf-Builds stehen kurz bei (0, 6000, 0) im Workspace und werden danach zerstört.
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local World = script.Parent.Parent:WaitForChild("World")
local MapKit = require(World:WaitForChild("MapKit"))
local NavBuilder = require(World:WaitForChild("NavBuilder"))
local LobbyLayout = require(World:WaitForChild("LobbyLayout"))

local TEST_ORIGIN = CFrame.new(0, 6000, 0)
local SPAWN_BOX = Vector3.new(1.98, 5, 1.98)
local SYMMETRY_TOLERANCE = 0.05

local function check(condition: any, message: string)
	if not condition then
		error(message, 2)
	end
end

local function arenaService(services: any): any
	local service = services and services.ArenaService
	check(service ~= nil, "ArenaService fehlt")
	return service
end

local function mapKeys(): { string }
	local keys: { string } = {}
	for key in pairs(Config.Maps.Maps or {}) do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

-- Map frisch bauen und an TEST_ORIGIN in den Workspace stellen; fn(model, layout); danach aufräumen
local function withEachMap(services: any, fn: (model: Model, layout: any, info: any) -> ())
	local service = arenaService(services)
	local failures: { string } = {}
	for _, key in ipairs(mapKeys()) do
		local layout = service.Layout(key)
		if not layout then
			table.insert(failures, key .. ": Layout fehlt")
			continue
		end
		local model, info = MapKit.Build(layout)
		model:PivotTo(TEST_ORIGIN)
		model.Parent = workspace
		local ok, err = pcall(fn, model, layout, info)
		model:Destroy()
		if not ok then
			table.insert(failures, key .. ": " .. tostring(err))
		end
	end
	check(#failures == 0, table.concat(failures, " | "))
end

local tests = {}

-- Jede Map baut fehlerfrei und hält ihr Teilebudget (S ≤ 700, M ≤ 900, L ≤ 1.100, Crown ≤ 400)
tests.MapPartBudgets = function(services: any)
	withEachMap(services, function(_model, layout, info)
		check(info.Parts > 0, "keine Teile")
		check(not info.OverBudget, ("%d Teile > Budget %d"):format(info.Parts, info.Budget))
		check(not info.TooMuchNeon, ("%d Neon-Teile > %d"):format(info.Neon, info.NeonLimit))
		check(#layout.SpawnsA >= 1, "keine Spawns")
	end)
end

-- Ray-Box 2×5×2 über jedem Spawn (A, B, FFA) berührt kein kollidierendes Teil
tests.SpawnsFree = function(services: any)
	withEachMap(services, function(model, layout)
		local blocked = NavBuilder.SpawnBlockers(model, layout, TEST_ORIGIN, SPAWN_BOX)
		check(#blocked == 0, "blockiert: " .. table.concat(blocked, ", "))
	end)
end

-- Punktsymmetrie: zu jedem Teilemittelpunkt (x, y, z) gibt es ein Teil bei (−x, y, −z)
tests.MapSymmetry = function(services: any)
	withEachMap(services, function(model)
		local centers: { [string]: number } = {}
		local list: { Vector3 } = {}
		local function key(v: Vector3): string
			return ("%d|%d|%d"):format(
				math.floor(v.X / SYMMETRY_TOLERANCE + 0.5),
				math.floor(v.Y / SYMMETRY_TOLERANCE + 0.5),
				math.floor(v.Z / SYMMETRY_TOLERANCE + 0.5)
			)
		end
		for _, inst in ipairs(model:GetDescendants()) do
			if inst:IsA("BasePart") then
				local p = TEST_ORIGIN:PointToObjectSpace(inst.Position)
				table.insert(list, p)
				local k = key(p)
				centers[k] = (centers[k] or 0) + 1
			end
		end
		local missing = 0
		local example = ""
		for _, p in ipairs(list) do
			if not centers[key(Vector3.new(-p.X, p.Y, -p.Z))] then
				missing += 1
				if example == "" then
					example = tostring(p)
				end
			end
		end
		check(missing == 0, ("%d Teile ohne Spiegel-Partner (z. B. %s)"):format(missing, example))
	end)
end

-- Nav-Graph zusammenhängend, Zone und alle Spawns erreichbar (BFS)
tests.NavReachable = function(services: any)
	withEachMap(services, function(model, layout)
		local nav, report = NavBuilder.Build(model, layout, TEST_ORIGIN)
		check(#nav.Nodes > 0, "Nav-Graph leer")
		check(#nav.Nodes <= math.max(300, tonumber(Config.Maps.Nav.MaxNodes) or 300), "zu viele Knoten")
		local reached = NavBuilder.Reachable(nav, 1)
		local count = 0
		for _ in pairs(reached) do
			count += 1
		end
		check(count == #nav.Nodes, ("nicht zusammenhängend: %d/%d"):format(count, #nav.Nodes))
		check(report.ZoneOk, "Zone nicht erreichbar")
		check(report.SpawnsOk, "Spawns ohne Nav-Anschluss: " .. table.concat(report.BadSpawns, ", "))
		local cover = 0
		for _, node in ipairs(nav.Nodes) do
			if node.Cover then
				cover += 1
			end
		end
		check(cover >= 1, "keine erreichbaren Deckungs-Knoten")
	end)
end

-- Template-Graphen (Boot) sind ebenfalls zusammenhängend
tests.TemplateNav = function(services: any)
	local service = arenaService(services)
	for _, key in ipairs(mapKeys()) do
		local def = Config.Maps.Maps[key]
		if not def.Fixed then
			local template = service.Template(key)
			check(template ~= nil, key .. ": Template fehlt")
			check(#template.Nav.Nodes > 0, key .. ": Template-Nav leer")
			local sizes = NavBuilder.Components(template.Nav)
			check(#sizes == 1, key .. ": Template-Nav hat " .. #sizes .. " Komponenten")
		end
	end
	local crown = service.Crown()
	check(crown.Slot == 0 and crown.Key == "CrownRing", "Crown-Arena falsch")
	check(#crown.Nav.Nodes > 0, "Crown-Nav leer")
	check(crown.Model.Parent ~= nil, "Crown Ring nicht in der Welt")
end

-- Lobby ≤ 2.500 Teile inkl. Crown Ring (≤ 400) und Range (≤ 400)
tests.LobbyBudget = function(services: any)
	local lobby = workspace:FindFirstChild(LobbyLayout.FolderName)
	check(lobby ~= nil, "workspace.Lobby fehlt")
	local parts = MapKit.Count(lobby :: Instance)
	local crownParts = MapKit.Count(arenaService(services).Crown().Model)
	local range = (lobby :: Instance):FindFirstChild(LobbyLayout.RangeName)
	check(range ~= nil, "Range fehlt")
	local rangeParts = MapKit.Count(range :: Instance)
	check(crownParts <= 400, "Crown Ring hat " .. crownParts .. " Teile")
	check(rangeParts <= 400, "Range hat " .. rangeParts .. " Teile")
	check(parts + crownParts <= LobbyLayout.PartBudget, ("Lobby hat %d Teile"):format(parts + crownParts))
end

-- Lobby-API liefert alles, was andere Pakete brauchen
tests.LobbyApi = function(services: any)
	local lobby = services and services.LobbyBuilder
	check(lobby ~= nil, "LobbyBuilder fehlt")
	local pads = lobby.Pads()
	check(#pads == 9, "9 Pads erwartet, " .. #pads .. " gefunden")
	for _, pad in ipairs(pads) do
		check(pad.Part:GetAttribute("Mode") == pad.Mode, "Pad " .. pad.Id .. ": Attribut Mode")
		check(pad.Part:GetAttribute("PadId") == pad.Id, "Pad " .. pad.Id .. ": Attribut PadId")
		if pad.Mode == "FFA" then
			check(#pad.SeatsA == 8 and #pad.SeatsB == 0, "FFA-Pad: 8 Sitze in SeatsA")
		else
			check(#pad.SeatsA == #pad.SeatsB and #pad.SeatsA >= 1, "Pad " .. pad.Id .. ": Sitze A/B")
		end
	end
	check(#lobby.CrownLine() == 6, "6 Herausforderer-Kreise erwartet")
	check(#lobby.RangeDummySpots() == 26, "26 Puppen-Plätze erwartet")
	check(#lobby.BotBooth() == 4, "4 Bot-Kabinen-Pads erwartet")
	local boards = lobby.Boards()
	for _, key in ipairs(LobbyLayout.BoardKeys) do
		local board = boards[key]
		check(board ~= nil, "Tafel " .. key .. " fehlt")
		local gui = board:FindFirstChild("Board")
		check(gui ~= nil and gui:FindFirstChild("Row10") ~= nil, "Tafel " .. key .. ": SurfaceGui Board/Row1..10")
	end
	local king = lobby.CrownBoard():FindFirstChild("KingBoard")
	check(king ~= nil, "Königs-Tafel: SurfaceGui fehlt")
	for _, name in ipairs({ "Avatar", "Name", "Streak" }) do
		check(king:FindFirstChild(name) ~= nil, "Königs-Tafel: " .. name .. " fehlt")
	end
	check(lobby.CrateMachine().Name == "CrateMachine", "Kisten-Automat fehlt")
	local zoneCf, zoneSize = lobby.RangeZone()
	check(zoneSize.X > 100 and zoneSize.Z > 100, "Range-Zone zu klein")
	check(math.abs(zoneCf.X + 131) < 0.01, "Range-Zone Mitte X −131 erwartet")
	local _, vipSize = lobby.VipZone()
	check(vipSize.X == 40 and vipSize.Z == 24, "VIP-Zone 40×24 erwartet")
	local door = workspace:FindFirstChild("VipDoor", true)
	check(door ~= nil and door:IsA("BasePart") and door.CanCollide, "VipDoor fehlt oder ist offen")
end

-- Acquire/Release: warmer Slot ohne Neubau; 9. Acquire bei 8 belegten -> nil; Aufräumen-Zustände
tests.AcquireReleaseCycle = function(services: any)
	local service = arenaService(services)
	local key = "PillarBox"
	local first = service.Acquire(key)
	check(first ~= nil, "Acquire " .. key .. " lieferte nil (Slots belegt?)")
	check(first.Slot >= 1 and first.Slot <= 8, "Slot außerhalb 1..8")
	check(first.Model.Parent ~= nil, "Map nicht geparentet")
	check(first.Model:GetAttribute("BuildId") == first.BuildId, "BuildId-Attribut fehlt")
	check(#first.Spawns.A >= 1 and #first.Spawns.B == #first.Spawns.A, "Spawns A/B")
	check(first.MapParams ~= nil and first.Vault ~= nil, "MapParams/Vault fehlen")
	service.Release(first)
	local again = service.Acquire(key)
	check(again ~= nil, "zweites Acquire nil")
	check(again.Slot == first.Slot and again.BuildId == first.BuildId, "warmer Slot wurde nicht wiederverwendet")
	service.Release(again)

	-- Alle freien Slots belegen (synchron, ohne Yield), dann muss Acquire nil liefern
	local taken = {}
	for _ = 1, 8 do
		local arena = service.Acquire(key)
		if not arena then
			break
		end
		table.insert(taken, arena)
	end
	local overflow = service.Acquire(key)
	local free = service.FreeSlots()
	for _, arena in ipairs(taken) do
		service.Release(arena)
	end
	if overflow then
		service.Release(overflow)
	end
	check(overflow == nil, "Acquire bei vollen Slots lieferte eine Arena")
	check(free == 0, "FreeSlots() bei vollen Slots = " .. free)
	local states = service.SlotStates()
	check(#states == 8, "8 Slot-Zustände erwartet")
end

-- MapsFor: Modi und Teamgrößen aus Config.Maps (B8.3)
tests.MapsFor = function(services: any)
	local service = arenaService(services)
	local function same(list: { string }, expected: { string }, label: string)
		check(table.concat(list, ",") == table.concat(expected, ","), label .. ": " .. table.concat(list, ","))
	end
	same(service.MapsFor("Duel1", 1), { "BlockYard", "NeonGrid", "PillarBox", "SkyGarden" }, "Duel1")
	same(service.MapsFor("Duel4", 4), { "BlockYard", "CandyDocks", "SnowFort" }, "Duel4")
	same(service.MapsFor("FFA", 0), { "BlockYard", "CandyDocks", "NeonGrid", "SkyGarden" }, "FFA")
	same(service.MapsFor("Crown", 1), { "CrownRing" }, "Crown")
	check(#service.MapsFor("Unbekannt", 1) == 0, "unbekannter Modus")
	local cf = service.LobbySpawn()
	check(typeof(cf) == "CFrame" and cf.Y > 0, "LobbySpawn")
	local range = service.Range()
	check(range.Key == "Range" and #range.Spawns.A == 0, "Range-Arena")
end

-- Stimmungen vollständig, Atmosphere-Dichte ≥ 0.32, Config.Maps.Validate leer
tests.MoodsValid = function()
	local errors = Config.Maps.Validate(Config)
	check(#errors == 0, table.concat(errors, " | "))
	for _, key in ipairs({ "Day", "Sunset", "NeonNight", "Fog", "Snowy" }) do
		local mood = Config.Maps.Moods[key]
		check(mood ~= nil, "Stimmung " .. key .. " fehlt")
		check(mood.Atmosphere.Density >= 0.32, key .. ": Dichte < 0.32")
	end
	check(Config.Maps.Moods.Snowy.Snow == true, "Snowy ohne Schnee")
end

return tests
