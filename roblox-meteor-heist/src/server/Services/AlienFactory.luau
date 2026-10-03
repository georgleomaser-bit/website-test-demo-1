--!strict
-- Baut das Aussehen eines Aliens (schlüpft aus einem Meteor) aus wenigen einfachen Teilen:
-- Körperform nach "Archetype" (Aliens.luau), Farben, Material/Farbe nach Mutation,
-- Effekte (Regenbogen, Aura, Umriss, Licht) und Namensschild darüber.
--
--  * Pivot (model:GetPivot()) = Bodenmitte -> model:PivotTo(Pad-Oberseite) stellt das Alien aufs Pad.
--  * Das Gesicht zeigt in Blickrichtung des Pivots (LookVector / lokales -Z).
--  * Alle Teile sind verankert, ohne Kollision. Nur "Body" (PrimaryPart) ist abfragbar (für Prompts).
--  * Höchstens 12 Teile pro Alien (Admin: 16), damit auch volle Basen nicht laggen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")) :: any
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))
local Aliens = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Aliens"))

type AlienDef = Aliens.AlienDef
type Entry = { Id: string, Alien: string?, Mut: string?, Lv: number? }

type Ctx = {
	model: Model,
	s: number, -- Gesamt-Skalierung (Seltenheit * Stufe * Modus * Level)
	color: Color3,
	accent: Color3,
	eyes: number,
	antennas: number,
	mutName: string,
	mutColor: Color3?,
	rainbow: boolean,
	carry: boolean,
	darkFace: boolean, -- sehr dunkles Gesicht -> leuchtende statt schwarze Knopfaugen
	mainMaterial: Enum.Material,
	mainTransparency: number,
	mainReflectance: number,
	count: number,
	max: number,
	top: number, -- höchster Punkt (unskaliert)
}

type Builder = (ctx: Ctx) -> (Part, number)

local AlienFactory = {}

local MAX_PARTS = 12
local MAX_PARTS_ADMIN = 16
local ADMIN_RANK = 10
local LEVEL_GROWTH = 0.012 -- +1,2% Größe pro Level (Level 20 = +23%)
local LABEL_GAP = 1.6
local SHADOW_MIN_VOLUME = 15 -- nur große Teile werfen Schatten (bewegte Schattenwerfer kosten viel)
local MODE_SCALE: { [string]: number } = { Base = 1, Photo = 1, Carry = 0.55 }

local DARK = Color3.fromRGB(25, 22, 30)
local WHITE = Color3.fromRGB(250, 250, 255)
local GOLD = Color3.fromRGB(255, 200, 40)
local STALK = Color3.fromRGB(245, 235, 215)
local METAL = Color3.fromRGB(70, 72, 82)
local ROCK = Color3.fromRGB(70, 65, 75)
local BLACK = Color3.new(0, 0, 0)
local FALLBACK_RARITY_COLORS: { [string]: Color3 } = { Admin = Color3.fromRGB(255, 40, 40) }

local RAINBOW_SEQUENCE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 60)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 200, 40)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(80, 255, 80)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(60, 220, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(90, 90, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 60, 220)),
})

local warned: { [string]: boolean } = {}
local function warnOnce(key: string, message: string)
	if not warned[key] then
		warned[key] = true
		warn(message)
	end
end

-- -------------------------------------------------------------------
-- Nachschlagen (robust, falls Config gerade etwas nicht kennt)
-- -------------------------------------------------------------------
local function resolveAlien(entry: Entry): AlienDef
	local alien = entry.Alien and Aliens.ById[entry.Alien]
	if alien then
		return alien
	end
	local options = Aliens.ByMeteor[entry.Id]
	local fallback = options and options[1] and Aliens.ById[options[1].Id] or Aliens.List[1]
	warnOnce(
		"alien:" .. tostring(entry.Alien) .. ":" .. tostring(entry.Id),
		"[AlienFactory] Unbekanntes Alien '" .. tostring(entry.Alien) .. "' -> zeige " .. fallback.Id
	)
	return fallback
end

local function rarityRank(rarityName: string): number
	local index = Config.RarityIndex and Config.RarityIndex[rarityName]
	return index or Aliens.RarityRank[rarityName] or 1
end

local function rarityColor(rarityName: string): Color3
	local rarity = Config.RaritiesByName and Config.RaritiesByName[rarityName]
	return rarity and rarity.Color or FALLBACK_RARITY_COLORS[rarityName] or WHITE
end

local function getMutation(name: string?): any
	local byName = Config.MutationsByName or {}
	return byName[name or "Normal"] or (Config.Mutations and Config.Mutations[1]) or { Name = "Normal", Mult = 1 }
end

local function maxLevel(): number
	return tonumber(Config.MaxLevel) or 20
end

local function levelOf(entry: Entry): number
	local lv = tonumber(entry.Lv) or 1
	if lv ~= lv then
		return 1
	end
	return math.clamp(math.floor(lv), 1, math.max(1, maxLevel()))
end

local function levelScale(lv: number): number
	return 1 + LEVEL_GROWTH * (lv - 1)
end

-- Farbe der Fläche, auf der das Gesicht sitzt (für die Wahl der Augenfarbe)
local function faceColorOf(look: Aliens.AlienLook, mut: any): Color3
	if look.Archetype == "Mushroom" then
		return STALK
	end
	local base: Color3 = typeof(mut.Color) == "Color3" and mut.Name ~= "Normal" and mut.Color or look.Color
	if look.Archetype == "Bug" then
		return base:Lerp(BLACK, 0.35)
	end
	return base
end

-- -------------------------------------------------------------------
-- Geometrie-Helfer (alle Maße unskaliert, Ursprung = Bodenmitte, vorne = -Z)
-- -------------------------------------------------------------------
local function room(ctx: Ctx, amount: number): boolean
	return ctx.count + amount <= ctx.max
