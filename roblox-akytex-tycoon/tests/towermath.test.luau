-- =====================================================================
--  AKYTEX TYCOON – Luau-CLI-Test für Shared/TowerMath (ohne Roblox)
--  Besitzer: WP6 (Turm-Ökonomie). DESIGN.md §D WP6 "Tests": Kosten-/Einkommens-/Bauzeit-Tabellen (== §B5.1 und
--  tools/economy_sim.py für alle 50 Etagen), Multiplikator-Gruppen (x2 ×2, x3 ×3, beide ×4, Zeitlich-Deckel ×10,
--  Event ≤ ×3), Offline-Klemmen (3 h exakt, Deckel), Sterne-Formel, Klemmung 9e15, Nachbar-Effekte, Config-Gleichstand.
--  Start (im Projektordner):  <scratchpad>/luau-build/luau tests/towermath.test.luau
-- =====================================================================

local TM = require("../src/shared/TowerMath")
local TowerConfig = require("../src/shared/Config/Tower")

local passed, failed = 0, 0
local failures: { string } = {}

local function check(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		table.insert(failures, name .. ": " .. tostring(err))
	end
end

local function eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(("%s erwartet %s, bekommen %s"):format(label or "Wert", tostring(expected), tostring(actual)), 2)
	end
end

local function near(actual: number, expected: number, tolerance: number, label: string?)
	if math.abs(actual - expected) > tolerance then
		error(("%s erwartet ≈%.12g, bekommen %.12g"):format(label or "Wert", expected, actual), 2)
	end
end

local NAN = 0 / 0
local HUGE = math.huge

-- Referenz aus tools/economy_sim.py (floor_cost / floor_income / build_time für n = 1 … 50)
-- stylua: ignore start
local COST = {0, 1000, 1500, 2250, 3375, 5062, 7594, 11391, 17086, 25629, 38443, 57665, 89957, 140334, 218920, 341516,
	532765, 831113, 1296537, 2022597, 3155251, 4922192, 7678620, 11978647, 18686689, 29524969, 46649452, 73706134,
	116455691, 183999992, 290719987, 459337580, 725753376, 1146690334, 1811770728, 2862597751, 4522904446, 7146189024,
	11290978658, 17839746280, 28543594049, 45669750478, 73071600764, 116914561223, 187063297957, 299301276731,
	478882042770, 766211268432, 1225938029491, 1961500847186}
local INCOME = {4.0, 5.2, 6.760000000000001, 8.788, 11.424400000000002, 14.851720000000002, 19.307236000000003,
	25.099406800000008, 32.62922884000001, 42.41799749200001, 55.14339673960002, 71.68641576148002, 93.19234048992404,
	121.15004263690125, 157.49505542797164, 204.74357205636312, 266.16664367327206, 346.01663677525374,
	449.8216278078298, 584.7681161501788, 760.1985509952325, 988.2581162938022, 1284.735551181943, 1670.156216536526,
	2171.2030814974837, 2822.564005946729, 3669.3332077307477, 4770.133170049972, 6201.173121064964, 8061.525057384454,
	10479.982574599791, 13623.977346979727, 17711.170551073646, 23024.521716395742, 29931.878231314466,
	38911.441700708805, 50584.87421092145, 65760.33647419789, 85488.43741645725, 111134.96864139444,
	144475.45923381278, 187818.09700395662, 244163.5261051436, 317412.5839366867, 412636.35911769274,
	536427.2668530006, 697355.4469089007, 906562.080981571, 1178530.7052760425, 1532089.9168588552}
local BUILD = {3.0, 3.0, 3.0, 3.0, 3.0, 3.0, 3.0, 3.0, 3.0, 20.0, 26.6, 35.378, 47.052740000000014, 62.580144200000014,
	83.23159178600002, 110.69801707538004, 147.22836271025545, 195.81372240463978, 260.4322507981709, 346.3748935615673,
	460.6786084368846, 612.7025492210565, 814.8943904640053, 1083.809539317127, 1441.466687291779, 1917.150694098066,
	2549.810423150428, 3391.2478627900696, 4510.359657510792, 5400.0, 5400.0, 5400.0, 5400.0, 5400.0, 5400.0, 5400.0,
	5400.0, 5400.0, 5400.0, 5400.0, 5400.0, 5400.0, 5400.0, 5400.0, 5400.0, 5400.0, 5400.0, 5400.0, 5400.0, 5400.0}
-- stylua: ignore end

local function floorData(room: string, level: number?, staff: { string }?, decor: { string }?): TM.FloorData
	return { R = room, L = level or 1, S = staff or {}, D = decor or {} }
end

local function part(key: string, value: number, group: string, source: string?): TM.MultPart
	return { Key = key, Value = value, Group = group, Source = source or "Earned" }
end

-- ---------------------------------------------------------------------
-- 1) Tabellen §B5.1 (Abnahme 1: alle 50 Etagen)
-- ---------------------------------------------------------------------
local function checkTables(label: string)
	for n = 1, 50 do
		eq(TM.FloorCost(n), COST[n], label .. " Kosten Etage " .. n)
		near(TM.FloorIncome(n), INCOME[n], INCOME[n] * 1e-12, label .. " Einkommen Etage " .. n)
		near(TM.BuildTime(n), BUILD[n], BUILD[n] * 1e-12, label .. " Bauzeit Etage " .. n)
	end
