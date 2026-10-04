-- =====================================================================
--  ALIEN-PARADE (alles lokal auf deinem Gerät)
--   • Die Eier (Ordner "ParadeMeteors") kommen vom Server und stehen dort im Start-Hangar.
--     Hier wird jedes Ei auf den Kopf seines Trägers gesetzt: Strecke aus der Parade-Uhr
--     (ParadePath, Attribute ParadeP0/ParadeSpeed), Spur + Ausweichen vor Bossen wie beim Server.
--   • Die Träger-Aliens gibt es NUR hier: einfache blockige Aliens (ca. 10 Teile), gepoolt und
--     wiederverwendet. Höchstens MAX_SMALL kleine (die nächsten zur Kamera) + MAX_BOSSES Bosse bekommen
--     ein Model, alle anderen Eier laufen ohne sichtbaren Träger (weit weg fällt das nicht auf).
--   • Watschel-Gang: Beine/Arme schwingen passend zur Strecke (kein Rutschen), Schritt-Wippen,
--     Kippeln, Antennen wackeln, ab und zu winkt einer. Kleine Eier sind oft gestapelt (1-3).
--   • Boss: groß, Krone, 2-3 Leibwächter laufen mit und stoßen beim Schubsen die Arme nach vorne.
--   • Ei weg (geklaut/gekauft): Träger hüpft erschrocken, "!" erscheint; ohne Eier rennt er davon.
--  Leistung: Bewegen mit EINEM workspace:BulkMoveTo pro Frame (WorldFX ruft Parade.Step auf),
--  Arm-/Bein-Posen sind vorberechnet (pro Teil genau ein neues CFrame), weit weg / außerhalb des
--  Bilds seltener bewegen, keine neuen Tabellen pro Frame.
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = require(script.Parent:WaitForChild("UI"))
local ParadePath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ParadePath"))

local Parade = {}

local ctx: any = nil
local path: ParadePath.Path? = nil
local fxFolder: Folder? = nil
local hidden = false -- Foto-Modus: "!" aus

local MAX_SMALL = 80 -- so viele kleine Träger sind höchstens sichtbar (die nächsten)
local MAX_BOSSES = 8
local RENDER_RANGE = 420 -- weiter weg: kein Träger-Model
local SCAN_INTERVAL = 0.25 -- so oft wird neu verteilt, wer ein Model bekommt
local CLOSE_DISTANCE = 45 -- so nah immer jedes Frame
local NEAR_DISTANCE = 110 -- sichtbar und näher: jedes Frame, weiter weg jedes FAR_SKIP. Frame
local FAR_SKIP = 3
local BEHIND_SKIP = 6 -- außerhalb des Bilds
local HIDDEN_CF = CFrame.new(0, -5000, 0)
-- Ausweichen beim Überholen eines Bosses (gleiche Werte wie der Server!)
local DODGE_ZONE = 8
local DODGE_FADE = 5
local DODGE_OFFSET = 8.4
local HOUSE_INSET = 10 -- so weit hinter der leuchtenden Hangar-Öffnung startet der Pfad (MapBuilder)

-- Gang
local STRIDE = 3.4 -- Studs pro Doppelschritt (mal Größe)
local POSE_STEPS = 33
local SWING_MAX = 1.5 -- rad, Bereich der vorberechneten Schwing-Posen
local LEG_SWING = 0.55
local ARM_SWING = 0.5
local BOB = 0.22
local ROLL = 0.07
local WAVE_TIME = 1.4
local WAVE_MIN = 6
local WAVE_RANGE = 10
local SCARED_HOP = 0.45
local SCARED_MARK = 1.2 -- so lange ist das "!" zu sehen
local RUN_TIME = 3.5 -- so lange rennt ein Träger ohne Eier noch weiter
local RUN_FACTOR = 2.4
local PUSH_POSE = 0.35 -- so lange stoßen die Leibwächter nach einem Schubser die Arme nach vorne
local BOSS_FX_WINDOW = 2.5 -- nur Bosse, die gerade erst losgelaufen sind, bekommen den Start-Effekt

