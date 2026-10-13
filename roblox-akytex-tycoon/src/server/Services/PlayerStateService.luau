-- =====================================================================
--  AKYTEX TYCOON – Spieler-Zustand, Anfragen, Nachrichten (Server/Services/PlayerStateService)
--  Besitzer: WP1 (Kern & Plattform). Vertrag: DESIGN.md §C5.2 + §C8 + §C9 + §C10 (CC-Kopie 1:1, REUSE §3.10):
--  Request-Verteiler mit Remote-Hygiene, Ready-Gate, State-Flush über eine Schnappschuss-Liste, "Sticky"-Schlüssel
--  + voller State alle 20 s, Leaderstats "Vermögen" (StringValue) + "Etagen" (IntValue).
--
--  Öffentliche API:
--    PlayerStateService.Handle(action, fn(p, arg) -> Reply, opts?)
--        opts { Rate?, Per?, Bucket = { Kapazität, Nachfüllen/s }?, NeedsReady? } – Std: 8 Aufrufe / 1 s, NeedsReady = true.
--        Ablauf je Aufruf (Muss-Regel 10): p.Parent == Players -> globales Limit (Config.Security.Rates.Request)
--        -> Aktionsname -> Aktions-Limit (RateLimiter bzw. Token-Bucket) -> Ready-Gate -> pcall(fn) -> {Ok, Message?, …}.
--        Typ-/Schlüssel-/IsFinite-/Klemm-Prüfung der Argumente macht der Handler des Besitzer-WPs.
--    PlayerStateService.Provide(key, fn(p) -> any)    State-Schlüssel (§C10; nie yielden, nie nil für "leer")
--    PlayerStateService.MarkDirty(p, ...keys)         ohne keys = voller State; Flush alle 0,2 s, voll alle 20 s
--    PlayerStateService.Notify(p, langKey, args?, kind?)          lokalisiert pro Empfänger
--    PlayerStateService.NotifyAll(langKey, args?, kind?, filter?)
--    PlayerStateService.NotifyRaw(p, text, kind?)                 Text ist schon lokalisiert/gefiltert (≤ 500 Zeichen)
--    PlayerStateService.Effect(p, name, strength, data?)          Name aus §C7.4
--    PlayerStateService.EffectAll(name, strength, data?, filter?)
--    PlayerStateService.IsReady(p): boolean
--    PlayerStateService.OnReady(cb(p))                nach Profil + LoadPasses + gestarteter Policy-Anfrage
--    PlayerStateService.LangOf(p): "de" | "en"        Einstellung Settings.Lang, sonst LocaleId
--    PlayerStateService.SetLeaderstat(p, "Vermögen" | "Etagen", value: number | string)
--  Eigene Request-Aktionen: "GetFull" (1/5 s), "SaveSettings" (2/s), "TutorialFlag" { Flag } (2/s).
--  Eigene State-Schlüssel: Settings, Flags, Server = { Version, Studio, NoSave, LocalMarket }.
--  Player-Attribut "PingMs" alle Config.Tech.PingAttrEvery (2) Sekunden.
-- =====================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Lang = require(Shared:WaitForChild("Lang"))
local Types = require(Shared:WaitForChild("Types"))
local Format = require(Shared:WaitForChild("Format"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local PlayerStateService = {}
local Services: any = nil

type Reply = Types.Reply
type Limit = { Check: (key: any) -> boolean, Clear: (key: any) -> () }
type Handler = {
	Fn: (Player, any) -> Reply,
	Limiter: Limit,
	NeedsReady: boolean,
}

local MAX_ACTION_LEN = 40
local MAX_ARGS = 16
local MAX_SETTINGS_KEYS = 64
local MAX_TEXT = 500
local MAX_LEADER_TEXT = 40
local MAX_MONEY = 9e15
local ERROR_LOG_EVERY = 10
local NOTIFY_DELAY = 2 -- Studio-Hinweis kurz nach dem Beitritt (Client-UI steht dann)

local TECH = Config.Tech
local FLUSH_EVERY = math.max(0.2, tonumber(TECH.StateFlush) or 0.2) -- nie öfter als 5×/s
local FULL_EVERY = math.max(1, tonumber(TECH.FullStateEvery) or 20)
local PING_EVERY = math.max(0.5, tonumber(TECH.PingAttrEvery) or 2)

local function rateFromConfig(name: string, fallbackCalls: number, fallbackPer: number): (number, number)
	local security = Config.Security
	local rates = type(security) == "table" and security.Rates or nil
	local entry = type(rates) == "table" and rates[name] or nil
	if type(entry) == "table" and Util.IsFinite(entry[1]) and Util.IsFinite(entry[2]) and entry[1] >= 1 then
		return entry[1], math.max(0.05, entry[2])
	end
	return fallbackCalls, fallbackPer
end

local requestCalls, requestPer = rateFromConfig("Request", 8, 1)
local requestLimiter = Util.RateLimiter(requestCalls, requestPer)

local handlers: { [string]: Handler } = {}
local providers: { [string]: (Player) -> any } = {}
local providerOrder: { string } = {}

-- Pro-Spieler-Tabellen (alle werden bei PlayerRemoving geleert)
local readyPlayers: { [Player]: boolean } = {}
local setupStarted: { [Player]: boolean } = {}
local dirtyKeys: { [Player]: { [string]: boolean } } = {}
local dirtyFull: { [Player]: boolean } = {}
local fullAt: { [Player]: number } = {}
local pingSent: { [Player]: number } = {}
local funnelLogged: { [Player]: { [string]: boolean } } = {}

local readyCallbacks: { (Player) -> () } = {}
local errorAt: { [string]: number } = {}

-- ---------------------------------------------------------------------
-- 1) HELFER
-- ---------------------------------------------------------------------
local function isPlayer(p: any): boolean
	return typeof(p) == "Instance" and p:IsA("Player") and p.Parent == Players
end

-- Fehler höchstens alle 10 s pro Quelle loggen (Exploiter dürfen den Output nicht fluten)
local function logError(source: string, err: any)
	local now = os.clock()
	if now - (errorAt[source] or -math.huge) >= ERROR_LOG_EVERY then
		errorAt[source] = now
		warn(("[PlayerStateService] %s: %s"):format(source, tostring(err)))
	end
end

-- Optionaler Dienst (zur Laufzeit, nil-sicher)
local function service(name: string): any
	return if Services then Services[name] else nil
end

local function dataOf(p: Player): Types.PlayerData?
	local dataService = service("DataService")
	if not dataService then
		return nil
	end
	return dataService.Get(p)
end

local function validKind(kind: any): Types.NotifyKind
	if
		kind == "Info"
		or kind == "Success"
		or kind == "Error"
		or kind == "Event"
		or kind == "Alarm"
		or kind == "Announce"
	then
		return kind
	end
	return "Info"
end

function PlayerStateService.LangOf(p: Player): Types.Lang
	local data = dataOf(p)
	local settings = data and data.Settings
	local override = if type(settings) == "table" and type(settings.Lang) == "string" then settings.Lang else nil
	return Lang.For(p, override)
end

local function localize(p: Player, key: string, args: { any }?): string
	local lang = PlayerStateService.LangOf(p)
	if type(args) == "table" then
		local count = math.min(#args, MAX_ARGS)
		return Lang.T(lang, key, table.unpack(args, 1, count))
	end
	return Lang.T(lang, key)
end

local function fail(p: Player, key: string): Reply
	return { Ok = false, Message = localize(p, key) }
end

local function metrics(fnName: string, ...: any)
	local metricsService = service("MetricsService")
	local fn = metricsService and metricsService[fnName]
	if type(fn) == "function" then
		local ok, err = pcall(fn, ...)
		if not ok then
			logError("MetricsService." .. fnName, err)
		end
	end
end

-- ---------------------------------------------------------------------
-- 2) NACHRICHTEN & EFFEKTE
-- ---------------------------------------------------------------------
function PlayerStateService.NotifyRaw(p: Player, text: string, kind: Types.NotifyKind?)
	if not isPlayer(p) or type(text) ~= "string" or text == "" then
		return
	end
	Remotes.Notify:FireClient(p, string.sub(text, 1, MAX_TEXT), validKind(kind))
end

function PlayerStateService.Notify(p: Player, key: string, args: { any }?, kind: Types.NotifyKind?)
	if not isPlayer(p) or type(key) ~= "string" then
		return
	end
	PlayerStateService.NotifyRaw(p, localize(p, key, args), kind)
end

local function passes(filter: ((Player) -> boolean)?, p: Player): boolean
	if filter == nil then
		return true
	end
	local ok, result = pcall(filter, p)
	if not ok then
		logError("Filter", result)
		return false
	end
	return result == true
end

function PlayerStateService.NotifyAll(
	key: string,
	args: { any }?,
	kind: Types.NotifyKind?,
	filter: ((Player) -> boolean)?
)
	for _, p in ipairs(Players:GetPlayers()) do
		if passes(filter, p) then
			PlayerStateService.Notify(p, key, args, kind)
		end
	end
end

function PlayerStateService.Effect(p: Player, name: string, strength: number, data: any?)
	if not isPlayer(p) or type(name) ~= "string" or name == "" then
		return
	end
	Remotes.Effect:FireClient(p, name, if Util.IsFinite(strength) then strength else 1, data)
end

function PlayerStateService.EffectAll(name: string, strength: number, data: any?, filter: ((Player) -> boolean)?)
	if type(name) ~= "string" or name == "" then
		return
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if passes(filter, p) then
			PlayerStateService.Effect(p, name, strength, data)
		end
	end
end

-- ---------------------------------------------------------------------
-- 3) LEADERSTATS (Spielerliste): "Vermögen" als Text (Zahlen bis 9e15 lesbar), "Etagen" als Ganzzahl
-- ---------------------------------------------------------------------
local LEADERSTATS: { { Name: string, Class: string } } = {
	{ Name = "Vermögen", Class = "StringValue" },
	{ Name = "Etagen", Class = "IntValue" },
}

