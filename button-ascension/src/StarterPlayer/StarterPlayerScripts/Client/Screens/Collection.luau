--[[
	Collection (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Screens/Collection
	Depends on: ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format,Formulas,Config/*},
	            Client/{State,ClientNet,ItemCard}

	The collection book: every item in the game grouped by crate. Discovered
	items show their art and bonus; undiscovered ones are silhouettes (Secret
	items reveal nothing). Each discovery permanently adds +1% Sparks, and
	milestones grant rewards that are claimed here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIFolder = ReplicatedStorage:WaitForChild("UI")
local UI = require(UIFolder.UIKit)
local Theme = require(UIFolder.Theme)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Config = Shared.Config
local Items = require(Config.Items)
local Chests = require(Config.Chests)
local Rarities = require(Config.Rarities)
local Rewards = require(Config.Rewards)
local GameConfig = require(Config.GameConfig)

local Client = script.Parent.Parent
local State = require(Client.State)
local ClientNet = require(Client.ClientNet)
local ItemCard = require(Client.ItemCard)

local C = Theme.Colors
local F = Theme.Fonts

local Collection = {}

function Collection.new(ctx)
	local window = UI.window({
		Name = "Collection",
		Title = "Collection Book",
		Subtitle = "Every discovery permanently adds +1% Sparks.",
		Icon = "📖",
		Parent = ctx.Layers.Windows,
	})
	local screen: { [string]: any } = { Window = window }
	local body = window.Body

	local header = UI.frame({ Size = UDim2.new(1, 0, 0, 44), Parent = body })
	local headline = UI.label({ Text = "", Font = F.Heading, TextSize = 17, Size = UDim2.new(0.5, 0, 0, 22), Parent = header })
	local bonus = UI.label({ Text = "", TextSize = 13, TextColor3 = C.Sparks, Size = UDim2.new(0.5, 0, 0, 18), Position = UDim2.fromOffset(0, 24), Parent = header })
	local progress = UI.progress({ Size = UDim2.new(0.5, -10, 0, 14), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Color = C.Accent2, Parent = header })

	local milestoneRow = UI.new("ScrollingFrame", {
		Name = "Milestones",
		Size = UDim2.new(1, 0, 0, 86),
		Position = UDim2.fromOffset(0, 50),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.Stroke,
		List = { Dir = "X", Pad = 8, VA = "Center" },
		Parent = body,
	})
	local milestoneCards = {}
	for index, m in ipairs(Rewards.Collection) do
		local card = UI.panel({ Name = m.Id, Size = UDim2.fromOffset(170, 78), BackgroundColor3 = C.PanelLight, LayoutOrder = index, Padding = 8, Parent = milestoneRow })
		local need = if m.Count < 0 then Items.Count else m.Count
		UI.label({ Text = `📖 {need} items`, Font = F.Heading, TextSize = 14, Size = UDim2.new(1, 0, 0, 18), Parent = card })
		UI.label({ Text = m.Text, TextSize = 12, TextColor3 = C.TextDim, TextWrapped = true, Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 18), Parent = card })
		local claim = UI.button({
			Text = "Claim",
			Variant = "success",
			Size = UDim2.new(1, 0, 0, 22),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			TextSize = 13,
			OnClick = function()
				local result = ClientNet.once("collection:" .. m.Id, "ClaimCollection", { Id = m.Id })
				if result then
					ctx.Notifications.result(result, "Milestone claimed!")
				end
			end,
			Parent = card,
		})
		milestoneCards[m.Id] = { Card = card, Claim = claim, Need = need }
	end

	local book = UI.scroll({
		Name = "Book",
		Size = UDim2.new(1, 0, 1, -146),
		Position = UDim2.fromOffset(0, 146),
		List = { Dir = "Y", Pad = 10 },
		Padding = { 2, 8, 2, 8 },
		Parent = body,
	})
	local sections = {}
	for index, chestId in ipairs(Chests.Order) do
		local chest = Chests.ById[chestId]
		local title = UI.label({
			Name = chestId .. "Title",
			Text = chest.Name,
			Font = F.Heading,
			TextSize = 16,
			TextColor3 = chest.Color,
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = index * 2 - 1,
			Parent = book,
		})
		local grid = UI.frame({
			Name = chestId .. "Grid",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = index * 2,
			Grid = { Cell = UDim2.fromOffset(84, 100), Pad = UDim2.fromOffset(8, 8) },
			Parent = book,
		})
		local cards = {}
		local pool = Items.PoolByChest[chestId] or {}
		local order = 0
		for _, rarityId in ipairs(Rarities.Order) do
			for _, itemId in ipairs(pool[rarityId] or {}) do
				order += 1
				local card = ItemCard.new({ Parent = grid, LayoutOrder = order, Size = UDim2.fromOffset(84, 100) })
				local item = Items.ById[itemId]
				UI.attachTooltip(card.Instance, function()
					local found = State.get("Discovered") or {}
					local discovered = found[itemId]
					if discovered then
						-- Which Golden / Rainbow versions have been found too.
						local variants = {}
						for _, variant in ipairs(Items.Variants) do
							local mark = if found[Items.variantId(itemId, variant.Id)] then "✓" else "✗"
							table.insert(variants, `{variant.Name} {mark}`)
						end
						return `<b>{item.Icon} {item.Name}</b> ({item.Rarity})\n{Formulas.describeItemBonus(item, 1)}\n{item.Description}\nDiscovered {os.date("%Y-%m-%d", discovered)}\n{table.concat(variants, " · ")}`
					end
					if item.Rarity == "Secret" then
						return `A secret hides in the {chest.Name}…`
					end
					return `Undiscovered {item.Rarity} item from the {chest.Name}.`
				end)
				card.Instance.Activated:Connect(function()
					if (State.get("Inventory") or {})[itemId] then
						local screens = ctx.Screens
						screens.open("Inventory", itemId)
					end
				end)
				table.insert(cards, { Card = card, Id = itemId })
			end
		end
		sections[chestId] = { Title = title, Cards = cards, Chest = chest }
	end

	function screen.Refresh()
		if not window.IsOpen() then
			return
		end
		local discovered = State.get("Discovered") or {}
		local claimed = State.get("CollectionClaimed") or {}
		local count = Formulas.discoveredCount(State.view())
		headline.Text = `Discovered {count} / {Items.Count}`
		bonus.Text = `Collection bonus: +{Format.pct(count * GameConfig.Collection.SparksBonusPerItem)} Sparks`
		progress.Set(count / Items.Count, Format.pct(count / Items.Count))
		for _, section in pairs(sections) do
			local found = 0
			for _, entry in ipairs(section.Cards) do
				local isFound = discovered[entry.Id] ~= nil
				if isFound then
					found += 1
				end
				entry.Card:Set({ Id = entry.Id, Undiscovered = not isFound })
			end
			section.Title.Text = `{section.Chest.Icon} {section.Chest.Name} — {found}/{#section.Cards}`
		end
		for id, entry in pairs(milestoneCards) do
			local done = claimed[id] == true
			local ready = count >= entry.Need
			UI.setText(entry.Claim, if done then "Claimed ✓" elseif ready then "Claim" else `{count}/{entry.Need}`)
			UI.setEnabled(entry.Claim, ready and not done)
			entry.Card.BackgroundColor3 = if ready and not done then Theme.darken(C.Success, 0.7) else C.PanelLight
		end
	end

	State.subscribe({ "Discovered", "CollectionClaimed", "Inventory" }, function()
		screen.Refresh()
	end)
	window.Opened.Event:Connect(screen.Refresh)
	return screen
end

return Collection