end

-- Halbe Höhe eines gedrehten Quaders (für den höchsten Punkt)
local function halfHeight(cf: CFrame, size: Vector3): number
	return (math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y + math.abs(cf.LookVector.Y) * size.Z)
		/ 2
end

-- CFrame, dessen X-Achse in Richtung "axis" zeigt (für Zylinder, Stäbe, Tentakel)
local function axisCFrame(center: Vector3, axis: Vector3): CFrame
	local x = axis.Magnitude > 1e-4 and axis.Unit or Vector3.xAxis
	local ref = math.abs(x.Y) < 0.9 and Vector3.yAxis or Vector3.zAxis
	local z = x:Cross(ref).Unit
	local y = z:Cross(x).Unit
	return CFrame.fromMatrix(center, x, y, z)
end

-- CFrame an "pos", dessen Vorderseite (-Z) in Richtung "normal" zeigt
local function facing(pos: Vector3, normal: Vector3): CFrame
	local n = normal.Magnitude > 1e-4 and normal.Unit or -Vector3.zAxis
	local up = math.abs(n.Y) < 0.95 and Vector3.yAxis or Vector3.zAxis
	return CFrame.lookAt(pos, pos + n, up)
end

-- Punkt + Normale auf der Vorderseite (-Z) eines Ellipsoids bei Höhe y und seitlich x
local function frontPoint(center: Vector3, radii: Vector3, x: number, y: number): (Vector3, Vector3)
	local dx = (x - center.X) / radii.X
	local dy = (y - center.Y) / radii.Y
	local depth = math.sqrt(math.max(0, 1 - dx * dx - dy * dy))
	local point = Vector3.new(x, y, center.Z - radii.Z * depth)
	local rel = point - center
	local normal = Vector3.new(rel.X / radii.X ^ 2, rel.Y / radii.Y ^ 2, rel.Z / radii.Z ^ 2)
	return point, normal.Magnitude > 1e-4 and normal.Unit or -Vector3.zAxis
end

-- Höhe der Oberseite eines Ellipsoids bei (x, z)
local function topY(center: Vector3, radii: Vector3, x: number, z: number): number
	local dx = (x - center.X) / radii.X
	local dz = (z - center.Z) / radii.Z
	return center.Y + radii.Y * math.sqrt(math.max(0, 1 - dx * dx - dz * dz))
end

local function styleRole(ctx: Ctx, part: Part, role: string)
	local material = Enum.Material.SmoothPlastic
	local color = ctx.color
	local transparency = 0
	local reflectance = 0
	if role == "Main" or role == "Shade" then
		material = ctx.mainMaterial
		transparency = ctx.mainTransparency
		reflectance = ctx.mainReflectance
		local mutColor = ctx.mutColor
		if ctx.mutName == "Gold" and mutColor then
			material = Enum.Material.Foil
			color = mutColor
			reflectance = 0
		elseif ctx.mutName == "Diamond" and mutColor then
			material = Enum.Material.Glass
			color = mutColor
			transparency = math.max(transparency, 0.15)
			reflectance = 0
		elseif ctx.mutName == "Cosmic" and mutColor then
			material = Enum.Material.Neon
			color = mutColor
			reflectance = 0
		end
		if role == "Shade" then
			color = color:Lerp(BLACK, 0.35)
		elseif ctx.rainbow then
			part:SetAttribute("Rainbow", true)
		end
	elseif role == "Accent" then
		color = ctx.accent
	elseif role == "Glow" then
		color = ctx.accent
		material = Enum.Material.Neon
		if ctx.rainbow then
			part:SetAttribute("Rainbow", true)
		end
	elseif role == "Dark" then
		color = DARK
		reflectance = 0.25
	elseif role == "White" then
		color = WHITE
	elseif role == "Gold" then
		color = GOLD
		material = Enum.Material.Foil
	elseif role == "Stalk" then
		color = STALK
	elseif role == "Metal" then
		color = METAL
		reflectance = 0.2
	elseif role == "Rock" then
		color = ctx.color:Lerp(ROCK, 0.65)
		material = Enum.Material.Slate
	elseif role == "Cape" then
		color = ctx.accent
		material = Enum.Material.Fabric
	end
	part.Material = material
	part.Color = color
	part.Transparency = transparency
	part.Reflectance = reflectance
end

-- shape: "Block" (Standard), "Ball", "Cylinder" (Achse = X) oder "Ellipsoid"
local function makePart(ctx: Ctx, name: string, role: string, size: Vector3, cf: CFrame, shape: string?): Part
	ctx.count += 1
	local s = ctx.s
	local part = Instance.new("Part")
	part.Name = name
	if shape == "Ball" then
		part.Shape = Enum.PartType.Ball
	elseif shape == "Cylinder" then
		part.Shape = Enum.PartType.Cylinder
	elseif shape == "Ellipsoid" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end
	part.Size = size * s
	part.CFrame = CFrame.new(cf.Position * s) * cf.Rotation
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	local scaled = part.Size
	part.CastShadow = not ctx.carry and scaled.X * scaled.Y * scaled.Z >= SHADOW_MIN_VOLUME
	if ctx.carry then
		part.Massless = true
	end
	styleRole(ctx, part, role)
	ctx.top = math.max(ctx.top, cf.Position.Y + halfHeight(cf, size))
	part.Parent = ctx.model
	return part
end

-- Wie makePart, aber nur wenn noch Platz im Teile-Budget ist
local function tryPart(ctx: Ctx, name: string, role: string, size: Vector3, cf: CFrame, shape: string?): Part?
	if not room(ctx, 1) then
		return nil
	end
	return makePart(ctx, name, role, size, cf, shape)
end

