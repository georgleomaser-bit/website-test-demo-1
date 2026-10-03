-- Meteore: das LAUFBAND in der Map-Mitte (E = kaufen, Meteor fliegt automatisch in die Base),
-- die Gratis-Zone am Spawn-Platz (Gratis- und Admin-Meteore), Meteoritenschauer-Event und Server-Glück.
--
-- PERFORMANCE: Laufband-Meteore werden vom Server EINMAL am Bandstart erzeugt und NIE bewegt.
-- Jeder Client rechnet die Position selbst aus (Attribute BeltT0, BeltSpeed, BeltStart, BeltDir):
--   Position = BeltStart + BeltDir * BeltSpeed * (Serverzeit - BeltT0)
-- Der Server prüft beim Kaufen mit genau dieser Formel.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local MeteorFactory = require(script.Parent:WaitForChild("MeteorFactory"))

local MeteorService = {}
local Services

local rng = Random.new()

-- Laufband-Meteore: { Kind = "Belt", Entry, Part, Price, T0, Start, Dir, Speed, Expires, Claimed, ClientReach }
local beltRecords = {}
-- Gratis-Zone/Showcase: { Kind = "Ground", Entry, Part, Price, Position, Expires, Claimed, Landed, ClientReach }
local groundRecords = {}
local beltFolder: Folder
local groundFolder: Folder

-- Warteschlange für Laufband-Meteore (Admin-Regen etc.), damit sie sich nicht überlappen
local beltQueue = {}
local lastBeltT0 = -math.huge
local lastBeltRadius = 0
local pendingNatural = nil -- schon gewürfelter nächster Meteor, wartet auf Platz
local nextNaturalAt = 0

local BELT_GAP = 0.6 -- Mindestabstand (Studs) zwischen zwei Meteoren auf dem Band
local BELT_PROMPT_REACH_EXTRA = 8 -- großzügige Toleranz beim Kaufen (Ping, Bandbewegung)
-- Kaufen-Reichweite am Laufband: wer am Geländer steht, ist ca. 10 Studs von der Bandmitte weg
local BELT_CLIENT_REACH = 15
local FALL_TIME = 0.9 -- so lange fliegt ein Meteor vom Himmel bzw. in die Base (Client-Effekt)

local serverLuckMult = 1
local serverLuckUntil = 0
local showerUntil = 0
local nextShowerAt = 0

-- -------------------------------------------------------------------
-- GLÜCK & EVENTS
-- -------------------------------------------------------------------
local function now(): number
	return workspace:GetServerTimeNow()
end

local function publishAttributes()
	ReplicatedStorage:SetAttribute("LuckMult", serverLuckMult)
	ReplicatedStorage:SetAttribute("LuckUntil", serverLuckUntil)
	ReplicatedStorage:SetAttribute("ShowerUntil", showerUntil)
	ReplicatedStorage:SetAttribute("NextShowerAt", nextShowerAt)
end

function MeteorService.IsShowerActive(): boolean
	return showerUntil > now()
end

function MeteorService.GetLuck(): number
	local luck = 1
	if serverLuckUntil > now() then
		luck *= serverLuckMult
	end
	if MeteorService.IsShowerActive() then
		luck *= Config.ShowerLuck
	end
	return luck
end

-- Verlängert laufendes Glück, statt es zu überschreiben
function MeteorService.AddServerLuck(mult: number, seconds: number)
	local t = now()
	if serverLuckUntil > t and mult <= serverLuckMult then
		serverLuckUntil += seconds
	else
		serverLuckMult = mult
		serverLuckUntil = math.max(serverLuckUntil, t) + seconds
	end
	publishAttributes()
end

function MeteorService.SetServerLuck(mult: number, untilTime: number)
	serverLuckMult = mult
	serverLuckUntil = untilTime
	publishAttributes()
end

