--!strict
-- =====================================================================
--  AKYTEX TYCOON – Turm-Formeln ohne Seiteneffekte (Shared/TowerMath)
--  Besitzer: WP6 (Turm-Ökonomie). Vertrag: DESIGN.md §C6.2, §B4.3–§B4.7, §B5, §B9.6 (Sterne).
--  Rein: lädt keine Roblox-Dienste -> Server (TowerService) und Client (Tower-Menü, Vorschau) rechnen exakt gleich;
--  mit der Luau-CLI testbar (tests/towermath.test.luau). Gleiche Werte wie tools/economy_sim.py (Tabelle §B5.1).
--
--  Parameter: Startwerte = DESIGN §B5 (unten eingebaut). In Roblox liest das Modul beim Laden Shared/Config/Tower
--  (falls vorhanden) über TowerMath.Configure – damit gilt immer, was in Config.Tower steht. Ungültige Werte werden
--  ignoriert (Startwert bleibt). Ungültige Eingaben (NaN, ±inf, negative Etagen) ergeben 0 – nie einen Fehler.
--
--  Öffentliche API (§C6.2):
--    TowerMath.FloorCost(n): number            Kosten Etage n (1 gratis, 2 = C2, dann Bänder), ganze CR
--    TowerMath.FloorIncome(n): number          Basis-Einkommen I(n) = I0 · IR^(n−1) CR/s
--    TowerMath.BuildTime(n): number            Grund-Bauzeit in s (1–9: Szene 3 s, dann min(Cap, 20 · 1,33^(n−10)))
--    TowerMath.LevelCost(n, l): number         Raum-Stufe L(l) -> L(l+1) auf Etage n (0 wenn l ≥ 5)
--    TowerMath.StaffCost(n, key): number       Personal auf Etage n (Janitor 0, Security fester Preis)
--    TowerMath.EfficiencyCost(k): number       nächste Effizienz-Stufe bei k gekauften (0 wenn k ≥ Max)
--    TowerMath.StageOf(floors): number         Stufe 1 … 12 (0 Etagen = Stufe 1 ohne Büro)
--    TowerMath.BaseIncome(floors, ctx): number Basis = Gehalt + Σ Etage(n) (Raum, Stufe, Personal, Café/Server,
--                                              Labor-Nachbarn, Komfort); ctx = { Comfort: (key) -> Punkte }
--    TowerMath.Multiplier(parts): (number, number)   gesamt, ohne Zeitlich (Gruppen §B5.2, Deckel ×10, Event ≤ ×3)
--    TowerMath.Offline(steadyPerSec, seconds, rate, capSeconds): number   floor(steady · rate · min(s, Deckel))
--    TowerMath.Stars(runSpend): number         floor(4 · log10(Lauf-Ausgaben / 1e6)), 0 unter 1e7
--    TowerMath.Clamp(n): number                ganzzahlig, 0 … 9e15
--  Helfer (abwärtskompatible Ergänzungen):
--    TowerMath.Configure(cfg)                  Parameter aus Config.Tower (+ optional Config.Decor-Werte)
--    TowerMath.FloorIncomeAt(floors, i, ctx)   Einkommen einer Etage im Tower (für das Tower-Menü)
--    TowerMath.Groups(parts)                   { Perm, Trader, Pass, Fixed, Timed } (Timed ungedeckelt)
--    TowerMath.PassFactor(has2x, has3x)        1 + x2 + 2·x3 (×2 / ×3 / zusammen ×4)
--    TowerMath.BuildSeconds(n, speedFactor)    Bauzeit mit Beschleunigern (nie unter MinFactor der Grundzeit)
--    TowerMath.RoomChangeCost(n)               Abteilungs-Wechsel (RoomChangePct der Etagenkosten)
--    TowerMath.Discount(cost, mult)            gerundete, geklemmte Kosten nach Rabatt (≥ 1, wenn cost > 0)
--    TowerMath.VaultCap(perSec, vaultFloors)   Tresor-Kapazität (20 min, +50 % je Tresor-Etage, max. 2)
--    TowerMath.OfflineRate(tresorPerk, hasPass) / TowerMath.OfflineCap(tresorPerk, lounges, club, hasPass)
--    TowerMath.GateFor(n): (licence, ipo)      Tor der Stufe, in die Etage n fällt
--    TowerMath.StageRange(stage): (first, last)
--    TowerMath.FLOORS · TowerMath.MAX_MONEY (9e15)
-- =====================================================================

