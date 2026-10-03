-- Baut das Aussehen eines Meteors: Größe nach Seltenheit, Licht/Feuer/Funken für seltene,
-- Material/Farbe nach Mutation, Namensschild darüber.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))

local MeteorFactory = {}

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

-- mode: "Ground" (zeigt Preis) oder "Base" (zeigt Einkommen + Level)
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
	local rarity = Config.RaritiesByName[def.Rarity]
	local mut = Config.MutationsByName[entry.Mut] or Config.Mutations[1]

	frame.NameLabel.Text = def.Name
	frame.NameLabel.TextColor3 = rarity.Color
	local tag = def.Rarity
	if mut.Name ~= "Normal" then
		tag = mut.Name .. " • " .. tag
	end
	frame.RarityLabel.Text = tag
	frame.RarityLabel.TextColor3 = mut.Color or rarity.Color
	if mode == "Ground" then
		if price and price <= 0 then
			frame.ValueLabel.Text = "GRATIS!"
			frame.ValueLabel.TextColor3 = Color3.fromRGB(120, 255, 120)
		else
			frame.ValueLabel.Text = Util.FormatCash(price or Config.MeteorValue(entry))
			frame.ValueLabel.TextColor3 = Color3.fromRGB(255, 230, 90)
		end
	else
		local lv = entry.Lv or 1
		local lvText = lv >= Config.MaxLevel and "MAX" or tostring(lv)
		frame.ValueLabel.Text = Util.FormatCash(Config.MeteorIncome(entry)) .. "/s  ⚡Lv " .. lvText
		frame.ValueLabel.TextColor3 = Color3.fromRGB(120, 255, 120)
	end
end

function MeteorFactory.Create(entry, mode: string, price: number?): BasePart
	local def = Config.MeteorsById[entry.Id]
	assert(def, "Unbekannter Meteor: " .. tostring(entry.Id))
	local rarity = Config.RaritiesByName[def.Rarity]
	local rarityIndex = Config.RarityIndex[def.Rarity]
	local mut = Config.MutationsByName[entry.Mut] or Config.Mutations[1]
	local size = MeteorFactory.GetSize(entry)

	local part = Instance.new("Part")
	part.Name = "Meteor"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(size, size, size)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CastShadow = true
	part.Material = Enum.Material.Slate
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
	elseif mut.Name == "Cosmic" then
		part.Material = Enum.Material.Neon
		part.Color = mut.Color
	end

	part:SetAttribute("MeteorId", entry.Id)
	part:SetAttribute("Mutation", mut.Name)

	-- Leuchten ab Rare, Feuer ab Legendary, Funken ab Mythic
	if rarityIndex >= 3 then
		local light = Instance.new("PointLight")
		light.Color = rarity.Color
		light.Range = 6 + rarityIndex * 2
		light.Brightness = 1 + rarityIndex * 0.3
		light.Parent = part
	end
	if rarityIndex >= 5 then
		local fire = Instance.new("Fire")
		fire.Color = rarity.Color
		fire.SecondaryColor = def.Color
		fire.Size = size * 0.9
		fire.Heat = 4
		fire.Parent = part
	end
	if rarityIndex >= 6 or mut.Name == "Cosmic" then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = mut.Color or rarity.Color
		sparkles.Parent = part
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.Size = UDim2.new(0, 220, 0, 70)
	gui.StudsOffset = Vector3.new(0, size / 2 + 1.8, 0)
	gui.MaxDistance = 70 + rarityIndex * 15
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

-- Passt Größe + Schild nach einem Level-Up an
function MeteorFactory.Refresh(part: BasePart, entry, mode: string)
	local size = MeteorFactory.GetSize(entry)
	local bottom = part.Position.Y - part.Size.Y / 2
	part.Size = Vector3.new(size, size, size)
	part.Position = Vector3.new(part.Position.X, bottom + size / 2, part.Position.Z)
	local gui = part:FindFirstChild("Info")
	if gui then
		gui.StudsOffset = Vector3.new(0, size / 2 + 1.8, 0)
	end
	local fire = part:FindFirstChildOfClass("Fire")
	if fire then
		fire.Size = size * 0.9
	end
	MeteorFactory.UpdateLabel(part, entry, mode)
end

function MeteorFactory.AddPrompt(
	part: BasePart,
	name: string,
	action: string,
	objectText: string,
	hold: number,
	key: Enum.KeyCode?
)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = action
	prompt.ObjectText = objectText
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = math.max(10, part.Size.X / 2 + 7)
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = key or Enum.KeyCode.E
	prompt.Parent = part
	return prompt
end

return MeteorFactory
