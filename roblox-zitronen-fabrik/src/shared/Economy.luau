--[[
	Alle Formeln der Wirtschaft an einem Ort.
	Wird vom Server (rechnet echt) und vom Client (zeigt Preise an) benutzt.
]]

local Config = require(script.Parent.Config)

local Economy = {}

--------------------------------------------------------------------------
-- Profil (das wird gespeichert)
--------------------------------------------------------------------------
function Economy.NewProfile()
	local lanes = {}
	for i = 1, #Config.Lanes do
		lanes[i] = { Level = 0, Manager = false, Upgraders = 0 }
	end
	return {
		Version = 1,
		Cash = Config.StartCash,
		EvoEarnings = 0, -- seit der letzten Evolution verdient (zählt für Investoren)
		AllTimeEarnings = 0,
		Investors = 0,
		InvestorsSpent = 0,
		Evolution = 0,
		Powers = {},
		Lanes = lanes,
		Upgrades = {},
		Decor = 0,
		Secrets = { UfoKey = false, UfoKeyDelivered = false },
		Daily = { LastDay = 0, Streak = 0 },
		ObbyLast = 0,
		Stats = { Rebirths = 0, Evolutions = 0, PlayTime = 0, Presses = 0, Golden = 0, Pickups = 0 },
		Settings = { Music = true, Sfx = true, OtherItems = true, Guide = true },
		LastOnline = 0,
	}
end

local function deepFill(target, template)
	for key, value in pairs(template) do
		if target[key] == nil then
			if type(value) == "table" then
				local copy = {}
				deepFill(copy, value)
				target[key] = copy
			else
				target[key] = value
			end
		elseif type(value) == "table" and type(target[key]) == "table" then
			deepFill(target[key], value)
		end
	end
end

local function sanitizeNumber(n, default)
	if type(n) ~= "number" or n ~= n then
		return default
	end
	if n == math.huge then
		return 1e300
	end
	return n
end