-- Länglicher Teil von "from" nach "to" (Arme, Beine, Tentakel, Antennen)
local function stick(
	ctx: Ctx,
	name: string,
	role: string,
	from: Vector3,
	to: Vector3,
	thickness: number,
	shape: string
): Part?
	local axis = to - from
	return tryPart(
		ctx,
		name,
		role,
		Vector3.new(axis.Magnitude, thickness, thickness),
		axisCFrame((from + to) / 2, axis),
		shape
	)
end

-- -------------------------------------------------------------------
-- Gesicht: Augen, Mund, Antennen
-- -------------------------------------------------------------------
-- style: "Big" (weiß + Pupille), "Beady" (glänzend schwarz), "Oval" (Geist), "Glow" (Roboter)
local function eyeParts(style: string): number
	return style == "Big" and 2 or 1
end

local function addEye(ctx: Ctx, pos: Vector3, normal: Vector3, size: number, style: string)
	local cf = facing(pos, normal)
	if style == "Big" then
		makePart(ctx, "Eye", "White", Vector3.one * size, cf, "Ball")
		makePart(ctx, "Pupil", "Dark", Vector3.one * size * 0.5, cf * CFrame.new(0, 0, -size * 0.32), "Ball")
	elseif style == "Oval" then
		local role = ctx.darkFace and "Glow" or "Dark"
		makePart(ctx, "Eye", role, Vector3.new(size * 0.6, size, size * 0.35), cf, "Ellipsoid")
	elseif style == "Glow" then
		makePart(ctx, "Eye", "Glow", Vector3.new(size, size * 0.7, size * 0.4), cf, "Block")
	else
		makePart(ctx, "Eye", ctx.darkFace and "Glow" or "Dark", Vector3.one * size, cf, "Ball")
	end
end

-- Seitliche Versätze (x, Höhe) für n Augen
local function eyeLayout(n: number, spread: number): { Vector2 }
	if n <= 1 then
		return { Vector2.zero }
	elseif n == 2 then
		return { Vector2.new(-spread, 0), Vector2.new(spread, 0) }
	elseif n == 3 then
		return { Vector2.new(-spread * 1.15, -0.05), Vector2.new(0, 0.2), Vector2.new(spread * 1.15, -0.05) }
	end
	return {
		Vector2.new(-spread * 1.5, -0.12),
		Vector2.new(-spread * 0.5, 0.05),
		Vector2.new(spread * 0.5, 0.05),
		Vector2.new(spread * 1.5, -0.12),
	}
end

-- Passt den Augen-Stil ans Budget an (Big -> Beady), damit immer alle Augen da sind
local function fitEyeStyle(ctx: Ctx, n: number, style: string): string
	if not room(ctx, n * eyeParts(style)) then
		return style == "Big" and "Beady" or style
	end
	return style
end

local function addEyesOnEllipsoid(
	ctx: Ctx,
	center: Vector3,
	radii: Vector3,
	y: number,
	spread: number,
	size: number,
	style: string
)
	local n = ctx.eyes
	if n >= 3 and style == "Big" then
		style = "Beady"
		size *= 0.75
	end
	style = fitEyeStyle(ctx, n, style)
	local embed = style == "Big" and 0.15 or 0.08
	for _, offset in ipairs(eyeLayout(n, spread)) do
		local point, normal = frontPoint(center, radii, offset.X, y + offset.Y)
		addEye(ctx, point + normal * (size * embed), normal, size, style)
	end
end

local function addMouthOnEllipsoid(ctx: Ctx, center: Vector3, radii: Vector3, y: number, width: number)
	if not room(ctx, 1) then
		return
	end
	local point, normal = frontPoint(center, radii, 0, y)
	makePart(ctx, "Mouth", "Dark", Vector3.new(width, 0.24, 0.3), facing(point, normal), "Ellipsoid")
end

-- Antennen mit leuchtender Kugel. Weniger Platz im Budget -> erst ohne Kugel, dann weniger Antennen.
-- baseYAt(x) liefert die Höhe der Kopf-Oberseite an der Stelle x.
local function addAntennas(
	ctx: Ctx,
	baseYAt: (x: number) -> number,
	z: number,
	spread: number,
	length: number,
	lean: number,
	tilt: number
)
	local n = ctx.antennas
	local perAntenna = 2
	while n > 0 and not room(ctx, n * perAntenna) do
		if perAntenna == 2 then
			perAntenna = 1
		else
			perAntenna = 2
			n -= 1
		end
	end
	if n <= 0 then
		return
	end
	local xs = n == 1 and { 0 } or (n == 2 and { -spread, spread } or { -spread, 0, spread })
	for _, x in ipairs(xs) do
		local side = x > 0 and 1 or (x < 0 and -1 or 0)
		local dir = Vector3.new(side * math.sin(lean), math.cos(lean), -math.sin(tilt)).Unit
		local base = Vector3.new(x, baseYAt(x) - 0.05, z)
		local tip = base + dir * length
		stick(ctx, "Antenna", "Shade", base, tip, 0.14, "Cylinder")
		if perAntenna == 2 then
			tryPart(ctx, "AntennaTip", "Glow", Vector3.one * 0.38, CFrame.new(tip), "Ball")
		end
	end
end

-- -------------------------------------------------------------------
-- KÖRPERFORMEN – jede gibt (Body, Höhe der Body-Mitte) zurück
-- -------------------------------------------------------------------
local Builders: { [string]: Builder } = {}

