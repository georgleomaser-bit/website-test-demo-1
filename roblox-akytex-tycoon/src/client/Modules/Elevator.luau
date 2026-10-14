-- =====================================================================
--  AKYTEX TYCOON – Aufzug: Etagen-Panel + Kinoszene (Client/Modules/Elevator)
--  Besitzer: WP8 (Turm-Optik, Interiors, Lifestyle). Vertrag: DESIGN.md §B4.10 (Etagen-Panel (UI) -> Client-
--  Kinoszene 1,5 s: Türen zu, Kabine fährt im Schacht, Kamera innen, ElevatorDing, Türen auf; der Server
--  teleportiert die Figur (Request "TowerElevator" {Floor}, Ziel-CFrame + Wurzelhöhen-Versatz, NoteTeleport);
--  keine physikalischen Plattformen; Privat-Etagen für Besucher gesperrt), §D WP8 Abnahme (4) (Ankunft mit Füßen auf
--  dem Boden, kein AntiCheat-Flag – macht PlotService serverseitig), §A4 (ReducedFx = ohne Fahrt).
--
--  Kein eigener Render-Loop: TowerView.Frame ruft Elevator.Step(dt). Kabine, Türen und Licht sind lokale Parts.
--  Öffentliche API (§C7.5):
--    Elevator.Go(floor)            fährt im Tower, in dem man steht (1 = Lobby/Erdgeschoss)
--  Ergänzungen: Elevator.OpenPanel(plot?) · Elevator.ClosePanel() · Elevator.IsRiding(): boolean · Elevator.Step(dt)
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = require(script.Parent:WaitForChild("UI"))
local TowerModels = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TowerModels"))

local Elevator = {}

local Theme = UI.Theme
local player = Players.LocalPlayer

local DOOR_SECONDS = 0.3
local RIDE_SECONDS = 0.9
local REPLY_WAIT = 3.5 -- Sekunden: länger wartet die Kabine nicht (Server antwortet erst nach dem Versetzen, ≤ 2 s Streaming)
local PANEL_RANGE = 16 -- Studs: weiter weg -> Panel schließt
local CORE = 10
local CABIN = 8.6
local CABIN_H = 9
local DOOR_Z = -CORE / 2 + 0.45 -- Kabinentür innen im Schacht (nicht auf der Ebene der Etagen-Türen: kein Flimmern)
local HALL_CLOSE_DELAY = 0.7 -- Etagen-Türen bleiben nach der Ankunft so lange offen

type Ride = {
	Plot: number,
	From: number,
	To: number,
	Start: number,
	MoveStart: number?,
	OpenAt: number?,
	EndAt: number?,
	Ok: boolean?,
	Base: CFrame,
	Parts: { BasePart },
	DoorL: BasePart,
	DoorR: BasePart,
	Saved: Enum.CameraType,
	Dinged: boolean,
}

local ctx: any = nil
local panel: Frame? = nil
local grid: Frame? = nil
local titleLabel: TextLabel? = nil
local panelPlot: number? = nil
local panelOrigin: Vector3? = nil
local ride: Ride? = nil
local fxFolder: Folder? = nil
local hallClose: { Plot: number, Floor: number, Start: number }? = nil

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function call(name: string, fnName: string, ...: any): (boolean, any)
	local modules = ctx and ctx.Modules
	local m = modules and modules[name]
	local fn = m and m[fnName]
	if type(fn) ~= "function" then
		return false, nil
	end
	return pcall(fn, ...)
end

local function T(key: string, ...: any): string
	return ctx.T(key, ...)
end

local function reduced(): boolean
	local ok, settings = call("Settings", "Get")
	return ok and type(settings) == "table" and settings.ReducedFx == true
end

local function sfx(role: string)
	call("Sfx", "Play", role)
end

local function rootPart(): BasePart?
	local character = player.Character
	local part = character and character:FindFirstChild("HumanoidRootPart")
	return if part and part:IsA("BasePart") then part else nil
end

local function plotInfo(plot: number): { [string]: any }?
	local ok, info = call("TowerView", "PlotInfo", plot)
	return if ok and type(info) == "table" then info else nil
end

-- Privat-Etagen aus dem Layout ("!" am Etagen-Eintrag)
local function privateSet(info: { [string]: any }): { [number]: boolean }
	local set: { [number]: boolean } = {}
	local layout = info.Layout
	if type(layout) ~= "string" or layout == "" then
		return set
	end
	local index = 0
	for chunk in string.gmatch(layout .. ";", "([^;]*);") do
		index += 1
		if string.sub(chunk, 1, 1) == "!" then
			set[index] = true
		end
		if index >= 50 then
			break
		end
	end
	return set
