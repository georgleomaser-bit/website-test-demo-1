-- =====================================================================
--  AKYTEX TYCOON – Selbsttests Turm-Ökonomie (Server/Tests/TowerTests)
--  Besitzer: WP6 (Turm-Ökonomie). Vertrag: DESIGN.md §D WP6 "Abnahme"/"Tests", §C17 (TowerMath == Tabelle §B5.1,
--  alle Preise < 1e14 ganzzahlig, Multiplikator-Deckel ×10). SelfTestService lädt dieses Modul; jeder Fehler = FAIL.
--  Alle Tests laufen auf Kopien von DataService.DefaultData() mit einem künstlichen CR-Konto (Attrappen-Env) –
--  keine Spieler, keine echten Spielstände, kein ShopService nötig.
--
--  Prüft: Tabellen, Preis-Grenzen, Stufen-Tore (Lizenz + Börsengang), eine Baustelle, Bauzeit-Untergrenze,
--  Abteilungen (Mindest-Stufe, Penthouse oben, Höchstzahl, Wechselkosten), Nachbar-Effekte, Penthouse wandert mit,
--  Personal-Plätze (Personal+), Raum-Stufen, Effizienz (Deckel 20, Vorstand-Rabatt), Multiplikator-Gruppen
--  (x2 ×2, x3 ×3, beide ×4, Zeitlich ×10, Event ≤ ×3), Offline (3 h exakt, Deckel, ohne Sozial/Zeitlich),
--  Börsengang-Reset behält Depot/Lizenz/Lager, Transfer-Fluss nur AKY -> CR, Bau-Hilfe, Bau-Express, Reparatur,
--  Deko-Plätze, Privat-Etagen, Auto-Plan, Live-Felder.
-- =====================================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared:WaitForChild("Util"))
local Config = require(Shared:WaitForChild("Config"))
local TowerMath = require(Shared:WaitForChild("TowerMath"))

local function eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(("%s erwartet %s, bekommen %s"):format(label or "Wert", tostring(expected), tostring(actual)), 2)
	end
end

local function near(actual: number, expected: number, tolerance: number, label: string?)
	if math.abs(actual - expected) > tolerance then
		error(("%s erwartet ≈%s, bekommen %s"):format(label or "Wert", tostring(expected), tostring(actual)), 2)
	end
end

local function truthy(value: any, label: string)
	if not value then
		error(label, 2)
	end
end

local function serviceModule(services: any, name: string): any
	local svc = services and services[name]
	if svc then
		return svc
	end
	local module = script.Parent.Parent:WaitForChild("Services"):FindFirstChild(name)
	assert(module and module:IsA("ModuleScript"), name .. " fehlt")
	return require(module) :: any
end

local function core(services: any): any
	return serviceModule(services, "TowerService")._Test.Core
end

local function newFactors(services: any): any
	return serviceModule(services, "TowerService")._Test.Factors()
end

-- frischer Spielstand (Kopie) mit reparierten Turm-Daten
local function newData(services: any): { [string]: any }
	local data = serviceModule(services, "DataService").DefaultData()
	core(services).Repair(data)
	return data
end

-- künstliches CR-Konto + Lager + Pässe/Perks (Attrappen-Env, gleiche Form wie TowerService._Env)
local function fakeEnv(opts: { [string]: any }?): (any, { [string]: any })
	local o = opts or {}
	local account = {
		Balance = o.Credits or 0,
		Debits = {} :: { { any } },
		Credits = {} :: { { any } },
		Storage = o.Storage or {},
		Passes = o.Passes or {},
		Perks = o.Perks or {},
		FailDebit = o.FailDebit == true,
	}
	local env = {
		Now = o.Now or 1000000,
		Licence = o.Licence or 1,
		Ipo = o.Ipo or 0,
		Perk = function(key: string): number
			return account.Perks[key] or 0
		end,
		HasPass = function(key: string): boolean
			return account.Passes[key] == true
		end,
		Balance = function(): number
			return account.Balance
		end,
		Debit = function(amount: number, sink: string): boolean
			if account.FailDebit or amount > account.Balance or amount % 1 ~= 0 then
				return false
			end
			account.Balance -= amount
			table.insert(account.Debits, { amount, sink })
			return true
		end,
		Credit = function(amount: number, source: string): boolean
			account.Balance += amount
			table.insert(account.Credits, { amount, source })
			return true
		end,
		TakeDecor = function(key: string): boolean
			local n = account.Storage[key] or 0
			if n <= 0 then
				return false
			end
			account.Storage[key] = n - 1
			return true
		end,
		ReturnDecor = function(key: string)
			account.Storage[key] = (account.Storage[key] or 0) + 1
		end,
		Comfort = function(_key: string): number
			return 2
		end,
		Owns = function(entry: any): boolean
			return entry.Unlock == "Default"
		end,
		BuildEvent = 1,
		CostEvent = function(_kind: string): number
			return o.CostEvent or 1
		end,
	}
	return env, account
end

