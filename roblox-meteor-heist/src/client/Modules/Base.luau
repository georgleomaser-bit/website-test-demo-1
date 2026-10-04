-- =====================================================================
--  🏠 BASE: Fenster zum Kaufen von Stockwerken + Base-Look (Knopf rechts),
--  dazu die Laser-Sperre am Eingang jeder Base (Streifen fahren beim Sperren zu, flimmern, Funken).
--  Kaufen fragt den Server ("BuyFloor" / "BuyBaseLook"), der prüft Geld + Reihenfolge.
--  Animationen (alles lokal, rein optisch, nur in Kameranähe):
--    • Effekt "FloorBuilt": das neue Stockwerk baut sich auf – Stufen und Pfeiler wachsen von unten,
--      Platte und Rand fallen von oben rein und federn, am Ende Staub + Funken
--    • Effekt "LookUpgrade": neue Deko ploppt nacheinander auf, Funkeln an Zaun und Laternen
--    • Lock-Knopf der eigenen Base: pulsierender Leuchtring, solange nicht gesperrt;
--      beim Sperren Druckwelle am Knopf + Funken an den Laser-Pfosten
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent:WaitForChild("UI"))

local Base = {}

local ctx: any = nil
local Theme = UI.Theme
local GRAY = Theme.Gray

type Row = { Index: number, Button: UI.Button, Card: Frame, Stroke: UIStroke }

local player = Players.LocalPlayer
local floorRows: { Row } = {}
local lookRows: { Row } = {}
local slotLabel: TextLabel
local badge: Frame? = nil

-- ---------------------------------------------------------------------
-- FENSTER
-- ---------------------------------------------------------------------
local function row(parent: Instance, order: number, title: string, info: string, onBuy: () -> ()): (Frame, UI.Button)
	local card = UI.Card({ Size = UDim2.new(1, 0, 0, 62), LayoutOrder = order, Parent = parent })
	UI.Label({
		Position = UDim2.fromOffset(12, 5),
		Size = UDim2.new(1, -190, 0, 30),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 22,
		Outline = 2,
		Parent = card,
	})
	UI.Label({
		Position = UDim2.fromOffset(12, 35),
		Size = UDim2.new(1, -190, 0, 20),
		Text = info,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.SubText,
		MaxText = 14,
		Parent = card,
	})
	local button = UI.Button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(160, 44),
		Text = "...",
		Color = GRAY,
		MaxText = 18,
		Parent = card,
	}, onBuy)
	return card, button
end

local function build()
	local win = UI.Window("🏠 BASE", 520, 560, Theme.Gold)
	local content = win.Content
	local Config = ctx.Config

	UI.Section(content, "🏢 Stockwerke", 1)
	slotLabel = UI.Label({
		Size = UDim2.new(1, 0, 0, 22),
		Text = "",
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.SubText,
		LayoutOrder = 2,
		MaxText = 16,
		Parent = content,
	})
	local floors = if type(Config.BaseFloors) == "table" then Config.BaseFloors else {}
	for i, def in ipairs(floors) do
		local need = math.floor(tonumber(def.RequiredRebirths) or 0)
		local info = ("+%d Plätze"):format(math.floor(tonumber(def.Slots) or 0))
		if need > 0 then
			info ..= ("  •  ab %d Rebirth"):format(need)
		end
		local card, button = row(content, 10 + i, tostring(def.Name or ("Stockwerk " .. (i + 1))), info, function()
			ctx.Request("BuyFloor")
		end)
		table.insert(floorRows, {
			Index = i,
			Button = button,
			Card = card,
			Stroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke,
		})
	end

	UI.Section(content, "✨ Base-Look", 50)
	local looks = if type(Config.BaseLooks) == "table" then Config.BaseLooks else {}
	for i, def in ipairs(looks) do
		local title = ("%s %s"):format(tostring(def.Icon or ""), tostring(def.Name or i))
		local card, button = row(content, 50 + i, title, tostring(def.Info or ""), function()
			ctx.Request("BuyBaseLook")
		end)
		table.insert(lookRows, {
			Index = i,
			Button = button,
			Card = card,
			Stroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke,
		})
	end
	UI.Label({
		Size = UDim2.new(1, 0, 0, 22),
		Text = "Bleibt auch nach Rebirth!",
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.SubText,
		LayoutOrder = 99,
		MaxText = 14,
		Parent = content,
	})
	ctx.Windows.Register("Base", win, Base.Refresh)
	local button = ctx.Hud.AddRightButton("🏗️", "Base", Theme.Gold, 8, function()
		ctx.Windows.Toggle("Base")
	end)
	badge = UI.Badge(button, "!")
