-- Baut das Aussehen eines Meteor-Eis (Roblox-Look wie Steal an Egg / Pet Simulator): klare Ei-Form
-- (Kugel + SpecialMesh "EggShape", Größe/Hitbox bleibt die Kugel), kräftige SmoothPlastic-Farben,
-- Größe nach Seltenheit, seltene Eier glänzen (Reflectance + Licht), Material/Farbe nach Mutation,
-- Spezial-Effekte der Admin-Meteore, Namensschild darüber (ohne Kasten, siehe SCHILD-STIL).
-- Lichter und Partikel gibt es bewusst sparsam (viele Eier gleichzeitig = sonst Lag).
-- Dazu: Prompts anlegen (AddPrompt) und serverseitig prüfen, ob lange genug gehalten wurde (OnHeldTrigger).
--
-- KRASSE EIER (ab Legendary, im Nest / am Boden / in der Base – nicht beim Tragen):
--   • Lichtsäule (Beam zwischen zwei Attachments, nach oben verblassend)
--   • Glitzer-Partikel "RareSparkle" in Seltenheitsfarbe
--   • Mythic+: Funkenregen "RareSparks" (+ Blitze, die der Client lokal zeichnet)
--   • Secret..Cosmic/Admin: Regenbogen-Aura "RareAura" und Regenbogen-Säule
--   • Infinity: dazu kreisende Sterne "RareInfinity", breitere + höhere Säule (stärkster Effekt)
--   • Attribut "RareFX" = Stufe (1 Legendary, 2 Mythic..Divine, 3 Secret..Cosmic/Admin, 4 Infinity):
--     der Client (WorldFX)
--     dreht damit lokal einen Ring ums Ei, lässt das Licht pulsieren und schaltet die Partikel nur in
--     Kameranähe ein (Emitter starten deshalb AUS).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))

local MeteorFactory = {}

-- Ab welcher Seltenheit (Index in Config.Rarities) gibt es ein Licht?
-- (Glitzern macht ab Legendary "RareSparkle" – nur in Kameranähe an, siehe unten)
local LIGHT_FROM = { Base = 5, Ground = 5, Nest = 5, Carry = 7 }
local SHADOW_MIN_SIZE = 3.5 -- nur große Meteore werfen Schatten
local FROST_WHITEN = 0.4 -- Frost-Meteore etwas weißer als die Mutationsfarbe (sonst fast wie Diamond)

-- Ei-Look
local EGG_WIDTH = 0.86 -- sichtbar schmaler als hoch = Ei (nur der Mesh, Part.Size bleibt die Kugel)
local RARE_SHINE = 0.15 -- ab Legendary glänzen die Eier (Reflectance)
local GOLD_SHINE = 0.3 -- Gold-Mutation: glänzendes Gold statt Folie
local VIVID_SAT = 0.3 -- Ei-Farben satter: Sättigung + so viel vom Rest
local VIVID_VAL = 0.15 -- ... und etwas heller

-- Krasse Eier (siehe oben)
local RARE_FROM = Config.RarityIndex.Legendary or 5
local RARE_MYTHIC = Config.RarityIndex.Mythic or 6
local RARE_SECRET = Config.RarityIndex.Secret or 9
local RARE_INFINITY = Config.RarityIndex.Infinity or 12
local RARE_MODES: { [string]: boolean } = { Nest = true, Ground = true, Base = true }
local PILLAR_HEIGHT = 28

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GREEN = Color3.fromRGB(90, 255, 100) -- Geld / Einkommen
local YELLOW = Color3.fromRGB(255, 225, 60) -- Preis
local HATCH_COLOR = Color3.fromRGB(255, 220, 120)

function MeteorFactory.GetSize(entry): number
	local def = Config.MeteorsById[entry.Id]
	local rarity = def and Config.RaritiesByName[def.Rarity] or Config.Rarities[1]
	return rarity.Size * (1 + 0.025 * ((entry.Lv or 1) - 1))
end

