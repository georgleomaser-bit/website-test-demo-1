-- =====================================================================
--  AKYTEX TYCOON – Garage, Autohaus, Tuning, Enthüllung (Client/Modules/Garage)
--  Besitzer: WP7 (Stadt, Grafik, Fahrzeuge). Vertrag: DESIGN.md §B12.1 (16 Autos, Garage-Plätze, Tuning 24 Lacke · 8 Felgen
--  · 6 Unterboden-Farben · Spoiler, Aktionärs-Rabatt), §A7 #10 (Drehteller-Enthüllung, Fahrt direkt auf den Autobahnring),
--  §C7.3 (Fenster "Garage"), §C7.4 (Effekt "Reveal" {Key} – Besitzer dieses Modul), §C7.5 (Garage.Open), §C9 (CarSpawn,
--  CarDespawn, CarBuy, CarTune), §C10 (State "Garage"), §0 Regel 17 (keine Kauf-Druck-Texte; Pass-Auto nur "Ansehen").
--
--  Fenster: oben eine 3D-Vorschau (ViewportFrame, Kamera kreist über verkettete Tweens – kein eigener Frame-Loop) mit
--  Name, Klasse, Spitze, Preis/Herkunft und Aktionen; darunter Reiter "Meine Autos" / "Autohaus" / "Tuning".
--  Tuning zeigt den Preis vorab (gleiche Formel wie der Server: Config.Vehicles.TunePrice) und färbt die Vorschau live.
--  Enthüllung: Glas-Overlay mit Drehteller-Bühne, "Losfahren" holt das Auto (CarSpawn); Hypercars bekommen danach einen
--  Navi-Strahl zur nächsten Autobahn-Auffahrt (Vehicles.Waypoint).
--
--  Öffentliche API (§C7.5):
--    Garage.Open()            öffnet das Fenster "Garage"
--  Zusätzlich: Garage.Select(key) · Garage.Tick() · Garage.Init(ctx) · Garage.Start()
-- =====================================================================

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent:WaitForChild("UI"))
local VehicleModels = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("VehicleModels")) :: any

local Garage = {}

local player = Players.LocalPlayer
local Theme = UI.Theme

type Preview = {
	Viewport: ViewportFrame,
	Camera: Camera,
	Model: Model?,
	Key: string?,
	Token: number,
	Radius: number,
}

local ctx: any = nil
local VC: any = {}
local window: any = nil
local builtLang: string? = nil
local tab = "Mine"
local pendingTab: string? = nil
local selected: string? = nil
local draft: { [string]: any }? = nil
local draftKey: string? = nil
local lastStateSig = ""

local preview: Preview? = nil
local infoName: TextLabel? = nil
local infoMeta: TextLabel? = nil
local infoPrice: TextLabel? = nil
local infoHint: TextLabel? = nil
local classChipHolder: Frame? = nil
local actionRow: Frame? = nil
local slotsLabel: TextLabel? = nil
local segmented: any = nil
local body: Frame? = nil

local ORBIT_STEPS = 12
local ORBIT_SECONDS = 14
local WINDOW_W, WINDOW_H = 780, 600
local CARD_W, CARD_H = 168, 104

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function T(key: string, ...: any): string
	return ctx.T(key, ...)
end

local function call(name: string, fnName: string, ...: any): (boolean, any)
	local modules = ctx and ctx.Modules
	local m = modules and modules[name]
	local fn = m and m[fnName]
	if type(fn) ~= "function" then
		return false, nil
	end
	return pcall(fn, ...)
end

local function reducedFx(): boolean
	local ok, settings = call("Settings", "Get")
	return ok and type(settings) == "table" and settings.ReducedFx == true
end

local function garageState(): { [string]: any }
	local state = ctx.State and ctx.State.Garage
	if type(state) == "table" then
		return state
	end
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

local function credits(): number
	local value = ctx.State and ctx.State.Credits
	return if type(value) == "number" then value else 0
end

local function formatCredits(n: number): string
	local ok, text = pcall(ctx.Format.Credits, n, ctx.Lang_())
	return if ok then text .. " " .. T("core.cr") else tostring(n)
end

local function pick(pair: any): string
	if type(pair) ~= "table" then
		return tostring(pair)
	end
	return ctx.Lang.Pick(ctx.Lang_(), pair)
end

local function owns(key: string): boolean
	local cars = garageState().Cars
	return type(cars) == "table" and cars[key] == true
end

local function classColor(class: string): Color3
	local info = VC.ClassInfo and VC.ClassInfo[class]
	return if info and typeof(info.Color) == "Color3" then info.Color else Theme.Accent
end

local function className(class: string): string
	local info = VC.ClassInfo and VC.ClassInfo[class]
	return if info then pick(info.Name) else class
