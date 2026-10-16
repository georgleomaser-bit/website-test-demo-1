--[[
	Balance-Simulation: ein "gieriger" Spieler kauft immer das, was sich am
	schnellsten bezahlt macht. Zeigt, wann Linien, Manager und Rebirths kommen.

	lune run tests/balance.sim.luau build/ZitronenFabrikTycoon.rbxlx [Stunden]
]]

local process = require("@lune/process")
local Harness = require("./harness")

local h = Harness.load(process.args[1] or "build/ZitronenFabrikTycoon.rbxlx")
local shared = Harness.find(h.game, "ReplicatedStorage.Shared")
local Config = h.require(shared.Config)
local Format = h.require(shared.Format)
local Economy = h.require(shared.Economy)

local HOURS = tonumber(process.args[2]) or 6
local DT = 1
local MANUAL_LANES = 2 -- so viele Linien ohne Manager drückt der Spieler selbst
local REACTION = 0.6

local profile = Economy.NewProfile()
local log = {}
local function note(t, text)
	table.insert(log, string.format("%8s  %s", Format.Time(t), text))
end

local function laneIncome(stats, i, manualAllowed)
	local st = profile.Lanes[i]
	if st.Level <= 0 then
		return 0
	end
	local ls = stats.Lanes[i]
	if st.Manager then
		return ls.IncomePerSec
	end
	if manualAllowed then
		return ls.Revenue / (ls.CycleTime + REACTION)
	end
	return 0
end

