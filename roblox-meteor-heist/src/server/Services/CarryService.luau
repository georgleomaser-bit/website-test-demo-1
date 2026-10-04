-- Klauen & Tragen:
--  * Fremde Meteore UND Aliens kann man klauen (E halten), wenn die Base nicht gesperrt ist,
--    und muss sie dann in die eigene Base tragen (Source = "Plot").
--    Wer mit dem Schläger getroffen wird, stirbt, in eine Falle tritt, zu langsam ist oder das Spiel verlässt,
--    verliert die Beute: sie fliegt zurück zum Besitzer.
--  * Eier aus den NESTERN (E = Schnappen) und Eier am Boden (fallen gelassen / Egg Rush) sind gratis,
--    müssen aber auch nach Hause getragen werden (Source = "Ground"). Klappt das nicht,
--    fällt das Ei an Ort und Stelle auf den Boden – und JEDER kann es schnappen.
--  * Gekaufte Meteore (F) muss man NICHT tragen – sie fliegen automatisch in die Base.
--  * Schläger zum Verteidigen (Stufe nach Index, Config.Bats; Gadget "Super-Schlag" = Boost).
--  * Wilde Kreaturen im Nester-Feld (FieldService) schubsen wie ein Schläger-Treffer: CarryService.CreatureHit.
--  * Seltene Beute ist schwer (Config.HeavyCarry, Tempo rechnet EconomyService), wer klaut, verliert
--    den Umhang (sonst könnte man Diebe nie treffen), Eingefrorene können nicht klauen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))
local MeteorFactory = require(script.Parent:WaitForChild("MeteorFactory"))
local AlienFactory = require(script.Parent:WaitForChild("AlienFactory"))

local CarryService = {}
local Services

local carrying: { [Player]: any } = {}
local stealing: { [any]: { [number]: Player } } = {} -- [plot][slot] = Dieb
local lastBonk: { [Player]: number } = {}
-- Klau-Versuche aus Basen pro Spieler höchstens so oft pro Sekunde (gegen Massen-Auslösen per Cheat)
local stealLimiter = Util.RateLimiter(6, 1)

local CARRY_HEIGHT = 2.6 -- Abstand über dem HumanoidRootPart (Unterkante der Beute)
-- Mindest-Tragezeit: kürzester möglicher Weg (raus aus der fremden Base, rein in die eigene)
-- geteilt durch Trage-Tempo * diesen Faktor. Schneller geht es nur mit Teleport/Durch-Wände-Laufen.
local MIN_CARRY_SPEED_FACTOR = 1.5
-- Laufbänder (Treadmills) schieben mit (wer mit Beute auf dem Band mitfährt, ist schneller)
local CONVEYOR_EXTRA_SPEED = 14
-- Schläger in Ruhe: Griff in der Hand, Schläger zeigt nach oben und lehnt etwas nach hinten
-- (der Client schwingt ihn beim Schlagen über Tool.Grip, siehe Client-Modul "Bat")
local BAT_REST_GRIP = CFrame.new(0, -0.4, 0) * CFrame.Angles(math.rad(-15), 0, 0)
-- Lange Heimwege (info.ScaleTimeout, z.B. das Ei vom Meteor-Run): Trage-Zeit = Weg / Trage-Tempo * TRIP_SLACK
-- + TRIP_EXTRA, mindestens Config.CarryTimeout. Der Weg wird großzügig gerechnet (|dx| + |dz| bis zum
-- Eingang der eigenen Base – Umwege um Basen und Nester sind darin enthalten).
local TRIP_SLACK = 1.3
local TRIP_EXTRA = 10
local TRIP_MAX = 240

-- Fortschritt für die Tagesaufgaben (RewardService) – ein Fehler dort darf das Klauen nie stören
local function trackReward(player: Player, kind: string, amount: number)
	local rewards = Services.RewardService
	if rewards and rewards.Track then
		local ok, err = pcall(rewards.Track, player, kind, amount)
		if not ok then
			warn("[CarryService] RewardService.Track(" .. kind .. ") fehlgeschlagen: " .. tostring(err))
		end
	end
end

local function ownsGadget(player: Player, id: string): boolean
	local gadgets = Services.GadgetService
	return gadgets ~= nil and gadgets.Owns(player, id) == true
end

-- Höchstes mögliches Trage-Tempo (für die Mindest-Tragezeit): Schritte-Tempo * Trage-Faktor
-- (Gamepass "Volle Speed beim Tragen" = kein Abzug), Speed Coil + Speed-Pad obendrauf
-- (ein Pad kann man unterwegs jederzeit mitnehmen), plus Laufband-Schub
local function maxCarrySpeed(player: Player): number
	local factor = Services.MonetizationService.HasPass(player, "CarryFast") and 1 or Config.CarrySpeedFactor
	local speed = math.max(8, Services.EconomyService.GetSpeed(player) * factor)
	if ownsGadget(player, "SpeedCoil") then
		speed *= 1 + Config.SpeedCoilBonus
	end
	speed *= 1 + (tonumber(Config.SpeedPads and Config.SpeedPads.Boost) or 0)
	return speed + CONVEYOR_EXTRA_SPEED
end

function CarryService.IsCarrying(player: Player): boolean
	return carrying[player] ~= nil
end

-- Was trägt der Spieler gerade? (Eintrag { Id, Mut, ... } oder nil) – z.B. für "schwere Beute"
function CarryService.CarriedEntry(player: Player): any
	local info = carrying[player]
	return info and info.Entry
end

