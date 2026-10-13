-- =====================================================================
--  AKYTEX TYCOON – Bauplätze, Besuche, Aufzug (Server/Services/PlotService)
--  Besitzer: WP6 (Turm-Ökonomie). Vertrag: DESIGN.md §C5.5 (PlotService), §C9 (TowerVisit/TowerHome/TowerElevator),
--  §C10 (State Plot), §B3 (Plot-Zuweisung mit Freunde-Nachbarschaft), §B4.10 (Aufzug, Besuche, Privat-Etagen).
--
--  * 10 Plots am Skyline-Ring (Config.Server.Plots). Beim Beitritt: freier Plot neben einem Freund im Server
--    (IsFriendsWithAsync, pcall, je Paar gecacht), sonst der nächste freie im Uhrzeigersinn ab Plot 1.
--  * Beim Verlassen: Plot frei, Besucher höflich zur Plaza teleportiert (AntiCheatService.NoteTeleport), Kran-Abbau
--    über TowerVisualService.Clear.
--  * Teleports immer serverseitig: erst Player:RequestStreamAroundAsync (StreamingEnabled), dann NoteTeleport +
--    PivotTo. Ziel-CFrames sind FUSSPUNKTE (Boden-Oberfläche); die Wurzel-Höhe rechnet Teleport selbst dazu.
--  * Geometrie (Config.Tower.Geometry): Plot-LookVector zeigt nach vorn (zur Plaza); Etage n beginnt auf Höhe
--    (n − 1) × FloorHeight; Aufzugs-Ankunft = Plot-Mitte + vorn × ElevatorLanding, Höhe + Slab. Etage 1 = Lobby.
--
--  Öffentliche API (§C5.5):
--    PlotService.PlotOf(p): number?            PlotService.OwnerOf(plot): Player?
--    PlotService.PlotCFrame(plot): CFrame      Plot-Mitte am Boden (CityService.PlotSite, sonst Ring-Formel §A5)
--    PlotService.LobbyCFrame(plot): CFrame     Fußpunkt vor der Aufzugstür im Erdgeschoss
--    PlotService.IsOnOwnPlot(p): boolean       waagerecht ≤ Config.Tower.CollectRange (70) zur Plot-Mitte
--    PlotService.Teleport(p, cf): boolean      + AntiCheatService.NoteTeleport
--  Ergänzungen: PlotService.FloorCFrame(plot, floor): CFrame · PlotService.TowerAt(position): number?
--    PlotService.VisitingOf(p): number?   (UserId des besuchten Towers)
--  Request-Handler: TowerVisit {UserId} (1/2 s), TowerHome {} (1/2 s), TowerElevator {Floor} (2/s)
--  State: Plot = { Id, Visiting? }. Attribut am Player: "Plot" (Nummer, 0 = keiner).
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Types = require(Shared:WaitForChild("Types"))
local Lang = require(Shared:WaitForChild("Lang"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local PlotService = {}
local Services: any = nil

type Reply = Types.Reply

local PREFIX = "[PlotService] "
local FRIEND_BUDGET = 4 -- Sekunden: so lange darf die Freundes-Suche beim Beitritt höchstens dauern
local FRIEND_CACHE_MAX = 400
local SPAWN_WAIT = 10 -- Sekunden auf HumanoidRootPart warten
local ERROR_LOG_EVERY = 10

local TCFG: { [string]: any } = if type(Config.Tower) == "table" then Config.Tower else {}

local function num(v: any, default: number): number
	return if Util.IsFinite(v) then v else default
end

local function sub(t: any, key: string): { [string]: any }
	local v = if type(t) == "table" then t[key] else nil
	return if type(v) == "table" then v else {}
end

local function plotCount(): number
	local server = Config.Server
	local n = if type(server) == "table" then server.Plots else nil
	return math.clamp(math.floor(num(n, 10)), 1, 32)
end

local PLOTS = plotCount()
local FLOORS = math.clamp(math.floor(num(TCFG.Floors, 50)), 1, 50)
local GEOMETRY = sub(TCFG, "Geometry")
local VISIT = sub(TCFG, "Visit")
local FLOOR_HEIGHT = num(TCFG.FloorHeight, 12)
local SLAB = num(GEOMETRY.Slab, 1)
local LANDING = num(GEOMETRY.ElevatorLanding, 8)
local TOWER_RADIUS = num(VISIT.TowerRadius, 55)

-- ---------------------------------------------------------------------
-- 1) ZUSTAND (pro Spieler bei PlayerRemoving geleert)
-- ---------------------------------------------------------------------
local owners: { [number]: Player } = {} -- Plot -> Besitzer
local plots: { [Player]: number } = {} -- Besitzer -> Plot
local visiting: { [Player]: number } = {} -- Besucher -> UserId des besuchten Towers
local visitedSession: { [Player]: { [number]: boolean } } = {} -- für Quest "VisitTower" (1× je Tower/Sitzung)
local assigning: { [Player]: boolean } = {}
local friendCache: { [string]: boolean } = {}
local friendCacheCount = 0
local errorLogAt: { [string]: number } = {}
local characterConnections: { [Player]: RBXScriptConnection } = {}

local function logError(where: string, err: any)
	local t = os.clock()
	if t - (errorLogAt[where] or -math.huge) >= ERROR_LOG_EVERY then
		errorLogAt[where] = t
		warn(PREFIX .. where .. ": " .. tostring(err))
	end
end

local function call(serviceName: string, fnName: string, ...: any): (boolean, any, any)
	local s = Services and Services[serviceName]
	local fn = if type(s) == "table" then s[fnName] else nil
	if type(fn) ~= "function" then
		return false, nil, nil
	end
	local ok, a, b = pcall(fn, ...)
	if not ok then
		logError(serviceName .. "." .. fnName, a)
		return false, nil, nil
	end
	return true, a, b
end

local function langOf(p: Player): Types.Lang
	local ok, lang = call("PlayerStateService", "LangOf", p)
	if ok and (lang == "de" or lang == "en") then
		return lang
	end
	return Lang.For(p)
end

local function fail(p: Player, key: string, args: { any }?): Reply
	local lang = langOf(p)
	return { Ok = false, Message = if args then Lang.T(lang, key, table.unpack(args)) else Lang.T(lang, key) }
end

local function okReply(p: Player, key: string?, args: { any }?): Reply
	if not key then
		return { Ok = true }
	end
	local lang = langOf(p)
	return { Ok = true, Message = if args then Lang.T(lang, key, table.unpack(args)) else Lang.T(lang, key) }
end

local function markDirty(p: Player, ...: string)
	call("PlayerStateService", "MarkDirty", p, ...)
end

local function dataOf(p: Player): { [string]: any }?
	local ok, data = call("DataService", "Get", p)
	if ok and type(data) == "table" and type(data.Tower) == "table" then
		return data
	end
	return nil
end

local function isAdmin(p: Player): boolean
	local ok, result = call("AdminService", "IsAdmin", p)
	return ok and result == true
end

local function rootOf(p: Player): BasePart?
	local character = p.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function validPlot(plot: any): boolean
	return Util.IsFinite(plot) and plot % 1 == 0 and plot >= 1 and plot <= PLOTS
end

-- ---------------------------------------------------------------------
-- 2) GEOMETRIE
-- ---------------------------------------------------------------------
-- Ring-Formel (§A5): R 420, Winkel 18° + (k − 1) · 36°, LookVector zur Plaza-Mitte
local function ringCFrame(plot: number): CFrame
	local city = Config.City
	local ring = if type(city) == "table" and type(city.Plots) == "table" then city.Plots else sub(TCFG, "Plots")
	local fallback = sub(TCFG, "Plots")
	local radius = num(ring.Radius, num(fallback.Radius, 420))
	local start = num(ring.StartAngle, num(fallback.StartAngle, 18))
	local step = num(ring.Step, num(fallback.Step, 360 / PLOTS))
	local angle = math.rad(start + (plot - 1) * step)
	local position = Vector3.new(radius * math.cos(angle), 0, radius * math.sin(angle))
	return CFrame.lookAt(position, Vector3.new(0, 0, 0))
