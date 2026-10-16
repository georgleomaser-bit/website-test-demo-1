--[[
	"Backt" die Welt in die Place-Datei, damit man in Roblox Studio die
	Insel, die Lobby und alle Fabriken schon im Editor sieht.

	lune run tools/bake.luau <rojo-place.rbxlx> <ausgabe.rbxl>
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Harness = require("../tests/harness")

local input = process.args[1]
local output = process.args[2]
assert(input and output, "Aufruf: lune run tools/bake.luau <eingabe> <ausgabe>")

local h = Harness.load(input)
local game = h.game
local WorldBuilder = h.require(Harness.find(game, "ServerScriptService.Server.World.WorldBuilder"))

local existing = game:GetService("Workspace"):FindFirstChild("World")
if existing then
	existing:Destroy()
end
WorldBuilder.Build(game:GetService("Workspace"), game:GetService("Lighting"))

fs.writeFile(output, roblox.serializePlace(game))
print("Welt gebacken:", output)