-- -------------------------------------------------------------------
-- BEWEGUNGS-PRÜFUNG (gegen Teleport- und Speed-Exploits)
-- -------------------------------------------------------------------
-- Die Position des Charakters bestimmt der Client. Deshalb hat jeder Spieler ein "Weg-Budget":
-- Es füllt sich mit dem erlaubten Tempo wieder auf, jede Bewegung verbraucht es (nur waagrecht,
-- Fallen zählt nicht). Ist es leer, war der Spieler unmöglich schnell -> kurz keine Käufe/Diebstähle,
-- getragene Beute fliegt zurück. Der Vorrat reicht für kurze Ping-Hänger (Position kommt gesammelt an).
local MOVE_RATE_FACTOR = 1.5 -- erlaubtes Tempo = WalkSpeed * 1.5 + MOVE_RATE_EXTRA
local MOVE_RATE_EXTRA = 16 -- Laufbänder schieben, Bonk-Rückstoß, kleine Physik-Sprünge
local MOVE_BUDGET_SECONDS = 0.75 -- Vorrat = so viele Sekunden erlaubtes Tempo
local MOVE_FLAG_TIME = 1.5 -- nach einem Verstoß so lange gesperrt
-- Nach einem Server-Teleport kurz warten: alte Positionen (vor dem Teleport) können noch ankommen.
-- In der Zeit zählen nur Positionen nahe am Teleport-Ziel, Kaufen/Klauen geht erst danach.
local TELEPORT_GRACE = 1
local TELEPORT_ANCHOR_RADIUS = 30

type MoveTrack = {
	Pos: Vector3?, -- letzte anerkannte Position
	Time: number,
	Budget: number,
	FlaggedUntil: number,
	GraceUntil: number,
	Anchor: Vector3?, -- Ziel des letzten Server-Teleports
	Extra: number?, -- Zusatz-Weg nach einem Schläger-Treffer (Rückstoß ist kein Cheat)
	ExtraUntil: number?,
}
local moveTrack: { [Player]: MoveTrack } = {}

-- Server-Teleports (Home, Laufbänder, Lock-Rauswurf, Admin, Respawn) sind erlaubt.
-- destination = Ziel des Teleports (nil = unbekannt, z.B. neuer Charakter)
function CarryService.NoteTeleport(player: Player, destination: Vector3?)
	local now = os.clock()
	local old = moveTrack[player]
	moveTrack[player] = {
		Pos = destination,
		Time = now,
		Budget = 0,
		FlaggedUntil = old and old.FlaggedUntil or 0,
		GraceUntil = now + TELEPORT_GRACE,
		Anchor = destination,
	}
	local info = carrying[player]
	if info then
		info.MinTime = 0 -- vom Server versetzt -> Mindest-Tragezeit gilt nicht mehr
	end
end

-- Rückstoß vom Schläger: der Getroffene darf kurz weiter "fliegen", ohne als Teleport zu gelten
local function allowKnockback(player: Player, studs: number)
	local track = moveTrack[player]
	if not track then
		return
	end
	local now = os.clock()
	track.Extra = studs
	track.ExtraUntil = now + 1.5
	track.Budget += studs
end

-- Misst die Bewegung seit der letzten Messung:
--   "ok"      = alles plausibel (darf kaufen/klauen)
--   "wait"    = gerade vom Server teleportiert (kurz warten, Beute bleibt)
--   "flagged" = unmöglich schnell oder noch gesperrt (Beute fliegt zurück)
function CarryService.MoveStatus(player: Player): string
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return "ok"
	end
	local admin = Services.AdminService
	if admin and admin.IsAdmin(player) then
		return "ok" -- Admins dürfen fliegen und teleportieren
	end
	local now = os.clock()
	local rate = humanoid.WalkSpeed * MOVE_RATE_FACTOR + MOVE_RATE_EXTRA
	local cap = rate * MOVE_BUDGET_SECONDS
	local pos = root.Position
	local track = moveTrack[player]
	if not track then
		track = { Pos = nil, Time = now, Budget = cap, FlaggedUntil = 0, GraceUntil = 0, Anchor = nil }
		moveTrack[player] = track
	end
	if now < track.GraceUntil then
		local anchor = track.Anchor
		local dx, dz = 0, 0
		if anchor then
			dx, dz = pos.X - anchor.X, pos.Z - anchor.Z
		end
		if dx * dx + dz * dz <= TELEPORT_ANCHOR_RADIUS * TELEPORT_ANCHOR_RADIUS then
			track.Pos = pos
		end
		track.Time = now
		track.Budget = cap
		return "wait"
	end
	local last = track.Pos
	if not last then
		-- erste Messung: nur merken (Kaufen/Klauen erst ab der nächsten Messung)
		track.Pos = pos
		track.Time = now
		track.Budget = cap
		return if now >= track.FlaggedUntil then "wait" else "flagged"
	end
	local dx, dz = pos.X - last.X, pos.Z - last.Z
	local distance = math.sqrt(dx * dx + dz * dz)
	local extra = if now < (track.ExtraUntil or 0) then track.Extra or 0 else 0
	local budget = math.min(cap + extra, track.Budget + rate * math.max(0, now - track.Time)) - distance
	track.Pos = pos
	track.Time = now
	if budget < 0 then
		track.Budget = cap
		track.FlaggedUntil = now + MOVE_FLAG_TIME
		return "flagged"
	end
	track.Budget = budget
	return if now >= track.FlaggedUntil then "ok" else "flagged"
end

-- Kürzester möglicher Weg (Studs) von "from" in der fremden Base bis in die eigene Base.
-- Die Basen sind OFFEN (nur ein niedriger Rand, über den man springen kann): man kann sie an JEDER
-- Kante verlassen und betreten. Gerechnet wird deshalb großzügig (Luftlinie bis zur nächsten Kante,
-- Abstand der beiden Rechtecke) -> echte Spieler sind immer langsamer.
-- Waagrechter Abstand eines Punkts zum Rechteck der Base (0 = drin)
local function distanceToPlot(plot, p: Vector3): number
	local minX, maxX, minZ, maxZ = Services.PlotService.WorldRect(plot)
	local dx = math.max(minX - p.X, 0, p.X - maxX)
	local dz = math.max(minZ - p.Z, 0, p.Z - maxZ)
	return math.sqrt(dx * dx + dz * dz)
