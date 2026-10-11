--!strict
-- =====================================================================
--  CLUTCH CLASH – Kosmetik-Modelle (Shared/CosmeticModels)
--  Besitzer: WP9 (Wirtschaft, Monetarisierung, Kosmetik). Vertrag: DESIGN.md C6.3 + B19.
--  Alles aus Parts (keine hochgeladenen Assets, Muss-Regel 1). Daten: Config.Cosmetics.
--
--  Öffentliche API:
--    CosmeticModels.ApplyWrap(model, wrapId)     Farben/Material pro Rolle (Attribut "Role" je Teil);
--        die orange Spitze "Tip" wird NIE verändert. wrapId "" = Original. Animierte Wraps bekommen
--        den Tag "AnimWrap" (+ Attribut "WrapId"), Sparkle/Galaxy zusätzlich einen Funkel-Emitter.
--    CosmeticModels.BuildCharm(id): Model        2–8 Teile, PrimaryPart "Ring" mit Attachment "Hook"
--        (oben; daran hängt das Viewmodel die Feder). Teile unverankert, verschweißt, nicht abfragbar.
--    CosmeticModels.TracerStyle(id, teamColor?): { Color, Width0, Width1, Texture, Transparency,
--        LightEmission, Sparkle, Zigzag }       Helligkeit ≥ 0.5, Transparenz ≤ 0.3 (B19)
--    CosmeticModels.StartAnimator()              Client: animiert Modelle mit Tag "AnimWrap"
--        (10 Hz, nur ≤ 80 Studs zur Kamera oder in einer Vorschau-ViewportFrame). Mehrfach-Aufruf egal.
--    CosmeticModels.CharmRecipes                 [Id] = { Teil-Rezepte }
-- =====================================================================

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config: any = require(Shared:WaitForChild("Config"))

local CosmeticModels = {}

export type CharmPart = {
	Shape: "Block" | "Ball" | "Cylinder" | "Wedge",
	Size: Vector3,
	Offset: CFrame,
	Color: Color3,
	Material: Enum.Material?,
	Transparency: number?,
}

export type TracerStyle = {
	Color: ColorSequence,
	Width0: number,
	Width1: number,
	Texture: string,
	Transparency: NumberSequence,
	LightEmission: number,
	Sparkle: boolean,
	Zigzag: boolean,
}

local ANIM_TAG = "AnimWrap"
local SPARKLE_NAME = "WrapSparkle"
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds" -- ASSETS.md VERIFIED
local WRAP_ROLES: { [string]: boolean } = { Body = true, Detail = true, Accent = true, Metal = true, Grip = true }
local MAX_ANIMATED = 64 -- so viele animierte Modelle höchstens pro Takt
local MIN_TRACER_VALUE = 0.5
local TRACER_TRANSPARENCY = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.05),
	NumberSequenceKeypoint.new(1, 0.3),
})

local rgb = Color3.fromRGB
local COSMETICS: any = Config.Cosmetics
local ANIM_HZ: number = tonumber(COSMETICS and COSMETICS.AnimHz) or 10
local ANIM_RANGE: number = tonumber(COSMETICS and COSMETICS.AnimRange) or 80

-- Material-Namen -> Enum (einmal aufgebaut; unbekannte Namen -> SmoothPlastic)
local MATERIALS: { [string]: Enum.Material } = {}
for _, item in ipairs(Enum.Material:GetEnumItems()) do
	MATERIALS[item.Name] = item
end

local function materialOf(name: any): Enum.Material
	if type(name) == "string" and name ~= "Ice" then -- Muss-Regel 11: nie Ice
		local found = MATERIALS[name]
		if found then
			return found
		end
	end
	return Enum.Material.SmoothPlastic
end

local function wrapDef(wrapId: string?): any
	if type(wrapId) ~= "string" or wrapId == "" or type(COSMETICS) ~= "table" then
		return nil
	end
	return COSMETICS.Wraps and COSMETICS.Wraps[wrapId]
end

