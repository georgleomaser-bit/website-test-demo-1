-- Builds the blocky (voxel style) animal models from the Look recipe in Config/Animals.
-- Models face -Z, stand on the ground at their pivot and are fully anchored.
-- A custom Model in ReplicatedStorage.AnimalModels named like the animal replaces the recipe.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = script.Parent
local Animals = require(Shared.Config.Animals)
local Game = require(Shared.Config.Game)

local AnimalModel = {}

local BLACK = Color3.fromRGB(25, 25, 30)
local WHITE = Color3.fromRGB(255, 255, 255)
local HORN_DARK = Color3.fromRGB(110, 20, 40)
local IVORY = Color3.fromRGB(250, 245, 225)
local GOLD = Color3.fromRGB(255, 205, 60)

local function block(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

-- Smooth ellipsoid filling the part's box (a sphere SpecialMesh with scale 1 follows Size,
-- so Model:ScaleTo keeps the proportions).
local function ball(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?)
	local p = block(model, name, size, cf, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Point on the surface of an ellipsoid (center c, half sizes r) in direction dir, as a CFrame
-- whose -Z (LookVector) points out of the surface.
local function onSurface(c: Vector3, r: Vector3, dir: Vector3, inset: number?): CFrame
	local t = 1 / math.sqrt((dir.X / r.X) ^ 2 + (dir.Y / r.Y) ^ 2 + (dir.Z / r.Z) ^ 2)
	local p = c + dir * t
	local n = Vector3.new(dir.X * t / (r.X * r.X), dir.Y * t / (r.Y * r.Y), dir.Z * t / (r.Z * r.Z)).Unit
	p -= n * (inset or 0)
	return CFrame.lookAt(p, p + n)
end

local function custom(speciesId: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("AnimalModels")
	local template = folder and folder:FindFirstChild(speciesId)
	if template and template:IsA("Model") then
		local m = template:Clone()
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		end
		local bbCf, size = m:GetBoundingBox()
		local bottom = bbCf * CFrame.new(0, -size.Y / 2, 0)
		local root = Instance.new("Part")
		root.Name = "Root"
		root.Size = Vector3.new(1, 1, 1)
		root.Transparency = 1
		root.Anchored = true
		root.CanCollide = false
		root.CanQuery = false
		root.CanTouch = false
		root.CFrame = bottom * CFrame.new(0, 0.5, 0)
		root.Parent = m
		m.PrimaryPart = root
		m.WorldPivot = bottom
		m:SetAttribute("Height", size.Y)
		return m
	end
	return nil
end

-- Builds the recipe at scale 1 around the origin; scaled afterwards with Model:ScaleTo.
-- Cute chibi style: smooth round shapes, a big head with huge glossy eyes, stubby legs,
-- light belly and claws. Dragons get segmented horns, a crest, diamond scales and a spiky tail.
local function buildRecipe(model: Model, look)
	local body = look.Body
	local accent = look.Accent
	local dark = body:Lerp(BLACK, 0.4)
	local skeleton = look.Skeleton
	local dragon = look.Wings or look.Tail == "spiked"
	local light = (look.Stripes or look.Spots or dragon) and body:Lerp(WHITE, 0.55) or accent
	if look.Panda or look.Fluffy then
		light = body:Lerp(WHITE, 0.3)
	end
	local horn = look.HornColor or (dragon and body:Lerp(WHITE, 0.6)) or IVORY
	local iris = look.Eye or (dragon and body:Lerp(BLACK, 0.25)) or Color3.fromRGB(70, 45, 30)
	local fierce = look.Horns == "oni" or look.Horns == "bull" or skeleton or look.Fire
	local mat = look.Shiny and Enum.Material.Glass or nil

	local legH = (look.Legs == "short" and 0.8) or (look.Legs == "long" and 1.9) or 1.15
	local bw, bh, bl = 2.7, 2.5, 3.4
	local hw, hh, hd = 3.3, 3.0, 2.9
	if look.Bulky then
		bw, bh, bl = 3.4, 3.0, 3.9
		hw, hh, hd = 3.7, 3.25, 3.15
	end
	local bodyY = legH + bh * 0.42
	local bodyC = Vector3.new(0, bodyY, 0)
	local bodyR = Vector3.new(bw, bh, bl) / 2
	local bodyTop = bodyY + bh / 2

	-- body and belly
	local torso = ball(model, "Body", Vector3.new(bw, bh, bl), CFrame.new(bodyC), body, mat)
	if look.Shiny then
		torso.Transparency = 0.05
	end
	ball(model, "Belly", Vector3.new(bw * 0.72, bh * 0.82, bl * 0.72), CFrame.new(0, bodyY - bh * 0.08, -bl * 0.17), skeleton and accent or light)
	if look.Panda then
		ball(model, "Band", Vector3.new(bw + 0.08, bh * 0.9, bl * 0.36), CFrame.new(0, bodyY + 0.05, -bl * 0.22), accent)
	end
	if look.Hump then
		ball(model, "Hump", Vector3.new(bw * 0.6, 1.5, bl * 0.45), CFrame.new(0, bodyTop - 0.15, 0.25), body)
	end
	if look.Fluffy then
		local wool = body:Lerp(WHITE, 0.12)
		for _, d in ipairs({ { 0, 1, -0.4 }, { 0, 1, 0.5 }, { 0.8, 0.6, 0 }, { -0.8, 0.6, 0 }, { 0.9, 0.2, 0.7 }, { -0.9, 0.2, 0.7 }, { 0.9, 0.2, -0.7 }, { -0.9, 0.2, -0.7 }, { 0, 0.7, 1.1 } }) do
			local cf = onSurface(bodyC, bodyR, Vector3.new(d[1], d[2], d[3]))
			ball(model, "Fluff", Vector3.new(1.4, 1.4, 1.4), cf, wool)
		end
	end
	if look.Stripes then
		for _, d in ipairs({ { 1, 0.3, -0.5 }, { 1, 0.35, 0.15 }, { 1, 0.3, 0.75 }, { 0.3, 1, 0.1 }, { 0.3, 1, 0.7 } }) do
			for _, sx in ipairs({ -1, 1 }) do
				local cf = onSurface(bodyC, bodyR, Vector3.new(d[1] * sx, d[2], d[3]), 0.06)
				ball(model, "Stripe", Vector3.new(0.32, 1.4, 0.2), cf * CFrame.Angles(0, 0, sx * 0.25), accent)
			end
		end
	end
	if look.Spots then
		for _, d in ipairs({ { 1, 0.3, -0.4 }, { 1, -0.2, 0.5 }, { -1, 0.25, 0.1 }, { -1, -0.25, -0.6 }, { 0.2, 1, 0.4 }, { -0.4, 1, -0.3 } }) do
			local cf = onSurface(bodyC, bodyR, Vector3.new(d[1], d[2], d[3]), 0.08)
			ball(model, "Spot", Vector3.new(0.65, 0.55, 0.25), cf, accent)
		end
	end
	if skeleton then
		for i = -1, 1 do
			for _, sx in ipairs({ -1, 1 }) do
				local cf = onSurface(bodyC, bodyR, Vector3.new(sx, 0.35, i * 0.45), 0.05)
				ball(model, "Rib", Vector3.new(0.25, 1.5, 0.22), cf * CFrame.Angles(0, 0, sx * 0.3), accent)
			end
		end
	end
	if dragon or look.Scales then
		-- diamond scales on back and flanks
		for _, d in ipairs({ { 0.55, 0.75, -0.3 }, { -0.55, 0.75, 0.1 }, { 0.6, 0.5, 0.55 }, { -0.7, 0.35, -0.45 }, { 0.85, 0.1, 0.0 }, { -0.85, 0.05, 0.6 } }) do
			local cf = onSurface(bodyC, bodyR, Vector3.new(d[1], d[2], d[3]), 0.03)
			block(model, "Scale", Vector3.new(0.38, 0.38, 0.1), cf * CFrame.Angles(0, 0, math.pi / 4), body:Lerp(BLACK, 0.18))
		end
	end

	-- stubby legs, round paws and claws
	local legColor = look.Panda and accent or body
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local x = sx * bw * 0.3
			local z = sz * bl * 0.27
			ball(model, "Leg", Vector3.new(1.15, legH + 1.0, 1.15), CFrame.new(x, (legH + 1.0) / 2 + 0.1, z), legColor)
			ball(model, "Paw", Vector3.new(1.35, 0.75, 1.55), CFrame.new(x, 0.37, z - 0.12), legColor)
			for c = -1, 1 do
				ball(model, "Claw", Vector3.new(0.3, 0.32, 0.42), CFrame.new(x + c * 0.36, 0.17, z - 0.85) * CFrame.Angles(-0.3, 0, 0), dragon and horn or light:Lerp(WHITE, 0.4))
			end
		end
	end

	-- neck + head
	local headY = bodyTop + hh * 0.28
	local headZ = -bl * 0.42
	if look.LongNeck then
		for i = 0, 2 do
			ball(model, "Neck", Vector3.new(1.5 - i * 0.1, 1.6, 1.5 - i * 0.1), CFrame.new(0, bodyTop - 0.2 + i * 0.85, -bl * 0.32 - i * 0.12), body)
		end
		headY = bodyTop + 2.4 + hh * 0.2
		headZ = -bl * 0.5
	end
	local headC = Vector3.new(0, headY, headZ)
	local headR = Vector3.new(hw, hh, hd) / 2
	ball(model, "Head", Vector3.new(hw, hh, hd), CFrame.new(headC), body, mat)
	local headTop = headY + hh / 2
	local top = headTop

	-- muzzle
	local snout = look.Snout or "short"
	local muzzleC = Vector3.new(0, headY - hh * 0.2, headZ - hd * 0.36)
	local muzzleR = Vector3.new(hw * 0.29, hh * 0.21, hd * 0.24)
	if snout == "long" then
		muzzleC = Vector3.new(0, headY - hh * 0.2, headZ - hd * 0.46)
		muzzleR = Vector3.new(hw * 0.27, hh * 0.21, hd * 0.34)
	elseif snout == "flat" then
		muzzleR = Vector3.new(hw * 0.2, hh * 0.14, hd * 0.2)
	elseif snout == "pig" then
		muzzleC = Vector3.new(0, headY - hh * 0.18, headZ - hd * 0.44)
		muzzleR = Vector3.new(hw * 0.22, hh * 0.17, hd * 0.12)
	end
	if snout == "trunk" then
		local y = headY - hh * 0.15
		local z = headZ - hd * 0.42
		for i = 1, 5 do
			local w = 1.0 - i * 0.1
			ball(model, "Trunk", Vector3.new(w, 1.0, w), CFrame.new(0, y, z), body)
			y -= 0.6
			z -= 0.15 - i * 0.02
		end
	else
		ball(model, "Muzzle", muzzleR * 2, CFrame.new(muzzleC), snout == "pig" and accent or light)
		local noseColor = look.RedNose and Color3.fromRGB(255, 50, 50) or (snout == "pig" and accent:Lerp(BLACK, 0.3) or dark)
		if snout == "pig" or dragon then
			for _, sx in ipairs({ -1, 1 }) do
				local cf = onSurface(muzzleC, muzzleR, Vector3.new(sx * 0.35, 0.25, -1), 0.02)
				ball(model, "Nostril", Vector3.new(0.22, 0.16, 0.12), cf, noseColor)
			end
		else
			local cf = onSurface(muzzleC, muzzleR, Vector3.new(0, 0.55, -1), 0.06)
			ball(model, "Nose", look.RedNose and Vector3.new(0.6, 0.55, 0.45) or Vector3.new(0.55, 0.38, 0.32), cf, noseColor, look.RedNose and Enum.Material.Neon or nil)
		end
		-- smile
		for _, sx in ipairs({ -1, 1 }) do
			local cf = onSurface(muzzleC, muzzleR, Vector3.new(sx * 0.32, -0.25, -1), 0.01)
			block(model, "Smile", Vector3.new(0.45, 0.07, 0.05), cf * CFrame.Angles(0, 0, sx * 0.35), BLACK)
		end
		if fierce then
			for _, sx in ipairs({ -1, 1 }) do
				local cf = onSurface(muzzleC, muzzleR, Vector3.new(sx * 0.3, -0.55, -1), 0.0)
				ball(model, "Fang", Vector3.new(0.16, 0.3, 0.12), cf, WHITE)
			end
		end
	end

	-- big glossy eyes on the curved face
	for _, sx in ipairs({ -1, 1 }) do
		local eye = onSurface(headC, headR, Vector3.new(sx * 0.48, 0.12, -1), 0.12)
		if look.Panda then
			ball(model, "EyePatch", Vector3.new(1.35, 1.5, 0.35), eye * CFrame.new(0, -0.05, 0.05) * CFrame.Angles(0, 0, sx * 0.3), accent)
		end
		ball(model, "EyeWhite", Vector3.new(1.0, 1.15, 0.4), eye, skeleton and BLACK or WHITE)
		ball(model, "Eye", Vector3.new(0.82, 0.98, 0.3), eye * CFrame.new(-sx * 0.04, -0.03, -0.1), iris, (skeleton or look.Eye) and Enum.Material.Neon or nil)
		ball(model, "Pupil", Vector3.new(0.46, 0.58, 0.2), eye * CFrame.new(-sx * 0.05, -0.06, -0.17), BLACK)
		ball(model, "EyeShine", Vector3.new(0.3, 0.3, 0.12), eye * CFrame.new(sx * 0.12, 0.2, -0.24), WHITE, Enum.Material.Neon)
		ball(model, "EyeShine", Vector3.new(0.14, 0.14, 0.1), eye * CFrame.new(-sx * 0.16, -0.24, -0.23), WHITE, Enum.Material.Neon)
		-- brow
		local brow = onSurface(headC, headR, Vector3.new(sx * 0.46, 0.55, -1), 0.03)
		block(model, "Brow", Vector3.new(0.75, 0.13, 0.08), brow * CFrame.Angles(0, 0, fierce and sx * 0.4 or -sx * 0.12), dark)
		-- blush
		if not fierce and not look.Panda and not skeleton then
			local cheek = onSurface(headC, headR, Vector3.new(sx * 0.75, -0.25, -0.75), 0.06)
			ball(model, "Blush", Vector3.new(0.6, 0.32, 0.12), cheek, Color3.fromRGB(255, 150, 180))
		end
	end

	if look.Mane then
		for i = 0, 9 do
			local a = i / 10 * math.pi * 2
			local d = Vector3.new(math.cos(a) * 1.0, math.sin(a) * 0.95, 0.35)
			local cf = onSurface(headC, headR + Vector3.new(0.15, 0.15, 0.15), d)
			ball(model, "Mane", Vector3.new(1.5, 1.5, 1.3), cf, accent)
		end
		top = headTop + 0.6
	end

	-- dragon crest and forehead diamond, cheek frills
	if dragon then
		for i = 0, 2 do
			local cf = onSurface(headC, headR, Vector3.new(0, 1, 0.15 + i * 0.45), 0.15)
			block(model, "Crest", Vector3.new(0.12, 0.75 - i * 0.15, 0.55), cf * CFrame.Angles(-math.pi / 2, 0, 0) * CFrame.Angles(0.5, 0, 0), dark)
		end
		block(model, "Diamond", Vector3.new(0.38, 0.38, 0.1), onSurface(headC, headR, Vector3.new(0, 0.62, -1), 0.02) * CFrame.Angles(0, 0, math.pi / 4), dark)
		for _, sx in ipairs({ -1, 1 }) do
			for i = 0, 1 do
				local cf = onSurface(headC, headR, Vector3.new(sx, 0.1 - i * 0.45, 0.1), 0.1)
				block(model, "Frill", Vector3.new(0.12, 0.4, 0.75), cf * CFrame.Angles(0, sx * 0.9, 0), body:Lerp(dark, 0.3))
			end
		end
	end

	-- ears
	local ears = look.Ears or "none"
	for _, sx in ipairs({ -1, 1 }) do
		if ears == "pointy" then
			local base = onSurface(headC, headR, Vector3.new(sx * 0.55, 0.85, 0.1), 0.25)
			local up = CFrame.lookAt(base.Position, base.Position + Vector3.new(sx * 0.45, 1, 0.15))
			ball(model, "Ear", Vector3.new(1.15, 0.5, 1.2), up * CFrame.new(0, 0, -0.45), body)
			ball(model, "Ear", Vector3.new(0.7, 0.4, 0.75), up * CFrame.new(0, 0, -0.95), body)
			ball(model, "EarInner", Vector3.new(0.65, 0.14, 0.85), up * CFrame.new(0, -0.22, -0.55), light)
			top = math.max(top, headTop + 1.0)
		elseif ears == "round" then
			local cf = onSurface(headC, headR, Vector3.new(sx * 0.6, 0.85, 0.15), 0.1)
			local face = CFrame.lookAt(cf.Position, cf.Position + Vector3.new(0, 0, -1))
			ball(model, "Ear", Vector3.new(1.05, 1.05, 0.5), face, look.Panda and accent or body)
			if not look.Panda then
				ball(model, "EarInner", Vector3.new(0.6, 0.6, 0.2), face * CFrame.new(0, 0, -0.17), light)
			end
			top = math.max(top, headTop + 0.5)
		elseif ears == "long" then
			local base = onSurface(headC, headR, Vector3.new(sx * 0.35, 1, 0.1), 0.2)
			local up = CFrame.lookAt(base.Position, base.Position + Vector3.new(sx * 0.18, 1, 0.12))
			ball(model, "Ear", Vector3.new(0.85, 0.5, 2.8), up * CFrame.new(0, 0, -1.3), body)
			ball(model, "EarInner", Vector3.new(0.45, 0.14, 2.1), up * CFrame.new(0, -0.22, -1.35), light)
			top = math.max(top, headTop + 2.6)
		elseif ears == "floppy" then
			local cf = onSurface(headC, headR, Vector3.new(sx, 0.25, 0.1), 0.15)
			ball(model, "Ear", Vector3.new(0.45, 1.5, 1.0), CFrame.new(cf.Position + Vector3.new(sx * 0.15, -0.45, 0)) * CFrame.Angles(0, 0, sx * 0.3), look.Panda and accent or body:Lerp(dark, 0.25))
		end
	end

	-- horns
	local horns = look.Horns or "none"
	local function segmentedHorn(sx: number, base: CFrame, color: Color3, count: number, size: number, bend: number)
		local cf = base
		for i = 1, count do
			local w = size * (1 - (i - 1) / (count + 0.6))
			ball(model, "Horn", Vector3.new(w, w * 1.15, w), cf, color)
			if i < count then
				-- thin darker ring between segments, like the reference horns
				ball(model, "HornRing", Vector3.new(w * 0.92, w * 0.3, w * 0.92), cf * CFrame.new(0, w * 0.5, 0), color:Lerp(BLACK, 0.12))
			end
			cf = cf * CFrame.new(0, w * 0.62, 0) * CFrame.Angles(bend, 0, -sx * bend * 0.4)
		end
		return cf.Position.Y
	end
	if horns == "small" then
		for _, sx in ipairs({ -1, 1 }) do
			local base = CFrame.new(onSurface(headC, headR, Vector3.new(sx * 0.5, 0.85, 0.2), 0.3).Position) * CFrame.Angles(0.15, 0, -sx * 0.25)
			top = math.max(top, segmentedHorn(sx, base, horn, 4, 1.05, 0.18))
		end
	elseif horns == "oni" then
		for _, sx in ipairs({ -1, 1 }) do
			local base = CFrame.new(onSurface(headC, headR, Vector3.new(sx * 0.55, 0.85, 0.1), 0.3).Position) * CFrame.Angles(0.1, 0, -sx * 0.5)
			top = math.max(top, segmentedHorn(sx, base, HORN_DARK, 5, 1.05, 0.28))
		end
	elseif horns == "antlers" then
		local col = Color3.fromRGB(235, 215, 175)
		for _, sx in ipairs({ -1, 1 }) do
			local p = onSurface(headC, headR, Vector3.new(sx * 0.45, 0.9, 0.2), 0.2).Position
			local base = CFrame.new(p) * CFrame.Angles(0, 0, -sx * 0.4)
			ball(model, "Antler", Vector3.new(0.35, 2.2, 0.35), base * CFrame.new(0, 1.0, 0), col)
			ball(model, "Antler", Vector3.new(0.3, 1.3, 0.3), base * CFrame.new(sx * 0.4, 1.1, 0) * CFrame.Angles(0, 0, -sx * 0.9), col)
			ball(model, "Antler", Vector3.new(0.3, 1.2, 0.3), base * CFrame.new(0, 1.7, -0.3) * CFrame.Angles(-0.7, 0, 0), col)
			ball(model, "Antler", Vector3.new(0.28, 1.0, 0.28), base * CFrame.new(sx * 0.3, 2.0, 0.1) * CFrame.Angles(0, 0, -sx * 0.6), col)
			top = math.max(top, p.Y + 2.4)
		end
	elseif horns == "unicorn" then
		local p = onSurface(headC, headR, Vector3.new(0, 0.85, -0.5), 0.2).Position
		top = math.max(top, segmentedHorn(1, CFrame.new(p) * CFrame.Angles(-0.35, 0, 0), GOLD, 5, 0.75, 0.0))
	elseif horns == "rhino" then
		local p = onSurface(muzzleC, muzzleR, Vector3.new(0, 1, -0.5), 0.1).Position
		segmentedHorn(1, CFrame.new(p) * CFrame.Angles(-0.35, 0, 0), IVORY, 3, 0.9, 0.15)
	elseif horns == "bull" then
		for _, sx in ipairs({ -1, 1 }) do
			local p = onSurface(headC, headR, Vector3.new(sx, 0.55, 0), 0.25).Position
			segmentedHorn(sx, CFrame.new(p) * CFrame.Angles(0, 0, -sx * 1.3), IVORY, 4, 0.8, 0.3)
		end
	elseif horns == "tusks" then
		for _, sx in ipairs({ -1, 1 }) do
			local p = muzzleC + Vector3.new(sx * muzzleR.X * 0.8, -muzzleR.Y * 0.6, -muzzleR.Z * 0.4)
			segmentedHorn(sx, CFrame.new(p) * CFrame.Angles(-2.3, 0, 0), IVORY, 3, 0.5, -0.3)
		end
	end

	-- tail
	local tail = look.Tail or "short"
	local tailBase = Vector3.new(0, bodyY + bh * 0.1, bl * 0.45)
	if tail == "short" then
		ball(model, "Tail", Vector3.new(0.85, 0.85, 0.85), CFrame.new(tailBase + Vector3.new(0, 0.1, 0.1)), look.Fluffy and body:Lerp(WHITE, 0.12) or body)
	elseif tail == "fluffy" then
		ball(model, "Tail", Vector3.new(1.3, 1.3, 1.7), CFrame.new(tailBase + Vector3.new(0, 0.4, 0.5)) * CFrame.Angles(0.6, 0, 0), body)
		ball(model, "Tail", Vector3.new(1.55, 1.55, 1.6), CFrame.new(tailBase + Vector3.new(0, 1.3, 1.1)) * CFrame.Angles(0.9, 0, 0), body)
		ball(model, "TailTip", Vector3.new(1.25, 1.25, 1.1), CFrame.new(tailBase + Vector3.new(0, 2.1, 1.35)), light)
		top = math.max(top, tailBase.Y + 2.7)
	elseif tail == "long" then
		local p = tailBase
		for i = 1, 5 do
			ball(model, "Tail", Vector3.new(0.5, 0.5, 0.9), CFrame.lookAt(p, p + Vector3.new(0, 0.3 + i * 0.15, 1)), body)
			p += Vector3.new(0, 0.2 + i * 0.12, 0.6 - i * 0.05)
		end
		ball(model, "TailTip", Vector3.new(0.85, 0.95, 0.85), CFrame.new(p), accent)
	elseif tail == "spiked" then
		local p = tailBase + Vector3.new(0, -0.3, 0)
		local dir = Vector3.new(0, -0.15, 1).Unit
		for i = 1, 7 do
			local w = 1.25 - i * 0.13
			local cf = CFrame.lookAt(p, p + dir)
			ball(model, "Tail", Vector3.new(w, w, 1.2), cf, body)
			block(model, "Spike", Vector3.new(0.12, w * 0.55, w * 0.55), cf * CFrame.new(0, w * 0.48, 0) * CFrame.Angles(math.pi / 4, 0, 0), dark)
			if i % 2 == 0 then
				block(model, "Scale", Vector3.new(0.25, 0.25, 0.08), cf * CFrame.new(w * 0.42, 0, 0) * CFrame.Angles(0, math.pi / 2, math.pi / 4), body:Lerp(WHITE, 0.45))
			end
			p += dir * 0.85
			dir = (dir + Vector3.new(0, 0.12 + i * 0.03, 0)).Unit
		end
		block(model, "TailBlade", Vector3.new(0.14, 0.9, 0.9), CFrame.lookAt(p, p + dir) * CFrame.Angles(math.pi / 4, 0, 0), dark)
	end

	-- back spikes
	if dragon or skeleton then
		for i = 0, 3 do
			local cf = onSurface(bodyC, bodyR, Vector3.new(0, 1, -0.55 + i * 0.4), 0.15)
			block(model, "Spike", Vector3.new(0.14, 0.6, 0.6), cf * CFrame.Angles(-math.pi / 2, 0, 0) * CFrame.Angles(math.pi / 4, 0, 0), dark)
		end
	end

	-- small cute wings: a bone with two fingers and a light membrane
	if look.Wings then
		for _, sx in ipairs({ -1, 1 }) do
			local root = Vector3.new(sx * bw * 0.32, bodyTop - 0.15, -bl * 0.12)
			-- the wing plane is tilted up so the membrane faces sideways/forward like the reference
			local wing = CFrame.new(root) * CFrame.Angles(0, -sx * 0.45, sx * 0.6) * CFrame.Angles(-1.0, 0, 0)
			ball(model, "WingBone", Vector3.new(3.0, 0.36, 0.36), wing * CFrame.new(sx * 1.4, 0, 0), body)
			ball(model, "WingTip", Vector3.new(0.5, 0.5, 0.5), wing * CFrame.new(sx * 2.85, 0, 0), horn)
			for i = 0, 1 do
				ball(model, "WingBone", Vector3.new(0.24, 0.24, 2.0 - i * 0.35), wing * CFrame.new(sx * (1.3 + i * 1.1), 0, 0.9) * CFrame.Angles(0, -sx * 0.3, 0), body)
			end
			local membrane = ball(model, "Wing", Vector3.new(2.8, 0.14, 1.9), wing * CFrame.new(sx * 1.5, -0.02, 0.8), skeleton and accent or body:Lerp(WHITE, 0.5))
			if skeleton then
				membrane.Transparency = 0.4
			end
		end
		top = math.max(top, bodyTop + 2.2)
	end

	return top
end

local function tint(model: Model, color: Color3, amount: number, material: Enum.Material?)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "Root" and p.Name ~= "Eye" and p.Name ~= "EyeWhite" and p.Name ~= "Pupil" and p.Name ~= "EyeShine" then
			p.Color = p.Color:Lerp(color, amount)
			if material then
				p.Material = material
			end
		end
	end
end

local function addAura(root: BasePart, auraIndex: number, scale: number)
	local aura = Game.Auras[auraIndex]
	if not aura or auraIndex <= 1 then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "AuraAttachment"
	attachment.Position = Vector3.new(0, 2 * scale, 0)
	attachment.Parent = root
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Aura"
	emitter.Color = ColorSequence.new(aura.Color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6 * scale),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Rate = 10 + auraIndex * 8
	emitter.Speed = NumberRange.new(1, 3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.Parent = attachment
	local light = Instance.new("PointLight")
	light.Color = aura.Color
	light.Range = 8 + 3 * scale
	light.Brightness = 1.5
	light.Parent = root
end

-- Builds a creature straight from a Look recipe (used for the nest guards).
function AnimalModel.buildCreature(look, scale: number): Model
	local model = Instance.new("Model")
	model.Name = "Creature"
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.new(0, 0.5, 0)
	root.Parent = model
	model.PrimaryPart = root
	local height = buildRecipe(model, look)
	model:SetAttribute("Height", height * scale)
	model.WorldPivot = CFrame.new(0, 0, 0)
	if scale ~= 1 then
		model:ScaleTo(scale)
	end
	return model
end

-- options: { Mutation = index, Aura = index }
function AnimalModel.build(speciesId: string, options): Model
	options = options or {}
	local def = Animals.ById[speciesId]
	local model = custom(speciesId)
	local scale = def and def.Scale or 1
	if not model then
		model = Instance.new("Model")
		model.Name = speciesId
		local root = Instance.new("Part")
		root.Name = "Root"
		root.Size = Vector3.new(1, 1, 1)
		root.Transparency = 1
		root.Anchored = true
		root.CanCollide = false
		root.CanQuery = false
		root.CanTouch = false
		root.CFrame = CFrame.new(0, 0.5, 0)
		root.Parent = model
		model.PrimaryPart = root
		local height = buildRecipe(model, def and def.Look or { Body = Color3.new(1, 1, 1), Accent = Color3.new(0.5, 0.5, 0.5) })
		model:SetAttribute("Height", height * scale)
		-- scale around the feet so the animal keeps standing on its pivot
		model.WorldPivot = CFrame.new(0, 0, 0)
		if scale ~= 1 then
			model:ScaleTo(scale)
		end
		if def and def.Look.Sparkle then
			local sparkles = Instance.new("Sparkles")
			sparkles.SparkleColor = def.Look.Accent
			sparkles.Parent = root
		end
		if def and def.Look.Fire then
			local head = model:FindFirstChild("Head")
			if head then
				local fire = Instance.new("Fire")
				fire.Size = 2.5 * scale
				fire.Heat = 3
				fire.Color = def.Look.Accent
				fire.SecondaryColor = Color3.fromRGB(255, 230, 120)
				fire.Parent = head
			end
		end
	end

	local mutation = options.Mutation or 1
	if mutation == 2 then
		tint(model, GOLD, 0.65, Enum.Material.Foil)
	elseif mutation == 3 then
		tint(model, Color3.fromRGB(150, 235, 255), 0.6, Enum.Material.Glass)
	elseif mutation == 4 then
		CollectionService:AddTag(model, "RainbowAnimal")
	end
	addAura(model.PrimaryPart :: BasePart, options.Aura or 1, scale)
	model:SetAttribute("Species", speciesId)
	return model
end

return AnimalModel