-- Fehlende Felder ergänzen (z. B. nach einem Update) und kaputte Werte reparieren
function Economy.Reconcile(profile)
	if type(profile) ~= "table" then
		return Economy.NewProfile()
	end
	local template = Economy.NewProfile()
	if type(profile.Lanes) ~= "table" then
		profile.Lanes = template.Lanes
	end
	for i = 1, #Config.Lanes do
		if type(profile.Lanes[i]) ~= "table" then
			profile.Lanes[i] = { Level = 0, Manager = false, Upgraders = 0 }
		end
	end
	deepFill(profile, template)
	profile.Cash = math.max(0, sanitizeNumber(profile.Cash, 0))
	profile.EvoEarnings = math.max(0, sanitizeNumber(profile.EvoEarnings, 0))
	profile.AllTimeEarnings = math.max(0, sanitizeNumber(profile.AllTimeEarnings, 0))
	profile.Investors = math.max(0, math.floor(sanitizeNumber(profile.Investors, 0)))
	profile.InvestorsSpent = math.max(0, math.floor(sanitizeNumber(profile.InvestorsSpent, 0)))
	profile.Evolution = math.clamp(math.floor(sanitizeNumber(profile.Evolution, 0)), 0, #Config.Fruits - 1)
	profile.Decor = math.clamp(math.floor(sanitizeNumber(profile.Decor, 0)), 0, #Config.Decor)
	for i = 1, #Config.Lanes do
		local lane = profile.Lanes[i]
		lane.Level = math.clamp(math.floor(sanitizeNumber(lane.Level, 0)), 0, Config.MaxLevel)
		lane.Upgraders = math.clamp(math.floor(sanitizeNumber(lane.Upgraders, 0)), 0, #Config.Lanes[i].Upgraders)
		lane.Manager = lane.Manager == true
		if lane.Level == 0 then
			lane.Manager = false
			lane.Upgraders = 0
		end
	end
	return profile
end

--------------------------------------------------------------------------
-- Level, Kosten, Meilensteine
--------------------------------------------------------------------------
function Economy.SpeedFactor(level: number): number
	local f = 1
	for _, m in ipairs(Config.Milestones) do
		if level >= m.Level and m.Speed then
			f *= m.Speed
		end
	end
	return f
end

function Economy.RevenueFactor(level: number): number
	local f = 1
	for _, m in ipairs(Config.Milestones) do
		if level >= m.Level and m.Revenue then
			f *= m.Revenue
		end
	end
	return f
end

function Economy.NextMilestone(level: number)
	for _, m in ipairs(Config.Milestones) do
		if m.Level > level then
			return m
		end
	end
	return nil
end

function Economy.PreviousMilestoneLevel(level: number): number
	local prev = 0
	for _, m in ipairs(Config.Milestones) do
		if m.Level <= level then
			prev = m.Level
		end
	end
	return prev
end

-- Kosten für `amount` Level ab dem aktuellen Level
function Economy.LevelCost(lane, level: number, amount: number, discount: number?): number
	if amount <= 0 then
		return 0
	end
	local g = lane.CostGrowth
	return lane.BaseCost * (g ^ level) * ((g ^ amount) - 1) / (g - 1) * (discount or 1)
end

-- Wie viele Level kann man sich mit `cash` leisten?
function Economy.MaxAffordable(lane, level: number, cash: number, discount: number?): number
	local cap = Config.MaxLevel - level
	if cap <= 0 then
		return 0
	end
	local g = lane.CostGrowth
	local first = lane.BaseCost * (g ^ level) * (discount or 1)
	if cash < first then
		return 0
	end
	local n = math.floor(math.log(cash * (g - 1) / first + 1) / math.log(g))
	n = math.clamp(n, 0, cap)
	while n > 0 and Economy.LevelCost(lane, level, n, discount) > cash do
		n -= 1
	end
	while n < cap and Economy.LevelCost(lane, level, n + 1, discount) <= cash do
		n += 1
	end
	return n
end

-- "x1", "x10", "x100" oder "max" -> Anzahl (mind. 1, damit der Preis angezeigt wird)
function Economy.ResolveBuyAmount(lane, level: number, cash: number, discount: number, mode): number
	local cap = Config.MaxLevel - level
	if cap <= 0 then
		return 0
	end
	if mode == "max" then
		return math.max(1, Economy.MaxAffordable(lane, level, cash, discount))
	end
	local amount = math.floor(tonumber(mode) or 1)
	return math.clamp(amount, 1, cap)
end

function Economy.UpgraderMult(laneCfg, owned: number): number
	local m = 1
	for j = 1, math.min(owned, #laneCfg.Upgraders) do
		m *= laneCfg.Upgraders[j].Mult
	end
	return m
end

--------------------------------------------------------------------------
-- Investoren, Kräfte, Evolution
--------------------------------------------------------------------------
function Economy.InvestorsTotalFor(evoEarnings: number): number
	if evoEarnings <= 0 then
		return 0
	end
	return math.floor(Config.Rebirth.Coefficient * (evoEarnings / Config.Rebirth.Divisor) ^ Config.Rebirth.Exponent + 1e-9)
end

-- Wie viel muss man (seit der Evolution) verdient haben für `n` Investoren insgesamt?
function Economy.EarningsForInvestors(n: number): number
	return Config.Rebirth.Divisor * (n / Config.Rebirth.Coefficient) ^ (1 / Config.Rebirth.Exponent)
end

function Economy.ClaimableInvestors(profile): number
	local total = Economy.InvestorsTotalFor(profile.EvoEarnings)
	return math.max(0, total - profile.Investors - profile.InvestorsSpent)
end

function Economy.PowerLevel(profile, id: string): number
	return tonumber(profile.Powers[id]) or 0
end

function Economy.PowerCost(power, level: number): number
	return math.floor(power.BaseCost * power.Growth ^ level + 0.5)
end

function Economy.EvolutionRequirement(tier: number): number
	return Config.Evolution.BaseRequirement * Config.Evolution.Growth ^ tier
end

function Economy.EvolutionProgress(profile): number
	return profile.Investors + profile.InvestorsSpent + Economy.ClaimableInvestors(profile)
end

function Economy.CanEvolve(profile): boolean
	if profile.Evolution >= #Config.Fruits - 1 then
		return false
	end
	return Economy.EvolutionProgress(profile) >= Economy.EvolutionRequirement(profile.Evolution)
end

function Economy.StartCashAfterRebirth(profile): number
	local lvl = Economy.PowerLevel(profile, "start")
	if lvl <= 0 then
		return Config.StartCash
	end
	return 1000 * Config.PowerById.start.Value ^ (lvl - 1)
end

--------------------------------------------------------------------------
-- Alle abgeleiteten Werte (Multiplikatoren, Einnahmen pro Linie …)
-- ctx: { EventIncome = number?, EventSpeed = number?, DoubleCash = bool?, TurboPass = bool? }
--------------------------------------------------------------------------
function Economy.ComputeStats(profile, ctx)
	ctx = ctx or {}

	local perInvestor = Config.Rebirth.BonusPerInvestor
		+ Economy.PowerLevel(profile, "charisma") * Config.PowerById.charisma.Value
	local laneUpgradeMult = {}
	for i = 1, #Config.Lanes do
		laneUpgradeMult[i] = 1
	end
	local allMult = 1
	for id, owned in pairs(profile.Upgrades) do
		local u = owned and Config.CashUpgradeById[id]
		if u then
			if u.InvestorAdd then
				perInvestor += u.InvestorAdd
			elseif u.Lane == 0 then
				allMult *= u.Mult
			elseif laneUpgradeMult[u.Lane] then
				laneUpgradeMult[u.Lane] *= u.Mult
			end
		end
	end
	if profile.Secrets.UfoKeyDelivered then
		perInvestor *= Config.Secrets.UfoKeyInvestorMult
	end

	local investorMult = 1 + profile.Investors * perInvestor
	local decorMult = 1 + profile.Decor * Config.DecorBonus
	local evoIncome = Config.Evolution.IncomeMult ^ profile.Evolution
	local evoSpeed = Config.Evolution.SpeedMult ^ profile.Evolution
	local passMult = ctx.DoubleCash and 2 or 1
	local eventIncome = ctx.EventIncome or 1
	local eventSpeed = ctx.EventSpeed or 1

	local global = investorMult * decorMult * evoIncome * passMult * eventIncome * allMult
	local speed = (Config.PowerById.turbo.Value ^ Economy.PowerLevel(profile, "turbo"))
		* evoSpeed
		* eventSpeed
		* (ctx.TurboPass and 1.5 or 1)

	local golden = Economy.PowerLevel(profile, "golden") * Config.PowerById.golden.Value
	local goldenFactor = 1 + 9 * golden

	local stats = {
		PerInvestor = perInvestor,
		InvestorMult = investorMult,
		DecorMult = decorMult,
		EvoIncome = evoIncome,
		EvoSpeed = evoSpeed,
		AllMult = allMult,
		Global = global,
		Speed = speed,
		GoldenChance = golden,
		Discount = 1 - Economy.PowerLevel(profile, "discount") * Config.PowerById.discount.Value,
		BuildDiscount = 1 - Economy.PowerLevel(profile, "school") * Config.PowerById.school.Value,
		Lanes = {},
		AutoIncome = 0,
		TotalIncome = 0,
	}

	for i, laneCfg in ipairs(Config.Lanes) do
		local state = profile.Lanes[i]
		local level = state.Level
		local cycle = math.max(Config.MinCycleTime, laneCfg.CycleTime / (Economy.SpeedFactor(math.max(level, 0)) * speed))
		local mult = Economy.UpgraderMult(laneCfg, state.Upgraders) * laneUpgradeMult[i] * global
		local revenue = laneCfg.BaseRevenue * level * Economy.RevenueFactor(level) * mult
		local perSec = level > 0 and revenue * goldenFactor / cycle or 0
		stats.Lanes[i] = {
			Revenue = revenue,
			CycleTime = cycle,
			IncomePerSec = perSec,
			Mult = mult,
			UpgradeMult = laneUpgradeMult[i],
		}
		stats.TotalIncome += perSec
		if state.Manager then
			stats.AutoIncome += perSec
		end
	end

	return stats
end

function Economy.ManagerCost(laneCfg, stats): number
	return laneCfg.ManagerCost * stats.BuildDiscount
end

function Economy.UpgraderCost(laneCfg, index: number, stats): number
	local u = laneCfg.Upgraders[index]
	return u and u.Cost * stats.BuildDiscount or math.huge
end

function Economy.OfflineRate(profile): number
	return Config.Offline.BaseRate + Economy.PowerLevel(profile, "night") * Config.PowerById.night.Value
end

function Economy.OfflineCapSeconds(profile): number
	return (Config.Offline.BaseHours + Economy.PowerLevel(profile, "night") * Config.Offline.HoursPerLevel) * 3600
end

-- "Minuten Einnahmen" als Belohnung: nutzt das Gesamteinkommen (als liefe alles)
function Economy.IncomeReward(stats, minutes: number, minimum: number): number
	return math.max(minimum, stats.TotalIncome * 60 * minutes)
end

return Economy
