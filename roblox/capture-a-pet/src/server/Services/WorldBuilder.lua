-- Builds the whole map from Config/Map at server start: checkered grass hub, six fenced
-- bases with treadmills, pens and nests, the canyon run lane with four zones and the
-- Dragon Lair. Other services read the generated layout from WorldBuilder.World.

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Map = require(Shared.Config.Map)
local Zones = require(Shared.Config.Zones)
local Treadmills = require(Shared.Config.Treadmills)
local Game = require(Shared.Config.Game)
local Format = require(Shared.Format)

local WorldBuilder = {}
WorldBuilder.World = {}

local FONT = Enum.Font.FredokaOne
local GRASS_A = Color3.fromRGB(118, 214, 72)
local GRASS_B = Color3.fromRGB(104, 200, 62)
local PLOT_A = Color3.fromRGB(134, 226, 84)
local PLOT_B = Color3.fromRGB(120, 214, 74)
local WOOD = Color3.fromRGB(176, 104, 60)
local WOOD_DARK = Color3.fromRGB(140, 80, 45)

local rng = Random.new(1337)

local function part(parent: Instance, props)
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = props.Material or Enum.Material.SmoothPlastic
	for key, value in pairs(props) do
		if key ~= "ClassName" and key ~= "Material" then
			(p :: any)[key] = value
		end
	end
	p.Parent = parent
	return p
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function billboard(adornee: BasePart, text: string, size: UDim2, offset: Vector3, color: Color3?, maxDistance: number?)
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.StudsOffsetWorldSpace = offset
	gui.AlwaysOnTop = false
	gui.MaxDistance = maxDistance or 150
	gui.LightInfluence = 0
	gui.Adornee = adornee
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextScaled = true
	label.RichText = true
	label.Text = text
	label.TextColor3 = color or Color3.new(1, 1, 1)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(20, 20, 30)
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = adornee
	return gui, label
end

-- Checkered floor made of tiles, like the reference screenshots.
local function checker(parent: Instance, cf: CFrame, sizeX: number, sizeZ: number, tile: number, colorA: Color3, colorB: Color3, thickness: number?)
	local nx = math.max(1, math.floor(sizeX / tile + 0.5))
	local nz = math.max(1, math.floor(sizeZ / tile + 0.5))
	local tx = sizeX / nx
	local tz = sizeZ / nz
	local h = thickness or 1
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			local x = -sizeX / 2 + tx * (ix + 0.5)
			local z = -sizeZ / 2 + tz * (iz + 0.5)
			part(parent, {
				Name = "Floor",
				Size = Vector3.new(tx, h, tz),
				CFrame = cf * CFrame.new(x, -h / 2, z),
				Color = ((ix + iz) % 2 == 0) and colorA or colorB,
				Material = Enum.Material.SmoothPlastic,
			})
		end
	end
end

local function fenceLine(parent: Instance, from: Vector3, to: Vector3)
	local delta = to - from
	local length = delta.Magnitude
	if length < 1 then
		return
	end
	local dir = delta.Unit
	local posts = math.max(1, math.floor(length / 8))
	for i = 0, posts do
		local pos = from + dir * (length * i / posts)
		part(parent, { Name = "Post", Size = Vector3.new(1.4, 5, 1.4), CFrame = CFrame.new(pos + Vector3.new(0, 2.5, 0)), Color = WOOD_DARK })
	end
	local mid = from + delta / 2
	for _, y in ipairs({ 1.6, 3.6 }) do
		part(parent, {
			Name = "Rail",
			Size = Vector3.new(0.6, 0.9, length),
			CFrame = CFrame.lookAt(mid + Vector3.new(0, y, 0), to + Vector3.new(0, y, 0)),
			Color = WOOD,
		})
	end
	-- diagonal braces for the ranch look
	for i = 0, posts - 1 do
		local a = from + dir * (length * i / posts) + Vector3.new(0, 1.4, 0)
		local b = from + dir * (length * (i + 1) / posts) + Vector3.new(0, 3.8, 0)
		local m = (a + b) / 2
		part(parent, { Name = "Brace", Size = Vector3.new(0.5, 0.7, (b - a).Magnitude), CFrame = CFrame.lookAt(m, b), Color = WOOD })
	end
end

