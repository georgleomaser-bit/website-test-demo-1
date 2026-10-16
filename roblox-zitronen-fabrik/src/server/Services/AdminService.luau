--[[
	Test-Menü für dich als Entwickler (nur in Roblox Studio, für den
	Spiel-Ersteller oder für IDs in Config.AdminUserIds).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local Core = require(script.Parent.Core)
local EventService = require(script.Parent.EventService)
local PlotService = require(script.Parent.PlotService)
local ProductionService = require(script.Parent.ProductionService)

local AdminService = {}

local commands = {}

function commands.cash(session)
	local amount = math.max(1e6, session.Profile.Cash * 1000)
	Core.AddEarnings(session, amount)
	Core.Notify(session.Player, "🛠️ +" .. Format.Cash(amount), "info")
end

function commands.investors(session)
	local add = math.max(100, session.Profile.Investors * 9)
	session.Profile.Investors += add
	Core.RecomputeStats(session)
	Core.Notify(session.Player, "🛠️ +" .. Format.Number(add) .. " Investoren", "info")
end

function commands.event(session)
	EventService.Begin(nil)
	Core.Notify(session.Player, "🛠️ Event gestartet", "info")
end

function commands.daily(session)
	session.Profile.Daily.LastDay = 0
	session.Profile.ObbyLast = 0
	Core.MarkDirty(session)
	Core.Notify(session.Player, "🛠️ Tägliche Belohnung & Obby zurückgesetzt", "info")
end

function commands.reset(session)
	local fresh = Economy.NewProfile()
	fresh.Settings = session.Profile.Settings
	session.Profile = fresh
	ProductionService.ResetLanes(session)
	PlotService.BuildFromProfile(session)
	Core.RecomputeStats(session)
	PlotService.TeleportHome(session)
	Core.Notify(session.Player, "🛠️ Spielstand zurückgesetzt", "info")
end

function AdminService.Init()
	Core.RegisterAction("Admin", function(session, command)
		if not Core.IsAdmin(session.Player) or type(command) ~= "string" then
			return
		end
		local fn = commands[command]
		if fn then
			fn(session)
		end
	end)
end

return AdminService
