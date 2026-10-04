-- ☄️ METEOR-RUN: langer Lauf-Parcours (Obby) – wer schnell ist, gewinnt ein Gratis-Ei!
--
-- LAGE: rechts neben dem Spawn-Platz, dann hinter den rechten Basen entlang bis zum Map-Ende
-- (zwischen den Rückwänden der Basen und der rechten Randwand). X-Mitte, Breite und Start werden
-- aus der Map abgeleitet (Basen, Randwände, Spawn-Platz). Deko (Bäume/Büsche) im Weg wird entfernt.
-- Die Strecke liegt erhöht (TOP Studs): wer runterfällt, muss zurück zum letzten Checkpoint.
--
-- ABLAUF: Rampe hoch -> durchs Start-Tor ("Bereit") -> über die Startlinie = Timer läuft
--   1 🔥 Lava-Felder   2 🦘 Sprünge über Lücken   3 🌀 rotierende Balken
--   4 ☄️ Meteor-Einschläge   5 🔥 Lava-Steine   -> 🏁 Ziel-Podest mit Belohnungs-Ei
-- Checkpoints (Pads) speichern den Fortschritt im Run. Lava, Runterfallen und Einschläge = zurück
-- zum letzten Checkpoint (niemand stirbt). Im Ziel: Cash + ein Gratis-Ei (Epic..Mythic, selten höher),
-- das man wie ein geklautes Ei nach Hause TRAGEN muss (CarryService, Source = "Ground", mit
-- ScaleTimeout = mehr Trage-Zeit, je weiter die eigene Base vom Ziel weg ist).
-- Abklingzeit pro Spieler zwischen zwei Belohnungen (auch im Spielstand: data.RunRewardAt),
-- Bestzeit in data.RunBest.
--
-- PERFORMANCE: Der Server bewegt NICHTS. Die rotierenden Balken dreht jeder Client selbst
-- (Attribute SpinPivot/SpinAxis/SpinSpeed/SpinT0, Winkel aus der Serverzeit -> alle sehen dasselbe).
-- Der Server prüft nur alle 0,2 s die Positionen (Lava, Checkpoints, Ziel, Runterfallen).
-- Einschläge bestimmt der Server: Effekt "RunImpact" an alle (Warnkreis 1 s vorher), dann Treffer-Prüfung.
--
-- ANTI-CHEAT: Checkpoints nur in der richtigen Reihenfolge, Ziel nur mit allen Checkpoints und
-- frühestens nach Streckenlänge / (MaxWalkSpeed * 1.3). Teleport-/Speed-Verstoß (CarryService.MoveStatus)
-- bricht den Run ab; Linien zählen nur bei einem zu Fuß möglichen Schritt (plausibleStep – auch in der
-- Schonzeit nach einem Zurücksetzen). Schweben über Lava (zu lange in der Luft, nicht auf einem Stein)
-- und Fliegen (viel zu hoch) = zurück zum Checkpoint. Wer etwas trägt, kann nicht starten.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))

local RunService = {}
local Services

local rng = Random.new()

-- -------------------------------------------------------------------
-- EINSTELLUNGEN
-- -------------------------------------------------------------------
local TOP = 8 -- Höhe der Lauffläche über der Wiese
local DECK = 1 -- Dicke der Lauffläche
local RAMP_LENGTH = 32 -- Rampe von der Wiese hoch zum Start
local PLAZA_GAP = 6 -- Abstand Rampen-Oberkante <-> Rand des Spawn-Platzes (Z)
local MAX_WIDTH = 14
local MIN_WIDTH = 8
-- Ersatzwerte, falls die Map anders aussieht (Werte aus MapBuilder)
local FALLBACK_PLOT_EDGE = 124
local FALLBACK_WALL_X = 168
local FALLBACK_WALL_MAX_Z = 256
local FALLBACK_PLAZA_MAX_Z = -226

local TICK = 0.2 -- so oft prüft der Server die Läufer
local REWARD_COOLDOWN = 180 -- Sekunden zwischen zwei Belohnungen pro Spieler
local MAX_RUN_TIME = 600 -- länger = Run abgebrochen
local AREA_SIDE = 20 -- so weit seitlich neben der Streckenmitte = Run abgebrochen (z.B. Home-Teleport)
local AREA_END = 12 -- so weit vor der Rampe / hinter dem Ziel = Run abgebrochen
local FALL_DEPTH = 1 -- Hüfte tiefer als Lauffläche + FALL_DEPTH = runtergefallen
local FOOT = 0.4 -- Lava-Felder zählen so viel breiter (Füße ragen über die Hüfte hinaus)
local NOTIFY_GAP = 1.5 -- Hinweise (Lava, Checkpoint fehlt ...) höchstens so oft pro Spieler
local SPEED_TOLERANCE = 1.3 -- Mindestzeit = Streckenlänge / (MaxWalkSpeed * SPEED_TOLERANCE)
-- Checkpoints/Ziel zählen nur, wenn der Schritt seit der letzten Messung zu Fuß möglich war
-- (WalkSpeed * STEP_FACTOR + STEP_EXTRA) * dt + STEP_SLACK – sonst wäre ein Teleport in der Schonzeit
-- nach einem Zurücksetzen (CarryService.MoveStatus = "wait") ein Abkürzungs-Trick
local STEP_FACTOR = 1.5
local STEP_EXTRA = 16
local STEP_SLACK = 4
local LAVA_AIR_MAX = 1.5 -- so lange darf man über Lava "in der Luft" sein (Sprung ~0,5 s) – länger = Schweben
-- Nach einem Server-Teleport kurz nichts prüfen: bis der Client den Teleport kennt, kommen noch alte
-- Positionen an (sonst: mehrfaches Zurücksetzen hintereinander bei hohem Ping)
local TELEPORT_GRACE = 0.75
local MAX_HEIGHT = 20 -- Hüfte höher als Lauffläche + das = Flug-Cheat -> zurück zum Checkpoint

local IMPACT_WARN = 1 -- Sekunden Warnkreis vor dem Einschlag
local IMPACT_RADIUS = 6
local IMPACT_INTERVAL = 0.7 -- so oft schlägt es ein, solange jemand im Einschlag-Abschnitt ist
local IMPACT_MAX = 6 -- höchstens so viele Einschläge gleichzeitig angekündigt
local IMPACT_AIM_CHANCE = 0.6 -- so oft wird auf einen Läufer gezielt (mit Vorhalt)
local IMPACT_LEAD = 0.6 -- Vorhalt in Sekunden
local IMPACT_HEIGHT = 12 -- so hoch über der Lauffläche trifft ein Einschlag noch (Hochspringen rettet nicht)

-- Belohnung
local PAR_TIME = 40 -- schneller als das = mehr Glück beim Ei
local RUN_MIN_CASH = 2500
local RUN_CASH_SECONDS = 90 -- Cash = max(RUN_MIN_CASH, Einkommen pro Sekunde * das)
local NEW_BEST_CASH_MULT = 1.5
local REBIRTH_LUCK = 0.1 -- pro Rebirth (max. 10) mehr Glück
local ANNOUNCE_RARITY = Config.RarityIndex.Mythic or 6 -- ab Mythic: allen ansagen
-- Gratis-Ei: Lucky = Gewicht wächst mit dem Glück, MinRebirths = erst ab so vielen Rebirths
local EGG_TABLE = {
	{ Rarity = "Epic", Weight = 60 },
	{ Rarity = "Legendary", Weight = 28, Lucky = true },
	{ Rarity = "Mythic", Weight = 10, Lucky = true },
	{ Rarity = "Celestial", Weight = 1.5, Lucky = true },
	{ Rarity = "Divine", Weight = 0.25, Lucky = true, MinRebirths = 3 },
}

