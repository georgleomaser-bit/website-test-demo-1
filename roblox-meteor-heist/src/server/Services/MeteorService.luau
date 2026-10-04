-- Meteore: das EI-RENNEN (Nester-Feld in der Map-Mitte), die Gratis-Zone am Spawn-Platz, Eier am Boden,
-- Meteoritenschauer, EGG RUSH, RENNEN-EVENT (Gold-Ei), Server-Glück und der GLÜCKS-ZÄHLER (Config.Pity).
-- NACHT (NightService): Nacht-Eier in den Nestern, Sternschnuppen-Eier (SpawnSkyEgg), Blutmond-Glück.
-- Öffentliche Nacht-API (auch fürs Admin-Panel): MeteorService.StartNight(bloodMoon?, seconds?),
-- MeteorService.EndNight(), MeteorService.IsNight(), MeteorService.IsBloodMoon().
--
-- NESTER (MapBuilder baut sie, Ordner "NestField"): alle paar Sekunden erscheint in einem zufälligen
-- freien Nest ein Ei, liegt eine Weile und verschwindet wieder (Config.Nests).
--   kleine Nester: oft, normale Seltenheiten
--   große Nester:  seltener, mindestens Config.Nests.BigMinRarity, viel öfter Legendary+ (Lichtsäule + Ansage)
-- Jedes Ei hat ZWEI Knöpfe – wer zuerst kommt, bekommt es:
--   E halten = SCHNAPPEN (GrabPrompt): gratis, aber man muss es selbst nach Hause TRAGEN
--              (CarryService, Source = "Ground"). Klappt das nicht (Bonk, Kreatur, Tod, Falle, zu langsam),
--              fällt es als GRATIS-Ei auf den Boden und jeder kann es schnappen.
--   F        = KAUFEN (BuyPrompt): kostet Cash, fliegt automatisch in die eigene Base.
-- EIER AM BODEN ("Drop"): fallen gelassen, Egg Rush, Sternschnuppen – nur E = Schnappen und Tragen.
-- RENNEN (Config.Race): Gold-Ei im entferntesten großen Nest. Wer es zuerst heimbringt, bekommt das Ei
-- (mindestens Legendary) + Cash (CarryService meldet die Ankunft über MeteorService.FinishRace).
--
-- PERFORMANCE: Nest-Eier liegen still (verankert, keine Bewegung). Höchstens Config.Nests.MaxEggs
-- (+ große Nester) gleichzeitig. Das "Pop" beim Erscheinen macht der Client lokal.
-- METEORITENSCHAUER: Eier kommen viel öfter, mehr große Nester gleichzeitig.
-- ANTI-CHEAT: Halten wird serverseitig geprüft (MeteorFactory.OnHeldTrigger), Schnappen/Kaufen ist
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

-- Ein Nest aus der Map (Teil "Nest" im Ordner NestField/Nests)
type Nest = {
	Part: BasePart,
	EggPoint: Vector3, -- Unterkante des Eis (Mitte der Mulde)
	Big: boolean,
	Race: boolean, -- Renn-Nest (dort erscheint das Gold-Ei)
	Pillar: Beam?, -- Lichtsäule großer Nester (an, solange ein Ei drin liegt)
	Record: any, -- Ei, das gerade drin liegt (nil = frei)
}

-- Eier in Nestern: { Kind = "Nest", Entry, Part, Price, Position, Expires, Claimed, Landed, ClientReach, Nest, Race? }
local nestRecords = {}
-- Gratis-Zone/Showcase (Kaufen/Schnappen = fliegt automatisch in die Base):
--   { Kind = "Ground", Entry, Part, Price, Position, Expires, Claimed, Landed, ClientReach }
local groundRecords = {}
-- Eier am Boden zum Schnappen + Tragen (fallen gelassen / Egg Rush / Sternschnuppe):
--   { Kind = "Drop", Entry, Part, Price = 0, Position, Expires, Claimed, Landed, ClientReach, EggRush }
local dropRecords = {}
local nestFolder: Folder
local groundFolder: Folder
local fieldFolder: Instance? = nil

local smallNests: { Nest } = {}
local bigNests: { Nest } = {}
local raceNest: Nest? = nil
-- Warteschlange vom Admin (Eierregen, Ei ins Nester-Feld): ein Ei pro Schritt
local nestQueue = {}
local nextSmallAt = 0 -- os.clock()
local nextBigAt = 0

local NESTS = Config.Nests
local BIG_MIN = Config.RarityIndex[NESTS.BigMinRarity] or 4
local NEST_REACH = tonumber(NESTS.Reach) or 9
local NEST_DROP_CLEAR = 4 -- kein neues Ei in ein Nest, auf dem ein fallen gelassenes Ei liegt
local NEST_RANDOM_TRIES = 8
local BIG_ANNOUNCE = Config.RarityIndex.Legendary or 5 -- ab hier: Ansage + Effekt am großen Nest
local QUEUE_BIG_FROM = Config.RarityIndex.Legendary or 5 -- Admin-Eier ab hier in große Nester

-- Eier am Boden liegen still: Spielraum nur für die Bewegung des Spielers während der Ping-Zeit
local STATIC_REACH_BASE = 2
local STATIC_REACH_PER_SPEED = 0.1 -- pro Laufgeschwindigkeit
local STATIC_REACH_MIN = 3
local STATIC_REACH_MAX = 10
local FALL_TIME = 0.9 -- so lange fliegt ein Meteor vom Himmel bzw. in die Base (Client-Effekt)
-- Zwei Knöpfe am selben Ei: Schnappen oben, Kaufen darunter (Pixel), sonst liegen sie übereinander
local GRAB_UI_OFFSET = Vector2.new(0, -40)
local BUY_UI_OFFSET = Vector2.new(0, 40)
local RARE_GRAB_ANNOUNCE = Config.RarityIndex.Mythic or 6 -- ab Mythic: allen sagen, wer gerade schnappt
local ADMIN_SPAWN_ANNOUNCE = Config.RarityIndex.Mythic or 6 -- vom Admin bestellte Eier: schon ab Mythic
-- ab Secret (auch Admin-Eier): Ansage IMMER (nicht gebremst) – so ein Ei will niemand verpassen
local SECRET_SPAWN_ANNOUNCE = Config.RarityIndex.Secret or 9
local RARE_ANNOUNCE_GAP = 4 -- solche Ansagen höchstens alle 4 Sekunden (sonst ist der Bildschirm voll)
-- Schnappen/Kaufen pro Spieler höchstens so oft pro Sekunde (gegen Massen-Auslösen per Cheat)
local actionLimiter = Util.RateLimiter(6, 1)