-- Schleim-Tropfen mit Bäckchen
Builders.Blob = function(ctx: Ctx): (Part, number)
	local c = Vector3.new(0, 1.2, 0)
	local r = Vector3.new(1.5, 1.2, 1.5)
	local body = makePart(ctx, "Body", "Main", r * 2, CFrame.new(c), "Ellipsoid")
	local topC = Vector3.new(0, 2.15, 0.1)
	local topR = Vector3.new(0.85, 0.65, 0.85)
	makePart(ctx, "Top", "Main", topR * 2, CFrame.new(topC), "Ellipsoid")
	addEyesOnEllipsoid(ctx, c, r, 1.55, 0.55, 0.75, "Big")
	addAntennas(ctx, function(x)
		return topY(topC, topR, x, topC.Z)
	end, topC.Z, 0.4, 0.9, math.rad(20), 0)
	addMouthOnEllipsoid(ctx, c, r, 0.8, 0.7)
	if room(ctx, 2) then
		for _, side in ipairs({ -1, 1 }) do
			local point, normal = frontPoint(c, r, side * 0.95, 0.95)
			makePart(ctx, "Cheek", "Accent", Vector3.new(0.45, 0.28, 0.15), facing(point, normal), "Ellipsoid")
		end
	end
	return body, c.Y
end

-- Einäugiger Riese mit Füßen und Armen
Builders.Cyclops = function(ctx: Ctx): (Part, number)
	local c = Vector3.new(0, 1.95, 0)
	local r = Vector3.new(1.3, 1.5, 1.2)
	local body = makePart(ctx, "Body", "Main", r * 2, CFrame.new(c), "Ellipsoid")
	for _, side in ipairs({ -1, 1 }) do
		makePart(ctx, "Foot", "Shade", Vector3.new(0.9, 0.5, 1.1), CFrame.new(side * 0.55, 0.25, -0.1), "Ellipsoid")
	end
	if ctx.eyes == 1 then
		local point, normal = frontPoint(c, r, 0, 2.35)
		local eyeCenter = point + normal * 0.2
		local cf = facing(eyeCenter, normal)
		makePart(ctx, "Eye", "White", Vector3.one * 1.35, cf, "Ball")
		makePart(ctx, "Iris", "Accent", Vector3.one * 0.8, cf * CFrame.new(0, 0, -0.42), "Ball")
		makePart(ctx, "Pupil", "Dark", Vector3.one * 0.42, cf * CFrame.new(0, 0, -0.68), "Ball")
	else
		addEyesOnEllipsoid(ctx, c, r, 2.35, 0.5, 0.7, "Big")
	end
	addAntennas(ctx, function(x)
		return topY(c, r, x, 0)
	end, 0, 0.45, 0.85, math.rad(25), 0)
	addMouthOnEllipsoid(ctx, c, r, 1.35, 0.9)
	if room(ctx, 2) then
		for _, side in ipairs({ -1, 1 }) do
			stick(
				ctx,
				"Arm",
				"Main",
				Vector3.new(side * 1.1, 2.0, 0),
				Vector3.new(side * 1.5, 1.3, -0.15),
				0.5,
				"Ellipsoid"
			)
		end
	end
	return body, c.Y
end

-- Tintenfisch mit Tentakeln
Builders.Squid = function(ctx: Ctx): (Part, number)
	local c = Vector3.new(0, 2.6, 0)
	local r = Vector3.new(1.3, 1.5, 1.3)
	local body = makePart(ctx, "Body", "Main", r * 2, CFrame.new(c), "Ellipsoid")
	local function tentacle(angle: number, reach: number)
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		stick(
			ctx,
			"Tentacle",
			"Main",
			dir * 0.6 + Vector3.new(0, 1.4, 0),
			dir * reach + Vector3.new(0, 0.2, 0),
			0.5,
			"Ellipsoid"
		)
	end
	for i = 0, 3 do
		tentacle(math.rad(45 + 90 * i), 1.35)
	end
	addEyesOnEllipsoid(ctx, c, r, 2.45, 0.55, 0.75, "Big")
	addAntennas(ctx, function(x)
		return topY(c, r, x, 0)
	end, 0, 0.45, 0.85, math.rad(20), 0)
	if room(ctx, 2) then
		tentacle(0, 1.45)
		tentacle(math.pi, 1.45)
	end
	if room(ctx, 2) then
		tentacle(math.rad(90), 1.35)
		tentacle(math.rad(-90), 1.2)
	end
	return body, c.Y
end

-- Käfer mit Panzer, Kopf, Beinen und Fühlern
Builders.Bug = function(ctx: Ctx): (Part, number)
	local c = Vector3.new(0, 1.25, 0.25)
	local r = Vector3.new(1.3, 0.85, 1.4)
	local body = makePart(ctx, "Body", "Main", r * 2, CFrame.new(c), "Ellipsoid")
	local headC = Vector3.new(0, 1.2, -1.25)
	local headR = Vector3.new(0.8, 0.65, 0.6)
	makePart(ctx, "Head", "Shade", headR * 2, CFrame.new(headC), "Ellipsoid")
	for _, side in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -0.35, 0.75 }) do
			stick(
				ctx,
				"Leg",
				"Dark",
				Vector3.new(side * 0.9, 0.8, z),
				Vector3.new(side * 1.5, 0.05, z + 0.15),
				0.2,
				"Cylinder"
			)
		end
	end
	addEyesOnEllipsoid(ctx, headC, headR, 1.35, 0.32, 0.45, "Beady")
	addAntennas(ctx, function(x)
		return topY(headC, headR, x, headC.Z)
	end, headC.Z, 0.25, 0.9, math.rad(25), math.rad(30))
	if room(ctx, 2) then
		for _, side in ipairs({ -1, 1 }) do
			local x, z = side * 0.55, 0.6
			makePart(ctx, "Spot", "Accent", Vector3.one * 0.55, CFrame.new(x, topY(c, r, x, z) - 0.08, z), "Ball")
		end
	end
	return body, c.Y
end

