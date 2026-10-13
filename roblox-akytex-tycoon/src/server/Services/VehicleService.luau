-- =====================================================================
--  AKYTEX TYCOON – Autos: Garage, Kauf, Tuning, Spawn, Tempo-Prüfung (Server/Services/VehicleService)
--  Besitzer: WP7 (Stadt, Grafik, Fahrzeuge). Vertrag: DESIGN.md §C5.6 (öffentliche API, Request-Handler), §B12.1 (16 Autos,
--  Klassen-Deckel, Server-Prüfung 5 Hz mit 1,3 × Deckel, 1 Auto je Spieler, Despawn 60 s nach dem Aussteigen, Garage 6 +4 je
--  Garagen-Ebene (max. 2) +12 Mega-Garage, Tuning, Aktionärs-Rabatt), §C11.3 (Kollisionsgruppen: VehicleService.Init
--  registriert Characters/Cars/World/Pickups VOR jedem Spawn; Charakter-Teile -> "Characters"), §C9 (CarSpawn/CarDespawn
--  1/3 s, CarBuy/CarTune 2/s, exakte Schlüssel), §C10 (State "Garage"), §0.4 (Rabatt: Fluss Depot -> Turm erlaubt, nie umgekehrt).
--
--  Physik: VehicleModels.Rig baut Federbeine/Motoren/Servo-Lenkung; Netzwerk-Besitzer = Fahrer (Client-Modul Vehicles
--  steuert Motoren, Boost, Drift). Der Server misst 5×/s das waagerechte Tempo: über 1,3 × Klassen-Deckel bei zwei Messungen
--  in Folge -> Server übernimmt kurz den Besitz, setzt das Tempo auf den Deckel und gibt AntiCheat-Punkte.
--  Einsteigen nur über den Prompt am eigenen Auto (Sitz CanTouch = false); fremde Insassen werden sofort ausgesetzt.
--
--  Öffentliche API (§C5.6):
--    VehicleService.Spawn(p, key): (boolean, string?)     string = Lang-Schlüssel des Grundes
--    VehicleService.Despawn(p)
--    VehicleService.Owns(p, key): boolean                  gespeichert ODER freigeschaltet (Gratis, Pass, Lizenz)
--    VehicleService.GrantCar(p, key): boolean              Gewährung (Starter-Paket, Login, Saison, Admin) – auch ohne Platz
--    VehicleService.Active(p): Model?
--    VehicleService.CollectionValue(p): number             Summe der CR-Preise eigener Autohaus-Autos
--  Zusätzlich: VehicleService.Slots(p): (used, total) · VehicleService._Test (reine Helfer für WorldTests)
--  Request-Handler: CarSpawn {Key}, CarDespawn {}, CarBuy {Key}, CarTune {Key, Paint?, Rims?, Glow?, Spoiler?}
--  RewardService.Track-Arten: "CarBuy" (1), "CarTune" (1), "Drive" (Studs, gebündelt ab 50)
-- =====================================================================

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any
local Util = require(Shared:WaitForChild("Util"))
local Lang = require(Shared:WaitForChild("Lang")) :: any
local Types = require(Shared:WaitForChild("Types"))
local Format = require(Shared:WaitForChild("Format")) :: any
local VehicleModels = require(Shared:WaitForChild("VehicleModels")) :: any
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local VehicleService = {}
local Services: any = nil

type Reply = Types.Reply

local PREFIX = "[VehicleService] "
local FOLDER_NAME = "AkytexCars"
local GROUPS = { "Characters", "Cars", "World", "Pickups" }
local MAX_KEY_LEN = 32
local ENTER_DISTANCE = 16
local ERROR_LOG_EVERY = 10
local RESET_NOTIFY_GAP = 10
local DRIVE_TRACK_STUDS = 50
local PARK_ANCHOR_AFTER = 3

type CarState = {
	Key: string,
	Model: Model,
	Rig: any,
	Seat: VehicleSeat,
	Prompt: ProximityPrompt?,
	Cap: number,
	Occupied: boolean,
	ExitAt: number?,
	Strikes: number,
	OwnerBackAt: number?,
	Parked: boolean,
	LastPos: Vector3?,
	DriveAcc: number,
	Conns: { RBXScriptConnection },
}

local VC: any = Config.Vehicles or {}
local active: { [Player]: CarState } = {}
local characterConns: { [Player]: { RBXScriptConnection } } = {}
local resetNotifyAt: { [Player]: number } = {}
local drivenOnce: { [Player]: boolean } = {}
local carFolder: Folder? = nil
local errorLogAt: { [string]: number } = {}
local groupsReady = false

-- ---------------------------------------------------------------------
-- 1) HELFER
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

local function langOf(p: Player): string
	local ok, lang = call("PlayerStateService", "LangOf", p)
	if ok and (lang == "de" or lang == "en") then
		return lang
	end
	return Lang.For(p)
end

local function localize(p: Player, key: string, args: { any }?): string
	if args then
		return Lang.T(langOf(p), key, table.unpack(args))
	end
	return Lang.T(langOf(p), key)