end

local function tuneOf(key: string): { [string]: any }
	local tune = garageState().Tune
	local entry = type(tune) == "table" and tune[key] or nil
	if type(entry) == "table" then
		return table.clone(entry)
	end
	local car = VC.Car(key)
	local recipe = car and VehicleModels.Recipes[car.Recipe] or nil
	return {
		Paint = if car then car.Paint else "Polar",
		Rims = VC.DefaultRims or "Stock",
		Glow = VC.GlowOff or "Off",
		Spoiler = if recipe then recipe.Spoiler == true else false,
	}
end

local function sourceText(car: any): string
	local source = car.Source
	if source == "Login" then
		return T("car.source.Login", car.LoginDay or 0)
	elseif source == "Season" then
		return T("car.source.Season", car.Tier or 0)
	elseif source == "Licence" then
		local progression = ctx.Config.Progression
		local licences = type(progression) == "table" and progression.Licences or nil
		local entry = type(licences) == "table" and licences[car.Licence] or nil
		local name = if type(entry) == "table" and type(entry.Name) == "table"
			then pick(entry.Name)
			else tostring(car.Licence)
		return T("car.source.Licence", name)
	end
	return T("car.source." .. tostring(source))
end

local function priceOf(car: any): (number, number)
	local price = math.floor(car.Price or 0)
	local rule = VC.ShareholderDiscount
	if garageState().Discount == true and car.Maker == "Velocitra" and type(rule) == "table" then
		local saved = math.floor(price * (rule.Pct or 0))
		return price - saved, saved
	end
	return price, 0
end

-- ---------------------------------------------------------------------
-- 1) 3D-VORSCHAU (ViewportFrame + kreisende Kamera aus verketteten Tweens)
-- ---------------------------------------------------------------------
local function orbitCFrame(radius: number, step: number, height: number): CFrame
	local a = (step / ORBIT_STEPS) * 2 * math.pi + math.rad(35)
	local pos = Vector3.new(radius * math.cos(a), height, radius * math.sin(a))
	return CFrame.lookAt(pos, Vector3.new(0, 1.6, 0))
end

local function startOrbit(p: Preview, height: number)
	p.Token += 1
	local token = p.Token
	if reducedFx() then
		p.Camera.CFrame = orbitCFrame(p.Radius, 0, height)
		return
	end
	local step = 0
	p.Camera.CFrame = orbitCFrame(p.Radius, step, height)
	local info = TweenInfo.new(ORBIT_SECONDS / ORBIT_STEPS, Enum.EasingStyle.Linear)
	local function nextStep()
		if p.Token ~= token or not p.Viewport.Parent then
			return
		end
		step = (step + 1) % ORBIT_STEPS
		local tween = TweenService:Create(p.Camera, info, { CFrame = orbitCFrame(p.Radius, step, height) })
		tween.Completed:Once(nextStep)
		tween:Play()
	end
	nextStep()
end

local function stage(viewport: ViewportFrame)
	-- Drehteller-Bühne: dunkler Marmor + Neon-Ring
	local disc = Instance.new("Part")
	disc.Name = "Stage"
	disc.Shape = Enum.PartType.Cylinder
	disc.Anchored = true
	disc.Size = Vector3.new(0.6, 22, 22)
	disc.CFrame = CFrame.new(0, -0.3, 0) * CFrame.Angles(0, 0, math.pi / 2)
	disc.Color = Color3.fromRGB(21, 23, 28)
	disc.Material = Enum.Material.Marble
	disc.Parent = viewport
	local ring = Instance.new("Part")
	ring.Name = "StageRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.Size = Vector3.new(0.1, 22.4, 22.4)
	ring.CFrame = CFrame.new(0, -0.32, 0) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Color = Theme.Cosmic2
	ring.Material = Enum.Material.Neon
	ring.Parent = viewport
end

local function newPreview(parent: Instance, size: UDim2, position: UDim2?): Preview
	local viewport: ViewportFrame = UI.Create("ViewportFrame", {
		Name = "Preview",
		Size = size,
		Position = position or UDim2.new(),
		BackgroundColor3 = Theme.Bg2,
		BackgroundTransparency = 0,
		Ambient = Color3.fromRGB(150, 160, 185),
		LightColor = Color3.fromRGB(255, 248, 236),
		LightDirection = Vector3.new(-0.5, -1, -0.4),
		Parent = parent,
	}, { UI.Corner(12) })
	local camera = Instance.new("Camera")
	camera.FieldOfView = 34
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	stage(viewport)
	return { Viewport = viewport, Camera = camera, Model = nil, Key = nil, Token = 0, Radius = 28 }
end