local TowerMath = {}

-- Lokale Typen (strukturell gleich Shared/Types – hier ohne require, damit das Modul CLI-testbar bleibt)
export type FloorData = { R: string, L: number, S: { string }, D: { string } }
export type MultPart = {
	Key: string,
	Value: number,
	Group: string,
	Source: string,
	Until: number?,
}
export type Ctx = {
	Comfort: ((key: string) -> number)?,
	ComfortPct: number?,
	ComfortMax: number?,
}
export type Groups = { Perm: number, Trader: number, Pass: number, Fixed: number, Timed: number }

type RoomParams = {
	Factor: number,
	StaffMult: number,
	Radius: number,
	TowerStaffMult: number,
	NeighbourMult: number,
	Max: number,
}
type StaffParams = { Bonus: number, CostMult: number, Price: number, Lobby: boolean }

local MAX_MONEY = 9e15
local HUGE = math.huge

TowerMath.MAX_MONEY = MAX_MONEY

-- ---------------------------------------------------------------------
-- 1) PARAMETER (Startwerte = DESIGN §B5; Configure überschreibt)
-- ---------------------------------------------------------------------
local P = {
	I0 = 4,
	IR = 1.30,
	C2 = 1000,
	Bands = { { 3, 12, 1.50 }, { 13, 25, 1.56 }, { 26, 40, 1.58 }, { 41, 50, 1.60 } } :: { { number } },
	Salary = 3,
	Floors = 50,
	LevelFactor = { 1.00, 1.25, 1.50, 1.80, 2.20 } :: { number },
	LevelCost = { 1, 2.5, 6, 15 } :: { number },
	UpgradeMin = 500,
	RoomChangePct = 0.25,
	EffBase = 10000,
	EffRatio = 3,
	EffMax = 20,
	BuildInstant = 9,
	BuildScene = 3,
	BuildBase = 20,
	BuildRatio = 1.33,
	BuildCap = 5400,
	BuildMinFactor = 0.25,
	StageFirst = { 1, 2, 4, 7, 10, 14, 18, 22, 26, 31, 37, 44 } :: { number },
	StageLicence = { 1, 1, 1, 1, 2, 3, 4, 4, 5, 6, 7, 7 } :: { number },
	StageIpo = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 } :: { number },
	ComfortPct = 0.005,
	ComfortMax = 0.10,
	ComfortItemMax = 5,
	TimedCap = 10,
	EventMax = 3,
	VaultMinutes = 20,
	VaultFloorBonus = 0.5,
	VaultFloorMax = 2,
	OffRate = 0.5,
	OffRateMax = 0.9,
	OffCapHours = 8,
	OffCapMax = 24,
	OffPerkRate = 0.05,
	OffPerkHours = 1,
	OffPerkMax = 8,
	OffPassRate = 0.15,
	OffPassMinHours = 24,
	OffLoungeHours = 1,
	OffLoungeMax = 4,
	OffClubHours = 4,
	StarsK = 4,
	StarsDiv = 1e6,
	StarsMin = 1e7,
}

local DEFAULT_ROOM: RoomParams =
	{ Factor = 1, StaffMult = 1, Radius = 0, TowerStaffMult = 1, NeighbourMult = 1, Max = HUGE }

