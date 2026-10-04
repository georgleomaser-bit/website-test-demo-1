-- NESTER-FELD (Map-Mitte, MapBuilder: Ordner "NestField"): WILDE KREATUREN + SPEED-PADS
--
-- KREATUREN (Config.Creatures): laufen in ihrem Revier im Feld herum. Kommt ein Spieler zu nah
-- (AggroRange), jagen sie ihn mit festem Tempo (schneller als Grundtempo 16, langsamer als gute
-- Speed-Werte). Treffer = Schubs wie ein Schläger-Treffer (CarryService.CreatureHit), ein getragenes Ei fällt runter.
-- Niemand stirbt. Ziel weg / zu weit weg / aus dem Feld raus -> zurück ins Revier.
-- Nachts mehr und schnellere Kreaturen (NightService.IsNight). Sie verlassen das Feld NIE
-- (Grenzen = Attribute MinX/MaxX/MinZ/MaxZ am Ordner "NestField" -> betreten keine Basen).
--
-- PERFORMANCE: Der Server hat KEINE Teile für die Kreaturen. Er rechnet nur 5x pro Sekunde Positionen
-- (gerade Linien, kein Pathfinding) und schreibt pro Kreatur EIN Text-Attribut "S" an einen Ordner
-- (NestField/Creatures/Creature): "Serverzeit|x|z|vx|vz|Modus" – nur wenn sich etwas ändert.
-- Der Client baut die blockigen Monster lokal und bewegt sie weich (Vorhersage + Glätten).
-- Modus: 0 = herumlaufen, 1 = jagen, 2 = zurück ins Revier, 3 = kurze Pause nach einem Treffer
--
-- SPEED-PADS (Config.SpeedPads): drüberlaufen = Attribut "SpeedPadUntil" am Spieler, EconomyService
-- rechnet das Tempo (+50 %, Deckel MaxSpeed). Die Bewegungs-Prüfung (CarryService.MoveStatus) nimmt das
-- echte WalkSpeed – ein Boost gilt also nicht als Teleport.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local FieldService = {}
local Services

local CREATURES = Config.Creatures
local PADS = Config.SpeedPads

local TICK = 0.2 -- so oft rechnet der Server (Client glättet dazwischen)
local HOME_RADIUS = 35 -- so weit läuft eine Kreatur um ihren Revier-Mittelpunkt
local ROAM_PAUSE_MIN = 1 -- Pause zwischen zwei Wegen (Sekunden)
local ROAM_PAUSE_MAX = 3.5
local ROAM_GIVE_UP = 12 -- spätestens nach so vielen Sekunden ein neues Ziel
local RETURN_SPEED_MULT = 1.4 -- zurück ins Revier etwas schneller als herumlaufen
local HIT_PAUSE = 0.8 -- nach einem Treffer kurz stehen bleiben
local TARGET_MARGIN = 4 -- Spieler zählt bis so weit außerhalb des Reviers noch als Ziel
local MAX_TARGET_HEIGHT = 25 -- wer so hoch ist (Sprung von der Base, fliegen), wird nicht gejagt
local HIT_HEIGHT = 7 -- Treffer nur, wenn auch die Höhe passt
local SEPARATION = 6 -- Kreaturen schieben sich auseinander, wenn sie sich so nah kommen
local PUBLISH_GAP = 1 -- spätestens so oft neu senden (auch ohne Änderung)
local VEL_CHANGE = 0.6 -- Tempo-Änderung, ab der neu gesendet wird
local HIT_NOTIFY_GAP = 12 -- Hinweis "Monster!" höchstens so oft pro Spieler
local PAD_COOLDOWN = 0.4 -- Touched feuert oft: höchstens so oft pro Spieler auswerten
local PAD_REACH = 4 -- HumanoidRootPart höchstens so weit neben dem Pad-Rand (Ping, breite Avatare)
local PAD_MAX_HEIGHT = 9 -- ... und höchstens so hoch darüber (Springen)
local FALLBACK_BOUNDS = { MinX = -29, MaxX = 29, MinZ = -205, MaxZ = 240 }

type Creature = {
	Folder: Folder,
	Pos: Vector3, -- Y immer 0 (Bodenhöhe macht der Client)
	Vel: Vector3,
	Home: Vector3,
	Goal: Vector3?,
	GoalUntil: number,
	WaitUntil: number,
	Target: Player?,
	Mode: number,
	PauseUntil: number,
	AggroAfter: number,
	SentAt: number,
	SentVel: Vector3,
	SentMode: number,
}