end

check("Tabellen == economy_sim.py für alle 50 Etagen", function()
	checkTables("Startwerte")
end)

check("Tabelle §B5.1: Stichproben und Summe 5,23e12", function()
	eq(TM.FloorCost(1), 0, "Etage 1 gratis")
	eq(TM.FloorCost(2), 1000)
	eq(TM.FloorCost(4), 2250)
	eq(TM.FloorCost(7), 7594)
	eq(TM.FloorCost(10), 25629)
	eq(TM.FloorCost(13), 89957)
	eq(TM.FloorCost(18), 831113)
	eq(TM.FloorCost(22), 4922192)
	eq(TM.FloorCost(25), 18686689)
	eq(TM.FloorCost(30), 183999992)
	eq(TM.FloorCost(37), 4522904446)
	eq(TM.FloorCost(44), 116914561223)
	eq(TM.FloorCost(50), 1961500847186)
	local sum = 0
	for n = 1, 50 do
		sum += TM.FloorCost(n)
	end
	eq(sum, 5231695359616, "Summe aller 50 Etagen")
	eq(math.floor(TM.FloorIncome(25) + 0.5), 2171, "Basis Etage 25")
	eq(math.floor(TM.FloorIncome(50) + 0.5), 1532090, "Basis Etage 50")
	near(TM.FloorIncome(13), 93.2, 0.01, "Basis Etage 13")
	eq(math.floor(TM.BuildTime(15) + 0.5), 83, "Etage 15 ≈ 83 s")
	near(TM.BuildTime(20) / 60, 5.77, 0.01, "Etage 20 ≈ 5,8 min")
	near(TM.BuildTime(25) / 60, 24.0, 0.05, "Etage 25 ≈ 24 min")
	eq(TM.BuildTime(30), 5400, "ab 30: 90 min")
	eq(TM.BuildTime(9), 3, "Etagen 1–9: 3 s")
end)

check("ungültige Etagen -> 0", function()
	for _, n in ipairs({ 0, -1, 51, 2.5, NAN, HUGE, -HUGE }) do
		eq(TM.FloorCost(n), 0, "Kosten " .. tostring(n))
		eq(TM.FloorIncome(n), 0, "Einkommen " .. tostring(n))
		eq(TM.BuildTime(n), 0, "Bauzeit " .. tostring(n))
	end
end)

-- ---------------------------------------------------------------------
-- 2) Raum-Stufen, Personal, Effizienz, Wechsel, Rabatt
-- ---------------------------------------------------------------------
check("LevelCost ×1/×2,5/×6/×15 von max(C(n), 500)", function()
	eq(TM.LevelCost(1, 1), 500, "Etage 1: Mindestbasis 500")
	eq(TM.LevelCost(1, 2), 1250)
	eq(TM.LevelCost(1, 3), 3000)
	eq(TM.LevelCost(1, 4), 7500)
	eq(TM.LevelCost(1, 5), 0, "L5 ist die höchste Stufe")
	eq(TM.LevelCost(10, 2), 64072, "25629 × 2,5 = 64072,5 -> 64072 (halb zur geraden Zahl)")
	eq(TM.LevelCost(50, 4), 1961500847186 * 15, "teuerste Raum-Stufe 2,94e13")
	eq(TM.LevelCost(0, 1), 0)
	eq(TM.LevelCost(5, 0), 0)
	eq(TM.LevelCost(5, NAN), 0)
end)

