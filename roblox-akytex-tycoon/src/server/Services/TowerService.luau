-- =====================================================================
--  AKYTEX TYCOON – Turm-Ökonomie (Server/Services/TowerService)
--  Besitzer: WP6 (Turm-Ökonomie). Vertrag: DESIGN.md §C5.5, §C9 (Tower*), §C10 (State Tower, Income), §B4, §B5,
--  §B8.2 (Gewinn-Transfer, CR-Seite), §B9.6 (Börsengang-Reset). Formeln: Shared/TowerMath (== tools/economy_sim.py).
--
--  Server ist Autorität: Etagen, Abteilungen, Personal, Raum-Stufen, Effizienz, Tresor, Offline-Einnahmen, Baustelle,
--  Boosts, Multiplikatoren. CR bucht NUR ShopService (Credit/Debit). Robux-Firewall (§0.4): Turm-Multiplikatoren wirken
--  nie auf AKY; der Gewinn-Transfer läuft nur AKY -> CR (OrderService.Withdraw liefert Cent, hier × Bau-Kurs der
--  Lizenz -> ShopService.Credit(…, "Transfer")). Es gibt KEINE Funktion, die CR in AKY verwandelt.
--
--  Ablauf:
--    * Profil geladen -> Turm-Daten reparieren, Attribute/Leaderstat, Hülle bauen (wenn der Plot steht).
--    * Bereit (Pässe geladen) -> Offline-Abrechnung (DataService.LastSavedAt) + Gratis-Sofortbau-Token des Tages.
--    * Takt "TowerIncome" 1 Hz (EIN Batch für alle): Bau fertig?, Boost-Countdown (nur online, nur der stärkste),
--      Einkommen (Teile alle 5 s neu), Tresor füllen, Hausmeister-Bot (60 s, auf dem Plot) / Auto-Kassierer (3 s).
--    * Glocke: OrderService.OnBell(p) -> Withdraw(p, "Bell") -> CR gutschreiben (Auto-Transfer, auch offline verbuchte).
--
--  Öffentliche API (§C5.5):
--    TowerService.Income(p): Types.IncomeInfo           PerSec inkl. Zeitlich, Steady ohne Zeitlich
--    TowerService.Floors(p) · Stage(p) · RunSpend(p) · TowerValue(p)   (TowerValue = 0,5 × RunSpend)
--    TowerService.AddBoost(p, "X2" | "X5" | "Bull", seconds): boolean
--    TowerService.SetServerBoost("Parade" | "Bell", mult, seconds)       setzt (überschreibt) den Server-Boost
--    TowerService.SetEventMult(mult, untilUnix)                           Golden Hour/Admin, geklemmt ≤ 3
--    TowerService.AddExpressToken(p, maxSeconds) · ApplyExpress(p, maxSeconds): boolean · AddInstantToken(p, n)
--    TowerService.ResetForIpo(p, perks): boolean       VORHER RunSpend(p) lesen (Sterne/Firmenwert rechnet WP9)
--    TowerService.AdminSetFloors(p, n): boolean
--    TowerService.CostMult("Floor" | "RoomLevel"): number    TowerService.SetCostEvent(kind, mult, untilUnix)
--    TowerService.OnFloorBuilt(cb(p, floor, stage)) · OnStageUp(cb(p, stage)) · OnTransfer(cb(p, akyCents, credits))
--  Ergänzungen (abwärtskompatibel):
--    TowerService.RoomCount(p, roomKey): number         z. B. "Garage" (Auto-Plätze), "Lounge"/"Marketing" (Respekt)
--    TowerService.SetBuildEvent(mult, untilUnix)        Admin-Bau-Boom: Bauzeit-Faktor (nie unter 25 % Grundzeit)
--    TowerService.Transfer(p, reason): (number, string?)   Gewinn-Transfer ausführen (CR, Grund-Schlüssel)
--    TowerService.Refresh(p)                            Einkommen sofort neu (nach Pass-/Abo-Kauf; kein Yield)
--  Request-Handler: TowerBuild, TowerRoom, TowerLevel, TowerHire, TowerFire, TowerEfficiency, TowerCollect,
--    TowerTransfer, TowerInstant, TowerExpress, TowerHelp, TowerName, TowerSkin, TowerNeon, TowerPrivate, TowerDecor,
--    TowerLayout, TowerAutoPlan   (TowerVisit/TowerHome/TowerElevator: PlotService)
--  State: Tower, Income. Effekte: BuildDone, StageUp, TransferTube, Collect, Crane. Attribut: TowerName ("a:n").
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Types = require(Shared:WaitForChild("Types"))
local Lang = require(Shared:WaitForChild("Lang"))
local Format = require(Shared:WaitForChild("Format"))
local Clock = require(Shared:WaitForChild("Clock"))
local TowerMath = require(Shared:WaitForChild("TowerMath"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local TowerService = {}
local Services: any = nil

type FloorData = Types.FloorData
type MultPart = Types.MultPart
type IncomeInfo = Types.IncomeInfo
type Reply = Types.Reply
type LangCode = Types.Lang

-- Umgebung für die Kern-Operationen (echte Dienste im Spiel, Attrappen in TowerTests)
export type Env = {
	Now: number,
	Licence: number,
	Ipo: number,
	Perk: (key: string) -> number, -- Schlüssel aus Config.Tower.Perks ("Growth", "Blitz", "Build", "Tempo", "Vault")
	HasPass: (key: string) -> boolean,
	Balance: () -> number,
	Debit: (amount: number, sink: string) -> boolean,
	Credit: (amount: number, source: string) -> boolean,
	TakeDecor: (key: string) -> boolean,
	ReturnDecor: (key: string) -> (),
	Comfort: (key: string) -> number,
	Owns: (entry: any) -> boolean,
	BuildEvent: number, -- Bauzeit-Faktor aus Admin-Bau-Boom (1 = keiner)
	CostEvent: (kind: string) -> number, -- Kosten-Faktor aus Bau-Boom (1 = keiner)
}

type Runtime = {
	Base: number,
	BaseDirty: boolean,
	Info: IncomeInfo?,
	InfoAt: number,
	InfoSig: string,
	VaultCap: number,
	VaultFrac: number,
	VaultFullNotified: boolean,
	JanitorAcc: number,
	AutoAcc: number,
	SlowAcc: number,
	JoinClock: number,
	JoinUnix: number,
	Settled: boolean,
	Welcome: { [string]: any }?,
	StageToastAt: number,
	MaxMoneyAt: number,
	AutoDirtyAt: number,
	Repaired: boolean,
}

-- ---------------------------------------------------------------------
-- 1) KONSTANTEN & CONFIG
-- ---------------------------------------------------------------------
local MAX_MONEY = 9e15
local PREFIX = "[TowerService] "
local PARTS_REFRESH = 5 -- Sekunden: Multiplikator-Teile (Freunde, Respekt, Pässe, Lizenz) neu einsammeln
local WELCOME_WINDOW = 120 -- Sekunden nach dem Beitritt zählen Glocken-Transfers in den Willkommen-Bericht
local AUTO_STATE_EVERY = 15 -- Auto-Kassierer: Tower-State höchstens alle 15 s senden (Netz-Budget §C16)
local MAX_COMFORT_CACHE = 256
local MAX_DECOR_KEY = 40
local ERROR_LOG_EVERY = 10

local TCFG: { [string]: any } = if type(Config.Tower) == "table" then Config.Tower else {}

local function isNum(v: any): boolean
	return Util.IsFinite(v)
end

local function isInt(v: any): boolean
	return Util.IsFinite(v) and v % 1 == 0
end

local function num(v: any, default: number): number
	return if Util.IsFinite(v) then v else default
end

local function sub(t: any, key: string): { [string]: any }
	local v = if type(t) == "table" then t[key] else nil
	return if type(v) == "table" then v else {}
end

local FLOORS = math.clamp(math.floor(num(TCFG.Floors, 50)), 1, 50)
local BUILD = sub(TCFG, "Build")
local OFFLINE = sub(TCFG, "Offline")
local IPO = sub(TCFG, "Ipo")
local PERKS = sub(TCFG, "Perks")
local DECOR_FALLBACK = sub(TCFG, "Decor")
local DEFAULT_ROOM = if type(TCFG.DefaultRoom) == "string" then TCFG.DefaultRoom else "Office"
local DEFAULT_SKIN = if type(TCFG.DefaultSkin) == "string" then TCFG.DefaultSkin else "GlassBlue"
local DEFAULT_NEON = if type(TCFG.DefaultNeon) == "string" then TCFG.DefaultNeon else "Accent"
local STAFF_SLOTS = math.floor(num(TCFG.StaffSlots, 2))
local STAFF_SLOTS_PLUS = math.max(STAFF_SLOTS, math.floor(num(TCFG.StaffSlotsPlus, 3)))
local PRIVATE_MAX = math.floor(num(TCFG.PrivateMax, 5))
local HELP_MAX = math.floor(num(BUILD.HelpMax, 3))
local EXPRESS_MAX = math.floor(num(BUILD.ExpressMax, 50))
local EXPRESS_MAX_SECONDS = math.floor(num(BUILD.ExpressMaxSeconds, 86400))
local INSTANT_MAX = math.floor(num(BUILD.InstantMax, 99))
local function listOf(t: any, key: string): { any }
	local v = if type(t) == "table" then t[key] else nil
	return if type(v) == "table" then v else {}
end
local NAME_ADJ = #listOf(sub(TCFG, "Names"), "Adj")
local NAME_NOUN = #listOf(sub(TCFG, "Names"), "Noun")

-- Nachschlage-Tabellen (Schlüssel -> Eintrag)
local function byKey(list: any): { [string]: any }
	local out: { [string]: any } = {}
	if type(list) == "table" then
		for _, entry in ipairs(list) do
			if type(entry) == "table" and type(entry.Key) == "string" then
				out[entry.Key] = entry
			end
		end
	end
	return out
end

local ROOMS = byKey(TCFG.Rooms)
local ROOM_LIST: { any } = {}
for _, room in ipairs(if type(TCFG.Rooms) == "table" then TCFG.Rooms else {}) do
	if type(room) == "table" and type(room.Key) == "string" then
		table.insert(ROOM_LIST, room)
	end
end
local STAFF = byKey(TCFG.Staff)
local SKINS = byKey(TCFG.Skins)
local NEONS = byKey(TCFG.Neon)
local STAGES: { any } = if type(TCFG.Stages) == "table" then TCFG.Stages else {}
local CROWNS: { any } = if type(TCFG.Crowns) == "table" then TCFG.Crowns else {}

-- live änderbare Multiplikator-Werte (Config.ApplyLive schreibt in Config.Tower.Mult) – immer frisch lesen
local function mult(key: string, default: number): number
	local m = if type(Config.Tower) == "table" then Config.Tower.Mult else nil
	return if type(m) == "table" and Util.IsFinite(m[key]) then m[key] else default
end

TowerMath.Configure(TCFG)

-- ---------------------------------------------------------------------
-- 2) LAUFZEIT-ZUSTAND (pro Spieler bei PlayerRemoving geleert)
-- ---------------------------------------------------------------------
local runtime: { [Player]: Runtime } = {}
local floorBuiltCallbacks: { (Player, number, number) -> () } = {}
local stageUpCallbacks: { (Player, number) -> () } = {}
local transferCallbacks: { (Player, number, number) -> () } = {}
local comfortCache: { [string]: number } = {}
local comfortCount = 0
local errorLogAt: { [string]: number } = {}

-- serverweite Faktoren (Einheit: Unix-Sekunden)
local serverBoost: { [string]: { Mult: number, Until: number } } = {
	Parade = { Mult = 1, Until = 0 },
	Bell = { Mult = 1, Until = 0 },
}
local eventBoost = { Mult = 1, Until = 0 }
local costEvents: { [string]: { Mult: number, Until: number } } = {
	Floor = { Mult = 1, Until = 0 },
	RoomLevel = { Mult = 1, Until = 0 },
}
local buildEvent = { Mult = 1, Until = 0 }

local function logError(where: string, err: any)
	local now = os.clock()
	if now - (errorLogAt[where] or -math.huge) >= ERROR_LOG_EVERY then
		errorLogAt[where] = now
		warn(PREFIX .. where .. ": " .. tostring(err))
	end
end

-- ---------------------------------------------------------------------
-- 3) DIENSTE (nur zur Laufzeit über Services, optional per pcall)
-- ---------------------------------------------------------------------
local function has(serviceName: string, fnName: string): boolean
	local s = Services and Services[serviceName]
	return type(s) == "table" and type(s[fnName]) == "function"
end

local function call(serviceName: string, fnName: string, ...: any): (boolean, any, any, any)
	local s = Services and Services[serviceName]
	local fn = if type(s) == "table" then s[fnName] else nil
	if type(fn) ~= "function" then
		return false, nil, nil, nil
	end
	local ok, a, b, c = pcall(fn, ...)
	if not ok then
		logError(serviceName .. "." .. fnName, a)
		return false, nil, nil, nil
	end
	return true, a, b, c
end

local function now(): number
	return Clock.Now()
end

local function dataOf(p: Player): { [string]: any }?
	local ok, data = call("DataService", "Get", p)
	if ok and type(data) == "table" and type(data.Tower) == "table" then
		return data
	end
	return nil
end

local function langOf(p: Player): LangCode
	local ok, lang = call("PlayerStateService", "LangOf", p)
	if ok and (lang == "de" or lang == "en") then
		return lang
	end
	return Lang.For(p)
end

local function localize(p: Player, key: string, args: { any }?): string
	local lang = langOf(p)
	if args then
		return Lang.T(lang, key, table.unpack(args))
	end
	return Lang.T(lang, key)
end

local function notify(p: Player, key: string, args: { any }?, kind: Types.NotifyKind?)
	call("PlayerStateService", "Notify", p, key, args, kind)
end

local function markDirty(p: Player, ...: string)
	call("PlayerStateService", "MarkDirty", p, ...)
end

local function fail(p: Player, key: string, args: { any }?): Reply
	return { Ok = false, Message = localize(p, key, args) }
end

local function okReply(p: Player, key: string?, args: { any }?, extra: { [string]: any }?): Reply
	local reply: Reply = (extra or {}) :: any
	reply.Ok = true
	if key then
		reply.Message = localize(p, key, args)
	end
	return reply
end

