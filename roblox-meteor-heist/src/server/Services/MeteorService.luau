-- Meteore: die ALIEN-PARADE in der Map-Mitte, die Gratis-Zone am Spawn-Platz, Eier am Boden,
-- Meteoritenschauer, EGG RUSH, Server-Glück und der GLÜCKS-ZÄHLER (Config.Pity).
-- NACHT (NightService): Nacht-Eier in der Parade, Sternschnuppen-Eier (SpawnSkyEgg), Blutmond-Glück.
-- Öffentliche Nacht-API (auch fürs Admin-Panel): MeteorService.StartNight(bloodMoon?, seconds?),
-- MeteorService.EndNight(), MeteorService.IsNight(), MeteorService.IsBloodMoon().
--
-- ALIEN-PARADE: kleine Aliens laufen vom UFO-Hangar zum Ziel-Tor und tragen 1-3 Eier auf dem Kopf.
-- Jedes Ei hat ZWEI Knöpfe
--   E halten = KLAUEN (GrabPrompt): gratis, aber man muss es selbst nach Hause TRAGEN
--              (CarryService, Source = "Ground"). Klappt das nicht (Bonk, Tod, Falle, zu langsam),
--              fällt es als GRATIS-Ei auf den Boden und jeder kann es schnappen.
--   F        = KAUFEN (BuyPrompt): kostet Cash, fliegt automatisch in die eigene Base.
-- Seltene Eier (ab Config.Parade.BossFromRarity) trägt ein großer, langsamer BOSS mit Leibwächtern.
-- Die Leibwächter schubsen alle PushInterval Sekunden jeden weg, der dem Boss zu nahe kommt –
-- dazwischen klappt Klauen mit gutem Timing.
-- EIER AM BODEN ("Drop"): fallen gelassen oder vom Egg Rush – nur E = Schnappen und Tragen.
--
-- PERFORMANCE: Parade-Eier werden vom Server EINMAL im Start-Hangar erzeugt und NIE bewegt.
-- Die Träger-Aliens gibt es nur beim Client (lokal, gepoolt). Jeder Client rechnet die Position selbst
-- aus (ParadePath + Attribute ParadeP0, ParadeSpeed, ParadeLane, ParadeOffset, Carrier, CarrierId):
--   Strecke = (Parade-Uhr jetzt - ParadeP0) * ParadeSpeed
-- Der Server prüft beim Kaufen/Klauen mit genau dieser Formel (ParadePath).
-- METEORITENSCHAUER: Träger starten viel öfter und die Parade-Uhr läuft schneller (alle gleichzeitig).
-- ANTI-CHEAT: Halten wird serverseitig geprüft (MeteorFactory.OnHeldTrigger), Klauen/Kaufen ist
-- pro Spieler gebremst, Eingefrorene (Falle/Admin) können nichts nehmen.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))
local ParadePath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ParadePath"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local MeteorFactory = require(script.Parent:WaitForChild("MeteorFactory"))

local MeteorService = {}
local Services

local rng = Random.new()

-- Parade-Eier: { Kind = "Parade", Entry, Part, Price, T0, P0, Speed, Lane, Offset, Boss, Guards,
--   CarrierId, NextPush, Claimed, ClientReach, HorizReach }
local paradeRecords = {}
-- Gratis-Zone/Showcase (Kaufen/Schnappen = fliegt automatisch in die Base):
--   { Kind = "Ground", Entry, Part, Price, Position, Expires, Claimed, Landed, ClientReach }
local groundRecords = {}
-- Eier am Boden zum Schnappen + Tragen (fallen gelassen / Egg Rush):
--   { Kind = "Drop", Entry, Part, Price = 0, Position, Expires, Claimed, Landed, ClientReach, EggRush }
local dropRecords = {}
local paradeFolder: Folder
local groundFolder: Folder

-- Warteschlange für Parade-Eier (Admin-Regen etc.)
local paradeQueue = {}
-- Letzter Träger je Spur (für den Mindestabstand): { P0, Speed, Back }
local laneLast: { [number]: { P0: number, Speed: number, Back: number } } = {}
local nextLane = 1
local pendingNatural = nil -- schon gewürfelte nächste Gruppe (1-3 Eier), wartet auf Platz
local spareEntry = nil -- beim Stapeln gewürfeltes großes Ei -> kommt als nächstes einzeln
local nextNaturalAt = 0
local carrierCounter = 0

-- Parade-Uhr (siehe ParadePath): P(t) = clockP + (t - clockT) * clockRate
local clockT, clockP, clockRate = 0, 0, 1