end

local function fail(p: Player, key: string, args: { any }?): Reply
	return { Ok = false, Message = localize(p, key, args) }
end

local function okReply(p: Player, key: string?, args: { any }?): Reply
	local reply: Reply = { Ok = true }
	if key then
		reply.Message = localize(p, key, args)
	end
	return reply
end

local function credits(p: Player, n: number): string
	local ok, text = pcall(Format.Credits, n, langOf(p))
	return if ok then text else tostring(n)
end

local function carName(p: Player, car: any): string
	return Lang.Pick(langOf(p), car.Name)
end

local function dataOf(p: Player): { [string]: any }?
	local ok, data = call("DataService", "Get", p)
	if ok and type(data) == "table" then
		return data
	end
	return nil
end

-- Garage-Teil des Spielstands reparieren (nie nil, Typen sauber)
local function garageOf(data: { [string]: any }): { [string]: any }
	local garage = data.Garage
	if type(garage) ~= "table" then
		garage = { Cars = { LamCity = true }, Active = "LamCity", Tune = {} }
		data.Garage = garage
	end
	if type(garage.Cars) ~= "table" then
		garage.Cars = { LamCity = true }
	end
	if type(garage.Tune) ~= "table" then
		garage.Tune = {}
	end
	if type(garage.Active) ~= "string" then
		garage.Active = "LamCity"
	end
	return garage
end

local function markDirty(p: Player)
	call("PlayerStateService", "MarkDirty", p, "Garage")
end

local function hasPass(p: Player, key: string): boolean
	local ok, result = call("MonetizationService", "HasPass", p, key)
	return ok and result == true
end

local function isClub(p: Player): boolean
	if p:GetAttribute("Club") == true then
		return true
	end
	local ok, result = call("MonetizationService", "IsClub", p)
	return ok and result == true
end

local function isVip(p: Player): boolean
	return p:GetAttribute("Vip") == true or hasPass(p, "VIP")
end

local function licenceOf(p: Player): number
	local ok, result = call("ProgressionService", "Licence", p)
	return if ok and Util.IsFinite(result) then result else 1
end

local function present(p: Player): boolean
	return typeof(p) == "Instance" and p:IsA("Player") and p.Parent == Players
end

-- Exakte Schlüssel (§C9): nur erlaubte Felder, jedes vom richtigen Typ
local function exact(arg: any, allowed: { [string]: string }, required: { string }): boolean
	if type(arg) ~= "table" then
		return false
	end
	local count = 0
	for key, value in pairs(arg) do
		count += 1
		if count > 8 or type(key) ~= "string" then
			return false
		end
		local kind = allowed[key]
		if kind == nil or type(value) ~= kind then
			return false
		end
		if kind == "string" and (#value == 0 or #value > MAX_KEY_LEN) then
			return false
		end
	end
	for _, key in ipairs(required) do
		if arg[key] == nil then
			return false
		end
	end
	return true
end

local function tuneDefaults(key: string): { [string]: any }
	local car = VC.Car(key)
	local recipe = car and VehicleModels.Recipes[car.Recipe] or nil
	return {
		Paint = if car then car.Paint else "Polar",
		Rims = VC.DefaultRims or "Stock",
		Glow = VC.GlowOff or "Off",
		Spoiler = if recipe then recipe.Spoiler == true else false,
	}
end

local function currentTune(data: { [string]: any }, key: string): { [string]: any }
	local garage = garageOf(data)
	local saved = garage.Tune[key]
	local tune = tuneDefaults(key)
	if type(saved) == "table" then
		if type(saved.Paint) == "string" and VC.Option("Paint", saved.Paint) then
			tune.Paint = saved.Paint
		end
		if type(saved.Rims) == "string" and VC.Option("Rims", saved.Rims) then
			tune.Rims = saved.Rims
		end
		if type(saved.Glow) == "string" and (saved.Glow == VC.GlowOff or VC.Option("Glow", saved.Glow)) then
			tune.Glow = saved.Glow
		end
		if type(saved.Spoiler) == "boolean" then
			tune.Spoiler = saved.Spoiler
		end
	end
	return tune
end

-- ---------------------------------------------------------------------
-- 2) REINE REGELN (auch für WorldTests)
-- ---------------------------------------------------------------------
-- Anzahl Garagen-Ebenen im Tower (Abteilung "Garage", höchstens GarageLevelsMax)
local function garageLevels(data: { [string]: any }): number
	local tower = data.Tower
	local floors = type(tower) == "table" and tower.Floors or nil
	local n = 0
	if type(floors) == "table" then
		for _, floor in ipairs(floors) do
			if type(floor) == "table" and floor.R == "Garage" then
				n += 1
			end
		end
	end
	return math.min(n, VC.GarageLevelsMax or 2)
end

local function slotsFor(data: { [string]: any }, megaGarage: boolean): number
	local base = VC.GarageBase or 6
	return base + garageLevels(data) * (VC.GarageLevelSlots or 4) + (if megaGarage then VC.MegaGarageSlots or 12 else 0)