local ROOMS: { [string]: RoomParams } = {
	Office = { Factor = 1.00, StaffMult = 1, Radius = 0, TowerStaffMult = 1, NeighbourMult = 1, Max = HUGE },
	Desk = { Factor = 1.25, StaffMult = 1, Radius = 0, TowerStaffMult = 1, NeighbourMult = 1, Max = HUGE },
	Cafe = { Factor = 0.60, StaffMult = 1.20, Radius = 2, TowerStaffMult = 1, NeighbourMult = 1, Max = HUGE },
	Garage = { Factor = 0.40, StaffMult = 1, Radius = 0, TowerStaffMult = 1, NeighbourMult = 1, Max = HUGE },
	Marketing = { Factor = 0.80, StaffMult = 1, Radius = 0, TowerStaffMult = 1, NeighbourMult = 1, Max = 3 },
	Vault = { Factor = 0.50, StaffMult = 1, Radius = 0, TowerStaffMult = 1, NeighbourMult = 1, Max = 2 },
	Lab = { Factor = 0.80, StaffMult = 1, Radius = 0, TowerStaffMult = 1, NeighbourMult = 1.15, Max = HUGE },
	Server = { Factor = 0.70, StaffMult = 1, Radius = 0, TowerStaffMult = 1.10, NeighbourMult = 1, Max = 3 },
	Lounge = { Factor = 0.50, StaffMult = 1, Radius = 0, TowerStaffMult = 1, NeighbourMult = 1, Max = 4 },
	BotLab = { Factor = 1.10, StaffMult = 1, Radius = 0, TowerStaffMult = 1, NeighbourMult = 1, Max = HUGE },
	Penthouse = { Factor = 0, StaffMult = 1, Radius = 0, TowerStaffMult = 1, NeighbourMult = 1, Max = 1 },
}

local STAFF: { [string]: StaffParams } = {
	Intern = { Bonus = 0.10, CostMult = 1, Price = 0, Lobby = false },
	Analyst = { Bonus = 0.25, CostMult = 3, Price = 0, Lobby = false },
	Senior = { Bonus = 0.50, CostMult = 9, Price = 0, Lobby = false },
	Quant = { Bonus = 1.00, CostMult = 25, Price = 0, Lobby = false },
	Janitor = { Bonus = 0, CostMult = 0, Price = 0, Lobby = true },
	Security = { Bonus = 0, CostMult = 0, Price = 50000, Lobby = true },
}

-- größte Reichweite eines Personal-Raums (Café ±2); nach Configure neu bestimmt
local maxStaffRadius = 0
local function refreshRadius()
	maxStaffRadius = 0
	for _, params in pairs(ROOMS) do
		if params.StaffMult > 1 then
			maxStaffRadius = math.max(maxStaffRadius, params.Radius)
		end
	end
end

-- Vorberechnete Tabellen (Kosten exakt wie economy_sim.py: gleiche Multiplikations-Reihenfolge, dann runden)
local COST: { number } = {}
local INCOME: { number } = {}

TowerMath.FLOORS = P.Floors

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= HUGE and n ~= -HUGE
end

-- Runden wie Python round() (halbe Werte zur geraden Zahl) -> exakt dieselben Kosten wie economy_sim.py
-- (z. B. Etage 6: 1000 · 1,5^4 = 5062,5 -> 5062)
local function roundHalfEven(x: number): number
	local whole = math.floor(x)
	local rest = x - whole
	if rest > 0.5 then
		return whole + 1
	elseif rest < 0.5 then
		return whole
	end
	return if whole % 2 == 0 then whole else whole + 1
end

local function bandFactor(k: number): number
	local factor = 1
	for _, band in ipairs(P.Bands) do
		if k >= band[1] and k <= band[2] then
			factor *= band[3]
		end
	end
	return factor
end

local function rebuildTables()
	table.clear(COST)
	table.clear(INCOME)
	local c = P.C2
	for n = 1, P.Floors do
		if n <= 1 then
			COST[n] = 0
		elseif n == 2 then
			COST[n] = roundHalfEven(c)
		else
			c *= bandFactor(n)
			COST[n] = roundHalfEven(c)
		end
		INCOME[n] = P.I0 * P.IR ^ (n - 1)
	end
	TowerMath.FLOORS = P.Floors
	refreshRadius()
end

-- ---------------------------------------------------------------------
-- 2) KONFIGURATION (aus Config.Tower; nur gültige Werte werden übernommen)
-- ---------------------------------------------------------------------
local function takeNum(target: any, key: string, value: any, lo: number, hi: number)
	if finite(value) and value >= lo and value <= hi then
		target[key] = value
	end
end

local function takeList(value: any, count: number, lo: number, hi: number): { number }?
	if type(value) ~= "table" or #value ~= count then
		return nil
	end
	local out: { number } = {}
	for i = 1, count do
		local v = value[i]
		if not finite(v) or v < lo or v > hi then
			return nil
		end
		out[i] = v
	end
	return out
end