local function fireAll(list: { any }, ...: any)
	for _, cb in ipairs(list) do
		local args = table.pack(...)
		task.spawn(function()
			local ok, err = pcall(cb, table.unpack(args, 1, args.n))
			if not ok then
				logError("Callback", err)
			end
		end)
	end
end

-- CR-Betrag in der Sprache des Empfängers ("1,25 Mio." / "1.25M")
local function credits(p: Player, n: number): string
	return Format.Credits(n, langOf(p))
end

local function plotOf(p: Player): number?
	local ok, plot = call("PlotService", "PlotOf", p)
	if ok and isInt(plot) then
		return plot
	end
	return nil
end

local function balanceOf(p: Player): number
	local ok, value = call("ShopService", "Balance", p)
	if ok and isNum(value) then
		return value
	end
	return 0
end

local function debit(p: Player, amount: number, sink: string): boolean
	if amount <= 0 then
		return true
	end
	local ok, result = call("ShopService", "Debit", p, amount, sink)
	return ok and result == true
end

local function credit(p: Player, amount: number, source: string): boolean
	if amount <= 0 then
		return true
	end
	local ok, result = call("ShopService", "Credit", p, amount, source)
	return ok and result == true
end

local function hasPass(p: Player, key: string): boolean
	local ok, result = call("MonetizationService", "HasPass", p, key)
	return ok and result == true
end

local function isClub(p: Player): boolean
	local ok, result = call("MonetizationService", "IsClub", p)
	return ok and result == true
end

local function isPremium(p: Player): boolean
	local ok, result = pcall(function()
		return p.MembershipType == Enum.MembershipType.Premium
	end)
	return ok and result == true
end

local function licenceOf(p: Player, data: { [string]: any }): number
	local ok, lic = call("ProgressionService", "Licence", p)
	if ok and isInt(lic) then
		return math.clamp(lic, 1, 10)
	end
	local prog = data.Prog
	if type(prog) == "table" and isInt(prog.Licence) then
		return math.clamp(prog.Licence, 1, 10)
	end
	return 1
end

local function ipoCountOf(p: Player, data: { [string]: any }): number
	local ok, count = call("ProgressionService", "IpoCount", p)
	if ok and isInt(count) then
		return math.max(0, count)
	end
	local prestige = sub(data.Prog, "Prestige")
	return if isInt(prestige.Count) then math.max(0, prestige.Count) else 0
end

-- Vorstand-Stufe über den Perk-Schlüssel aus Config.Tower.Perks ("Growth" -> "Wachstum")
local function perkOf(p: Player, data: { [string]: any }, key: string): number
	local branch = PERKS[key]
	if type(branch) ~= "string" then
		return 0
	end
	local ok, level = call("ProgressionService", "Perk", p, branch)
	if ok and isNum(level) then
		return math.max(0, math.floor(level))
	end
	local perks = sub(sub(data.Prog, "Prestige"), "Perks")
	return if isNum(perks[branch]) then math.max(0, math.floor(perks[branch])) else 0
end

local function licenceTable(): { any }
	local prog = Config.Progression
	if type(prog) == "table" and type(prog.Licences) == "table" and #prog.Licences > 0 then
		return prog.Licences
	end
	local trading = Config.Trading
	if type(trading) == "table" and type(trading.LicenceFallback) == "table" then
		return trading.LicenceFallback
	end
	return {}
end

local function licenceName(lang: LangCode, idx: number): string
	local def = licenceTable()[idx]
	if type(def) == "table" then
		if type(def.Name) == "table" then
			return Lang.Pick(lang, def.Name)
		elseif type(def.Key) == "string" then
			return def.Key
		end
	end
	return "#" .. tostring(idx)
end

-- Bau-Kurs hängt NUR von der Lizenz ab (§B8.3) – nie von Pässen, Boosts oder Tower-Stufe
local function bauKursOf(p: Player, data: { [string]: any }): number
	local ok, def = call("ProgressionService", "LicenceDef", p)
	if ok and type(def) == "table" and isNum(def.BauKurs) and def.BauKurs > 0 then
		return math.clamp(def.BauKurs, 1, 1e6)
	end
	local row = licenceTable()[licenceOf(p, data)]
	if type(row) == "table" and isNum(row.BauKurs) and row.BauKurs > 0 then
		return math.clamp(row.BauKurs, 1, 1e6)
	end
	return 40
end

local function comfortOf(key: string): number
	local cached = comfortCache[key]
	if cached ~= nil then
		return cached
	end
	local ok, result = call("LifestyleService", "Comfort", key)
	if not ok or not isNum(result) then
		return 0 -- nicht merken: LifestyleService kann später verfügbar sein
	end
	local value = math.clamp(result, 0, num(DECOR_FALLBACK.ComfortItemMax, 5))
	if comfortCount < MAX_COMFORT_CACHE then
		comfortCache[key] = value
		comfortCount += 1
	end
	return value
end

local function decorCfg(key: string, default: number): number
	local decor = Config.Decor
	if type(decor) == "table" and isNum(decor[key]) then
		return decor[key]
	end
	return num(DECOR_FALLBACK[key], default)
end

-- Lager-Rückfall ohne LifestyleService (nur damit nie Deko verloren geht; Schema §C12.1 Storage.Decor)
local function returnDecorRaw(data: { [string]: any }, key: string)
	if type(data.Storage) ~= "table" then
		data.Storage = { Decor = {} }
	end
	if type(data.Storage.Decor) ~= "table" then
		data.Storage.Decor = {}
	end
	local decor = data.Storage.Decor
	decor[key] = math.max(0, math.floor(num(decor[key], 0))) + 1
end

-- Kosmetik-Besitz (Fassaden/Neon): Pass, LifestyleService.Owns oder Kosmetik-Liste im Spielstand
local function ownsUnlock(p: Player, data: { [string]: any }, entry: any): boolean
	if type(entry) ~= "table" then
		return false
	end
	if entry.Unlock == "Default" then
		return true
	elseif entry.Unlock == "Pass" then
		return type(entry.Pass) == "string" and hasPass(p, entry.Pass)
	end
	local key = entry.Key
	local ok, owned = call("LifestyleService", "Owns", p, key)
	if ok and owned == true then
		return true
	end
	for _, list in ipairs({ data.Cosmetics, sub(data.Purchases, "Cosmetics") }) do
		if type(list) == "table" then
			if list[key] == true then
				return true
			end
			for _, value in ipairs(list) do
				if value == key then
					return true
				end
			end
		end
	end
	return false
end

-- ---------------------------------------------------------------------
-- 4) SERVERWEITE FAKTOREN
-- ---------------------------------------------------------------------
local function activeMult(entry: { Mult: number, Until: number }, t: number): number
	if entry.Until > t and entry.Mult > 1 then
		return entry.Mult
	end
	return 1
end

local function costEventMult(kind: string, t: number): number
	local entry = costEvents[kind]
	if entry and entry.Until > t then
		return math.clamp(entry.Mult, mult("CostEventMin", 0.1), 1)
	end
	return 1
end

local function buildEventMult(t: number): number
	if buildEvent.Until > t then
		return math.clamp(buildEvent.Mult, 0, 1)
	end
	return 1
end

-- ---------------------------------------------------------------------
-- 5) KERN (reine Daten-Operationen auf data.Tower mit einer Env – auch für TowerTests)
-- ---------------------------------------------------------------------
local Core = {}

function Core.NewFloor(): FloorData
	return { R = DEFAULT_ROOM, L = 1, S = {}, D = {} }
end