end

local function setRow(r: Row, text: string, color: Color3, highlight: boolean)
	r.Button.SetText(text)
	r.Button.SetColor(color)
	local strokeColor = if highlight then Theme.Gold else Color3.new(0, 0, 0)
	if r.Stroke and r.Stroke.Color ~= strokeColor then
		r.Stroke.Color = strokeColor
		r.Stroke.Thickness = if highlight then 4 else 2
	end
end

-- Nächstes Stockwerk, das man kaufen kann (nil = alle gebaut)
local function nextFloorDef(state: any): any
	local defs = ctx.Config.BaseFloors
	return if type(defs) == "table" then defs[tonumber(state.BaseFloors) or 1] else nil
end

function Base.Refresh(state: any)
	if not state then
		return
	end
	local Util = ctx.Util
	local cash = tonumber(state.Cash) or 0
	local rebirths = tonumber(state.Rebirths) or 0
	local floors = tonumber(state.BaseFloors) or 1
	local look = tonumber(state.BaseLook) or 1
	local text = ("Plätze: %d / %d  •  Stockwerk %d"):format(
		math.floor(tonumber(state.UsedSlots) or 0),
		math.floor(tonumber(state.Slots) or 0),
		floors
	)
	if slotLabel.Text ~= text then
		slotLabel.Text = text
	end
	for _, r in ipairs(floorRows) do
		local def = ctx.Config.BaseFloors[r.Index]
		local price = tonumber(def.Price) or 0
		local need = math.floor(tonumber(def.RequiredRebirths) or 0)
		if r.Index + 1 <= floors then
			setRow(r, "✅ Gebaut", GRAY, true)
		elseif r.Index == floors then
			if rebirths < need then
				setRow(r, "🔥 Rebirth " .. need, GRAY, false)
			else
				setRow(r, "💵 " .. Util.FormatCash(price), if cash >= price then Theme.Green else GRAY, false)
			end
		else
			setRow(r, "🔒 " .. Util.FormatCash(price), GRAY, false)
		end
	end
	for _, r in ipairs(lookRows) do
		local def = ctx.Config.BaseLooks[r.Index]
		local price = tonumber(def.Price) or 0
		if r.Index == look then
			setRow(r, "✅ Aktiv", Theme.Gold, true)
		elseif r.Index < look then
			setRow(r, "✅ Gekauft", GRAY, false)
		elseif r.Index == look + 1 then
			setRow(r, "💵 " .. Util.FormatCash(price), if cash >= price then Theme.Green else GRAY, false)
		else
			setRow(r, "🔒 " .. Util.FormatCash(price), GRAY, false)
		end
	end
end

-- Badge jede neue State-Meldung: "!" wenn das nächste Stockwerk bezahlbar ist
function Base.OnState(state: any)
	if not badge or not state then
		return
	end
	local cash = tonumber(state.Cash) or 0
	local nextFloor = nextFloorDef(state)
	local need = nextFloor and math.floor(tonumber(nextFloor.RequiredRebirths) or 0) or 0
	local show = nextFloor ~= nil
		and cash >= (tonumber(nextFloor.Price) or math.huge)
		and (tonumber(state.Rebirths) or 0) >= need
	UI.SetBadge(badge, if show then "!" else nil, nil, show)
end

