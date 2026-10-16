--[[
	Tests für Format und Economy. Start: lune run tests/shared.test.luau build/ZitronenFabrikTycoon.rbxlx
]]

local process = require("@lune/process")
local Harness = require("./harness")

local placePath = process.args[1] or "build/ZitronenFabrikTycoon.rbxlx"
local h = Harness.load(placePath)
local shared = Harness.find(h.game, "ReplicatedStorage.Shared")
local Config = h.require(shared.Config)
local Format = h.require(shared.Format)
local Economy = h.require(shared.Economy)

local failures = 0
local passes = 0
local function check(name, cond, detail)
	if cond then
		passes += 1
	else
		failures += 1
		print("FEHLER: " .. name .. (detail and (" -> " .. tostring(detail)) or ""))
	end
end
local function eq(name, got, want)
	check(name, got == want, "erwartet " .. tostring(want) .. ", bekommen " .. tostring(got))
end

-- Format
eq("0", Format.Number(0), "0")
eq("1.5", Format.Number(1.5), "1.5")
eq("999", Format.Number(999), "999")
eq("1K", Format.Number(1000), "1K")
eq("1.5K", Format.Number(1500), "1.5K")
eq("12.3K", Format.Number(12345), "12.3K")
eq("123K", Format.Number(123456), "123K")
eq("999K", Format.Number(999999), "999K")
eq("1M", Format.Number(1e6), "1M")
eq("1B", Format.Number(1e9), "1B")
eq("1T", Format.Number(1e12), "1T")
eq("1Qa", Format.Number(1e15), "1Qa")
eq("2.5Sx", Format.Number(2.5e21), "2.5Sx")
eq("neg", Format.Number(-1500), "-1.5K")
eq("nan", Format.Number(0 / 0), "0")
eq("cash", Format.Cash(2500), "$2.5K")
eq("huge sci", string.sub(Format.Number(1e100), -3), "100")
eq("int", Format.Int(1234567), "1.234.567")
eq("int small", Format.Int(123), "123")
eq("int 6", Format.Int(123456), "123.456")
eq("time s", Format.Time(45), "45s")
eq("time m", Format.Time(192), "3m 12s")
eq("time h", Format.Time(3700), "1h 01m")
for exp = 3, 90 do
	for _, m in { 1, 1.5, 9.99, 5 } do
		local s = Format.Number(m * 10 ^ exp)
		check("kein 1000er " .. exp, not string.find(s, "^1000"), s)
	end
end

-- Economy: Kosten
local lane1 = Config.Lanes[1]
eq("unlock kostet BaseCost", Economy.LevelCost(lane1, 0, 1, 1), lane1.BaseCost)
check("summe", math.abs(Economy.LevelCost(lane1, 0, 2, 1) - lane1.BaseCost * (1 + lane1.CostGrowth)) < 1e-9)
eq("max mit 1$", Economy.MaxAffordable(lane1, 0, 1, 1), 1)
eq("max mit 0$", Economy.MaxAffordable(lane1, 0, 0.5, 1), 0)
for _, lane in Config.Lanes do
	for _, level in { 0, 1, 7, 50, 300 } do
		for _, cash in { 1, 1e3, 1e9, 1e20, 1e40 } do
			local n = Economy.MaxAffordable(lane, level, cash, 1)
			check("max bezahlbar " .. lane.Id, n == 0 or Economy.LevelCost(lane, level, n, 1) <= cash)
			check("max ist maximal " .. lane.Id, n + level >= Config.MaxLevel or Economy.LevelCost(lane, level, n + 1, 1) > cash)
		end
	end
end
eq("max level cap", Economy.MaxAffordable(lane1, Config.MaxLevel, 1e300, 1), 0)
eq("resolve max min 1", Economy.ResolveBuyAmount(lane1, 5, 0, 1, "max"), 1)
eq("resolve 10", Economy.ResolveBuyAmount(lane1, 5, 0, 1, 10), 10)
eq("resolve cap", Economy.ResolveBuyAmount(lane1, Config.MaxLevel - 3, 0, 1, 100), 3)

-- Meilensteine
eq("speed 0", Economy.SpeedFactor(0), 1)
eq("speed 24", Economy.SpeedFactor(24), 1)
eq("speed 25", Economy.SpeedFactor(25), 2)
eq("speed 50", Economy.SpeedFactor(50), 4)
eq("next ms", Economy.NextMilestone(10).Level, 25)
eq("prev ms", Economy.PreviousMilestoneLevel(30), 25)

-- Investoren
eq("inv 0", Economy.InvestorsTotalFor(0), 0)
eq("inv divisor", Economy.InvestorsTotalFor(Config.Rebirth.Divisor), Config.Rebirth.Coefficient)
check("inverse", Economy.InvestorsTotalFor(Economy.EarningsForInvestors(500)) >= 499)

-- Profil & Stats
local p = Economy.NewProfile()
local stats = Economy.ComputeStats(p, {})
eq("neues profil kein einkommen", stats.TotalIncome, 0)
p.Lanes[1].Level = 1
stats = Economy.ComputeStats(p, {})
check("einkommen lane1", math.abs(stats.Lanes[1].IncomePerSec - 1 / 1.2) < 1e-9, stats.Lanes[1].IncomePerSec)
p.Investors = 100
stats = Economy.ComputeStats(p, {})
check("investoren bonus", math.abs(stats.Global - 3) < 1e-9, stats.Global)
p.Upgrades["l1_1"] = true
stats = Economy.ComputeStats(p, {})
check("upgrade x3", math.abs(stats.Lanes[1].Revenue - 9) < 1e-9, stats.Lanes[1].Revenue)
p.Lanes[1].Upgraders = 3
stats = Economy.ComputeStats(p, { EventIncome = 3, EventSpeed = 2, DoubleCash = true })
check("alles zusammen", math.abs(stats.Lanes[1].Revenue - 1 * 3 * 3 * 30 * 3 * 2) < 1e-6, stats.Lanes[1].Revenue)
check("event speed", math.abs(stats.Lanes[1].CycleTime - 0.6) < 1e-9, stats.Lanes[1].CycleTime)

-- Reconcile
local broken = { Cash = 0 / 0, Lanes = { { Level = 5000, Manager = "ja", Upgraders = 99 } }, Powers = {} }
local fixed = Economy.Reconcile(broken)
eq("reconcile cash", fixed.Cash, 0)
eq("reconcile level", fixed.Lanes[1].Level, Config.MaxLevel)
eq("reconcile manager", fixed.Lanes[1].Manager, false)
eq("reconcile upgr", fixed.Lanes[1].Upgraders, 3)
eq("reconcile lanes", #fixed.Lanes, #Config.Lanes)
check("reconcile settings", fixed.Settings.Music == true)

-- Upgrades sind sortiert und eindeutig
local seen = {}
for i, u in Config.CashUpgrades do
	check("upgrade eindeutig " .. u.Id, not seen[u.Id])
	seen[u.Id] = true
	if i > 1 then
		check("sortiert", Config.CashUpgrades[i - 1].Cost <= u.Cost)
	end
end

print(string.format("Shared-Tests: %d ok, %d Fehler", passes, failures))
if failures > 0 then
	process.exit(1)
end