-- Egg Rush: Eier fallen nacheinander (sieht nach Regen aus) aus dieser Höhe aufs Nester-Feld
local EGG_RUSH_SKY = 120
local EGG_RUSH_SPAWN_GAP = 0.08
local EGG_SPOT_TRIES = 30 -- Versuche pro Ei, einen freien Platz zu finden
local EGG_EDGE_MARGIN = 8 -- Abstand zum Map-Rand
local EGG_FIELD_MARGIN = 2 -- Abstand zum Rand des Nester-Felds
local EGG_PLOT_MARGIN = 3 -- Abstand zu Basen
local EGG_SPACING = 3 -- Abstand zwischen zwei Eiern
local EGG_RUSH_SHOWER_GAP = 60 -- Egg Rush nicht direkt vor/nach dem Meteoritenschauer
local SHOWER_AFTER_RUSH = 20 -- Schauer wartet, bis der Egg Rush (oder das Rennen) vorbei ist (+ so viele Sekunden)
-- Ersatz-Grenzen, falls die Map keine "Boundary"-Wände hat
local FALLBACK_AREA = { MinX = -168, MaxX = 168, MinZ = -406, MaxZ = 256 }

-- RENNEN (Config.Race)
local RACE = Config.Race
local RACE_MIN = Config.RarityIndex[RACE.MinRarity] or 5
local RACE_BUSY_GAP = 60 -- Rennen nicht kurz vor Egg Rush / Schauer
local RACE_NIGHT_GAP = 30 -- ... und nicht kurz vor dem Nacht-Beginn
local RACE_RETRY = 45 -- war gerade etwas los: so viele Sekunden später nochmal versuchen
local RACE_LOST_CHECKS = 3 -- Gold-Ei so oft hintereinander nicht gefunden -> Rennen vorbei
local raceActive = false
local raceId = 0
local raceUntil = 0
local nextRaceAt = 0
local raceLost = 0

local serverLuckMult = 1
local serverLuckUntil = 0
local showerUntil = 0
local nextShowerAt = 0
local eggRushUntil = 0
local nextEggRushAt = 0
local lastRareAnnounce = -math.huge

-- GLÜCKS-ZÄHLER (pro Server): Nest-Eier seit dem letzten Legendary+ (siehe Config.Pity)
local PITY = Config.Pity or { Step = 20, Bonus = 0.25, Max = 3, FromRarity = "Legendary" }
local PITY_FROM = Config.RarityIndex[PITY.FromRarity] or 5
local PITY_FULL = math.ceil((PITY.Max - 1) / PITY.Bonus) * PITY.Step -- ab so vielen Eiern ist das Glück voll
local pityCount = 0
local NIGHT = Config.Night or {}

-- -------------------------------------------------------------------
-- GLÜCK & EVENTS
-- -------------------------------------------------------------------
local function now(): number
	return workspace:GetServerTimeNow()
end

-- Glück für Legendary+ durch den Glücks-Zähler (1 = kein Bonus)
local function pityMult(): number
	return math.min(PITY.Max, 1 + math.floor(pityCount / PITY.Step) * PITY.Bonus)
end

-- (nur bei Änderung schreiben: die Nester würfeln ~2 Eier pro Sekunde)
local function setAttributeIfChanged(name: string, value: number)
	if ReplicatedStorage:GetAttribute(name) ~= value then
		ReplicatedStorage:SetAttribute(name, value)
	end
end

local function publishPity()
	setAttributeIfChanged("PityCount", pityCount)
	setAttributeIfChanged("PityFull", PITY_FULL)
	setAttributeIfChanged("PityMult", pityMult())
end

-- Nacht / Blutmond (NightService fehlt -> immer Tag)
local function nightState(): (boolean, boolean)
	local night = Services and Services.NightService
	if night then
		return night.IsNight(), night.IsBloodMoon()
	end
	return false, false
end

local function publishAttributes()
	ReplicatedStorage:SetAttribute("LuckMult", serverLuckMult)
	ReplicatedStorage:SetAttribute("LuckUntil", serverLuckUntil)
	ReplicatedStorage:SetAttribute("ShowerUntil", showerUntil)
	ReplicatedStorage:SetAttribute("NextShowerAt", nextShowerAt)
	ReplicatedStorage:SetAttribute("EggRushUntil", eggRushUntil)
	ReplicatedStorage:SetAttribute("NextEggRushAt", nextEggRushAt)
	ReplicatedStorage:SetAttribute("RaceUntil", if raceActive then raceUntil else 0)
	ReplicatedStorage:SetAttribute("NextRaceAt", nextRaceAt)
end

-- Ansage an alle für seltene Eier (Nester, Schnappen) – höchstens alle RARE_ANNOUNCE_GAP Sekunden,
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
	local _, bloodMoon = nightState()
	if bloodMoon then
		luck *= tonumber(NIGHT.BloodMoonLuck) or 2
	end
	return luck
end

-- -------------------------------------------------------------------
-- NACHT-API (die Arbeit macht NightService; hier nur weitergereicht, damit alles an EINER Stelle ist)
-- -------------------------------------------------------------------
function MeteorService.IsNight(): boolean
	local night = nightState()
	return night
end

function MeteorService.IsBloodMoon(): boolean
	local _, bloodMoon = nightState()
	return bloodMoon
end

-- Nacht sofort starten (bloodMoon = true -> Blutmond), seconds = Länge (Standard Config.Night.NightLength)
function MeteorService.StartNight(bloodMoon: boolean?, seconds: number?): boolean
	local night = Services and Services.NightService
	if not night then
		return false
	end
	night.StartNight(bloodMoon == true, seconds)
	return true
end