local function animList(def: any): { string }
	if def == nil or type(COSMETICS) ~= "table" or type(COSMETICS.AnimList) ~= "function" then
		return {}
	end
	return COSMETICS.AnimList(def)
end

-- Muss-Regel 11: Waffen-, Charm-, Finisher-Teile nie abfragbar/berührbar/kollidierend
local function makeInert(part: BasePart)
	part.CanQuery = false
	part.CanTouch = false
	part.CanCollide = false
	part.Massless = true
	part.CastShadow = false
end

-- =====================================================================
-- 1) WRAPS
-- =====================================================================
local function firstBodyPart(model: Model): BasePart?
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("Role") == "Body" then
			return d
		end
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function setSparkle(model: Model, on: boolean, color: Color3?)
	local holder = firstBodyPart(model)
	if holder == nil then
		return
	end
	local emitter = holder:FindFirstChild(SPARKLE_NAME)
	if not on then
		if emitter then
			emitter:Destroy()
		end
		return
	end
	if emitter == nil or not emitter:IsA("ParticleEmitter") then
		local created = Instance.new("ParticleEmitter")
		created.Name = SPARKLE_NAME
		created.Texture = SPARKLE_TEXTURE
		created.Rate = 4
		created.Lifetime = NumberRange.new(0.4, 0.7)
		created.Speed = NumberRange.new(0.2, 0.6)
		created.SpreadAngle = Vector2.new(180, 180)
		created.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(0.5, 0.16),
			NumberSequenceKeypoint.new(1, 0),
		})
		created.LightEmission = 1
		created.LockedToPart = true
		created.Enabled = false -- der Client-Animator schaltet in Reichweite ein
		created.Parent = holder
		emitter = created
	end
	(emitter :: ParticleEmitter).Color = ColorSequence.new(color or Color3.new(1, 1, 1))
end

function CosmeticModels.ApplyWrap(model: Model, wrapId: string)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	local def = wrapDef(wrapId)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local role = d:GetAttribute("Role")
			if type(role) == "string" and WRAP_ROLES[role] then -- "Tip" bleibt immer orange
				if d:GetAttribute("BaseColor") == nil then
					d:SetAttribute("BaseColor", d.Color)
					d:SetAttribute("BaseMaterial", d.Material.Name)
				end
				local spec = def and def.Roles and def.Roles[role]
				if type(spec) == "table" and typeof(spec.Color) == "Color3" then
					d.Color = spec.Color
					d.Material = materialOf(spec.Material)
				else
					local baseColor = d:GetAttribute("BaseColor")
					if typeof(baseColor) == "Color3" then
						d.Color = baseColor
					end
					d.Material = materialOf(d:GetAttribute("BaseMaterial"))
				end
			end
		end
	end
	local anims = animList(def)
	model:SetAttribute("WrapId", if def then wrapId else "")
	if #anims > 0 then
		CollectionService:AddTag(model, ANIM_TAG)
	else
		CollectionService:RemoveTag(model, ANIM_TAG)
	end
	local sparkle = table.find(anims, "Sparkle") ~= nil or table.find(anims, "Galaxy") ~= nil
	local accent = def and def.Roles and def.Roles.Accent
	setSparkle(model, sparkle, if type(accent) == "table" then accent.Color else nil)
end

-- =====================================================================
-- 2) CHARMS (Rezepte: Teile relativ zum Ring; der Anhänger hängt nach unten)
-- =====================================================================
local CF = CFrame.new
local ANG = CFrame.Angles
local R90 = math.rad(90)
local UP = ANG(0, 0, R90) -- Zylinder aufrecht (Achse Y)
local FACE = ANG(0, R90, 0) -- Zylinder als Scheibe nach vorn
local BLACK = rgb(25, 25, 30)
local GOLD = rgb(255, 200, 40)

local function part(
	shape: "Block" | "Ball" | "Cylinder" | "Wedge",
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material?,
	transparency: number?
): CharmPart
	return {
		Shape = shape,
		Size = size,
		Offset = offset,
		Color = color,
		Material = material,
		Transparency = transparency,
	}
end