end

-- Plot-Mitten von CityService werden gemerkt (statisch); ohne CityService gilt die Ring-Formel
local siteCache: { [number]: CFrame } = {}

function PlotService.PlotCFrame(plot: number): CFrame
	if not validPlot(plot) then
		return CFrame.identity
	end
	local cached = siteCache[plot]
	if cached then
		return cached
	end
	local ok, cf = call("CityService", "PlotSite", plot)
	if ok and typeof(cf) == "CFrame" and Util.IsFiniteVector(cf.Position) then
		siteCache[plot] = cf
		return cf
	end
	return ringCFrame(plot)
end

-- Fußpunkt vor der Aufzugstür auf Etage floor (1 = Erdgeschoss/Lobby)
function PlotService.FloorCFrame(plot: number, floor: number): CFrame
	local base = PlotService.PlotCFrame(plot)
	local level = math.clamp(math.floor(num(floor, 1)), 1, FLOORS)
	return base * CFrame.new(0, (level - 1) * FLOOR_HEIGHT + SLAB, -LANDING)
end

function PlotService.LobbyCFrame(plot: number): CFrame
	return PlotService.FloorCFrame(plot, 1)
end

local function horizontalDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- In welchem Plot steht diese Position (waagerecht ≤ Config.Tower.Visit.TowerRadius)?
function PlotService.TowerAt(position: Vector3): number?
	if typeof(position) ~= "Vector3" then
		return nil
	end
	for plot = 1, PLOTS do
		if horizontalDistance(position, PlotService.PlotCFrame(plot).Position) <= TOWER_RADIUS then
			return plot
		end
	end
	return nil