local rng = Random.new()
local creatures: { Creature } = {}
local creatureFolder: Folder? = nil
local bounds = table.clone(FALLBACK_BOUNDS)
local hitNotifyAt: { [Player]: number } = {}
local padAt: { [Player]: number } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function isNight(): boolean
	local night = Services.NightService
	return night ~= nil and night.IsNight() == true
end

local function clampToField(pos: Vector3): Vector3
	return Vector3.new(math.clamp(pos.X, bounds.MinX, bounds.MaxX), 0, math.clamp(pos.Z, bounds.MinZ, bounds.MaxZ))
end

-- Revier-Mittelpunkte gleichmäßig über die Länge des Felds verteilen (abwechselnd links/rechts)
local function assignHomes()
	local count = #creatures
	local length = bounds.MaxZ - bounds.MinZ
	for i, creature in ipairs(creatures) do
		local z = bounds.MinZ + (i - 0.5) * length / math.max(1, count)
		local x = (if i % 2 == 0 then 1 else -1) * rng:NextNumber(4, 14)
		creature.Home = clampToField(Vector3.new(x, 0, z))
		if creature.Mode == 0 then
			creature.Goal = nil
		end
	end
end

local function publish(creature: Creature, t: number)
	local pos, vel = creature.Pos, creature.Vel
	creature.Folder:SetAttribute(
		"S",
		string.format("%.3f|%.2f|%.2f|%.2f|%.2f|%d", t, pos.X, pos.Z, vel.X, vel.Z, creature.Mode)
	)
	creature.SentAt = t
	creature.SentVel = vel
	creature.SentMode = creature.Mode
end

local function addCreature(index: number)
	local folder = Instance.new("Folder")
	folder.Name = "Creature"
	folder:SetAttribute("Look", (index - 1) % 3 + 1) -- 3 Farb-Varianten
	local start = clampToField(Vector3.new(rng:NextNumber(-10, 10), 0, rng:NextNumber(bounds.MinZ, bounds.MaxZ)))
	local creature: Creature = {
		Folder = folder,
		Pos = start,
		Vel = Vector3.zero,
		Home = start,
		Goal = nil,
		GoalUntil = 0,
		WaitUntil = 0,
		Target = nil,
		Mode = 0,
		PauseUntil = 0,
		AggroAfter = 0,
		SentAt = 0,
		SentVel = Vector3.zero,
		SentMode = 0,
	}
	publish(creature, now()) -- Attribut VOR dem Parenten -> kommt zusammen beim Client an
	folder.Parent = creatureFolder
	table.insert(creatures, creature)
end

