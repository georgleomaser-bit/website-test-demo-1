-- =====================================================================
--  EI-RENNEN (alles lokal auf deinem Gerät, der Server merkt davon nichts)
--   • Wilde Kreaturen: der Server schickt pro Kreatur nur ein Text-Attribut "S"
--     ("Serverzeit|x|z|vx|vz|Modus", Ordner NestField/Creatures). Hier wird ein blockiges Monster
--     (15 Teile: Körper, Augen, Mund, Hörner, Arme, Beine, Füße) gebaut und weich bewegt
--     (Position vorhersagen x + v * Zeit, glätten). Animation je Modus:
--       0 herumlaufen: Lauf-Zyklus (Beine + Arme gegengleich), im Stand Atmen + Umschauen
--       1 jagen:       kurzes Ducken, dann Sprint mit Vorlage, Arme nach vorn, Mund auf, rote Augen,
--                      "!" ploppt auf, Staub an den Füßen
--       3 Treffer:     Jubel-Hüpfer mit Armen hoch + kleine Funken
--       1 -> 2/0 aufgeben: Kopfschütteln, Arme hängen, "?" über dem Kopf
--     Nachts leuchten alle Augen rot.
--   • Nester: neues Ei fällt ins Nest und federt (Squash & Stretch über eine lokale Kugel), Stroh fliegt;
--     große Nester mit Ei glitzern.
--   • Speed-Pads: Pfeile laufen über das Pad, Pad pulsiert. Mit Boost: Leuchtspur am Spieler (bei allen),
--     beim eigenen Boost Sichtfeld-Puls + Leucht-Rand am Bildschirm.
--   • Gold-Ei-Rennen: Fanfare (Banner + Konfetti) beim Start, Leuchtpfeil + Bodenring über dem Gold-Ei.
--  Leistung: alles dt-basiert, Teile mit EINEM workspace:BulkMoveTo pro Frame, weit weg seltener bzw.
--  gar nicht, feste Vorräte (Kugeln, Emitter) statt neuer Teile, keine neuen Tabellen pro Frame.
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local NestField = {}

local player = Players.LocalPlayer
local ctx: any = nil
local fxFolder: Folder? = nil
local hidden = false -- Foto-Modus: "!" und Bildschirm-Effekte aus

local WHITE = Color3.new(1, 1, 1)
local HIDDEN_CF = CFrame.new(0, -5000, 0)

-- ---------------------------------------------------------------------
-- KREATUREN
-- ---------------------------------------------------------------------
local GROUND_Y = 0.2 -- Oberkante des Feld-Bodens (MapBuilder FIELD_TOP)
local MAX_LEAD = 0.5 -- höchstens so weit (Sekunden) vorhersagen
local SMOOTH = 10 -- wie schnell die Anzeige der Vorhersage folgt (1/s)
local TURN = 8
local FAR_DISTANCE = 200 -- weiter weg: nur jedes FAR_SKIP. Frame bewegen, ohne Feinheiten
local FAR_SKIP = 4
local HIDE_DISTANCE = 520 -- noch weiter weg: gar nicht bewegen
local DUST_RANGE = 110 -- Staub an den Füßen nur so nah an der Kamera
local HIP_Y = 1.3 -- Hüfthöhe über dem Boden (Drehpunkt für Oberkörper und Beine)
local LEG_LENGTH = 1.3
local ARM_LENGTH = 2.2
local HIT_TIME = 0.8 -- Treffer-Jubel (so lange pausiert die Kreatur auch auf dem Server)
local GIVEUP_TIME = 1.1 -- Kopfschütteln nach dem Aufgeben
local CROUCH_TIME = 0.22 -- Ducken vor dem Sprint
local ALERT_SIZE = UDim2.fromOffset(44, 54)
local ALERT_POP = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local BODY_COLORS = {
	Color3.fromRGB(120, 70, 200),
	Color3.fromRGB(70, 160, 70),
	Color3.fromRGB(220, 90, 60),
}
local DARK = Color3.fromRGB(40, 35, 45)
local EYE_RED = Color3.fromRGB(255, 40, 40)
local MOUTH_CLOSED = Vector3.new(1.4, 0.3, 0.2)
local MOUTH_OPEN = Vector3.new(1.7, 0.85, 0.2)