end

local function plazaCFrame(): CFrame
	local ok, cf = call("CityService", "Anchor", "Spawn")
	if ok and typeof(cf) == "CFrame" then
		return cf
	end
	local fallback = VISIT.PlazaFallback
	if type(fallback) == "table" then
		return CFrame.new(num(fallback[1], 0), num(fallback[2], 4), num(fallback[3], 60))
	end
	return CFrame.new(0, 4, 60)
end

-- ---------------------------------------------------------------------
-- 3) ÖFFENTLICHE ABFRAGEN
-- ---------------------------------------------------------------------
function PlotService.PlotOf(p: Player): number?
	return plots[p]
end

function PlotService.OwnerOf(plot: number): Player?
	local owner = owners[plot]
	if owner and owner.Parent == Players then
		return owner
	end
	return nil
end

function PlotService.VisitingOf(p: Player): number?
	return visiting[p]
end

function PlotService.IsOnOwnPlot(p: Player): boolean
	local plot = plots[p]
	local root = rootOf(p)
	if not plot or not root then
		return false
	end
	local range = num(TCFG.CollectRange, 70)
	return horizontalDistance(root.Position, PlotService.PlotCFrame(plot).Position) <= range
end

-- ---------------------------------------------------------------------
-- 4) TELEPORT (Fußpunkt -> Wurzel-Höhe; Streaming zuerst; AntiCheat-Gnade direkt vor dem Versetzen)
-- ---------------------------------------------------------------------
local function rootOffset(humanoid: Humanoid, root: BasePart): number
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		return root.Size.Y * 0.5 + 2
	end
	return humanoid.HipHeight + root.Size.Y * 0.5
end

function PlotService.Teleport(p: Player, cf: CFrame): boolean
	if typeof(p) ~= "Instance" or not p:IsA("Player") or p.Parent ~= Players or typeof(cf) ~= "CFrame" then
		return false
	end
	if not Util.IsFiniteVector(cf.Position) then
		return false
	end
	local character = p.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = rootOf(p)
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return false
	end
	if humanoid.SeatPart ~= nil then
		return false -- erst aussteigen (Sitz-Schweißung würde das Auto mitziehen)
	end
	local target = cf + Vector3.new(0, rootOffset(humanoid, root), 0)
	task.spawn(function()
		local timeout = num(VISIT.StreamTimeout, 2)
		if timeout > 0 then
			pcall(function()
				p:RequestStreamAroundAsync(target.Position, timeout)
			end)
		end
		if p.Parent ~= Players or p.Character ~= character or humanoid.Health <= 0 or humanoid.SeatPart ~= nil then
			return
		end
		call("AntiCheatService", "NoteTeleport", p, target)
		local ok, err = pcall(function()
			character:PivotTo(target)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end)
		if not ok then
			logError("Teleport", err)
		end
	end)
	return true
