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
-- Ein paar Früchte aufs Band legen (nur fürs Vorschau-Bild; im Spiel macht das der Client)
local L = Config.Layout
local origin = plot:GetAttribute("Origin")
local fruit = Config.Fruits[1]
for i, laneCfg in ipairs(Config.Lanes) do
	local laneCF = origin * roblox.CFrame.new(Config.LaneX(i), 0, 0)
	for z = L.BeltStartZ - 3, L.BeltEndZ + 2, -7 do
		local stage = 0
		for j = 1, 3 do
			if z < L.UpgraderZ[j] then
				stage = j
			end
		end
		local st = laneCfg.Items[stage + 1]
		local part = roblox.Instance.new("Part")
		part.Anchored = true
		part.Name = "PreviewItem"
		local size = st.Size
		if st.Kind == "Ball" then
			part.Shape = roblox.Enum.PartType.Ball
		elseif st.Kind == "Cylinder" or st.Kind == "Coin" then
			part.Shape = roblox.Enum.PartType.Cylinder
		elseif st.Kind == "Egg" then
			local mesh = roblox.Instance.new("SpecialMesh")
			mesh.MeshType = roblox.Enum.MeshType.Sphere
			mesh.Parent = part
		end
		part.Size = size
		part.Color = st.Color == "Fruit" and fruit.Color or st.Color
		part.Material = st.Color == "Fruit" and fruit.Material or st.Material
		local half = (st.Kind == "Cylinder" or st.Kind == "Coin") and size.X / 2 or size.Y / 2
		local cf = laneCF * roblox.CFrame.new(0, L.BeltY + half, z)
		if st.Kind == "Cylinder" or st.Kind == "Coin" then
			cf = cf * roblox.CFrame.Angles(0, 0, math.rad(90))
		elseif st.Kind == "Gem" then
			cf = cf * roblox.CFrame.Angles(math.rad(45), 0, math.rad(45))
		end
		part.CFrame = cf
		part.Parent = plot
	end
end

fs.writeFile(process.args[2], roblox.serializePlace(game))