local V = Vector3.new
local NEON = Enum.Material.Neon
local FOIL = Enum.Material.Foil

CosmeticModels.CharmRecipes = {
	C_Duck = {
		part("Ball", V(0.34, 0.3, 0.34), CF(0, -0.34, 0), rgb(255, 215, 60)),
		part("Ball", V(0.22, 0.22, 0.22), CF(0, -0.17, -0.08), rgb(255, 215, 60)),
		part("Wedge", V(0.08, 0.06, 0.1), CF(0, -0.18, -0.22) * ANG(0, math.pi, 0), rgb(255, 140, 30)),
		part("Ball", V(0.05, 0.05, 0.05), CF(0.07, -0.14, -0.17), BLACK),
	},
	C_Dice = {
		part("Block", V(0.3, 0.3, 0.3), CF(0, -0.3, 0), rgb(245, 245, 250)),
		part("Ball", V(0.06, 0.06, 0.03), CF(0, -0.3, -0.155), BLACK),
		part("Ball", V(0.06, 0.06, 0.03), CF(0.08, -0.22, -0.155), BLACK),
		part("Ball", V(0.06, 0.06, 0.03), CF(-0.08, -0.38, -0.155), BLACK),
	},
	C_Star = {
		part("Block", V(0.38, 0.1, 0.06), CF(0, -0.3, 0), rgb(255, 220, 60), NEON),
		part("Block", V(0.38, 0.1, 0.06), CF(0, -0.3, 0) * ANG(0, 0, math.rad(60)), rgb(255, 220, 60), NEON),
		part("Block", V(0.38, 0.1, 0.06), CF(0, -0.3, 0) * ANG(0, 0, math.rad(-60)), rgb(255, 220, 60), NEON),
		part("Ball", V(0.14, 0.14, 0.08), CF(0, -0.3, 0), rgb(255, 245, 160)),
	},
	C_Heart = {
		part("Ball", V(0.2, 0.2, 0.12), CF(-0.07, -0.25, 0), rgb(255, 70, 110)),
		part("Ball", V(0.2, 0.2, 0.12), CF(0.07, -0.25, 0), rgb(255, 70, 110)),
		part("Block", V(0.19, 0.19, 0.1), CF(0, -0.32, 0) * ANG(0, 0, math.rad(45)), rgb(255, 70, 110)),
	},
	C_Donut = {
		part("Cylinder", V(0.1, 0.34, 0.34), CF(0, -0.3, 0) * FACE, rgb(225, 170, 100)),
		part("Cylinder", V(0.04, 0.3, 0.3), CF(0, -0.3, -0.055) * FACE, rgb(255, 130, 190)),
		part("Cylinder", V(0.05, 0.1, 0.1), CF(0, -0.3, -0.07) * FACE, rgb(110, 70, 40)),
		part("Block", V(0.05, 0.015, 0.015), CF(0.08, -0.24, -0.08), rgb(90, 220, 255), NEON),
	},
	C_MiniRocket = {
		part("Cylinder", V(0.36, 0.14, 0.14), CF(0, -0.36, 0) * UP, rgb(240, 240, 250)),
		part("Ball", V(0.14, 0.16, 0.14), CF(0, -0.17, 0), rgb(255, 70, 70)),
		part("Wedge", V(0.03, 0.12, 0.1), CF(0.08, -0.5, 0) * ANG(0, R90, 0), rgb(255, 70, 70)),
		part("Wedge", V(0.03, 0.12, 0.1), CF(-0.08, -0.5, 0) * ANG(0, -R90, 0), rgb(255, 70, 70)),
		part("Ball", V(0.1, 0.12, 0.1), CF(0, -0.58, 0), rgb(255, 160, 40), NEON),
	},
	C_CubeBuddy = {
		part("Block", V(0.3, 0.3, 0.3), CF(0, -0.3, 0), rgb(100, 200, 255)),
		part("Ball", V(0.06, 0.06, 0.03), CF(0.07, -0.26, -0.155), BLACK),
		part("Ball", V(0.06, 0.06, 0.03), CF(-0.07, -0.26, -0.155), BLACK),
		part("Block", V(0.1, 0.02, 0.02), CF(0, -0.36, -0.155), BLACK),
	},
	C_Ghost = {
		part("Ball", V(0.3, 0.3, 0.3), CF(0, -0.26, 0), rgb(245, 245, 255), nil, 0.15),
		part("Cylinder", V(0.22, 0.3, 0.3), CF(0, -0.38, 0) * UP, rgb(245, 245, 255), nil, 0.15),
		part("Ball", V(0.06, 0.08, 0.03), CF(0.07, -0.24, -0.15), BLACK),
		part("Ball", V(0.06, 0.08, 0.03), CF(-0.07, -0.24, -0.15), BLACK),
	},
	C_Crown = {
		part("Cylinder", V(0.12, 0.3, 0.3), CF(0, -0.38, 0) * UP, GOLD, FOIL),
		part("Block", V(0.06, 0.14, 0.06), CF(-0.1, -0.27, 0) * ANG(0, 0, math.rad(12)), GOLD, FOIL),
		part("Block", V(0.06, 0.16, 0.06), CF(0, -0.26, 0), GOLD, FOIL),
		part("Block", V(0.06, 0.14, 0.06), CF(0.1, -0.27, 0) * ANG(0, 0, math.rad(-12)), GOLD, FOIL),
		part("Ball", V(0.07, 0.07, 0.04), CF(0, -0.38, -0.15), rgb(255, 50, 90), NEON),
	},
	C_Cactus = {
		part("Cylinder", V(0.12, 0.2, 0.2), CF(0, -0.5, 0) * UP, rgb(205, 110, 70)),
		part("Cylinder", V(0.3, 0.12, 0.12), CF(0, -0.3, 0) * UP, rgb(80, 180, 80)),
		part("Cylinder", V(0.12, 0.07, 0.07), CF(0.1, -0.27, 0) * UP, rgb(80, 180, 80)),
		part("Cylinder", V(0.1, 0.07, 0.07), CF(-0.1, -0.31, 0) * UP, rgb(80, 180, 80)),
	},
	C_Trophy = {
		part("Block", V(0.18, 0.06, 0.12), CF(0, -0.52, 0), rgb(60, 50, 40)),
		part("Cylinder", V(0.12, 0.05, 0.05), CF(0, -0.43, 0) * UP, GOLD, FOIL),
		part("Cylinder", V(0.16, 0.2, 0.2), CF(0, -0.29, 0) * UP, GOLD, FOIL),
		part("Ball", V(0.07, 0.07, 0.07), CF(0.12, -0.29, 0), GOLD, FOIL),
		part("Ball", V(0.07, 0.07, 0.07), CF(-0.12, -0.29, 0), GOLD, FOIL),
	},
	C_CalendarCat = {
		part("Ball", V(0.28, 0.26, 0.26), CF(0, -0.3, 0), rgb(255, 160, 70)),
		part("Wedge", V(0.04, 0.1, 0.08), CF(0.08, -0.15, 0) * ANG(0, R90, 0), rgb(255, 160, 70)),
		part("Wedge", V(0.04, 0.1, 0.08), CF(-0.08, -0.15, 0) * ANG(0, R90, 0), rgb(255, 160, 70)),
		part("Ball", V(0.05, 0.06, 0.03), CF(0.06, -0.28, -0.13), BLACK),
		part("Ball", V(0.05, 0.06, 0.03), CF(-0.06, -0.28, -0.13), BLACK),
		part("Ball", V(0.03, 0.03, 0.03), CF(0, -0.33, -0.135), rgb(255, 120, 160)),
	},
	C_StarterStar = {
		part("Block", V(0.38, 0.1, 0.06), CF(0, -0.3, 0), rgb(255, 90, 90), NEON),
		part("Block", V(0.38, 0.1, 0.06), CF(0, -0.3, 0) * ANG(0, 0, math.rad(60)), rgb(80, 220, 255), NEON),
		part("Block", V(0.38, 0.1, 0.06), CF(0, -0.3, 0) * ANG(0, 0, math.rad(-60)), rgb(150, 255, 120), NEON),
		part("Ball", V(0.14, 0.14, 0.08), CF(0, -0.3, 0), rgb(255, 255, 255), NEON),
	},
} :: { [string]: { CharmPart } }