local SMALL_COLORS = {
	Color3.fromRGB(75, 200, 75),
	Color3.fromRGB(80, 170, 255),
	Color3.fromRGB(255, 110, 200),
	Color3.fromRGB(255, 170, 40),
	Color3.fromRGB(160, 90, 255),
	Color3.fromRGB(255, 220, 50),
	Color3.fromRGB(40, 210, 200),
}
local BOSS_COLOR = Color3.fromRGB(120, 40, 170)
local GUARD_SUIT = Color3.fromRGB(35, 35, 40)
local GUARD_SKIN = Color3.fromRGB(110, 190, 90)
local EYE_COLOR = Color3.fromRGB(20, 20, 25)
local GOLD = Color3.fromRGB(255, 200, 40)
local BLACK = Color3.new(0, 0, 0)

-- ---------------------------------------------------------------------
-- BAUPLAN DER ALIENS (Größe 1, Füße bei y = 0, Blick nach -Z)
-- Limb = Teil schwingt um seinen Drehpunkt (Pivot); Rest = Lage relativ zum Drehpunkt
-- ---------------------------------------------------------------------
type PartSpec = {
	Size: Vector3,
	Pivot: Vector3,
	Rest: CFrame,
	Limb: string?, -- "LegL" | "LegR" | "ArmL" | "ArmR" | "AntL" | "AntR"
	Role: string, -- "Skin" | "Body" | "Eye" | "Gold"
	Head: boolean?,
}

local BASE_SPECS: { PartSpec } = {
	{
		Size = Vector3.new(0.8, 1.4, 0.8),
		Pivot = Vector3.new(-0.5, 1.4, 0),
		Rest = CFrame.new(0, -0.7, 0),
		Limb = "LegL",
		Role = "Body",
	},
	{
		Size = Vector3.new(0.8, 1.4, 0.8),
		Pivot = Vector3.new(0.5, 1.4, 0),
		Rest = CFrame.new(0, -0.7, 0),
		Limb = "LegR",
		Role = "Body",
	},
	{ Size = Vector3.new(2, 1.8, 1.4), Pivot = Vector3.new(0, 2.3, 0), Rest = CFrame.new(), Role = "Body" },
	{
		Size = Vector3.new(0.6, 1.4, 0.6),
		Pivot = Vector3.new(-1.3, 3, 0),
		Rest = CFrame.new(0, -0.6, 0),
		Limb = "ArmL",
		Role = "Skin",
	},
	{
		Size = Vector3.new(0.6, 1.4, 0.6),
		Pivot = Vector3.new(1.3, 3, 0),
		Rest = CFrame.new(0, -0.6, 0),
		Limb = "ArmR",
		Role = "Skin",
	},
	{
		Size = Vector3.new(2.4, 2.2, 2),
		Pivot = Vector3.new(0, 4.3, 0),
		Rest = CFrame.new(),
		Role = "Skin",
		Head = true,
	},
	{ Size = Vector3.new(0.5, 0.7, 0.2), Pivot = Vector3.new(-0.5, 4.5, -1.02), Rest = CFrame.new(), Role = "Eye" },
	{ Size = Vector3.new(0.5, 0.7, 0.2), Pivot = Vector3.new(0.5, 4.5, -1.02), Rest = CFrame.new(), Role = "Eye" },
	{
		Size = Vector3.new(0.25, 1.2, 0.25),
		Pivot = Vector3.new(-1.05, 5.1, 0),
		Rest = CFrame.Angles(0, 0, 0.6) * CFrame.new(0, 0.6, 0),
		Limb = "AntL",
		Role = "Skin",
	},
	{
		Size = Vector3.new(0.25, 1.2, 0.25),
		Pivot = Vector3.new(1.05, 5.1, 0),
		Rest = CFrame.Angles(0, 0, -0.6) * CFrame.new(0, 0.6, 0),
		Limb = "AntR",
		Role = "Skin",
	},
}

-- Krone des Bosses: 4 goldene Zacken an den Kopf-Ecken (das Ei sitzt in der Mitte)
local CROWN_SPECS: { PartSpec } = {}
for _, corner in ipairs({ { -0.95, -0.8 }, { 0.95, -0.8 }, { -0.95, 0.8 }, { 0.95, 0.8 } }) do
	table.insert(CROWN_SPECS, {
		Size = Vector3.new(0.45, 0.8, 0.45),
		Pivot = Vector3.new(corner[1], 5.8, corner[2]),
		Rest = CFrame.new(),
		Role = "Gold",
	})
end