-- Roboter auf Ketten mit Visier
Builders.Robot = function(ctx: Ctx): (Part, number)
	makePart(ctx, "Treads", "Metal", Vector3.new(2.2, 0.6, 1.8), CFrame.new(0, 0.3, 0))
	local bodyY = 1.55
	local body = makePart(ctx, "Body", "Main", Vector3.new(2.4, 1.9, 1.8), CFrame.new(0, bodyY, 0))
	makePart(ctx, "Head", "Main", Vector3.new(1.8, 1.3, 1.5), CFrame.new(0, 3.15, 0))
	makePart(ctx, "Visor", "Dark", Vector3.new(1.5, 0.6, 0.12), CFrame.new(0, 3.2, -0.76))
	local style = fitEyeStyle(ctx, ctx.eyes, "Glow")
	for _, offset in ipairs(eyeLayout(ctx.eyes, 0.42)) do
		addEye(ctx, Vector3.new(offset.X, 3.2 + offset.Y * 0.5, -0.84), -Vector3.zAxis, 0.32, style)
	end
	if room(ctx, 2) then
		for _, side in ipairs({ -1, 1 }) do
			makePart(
				ctx,
				"Arm",
				"Shade",
				Vector3.new(0.45, 1.4, 0.45),
				CFrame.new(side * 1.42, 1.5, 0) * CFrame.Angles(0, 0, math.rad(side * 8))
			)
		end
	end
	addAntennas(ctx, function()
		return 3.8
	end, 0, 0.5, 0.8, math.rad(15), 0)
	tryPart(ctx, "ChestLight", "Glow", Vector3.one * 0.5, CFrame.new(0, 1.75, -0.88), "Ball")
	tryPart(ctx, "Grill", "Dark", Vector3.new(0.8, 0.14, 0.1), CFrame.new(0, 2.75, -0.76))
	return body, bodyY
end

-- Schwebendes Gespenst
Builders.Ghost = function(ctx: Ctx): (Part, number)
	ctx.mainTransparency = math.max(ctx.mainTransparency, 0.1)
	local c = Vector3.new(0, 2.55, 0)
	local r = Vector3.new(1.3, 1.45, 1.25)
	local body = makePart(ctx, "Body", "Main", r * 2, CFrame.new(c), "Ellipsoid")
	makePart(ctx, "Tail", "Main", Vector3.new(1.9, 1.6, 1.9), CFrame.new(0, 1.35, 0.15), "Ellipsoid")
	addEyesOnEllipsoid(ctx, c, r, 2.8, 0.48, 0.75, "Oval")
	addAntennas(ctx, function(x)
		return topY(c, r, x, 0)
	end, 0, 0.45, 0.8, math.rad(20), 0)
	if room(ctx, 1) then
		local point, normal = frontPoint(c, r, 0, 2.05)
		makePart(ctx, "Mouth", "Dark", Vector3.new(0.5, 0.6, 0.25), facing(point, normal), "Ellipsoid")
	end
	if room(ctx, 2) then
		for _, side in ipairs({ -1, 1 }) do
			stick(
				ctx,
				"Arm",
				"Main",
				Vector3.new(side * 1.05, 2.5, 0),
				Vector3.new(side * 1.45, 1.95, -0.25),
				0.55,
				"Ellipsoid"
			)
		end
	end
	if room(ctx, 3) then
		for i = 0, 2 do
			local angle = math.rad(90 + 120 * i)
			makePart(
				ctx,
				"Wisp",
				"Main",
				Vector3.one * 0.7,
				CFrame.new(math.cos(angle) * 0.6, 0.55, math.sin(angle) * 0.6),
				"Ball"
			)
		end
	end
	return body, c.Y
end

-- Lebender Edelstein (Würfel auf der Spitze) auf einem Felsen, mit leuchtenden Splittern
Builders.Crystal = function(ctx: Ctx): (Part, number)
	ctx.mainReflectance = math.max(ctx.mainReflectance, 0.2)
	makePart(ctx, "Rock", "Rock", Vector3.new(3.0, 0.8, 3.0), CFrame.new(0, 0.4, 0), "Ellipsoid")
	-- Die 3 oberen Würfelflächen zeigen schräg nach oben, eine davon genau nach vorne (-Z)
	local a, b = 1 / math.sqrt(3), math.sqrt(2 / 3)
	local h = math.sqrt(3) / 2
	local front = Vector3.new(0, a, -b)
	local backLeft = Vector3.new(-h * b, a, 0.5 * b)
	local backRight = Vector3.new(h * b, a, 0.5 * b)
	local side = 2.0
	local bodyY = 0.45 + side * h
	local c = Vector3.new(0, bodyY, 0)
	local body = makePart(ctx, "Body", "Main", Vector3.one * side, CFrame.fromMatrix(c, front, backLeft, backRight))
	-- Gesicht auf der vorderen Fläche (von vorne gesehen eine Raute)
	local faceCenter = c + front * (side / 2)
	local faceUp = Vector3.new(0, b, a)
	local style = fitEyeStyle(ctx, ctx.eyes, ctx.eyes >= 3 and "Beady" or "Big")
	local size = style == "Big" and 0.6 or 0.42
	for _, offset in ipairs(eyeLayout(ctx.eyes, 0.38)) do
		local pos = faceCenter + Vector3.xAxis * offset.X + faceUp * (0.2 + offset.Y) + front * (size * 0.2)
		addEye(ctx, pos, front, size, style)
	end
	if room(ctx, 1) then
		makePart(ctx, "Mouth", "Dark", Vector3.new(0.5, 0.14, 0.1), facing(faceCenter - faceUp * 0.45, front))
	end
	addAntennas(ctx, function()
		return bodyY + side * h - 0.2
	end, 0, 0.3, 0.8, math.rad(20), 0)
	if room(ctx, 2) then
		for _, sideSign in ipairs({ -1, 1 }) do
			makePart(
				ctx,
				"Shard",
				"Glow",
				Vector3.new(0.6, 1.7, 0.6),
				CFrame.new(sideSign * 0.95, 1.25, 0.4) * CFrame.Angles(0, math.rad(45), math.rad(-sideSign * 25))
			)
		end
	end
	tryPart(
		ctx,
		"Shard",
		"Glow",
		Vector3.new(0.6, 1.5, 0.6),
		CFrame.new(0, 1.2, 1.0) * CFrame.Angles(math.rad(25), math.rad(45), 0)
	)
	return body, bodyY
