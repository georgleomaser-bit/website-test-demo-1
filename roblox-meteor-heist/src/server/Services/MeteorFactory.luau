-- Baut das Aussehen eines Meteors: Größe nach Seltenheit, Licht/Feuer/Funken für seltene,
-- Material/Farbe nach Mutation, Spezial-Effekte der Admin-Meteore, Namensschild darüber.
-- Lichter und Feuer gibt es bewusst sparsam (viele Meteore gleichzeitig = sonst Lag).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))

local MeteorFactory = {}

-- Ab welcher Seltenheit (Index in Config.Rarities) gibt es welchen Effekt?
-- Laufband: es liegen sehr viele Meteore gleichzeitig darauf -> noch sparsamer.
local LIGHT_FROM = { Base = 5, Ground = 5, Belt = 6, Carry = 7 }
local FIRE_FROM = { Base = 7, Ground = 7, Belt = 99, Carry = 99 }
local SPARKLES_FROM = { Base = 6, Ground = 6, Belt = 7, Carry = 99 }
local SHADOW_MIN_SIZE = 3.5 -- nur große Meteore werfen Schatten

local GREEN = Color3.fromRGB(120, 255, 120)
local YELLOW = Color3.fromRGB(255, 230, 90)
local HATCH_COLOR = Color3.fromRGB(255, 220, 120)

function MeteorFactory.GetSize(entry): number
	local def = Config.MeteorsById[entry.Id]
	local rarity = def and Config.RaritiesByName[def.Rarity] or Config.Rarities[1]
	return rarity.Size * (1 + 0.025 * ((entry.Lv or 1) - 1))
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

-- mode: "Ground"/"Belt" (zeigt Preis), "Base" (Schlüpf-Countdown bzw. Einkommen + Level),
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
	local rarity = Config.RaritiesByName[def.Rarity]
	local mut = Config.MutationsByName[entry.Mut] or Config.Mutations[1]

	nameLabel.Text = def.Name
	nameLabel.TextColor3 = rarity.Color
	local tag = def.Rarity == "Admin" and "👑 ADMIN" or def.Rarity
	if mut.Name ~= "Normal" then
		-- gleiche Symbole wie an den Aliens und auf der Schlüpf-Karte (Config.Mutations -> Icon)
		tag = (if type(mut.Icon) == "string" then mut.Icon .. " " else "") .. mut.Name .. " • " .. tag
	end
	rarityLabel.Text = tag
	rarityLabel.TextColor3 = mut.Color or rarity.Color
	if mode == "Ground" or mode == "Belt" then
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
			-- frisch vom Förderband/Boden geklaut: Countdown startet erst in der Base
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
		emitter.Rate = mode == "Belt" and 12 or 25
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

-- mode: "Belt" (Laufband), "Ground" (Gratis-Zone/Showcase), "Base" (in der Base), "Carry" (getragen)
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
	part.CastShadow = size >= SHADOW_MIN_SIZE and mode ~= "Belt"
	part.Material = isAdmin and Enum.Material.Neon or Enum.Material.Slate
	part.Color = def.Color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	if mut.Name == "Gold" then
		part.Material = Enum.Material.Foil
		part.Color = mut.Color
	elseif mut.Name == "Diamond" then
		part.Material = Enum.Material.Glass
		part.Transparency = 0.15
		part.Color = mut.Color
	elseif mut.Name == "Cosmic" or mut.Name == "Lava" then
		-- Cosmic leuchtet lila, Lava glühend orange (+ kleines Feuer, unten bei den Effekten)
		part.Material = Enum.Material.Neon
		part.Color = mut.Color
	elseif mut.Name == "Frost" then
		-- hellblaues Eis
		part.Material = Enum.Material.Glass
		part.Transparency = 0.1
		part.Reflectance = 0.15
		part.Color = mut.Color
	elseif mut.Rainbow == true then
		-- Regenbogen: der Client färbt alle Teile mit dem Attribut "Rainbow" lokal durch
		part.Material = Enum.Material.Neon
		part.Color = mut.Color or Color3.new(1, 1, 1)
		part:SetAttribute("Rainbow", true)
	end

	part:SetAttribute("MeteorId", entry.Id)
	part:SetAttribute("Mutation", mut.Name)
	part:SetAttribute("Rarity", def.Rarity)

	-- Leuchten / Feuer / Funken nur für seltene Meteore (siehe Tabellen oben)
	local lightFrom = LIGHT_FROM[mode] or 5
	if rarityIndex >= lightFrom and not isAdmin then
		local light = Instance.new("PointLight")
		light.Color = rarity.Color
		light.Range = 6 + rarityIndex * 1.5
		light.Brightness = 1 + rarityIndex * 0.2
		light.Shadows = false
		light.Parent = part
	end
	if rarityIndex >= (FIRE_FROM[mode] or 99) and not isAdmin then
		local fire = Instance.new("Fire")
		fire.Color = rarity.Color
		fire.SecondaryColor = def.Color
		fire.Size = size * 0.9
		fire.Heat = 4
		fire.Parent = part
	end
	if mut.Name == "Lava" and not part:FindFirstChildOfClass("Fire") then
		-- Lava-Mutation: kleines Feuer (auch am Band – Lava ist selten genug)
		local fire = Instance.new("Fire")
		fire.Color = mut.Color
		fire.SecondaryColor = Color3.fromRGB(120, 20, 0)
		fire.Size = math.max(1.5, size * 0.45)
		fire.Heat = 3
		fire.Parent = part
	end
	local specialMut = mut.Name == "Cosmic" or mut.Rainbow == true
	if (rarityIndex >= (SPARKLES_FROM[mode] or 99) or (specialMut and mode ~= "Carry")) and not isAdmin then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = mut.Color or rarity.Color
		sparkles.Parent = part
	end
	addSpecialEffects(part, def, part.Color, size, mode)

	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.Size = UDim2.new(0, 220, 0, 70)
	gui.StudsOffset = Vector3.new(0, size / 2 + 1.8, 0)
	if mode == "Belt" then
		gui.MaxDistance = 45 + rarityIndex * 8 -- viele Schilder am Band: nur in der Nähe zeigen
	elseif mode == "Carry" then
		gui.MaxDistance = 60
	else
		gui.MaxDistance = 70 + rarityIndex * 15
	end
	gui.LightInfluence = 0
	gui.Parent = part

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
	local fire = part:FindFirstChildOfClass("Fire")
	if fire then
		local mut = Config.MutationsByName[entry.Mut]
		-- Lava-Feuer bleibt klein, Seltenheits-Feuer wächst mit
		local onlyLava = mut ~= nil and mut.Name == "Lava" and fire.Color == mut.Color
		fire.Size = onlyLava and math.max(1.5, size * 0.45) or size * 0.9
	end
	MeteorFactory.UpdateLabel(part, entry, mode)
end

-- distance = optionale Aktivierungs-Reichweite (sonst aus der Größe des Teils)
-- Hinweis: Zwei Prompts am selben Teil (z.B. Klauen + Kaufen am Förderband) bekommen über
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

return MeteorFactory
