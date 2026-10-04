-- =====================================================================
--  WELT-ANIMATIONEN (alles lokal auf deinem Gerät -> butterweich, kein Server-Lag)
--   • Alien-Parade (Eier + lokale Träger-Aliens): eigenes Modul "Parade", wird hier über
--     WorldFX.SetPreStep jedes Frame VOR den krassen Eiern aufgerufen (Ringe folgen dem Ei)
--   • Streifen auf den Treadmills laufen gleichmäßig durch und tauchen an den
--     Enden unter die Lauffläche (kein Aufploppen)
--   • Aliens leben: Atmen mit Squash & Stretch, kleine Hüpfer, Blinzeln, drehen sich zu Spielern
--   • Eier wackeln die letzten Sekunden immer stärker, Risse leuchten auf; frisch geschlüpfte
--     Aliens ploppen mit Overshoot herein
--   • Regenbogen-Teile färben sich durch
--   • Umrisse (Highlights): nur die nächsten paar sind an (Roblox zeigt max. 31, jeder kostet Leistung)
--   • Lava-Feuer an Parade-Eiern (Attribut "LavaFire"): nur die nächsten paar brennen
--   • Meteore in der Base zeigen "🐣 Schlüpft in m:ss"
--   • Laufband-Schilder zeigen, welche Laufbänder DU schon freigeschaltet hast
--   • Krasse Eier (Attribut "RareFX", ab Legendary): Ring dreht sich, Licht pulsiert, Partikel nur
--     in Kameranähe, ab Mythic Blitze (nur die nächsten MAX_RINGS)
--  Arbeit pro Frame ist begrenzt: höchstens MAX_ANIM Aliens in ANIM_RANGE Studs werden animiert
--  (jedes ca. 30x pro Sekunde), weit entfernte Dinge werden seltener oder gar nicht bewegt.
-- =====================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local UI = require(script.Parent:WaitForChild("UI"))

local WorldFX = {}

local ctx: any = nil
local fxFolder: Folder? = nil

local BEHIND_FRAME_SKIP = 8 -- außerhalb des Sichtfelds (nicht zu sehen): nur jedes 8. Frame
local CLOSE_DISTANCE = 40 -- so nah immer jedes Frame (auch knapp hinter/neben der Kamera sichtbar)
local VIEW_MARGIN = math.rad(12) -- Sichtfeld etwas größer rechnen (große Eier/Träger am Bildrand)
local STRIPE_RANGE = 320 -- Streifen auf Treadmills nur in der Nähe bewegen
local STRIPE_SINK = 0.14 -- so tief tauchen die Streifen an den Enden unter die Lauffläche
local SLOW_INTERVAL = 1 / 30 -- Alien-Animation + Regenbogen höchstens 30x pro Sekunde
local SCAN_INTERVAL = 0.5 -- so oft wird neu gewählt, welche Aliens leben / welche Umrisse an sind
local CLEANUP_INTERVAL = 1 -- so oft fliegen zerstörte Objekte aus den Listen
local MAX_HIGHLIGHTS = 12 -- so viele Umrisse höchstens gleichzeitig (die nächsten)
local HIGHLIGHT_RANGE = 150
local MAX_LAVA_FIRES = 6 -- so viele Lava-Feuer in der Parade brennen höchstens gleichzeitig (die nächsten)
local LAVA_FIRE_RANGE = 60
local HATCH_INTERVAL = 0.2 -- Schlüpf-Countdown 5x pro Sekunde
local HATCH_RANGE = 170
local RAINBOW_RANGE = 400

-- Aliens
local ANIM_RANGE = 120 -- nur Aliens in Kameranähe animieren
local MAX_ANIM = 60 -- höchstens so viele (die nächsten) gleichzeitig
local MAX_SQUASH = 20 -- so viele (die nächsten) werden zusätzlich gestaucht/gestreckt
local SQUASH_RANGE = 70
local LOOK_RANGE = 35 -- Spieler so nah -> Alien dreht sich zu ihm
local MAX_TURN = math.rad(65) -- höchstens so weit aus der Ruhe-Richtung drehen
local TURN_SPEED = 3.5 -- wie schnell es sich dreht (1/s)
local HOP_TIME = 0.62 -- Dauer eines Hüpfers
local HOP_MIN = 3 -- Pause zwischen zwei Hüpfern: HOP_MIN + 0..HOP_RANGE Sekunden
local HOP_RANGE = 6
local BLINK_TIME = 0.14

-- Schlüpfen
local WOBBLE_TIME = 3 -- so viele Sekunden vor dem Schlüpfen wackelt das Ei
local WOBBLE_GRACE = 4 -- so lange nach HatchAt weiterwackeln (bis der Server schlüpfen lässt)
local MAX_WOBBLE = 8 -- höchstens so viele Eier wackeln gleichzeitig
local CRACKS_PER_EGG = 3
local EGG_DUE_WINDOW = 2.5 -- Ei verschwindet so kurz vor/nach HatchAt -> zählt als geschlüpft
local POP_TIME = 0.5 -- Dauer des Reinploppens
local POP_DELAY = 0.06 -- kurz klein bleiben (Lichtblitz)
local POP_OVERSHOOT = 2.4 -- wie weit es über die Endgröße hinaus federt
local POP_MIN = 0.02
local POP_MATCH_DISTANCE = 6 -- Ei/Effekt und neues Alien höchstens so weit auseinander
local RECENT_TIME = 1.5 -- so lange werden neue Aliens / verschwundene Eier gemerkt

local HATCH_COLOR = Color3.fromRGB(255, 225, 120)

-- Wiederverwendete Listen für workspace:BulkMoveTo (keine neuen Tabellen pro Frame)
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}
local frameNumber = 0

-- Parade (eigenes Modul): wird jedes Frame vor den krassen Eiern aufgerufen
type PreStep = (now: number, dt: number, camPos: Vector3, look: Vector3, cosLimit: number, frame: number) -> ()
local preStep: PreStep? = nil

function WorldFX.SetPreStep(fn: PreStep?)
	preStep = fn
end

-- Kosinus des halben Sichtfelds (Bild-Diagonale + Rand): rel:Dot(look) < Abstand * viewCos = nicht im Bild
local function viewCos(camera: Camera): number
	local size = camera.ViewportSize
	local aspect = if size.Y > 0 then size.X / size.Y else 16 / 9
	local halfVertical = math.rad(camera.FieldOfView) / 2
	local halfDiagonal = math.atan(math.tan(halfVertical) * math.sqrt(1 + aspect * aspect))
	return math.cos(math.min(halfDiagonal + VIEW_MARGIN, math.pi / 2))
end

-- ---------------------------------------------------------------------
-- STREIFEN (lokale Teile, die über die Treadmills laufen)
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
	colors: { normal: Color3, accent: Color3, rainbow: boolean, accentEvery: number }
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

