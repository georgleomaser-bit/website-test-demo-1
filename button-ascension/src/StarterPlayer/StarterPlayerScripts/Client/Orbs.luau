--[[
	Orbs (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Orbs
	Depends on: ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format, Config/Chests},
	            Client/{ClientNet, Notifications}

	Renders bonus orbs offered by the server (OrbSpawn) and claims them.
	The server decides whether a claim is valid and what it is worth.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UIFolder = ReplicatedStorage:WaitForChild("UI")
local UI = require(UIFolder.UIKit)
local Theme = require(UIFolder.Theme)
local Effects = require(UIFolder.Effects)
local SoundPlayer = require(UIFolder.SoundPlayer)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Chests = require(Shared.Config.Chests)

local ClientNet = require(script.Parent.ClientNet)

local C = Theme.Colors
local Orbs = {}

local layer: Frame
local notifications

function Orbs.init(ctx)
	layer = ctx.Layers.Orbs
	notifications = ctx.Notifications
end

local function describe(reward): string
	if reward.Type == "Sparks" then
		return `+{Format.short(reward.Amount)} Sparks`
	elseif reward.Type == "Gems" then
		return `+{Format.short(reward.Amount)} Gems`
	elseif reward.Type == "Chest" then
		local chest = Chests.ById[reward.Chest]
		return if chest then `+1 {chest.Name}` else "+1 crate"
	elseif reward.Type == "Frenzy" then
		return `Frenzy ×{reward.Multiplier} for {reward.Duration}s!`
	end
	return "Bonus!"
end

function Orbs.spawn(info)
	if type(info) ~= "table" or type(info.Id) ~= "number" then
		return
	end
	local lifetime = info.Lifetime or 8
	local orb = UI.new("TextButton", {
		Name = "Orb",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(info.X or 0.5, info.Y or 0.4),
		Size = UDim2.fromOffset(84, 84),
		BackgroundColor3 = C.Accent2,
		AutoButtonColor = false,
		Text = "✨",
		TextSize = 34,
		ZIndex = 50,
		Selectable = true,
		Corner = Theme.Radius.Pill,
		Stroke = { Color = C.White, Thickness = 3, Transparency = 0.2 },
		Parent = layer,
	})
	UI.gradient(orb, {
		Color = ColorSequence.new(Color3.fromRGB(150, 255, 255), Color3.fromRGB(80, 120, 255)),
		Rotation = 45,
	})
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = orb
	UI.tween(scale, { Scale = 1 }, Theme.Motion.Pop, true)
	local timer = UI.new("Frame", {
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 6),
		Size = UDim2.fromOffset(70, 6),
		BackgroundColor3 = C.White,
		ZIndex = 50,
		Corner = Theme.Radius.Pill,
		Parent = orb,
	})
	UI.tween(timer, { Size = UDim2.fromOffset(0, 6) }, TweenInfo.new(lifetime, Enum.EasingStyle.Linear), true)
	SoundPlayer.play("Orb")

	local alive = true
	local born = os.clock()
	local origin = orb.Position
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if not alive then
			connection:Disconnect()
			return
		end
		if not Theme.ReducedMotion then
			local t = os.clock() - born
			orb.Position = origin + UDim2.fromOffset(math.sin(t * 2.3) * 10, math.sin(t * 3.1) * 8)
			orb.Rotation = math.sin(t * 1.7) * 8
		end
	end)

	local function remove()
		alive = false
		local t = UI.tween(scale, { Scale = 0 }, Theme.Motion.Fast, true)
		if t then
			t.Completed:Wait()
		end
		orb:Destroy()
	end

	orb.Activated:Connect(function()
		if not alive then
			return
		end
		alive = false
		local center = orb.AbsolutePosition + orb.AbsoluteSize / 2 - layer.AbsolutePosition
		Effects.burst(layer, center, C.Accent2, 18, 180)
		Effects.ring(layer, center, C.Accent2, 220)
		task.spawn(remove)
		local result = ClientNet.action("ClaimOrb", { Id = info.Id })
		if result.ok and result.Reward then
			SoundPlayer.play("Golden")
			notifications.toast(`<b>Bonus orb!</b> {describe(result.Reward)}`, { Icon = "✨", Color = C.Accent2 })
		else
			notifications.error(result.err)
		end
	end)

	task.delay(lifetime, function()
		if alive then
			remove()
		end
	end)
end

return Orbs
