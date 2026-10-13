-- =====================================================================
--  AKYTEX TYCOON – Die Stadt (Server/Services/CityService)
--  Besitzer: WP7 (Stadt, Grafik, Fahrzeuge). Vertrag: DESIGN.md §C5.6 (öffentliche API), §A5 (2-km-Stadt mit allen Zonen),
--  §B3 (Plots, Streaming-Modi, Teilebudget ≤ 12.000, Aufbau ≤ 400 Parts je Frame), §D WP7 (Anker mit Attributen,
--  Monitor-/Board-Parts), §C16 (Budgets).
--
--  Ablauf: Init plant die Stadt (World/CityLayout, rein) und baut sofort nur das Nötigste (Plaza-Boden, Spawn, Plot-Flächen,
--  Anker, Board-Flächen). Der Rest entsteht über Scheduler.EveryFrame verteilt: je Frame ≤ Config.City.BuildPerFrame Teile
--  (World/CityKit) + Config.City.TerrainPerFrame Terrain-Aufträge (Boden, Grüngürtel, Marina-Wasser, Villenhügel mit
--  Serpentine und Autobahn-Tunnel). Danach Ready() = true und die Teilezahl steht fest (SelfTest WorldTests).
--  Schnellreise-Prompts (Helipad hoch/zur Plaza, Club-Lift) handelt der Server selbst (ProximityPrompt.Triggered,
--  Teleport über PlotService.Teleport + AntiCheatService.NoteTeleport).
--
--  Öffentliche API (§C5.6):
--    CityService.Anchor(name): CFrame?        "Bell","BellZone","TowerTour","Showroom","Boutique","Helipad","Marina",
--                                             "Lookout","PressScreen","IpoWall","HallOfFame","Academy","VipBalcony",
--                                             "Rooftop","Spawn" (+ Läden "ShopBurger" …) – Fußpunkte, LookVector = Blick
--    CityService.Route(name): { Vector3 }     "Ring" | "Outer" | "Highway" | "Parade" – geschlossen (letzter = erster)
--    CityService.ShopPart(instId): BasePart?  Laden-Front (6 Firmen-Läden), sonst Leuchtschild des Kulissen-Turms
--    CityService.PlotSite(plot): CFrame       Plot-Mitte auf der Plot-Oberkante, LookVector zur Plaza
--    CityService.BoardPart(name): BasePart?   "Wealth","League","Return","Skyline","Firm","Respekt","IpoWall",
--                                             "PressScreen","HallOfFame","Hall1","Hall2","Hall3","TowerTour"
--    CityService.Ready(): boolean
--  Zusätzlich: CityService.PartCount(): number · CityService.Folder(): Folder? · CityService.AnchorNames(): { string } ·
--    CityService.Stats(): { Parts, Specs, Built, Terrain, TerrainDone, Seconds, Ready }
-- =====================================================================

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any
local Util = require(Shared:WaitForChild("Util"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))
local World = script.Parent.Parent:WaitForChild("World")
local CityLayout = require(World:WaitForChild("CityLayout")) :: any
local CityKit = require(World:WaitForChild("CityKit")) :: any

local CityService = {}
local Services: any = nil

local PREFIX = "[CityService] "
local FOLDER_NAME = "AkytexCity"
local CAR_COST = 46 -- ein Ausstellungsauto zählt so viele Teile im Frame-Budget
local TRAVEL_COOLDOWN = 2
local ERROR_LOG_EVERY = 10
local MAX_PROMPT_DISTANCE = 16

type BuildItem = { Group: any, Spec: any }

local plan: any = nil
local anchors: { [string]: CFrame } = {}
local plotSites: { CFrame } = {}
local cityFolder: Folder? = nil
local groupModels: { [any]: Model } = {}
local queue: { BuildItem } = {}
local queueIndex = 1
local terrainIndex = 1
local ready = false
local partCount = 0
local builtSpecs = 0
local startedAt = 0
local finishedAt = 0
local stopBuild: (() -> ())? = nil
local boardParts: { [string]: BasePart } = {}
local shopParts: { [number]: BasePart } = {}
local signParts: { [number]: BasePart } = {}
local travelAt: { [Player]: number } = {}
local errorLogAt: { [string]: number } = {}

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function logError(where: string, err: any)
	local now = os.clock()
	if now - (errorLogAt[where] or -math.huge) >= ERROR_LOG_EVERY then
		errorLogAt[where] = now
		warn(PREFIX .. where .. ": " .. tostring(err))
	end
end

local function call(serviceName: string, fnName: string, ...: any): (boolean, any)
	local s = Services and Services[serviceName]
	local fn = if type(s) == "table" then s[fnName] else nil
	if type(fn) ~= "function" then
		return false, nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		logError(serviceName .. "." .. fnName, result)
		return false, nil
	end
	return true, result
end

local function ensurePlan(): any
	if plan == nil then
		plan = CityLayout.Plan(Config)
		anchors = plan.Anchors
		plotSites = plan.PlotSites
	end
	return plan
end

