-- =====================================================================
--  CLUTCH CLASH – Live-Balance & Spiel-Statistik (Server/Services/BalanceService)
--  Besitzer: WP7 (Sicherheit, Admin, Live-Balance). Vertrag: DESIGN.md C5.7, C14, B25.3 (Reiter Balance/Statistik).
--
--  Live-Balance:
--    * Beim Boot aus CC_Live_v1 "Balance" laden ({Version, Weapons = {[key] = {[field] = value}}, Disabled}).
--    * Angewendet über Config.ApplyBalance (Server) + ReplicatedStorage.LiveBalance (StringValue, HttpService:JSONEncode)
--      -> jeder Client wendet denselben Stand an (WP10). Effect "Balance" {Version} an alle.
--    * Admin: SetField/ResetWeapon = Vorschau NUR auf diesem Server; Save = neue Version für alle Server
--      (UpdateAsync + MessagingService "CC_Global" {Kind = "Balance", Version}); Poll alle 120 s als Sicherheitsnetz.
--    * Verlauf der letzten 10 Versionen (CC_Live_v1 "BalanceHistory"), Revert = alte Version als neue Version speichern.
--    * Not-Aus (SetEnabled false): sofort für alle Server; Waffe verschwindet aus laufenden Loadouts.
--  Statistik (nicht aus Admin-Show-Matches = Tainted):
--    * Zähler pro Waffe/Map/Modus im Speicher, Flush alle 600 s in CC_Stats_v1 "S_<yyyymmdd>_<shard>" (UpdateAsync-Merge).
--    * Eigene Quellen: MatchService.OnMatchEnd (Pick, WinWith, Map, Mode, Matches, Bot-Anteil),
--      WeaponService.OnShot (Schüsse/Treffer/Kopftreffer), CombatService.OnElimination (Pops).
--      Wartezeit (QueueTime) und Kill/Head kommen über Stat() von QueueService/CombatService.
--
--  Öffentliche API (C5.7):
--    BalanceService.Stat(kind, key, n?)      kind "Pick" | "Kill" | "Head" | "WinWith" | "Map" | "Mode" | "QueueTime"
--    BalanceService.Version(): number
--  Zusatz (nur AdminService, Reiter Balance/Statistik – manche yielden):
--    BalanceService.GetBalance(): table                    {Version, Preview, Defaults, Overrides, Disabled, History, Fields, Weapons}
--    BalanceService.SetField(weapon, field, value): (boolean, number|string)
--    BalanceService.ResetWeapon(weapon): boolean
--    BalanceService.Save(by: Player?): (boolean, number, boolean)      ok, Version, nurLokal   (yieldet)
--    BalanceService.Revert(version, by): (boolean, number?)                                   (yieldet)
--    BalanceService.SetEnabled(weapon, on, by): (boolean, number?)                            (yieldet)
--    BalanceService.GetStats(days): table                                                    (yieldet)
-- =====================================================================

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))
local Util = require(Shared:WaitForChild("Util"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local BalanceService = {}
local Services: any = nil

local SEC: any = Config.Security
local LIVE_VALUE_NAME = "LiveBalance"
local HISTORY_CACHE_SECONDS = 30
local TAINT_CACHE_SECONDS = 2
local MAX_KEY_LEN = 40
local SLOTS: { Types.SlotName } = { "Primary", "Secondary", "Melee", "Utility" }

-- Öffentliche Statistik-Arten (C5.7) + interne Zähler
local PUBLIC_KINDS: { [string]: boolean } =
	{ Pick = true, Kill = true, Head = true, WinWith = true, Map = true, Mode = true, QueueTime = true }

type BalanceData = { Version: number, Weapons: { [string]: { [string]: number } }, Disabled: { [string]: boolean } }
type HistoryEntry = {
	Version: number,
	Weapons: { [string]: { [string]: number } },
	Disabled: { [string]: boolean },
	T: number,
	By: number,
	ByName: string,
}
type Counters = { [string]: { [string]: number } }

-- ---------------------------------------------------------------------
-- ZUSTAND
-- ---------------------------------------------------------------------
local saved: BalanceData = { Version = 0, Weapons = {}, Disabled = {} } -- letzter gespeicherter Stand
local working: BalanceData = { Version = 0, Weapons = {}, Disabled = {} } -- angewendeter Stand (inkl. Vorschau)
local preview = false
local lastBroadcastVersion = -1
local liveValue: StringValue? = nil

local liveStore: DataStore? = nil
local statsStore: DataStore? = nil
local storeDisabled = false
local storeWarned = false
local loading = false
local saving = false

local historyCache: { HistoryEntry }? = nil
local historyAt = -math.huge

local counters: Counters = {}
local flushing = false
local statsCache: { [number]: { T: number, Data: any } } = {}
local taintCache: { [string]: { T: number, Tainted: boolean } } = {}
local taintCacheSize = 0
local reloadPending = false
local shotSource = false -- WeaponService.OnShot angemeldet (Schüsse/Treffer/Kopf aus eigener Quelle)
local popSource = false -- CombatService.OnElimination angemeldet (Pops ohne Schießstand/Tainted)

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function call(name: string, fnName: string, ...: any): (boolean, ...any)
	local svc = if Services then Services[name] else nil
	local fn = if type(svc) == "table" then svc[fnName] else nil
	if type(fn) ~= "function" then
		return false
	end
	return pcall(fn, ...)
end

local function balanceFields(): { [string]: { number } }
	local fields = Config.Weapons and Config.Weapons.BalanceFields
	return if type(fields) == "table" then fields else {}
end

local function weaponList(): { any }
	local list = Config.Weapons and Config.Weapons.List
	return if type(list) == "table" then list else {}
end

local function baseDef(key: string): any
	for _, def in ipairs(weaponList()) do
		if type(def) == "table" and def.Key == key then
			return def
		end
	end
	return nil
end

-- Basiswert eines Felds ("Projectile.SplashMax" = verschachtelt) oder nil
local function baseValue(def: any, field: string): number?
	if type(def) ~= "table" then
		return nil
	end
	local dot = string.find(field, ".", 1, true)
	local value: any
	if dot then
		local nested = def[string.sub(field, 1, dot - 1)]
		value = if type(nested) == "table" then nested[string.sub(field, dot + 1)] else nil
	else
		value = def[field]
	end
	return if Util.IsFinite(value) then value else nil
end

local function boundsOf(field: string): (number?, number?)
	local b = balanceFields()[field]
	if type(b) ~= "table" or not Util.IsFinite(b[1]) or not Util.IsFinite(b[2]) or b[1] > b[2] then
		return nil, nil
	end
	return b[1], b[2]
end

local function realDay(): number
	return math.floor(os.time() / 86400)
end

local function dateKey(day: number): string
	return os.date("!%Y%m%d", day * 86400) :: string
end

local function shardCount(): number
	return math.max(1, math.floor(tonumber(Config.Tech.Shards) or 8))
end

local function shard(): number
	return Util.Hash(game.JobId) % shardCount()
end

-- Stand säubern (alles, was aus dem DataStore oder vom Netz kommt)
local function clean(raw: any): BalanceData
	local out: BalanceData = { Version = 0, Weapons = {}, Disabled = {} }
	if type(raw) ~= "table" then
		return out
	end
	if Util.IsFinite(raw.Version) and raw.Version >= 0 then
		out.Version = math.floor(raw.Version)
	end
	if type(raw.Weapons) == "table" then
		for key, fields in pairs(raw.Weapons) do
			if type(key) == "string" and baseDef(key) and type(fields) == "table" then
				local entry: { [string]: number } = {}
				local any = false
				for field, value in pairs(fields) do
					local lo, hi = boundsOf(if type(field) == "string" then field else "")
					if lo and hi and Util.IsFinite(value) then
						entry[field] = math.clamp(value, lo, hi)
						any = true
					end
				end
				if any then
					out.Weapons[key] = entry
				end
			end
		end
	end
	if type(raw.Disabled) == "table" then
		for key, flag in pairs(raw.Disabled) do
			if type(key) == "string" and flag == true and baseDef(key) then
				out.Disabled[key] = true
			end
		end
	end
	return out
end

local function copyData(data: BalanceData): BalanceData
	return { Version = data.Version, Weapons = Util.DeepCopy(data.Weapons), Disabled = table.clone(data.Disabled) }
end

local function sameWeapons(a: { [string]: { [string]: number } }, b: { [string]: { [string]: number } }): boolean
	for key, fields in pairs(a) do
		local other = b[key]
		if not other then
			return false
		end
		for field, value in pairs(fields) do
			if other[field] ~= value then
				return false
			end
		end
		for field in pairs(other) do
			if fields[field] == nil then
				return false
			end
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false
		end
	end
	return true
end

-- ---------------------------------------------------------------------
-- DATASTORES (alles in pcall; Studio ohne API-Zugriff -> nur lokal)
-- ---------------------------------------------------------------------
local function noteStoreError(err: any)
	local text = string.lower(tostring(err))
	local studioError = string.find(text, "studio", 1, true)
		or string.find(text, "publish", 1, true)
		or string.find(text, "api services", 1, true)
		or string.find(text, "403", 1, true)
	if RunService:IsStudio() and studioError then
		storeDisabled = true
		if not storeWarned then
			storeWarned = true
			warn("[Balance] Kein DataStore-Zugriff im Studio – Balance/Statistik nur auf diesem Server.")
		end
	else
		warn("[Balance] DataStore-Fehler: " .. tostring(err))
	end
end

local function getStore(name: string): DataStore?
	if storeDisabled then
		return nil
	end
	local cached = if name == Config.Tech.LiveStore then liveStore else statsStore
	if cached then
		return cached
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(name)
	end)
	if not ok or not result then
		noteStoreError(result)
		return nil
	end
	if name == Config.Tech.LiveStore then
		liveStore = result
	else
		statsStore = result
	end
	return result
end

local function storeGet(storeName: string, key: string): (boolean, any)
	local store = getStore(storeName)
	if not store then
		return false, nil
	end
	local ok, result = pcall(function()
		return (store :: DataStore):GetAsync(key)
	end)
	if not ok then
		noteStoreError(result)
		return false, nil
	end
	return true, result
end

local function storeUpdate(storeName: string, key: string, transform: (old: any) -> any): (boolean, any)
	local store = getStore(storeName)
	if not store then
		return false, nil
	end
	local ok, result = pcall(function()
		return (store :: DataStore):UpdateAsync(key, function(old)
			return transform(old)
		end)
	end)
	if not ok then
		noteStoreError(result)
		return false, nil
	end
	return true, result
end

local function publish(message: { [string]: any }): boolean
	local ok, err = pcall(function()
		MessagingService:PublishAsync(Config.Tech.MessagingTopic, message)
	end)
	if not ok then
		warn("[Balance] Global senden fehlgeschlagen: " .. tostring(err))
	end
	return ok
end

-- ---------------------------------------------------------------------
-- ANWENDEN
-- ---------------------------------------------------------------------
-- Not-Aus: abgeschaltete Waffen aus laufenden Loadouts nehmen (Spieler: validiertes Loadout, Bots: Standard-Waffe)
local function enforceDisabled()
	local function hasDisabled(loadout: any): boolean
		if type(loadout) ~= "table" then
			return false
		end
		for _, slot in ipairs(SLOTS) do
			local def: any = Config.Weapon(loadout[slot])
			if def and def.Enabled == false then
				return true
			end
		end
		return false
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local ok, c = call("CombatService", "OfPlayer", p)
		if ok and type(c) == "table" and hasDisabled(c.Loadout) then
			local okX, info = call("CombatService", "Context", c.Ctx)
			local rules = if okX and type(info) == "table" then info.Rules else nil
			local okL, loadout = call("ShopService", "GetLoadout", p, rules)
			if okL and type(loadout) == "table" then
				call("WeaponService", "SetLoadout", c, loadout)
			end
		end
	end
	local defaults = Config.Weapons and Config.Weapons.DefaultLoadout or {}
	for _, model in ipairs(CollectionService:GetTagged("Bot")) do
		local id = model:GetAttribute("CombatantId")
		if Util.IsFinite(id) then
			local ok, c = call("CombatService", "Get", id)
			if ok and type(c) == "table" and hasDisabled(c.Loadout) then
				local loadout = table.clone(c.Loadout)
				for _, slot in ipairs(SLOTS) do
					local def: any = Config.Weapon(loadout[slot])
					if def and def.Enabled == false and type(defaults[slot]) == "string" then
						loadout[slot] = defaults[slot]
					end
				end
				call("WeaponService", "SetLoadout", c, loadout)
			end
		end
	end
end

local function applyWorking()
	Config.ApplyBalance({ Version = working.Version, Weapons = working.Weapons, Disabled = working.Disabled })
	if liveValue then
		local ok, json = pcall(function()
			return HttpService:JSONEncode({
				Version = working.Version,
				Weapons = working.Weapons,
				Disabled = working.Disabled,
				Preview = preview,
			})
		end)
		if ok then
			liveValue.Value = json
		end
	end
	if working.Version ~= lastBroadcastVersion then
		lastBroadcastVersion = working.Version
		call("PlayerStateService", "EffectAll", "Balance", 1, { Version = working.Version })
	end
	-- Not-Aus aktiv? -> laufende Loadouts reparieren
	if next(working.Disabled) ~= nil then
		enforceDisabled()
	end
end

-- Gespeicherten Stand übernehmen (Vorschau verfällt)
local function adoptSaved(data: BalanceData)
	saved = copyData(data)
	working = copyData(data)
	preview = false
	applyWorking()
end

local function loadFromStore(force: boolean?)
	if loading then
		reloadPending = true -- neue Version kam während des Ladens -> danach nochmal
		return
	end
	loading = true
	reloadPending = false
	local ok, raw = storeGet(Config.Tech.LiveStore, "Balance")
	if ok then
		local data = clean(raw)
		if force or data.Version > saved.Version then
			adoptSaved(data)
			if data.Version > 0 then
				print(("[Balance] Live-Balance v%d übernommen"):format(data.Version))
			end
		end
	end
	loading = false
	if reloadPending then
		reloadPending = false
		task.spawn(loadFromStore, false)
	end
end

local function loadHistory(): { HistoryEntry }
	if historyCache and os.clock() - historyAt < HISTORY_CACHE_SECONDS then
		return historyCache
	end
	local list: { HistoryEntry } = {}
	local ok, raw = storeGet(Config.Tech.LiveStore, "BalanceHistory")
	if ok and type(raw) == "table" then
		for _, entry in ipairs(raw) do
			if type(entry) == "table" and Util.IsFinite(entry.Version) then
				local data = clean(entry)
				table.insert(list, {
					Version = data.Version,
					Weapons = data.Weapons,
					Disabled = data.Disabled,
					T = if Util.IsFinite(entry.T) then entry.T else 0,
					By = if Util.IsFinite(entry.By) then entry.By else 0,
					ByName = if type(entry.ByName) == "string" then string.sub(entry.ByName, 1, 40) else "?",
				})
			end
		end
	elseif historyCache then
		list = historyCache -- Lesefehler: alten Verlauf behalten
	end
	historyCache = list
	historyAt = os.clock()
	return list
end

-- Neue Version schreiben (Balance + Verlauf) und an alle Server melden – yieldet
local function persist(content: BalanceData, by: Player?): (boolean, number, boolean)
	local newVersion = math.max(saved.Version, working.Version) + 1
	local okWrite, result = storeUpdate(Config.Tech.LiveStore, "Balance", function(old)
		local base = clean(old)
		newVersion = math.max(base.Version, saved.Version, working.Version) + 1
		return { Version = newVersion, Weapons = content.Weapons, Disabled = content.Disabled }
	end)
	local final: BalanceData = { Version = newVersion, Weapons = content.Weapons, Disabled = content.Disabled }
	if okWrite and type(result) == "table" then
		final = clean(result)
	end
	local entry: HistoryEntry = {
		Version = final.Version,
		Weapons = final.Weapons,
		Disabled = final.Disabled,
		T = os.time(),
		By = if by then by.UserId else 0,
		ByName = if by then by.Name else "Server",
	}
	if okWrite then
		local keep = math.max(1, math.floor(tonumber(SEC.HistoryVersions) or 10))
		storeUpdate(Config.Tech.LiveStore, "BalanceHistory", function(old)
			local list: { any } = { entry }
			if type(old) == "table" then
				for _, item in ipairs(old) do
					if #list >= keep then
						break
					end
					if type(item) == "table" and item.Version ~= entry.Version then
						table.insert(list, item)
					end
				end
			end
			return list
		end)
	end
	-- lokaler Verlauf (auch ohne DataStore, z. B. Studio)
	local hist = historyCache or {}
	table.insert(hist, 1, entry)
	while #hist > math.max(1, math.floor(tonumber(SEC.HistoryVersions) or 10)) do
		table.remove(hist)
	end
	historyCache = hist
	historyAt = os.clock()
	adoptSaved(final)
	local localOnly = not okWrite
	if okWrite then
		publish({ Kind = "Balance", Version = final.Version })
	end
	return true, final.Version, localOnly
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICHE API (C5.7)
-- ---------------------------------------------------------------------
local function bump(kind: string, key: string, n: number)
	local bucket = counters[kind]
	if not bucket then
		bucket = {}
		counters[kind] = bucket
	end
	if bucket[key] == nil then
		local count = 0
		for _ in pairs(bucket) do
			count += 1
		end
		if count >= (tonumber(SEC.StatsMaxKeys) or 64) then
			return
		end
	end
	bucket[key] = (bucket[key] or 0) + n
end

function BalanceService.Stat(
	kind: "Pick" | "Kill" | "Head" | "WinWith" | "Map" | "Mode" | "QueueTime",
	key: string,
	n: number?
)
	if type(kind) ~= "string" or not PUBLIC_KINDS[kind] or type(key) ~= "string" then
		return
	end
	if #key == 0 or #key > MAX_KEY_LEN then
		return
	end
	local amount = if Util.IsFinite(n) then math.clamp(n :: number, 0, 1e6) else 1
	bump(kind, key, amount)
	if kind == "QueueTime" then
		bump("QueueTimeN", key, 1)
	end
end

function BalanceService.Version(): number
	return working.Version
end

-- ---------------------------------------------------------------------
-- ADMIN-API (Reiter Balance)
-- ---------------------------------------------------------------------
function BalanceService.GetBalance(): { [string]: any }
	local defaults: { [string]: { [string]: number } } = {}
	local weapons: { string } = {}
	local fields = balanceFields()
	for _, def in ipairs(weaponList()) do
		if type(def) == "table" and type(def.Key) == "string" then
			table.insert(weapons, def.Key)
			local entry: { [string]: number } = {}
			for field in pairs(fields) do
				local value = baseValue(def, field)
				if value then
					entry[field] = value
				end
			end
			defaults[def.Key] = entry
		end
	end
	local history: { { [string]: any } } = {}
	for _, entry in ipairs(loadHistory()) do
		local changes = 0
		for _, f in pairs(entry.Weapons) do
			for _ in pairs(f) do
				changes += 1
			end
		end
		local off = 0
		for _ in pairs(entry.Disabled) do
			off += 1
		end
		table.insert(
			history,
			{ Version = entry.Version, T = entry.T, ByName = entry.ByName, Changes = changes, Off = off }
		)
	end
	local fieldList: { string } = Util.Snapshot(fields)
	table.sort(fieldList)
	return {
		Version = saved.Version,
		Preview = preview,
		Defaults = defaults,
		Overrides = Util.DeepCopy(working.Weapons),
		Disabled = table.clone(working.Disabled),
		History = history,
		Fields = fieldList,
		Bounds = Util.DeepCopy(fields),
		Weapons = weapons,
	}
end

-- Vorschau nur auf diesem Server (Version bleibt, Preview = true)
function BalanceService.SetField(weapon: string, field: string, value: number): (boolean, number | string)
	if type(weapon) ~= "string" or type(field) ~= "string" then
		return false, "invalid"
	end
	local def = baseDef(weapon)
	local lo, hi = boundsOf(field)
	if not def or not lo or not hi or baseValue(def, field) == nil or not Util.IsFinite(value) then
		return false, "invalid"
	end
	local v = math.clamp(value, lo, hi)
	if field == "Mag" then
		v = math.clamp(math.floor(v + 0.5), math.ceil(lo), math.floor(hi))
	end
	local entry = working.Weapons[weapon] or {}
	entry[field] = v
	working.Weapons[weapon] = entry
	preview = not sameWeapons(working.Weapons, saved.Weapons)
	applyWorking()
	return true, v
end

function BalanceService.ResetWeapon(weapon: string): boolean
	if type(weapon) ~= "string" or not baseDef(weapon) then
		return false
	end
	working.Weapons[weapon] = nil
	preview = not sameWeapons(working.Weapons, saved.Weapons)
	applyWorking()
	return true
end

-- Für alle Server speichern (neue Version) – yieldet
function BalanceService.Save(by: Player?): (boolean, number, boolean)
	if saving then
		return false, saved.Version, false
	end
	saving = true
	local ok, okSave, version, localOnly = pcall(persist, copyData(working), by)
	saving = false
	if not ok then
		warn("[Balance] Speichern fehlgeschlagen: " .. tostring(okSave))
		return false, saved.Version, false
	end
	return okSave, version, localOnly
end

-- Alte Version aus dem Verlauf als NEUE Version speichern – yieldet
function BalanceService.Revert(version: number, by: Player?): (boolean, number?)
	if not Util.IsFinite(version) then
		return false, nil
	end
	local target: HistoryEntry? = nil
	for _, entry in ipairs(loadHistory()) do
		if entry.Version == math.floor(version) then
			target = entry
			break
		end
	end
	if version == 0 then
		target = { Version = 0, Weapons = {}, Disabled = {}, T = 0, By = 0, ByName = "" }
	end
	if not target or saving then
		return false, nil
	end
	saving = true
	local content: BalanceData =
		{ Version = target.Version, Weapons = Util.DeepCopy(target.Weapons), Disabled = table.clone(target.Disabled) }
	local ok, okSave, newVersion = pcall(persist, content, by)
	saving = false
	if not ok or not okSave then
		return false, nil
	end
	return true, newVersion
end

-- Not-Aus / wieder an: sofort für alle Server (Vorschau-Felder bleiben lokal) – yieldet
function BalanceService.SetEnabled(weapon: string, on: boolean, by: Player?): (boolean, number?)
	if type(weapon) ~= "string" or not baseDef(weapon) or saving then
		return false, nil
	end
	saving = true
	local content = copyData(saved)
	content.Disabled[weapon] = if on then nil else true
	local keepPreview = preview
	local previewWeapons = Util.DeepCopy(working.Weapons)
	local ok, okSave, newVersion = pcall(persist, content, by)
	saving = false
	if not ok or not okSave then
		return false, nil
	end
	if keepPreview then
		working.Weapons = previewWeapons
		preview = not sameWeapons(working.Weapons, saved.Weapons)
		applyWorking()
	end
	return true, newVersion
end

-- ---------------------------------------------------------------------
-- STATISTIK
-- ---------------------------------------------------------------------
-- Zählt nur in echten Matches ("M<id>"), nie im Schießstand und nie in Admin-Show-Matches (Tainted)
local function countsForStats(ctx: any): boolean
	if type(ctx) ~= "string" or string.sub(ctx, 1, 1) ~= "M" then
		return false
	end
	local cached = taintCache[ctx]
	local now = os.clock()
	if cached and now - cached.T < TAINT_CACHE_SECONDS then
		return not cached.Tainted
	end
	local id = tonumber(string.sub(ctx, 2))
	local tainted = false
	if id then
		local ok, info = call("MatchService", "Info", id)
		tainted = ok and type(info) == "table" and info.Tainted == true
	end
	if taintCache[ctx] == nil then
		taintCacheSize += 1
		if taintCacheSize > 64 then
			table.clear(taintCache) -- begrenzt halten
			taintCacheSize = 1
		end
	end
	taintCache[ctx] = { T = now, Tainted = tainted }
	return not tainted
end

local function humanCombatant(c: any): boolean
	if type(c) ~= "table" or c.Kind ~= "Player" then
		return false
	end
	local p = c.Player
	return typeof(p) == "Instance" and p:IsA("Player")
end

local function onShot(c: any, def: any, hits: number, heads: number)
	if not humanCombatant(c) or type(def) ~= "table" or type(def.Key) ~= "string" or def.AdminOnly then
		return
	end
	if not countsForStats(c.Ctx) then
		return
	end
	local h = if Util.IsFinite(hits) then math.clamp(math.floor(hits), 0, 32) else 0
	local hd = if Util.IsFinite(heads) then math.clamp(math.floor(heads), 0, h) else 0
	bump("Shot", def.Key, 1)
	if h > 0 then
		bump("Hit", def.Key, 1)
	end
	if hd > 0 then
		bump("HeadHit", def.Key, 1)
	end
end

local function onElimination(_victim: any, killer: any, info: any)
	if not humanCombatant(killer) or type(info) ~= "table" or type(info.WeaponKey) ~= "string" then
		return
	end
	local def: any = Config.Weapon(info.WeaponKey)
	if not def or def.AdminOnly or not countsForStats(killer.Ctx) then
		return
	end
	bump("Pop", info.WeaponKey, 1)
	if info.Head == true then
		bump("HeadPop", info.WeaponKey, 1)
	end
end

local function onMatchEnd(result: any)
	if type(result) ~= "table" or result.Tainted == true or result.Tutorial == true then
		return
	end
	bump("Match", "Total", 1)
	if result.VsBots == true then
		bump("Match", "VsBots", 1)
	end
	if type(result.Map) == "string" and #result.Map <= MAX_KEY_LEN then
		bump("Map", result.Map, 1)
	end
	if type(result.Mode) == "string" and #result.Mode <= MAX_KEY_LEN then
		bump("Mode", result.Mode, 1)
	end
	if type(result.PerPlayer) ~= "table" then
		return
	end
	for p, r in pairs(result.PerPlayer) do
		if typeof(p) == "Instance" and type(r) == "table" and type(r.WeaponUsed) == "table" then
			bump("Match", "PlayerMatches", 1)
			for key, used in pairs(r.WeaponUsed) do
				local def: any = if type(key) == "string" then Config.Weapon(key) else nil
				if used == true and def and not def.AdminOnly then
					bump("Pick", key, 1)
					if r.Won == true then
						bump("WinWith", key, 1)
					end
				end
			end
		end
	end
end

local function mergeCounters(target: Counters, source: any)
	if type(source) ~= "table" then
		return
	end
	for kind, bucket in pairs(source) do
		if type(kind) == "string" and type(bucket) == "table" then
			local into = target[kind]
			if not into then
				into = {}
				target[kind] = into
			end
			for key, n in pairs(bucket) do
				if type(key) == "string" and Util.IsFinite(n) then
					into[key] = (into[key] or 0) + n
				end
			end
		end
	end
end

local function flushStats()
	if flushing or next(counters) == nil then
		return
	end
	flushing = true
	local batch = counters
	counters = {}
	task.spawn(function()
		local key = ("S_%s_%d"):format(dateKey(realDay()), shard())
		local ok = storeUpdate(Config.Tech.StatsStore, key, function(old)
			local merged: Counters = {}
			mergeCounters(merged, old)
			mergeCounters(merged, batch)
			return merged
		end)
		if not ok and not storeDisabled then
			mergeCounters(counters, batch) -- beim nächsten Mal nochmal versuchen
		end
		statsCache = {}
		flushing = false
	end)
end

local function pct(a: number, b: number): number
	if b <= 0 then
		return 0
	end
	return math.floor(a / b * 1000 + 0.5) / 10
end

-- Statistik der letzten 1 oder 7 Tage (alle Shards + ungespeicherte Zähler dieses Servers) – yieldet
function BalanceService.GetStats(days: number): { [string]: any }
	local count = if days == 7 then 7 else 1
	local cached = statsCache[count]
	if cached and os.clock() - cached.T < (tonumber(SEC.StatsCacheSeconds) or 60) then
		return cached.Data
	end
	local total: Counters = {}
	if getStore(Config.Tech.StatsStore) then
		local today = realDay()
		local gap = tonumber(SEC.StoreReadGap) or 0.25
		local first = true
		for d = 0, count - 1 do
			for s = 0, shardCount() - 1 do
				if storeDisabled then
					break
				end
				if not first then
					task.wait(gap)
				end
				first = false
				local ok, value = storeGet(Config.Tech.StatsStore, ("S_%s_%d"):format(dateKey(today - d), s))
				if ok then
					mergeCounters(total, value)
				end
			end
		end
	end
	mergeCounters(total, counters)
	local function get(kind: string, key: string): number
		local bucket = total[kind]
		return if bucket and Util.IsFinite(bucket[key]) then bucket[key] else 0
	end
	local playerMatches = get("Match", "PlayerMatches")
	local weapons: { { [string]: any } } = {}
	for _, def in ipairs(weaponList()) do
		if type(def) == "table" and type(def.Key) == "string" and not def.AdminOnly then
			local key = def.Key
			local picks = get("Pick", key)
			-- eigene Quellen (nur echte, nicht getaintete Matches) vor den Stat-Aufrufen anderer Pakete
			local pops = if popSource then get("Pop", key) else get("Kill", key)
			local hits = get("Hit", key)
			local headPct = if shotSource and hits > 0
				then pct(get("HeadHit", key), hits)
				else pct(if popSource then get("HeadPop", key) else get("Head", key), pops)
			local pickPct = pct(picks, playerMatches)
			table.insert(weapons, {
				Key = key,
				Slot = def.Slot,
				Picks = picks,
				PickPct = pickPct,
				Pops = pops,
				PopsPerMatch = if picks > 0 then math.floor(pops / picks * 100 + 0.5) / 100 else 0,
				WinPct = pct(get("WinWith", key), picks),
				HeadPct = headPct,
				AccuracyPct = pct(hits, get("Shot", key)),
				BuffFirst = playerMatches > 0 and pickPct < 3,
			})
		end
	end
	table.sort(weapons, function(a, b)
		return a.Picks > b.Picks
	end)
	local function list(kind: string): { { Key: string, Picks: number } }
		local out: { { Key: string, Picks: number } } = {}
		for key, n in pairs(total[kind] or {}) do
			table.insert(out, { Key = key, Picks = n })
		end
		table.sort(out, function(a, b)
			return a.Picks > b.Picks
		end)
		return out
	end
	local queue: { { Mode: string, Seconds: number } } = {}
	local qSum, qCount = 0, 0
	for mode, sum in pairs(total.QueueTime or {}) do
		local n = get("QueueTimeN", mode)
		if n > 0 then
			table.insert(queue, { Mode = mode, Seconds = math.floor(sum / n * 10 + 0.5) / 10 })
			qSum += sum
			qCount += n
		end
	end
	table.sort(queue, function(a, b)
		return a.Mode < b.Mode
	end)
	local matches = get("Match", "Total")
	local data = {
		Days = count,
		Matches = matches,
		PlayerMatches = playerMatches,
		BotPct = pct(get("Match", "VsBots"), matches),
		AvgQueue = if qCount > 0 then math.floor(qSum / qCount * 10 + 0.5) / 10 else 0,
		Queue = queue,
		Weapons = weapons,
		Maps = list("Map"),
		Modes = list("Mode"),
	}
	statsCache[count] = { T = os.clock(), Data = data }
	return data
end

-- ---------------------------------------------------------------------
-- LEBENSZYKLUS
-- ---------------------------------------------------------------------
function BalanceService.Init(services: any)
	Services = services
	local existing = ReplicatedStorage:FindFirstChild(LIVE_VALUE_NAME)
	if existing and not existing:IsA("StringValue") then
		existing.Name = LIVE_VALUE_NAME .. "_Alt"
		existing = nil
	end
	local value: StringValue
	if existing and existing:IsA("StringValue") then
		value = existing
	else
		value = Instance.new("StringValue")
		value.Name = LIVE_VALUE_NAME
		value.Parent = ReplicatedStorage
	end
	liveValue = value
	value.Value = HttpService:JSONEncode({ Version = 0, Weapons = {}, Disabled = {}, Preview = false })
end

function BalanceService.Start()
	-- Beim Boot laden (yieldet -> eigener Thread)
	task.spawn(loadFromStore, true)

	-- Global: neue Version gespeichert -> laden (Sender empfängt auch selbst, dann gleiche Version = nichts)
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(Config.Tech.MessagingTopic, function(packet)
				local message = if type(packet) == "table" then packet.Data else nil
				if type(message) ~= "table" or message.Kind ~= "Balance" then
					return
				end
				local version = message.Version
				if Util.IsFinite(version) and version % 1 == 0 and version > saved.Version and version < 1e9 then
					task.spawn(loadFromStore, false)
				end
			end)
		end)
		if not ok then
			warn("[Balance] MessagingService nicht verfügbar (in Studio normal): " .. tostring(err))
		end
	end)

	-- Poll alle 120 s (Sicherheitsnetz, falls eine Nachricht verloren ging)
	local poll = math.max(30, tonumber(Config.Tech.BalancePollSeconds) or 120)
	Scheduler.Every("BalancePoll", 1 / poll, function()
		if not storeDisabled then
			task.spawn(loadFromStore, false)
		end
	end)
	-- Statistik-Flush alle 600 s
	local flushEvery = math.max(60, tonumber(Config.Tech.StatsFlushSeconds) or 600)
	Scheduler.Every("BalanceStatsFlush", 1 / flushEvery, flushStats)

	-- Eigene Statistik-Quellen
	shotSource = call("WeaponService", "OnShot", onShot) == true
	popSource = call("CombatService", "OnElimination", onElimination) == true
	call("MatchService", "OnMatchEnd", onMatchEnd)

	game:BindToClose(function()
		if next(counters) ~= nil and not storeDisabled then
			local batch = counters
			counters = {}
			local key = ("S_%s_%d"):format(dateKey(realDay()), shard())
			pcall(storeUpdate, Config.Tech.StatsStore, key, function(old)
				local merged: Counters = {}
				mergeCounters(merged, old)
				mergeCounters(merged, batch)
				return merged
			end)
		end
	end)
end

return BalanceService
