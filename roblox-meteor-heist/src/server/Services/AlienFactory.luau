--!strict
-- Baut das Aussehen eines Aliens (schlüpft aus einem Meteor) im Stil knuffiger Roblox-Pets:
-- wenige, runde, saubere Formen, große glänzende Augen (mit weißem Lichtreflex), Bäckchen,
-- kleiner Mund. Jede Körperform ("Archetype", Aliens.luau) hat EIN klares Erkennungsmerkmal.
--
--  * Stufen: Normal = schlicht, Selten = ein Extra-Detail (je Form eins), Ultra = Flügel +
--    Heiligenschein (King: Flügel + leuchtender Kronen-Edelstein). Admin: immer Flügel + Schein.
--  * Mutationen: Gold (Folie), Diamond (Glas), Cosmic (Neon + Funken), Frost (Eis-Körper,
--    Schnee-Füße, Schneeflocken), Lava (glühender Körper, Vulkangestein, kleines Feuer),
--    Rainbow (alle farbigen Teile mit Attribut "Rainbow" -> der Client färbt sie durch).
--  * Umriss (Highlight) nur noch bei Tier "Ultra" + Rarity "Admin" (Roblox zeigt nur ~31 gleichzeitig).
--  * Pivot (model:GetPivot()) = Bodenmitte -> model:PivotTo(Pad-Oberseite) stellt das Alien aufs Pad.
--  * Das Gesicht zeigt in Blickrichtung des Pivots (LookVector / lokales -Z).
--  * Alle Teile sind verankert, ohne Kollision. Nur "Body" (PrimaryPart) ist abfragbar (für Prompts).
--  * Höchstens 18 Teile pro Alien (Admin: 24), damit auch volle Basen nicht laggen. Die Teile werden
--    nach Wichtigkeit gebaut (Körper, Augen, Mund, Stufen-Extra, Bäckchen, Antennen, ...), was nicht
--    mehr ins Budget passt, fällt weg.
--  * Augen-Teile (Eye, Iris, Pupil, Shine) haben dieselbe Teilgröße wie ihr Auge (kleiner sichtbar per
--    SpecialMesh.Scale) -> beim Blinzeln (WorldFX) sinken sie alle gleich tief in den Kopf.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")) :: any
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))
local Aliens = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Aliens"))

type AlienDef = Aliens.AlienDef
type Entry = { Id: string, Alien: string?, Mut: string?, Lv: number? }

-- Aussehen einer Mutation an "Main" (Körper), "Light" (Bauch, Schnauze) und "Shade" (Füße, Arme, Antennen).
-- Die Farbe kommt aus Config.Mutations; ohne Eintrag hier wird nur umgefärbt.
type MutStyle = {
	Material: Enum.Material,
	Transparency: number?, -- mindestens so durchsichtig
	Reflectance: number?, -- Standard 0
	ShadeMaterial: Enum.Material?, -- Standard: wie Material
	ShadeTint: Color3?, -- Shade = Körperfarbe in Richtung dieser Farbe (Standard: dunkler)
	ShadeAlpha: number?,
}

-- Ellipsoid (Mitte + Radien), auf dessen Vorderseite (-Z) ein Gesicht sitzt
type Face = { c: Vector3, r: Vector3 }

type Ctx = {
	model: Model,
	s: number, -- Gesamt-Skalierung (Seltenheit * Stufe * Modus * Level)
	color: Color3,
	accent: Color3,
	eyes: number,
	antennas: number,
	tier: number, -- 1 = Normal, 2 = Selten, 3 = Ultra
	rank: number, -- Seltenheits-Rang (1 Common .. 10 Admin)
	admin: boolean,
	faceRole: string, -- Rolle der Fläche, auf der die Augen sitzen (für die Augenfarbe)
	mutStyle: MutStyle?,
	mutColor: Color3?, -- nil = eigene Farbe (Normal, Regenbogen)
	rainbow: boolean, -- Körper + Leucht-Teile färben sich durch
	rainbowShade: boolean, -- auch die Shade-Teile (Regenbogen-Mutation)
	carry: boolean,
	mainMaterial: Enum.Material,
	mainTransparency: number,
	mainReflectance: number,
	count: number,
	max: number,
	top: number, -- höchster Punkt (unskaliert)
	haloZ: number?, -- Heiligenschein vorgemerkt (wird zuletzt über dem höchsten Punkt gebaut)
}

type Builder = (ctx: Ctx) -> (Part, number)

local AlienFactory = {}

local MAX_PARTS = 18
local MAX_PARTS_ADMIN = 24
-- Rang der Seltenheit "Admin" (Godly/Cosmic/Infinity liegen darunter und sind KEINE Admin-Aliens)
local ADMIN_RANK = (Config.RarityIndex and Config.RarityIndex.Admin) or Aliens.RarityRank.Admin or 13
local LEVEL_GROWTH = 0.012 -- +1,2% Größe pro Level (Level 20 = +23%)
local LABEL_GAP = 1.6
local SHADOW_MIN_VOLUME = 6 -- nur große Teile werfen Schatten (bewegte Schattenwerfer kosten viel)
local MODE_SCALE: { [string]: number } = { Base = 1, Photo = 1, Carry = 0.55 }

local DARK = Color3.fromRGB(28, 24, 42) -- Augen, Mund
local WHITE = Color3.fromRGB(250, 250, 255)
local GOLD = Color3.fromRGB(255, 200, 40)
local STALK = Color3.fromRGB(250, 238, 214)
local METAL = Color3.fromRGB(92, 98, 115)
local ROCK = Color3.fromRGB(70, 65, 75)
local BLACK = Color3.new(0, 0, 0)
local BLUSH = Color3.fromRGB(255, 105, 150)
local TONGUE = Color3.fromRGB(255, 110, 130)
local HALO = Color3.fromRGB(255, 226, 110)
local LEAF = Color3.fromRGB(90, 210, 90)
local FROST_LIGHT = Color3.fromRGB(190, 235, 255)
local LAVA_ORANGE = Color3.fromRGB(255, 110, 30)
local LAVA_DARK = Color3.fromRGB(120, 20, 0)
local FALLBACK_RARITY_COLORS: { [string]: Color3 } = { Admin = Color3.fromRGB(255, 40, 40) }

-- Umriss (Highlight) nur für diese Kombination – Roblox zeigt höchstens ~31 Highlights gleichzeitig
local HIGHLIGHT_TIER = "Ultra"
local HIGHLIGHT_RARITY = "Admin"

local SHADE_ALPHA = 0.3 -- Shade-Teile: so viel dunkler als der Körper
local LIGHT_ALPHA = 0.55 -- Light-Teile (Bauch, Schnauze): so viel heller als der Körper
local DARK_FACE = 0.2 -- Gesichtsfläche dunkler als das -> leuchtende statt dunkle Augen

local TIER_INDEX: { [string]: number } = { Normal = 1, Selten = 2, Ultra = 3 }