function Core.Stage(t: any): number
	return TowerMath.StageOf(if type(t.Floors) == "table" then #t.Floors else 0)
end

function Core.RoomCount(t: any, key: string): number
	local count = 0
	if type(t.Floors) == "table" then
		for _, floor in ipairs(t.Floors) do
			if type(floor) == "table" and floor.R == key then
				count += 1
			end
		end
	end
	return count
end

function Core.DecorSlots(t: any, index: number): number
	local floor = t.Floors[index]
	local room = if type(floor) == "table" then ROOMS[floor.R] else nil
	if room and isInt(room.DecorSlots) then
		return math.floor(decorCfg("PenthouseSlots", room.DecorSlots))
	end
	return math.floor(decorCfg("SlotsPerFloor", 3))
end

-- Deko-Liste auf n Plätze kürzen; überzählige Teile gehen ins Lager
local function trimDecor(floor: FloorData, slots: number, returnFn: (string) -> ())
	for i = #floor.D, slots + 1, -1 do
		local key = floor.D[i]
		if type(key) == "string" and key ~= "" then
			returnFn(key)
		end
		floor.D[i] = nil
	end
	-- leere Plätze am Ende entfernen (JSON-Liste bleibt lückenlos, "" = leerer Platz)
	for i = #floor.D, 1, -1 do
		if floor.D[i] == "" then
			floor.D[i] = nil
		else
			break
		end
	end
end

local function repairFloor(raw: any): FloorData
	if type(raw) ~= "table" then
		return Core.NewFloor()
	end
	local floor: FloorData = {
		R = if type(raw.R) == "string" and ROOMS[raw.R] then raw.R else DEFAULT_ROOM,
		L = if isNum(raw.L) then math.clamp(math.floor(raw.L), 1, 5) else 1,
		S = {},
		D = {},
	}
	if type(raw.S) == "table" then
		for _, key in ipairs(raw.S) do
			local staff = STAFF[key]
			if staff and not staff.Lobby and #floor.S < STAFF_SLOTS_PLUS then
				table.insert(floor.S, key)
			end
		end
	end
	if type(raw.D) == "table" then
		for i, key in ipairs(raw.D) do
			if i > 16 then
				break
			end
			floor.D[i] = if type(key) == "string" and #key <= MAX_DECOR_KEY then key else ""
		end
	end
	return floor
end

-- Turm-Daten reparieren (nach dem Laden). Gibt die Erstattung einer ungültigen Baustelle zurück (CR).
function Core.Repair(data: { [string]: any }): number
	local t = data.Tower
	local refund = 0
	local old = if type(t.Floors) == "table" then t.Floors else {}
	local floors: { FloorData } = {}
	for i, raw in ipairs(old) do
		if i > FLOORS then
			break
		end
		floors[i] = repairFloor(raw)
	end
	if type(t.Floors) ~= "table" then
		t.Floors = {}
	end
	table.clear(t.Floors)
	for i, floor in ipairs(floors) do
		t.Floors[i] = floor
	end
	local count = #t.Floors
	-- Penthouse nur ganz oben; Deko-Plätze passend kürzen
	for i, floor in ipairs(t.Floors) do
		local room = ROOMS[floor.R]
		if room and room.TopOnly and i ~= count then
			floor.R = DEFAULT_ROOM
		end
		trimDecor(floor, Core.DecorSlots(t, i), function(key: string)
			returnDecorRaw(data, key)
		end)
	end
	-- Baustelle
	if type(t.Build) ~= "table" then
		t.Build = {}
	end
	local build = t.Build
	if build.Floor ~= nil then
		local valid = isInt(build.Floor)
			and build.Floor == count + 1
			and build.Floor <= FLOORS
			and isNum(build.Until)
			and isNum(build.Start)
		if not valid then
			if isNum(build.Cost) and build.Cost > 0 then
				refund = TowerMath.Clamp(build.Cost)
			end
			t.Build = {}
		end
	end
	if t.Build.Floor == nil then
		t.Build = {}
		t.Helpers = {}
	end
	local effMax = math.floor(num(sub(TCFG, "Efficiency").Max, 20))
	t.Eff = if isNum(t.Eff) then math.clamp(math.floor(t.Eff), 0, effMax) else 0
	t.Vault = TowerMath.Clamp(num(t.Vault, 0))
	t.RunSpend = TowerMath.Clamp(num(t.RunSpend, 0))
	t.PendingCredits = TowerMath.Clamp(num(t.PendingCredits, 0))
	if type(t.Skin) ~= "string" or SKINS[t.Skin] == nil then
		t.Skin = DEFAULT_SKIN
	end
	if type(t.Neon) ~= "string" or NEONS[t.Neon] == nil then
		t.Neon = DEFAULT_NEON
	end
	if type(t.Crown) ~= "string" then
		t.Crown = ""
	end
	if type(t.Name) ~= "table" then
		t.Name = { A = 1, N = 1 }
	end
	t.Name.A = if isInt(t.Name.A) and t.Name.A >= 1 and t.Name.A <= NAME_ADJ then t.Name.A else 1
	t.Name.N = if isInt(t.Name.N) and t.Name.N >= 1 and t.Name.N <= NAME_NOUN then t.Name.N else 1
	local private: { number } = {}
	local seen: { [number]: boolean } = {}
	if type(t.Private) == "table" then
		for _, floor in ipairs(t.Private) do
			if isInt(floor) and floor >= 1 and floor <= count and not seen[floor] and #private < PRIVATE_MAX then
				seen[floor] = true
				table.insert(private, floor)
			end
		end
	end
	t.Private = private
	local express: { number } = {}
	if type(t.Express) == "table" then
		for _, seconds in ipairs(t.Express) do
			if isNum(seconds) and seconds >= 1 and #express < EXPRESS_MAX then
				table.insert(express, math.clamp(math.floor(seconds), 1, EXPRESS_MAX_SECONDS))
			end
		end
	end
	t.Express = express
	t.Instant = if isNum(t.Instant) then math.clamp(math.floor(t.Instant), 0, INSTANT_MAX) else 0
	t.InstantDay = if isInt(t.InstantDay) then math.max(0, t.InstantDay) else 0
	local helpers: { number } = {}
	if type(t.Helpers) == "table" then
		for _, userId in ipairs(t.Helpers) do
			if isInt(userId) and #helpers < HELP_MAX then
				table.insert(helpers, userId)
			end
		end
	end
	t.Helpers = helpers
	if type(t.Layouts) ~= "table" then
		t.Layouts = {}
	end
	if type(t.KeepLayout) ~= "boolean" then
		t.KeepLayout = true
	end
	if type(t.Janitor) ~= "boolean" then
		t.Janitor = false
	end
	if type(t.Security) ~= "boolean" then
		t.Security = false
	end
	-- Boosts (Rest-Spielsekunden)
	if type(data.Boosts) ~= "table" then
		data.Boosts = { X2 = 0, X5 = 0, Bull = 0 }
	end
	local boostMax = mult("BoostMaxSeconds", 2592000)
	for _, kind in ipairs({ "X2", "X5", "Bull" }) do
		data.Boosts[kind] = math.clamp(num(data.Boosts[kind], 0), 0, boostMax)
	end
	return refund
end

-- Kosten-Faktor: Vorstand "Bau" (−5 %/Stufe) × Bau-Boom (nur Etagen/Raum-Stufen)
function Core.CostFactor(env: Env, kind: string?): number
	local level = math.clamp(env.Perk("Build"), 0, num(IPO.BuildMax, 8))
	local factor = 1 - num(IPO.BuildPct, 0.05) * level
	if kind == "Floor" or kind == "RoomLevel" then
		factor *= env.CostEvent(kind)
	end
	return math.clamp(factor, 0, 1)
end

-- Bauzeit mit Bau-Crew Pro, Vorstand "Tempo", Admin-Bau-Boom (TowerMath klemmt auf ≥ 25 % der Grundzeit)
function Core.BuildSeconds(n: number, env: Env): number
	local speed = 1
	if env.HasPass(BUILD.CrewPass or "BuildCrew") then
		speed *= 1 - num(BUILD.CrewPct, 0.5)
	end
	local tempo = math.clamp(env.Perk("Tempo"), 0, num(BUILD.TempoMax, 5))
	speed *= 1 - num(BUILD.TempoPct, 0.10) * tempo
	speed *= env.BuildEvent
	return TowerMath.BuildSeconds(n, speed)
end

local function stageName(lang: LangCode, stage: number): string
	local entry = STAGES[stage]
	return if type(entry) == "table" then Lang.Pick(lang, entry.Name) else tostring(stage)
end

-- Nächste Etage starten (Tor, CR, Kran frei). Gibt (ok, Fehler-Schlüssel, Argumente, Ergebnis) zurück.
-- Argumente mit Lizenz-/Stufen-Index werden vom Aufrufer lokalisiert (Rückgabe "Gate").
function Core.StartBuild(t: any, env: Env): (boolean, string?, { any }?, { [string]: any }?)
	local n = #t.Floors + 1
	if n > FLOORS then
		return false, "tower.maxFloors", nil, nil
	end
	if t.Build.Floor ~= nil then
		return false, "tower.craneBusy", { math.max(0, math.ceil(num(t.Build.Until, 0) - env.Now)) }, nil
	end
	local licence, ipo = TowerMath.GateFor(n)
	if env.Licence < licence then
		return false, "tower.gateLicence", nil, { Stage = TowerMath.StageOf(n), Licence = licence }
	end
	if env.Ipo < ipo then
		return false, "tower.gateIpo", nil, { Stage = TowerMath.StageOf(n), Ipo = ipo }
	end
	local cost = TowerMath.Discount(TowerMath.FloorCost(n), Core.CostFactor(env, "Floor"))
	if cost > 0 then
		local balance = env.Balance()
		if balance < cost then
			return false, "tower.noCredits", { cost - balance }, nil
		end
		if not env.Debit(cost, "Floor") then
			return false, "tower.noCredits", { cost }, nil
		end
	end
	local seconds = math.max(0, Core.BuildSeconds(n, env))
	t.Build = { Floor = n, Start = env.Now, Until = env.Now + seconds, Total = seconds, Cost = cost }
	t.Helpers = {}
	t.RunSpend = TowerMath.Clamp(t.RunSpend + cost)
	return true, nil, nil, { Floor = n, Cost = cost, Seconds = seconds }
end

-- Fertige Baustelle übernehmen. Gibt (Etage, alte Stufe, neue Stufe) oder nil zurück.
function Core.FinishBuild(t: any, env: Env): (number?, number, number)
	local build = t.Build
	local n = build.Floor
	if not isInt(n) or n ~= #t.Floors + 1 or n > FLOORS then
		t.Build = {}
		t.Helpers = {}
		return nil, Core.Stage(t), Core.Stage(t)
	end
	local oldStage = Core.Stage(t)
	local floor = Core.NewFloor()
	-- Penthouse wandert mit nach oben (nur die oberste Etage darf es sein)
	local top = t.Floors[#t.Floors]
	local topRoom = if top then ROOMS[top.R] else nil
	if top and topRoom and topRoom.TopOnly then
		floor.R = top.R
		floor.D = top.D
		top.R = DEFAULT_ROOM
		top.D = {}
	end
	table.insert(t.Floors, floor)
	t.Build = {}
	t.Helpers = {}
	-- "Layout merken": Deko dieser Etage aus dem letzten Lauf wieder aufstellen
	local layout = if t.KeepLayout then t.Layouts[tostring(n)] else nil
	if type(layout) == "table" and #floor.D == 0 then
		local slots = Core.DecorSlots(t, n)
		for slotIndex = 1, math.min(#layout, slots) do
			local key = layout[slotIndex]
			if type(key) == "string" and key ~= "" and env.TakeDecor(key) then
				floor.D[slotIndex] = key
			elseif floor.D[slotIndex] == nil then
				floor.D[slotIndex] = ""
			end
		end
		trimDecor(floor, slots, env.ReturnDecor)
	end
	return n, oldStage, Core.Stage(t)
end

local function floorAt(t: any, index: any): FloorData?
	if not isInt(index) or index < 1 or index > #t.Floors then
		return nil
	end
	return t.Floors[index]
end

function Core.SetRoom(t: any, env: Env, index: number, key: string): (boolean, string?, { any }?)
	local floor = floorAt(t, index)
	if not floor then
		return false, "tower.noFloor", nil
	end
	local room = ROOMS[key]
	if not room then
		return false, "core.invalid", nil
	end
	if floor.R == key then
		return false, "tower.roomSame", nil
	end
	if Core.Stage(t) < num(room.MinStage, 1) then
		return false, "tower.roomLocked", { room.MinStage }
	end
	if room.TopOnly and index ~= #t.Floors then
		return false, "tower.roomTopOnly", nil
	end
	if isInt(room.Max) and Core.RoomCount(t, key) >= room.Max then
		return false, "tower.roomMax", { room.Max }
	end
	local cost = TowerMath.RoomChangeCost(index)
	if cost > 0 then
		local balance = env.Balance()
		if balance < cost then
			return false, "tower.noCredits", { cost - balance }
		end
		if not env.Debit(cost, "Room") then
			return false, "tower.noCredits", { cost }
		end
	end
	floor.R = key
	trimDecor(floor, Core.DecorSlots(t, index), env.ReturnDecor)
	t.RunSpend = TowerMath.Clamp(t.RunSpend + cost)
	return true, nil, { cost }
end

function Core.LevelUp(t: any, env: Env, index: number): (boolean, string?, { any }?)
	local floor = floorAt(t, index)
	if not floor then
		return false, "tower.noFloor", nil
	end
	if floor.L >= 5 then
		return false, "tower.levelMax", nil
	end
	local cost = TowerMath.Discount(TowerMath.LevelCost(index, floor.L), Core.CostFactor(env, "RoomLevel"))
	local balance = env.Balance()
	if balance < cost then
		return false, "tower.noCredits", { cost - balance }
	end
	if not env.Debit(cost, "RoomLevel") then
		return false, "tower.noCredits", { cost }
	end
	floor.L += 1
	t.RunSpend = TowerMath.Clamp(t.RunSpend + cost)
	return true, nil, { index, floor.L }
end

function Core.StaffSlots(env: Env): number
	return if env.HasPass(TCFG.StaffPass or "StaffPlus") then STAFF_SLOTS_PLUS else STAFF_SLOTS
end

function Core.Hire(t: any, env: Env, index: number, key: string): (boolean, string?, { any }?)
	local staff = STAFF[key]
	if not staff then
		return false, "core.invalid", nil
	end
	if Core.Stage(t) < num(staff.MinStage, 1) then
		return false, "tower.staffLocked", { staff.MinStage }
	end
	if staff.Lobby then
		if t[key] == true then
			return false, "tower.uniqueOwned", nil
		end
		local cost = TowerMath.Discount(TowerMath.StaffCost(0, key), Core.CostFactor(env, nil))
		if cost > 0 then
			local balance = env.Balance()
			if balance < cost then
				return false, "tower.noCredits", { cost - balance }
			end
			if not env.Debit(cost, "Staff") then
				return false, "tower.noCredits", { cost }
			end
		end
		t[key] = true
		t.RunSpend = TowerMath.Clamp(t.RunSpend + cost)
		return true, nil, { 0 }
	end
	local floor = floorAt(t, index)
	if not floor then
		return false, "tower.noFloor", nil
	end
	local slots = Core.StaffSlots(env)
	if #floor.S >= slots then
		return false, if slots < STAFF_SLOTS_PLUS then "tower.slotsPlus" else "tower.slotsFull", { index }
	end
	local cost = TowerMath.Discount(TowerMath.StaffCost(index, key), Core.CostFactor(env, nil))
	local balance = env.Balance()
	if balance < cost then
		return false, "tower.noCredits", { cost - balance }
	end
	if not env.Debit(cost, "Staff") then
		return false, "tower.noCredits", { cost }
	end
	table.insert(floor.S, key)
	t.RunSpend = TowerMath.Clamp(t.RunSpend + cost)
	return true, nil, { index }
end

-- Etage 0 = Lobby: Platz 1 Hausmeister-Bot, Platz 2 Sicherheits-Bot
function Core.Fire(t: any, index: number, slot: number): (boolean, string?, string?)
	if index == 0 then
		local key = if slot == 1 then "Janitor" elseif slot == 2 then "Security" else nil
		if key == nil or t[key] ~= true then
			return false, "tower.noStaff", nil
		end
		t[key] = false
		return true, nil, key
	end
	local floor = floorAt(t, index)
	if not floor then
		return false, "tower.noFloor", nil
	end
	if not isInt(slot) or slot < 1 or slot > #floor.S then
		return false, "tower.noStaff", nil
	end
	local key = table.remove(floor.S, slot)
	return true, nil, key
end

function Core.Efficiency(t: any, env: Env): (boolean, string?, { any }?)
	local max = math.floor(num(sub(TCFG, "Efficiency").Max, 20))
	if t.Eff >= max then
		return false, "tower.effMax", nil
	end
	local cost = TowerMath.Discount(TowerMath.EfficiencyCost(t.Eff), Core.CostFactor(env, nil))
	local balance = env.Balance()
	if balance < cost then
		return false, "tower.noCredits", { cost - balance }
	end
	if not env.Debit(cost, "Efficiency") then
		return false, "tower.noCredits", { cost }
	end
	t.Eff += 1
	t.RunSpend = TowerMath.Clamp(t.RunSpend + cost)
	return true, nil, { t.Eff }
end

-- Deko in einen festen Platz stellen (key) oder entfernen (key = nil/"")
function Core.SetDecor(t: any, env: Env, index: number, slot: number, key: string?): (boolean, string?)
	local floor = floorAt(t, index)
	if not floor then
		return false, "tower.noFloor"
	end
	local slots = Core.DecorSlots(t, index)
	if not isInt(slot) or slot < 1 or slot > slots then
		return false, "core.invalid"
	end
	for i = #floor.D + 1, slot do
		floor.D[i] = ""
	end
	local old = floor.D[slot]
	if key ~= nil and key ~= "" then
		if old == key then
			return false, "tower.decorSame"
		end
		if not env.TakeDecor(key) then
			return false, "tower.decorNone"
		end
		floor.D[slot] = key
	else
		floor.D[slot] = ""
	end
	if type(old) == "string" and old ~= "" then
		env.ReturnDecor(old)
	end
	trimDecor(floor, slots, env.ReturnDecor)
	return true, nil
end

function Core.SetPrivate(t: any, index: number, on: boolean): (boolean, string?, { any }?)
	if not floorAt(t, index) then
		return false, "tower.noFloor", nil
	end
	local position = table.find(t.Private, index)
	if on then
		if position then
			return true, nil, nil
		end
		if #t.Private >= PRIVATE_MAX then
			return false, "tower.privateMax", { PRIVATE_MAX }
		end
		table.insert(t.Private, index)
	elseif position then
		table.remove(t.Private, position)
	end
	return true, nil, nil
end

-- Restzeit der Baustelle um seconds kürzen (Bau-Express) – beendet sie, wenn der Rest reicht
function Core.ApplyExpress(t: any, env: Env, seconds: number): boolean
	if t.Build.Floor == nil then
		return false
	end
	local remaining = num(t.Build.Until, env.Now) - env.Now
	if remaining <= seconds then
		t.Build.Until = env.Now
	else
		t.Build.Until -= seconds
	end
	return true
end

-- Bau-Hilfe: −HelpPct der Restzeit, höchstens HelpMax Helfer je Etage, je Helfer 1×, nie unter MinFactor
function Core.ApplyHelp(t: any, env: Env, helperId: number): (boolean, string?)
	local build = t.Build
	if build.Floor == nil then
		return false, "tower.noBuild"
	end
	local remaining = num(build.Until, env.Now) - env.Now
	if remaining <= 5 then
		return false, "tower.instantNotNeeded"
	end
	if table.find(t.Helpers, helperId) then
		return false, "tower.helpAgain"
	end
	if #t.Helpers >= HELP_MAX then
		return false, "tower.helpFull"
	end
	local floorBase = TowerMath.BuildTime(build.Floor) * num(BUILD.MinFactor, 0.25)
	local earliest = num(build.Start, env.Now) + floorBase
	local target = build.Until - remaining * num(BUILD.HelpPct, 0.10)
	build.Until = math.max(earliest, math.min(build.Until, target))
	table.insert(t.Helpers, helperId)
	return true, nil
end

-- Börsengang-Reset (§B9.6): CR (Start-CR laut Perk, Standard 0), Etagen, Abteilungen, Raum-Stufen, Personal,
-- Effizienz, Baustelle, Tresor starten neu. Bleibt: Depot, Lizenz, Lager (Deko kommt zurück, Layout gemerkt),
-- Fassade/Neon/Name, Token, Boosts, Lobby-Bots. Gibt false zurück, ohne etwas zu ändern, wenn CR nicht abbuchbar.
function Core.ResetForIpo(data: { [string]: any }, env: Env, perks: { [string]: number }?): boolean
	local t = data.Tower
	local perkTable = if type(perks) == "table" then perks else {}
	local startCredits = TowerMath.Clamp(num(perkTable.StartCredits, 0))
	-- 1) CR auf Start-CR (zuerst – schlägt das fehl, bleibt alles unverändert)
	local balance = env.Balance()
	if balance > startCredits then
		local amount = balance - startCredits
		if not env.Debit(amount, "Ipo") and not env.Debit(amount, "Admin") then
			return false
		end
	elseif balance < startCredits then
		env.Credit(startCredits - balance, "Admin")
	end
	-- 2) Layout merken + Deko zurück ins Lager
	local layouts: { [string]: { string } } = {}
	for i, floor in ipairs(t.Floors) do
		local keep: { string } = {}
		local any = false
		for slotIndex, key in ipairs(floor.D) do
			keep[slotIndex] = if type(key) == "string" then key else ""
			if type(key) == "string" and key ~= "" then
				any = true
				env.ReturnDecor(key)
			end
		end
		if any then
			layouts[tostring(i)] = keep
		end
	end
	if t.KeepLayout then
		t.Layouts = layouts
	end
	-- 3) Neustart
	table.clear(t.Floors)
	t.Eff = 0
	t.Vault = 0
	t.Build = {}
	t.Helpers = {}
	t.RunSpend = 0
	t.Private = {}
	t.PendingCredits = 0 -- vorgemerkte CR gehören zum alten Lauf (sonst umgingen sie den CR-Neustart)
	if IPO.KeepLobbyBots == false then
		t.Janitor = false
		t.Security = false
	end
	-- 4) Vorstand "Blitzstart": Start mit 4 / 8 / 12 fertigen Etagen (+ gemerkte Deko)
	local blitzBranch = PERKS.Blitz or "Blitzstart"
	local level = num(perkTable[blitzBranch], num(perkTable.Blitz, env.Perk("Blitz")))
	local blitzList = if type(IPO.Blitz) == "table" then IPO.Blitz else {}
	level = math.clamp(math.floor(level), 0, #blitzList)
	local startFloors = if level > 0 then math.clamp(math.floor(num(blitzList[level], 0)), 0, FLOORS) else 0
	for i = 1, startFloors do
		t.Floors[i] = Core.NewFloor()
	end
	if t.KeepLayout then
		for i = 1, startFloors do
			local layout = t.Layouts[tostring(i)]
			if type(layout) == "table" then
				local floor = t.Floors[i]
				local slots = Core.DecorSlots(t, i)
				for slotIndex = 1, math.min(#layout, slots) do
					local key = layout[slotIndex]
					floor.D[slotIndex] = if type(key) == "string" and key ~= "" and env.TakeDecor(key) then key else ""
				end
				trimDecor(floor, slots, env.ReturnDecor)
			end
		end
	end
	return true
end

-- Admin: Etagenzahl setzen (Baustelle wird erstattet, Deko entfernter Etagen geht ins Lager)
function Core.SetFloors(t: any, env: Env, n: number)
	if t.Build.Floor ~= nil then
		local cost = TowerMath.Clamp(num(t.Build.Cost, 0))
		if cost > 0 then
			env.Credit(cost, "Refund")
		end
		t.Build = {}
		t.Helpers = {}
	end
	local target = math.clamp(math.floor(n), 0, FLOORS)
	while #t.Floors > target do
		local floor = table.remove(t.Floors)
		if floor then
			for _, key in ipairs(floor.D) do
				if type(key) == "string" and key ~= "" then
					env.ReturnDecor(key)
				end
			end
		end
	end
	while #t.Floors < target do
		table.insert(t.Floors, Core.NewFloor())
	end
	-- Penthouse nur oben
	for i, floor in ipairs(t.Floors) do
		local room = ROOMS[floor.R]
		if room and room.TopOnly and i ~= #t.Floors then
			floor.R = DEFAULT_ROOM
			trimDecor(floor, Core.DecorSlots(t, i), env.ReturnDecor)
		end
	end
	local private: { number } = {}
	for _, floor in ipairs(t.Private) do
		if floor <= #t.Floors then
			table.insert(private, floor)
		end
	end
	t.Private = private
end

function Core.ConvertTransfer(akyCents: number, bauKurs: number): number
	if not isNum(akyCents) or not isNum(bauKurs) or akyCents <= 0 or bauKurs <= 0 then
		return 0
	end
	return TowerMath.Clamp(math.floor(akyCents * bauKurs / 100))
end

-- Gewinn-Transfer-Fluss (§B8.2): AKY verlassen das Depot NUR über withdraw (OrderService.Withdraw, Cent),
-- werden zum Bau-Kurs der Lizenz in CR umgerechnet und gutgeschrieben (sonst vorgemerkt, nie zurück ins Depot).
-- Gibt (Cent, CR, Grund-Schlüssel) zurück.
function Core.Transfer(
	withdraw: () -> (any, any),
	bauKurs: number,
	creditFn: (amount: number) -> boolean,
	pend: (amount: number) -> ()
): (number, number, string?)
	local cents, why = withdraw()
	local akyCents = if isNum(cents) then math.max(0, math.floor(cents)) else 0
	if akyCents <= 0 then
		return 0, 0, if type(why) == "string" then why else "trade.transferNone"
	end
	local amount = Core.ConvertTransfer(akyCents, bauKurs)
	if amount > 0 and not creditFn(amount) then
		pend(amount)
	end
	return akyCents, amount, nil
end

-- ---------------------------------------------------------------------
-- 6) MULTIPLIKATOR-TEILE (§B5.2)
-- ---------------------------------------------------------------------
export type Factors = {
	Eff: number,
	Ipo: number,
	Growth: number,
	Album: number,
	Friends: number,
	Respekt: number,
	Marketing: number,
	Penthouse: boolean,
	Trader: { { Key: string, Value: number } },
	Pass: number,
	Fixed: { { Key: string, Value: number } },
	Boost: { Key: string, Value: number, Until: number, Source: string }?,
	Server: { Key: string, Value: number, Until: number }?,
	Event: { Value: number, Until: number? }?,
}

local function addPart(
	parts: { MultPart },
	key: string,
	value: number,
	group: "Perm" | "Trader" | "Pass" | "Fixed" | "Timed",
	source: "Earned" | "Skill" | "Bought" | "Event",
	untilT: number?
)
	if not isNum(value) then
		return
	end
	if group == "Perm" and value <= 0 then
		return
	end
	if group ~= "Perm" and value <= 1 + 1e-9 then
		return
	end
	table.insert(parts, { Key = key, Value = value, Group = group, Source = source, Until = untilT })
end

-- social = Freunde/Respekt einrechnen (nur in der Sitzung), timed = Zeitlich einrechnen
function Core.BuildParts(f: Factors, social: boolean, timed: boolean): { MultPart }
	local parts: { MultPart } = {}
	local effStep = num(sub(TCFG, "Efficiency").Step, 0.10)
	addPart(parts, "Efficiency", effStep * f.Eff, "Perm", "Earned")
	addPart(parts, "Ipo", mult("IpoStep", 0.25) * math.min(f.Ipo, mult("IpoMax", 20)), "Perm", "Earned")
	addPart(parts, "Growth", mult("GrowthStep", 0.10) * math.min(f.Growth, mult("GrowthMax", 10)), "Perm", "Earned")
	addPart(parts, "Album", mult("AlbumStep", 0.02) * math.min(f.Album, mult("AlbumMax", 6)), "Perm", "Earned")
	if social then
		addPart(
			parts,
			"Friends",
			mult("FriendStep", 0.10) * math.min(f.Friends, mult("FriendMax", 4)),
			"Perm",
			"Earned"
		)
		addPart(
			parts,
			"Respekt",
			mult("RespektStep", 0.01) * math.min(f.Respekt, mult("RespektMax", 20)),
			"Perm",
			"Earned"
		)
	end
	local marketing = ROOMS.Marketing
	if marketing then
		local count = math.min(f.Marketing, num(marketing.Max, 3))
		addPart(parts, "Marketing", num(marketing.IncomePct, 0.05) * count, "Perm", "Earned")
	end
	local penthouse = ROOMS.Penthouse
	if penthouse and f.Penthouse then
		addPart(parts, "Penthouse", num(penthouse.IncomePct, 0.10), "Perm", "Earned")
	end
	for _, entry in ipairs(f.Trader) do
		addPart(parts, entry.Key, entry.Value, "Trader", "Skill")
	end
	if f.Pass >= 4 - 1e-9 and f.Pass <= 4 + 1e-9 then
		-- beide Pässe: EINE ehrliche Zeile "Einkommens-Pässe ×4" (x2 + x3 = x4, nie ×2 und ×3 nebeneinander)
		addPart(parts, "Passes", 4, "Pass", "Bought")
	elseif f.Pass >= 3 - 1e-9 and f.Pass <= 3 + 1e-9 then
		addPart(parts, "Income3x", 3, "Pass", "Bought")
	elseif f.Pass >= 2 - 1e-9 and f.Pass <= 2 + 1e-9 then
		addPart(parts, "Income2x", 2, "Pass", "Bought")
	else
		addPart(parts, "Passes", f.Pass, "Pass", "Bought")
	end
	for _, entry in ipairs(f.Fixed) do
		addPart(parts, entry.Key, entry.Value, "Fixed", "Bought")
	end
	if timed then
		local boost = f.Boost
		if boost then
			addPart(parts, boost.Key, boost.Value, "Timed", boost.Source :: any, boost.Until)
		end
		local server = f.Server
		if server then
			addPart(parts, server.Key, server.Value, "Timed", "Event", server.Until)
		end
		local event = f.Event
		if event then
			addPart(parts, "Event", math.min(event.Value, mult("EventMax", 3)), "Timed", "Event", event.Until)
		end
	end
	return parts
end

-- Stärkster aktiver persönlicher Boost (x5 vor x2 vor Bullen-Bonus; die anderen pausieren)
local function activeBoostKind(data: { [string]: any }): (string?, number)
	local events = Config.Events
	if type(events) == "table" and events.BoostPause == true then
		return nil, 1
	end
	local boosts = data.Boosts
	if type(boosts) ~= "table" then
		return nil, 1
	end
	local best: string? = nil
	local bestValue = 1
	for _, kind in ipairs({ "X5", "X2", "Bull" }) do
		if num(boosts[kind], 0) > 0 then
			local value = mult(kind, if kind == "X5" then 5 elseif kind == "X2" then 2 else 1.5)
			if value > bestValue then
				best, bestValue = kind, value
			end
		end
	end
	return best, bestValue
end

local function traderEntries(p: Player): { { Key: string, Value: number } }
	local ok, total, licPart, rufPart = call("ProgressionService", "TraderFactor", p)
	if not ok or not isNum(total) or total < 1 then
		return {}
	end
	if isNum(licPart) and isNum(rufPart) then
		if licPart >= 1 and rufPart >= 1 and math.abs(licPart * rufPart - total) < 1e-6 then
			return { { Key = "Licence", Value = licPart }, { Key = "Ruf", Value = rufPart } }
		end
		if licPart >= 0 and rufPart >= 0 and math.abs((1 + licPart) * (1 + rufPart) - total) < 1e-6 then
			return { { Key = "Licence", Value = 1 + licPart }, { Key = "Ruf", Value = 1 + rufPart } }
		end
	end
	return { { Key = "Licence", Value = math.min(total, 10) } }
end

local function fixedEntries(p: Player): { { Key: string, Value: number } }
	local premium = isPremium(p)
	local ok, factor = call("MonetizationService", "FixedFactor", p)
	if not ok or not isNum(factor) then
		-- ohne Shop-Dienst zählt nur Roblox Premium
		return if premium then { { Key = "Premium", Value = mult("Premium", 1.10) } } else {}
	end
	local entries: { { Key: string, Value: number } } = {}
	local product = 1
	if hasPass(p, "VIP") then
		table.insert(entries, { Key = "Vip", Value = mult("Vip", 1.10) })
		product *= mult("Vip", 1.10)
	end
	if isClub(p) then
		table.insert(entries, { Key = "Club", Value = mult("Club", 1.15) })
		product *= mult("Club", 1.15)
	end
	if premium then
		table.insert(entries, { Key = "Premium", Value = mult("Premium", 1.10) })
		product *= mult("Premium", 1.10)
	end
	if math.abs(product - factor) < 1e-6 then
		return entries
	end
	-- Aufteilung passt nicht zur Wahrheit von WP10 -> eine Zeile mit dem echten Faktor
	return if factor > 1 then { { Key = "Fixed", Value = math.min(factor, 10) } } else {}
end

local function passFactorOf(p: Player): number
	local ok, factor = call("MonetizationService", "PassFactor", p)
	if ok and isNum(factor) then
		return math.clamp(factor, 1, 4)
	end
	return TowerMath.PassFactor(hasPass(p, "Income2x"), hasPass(p, "Income3x"))
end

local function gatherFactors(p: Player, data: { [string]: any }, t: number): Factors
	local tower = data.Tower
	local okAlbum, album = call("ProgressionService", "AlbumSets", p)
	local okFriends, friends = call("CommunityService", "FriendsInServer", p)
	local okRespekt, respekt = call("CommunityService", "RespektActive", p)
	local count = #tower.Floors
	local top = tower.Floors[count]
	local factors: Factors = {
		Eff = tower.Eff,
		Ipo = ipoCountOf(p, data),
		Growth = perkOf(p, data, "Growth"),
		Album = if okAlbum and isNum(album) then math.max(0, math.floor(album)) else 0,
		Friends = if okFriends and isNum(friends) then math.max(0, math.floor(friends)) else 0,
		Respekt = if okRespekt and isNum(respekt) then math.max(0, math.floor(respekt)) else 0,
		Marketing = Core.RoomCount(tower, "Marketing"),
		Penthouse = top ~= nil and ROOMS[top.R] ~= nil and ROOMS[top.R].TopOnly == true,
		Trader = traderEntries(p),
		Pass = passFactorOf(p),
		Fixed = fixedEntries(p),
		Boost = nil,
		Server = nil,
		Event = nil,
	}
	local kind, value = activeBoostKind(data)
	if kind then
		factors.Boost = {
			Key = kind,
			Value = value,
			Until = math.floor(t + num(data.Boosts[kind], 0)),
			Source = if kind == "Bull" then "Event" else "Bought",
		}
	end
	local parade = activeMult(serverBoost.Parade, t)
	local bell = activeMult(serverBoost.Bell, t)
	if parade > 1 or bell > 1 then
		if parade >= bell then
			factors.Server = { Key = "Parade", Value = parade, Until = serverBoost.Parade.Until }
		else
			factors.Server = { Key = "BellMoment", Value = bell, Until = serverBoost.Bell.Until }
		end
	end
	local eventValue = activeMult(eventBoost, t)
	local eventUntil = eventBoost.Until
	local okEvent, pulled = call("EventService", "EventMult")
	if okEvent and isNum(pulled) and pulled > eventValue then
		eventValue = pulled
		eventUntil = 0
	end
	eventValue = math.clamp(eventValue, 1, mult("EventMax", 3))
	if eventValue > 1 then
		factors.Event = { Value = eventValue, Until = if eventUntil > t then eventUntil else nil }
	end
	return factors
end

-- ---------------------------------------------------------------------
-- 7) EINKOMMEN, TRESOR
-- ---------------------------------------------------------------------
local function newRuntime(): Runtime
	return {
		Base = 0,
		BaseDirty = true,
		Info = nil,
		InfoAt = -math.huge,
		InfoSig = "",
		VaultCap = 0,
		VaultFrac = 0,
		VaultFullNotified = false,
		JanitorAcc = 0,
		AutoAcc = 0,
		SlowAcc = 0,
		JoinClock = os.clock(),
		JoinUnix = Clock.Now(),
		Settled = false,
		Welcome = nil,
		StageToastAt = -math.huge,
		MaxMoneyAt = -math.huge,
		AutoDirtyAt = -math.huge,
		Repaired = false,
	}