local PARADE = Config.Parade
local BOSS_FROM = Config.RarityIndex[PARADE.BossFromRarity] or 5
local GUARDS_PLUS_FROM = Config.RarityIndex[PARADE.GuardsPlusFrom] or 6
local STACK_MAX_RARITY = Config.RarityIndex[PARADE.StackMaxRarity] or 2
local BOSS_FRONT = 4.5 -- Platz vor dem Boss-Mittelpunkt (Studs)
local BOSS_BACK = 9 -- Platz dahinter (hinterer Leibwächter)
local CARRIER_MIN_HALF = 1.3 -- halbe Tiefe eines kleinen Trägers
-- Ausweichen beim Überholen eines Bosses (gleiche Werte wie der Client!)
local DODGE_ZONE = 8
local DODGE_FADE = 5
local DODGE_OFFSET = 8.4
-- Reichweite an der Parade: waagrecht gerechnet (Eier sitzen hoch auf dem Kopf)
-- (12: vom Bordstein erreicht man beide Spuren, aber nicht vom eigenen Base-Eingang aus)
local PARADE_CLIENT_REACH = 12
local PARADE_REACH_EXTRA = 4 -- Spielraum beim Server (Ping)
-- am Boss weniger Spielraum: BossGrabReach + das bleibt INNERHALB der Schubs-Zone (PushRadius)
local BOSS_REACH_EXTRA = 2
local PARADE_REACH_SAMPLES = 6 -- Server prüft auch, wo das Ei bis zu 0,6 s vorher war (Ping)
local PARADE_VERTICAL_EXTRA = 8
local ROOT_HEIGHT = 2.5 -- Hüfte über dem Boden (für die 3D-Reichweite am Client)
local PUSH_NOTIFY_GAP = 8 -- Hinweis "Leibwächter schubsen" höchstens alle 8 s pro Spieler
-- Eier am Boden liegen still: Spielraum nur für die Bewegung des Spielers während der Ping-Zeit
local STATIC_REACH_BASE = 2
local STATIC_REACH_PER_SPEED = 0.1 -- pro Laufgeschwindigkeit
local STATIC_REACH_MIN = 3
local STATIC_REACH_MAX = 10
local FALL_TIME = 0.9 -- so lange fliegt ein Meteor vom Himmel bzw. in die Base (Client-Effekt)
-- Zwei Knöpfe am selben Meteor: Klauen oben, Kaufen darunter (Pixel), sonst liegen sie übereinander
local GRAB_UI_OFFSET = Vector2.new(0, -40)
local BUY_UI_OFFSET = Vector2.new(0, 40)
local RARE_GRAB_ANNOUNCE = Config.RarityIndex.Mythic or 6 -- ab Mythic: allen sagen, wer gerade klaut
local ADMIN_SPAWN_ANNOUNCE = Config.RarityIndex.Mythic or 6 -- vom Admin bestellte Eier: schon ab Mythic
-- ab Secret (auch Admin-Eier): Ansage IMMER (nicht gebremst) – so ein Ei will niemand verpassen
local SECRET_SPAWN_ANNOUNCE = Config.RarityIndex.Secret or 9
local RARE_ANNOUNCE_GAP = 4 -- solche Ansagen höchstens alle 4 Sekunden (sonst ist der Bildschirm voll)
-- Kaufen/Klauen/Schnappen pro Spieler höchstens so oft pro Sekunde (gegen Massen-Auslösen per Cheat)
local actionLimiter = Util.RateLimiter(6, 1)
local pushNotifyAt: { [Player]: number } = {}

-- Egg Rush: Eier fallen nacheinander (sieht nach Regen aus) aus dieser Höhe
local EGG_RUSH_SKY = 120
local EGG_RUSH_SPAWN_GAP = 0.08
local EGG_SPOT_TRIES = 30 -- Versuche pro Ei, einen freien Wiesen-Platz zu finden
local EGG_EDGE_MARGIN = 8 -- Abstand zum Map-Rand
local EGG_ROAD_CLEARANCE = 4 -- Abstand zum Straßenrand der Parade
local EGG_PLOT_MARGIN = 3 -- Abstand zu Basen
local EGG_SPACING = 3 -- Abstand zwischen zwei Eiern
local EGG_RUSH_SHOWER_GAP = 60 -- Egg Rush nicht direkt vor/nach dem Meteoritenschauer
local SHOWER_AFTER_RUSH = 20 -- Schauer wartet, bis der Egg Rush vorbei ist (+ so viele Sekunden)
-- Ersatz-Grenzen, falls die Map keine "Boundary"-Wände hat
local FALLBACK_AREA = { MinX = -168, MaxX = 168, MinZ = -406, MaxZ = 256 }