-- Teile, die der Client als Augen erkennt (Attribut "Eye" -> lokales Blinzeln)
local EYE_PARTS: { [string]: boolean } = { Eye = true, Pupil = true, Iris = true, Shine = true }

local MUT_STYLES: { [string]: MutStyle } = {
	Gold = { Material = Enum.Material.Foil, Reflectance = 0.1 },
	Diamond = { Material = Enum.Material.Glass, Transparency = 0.2, Reflectance = 0.15 },
	Cosmic = { Material = Enum.Material.Neon },
	-- Eis-Körper, Füße/Antennen wie aus Schnee (+ Schneeflocken, siehe addEffects)
	Frost = {
		Material = Enum.Material.Ice,
		Reflectance = 0.05,
		ShadeMaterial = Enum.Material.Snow,
		ShadeTint = WHITE,
		ShadeAlpha = 0.55,
	},
	-- glühender Körper, Füße/Antennen aus dunklem Vulkangestein (+ kleines Feuer, siehe addEffects)
	Lava = {
		Material = Enum.Material.Neon,
		ShadeMaterial = Enum.Material.Basalt,
		ShadeTint = BLACK,
		ShadeAlpha = 0.7,
	},
}

-- Symbol vor dem Mutationsnamen im Namensschild (Config.Mutations -> Icon hat Vorrang; das hier ist der Ersatz)
local MUT_ICONS: { [string]: string } = {
	Gold = "🪙",
	Diamond = "💎",
	Cosmic = "🌌",
	Frost = "❄️",
	Lava = "🔥",
	Rainbow = "🌈",
}

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

-- Symbol + Name einer Mutation fürs Schild, z.B. "🔥 Lava"
local function mutationText(mut: any): string
	local name = tostring(mut.Name)
	local configIcon = if type(mut.Icon) == "string" and mut.Icon ~= "" then mut.Icon else nil
	local icon = configIcon or MUT_ICONS[name] or (mut.Rainbow == true and MUT_ICONS.Rainbow) or nil
	return icon and (icon .. " " .. name) or name
end

local function luminance(color: Color3): number
	return 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
end

-- -------------------------------------------------------------------
-- Farben + Material nach Rolle
-- -------------------------------------------------------------------
-- Körperfarbe (Mutation hat Vorrang)
local function mainColorOf(ctx: Ctx): Color3
	return ctx.mutColor or ctx.color
end

-- Farbe der Shade-Teile (Füße, Arme, Antennen) aus der Körperfarbe
local function shadeColorOf(ctx: Ctx, base: Color3): Color3
	local style = ctx.mutStyle
	local tint = style and style.ShadeTint or BLACK
	local alpha = style and style.ShadeAlpha or SHADE_ALPHA
	return base:Lerp(tint, alpha)
end

-- Farbe, die eine Rolle bekommt (ohne Regenbogen-Durchfärben)
local function roleColor(ctx: Ctx, role: string): Color3
	if role == "Main" then
		return mainColorOf(ctx)
	elseif role == "Shade" then
		return shadeColorOf(ctx, mainColorOf(ctx))
	elseif role == "Light" then
		return mainColorOf(ctx):Lerp(WHITE, LIGHT_ALPHA)
	elseif role == "Accent" or role == "Glow" or role == "Cape" then
		return ctx.accent
	elseif role == "Dark" then
		return DARK
	elseif role == "White" or role == "Shine" then
		return WHITE
	elseif role == "Blush" then
		return BLUSH:Lerp(mainColorOf(ctx), 0.2)
	elseif role == "Tongue" then
		return TONGUE
	elseif role == "Gold" then
		return GOLD
	elseif role == "Stalk" then
		return STALK
	elseif role == "StalkShade" then
		return STALK:Lerp(mainColorOf(ctx), 0.35)
	elseif role == "Metal" then
		return METAL
	elseif role == "Rock" then
		return ctx.color:Lerp(ROCK, 0.65)
	elseif role == "Wing" then
		return WHITE:Lerp(ctx.accent, 0.12)
	elseif role == "Halo" then
		return HALO
	elseif role == "Leaf" then
		return LEAF
	end
	return ctx.color
end

-- Farbe der Fläche, auf der das Gesicht sitzt (Regenbogen färbt der Client hell + satt -> zählt als hell)
local function faceColorOf(ctx: Ctx): Color3
	if ctx.rainbow and ctx.faceRole == "Main" then
		return WHITE
	end
	return roleColor(ctx, ctx.faceRole)
end

local function styleRole(ctx: Ctx, part: Part, role: string)
	local material = Enum.Material.SmoothPlastic
	local color = roleColor(ctx, role)
	local transparency = 0
	local reflectance = 0
	if role == "Main" or role == "Shade" or role == "Light" then
		material = ctx.mainMaterial
		transparency = ctx.mainTransparency
		reflectance = ctx.mainReflectance
		local style = ctx.mutStyle
		if style then
			material = style.Material
			transparency = math.max(transparency, style.Transparency or 0)
			reflectance = style.Reflectance or 0
		end
		if role == "Shade" then
			if style and style.ShadeMaterial then
				material = style.ShadeMaterial
			end
			if ctx.rainbowShade then
				part:SetAttribute("Rainbow", true)
			end
		elseif role == "Main" and ctx.rainbow then
			part:SetAttribute("Rainbow", true)
		end
	elseif role == "Glow" then
		material = Enum.Material.Neon
		if ctx.rainbow then
			part:SetAttribute("Rainbow", true)
		end
	elseif role == "Shine" then
		material = Enum.Material.Neon
	elseif role == "Dark" or role == "Metal" then
		reflectance = 0.2
	elseif role == "Blush" then
		transparency = 0.25
	elseif role == "Gold" then
		material = Enum.Material.Foil
		reflectance = 0.1
	elseif role == "Rock" then
		material = Enum.Material.Slate
	elseif role == "Cape" then
		material = Enum.Material.Fabric
	elseif role == "Halo" then
		material = Enum.Material.Neon
		transparency = 0.15
		if ctx.rainbow then
			part:SetAttribute("Rainbow", true)
		end
	end
	part.Material = material
	part.Color = color
	part.Transparency = transparency
	part.Reflectance = reflectance
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
local function frontPoint(face: Face, x: number, y: number): (Vector3, Vector3)
	local center, radii = face.c, face.r
	local dx = (x - center.X) / radii.X
	local dy = (y - center.Y) / radii.Y
	local depth = math.sqrt(math.max(0, 1 - dx * dx - dy * dy))
	local point = Vector3.new(x, y, center.Z - radii.Z * depth)
	local rel = point - center
	local normal = Vector3.new(rel.X / radii.X ^ 2, rel.Y / radii.Y ^ 2, rel.Z / radii.Z ^ 2)
	return point, normal.Magnitude > 1e-4 and normal.Unit or -Vector3.zAxis
end

-- CFrame auf der Vorderseite eines Ellipsoids, "out" Studs nach außen versetzt, Blick nach außen
local function onFace(face: Face, x: number, y: number, out: number): CFrame
	local point, normal = frontPoint(face, x, y)
	return facing(point + normal * out, normal)