local function bush(parent: Instance, pos: Vector3, size: number)
	local green = Color3.fromRGB(70, 160, 55)
	part(parent, { Name = "Bush", Size = Vector3.new(size * 1.6, size, size), CFrame = CFrame.new(pos + Vector3.new(0, size / 2, 0)), Color = green, Material = Enum.Material.Grass, CanCollide = false })
	part(parent, { Name = "Bush", Size = Vector3.new(size, size * 0.6, size * 0.8), CFrame = CFrame.new(pos + Vector3.new(size * 0.3, size * 1.2, 0)), Color = green:Lerp(Color3.new(0, 0, 0), 0.1), Material = Enum.Material.Grass, CanCollide = false })
end

local function cactus(parent: Instance, pos: Vector3)
	local green = Color3.fromRGB(70, 150, 70)
	local h = rng:NextNumber(5, 10)
	part(parent, { Name = "Cactus", Size = Vector3.new(1.4, h, 1.4), CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)), Color = green, CanCollide = false })
	part(parent, { Name = "Cactus", Size = Vector3.new(2.6, 0.9, 0.9), CFrame = CFrame.new(pos + Vector3.new(1, h * 0.55, 0)), Color = green, CanCollide = false })
	part(parent, { Name = "Cactus", Size = Vector3.new(0.9, 2.4, 0.9), CFrame = CFrame.new(pos + Vector3.new(2, h * 0.55 + 1.2, 0)), Color = green, CanCollide = false })
end

local function crystal(parent: Instance, pos: Vector3, color: Color3)
	local h = rng:NextNumber(4, 11)
	part(parent, {
		Name = "Crystal",
		Size = Vector3.new(2, h, 2),
		CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 3), rng:NextNumber(-0.3, 0.3)),
		Color = color,
		Material = Enum.Material.Glass,
		Transparency = 0.15,
		CanCollide = false,
	})
end