type Kind = {
	Specs: { PartSpec },
	Scale: number,
	Static: { CFrame }, -- feste Lage je Teil (Nicht-Limbs)
	Swing: { [number]: { CFrame } }, -- Limbs: vorberechnete Posen (Schwingen um X bzw. Z)
	Raise: { [number]: { CFrame } }, -- Arme: hochgerissen (Winken / Panik)
	Limbs: { [number]: string },
	Head: number,
}

local function scaledRest(rest: CFrame, scale: number): CFrame
	return CFrame.new(rest.Position * scale) * rest.Rotation
end

local function poseIndex(angle: number): number
	local k = math.clamp((angle / SWING_MAX + 1) * 0.5, 0, 1)
	return math.floor(k * (POSE_STEPS - 1) + 0.5) + 1
end

local function buildKind(specs: { PartSpec }, scale: number): Kind
	local kind: Kind = { Specs = specs, Scale = scale, Static = {}, Swing = {}, Raise = {}, Limbs = {}, Head = 1 }
	for i, spec in ipairs(specs) do
		local pivot = CFrame.new(spec.Pivot * scale)
		local rest = scaledRest(spec.Rest, scale)
		kind.Static[i] = pivot * rest
		if spec.Head then
			kind.Head = i
		end
		local limb = spec.Limb
		if limb then
			kind.Limbs[i] = limb
			local swing: { CFrame } = {}
			local sideways = limb == "AntL" or limb == "AntR"
			for k = 1, POSE_STEPS do
				local angle = ((k - 1) / (POSE_STEPS - 1) * 2 - 1) * SWING_MAX
				local rot = if sideways then CFrame.Angles(0, 0, angle) else CFrame.Angles(angle, 0, 0)
				swing[k] = pivot * rot * rest
			end
			kind.Swing[i] = swing
			if limb == "ArmL" or limb == "ArmR" then
				-- hochgerissener Arm (seitlich nach oben, winkt hin und her)
				local raise: { CFrame } = {}
				local sign = if limb == "ArmR" then 1 else -1
				for k = 1, POSE_STEPS do
					local u = (k - 1) / (POSE_STEPS - 1)
					raise[k] = pivot * CFrame.Angles(0, 0, sign * (2.3 + 0.6 * u)) * rest
				end
				kind.Raise[i] = raise
			end
		end
	end
	return kind
end

local bossSpecs: { PartSpec } = table.clone(BASE_SPECS)
for _, spec in ipairs(CROWN_SPECS) do
	table.insert(bossSpecs, spec)
end

local smallKind: Kind
local bossKind: Kind
local guardKind: Kind

-- ---------------------------------------------------------------------
-- POOL (lokale Models werden nie zerstört, nur versteckt und wiederverwendet)
-- ---------------------------------------------------------------------
type Model = {
	Kind: Kind,
	Parts: { BasePart },
	Mark: BillboardGui,
	Guards: { Model },
	Hidden: boolean,
}

local smallFree: { Model } = {}
local bossFree: { Model } = {}
local smallCount = 0
local bossCount = 0

local function makeModel(kind: Kind, withMark: boolean): Model
	local folder = fxFolder
	local parts: { BasePart } = {}
	for _, spec in ipairs(kind.Specs) do
		table.insert(
			parts,
			UI.Create("Part", {
				Name = "ParadeAlien",
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Material = if spec.Role == "Gold" then Enum.Material.SmoothPlastic else Enum.Material.Plastic,
				TopSurface = Enum.SurfaceType.Smooth,
				BottomSurface = Enum.SurfaceType.Smooth,
				Size = spec.Size * kind.Scale,
				Color = if spec.Role == "Eye" then EYE_COLOR elseif spec.Role == "Gold" then GOLD else BLACK,
				CFrame = HIDDEN_CF,
				Parent = folder,
			})
		)
	end
	local head = parts[kind.Head]
	local mark: BillboardGui = UI.Create("BillboardGui", {
		Name = "ParadeMark",
		Size = UDim2.fromScale(2.2 * kind.Scale, 2.2 * kind.Scale),
		StudsOffset = Vector3.new(1.8 * kind.Scale, 0.6 * kind.Scale, 0),
		MaxDistance = 120,
		LightInfluence = 0,
		Enabled = false,
		Adornee = head,
		Parent = if withMark then head else nil,
	})
	local label: TextLabel = UI.Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.FredokaOne,
		TextScaled = true,
		Text = "!",
		TextColor3 = Color3.fromRGB(255, 225, 40),
		Parent = mark,
	})
	UI.Create("UIStroke", { Thickness = 3, Color = BLACK, Parent = label })
	return { Kind = kind, Parts = parts, Mark = mark, Guards = {}, Hidden = true }