local function ensureStat(folder: Instance, name: string, className: string): Instance
	local stat = folder:FindFirstChild(name)
	if stat and stat.ClassName == className then
		return stat
	elseif stat then
		stat:Destroy()
	end
	local created = Instance.new(className)
	created.Name = name
	if created:IsA("StringValue") then
		created.Value = "0"
	end
	created.Parent = folder
	return created
end

local function ensureLeaderstats(p: Player): Instance
	local folder = p:FindFirstChild("leaderstats")
	if not (folder and folder:IsA("Folder")) then
		if folder then
			folder:Destroy()
		end
		local created = Instance.new("Folder")
		created.Name = "leaderstats"
		folder = created
	end
	for _, spec in ipairs(LEADERSTATS) do
		ensureStat(folder :: Instance, spec.Name, spec.Class)
	end
	if (folder :: Instance).Parent ~= p then
		(folder :: Instance).Parent = p
	end
	return folder :: Instance
end

function PlayerStateService.SetLeaderstat(p: Player, name: "Vermögen" | "Etagen", value: number | string)
	if not isPlayer(p) then
		return
	end
	local folder = ensureLeaderstats(p)
	if name == "Vermögen" then
		local text: string
		if type(value) == "string" then
			text = string.sub(value, 1, MAX_LEADER_TEXT)
		elseif Util.IsFinite(value) then
			-- eine Anzeige für alle Betrachter -> neutrale Kurzform (1.25M, MAX ab 9e15)
			text = Format.Credits(math.clamp(value :: number, 0, MAX_MONEY), "en")
		else
			return
		end
		local stat = ensureStat(folder, name, "StringValue") :: StringValue
		if stat.Value ~= text then
			stat.Value = text
		end
	elseif name == "Etagen" then
		local number = if type(value) == "string" then tonumber(value) else value
		if not Util.IsFinite(number) then
			return
		end
		local stat = ensureStat(folder, name, "IntValue") :: IntValue
		local clean = math.clamp(math.floor(number :: number), 0, 2 ^ 52)
		if stat.Value ~= clean then
			stat.Value = clean
		end
	end
