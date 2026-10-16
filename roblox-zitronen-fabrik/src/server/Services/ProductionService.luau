--[[
	Die Produktion: Jede Linie läuft in Zyklen. Ohne Manager muss der Spieler
	den roten Knopf drücken, mit Manager läuft sie von allein.
	Am Ende jedes Zyklus wird verkauft und Geld gutgeschrieben.
	(Die Früchte auf dem Band zeigt der Client – passend zu diesen Zeiten.)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Core = require(script.Parent.Core)
local PlotService = require(script.Parent.PlotService)

local ProductionService = {}

function ProductionService.StartLane(session, laneIndex: number): boolean
	if type(laneIndex) ~= "number" then
		return false
	end
	laneIndex = math.floor(laneIndex)
	local lane = session.Profile.Lanes[laneIndex]
	local rt = session.Lanes[laneIndex]
	if not lane or not rt or lane.Level <= 0 then
		return false
	end
	if rt.Running then
		return false
	end
	rt.Running = true
	rt.CycleStart = workspace:GetServerTimeNow()
	session.Profile.Stats.Presses += 1
	Core.WriteLaneState(session, laneIndex)
	Core.Effect(session.Player, "Press", laneIndex)
	return true
end

-- Manager-Linien laufen nach dem Laden/Kaufen sofort los
function ProductionService.InitLanes(session)
	local now = workspace:GetServerTimeNow()
	for i, lane in ipairs(session.Profile.Lanes) do
		local rt = session.Lanes[i]
		if lane.Level > 0 and lane.Manager then
			rt.Running = true
			rt.CycleStart = now
		else
			rt.Running = false
			rt.CycleStart = 0
		end
	end
end

function ProductionService.ResetLanes(session)
	for _, rt in ipairs(session.Lanes) do
		rt.Running = false
		rt.CycleStart = 0
		rt.Revenue = 0
	end
end

local function credit(session, laneIndex: number, cycles: number)
	local rt = session.Lanes[laneIndex]
	local revenue = rt.Revenue
	if revenue <= 0 or cycles <= 0 then
		return
	end
	local chance = session.Stats and session.Stats.GoldenChance or 0
	local total = revenue * cycles
	if chance > 0 then
		if cycles <= 3 then
			local golden = 0
			for _ = 1, cycles do
				if math.random() < chance then
					golden += 1
				end
			end
			if golden > 0 then
				total += revenue * 9 * golden
				session.Profile.Stats.Golden += golden
				Core.Effect(session.Player, "Golden", { Lane = laneIndex, Amount = revenue * 10 })
			end
		else
			-- Sehr schnelle Linien: Durchschnitt statt Würfeln
			total *= 1 + 9 * chance
		end
	end
	Core.AddEarnings(session, total, true)
end

function ProductionService.Init()
	PlotService.PressHandler = function(session, laneIndex)
		local lane = session.Profile.Lanes[laneIndex]
		if lane and lane.Manager then
			Core.Notify(session.Player, "Das macht schon dein Manager für dich! 😎", "info")
			return
		end
		ProductionService.StartLane(session, laneIndex)
	end
	Core.RegisterAction("StartLane", function(session, laneIndex)
		ProductionService.StartLane(session, laneIndex)
	end)
	Core.RegisterAction("StartAll", function(session)
		for i = 1, #Config.Lanes do
			local lane = session.Profile.Lanes[i]
			if lane.Level > 0 and not lane.Manager then
				ProductionService.StartLane(session, i)
			end
		end
	end)
end

function ProductionService.Start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.05 then
			return
		end
		acc = 0
		local now = workspace:GetServerTimeNow()
		for _, session in pairs(Core.Sessions) do
			if session.Loaded then
				for i, rt in ipairs(session.Lanes) do
					if rt.Running and rt.CycleTime > 0 then
						local elapsed = now - rt.CycleStart
						if elapsed >= rt.CycleTime then
							local lane = session.Profile.Lanes[i]
							if lane.Manager then
								local cycles = math.floor(elapsed / rt.CycleTime)
								rt.CycleStart += cycles * rt.CycleTime
								credit(session, i, cycles)
							else
								rt.Running = false
								credit(session, i, 1)
								Core.WriteLaneState(session, i)
							end
						end
					end
				end
			end
		end
	end)
end

ProductionService.Players = Players

return ProductionService
