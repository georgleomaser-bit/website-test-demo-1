--[[
	TutorialService (ModuleScript)
	Location: ServerScriptService/Services/TutorialService
	Depends on: Shared/Config/Tutorial, Core/Net, EconomyService, SyncService, Net

	Runs the first-time tutorial (steps in Config/Tutorial). The server decides
	when a step is done by looking at the player's real data, e.g. "TotalClicks
	grew by 10 since this step started". The client may only send intents:
	  TutorialSeen     { Step = id }  completes the CURRENT step if it is a "seen" step
	  TutorialSkip     {}             ends the tutorial (no reward)
	  TutorialRestart  {}             replays it from step 1 (reward only once ever)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tutorial = require(Shared.Config.Tutorial)
local Core = script.Parent.Parent.Core
local Net = require(Core.Net)
local Guard = require(Core.Guard)

local TutorialService = { Name = "TutorialService" }

local CHECK_INTERVAL = 0.5

-- The saved counter a "stat" step watches.
local function counter(data, stat: string): number
	if stat == "ObbyCheckpoints" then
		return data.Obby.Checkpoints
	end
	return data.Stats[stat] or 0
end

function TutorialService:Init(services)
	self.Services = services
	Net.registerAction("TutorialSeen", {
		Rate = { Capacity = 4, Refill = 1 },
		Handler = function(profile, payload)
			return self:Seen(profile, payload.Step)
		end,
	})
	Net.registerAction("TutorialSkip", {
		Rate = { Capacity = 2, Refill = 0.2 },
		Handler = function(profile)
			return self:Skip(profile)
		end,
	})
	Net.registerAction("TutorialRestart", {
		Rate = { Capacity = 2, Refill = 0.1 },
		Handler = function(profile)
			return self:Restart(profile)
		end,
	})
end

function TutorialService:Start()
	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)
			for _, profile in pairs(self.Services.DataService.Profiles) do
				if not profile.Data.Tutorial.Done then
					self:Check(profile)
				end
			end
		end
	end)
end

function TutorialService:OnProfileLoaded(profile)
	local state = profile.Data.Tutorial
	if not state.Done and state.Step == 1 and state.Base == 0 then
		self:_begin(profile, 1)
	end
end

-- Starts a step: remembers the watched counter so only NEW progress counts.
function TutorialService:_begin(profile, index: number)
	local state = profile.Data.Tutorial
	local step = Tutorial.Steps[index]
	state.Step = index
	state.Base = if step and step.Kind == "stat" then counter(profile.Data, step.Stat) else 0
	self.Services.SyncService:MarkDirty(profile, "Tutorial")
end

function TutorialService:_complete(profile)
	local state = profile.Data.Tutorial
	local index = state.Step
	if index < #Tutorial.Steps then
		self:_begin(profile, index + 1)
		return
	end
	state.Done = true
	state.Skipped = false
	self.Services.SyncService:MarkDirty(profile, "Tutorial")
	if not state.Rewarded then
		state.Rewarded = true
		self.Services.EconomyService:GrantReward(profile, Tutorial.Reward, "tutorial")
		self.Services.Net.notify(profile.Player, "Toast", { Icon = "🎓", Text = `Tutorial complete! +{Tutorial.Reward.Gems} 💎` })
	else
		self.Services.Net.notify(profile.Player, "Toast", { Icon = "🎓", Text = "Tutorial complete!" })
	end
end

-- Completes the current step if the player really did it.
function TutorialService:Check(profile)
	local state = profile.Data.Tutorial
	local step = Tutorial.Steps[state.Step]
	if state.Done or not step then
		return
	end
	local data = profile.Data
	local done = false
	if step.Kind == "stat" then
		done = counter(data, step.Stat) - state.Base >= step.Amount
	elseif step.Kind == "equip" then
		done = #data.Equipped > 0
	end
	if done then
		self:_complete(profile)
	end
end

function TutorialService:Seen(profile, rawStep: any)
	local state = profile.Data.Tutorial
	local stepId = Guard.id(rawStep, Tutorial.ById)
	local step = Tutorial.Steps[state.Step]
	if state.Done or not stepId or not step or step.Id ~= stepId or step.Kind ~= "seen" then
		-- Only the step that is active right now, and only "look at this" steps.
		return Net.fail("That tutorial step is not active.")
	end
	self:_complete(profile)
	return Net.ok({ Step = profile.Data.Tutorial.Step, Done = profile.Data.Tutorial.Done })
end

function TutorialService:Skip(profile)
	local state = profile.Data.Tutorial
	if state.Done then
		return Net.ok({ Done = true })
	end
	state.Done = true
	state.Skipped = true
	self.Services.SyncService:MarkDirty(profile, "Tutorial")
	return Net.ok({ Done = true })
end

function TutorialService:Restart(profile)
	local state = profile.Data.Tutorial
	state.Done = false
	state.Skipped = false
	self:_begin(profile, 1)
	return Net.ok({ Step = 1 })
end

return TutorialService