function TowerMath.Configure(cfg: any)
	if type(cfg) ~= "table" then
		return
	end
	local p: any = P
	takeNum(p, "I0", cfg.I0, 0.01, 1e6)
	takeNum(p, "IR", cfg.IR, 1, 3)
	takeNum(p, "C2", cfg.C2, 1, 1e9)
	takeNum(p, "Salary", cfg.Salary, 0, 1e6)
	if finite(cfg.Floors) and cfg.Floors >= 1 and cfg.Floors <= 50 and cfg.Floors % 1 == 0 then
		P.Floors = cfg.Floors
	end
	if type(cfg.Bands) == "table" and #cfg.Bands > 0 then
		local bands: { { number } } = {}
		local ok = true
		for _, band in ipairs(cfg.Bands) do
			if type(band) ~= "table" or not finite(band[1]) or not finite(band[2]) or not finite(band[3]) then
				ok = false
				break
			end
			if band[3] < 1 or band[3] > 3 or band[2] < band[1] then
				ok = false
				break
			end
			table.insert(bands, { band[1], band[2], band[3] })
		end
		if ok then
			P.Bands = bands
		end
	end
	P.LevelFactor = takeList(cfg.LevelFactor, 5, 0.1, 10) or P.LevelFactor
	P.LevelCost = takeList(cfg.LevelCost, 4, 0, 1000) or P.LevelCost
	takeNum(p, "UpgradeMin", cfg.UpgradeMin, 0, 1e9)
	takeNum(p, "RoomChangePct", cfg.RoomChangePct, 0, 1)
	local eff = cfg.Efficiency
	if type(eff) == "table" then
		takeNum(p, "EffBase", eff.Base, 1, 1e9)
		takeNum(p, "EffRatio", eff.Ratio, 1, 10)
		if finite(eff.Max) and eff.Max >= 1 and eff.Max <= 40 and eff.Max % 1 == 0 then
			P.EffMax = eff.Max
		end
	end
	local build = cfg.Build
	if type(build) == "table" then
		takeNum(p, "BuildInstant", build.Instant, 0, 50)
		takeNum(p, "BuildScene", build.SceneSeconds, 0, 60)
		takeNum(p, "BuildBase", build.BaseSeconds, 1, 3600)
		takeNum(p, "BuildRatio", build.Ratio, 1, 3)
		takeNum(p, "BuildCap", build.Cap, 1, 86400)
		takeNum(p, "BuildMinFactor", build.MinFactor, 0.01, 1)
	end
	if type(cfg.Stages) == "table" and #cfg.Stages == 12 then
		local first, licence, ipo = {}, {}, {}
		local ok = true
		for i, stage in ipairs(cfg.Stages) do
			if type(stage) ~= "table" or not finite(stage.First) or not finite(stage.Licence) then
				ok = false
				break
			end
			first[i] = stage.First
			licence[i] = stage.Licence
			ipo[i] = if finite(stage.Ipo) then stage.Ipo else 0
		end
		if ok and first[1] == 1 then
			P.StageFirst, P.StageLicence, P.StageIpo = first, licence, ipo
		end
	end
	if type(cfg.Rooms) == "table" then
		for _, room in ipairs(cfg.Rooms) do
			if type(room) == "table" and type(room.Key) == "string" and finite(room.Factor) then
				ROOMS[room.Key] = {
					Factor = math.clamp(room.Factor, 0, 5),
					StaffMult = if finite(room.StaffMult) then math.clamp(room.StaffMult, 1, 3) else 1,
					Radius = if finite(room.Radius) then math.clamp(math.floor(room.Radius), 0, 10) else 0,
					TowerStaffMult = if finite(room.TowerStaffMult) then math.clamp(room.TowerStaffMult, 1, 3) else 1,
					NeighbourMult = if finite(room.NeighbourMult) then math.clamp(room.NeighbourMult, 1, 3) else 1,
					Max = if finite(room.Max) and room.Max >= 1 then math.floor(room.Max) else HUGE,
				}
			end
		end
	end
	if type(cfg.Staff) == "table" then
		for _, staff in ipairs(cfg.Staff) do
			if type(staff) == "table" and type(staff.Key) == "string" then
				STAFF[staff.Key] = {
					Bonus = if finite(staff.Bonus) then math.clamp(staff.Bonus, 0, 10) else 0,
					CostMult = if finite(staff.CostMult) then math.clamp(staff.CostMult, 0, 1000) else 0,
					Price = if finite(staff.Price) then math.clamp(math.floor(staff.Price), 0, 1e13) else 0,
					Lobby = staff.Lobby == true,
				}
			end
		end
	end
	local decor = cfg.Decor
	if type(decor) == "table" then
		takeNum(p, "ComfortPct", decor.ComfortPct, 0, 0.1)
		takeNum(p, "ComfortMax", decor.ComfortMax, 0, 1)
		takeNum(p, "ComfortItemMax", decor.ComfortItemMax, 1, 20)
	end
	local mult = cfg.Mult
	if type(mult) == "table" then
		takeNum(p, "TimedCap", mult.TimedCap, 1, 10)
		takeNum(p, "EventMax", mult.EventMax, 1, 3)
	end
	takeNum(p, "VaultMinutes", cfg.VaultMinutes, 1, 240)
	takeNum(p, "VaultFloorBonus", cfg.VaultFloorBonus, 0, 5)
	if type(cfg.Rooms) == "table" then
		for _, room in ipairs(cfg.Rooms) do
			if type(room) == "table" and room.Key == "Vault" and finite(room.Max) then
				P.VaultFloorMax = math.clamp(math.floor(room.Max), 0, 50)
			end
		end
	end
	local off = cfg.Offline
	if type(off) == "table" then
		takeNum(p, "OffRate", off.Rate, 0, 1)
		takeNum(p, "OffRateMax", off.RateMax, 0, 1)
		takeNum(p, "OffCapHours", off.CapHours, 0, 48)
		takeNum(p, "OffCapMax", off.CapMax, 0, 48)
		takeNum(p, "OffPerkRate", off.PerkRate, 0, 0.2)
		takeNum(p, "OffPerkHours", off.PerkHours, 0, 6)
		takeNum(p, "OffPerkMax", off.PerkMax, 0, 20)
		takeNum(p, "OffPassRate", off.PassRate, 0, 1)
		takeNum(p, "OffPassMinHours", off.PassMinHours, 0, 48)
		takeNum(p, "OffLoungeHours", off.LoungeHours, 0, 6)
		takeNum(p, "OffLoungeMax", off.LoungeMax, 0, 20)
		takeNum(p, "OffClubHours", off.ClubHours, 0, 24)
	end
	rebuildTables()