end

local function colorModel(model: Model, skin: Color3, body: Color3)
	for i, spec in ipairs(model.Kind.Specs) do
		local part = model.Parts[i]
		local color = if spec.Role == "Skin" then skin elseif spec.Role == "Body" then body else nil
		if color and part.Color ~= color then
			part.Color = color
		end
	end
end

local function acquireSmall(): Model?
	local model = table.remove(smallFree)
	if model then
		return model
	end
	if smallCount >= MAX_SMALL then
		return nil
	end
	smallCount += 1
	return makeModel(smallKind, true)
end

local function acquireBoss(): Model?
	local model = table.remove(bossFree)
	if model then
		return model
	end
	if bossCount >= MAX_BOSSES then
		return nil
	end
	bossCount += 1
	model = makeModel(bossKind, true)
	colorModel(model, BOSS_COLOR, BOSS_COLOR:Lerp(BLACK, 0.25))
	for _ = 1, 3 do
		local guard = makeModel(guardKind, false)
		colorModel(guard, GUARD_SKIN, GUARD_SUIT)
		table.insert(model.Guards, guard)
	end
	return model
end

-- ---------------------------------------------------------------------
-- TRÄGER + EIER
-- ---------------------------------------------------------------------
type Egg = {
	Part: BasePart,
	Stack: number,
	Size: number,
	Height: number, -- Ei-Mitte über der Straße (gestapelt: rutscht nach, wenn ein unteres fehlt)
	OffsetCF: CFrame,
}

type Carrier = {
	Id: number,
	Boss: boolean,
	Guards: number,
	T0: number,
	P0: number,
	Speed: number,
	Lane: number,
	HeadTop: number,
	Eggs: { Egg },
	Dist: number,
	Index: number,
	Extra: number, -- zusätzliche Strecke beim Wegrennen (nur ohne Eier)
	CamDist: number,
	Model: Model?,
	Want: boolean,
	Phase: number,
	Color: number,
	Slot: number,
	Fresh: boolean,
	Scared: number, -- Zeitpunkt des Schrecks (-1 = nie)
	Empty: boolean,
	WaveAt: number,
	WaveStart: number,
}

local carriers: { Carrier } = {}
local carrierById: { [number]: Carrier } = {}
local bosses: { Carrier } = {}
local eggSeen: { [Instance]: boolean } = {}
local candidates: { Carrier } = {}
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}
local hideParts: { BasePart } = {}
local hideCFrames: { CFrame } = {}
local nextLocalId = -1

-- Parade-Uhr (siehe ParadePath)
local clockT: number? = nil
local clockP = 0
local clockRate = 1
local scanClock = SCAN_INTERVAL

local function byCamDist(a: Carrier, b: Carrier): boolean
	return a.CamDist < b.CamDist
end

local function carrierDistance(carrier: Carrier, now: number): number
	local t = clockT
	if t then
		return (clockP + (now - t) * clockRate - carrier.P0) * carrier.Speed + carrier.Extra
	end
	return (now - carrier.T0) * carrier.Speed + carrier.Extra -- Uhr noch nicht da: Serverzeit
end

-- Höhe der Eier neu stapeln (ein unteres Ei fehlt -> obere rutschen nach)
local function restack(carrier: Carrier)
	table.sort(carrier.Eggs, function(a: Egg, b: Egg)
		return a.Stack < b.Stack
	end)
	local height = carrier.HeadTop
	for _, egg in ipairs(carrier.Eggs) do
		local center = height + egg.Size / 2 + 0.05
		height += egg.Size
		if math.abs(center - egg.Height) > 0.01 then
			egg.Height = center
			egg.OffsetCF = CFrame.new(0, center, 0)
		end
	end
end

-- Start-Effekt einer Boss-Parade (Konfetti an der Hangar-Öffnung)
local function bossStartFX(carrier: Carrier, now: number)
	local p = path
	if not p or now - carrier.T0 > BOSS_FX_WINDOW or not ctx or not ctx.Effects then
		return
	end
	local pos = ParadePath.Sample(p, HOUSE_INSET)
	ctx.Effects.Play("ParadeBoss", 1, { Position = pos + Vector3.new(0, 4, 0) })
