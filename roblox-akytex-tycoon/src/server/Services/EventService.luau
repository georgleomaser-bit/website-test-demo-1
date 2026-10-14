-- =====================================================================
--  AKYTEX TYCOON – Welt-Events, Live-Ops-Kalender, Admin-Abuse-Shows (Server/Services/EventService)
--  Besitzer: WP11 (Admin, Events, Anti-Cheat). Vertrag: DESIGN.md §C5.10, §B10 (Welt-Events :10, Glocken-Moment,
--  Sky-Show, Bär/Bulle, Bullen-Parade, Feuerwerk, Geldregen, Samstags-Show + Automatik), §B15.3 (Nicht-Markt-Teil des
--  Admin-Abuse-Katalogs), §C8 (Remote "World"), §C9 (EventPickup), §C10 (State "Event"), §C11.2 (Pickup-Fälschung).
--
--  Ablauf (Scheduler "EventTick" 1 Hz, "EventRain" 4 Hz nur bei aktivem Geldregen):
--    * jeder Börsentag :10 -> Welt-Event Rotation[(Börsentag % #Rotation) + 1] (Clock, auf allen Servern gleich):
--      Geldtransporter (Bündel entlang des Rings, je 20 s Dauer-Einkommen) · Drohnen-Lieferung (8 Pakete an
--      deterministischen Punkten, Hash aus dem Start-Tick, je 60 s) · Bau-Boom (−25 %, TowerService.SetCostEvent) ·
--      Pressekonferenz (Quartalszahlen von :03 des nächsten Börsentags + 3-Fragen-Quiz über Antwort-Felder)
--    * Börsentag % 3 == 0: Glocken-Moment :00–:01 (≥ 3 Spieler in der Zone -> TowerService.SetServerBoost("Bell", ×1,2,
--      300 s)) und Sky-Show :15 nachts (Respekt zählt 10 min doppelt – CommunityService liest Active())
--    * Crash-News -> „Beruhige den Bären“ (Vertrauens-Kugeln je Spieler, Ziel 25 × Spieler, Erfolg = 10 min Einkommen)
--      Rally-News -> goldener Bulle auf dem Ring (Berühren = Bullen-Bonus ×1,5 für 5 min, 1× je Rally)
--    * Wochen-Kalender (Config.Events.Weekly, Berlin-Zeit): Power-Hour-Anzeige, Erinnerungen an den Besitzer,
--      automatische Samstags-Show 18:15 (nur wenn MarketService.AutoShowCancelled(Woche) == false), Bilanz-Sonntag
--  Pickups werden PRO SPIELER instanziert: Server vergibt Token {Id, Kind, Pos, Until} (Remote World "Pickups" nur an
--  den Eigentümer), Einsammeln über Request "EventPickup" {Id} (Token gehört dem Spieler, Fenster gültig, Abstand ≤ 12,
--  max. 1 je Id). Kein Event löscht oder berührt Käufe; Belohnungen nur CR (ShopService.Credit) / Turm-Boost / XP.
--
--  Öffentliche API (§C5.10):
--    EventService.Active(): { Types.EventState }       EventService.EventMult(): number   (Golden Hour, ≤ 3)
--    EventService.IsAdminAbuse(): boolean               EventService.BearActive(): boolean
--    EventService.Start(kind, args, "Local" | "Global", by?): (boolean, string)
--      (ohne Argumente = Lebenszyklus-Start durch den Loader, genau einmal – Vertrag und Loader nutzen denselben Namen)
--    EventService.StartParade(buyer, seconds)           EventService.StartFireworks(buyer)
--  Ergänzungen (WP11-intern, abwärtskompatibel):
--    EventService.Clamp(kind, args): ({ [string]: any }?, string?)   Parameter klemmen (AdminService, AdminTests)
--    EventService.ApplyGlobal(msg): boolean                           globale Admin-Abuse-Nachricht ausführen (geprüft)
--    EventService.Stop(kind): number                                  laufende Events einer Art beenden (lokal)
--    EventService.Kinds(): { string }                                 startbare Arten (Admin-Panel)
--    EventService.Stats(): { [string]: number }                       Zähler für Dashboard/F8
--  Request-Handler: EventPickup. State: Event. Effekte: MoneyRain, BullParade, Bear, GoldenBull, SkyShow, Fireworks,
--  BossAppear, AbuseBanner, BellMoment (+ Kern-Effekte CoinFly/Confetti von WP2).
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Types = require(Shared:WaitForChild("Types"))
local Clock = require(Shared:WaitForChild("Clock"))
local Lang = require(Shared:WaitForChild("Lang"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local EventService = {}
local Services: any = nil

type Plain = { [string]: any }
type EventState = Types.EventState

type Ev = {
	Key: string,
	Kind: string,
	Started: number,
	Until: number,
	Scope: "Local" | "Global",
	Data: Plain,
	Admin: boolean,
	Run: Plain, -- nur Server (nie gesendet)
}

type Token = {
	Id: number,
	Kind: string,
	Pos: Vector3,
	Until: number,
	From: number,
	SendAt: number,
	Event: string,
	Reward: string, -- "Income" | "Orb" | "Quiz"
	Seconds: number,
	Source: string,
	Q: number,
	O: number,
	Sent: boolean,
}

type Route = { Points: { Vector3 }, Cum: { number }, Length: number }

local EV: any = Config.Events
local SEASON: any = Config.Season

local DAY = Clock.DAY_TICKS
local MAX_EVENTS = 24
local MAX_ACTIVE_STATE = 12
local MAX_CATCHUP_TICKS = 5
local MAX_PENDING = 16
local BEAR_BROADCAST_GAP = 0.5
local PICKUP_SLACK = 0.75 -- Sekunden Toleranz beim Fenster-Anfang (Laufzeit des Pakets)
local RANGE_SLACK = 1.5 -- Studs Toleranz für die Reichweite (Netz-Versatz der Wurzel)
local ERROR_LOG_GAP = 10
local SHOW_FOLDER = "AT_EventWorld"
local ROUTE_CACHE_MAX = 8

-- Startbare Arten: Welt-Events + Nicht-Markt-Katalog + Welt-Darsteller (Admin-Tab Welt/Debug lokal)
local WORLD_KINDS: { [string]: boolean } = { Truck = true, Drones = true, BuildBoom = true, Press = true }
local START_KINDS: { [string]: boolean } = {
	Truck = true,
	Drones = true,
	BuildBoom = true,
	Press = true,
	BellMoment = true,
	SkyShow = true,
	Bear = true,
	GoldenBull = true,
	MoneyRain = true,
	GoldenHour = true,
	XpRush = true,
	AdminBuildBoom = true,
	Lightshow = true,
	Fireworks = true,
	Confetti = true,
	BellShow = true,
	Boss = true,
	AllToHall = true,
	SaturdayShow = true,
	AutoShow = true,
	LeagueFinale = true,
}
-- Admin-Abuse (zählt für "ADMIN-ABUSE aktiv", sperrt Angebote)
local ADMIN_KINDS: { [string]: boolean } = {
	MoneyRain = true,
	GoldenHour = true,
	XpRush = true,
	AdminBuildBoom = true,
	Lightshow = true,
	Fireworks = true,
	Confetti = true,
	BellShow = true,
	Boss = true,
	AllToHall = true,
	SaturdayShow = true,
}

-- ---------------------------------------------------------------------
-- ZUSTAND (Pro-Spieler-Tabellen werden bei PlayerRemoving geleert)
-- ---------------------------------------------------------------------
local events: { [string]: Ev } = {}
local tokens: { [Player]: { [number]: Token } } = {}
local tokenCount: { [Player]: number } = {}
local issued: { [Player]: { [string]: boolean } } = {} -- Event-Schlüssel -> Pickups schon erzeugt
local collected: { [Player]: { [string]: number } } = {} -- Event-Schlüssel -> eingesammelte Pickups
local rewarded: { [Player]: { [string]: boolean } } = {} -- Event-Schlüssel -> Teilnahme-Belohnung schon gegeben
local quiz: { [Player]: { Event: string, Q: number, Correct: number, Done: boolean } } = {}
local bullTouched: { [Player]: string } = {}
local rainPlan: { [Player]: { Next: number, Left: number, Gap: number } } = {}
local bearPart: { [Player]: number } = {} -- Kugeln im aktuellen Bären
local pending: { { At: number, Kind: string, Args: Plain, Scope: "Local" | "Global", By: number?, Meta: Plain? } } = {}
local weeklyNext: { [string]: number } = {}

local nextTokenId = 1
local lastTick: number? = nil
local bellWindow: { Day: number, Until: number, Done: boolean }? = nil
local bear: { Key: string, Have: number, Goal: number, BroadcastAt: number, Sent: string }? = nil
local eventMultValue = 1
local eventMultUntil = 0
local stateSig = ""
local stats = { Started = 0, Pickups = 0, Rejected = 0, BearWins = 0 }
local routeCache: { [string]: Route } = {}
local routeCacheCount = 0
local errorAt: { [string]: number } = {}
local showFolder: Folder? = nil

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function logError(source: string, err: any)
	local now = os.clock()
	if now - (errorAt[source] or -math.huge) >= ERROR_LOG_GAP then
		errorAt[source] = now
		warn(("[EventService] %s: %s"):format(source, tostring(err)))
	end
end

local function service(name: string): any
	return if Services then Services[name] else nil
end

-- Services.<name>.<fn>(...) in pcall; fehlt der Dienst -> false
local function call(name: string, fnName: string, ...: any): (boolean, ...any)
	local svc = service(name)
	local fn = if type(svc) == "table" then svc[fnName] else nil
	if type(fn) ~= "function" then
		return false
	end
	local result = table.pack(pcall(fn, ...))
	if not result[1] then
		logError(name .. "." .. fnName, result[2])
	end
	return table.unpack(result, 1, result.n)
end

local function present(p: any): boolean
	return typeof(p) == "Instance" and p:IsA("Player") and p.Parent == Players
end

local function isNum(n: any): boolean
	return Util.IsFinite(n)
end

local function num(value: any, default: number): number
	return if Util.IsFinite(value) then value else default
end

local function now(): number
	return Clock.Now()
end

local function ready(p: Player): boolean
	local ok, result = call("PlayerStateService", "IsReady", p)
	return ok and result == true
end

local function notifyAll(key: string, args: { any }?, kind: Types.NotifyKind?)
	call("PlayerStateService", "NotifyAll", key, args, kind or "Event")
end

local function notify(p: Player, key: string, args: { any }?, kind: Types.NotifyKind?)
	call("PlayerStateService", "Notify", p, key, args, kind or "Event")
end

local function effectAll(name: string, strength: number, data: any?)
	call("PlayerStateService", "EffectAll", name, strength, data)
end

local function effect(p: Player, name: string, strength: number, data: any?)
	call("PlayerStateService", "Effect", p, name, strength, data)
end

local function markAll()
	for _, p in ipairs(Players:GetPlayers()) do
		call("PlayerStateService", "MarkDirty", p, "Event")
	end
end

local function rootOf(p: Player): BasePart?
	local character = p.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function isStudio(): boolean
	return RunService:IsStudio()
end

local function playerName(userId: number?): string
	if not isNum(userId) then
		return "?"
	end
	local p = Players:GetPlayerByUserId(userId :: number)
	if p then
		return string.sub(p.DisplayName, 1, 40)
	end
	return tostring(userId)
end

-- Dauer-Einkommen pro Sekunde (ohne Zeitlich) – Grundlage aller Event-Belohnungen
local function steadyIncome(p: Player): number
	local ok, info = call("TowerService", "Income", p)
	if ok and type(info) == "table" and isNum(info.Steady) and info.Steady > 0 then
		return info.Steady
	end
	return 0
end

local function creditIncome(p: Player, seconds: number, source: string): number
	local amount = math.floor(steadyIncome(p) * seconds)
	amount = math.max(amount, math.floor(num(EV.MinPickupCredits, 10)))
	amount = math.clamp(amount, 0, 1e14)
	if amount < 1 then
		return 0
	end
	local ok, credited = call("ShopService", "Credit", p, amount, source)
	if ok and credited == true then
		return amount
	end
	return 0
end

local function plazaCenter(): Vector3
	local zones = Config.City and Config.City.Zones
	local plaza = zones and zones.Plaza
	if plaza and typeof(plaza.Center) == "Vector3" then
		return plaza.Center
	end
	return Vector3.zero
end

local function anchor(name: string): CFrame?
	local ok, cf = call("CityService", "Anchor", name)
	if ok and typeof(cf) == "CFrame" then
		return cf
	end
	return nil
end

local function sectorOfWeek(): string
	local sectors = Config.Companies and Config.Companies.Sectors
	local week = Clock.WeekIndex(Clock.Tick())
	if type(sectors) == "table" and #sectors > 0 then
		local entry = sectors[(week % #sectors) + 1]
		if type(entry) == "table" and type(entry.Key) == "string" then
			return entry.Key
		end
	end
	return "T"
end

local function folder(): Folder
	local existing = showFolder
	if existing and existing.Parent then
		return existing
	end
	local created = workspace:FindFirstChild(SHOW_FOLDER)
	if not created or not created:IsA("Folder") then
		local f = Instance.new("Folder")
		f.Name = SHOW_FOLDER
		f.Parent = workspace
		created = f
	end
	showFolder = created :: Folder
	return created :: Folder
end

-- Boden unter einem Punkt (Kugeln/Münzen sollen nicht in Wänden oder in der Luft hängen)
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = false
groundParams.RespectCanCollide = true

local function groundAt(pos: Vector3, lift: number): Vector3
	local list: { Instance } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	table.insert(list, folder())
	groundParams.ExcludeInstances = list
	local result = workspace:Raycast(pos + Vector3.new(0, 80, 0), Vector3.new(0, -220, 0), groundParams)
	if result then
		return result.Position + Vector3.new(0, lift, 0)
	end
	return pos + Vector3.new(0, lift, 0)
end

-- ---------------------------------------------------------------------
-- ROUTEN (gleiche Punkte wie der Client: Config.City.RoutePoints)
-- ---------------------------------------------------------------------
local function routeOf(name: string): Route?
	local cached = routeCache[name]
	if cached then
		return cached
	end
	local points: any = nil
	local ok, result = call("CityService", "Route", name)
	if ok and type(result) == "table" and #result >= 2 then
		points = result
	else
		local city: any = Config.City
		if city and type(city.RoutePoints) == "function" then
			local okCfg, fromCfg = pcall(city.RoutePoints, name)
			if okCfg and type(fromCfg) == "table" and #fromCfg >= 2 then
				points = fromCfg
			end
		end
	end
	if type(points) ~= "table" then
		return nil
	end
	local cum: { number } = { 0 }
	local length = 0
	for i = 2, #points do
		length += (points[i] - points[i - 1]).Magnitude
		cum[i] = length
	end
	if length <= 0 then
		return nil
	end
	local route: Route = { Points = points, Cum = cum, Length = length }
	if routeCacheCount < ROUTE_CACHE_MAX then
		routeCache[name] = route
		routeCacheCount += 1
	end
	return route
end

-- Punkt bei Anteil f (0 … 1) der Route, plus Richtung
local function pointAt(route: Route, f: number): (Vector3, Vector3)
	local target = (f % 1) * route.Length
	local points, cum = route.Points, route.Cum
	local lo, hi = 1, #cum
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if cum[mid] <= target then
			lo = mid
		else
			hi = mid
		end
	end
	local a, b = points[lo], points[math.min(lo + 1, #points)]
	local seg = cum[math.min(lo + 1, #cum)] - cum[lo]
	local t = if seg > 0 then (target - cum[lo]) / seg else 0
	local dir = b - a
	return a:Lerp(b, t), if dir.Magnitude > 0.01 then dir.Unit else Vector3.new(1, 0, 0)
end

-- ---------------------------------------------------------------------
-- EVENT-VERWALTUNG
-- ---------------------------------------------------------------------
local function publicState(ev: Ev): EventState
	return {
		Kind = ev.Kind,
		Started = ev.Started,
		Until = ev.Until,
		Scope = ev.Scope,
		Data = ev.Data,
	}
end

local function countEvents(): number
	local n = 0
	for _ in pairs(events) do
		n += 1
	end
	return n
end

local function addEvent(
	key: string,
	kind: string,
	seconds: number,
	scope: "Local" | "Global",
	data: Plain,
	admin: boolean
): Ev?
	local t = now()
	local existing = events[key]
	if existing == nil and countEvents() >= MAX_EVENTS then
		logError("addEvent", "zu viele gleichzeitige Events – " .. kind .. " übersprungen")
		return nil
	end
	local ev: Ev = {
		Key = key,
		Kind = kind,
		Started = t,
		Until = t + math.max(1, seconds),
		Scope = scope,
		Data = data,
		Admin = admin,
		Run = {},
	}
	events[key] = ev
	stats.Started += 1
	Remotes.World:FireAllClients("Event", publicState(ev))
	markAll()
	return ev
end

local function endEvent(key: string)
	local ev = events[key]
	if not ev then
		return
	end
	events[key] = nil
	local t = now()
	local state = publicState(ev)
	state.Until = math.min(state.Until, t)
	Remotes.World:FireAllClients("Event", state)
	-- offene Pickups dieses Events verfallen (Clients räumen über Until/PickupGone selbst auf)
	for p, list in pairs(tokens) do
		local gone: { number } = {}
		for id, token in pairs(list) do
			if token.Event == key and token.Until <= t then
				table.insert(gone, id)
			end
		end
		for _, id in ipairs(gone) do
			list[id] = nil
			tokenCount[p] = math.max(0, (tokenCount[p] or 1) - 1)
			if present(p) then
				Remotes.World:FireClient(p, "PickupGone", { Id = id })
			end
		end
	end
	markAll()
end

-- ---------------------------------------------------------------------
-- PICKUP-TOKEN (pro Spieler)
-- ---------------------------------------------------------------------
local function addToken(
	p: Player,
	eventKey: string,
	kind: string,
	pos: Vector3,
	from: number,
	sendAt: number,
	untilT: number,
	reward: string,
	seconds: number,
	source: string,
	q: number?,
	o: number?
): Token?
	if not present(p) or not Util.IsFiniteVector(pos) then
		return nil
	end
	local maxTokens = math.floor(num(EV.PickupMaxPerPlayer, 60))
	local count = tokenCount[p] or 0
	if count >= maxTokens then
		return nil
	end
	local list = tokens[p]
	if not list then
		list = {}
		tokens[p] = list
	end
	local id = nextTokenId
	nextTokenId += 1
	if nextTokenId > 2 ^ 31 then
		nextTokenId = 1
	end
	local token: Token = {
		Id = id,
		Kind = kind,
		Pos = pos,
		Until = untilT,
		From = from,
		SendAt = sendAt,
		Event = eventKey,
		Reward = reward,
		Seconds = seconds,
		Source = source,
		Q = q or 0,
		O = o or 0,
		Sent = false,
	}
	list[id] = token
	tokenCount[p] = count + 1
	return token
end

local function removeToken(p: Player, id: number, tell: boolean)
	local list = tokens[p]
	if not list or not list[id] then
		return
	end
	list[id] = nil
	tokenCount[p] = math.max(0, (tokenCount[p] or 1) - 1)
	if tell and present(p) then
		Remotes.World:FireClient(p, "PickupGone", { Id = id })
	end
end

-- Fällige Token an ihre Eigentümer senden (ein Paket je Spieler und Takt)
local function flushTokens(t: number)
	for p, list in pairs(tokens) do
		if not present(p) then
			continue
		end
		local batch: { Plain } = {}
		local expired: { number } = {}
		for id, token in pairs(list) do
			if token.Until <= t then
				table.insert(expired, id)
			elseif not token.Sent and token.SendAt <= t then
				token.Sent = true
				table.insert(batch, { Id = token.Id, Kind = token.Kind, Pos = token.Pos, Until = token.Until })
			end
		end
		for _, id in ipairs(expired) do
			removeToken(p, id, false)
		end
		if #batch > 0 then
			Remotes.World:FireClient(p, "Pickups", batch)
		end
	end
end

local function participation(p: Player, eventKey: string)
	local per = collected[p]
	if not per then
		per = {}
		collected[p] = per
	end
	local first = (per[eventKey] or 0) == 0
	per[eventKey] = (per[eventKey] or 0) + 1
	if first then
		call("ProgressionService", "NoteStat", p, "WorldEvent", 1, nil)
	end
	return per[eventKey]
end

local function seasonXpOnce(p: Player, eventKey: string)
	local per = rewarded[p]
	if not per then
		per = {}
		rewarded[p] = per
	end
	if per[eventKey] then
		return
	end
	per[eventKey] = true
	local xp = num(SEASON and SEASON.XpSources and SEASON.XpSources.WorldEvent and SEASON.XpSources.WorldEvent.Xp, 0)
	if xp <= 0 then
		xp = num(EV.WorldSeasonXp, 50)
	end
	call("RewardService", "GrantSeasonXp", p, xp, "WorldEvent")
end

-- ---------------------------------------------------------------------
-- WELT-EVENTS (:10)
-- ---------------------------------------------------------------------
local function hashRandom(seed: number): Random
	return Random.new(seed % 2147483647)
end

-- Geldtransporter: Bündel entlang des Rings, erst sichtbar, wenn der Transporter vorbeifährt
local function issueTruck(p: Player, ev: Ev)
	local cfg = EV.Truck
	local route = routeOf(cfg.Route or "Ring")
	if not route then
		return
	end
	local count = math.clamp(math.floor(num(cfg.Bundles, 30)), 1, 60)
	local seconds = num(cfg.Seconds, 120)
	local rng = hashRandom(math.floor(ev.Started))
	local lateral = num(cfg.Lateral, 8)
	local untilT = ev.Until + num(cfg.Linger, 30)
	for i = 1, count do
		local f = (i - 0.5) / count
		local pos, dir = pointAt(route, f)
		local side = Vector3.new(-dir.Z, 0, dir.X)
		local offset = side * ((rng:NextNumber() * 2 - 1) * lateral)
		local at = ev.Started + f * seconds
		addToken(
			p,
			ev.Key,
			"Bundle",
			pos + offset + Vector3.new(0, 1.6, 0),
			at,
			at,
			untilT,
			"Income",
			num(cfg.IncomeSeconds, 20),
			"Pickup"
		)
	end
end

-- Drohnen: deterministische Punkte (Anker der Stadt + Plot-Vorplätze), Hash aus dem Start-Tick
local function droneSpots(seed: number, count: number): { Vector3 }
	local candidates: { Vector3 } = {}
	for _, name in ipairs({
		"Spawn",
		"BellZone",
		"TowerTour",
		"Showroom",
		"Boutique",
		"Marina",
		"Lookout",
		"PressScreen",
	}) do
		local cf = anchor(name)
		if cf then
			table.insert(candidates, cf.Position)
		end
	end
	local plots = math.floor(num(Config.Server and Config.Server.Plots, 10))
	for k = 1, plots do
		local ok, site = call("CityService", "PlotSite", k)
		if ok and typeof(site) == "CFrame" then
			local toPlaza = plazaCenter() - site.Position
			local flat = Vector3.new(toPlaza.X, 0, toPlaza.Z)
			if flat.Magnitude > 1 then
				table.insert(candidates, site.Position + flat.Unit * 46)
			end
		end
	end
	if #candidates == 0 then
		local c = plazaCenter()
		for k = 1, 8 do
			local a = k / 8 * math.pi * 2
			table.insert(candidates, c + Vector3.new(math.cos(a) * 60, 0, math.sin(a) * 60))
		end
	end
	local rng = hashRandom(seed)
	local spread = num(EV.Drones.Spread, 14)
	local out: { Vector3 } = {}
	for i = 1, count do
		local base = candidates[rng:NextInteger(1, #candidates)]
		local a = rng:NextNumber() * math.pi * 2
		local r = rng:NextNumber() * spread
		out[i] = base + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
	end
	return out
end

local function issueDrones(p: Player, ev: Ev)
	local cfg = EV.Drones
	local spots: { Vector3 } = ev.Run.Spots
	if type(spots) ~= "table" then
		return
	end
	local from = ev.Started + num(cfg.DropSeconds, 8)
	for _, pos in ipairs(spots) do
		addToken(p, ev.Key, "Package", pos, from, ev.Started, ev.Until, "Income", num(cfg.IncomeSeconds, 60), "Pickup")
	end
end

-- Pressekonferenz: Antwort-Felder vor dem Hologramm (eine Frage nach der anderen)
local function quizPads(): { Vector3 }
	local cf = anchor("PressScreen")
	local base: CFrame = cf or CFrame.new(plazaCenter() + Vector3.new(0, 0, 40))
	local spacing = num(EV.Press.PadSpacing, 7)
	local pads: { Vector3 } = {}
	for o = 1, 3 do
		local local_ = base * CFrame.new((o - 2) * spacing, 0, -6)
		pads[o] = local_.Position + Vector3.new(0, 1.2, 0)
	end
	return pads
end

local function issueQuestion(p: Player, ev: Ev, q: number)
	local pads: { Vector3 } = ev.Run.Pads
	if type(pads) ~= "table" then
		return
	end
	local t = now()
	local from = math.max(t, ev.Started + 4)
	for o = 1, 3 do
		addToken(p, ev.Key, ("Quiz:%d:%d"):format(q, o), pads[o], from, t, ev.Until, "Quiz", 0, "", q, o)
	end
end

local function issuePress(p: Player, ev: Ev)
	quiz[p] = { Event = ev.Key, Q = 1, Correct = 0, Done = false }
	issueQuestion(p, ev, 1)
end

-- Pickups für alle bereiten Spieler erzeugen, die für ein laufendes Event noch keine haben (auch späte Beitritte)
local ISSUERS: { [string]: (Player, Ev) -> () } = {
	Truck = issueTruck,
	Drones = issueDrones,
	Press = issuePress,
}

local function issueAll()
	for key, ev in pairs(events) do
		local issuer = ISSUERS[ev.Kind]
		if issuer and ev.Until > now() then
			for _, p in ipairs(Players:GetPlayers()) do
				local done = issued[p]
				if not done then
					done = {}
					issued[p] = done
				end
				if not done[key] and ready(p) then
					done[key] = true
					local ok, err = pcall(issuer, p, ev)
					if not ok then
						logError("issue " .. ev.Kind, err)
					end
				end
			end
		end
	end
end

local function startTruck(scope: "Local" | "Global"): Ev?
	local cfg = EV.Truck
	return addEvent(
		"Truck",
		"Truck",
		num(cfg.Seconds, 120),
		scope,
		{ Route = cfg.Route or "Ring", Count = math.floor(num(cfg.Bundles, 30)) },
		false
	)
end

local function startDrones(scope: "Local" | "Global"): Ev?
	local cfg = EV.Drones
	local count = math.clamp(math.floor(num(cfg.Packages, 8)), 1, 30)
	local seed = math.floor(Clock.Tick())
	local spots = droneSpots(seed, count)
	local ev =
		addEvent("Drones", "Drones", num(cfg.Seconds, 120), scope, { Spots = spots, Drop = cfg.DropSeconds }, false)
	if ev then
		ev.Run.Spots = spots
	end
	return ev
end

local function adminBoomActive(): boolean
	local ev = events.AdminBuildBoom
	return ev ~= nil and ev.Until > now()
end

local function startBuildBoom(scope: "Local" | "Global"): Ev?
	local cfg = EV.BuildBoom
	local seconds = num(cfg.Seconds, 300)
	local mult = math.clamp(1 - num(cfg.Pct, 0.25), 0.1, 1)
	local untilT = now() + seconds
	-- läuft schon ein Admin-Bau-Boom (−50 % Etagen), nur die Raum-Stufen verbilligen
	call("TowerService", "SetCostEvent", if adminBoomActive() then "RoomLevel" else "Both", mult, untilT)
	notifyAll("evt.buildBoomStart", { math.floor(num(cfg.Pct, 0.25) * 100 + 0.5) }, "Event")
	return addEvent("BuildBoom", "BuildBoom", seconds, scope, { Pct = num(cfg.Pct, 0.25) }, false)
end

local function pressItems(): { Plain }
	local out: { Plain } = {}
	local ok, items = call("MarketService", "Calendar", 2)
	if not ok or type(items) ~= "table" then
		return out
	end
	local tick = Clock.Tick()
	local nextStart = (Clock.DayIndex(tick) + 1) * DAY
	local maxItems = math.floor(num(EV.Press.MaxItems, 4))
	for _, item in ipairs(items) do
		if type(item) == "table" and item.Kind == "Earnings" and isNum(item.T) and isNum(item.I) then
			if item.T >= nextStart + 180 and item.T < nextStart + 240 and #out < maxItems then
				table.insert(out, { I = item.I, T = item.T })
			end
		end
	end
	return out
end

local function startPress(scope: "Local" | "Global"): Ev?
	local cfg = EV.Press
	local pool = cfg.Quiz
	local day = Clock.DayIndex(Clock.Tick())
	local count = math.clamp(math.floor(num(cfg.Questions, 3)), 1, #pool)
	local picked: { number } = {}
	local rng = hashRandom(day * 7919 + 13)
	local order: { number } = {}
	for i = 1, #pool do
		order[i] = i
	end
	for i = #order, 2, -1 do -- Fisher-Yates mit festem Seed (alle Server gleich)
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	for i = 1, count do
		table.insert(picked, pool[order[i]].Id)
	end
	local screen = anchor("PressScreen") or CFrame.new(plazaCenter() + Vector3.new(0, 0, 40))
	local ev = addEvent("Press", "Press", num(cfg.Seconds, 90), scope, {
		Items = pressItems(),
		Quiz = picked,
		Lead = cfg.LeadMinutes,
		Pos = screen.Position,
		Look = screen.LookVector,
	}, false)
	if ev then
		ev.Run.Pads = quizPads()
		ev.Run.Quiz = picked
	end
	return ev
end

local WORLD_STARTERS: { [string]: ("Local" | "Global") -> Ev? } = {
	Truck = startTruck,
	Drones = startDrones,
	BuildBoom = startBuildBoom,
	Press = startPress,
}

local function startWorld(kind: string, scope: "Local" | "Global"): Ev?
	local starter = WORLD_STARTERS[kind]
	if not starter then
		return nil
	end
	if events[kind] and events[kind].Until > now() then
		return nil -- läuft schon
	end
	local ev = starter(scope)
	if ev and kind ~= "BuildBoom" then
		notifyAll("evt.worldStart." .. kind, nil, "Event")
	end
	return ev
end

local function rotationKind(day: number): string?
	local rotation = EV.Rotation
	if type(rotation) ~= "table" or #rotation == 0 then
		return nil
	end
	return rotation[(day % #rotation) + 1]
end

-- ---------------------------------------------------------------------
-- GLOCKEN-MOMENT, SKY-SHOW
-- ---------------------------------------------------------------------
local function bellZone(): (Vector3, number)
	local cf = anchor("BellZone")
	local zones = Config.City and Config.City.Zones
	local plaza = zones and zones.Plaza
	local radius = num(plaza and plaza.BellZoneRadius, num(EV.BellMoment.ZoneRadius, 18))
	if cf then
		return cf.Position, radius
	end
	return plazaCenter(), radius
end

local function playersInBellZone(): number
	local center, radius = bellZone()
	local count = 0
	for _, p in ipairs(Players:GetPlayers()) do
		local root = rootOf(p)
		if root then
			local offset = root.Position - center
			if Vector2.new(offset.X, offset.Z).Magnitude <= radius + 2 and math.abs(offset.Y) < 40 then
				count += 1
			end
		end
	end
	return count
end

local function boostsPaused(): boolean
	return EV.BoostPause == true
end

local function triggerBellMoment(scope: "Local" | "Global", count: number): Ev?
	local cfg = EV.BellMoment
	local seconds = num(cfg.Seconds, 300)
	local mult = math.clamp(num(cfg.Mult, 1.2), 1, 1.5)
	if not boostsPaused() then
		call("TowerService", "SetServerBoost", "Bell", mult, seconds)
	end
	effectAll("BellMoment", 1, { Seconds = seconds, Count = count, Mult = mult })
	notifyAll("evt.bellMoment", { count, ("%.1f"):format(mult) }, "Success")
	return addEvent("BellMoment", "BellMoment", seconds, scope, { Mult = mult, Count = count }, false)
end

local function startSkyShow(scope: "Local" | "Global", admin: boolean): Ev?
	local cfg = EV.SkyShow
	local show = num(cfg.ShowSeconds, 75)
	effectAll("SkyShow", 1, { Seconds = show, Admin = admin })
	if admin then
		return addEvent("Lightshow", "Lightshow", show, scope, { Seconds = show }, true)
	end
	notifyAll("evt.skyShow", { math.floor(num(cfg.Seconds, 600) / 60) }, "Event")
	return addEvent("SkyShow", "SkyShow", num(cfg.Seconds, 600), scope, {
		Show = show,
		RespektMult = num(cfg.RespektMult, 2),
	}, false)
end

-- ---------------------------------------------------------------------
-- BÄR (Crash) & GOLDENER BULLE (Rally) – serverlokal, ohne Markteinfluss
-- ---------------------------------------------------------------------
local function bearGoal(): number
	local perPlayer = math.floor(num(EV.Bear.GoalPerPlayer, 25))
	return math.max(1, #Players:GetPlayers()) * perPlayer
end

local function orbSpot(): Vector3
	local cfg = EV.Bear
	local center = plazaCenter()
	local a = math.random() * math.pi * 2
	local r = num(cfg.RadiusMin, 20) + math.random() * (num(cfg.RadiusMax, 110) - num(cfg.RadiusMin, 20))
	return groundAt(center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), 2.5)
end

local function spawnOrb(p: Player, ev: Ev): boolean
	local maxOrbs = math.floor(num(EV.Bear.OrbsMaxPerPlayer, 60))
	local spawned = ev.Run.Spawned
	if type(spawned) ~= "table" then
		spawned = {}
		ev.Run.Spawned = spawned
	end
	if (spawned[p] or 0) >= maxOrbs then
		return false
	end
	local t = now()
	local token = addToken(p, ev.Key, "Orb", orbSpot(), t + 0.5, t, ev.Until, "Orb", 0, "")
	if token then
		spawned[p] = (spawned[p] or 0) + 1
		return true
	end
	return false
end

local function issueBear(p: Player, ev: Ev)
	for _ = 1, math.clamp(math.floor(num(EV.Bear.OrbsPerPlayer, 8)), 1, 20) do
		spawnOrb(p, ev)
	end
end
ISSUERS.Bear = issueBear

local function broadcastBear(force: boolean)
	local b = bear
	if not b then
		return
	end
	local t = os.clock()
	local sig = ("%d/%d"):format(b.Have, b.Goal)
	if not force and (sig == b.Sent or t - b.BroadcastAt < BEAR_BROADCAST_GAP) then
		return
	end
	b.Sent = sig
	b.BroadcastAt = t
	Remotes.World:FireAllClients("Bear", { Have = b.Have, Goal = b.Goal })
end

local function startBear(scope: "Local" | "Global", probe: boolean): Ev?
	if bear and events[bear.Key] then
		return events[bear.Key] -- ein Bär zur Zeit
	end
	local cfg = EV.Bear
	local key = "Bear"
	local goal = bearGoal()
	local ev = addEvent(key, "Bear", num(cfg.Seconds, 150), scope, { Goal = goal, Probe = probe }, false)
	if not ev then
		return nil
	end
	bear = { Key = key, Have = 0, Goal = goal, BroadcastAt = 0, Sent = "" }
	table.clear(bearPart)
	effectAll("Bear", 1, { Seconds = ev.Until - ev.Started, Phase = "Arrive", Goal = goal })
	notifyAll("evt.bearArrive", { goal }, "Alarm")
	broadcastBear(true)
	return ev
end

local function finishBear(success: boolean)
	local b = bear
	if not b then
		return
	end
	bear = nil
	local cfg = EV.Bear
	if success then
		stats.BearWins += 1
		local seconds = num(cfg.RewardMinutes, 10) * 60
		for p, orbs in pairs(bearPart) do
			if present(p) and orbs > 0 then
				local amount = creditIncome(p, seconds, "Event")
				if amount > 0 then
					effect(p, "CoinFly", amount, nil)
				end
				notify(p, "evt.bearRewarded", { math.floor(num(cfg.RewardMinutes, 10)) }, "Success")
				seasonXpOnce(p, b.Key .. tostring(math.floor(os.time() / 60)))
			end
		end
		effectAll("Bear", 1, { Phase = "Success" })
		notifyAll("evt.bearCalm", nil, "Success")
	else
		effectAll("Bear", 1, { Phase = "Leave" })
		notifyAll("evt.bearLeft", nil, "Info")
	end
	table.clear(bearPart)
	Remotes.World:FireAllClients("Bear", { Have = 0, Goal = 0 })
	endEvent(b.Key)
end

local function startGoldenBull(scope: "Local" | "Global"): Ev?
	local existing = events.GoldenBull
	if existing and existing.Until > now() then
		return existing
	end
	local cfg = EV.GoldenBull
	local seconds = num(cfg.Seconds, 180)
	local rally = ("Bull%d"):format(math.floor(now()))
	local ev =
		addEvent("GoldenBull", "GoldenBull", seconds, scope, { Route = cfg.Route or "Ring", Rally = rally }, false)
	if ev then
		ev.Run.Rally = rally
		effectAll("GoldenBull", 1, { Seconds = seconds, Phase = "Run" })
		notifyAll("evt.goldenBull", { math.floor(num(cfg.BonusSeconds, 300) / 60) }, "Event")
	end
	return ev
end

-- Bulle berühren: Server misst den Abstand zur berechneten Position (1×/s)
local function checkBullTouches(ev: Ev, t: number)
	local cfg = EV.GoldenBull
	local route = routeOf(ev.Data.Route or "Ring")
	if not route then
		return
	end
	local seconds = math.max(1, ev.Until - ev.Started)
	local pos = pointAt(route, math.clamp((t - ev.Started) / seconds, 0, 1))
	local range = num(cfg.TouchRange, 14)
	local rally: string = ev.Run.Rally or ev.Key
	for _, p in ipairs(Players:GetPlayers()) do
		if bullTouched[p] ~= rally then
			local root = rootOf(p)
			if root then
				local d = root.Position - pos
				if Vector2.new(d.X, d.Z).Magnitude <= range and math.abs(d.Y) < 16 then
					bullTouched[p] = rally
					local ok, granted = call("TowerService", "AddBoost", p, "Bull", num(cfg.BonusSeconds, 300))
					if ok and granted == true then
						effect(p, "GoldenBull", 1, { Phase = "Touch" })
						notify(p, "evt.bullTouched", { math.floor(num(cfg.BonusSeconds, 300) / 60) }, "Success")
					end
				end
			end
		end
	end
end

-- Markt-Nachrichten -> Bär/Bulle (Crash/Rally im Plan oder vom Besitzer). Kein Rückweg in den Markt.
local function onNews(n: any)
	if type(n) ~= "table" or type(n.Kind) ~= "string" then
		return
	end
	local adminMove = Config.News and Config.News.AdminMove
	local isCrash = n.Kind == "Crash" or (n.Kind == "Admin" and type(adminMove) == "table" and n.Key == adminMove.Crash)
	local isRally = n.Kind == "Rally" or (n.Kind == "Admin" and type(adminMove) == "table" and n.Key == adminMove.Rally)
	if isCrash then
		startBear("Local", false)
	elseif isRally then
		startGoldenBull("Local")
	end
end

-- ---------------------------------------------------------------------
-- GELDREGEN (pro Spieler instanziert, 4 Hz während er läuft)
-- ---------------------------------------------------------------------
local function rainSpot(p: Player): Vector3
	local cfg = EV.MoneyRain
	local root = rootOf(p)
	local roll = math.random()
	if root and roll < num(cfg.NearShare, 0.5) then
		local a = math.random() * math.pi * 2
		local r = num(cfg.NearMin, 10) + math.random() * (num(cfg.NearMax, 40) - num(cfg.NearMin, 10))
		return groundAt(root.Position + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), 2)
	end
	local okPlot, plot = call("PlotService", "PlotOf", p)
	if roll < 0.75 and okPlot and isNum(plot) then
		local okSite, site = call("CityService", "PlotSite", plot)
		if okSite and typeof(site) == "CFrame" then
			local toPlaza = plazaCenter() - site.Position
			local flat = Vector3.new(toPlaza.X, 0, toPlaza.Z)
			local front = if flat.Magnitude > 1 then site.Position + flat.Unit * 44 else site.Position
			local a = math.random() * math.pi * 2
			local r = math.random() * 18
			return groundAt(front + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), 2)
		end
	end
	local center = plazaCenter()
	local a = math.random() * math.pi * 2
	local r = 12 + math.random() * 95
	return groundAt(center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), 2)
end

local function startMoneyRain(seconds: number, scope: "Local" | "Global", admin: boolean, key: string?): Ev?
	local evKey = key or "MoneyRain"
	local ev = addEvent(evKey, "MoneyRain", seconds, scope, { Seconds = seconds }, admin)
	if not ev then
		return nil
	end
	table.clear(rainPlan)
	effectAll("MoneyRain", 1, { Seconds = seconds })
	notifyAll("evt.moneyRain", { math.floor(seconds) }, "Event")
	return ev
end

local function rainTick()
	local ev: Ev? = nil
	for _, candidate in pairs(events) do
		if candidate.Kind == "MoneyRain" and candidate.Until > now() then
			ev = candidate
			break
		end
	end
	if not ev then
		if next(rainPlan) ~= nil then
			table.clear(rainPlan)
		end
		return
	end
	local rain: Ev = ev
	local t = now()
	local total = math.clamp(math.floor(num(EV.RainCoinsMax, 30)), 1, 30)
	local duration = math.max(1, rain.Until - rain.Started)
	local fall = num(EV.MoneyRain.FallSeconds, 1.6)
	local linger = num(EV.MoneyRain.Linger, 25)
	local seconds = num(EV.RainCoinMinutes, 2) * 60
	for _, p in ipairs(Players:GetPlayers()) do
		if ready(p) then
			local plan = rainPlan[p]
			if not plan then
				local remaining = math.max(1, rain.Until - t)
				local left = math.max(1, math.floor(total * remaining / duration + 0.5))
				plan = { Next = t, Left = left, Gap = remaining / left }
				rainPlan[p] = plan
			end
			if plan.Left > 0 and t >= plan.Next then
				plan.Left -= 1
				plan.Next = t + plan.Gap
				addToken(p, rain.Key, "Coin", rainSpot(p), t + fall, t, rain.Until + linger, "Income", seconds, "Rain")
			end
		end
	end
	flushTokens(t)
end

-- ---------------------------------------------------------------------
-- ADMIN-SHOWS (Nicht-Markt, §B15.3)
-- ---------------------------------------------------------------------
local function startGoldenHour(mult: number, minutes: number, scope: "Local" | "Global", key: string?): Ev?
	local seconds = minutes * 60
	local untilT = now() + seconds
	if not boostsPaused() then
		eventMultValue = mult
		eventMultUntil = untilT
		call("TowerService", "SetEventMult", mult, untilT)
	end
	effectAll("AbuseBanner", 1, { Kind = "GoldenHour", Seconds = seconds, Mult = mult, Until = untilT })
	notifyAll("evt.goldenHour", { ("%g"):format(mult), math.floor(minutes) }, "Event")
	return addEvent(key or "GoldenHour", "GoldenHour", seconds, scope, { Mult = mult }, true)
end

local function startXpRush(minutes: number, scope: "Local" | "Global"): Ev?
	local seconds = minutes * 60
	local kind = (Config.Progression and Config.Progression.XpRushKind) or "XpRush"
	effectAll("AbuseBanner", 1, { Kind = "XpRush", Seconds = seconds, Mult = 2, Until = now() + seconds })
	notifyAll("evt.xpRush", { math.floor(minutes) }, "Event")
	return addEvent("XpRush", kind, seconds, scope, { Mult = 2 }, true)
end

local function startAdminBuildBoom(scope: "Local" | "Global"): Ev?
	local cfg = EV.AdminLimits.BuildBoom
	local seconds = num(cfg.Minutes, 10) * 60
	local untilT = now() + seconds
	call("TowerService", "SetCostEvent", "Floor", math.clamp(num(cfg.CostMult, 0.5), 0.1, 1), untilT)
	call("TowerService", "SetBuildEvent", math.clamp(num(cfg.BuildMult, 0.1), 0, 1), untilT)
	effectAll("AbuseBanner", 1, { Kind = "BuildBoom", Seconds = seconds, Until = untilT })
	notifyAll("evt.adminBuildBoom", { math.floor(seconds / 60) }, "Event")
	return addEvent("AdminBuildBoom", "BuildBoom", seconds, scope, {
		Pct = 1 - num(cfg.CostMult, 0.5),
		Build = 1 - num(cfg.BuildMult, 0.1),
		Admin = true,
	}, true)
end

local function startFireworks(
	seconds: number,
	plot: number?,
	userId: number?,
	scope: "Local" | "Global",
	admin: boolean
): Ev?
	local key = ("Fireworks:%s"):format(tostring(userId or "Show"))
	effectAll("Fireworks", 1, { Seconds = seconds, Plot = plot, UserId = userId })
	return addEvent(key, "Fireworks", seconds, scope, { Plot = plot, UserId = userId }, admin)
end

-- Boss-Auftritt: Besitzer-Avatar ×8 auf dem Börsensaal-Dach (CreateHumanoidModelFromDescriptionAsync, kein Upload)
local function buildBoss(ev: Ev, userId: number)
	local limits = EV.AdminLimits.Boss
	local count = math.clamp(math.floor(num(limits.Count, 8)), 1, 8)
	local spacing = num(limits.Spacing, 9)
	local desc: HumanoidDescription? = nil
	if userId > 0 then
		local ok, result = pcall(function()
			return Players:GetHumanoidDescriptionFromUserIdAsync(userId)
		end)
		if ok and typeof(result) == "Instance" and result:IsA("HumanoidDescription") then
			desc = result
		end
	end
	if not desc then
		desc = Instance.new("HumanoidDescription")
	end
	local okModel, model = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(desc :: HumanoidDescription, Enum.HumanoidRigType.R15)
	end)
	if not okModel or typeof(model) ~= "Instance" or not model:IsA("Model") then
		logError("Boss", model)
		return
	end
	if events[ev.Key] ~= ev then
		model:Destroy()
		return -- schon vorbei
	end
	local roof = anchor("Rooftop") or anchor("Bell") or CFrame.new(plazaCenter() + Vector3.new(0, 60, -120))
	local holder = Instance.new("Model")
	holder.Name = "AT_BossShow"
	holder.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local template: Model = model
	local humanoid = template:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	-- Nur die Wurzel verankern: die Glieder hängen über Motor6D daran, damit die Winke-Pose (EffectsEvent setzt
	-- RightShoulder.C0 lokal) sie bewegen kann – zwischen zwei verankerten Teilen bewegt ein Gelenk nichts.
	local rootPart = template:FindFirstChild("HumanoidRootPart") or template.PrimaryPart
	for _, d in ipairs(template:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = rootPart == nil or d == rootPart
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local height = template:GetExtentsSize().Y
	for i = 1, count do
		local clone = if i == count then template else template:Clone()
		clone.Name = ("Boss%d"):format(i)
		local offset = (i - (count + 1) / 2) * spacing
		clone:PivotTo(roof * CFrame.new(offset, height * 0.5 + 0.2, 0) * CFrame.Angles(0, math.pi, 0))
		clone.Parent = holder
	end
	holder.Parent = folder()
	ev.Run.Model = holder
	effectAll("BossAppear", 1, { Seconds = ev.Until - now(), UserId = userId, Name = playerName(userId) })
end

local function startBoss(seconds: number, userId: number, scope: "Local" | "Global"): Ev?
	local old = events.Boss
	if old then
		local model = old.Run.Model
		if typeof(model) == "Instance" then
			model:Destroy()
		end
		endEvent("Boss")
	end
	local ev = addEvent("Boss", "Boss", seconds, scope, { UserId = userId }, true)
	if not ev then
		return nil
	end
	notifyAll("evt.boss", { playerName(userId) }, "Event")
	task.spawn(buildBoss, ev, userId)
	return ev
end

-- Alle in den Börsensaal (nur dieser Server): Ring-Aufstellung vor der Glocke
local function allToHall(): number
	local base = anchor("Bell")
	local center: Vector3
	local look: Vector3
	if base then
		center = base.Position + base.LookVector * 18
		look = base.Position
	else
		local zones = Config.City and Config.City.Zones
		local exchange = zones and zones.Exchange
		center = (
			if exchange and typeof(exchange.Center) == "Vector3" then exchange.Center else Vector3.new(0, 0, -190)
		) + Vector3.new(0, 0, 30)
		look = center + Vector3.new(0, 0, -10)
	end
	local limits = EV.AdminLimits.AllToHall
	local spacing = num(limits.Spacing, 5)
	local done = 0
	for i, p in ipairs(Players:GetPlayers()) do
		local ring = 1 + (i - 1) // 8
		local a = ((i - 1) % 8) / 8 * math.pi * 2
		local pos = center + Vector3.new(math.cos(a), 0, math.sin(a)) * (ring * spacing)
		local ok, moved = call("PlotService", "Teleport", p, CFrame.lookAt(pos, Vector3.new(look.X, pos.Y, look.Z)))
		if ok and moved == true then
			done += 1
		end
	end
	effectAll("AbuseBanner", 1, { Kind = "AllToHall", Seconds = 6 })
	return done
end

-- Samstags-Show (Banner -> Golden Hour ×2 30 min -> Rally (Markt, separat) -> Geldregen -> Feuerwerk)
local function startShow(kind: "AutoShow" | "SaturdayShow", args: Plain, scope: "Local" | "Global"): Ev?
	local existing = events.Show
	if existing and existing.Until > now() then
		return nil
	end
	local goldenMult = math.clamp(num(args.GoldenMult, 2), 1, 3)
	local goldenMinutes = math.clamp(num(args.GoldenMinutes, 30), 1, 60)
	local rainDelay = math.clamp(num(args.RainDelay, 75), 0, 1800)
	local rainSeconds = math.clamp(num(args.RainSeconds, 180), 60, 300)
	local fireworksDelay = math.clamp(num(args.FireworksDelay, 260), 0, 1800)
	local length = math.max(rainDelay + rainSeconds, fireworksDelay + num(EV.Fireworks.Seconds, 20)) + 5
	local sector = sectorOfWeek()
	local ev = addEvent("Show", kind, length, scope, { Sector = sector }, kind == "SaturdayShow")
	if not ev then
		return nil
	end
	local t = ev.Started
	ev.Run.Steps = {
		{ At = t + rainDelay, Kind = "Rain", Seconds = rainSeconds, Done = false },
		{ At = t + fireworksDelay, Kind = "Fireworks", Done = false },
	}
	effectAll("AbuseBanner", 1, { Kind = kind, Seconds = 8, Sector = sector })
	notifyAll(if kind == "AutoShow" then "evt.autoShow" else "evt.saturdayShow", nil, "Event")
	startGoldenHour(goldenMult, goldenMinutes, scope, "ShowGolden")
	return ev
end

local function runShowSteps(ev: Ev, t: number)
	local steps = ev.Run.Steps
	if type(steps) ~= "table" then
		return
	end
	for _, step in ipairs(steps) do
		if not step.Done and t >= step.At then
			step.Done = true
			if step.Kind == "Rain" then
				startMoneyRain(step.Seconds, ev.Scope, ev.Admin, "ShowRain")
			elseif step.Kind == "Fireworks" then
				startFireworks(num(EV.Fireworks.Seconds, 20), nil, nil, ev.Scope, ev.Admin)
			end
		end
	end
end

-- Bilanz-Sonntag: Liga-Finale-Show + Top-10-Hologramme (Namen aus LeaderboardService, ohne Werte)
local function startLeagueFinale(args: Plain, scope: "Local" | "Global"): Ev?
	local seconds = math.clamp(num(args.Seconds, 150), 30, 600)
	local top: { string } = {}
	local ok, rows =
		call("LeaderboardService", "Top", EV.LeagueBoard or "League", math.clamp(math.floor(num(args.Top, 10)), 1, 10))
	if ok and type(rows) == "table" then
		for _, row in ipairs(rows) do
			if type(row) == "table" and type(row.Name) == "string" and #top < 10 then
				table.insert(top, string.sub(row.Name, 1, 32))
			end
		end
	end
	effectAll("SkyShow", 1, { Seconds = math.min(seconds, num(EV.SkyShow.ShowSeconds, 75)), Finale = true })
	notifyAll("evt.leagueFinale", nil, "Event")
	local hall = anchor("HallOfFame")
	return addEvent(
		"LeagueFinale",
		"LeagueFinale",
		seconds,
		scope,
		{ Top = top, Pos = if hall then hall.Position else plazaCenter() + Vector3.new(30, 0, 30) },
		false
	)
end

-- ---------------------------------------------------------------------
-- KLEMMEN (§B15.3) – reine Funktion, auch für AdminTests
-- ---------------------------------------------------------------------
local function clampNum(value: any, lo: number, hi: number, default: number): number
	local n = tonumber(value)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		n = default
	end
	return math.clamp(n :: number, lo, hi)
end

function EventService.Clamp(kind: string, args: any): ({ [string]: any }?, string?)
	if type(kind) ~= "string" or not START_KINDS[kind] then
		return nil, "admin.evUnknown"
	end
	local raw: Plain = if type(args) == "table" then args else {}
	local limits = EV.AdminLimits
	local out: Plain = {}
	if kind == "MoneyRain" then
		local r = limits.MoneyRain.Seconds
		out.Seconds = math.floor(clampNum(raw.Seconds, r[1], r[2], num(EV.MoneyRain.DefaultSeconds, 120)))
	elseif kind == "GoldenHour" then
		local m, mins = limits.GoldenHour.Mult, limits.GoldenHour.Minutes
		local mult = clampNum(raw.Mult, m[1], m[2], m[1])
		out.Mult = if mult >= 2.5 then 3 else 2 -- nur ×2 oder ×3 (§B15.3)
		out.Mult = math.clamp(out.Mult, m[1], m[2])
		out.Minutes = math.floor(clampNum(raw.Minutes, mins[1], mins[2], mins[1]))
	elseif kind == "XpRush" then
		local mins = limits.XpRush.Minutes
		out.Minutes = math.floor(clampNum(raw.Minutes, mins[1], mins[2], mins[1]))
	elseif kind == "Boss" then
		local r = limits.Boss.Seconds
		out.Seconds = math.floor(clampNum(raw.Seconds, r[1], r[2], r[1]))
	elseif kind == "SaturdayShow" or kind == "AutoShow" then
		local show = limits.SaturdayShow
		out.GoldenMult = show.GoldenMult
		out.GoldenMinutes = show.GoldenMinutes
		out.RainDelay = show.RainDelay
		out.RainSeconds = show.RainSeconds
		out.FireworksDelay = show.FireworksDelay
	elseif kind == "LeagueFinale" then
		out.Seconds = math.floor(clampNum(raw.Seconds, 30, 600, 150))
		out.Top = 10
	end
	if raw.Probe == true then
		out.Probe = true
	end
	return out, nil
end

function EventService.Kinds(): { string }
	local list: { string } = {}
	for kind in pairs(START_KINDS) do
		table.insert(list, kind)
	end
	table.sort(list)
	return list
end

-- ---------------------------------------------------------------------
-- STARTEN (lokal, global über AdminService, geplant)
-- ---------------------------------------------------------------------
local function runEvent(kind: string, args: Plain, scope: "Local" | "Global", byUserId: number?): (boolean, string)
	local ev: Ev? = nil
	if WORLD_KINDS[kind] then
		ev = startWorld(kind, scope)
	elseif kind == "BellMoment" then
		ev = triggerBellMoment(scope, playersInBellZone())
	elseif kind == "SkyShow" then
		ev = startSkyShow(scope, false)
	elseif kind == "Lightshow" then
		ev = startSkyShow(scope, true)
	elseif kind == "Bear" then
		ev = startBear(scope, args.Probe == true)
	elseif kind == "GoldenBull" then
		ev = startGoldenBull(scope)
	elseif kind == "MoneyRain" then
		ev = startMoneyRain(args.Seconds, scope, true, nil)
	elseif kind == "GoldenHour" then
		ev = startGoldenHour(args.Mult, args.Minutes, scope, nil)
	elseif kind == "XpRush" then
		ev = startXpRush(args.Minutes, scope)
	elseif kind == "AdminBuildBoom" then
		ev = startAdminBuildBoom(scope)
	elseif kind == "Fireworks" then
		ev = startFireworks(num(EV.AdminLimits.Fireworks.Seconds, 20), nil, nil, scope, true)
	elseif kind == "Confetti" then
		effectAll("Confetti", 2, nil)
		ev = addEvent("Confetti", "Confetti", num(EV.AdminLimits.Confetti.Seconds, 6), scope, {}, true)
	elseif kind == "BellShow" then
		local seconds = num(EV.AdminLimits.BellShow.Seconds, 30)
		effectAll("BellMoment", 1, { Seconds = seconds, Show = true })
		ev = addEvent("BellShow", "BellShow", seconds, scope, {}, true)
	elseif kind == "Boss" then
		ev = startBoss(args.Seconds, byUserId or game.CreatorId, scope)
	elseif kind == "AllToHall" then
		local moved = allToHall()
		ev = addEvent("AllToHall", "AllToHall", 6, "Local", { Moved = moved }, true)
	elseif kind == "SaturdayShow" or kind == "AutoShow" then
		ev = startShow(kind, args, scope)
	elseif kind == "LeagueFinale" then
		ev = startLeagueFinale(args, scope)
	end
	if ev == nil then
		return false, "admin.evBusy"
	end
	return true, "admin.evStarted"
end

-- Admin-/System-Event starten (öffentlicher Teil von EventService.Start, siehe unten)
local function startEvent(
	kind: string,
	args: { [string]: any },
	scope: "Local" | "Global",
	by: Player?
): (boolean, string)
	local clean, err = EventService.Clamp(kind, args)
	if not clean then
		return false, err or "admin.evUnknown"
	end
	local scopeName: "Local" | "Global" = if scope == "Global" then "Global" else "Local"
	if scopeName == "Global" and kind == "AllToHall" then
		scopeName = "Local" -- nur dieser Server (§B15.3)
	end
	if scopeName == "Global" and by ~= nil then
		-- über AdminService an alle Server (MessagingService "AT_Global"); der Sender empfängt selbst
		local ok, sent, how = call("AdminService", "PublishAbuse", kind, clean, by)
		if ok and sent == true then
			return true, if how == "local" then "admin.globalFailed" else "admin.evGlobal"
		end
	end
	return runEvent(kind, clean, scopeName, if by then by.UserId else nil)
end

-- Globale Admin-Abuse-Nachricht (von AdminService.handleGlobal): jedes Feld prüfen, obere Zeitgrenze, dann planen
function EventService.ApplyGlobal(msg: any): boolean
	if type(msg) ~= "table" or type(msg.Event) ~= "string" then
		return false
	end
	local kind = msg.Event
	if not ADMIN_KINDS[kind] or kind == "AllToHall" then
		return false
	end
	local clean = EventService.Clamp(kind, msg.Args)
	if not clean then
		return false
	end
	local t = now()
	local maxSeconds = num(EV.MaxGlobalSeconds, 3600)
	local startAt = msg.StartAt
	if not isNum(startAt) or startAt > t + maxSeconds then
		return false
	end
	local untilT = msg.Until
	if not isNum(untilT) or untilT <= t or untilT > t + maxSeconds then
		return false
	end
	local by = if isNum(msg.By) and msg.By % 1 == 0 then msg.By else nil
	if startAt <= t + 0.05 then
		runEvent(kind, clean, "Global", by)
		return true
	end
	if #pending >= MAX_PENDING then
		return false
	end
	table.insert(pending, { At = startAt, Kind = kind, Args = clean, Scope = "Global", By = by, Meta = nil })
	return true
end

function EventService.Stop(kind: string): number
	if type(kind) ~= "string" then
		return 0
	end
	local keys: { string } = {}
	for key, ev in pairs(events) do
		if ev.Kind == kind then
			table.insert(keys, key)
		end
	end
	for _, key in ipairs(keys) do
		local ev = events[key]
		if ev and ev.Kind == "GoldenHour" then
			eventMultValue, eventMultUntil = 1, 0
			call("TowerService", "SetEventMult", 1, 0)
		elseif ev and ev.Kind == "Bear" then
			finishBear(false)
		end
		if ev and ev.Kind == "Boss" then
			local model = ev.Run.Model
			if typeof(model) == "Instance" then
				model:Destroy()
			end
		end
		endEvent(key)
	end
	return #keys
end

function EventService.StartParade(buyer: Player, seconds: number)
	if not isNum(seconds) or seconds <= 0 then
		return
	end
	local cfg = EV.Parade
	local length = math.clamp(seconds, 1, num(cfg.MaxSeconds, 3600))
	local userId = if present(buyer) then buyer.UserId else 0
	local name = if present(buyer) then string.sub(buyer.DisplayName, 1, 40) else "?"
	local existing = events.Parade
	local untilT = now() + length
	if existing then
		existing.Until = untilT
		existing.Data = { UserId = userId, Name = name, Route = cfg.Route or "Parade", Bulls = cfg.Bulls }
		Remotes.World:FireAllClients("Event", publicState(existing))
		markAll()
	else
		addEvent("Parade", "Parade", length, "Local", {
			UserId = userId,
			Name = name,
			Route = cfg.Route or "Parade",
			Bulls = cfg.Bulls,
		}, false)
	end
	Remotes.World:FireAllClients("Parade", { UserId = userId, Until = untilT })
	effectAll("BullParade", 1, { Seconds = length, UserId = userId, Name = name, Until = untilT })
	notifyAll("evt.paradeThanks", { name }, "Event")
end

function EventService.StartFireworks(buyer: Player)
	local plot: number? = nil
	local userId: number? = nil
	if present(buyer) then
		userId = buyer.UserId
		local ok, result = call("PlotService", "PlotOf", buyer)
		if ok and isNum(result) then
			plot = result
		end
	end
	startFireworks(num(EV.Fireworks.Seconds, 20), plot, userId, "Local", false)
	if userId then
		notifyAll("evt.fireworksBy", { playerName(userId) }, "Event")
	end
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICHE ABFRAGEN
-- ---------------------------------------------------------------------
function EventService.Active(): { EventState }
	local t = now()
	local list: { EventState } = {}
	for _, ev in pairs(events) do
		if ev.Until > t then
			table.insert(list, publicState(ev))
		end
	end
	table.sort(list, function(a, b)
		return a.Until < b.Until
	end)
	return list
end

function EventService.EventMult(): number
	if boostsPaused() or now() >= eventMultUntil then
		return 1
	end
	local cap = num(Config.Tower and Config.Tower.Mult and Config.Tower.Mult.EventMax, 3)
	return math.clamp(eventMultValue, 1, math.min(3, cap))
end

function EventService.IsAdminAbuse(): boolean
	local t = now()
	for _, ev in pairs(events) do
		if ev.Admin and ev.Until > t then
			return true
		end
	end
	local ok, window = call("MarketService", "AdminWindowActive")
	return ok and window == true
end

function EventService.BearActive(): boolean
	return bear ~= nil
end

function EventService.Stats(): { [string]: number }
	local open = 0
	for _, n in pairs(tokenCount) do
		open += n
	end
	return {
		Active = countEvents(),
		Started = stats.Started,
		Pickups = stats.Pickups,
		Rejected = stats.Rejected,
		BearWins = stats.BearWins,
		OpenTokens = open,
	}
end

-- nächstes Welt-Event (für die HUD-Pille „… in 4:12“)
local function nextWorld(t: number): Plain?
	local tick = Clock.TickOf(t)
	local day = Clock.DayIndex(tick)
	local minute = math.floor(num(EV.WorldMinute, 10))
	for offset = 0, 1 do
		local at = (day + offset) * DAY + minute * 60
		if at > tick then
			local kind = rotationKind(day + offset)
			if kind then
				return { Kind = kind, At = Clock.UnixOf(at) }
			end
		end
	end
	return nil
end

local function eventState(_p: Player): Plain
	local active = EventService.Active()
	while #active > MAX_ACTIVE_STATE do
		table.remove(active)
	end
	local b = bear
	return {
		Active = active,
		Next = nextWorld(now()) or { Kind = "", At = 0 },
		AdminAbuse = EventService.IsAdminAbuse(),
		BearHave = if b then b.Have else 0,
		BearGoal = if b then b.Goal else 0,
	}
end

-- ---------------------------------------------------------------------
-- REQUEST "EventPickup" {Id} (§C9: Token gehört dem Spieler, Fenster gültig, Abstand ≤ 12, max. 1 je Id)
-- ---------------------------------------------------------------------
local function reject(p: Player, key: string): Types.Reply
	stats.Rejected += 1
	local ok, lang = call("PlayerStateService", "LangOf", p)
	return { Ok = false, Message = Lang.T(if ok and (lang == "de" or lang == "en") then lang else Lang.For(p), key) }
end

local function rewardQuiz(p: Player, token: Token, ev: Ev?)
	local state = quiz[p]
	if not state or state.Event ~= token.Event or state.Done or token.Q ~= state.Q then
		return
	end
	-- alle Antwort-Felder dieser Frage verschwinden
	local list = tokens[p]
	if list then
		local siblings: { number } = {}
		for id, other in pairs(list) do
			if other.Event == token.Event and other.Reward == "Quiz" and other.Q == token.Q then
				table.insert(siblings, id)
			end
		end
		for _, id in ipairs(siblings) do
			removeToken(p, id, true)
		end
	end
	local ids: { number } = if ev and type(ev.Run.Quiz) == "table" then ev.Run.Quiz else {}
	local quizId = ids[token.Q]
	local correctIndex = 0
	for _, entry in ipairs(EV.Press.Quiz) do
		if entry.Id == quizId then
			correctIndex = entry.Correct
			break
		end
	end
	local right = token.O == correctIndex
	if right then
		state.Correct += 1
	end
	effect(
		p,
		"Toast",
		1,
		{ Key = if right then "evt.quizRight" else "evt.quizWrong", Kind = if right then "Success" else "Info" }
	)
	local total = #ids
	if token.Q >= total then
		state.Done = true
		if state.Correct >= math.floor(num(EV.Press.PassCorrect, 2)) then
			call("ProgressionService", "AddXp", p, num(EV.Press.QuizXp, 50), "PressQuiz", nil)
			notify(p, "evt.quizPassed", { state.Correct, total, math.floor(num(EV.Press.QuizXp, 50)) }, "Success")
			seasonXpOnce(p, token.Event)
		else
			notify(p, "evt.quizFailed", { state.Correct, total }, "Info")
		end
	elseif ev and ev.Until > now() then
		state.Q += 1
		issueQuestion(p, ev, state.Q)
		flushTokens(now())
	end
end

local function handlePickup(p: Player, arg: any): Types.Reply
	if type(arg) ~= "table" then
		return reject(p, "core.invalid")
	end
	for key in pairs(arg) do
		if key ~= "Id" then
			return reject(p, "core.invalid")
		end
	end
	local id = arg.Id
	if not isNum(id) or id % 1 ~= 0 or id < 1 or id > 2 ^ 31 then
		return reject(p, "core.invalid")
	end
	local list = tokens[p]
	local token = list and list[id]
	if not token then
		return reject(p, "evt.pickupGone") -- fremdes, abgelaufenes oder schon gesammeltes Token
	end
	local t = now()
	if t < token.From - PICKUP_SLACK or t > token.Until then
		if t > token.Until then
			removeToken(p, id, true)
		end
		return reject(p, "evt.pickupWindow")
	end
	local root = rootOf(p)
	if not root then
		return reject(p, "evt.pickupFar")
	end
	local range = num(EV.PickupRange, 12) + RANGE_SLACK
	if (root.Position - token.Pos).Magnitude > range then
		return reject(p, "evt.pickupFar") -- Fernsammeln abgelehnt (§C11.2)
	end
	removeToken(p, id, false)
	stats.Pickups += 1
	local ev = events[token.Event]
	if token.Reward == "Income" then
		local amount = creditIncome(p, token.Seconds, token.Source)
		local count = participation(p, token.Event)
		call("RewardService", "Track", p, "Pickup", 1, { Kind = token.Kind })
		local needed = if token.Kind == "Bundle"
			then math.floor(num(EV.Truck.SeasonXpMin, 10))
			elseif token.Kind == "Package" then math.max(1, math.floor(num(EV.Drones.Packages, 8) / 2))
			else math.huge
		if count >= needed then
			seasonXpOnce(p, token.Event)
		end
		return { Ok = true, Id = id, Credits = amount }
	elseif token.Reward == "Orb" then
		local b = bear
		if b and ev and ev.Key == b.Key then
			b.Have += 1
			bearPart[p] = (bearPart[p] or 0) + 1
			participation(p, token.Event)
			call("RewardService", "Track", p, "BearOrbs", 1, nil)
			spawnOrb(p, ev)
			flushTokens(t)
			broadcastBear(false)
			if b.Have >= b.Goal then
				finishBear(true)
			end
		end
		return { Ok = true, Id = id }
	elseif token.Reward == "Quiz" then
		rewardQuiz(p, token, ev)
		return { Ok = true, Id = id }
	end
	return { Ok = true, Id = id }
end

-- ---------------------------------------------------------------------
-- TAKT (1 Hz): Börsentag-Grenzen, Wochen-Kalender, Ablauf, Bulle, Glocken-Zone, Token senden, State
-- ---------------------------------------------------------------------
local function onTickBoundary(tick: number)
	local within = tick % DAY
	local day = tick // DAY
	if within == math.floor(num(EV.WorldMinute, 10)) * 60 then
		local kind = rotationKind(day)
		if kind then
			runEvent(kind, {}, "Local", nil)
		end
	end
	local bellCfg = EV.BellMoment
	if within == 0 and day % math.max(1, math.floor(num(bellCfg.DayEvery, 3))) == 0 then
		bellWindow = { Day = day, Until = Clock.UnixOf(tick) + num(bellCfg.WindowSeconds, 60), Done = false }
	end
	local skyCfg = EV.SkyShow
	if
		within == math.floor(num(skyCfg.Minute, 15)) * 60
		and day % math.max(1, math.floor(num(skyCfg.DayEvery, 3))) == 0
		and Clock.IsNight(tick)
	then
		startSkyShow("Local", false)
	end
end

local function bellCheck(t: number)
	local window = bellWindow
	if not window or window.Done then
		return
	end
	if t > window.Until then
		bellWindow = nil
		return
	end
	local needed = math.floor(num(EV.BellMoment.MinPlayers, 3))
	if isStudio() then
		needed = math.floor(num(Config.Studio and Config.Studio.BellZoneMinPlayers, 1))
	end
	local count = playersInBellZone()
	if count >= math.max(1, needed) then
		window.Done = true
		triggerBellMoment("Local", count)
	end
end

local function weeklyFire(entry: Plain, t: number)
	local args = if type(entry.Args) == "table" then entry.Args else {}
	if entry.Kind == "PowerHour" then
		local minutes = math.clamp(num(args.Minutes, 60), 1, 240)
		addEvent("PowerHour", "PowerHour", minutes * 60, "Local", { Mult = 2 }, false)
		notifyAll("evt.powerHour", { math.floor(minutes) }, "Event")
	elseif entry.Kind == "Reminder" then
		local key = if type(args.Text) == "string" then args.Text else "evt.cal.update"
		for _, p in ipairs(Players:GetPlayers()) do
			local ok, admin = call("AdminService", "IsAdmin", p)
			if ok and admin == true then
				notify(p, key, nil, "Alarm")
			end
		end
	elseif entry.Kind == "AutoShow" then
		local week = Clock.WeekIndex(Clock.TickOf(t))
		local ok, cancelled = call("MarketService", "AutoShowCancelled", week)
		if ok and cancelled == true then
			return -- der Besitzer hat eine eigene Show gestartet (CancelAutoShow im GlobalBus)
		end
		local clean = EventService.Clamp("AutoShow", args) or {}
		startShow("AutoShow", clean, "Local")
	elseif entry.Kind == "LeagueFinale" then
		task.spawn(function()
			local clean = EventService.Clamp("LeagueFinale", args) or {}
			startLeagueFinale(clean, "Local")
		end)
	end
end

-- Letzter Termin (Berlin) bis einschließlich t – für Server, die mitten in einem Termin starten
local function previousBerlin(entry: Plain, t: number): number?
	local prev = Clock.NextBerlin(entry.Dow, entry.HH, entry.MM, t - 8 * 86400)
	if prev > t then
		return nil
	end
	for _ = 1, 9 do -- täglich: höchstens 8 Schritte, wöchentlich: höchstens 2
		local nextAt = Clock.NextBerlin(entry.Dow, entry.HH, entry.MM, prev)
		if nextAt > t then
			break
		end
		prev = nextAt
	end
	return prev
end

-- Nachholen beim Server-Start: ein neuer Server (Andrang zur Samstags-Show!) zeigt die Automatik-Show noch,
-- wenn sie erst vor Kurzem begonnen hat (Sekunden je Kind)
local WEEKLY_CATCHUP: { [string]: number } = { AutoShow = 150 }
local catchupAt: { [string]: number } = {}

-- Absage-Liste (GlobalBus) erst nach dem Markt-Start verlässlich – vorher nichts nachholen
local function marketReady(): boolean
	if not service("MarketService") then
		return true
	end
	local ok, info = call("MarketService", "Stats")
	return ok and type(info) == "table" and info.Ready == true
end

local function weeklyCatchup(entry: Plain, key: string, t: number)
	local since = catchupAt[key]
	if since == nil then
		return
	end
	if t - since > (WEEKLY_CATCHUP[tostring(entry.Kind)] or 0) then
		catchupAt[key] = nil
	elseif marketReady() then
		catchupAt[key] = nil
		local ok, err = pcall(weeklyFire, entry, t)
		if not ok then
			logError("Weekly " .. key, err)
		end
	end
end

local function weeklyTick(t: number)
	for _, entry in ipairs(EV.Weekly) do
		local key = entry.Key
		if type(key) == "string" then
			local at = weeklyNext[key]
			if at == nil then
				weeklyNext[key] = Clock.NextBerlin(entry.Dow, entry.HH, entry.MM, t)
				local catchup = WEEKLY_CATCHUP[tostring(entry.Kind)]
				local okPrev, prev = pcall(previousBerlin, entry, t)
				if catchup and okPrev and type(prev) == "number" and t - prev <= catchup then
					catchupAt[key] = prev
				end
			elseif t >= at then
				weeklyNext[key] = Clock.NextBerlin(entry.Dow, entry.HH, entry.MM, at)
				catchupAt[key] = nil -- regulärer Termin feuert selbst
				if t - at <= 60 then
					local ok, err = pcall(weeklyFire, entry, t)
					if not ok then
						logError("Weekly " .. key, err)
					end
				end
			end
			weeklyCatchup(entry, key, t)
		end
	end
end

local function expireEvents(t: number)
	local ended: { string } = {}
	for key, ev in pairs(events) do
		if ev.Until <= t then
			table.insert(ended, key)
		elseif ev.Kind == "GoldenBull" then
			checkBullTouches(ev, t)
		elseif ev.Kind == "AutoShow" or ev.Kind == "SaturdayShow" then
			runShowSteps(ev, t)
		end
	end
	for _, key in ipairs(ended) do
		local ev = events[key]
		if ev then
			if ev.Kind == "Bear" then
				finishBear(false)
			else
				if ev.Kind == "Boss" then
					local model = ev.Run.Model
					if typeof(model) == "Instance" then
						model:Destroy()
					end
				elseif ev.Kind == "Press" then
					for p, state in pairs(quiz) do
						if state.Event == key then
							quiz[p] = nil
						end
					end
				end
				endEvent(key)
			end
		end
	end
	-- Bär: Ziel folgt der Spielerzahl (25 × anwesende Spieler)
	local b = bear
	if b then
		local goal = bearGoal()
		if goal ~= b.Goal then
			b.Goal = goal
			broadcastBear(true)
			if b.Have >= b.Goal then
				finishBear(true)
			end
		end
	end
end

local function runPending(t: number)
	local i = 1
	while i <= #pending do
		local entry = pending[i]
		if t >= entry.At then
			table.remove(pending, i)
			local ok, err = pcall(function()
				runEvent(entry.Kind, entry.Args, entry.Scope, entry.By)
			end)
			if not ok then
				logError("pending " .. entry.Kind, err)
			end
		else
			i += 1
		end
	end
end

local function tickSecond()
	local t = now()
	local tick = Clock.TickOf(t)
	local from = (lastTick or tick - 1) + 1
	if tick - from > MAX_CATCHUP_TICKS then
		from = tick - MAX_CATCHUP_TICKS -- nach Stillstand nur die letzten Sekunden nachholen
	end
	for boundary = from, tick do
		onTickBoundary(boundary)
	end
	lastTick = tick
	runPending(t)
	weeklyTick(t)
	expireEvents(t)
	bellCheck(t)
	issueAll()
	flushTokens(t)
	-- State nur bei Änderung neu senden (Bär-Fortschritt, Events, Admin-Fenster)
	local b = bear
	local upcoming = nextWorld(t)
	local sig = ("%d|%s|%d|%s"):format(
		countEvents(),
		if EventService.IsAdminAbuse() then "A" else "-",
		if b then b.Have * 1000 + b.Goal else 0,
		tostring(if upcoming then upcoming.At else 0)
	)
	if sig ~= stateSig then
		stateSig = sig
		markAll()
	end
end

-- ---------------------------------------------------------------------
-- LEBENSZYKLUS
-- ---------------------------------------------------------------------
local function clearPlayer(p: Player)
	tokens[p] = nil
	tokenCount[p] = nil
	issued[p] = nil
	collected[p] = nil
	rewarded[p] = nil
	quiz[p] = nil
	bullTouched[p] = nil
	rainPlan[p] = nil
	bearPart[p] = nil
	for _, ev in pairs(events) do
		local spawned = ev.Run.Spawned
		if type(spawned) == "table" then
			spawned[p] = nil
		end
	end
end

-- Anker-Positionen für die Clients (Glocken-Zone, Pressewand, Hall of Fame) als workspace-Attribute:
-- der Client kennt CityLayout nicht und darf unter StreamingEnabled nicht auf ferne Teile warten.
local function publishAnchors()
	local center, radius = bellZone()
	workspace:SetAttribute("AT_BellZone", center)
	workspace:SetAttribute("AT_BellZoneRadius", radius)
	local press = anchor("PressScreen")
	if press then
		workspace:SetAttribute("AT_PressPos", press.Position)
		workspace:SetAttribute("AT_PressLook", press.LookVector)
	end
	local hall = anchor("HallOfFame")
	if hall then
		workspace:SetAttribute("AT_HallPos", hall.Position)
	end
end

function EventService.Init(services: any)
	Services = services
	-- Request + State in Init registrieren (§C3 Phase 2); PlayerStateService ist Kern (WP1)
	local pss = services and services.PlayerStateService
	if pss and type(pss.Handle) == "function" and type(pss.Provide) == "function" then
		pss.Handle("EventPickup", handlePickup, { Rate = 10, Per = 1 })
		pss.Provide("Event", eventState)
	else
		warn("[EventService] PlayerStateService fehlt – EventPickup/State nicht registriert")
	end
end

-- Lebenszyklus-Start (Phase 3 im Loader): Verbindungen, Kalender-Nachlauf, Anker, Takte
local function boot()
	Players.PlayerRemoving:Connect(clearPlayer)
	call("MarketService", "OnNews", onNews)
	-- Power-Hour, die beim Server-Start schon läuft, sofort anzeigen
	local t = now()
	for _, entry in ipairs(EV.Weekly) do
		if entry.Kind == "PowerHour" and type(entry.Args) == "table" then
			local prev = Clock.NextBerlin(entry.Dow, entry.HH, entry.MM, t - 7 * 86400 - 1)
			local guard = 0
			while guard < 8 do -- höchstens 8 Kandidaten (täglich eine Woche zurück)
				guard += 1
				local nextAt = Clock.NextBerlin(entry.Dow, entry.HH, entry.MM, prev)
				if nextAt > t then
					break
				end
				prev = nextAt
			end
			local minutes = math.clamp(num(entry.Args.Minutes, 60), 1, 240)
			if prev <= t and t < prev + minutes * 60 then
				addEvent("PowerHour", "PowerHour", prev + minutes * 60 - t, "Local", { Mult = 2 }, false)
			end
		end
	end
	task.defer(function()
		local ok, err = pcall(publishAnchors)
		if not ok then
			logError("publishAnchors", err)
		end
	end)
	Scheduler.Every("EventTick", 1, tickSecond)
	Scheduler.Every("EventRain", 4, rainTick)
end

-- Ein Name, zwei Rollen: Der Vertrag (§C5.10) nennt die Event-API "EventService.Start(kind, args, scope, by)", der Loader
-- (Main.server, §C2) ruft "Service.Start()" ohne Argumente als Lebenszyklus. Ohne Argumente = einmaliger Boot,
-- mit Event-Art = Event starten. Ein zweiter Aufruf ohne Argumente startet nichts doppelt.
local booted = false

function EventService.Start(
	kind: string?,
	args: { [string]: any }?,
	scope: ("Local" | "Global")?,
	by: Player?
): (boolean, string)
	if kind == nil and args == nil then
		if booted then
			return false, "admin.evUnknown"
		end
		booted = true
		boot()
		return true, ""
	end
	if type(kind) ~= "string" then
		return false, "admin.evUnknown"
	end
	return startEvent(
		kind,
		if type(args) == "table" then args else {},
		if scope == "Global" then "Global" else "Local",
		by
	)
end

return EventService
