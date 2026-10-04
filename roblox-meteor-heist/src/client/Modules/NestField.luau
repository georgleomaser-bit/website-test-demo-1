-- =====================================================================
--  EI-RENNEN (alles lokal auf deinem Gerät)
--   • Wilde Kreaturen: der Server schickt pro Kreatur nur ein Text-Attribut "S"
--     ("Serverzeit|x|z|vx|vz|Modus", Ordner NestField/Creatures). Hier wird ein blockiges Monster
--     (9 Teile) gebaut und weich bewegt: Position vorhersagen (x + v * Zeit) und glätten.
--     Modus 1 = jagt: rote Augen + "!" über dem Kopf. Nachts leuchten alle Augen rot.
--   • Neue Eier in den Nestern ploppen kurz auf (Effekt "NestPop" + kleiner Größen-Hüpfer).
--   • Speed-Pad berührt (Attribut "SpeedPadUntil"): Sichtfeld wird kurz weiter (Tempo-Gefühl).
--  Leistung: alle Teile mit EINEM workspace:BulkMoveTo pro Frame, weit weg seltener.
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local NestField = {}

local player = Players.LocalPlayer
local ctx: any = nil
local fxFolder: Folder? = nil
local hidden = false -- Foto-Modus: "!" aus

local GROUND_Y = 0.2 -- Oberkante des Feld-Bodens (MapBuilder FIELD_TOP)
local MAX_LEAD = 0.5 -- höchstens so weit (Sekunden) vorhersagen
local SMOOTH = 10 -- wie schnell die Anzeige der Vorhersage folgt (1/s)
local TURN = 8
local FAR_DISTANCE = 220 -- weiter weg: nur jedes FAR_SKIP. Frame bewegen
local FAR_SKIP = 4
local POP_RANGE = 160 -- Eier-Pop nur in der Nähe
local POP_TIME = 0.35
local FOV_BOOST = 10
local FOV_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BODY_COLORS = {
	Color3.fromRGB(120, 70, 200),
	Color3.fromRGB(70, 160, 70),
	Color3.fromRGB(220, 90, 60),
}
local DARK = Color3.fromRGB(40, 35, 45)
local EYE_RED = Color3.fromRGB(255, 40, 40)

-- Teile relativ zum Fußpunkt (Blick nach -Z): Name, Größe, Versatz, Farbe (nil = Körperfarbe)
type PartDef = { Name: string, Size: Vector3, Offset: Vector3, Color: Color3? }
local PART_DEFS: { PartDef } = {
	{ Name = "Body", Size = Vector3.new(4.2, 3.6, 3.8), Offset = Vector3.new(0, 2.7, 0) },
	{
		Name = "Belly",
		Size = Vector3.new(2.6, 1.8, 0.2),
		Offset = Vector3.new(0, 2.3, -1.95),
		Color = Color3.fromRGB(240, 230, 200),
	},
	{
		Name = "EyeL",
		Size = Vector3.new(1, 1, 0.2),
		Offset = Vector3.new(-0.9, 3.6, -1.95),
		Color = Color3.new(1, 1, 1),
	},
	{
		Name = "EyeR",
		Size = Vector3.new(1, 1, 0.2),
		Offset = Vector3.new(0.9, 3.6, -1.95),
		Color = Color3.new(1, 1, 1),
	},
	{ Name = "PupilL", Size = Vector3.new(0.5, 0.5, 0.2), Offset = Vector3.new(-0.9, 3.55, -2.1), Color = DARK },
	{ Name = "PupilR", Size = Vector3.new(0.5, 0.5, 0.2), Offset = Vector3.new(0.9, 3.55, -2.1), Color = DARK },
	{ Name = "HornL", Size = Vector3.new(0.6, 1.2, 0.6), Offset = Vector3.new(-1.4, 5.1, 0), Color = DARK },
	{ Name = "HornR", Size = Vector3.new(0.6, 1.2, 0.6), Offset = Vector3.new(1.4, 5.1, 0), Color = DARK },
	{ Name = "FootL", Size = Vector3.new(1.3, 0.9, 1.6), Offset = Vector3.new(-1.1, 0.45, 0), Color = DARK },
	{ Name = "FootR", Size = Vector3.new(1.3, 0.9, 1.6), Offset = Vector3.new(1.1, 0.45, 0), Color = DARK },
}

