--[[
	Obby (ModuleScript)
	Location: ReplicatedStorage/Shared/Config/Obby

	Configuration for the obstacle course next to the plaza. The course itself
	is built by ServerScriptService/Services/ObbyService. Players keep earning
	from auto-presses and passive income while they run it.

	Progress (saved per player, written only by the server):
	  Stage        checkpoints cleared in the current run (0 = not started)
	  Best         furthest stage ever cleared
	  Completions  finished runs
	  Checkpoints  checkpoints reached in total (used by the tutorial)

	Rewards are paid ONLY by the server, in Sparks worth a number of base
	presses (so they keep up with progression) plus Gems for first clears.
]]

local Obby = {}

Obby.StageCount = 15

Obby.StageNames = {
	"First Steps",
	"Stairway",
	"Hot Floor",
	"Tightrope",
	"Ferry",
	"Spinner",
	"Zigzag",
	"Ladder",
	"Elevators",
	"Islands",
	"Double Spin",
	"Leap of Faith",
	"Needle",
	"Lava Ferry",
	"Summit",
}

-- Rewards ---------------------------------------------------------------------------------
Obby.Rewards = {
	-- Sparks for each checkpoint in a run: base press value × presses × stage number.
	CheckpointPresses = 25,
	-- Gems the first time a stage is ever cleared; every 5th stage pays the milestone amount.
	FirstClearGems = 5,
	MilestoneGems = 25,
	-- Finishing a run.
	FinishPresses = 600,
	FinishGems = 10,
	FirstFinishGems = 100,
	-- Extra Gems when the total number of completions reaches these values.
	CompletionMilestones = { [5] = 50, [10] = 100, [25] = 250, [50] = 500 },
}

-- Anti-cheat ---------------------------------------------------------------------------------
Obby.AntiCheat = {
	-- How often the server samples character positions (seconds).
	SampleInterval = 0.1,
	-- A checkpoint only counts if the run from the previous one took at least
	-- distance / MaxTravelSpeed seconds (and never less than MinSegmentSeconds).
	MaxTravelSpeed = 45,
	MinSegmentSeconds = 2,
	-- Moving further than this between two samples (not caused by the server) is
	-- treated as a teleport: progress is ignored for SuspectSeconds and flagged.
	TeleportDistance = 40,
	SuspectSeconds = 4,
	-- Falling this far below your checkpoint sends you back to it.
	VoidDepth = 30,
}

-- The "Go to obby" / "Back to plaza" buttons.
Obby.TeleportRate = { Capacity = 2, Refill = 0.25 }

return Obby