check("StaffCost ×1/×3/×9/×25, Hausmeister 0, Sicherheit 50.000", function()
	eq(TM.StaffCost(2, "Intern"), 1000)
	eq(TM.StaffCost(1, "Intern"), 500, "Mindestbasis 500")
	eq(TM.StaffCost(10, "Analyst"), 25629 * 3)
	eq(TM.StaffCost(20, "Senior"), 2022597 * 9)
	eq(TM.StaffCost(50, "Quant"), 1961500847186 * 25, "teuerster Einzelpreis 4,9e13")
	assert(TM.StaffCost(50, "Quant") < 1e14, "G1: < 1e14")
	eq(TM.StaffCost(30, "Janitor"), 0)
	eq(TM.StaffCost(0, "Security"), 50000)
	eq(TM.StaffCost(5, "Unbekannt"), 0)
	eq(TM.StaffCost(51, "Intern"), 0)
end)

check("EfficiencyCost 10.000 × 3^k (k = 0 … 19)", function()
	eq(TM.EfficiencyCost(0), 10000)
	eq(TM.EfficiencyCost(1), 30000)
	eq(TM.EfficiencyCost(19), 11622614670000, "Stufe 20 kostet 1,16e13")
	eq(TM.EfficiencyCost(20), 0, "Deckel 20")
	eq(TM.EfficiencyCost(-1), 0)
	eq(TM.EfficiencyCost(1.5), 0)
	eq(TM.EfficiencyCost(NAN), 0)
end)

check("Abteilungs-Wechsel 25 % der Etagenkosten, Rabatt-Rundung", function()
	eq(TM.RoomChangeCost(1), 0, "Etage 1 gratis")
	eq(TM.RoomChangeCost(2), 250)
	eq(TM.RoomChangeCost(10), 6407, "25629 × 0,25 = 6407,25")
	eq(TM.Discount(1000, 0.75), 750)
	eq(TM.Discount(5, 0.5), 2, "2,5 -> 2 (halb zur geraden Zahl)")
	eq(TM.Discount(1000, 0.6 * 0.5), 300)
	eq(TM.Discount(1, 0.1), 1, "nie gratis, wenn etwas kostet")
	eq(TM.Discount(0, 0.5), 0)
	eq(TM.Discount(1000, NAN), 1000, "kaputter Rabatt -> voller Preis")
	eq(TM.Discount(1000, 2), 1000, "Rabatt > 1 -> geklemmt")
end)

-- ---------------------------------------------------------------------
-- 3) Stufen & Tore (§B4.2)
-- ---------------------------------------------------------------------
check("StageOf: 12 Stufen, 0 Etagen = Stufe 1", function()
	local expect = { [0] = 1, [1] = 1, [2] = 2, [3] = 2, [4] = 3, [6] = 3, [7] = 4, [9] = 4, [10] = 5, [13] = 5 }
	for floors, stage in pairs(expect) do
		eq(TM.StageOf(floors), stage, "Etagen " .. floors)
	end
	eq(TM.StageOf(14), 6)
	eq(TM.StageOf(18), 7)
	eq(TM.StageOf(22), 8)
	eq(TM.StageOf(25), 8)
	eq(TM.StageOf(26), 9)
	eq(TM.StageOf(31), 10)
	eq(TM.StageOf(37), 11)
	eq(TM.StageOf(43), 11)
	eq(TM.StageOf(44), 12)
	eq(TM.StageOf(50), 12)
	eq(TM.StageOf(NAN), 1)
	local first, last = TM.StageRange(12)
	eq(first, 44)
	eq(last, 50)
	first, last = TM.StageRange(5)
	eq(first, 10)
	eq(last, 13)
end)