-- Nacht sofort beenden (Sonnenaufgang)
function MeteorService.EndNight(): boolean
	local night = Services and Services.NightService
	if not night then
		return false
	end
	night.EndNight()
	return true
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
	nextBigAt = 0 -- große Nester sofort füllen
	publishAttributes()
	-- Im Schauer gibt es keine Locks! (Ein gekauftes Base-Schild bleibt aber an.)
	for _, plot in ipairs(Services.PlotService.Plots) do
		if not Services.PlotService.IsShielded(plot) then
			Services.PlotService.SetLocked(plot, 0)
		end
	end
	Services.EconomyService.NotifyAll(
		"🌠 METEORITENSCHAUER! Volle Nester, keine Locks, " .. Config.ShowerLuck .. "x Glück!",
		"Event"
	)
end

-- -------------------------------------------------------------------
-- ZUFALL
-- -------------------------------------------------------------------
-- luck: ab Rare mal Glück. pity: nur Legendary+ mal Glücks-Zähler. Nachts: Godly+ mal NightMult.
-- minIndex (optional): nur Seltenheiten ab diesem Index (große Nester, Gold-Ei)
function MeteorService.RollRarity(luck: number, pity: number?, minIndex: number?)
	local night = nightState()
	local pityBonus = pity or 1
	return Util.WeightedPick(Config.Rarities, function(rarity)
		if rarity.AdminOnly or #Config.MeteorsByRarity[rarity.Name] == 0 then
			return 0
		end
		local index = Config.RarityIndex[rarity.Name]
		if minIndex and index < minIndex then
			return 0
		end
		local weight = index >= 3 and rarity.Weight * luck or rarity.Weight
		if index >= PITY_FROM then
			weight *= pityBonus
		end
		if night and rarity.NightMult then
			weight *= rarity.NightMult
		end
		return weight
	end, rng)
end

function MeteorService.RollMutation(luck: number): string
	local mut = Util.WeightedPick(Config.Mutations, function(m)
		return m.Name == "Normal" and m.Weight or m.Weight * luck
	end, rng)
	return mut.Name
end

