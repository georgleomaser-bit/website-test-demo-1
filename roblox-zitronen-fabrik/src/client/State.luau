--[[
	Was der Client über den Spieler weiß (kommt vom Server per "Sync").
	Geld kommt schneller über Attribute am Spieler.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer

local State = {}

State.Data = nil :: any
State.Changed = Instance.new("BindableEvent")
State.BuyMode = 1 :: any -- 1, 10, 100 oder "max"

function State.Init()
	Remotes.Get("Sync").OnClientEvent:Connect(function(payload)
		State.Data = payload
		State.Changed:Fire()
	end)
end

function State.Ready(): boolean
	return State.Data ~= nil
end

function State.Cash(): number
	return player:GetAttribute("Cash") or 0
end

function State.Income(): number
	return player:GetAttribute("Income") or 0
end

function State.EvoEarnings(): number
	return player:GetAttribute("EvoEarnings") or 0
end

function State.Plot(): Model?
	if not State.Data or State.Data.PlotIndex == 0 then
		return nil
	end
	local world = workspace:FindFirstChild("World")
	local plots = world and world:FindFirstChild("Plots")
	return plots and plots:FindFirstChild("Plot" .. State.Data.PlotIndex) :: Model?
end

function State.Setting(key: string): boolean
	if not State.Data then
		return true
	end
	return State.Data.Profile.Settings[key] ~= false
end

-- Profil-Ansicht mit aktuellem Geld (für Economy-Funktionen)
function State.ProfileView()
	local data = State.Data
	if not data then
		return nil
	end
	local p = data.Profile
	return {
		Cash = State.Cash(),
		EvoEarnings = State.EvoEarnings(),
		Investors = p.Investors,
		InvestorsSpent = p.InvestorsSpent,
		Evolution = p.Evolution,
		Powers = p.Powers,
		Lanes = p.Lanes,
		Upgrades = p.Upgrades,
		Decor = p.Decor,
		Secrets = p.Secrets,
	}
end

State.Player = player

return State