end

local function comfortCtx(): TowerMath.Ctx
	return {
		Comfort = comfortOf,
		ComfortPct = decorCfg("ComfortPct", 0.005),
		ComfortMax = decorCfg("ComfortMax", 0.10),
	}
end

local function baseOf(rt: Runtime, tower: any): number
	if rt.BaseDirty then
		rt.Base = TowerMath.BaseIncome(tower.Floors, comfortCtx())
		rt.BaseDirty = false
	end
	return rt.Base
end

local function emptyInfo(): IncomeInfo
	return { PerSec = 0, Steady = 0, Mult = 1, Parts = {} }
end

local function infoSignature(info: IncomeInfo): string
	local pieces = { string.format("%.6g|%.6g", info.PerSec, info.Mult) }
	for _, part in ipairs(info.Parts) do
		table.insert(pieces, part.Key .. "=" .. string.format("%.4g", part.Value) .. "@" .. tostring(part.Until or ""))
	end
	return table.concat(pieces, ",")
end

local function computeInfo(p: Player, data: { [string]: any }, rt: Runtime, t: number): IncomeInfo
	local base = baseOf(rt, data.Tower)
	local parts = Core.BuildParts(gatherFactors(p, data, t), true, true)
	local total, steady = TowerMath.Multiplier(parts :: any)
	return {
		PerSec = math.min(base * total, MAX_MONEY),
		Steady = math.min(base * steady, MAX_MONEY),
		Mult = total,
		Parts = parts,
	}