end

-- ---------------------------------------------------------------------
-- 4) STATE (Provide / MarkDirty / Flush)
-- ---------------------------------------------------------------------
function PlayerStateService.Provide(key: string, fn: (p: Player) -> any)
	if type(key) ~= "string" or key == "" or type(fn) ~= "function" then
		warn("[PlayerStateService] Provide: Schlüssel (string) und Funktion erwartet")
		return
	end
	if providers[key] == nil then
		table.insert(providerOrder, key)
	else
		warn("[PlayerStateService] State-Schlüssel " .. key .. " wird ersetzt")
	end
	providers[key] = fn
end

function PlayerStateService.MarkDirty(p: Player, ...: string)
	if not isPlayer(p) then
		return
	end
	local count = select("#", ...)
	if count == 0 then
		dirtyFull[p] = true
		return
	end
	local set = dirtyKeys[p]
	if not set then
		set = {}
		dirtyKeys[p] = set
	end
	for i = 1, count do
		local key = select(i, ...)
		if type(key) == "string" then
			set[key] = true
		end
	end
end

local function compute(p: Player, key: string): (boolean, any)
	local provider = providers[key]
	if not provider then
		return false, nil
	end
	local ok, value = pcall(provider, p)
	if not ok then
		logError("State-Schlüssel " .. key, value)
		return false, nil
	end
	return true, value
