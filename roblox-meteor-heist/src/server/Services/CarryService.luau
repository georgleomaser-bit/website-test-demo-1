-- Klauen & Tragen:
--  * Fremde Meteore UND Aliens kann man klauen (E halten), wenn die Base nicht gesperrt ist,
--    und muss sie dann in die eigene Base tragen (Source = "Plot").
--    Wer gebonkt wird, stirbt, in eine Falle tritt, zu langsam ist oder das Spiel verlässt,
--    verliert die Beute: sie fliegt zurück zum Besitzer.
--  * Eier aus der ALIEN-PARADE (E = Klauen) und Eier am Boden (fallen gelassen / Egg Rush) sind gratis,
--    müssen aber auch nach Hause getragen werden (Source = "Ground"). Klappt das nicht,
--    fällt das Ei an Ort und Stelle auf den Boden – und JEDER kann es schnappen.
--  * Gekaufte Meteore (F) muss man NICHT tragen – sie fliegen automatisch in die Base.
--  * Bonk-Schläger (bzw. Super-Bonk-Gadget) zum Verteidigen.
--  * Seltene Beute ist schwer (Config.HeavyCarry, Tempo rechnet EconomyService), wer klaut, verliert
--    den Umhang (sonst wäre jeder Diebstahl unbonkbar), Eingefrorene können nicht klauen.

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
local SUPER_BONK_NAME = "Super-Bonk" -- Werkzeug-Name im Rucksack (normaler Schläger: "Bonk")
-- Lange Heimwege (info.ScaleTimeout, z.B. das Ei vom Meteor-Run): Trage-Zeit = Weg / Trage-Tempo * TRIP_SLACK
-- + TRIP_EXTRA, mindestens Config.CarryTimeout. Der Weg wird großzügig gerechnet (|dx| + |dz| bis zum
-- Eingang der eigenen Base – Umwege um Basen und Parade sind darin enthalten).
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
-- (Gamepass "Volle Speed beim Tragen" = kein Abzug), Speed Coil obendrauf, plus Laufband-Schub
local function maxCarrySpeed(player: Player): number
	local factor = Services.MonetizationService.HasPass(player, "CarryFast") and 1 or Config.CarrySpeedFactor
	local speed = math.max(8, Services.EconomyService.GetSpeed(player) * factor)
	if ownsGadget(player, "SpeedCoil") then
		speed *= 1 + Config.SpeedCoilBonus
	end
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
	local budget = math.min(cap, track.Budget + rate * math.max(0, now - track.Time)) - distance
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

-- Mindest-Tragezeit für ein Ei aus der Parade/vom Boden: Luftlinie bis zum Eingang der eigenen Base
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
-- info (Ground): { Source = "Ground", From = "Parade"|"Drop"|"Run"?, GrabPosition?, MinTime?, ScaleTimeout? }
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

-- Ei aus der Parade/vom Boden sicher zu Hause -> in einen freien Slot, Schlüpf-Countdown startet
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

-- Hinweise beim Verlieren: Beute aus einer Base fliegt zurück, ein Ei aus der Parade fällt herunter
local PLOT_FAIL_TEXT = {
	bonked = "💥 Gebonkt! Die Beute fliegt zurück.",
	timeout = "⏰ Zu langsam! Die Beute fliegt zurück.",
	full = "📦 Deine Base ist voll – die Beute fliegt zurück!",
	teleport = "🚫 Mit Beute kann man nicht teleportieren!",
	locked = "🔒 Die Base wurde gesperrt – deine Beute fliegt zurück!",
	trap = "🪤 FALLE! Die Beute fliegt zurück.",
}
local GROUND_FAIL_TEXT = {
	bonked = "💥 Gebonkt! Das Ei ist runtergefallen – schnapp es dir zurück!",
	timeout = "⏰ Zu langsam! Das Ei ist runtergefallen.",
	full = "📦 Deine Base ist voll – das Ei liegt jetzt am Boden!",
	teleport = "🚫 Mit Beute kann man nicht teleportieren!",
	locked = "🔒 Gesperrte Base – das Ei ist runtergefallen!",
	trap = "🪤 FALLE! Das Ei ist runtergefallen.",
	died = "💀 Das Ei ist runtergefallen – jemand anderes kann es jetzt schnappen!",
}