-- Farbverlauf durch alle Regenbogenfarben (Säule + Aura der Secret/Admin-Eier, Schilder ab Infinity)
local function rainbowSequence(): ColorSequence
	local keys = {}
	for i = 0, 6 do
		table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 0.85, 1)))
	end
	return ColorSequence.new(keys)
end

-- Kräftigere Farbe (Roblox-Look): satter + etwas heller. Grau bleibt grau, sehr Dunkles bleibt dunkel.
-- amount = Stärke (1 = wie bei den Eiern); die AlienFactory nimmt weniger.
function MeteorFactory.Vivid(color: Color3, amount: number?): Color3
	local k = amount or 1
	local h, s, v = color:ToHSV()
	if s > 0.12 then
		s += (1 - s) * VIVID_SAT * k
	end
	if v > 0.25 then
		v += (1 - v) * VIVID_VAL * k
	end
	return Color3.fromHSV(h, s, v)
end

-- -------------------------------------------------------------------
-- SCHILD-STIL (wie Steal a Brainrot) – auch die AlienFactory baut ihre Schilder hiermit:
-- KEIN Kasten (das Frame "Frame" bleibt, ist aber komplett unsichtbar), nur Text in FredokaOne
-- mit dicker schwarzer Kontur. Aufbau: BillboardGui "Info" > Frame "Frame" > NameLabel,
-- RarityLabel, ValueLabel (Namen werden gesucht – nicht ändern!).
--   NameLabel   = Name (weiß), davor evtl. die Mutation in ihrer Farbe (RichText)
--   RarityLabel = Seltenheit in Seltenheitsfarbe; ab Mythic mit Farbverlauf (UIGradient
--                 "RarityGradient", statisch – der Client darf ihn lokal animieren)
--   ValueLabel  = Preis (gelb) bzw. Einkommen "$12/s" (grün)
-- -------------------------------------------------------------------
local INFO_SIZE = UDim2.fromOffset(300, 82)
local NAME_TEXT = 22
local RARITY_TEXT = 18
local VALUE_TEXT = 20
local MUT_TEXT = 17 -- Mutation vor dem Namen etwas kleiner
local STROKE_NAME = 3
local STROKE_TEXT = 2.5
local GRADIENT_NAME = "RarityGradient"
local GRADIENT_FROM = Config.RarityIndex.Mythic or 6 -- ab dieser Seltenheit: Farbverlauf
local rgb = Color3.fromRGB
-- Verlauf (links, Mitte, rechts) je Seltenheit; Infinity/Admin = Regenbogen.
-- Unbekannte hohe Seltenheiten bekommen automatisch einen hellen Glanz in ihrer Farbe.
local RARITY_GRADIENTS: { [string]: { Color3 } } = {
	Mythic = { rgb(255, 60, 90), rgb(255, 170, 70), rgb(255, 60, 160) },
	Celestial = { rgb(90, 230, 255), rgb(255, 255, 255), rgb(90, 140, 255) },
	Divine = { rgb(255, 225, 110), rgb(255, 255, 230), rgb(255, 180, 60) },
	Secret = { rgb(255, 255, 255), rgb(160, 235, 255), rgb(255, 180, 240) },
	Godly = { rgb(255, 210, 0), rgb(255, 250, 190), rgb(255, 140, 0) },
	Cosmic = { rgb(110, 90, 255), rgb(230, 100, 255), rgb(80, 200, 255) },
}
local RAINBOW_RARITIES: { [string]: boolean } = { Infinity = true, Admin = true }

local function gradientSequence(rarityName: string, color: Color3): ColorSequence
	if RAINBOW_RARITIES[rarityName] then
		return rainbowSequence()
	end
	local keys = RARITY_GRADIENTS[rarityName] or { color, color:Lerp(WHITE, 0.55), color }
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, keys[1]),
		ColorSequenceKeypoint.new(0.5, keys[2]),
		ColorSequenceKeypoint.new(1, keys[3]),
	})
end

