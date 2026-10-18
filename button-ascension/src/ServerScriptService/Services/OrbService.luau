--[[
	OrbService (ModuleScript)
	Location: ServerScriptService/Services/OrbService
	Depends on: Shared/Config/{GameConfig,Chests}, Shared/Util, Core/Net, Core/Guard,
	            Core/DataOps, EconomyService, StatsService, SyncService, QuestService

	Bonus orbs: every 70–140 seconds (shorter with Orb Magnet) the server
	offers a player an orb that floats onto their screen for a few seconds.
	The server remembers the only valid orb id and its expiry, so orbs cannot
	be invented, claimed twice or claimed late by a modified client.

	Action: ClaimOrb { Id: integer }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Chests = require(Shared.Config.Chests)
local Util = require(Shared.Util)
local Core = script.Parent.Parent.Core
local Net = require(Core.Net)
local Guard = require(Core.Guard)
local DataOps = require(Core.DataOps)

local ORBS = GameConfig.Orbs

local OrbService = { Name = "OrbService" }

local rng = Random.new()

function OrbService:Init(services)
	self.Services = services
	Net.registerAction("ClaimOrb", {
		Rate = { Capacity = 3, Refill = 0.5 },
		Handler = function(profile, payload)
			return self:Claim(profile, payload.Id)
		end,
	})
end

function OrbService:Start()
	if not ORBS.Enabled then
		return
	end
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for _, profile in pairs(self.Services.DataService.Profiles) do
				local rt = profile.Runtime
				if rt.Orb and now > rt.Orb.ExpiresAt + ORBS.ClaimGrace then
					rt.Orb = nil
					self:_schedule(profile, false)
				elseif not rt.Orb and rt.NextOrbAt and now >= rt.NextOrbAt then
					self:_spawn(profile)
				end
			end
		end
	end)
end

function OrbService:OnProfileLoaded(profile)
	profile.Runtime.OrbCounter = 0
	self:_schedule(profile, true)
end

function OrbService:_schedule(profile, first: boolean)
	local stats = self.Services.StatsService:Get(profile)
	local delay = if first then rng:NextNumber(30, 60) else rng:NextNumber(ORBS.MinInterval, ORBS.MaxInterval)
	profile.Runtime.NextOrbAt = os.clock() + delay * stats.orbIntervalMultiplier
end

function OrbService:_spawn(profile)
	local rt = profile.Runtime
	rt.OrbCounter += 1
	rt.Orb = { Id = rt.OrbCounter, ExpiresAt = os.clock() + ORBS.Lifetime }
	self.Services.Net.fire(profile.Player, "OrbSpawn", {
		Id = rt.Orb.Id,
		Lifetime = ORBS.Lifetime,
		X = rng:NextNumber(0.18, 0.82),
		Y = rng:NextNumber(0.25, 0.7),
	})
end

function OrbService:Claim(profile, rawId: any)
	local id = Guard.integer(rawId, 1, 1e9)
	local rt = profile.Runtime
	local orb = rt.Orb
	if not id or not orb or orb.Id ~= id then
		return Net.fail("That orb is gone.")
	end
	if os.clock() > orb.ExpiresAt + ORBS.ClaimGrace then
		rt.Orb = nil
		self:_schedule(profile, false)
		return Net.fail("Too slow! The orb faded.")
	end
	rt.Orb = nil
	self:_schedule(profile, false)

	local stats = self.Services.StatsService:Get(profile)
	local reward = Util.weightedPick(rng, ORBS.Rewards)
	local result = { Type = reward.Type }
	local economy = self.Services.EconomyService
	if reward.Type == "Sparks" then
		local amount = math.max(stats.clickValue * reward.MinClicks, stats.passivePerSec * reward.IncomeSeconds)
			* stats.orbRewardMultiplier
		economy:AddSparks(profile, amount, "orb")
		result.Amount = amount
	elseif reward.Type == "Gems" then
		local gems = math.floor(rng:NextInteger(reward.Min, reward.Max) * stats.gemMultiplier * stats.orbRewardMultiplier)
		economy:Add(profile, "Gems", gems, "orb")
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

	profile.Data.Stats.OrbsCollected += 1
	self.Services.SyncService:MarkDirty(profile, "Stats")
	self.Services.QuestService:Progress(profile, "OrbsCollected", 1)
	self.Services.AchievementService:MarkDirty(profile)
	return Net.ok({ Reward = result })
end

return OrbService