-- Teile relativ zum Fußpunkt (Blick nach -Z). Group: "Upper" (hängt am Oberkörper), "ArmL/ArmR"
-- (Offset = Schulter), "LegL/LegR" (Offset = Hüfte), "FootL/FootR" (Offset = Hüfte). Color nil = Körperfarbe,
-- Shade = Körperfarbe etwas dunkler.
type PartDef = {
	Name: string,
	Size: Vector3,
	Offset: Vector3,
	Group: string,
	Color: Color3?,
	Shade: boolean?,
}
local PART_DEFS: { PartDef } = {
	{ Name = "Body", Size = Vector3.new(4.2, 3.4, 3.8), Offset = Vector3.new(0, 3, 0), Group = "Upper" },
	{
		Name = "Belly",
		Size = Vector3.new(2.6, 1.8, 0.2),
		Offset = Vector3.new(0, 2.55, -1.95),
		Group = "Upper",
		Color = Color3.fromRGB(240, 230, 200),
	},
	{
		Name = "EyeL",
		Size = Vector3.new(1, 1, 0.2),
		Offset = Vector3.new(-0.9, 3.85, -1.95),
		Group = "Upper",
		Color = WHITE,
	},
	{
		Name = "EyeR",
		Size = Vector3.new(1, 1, 0.2),
		Offset = Vector3.new(0.9, 3.85, -1.95),
		Group = "Upper",
		Color = WHITE,
	},
	{
		Name = "PupilL",
		Size = Vector3.new(0.5, 0.5, 0.2),
		Offset = Vector3.new(-0.9, 3.8, -2.1),
		Group = "Upper",
		Color = DARK,
	},
	{
		Name = "PupilR",
		Size = Vector3.new(0.5, 0.5, 0.2),
		Offset = Vector3.new(0.9, 3.8, -2.1),
		Group = "Upper",
		Color = DARK,
	},
	{ Name = "Mouth", Size = MOUTH_CLOSED, Offset = Vector3.new(0, 3.05, -1.96), Group = "Upper", Color = DARK },
	{
		Name = "HornL",
		Size = Vector3.new(0.6, 1.2, 0.6),
		Offset = Vector3.new(-1.4, 5.3, 0),
		Group = "Upper",
		Color = DARK,
	},
	{
		Name = "HornR",
		Size = Vector3.new(0.6, 1.2, 0.6),
		Offset = Vector3.new(1.4, 5.3, 0),
		Group = "Upper",
		Color = DARK,
	},
	{
		Name = "ArmL",
		Size = Vector3.new(0.9, ARM_LENGTH, 0.9),
		Offset = Vector3.new(-2.55, 3.8, 0),
		Group = "ArmL",
		Shade = true,
	},
	{
		Name = "ArmR",
		Size = Vector3.new(0.9, ARM_LENGTH, 0.9),
		Offset = Vector3.new(2.55, 3.8, 0),
		Group = "ArmR",
		Shade = true,
	},
	{
		Name = "LegL",
		Size = Vector3.new(1.1, LEG_LENGTH, 1.1),
		Offset = Vector3.new(-1.1, HIP_Y, 0),
		Group = "LegL",
		Shade = true,
	},
	{
		Name = "LegR",
		Size = Vector3.new(1.1, LEG_LENGTH, 1.1),
		Offset = Vector3.new(1.1, HIP_Y, 0),
		Group = "LegR",
		Shade = true,
	},
	{
		Name = "FootL",
		Size = Vector3.new(1.3, 0.5, 1.7),
		Offset = Vector3.new(-1.1, HIP_Y, 0),
		Group = "FootL",
		Color = DARK,
	},
	{
		Name = "FootR",
		Size = Vector3.new(1.3, 0.5, 1.7),
		Offset = Vector3.new(1.1, HIP_Y, 0),
		Group = "FootR",
		Color = DARK,
	},
}
-- Lage relativ zur Hüfte (einmal ausgerechnet)
local REL: { Vector3 } = {}
for i, def in ipairs(PART_DEFS) do
	REL[i] = Vector3.new(def.Offset.X, def.Offset.Y - HIP_Y, def.Offset.Z)
end
local ARM_DOWN = CFrame.new(0, -ARM_LENGTH / 2 + 0.2, 0)
local LEG_DOWN = CFrame.new(0, -LEG_LENGTH / 2, 0)
local FOOT_DOWN = CFrame.new(0, -LEG_LENGTH + 0.25, -0.25)

type Monster = {
	Source: Instance,
	Parts: { BasePart },
	Pupils: { BasePart },
	Mouth: BasePart,
	Dust: ParticleEmitter,
	Alert: BillboardGui,
	AlertLabel: TextLabel,
	AlertText: string,
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
	Speed: number, -- geglättetes Tempo (für weiche Übergänge Stehen <-> Laufen <-> Sprint)
	Seed: number,
	Red: boolean?,
	MouthOpen: boolean,
	DustOn: boolean,
	ShownMode: number, -- zuletzt angezeigter Modus (für Übergänge)
	ChaseAt: number,
	HitAt: number,
	GiveUpAt: number,
}

local monsters: { [Instance]: Monster } = {}
local bounds = { MinX = -29, MaxX = 29, MinZ = -205, MaxZ = 240 }
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}
local frame = 0
local animClock = 0

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

local function makeDust(parent: BasePart): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Dust"
	emitter.Color = ColorSequence.new(Color3.fromRGB(205, 190, 150), Color3.fromRGB(160, 150, 130))
	emitter.LightInfluence = 0.8
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1.6),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.35, 0.6)
	emitter.Speed = NumberRange.new(2, 5)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Acceleration = Vector3.new(0, 2, 0)
	emitter.Drag = 3
	emitter.Rate = 0
	emitter.Parent = parent
	return emitter
end