end

-- Stachelkugel
Builders.Spiky = function(ctx: Ctx): (Part, number)
	local radius = 1.4
	local c = Vector3.new(0, radius, 0)
	local r = Vector3.one * radius
	local body = makePart(ctx, "Body", "Main", r * 2, CFrame.new(c), "Ball")
	addEyesOnEllipsoid(ctx, c, r, 1.65, 0.5, 0.7, "Big")
	addMouthOnEllipsoid(ctx, c, r, 1.0, 0.6)
	addAntennas(ctx, function(x)
		return topY(c, r, x, 0)
	end, 0, 0.45, 0.8, math.rad(25), 0)
	local function spike(dir: Vector3)
		local d = dir.Unit
		tryPart(ctx, "Spike", "Accent", Vector3.new(1.4, 0.5, 0.5), axisCFrame(c + d * (radius + 0.3), d), "Ellipsoid")
	end
	spike(Vector3.new(0, 1, 0.15))
	local pairsList = {
		Vector3.new(0.6, 0.75, 0.2),
		Vector3.new(0.55, 0.45, 0.7),
		Vector3.new(0.3, 0.9, -0.35),
	}
	for i, dir in ipairs(pairsList) do
		if room(ctx, 2) then
			spike(dir)
			spike(Vector3.new(-dir.X, dir.Y, dir.Z))
		end
		if i == 2 and room(ctx, 1) then
			spike(Vector3.new(0, 0.6, 0.8))
		end
	end
	return body, c.Y
end

-- König mit Krone, Umhang und Schnurrbart
Builders.King = function(ctx: Ctx): (Part, number)
	local c = Vector3.new(0, 1.4, 0)
	local r = Vector3.new(1.35, 1.35, 1.25)
	local body = makePart(ctx, "Body", "Main", r * 2, CFrame.new(c), "Ellipsoid")
	local crownY = 2.85
	makePart(
		ctx,
		"Crown",
		"Gold",
		Vector3.new(0.6, 1.7, 1.7),
		CFrame.new(0, crownY, 0) * CFrame.Angles(0, 0, math.rad(90)),
		"Cylinder"
	)
	for _, pos in ipairs({ Vector3.new(-0.7, 3.3, 0), Vector3.new(0.7, 3.3, 0), Vector3.new(0, 3.35, -0.7) }) do
		makePart(
			ctx,
			"CrownPoint",
			"Gold",
			Vector3.one * 0.45,
			CFrame.new(pos) * CFrame.Angles(0, math.rad(45), 0) * CFrame.Angles(math.rad(45), 0, 0)
		)
	end
	addEyesOnEllipsoid(ctx, c, r, 1.8, 0.5, 0.7, "Big")
	addAntennas(ctx, function()
		return 3.15
	end, 0.3, 0.45, 0.8, math.rad(25), 0)
	if room(ctx, 1) then
		local point, normal = frontPoint(c, r, 0, 1.3)
		makePart(ctx, "Mustache", "Dark", Vector3.new(1.0, 0.28, 0.3), facing(point, normal), "Ellipsoid")
	end
	tryPart(ctx, "Cape", "Cape", Vector3.new(2.4, 2.3, 0.35), CFrame.new(0, 1.35, 1.2), "Ellipsoid")
	tryPart(ctx, "Gem", "Glow", Vector3.one * 0.32, CFrame.new(0, crownY, -0.88), "Ball")
	if room(ctx, 2) then
		for _, side in ipairs({ -1, 1 }) do
			makePart(
				ctx,
				"Foot",
				"Shade",
				Vector3.new(0.85, 0.45, 1.0),
				CFrame.new(side * 0.55, 0.22, -0.3),
				"Ellipsoid"
			)
		end
	end
	return body, c.Y
end

-- Pilz-Alien: Gesicht im Stiel, gepunkteter Hut
Builders.Mushroom = function(ctx: Ctx): (Part, number)
	local c = Vector3.new(0, 1.25, 0)
	local r = Vector3.new(1.0, 1.25, 1.0)
	local body = makePart(ctx, "Body", "Stalk", r * 2, CFrame.new(c), "Ellipsoid")
	local capC = Vector3.new(0, 2.65, 0.05)
	local capR = Vector3.new(1.7, 0.85, 1.7)
	makePart(ctx, "Cap", "Main", capR * 2, CFrame.new(capC), "Ellipsoid")
	addEyesOnEllipsoid(ctx, c, r, 1.35, 0.38, 0.62, "Big")
	addMouthOnEllipsoid(ctx, c, r, 0.75, 0.5)
	addAntennas(ctx, function(x)
		return topY(capC, capR, x, capC.Z)
	end, capC.Z, 0.5, 0.8, math.rad(20), 0)
	local function spot(x: number, z: number)
		tryPart(ctx, "Spot", "Accent", Vector3.one * 0.55, CFrame.new(x, topY(capC, capR, x, z) - 0.12, z), "Ball")
	end
	spot(0, capC.Z)
	if room(ctx, 2) then
		spot(-0.95, -0.6)
		spot(0.95, -0.6)
	end
	if room(ctx, 2) then
		spot(-1.0, 0.75)
		spot(1.0, 0.75)
	end
	return body, c.Y
end