end

-- Vorplatz vor dem eigenen Tower (Blick zum Tower)
local function spawnCFrame(plot: number): CFrame
	local base = PlotService.PlotCFrame(plot)
	local position = (base * CFrame.new(0, 0.5, -num(VISIT.SpawnOffset, 40))).Position
	local center = base.Position
	return CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z))
end

local function placeAtPlot(p: Player)
	local plot = plots[p]
	if not plot or VISIT.SpawnAtPlot == false then
		return
	end
	PlotService.Teleport(p, spawnCFrame(plot))
end

-- ---------------------------------------------------------------------
-- 5) ZUWEISUNG MIT FREUNDE-NACHBARSCHAFT (§B3)
-- ---------------------------------------------------------------------
local function pairKey(a: number, b: number): string
	return if a < b then a .. ":" .. b else b .. ":" .. a
end

local function areFriends(a: Player, b: Player): boolean
	if a.UserId <= 0 or b.UserId <= 0 then
		return false -- Studio-Testspieler: IsFriendsWithAsync scheitert ohnehin
	end
	local key = pairKey(a.UserId, b.UserId)
	local cached = friendCache[key]
	if cached ~= nil then
		return cached
	end
	local ok, result = pcall(function()
		return a:IsFriendsWithAsync(b.UserId)
	end)
	local value = ok and result == true
	if ok and friendCacheCount < FRIEND_CACHE_MAX then
		friendCache[key] = value
		friendCacheCount += 1
	end
	return value
end

local function isFree(plot: number): boolean
	local owner = owners[plot]
	return owner == nil or owner.Parent ~= Players
end

local function neighbours(plot: number): { number }
	local left = if plot == 1 then PLOTS else plot - 1
	local right = if plot == PLOTS then 1 else plot + 1
	return { right, left }
end

local function pickPlot(friendPlots: { number }): number?
	for _, plot in ipairs(friendPlots) do
		for _, candidate in ipairs(neighbours(plot)) do
			if isFree(candidate) then
				return candidate
			end
		end
	end
	for plot = 1, PLOTS do
		if isFree(plot) then
			return plot
		end
	end
	return nil
end

local function assign(p: Player)
	if plots[p] or assigning[p] then
		return
	end
	assigning[p] = true
	-- 1) Freunde im Server mit Plot suchen (yieldet – darum vor der eigentlichen Wahl)
	local friendPlots: { number } = {}
	local started = os.clock()
	for _, other in ipairs(Players:GetPlayers()) do
		if os.clock() - started > FRIEND_BUDGET then
			break
		end
		if other ~= p and plots[other] and areFriends(p, other) then
			table.insert(friendPlots, plots[other])
		end
	end
	assigning[p] = nil
	if p.Parent ~= Players or plots[p] then
		return
	end
	-- 2) Wahl + Eintrag ohne Yield dazwischen (keine Doppelvergabe)
	local plot = pickPlot(friendPlots)
	if not plot then
		warn(PREFIX .. "kein freier Plot für " .. p.Name)
		pcall(function()
			p:SetAttribute("Plot", 0)
		end)
		markDirty(p, "Plot")
		return
	end
	owners[plot] = p
	plots[p] = plot
	pcall(function()
		p:SetAttribute("Plot", plot)
	end)
	markDirty(p, "Plot", "Tower")
	local okLoaded, loaded = call("DataService", "IsLoaded", p)
	if okLoaded and loaded == true then
		call("TowerVisualService", "Rebuild", p)
	end
	if p.Character then
		placeAtPlot(p)
	end
