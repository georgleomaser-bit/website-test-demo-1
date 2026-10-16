--[[
	Mini-"Roblox" für Tests mit Lune (https://lune-org.github.io).
	Lädt die von Rojo gebaute Place-Datei und kann ModuleScripts daraus
	mit einer Roblox-ähnlichen Umgebung ausführen.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Harness = {}

-- Ganz einfacher Ersatz für Roblox' Random (deterministisch)
local RandomShim = {}
RandomShim.__index = RandomShim
function RandomShim.new(seed)
	return setmetatable({ state = (tonumber(seed) or 1) % 2147483647 }, RandomShim)
end
function RandomShim:_next()
	self.state = (self.state * 48271) % 2147483647
	return self.state / 2147483647
end
function RandomShim:NextNumber(a, b)
	a = a or 0
	b = b or 1
	return a + (b - a) * self:_next()
end
function RandomShim:NextInteger(a, b)
	return math.floor(a + (b - a + 1) * self:_next())
end

function Harness.load(placePath: string)
	local game = roblox.deserializePlace(fs.readFile(placePath))
	local cache = {}
	local env

	local function requireModule(moduleScript)
		if cache[moduleScript] ~= nil then
			return cache[moduleScript]
		end
		assert(moduleScript and moduleScript.ClassName == "ModuleScript", "require: kein ModuleScript: " .. tostring(moduleScript))
		-- Lune kopiert die Umgebung flach (Metatables gehen verloren), daher alles direkt eintragen
		local moduleEnv = { script = moduleScript }
		for key, value in pairs(env) do
			moduleEnv[key] = value
		end
		local chunk = luau.load(moduleScript.Source, {
			environment = moduleEnv,
			debugName = moduleScript:GetFullName(),
		})
		local result = chunk()
		cache[moduleScript] = result
		return result
	end

	env = {
		game = game,
		workspace = game:GetService("Workspace"),
		require = requireModule,
		Instance = roblox.Instance,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Enum = roblox.Enum,
		BrickColor = roblox.BrickColor,
		Font = roblox.Font,
		Rect = roblox.Rect,
		PhysicalProperties = roblox.PhysicalProperties,
		Random = RandomShim,
		task = task,
		tick = os.clock,
		time = os.clock,
		warn = function(...)
			print("[warn]", ...)
		end,
	}

	return {
		game = game,
		require = requireModule,
		env = env,
	}
end

function Harness.find(root, path: string)
	local current = root
	for name in string.gmatch(path, "[^%.]+") do
		local nextChild = current:FindFirstChild(name)
		assert(nextChild, "Nicht gefunden: " .. path .. " (bei " .. name .. ")")
		current = nextChild
	end
	return current
end

return Harness