end

-- true = aufgenommen (oder kein Ei), false = Attribute fehlen noch
local function addEgg(inst: Instance): boolean
	if not inst:IsA("BasePart") or eggSeen[inst] then
		return true
	end
	local p0 = inst:GetAttribute("ParadeP0")
	local t0 = inst:GetAttribute("ParadeT0")
	local speed = inst:GetAttribute("ParadeSpeed")
	local lane = inst:GetAttribute("ParadeLane")
	if type(p0) ~= "number" or type(t0) ~= "number" or type(speed) ~= "number" or type(lane) ~= "number" then
		return false
	end
	eggSeen[inst] = true
	local id = inst:GetAttribute("CarrierId")
	if type(id) ~= "number" then
		id = nextLocalId
		nextLocalId -= 1
	end
	local boss = inst:GetAttribute("Carrier") == "Boss"
	local carrier = carrierById[id]
	if not carrier then
		local parade = ctx and ctx.Config.Parade
		local scale = if boss then (tonumber(parade and parade.BossScale) or 2.2) else 1
		local headTop = (tonumber(parade and parade.CarrierHeight) or 5.4) * scale
		local now = workspace:GetServerTimeNow()
		carrier = {
			Id = id,
			Boss = boss,
			Guards = math.clamp(tonumber(inst:GetAttribute("ParadeGuards")) or 0, 0, 3),
			T0 = t0,
			P0 = p0,
			Speed = speed,
			Lane = lane,
			HeadTop = headTop,
			Eggs = {},
			Dist = 0,
			Index = 1,
			Extra = 0,
			CamDist = math.huge,
			Model = nil,
			Want = false,
			Phase = math.random() * math.pi * 2,
			Color = math.abs(id) % #SMALL_COLORS + 1,
			Slot = math.random(0, BEHIND_SKIP - 1),
			Fresh = true,
			Scared = -1,
			Empty = false,
			WaveAt = now + math.random() * WAVE_RANGE,
			WaveStart = -math.huge,
		}
		carrierById[id] = carrier
		table.insert(carriers, carrier)
		if boss then
			table.insert(bosses, carrier)
			bossStartFX(carrier, now)
		end
		scanClock = SCAN_INTERVAL -- gleich beim nächsten Frame ein Model geben
	end
	local size = inst.Size.Y
	table.insert(carrier.Eggs, {
		Part = inst,
		Stack = tonumber(inst:GetAttribute("ParadeStack")) or 1,
		Size = size,
		Height = -1,
		OffsetCF = CFrame.new(),
	})
	restack(carrier)
	carrier.Fresh = true
	return true
end

local function watchEgg(inst: Instance)
	if addEgg(inst) then
		return
	end
	-- Attribute kommen evtl. erst nach dem Einfügen -> warten
	local connection: RBXScriptConnection? = nil
	connection = inst.AttributeChanged:Connect(function()
		if addEgg(inst) or not inst.Parent then
			if connection then
				connection:Disconnect()
			end
		end
	end)
end

-- Model verstecken (Teile weit weg) und zurück in den Pool
local function hideModel(model: Model)
	if model.Hidden then
		return
	end
	model.Hidden = true
	model.Mark.Enabled = false
	for _, part in ipairs(model.Parts) do
		table.insert(hideParts, part)
		table.insert(hideCFrames, HIDDEN_CF)
	end
	for _, guard in ipairs(model.Guards) do
		hideModel(guard)
	end
end

local function releaseModel(carrier: Carrier)
	local model = carrier.Model
	if not model then
		return
	end
	carrier.Model = nil
	hideModel(model)
	table.insert(if carrier.Boss then bossFree else smallFree, model)
end

local function giveModel(carrier: Carrier)
	local model = if carrier.Boss then acquireBoss() else acquireSmall()
	if not model then
		return
	end
	if not carrier.Boss then
		local color = SMALL_COLORS[carrier.Color] or SMALL_COLORS[1]
		colorModel(model, color, color:Lerp(BLACK, 0.18))
	end
	model.Hidden = false
	carrier.Model = model
	carrier.Fresh = true
	if carrier.Scared >= 0 and workspace:GetServerTimeNow() - carrier.Scared < SCARED_MARK then
		model.Mark.Enabled = not hidden
	end
	for g, guard in ipairs(model.Guards) do
		guard.Hidden = g > carrier.Guards -- unbenutzte Leibwächter bleiben versteckt
	end
