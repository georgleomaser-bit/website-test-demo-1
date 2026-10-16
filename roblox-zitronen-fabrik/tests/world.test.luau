--[[
	Baut die komplette Welt in Lune (prüft dabei alle Property-Namen und -Typen),
	baut auf einer Fabrik alles aus und prüft Labyrinth & Positionen.

	lune run tests/world.test.luau build/ZitronenFabrikTycoon.rbxlx [bake-ausgabe.rbxlx]
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Harness = require("./harness")
local Vector3 = roblox.Vector3

local placePath = process.args[1] or "build/ZitronenFabrikTycoon.rbxlx"
local h = Harness.load(placePath)
local game = h.game
local Config = h.require(Harness.find(game, "ReplicatedStorage.Shared.Config"))
local worldFolder = Harness.find(game, "ServerScriptService.Server.World")
local WorldBuilder = h.require(worldFolder.WorldBuilder)
local PlotBuilder = h.require(worldFolder.PlotBuilder)

local failures = 0
local function check(name, cond, detail)
	if not cond then
		failures += 1
		print("FEHLER: " .. name .. (detail and (" -> " .. tostring(detail)) or ""))
	end
end

-- Alle BrickColor-Namen im Code müssen echte Namen sein
for _, file in ipairs({ "src/server/World/WorldBuilder.luau", "src/server/World/PlotBuilder.luau" }) do
	local source = fs.readFile(file)
	for name in string.gmatch(source, 'C%("([^"]+)"%)') do
		local ok, bc = pcall(roblox.BrickColor.new, name)
		check("BrickColor " .. name, ok and bc.Name == name, ok and bc.Name or bc)
	end
end
for _, name in ipairs(PlotBuilder.PlotColors) do
	local bc = roblox.BrickColor.new(name)
	check("PlotColor " .. name, bc.Name == name, bc.Name)
end

local workspace = game:GetService("Workspace")
local lighting = game:GetService("Lighting")
local world = WorldBuilder.Build(workspace, lighting)
check("World gebaut", world ~= nil and world.Parent == workspace)

local plots = world:FindFirstChild("Plots")
check("6 Plots", plots and #plots:GetChildren() == Config.MaxPlots)

-- Eine Fabrik komplett ausbauen
local plot = plots:FindFirstChild("Plot1")
for i = 1, #Config.Lanes do
	local lane = PlotBuilder.BuildLane(plot, i)
	check("Lane " .. i, lane and lane.Parent == plot.Lanes)
	for j = 1, #Config.Lanes[i].Upgraders do
		check("Upgrader " .. i .. "." .. j, PlotBuilder.BuildUpgrader(plot, i, j) ~= nil)
	end
	PlotBuilder.CreatePad(plot, "manager_" .. i, Config.Layout.ManagerPadOffset + Vector3.new(Config.LaneX(i), 0, 0), "Manager", 1000, "manager", i)
end
for k = 1, #Config.Decor do
	check("Deko " .. k, PlotBuilder.BuildDecor(plot, k) ~= nil)
end
PlotBuilder.SetOwner(plot, 123, "Tester")
check("Placeholders weg", #plot.Placeholders:GetChildren() == 0)

-- Nichts darf unter/über der Fabrik herausragen, Knöpfe nicht in Gebäuden
local origin = plot:GetAttribute("Origin")
local half = Config.Layout.PlotSize / 2
local partCount = 0
for _, d in ipairs(plot:GetDescendants()) do
	if d:IsA("BasePart") then
		partCount += 1
		local p = origin:PointToObjectSpace(d.CFrame.Position)
		check("innerhalb der Fabrik: " .. d:GetFullName(), math.abs(p.X) <= half + 1 and math.abs(p.Z) <= half + 1, tostring(p))
	end
end
print("Parts in einer voll ausgebauten Fabrik:", partCount)

-- Kauf-Knöpfe dürfen keine Gebäude-Parts schneiden
local function overlaps(a: BasePart, b: BasePart)
	local pa = origin:PointToObjectSpace(a.CFrame.Position)
	local pb = origin:PointToObjectSpace(b.CFrame.Position)
	local sa, sb = a.Size, b.Size
	return math.abs(pa.X - pb.X) < (sa.X + sb.X) / 2 - 0.05 and math.abs(pa.Z - pb.Z) < (sa.Z + sb.Z) / 2 - 0.05 and math.abs(pa.Y - pb.Y) < (sa.Y + sb.Y) / 2 - 0.05
end
local padSpots = {}
for i = 1, #Config.Lanes do
	table.insert(padSpots, Config.Layout.ManagerPadOffset + Vector3.new(Config.LaneX(i), 0, 0))
	for j = 1, 3 do
		table.insert(padSpots, Vector3.new(Config.LaneX(i) + Config.Layout.UpgraderPadX, 0, Config.Layout.UpgraderZ[j]))
	end
	table.insert(padSpots, Vector3.new(Config.LaneX(i), 0, Config.Layout.UnlockPadZ))
end
table.insert(padSpots, Config.Layout.DecorPadPos)
for n, spot in ipairs(padSpots) do
	local pad = PlotBuilder.CreatePad(plot, "test_" .. n, spot, "Test", 1, "test", 0)
	local padPart = pad.Pad
	for _, d in ipairs(plot:GetDescendants()) do
		if d:IsA("BasePart") and d ~= padPart and d.Name ~= "Floor" and d.Name ~= "Base" and d.Name ~= "Ring" and not d:IsDescendantOf(plot.Buttons) and d.Transparency < 1 and d.CanCollide then
			if overlaps(padPart, d) then
				check("Knopf " .. n .. " schneidet " .. d:GetFullName(), false, tostring(origin:PointToObjectSpace(d.CFrame.Position)))
			end
		end
	end
	pad:Destroy()
end

-- Kanalisation: alle Hebel und die Tür vom Start erreichbar
local map = WorldBuilder.SewerMap
local start
local targets = {}
for r, line in ipairs(map) do
	for c = 1, #line do
		local ch = string.sub(line, c, c)
		if ch == "S" then
			start = { r, c }
		elseif ch ~= "#" and ch ~= "." then
			targets[ch] = { r, c }
		end
	end
end
local seen = { [start[1] .. "," .. start[2]] = true }
local queue = { start }
while #queue > 0 do
	local cur = table.remove(queue, 1)
	for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		local r, c = cur[1] + d[1], cur[2] + d[2]
		local line = map[r]
		if line and c >= 1 and c <= #line then
			local ch = string.sub(line, c, c)
			local key = r .. "," .. c
			if ch ~= "#" and not seen[key] then
				seen[key] = true
				if ch ~= "D" then
					table.insert(queue, { r, c })
				end
			end
		end
	end
end
for ch, pos in pairs(targets) do
	check("Kanal erreichbar: " .. ch, seen[pos[1] .. "," .. pos[2]] == true)
end
check("4 Hebel", #world.Sewer.Levers:GetChildren() == 4)

-- Alle Fabriken leeren
PlotBuilder.Clear(plot)
check("Clear: Platzhalter zurück", #plot.Placeholders:GetChildren() == #Config.Lanes)

local total = 0
for _, d in ipairs(world:GetDescendants()) do
	if d:IsA("BasePart") then
		total += 1
	end
end
print("Parts in der leeren Welt:", total)

if process.args[2] then
	fs.writeFile(process.args[2], roblox.serializePlace(game))
	print("Gebackene Welt gespeichert:", process.args[2])
end

if failures > 0 then
	print("Welt-Tests: " .. failures .. " Fehler")
	process.exit(1)
end
print("Welt-Tests: alles ok")
