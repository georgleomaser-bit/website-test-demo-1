-- =====================================================================
--  AKYTEX TYCOON – Selbsttests Stadt, Grafik, Fahrzeuge (Server/Tests/WorldTests)
--  Besitzer: WP7 (Stadt, Grafik, Fahrzeuge). Vertrag: DESIGN.md §D WP7 "Tests" (Teilezahl, Anker vorhanden, Plot-Seiten 10,
--  Kollisionsgruppen-Matrix, Routen geschlossen), §C17 (SelfTest), §B3 (Teilebudget ≤ 12.000), §C11.3, §B12.1.
--  SelfTestService lädt dieses Modul; jeder Fehler (error/assert) = FAIL. Tests warten höchstens 60 s auf den Stadtbau.
--  Keine Spieler nötig: Fahrzeug-Regeln über VehicleService._Test, Modelle über Shared/VehicleModels (ohne Workspace).
-- =====================================================================

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config")) :: any
local Lang = require(Shared:WaitForChild("Lang")) :: any
local VehicleModels = require(Shared:WaitForChild("VehicleModels")) :: any

local READY_WAIT = 60
local ANCHORS = {
	"Bell",
	"BellZone",
	"TowerTour",
	"Showroom",
	"Boutique",
	"Helipad",
	"Marina",
	"Lookout",
	"PressScreen",
	"IpoWall",
	"HallOfFame",
	"Academy",
	"VipBalcony",
	"Rooftop",
	"Spawn",
}
local BOARDS = {
	"Wealth",
	"League",
	"Return",
	"Skyline",
	"Firm",
	"Respekt",
	"IpoWall",
	"PressScreen",
	"HallOfFame",
	"Hall1",
	"Hall2",
	"Hall3",
	"TowerTour",
}

local function eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(("%s erwartet %s, bekommen %s"):format(label or "Wert", tostring(expected), tostring(actual)), 2)
	end
end

local function near(actual: number, expected: number, tolerance: number, label: string?)
	if math.abs(actual - expected) > tolerance then
		error(("%s erwartet ≈%s, bekommen %s"):format(label or "Wert", tostring(expected), tostring(actual)), 2)
	end
end

local function truthy(value: any, label: string)
	if not value then
		error(label, 2)
	end
end

local function serviceModule(services: any, name: string): any
	local svc = services and services[name]
	if svc then
		return svc
	end
	local module = script.Parent.Parent:WaitForChild("Services"):FindFirstChild(name)
	assert(module and module:IsA("ModuleScript"), name .. " fehlt")
	return require(module) :: any
end

local function readyCity(services: any): any
	local city = serviceModule(services, "CityService")
	local started = os.clock()
	while not city.Ready() and os.clock() - started < READY_WAIT do
		task.wait(0.25)
	end
	truthy(city.Ready(), "Stadt nach 60 s nicht fertig gebaut")
	return city
end

local function newData(services: any): { [string]: any }
	return serviceModule(services, "DataService").DefaultData()
end

local Tests = {}

-- ---------------------------------------------------------------------
-- STADT
-- ---------------------------------------------------------------------
function Tests.CityPartBudget(services: any)
	local city = readyCity(services)
	local parts = city.PartCount()
	truthy(parts > 1000, "Stadt hat zu wenige Teile: " .. tostring(parts))
	truthy(
		parts <= Config.City.PartBudget,
		("Teilebudget überschritten: %d > %d"):format(parts, Config.City.PartBudget)
	)
	truthy(Config.City.PartBudget <= 12000, "PartBudget > 12.000 (§B3)")
	truthy(Config.City.BuildPerFrame <= 400, "BuildPerFrame > 400 (§B3)")
end

function Tests.AnchorsPresent(services: any)
	local city = readyCity(services)
	local folder = city.Folder()
	truthy(folder, "Stadt-Ordner fehlt")
	local found: { [string]: boolean } = {}
	for _, inst in ipairs(folder:GetDescendants()) do
		local name = inst:GetAttribute("Anchor")
		if type(name) == "string" then
			found[name] = true
		end
	end
	for _, name in ipairs(ANCHORS) do
		local cf = city.Anchor(name)
		truthy(typeof(cf) == "CFrame", "Anker fehlt: " .. name)
		truthy(found[name], "Anker-Teil mit Attribut fehlt: " .. name)
	end
	for _, anchorName in pairs(Config.City.Shops) do
		truthy(typeof(city.Anchor(anchorName)) == "CFrame", "Laden-Anker fehlt: " .. anchorName)
	end
	near(city.Anchor("Spawn").Position.Y, Config.City.Levels.Walk, 0.01, "Spawn-Fußpunkt")
	eq(city.Anchor("Unbekannt"), nil, "unbekannter Anker")