-- n Etagen direkt bauen (Bau starten + sofort fertigstellen)
local function buildFloors(services: any, data: any, env: any, n: number)
	local c = core(services)
	for _ = 1, n do
		local ok, key = c.StartBuild(data.Tower, env)
		assert(ok, "Bau gescheitert: " .. tostring(key))
		data.Tower.Build.Until = env.Now
		local floor = c.FinishBuild(data.Tower, env)
		assert(floor, "FinishBuild ohne Etage")
	end
end

local function deepEqual(a: any, b: any, path: string): (boolean, string?)
	if type(a) ~= type(b) then
		return false, path
	end
	if type(a) ~= "table" then
		if a ~= b then
			return false, path
		end
		return true, nil
	end
	for key, value in pairs(a) do
		local ok, where = deepEqual(value, b[key], path .. "." .. tostring(key))
		if not ok then
			return false, where
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false, path .. "." .. tostring(key)
		end
	end
	return true, nil
end

local Tests = {}

-- ---------------------------------------------------------------------
-- 1) Tabellen & Grenzen (§C17)
-- ---------------------------------------------------------------------
Tests["TowerMath == Tabelle §B5.1"] = function()
	local rows = {
		{ 1, 0, 4.0 },
		{ 2, 1000, 5.2 },
		{ 4, 2250, 8.8 },
		{ 7, 7594, 19.3 },
		{ 10, 25629, 42.4 },
		{ 13, 89957, 93.2 },
		{ 14, 140334, 121.2 },
		{ 18, 831113, 346.0 },
		{ 21, 3155251, 760.2 },
		{ 22, 4922192, 988 },
		{ 25, 18686689, 2171 },
		{ 26, 29524969, 2823 },
		{ 30, 183999992, 8062 },
		{ 31, 290719987, 10480 },
		{ 37, 4522904446, 50585 },
		{ 40, 17839746280, 111135 },
		{ 44, 116914561223, 317413 },
		{ 50, 1961500847186, 1532090 },
	}
	for _, row in ipairs(rows) do
		eq(TowerMath.FloorCost(row[1]), row[2], "Kosten Etage " .. row[1])
		near(TowerMath.FloorIncome(row[1]), row[3], math.max(0.051, row[3] * 0.0005), "Einkommen Etage " .. row[1])
	end
	local sum = 0
	for n = 1, 50 do
		sum += TowerMath.FloorCost(n)
	end
	eq(sum, 5231695359616, "Summe 5,23e12")
	near(TowerMath.BuildTime(22) / 60, 10.2, 0.05, "Bauzeit Etage 22")
	eq(TowerMath.BuildTime(30), 5400, "Bauzeit ab 30")
end

Tests["Alle Preise < 1e14 und ganzzahlig"] = function()
	local function ok(value: number, label: string)
		truthy(Util.IsFinite(value) and value >= 0 and value % 1 == 0, label .. ": ganzzahlig ≥ 0")
		truthy(value < 1e14, label .. (": %s ≥ 1e14"):format(tostring(value)))
	end
	local worst = 0
	for n = 1, 50 do
		ok(TowerMath.FloorCost(n), "Etage " .. n)
		ok(TowerMath.RoomChangeCost(n), "Wechsel " .. n)
		for l = 1, 4 do
			ok(TowerMath.LevelCost(n, l), ("Raum-Stufe %d/%d"):format(n, l))
			worst = math.max(worst, TowerMath.LevelCost(n, l))
		end
		for _, staff in ipairs(Config.Tower.Staff) do
			ok(TowerMath.StaffCost(n, staff.Key), ("Personal %s/%d"):format(staff.Key, n))
			worst = math.max(worst, TowerMath.StaffCost(n, staff.Key))
		end
	end
	for k = 0, 19 do
		ok(TowerMath.EfficiencyCost(k), "Effizienz " .. k)
	end
	near(worst, 4.9e13, 0.01e13, "teuerster Einzelpreis (Quant Etage 50)")
	eq(TowerMath.Clamp(1e20), 9e15, "Klemmung 9e15")
end