local function lavaRock(parent: Instance, pos: Vector3)
	local s = rng:NextNumber(3, 7)
	part(parent, { Name = "Rock", Size = Vector3.new(s, s * 0.7, s), CFrame = CFrame.new(pos + Vector3.new(0, s * 0.35, 0)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Color = Color3.fromRGB(40, 32, 36), CanCollide = false })
	part(parent, { Name = "Glow", Size = Vector3.new(s * 0.5, 0.2, s * 0.5), CFrame = CFrame.new(pos + Vector3.new(0, s * 0.7 + 0.05, 0)), Color = Color3.fromRGB(255, 110, 30), Material = Enum.Material.Neon, CanCollide = false })
end

local function buildTreadmill(parent: Instance, cf: CFrame, tier: number)
	local def = Treadmills[tier]
	local color = def and def.Color or Color3.fromRGB(255, 215, 0)
	local name = def and (def.Name .. " Treadmill") or "VIP Treadmill"
	local model = Instance.new("Model")
	model.Name = "Treadmill" .. tier
	part(model, { Name = "Base", Size = Vector3.new(8, 1.2, 13), CFrame = cf * CFrame.new(0, 0.6, 0), Color = Color3.fromRGB(55, 58, 66) })
	part(model, { Name = "Trim", Size = Vector3.new(8.2, 0.4, 13.2), CFrame = cf * CFrame.new(0, 1.1, 0), Color = color, Material = Enum.Material.Neon })
	local belt = part(model, { Name = "Belt", Size = Vector3.new(6, 0.5, 11), CFrame = cf * CFrame.new(0, 1.45, 0.5), Color = Color3.fromRGB(30, 30, 34) })
	for i = 0, 5 do
		part(model, {
			Name = "Stripe",
			Size = Vector3.new(5.8, 0.05, 0.4),
			CFrame = cf * CFrame.new(0, 1.72, -4.5 + i * 2 + 0.5),
			Color = Color3.fromRGB(70, 70, 78),
			CanCollide = false,
			CanQuery = false,
		})
	end
	for _, sx in ipairs({ -1, 1 }) do
		part(model, { Name = "Pole", Size = Vector3.new(0.5, 4.5, 0.5), CFrame = cf * CFrame.new(sx * 3.3, 3.4, -5), Color = Color3.fromRGB(200, 200, 210), Material = Enum.Material.Metal })
		part(model, { Name = "Handle", Size = Vector3.new(0.4, 0.4, 5), CFrame = cf * CFrame.new(sx * 3.3, 4.6, -2.6), Color = Color3.fromRGB(200, 200, 210), Material = Enum.Material.Metal })
	end
	local console = part(model, { Name = "Console", Size = Vector3.new(7, 1.6, 1.2), CFrame = cf * CFrame.new(0, 5.6, -5) * CFrame.Angles(math.rad(-25), 0, 0), Color = Color3.fromRGB(45, 45, 55) })
	part(model, { Name = "Screen", Size = Vector3.new(5, 1, 0.2), CFrame = console.CFrame * CFrame.new(0, 0, 0.62), Color = color, Material = Enum.Material.Neon })
	model.PrimaryPart = belt
	model.Parent = parent
	local gui, label = billboard(console, "", UDim2.fromOffset(220, 90), Vector3.new(0, 4.5, 0), Color3.new(1, 1, 1), 90)
	gui.Name = "Info"
	return {
		Tier = tier,
		Model = model,
		Belt = belt,
		Console = console,
		Label = label,
		Name = name,
	}
end

local function buildNest(parent: Instance, cf: CFrame, scale: number)
	local model = Instance.new("Model")
	model.Name = "Nest"
	local twig = Color3.fromRGB(120, 72, 40)
	local twig2 = Color3.fromRGB(150, 95, 55)
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		local r = 3.2 * scale
		part(model, {
			Name = "Twig",
			Size = Vector3.new(0.7 * scale, 0.7 * scale, 3.6 * scale),
			CFrame = cf * CFrame.new(math.cos(a) * r, 0.6 * scale + (i % 2) * 0.4 * scale, math.sin(a) * r) * CFrame.Angles(0, -a, 0.25 * (i % 2 == 0 and 1 or -1)),
			Color = (i % 2 == 0) and twig or twig2,
			CanCollide = false,
		})
	end
	part(model, { Name = "Bed", Size = Vector3.new(5.5 * scale, 0.6 * scale, 5.5 * scale), CFrame = cf * CFrame.new(0, 0.3 * scale, 0), Color = Color3.fromRGB(100, 62, 35), CanCollide = false })
	model.Parent = parent
	return model
end

local function sign(parent: Instance, cf: CFrame, text: string, color: Color3, width: number)
	local board = part(parent, { Name = "Sign", Size = Vector3.new(width, 9, 1), CFrame = cf, Color = WOOD })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = Color3.fromRGB(30, 20, 15)
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = board
	return board, label
end

local function buildPlot(parent: Instance, index: number, center: Vector3)
	local size = Map.Plot.Size
	local facing = center.X < 0 and Vector3.new(1, 0, 0) or Vector3.new(-1, 0, 0)
	-- local -Z points toward the avenue (front of the base)
	local cf = CFrame.lookAt(center, center + facing)
	local model = Instance.new("Model")
	model.Name = "Plot" .. index
	local floor = folder(model, "Floor")
	checker(floor, cf * CFrame.new(0, 0.02, 0), size.X, size.Z, 15, PLOT_A, PLOT_B, 1)

	-- fence with an entrance gap in the front
	local fence = folder(model, "Fence")
	local hx, hz = size.X / 2, size.Z / 2
	local function wp(x, z)
		return (cf * CFrame.new(x, 0, z)).Position
	end
	fenceLine(fence, wp(-hx, -hz), wp(-14, -hz))
	fenceLine(fence, wp(14, -hz), wp(hx, -hz))
	fenceLine(fence, wp(hx, -hz), wp(hx, hz))
	fenceLine(fence, wp(hx, hz), wp(-hx, hz))
	fenceLine(fence, wp(-hx, hz), wp(-hx, -hz))

	-- entrance arch + owner sign
	for _, sx in ipairs({ -1, 1 }) do
		part(model, { Name = "ArchPost", Size = Vector3.new(2, 14, 2), CFrame = cf * CFrame.new(sx * 15, 7, -hz), Color = WOOD_DARK })
	end
	local board, ownerLabel = sign(model, cf * CFrame.new(0, 15, -hz) * CFrame.Angles(0, math.pi, 0), "Empty Base", Color3.fromRGB(255, 255, 255), 30)
	board.Name = "OwnerSign"

	-- treadmills along the back edge (8 tiers + VIP)
	local treadmills = {}
	local tmFolder = folder(model, "Treadmills")
	local count = #Treadmills + 1
	for i = 1, count do
		local x = -((count - 1) * 16) / 2 + (i - 1) * 16
		local tier = i <= #Treadmills and i or 0
		local tcf = cf * CFrame.new(x, 0, hz - 16)
		treadmills[tier] = buildTreadmill(tmFolder, tcf, tier)
	end

	-- pen slots
	local penSlots = {}
	local cols = Map.Plot.PenColumns
	local spacing = Map.Plot.PenSpacing
	for slot = 1, Map.Plot.MaxPenSlots do
		local col = (slot - 1) % cols
		local row = math.floor((slot - 1) / cols)
		local x = -((cols - 1) * spacing) / 2 + col * spacing
		local z = -hz + 34 + row * spacing
		-- animals face the avenue
		penSlots[slot] = cf * CFrame.new(x, 0, z)
	end

	-- incubator nests on the left side
	local incubators = {}
	local incFolder = folder(model, "Nests")
	for i = 1, 6 do
		local icf = cf * CFrame.new(-hx + 9, 0, -hz + 30 + (i - 1) * 19)
		local nest = buildNest(incFolder, icf, 1)
		nest.Name = "Nest" .. i
		incubators[i] = { CFrame = icf, Model = nest }
	end

	-- base lock button near the entrance
	local lockBase = part(model, { Name = "LockPad", Size = Vector3.new(6, 1, 6), CFrame = cf * CFrame.new(24, 0.5, -hz + 8), Color = Color3.fromRGB(60, 60, 70) })
	local lockButton = part(model, { Name = "LockButton", Size = Vector3.new(4, 1, 4), CFrame = cf * CFrame.new(24, 1.3, -hz + 8), Color = Color3.fromRGB(255, 70, 70), Material = Enum.Material.Neon })
	local _, lockLabel = billboard(lockBase, "LOCK BASE", UDim2.fromOffset(160, 50), Vector3.new(0, 4, 0), Color3.new(1, 1, 1), 60)

	-- laser barrier shown while the base is locked (visual only, stealing is blocked server side)
	local barrier = folder(model, "Barrier")
	local function laser(a: Vector3, b: Vector3)
		local m = (a + b) / 2 + Vector3.new(0, 4, 0)
		part(barrier, {
			Name = "Laser",
			Size = Vector3.new(0.4, 8, (b - a).Magnitude),
			CFrame = CFrame.lookAt(m, b + Vector3.new(0, 4, 0)),
			Color = Color3.fromRGB(255, 40, 60),
			Material = Enum.Material.Neon,
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
		})
	end
	laser(wp(-hx, -hz), wp(hx, -hz))
	laser(wp(hx, -hz), wp(hx, hz))
	laser(wp(hx, hz), wp(-hx, hz))
	laser(wp(-hx, hz), wp(-hx, -hz))

	-- invisible region used for "inside my base" checks
	local region = part(model, {
		Name = "Region",
		Size = Vector3.new(size.X, 40, size.Z),
		CFrame = cf * CFrame.new(0, 20, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})

	model.Parent = parent
	return {
		Index = index,
		CFrame = cf,
		Model = model,
		Region = region,
		Treadmills = treadmills,
		PenSlots = penSlots,
		Incubators = incubators,
		LockButton = lockButton,
		LockLabel = lockLabel,
		Barrier = barrier,
		OwnerLabel = ownerLabel,
		Spawn = cf * CFrame.new(0, 4, -hz + 14),
	}
end

local function buildLane(parent: Instance)
	local lane = folder(parent, "Lane")
	local width = Map.Lane.Width
	local wallH = Map.Lane.WallHeight
	local nests = {}
	for zoneIndex, zone in ipairs(Zones) do
		local z0 = Map.zoneStartZ(zoneIndex)
		local len = Map.Lane.ZoneLength
		local zf = folder(lane, "Zone" .. zoneIndex)
		checker(zf, CFrame.new(0, 0.02, z0 + len / 2), width, len, 27.5, zone.Floor, zone.FloorAlt, 1)
		-- walls built from panels in two shades, with a grass/snow/lava rim on top
		for _, sx in ipairs({ -1, 1 }) do
			local panels = math.floor(len / 50)
			for i = 0, panels - 1 do
				local pz = z0 + 25 + i * 50
				part(zf, {
					Name = "Wall",
					Size = Vector3.new(12, wallH, 50),
					CFrame = CFrame.new(sx * (width / 2 + 6), wallH / 2, pz),
					Color = (i % 2 == 0) and zone.Wall or zone.Wall:Lerp(Color3.new(0, 0, 0), 0.07),
				})
			end
			part(zf, {
				Name = "WallTop",
				Size = Vector3.new(14, 3, len),
				CFrame = CFrame.new(sx * (width / 2 + 6), wallH + 1.5, z0 + len / 2),
				Color = zone.WallTop,
				Material = zoneIndex == 4 and Enum.Material.Neon or Enum.Material.SmoothPlastic,
			})
		end
		-- zone gate with the zone name
		for _, sx in ipairs({ -1, 1 }) do
			part(zf, { Name = "GatePost", Size = Vector3.new(4, 30, 4), CFrame = CFrame.new(sx * (width / 2 - 4), 15, z0 + 2), Color = zone.Accent })
		end
		local beam = part(zf, { Name = "GateBeam", Size = Vector3.new(width - 4, 6, 3), CFrame = CFrame.new(0, 31, z0 + 2), Color = zone.Accent })
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Back
		gui.PixelsPerStud = 12
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = FONT
		label.TextScaled = true
		label.Text = zone.Name:upper()
		label.TextColor3 = Color3.new(1, 1, 1)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 4
		stroke.Parent = label
		label.Parent = gui
		gui.Parent = beam

		-- decoration along the walls
		for i = 1, 22 do
			local sx = (i % 2 == 0) and 1 or -1
			local pos = Vector3.new(sx * (width / 2 - rng:NextNumber(3, 9)), 0, z0 + rng:NextNumber(20, len - 20))
			if zoneIndex == 1 then
				bush(zf, pos, rng:NextNumber(3, 6))
			elseif zoneIndex == 2 then
				if i % 3 == 0 then
					bush(zf, pos, rng:NextNumber(3, 5))
				else
					cactus(zf, pos)
				end
			elseif zoneIndex == 3 then
				crystal(zf, pos, Color3.fromRGB(150, 220, 255))
			else
				lavaRock(zf, pos)
			end
		end

		-- guarded nests
		nests[zoneIndex] = {}
		for n = 1, Game.NestsPerZone do
			local side = (n % 2 == 0) and 1 or -1
			local nz = z0 + len * (n / (Game.NestsPerZone + 1))
			local ncf = CFrame.new(side * (width / 2 - 20), 0, nz)
			buildNest(zf, ncf, 1.6)
			nests[zoneIndex][n] = ncf
		end
	end
	-- end wall
	local endZ = Map.zoneStartZ(5)
	part(lane, { Name = "EndWall", Size = Vector3.new(width + 24, wallH, 12), CFrame = CFrame.new(0, wallH / 2, endZ + 6), Color = Zones[4].Wall })
	return nests
end

local function buildLair(parent: Instance)
	local lair = folder(parent, "DragonLair")
	local c = Game.LairCenter
	local size = 230
	checker(lair, CFrame.new(c + Vector3.new(0, 0.02, 0)), size, size, 23, Color3.fromRGB(70, 150, 60), Color3.fromRGB(60, 135, 52), 1)
	-- rock walls and a lava moat
	for _, side in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		local dx, dz = side[1], side[2]
		local wallPos = c + Vector3.new(dx * (size / 2 + 20), 40, dz * (size / 2 + 20))
		local wallSize = dx ~= 0 and Vector3.new(10, 80, size + 50) or Vector3.new(size + 50, 80, 10)
		part(lair, { Name = "Rock", Size = wallSize, CFrame = CFrame.new(wallPos), Color = Color3.fromRGB(45, 38, 40), Material = Enum.Material.Slate })
		local lavaPos = c + Vector3.new(dx * (size / 2 + 8), 0.1, dz * (size / 2 + 8))
		local lavaSize = dx ~= 0 and Vector3.new(14, 1, size + 30) or Vector3.new(size + 30, 1, 14)
		part(lair, { Name = "Lava", Size = lavaSize, CFrame = CFrame.new(lavaPos), Color = Color3.fromRGB(255, 100, 20), Material = Enum.Material.Neon })
	end
	part(lair, { Name = "Ceiling", Size = Vector3.new(size + 60, 4, size + 60), CFrame = CFrame.new(c + Vector3.new(0, 82, 0)), Color = Color3.fromRGB(35, 28, 30), Material = Enum.Material.Slate })
	-- gold piles and torches
	for i = 1, 10 do
		local a = i / 10 * math.pi * 2
		local pos = c + Vector3.new(math.cos(a) * 95, 0, math.sin(a) * 95)
		for _ = 1, 5 do
			local s = rng:NextNumber(3, 6)
			part(lair, {
				Name = "Gold",
				Size = Vector3.new(s, s, s),
				CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-5, 5), s / 2 + rng:NextNumber(0, 3), rng:NextNumber(-5, 5))),
				Color = Color3.fromRGB(255, 190, 50),
				Material = Enum.Material.Foil,
				CanCollide = false,
			})
		end
		local torch = part(lair, { Name = "Torch", Size = Vector3.new(1.2, 10, 1.2), CFrame = CFrame.new(pos + Vector3.new(0, 5, 0) + (c - pos).Unit * 12), Color = WOOD_DARK })
		local fire = Instance.new("Fire")
		fire.Size = 6
		fire.Parent = torch
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 150, 60)
		light.Range = 30
		light.Brightness = 2
		light.Parent = torch
	end
	-- egg pads in rings
	local pads = {}
	for i = 1, Game.LairEggCount do
		local ring = (i % 2 == 0) and 40 or 70
		local a = i / Game.LairEggCount * math.pi * 2
		table.insert(pads, CFrame.new(c + Vector3.new(math.cos(a) * ring, 0, math.sin(a) * ring)))
	end
	-- exit portal
	local exitPos = c + Vector3.new(0, 0, size / 2 - 12)
	local exit = part(lair, { Name = "ExitPortal", Size = Vector3.new(16, 18, 2), CFrame = CFrame.new(exitPos + Vector3.new(0, 9, 0)), Color = Color3.fromRGB(80, 255, 140), Material = Enum.Material.Neon, Transparency = 0.3, CanCollide = false })
	billboard(exit, "EXIT", UDim2.fromOffset(160, 50), Vector3.new(0, 12, 0), Color3.new(1, 1, 1))
	return {
		Center = c,
		Size = size,
		Pads = pads,
		Exit = exit,
		Spawn = CFrame.new(c + Vector3.new(0, 4, size / 2 - 30)) * CFrame.Angles(0, 0, 0),
	}