end

local function onCharacterAdded(p: Player, character: Model)
	if VISIT.SpawnAtPlot == false then
		return
	end
	task.spawn(function()
		local root = character:WaitForChild("HumanoidRootPart", SPAWN_WAIT)
		if root and p.Parent == Players and p.Character == character and plots[p] then
			placeAtPlot(p)
		end
	end)
end

local function onPlayerAdded(p: Player)
	visitedSession[p] = {}
	if characterConnections[p] == nil then
		characterConnections[p] = p.CharacterAdded:Connect(function(character: Model)
			onCharacterAdded(p, character)
		end)
	end
	task.spawn(assign, p)
end

-- Besucher eines Plots (in der Fläche oder als Besuch gemerkt) höflich zur Plaza bringen
local function sendVisitorsHome(plot: number, ownerUserId: number, leaving: Player?)
	local center = PlotService.PlotCFrame(plot).Position
	local plaza = plazaCFrame()
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= leaving and plots[other] ~= plot then
			local root = rootOf(other)
			local inside = root ~= nil and horizontalDistance(root.Position, center) <= TOWER_RADIUS
			if inside or visiting[other] == ownerUserId then
				if visiting[other] == ownerUserId then
					visiting[other] = nil
					markDirty(other, "Plot")
				end
				if inside then
					PlotService.Teleport(other, plaza)
				end
			end
		end
	end
end

local function onPlayerRemoving(p: Player)
	local plot = plots[p]
	if plot then
		sendVisitorsHome(plot, p.UserId, p)
		call("TowerVisualService", "Clear", plot)
		if owners[plot] == p then
			owners[plot] = nil
		end
	end
	plots[p] = nil
	visiting[p] = nil
	visitedSession[p] = nil
	assigning[p] = nil
	local connection = characterConnections[p]
	if connection then
		connection:Disconnect()
		characterConnections[p] = nil
	end
	-- Freundes-Cache: Paare dieses Spielers entfernen
	local id = tostring(p.UserId)
	for key in pairs(friendCache) do
		local a, b = string.match(key, "^(%-?%d+):(%-?%d+)$")
		if a == id or b == id then
			friendCache[key] = nil
			friendCacheCount -= 1
		end
	end
	friendCacheCount = math.max(0, friendCacheCount)
end

-- ---------------------------------------------------------------------
-- 6) BESUCHE ERKENNEN (1 Hz): wer steht in welchem fremden Tower?
-- ---------------------------------------------------------------------
local function visitJob(_dt: number)
	for _, p in ipairs(Players:GetPlayers()) do
		local root = rootOf(p)
		local current = visiting[p]
		local nextVisit: number? = nil
		if root then
			local plot = PlotService.TowerAt(root.Position)
			local owner = if plot then PlotService.OwnerOf(plot) else nil
			if owner and owner ~= p then
				nextVisit = owner.UserId
			end
		end
		if nextVisit ~= current then
			local visitId = nextVisit
			if visitId then
				visiting[p] = visitId
			else
				visiting[p] = nil
			end
			markDirty(p, "Plot")
			if visitId then
				local seen = visitedSession[p]
				if seen and not seen[visitId] then
					seen[visitId] = true
					call("RewardService", "Track", p, "VisitTower", 1, { Owner = visitId })
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- 7) REQUEST-HANDLER (§C9)
-- ---------------------------------------------------------------------
local function exact(arg: any, spec: { [string]: string }): boolean
	if type(arg) ~= "table" then
		return false
	end
	local count = 0
	for key, value in pairs(arg) do
		count += 1
		if count > 4 or spec[key] == nil or type(value) ~= spec[key] then
			return false
		end
		if spec[key] == "number" and not Util.IsFinite(value) then
			return false
		end
	end
	for key in pairs(spec) do
		if arg[key] == nil then
			return false
		end
	end
	return true
end

local function teleportReply(p: Player, cf: CFrame, key: string?, args: { any }?): Reply
	local character = p.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.SeatPart ~= nil then
		return fail(p, "tower.inCar")
	end
	if not PlotService.Teleport(p, cf) then
		return fail(p, "tower.noCharacter")
	end
	return okReply(p, key, args)