-- ---------------------------------------------------------------------
-- 2) Bauen & Tore (§B4.2, §B4.7)
-- ---------------------------------------------------------------------
Tests["Stufen-Tore: Lizenz und Börsengang"] = function(services)
	local c = core(services)
	local data = newData(services)
	local env = fakeEnv({ Credits = 1e13, Licence = 1 })
	buildFloors(services, data, env, 9)
	eq(#data.Tower.Floors, 9)
	local ok, key = c.StartBuild(data.Tower, env)
	eq(ok, false, "Etage 10 ohne Azubi II")
	eq(key, "tower.gateLicence")
	env.Licence = 2
	ok = c.StartBuild(data.Tower, env)
	eq(ok, true, "Etage 10 mit Azubi II")
	-- Orbit-Spire: Fondsmanager I UND ≥ 1 Börsengang
	local env2 = fakeEnv({ Credits = 1e14, Licence = 7, Ipo = 0 })
	local data2 = newData(services)
	c.SetFloors(data2.Tower, env2, 43)
	ok, key = c.StartBuild(data2.Tower, env2)
	eq(ok, false, "Etage 44 ohne Börsengang")
	eq(key, "tower.gateIpo")
	env2.Ipo = 1
	ok = c.StartBuild(data2.Tower, env2)
	eq(ok, true, "Etage 44 mit Börsengang")
	-- Robux überspringen kein Tor: Pässe ändern nichts
	local env3 =
		fakeEnv({ Credits = 1e13, Licence = 1, Passes = { Income2x = true, Income3x = true, BuildCrew = true } })
	local data3 = newData(services)
	buildFloors(services, data3, env3, 9)
	ok, key = c.StartBuild(data3.Tower, env3)
	eq(ok, false, "Pässe öffnen kein Lizenz-Tor")
	eq(key, "tower.gateLicence")
end

Tests["Bauen: eine Baustelle, Kosten, Lauf-Ausgaben"] = function(services)
	local c = core(services)
	local data = newData(services)
	local env, account = fakeEnv({ Credits = 5000 })
	local ok, _, _, result = c.StartBuild(data.Tower, env)
	eq(ok, true, "Etage 1")
	eq(result.Cost, 0, "Etage 1 gratis")
	local busy, key = c.StartBuild(data.Tower, env)
	eq(busy, false, "zweite Baustelle")
	eq(key, "tower.craneBusy")
	data.Tower.Build.Until = env.Now
	c.FinishBuild(data.Tower, env)
	ok, _, _, result = c.StartBuild(data.Tower, env)
	eq(ok, true, "Etage 2")
	eq(result.Cost, 1000)
	eq(account.Balance, 4000, "1.000 CR abgebucht")
	eq(account.Debits[1][2], "Floor", "Senke Floor")
	eq(data.Tower.RunSpend, 1000, "Lauf-Ausgaben")
	data.Tower.Build.Until = env.Now
	c.FinishBuild(data.Tower, env)
	-- zu wenig CR
	account.Balance = 10
	ok, key = c.StartBuild(data.Tower, env)
	eq(ok, false)
	eq(key, "tower.noCredits")
	eq(data.Tower.Build.Floor, nil, "keine Baustelle ohne Bezahlung")
end

Tests["Bauzeit: Beschleuniger nie unter 25 %, Bau-Boom-Rabatt"] = function(services)
	local c = core(services)
	local env = fakeEnv({ Passes = { BuildCrew = true }, Perks = { Tempo = 5 } })
	eq(c.BuildSeconds(30, env), 5400 * 0.25, "Crew −50 % × Tempo −50 % = Untergrenze")
	env.BuildEvent = 0.1
	eq(c.BuildSeconds(30, env), 5400 * 0.25, "Admin-Bau-Boom: Untergrenze bleibt")
	local plain = fakeEnv({})
	eq(c.BuildSeconds(30, plain), 5400)
	eq(c.BuildSeconds(5, env), 3, "Szene bleibt 3 s")
	-- Kosten: Vorstand "Bau" −5 %/Stufe × Bau-Boom
	local discounted = fakeEnv({ Perks = { Build = 8 }, CostEvent = 0.75 })
	near(c.CostFactor(discounted, "Floor"), 0.6 * 0.75, 1e-12, "Etagen: Perk × Bau-Boom")
	near(c.CostFactor(discounted, nil), 0.6, 1e-12, "Personal/Effizienz: nur Perk")
end

-- ---------------------------------------------------------------------
-- 3) Abteilungen, Nachbar-Effekte, Personal, Raum-Stufen, Effizienz
-- ---------------------------------------------------------------------
Tests["Abteilungen: Mindest-Stufe, Penthouse oben, Höchstzahl, Wechselkosten"] = function(services)
	local c = core(services)
	local data = newData(services)
	local env, account = fakeEnv({ Credits = 1e12, Licence = 10, Ipo = 1 })
	buildFloors(services, data, env, 5)
	local ok, key = c.SetRoom(data.Tower, env, 3, "Lab")
	eq(ok, false, "Labor erst ab Stufe 5")
	eq(key, "tower.roomLocked")
	buildFloors(services, data, env, 5) -- 10 Etagen = Stufe 5
	local before = account.Balance
	ok = c.SetRoom(data.Tower, env, 3, "Lab")
	eq(ok, true, "Labor auf Etage 3")
	eq(before - account.Balance, TowerMath.RoomChangeCost(3), "Wechsel = 25 % der Etagenkosten")
	ok, key = c.SetRoom(data.Tower, env, 3, "Lab")
	eq(key, "tower.roomSame")
	eq(c.SetRoom(data.Tower, env, 4, "Vault"), true)
	eq(c.SetRoom(data.Tower, env, 5, "Vault"), true)
	ok, key = c.SetRoom(data.Tower, env, 6, "Vault")
	eq(key, "tower.roomMax", "höchstens 2 Tresor-Etagen")
	ok, key = c.SetRoom(data.Tower, env, 9, "Penthouse")
	eq(key, "tower.roomLocked", "Penthouse ab Stufe 10")
	buildFloors(services, data, env, 21) -- 31 Etagen = Stufe 10
	ok, key = c.SetRoom(data.Tower, env, 30, "Penthouse")
	eq(key, "tower.roomTopOnly")
	eq(c.SetRoom(data.Tower, env, 31, "Penthouse"), true, "Penthouse oben")
	eq(c.RoomCount(data.Tower, "Vault"), 2)