-- RichText: Sonderzeichen im Namen dürfen keine Tags werden
local function escapeRich(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function colored(text: string, color: Color3): string
	return '<font color="#' .. color:ToHex() .. '">' .. text .. "</font>"
end

-- Jeder Buchstabe in einer anderen Regenbogenfarbe (für die Regenbogen-Mutation)
local function rainbowText(text: string): string
	local count = math.max(1, utf8.len(text) or #text)
	local parts = {}
	local i = 0
	for _, code in utf8.codes(text) do
		table.insert(parts, colored(escapeRich(utf8.char(code)), Color3.fromHSV(i / count * 0.85, 0.75, 1)))
		i += 1
	end
	return table.concat(parts)
end

-- "🔥 LAVA" vor dem Namen: Symbol + Mutationsname in Mutationsfarbe (Regenbogen = bunte Buchstaben)
function MeteorFactory.MutationPrefix(icon: string?, name: string, color: Color3?, rainbow: boolean?): string
	local upper = string.upper(name)
	local word = if rainbow then rainbowText(upper) else colored(escapeRich(upper), color or WHITE)
	local iconText = if icon and icon ~= "" then icon .. " " else ""
	return '<font size="' .. MUT_TEXT .. '">' .. iconText .. word .. "</font>  "
end

-- Name-Zeile: immer weiß (prefix = MutationPrefix oder nil)
function MeteorFactory.SetNameText(label: TextLabel, name: string, prefix: string?)
	label.RichText = true
	label.TextColor3 = WHITE
	label.Text = (prefix or "") .. escapeRich(name)
end

-- Seltenheits-Zeile: Seltenheitsfarbe, ab Mythic Farbverlauf. extra = Zusatz dahinter (z.B. die
-- Alien-Stufe "Ultra") in extraColor (beim Farbverlauf färbt der Verlauf alles).
function MeteorFactory.SetRarityText(
	label: TextLabel,
	rarityName: string,
	text: string,
	extra: string?,
	extraColor: Color3?
)
	local rarity = Config.RaritiesByName[rarityName]
	local color: Color3 = if rarity and typeof(rarity.Color) == "Color3" then rarity.Color else WHITE
	local index = Config.RarityIndex[rarityName] or 1
	local old = label:FindFirstChild(GRADIENT_NAME)
	local body = escapeRich(text)
	label.RichText = true
	if index >= GRADIENT_FROM then
		local gradient: UIGradient
		if old and old:IsA("UIGradient") then
			gradient = old
		else
			gradient = Instance.new("UIGradient")
			gradient.Name = GRADIENT_NAME
			gradient.Parent = label
		end
		gradient.Color = gradientSequence(rarityName, color)
		label.TextColor3 = WHITE -- Weiß x Verlauf = reine Verlaufsfarben (die Kontur bleibt schwarz)
		if extra then
			body ..= "  •  " .. escapeRich(extra)
		end
	else
		if old then
			old:Destroy()
		end
		label.TextColor3 = color
		if extra then
			local extraText = escapeRich(extra)
			body ..= "  •  " .. (if extraColor then colored(extraText, extraColor) else extraText)
		end
	end
	label.Text = body
end

local function makeLabel(parent: Instance, name: string, order: number, textSize: number, stroke: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Size = UDim2.new(1, 0, 0, textSize + 6)
	label.LayoutOrder = order
	label.Font = Enum.Font.FredokaOne
	label.TextSize = textSize
	label.TextColor3 = WHITE
	label.Text = ""
	local outline = Instance.new("UIStroke")
	outline.Thickness = stroke
	outline.Color = BLACK
	outline.LineJoinMode = Enum.LineJoinMode.Round
	outline.Parent = label
	label.Parent = parent
	return label
end

-- Baut das Schild "Info" (BillboardGui > Frame > NameLabel/RarityLabel/ValueLabel), noch ohne Parent.
-- Der Aufrufer setzt StudsOffset + Parent.
function MeteorFactory.BuildInfo(maxDistance: number): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.Size = INFO_SIZE
	gui.MaxDistance = maxDistance
	gui.LightInfluence = 0
	-- unsichtbares Frame (kein Kasten, keine Kontur) – wird gesucht, deshalb bleibt es
	local frame = Instance.new("Frame")
	frame.Name = "Frame"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Parent = frame
	makeLabel(frame, "NameLabel", 1, NAME_TEXT, STROKE_NAME)
	makeLabel(frame, "RarityLabel", 2, RARITY_TEXT, STROKE_TEXT)
	makeLabel(frame, "ValueLabel", 3, VALUE_TEXT, STROKE_TEXT)
	return gui
end

MeteorFactory.MoneyColor = GREEN

-- mode: "Ground"/"Nest" (zeigt Preis), "Base" (Schlüpf-Countdown bzw. Einkommen + Level),
--       "Carry" (getragen: Schlüpfen pausiert)
function MeteorFactory.UpdateLabel(part: BasePart, entry, mode: string, price: number?)
	local gui = part:FindFirstChild("Info")
	if not gui then
		return
	end
	local frame = gui:FindFirstChild("Frame")
	local def = Config.MeteorsById[entry.Id]
	if not frame or not def then
		return
	end
	local nameLabel = frame:FindFirstChild("NameLabel") :: TextLabel?
	local rarityLabel = frame:FindFirstChild("RarityLabel") :: TextLabel?
	local valueLabel = frame:FindFirstChild("ValueLabel") :: TextLabel?
	if not nameLabel or not rarityLabel or not valueLabel then
		return
	end
	local mut = Config.MutationsByName[entry.Mut] or Config.Mutations[1]

	-- Name weiß; eine Mutation steht farbig davor (gleiche Symbole wie an den Aliens und auf der
	-- Schlüpf-Karte: Config.Mutations -> Icon)
	local prefix = nil
	if mut.Name ~= "Normal" then
		local icon = if type(mut.Icon) == "string" then mut.Icon else nil
		prefix = MeteorFactory.MutationPrefix(icon, mut.Name, mut.Color, mut.Rainbow == true)
	end
	MeteorFactory.SetNameText(nameLabel, def.Name, prefix)
	MeteorFactory.SetRarityText(rarityLabel, def.Rarity, if def.Rarity == "Admin" then "👑 ADMIN" else def.Rarity)
	if mode == "Ground" or mode == "Nest" then
		if price and price <= 0 then
			valueLabel.Text = "🎁 GRATIS!"
			valueLabel.TextColor3 = GREEN
		else
			valueLabel.Text = Util.FormatCash(price or Config.MeteorValue(entry))
			valueLabel.TextColor3 = YELLOW
		end
	elseif entry.Alien == nil then
		-- Noch nicht geschlüpft: der Client zählt über das Attribut "HatchAt" live herunter
		local hatch = math.max(0, tonumber(entry.Hatch) or 0)
		if mode == "Carry" and entry.Hatch == nil then
			-- frisch aus dem Nest/vom Boden geschnappt: Countdown startet erst in der Base
			valueLabel.Text = "🏠 Heimbringen! 🐣 " .. Util.FormatTime(Config.HatchTime(entry.Id))
		elseif mode == "Carry" then
			valueLabel.Text = "🐣 ⏸ " .. Util.FormatTime(hatch)
		elseif hatch <= 0 then
			valueLabel.Text = "🐣 Schlüpft..."
		else
			valueLabel.Text = "🐣 Schlüpft in " .. Util.FormatTime(hatch)
		end
		valueLabel.TextColor3 = HATCH_COLOR
	else
		local lv = entry.Lv or 1
		local lvText = lv >= Config.MaxLevel and "MAX" or tostring(lv)
		valueLabel.Text = Util.FormatCash(Config.MeteorIncome(entry)) .. "/s  ⚡Lv " .. lvText
		valueLabel.TextColor3 = GREEN
	end
end

-- Spezial-Effekte (Admin-Meteore): Regenbogen, Umriss, Aura, starkes Licht
local function addSpecialEffects(part: BasePart, def, color: Color3, size: number, mode: string)
	local fx = def.Effects
	if type(fx) ~= "table" then
		return
	end
	if fx.Rainbow then
		part:SetAttribute("Rainbow", true) -- Client färbt lokal durch alle Farben
	end
	if fx.Highlight and mode ~= "Carry" then
		-- startet AUS: der Client schaltet nur die nächsten paar Highlights ein (Roblox-Limit 31)
		local highlight = Instance.new("Highlight")
		highlight.Name = "AdminHighlight"
		highlight.Enabled = false
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.FillColor = color
		highlight.FillTransparency = 0.75
		highlight.OutlineColor = color:Lerp(Color3.new(1, 1, 1), 0.4)
		highlight.OutlineTransparency = 0
		if fx.Rainbow then
			highlight:SetAttribute("Rainbow", true)
		end
		highlight.Adornee = part
		highlight.Parent = part
	end
	if fx.Aura then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Aura"
		emitter.Color = ColorSequence.new(color, color:Lerp(Color3.new(1, 1, 1), 0.6))
		emitter.LightEmission = 1
		emitter.LightInfluence = 0
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, size * 0.12),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Lifetime = NumberRange.new(0.8, 1.6)
		emitter.Speed = NumberRange.new(size * 0.4, size * 0.9)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Rate = mode == "Nest" and 12 or 25
		emitter.Parent = part
		if fx.Rainbow then
			emitter:SetAttribute("Rainbow", true)
		end
	end
	if fx.BigLight then
		local light = part:FindFirstChildOfClass("PointLight") or Instance.new("PointLight")
		light.Color = color
		light.Range = 30
		light.Brightness = 3
		light.Shadows = false
		light.Parent = part
		if fx.Rainbow then
			light:SetAttribute("Rainbow", true)
		end
	end
end

local function rareEmitter(name: string, part: BasePart, props: { [string]: any }): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Enabled = false -- der Client schaltet nur Emitter in Kameranähe ein (WorldFX)
	for key, value in pairs(props) do
		(emitter :: any)[key] = value
	end
	emitter.Parent = part
	return emitter
end

-- Lichtsäule, Glitzern, Funkenregen, Regenbogen-Aura (siehe Kopf der Datei)
local function addRareEffects(part: BasePart, rarityIndex: number, color: Color3, size: number)
	local tier = if rarityIndex == RARE_INFINITY
		then 4
		elseif rarityIndex >= RARE_SECRET then 3
		elseif rarityIndex >= RARE_MYTHIC then 2
		else 1
	local rainbow = tier >= 3
	part:SetAttribute("RareFX", tier)

	-- Lichtsäule: Beam von der Ei-Mitte senkrecht nach oben, unten kräftig, oben unsichtbar.
	local bottom = Instance.new("Attachment")
	bottom.Name = "PillarBottom"
	bottom.Parent = part
	local top = Instance.new("Attachment")
	top.Name = "PillarTop"
	top.Position = Vector3.new(0, PILLAR_HEIGHT + tier * 6, 0)
	top.Parent = part
	local beam = Instance.new("Beam")
	beam.Name = "RarePillar"
	beam.Attachment0 = bottom
	beam.Attachment1 = top
	beam.Color = if rainbow then rainbowSequence() else ColorSequence.new(color, color:Lerp(Color3.new(1, 1, 1), 0.5))
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.55, 0.75),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Width0 = size * (if tier >= 4 then 1.2 else 0.85)
	beam.Width1 = size * (if tier >= 4 then 0.7 else 0.45)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Parent = part

	-- Glitzern in Seltenheitsfarbe
	rareEmitter("RareSparkle", part, {
		Color = if rainbow then rainbowSequence() else ColorSequence.new(color, Color3.new(1, 1, 1)),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, math.clamp(size * 0.09, 0.3, 0.7)),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new(0.1, 1),
		Lifetime = NumberRange.new(0.9, 1.6),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 2, 0),
		RotSpeed = NumberRange.new(-180, 180),
		Rate = 6 + tier * 5,
	})
	if tier >= 2 then
		-- Funkenregen: Funken spritzen hoch und regnen herunter
		rareEmitter("RareSparks", part, {
			Color = ColorSequence.new(Color3.new(1, 1, 1), color),
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.25),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Transparency = NumberSequence.new(0, 0.6),
			Lifetime = NumberRange.new(0.8, 1.3),
			Speed = NumberRange.new(8, 13),
			SpreadAngle = Vector2.new(28, 28),
			EmissionDirection = Enum.NormalId.Top,
			Acceleration = Vector3.new(0, -24, 0),
			Drag = 0.5,
			Rate = 8 + tier * 3,
		})
	end
	if rainbow then
		-- Regenbogen-Aura: große weiche Kugeln in allen Farben um das Ei
		rareEmitter("RareAura", part, {
			Color = rainbowSequence(),
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, size * 0.25),
				NumberSequenceKeypoint.new(1, size * 0.5),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.3, 0.6),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Lifetime = NumberRange.new(1.2, 1.8),
			Speed = NumberRange.new(size * 0.3, size * 0.6),
			SpreadAngle = Vector2.new(180, 180),
			Rate = 10,
		})
	end
	if tier >= 4 then
		-- Infinity: helle Sterne kreisen um das Ei und steigen langsam auf
		rareEmitter("RareInfinity", part, {
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Color = ColorSequence.new(Color3.new(1, 1, 1), color),
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, size * 0.18),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Transparency = NumberSequence.new(0, 0.8),
			Lifetime = NumberRange.new(1.5, 2.5),
			Speed = NumberRange.new(1, 2),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, 3, 0),
			RotSpeed = NumberRange.new(90, 270),
			Rate = 14,
		})
	end
