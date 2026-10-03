-- =====================================================================
--  WELT-ANIMATIONEN (alles lokal auf deinem Gerät -> butterweich, kein Server-Lag)
--   • Meteore auf dem großen Laufband: Position = Start + Richtung * Tempo * (Zeit seit Start)
--   • Streifen auf dem Laufband und auf den Treadmills laufen mit
--   • Aliens wippen sanft, Regenbogen-Teile färben sich durch
--   • Meteore in der Base zeigen "🐣 Schlüpft in m:ss"
--   • Laufband-Schilder zeigen, welche Laufbänder DU schon freigeschaltet hast
--  Arbeit pro Frame ist begrenzt: weit entfernte Dinge werden seltener oder gar nicht bewegt.
-- =====================================================================

local RunService = game:GetService("RunService")

local UI = require(script.Parent:WaitForChild("UI"))

local WorldFX = {}

local ctx: any = nil
local fxFolder: Folder? = nil

local NEAR_DISTANCE = 260 -- näher dran: jedes Frame bewegen
local FAR_FRAME_SKIP = 4 -- weiter weg: nur jedes 4. Frame
local STRIPE_RANGE = 320 -- Streifen auf Treadmills nur in der Nähe bewegen
local BOB_RANGE = 100 -- Aliens nur in der Nähe wippen lassen
local SLOW_INTERVAL = 1 / 30 -- Wippen + Regenbogen höchstens 30x pro Sekunde
local HATCH_INTERVAL = 0.2 -- Schlüpf-Countdown 5x pro Sekunde
local HATCH_RANGE = 170
local RAINBOW_RANGE = 400
local BELT_SPIN = 0.6 -- sanfte Drehung der Meteore auf dem Band (rad/s)

local HATCH_COLOR = Color3.fromRGB(255, 225, 120)

-- Wiederverwendete Listen für workspace:BulkMoveTo (keine neuen Tabellen pro Frame)
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}
local frameNumber = 0

-- ---------------------------------------------------------------------
-- METEORE AUF DEM LAUFBAND
-- ---------------------------------------------------------------------
type BeltRecord = {
	Part: BasePart,
	Start: Vector3,
	Dir: Vector3,
	Speed: number,
	T0: number,
	MaxDist: number,
	Phase: number,
	Slot: number,
}

local beltRecords: { BeltRecord } = {}
local beltByPart: { [Instance]: BeltRecord } = {}
local beltLength = 440