local function buildMonster(source: Instance)
	local folder = fxFolder
	if not folder or monsters[source] then
		return
	end
	local look = math.clamp(math.floor(tonumber(source:GetAttribute("Look")) or 1), 1, #BODY_COLORS)
	local bodyColor = BODY_COLORS[look]
	local shade = bodyColor:Lerp(Color3.new(0, 0, 0), 0.22)
	local model = Instance.new("Model")
	model.Name = "Creature"
	local parts: { BasePart } = {}
	local pupils: { BasePart } = {}
	local mouth: BasePart? = nil
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
		p.Color = def.Color or (if def.Shade then shade else bodyColor)
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CFrame = HIDDEN_CF
		p.Parent = model
		table.insert(parts, p)
		if def.Name == "PupilL" or def.Name == "PupilR" then
			table.insert(pupils, p)
		elseif def.Name == "Mouth" then
			mouth = p
		end
	end
	-- "!" / "?" / "💢" über dem Kopf
	local alert = Instance.new("BillboardGui")
	alert.Name = "Alert"
	alert.Size = ALERT_SIZE
	alert.StudsOffset = Vector3.new(0, 4.4, 0)
	alert.MaxDistance = 130
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
	local foot = parts[#parts - 1]
	local dust = makeDust(foot)
	model.Parent = folder

	local monster: Monster = {
		Source = source,
		Parts = parts,
		Pupils = pupils,
		Mouth = mouth :: BasePart,
		Dust = dust,
		Alert = alert,
		AlertLabel = label,
		AlertText = "",
		T = workspace:GetServerTimeNow(),
		X = 0,
		Z = 0,
		VX = 0,
		VZ = 0,
		Mode = 0,
		Pos = Vector3.zero,
		Yaw = 0,
		Phase = 0,
		Speed = 0,
		Seed = math.random() * 10,
		Red = nil,
		MouthOpen = false,
		DustOn = false,
		ShownMode = 0,
		ChaseAt = -math.huge,
		HitAt = -math.huge,
		GiveUpAt = -math.huge,
	}
	parseState(monster)
	monster.Pos = Vector3.new(monster.X, GROUND_Y, monster.Z)
	monster.ShownMode = monster.Mode
	monsters[source] = monster
	source:GetAttributeChangedSignal("S"):Connect(function()
		parseState(monster)
	end)
	local function remove()
		if monsters[source] == monster then
			monsters[source] = nil
		end
		model:Destroy()
	end
	source.Destroying:Connect(remove)
	source.AncestryChanged:Connect(function()
		if not source:IsDescendantOf(workspace) then
			remove()
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

local function setMouth(monster: Monster, open: boolean)
	if monster.MouthOpen ~= open then
		monster.MouthOpen = open
		monster.Mouth.Size = if open then MOUTH_OPEN else MOUTH_CLOSED
	end
end

local function setDust(monster: Monster, on: boolean)
	if monster.DustOn ~= on then
		monster.DustOn = on
		monster.Dust.Rate = if on then 22 else 0
	end
end

-- Symbol über dem Kopf ("" = aus); neues Symbol ploppt auf
local function setAlert(monster: Monster, text: string, color: Color3)
	local show = text ~= "" and not hidden
	if monster.Alert.Enabled ~= show then
		monster.Alert.Enabled = show
	end
	if text == monster.AlertText then
		return
	end
	monster.AlertText = text
	if text ~= "" then
		monster.AlertLabel.Text = text
		monster.AlertLabel.TextColor3 = color
		monster.Alert.Size = UDim2.fromOffset(8, 10)
		TweenService:Create(monster.Alert, ALERT_POP, { Size = ALERT_SIZE }):Play()
	end
end

-- Moduswechsel merken (Ducken vor dem Sprint, Treffer-Jubel, Aufgeben)
local function noteMode(monster: Monster, now: number, near: boolean)
	local mode = monster.Mode
	local old = monster.ShownMode
	if mode == old then
		return
	end
	monster.ShownMode = mode
	if mode == 1 then
		monster.ChaseAt = now
	elseif mode == 3 then
		monster.HitAt = now
		if near and ctx and ctx.Effects and ctx.Effects.Burst then
			ctx.Effects.Burst(monster.Pos + Vector3.new(0, 5.5, 0), Color3.fromRGB(255, 220, 60), 10, false)
		end
	elseif old == 1 then
		monster.GiveUpAt = now -- hat aufgegeben (Ziel zu weit weg)
	end
end

-- Pose für dieses Frame: schreibt alle Teile in moveParts/moveCFrames ab Index count+1
local function poseMonster(monster: Monster, count: number, detail: boolean): number
	local now = animClock
	local speed = monster.Speed
	local mode = monster.Mode
	local chasing = mode == 1
	local amp = math.clamp(speed / 10, 0, 1)
	local sinP = math.sin(monster.Phase)
	local legSwing = sinP * 0.75 * amp
	local armSwing = -sinP * (if chasing then 1.1 else 0.8) * amp
	local bob = math.abs(sinP) * 0.32 * amp
	local lean = (if chasing then -0.3 else -0.07) * amp
	local roll = math.cos(monster.Phase) * 0.06 * amp
	local shake = 0
	local hop = 0
	local armBase = if chasing then 1.05 else 0
	local armOut = 0.12
	local lookX = 0
	if detail then
		-- im Stand: Atmen + Umschauen
		local still = 1 - amp
		bob += math.sin(now * 2.3 + monster.Seed) * 0.07 * still
		armSwing += math.sin(now * 1.6 + monster.Seed) * 0.12 * still
		lookX = math.sin(now * 0.8 + monster.Seed * 2) * 0.13 * still
		-- Ducken vor dem Sprint
		local sinceChase = now - monster.ChaseAt
		if chasing and sinceChase < CROUCH_TIME then
			local k = math.sin(sinceChase / CROUCH_TIME * math.pi)
			bob -= 0.45 * k
			lean += 0.25 * k
		end
		-- Treffer: Jubel-Hüpfer, Arme hoch
		local sinceHit = now - monster.HitAt
		if sinceHit < HIT_TIME then
			local u = sinceHit / HIT_TIME
			hop = math.sin(u * math.pi) * 1.3
			armBase = 2.75 + math.sin(now * 22) * 0.18
			armSwing = 0
			armOut = 0.35
			lean = 0.18 * math.sin(u * math.pi)
			legSwing = 0.25 * math.sin(u * math.pi)
		end
		-- Aufgeben: Kopfschütteln, Arme hängen
		local sinceGiveUp = now - monster.GiveUpAt
		if sinceGiveUp < GIVEUP_TIME then
			local u = sinceGiveUp / GIVEUP_TIME
			shake = math.sin(u * math.pi * 6) * 0.42 * (1 - u)
			armBase = -0.15
			armOut = 0.05
		end
	end

	local root = CFrame.new(monster.Pos) * CFrame.Angles(0, monster.Yaw, 0)
	local upper = root * CFrame.new(0, HIP_Y + bob + hop, 0) * CFrame.Angles(lean, shake, roll)
	local hipY = HIP_Y + hop
	for i, part in ipairs(monster.Parts) do
		local def = PART_DEFS[i]
		local rel = REL[i]
		local group = def.Group
		local cf
		if group == "Upper" then
			if def.Name == "PupilL" or def.Name == "PupilR" then
				cf = upper * CFrame.new(rel.X + lookX, rel.Y, rel.Z)
			else
				cf = upper * CFrame.new(rel.X, rel.Y, rel.Z)
			end
		elseif group == "ArmL" or group == "ArmR" then
			local side = if group == "ArmL" then -1 else 1
			local swing = if group == "ArmL" then armSwing else -armSwing
			cf = upper * CFrame.new(rel.X, rel.Y, rel.Z) * CFrame.Angles(armBase + swing, 0, side * armOut) * ARM_DOWN
		else
			local left = group == "LegL" or group == "FootL"
			local swing = if left then legSwing else -legSwing
			local hip = root * CFrame.new(def.Offset.X, hipY, 0) * CFrame.Angles(swing, 0, 0)
			if group == "LegL" or group == "LegR" then
				cf = hip * LEG_DOWN
			else
				cf = hip * FOOT_DOWN
			end
		end
		count += 1
		moveParts[count] = part
		moveCFrames[count] = cf
	end
	return count
end

local function stepMonsters(dt: number, camPos: Vector3, count: number): number
	local now = workspace:GetServerTimeNow()
	local night = ReplicatedStorage:GetAttribute("IsNight") == true
	local alpha = 1 - math.exp(-SMOOTH * dt)
	local turnAlpha = 1 - math.exp(-TURN * dt)
	local index = 0
	for _, monster in pairs(monsters) do
		index += 1
		local distance = (monster.Pos - camPos).Magnitude
		local far = distance > FAR_DISTANCE
		local due = not far or (frame + index) % FAR_SKIP == 0
		if distance > HIDE_DISTANCE then
			-- sehr weit weg: nur die Position mitführen (kommt man näher, stimmt sie sofort)
			due = false
			monster.Pos = Vector3.new(monster.X, GROUND_Y, monster.Z)
		end
		if due then
			local stepDt = if far then dt * FAR_SKIP else dt
			local lead = math.clamp(now - monster.T, 0, MAX_LEAD)
			local px = math.clamp(monster.X + monster.VX * lead, bounds.MinX, bounds.MaxX)
			local pz = math.clamp(monster.Z + monster.VZ * lead, bounds.MinZ, bounds.MaxZ)
			monster.Pos = monster.Pos:Lerp(Vector3.new(px, GROUND_Y, pz), if far then 1 else alpha)
			local rawSpeed = math.sqrt(monster.VX * monster.VX + monster.VZ * monster.VZ)
			if rawSpeed > 0.5 then
				local wanted = math.atan2(-monster.VX, -monster.VZ)
				local diff = (wanted - monster.Yaw + math.pi) % (2 * math.pi) - math.pi
				monster.Yaw += diff * (if far then 1 else turnAlpha)
			end
			-- Tempo weich nachführen (kein Ruck zwischen Stehen, Gehen und Sprint)
			monster.Speed += (rawSpeed - monster.Speed) * math.min(1, stepDt * 8)
			monster.Phase += stepDt * (2 + monster.Speed * 0.55)
			noteMode(monster, animClock, not far)
			local chasing = monster.Mode == 1
			setEyes(monster, chasing or night)
			setMouth(monster, chasing)
			setDust(monster, chasing and distance < DUST_RANGE and monster.Speed > 4)
			if animClock - monster.HitAt < HIT_TIME then
				setAlert(monster, "💢", Color3.fromRGB(255, 120, 60))
			elseif animClock - monster.GiveUpAt < GIVEUP_TIME then
				setAlert(monster, "?", Color3.fromRGB(255, 230, 120))
			elseif chasing then
				setAlert(monster, "!", EYE_RED)
			else
				setAlert(monster, "", WHITE)
			end
			count = poseMonster(monster, count, not far)
		end
	end
	return count
end

-- ---------------------------------------------------------------------
-- NESTER: Ei-Pop mit Squash & Stretch, Stroh, Glitzer großer Nester
-- ---------------------------------------------------------------------
local POP_RANGE = 150 -- Eier-Pop nur in der Nähe
local POP_TIME = 0.6
local POP_DROP = 3.5 -- so hoch über dem Nest fängt das Ei an zu fallen
local POP_POOL = 10 -- so viele Eier können gleichzeitig ploppen
local GLITTER_RANGE = 170
local GLITTER_INTERVAL = 0.5
local STRAW_COLORS = ColorSequence.new(Color3.fromRGB(240, 205, 110), Color3.fromRGB(190, 140, 70))

type Pop = {
	Proxy: BasePart,
	Mesh: SpecialMesh,
	Egg: BasePart?,
	Rest: CFrame,
	Height: number,
	Start: number,
	Landed: boolean,
}
local pops: { Pop } = {}
local strawPart: BasePart? = nil
local strawEmitter: ParticleEmitter? = nil

type Glitter = { Nest: BasePart, Pillar: Beam, Emitter: ParticleEmitter, On: boolean }
local glitters: { Glitter } = {}
local glitterClock = 0

local function buildPops()
	local folder = fxFolder :: Folder
	for _ = 1, POP_POOL do
		local proxy = Instance.new("Part")
		proxy.Name = "EggPop"
		proxy.Anchored = true
		proxy.CanCollide = false
		proxy.CanQuery = false
		proxy.CanTouch = false
		proxy.CastShadow = false
		proxy.Transparency = 1
		proxy.CFrame = HIDDEN_CF
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = proxy
		proxy.Parent = folder
		table.insert(pops, {
			Proxy = proxy,
			Mesh = mesh,
			Egg = nil,
			Rest = HIDDEN_CF,
			Height = 1,
			Start = 0,
			Landed = false,
		})
	end
	-- EIN Stroh-Emitter für alle Nester: hinschieben, Emit, Teilchen bleiben in der Welt
	local holder = Instance.new("Part")
	holder.Name = "Straw"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(3, 0.2, 3)
	holder.CFrame = HIDDEN_CF
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = STRAW_COLORS
	emitter.LightInfluence = 0.7
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.32),
		NumberSequenceKeypoint.new(1, 0.15),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.75, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(7, 13)
	emitter.SpreadAngle = Vector2.new(55, 55)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Acceleration = Vector3.new(0, -45, 0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-300, 300)
	emitter.Rate = 0
	emitter.Parent = holder
	holder.Parent = folder
	strawPart = holder
	strawEmitter = emitter
end

local function endPop(pop: Pop)
	local egg = pop.Egg
	if egg then
		egg.LocalTransparencyModifier = 0
	end
	pop.Egg = nil
	pop.Proxy.Transparency = 1
	pop.Proxy.CFrame = HIDDEN_CF
end

local function strawBurst(position: Vector3, amount: number)
	local holder, emitter = strawPart, strawEmitter
	if holder and emitter then
		holder.CFrame = CFrame.new(position)
		emitter:Emit(amount)
	end
end

-- Neues Ei im Nest: fällt rein, staucht sich beim Aufprall, federt nach (lokale Kugel statt Ei)
local function onNestEgg(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera or (camera.CFrame.Position - inst.Position).Magnitude > POP_RANGE then
		return
	end
	local free: Pop? = nil
	for _, pop in ipairs(pops) do
		if not pop.Egg then
			free = pop
			break
		end
	end
	if not free then
		ctx.Effects.Play("NestPop", 0, { Position = inst.Position, Rarity = inst:GetAttribute("Rarity") })
		return
	end
	free.Egg = inst
	free.Rest = inst.CFrame
	free.Height = inst.Size.Y
	free.Start = animClock
	free.Landed = false
	local proxy = free.Proxy
	proxy.Size = inst.Size
	proxy.Color = inst.Color
	proxy.Material = inst.Material
	proxy.Reflectance = inst.Reflectance
	proxy.Transparency = inst.Transparency
	inst.LocalTransparencyModifier = 1
end

local function stepPops(count: number): number
	for _, pop in ipairs(pops) do
		local egg = pop.Egg
		if egg then
			local u = (animClock - pop.Start) / POP_TIME
			if u >= 1 or not egg.Parent then
				endPop(pop)
			else
				local y, sx, sy = 0, 1, 1
				if u < 0.3 then
					-- Fall: wird beim Fallen größer und gestreckt
					local k = u / 0.3
					y = POP_DROP * (1 - k * k)
					local grow = 0.45 + 0.55 * k
					sx, sy = grow * 0.82, grow * 1.22
				elseif u < 0.5 then
					-- Aufprall: platt drücken (Unterkante bleibt im Nest)
					if not pop.Landed then
						pop.Landed = true
						local bottom = pop.Rest.Position - Vector3.new(0, pop.Height / 2, 0)
						strawBurst(bottom, 10)
						ctx.Effects.Play(
							"NestPop",
							0,
							{ Position = pop.Rest.Position, Rarity = egg:GetAttribute("Rarity") }
						)
					end
					local s = math.sin((u - 0.3) / 0.2 * math.pi)
					sx, sy = 1 + 0.32 * s, 1 - 0.36 * s
					y = -pop.Height * 0.18 * s
				else
					-- nachfedern
					local k = (u - 0.5) / 0.5
					local w = math.sin(k * math.pi * 2.5) * (1 - k) * 0.16
					sx, sy = 1 - w * 0.6, 1 + w
					y = pop.Height * 0.5 * (sy - 1)
				end
				pop.Mesh.Scale = Vector3.new(sx, sy, sx)
				count += 1
				moveParts[count] = pop.Proxy
				moveCFrames[count] = pop.Rest + Vector3.new(0, y, 0)
			end
		end
	end
	return count
end

local function addGlitter(nest: Instance)
	if not nest:IsA("BasePart") or nest:GetAttribute("NestSize") ~= "Big" then
		return
	end
	local pillar = nest:FindFirstChild("NestPillar")
	local point = nest:GetAttribute("EggPoint")
	if not pillar or not pillar:IsA("Beam") or typeof(point) ~= "Vector3" then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "Glitter"
	attachment.Parent = nest
	attachment.WorldPosition = point + Vector3.new(0, 2, 0)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.3, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new(0.1, 1)
	emitter.Lifetime = NumberRange.new(0.9, 1.6)
	emitter.Speed = NumberRange.new(1.5, 4)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 1.5, 0)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Rate = 0
	emitter.Parent = attachment
	table.insert(glitters, { Nest = nest, Pillar = pillar, Emitter = emitter, On = false })
end

local function stepGlitter(camPos: Vector3)
	for _, glitter in ipairs(glitters) do
		local on = glitter.Pillar.Enabled and not hidden and (glitter.Nest.Position - camPos).Magnitude < GLITTER_RANGE
		if on ~= glitter.On then
			glitter.On = on
			if on then
				local keypoints = glitter.Pillar.Color.Keypoints
				local color = keypoints[1] and keypoints[1].Value or WHITE
				glitter.Emitter.Color = ColorSequence.new(color, WHITE)
			end
			glitter.Emitter.Rate = if on then 9 else 0
		end
	end
end

-- ---------------------------------------------------------------------
-- SPEED-PADS: laufende Pfeile, Puls, Leuchtspur, Sichtfeld-Puls
-- ---------------------------------------------------------------------
local PAD_RANGE = 140
local PAD_INTERVAL = 1 / 30
local ARROWS = 3
local ARROW_SPEED = 0.9 -- Pad-Längen pro Sekunde
local TRAIL_RANGE = 260
local TRAIL_INTERVAL = 0.2
local FOV_PUNCH = 16
local FOV_HOLD = 9
local FOV_IN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FOV_SETTLE = TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local FOV_OUT = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local EDGE_INFO = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PAD_COLOR = Color3.fromRGB(0, 170, 255)
local TRAIL_COLOR = Color3.fromRGB(80, 220, 255)

type Pad = {
	Part: BasePart,
	Gui: SurfaceGui,
	Arrows: { TextLabel },
	Bolt: TextLabel,
	BaseColor: Color3,
	Active: boolean,
}
local pads: { Pad } = {}
local padClock = 0
local trailClock = 0
local trails: { [Model]: Trail } = {}
local baseFov: number? = nil
local fovToken = 0
local edgeStroke: UIStroke? = nil

local function addPad(part: Instance)
	if not part:IsA("BasePart") or part:GetAttribute("SpeedPad") ~= true then
		return
	end
	local serverIcon = part:FindFirstChild("Icon")
	if serverIcon and serverIcon:IsA("SurfaceGui") then
		serverIcon.Enabled = false -- unser lokales Schild zeigt Blitz + Pfeile
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "PadFX"
	gui.Face = Enum.NormalId.Top
	gui.CanvasSize = Vector2.new(100, 100)
	gui.LightInfluence = 0
	gui.ClipsDescendants = true
	gui.Enabled = false
	local arrows = {}
	for i = 1, ARROWS do
		local arrow = Instance.new("TextLabel")
		arrow.BackgroundTransparency = 1
		arrow.AnchorPoint = Vector2.new(0.5, 0.5)
		arrow.Size = UDim2.fromScale(0.8, 0.34)
		arrow.Position = UDim2.fromScale(0.5, i / ARROWS)
		arrow.Font = Enum.Font.FredokaOne
		arrow.TextScaled = true
		arrow.Text = "▲"
		arrow.TextColor3 = WHITE
		arrow.TextTransparency = 0.3
		arrow.Parent = gui
		table.insert(arrows, arrow)
	end
	local bolt = Instance.new("TextLabel")
	bolt.BackgroundTransparency = 1
	bolt.AnchorPoint = Vector2.new(0.5, 0.5)
	bolt.Position = UDim2.fromScale(0.5, 0.5)
	bolt.Size = UDim2.fromScale(0.55, 0.55)
	bolt.Font = Enum.Font.FredokaOne
	bolt.TextScaled = true
	bolt.Text = "⚡"
	bolt.TextColor3 = Color3.fromRGB(255, 240, 120)
	bolt.ZIndex = 2
	bolt.Parent = gui
	gui.Adornee = part
	gui.Parent = part
	table.insert(pads, { Part = part, Gui = gui, Arrows = arrows, Bolt = bolt, BaseColor = part.Color, Active = false })
end

local function stepPads(camPos: Vector3)
	local t = animClock
	for _, pad in ipairs(pads) do
		local near = not hidden and (pad.Part.Position - camPos).Magnitude < PAD_RANGE
		if near ~= pad.Active then
			pad.Active = near
			pad.Gui.Enabled = near
			if not near then
				pad.Part.Color = pad.BaseColor
			end
		end
		if near then
			for i, arrow in ipairs(pad.Arrows) do
				-- Pfeile laufen nach "oben" über das Pad, blenden an den Enden aus
				local s = (i / ARROWS + t * ARROW_SPEED) % 1
				arrow.Position = UDim2.fromScale(0.5, 1.15 - s * 1.3)
				arrow.TextTransparency = 0.15 + 0.85 * math.abs(s - 0.5) * 2
			end
			local pulse = (math.sin(t * 5 + pad.Part.Position.Z * 0.1) + 1) / 2
			pad.Part.Color = pad.BaseColor:Lerp(WHITE, 0.08 + 0.3 * pulse)
			pad.Bolt.Rotation = math.sin(t * 7) * 8
		end
	end
end

local function makeTrail(character: Model): Trail?
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local top = Instance.new("Attachment")
	top.Name = "BoostTrailTop"
	top.Position = Vector3.new(0, 1.1, 0.4)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = "BoostTrailBottom"
	bottom.Position = Vector3.new(0, -2.2, 0.4)
	bottom.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "BoostTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = ColorSequence.new(TRAIL_COLOR, WHITE)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = 0.35
	trail.MinLength = 0.2
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.FaceCamera = true
	trail.Enabled = false
	trail.Parent = root
	character.Destroying:Connect(function()
		trails[character] = nil
	end)
	return trail
end

-- Alle 0,2 s: Leuchtspur an allen Spielern mit Boost (in Kameranähe)
local function stepTrails(camPos: Vector3)
	local now = workspace:GetServerTimeNow()
	for character, trail in pairs(trails) do
		if not character.Parent or not trail.Parent then
			trails[character] = nil
		end
	end
	for _, other in ipairs(Players:GetPlayers()) do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character and root and root:IsA("BasePart") then
			local boosted = (tonumber(other:GetAttribute("SpeedPadUntil")) or 0) > now
				and (root.Position - camPos).Magnitude < TRAIL_RANGE
			local trail = trails[character]
			if boosted and not trail then
				trail = makeTrail(character)
				if trail then
					trails[character] = trail
				end
			end
			if trail and trail.Enabled ~= boosted then
				trail.Enabled = boosted
			end
		end
	end
end

local function buildEdge()
	local frameGui = Instance.new("Frame")
	frameGui.Name = "BoostEdge"
	frameGui.BackgroundTransparency = 1
	frameGui.Size = UDim2.fromScale(1, 1)
	frameGui.ZIndex = 0
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 22
	stroke.Color = TRAIL_COLOR
	stroke.Transparency = 1
	stroke.Parent = frameGui
	frameGui.Parent = ctx.Gui
	edgeStroke = stroke
end

-- Eigener Boost: Sichtfeld springt kurz weit auf und pendelt sich ein, Bildschirmrand leuchtet
local function onSpeedPad()
	local camera = workspace.CurrentCamera
	local untilTime = tonumber(player:GetAttribute("SpeedPadUntil")) or 0
	local left = untilTime - workspace:GetServerTimeNow()
	if not camera or left <= 0 then
		return
	end
	local fov = baseFov or camera.FieldOfView
	local fresh = baseFov == nil
	baseFov = fov
	fovToken += 1
	local token = fovToken
	if fresh then
		local punch = TweenService:Create(camera, FOV_IN, { FieldOfView = fov + FOV_PUNCH })
		punch.Completed:Connect(function()
			if token == fovToken then
				TweenService:Create(camera, FOV_SETTLE, { FieldOfView = fov + FOV_HOLD }):Play()
			end
		end)
		punch:Play()
		local stroke = edgeStroke
		if stroke and not hidden then
			stroke.Transparency = 0.25
			TweenService:Create(stroke, EDGE_INFO, { Transparency = 1 }):Play()
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and ctx.Effects.Ring then
			ctx.Effects.Ring(root.Position - Vector3.new(0, 2.8, 0), PAD_COLOR, 12, 0.45)
		end
	end
	task.delay(left, function()
		if token == fovToken and workspace.CurrentCamera == camera then
			TweenService:Create(camera, FOV_OUT, { FieldOfView = fov }):Play()
			baseFov = nil
		end
	end)
end

-- ---------------------------------------------------------------------
-- GOLD-EI-RENNEN: Fanfare + Leuchtpfeil über dem Gold-Ei
-- ---------------------------------------------------------------------
local ARROW_HEIGHT = 13
local FANFARE_TIME = 2.6
local FANFARE_IN = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FANFARE_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local SHINE_INFO = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local GOLD = Color3.fromRGB(255, 205, 50)

local raceAnchor: BasePart? = nil
local raceArrow: BillboardGui? = nil
local raceArrowLabel: TextLabel? = nil
local raceRing: BasePart? = nil
local raceShown = false
local fanfare: Frame? = nil
local fanfareScale: UIScale? = nil
local fanfareShine: UIGradient? = nil
local fanfareToken = 0

local function buildRace()
	local folder = fxFolder :: Folder
	local anchor = Instance.new("Part")
	anchor.Name = "RaceArrowAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = HIDDEN_CF
	anchor.Parent = folder
	local gui = Instance.new("BillboardGui")
	gui.Name = "RaceArrow"
	gui.Size = UDim2.fromOffset(90, 110)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 900
	gui.Enabled = false
	gui.Adornee = anchor
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "▼"
	label.TextColor3 = GOLD
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = Color3.fromRGB(120, 60, 0)
	stroke.Parent = label
	label.Parent = gui
	local ringPart = Instance.new("Part")
	ringPart.Name = "RaceRing"
	ringPart.Shape = Enum.PartType.Cylinder
	ringPart.Anchored = true
	ringPart.CanCollide = false
	ringPart.CanQuery = false
	ringPart.CanTouch = false
	ringPart.CastShadow = false
	ringPart.Material = Enum.Material.Neon
	ringPart.Color = GOLD
	ringPart.Transparency = 1
	ringPart.Size = Vector3.new(0.2, 10, 10)
	ringPart.CFrame = HIDDEN_CF
	ringPart.Parent = folder
	raceAnchor, raceArrow, raceArrowLabel, raceRing = anchor, gui, label, ringPart

	-- Fanfare-Banner (einmal gebaut, wiederverwendet)
	local banner = Instance.new("Frame")
	banner.Name = "RaceFanfare"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.3)
	banner.Size = UDim2.fromOffset(560, 120)
	banner.BackgroundTransparency = 1
	banner.Visible = false
	banner.ZIndex = 30
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = banner
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.66)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Text = "🏁 EI-RENNEN! 🏁"
	title.TextColor3 = WHITE
	title.ZIndex = 31
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Thickness = 5
	titleStroke.Color = Color3.fromRGB(110, 55, 0)
	titleStroke.Parent = title
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, GOLD),
		ColorSequenceKeypoint.new(0.45, GOLD),
		ColorSequenceKeypoint.new(0.5, WHITE),
		ColorSequenceKeypoint.new(0.55, GOLD),
		ColorSequenceKeypoint.new(1, GOLD),
	})
	gradient.Offset = Vector2.new(-1, 0)
	gradient.Parent = title
	title.Parent = banner
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromScale(0, 0.66)
	sub.Size = UDim2.fromScale(1, 0.34)
	sub.Font = Enum.Font.FredokaOne
	sub.TextScaled = true
	sub.Text = "Hol das Gold-Ei und bring es heim!"
	sub.TextColor3 = WHITE
	sub.ZIndex = 31
	local subStroke = Instance.new("UIStroke")
	subStroke.Thickness = 3
	subStroke.Parent = sub
	sub.Parent = banner
	banner.Parent = ctx.Gui
	fanfare, fanfareScale, fanfareShine = banner, scale, gradient