end

-- mode: "Nest" (in einem Nest im Ei-Rennen), "Ground" (Gratis-Zone/Showcase), "Base" (in der Base), "Carry" (getragen)
function MeteorFactory.Create(entry, mode: string, price: number?): BasePart
	local def = Config.MeteorsById[entry.Id]
	assert(def, "Unbekannter Meteor: " .. tostring(entry.Id))
	local rarity = Config.RaritiesByName[def.Rarity]
	local rarityIndex = Config.RarityIndex[def.Rarity]
	local mut = Config.MutationsByName[entry.Mut] or Config.Mutations[1]
	local size = MeteorFactory.GetSize(entry)
	local isAdmin = rarity.AdminOnly == true

	local part = Instance.new("Part")
	part.Name = "Meteor"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(size, size, size)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CastShadow = size >= SHADOW_MIN_SIZE and mode ~= "Nest"
	-- kräftiges, glattes Plastik in der (satteren) Ei-Farbe; ab Legendary glänzt das Ei
	part.Material = Enum.Material.SmoothPlastic
	part.Color = MeteorFactory.Vivid(def.Color)
	part.Reflectance = if rarityIndex >= RARE_FROM then RARE_SHINE else 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	-- Ei-Form: die Kugel wird optisch etwas schmaler (Size, Hitbox und Prompts bleiben wie bisher)
	local eggShape = Instance.new("SpecialMesh")
	eggShape.Name = "EggShape"
	eggShape.MeshType = Enum.MeshType.Sphere
	eggShape.Scale = Vector3.new(EGG_WIDTH, 1, EGG_WIDTH)
	eggShape.Parent = part

	if mut.Name == "Gold" then
		-- glänzendes Gold (statt Folie)
		part.Color = mut.Color
		part.Reflectance = GOLD_SHINE
	elseif mut.Name == "Diamond" then
		-- seltener Effekt: türkises Glas + Glitzern (unten) – so sieht man den Unterschied zu Frost
		part.Material = Enum.Material.Glass
		part.Transparency = 0.1
		part.Reflectance = 0.2
		part.Color = mut.Color
	elseif mut.Name == "Galaxy" then
		-- sehr selten: leuchtet lila (+ Glitzern, unten)
		part.Material = Enum.Material.Neon
		part.Color = mut.Color
	elseif mut.Name == "Lava" then
		-- knallig orange (+ kleines Feuer, unten bei den Effekten)
		part.Color = mut.Color
	elseif mut.Name == "Frost" then
		-- hellblaues Eis: heller und weißlicher als Diamond, dazu fallen Schneeflocken (unten)
		part.Reflectance = 0.15
		part.Color = mut.Color:Lerp(WHITE, FROST_WHITEN)
	elseif mut.Rainbow == true then
		-- Regenbogen (sehr selten): der Client färbt alle Teile mit dem Attribut "Rainbow" lokal durch
		part.Material = Enum.Material.Neon
		part.Color = mut.Color or WHITE
		part:SetAttribute("Rainbow", true)
	end

	part:SetAttribute("MeteorId", entry.Id)
	part:SetAttribute("Mutation", mut.Name)
	part:SetAttribute("Rarity", def.Rarity)

	-- Leuchten nur für seltene Meteore (siehe Tabelle oben)
	local lightFrom = LIGHT_FROM[mode] or 5
	if rarityIndex >= lightFrom and not isAdmin then
		local light = Instance.new("PointLight")
		light.Color = rarity.Color
		light.Range = 6 + rarityIndex * 1.5
		light.Brightness = 1 + rarityIndex * 0.2
		light.Shadows = false
		light.Parent = part
	end
	if mut.Name == "Lava" then
		-- Lava-Mutation: kleines Feuer. Im Nest startet es AUS (mit Glück-Events sind dort
		-- viele Lava-Meteore): der Client schaltet nur die nächsten paar ein (Attribut "LavaFire", WorldFX).
		local fire = Instance.new("Fire")
		fire.Color = mut.Color
		fire.SecondaryColor = Color3.fromRGB(120, 20, 0)
		fire.Size = math.max(1.5, size * 0.45)
		fire.Heat = 3
		if mode == "Nest" then
			fire.Enabled = false
			fire:SetAttribute("LavaFire", true)
		end
		fire.Parent = part
	end
	if mut.Name == "Frost" then
		-- Frost-Mutation: ein paar Schneeflocken rieseln herunter
		local snow = Instance.new("ParticleEmitter")
		snow.Name = "FrostSnow"
		snow.Color = ColorSequence.new(WHITE)
		snow.LightEmission = 0.5
		snow.LightInfluence = 0
		snow.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, math.clamp(size * 0.07, 0.15, 0.45)),
			NumberSequenceKeypoint.new(1, 0),
		})
		snow.Lifetime = NumberRange.new(1, 1.6)
		snow.Speed = NumberRange.new(0.5, 1.5)
		snow.SpreadAngle = Vector2.new(180, 180)
		snow.Acceleration = Vector3.new(0, -4, 0)
		snow.Rate = if mode == "Nest" then 3 else 6
		snow.Parent = part
	end
	-- Glitzern nur noch für die besonderen Mutationen (seltene Eier glitzern über "RareSparkle",
	-- das der Client nur in Kameranähe einschaltet -> weniger Partikel)
	local specialMut = mut.Name == "Galaxy" or mut.Name == "Diamond" or mut.Rainbow == true
	if specialMut and mode ~= "Carry" and not isAdmin then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = mut.Color or rarity.Color
		sparkles.Parent = part
	end
	addSpecialEffects(part, def, part.Color, size, mode)
	if rarityIndex >= RARE_FROM and RARE_MODES[mode] then
		addRareEffects(part, rarityIndex, rarity.Color, size)
	end

	local maxDistance
	if mode == "Nest" then
		maxDistance = 45 + rarityIndex * 8 -- viele Schilder im Nester-Feld: nur in der Nähe zeigen
	elseif mode == "Carry" then
		maxDistance = 60
	else
		maxDistance = 70 + rarityIndex * 15
	end
	local gui = MeteorFactory.BuildInfo(maxDistance)
	gui.StudsOffset = Vector3.new(0, size / 2 + 1.8, 0)
	gui.Parent = part

	MeteorFactory.UpdateLabel(part, entry, mode, price)
	return part