end

function Tests.PlotSites10(services: any)
	local city = serviceModule(services, "CityService")
	local plots = Config.City.Plots
	eq(plots.Count, 10, "Plots")
	local seen: { Vector3 } = {}
	for k = 1, plots.Count do
		local cf = city.PlotSite(k)
		truthy(typeof(cf) == "CFrame", "PlotSite " .. k)
		local pos = cf.Position
		near(Vector3.new(pos.X, 0, pos.Z).Magnitude, plots.Radius, 0.5, "Plot-Radius " .. k)
		local deg = math.deg(math.atan2(pos.Z, pos.X)) % 360
		local expected = (plots.StartAngle + (k - 1) * plots.Step) % 360
		near(((deg - expected + 180) % 360) - 180, 0, 0.5, "Plot-Winkel " .. k)
		local toCenter = (Vector3.new(0, pos.Y, 0) - pos).Unit
		truthy(cf.LookVector:Dot(toCenter) > 0.99, "Plot " .. k .. " blickt nicht zur Plaza")
		for _, other in ipairs(seen) do
			truthy((other - pos).Magnitude > plots.Size, "Plots überlappen")
		end
		table.insert(seen, pos)
		near((Config.City.PlotCFrame(k).Position - pos).Magnitude, 0, 0.01, "PlotCFrame == PlotSite " .. k)
	end
	local okPlot, plotService = pcall(serviceModule, services, "PlotService")
	if okPlot and type(plotService) == "table" and type(plotService.PlotCFrame) == "function" then
		for k = 1, plots.Count do
			near(
				(plotService.PlotCFrame(k).Position - city.PlotSite(k).Position).Magnitude,
				0,
				0.01,
				"PlotService " .. k
			)
		end
	end
end

function Tests.CollisionMatrix(services: any)
	local vehicleService = serviceModule(services, "VehicleService")
	truthy(vehicleService._Test.GroupsReady(), "Kollisionsgruppen nicht registriert")
	local function collidable(a: string, b: string): boolean
		return PhysicsService:CollisionGroupsAreCollidable(a, b)
	end
	for _, name in ipairs({ "Characters", "Cars", "World", "Pickups" }) do
		truthy(PhysicsService:IsCollisionGroupRegistered(name), "Gruppe fehlt: " .. name)
	end
	eq(collidable("Cars", "Characters"), false, "Cars×Characters")
	eq(collidable("Cars", "Cars"), false, "Cars×Cars")
	eq(collidable("Cars", "World"), true, "Cars×World")
	eq(collidable("Cars", "Default"), true, "Cars×Default")
	for _, other in ipairs({ "Default", "Characters", "Cars", "World", "Pickups" }) do
		eq(collidable("Pickups", other), false, "Pickups×" .. other)
	end
end