end

local function playFanfare()
	local banner, scale, shine = fanfare, fanfareScale, fanfareShine
	if not banner or not scale or not shine or hidden then
		return
	end
	fanfareToken += 1
	local token = fanfareToken
	banner.Visible = true
	banner.Rotation = -6
	scale.Scale = 0
	TweenService:Create(scale, FANFARE_IN, { Scale = 1 }):Play()
	TweenService:Create(banner, FANFARE_IN, { Rotation = 0 }):Play()
	shine.Offset = Vector2.new(-1, 0)
	local sweep = TweenService:Create(shine, SHINE_INFO, { Offset = Vector2.new(1, 0) })
	sweep:Play()
	ctx.Effects.Play("Confetti", 1.2)
	task.delay(FANFARE_TIME, function()
		if token ~= fanfareToken then
			return
		end
		local out = TweenService:Create(scale, FANFARE_OUT, { Scale = 0 })
		out.Completed:Connect(function()
			if token == fanfareToken then
				banner.Visible = false
			end
		end)
		out:Play()
	end)
end

local function stepRace(count: number): number
	local anchor, gui, label, ringPart = raceAnchor, raceArrow, raceArrowLabel, raceRing
	if not anchor or not gui or not label or not ringPart then
		return count
	end
	local untilTime = tonumber(ReplicatedStorage:GetAttribute("RaceUntil")) or 0
	local target = ReplicatedStorage:GetAttribute("RaceTarget")
	local show = untilTime > workspace:GetServerTimeNow() and typeof(target) == "Vector3" and not hidden
	if show ~= raceShown then
		raceShown = show
		gui.Enabled = show
		ringPart.Transparency = if show then 0.35 else 1
		if not show then
			anchor.CFrame = HIDDEN_CF
			ringPart.CFrame = HIDDEN_CF
		end
	end
	if show and typeof(target) == "Vector3" then
		local t = animClock
		local bobY = math.abs(math.sin(t * 3)) * 2.2
		count += 1
		moveParts[count] = anchor
		moveCFrames[count] = CFrame.new(target.X, target.Y + ARROW_HEIGHT - bobY, target.Z)
		local pulse = (math.sin(t * 4) + 1) / 2
		local size = 9 + pulse * 3
		if math.abs(ringPart.Size.Y - size) > 0.05 then
			ringPart.Size = Vector3.new(0.2, size, size)
		end
		count += 1
		moveParts[count] = ringPart
		moveCFrames[count] = CFrame.new(target.X, target.Y - 1.6, target.Z) * CFrame.Angles(0, 0, math.pi / 2)
		label.Rotation = math.sin(t * 2.5) * 6
	end
	return count
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICH
-- ---------------------------------------------------------------------
-- Foto-Modus: Symbole, Pfeile, Glitzer und Bildschirm-Effekte aus
function NestField.SetHidden(value: boolean)
	hidden = value
