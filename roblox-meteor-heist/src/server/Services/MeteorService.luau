-- Meteore: das FÖRDERBAND in der Map-Mitte, die Gratis-Zone am Spawn-Platz, Eier am Boden,
-- Meteoritenschauer, EGG RUSH und Server-Glück.
--
-- FÖRDERBAND: jeder Meteor hat ZWEI Knöpfe
--   E halten = KLAUEN (GrabPrompt): gratis, aber man muss ihn selbst nach Hause TRAGEN
--              (CarryService, Source = "Ground"). Klappt das nicht (Bonk, Tod, Falle, zu langsam),
--              fällt er als GRATIS-Ei auf den Boden und jeder kann ihn schnappen.
--   F        = KAUFEN (BuyPrompt): kostet Cash, fliegt automatisch in die eigene Base.
-- EIER AM BODEN ("Drop"): fallen gelassen oder vom Egg Rush – nur E = Schnappen und Tragen.
--
-- PERFORMANCE: Förderband-Meteore werden vom Server EINMAL am Bandstart erzeugt und NIE bewegt.
-- Jeder Client rechnet die Position selbst aus (Attribute BeltT0, BeltSpeed, BeltStart, BeltDir):
--   Position = BeltStart + BeltDir * BeltSpeed * (Serverzeit - BeltT0)
-- Der Server prüft beim Kaufen/Klauen mit genau dieser Formel.
-- METEORITENSCHAUER: Meteore fahren auf zwei Spuren (BeltStart seitlich versetzt), damit wirklich
-- viel mehr aufs Band passen. Jede Spur hat ihren eigenen Mindestabstand.
-- ANTI-CHEAT: Halten wird serverseitig geprüft (MeteorFactory.OnHeldTrigger), Klauen/Kaufen ist
-- pro Spieler gebremst, Eingefrorene (Falle/Admin) können nichts nehmen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local MeteorFactory = require(script.Parent:WaitForChild("MeteorFactory"))

local MeteorService = {}
local Services

local rng = Random.new()

-- Förderband-Meteore: { Kind = "Belt", Entry, Part, Price, T0, Start, Dir, Speed, Expires, Claimed, ClientReach }
local beltRecords = {}
-- Gratis-Zone/Showcase (Kaufen/Schnappen = fliegt automatisch in die Base):
--   { Kind = "Ground", Entry, Part, Price, Position, Expires, Claimed, Landed, ClientReach }
local groundRecords = {}
-- Eier am Boden zum Schnappen + Tragen (fallen gelassen / Egg Rush):
--   { Kind = "Drop", Entry, Part, Price = 0, Position, Expires, Claimed, Landed, ClientReach, EggRush }
local dropRecords = {}
local beltFolder: Folder
local groundFolder: Folder

-- Warteschlange für Förderband-Meteore (Admin-Regen etc.), damit sie sich nicht überlappen
local beltQueue = {}
-- Letzter Meteor je Spur (für den Mindestabstand). Spur 0 = Bandmitte,
-- -1 / 1 = links / rechts davon (nur im Meteoritenschauer)
local laneLast: { [number]: { T0: number, Radius: number } } = {}
local nextSideLane = 1
local pendingNatural = nil -- schon gewürfelter nächster Meteor, wartet auf Platz
local nextNaturalAt = 0

local BELT_GAP = 0.6 -- Mindestabstand (Studs) zwischen zwei Meteoren auf dem Band
local LANE_MAX_RADIUS = 2.5 -- größere Meteore fahren auch im Schauer in der Bandmitte
-- Toleranz beim Kaufen/Klauen am Band: ENTLANG des Bands großzügig (Ping, der Meteor fährt weiter),
-- QUER zum Band nur wenig mehr als beim Client (sonst klaut man vom eigenen Base-Eingang aus)
local BELT_PROMPT_REACH_EXTRA = 8
local BELT_ACROSS_EXTRA = 4
-- Eier am Boden liegen still: Spielraum nur für die Bewegung des Spielers während der Ping-Zeit
local STATIC_REACH_BASE = 2
local STATIC_REACH_PER_SPEED = 0.1 -- pro Laufgeschwindigkeit
local STATIC_REACH_MIN = 3
local STATIC_REACH_MAX = 10
-- Reichweite am Förderband: wer am Geländer steht, ist ca. 10 Studs von der Bandmitte weg
local BELT_CLIENT_REACH = 15
local FALL_TIME = 0.9 -- so lange fliegt ein Meteor vom Himmel bzw. in die Base (Client-Effekt)
-- Zwei Knöpfe am selben Meteor: Klauen oben, Kaufen darunter (Pixel), sonst liegen sie übereinander
local GRAB_UI_OFFSET = Vector2.new(0, -40)
local BUY_UI_OFFSET = Vector2.new(0, 40)
local RARE_GRAB_ANNOUNCE = Config.RarityIndex.Mythic or 6 -- ab Mythic: allen sagen, wer gerade vom Band klaut
local RARE_SPAWN_ANNOUNCE = Config.RarityIndex.Celestial or 7 -- ab Celestial: "fährt aufs Förderband"
local ADMIN_SPAWN_ANNOUNCE = Config.RarityIndex.Mythic or 6 -- vom Admin bestellte Meteore: schon ab Mythic
local RARE_ANNOUNCE_GAP = 4 -- solche Ansagen höchstens alle 4 Sekunden (sonst ist der Bildschirm voll)
-- Kaufen/Klauen/Schnappen pro Spieler höchstens so oft pro Sekunde (gegen Massen-Auslösen per Cheat)
local actionLimiter = Util.RateLimiter(6, 1)