end

-- Ebene Vorderseite (z.B. Roboter-Bildschirm, Kristall): als sehr großes Ellipsoid genähert
local function flatFace(x: number, y: number, z: number): Face
	return { c = Vector3.new(x, y, z + 200), r = Vector3.one * 200 }
end

-- Höhe der Oberseite eines Ellipsoids bei (x, z)
local function topY(face: Face, x: number, z: number): number
	local center, radii = face.c, face.r
	local dx = (x - center.X) / radii.X
	local dz = (z - center.Z) / radii.Z
	return center.Y + radii.Y * math.sqrt(math.max(0, 1 - dx * dx - dz * dz))
end

-- shape: "Block" (Standard), "Ball", "Cylinder" (Achse = X) oder "Ellipsoid".
-- meshScale (nur Ellipsoid): sichtbare Größe = Size * meshScale (für Augen-Teile, siehe oben)
local function makePart(
	ctx: Ctx,
	name: string,
	role: string,
	size: Vector3,
	cf: CFrame,
	shape: string?,
	meshScale: Vector3?
): Part
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
		if meshScale then
			mesh.Scale = meshScale
		end
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
	local visible = meshScale and size * meshScale or size
	local scaled = visible * s
	part.CastShadow = not ctx.carry and scaled.X * scaled.Y * scaled.Z >= SHADOW_MIN_VOLUME
	if ctx.carry then
		part.Massless = true
	end
	styleRole(ctx, part, role)
	if EYE_PARTS[name] then
		part:SetAttribute("Eye", true) -- Client: Augen blinzeln lokal (rein optisch)
	end
	ctx.top = math.max(ctx.top, cf.Position.Y + halfHeight(cf, visible))
	part.Parent = ctx.model
	return part
end

-- Wie makePart, aber nur wenn noch Platz im Teile-Budget ist
local function tryPart(
	ctx: Ctx,
	name: string,
	role: string,
	size: Vector3,
	cf: CFrame,
	shape: string?,
	meshScale: Vector3?
): Part?
	if not room(ctx, 1) then
		return nil
	end
	return makePart(ctx, name, role, size, cf, shape, meshScale)
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

-- Paar links/rechts (nur wenn beide ins Budget passen). make(side) baut eine Seite (-1 / 1).
local function pair(ctx: Ctx, make: (side: number) -> ())
	if room(ctx, 2) then
		make(-1)
		make(1)
	end
end

-- -------------------------------------------------------------------
-- Gesicht: Augen, Mund, Bäckchen, Antennen
-- -------------------------------------------------------------------
-- Seitliche Versätze (x in Studs, Höhe in Augenhöhen) für n Augen
local function eyeLayout(n: number, spread: number): { Vector2 }
	if n <= 1 then
		return { Vector2.zero }
	elseif n == 2 then
		return { Vector2.new(-spread, 0), Vector2.new(spread, 0) }
	elseif n == 3 then
		return { Vector2.new(-spread * 1.2, -0.12), Vector2.new(0, 0.3), Vector2.new(spread * 1.2, -0.12) }
	end
	return {
		Vector2.new(-spread * 1.5, -0.15),
		Vector2.new(-spread * 0.5, 0.08),
		Vector2.new(spread * 0.5, 0.08),
		Vector2.new(spread * 1.5, -0.15),
	}
end

-- Große, glänzende Ovalaugen (dunkel, auf dunkler Fläche leuchtend) mit weißem Lichtreflex.
-- Ohne Platz im Budget: ohne Reflex (aber immer alle Augen).
local function addEyes(ctx: Ctx, face: Face, y: number, spread: number, h: number)
	local n = ctx.eyes
	if n >= 3 then
		h *= 0.7
		spread *= 0.75
	end
	local w, d = h * 0.76, h * 0.5
	local withShine = room(ctx, n * 2)
	local glow = luminance(faceColorOf(ctx)) < DARK_FACE
	local role = glow and "Glow" or "Dark"
	-- leuchtende (helle) Augen auf dunklem Gesicht: dunkler statt weißer Glanzpunkt
	local shineRole = (glow and luminance(ctx.accent) > 0.75) and "Dark" or "Shine"
	local size = Vector3.new(w, h, d)
	local shineScale = Vector3.new(0.36, 0.36 * w / h, 0.3)
	for _, offset in ipairs(eyeLayout(n, spread)) do
		local cf = onFace(face, offset.X, y + offset.Y * h, d * 0.1)
		makePart(ctx, "Eye", role, size, cf, "Ellipsoid")
		if withShine then
			makePart(
				ctx,
				"Shine",
				shineRole,
				size,
				cf * CFrame.new(w * 0.2, h * 0.2, -d * 0.36),
				"Ellipsoid",
				shineScale
			)
		end
	end
end

-- Ein riesiges Zyklopen-Auge: weiß, Iris in Akzentfarbe, Pupille, Lichtreflex
local function addBigEye(ctx: Ctx, face: Face, y: number, h: number)
	local size = Vector3.new(h * 0.94, h, h * 0.6)
	local cf = onFace(face, 0, y, h * 0.06)
	makePart(ctx, "Eye", "White", size, cf, "Ellipsoid")
	local d = size.Z
	makePart(
		ctx,
		"Iris",
		"Accent",
		size,
		cf * CFrame.new(0, -h * 0.03, -d * 0.3),
		"Ellipsoid",
		Vector3.new(0.6, 0.58, 0.5)
	)
	makePart(
		ctx,
		"Pupil",
		"Dark",
		size,
		cf * CFrame.new(0, -h * 0.03, -d * 0.44),
		"Ellipsoid",
		Vector3.new(0.32, 0.32, 0.4)
	)
	tryPart(
		ctx,
		"Shine",
		"Shine",
		size,
		cf * CFrame.new(h * 0.13, h * 0.11, -d * 0.6),
		"Ellipsoid",
		Vector3.new(0.17, 0.16, 0.2)
	)
end

-- Mund. "Open" = kleines offenes Lächeln, "O" = rundes Staunen. Gibt die Lage zurück (für die Zunge).
local function addMouth(ctx: Ctx, face: Face, y: number, w: number, style: string): CFrame?
	if not room(ctx, 1) then
		return nil
	end
	local cf = onFace(face, 0, y, 0.02)
	local role = luminance(faceColorOf(ctx)) < DARK_FACE and "Glow" or "Dark" -- dunkles Gesicht: leuchtender Mund
	if style == "O" then
		makePart(ctx, "Mouth", role, Vector3.new(w * 0.62, w * 0.72, 0.2), cf, "Ellipsoid")
		return nil
	end
	makePart(ctx, "Mouth", role, Vector3.new(w, w * 0.6, 0.22), cf, "Ellipsoid")
	return cf
end