end

-- ---------------------------------------------------------------------
-- 3) ETAGEN
-- ---------------------------------------------------------------------
local function validFloor(n: any): boolean
	return finite(n) and n >= 1 and n <= P.Floors and n % 1 == 0
end

function TowerMath.Clamp(n: number): number
	if type(n) ~= "number" or n ~= n then
		return 0
	end
	if n >= MAX_MONEY then
		return MAX_MONEY
	end
	if n <= 0 then
		return 0
	end
	return math.floor(n)
end

function TowerMath.FloorCost(n: number): number
	if not validFloor(n) then
		return 0
	end
	return COST[n]
end

function TowerMath.FloorIncome(n: number): number
	if not validFloor(n) then
		return 0
	end
	return INCOME[n]
end

function TowerMath.BuildTime(n: number): number
	if not validFloor(n) then
		return 0
	end
	if n <= P.BuildInstant then
		return P.BuildScene
	end
	return math.min(P.BuildCap, P.BuildBase * P.BuildRatio ^ (n - 10))
end

-- Bauzeit mit Beschleunigern: speedFactor = Π (1 − Rabatt) (Bau-Crew, Tempo, Admin-Bau-Boom), nie unter MinFactor.
-- Szene-Etagen (1 … Instant) bleiben bei der Szenen-Länge.
function TowerMath.BuildSeconds(n: number, speedFactor: number?): number
	local base = TowerMath.BuildTime(n)
	if base <= 0 or n <= P.BuildInstant then
		return base
	end
	local factor = if finite(speedFactor) then math.clamp(speedFactor :: number, 0, 1) else 1
	return base * math.max(P.BuildMinFactor, factor)
end

-- Grundlage für Raum-Stufen und Personal: max(Etagenkosten, UpgradeMin)
local function upgradeBase(n: number): number
	return math.max(TowerMath.FloorCost(n), P.UpgradeMin)
end

