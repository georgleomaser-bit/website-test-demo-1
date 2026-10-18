--[[
	ObbyClient (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/ObbyClient
	Depends on: ReplicatedStorage/Shared/Config/Obby, ReplicatedStorage/UI/Theme, Client/State

	Local-only look of the obby: checkpoints you have already cleared in your
	current run turn green, the next one pulses. Nothing here replicates or
	affects progress (the server decides that, see ObbyService).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ObbyConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Obby"))
local Theme = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Theme"))
local State = require(script.Parent.State)

local ObbyClient = {}

local CLEARED = Color3.fromRGB(74, 222, 128)
local AHEAD = Color3.fromRGB(77, 225, 255)
local NEXT = Color3.fromRGB(255, 255, 255)

function ObbyClient.init(_ctx)
	task.spawn(function()
		local model = workspace:WaitForChild("Obby", 60)
		if not model then
			return
		end
		local pads = {}
		for stage = 1, ObbyConfig.StageCount - 1 do
			local pad = model:WaitForChild("Checkpoint" .. stage, 10)
			if pad and pad:IsA("BasePart") then
				pads[stage] = pad
			end
		end
		local pulse: Tween? = nil
		local function apply()
			local obby = State.get("Obby")
			local stage = if obby then obby.Stage else 0
			if pulse then
				pulse:Cancel()
				pulse = nil
			end
			for index, pad in pairs(pads) do
				pad.Color = if index <= stage then CLEARED else AHEAD
			end
			local nextPad = pads[stage + 1]
			if nextPad then
				nextPad.Color = NEXT
				if Theme.ReducedMotion then
					return
				end
				pulse = TweenService:Create(nextPad, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Color = AHEAD })
				pulse:Play()
			end
		end
		State.subscribe("Obby", apply)
		State.onReady(apply)
	end)
end

return ObbyClient
