--[[
	Belohnungen: Offline-Geld (Manager arbeiten weiter, während du weg bist)
	und die tägliche Belohnung mit Serie (Tag 1–7).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local Core = require(script.Parent.Core)

local RewardService = {}

local function today(): number
	return os.time() // 86400
end

local function nextStreak(profile): number
	local daily = profile.Daily
	if daily.LastDay == today() - 1 then
		return daily.Streak % #Config.Daily.Minutes + 1
	end
	return 1
end

local function dailyAvailable(profile): boolean
	return profile.Daily.LastDay < today()
end

-- Einkommen ohne Event-Bonus (für Offline-Geld & Belohnungen)
local function baseStats(session)
	return Economy.ComputeStats(session.Profile, {
		DoubleCash = session.Passes.DoubleCash,
		TurboPass = session.Passes.Turbo,
	})
end

function RewardService.GrantOffline(session)
	local profile = session.Profile
	if profile.LastOnline <= 0 then
		return
	end
	local elapsed = os.time() - profile.LastOnline
	if elapsed < Config.Offline.MinSeconds then
		return
	end
	local stats = baseStats(session)
	if stats.AutoIncome <= 0 then
		return
	end
	local seconds = math.min(elapsed, Economy.OfflineCapSeconds(profile))
	local amount = stats.AutoIncome * Economy.OfflineRate(profile) * seconds
	if amount <= 0 then
		return
	end
	Core.AddEarnings(session, amount)
	Core.Effect(session.Player, "Offline", { Amount = amount, Seconds = elapsed, Counted = seconds })
end

function RewardService.ClaimDaily(session)
	local profile = session.Profile
	if not dailyAvailable(profile) then
		Core.Notify(session.Player, "Die tägliche Belohnung gibt's morgen wieder! ⏳", "info")
		return
	end
	local streak = nextStreak(profile)
	local stats = baseStats(session)
	local amount = Economy.IncomeReward(stats, Config.Daily.Minutes[streak], Config.Daily.MinReward)
	profile.Daily.LastDay = today()
	profile.Daily.Streak = streak
	Core.AddEarnings(session, amount)
	Core.MarkDirty(session)
	Core.Notify(session.Player, "🎁 Tag " .. streak .. ": +" .. Format.Cash(amount) .. "!", "gold")
	Core.Effect(session.Player, "Reward", { Amount = amount, Title = "Tägliche Belohnung – Tag " .. streak })
end

function RewardService.Init()
	Core.RegisterAction("ClaimDaily", RewardService.ClaimDaily)
	table.insert(Core.SyncExtras, function(session, payload)
		local profile = session.Profile
		local streak = nextStreak(profile)
		local stats = session.Stats or baseStats(session)
		payload.Daily = {
			Available = dailyAvailable(profile),
			Streak = streak,
			Reward = Economy.IncomeReward(stats, Config.Daily.Minutes[streak], Config.Daily.MinReward),
			SecondsLeft = (today() + 1) * 86400 - os.time(),
		}
	end)
end

return RewardService