-- Admin-Extra: leuchtende Kugeln rund ums Alien
local function addOrbs(ctx: Ctx, height: number)
	for i = 0, 3 do
		if not room(ctx, 1) then
			return
		end
		local angle = math.rad(45 + 90 * i)
		makePart(
			ctx,
			"Orb",
			"Glow",
			Vector3.one * 0.55,
			CFrame.new(math.cos(angle) * 1.75, height + (i % 2) * 0.5, math.sin(angle) * 1.75),
			"Ball"
		)
	end
end

-- -------------------------------------------------------------------
-- Effekte + Namensschild
-- -------------------------------------------------------------------
local function addEffects(model: Model, body: Part, alien: AlienDef, mut: any, s: number, carry: boolean)
	local fx = alien.Effects
	local rank = rarityRank(alien.Rarity)
	local color = rarityColor(alien.Rarity)
	local accent = alien.Look.Accent

	-- Umriss: getragen keiner. Startet AUS – der Client schaltet nur die nächsten paar ein
	-- (Roblox zeigt höchstens 31 Highlights gleichzeitig, jedes kostet einen Render-Durchgang).
	if fx.Highlight and not carry then
		local highlight = Instance.new("Highlight")
		highlight.Name = "Glow"
		highlight.Enabled = false
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.FillColor = color
		highlight.FillTransparency = 0.85
		highlight.OutlineColor = accent
		highlight.OutlineTransparency = 0.1
		if fx.Rainbow then
			highlight:SetAttribute("Rainbow", true)
		end
		highlight.Parent = model
	end

	if fx.Aura then
		local aura = Instance.new("ParticleEmitter")
		aura.Name = "Aura"
		aura.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		aura.Color = fx.Rainbow and RAINBOW_SEQUENCE or ColorSequence.new(color, accent)
		aura.LightEmission = 1
		aura.LightInfluence = 0
		aura.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35 * s),
			NumberSequenceKeypoint.new(0.6, 0.25 * s),
			NumberSequenceKeypoint.new(1, 0),
		})
		aura.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		aura.Lifetime = NumberRange.new(1, 1.8)
		aura.Speed = NumberRange.new(0.4, 1.2)
		aura.SpreadAngle = Vector2.new(180, 180)
		aura.Acceleration = Vector3.new(0, 1.2 * s, 0)
		aura.RotSpeed = NumberRange.new(-90, 90)
		local rate = rank >= ADMIN_RANK and 18 or (rank >= 8 and 10 or 6)
		aura.Rate = carry and math.ceil(rate / 2) or rate
		aura.Parent = body
	end

	if fx.BigLight then
		local light = Instance.new("PointLight")
		light.Name = "BigLight"
		light.Range = 30
		light.Brightness = 2.5
		light.Color = accent:Lerp(color, 0.5)
		light.Shadows = false
		light.Parent = body
	elseif rank >= 8 or (rank >= 5 and alien.Tier ~= "Normal") then
		-- kleines Licht erst ab Legendary (sparsam)
		local light = Instance.new("PointLight")
		light.Name = "Light"
		light.Range = 8 + (rank - 5) * 1.5
		light.Brightness = 1.2
		light.Color = color
		light.Shadows = false
		light.Parent = body
	end

	if fx.Fire then
		local fire = Instance.new("Fire")
		fire.Color = color
		fire.SecondaryColor = accent
		fire.Size = 3 * s
		fire.Heat = 6
		fire.Parent = body
	end

	if mut.Name == "Cosmic" then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = mut.Color or color
		sparkles.Parent = body
	end
end

local function makeLabel(parent: Instance, name: string, order: number, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, textSize + 4)
	label.LayoutOrder = order
	label.Font = Enum.Font.FredokaOne
	label.TextSize = textSize
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = ""
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = label
	label.Parent = parent
	return label
end

local function getBody(model: Model): BasePart?
	local primary = model.PrimaryPart
	if primary then
		return primary
	end
	local body = model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		return body
	end
	return nil
end

-- Abstand Schild <-> Body-Mitte passend zur aktuellen Größe
local function updateLabelOffset(model: Model, body: BasePart)
	local gui = body:FindFirstChild("Info")
	if not gui or not gui:IsA("BillboardGui") then
		return
	end
	local scale = model:GetScale()
	local top = tonumber(model:GetAttribute("TopHeight")) or body.Size.Y
	local pivot = tonumber(model:GetAttribute("PivotHeight")) or body.Size.Y / 2
	gui.StudsOffsetWorldSpace = Vector3.new(0, (top - pivot) * scale + LABEL_GAP, 0)
end

-- -------------------------------------------------------------------
-- ÖFFENTLICH
-- -------------------------------------------------------------------

-- Schild aktualisieren: Name, "Stufe • Seltenheit [• Mutation]", "$X/s ⚡Lv n"
function AlienFactory.UpdateLabel(model: Model, entry: Entry)
	local body = getBody(model)
	local gui = body and body:FindFirstChild("Info")
	local frame = gui and gui:FindFirstChild("Frame")
	if not frame then
		return
	end
	local nameLabel = frame:FindFirstChild("NameLabel") :: TextLabel?
	local rarityLabel = frame:FindFirstChild("RarityLabel") :: TextLabel?
	local valueLabel = frame:FindFirstChild("ValueLabel") :: TextLabel?
	local alien = resolveAlien(entry)
	local mut = getMutation(entry.Mut)
	local color = rarityColor(alien.Rarity)

	if nameLabel then
		nameLabel.Text = alien.Name
		nameLabel.TextColor3 = color
	end
	if rarityLabel then
		local tag = alien.Tier .. " • " .. alien.Rarity
		if mut.Name ~= "Normal" then
			tag ..= " • " .. tostring(mut.Name)
		end
		rarityLabel.Text = tag
		rarityLabel.TextColor3 = mut.Color
			or (alien.Tier == "Normal" and color or Aliens.TierColors[alien.Tier] or color)
	end
	if valueLabel then
		-- Unbekannte Alien-Id -> mit dem Ersatz-Alien rechnen, damit Config nicht stolpert
		local incomeEntry = (entry.Alien == alien.Id) and entry
			or { Id = entry.Id, Alien = alien.Id, Mut = entry.Mut, Lv = entry.Lv }
		local income = tonumber(Config.MeteorIncome(incomeEntry)) or 0
		local lv = levelOf(entry)
		local lvText = lv >= maxLevel() and "MAX" or tostring(lv)
		valueLabel.Text = Util.FormatCash(income) .. "/s  ⚡Lv " .. lvText
		valueLabel.TextColor3 = Color3.fromRGB(120, 255, 120)
	end