local serverLuckMult = 1
local serverLuckUntil = 0
local showerUntil = 0
local nextShowerAt = 0
local eggRushUntil = 0
local nextEggRushAt = 0
local lastRareAnnounce = -math.huge

-- GLÜCKS-ZÄHLER (pro Server): Parade-Eier seit dem letzten Legendary+ (siehe Config.Pity)
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

local function publishPity()
	ReplicatedStorage:SetAttribute("PityCount", pityCount)
	ReplicatedStorage:SetAttribute("PityFull", PITY_FULL)
	ReplicatedStorage:SetAttribute("PityMult", pityMult())
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
end

-- Ansage an alle für seltene Eier (Parade, Klauen) – höchstens alle RARE_ANNOUNCE_GAP Sekunden,
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
	publishAttributes()
	-- Im Schauer gibt es keine Locks! (Ein gekauftes Base-Schild bleibt aber an.)
	for _, plot in ipairs(Services.PlotService.Plots) do
		if not Services.PlotService.IsShielded(plot) then
			Services.PlotService.SetLocked(plot, 0)
		end
	end
	Services.EconomyService.NotifyAll(
		"🌠 METEORITENSCHAUER! Volle Parade, keine Locks, " .. Config.ShowerLuck .. "x Glück!",
		"Event"
	)
end