-- Strecke: Abstände (Studs) ab der Rampen-Oberkante entlang +Z
local GATE_D = 6 -- Start-Tor
local READY_FROM_D = 7 -- ab hier "Bereit"
local START_LINE_D = 16 -- Startlinie: hier startet der Timer
local START_RESPAWN_D = 19 -- zurückgesetzt ohne Checkpoint -> hierhin (Timer läuft weiter)
local CHECKPOINT_D = { 104, 192, 280, 368 } -- Mitte der Checkpoint-Pads
local CHECKPOINT_DEPTH = 8
local IMPACT_AFTER_CP = 3 -- Einschlag-Abschnitt liegt hinter Checkpoint 3
local IMPACT_FROM_D = 288
local IMPACT_TO_D = 360
local FINISH_D = 434 -- Ziellinie
local END_D = 452 -- Ende des Ziel-Podests

local COLORS = {
	Deck = Color3.fromRGB(46, 40, 78),
	DeckAlt = Color3.fromRGB(60, 44, 96),
	Edge = Color3.fromRGB(0, 220, 255),
	Pillar = Color3.fromRGB(70, 70, 86),
	Lava = Color3.fromRGB(255, 90, 20),
	Stone = Color3.fromRGB(110, 100, 95),
	Gate = Color3.fromRGB(255, 140, 40),
	Finish = Color3.fromRGB(255, 205, 40),
	Checkpoint = Color3.fromRGB(80, 200, 255),
	Spinner = Color3.fromRGB(255, 60, 90),
	Crater = Color3.fromRGB(40, 30, 30),
}
local WHITE = Color3.new(1, 1, 1)

local RESET_TEXT: { [string]: string } = {
	lava = "🔥 Lava! Zurück zum Checkpoint!",
	fall = "🕳️ Runtergefallen! Zurück zum Checkpoint!",
	impact = "☄️ Getroffen! Zurück zum Checkpoint!",
}

-- -------------------------------------------------------------------
-- ZUSTAND
-- -------------------------------------------------------------------
type Box = { MinX: number, MaxX: number, MinZ: number, MaxZ: number, Top: number }
-- Phase "Ready" = im Start-Tor (Timer steht), "Running" = Timer läuft
type RunState = { Phase: string, Start: number, CP: number }

local runs: { [Player]: RunState } = {}
local cooldownUntil: { [number]: number } = {} -- UserId -> Serverzeit (überlebt Neu-Beitreten auf dem Server)
-- Zusätzlich im Spielstand: data.RunRewardAt = os.time(), ab dann gibt es wieder eine Belohnung
-- (sonst: Server wechseln = Abklingzeit weg)
local notifyAt: { [Player]: number } = {}
local lastPos: { [Player]: Vector3 } = {} -- letzte gemessene Position (für Linien und Lava dazwischen)
local lavaAir: { [Player]: number } = {} -- Sekunden ununterbrochen über Lava, ohne auf einem Stein zu stehen
local graceUntil: { [Player]: number } = {} -- os.clock(): bis dann keine Lava-/Fall-/Einschlag-Prüfung
local runFolder: Folder? = nil
local recordLabel: TextLabel? = nil
local serverRecord: { Name: string, Time: number }? = nil

-- Geometrie (wird beim Bauen gesetzt)
local X0 = 146
local Z0 = -232
local WIDTH = MAX_WIDTH
local lavaBoxes: { Box } = {}
local checkpointZ: { number } = {}
local respawnCF: { CFrame } = {} -- [1] = Start, [i + 1] = Checkpoint i
local startSpawnCF = CFrame.new()
local readyMinZ, readyMaxZ = 0, 0
local finishZ = 0
local exitMinZ, exitMaxZ = 0, 0 -- Rampe vom Ziel-Podest runter
local lineMinX, lineMaxX = 0, 0 -- so breit zählen Startlinie, Checkpoints, Ziel
local areaMinX, areaMaxX, areaMinZ, areaMaxZ = 0, 0, 0, 0 -- Strecke mit Rand
local exitMinX = 0 -- Ziel-Rampe zählt auch noch zur Strecke (bis hier)
local minRunTime = 0
local stoneParams = RaycastParams.new() -- Strahl nach unten trifft nur die Lava-Steine
stoneParams.FilterType = Enum.RaycastFilterType.Include

-- -------------------------------------------------------------------
-- KLEINE HELFER
-- -------------------------------------------------------------------
local function now(): number
	return workspace:GetServerTimeNow()
end