end

local function buildFull(p: Player): { [string]: any }
	local state: { [string]: any } = {}
	for _, key in ipairs(providerOrder) do
		local ok, value = compute(p, key)
		if ok and value ~= nil then
			state[key] = value
		end
	end
	return state
end

local function flushPlayer(p: Player, now: number)
	local full = dirtyFull[p] == true or now - (fullAt[p] or -math.huge) >= FULL_EVERY
	if full then
		fullAt[p] = now
		dirtyFull[p] = nil
		dirtyKeys[p] = nil
		Remotes.State:FireClient(p, buildFull(p), true)
		return
	end
	local keys = dirtyKeys[p]
	if not keys then
		return
	end
	dirtyKeys[p] = nil
	local partial: { [string]: any } = {}
	local any = false
	for key in pairs(keys) do
		local ok, value = compute(p, key)
		if ok and value ~= nil then
			partial[key] = value
			any = true
		end
	end
	if any then
		Remotes.State:FireClient(p, partial, false)
	end
end

-- Schnappschuss-Liste: Provider dürfen MarkDirty aufrufen, ohne die Iteration zu stören
local flushList: { Player } = {}
local function flushAll()
	local now = os.clock()
	table.clear(flushList)
	for p in pairs(readyPlayers) do
		table.insert(flushList, p)
	end
	for _, p in ipairs(flushList) do
		if readyPlayers[p] and p.Parent == Players then
			local ok, err = pcall(flushPlayer, p, now)
			if not ok then
				logError("State an " .. p.Name, err)
			end
		end
	end
	-- Reste von Spielern, die schon weg sind (z. B. MarkDirty nach PlayerRemoving), aufräumen
	for p in pairs(dirtyKeys) do
		if p.Parent ~= Players then
			dirtyKeys[p] = nil
		end
	end
	for p in pairs(dirtyFull) do
		if p.Parent ~= Players then
			dirtyFull[p] = nil
		end
	end
end

local function updatePings()
	for _, p in ipairs(Players:GetPlayers()) do
		local ok, ping = pcall(function()
			return p:GetNetworkPing()
		end)
		if ok and Util.IsFinite(ping) then
			local ms = math.clamp(math.floor(ping * 1000 + 0.5), 0, 99999)
			if pingSent[p] ~= ms then
				pingSent[p] = ms
				p:SetAttribute("PingMs", ms)
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- 5) EINSTELLUNGEN (Schema Config.Client.SettingsSchema)
-- ---------------------------------------------------------------------
local function settingsSpec(): ({ [string]: any }, { [string]: any })
	local client = Config.Client
	local defaults = if type(client) == "table" and type(client.DefaultSettings) == "table"
		then client.DefaultSettings
		else {}
	local schema = if type(client) == "table" and type(client.SettingsSchema) == "table"
		then client.SettingsSchema
		else {}
	return defaults, schema
end

