-- Treadmill training and movement speed. Standing on one of your own treadmills trains
-- Speed every tick; WalkSpeed follows the Speed stat (log scale), mount, carry and slow mode.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Formulas = require(Shared.Formulas)
local Map = require(Shared.Config.Map)

local TrainingService = {}

local S

function TrainingService.Init(services)
	S = services
end

local function treadmillUnder(player: Player, hrp: BasePart): number?
	local plot = S.PlotService.plot(player)
	local data = S.DataService.get(player)
	local rt = S.PlayerService.get(player)
	if not plot or not data or not rt then
		return nil
	end
	for tier, tm in pairs(plot.Treadmills) do
		local owned = (tier == 0 and rt.Passes.VIP) or (tier > 0 and tier <= data.Treadmill)
		if owned then
			local localPos = tm.Belt.CFrame:PointToObjectSpace(hrp.Position)
			if math.abs(localPos.X) <= 3.4 and math.abs(localPos.Z) <= 6 and localPos.Y > 0 and localPos.Y < 7 then
				return tier
			end
		end
	end
	return nil
end

function TrainingService.walkSpeedFor(player: Player): number
	local data = S.DataService.get(player)
	if not data then
		return Game.BaseWalkSpeed
	end
	local mountMult = S.MountService.speedMult(player)
	local carryFactor = S.CarryService.speedFactor(player)
	return Formulas.walkSpeed(data.Speed, mountMult, data.SlowMode, carryFactor)
end

function TrainingService.Start()
	local last = os.clock()
	task.spawn(function()
		while true do
			task.wait(Game.TrainTickSeconds)
			local now = os.clock()
			local dt = math.min(now - last, 1)
			last = now
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				local data = S.DataService.get(player)
				if humanoid and hrp and data and humanoid.Health > 0 then
					local tier = treadmillUnder(player, hrp :: BasePart)
					if tier then
						local ctx = S.PlayerService.ctx(player)
						if ctx then
							S.PlayerService.addSpeed(player, Formulas.treadmillGain(ctx, tier) * dt)
						end
						if player:GetAttribute("Treadmill") ~= tier then
							player:SetAttribute("Treadmill", tier)
						end
					elseif player:GetAttribute("Treadmill") ~= nil then
						player:SetAttribute("Treadmill", nil)
					end
					local stunnedUntil = player:GetAttribute("StunnedUntil") or 0
					local ws = TrainingService.walkSpeedFor(player)
					if os.clock() < stunnedUntil then
						ws = 4
					end
					if math.abs(humanoid.WalkSpeed - ws) > 0.05 then
						humanoid.WalkSpeed = ws
					end
					-- remember the farthest zone reached (used by Dragon Lair eggs)
					local zone = Map.zoneAt(hrp.Position.Z)
					if zone and zone > data.MaxZone and math.abs(hrp.Position.X) < Map.Lane.Width then
						data.MaxZone = zone
					end
				end
			end
		end
	end)
end

return TrainingService