-- ---------------------------------------------------------------------
-- LASER-SPERRE (lokal): Streifen fahren von beiden Pfosten zur Mitte
-- ---------------------------------------------------------------------
type Gate = {
	Barrier: BasePart,
	Beams: { { Part: BasePart, Closed: CFrame, Open: CFrame, Size: Vector3 } },
	State: string, -- "open" / "lock" / "shield"
}

local SPARK_RANGE = 220 -- Funken + Flimmern nur so nah an der Kamera
local SHIMMER_RANGE = 200
local LOCK_COLOR = Color3.fromRGB(255, 50, 50)
local SHIELD_COLOR = Color3.fromRGB(70, 170, 255)
local BEAM_THICK = 0.3
local CLOSE_TIME = 0.7
local OPEN_TIME = 0.4
local STAGGER = 0.06

local gates: { [Instance]: Gate } = {}
local laserFolder: Folder? = nil

local function makeGate(model: Instance, barrier: BasePart): Gate
	local folder = laserFolder :: Folder
	local count = math.clamp(math.floor(tonumber(barrier:GetAttribute("Beams")) or 5), 1, 8)
	local width, height = barrier.Size.X, barrier.Size.Y
	local half = width / 2
	local beams = {}
	for k = 1, count do
		local y = -height / 2 + height * (k - 0.5) / count
		for _, s in ipairs({ -1, 1 }) do
			local closedCf = barrier.CFrame * CFrame.new(s * half / 2, y, 0)
			local openCf = barrier.CFrame * CFrame.new(s * half, y, 0)
			local p = Instance.new("Part")
			p.Name = "Laser"
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Material = Enum.Material.Neon
			p.Color = LOCK_COLOR
			p.Transparency = 1
			p.Size = Vector3.new(0.05, BEAM_THICK, BEAM_THICK)
			p.CFrame = openCf
			p.Parent = folder
			table.insert(
				beams,
				{ Part = p, Closed = closedCf, Open = openCf, Size = Vector3.new(half, BEAM_THICK, BEAM_THICK) }
			)
		end
	end
	local gate: Gate = { Barrier = barrier, Beams = beams, State = "open" }
	gates[model] = gate
	return gate
end

-- Funken an beiden Laser-Pfosten + Druckwelle am Lock-Knopf (nur in Kameranähe, macht Effects)
local function gateSparks(model: Instance, gate: Gate, color: Color3)
	local effects = ctx and ctx.Effects
	local camera = workspace.CurrentCamera
	local barrier = gate.Barrier
	if not effects or not effects.Burst or not camera then
		return
	end
	if (barrier.Position - camera.CFrame.Position).Magnitude > SPARK_RANGE then
		return
	end
	local half = barrier.Size.X / 2
	for _, s in ipairs({ -1, 1 }) do
		effects.Burst((barrier.CFrame * CFrame.new(s * half, 0, 0)).Position, color, 8, false)
	end
	local pad = model:FindFirstChild("LockPad")
	if pad and pad:IsA("BasePart") then
		effects.Ring(pad.Position - Vector3.new(0, pad.Size.Y / 2, 0), color, 14, 0.5)
	end
end

local function setGate(gate: Gate, state: string, model: Instance?)
	if gate.State == state then
		return
	end
	local wasOpen = gate.State == "open"
	gate.State = state
	if wasOpen and model then
		gateSparks(model, gate, if state == "shield" then SHIELD_COLOR else LOCK_COLOR)
	end
	for i, beam in ipairs(gate.Beams) do
		local p = beam.Part
		local delayTime = math.floor((i - 1) / 2) * STAGGER
		if state == "open" then
			local tween = TweenService:Create(
				p,
				TweenInfo.new(OPEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, delayTime),
				{ Size = Vector3.new(0.05, BEAM_THICK, BEAM_THICK), CFrame = beam.Open }
			)
			tween.Completed:Connect(function(status)
				if status == Enum.PlaybackState.Completed and gate.State == "open" then
					p.Transparency = 1
				end
			end)
			tween:Play()
		else
			p.Color = if state == "shield" then SHIELD_COLOR else LOCK_COLOR
			p.Transparency = 0.15
			if wasOpen then
				TweenService:Create(
					p,
					TweenInfo.new(CLOSE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delayTime),
					{ Size = beam.Size, CFrame = beam.Closed }
				):Play()
			end
		end
	end