check("GateFor: Lizenz-Tore + Börsengang", function()
	local lic, ipo = TM.GateFor(9)
	eq(lic, 1, "Etage 9 frei")
	eq(ipo, 0)
	lic = TM.GateFor(10)
	eq(lic, 2, "Etage 10 = Azubi II")
	lic = TM.GateFor(14)
	eq(lic, 3, "Etage 14 = Azubi III")
	lic = TM.GateFor(18)
	eq(lic, 4, "Etage 18 = Trader I")
	lic = TM.GateFor(26)
	eq(lic, 5, "Etage 26 = Trader II")
	lic = TM.GateFor(31)
	eq(lic, 6, "Etage 31 = Trader III")
	lic, ipo = TM.GateFor(37)
	eq(lic, 7, "Etage 37 = Fondsmanager I")
	eq(ipo, 0)
	lic, ipo = TM.GateFor(44)
	eq(lic, 7, "Orbit-Spire: Fondsmanager I")
	eq(ipo, 1, "… und ≥ 1 Börsengang")
end)

-- ---------------------------------------------------------------------
-- 4) Einkommen & Nachbar-Effekte (§B4.3/§B4.4/§B5.2)
-- ---------------------------------------------------------------------
check("BaseIncome: Gehalt, Raum, Stufe, Personal", function()
	eq(TM.BaseIncome({}), 3, "nur Gehalt")
	near(TM.BaseIncome({ floorData("Office") }), 7, 1e-9, "3 + 4")
	near(TM.BaseIncome({ floorData("Desk") }), 3 + 5, 1e-9, "Desk ×1,25")
	near(TM.BaseIncome({ floorData("Desk", 3) }), 3 + 4 * 1.25 * 1.5, 1e-9, "L3 ×1,5")
	near(TM.BaseIncome({ floorData("Office", 1, { "Intern", "Analyst" }) }), 3 + 4 * 1.35, 1e-9, "+10 % +25 %")
	near(TM.BaseIncome({ floorData("Office", 1, { "Quant", "Quant", "Quant", "Quant" }) }), 3 + 4 * 4, 1e-9, "max. 3")
	near(TM.BaseIncome({ floorData("Penthouse", 5, { "Quant" }) }), 3, 1e-9, "Penthouse ×0")
	near(TM.BaseIncome({ floorData("Unbekannt") }), 7, 1e-9, "unbekannter Raum zählt wie Büro")
end)

check("Nachbar-Effekte: Café ±2, Server ×1,10 (max. 3), Labor ×1,15", function()
	local i2 = TM.FloorIncome(2)
	local i3 = TM.FloorIncome(3)
	-- Café auf Etage 1 wirkt auf Personal der Etage 3 (Abstand 2), nicht auf Etage 4 (Abstand 3)
	local floors = { floorData("Cafe"), floorData("Office"), floorData("Office", 1, { "Senior" }) }
	near(TM.FloorIncomeAt(floors, 3, nil), i3 * (1 + 0.5 * 1.2), 1e-9, "Café ±2")
	floors[4] = floorData("Office", 1, { "Senior" })
	near(TM.FloorIncomeAt(floors, 4, nil), TM.FloorIncome(4) * 1.5, 1e-9, "Café wirkt nicht über 2 Etagen")
	-- zwei Cafés stapeln nicht
	local twoCafe = { floorData("Cafe"), floorData("Office", 1, { "Senior" }), floorData("Cafe") }
	near(TM.FloorIncomeAt(twoCafe, 2, nil), i2 * 1.6, 1e-9, "stärkstes Café zählt einmal")
	-- Server-Räume: alle Personal-Boni ×1,1 je Raum, höchstens 3
	local servers = { floorData("Office", 1, { "Quant" }) }
	for _ = 1, 4 do
		table.insert(servers, floorData("Server"))
	end
	near(TM.FloorIncomeAt(servers, 1, nil), 4 * (1 + 1.0 * 1.1 ^ 3), 1e-9, "Server-Deckel 3")
	-- Labor: Etagen direkt darüber/darunter ×1,15 (je Labor)
	local lab = { floorData("Lab"), floorData("Office"), floorData("Lab"), floorData("Office") }
	near(TM.FloorIncomeAt(lab, 2, nil), i2 * 1.15 * 1.15, 1e-9, "zwischen zwei Laboren")
	near(TM.FloorIncomeAt(lab, 4, nil), TM.FloorIncome(4) * 1.15, 1e-9, "unter einem Labor")
	near(TM.FloorIncomeAt(lab, 1, nil), 4 * 0.8, 1e-9, "Labor selbst ×0,8")
	eq(TM.FloorIncomeAt(lab, 9, nil), 0, "Etage außerhalb")
end)