local function showCar(p: Preview, key: string?, tune: { [string]: any }?)
	if p.Key ~= key then
		if p.Model then
			p.Model:Destroy()
			p.Model = nil
		end
		p.Key = key
		if key and VC.Car(key) then
			local ok, model = pcall(VehicleModels.Build, key)
			if ok and typeof(model) == "Instance" then
				local m = model :: Model
				m:PivotTo(CFrame.identity)
				m.Parent = p.Viewport
				p.Model = m
				local recipe = VehicleModels.Recipes[(VC.Car(key) :: any).Recipe]
				p.Radius = if recipe then math.max(20, recipe.L * 1.75) else 26
				startOrbit(p, if recipe then recipe.L * 0.42 else 6)
			end
		end
	end
	local model = p.Model
	if model and key then
		pcall(VehicleModels.ApplyTune, model, key, tune)
	end
end

-- ---------------------------------------------------------------------
-- 2) FENSTER-INHALT
-- ---------------------------------------------------------------------
local refresh: () -> () = function() end

-- Antwort als Toast zeigen (Server-Texte sind schon lokalisiert)
local function toast(reply: any): { [string]: any }
	if type(reply) ~= "table" then
		return { Ok = false }
	end
	if type(reply.Message) == "string" and reply.Message ~= "" then
		ctx.Toast(reply.Message, if reply.Ok then "Success" else "Error")
	end
	return reply
end