-- Zunge im offenen Mund (unwichtig -> wird spät gebaut)
local function addTongue(ctx: Ctx, mouth: CFrame?, w: number)
	if mouth then
		tryPart(
			ctx,
			"Tongue",
			"Tongue",
			Vector3.new(w * 0.62, w * 0.3, 0.16),
			mouth * CFrame.new(0, -w * 0.12, -0.05),
			"Ellipsoid"
		)
	end
end

local function addBlush(ctx: Ctx, face: Face, y: number, x: number, k: number)
	pair(ctx, function(side)
		makePart(ctx, "Cheek", "Blush", Vector3.new(0.44, 0.24, 0.12) * k, onFace(face, side * x, y, 0), "Ellipsoid")
	end)
end

-- Fläche (Bauch, Schnauze) auf der Vorderseite, etwas herausstehend
local function addPatch(ctx: Ctx, name: string, role: string, face: Face, y: number, size: Vector3): CFrame?
	local cf = onFace(face, 0, y, -size.Z * 0.2)
	if tryPart(ctx, name, role, size, cf, "Ellipsoid") then
		return cf
	end
	return nil
end

local function addFeet(ctx: Ctx, x: number, z: number, size: Vector3, role: string)
	pair(ctx, function(side)
		makePart(ctx, "Foot", role, size, CFrame.new(side * x, size.Y / 2, z), "Ellipsoid")
	end)
end