-- Egg Rush: Eier fallen nacheinander (sieht nach Regen aus) aus dieser Höhe
local EGG_RUSH_SKY = 120
local EGG_RUSH_SPAWN_GAP = 0.08
local EGG_SPOT_TRIES = 30 -- Versuche pro Ei, einen freien Wiesen-Platz zu finden
local EGG_EDGE_MARGIN = 8 -- Abstand zum Map-Rand
local EGG_BELT_CLEARANCE = 12 -- Abstand zur Bandmitte (Geländer, Rahmen)
local EGG_PLOT_MARGIN = 3 -- Abstand zu Basen
local EGG_SPACING = 3 -- Abstand zwischen zwei Eiern
local EGG_RUSH_SHOWER_GAP = 60 -- Egg Rush nicht direkt vor/nach dem Meteoritenschauer
local SHOWER_AFTER_RUSH = 20 -- Schauer wartet, bis der Egg Rush vorbei ist (+ so viele Sekunden)
-- Ersatz-Grenzen, falls die Map keine "Boundary"-Wände hat
local FALLBACK_AREA = { MinX = -150, MaxX = 150, MinZ = -406, MaxZ = 256 }

local serverLuckMult = 1
local serverLuckUntil = 0
local showerUntil = 0
local nextShowerAt = 0
local eggRushUntil = 0
local nextEggRushAt = 0
local lastRareAnnounce = -math.huge

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
	ReplicatedStorage:SetAttribute("EggRushUntil", eggRushUntil)
	ReplicatedStorage:SetAttribute("NextEggRushAt", nextEggRushAt)
end

-- Ansage an alle für seltene Eier (Förderband, Klauen) – höchstens alle RARE_ANNOUNCE_GAP Sekunden,
-- überzählige fallen weg (sonst verdrängen sie wichtige eigene Meldungen wie den Diebstahl-Alarm)
local function rareAnnounce(text: string)
	local t = os.clock()
	if t - lastRareAnnounce < RARE_ANNOUNCE_GAP then
		return
	end
	lastRareAnnounce = t
	Services.EconomyService.NotifyAll(text, "Event")
end

function MeteorService.IsShowerActive(): boolean
	return showerUntil > now()
end

function MeteorService.IsEggRushActive(): boolean
	return eggRushUntil > now()
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
	-- Im Schauer gibt es keine Locks! (Ein gekauftes Base-Schild bleibt aber an.)
	for _, plot in ipairs(Services.PlotService.Plots) do
		if not Services.PlotService.IsShielded(plot) then
			Services.PlotService.SetLocked(plot, 0)
		end
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

-- Zufälliger Meteor einer Seltenheit (nur Förderband-Meteore; includeAll = auch Admin/nicht spawnbare)
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

-- Neuer (noch nicht gekaufter) Eintrag – Hatch/Alien kommen erst in der Base dazu
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
-- FÖRDERBAND – Grundlagen
-- -------------------------------------------------------------------
local beltWarned = false

-- Förderband-Daten (von MapBuilder über PlotService, sonst aus den Attributen des Belt-Parts)
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
		warn("[MeteorService] Kein Förderband gefunden – Meteore können nicht spawnen!")
	end
	return nil
end

function MeteorService.BeltPosition(record): Vector3
	return record.Start + record.Dir * record.Speed * (now() - record.T0)
end

local function listFor(kind: string)
	if kind == "Belt" then
		return beltRecords
	elseif kind == "Drop" then
		return dropRecords
	end
	return groundRecords
end

local function removeRecord(record)
	local list = listFor(record.Kind)
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

-- -------------------------------------------------------------------
-- KAUFEN / KLAUEN / SCHNAPPEN (alles serverseitig geprüft)
-- -------------------------------------------------------------------
local function aliveRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return root
end

-- Eingefroren (Falle / Admin-Freeze = HumanoidRootPart verankert)? Dann wird nichts genommen.
local function isFrozen(player: Player, root: BasePart): boolean
	if root.Anchored then
		Services.EconomyService.Notify(player, "🧊 Du bist eingefroren!", "Error")
		return true
	end
	return false
end

-- Liegt diese Stelle in einer gesperrten Base (Lock oder Base-Schild)? -> diese Base, sonst nil
local function lockedPlotAt(position: Vector3)
	local Plot = Services.PlotService
	for _, plot in ipairs(Plot.Plots) do
		if plot.Owner and Plot.IsInside(plot, position) and Plot.IsLocked(plot) then
			return plot
		end
	end
	return nil
end