end

local function vaultCapOf(data: { [string]: any }, info: IncomeInfo): number
	return TowerMath.VaultCap(info.PerSec, Core.RoomCount(data.Tower, "Vault"))
end

-- Einkommen holen/aktualisieren; markiert Income (und Tower bei neuer Tresor-Kapazität) bei Änderung
local function refreshIncome(p: Player, data: { [string]: any }, rt: Runtime, force: boolean): IncomeInfo
	local clockNow = os.clock()
	local info = rt.Info
	if info and not force and not rt.BaseDirty and clockNow - rt.InfoAt < PARTS_REFRESH then
		return info
	end
	local fresh = computeInfo(p, data, rt, now())
	rt.Info = fresh
	rt.InfoAt = clockNow
	local sig = infoSignature(fresh)
	if sig ~= rt.InfoSig then
		rt.InfoSig = sig
		markDirty(p, "Income")
	end
	local cap = vaultCapOf(data, fresh)
	if math.abs(cap - rt.VaultCap) > math.max(1, rt.VaultCap * 0.001) then
		rt.VaultCap = cap
		markDirty(p, "Tower")
	end
	return fresh
end

local function invalidate(p: Player)
	local rt = runtime[p]
	if rt then
		rt.BaseDirty = true
		rt.InfoAt = -math.huge
	end
end

-- Dauer-Einkommen für die Offline-Abrechnung: ohne Zeitlich, ohne Freunde-/Respekt-Anteil (§B5.2)
local function offlineSteady(p: Player, data: { [string]: any }, rt: Runtime): number
	local base = baseOf(rt, data.Tower)
	local parts = Core.BuildParts(gatherFactors(p, data, now()), false, false)
	local _, steady = TowerMath.Multiplier(parts :: any)
	return math.min(base * steady, MAX_MONEY)
end

local function effect(p: Player, name: string, strength: number, payload: any)
	call("PlayerStateService", "Effect", p, name, strength, payload)
end

local function effectAll(name: string, strength: number, payload: any)
	call("PlayerStateService", "EffectAll", name, strength, payload)
end

local function track(p: Player, kind: string, amount: number, ctx: { [string]: any }?)
	call("RewardService", "Track", p, kind, amount, ctx)
end

local function funnel(p: Player, step: number, name: string)
	call("MetricsService", "Funnel", p, step, name)
end

-- CR gutschreiben; gelingt das nicht (Dienst fehlt/Deckel), wird es vorgemerkt und später nachgebucht
local function creditOrPend(p: Player, data: { [string]: any }, amount: number, source: string): boolean
	if amount <= 0 then
		return true
	end
	if credit(p, amount, source) then
		return true
	end
	local tower = data.Tower
	tower.PendingCredits = TowerMath.Clamp(num(tower.PendingCredits, 0) + amount)
	return false
end

-- Tresor leeren -> CR. Gibt den gutgeschriebenen Betrag zurück.
local function collectVault(p: Player, data: { [string]: any }, rt: Runtime, manual: boolean): number
	local tower = data.Tower
	local amount = TowerMath.Clamp(tower.Vault)
	if amount <= 0 then
		return 0
	end
	if not has("ShopService", "Credit") then
		return 0
	end
	local room = math.max(0, MAX_MONEY - balanceOf(p))
	local take = math.min(amount, math.floor(room))
	if take <= 0 then
		if os.clock() - rt.MaxMoneyAt > 60 then
			rt.MaxMoneyAt = os.clock()
			notify(p, "tower.maxMoney", nil, "Alarm")
		end
		return 0
	end
	if not credit(p, take, "Vault") then
		return 0
	end
	tower.Vault = TowerMath.Clamp(tower.Vault - take)
	rt.VaultFullNotified = false
	if type(data.Stats) == "table" then
		data.Stats.Collected = TowerMath.Clamp(num(data.Stats.Collected, 0) + take)
	end
	if take < amount and os.clock() - rt.MaxMoneyAt > 60 then
		rt.MaxMoneyAt = os.clock()
		notify(p, "tower.maxMoney", nil, "Alarm")
	end
	track(p, "Collect", 1, { Amount = take, Manual = manual })
	if manual then
		funnel(p, 5, "FirstCollect")
		markDirty(p, "Tower")
	elseif os.clock() - rt.AutoDirtyAt >= AUTO_STATE_EVERY then
		rt.AutoDirtyAt = os.clock()
		markDirty(p, "Tower")
	end
	return take
end

local function fillVault(p: Player, data: { [string]: any }, rt: Runtime, info: IncomeInfo, dt: number)
	local tower = data.Tower
	local cap = rt.VaultCap
	if cap <= 0 then
		cap = vaultCapOf(data, info)
		rt.VaultCap = cap
	end
	if tower.Vault >= cap then
		rt.VaultFrac = 0
		if not rt.VaultFullNotified and cap > 0 then
			rt.VaultFullNotified = true
			notify(p, "tower.vaultFull", nil, "Info")
			markDirty(p, "Tower")
		end
		return
	end
	rt.VaultFrac += info.PerSec * dt
	local add = math.floor(rt.VaultFrac)
	if add <= 0 then
		return
	end
	rt.VaultFrac -= add
	tower.Vault = TowerMath.Clamp(math.min(cap, tower.Vault + add))
end

-- ---------------------------------------------------------------------
-- 8) STATE (§C10)
-- ---------------------------------------------------------------------
local function crownFor(ipos: number): string
	local key = ""
	for _, crown in ipairs(CROWNS) do
		if type(crown) == "table" and isNum(crown.Ipos) and ipos >= crown.Ipos then
			key = crown.Key
		end
	end
	return key
end

-- Krone (Silber/Gold/Platin/Holo/Orbit) folgt der Zahl der Börsengänge; Data.Tower.Crown für TowerVisualService
local function syncCrown(p: Player, data: { [string]: any })
	local tower = data.Tower
	local crown = crownFor(ipoCountOf(p, data))
	if tower.Crown ~= crown then
		tower.Crown = crown
		call("TowerVisualService", "Rebuild", p)
		markDirty(p, "Tower")
	end
end

local function towerState(p: Player): { [string]: any }
	local data = dataOf(p)
	if not data then
		return {
			Floors = 0,
			Stage = 1,
			Vault = 0,
			VaultCap = 0,
			Build = {},
			Eff = 0,
			Skin = DEFAULT_SKIN,
			Neon = DEFAULT_NEON,
			Name = { A = 1, N = 1 },
			Private = {},
			Tokens = { Express = 0, Instant = 0, ExpressSeconds = {} },
			CostEvent = { Floor = 1, RoomLevel = 1, Until = 0 },
			List = {},
		}
	end
	local tower = data.Tower
	local rt = runtime[p]
	local t = now()
	local count = #tower.Floors
	local list = {}
	for i, floor in ipairs(tower.Floors) do
		list[i] = { R = floor.R, L = floor.L, S = table.clone(floor.S), D = table.clone(floor.D) }
	end
	local build = tower.Build
	local nextFloor = count + 1
	local env = TowerService._Env(p, data)
	local nextInfo: { [string]: any } = { Floor = nextFloor }
	if nextFloor <= FLOORS then
		local licence, ipo = TowerMath.GateFor(nextFloor)
		nextInfo.Cost = TowerMath.Discount(TowerMath.FloorCost(nextFloor), Core.CostFactor(env, "Floor"))
		nextInfo.Income = TowerMath.FloorIncome(nextFloor)
		nextInfo.Seconds = Core.BuildSeconds(nextFloor, env)
		nextInfo.Stage = TowerMath.StageOf(nextFloor)
		nextInfo.Licence = licence
		nextInfo.Ipo = ipo
		if env.Licence < licence then
			nextInfo.Locked = "tower.gateLicence"
		elseif env.Ipo < ipo then
			nextInfo.Locked = "tower.gateIpo"
		end
	else
		nextInfo.Locked = "tower.maxFloors"
	end
	local floorEvent = costEventMult("Floor", t)
	local levelEvent = costEventMult("RoomLevel", t)
	local eventUntil = math.max(
		if floorEvent < 1 then costEvents.Floor.Until else 0,
		if levelEvent < 1 then costEvents.RoomLevel.Until else 0
	)
	local effMax = math.floor(num(sub(TCFG, "Efficiency").Max, 20))
	return {
		Floors = count,
		Stage = Core.Stage(tower),
		Vault = tower.Vault,
		VaultCap = if rt then rt.VaultCap else 0,
		Build = if build.Floor ~= nil
			then {
				Floor = build.Floor,
				Until = build.Until,
				Start = build.Start,
				Total = build.Total,
				Helpers = #tower.Helpers,
			}
			else {},
		Eff = tower.Eff,
		EffCost = if tower.Eff < effMax
			then TowerMath.Discount(TowerMath.EfficiencyCost(tower.Eff), Core.CostFactor(env, nil))
			else 0,
		Skin = tower.Skin,
		Neon = tower.Neon,
		Crown = tower.Crown,
		Name = { A = tower.Name.A, N = tower.Name.N },
		Private = table.clone(tower.Private),
		Tokens = { Express = #tower.Express, Instant = tower.Instant, ExpressSeconds = table.clone(tower.Express) },
		CostEvent = { Floor = floorEvent, RoomLevel = levelEvent, Until = eventUntil },
		List = list,
		Next = nextInfo,
		StaffSlots = Core.StaffSlots(env),
		CostFactor = Core.CostFactor(env, nil),
		Janitor = tower.Janitor,
		Security = tower.Security,
		KeepLayout = tower.KeepLayout,
		RunSpend = tower.RunSpend,
		Pending = tower.PendingCredits,
		Offline = if rt and rt.Welcome then rt.Welcome else nil,
	}
end

local function incomeState(p: Player): IncomeInfo
	local data = dataOf(p)
	local rt = runtime[p]
	if not data or not rt then
		return emptyInfo()
	end
	local info = rt.Info
	if info then
		return info
	end
	return refreshIncome(p, data, rt, true)
end

-- ---------------------------------------------------------------------
-- 9) ENV FÜR ECHTE SPIELER
-- ---------------------------------------------------------------------
function TowerService._Env(p: Player, data: { [string]: any }): Env
	local t = now()
	local lifestyle = has("LifestyleService", "TakeDecor") and has("LifestyleService", "ReturnDecor")
	return {
		Now = t,
		Licence = licenceOf(p, data),
		Ipo = ipoCountOf(p, data),
		Perk = function(key: string): number
			return perkOf(p, data, key)
		end,
		HasPass = function(key: string): boolean
			return hasPass(p, key)
		end,
		Balance = function(): number
			return balanceOf(p)
		end,
		Debit = function(amount: number, sink: string): boolean
			return debit(p, amount, sink)
		end,
		Credit = function(amount: number, source: string): boolean
			return creditOrPend(p, data, amount, source)
		end,
		TakeDecor = function(key: string): boolean
			if not lifestyle then
				return false
			end
			local ok, result = call("LifestyleService", "TakeDecor", p, key)
			return ok and result == true
		end,
		ReturnDecor = function(key: string)
			if lifestyle then
				local ok = call("LifestyleService", "ReturnDecor", p, key)
				if ok then
					return
				end
			end
			returnDecorRaw(data, key)
		end,
		Comfort = comfortOf,
		Owns = function(entry: any): boolean
			return ownsUnlock(p, data, entry)
		end,
		BuildEvent = buildEventMult(t),
		CostEvent = function(kind: string): number
			return costEventMult(kind, t)
		end,
	}
end

-- ---------------------------------------------------------------------
-- 10) BAUEN, FERTIGSTELLEN, VISUALS
-- ---------------------------------------------------------------------
local function visual(fnName: string, ...: any)
	call("TowerVisualService", fnName, ...)
end