end

-- Von innen: Weg bis zur nächsten Kante der Base
local function distanceToEdge(plot, p: Vector3): number
	local hx, hz = Services.PlotService.HalfExtents(plot)
	local localPos = plot.CFrame:PointToObjectSpace(p)
	return math.max(0, math.min(hx - math.abs(localPos.X), hz - math.abs(localPos.Z)))
end

-- Lücke zwischen zwei Basen-Rechtecken (0 = berühren sich)
local function plotGap(a, b): number
	local aMinX, aMaxX, aMinZ, aMaxZ = Services.PlotService.WorldRect(a)
	local bMinX, bMaxX, bMinZ, bMaxZ = Services.PlotService.WorldRect(b)
	local dx = math.max(bMinX - aMaxX, 0, aMinX - bMaxX)
	local dz = math.max(bMinZ - aMaxZ, 0, aMinZ - bMaxZ)
	return math.sqrt(dx * dx + dz * dz)
end

local function minCarryDistance(victimPlot, ownPlot, from: Vector3): number
	if victimPlot == ownPlot then
		return 0
	end
	return distanceToEdge(victimPlot, from) + plotGap(victimPlot, ownPlot)
end

-- Trage-Tempo OHNE Speed Coil (die kann man unterwegs weglegen) – gleiche Regeln wie EconomyService
local function slowCarrySpeed(player: Player, entry): number
	local factor = 1
	if not Services.MonetizationService.HasPass(player, "CarryFast") then
		factor = Config.CarrySpeedFactor
		local heavy = Config.HeavyFactor(entry)
		if heavy then
			factor = math.min(factor, heavy)
		end
	end
	return math.max(8, Services.EconomyService.GetSpeed(player) * factor)
end

-- Trage-Zeit für einen langen Heimweg (info.ScaleTimeout): proportional zur Entfernung zur eigenen Base
local function tripTimeout(player: Player, entry, from: Vector3?): number
	local plot = Services.PlotService.GetPlot(player)
	if not plot or not from then
		return Config.CarryTimeout
	end
	local _, halfZ = Services.PlotService.HalfExtents(plot)
	local entrance = plot.CFrame:PointToWorldSpace(Vector3.new(0, 0, -halfZ))
	local route = math.abs(from.X - entrance.X) + math.abs(from.Z - entrance.Z)
	local seconds = route / slowCarrySpeed(player, entry) * TRIP_SLACK + TRIP_EXTRA
	return math.clamp(math.ceil(seconds), Config.CarryTimeout, TRIP_MAX)
end

-- Mindest-Tragezeit für ein Ei aus einem Nest/vom Boden: Luftlinie bis zum Eingang der eigenen Base
local function minGroundCarryTime(player: Player, from: Vector3?): number
	local plot = Services.PlotService.GetPlot(player)
	if not plot or not from or Services.PlotService.IsInside(plot, from) then
		return 0
	end
	return distanceToPlot(plot, from) / (maxCarrySpeed(player) * MIN_CARRY_SPEED_FACTOR)
end

function CarryService.IsSlotBeingStolen(plot, slot: number): boolean
	local map = stealing[plot]
	return map ~= nil and map[slot] ~= nil
end

local function clearStealMark(info)
	if info.Source == "Plot" and stealing[info.VictimPlot] then
		stealing[info.VictimPlot][info.Slot] = nil
	end
end

local function cleanup(player: Player, info)
	carrying[player] = nil
	player:SetAttribute("CarryTimeout", nil)
	if info.Visual then
		info.Visual:Destroy()
		info.Visual = nil
	end
	Services.EconomyService.ApplySpeed(player)
	Services.EconomyService.MarkDirty(player)
end

-- Getragene Beute: alle Teile lose, gewichtslos, ohne Kollision, an den Spieler geschweißt
local function prepareCarryPart(p: BasePart)
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
end