local DEFAULT_CHARM: { CharmPart } = { part("Ball", V(0.24, 0.24, 0.24), CF(0, -0.28, 0), rgb(200, 200, 210)) }

local function newPart(shape: string): BasePart
	if shape == "Wedge" then
		return Instance.new("WedgePart")
	end
	local p = Instance.new("Part")
	if shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	elseif shape == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	else
		p.Shape = Enum.PartType.Block
	end
	return p
end

function CosmeticModels.BuildCharm(id: string): Model
	local recipe = CosmeticModels.CharmRecipes[id] or DEFAULT_CHARM
	local model = Instance.new("Model")
	model.Name = if type(id) == "string" then id else "Charm"
	model:SetAttribute("CharmId", id)
	local ring = newPart("Cylinder")
	ring.Name = "Ring"
	ring.Size = V(0.05, 0.16, 0.16)
	ring.CFrame = CFrame.identity
	ring.Color = rgb(200, 205, 215)
	ring.Material = Enum.Material.Metal
	ring.Anchored = false
	makeInert(ring)
	ring.Parent = model
	local hook = Instance.new("Attachment")
	hook.Name = "Hook"
	hook.Position = V(0, 0.08, 0)
	hook.Parent = ring
	for i, spec in ipairs(recipe) do
		if i > 7 then
			break -- Budget: höchstens 8 Teile inkl. Ring (C17)
		end
		local p = newPart(spec.Shape)
		p.Name = "Part" .. i
		p.Size = spec.Size
		p.CFrame = spec.Offset
		p.Color = spec.Color
		p.Material = spec.Material or Enum.Material.SmoothPlastic
		p.Transparency = spec.Transparency or 0
		p.Anchored = false
		makeInert(p)
		p.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = ring
		weld.Part1 = p
		weld.Parent = p
	end
	model.PrimaryPart = ring
	return model