-- Fertiges Teil registrieren (Boards, Läden, Kulissen-Schilder)
local function register(inst: Instance?)
	if not inst then
		return
	end
	local function one(part: Instance)
		if not part:IsA("BasePart") then
			return
		end
		partCount += 1
		local board = part:GetAttribute("Board")
		if type(board) == "string" then
			boardParts[board] = part
		end
		local shop = part:GetAttribute("Shop")
		if type(shop) == "number" then
			shopParts[shop] = part
		end
		local company = part:GetAttribute("Company")
		if type(company) == "number" and company > 0 then
			signParts[company] = part
		end
	end
	one(inst)
	for _, child in ipairs(inst:GetDescendants()) do
		one(child)
	end
end

local function modelFor(group: any): Model
	local model = groupModels[group]
	if model and model.Parent then
		return model
	end
	local folder = cityFolder :: Folder
	model = CityKit.GroupModel(group, folder)
	groupModels[group] = model
	local ok, err = pcall(CityKit.PlaceAssets, group, model)
	if not ok then
		logError("PlaceAssets " .. tostring(group.Key), err)
	end
	return model
end

local function buildOne(item: BuildItem): number
	local model = modelFor(item.Group)
	local ok, result = pcall(CityKit.Build, item.Spec, model, item.Group)
	builtSpecs += 1
	if not ok then
		logError("Build " .. tostring(item.Spec.Name), result)
		return 1
	end
	register(result)
	return if item.Spec.Car then CAR_COST else 1
end

local function setupTerrain()
	local terrain = workspace.Terrain
	local ground = Config.City.Ground
	for name, color in pairs(ground.Colors) do
		local material = (Enum.Material :: any)[name]
		if typeof(material) == "EnumItem" and typeof(color) == "Color3" then
			pcall(function()
				terrain:SetMaterialColor(material, color)
			end)
		end
	end
	local water = ground.Water
	pcall(function()
		terrain.WaterColor = water.Color
		terrain.WaterTransparency = water.Transparency
		terrain.WaterReflectance = water.Reflectance
		terrain.WaterWaveSize = water.WaveSize
		terrain.WaterWaveSpeed = water.WaveSpeed
		terrain.Decoration = false -- kein Gras-Teppich (Leistung Handy)
	end)
end

local function finish()
	ready = true
	finishedAt = os.clock()
	local folder = cityFolder
	if folder then
		partCount = CityKit.CountParts(folder)
	end
	local budget = Config.City.PartBudget or 12000
	print(("%sStadt gebaut: %d Teile (Budget %d) in %.1f s"):format(PREFIX, partCount, budget, finishedAt - startedAt))
	if partCount > budget then
		warn(PREFIX .. ("Teilebudget überschritten: %d > %d"):format(partCount, budget))
	end
	local stop = stopBuild
	stopBuild = nil
	if stop then
		stop()
	end
end

-- Ein Frame Aufbau (yieldet nie)
local function buildStep(_dt: number)
	if ready then
		return
	end
	local p = plan
	if not p then
		return
	end
	local terrainJobs = p.Terrain
	local terrainBudget = math.max(1, Config.City.TerrainPerFrame or 3)
	local terrain = workspace.Terrain
	while terrainBudget > 0 and terrainIndex <= #terrainJobs do
		local job = terrainJobs[terrainIndex]
		terrainIndex += 1
		terrainBudget -= 1
		local ok, err = pcall(job, terrain)
		if not ok then
			logError("Terrain", err)
		end
	end
	local budget = math.max(10, Config.City.BuildPerFrame or 400)
	while budget > 0 and queueIndex <= #queue do
		local item = queue[queueIndex]
		queueIndex += 1
		budget -= buildOne(item)
	end
	if queueIndex > #queue and terrainIndex > #terrainJobs then
		finish()
	end
end

-- ---------------------------------------------------------------------
-- SCHNELLREISE (Helipad, Club-Lift)
-- ---------------------------------------------------------------------
local function notify(p: Player, key: string, kind: string?)
	call("PlayerStateService", "Notify", p, key, nil, kind or "Info")
end

local function teleport(p: Player, cf: CFrame): boolean
	local ok, result = call("PlotService", "Teleport", p, cf)
	if ok then
		return result == true
	end
	-- Ersatz ohne PlotService: Fußpunkt + Wurzel-Höhe, NoteTeleport vorher
	local character = p.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or not root or not root:IsA("BasePart") or humanoid.SeatPart ~= nil then
		return false
	end
	local target = cf + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	call("AntiCheatService", "NoteTeleport", p, target)
	local moved = pcall(function()
		character:PivotTo(target)
		root.AssemblyLinearVelocity = Vector3.zero
	end)
	return moved
end

local function isClub(p: Player): boolean
	if p:GetAttribute("Club") == true then
		return true
	end
	local ok, result = call("MonetizationService", "IsClub", p)
	return ok and result == true
end