-- Antennen mit Kugel. Weniger Platz im Budget -> erst ohne Kugel, dann weniger Antennen.
-- baseYAt(x) liefert die Höhe der Kopf-Oberseite an der Stelle x. single = x-Lage einer einzelnen Antenne.
local function addAntennas(
	ctx: Ctx,
	baseYAt: (x: number) -> number,
	z: number,
	spread: number,
	length: number,
	lean: number,
	tilt: number,
	single: number?
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
	local xs = n == 1 and { single or 0 } or (n == 2 and { -spread, spread } or { -spread, 0, spread })
	local tipRole = (ctx.tier >= 3 or ctx.rank >= 6) and "Glow" or "Accent"
	for _, x in ipairs(xs) do
		local side = x > 0.01 and 1 or (x < -0.01 and -1 or 0)
		local dir = Vector3.new(side * math.sin(lean), math.cos(lean), -math.sin(tilt)).Unit
		local base = Vector3.new(x, baseYAt(x) - 0.08, z)
		local tip = base + dir * length
		stick(ctx, "Antenna", "Shade", base, tip, 0.13, "Cylinder")
		if perAntenna == 2 then
			tryPart(ctx, "AntennaTip", tipRole, Vector3.one * 0.4, CFrame.new(tip), "Ball")
		end
	end
end

-- -------------------------------------------------------------------
-- Ultra / Admin: Flügel + Heiligenschein
-- -------------------------------------------------------------------
-- anchor = Mitte des oberen Rückens, half = halbe Körperbreite dort, k = Flügelgröße
local function addWings(ctx: Ctx, anchor: Vector3, half: number, k: number)
	pair(ctx, function(side)
		local len = 1.35 * k
		local pos = anchor + Vector3.new(side * (half + len * 0.22), len * 0.25, 0)
		local cf = CFrame.new(pos)
			* CFrame.Angles(0, side * math.rad(-30), 0)
			* CFrame.Angles(0, 0, side * math.rad(30))
		makePart(ctx, "Wing", "Wing", Vector3.new(len, len * 0.62, 0.22 * k), cf, "Ellipsoid")
	end)
	if ctx.admin then
		-- Admin: zweites, kleineres Flügelpaar darunter (Seraph-Look)
		pair(ctx, function(side)
			local len = 1.15 * k
			local pos = anchor + Vector3.new(side * (half + len * 0.25), -len * 0.3, 0.1)
			local cf = CFrame.new(pos)
				* CFrame.Angles(0, side * math.rad(-35), 0)
				* CFrame.Angles(0, 0, side * math.rad(-20))
			makePart(ctx, "Wing", "Wing", Vector3.new(len, len * 0.55, 0.2 * k), cf, "Ellipsoid")
		end)
	end
end

local function addHalo(ctx: Ctx, pos: Vector3, diameter: number)
	tryPart(
		ctx,
		"Halo",
		"Halo",
		Vector3.new(0.12, diameter, diameter),
		CFrame.new(pos) * CFrame.Angles(math.rad(-12), 0, 0) * CFrame.Angles(0, 0, math.rad(90)),
		"Cylinder"
	)
end

local function isUltra(ctx: Ctx): boolean
	return ctx.tier >= 3 or ctx.admin
end

-- Flügel + Heiligenschein (nur Ultra/Admin). Der Schein wird nur vorgemerkt (1 Teil reserviert) und
-- am Ende über dem höchsten Punkt gebaut (finishUltra), damit er nie in Antennen/Krone steckt.
-- haloZ = nil -> nur Flügel.
local function addUltra(ctx: Ctx, anchor: Vector3, half: number, haloZ: number?)
	if not isUltra(ctx) then
		return
	end
	addWings(ctx, anchor, half, ctx.admin and 1.15 or 1)
	if haloZ and room(ctx, 1) then
		ctx.haloZ = haloZ
		ctx.max -= 1
	end
end

local function finishUltra(ctx: Ctx)
	local haloZ = ctx.haloZ
	if haloZ then
		ctx.haloZ = nil
		ctx.max += 1
		addHalo(ctx, Vector3.new(0, ctx.top + 0.4, haloZ), ctx.admin and 1.7 or 1.4)
	end
end

-- -------------------------------------------------------------------
-- KÖRPERFORMEN – jede gibt (Body, Höhe der Body-Mitte) zurück.
-- Reihenfolge = Wichtigkeit (was am Ende nicht mehr ins Budget passt, fällt weg).
-- -------------------------------------------------------------------
local Builders: { [string]: Builder } = {}

-- Mochi-Schleim mit Tropfen-Spitze. Selten: runde Öhrchen.
Builders.Blob = function(ctx: Ctx): (Part, number)
	local face: Face = { c = Vector3.new(0, 1.2, 0), r = Vector3.new(1.55, 1.2, 1.45) }
	local body = makePart(ctx, "Body", "Main", face.r * 2, CFrame.new(face.c), "Ellipsoid")
	makePart(
		ctx,
		"Top",
		"Main",
		Vector3.new(0.62, 0.95, 0.62),
		CFrame.new(0.1, 2.38, 0.05) * CFrame.Angles(0, 0, math.rad(-16)),
		"Ellipsoid"
	)
	addEyes(ctx, face, 1.45, 0.56, 0.82)
	local mouth = addMouth(ctx, face, 0.9, 0.44, "Open")
	if ctx.tier >= 2 then
		pair(ctx, function(side)
			makePart(
				ctx,
				"Ear",
				"Main",
				Vector3.new(0.75, 0.75, 0.5),
				CFrame.new(side * 1.0, 2.05, 0.1) * CFrame.Angles(0, 0, math.rad(side * -25)),
				"Ellipsoid"
			)
		end)
	end
	addUltra(ctx, Vector3.new(0, 1.55, 0.95), 0.85, 0.05)
	addBlush(ctx, face, 1.0, 0.98, 1)
	addAntennas(ctx, function(x)
		return topY(face, x, 0)
	end, 0, 0.55, 0.85, math.rad(22), 0, -0.55)
	addTongue(ctx, mouth, 0.44)
	return body, face.c.Y
end

-- Einäugiges Monsterchen auf zwei Füßen. Selten: heller Bauch.
Builders.Cyclops = function(ctx: Ctx): (Part, number)
	local face: Face = { c = Vector3.new(0, 1.9, 0), r = Vector3.new(1.3, 1.45, 1.2) }
	local body = makePart(ctx, "Body", "Main", face.r * 2, CFrame.new(face.c), "Ellipsoid")
	addFeet(ctx, 0.58, -0.12, Vector3.new(0.85, 0.5, 1.05), "Shade")
	if ctx.eyes == 1 then
		addBigEye(ctx, face, 2.35, 1.3)
	else
		addEyes(ctx, face, 2.3, 0.5, 0.75)
	end
	local mouth = addMouth(ctx, face, 1.5, 0.5, "Open")
	if ctx.tier >= 2 then
		addPatch(ctx, "Belly", "Light", face, 0.95, Vector3.new(1.3, 0.95, 0.5))
	end
	addUltra(ctx, Vector3.new(0, 2.2, 0.95), 0.75, 0.05)
	pair(ctx, function(side)
		stick(
			ctx,
			"Arm",
			"Main",
			Vector3.new(side * 1.1, 1.85, 0),
			Vector3.new(side * 1.5, 1.25, -0.15),
			0.5,
			"Ellipsoid"
		)
	end)
	addBlush(ctx, face, 1.75, 0.92, 1)
	addAntennas(ctx, function(x)
		return topY(face, x, 0)
	end, 0, 0.5, 0.8, math.rad(25), 0)
	addTongue(ctx, mouth, 0.5)
	return body, face.c.Y
end

-- Kawaii-Oktopus: runder Kopf, kurze dicke Tentakel. Selten: Locke in Akzentfarbe.
Builders.Squid = function(ctx: Ctx): (Part, number)
	local face: Face = { c = Vector3.new(0, 2.3, 0), r = Vector3.new(1.35, 1.35, 1.3) }
	local body = makePart(ctx, "Body", "Main", face.r * 2, CFrame.new(face.c), "Ellipsoid")
	local function tentacle(angle: number)
		local dir = Vector3.new(math.sin(angle), 0, -math.cos(angle))
		stick(
			ctx,
			"Tentacle",
			"Main",
			dir * 0.55 + Vector3.new(0, 1.25, 0),
			dir * 1.45 + Vector3.new(0, 0.28, 0),
			0.56,
			"Ellipsoid"
		)
	end
	addEyes(ctx, face, 2.3, 0.55, 0.78)
	addMouth(ctx, face, 1.7, 0.42, "O")
	for _, deg in ipairs({ -40, 40, -110, 110 }) do
		tentacle(math.rad(deg))
	end
	if ctx.tier >= 2 then
		tryPart(
			ctx,
			"Top",
			"Accent",
			Vector3.new(0.5, 0.85, 0.5),
			CFrame.new(0.15, 3.65, 0.1) * CFrame.Angles(0, 0, math.rad(-20)),
			"Ellipsoid"
		)
	end
	addUltra(ctx, Vector3.new(0, 2.4, 0.95), 0.85, 0.05)
	addBlush(ctx, face, 1.9, 0.88, 1)
	pair(ctx, function(side)
		tentacle(math.rad(side * 170))
	end)
	addAntennas(ctx, function(x)
		return topY(face, x, 0)
	end, 0, 0.5, 0.8, math.rad(20), 0, -0.5)
	return body, face.c.Y
end

-- Marienkäfer: runder Panzer mit Mittelnaht, heller Kopf mit Fühlern. Selten: zwei Punkte.
Builders.Bug = function(ctx: Ctx): (Part, number)
	ctx.faceRole = "Light"
	local shell: Face = { c = Vector3.new(0, 1.2, 0.35), r = Vector3.new(1.35, 0.95, 1.35) }
	local body = makePart(ctx, "Body", "Main", shell.r * 2, CFrame.new(shell.c), "Ellipsoid")
	local head: Face = { c = Vector3.new(0, 1.3, -0.85), r = Vector3.new(0.9, 0.82, 0.72) }
	makePart(ctx, "Head", "Light", head.r * 2, CFrame.new(head.c), "Ellipsoid")
	addEyes(ctx, head, 1.45, 0.38, 0.58)
	local mouth = addMouth(ctx, head, 0.98, 0.32, "Open")
	makePart(
		ctx,
		"Seam",
		"Dark",
		Vector3.new(0.1, shell.r.Y * 2 + 0.03, shell.r.Z * 2 + 0.03),
		CFrame.new(shell.c + Vector3.new(0, 0, 0.02)),
		"Ellipsoid"
	)
	for _, z in ipairs({ -0.15, 0.85 }) do
		pair(ctx, function(side)
			stick(
				ctx,
				"Leg",
				"Dark",
				Vector3.new(side * 0.95, 0.6, z),
				Vector3.new(side * 1.35, 0.14, z - 0.1),
				0.28,
				"Ellipsoid"
			)
		end)
	end
	if ctx.tier >= 2 then
		pair(ctx, function(side)
			local x, z = side * 0.62, 0.55
			makePart(
				ctx,
				"Spot",
				"Accent",
				Vector3.new(0.62, 0.3, 0.62),
				CFrame.new(x, topY(shell, x, z) - 0.1, z),
				"Ellipsoid"
			)
		end)
	end
	addUltra(ctx, Vector3.new(0, 1.7, 0.6), 0.8, -0.75)
	addBlush(ctx, head, 1.08, 0.55, 0.75)
	addAntennas(ctx, function(x)
		return topY(head, x, head.c.Z)
	end, head.c.Z, 0.3, 0.85, math.rad(25), math.rad(25))
	addTongue(ctx, mouth, 0.32)
	return body, shell.c.Y
end

-- Knuffiger Roboter: großer Kopf mit Bildschirm-Gesicht, Rolle statt Beine. Selten: Akzent-Streifen.
Builders.Robot = function(ctx: Ctx): (Part, number)
	ctx.faceRole = "Dark"
	makePart(ctx, "Treads", "Metal", Vector3.new(1.8, 0.8, 0.8), CFrame.new(0, 0.4, 0), "Cylinder")
	local bodyY = 1.4
	local body = makePart(ctx, "Body", "Main", Vector3.new(1.7, 1.2, 1.4), CFrame.new(0, bodyY, 0))
	local headY = 2.85
	makePart(ctx, "Head", "Main", Vector3.new(2.3, 1.7, 1.8), CFrame.new(0, headY, 0))
	makePart(ctx, "Visor", "Dark", Vector3.new(1.9, 1.25, 0.1), CFrame.new(0, headY, -0.92))
	local screen = flatFace(0, headY, -0.97)
	for _, offset in ipairs(eyeLayout(ctx.eyes, ctx.eyes >= 3 and 0.36 or 0.45)) do
		local h = ctx.eyes >= 3 and 0.4 or 0.55
		makePart(
			ctx,
			"Eye",
			"Glow",
			Vector3.new(h * 0.72, h, 0.1),
			onFace(screen, offset.X, headY + 0.12 + offset.Y * h, 0),
			"Ellipsoid"
		)
	end
	tryPart(ctx, "Mouth", "Glow", Vector3.new(0.5, 0.14, 0.08), onFace(screen, 0, headY - 0.38, 0), "Ellipsoid")
	if ctx.tier >= 2 then
		tryPart(ctx, "Stripe", "Accent", Vector3.new(2.34, 0.3, 1.84), CFrame.new(0, headY + 0.62, 0))
	end
	addUltra(ctx, Vector3.new(0, headY - 0.1, 0.75), 1.0, 0.05)
	pair(ctx, function(side)
		makePart(ctx, "Ear", "Metal", Vector3.new(0.3, 0.75, 0.75), CFrame.new(side * 1.25, headY, 0), "Cylinder")
	end)
	pair(ctx, function(side)
		stick(
			ctx,
			"Arm",
			"Shade",
			Vector3.new(side * 0.9, 1.75, 0),
			Vector3.new(side * 1.28, 1.05, -0.15),
			0.42,
			"Ellipsoid"
		)
	end)
	addAntennas(ctx, function()
		return headY + 0.85
	end, 0, 0.55, 0.75, math.rad(15), 0)
	tryPart(ctx, "ChestLight", "Glow", Vector3.one * 0.38, CFrame.new(0, bodyY + 0.05, -0.7), "Ball")
	return body, bodyY
end

-- Schwebendes Gespenst mit Wellen-Saum. Selten: Schleife.
Builders.Ghost = function(ctx: Ctx): (Part, number)
	ctx.mainTransparency = math.max(ctx.mainTransparency, 0.08)
	local face: Face = { c = Vector3.new(0, 2.3, 0), r = Vector3.new(1.3, 1.5, 1.25) }
	local body = makePart(ctx, "Body", "Main", face.r * 2, CFrame.new(face.c), "Ellipsoid")
	addEyes(ctx, face, 2.55, 0.5, 0.8)
	local mouth = addMouth(ctx, face, 1.95, 0.42, "Open")
	for i = 0, 2 do
		local angle = math.rad(-60 + 120 * i)
		makePart(
			ctx,
			"Wisp",
			"Main",
			Vector3.new(0.95, 0.85, 0.95),
			CFrame.new(math.sin(angle) * 0.78, 0.9, -math.cos(angle) * 0.78),
			"Ellipsoid"
		)
	end
	if ctx.tier >= 2 and room(ctx, 3) then
		local knot = Vector3.new(0.75, 3.55, -0.1)
		for _, side in ipairs({ -1, 1 }) do
			makePart(
				ctx,
				"Bow",
				"Accent",
				Vector3.new(0.6, 0.42, 0.25),
				CFrame.new(knot + Vector3.new(side * 0.3, 0, 0)) * CFrame.Angles(0, 0, math.rad(side * 20)),
				"Ellipsoid"
			)
		end
		makePart(ctx, "Bow", "Accent", Vector3.one * 0.26, CFrame.new(knot + Vector3.new(0, 0, -0.04)), "Ball")
	end
	addUltra(ctx, Vector3.new(0, 2.5, 0.9), 0.8, 0.05)
	pair(ctx, function(side)
		stick(
			ctx,
			"Arm",
			"Main",
			Vector3.new(side * 1.05, 2.2, 0),
			Vector3.new(side * 1.5, 1.75, -0.25),
			0.5,
			"Ellipsoid"
		)
	end)
	addBlush(ctx, face, 2.1, 0.86, 1)
	addAntennas(ctx, function(x)
		return topY(face, x, 0)
	end, 0, 0.45, 0.8, math.rad(20), 0)
	addTongue(ctx, mouth, 0.42)
	return body, face.c.Y
end

-- Lebender Edelstein (Raute) auf einem Felsen, flankiert von zwei Kristallen. Selten: Kristalle leuchten.
Builders.Crystal = function(ctx: Ctx): (Part, number)
	ctx.mainReflectance = math.max(ctx.mainReflectance, 0.15)
	makePart(ctx, "Rock", "Rock", Vector3.new(3.0, 0.8, 2.6), CFrame.new(0, 0.4, 0), "Ellipsoid")
	local side, depth = 1.75, 1.25
	local bodyY = 0.5 + side * math.sqrt(0.5)
	local body = makePart(
		ctx,
		"Body",
		"Main",
		Vector3.new(side, side, depth),
		CFrame.new(0, bodyY, 0) * CFrame.Angles(0, 0, math.rad(45))
	)
	local face = flatFace(0, bodyY, -depth / 2)
	addEyes(ctx, face, bodyY + 0.2, 0.38, 0.6)
	local mouth = addMouth(ctx, face, bodyY - 0.32, 0.36, "Open")
	local shardRole = ctx.tier >= 2 and "Glow" or "Light"
	pair(ctx, function(sideSign)
		makePart(
			ctx,
			"Shard",
			shardRole,
			Vector3.new(0.6, 1.4, 0.6),
			CFrame.new(sideSign * 1.2, 1.05, 0.3)
				* CFrame.Angles(0, 0, math.rad(-sideSign * 22))
				* CFrame.Angles(0, math.rad(45), 0)
		)
	end)
	addUltra(ctx, Vector3.new(0, bodyY + 0.2, 0.55), 0.7, 0.05)
	addBlush(ctx, face, bodyY - 0.15, 0.62, 0.85)
	addAntennas(ctx, function()
		return bodyY + side * 0.707 - 0.15
	end, 0, 0.25, 0.75, math.rad(25), 0)
	addTongue(ctx, mouth, 0.36)
	return body, bodyY
end

-- Igel: runder Körper, weiche Stacheln auf Rücken + Kopf, Schnäuzchen. Selten: freche Augenbrauen.
Builders.Spiky = function(ctx: Ctx): (Part, number)
	local face: Face = { c = Vector3.new(0, 1.4, 0), r = Vector3.new(1.4, 1.3, 1.35) }
	local body = makePart(ctx, "Body", "Main", face.r * 2, CFrame.new(face.c), "Ellipsoid")
	addEyes(ctx, face, 1.6, 0.52, 0.72)
	local snout = addPatch(ctx, "Snout", "Light", face, 1.05, Vector3.new(0.8, 0.52, 0.75))
	if snout then
		tryPart(ctx, "Nose", "Dark", Vector3.new(0.3, 0.2, 0.2), snout * CFrame.new(0, 0.12, -0.32), "Ellipsoid")
	end
	local function spike(dir: Vector3)
		local d = dir.Unit
		tryPart(
			ctx,
			"Spike",
			"Accent",
			Vector3.new(1.25, 0.5, 0.5),
			axisCFrame(face.c + Vector3.new(d.X * 1.25, d.Y * 1.15, d.Z * 1.2), d),
			"Ellipsoid"
		)
	end
	spike(Vector3.new(0, 1, 0.3))
	for _, dir in ipairs({ Vector3.new(0.6, 0.75, 0.4), Vector3.new(0.75, 0.25, 0.75) }) do
		if room(ctx, 2) then
			spike(dir)
			spike(Vector3.new(-dir.X, dir.Y, dir.Z))
		end
	end
	addFeet(ctx, 0.6, -0.3, Vector3.new(0.75, 0.42, 0.95), "Shade")
	if ctx.tier >= 2 then
		pair(ctx, function(side)
			local cf = onFace(face, side * 0.5, 2.12, 0.02) * CFrame.Angles(0, 0, math.rad(side * -15))
			makePart(ctx, "Brow", "Dark", Vector3.new(0.5, 0.14, 0.14), cf, "Ellipsoid")
		end)
	end
	addUltra(ctx, Vector3.new(0, 1.7, 1.0), 0.8, 0.25)
	addBlush(ctx, face, 1.12, 0.95, 1)
	if room(ctx, 1) then
		spike(Vector3.new(0, 0.45, 1))
	end
	addAntennas(ctx, function(x)
		return topY(face, x, 0)
	end, 0, 0.5, 0.8, math.rad(25), 0)
	return body, face.c.Y
end

-- König: runder Körper, goldene Krone mit Edelstein, Umhang, Schnurrbart. Selten: Zepter.
-- Ultra: Flügel + der Kronen-Edelstein leuchtet (statt Heiligenschein).
Builders.King = function(ctx: Ctx): (Part, number)
	local face: Face = { c = Vector3.new(0, 1.45, 0), r = Vector3.new(1.4, 1.3, 1.3) }
	local body = makePart(ctx, "Body", "Main", face.r * 2, CFrame.new(face.c), "Ellipsoid")
	local crownY = 2.85
	makePart(
		ctx,
		"Crown",
		"Gold",
		Vector3.new(0.55, 1.55, 1.55),
		CFrame.new(0, crownY, 0.05) * CFrame.Angles(0, 0, math.rad(90)),
		"Cylinder"
	)
	for _, pos in ipairs({
		Vector3.new(0, crownY + 0.38, -0.62),
		Vector3.new(-0.62, crownY + 0.38, 0.05),
		Vector3.new(0.62, crownY + 0.38, 0.05),
	}) do
		makePart(ctx, "CrownPoint", "Gold", Vector3.new(0.4, 0.75, 0.4), CFrame.new(pos), "Ellipsoid")
	end
	addEyes(ctx, face, 1.8, 0.52, 0.72)
	if room(ctx, 2) then
		for _, side in ipairs({ -1, 1 }) do
			local cf = onFace(face, side * 0.28, 1.28, 0.02) * CFrame.Angles(0, 0, math.rad(side * 12))
			makePart(ctx, "Mustache", "Dark", Vector3.new(0.62, 0.26, 0.24), cf, "Ellipsoid")
		end
	end
	tryPart(ctx, "Cape", "Cape", Vector3.new(2.6, 2.3, 0.35), CFrame.new(0, 1.4, 1.12), "Ellipsoid")
	tryPart(
		ctx,
		"Gem",
		isUltra(ctx) and "Glow" or "Accent",
		Vector3.one * (isUltra(ctx) and 0.42 or 0.32),
		CFrame.new(0, crownY, -0.78),
		"Ball"
	)
	if ctx.tier >= 2 and room(ctx, 2) then
		stick(ctx, "Scepter", "Gold", Vector3.new(1.45, 0.35, -0.45), Vector3.new(1.45, 2.15, -0.45), 0.16, "Cylinder")
		makePart(ctx, "ScepterGem", "Accent", Vector3.one * 0.42, CFrame.new(1.45, 2.3, -0.45), "Ball")
	end
	addUltra(ctx, Vector3.new(0, 1.9, 1.0), 0.85, nil)
	addFeet(ctx, 0.58, -0.4, Vector3.new(0.82, 0.45, 1.0), "Shade")
	addBlush(ctx, face, 1.45, 0.98, 1)
	addAntennas(ctx, function()
		return crownY + 0.25
	end, 0.3, 0.45, 0.8, math.rad(25), 0)
	return body, face.c.Y
end

-- Pilz: Gesicht im hellen Stiel, großer Hut mit drei Punkten. Selten: Blätter-Spross auf dem Hut.
Builders.Mushroom = function(ctx: Ctx): (Part, number)
	ctx.faceRole = "Stalk"
	local face: Face = { c = Vector3.new(0, 1.15, 0), r = Vector3.new(1.05, 1.15, 1.0) }
	local body = makePart(ctx, "Body", "Stalk", face.r * 2, CFrame.new(face.c), "Ellipsoid")
	local cap: Face = { c = Vector3.new(0, 2.55, 0.05), r = Vector3.new(1.8, 0.95, 1.7) }
	makePart(ctx, "Cap", "Main", cap.r * 2, CFrame.new(cap.c), "Ellipsoid")
	addEyes(ctx, face, 1.3, 0.4, 0.62)
	local mouth = addMouth(ctx, face, 0.8, 0.36, "Open")
	local function spot(x: number, z: number)
		local y = topY(cap, x, z)
		local up = Vector3.new(x / cap.r.X ^ 2, (y - cap.c.Y) / cap.r.Y ^ 2, (z - cap.c.Z) / cap.r.Z ^ 2)
		tryPart(
			ctx,
			"Spot",
			"Accent",
			Vector3.new(0.68, 0.68, 0.26),
			facing(Vector3.new(x, y - 0.06, z), up),
			"Ellipsoid"
		)
	end
	spot(0, -0.55)
	if room(ctx, 2) then
		spot(-1.05, -0.35)
		spot(1.05, -0.35)
	end
	if ctx.tier >= 2 then
		pair(ctx, function(side)
			makePart(
				ctx,
				"Leaf",
				"Leaf",
				Vector3.new(0.7, 0.24, 0.42),
				CFrame.new(side * 0.3, 3.55, 0.3) * CFrame.Angles(0, 0, math.rad(side * 35)),
				"Ellipsoid"
			)
		end)
	end
	addUltra(ctx, Vector3.new(0, 1.7, 0.85), 0.75, 0.05)
	addFeet(ctx, 0.5, -0.25, Vector3.new(0.7, 0.4, 0.85), "StalkShade")
	addBlush(ctx, face, 0.98, 0.66, 0.85)
	addAntennas(ctx, function(x)
		return topY(cap, x, cap.c.Z)
	end, cap.c.Z, 0.55, 0.8, math.rad(20), 0)
	addTongue(ctx, mouth, 0.36)
	return body, face.c.Y
end

-- -------------------------------------------------------------------
-- Effekte + Namensschild
-- -------------------------------------------------------------------
-- Glitzer-Partikel rund ums Alien (Aura der seltenen Aliens, Regenbogen-Mutation)
local function addAura(body: Part, color: ColorSequence, s: number, rate: number)
	local aura = Instance.new("ParticleEmitter")
	aura.Name = "Aura"
	aura.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	aura.Color = color
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
	aura.Rate = rate
	aura.Parent = body
end

-- Frost-Mutation: ein paar Schneeflocken rieseln vom Alien herab
local function addSnow(body: Part, s: number, carry: boolean)
	local snow = Instance.new("ParticleEmitter")
	snow.Name = "FrostSnow"
	snow.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	snow.Color = ColorSequence.new(WHITE, FROST_LIGHT)
	snow.LightEmission = 0.5
	snow.LightInfluence = 0.2
	snow.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.22 * s),
		NumberSequenceKeypoint.new(1, 0),
	})
	snow.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	snow.Lifetime = NumberRange.new(1.2, 2)
	snow.Speed = NumberRange.new(0.2, 0.6)
	snow.SpreadAngle = Vector2.new(180, 180)
	snow.Acceleration = Vector3.new(0, -1.5 * s, 0)
	snow.Drag = 1
	snow.RotSpeed = NumberRange.new(-60, 60)
	snow.Rate = carry and 2 or 4
	snow.Parent = body