-- Steht der Spieler nah genug dran (analytisch, mit Toleranz) und hat sich nicht unmöglich schnell
-- bewegt? Gibt die aktuelle Meteor-Position zurück, sonst nil (Hinweis wurde dann schon geschickt).
local function checkReach(player: Player, record, root: BasePart): Vector3?
	local position = currentPosition(record)
	if not position then
		return nil
	end
	-- Grundlage: gleiche Reichweite wie beim Client (ClientMaxDistance)
	local clientReach = record.ClientReach or 10
	local offset = root.Position - position
	local tooFar
	if record.Kind == "Belt" then
		-- entlang des Bands großzügig (der Meteor fährt während der Ping-Zeit weiter),
		-- quer zum Band nur wenig mehr als beim Client
		local along = offset:Dot(record.Dir)
		local across = (offset - record.Dir * along).Magnitude
		tooFar = math.abs(along) > clientReach + BELT_PROMPT_REACH_EXTRA + record.Speed * 0.5
			or across > clientReach + BELT_ACROSS_EXTRA
	else
		-- liegt still: nur Spielraum für die eigene Bewegung (schnelle Spieler etwas mehr)
		local character = root.Parent
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local walkSpeed = if humanoid then humanoid.WalkSpeed else Config.NormalWalkSpeed
		local extra =
			math.clamp(STATIC_REACH_BASE + walkSpeed * STATIC_REACH_PER_SPEED, STATIC_REACH_MIN, STATIC_REACH_MAX)
		tooFar = offset.Magnitude > clientReach + extra
	end
	if tooFar then
		Services.EconomyService.Notify(player, "🏃 Zu weit weg – lauf näher ran!", "Error")
		return nil
	end
	-- Die Position kommt vom Client: wer gerade unmöglich weit "gesprungen" ist (Teleport-Exploit),
	-- darf nicht kaufen/klauen. (Server-Teleports wie Home sind erlaubt, danach kurz warten.)
	if Services.CarryService.MoveStatus(player) ~= "ok" then
		Services.EconomyService.Notify(player, "⏳ Kurz warten und nochmal versuchen!", "Error")
		return nil
	end
	return position
end

-- KAUFEN (Förderband, F) / Schnappen in der Gratis-Zone: fliegt AUTOMATISCH in einen freien Slot
local function tryClaim(player: Player, record)
	if record.Claimed or not record.Part or record.Landed == false then
		return
	end
	if not actionLimiter.Check(player) then
		return -- zu viele Versuche auf einmal (Cheat) -> still ignorieren
	end
	local data = Services.DataService.Get(player)
	if not data or not Services.EconomyService.IsReady(player) then
		return
	end
	local root = aliveRoot(player)
	if not root or isFrozen(player, root) then
		return
	end
	local position = checkReach(player, record, root)
	if not position then
		return
	end
	local plot = Services.PlotService.GetPlot(player)
	if not plot then
		Services.EconomyService.Notify(player, "Du hast keine Base auf diesem Server.", "Error")
		return
	end
	local slot = Services.PlotService.FreeSlot(player)
	if not slot then
		Services.EconomyService.Notify(player, "📦 Deine Base ist voll! Verkaufe erst etwas.", "Error")
		return
	end
	local def = Config.MeteorsById[record.Entry.Id]
	if record.Price > 0 then
		-- Rebirth-Anforderung gilt nur fürs KAUFEN – klauen geht immer
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
				"💸 Nicht genug Cash! Du brauchst "
					.. Util.FormatCash(record.Price)
					.. " – oder klau ihn gratis! 😈",
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

-- KLAUEN vom Förderband (E) / Schnappen eines Eis am Boden: gratis, aber selbst nach Hause tragen
local function tryGrab(player: Player, record)
	if record.Claimed or not record.Part or record.Landed == false then
		return
	end
	if not actionLimiter.Check(player) then
		return -- zu viele Versuche auf einmal (Cheat) -> still ignorieren
	end
	local data = Services.DataService.Get(player)
	if not data or not Services.EconomyService.IsReady(player) then
		return
	end
	local root = aliveRoot(player)
	if not root or isFrozen(player, root) then
		return
	end
	if Services.CarryService.IsCarrying(player) then
		Services.EconomyService.Notify(player, "🎒 Du trägst schon etwas – erst nach Hause bringen!", "Error")
		return
	end
	local plot = Services.PlotService.GetPlot(player)
	if not plot then
		Services.EconomyService.Notify(player, "Du hast keine Base auf diesem Server.", "Error")
		return
	end
	if not Services.PlotService.FreeSlot(player) then
		Services.EconomyService.Notify(player, "📦 Deine Base ist voll! Verkaufe erst etwas.", "Error")
		return
	end
	if record.Kind == "Drop" then
		-- Ei liegt in einer gesperrten Base (Lock / Base-Schild): nur der Besitzer darf es nehmen
		local lockedPlot = lockedPlotAt(record.Position)
		if lockedPlot and lockedPlot.Owner ~= player then
			Services.EconomyService.Notify(player, "🔒 Das Ei liegt in einer gesperrten Base!", "Error")
			return
		end
	end
	local position = checkReach(player, record, root)
	if not position then
		return
	end
	record.Claimed = true
	local entry = record.Entry
	local fromBelt = record.Kind == "Belt"
	removeRecord(record)
	Services.CarryService.StartCarry(player, entry, {
		Source = "Ground",
		From = fromBelt and "Belt" or "Drop",
		GrabPosition = position,
	})
	local def = Config.MeteorsById[entry.Id]
	if fromBelt and def and Config.RarityIndex[def.Rarity] >= RARE_GRAB_ANNOUNCE then
		local mut = entry.Mut ~= "Normal" and (entry.Mut .. " ") or ""
		rareAnnounce(
			"😈 "
				.. player.DisplayName
				.. " klaut "
				.. def.Rarity
				.. " "
				.. mut
				.. def.Name
				.. " vom Band – BONK IHN! 🔨"
		)
	end