end

-- Passt Größe + Schild an (z.B. nach Level-Änderung durch den Admin)
function MeteorFactory.Refresh(part: BasePart, entry, mode: string)
	local size = MeteorFactory.GetSize(entry)
	local bottom = part.Position.Y - part.Size.Y / 2
	part.Size = Vector3.new(size, size, size)
	part.Position = Vector3.new(part.Position.X, bottom + size / 2, part.Position.Z)
	local gui = part:FindFirstChild("Info")
	if gui and gui:IsA("BillboardGui") then
		gui.StudsOffset = Vector3.new(0, size / 2 + 1.8, 0)
	end
	local beam = part:FindFirstChild("RarePillar")
	if beam and beam:IsA("Beam") then
		local wide = part:GetAttribute("RareFX") == 4 -- Infinity: breitere Säule
		beam.Width0 = size * (if wide then 1.2 else 0.85)
		beam.Width1 = size * (if wide then 0.7 else 0.45)
	end
	local fire = part:FindFirstChildOfClass("Fire")
	if fire then
		fire.Size = math.max(1.5, size * 0.45) -- (nur noch das kleine Lava-Feuer)
	end
	MeteorFactory.UpdateLabel(part, entry, mode)
end

-- distance = optionale Aktivierungs-Reichweite (sonst aus der Größe des Teils)
-- Hinweis: Zwei Prompts am selben Teil (z.B. Schnappen + Kaufen am Nest) bekommen über
-- prompt.UIOffset (Pixel) verschiedene Plätze, sonst liegen sie übereinander.
function MeteorFactory.AddPrompt(
	part: BasePart,
	name: string,
	action: string,
	objectText: string,
	hold: number,
	key: Enum.KeyCode?,
	distance: number?
): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = action
	prompt.ObjectText = objectText
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = distance or math.max(10, part.Size.X / 2 + 7)
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = key or Enum.KeyCode.E
	prompt.Parent = part
	return prompt