end

local function usedSlots(data: { [string]: any }): number
	local n = 0
	for key, owned in pairs(garageOf(data).Cars) do
		if owned == true and VC.Car(key) then
			n += 1
		end
	end
	return n
end

-- Preis mit Aktionärs-Rabatt (§B12.1): (Endpreis, gesparter Betrag)
local function priceFor(car: any, discount: boolean): (number, number)
	local price = math.floor(car.Price or 0)
	local rule = VC.ShareholderDiscount
	if discount and car.Maker == "Velocitra" and type(rule) == "table" then
		local saved = math.floor(price * (rule.Pct or 0))
		return price - saved, saved
	end
	return price, 0
end

-- Tuning-Wunsch prüfen + Preis: (ok, Grund-Schlüssel?, neue Werte, Preis)
local function evaluateTune(
	carKey: string,
	current: { [string]: any },
	want: { [string]: any },
	vip: boolean,
	club: boolean
): (boolean, string?, { [string]: any }, number)
	local result = table.clone(current)
	local price = 0
	local changed = false
	if want.Paint ~= nil and want.Paint ~= current.Paint then
		local paint = VC.Option("Paint", want.Paint)
		if not paint then
			return false, "car.tuneUnknown", result, 0
		end
		if paint.Unlock == "Pass" and not vip then
			return false, "car.tuneVip", result, 0
		end
		if paint.Unlock == "Club" and not club then
			return false, "car.tuneClub", result, 0
		end
		result.Paint = want.Paint
		price += VC.TunePrice(carKey, "Paint", want.Paint)
		changed = true
	end
	if want.Rims ~= nil and want.Rims ~= current.Rims then
		if not VC.Option("Rims", want.Rims) then
			return false, "car.tuneUnknown", result, 0
		end
		result.Rims = want.Rims
		price += VC.TunePrice(carKey, "Rims", want.Rims)
		changed = true
	end
	if want.Glow ~= nil and want.Glow ~= current.Glow then
		if want.Glow ~= VC.GlowOff and not VC.Option("Glow", want.Glow) then
			return false, "car.tuneUnknown", result, 0
		end
		result.Glow = want.Glow
		price += VC.TunePrice(carKey, "Glow", want.Glow)
		changed = true
	end
	if want.Spoiler ~= nil and want.Spoiler ~= current.Spoiler then
		result.Spoiler = want.Spoiler
		if want.Spoiler then
			price += VC.TunePrice(carKey, "Spoiler", nil)
		end
		changed = true
	end
	if not changed then
		return false, "car.tuneNothing", result, 0
	end
	return true, nil, result, math.clamp(math.floor(price), 0, 9e13)
end

-- ---------------------------------------------------------------------
-- 3) BESITZ, PLÄTZE, RABATT
-- ---------------------------------------------------------------------
function VehicleService.Owns(p: Player, key: string): boolean
	local car = VC.Car(key)
	if not car or not present(p) then
		return false
	end
	if car.Source == "Free" then
		return true
	end
	local data = dataOf(p)
	if data and garageOf(data).Cars[key] == true then
		return true
	end
	if car.Source == "Pass" and type(car.Pass) == "string" then
		return hasPass(p, car.Pass)
	end
	if car.Source == "Licence" and Util.IsFinite(car.Licence) then
		return licenceOf(p) >= car.Licence
	end
	return false
end

function VehicleService.Slots(p: Player): (number, number)
	local data = dataOf(p)
	if not data then
		return 0, VC.GarageBase or 6
	end
	return usedSlots(data), slotsFor(data, hasPass(p, "MegaGarage"))
end

local function hasDiscount(p: Player): boolean
	local rule = VC.ShareholderDiscount
	if type(rule) ~= "table" then
		return false
	end
	local ok, shares = call("OrderService", "HoldsShares", p, rule.I)
	return ok and Util.IsFinite(shares) and shares >= rule.Min
end

function VehicleService.CollectionValue(p: Player): number
	local data = dataOf(p)
	if not data then
		return 0
	end
	local total = 0
	for key, owned in pairs(garageOf(data).Cars) do
		local car = VC.Car(key)
		if owned == true and car and car.Source == "Shop" and Util.IsFinite(car.Price) then
			total += car.Price
		end
	end
	return math.min(total, 9e15)
end

function VehicleService.GrantCar(p: Player, key: string): boolean
	local car = VC.Car(key)
	if not car or not present(p) then
		return false
	end
	local data = dataOf(p)
	if not data then
		return false
	end
	local garage = garageOf(data)
	if garage.Cars[key] == true then
		return true
	end
	garage.Cars[key] = true
	markDirty(p)
	call("PlayerStateService", "Effect", p, "Reveal", 1, { Key = key })
	return true
end

