-- =====================================================================
--  AKYTEX TYCOON – Umgebungsleben: Verkehr, Drohnen, Luftschiff, Hologramme, Firmen-Läden (Client/Modules/CityLife)
--  Besitzer: WP7 (Stadt, Grafik, Fahrzeuge). Vertrag: DESIGN.md §A5 (Umgebungsleben nur Client, Budget je Grafikstufe:
--  Verkehr 0/10/20/32 auf Splines, Lieferdrohnen 0/4/8/14, Hologramm-Werbetafeln fiktiver Firmen, Luftschiff mit ΛKYTEX-Logo;
--  Firmen-Läden bekommen Spot + Mini-Ticker, solange ihre Firma eine aktive News hat; keine Fußgänger-NPCs), §C7.5
--  (CityLife.SetDensity), §C16 (CityLife < 0,5 ms/Frame), §C14.3 (Asset-Plätze City.TrafficCar/Drone/Blimp mit Rezept).
--
--  Alles hier ist lokal (nie repliziert, nie kollidierend, kein Schatten) und gepoolt: Positionen kommen aus der
--  Server-Zeit (Clock.Now) -> Verkehr und Luftschiff stehen auf allen Clients an derselben Stelle. Bewegung über
--  workspace:BulkMoveTo, weit entfernte Autos werden nicht bewegt (unsichtbar geparkt).
--  Laden-Mini-Ticker: ein lokales Teil mit Attribut Monitor = Kürzel am Platz "ShopTicker" -> das Modul Monitors (WP5)
--  zeichnet den Live-Chart; Spot = SpotLight am Teil mit Attribut "ShopSpot".
--
--  Öffentliche API (§C7.5):
--    CityLife.SetDensity(mult)        0 … 2 (Tutorial/Fotomodus können das Leben dämpfen), Standard 1
--  Zusätzlich: CityLife.Counts(): { Traffic, Drones, Billboards } · CityLife.Frame(dt) · CityLife.Init(ctx) · CityLife.Start()
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CityLife = {}

type Lane = { Points: { Vector3 }, Spacing: number, Length: number, Dir: number, Speed: number }
type Mover = { Parts: { BasePart }, Offsets: { CFrame }, Lane: Lane?, Phase: number, Hidden: boolean }
type Drone = {
	Parts: { BasePart },
	Offsets: { CFrame },
	Center: Vector3,
	Radius: number,
	Height: number,
	Speed: number,
	Phase: number,
}
type Board = {
	Root: BasePart,
	Ring: BasePart,
	Gui: BillboardGui,
	Ticker: TextLabel,
	Change: TextLabel,
	I: number,
	Base: CFrame,
	Angle: number,
}
type ShopState = { Until: number, Shown: boolean, Monitor: BasePart? }

local ctx: any = nil
local cityCfg: any = {}
local lifeCfg: any = {}
local folder: Folder? = nil
local density = 1
local lanes: { Lane } = {}
local laneWeights: { number } = {}
local traffic: { Mover } = {}
local drones: { Drone } = {}
local boards: { Board } = {}
local blimp: { Parts: { BasePart }, Offsets: { CFrame } }? = nil
local shopStates: { [number]: ShopState } = {}
local tickerSlots: { [number]: BasePart } = {}
local spotParts: { [number]: BasePart } = {}
local shopFronts: { [number]: BasePart } = {}
local signals: { [BasePart]: { Lamp: string, Group: number } } = {}
local signalAccum = 0
local AssetSlot: any = nil

local LANE_SPACING = 8
local MAX_TRAFFIC = 48
local MAX_DRONES = 20
local SHOP_CHECK = 0.5
local BOARD_REFRESH = 1
local HIDE_Y = -2000
local shopAccum = 0
local boardAccum = 0
local SIGNAL_HZ = 4
local SIGNAL_CYCLE = 30 -- Sekunden: Grün 0–14, Gelb 14–17, Rot 17–30 (alle Clients gleich, aus der Server-Zeit)
local SIGNAL_LIT: { [string]: Color3 } = {
	Red = Color3.fromRGB(255, 64, 64),
	Amber = Color3.fromRGB(250, 190, 40),
	Green = Color3.fromRGB(34, 197, 94),
}
local SIGNAL_DIM: { [string]: Color3 } = {
	Red = Color3.fromRGB(70, 24, 24),
	Amber = Color3.fromRGB(70, 54, 16),
	Green = Color3.fromRGB(14, 52, 28),
}

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function call(name: string, fnName: string, ...: any): (boolean, any, any)
	local modules = ctx and ctx.Modules
	local m = modules and modules[name]
	local fn = m and m[fnName]
	if type(fn) ~= "function" then
		return false, nil, nil
	end
	return pcall(fn, ...)