end

Tests["Nachbar-Effekte im Tower (Labor, Café, Server)"] = function(services)
	local c = core(services)
	local data = newData(services)
	local env = fakeEnv({ Credits = 1e12, Licence = 10 })
	buildFloors(services, data, env, 10)
	local floors = data.Tower.Floors
	local i2 = TowerMath.FloorIncome(2)
	near(TowerMath.FloorIncomeAt(floors, 2, nil), i2, 1e-9, "Büro ohne Nachbarn")
	assert(c.SetRoom(data.Tower, env, 3, "Lab"))
	near(TowerMath.FloorIncomeAt(floors, 2, nil), i2 * 1.15, 1e-9, "Labor darüber ×1,15")
	assert(c.SetRoom(data.Tower, env, 1, "Lab"))
	near(TowerMath.FloorIncomeAt(floors, 2, nil), i2 * 1.15 * 1.15, 1e-9, "Labor darüber und darunter")
	-- Café ±2 auf Personal-Boni
	assert(c.Hire(data.Tower, env, 6, "Analyst"))
	local i6 = TowerMath.FloorIncome(6)
	near(TowerMath.FloorIncomeAt(floors, 6, nil), i6 * 1.25, 1e-9, "Analyst +25 %")
	assert(c.SetRoom(data.Tower, env, 8, "Cafe"))
	near(TowerMath.FloorIncomeAt(floors, 6, nil), i6 * (1 + 0.25 * 1.2), 1e-9, "Café 2 Etagen weiter")
	-- Server-Raum: alle Personal-Boni ×1,1
	assert(c.SetRoom(data.Tower, env, 10, "Server"))
	near(TowerMath.FloorIncomeAt(floors, 6, nil), i6 * (1 + 0.25 * 1.2 * 1.1), 1e-9, "Server ×1,1")
end

