--!strict
-- =====================================================================
--  AKYTEX TYCOON – Wochen-Seeds, Wochenschluss, IPO-Liste (Server/Market/MarketSeed)
--  Besitzer: WP3 (Markt-Engine). Vertrag: MARKET.md §5.6, DESIGN.md §C13, §C17, §C19 Nr. 10.
--  DataStore Config.Tech.MarketStore ("AT_Market_v1"):
--    Seed_W<w>  zufällige 31-Bit-Zahl, UpdateAsync "nur setzen, wenn leer"; der erste Server legt auch Seed_W<w+1> an
--    Close_W<w> { [tostring(id)] = Cent } Wochenschlusskurse (Aktien, ETFs, gelistete IPOs) = Basis der Woche w+1
--    Ipo_S<s>   { [tostring(id)] = { Tick, Issue, Open, By } } gelistete IPOs der Saison s
--    Tune_W<w>  { NewsMeanGap } – Live-Stellschraube, beim Anlegen der Woche eingefroren (alle Server gleich)
--  Der Seed ist NIE im Place-File/Config und erreicht NIE einen Client.
--  Studio (Config.Studio.LocalMarket) oder DataStore nicht erreichbar -> Fallback-Seed (lokaler Testmarkt):
--    hash4(Config.Market.StudioSalt, w, PEPPER, 0) – PEPPER liegt nur hier (ServerScriptService, nicht repliziert),
--    damit ein Client aus der replizierten Config den Fallback-Markt nicht vorausrechnen kann.
--  Live: zuerst Wiederholen mit Backoff (Config.Market.Seed.RetrySeconds), dann Fallback.
--  Alle DataStore-Aufrufe in pcall; alle Funktionen außer Fallback() YIELDEN (nur aus eigenen Threads aufrufen).
--
--  Öffentliche API (nur WP3)
--    MarketSeed.Load(w): (seed: number, local: boolean)
--    MarketSeed.Peek(w): number?  (nur lesen)   MarketSeed.EnsureNext(w)   MarketSeed.Fallback(w): number
--    MarketSeed.LoadClose(w): { [number]: number }?      MarketSeed.SaveClose(w, closes)
--    MarketSeed.LoadIpos(s): { [number]: { Tick, Issue, Open, By } }      MarketSeed.SaveIpo(s, id, rec)
--    MarketSeed.LoadTune(w, default): number (NewsMeanGap)
--    MarketSeed.IsLocal(): boolean            MarketSeed.Ok(): boolean (letzter DataStore-Zugriff erfolgreich)
-- =====================================================================

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Noise = require(script.Parent:WaitForChild("Noise"))

local MarketSeed = {}

local PEPPER = 0x6B1D3A57 -- Server-Geheimnis für den Fallback-Seed (nur ServerScriptService)
local MAX_ENTRIES = 300 -- so viele Einträge darf ein Close-/Ipo-Datensatz höchstens haben

local store: DataStore? = nil
local localMode = false
local lastOk = true

local function marketCfg(): { [string]: any }
	return Config.Market :: any
end

local function studioLocal(): boolean
	local studio: any = Config.Studio
	return RunService:IsStudio() and type(studio) == "table" and studio.LocalMarket == true
end

local function isAccessError(err: any): boolean
	local text = string.lower(tostring(err))
	return string.find(text, "studio", 1, true) ~= nil
		or string.find(text, "api services", 1, true) ~= nil
		or string.find(text, "403", 1, true) ~= nil
		or string.find(text, "publish", 1, true) ~= nil
end

local function getStore(): DataStore?
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore((Config.Tech :: any).MarketStore or "AT_Market_v1")
	end)
	if ok and result then
		store = result
		return result
	end
	return nil
end

function MarketSeed.Fallback(w: number): number
	local salt = tonumber(marketCfg().StudioSalt) or 1
	return Noise.Hash4(salt, w, PEPPER, 0) % 2147483647 + 1
end