end

local function addEffects(model: Model, body: Part, alien: AlienDef, mut: any, s: number, carry: boolean)
	local fx = alien.Effects
	local rank = rarityRank(alien.Rarity)
	local color = rarityColor(alien.Rarity)
	local accent = alien.Look.Accent
	local rainbowMut = mut.Rainbow == true
	local mutName = tostring(mut.Name)

	-- Umriss: nur Ultra-Admin-Aliens, getragen keiner. Startet AUS – der Client schaltet nur die
	-- nächsten paar ein (Roblox zeigt höchstens 31 Highlights gleichzeitig, jedes kostet einen Render-Durchgang).
	if fx.Highlight and not carry and alien.Tier == HIGHLIGHT_TIER and alien.Rarity == HIGHLIGHT_RARITY then
		local highlight = Instance.new("Highlight")
		highlight.Name = "Glow"
		highlight.Enabled = false
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.FillColor = color
		highlight.FillTransparency = 0.85
		highlight.OutlineColor = accent
		highlight.OutlineTransparency = 0.1
		if fx.Rainbow or rainbowMut then
			highlight:SetAttribute("Rainbow", true)
		end
		highlight.Parent = model
	end

	if fx.Aura then
		local rate = rank >= ADMIN_RANK and 18 or (rank >= 8 and 10 or 6)
		local auraColor = (fx.Rainbow or rainbowMut) and RAINBOW_SEQUENCE or ColorSequence.new(color, accent)
		addAura(body, auraColor, s, carry and math.ceil(rate / 2) or rate)
	elseif rainbowMut then
		-- Regenbogen-Mutation: bunte Glitzer-Aura auch ohne eigene Aura
		addAura(body, RAINBOW_SEQUENCE, s, carry and 3 or 6)
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
	elseif mutName == "Lava" then
		-- Lava-Mutation: kleines Feuer (nur eins pro Alien)
		local fire = Instance.new("Fire")
		fire.Name = "LavaFire"
		fire.Color = typeof(mut.Color) == "Color3" and mut.Color or LAVA_ORANGE
		fire.SecondaryColor = LAVA_DARK
		fire.Size = math.clamp(2.2 * s, 2, 6)
		fire.Heat = 4
		fire.Parent = body
	end

	if mutName == "Frost" then
		addSnow(body, s, carry)
	end

	if mutName == "Cosmic" then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = mut.Color or color
		sparkles.Parent = body
	elseif rainbowMut and not carry then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = WHITE
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