-- ---------------------------------------------------------------------
-- 4) KOLLISIONSGRUPPEN (§C11.3)
-- ---------------------------------------------------------------------
local function registerGroups()
	for _, name in ipairs(GROUPS) do
		local okCheck, exists = pcall(function(): boolean
			return PhysicsService:IsCollisionGroupRegistered(name)
		end)
		if not (okCheck and exists) then
			local ok, err = pcall(function()
				workspace:RegisterCollisionGroup(name)
			end)
			if not ok then
				warn(PREFIX .. "Kollisionsgruppe " .. name .. ": " .. tostring(err))
			end
		end
	end
	local ok, err = pcall(function()
		PhysicsService:CollisionGroupSetCollidable("Cars", "Characters", false) -- kein Rammen, kein Schleudern
		PhysicsService:CollisionGroupSetCollidable("Cars", "Cars", false) -- Autos fahren durcheinander hindurch
		PhysicsService:CollisionGroupSetCollidable("Cars", "World", true)
		PhysicsService:CollisionGroupSetCollidable("Cars", "Default", true) -- Welt = Standardgruppe
		for _, other in ipairs({ "Default", "Characters", "Cars", "World", "Pickups" }) do
			PhysicsService:CollisionGroupSetCollidable("Pickups", other, false)
		end
	end)
	if not ok then
		warn(PREFIX .. "Kollisionsmatrix: " .. tostring(err))
	end
	groupsReady = ok
end

local function setCharacterGroup(inst: Instance)
	if inst:IsA("BasePart") then
		inst.CollisionGroup = "Characters"
	end
end

local function clearCharacterConns(p: Player)
	local conns = characterConns[p]
	if conns then
		for _, conn in ipairs(conns) do
			conn:Disconnect()
		end
	end
	characterConns[p] = nil
end

local function onCharacter(p: Player, character: Model)
	clearCharacterConns(p)
	for _, inst in ipairs(character:GetDescendants()) do
		setCharacterGroup(inst)
	end
	characterConns[p] = {
		character.DescendantAdded:Connect(setCharacterGroup),
	}
end

-- ---------------------------------------------------------------------
-- 5) SPAWN / DESPAWN
-- ---------------------------------------------------------------------
local function folder(): Folder
	local existing = carFolder
	if existing and existing.Parent then
		return existing
	end
	local old = workspace:FindFirstChild(FOLDER_NAME)
	if old and old:IsA("Folder") then
		carFolder = old
		return old
	end
	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = workspace
	carFolder = created
	return created
end

local function setOwner(state: CarState, owner: Player?)
	for _, part in ipairs(state.Model:GetDescendants()) do
		if part:IsA("BasePart") and not part.Anchored then
			pcall(function()
				if part:CanSetNetworkOwnership() then
					part:SetNetworkOwner(owner)
				end
			end)
		end
	end
end

local function setParked(state: CarState, parked: boolean)
	if state.Parked == parked then
		return
	end
	state.Parked = parked
	local chassis = state.Rig and state.Rig.Chassis
	if chassis and chassis.Parent then
		chassis.Anchored = parked
	end
end

local function allowance(p: Player, cap: number?)
	if cap then
		local security = Config.Security or {}
		local slack = (security.Allowances and security.Allowances.CarSlack) or 1.2
		local boost = (VC.Boost and VC.Boost.Mult) or 1.25
		call("AntiCheatService", "SetAllowance", p, { MaxSpeed = cap * boost * slack })
	else
		call("AntiCheatService", "SetAllowance", p, nil)
	end
end

function VehicleService.Despawn(p: Player)
	local state = active[p]
	if not state then
		return
	end
	active[p] = nil
	for _, conn in ipairs(state.Conns) do
		conn:Disconnect()
	end
	if state.Occupied and present(p) then
		allowance(p, nil)
		call("AntiCheatService", "Grace", p, "Impulse", 1.5, state.Cap * 1.3)
	end
	if state.Model.Parent then
		state.Model:Destroy()
	end
	if present(p) then
		markDirty(p)
	end
end

-- nächster Spawnpunkt: eigene Garage (Plot-Einfahrt) oder Config.Vehicles.SpawnPoints
local function spawnCFrame(p: Player, root: BasePart): CFrame
	local candidates: { CFrame } = {}
	local okPlot, plot = call("PlotService", "PlotOf", p)
	if okPlot and Util.IsFinite(plot) then
		local okSite, site = call("CityService", "PlotSite", plot)
		local cf: CFrame = if okSite and typeof(site) == "CFrame" then site else Config.City.PlotCFrame(plot)
		local pos = (cf * CFrame.new(0, 0, -(VC.GarageSpawnOffset or 68))).Position
		local road = Config.City.Levels.Road
		local flatPos = Vector3.new(pos.X, road, pos.Z)
		table.insert(candidates, CFrame.lookAt(flatPos, flatPos + Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)))
	end
	for _, point in ipairs(VC.SpawnPoints or {}) do
		if typeof(point.Position) == "Vector3" and typeof(point.Facing) == "Vector3" then
			table.insert(candidates, CFrame.lookAt(point.Position, point.Position + point.Facing))
		end
	end
	local best = candidates[1] or CFrame.new(0, Config.City.Levels.Road, 214)
	local bestDist = math.huge
	for _, cf in ipairs(candidates) do
		local d = (cf.Position - root.Position).Magnitude
		if d < bestDist then
			best, bestDist = cf, d
		end
	end
	return best