end

local function removeCarrier(index: number)
	local carrier = carriers[index]
	releaseModel(carrier)
	carrierById[carrier.Id] = nil
	local bossIndex = table.find(bosses, carrier)
	if bossIndex then
		table.remove(bosses, bossIndex)
	end
	carriers[index] = carriers[#carriers]
	carriers[#carriers] = nil
end

-- Alle SCAN_INTERVAL s: die nächsten MAX_SMALL kleinen Träger (+ alle Bosse) bekommen ein Model
local function scan()
	local count = 0
	for _, carrier in ipairs(carriers) do
		carrier.Want = false
		if carrier.CamDist <= RENDER_RANGE then
			if carrier.Boss then
				carrier.Want = true
			else
				count += 1
				candidates[count] = carrier
			end
		end
	end
	for i = #candidates, count + 1, -1 do
		candidates[i] = nil
	end
	if count > MAX_SMALL then
		table.sort(candidates, byCamDist)
	end
	for i = 1, math.min(count, MAX_SMALL) do
		candidates[i].Want = true
	end
	-- erst abgeben, dann verteilen (sonst ist der Pool leer)
	for _, carrier in ipairs(carriers) do
		if carrier.Model and not carrier.Want then
			releaseModel(carrier)
		end
	end
	for _, carrier in ipairs(carriers) do
		if carrier.Want and not carrier.Model then
			giveModel(carrier)
		end
	end
end

-- Versteckte Models wirklich wegschieben (gesammelt, ein BulkMoveTo)
local function flushHidden()
	if #hideParts > 0 then
		workspace:BulkMoveTo(hideParts, hideCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		table.clear(hideParts)
		table.clear(hideCFrames)
	end
end

-- Drehung aus Blickrichtung (waagrecht) + Kippeln um die Laufrichtung -> EIN neues CFrame
local function rootFrame(x: number, y: number, z: number, dir: Vector3, roll: number): CFrame
	local fx, fz = dir.X, dir.Z
	local c, s = math.cos(roll), math.sin(roll)
	return CFrame.new(x, y, z, -fz * c, fz * s, -fx, s, c, 0, fx * c, -fx * s, -fz)
end

-- Pose eines Models in die Listen (Gibt die neue Anzahl zurück).
-- swing = Schwing-Wert (-1..1), raise/raiseBoth = Arm(e) hoch (u = 0..1 Winken), push = Arme nach vorne
local function poseModel(
	model: Model,
	root: CFrame,
	swing: number,
	antenna: number,
	raiseRight: boolean,
	raiseBoth: boolean,
	raiseU: number,
	push: boolean,
	count: number
): number
	local kind = model.Kind
	local parts = model.Parts
	local legIndex = poseIndex(swing * LEG_SWING)
	local legIndexR = poseIndex(-swing * LEG_SWING)
	local armIndex = poseIndex(-swing * ARM_SWING)
	local armIndexR = poseIndex(swing * ARM_SWING)
	local antIndex = poseIndex(antenna)
	local raiseIndex = math.floor(math.clamp(raiseU, 0, 1) * (POSE_STEPS - 1) + 0.5) + 1
	local pushIndex = poseIndex(1.45) -- Arme waagrecht nach vorne (-Z)
	for i, part in ipairs(parts) do
		local limb = kind.Limbs[i]
		local cf: CFrame
		if not limb then
			cf = kind.Static[i]
		elseif limb == "LegL" then
			cf = kind.Swing[i][legIndex]
		elseif limb == "LegR" then
			cf = kind.Swing[i][legIndexR]
		elseif limb == "ArmL" then
			if push then
				cf = kind.Swing[i][pushIndex]
			elseif raiseBoth then
				cf = kind.Raise[i][raiseIndex]
			else
				cf = kind.Swing[i][armIndex]
			end
		elseif limb == "ArmR" then
			if push then
				cf = kind.Swing[i][pushIndex]
			elseif raiseRight or raiseBoth then
				cf = kind.Raise[i][raiseIndex]
			else
				cf = kind.Swing[i][armIndexR]
			end
		elseif limb == "AntL" then
			cf = kind.Swing[i][antIndex]
		else
			cf = kind.Swing[i][POSE_STEPS + 1 - antIndex]
		end
		count += 1
		moveParts[count] = part
		moveCFrames[count] = root * cf
	end
	return count
end

-- Leibwächter neben/hinter dem Boss (rechts, links, hinten)
local GUARD_OFFSETS = { { -5.2, 0 }, { 5.2, 0 }, { 0, 6 } }

-- Ein Träger (Model + Eier) in die Listen
local function poseCarrier(carrier: Carrier, ground: Vector3, dir: Vector3, now: number, count: number): number
	local model = carrier.Model
	local scale = if model then model.Kind.Scale elseif carrier.Boss then 2.2 else 1
	local cycle = carrier.Dist / (STRIDE * scale) * math.pi * 2 + carrier.Phase
	local swing = math.sin(cycle)
	local bob = math.abs(swing) * BOB * scale
	local roll = swing * ROLL
	local scared = carrier.Scared
	if scared >= 0 then
		local u = (now - scared) / SCARED_HOP
		if u < 1 then
			bob += 4 * u * (1 - u) * 1.6 * scale -- Schreck-Hüpfer
		end
	end
	local root = rootFrame(ground.X, ground.Y + bob, ground.Z, dir, roll)
	if model then
		local waving = not carrier.Boss and now - carrier.WaveStart < WAVE_TIME
		local panic = carrier.Empty and scared >= 0
		local raiseU = 0.5 + 0.5 * math.sin(now * 14 + carrier.Phase)
		count = poseModel(model, root, swing, math.sin(cycle * 2) * 0.3, waving, panic, raiseU, false, count)
		if carrier.Boss then
			local pushTime = tonumber(ctx and ctx.Config.Parade and ctx.Config.Parade.PushInterval) or 1.5
			local push = not panic and (now - carrier.T0) % pushTime < PUSH_POSE
			local rx, rz = -dir.Z, dir.X -- rechts
			for g = 1, carrier.Guards do
				local guard = model.Guards[g]
				local offset = GUARD_OFFSETS[g]
				if guard and offset then
					local gx = ground.X + rx * offset[1] - dir.X * offset[2]
					local gz = ground.Z + rz * offset[1] - dir.Z * offset[2]
					local gCycle = carrier.Dist / (STRIDE * guard.Kind.Scale) * math.pi * 2 + g * 1.7
					local gSwing = math.sin(gCycle)
					local gRoot =
						rootFrame(gx, ground.Y + math.abs(gSwing) * BOB * guard.Kind.Scale, gz, dir, gSwing * ROLL)
					count = poseModel(guard, gRoot, gSwing, 0, false, panic, raiseU, push, count)
				end
			end
		end
	end
	for _, egg in ipairs(carrier.Eggs) do
		count += 1
		moveParts[count] = egg.Part
		moveCFrames[count] = root * egg.OffsetCF
	end
	return count
end

-- Eier prüfen: weg (geklaut/gekauft/am Ziel)? -> Schreck bzw. fertig. true = Träger kann weg.
local function checkEggs(carrier: Carrier, now: number, length: number): boolean
	local eggs = carrier.Eggs
	local lost = false
	for i = #eggs, 1, -1 do
		if eggs[i].Part.Parent == nil then
			eggSeen[eggs[i].Part] = nil
			table.remove(eggs, i)
			lost = true
		end
	end
	if lost then
		if carrier.Dist < length - 3 then
			carrier.Scared = now
			local model = carrier.Model
			if model then
				model.Mark.Enabled = not hidden
			end
		end
		if #eggs == 0 then
			carrier.Empty = true
		else
			restack(carrier)
		end
	end
	local model = carrier.Model
	if model and model.Mark.Enabled and now - carrier.Scared > SCARED_MARK then
		model.Mark.Enabled = false
	end
	if carrier.Empty then
		-- ohne Eier: am Ziel sofort weg, nach einem Schreck noch kurz wegrennen
		return carrier.Scared < 0 or now - carrier.Scared > RUN_TIME or carrier.Dist >= length
	end
	return false
end

-- Jedes Frame (von WorldFX aufgerufen, vor den krassen Eiern)
function Parade.Step(now: number, dt: number, camPos: Vector3, look: Vector3, cosLimit: number, frame: number)
	local p = path
	if not p then
		return
	end
	local length = p.Length
	-- Bosse zuerst (die anderen weichen ihnen aus)
	for _, boss in ipairs(bosses) do
		boss.Dist = carrierDistance(boss, now)
	end
	local count = 0
	for i = #carriers, 1, -1 do
		local carrier = carriers[i]
		if checkEggs(carrier, now, length) then
			removeCarrier(i)
		else
			if carrier.Empty and carrier.Scared >= 0 then
				carrier.Extra += dt * carrier.Speed * clockRate * (RUN_FACTOR - 1) -- rennt davon
			end
			if not carrier.Boss then
				carrier.Dist = carrierDistance(carrier, now)
			end
			if not carrier.Boss and carrier.Model and now >= carrier.WaveAt then
				carrier.WaveStart = now
				carrier.WaveAt = now + WAVE_MIN + math.random() * WAVE_RANGE
			end
			local dist = math.clamp(carrier.Dist, 0, length)
			local pos, dir, index = ParadePath.Sample(p, dist, carrier.Index)
			carrier.Index = index
			local lateral = carrier.Lane
			if not carrier.Boss and #bosses > 0 then
				local amount = 0
				for _, boss in ipairs(bosses) do
					amount = math.max(amount, ParadePath.DodgeAmount(dist, boss.Dist, DODGE_ZONE, DODGE_FADE))
				end
				lateral = ParadePath.Lateral(carrier.Lane, amount, DODGE_OFFSET)
			end
			local ground = pos + Vector3.new(-dir.Z, 0, dir.X) * lateral
			local rel = ground - camPos
			local distance = rel.Magnitude
			carrier.CamDist = distance
			-- ganz nah, frisch, sichtbar in der Nähe: jedes Frame; sonst seltener
			local due = true
			if carrier.Fresh then
				carrier.Fresh = false
			elseif distance >= CLOSE_DISTANCE then
				local slot = frame + carrier.Slot
				if rel:Dot(look) < distance * cosLimit then
					due = slot % BEHIND_SKIP == 0
				elseif distance >= NEAR_DISTANCE then
					due = slot % FAR_SKIP == 0
				end
			end
			if due then
				count = poseCarrier(carrier, ground, dir, now, count)
			end
		end
	end
	if count > 0 then
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		-- Listen leeren (Kapazität bleibt -> keine neuen Tabellen)
		table.clear(moveParts)
		table.clear(moveCFrames)
	end
	scanClock += dt
	if scanClock >= SCAN_INTERVAL then
		scanClock = 0
		scan()
	end
	flushHidden()
end

-- Foto-Modus: "!" ausblenden
function Parade.SetHidden(value: boolean)
	hidden = value
	if value then
		for _, carrier in ipairs(carriers) do
			local model = carrier.Model
			if model then
				model.Mark.Enabled = false
			end
		end
	end
end

local function readClock(folder: Instance)
	local t, p, rate = ParadePath.ParseClock(folder:GetAttribute("ParadeClock"))
	if t and p and rate then
		clockT, clockP, clockRate = t, p, rate
	end
end

function Parade.Init(context: any, map: Instance)
	ctx = context
	local scale = tonumber(ctx.Config.Parade and ctx.Config.Parade.BossScale) or 2.2
	smallKind = buildKind(BASE_SPECS, 1)
	bossKind = buildKind(bossSpecs, scale)
	guardKind = buildKind(BASE_SPECS, 1.15)
	fxFolder = UI.Create("Folder", { Name = "MeteorHeistParade", Parent = workspace })

	task.spawn(function()
		local folder = map:WaitForChild("Parade", 60)
		if folder then
			path = ParadePath.FromFolder(folder)
			readClock(folder)
			folder:GetAttributeChangedSignal("ParadeClock"):Connect(function()
				readClock(folder)
			end)
		end
		if not path then
			path = ParadePath.FromConfig(ctx.Config)
		end
		if not path then
			warn("[Parade] Kein Parade-Pfad gefunden – Parade-Animation aus")
			return
		end
		local eggs = map:WaitForChild("ParadeMeteors", 60)
		if not eggs then
			warn("[Parade] 'ParadeMeteors' nicht gefunden – Parade-Animation aus")
			return
		end
		for _, child in ipairs(eggs:GetChildren()) do
			watchEgg(child)
		end
		eggs.ChildAdded:Connect(watchEgg)
	end)
end

return Parade