local function onPrompt(prompt: ProximityPrompt, p: Player)
	local folder = cityFolder
	if not folder or not prompt:IsDescendantOf(folder) or p.Parent ~= Players then
		return
	end
	local action = prompt:GetAttribute("Action")
	if type(action) ~= "string" then
		return -- Fenster-Prompts öffnet der Client (UI-Kit)
	end
	-- Abstand selbst prüfen (Prompt-Distanz ist nur Client-UX)
	local character = p.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local holder = prompt.Parent
	if not root or not root:IsA("BasePart") or not holder or not holder:IsA("BasePart") then
		return
	end
	if (root.Position - holder.Position).Magnitude > MAX_PROMPT_DISTANCE then
		return
	end
	local now = os.clock()
	if now - (travelAt[p] or -math.huge) < TRAVEL_COOLDOWN then
		notify(p, "world.travelBusy")
		return
	end
	travelAt[p] = now
	local target: CFrame? = nil
	local message: string? = nil
	if action == "HelipadUp" then
		target, message = anchors.Helipad, "world.travelHelipad"
	elseif action == "HelipadFly" then
		target, message = anchors.Spawn, "world.travelPlaza"
	elseif action == "ClubUp" then
		if not isClub(p) then
			notify(p, "world.clubOnly", "Error")
			return
		end
		target, message = anchors.Rooftop, "world.travelRoof"
	elseif action == "ClubDown" then
		target = anchors.IpoWall
	end
	if target and teleport(p, target) and message then
		notify(p, message, "Success")
	end
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICHE API (§C5.6)
-- ---------------------------------------------------------------------
function CityService.Anchor(name: string): CFrame?
	if type(name) ~= "string" then
		return nil
	end
	if next(anchors) == nil then
		local ok, result = pcall(CityLayout.Anchors, Config)
		if ok and type(result) == "table" then
			anchors = result
		end
	end
	return anchors[name]
end

function CityService.AnchorNames(): { string }
	local names = {}
	for name in pairs(anchors) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function CityService.Route(name: string): { Vector3 }
	if type(name) ~= "string" then
		return {}
	end
	local ok, points = pcall(Config.City.RoutePoints, name)
	if ok and type(points) == "table" then
		return points
	end
	return {}
end

function CityService.ShopPart(instId: number): BasePart?
	if not Util.IsFinite(instId) then
		return nil
	end
	local shop = shopParts[instId]
	if shop and shop.Parent then
		return shop
	end
	local sign = signParts[instId]
	if sign and sign.Parent then
		return sign
	end
	return nil
end

function CityService.PlotSite(plot: number): CFrame
	local k = if Util.IsFinite(plot) then math.floor(plot) else 1
	local site = plotSites[k]
	if site then
		return site
	end
	return Config.City.PlotCFrame(k)
end

function CityService.BoardPart(name: string): BasePart?
	if type(name) ~= "string" then
		return nil
	end
	local part = boardParts[name]
	if part and part.Parent then
		return part
	end
	return nil
end

function CityService.Ready(): boolean
	return ready
end

function CityService.PartCount(): number
	local folder = cityFolder
	if ready or not folder then
		return partCount
	end
	return CityKit.CountParts(folder)
end

function CityService.Folder(): Folder?
	return cityFolder
end

function CityService.Stats(): { [string]: any }
	local p = plan
	return {
		Parts = CityService.PartCount(),
		Specs = if p then p.Count else 0,
		Built = builtSpecs,
		Terrain = if p then #p.Terrain else 0,
		TerrainDone = terrainIndex - 1,
		Seconds = (if ready then finishedAt else os.clock()) - startedAt,
		Ready = ready,
	}
end

-- ---------------------------------------------------------------------
-- LEBENSZYKLUS
-- ---------------------------------------------------------------------
function CityService.Init(services: any)
	Services = services
	startedAt = os.clock()
	local okPlan, err = pcall(ensurePlan)
	if not okPlan then
		warn(PREFIX .. "Stadtplan fehlgeschlagen: " .. tostring(err))
		ready = true
		return
	end
	-- alter Bau (z. B. Studio-Neustart im selben Ort) weg, dann neu
	local old = workspace:FindFirstChild(FOLDER_NAME)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = workspace
	cityFolder = folder
	setupTerrain()
	-- Priorität sofort (Spawn, Plot-Flächen, Anker, Boards), Rest in die Warteschlange
	local priority = 0
	for _, group in ipairs(plan.Groups) do
		for _, spec in ipairs(group.Specs) do
			local item = { Group = group, Spec = spec }
			if spec.Priority then
				buildOne(item)
				priority += 1
			else
				table.insert(queue, item)
			end
		end
	end
	stopBuild = Scheduler.EveryFrame("CityBuild", buildStep)
	print(
		("%sAufbau gestartet: %d sofort, %d in der Warteschlange, %d Terrain-Aufträge"):format(
			PREFIX,
			priority,
			#queue,
			#plan.Terrain
		)
	)
end

function CityService.Start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, p: Player)
		local ok, err = pcall(onPrompt, prompt, p)
		if not ok then
			logError("Prompt", err)
		end
	end)
	Players.PlayerRemoving:Connect(function(p: Player)
		travelAt[p] = nil
	end)
end

return CityService