function TowerMath.LevelCost(n: number, l: number): number
	if not validFloor(n) or not finite(l) or l % 1 ~= 0 or l < 1 or l > #P.LevelCost then
		return 0
	end
	return TowerMath.Clamp(roundHalfEven(upgradeBase(n) * P.LevelCost[l]))
end

function TowerMath.StaffCost(n: number, key: string): number
	local staff = STAFF[key]
	if staff == nil then
		return 0
	end
	if staff.Lobby then
		return TowerMath.Clamp(staff.Price)
	end
	if not validFloor(n) then
		return 0
	end
	return TowerMath.Clamp(roundHalfEven(upgradeBase(n) * staff.CostMult))
end

function TowerMath.EfficiencyCost(k: number): number
	if not finite(k) or k % 1 ~= 0 or k < 0 or k >= P.EffMax then
		return 0
	end
	return TowerMath.Clamp(roundHalfEven(P.EffBase * P.EffRatio ^ k))
end

function TowerMath.RoomChangeCost(n: number): number
	if not validFloor(n) then
		return 0
	end
	return TowerMath.Clamp(roundHalfEven(TowerMath.FloorCost(n) * P.RoomChangePct))
end

-- Rabatt anwenden (Vorstand "Bau", Bau-Boom): gerundet, geklemmt, nie 0 für etwas, das etwas kostet
function TowerMath.Discount(cost: number, mult: number): number
	if not finite(cost) or cost <= 0 then
		return 0
	end
	local m = if finite(mult) then math.clamp(mult, 0, 1) else 1
	return math.max(1, TowerMath.Clamp(roundHalfEven(cost * m)))
end

-- ---------------------------------------------------------------------
-- 4) STUFEN & TORE
-- ---------------------------------------------------------------------
function TowerMath.StageOf(floors: number): number
	if not finite(floors) or floors < 1 then
		return 1 -- Bauplatz = Stufe 1 ohne Büro (§B4.2)
	end
	local stage = 1
	for i, first in ipairs(P.StageFirst) do
		if floors >= first then
			stage = i
		end
	end
	return stage
end

function TowerMath.StageRange(stage: number): (number, number)
	local count = #P.StageFirst
	if not finite(stage) or stage < 1 or stage > count or stage % 1 ~= 0 then
		return 0, 0
	end
	local first = P.StageFirst[stage]
	local last = if stage < count then P.StageFirst[stage + 1] - 1 else P.Floors
	return first, last
end

-- Tor (Lizenz-Index, Mindest-Börsengänge) für den Bau von Etage n
function TowerMath.GateFor(n: number): (number, number)
	if not validFloor(n) then
		return 1, 0
	end
	local stage = TowerMath.StageOf(n)
	return P.StageLicence[stage] or 1, P.StageIpo[stage] or 0
end

-- ---------------------------------------------------------------------
-- 5) EINKOMMEN (§B5.2)
--    Etage(n) = I(n) × Raum × Stufe(L) × (1 + Σ Personal × Café × Server) × Labor-Nachbarn × (1 + Komfort)
--    Basis    = Gehalt + Σ Etage(n)
-- ---------------------------------------------------------------------
local function roomOf(floor: any): RoomParams
	if type(floor) ~= "table" then
		return DEFAULT_ROOM
	end
	return ROOMS[floor.R] or DEFAULT_ROOM
end

-- Server-Faktor für alle Personal-Boni (je Server-Raum, höchstens Max Räume)
local function serverFactor(floors: { FloorData }, count: number): number
	local servers = 0
	local mult, cap = 1, HUGE
	for i = 1, count do
		local room = roomOf(floors[i])
		if room.TowerStaffMult > 1 then
			servers += 1
			mult = room.TowerStaffMult
			cap = room.Max
		end
	end
	return mult ^ math.min(servers, cap)
end

local function comfortOf(floor: FloorData, ctx: Ctx?): number
	local fn = ctx and ctx.Comfort
	if fn == nil or type(floor.D) ~= "table" then
		return 0
	end
	local pct = if ctx and finite(ctx.ComfortPct) then ctx.ComfortPct :: number else P.ComfortPct
	local cap = if ctx and finite(ctx.ComfortMax) then ctx.ComfortMax :: number else P.ComfortMax
	local points = 0
	for index, key in ipairs(floor.D) do
		if index > 16 then
			break
		end
		if type(key) == "string" and key ~= "" then
			local ok, value = pcall(fn, key)
			if ok and finite(value) then
				points += math.clamp(value, 0, P.ComfortItemMax)
			end
		end
	end
	return math.clamp(points * pct, 0, math.max(0, cap))