function MarketSeed.IsLocal(): boolean
	return localMode
end

function MarketSeed.Ok(): boolean
	return lastOk
end

-- ein DataStore-Aufruf mit pcall; Rückgabe ok, Ergebnis, ist Zugriffsfehler (Studio ohne API)
local function call(fn: (DataStore) -> any): (boolean, any, boolean)
	local ds = getStore()
	if ds == nil then
		lastOk = false
		return false, nil, true
	end
	local ok, result = pcall(fn, ds)
	lastOk = ok
	if not ok then
		return false, result, isAccessError(result)
	end
	return true, result, false
end

local function newSeed(): number
	local rng = Random.new()
	return rng:NextInteger(1, 2147483646)
end

local function validSeed(v: any): boolean
	return type(v) == "number" and v == v and v % 1 == 0 and v >= 1 and v < 2147483648
end

-- Seed_W<w> lesen bzw. anlegen ("nur setzen, wenn leer")
local function fetchSeed(w: number): (boolean, number?, boolean)
	local candidate = newSeed()
	local ok, result, access = call(function(ds: DataStore)
		return ds:UpdateAsync("Seed_W" .. w, function(old: any)
			if validSeed(old) then
				return nil -- nichts schreiben, vorhandenen behalten
			end
			return candidate
		end)
	end)
	if ok then
		if validSeed(result) then
			return true, result, false
		end
		-- UpdateAsync gibt bei "nil zurück" (nichts geschrieben) den alten Wert zurück; sicherheitshalber lesen
		local okGet, value = call(function(ds: DataStore)
			return (ds:GetAsync("Seed_W" .. w))
		end)
		if okGet and validSeed(value) then
			return true, value, false
		end
		return false, nil, false
	end
	return false, nil, access
end