end

-- entry = { Id = meteorId, Alien = alienId, Mut, Lv }, mode = "Base" | "Carry" | "Photo"
function AlienFactory.Create(entry: Entry, mode: string?): Model
	local alien = resolveAlien(entry)
	local look = alien.Look
	local fx = alien.Effects
	local rank = rarityRank(alien.Rarity)
	local mut = getMutation(entry.Mut)
	local modeName = (mode == "Carry" or mode == "Photo") and mode or "Base"
	local carry = modeName == "Carry"
	local lvScale = levelScale(levelOf(entry))
	local s = look.Scale * MODE_SCALE[modeName] * lvScale

	local model = Instance.new("Model")
	model.Name = "Alien"

	-- Wie hell ist die Fläche, auf der die Augen sitzen? (Pilz: heller Stiel, Käfer: dunklerer Kopf)
	local faceColor: Color3 = faceColorOf(look, mut)
	local luminance = 0.299 * faceColor.R + 0.587 * faceColor.G + 0.114 * faceColor.B

	local ctx: Ctx = {
		model = model,
		s = s,
		color = look.Color,
		accent = look.Accent,
		eyes = look.Eyes,
		antennas = look.Antennas,
		mutName = tostring(mut.Name),
		mutColor = typeof(mut.Color) == "Color3" and mut.Color or nil,
		rainbow = fx.Rainbow == true,
		carry = carry,
		darkFace = luminance < 0.2,
		mainMaterial = Enum.Material.SmoothPlastic,
		mainTransparency = 0,
		mainReflectance = look.Archetype == "Robot" and 0.12 or 0,
		count = 0,
		max = rank >= ADMIN_RANK and MAX_PARTS_ADMIN or MAX_PARTS,
		top = 0,
	}

	local builder = Builders[look.Archetype] or Builders.Blob
	local body, bodyY = builder(ctx)
	if rank >= ADMIN_RANK then
		addOrbs(ctx, bodyY)
	end
	body.CanQuery = not carry -- für Prompts/Klicks; getragen stört es nur die Kamera

	-- Pivot = Bodenmitte, aufrecht, Blick nach -Z (beim Bauen = Welt-Ursprung).
	-- Bei gesetztem PrimaryPart zählt dessen PivotOffset (relativ zum gedrehten Body!).
	body.PivotOffset = body.CFrame:Inverse()
	model.WorldPivot = CFrame.new()
	model.PrimaryPart = body

	model:SetAttribute("AlienId", alien.Id)
	model:SetAttribute("MeteorId", entry.Id)
	model:SetAttribute("Rarity", alien.Rarity)
	model:SetAttribute("Tier", alien.Tier)
	model:SetAttribute("Mutation", tostring(mut.Name))
	model:SetAttribute("Bob", not carry) -- getragene Aliens nicht wippen (würde den Spieler mitbewegen)
	if ctx.rainbow then
		model:SetAttribute("Rainbow", true)
	end
	-- für Refresh: Höhen beim Bauen (inkl. Skalierung) + Level-Faktor beim Bauen
	model:SetAttribute("PivotHeight", bodyY * s)
	model:SetAttribute("TopHeight", ctx.top * s)
	model:SetAttribute("BuiltLevelScale", lvScale)

	addEffects(model, body, alien, mut, s, carry)

	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.Size = UDim2.new(0, 220, 0, 70)
	gui.StudsOffsetWorldSpace = Vector3.new(0, (ctx.top - bodyY) * s + LABEL_GAP, 0)
	gui.MaxDistance = carry and 60 or (70 + rank * 15)
	gui.LightInfluence = 0
	gui.Parent = body

	local frame = Instance.new("Frame")
	frame.Name = "Frame"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Parent = frame

	makeLabel(frame, "NameLabel", 1, 20)
	makeLabel(frame, "RarityLabel", 2, 15)
	makeLabel(frame, "ValueLabel", 3, 17)

	AlienFactory.UpdateLabel(model, entry)
	return model
end

-- Nach einem Level-Up: Größe leicht anpassen (Boden bleibt, wo er ist) + Schild aktualisieren
function AlienFactory.Refresh(model: Model, entry: Entry)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	local body = getBody(model)
	if not body then
		return
	end
	local built = tonumber(model:GetAttribute("BuiltLevelScale")) or 1
	local target = levelScale(levelOf(entry)) / (built > 0 and built or 1)
	local current = model:GetScale()
	if math.abs(current - target) > 0.001 then
		-- Lage des Body relativ zum Boden-Pivot merken, skalieren, Pivot neu setzen, zurückstellen
		local pivot = model:GetPivot()
		local rel = pivot:ToObjectSpace(body.CFrame)
		model:ScaleTo(target)
		local scaledRel = CFrame.new(rel.Position * (target / current)) * rel.Rotation
		body.PivotOffset = scaledRel:Inverse()
		model:PivotTo(pivot)
		-- Zähler: der Client (Wippen) merkt daran, dass sich die Teile verändert haben
		model:SetAttribute("Rev", (tonumber(model:GetAttribute("Rev")) or 0) + 1)
	end
	updateLabelOffset(model, body)
	AlienFactory.UpdateLabel(model, entry)
end

return AlienFactory