local function plotPayload(p: Player, extra: { [string]: any }): { [string]: any }
	extra.Plot = plotOf(p) or 0
	extra.UserId = p.UserId
	return extra
end

local function setTowerAttributes(p: Player, data: { [string]: any })
	local tower = data.Tower
	pcall(function()
		p:SetAttribute("TowerName", string.format("%d:%d", tower.Name.A, tower.Name.N))
	end)
end

local function announceStage(p: Player, stage: number, rt: Runtime)
	local cooldown = num(TCFG.StageToastCooldown, 90)
	if os.clock() - rt.StageToastAt < cooldown then
		return
	end
	rt.StageToastAt = os.clock()
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= p then
			local lang = langOf(other)
			notify(other, "tower.stageAnnounce", { p.DisplayName, stage, stageName(lang, stage) }, "Event")
		end
	end
end

local function onFloorFinished(
	p: Player,
	data: { [string]: any },
	floor: number,
	oldStage: number,
	newStage: number,
	whileAway: boolean
)
	local tower = data.Tower
	local rt = runtime[p]
	-- erster Bau des Kontos: Tresor vorgefüllt (Tutorial "Erstes Sammeln")
	if type(data.Stats) == "table" then
		if num(data.Stats.FloorsBuilt, 0) <= 0 then
			tower.Vault = math.max(tower.Vault, math.floor(num(TCFG.VaultPrefill, 300)))
		end
		data.Stats.FloorsBuilt = math.floor(num(data.Stats.FloorsBuilt, 0)) + 1
	end
	local before = if rt then rt.Base else 0
	invalidate(p)
	local gain = 0
	if rt then
		local info = refreshIncome(p, data, rt, true)
		gain = math.max(0, (rt.Base - before) * info.Mult)
	end
	visual("FloorAdded", p, floor)
	effectAll("BuildDone", 1, plotPayload(p, { Floor = floor, Stage = newStage, Amount = gain }))
	call("PlayerStateService", "SetLeaderstat", p, "Etagen", #tower.Floors)
	track(p, "BuildFloor", 1, { Floor = floor })
	if floor == 1 then
		funnel(p, 4, "Floor1")
	end
	fireAll(floorBuiltCallbacks, p, floor, newStage)
	if newStage > oldStage then
		effectAll("StageUp", 1, plotPayload(p, { Floor = floor, Stage = newStage, Amount = 0 }))
		call("MetricsService", "Progression", p, "TowerStage", "Complete", newStage)
		if newStage == 3 then
			funnel(p, 8, "Stage3")
		end
		if rt then
			announceStage(p, newStage, rt)
		end
		fireAll(stageUpCallbacks, p, newStage)
	end
	if rt and whileAway then
		-- während der Abwesenheit fertig gewordener Bau -> Willkommen-Bericht ("fertige Bauten")
		local welcome = rt.Welcome or {}
		welcome.Built = floor
		rt.Welcome = welcome
	end
	markDirty(p, "Tower", "Income")
end

local function finishBuild(p: Player, data: { [string]: any })
	local env = TowerService._Env(p, data)
	local rt = runtime[p]
	local whileAway = rt ~= nil and num(data.Tower.Build.Until, math.huge) <= rt.JoinUnix
	local floor, oldStage, newStage = Core.FinishBuild(data.Tower, env)
	if floor then
		onFloorFinished(p, data, floor, oldStage, newStage, whileAway)
	else
		markDirty(p, "Tower")
	end
end

-- ---------------------------------------------------------------------
-- 11) GEWINN-TRANSFER (§B8.2) – nur AKY -> CR
-- ---------------------------------------------------------------------
function TowerService.Transfer(p: Player, reason: "Manual" | "Bell" | "Offline"): (number, string?)
	local data = dataOf(p)
	if not data then
		return 0, "core.loading"
	end
	if not has("ShopService", "Credit") then
		return 0, "tower.shopMissing"
	end
	if not has("OrderService", "Withdraw") then
		return 0, "core.error"
	end
	local akyCents, amount, why = Core.Transfer(
		function(): (any, any)
			local ok, cents, reasonKey = call("OrderService", "Withdraw", p, reason)
			if not ok then
				return 0, "core.error"
			end
			return cents, reasonKey
		end,
		bauKursOf(p, data),
		function(value: number): boolean
			return credit(p, value, "Transfer")
		end,
		function(value: number)
			local tower = data.Tower
			tower.PendingCredits = TowerMath.Clamp(num(tower.PendingCredits, 0) + value)
		end
	)
	if akyCents <= 0 then
		return 0, why
	end
	fireAll(transferCallbacks, p, akyCents, amount)
	track(p, "Transfer", 1, { Credits = amount, Reason = reason })
	funnel(p, 7, "FirstTransfer")
	effect(p, "TransferTube", 1, plotPayload(p, { Amount = amount }))
	local rt = runtime[p]
	if rt and reason ~= "Manual" and os.clock() - rt.JoinClock < WELCOME_WINDOW then
		local welcome = rt.Welcome or {}
		welcome.Transfer = num(welcome.Transfer, 0) + amount
		rt.Welcome = welcome
	end
	markDirty(p, "Tower")
	return amount, nil
end

local function onBell(p: Player)
	if not dataOf(p) then
		return
	end
	local amount = TowerService.Transfer(p, "Bell")
	if amount > 0 then
		notify(p, "tower.transferBell", { credits(p, amount) }, "Success")
	end
end

-- ---------------------------------------------------------------------
-- 12) OFFLINE-ABRECHNUNG & TAGES-TOKEN
-- ---------------------------------------------------------------------
local function grantDailyToken(p: Player, data: { [string]: any })
	local tower = data.Tower
	local today = Util.UtcDay()
	if tower.InstantDay >= today then
		return
	end
	local daily = math.floor(num(BUILD.DailyInstant, 1))
	tower.InstantDay = today
	if daily > 0 and tower.Instant < INSTANT_MAX then
		tower.Instant = math.min(INSTANT_MAX, tower.Instant + daily)
		notify(p, "tower.dailyToken", nil, "Info")
		markDirty(p, "Tower")
	end
end

local function settleOffline(p: Player, data: { [string]: any }, rt: Runtime)
	if rt.Settled then
		return
	end
	rt.Settled = true
	local ok, savedAt = call("DataService", "LastSavedAt", p)
	if not ok or not isNum(savedAt) or savedAt <= 0 then
		return -- neues Konto
	end
	local away = os.time() - savedAt
	if away < num(OFFLINE.MinAway, 60) then
		return
	end
	local tresor = perkOf(p, data, "Vault")
	local passKey = OFFLINE.Pass or "OfflineVault"
	local vaultPass = hasPass(p, passKey)
	local rate = TowerMath.OfflineRate(tresor, vaultPass)
	local cap = TowerMath.OfflineCap(tresor, Core.RoomCount(data.Tower, "Lounge"), isClub(p), vaultPass)
	local steady = offlineSteady(p, data, rt)
	local amount = TowerMath.Offline(steady, away, rate, cap)
	local welcome = rt.Welcome or {}
	welcome.Seconds = math.min(away, cap)
	welcome.Away = away
	welcome.Rate = rate
	welcome.Cap = cap
	welcome.Amount = amount
	welcome.At = os.time()
	rt.Welcome = welcome
	if amount > 0 then
		creditOrPend(p, data, amount, "Offline")
		notify(p, "tower.offline", { credits(p, amount) }, "Success")
	end
	markDirty(p, "Tower")
end

-- ---------------------------------------------------------------------
-- 13) TAKT (1 Hz, ein Batch für alle Spieler)
-- ---------------------------------------------------------------------
local function tickBoosts(p: Player, data: { [string]: any }, dt: number)
	local kind = activeBoostKind(data)
	if not kind then
		return
	end
	local boosts = data.Boosts
	local before = num(boosts[kind], 0)
	local after = math.max(0, before - dt)
	boosts[kind] = after
	if after <= 0 then
		invalidate(p)
		markDirty(p, "Boosts", "Income")
		-- ehrliche Rückmeldung (kein Kauf-Hinweis): welcher Boost endet, läuft ein pausierter weiter?
		local lang = langOf(p)
		local function label(k: string): string
			return Format.Mult(mult(k, if k == "X5" then 5 elseif k == "X2" then 2 else 1.5), lang)
		end
		local nextKind = activeBoostKind(data)
		if nextKind then
			notify(
				p,
				"tower.boostResumed",
				{ label(kind), label(nextKind), Format.Duration(num(boosts[nextKind], 0), lang) },
				"Info"
			)
		else
			notify(p, "tower.boostEnded", { label(kind) }, "Info")
		end
	elseif math.floor(before / 30) ~= math.floor(after / 30) then
		markDirty(p, "Boosts")
	end
end

local function retryPending(p: Player, data: { [string]: any })
	local tower = data.Tower
	local pending = TowerMath.Clamp(num(tower.PendingCredits, 0))
	if pending <= 0 or not has("ShopService", "Credit") then
		return
	end
	local room = math.max(0, math.floor(MAX_MONEY - balanceOf(p)))
	local take = math.min(pending, room)
	if take > 0 and credit(p, take, "Refund") then
		tower.PendingCredits = pending - take
		markDirty(p, "Tower")
	end
end

local function incomeJob(dt: number)
	local t = now()
	local autoEvery = num(TCFG.AutoCollectSeconds, 3)
	local janitorEvery = num(TCFG.JanitorSeconds, 60)
	for p, rt in pairs(runtime) do
		if p.Parent ~= Players then
			continue
		end
		local data = dataOf(p)
		if not data then
			continue
		end
		local tower = data.Tower
		local ok, err = pcall(function()
			-- 1) Baustelle fertig?
			if tower.Build.Floor ~= nil and num(tower.Build.Until, 0) <= t then
				finishBuild(p, data)
			end
			-- 2) Boost-Countdown (nur online, nur der stärkste)
			tickBoosts(p, data, dt)
			-- 3) Einkommen + Tresor
			local info = refreshIncome(p, data, rt, false)
			fillVault(p, data, rt, info, dt)
			-- 4) Automatik: Auto-Kassierer (Pass, überall) / Hausmeister-Bot (auf dem Plot)
			rt.AutoAcc += dt
			rt.JanitorAcc += dt
			if rt.AutoAcc >= autoEvery then
				rt.AutoAcc = 0
				if tower.Vault > 0 and hasPass(p, TCFG.AutoCollectPass or "AutoCollect") then
					collectVault(p, data, rt, false)
				end
			end
			if rt.JanitorAcc >= janitorEvery then
				rt.JanitorAcc = 0
				if tower.Janitor and tower.Vault > 0 then
					local okPlot, onPlot = call("PlotService", "IsOnOwnPlot", p)
					if okPlot and onPlot == true then
						local amount = collectVault(p, data, rt, false)
						if amount > 0 then
							effect(p, "Collect", 0.5, plotPayload(p, { Amount = amount, Janitor = true }))
						end
					end
				end
			end
			-- 5) langsame Aufgaben (alle 5 s): vorgemerkte CR nachbuchen, Tages-Token, Börsengang-Krone
			rt.SlowAcc += dt
			if rt.SlowAcc >= 5 then
				rt.SlowAcc = 0
				retryPending(p, data)
				if rt.Settled then
					grantDailyToken(p, data)
				end
				syncCrown(p, data)
			end
		end)
		if not ok then
			logError("TowerIncome", err)
		end
	end
end

-- ---------------------------------------------------------------------
-- 14) REQUEST-HANDLER (§C9) – Argumente exakt prüfen
-- ---------------------------------------------------------------------
local function exact(arg: any, spec: { [string]: string }, optional: { [string]: boolean }?): boolean
	if type(arg) ~= "table" then
		return false
	end
	local count = 0
	for key, value in pairs(arg) do
		count += 1
		if count > 8 then
			return false
		end
		local want = spec[key]
		if want == nil or type(value) ~= want then
			return false
		end
		if want == "number" and not isNum(value) then
			return false
		end
	end
	for key in pairs(spec) do
		if arg[key] == nil and not (optional and optional[key]) then
			return false
		end
	end
	return true
end

local function intIn(v: any, lo: number, hi: number): boolean
	return isInt(v) and v >= lo and v <= hi
end

-- Fehler-Schlüssel + Argumente lokalisiert beantworten (Kosten als CR-Text)
local function coreFail(p: Player, key: string?, args: { any }?): Reply
	local k = key or "core.error"
	if k == "tower.noCredits" and args then
		return fail(p, k, { credits(p, args[1]) })
	elseif k == "tower.craneBusy" and args then
		return fail(p, k, { Format.Duration(args[1], langOf(p)) })
	end
	return fail(p, k, args)
end

local function after(p: Player, data: { [string]: any }, touch: boolean)
	invalidate(p)
	local rt = runtime[p]
	if rt then
		refreshIncome(p, data, rt, true)
	end
	if touch then
		visual("Touch", p)
	end
	markDirty(p, "Tower", "Income")
end

local function handleBuild(p: Player, arg: any): Reply
	if arg ~= nil and not exact(arg, {}) then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	local env = TowerService._Env(p, data)
	local tower = data.Tower
	local ok, key, args, result = Core.StartBuild(tower, env)
	if not ok then
		if key == "tower.gateLicence" and result then
			local lang = langOf(p)
			return fail(p, key, { stageName(lang, result.Stage), licenceName(lang, result.Licence) })
		elseif key == "tower.gateIpo" and result then
			return fail(p, key, { stageName(langOf(p), result.Stage), result.Ipo })
		end
		return coreFail(p, key, args)
	end
	local info = result :: { [string]: any }
	effectAll("Crane", 1, plotPayload(p, { Floor = info.Floor, Seconds = info.Seconds, Stage = Core.Stage(tower) }))
	if info.Seconds <= 0 then
		finishBuild(p, data)
	end
	markDirty(p, "Tower")
	return okReply(p, nil, nil, { Floor = info.Floor, Cost = info.Cost, Seconds = info.Seconds })
end

local function handleRoom(p: Player, arg: any): Reply
	if not exact(arg, { Floor = "number", Room = "string" }) or not intIn(arg.Floor, 1, FLOORS) then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	local ok, key, args = Core.SetRoom(data.Tower, TowerService._Env(p, data), arg.Floor, arg.Room)
	if not ok then
		if key == "tower.roomLocked" and args then
			return fail(p, key, { Lang.Pick(langOf(p), ROOMS[arg.Room].Name), args[1] })
		elseif key == "tower.roomMax" and args then
			return fail(p, key, { args[1], Lang.Pick(langOf(p), ROOMS[arg.Room].Name) })
		end
		return coreFail(p, key, args)
	end
	after(p, data, true)
	return okReply(p, "tower.roomSet", { arg.Floor, Lang.Pick(langOf(p), ROOMS[arg.Room].Name) })