end

local function updateGates()
	local now = workspace:GetServerTimeNow()
	for model, gate in pairs(gates) do
		if not model.Parent or not gate.Barrier.Parent then
			for _, beam in ipairs(gate.Beams) do
				beam.Part:Destroy()
			end
			gates[model] = nil
		else
			local shield = tonumber(model:GetAttribute("ShieldUntil")) or 0
			local locked = tonumber(model:GetAttribute("LockedUntil")) or 0
			local state = if shield > now then "shield" elseif locked > now then "lock" else "open"
			setGate(gate, state, model)
		end
	end
end

local function scanPlots(plots: Instance)
	for _, model in ipairs(plots:GetChildren()) do
		if not gates[model] and model:GetAttribute("LockedUntil") ~= nil then
			local barrier = model:FindFirstChild("Barrier")
			if barrier and barrier:IsA("BasePart") then
				makeGate(model, barrier)
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- LASER-FLIMMERN + LEUCHTRING AM EIGENEN LOCK-KNOPF (jedes Frame, nur in Kameranähe)
-- ---------------------------------------------------------------------
local plotsFolder: Instance? = nil
local lockRing: BasePart? = nil
local ringShown = false
local fxClock = 0

local function myPlot(): Instance?
	local plots = plotsFolder
	if not plots then
		return nil
	end
	for model in pairs(gates) do
		if model:GetAttribute("OwnerUserId") == player.UserId then
			return model
		end
	end
	return nil
end

local function buildLockRing()
	local ring = Instance.new("Part")
	ring.Name = "LockRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 90, 90)
	ring.Transparency = 1
	ring.Size = Vector3.new(0.12, 8, 8)
	ring.CFrame = CFrame.new(0, -5000, 0)
	ring.Parent = laserFolder
	lockRing = ring
end

local myGateModel: Instance? = nil
local myGateClock = 0

local function stepGateFx(dt: number)
	fxClock += dt
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local camPos = camera.CFrame.Position
	for _, gate in pairs(gates) do
		if gate.State ~= "open" and (gate.Barrier.Position - camPos).Magnitude < SHIMMER_RANGE then
			for i, beam in ipairs(gate.Beams) do
				beam.Part.Transparency = 0.08 + 0.3 * (math.sin(fxClock * 17 + i * 1.7) + 1) / 2
			end
		end
	end
	-- eigener Lock-Knopf: Ring pulsiert, solange die Base offen ist ("tritt drauf!")
	myGateClock += dt
	if myGateClock > 1 or not myGateModel then
		myGateClock = 0
		myGateModel = myPlot()
	end
	local ring = lockRing
	local model = myGateModel
	local gate = model and gates[model]
	local pad = model and model:FindFirstChild("LockPad")
	local show = ring ~= nil
		and gate ~= nil
		and gate.State == "open"
		and pad ~= nil
		and pad:IsA("BasePart")
		and (pad.Position - camPos).Magnitude < 150
		and (tonumber(ReplicatedStorage:GetAttribute("ShowerUntil")) or 0) <= workspace:GetServerTimeNow()
		and not (ctx.Effects.IsHidden and ctx.Effects.IsHidden())
	if ring and show ~= ringShown then
		ringShown = show
		if not show then
			ring.Transparency = 1
			ring.CFrame = CFrame.new(0, -5000, 0)
		end
	end
	if ring and show and pad and pad:IsA("BasePart") then
		local u = (fxClock * 0.8) % 1
		local size = 6 + u * 5
		ring.Size = Vector3.new(0.12, size, size)
		ring.Transparency = 0.2 + 0.8 * u
		local bottom = pad.Position - Vector3.new(0, pad.Size.Y / 2 - 0.05, 0)
		ring.CFrame = CFrame.new(bottom) * CFrame.Angles(0, 0, math.pi / 2)
	end