local function clear(frame: Instance)
	for _, child in ipairs(frame:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIGridLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function setDraft(key: string?)
	draftKey = key
	draft = if key then tuneOf(key) else nil
end

local function selectCar(key: string)
	if not VC.Car(key) then
		return
	end
	selected = key
	setDraft(key)
	refresh()
end

local function buildActions(car: any)
	local row = actionRow
	if not row then
		return
	end
	clear(row)
	local key = car.Key
	local state = garageState()
	if owns(key) then
		if state.Spawned == key then
			UI.Button({
				Text = T("car.despawn"),
				Size = UDim2.fromOffset(150, 38),
				Variant = "Secondary",
				LayoutOrder = 1,
				Parent = row,
			}, function()
				toast(ctx.RequestFull("CarDespawn", {}, true))
			end)
		else
			UI.Button({
				Text = T("car.spawn"),
				Size = UDim2.fromOffset(150, 38),
				Variant = "Primary",
				LayoutOrder = 1,
				Parent = row,
			}, function()
				local reply = toast(ctx.RequestFull("CarSpawn", { Key = key }, true))
				if reply.Ok and window then
					ctx.Windows.Close("Garage")
				end
			end)
		end
		UI.Button({
			Text = T("car.tab.tune"),
			Size = UDim2.fromOffset(120, 38),
			Variant = "Secondary",
			LayoutOrder = 2,
			Parent = row,
		}, function()
			tab = "Tune"
			if segmented then
				segmented.Set("Tune", true)
			end
			refresh()
		end)
	elseif car.Source == "Shop" then
		local price = priceOf(car)
		local full = (state.Used or 0) >= (state.Slots or 6)
		local affordable = credits() >= price
		UI.Button({
			Text = T("car.buy") .. " · " .. formatCredits(price),
			Size = UDim2.fromOffset(196, 38),
			Variant = if affordable and not full then "Primary" else "Muted",
			LayoutOrder = 1,
			Parent = row,
		}, function()
			toast(ctx.RequestFull("CarBuy", { Key = key }, true))
		end)
		if state.Spawned == key and state.Test == true then
			UI.Button({
				Text = T("car.despawn"),
				Size = UDim2.fromOffset(132, 38),
				Variant = "Secondary",
				LayoutOrder = 2,
				Parent = row,
			}, function()
				toast(ctx.RequestFull("CarDespawn", {}, true))
			end)
		else
			-- Probefahrt (nur am Autohaus; der Server prüft Ort und Cooldown)
			UI.Button({
				Text = T("car.testDrive"),
				Size = UDim2.fromOffset(132, 38),
				Variant = "Secondary",
				LayoutOrder = 2,
				Parent = row,
			}, function()
				local reply = toast(ctx.RequestFull("CarSpawn", { Key = key, Test = true }, true))
				if reply.Ok and window then
					ctx.Windows.Close("Garage")
				end
			end)
		end
	elseif car.Source == "Pass" then
		UI.Button({
			Text = T("car.view"),
			Size = UDim2.fromOffset(150, 38),
			Variant = "Secondary",
			LayoutOrder = 1,
			Parent = row,
		}, function()
			ctx.Windows.Close("Garage")
			call("Shop", "Open", if type(car.Pass) == "string" then car.Pass else "Passes") -- direkt die Pass-Details
		end)
	else
		UI.Button({
			Text = sourceText(car),
			Size = UDim2.fromOffset(220, 38),
			Variant = "Muted",
			LayoutOrder = 1,
			Parent = row,
		}, function() end)
	end
end

local function updateInfo()
	local key = selected or garageState().Active or "LamCity"
	local car = VC.Car(key)
	if not car then
		return
	end
	selected = car.Key
	if draftKey ~= car.Key then
		setDraft(car.Key)
	end
	if infoName then
		infoName.Text = pick(car.Name)
	end
	local holder = classChipHolder
	if holder then
		clear(holder)
		UI.Chip(holder, className(car.Class), classColor(car.Class), { LayoutOrder = 1 })
		if car.Maker == "Velocitra" and garageState().Discount == true then
			local pct = math.floor(((VC.ShareholderDiscount and VC.ShareholderDiscount.Pct) or 0) * 100 + 0.5)
			UI.Chip(holder, T("car.discountTag", "−" .. pct .. " %"), Theme.Up, { LayoutOrder = 2 })
		end
		if owns(car.Key) then
			UI.Chip(
				holder,
				if garageState().Spawned == car.Key then T("car.activeTag") else T("car.ownedTag"),
				Theme.Accent,
				{
					LayoutOrder = 3,
				}
			)
		end
	end
	if infoMeta then
		infoMeta.Text = T("car.topSpeed", VC.Cap(car.Key))
	end
	if infoPrice then
		if car.Source == "Shop" and not owns(car.Key) then
			local price, saved = priceOf(car)
			infoPrice.Text = formatCredits(price)
				.. (if saved > 0 then "  (" .. T("car.discountTag", formatCredits(saved)) .. ")" else "")
		else
			infoPrice.Text = sourceText(car)
		end
	end
	if infoHint then
		local rule = VC.ShareholderDiscount
		local company = ctx.Config.Companies
			and ctx.Config.Companies.ById
			and rule
			and ctx.Config.Companies.ById[rule.I]
		if car.Maker == "Velocitra" and rule and company then
			infoHint.Text = T("car.discountHint", rule.Min, company.Ticker, math.floor(rule.Pct * 100 + 0.5) .. " %")
		else
			infoHint.Text = ""
		end
	end
	if slotsLabel then
		local state = garageState()
		slotsLabel.Text = T("car.slots", state.Used or 0, state.Slots or 6)
	end
	buildActions(car)
	if preview then
		showCar(preview, car.Key, draft)
	end
end

-- Hover/Drück-Feedback für Karten-Knöpfe (wie das UI-Kit: Hover heller, Drücken Feder 0,97 in 0,08 s,
-- Loslassen 0,3 s Back Out)
local PRESS_INFO = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local HOVER_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function cardFeedback(card: Frame, hit: TextButton)
	local scale: UIScale = UI.Create("UIScale", { Scale = 1, Parent = card })
	local base = card.BackgroundColor3
	hit.MouseEnter:Connect(function()
		TweenService:Create(card, HOVER_INFO, { BackgroundColor3 = Theme.Hover }):Play()
	end)
	hit.MouseLeave:Connect(function()
		TweenService:Create(card, HOVER_INFO, { BackgroundColor3 = base }):Play()
		TweenService:Create(scale, RELEASE_INFO, { Scale = 1 }):Play()
	end)
	hit.MouseButton1Down:Connect(function()
		TweenService:Create(scale, PRESS_INFO, { Scale = 0.97 }):Play()
	end)
	hit.MouseButton1Up:Connect(function()
		TweenService:Create(scale, RELEASE_INFO, { Scale = 1 }):Play()
	end)
end

local function carCard(parent: Instance, car: any, order: number)
	local isSelected = car.Key == selected
	local card = UI.Card({ Name = car.Key, LayoutOrder = order, Parent = parent })
	local stroke = card:FindFirstChildWhichIsA("UIStroke")
	if stroke and isSelected then
		stroke.Color = Theme.Accent
		stroke.Thickness = 2
	end
	UI.Label({
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.new(1, -20, 0, 20),
		Text = pick(car.Name),
		Face = "BodyBold",
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 16,
		Parent = card,
	})
	local chipRow = UI.Create("Frame", {
		Position = UDim2.fromOffset(10, 32),
		Size = UDim2.new(1, -20, 0, 22),
		BackgroundTransparency = 1,
		Parent = card,
	}, { UI.Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }) })
	UI.Chip(chipRow, className(car.Class), classColor(car.Class))
	UI.Label({
		Position = UDim2.fromOffset(10, 58),
		Size = UDim2.new(1, -20, 0, 16),
		Text = T("car.topSpeed", VC.Cap(car.Key)),
		TextColor3 = Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 13,
		Parent = card,
	})
	local status: string
	local color = Theme.Muted
	if garageState().Spawned == car.Key and garageState().Test == true then
		status, color = T("car.testDrive"), Theme.Cosmic2
	elseif garageState().Spawned == car.Key then
		status, color = T("car.activeTag"), Theme.Accent
	elseif owns(car.Key) then
		status, color = T("car.ownedTag"), Theme.Up
	elseif car.Source == "Shop" then
		status, color = formatCredits((priceOf(car))), Theme.Text
	else
		status = sourceText(car)
	end
	UI.Label({
		Position = UDim2.fromOffset(10, 78),
		Size = UDim2.new(1, -20, 0, 18),
		Text = status,
		Face = "MonoBold",
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 14,
		Parent = card,
	})
	local hit: TextButton = UI.Create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 5,
		Parent = card,
	})
	cardFeedback(card, hit)
	hit.Activated:Connect(function()
		call("Sfx", "Play", "UIClick")
		selectCar(car.Key)
	end)