check("Komfort: +0,5 % je Punkt, max. +10 % je Etage", function()
	local ctx = {
		Comfort = function(key: string): number
			return if key == "big" then 5 elseif key == "bad" then 0 / 0 else 2
		end,
	}
	near(TM.BaseIncome({ floorData("Office", 1, {}, { "big", "big" }) }, ctx), 3 + 4 * 1.05, 1e-9, "10 Punkte")
	near(TM.BaseIncome({ floorData("Office", 1, {}, { "big", "big", "big", "big", "big" }) }, ctx), 3 + 4 * 1.10, 1e-9)
	near(TM.BaseIncome({ floorData("Office", 1, {}, { "", "bad", "x" }) }, ctx), 3 + 4 * 1.01, 1e-9, "leer/NaN = 0")
end)

-- ---------------------------------------------------------------------
-- 5) Multiplikator-Gruppen (Abnahme 3 + 4)
-- ---------------------------------------------------------------------
check("Pässe: x2 allein ×2, x3 allein ×3, beide ×4", function()
	eq(TM.PassFactor(false, false), 1)
	eq(TM.PassFactor(true, false), 2)
	eq(TM.PassFactor(false, true), 3)
	eq(TM.PassFactor(true, true), 4)
	local total = TM.Multiplier({ part("Income2x", 2, "Pass", "Bought") })
	eq(total, 2, "nur x2")
	total = TM.Multiplier({ part("Income3x", 3, "Pass", "Bought") })
	eq(total, 3, "nur x3")
	total = TM.Multiplier({ part("Income2x", 2, "Pass", "Bought"), part("Income3x", 3, "Pass", "Bought") })
	eq(total, 4, "zusammen x4")
end)

check("Perm additiv, Trader/Fixed multiplikativ, Steady ohne Zeitlich", function()
	local parts = {
		part("Efficiency", 2.0, "Perm"),
		part("Ipo", 0.5, "Perm"),
		part("Licence", 1.12, "Trader", "Skill"),
		part("Ruf", 1.3, "Trader", "Skill"),
		part("Vip", 1.1, "Fixed", "Bought"),
		part("X2", 2, "Timed", "Bought"),
	}
	local total, steady = TM.Multiplier(parts)
	near(steady, 3.5 * 1.12 * 1.3 * 1.1, 1e-9, "Steady")
	near(total, steady * 2, 1e-9, "mit Zeitlich")
	local g = TM.Groups(parts)
	near(g.Perm, 3.5, 1e-12)
	near(g.Trader, 1.456, 1e-12)
	eq(g.Timed, 2)
	local maxPerm = 1 + 2.0 + 5.0 + 1.0 + 0.12 + 0.4 + 0.2 + 0.15 + 0.10
	near(maxPerm, 9.97, 1e-9, "Perm-Maximum laut §B5.2")
end)

check("Zeitlich-Deckel ×10, Event ≤ ×3, Werte geklemmt", function()
	local total, steady = TM.Multiplier({
		part("X5", 5, "Timed", "Bought"),
		part("Parade", 1.5, "Timed", "Event"),
		part("Event", 3, "Timed", "Event"),
	})
	eq(steady, 1)
	eq(total, 10, "5 × 1,5 × 3 = 22,5 -> Deckel 10")
	total = TM.Multiplier({ part("Event", 5, "Timed", "Event") })
	eq(total, 3, "Event nie über ×3")
	total = TM.Multiplier({ part("GoldenHour", 9, "Timed", "Event"), part("X2", 2, "Timed", "Bought") })
	eq(total, 6, "Golden Hour ×3 × Boost ×2")
	total = TM.Multiplier({ part("Kaputt", NAN, "Timed"), part("Weniger", 0.2, "Timed"), part("Neg", -3, "Perm") })
	eq(total, 1, "NaN/kleiner 1/negativ wirkungslos")
	total = TM.Multiplier({})
	eq(total, 1)
end)

