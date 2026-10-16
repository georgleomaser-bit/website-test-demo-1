--[[
	🍋 ZITRONEN-FABRIK TYCOON – Client-Start
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
Remotes.Init()

local Client = script.Parent
local State = require(Client.State)
local Sound = require(Client.Sound)
local Effects = require(Client.Effects)
local UI = Client.UI
local HUD = require(UI.HUD)
local Windows = require(UI.Windows)
local FactoryWindow = require(UI.FactoryWindow)
local UpgradesWindow = require(UI.UpgradesWindow)
local RebirthWindow = require(UI.RebirthWindow)
local EvolutionWindow = require(UI.EvolutionWindow)
local MiscWindows = require(UI.MiscWindows)
local Conveyors = require(Client.World.Conveyors)
local PlotVisuals = require(Client.World.PlotVisuals)

State.Init()
HUD.Create()
FactoryWindow.Create()
UpgradesWindow.Create()
RebirthWindow.Create()
EvolutionWindow.Create()
MiscWindows.CreateSettings()
MiscWindows.CreateAdmin()
if MiscWindows.ShopEnabled() then
	MiscWindows.CreateShop()
end

Windows.Start()
HUD.Start()
Effects.Start()
Conveyors.Start()
PlotVisuals.Start()

State.Changed.Event:Connect(function()
	Sound.UpdateMusic()
end)
