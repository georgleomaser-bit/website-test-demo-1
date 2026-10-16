--[[
	Rebirth (Alien-Investoren von Zorp), Alien-Kräfte und Frucht-Evolution.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local Core = require(script.Parent.Core)
local PlotService = require(script.Parent.PlotService)
local ProductionService = require(script.Parent.ProductionService)

local PrestigeService = {}

local function resetFactory(session)
	local profile = session.Profile
	for i = 1, #Config.Lanes do
		profile.Lanes[i] = { Level = 0, Manager = false, Upgraders = 0 }
	end
	profile.Upgrades = {}
	profile.Decor = 0
	ProductionService.ResetLanes(session)
	PlotService.BuildFromProfile(session)
	Core.RecomputeStats(session)
	PlotService.RefreshPads(session)
	PlotService.TeleportHome(session)
end

function PrestigeService.Rebirth(session)
	local profile = session.Profile
	local claim = Economy.ClaimableInvestors(profile)
	if claim < Config.Rebirth.MinInvestors then
		local need = Economy.EarningsForInvestors(profile.Investors + profile.InvestorsSpent + 1) - profile.EvoEarnings
		Core.Notify(session.Player, "Zorp: \"Noch keine Investoren für dich! Verdiene noch " .. Format.Cash(need) .. ".\"", "error")
		return
	end
	profile.Investors += claim
	profile.Stats.Rebirths += 1
	profile.Cash = Economy.StartCashAfterRebirth(profile)
	session.CashDirty = true
	resetFactory(session)
	local bonus = session.Stats.InvestorMult
	Core.Effect(session.Player, "Rebirth", { Investors = claim, Total = profile.Investors, Bonus = bonus })
	Core.NotifyAll("🛸 " .. session.Player.DisplayName .. " hat Rebirth gemacht und " .. Format.Number(claim) .. " Alien-Investoren bekommen!", "gold")
end

function PrestigeService.BuyPower(session, id: any)
	if type(id) ~= "string" then
		return
	end
	local power = Config.PowerById[id]
	if not power then
		return
	end
	local profile = session.Profile
	local level = Economy.PowerLevel(profile, id)
	if level >= power.Max then
		Core.Notify(session.Player, power.Name .. " ist schon auf Maximum!", "info")
		return
	end
	local cost = Economy.PowerCost(power, level)
	if profile.Investors < cost then
		Core.Notify(session.Player, "Du brauchst " .. Format.Number(cost) .. " Investoren für " .. power.Name .. ".", "error")
		Core.Effect(session.Player, "Error")
		return
	end
	profile.Investors -= cost
	profile.InvestorsSpent += cost
	profile.Powers[id] = level + 1
	Core.RecomputeStats(session)
	PlotService.RefreshPads(session)
	Core.Notify(session.Player, power.Emoji .. " " .. power.Name .. " ist jetzt Stufe " .. (level + 1) .. "!", "success")
	Core.Effect(session.Player, "Purchase")
end

function PrestigeService.Evolve(session)
	local profile = session.Profile
	if profile.Evolution >= #Config.Fruits - 1 then
		Core.Notify(session.Player, "Du hast schon die letzte Frucht! 🌌", "info")
		return
	end
	if not Economy.CanEvolve(profile) then
		Core.Notify(session.Player, "Du brauchst " .. Format.Number(Economy.EvolutionRequirement(profile.Evolution)) .. " Investoren insgesamt für die Evolution.", "error")
		Core.Effect(session.Player, "Error")
		return
	end
	local tier = profile.Evolution + 1
	profile.Evolution = tier
	profile.Investors = 0
	profile.InvestorsSpent = 0
	profile.Powers = {}
	profile.EvoEarnings = 0
	profile.Cash = Config.StartCash
	profile.Stats.Evolutions += 1
	session.CashDirty = true
	resetFactory(session)
	local fruit = Config.Fruits[tier + 1]
	Core.Effect(session.Player, "Evolve", { Tier = tier, Fruit = fruit.Name, Emoji = fruit.Emoji })
	Core.NotifyAll("🌀 " .. session.Player.DisplayName .. " hat sich zur " .. fruit.Emoji .. " " .. fruit.Name .. " entwickelt!", "gold")
end

function PrestigeService.Init()
	Core.RegisterAction("Rebirth", PrestigeService.Rebirth)
	Core.RegisterAction("BuyPower", PrestigeService.BuyPower)
	Core.RegisterAction("Evolve", PrestigeService.Evolve)
end

return PrestigeService
