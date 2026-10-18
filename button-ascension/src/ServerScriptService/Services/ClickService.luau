--[[
	ClickService (ModuleScript)
	Location: ServerScriptService/Services/ClickService
	Depends on: Shared/Config/GameConfig, Shared/Config/Chests, Shared/Formulas, Shared/Util,
	            Core/RateLimiter, Core/DataOps, StatsService, EconomyService, QuestService,
	            AchievementService, SecurityService, SyncService, WorldService, Net

	Server-authoritative pressing.
	  * Manual presses arrive on the "Click" RemoteEvent with NO trusted data.
	    A token bucket caps accepted presses (GameConfig.Click); excess presses
	    are dropped and sustained floods are flagged.
	  * Value, combo, crit, streak bursts and golden presses are rolled here.
	  * Auto-presses and passive income tick on a fixed interval.
	  * Offline earnings are granted once when the profile loads.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Chests = require(Shared.Config.Chests)
local Formulas = require(Shared.Formulas)
local Util = require(Shared.Util)
local Core = script.Parent.Parent.Core
local RateLimiter = require(Core.RateLimiter)
local DataOps = require(Core.DataOps)

local CLICK = GameConfig.Click

local ClickService = {
	Name = "ClickService",
	ServerClicksThisSecond = 0,
}

local limiter = RateLimiter.new(CLICK.BurstCapacity, CLICK.MaxClicksPerSecond)
local rng = Random.new()

function ClickService:Init(services)
	self.Services = services
	services.Net.onEvent("Click", function(player)
		self:_onClick(player)
	end)
end

function ClickService:Start()
	local autoAccumulator = 0
	local passiveAccumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		autoAccumulator += dt
		passiveAccumulator += dt
		if autoAccumulator >= GameConfig.AutoClick.TickInterval then
			local step = autoAccumulator
			autoAccumulator = 0
			for _, profile in pairs(self.Services.DataService.Profiles) do
				self:_autoTick(profile, step)
			end
		end
		if passiveAccumulator >= GameConfig.Passive.TickInterval then
			local step = passiveAccumulator
			passiveAccumulator = 0
			for _, profile in pairs(self.Services.DataService.Profiles) do
				self:_passiveTick(profile, step)
			end
		end
	end)
end

function ClickService:OnProfileLoaded(profile)
	local rt = profile.Runtime
	rt.Combo = 0
	rt.StreakCount = 0
	rt.LastClick = 0
	rt.AutoCarry = 0
	rt.PendingAuto = 0
	rt.PendingAutoCount = 0
	rt.PendingPassive = 0
	rt.AttemptWindow = os.clock()
	rt.AttemptCount = 0
	self:_grantOffline(profile)
end

function ClickService:OnProfileReleasing(profile)
	limiter:reset(profile.UserId)
end

-- Offline earnings: a share of passive income for the time since the last save.
function ClickService:_grantOffline(profile)
	local cfg = GameConfig.Offline
	local data = profile.Data
	local lastSeen = data.Meta.LastSeen
	if not cfg.Enabled or profile.Temporary or lastSeen <= 0 then
		return
	end
	local elapsed = os.time() - lastSeen
	if elapsed < cfg.MinSeconds then
		return
	end
	local stats = self.Services.StatsService:GetBase(profile)
	local seconds = math.min(elapsed, stats.offlineMaxSeconds)
	local amount = stats.passivePerSec * seconds * stats.offlineRate
	if amount >= 1 then
		self.Services.EconomyService:AddSparks(profile, amount, "offline")
		data.Stats.OfflineEarned += amount
		self.Services.Net.notify(profile.Player, "Offline", { Amount = amount, Seconds = seconds, Away = elapsed })
	end
end

local function rollGoldenReward(self, profile, stats)
	local reward = Util.weightedPick(rng, GameConfig.GoldenRewards)
	local result = { Type = reward.Type }
	if reward.Type == "Sparks" then
		local amount = stats.clickValue * reward.Clicks
		self.Services.EconomyService:AddSparks(profile, amount, "golden")
		result.Amount = amount
	elseif reward.Type == "Gems" then
		local gems = math.floor(rng:NextInteger(reward.Min, reward.Max) * stats.gemMultiplier)
		self.Services.EconomyService:Add(profile, "Gems", gems, "golden")
		result.Amount = gems
	elseif reward.Type == "Chest" then
		local chestId = Chests.bestSparksChestForStage(stats.stage)
		DataOps.addChest(profile.Data, chestId, 1)
		self.Services.SyncService:MarkDirty(profile, "Chests")
		result.Chest = chestId
	elseif reward.Type == "Frenzy" then
		self.Services.StatsService:StartFrenzy(profile, reward.Multiplier, reward.Duration)
		result.Multiplier = reward.Multiplier
		result.Duration = reward.Duration
	end
	return result
end

function ClickService:_onClick(player: Player)
	local profile = self.Services.DataService:GetProfile(player)
	if not profile then
		return
	end
	local rt = profile.Runtime
	local now = os.clock()

	-- Flood detection counts attempts, accepted or not.
	if now - rt.AttemptWindow >= 1 then
		if rt.AttemptCount > CLICK.SuspiciousClicksPerSecond then
			self.Services.SecurityService:Flag(player, "ClickFlood", rt.AttemptCount .. " presses/s")
		end
		rt.AttemptWindow = now
		rt.AttemptCount = 0
	end
	rt.AttemptCount += 1

	if not limiter:allow(player.UserId) then
		return
	end

	local stats = self.Services.StatsService:Get(profile)
	local data = profile.Data

	if now - rt.LastClick <= stats.comboWindow then
		rt.Combo = math.min(rt.Combo + 1, CLICK.HardComboLimit)
		rt.StreakCount += 1
	else
		rt.Combo = 1
		rt.StreakCount = 1
	end
	rt.LastClick = now

	local comboMult = Formulas.comboMultiplier(stats, rt.Combo)
	local crit = rng:NextNumber() < stats.critChance
	local amount = stats.clickValue * comboMult * (if crit then stats.critMultiplier else 1)

	local streakBonus = 0
	-- Counted separately from the clamped combo, so a capped combo still bursts only every StreakEvery presses.
	if rt.StreakCount % CLICK.StreakEvery == 0 then
		streakBonus = stats.clickValue * CLICK.StreakBurstClicks * stats.streakMultiplier * (rt.Combo / CLICK.StreakEvery) ^ 0.5
		data.Stats.StreakBursts += 1
	end

	local economy = self.Services.EconomyService
	economy:AddSparks(profile, amount + streakBonus, "click")
	economy:AddXP(profile, CLICK.XPPerClick * stats.xpMultiplier)

	local s = data.Stats
	s.TotalClicks += 1
	if crit then
		s.TotalCrits += 1
	end
	if rt.Combo > s.HighestCombo then
		s.HighestCombo = rt.Combo
	end

	local golden = nil
	if rng:NextNumber() < stats.goldenChance then
		s.GoldenClicks += 1
		golden = rollGoldenReward(self, profile, stats)
	end

	local quests = self.Services.QuestService
	quests:Progress(profile, "Clicks", 1)
	quests:Progress(profile, "Combo", rt.Combo)
	if crit then
		quests:Progress(profile, "Crits", 1)
	end
	if golden then
		quests:Progress(profile, "GoldenClicks", 1)
	end
	self.Services.AchievementService:MarkDirty(profile)
	self.ServerClicksThisSecond += 1

	self.Services.Net.fire(player, "ClickResult", {
		Amount = amount,
		Crit = crit,
		Combo = rt.Combo,
		ComboMult = comboMult,
		Streak = if streakBonus > 0 then streakBonus else nil,
		Golden = golden,
	})
end

function ClickService:_autoTick(profile, dt: number)
	local stats = self.Services.StatsService:Get(profile)
	if stats.autoRate <= 0 then
		return
	end
	local rt = profile.Runtime
	rt.AutoCarry = (rt.AutoCarry or 0) + stats.autoRate * dt
	local presses = math.floor(rt.AutoCarry)
	if presses <= 0 then
		return
	end
	rt.AutoCarry -= presses
	local crits = 0
	for _ = 1, presses do
		if rng:NextNumber() < stats.critChance then
			crits += 1
		end
	end
	local amount = stats.clickValue * (presses + crits * (stats.critMultiplier - 1))
	self.Services.EconomyService:AddSparks(profile, amount, "auto")
	self.Services.EconomyService:AddXP(profile, presses * CLICK.XPPerClick * CLICK.AutoClickXPFactor * stats.xpMultiplier)
	profile.Data.Stats.AutoClicks += presses
	profile.Data.Stats.TotalCrits += crits
	rt.PendingAuto = (rt.PendingAuto or 0) + amount
	rt.PendingAutoCount = (rt.PendingAutoCount or 0) + presses
end

function ClickService:_passiveTick(profile, dt: number)
	local stats = self.Services.StatsService:Get(profile)
	local rt = profile.Runtime
	local data = profile.Data
	data.Stats.PlayTime += dt
	if stats.passivePerSec > 0 then
		local amount = stats.passivePerSec * dt
		self.Services.EconomyService:AddSparks(profile, amount, "passive")
		rt.PendingPassive = (rt.PendingPassive or 0) + amount
	end
	-- One aggregated update per second for the client's floating numbers.
	if (rt.PendingAuto or 0) > 0 or (rt.PendingPassive or 0) > 0 then
		self.Services.Net.fire(profile.Player, "ClickResult", {
			Auto = rt.PendingAuto,
			AutoCount = rt.PendingAutoCount,
			Passive = rt.PendingPassive,
		})
		rt.PendingAuto = 0
		rt.PendingAutoCount = 0
		rt.PendingPassive = 0
	end
end

-- Resets the combo (used by ascension).
function ClickService:ResetCombo(profile)
	profile.Runtime.Combo = 0
	profile.Runtime.StreakCount = 0
	profile.Runtime.LastClick = 0
end

return ClickService