end

local function onOccupant(p: Player, state: CarState)
	local humanoid = state.Seat.Occupant
	if humanoid then
		local rider = Players:GetPlayerFromCharacter(humanoid.Parent)
		if rider ~= p then
			-- fremder Insasse: sofort aussetzen
			humanoid.Sit = false
			local weld = state.Seat:FindFirstChild("SeatWeld")
			if weld then
				weld:Destroy()
			end
			return
		end
		state.Occupied = true
		state.ExitAt = nil
		state.Strikes = 0
		setParked(state, false)
		setOwner(state, p)
		allowance(p, state.Cap)
		if state.Prompt then
			state.Prompt.Enabled = false
		end
		if not drivenOnce[p] then
			drivenOnce[p] = true
			call("MetricsService", "Funnel", p, 12, "CarDriven")
		end
	else
		if state.Occupied then
			state.Occupied = false
			state.ExitAt = os.clock()
			if present(p) then
				allowance(p, nil)
				call("AntiCheatService", "Grace", p, "Impulse", 1.5, state.Cap * 1.3)
			end
			setOwner(state, nil)
		end
		if state.Prompt then
			state.Prompt.Enabled = true
		end
	end
end

local function addEnterPrompt(p: Player, state: CarState, car: any)
	local body = state.Model:FindFirstChild("Body")
	if not body or not body:IsA("BasePart") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EnterPrompt"
	prompt.ActionText = Lang.T("en", "car.enter")
	prompt.ObjectText = Lang.Pick("en", car.Name)
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("TextKey", "car.enter")
	prompt:SetAttribute("Action", "CarEnter")
	prompt:SetAttribute("Owner", p.UserId)
	prompt.Enabled = false
	prompt.Parent = body
	state.Prompt = prompt
end

local function addTrail(model: Model, rig: any)
	local chassis = rig.Chassis
	local size = chassis.Size
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailA"
	a0.Position = Vector3.new(-size.X / 2, -0.2, size.Z / 2)
	a0.Parent = chassis
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailB"
	a1.Position = Vector3.new(size.X / 2, -0.2, size.Z / 2)
	a1.Parent = chassis
	local trail = Instance.new("Trail")
	trail.Name = "NeonTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.5
	trail.MinLength = 0.2
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(Color3.fromRGB(79, 140, 255), Color3.fromRGB(179, 107, 255))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	trail.Texture = "rbxasset://textures/gradient.png"
	trail.FaceCamera = true
	trail.Parent = chassis
	model:SetAttribute("Trail", true)
end

function VehicleService.Spawn(p: Player, key: string): (boolean, string?)
	if not present(p) then
		return false, "car.noCharacter"
	end
	local car = VC.Car(key)
	if not car then
		return false, "car.unknown"
	end
	if not VehicleService.Owns(p, key) then
		return false, "car.notOwned"
	end
	local data = dataOf(p)
	if not data then
		return false, "core.loading"
	end
	local character = p.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return false, "car.noCharacter"
	end
	if not groupsReady then
		registerGroups()
	end
	VehicleService.Despawn(p)
	-- fremden Sitz (Terminal-Hocker …) verlassen
	local seatPart = humanoid.SeatPart
	if seatPart then
		local weld = seatPart:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		humanoid.Sit = false
	end

	local tune = currentTune(data, key)
	local okBuild, model = pcall(VehicleModels.Build, key, tune.Paint, tune.Rims, tune.Glow)
	if not okBuild or typeof(model) ~= "Instance" then
		logError("Build " .. key, model)
		return false, "core.error"
	end
	local carModel = model :: Model
	VehicleModels.ApplyTune(carModel, key, tune)
	local cf = spawnCFrame(p, root)
	carModel:PivotTo(cf + Vector3.new(0, 0.35, 0))
	local okRig, rig = pcall(VehicleModels.Rig, carModel, key)
	if not okRig then
		logError("Rig " .. key, rig)
		carModel:Destroy()
		return false, "core.error"
	end
	local cap = VC.Cap(key)
	carModel.Name = "Car_" .. p.UserId
	carModel:SetAttribute("Owner", p.UserId)
	carModel:SetAttribute("Cap", cap)
	pcall(function()
		carModel.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- nie ein Auto ohne Räder auf dem Client
	end)
	local state: CarState = {
		Key = key,
		Model = carModel,
		Rig = rig,
		Seat = rig.Seat,
		Prompt = nil,
		Cap = cap,
		Occupied = false,
		ExitAt = os.clock(),
		Strikes = 0,
		OwnerBackAt = nil,
		Parked = false,
		LastPos = nil,
		DriveAcc = 0,
		Conns = {},
	}
	addEnterPrompt(p, state, car)
	if car.Trail then
		addTrail(carModel, rig)
	end
	carModel.Parent = folder()
	active[p] = state
	table.insert(
		state.Conns,
		state.Seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			local ok, err = pcall(onOccupant, p, state)
			if not ok then
				logError("Occupant", err)
			end
		end)
	)
	table.insert(
		state.Conns,
		carModel.AncestryChanged:Connect(function()
			if not carModel:IsDescendantOf(workspace) and active[p] == state then
				VehicleService.Despawn(p)
			end
		end)
	)
	garageOf(data).Active = key
	-- einsteigen: AntiCheat vorwarnen, dann setzen
	call("AntiCheatService", "NoteTeleport", p, state.Seat.CFrame)
	local okSit, sitErr = pcall(function()
		state.Seat:Sit(humanoid)
	end)
	if not okSit then
		logError("Sit", sitErr)
	end
	markDirty(p)
	return true, nil