end

-- -------------------------------------------------------------------
-- PROMPTS
-- -------------------------------------------------------------------
-- Förderband: E = Klauen (gratis, tragen), F = Kaufen (automatische Lieferung)
local function attachBeltPrompts(record, serverReach: number)
	local part: BasePart = record.Part
	local def = Config.MeteorsById[record.Entry.Id]
	local radius = part.Size.X / 2
	-- man steht hinter dem Geländer -> größere Reichweite als am Boden
	local clientReach = math.max(BELT_CLIENT_REACH, radius + 10)
	record.ClientReach = clientReach

	local grab = MeteorFactory.AddPrompt(
		part,
		"GrabPrompt",
		"Klauen",
		def.Name,
		Config.BeltGrabHold,
		Enum.KeyCode.E,
		serverReach
	)
	grab.GamepadKeyCode = Enum.KeyCode.ButtonX
	grab.UIOffset = GRAB_UI_OFFSET
	-- Der Client stellt die echte Reichweite lokal ein (die Server-Reichweite ist absichtlich riesig,
	-- weil der Meteor auf dem Server am Bandstart bleibt).
	grab:SetAttribute("ClientMaxDistance", clientReach)
	-- gratis -> der Server prüft, ob wirklich so lange gehalten wurde
	MeteorFactory.OnHeldTrigger(grab, function(player)
		tryGrab(player, record)
	end)

	local action = record.Price > 0 and ("Kaufen " .. Util.FormatCash(record.Price)) or "🎁 Gratis holen"
	local buy = MeteorFactory.AddPrompt(
		part,
		"BuyPrompt",
		action,
		def.Name .. " (" .. def.Rarity .. ")",
		Config.BeltBuyHold,
		Enum.KeyCode.F,
		serverReach
	)
	buy.GamepadKeyCode = Enum.KeyCode.ButtonY
	buy.UIOffset = BUY_UI_OFFSET
	buy:SetAttribute("ClientMaxDistance", clientReach)
	buy.Triggered:Connect(function(player)
		tryClaim(player, record)
	end)
end

-- Gratis-Zone / Showcase: E = Kaufen bzw. Schnappen (automatische Lieferung)
local function attachClaimPrompt(record)
	local def = Config.MeteorsById[record.Entry.Id]
	local action = record.Price > 0 and ("Kaufen " .. Util.FormatCash(record.Price)) or "🎁 Schnappen (GRATIS)"
	local reach = math.max(10, record.Part.Size.X / 2 + 7)
	record.ClientReach = reach
	local prompt = MeteorFactory.AddPrompt(
		record.Part,
		"BuyPrompt",
		action,
		def.Name .. " (" .. def.Rarity .. ")",
		Config.GrabHoldDuration,
		Enum.KeyCode.E,
		reach
	)
	prompt:SetAttribute("ClientMaxDistance", reach)
	prompt.Enabled = record.Landed ~= false
	local function onClaim(player: Player)
		tryClaim(player, record)
	end
	if record.Price > 0 then
		prompt.Triggered:Connect(onClaim) -- wer bezahlt, braucht keine Halte-Prüfung
	else
		MeteorFactory.OnHeldTrigger(prompt, onClaim) -- gratis -> wirklich halten
	end
	return prompt
end

-- Ei am Boden: nur E = Schnappen (dann selbst nach Hause tragen)
local function attachDropPrompt(record)
	local def = Config.MeteorsById[record.Entry.Id]
	local reach = math.max(10, record.Part.Size.X / 2 + 7)
	record.ClientReach = reach
	local prompt = MeteorFactory.AddPrompt(
		record.Part,
		"GrabPrompt",
		"Schnappen",
		def.Name,
		Config.GroundGrabHold,
		Enum.KeyCode.E,
		reach
	)
	prompt:SetAttribute("ClientMaxDistance", reach)
	prompt.Enabled = record.Landed ~= false
	MeteorFactory.OnHeldTrigger(prompt, function(player)
		tryGrab(player, record)
	end)
	return prompt
end

local function enablePrompts(part: BasePart)
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("ProximityPrompt") then
			child.Enabled = true
		end
	end
end

local function announce(entry, text: string)
	local def = Config.MeteorsById[entry.Id]
	local mut = entry.Mut ~= "Normal" and (entry.Mut .. " ") or ""
	Services.EconomyService.NotifyAll(text:format(def.Rarity .. " " .. mut .. def.Name), "Event")
end