function MeteorService.StartShower(duration: number?)
	local t = now()
	showerUntil = math.max(showerUntil, t) + (duration or Config.ShowerDuration)
	nextShowerAt = showerUntil + Config.ShowerInterval
	publishAttributes()
	-- Im Schauer gibt es keine Locks!
	for _, plot in ipairs(Services.PlotService.Plots) do
		Services.PlotService.SetLocked(plot, 0)
	end
	Services.EconomyService.NotifyAll(
		"🌠 METEORITENSCHAUER! Viel mehr Meteore, keine Locks, " .. Config.ShowerLuck .. "x Glück!",
		"Event"
	)
end

-- -------------------------------------------------------------------
-- ZUFALL
-- -------------------------------------------------------------------
function MeteorService.RollRarity(luck: number)
	return Util.WeightedPick(Config.Rarities, function(rarity)
		if rarity.AdminOnly or #Config.MeteorsByRarity[rarity.Name] == 0 then
			return 0
		end
		local index = Config.RarityIndex[rarity.Name]
		return index >= 3 and rarity.Weight * luck or rarity.Weight
	end, rng)
end

function MeteorService.RollMutation(luck: number): string
	local mut = Util.WeightedPick(Config.Mutations, function(m)
		return m.Name == "Normal" and m.Weight or m.Weight * luck
	end, rng)
	return mut.Name
end