end

-- =====================================================================
-- 3) TRACER-STIL
-- =====================================================================
local function brighten(color: Color3): Color3
	local h, s, v = color:ToHSV()
	if v < MIN_TRACER_VALUE then
		v = MIN_TRACER_VALUE
	end
	return Color3.fromHSV(h, s, v)
end

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, rgb(255, 70, 70)),
	ColorSequenceKeypoint.new(0.2, rgb(255, 170, 40)),
	ColorSequenceKeypoint.new(0.4, rgb(255, 240, 70)),
	ColorSequenceKeypoint.new(0.6, rgb(80, 230, 110)),
	ColorSequenceKeypoint.new(0.8, rgb(70, 160, 255)),
	ColorSequenceKeypoint.new(1, rgb(190, 90, 255)),
})

function CosmeticModels.TracerStyle(id: string, teamColor: Color3?): TracerStyle
	local tracers = COSMETICS and COSMETICS.Tracers or {}
	local def = tracers[id] or tracers.T_Team or {}
	local color: ColorSequence
	if def.Color == "Rainbow" then
		color = RAINBOW
	elseif typeof(def.Color) == "Color3" then
		color = ColorSequence.new(brighten(def.Color))
	else -- "Team": Teamfarbe des Schützen (oder Weiß)
		color = ColorSequence.new(brighten(teamColor or Color3.new(1, 1, 1)))
	end
	return {
		Color = color,
		Width0 = tonumber(def.Width0) or 0.12,
		Width1 = tonumber(def.Width1) or 0.05,
		Texture = if type(def.Texture) == "string" then def.Texture else "",
		Transparency = TRACER_TRANSPARENCY,
		LightEmission = 1,
		Sparkle = def.Sparkle == true,
		Zigzag = def.Zigzag == true,
	}
end

-- =====================================================================
-- 4) ANIMATOR (Client, 10 Hz, ≤ 80 Studs)
-- =====================================================================
type AnimCache = { WrapId: string, Body: { BasePart }, Detail: { BasePart }, Accent: { BasePart }, Anims: { string } }