end

local function tier(): string
	local ok, value = call("Quality", "Tier")
	return if ok and type(value) == "string" then value else "Medium"
end

local function budget(key: string, fallback: number): number
	local ok, value = call("Quality", "Budget", key)
	if ok and type(value) == "number" then
		return value
	end
	return fallback
end

local function serverTime(): number
	return ctx.Clock.Now()
end

local function localPart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		(part :: any)[key] = value
	end
	return part
end

local function ensureFolder(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local created = Instance.new("Folder")
	created.Name = "AT_CityLife"
	created.Parent = workspace
	folder = created
	return created
end

-- Ein Asset-Platz (City.<key>) als lokales Modell, sonst Rezept; Rückgabe: Teile + relative Lagen zum Pivot
local function assetOrRecipe(key: string, recipe: () -> { BasePart }): { BasePart }
	local slots = cityCfg.Assets
	local slot = type(slots) == "table" and slots[key] or nil
	if AssetSlot and slot and AssetSlot.IsSet(slot) then
		local ok, inst = pcall(AssetSlot.Mesh, AssetSlot.KeyOf("City", key), slot, function(): Instance
			local empty = Instance.new("Model")
			empty.Name = "Recipe"
			return empty
		end)
		if ok and typeof(inst) == "Instance" and inst.Name ~= "Recipe" then
			local parts: { BasePart } = {}
			for _, d in ipairs(inst:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
					d.CastShadow = false
					table.insert(parts, d)
				end
			end
			if inst:IsA("BasePart") then
				table.insert(parts, inst)
			end
			for _, part in ipairs(parts) do
				part.Parent = ensureFolder()
			end
			if inst:IsA("Model") then
				inst:Destroy()
			end
			if #parts > 0 then
				return parts
			end
		elseif ok and typeof(inst) == "Instance" then
			inst:Destroy()
		end
	end
	return recipe()
end

local function offsetsOf(parts: { BasePart }, pivot: CFrame): { CFrame }
	local offsets: { CFrame } = {}
	for i, part in ipairs(parts) do
		offsets[i] = pivot:Inverse() * part.CFrame
	end
	return offsets
end

local function destroyParts(parts: { BasePart })
	for _, part in ipairs(parts) do
		part:Destroy()
	end
end

-- ---------------------------------------------------------------------
-- 1) SPUREN (gleichmäßig abgetastete Ringe mit Spur-Versatz)
-- ---------------------------------------------------------------------
local function buildLane(def: any): Lane?
	local roadRadius = cityCfg.RoadRadius
	if type(roadRadius) ~= "function" then
		return nil
	end
	local y = (cityCfg.Levels and cityCfg.Levels.Road or 0.25)
	local samples = 1080
	local fine: { Vector3 } = {}
	for i = 0, samples - 1 do
		local deg = i * 360 / samples
		local okR, r = pcall(roadRadius, def.Road, deg, def.Offset)
		if not okR then
			return nil
		end
		local a = math.rad(deg)
		table.insert(fine, Vector3.new(r * math.cos(a), y, r * math.sin(a)))
	end
	local cumulative = { 0 }
	local total = 0
	for i = 1, samples do
		total += (fine[(i % samples) + 1] - fine[i]).Magnitude
		cumulative[i + 1] = total
	end
	local count = math.max(16, math.floor(total / LANE_SPACING))
	local spacing = total / count
	local points: { Vector3 } = {}
	local j = 1
	for k = 0, count - 1 do
		local s = k * spacing
		while j < samples and cumulative[j + 1] < s do
			j += 1
		end
		local seg = cumulative[j + 1] - cumulative[j]
		local f = if seg > 0 then (s - cumulative[j]) / seg else 0
		table.insert(points, fine[j]:Lerp(fine[(j % samples) + 1], f))
	end
	return { Points = points, Spacing = spacing, Length = total, Dir = def.Dir or 1, Speed = def.Speed or 40 }
end

-- Lage auf einer Spur bei Bogenlänge s (geschlossen)
local function laneCFrame(lane: Lane, s: number): CFrame
	local n = #lane.Points
	local u = (s % lane.Length) / lane.Spacing
	local i = math.floor(u)
	local f = u - i
	local a = lane.Points[(i % n) + 1]
	local b = lane.Points[((i + 1) % n) + 1]
	local pos = a:Lerp(b, f)
	local dir = (b - a) * lane.Dir
	if dir.Magnitude < 1e-4 then
		dir = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(pos, pos + dir)
end

-- ---------------------------------------------------------------------
-- 2) VERKEHR
-- ---------------------------------------------------------------------
local function makeTrafficCar(index: number): { BasePart }
	local colors = lifeCfg.TrafficColors or { Color3.fromRGB(30, 34, 44) }
	local color = colors[(index % #colors) + 1]
	local parts: { BasePart } = {}
	local function add(props: { [string]: any })
		local part = localPart(props)
		part.Parent = ensureFolder()
		table.insert(parts, part)
	end
	add({
		Size = Vector3.new(6, 1.8, 12.5),
		CFrame = CFrame.new(0, 1.7, 0),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.15,
	})
	add({
		Size = Vector3.new(5.2, 1.6, 6),
		CFrame = CFrame.new(0, 3.4, 0.6),
		Color = Color3.fromRGB(14, 20, 32),
		Material = Enum.Material.Glass,
		Transparency = 0.2,
		Reflectance = 0.3,
	})
	for _, z in ipairs({ -3.8, 3.8 }) do
		local wheel = localPart({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(6.3, 2.3, 2.3),
			CFrame = CFrame.new(0, 1.15, z),
			Color = Color3.fromRGB(22, 23, 27),
			Material = Enum.Material.SmoothPlastic,
		})
		wheel.Parent = ensureFolder()
		table.insert(parts, wheel)
	end
	add({
		Size = Vector3.new(5, 0.25, 0.1),
		CFrame = CFrame.new(0, 1.9, -6.3),
		Color = Color3.fromRGB(235, 242, 255),
		Material = Enum.Material.Neon,
	})
	add({
		Size = Vector3.new(5, 0.25, 0.1),
		CFrame = CFrame.new(0, 2.1, 6.3),
		Color = Color3.fromRGB(239, 48, 56),
		Material = Enum.Material.Neon,
	})
	return parts
end

local function wantedTraffic(): number
	return math.clamp(math.floor(budget("Traffic", 10) * density + 0.5), 0, MAX_TRAFFIC)
end

local function pickLane(index: number): Lane?
	if #lanes == 0 then
		return nil
	end
	-- nach Länge gewichtet, deterministisch
	local total = 0
	for _, w in ipairs(laneWeights) do
		total += w
	end
	local x = ((index * 0.6180339887) % 1) * total
	for i, w in ipairs(laneWeights) do
		x -= w
		if x <= 0 then
			return lanes[i]
		end
	end
	return lanes[#lanes]
end

local function syncTraffic()
	local want = wantedTraffic()
	while #traffic > want do
		local mover = table.remove(traffic) :: Mover
		destroyParts(mover.Parts)
	end
	while #traffic < want do
		local index = #traffic + 1
		local parts = assetOrRecipe("TrafficCar", function()
			return makeTrafficCar(index)
		end)
		table.insert(traffic, {
			Parts = parts,
			Offsets = offsetsOf(parts, CFrame.identity),
			Lane = pickLane(index),
			Phase = (index * 0.37) % 1,
			Hidden = false,
		})
	end
end

local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

local function updateTraffic()
	local camera = workspace.CurrentCamera
	local origin = if camera then camera.CFrame.Position else Vector3.zero
	local radius = lifeCfg.UpdateRadius or 900
	local t = serverTime()
	table.clear(moveParts)
	table.clear(moveCFrames)
	for _, mover in ipairs(traffic) do
		local lane = mover.Lane
		if not lane then
			continue
		end
		local s = mover.Phase * lane.Length + lane.Dir * lane.Speed * t -- Dir −1 fährt die Punktliste rückwärts
		local cf = laneCFrame(lane, s)
		local far = (cf.Position - origin).Magnitude > radius
		if far and mover.Hidden then
			continue
		end
		if far then
			cf = CFrame.new(cf.X, HIDE_Y, cf.Z)
			mover.Hidden = true
		else
			mover.Hidden = false
		end
		for i, part in ipairs(mover.Parts) do
			table.insert(moveParts, part)
			table.insert(moveCFrames, cf * mover.Offsets[i])
		end
	end
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- ---------------------------------------------------------------------
-- 3) DROHNEN
-- ---------------------------------------------------------------------
local function makeDrone(): { BasePart }
	local parts: { BasePart } = {}
	local function add(props: { [string]: any })
		local part = localPart(props)
		part.Parent = ensureFolder()
		table.insert(parts, part)
	end
	add({
		Size = Vector3.new(1.8, 0.5, 1.8),
		CFrame = CFrame.new(0, 0, 0),
		Color = Color3.fromRGB(26, 33, 48),
		Material = Enum.Material.Metal,
	})
	for _, x in ipairs({ -1.4, 1.4 }) do
		for _, z in ipairs({ -1.4, 1.4 }) do
			add({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.08, 1.6, 1.6),
				CFrame = CFrame.new(x, 0.3, z) * CFrame.Angles(0, 0, math.pi / 2),
				Color = Color3.fromRGB(79, 140, 255),
				Material = Enum.Material.Neon,
				Transparency = 0.45,
			})
		end
	end
	add({
		Size = Vector3.new(1.2, 1, 1.2),
		CFrame = CFrame.new(0, -0.9, 0),
		Color = Color3.fromRGB(245, 158, 11),
		Material = Enum.Material.SmoothPlastic,
	})
	-- Positionslicht (blinkt, nachts gut sichtbar)
	local blink = localPart({
		Name = "NavBlink",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.45, 0.45, 0.45),
		CFrame = CFrame.new(0, 0.45, 0),
		Color = Color3.fromRGB(239, 68, 68),
		Material = Enum.Material.Neon,
	})
	blink.Parent = ensureFolder()
	table.insert(parts, blink)
	return parts