-- Schema-Eintrag zu einem Schlüssel. Verschachtelte Einstellungen (z. B. Indicators) dürfen als
-- { Type = "table", Fields = {…} }, als Tabelle von Einträgen oder als "Key.Feld"-Schlüssel stehen.
local function entryFor(schema: { [string]: any }, key: string): any
	local entry = schema[key]
	if type(entry) == "table" then
		if entry.Type ~= nil or type(entry.Fields) == "table" then
			return entry
		end
		-- Tabelle aus Feld-Einträgen ohne eigenen Typ
		local fields: { [string]: any } = {}
		local found = false
		for field, sub in pairs(entry) do
			if type(field) == "string" and type(sub) == "table" and sub.Type ~= nil then
				fields[field] = sub
				found = true
			end
		end
		return if found then { Type = "table", Fields = fields } else nil
	end
	-- "Key.Feld"-Schreibweise
	local prefix = key .. "."
	local fields: { [string]: any } = {}
	local found = false
	for name, sub in pairs(schema) do
		if type(name) == "string" and string.sub(name, 1, #prefix) == prefix and type(sub) == "table" then
			fields[string.sub(name, #prefix + 1)] = sub
			found = true
		end
	end
	return if found then { Type = "table", Fields = fields } else nil
end

-- Prüft/klemmt einen Wert. base = bisheriger Wert (für verschachtelte Tabellen: nur geänderte Felder).
local function checkValue(entry: any, value: any, base: any, depth: number): (boolean, any)
	if type(entry) ~= "table" or depth > 3 then
		return false, nil
	end
	local kind = entry.Type
	if kind == "number" then
		if not Util.IsFinite(value) then
			return false, nil
		end
		local v = value
		local step = entry.Step
		if Util.IsFinite(step) and step > 0 then
			v = math.floor(v / step + 0.5) * step
		end
		if entry.Integer == true then
			v = math.floor(v + 0.5)
		end
		if Util.IsFinite(entry.Min) then
			v = math.max(v, entry.Min)
		end
		if Util.IsFinite(entry.Max) then
			v = math.min(v, entry.Max)
		end
		return true, v
	elseif kind == "boolean" then
		return type(value) == "boolean", value
	elseif kind == "enum" then
		local options = entry.Options
		if type(options) ~= "table" then
			return false, nil
		end
		for _, option in ipairs(options) do
			if option == value then
				return true, value
			end
		end
		return false, nil
	elseif kind == "string" then
		if type(value) ~= "string" then
			return false, nil
		end
		local maxLen = if Util.IsFinite(entry.MaxLen) then math.max(0, entry.MaxLen) else 32
		return true, string.sub(value, 1, maxLen)
	elseif kind == "table" or type(entry.Fields) == "table" then
		local fields = entry.Fields
		if type(value) ~= "table" or type(fields) ~= "table" then
			return false, nil
		end
		local clean: { [string]: any } = if type(base) == "table" then Util.DeepCopy(base) else {}
		local any = false
		for field, fieldEntry in pairs(fields) do
			local fieldValue = value[field]
			if fieldValue ~= nil then
				local ok, cleanValue = checkValue(fieldEntry, fieldValue, clean[field], depth + 1)
				if ok then
					clean[field] = cleanValue
					any = true
				end
			end
		end
		return any, clean
	end
	return false, nil
end

-- Beim Laden: kaputte Werte auf Standard, unbekannte Schlüssel weg (nur wenn ein Schema existiert)
local function sanitizeSettings(data: Types.PlayerData)
	local defaults, schema = settingsSpec()
	if next(defaults) == nil then
		return
	end
	if type(data.Settings) ~= "table" then
		data.Settings = Util.DeepCopy(defaults)
		return
	end
	local settings = data.Settings
	for _, key in ipairs(Util.Snapshot(settings)) do
		local default = defaults[key]
		local value = settings[key]
		if type(key) ~= "string" or (default == nil and schema[key] == nil) then
			settings[key] = nil
		else
			local entry = entryFor(schema, key)
			if entry then
				local ok, clean = checkValue(entry, value, default, 1)
				if ok then
					settings[key] = clean
				else
					settings[key] = Util.DeepCopy(default)
				end
			elseif default ~= nil and type(value) ~= type(default) then
				settings[key] = Util.DeepCopy(default)
			end
		end
	end
	Util.Reconcile(settings, defaults)
end

-- ---------------------------------------------------------------------
-- 6) ANFRAGEN (Request.OnServerInvoke)
-- ---------------------------------------------------------------------
function PlayerStateService.Handle(
	action: string,
	fn: (p: Player, arg: any) -> Types.Reply,
	opts: { Rate: number?, Per: number?, Bucket: { number }?, NeedsReady: boolean? }?
)
	if type(action) ~= "string" or action == "" or #action > MAX_ACTION_LEN or type(fn) ~= "function" then
		warn("[PlayerStateService] Handle: Aktionsname (1–40 Zeichen) und Funktion erwartet")
		return
	end
	if not string.match(action, "^%a+$") then
		warn("[PlayerStateService] Handle: Aktionsnamen nur aus Buchstaben (§C9): " .. action)
	end
	local options = opts or {}
	local limiter: Limit
	local bucket = options.Bucket
	if type(bucket) == "table" and Util.IsFinite(bucket[1]) and Util.IsFinite(bucket[2]) and bucket[1] >= 1 then
		-- Token-Bucket { Kapazität, Nachfüllen/s } (z. B. TradePlace B 6/1,5)
		local tokens = Util.TokenBucket(bucket[1], math.max(0, bucket[2]))
		limiter = {
			Check = function(key: any): boolean
				return tokens.Take(key, 1)
			end,
			Clear = tokens.Clear,
		}
	else
		local rate = if Util.IsFinite(options.Rate) and (options.Rate :: number) >= 1 then options.Rate :: number else 8
		local per = if Util.IsFinite(options.Per) and (options.Per :: number) > 0 then options.Per :: number else 1
		local window = Util.RateLimiter(rate, per)
		limiter = { Check = window.Check, Clear = window.Clear }
	end
	if handlers[action] then
		warn("[PlayerStateService] Aktion " .. action .. " wird ersetzt")
	end
	handlers[action] = {
		Fn = fn,
		Limiter = limiter,
		NeedsReady = options.NeedsReady ~= false,
	}
end

local function normalize(result: any): Reply
	if type(result) ~= "table" then
		return { Ok = result == true }
	end
	result.Ok = result.Ok == true
	if result.Message ~= nil and type(result.Message) ~= "string" then
		result.Message = tostring(result.Message)
	end
	return result
end

-- Reihenfolge (Muss-Regel 10): p.Parent -> globales Limit -> Aktion -> Aktions-Limit -> Ready -> pcall -> Tabelle
local function dispatch(p: Player, action: any, arg: any): Reply
	if p.Parent ~= Players then
		return { Ok = false } -- schon gegangen: keine Limiter-Einträge mehr anlegen (PlayerRemoving hat aufgeräumt)
	end
	if not requestLimiter.Check(p) then
		return fail(p, "core.tooFast")
	end
	if type(action) ~= "string" or #action == 0 or #action > MAX_ACTION_LEN then
		return fail(p, "core.unknownAction")
	end
	local handler = handlers[action]
	if not handler then
		return fail(p, "core.unknownAction")
	end
	if not handler.Limiter.Check(p) then
		return fail(p, "core.tooFast")
	end
	if handler.NeedsReady and not readyPlayers[p] then
		return fail(p, "core.loading")
	end
	local ok, result = pcall(handler.Fn, p, arg)
	if not ok then
		logError("Aktion " .. action, result)
		return fail(p, "core.error")
	end
	return normalize(result)
end

-- Eigene Aktionen ------------------------------------------------------
-- Tutorial-/Hinweis-Flags, die NUR der Client kennt (Ladebildschirm, Kamera-Anflug, gesehene Fenster).
-- Funnel: Schritte, die nur der Client erlebt (§B2), werden hier geloggt (MetricsService dedupliziert je Sitzung).
local TUTORIAL_FLAGS: { [string]: any } = { -- true = nur Flag, { Step, Name } = Flag + Funnel-Schritt
	SplashDone = { Step = 2, Name = "SplashDone" },
	FlyInDone = { Step = 3, Name = "Spawned" },
	Welcome = true,
	Done = true,
	Skipped = true,
	DisclaimerSeen = true,
	TerminalSeen = true,
	TowerSeen = true,
	ShopSeen = true,
	SettingsSeen = true,
	CalendarSeen = true,
	FavoritePrompted = { Step = 16, Name = "FavoritePrompted" },
}

local function handleGetFull(p: Player, _arg: any): Reply
	return { Ok = true, State = buildFull(p) }
end

local function handleSaveSettings(p: Player, arg: any): Reply
	if type(arg) ~= "table" then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	if type(data.Settings) ~= "table" then
		data.Settings = {}
	end
	local settings = data.Settings
	local _, schema = settingsSpec()
	local changed = 0
	local seen = 0
	for key, value in pairs(arg) do
		seen += 1
		if seen > MAX_SETTINGS_KEYS then
			break
		end
		if type(key) == "string" and #key <= MAX_ACTION_LEN then
			local entry = entryFor(schema, key)
			if entry then
				local ok, clean = checkValue(entry, value, settings[key], 1)
				if ok then
					settings[key] = clean
					changed += 1
				end
			end
		end
	end
	if changed == 0 then
		return fail(p, "core.invalid")
	end
	PlayerStateService.MarkDirty(p, "Settings")
	return { Ok = true }
end

local function handleTutorialFlag(p: Player, arg: any): Reply
	-- exakte Schlüssel: { Flag = string }
	if type(arg) ~= "table" or type(arg.Flag) ~= "string" or #arg.Flag > MAX_ACTION_LEN then
		return fail(p, "core.invalid")
	end
	for key in pairs(arg) do
		if key ~= "Flag" then
			return fail(p, "core.invalid")
		end
	end
	local flag = arg.Flag
	local spec = TUTORIAL_FLAGS[flag]
	if spec == nil then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	if type(data.Flags) ~= "table" then
		data.Flags = {}
	end
	local flags = data.Flags
	local first = flags[flag] ~= true
	flags[flag] = true
	if flag == "Done" or flag == "Skipped" then
		flags.Done = true
		flags.Tutorial = true -- CC-Kompatibilität: "Tutorial abgeschlossen"
	end
	if type(spec) == "table" then
		local logged = funnelLogged[p]
		if not logged then
			logged = {}
			funnelLogged[p] = logged
		end
		if not logged[flag] then
			logged[flag] = true
			metrics("Funnel", p, spec.Step, spec.Name)
		end
	end
	if first and flag == "Skipped" then
		metrics("Custom", p, "TutorialSkipped", 1, nil)
	end
	PlayerStateService.MarkDirty(p, "Flags")
	return { Ok = true }
end

-- ---------------------------------------------------------------------
-- 7) READY-GATE: Profil geladen -> Pässe geprüft -> Policy-Anfrage gestartet -> bereit
-- ---------------------------------------------------------------------
function PlayerStateService.IsReady(p: Player): boolean
	return readyPlayers[p] == true
end

local function runReady(callback: (Player) -> (), p: Player)
	local ok, err = xpcall(callback, debug.traceback, p)
	if not ok then
		warn("[PlayerStateService] OnReady-Callback Fehler: " .. tostring(err))
	end
end

function PlayerStateService.OnReady(callback: (p: Player) -> ())
	if type(callback) ~= "function" then
		return
	end
	table.insert(readyCallbacks, callback)
	-- später registriert: schon bereite Spieler nachreichen
	for p in pairs(readyPlayers) do
		task.spawn(runReady, callback, p)
	end
end

-- Startwerte der Spielerliste (Vermögen kommt danach laufend von ProgressionService, WP9)
local function initialLeaderstats(p: Player, data: Types.PlayerData)
	local tower = data.Tower
	local floors = if type(tower) == "table" and type(tower.Floors) == "table" then #tower.Floors else 0
	PlayerStateService.SetLeaderstat(p, "Etagen", floors)
	local wealth = if Util.IsFinite(data.Credits) then data.Credits else 0
	local progression = service("ProgressionService")
	if progression and type(progression.Wealth) == "function" then
		local ok, value = pcall(progression.Wealth, p)
		if ok and Util.IsFinite(value) then
			wealth = value
		end
	end
	PlayerStateService.SetLeaderstat(p, "Vermögen", wealth)
end

local function onProfileLoaded(p: Player, data: Types.PlayerData)
	if setupStarted[p] or p.Parent ~= Players then
		return
	end
	setupStarted[p] = true

	-- Spielerliste
	ensureLeaderstats(p)
	local okStats, errStats = pcall(initialLeaderstats, p, data)
	if not okStats then
		logError("Leaderstats", errStats)
	end

	-- Einstellungen reparieren (Schema kann sich seit dem letzten Besuch geändert haben)
	local okSettings, errSettings = pcall(sanitizeSettings, data)
	if not okSettings then
		logError("Einstellungen", errSettings)
	end

	-- Gamepässe prüfen (yieldet, 3 Versuche) und Policy-Anfrage starten (MonetizationService, WP10)
	local monetization = service("MonetizationService")
	if monetization then
		if type(monetization.LoadPasses) == "function" then
			local ok, err = pcall(monetization.LoadPasses, p)
			if not ok then
				logError("MonetizationService.LoadPasses", err)
			end
		end
		if type(monetization.RandomAllowed) == "function" then
			task.spawn(function()
				local ok, err = pcall(monetization.RandomAllowed, p)
				if not ok then
					logError("MonetizationService.RandomAllowed", err)
				end
			end)
		end
	end

	local dataService = service("DataService")
	if p.Parent ~= Players or not dataService or dataService.Get(p) ~= data then
		return -- inzwischen gegangen
	end
	readyPlayers[p] = true
	dirtyFull[p] = true -- voller State beim nächsten Flush (≤ 0,2 s)
	for _, callback in ipairs(readyCallbacks) do
		task.spawn(runReady, callback, p)
	end

	-- Studio: "Fortschritt wird nicht gespeichert"
	if dataService.IsNoSave(p) then
		local reason = if type(dataService.NoSaveReason) == "function" then dataService.NoSaveReason(p) else nil
		task.delay(NOTIFY_DELAY, function()
			if p.Parent == Players then
				PlayerStateService.Notify(p, "core.studioNoSave", nil, "Info")
				if reason == "NoApi" then
					PlayerStateService.Notify(p, "core.studioNoApi", nil, "Alarm")
				end
			end
		end)
	end
end

local function onPlayerRemoving(p: Player)
	readyPlayers[p] = nil
	setupStarted[p] = nil
	dirtyKeys[p] = nil
	dirtyFull[p] = nil
	fullAt[p] = nil
	pingSent[p] = nil
	funnelLogged[p] = nil
	requestLimiter.Clear(p)
	for _, handler in pairs(handlers) do
		handler.Limiter.Clear(p)
	end
end

-- ---------------------------------------------------------------------
-- 8) INIT / START
-- ---------------------------------------------------------------------
local function localMarket(): boolean
	local market = service("MarketService")
	if market and type(market.IsLocalMarket) == "function" then
		local ok, result = pcall(market.IsLocalMarket)
		return ok and result == true
	end
	return false
