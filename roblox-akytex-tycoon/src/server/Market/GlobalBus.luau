--!strict
-- =====================================================================
--  AKYTEX TYCOON – Globaler Event-Bus für Markt-Admin-Events (Server/Market/GlobalBus)
--  Besitzer: WP3 (Markt-Engine). Vertrag: MARKET.md §8.2–§8.4, DESIGN.md §C13, §B15.3, §C19 Nr. 10.
--  Wahrheit:   MemoryStore SortedMap "AT_Bus_W<w>" (Config.Tech.BusMapPrefix), Schlüssel "%012d_<guid>" (Aktivierungs-
--              Tick), Ablauf 26 h. Ein Event gilt nur, wenn es dort steht (Schreiben scheitert -> Event abgebrochen).
--  Schnellweg: MessagingService-Thema Config.Tech.BusTopic ("AT_EV"), Nachricht = nur der Schlüssel.
--  Poll:       jeder Server liest alle 5 s GetRangeAsync(aufsteigend, 50, ab min(letzter Schlüssel, jetzt − 30 s)) –
--              verlorene Nachrichten werden so nachgeholt. Vorlauf 10 s -> alle Server wenden das Event im SELBEN Tick an.
--  Audit:      DataStore Config.Tech.GlobalStore ("AT_Global"), Schlüssel AdminLog_W<w> (letzte 200 Einträge).
--  Jedes Feld wird validiert und geklemmt (auch Werte aus dem Speicher), obere Zeitgrenze, Dedupe per Id (200).
--  Studio ohne API / lokaler Testmarkt: Publish wendet lokal an (Bus nur lokal, §C17).
--  Alle MemoryStore/Messaging/DataStore-Aufrufe in pcall; Publish/Poll/Start YIELDEN (eigene Threads).
--
--  Öffentliche API (nur WP3)
--    GlobalBus.Start(onEvent: (ev, late) -> (), opts: { Local: boolean, Now: () -> number })
--    GlobalBus.Publish(ev): (boolean, string?)        "ok" | "local" | Fehlertext
--    GlobalBus.Poll()                                   (MarketService ruft es alle 5 s in einem eigenen Thread)
--    GlobalBus.Validate(raw, nowTick): BusEvent?        GlobalBus.NewId(): string
--    GlobalBus.Ok(): boolean                            letzter Bus-Zugriff erfolgreich (Admin-Dashboard)
--    GlobalBus.LoadLog(w): { BusEvent }                 Admin-Log der Woche (Admin-Fenster älter als 26 h)
--    GlobalBus.Seen(id): boolean · GlobalBus.Stop()
-- =====================================================================

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MarketClock = require(script.Parent:WaitForChild("MarketClock"))

local GlobalBus = {}

export type BusEvent = {
	Id: string,
	Kind: string,
	Scope: string,
	Target: (number | string)?,
	Strength: number,
	Ramp: number,
	Decay: number,
	StartTick: number,
	Until: number,
	Text: { de: string, en: string }?,
	By: number,
	Warn: number?,
	Band: number?,
	Dir: number?,
}

local KINDS = {
	Crash = true,
	Rally = true,
	Pump = true,
	Dump = true,
	Halt = true,
	Resume = true,
	Ipo = true,
	News = true,
	Vol = true,
	Normalize = true,
	CancelAutoShow = true,
}
local SECTORS = { T = true, E = true, M = true, K = true, G = true, F = true }
local MAX_TEXT = 200 -- Bytes je Sprache (80 Zeichen UTF-8)

local handler: ((BusEvent, boolean) -> ())? = nil
local nowFn: () -> number = MarketClock.Tick
local localOnly = false
local busOk = true
local started = false
local polling = false
local lastKeys: { [number]: string } = {} -- je Woche der zuletzt gesehene Schlüssel
local seenIds: { [string]: boolean } = {}
local seenOrder: { string } = {}
local subscription: RBXScriptConnection? = nil

local function cfg(): { [string]: any }
	return (Config.Market :: any).Bus
end

local function tech(): { [string]: any }
	return Config.Tech :: any