local function stepStripes(now: number, camPos: Vector3, look: Vector3, cosLimit: number, count: number): number
	for _, set in ipairs(stripeSets) do
		if (set.Center - camPos).Magnitude < STRIPE_RANGE then
			local rot = set.Rot
			local r00, r01, r02, r10, r11, r12, r20, r21, r22 =
				rot[1], rot[2], rot[3], rot[4], rot[5], rot[6], rot[7], rot[8], rot[9]
			local shift = (now * set.Speed) % set.Length
			-- Hochachse der Streifen (2. Spalte der Drehmatrix): an den Enden darunter wegtauchen,
			-- statt am Ende zu verschwinden und am Anfang aufzuploppen
			local up = Vector3.new(r01, r11, r21)
			local length, edge = set.Length, set.Spacing * 0.6
			for i, stripe in ipairs(set.Parts) do
				local s = ((i - 0.5) * set.Spacing + shift) % length
				local pos = set.Origin + set.Dir * s
				local toEnd = math.min(s, length - s)
				if toEnd < edge then
					local k = 1 - toEnd / edge
					pos -= up * (k * k * STRIPE_SINK)
				end
				local rel = pos - camPos
				local distance = rel.Magnitude
				local due = true
				if distance >= CLOSE_DISTANCE and rel:Dot(look) < distance * cosLimit then
					due = (frameNumber + i) % BEHIND_FRAME_SKIP == 0 -- nicht im Bild
				end
				if due then
					count += 1
					moveParts[count] = stripe
					moveCFrames[count] = CFrame.new(pos.X, pos.Y, pos.Z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
				end
			end
		end
	end
	return count
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
	})
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
-- LEBENDIGE ALIENS (Idle-Animation, alles lokal)
--  • Atmen mit Squash & Stretch (Body wird lokal gestaucht/gestreckt, Volumen bleibt gleich)
--  • ab und zu ein kleiner Hüpfer: Anlauf (stauchen) -> Sprung (strecken) -> Landung (federn)
--  • Augen blinzeln (Teile mit Attribut "Eye" sinken kurz in den Kopf)
--  • drehen sich sanft zum nächsten Spieler in der Nähe (Ziel nur alle SCAN_INTERVAL s neu)
--  • Geister/Kristalle schweben statt zu hüpfen, Roboter hüpfen steif (ohne Stauchen)
-- Pro Alien werden die Teile + ihre Lage zum Ruhe-Pivot EINMAL gemerkt (Position + Drehmatrix als
-- Zahlen). Jedes Frame kommt nur ein Teil der Aliens dran (jedes ca. 30x pro Sekunde), alle Teile
-- werden mit EINEM workspace:BulkMoveTo bewegt – pro Teil entsteht genau ein neues CFrame.
-- ---------------------------------------------------------------------
type AnimRecord = {
	Model: Model,
	Primary: BasePart?,
	PrimaryIndex: number,
	Base: CFrame?, -- Ruhe-Pivot (wie vom Server gesetzt)
	Parts: { BasePart },
	Pos: { Vector3 }, -- Teil-Position relativ zum Ruhe-Pivot
	Rot: { number }, -- Teil-Drehung relativ zum Ruhe-Pivot (9 Zahlen je Teil)
	EyeIn: { Vector3 }, -- Augen: Richtung + Weg ins Gesicht beim Blinzeln (sonst 0)
	HasEyes: boolean,
	LastPrimary: CFrame?, -- zuletzt von uns gesetzte Lage des PrimaryPart
	Rev: any, -- Attribut "Rev" (ändert der Server nach dem Wachsen)
	BodySize: Vector3?, -- echte Body-Größe (Attribut "BaseSize" vom Server)
	CanSquash: boolean,
	Style: string, -- "Hop" | "Float" | "Stiff"
	Phase: number,
	Height: number,
	HopHeight: number,
	Slot: number,
	Dist: number,
	Moved: boolean,
	Squash: boolean, -- darf gerade gestaucht werden (nur die nächsten MAX_SQUASH)
	Resized: boolean, -- Body-Größe gerade lokal verändert
	SetSize: Vector3?, -- zuletzt von uns gesetzte Body-Größe (anders = der Server hat sie geändert)
	Yaw: number,
	YawTarget: number,
	HopAt: number,
	HopStart: number,
	BlinkAt: number,
	BlinkStart: number,
	Last: number,
}

local ANIM_STYLES: { [string]: string } = { Ghost = "Float", Crystal = "Float", Robot = "Stiff" }
local NO_SQUASH: { [string]: boolean } = { Crystal = true, Robot = true }
local EYE_NAMES: { [string]: boolean } = { Eye = true, Pupil = true, Iris = true }

local animRecords: { AnimRecord } = {}
local animSeen: { [Instance]: AnimRecord } = {}
local animCandidates: { AnimRecord } = {} -- wiederverwendet (keine neuen Tabellen pro Durchlauf)
local activeAnims: { AnimRecord } = {}
local animParts: { BasePart } = {}
local animCFrames: { CFrame } = {}
local resetParts: { BasePart } = {}
local resetCFrames: { CFrame } = {}
local playerRoots: { Vector3 } = {}
local popping: { [Instance]: boolean } = {} -- Aliens, die gerade "reinploppen" (nicht wippen)

local function addAnim(inst: Instance): AnimRecord?
	if not inst:IsA("Model") or inst:GetAttribute("Bob") ~= true then
		return nil
	end
	local existing = animSeen[inst]
	if existing then
		return existing
	end
	local top = tonumber(inst:GetAttribute("TopHeight")) or 3
	local archetype = inst:GetAttribute("Archetype")
	local style = if type(archetype) == "string" then ANIM_STYLES[archetype] or "Hop" else "Hop"
	local record: AnimRecord = {
		Model = inst,
		Primary = nil,
		PrimaryIndex = 0,
		Base = nil,
		Parts = {},
		Pos = {},
		Rot = {},
		EyeIn = {},
		HasEyes = false,
		LastPrimary = nil,
		Rev = nil,
		BodySize = nil,
		CanSquash = not (type(archetype) == "string" and NO_SQUASH[archetype] == true),
		Style = style,
		Phase = math.random() * math.pi * 2,
		Height = top,
		HopHeight = math.clamp(top * (if style == "Stiff" then 0.06 else 0.12), 0.25, 1.1),
		Slot = math.random(0, 7),
		Dist = math.huge,
		Moved = false,
		Squash = false,
		Resized = false,
		SetSize = nil,
		Yaw = 0,
		YawTarget = 0,
		HopAt = 0,
		HopStart = -1,
		BlinkAt = 0,
		BlinkStart = -1,
		Last = 0,
	}
	animSeen[inst] = record
	table.insert(animRecords, record)
	return record
end

-- Stammt die aktuelle Body-Größe noch von uns (Stauchen)? Hat der Server sie inzwischen geändert
-- (Level-Up: AlienFactory.Refresh skaliert das Model), gilt seine Größe – nie mit einer alten überschreiben.
local function ownsBodySize(record: AnimRecord, primary: BasePart): boolean
	local setSize = record.SetSize
	return record.Resized and setSize ~= nil and (primary.Size - setSize).Magnitude < 1e-3
end

-- Echte Body-Größe: nicht gestaucht = die aktuelle (vom Server), gestaucht = die gemerkte bzw. das
-- Attribut "BaseSize" vom Server
local function realBodySize(record: AnimRecord, primary: BasePart): Vector3?
	if not ownsBodySize(record, primary) then
		return primary.Size
	end
	local size = primary:GetAttribute("BaseSize")
	if typeof(size) == "Vector3" then
		return size
	end
	return record.BodySize
end

-- Body zurück auf seine echte Größe (nur, wenn wir ihn gestaucht haben und der Server nichts geändert hat)
local function restoreBodySize(record: AnimRecord)
	local primary, bodySize = record.Primary, record.BodySize
	if primary and bodySize and primary.Parent and ownsBodySize(record, primary) then
		primary.Size = bodySize
	end
	record.Resized = false
	record.SetSize = nil
end