-- -------------------------------------------------------------------
-- ZUFALL
-- -------------------------------------------------------------------
-- luck: ab Rare mal Glück. pity: nur Legendary+ mal Glücks-Zähler. Nachts: Godly+ mal NightMult.
function MeteorService.RollRarity(luck: number, pity: number?)
	local night = nightState()
	local pityBonus = pity or 1
	return Util.WeightedPick(Config.Rarities, function(rarity)
		if rarity.AdminOnly or #Config.MeteorsByRarity[rarity.Name] == 0 then
			return 0
		end
		local index = Config.RarityIndex[rarity.Name]
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

-- Zufälliger Meteor einer Seltenheit (nur Meteore, die von selbst in die Parade kommen; includeAll = auch Admin/nicht spawnbare)
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
-- pity = Glücks-Bonus für Legendary+ (nur natürliche Parade-Eier, siehe rollNatural)
function MeteorService.RollEntry(luck: number?, pity: number?)
	local l = luck or MeteorService.GetLuck()
	local rarity = MeteorService.RollRarity(l, pity)
	local def = MeteorService.RandomOfRarity(rarity.Name) or Config.Meteors[1]
	return { Id = def.Id, Mut = MeteorService.RollMutation(l), Lv = 1, Xp = 0 }
end

-- Natürliches Parade-Ei: mit Glücks-Zähler. Legendary+ setzt ihn zurück, sonst +1.
local function rollNatural()
	local entry = MeteorService.RollEntry(nil, pityMult())
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
-- PARADE – Grundlagen (Pfad, Uhr, Positionen)
-- -------------------------------------------------------------------
local paradeWarned = false
local cachedPath: ParadePath.Path? = nil

-- Parade-Pfad (von MapBuilder über PlotService, sonst aus Config)
local function getPath(): ParadePath.Path?
	if cachedPath then
		return cachedPath
	end
	local parade = Services.PlotService.Parade
	local path = parade and parade.Path or ParadePath.FromConfig(Config)
	if path then
		cachedPath = path
		return path
	end
	if not paradeWarned then
		paradeWarned = true
		warn("[MeteorService] Kein Parade-Pfad gefunden – Parade-Eier können nicht spawnen!")
	end
	return nil
end

local function paradeMapFolder(): Instance?
	local parade = Services.PlotService.Parade
	return parade and parade.Folder or nil
end

local function clockAt(t: number): number
	return clockP + (t - clockT) * clockRate
end

-- Uhr an den Map-Ordner "Parade" schreiben (EIN Text-Attribut -> kommt immer komplett beim Client an)
local function publishClock()
	local folder = paradeMapFolder()
	if folder then
		folder:SetAttribute("ParadeClock", ParadePath.FormatClock(clockT, clockP, clockRate))
	end
end

-- Tempo der ganzen Parade ändern (Position bleibt stetig, nur das Tempo springt)
local function setClockRate(rate: number)
	local t = now()
	clockP = clockAt(t)
	clockT = t
	clockRate = rate
	publishClock()
end

-- Strecke eines Parade-Eis zur Serverzeit t
local function paradeDistance(record, t: number): number
	return (clockAt(t) - record.P0) * record.Speed
end

-- Seitlicher Versatz (mit Ausweichen vor Bossen) zur Zeit t bei Strecke dist
local function paradeLateral(record, dist: number, t: number): number
	if record.Boss then
		return record.Lane
	end
	local amount = 0
	for _, other in ipairs(paradeRecords) do
		if other.Boss and other.Part then
			amount = math.max(amount, ParadePath.DodgeAmount(dist, paradeDistance(other, t), DODGE_ZONE, DODGE_FADE))
		end
	end
	return ParadePath.Lateral(record.Lane, amount, DODGE_OFFSET)
end

-- Position des Eis zur Zeit t (nil = nicht auf der Strecke)
local function paradeEggPosition(record, t: number): Vector3?
	local path = getPath()
	if not path then
		return nil
	end
	local dist = paradeDistance(record, t)
	if dist < 0 or dist > path.Length then
		return nil
	end
	local pos, dir = ParadePath.Sample(path, dist)
	local lateral = paradeLateral(record, dist, t)
	return pos + ParadePath.Right(dir) * lateral + Vector3.new(0, record.Offset, 0)
end

function MeteorService.ParadePosition(record): Vector3?
	return paradeEggPosition(record, now())
end

local function listFor(kind: string)
	if kind == "Parade" then
		return paradeRecords
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
	if record.Kind == "Parade" then
		return paradeEggPosition(record, now())
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
	local tooFar
	if record.Kind == "Parade" then
		-- Das Ei läuft weiter, während der Klick unterwegs ist -> auch die Stellen der letzten 0,6 s
		-- zählen. Gerechnet wird waagrecht (das Ei sitzt hoch auf dem Kopf), dazu eine Höhen-Grenze.
		local t = now()
		local rootPos = root.Position
		local best = math.huge
		local bestY = position.Y
		for k = 0, PARADE_REACH_SAMPLES do
			local sample = if k == 0 then position else paradeEggPosition(record, t - k * 0.1)
			if sample then
				local dx, dz = sample.X - rootPos.X, sample.Z - rootPos.Z
				local d = math.sqrt(dx * dx + dz * dz)
				if d < best then
					best, bestY = d, sample.Y
				end
			end
		end
		local extra = if record.Boss then BOSS_REACH_EXTRA else PARADE_REACH_EXTRA
		tooFar = best > (record.HorizReach or clientReach) + extra
			or math.abs(rootPos.Y - bestY) > clientReach + PARADE_VERTICAL_EXTRA
	else
		-- liegt still: nur Spielraum für die eigene Bewegung (schnelle Spieler etwas mehr)
		local offset = root.Position - position
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

-- KAUFEN (Parade, F) / Schnappen in der Gratis-Zone: fliegt AUTOMATISCH in einen freien Slot
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

-- KLAUEN aus der Parade (E) / Schnappen eines Eis am Boden: gratis, aber selbst nach Hause tragen
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
	local fromParade = record.Kind == "Parade"
	removeRecord(record)
	Services.CarryService.StartCarry(player, entry, {
		Source = "Ground",
		From = fromParade and "Parade" or "Drop",
		GrabPosition = position,
	})
	local def = Config.MeteorsById[entry.Id]
	if fromParade and def and Config.RarityIndex[def.Rarity] >= RARE_GRAB_ANNOUNCE then
		local mut = entry.Mut ~= "Normal" and (entry.Mut .. " ") or ""
		rareAnnounce(player.DisplayName .. " klaut " .. def.Rarity .. " " .. mut .. def.Name .. "! Bonk ihn!")
	end
end

-- -------------------------------------------------------------------
-- PROMPTS
-- -------------------------------------------------------------------
-- Parade: E = Klauen (gratis, tragen), F = Kaufen (automatische Lieferung)
local function attachParadePrompts(record, serverReach: number)
	local part: BasePart = record.Part
	local def = Config.MeteorsById[record.Entry.Id]
	local radius = part.Size.X / 2
	-- waagrechte Reichweite: am Boss absichtlich klein (man muss in die Schubs-Zone der Leibwächter)
	local horiz = if record.Boss then PARADE.BossGrabReach else math.max(PARADE_CLIENT_REACH, radius + 10)
	record.HorizReach = horiz
	-- Der Client misst in 3D (zum Ei hoch auf dem Kopf) -> Höhe einrechnen
	local dy = math.max(0, PARADE.RoadTop + record.Offset - ROOT_HEIGHT)
	local clientReach = math.sqrt(horiz * horiz + dy * dy)
	record.ClientReach = clientReach

	local grab = MeteorFactory.AddPrompt(
		part,
		"GrabPrompt",
		"Klauen",
		def.Name,
		Config.ParadeGrabHold,
		Enum.KeyCode.E,
		serverReach
	)
	grab.GamepadKeyCode = Enum.KeyCode.ButtonX
	grab.UIOffset = GRAB_UI_OFFSET
	-- Der Client stellt die echte Reichweite lokal ein (die Server-Reichweite ist absichtlich riesig,
	-- weil das Ei auf dem Server im Start-Hangar bleibt).
	grab:SetAttribute("ClientMaxDistance", clientReach)
	-- gratis -> der Server prüft, ob wirklich so lange gehalten wurde
	MeteorFactory.OnHeldTrigger(grab, function(player)
		tryGrab(player, record)
	end)

	local action = record.Price > 0 and ("Kaufen " .. Util.FormatCash(record.Price)) or "Gratis holen"
	local buy = MeteorFactory.AddPrompt(
		part,
		"BuyPrompt",
		action,
		def.Name .. " (" .. def.Rarity .. ")",
		Config.ParadeBuyHold,
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
-- PARADE – Spawnen
-- -------------------------------------------------------------------
local BOSS_ANNOUNCE_GAP = 6 -- normale Boss-Ansagen höchstens alle 6 s
local lastBossAnnounce = -math.huge
local serverReachCache: number? = nil

local function rarityIndexOf(entry): number
	local def = Config.MeteorsById[entry.Id]
	return def and Config.RarityIndex[def.Rarity] or 1
end

local function isBossEntry(entry): boolean
	return rarityIndexOf(entry) >= BOSS_FROM
end

-- Gruppe = Eier auf EINEM Träger (1-3 gestapelt) oder ein einzelnes Boss-Ei
local function groupIsBoss(group: { any }): boolean
	return #group == 1 and isBossEntry(group[1])
end

-- Platz, den die Gruppe vor sich braucht (halbe Tiefe des Trägers bzw. des größten Eis)
local function groupFront(group: { any }): number
	if groupIsBoss(group) then
		return BOSS_FRONT
	end
	local front = CARRIER_MIN_HALF
	for _, entry in ipairs(group) do
		front = math.max(front, MeteorFactory.GetSize(entry) / 2)
	end
	return front
end

-- Startet einen Träger mit seinen Eiern im Start-Hangar (ohne Platzprüfung – dafür sorgt die Schleife).
-- free = gratis, lane = Spur (Boss: egal, läuft in der Mitte)
-- shouldAnnounce: nil = natürlich (Boss-Ansage gebremst), true = vom Admin bestellt, false = still
local function spawnCarrier(group: { any }, free: boolean, lane: number, shouldAnnounce: boolean?)
	local path = getPath()
	if not path or #group == 0 then
		return
	end
	local t = now()
	local p0 = clockAt(t)
	local boss = groupIsBoss(group)
	local speed = Config.ParadeSpeed * (if boss then PARADE.BossSpeedFactor else 1)
	local laneOffset = if boss then 0 else lane
	local index = rarityIndexOf(group[1])
	local guards = if not boss then 0 elseif index >= GUARDS_PLUS_FROM then 3 else 2
	carrierCounter += 1
	local startPos, startDir = ParadePath.Sample(path, 0)
	local side = ParadePath.Right(startDir)
	local serverReach = serverReachCache
	if not serverReach then
		-- Server-Reichweite = ganze Strecke (das Ei bleibt auf dem Server im Hangar), echte Prüfung in checkReach
		serverReach = ParadePath.MaxDistanceFrom(path, startPos) + 60
		serverReachCache = serverReach
	end
	local height = PARADE.CarrierHeight * (if boss then PARADE.BossScale else 1)
	for stack, entry in ipairs(group) do
		local size = MeteorFactory.GetSize(entry)
		local offset = height + size / 2 + 0.05 -- Ei-Mitte über der Straße (gestapelt: übereinander)
		height += size
		local price = if free then 0 else math.floor(Config.MeteorValue(entry))
		local part = MeteorFactory.Create(entry, "Parade", price)
		part.CFrame = CFrame.new(startPos + side * laneOffset + Vector3.new(0, offset, 0))
		-- Attribute VOR dem Parenten setzen -> kommen gleichzeitig beim Client an
		part:SetAttribute("ParadeT0", t)
		part:SetAttribute("ParadeP0", p0)
		part:SetAttribute("ParadeSpeed", speed)
		part:SetAttribute("ParadeLane", laneOffset)
		part:SetAttribute("ParadeOffset", offset)
		part:SetAttribute("ParadeStack", stack)
		part:SetAttribute("Carrier", if boss then "Boss" else "Small")
		part:SetAttribute("CarrierId", carrierCounter)
		if boss then
			part:SetAttribute("ParadeGuards", guards)
		end
		local record = {
			Kind = "Parade",
			Entry = entry,
			Part = part,
			Price = price,
			T0 = t,
			P0 = p0,
			Speed = speed,
			Lane = laneOffset,
			Offset = offset,
			Boss = boss,
			Guards = guards,
			CarrierId = carrierCounter,
			NextPush = t + PARADE.PushInterval,
			Claimed = false,
		}
		table.insert(paradeRecords, record)
		attachParadePrompts(record, serverReach)
		part.Parent = paradeFolder
	end

	-- Abstand merken: ein Boss sperrt alle Spuren (er läuft in der Mitte, Leibwächter daneben)
	local info = { P0 = p0, Speed = speed, Back = if boss then BOSS_BACK else groupFront(group) }
	if boss then
		for _, l in ipairs(PARADE.Lanes) do
			laneLast[l] = info
		end
	else
		laneLast[lane] = info
	end

	if boss then
		local entry = group[1]
		if shouldAnnounce == true and index >= ADMIN_SPAWN_ANNOUNCE then
			announce(entry, "👑 Ein Boss bringt %s zur Parade!")
		elseif shouldAnnounce == nil and index >= SECRET_SPAWN_ANNOUNCE then
			announce(entry, "👑 WAHNSINN! Ein Boss bringt %s zur Parade!")
		elseif shouldAnnounce == nil and os.clock() - lastBossAnnounce >= BOSS_ANNOUNCE_GAP then
			lastBossAnnounce = os.clock()
			announce(entry, "👑 Boss-Parade: %s – mit Leibwächtern!")
		end
	end
end

-- Hat die Spur am Start genug Platz für eine Gruppe mit diesem vorderen Platzbedarf?
local function laneHasRoom(lane: number, front: number, t: number): boolean
	local last = laneLast[lane]
	if not last then
		return true
	end
	local traveled = (clockAt(t) - last.P0) * last.Speed
	return traveled >= last.Back + front + PARADE.Gap
end

-- Freie Spur (nil = gerade kein Platz, kurz warten). Kleine Träger abwechselnd, Boss braucht alle Spuren.
local function pickLane(group: { any }): number?
	local t = now()
	local front = groupFront(group)
	local lanes = PARADE.Lanes
	if groupIsBoss(group) then
		for _, lane in ipairs(lanes) do
			if not laneHasRoom(lane, front, t) then
				return nil
			end
		end
		return 0
	end
	for _ = 1, #lanes do
		local lane = lanes[nextLane] or 0
		nextLane = nextLane % #lanes + 1
		if laneHasRoom(lane, front, t) then
			return lane
		end
	end
	return nil
end

-- Nächste natürliche Gruppe: kleine Eier werden oft gestapelt (1-3 auf einem Träger)
local function rollGroup(): { any }
	local first = spareEntry or rollNatural()
	spareEntry = nil
	local group = { first }
	if rarityIndexOf(first) <= STACK_MAX_RARITY then
		local chances = PARADE.StackChances
		local r = rng:NextNumber()
		local count = 1
		local sum = 0
		for i, chance in ipairs(chances) do
			sum += chance
			if r < sum then
				count = i
				break
			end
			count = i
		end
		for _ = 2, count do
			local extra = rollNatural()
			if rarityIndexOf(extra) <= STACK_MAX_RARITY then
				table.insert(group, extra)
			else
				spareEntry = extra -- großes Ei: kommt als nächstes einzeln
				break
			end
		end
	end
	return group
end

-- Leibwächter schubsen alle weg, die dem Boss zu nahe kommen (wie ein Bonk, nur ohne Beute-Verlust)
local function pushAround(record, t: number)
	local path = getPath()
	if not path then
		return
	end
	local dist = paradeDistance(record, t)
	if dist < 6 or dist > path.Length - 6 then
		return -- noch im Hangar / schon im Ziel-Tor
	end
	local pos, dir = ParadePath.Sample(path, dist)
	local radius = PARADE.PushRadius
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 and not root.Anchored then
			local rootPos = root.Position
			local dx, dz = rootPos.X - pos.X, rootPos.Z - pos.Z
			local d = math.sqrt(dx * dx + dz * dz)
			if d < radius and rootPos.Y < pos.Y + 30 then
				local away = if d > 0.5 then Vector3.new(dx / d, 0, dz / d) else ParadePath.Right(dir)
				-- Rückstoß (läuft beim Spieler, weil der seine Physik besitzt)
				local attachment = Instance.new("Attachment")
				attachment.Parent = root
				local velocity = Instance.new("LinearVelocity")
				velocity.Attachment0 = attachment
				velocity.MaxForce = 1e6
				velocity.RelativeTo = Enum.ActuatorRelativeTo.World
				velocity.VectorVelocity = away * PARADE.PushForce + Vector3.new(0, 25, 0)
				velocity.Parent = root
				Debris:AddItem(velocity, 0.18)
				Debris:AddItem(attachment, 0.18)
				Services.EconomyService.Effect(player, "Shake", 0.4)
				local clock = os.clock()
				if clock - (pushNotifyAt[player] or -math.huge) >= PUSH_NOTIFY_GAP then
					pushNotifyAt[player] = clock
					Services.EconomyService.Notify(
						player,
						"Die Leibwächter schubsen! Greif zwischen den Schubsern zu.",
						"Info"
					)
				end
			end
		end
	end
end

-- opts: { Id?, Mut?, Rarity?, Free?, Announce? } -> kommt so bald wie möglich in die Parade
-- (Announce = true: allen ansagen, ab Mythic)
function MeteorService.QueueParade(opts)
	table.insert(paradeQueue, opts or {})
end

-- Ein Schritt der Parade-Schleife: Uhr-Tempo, Abmelden, Schubsen, Warteschlange, natürliche Träger
local function paradeStep()
	local t = now()
	local shower = MeteorService.IsShowerActive()
	local wantedRate = if shower then tonumber(Config.ShowerParadeSpeedMult) or 1 else 1
	if clockRate ~= wantedRate then
		setClockRate(wantedRate)
	end
	local path = getPath()
	if not path then
		return
	end
	-- Eier hinter dem Ziel-Tor abmelden, Bosse schubsen (verschiedene Tempos -> alle prüfen)
	local length = path.Length
	local interval = PARADE.PushInterval
	for i = #paradeRecords, 1, -1 do
		local record = paradeRecords[i]
		if paradeDistance(record, t) > length then
			removeRecord(record)
		elseif record.Boss and t >= record.NextPush then
			record.NextPush += interval
			if record.NextPush <= t then
				record.NextPush = t + interval
			end
			pushAround(record, t)
		end
	end
	local cap = if shower
		then math.max(Config.MaxParadeMeteors, Config.ShowerMaxParadeMeteors)
		else Config.MaxParadeMeteors
	local queued = paradeQueue[1]
	if queued then
		if #paradeRecords >= cap then
			return
		end
		if not queued.Entry then
			queued.Entry = makeEntry(queued)
			if not queued.Entry then
				table.remove(paradeQueue, 1)
				return
			end
		end
		local group = { queued.Entry }
		local lane = pickLane(group)
		if lane then
			table.remove(paradeQueue, 1)
			-- vom Admin bestellt: Announce true/false, sonst (z.B. Meteorregen) keine Ansage
			spawnCarrier(group, queued.Free == true, lane, queued.Announce == true)
		end
		return
	end
	if #Players:GetPlayers() == 0 then
		return
	end
	if not pendingNatural and t >= nextNaturalAt then
		pendingNatural = rollGroup()
		local spawnInterval = if shower then Config.ShowerParadeInterval else Config.ParadeSpawnInterval
		nextNaturalAt = t + spawnInterval
	end
	local group = pendingNatural
	if group and #paradeRecords + #group <= cap then
		local lane = pickLane(group)
		if lane then
			pendingNatural = nil
			spawnCarrier(group, false, lane, nil)
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
	if paradeFolder then
		table.insert(ignore, paradeFolder)
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

-- Stelle auf der Parade-Straße? -> seitlich daneben auf die Wiese schieben.
-- Sonst läge das Ei still auf der Straße, während die Träger hindurchlaufen.
local DROP_ROAD_MARGIN = 2 -- so weit neben der Straße zählt noch als "auf der Straße"
local DROP_ROAD_GAP = 4 -- so weit neben der Straße landet das Ei (plus sein Radius)
local function offParade(position: Vector3, radius: number): Vector3
	local path = getPath()
	if not path then
		return position
	end
	local halfWidth = (tonumber(PARADE.RoadWidth) or 20) / 2
	local point, along, side, outward = ParadePath.Nearest(path, position)
	if along <= 0.01 or along >= path.Length - 0.01 or side >= halfWidth + DROP_ROAD_MARGIN then
		return position -- neben der Straße (oder vor/hinter Hangar und Tor)
	end
	local target = point + outward * (halfWidth + DROP_ROAD_GAP + radius)
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
	local spot = offParade(position, MeteorFactory.GetSize(clean) / 2)
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

-- Freier Platz auf der Wiese: innerhalb der Map, nicht in/an Basen, nicht an der Parade-Straße,
-- nicht auf dem Spawn-Platz/Bäumen (der Strahl muss genau den Wiesenboden "Ground" treffen).
local function findEggSpot(radius: number, groundPart: BasePart, params: RaycastParams): Vector3?
	local area = mapArea()
	local margin = EGG_EDGE_MARGIN + radius
	if area.MaxX - area.MinX <= margin * 2 or area.MaxZ - area.MinZ <= margin * 2 then
		return nil
	end
	local path = getPath()
	local roadClear = (tonumber(PARADE.RoadWidth) or 20) / 2 + EGG_ROAD_CLEARANCE + radius
	for _ = 1, EGG_SPOT_TRIES do
		local x = rng:NextNumber(area.MinX + margin, area.MaxX - margin)
		local z = rng:NextNumber(area.MinZ + margin, area.MaxZ - margin)
		local flatPos = Vector3.new(x, 0, z)
		local ok = true
		if path then
			local _, _, side = ParadePath.Nearest(path, flatPos)
			if side < roadClear then
				ok = false
			end
		end
		if ok then
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

-- Wiesenboden "Ground" der Map (nil = nicht gefunden)
local function meadowGround(): BasePart?
	local map = Services.PlotService.MapFolder
	local groundPart = map and map:FindFirstChild("Ground")
	if groundPart and groundPart:IsA("BasePart") then
		return groundPart
	end
	return nil
end

-- Freier Platz auf der Wiese (wie beim Egg Rush) – z.B. für die leuchtenden Kisten der Nacht.
-- Gibt den Punkt AUF dem Boden zurück oder nil.
function MeteorService.FindMeadowSpot(radius: number): Vector3?
	local groundPart = meadowGround()
	if not groundPart then
		return nil
	end
	return findEggSpot(math.max(0.5, radius), groundPart, rayParams(false))
end

-- 🌠 STERNSCHNUPPE: ein Gratis-Ei fällt schräg vom Himmel auf die Wiese (wie Egg-Rush-Eier:
-- schnappen und heimtragen). opts: { Luck: number?, Lifetime: number? } -> Eintrag am Boden oder nil
function MeteorService.SpawnSkyEgg(opts)
	opts = opts or {}
	local groundPart = meadowGround()
	if not groundPart then
		return nil
	end
	local luck = MeteorService.GetLuck() * (tonumber(opts.Luck) or 1)
	local entry = MeteorService.RollEntry(luck)
	local spot = findEggSpot(MeteorFactory.GetSize(entry) / 2, groundPart, rayParams(false))
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
		announce(entry, "🌠 Eine Sternschnuppe bringt %s auf die Wiese!")
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

-- Allgemeiner Spawn (Admin-Panel): opts.Where = "Parade" (Standard), "Free" (Gratis-Zone) oder Position
function MeteorService.SpawnMeteor(opts)
	opts = opts or {}
	if opts.Position or opts.Where == "Free" then
		return MeteorService.SpawnStatic(opts)
	end
	MeteorService.QueueParade(opts)
	return nil
end

-- Parade, Gratis-Zone und alle Eier am Boden leeren
function MeteorService.ClearGround()
	for i = #groundRecords, 1, -1 do
		removeRecord(groundRecords[i])
	end
	for i = #dropRecords, 1, -1 do
		removeRecord(dropRecords[i])
	end
	for i = #paradeRecords, 1, -1 do
		removeRecord(paradeRecords[i])
	end
	table.clear(paradeQueue)
	table.clear(laneLast)
	pendingNatural = nil
	spareEntry = nil
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
	paradeFolder = getFolder("ParadeMeteors") -- Name wird vom Client gesucht!
	groundFolder = getFolder("GroundMeteors")
	-- Parade-Uhr starten (der Client braucht sie, um die Träger zu bewegen)
	clockT, clockP, clockRate = now(), 0, 1
	publishClock()
end

function MeteorService.Start()
	local t = now()
	nextShowerAt = t + Config.ShowerInterval
	nextEggRushAt = t + Config.EggRushInterval / 2 -- versetzt: erster Egg Rush lange vor dem ersten Schauer
	publishAttributes()
	publishPity()
	Players.PlayerRemoving:Connect(function(player)
		actionLimiter.Clear(player)
		pushNotifyAt[player] = nil
	end)

	-- Parade-Schleife (nur Rechnen + gelegentlich ein neues Part – kein Bewegen!)
	task.spawn(function()
		while true do
			task.wait(0.05)
			local ok, err = pcall(paradeStep)
			if not ok then
				warn("[MeteorService] Parade-Fehler: " .. tostring(err))
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