local function removeBeltRecord(record: BeltRecord)
	beltByPart[record.Part] = nil
	local index = table.find(beltRecords, record)
	if index then
		beltRecords[index] = beltRecords[#beltRecords]
		beltRecords[#beltRecords] = nil
	end
end

-- true = aufgenommen (oder kein Meteor), false = Attribute fehlen noch
local function addBeltMeteor(inst: Instance): boolean
	if not inst:IsA("BasePart") then
		return true
	end
	if beltByPart[inst] then
		return true
	end
	local t0 = inst:GetAttribute("BeltT0")
	local start = inst:GetAttribute("BeltStart")
	local dir = inst:GetAttribute("BeltDir")
	local speed = inst:GetAttribute("BeltSpeed")
	if type(t0) ~= "number" or typeof(start) ~= "Vector3" or typeof(dir) ~= "Vector3" or type(speed) ~= "number" then
		return false
	end
	local direction: Vector3 = if dir.Magnitude > 0.001 then dir.Unit else Vector3.zAxis
	local record: BeltRecord = {
		Part = inst,
		Start = start,
		Dir = direction,
		Speed = speed,
		T0 = t0,
		MaxDist = beltLength + 6,
		Phase = math.random() * math.pi * 2,
		Slot = math.random(0, FAR_FRAME_SKIP - 1),
	}
	beltByPart[inst] = record
	table.insert(beltRecords, record)
	return true
end

local function watchBeltMeteor(inst: Instance)
	if addBeltMeteor(inst) then
		return
	end
	-- Attribute kommen evtl. erst nach dem Einfügen -> warten
	local connection: RBXScriptConnection? = nil
	connection = inst.AttributeChanged:Connect(function()
		if addBeltMeteor(inst) or not inst.Parent then
			if connection then
				connection:Disconnect()
			end
		end
	end)
end

-- Gibt die Anzahl der eingetragenen Teile zurück
local function stepBelt(now: number, camPos: Vector3, count: number): number
	for i = #beltRecords, 1, -1 do
		local record = beltRecords[i]
		local part = record.Part
		if part.Parent == nil then
			removeBeltRecord(record)
		else
			local elapsed = now - record.T0
			local dist = math.clamp(record.Speed * elapsed, 0, record.MaxDist)
			local pos = record.Start + record.Dir * dist
			if (pos - camPos).Magnitude < NEAR_DISTANCE or (frameNumber + record.Slot) % FAR_FRAME_SKIP == 0 then
				local angle = elapsed * BELT_SPIN + record.Phase
				local c, s = math.cos(angle), math.sin(angle)
				count += 1
				moveParts[count] = part
				-- Drehung um die Hochachse, direkt als Matrix (nur EIN neues CFrame)
				moveCFrames[count] = CFrame.new(pos.X, pos.Y, pos.Z, c, 0, s, 0, 1, 0, -s, 0, c)
			end
		end
	end
	return count
end

-- ---------------------------------------------------------------------
-- STREIFEN (lokale Teile, die über Band und Treadmills laufen)
-- ---------------------------------------------------------------------
type StripeSet = {
	Parts: { BasePart },
	Origin: Vector3, -- Startpunkt auf der Oberfläche
	Dir: Vector3, -- Laufrichtung
	Rot: { number }, -- Drehmatrix (9 Zahlen)
	Length: number,
	Spacing: number,
	Speed: number,
	Center: Vector3,
	Always: boolean, -- true = immer bewegen (Hauptband)
}

local stripeSets: { StripeSet } = {}

-- Rainbow-Liste (weiter unten) wird auch von den Streifen benutzt
local addRainbow: (inst: Instance) -> ()

local function makeStripeSet(
	surfaceCFrame: CFrame,
	length: number,
	width: number,
	speed: number,
	spacing: number,
	colors: { normal: Color3, accent: Color3, rainbow: boolean, accentEvery: number },
	always: boolean
): StripeSet?
	local folder = fxFolder
	if not folder or length <= 1 or width <= 0.5 then
		return nil
	end
	local count = math.max(1, math.floor(length / spacing))
	spacing = length / count
	local dir = surfaceCFrame.LookVector
	local origin = surfaceCFrame.Position - dir * (length / 2)
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = surfaceCFrame:GetComponents()
	local set: StripeSet = {
		Parts = {},
		Origin = origin,
		Dir = dir,
		Rot = { r00, r01, r02, r10, r11, r12, r20, r21, r22 },
		Length = length,
		Spacing = spacing,
		Speed = speed,
		Center = surfaceCFrame.Position,
		Always = always,
	}
	for i = 1, count do
		local accent = colors.accentEvery > 0 and i % colors.accentEvery == 0
		-- gleich an die richtige Stelle setzen (Regenbogen-Welle hängt von der Position ab)
		local startPos = origin + dir * ((i - 0.5) * spacing)
		local stripe = UI.Create("Part", {
			Name = "Stripe",
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Size = Vector3.new(math.max(0.4, width - 0.8), 0.06, if accent then 0.5 else 0.7),
			Material = if accent then Enum.Material.Neon else Enum.Material.SmoothPlastic,
			Color = if accent then colors.accent else colors.normal,
			CFrame = surfaceCFrame.Rotation + startPos,
			Parent = folder,
		})
		if accent and colors.rainbow then
			stripe:SetAttribute("Rainbow", true)
			addRainbow(stripe)
		end
		table.insert(set.Parts, stripe)
	end
	table.insert(stripeSets, set)
	return set
end

local function stepStripes(now: number, camPos: Vector3, count: number): number
	for _, set in ipairs(stripeSets) do
		if set.Always or (set.Center - camPos).Magnitude < STRIPE_RANGE then
			local rot = set.Rot
			local r00, r01, r02, r10, r11, r12, r20, r21, r22 =
				rot[1], rot[2], rot[3], rot[4], rot[5], rot[6], rot[7], rot[8], rot[9]
			local shift = (now * set.Speed) % set.Length
			for i, stripe in ipairs(set.Parts) do
				local s = ((i - 0.5) * set.Spacing + shift) % set.Length
				local pos = set.Origin + set.Dir * s
				count += 1
				moveParts[count] = stripe
				moveCFrames[count] = CFrame.new(pos.X, pos.Y, pos.Z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
			end
		end
	end
	return count
end

-- Hauptband: Streifen quer über die ganze Länge
local function setupMainBelt(belt: Instance)
	if not belt:IsA("BasePart") then
		return
	end
	local start = belt:GetAttribute("BeltStart")
	local dir = belt:GetAttribute("BeltDir")
	local length = tonumber(belt:GetAttribute("BeltLength")) or belt.Size.Z
	local width = tonumber(belt:GetAttribute("BeltWidth")) or belt.Size.X
	local speed = tonumber(belt:GetAttribute("BeltSpeed")) or tonumber(ctx.Config.BeltSpeed) or 9
	if typeof(start) ~= "Vector3" then
		start = belt.Position + Vector3.new(0, belt.Size.Y / 2, -belt.Size.Z / 2)
	end
	if typeof(dir) ~= "Vector3" or dir.Magnitude < 0.001 then
		dir = Vector3.zAxis
	end
	local direction: Vector3 = (dir :: Vector3).Unit
	beltLength = length
	for _, record in ipairs(beltRecords) do
		record.MaxDist = beltLength + 6
	end
	local startPos: Vector3 = start :: Vector3
	local center = startPos + direction * (length / 2) + Vector3.new(0, 0.04, 0)
	makeStripeSet(CFrame.lookAt(center, center + direction), length, width, speed, 5, {
		normal = Color3.fromRGB(72, 72, 86),
		accent = Color3.fromRGB(30, 150, 230),
		rainbow = false,
		accentEvery = 4,
	}, true)
end

-- ---------------------------------------------------------------------
-- TREADMILLS (Laufbänder auf dem Spawn-Platz)
-- ---------------------------------------------------------------------
type TreadmillInfo = { Model: Model, Id: string }
local treadmills: { TreadmillInfo } = {}
local treadmillSeen: { [Instance]: boolean } = {}
local lastSteps = 0
local lastBest: string? = nil
local signKey = ""
local updateSigns: () -> ()

local function treadmillDef(id: string): any
	local list = ctx.Config.Treadmills
	if type(list) ~= "table" then
		return nil
	end
	for _, def in ipairs(list) do
		if def.Id == id then
			return def
		end
	end
	return nil
end

local function setupTreadmill(model: Instance)
	if not model:IsA("Model") or treadmillSeen[model] then
		return
	end
	local id = model:GetAttribute("TreadmillId")
	local belt = model.PrimaryPart or model:FindFirstChild("Belt")
	if type(id) ~= "string" or not belt or not belt:IsA("BasePart") then
		return
	end
	treadmillSeen[model] = true
	table.insert(treadmills, { Model = model, Id = id })

	local def = treadmillDef(id)
	local color: Color3 = if def and typeof(def.Color) == "Color3" then def.Color else Color3.new(1, 1, 1)
	local dir = belt:GetAttribute("BeltDir")
	local speed = tonumber(belt:GetAttribute("BeltSpeed")) or 14
	local cf = belt.CFrame
	local worldDir: Vector3 = if typeof(dir) == "Vector3" and dir.Magnitude > 0.001 then dir.Unit else -cf.LookVector
	-- Richtung auf die nächste Achse der Lauffläche legen (Länge/Breite der Fläche bestimmen)
	local localDir = cf:VectorToObjectSpace(worldDir)
	local alongZ = math.abs(localDir.Z) >= math.abs(localDir.X)
	local length = if alongZ then belt.Size.Z else belt.Size.X
	local width = if alongZ then belt.Size.X else belt.Size.Z
	local axis = if alongZ
		then Vector3.new(0, 0, if localDir.Z >= 0 then 1 else -1)
		else Vector3.new(if localDir.X >= 0 then 1 else -1, 0, 0)
	local direction = cf:VectorToWorldSpace(axis)
	local top = cf:PointToWorldSpace(Vector3.new(0, belt.Size.Y / 2 + 0.035, 0))
	makeStripeSet(CFrame.lookAt(top, top + direction, cf.UpVector), length, width, speed, 2.5, {
		normal = Color3.fromRGB(48, 48, 58),
		accent = color,
		rainbow = id == "Regenbogen" or (def ~= nil and def.Rainbow == true),
		accentEvery = 3,
	}, false)
	signKey = "" -- Schilder beim nächsten Mal neu schreiben
	updateSigns()
end

local function findSignLabel(model: Model, name: string): TextLabel?
	local sign = model:FindFirstChild("Sign", true)
	local frame = sign and sign:FindFirstChild("Frame")
	local labelObj = frame and frame:FindFirstChild(name)
	if labelObj and labelObj:IsA("TextLabel") then
		return labelObj
	end
	return nil
end

-- Schilder an den Laufbändern: freigeschaltet / gesperrt / dein bestes (nur bei Änderung)
updateSigns = function()
	if not ctx then
		return
	end
	local best = lastBest
	local unlocked = 0
	for _, info in ipairs(treadmills) do
		local def = treadmillDef(info.Id)
		local required = def and tonumber(def.Required) or tonumber(info.Model:GetAttribute("Required")) or 0
		if lastSteps >= required then
			unlocked += 1
		end
	end
	local key = unlocked .. "|" .. tostring(best) .. "|" .. #treadmills
	if key == signKey then
		return
	end
	signKey = key
	local Util = ctx.Util
	for _, info in ipairs(treadmills) do
		local def = treadmillDef(info.Id)
		local required = def and tonumber(def.Required) or tonumber(info.Model:GetAttribute("Required")) or 0
		local lockLabel = findSignLabel(info.Model, "LockLabel")
		if lockLabel then
			if best == info.Id then
				lockLabel.Text = "⭐ Dein bestes Laufband!"
				lockLabel.TextColor3 = Color3.fromRGB(255, 220, 60)
			elseif lastSteps >= required then
				lockLabel.Text = "✅ Freigeschaltet"
				lockLabel.TextColor3 = Color3.fromRGB(120, 255, 120)
			else
				lockLabel.Text = "🔒 ab " .. Util.FormatNumber(required) .. " 👟"
				lockLabel.TextColor3 = Color3.fromRGB(255, 130, 130)
			end
		end
	end
end

function WorldFX.UpdateTreadmills(steps: number, best: string?)
	lastSteps = tonumber(steps) or 0
	lastBest = best
	updateSigns()
end

-- ---------------------------------------------------------------------
-- WIPPENDE ALIENS
-- ---------------------------------------------------------------------
type BobRecord = {
	Model: Model,
	Base: CFrame?,
	Last: CFrame?,
	Phase: number,
	Amp: number,
	Moved: boolean,
}

local bobRecords: { BobRecord } = {}
local bobSeen: { [Instance]: boolean } = {}

local function addBob(inst: Instance)
	if not inst:IsA("Model") or bobSeen[inst] or inst:GetAttribute("Bob") ~= true then
		return
	end
	bobSeen[inst] = true
	local top = tonumber(inst:GetAttribute("TopHeight"))
	table.insert(bobRecords, {
		Model = inst,
		Base = nil,
		Last = nil,
		Phase = math.random() * math.pi * 2,
		Amp = if top then math.clamp(top * 0.06, 0.15, 0.6) else 0.3,
		Moved = false,
	})
end

local function stepBob(now: number, camPos: Vector3)
	for i = #bobRecords, 1, -1 do
		local record = bobRecords[i]
		local model = record.Model
		if model.Parent == nil then
			bobSeen[model] = nil
			bobRecords[i] = bobRecords[#bobRecords]
			bobRecords[#bobRecords] = nil
		else
			local primary = model.PrimaryPart
			-- Getragene Aliens (nicht verankert, am Spieler) nie bewegen
			if primary and primary.Anchored and model:GetAttribute("Bob") == true then
				local current = model:GetPivot()
				local last = record.Last
				if record.Base == nil or (last and (current.Position - last.Position).Magnitude > 0.02) then
					-- Erstes Mal oder der Server hat das Alien verschoben -> neue Ruhe-Position
					record.Base = current
				end
				local base = record.Base :: CFrame
				if (base.Position - camPos).Magnitude <= BOB_RANGE then
					local wave = math.sin(now * 2.4 + record.Phase) * 0.5 + 0.5
					local target = base + Vector3.new(0, wave * record.Amp, 0)
					model:PivotTo(target)
					record.Last = target
					record.Moved = true
				elseif record.Moved then
					model:PivotTo(base)
					record.Last = base
					record.Moved = false
				else
					record.Last = current
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- REGENBOGEN (Teile + Highlights mit Attribut Rainbow)
-- ---------------------------------------------------------------------
type RainbowRecord = { Inst: Instance, Offset: number, IsPart: boolean }

local PALETTE_SIZE = 96
local palette: { Color3 } = {}
for i = 1, PALETTE_SIZE do
	palette[i] = Color3.fromHSV((i - 1) / PALETTE_SIZE, 0.85, 1)
end

local rainbowRecords: { RainbowRecord } = {}
local rainbowSeen: { [Instance]: boolean } = {}

addRainbow = function(inst: Instance)
	if rainbowSeen[inst] then
		return
	end
	if inst:IsA("BasePart") then
		rainbowSeen[inst] = true
		local pos = inst.Position
		table.insert(rainbowRecords, { Inst = inst, Offset = ((pos.X + pos.Z) * 0.008) % 1, IsPart = true })
	elseif inst:IsA("Highlight") then
		rainbowSeen[inst] = true
		table.insert(rainbowRecords, { Inst = inst, Offset = math.random(), IsPart = false })
	end
end

local function considerRainbow(inst: Instance)
	if inst:GetAttribute("Rainbow") == true then
		addRainbow(inst)
	end
end

local function stepRainbow(now: number, camPos: Vector3)
	local hue = (now * 0.22) % 1
	for i = #rainbowRecords, 1, -1 do
		local record = rainbowRecords[i]
		local inst = record.Inst
		if inst.Parent == nil then
			rainbowSeen[inst] = nil
			rainbowRecords[i] = rainbowRecords[#rainbowRecords]
			rainbowRecords[#rainbowRecords] = nil
		else
			local index = math.floor(((hue + record.Offset) % 1) * PALETTE_SIZE) + 1
			local color = palette[index] or palette[1]
			if record.IsPart then
				local part = inst :: BasePart
				if (part.Position - camPos).Magnitude < RAINBOW_RANGE then
					part.Color = color
				end
			else
				local highlight = inst :: Highlight
				highlight.FillColor = color
				highlight.OutlineColor = color
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- SCHLÜPF-COUNTDOWN an unschlüpften Meteoren in den Basen
-- ---------------------------------------------------------------------
type HatchRecord = { Part: BasePart, Label: TextLabel? }

local hatchRecords: { HatchRecord } = {}
local hatchSeen: { [Instance]: boolean } = {}

local function addHatchCandidate(inst: Instance)
	if not inst:IsA("BasePart") or hatchSeen[inst] then
		return
	end
	if inst:GetAttribute("HatchAt") == nil and inst.Name ~= "Meteor" then
		return
	end
	hatchSeen[inst] = true
	table.insert(hatchRecords, { Part = inst, Label = nil })
end

local function findValueLabel(part: BasePart): TextLabel?
	local info = part:FindFirstChild("Info")
	local frame = info and info:FindFirstChild("Frame")
	local labelObj = frame and frame:FindFirstChild("ValueLabel")
	if labelObj and labelObj:IsA("TextLabel") then
		return labelObj
	end
	return nil
end

local function stepHatch(now: number, camPos: Vector3)
	local Util = ctx.Util
	for i = #hatchRecords, 1, -1 do
		local record = hatchRecords[i]
		local part = record.Part
		if part.Parent == nil then
			hatchSeen[part] = nil
			hatchRecords[i] = hatchRecords[#hatchRecords]
			hatchRecords[#hatchRecords] = nil
		else
			local hatchAt = part:GetAttribute("HatchAt")
			if type(hatchAt) == "number" and (part.Position - camPos).Magnitude < HATCH_RANGE then
				local labelObj = record.Label
				if not labelObj or labelObj.Parent == nil then
					labelObj = findValueLabel(part)
					record.Label = labelObj
				end
				if labelObj then
					local left = hatchAt - now
					local text = if left > 0.5
						then "🐣 Schlüpft in " .. Util.FormatTime(math.ceil(left))
						else "🐣 Schlüpft..."
					if labelObj.Text ~= text then
						labelObj.Text = text
						labelObj.TextColor3 = HATCH_COLOR
					end
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- START
-- ---------------------------------------------------------------------
local function watchFolder(parent: Instance, name: string, onChild: (Instance) -> ())
	task.spawn(function()
		local folder = parent:WaitForChild(name, 60)
		if not folder then
			warn("[WorldFX] '" .. name .. "' nicht gefunden – Animation dafür aus")
			return
		end
		for _, child in ipairs(folder:GetChildren()) do
			onChild(child)
		end
		folder.ChildAdded:Connect(onChild)
	end)
end

function WorldFX.Init(context: any, map: Instance)
	ctx = context
	fxFolder = UI.Create("Folder", { Name = "MeteorHeistStripes", Parent = workspace })

	-- Hauptband (Streifen) + Meteore darauf
	task.spawn(function()
		local belt = map:WaitForChild("Belt", 60)
		if belt then
			setupMainBelt(belt)
		end
	end)
	watchFolder(map, "BeltMeteors", watchBeltMeteor)
	watchFolder(map, "Treadmills", setupTreadmill)

	-- Aliens, Regenbogen und Schlüpf-Meteore: einmal alles durchsehen, danach nur Neues
	for _, inst in ipairs(map:GetDescendants()) do
		addBob(inst)
		local parent = inst.Parent
		if parent and parent.Name ~= "BeltMeteors" and parent.Name ~= "GroundMeteors" then
			addHatchCandidate(inst)
		end
	end
	map.DescendantAdded:Connect(function(inst)
		addBob(inst)
		local parent = inst.Parent
		-- Meteore auf dem Band / am Boden schlüpfen nie -> gar nicht erst beobachten
		if parent and parent.Name ~= "BeltMeteors" and parent.Name ~= "GroundMeteors" then
			addHatchCandidate(inst)
		end
	end)
	-- Regenbogen auch an getragenen Aliens (die hängen am Charakter, nicht in der Map)
	for _, inst in ipairs(workspace:GetDescendants()) do
		considerRainbow(inst)
	end
	workspace.DescendantAdded:Connect(considerRainbow)

	local slowClock = 0
	local hatchClock = 0
	local animClock = 0 -- eigene Animations-Uhr (läuft mit dt, auch bei Rucklern gleichmäßig)
	RunService.RenderStepped:Connect(function(dt: number)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		frameNumber += 1
		local camPos = camera.CFrame.Position
		local now = workspace:GetServerTimeNow()

		table.clear(moveParts)
		table.clear(moveCFrames)
		local count = stepBelt(now, camPos, 0)
		count = stepStripes(now, camPos, count)
		if count > 0 then
			workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end

		animClock += dt
		slowClock += dt
		if slowClock >= SLOW_INTERVAL then
			slowClock = 0
			stepBob(animClock, camPos)
			stepRainbow(animClock, camPos)
		end
		hatchClock += dt
		if hatchClock >= HATCH_INTERVAL then
			hatchClock = 0
			stepHatch(now, camPos)
		end
	end)
end

return WorldFX