-- -------------------------------------------------------------------
-- FÖRDERBAND – Spawnen
-- -------------------------------------------------------------------
-- Legt einen Meteor sofort an den Bandstart der Spur "lane" (ohne Platzprüfung – dafür sorgt die Schleife).
-- lane: 0 = Bandmitte, -1 / 1 = Schauer-Spuren links / rechts
-- shouldAnnounce: nil = natürlicher Meteor (Ansage ab Celestial, gebremst), true = vom Admin bestellt
local function spawnOnBelt(entry, price: number, lane: number, shouldAnnounce: boolean?)
	local belt = getBelt()
	if not belt then
		return nil
	end
	local speed = Config.BeltSpeed
	local size = MeteorFactory.GetSize(entry)
	local radius = size / 2
	local t0 = now()
	local side = belt.Dir:Cross(Vector3.yAxis) -- waagrecht quer zum Band
	local start = belt.Start + Vector3.new(0, radius, 0) + side * (lane * Config.BeltLaneOffset)

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
	-- Server-Reichweite = ganzes Band (siehe attachBeltPrompts), echte Prüfung in checkReach
	attachBeltPrompts(record, belt.Length + 60)
	part.Parent = beltFolder

	laneLast[lane] = { T0 = t0, Radius = radius }

	local def = Config.MeteorsById[entry.Id]
	local index = Config.RarityIndex[def.Rarity]
	if shouldAnnounce == true and index >= ADMIN_SPAWN_ANNOUNCE then
		announce(entry, "☄️ Ein %s fährt aufs Förderband!")
	elseif shouldAnnounce == nil and index >= RARE_SPAWN_ANNOUNCE then
		local mut = entry.Mut ~= "Normal" and (entry.Mut .. " ") or ""
		rareAnnounce("☄️ Ein " .. def.Rarity .. " " .. mut .. def.Name .. " fährt aufs Förderband!")
	end
	return record
end

-- Ist am Bandstart der Spur "lane" genug Platz für einen Meteor mit diesem Radius?
-- Geprüft wird gegen den letzten Meteor JEDER Spur: Kugeln auf Nachbarspuren berühren sich nur,
-- wenn sie seitlich näher sind als ihre Radien zusammen.
local function laneHasRoom(lane: number, radius: number): boolean
	local t = now()
	for otherLane, last in pairs(laneLast) do
		local apart = math.abs(otherLane - lane) * Config.BeltLaneOffset
		local needed = last.Radius + radius + BELT_GAP
		if apart < needed then
			local alongNeeded = math.sqrt(needed * needed - apart * apart)
			if (t - last.T0) * Config.BeltSpeed < alongNeeded then
				return false
			end
		end
	end
	return true
end

-- Freie Spur für einen Meteor mit diesem Radius (nil = gerade kein Platz, kurz warten).
-- Normal: Bandmitte. Im Meteoritenschauer: kleine Meteore abwechselnd links/rechts, große in die Mitte.
local function pickLane(radius: number): number?
	if not MeteorService.IsShowerActive() or radius > LANE_MAX_RADIUS then
		return if laneHasRoom(0, radius) then 0 else nil
	end
	for _ = 1, 2 do
		local lane = nextSideLane
		nextSideLane = -nextSideLane
		if laneHasRoom(lane, radius) then
			return lane
		end
	end
	return nil
end

-- opts: { Id?, Mut?, Rarity?, Free?, Announce? } -> kommt so bald wie möglich aufs Band
-- (Announce = true: allen ansagen, ab Mythic)
function MeteorService.QueueBelt(opts)
	table.insert(beltQueue, opts or {})
end

-- Ein Schritt der Förderband-Schleife: Warteschlange zuerst, dann natürliche Meteore
local function beltStep()
	local t = now()
	-- abgelaufene Meteore (über das Bandende) entfernen. Die Liste ist nach Startzeit sortiert
	-- (gleiches Tempo, gleiche Länge) -> die ältesten stehen vorne, mehr muss man nicht prüfen.
	while beltRecords[1] and t >= beltRecords[1].Expires do
		removeRecord(beltRecords[1])
	end
	local shower = MeteorService.IsShowerActive()
	local cap = if shower then math.max(Config.MaxBeltMeteors, Config.ShowerMaxBeltMeteors) else Config.MaxBeltMeteors
	if #beltRecords >= cap then
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
		local lane = pickLane(MeteorFactory.GetSize(queued.Entry) / 2)
		if lane then
			table.remove(beltQueue, 1)
			local price = queued.Free and 0 or math.floor(Config.MeteorValue(queued.Entry))
			-- vom Admin bestellt: Announce true/false, sonst (z.B. Meteorregen) keine Ansage
			spawnOnBelt(queued.Entry, price, lane, queued.Announce == true)
		end
		return
	end
	if #Players:GetPlayers() == 0 then
		return
	end
	if not pendingNatural and t >= nextNaturalAt then
		pendingNatural = MeteorService.RollEntry()
		local interval = if shower then Config.ShowerBeltInterval else Config.BeltSpawnInterval
		nextNaturalAt = t + interval
	end
	if pendingNatural then
		local lane = pickLane(MeteorFactory.GetSize(pendingNatural) / 2)
		if lane then
			local entry = pendingNatural
			pendingNatural = nil
			spawnOnBelt(entry, math.floor(Config.MeteorValue(entry)), lane, nil)
		end
	end