-- ---------------------------------------------------------------------
-- 6) Offline (Abnahme 5) & Tresor
-- ---------------------------------------------------------------------
check("Offline: 3 h exakt Steady × Rate × 3 h, Deckel geklemmt", function()
	eq(TM.Offline(1000, 3 * 3600, 0.5, 8 * 3600), 1000 * 0.5 * 10800, "3 h")
	eq(TM.Offline(1234.5, 3 * 3600, 0.65, 24 * 3600), math.floor(1234.5 * 0.65 * 10800), "abgerundet")
	eq(TM.Offline(1000, 30 * 3600, 0.5, 8 * 3600), 1000 * 0.5 * 8 * 3600, "über Deckel -> 8 h")
	eq(TM.Offline(1000, -50, 0.5, 8 * 3600), 0, "negative Zeit")
	eq(TM.Offline(NAN, 100, 0.5, 100), 0)
	eq(TM.Offline(1000, HUGE, 0.5, 100), 0, "unendliche Zeit ist kein Wert")
	eq(TM.Offline(1e15, 86400, 0.9, 86400), 9e15, "Klemmung 9e15")
end)

check("Offline-Rate und -Deckel (§B4.6)", function()
	near(TM.OfflineRate(0, false), 0.5, 1e-12)
	near(TM.OfflineRate(8, false), 0.9, 1e-12, "+40 Pp")
	near(TM.OfflineRate(0, true), 0.65, 1e-12, "Pass +15 Pp")
	near(TM.OfflineRate(8, true), 0.9, 1e-12, "Obergrenze 90 %")
	near(TM.OfflineRate(99, false), 0.9, 1e-12, "Perk geklemmt")
	eq(TM.OfflineCap(0, 0, false, false), 8 * 3600)
	eq(TM.OfflineCap(3, 2, false, false), 13 * 3600, "8 + 3 + 2")
	eq(TM.OfflineCap(0, 9, false, false), 12 * 3600, "Lounges max. 4")
	eq(TM.OfflineCap(0, 0, true, false), 12 * 3600, "Club +4 h")
	eq(TM.OfflineCap(0, 0, false, true), 24 * 3600, "Pass mindestens 24 h")
	eq(TM.OfflineCap(8, 4, true, true), 24 * 3600, "Obergrenze 24 h")
end)

check("Tresor-Kapazität 20 min (+50 % je Tresor-Etage, max. 2)", function()
	eq(TM.VaultCap(3, 0), 3600)
	eq(TM.VaultCap(3, 1), 5400)
	eq(TM.VaultCap(3, 2), 7200)
	eq(TM.VaultCap(3, 5), 7200, "max. 2 Tresor-Etagen")
	eq(TM.VaultCap(0, 2), 0)
	eq(TM.VaultCap(NAN, 1), 0)
end)

check("BuildSeconds: Beschleuniger nie unter 25 % der Grundzeit", function()
	eq(TM.BuildSeconds(30, 0.5 * 0.5), 1350, "Crew + Tempo 5")
	eq(TM.BuildSeconds(30, 0.1), 1350, "Admin −90 % -> Untergrenze")
	eq(TM.BuildSeconds(30, 1), 5400)
	eq(TM.BuildSeconds(30, nil), 5400)
	eq(TM.BuildSeconds(5, 0.25), 3, "Szene bleibt 3 s")
	eq(TM.BuildSeconds(0, 0.5), 0)
end)

-- ---------------------------------------------------------------------
-- 7) Sterne & Klemmung
-- ---------------------------------------------------------------------
check("Sterne-Formel floor(4 · log10(x / 1e6))", function()
	eq(TM.Stars(9999999), 0, "unter 1e7")
	eq(TM.Stars(1e7), 4)
	eq(TM.Stars(1e9), 12, "Lauf 1 ≈ 1e9 -> 12 ★")
	eq(TM.Stars(1e13), 28, "Lauf 2 ≈ 1e13 -> 28 ★")
	eq(TM.Stars(3.17e9), 14, "log10(3170) = 3,501")
	eq(TM.Stars(3.16e9), 13, "knapp darunter")
	eq(TM.Stars(NAN), 0)
	eq(TM.Stars(-5), 0)
end)

