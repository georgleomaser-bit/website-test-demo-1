-- Daily login streak, playtime gifts, daily tasks, expeditions, codes and index rewards.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Rewards = require(Shared.Config.Rewards)
local Animals = require(Shared.Config.Animals)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)

local RewardService = {}

local S
local rng = Random.new()

function RewardService.Init(services)
	S = services
end

local function today(): number
	return math.floor(os.time() / 86400)
end

local function makeTasks(player: Player)
	local data = S.DataService.get(player)
	local ctx = S.PlayerService.ctx(player)
	local pool = table.clone(Rewards.TaskPool)
	local list = {}
	for _ = 1, math.min(Rewards.TasksPerDay, #pool) do
		local def = table.remove(pool, rng:NextInteger(1, #pool))
		local goal
		if def.Kind == "Train" then
			goal = Formulas.speedForSeconds(ctx, def.TrainSeconds, def.Min)
		elseif def.Kind == "EarnCash" then
			goal = Formulas.cashForSeconds(ctx, def.IncomeSeconds, def.Min)
		else
			goal = def.Count
		end
		table.insert(list, {
			Kind = def.Kind,
			Text = string.format(def.Text, Format.number(goal)),
			Goal = goal,
			Progress = 0,
			Claimed = false,
		})
	end
	data.Tasks = { Day = today(), List = list, AllClaimed = false }
end

local function checkDay(player: Player)
	local data = S.DataService.get(player)
	local rt = S.PlayerService.get(player)
	if not data then
		return
	end
	if data.Tasks.Day ~= today() then
		makeTasks(player)
		S.PlayerService.markState(player)
	end
	if rt and rt.Passes.BaitBag and data.BaitBagDay ~= today() then
		data.BaitBagDay = today()
		S.PlayerService.addBait(player, Rewards.BaitBagDaily)
		S.PlayerService.notify(player, "Bait Bag: +" .. Rewards.BaitBagDaily .. " Glow Bait for today!", "reward")
	end
end

function RewardService.onJoin(player: Player)
	checkDay(player)
end

function RewardService.progress(player: Player, kind: string, amount: number)
	local data = S.DataService.get(player)
	if not data or not data.Tasks or not data.Tasks.List then
		return
	end
	for _, t in ipairs(data.Tasks.List) do
		if t.Kind == kind and not t.Claimed and t.Progress < t.Goal then
			t.Progress = math.min(t.Goal, t.Progress + amount)
			if t.Progress >= t.Goal then
				S.PlayerService.notify(player, "Task complete: " .. t.Text .. "! Claim it in Tasks.", "success")
				S.PlayerService.markState(player)
			else
				S.PlayerService.markStats(player)
			end
		end
	end
end

function RewardService.expeditionProgress(player: Player, zone: number)
	local data = S.DataService.get(player)
	local exp = data.Expedition
	if exp.Zones[zone] then
		return
	end
	exp.Zones[zone] = true
	local done = 0
	for i = 1, 4 do
		if exp.Zones[i] then
			done += 1
		end
	end
	if done >= 4 then
		exp.Level += 1
		exp.Zones = { false, false, false, false }
		S.PlayerService.grantRewards(player, Rewards.Expedition(exp.Level), "Expedition " .. exp.Level .. " complete")
		S.PlayerService.effect(player, "Expedition", { Level = exp.Level })
	else
		S.PlayerService.notify(player, "Expedition: " .. done .. "/4 zones", "info")
	end
	S.PlayerService.markState(player)
end

function RewardService.Start()
	local Router = S.Router

	Router.register("ClaimDaily", function(player)
		local data = S.DataService.get(player)
		local now = os.time()
		local hours = (now - data.Daily.Last) / 3600
		if data.Daily.Last > 0 and hours < Rewards.DailyClaimCooldownHours then
			return false, "Next daily reward in " .. Format.time((Rewards.DailyClaimCooldownHours - hours) * 3600)
		end
		if data.Daily.Last == 0 or hours > Rewards.DailyStreakResetHours then
			data.Daily.Streak = 1
		else
			data.Daily.Streak += 1
		end
		data.Daily.Last = now
		local index = ((data.Daily.Streak - 1) % #Rewards.Daily) + 1
		S.PlayerService.grantRewards(player, Rewards.Daily[index], "Day " .. data.Daily.Streak .. " reward")
		return true
	end)

	Router.register("ClaimPlaytime", function(player, index)
		local rt = S.PlayerService.get(player)
		local gift = type(index) == "number" and Rewards.Playtime[index]
		if not gift then
			return false
		end
		local key = tostring(index)
		if rt.PlaytimeClaimed[key] then
			return false, "Already claimed"
		end
		if os.time() - rt.SessionStart < gift.Minutes * 60 then
			return false, "Not ready yet"
		end
		rt.PlaytimeClaimed[key] = true
		S.PlayerService.grantRewards(player, { gift.Reward }, "Gift")
		return true
	end)

	Router.register("ClaimTask", function(player, index)
		checkDay(player)
		local data = S.DataService.get(player)
		local t = type(index) == "number" and data.Tasks.List[index]
		if not t then
			return false
		end
		if t.Claimed then
			return false, "Already claimed"
		end
		if t.Progress < t.Goal then
			return false, "Not finished yet"
		end
		t.Claimed = true
		S.PlayerService.grantRewards(player, Rewards.TaskReward, "Task reward")
		local all = true
		for _, other in ipairs(data.Tasks.List) do
			if not other.Claimed then
				all = false
			end
		end
		if all and not data.Tasks.AllClaimed then
			data.Tasks.AllClaimed = true
			S.PlayerService.grantRewards(player, Rewards.AllTasksReward, "All tasks done")
		end
		return true
	end)

	Router.register("RedeemCode", function(player, code)
		if type(code) ~= "string" or #code > 40 then
			return false, "Invalid code"
		end
		code = string.upper((code:gsub("%s", "")))
		local reward = Rewards.Codes[code]
		if not reward then
			return false, "Invalid code"
		end
		local data = S.DataService.get(player)
		if data.Codes[code] then
			return false, "Code already redeemed"
		end
		data.Codes[code] = true
		S.PlayerService.grantRewards(player, reward, "Code " .. code)
		return true, "Code redeemed!"
	end)

	Router.register("ClaimIndexZone", function(player, zone)
		local data = S.DataService.get(player)
		local reward = type(zone) == "number" and Rewards.IndexZone[zone]
		if not reward then
			return false
		end
		local key = tostring(zone)
		if data.IndexClaimed.Zones[key] then
			return false, "Already claimed"
		end
		for _, def in ipairs(Animals.ByZone[zone]) do
			if not data.Index[def.Id] then
				return false, "Discover every animal of this zone first"
			end
		end
		data.IndexClaimed.Zones[key] = true
		S.PlayerService.grantRewards(player, reward, "Index reward")
		return true
	end)

	Router.register("ClaimIndexMilestone", function(player, index)
		local data = S.DataService.get(player)
		local milestone = type(index) == "number" and Rewards.IndexMilestones[index]
		if not milestone then
			return false
		end
		local key = tostring(index)
		if data.IndexClaimed.Milestones[key] then
			return false, "Already claimed"
		end
		local count = 0
		for _ in pairs(data.Index) do
			count += 1
		end
		if count < milestone.Count then
			return false, "Discover " .. milestone.Count .. " animals first"
		end
		data.IndexClaimed.Milestones[key] = true
		S.PlayerService.grantRewards(player, milestone.Reward, "Index milestone")
		return true
	end)

	-- new day while playing
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
				if S.DataService.isLoaded(player) then
					checkDay(player)
				end
			end
		end
	end)
end

return RewardService