end

local function buildBoard(parent: Instance, cf: CFrame, title: string)
	local board = part(parent, { Name = title .. "Board", Size = Vector3.new(26, 32, 1.5), CFrame = cf * CFrame.new(0, 18, 0), Color = Color3.fromRGB(35, 40, 70) })
	for _, sx in ipairs({ -1, 1 }) do
		part(parent, { Name = "Leg", Size = Vector3.new(1.5, 18, 1.5), CFrame = cf * CFrame.new(sx * 11, 1, 0), Color = Color3.fromRGB(25, 28, 50) })
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 20
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.LightInfluence = 0
	local list = Instance.new("Frame")
	list.Name = "List"
	list.Size = UDim2.fromScale(1, 1)
	list.BackgroundTransparency = 1
	list.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = list
	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.LayoutOrder = 0
	header.Size = UDim2.new(1, 0, 0, 70)
	header.BackgroundTransparency = 1
	header.Font = FONT
	header.TextScaled = true
	header.Text = title
	header.TextColor3 = Color3.fromRGB(255, 220, 80)
	header.Parent = list
	gui.Parent = board
	return list
end

function WorldBuilder.Init(_services)
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.6
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 160)
	Lighting.Ambient = Color3.fromRGB(110, 110, 120)
	Lighting.GlobalShadows = true
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.25
		atmosphere.Color = Color3.fromRGB(200, 225, 255)
		atmosphere.Decay = Color3.fromRGB(150, 190, 255)
		atmosphere.Parent = Lighting
	end

	local old = Workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	local mapFolder = folder(Workspace, "Map")
	local hub = folder(mapFolder, "Hub")

	-- hub ground
	checker(hub, CFrame.new(Map.Hub.Center), Map.Hub.Size.X, Map.Hub.Size.Z, 28, GRASS_A, GRASS_B, 2)
	-- avenue
	part(hub, {
		Name = "Avenue",
		Size = Vector3.new(60, 0.2, Map.Hub.Size.Z),
		CFrame = CFrame.new(Map.Hub.Center + Vector3.new(0, 0.1, 0)),
		Color = Color3.fromRGB(225, 205, 160),
		CanCollide = false,
	})
	-- hub border walls (the reference has terracotta walls with grass on top)
	local hs = Map.Hub.Size
	local hc = Map.Hub.Center
	for _, data in ipairs({
		{ Vector3.new(hs.X / 2 + 6, 20, 0), Vector3.new(12, 40, hs.Z) },
		{ Vector3.new(-hs.X / 2 - 6, 20, 0), Vector3.new(12, 40, hs.Z) },
		{ Vector3.new(0, 20, -hs.Z / 2 - 6), Vector3.new(hs.X + 24, 40, 12) },
	}) do
		part(hub, { Name = "HubWall", Size = data[2], CFrame = CFrame.new(hc + data[1]), Color = Color3.fromRGB(205, 120, 95) })
		part(hub, { Name = "HubWallTop", Size = data[2] + Vector3.new(2, -38, 2), CFrame = CFrame.new(hc + data[1] + Vector3.new(0, 21, 0)), Color = GRASS_A })
	end
	-- front wall pieces left and right of the lane entrance
	local frontZ = hc.Z + hs.Z / 2 + 6
	local sideWidth = (hs.X - Map.Lane.Width) / 2
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (Map.Lane.Width / 2 + sideWidth / 2)
		part(hub, { Name = "HubWall", Size = Vector3.new(sideWidth + 12, 40, 12), CFrame = CFrame.new(x, 20, frontZ), Color = Color3.fromRGB(205, 120, 95) })
		part(hub, { Name = "HubWallTop", Size = Vector3.new(sideWidth + 14, 2, 14), CFrame = CFrame.new(x, 41, frontZ), Color = GRASS_A })
	end
	-- bushes along the hub edges, kept out of the bases and the avenue
	for _ = 1, 30 do
		local x = rng:NextNumber(-hs.X / 2 + 10, hs.X / 2 - 10)
		local z = rng:NextNumber(hc.Z - hs.Z / 2 + 10, hc.Z + hs.Z / 2 - 10)
		if math.abs(x) > 225 or (math.abs(x) > 32 and math.abs(x) < 38) then
			bush(hub, Vector3.new(x, 0, z), rng:NextNumber(3, 6))
		end
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(Map.Hub.Spawn - Vector3.new(0, 2.5, 0))
	spawn.Color = Color3.fromRGB(255, 220, 90)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = hub
	local spawnDecal = spawn:FindFirstChildOfClass("Decal")
	if spawnDecal then
		spawnDecal:Destroy()
	end

	-- bases
	local plots = {}
	local plotsFolder = folder(mapFolder, "Plots")
	for index, center in ipairs(Map.Plot.Centers) do
		plots[index] = buildPlot(plotsFolder, index, center)
	end

	-- lane
	local nests = buildLane(mapFolder)

	-- Dragon Lair and its portal at the far end of the hub
	local lair = buildLair(mapFolder)
	local portalPos = Vector3.new(0, 0, hc.Z - hs.Z / 2 + 30)
	local portalFrame = part(hub, { Name = "LairPortalFrame", Size = Vector3.new(24, 26, 3), CFrame = CFrame.new(portalPos + Vector3.new(0, 13, -1)), Color = Color3.fromRGB(45, 30, 35) })
	local portal = part(hub, { Name = "LairPortal", Size = Vector3.new(18, 20, 1), CFrame = CFrame.new(portalPos + Vector3.new(0, 11, 1)), Color = Color3.fromRGB(255, 90, 30), Material = Enum.Material.Neon, Transparency = 0.25, CanCollide = false })
	local _, portalLabel = billboard(portalFrame, "DRAGON LAIR", UDim2.fromOffset(300, 90), Vector3.new(0, 18, 0), Color3.fromRGB(255, 140, 60), 300)

	-- leaderboards near the lane entrance
	local boards = {
		Cash = buildBoard(hub, CFrame.new(-75, 0, hc.Z + hs.Z / 2 - 40) * CFrame.Angles(0, math.pi, 0), "Top Cash"),
		Speed = buildBoard(hub, CFrame.new(75, 0, hc.Z + hs.Z / 2 - 40) * CFrame.Angles(0, math.pi, 0), "Top Speed"),
	}

	WorldBuilder.World = {
		Folder = mapFolder,
		Plots = plots,
		Nests = nests,
		Lair = lair,
		LairPortal = portal,
		LairPortalLabel = portalLabel,
		Boards = boards,
	}
	WorldBuilder.billboard = billboard
	WorldBuilder.part = part
	WorldBuilder.buildNest = buildNest
	WorldBuilder.Format = Format
end

function WorldBuilder.Start() end

return WorldBuilder