-- Zufälliger Meteor einer Seltenheit (nur Laufband-Meteore; includeAll = auch Admin/nicht spawnbare)
function MeteorService.RandomOfRarity(rarityName: string, includeAll: boolean?)
	local list = Config.MeteorsByRarity[rarityName]
	if (not list or #list == 0) and includeAll then
		list = Config.MeteorsByRarityAll[rarityName]
	end
	if not list or #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

function MeteorService.RandomAdminMeteor()
	local list = Config.AdminMeteors
	if #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

-- Neuer (noch nicht gekaufter) Eintrag – Hatch/Alien kommen erst beim Kaufen dazu
function MeteorService.RollEntry(luck: number?)
	local l = luck or MeteorService.GetLuck()
	local rarity = MeteorService.RollRarity(l)
	local def = MeteorService.RandomOfRarity(rarity.Name) or Config.Meteors[1]
	return { Id = def.Id, Mut = MeteorService.RollMutation(l), Lv = 1, Xp = 0 }
end

-- opts: { Id?, Mut?, Rarity? } -> Eintrag (oder nil, wenn es die Seltenheit nicht gibt)
local function makeEntry(opts)
	local entry
	local luck = MeteorService.GetLuck()
	if opts.Id and Config.MeteorsById[opts.Id] then
		entry = { Id = opts.Id, Mut = opts.Mut or MeteorService.RollMutation(luck), Lv = 1, Xp = 0 }
	elseif opts.Rarity and Config.RaritiesByName[opts.Rarity] then
		local def = MeteorService.RandomOfRarity(opts.Rarity, true)
		if not def then
			return nil
		end
		entry = { Id = def.Id, Mut = opts.Mut or MeteorService.RollMutation(luck), Lv = 1, Xp = 0 }
	else
		entry = MeteorService.RollEntry(luck)
	end
	if not Config.MutationsByName[entry.Mut] then
		entry.Mut = "Normal"
	end
	return entry
end

-- -------------------------------------------------------------------
-- LAUFBAND
-- -------------------------------------------------------------------
local beltWarned = false

-- Laufband-Daten (von MapBuilder über PlotService, sonst aus den Attributen des Belt-Parts)
local function getBelt()
	local belt = Services.PlotService.Belt
	if belt and belt.Start and belt.Dir and belt.Length then
		return belt
	end
	local map = Services.PlotService.MapFolder
	local part = map and map:FindFirstChild("Belt")
	if part and part:IsA("BasePart") then
		local start = part:GetAttribute("BeltStart")
		local dir = part:GetAttribute("BeltDir")
		local length = part:GetAttribute("BeltLength")
		if typeof(start) == "Vector3" and typeof(dir) == "Vector3" and type(length) == "number" then
			belt = { Part = part, Start = start, Dir = dir.Unit, Length = length, Width = part.Size.X }
			Services.PlotService.Belt = belt
			return belt
		end
	end
	if not beltWarned then
		beltWarned = true
		warn("[MeteorService] Kein Laufband gefunden – Meteore können nicht spawnen!")
	end
	return nil
end

function MeteorService.BeltPosition(record): Vector3
	return record.Start + record.Dir * record.Speed * (now() - record.T0)
end

local function removeRecord(record)
	local list = record.Kind == "Belt" and beltRecords or groundRecords
	local index = table.find(list, record)
	if index then
		table.remove(list, index)
	end
	if record.Part then
		record.Part:Destroy()
		record.Part = nil
	end
end

local function currentPosition(record): Vector3?
	if not record.Part then
		return nil
	end
	if record.Kind == "Belt" then
		return MeteorService.BeltPosition(record)
	end
	return record.Position
end

-- Kaufen / Schnappen: Meteor fliegt AUTOMATISCH in einen freien Slot der eigenen Base
local function tryClaim(player: Player, record)
	if record.Claimed or not record.Part or record.Landed == false then
		return
	end
	local data = Services.DataService.Get(player)
	if not data then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	local position = currentPosition(record)
	if not position then
		return
	end
	-- gleiche Reichweite wie beim Client (ClientMaxDistance) + großzügige Toleranz
	local reach = (record.ClientReach or 10) + BELT_PROMPT_REACH_EXTRA
	if record.Kind == "Belt" then
		reach += record.Speed * 0.5 -- Band bewegt sich während der Ping-Zeit weiter
	end
	if (root.Position - position).Magnitude > reach then
		Services.EconomyService.Notify(player, "🏃 Zu weit weg – lauf näher ran!", "Error")
		return
	end
	local plot = Services.PlotService.GetPlot(player)
	if not plot then
		Services.EconomyService.Notify(player, "Du hast keine Base auf diesem Server.", "Error")
		return
	end
	local slot = Services.PlotService.FreeSlot(player)
	if not slot then
		Services.EconomyService.Notify(player, "📦 Deine Base ist voll! Verkaufe etwas (F).", "Error")
		return
	end
	local def = Config.MeteorsById[record.Entry.Id]
	if record.Price > 0 then
		local rarity = Config.RaritiesByName[def.Rarity]
		local required = rarity.RequiredRebirths or 0
		if data.Rebirths < required then
			Services.EconomyService.Notify(
				player,
				"🔥 " .. def.Rarity .. " braucht " .. required .. " Rebirth(s) zum Kaufen – aber klauen geht! 😈",
				"Error"
			)
			return
		end
		if data.Cash < record.Price then
			Services.EconomyService.Notify(
				player,
				"💸 Nicht genug Cash! Du brauchst " .. Util.FormatCash(record.Price),
				"Error"
			)
			return
		end
		data.Cash -= record.Price
		data.Stats.Bought += 1
	end
	record.Claimed = true
	local entry = record.Entry
	removeRecord(record)
	Services.EconomyService.DeliverMeteor(player, plot, slot, entry, position)
	Services.EconomyService.Notify(
		player,
		(record.Price > 0 and "✅ Gekauft: " or "🎁 Geschnappt: ") .. def.Name .. "! Gleich schlüpft ein Alien 🐣",
		"Success"
	)
end

local function attachClaimPrompt(record, reach: number?)
	local def = Config.MeteorsById[record.Entry.Id]
	local action = record.Price > 0 and ("Kaufen " .. Util.FormatCash(record.Price)) or "🎁 Schnappen (GRATIS)"
	local radius = record.Part.Size.X / 2
	-- Laufband: man steht hinter dem Geländer -> größere Reichweite als am Boden
	local normalReach = record.Kind == "Belt" and math.max(BELT_CLIENT_REACH, radius + 10) or math.max(10, radius + 7)
	record.ClientReach = normalReach
	local prompt = MeteorFactory.AddPrompt(
		record.Part,
		"BuyPrompt",
		action,
		def.Name .. " (" .. def.Rarity .. ")",
		Config.GrabHoldDuration,
		Enum.KeyCode.E,
		reach or normalReach
	)
	-- Der Client stellt die echte Reichweite lokal ein (die Server-Reichweite ist beim Laufband
	-- absichtlich riesig, weil der Meteor auf dem Server am Bandstart bleibt).
	prompt:SetAttribute("ClientMaxDistance", normalReach)
	prompt.Enabled = record.Landed ~= false
	prompt.Triggered:Connect(function(player)
		tryClaim(player, record)
	end)
	return prompt
end

local function announce(entry, text: string)
	local def = Config.MeteorsById[entry.Id]
	local mut = entry.Mut ~= "Normal" and (entry.Mut .. " ") or ""
	Services.EconomyService.NotifyAll(text:format(def.Rarity .. " " .. mut .. def.Name), "Event")
end

-- Legt einen Meteor sofort an den Bandstart (ohne Platzprüfung – dafür sorgt die Schleife)
local function spawnOnBelt(entry, price: number, shouldAnnounce: boolean?)
	local belt = getBelt()
	if not belt then
		return nil
	end
	local speed = Config.BeltSpeed
	local size = MeteorFactory.GetSize(entry)
	local radius = size / 2
	local t0 = now()
	local start = belt.Start + Vector3.new(0, radius, 0)

	local part = MeteorFactory.Create(entry, "Belt", price)
	part.CFrame = CFrame.new(start)
	-- Attribute VOR dem Parenten setzen -> kommen gleichzeitig beim Client an
	part:SetAttribute("BeltT0", t0)
	part:SetAttribute("BeltSpeed", speed)
	part:SetAttribute("BeltStart", start)
	part:SetAttribute("BeltDir", belt.Dir)

	local record = {
		Kind = "Belt",
		Entry = entry,
		Part = part,
		Price = price,
		T0 = t0,
		Start = start,
		Dir = belt.Dir,
		Speed = speed,
		Expires = t0 + belt.Length / speed,
		Claimed = false,
	}
	table.insert(beltRecords, record)
	-- Server-Reichweite = ganzes Band (siehe attachClaimPrompt), echte Prüfung in tryClaim
	attachClaimPrompt(record, belt.Length + 60)
	part.Parent = beltFolder

	lastBeltT0 = t0
	lastBeltRadius = radius

	local def = Config.MeteorsById[entry.Id]
	if shouldAnnounce ~= false and Config.RarityIndex[def.Rarity] >= 6 then
		announce(entry, "☄️ Ein %s fährt aufs Laufband! 🏃")
	end
	return record
end

-- Ist am Bandstart genug Platz für einen Meteor mit diesem Radius?
local function beltHasRoom(radius: number): boolean
	local travelled = (now() - lastBeltT0) * Config.BeltSpeed
	return travelled >= lastBeltRadius + radius + BELT_GAP
end

-- opts: { Id?, Mut?, Rarity?, Free?, Announce? } -> kommt so bald wie möglich aufs Band
function MeteorService.QueueBelt(opts)
	table.insert(beltQueue, opts or {})
end

-- Ein Schritt der Laufband-Schleife: Warteschlange zuerst, dann natürliche Meteore
local function beltStep()
	local t = now()
	-- abgelaufene Meteore (über das Bandende) entfernen. Die Liste ist nach Startzeit sortiert
	-- (gleiches Tempo, gleiche Länge) -> die ältesten stehen vorne, mehr muss man nicht prüfen.
	while beltRecords[1] and t >= beltRecords[1].Expires do
		removeRecord(beltRecords[1])
	end
	if #beltRecords >= Config.MaxBeltMeteors then
		return
	end
	local queued = beltQueue[1]
	if queued then
		if not queued.Entry then
			queued.Entry = makeEntry(queued)
			if not queued.Entry then
				table.remove(beltQueue, 1)
				return
			end
		end
		if beltHasRoom(MeteorFactory.GetSize(queued.Entry) / 2) then
			table.remove(beltQueue, 1)
			local price = queued.Free and 0 or math.floor(Config.MeteorValue(queued.Entry))
			spawnOnBelt(queued.Entry, price, queued.Announce)
		end
		return
	end
	if #Players:GetPlayers() == 0 then
		return
	end
	if not pendingNatural and t >= nextNaturalAt then
		pendingNatural = MeteorService.RollEntry()
		local interval = MeteorService.IsShowerActive() and Config.ShowerBeltInterval or Config.BeltSpawnInterval
		nextNaturalAt = t + interval
	end
	if pendingNatural and beltHasRoom(MeteorFactory.GetSize(pendingNatural) / 2) then
		local entry = pendingNatural
		pendingNatural = nil
		spawnOnBelt(entry, math.floor(Config.MeteorValue(entry)))
	end
end

-- -------------------------------------------------------------------
-- GRATIS-ZONE & STATISCHE METEORE (Admin, Showcase)
-- -------------------------------------------------------------------
local function freeZone()
	local zone = Services.PlotService.FreeZone
	local center = zone and zone.Center or Vector3.new(0, 0.2, -264)
	local radius = zone and zone.Radius or 20
	return center, radius
end

local function randomFreeSpot(size: number): Vector3
	local center, radius = freeZone()
	local usable = math.max(1, radius - size / 2 - 1)
	local best = center
	for _ = 1, 12 do
		local angle = rng:NextNumber() * math.pi * 2
		local dist = math.sqrt(rng:NextNumber()) * usable
		local pos = center + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
		local free = true
		for _, record in ipairs(groundRecords) do
			if record.Part and (record.Position - pos).Magnitude < (record.Part.Size.X + size) / 2 + 1 then
				free = false
				break
			end
		end
		best = pos
		if free then
			break
		end
	end
	return best
end

-- Shake + Funken für alle in der Nähe eines Einschlags
local function impactEffect(position: Vector3, size: number, rarityName: string)
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = 0
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Visible = true
	explosion.Parent = workspace
	Remotes.Effect:FireAllClients("Hatch", 0, { Position = position, Rarity = rarityName })
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (root.Position - position).Magnitude < 60 + size * 12 then
			Services.EconomyService.Effect(player, "Shake", math.clamp(size / 6, 0.4, 1.6))
		end
	end
end

-- Statischer Meteor am Boden (Gratis-Zone, vor dem Admin, Showcase).
-- opts: { Id?, Mut?, Rarity?, Position?, Free?, Announce?, Lifetime?, Instant? }
--   Position fehlt -> zufällig in der Gratis-Zone
--   Instant = true -> liegt sofort da; sonst fällt er vom Himmel (Client-Effekt) und schlägt ein
function MeteorService.SpawnStatic(opts)
	opts = opts or {}
	local entry = makeEntry(opts)
	if not entry then
		return nil
	end
	-- Platz schaffen: älteste entfernen, wenn zu viele daliegen
	while #groundRecords >= Config.MaxFreeMeteors do
		removeRecord(groundRecords[1])
	end

	local price = opts.Free and 0 or math.floor(Config.MeteorValue(entry))
	local size = MeteorFactory.GetSize(entry)
	local spot = opts.Position or randomFreeSpot(size)
	local center = freeZone()
	local groundY = opts.Position and opts.Position.Y or center.Y
	local position = Vector3.new(spot.X, groundY + size / 2 + 0.1, spot.Z)
	local part = MeteorFactory.Create(entry, "Ground", price)
	part.CFrame = CFrame.new(position)

	local def = Config.MeteorsById[entry.Id]
	local record = {
		Kind = "Ground",
		Entry = entry,
		Part = part,
		Price = price,
		Position = position,
		Expires = os.clock() + (tonumber(opts.Lifetime) or Config.FreeMeteorLifetime),
		Claimed = false,
		Landed = opts.Instant == true,
	}
	table.insert(groundRecords, record)
	attachClaimPrompt(record)

	if opts.Announce ~= false and Config.RarityIndex[def.Rarity] >= 5 then
		announce(entry, price > 0 and "☄️ Ein %s ist gelandet!" or "🎁 Ein GRATIS %s liegt in der Gratis-Zone!")
	end

	if opts.Instant then
		part.Parent = groundFolder
		return record
	end
	-- Fall-Animation macht der Client ("Deliver" vom Himmel), danach erscheint der echte Meteor
	local sky = position + Vector3.new(rng:NextNumber(-50, 50), 220, rng:NextNumber(-50, 50))
	Remotes.Effect:FireAllClients("Deliver", 0, { From = sky, To = position, MeteorId = entry.Id, Mut = entry.Mut })
	task.delay(FALL_TIME, function()
		if record.Part ~= part or record.Claimed then
			return
		end
		part.Parent = groundFolder
		record.Landed = true
		local prompt = part:FindFirstChild("BuyPrompt")
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = true
		end
		impactEffect(position, size, def.Rarity)
	end)
	return record
end

-- Allgemeiner Spawn (Admin-Panel): opts.Where = "Belt" (Standard), "Free" (Gratis-Zone) oder Position
function MeteorService.SpawnMeteor(opts)
	opts = opts or {}
	if opts.Position or opts.Where == "Free" then
		return MeteorService.SpawnStatic(opts)
	end
	MeteorService.QueueBelt(opts)
	return nil
end

-- Laufband + Gratis-Zone leeren
function MeteorService.ClearGround()
	for i = #groundRecords, 1, -1 do
		removeRecord(groundRecords[i])
	end
	for i = #beltRecords, 1, -1 do
		removeRecord(beltRecords[i])
	end
	table.clear(beltQueue)
	pendingNatural = nil
end

function MeteorService.Init(services)
	Services = services
	local map = Services.PlotService.MapFolder or workspace
	local function getFolder(name: string): Folder
		local existing = map:FindFirstChild(name)
		if existing and existing:IsA("Folder") then
			existing:ClearAllChildren()
			return existing
		end
		local created = Instance.new("Folder")
		created.Name = name
		created.Parent = map
		return created
	end
	beltFolder = getFolder("BeltMeteors")
	groundFolder = getFolder("GroundMeteors")
	local belt = getBelt()
	if belt and belt.Part then
		belt.Part:SetAttribute("BeltSpeed", Config.BeltSpeed)
	end
end

function MeteorService.Start()
	nextShowerAt = now() + Config.ShowerInterval
	publishAttributes()

	-- Laufband-Schleife (nur Rechnen + gelegentlich ein neues Part – kein Bewegen!)
	task.spawn(function()
		while true do
			task.wait(0.05)
			local ok, err = pcall(beltStep)
			if not ok then
				warn("[MeteorService] Laufband-Fehler: " .. tostring(err))
				pendingNatural = nil
				task.wait(1)
			end
		end
	end)

	-- Gratis-Meteore verschwinden lassen + Event-Timer
	task.spawn(function()
		local wasShower = false
		while true do
			task.wait(1)
			local clock = os.clock()
			for i = #groundRecords, 1, -1 do
				local record = groundRecords[i]
				if not record.Claimed and clock > record.Expires then
					removeRecord(record)
				end
			end
			local t = now()
			if not MeteorService.IsShowerActive() and t >= nextShowerAt then
				MeteorService.StartShower()
			end
			local active = MeteorService.IsShowerActive()
			if wasShower and not active then
				Services.EconomyService.NotifyAll("Der Meteoritenschauer ist vorbei. Locks gehen wieder! 🔒", "Info")
			end
			wasShower = active
		end
	end)
end

return MeteorService