local function totalIncome(stats)
	-- Manuelle Linien: die besten MANUAL_LANES ohne Manager
	local manual = {}
	for i = 1, #Config.Lanes do
		if profile.Lanes[i].Level > 0 and not profile.Lanes[i].Manager then
			table.insert(manual, { i = i, v = laneIncome(stats, i, true) })
		end
	end
	table.sort(manual, function(a, b)
		return a.v > b.v
	end)
	local allowed = {}
	for k = 1, math.min(MANUAL_LANES, #manual) do
		allowed[manual[k].i] = true
	end
	local sum = 0
	for i = 1, #Config.Lanes do
		sum += laneIncome(stats, i, allowed[i])
	end
	return sum
end

local function deepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in pairs(t) do
		c[k] = deepCopy(v)
	end
	return c
end

local function evaluate(apply)
	local saved = deepCopy(profile)
	local before = totalIncome(Economy.ComputeStats(profile, {}))
	apply()
	local after = totalIncome(Economy.ComputeStats(profile, {}))
	profile = saved
	return after - before
end

local function options()
	local stats = Economy.ComputeStats(profile, {})
	local list = {}
	for i, lane in ipairs(Config.Lanes) do
		local st = profile.Lanes[i]
		local prevUnlocked = i == 1 or profile.Lanes[i - 1].Level > 0
		if st.Level == 0 then
			if prevUnlocked then
				table.insert(list, {
					name = "Linie " .. i .. " freischalten",
					cost = Economy.LevelCost(lane, 0, 1, stats.Discount),
					apply = function()
						profile.Lanes[i].Level = 1
					end,
					event = true,
				})
			end
		else
			if st.Level < Config.MaxLevel then
				table.insert(list, {
					name = "Linie " .. i .. " Level",
					cost = Economy.LevelCost(lane, st.Level, 1, stats.Discount),
					apply = function()
						profile.Lanes[i].Level += 1
					end,
				})
			end
			if not st.Manager then
				table.insert(list, {
					name = "Manager " .. i,
					cost = Economy.ManagerCost(lane, stats),
					apply = function()
						profile.Lanes[i].Manager = true
					end,
					event = true,
				})
			end
			if st.Upgraders < #lane.Upgraders then
				table.insert(list, {
					name = "Maschine " .. i .. "." .. (st.Upgraders + 1),
					cost = Economy.UpgraderCost(lane, st.Upgraders + 1, stats),
					apply = function()
						profile.Lanes[i].Upgraders += 1
					end,
					event = true,
				})
			end
		end
	end
	for _, u in ipairs(Config.CashUpgrades) do
		if not profile.Upgrades[u.Id] then
			table.insert(list, {
				name = "Upgrade " .. u.Name,
				cost = u.Cost,
				apply = function()
					profile.Upgrades[u.Id] = true
				end,
				event = true,
			})
			break -- nur das günstigste anbieten reicht für die Simulation
		end
	end
	if profile.Decor < #Config.Decor then
		local d = Config.Decor[profile.Decor + 1]
		table.insert(list, {
			name = "Deko " .. d.Name,
			cost = d.Cost,
			apply = function()
				profile.Decor += 1
			end,
			event = true,
		})
	end
	return list
end

local function bestOption()
	local best, bestScore = nil, math.huge
	local income = math.max(1e-9, totalIncome(Economy.ComputeStats(profile, {})))
	for _, opt in ipairs(options()) do
		local gain = evaluate(opt.apply)
		local score
		if gain > 0 then
			-- Amortisationszeit + Wartezeit bis man es sich leisten kann
			score = opt.cost / gain + math.max(0, opt.cost - profile.Cash) / income
		else
			score = math.huge
		end
		if score < bestScore then
			best, bestScore = opt, score
		end
	end
	return best
end

local function rebirth(t)
	local claim = Economy.ClaimableInvestors(profile)
	profile.Investors += claim
	profile.Stats.Rebirths += 1
	local keep = {
		Investors = profile.Investors,
		InvestorsSpent = profile.InvestorsSpent,
		EvoEarnings = profile.EvoEarnings,
		AllTimeEarnings = profile.AllTimeEarnings,
		Evolution = profile.Evolution,
		Powers = profile.Powers,
		Stats = profile.Stats,
	}
	profile = Economy.NewProfile()
	for k, v in pairs(keep) do
		profile[k] = v
	end
	profile.Cash = Economy.StartCashAfterRebirth(profile)
	local stats = Economy.ComputeStats(profile, {})
	note(t, string.format("REBIRTH #%d: +%s Investoren (jetzt %s, Bonus x%.2f)", profile.Stats.Rebirths, Format.Number(claim), Format.Number(profile.Investors), stats.InvestorMult))
end

local t = 0
local nextReport = 600
local runStart = 0
while t < HOURS * 3600 do
	-- Kaufen, solange das beste Angebot bezahlbar ist
	for _ = 1, 200 do
		local opt = bestOption()
		if not opt or opt.cost > profile.Cash then
			break
		end
		profile.Cash -= opt.cost
		opt.apply()
		if opt.event then
			note(t, opt.name .. " für " .. Format.Cash(opt.cost))
		end
	end

	local stats = Economy.ComputeStats(profile, {})
	local inc = totalIncome(stats)
	profile.Cash += inc * DT
	profile.EvoEarnings += inc * DT
	profile.AllTimeEarnings += inc * DT
	t += DT

	-- Rebirth, wenn sich die Investoren mindestens verdoppeln (und mind. 20 Minuten gespielt)
	local claim = Economy.ClaimableInvestors(profile)
	if claim >= math.max(25, profile.Investors) and t - runStart > 15 * 60 then
		rebirth(t)
		runStart = t
	end

	if Economy.CanEvolve(profile) and Economy.ClaimableInvestors(profile) > 0 then
		local tier = profile.Evolution + 1
		local keepStats = profile.Stats
		local all = profile.AllTimeEarnings
		profile = Economy.NewProfile()
		profile.Evolution = tier
		profile.Stats = keepStats
		profile.AllTimeEarnings = all
		runStart = t
		note(t, "EVOLUTION -> " .. Config.Fruits[tier + 1].Name)
	end

	if t >= nextReport then
		nextReport += 1800
		local levels = {}
		for i = 1, #Config.Lanes do
			table.insert(levels, tostring(profile.Lanes[i].Level) .. (profile.Lanes[i].Manager and "M" or ""))
		end
		note(t, string.format("Bericht: %s/s, Geld %s, Level [%s], nächster Rebirth +%s, Evo-Einnahmen %s, Upgrades %d", Format.Cash(inc), Format.Cash(profile.Cash), table.concat(levels, " "), Format.Number(claim), Format.Cash(profile.EvoEarnings), (function() local n = 0 for _ in pairs(profile.Upgrades) do n += 1 end return n end)()))
	end
end

for _, line in ipairs(log) do
	print(line)
end
