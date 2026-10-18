--[[
	ItemCard (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/ItemCard
	Depends on: ReplicatedStorage/UI/{UIKit,Theme}, ReplicatedStorage/Shared/Config/{Items,Rarities}

	Reusable item tile with rarity border, glow, icon, name and badges
	(count, equipped, favourite, new). Secret items get an animated rainbow
	border. Golden variants get a gold tint and border, Rainbow variants the
	animated rainbow border (static with Reduced Motion), both with a ✦ mark.
	Undiscovered items render as a dark silhouette.
	Cards are updated in place (Set) so large grids never get rebuilt.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UIFolder = ReplicatedStorage:WaitForChild("UI")
local UI = require(UIFolder.UIKit)
local Theme = require(UIFolder.Theme)
local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Items = require(Config.Items)
local Rarities = require(Config.Rarities)

local C = Theme.Colors
local F = Theme.Fonts

local ItemCard = {}
ItemCard.__index = ItemCard

local secretGradients: { UIGradient } = {}
local spinning = false

local function ensureSpin()
	if spinning then
		return
	end
	spinning = true
	RunService.RenderStepped:Connect(function(dt)
		if Theme.ReducedMotion then
			return
		end
		for i = #secretGradients, 1, -1 do
			local g = secretGradients[i]
			if g.Parent == nil then
				table.remove(secretGradients, i)
			else
				g.Rotation = (g.Rotation + dt * 90) % 360
			end
		end
	end)
end

--[[ props: Parent, Size, LayoutOrder, OnClick(card), ShowName (default true) ]]
function ItemCard.new(props)
	local self = setmetatable({}, ItemCard)
	local button = UI.new("TextButton", {
		Name = "ItemCard",
		Size = props.Size or UDim2.fromOffset(96, 112),
		LayoutOrder = props.LayoutOrder or 0,
		BackgroundColor3 = C.PanelLight,
		AutoButtonColor = false,
		Text = "",
		Selectable = true,
		Corner = Theme.Radius.Medium,
		Parent = props.Parent,
	})
	self.Instance = button
	self.Stroke = UI.stroke(button, { Color = C.StrokeSoft, Thickness = 2 })
	self.Gradient = UI.gradient(button, { Color = ColorSequence.new(C.PanelLight, C.Panel), Rotation = 90 })
	self.Scale = Instance.new("UIScale")
	self.Scale.Parent = button

	self.Icon = UI.label({
		Name = "Icon",
		Text = "",
		TextSize = 40,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0.62, 0),
		Position = UDim2.fromScale(0, 0.06),
		ZIndex = 2,
		Parent = button,
	})
	self.Name = UI.label({
		Name = "ItemName",
		Text = "",
		Font = F.Bold,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -8, 0.3, 0),
		Position = UDim2.new(0, 4, 0.68, 0),
		ZIndex = 2,
		Visible = props.ShowName ~= false,
		Parent = button,
	})
	self.Count = UI.label({
		Name = "Count",
		Text = "",
		Font = F.Heading,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, -8, 0, 16),
		Position = UDim2.fromOffset(0, 4),
		ZIndex = 3,
		Parent = button,
	})
	self.Equipped = UI.label({
		Name = "Equipped",
		Text = "E",
		Font = F.Heading,
		TextSize = 11,
		TextColor3 = C.Background,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundColor3 = C.Success,
		BackgroundTransparency = 0,
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.fromOffset(4, 4),
		ZIndex = 3,
		Visible = false,
		Corner = Theme.Radius.Pill,
		Parent = button,
	})
	self.Favorite = UI.label({
		Name = "Favorite",
		Text = "★",
		TextSize = 14,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.fromOffset(4, 24),
		ZIndex = 3,
		Visible = false,
		Parent = button,
	})
	self.VariantMark = UI.label({
		Name = "VariantMark",
		Text = "✦",
		Font = F.Heading,
		TextSize = 15,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, -8, 0, 16),
		Position = UDim2.fromOffset(0, 20),
		ZIndex = 3,
		Visible = false,
		Parent = button,
	})
	self.NewBadge = UI.label({
		Name = "New",
		Text = "NEW",
		Font = F.Heading,
		TextSize = 11,
		TextColor3 = C.White,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundColor3 = C.Accent,
		BackgroundTransparency = 0,
		Size = UDim2.fromOffset(38, 16),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 0),
		ZIndex = 4,
		Visible = false,
		Corner = Theme.Radius.Pill,
		Parent = button,
	})

	button.MouseEnter:Connect(function()
		UI.tween(self.Scale, { Scale = 1.05 }, Theme.Motion.Fast)
	end)
	button.MouseLeave:Connect(function()
		UI.tween(self.Scale, { Scale = 1 }, Theme.Motion.Fast)
	end)
	button.SelectionGained:Connect(function()
		UI.tween(self.Scale, { Scale = 1.05 }, Theme.Motion.Fast)
	end)
	button.SelectionLost:Connect(function()
		UI.tween(self.Scale, { Scale = 1 }, Theme.Motion.Fast)
	end)
	if props.OnClick then
		button.Activated:Connect(function()
			props.OnClick(self)
		end)
	end
	return self