type Monster = {
	Source: Instance,
	Parts: { BasePart },
	Pupils: { BasePart },
	Alert: BillboardGui,
	-- Stand vom Server
	T: number,
	X: number,
	Z: number,
	VX: number,
	VZ: number,
	Mode: number,
	-- Anzeige
	Pos: Vector3,
	Yaw: number,
	Phase: number,
	Red: boolean?,
}

local monsters: { [Instance]: Monster } = {}
local bounds = { MinX = -29, MaxX = 29, MinZ = -205, MaxZ = 240 }
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}
local frame = 0
local baseFov: number? = nil
local fovToken = 0

local function parseState(monster: Monster)
	local text = monster.Source:GetAttribute("S")
	if type(text) ~= "string" then
		return
	end
	local t, x, z, vx, vz, mode = string.match(text, "^([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)$")
	local nt, nx, nz = tonumber(t), tonumber(x), tonumber(z)
	if not nt or not nx or not nz then
		return
	end
	monster.T, monster.X, monster.Z = nt, nx, nz
	monster.VX, monster.VZ = tonumber(vx) or 0, tonumber(vz) or 0
	monster.Mode = tonumber(mode) or 0
end

local function buildMonster(source: Instance)
	local folder = fxFolder
	if not folder or monsters[source] then
		return
	end
	local look = math.clamp(math.floor(tonumber(source:GetAttribute("Look")) or 1), 1, #BODY_COLORS)
	local bodyColor = BODY_COLORS[look]
	local model = Instance.new("Model")
	model.Name = "Creature"
	local parts: { BasePart } = {}
	local pupils: { BasePart } = {}
	for _, def in ipairs(PART_DEFS) do
		local p = Instance.new("Part")
		p.Name = def.Name
		p.Size = def.Size
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = def.Name == "Body"
		p.Material = Enum.Material.SmoothPlastic
		p.Color = def.Color or bodyColor
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CFrame = CFrame.new(0, -500, 0)
		p.Parent = model
		table.insert(parts, p)
		if def.Name == "PupilL" or def.Name == "PupilR" then
			table.insert(pupils, p)
		end
	end
	-- "!" über dem Kopf, solange es jagt
	local alert = Instance.new("BillboardGui")
	alert.Name = "Alert"
	alert.Size = UDim2.fromOffset(40, 50)
	alert.StudsOffset = Vector3.new(0, 4, 0)
	alert.MaxDistance = 120
	alert.Enabled = false
	alert.Adornee = parts[1]
	alert.Parent = parts[1]
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "!"
	label.TextColor3 = EYE_RED
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = label
	label.Parent = alert
	model.Parent = folder

	local monster: Monster = {
		Source = source,
		Parts = parts,
		Pupils = pupils,
		Alert = alert,
		T = workspace:GetServerTimeNow(),
		X = 0,
		Z = 0,
		VX = 0,
		VZ = 0,
		Mode = 0,
		Pos = Vector3.zero,
		Yaw = 0,
		Phase = 0,
		Red = nil,
	}
	parseState(monster)
	monster.Pos = Vector3.new(monster.X, GROUND_Y, monster.Z)
	monsters[source] = monster
	source:GetAttributeChangedSignal("S"):Connect(function()
		parseState(monster)
	end)
	source.Destroying:Connect(function()
		monsters[source] = nil
		model:Destroy()
	end)
	source.AncestryChanged:Connect(function()
		if not source:IsDescendantOf(workspace) then
			monsters[source] = nil
			model:Destroy()
		end
	end)
end

local function setEyes(monster: Monster, red: boolean)
	if monster.Red == red then
		return
	end
	monster.Red = red
	for _, pupil in ipairs(monster.Pupils) do
		pupil.Color = if red then EYE_RED else DARK
		pupil.Material = if red then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
end

local function step(dt: number)
	frame += 1
	local camera = workspace.CurrentCamera
	local camPos = if camera then camera.CFrame.Position else Vector3.zero
	local now = workspace:GetServerTimeNow()
	local night = ReplicatedStorage:GetAttribute("IsNight") == true
	local alpha = 1 - math.exp(-SMOOTH * dt)
	local turnAlpha = 1 - math.exp(-TURN * dt)
	table.clear(moveParts)
	table.clear(moveCFrames)
	local count = 0
	local index = 0
	for _, monster in pairs(monsters) do
		index += 1
		local far = (monster.Pos - camPos).Magnitude > FAR_DISTANCE
		if not far or (frame + index) % FAR_SKIP == 0 then
			local stepDt = if far then dt * FAR_SKIP else dt
			local lead = math.clamp(now - monster.T, 0, MAX_LEAD)
			local px = math.clamp(monster.X + monster.VX * lead, bounds.MinX, bounds.MaxX)
			local pz = math.clamp(monster.Z + monster.VZ * lead, bounds.MinZ, bounds.MaxZ)
			local target = Vector3.new(px, GROUND_Y, pz)
			local a = if far then 1 else alpha
			monster.Pos = monster.Pos:Lerp(target, a)
			local speed = math.sqrt(monster.VX * monster.VX + monster.VZ * monster.VZ)
			if speed > 0.5 then
				local wanted = math.atan2(-monster.VX, -monster.VZ)
				local diff = (wanted - monster.Yaw + math.pi) % (2 * math.pi) - math.pi
				monster.Yaw += diff * (if far then 1 else turnAlpha)
				monster.Phase += stepDt * speed * 0.9
			end
			local chasing = monster.Mode == 1
			setEyes(monster, chasing or night)
			local showAlert = chasing and not hidden
			if monster.Alert.Enabled ~= showAlert then
				monster.Alert.Enabled = showAlert
			end
			local swing = if speed > 0.5 then math.sin(monster.Phase) else 0
			local bob = math.abs(swing) * 0.35
			local root = CFrame.new(monster.Pos) * CFrame.Angles(0, monster.Yaw, 0)
			for i, part in ipairs(monster.Parts) do
				local def = PART_DEFS[i]
				local offset = def.Offset
				local cf
				if def.Name == "FootL" then
					cf = root * CFrame.new(offset.X, offset.Y, offset.Z + swing * 0.7)
				elseif def.Name == "FootR" then
					cf = root * CFrame.new(offset.X, offset.Y, offset.Z - swing * 0.7)
				else
					cf = root * CFrame.new(offset.X, offset.Y + bob, offset.Z)
				end
				count += 1
				moveParts[count] = part
				moveCFrames[count] = cf
			end
		end
	end
	if count > 0 then
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Neues Ei im Nest: kurz aufleuchten + Größen-Hüpfer (nur in der Nähe)
local function onNestEgg(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera or (camera.CFrame.Position - inst.Position).Magnitude > POP_RANGE then
		return
	end
	ctx.Effects.Play("NestPop", 0, { Position = inst.Position, Rarity = inst:GetAttribute("Rarity") })
	local size = inst.Size
	inst.Size = size * 0.3
	TweenService:Create(inst, TweenInfo.new(POP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = size })
		:Play()
end

-- Speed-Pad: Sichtfeld kurz weiter
local function onSpeedPad()
	local camera = workspace.CurrentCamera
	local untilTime = tonumber(player:GetAttribute("SpeedPadUntil")) or 0
	local left = untilTime - workspace:GetServerTimeNow()
	if not camera or left <= 0 then
		return
	end
	local fov = baseFov or camera.FieldOfView
	baseFov = fov
	fovToken += 1
	local token = fovToken
	TweenService:Create(camera, FOV_INFO, { FieldOfView = fov + FOV_BOOST }):Play()
	task.delay(left, function()
		if token == fovToken and workspace.CurrentCamera == camera then
			TweenService:Create(camera, FOV_INFO, { FieldOfView = fov }):Play()
			baseFov = nil
		end
	end)
end

-- Foto-Modus: "!" über den Kreaturen aus
function NestField.SetHidden(value: boolean)
	hidden = value
end

function NestField.Init(context: any, map: Instance)
	ctx = context
	local folder = Instance.new("Folder")
	folder.Name = "MeteorHeistCreatures"
	folder.Parent = workspace
	fxFolder = folder
	player:GetAttributeChangedSignal("SpeedPadUntil"):Connect(onSpeedPad)
	RunService.RenderStepped:Connect(step)

	task.spawn(function()
		local eggs = map:WaitForChild("NestMeteors", 60)
		if eggs then
			eggs.ChildAdded:Connect(onNestEgg)
		end
	end)
	task.spawn(function()
		local field = map:WaitForChild("NestField", 60)
		if not field then
			return
		end
		for key in pairs(bounds) do
			local value = tonumber(field:GetAttribute(key))
			if value then
				bounds[key] = value
			end
		end
		local folder = field:WaitForChild("Creatures", 60)
		if not folder then
			return
		end
		for _, child in ipairs(folder:GetChildren()) do
			buildMonster(child)
		end
		folder.ChildAdded:Connect(buildMonster)
	end)
end

return NestField
