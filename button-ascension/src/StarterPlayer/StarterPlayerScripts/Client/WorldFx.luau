--[[
	WorldFx (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/WorldFx
	Depends on: ReplicatedStorage/Shared/{Formulas, Config/GameConfig}, Client/State

	Local-only effects on the 3D giant button in Workspace.Arena:
	  * it dips every time you press,
	  * its glow follows the whole server's presses per second (ServerCPS),
	  * it takes the colour of YOUR current stage.
	Nothing here replicates; every client sees its own view.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared.Formulas)

local State = require(script.Parent.State)

local WorldFx = {}

function WorldFx.init(ctx)
	task.spawn(function()
		local arena = workspace:WaitForChild("Arena", 30)
		local button = arena and arena:WaitForChild("GiantButton", 10)
		local cap = button and button:WaitForChild("Cap", 10)
		if not cap or not cap:IsA("BasePart") then
			return
		end
		local rim = button:FindFirstChild("Rim")
		local ring = arena:FindFirstChild("NeonRing")
		local light = cap:FindFirstChildOfClass("PointLight")
		local baseCFrame = cap.CFrame
		local pressInfo = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local releaseInfo = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

		ctx.BigButton.Pressed.Event:Connect(function()
			local down = TweenService:Create(cap, pressInfo, { CFrame = baseCFrame * CFrame.new(-0.7, 0, 0) })
			down.Completed:Connect(function()
				TweenService:Create(cap, releaseInfo, { CFrame = baseCFrame }):Play()
			end)
			down:Play()
		end)

		local serverState = ReplicatedStorage:WaitForChild("ServerState", 30)
		if serverState and light then
			serverState:GetAttributeChangedSignal("ServerCPS"):Connect(function()
				local cps = serverState:GetAttribute("ServerCPS") or 0
				TweenService:Create(light, TweenInfo.new(0.8), { Brightness = 1.5 + math.min(cps, 80) / 16 }):Play()
			end)
		end

		local currentStage = 0
		local function applyStage()
			local stage = Formulas.stageFor(State.progress().Rebirths)
			if stage.Id == currentStage then
				return
			end
			currentStage = stage.Id
			cap.Color = stage.Accent
			if light then
				light.Color = stage.Accent
			end
			if rim and rim:IsA("BasePart") then
				rim.Color = stage.Accent
			end
			if ring then
				for _, segment in ipairs(ring:GetChildren()) do
					if segment:IsA("BasePart") then
						segment.Color = stage.Accent
					end
				end
			end
		end
		State.subscribe("Progress", applyStage)
		State.onReady(applyStage)
	end)
end

return WorldFx