-- Ruhe-Lage neu merken (erstes Mal, oder der Server hat das Alien verschoben/vergrößert)
local function rebaseAnim(record: AnimRecord): boolean
	local model = record.Model
	local primary = model.PrimaryPart
	if not primary then
		return false
	end
	-- Body zuerst auf seine echte Größe (falls wir ihn gerade gestaucht hatten)
	local bodySize = realBodySize(record, primary)
	if bodySize and ownsBodySize(record, primary) then
		primary.Size = bodySize
	end
	record.Resized = false
	record.SetSize = nil
	record.BodySize = bodySize
	local base = model:GetPivot()
	local inverse = base:Inverse()
	table.clear(record.Parts)
	table.clear(record.Pos)
	table.clear(record.Rot)
	table.clear(record.EyeIn)
	record.PrimaryIndex = 0
	record.HasEyes = false
	local rot = record.Rot
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local rel = inverse * d.CFrame
			local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = rel:GetComponents()
			table.insert(record.Parts, d)
			table.insert(record.Pos, rel.Position)
			local k = #rot
			rot[k + 1], rot[k + 2], rot[k + 3] = r00, r01, r02
			rot[k + 4], rot[k + 5], rot[k + 6] = r10, r11, r12
			rot[k + 7], rot[k + 8], rot[k + 9] = r20, r21, r22
			local eyeIn = Vector3.zero
			if d:GetAttribute("Eye") == true or EYE_NAMES[d.Name] then
				-- lokale +Z-Achse des Auges = nach innen (Augen schauen nach -Z)
				local depth = math.max(d.Size.X, d.Size.Y) * 0.6
				eyeIn = Vector3.new(r02, r12, r22) * depth
				record.HasEyes = true
			end
			table.insert(record.EyeIn, eyeIn)
			if d == primary then
				record.PrimaryIndex = #record.Parts
			end
		end
	end
	-- Stauchen nur bei aufrechtem Body, der kein Ball ist (Bälle lassen sich nicht verzerren)
	local relPrimary = inverse * primary.CFrame
	local upright = relPrimary.UpVector.Y > 0.995
	local isBall = primary:IsA("Part") and primary.Shape == Enum.PartType.Ball
	if not upright or isBall or bodySize == nil then
		record.CanSquash = false
	end
	record.Primary = primary
	record.Base = base
	record.LastPrimary = primary.CFrame
	record.Rev = model:GetAttribute("Rev")
	record.Moved = false
	return record.PrimaryIndex > 0
end

-- Pose eines Aliens in die Listen eintragen (Gibt die neue Anzahl zurück).
-- yaw = Drehung um die Hochachse, lift = Anheben, sy = Stauchung (1 = normal), blink = 0..1
local function poseAnim(
	record: AnimRecord,
	base: CFrame,
	yaw: number,
	lift: number,
	sy: number,
	blink: number,
	parts: { BasePart },
	cframes: { CFrame },
	count: number
): number
	local px, py, pz, b00, b01, b02, b10, b11, b12, b20, b21, b22 = base:GetComponents()
	local c, s = math.cos(yaw), math.sin(yaw)
	-- M = Basis-Drehung * Drehung um Y (Spalten 0 und 2 ändern sich, Spalte 1 bleibt)
	local m00, m10, m20 = b00 * c - b02 * s, b10 * c - b12 * s, b20 * c - b22 * s
	local m01, m11, m21 = b01, b11, b21
	local m02, m12, m22 = b00 * s + b02 * c, b10 * s + b12 * c, b20 * s + b22 * c
	local sx = 1 / math.sqrt(sy)
	local pos, rot, eyeIn = record.Pos, record.Rot, record.EyeIn
	local primaryIndex = record.PrimaryIndex
	for i, part in ipairs(record.Parts) do
		local p = pos[i]
		local vx, vy, vz = p.X * sx, p.Y * sy + lift, p.Z * sx
		if blink > 0 then
			local e = eyeIn[i]
			vx += e.X * blink
			vy += e.Y * blink
			vz += e.Z * blink
		end
		local k = (i - 1) * 9
		local r00, r01, r02 = rot[k + 1], rot[k + 2], rot[k + 3]
		local r10, r11, r12 = rot[k + 4], rot[k + 5], rot[k + 6]
		local r20, r21, r22 = rot[k + 7], rot[k + 8], rot[k + 9]
		local cf = CFrame.new(
			px + m00 * vx + m01 * vy + m02 * vz,
			py + m10 * vx + m11 * vy + m12 * vz,
			pz + m20 * vx + m21 * vy + m22 * vz,
			m00 * r00 + m01 * r10 + m02 * r20,
			m00 * r01 + m01 * r11 + m02 * r21,
			m00 * r02 + m01 * r12 + m02 * r22,
			m10 * r00 + m11 * r10 + m12 * r20,
			m10 * r01 + m11 * r11 + m12 * r21,
			m10 * r02 + m11 * r12 + m12 * r22,
			m20 * r00 + m21 * r10 + m22 * r20,
			m20 * r01 + m21 * r11 + m22 * r21,
			m20 * r02 + m21 * r12 + m22 * r22
		)
		count += 1
		parts[count] = part
		cframes[count] = cf
		if i == primaryIndex then
			record.LastPrimary = cf
		end
	end
	return count
end