local animatorStarted = false
local cache: { [Model]: AnimCache } = setmetatable({}, { __mode = "k" }) :: any

local function buildCache(model: Model, wrapId: string): AnimCache
	local entry: AnimCache = { WrapId = wrapId, Body = {}, Detail = {}, Accent = {}, Anims = animList(wrapDef(wrapId)) }
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local role = d:GetAttribute("Role")
			if role == "Body" then
				table.insert(entry.Body, d)
			elseif role == "Detail" then
				table.insert(entry.Detail, d)
			elseif role == "Accent" then
				table.insert(entry.Accent, d)
			end
		end
	end
	return entry
end

local function setColors(parts: { BasePart }, color: Color3)
	for _, p in ipairs(parts) do
		if p.Color ~= color then
			p.Color = color
		end
	end
end

local function animateModel(entry: AnimCache, t: number)
	local def = wrapDef(entry.WrapId)
	if def == nil then
		return
	end
	for _, anim in ipairs(entry.Anims) do
		if anim == "Pulse" then
			local accent = def.Roles and def.Roles.Accent
			local base: Color3 = if type(accent) == "table" and typeof(accent.Color) == "Color3"
				then accent.Color
				else Color3.new(1, 1, 1)
			local alpha = (math.sin(t * 4) + 1) * 0.3
			setColors(entry.Accent, base:Lerp(Color3.new(1, 1, 1), alpha))
		elseif anim == "Rainbow" then
			setColors(entry.Body, Color3.fromHSV((t * 0.25) % 1, 0.7, 1))
			setColors(entry.Detail, Color3.fromHSV((t * 0.25 + 0.33) % 1, 0.6, 1))
		elseif anim == "Galaxy" then
			local alpha = (math.sin(t * 1.5) + 1) / 2
			setColors(entry.Body, rgb(25, 15, 70):Lerp(rgb(110, 40, 190), alpha))
			setColors(entry.Accent, Color3.fromHSV(0.6 + 0.25 * alpha, 0.6, 1))
		end
	end
end

local function inPreview(model: Model): boolean
	return model:FindFirstAncestorWhichIsA("ViewportFrame") ~= nil
end

local function step(t: number)
	local camera = workspace.CurrentCamera
	local camPos = if camera then camera.CFrame.Position else Vector3.zero
	local tagged = CollectionService:GetTagged(ANIM_TAG)
	for i, inst in ipairs(tagged) do
		if i > MAX_ANIMATED then
			break
		end
		if inst:IsA("Model") then
			local model = inst :: Model
			local near = inPreview(model)
			if not near and model:IsDescendantOf(workspace) then
				near = (model:GetPivot().Position - camPos).Magnitude <= ANIM_RANGE
			end
			local wrapId = model:GetAttribute("WrapId")
			local id = if type(wrapId) == "string" then wrapId else ""
			local entry = cache[model]
			if entry == nil or entry.WrapId ~= id then
				entry = buildCache(model, id)
				cache[model] = entry
			end
			local holder = firstBodyPart(model)
			local emitter = holder and holder:FindFirstChild(SPARKLE_NAME)
			if emitter and emitter:IsA("ParticleEmitter") and emitter.Enabled ~= near then
				emitter.Enabled = near
			end
			if near then
				animateModel(entry, t)
			end
		end
	end
end

function CosmeticModels.StartAnimator()
	if animatorStarted or not RunService:IsClient() then
		return
	end
	animatorStarted = true
	local interval = 1 / math.max(1, ANIM_HZ)
	local acc = 0
	local clock = 0
	local lastWarn = -math.huge
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		clock += dt
		if acc < interval then
			return
		end
		acc = 0
		local ok, err = pcall(function()
			step(clock)
		end)
		if not ok and clock - lastWarn >= 10 then -- Fehler höchstens alle 10 s melden
			lastWarn = clock
			warn("[CosmeticModels] Animator: " .. tostring(err))
		end
	end)
end

return CosmeticModels