end

function VehicleService.Active(p: Player): Model?
	local state = active[p]
	if state and state.Model.Parent then
		return state.Model
	end
	return nil
end

-- ---------------------------------------------------------------------
-- 6) TEMPO-PRÜFUNG, DESPAWN-TIMER, STRECKE (5 Hz)
-- ---------------------------------------------------------------------
local function trackDrive(p: Player, state: CarState, studs: number)
	state.DriveAcc += studs
	if state.DriveAcc >= DRIVE_TRACK_STUDS then
		local amount = math.floor(state.DriveAcc)
		state.DriveAcc -= amount
		local data = dataOf(p)
		if data and type(data.Stats) == "table" and Util.IsFinite(data.Stats.Drive) then
			data.Stats.Drive = math.min(data.Stats.Drive + amount, 9e15)
		end
		call("RewardService", "Track", p, "Drive", amount, { Car = state.Key })
	end
end

local function checkCar(p: Player, state: CarState, now: number)
	local model = state.Model
	local chassis = state.Rig and state.Rig.Chassis
	if not model.Parent or not chassis or not chassis.Parent then
		VehicleService.Despawn(p)
		return
	end
	local check = VC.SpeedCheck or {}
	if chassis.Position.Y < (check.FallY or -60) then
		VehicleService.Despawn(p)
		return
	end
	if not state.Occupied then
		local exitAt = state.ExitAt or now
		if now - exitAt >= (VC.DespawnSeconds or 60) then
			VehicleService.Despawn(p)
			return
		end
		if now - exitAt >= PARK_ANCHOR_AFTER and chassis.AssemblyLinearVelocity.Magnitude < 2 then
			setParked(state, true)
		end
		state.LastPos = nil
		return
	end
	-- Besitz nach einem Zurücksetzen zurückgeben
	if state.OwnerBackAt and now >= state.OwnerBackAt then
		state.OwnerBackAt = nil
		setOwner(state, p)
	end
	local velocity = chassis.AssemblyLinearVelocity
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = horizontal.Magnitude
	local limit = state.Cap * (check.Factor or 1.3)
	if speed > limit then
		state.Strikes += 1
		if state.Strikes >= (check.Strikes or 2) then
			state.Strikes = 0
			setOwner(state, nil)
			state.OwnerBackAt = now + (check.OwnerBack or 0.6)
			local clamped = horizontal.Unit * state.Cap
			pcall(function()
				chassis.AssemblyLinearVelocity = Vector3.new(clamped.X, math.min(velocity.Y, 0), clamped.Z)
				chassis.AssemblyAngularVelocity = Vector3.zero
			end)
			local weights = Config.Security and Config.Security.Weights or {}
			call("AntiCheatService", "Add", p, "Car", weights.Car or 4, {
				Speed = math.floor(speed),
				Cap = state.Cap,
				Car = state.Key,
			})
			if now - (resetNotifyAt[p] or -math.huge) >= RESET_NOTIFY_GAP then
				resetNotifyAt[p] = now
				call("PlayerStateService", "Notify", p, "car.speedReset", nil, "Error")
			end
		end
	else
		state.Strikes = 0
	end
	local pos = chassis.Position
	local last = state.LastPos
	if last then
		local moved = Vector3.new(pos.X - last.X, 0, pos.Z - last.Z).Magnitude
		if moved < state.Cap * 1.5 then -- Sprünge (Teleport, Zurücksetzen) zählen nicht
			trackDrive(p, state, moved)
		end
	end
	state.LastPos = pos
end

local function checkAll(_dt: number)
	local now = os.clock()
	for p, state in pairs(active) do
		if not present(p) then
			VehicleService.Despawn(p)
			continue
		end
		local ok, err = pcall(checkCar, p, state, now)
		if not ok then
			logError("Check", err)
		end
	end
end