local function weldTo(part0: BasePart, part1: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = part0
	w.Part1 = part1
	w.Parent = part1
end

-- Alien-Kopie über dem Kopf (Model: alle Teile an den Body, Body an den HumanoidRootPart)
local function createAlienVisual(entry, root: BasePart): Instance?
	local ok, result = pcall(AlienFactory.Create, entry, "Carry")
	if not ok or typeof(result) ~= "Instance" or not result:IsA("Model") then
		warn("[CarryService] Alien-Optik fehlgeschlagen: " .. tostring(result))
		return nil
	end
	local model = result :: Model
	local body = model.PrimaryPart or model:FindFirstChild("Body")
	if not body or not body:IsA("BasePart") then
		model:Destroy()
		return nil
	end
	model.Name = "CarriedAlien"
	model:SetAttribute("Bob", false) -- nicht wippen (würde den Spieler mitbewegen)
	model:PivotTo(root.CFrame * CFrame.new(0, CARRY_HEIGHT, 0))
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			prepareCarryPart(d)
			if d ~= body then
				weldTo(body, d)
			end
		end
	end
	weldTo(root, body)
	return model
end

local function createVisual(player: Player, entry): Instance?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not root then
		return nil
	end
	local visual: Instance? = nil
	if entry.Alien ~= nil then
		visual = createAlienVisual(entry, root)
	end
	if not visual then
		local meteor = MeteorFactory.Create(entry, "Carry")
		meteor.Name = "CarriedMeteor"
		prepareCarryPart(meteor)
		meteor.CFrame = root.CFrame * CFrame.new(0, CARRY_HEIGHT + meteor.Size.Y / 2, 0)
		weldTo(root, meteor)
		visual = meteor
	end
	if visual then
		visual.Parent = character
	end
	return visual
end

-- info (Plot):   { Source = "Plot", VictimPlot, VictimPlayer, Slot, EntryRef, MinTime? }
-- info (Ground): { Source = "Ground", From = "Nest"|"Drop"|"Race"|"Run"?, GrabPosition?, MinTime?, ScaleTimeout? }
--   ScaleTimeout = true: Trage-Zeit wächst mit der Entfernung zur eigenen Base (tripTimeout)
-- Dazu kommen hier: Entry, Started, Character, StartPos, LastPos (laufend), Visual, Timeout
function CarryService.StartCarry(player: Player, entry, info)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	info.Entry = entry
	info.Started = os.clock()
	info.Character = character
	info.StartPos = root and root.Position or info.GrabPosition
	info.LastPos = info.StartPos
	if info.MinTime == nil then
		info.MinTime = info.Source == "Ground" and minGroundCarryTime(player, info.StartPos) or 0
	end
	info.Timeout = if info.ScaleTimeout
		then tripTimeout(player, entry, info.StartPos)
		else tonumber(info.Timeout) or Config.CarryTimeout
	-- Client (HUD-Countdown) kennt so die echte Trage-Zeit
	player:SetAttribute("CarryTimeout", info.Timeout)
	-- Wer klaut, wird sichtbar: sonst wäre jeder Diebstahl mit Umhang unbonkbar
	local gadgets = Services.GadgetService
	local uncloaked = false
	if gadgets and gadgets.IsCloaked(player) then
		gadgets.EndCloak(player, true)
		uncloaked = true
	end
	info.Visual = createVisual(player, entry)
	carrying[player] = info
	Services.EconomyService.ApplySpeed(player)
	Services.EconomyService.MarkDirty(player)
	local extra = ""
	if Config.HeavyFactor(entry) and not Services.MonetizationService.HasPass(player, "CarryFast") then
		extra ..= " 🐢 Schwer – du bist langsamer!"
	end
	if uncloaked then
		extra ..= " 👻 Du bist wieder sichtbar!"
	end
	if info.Source == "Ground" then
		Services.EconomyService.Notify(
			player,
			"😈 Geschnappt: " .. Config.EntryName(entry) .. "! Schnell in deine Base 🏃" .. extra,
			"Info"
		)
	else
		Services.EconomyService.Notify(
			player,
			"🏃 Bring " .. Config.EntryName(entry) .. " in deine Base!" .. extra,
			"Info"
		)
	end
end

-- Weltposition der getragenen Beute (für den Fall-Effekt beim Fallenlassen)
local function visualPosition(info): Vector3?
	local visual = info.Visual
	if not visual or not visual.Parent then
		return nil
	end
	if visual:IsA("BasePart") then
		return visual.Position
	elseif visual:IsA("Model") then
		return visual:GetPivot().Position
	end
	return nil
end

-- Ei aus einem Nest/vom Boden sicher zu Hause -> in einen freien Slot, Schlüpf-Countdown startet
-- (das Gold-Ei des Rennens meldet hier den Sieg: MeteorService.FinishRace)
local function succeedGround(player: Player, info)
	local data = Services.DataService.Get(player)
	local plot = Services.PlotService.GetPlot(player)
	local slot = Services.PlotService.FreeSlot(player)
	if not data or not plot or not slot then
		CarryService.Fail(player, "full")
		return
	end
	local from = visualPosition(info)
	cleanup(player, info)
	local placed = Services.EconomyService.DeliverMeteor(player, plot, slot, info.Entry, from)
	if not placed then
		-- (sollte nie passieren) Ei nicht verlieren: an Ort und Stelle fallen lassen
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local spot = root and root.Position or info.LastPos
		if spot then
			Services.MeteorService.DropMeteor(info.Entry, spot, from)
		end
		return
	end
	data.Stats.Grabbed = (tonumber(data.Stats.Grabbed) or 0) + 1
	trackReward(player, "Grab", 1)
	Services.EconomyService.Notify(
		player,
		"🏠 Zuhause! " .. Config.EntryName(info.Entry) .. " schlüpft bald 🐣",
		"Success"
	)
	Services.EconomyService.Effect(player, "Confetti", 1)
	if info.Entry.Race ~= nil and Services.MeteorService.FinishRace then
		local ok, err = pcall(Services.MeteorService.FinishRace, player, info.Entry)
		if not ok then
			warn("[CarryService] FinishRace fehlgeschlagen: " .. tostring(err))
		end
	end
end

local function succeed(player: Player)
	local info = carrying[player]
	if not info then
		return
	end
	if info.Source == "Ground" then
		succeedGround(player, info)
		return
	end
	local data = Services.DataService.Get(player)
	local plot = Services.PlotService.GetPlot(player)
	local slot = Services.PlotService.FreeSlot(player)
	local name = Config.EntryName(info.Entry)

	local victim = info.VictimPlayer
	local victimData = victim and victim.Parent and Services.DataService.Get(victim)
	local key = tostring(info.Slot)
	if not data or not plot or not slot or not victimData or victimData.Meteors[key] ~= info.EntryRef then
		CarryService.Fail(player, slot and "invalid" or "full")
		return
	end
	victimData.Meteors[key] = nil
	data.Meteors[tostring(slot)] = info.EntryRef
	data.Stats.Stolen += 1
	victimData.Stats.Robbed += 1
	clearStealMark(info)
	cleanup(player, info)
	if info.EntryRef.Alien ~= nil then
		Services.EconomyService.Discover(player, info.EntryRef.Alien)
	end
	Services.PlotService.RenderSlot(plot, slot)
	Services.PlotService.RenderSlot(info.VictimPlot, info.Slot)
	Services.EconomyService.MarkDirty(victim)
	trackReward(player, "Steal", 1)
	Services.EconomyService.Notify(player, "😈 Geklaut: " .. name .. "!", "Success")
	Services.EconomyService.Notify(
		victim,
		"💔 " .. player.DisplayName .. " hat dein " .. name .. " geklaut!",
		"Error"
	)
	Services.EconomyService.Effect(player, "Confetti", 1)
end

-- Hinweise beim Verlieren: Beute aus einer Base fliegt zurück, ein Ei aus einem Nest fällt herunter
local PLOT_FAIL_TEXT = {
	bonked = "💥 Getroffen! Die Beute fliegt zurück.",
	timeout = "⏰ Zu langsam! Die Beute fliegt zurück.",
	full = "📦 Deine Base ist voll – die Beute fliegt zurück!",
	teleport = "🚫 Mit Beute kann man nicht teleportieren!",
	locked = "🔒 Die Base wurde gesperrt – deine Beute fliegt zurück!",
	trap = "🪤 FALLE! Die Beute fliegt zurück.",
	creature = "👾 Erwischt! Die Beute fliegt zurück.",
}
local GROUND_FAIL_TEXT = {
	bonked = "💥 Getroffen! Das Ei ist runtergefallen – schnapp es dir zurück!",
	timeout = "⏰ Zu langsam! Das Ei ist runtergefallen.",
	full = "📦 Deine Base ist voll – das Ei liegt jetzt am Boden!",
	teleport = "🚫 Mit Beute kann man nicht teleportieren!",
	locked = "🔒 Gesperrte Base – das Ei ist runtergefallen!",
	trap = "🪤 FALLE! Das Ei ist runtergefallen.",
	died = "💀 Das Ei ist runtergefallen – jemand anderes kann es jetzt schnappen!",
	creature = "👾 Erwischt! Das Ei ist runtergefallen.",
}

-- Ei aus einem Nest/vom Boden verloren -> fällt als GRATIS-Ei auf den Boden (jeder darf es schnappen)
local function dropGroundLoot(player: Player, info, reason: string, from: Vector3?)
	local spot: Vector3? = nil
	if reason == "teleport" or reason == "invalid" then
		-- Verdacht auf Teleport-Trick: dort ablegen, wo das Tragen angefangen hat
		spot = info.StartPos
	else
		-- nur der Charakter, der das Ei getragen hat (nach einem Respawn steht der neue woanders)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if character == info.Character and root and humanoid and humanoid.Health > 0 then
			spot = root.Position
		else
			spot = info.LastPos or info.StartPos
		end
	end
	if not spot then
		return
	end
	local ok, err = pcall(Services.MeteorService.DropMeteor, info.Entry, spot, from)
	if not ok then
		warn("[CarryService] Ei fallen lassen fehlgeschlagen: " .. tostring(err))
	end
end

function CarryService.Fail(player: Player, reason: string)
	local info = carrying[player]
	if not info then
		return
	end
	local from = visualPosition(info)
	clearStealMark(info)
	cleanup(player, info)
	local name = Config.EntryName(info.Entry)

	if info.Source == "Ground" then
		dropGroundLoot(player, info, reason, from)
		local text = GROUND_FAIL_TEXT[reason]
		if text then
			Services.EconomyService.Notify(player, text, "Error")
		end
		return
	end

	-- zurück zum Besitzer
	if info.VictimPlot and info.VictimPlot.Owner == info.VictimPlayer then
		Services.PlotService.RenderSlot(info.VictimPlot, info.Slot)
		Services.EconomyService.MarkDirty(info.VictimPlayer)
		if reason ~= "victimLeft" then
			Services.EconomyService.Notify(info.VictimPlayer, "🛡️ Dein " .. name .. " ist zurück!", "Success")
		end
	end
	local text = PLOT_FAIL_TEXT[reason]
	if text then
		Services.EconomyService.Notify(player, text, "Error")
	end
end

function CarryService.TrySteal(thief: Player, plot, slot: number)
	local owner = plot.Owner
	if not owner or owner == thief then
		return
	end
	if not stealLimiter.Check(thief) then
		return -- zu viele Versuche auf einmal (Cheat) -> still ignorieren
	end
	local thiefData = Services.DataService.Get(thief)
	local ownerData = Services.DataService.Get(owner)
	local Economy = Services.EconomyService
	if not thiefData or not ownerData or not Economy.IsReady(thief) or not Economy.IsReady(owner) then
		return
	end
	if Services.PlotService.IsLocked(plot) then
		Services.EconomyService.Notify(thief, "🔒 Diese Base ist gesperrt!", "Error")
		return
	end
	if owner:GetAttribute("AdminGod") == true then
		Services.EconomyService.Notify(thief, "Diese Base ist geschützt.", "Error")
		return
	end
	if CarryService.IsSlotBeingStolen(plot, slot) or carrying[thief] then
		return
	end
	local entry = ownerData.Meteors[tostring(slot)]
	if not entry then
		return
	end
	local thiefPlot = Services.PlotService.GetPlot(thief)
	if not thiefPlot then
		Services.EconomyService.Notify(thief, "Du hast keine Base auf diesem Server.", "Error")
		return
	end
	if not Services.PlotService.FreeSlot(thief) then
		Services.EconomyService.Notify(thief, "📦 Deine Base ist voll! Verkaufe erst etwas.", "Error")
		return
	end
	local character = thief.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local object = plot.MeteorParts[slot]
	local objectPos = Services.PlotService.ObjectPosition(object)
	if not root or not humanoid or humanoid.Health <= 0 or not objectPos then
		return
	end
	if root.Anchored then
		-- eingefroren (Falle / Admin): erst auftauen, dann klauen
		Services.EconomyService.Notify(thief, "🧊 Du bist eingefroren!", "Error")
		return
	end
	if (root.Position - objectPos).Magnitude > Services.PlotService.ObjectRadius(object) + 16 then
		return -- zu weit weg
	end
	if not Services.PlotService.IsInside(plot, root.Position) then
		return -- klauen nur, wer IN der fremden Base steht (nicht durch die Wand aus der Nachbar-Base)
	end
	if CarryService.MoveStatus(thief) ~= "ok" then
		Services.EconomyService.Notify(thief, "⏳ Kurz warten und nochmal versuchen!", "Error")
		return
	end
	local minTime = minCarryDistance(plot, thiefPlot, root.Position) / (maxCarrySpeed(thief) * MIN_CARRY_SPEED_FACTOR)

	stealing[plot] = stealing[plot] or {}
	stealing[plot][slot] = thief
	Services.PlotService.RenderSlot(plot, slot) -- macht das Objekt in der Base unsichtbar
	CarryService.StartCarry(thief, entry, {
		Source = "Plot",
		VictimPlot = plot,
		VictimPlayer = owner,
		Slot = slot,
		EntryRef = entry,
		MinTime = minTime,
	})
	Services.EconomyService.MarkDirty(owner)
	Services.EconomyService.Notify(
		owner,
		"🚨 " .. thief.DisplayName .. " klaut dein " .. Config.EntryName(entry) .. "! HAU IHN! 🔨",
		"Alarm"
	)
	Services.EconomyService.Effect(owner, "Alarm", 1)
end

-- Alle laufenden Diebstähle aus einer Base abbrechen (Rebirth, Reset, Verlassen)
function CarryService.CancelStealsFromPlot(plot, reason: string?)
	for thief, info in pairs(carrying) do
		if info.Source == "Plot" and info.VictimPlot == plot then
			CarryService.Fail(thief, reason or "cancelled")
		end
	end
end

-- -------------------------------------------------------------------
-- SCHLÄGER (wie in Steal-Spielen): jeder hat automatisch den besten Schläger, den sein Index freischaltet
-- (Config.Bats). Super-Bonk-Gadget = Boost (mehr Reichweite + Wucht, schneller), kein eigenes Werkzeug.
-- Der Klick kommt vom Client – Reichweite, Abklingzeit, Blickrichtung, Umhang und Gott-Modus prüft der Server.
-- -------------------------------------------------------------------
local BAT_ATTRIBUTE = "Bat" -- Werkzeug-Attribut: Id des Schlägers (Config.Bats)
local HIT_SOUND = "rbxasset://sounds/action_jump_land.mp3" -- hoch abgespielt = dumpfes "Bonk"
local KNOCKBACK_TIME = 0.22 -- so lange schiebt der Rückstoß
local STUN_IMMUNE_EXTRA = 0.4 -- nach dem Taumeln kurz kein neuer Rückstoß (kein Dauer-Wegschlagen)
local FACING_DOT = 0.1 -- Ziel muss grob vor dem Schläger stehen

local batTemplates: { [string]: Tool } = {}
local batTier: { [Player]: string } = {} -- zuletzt gegebener Schläger (für die Freischalt-Meldung)
local stunnedUntil: { [Player]: number } = {}

local function batIndex(id: string?): number
	for i, bat in ipairs(Config.Bats) do
		if bat.Id == id then
			return i
		end
	end
	return 0
end

-- Bester erlaubter Schläger und ob der Spielstand schon geladen ist
local function allowedBat(player: Player): (any, boolean)
	local data = Services.DataService.Get(player)
	if not data then
		return Config.Bats[1], false
	end
	local bat = Config.BestBat(Services.EconomyService.IndexCount(data))
	return bat, true
end

-- Reichweite, Wucht, Abklingzeit – mit Super-Bonk-Boost
local function batStats(player: Player, bat): (number, number, number)
	local range, force, cooldown = bat.Range, bat.Force, bat.Cooldown
	if ownsGadget(player, "SuperBonk") then
		range *= Config.SuperBonkRangeMult
		force *= Config.SuperBonkForceMult
		cooldown *= Config.SuperBonkCooldownMult
	end
	return range, force, cooldown
end

local function playHitSound(root: BasePart)
	local sound = Instance.new("Sound")
	sound.Name = "BonkHit"
	sound.SoundId = HIT_SOUND
	sound.Volume = 1
	sound.PlaybackSpeed = 1.5
	sound.RollOffMaxDistance = 120
	sound.Parent = root
	sound:Play()
	Debris:AddItem(sound, 2)
end

-- Ziel fliegt weg (läuft beim Getroffenen, weil er seine Physik besitzt) und taumelt kurz (Client).
-- Getötet wird niemand: nur Schub + kurzes Umfallen (PlatformStand beim Client).
local function knockback(target: Player, targetRoot: BasePart, direction: Vector3, force: number, super: boolean)
	local now = os.clock()
	if now < (stunnedUntil[target] or 0) or targetRoot.Anchored then
		return -- taumelt noch / eingefroren -> kein neuer Rückstoß
	end
	stunnedUntil[target] = now + Config.BonkStunTime + STUN_IMMUNE_EXTRA
	allowKnockback(target, force * 0.8 + 20) -- (fliegt nach dem Schub noch etwas weiter)
	local attachment = Instance.new("Attachment")
	attachment.Name = "BonkAttachment"
	attachment.Parent = targetRoot
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "BonkVelocity"
	velocity.Attachment0 = attachment
	velocity.MaxForce = 1e6
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VectorVelocity = direction * force + Vector3.new(0, Config.BonkLift + (super and 10 or 0), 0)
	velocity.Parent = targetRoot
	Debris:AddItem(velocity, KNOCKBACK_TIME)
	Debris:AddItem(attachment, KNOCKBACK_TIME)
	Services.EconomyService.Effect(target, "Bonked", 1, { Dir = direction, Time = Config.BonkStunTime })
end

-- Wilde Kreatur im Nester-Feld trifft (FieldService): Schubs wie ein Bonk (niemand stirbt),
-- getragene Beute geht verloren. true = getroffen (false: taumelt noch, eingefroren, Gott-Modus ...)
function CarryService.CreatureHit(player: Player, direction: Vector3, force: number): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 or root.Anchored then
		return false
	end
	if player:GetAttribute("AdminGod") == true or os.clock() < (stunnedUntil[player] or 0) then
		return false
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else root.CFrame.LookVector * -1
	playHitSound(root)
	knockback(player, root, flat, force, false)
	Services.EconomyService.Effect(player, "Shake", 0.6)
	if carrying[player] then
		CarryService.Fail(player, "creature")
	end
	return true
end

local function swing(player: Player, tool: Tool)
	local bat = Config.BatsById[tool:GetAttribute(BAT_ATTRIBUTE)]
	if not bat then
		return
	end
	-- nie besser als erlaubt (z.B. nach einem Reset mit altem Werkzeug in der Hand)
	local allowed = allowedBat(player)
	if batIndex(bat.Id) > batIndex(allowed.Id) then
		bat = allowed
	end
	local range, force, cooldown = batStats(player, bat)
	local t = os.clock()
	if t - (lastBonk[player] or 0) < cooldown then
		return
	end
	lastBonk[player] = t

	-- Schlag-Animation für alle über das Standard-Animate-Skript (der Besitzer schwingt zusätzlich lokal)
	local anim = Instance.new("StringValue")
	anim.Name = "toolanim"
	anim.Value = "Slash"
	anim.Parent = tool
	Debris:AddItem(anim, 1)

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 or tool.Parent ~= character or root.Anchored then
		return -- nur mit dem Schläger in der Hand, lebendig und nicht eingefroren
	end
	if CarryService.MoveStatus(player) == "flagged" then
		return -- gerade unmöglich schnell bewegt (Teleport-Exploit) -> Schlag zählt nicht
	end
	local gadgets = Services.GadgetService
	local best, bestDist = nil, range
	for _, other in ipairs(Players:GetPlayers()) do
		-- Unsichtbare (Umhang) kann man nicht treffen – wer Beute trägt, aber schon
		-- (Klauen beendet den Umhang sowieso, das hier ist nur das Sicherheitsnetz)
		local cloaked = gadgets ~= nil and gadgets.IsCloaked(other) and not carrying[other]
		local god = other:GetAttribute("AdminGod") == true -- Admin-Gott-Modus
		if other ~= player and not cloaked and not god then
			local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local otherHum = other.Character and other.Character:FindFirstChildOfClass("Humanoid")
			if otherRoot and otherHum and otherHum.Health > 0 then
				local offset = otherRoot.Position - root.Position
				local dist = offset.Magnitude
				local facing = dist < 3 or root.CFrame.LookVector:Dot(offset.Unit) > FACING_DOT
				if dist <= bestDist and facing then
					best, bestDist = other, dist
				end
			end
		end
	end
	if not best then
		return
	end
	local targetRoot = best.Character and best.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not targetRoot then
		return
	end
	local direction = targetRoot.Position - root.Position
	direction = Vector3.new(direction.X, 0, direction.Z)
	direction = direction.Magnitude > 0.01 and direction.Unit or root.CFrame.LookVector
	local super = ownsGadget(player, "SuperBonk")

	playHitSound(targetRoot)
	knockback(best, targetRoot, direction, force, super)
	Services.EconomyService.Effect(best, "Shake", super and 1 or 0.7)
	Services.EconomyService.Effect(player, "Shake", 0.25)
	if carrying[best] then
		CarryService.Fail(best, "bonked")
		trackReward(player, "Bonk", 1)
		Services.EconomyService.Notify(player, "Treffer! " .. best.DisplayName .. " hat die Beute verloren!", "Success")
	end
end

local function batPart(tool: Tool, name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = tool
	return p
end

-- Blockiger Baseballschläger aus wenigen Teilen, alles entlang +Y des Griffs (Handle):
-- Knauf unten, Griff (Handle), Hals, dicker Schlagteil, Kappe. Hohe Stufen: Leucht-Ringe, König: Krone.
local function createBatTool(bat): Tool
	local tool = Instance.new("Tool")
	tool.Name = bat.Name
	tool.ToolTip = "Klick = Schlagen! Diebe verlieren ihre Beute."
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.Grip = BAT_REST_GRIP
	tool:SetAttribute(BAT_ATTRIBUTE, bat.Id)

	local color: Color3 = bat.Color
	local material: Enum.Material = bat.Material or Enum.Material.SmoothPlastic
	local gripColor: Color3 = bat.Grip or Color3.fromRGB(50, 40, 35)
	local handle = batPart(tool, "Handle", Vector3.new(0.4, 1.8, 0.4), gripColor, Enum.Material.SmoothPlastic)
	local function attach(name: string, size: Vector3, y: number, partColor: Color3, partMaterial: Enum.Material): Part
		local p = batPart(tool, name, size, partColor, partMaterial)
		p.CFrame = handle.CFrame * CFrame.new(0, y, 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = p
		weld.Parent = p
		return p
	end
	attach("Knob", Vector3.new(0.6, 0.25, 0.6), -1.02, gripColor, Enum.Material.SmoothPlastic)
	attach("Neck", Vector3.new(0.55, 0.8, 0.55), 1.3, color, material)
	attach("Barrel", Vector3.new(0.85, 2.4, 0.85), 2.9, color, material)
	attach("Cap", Vector3.new(0.95, 0.22, 0.95), 4.2, color:Lerp(Color3.new(0, 0, 0), 0.25), material)
	local accent: Color3? = bat.Accent
	if accent then
		attach("Ring", Vector3.new(0.95, 0.22, 0.95), 2.1, accent, Enum.Material.Neon)
		attach("Ring", Vector3.new(0.95, 0.22, 0.95), 3.7, accent, Enum.Material.Neon)
	end
	if bat.Crown and accent then
		for _, offset in ipairs({
			Vector3.new(0.3, 0, 0.3),
			Vector3.new(-0.3, 0, 0.3),
			Vector3.new(0.3, 0, -0.3),
			Vector3.new(-0.3, 0, -0.3),
		}) do
			local spike = attach("Crown", Vector3.new(0.25, 0.45, 0.25), 4.5, accent, Enum.Material.Neon)
			spike.CFrame = handle.CFrame * CFrame.new(offset.X, 4.5, offset.Z)
		end
	end
	return tool
end

-- Gibt den besten erlaubten Schläger – ohne Doppelte; ein schlechterer fliegt raus (war er in der
-- Hand, kommt der neue gleich in die Hand). Beim Spawnen, bei neuem Index, nach dem Laden.
function CarryService.GiveBat(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	local character = player.Character
	local bat, loaded = allowedBat(player)
	local template = batTemplates[bat.Id]
	if not template then
		return
	end
	-- Freischalt-Meldung (nur wenn der Spielstand geladen ist und es wirklich besser wurde)
	if loaded then
		local known = batTier[player]
		if known and batIndex(bat.Id) > batIndex(known) then
			Services.EconomyService.Notify(
				player,
				"Neuer Schläger: " .. bat.Name .. "! Mehr Reichweite und Wucht.",
				"Success"
			)
			Services.EconomyService.Effect(player, "Confetti", 2)
		end
		batTier[player] = bat.Id
	end
	local have = false
	local wasEquipped = false
	for _, container in ipairs({ backpack, character }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and child:GetAttribute(BAT_ATTRIBUTE) ~= nil then
					if child:GetAttribute(BAT_ATTRIBUTE) == bat.Id and not have then
						have = true
					else
						wasEquipped = wasEquipped or child.Parent == character
						child:Destroy()
					end
				end
			end
		end
	end
	if have then
		return
	end
	local tool = template:Clone()
	tool.Activated:Connect(function()
		swing(player, tool)
	end)
	tool.Parent = backpack
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if wasEquipped and humanoid and humanoid.Health > 0 then
		humanoid:EquipTool(tool)
	end
end

-- Index hat sich geändert -> passt der Schläger noch? (EconomyService.Discover)
function CarryService.CheckBat(player: Player)
	if player.Parent then
		CarryService.GiveBat(player)
	end
end

local function giveTool(player: Player)
	if player:WaitForChild("Backpack", 10) then
		CarryService.GiveBat(player)
	end
end

function CarryService.Init(services)
	Services = services
	for _, bat in ipairs(Config.Bats) do
		batTemplates[bat.Id] = createBatTool(bat)
	end
end

function CarryService.Start()
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			-- neuer Charakter -> alte Beute ist weg (fliegt zurück bzw. das Ei fällt herunter)
			if carrying[player] then
				CarryService.Fail(player, "died")
			end
			CarryService.NoteTeleport(player) -- neuer Charakter steht woanders
			local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
			if humanoid then
				humanoid.Died:Connect(function()
					CarryService.Fail(player, "died")
				end)
			end
			giveTool(player)
			Services.EconomyService.ApplySpeed(player)
		end)
		if player.Character then
			task.spawn(giveTool, player)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayer, player)
	end

	-- Beim Verlassen (vor dem Speichern): Diebstähle sauber beenden (Beute geht zurück).
	-- Kann zweimal aufgerufen werden (PlayerRemoving + Speichern) – ist harmlos.
	local function onLeaving(player: Player)
		lastBonk[player] = nil
		batTier[player] = nil
		stunnedUntil[player] = nil
		moveTrack[player] = nil
		stealLimiter.Clear(player)
		if carrying[player] then
			CarryService.Fail(player, "left")
		end
	end
	Services.DataService.OnProfileReleasing(onLeaving)
	Players.PlayerRemoving:Connect(onLeaving)

	-- Prüfen: angekommen? gestorben? zu langsam? teleportiert?
	task.spawn(function()
		while true do
			task.wait(0.15)
			-- Bewegung ALLER Spieler messen (Anti-Teleport fürs Tragen, Kaufen und Klauen)
			for _, player in ipairs(Players:GetPlayers()) do
				if CarryService.MoveStatus(player) == "flagged" and carrying[player] then
					CarryService.Fail(player, "teleport")
				end
			end
			for player, info in pairs(carrying) do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local plot = Services.PlotService.GetPlot(player)
				local elapsed = os.clock() - info.Started
				if root and character == info.Character then
					info.LastPos = root.Position -- falls das Ei gleich herunterfällt (Tod, Verlassen)
				end
				if not root or not humanoid or humanoid.Health <= 0 or not info.Visual or not info.Visual.Parent then
					-- (Visual weg = Charakter neu gespawnt oder Beute zerstört)
					CarryService.Fail(player, "died")
				elseif elapsed > (info.Timeout or Config.CarryTimeout) then
					CarryService.Fail(player, "timeout")
				elseif plot and Services.PlotService.IsInside(plot, root.Position) then
					local admin = Services.AdminService
					if elapsed < (info.MinTime or 0) and not (admin and admin.IsAdmin(player)) then
						-- schneller als der kürzeste mögliche Weg -> Teleport oder durch die Wand
						CarryService.Fail(player, "teleport")
					else
						succeed(player)
					end
				end
			end
		end
	end)
end

return CarryService