end

-- -------------------------------------------------------------------
-- BODEN: Raycasts
-- -------------------------------------------------------------------
-- Spieler und Meteore ignorieren (die Liste wird bei jedem Aufruf neu gefüllt)
local function rayParams(respectCanCollide: boolean): RaycastParams
	local ignore: { Instance } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	if beltFolder then
		table.insert(ignore, beltFolder)
	end
	if groundFolder then
		table.insert(ignore, groundFolder)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = respectCanCollide
	return params
end

-- Boden unter einer Position (nur begehbare Teile). Nichts gefunden -> Höhe 0 (Wiese)
local function groundBelow(position: Vector3): Vector3
	local result = workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -80, 0), rayParams(true))
	if result then
		return result.Position
	end
	return Vector3.new(position.X, 0, position.Z)
end

-- -------------------------------------------------------------------
-- EIER AM BODEN (fallen gelassen / Egg Rush)
-- -------------------------------------------------------------------
-- Legt ein Ei auf den Boden. groundPos = Punkt AUF dem Boden.
-- opts: { From: Vector3?, SkyHeight: number?, Lifetime: number?, EggRush: boolean? }
--   From/SkyHeight -> fällt sichtbar dorthin (Client-Effekt "Deliver"), sonst liegt es sofort da
local function spawnDrop(entry, groundPos: Vector3, opts)
	while #dropRecords >= Config.MaxDroppedMeteors do
		removeRecord(dropRecords[1]) -- älteste weg
	end
	local size = MeteorFactory.GetSize(entry)
	local position = Vector3.new(groundPos.X, groundPos.Y + size / 2 + 0.1, groundPos.Z)
	local part = MeteorFactory.Create(entry, "Ground", 0)
	part.CFrame = CFrame.new(position)

	local record = {
		Kind = "Drop",
		Entry = entry,
		Part = part,
		Price = 0,
		Position = position,
		Expires = os.clock() + math.max(1, tonumber(opts.Lifetime) or Config.DroppedLifetime),
		Claimed = false,
		Landed = false,
		EggRush = opts.EggRush == true,
	}
	table.insert(dropRecords, record)
	attachDropPrompt(record)

	local from: Vector3? = opts.From
	if not from and opts.SkyHeight then
		from = position + Vector3.new(0, opts.SkyHeight, 0)
	end
	local function land()
		if record.Part ~= part or record.Claimed then
			return -- schon weg (abgelaufen, Admin hat aufgeräumt ...)
		end
		part.Parent = groundFolder
		record.Landed = true
		enablePrompts(part)
	end
	if from then
		Remotes.Effect:FireAllClients("Deliver", 0, {
			From = from,
			To = position,
			MeteorId = entry.Id,
			Mut = entry.Mut,
		})
		task.delay(FALL_TIME, land)
	else
		land()
	end
	return record
end

-- Stelle über dem Förderband (oder im Geländer)? -> seitlich daneben auf die Wiese schieben.
-- Sonst läge das Ei still auf dem Band, während die anderen Meteore hindurchfahren.
local DROP_BELT_MARGIN = 3 -- so weit neben der Lauffläche zählt noch als "auf dem Band"
local DROP_BELT_GAP = 5 -- so weit neben der Lauffläche landet das Ei (plus sein Radius)
local function offBelt(position: Vector3, radius: number): Vector3
	local belt = getBelt()
	if not belt then
		return position
	end
	local halfWidth = (tonumber(belt.Width) or 14) / 2
	local rel = Vector3.new(position.X - belt.Start.X, 0, position.Z - belt.Start.Z)
	local along = rel:Dot(belt.Dir)
	local sideVec = rel - belt.Dir * along
	local side = sideVec.Magnitude
	if along < -2 or along > belt.Length + 2 or side >= halfWidth + DROP_BELT_MARGIN then
		return position
	end
	local outward = if side > 0.05 then sideVec.Unit else belt.Dir:Cross(Vector3.yAxis).Unit
	local target = belt.Start + belt.Dir * along + outward * (halfWidth + DROP_BELT_GAP + radius)
	return Vector3.new(target.X, position.Y, target.Z)
end

-- Getragenes Ei fällt zu Boden (gebonkt, gestorben, Falle, zu langsam ...). Es liegt dann GRATIS da
-- und JEDER kann es schnappen. position = ungefähre Stelle (der Boden darunter wird gesucht),
-- from = optional: von hier fällt es sichtbar herunter (z.B. über dem Kopf des Trägers).
function MeteorService.DropMeteor(entry, position: Vector3, from: Vector3?)
	if type(entry) ~= "table" or not Config.MeteorsById[entry.Id] or typeof(position) ~= "Vector3" then
		return nil
	end
	local clean = {
		Id = entry.Id,
		Mut = Config.MutationsByName[entry.Mut] and entry.Mut or "Normal",
		Lv = math.clamp(math.floor(tonumber(entry.Lv) or 1), 1, Config.MaxLevel),
		Xp = 0,
		Alien = entry.Alien,
	}
	local spot = offBelt(position, MeteorFactory.GetSize(clean) / 2)
	return spawnDrop(clean, groundBelow(spot), { From = from, Lifetime = Config.DroppedLifetime })
