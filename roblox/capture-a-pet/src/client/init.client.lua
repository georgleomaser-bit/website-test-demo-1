-- Capture a Pet: client entry point. Builds the UI and effects, then waits for the first
-- state from the server.

local Players = game:GetService("Players")

local State = require(script:WaitForChild("State"))
local UI = script:WaitForChild("UI")
local Windows = require(UI:WaitForChild("Windows"))
local Feed = require(UI:WaitForChild("Feed"))
local HUD = require(UI:WaitForChild("HUD"))

Windows.screen()
Feed.init()
require(UI:WaitForChild("ShopWindow")).init()
require(UI:WaitForChild("IndexWindow")).init()
require(UI:WaitForChild("PetsWindow")).init()
require(UI:WaitForChild("RewardWindows")).init()
require(UI:WaitForChild("AdminWindow")).init()
HUD.init()
require(script:WaitForChild("Effects")).init()

-- loading hint until the save is loaded
local player = Players.LocalPlayer
if not State.ready() then
	Feed.notify("Loading your animals...", "info")
end
local function welcome()
	Feed.notify("Welcome to Capture a Pet, " .. player.DisplayName .. "!", "reward")
end
if State.ready() then
	welcome()
else
	State.Changed:Once(welcome)
end
if State.ready() then
	HUD.refresh()
end