-- Ei aus der Parade/vom Boden verloren -> fällt als GRATIS-Ei auf den Boden (jeder darf es schnappen)
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
		"🚨 " .. thief.DisplayName .. " klaut dein " .. Config.EntryName(entry) .. "! BONK IHN!",
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
-- BONK-SCHLÄGER (normal bzw. Super-Bonk-Gadget: doppelte Reichweite + Wucht, schneller)
-- -------------------------------------------------------------------
local function bonk(player: Player, tool: Tool, super: boolean)
	local t = os.clock()
	local cooldown = super and Config.SuperBonkCooldown or Config.BonkCooldown
	if t - (lastBonk[player] or 0) < cooldown then
		return
	end
	lastBonk[player] = t

	-- Schlag-Animation über das Standard-Animate-Skript
	local anim = Instance.new("StringValue")
	anim.Name = "toolanim"
	anim.Value = "Slash"
	anim.Parent = tool
	Debris:AddItem(anim, 1)

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or tool.Parent ~= character then
		return -- nur mit dem Schläger in der Hand
	end
	local range = super and Config.BonkRange * Config.SuperBonkRangeMult or Config.BonkRange
	local force = super and Config.BonkForce * Config.SuperBonkForceMult or Config.BonkForce
	local gadgets = Services.GadgetService
	local best, bestDist = nil, range
	for _, other in ipairs(Players:GetPlayers()) do
		-- Unsichtbare (Umhang) kann man nicht bonken – wer Beute trägt, aber schon
		-- (Klauen beendet den Umhang sowieso, das hier ist nur das Sicherheitsnetz)
		local cloaked = gadgets ~= nil and gadgets.IsCloaked(other) and not carrying[other]
		if other ~= player and not cloaked then
			local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local otherHum = other.Character and other.Character:FindFirstChildOfClass("Humanoid")
			if otherRoot and otherHum and otherHum.Health > 0 then
				local offset = otherRoot.Position - root.Position
				local dist = offset.Magnitude
				local facing = dist < 3 or root.CFrame.LookVector:Dot(offset.Unit) > 0.1
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

	-- Rückstoß (läuft beim getroffenen Spieler, weil der seine Physik besitzt)
	if not targetRoot.Anchored then
		local attachment = Instance.new("Attachment")
		attachment.Parent = targetRoot
		local velocity = Instance.new("LinearVelocity")
		velocity.Attachment0 = attachment
		velocity.MaxForce = 1e6
		velocity.RelativeTo = Enum.ActuatorRelativeTo.World
		velocity.VectorVelocity = direction * force + Vector3.new(0, super and 45 or 30, 0)
		velocity.Parent = targetRoot
		Debris:AddItem(velocity, 0.18)
		Debris:AddItem(attachment, 0.18)
	end

	Services.EconomyService.Effect(best, "Shake", super and 1 or 0.6)
	if carrying[best] then
		CarryService.Fail(best, "bonked")
		trackReward(player, "Bonk", 1)
		Services.EconomyService.Notify(
			player,
			"💥 Treffer! " .. best.DisplayName .. " hat die Beute verloren!",
			"Success"
		)
	end
end

local function createBonkTool(super: boolean): Tool
	local tool = Instance.new("Tool")
	tool.Name = super and SUPER_BONK_NAME or "Bonk"
	tool.ToolTip = super and "Klick = SUPER-BONK! Doppelte Reichweite und Wucht."
		or "Klick = Bonk! Diebe verlieren ihre Beute."
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	local length = super and 5.2 or 4.2
	tool.Grip = CFrame.new(0, 0, -length * 0.38) * CFrame.Angles(math.rad(-90), 0, 0)
	tool:SetAttribute("Gadget", super and "SuperBonk" or nil)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.6, 0.6, length)
	handle.Color = super and Color3.fromRGB(60, 60, 70) or Color3.fromRGB(255, 170, 60)
	handle.Material = super and Enum.Material.Metal or Enum.Material.SmoothPlastic
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	local head = Instance.new("Part")
	head.Name = "Head"
	head.CanCollide = false
	head.Massless = true
	if super then
		-- großer goldener Hammerkopf mit Leuchtring
		head.Size = Vector3.new(2.4, 2.4, 3.4)
		head.Color = Color3.fromRGB(255, 200, 40)
		head.Material = Enum.Material.Foil
		head.CFrame = handle.CFrame * CFrame.new(0, 0, -length / 2 - 0.4) * CFrame.Angles(0, math.rad(90), 0)
		local glow = Instance.new("Part")
		glow.Name = "Glow"
		glow.Shape = Enum.PartType.Cylinder
		glow.Size = Vector3.new(0.5, 2.8, 2.8)
		glow.Color = Color3.fromRGB(255, 90, 40)
		glow.Material = Enum.Material.Neon
		glow.CanCollide = false
		glow.Massless = true
		glow.CFrame = head.CFrame
		local glowWeld = Instance.new("WeldConstraint")
		glowWeld.Part0 = head
		glowWeld.Part1 = glow
		glowWeld.Parent = glow
		glow.Parent = tool
	else
		head.Shape = Enum.PartType.Ball
		head.Size = Vector3.new(1.6, 1.6, 1.6)
		head.Color = Color3.fromRGB(255, 90, 60)
		head.Material = Enum.Material.SmoothPlastic
		head.CFrame = handle.CFrame * CFrame.new(0, 0, -2.2)
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = head
	weld.Parent = head
	head.Parent = tool
	return tool
end

local bonkTemplate: Tool
local superBonkTemplate: Tool

local function findTool(container: Instance?, name: string): Tool?
	local found = container and container:FindFirstChild(name)
	if found and found:IsA("Tool") then
		return found
	end
	return nil
end

-- Gibt den passenden Schläger (Bonk oder Super-Bonk) – ohne Doppelte, alter Schläger fliegt raus.
-- Wird beim Spawnen und nach dem Kauf/Geschenk des Super-Bonks aufgerufen.
function CarryService.GiveBonk(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack or not bonkTemplate then
		return
	end
	local character = player.Character
	local super = ownsGadget(player, "SuperBonk")
	local wanted = super and SUPER_BONK_NAME or "Bonk"
	local unwanted = super and "Bonk" or SUPER_BONK_NAME
	for _, container in ipairs({ backpack, character }) do
		local old = findTool(container, unwanted)
		if old then
			old:Destroy()
		end
	end
	if findTool(backpack, wanted) or findTool(character, wanted) then
		return
	end
	local tool = (super and superBonkTemplate or bonkTemplate):Clone()
	tool.Activated:Connect(function()
		bonk(player, tool, super)
	end)
	tool.Parent = backpack
end

local function giveTool(player: Player)
	if player:WaitForChild("Backpack", 10) then
		CarryService.GiveBonk(player)
	end
end

function CarryService.Init(services)
	Services = services
	bonkTemplate = createBonkTool(false)
	superBonkTemplate = createBonkTool(true)
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