function Tests.RoutesClosed(services: any)
	local city = serviceModule(services, "CityService")
	for name, def in pairs(Config.City.Routes) do
		local points = city.Route(name)
		truthy(#points >= 9, "Route " .. name .. " zu kurz")
		near((points[1] - points[#points]).Magnitude, 0, 0.001, "Route " .. name .. " geschlossen")
		local maxSeg = 0
		for i = 1, #points - 1 do
			maxSeg = math.max(maxSeg, (points[i + 1] - points[i]).Magnitude)
		end
		truthy(maxSeg < def.Spacing * 2, ("Route %s: Lücke %.1f"):format(name, maxSeg))
	end
	-- Ring-Boulevard weicht dem Börsensaal aus (Mittellinie außerhalb Halle + Gehweg + halbe Fahrbahn)
	local ex = Config.City.Zones.Exchange
	local halfW = ex.Width / 2 + Config.City.Roads.Ring.Width / 2
	local back = ex.Center.Z - ex.Depth / 2 - Config.City.Roads.Ring.Width / 2
	local front = ex.Center.Z + ex.Depth / 2
	for _, p in ipairs(city.Route("Ring")) do
		local inside = math.abs(p.X) < halfW and p.Z > back and p.Z < front
		truthy(not inside, ("Ring-Punkt im Börsensaal: %.0f, %.0f"):format(p.X, p.Z))
	end
end

function Tests.BoardsShopsMonitors(services: any)
	local city = readyCity(services)
	for _, name in ipairs(BOARDS) do
		local part = city.BoardPart(name)
		truthy(part and part:IsA("BasePart"), "Board-Fläche fehlt: " .. name)
		eq(part:GetAttribute("Board"), name, "Board-Attribut " .. name)
	end
	for instId in pairs(Config.City.Shops) do
		local part = city.ShopPart(instId)
		truthy(part and part:IsA("BasePart"), "Laden-Front fehlt: " .. tostring(instId))
		eq(part:GetAttribute("Shop"), instId, "Laden-Attribut")
	end
	local kinds: { [string]: number } = {}
	local monitors = 0
	local shopTickers, windowsTagged, budgetLights = 0, 0, 0
	for _, inst in ipairs(city.Folder():GetDescendants()) do
		local monitor = inst:GetAttribute("Monitor")
		if monitor ~= nil and inst:IsA("BasePart") then
			monitors += 1
			if type(monitor) == "string" then
				kinds[monitor] = (kinds[monitor] or 0) + 1
			end
		end
		if inst:GetAttribute("ShopTicker") ~= nil then
			shopTickers += 1
		end
		if inst:GetAttribute("WindowLight") ~= nil then
			windowsTagged += 1
		end
		if inst:IsA("Light") and inst:GetAttribute("Budget") == true then
			budgetLights += 1
			eq(inst.Enabled, false, "Budget-Licht muss serverseitig aus sein")
		end
	end
	truthy(monitors >= 41, "zu wenige Monitor-Teile: " .. monitors)
	eq(kinds.Candles, 1, "Kerzentafel")
	eq(kinds.Heatmap, 1, "Heatmap-Wand")
	eq(kinds.Ticker, 4, "Ticker-Wände")
	eq(kinds.TickerRing, 16, "Tickerring")
	eq(kinds.Chart, 8, "Terminal-Pulte")
	eq(shopTickers, 6, "Laden-Ticker-Plätze")
	truthy(windowsTagged >= 36, "Fensterlicht-Teile fehlen")
	truthy(budgetLights > 50, "Laternen fehlen")
end

function Tests.ConfigValidate(_services: any)
	local cityErrors = Config.City.Validate(Config)
	eq(#cityErrors, 0, "Config.City.Validate: " .. tostring(cityErrors[1]))
	local carErrors = Config.Vehicles.Validate(Config)
	eq(#carErrors, 0, "Config.Vehicles.Validate: " .. tostring(carErrors[1]))
end

-- ---------------------------------------------------------------------
-- FAHRZEUGE
-- ---------------------------------------------------------------------
function Tests.ClassCaps(_services: any)
	local expected = { Kompakt = 60, Limousine = 75, Sport = 95, Super = 120, Hyper = 150 }
	for class, cap in pairs(expected) do
		eq(Config.Vehicles.Classes[class], cap, "Klasse " .. class)
	end
	eq(#Config.Vehicles.Cars, 16, "16 Autos")
	for _, car in ipairs(Config.Vehicles.Cars) do
		eq(Config.Vehicles.Cap(car.Key), expected[car.Class], "Deckel " .. car.Key)
		truthy(VehicleModels.Recipes[car.Recipe] ~= nil, "Bauplan fehlt: " .. car.Key)
		truthy(Lang.Pick("de", car.Name) ~= "" and Lang.Pick("en", car.Name) ~= "", "Name fehlt: " .. car.Key)
	end
	eq(Config.Vehicles.Cap("Lam1"), 150, "Λ-1 nie schneller als Hyper")
	truthy(Config.Vehicles.Boost.Mult < Config.Vehicles.SpeedCheck.Factor, "Boost unter Prüf-Grenze")
end

function Tests.VehicleModelsBuild(_services: any)
	for _, car in ipairs(Config.Vehicles.Cars) do
		local model = VehicleModels.Build(car.Key)
		truthy(model:IsA("Model"), "Build " .. car.Key)
		local chassis = model:FindFirstChild("Chassis")
		truthy(chassis and model.PrimaryPart == chassis, "Chassis " .. car.Key)
		local seat = model:FindFirstChild("Seat")
		truthy(seat and seat:IsA("VehicleSeat"), "VehicleSeat " .. car.Key)
		eq((seat :: VehicleSeat).CanTouch, false, "Sitz nur per Prompt")
		local parts = 0
		for _, inst in ipairs(model:GetDescendants()) do
			if inst:IsA("BasePart") then
				parts += 1
			end
		end
		truthy(parts <= 60, ("%s: %d Teile (> 60)"):format(car.Key, parts))
		for _, wheel in ipairs({ "FL", "FR", "RL", "RR" }) do
			truthy(model:FindFirstChild("Wheel_" .. wheel), car.Key .. " Rad " .. wheel)
		end
		-- Lack + Spoiler live umschaltbar
		local body = model:FindFirstChild("Body") :: BasePart
		VehicleModels.ApplyTune(model, car.Key, { Paint = "Red", Spoiler = true, Glow = "Blue", Rims = "NeonBlue" })
		if body:GetAttribute("Paint") == true then
			eq(body.Color, Config.Vehicles.Option("Paint", "Red").Color, car.Key .. " Lack")
		end
		eq(model:GetAttribute("Spoiler"), true, car.Key .. " Spoiler an")
		eq(model:GetAttribute("Glow"), "Blue", car.Key .. " Unterbodenlicht")
		VehicleModels.ApplyTune(model, car.Key, { Spoiler = false, Glow = "Off" })
		eq(model:GetAttribute("Spoiler"), false, car.Key .. " Spoiler aus")
		local light = (chassis :: Instance):FindFirstChild("Underglow")
		truthy(light and light:GetAttribute("Budget") == false, car.Key .. " Unterbodenlicht aus = kein Budget")
		model:Destroy()
	end
end

function Tests.VehicleRig(_services: any)
	local model = VehicleModels.Build("QuasarX")
	-- Drehpunkt = Bodenmitte: PivotTo auf den Spawnpunkt setzt die Räder auf den Boden
	truthy(math.abs(model:GetPivot().Position.Y) < 0.01, "Drehpunkt auf Bodenhöhe")
	model:PivotTo(CFrame.new(0, 500, 0))
	local rig = VehicleModels.Rig(model, "QuasarX")
	local motors, steer = 0, 0
	for _ in pairs(rig.Motors) do
		motors += 1
	end
	for _ in pairs(rig.Steer) do
		steer += 1
	end
	eq(motors, 4, "4 Rad-Motoren")
	eq(steer, 2, "Servo-Lenkung vorn")
	eq(#rig.Springs, 4, "4 Federn")
	truthy(rig.Mass > 0, "Masse")
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			eq(inst.CollisionGroup, "Cars", "Kollisionsgruppe " .. inst.Name)
			eq(inst.Anchored, false, "gelöst " .. inst.Name)
		end
	end
	for _, motor in pairs(rig.Motors) do
		eq(motor.ActuatorType, Enum.ActuatorType.Motor, "Motor")
	end
	for _, servo in pairs(rig.Steer) do
		eq(servo.ActuatorType, Enum.ActuatorType.Servo, "Servo")
	end
	model:Destroy()
end

function Tests.GarageRules(services: any)
	local helpers = serviceModule(services, "VehicleService")._Test
	local data = newData(services)
	eq(helpers.SlotsFor(data, false), Config.Vehicles.GarageBase, "Grund-Plätze")
	data.Tower.Floors = {
		{ R = "Garage", L = 1, S = {}, D = {} },
		{ R = "Office", L = 1, S = {}, D = {} },
		{ R = "Garage", L = 1, S = {}, D = {} },
		{ R = "Garage", L = 1, S = {}, D = {} },
	}
	eq(helpers.GarageLevels(data), Config.Vehicles.GarageLevelsMax, "Garagen-Ebenen gedeckelt")
	local withLevels = Config.Vehicles.GarageBase + Config.Vehicles.GarageLevelsMax * Config.Vehicles.GarageLevelSlots
	eq(helpers.SlotsFor(data, false), withLevels, "Plätze mit Ebenen")
	eq(helpers.SlotsFor(data, true), withLevels + Config.Vehicles.MegaGarageSlots, "Mega-Garage")
	eq(helpers.UsedSlots(data), 1, "Gratis-Auto belegt einen Platz")
	-- Aktionärs-Rabatt nur auf Velocitra-Autos
	local velocitra = Config.Vehicles.Car("VelocitraS")
	local price, saved = helpers.PriceFor(velocitra, true)
	eq(saved, math.floor(velocitra.Price * Config.Vehicles.ShareholderDiscount.Pct), "Rabatt")
	eq(price, velocitra.Price - saved, "Endpreis")
	local stratos = Config.Vehicles.Car("Stratos")
	local p2, s2 = helpers.PriceFor(stratos, true)
	eq(s2, 0, "kein Rabatt für andere Marken")
	eq(p2, stratos.Price, "voller Preis")
	-- Tuning
	local current = helpers.TuneDefaults("Stratos")
	local ok, reason = helpers.EvaluateTune("Stratos", current, {}, false, false)
	eq(ok, false, "keine Änderung")
	eq(reason, "car.tuneNothing", "Grund keine Änderung")
	local okVip, reasonVip = helpers.EvaluateTune("Stratos", current, { Paint = "Platin" }, false, false)
	eq(okVip, false, "VIP-Lack gesperrt")
	eq(reasonVip, "car.tuneVip", "Grund VIP")
	local okClub, reasonClub = helpers.EvaluateTune("Stratos", current, { Paint = "ClubNoir" }, true, false)
	eq(okClub, false, "Club-Lack gesperrt")
	eq(reasonClub, "car.tuneClub", "Grund Club")
	local okPaint, _, result, cost =
		helpers.EvaluateTune("Stratos", current, { Paint = "BlueM", Glow = "Cyan" }, false, false)
	eq(okPaint, true, "Lack + Unterboden")
	eq(result.Paint, "BlueM", "neuer Lack")
	eq(
		cost,
		Config.Vehicles.TunePrice("Stratos", "Paint", "BlueM") + Config.Vehicles.TunePrice("Stratos", "Glow", "Cyan"),
		"Tuning-Preis"
	)
	truthy(cost % 1 == 0 and cost > 0 and cost < 1e14, "Tuning-Preis ganzzahlig")
	local okOff, _, _, costOff = helpers.EvaluateTune(
		"Stratos",
		{ Paint = current.Paint, Rims = current.Rims, Glow = "Cyan", Spoiler = true },
		{ Glow = "Off", Spoiler = false },
		false,
		false
	)
	eq(okOff, true, "ausschalten erlaubt")
	eq(costOff, 0, "ausschalten kostet nichts")
	local okBad, reasonBad = helpers.EvaluateTune("Stratos", current, { Rims = "Gibtsnicht" }, false, false)
	eq(okBad, false, "unbekannte Felge")
	eq(reasonBad, "car.tuneUnknown", "Grund unbekannt")
end

function Tests.RequestKeys(services: any)
	local exact = serviceModule(services, "VehicleService")._Test.Exact
	eq(exact({ Key = "LamCity" }, { Key = "string" }, { "Key" }), true, "gültig")
	eq(exact({ Key = "LamCity", Extra = 1 }, { Key = "string" }, { "Key" }), false, "fremder Schlüssel")
	eq(exact({ Key = 5 }, { Key = "string" }, { "Key" }), false, "falscher Typ")
	eq(exact({}, { Key = "string" }, { "Key" }), false, "Pflichtfeld fehlt")
	eq(exact({ Key = string.rep("x", 40) }, { Key = "string" }, { "Key" }), false, "zu lang")
	eq(exact("LamCity", { Key = "string" }, { "Key" }), false, "keine Tabelle")
	eq(exact({ Key = "Stratos", Spoiler = true }, { Key = "string", Spoiler = "boolean" }, { "Key" }), true, "Spoiler")
end

function Tests.LangKeys(_services: any)
	for _, key in ipairs({
		"car.spawned",
		"car.bought",
		"car.garageFull",
		"car.noCredits",
		"car.tuned",
		"car.reveal.title",
		"car.reveal.drive",
		"car.speedReset",
		"car.enter",
		"car.hyperAnnounce",
		"world.prompt.terminal",
		"world.prompt.helipadFly",
		"world.clubOnly",
	}) do
		truthy(Lang.Has(key), "Lang-Schlüssel fehlt: " .. key)
	end
	for _, source in pairs({ "Free", "Shop", "Starter", "Login", "Licence", "Season", "Pass" }) do
		truthy(Lang.Has("car.source." .. source), "Herkunft ohne Text: " .. source)
	end
end

return Tests