end

local function buildCarList(parent: Frame, mineOnly: boolean)
	local grid = UI.Grid(parent, 2, CARD_W, CARD_H)
	local order = 0
	for _, car in ipairs(VC.Cars or {}) do
		local mine = owns(car.Key)
		if (mineOnly and mine) or (not mineOnly and not mine) then
			order += 1
			carCard(grid, car, order)
		end
	end
	if order == 0 then
		UI.Label({
			Size = UDim2.new(1, 0, 0, 44),
			Text = if mineOnly then T("car.none") else T("car.allOwned"),
			TextWrapped = true,
			TextColor3 = Theme.Muted,
			MaxText = 15,
			LayoutOrder = 1,
			Parent = parent,
		})
	end
end

-- Tuning-Reiter
local function optionButton(
	parent: Instance,
	order: number,
	text: string,
	color: Color3,
	on: boolean,
	locked: string?,
	onClick: () -> ()
)
	local holder = UI.Card({ Size = UDim2.fromOffset(110, 40), LayoutOrder = order, Parent = parent })
	local stroke = holder:FindFirstChildWhichIsA("UIStroke")
	if stroke and on then
		stroke.Color = Theme.Accent
		stroke.Thickness = 2
	end
	UI.Create("Frame", {
		Position = UDim2.new(0, 8, 0.5, -9),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = holder,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }), UI.Stroke(nil, 1) })
	UI.Label({
		Position = UDim2.fromOffset(32, 4),
		Size = UDim2.new(1, -38, 1, -8),
		Text = if locked then locked .. " · " .. text else text,
		TextColor3 = if locked then Theme.Warn else Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 12,
		Parent = holder,
	})
	local hit: TextButton = UI.Create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 5,
		Parent = holder,
	})
	cardFeedback(holder, hit)
	hit.Activated:Connect(function()
		call("Sfx", "Play", "UIClick")
		onClick()
	end)
end

local function tunePrice(key: string, current: { [string]: any }, want: { [string]: any }): number
	local total = 0
	if want.Paint ~= current.Paint then
		total += VC.TunePrice(key, "Paint", want.Paint)
	end
	if want.Rims ~= current.Rims then
		total += VC.TunePrice(key, "Rims", want.Rims)
	end
	if want.Glow ~= current.Glow then
		total += VC.TunePrice(key, "Glow", want.Glow)
	end
	if want.Spoiler ~= current.Spoiler and want.Spoiler == true then
		total += VC.TunePrice(key, "Spoiler", nil)
	end
	return total
end