end

function GlobalBus.Ok(): boolean
	return busOk
end

function GlobalBus.NewId(): string
	local ok, guid = pcall(function()
		return HttpService:GenerateGUID(false)
	end)
	local text = if ok and type(guid) == "string" then guid else tostring(os.clock()) .. tostring(math.random())
	return (string.gsub(text, "[^%w]", ""))
end

function GlobalBus.Seen(id: string): boolean
	return seenIds[id] == true
end

local function remember(id: string)
	if seenIds[id] then
		return
	end
	seenIds[id] = true
	table.insert(seenOrder, id)
	local limit = cfg().Dedupe or 200
	while #seenOrder > limit do
		local old = table.remove(seenOrder, 1)
		if old then
			seenIds[old] = nil
		end
	end
end

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function cleanText(text: any): string?
	if type(text) ~= "string" or text == "" then
		return nil
	end
	local cut = string.sub(text, 1, MAX_TEXT)
	-- abgeschnittene UTF-8-Folgen entfernen
	while #cut > 0 and utf8.len(cut) == nil do
		cut = string.sub(cut, 1, #cut - 1)
	end
	return if cut ~= "" then cut else nil
end

-- jedes Feld prüfen + klemmen; obere Zeitgrenze (Until ≤ jetzt + MaxSpan + Vorlauf + Puffer)
function GlobalBus.Validate(raw: any, nowTick: number): BusEvent?
	if type(raw) ~= "table" then
		return nil
	end
	local market: any = Config.Market
	local admin = market.Admin
	local bus = cfg()
	if type(raw.Id) ~= "string" or #raw.Id < 4 or #raw.Id > 64 or not string.match(raw.Id, "^[%w]+$") then
		return nil
	end
	if not KINDS[raw.Kind] then
		return nil
	end
	if not finite(raw.StartTick) or not finite(raw.Until) then
		return nil
	end
	local start = math.floor(raw.StartTick)
	local untilTick = math.floor(raw.Until)
	if start > nowTick + (bus.MaxFuture or 60) or start < nowTick - (bus.ExpirySeconds or 93600) then
		return nil
	end
	if untilTick < start or untilTick > start + admin.MaxSpan + admin.Lead + 5 then
		return nil
	end
	local scope = raw.Scope
	if scope ~= "All" and scope ~= "Sector" and scope ~= "Inst" then
		return nil
	end
	local target: (number | string)? = nil
	if scope == "Sector" then
		if type(raw.Target) ~= "string" or not SECTORS[raw.Target] then
			return nil
		end
		target = raw.Target
	elseif raw.Kind == "CancelAutoShow" then
		-- Ziel = Woche, deren Samstags-Show abgesagt wird
		if not finite(raw.Target) or raw.Target % 1 ~= 0 or raw.Target < 0 or raw.Target > 100000 then
			return nil
		end
		target = raw.Target
	elseif scope == "Inst" or raw.Kind == "Ipo" then
		if not finite(raw.Target) or raw.Target % 1 ~= 0 or raw.Target < 1 or raw.Target > 255 then
			return nil
		end
		target = raw.Target
	end
	local ev: BusEvent = {
		Id = raw.Id,
		Kind = raw.Kind,
		Scope = scope,
		Target = target,
		Strength = if finite(raw.Strength) then math.clamp(raw.Strength, 0, 5) else 0,
		Ramp = if finite(raw.Ramp) then math.clamp(math.floor(raw.Ramp), 1, admin.Ramp[2]) else admin.Ramp[1],
		Decay = if finite(raw.Decay) then math.clamp(math.floor(raw.Decay), 1, admin.Decay[2]) else admin.Decay[1],
		StartTick = start,
		Until = untilTick,
		Text = nil,
		By = if finite(raw.By) then math.floor(raw.By) else 0,
		Warn = if finite(raw.Warn) then math.clamp(math.floor(raw.Warn), 0, admin.WarnSeconds) else 0,
		Band = if finite(raw.Band) then math.clamp(math.floor(raw.Band), 1, 4) else nil,
		Dir = if finite(raw.Dir) then (if raw.Dir < 0 then -1 else 1) else nil,
	}
	if type(raw.Text) == "table" then
		local de, en = cleanText(raw.Text.de), cleanText(raw.Text.en)
		if de or en then
			ev.Text = { de = de or en or "", en = en or de or "" }
		end
	end
	-- Gesamtdauer (Warnung + Rampe + Abklingen) nie über MaxSpan
	if ev.Kind == "Crash" or ev.Kind == "Rally" or ev.Kind == "Pump" or ev.Kind == "Dump" then
		local span = (ev.Warn or 0) + ev.Ramp + ev.Decay
		if span > admin.MaxSpan then
			ev.Decay = math.max(1, admin.MaxSpan - (ev.Warn or 0) - ev.Ramp)
		end
	end
	return ev
end

local function mapName(week: number): string
	return (tech().BusMapPrefix or "AT_Bus_W") .. week
end

local function keyOf(ev: BusEvent): string
	return string.format("%012d_%s", ev.StartTick, ev.Id)
end

local function deliver(raw: any, source: string)
	local now = nowFn()
	local ev = GlobalBus.Validate(raw, now)
	if ev == nil or seenIds[ev.Id] then
		return
	end
	remember(ev.Id)
	local late = ev.StartTick <= now
	local fn = handler
	if fn then
		local ok, err = pcall(function(): any
			fn(ev, late)
			return nil
		end)
		if not ok then
			warn("[GlobalBus] Fehler beim Anwenden (" .. source .. "): " .. tostring(err))
		end
	end
end

-- ---------------------------------------------------------------------
-- LESEN (Poll + gezielt per Schlüssel)
-- ---------------------------------------------------------------------
local function readRange(week: number, fromKey: string?): (boolean, { any })
	local ok, result = pcall(function()
		local map = MemoryStoreService:GetSortedMap(mapName(week))
		return map:GetRangeAsync(Enum.SortDirection.Ascending, cfg().PageSize or 50, fromKey, nil)
	end)
	if not ok or type(result) ~= "table" then
		return false, {}
	end
	return true, result
end

-- Start: beim ersten Poll ab Horizont (26 h), danach ab min(letzter Schlüssel, jetzt − PollLookback). So werden auch
-- Events gefunden, deren Schlüssel kleiner ist als der zuletzt gesehene (zwei Server veröffentlichen fast gleichzeitig,
-- der frühere Start-Tick wird später geschrieben); Doppelte fängt die Id-Dedupe ab.
local function pollWeek(week: number, startKey: string, trailKey: string)
	local last = lastKeys[week]
	local key = if last == nil then startKey elseif last < trailKey then last else trailKey
	local pages = 0
	local allOk = true
	while pages < (cfg().MaxPages or 20) do
		pages += 1
		local ok, items = readRange(week, key)
		if not ok then
			allOk = false
			break
		end
		for _, entry in ipairs(items) do
			if type(entry) == "table" and type(entry.key) == "string" then
				key = entry.key
				deliver(entry.value, "poll")
			end
		end
		if #items < (cfg().PageSize or 50) then
			break
		end
	end
	if key then
		lastKeys[week] = key
	end
	busOk = allOk
end

function GlobalBus.Poll()
	if localOnly or polling then
		return
	end
	polling = true
	local now = nowFn()
	local week = MarketClock.WeekIndex(now)
	local horizon = now - (cfg().ExpirySeconds or 93600)
	local startKey = string.format("%012d", math.max(0, horizon))
	local trailKey = string.format("%012d", math.max(0, now - (cfg().PollLookback or 30)))
	local ok, err = pcall(function()
		if MarketClock.WeekIndex(horizon) < week then
			pollWeek(week - 1, startKey, trailKey)
		end
		pollWeek(week, startKey, trailKey)
	end)
	if not ok then
		busOk = false
		warn("[GlobalBus] Poll-Fehler: " .. tostring(err))
	end
	polling = false
end

local function fetchKey(key: string)
	local startTick = tonumber(string.sub(key, 1, 12))
	if startTick == nil then
		return
	end
	local ok, value = pcall(function()
		local map = MemoryStoreService:GetSortedMap(mapName(MarketClock.WeekIndex(startTick)))
		return map:GetAsync(key)
	end)
	if ok and value ~= nil then
		deliver(value, "messaging")
	end
end

-- ---------------------------------------------------------------------
-- START / VERÖFFENTLICHEN
-- ---------------------------------------------------------------------
function GlobalBus.Start(onEvent: (BusEvent, boolean) -> (), opts: { Local: boolean, Now: (() -> number)? })
	handler = onEvent
	localOnly = opts.Local == true
	if opts.Now then
		nowFn = opts.Now
	end
	if started then
		return
	end
	started = true
	if localOnly then
		return
	end
	local ok, conn = pcall(function()
		return MessagingService:SubscribeAsync(tech().BusTopic or "AT_EV", function(message: any)
			local data = if type(message) == "table" then message.Data else nil
			if type(data) == "string" and #data <= 100 and string.match(data, "^%d+_[%w]+$") then
				task.spawn(fetchKey, data)
			end
		end)
	end)
	if ok and conn then
		subscription = conn
	else
		busOk = false
		warn("[GlobalBus] Messaging-Abo fehlgeschlagen – nur Poll (" .. tostring(conn) .. ")")
	end
	GlobalBus.Poll()
end

function GlobalBus.Stop()
	if subscription then
		subscription:Disconnect()
		subscription = nil
	end
	started = false
end

local function appendLog(ev: BusEvent)
	pcall(function()
		local ds = DataStoreService:GetDataStore(tech().GlobalStore or "AT_Global")
		local week = MarketClock.WeekIndex(ev.StartTick)
		ds:UpdateAsync("AdminLog_W" .. week, function(old: any)
			local list = if type(old) == "table" then old else {}
			table.insert(list, ev)
			while #list > (cfg().LogMax or 200) do
				table.remove(list, 1)
			end
			return list
		end)
	end)
end

-- yieldet; Rückgabe (true, "ok") verteilt · (true, "local") nur lokal · (false, Grund) abgebrochen
function GlobalBus.Publish(ev: BusEvent): (boolean, string?)
	local now = nowFn()
	local clean = GlobalBus.Validate(ev, now)
	if clean == nil then
		return false, "invalid"
	end
	if localOnly then
		deliver(clean, "local")
		return true, "local"
	end
	local key = keyOf(clean)
	local okSet, errSet = pcall(function()
		local map = MemoryStoreService:GetSortedMap(mapName(MarketClock.WeekIndex(clean.StartTick)))
		map:SetAsync(key, clean, cfg().ExpirySeconds or 93600)
	end)
	if not okSet then
		busOk = false
		warn("[GlobalBus] Markt-Event nicht verteilt: " .. tostring(errSet))
		return false, "store"
	end
	busOk = true
	pcall(function()
		MessagingService:PublishAsync(tech().BusTopic or "AT_EV", key)
	end)
	deliver(clean, "publish") -- der eigene Server wendet sofort an (Poll/Messaging deduplizieren)
	task.spawn(appendLog, clean)
	return true, "ok"
end

function GlobalBus.LoadLog(week: number): { BusEvent }
	local out: { BusEvent } = {}
	if localOnly then
		return out
	end
	local ok, list = pcall(function()
		local ds = DataStoreService:GetDataStore(tech().GlobalStore or "AT_Global")
		return (ds:GetAsync("AdminLog_W" .. week))
	end)
	if not ok or type(list) ~= "table" then
		return out
	end
	local count = 0
	for _, raw in ipairs(list) do
		count += 1
		if count > (cfg().LogMax or 200) then
			break
		end
		-- Log-Einträge sind älter als der Bus: nur Form prüfen (Zeitgrenze relativ zum eigenen Start)
		if type(raw) == "table" and finite(raw.StartTick) then
			local ev = GlobalBus.Validate(raw, math.floor(raw.StartTick))
			if ev then
				table.insert(out, ev)
			end
		end
	end
	return out
end

return GlobalBus