end

-- ---------------------------------------------------------------------
-- BAU-ANIMATION (Stockwerk gekauft) + LOOK-FUNKELN
-- ---------------------------------------------------------------------
local BUILD_RANGE = 320
local BUILD_STAGGER = 0.035
local BUILD_MAX_DELAY = 1.1
local GROW_TIME = 0.4
local DROP_TIME = 0.55
local DROP_HEIGHT = 16
local LOOK_STAGGER = 0.05
local LOOK_TIME = 0.45
local SPARKLE = Color3.fromRGB(255, 225, 110)

local function findPlotModel(index: any): Instance?
	local plots = plotsFolder
	if not plots or type(index) ~= "number" then
		return nil
	end
	for _, model in ipairs(plots:GetChildren()) do
		if model:GetAttribute("PlotIndex") == index then
			return model
		end
	end
	return nil
end

local function inRange(model: Instance): boolean
	local camera = workspace.CurrentCamera
	if not camera or not model:IsA("Model") then
		return false
	end
	return (model:GetPivot().Position - camera.CFrame.Position).Magnitude < BUILD_RANGE
end

-- Ein Teil von unten wachsen lassen (Stufen, Pfeiler) bzw. von oben reinfallen lassen (Platte, Rand)
local function buildPart(part: BasePart, delayTime: number, drop: boolean)
	local finalCf, finalSize, collide = part.CFrame, part.Size, part.CanCollide
	part.CanCollide = false
	part.LocalTransparencyModifier = 1
	local info
	if drop then
		part.CFrame = finalCf
			+ Vector3.new(0, DROP_HEIGHT, 0)
			+ Vector3.new(math.random() * 2 - 1, 0, math.random() * 2 - 1)
		info = TweenInfo.new(DROP_TIME, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out, 0, false, delayTime)
	else
		local flat = Vector3.new(finalSize.X, math.min(0.2, finalSize.Y), finalSize.Z)
		part.Size = flat
		part.CFrame = finalCf * CFrame.new(0, -(finalSize.Y - flat.Y) / 2, 0)
		info = TweenInfo.new(GROW_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delayTime)
	end
	TweenService:Create(part, info, { CFrame = finalCf, Size = finalSize }):Play()
	task.delay(delayTime, function()
		part.LocalTransparencyModifier = 0
	end)
	task.delay(delayTime + math.max(GROW_TIME, DROP_TIME) + 0.1, function()
		-- genau zurück auf die echten Werte (der Server hat sie nie geändert)
		part.CFrame = finalCf
		part.Size = finalSize
		part.CanCollide = collide
		part.LocalTransparencyModifier = 0
	end)
end