-- Schild aktualisieren: Name, "Stufe • Seltenheit [• 🔥 Mutation]", "$X/s ⚡Lv n"
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
			tag ..= " • " .. mutationText(mut)
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

	-- Mutation: Regenbogen färbt der Client durch (eigene Farbe bleibt als Grundfarbe),
	-- alle anderen färben den Körper in der Mutationsfarbe (+ Material aus MUT_STYLES)
	local mutName = tostring(mut.Name)
	local rainbowMut = mut.Rainbow == true
	local mutColor: Color3? = nil
	if not rainbowMut and mutName ~= "Normal" and typeof(mut.Color) == "Color3" then
		mutColor = mut.Color
	end

	local ctx: Ctx = {
		model = model,
		s = s,
		color = look.Color,
		accent = look.Accent,
		eyes = look.Eyes,
		antennas = look.Antennas,
		tier = TIER_INDEX[alien.Tier] or 1,
		rank = rank,
		admin = rank >= ADMIN_RANK,
		faceRole = "Main",
		mutStyle = if rainbowMut then nil else MUT_STYLES[mutName],
		mutColor = mutColor,
		rainbow = fx.Rainbow == true or rainbowMut,
		rainbowShade = rainbowMut,
		carry = carry,
		mainMaterial = Enum.Material.SmoothPlastic,
		mainTransparency = 0,
		mainReflectance = look.Archetype == "Robot" and 0.12 or 0,
		count = 0,
		max = rank >= ADMIN_RANK and MAX_PARTS_ADMIN or MAX_PARTS,
		top = 0,
	}

	local builder = Builders[look.Archetype] or Builders.Blob
	local body, bodyY = builder(ctx)
	finishUltra(ctx)
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
	model:SetAttribute("Mutation", mutName)
	model:SetAttribute("Bob", not carry) -- getragene Aliens nicht wippen (würde den Spieler mitbewegen)
	if ctx.rainbow then
		model:SetAttribute("Rainbow", true)
	end
	-- für Refresh: Höhen beim Bauen (inkl. Skalierung) + Level-Faktor beim Bauen
	model:SetAttribute("PivotHeight", bodyY * s)
	model:SetAttribute("TopHeight", ctx.top * s)
	model:SetAttribute("BuiltLevelScale", lvScale)
	-- nur für Client-Animationen (Squash & Stretch, Bewegungsstil): Body-Größe beim Bauen, Körperform
	model:SetAttribute("Archetype", look.Archetype)
	body:SetAttribute("BaseSize", body.Size)

	addEffects(model, body, alien, mut, s, carry)

	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.Size = UDim2.new(0, 240, 0, 70)
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
		body:SetAttribute("BaseSize", body.Size) -- Client-Squash rechnet mit der neuen Größe
		-- Zähler: der Client (Wippen) merkt daran, dass sich die Teile verändert haben
		model:SetAttribute("Rev", (tonumber(model:GetAttribute("Rev")) or 0) + 1)
	end
	updateLabelOffset(model, body)
	AlienFactory.UpdateLabel(model, entry)
end

return AlienFactory