end

--[[
	state: { Id, Count?, Equipped?, Favorite?, New?, Undiscovered?, Selected? }
]]
function ItemCard:Set(state)
	self.State = state
	local item = Items.ById[state.Id]
	if not item then
		return
	end
	local rarity = Rarities.ById[item.Rarity]
	local undiscovered = state.Undiscovered == true
	local color = if undiscovered then C.StrokeSoft else rarity.Color

	self.Icon.Text = if undiscovered then "?" else item.Icon
	self.Icon.TextColor3 = if undiscovered then C.TextMuted else C.White
	self.Icon.Font = if undiscovered then F.Heading else F.Medium
	if undiscovered then
		self.Name.Text = if item.Rarity == "Secret" then "Secret" else "???"
		self.Name.TextColor3 = C.TextMuted
	else
		self.Name.Text = item.Name
		self.Name.TextColor3 = rarity.Color
	end
	self.Count.Text = if state.Count and state.Count > 1 then "×" .. tostring(state.Count) else ""
	self.Equipped.Visible = state.Equipped == true
	self.Favorite.Visible = state.Favorite == true
	self.NewBadge.Visible = state.New == true

	local variant = if undiscovered then nil else Items.VariantById[item.Variant or ""]
	self.VariantMark.Visible = variant ~= nil
	if variant then
		self.VariantMark.TextColor3 = variant.Color
	end
	self.Stroke.Color = if state.Selected then C.White elseif variant and variant.Id == "golden" then C.Gold else color
	self.Stroke.Thickness = if state.Selected or variant then 3 else 2
	self.Gradient.Color = if undiscovered
		then ColorSequence.new(C.Panel, C.BackgroundAlt)
		elseif variant and variant.Id == "golden" then ColorSequence.new(Color3.fromRGB(130, 96, 18), C.Panel)
		elseif variant then ColorSequence.new(Color3.fromRGB(110, 40, 120), C.Panel)
		else ColorSequence.new(Theme.darken(rarity.Glow, 0.35), C.Panel)

	local secretGradient = self.Stroke:FindFirstChildOfClass("UIGradient")
	if (item.Rarity == "Secret" or item.Variant == "rainbow") and not undiscovered then
		if not secretGradient then
			secretGradient = Instance.new("UIGradient")
			secretGradient.Color = Rarities.SecretGradient
			secretGradient.Parent = self.Stroke
			table.insert(secretGradients, secretGradient)
			ensureSpin()
		end
		self.Stroke.Color = C.White
	elseif secretGradient then
		secretGradient:Destroy()
	end
end

return ItemCard