-- ---------------------------------------------------------------------
-- 7) STATE "Garage" + REQUEST-HANDLER
-- ---------------------------------------------------------------------
local function garageState(p: Player): { [string]: any }
	local data = dataOf(p)
	if not data then
		return {
			Cars = { LamCity = true },
			Active = "LamCity",
			Tune = {},
			Slots = VC.GarageBase or 6,
			Used = 1,
			Spawned = "",
			Discount = false,
		}
	end
	local garage = garageOf(data)
	local cars: { [string]: boolean } = {}
	for key, owned in pairs(garage.Cars) do
		if owned == true and VC.Car(key) then
			cars[key] = true
		end
	end
	for _, car in ipairs(VC.Cars or {}) do
		if not cars[car.Key] and VehicleService.Owns(p, car.Key) then
			cars[car.Key] = true
		end
	end
	local tune: { [string]: any } = {}
	for key in pairs(cars) do
		tune[key] = currentTune(data, key)
	end
	local state = active[p]
	return {
		Cars = cars,
		Active = garage.Active,
		Tune = tune,
		Slots = slotsFor(data, hasPass(p, "MegaGarage")),
		Used = usedSlots(data),
		Spawned = if state then state.Key else "",
		Discount = hasDiscount(p),
	}
end

local function handleSpawn(p: Player, arg: any): Reply
	if not exact(arg, { Key = "string" }, { "Key" }) then
		return fail(p, "core.invalid")
	end
	local car = VC.Car(arg.Key)
	if not car then
		return fail(p, "car.unknown")
	end
	local ok, reason = VehicleService.Spawn(p, arg.Key)
	if not ok then
		return fail(p, reason or "core.error")
	end
	return okReply(p, "car.spawned", { carName(p, car) })
end

local function handleDespawn(p: Player, arg: any): Reply
	if arg ~= nil and (type(arg) ~= "table" or next(arg) ~= nil) then
		return fail(p, "core.invalid")
	end
	if not active[p] then
		return fail(p, "car.noActive")
	end
	VehicleService.Despawn(p)
	return okReply(p, "car.despawned")
end

local function sourceReason(p: Player, car: any): Reply
	if car.Source == "Pass" then
		return fail(p, "car.passOnly")
	elseif car.Source == "Licence" then
		local name = tostring(car.Licence)
		local progression = Config.Progression
		local licences = type(progression) == "table" and progression.Licences or nil
		local entry = type(licences) == "table" and licences[car.Licence] or nil
		if type(entry) == "table" and type(entry.Name) == "table" then
			name = Lang.Pick(langOf(p), entry.Name)
		end
		return fail(p, "car.licenceOnly", { name })
	elseif car.Source == "Login" then
		return fail(p, "car.loginOnly", { car.LoginDay or 0 })
	elseif car.Source == "Season" then
		return fail(p, "car.seasonOnly", { car.Tier or 0 })
	elseif car.Source == "Starter" then
		return fail(p, "car.starterOnly")
	end
	return fail(p, "car.notForSale", { carName(p, car) })
end

local function handleBuy(p: Player, arg: any): Reply
	if not exact(arg, { Key = "string" }, { "Key" }) then
		return fail(p, "core.invalid")
	end
	local car = VC.Car(arg.Key)
	if not car then
		return fail(p, "car.unknown")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	local garage = garageOf(data)
	if garage.Cars[car.Key] == true or (car.Source == "Free") then
		return fail(p, "car.owned", { carName(p, car) })
	end
	if car.Source ~= "Shop" then
		return sourceReason(p, car)
	end
	local used, total = usedSlots(data), slotsFor(data, hasPass(p, "MegaGarage"))
	if used >= total then
		return fail(p, "car.garageFull", { used, total })
	end
	local price, saved = priceFor(car, hasDiscount(p))
	if price <= 0 or price >= 9e15 then
		return fail(p, "core.error")
	end
	local okDebit, debited = call("ShopService", "Debit", p, price, "Car")
	if not okDebit then
		return fail(p, "car.shopMissing")
	end
	if debited ~= true then
		local okBalance, balance = call("ShopService", "Balance", p)
		local missing = if okBalance and Util.IsFinite(balance) then math.max(0, price - balance) else price
		return fail(p, "car.noCredits", { credits(p, missing) })
	end
	garage.Cars[car.Key] = true
	markDirty(p)
	call("PlayerStateService", "Effect", p, "Reveal", 1, { Key = car.Key })
	call("RewardService", "Track", p, "CarBuy", 1, { Car = car.Key, Class = car.Class })
	if car.Class == "Hyper" then
		call("CommunityService", "Announce", "car.hyperAnnounce", { p.DisplayName, Lang.Pick("en", car.Name) })
	end
	if saved > 0 then
		return okReply(p, "car.boughtDiscount", { carName(p, car), credits(p, saved) })
	end
	return okReply(p, "car.bought", { carName(p, car) })
end

