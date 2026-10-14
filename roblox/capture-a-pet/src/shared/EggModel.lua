-- Blocky patterned eggs. Rare eggs get a crown and a colored aura ring; common ones don't.

local Shared = script.Parent
local Animals = require(Shared.Config.Animals)
local Game = require(Shared.Config.Game)

local EggModel = {}

-- egg silhouette: width of each layer from bottom to top
local LAYERS = { 1.7, 2.3, 2.6, 2.75, 2.75, 2.6, 2.3, 1.9, 1.3 }
local LAYER_H = 0.42

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
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

-- options: { Species, Rarity, Aura, Scale }
function EggModel.build(options): Model
	local def = Animals.ById[options.Species]
	local rarity = options.Rarity or (def and def.Rarity) or 1
	local scale = (options.Scale or 1) * (1 + (rarity - 1) * 0.12)
	local base = def and def.Look.Body or Color3.fromRGB(240, 235, 220)
	local accent = def and def.Look.Accent or Color3.fromRGB(60, 60, 60)
	-- dark animals get a lighter base so the pattern stays readable
	if (base.R + base.G + base.B) / 3 < 0.25 then
		base, accent = accent, base
	end
	local seed = 0
	for i = 1, #(options.Species or "") do
		seed += string.byte(options.Species, i) * i
	end
	local rng = Random.new(seed)

	local model = Instance.new("Model")
	model.Name = "Egg"
	local root = block(model, "Root", Vector3.new(1, 1, 1), CFrame.new(0, 0.5, 0), base)
	root.Transparency = 1
	model.PrimaryPart = root

	local y = 0
	for layer, w in ipairs(LAYERS) do
		block(model, "Shell", Vector3.new(w, LAYER_H, w), CFrame.new(0, y + LAYER_H / 2, 0), base)
		-- pattern patches stuck onto the shell (soccer-ball / spots look)
		local patches = (layer > 1 and layer < #LAYERS) and 3 or 0
		for i = 1, patches do
			local a = (i / patches) * math.pi * 2 + layer * 0.9 + rng:NextNumber(-0.3, 0.3)
			local r = w / 2
			local pw = rng:NextNumber(0.5, 0.9)
			block(model, "Patch", Vector3.new(pw, LAYER_H + 0.02, 0.12), CFrame.new(math.cos(a) * r, y + LAYER_H / 2, math.sin(a) * r) * CFrame.Angles(0, -a + math.pi / 2, 0), accent)
		end
		y += LAYER_H
	end
	local height = y

	if rarity >= 5 then
		-- golden crown on top
		local gold = Color3.fromRGB(255, 205, 50)
		block(model, "Crown", Vector3.new(1.5, 0.35, 1.5), CFrame.new(0, height + 0.15, 0), gold, Enum.Material.Foil)
		for i = 0, 4 do
			local a = i / 5 * math.pi * 2
			block(model, "CrownSpike", Vector3.new(0.3, 0.6, 0.3), CFrame.new(math.cos(a) * 0.6, height + 0.6, math.sin(a) * 0.6), gold, Enum.Material.Foil)
		end
		height += 0.9
	end

	if rarity >= Game.EggAuraMinRarity then
		local color = Game.Rarities[rarity].Color
		if rarity == 7 then
			color = Color3.fromRGB(255, 255, 255)
		end
		-- glowing ring on the ground
		local ring = Instance.new("Part")
		ring.Name = "AuraRing"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.15, 5.5, 5.5)
		ring.CFrame = CFrame.new(0, 0.08, 0) * CFrame.Angles(0, 0, math.rad(90))
		ring.Color = color
		ring.Material = Enum.Material.Neon
		ring.Transparency = 0.35
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.Parent = model
		local attachment = Instance.new("Attachment")
		attachment.Position = Vector3.new(0, 1.5, 0)
		attachment.Parent = root
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Aura"
		if rarity >= 6 then
			emitter.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
				ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 240, 80)),
				ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 220, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 90, 255)),
			})
		else
			emitter.Color = ColorSequence.new(color)
		end
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new(0.5, 0)
		emitter.Lifetime = NumberRange.new(0.8, 1.5)
		emitter.Rate = 6 + rarity * 5
		emitter.Speed = NumberRange.new(1.5, 3)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Parent = attachment
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 10
		light.Brightness = 1.2 + rarity * 0.2
		light.Parent = root
	end

	local auraIndex = options.Aura or 1
	if auraIndex > 1 then
		local aura = Game.Auras[auraIndex]
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = aura.Color
		sparkles.Parent = root
	end

	model:SetAttribute("Height", height * scale)
	model.WorldPivot = CFrame.new(0, 0, 0) -- scale around the bottom so the egg stays on the ground
	if scale ~= 1 then
		model:ScaleTo(scale)
	end
	return model
end

function EggModel.displayName(speciesId: string, rarity: number): string
	return Game.Rarities[rarity].Name .. " " .. speciesId .. " Egg"
end

return EggModel