end

local function syncDrones()
	local want = math.clamp(math.floor(budget("Drones", 4) * density + 0.5), 0, MAX_DRONES)
	local cfgD = lifeCfg.Drones or {}
	while #drones > want do
		local drone = table.remove(drones) :: Drone
		destroyParts(drone.Parts)
	end
	while #drones < want do
		local index = #drones + 1
		local parts = assetOrRecipe("Drone", makeDrone)
		local u = (index * 0.6180339887) % 1
		local v = (index * 0.3819660113) % 1
		local minR, maxR = cfgD.MinRadius or 160, cfgD.MaxRadius or 700
		local angle = u * 2 * math.pi
		local dist = minR + v * (maxR - minR) * 0.6
		table.insert(drones, {
			Parts = parts,
			Offsets = offsetsOf(parts, CFrame.identity),
			Center = Vector3.new(dist * math.cos(angle), 0, dist * math.sin(angle)),
			Radius = 60 + v * 140,
			Height = (cfgD.MinHeight or 70) + u * ((cfgD.MaxHeight or 150) - (cfgD.MinHeight or 70)),
			Speed = cfgD.Speed or 26,
			Phase = u * 2 * math.pi,
		})
	end
end

local function updateDrones()
	local t = serverTime()
	table.clear(moveParts)
	table.clear(moveCFrames)
	for _, drone in ipairs(drones) do
		local w = drone.Speed / drone.Radius
		local a = drone.Phase + w * t
		local pos = drone.Center
			+ Vector3.new(
				drone.Radius * math.cos(a),
				drone.Height + math.sin(t * 1.3 + drone.Phase) * 2.5,
				drone.Radius * math.sin(a)
			)
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		local cf = CFrame.lookAt(pos, pos + tangent) * CFrame.Angles(math.rad(-8), 0, 0)
		local blinkOn = (t * 1.2 + drone.Phase) % 1 < 0.18
		for i, part in ipairs(drone.Parts) do
			table.insert(moveParts, part)
			table.insert(moveCFrames, cf * drone.Offsets[i])
			if part.Name == "NavBlink" then
				local transparency = if blinkOn then 0 else 0.85
				if part.Transparency ~= transparency then
					part.Transparency = transparency
				end
			end
		end
	end
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- ---------------------------------------------------------------------
-- 4) LUFTSCHIFF MIT ΛKYTEX-LOGO
-- ---------------------------------------------------------------------
local function logoText(): string
	for _, sign in ipairs(cityCfg.Signs or {}) do
		if sign.Key == "Logo" then
			return sign.Name
		end
	end
	return ctx.T("core.gameName")