end

local function handleVisit(p: Player, arg: any): Reply
	if not exact(arg, { UserId = "number" }) or arg.UserId % 1 ~= 0 then
		return fail(p, "core.invalid")
	end
	if arg.UserId == p.UserId then
		local own = plots[p]
		if not own then
			return fail(p, "tower.noPlot")
		end
		return teleportReply(p, PlotService.LobbyCFrame(own), "tower.home", nil)
	end
	local owner = Players:GetPlayerByUserId(arg.UserId)
	local plot = if owner then plots[owner] else nil
	if not owner or not plot then
		return fail(p, "tower.ownerGone")
	end
	local reply = teleportReply(p, PlotService.LobbyCFrame(plot), "tower.visiting", { owner.DisplayName })
	if reply.Ok then
		visiting[p] = owner.UserId
		markDirty(p, "Plot")
		local seen = visitedSession[p]
		if seen and not seen[owner.UserId] then
			seen[owner.UserId] = true
			call("RewardService", "Track", p, "VisitTower", 1, { Owner = owner.UserId })
		end
	end
	return reply
end

local function handleHome(p: Player, arg: any): Reply
	if arg ~= nil and not exact(arg, {}) then
		return fail(p, "core.invalid")
	end
	local plot = plots[p]
	if not plot then
		return fail(p, "tower.noPlot")
	end
	local reply = teleportReply(p, PlotService.LobbyCFrame(plot), "tower.home", nil)
	if reply.Ok and visiting[p] ~= nil then
		visiting[p] = nil
		markDirty(p, "Plot")
	end
	return reply
end

local function handleElevator(p: Player, arg: any): Reply
	if not exact(arg, { Floor = "number" }) or arg.Floor % 1 ~= 0 or arg.Floor < 0 or arg.Floor > FLOORS then
		return fail(p, "core.invalid")
	end
	local root = rootOf(p)
	if not root then
		return fail(p, "tower.noCharacter")
	end
	-- nur im eigenen oder gerade besuchten Tower (dort, wo man steht)
	local plot = PlotService.TowerAt(root.Position)
	local owner = if plot then PlotService.OwnerOf(plot) else nil
	if not plot or not owner then
		return fail(p, "tower.notInTower")
	end
	local data = dataOf(owner)
	if not data then
		return fail(p, "core.loading")
	end
	local tower = data.Tower
	local floors = if type(tower.Floors) == "table" then #tower.Floors else 0
	local floor = math.max(1, arg.Floor) -- 0 = Lobby = Erdgeschoss
	if floor > math.max(1, floors) then
		return fail(p, "tower.noFloor")
	end
	if owner ~= p and type(tower.Private) == "table" and table.find(tower.Private, floor) and not isAdmin(p) then
		return fail(p, "tower.privateFloor")
	end
	return teleportReply(p, PlotService.FloorCFrame(plot, floor), nil, nil)
end

-- ---------------------------------------------------------------------
-- 8) STATE & LEBENSZYKLUS
-- ---------------------------------------------------------------------
local function plotState(p: Player): { [string]: any }
	return { Id = plots[p] or 0, Visiting = visiting[p] }
end

function PlotService.Init(services: any)
	Services = services
	local pss = Services.PlayerStateService
	if type(pss) ~= "table" then
		warn(PREFIX .. "PlayerStateService fehlt – keine Anfragen/State")
		return
	end
	pss.Provide("Plot", plotState)
	pss.Handle("TowerVisit", handleVisit, { Rate = 1, Per = 2 })
	pss.Handle("TowerHome", handleHome, { Rate = 1, Per = 2 })
	pss.Handle("TowerElevator", handleElevator, { Rate = 2, Per = 1 })
end

function PlotService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, p)
		if p.Character then
			task.spawn(onCharacterAdded, p, p.Character)
		end
	end
	Scheduler.Every("PlotVisits", 1, visitJob)
end

return PlotService