local function animateFloor(floorModel: Instance)
	local grow: { BasePart } = {}
	local drop: { BasePart } = {}
	for _, d in ipairs(floorModel:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "Step" or d.Name == "Pillar" then
				table.insert(grow, d)
			else
				table.insert(drop, d)
			end
		end
	end
	-- Treppe von unten nach oben, dann die Pfeiler, danach fällt die Platte drauf
	table.sort(grow, function(a, b)
		return a.Position.Y + a.Size.Y / 2 < b.Position.Y + b.Size.Y / 2
	end)
	local stagger = math.min(BUILD_STAGGER, BUILD_MAX_DELAY / math.max(1, #grow + #drop))
	local delayTime = 0
	for _, part in ipairs(grow) do
		buildPart(part, delayTime, false)
		delayTime += stagger
	end
	local plateAt = delayTime
	for i, part in ipairs(drop) do
		buildPart(part, plateAt + (i - 1) * stagger * 0.5, true)
	end
	local total = plateAt + #drop * stagger * 0.5 + DROP_TIME
	local effects = ctx.Effects
	task.delay(total, function()
		if not floorModel.Parent or not effects.Burst then
			return
		end
		local plate = floorModel:FindFirstChild("Floor")
		if plate and plate:IsA("BasePart") then
			local top = plate.Position + Vector3.new(0, plate.Size.Y / 2, 0)
			effects.Puff(top, Color3.fromRGB(230, 220, 200), 18)
			effects.Burst(top + Vector3.new(0, 3, 0), SPARKLE, 26, true)
			effects.Ring(top, SPARKLE, 40, 0.7)
		end
	end)
end

local function onFloorBuilt(data: any)
	if type(data) ~= "table" then
		return
	end
	local model = findPlotModel(data.Plot)
	if not model or not inRange(model) then
		return
	end
	local floors = model:FindFirstChild("Floors")
	local floorModel = floors and floors:WaitForChild("Floor" .. tostring(data.Floor), 3)
	if floorModel then
		animateFloor(floorModel)
	end
end

local function onLookUpgrade(data: any)
	if type(data) ~= "table" then
		return
	end
	local model = findPlotModel(data.Plot)
	if not model or not inRange(model) then
		return
	end
	local look = model:FindFirstChild("Look")
	local parts: { BasePart } = {}
	if look then
		for _, d in ipairs(look:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
	end
	local effects = ctx.Effects
	for i, part in ipairs(parts) do
		local finalSize = part.Size
		local delayTime = math.min(1.2, (i - 1) * LOOK_STAGGER)
		part.Size = finalSize * 0.05
		TweenService:Create(
			part,
			TweenInfo.new(LOOK_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delayTime),
			{ Size = finalSize }
		):Play()
		task.delay(delayTime + LOOK_TIME + 0.05, function()
			part.Size = finalSize
		end)
		-- Funkeln an Laternen, Fahnen und Bogen (jedes dritte Teil, das reicht)
		if effects.Burst and i % 3 == 1 then
			task.delay(delayTime + LOOK_TIME * 0.6, function()
				if part.Parent then
					effects.Burst(part.Position, SPARKLE, 6, false)
				end
			end)
		end
	end
	-- Glanz über den Zaun
	if effects.Burst then
		for _, child in ipairs(model:GetChildren()) do
			if child:IsA("BasePart") and (child.Name == "BackFence" or child.Name == "SideFence") then
				effects.Burst(child.Position + Vector3.new(0, 1.5, 0), SPARKLE, 12, false)
			end
		end
		local floorPart = model:FindFirstChild("Floor")
		if floorPart and floorPart:IsA("BasePart") then
			effects.Ring(floorPart.Position + Vector3.new(0, floorPart.Size.Y / 2, 0), SPARKLE, 70, 0.8)
		end
	end
end

function Base.SetMap(map: Instance)
	local plots = map:WaitForChild("Plots", 60)
	if not plots then
		return
	end
	plotsFolder = plots
	local folder = Instance.new("Folder")
	folder.Name = "BaseLasers" -- nur lokal
	folder.Parent = workspace
	laserFolder = folder
	buildLockRing()
	RunService.RenderStepped:Connect(function(dt: number)
		local ok, err = pcall(stepGateFx, dt)
		if not ok then
			warn("[Base] Effekte: " .. tostring(err))
		end
	end)
	task.spawn(function()
		local clock = 0
		while true do
			if clock % 10 == 0 then
				scanPlots(plots) -- neue Basen (Replikation) nachholen
			end
			clock += 1
			local ok, err = pcall(updateGates)
			if not ok then
				warn("[Base] Laser: " .. tostring(err))
			end
			task.wait(0.2)
		end
	end)
end

function Base.Init(context: any)
	ctx = context
	build()
	ctx.Remotes.Effect.OnClientEvent:Connect(function(name, _strength, data)
		if name == "FloorBuilt" then
			task.spawn(onFloorBuilt, data)
		elseif name == "LookUpgrade" then
			task.spawn(onLookUpgrade, data)
		end
	end)
end

return Base