end

local function makeBlimp(): { BasePart }
	local parts: { BasePart } = {}
	local function add(props: { [string]: any }): Part
		local part = localPart(props)
		part.Parent = ensureFolder()
		table.insert(parts, part)
		return part
	end
	local envelope = add({
		Size = Vector3.new(26, 22, 70),
		CFrame = CFrame.identity,
		Color = Color3.fromRGB(226, 230, 238),
		Material = Enum.Material.SmoothPlastic,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = envelope
	add({
		Size = Vector3.new(6, 3.4, 14),
		CFrame = CFrame.new(0, -12, -2),
		Color = Color3.fromRGB(26, 33, 48),
		Material = Enum.Material.Metal,
	})
	add({
		Size = Vector3.new(26.4, 0.6, 30),
		CFrame = CFrame.new(0, -2, 0),
		Color = Color3.fromRGB(79, 140, 255),
		Material = Enum.Material.Neon,
		Transparency = 0.1,
	})
	for _, def in ipairs({
		{ CFrame.new(0, 7, 32), Vector3.new(0.6, 8, 8) },
		{ CFrame.new(0, -7, 32), Vector3.new(0.6, 8, 8) },
		{ CFrame.new(7, 0, 32), Vector3.new(8, 0.6, 8) },
		{ CFrame.new(-7, 0, 32), Vector3.new(8, 0.6, 8) },
	}) do
		add({
			Size = def[2],
			CFrame = def[1],
			Color = Color3.fromRGB(26, 33, 48),
			Material = Enum.Material.SmoothPlastic,
		})
	end
	for _, side in ipairs({ -1, 1 }) do
		local plate = add({
			Size = Vector3.new(0.2, 7, 26),
			CFrame = CFrame.new(side * 13.1, 3, -2),
			Color = Color3.fromRGB(11, 15, 23),
			Material = Enum.Material.SmoothPlastic,
			Transparency = 1,
		})
		local gui = Instance.new("SurfaceGui")
		gui.Face = if side > 0 then Enum.NormalId.Right else Enum.NormalId.Left
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		gui.LightInfluence = 0
		gui.Brightness = 2
		gui.MaxDistance = 2000
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Text = logoText()
		label.TextColor3 = Color3.fromRGB(110, 162, 242)
		label.TextScaled = true
		label.FontFace = Font.new("rbxasset://fonts/families/BuilderExtended.json", Enum.FontWeight.Bold)
		label.Parent = gui
		gui.Parent = plate
	end
	return parts
end

local function syncBlimp()
	local cfgB = lifeCfg.Blimp or {}
	local want = cfgB[tier()] ~= false
	if want and not blimp then
		local parts = assetOrRecipe("Blimp", makeBlimp)
		blimp = { Parts = parts, Offsets = offsetsOf(parts, CFrame.identity) }
	elseif not want and blimp then
		destroyParts(blimp.Parts)
		blimp = nil
	end
end

local function updateBlimp()
	local b = blimp
	if not b then
		return
	end
	local cfgB = lifeCfg.Blimp or {}
	local r = cfgB.Radius or 720
	local a = serverTime() * (cfgB.Speed or 11) / r
	local pos = Vector3.new(r * math.cos(a), (cfgB.Height or 270) + math.sin(a * 3) * 4, r * math.sin(a))
	local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
	local cf = CFrame.lookAt(pos, pos + tangent) -- Nase (-Z) in Flugrichtung, Leitwerke (+Z) hinten
	table.clear(moveParts)
	table.clear(moveCFrames)
	for i, part in ipairs(b.Parts) do
		table.insert(moveParts, part)
		table.insert(moveCFrames, cf * b.Offsets[i])
	end
	workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
end

-- ---------------------------------------------------------------------
-- 5) HOLOGRAMM-WERBETAFELN (fiktive Firmen, Live-Kurs aus dem Frame)
-- ---------------------------------------------------------------------
local function companyOf(i: number): any?
	local companies = ctx.Config.Companies
	local byId = type(companies) == "table" and companies.ById or nil
	return if type(byId) == "table" then byId[i] else nil
end

local function sectorColor(sector: string?): Color3
	local colors = ctx.Config.Colors and ctx.Config.Colors.Sectors
	if type(colors) == "table" and sector and typeof(colors[sector]) == "Color3" then
		return colors[sector]
	end
	return Color3.fromRGB(79, 140, 255)
end

local function makeBoard(def: any): Board?
	local company = companyOf(def.I)
	if not company then
		return nil
	end
	local color = sectorColor(company.Sector)
	local a = math.rad(def.Angle)
	local pos = Vector3.new(def.Radius * math.cos(a), def.Height, def.Radius * math.sin(a))
	local root = localPart({
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(pos),
		Transparency = 1,
	})
	root.Parent = ensureFolder()
	local ring = localPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, 14, 14),
		CFrame = CFrame.new(pos - Vector3.new(0, 6, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
	})
	ring.Parent = ensureFolder()
	-- Hologramm-Projektor: Lichtkegel vom Ring zur Tafel + aufsteigende Funken (Partikel im Budget)
	local beamFrom = Instance.new("Attachment")
	beamFrom.Name = "HoloFrom"
	beamFrom.Parent = ring
	local beamTo = Instance.new("Attachment")
	beamTo.Name = "HoloTo"
	beamTo.Parent = root
	local cone = Instance.new("Beam")
	cone.Name = "HoloCone"
	cone.Attachment0 = beamFrom
	cone.Attachment1 = beamTo
	cone.Width0 = 12
	cone.Width1 = 17
	cone.FaceCamera = true
	cone.LightEmission = 1
	cone.LightInfluence = 0
	cone.Texture = "rbxasset://textures/gradient.png"
	cone.TextureMode = Enum.TextureMode.Stretch
	cone.Color = ColorSequence.new(color)
	cone.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 0.92),
	})
	cone.Segments = 2
	cone.Parent = ring
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "HoloSparks"
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(color)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	sparks.Lifetime = NumberRange.new(1.2, 2)
	sparks.Speed = NumberRange.new(2, 4)
	sparks.SpreadAngle = Vector2.new(25, 25)
	sparks.Acceleration = Vector3.new(0, 1.5, 0)
	sparks.EmissionDirection = Enum.NormalId.Right -- Zylinder-Achse X = senkrecht
	sparks.Rate = math.floor(6 * budget("Particles", 0.6) + 0.5)
	sparks.Parent = ring
	local gui = Instance.new("BillboardGui")
	gui.Name = "Hologram"
	gui.Size = UDim2.fromScale(18, 8)
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.MaxDistance = 700
	gui.Adornee = root
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(11, 15, 23)
	frame.BackgroundTransparency = 0.45
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.12, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 2
	stroke.Transparency = 0.2
	stroke.Parent = frame
	local ticker = Instance.new("TextLabel")
	ticker.BackgroundTransparency = 1
	ticker.Position = UDim2.fromScale(0.06, 0.06)
	ticker.Size = UDim2.fromScale(0.88, 0.48)
	ticker.FontFace = Font.new("rbxasset://fonts/families/BuilderExtended.json", Enum.FontWeight.Bold)
	ticker.Text = company.Ticker
	ticker.TextColor3 = color
	ticker.TextScaled = true
	ticker.Parent = frame
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromScale(0.06, 0.56)
	name.Size = UDim2.fromScale(0.56, 0.36)
	name.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
	name.Text = company.Name
	name.TextColor3 = Color3.fromRGB(230, 236, 245)
	name.TextScaled = true
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = frame
	local change = Instance.new("TextLabel")
	change.BackgroundTransparency = 1
	change.Position = UDim2.fromScale(0.62, 0.56)
	change.Size = UDim2.fromScale(0.32, 0.36)
	change.FontFace = Font.new("rbxasset://fonts/families/BuilderMono.json", Enum.FontWeight.Bold)
	change.Text = ""
	change.TextColor3 = Color3.fromRGB(170, 180, 195)
	change.TextScaled = true
	change.TextXAlignment = Enum.TextXAlignment.Right
	change.Parent = frame
	gui.Parent = root
	return {
		Root = root,
		Ring = ring,
		Gui = gui,
		Ticker = ticker,
		Change = change,
		I = def.I,
		Base = ring.CFrame,
		Angle = 0,
	}
