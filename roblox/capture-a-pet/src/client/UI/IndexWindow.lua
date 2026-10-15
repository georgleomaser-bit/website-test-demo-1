-- Pet Index, laid out like the reference: zone tabs on the left, rarity-colored tiles in
-- the middle, the selected animal with its rewards on the right and an unlock bar below.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Format = require(Shared.Format)
local Animals = require(Shared.Config.Animals)
local Zones = require(Shared.Config.Zones)
local Game = require(Shared.Config.Game)
local Rewards = require(Shared.Config.Rewards)

local Kit = require(script.Parent.Kit)
local Windows = require(script.Parent.Windows)
local Feed = require(script.Parent.Feed)
local Preview = require(script.Parent.Preview)
local State = require(script.Parent.Parent.State)

local IndexWindow = {}

local window
local selectedZone = 1
local zoneButtons = {}
local grid
local tiles = {}
local detail = {}
local progress = {}
local milestoneButtons = {}

local function discovered(id: string): boolean
	return State.ready() and State.Data.Index[id] == true
end

local function countDiscovered(): number
	local n = 0
	if State.ready() then
		for _ in pairs(State.Data.Index) do
			n += 1
		end
	end
	return n
end

local function rarityColor(r: number): Color3
	return Game.Rarities[r].Color
end

local function selectAnimal(id: string)
	local def = Animals.ById[id]
	local known = discovered(id)
	Preview.showAnimal(detail.Viewport, id, {}, not known)
	detail.Name.Text = known and def.Id or "???"
	detail.Rarity.Text = Game.Rarities[def.Rarity].Name
	detail.Rarity.TextColor3 = def.Rarity == 7 and Color3.new(1, 1, 1) or rarityColor(def.Rarity)
	detail.Income.Text = "$" .. Format.number(def.Income) .. "/s"
	detail.Card:FindFirstChildOfClass("UIStroke").Color = rarityColor(def.Rarity)
end

local function buildTiles()
	for _, t in pairs(tiles) do
		t:Destroy()
	end
	tiles = {}
	for order, def in ipairs(Animals.ByZone[selectedZone]) do
		local known = discovered(def.Id)
		local tile = Kit.new("TextButton", {
			Name = def.Id,
			AutoButtonColor = true,
			BackgroundColor3 = known and rarityColor(def.Rarity) or Color3.fromRGB(70, 72, 90),
			LayoutOrder = order,
			Text = "",
			Parent = grid,
		})
		Kit.corner(tile, 10)
		Kit.stroke(tile, 2.5, nil, Enum.ApplyStrokeMode.Border)
		Kit.gradient(tile, Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170))
		Kit.label({ Text = known and def.Id or "???", Size = UDim2.new(1, -6, 0, 18), Position = UDim2.fromOffset(3, 2), Z = 24, Parent = tile })
		local vp = Preview.new(tile, UDim2.new(1, -8, 1, -24), UDim2.fromOffset(4, 20), 23)
		Preview.showAnimal(vp, def.Id, {}, not known, true)
		if State.ready() and State.Data.Mount ~= "" then
			for _, a in ipairs(State.Data.Animals) do
				if a.Uid == State.Data.Mount and a.Species == def.Id then
					local tag = Kit.panel({ Size = UDim2.new(1, -8, 0, 18), Position = UDim2.new(0, 4, 1, -22), Color = Kit.Colors.Green, Radius = 6, StrokeThickness = 2, Z = 25, Parent = tile })
					Kit.label({ Text = "Riding", Z = 26, Parent = tag })
				end
			end
		end
		tile.Activated:Connect(function()
			Kit.playClick()
			selectAnimal(def.Id)
		end)
		tiles[def.Id] = tile
	end
	local first = Animals.ByZone[selectedZone][1]
	selectAnimal(first.Id)
end