-- Zufälliger Meteor einer Seltenheit (nur Meteore, die von selbst in die Nester kommen; includeAll = auch Admin/nicht spawnbare)
-- Nachts kommen die Nacht-Eier dazu (je Config.Night.NightEggWeight so oft wie ein normales Ei).
function MeteorService.RandomOfRarity(rarityName: string, includeAll: boolean?)
	local list = Config.MeteorsByRarity[rarityName]
	if (not list or #list == 0) and includeAll then
		list = Config.MeteorsByRarityAll[rarityName]
	end
	if not list or #list == 0 then
		return nil
	end
	local night, bloodMoon = nightState()
	local nightList = Config.NightMeteorsByRarity and Config.NightMeteorsByRarity[rarityName]
	if night and nightList and #nightList > 0 then
		local nightWeight = tonumber(NIGHT.NightEggWeight) or 2
		local pool = {}
		for _, def in ipairs(list) do
			table.insert(pool, { Def = def, Weight = 1 })
		end
		for _, def in ipairs(nightList) do
			if bloodMoon or def.BloodMoonOnly ~= true then
				table.insert(pool, { Def = def, Weight = nightWeight })
			end
		end
		return Util.WeightedPick(pool, nil, rng).Def
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
-- pity = Glücks-Bonus für Legendary+ (nur natürliche Nest-Eier, siehe rollNestEntry), minIndex siehe RollRarity
function MeteorService.RollEntry(luck: number?, pity: number?, minIndex: number?)
	local l = luck or MeteorService.GetLuck()
	local rarity = MeteorService.RollRarity(l, pity, minIndex)
	local def = MeteorService.RandomOfRarity(rarity.Name) or Config.Meteors[1]
	return { Id = def.Id, Mut = MeteorService.RollMutation(l), Lv = 1, Xp = 0 }
end

-- Natürliches Nest-Ei: mit Glücks-Zähler. Legendary+ setzt ihn zurück, sonst +1.
-- big = großes Nest (mehr Glück, mindestens Config.Nests.BigMinRarity)
local function rollNestEntry(big: boolean)
	local luck = MeteorService.GetLuck() * (if big then tonumber(NESTS.BigLuck) or 1 else 1)
	local entry = MeteorService.RollEntry(luck, pityMult(), if big then BIG_MIN else nil)
	local def = Config.MeteorsById[entry.Id]
	if def and (Config.RarityIndex[def.Rarity] or 1) >= PITY_FROM then
		pityCount = 0
	else
		pityCount += 1
	end
	publishPity()
	return entry
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
-- EINTRÄGE (Nest, Gratis-Zone, Boden)
-- -------------------------------------------------------------------
local function listFor(kind: string)
	if kind == "Nest" then
		return nestRecords
	elseif kind == "Drop" then
		return dropRecords
	end
	return groundRecords
end

-- Nest wieder frei: Lichtsäule aus
local function freeNest(nest: Nest?, record)
	if nest and nest.Record == record then
		nest.Record = nil
		if nest.Pillar then
			nest.Pillar.Enabled = false
		end
	end
end

local function removeRecord(record)
	local list = listFor(record.Kind)
	local index = table.find(list, record)
	if index then
		table.remove(list, index)
	end
	freeNest(record.Nest, record)
	if record.Part then
		record.Part:Destroy()
		record.Part = nil
	end
end

local function currentPosition(record): Vector3?
	if not record.Part then
		return nil
	end
	return record.Position
end

local function rarityIndexOf(entry): number
	local def = Config.MeteorsById[entry.Id]
	return def and Config.RarityIndex[def.Rarity] or 1
end

-- Schild "🏁 GOLD-EI" über dem Renn-Ei (immer sichtbar, auch durch Wände)
local function addRaceMarker(part: BasePart)
	part:SetAttribute("RaceEgg", true)
	local gui = Instance.new("BillboardGui")
	gui.Name = "RaceMarker"
	gui.Size = UDim2.fromOffset(170, 46)
	gui.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 1000
	gui.LightInfluence = 0
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "🏁 GOLD-EI"
	label.TextColor3 = Color3.fromRGB(255, 215, 60)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = label
	label.Parent = gui
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
	-- liegt still: nur Spielraum für die eigene Bewegung (schnelle Spieler etwas mehr)
	local clientReach = record.ClientReach or 10
	local offset = root.Position - position
	local character = root.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local walkSpeed = if humanoid then humanoid.WalkSpeed else Config.NormalWalkSpeed
	local extra = math.clamp(STATIC_REACH_BASE + walkSpeed * STATIC_REACH_PER_SPEED, STATIC_REACH_MIN, STATIC_REACH_MAX)
	local tooFar = offset.Magnitude > clientReach + extra
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

-- KAUFEN (Nest, F) / Schnappen in der Gratis-Zone: fliegt AUTOMATISCH in einen freien Slot
local function tryClaim(player: Player, record)
	if record.Claimed or not record.Part or record.Landed == false or record.Race then
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
				"🔥 " .. def.Rarity .. " braucht " .. required .. " Rebirth(s) zum Kaufen – schnappen geht! 😈",
				"Error"
			)
			return
		end
		if data.Cash < record.Price then
			Services.EconomyService.Notify(
				player,
				"💸 Nicht genug Cash! Du brauchst " .. Util.FormatCash(record.Price) .. " – oder schnapp es gratis!",
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

-- SCHNAPPEN aus einem Nest (E) / eines Eis am Boden: gratis, aber selbst nach Hause tragen
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
	local fromNest = record.Kind == "Nest"
	local isRace = entry.Race ~= nil and entry.Race == raceId and raceActive
	removeRecord(record)
	Services.CarryService.StartCarry(player, entry, {
		Source = "Ground",
		From = if isRace then "Race" elseif fromNest then "Nest" else "Drop",
		GrabPosition = position,
		ScaleTimeout = fromNest or isRace, -- weite Wege übers Feld: mehr Zeit
	})
	local def = Config.MeteorsById[entry.Id]
	if isRace then
		rareAnnounce("🏁 " .. player.DisplayName .. " hat das Gold-Ei! Bonk ihn!")
	elseif fromNest and def and Config.RarityIndex[def.Rarity] >= RARE_GRAB_ANNOUNCE then
		local mut = entry.Mut ~= "Normal" and (entry.Mut .. " ") or ""
		rareAnnounce(player.DisplayName .. " schnappt " .. def.Rarity .. " " .. mut .. def.Name .. "! Bonk ihn!")
	end
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

-- Nest-Ei: E = Schnappen (gratis, tragen), F = Kaufen (automatische Lieferung; nicht beim Gold-Ei)
local function attachNestPrompts(record)
	local part: BasePart = record.Part
	local def = Config.MeteorsById[record.Entry.Id]
	local reach = math.max(NEST_REACH, part.Size.X / 2 + 6)
	record.ClientReach = reach

	local grab =
		MeteorFactory.AddPrompt(part, "GrabPrompt", "Schnappen", def.Name, Config.NestGrabHold, Enum.KeyCode.E, reach)
	grab.GamepadKeyCode = Enum.KeyCode.ButtonX
	grab:SetAttribute("ClientMaxDistance", reach)
	-- gratis -> der Server prüft, ob wirklich so lange gehalten wurde
	MeteorFactory.OnHeldTrigger(grab, function(player)
		tryGrab(player, record)
	end)
	if record.Race then
		return
	end
	grab.UIOffset = GRAB_UI_OFFSET

	local action = record.Price > 0 and ("Kaufen " .. Util.FormatCash(record.Price)) or "Gratis holen"
	local buy = MeteorFactory.AddPrompt(
		part,
		"BuyPrompt",
		action,
		def.Name .. " (" .. def.Rarity .. ")",
		Config.NestBuyHold,
		Enum.KeyCode.F,
		reach
	)
	buy.GamepadKeyCode = Enum.KeyCode.ButtonY
	buy.UIOffset = BUY_UI_OFFSET
	buy:SetAttribute("ClientMaxDistance", reach)
	buy.Triggered:Connect(function(player)
		tryClaim(player, record)
	end)
end

-- -------------------------------------------------------------------
-- NESTER – Eier erscheinen in zufälligen freien Nestern
-- -------------------------------------------------------------------
-- Nester aus der Map lesen (MapBuilder: NestField/Nests, Teile "Nest" mit NestSize + EggPoint)
local function loadNests()
	table.clear(smallNests)
	table.clear(bigNests)
	raceNest = nil
	local map = Services.PlotService.MapFolder
	local field = map and map:FindFirstChild("NestField")
	local folder = field and field:FindFirstChild("Nests")
	fieldFolder = field
	if not folder then
		warn("[MeteorService] Kein Nester-Feld (NestField/Nests) gefunden – keine Nest-Eier!")
		return
	end
	for _, child in ipairs(folder:GetChildren()) do
		local point = child:GetAttribute("EggPoint")
		if child:IsA("BasePart") and child.Name == "Nest" and typeof(point) == "Vector3" then
			local pillar = child:FindFirstChild("NestPillar")
			local nest: Nest = {
				Part = child,
				EggPoint = point,
				Big = child:GetAttribute("NestSize") == "Big",
				Race = child:GetAttribute("RaceNest") == true,
				Pillar = if pillar and pillar:IsA("Beam") then pillar else nil,
				Record = nil,
			}
			table.insert(if nest.Big then bigNests else smallNests, nest)
			if nest.Race then
				raceNest = nest
			end
		end
	end
	-- kein markiertes Renn-Nest: das große Nest am weitesten hinten (größtes Z)
	if not raceNest then
		for _, nest in ipairs(bigNests) do
			if not raceNest or nest.EggPoint.Z > raceNest.EggPoint.Z then
				raceNest = nest
			end
		end
		if raceNest then
			raceNest.Race = true
		end
	end
end

local function nestIsFree(nest: Nest): boolean
	if nest.Record then
		return false
	end
	local point = nest.EggPoint
	for _, record in ipairs(dropRecords) do
		local dx, dz = record.Position.X - point.X, record.Position.Z - point.Z
		if dx * dx + dz * dz < NEST_DROP_CLEAR * NEST_DROP_CLEAR then
			return false
		end
	end
	return true
end

-- Zufälliges freies Nest (das Renn-Nest bleibt während des Rennens frei)
local function pickFreeNest(list: { Nest }): Nest?
	local count = #list
	if count == 0 then
		return nil
	end
	local function usable(nest: Nest): boolean
		return nestIsFree(nest) and not (nest.Race and raceActive)
	end
	for _ = 1, NEST_RANDOM_TRIES do
		local nest = list[rng:NextInteger(1, count)]
		if usable(nest) then
			return nest
		end
	end
	local start = rng:NextInteger(1, count)
	for k = 0, count - 1 do
		local nest = list[(start + k - 1) % count + 1]
		if usable(nest) then
			return nest
		end
	end
	return nil
end

local function countNestEggs(): (number, number)
	local small, big = 0, 0
	for _, record in ipairs(nestRecords) do
		if record.Nest and record.Nest.Big then
			big += 1
		else
			small += 1
		end
	end
	return small, big
end

-- Legt ein Ei in ein Nest. opts: { Free?, Lifetime?, Race? }
local function spawnNestEgg(nest: Nest, entry, opts)
	local size = MeteorFactory.GetSize(entry)
	local price = if opts.Free or opts.Race then 0 else math.floor(Config.MeteorValue(entry))
	local position = nest.EggPoint + Vector3.new(0, size / 2, 0)
	local part = MeteorFactory.Create(entry, "Nest", price)
	part.CFrame = CFrame.new(position)
	part:SetAttribute("NestSize", if nest.Big then "Big" else "Small")
	local lifetime = tonumber(opts.Lifetime)
		or (if nest.Big then tonumber(NESTS.BigLifetime) or 45 else tonumber(NESTS.Lifetime) or 30)
	local record = {
		Kind = "Nest",
		Entry = entry,
		Part = part,
		Price = price,
		Position = position,
		Expires = os.clock() + lifetime,
		Claimed = false,
		Landed = true,
		Nest = nest,
		Race = opts.Race,
	}
	nest.Record = record
	table.insert(nestRecords, record)
	attachNestPrompts(record)
	if opts.Race then
		addRaceMarker(part)
	end
	local pillar = nest.Pillar
	if pillar then
		local def = Config.MeteorsById[entry.Id]
		local rarity = def and Config.RaritiesByName[def.Rarity]
		local color: Color3 = if opts.Race
			then Color3.fromRGB(255, 215, 60)
			elseif rarity then rarity.Color
			else Color3.new(1, 1, 1)
		pillar.Color = ColorSequence.new(color, color:Lerp(Color3.new(1, 1, 1), 0.5))
		pillar.Enabled = true
	end
	part.Parent = nestFolder
	return record
end

-- Ansage + Effekt für ein neues Nest-Ei. admin = vom Admin bestellt (schon ab Mythic ansagen)
local function announceNestEgg(record, admin: boolean)
	local entry = record.Entry
	local index = rarityIndexOf(entry)
	local big = record.Nest ~= nil and record.Nest.Big
	if index >= SECRET_SPAWN_ANNOUNCE then
		announce(entry, "🥚 WAHNSINN! %s im Nest!")
	elseif admin and index >= ADMIN_SPAWN_ANNOUNCE then
		announce(entry, "🥚 %s im Nest!")
	elseif big and index >= BIG_ANNOUNCE then
		local def = Config.MeteorsById[entry.Id]
		local mut = entry.Mut ~= "Normal" and (entry.Mut .. " ") or ""
		rareAnnounce("🥚 Großes Nest: " .. def.Rarity .. " " .. mut .. def.Name .. "!")
	end
	if big and index >= BIG_ANNOUNCE then
		local def = Config.MeteorsById[entry.Id]
		Remotes.Effect:FireAllClients("BigNest", 0, { Position = record.Position, Rarity = def.Rarity })
	end
end

-- Ei vom Admin (Warteschlange): Legendary+ in ein großes Nest, sonst klein; alles voll -> ältestes weg
local function spawnQueued(opts)
	local entry = makeEntry(opts)
	if not entry then
		return
	end
	local big = rarityIndexOf(entry) >= QUEUE_BIG_FROM
	local first, second = smallNests, bigNests
	if big then
		first, second = bigNests, smallNests
	end
	local nest = pickFreeNest(first) or pickFreeNest(second)
	if not nest then
		for _, record in ipairs(nestRecords) do
			if not record.Race and not record.Claimed and record.Nest and record.Nest.Big == big then
				nest = record.Nest
				removeRecord(record)
				break
			end
		end
	end
	if not nest then
		return
	end
	local record = spawnNestEgg(nest, entry, { Free = opts.Free == true })
	if opts.Announce == true then
		announceNestEgg(record, true)
	end
end

-- opts: { Id?, Mut?, Rarity?, Free?, Announce? } -> kommt so bald wie möglich in ein Nest
-- (Announce = true: allen ansagen, ab Mythic)
function MeteorService.QueueNest(opts)
	table.insert(nestQueue, opts or {})
end

-- Ein Schritt: abgelaufene Eier weg, Admin-Warteschlange, neue Eier (kleine + große Nester)
local function nestStep()
	local clock = os.clock()
	for i = #nestRecords, 1, -1 do
		local record = nestRecords[i]
		if record and not record.Claimed and not record.Race and clock > record.Expires then
			removeRecord(record)
		end
	end
	local queued = table.remove(nestQueue, 1)
	if queued then
		spawnQueued(queued)
	end
	if #Players:GetPlayers() == 0 then
		return
	end
	local shower = MeteorService.IsShowerActive()
	local small, big = countNestEggs()
	if clock >= nextSmallAt then
		nextSmallAt = clock + (tonumber(if shower then NESTS.ShowerSpawnInterval else NESTS.SpawnInterval) or 0.5)
		local maxEggs = tonumber(if shower then NESTS.ShowerMaxEggs else NESTS.MaxEggs) or 50
		if small < maxEggs then
			local nest = pickFreeNest(smallNests)
			if nest then
				announceNestEgg(spawnNestEgg(nest, rollNestEntry(false), {}), false)
			end
		end
	end
	if clock >= nextBigAt then
		local range = (if shower then NESTS.ShowerBigInterval else NESTS.BigInterval) or { 10, 16 }
		nextBigAt = clock + rng:NextNumber(tonumber(range[1]) or 10, tonumber(range[2]) or 16)
		local maxBig = tonumber(if shower then NESTS.ShowerMaxBigEggs else NESTS.MaxBigEggs) or 3
		if big < maxBig then
			local nest = pickFreeNest(bigNests)
			if nest then
				announceNestEgg(spawnNestEgg(nest, rollNestEntry(true), {}), false)
			end
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
	if nestFolder then
		table.insert(ignore, nestFolder)
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
-- EIER AM BODEN (fallen gelassen / Egg Rush / Sternschnuppe)
-- -------------------------------------------------------------------
-- Legt ein Ei auf den Boden. groundPos = Punkt AUF dem Boden.
-- opts: { From: Vector3?, SkyHeight: number?, Lifetime: number?, EggRush: boolean?, ShootingStar: boolean? }
--   From/SkyHeight -> fällt sichtbar dorthin (Client-Effekt "Deliver"), sonst liegt es sofort da
--   ShootingStar -> Attribut am Ei (der Client lässt es funkeln)
local function spawnDrop(entry, groundPos: Vector3, opts)
	while #dropRecords >= Config.MaxDroppedMeteors do
		removeRecord(dropRecords[1]) -- älteste weg
	end
	local size = MeteorFactory.GetSize(entry)
	local position = Vector3.new(groundPos.X, groundPos.Y + size / 2 + 0.1, groundPos.Z)
	local part = MeteorFactory.Create(entry, "Ground", 0)
	part.CFrame = CFrame.new(position)
	if opts.ShootingStar then
		part:SetAttribute("ShootingStar", true)
	end
	if entry.Race ~= nil then
		addRaceMarker(part)
	end

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

-- Getragenes Ei fällt zu Boden (gebonkt, Kreatur, gestorben, Falle, zu langsam ...). Es liegt dann GRATIS da
-- und JEDER kann es schnappen. position = ungefähre Stelle (der Boden darunter wird gesucht),
-- from = optional: von hier fällt es sichtbar herunter (z.B. über dem Kopf des Trägers).
-- Das Gold-Ei des laufenden Rennens bleibt dabei das Gold-Ei (liegt bis zum Ende des Rennens).
function MeteorService.DropMeteor(entry, position: Vector3, from: Vector3?)
	if type(entry) ~= "table" or not Config.MeteorsById[entry.Id] or typeof(position) ~= "Vector3" then
		return nil
	end
	local isRace = raceActive and entry.Race ~= nil and entry.Race == raceId
	local clean = {
		Id = entry.Id,
		Mut = Config.MutationsByName[entry.Mut] and entry.Mut or "Normal",
		Lv = math.clamp(math.floor(tonumber(entry.Lv) or 1), 1, Config.MaxLevel),
		Xp = 0,
		Alien = entry.Alien,
		Race = if isRace then raceId else nil,
	}
	local lifetime = if isRace then math.max(5, raceUntil - now()) else Config.DroppedLifetime
	return spawnDrop(clean, groundBelow(position), { From = from, Lifetime = lifetime })
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

-- Freier Platz auf der Wiese: innerhalb der Map, nicht in/an Basen, nicht auf dem Nester-Feld,
-- nicht auf dem Spawn-Platz/Bäumen (der Strahl muss genau den Wiesenboden "Ground" treffen).
local function findEggSpot(radius: number, groundPart: BasePart, params: RaycastParams): Vector3?
	local area = mapArea()
	local margin = EGG_EDGE_MARGIN + radius
	if area.MaxX - area.MinX <= margin * 2 or area.MaxZ - area.MinZ <= margin * 2 then
		return nil
	end
	for _ = 1, EGG_SPOT_TRIES do
		local x = rng:NextNumber(area.MinX + margin, area.MaxX - margin)
		local z = rng:NextNumber(area.MinZ + margin, area.MaxZ - margin)
		local flatPos = Vector3.new(x, 0, z)
		local ok = true
		do
			for _, plot in ipairs(Services.PlotService.Plots) do
				local hx, hz = Services.PlotService.HalfExtents(plot)
				local plotMargin = radius + EGG_PLOT_MARGIN
				local localPos = plot.CFrame:PointToObjectSpace(flatPos)
				if math.abs(localPos.X) <= hx + plotMargin and math.abs(localPos.Z) <= hz + plotMargin then
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

-- Boden des Nester-Felds (nil = nicht gefunden)
local function fieldFloor(): BasePart?
	local floor = fieldFolder and fieldFolder:FindFirstChild("Floor")
	if floor and floor:IsA("BasePart") then
		return floor
	end
	return nil
end

-- Freier Platz auf dem Nester-Feld (nicht auf Nestern/Pads, nicht zu nah an anderen Eiern).
-- Der Strahl muss genau den Feld-Boden treffen. Gibt den Punkt AUF dem Boden zurück oder nil.
local function findFieldSpot(radius: number, floor: BasePart, params: RaycastParams): Vector3?
	local half = floor.Size / 2
	local center = floor.Position
	local margin = EGG_FIELD_MARGIN + radius
	if half.X <= margin or half.Z <= margin then
		return nil
	end
	for _ = 1, EGG_SPOT_TRIES do
		local x = rng:NextNumber(center.X - half.X + margin, center.X + half.X - margin)
		local z = rng:NextNumber(center.Z - half.Z + margin, center.Z + half.Z - margin)
		local ok = true
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
		if ok then
			local result = workspace:Raycast(Vector3.new(x, 60, z), Vector3.new(0, -100, 0), params)
			if result and result.Instance == floor then
				return result.Position
			end
		end
	end
	return nil
end

-- Wiesenboden "Ground" der Map (nil = nicht gefunden)
local function meadowGround(): BasePart?
	local map = Services.PlotService.MapFolder
	local groundPart = map and map:FindFirstChild("Ground")
	if groundPart and groundPart:IsA("BasePart") then
		return groundPart
	end
	return nil
end

-- Platz für ein Gratis-Ei: aufs Nester-Feld (fehlt es, auf die Wiese)
local function freeEggSpot(radius: number, params: RaycastParams): Vector3?
	local floor = fieldFloor()
	if floor then
		return findFieldSpot(radius, floor, params)
	end
	local groundPart = meadowGround()
	if not groundPart then
		return nil
	end
	return findEggSpot(radius, groundPart, params)
end

-- 🥚 EGG RUSH: Config.EggRushCount Gratis-Eier (3x Glück) regnen aufs Nester-Feld.
-- Läuft schon einer, wird er verlängert und es kommen noch mehr Eier dazu.
-- duration/count optional (Standard aus Config). Gibt die Anzahl der geplanten Eier zurück.
function MeteorService.StartEggRush(duration: number?, count: number?): number
	local t = now()
	if not fieldFloor() and not meadowGround() then
		warn("[MeteorService] Egg Rush: kein Boden gefunden – keine Eier")
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
	Services.EconomyService.NotifyAll("🥚 EGG RUSH! Eier regnen aufs Feld – schnell!", "Event")

	task.spawn(function()
		-- Nester/Pads sollen auch treffen (dann ist dort kein Platz) -> CanCollide nicht beachten
		local params = rayParams(false)
		for _ = 1, amount do
			local remaining = eggRushUntil - now()
			if remaining <= 1 then
				break
			end
			local entry = MeteorService.RollEntry(MeteorService.GetLuck() * Config.EggRushLuck)
			local spot = freeEggSpot(MeteorFactory.GetSize(entry) / 2, params)
			if spot then
				spawnDrop(entry, spot, { SkyHeight = EGG_RUSH_SKY, Lifetime = remaining, EggRush = true })
			end
			task.wait(EGG_RUSH_SPAWN_GAP)
		end
	end)
	return amount
end

-- Freier Platz auf der Wiese (nicht auf dem Nester-Feld) – z.B. für die leuchtenden Kisten der Nacht.
-- Gibt den Punkt AUF dem Boden zurück oder nil.
function MeteorService.FindMeadowSpot(radius: number): Vector3?
	local groundPart = meadowGround()
	if not groundPart then
		return nil
	end
	return findEggSpot(math.max(0.5, radius), groundPart, rayParams(false))
end

-- 🌠 STERNSCHNUPPE: ein Gratis-Ei fällt schräg vom Himmel aufs Nester-Feld (wie Egg-Rush-Eier:
-- schnappen und heimtragen). opts: { Luck: number?, Lifetime: number? } -> Eintrag am Boden oder nil
function MeteorService.SpawnSkyEgg(opts)
	opts = opts or {}
	local luck = MeteorService.GetLuck() * (tonumber(opts.Luck) or 1)
	local entry = MeteorService.RollEntry(luck)
	local spot = freeEggSpot(MeteorFactory.GetSize(entry) / 2, rayParams(false))
	if not spot then
		return nil
	end
	-- schräg von oben: steil genug, dass der Client es als "Fall" (mit Schweif) zeigt
	local angle = rng:NextNumber() * math.pi * 2
	local from = spot + Vector3.new(math.cos(angle) * 60, 160, math.sin(angle) * 60)
	local record = spawnDrop(entry, spot, {
		From = from,
		Lifetime = tonumber(opts.Lifetime) or 45,
		ShootingStar = true,
	})
	local def = Config.MeteorsById[entry.Id]
	if def and (Config.RarityIndex[def.Rarity] or 1) >= RARE_GRAB_ANNOUNCE then
		announce(entry, "🌠 Sternschnuppe: %s auf dem Feld!")
	end
	return record
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

-- Allgemeiner Spawn (Admin-Panel): opts.Where = "Nest" (Standard), "Free" (Gratis-Zone) oder Position
function MeteorService.SpawnMeteor(opts)
	opts = opts or {}
	if opts.Position or opts.Where == "Free" then
		return MeteorService.SpawnStatic(opts)
	end
	MeteorService.QueueNest(opts)
	return nil
end

-- Nester, Gratis-Zone und alle Eier am Boden leeren (ein laufendes Rennen bleibt, das Gold-Ei auch)
function MeteorService.ClearGround()
	for i = #groundRecords, 1, -1 do
		removeRecord(groundRecords[i])
	end
	for i = #dropRecords, 1, -1 do
		local record = dropRecords[i]
		if not (raceActive and record.Entry.Race == raceId) then
			removeRecord(record)
		end
	end
	for i = #nestRecords, 1, -1 do
		local record = nestRecords[i]
		if not record.Race then
			removeRecord(record)
		end
	end
	table.clear(nestQueue)
end

-- -------------------------------------------------------------------
-- RENNEN-EVENT: Gold-Ei im entferntesten großen Nest – wer es zuerst heimbringt, gewinnt
-- -------------------------------------------------------------------
function MeteorService.IsRaceActive(): boolean
	return raceActive
end

-- Wo ist das Gold-Ei gerade? (im Nest, am Boden oder beim Träger) -> für den Pfeil der Spieler
local function raceTarget(): Vector3?
	for _, record in ipairs(nestRecords) do
		if record.Race == raceId then
			return record.Position
		end
	end
	for _, record in ipairs(dropRecords) do
		if record.Entry.Race == raceId then
			return record.Position
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local entry = Services.CarryService.CarriedEntry(player)
		if type(entry) == "table" and entry.Race == raceId then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				return root.Position
			end
		end
	end
	return nil
end

local function endRace(winner: Player?)
	if not raceActive then
		return
	end
	raceActive = false
	nextRaceAt = now() + (tonumber(RACE.Interval) or 420)
	-- übrig gebliebenes Gold-Ei weg (wer es gerade trägt, behält es als normales Ei)
	for i = #nestRecords, 1, -1 do
		if nestRecords[i].Race == raceId then
			removeRecord(nestRecords[i])
		end
	end
	for i = #dropRecords, 1, -1 do
		if dropRecords[i].Entry.Race == raceId then
			removeRecord(dropRecords[i])
		end
	end
	ReplicatedStorage:SetAttribute("RaceTarget", nil)
	publishAttributes()
	if not winner then
		Services.EconomyService.NotifyAll("🏁 Rennen vorbei – niemand hat das Gold-Ei heimgebracht.", "Info")
	end
end

-- Rennen sofort starten (Admin oder Timer). Gibt (Erfolg, Text) zurück.
function MeteorService.StartRace(): (boolean, string)
	if raceActive then
		return false, "Das Rennen läuft schon"
	end
	local nest = raceNest
	if not nest then
		return false, "Kein Renn-Nest gefunden"
	end
	if nest.Record then
		removeRecord(nest.Record)
	end
	local rarity = MeteorService.RollRarity(MeteorService.GetLuck(), nil, RACE_MIN)
	local def = MeteorService.RandomOfRarity(rarity.Name, true)
	if not def then
		return false, "Kein Ei für das Rennen gefunden"
	end
	raceId += 1
	raceActive = true
	raceLost = 0
	local duration = tonumber(RACE.Duration) or 150
	raceUntil = now() + duration
	local entry = {
		Id = def.Id,
		Mut = if Config.MutationsByName.Gold then "Gold" else "Normal",
		Lv = 1,
		Xp = 0,
		Race = raceId,
	}
	local record = spawnNestEgg(nest, entry, { Race = raceId, Lifetime = duration + 5 })
	ReplicatedStorage:SetAttribute("RaceTarget", record.Position)
	publishAttributes()
	Services.EconomyService.NotifyAll("🏁 EI-RENNEN! Hol das Gold-Ei am Ende des Felds!", "Event")
	Remotes.Effect:FireAllClients("RaceStart", 0, { Position = record.Position })
	return true, "🏁 Rennen gestartet: " .. def.Rarity .. " " .. def.Name
end

-- CarryService: ein Ei ist zu Hause angekommen. Ist es das Gold-Ei -> Sieg!
function MeteorService.FinishRace(player: Player, entry)
	if not raceActive or type(entry) ~= "table" or entry.Race ~= raceId then
		return
	end
	local Economy = Services.EconomyService
	local seconds = tonumber(RACE.CashSeconds) or 300
	local amount = math.floor(math.max(tonumber(RACE.CashMin) or 25000, Economy.GetIncome(player) * seconds))
	Economy.AddCash(player, amount)
	Economy.Effect(player, "Collect", amount)
	Economy.Effect(player, "Confetti", 2)
	endRace(player)
	Economy.NotifyAll("🏁 " .. player.DisplayName .. " gewinnt das Ei-Rennen! +" .. Util.FormatCash(amount), "Event")
end

local function raceStep()
	if not raceActive then
		return
	end
	if now() >= raceUntil then
		endRace(nil)
		return
	end
	local target = raceTarget()
	if target then
		raceLost = 0
		ReplicatedStorage:SetAttribute("RaceTarget", target)
	else
		-- Gold-Ei verschwunden (Admin aufgeräumt, Träger hat das Spiel verlassen ...)
		raceLost += 1
		if raceLost >= RACE_LOST_CHECKS then
			endRace(nil)
		end
	end
end

-- Ist gerade (oder gleich) ein anderes Event? Dann wartet das Rennen.
local function raceBlocked(t: number): boolean
	if MeteorService.IsShowerActive() or MeteorService.IsEggRushActive() then
		return true
	end
	if nextShowerAt - t < RACE_BUSY_GAP or nextEggRushAt - t < RACE_BUSY_GAP then
		return true
	end
	local night = nightState()
	local nextNight = tonumber(ReplicatedStorage:GetAttribute("NextNightAt")) or 0
	return not night and nextNight > t and nextNight - t < RACE_NIGHT_GAP
end

-- -------------------------------------------------------------------
-- EVENT-TIMER (Schauer, Egg Rush, Rennen – zeitlich versetzt)
-- -------------------------------------------------------------------
local function eventStep()
	local t = now()
	-- Meteoritenschauer: wartet, bis ein laufender Egg Rush / ein Rennen vorbei ist
	if not MeteorService.IsShowerActive() and t >= nextShowerAt then
		if MeteorService.IsEggRushActive() then
			nextShowerAt = eggRushUntil + SHOWER_AFTER_RUSH
			publishAttributes()
		elseif raceActive then
			nextShowerAt = raceUntil + SHOWER_AFTER_RUSH
			publishAttributes()
		else
			MeteorService.StartShower()
		end
	end
	-- Egg Rush: nicht im Schauer/Rennen und nicht kurz davor (sonst gehen beide Events unter)
	if not MeteorService.IsEggRushActive() and t >= nextEggRushAt then
		local showerSoon = nextShowerAt - t < Config.EggRushDuration + SHOWER_AFTER_RUSH
		if #Players:GetPlayers() == 0 then
			nextEggRushAt = t + 30
			publishAttributes()
		elseif raceActive then
			nextEggRushAt = raceUntil + SHOWER_AFTER_RUSH
			publishAttributes()
		elseif MeteorService.IsShowerActive() or showerSoon then
			local showerEnd = MeteorService.IsShowerActive() and showerUntil or (nextShowerAt + Config.ShowerDuration)
			nextEggRushAt = showerEnd + EGG_RUSH_SHOWER_GAP
			publishAttributes()
		else
			MeteorService.StartEggRush()
		end
	end
	-- Rennen
	if not raceActive and t >= nextRaceAt then
		if #Players:GetPlayers() == 0 then
			nextRaceAt = t + 30
			publishAttributes()
		elseif raceBlocked(t) then
			nextRaceAt = t + RACE_RETRY
			publishAttributes()
		else
			MeteorService.StartRace()
		end
	end
	raceStep()
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
	nestFolder = getFolder("NestMeteors") -- Name wird vom Client gesucht!
	groundFolder = getFolder("GroundMeteors")
	loadNests()
end

function MeteorService.Start()
	local t = now()
	nextShowerAt = t + Config.ShowerInterval
	nextEggRushAt = t + Config.EggRushInterval / 2 -- versetzt: erster Egg Rush lange vor dem ersten Schauer
	nextRaceAt = t + (tonumber(RACE.Interval) or 420) / 2 -- erstes Rennen zwischen Egg Rush und Schauer
	publishAttributes()
	publishPity()
	Players.PlayerRemoving:Connect(function(player)
		actionLimiter.Clear(player)
	end)

	-- Nester-Schleife (nur Rechnen + gelegentlich ein neues Ei – nichts bewegt sich)
	task.spawn(function()
		while true do
			task.wait(0.1)
			local ok, err = pcall(nestStep)
			if not ok then
				warn("[MeteorService] Nester-Fehler: " .. tostring(err))
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