end

-- Spielfläche aus den unsichtbaren Randwänden der Map (sonst Ersatz-Grenzen).
-- Wände links/rechts sind in X dünn, vorne/hinten in Z dünn; gerechnet wird mit den Innenkanten.
local areaCache = nil
local function mapArea()
	if areaCache then
		return areaCache
	end
	local map = Services.PlotService.MapFolder
	local xWalls: { BasePart } = {}
	local zWalls: { BasePart } = {}
	if map then
		for _, child in ipairs(map:GetChildren()) do
			if child.Name == "Boundary" and child:IsA("BasePart") then
				table.insert(child.Size.X < child.Size.Z and xWalls or zWalls, child)
			end
		end
	end
	local area = table.clone(FALLBACK_AREA)
	if #xWalls >= 2 and #zWalls >= 2 then
		table.sort(xWalls, function(a, b)
			return a.Position.X < b.Position.X
		end)
		table.sort(zWalls, function(a, b)
			return a.Position.Z < b.Position.Z
		end)
		local low, high = xWalls[1], xWalls[#xWalls]
		local back, front = zWalls[1], zWalls[#zWalls]
		local candidate = {
			MinX = low.Position.X + low.Size.X / 2,
			MaxX = high.Position.X - high.Size.X / 2,
			MinZ = back.Position.Z + back.Size.Z / 2,
			MaxZ = front.Position.Z - front.Size.Z / 2,
		}
		if candidate.MinX < candidate.MaxX and candidate.MinZ < candidate.MaxZ then
			area = candidate
		end
	end
	areaCache = area
	return area
end

-- Freier Platz auf der Wiese: innerhalb der Map, nicht in/an Basen, nicht am Förderband,
-- nicht auf dem Spawn-Platz/Bäumen (der Strahl muss genau den Wiesenboden "Ground" treffen).
local function findEggSpot(radius: number, groundPart: BasePart, params: RaycastParams): Vector3?
	local area = mapArea()
	local margin = EGG_EDGE_MARGIN + radius
	if area.MaxX - area.MinX <= margin * 2 or area.MaxZ - area.MinZ <= margin * 2 then
		return nil
	end
	local belt = getBelt()
	for _ = 1, EGG_SPOT_TRIES do
		local x = rng:NextNumber(area.MinX + margin, area.MaxX - margin)
		local z = rng:NextNumber(area.MinZ + margin, area.MaxZ - margin)
		local flatPos = Vector3.new(x, 0, z)
		local ok = true
		if belt then
			local rel = flatPos - Vector3.new(belt.Start.X, 0, belt.Start.Z)
			local along = rel:Dot(belt.Dir)
			local side = (rel - belt.Dir * along).Magnitude
			if along > -20 and along < belt.Length + 20 and side < EGG_BELT_CLEARANCE + radius then
				ok = false
			end
		end
		if ok then
			for _, plot in ipairs(Services.PlotService.Plots) do
				local half = (plot.HalfSize or 36) + radius + EGG_PLOT_MARGIN
				local localPos = plot.CFrame:PointToObjectSpace(flatPos)
				if math.abs(localPos.X) <= half and math.abs(localPos.Z) <= half then
					ok = false
					break
				end
			end
		end
		if ok then
			for _, record in ipairs(dropRecords) do
				local other = record.Position
				local otherRadius = record.Part and record.Part.Size.X / 2 or 2
				local dx, dz = other.X - x, other.Z - z
				local minDist = radius + otherRadius + EGG_SPACING
				if dx * dx + dz * dz < minDist * minDist then
					ok = false
					break
				end
			end
		end
		if ok then
			local result = workspace:Raycast(Vector3.new(x, 80, z), Vector3.new(0, -120, 0), params)
			if result and result.Instance == groundPart then
				return result.Position
			end
		end
	end
	return nil
end

-- 🥚 EGG RUSH: Config.EggRushCount Gratis-Eier (3x Glück) regnen auf die ganze Wiese.
-- Läuft schon einer, wird er verlängert und es kommen noch mehr Eier dazu.
-- duration/count optional (Standard aus Config). Gibt die Anzahl der geplanten Eier zurück.
function MeteorService.StartEggRush(duration: number?, count: number?): number
	local t = now()
	local map = Services.PlotService.MapFolder
	local groundPart = map and map:FindFirstChild("Ground")
	if not groundPart or not groundPart:IsA("BasePart") then
		warn("[MeteorService] Egg Rush: Wiesenboden 'Ground' nicht gefunden – keine Eier")
		nextEggRushAt = t + Config.EggRushInterval
		publishAttributes()
		return 0
	end
	local length = math.clamp(tonumber(duration) or Config.EggRushDuration, 5, 600)
	local amount = math.clamp(math.floor(tonumber(count) or Config.EggRushCount), 1, Config.MaxDroppedMeteors)
	eggRushUntil = math.max(eggRushUntil, t + length)
	nextEggRushAt = eggRushUntil + Config.EggRushInterval
	publishAttributes()
	-- Eier eines laufenden Rush bleiben so lange liegen wie der verlängerte Rush
	local clock = os.clock()
	for _, record in ipairs(dropRecords) do
		if record.EggRush then
			record.Expires = math.max(record.Expires, clock + (eggRushUntil - t))
		end
	end
	Services.EconomyService.NotifyAll("🥚 EGG RUSH! Überall liegen Eier – der Schnellste gewinnt!", "Event")

	task.spawn(function()
		-- Bäume/Büsche sollen auch treffen (dann ist dort kein Platz) -> CanCollide nicht beachten
		local params = rayParams(false)
		for _ = 1, amount do
			local remaining = eggRushUntil - now()
			if remaining <= 1 then
				break
			end
			local entry = MeteorService.RollEntry(MeteorService.GetLuck() * Config.EggRushLuck)
			local spot = findEggSpot(MeteorFactory.GetSize(entry) / 2, groundPart, params)
			if spot then
				spawnDrop(entry, spot, { SkyHeight = EGG_RUSH_SKY, Lifetime = remaining, EggRush = true })
			end
			task.wait(EGG_RUSH_SPAWN_GAP)
		end
	end)
	return amount
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
		enablePrompts(part)
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

-- Förderband, Gratis-Zone und alle Eier am Boden leeren
function MeteorService.ClearGround()
	for i = #groundRecords, 1, -1 do
		removeRecord(groundRecords[i])
	end
	for i = #dropRecords, 1, -1 do
		removeRecord(dropRecords[i])
	end
	for i = #beltRecords, 1, -1 do
		removeRecord(beltRecords[i])
	end
	table.clear(beltQueue)
	table.clear(laneLast)
	pendingNatural = nil
end

-- -------------------------------------------------------------------
-- EVENT-TIMER (Schauer + Egg Rush, zeitlich versetzt)
-- -------------------------------------------------------------------
local function eventStep()
	local t = now()
	-- Meteoritenschauer: wartet, bis ein laufender Egg Rush vorbei ist
	if not MeteorService.IsShowerActive() and t >= nextShowerAt then
		if MeteorService.IsEggRushActive() then
			nextShowerAt = eggRushUntil + SHOWER_AFTER_RUSH
			publishAttributes()
		else
			MeteorService.StartShower()
		end
	end
	-- Egg Rush: nicht im Schauer und nicht kurz davor (sonst gehen beide Events unter)
	if not MeteorService.IsEggRushActive() and t >= nextEggRushAt then
		local showerSoon = nextShowerAt - t < Config.EggRushDuration + SHOWER_AFTER_RUSH
		if #Players:GetPlayers() == 0 then
			nextEggRushAt = t + 30
			publishAttributes()
		elseif MeteorService.IsShowerActive() or showerSoon then
			local showerEnd = MeteorService.IsShowerActive() and showerUntil or (nextShowerAt + Config.ShowerDuration)
			nextEggRushAt = showerEnd + EGG_RUSH_SHOWER_GAP
			publishAttributes()
		else
			MeteorService.StartEggRush()
		end
	end
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
	local t = now()
	nextShowerAt = t + Config.ShowerInterval
	nextEggRushAt = t + Config.EggRushInterval / 2 -- versetzt: erster Egg Rush lange vor dem ersten Schauer
	publishAttributes()
	Players.PlayerRemoving:Connect(function(player)
		actionLimiter.Clear(player)
	end)

	-- Förderband-Schleife (nur Rechnen + gelegentlich ein neues Part – kein Bewegen!)
	task.spawn(function()
		while true do
			task.wait(0.05)
			local ok, err = pcall(beltStep)
			if not ok then
				warn("[MeteorService] Förderband-Fehler: " .. tostring(err))
				pendingNatural = nil
				task.wait(1)
			end
		end
	end)

	-- Meteore am Boden verschwinden lassen + Event-Timer
	task.spawn(function()
		local wasShower = false
		local wasRush = false
		while true do
			task.wait(1)
			local clock = os.clock()
			for i = #groundRecords, 1, -1 do
				local record = groundRecords[i]
				if not record.Claimed and clock > record.Expires then
					removeRecord(record)
				end
			end
			for i = #dropRecords, 1, -1 do
				local record = dropRecords[i]
				if record and not record.Claimed and clock > record.Expires then
					removeRecord(record)
				end
			end
			local ok, err = pcall(eventStep)
			if not ok then
				warn("[MeteorService] Event-Fehler: " .. tostring(err))
			end
			local shower = MeteorService.IsShowerActive()
			if wasShower and not shower then
				Services.EconomyService.NotifyAll("Der Meteoritenschauer ist vorbei. Locks gehen wieder! 🔒", "Info")
			end
			wasShower = shower
			local rush = MeteorService.IsEggRushActive()
			if wasRush and not rush then
				Services.EconomyService.NotifyAll("🥚 Der Egg Rush ist vorbei!", "Info")
			end
			wasRush = rush
		end
	end)
end

return MeteorService