function IndexWindow.refresh()
	if not State.ready() or not window then
		return
	end
	local total = #Animals.List
	local n = countDiscovered()
	progress.Text.Text = string.format("Unlocked: %d/%d", n, total)
	Kit.tween(progress.Fill, 0.3, { Size = UDim2.new(n / total, 0, 1, 0) })
	-- zone reward
	local claimed = State.Data.IndexClaimed.Zones[tostring(selectedZone)] == true
	local complete = true
	local zoneKnown = 0
	for _, def in ipairs(Animals.ByZone[selectedZone]) do
		if discovered(def.Id) then
			zoneKnown += 1
		else
			complete = false
		end
	end
	detail.ZoneInfo.Text = string.format("%s: %d/%d", Zones[selectedZone].Name, zoneKnown, #Animals.ByZone[selectedZone])
	if claimed then
		detail.Claim.setText("CLAIMED!")
		detail.Claim.setColor(Kit.Colors.Gray)
	elseif complete then
		detail.Claim.setText("CLAIM!")
		detail.Claim.setColor(Kit.Colors.Green)
	else
		detail.Claim.setText("Find all")
		detail.Claim.setColor(Kit.Colors.Gray)
	end
	for i, m in ipairs(Rewards.IndexMilestones) do
		local b = milestoneButtons[i]
		local done = State.Data.IndexClaimed.Milestones[tostring(i)] == true
		if done then
			b.setText("✔")
			b.setColor(Kit.Colors.Green)
		elseif n >= m.Count then
			b.setText("🎁")
			b.setColor(Kit.Colors.Yellow)
		else
			b.setText(tostring(m.Count))
			b.setColor(Kit.Colors.Gray)
		end
	end
	for i, b in ipairs(zoneButtons) do
		b.setColor(i == selectedZone and Zones[i].Accent or Zones[i].Floor:Lerp(Color3.new(0, 0, 0), 0.3))
	end
end

function IndexWindow.init()
	window = Windows.create("Index", "Pet Index", Vector2.new(820, 500))
	local content = window.Content

	-- zone tabs
	local zonesFrame = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0, 150, 1, -56), Parent = content })
	Kit.list(zonesFrame, 8)
	for i, zone in ipairs(Zones) do
		zoneButtons[i] = Kit.button({ Text = zone.Name, Size = UDim2.new(1, 0, 0, 74), Order = i, Color = zone.Floor, Parent = zonesFrame, MaxTextSize = 24 }, function()
			selectedZone = i
			buildTiles()
			IndexWindow.refresh()
		end)
	end

	-- grid
	local gridPanel = Kit.panel({ Size = UDim2.new(1, -420, 1, -56), Position = UDim2.fromOffset(160, 0), Color = Kit.Colors.PanelDark, Parent = content })
	grid = Windows.scroll(gridPanel, UDim2.new(1, -8, 1, -8), UDim2.fromOffset(4, 4))
	Kit.new("UIGridLayout", { CellSize = UDim2.fromOffset(84, 92), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })

	-- detail card
	local card = Kit.panel({ Size = UDim2.fromOffset(250, 250), Position = UDim2.new(1, 0, 0, 0), Anchor = Vector2.new(1, 0), Color = Kit.Colors.PanelDark, StrokeThickness = 4, Parent = content })
	detail.Card = card
	detail.Viewport = Preview.new(card, UDim2.new(1, -16, 0, 150), UDim2.fromOffset(8, 6))
	detail.Name = Kit.label({ Text = "", Size = UDim2.new(1, -16, 0, 30), Position = UDim2.fromOffset(8, 156), Parent = card })
	detail.Rarity = Kit.label({ Text = "", Size = UDim2.new(1, -16, 0, 24), Position = UDim2.fromOffset(8, 186), Parent = card })
	detail.Income = Kit.label({ Text = "", Size = UDim2.new(1, -16, 0, 26), Position = UDim2.fromOffset(8, 212), Color = Kit.Colors.Money, Parent = card })

	local rewards = Kit.panel({ Size = UDim2.fromOffset(250, 170), Position = UDim2.new(1, 0, 0, 262), Anchor = Vector2.new(1, 0), Color = Color3.fromRGB(30, 60, 40), StrokeColor = Kit.Colors.GreenDark, Parent = content })
	Kit.label({ Text = "Rewards:", Size = UDim2.new(1, -16, 0, 24), Position = UDim2.fromOffset(8, 4), XAlign = Enum.TextXAlignment.Left, Parent = rewards })
	local milestones = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -16, 0, 44), Position = UDim2.fromOffset(8, 30), Parent = rewards })
	Kit.list(milestones, 4, true, Enum.HorizontalAlignment.Center)
	for i, m in ipairs(Rewards.IndexMilestones) do
		milestoneButtons[i] = Kit.button({ Text = tostring(m.Count), Size = UDim2.fromOffset(42, 40), Order = i, Color = Kit.Colors.Gray, Parent = milestones }, function()
			local ok, msg = State.action("ClaimIndexMilestone", i)
			if msg then
				Feed.notify(msg, ok and "success" or "error")
			end
		end)
	end
	detail.ZoneInfo = Kit.label({ Text = "", Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(8, 82), Parent = rewards })
	detail.Claim = Kit.button({ Text = "CLAIM!", Size = UDim2.new(1, -30, 0, 44), Position = UDim2.new(0.5, 0, 1, -12), Anchor = Vector2.new(0.5, 1), Color = Kit.Colors.Green, Parent = rewards }, function()
		local ok, msg = State.action("ClaimIndexZone", selectedZone)
		if msg then
			Feed.notify(msg, ok and "success" or "error")
		end
	end)

	-- unlock bar
	local bar = Kit.panel({ Size = UDim2.new(1, -270, 0, 40), Position = UDim2.new(0, 0, 1, -6), Anchor = Vector2.new(0, 1), Color = Kit.Colors.PanelDark, Radius = 20, Parent = content })
	progress.Fill = Kit.new("Frame", { BackgroundColor3 = Kit.Colors.Blue, Size = UDim2.new(0, 0, 1, 0), Parent = bar })
	Kit.corner(progress.Fill, 20)
	Kit.gradient(progress.Fill, Color3.fromRGB(140, 210, 255), Color3.fromRGB(40, 120, 230))
	progress.Text = Kit.label({ Text = "", Size = UDim2.new(1, -60, 1, -6), Position = UDim2.fromOffset(50, 3), Z = 3, Parent = bar })
	Kit.label({ Text = "📘", Size = UDim2.fromOffset(52, 52), Position = UDim2.new(0, -14, 0.5, 0), Anchor = Vector2.new(0, 0.5), Stroke = false, Z = 4, Parent = bar })

	window.OnOpen = function()
		buildTiles()
		IndexWindow.refresh()
	end
	State.Changed:Connect(function()
		if Windows.isOpen("Index") then
			IndexWindow.refresh()
		end
	end)
end

return IndexWindow