check("Clamp: ganzzahlig 0 … 9e15", function()
	eq(TM.Clamp(NAN), 0)
	eq(TM.Clamp(-5), 0)
	eq(TM.Clamp(1.7), 1)
	eq(TM.Clamp(1e16), 9e15)
	eq(TM.Clamp(HUGE), 9e15)
	eq(TM.Clamp(-HUGE), 0)
	eq(TM.Clamp(8999999999999999), 8999999999999999, "knapp unter dem Deckel bleibt")
	eq(TM.Clamp(9e15 + 2), 9e15)
	eq(TM.MAX_MONEY, 9e15)
	assert(TM.MAX_MONEY < 2 ^ 53, "unter 2^53")
end)

-- ---------------------------------------------------------------------
-- 8) Gleichstand mit Config/Tower (eine Wahrheit)
-- ---------------------------------------------------------------------
check("Config.Tower.Validate ohne Meldungen", function()
	local errors = TowerConfig.Validate({})
	assert(#errors == 0, table.concat(errors, " | "))
end)

check("Startwerte == Config/Tower (Konstanten, Stufen, Räume, Personal)", function()
	eq(TowerConfig.I0, 4)
	eq(TowerConfig.IR, 1.30)
	eq(TowerConfig.C2, TM.FloorCost(2))
	eq(TowerConfig.Floors, TM.FLOORS)
	eq(TowerConfig.Salary, TM.BaseIncome({}))
	for i, stage in ipairs(TowerConfig.Stages) do
		eq(TM.StageOf(stage.First), i, "Stufe " .. stage.Key)
		local lic, ipo = TM.GateFor(stage.First)
		eq(lic, stage.Licence, "Tor Lizenz " .. stage.Key)
		eq(ipo, stage.Ipo, "Tor Börsengang " .. stage.Key)
	end
	for _, room in ipairs(TowerConfig.Rooms) do
		near(TM.BaseIncome({ floorData(room.Key) }), 3 + 4 * room.Factor, 1e-9, "Raum " .. room.Key)
	end
	for _, staff in ipairs(TowerConfig.Staff) do
		if staff.Lobby then
			eq(TM.StaffCost(5, staff.Key), staff.Price, "Preis " .. staff.Key)
		else
			eq(TM.StaffCost(5, staff.Key), math.floor(3375 * staff.CostMult + 0.5), "Kosten " .. staff.Key)
		end
	end
	eq(TM.EfficiencyCost(TowerConfig.Efficiency.Max), 0, "Effizienz-Deckel")
	eq(TM.EfficiencyCost(0), TowerConfig.Efficiency.Base)
end)

check("Configure(Config/Tower) ändert nichts an den Tabellen", function()
	TM.Configure(TowerConfig)
	checkTables("nach Configure")
	TM.Configure({ I0 = NAN, IR = 99, C2 = -5, Bands = { { 3, 50, 9 } }, Floors = 70 })
	checkTables("ungültige Werte ignoriert")
	TM.Configure(nil)
	checkTables("nil ignoriert")
end)

check("Tower-Name aus Wortbausteinen", function()
	eq(TowerConfig.NameText(5, 1, "de"), "Stiller Falke Tower")
	eq(TowerConfig.NameText(5, 1, "en"), "Silent Falcon Tower")
	eq(TowerConfig.NameText(18, 3, "de"), "Kristall-Komet Tower", "Bindestrich-Baustein")
	eq(TowerConfig.NameText(999, -1, "de"), "Blauer Falke Tower", "ungültig -> 1")
end)

-- ---------------------------------------------------------------------
for _, failure in ipairs(failures) do
	print("FAIL " .. failure)
end
print(("towermath.test: %d/%d PASS"):format(passed, passed + failed))
if failed > 0 then
	error(("%d Test(s) fehlgeschlagen"):format(failed))
end