end

function PlayerStateService.Init(services: any)
	Services = services

	-- eigene State-Schlüssel (§C10)
	PlayerStateService.Provide("Settings", function(p: Player)
		local data = dataOf(p)
		return if data and type(data.Settings) == "table" then data.Settings else {}
	end)
	PlayerStateService.Provide("Flags", function(p: Player)
		local data = dataOf(p)
		return if data and type(data.Flags) == "table" then data.Flags else {}
	end)
	PlayerStateService.Provide("Server", function(p: Player)
		local dataService = service("DataService")
		return {
			Version = Config.Version,
			Studio = RunService:IsStudio(),
			NoSave = dataService ~= nil and dataService.IsNoSave(p) == true,
			LocalMarket = localMarket(),
		}
	end)

	-- eigene Aktionen (§C9)
	PlayerStateService.Handle("GetFull", handleGetFull, { Rate = 1, Per = 5 })
	PlayerStateService.Handle("SaveSettings", handleSaveSettings, { Rate = 2, Per = 1 })
	PlayerStateService.Handle("TutorialFlag", handleTutorialFlag, { Rate = 2, Per = 1 })
end

function PlayerStateService.Start()
	Remotes.Request.OnServerInvoke = function(p: Player, action: any, arg: any)
		local ok, result = pcall(dispatch, p, action, arg)
		if ok then
			return result
		end
		logError("Request", result)
		return { Ok = false, Message = Lang.T("en", "core.error") }
	end

	local dataService = service("DataService")
	if dataService then
		dataService.OnProfileLoaded(onProfileLoaded)
	else
		warn("[PlayerStateService] DataService fehlt – niemand wird bereit")
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	Scheduler.Every("StateFlush", 1 / FLUSH_EVERY, function()
		flushAll()
	end)
	Scheduler.Every("PingAttr", 1 / PING_EVERY, function()
		updatePings()
	end)
end

return PlayerStateService