end

local function step(dt: number)
	frame += 1
	animClock += dt
	local camera = workspace.CurrentCamera
	local camPos = if camera then camera.CFrame.Position else Vector3.zero
	table.clear(moveParts)
	table.clear(moveCFrames)
	local count = stepMonsters(dt, camPos, 0)
	count = stepPops(count)
	count = stepRace(count)
	if count > 0 then
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	padClock += dt
	if padClock >= PAD_INTERVAL then
		padClock = math.min(padClock - PAD_INTERVAL, PAD_INTERVAL)
		stepPads(camPos)
	end
	trailClock += dt
	if trailClock >= TRAIL_INTERVAL then
		trailClock = 0
		stepTrails(camPos)
	end
	glitterClock += dt
	if glitterClock >= GLITTER_INTERVAL then
		glitterClock = 0
		stepGlitter(camPos)
	end
end

function NestField.Init(context: any, map: Instance)
	ctx = context
	local visuals = Instance.new("Folder")
	visuals.Name = "MeteorHeistCreatures"
	visuals.Parent = workspace
	fxFolder = visuals
	buildPops()
	buildRace()
	buildEdge()
	player:GetAttributeChangedSignal("SpeedPadUntil"):Connect(onSpeedPad)
	player.CharacterAdded:Connect(function()
		-- neuer Charakter: Sichtfeld zurück auf normal (der Boost gilt nicht mehr)
		local camera = workspace.CurrentCamera
		if baseFov and camera then
			fovToken += 1
			camera.FieldOfView = baseFov
			baseFov = nil
		end
	end)
	ctx.Remotes.Effect.OnClientEvent:Connect(function(name)
		if name == "RaceStart" then
			playFanfare()
		end
	end)
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
		local nests = field:WaitForChild("Nests", 30)
		if nests then
			for _, nest in ipairs(nests:GetChildren()) do
				addGlitter(nest)
			end
			nests.ChildAdded:Connect(addGlitter)
		end
		local padFolder = field:WaitForChild("SpeedPads", 30)
		if padFolder then
			for _, pad in ipairs(padFolder:GetChildren()) do
				addPad(pad)
			end
			padFolder.ChildAdded:Connect(addPad)
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