end

local function floorIncome(floors: { FloorData }, i: number, count: number, serverF: number, ctx: Ctx?): number
	local floor = floors[i]
	if type(floor) ~= "table" then
		return 0
	end
	local room = roomOf(floor)
	if room.Factor <= 0 then
		return 0
	end
	local level = if finite(floor.L) then math.clamp(math.floor(floor.L), 1, #P.LevelFactor) else 1
	-- Personal-Boni (höchstens 3 Plätze zählen)
	local staffSum = 0
	if type(floor.S) == "table" then
		for index, key in ipairs(floor.S) do
			if index > 3 then
				break
			end
			local staff = STAFF[key]
			if staff and not staff.Lobby then
				staffSum += staff.Bonus
			end
		end
	end
	-- Smoothie-Café in Reichweite ±Radius (stapelt nicht – der stärkste Raum in Reichweite zählt)
	local cafe = 1
	if staffSum > 0 then
		for j = math.max(1, i - maxStaffRadius), math.min(count, i + maxStaffRadius) do
			local params = roomOf(floors[j])
			if params.StaffMult > cafe and math.abs(j - i) <= params.Radius then
				cafe = params.StaffMult
			end
		end
	end
	-- Labor-Nachbarn (je Labor direkt darüber/darunter)
	local neighbour = 1
	if i > 1 then
		neighbour *= roomOf(floors[i - 1]).NeighbourMult
	end
	if i < count then
		neighbour *= roomOf(floors[i + 1]).NeighbourMult
	end
	local comfort = comfortOf(floor, ctx)
	return INCOME[i] * room.Factor * P.LevelFactor[level] * (1 + staffSum * cafe * serverF) * neighbour * (1 + comfort)
end

local function floorCount(floors: any): number
	if type(floors) ~= "table" then
		return 0
	end
	return math.min(#floors, P.Floors)
end

function TowerMath.BaseIncome(floors: { FloorData }, ctx: Ctx?): number
	local count = floorCount(floors)
	local total = P.Salary
	if count == 0 then
		return total
	end
	local serverF = serverFactor(floors, count)
	for i = 1, count do
		total += floorIncome(floors, i, count, serverF, ctx)
	end
	return total
end

function TowerMath.FloorIncomeAt(floors: { FloorData }, i: number, ctx: Ctx?): number
	local count = floorCount(floors)
	if not finite(i) or i < 1 or i > count or i % 1 ~= 0 then
		return 0
	end
	return floorIncome(floors, i, count, serverFactor(floors, count), ctx)
end

-- ---------------------------------------------------------------------
-- 6) MULTIPLIKATOREN (§B5.2)
--    Perm   = 1 + Σ Werte (additiv)            Trader = Π Werte (Lizenz × Ruf)
--    Pass   = 1 + Σ (Wert − 1) (x2 = 2, x3 = 3 -> zusammen ×4)
--    Fixed  = Π Werte (VIP × Club × Premium)    Timed = min(TimedCap, Π Werte), Event-Teile ≤ EventMax
-- ---------------------------------------------------------------------
local EVENT_KEYS = { Event = true, GoldenHour = true, Admin = true }

function TowerMath.Groups(parts: { MultPart }): Groups
	local perm, trader, pass, fixed, timed = 1, 1, 1, 1, 1
	if type(parts) ~= "table" then
		return { Perm = 1, Trader = 1, Pass = 1, Fixed = 1, Timed = 1 }
	end
	for index, part in ipairs(parts) do
		if index > 64 then
			break
		end
		if type(part) ~= "table" or not finite(part.Value) then
			continue
		end
		local value = part.Value
		local group = part.Group
		if group == "Perm" then
			perm += math.max(0, value)
		elseif group == "Trader" then
			trader *= math.clamp(value, 1, 10)
		elseif group == "Pass" then
			pass += math.clamp(value, 1, 10) - 1
		elseif group == "Fixed" then
			fixed *= math.clamp(value, 1, 10)
		elseif group == "Timed" then
			local v = math.clamp(value, 1, P.TimedCap)
			if EVENT_KEYS[part.Key] then
				v = math.min(v, P.EventMax)
			end
			timed *= v
		end
	end
	return { Perm = perm, Trader = trader, Pass = pass, Fixed = fixed, Timed = timed }
end

function TowerMath.Multiplier(parts: { MultPart }): (number, number)
	local g = TowerMath.Groups(parts)
	local steady = g.Perm * g.Trader * g.Pass * g.Fixed
	return steady * math.min(P.TimedCap, g.Timed), steady
end

function TowerMath.PassFactor(has2x: boolean, has3x: boolean): number
	return 1 + (if has2x then 1 else 0) + (if has3x then 2 else 0)
end

-- ---------------------------------------------------------------------
-- 7) TRESOR & OFFLINE (§B4.6)
-- ---------------------------------------------------------------------
function TowerMath.VaultCap(perSec: number, vaultFloors: number): number
	if not finite(perSec) or perSec <= 0 then
		return 0
	end
	local floors = if finite(vaultFloors) then math.clamp(math.floor(vaultFloors), 0, P.VaultFloorMax) else 0
	return TowerMath.Clamp(perSec * 60 * P.VaultMinutes * (1 + P.VaultFloorBonus * floors))