-- 41.27 -> "0:41.3"
local function formatRunTime(seconds: number): string
	local tenths = math.floor(math.max(0, seconds) * 10 + 0.5)
	return string.format("%d:%04.1f", tenths // 600, (tenths % 600) / 10)
end

local function world(d: number, x: number, y: number): Vector3
	return Vector3.new(X0 + x, y, Z0 + d)
end

local function aliveRoot(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end
	return root, humanoid
end

-- Normale Höhe des HumanoidRootPart über dem Boden, wenn man steht (R15 bzw. R6)
local function standHeight(humanoid: Humanoid, root: BasePart): number
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	return root.Size.Y / 2 + 2
end

local function notifyLimited(player: Player, text: string, kind: string)
	local t = os.clock()
	if t - (notifyAt[player] or 0) < NOTIFY_GAP then
		return
	end
	notifyAt[player] = t
	Services.EconomyService.Notify(player, text, kind)
end

-- Schneidet die Strecke a -> b (waagrecht) das Rechteck? (schnelle Läufer überspringen sonst Felder)
local function segmentHitsBox(a: Vector3, b: Vector3, box: Box): boolean
	local t0, t1 = 0, 1
	for axis = 1, 2 do
		local origin = if axis == 1 then a.X else a.Z
		local delta = if axis == 1 then b.X - a.X else b.Z - a.Z
		local lo = if axis == 1 then box.MinX else box.MinZ
		local hi = if axis == 1 then box.MaxX else box.MaxZ
		if math.abs(delta) < 1e-6 then
			if origin < lo or origin > hi then
				return false
			end
		else
			local u0 = (lo - origin) / delta
			local u1 = (hi - origin) / delta
			if u0 > u1 then
				u0, u1 = u1, u0
			end
			t0 = math.max(t0, u0)
			t1 = math.min(t1, u1)
			if t0 > t1 then
				return false
			end
		end
	end
	return true
end

-- Ist die Linie bei z (quer über die Strecke) von a nach b vorwärts überquert worden?
local function crossedLine(a: Vector3, b: Vector3, z: number): boolean
	if not (a.Z < z and b.Z >= z) then
		return false
	end
	local t = (z - a.Z) / (b.Z - a.Z)
	local x = a.X + (b.X - a.X) * t
	local y = a.Y + (b.Y - a.Y) * t
	return x >= lineMinX and x <= lineMaxX and y > TOP - FALL_DEPTH and y < TOP + 20
end

-- Auf/an der Strecke (inkl. Rampe vom Ziel-Podest)? Weiter weg = Run abgebrochen
local function inArea(p: Vector3): boolean
	if p.X >= areaMinX and p.X <= areaMaxX and p.Z >= areaMinZ and p.Z <= areaMaxZ then
		return true
	end
	return p.X >= exitMinX and p.X < areaMinX and p.Z >= exitMinZ - 4 and p.Z <= exitMaxZ + 4
end

local function inReadyZone(p: Vector3): boolean
	return p.X >= lineMinX and p.X <= lineMaxX and p.Z >= readyMinZ and p.Z < readyMaxZ and p.Y > TOP and p.Y < TOP + 12
end

-- -------------------------------------------------------------------
-- BAU-HELFER (wie im MapBuilder)
-- -------------------------------------------------------------------
local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false -- alles wird per Position geprüft (spart Physik-Arbeit)
	for key, value in pairs(props) do
		if key ~= "Parent" then
			(p :: any)[key] = value
		end
	end
	p.Parent = props.Parent
	return p
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Unsichtbarer Ankerpunkt für Schilder
local function anchorPart(name: string, position: Vector3, parent: Instance): Part
	return part({
		Name = name,
		Size = Vector3.new(1, 1, 1),
		Position = position,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
		Parent = parent,
	})
end

type SignLine = { Name: string, Text: string, Color: Color3, Height: number }

-- Mehrzeiliges Schild in Studs-Größe (Aufbau wie MapBuilder: BillboardGui > Frame > TextLabels)
local function worldSign(parent: Instance, width: number, height: number, lines: { SignLine }): { [string]: TextLabel }
	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromScale(width, height)
	gui.MaxDistance = 400
	gui.LightInfluence = 0
	gui.Parent = parent
	local frame = Instance.new("Frame")
	frame.Name = "Frame"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = frame
	local labels: { [string]: TextLabel } = {}
	for order, line in ipairs(lines) do
		local label = Instance.new("TextLabel")
		label.Name = line.Name
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, line.Height)
		label.LayoutOrder = order
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = line.Color
		label.Text = line.Text
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Parent = label
		label.Parent = frame
		labels[line.Name] = label
	end
	return labels
end

-- -------------------------------------------------------------------
-- LAGE AUS DER MAP ABLEITEN
-- -------------------------------------------------------------------
-- X-Mitte zwischen Außenkante der rechten Basen und rechter Randwand, Start neben dem Spawn-Platz
local function computeLayout(map: Instance?)
	local plotEdge = -math.huge
	for _, plot in ipairs(Services.PlotService.Plots) do
		local cf = plot.CFrame
		if typeof(cf) == "CFrame" and cf.Position.X > 0 then
			-- Basen können rechteckig + gedreht sein -> echte Außenkante aus dem Welt-Rechteck
			local _, maxX = Services.PlotService.WorldRect(plot)
			plotEdge = math.max(plotEdge, maxX)
		end
	end
	if plotEdge == -math.huge then
		plotEdge = FALLBACK_PLOT_EDGE
	end
	local wallX, wallMaxZ = FALLBACK_WALL_X, FALLBACK_WALL_MAX_Z
	local plazaMaxZ = FALLBACK_PLAZA_MAX_Z
	if map then
		local foundX, foundZ = math.huge, -math.huge
		for _, child in ipairs(map:GetChildren()) do
			if child.Name == "Boundary" and child:IsA("BasePart") then
				if child.Size.X < child.Size.Z and child.Position.X > 0 then
					foundX = math.min(foundX, child.Position.X - child.Size.X / 2)
				elseif child.Size.Z < child.Size.X and child.Position.Z > 0 then
					foundZ = math.max(foundZ, child.Position.Z - child.Size.Z / 2)
				end
			end
		end
		if foundX < math.huge then
			wallX = foundX
		end
		if foundZ > -math.huge then
			wallMaxZ = foundZ
		end
		local plaza = map:FindFirstChild("Plaza")
		local floorPart = plaza and plaza:FindFirstChild("Floor")
		if floorPart and floorPart:IsA("BasePart") then
			plazaMaxZ = floorPart.Position.Z + floorPart.Size.Z / 2
		end
	end
	local gap = wallX - plotEdge
	WIDTH = math.clamp(gap - 10, MIN_WIDTH, MAX_WIDTH)
	X0 = (plotEdge + wallX) / 2
	Z0 = plazaMaxZ - PLAZA_GAP
	if gap - WIDTH < 4 then
		warn("[RunService] Wenig Platz zwischen Basen und Randwand – der Meteor-Run wird eng")
	end
	if Z0 + END_D + 4 > wallMaxZ then
		warn("[RunService] Der Meteor-Run ist länger als die Map – das Ziel liegt hinter der Randwand!")
	end
end

-- Deko (Bäume/Büsche) im Weg entfernen, andere Kollisionen melden
local function clearArea(map: Instance, center: Vector3, size: Vector3)
	local deco = map:FindFirstChild("Deco")
	-- ohne Filter (alles im Kasten), nur Teile der Map zählen
	local hits = workspace:GetPartBoundsInBox(CFrame.new(center), size)
	local conflicts: { string } = {}
	for _, hit in ipairs(hits) do
		if not hit.Parent or not hit:IsDescendantOf(map) then
			continue -- schon entfernt (Teil eines Baums) oder gehört nicht zur Map
		end
		if deco and hit:IsDescendantOf(deco) then
			-- ganzen Baum entfernen (Stamm + Krone stehen an derselben Stelle)
			local spot = hit.Position
			for _, other in ipairs(deco:GetChildren()) do
				if other ~= hit and other:IsA("BasePart") then
					local dx, dz = other.Position.X - spot.X, other.Position.Z - spot.Z
					if dx * dx + dz * dz < 1 then
						other:Destroy()
					end
				end
			end
			hit:Destroy()
		elseif hit.Name ~= "Ground" and #conflicts < 5 then
			table.insert(conflicts, hit:GetFullName())
		end
	end
	if #conflicts > 0 then
		warn("[RunService] Meteor-Run überschneidet sich mit: " .. table.concat(conflicts, ", "))
	end
end

-- -------------------------------------------------------------------
-- STRECKE BAUEN
-- -------------------------------------------------------------------
local decoFolder: Folder
local lavaFolder: Folder
local spinnerFolder: Folder
local checkpointFolder: Folder

-- Lauffläche von d0 bis d1 (x = Versatz zur Mitte), mit Leuchtkanten und Stützen
local function deck(d0: number, d1: number, x: number, width: number, color: Color3)
	local length = d1 - d0
	local mid = (d0 + d1) / 2
	part({
		Name = "Deck",
		Size = Vector3.new(width, DECK, length),
		Position = world(mid, x, TOP - DECK / 2),
		Material = Enum.Material.SmoothPlastic,
		Color = color,
		Parent = decoFolder,
	})
	for _, s in ipairs({ -1, 1 }) do
		part({
			Name = "Edge",
			Size = Vector3.new(0.4, 0.3, length),
			Position = world(mid, x + s * (width / 2 - 0.2), TOP + 0.15),
			Material = Enum.Material.Neon,
			Color = COLORS.Edge,
			CanCollide = false,
			CastShadow = false,
			Parent = decoFolder,
		})
	end
	local count = math.max(1, math.floor(length / 20 + 0.5))
	for i = 1, count do
		local d = d0 + length * (i - 0.5) / count
		local offsets = if width >= 6 then { -(width / 2 - 1), width / 2 - 1 } else { 0 }
		for _, ox in ipairs(offsets) do
			part({
				Name = "Pillar",
				Size = Vector3.new(1.2, TOP - DECK, 1.2),
				Position = world(d, x + ox, (TOP - DECK) / 2),
				Material = Enum.Material.Metal,
				Color = COLORS.Pillar,
				CastShadow = false,
				Parent = decoFolder,
			})
		end
	end
end

-- Lava-Feld auf der Lauffläche (x0..x1 relativ zur Mitte). Ohne Kollision: man steht auf dem Deck,
-- die Prüfung macht der Server (Position).
local function lava(d0: number, d1: number, x0: number, x1: number)
	part({
		Name = "Lava",
		Size = Vector3.new(x1 - x0, 0.2, d1 - d0),
		Position = world((d0 + d1) / 2, (x0 + x1) / 2, TOP + 0.1),
		Material = Enum.Material.Neon,
		Color = COLORS.Lava,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
		Parent = lavaFolder,
	})
	table.insert(lavaBoxes, {
		MinX = X0 + x0 - FOOT,
		MaxX = X0 + x1 + FOOT,
		MinZ = Z0 + d0 - FOOT,
		MaxZ = Z0 + d1 + FOOT,
		Top = TOP,
	})
end

-- Rotierender Balken: der Client dreht ihn um "pivot" (Achse im Pivot-Raum), der Server nie
local function spinner(
	name: string,
	pivot: CFrame,
	offset: CFrame,
	size: Vector3,
	axis: Vector3,
	speed: number,
	t0: number
)
	local bar = part({
		Name = name,
		Size = size,
		CFrame = pivot * offset,
		Material = Enum.Material.Neon,
		Color = COLORS.Spinner,
		CastShadow = false,
		Parent = spinnerFolder,
	})
	bar:SetAttribute("SpinPivot", pivot)
	bar:SetAttribute("SpinAxis", axis)
	bar:SetAttribute("SpinSpeed", speed) -- Bogenmaß pro Sekunde
	bar:SetAttribute("SpinT0", t0) -- Serverzeit, zu der der Balken so steht wie auf dem Server
end

local function gate(d: number, color: Color3, height: number)
	local half = WIDTH / 2
	for _, s in ipairs({ -1, 1 }) do
		part({
			Name = "GatePillar",
			Size = Vector3.new(1.6, height, 1.6),
			Position = world(d, s * (half + 0.8), TOP + height / 2),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(50, 50, 62),
			Parent = decoFolder,
		})
		part({
			Name = "GateGlow",
			Size = Vector3.new(0.5, height - 1, 0.5),
			Position = world(d, s * (half - 0.1), TOP + height / 2),
			Material = Enum.Material.Neon,
			Color = color,
			CanCollide = false,
			CastShadow = false,
			Parent = decoFolder,
		})
	end
	part({
		Name = "GateBeam",
		Size = Vector3.new(WIDTH + 3.2, 1.6, 1.6),
		Position = world(d, 0, TOP + height + 0.8),
		Material = Enum.Material.Neon,
		Color = color,
		CastShadow = false,
		Parent = decoFolder,
	})
end

-- Linie quer über die Strecke (Start/Ziel: kariert)
local function line(d: number, checkered: boolean)
	local tiles = math.max(2, math.floor(WIDTH / 2))
	local tile = WIDTH / tiles
	for row = 0, 1 do
		for i = 0, tiles - 1 do
			local white = (i + row) % 2 == 0
			if checkered or white then
				part({
					Name = "Line",
					Size = Vector3.new(tile, 0.06, 1),
					Position = world(d - 0.5 + row, -WIDTH / 2 + tile * (i + 0.5), TOP + 0.03),
					Material = Enum.Material.SmoothPlastic,
					Color = if white then WHITE else Color3.fromRGB(20, 20, 24),
					CanCollide = false,
					CanQuery = false,
					CastShadow = false,
					Parent = decoFolder,
				})
			end
		end
	end
end

local function sectionSign(d: number, title: string, hint: string, color: Color3)
	local anchor = anchorPart("SectionSign", world(d, WIDTH / 2 + 2.5, TOP + 7), decoFolder)
	worldSign(anchor, 14, 4.4, {
		{ Name = "Title", Text = title, Color = color, Height = 0.6 },
		{ Name = "Hint", Text = hint, Color = WHITE, Height = 0.4 },
	})
end

local function checkpointPad(index: number, d: number)
	local pad = part({
		Name = "Checkpoint" .. index,
		Size = Vector3.new(WIDTH, 0.12, CHECKPOINT_DEPTH),
		Position = world(d, 0, TOP + 0.06),
		Material = Enum.Material.Neon,
		Color = COLORS.Checkpoint,
		Transparency = 0.25,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
		Parent = checkpointFolder,
	})
	pad:SetAttribute("CheckpointIndex", index)
	for _, s in ipairs({ -1, 1 }) do
		part({
			Name = "Flag",
			Size = Vector3.new(0.5, 6, 0.5),
			Position = world(d, s * (WIDTH / 2 + 0.6), TOP + 3),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(220, 220, 230),
			Parent = decoFolder,
		})
		part({
			Name = "FlagCloth",
			Size = Vector3.new(0.2, 1.6, 2.4),
			Position = world(d + 1.2, s * (WIDTH / 2 + 0.6), TOP + 5.2),
			Material = Enum.Material.Neon,
			Color = COLORS.Checkpoint,
			CanCollide = false,
			CastShadow = false,
			Parent = decoFolder,
		})
	end
	local anchor = anchorPart("CheckpointSign", world(d, 0, TOP + 7.5), decoFolder)
	worldSign(anchor, 8, 2.4, {
		{
			Name = "Title",
			Text = "🚩 Checkpoint " .. index .. "/" .. #CHECKPOINT_D,
			Color = Color3.fromRGB(140, 230, 255),
			Height = 1,
		},
	})
	checkpointZ[index] = Z0 + d
	respawnCF[index + 1] = CFrame.lookAt(world(d + 1.5, 0, TOP + 3.5), world(d + 10, 0, TOP + 3.5))
end

local function build(map: Instance): Folder
	local half = WIDTH / 2
	table.clear(lavaBoxes)
	table.clear(checkpointZ)
	table.clear(respawnCF)

	local root = Instance.new("Folder")
	root.Name = "MeteorRun"
	decoFolder = folder("Deco", root)
	lavaFolder = folder("Lava", root)
	spinnerFolder = folder("Spinners", root)
	checkpointFolder = folder("Checkpoints", root)

	-- RAMPE von der Wiese hoch zum Start (Oberkante genau auf der Lauffläche)
	local rampTop = world(0, 0, TOP)
	local rampBottom = world(-RAMP_LENGTH, 0, 0)
	part({
		Name = "Ramp",
		Size = Vector3.new(WIDTH, 1, (rampTop - rampBottom).Magnitude),
		CFrame = CFrame.lookAt((rampTop + rampBottom) / 2, rampTop) * CFrame.new(0, -0.5, 0),
		Material = Enum.Material.SmoothPlastic,
		Color = COLORS.DeckAlt,
		Parent = decoFolder,
	})
	local rampSign = anchorPart("RampSign", world(-RAMP_LENGTH + 2, 0, 9), decoFolder)
	worldSign(rampSign, 20, 5, {
		{ Name = "Title", Text = "☄️ METEOR-RUN ⬆️", Color = COLORS.Gate, Height = 0.62 },
		{ Name = "Hint", Text = "Schnell sein = Gratis-Ei! 🥚", Color = WHITE, Height = 0.38 },
	})

	-- START: Plattform, Tor, Startlinie
	deck(0, 108, 0, WIDTH, COLORS.Deck)
	gate(GATE_D, COLORS.Gate, 13)
	line(START_LINE_D, true)
	local startSign = anchorPart("StartSign", world(GATE_D, 0, TOP + 21), decoFolder)
	local labels = worldSign(startSign, 30, 9, {
		{ Name = "Title", Text = "☄️ METEOR-RUN", Color = COLORS.Gate, Height = 0.5 },
		{ Name = "Record", Text = "🏆 Rekord: noch keiner!", Color = Color3.fromRGB(255, 230, 90), Height = 0.27 },
		{ Name = "Hint", Text = "Über die Linie = Timer läuft!", Color = WHITE, Height = 0.23 },
	})
	recordLabel = labels.Record

	-- 1) LAVA-FELDER (quer, dann Slalom)
	sectionSign(22, "1/5 🔥 LAVA", "Nicht berühren – drüberspringen!", COLORS.Lava)
	lava(28, 32, -half, half)
	lava(40, 44, -half, half)
	lava(50, 62, -half, half * 0.15)
	lava(64, 76, -half * 0.15, half)
	lava(82, 87, -half, half)
	lava(92, 96, -half, half)

	-- 2) SPRÜNGE über Lücken: alle Lücken 4 Studs (mit Tempo 16 gut zu schaffen), Plattformen
	-- werden schmaler und versetzt, überlappen sich aber immer um mindestens 4 Studs (gerade springen geht)
	sectionSign(110, "2/5 🦘 SPRÜNGE", "Anlauf nehmen!", Color3.fromRGB(120, 255, 120))
	deck(112, 124, 0, WIDTH, COLORS.DeckAlt)
	deck(128, 138, 0, math.max(8, WIDTH * 0.7), COLORS.Deck)
	local jumpWidth = math.max(6, WIDTH * 0.55)
	local jumpShift = math.max(0, (jumpWidth - 4) / 2) -- Versatz: beide Plattformen überlappen um 4 Studs
	deck(142, 151, jumpShift, jumpWidth, COLORS.DeckAlt)
	deck(155, 164, -jumpShift, jumpWidth, COLORS.Deck)
	deck(168, 284, 0, WIDTH, COLORS.DeckAlt)

	-- 3) ROTIERENDE BALKEN (der Client dreht sie)
	local t0 = now()
	sectionSign(198, "3/5 🌀 BALKEN", "Timing ist alles!", COLORS.Spinner)
	local barLength = WIDTH - 1
	local function post(d: number)
		part({
			Name = "SpinnerPost",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(3, 1.4, 1.4),
			CFrame = CFrame.new(world(d, 0, TOP + 1.5)) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(60, 60, 72),
			Parent = decoFolder,
		})
	end
	-- a) Fegebalken knapp über dem Boden (drüberspringen)
	post(210)
	spinner(
		"SweeperA",
		CFrame.new(world(210, 0, TOP + 1.2)),
		CFrame.new(),
		Vector3.new(barLength, 1.2, 1.2),
		Vector3.yAxis,
		1.8,
		t0
	)
	-- b) Windmühle: ein Balken dreht sich quer über die Strecke (unten durchlaufen, wenn er oben ist)
	local millPivot = CFrame.new(world(234, 0, TOP + 7.5))
	for _, s in ipairs({ -1, 1 }) do
		part({
			Name = "MillPost",
			Size = Vector3.new(1.2, 10, 1.2),
			Position = world(235.6, s * (half + 0.8), TOP + 5),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(60, 60, 72),
			Parent = decoFolder,
		})
	end
	part({
		Name = "MillBeam",
		Size = Vector3.new(WIDTH + 2.8, 1, 1),
		Position = world(235.6, 0, TOP + 10.5),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(60, 60, 72),
		Parent = decoFolder,
	})
	part({
		Name = "MillAxle",
		Size = Vector3.new(0.8, 0.8, 1.6),
		Position = world(234.8, 0, TOP + 7.5),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 220, 60),
		CanCollide = false,
		CastShadow = false,
		Parent = decoFolder,
	})
	part({
		Name = "MillHanger",
		Size = Vector3.new(0.6, 3, 0.6),
		Position = world(235.6, 0, TOP + 9),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(60, 60, 72),
		CanCollide = false,
		Parent = decoFolder,
	})
	spinner("Windmill", millPivot, CFrame.new(), Vector3.new(barLength, 1.2, 1.2), Vector3.zAxis, 1.4, t0)
	-- c) Kreuz aus zwei Fegebalken, andersherum
	post(258)
	local crossPivot = CFrame.new(world(258, 0, TOP + 1.2))
	spinner("SweeperC1", crossPivot, CFrame.new(), Vector3.new(barLength, 1.2, 1.2), Vector3.yAxis, -1.5, t0)
	spinner(
		"SweeperC2",
		crossPivot,
		CFrame.Angles(0, math.rad(90), 0),
		Vector3.new(barLength, 1.2, 1.2),
		Vector3.yAxis,
		-1.5,
		t0
	)

	-- 4) METEOR-EINSCHLÄGE (Server bestimmt sie, Client zeigt Warnkreis + Einschlag)
	deck(284, 372, 0, WIDTH, COLORS.Deck)
	sectionSign(286, "4/5 ☄️ EINSCHLÄGE", "Raus aus den roten Kreisen!", Color3.fromRGB(255, 120, 120))
	local craterRng = Random.new(4242)
	for _ = 1, 7 do
		local d = craterRng:NextNumber(IMPACT_FROM_D + 4, IMPACT_TO_D - 4)
		local x = craterRng:NextNumber(-half + 2.5, half - 2.5)
		local size = craterRng:NextNumber(3, 4.5)
		part({
			Name = "Crater",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.05, size, size),
			CFrame = CFrame.new(world(d, x, TOP + 0.03)) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Slate,
			Color = COLORS.Crater,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
			Parent = decoFolder,
		})
	end

	-- 5) LAVA-STEINE: alles Lava, nur auf den Steinen ist man sicher
	deck(372, END_D, 0, WIDTH, COLORS.DeckAlt)
	sectionSign(374, "5/5 🔥 LAVA-STEINE", "Von Stein zu Stein!", COLORS.Lava)
	lava(376, 428, -half, half)
	local stoneFolder = folder("Stones", root)
	for i, x in ipairs({ -0.4, 0.45, -0.3, 0.5, -0.5, 0.1, -0.35, 0.3 }) do
		part({
			Name = "Stone",
			Size = Vector3.new(4, 1.4, 4),
			Position = world(374 + i * 6.5, half * x, TOP + 0.7),
			Material = Enum.Material.Slate,
			Color = COLORS.Stone,
			Parent = stoneFolder,
		})
	end
	stoneParams.FilterDescendantsInstances = { stoneFolder }

	-- CHECKPOINTS
	respawnCF[1] = CFrame.lookAt(world(START_RESPAWN_D, 0, TOP + 3.5), world(START_RESPAWN_D + 10, 0, TOP + 3.5))
	for index, d in ipairs(CHECKPOINT_D) do
		checkpointPad(index, d)
	end

	-- ZIEL: Tor, Linie, Podest mit Belohnungs-Ei, Rampe runter (Richtung Basen)
	gate(FINISH_D, COLORS.Finish, 12)
	line(FINISH_D, true)
	local finishSign = anchorPart("FinishSign", world(FINISH_D, 0, TOP + 18), decoFolder)
	worldSign(finishSign, 20, 5, {
		{ Name = "Title", Text = "🏁 ZIEL 🏁", Color = COLORS.Finish, Height = 0.62 },
		{ Name = "Hint", Text = "Gratis-Ei – dann schnell heimtragen!", Color = WHITE, Height = 0.38 },
	})
	local podiumD = 444
	part({
		Name = "Podium",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 7, 7),
		CFrame = CFrame.new(world(podiumD, 0, TOP + 1)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(255, 205, 60),
		Parent = decoFolder,
	})
	part({
		Name = "PodiumRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 7.6, 7.6),
		CFrame = CFrame.new(world(podiumD, 0, TOP + 2)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 120, 200),
		CanCollide = false,
		CastShadow = false,
		Parent = decoFolder,
	})
	local egg = part({
		Name = "RewardEgg",
		Size = Vector3.new(3, 3, 3),
		Position = world(podiumD, 0, TOP + 4.6),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(180, 80, 255),
		CanCollide = false,
		CanQuery = false,
		Parent = decoFolder,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.35, 1)
	mesh.Parent = egg
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(220, 140, 255)
	light.Range = 16
	light.Brightness = 2
	light.Shadows = false
	light.Parent = egg
	egg:SetAttribute("Bob", true) -- Client lässt es schweben und drehen
	local eggSign = anchorPart("EggSign", world(podiumD, 0, TOP + 8.5), decoFolder)
	worldSign(eggSign, 9, 2.2, {
		{ Name = "Title", Text = "🥚 Belohnungs-Ei", Color = Color3.fromRGB(230, 180, 255), Height = 1 },
	})
	-- Rampe vom Podest runter auf die Wiese (zur Seite der Basen)
	local exitTop = world(podiumD, -half, TOP)
	local exitBottom = world(podiumD, -half - RAMP_LENGTH, 0)
	part({
		Name = "ExitRamp",
		Size = Vector3.new(8, 1, (exitTop - exitBottom).Magnitude),
		CFrame = CFrame.lookAt((exitTop + exitBottom) / 2, exitTop) * CFrame.new(0, -0.5, 0),
		Material = Enum.Material.SmoothPlastic,
		Color = COLORS.DeckAlt,
		Parent = decoFolder,
	})

	-- Werte für die Prüfung
	startSpawnCF = CFrame.lookAt(world(2.5, 0, TOP + 3.5), world(12, 0, TOP + 3.5))
	readyMinZ = Z0 + READY_FROM_D
	readyMaxZ = Z0 + START_LINE_D
	finishZ = Z0 + FINISH_D
	exitMinZ = Z0 + podiumD - 6
	exitMaxZ = Z0 + podiumD + 6
	lineMinX = X0 - half - 3
	lineMaxX = X0 + half + 3
	areaMinX = X0 - AREA_SIDE
	areaMaxX = X0 + AREA_SIDE
	areaMinZ = Z0 - RAMP_LENGTH - AREA_END
	areaMaxZ = Z0 + END_D + AREA_END
	exitMinX = X0 - half - RAMP_LENGTH - 6
	local length = FINISH_D - START_LINE_D
	local fastest = (tonumber(Config.MaxWalkSpeed) or 80) * SPEED_TOLERANCE
	minRunTime = length / fastest

	root:SetAttribute("CheckpointCount", #CHECKPOINT_D)
	root:SetAttribute("Length", length)
	root:SetAttribute("MinTime", minRunTime)
	root:SetAttribute("StartCFrame", startSpawnCF)
	root.Parent = map
	return root
end

-- -------------------------------------------------------------------
-- LAUF-LOGIK
-- -------------------------------------------------------------------
local function publish(player: Player, run: RunState?)
	if run then
		player:SetAttribute("RunActive", true)
		player:SetAttribute("RunStart", if run.Phase == "Running" then run.Start else 0)
		player:SetAttribute("RunCP", run.CP)
	else
		player:SetAttribute("RunActive", false)
		player:SetAttribute("RunStart", 0)
		player:SetAttribute("RunCP", 0)
	end
end

local function teleport(player: Player, cf: CFrame)
	local character = player.Character
	if not character then
		return
	end
	character:PivotTo(cf)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.zero
	end
	Services.CarryService.NoteTeleport(player, cf.Position)
	lastPos[player] = cf.Position
	lavaAir[player] = nil
	graceUntil[player] = os.clock() + TELEPORT_GRACE
end

local function inGrace(player: Player): boolean
	return os.clock() < (graceUntil[player] or 0)
end

local function cancelRun(player: Player, text: string?)
	if not runs[player] then
		return
	end
	runs[player] = nil
	lavaAir[player] = nil
	publish(player, nil)
	if text then
		Services.EconomyService.Notify(player, text, "Info")
	end
end

local function resetToCheckpoint(player: Player, run: RunState, reason: string)
	local cf = respawnCF[run.CP + 1] or respawnCF[1]
	teleport(player, cf)
	Services.EconomyService.Effect(player, "RunReset", 0, { Reason = reason })
	notifyLimited(player, RESET_TEXT[reason] or "↩️ Zurück zum Checkpoint!", "Error")
end

-- Steht/läuft der Spieler zwischen a und b auf einem Lava-Feld? (beide Messungen am Boden)
local function touchedLava(a: Vector3, b: Vector3, stand: number): boolean
	for _, box in ipairs(lavaBoxes) do
		local ha, hb = a.Y - box.Top, b.Y - box.Top
		if ha > 0.5 and hb > 0.5 and ha <= stand + 0.6 and hb <= stand + 0.6 and segmentHitsBox(a, b, box) then
			return true
		end
	end
	return false
end

-- Über einem Lava-Feld (waagrecht)?
local function overLava(p: Vector3): boolean
	for _, box in ipairs(lavaBoxes) do
		if p.X >= box.MinX and p.X <= box.MaxX and p.Z >= box.MinZ and p.Z <= box.MaxZ then
			return true
		end
	end
	return false
end

-- Steht der Spieler auf einem Lava-Stein? (kurzer Strahl nach unten, trifft nur die Steine)
local function onStone(p: Vector3, stand: number): boolean
	return workspace:Raycast(p, Vector3.new(0, -(stand + 1.5), 0), stoneParams) ~= nil
end

-- Schwebt der Spieler über Lava? (zu lange "in der Luft" über einem Lava-Feld = Schwebe-/Flug-Cheat;
-- wer tief über der Lava steht, fängt touchedLava, wer auf einem Stein steht, ist sicher)
local function hoveringOverLava(player: Player, p: Vector3, stand: number, dt: number): boolean
	if not overLava(p) or onStone(p, stand) then
		lavaAir[player] = nil
		return false
	end
	local air = (lavaAir[player] or 0) + dt
	lavaAir[player] = air
	return air > LAVA_AIR_MAX
end

-- War der Schritt a -> b in dt Sekunden zu Fuß möglich? (sonst zählen Linien nicht)
local function plausibleStep(humanoid: Humanoid, a: Vector3, b: Vector3, dt: number): boolean
	local dx, dz = b.X - a.X, b.Z - a.Z
	local maxStep = (humanoid.WalkSpeed * STEP_FACTOR + STEP_EXTRA) * dt + STEP_SLACK
	return dx * dx + dz * dz <= maxStep * maxStep
end

local function updateRecordSign()
	local label = recordLabel
	local record = serverRecord
	if label and record then
		label.Text = "🏆 Rekord: " .. record.Name .. " – " .. formatRunTime(record.Time)
	end
end

local function rollEggRarity(luck: number, rebirths: number): string
	local pick = Util.WeightedPick(EGG_TABLE, function(item): number
		local list = Config.MeteorsByRarity[item.Rarity]
		if not Config.RaritiesByName[item.Rarity] or not list or #list == 0 then
			return 0
		end
		if rebirths < (item.MinRebirths or 0) then
			return 0
		end
		return if item.Lucky then item.Weight * luck else item.Weight
	end, rng)
	return pick.Rarity
end

-- Belohnung: Cash + Gratis-Ei zum Heimtragen (Base voll -> Verkaufswert als Cash)
local function giveReward(player: Player, data, elapsed: number, newBest: boolean): string
	local Economy = Services.EconomyService
	local cash = math.floor(
		math.max(RUN_MIN_CASH, Economy.GetIncome(player) * RUN_CASH_SECONDS)
			* (if newBest then NEW_BEST_CASH_MULT else 1)
	)
	Economy.AddCash(player, cash)
	Economy.Effect(player, "Collect", cash)
	local text = " +" .. Util.FormatCash(cash)

	local rebirths = tonumber(data.Rebirths) or 0
	local luck = 1
		+ math.clamp((PAR_TIME - elapsed) / PAR_TIME, 0, 0.6)
		+ math.min(rebirths, 10) * REBIRTH_LUCK
		+ (if newBest then 0.25 else 0)
	local Meteor = Services.MeteorService
	local def = Meteor.RandomOfRarity(rollEggRarity(luck, rebirths))
	if not def then
		return text
	end
	local entry = { Id = def.Id, Mut = Meteor.RollMutation(1), Lv = 1, Xp = 0 }
	local label = (if entry.Mut ~= "Normal" then entry.Mut .. " " else "") .. def.Name .. " (" .. def.Rarity .. ")"
	local root = aliveRoot(player)
	local canCarry = root ~= nil
		and Services.PlotService.GetPlot(player) ~= nil
		and Services.PlotService.FreeSlot(player) ~= nil
		and not Services.CarryService.IsCarrying(player)
	if root and canCarry then
		Services.CarryService.StartCarry(player, entry, {
			Source = "Ground",
			From = "Run",
			GrabPosition = root.Position,
			ScaleTimeout = true, -- langer Heimweg: Trage-Zeit wächst mit der Entfernung zur eigenen Base
		})
		if (Config.RarityIndex[def.Rarity] or 0) >= ANNOUNCE_RARITY then
			Economy.NotifyAll(
				"☄️ "
					.. player.DisplayName
					.. " hat den Meteor-Run geschafft und trägt ein "
					.. def.Rarity
					.. "-Ei heim – HAU IHN! 🔨",
				"Event"
			)
		end
		local seconds = tonumber(player:GetAttribute("CarryTimeout")) or Config.CarryTimeout
		return text .. " 🥚 " .. label .. " – TRAG ES HEIM (" .. seconds .. " s)! 🏃"
	end
	local value = math.floor(Config.MeteorValue(entry) * Config.SellRatio)
	Economy.AddCash(player, value)
	return text .. " 📦 Base voll – " .. Util.FormatCash(value) .. " statt " .. label
end

local function finishRun(player: Player, run: RunState)
	local elapsed = now() - run.Start
	runs[player] = nil
	publish(player, nil)
	local admin = Services.AdminService
	if elapsed < minRunTime and not (admin and admin.IsAdmin(player)) then
		Services.EconomyService.Notify(player, "🚫 Unmöglich schnell – dieser Run zählt nicht!", "Error")
		return
	end
	local data = Services.DataService.Get(player)
	if not data then
		return
	end
	local oldBest = tonumber(data.RunBest)
	if oldBest and (oldBest ~= oldBest or oldBest <= 0) then
		oldBest = nil
	end
	local newBest = oldBest == nil or elapsed < oldBest
	local best = elapsed
	if newBest then
		data.RunBest = math.floor(elapsed * 100 + 0.5) / 100
		player:SetAttribute("RunBest", data.RunBest)
	elseif oldBest then
		best = oldBest
	end
	if not serverRecord or elapsed < serverRecord.Time then
		serverRecord = { Name = player.DisplayName, Time = elapsed }
		updateRecordSign()
	end

	local t = now()
	local cooldownEnd = cooldownUntil[player.UserId] or 0
	local rewarded = t >= cooldownEnd
	Services.EconomyService.Effect(
		player,
		"RunFinish",
		elapsed,
		{ Time = elapsed, Best = best, NewBest = newBest, Reward = rewarded }
	)
	local timeText = "🏁 ZIEL in "
		.. formatRunTime(elapsed)
		.. "!"
		.. (if newBest then " 🏆 NEUE BESTZEIT!" else "")
	if not rewarded then
		Services.EconomyService.Notify(
			player,
			timeText .. " ⏳ Nächste Belohnung in " .. Util.FormatTime(math.ceil(cooldownEnd - t)),
			"Info"
		)
		Services.EconomyService.MarkDirty(player)
		return
	end
	cooldownUntil[player.UserId] = t + REWARD_COOLDOWN
	data.RunRewardAt = os.time() + REWARD_COOLDOWN
	player:SetAttribute("RunCooldownUntil", t + REWARD_COOLDOWN)
	local rewardText = giveReward(player, data, elapsed, newBest)
	Services.EconomyService.Notify(player, timeText .. rewardText, "Success")
	Services.EconomyService.MarkDirty(player)
end

-- Ein Prüf-Schritt für einen Spieler (alle TICK Sekunden, dt = echte Zeit seit dem letzten Schritt)
local function stepPlayer(player: Player, dt: number)
	local root, humanoid = aliveRoot(player)
	local run = runs[player]
	if not root or not humanoid then
		if run then
			cancelRun(player)
		end
		return
	end
	local pos = root.Position
	local last = lastPos[player] or pos
	lastPos[player] = pos
	if not run then
		-- Nicht im Run: Start-Tor betreten? Lava berührt? (z.B. von der Seite reingesprungen)
		if not inArea(pos) then
			return
		end
		-- Wer schnell ist, rennt in einem Takt durchs Tor UND über die Linie -> sofort "Running"
		local dashed = crossedLine(last, pos, readyMaxZ) and last.Z >= Z0 - RAMP_LENGTH
		if inReadyZone(pos) or dashed then
			if Services.CarryService.IsCarrying(player) then
				notifyLimited(player, "🎒 Mit Beute kein Run – erst nach Hause bringen!", "Error")
			elseif Services.EconomyService.IsReady(player) then
				local newRun: RunState = {
					Phase = if dashed then "Running" else "Ready",
					Start = if dashed then now() else 0,
					CP = 0,
				}
				runs[player] = newRun
				publish(player, newRun)
				Services.EconomyService.Effect(player, if dashed then "RunStart" else "RunReady", 0)
			end
		elseif
			not Services.CarryService.IsCarrying(player) -- mit Beute wird nie teleportiert
			and not inGrace(player)
			and touchedLava(last, pos, standHeight(humanoid, root))
		then
			teleport(player, startSpawnCF)
			notifyLimited(player, "🔥 Lava! Starte den Run am Tor ☄️", "Error")
		end
		return
	end

	if Services.CarryService.IsCarrying(player) then
		cancelRun(player, "🎒 Mit Beute kein Run – abgebrochen.")
		return
	end
	if not inArea(pos) then
		cancelRun(player, "☄️ Meteor-Run abgebrochen.")
		return
	end
	local move = Services.CarryService.MoveStatus(player)
	if move == "flagged" then
		cancelRun(player, "🚫 Unmöglich schnell – Run abgebrochen!")
		return
	end

	if run.Phase == "Ready" then
		if crossedLine(last, pos, readyMaxZ) then
			run.Phase = "Running"
			run.Start = now()
			publish(player, run)
			Services.EconomyService.Effect(player, "RunStart", 0)
		elseif not inReadyZone(pos) then
			cancelRun(player) -- zurück aus dem Tor gelaufen
		end
		return
	end

	-- Running
	if now() - run.Start > MAX_RUN_TIME then
		cancelRun(player, "⏰ Zu lange – Meteor-Run abgebrochen.")
		return
	end
	if inReadyZone(pos) then
		-- zurück ins Start-Tor = Neustart
		run.Phase = "Ready"
		run.Start = 0
		run.CP = 0
		publish(player, run)
		return
	end
	if inGrace(player) then
		return -- gerade zurückgesetzt: alte Positionen vor dem Teleport nicht werten
	end
	if pos.Y > TOP + MAX_HEIGHT then
		resetToCheckpoint(player, run, "fall") -- so hoch kommt man nicht (Flug-Cheat)
		return
	end
	if pos.Y < TOP - FALL_DEPTH then
		if pos.X < lineMinX and pos.Z >= exitMinZ and pos.Z <= exitMaxZ then
			cancelRun(player, "☄️ Meteor-Run abgebrochen.") -- über die Ziel-Rampe runter (ohne alle Checkpoints)
		else
			resetToCheckpoint(player, run, "fall")
		end
		return
	end
	local stand = standHeight(humanoid, root)
	if touchedLava(last, pos, stand) or hoveringOverLava(player, pos, stand, dt) then
		resetToCheckpoint(player, run, "lava")
		return
	end
	local admin = Services.AdminService
	local isAdmin = admin ~= nil and admin.IsAdmin(player) -- Admins dürfen zum Testen fliegen
	if move ~= "ok" or not (isAdmin or plausibleStep(humanoid, last, pos, dt)) then
		-- Schonzeit nach einem Teleport ("wait": Positionen werden noch nicht geprüft) oder ein
		-- unmöglich weiter Schritt -> keine Linie zählt
		return
	end
	local nextIndex = run.CP + 1
	local nextZ = checkpointZ[nextIndex]
	if nextZ and crossedLine(last, pos, nextZ) then
		run.CP = nextIndex
		publish(player, run)
		Services.EconomyService.Effect(player, "RunCheckpoint", nextIndex, {
			Position = Vector3.new(X0, TOP + 0.5, nextZ),
			Time = now() - run.Start,
		})
		return
	end
	if crossedLine(last, pos, finishZ) then
		if run.CP >= #checkpointZ then
			finishRun(player, run)
		else
			notifyLimited(player, "🚩 Du hast einen Checkpoint verpasst!", "Error")
		end
	end
end

-- -------------------------------------------------------------------
-- METEOR-EINSCHLÄGE
-- -------------------------------------------------------------------
local pendingImpacts = 0
local impactClock = 0
local runnerRoots: { BasePart } = {}

local function scheduleImpact(position: Vector3)
	pendingImpacts += 1
	Remotes.Effect:FireAllClients("RunImpact", 0, {
		Position = position,
		Radius = IMPACT_RADIUS,
		At = now() + IMPACT_WARN,
	})
	task.delay(IMPACT_WARN, function()
		pendingImpacts -= 1
		local hitRadius = IMPACT_RADIUS + 1
		for player, run in pairs(runs) do
			if run.Phase == "Running" and not inGrace(player) then
				local root = aliveRoot(player)
				if root then
					local p = root.Position
					local dx, dz = p.X - position.X, p.Z - position.Z
					if
						dx * dx + dz * dz <= hitRadius * hitRadius
						and p.Y > position.Y - 1
						and p.Y < position.Y + IMPACT_HEIGHT
					then
						resetToCheckpoint(player, run, "impact")
					end
				end
			end
		end
	end)
end

local function stepImpacts(dt: number)
	table.clear(runnerRoots)
	local zoneMin = Z0 + IMPACT_FROM_D - 10
	local zoneMax = Z0 + IMPACT_TO_D + 6
	for player, run in pairs(runs) do
		if run.Phase == "Running" and run.CP == IMPACT_AFTER_CP then
			local root = aliveRoot(player)
			if root and root.Position.Z >= zoneMin and root.Position.Z <= zoneMax then
				table.insert(runnerRoots, root)
			end
		end
	end
	if #runnerRoots == 0 then
		impactClock = 0
		return
	end
	impactClock += dt
	if impactClock < IMPACT_INTERVAL or pendingImpacts >= IMPACT_MAX then
		return
	end
	impactClock = 0
	local half = WIDTH / 2 - 1
	local x = X0 + rng:NextNumber(-half, half)
	local z = Z0 + rng:NextNumber(IMPACT_FROM_D, IMPACT_TO_D)
	if rng:NextNumber() < IMPACT_AIM_CHANCE then
		local root = runnerRoots[rng:NextInteger(1, #runnerRoots)]
		local velocity = root.AssemblyLinearVelocity
		local aim = root.Position + Vector3.new(velocity.X, 0, velocity.Z) * IMPACT_LEAD
		x = math.clamp(aim.X, X0 - half, X0 + half)
		z = math.clamp(aim.Z, Z0 + IMPACT_FROM_D, Z0 + IMPACT_TO_D)
	end
	scheduleImpact(Vector3.new(x, TOP, z))
end

-- -------------------------------------------------------------------
-- ÖFFENTLICH
-- -------------------------------------------------------------------
-- Request "GoRun": zum Start-Tor teleportieren (nicht beim Tragen)
function RunService.Teleport(player: Player): (boolean, string)
	if not runFolder then
		return false, "☄️ Der Meteor-Run ist gerade nicht da."
	end
	if Services.CarryService.IsCarrying(player) then
		return false, "Mit Beute musst du laufen! 🏃"
	end
	local root = aliveRoot(player)
	if not root then
		return false, "Kein Charakter"
	end
	if root.Anchored then
		return false, "🧊 Du bist eingefroren!"
	end
	cancelRun(player)
	teleport(player, startSpawnCF)
	return true, "☄️ Lauf durchs Tor – über der Linie startet der Timer!"
end

-- Läuft der Spieler gerade den Meteor-Run? (z.B. für andere Services)
function RunService.IsRunning(player: Player): boolean
	return runs[player] ~= nil
end

function RunService.Init(services)
	Services = services
	local map = Services.PlotService.MapFolder
	if not map then
		warn("[RunService] Keine Map – Meteor-Run wird nicht gebaut")
		return
	end
	local old = map:FindFirstChild("MeteorRun")
	if old then
		old:Destroy()
	end
	computeLayout(map)
	-- Platz schaffen: Strecke + Rampen (Bäume/Büsche weg, andere Teile melden)
	local half = WIDTH / 2
	local zMin = Z0 - RAMP_LENGTH - 2
	local zMax = Z0 + END_D + 2
	clearArea(map, Vector3.new(X0, 16, (zMin + zMax) / 2), Vector3.new(WIDTH + 8, 30, zMax - zMin))
	clearArea(map, Vector3.new(X0 - half - RAMP_LENGTH / 2 - 2, 10, Z0 + 444), Vector3.new(RAMP_LENGTH + 4, 18, 12))
	runFolder = build(map)
end

function RunService.Start()
	if not runFolder then
		return
	end
	Services.DataService.OnProfileLoaded(function(player: Player, data)
		local best = tonumber(data.RunBest)
		if best and best == best and best > 0 and best < math.huge then
			player:SetAttribute("RunBest", best)
		else
			data.RunBest = nil
		end
		-- Abklingzeit aus dem Spielstand (von einem anderen Server) übernehmen
		local rewardAt = tonumber(data.RunRewardAt)
		if rewardAt and rewardAt == rewardAt then
			local left = math.min(rewardAt - os.time(), REWARD_COOLDOWN)
			if left > 0 then
				cooldownUntil[player.UserId] = math.max(cooldownUntil[player.UserId] or 0, now() + left)
			else
				data.RunRewardAt = nil
			end
		else
			data.RunRewardAt = nil
		end
		local cooldown = cooldownUntil[player.UserId]
		if cooldown then
			player:SetAttribute("RunCooldownUntil", cooldown)
		end
	end)

	local function onPlayer(player: Player)
		publish(player, nil)
		player.CharacterAdded:Connect(function()
			cancelRun(player) -- neuer Charakter (gestorben, Reset) -> Run ist vorbei
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		runs[player] = nil
		notifyAt[player] = nil
		lastPos[player] = nil
		lavaAir[player] = nil
		graceUntil[player] = nil
	end)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(TICK)
			local clock = os.clock()
			local dt = math.clamp(clock - last, 0, 1)
			last = clock
			for _, player in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(stepPlayer, player, dt)
				if not ok then
					warn("[RunService] Fehler bei " .. player.Name .. ": " .. tostring(err))
				end
			end
			local ok, err = pcall(stepImpacts, dt)
			if not ok then
				warn("[RunService] Einschlag-Fehler: " .. tostring(err))
			end
		end
	end)
end

return RunService