end

-- -------------------------------------------------------------------
-- HALTEN PRÜFEN (gegen "sofort auslösen"-Cheats)
-- "Triggered" schickt der Client. Ein Cheater kann einen Prompt auch ohne Halten auslösen
-- (z.B. HoldDuration lokal auf 0). Deshalb merkt sich der Server, wann der Spieler angefangen
-- hat zu halten (PromptButtonHoldBegan kommt auch auf dem Server an), und ruft callback nur auf,
-- wenn wirklich so lange gehalten wurde, wie die HoldDuration HIER auf dem Server sagt.
-- -------------------------------------------------------------------
local HOLD_TOLERANCE = 0.15 -- Sekunden Spielraum für Netzwerk-Schwankungen
local HOLD_MAX_EXTRA = 3 -- ein Halten zählt höchstens so lange über die HoldDuration hinaus

function MeteorFactory.OnHeldTrigger(prompt: ProximityPrompt, callback: (player: Player) -> ())
	local started: { [Player]: number } = {}
	local ended: { [Player]: number } = {}
	prompt.PromptButtonHoldBegan:Connect(function(player: Player)
		started[player] = os.clock()
		ended[player] = nil
	end)
	prompt.PromptButtonHoldEnded:Connect(function(player: Player)
		-- (kommt evtl. kurz VOR Triggered an -> Zeitpunkt merken statt löschen)
		if started[player] then
			ended[player] = os.clock()
		end
	end)
	prompt.Triggered:Connect(function(player: Player)
		local hold = prompt.HoldDuration
		if hold > 0 then
			local t = os.clock()
			local begin = started[player]
			local release = ended[player]
			started[player] = nil
			ended[player] = nil
			if not begin then
				return -- nie angefangen zu halten
			end
			local heldUntil = if release then math.min(release, t) else t
			if heldUntil - begin < hold - HOLD_TOLERANCE or t - begin > hold + HOLD_MAX_EXTRA then
				return -- zu kurz gehalten (oder ein uraltes Halten)
			end
		end
		callback(player)
	end)
end

return MeteorFactory