end

local function currentFloor(): number?
	local ok, floor = call("TowerView", "CurrentFloor")
	return if ok and type(floor) == "number" then floor else nil
end

-- ---------------------------------------------------------------------
-- PANEL (Glas-Karte unten in der Mitte, Knöpfe 1 … N, Controller-tauglich)
-- ---------------------------------------------------------------------
local function buildPanel()
	local frame: Frame = UI.Panel({
		Name = "ElevatorPanel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -130),
		Size = UDim2.fromOffset(520, 300),
		Visible = false,
		ZIndex = 40,
		Parent = ctx.Gui,
	})
	titleLabel = UI.Label({
		Name = "Title",
		Position = UDim2.fromOffset(18, 12),
		Size = UDim2.new(1, -80, 0, 26),
		Face = "Display",
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 20,
		ZIndex = 41,
		Parent = frame,
	})
	UI.Button({
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(36, 36),
		Text = "✕",
		Variant = "Ghost",
		ZIndex = 41,
		Parent = frame,
	}, function()
		Elevator.ClosePanel()
	end)
	local scroller: ScrollingFrame = UI.Create("ScrollingFrame", {
		Name = "Floors",
		Position = UDim2.fromOffset(14, 48),
		Size = UDim2.new(1, -28, 1, -60),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Muted,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 41,
		Parent = frame,
	})
	local holder = UI.Grid(scroller, 1, 52, 44)
	grid = holder
	panel = frame
end