end

local function syncBoards()
	local counts = lifeCfg.Billboards or {}
	local list = cityCfg.Billboards or {}
	local want = math.clamp(math.floor((counts[tier()] or 8) * math.min(1, density) + 0.5), 0, #list)
	while #boards > want do
		local board = table.remove(boards) :: Board
		board.Root:Destroy()
		board.Ring:Destroy()
	end
	while #boards < want do
		local def = list[#boards + 1]
		local board = makeBoard(def)
		if not board then
			break
		end
		table.insert(boards, board)
	end
end

local function refreshBoards()
	local lang = ctx.Lang_()
	for _, board in ipairs(boards) do
		local ok, _close, change = call("MarketClient", "Quote", board.I)
		if ok and type(change) == "number" then
			local okText, text = pcall(ctx.Format.Pct, change, lang, 2, true)
			local okArrow, arrow = call("UI", "TrendArrow", change)
			board.Change.Text = (if okArrow then tostring(arrow) .. " " else "") .. (if okText then text else "")
			local okColor, color = call("UI", "TrendColor", change)
			if okColor and typeof(color) == "Color3" then
				board.Change.TextColor3 = color
			end
		end
	end
end

local function spinBoards(dt: number)
	for _, board in ipairs(boards) do
		board.Angle = (board.Angle + dt * 0.6) % (2 * math.pi)
		board.Ring.CFrame = CFrame.new(board.Base.Position)
			* CFrame.Angles(0, board.Angle, 0)
			* CFrame.Angles(0, 0, math.pi / 2)
	end
end

-- ---------------------------------------------------------------------
-- 6) FIRMEN-LÄDEN: Spot + Mini-Ticker bei aktiver News
-- ---------------------------------------------------------------------
local function shopActive(i: number, seconds: number)
	local state = shopStates[i]
	if not state then
		return
	end
	state.Until = math.max(state.Until, serverTime() + seconds)
end

local function showShop(i: number, on: boolean)
	local state = shopStates[i]
	if not state or state.Shown == on then
		return
	end
	state.Shown = on
	local spot = spotParts[i]
	if spot and spot.Parent then
		local light = spot:FindFirstChildWhichIsA("SpotLight")
		if light then
			light.Enabled = on
		end
	end
	local front = shopFronts[i]
	if front and front.Parent then
		local gui = front:FindFirstChildWhichIsA("SurfaceGui")
		if gui then
			gui.Brightness = if on then 3.6 else 2.2
		end
	end
	if on then
		local slot = tickerSlots[i]
		local company = companyOf(i)
		if slot and slot.Parent and company then
			local monitor = localPart({
				Name = "ShopTickerLive",
				Size = slot.Size,
				CFrame = slot.CFrame,
				Color = Color3.fromRGB(11, 15, 23),
				Material = Enum.Material.SmoothPlastic,
			})
			monitor:SetAttribute("Monitor", company.Ticker) -- Modul Monitors zeichnet den Live-Chart
			monitor.Parent = ensureFolder()
			state.Monitor = monitor
		end
	else
		local monitor = state.Monitor
		state.Monitor = nil
		if monitor then
			monitor:Destroy()
		end
	end
end

local function checkShops()
	local t = serverTime()
	for i, state in pairs(shopStates) do
		local on = state.Until > t
		if on and state.Shown and (not state.Monitor or not state.Monitor.Parent) and tickerSlots[i] then
			state.Shown = false -- Platz neu hereingestreamt -> Ticker neu anlegen
		end
		showShop(i, on)
	end
end

local function considerWorld(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	local ticker = inst:GetAttribute("ShopTicker")
	if type(ticker) == "number" then
		tickerSlots[ticker] = inst
	end
	local spot = inst:GetAttribute("ShopSpot")
	if type(spot) == "number" then
		spotParts[spot] = inst
		local state = shopStates[spot]
		local light = inst:FindFirstChildWhichIsA("SpotLight")
		if light and state then
			light.Enabled = state.Shown
		end
	end
	local shop = inst:GetAttribute("Shop")
	if type(shop) == "number" then
		shopFronts[shop] = inst
	end
	local lamp = inst:GetAttribute("Signal")
	if type(lamp) == "string" and SIGNAL_LIT[lamp] then
		signals[inst] = { Lamp = lamp, Group = tonumber(inst:GetAttribute("SignalGroup")) or 0 }
	end
end

-- Ampeln an den Avenue-Einmündungen schalten (rein optisch, alle Clients gleich)
local function stepSignals()
	local t = serverTime()
	for part, info in pairs(signals) do
		if not part.Parent then
			signals[part] = nil
			continue
		end
		local phase = (t + info.Group / 12) % SIGNAL_CYCLE
		local active = if phase < 14 then "Green" elseif phase < 17 then "Amber" else "Red"
		local lit = info.Lamp == active
		local color = if lit then SIGNAL_LIT[info.Lamp] else SIGNAL_DIM[info.Lamp]
		if part.Color ~= color then
			part.Color = color
			part.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICHE API
-- ---------------------------------------------------------------------
local function syncAll()
	syncTraffic()
	syncDrones()
	syncBlimp()
	syncBoards()
end

function CityLife.SetDensity(mult: number)
	if type(mult) ~= "number" or mult ~= mult then
		return
	end
	density = math.clamp(mult, 0, 2)
	syncAll()
end

function CityLife.Counts(): { [string]: number }
	return { Traffic = #traffic, Drones = #drones, Billboards = #boards }
end

function CityLife.Frame(dt: number)
	updateTraffic()
	updateDrones()
	updateBlimp()
	spinBoards(dt)
	shopAccum += dt
	if shopAccum >= SHOP_CHECK then
		shopAccum = 0
		checkShops()
	end
	boardAccum += dt
	if boardAccum >= BOARD_REFRESH then
		boardAccum = 0
		refreshBoards()
	end
	signalAccum += dt
	if signalAccum >= 1 / SIGNAL_HZ then
		signalAccum = 0
		stepSignals()
	end
end

function CityLife.Init(context: any)
	ctx = context
	cityCfg = ctx.Config.City or {}
	lifeCfg = cityCfg.Life or {}
	local assetModule = ReplicatedStorage:FindFirstChild("Shared")
		and ReplicatedStorage.Shared:FindFirstChild("AssetSlot")
	if assetModule and assetModule:IsA("ModuleScript") then
		local ok, result = pcall(require, assetModule)
		AssetSlot = if ok then result else nil
	end
	for _, def in ipairs(cityCfg.Lanes or {}) do
		local lane = buildLane(def)
		if lane then
			table.insert(lanes, lane)
			table.insert(laneWeights, lane.Length)
		end
	end
	for instId in pairs(cityCfg.Shops or {}) do
		shopStates[instId] = { Until = 0, Shown = false, Monitor = nil }
	end
	local newsSeconds = cityCfg.ShopNewsSeconds or 120
	local hooks = ctx.Hooks
	hooks.On("Market:News", function(news: any)
		if type(news) == "table" and type(news.I) == "number" then
			shopActive(news.I, newsSeconds)
		end
	end)
	hooks.On("Quotes", function(frame: any)
		if type(frame) ~= "table" or type(frame.Rows) ~= "table" then
			return
		end
		for _, row in ipairs(frame.Rows) do
			if shopStates[row.Id] and bit32.band(row.Flags or 0, 2) ~= 0 then -- QuoteCodec.ROW_FLAGS.News
				shopActive(row.Id, 3)
			end
		end
	end)
	hooks.On("Quality", function()
		syncAll()
	end)
end

function CityLife.Start()
	syncAll()
	workspace.DescendantAdded:Connect(considerWorld)
	task.spawn(function()
		local ok, list = pcall(function()
			return workspace:GetDescendants()
		end)
		if ok and type(list) == "table" then
			for index, inst in ipairs(list) do
				considerWorld(inst)
				if index % 2000 == 0 then
					task.wait()
				end
			end
		end
	end)
end

return CityLife