local function buildTune(parent: Frame)
	local key = selected
	local car = key and VC.Car(key) or nil
	if not car or not owns(car.Key) or not draft then
		UI.Label({
			Size = UDim2.new(1, 0, 0, 30),
			Text = T("car.pickCar"),
			TextColor3 = Theme.Muted,
			MaxText = 15,
			LayoutOrder = 1,
			Parent = parent,
		})
		return
	end
	local d = draft :: { [string]: any }
	local current = tuneOf(car.Key)
	local vip = player:GetAttribute("Vip") == true
	local club = player:GetAttribute("Club") == true
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	UI.Section(parent, T("car.tuneFor", pick(car.Name)), nextOrder(), Theme.Purple)
	UI.Section(parent, T("car.paint"), nextOrder(), Theme.Accent)
	local paints = UI.Grid(parent, nextOrder(), 110, 40)
	for i, paint in ipairs(VC.Paints or {}) do
		local locked: string? = nil
		if paint.Unlock == "Pass" and not vip then
			locked = T("car.vipTag")
		elseif paint.Unlock == "Club" and not club then
			locked = T("car.clubTag")
		end
		local label = pick(paint.Name) .. (if paint.Metallic then " ✦" else "")
		optionButton(paints, i, label, paint.Color, d.Paint == paint.Key, locked, function()
			if locked then
				ctx.Toast(if paint.Unlock == "Club" then T("car.tuneClub") else T("car.tuneVip"), "Info")
				return
			end
			d.Paint = paint.Key
			refresh()
		end)
	end
	UI.Section(parent, T("car.rims"), nextOrder(), Theme.Accent)
	local rims = UI.Grid(parent, nextOrder(), 110, 40)
	for i, rim in ipairs(VC.Rims or {}) do
		optionButton(rims, i, pick(rim.Name), rim.Color, d.Rims == rim.Key, nil, function()
			d.Rims = rim.Key
			refresh()
		end)
	end
	UI.Section(parent, T("car.glow"), nextOrder(), Theme.Accent)
	local glows = UI.Grid(parent, nextOrder(), 110, 40)
	optionButton(glows, 0, T("car.glowOff"), Theme.Bg2, d.Glow == (VC.GlowOff or "Off"), nil, function()
		d.Glow = VC.GlowOff or "Off"
		refresh()
	end)
	for i, glow in ipairs(VC.Glow or {}) do
		optionButton(glows, i, pick(glow.Name), glow.Color, d.Glow == glow.Key, nil, function()
			d.Glow = glow.Key
			refresh()
		end)
	end
	UI.Section(parent, T("car.spoiler"), nextOrder(), Theme.Accent)
	local spoilers = UI.Grid(parent, nextOrder(), 150, 40)
	optionButton(spoilers, 1, T("car.spoilerOn"), Theme.Text2, d.Spoiler == true, nil, function()
		d.Spoiler = true
		refresh()
	end)
	optionButton(spoilers, 2, T("car.spoilerOff"), Theme.Bg2, d.Spoiler ~= true, nil, function()
		d.Spoiler = false
		refresh()
	end)
	local price = tunePrice(car.Key, current, d)
	local changed = d.Paint ~= current.Paint
		or d.Rims ~= current.Rims
		or d.Glow ~= current.Glow
		or d.Spoiler ~= current.Spoiler
	local row = UI.Row(parent, nextOrder(), 46)
	UI.Button({
		Text = if price > 0 then T("car.apply", formatCredits(price)) else T("car.applyFree"),
		Size = UDim2.fromOffset(280, 40),
		Variant = if changed and credits() >= price then "Primary" else "Muted",
		LayoutOrder = 1,
		Parent = row,
	}, function()
		if not changed then
			ctx.Toast(T("car.tuneNothing"), "Info")
			return
		end
		local arg: { [string]: any } = { Key = car.Key }
		if d.Paint ~= current.Paint then
			arg.Paint = d.Paint
		end
		if d.Rims ~= current.Rims then
			arg.Rims = d.Rims
		end
		if d.Glow ~= current.Glow then
			arg.Glow = d.Glow
		end
		if d.Spoiler ~= current.Spoiler then
			arg.Spoiler = d.Spoiler
		end
		toast(ctx.RequestFull("CarTune", arg, true))
	end)
end

local function buildBody()
	local frame = body
	if not frame then
		return
	end
	clear(frame)
	if tab == "Tune" then
		buildTune(frame)
	else
		buildCarList(frame, tab == "Mine")
	end
end