local function fillPanel(plot: number)
	local holder = grid
	local info = plotInfo(plot)
	if not holder or not info then
		return
	end
	for _, child in ipairs(holder:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local floors = math.max(1, math.floor(tonumber(info.Floors) or 1))
	local private = privateSet(info)
	local owner = info.Owner == player.UserId
	local current = currentFloor() or 1
	if titleLabel then
		titleLabel.Text = UI.Upper(T("tui.elevator.title"))
	end
	for floor = 1, floors do
		local locked = private[floor] == true and not owner
		local here = floor == current
		UI.Button({
			Name = "F" .. floor,
			Size = UDim2.fromOffset(52, 44),
			LayoutOrder = floor,
			Text = if floor == 1 then T("tui.elevator.lobby") elseif locked then "🔒" else tostring(floor),
			Variant = if here then "Primary" elseif locked then "Muted" else "Secondary",
			MaxText = 16,
			Corner = 10,
			ZIndex = 42,
			Parent = holder,
		}, function()
			if locked then
				ctx.Toast(T("tui.elevator.private"), "Error")
				return
			end
			Elevator.Go(floor)
		end)
	end
end

function Elevator.OpenPanel(plot: number?)
	if ride then
		return
	end
	local okInside, inside = call("TowerView", "InsideTower")
	local target = plot or (if okInside then inside else nil)
	if type(target) ~= "number" then
		ctx.Toast(T("tui.elevator.notInside"), "Error")
		return
	end
	if not panel then
		buildPanel()
	end
	panelPlot = target
	local part = rootPart()
	panelOrigin = if part then part.Position else nil
	fillPanel(target)
	local frame = panel
	if frame then
		frame.Visible = true
		local scale = frame:FindFirstChildOfClass("UIScale") or UI.Create("UIScale", { Parent = frame })
		UI.Pulse(scale :: UIScale, 0.04)
	end
	sfx("UIClick")
end

function Elevator.ClosePanel()
	if panel then
		panel.Visible = false
	end
	panelPlot = nil
	panelOrigin = nil
end

function Elevator.IsRiding(): boolean
	return ride ~= nil
end

-- ---------------------------------------------------------------------
-- KINOSZENE: Kabine im Kern, Kamera innen, Türen zu -> Fahrt -> Türen auf (1,5 s)
-- ---------------------------------------------------------------------
local function cabinPart(
	parts: { BasePart },
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	t: number?
): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material
	part.Transparency = t or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = fxFolder
	table.insert(parts, part)
	return part
end

local function cabinBase(info: { [string]: any }, floor: number): CFrame
	local fh = TowerModels.FloorHeight()
	local slab = TowerModels.SlabHeight()
	return (info.Pivot :: CFrame) * CFrame.new(0, (floor - 1) * fh + slab, 0)
end

local function buildCabin(base: CFrame): ({ BasePart }, BasePart, BasePart)
	local parts: { BasePart } = {}
	local glass = Color3.fromRGB(207, 227, 247)
	local metal = Color3.fromRGB(31, 41, 55)
	cabinPart(
		parts,
		Vector3.new(CABIN, 0.3, CABIN),
		base * CFrame.new(0, 0.15, 0),
		Color3.fromRGB(26, 33, 48),
		Enum.Material.Marble
	)
	cabinPart(parts, Vector3.new(CABIN, 0.3, CABIN), base * CFrame.new(0, CABIN_H, 0), metal, Enum.Material.Metal)
	cabinPart(
		parts,
		Vector3.new(0.2, CABIN_H, CABIN),
		base * CFrame.new(-CABIN / 2, CABIN_H / 2, 0),
		glass,
		Enum.Material.Glass,
		0.6
	)
	cabinPart(
		parts,
		Vector3.new(0.2, CABIN_H, CABIN),
		base * CFrame.new(CABIN / 2, CABIN_H / 2, 0),
		glass,
		Enum.Material.Glass,
		0.6
	)
	cabinPart(
		parts,
		Vector3.new(CABIN, CABIN_H, 0.2),
		base * CFrame.new(0, CABIN_H / 2, CABIN / 2),
		glass,
		Enum.Material.Glass,
		0.55
	)
	local strip = cabinPart(
		parts,
		Vector3.new(CABIN - 1, 0.15, 0.6),
		base * CFrame.new(0, CABIN_H - 0.3, 0),
		Theme.Accent,
		Enum.Material.Neon
	)
	local light = Instance.new("PointLight")
	light.Range = 12
	light.Brightness = 1.4
	light.Color = Color3.fromRGB(230, 240, 255)
	light.Parent = strip
	-- Türflügel vorn (−Z), anfangs offen
	local doorW = 2.4
	local doorL = cabinPart(
		parts,
		Vector3.new(doorW, 7.2, 0.2),
		base * CFrame.new(-3.4, 3.6, DOOR_Z),
		Color3.fromRGB(192, 199, 212),
		Enum.Material.Metal
	)
	local doorR = cabinPart(
		parts,
		Vector3.new(doorW, 7.2, 0.2),
		base * CFrame.new(3.4, 3.6, DOOR_Z),
		Color3.fromRGB(192, 199, 212),
		Enum.Material.Metal
	)
	return parts, doorL, doorR
end

local function hallDoors(plot: number, floor: number, openness: number)
	call("TowerView", "SetDoors", plot, floor, openness)
end

local function setDoors(r: Ride, base: CFrame, openness: number)
	local x = 1.2 + openness * 2.2
	r.DoorL.CFrame = base * CFrame.new(-x, 3.6, DOOR_Z)
	r.DoorR.CFrame = base * CFrame.new(x, 3.6, DOOR_Z)
end

local function endRide()
	local r = ride
	if not r then
		return
	end
	ride = nil
	call("WorldLook", "SetCinematic", false)
	local closing = hallClose
	local arrived = closing ~= nil and closing.Plot == r.Plot and closing.Floor == r.To and closing.Start >= r.Start
	if not arrived then
		-- abgebrochen (Respawn, Kamera übernommen): Etagen-Türen nicht halb offen stehen lassen
		hallDoors(r.Plot, r.From, 0)
		hallDoors(r.Plot, r.To, 0)
	end
	for _, part in ipairs(r.Parts) do
		part:Destroy()
	end
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = if r.Saved == Enum.CameraType.Scriptable then Enum.CameraType.Custom else r.Saved
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

local function request(floor: number)
	task.spawn(function()
		local reply = ctx.RequestFull("TowerElevator", { Floor = floor })
		local r = ride
		if r and r.To == floor then
			r.Ok = reply.Ok == true
		end
	end)
end

function Elevator.Go(floor: number)
	if type(floor) ~= "number" or floor ~= floor or ride then
		return
	end
	local okInside, plot = call("TowerView", "InsideTower")
	if not okInside or type(plot) ~= "number" then
		ctx.Toast(T("tui.elevator.notInside"), "Error")
		return
	end
	local info = plotInfo(plot)
	if not info then
		return
	end
	local floors = math.max(1, math.floor(tonumber(info.Floors) or 1))
	local target = math.clamp(math.floor(floor), 1, floors)
	local current = currentFloor() or 1
	Elevator.ClosePanel()
	if target == current then
		return
	end
	if privateSet(info)[target] and info.Owner ~= player.UserId then
		ctx.Toast(T("tui.elevator.private"), "Error")
		return
	end
	local camera = workspace.CurrentCamera
	if reduced() or not camera then
		request(target)
		sfx("ElevatorDing")
		return
	end
	local base = cabinBase(info, current)
	local parts, doorL, doorR = buildCabin(base)
	local r: Ride = {
		Plot = plot,
		From = current,
		To = target,
		Start = os.clock(),
		MoveStart = nil,
		OpenAt = nil,
		EndAt = nil,
		Ok = nil,
		Base = base,
		Parts = parts,
		DoorL = doorL,
		DoorR = doorR,
		Saved = camera.CameraType,
		Dinged = false,
	}
	ride = r
	camera.CameraType = Enum.CameraType.Scriptable
	call("WorldLook", "SetCinematic", true, 8) -- Kabine scharf, Schacht/Stadt durchs Glas weich
	camera.CFrame = CFrame.lookAt((base * CFrame.new(0, 5.2, 2.8)).Position, (base * CFrame.new(0, 4.6, -8)).Position)
	request(target)
	sfx("UIClick")
end

local function moveCabin(r: Ride, base: CFrame)
	local delta = base.Position - r.Base.Position
	for _, part in ipairs(r.Parts) do
		part.CFrame = part.CFrame + delta
	end
	r.Base = base
end

function Elevator.Step(_dt: number)
	-- Panel schließt, wenn man weggeht
	local frame = panel
	if frame and frame.Visible and panelOrigin then
		local part = rootPart()
		local okInside, inside = call("TowerView", "InsideTower")
		local left = okInside and panelPlot ~= nil and inside ~= panelPlot
		if not part or left or (part.Position - panelOrigin).Magnitude > PANEL_RANGE then
			Elevator.ClosePanel()
		end
	end
	-- Etagen-Türen nach der Ankunft wieder schließen (die Figur steht schon davor)
	local closing = hallClose
	if closing and not ride then
		local alpha = math.clamp((os.clock() - closing.Start - HALL_CLOSE_DELAY) / (DOOR_SECONDS * 1.5), 0, 1)
		hallDoors(closing.Plot, closing.Floor, 1 - alpha)
		if alpha >= 1 then
			hallClose = nil
		end
	end
	local r = ride
	if not r then
		return
	end
	local camera = workspace.CurrentCamera
	local info = plotInfo(r.Plot)
	if not camera or not info then
		endRide()
		return
	end
	local t = os.clock()
	local elapsed = t - r.Start
	-- 1) Türen schließen (Kabine + Etage)
	if not r.MoveStart then
		local openness = 1 - math.clamp(elapsed / DOOR_SECONDS, 0, 1)
		setDoors(r, r.Base, openness)
		hallDoors(r.Plot, r.From, openness)
		if elapsed >= DOOR_SECONDS then
			if r.Ok == true then
				r.MoveStart = t
			elseif r.Ok == false or elapsed > REPLY_WAIT then
				-- abgelehnt/keine Antwort: Türen wieder auf, zurück zur Figur
				r.MoveStart = t - RIDE_SECONDS
				r.To = r.From
			end
		end
	end
	-- 2) Fahrt im Schacht (Kamera fährt mit)
	local moveStart = r.MoveStart
	if moveStart and not r.OpenAt then
		local alpha = math.clamp((t - moveStart) / RIDE_SECONDS, 0, 1)
		local ease = alpha * alpha * (3 - 2 * alpha)
		local fromBase = cabinBase(info, r.From)
		local toBase = cabinBase(info, r.To)
		moveCabin(r, fromBase:Lerp(toBase, ease))
		setDoors(r, r.Base, 0)
		if alpha >= 1 then
			r.OpenAt = t
			if not r.Dinged then
				r.Dinged = true
				sfx("ElevatorDing")
			end
		end
	end
	-- 3) Türen auf (Kabine + Ziel-Etage), dann Kamera zurück; die Etagen-Türen schließen kurz danach
	local openAt = r.OpenAt
	if openAt then
		local alpha = math.clamp((t - openAt) / DOOR_SECONDS, 0, 1)
		setDoors(r, r.Base, alpha)
		hallDoors(r.Plot, r.To, alpha)
		if alpha >= 1 then
			hallClose = { Plot = r.Plot, Floor = r.To, Start = t }
			endRide()
			return
		end
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		endRide()
		return
	end
	camera.CFrame =
		CFrame.lookAt((r.Base * CFrame.new(0, 5.2, 2.8)).Position, (r.Base * CFrame.new(0, 4.6, -8)).Position)
end

function Elevator.Init(context: any)
	ctx = context
	local folder = Instance.new("Folder")
	folder.Name = "AkyElevatorFX"
	folder.Parent = workspace
	fxFolder = folder
	player.CharacterAdded:Connect(function()
		endRide()
		Elevator.ClosePanel()
	end)
	ctx.Hooks.On("WindowOpened", function()
		Elevator.ClosePanel()
	end)
end

function Elevator.Start() end

return Elevator