local function handleTune(p: Player, arg: any): Reply
	if
		not exact(
			arg,
			{ Key = "string", Paint = "string", Rims = "string", Glow = "string", Spoiler = "boolean" },
			{ "Key" }
		)
	then
		return fail(p, "core.invalid")
	end
	local car = VC.Car(arg.Key)
	if not car then
		return fail(p, "car.unknown")
	end
	if not VehicleService.Owns(p, car.Key) then
		return fail(p, "car.notOwned")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	local current = currentTune(data, car.Key)
	local ok, reason, result, price = evaluateTune(car.Key, current, {
		Paint = arg.Paint,
		Rims = arg.Rims,
		Glow = arg.Glow,
		Spoiler = arg.Spoiler,
	}, isVip(p), isClub(p))
	if not ok then
		return fail(p, reason or "car.tuneNothing")
	end
	if price > 0 then
		local okDebit, debited = call("ShopService", "Debit", p, price, "Tune")
		if not okDebit then
			return fail(p, "car.shopMissing")
		end
		if debited ~= true then
			local okBalance, balance = call("ShopService", "Balance", p)
			local missing = if okBalance and Util.IsFinite(balance) then math.max(0, price - balance) else price
			return fail(p, "car.noCredits", { credits(p, missing) })
		end
	end
	garageOf(data).Tune[car.Key] = result
	local state = active[p]
	if state and state.Key == car.Key and state.Model.Parent then
		pcall(VehicleModels.ApplyTune, state.Model, car.Key, result)
	end
	markDirty(p)
	call("RewardService", "Track", p, "CarTune", 1, { Car = car.Key })
	if price > 0 then
		return okReply(p, "car.tuned", { carName(p, car), credits(p, price) })
	end
	return okReply(p, "car.tunedFree", { carName(p, car) })
end

-- Einsteigen über den Prompt am eigenen Auto
local function onPrompt(prompt: ProximityPrompt, p: Player)
	if prompt:GetAttribute("Action") ~= "CarEnter" or not present(p) then
		return
	end
	local state = active[p]
	if not state or prompt:GetAttribute("Owner") ~= p.UserId or not prompt:IsDescendantOf(state.Model) then
		return
	end
	if state.Seat.Occupant ~= nil then
		return
	end
	local character = p.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end
	if (root.Position - state.Seat.Position).Magnitude > ENTER_DISTANCE then
		return
	end
	setParked(state, false)
	call("AntiCheatService", "NoteTeleport", p, state.Seat.CFrame)
	state.Seat:Sit(humanoid)
end

-- ---------------------------------------------------------------------
-- 8) LEBENSZYKLUS
-- ---------------------------------------------------------------------
local function onPlayerAdded(p: Player)
	p.CharacterAdded:Connect(function(character: Model)
		onCharacter(p, character)
	end)
	if p.Character then
		onCharacter(p, p.Character)
	end
end

local function onPlayerRemoving(p: Player)
	VehicleService.Despawn(p)
	active[p] = nil
	clearCharacterConns(p)
	resetNotifyAt[p] = nil
	drivenOnce[p] = nil
end

local function onProfileLoaded(p: Player, data: { [string]: any })
	local garage = garageOf(data)
	-- unbekannte/kaputte Einträge nicht löschen (künftige Autos), nur Typen reparieren
	for key, owned in pairs(garage.Cars) do
		if type(key) ~= "string" or type(owned) ~= "boolean" then
			garage.Cars[key] = nil
		end
	end
	garage.Cars.LamCity = true
	if VC.Car(garage.Active) == nil then
		garage.Active = "LamCity"
	end
	for key, tune in pairs(garage.Tune) do
		if type(key) ~= "string" or type(tune) ~= "table" then
			garage.Tune[key] = nil
		end
	end
	markDirty(p)
end

function VehicleService.Init(services: any)
	Services = services
	registerGroups() -- §C11.3: vor jedem Spawn
	local pss = Services.PlayerStateService
	if type(pss) ~= "table" then
		warn(PREFIX .. "PlayerStateService fehlt – keine Anfragen/State")
		return
	end
	pss.Provide("Garage", garageState)
	pss.Handle("CarSpawn", handleSpawn, { Rate = 1, Per = 3 })
	pss.Handle("CarDespawn", handleDespawn, { Rate = 1, Per = 3 })
	pss.Handle("CarBuy", handleBuy, { Rate = 2, Per = 1 })
	pss.Handle("CarTune", handleTune, { Rate = 2, Per = 1 })
end

function VehicleService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, p)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	call("DataService", "OnProfileLoaded", onProfileLoaded)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, p: Player)
		local ok, err = pcall(onPrompt, prompt, p)
		if not ok then
			logError("Prompt", err)
		end
	end)
	Scheduler.Every("VehicleCheck", (VC.SpeedCheck and VC.SpeedCheck.Hz) or 5, checkAll)
end

-- Reine Helfer für WorldTests (keine Spieler nötig)
VehicleService._Test = {
	GarageLevels = garageLevels,
	SlotsFor = slotsFor,
	UsedSlots = usedSlots,
	PriceFor = priceFor,
	EvaluateTune = evaluateTune,
	TuneDefaults = tuneDefaults,
	CurrentTune = currentTune,
	Exact = exact,
	GroupsReady = function(): boolean
		return groupsReady
	end,
}

return VehicleService