local function buildWindow()
	local win = window
	if not win then
		return
	end
	local content = win.Content
	clear(content)
	builtLang = ctx.Lang_()
	local top = UI.Card({ Name = "Top", Size = UDim2.new(1, -4, 0, 236), LayoutOrder = 1, Parent = content })
	preview = newPreview(top, UDim2.new(0.52, -12, 1, -16), UDim2.fromOffset(8, 8))
	local info = UI.Create("Frame", {
		Name = "Info",
		Position = UDim2.new(0.52, 4, 0, 10),
		Size = UDim2.new(0.48, -16, 1, -20),
		BackgroundTransparency = 1,
		Parent = top,
	})
	infoName = UI.Label({
		Size = UDim2.new(1, 0, 0, 32),
		Face = "Display",
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 26,
		Parent = info,
	})
	classChipHolder = UI.Create("Frame", {
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Parent = info,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	infoMeta = UI.Label({
		Position = UDim2.fromOffset(0, 66),
		Size = UDim2.new(1, 0, 0, 20),
		TextColor3 = Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 15,
		Parent = info,
	})
	infoPrice = UI.Label({
		Position = UDim2.fromOffset(0, 90),
		Size = UDim2.new(1, 0, 0, 24),
		Face = "MonoBold",
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 18,
		Parent = info,
	})
	infoHint = UI.Label({
		Position = UDim2.fromOffset(0, 118),
		Size = UDim2.new(1, 0, 0, 30),
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 12,
		Parent = info,
	})
	actionRow = UI.Create("Frame", {
		Position = UDim2.new(0, 0, 1, -66),
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		Parent = info,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	slotsLabel = UI.Label({
		Position = UDim2.new(0, 0, 1, -20),
		Size = UDim2.new(1, 0, 0, 18),
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 13,
		Parent = info,
	})
	local segHolder = UI.Create(
		"Frame",
		{ Size = UDim2.new(1, -4, 0, 36), BackgroundTransparency = 1, LayoutOrder = 2, Parent = content }
	)
	segmented = UI.Segmented(segHolder, {
		{ Key = "Mine", Text = T("car.tab.mine") },
		{ Key = "Dealer", Text = T("car.tab.dealer") },
		{ Key = "Tune", Text = T("car.tab.tune") },
	}, function(key: string)
		tab = key
		refresh()
	end)
	segmented.Set(tab, true)
	body = UI.Create("Frame", {
		Name = "Body",
		Size = UDim2.new(1, -4, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = content,
	}, { UI.Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
end

refresh = function()
	local win = window
	if not win or not win.IsOpen then
		return
	end
	if builtLang ~= ctx.Lang_() then
		buildWindow()
	end
	updateInfo()
	buildBody()
end

local function stateSignature(): string
	local state = garageState()
	local parts = {
		tostring(state.Spawned),
		tostring(state.Test),
		tostring(state.Used),
		tostring(state.Slots),
		tostring(state.Discount),
		tostring(state.Active),
	}
	local keys = {}
	for key in pairs(state.Cars or {}) do
		table.insert(keys, key)
	end
	table.sort(keys)
	table.insert(parts, table.concat(keys, ","))
	local tune = state.Tune or {}
	for _, key in ipairs(keys) do
		local entry = tune[key]
		if type(entry) == "table" then
			table.insert(
				parts,
				("%s:%s:%s:%s"):format(
					tostring(entry.Paint),
					tostring(entry.Rims),
					tostring(entry.Glow),
					tostring(entry.Spoiler)
				)
			)
		end
	end
	return table.concat(parts, "|")
end

local function openWindow()
	if not window then
		window = UI.Window(T("car.title"), WINDOW_W, WINDOW_H, Theme.Purple)
		buildWindow()
	end
	if pendingTab then
		tab = pendingTab
		pendingTab = nil
	end
	if segmented then
		segmented.Set(tab, true)
	end
	if not selected then
		selected = garageState().Active or "LamCity"
	end
	setDraft(selected)
	UI.OpenWindow(window)
	lastStateSig = stateSignature()
	refresh()
end

local function closeWindow()
	if window and window.IsOpen then
		UI.CloseWindow(window)
	end
end

-- ---------------------------------------------------------------------
-- 3) ENTHÜLLUNG (Effekt "Reveal" {Key})
-- ---------------------------------------------------------------------
local revealGui: ScreenGui? = nil

local function nearestRamp(): Vector3?
	local city = ctx.Config.City
	local roads = city and city.Roads
	if type(roads) ~= "table" or type(roads.Highway) ~= "table" then
		return nil
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local origin = if root and root:IsA("BasePart") then root.Position else Vector3.zero
	local best: Vector3? = nil
	local bestDist = math.huge
	local r = roads.Outer.Radius + roads.Outer.Width / 2 + 20
	for _, deg in ipairs(roads.Highway.Ramps or {}) do
		local a = math.rad(deg)
		local pos = Vector3.new(r * math.cos(a), city.Levels.Road, r * math.sin(a))
		local d = (pos - origin).Magnitude
		if d < bestDist then
			best, bestDist = pos, d
		end
	end
	return best
end

local function closeReveal()
	local gui = revealGui
	revealGui = nil
	if gui then
		gui:Destroy()
	end
end

local function playReveal(_strength: number, data: any)
	local key = type(data) == "table" and data.Key or nil
	local car = if type(key) == "string" then VC.Car(key) else nil
	if not car then
		return
	end
	closeReveal()
	local gui = Instance.new("ScreenGui")
	gui.Name = "AkytexTycoonReveal"
	gui.DisplayOrder = 40
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	local shade: Frame = UI.Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Space,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = gui,
	})
	local panel: Frame = UI.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 10),
		Size = UDim2.fromScale(0.62, 0.7),
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Parent = shade,
	}, {
		UI.Corner(16),
		UI.Stroke(Theme.Cosmic2, 1),
		UI.Create("UISizeConstraint", { MinSize = Vector2.new(320, 300), MaxSize = Vector2.new(900, 640) }),
	})
	local scale: UIScale = UI.Create("UIScale", { Scale = 0.96, Parent = panel })
	UI.Label({
		Position = UDim2.fromScale(0.05, 0.04),
		Size = UDim2.fromScale(0.9, 0.07),
		Text = T("car.reveal.title"),
		Face = "Display",
		TextColor3 = Theme.Cosmic2,
		MaxText = 20,
		Parent = panel,
	})
	local p = newPreview(panel, UDim2.fromScale(0.9, 0.56), UDim2.fromScale(0.05, 0.13))
	showCar(p, car.Key, tuneOf(car.Key))
	-- Lichtschweif über die Bühne
	local sweep: Frame = UI.Create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.85,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = p.Viewport,
	}, { UI.Corner(12) })
	local gradient: UIGradient = UI.Create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.45, 1),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(0.55, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Rotation = 20,
		Offset = Vector2.new(-1, 0),
		Parent = sweep,
	})
	UI.Label({
		Position = UDim2.fromScale(0.05, 0.71),
		Size = UDim2.fromScale(0.9, 0.08),
		Text = pick(car.Name),
		Face = "Display",
		MaxText = 34,
		Parent = panel,
	})
	UI.Label({
		Position = UDim2.fromScale(0.05, 0.79),
		Size = UDim2.fromScale(0.9, 0.05),
		Text = T("car.class", className(car.Class)) .. "  ·  " .. T("car.topSpeed", VC.Cap(car.Key)),
		TextColor3 = classColor(car.Class),
		MaxText = 16,
		Parent = panel,
	})
	local buttons = UI.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.new(0.9, 0, 0, 42),
		BackgroundTransparency = 1,
		Parent = panel,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	UI.Button({
		Text = T("car.reveal.drive"),
		Size = UDim2.fromOffset(190, 42),
		Variant = "Primary",
		LayoutOrder = 1,
		Parent = buttons,
	}, function()
		closeReveal()
		local reply = toast(ctx.RequestFull("CarSpawn", { Key = car.Key }, true))
		if reply.Ok and car.Class == "Hyper" then
			local target = nearestRamp()
			if target then
				call("Vehicles", "Waypoint", target)
				ctx.Toast(T("car.reveal.highway"), "Event")
			end
		end
	end)
	UI.Button({
		Text = T("car.reveal.later"),
		Size = UDim2.fromOffset(150, 42),
		Variant = "Secondary",
		LayoutOrder = 2,
		Parent = buttons,
	}, function()
		closeReveal()
	end)
	gui.Parent = player:WaitForChild("PlayerGui")
	revealGui = gui
	call("Sfx", "Play", "Achievement")
	local fast = reducedFx()
	TweenService:Create(
		shade,
		TweenInfo.new(if fast then 0.05 else 0.26, Enum.EasingStyle.Quint),
		{ BackgroundTransparency = 0.35 }
	):Play()
	TweenService:Create(
		scale,
		TweenInfo.new(if fast then 0.05 else 0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
	if not fast then
		TweenService
			:Create(gradient, TweenInfo.new(1.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0, false, 0.35), {
				Offset = Vector2.new(1, 0),
			})
			:Play()
	end
	task.delay(18, function()
		if revealGui == gui then
			closeReveal()
		end
	end)
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICHE API
-- ---------------------------------------------------------------------
function Garage.Open()
	ctx.Windows.Open("Garage")
end

function Garage.Select(key: string)
	selectCar(key)
end

function Garage.Tick()
	local win = window
	if not win or not win.IsOpen then
		return
	end
	local sig = stateSignature()
	if sig ~= lastStateSig or builtLang ~= ctx.Lang_() then
		lastStateSig = sig
		if draftKey then
			-- gespeicherte Werte übernehmen (z. B. nach erfolgreichem Tuning)
			setDraft(draftKey)
		end
		refresh()
	end
end

function Garage.Init(context: any)
	ctx = context
	VC = ctx.Config.Vehicles or {}
	ctx.Windows.Register("Garage", openWindow, closeWindow)
	local effects = ctx.Modules.Effects
	if effects and type(effects.Register) == "function" then
		effects.Register("Reveal", playReveal)
	end
	ctx.Hooks.On("State", function(_state: any, changed: any)
		if type(changed) == "table" and (changed.Garage or changed.Credits) then
			Garage.Tick()
		end
	end)
	-- Prompts in der Welt: Autohaus öffnet den Reiter "Autohaus", die Lackier-Box "Tuning"
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		if who ~= player or prompt:GetAttribute("Window") ~= "Garage" then
			return
		end
		local wanted = prompt:GetAttribute("Tab")
		local nextTab = if wanted == "Tune" then "Tune" else "Dealer"
		if window and window.IsOpen then
			tab = nextTab
			if segmented then
				segmented.Set(tab, true)
			end
			refresh()
		else
			pendingTab = nextTab
		end
	end)
end

function Garage.Start() end

return Garage