function MarketSeed.Load(w: number): (number, boolean)
	if studioLocal() then
		localMode = true
		return MarketSeed.Fallback(w), true
	end
	local cfg = marketCfg().Seed or {}
	local backoff: { number } = cfg.Backoff or { 2, 4, 8, 15, 30 }
	local budget = tonumber(cfg.RetrySeconds) or 60
	local waited = 0
	local attempt = 0
	while true do
		attempt += 1
		local ok, seed, access = fetchSeed(w)
		if ok and seed then
			localMode = false
			return seed, false
		end
		if access and RunService:IsStudio() then
			break -- Studio ohne API-Zugriff: sofort lokaler Testmarkt
		end
		local pause = backoff[math.min(attempt, #backoff)] or 5
		if waited + pause > budget then
			break
		end
		task.wait(pause)
		waited += pause
	end
	warn("[MarketSeed] Seed nicht erreichbar – lokaler Fallback-Markt für Woche " .. w)
	localMode = true
	return MarketSeed.Fallback(w), true
end

-- nur lesen (Vorwoche für Historie/Offline-Abgleich): nil = gab es nicht oder nicht erreichbar
function MarketSeed.Peek(w: number): number?
	if studioLocal() or localMode then
		return MarketSeed.Fallback(w)
	end
	local ok, value = call(function(ds: DataStore)
		return (ds:GetAsync("Seed_W" .. w))
	end)
	if ok and validSeed(value) then
		return value
	end
	return nil
end

function MarketSeed.EnsureNext(w: number)
	if localMode or studioLocal() then
		return
	end
	fetchSeed(w + 1)
end

-- ---------------------------------------------------------------------
-- WOCHENSCHLUSS
-- ---------------------------------------------------------------------
local function cleanCloses(raw: any): { [number]: number }?
	if type(raw) ~= "table" then
		return nil
	end
	local out: { [number]: number } = {}
	local count = 0
	for key, value in pairs(raw) do
		count += 1
		if count > MAX_ENTRIES then
			break
		end
		local id = tonumber(key)
		if
			id
			and id % 1 == 0
			and id >= 1
			and id <= 255
			and type(value) == "number"
			and value == value
			and value % 1 == 0
			and value >= 1
			and value <= 9999999
		then
			out[id] = value
		end
	end
	return out
end

function MarketSeed.LoadClose(w: number): { [number]: number }?
	if localMode or studioLocal() then
		return nil
	end
	local ok, result = call(function(ds: DataStore)
		return (ds:GetAsync("Close_W" .. w))
	end)
	if not ok then
		return nil
	end
	return cleanCloses(result)
end

function MarketSeed.SaveClose(w: number, closes: { [number]: number })
	if localMode or studioLocal() then
		return
	end
	local payload: { [string]: number } = {}
	for id, cents in pairs(closes) do
		payload[tostring(id)] = math.clamp(math.round(cents), 1, 9999999)
	end
	call(function(ds: DataStore)
		return ds:UpdateAsync("Close_W" .. w, function(old: any)
			if type(old) == "table" and next(old) ~= nil then
				return nil -- erster Schreiber gewinnt (alle Server rechnen dieselben Werte)
			end
			return payload
		end)
	end)
end

-- ---------------------------------------------------------------------
-- IPO-LISTE JE SAISON
-- ---------------------------------------------------------------------
function MarketSeed.LoadIpos(s: number): { [number]: { [string]: number } }
	local out: { [number]: { [string]: number } } = {}
	if localMode or studioLocal() then
		return out
	end
	local ok, result = call(function(ds: DataStore)
		return (ds:GetAsync("Ipo_S" .. s))
	end)
	if not ok or type(result) ~= "table" then
		return out
	end
	local count = 0
	for key, rec in pairs(result) do
		count += 1
		if count > MAX_ENTRIES then
			break
		end
		local id = tonumber(key)
		if id and id >= 100 and id <= 139 and type(rec) == "table" then
			local tick, issue, open = tonumber(rec.Tick), tonumber(rec.Issue), tonumber(rec.Open)
			if tick and issue and open and tick >= 0 and issue >= 1 and open >= 1 and open <= 9999999 then
				out[id] = {
					Tick = math.floor(tick),
					Issue = math.floor(issue),
					Open = math.floor(open),
					By = tonumber(rec.By) or 0,
				}
			end
		end
	end
	return out
end

function MarketSeed.SaveIpo(s: number, id: number, rec: { [string]: number })
	if localMode or studioLocal() then
		return
	end
	call(function(ds: DataStore)
		return ds:UpdateAsync("Ipo_S" .. s, function(old: any)
			local data = if type(old) == "table" then old else {}
			local key = tostring(id)
			if data[key] ~= nil then
				return nil -- schon gelistet: nie überschreiben
			end
			data[key] = { Tick = rec.Tick, Issue = rec.Issue, Open = rec.Open, By = rec.By or 0 }
			return data
		end)
	end)
end

-- ---------------------------------------------------------------------
-- EINGEFRORENE LIVE-STELLSCHRAUBE (News-Takt) JE WOCHE
-- ---------------------------------------------------------------------
function MarketSeed.LoadTune(w: number, default: number): number
	local fallback = math.clamp(tonumber(default) or 1500, 300, 6000)
	if localMode or studioLocal() then
		return fallback
	end
	local ok, result = call(function(ds: DataStore)
		return ds:UpdateAsync("Tune_W" .. w, function(old: any)
			if type(old) == "table" and type(old.NewsMeanGap) == "number" then
				return nil
			end
			return { NewsMeanGap = fallback }
		end)
	end)
	if ok and type(result) == "table" and type(result.NewsMeanGap) == "number" then
		return math.clamp(result.NewsMeanGap, 300, 6000)
	end
	local okGet, value = call(function(ds: DataStore)
		return (ds:GetAsync("Tune_W" .. w))
	end)
	if okGet and type(value) == "table" and type(value.NewsMeanGap) == "number" then
		return math.clamp(value.NewsMeanGap, 300, 6000)
	end
	return fallback
end

return MarketSeed