end

function TowerMath.OfflineRate(tresorPerk: number, hasPass: boolean): number
	local perk = if finite(tresorPerk) then math.clamp(math.floor(tresorPerk), 0, P.OffPerkMax) else 0
	local rate = P.OffRate + P.OffPerkRate * perk + (if hasPass then P.OffPassRate else 0)
	return math.clamp(rate, 0, P.OffRateMax)
end

-- Offline-Deckel in Sekunden
function TowerMath.OfflineCap(tresorPerk: number, lounges: number, club: boolean, hasPass: boolean): number
	local perk = if finite(tresorPerk) then math.clamp(math.floor(tresorPerk), 0, P.OffPerkMax) else 0
	local lounge = if finite(lounges) then math.clamp(math.floor(lounges), 0, P.OffLoungeMax) else 0
	local hours = P.OffCapHours + P.OffPerkHours * perk + P.OffLoungeHours * lounge
	if club then
		hours += P.OffClubHours
	end
	if hasPass then
		hours = math.max(hours, P.OffPassMinHours)
	end
	return math.clamp(hours, 0, P.OffCapMax) * 3600
end

function TowerMath.Offline(steadyPerSec: number, seconds: number, rate: number, capSeconds: number): number
	if not finite(steadyPerSec) or not finite(seconds) or not finite(rate) or not finite(capSeconds) then
		return 0
	end
	if steadyPerSec <= 0 or seconds <= 0 or rate <= 0 or capSeconds <= 0 then
		return 0
	end
	local away = math.min(seconds, capSeconds)
	return TowerMath.Clamp(steadyPerSec * math.min(rate, 1) * away)
end

-- ---------------------------------------------------------------------
-- 8) BÖRSENGANG-STERNE (§B9.6): ★ = floor(4 · log10(Lauf-Ausgaben / 1e6)), 0 unter 1e7
-- ---------------------------------------------------------------------
function TowerMath.Stars(runSpend: number): number
	if not finite(runSpend) or runSpend < P.StarsMin then
		return 0
	end
	return math.max(0, math.floor(P.StarsK * math.log10(runSpend / P.StarsDiv)))
end

-- ---------------------------------------------------------------------
-- 9) START: Tabellen bauen, in Roblox Config.Tower übernehmen (Luau-CLI: "script" fehlt -> Startwerte)
-- ---------------------------------------------------------------------
rebuildTables()
do
	local ok, cfg = pcall(function(): any
		local here: any = script
		if typeof(here) ~= "Instance" then
			return nil
		end
		local configModule = here.Parent and here.Parent:FindFirstChild("Config")
		local towerModule = configModule and configModule:FindFirstChild("Tower")
		if towerModule and towerModule:IsA("ModuleScript") then
			local loaded, result = pcall(require, towerModule)
			return if loaded then result else nil
		end
		return nil
	end)
	if ok and type(cfg) == "table" then
		TowerMath.Configure(cfg)
	end
end

return TowerMath