end

local function handleLevel(p: Player, arg: any): Reply
	if not exact(arg, { Floor = "number" }) or not intIn(arg.Floor, 1, FLOORS) then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	local ok, key, args = Core.LevelUp(data.Tower, TowerService._Env(p, data), arg.Floor)
	if not ok then
		return coreFail(p, key, args)
	end
	after(p, data, true)
	track(p, "RoomLevel", 1, { Floor = arg.Floor })
	return okReply(p, "tower.levelUp", args)
end

local function handleHire(p: Player, arg: any): Reply
	if not exact(arg, { Floor = "number", Staff = "string" }) or not intIn(arg.Floor, 0, FLOORS) then
		return fail(p, "core.invalid")
	end
	local staff = STAFF[arg.Staff]
	if not staff or (arg.Floor == 0 and not staff.Lobby) then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	local ok, key, args = Core.Hire(data.Tower, TowerService._Env(p, data), arg.Floor, arg.Staff)
	local lang = langOf(p)
	if not ok then
		if key == "tower.staffLocked" and args then
			return fail(p, key, { Lang.Pick(lang, staff.Name), args[1] })
		end
		return coreFail(p, key, args)
	end
	after(p, data, true)
	track(p, "Hire", 1, { Staff = arg.Staff, Floor = arg.Floor })
	if arg.Staff == "Janitor" then
		funnel(p, 10, "FirstAutomation")
	elseif not staff.Lobby then
		funnel(p, 9, "FirstStaff")
	end
	if staff.Lobby then
		return okReply(p, "tower.lobbyHired", { Lang.Pick(lang, staff.Name) })
	end
	return okReply(p, "tower.hired", { Lang.Pick(lang, staff.Name), arg.Floor })
end

local function handleFire(p: Player, arg: any): Reply
	if not exact(arg, { Floor = "number", Slot = "number" }) or not intIn(arg.Floor, 0, FLOORS) then
		return fail(p, "core.invalid")
	end
	if not intIn(arg.Slot, 1, STAFF_SLOTS_PLUS) then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	local ok, key, staffKey = Core.Fire(data.Tower, arg.Floor, arg.Slot)
	if not ok then
		return coreFail(p, key, nil)
	end
	after(p, data, true)
	local staff = if staffKey then STAFF[staffKey] else nil
	local name = if staff then Lang.Pick(langOf(p), staff.Name) else ""
	return okReply(p, "tower.fired", { name })
end

local function handleEfficiency(p: Player, arg: any): Reply
	if arg ~= nil and not exact(arg, {}) then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	local ok, key, args = Core.Efficiency(data.Tower, TowerService._Env(p, data))
	if not ok then
		return coreFail(p, key, args)
	end
	after(p, data, false)
	track(p, "Efficiency", 1, { Level = data.Tower.Eff })
	funnel(p, 15, "FirstMultiplier")
	local info = incomeState(p)
	return okReply(p, "tower.effUp", { data.Tower.Eff, Format.Mult(info.Mult, langOf(p)) })
end

local function handleCollect(p: Player, arg: any): Reply
	if arg ~= nil and not exact(arg, {}) then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	local rt = runtime[p]
	if not data or not rt then
		return fail(p, "core.loading")
	end
	local okPlot, onPlot = call("PlotService", "IsOnOwnPlot", p)
	if not okPlot or onPlot ~= true then
		return fail(p, "tower.tooFar", { math.floor(num(TCFG.CollectRange, 70)) })
	end
	if data.Tower.Vault <= 0 then
		return fail(p, "tower.vaultEmpty")
	end
	if not has("ShopService", "Credit") then
		return fail(p, "tower.shopMissing")
	end
	local amount = collectVault(p, data, rt, true)
	if amount <= 0 then
		return fail(p, if MAX_MONEY - balanceOf(p) < 1 then "tower.maxMoney" else "core.error")
	end
	effect(p, "Collect", 1, plotPayload(p, { Amount = amount }))
	return okReply(p, nil, nil, { Amount = amount })
end

local function handleTransfer(p: Player, arg: any): Reply
	if arg ~= nil and not exact(arg, {}) then
		return fail(p, "core.invalid")
	end
	if not dataOf(p) then
		return fail(p, "core.loading")
	end
	local amount, why = TowerService.Transfer(p, "Manual")
	if amount <= 0 then
		return fail(p, why or "trade.transferNone")
	end
	return okReply(p, "tower.transferDone", { credits(p, amount) }, { Credits = amount })
end

