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
local function buildRecipe(model: Model, look)
	local body = look.Body
	local accent = look.Accent
	local eyeColor = look.Eye or BLACK
	local bulky = look.Bulky
	local legLen = (look.Legs == "short" and 1.0) or (look.Legs == "long" and 2.6) or 1.7
	local bw, bh, bl = 2.6, 2.4, 4.2
	if bulky then
		bw, bh, bl = 3.4, 3.0, 4.8
	end
	local legW = bulky and 1.15 or 0.9
	local hs = bulky and 2.6 or 2.2
	local bodyY = legLen + bh / 2
	local bodyTop = legLen + bh
	local skeleton = look.Skeleton

	local bodyMat = look.Shiny and Enum.Material.Glass or Enum.Material.SmoothPlastic

	-- body
	local torso = block(model, "Body", Vector3.new(bw, bh, bl), CFrame.new(0, bodyY, 0), body, bodyMat)
	if look.Shiny then
		torso.Transparency = 0.05
	end
	-- belly
	block(model, "Belly", Vector3.new(bw * 0.7, 0.2, bl * 0.75), CFrame.new(0, legLen - 0.05, 0), look.Panda and body or accent)
	if look.Panda then
		-- panda pattern: dark band around the shoulders
		block(model, "Band", Vector3.new(bw + 0.06, bh + 0.06, 1.3), CFrame.new(0, bodyY, -bl / 2 + 1.0), accent)
	end
	if look.Hump then
		block(model, "Hump", Vector3.new(bw * 0.6, 1.2, bl * 0.4), CFrame.new(0, bodyTop + 0.55, 0.2), body)
	end
	if look.Fluffy then
		block(model, "Fluff", Vector3.new(bw + 0.4, 0.8, bl * 0.8), CFrame.new(0, bodyTop - 0.2, 0), body, Enum.Material.Fabric)
	end
	if look.Stripes or skeleton then
		local stripeColor = skeleton and accent or accent
		for i = -1, 1 do
			block(model, "Stripe", Vector3.new(bw + 0.06, bh * 0.65, 0.35), CFrame.new(0, bodyY + bh * 0.18, i * bl * 0.25), stripeColor)
		end
	end
	if look.Spots then
		local spots = { { 1, 0.4, -0.8 }, { 1, -0.2, 0.9 }, { -1, 0.3, 0.3 }, { -1, -0.3, -1.2 } }
		for _, s in ipairs(spots) do
			block(model, "Spot", Vector3.new(0.1, 0.55, 0.55), CFrame.new(s[1] * (bw / 2 + 0.03), bodyY + s[2], s[3]), accent)
		end
	end

	-- legs
	local legColor = look.Panda and accent or body
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local x = sx * (bw / 2 - legW / 2 - 0.1)
			local z = sz * (bl / 2 - legW / 2 - 0.25)
			block(model, "Leg", Vector3.new(legW, legLen, legW), CFrame.new(x, legLen / 2, z), legColor)
			block(model, "Paw", Vector3.new(legW + 0.08, 0.3, legW + 0.08), CFrame.new(x, 0.15, z), skeleton and body or (look.Panda and accent or accent:Lerp(body, 0.5)))
		end
	end

	-- neck + head
	local headY = bodyTop + hs * 0.25
	local headZ = -(bl / 2 + hs / 2 - 0.4)
	if look.LongNeck then
		block(model, "Neck", Vector3.new(1.2, 2.6, 1.2), CFrame.new(0, bodyTop + 0.9, -bl / 2 + 0.6), body)
		headY = bodyTop + 2.2
		headZ = -(bl / 2 + 0.4)
	end
	local headCF = CFrame.new(0, headY, headZ)
	block(model, "Head", Vector3.new(hs, hs, hs), headCF, body, bodyMat)
	local front = headZ - hs / 2

	if look.Mane then
		block(model, "Mane", Vector3.new(hs + 0.9, hs + 0.9, 1.2), CFrame.new(0, headY, headZ + hs / 2 - 0.2), accent, Enum.Material.Fabric)
	end

	-- eyes
	local eyeMat = (skeleton or look.Eye) and Enum.Material.Neon or Enum.Material.SmoothPlastic
	for _, sx in ipairs({ -1, 1 }) do
		if look.Panda then
			block(model, "EyePatch", Vector3.new(0.7, 0.75, 0.08), CFrame.new(sx * hs * 0.24, headY + 0.25, front - 0.02), accent)
		end
		block(model, "EyeWhite", Vector3.new(0.5, 0.55, 0.08), CFrame.new(sx * hs * 0.24, headY + 0.25, front - 0.05), skeleton and BLACK or WHITE)
		block(model, "Eye", Vector3.new(0.3, 0.38, 0.1), CFrame.new(sx * hs * 0.24, headY + 0.22, front - 0.09), eyeColor, eyeMat)
	end

	-- snout
	local snout = look.Snout or "short"
	local snoutTipZ = front
	local snoutY = headY - hs * 0.22
	if snout == "long" then
		block(model, "Snout", Vector3.new(hs * 0.55, hs * 0.4, 1.1), CFrame.new(0, snoutY, front - 0.5), body)
		block(model, "Muzzle", Vector3.new(hs * 0.5, 0.2, 1.0), CFrame.new(0, snoutY - hs * 0.2, front - 0.5), accent)
		snoutTipZ = front - 1.05
	elseif snout == "short" then
		block(model, "Snout", Vector3.new(hs * 0.5, hs * 0.32, 0.45), CFrame.new(0, snoutY, front - 0.2), accent)
		snoutTipZ = front - 0.43
	elseif snout == "pig" then
		block(model, "Snout", Vector3.new(hs * 0.45, hs * 0.35, 0.4), CFrame.new(0, snoutY, front - 0.2), accent)
		for _, sx in ipairs({ -1, 1 }) do
			block(model, "Nostril", Vector3.new(0.15, 0.2, 0.05), CFrame.new(sx * 0.18, snoutY, front - 0.42), BLACK)
		end
	elseif snout == "trunk" then
		local y = snoutY
		local z = front - 0.3
		for i = 1, 4 do
			local w = 0.75 - i * 0.08
			block(model, "Trunk", Vector3.new(w, 0.8, w), CFrame.new(0, y, z), body)
			y -= 0.7
			z -= 0.12
		end
		snoutTipZ = front - 0.3
	else -- flat
		block(model, "Snout", Vector3.new(hs * 0.3, hs * 0.2, 0.2), CFrame.new(0, snoutY, front - 0.08), accent)
		snoutTipZ = front - 0.18
	end
	if snout ~= "pig" and snout ~= "trunk" and not skeleton then
		local noseColor = look.RedNose and Color3.fromRGB(255, 40, 40) or BLACK
		local noseSize = look.RedNose and 0.45 or 0.3
		block(model, "Nose", Vector3.new(noseSize, noseSize * 0.7, 0.12), CFrame.new(0, snoutY + 0.1, snoutTipZ - 0.04), noseColor, look.RedNose and Enum.Material.Neon or nil)
	end
	if skeleton then
		for i = -1, 1 do
			block(model, "Tooth", Vector3.new(0.16, 0.3, 0.16), CFrame.new(i * 0.3, snoutY - 0.45, snoutTipZ + 0.15), WHITE)
		end
	end

	-- ears
	local ears = look.Ears or "none"
	local headTop = headY + hs / 2
	for _, sx in ipairs({ -1, 1 }) do
		local ex = sx * hs * 0.3
		if ears == "pointy" then
			block(model, "Ear", Vector3.new(0.6, 0.8, 0.3), CFrame.new(ex, headTop + 0.4, headZ + 0.3) * CFrame.Angles(0, 0, -sx * 0.15), body)
			block(model, "EarInner", Vector3.new(0.3, 0.5, 0.05), CFrame.new(ex, headTop + 0.35, headZ + 0.13) * CFrame.Angles(0, 0, -sx * 0.15), accent)
		elseif ears == "round" then
			block(model, "Ear", Vector3.new(0.7, 0.6, 0.3), CFrame.new(ex, headTop + 0.25, headZ + 0.3), look.Panda and accent or body)
		elseif ears == "long" then
			block(model, "Ear", Vector3.new(0.5, 1.7, 0.3), CFrame.new(ex, headTop + 0.8, headZ + 0.3) * CFrame.Angles(0, 0, -sx * 0.1), body)
			block(model, "EarInner", Vector3.new(0.25, 1.3, 0.05), CFrame.new(ex, headTop + 0.8, headZ + 0.13) * CFrame.Angles(0, 0, -sx * 0.1), accent)
		elseif ears == "floppy" then
			block(model, "Ear", Vector3.new(0.3, 1.0, 0.7), CFrame.new(sx * (hs / 2 + 0.15), headY + 0.2, headZ + 0.2) * CFrame.Angles(0, 0, sx * 0.2), body)
		end
	end

	-- horns
	local horns = look.Horns or "none"
	if horns == "small" then
		for _, sx in ipairs({ -1, 1 }) do
			block(model, "Horn", Vector3.new(0.3, 0.8, 0.3), CFrame.new(sx * hs * 0.25, headTop + 0.35, headZ + 0.45) * CFrame.Angles(-0.4, 0, 0), IVORY)
		end
	elseif horns == "oni" then
		for _, sx in ipairs({ -1, 1 }) do
			local base = CFrame.new(sx * hs * 0.32, headTop + 0.55, headZ + 0.2) * CFrame.Angles(0.15, 0, -sx * 0.35)
			block(model, "Horn", Vector3.new(0.5, 1.3, 0.5), base, HORN_DARK)
			block(model, "Horn", Vector3.new(0.38, 1.0, 0.38), base * CFrame.new(0, 1.0, 0.15) * CFrame.Angles(0.5, 0, 0), HORN_DARK)
			block(model, "HornTip", Vector3.new(0.25, 0.7, 0.25), base * CFrame.new(0, 1.6, 0.55) * CFrame.Angles(1.0, 0, 0), BLACK)
		end
	elseif horns == "antlers" then
		for _, sx in ipairs({ -1, 1 }) do
			local base = CFrame.new(sx * hs * 0.28, headTop + 0.6, headZ + 0.3) * CFrame.Angles(0, 0, -sx * 0.3)
			local col = Color3.fromRGB(235, 215, 175)
			block(model, "Antler", Vector3.new(0.25, 1.4, 0.25), base, col)
			block(model, "Antler", Vector3.new(0.2, 0.9, 0.2), base * CFrame.new(sx * 0.35, 0.5, 0) * CFrame.Angles(0, 0, -sx * 0.9), col)
			block(model, "Antler", Vector3.new(0.2, 0.8, 0.2), base * CFrame.new(0, 0.9, -0.3) * CFrame.Angles(-0.7, 0, 0), col)
		end
	elseif horns == "unicorn" then
		for i = 1, 3 do
			local w = 0.5 - i * 0.12
			block(model, "Horn", Vector3.new(w, 0.55, w), CFrame.new(0, headTop + 0.1 + i * 0.45, front + 0.6 - i * 0.12) * CFrame.Angles(-0.3, 0, 0), GOLD, Enum.Material.Neon)
		end
	elseif horns == "rhino" then
		block(model, "Horn", Vector3.new(0.5, 1.1, 0.5), CFrame.new(0, snoutY + 0.6, snoutTipZ + 0.2) * CFrame.Angles(-0.25, 0, 0), IVORY)
		block(model, "Horn", Vector3.new(0.35, 0.6, 0.35), CFrame.new(0, headTop + 0.2, front + 0.5), IVORY)
	elseif horns == "bull" then
		for _, sx in ipairs({ -1, 1 }) do
			block(model, "Horn", Vector3.new(1.0, 0.35, 0.35), CFrame.new(sx * (hs / 2 + 0.4), headTop - 0.2, headZ), IVORY)
			block(model, "HornTip", Vector3.new(0.3, 0.7, 0.3), CFrame.new(sx * (hs / 2 + 0.8), headTop + 0.2, headZ), IVORY)
		end
	elseif horns == "tusks" then
		for _, sx in ipairs({ -1, 1 }) do
			block(model, "Tusk", Vector3.new(0.3, 0.3, 1.2), CFrame.new(sx * 0.45, snoutY - 0.35, snoutTipZ - 0.3) * CFrame.Angles(0.35, 0, 0), IVORY)
		end
	end

	-- tail
	local tail = look.Tail or "short"
	local backZ = bl / 2
	if tail == "short" then
		block(model, "Tail", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, bodyTop - 0.4, backZ + 0.2), body)
	elseif tail == "long" then
		block(model, "Tail", Vector3.new(0.35, 0.35, 2.0), CFrame.new(0, bodyTop, backZ + 0.8) * CFrame.Angles(0.5, 0, 0), body)
		block(model, "TailTip", Vector3.new(0.45, 0.45, 0.5), CFrame.new(0, bodyTop + 0.85, backZ + 1.6), accent)
	elseif tail == "fluffy" then
		block(model, "Tail", Vector3.new(0.9, 0.9, 1.8), CFrame.new(0, bodyTop - 0.1, backZ + 0.8) * CFrame.Angles(0.45, 0, 0), body, Enum.Material.Fabric)
		block(model, "TailTip", Vector3.new(0.85, 0.85, 0.6), CFrame.new(0, bodyTop + 0.55, backZ + 1.65) * CFrame.Angles(0.45, 0, 0), accent, Enum.Material.Fabric)
	elseif tail == "spiked" then
		local z = backZ + 0.6
		local y = bodyY
		for i = 1, 4 do
			local w = 1.2 - i * 0.22
			block(model, "Tail", Vector3.new(w, w, 1.2), CFrame.new(0, y, z), body)
			block(model, "Spike", Vector3.new(0.2, 0.5, 0.3), CFrame.new(0, y + w / 2 + 0.2, z), accent)
			z += 1.05
			y -= 0.15
		end
	end
	-- back spikes for dragons
	if look.Wings or skeleton then
		for i = -1, 1 do
			block(model, "Spike", Vector3.new(0.25, 0.6, 0.6), CFrame.new(0, bodyTop + 0.25, i * bl * 0.28), accent)
		end
	end

	-- wings
	if look.Wings then
		for _, sx in ipairs({ -1, 1 }) do
			local base = CFrame.new(sx * (bw / 2 + 0.2), bodyTop + 0.3, -0.3) * CFrame.Angles(0, 0, sx * 0.55)
			if skeleton then
				block(model, "WingBone", Vector3.new(4.2, 0.3, 0.3), base * CFrame.new(sx * 2.0, 0, -0.8), body)
				for i = 0, 2 do
					block(model, "WingBone", Vector3.new(0.22, 0.22, 2.4), base * CFrame.new(sx * (0.8 + i * 1.2), 0, 0.3), body)
				end
			else
				block(model, "Wing", Vector3.new(4.2, 0.22, 2.6), base * CFrame.new(sx * 2.0, 0, 0), accent)
				block(model, "WingBone", Vector3.new(4.4, 0.35, 0.35), base * CFrame.new(sx * 2.1, 0.05, -1.3), body)
			end
		end
	end

	return bodyTop + (look.LongNeck and 3.5 or hs * 0.9)
end

local function tint(model: Model, color: Color3, amount: number, material: Enum.Material?)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "Root" and p.Name ~= "Eye" and p.Name ~= "EyeWhite" then
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
