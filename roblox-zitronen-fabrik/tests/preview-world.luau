--[[
	Baut die Welt + eine voll ausgebaute Fabrik und speichert sie als Place
	(für Vorschau-Bilder). lune run tests/preview-world.luau <place> <ausgabe>
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Harness = require("./harness")

local h = Harness.load(process.args[1])
local game = h.game
local Config = h.require(Harness.find(game, "ReplicatedStorage.Shared.Config"))
local worldFolder = Harness.find(game, "ServerScriptService.Server.World")
local WorldBuilder = h.require(worldFolder.WorldBuilder)
local PlotBuilder = h.require(worldFolder.PlotBuilder)

local world = WorldBuilder.Build(game:GetService("Workspace"), game:GetService("Lighting"))
local plot = world.Plots.Plot1
for i = 1, #Config.Lanes do
	PlotBuilder.BuildLane(plot, i)
	for j = 1, #Config.Lanes[i].Upgraders do
		PlotBuilder.BuildUpgrader(plot, i, j)
	end
end
for k = 1, #Config.Decor do
	PlotBuilder.BuildDecor(plot, k)
end
local plot2 = world.Plots.Plot2
PlotBuilder.BuildLane(plot2, 1)
PlotBuilder.BuildUpgrader(plot2, 1, 1)
PlotBuilder.CreatePad(plot2, "manager_1", Config.Layout.ManagerPadOffset + roblox.Vector3.new(Config.LaneX(1), 0, 0), "🤖 Manager", 2500, "manager", 1)
PlotBuilder.CreatePad(plot2, "unlock_2", roblox.Vector3.new(Config.LaneX(2), 0, Config.Layout.UnlockPadZ), "🚚 Lieferdienst", 75, "unlock", 2)
fs.writeFile(process.args[2], roblox.serializePlace(game))