Tests["Penthouse wandert beim Bau nach oben (mit Deko)"] = function(services)
	local c = core(services)
	local data = newData(services)
	local env = fakeEnv({ Credits = 1e13, Licence = 10, Storage = { sofa = 4 } })
	c.SetFloors(data.Tower, env, 31)
	assert(c.SetRoom(data.Tower, env, 31, "Penthouse"))
	for slot = 1, 4 do
		assert(c.SetDecor(data.Tower, env, 31, slot, "sofa"))
	end
	eq(c.DecorSlots(data.Tower, 31), 8, "Penthouse 8 Plätze")
	buildFloors(services, data, env, 1)
	local floors = data.Tower.Floors
	eq(floors[32].R, "Penthouse", "neue oberste Etage")
	eq(#floors[32].D, 4, "Deko zieht mit")
	eq(floors[31].R, Config.Tower.DefaultRoom, "alte Etage wird Büro")
	eq(#floors[31].D, 0)
end

Tests["Personal: 2 Plätze, 3 mit Personal+, Mindest-Stufe, Lobby-Bots"] = function(services)
	local c = core(services)
	local data = newData(services)
	local env, account = fakeEnv({ Credits = 1e12, Licence = 10 })
	buildFloors(services, data, env, 7) -- Stufe 4
	eq(c.Hire(data.Tower, env, 5, "Intern"), true)
	eq(c.Hire(data.Tower, env, 5, "Analyst"), true)
	local ok, key = c.Hire(data.Tower, env, 5, "Intern")
	eq(ok, false)
	eq(key, "tower.slotsPlus", "3. Platz nur mit Personal+")
	account.Passes.StaffPlus = true
	eq(c.Hire(data.Tower, env, 5, "Intern"), true, "3. Platz mit Personal+")
	ok, key = c.Hire(data.Tower, env, 5, "Intern")
	eq(key, "tower.slotsFull")
	ok, key = c.Hire(data.Tower, env, 6, "Quant")
	eq(key, "tower.staffLocked", "Quant ab Stufe 8")
	-- Kosten: ×1 / ×3 von max(C(n), 500)
	local balance = account.Balance
	assert(c.Hire(data.Tower, env, 6, "Analyst"))
	eq(balance - account.Balance, TowerMath.StaffCost(6, "Analyst"), "Analyst-Kosten")
	-- Lobby: Hausmeister gratis, je 1
	balance = account.Balance
	eq(c.Hire(data.Tower, env, 0, "Janitor"), true)
	eq(account.Balance, balance, "Hausmeister gratis")
	ok, key = c.Hire(data.Tower, env, 0, "Janitor")
	eq(key, "tower.uniqueOwned")
	-- Entlassen ohne Erstattung
	balance = account.Balance
	local fired, _, staffKey = c.Fire(data.Tower, 5, 1)
	eq(fired, true)
	eq(staffKey, "Intern")
	eq(account.Balance, balance, "keine Rückerstattung")
	eq(#data.Tower.Floors[5].S, 2)
	eq(c.Fire(data.Tower, 0, 1), true, "Hausmeister entlassen")
	eq(data.Tower.Janitor, false)
end

Tests["Raum-Stufen L1–L5 und Effizienz (Deckel 20)"] = function(services)
	local c = core(services)
	local data = newData(services)
	local env, account = fakeEnv({ Credits = 1e14 })
	buildFloors(services, data, env, 4)
	for level = 1, 4 do
		local before = account.Balance
		assert(c.LevelUp(data.Tower, env, 4))
		eq(before - account.Balance, TowerMath.LevelCost(4, level), "Raum-Stufe " .. level)
	end
	local ok, key = c.LevelUp(data.Tower, env, 4)
	eq(ok, false)
	eq(key, "tower.levelMax")
	for k = 0, 19 do
		local before = account.Balance
		assert(c.Efficiency(data.Tower, env))
		eq(before - account.Balance, 10000 * 3 ^ k, "Effizienz-Stufe " .. (k + 1))
	end
	ok, key = c.Efficiency(data.Tower, env)
	eq(key, "tower.effMax", "Deckel 20")
	eq(data.Tower.Eff, 20)
	-- Vorstand "Bau" 8: −40 %
	local data2 = newData(services)
	local env2, account2 = fakeEnv({ Credits = 1e6, Perks = { Build = 8 } })
	assert(c.Efficiency(data2.Tower, env2))
	eq(1e6 - account2.Balance, 6000, "10.000 × 0,6")
end

-- ---------------------------------------------------------------------
-- 4) Multiplikatoren & Einkommen (Abnahme 3/4)
-- ---------------------------------------------------------------------
Tests["Einkommen: x2 allein ×2, x3 allein ×3, beide ×4"] = function(services)
	local c = core(services)
	local base = 1234.5
	for _, case in ipairs({ { 1, 1 }, { 2, 2 }, { 3, 3 }, { 4, 4 } }) do
		local f = newFactors(services)
		f.Pass = case[1]
		local total, steady = TowerMath.Multiplier(c.BuildParts(f, true, true))
		eq(total, case[2], "Pass-Faktor " .. case[1])
		near(base * total, base * case[2], 1e-9, "Einkommen")
		eq(steady, case[2])
	end
	-- beide Pässe: EINE ehrliche Zeile ×4 in der Aufschlüsselung (nie ×2 und ×3 nebeneinander)
	local f = newFactors(services)
	f.Pass = 4
	local passParts = {}
	for _, part in ipairs(c.BuildParts(f, true, true)) do
		if part.Group == "Pass" then
			table.insert(passParts, part)
		end
	end
	eq(#passParts, 1, "eine Pass-Zeile")
	eq(passParts[1].Key, "Passes")
	eq(passParts[1].Value, 4)
end

Tests["Multiplikator-Deckel ×10, Event ≤ ×3, Perm additiv"] = function(services)
	local c = core(services)
	local f = newFactors(services)
	f.Eff = 20
	f.Ipo = 25
	f.Growth = 10
	f.Album = 9
	f.Friends = 7
	f.Respekt = 30
	f.Marketing = 5
	f.Penthouse = true
	local g = TowerMath.Groups(c.BuildParts(f, true, true))
	near(g.Perm, 9.97, 1e-9, "Perm-Maximum 9,97 (alle Deckel)")
	f.Boost = { Key = "X5", Value = 5, Until = 0, Source = "Bought" }
	f.Server = { Key = "Parade", Value = 1.5, Until = 0 }
	f.Event = { Value = 3, Until = nil }
	local total, steady = TowerMath.Multiplier(c.BuildParts(f, true, true))
	near(total, steady * 10, 1e-9, "Zeitlich gedeckelt auf ×10")
	f.Boost = nil
	f.Server = nil
	f.Event = { Value = 9, Until = nil }
	total, steady = TowerMath.Multiplier(c.BuildParts(f, true, true))
	near(total, steady * 3, 1e-9, "Event nie über ×3")
	local parts = c.BuildParts(f, true, false)
	for _, part in ipairs(parts) do
		truthy(part.Group ~= "Timed", "ohne Zeitlich keine Timed-Teile")
	end
end

Tests["Offline: 3 h exakt Steady × Rate × 3 h, ohne Sozial/Zeitlich, Deckel"] = function(services)
	local c = core(services)
	local data = newData(services)
	local env = fakeEnv({ Credits = 1e12, Licence = 10 })
	buildFloors(services, data, env, 12)
	local base = TowerMath.BaseIncome(data.Tower.Floors, nil)
	local f = newFactors(services)
	f.Eff = 3
	f.Friends = 4
	f.Respekt = 10
	f.Pass = 2
	f.Boost = { Key = "X2", Value = 2, Until = 0, Source = "Bought" }
	local _, offlineMult = TowerMath.Multiplier(c.BuildParts(f, false, false))
	near(offlineMult, 1.3 * 2, 1e-9, "Offline: ohne Freunde/Respekt/Boost")
	local steady = base * offlineMult
	local rate = TowerMath.OfflineRate(0, false)
	local cap = TowerMath.OfflineCap(0, 0, false, false)
	eq(TowerMath.Offline(steady, 3 * 3600, rate, cap), math.floor(steady * 0.5 * 10800), "3 h exakt")
	eq(TowerMath.Offline(steady, 30 * 3600, rate, cap), math.floor(steady * 0.5 * 8 * 3600), "Deckel 8 h")
	eq(TowerMath.Offline(steady, 30, rate, cap), math.floor(steady * 0.5 * 30), "Formel (MinAway prüft der Dienst)")
end

-- ---------------------------------------------------------------------
-- 5) Börsengang-Reset (§B9.6) & Transfer (§B8.2)
-- ---------------------------------------------------------------------
Tests["Börsengang-Reset behält Depot, Lizenz, Lager"] = function(services)
	local c = core(services)
	local data = newData(services)
	data.Prog.Licence = 6
	local dep = data.Depot -- Kopie aus DefaultData (Attrappe), nie ein echter Spielstand
	dep.Cash = 123456789
	dep.Basis = 100000000
	dep.Pos["7"] = { Q = 10, C = 50000, R = 0 }
	data.Garage.Cars.Streak = true
	data.Life.Watches.Chrono = true
	local env, account = fakeEnv({ Credits = 1e13, Licence = 6, Storage = { plant = 3, lamp = 1 } })
	buildFloors(services, data, env, 25)
	assert(c.SetDecor(data.Tower, env, 2, 1, "plant"))
	assert(c.SetDecor(data.Tower, env, 2, 2, "plant"))
	assert(c.SetDecor(data.Tower, env, 20, 3, "lamp"))
	assert(c.Efficiency(data.Tower, env))
	data.Tower.Vault = 999
	data.Tower.Janitor = true
	data.Tower.Instant = 2
	table.insert(data.Tower.Express, 600)
	data.Tower.Skin = "Obsidian"
	data.Tower.PendingCredits = 777
	local depotBefore = Util.DeepCopy(data.Depot)
	local progBefore = Util.DeepCopy(data.Prog)
	local garageBefore = Util.DeepCopy(data.Garage)
	local lifeBefore = Util.DeepCopy(data.Life)
	eq(account.Storage.plant, 1, "2 Pflanzen stehen")
	local ok = c.ResetForIpo(data, env, { Blitzstart = 2 })
	eq(ok, true)
	local same, where = deepEqual(depotBefore, data.Depot, "Depot")
	truthy(same, "Depot unverändert (" .. tostring(where) .. ")")
	same, where = deepEqual(progBefore, data.Prog, "Prog")
	truthy(same, "Prog/Lizenz unverändert (" .. tostring(where) .. ")")
	truthy(deepEqual(garageBefore, data.Garage, "Garage"), "Autos bleiben")
	truthy(deepEqual(lifeBefore, data.Life, "Life"), "Uhren bleiben")
	eq(account.Balance, 0, "CR neu (Start-CR 0)")
	eq(#data.Tower.Floors, 8, "Blitzstart 2 = 8 Etagen")
	eq(data.Tower.Eff, 0, "Effizienz neu")
	eq(data.Tower.Vault, 0, "Tresor neu")
	eq(data.Tower.RunSpend, 0, "Lauf-Ausgaben neu")
	eq(data.Tower.PendingCredits, 0, "vorgemerkte CR gehören zum alten Lauf")
	eq(data.Tower.Build.Floor, nil, "keine Baustelle")
	eq(data.Tower.Janitor, true, "Lobby-Bot bleibt")
	eq(data.Tower.Instant, 2, "Token bleiben")
	eq(#data.Tower.Express, 1, "Express bleibt")
	eq(data.Tower.Skin, "Obsidian", "Fassade bleibt")
	-- Lager: alles zurück, "Layout merken" stellt Etage 2 wieder auf, Etage 20 bleibt im Lager
	eq(data.Tower.Floors[2].D[1], "plant", "Layout gemerkt (Etage 2)")
	eq(data.Tower.Floors[2].D[2], "plant")
	eq(account.Storage.plant, 1, "Pflanzen: 3 − 2 wieder aufgestellt")
	eq(account.Storage.lamp, 1, "Lampe zurück im Lager")
	truthy(type(data.Tower.Layouts["20"]) == "table", "Layout Etage 20 gemerkt")
	-- CR nicht abbuchbar -> nichts ändert sich
	local data2 = newData(services)
	local env2 = fakeEnv({ Credits = 1e9 })
	buildFloors(services, data2, env2, 5)
	local env3 = fakeEnv({ Credits = 500, FailDebit = true })
	eq(c.ResetForIpo(data2, env3, {}), false, "Abbuchung scheitert")
	eq(#data2.Tower.Floors, 5, "Turm unverändert")
end

Tests["Transfer-Fluss nur AKY -> CR (Bau-Kurs der Lizenz)"] = function(services)
	local c = core(services)
	eq(c.ConvertTransfer(37500, 40), 15000, "375 AKY × 40 = 15.000 CR (Tutorial)")
	eq(c.ConvertTransfer(1240 * 100, 40), 49600, "Beispiel §B8.2")
	eq(c.ConvertTransfer(12345, 1500), math.floor(12345 * 1500 / 100))
	eq(c.ConvertTransfer(0, 40), 0)
	eq(c.ConvertTransfer(-5, 40), 0)
	eq(c.ConvertTransfer(0 / 0, 40), 0)
	eq(c.ConvertTransfer(6e9 * 0.06, 40000), 1.44e11, "höchster Transfer je Börsentag (Legende) = 1,44e11 CR")
	eq(c.ConvertTransfer(1e15, 40000), 9e15, "geklemmt auf 9e15")
	-- Fluss mit Attrappen: Depot verliert nur über withdraw, CR kommen nur über credit
	local wallet = { Cash = 50000, Withdrawn = 0 } -- Depot-Attrappe
	local credited, pending = 0, 0
	local cents, amount, why = c.Transfer(
		function(): (any, any)
			wallet.Cash -= 1240
			wallet.Withdrawn += 1240
			return 1240, nil
		end,
		200,
		function(value: number): boolean
			credited += value
			return true
		end,
		function(value: number)
			pending += value
		end
	)
	eq(cents, 1240)
	eq(amount, 2480, "12,40 AKY × 200")
	eq(why, nil)
	eq(credited, 2480)
	eq(pending, 0)
	eq(wallet.Cash, 48760, "AKY verlassen das Depot nur über Withdraw")
	-- Gutschrift scheitert -> vorgemerkt, nie zurück ins Depot
	cents, amount = c.Transfer(
		function(): (any, any)
			return 500, nil
		end,
		40,
		function(): boolean
			return false
		end,
		function(value: number)
			pending += value
		end
	)
	eq(pending, 200, "vorgemerkt")
	eq(wallet.Cash, 48760, "Depot unberührt")
	-- nichts abhebbar -> Grund durchreichen, keine CR
	cents, amount, why = c.Transfer(
		function(): (any, any)
			return 0, "trade.transferUsed"
		end,
		40,
		function(): boolean
			error("darf nicht gutschreiben")
		end,
		function()
			error("darf nichts vormerken")
		end
	)
	eq(cents, 0)
	eq(amount, 0)
	eq(why, "trade.transferUsed")
end

-- ---------------------------------------------------------------------
-- 6) Bau-Hilfe, Express, Reparatur, Deko, Privat, Auto-Plan, Live-Felder
-- ---------------------------------------------------------------------
Tests["Bau-Hilfe −10 %, max. 3, je Helfer 1×, Untergrenze"] = function(services)
	local c = core(services)
	local data = newData(services)
	local env = fakeEnv({ Credits = 1e13, Licence = 10 })
	c.SetFloors(data.Tower, env, 29)
	assert(c.StartBuild(data.Tower, env))
	local build = data.Tower.Build
	eq(build.Until - build.Start, 5400, "Etage 30: 90 min")
	assert(c.ApplyHelp(data.Tower, env, 101))
	near(build.Until - env.Now, 4860, 1e-6, "−10 % der Restzeit")
	local ok, key = c.ApplyHelp(data.Tower, env, 101)
	eq(key, "tower.helpAgain")
	assert(c.ApplyHelp(data.Tower, env, 102))
	assert(c.ApplyHelp(data.Tower, env, 103))
	ok, key = c.ApplyHelp(data.Tower, env, 104)
	eq(ok, false)
	eq(key, "tower.helpFull", "höchstens 3 Helfer")
	-- Untergrenze 25 % der Grundzeit
	local data2 = newData(services)
	local env2 = fakeEnv({ Credits = 1e13, Licence = 10, Passes = { BuildCrew = true }, Perks = { Tempo = 5 } })
	c.SetFloors(data2.Tower, env2, 29)
	assert(c.StartBuild(data2.Tower, env2))
	assert(c.ApplyHelp(data2.Tower, env2, 1))
	eq(data2.Tower.Build.Until - data2.Tower.Build.Start, 1350, "nie unter 25 % der Grundzeit")
end

Tests["Bau-Express kürzt bzw. beendet die Baustelle"] = function(services)
	local c = core(services)
	local data = newData(services)
	local env = fakeEnv({ Credits = 1e13, Licence = 10 })
	eq(c.ApplyExpress(data.Tower, env, 600), false, "ohne Baustelle -> Token (Dienst)")
	c.SetFloors(data.Tower, env, 29)
	assert(c.StartBuild(data.Tower, env))
	assert(c.ApplyExpress(data.Tower, env, 600))
	eq(data.Tower.Build.Until - env.Now, 4800, "−10 min")
	assert(c.ApplyExpress(data.Tower, env, 10800))
	eq(data.Tower.Build.Until, env.Now, "Rest ≤ 3 h -> fertig")
end

Tests["Reparatur kaputter Turm-Daten"] = function(services)
	local c = core(services)
	local data = serviceModule(services, "DataService").DefaultData()
	data.Tower.Floors = {
		{ R = "Penthouse", L = 9, S = { "Quant", "Janitor", "Nope", "Intern", "Senior", "Analyst" }, D = { 5, "a" } },
		"kaputt",
		{ R = "Desk", L = 0 / 0, S = "x", D = { "a", "b", "c", "d", "e" } },
	}
	data.Tower.Build = { Floor = 9, Until = 5, Start = 1, Cost = 777 }
	data.Tower.Eff = 99
	data.Tower.Vault = -5
	data.Tower.Skin = "Unbekannt"
	data.Tower.Private = { 1, 1, 7, 2.5 }
	data.Tower.Express = { 600, -1, "x" }
	data.Tower.Name = { A = 999, N = 0 }
	data.Boosts.X2 = 0 / 0
	local refund = c.Repair(data)
	local t = data.Tower
	eq(refund, 777, "ungültige Baustelle wird erstattet")
	eq(t.Build.Floor, nil)
	eq(#t.Floors, 3)
	eq(t.Floors[1].R, Config.Tower.DefaultRoom, "Penthouse nicht oben -> Büro")
	eq(t.Floors[1].L, 5)
	eq(#t.Floors[1].S, 3, "höchstens 3 gültige Personal-Einträge")
	eq(t.Floors[1].D[1], "", "ungültige Deko -> leerer Platz")
	eq(t.Floors[1].D[2], "a")
	eq(t.Floors[2].R, Config.Tower.DefaultRoom, "kaputte Etage -> neue Etage")
	eq(t.Floors[3].L, 1)
	eq(#t.Floors[3].D, 3, "überzählige Deko …")
	eq(data.Storage.Decor.d, 1, "… geht ins Lager")
	eq(t.Eff, Config.Tower.Efficiency.Max, "Effizienz geklemmt auf den Deckel")
	eq(t.Vault, 0)
	eq(t.Skin, Config.Tower.DefaultSkin)
	eq(#t.Private, 1, "nur gültige Privat-Etagen")
	eq(#t.Express, 1)
	eq(t.Name.A, 1)
	eq(t.Name.N, 1)
	eq(data.Boosts.X2, 0)
end

Tests["Deko: feste Plätze, Lager, Austausch"] = function(services)
	local c = core(services)
	local data = newData(services)
	local env, account = fakeEnv({ Credits = 1e9, Storage = { sofa = 1, desk = 1 } })
	buildFloors(services, data, env, 3)
	local ok, key = c.SetDecor(data.Tower, env, 2, 4, "sofa")
	eq(key, "core.invalid", "nur 3 Plätze je Etage")
	eq(c.SetDecor(data.Tower, env, 2, 3, "sofa"), true)
	eq(account.Storage.sofa, 0)
	eq(data.Tower.Floors[2].D[3], "sofa")
	eq(data.Tower.Floors[2].D[1], "", "Lücken als leere Plätze")
	ok, key = c.SetDecor(data.Tower, env, 2, 1, "sofa")
	eq(ok, false)
	eq(key, "tower.decorNone", "nichts im Lager")
	eq(c.SetDecor(data.Tower, env, 2, 3, "desk"), true, "austauschen")
	eq(account.Storage.sofa, 1, "altes Teil zurück ins Lager")
	eq(c.SetDecor(data.Tower, env, 2, 3, nil), true, "entfernen")
	eq(account.Storage.desk, 1)
	eq(#data.Tower.Floors[2].D, 0, "leere Plätze am Ende entfernt")
end

Tests["Privat-Etagen höchstens 5"] = function(services)
	local c = core(services)
	local data = newData(services)
	local env = fakeEnv({ Credits = 1e9 })
	buildFloors(services, data, env, 8)
	for floor = 1, 5 do
		eq(c.SetPrivate(data.Tower, floor, true), true)
	end
	local ok, key = c.SetPrivate(data.Tower, 6, true)
	eq(ok, false)
	eq(key, "tower.privateMax")
	eq(c.SetPrivate(data.Tower, 3, false), true)
	eq(c.SetPrivate(data.Tower, 6, true), true)
	ok, key = c.SetPrivate(data.Tower, 20, true)
	eq(key, "tower.noFloor")
end

Tests["Auto-Plan schlägt bessere Belegung vor (ändert nichts)"] = function(services)
	local c = core(services)
	local data = newData(services)
	local env = fakeEnv({ Credits = 1e12, Licence = 10 })
	buildFloors(services, data, env, 10)
	local plan, gain, cost = c.AutoPlan(data.Tower, c.Stage(data.Tower), 1, nil)
	eq(#plan, 10)
	truthy(gain > 0, "Gewinn > 0")
	truthy(cost > 0, "Wechsel kosten etwas")
	eq(data.Tower.Floors[1].R, Config.Tower.DefaultRoom, "Plan ändert den Tower nicht")
	local desks = 0
	for _, key in ipairs(plan) do
		if key == "Desk" then
			desks += 1
		end
	end
	truthy(desks >= 5, "Trading-Desk ist die beste Grundbelegung")
end

Tests["Config.Tower: Live-Felder und Pflicht-Schlüssel"] = function()
	local t = Config.Tower
	for _, key in ipairs({ "Bull", "Parade", "BellMoment", "EventMax", "TimedCap" }) do
		truthy(Util.IsFinite(t.Mult[key]), "Config.Tower.Mult." .. key)
	end
	truthy(t.Mult.EventMax <= 3, "Event ≤ ×3")
	truthy(t.Mult.TimedCap <= 10, "Zeitlich ≤ ×10")
	eq(#t.Stages, 12)
	eq(#t.Rooms, 11)
	eq(t.Efficiency.Max, 20)
	eq(t.CollectRange, 70)
	local errors = t.Validate(Config)
	truthy(#errors == 0, "Config.Tower.Validate: " .. table.concat(errors, " | "))
end

return Tests