-- Einmal zurück auf die Ruhe-Lage (z.B. zu weit weg): Teile exakt an ihren Platz, Body-Größe zurück
local function resetAnim(record: AnimRecord)
	local base = record.Base
	local primary = record.Primary
	restoreBodySize(record)
	if base and primary and record.Moved and primary:IsDescendantOf(workspace) and not popping[record.Model] then
		table.clear(resetParts)
		table.clear(resetCFrames)
		local count = poseAnim(record, base, 0, 0, 1, 0, resetParts, resetCFrames, 0)
		if count > 0 then
			workspace:BulkMoveTo(resetParts, resetCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end
	record.Moved = false
	record.Yaw = 0
	record.HopStart = -1
	record.BlinkStart = -1
end

local function byDistance(a: AnimRecord, b: AnimRecord): boolean
	return a.Dist < b.Dist
end

-- Positionen aller Spieler-Charaktere (für "zum Spieler drehen"), nur alle SCAN_INTERVAL s
local function gatherPlayerRoots()
	table.clear(playerRoots)
	for _, plr in ipairs(Players:GetPlayers()) do
		local character = plr.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			table.insert(playerRoots, root.Position)
		end
	end
end

-- Blickrichtung: zum nächsten Spieler in LOOK_RANGE (begrenzt), sonst ab und zu umschauen
local function chooseYaw(record: AnimRecord, base: CFrame)
	local basePos = base.Position
	local best = LOOK_RANGE
	local target: Vector3? = nil
	for _, rootPos in ipairs(playerRoots) do
		local d = (rootPos - basePos).Magnitude
		if d < best and d > 1 then
			best = d
			target = rootPos
		end
	end
	if target then
		local rel = base:PointToObjectSpace(target)
		record.YawTarget = math.clamp(math.atan2(-rel.X, -rel.Z), -MAX_TURN, MAX_TURN)
	elseif math.random() < 0.12 then
		record.YawTarget = (math.random() - 0.5) * 0.7
	end
end

-- Alle SCAN_INTERVAL Sekunden: die nächsten MAX_ANIM Aliens in Reichweite animieren
local function scanAnim(camPos: Vector3)
	gatherPlayerRoots()
	local count = 0
	for i = #animRecords, 1, -1 do
		local record = animRecords[i]
		local model = record.Model
		if model.Parent == nil or not model:IsDescendantOf(workspace) then
			-- zerstört (auch wenn nur der Ordner darüber weg ist, z.B. Foto-Deko)
			animSeen[model] = nil
			popping[model] = nil
			animRecords[i] = animRecords[#animRecords]
			animRecords[#animRecords] = nil
		else
			local pivot = record.Base or model:GetPivot()
			record.Dist = (pivot.Position - camPos).Magnitude
			if record.Dist <= ANIM_RANGE then
				count += 1
				animCandidates[count] = record
			else
				resetAnim(record)
			end
		end
	end
	for i = #animCandidates, count + 1, -1 do
		animCandidates[i] = nil
	end
	table.sort(animCandidates, byDistance)
	for i = MAX_ANIM + 1, count do
		resetAnim(animCandidates[i])
	end
	table.clear(activeAnims)
	for i = 1, math.min(count, MAX_ANIM) do
		local record = animCandidates[i]
		activeAnims[i] = record
		local squash = i <= MAX_SQUASH and record.Dist <= SQUASH_RANGE
		if not squash and record.Resized then
			restoreBodySize(record)
		end
		record.Squash = squash
		local base = record.Base
		if base then
			chooseYaw(record, base)
		end
	end
end

-- Hüpfer: u = 0..1 -> (Anheben, Stauchung)
local function hopShape(u: number, height: number): (number, number)
	if u < 0.18 then -- Anlauf: in die Knie gehen
		local k = u / 0.18
		return 0, 1 - 0.17 * math.sin(k * math.pi * 0.5)
	elseif u < 0.7 then -- Flug: gestreckt hoch, leicht gestaucht runter
		local k = (u - 0.18) / 0.52
		return height * 4 * k * (1 - k), 1 + 0.13 * (1 - 2 * k)
	end
	-- Landung: federt gedämpft aus
	local k = (u - 0.7) / 0.3
	return 0, 1 - 0.15 * (1 - k) * math.cos(k * math.pi * 2.5)
end

local function animateRecord(record: AnimRecord, base: CFrame, now: number, count: number): number
	local dt = math.clamp(now - record.Last, 0, 0.25)
	record.Last = now
	record.Yaw += (record.YawTarget - record.Yaw) * (1 - math.exp(-dt * TURN_SPEED))
	local t = now + record.Phase
	local lift, sy = 0, 1
	if record.Style == "Float" then
		lift = record.Height * 0.07 * (0.5 + 0.5 * math.sin(t * 1.7))
		sy = 1 + 0.03 * math.sin(t * 1.7 + 1.2)
	else
		sy = 1 + 0.035 * math.sin(t * 2.3)
		if record.HopStart >= 0 then
			local u = (now - record.HopStart) / HOP_TIME
			if u >= 1 then
				record.HopStart = -1
				record.HopAt = now + HOP_MIN + math.random() * HOP_RANGE
			else
				local hopLift, hopSquash = hopShape(u, record.HopHeight)
				lift = hopLift
				sy *= hopSquash
			end
		elseif record.HopAt == 0 then
			record.HopAt = now + math.random() * HOP_RANGE
		elseif now >= record.HopAt then
			record.HopStart = now
		end
	end
	local squash = record.Squash and record.CanSquash
	if not squash then
		sy = 1
	end
	local blink = 0
	if record.HasEyes then
		if record.BlinkStart >= 0 then
			local u = (now - record.BlinkStart) / BLINK_TIME
			if u >= 1 then
				record.BlinkStart = -1
				-- manchmal doppelt blinzeln
				record.BlinkAt = now + (if math.random() < 0.2 then 0.12 else 1.8 + math.random() * 3.5)
			else
				blink = math.sin(u * math.pi)
			end
		elseif record.BlinkAt == 0 then
			record.BlinkAt = now + math.random() * 4
		elseif now >= record.BlinkAt then
			record.BlinkStart = now
		end
	end
	local primary = record.Primary
	local bodySize = record.BodySize
	if squash and primary and bodySize then
		local sx = 1 / math.sqrt(sy)
		local size = Vector3.new(bodySize.X * sx, bodySize.Y * sy, bodySize.Z * sx)
		primary.Size = size
		record.Resized = true
		record.SetSize = primary.Size -- so, wie Roblox den Wert speichert (für den Vergleich)
	end
	record.Moved = true
	return poseAnim(record, base, record.Yaw, lift, sy, blink, animParts, animCFrames, count)
end

-- stride = jedes wievielte Frame ein Alien drankommt (60 FPS -> 2 = 30x pro Sekunde)
local function stepAnim(now: number, stride: number): number
	local count = 0
	for _, record in ipairs(activeAnims) do
		local model = record.Model
		if (frameNumber + record.Slot) % stride == 0 and not popping[model] then
			local primary = model.PrimaryPart
			-- Getragene Aliens (nicht verankert, am Spieler) nie bewegen; gelöschte (auch wenn nur der
			-- Ordner darüber weg ist) ebenfalls nicht – die fliegen beim nächsten scanAnim raus
			if
				primary
				and primary.Anchored
				and model:GetAttribute("Bob") == true
				and primary:IsDescendantOf(workspace)
			then
				local last = record.LastPrimary
				local ready = record.Base ~= nil and record.Primary == primary
				if
					not ready
					or not last
					or (primary.Position - last.Position).Magnitude > 0.02
					or model:GetAttribute("Rev") ~= record.Rev
					or (record.Resized and not ownsBodySize(record, primary)) -- Server hat die Größe geändert
				then
					ready = rebaseAnim(record)
					local newBase = record.Base
					if ready and newBase then
						chooseYaw(record, newBase)
					end
				end
				local base = record.Base
				if ready and base then
					count = animateRecord(record, base, now, count)
				end
			end
		end
	end
	return count
end

-- ---------------------------------------------------------------------
-- SCHLÜPFEN: Alien "ploppt" mit Overshoot rein (Model:ScaleTo lokal, danach exakt zurück)
-- Erkannt wird ein Schlüpfen, wenn ein neues Alien dort auftaucht, wo gerade ein fälliges Ei
-- verschwunden ist – oder wenn der Server-Effekt "Hatch" in der Nähe eines neuen Aliens kommt.
-- ---------------------------------------------------------------------
type PopRecord = { Model: Model, Start: number, Scale: number }
type RecentAlien = { Model: Model, Time: number, Pos: Vector3? }
type RecentEgg = { Pos: Vector3, Time: number }

local pops: { PopRecord } = {}
local recentAliens: { RecentAlien } = {} -- neu aufgetauchte Aliens (kurz gemerkt)
local recentEggs: { RecentEgg } = {} -- gerade verschwundene, fällige Eier (kurz gemerkt)
local animClockNow = 0 -- aktuelle Animations-Uhr (für Ereignisse außerhalb der Frame-Schleife)

local function backOut(t: number): number
	local s = POP_OVERSHOOT
	local u = t - 1
	return 1 + (s + 1) * u * u * u + s * u * u
end

local function startPop(model: Model)
	if popping[model] or not model.PrimaryPart then
		return
	end
	local ok, scale = pcall(model.GetScale, model)
	if not ok or type(scale) ~= "number" or scale <= 0 then
		return
	end
	local record = animSeen[model]
	if record then
		resetAnim(record)
		record.Base = nil -- nach dem Ploppen neu einmessen
	end
	popping[model] = true
	pcall(model.ScaleTo, model, scale * POP_MIN)
	table.insert(pops, { Model = model, Start = animClockNow, Scale = scale })
end

local function stepPops(now: number)
	for i = #pops, 1, -1 do
		local pop = pops[i]
		local model = pop.Model
		local u = (now - pop.Start - POP_DELAY) / POP_TIME
		local alive = model.Parent ~= nil and model.PrimaryPart ~= nil
		if not alive or u >= 1 then
			if alive then
				pcall(model.ScaleTo, model, pop.Scale)
			end
			popping[model] = nil
			pops[i] = pops[#pops]
			pops[#pops] = nil
		elseif u > 0 then
			pcall(model.ScaleTo, model, pop.Scale * math.max(POP_MIN, backOut(u)))
		end
	end
end

local function flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
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
				if highlight.Enabled then -- ausgeschaltete Umrisse nicht umfärben
					highlight.FillColor = color
					highlight.OutlineColor = color
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- NUR DIE NÄCHSTEN EINSCHALTEN: Umrisse (Highlights, Roblox zeigt max. 31) und Lava-Feuer an
-- Parade-Eiern (sonst brennen bei Glück-Events Dutzende gleichzeitig).
-- Der Server legt beide ausgeschaltet an; hier werden alle SCAN_INTERVAL Sekunden die nächsten
-- "Max" in Reichweite eingeschaltet, alle anderen aus.
-- ---------------------------------------------------------------------
type NearestSet = {
	Items: { Instance },
	Seen: { [Instance]: boolean },
	Candidates: { Instance },
	Dist: { [Instance]: number },
	Max: number,
	Range: number,
	ByDistance: (a: Instance, b: Instance) -> boolean,
}

local function newNearestSet(maxOn: number, range: number): NearestSet
	local dist: { [Instance]: number } = {}
	return {
		Items = {},
		Seen = {},
		Candidates = {},
		Dist = dist,
		Max = maxOn,
		Range = range,
		ByDistance = function(a: Instance, b: Instance): boolean
			return (dist[a] or math.huge) < (dist[b] or math.huge)
		end,
	}
end

local highlightSet = newNearestSet(MAX_HIGHLIGHTS, HIGHLIGHT_RANGE)
local lavaSet = newNearestSet(MAX_LAVA_FIRES, LAVA_FIRE_RANGE)

-- Highlight oder Fire (beide haben "Enabled")
local function setOn(inst: Instance, on: boolean)
	local item = inst :: any
	if item.Enabled ~= on then
		item.Enabled = on
	end
end

local function nearestAdd(set: NearestSet, inst: Instance)
	if not set.Seen[inst] then
		set.Seen[inst] = true
		setOn(inst, false) -- bis zum nächsten Durchlauf aus
		table.insert(set.Items, inst)
	end
end

local function addHighlight(inst: Instance)
	if inst:IsA("Highlight") then
		nearestAdd(highlightSet, inst)
	elseif inst:IsA("Fire") and inst:GetAttribute("LavaFire") == true then
		nearestAdd(lavaSet, inst)
	end
end

-- Highlight: sein Adornee (oder Parent); Feuer: sein Meteor
local function effectPosition(inst: Instance): Vector3?
	local target = inst.Parent
	if inst:IsA("Highlight") and inst.Adornee then
		target = inst.Adornee
	end
	if target and target:IsA("BasePart") then
		return target.Position
	elseif target and target:IsA("Model") then
		return target:GetPivot().Position
	end
	return nil
end

local function scanNearest(set: NearestSet, camPos: Vector3)
	local items, candidates, dist = set.Items, set.Candidates, set.Dist
	table.clear(dist)
	local count = 0
	for i = #items, 1, -1 do
		local inst = items[i]
		if inst.Parent == nil or not inst:IsDescendantOf(workspace) then
			set.Seen[inst] = nil
			items[i] = items[#items]
			items[#items] = nil
		else
			local pos = effectPosition(inst)
			local d = if pos then (pos - camPos).Magnitude else math.huge
			if d <= set.Range then
				count += 1
				candidates[count] = inst
				dist[inst] = d
			else
				setOn(inst, false)
			end
		end
	end
	for i = #candidates, count + 1, -1 do
		candidates[i] = nil
	end
	if count > set.Max then
		table.sort(candidates, set.ByDistance)
	end
	for i = 1, count do
		setOn(candidates[i], i <= set.Max)
	end
end

local function scanHighlights(camPos: Vector3)
	scanNearest(highlightSet, camPos)
	scanNearest(lavaSet, camPos)
end

-- ---------------------------------------------------------------------
-- SCHLÜPF-COUNTDOWN an unschlüpften Meteoren in den Basen
-- + die letzten WOBBLE_TIME Sekunden: Ei wackelt immer stärker, leuchtende Risse brechen auf
--   (alles lokal anhand von HatchAt; die Risse sind lokale Neon-Teilchen, die mitwackeln)
-- ---------------------------------------------------------------------
type HatchRecord = {
	Part: BasePart,
	Label: TextLabel?,
	HatchAt: number?,
	Wobble: boolean,
	BaseCF: CFrame?, -- Lage vom Server
	LastCF: CFrame?, -- zuletzt von uns gesetzt
	Cracks: { BasePart },
	CrackOffsets: { CFrame },
	Light: PointLight?,
	Progress: number, -- 0..1 (wie weit das Schlüpfen ist)
}

local hatchRecords: { HatchRecord } = {}
local hatchSeen: { [Instance]: boolean } = {}
local wobbling: { HatchRecord } = {}

local function addHatchCandidate(inst: Instance)
	if not inst:IsA("BasePart") or hatchSeen[inst] then
		return
	end
	if inst:GetAttribute("HatchAt") == nil and inst.Name ~= "Meteor" then
		return
	end
	hatchSeen[inst] = true
	table.insert(hatchRecords, {
		Part = inst,
		Label = nil,
		HatchAt = nil,
		Wobble = false,
		BaseCF = nil,
		LastCF = nil,
		Cracks = {},
		CrackOffsets = {},
		Light = nil,
		Progress = 0,
	})
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

-- Farbe der Risse: Seltenheits-Farbe des Eis, aufgehellt
local function crackColor(part: BasePart): Color3
	local rarityName = part:GetAttribute("Rarity")
	local rarities = ctx and ctx.Config.RaritiesByName
	local rarity = rarities and type(rarityName) == "string" and rarities[rarityName]
	local color: Color3 = if rarity and typeof(rarity.Color) == "Color3" then rarity.Color else HATCH_COLOR
	return color:Lerp(Color3.new(1, 1, 1), 0.35)
end

-- Ei fängt an zu wackeln: Risse anlegen (3 Zickzack-Risse aus je 2 Stücken) + Licht im Inneren
local function startWobble(record: HatchRecord)
	local folder = fxFolder
	local part = record.Part
	if not folder then
		return
	end
	record.Wobble = true
	local base = part.CFrame
	record.BaseCF = base
	record.LastCF = base
	local radius = part.Size.Y / 2
	local color = crackColor(part)
	local width = math.clamp(radius * 0.09, 0.06, 0.3)
	for _ = 1, CRACKS_PER_EGG do
		-- zufällige Stelle in der oberen 3/4-Kugel, Riss liegt tangential auf der Schale
		local dir = Vector3.new(math.random() - 0.5, math.random() * 0.9 - 0.25, math.random() - 0.5)
		dir = if dir.Magnitude > 0.05 then dir.Unit else Vector3.yAxis
		local surface = CFrame.lookAt(dir * radius * 0.97, dir * (radius + 1))
			* CFrame.Angles(0, 0, math.random() * math.pi * 2)
		local length = radius * (0.35 + math.random() * 0.3)
		for segment = 0, 1 do
			local bend = if segment == 0 then 0.5 else -0.6
			local offset = surface * CFrame.new(0, length * (segment - 0.5) * 0.9, 0) * CFrame.Angles(0, 0, bend)
			local crack = UI.Create("Part", {
				Name = "EggCrack",
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Material = Enum.Material.Neon,
				Color = color,
				Transparency = 1,
				Size = Vector3.new(width, length * 0.6, width * 0.6),
				CFrame = base * offset,
				Parent = folder,
			})
			table.insert(record.Cracks, crack)
			table.insert(record.CrackOffsets, offset)
		end
	end
	local first = record.Cracks[1]
	if first then
		record.Light = UI.Create("PointLight", {
			Color = color,
			Brightness = 0,
			Range = math.clamp(radius * 5, 6, 20),
			Shadows = false,
			Parent = first,
		})
	end
end

-- Wackeln aus: Risse weg, Ei (falls noch da und nicht vom Server bewegt) zurück an seinen Platz
local function stopWobble(record: HatchRecord)
	record.Wobble = false
	for _, crack in ipairs(record.Cracks) do
		crack:Destroy()
	end
	table.clear(record.Cracks)
	table.clear(record.CrackOffsets)
	record.Light = nil
	local part = record.Part
	local base, last = record.BaseCF, record.LastCF
	if base and last and part.Parent and (part.Position - last.Position).Magnitude < 0.01 then
		part.CFrame = base
	end
	record.BaseCF = nil
	record.LastCF = nil
end

-- Ei ist verschwunden: war es fällig, kurz merken (das neue Alien an dieser Stelle ploppt dann rein)
local function eggGone(record: HatchRecord, now: number)
	local hatchAt = record.HatchAt
	if hatchAt and hatchAt - now < EGG_DUE_WINDOW then
		table.insert(recentEggs, { Pos = record.Part.Position, Time = animClockNow })
	end
	if record.Wobble then
		stopWobble(record)
	end
end

local function removeHatchRecord(i: number, now: number)
	local record = hatchRecords[i]
	hatchSeen[record.Part] = nil
	eggGone(record, now)
	hatchRecords[i] = hatchRecords[#hatchRecords]
	hatchRecords[#hatchRecords] = nil
end

local function stepHatch(now: number, camPos: Vector3)
	local Util = ctx.Util
	table.clear(wobbling)
	for i = #hatchRecords, 1, -1 do
		local record = hatchRecords[i]
		local part = record.Part
		if part.Parent == nil then
			removeHatchRecord(i, now)
		else
			local hatchAt = part:GetAttribute("HatchAt")
			record.HatchAt = if type(hatchAt) == "number" then hatchAt else nil
			local distance = (part.Position - camPos).Magnitude
			local wantWobble = false
			if type(hatchAt) == "number" and distance < HATCH_RANGE then
				local left = hatchAt - now
				local labelObj = record.Label
				if not labelObj or labelObj.Parent == nil then
					labelObj = findValueLabel(part)
					record.Label = labelObj
				end
				if labelObj then
					local text = if left > 0.5
						then "🐣 Schlüpft in " .. Util.FormatTime(math.ceil(left))
						else "🐣 Schlüpft..."
					-- letzte Sekunden: Schrift blinkt zwischen Gold und Weiß
					local color = HATCH_COLOR
					if left < WOBBLE_TIME and math.floor(now * 5) % 2 == 0 then
						color = Color3.new(1, 1, 1)
					end
					if labelObj.Text ~= text then
						labelObj.Text = text
					end
					if labelObj.TextColor3 ~= color then
						labelObj.TextColor3 = color
					end
				end
				wantWobble = left < WOBBLE_TIME
					and left > -WOBBLE_GRACE
					and distance < ANIM_RANGE
					and part.Anchored
					and #wobbling < MAX_WOBBLE
			end
			if wantWobble then
				if not record.Wobble then
					startWobble(record)
				end
				if record.Wobble then
					table.insert(wobbling, record)
				end
			elseif record.Wobble then
				stopWobble(record)
			end
		end
	end
end

-- Jedes Frame: wackelnde Eier + ihre Risse bewegen (in die gemeinsame BulkMoveTo-Liste)
local function stepEggs(now: number, count: number): number
	for _, record in ipairs(wobbling) do
		local part = record.Part
		local hatchAt = record.HatchAt
		if record.Wobble and hatchAt and part.Parent then
			-- Der Server hat das Ei bewegt/vergrößert? -> neue Ruhe-Lage
			local last = record.LastCF
			if not last or (part.Position - last.Position).Magnitude > 0.01 then
				record.BaseCF = part.CFrame
			end
			local base = record.BaseCF
			if base then
				local left = hatchAt - now
				local u = math.clamp(1 - left / WOBBLE_TIME, 0, 1)
				record.Progress = u
				local amp = math.rad(3 + 17 * u * u)
				local speed = 9 + 24 * u
				local a = math.sin(now * speed) * amp
				local b = math.sin(now * speed * 0.77 + 1.3) * amp * 0.55
				local radius = part.Size.Y / 2
				-- kurz vor dem Schlüpfen hüpft das Ei
				local hop = if u > 0.75 then math.abs(math.sin(now * speed * 0.5)) * radius * 0.25 * (u - 0.75) else 0
				local cf = base * CFrame.new(0, hop - radius, 0) * CFrame.Angles(b, 0, a) * CFrame.new(0, radius, 0)
				count += 1
				moveParts[count] = part
				moveCFrames[count] = cf
				record.LastCF = cf
				local glow = math.clamp(u * 1.25, 0, 1)
				local transparency = 1 - glow * 0.95
				for j, crack in ipairs(record.Cracks) do
					count += 1
					moveParts[count] = crack
					moveCFrames[count] = cf * record.CrackOffsets[j]
					-- Risse brechen nacheinander auf
					local own = math.clamp(glow * 1.6 - (j - 1) * 0.12, 0, 1)
					local wanted = 1 - own * (1 - transparency)
					if math.abs(crack.Transparency - wanted) > 0.02 then
						crack.Transparency = wanted
					end
				end
				local light = record.Light
				if light then
					light.Brightness = glow * glow * (4 + math.sin(now * 23) * 1.2)
				end
			end
		end
	end
	return count
end

-- Zerstörte Objekte aus den Listen werfen. Je nach Destroy-Replikation behalten Teile in einem
-- zerstörten Model ihren Parent – deshalb (selten) prüfen, ob sie noch in der Welt hängen.
local function cleanupDead(now: number)
	for i = #rainbowRecords, 1, -1 do
		local inst = rainbowRecords[i].Inst
		if not inst:IsDescendantOf(workspace) then
			rainbowSeen[inst] = nil
			rainbowRecords[i] = rainbowRecords[#rainbowRecords]
			rainbowRecords[#rainbowRecords] = nil
		end
	end
	for i = #hatchRecords, 1, -1 do
		if not hatchRecords[i].Part:IsDescendantOf(workspace) then
			removeHatchRecord(i, now)
		end
	end
end

-- ---------------------------------------------------------------------
-- NEUE ALIENS: kurz merken und prüfen, ob sie gerade geschlüpft sind (-> reinploppen)
-- ---------------------------------------------------------------------
local pendingAliens: { RecentAlien } = {}
local initDone = false

local function onAlienAdded(inst: Instance)
	if initDone and inst:IsA("Model") and inst:GetAttribute("Bob") == true then
		table.insert(pendingAliens, { Model = inst, Time = animClockNow, Pos = nil })
	end
end

-- Passendes verschwundenes Ei (oder "Hatch"-Effekt) an dieser Stelle? -> verbrauchen
local function matchEgg(pos: Vector3): boolean
	for i = #recentEggs, 1, -1 do
		if flatDistance(recentEggs[i].Pos, pos) < POP_MATCH_DISTANCE then
			table.remove(recentEggs, i)
			return true
		end
	end
	return false
end

local function stepPendingAliens(now: number)
	local clock = animClockNow
	for i = #recentEggs, 1, -1 do
		if clock - recentEggs[i].Time > RECENT_TIME then
			table.remove(recentEggs, i)
		end
	end
	for i = #recentAliens, 1, -1 do
		if clock - recentAliens[i].Time > RECENT_TIME or recentAliens[i].Model.Parent == nil then
			table.remove(recentAliens, i)
		end
	end
	if #pendingAliens == 0 then
		return
	end
	-- Eier, die gerade verschwunden sind, sofort einsammeln (nicht erst beim nächsten Countdown-Takt)
	for i = #hatchRecords, 1, -1 do
		if hatchRecords[i].Part.Parent == nil then
			removeHatchRecord(i, now)
		end
	end
	for i = #pendingAliens, 1, -1 do
		local entry = pendingAliens[i]
		local model = entry.Model
		if model.Parent == nil or clock - entry.Time > RECENT_TIME then
			table.remove(pendingAliens, i)
		elseif model.PrimaryPart then
			table.remove(pendingAliens, i)
			local pos = model:GetPivot().Position
			entry.Pos = pos
			if matchEgg(pos) then
				startPop(model)
			else
				table.insert(recentAliens, entry)
			end
		end
	end
end

-- Der Server meldet ein Schlüpfen (Effekt "Hatch"): neues Alien dort -> reinploppen lassen
function WorldFX.NoteHatch(position: Vector3)
	if typeof(position) ~= "Vector3" then
		return
	end
	for i = #recentAliens, 1, -1 do
		local entry = recentAliens[i]
		local pos = entry.Pos
		if pos and flatDistance(pos, position) < POP_MATCH_DISTANCE then
			table.remove(recentAliens, i)
			startPop(entry.Model)
			return
		end
	end
	-- Alien ist evtl. noch unterwegs -> wie ein verschwundenes Ei merken
	table.insert(recentEggs, { Pos = position, Time = animClockNow })
end

-- ---------------------------------------------------------------------
-- KRASSE EIER (Attribut "RareFX" vom Server, ab Legendary): rotierender Ring aus leuchtenden
-- Würfeln, stärker pulsierendes Licht, Partikel nur in Kameranähe, Säule immer senkrecht,
-- ab Mythic zuckende Blitze. Alles lokal; nur die nächsten MAX_RINGS bekommen Ring + Blitze.
-- ---------------------------------------------------------------------
type RareRecord = {
	Part: BasePart,
	Tier: number,
	Color: Color3,
	Emitters: { ParticleEmitter },
	EmittersOn: boolean,
	Light: PointLight?,
	LightBase: number,
	Top: Attachment?,
	TopHeight: number,
	Ring: { BasePart }, -- leer = gerade kein Ring
	Phase: number,
	Dist: number,
	NextBolt: number,
}

local RARE_FX_RANGE = 130 -- Partikel nur so nah an der Kamera
local RARE_RING_RANGE = 110
local MAX_RINGS = 8 -- so viele Eier bekommen gleichzeitig Ring + Blitze (die nächsten)
local RING_SEGMENTS = 10
local RING_SPEED = 1.6 -- rad/s
local RING_TILT = math.rad(18)
local MAX_BOLTS = 4
local BOLT_SEGMENTS = 3
local BOLT_TIME = 0.12
local HIDDEN_CF = CFrame.new(0, -5000, 0)

local rareRecords: { RareRecord } = {}
local rareSeen: { [Instance]: RareRecord } = {}
local rareCandidates: { RareRecord } = {}
local rareParts: { BasePart } = {}
local rareCFrames: { CFrame } = {}
type Bolt = { Parts: { BasePart }, Until: number, Active: boolean }
local bolts: { Bolt } = {}

local function rareColor(part: BasePart): Color3
	local rarityName = part:GetAttribute("Rarity")
	local rarities = ctx and ctx.Config.RaritiesByName
	local rarity = rarities and type(rarityName) == "string" and rarities[rarityName]
	if rarity and typeof(rarity.Color) == "Color3" then
		return rarity.Color
	end
	return HATCH_COLOR
end

local function addRare(inst: Instance)
	if not inst:IsA("BasePart") or rareSeen[inst] then
		return
	end
	local tier = inst:GetAttribute("RareFX")
	if type(tier) ~= "number" then
		return
	end
	local emitters: { ParticleEmitter } = {}
	for _, child in ipairs(inst:GetChildren()) do
		if child:IsA("ParticleEmitter") and string.sub(child.Name, 1, 4) == "Rare" then
			child.Enabled = false
			table.insert(emitters, child)
		end
	end
	local light = inst:FindFirstChildOfClass("PointLight")
	local top = inst:FindFirstChild("PillarTop")
	local record: RareRecord = {
		Part = inst,
		Tier = tier,
		Color = rareColor(inst),
		Emitters = emitters,
		EmittersOn = false,
		Light = light,
		LightBase = if light then light.Brightness else 0,
		Top = if top and top:IsA("Attachment") then top else nil,
		TopHeight = if top and top:IsA("Attachment") then top.Position.Magnitude else 0,
		Ring = {},
		Phase = math.random() * math.pi * 2,
		Dist = math.huge,
		NextBolt = 0,
	}
	rareSeen[inst] = record
	table.insert(rareRecords, record)
end

local function removeRing(record: RareRecord)
	for _, segment in ipairs(record.Ring) do
		segment:Destroy()
	end
	table.clear(record.Ring)
end

local function buildRing(record: RareRecord)
	local folder = fxFolder
	if not folder or #record.Ring > 0 then
		return
	end
	local radius = record.Part.Size.X * 0.5 + 1
	local count = RING_SEGMENTS * (if record.Tier >= 2 then 2 else 1)
	local length = 2 * math.pi * radius / RING_SEGMENTS * 0.55
	for i = 1, count do
		local color = record.Color:Lerp(Color3.new(1, 1, 1), 0.25)
		if record.Tier >= 3 then
			color = Color3.fromHSV(((i - 1) % RING_SEGMENTS) / RING_SEGMENTS, 0.85, 1)
		end
		table.insert(
			record.Ring,
			UI.Create("Part", {
				Name = "RareRing",
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Material = Enum.Material.Neon,
				Color = color,
				Size = Vector3.new(0.35, 0.35, length),
				CFrame = HIDDEN_CF,
				Parent = folder,
			})
		)
	end
end

local function setEmitters(record: RareRecord, on: boolean)
	if record.EmittersOn == on then
		return
	end
	record.EmittersOn = on
	for _, emitter in ipairs(record.Emitters) do
		emitter.Enabled = on
	end
end

local function byRareDistance(a: RareRecord, b: RareRecord): boolean
	return a.Dist < b.Dist
end

-- Alle SCAN_INTERVAL s: Partikel nach Entfernung, Ringe nur für die nächsten MAX_RINGS
local function scanRare(camPos: Vector3)
	local count = 0
	for i = #rareRecords, 1, -1 do
		local record = rareRecords[i]
		local part = record.Part
		if part.Parent == nil or not part:IsDescendantOf(workspace) then
			removeRing(record)
			rareSeen[part] = nil
			rareRecords[i] = rareRecords[#rareRecords]
			rareRecords[#rareRecords] = nil
		else
			record.Dist = (part.Position - camPos).Magnitude
			setEmitters(record, record.Dist < RARE_FX_RANGE)
			if record.Dist < RARE_RING_RANGE then
				count += 1
				rareCandidates[count] = record
			elseif #record.Ring > 0 then
				removeRing(record)
			end
		end
	end
	for i = #rareCandidates, count + 1, -1 do
		rareCandidates[i] = nil
	end
	if count > MAX_RINGS then
		table.sort(rareCandidates, byRareDistance)
	end
	for i = 1, count do
		local record = rareCandidates[i]
		if i <= MAX_RINGS then
			buildRing(record)
		else
			removeRing(record)
		end
	end
end

local function buildBolts()
	local folder = fxFolder
	if not folder then
		return
	end
	for _ = 1, MAX_BOLTS do
		local bolt: Bolt = { Parts = {}, Until = 0, Active = false }
		for _ = 1, BOLT_SEGMENTS do
			table.insert(
				bolt.Parts,
				UI.Create("Part", {
					Name = "RareBolt",
					Anchored = true,
					CanCollide = false,
					CanQuery = false,
					CanTouch = false,
					CastShadow = false,
					Material = Enum.Material.Neon,
					Color = Color3.fromRGB(220, 240, 255),
					Size = Vector3.new(0.25, 0.25, 1),
					CFrame = HIDDEN_CF,
					Parent = folder,
				})
			)
		end
		table.insert(bolts, bolt)
	end
end

-- Blitz von oben ins Ei: Zickzack aus BOLT_SEGMENTS Stücken, kurz sichtbar
local function fireBolt(record: RareRecord, now: number, count: number): number
	for _, bolt in ipairs(bolts) do
		if not bolt.Active then
			bolt.Active = true
			bolt.Until = now + BOLT_TIME
			local center = record.Part.Position
			local radius = record.Part.Size.Y / 2
			local from = center
				+ Vector3.new((math.random() - 0.5) * 6, 12 + math.random() * 6, (math.random() - 0.5) * 6)
			local to = center + Vector3.new(0, radius * 0.8, 0)
			local last = from
			for j, segment in ipairs(bolt.Parts) do
				local t = j / BOLT_SEGMENTS
				local point = from:Lerp(to, t)
				if j < BOLT_SEGMENTS then
					point += Vector3.new((math.random() - 0.5) * 3, 0, (math.random() - 0.5) * 3)
				end
				local length = (point - last).Magnitude
				segment.Size = Vector3.new(0.25, 0.25, math.max(0.2, length))
				segment.Color = record.Color:Lerp(Color3.new(1, 1, 1), 0.6)
				count += 1
				rareParts[count] = segment
				rareCFrames[count] = CFrame.lookAt((point + last) / 2, point)
				last = point
			end
			return count
		end
	end
	return count
end

-- Jedes Frame: Ringe drehen, Licht pulsieren, Säule senkrecht halten, Blitze
local function stepRare(now: number)
	local count = 0
	for _, bolt in ipairs(bolts) do
		if bolt.Active and now >= bolt.Until then
			bolt.Active = false
			for _, segment in ipairs(bolt.Parts) do
				count += 1
				rareParts[count] = segment
				rareCFrames[count] = HIDDEN_CF
			end
		end
	end
	for _, record in ipairs(rareRecords) do
		if record.EmittersOn then
			local part = record.Part
			local t = now + record.Phase
			-- Glühen pulsiert kräftig
			local light = record.Light
			if light then
				light.Brightness = record.LightBase * (1.1 + 0.6 * math.sin(t * 3.4))
			end
			-- Säule zeigt immer senkrecht nach oben (das Ei wackelt auf dem Kopf des Trägers)
			local top = record.Top
			if top then
				top.Position = part.CFrame:VectorToObjectSpace(Vector3.new(0, record.TopHeight, 0))
			end
			local ring = record.Ring
			if #ring > 0 then
				local center = part.Position
				local radius = part.Size.X * 0.5 + 1
				local spin = t * RING_SPEED
				for i, segment in ipairs(ring) do
					local second = i > RING_SEGMENTS
					local k = if second then i - RING_SEGMENTS else i
					local angle = (if second then -spin else spin) + k * (2 * math.pi / RING_SEGMENTS)
					local tilt = if second then CFrame.Angles(0, 0, RING_TILT * 2.5) else CFrame.Angles(RING_TILT, 0, 0)
					count += 1
					rareParts[count] = segment
					rareCFrames[count] = CFrame.new(center)
						* tilt
						* CFrame.Angles(0, -angle, 0)
						* CFrame.new(radius, 0, 0)
				end
				if record.Tier >= 2 and now >= record.NextBolt then
					record.NextBolt = now + 1 + math.random() * (if record.Tier >= 3 then 1.2 else 2.2)
					count = fireBolt(record, now, count)
				end
			end
		end
	end
	if count > 0 then
		workspace:BulkMoveTo(rareParts, rareCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		table.clear(rareParts)
		table.clear(rareCFrames)
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

	watchFolder(map, "Treadmills", setupTreadmill)

	-- Aliens, Regenbogen und Schlüpf-Meteore: einmal alles durchsehen, danach nur Neues
	buildBolts()
	for _, inst in ipairs(map:GetDescendants()) do
		addAnim(inst)
		addRare(inst)
		local parent = inst.Parent
		if parent and parent.Name ~= "ParadeMeteors" and parent.Name ~= "GroundMeteors" then
			addHatchCandidate(inst)
		end
	end
	initDone = true
	map.DescendantAdded:Connect(function(inst)
		if addAnim(inst) then
			onAlienAdded(inst)
		end
		addRare(inst)
		local parent = inst.Parent
		-- Eier in der Parade / am Boden schlüpfen nie -> gar nicht erst beobachten
		if parent and parent.Name ~= "ParadeMeteors" and parent.Name ~= "GroundMeteors" then
			addHatchCandidate(inst)
		end
	end)
	-- Regenbogen + Umrisse (+ Lava-Feuer) überall – auch an getragenen Aliens (hängen am Charakter, nicht in der Map)
	local function onWorldDescendant(inst: Instance)
		considerRainbow(inst)
		addHighlight(inst)
	end
	for _, inst in ipairs(workspace:GetDescendants()) do
		onWorldDescendant(inst)
	end
	workspace.DescendantAdded:Connect(onWorldDescendant)

	local slowClock = 0
	local hatchClock = HATCH_INTERVAL
	local scanClock = SCAN_INTERVAL -- gleich im ersten Frame auswählen
	local cleanupClock = 0
	local animClock = 0 -- eigene Animations-Uhr (läuft mit dt, auch bei Rucklern gleichmäßig)
	local stripeClock = 0 -- eigene Uhr für die Streifen (Serverzeit wird nachgeregelt -> ruckelt)
	RunService.RenderStepped:Connect(function(dt: number)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		frameNumber += 1
		local camCFrame = camera.CFrame
		local camPos = camCFrame.Position
		local now = workspace:GetServerTimeNow()
		animClock += dt
		stripeClock += dt
		animClockNow = animClock

		-- Schlüpf-Countdown zuerst (wählt die wackelnden Eier für dieses Frame)
		hatchClock += dt
		if hatchClock >= HATCH_INTERVAL then
			hatchClock = math.min(hatchClock - HATCH_INTERVAL, HATCH_INTERVAL)
			stepHatch(now, camPos)
		end

		table.clear(moveParts)
		table.clear(moveCFrames)
		local look = camCFrame.LookVector
		local cosLimit = viewCos(camera)
		local count = stepStripes(stripeClock, camPos, look, cosLimit, 0)
		if #wobbling > 0 then
			count = stepEggs(now, count)
		end
		if count > 0 then
			workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end
		-- Parade (Eier + Träger) VOR den krassen Eiern (Ringe folgen der aktuellen Position)
		local step = preStep
		if step then
			step(now, dt, camPos, look, cosLimit, frameNumber)
		end
		stepRare(now)

		scanClock += dt
		if scanClock >= SCAN_INTERVAL then
			scanClock = 0
			scanAnim(camPos)
			scanHighlights(camPos)
			scanRare(camPos)
		end
		cleanupClock += dt
		if cleanupClock >= CLEANUP_INTERVAL then
			cleanupClock = 0
			cleanupDead(now)
		end

		-- Neue Aliens: geschlüpft? -> reinploppen (Overshoot)
		if #pendingAliens > 0 or #recentEggs > 0 or #recentAliens > 0 then
			stepPendingAliens(now)
		end
		if #pops > 0 then
			stepPops(animClock)
		end

		-- Aliens: jedes Frame ein Teil, jedes einzelne ca. 30x pro Sekunde
		local stride = math.max(1, math.floor(SLOW_INTERVAL / math.max(dt, 1 / 240) + 0.5))
		table.clear(animParts)
		table.clear(animCFrames)
		local animCount = stepAnim(animClock, stride)
		if animCount > 0 then
			workspace:BulkMoveTo(animParts, animCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end

		slowClock += dt
		if slowClock >= SLOW_INTERVAL then
			-- abziehen statt auf 0 setzen -> gleichmäßiger Takt (nach Rucklern nicht nachholen)
			slowClock = math.min(slowClock - SLOW_INTERVAL, SLOW_INTERVAL)
			stepRainbow(animClock, camPos)
		end
	end)
end

return WorldFX