-- Anzahl an Tag/Nacht anpassen (überzählige verschwinden – bevorzugt die, die gerade nicht jagen)
local function updateCount()
	local wanted = math.max(0, math.floor(tonumber(if isNight() then CREATURES.Night else CREATURES.Day) or 0))
	if #creatures == wanted then
		return
	end
	while #creatures < wanted do
		addCreature(#creatures + 1)
	end
	while #creatures > wanted do
		local index = #creatures
		for i = #creatures, 1, -1 do
			if creatures[i].Mode ~= 1 then
				index = i
				break
			end
		end
		local creature = table.remove(creatures, index)
		if creature then
			creature.Folder:Destroy()
		end
	end
	assignHomes()
end

-- Wen darf man jagen? Lebendig, nicht eingefroren, nicht unsichtbar/Gott-Modus, IM Feld (+ Rand)
local function collectTargets(): { { Player: Player, Root: BasePart } }
	local list = {}
	local gadgets = Services.GadgetService
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 and not root.Anchored then
			local pos = root.Position
			local inside = pos.X >= bounds.MinX - TARGET_MARGIN
				and pos.X <= bounds.MaxX + TARGET_MARGIN
				and pos.Z >= bounds.MinZ - TARGET_MARGIN
				and pos.Z <= bounds.MaxZ + TARGET_MARGIN
				and pos.Y < MAX_TARGET_HEIGHT
			local cloaked = gadgets ~= nil and gadgets.IsCloaked(player) == true
			if inside and not cloaked and player:GetAttribute("AdminGod") ~= true then
				table.insert(list, { Player = player, Root = root })
			end
		end
	end
	return list
end

local function flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function hit(creature: Creature, player: Player, root: BasePart, t: number)
	local away = root.Position - creature.Pos
	local force = tonumber(CREATURES.PushForce) or 60
	local landed = Services.CarryService.CreatureHit(player, away, force)
	creature.Target = nil
	creature.Mode = 3
	creature.PauseUntil = t + HIT_PAUSE
	creature.AggroAfter = t + (tonumber(CREATURES.HitCooldown) or 2.5)
	if landed then
		local clock = os.clock()
		if clock - (hitNotifyAt[player] or -math.huge) >= HIT_NOTIFY_GAP then
			hitNotifyAt[player] = clock
			Services.EconomyService.Notify(player, "👾 Monster! Lauf schneller!", "Error")
		end
	end
end

local function stepCreature(creature: Creature, targets, t: number, dt: number, chaseSpeed: number)
	local pos = creature.Pos
	-- Pause nach einem Treffer
	if creature.Mode == 3 then
		creature.Vel = Vector3.zero
		if t < creature.PauseUntil then
			return
		end
		creature.Mode = 2
	end
	-- Ziel noch gültig?
	local targetRoot: BasePart? = nil
	if creature.Target then
		for _, item in ipairs(targets) do
			if item.Player == creature.Target then
				targetRoot = item.Root
				break
			end
		end
		local lose = tonumber(CREATURES.LoseRange) or 40
		if not targetRoot or flatDistance(targetRoot.Position, pos) > lose then
			creature.Target = nil
			targetRoot = nil
			creature.Mode = 2
		end
	end
	-- neues Ziel: der nächste Spieler in Reichweite
	if not creature.Target and t >= creature.AggroAfter then
		local best = tonumber(CREATURES.AggroRange) or 25
		for _, item in ipairs(targets) do
			local d = flatDistance(item.Root.Position, pos)
			if d < best then
				best = d
				creature.Target = item.Player
				targetRoot = item.Root
			end
		end
		if creature.Target then
			creature.Mode = 1
		end
	end

	local goal: Vector3
	local speed: number
	if creature.Mode == 1 and targetRoot then
		local targetPos = targetRoot.Position
		if
			flatDistance(targetPos, pos) <= (tonumber(CREATURES.HitRange) or 4.5)
			and math.abs(targetPos.Y - 3) < HIT_HEIGHT
		then
			hit(creature, creature.Target :: Player, targetRoot, t)
			creature.Vel = Vector3.zero
			return
		end
		goal = clampToField(targetPos)
		speed = chaseSpeed
	elseif creature.Mode == 2 then
		goal = creature.Home
		speed = (tonumber(CREATURES.RoamSpeed) or 8) * RETURN_SPEED_MULT
		if flatDistance(goal, pos) < 3 then
			creature.Mode = 0
			creature.Goal = nil
			creature.WaitUntil = t + rng:NextNumber(ROAM_PAUSE_MIN, ROAM_PAUSE_MAX)
		end
	else
		creature.Mode = 0
		local roamGoal = creature.Goal
		if roamGoal and (flatDistance(roamGoal, pos) < 1.5 or t > creature.GoalUntil) then
			creature.Goal = nil
			roamGoal = nil
			creature.WaitUntil = t + rng:NextNumber(ROAM_PAUSE_MIN, ROAM_PAUSE_MAX)
		end
		if not roamGoal and t >= creature.WaitUntil then
			local angle = rng:NextNumber() * math.pi * 2
			local radius = math.sqrt(rng:NextNumber()) * HOME_RADIUS
			roamGoal = clampToField(creature.Home + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
			creature.Goal = roamGoal
			creature.GoalUntil = t + ROAM_GIVE_UP
		end
		if not roamGoal then
			creature.Vel = Vector3.zero
			return
		end
		goal = roamGoal
		speed = tonumber(CREATURES.RoamSpeed) or 8
	end

	local delta = Vector3.new(goal.X - pos.X, 0, goal.Z - pos.Z)
	local distance = delta.Magnitude
	if distance < 0.05 then
		creature.Vel = Vector3.zero
		return
	end
	local dir = delta / distance
	local stepLength = math.min(speed * dt, distance)
	creature.Pos = clampToField(pos + dir * stepLength)
	creature.Vel = if stepLength < distance then dir * speed else Vector3.zero
end

-- Kreaturen schieben sich sanft auseinander (sonst laufen beim Jagen alle aufeinander)
local function separate()
	for i = 1, #creatures do
		local a = creatures[i]
		for j = i + 1, #creatures do
			local b = creatures[j]
			local offset = Vector3.new(b.Pos.X - a.Pos.X, 0, b.Pos.Z - a.Pos.Z)
			local d = offset.Magnitude
			if d < SEPARATION then
				local push = if d > 0.01 then offset / d else Vector3.new(1, 0, 0)
				local amount = (SEPARATION - d) / 2
				a.Pos = clampToField(a.Pos - push * amount)
				b.Pos = clampToField(b.Pos + push * amount)
			end
		end
	end
end

local function step(dt: number)
	updateCount()
	if #creatures == 0 then
		return
	end
	local t = now()
	local targets = collectTargets()
	local chaseSpeed = tonumber(if isNight() then CREATURES.NightChaseSpeed else CREATURES.ChaseSpeed) or 21
	for _, creature in ipairs(creatures) do
		stepCreature(creature, targets, t, dt, chaseSpeed)
	end
	separate()
	for _, creature in ipairs(creatures) do
		local changed = creature.Mode ~= creature.SentMode
			or (creature.Vel - creature.SentVel).Magnitude > VEL_CHANGE
			or (creature.Vel.Magnitude > 0 and t - creature.SentAt >= PUBLISH_GAP)
			or t - creature.SentAt >= PUBLISH_GAP * 3
		if changed then
			publish(creature, t)
		end
	end
end

-- -------------------------------------------------------------------
-- SPEED-PADS
-- -------------------------------------------------------------------
local function onPadTouched(pad: BasePart, hitPart: BasePart)
	local model = hitPart:FindFirstAncestorOfClass("Model")
	local player = model and Players:GetPlayerFromCharacter(model)
	if not player then
		return
	end
	local humanoid = (model :: Model):FindFirstChildOfClass("Humanoid")
	local root = (model :: Model):FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") or root.Anchored then
		return
	end
	local clock = os.clock()
	if clock < (padAt[player] or 0) then
		return
	end
	-- Touched meldet der Client: nur zählen, wenn der Spieler wirklich auf/über dem Pad steht
	-- (sonst könnte ein Exploit den Boost von überall auslösen)
	local offset = root.Position - pad.Position
	local reach = math.max(pad.Size.X, pad.Size.Z) / 2 + PAD_REACH
	if offset.X * offset.X + offset.Z * offset.Z > reach * reach or offset.Y > PAD_MAX_HEIGHT or offset.Y < -2 then
		return
	end
	padAt[player] = clock + PAD_COOLDOWN
	local duration = math.clamp(tonumber(PADS.Duration) or 3, 0.5, 30)
	player:SetAttribute("SpeedPadUntil", now() + duration)
	Services.EconomyService.ApplySpeed(player)
	task.delay(duration + 0.05, function()
		if player.Parent and (tonumber(player:GetAttribute("SpeedPadUntil")) or 0) <= now() then
			Services.EconomyService.ApplySpeed(player)
		end
	end)
end

function FieldService.Init(services)
	Services = services
	local map = Services.PlotService.MapFolder
	local field = map and map:FindFirstChild("NestField")
	if not field then
		warn("[FieldService] Kein Nester-Feld gefunden – keine Kreaturen, keine Speed-Pads")
		return
	end
	for key in pairs(FALLBACK_BOUNDS) do
		local value = tonumber(field:GetAttribute(key))
		if value then
			bounds[key] = value
		end
	end
	local existing = field:FindFirstChild("Creatures")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Creatures" -- Name wird vom Client gesucht!
	folder.Parent = field
	creatureFolder = folder

	local pads = field:FindFirstChild("SpeedPads")
	if pads then
		for _, pad in ipairs(pads:GetChildren()) do
			if pad:IsA("BasePart") then
				pad.Touched:Connect(function(hitPart)
					onPadTouched(pad, hitPart)
				end)
			end
		end
	end
end

function FieldService.Start()
	if not creatureFolder then
		return
	end
	Players.PlayerRemoving:Connect(function(player)
		hitNotifyAt[player] = nil
		padAt[player] = nil
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(TICK)
			local clock = os.clock()
			local dt = math.min(clock - last, 0.5)
			last = clock
			if #Players:GetPlayers() > 0 then
				local ok, err = pcall(step, dt)
				if not ok then
					warn("[FieldService] Fehler: " .. tostring(err))
					task.wait(1)
				end
			end
		end
	end)
end

return FieldService