local function handleInstant(p: Player, arg: any): Reply
	if arg ~= nil and not exact(arg, {}) then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	local tower = data.Tower
	local build = tower.Build
	if build.Floor == nil then
		return fail(p, "tower.noBuild")
	end
	if build.Floor <= num(BUILD.Instant, 9) or num(build.Until, 0) - now() <= 5 then
		return fail(p, "tower.instantNotNeeded")
	end
	if tower.Instant <= 0 then
		return fail(p, "tower.noInstant")
	end
	tower.Instant -= 1
	build.Until = now()
	finishBuild(p, data)
	return okReply(p, "tower.instantUsed", { #tower.Floors })
end

-- Bau-Express-Token: der kleinste, der den Bau beendet – sonst der größte
local function pickExpress(list: { number }, remaining: number): number?
	local best: number? = nil
	for i, seconds in ipairs(list) do
		if seconds >= remaining then
			if best == nil or list[best] < remaining or seconds < list[best] then
				best = i
			end
		elseif best == nil or (list[best] < remaining and seconds > list[best]) then
			best = i
		end
	end
	return best
end

local function handleExpress(p: Player, arg: any): Reply
	if arg ~= nil and not exact(arg, {}) then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	local tower = data.Tower
	local build = tower.Build
	if build.Floor == nil then
		return fail(p, "tower.noBuild")
	end
	local remaining = num(build.Until, 0) - now()
	if remaining <= 5 then
		return fail(p, "tower.instantNotNeeded")
	end
	local index = pickExpress(tower.Express, remaining)
	if index == nil then
		return fail(p, "tower.noExpress")
	end
	local seconds = table.remove(tower.Express, index) :: number
	local env = TowerService._Env(p, data)
	Core.ApplyExpress(tower, env, seconds)
	if num(build.Until, 0) <= env.Now then
		finishBuild(p, data)
	end
	markDirty(p, "Tower")
	return okReply(p, "tower.expressUsed", { Format.Duration(math.min(seconds, remaining), langOf(p)) })
end

local function helperAllowed(helper: Player): boolean
	local studio = Config.Studio
	if RunService:IsStudio() and type(studio) == "table" and studio.SkipAccountAge == true then
		return true
	end
	local security = if type(Config.Security) == "table" then Config.Security else {}
	local minAge = num(security.AccountAgeMin, 3)
	local minSession = num(security.SessionMinForSocial, 600)
	local okAge, age = pcall(function()
		return helper.AccountAge
	end)
	if not okAge or not isNum(age) or age < minAge then
		return false
	end
	local rt = runtime[helper]
	return rt ~= nil and os.clock() - rt.JoinClock >= minSession
end

local function rootOf(p: Player): BasePart?
	local character = p.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function handleHelp(p: Player, arg: any): Reply
	if not exact(arg, { OwnerUserId = "number" }) or not isInt(arg.OwnerUserId) then
		return fail(p, "core.invalid")
	end
	if arg.OwnerUserId == p.UserId then
		return fail(p, "tower.helpSelf")
	end
	local owner = Players:GetPlayerByUserId(arg.OwnerUserId)
	local ownerData = if owner then dataOf(owner) else nil
	if not owner or not ownerData then
		return fail(p, "tower.ownerGone")
	end
	if not helperAllowed(p) then
		return fail(p, "tower.helpNew")
	end
	local okPlot, plot = call("PlotService", "PlotOf", owner)
	local okCf, plotCf = call("PlotService", "PlotCFrame", if okPlot then plot else 0)
	local root = rootOf(p)
	if not okPlot or not isInt(plot) or not okCf or typeof(plotCf) ~= "CFrame" or not root then
		return fail(p, "tower.helpTooFar")
	end
	local delta = root.Position - (plotCf :: CFrame).Position
	if Vector3.new(delta.X, 0, delta.Z).Magnitude > num(BUILD.HelpRange, 40) then
		return fail(p, "tower.helpTooFar")
	end
	local ok, key = Core.ApplyHelp(ownerData.Tower, TowerService._Env(owner, ownerData), p.UserId)
	if not ok then
		return coreFail(p, key, nil)
	end
	call("RewardService", "GrantSeasonXp", p, math.floor(num(BUILD.HelpSeasonXp, 25)), "HelpBuild")
	track(p, "HelpBuild", 1, { Owner = owner.UserId })
	notify(owner, "tower.helpReceived", { p.DisplayName }, "Success")
	markDirty(owner, "Tower")
	return okReply(p, "tower.helped", nil)
end

local function handleName(p: Player, arg: any): Reply
	if not exact(arg, { A = "number", N = "number" }) then
		return fail(p, "core.invalid")
	end
	if not intIn(arg.A, 1, NAME_ADJ) or not intIn(arg.N, 1, NAME_NOUN) then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	data.Tower.Name = { A = arg.A, N = arg.N }
	setTowerAttributes(p, data)
	visual("Touch", p)
	markDirty(p, "Tower")
	local nameText = if type(TCFG.NameText) == "function" then TCFG.NameText(arg.A, arg.N, langOf(p)) else ""
	return okReply(p, "tower.nameSet", { nameText })
end

local function handleSkin(p: Player, arg: any): Reply
	if not exact(arg, { Skin = "string" }) then
		return fail(p, "core.invalid")
	end
	local entry = SKINS[arg.Skin]
	if not entry then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	if not ownsUnlock(p, data, entry) then
		return fail(p, "tower.locked")
	end
	data.Tower.Skin = arg.Skin
	visual("Rebuild", p)
	markDirty(p, "Tower")
	return okReply(p, "tower.skinSet", { Lang.Pick(langOf(p), entry.Name) })
end

local function handleNeon(p: Player, arg: any): Reply
	if not exact(arg, { Color = "string" }) then
		return fail(p, "core.invalid")
	end
	local entry = NEONS[arg.Color]
	if not entry then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	if not ownsUnlock(p, data, entry) then
		return fail(p, "tower.locked")
	end
	data.Tower.Neon = arg.Color
	visual("Rebuild", p)
	markDirty(p, "Tower")
	return okReply(p, "tower.neonSet", { Lang.Pick(langOf(p), entry.Name) })
end

local function handlePrivate(p: Player, arg: any): Reply
	if not exact(arg, { Floor = "number", On = "boolean" }) or not intIn(arg.Floor, 1, FLOORS) then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	local ok, key, args = Core.SetPrivate(data.Tower, arg.Floor, arg.On)
	if not ok then
		return coreFail(p, key, args)
	end
	visual("Touch", p)
	markDirty(p, "Tower")
	return okReply(p, if arg.On then "tower.privateOn" else "tower.privateOff", { arg.Floor })
end

local function validDecorKey(key: any): boolean
	return type(key) == "string" and #key >= 1 and #key <= MAX_DECOR_KEY and string.match(key, "^[%w_]+$") ~= nil
end

local function handleDecor(p: Player, arg: any): Reply
	if not exact(arg, { Floor = "number", Slot = "number", Key = "string" }, { Key = true }) then
		return fail(p, "core.invalid")
	end
	if not intIn(arg.Floor, 1, FLOORS) or not intIn(arg.Slot, 1, 16) then
		return fail(p, "core.invalid")
	end
	if arg.Key ~= nil and arg.Key ~= "" and not validDecorKey(arg.Key) then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	if not (has("LifestyleService", "TakeDecor") and has("LifestyleService", "ReturnDecor")) then
		return fail(p, "tower.decorUnavailable")
	end
	local placing = arg.Key ~= nil and arg.Key ~= ""
	local ok, key = Core.SetDecor(data.Tower, TowerService._Env(p, data), arg.Floor, arg.Slot, arg.Key)
	if not ok then
		return coreFail(p, key, nil)
	end
	after(p, data, true)
	return okReply(p, if placing then "tower.decorPlaced" else "tower.decorRemoved", { arg.Floor })
end

local function handleLayout(p: Player, arg: any): Reply
	if not exact(arg, { On = "boolean" }) then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	data.Tower.KeepLayout = arg.On
	markDirty(p, "Tower")
	return okReply(p, if arg.On then "tower.layoutOn" else "tower.layoutOff", nil)
end

-- "Auto-Plan" (Tiko, Greedy nach Einkommen): schlägt je Etage eine Abteilung vor (ändert nichts)
function Core.AutoPlan(t: any, stage: number, permBase: number, ctx: TowerMath.Ctx?): ({ string }, number, number)
	local count = #t.Floors
	local plan: { FloorData } = {}
	for i, floor in ipairs(t.Floors) do
		plan[i] = { R = floor.R, L = floor.L, S = floor.S, D = floor.D }
	end
	local marketing = ROOMS.Marketing
	local penthouse = ROOMS.Penthouse
	local function objective(floors: { FloorData }): number
		local perm = permBase
		local mkt, top = 0, floors[count]
		for _, floor in ipairs(floors) do
			if floor.R == "Marketing" then
				mkt += 1
			end
		end
		if marketing then
			perm += num(marketing.IncomePct, 0.05) * math.min(mkt, num(marketing.Max, 3))
		end
		if penthouse and top and top.R == "Penthouse" then
			perm += num(penthouse.IncomePct, 0.10)
		end
		return TowerMath.BaseIncome(floors, ctx) * perm
	end
	local before = objective(plan)
	local best = before
	-- zwei Durchgänge von oben nach unten (Nachbar-Effekte wirken in beide Richtungen)
	for _ = 1, 2 do
		local improved = false
		for i = count, 1, -1 do
			local current = plan[i].R
			local chosen = current
			for _, room in ipairs(ROOM_LIST) do
				local key = room.Key
				if key ~= current and stage >= num(room.MinStage, 1) and not (room.TopOnly and i ~= count) then
					local allowed = true
					if isInt(room.Max) then
						local used = 0
						for j, floor in ipairs(plan) do
							if j ~= i and floor.R == key then
								used += 1
							end
						end
						allowed = used < room.Max
					end
					if allowed then
						plan[i].R = key
						local value = objective(plan)
						if value > best + 1e-9 then
							best = value
							chosen = key
						end
						plan[i].R = chosen
					end
				end
			end
			if chosen ~= current then
				improved = true
			end
		end
		if not improved then
			break
		end
	end
	local result: { string } = {}
	local cost = 0
	for i, floor in ipairs(plan) do
		result[i] = floor.R
		if floor.R ~= t.Floors[i].R then
			cost += TowerMath.RoomChangeCost(i)
		end
	end
	return result, math.max(0, best - before), cost
end

local function handleAutoPlan(p: Player, arg: any): Reply
	if arg ~= nil and not exact(arg, {}) then
		return fail(p, "core.invalid")
	end
	local data = dataOf(p)
	if not data then
		return fail(p, "core.loading")
	end
	local tower = data.Tower
	local factors = gatherFactors(p, data, now())
	-- Perm ohne Marketing/Penthouse (die bewertet der Plan selbst)
	factors.Marketing = 0
	factors.Penthouse = false
	local g = TowerMath.Groups(Core.BuildParts(factors, true, false) :: any)
	local plan, gain, cost = Core.AutoPlan(tower, Core.Stage(tower), g.Perm, comfortCtx())
	local steady = g.Trader * g.Pass * g.Fixed
	local perSecGain = gain * steady
	if perSecGain < 0.01 then
		return okReply(p, "tower.autoPlanNone", nil, { Plan = plan, Gain = 0, Cost = 0 })
	end
	return okReply(p, "tower.autoPlan", { credits(p, perSecGain) }, { Plan = plan, Gain = perSecGain, Cost = cost })
end

-- ---------------------------------------------------------------------
-- 15) ÖFFENTLICHE API (§C5.5)
-- ---------------------------------------------------------------------
function TowerService.Income(p: Player): IncomeInfo
	return incomeState(p)
end

function TowerService.Floors(p: Player): number
	local data = dataOf(p)
	return if data then #data.Tower.Floors else 0
end

function TowerService.Stage(p: Player): number
	local data = dataOf(p)
	return if data then Core.Stage(data.Tower) else 1
end

function TowerService.RunSpend(p: Player): number
	local data = dataOf(p)
	return if data then TowerMath.Clamp(num(data.Tower.RunSpend, 0)) else 0
end

function TowerService.TowerValue(p: Player): number
	return TowerMath.Clamp(math.floor(TowerService.RunSpend(p) * 0.5))
end

-- Einkommen/Multiplikatoren sofort neu rechnen (Pass-/Abo-Kauf, Premium-Wechsel) – kein Yield
function TowerService.Refresh(p: Player)
	local data = dataOf(p)
	local rt = runtime[p]
	if not data or not rt then
		return
	end
	invalidate(p)
	refreshIncome(p, data, rt, true)
	markDirty(p, "Income", "Tower")
end

function TowerService.RoomCount(p: Player, roomKey: string): number
	local data = dataOf(p)
	if not data or type(roomKey) ~= "string" then
		return 0
	end
	return Core.RoomCount(data.Tower, roomKey)
end

function TowerService.AddBoost(p: Player, kind: "X2" | "X5" | "Bull", seconds: number): boolean
	if kind ~= "X2" and kind ~= "X5" and kind ~= "Bull" then
		return false
	end
	if not isNum(seconds) or seconds <= 0 then
		return false
	end
	local data = dataOf(p)
	if not data then
		return false
	end
	local boosts = data.Boosts
	local maxSeconds = mult("BoostMaxSeconds", 2592000)
	if kind == "Bull" then
		-- Bullen-Bonus stapelt nicht (1× je Rally): höchstens auf die neue Dauer verlängern
		boosts.Bull = math.clamp(math.max(num(boosts.Bull, 0), seconds), 0, maxSeconds)
	else
		boosts[kind] = math.clamp(num(boosts[kind], 0) + seconds, 0, maxSeconds)
	end
	invalidate(p)
	local rt = runtime[p]
	if rt then
		refreshIncome(p, data, rt, true)
	end
	markDirty(p, "Boosts", "Income")
	return true
end

function TowerService.SetServerBoost(kind: "Parade" | "Bell", value: number, seconds: number)
	local entry = serverBoost[kind]
	if not entry or not isNum(value) or not isNum(seconds) then
		return
	end
	local t = now()
	if seconds <= 0 or value <= 1 then
		entry.Mult, entry.Until = 1, 0
	else
		entry.Mult = math.clamp(value, 1, mult("ServerMax", 2))
		entry.Until = t + math.min(seconds, mult("EventMaxSeconds", 3600))
	end
	for p in pairs(runtime) do
		invalidate(p)
	end
end

function TowerService.SetEventMult(value: number, untilUnix: number)
	if not isNum(value) or not isNum(untilUnix) then
		return
	end
	local t = now()
	if untilUnix <= t or value <= 1 then
		eventBoost.Mult, eventBoost.Until = 1, 0
	else
		eventBoost.Mult = math.clamp(value, 1, mult("EventMax", 3))
		eventBoost.Until = math.min(untilUnix, t + mult("EventMaxSeconds", 3600))
	end
	for p in pairs(runtime) do
		invalidate(p)
	end
end

function TowerService.CostMult(kind: "Floor" | "RoomLevel"): number
	return costEventMult(kind, now())
end

function TowerService.SetCostEvent(kind: "Floor" | "RoomLevel" | "Both", value: number, untilUnix: number)
	if not isNum(value) or not isNum(untilUnix) then
		return
	end
	local kinds = if kind == "Both" then { "Floor", "RoomLevel" } elseif costEvents[kind] then { kind } else {}
	local t = now()
	for _, k in ipairs(kinds) do
		local entry = costEvents[k]
		if untilUnix <= t or value >= 1 then
			entry.Mult, entry.Until = 1, 0
		else
			entry.Mult = math.clamp(value, mult("CostEventMin", 0.1), 1)
			entry.Until = math.min(untilUnix, t + mult("EventMaxSeconds", 3600))
		end
	end
	for p in pairs(runtime) do
		markDirty(p, "Tower")
	end
end

function TowerService.SetBuildEvent(value: number, untilUnix: number)
	if not isNum(value) or not isNum(untilUnix) then
		return
	end
	local t = now()
	if untilUnix <= t or value >= 1 then
		buildEvent.Mult, buildEvent.Until = 1, 0
	else
		buildEvent.Mult = math.clamp(value, 0, 1)
		buildEvent.Until = math.min(untilUnix, t + mult("EventMaxSeconds", 3600))
	end
end

function TowerService.AddExpressToken(p: Player, maxSeconds: number): boolean
	if not isNum(maxSeconds) or maxSeconds < 1 then
		return false
	end
	local data = dataOf(p)
	if not data then
		return false
	end
	local tower = data.Tower
	if #tower.Express >= EXPRESS_MAX then
		return false
	end
	table.insert(tower.Express, math.clamp(math.floor(maxSeconds), 1, EXPRESS_MAX_SECONDS))
	markDirty(p, "Tower")
	return true
end

function TowerService.ApplyExpress(p: Player, maxSeconds: number): boolean
	if not isNum(maxSeconds) or maxSeconds < 1 then
		return false
	end
	local data = dataOf(p)
	if not data then
		return false
	end
	local env = TowerService._Env(p, data)
	local tower = data.Tower
	if not Core.ApplyExpress(tower, env, math.min(maxSeconds, EXPRESS_MAX_SECONDS)) then
		return false
	end
	if num(tower.Build.Until, 0) <= env.Now then
		finishBuild(p, data)
	end
	markDirty(p, "Tower")
	return true
end

function TowerService.AddInstantToken(p: Player, n: number): boolean
	if not isInt(n) or n < 1 then
		return false
	end
	local data = dataOf(p)
	if not data then
		return false
	end
	local tower = data.Tower
	tower.Instant = math.min(INSTANT_MAX, tower.Instant + n)
	markDirty(p, "Tower")
	return true
end

function TowerService.ResetForIpo(p: Player, perks: { [string]: number }): boolean
	local data = dataOf(p)
	if not data then
		return false
	end
	local env = TowerService._Env(p, data)
	local ok = Core.ResetForIpo(data, env, perks)
	if not ok then
		return false
	end
	local rt = runtime[p]
	if rt then
		rt.VaultFrac = 0
		rt.VaultFullNotified = false
	end
	invalidate(p)
	visual("Rebuild", p)
	call("PlayerStateService", "SetLeaderstat", p, "Etagen", #data.Tower.Floors)
	markDirty(p, "Tower", "Income")
	return true
end

function TowerService.AdminSetFloors(p: Player, n: number): boolean
	if not isInt(n) or n < 0 or n > FLOORS then
		return false
	end
	local data = dataOf(p)
	if not data then
		return false
	end
	Core.SetFloors(data.Tower, TowerService._Env(p, data), n)
	invalidate(p)
	visual("Rebuild", p)
	call("PlayerStateService", "SetLeaderstat", p, "Etagen", #data.Tower.Floors)
	markDirty(p, "Tower", "Income")
	return true
end

function TowerService.OnFloorBuilt(cb: (p: Player, floor: number, stage: number) -> ())
	if type(cb) == "function" then
		table.insert(floorBuiltCallbacks, cb)
	end
end

function TowerService.OnStageUp(cb: (p: Player, stage: number) -> ())
	if type(cb) == "function" then
		table.insert(stageUpCallbacks, cb)
	end
end

function TowerService.OnTransfer(cb: (p: Player, akyCents: number, credits: number) -> ())
	if type(cb) == "function" then
		table.insert(transferCallbacks, cb)
	end
end

-- Interne Teile für TowerTests (keine Spieler, keine echten Spielstände)
TowerService._Test = {
	Core = Core,
	Factors = function(): Factors
		return {
			Eff = 0,
			Ipo = 0,
			Growth = 0,
			Album = 0,
			Friends = 0,
			Respekt = 0,
			Marketing = 0,
			Penthouse = false,
			Trader = {},
			Pass = 1,
			Fixed = {},
			Boost = nil,
			Server = nil,
			Event = nil,
		}
	end,
}

-- ---------------------------------------------------------------------
-- 16) LEBENSZYKLUS
-- ---------------------------------------------------------------------
-- Einmal je Sitzung: Turm-Daten reparieren, Laufzeit anlegen, Attribute/Leaderstat, Hülle (wenn der Plot steht)
local function ensureLoaded(p: Player, data: { [string]: any }): Runtime?
	if p.Parent ~= Players or type(data.Tower) ~= "table" then
		return nil
	end
	local rt = runtime[p] or newRuntime()
	runtime[p] = rt
	if rt.Repaired then
		return rt
	end
	rt.Repaired = true
	local refund = Core.Repair(data)
	rt.BaseDirty = true
	if refund > 0 then
		creditOrPend(p, data, refund, "Refund")
	end
	data.Tower.Crown = crownFor(ipoCountOf(p, data))
	setTowerAttributes(p, data)
	call("PlayerStateService", "SetLeaderstat", p, "Etagen", #data.Tower.Floors)
	refreshIncome(p, data, rt, true)
	if plotOf(p) then
		visual("Rebuild", p)
	end
	markDirty(p, "Tower", "Income")
	return rt
end

local function onProfileLoaded(p: Player, data: { [string]: any })
	ensureLoaded(p, data)
end

local function onReady(p: Player)
	local data = dataOf(p)
	local rt = if data then ensureLoaded(p, data) else nil
	if not data or not rt then
		return
	end
	invalidate(p)
	settleOffline(p, data, rt)
	grantDailyToken(p, data)
	refreshIncome(p, data, rt, true)
	markDirty(p, "Tower", "Income")
end

local function onPlayerRemoving(p: Player)
	runtime[p] = nil
end

function TowerService.Init(services: any)
	Services = services
	local pss = Services.PlayerStateService
	if type(pss) ~= "table" then
		warn(PREFIX .. "PlayerStateService fehlt – keine Anfragen/State")
		return
	end
	pss.Provide("Tower", towerState)
	pss.Provide("Income", incomeState)
	pss.Handle("TowerBuild", handleBuild, { Rate = 4, Per = 1 })
	pss.Handle("TowerRoom", handleRoom, { Rate = 8, Per = 1 })
	pss.Handle("TowerLevel", handleLevel, { Rate = 8, Per = 1 })
	pss.Handle("TowerHire", handleHire, { Rate = 8, Per = 1 })
	pss.Handle("TowerFire", handleFire, { Rate = 8, Per = 1 })
	pss.Handle("TowerEfficiency", handleEfficiency, { Rate = 4, Per = 1 })
	pss.Handle("TowerCollect", handleCollect, { Rate = 4, Per = 1 })
	pss.Handle("TowerTransfer", handleTransfer, { Rate = 1, Per = 5 })
	pss.Handle("TowerInstant", handleInstant, { Rate = 1, Per = 1 })
	pss.Handle("TowerExpress", handleExpress, { Rate = 1, Per = 1 })
	pss.Handle("TowerHelp", handleHelp, { Rate = 1, Per = 1 })
	pss.Handle("TowerName", handleName, { Rate = 2, Per = 1 })
	pss.Handle("TowerSkin", handleSkin, { Rate = 2, Per = 1 })
	pss.Handle("TowerNeon", handleNeon, { Rate = 2, Per = 1 })
	pss.Handle("TowerPrivate", handlePrivate, { Rate = 2, Per = 1 })
	pss.Handle("TowerDecor", handleDecor, { Rate = 8, Per = 1 })
	pss.Handle("TowerLayout", handleLayout, { Rate = 1, Per = 1 })
	pss.Handle("TowerAutoPlan", handleAutoPlan, { Rate = 1, Per = 1 })
end

function TowerService.Start()
	call("OrderService", "OnBell", function(p: Player)
		onBell(p)
	end)
	call("DataService", "OnProfileLoaded", onProfileLoaded)
	call("PlayerStateService", "OnReady", onReady)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	-- Roblox Premium mitten in der Sitzung gekauft/beendet -> ×1,10 sofort im Multiplikator-Chip
	Players.PlayerMembershipChanged:Connect(function(p: Player)
		TowerService.Refresh(p)
	end)
	Scheduler.Every("TowerIncome", 1, incomeJob)
end

return TowerService
