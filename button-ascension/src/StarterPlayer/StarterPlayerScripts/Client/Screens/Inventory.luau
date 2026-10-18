--[[
	Inventory (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Screens/Inventory
	Depends on: ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format,Formulas,Config/*},
	            Client/{State,ClientNet,ItemCard}

	Owned items as a searchable, filterable, sortable grid. Items stack by
	type, and each card is created once and then reused (only visibility and
	order change when filtering), so the grid stays fast for any collection.
	The detail panel equips, favourites and sells; selling Epic or better
	asks for confirmation (setting: Confirm rare sales).
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
local Rarities = require(Config.Rarities)
local Chests = require(Config.Chests)
local GameConfig = require(Config.GameConfig)

local Client = script.Parent.Parent
local State = require(Client.State)
local ClientNet = require(Client.ClientNet)
local ItemCard = require(Client.ItemCard)

local C = Theme.Colors
local F = Theme.Fonts

local Inventory = {}

local SORTS = {
	{ Id = "rarity", Text = "Rarity" },
	{ Id = "power", Text = "Power" },
	{ Id = "new", Text = "Newest" },
	{ Id = "count", Text = "Count" },
}

function Inventory.new(ctx)
	local window = UI.window({
		Name = "Inventory",
		Title = "Inventory",
		Subtitle = "Equip items for bonuses. Extra copies make an equipped item up to twice as strong.",
		Icon = "🎒",
		Parent = ctx.Layers.Windows,
	})
	local screen: { [string]: any } = { Window = window }
	local body = window.Body

	local search = ""
	local rarityFilter = 0
	local sortMode = "rarity"
	local selectedId: string? = nil
	local sellMaxRarity = 3

	-- Toolbar -------------------------------------------------------------------------------
	local toolbar = UI.frame({ Name = "Toolbar", Size = UDim2.new(1, 0, 0, 38), Parent = body })
	UI.textbox({
		Placeholder = "🔍 Search…",
		Size = UDim2.fromOffset(150, 36),
		MaxLength = 30,
		OnChanged = function(text)
			search = string.lower(text)
			screen.Render()
		end,
		Parent = toolbar,
	})
	local rarityOptions = { { Id = 0, Text = "All" } }
	for i, id in ipairs(Rarities.Order) do
		table.insert(rarityOptions, { Id = i, Text = string.sub(id, 1, 1) })
	end
	local rarityControl = UI.segmented({
		Options = rarityOptions,
		Value = 0,
		ButtonWidth = 34,
		Position = UDim2.fromOffset(158, 2),
		OnChange = function(id)
			rarityFilter = id
			screen.Render()
		end,
		Parent = toolbar,
	})
	for i, id in ipairs(Rarities.Order) do
		local button = rarityControl.Buttons[i]
		button.TextColor3 = Theme.rarityColor(id)
		UI.attachTooltip(button, id)
	end
	UI.segmented({
		Options = SORTS,
		Value = "rarity",
		ButtonWidth = 56,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 2),
		OnChange = function(id)
			sortMode = id
			screen.Render()
		end,
		Parent = toolbar,
	})

	-- Grid ------------------------------------------------------------------------------------
	local grid = UI.scroll({
		Name = "Grid",
		Size = UDim2.new(1, -326, 1, -150),
		Position = UDim2.fromOffset(0, 48),
		Grid = { Cell = UDim2.fromOffset(92, 108), Pad = UDim2.fromOffset(8, 8) },
		Padding = { 4, 8, 6, 6 },
		Parent = body,
	})
	local empty = UI.label({
		Text = "No items yet — open crates to find some!",
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, -326, 0, 30),
		Position = UDim2.fromOffset(0, 160),
		Visible = false,
		Parent = body,
	})
	local cards: { [string]: any } = {}

	-- Detail panel -----------------------------------------------------------------------------
	local detail = UI.panel({
		Name = "Detail",
		Size = UDim2.new(0, 310, 1, -150),
		Position = UDim2.new(1, -310, 0, 48),
		BackgroundColor3 = C.PanelLight,
		Padding = 14,
		Parent = body,
	})
	local dIcon = UI.label({ Text = "", TextSize = 56, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 70), Parent = detail })
	local dName = UI.label({ Text = "Select an item", Font = F.Heading, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 72), Parent = detail })
	local dSub = UI.label({ Text = "", TextSize = 13, TextColor3 = C.TextDim, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 98), Parent = detail })
	local dEffect = UI.label({ Text = "", Font = F.Bold, TextSize = 15, TextColor3 = C.Accent2, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 122), Parent = detail })
	local dCopies = UI.label({ Text = "", TextSize = 13, TextColor3 = C.TextDim, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 144), Parent = detail })
	local dDesc = UI.label({ Text = "", TextSize = 13, TextColor3 = C.TextDim, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 180), Parent = detail })
	local dValue = UI.label({ Text = "", TextSize = 13, TextColor3 = C.Gems, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 218), Parent = detail })
	local actions = UI.frame({ Size = UDim2.new(1, 0, 0, 132), AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Parent = detail })

	local equipButton, favButton, sellOne, sellExtra, sellAll

	local function confirmSell(item, count: number): boolean
		local settings = State.get("Settings") or {}
		local equipped = table.find(State.get("Equipped") or {}, item.Id) ~= nil
		local owned = (State.get("Inventory") or {})[item.Id] or 0
		local needs = (settings.ConfirmRareSales ~= false and item.RarityIndex >= 4) or (equipped and count >= owned)
		if not needs then
			return true
		end
		local stats = State.stats()
		local gems = Formulas.sellValue(item, count, if stats then stats.gemMultiplier else 1)
		return UI.confirm({
			Title = `Sell {count}× {item.Name}?`,
			Message = `This {item.Rarity} item sells for 💎 {Format.short(gems)}.` .. (if equipped and count >= owned then " It will be unequipped." else ""),
			ConfirmText = "Sell",
			Danger = true,
		})
	end

	local function sell(count: number)
		local item = selectedId and Items.ById[selectedId]
		if not item then
			return
		end
		if not confirmSell(item, count) then
			return
		end
		local result = ClientNet.once("sell", "Sell", { Id = item.Id, Amount = count })
		if result then
			if result.ok then
				ctx.Notifications.result(result, `Sold {result.Sold}× {item.Name} for 💎 {Format.short(result.Gems)}`)
			else
				ctx.Notifications.error(result.err)
			end
		end
	end

	equipButton = UI.button({
		Text = "Equip",
		Variant = "primary",
		Size = UDim2.new(0.62, -4, 0, 40),
		OnClick = function()
			if not selectedId then
				return
			end
			local isEquipped = table.find(State.get("Equipped") or {}, selectedId) ~= nil
			local result = ClientNet.once("equip", if isEquipped then "Unequip" else "Equip", { Id = selectedId })
			if result and not result.ok then
				ctx.Notifications.error(result.err)
			end
		end,
		Parent = actions,
	})
	favButton = UI.button({
		Text = "☆",
		Variant = "ghost",
		Size = UDim2.new(0.38, -4, 0, 40),
		Position = UDim2.new(0.62, 4, 0, 0),
		Tooltip = "Favourite items can't be sold.",
		OnClick = function()
			if not selectedId then
				return
			end
			local isFav = (State.get("Favorites") or {})[selectedId] == true
			local result = ClientNet.once("fav", "Favorite", { Id = selectedId, State = not isFav })
			if result and not result.ok then
				ctx.Notifications.error(result.err)
			end
		end,
		Parent = actions,
	})
	sellOne = UI.button({
		Text = "Sell 1",
		Variant = "danger",
		Size = UDim2.new(1 / 3, -6, 0, 36),
		Position = UDim2.fromOffset(0, 48),
		TextSize = 14,
		OnClick = function()
			sell(1)
		end,
		Parent = actions,
	})
	sellExtra = UI.button({
		Text = "Sell extras",
		Variant = "danger",
		Size = UDim2.new(1 / 3, -6, 0, 36),
		Position = UDim2.new(1 / 3, 3, 0, 48),
		TextSize = 14,
		Tooltip = "Sell every copy except one.",
		OnClick = function()
			local owned = selectedId and (State.get("Inventory") or {})[selectedId] or 0
			if owned > 1 then
				sell(owned - 1)
			end
		end,
		Parent = actions,
	})
	sellAll = UI.button({
		Text = "Sell all",
		Variant = "danger",
		Size = UDim2.new(1 / 3, -6, 0, 36),
		Position = UDim2.new(2 / 3, 6, 0, 48),
		TextSize = 14,
		OnClick = function()
			local owned = selectedId and (State.get("Inventory") or {})[selectedId] or 0
			if owned > 0 then
				sell(owned)
			end
		end,
		Parent = actions,
	})
	local dDate = UI.label({ Text = "", TextSize = 12, TextColor3 = C.TextMuted, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 96), Parent = actions })

	-- Equipped bar -------------------------------------------------------------------------------
	local bar = UI.panel({
		Name = "EquipBar",
		Size = UDim2.new(1, 0, 0, 92),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.PanelLight,
		Padding = 10,
		Parent = body,
	})
	local slotsLabel = UI.label({ Text = "Equipped", Font = F.Heading, TextSize = 15, Size = UDim2.fromOffset(140, 20), Parent = bar })
	local slotsBonus = UI.label({ Text = "", TextSize = 12, TextColor3 = C.TextDim, TextWrapped = true, Size = UDim2.fromOffset(140, 46), Position = UDim2.fromOffset(0, 22), Parent = bar })
	local slotRow = UI.frame({ Size = UDim2.new(1, -460, 1, 0), Position = UDim2.fromOffset(146, 0), List = { Dir = "X", Pad = 6, VA = "Center" }, Parent = bar })
	local slotButtons = {}
	for i = 1, GameConfig.Equip.MaxSlots do
		local slot = UI.new("TextButton", {
			Name = "Slot" .. i,
			Size = UDim2.fromOffset(62, 62),
			BackgroundColor3 = C.BackgroundAlt,
			AutoButtonColor = false,
			Text = "",
			TextSize = 30,
			TextColor3 = C.White,
			LayoutOrder = i,
			Corner = Theme.Radius.Medium,
			Parent = slotRow,
		})
		local stroke = UI.stroke(slot, { Color = C.StrokeSoft, Thickness = 1.5 })
		slot.Activated:Connect(function()
			local id = (State.get("Equipped") or {})[i]
			if id then
				selectedId = id
				screen.Render()
			end
		end)
		slotButtons[i] = { Button = slot, Stroke = stroke }
	end
	UI.button({
		Text = "Equip best",
		Icon = "⭐",
		Variant = "primary",
		Size = UDim2.fromOffset(140, 34),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -160, 0, 2),
		TextSize = 14,
		OnClick = function()
			local result = ClientNet.once("equipbest", "EquipBest")
			if result then
				ctx.Notifications.result(result, "Equipped your strongest items.")
			end
		end,
		Parent = bar,
	})
	local sellRarity = UI.button({
		Text = "",
		Variant = "ghost",
		Size = UDim2.fromOffset(150, 34),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, -2),
		TextSize = 13,
		Tooltip = "Choose the highest rarity included when selling duplicates.",
		Parent = bar,
	})
	local function renderSellRarity()
		local id = Rarities.Order[sellMaxRarity]
		sellRarity.Text = `up to {id} ▾`
		sellRarity.TextColor3 = Theme.rarityColor(id)
	end
	sellRarity.Activated:Connect(function()
		sellMaxRarity = (sellMaxRarity % 6) + 1
		renderSellRarity()
	end)
	renderSellRarity()
	UI.button({
		Text = "Sell duplicates",
		Icon = "💎",
		Variant = "danger",
		Size = UDim2.fromOffset(150, 34),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 2),
		TextSize = 14,
		OnClick = function()
			local rarityName = Rarities.Order[sellMaxRarity]
			local ok = UI.confirm({
				Title = "Sell duplicates?",
				Message = `Sells every extra copy of Common to {rarityName} items, keeping one of each. Favourites are never sold.`,
				ConfirmText = "Sell duplicates",
				Danger = sellMaxRarity >= 4,
			})
			if not ok then
				return
			end
			local result = ClientNet.once("selldupes", "SellDuplicates", { MaxRarity = sellMaxRarity })
			if result then
				if result.ok then
					ctx.Notifications.result(result, `Sold {result.Sold} duplicates for 💎 {Format.short(result.Gems)}`)
				else
					ctx.Notifications.error(result.err)
				end
			end
		end,
		Parent = bar,
	})

	-- Rendering -----------------------------------------------------------------------------------

	local function renderDetail()
		local inventory = State.get("Inventory") or {}
		local item = selectedId and Items.ById[selectedId]
		local count = if item then inventory[item.Id] or 0 else 0
		if not item or count <= 0 then
			selectedId = nil
			dIcon.Text = "🎒"
			dName.Text = "Select an item"
			dName.TextColor3 = C.Text
			dSub.Text, dEffect.Text, dCopies.Text, dDesc.Text, dValue.Text, dDate.Text = "", "", "", "", "", ""
			for _, b in ipairs({ equipButton, favButton, sellOne, sellExtra, sellAll }) do
				UI.setEnabled(b, false)
			end
			return
		end
		local equipped = table.find(State.get("Equipped") or {}, item.Id) ~= nil
		local favorite = (State.get("Favorites") or {})[item.Id] == true
		local stats = State.stats()
		dIcon.Text = item.Icon
		dName.Text = item.Name
		dName.TextColor3 = Theme.rarityColor(item.Rarity)
		dSub.Text = `{item.Rarity} · {Chests.ById[item.Chest].Name} · owned ×{count}`
		dEffect.Text = Formulas.describeItemBonus(item, count) .. (if equipped then " (active)" else "")
		local bonus = Formulas.copyBonus(count)
		dCopies.Text = `Copies bonus: +{Format.pct(bonus)} power` .. (if bonus < GameConfig.Equip.MaxCopyBonus then " · more copies increase it" else " · maxed")
		dDesc.Text = item.Description
		dValue.Text = `Sell value: 💎 {Format.short(Formulas.sellValue(item, 1, if stats then stats.gemMultiplier else 1))} each`
		local found = (State.get("Discovered") or {})[item.Id]
		dDate.Text = if found then "Discovered " .. os.date("%Y-%m-%d", found) else ""
		UI.setText(equipButton, if equipped then "Unequip" else "Equip")
		UI.setVariant(equipButton, if equipped then "secondary" else "primary")
		UI.setEnabled(equipButton, true)
		UI.setText(favButton, if favorite then "★ Favourite" else "☆ Favourite")
		UI.setEnabled(favButton, true)
		UI.setEnabled(sellOne, not favorite)
		UI.setEnabled(sellExtra, not favorite and count > 1)
		UI.setEnabled(sellAll, not favorite)
	end

	local function renderEquipBar()
		local equippedList = State.get("Equipped") or {}
		local stats = State.stats()
		local slots = if stats then stats.equipSlots else GameConfig.Equip.BaseSlots
		slotsLabel.Text = `Equipped {#equippedList}/{slots}`
		local inventory = State.get("Inventory") or {}
		local totals = {}
		for _, id in ipairs(equippedList) do
			local item = Items.ById[id]
			if item then
				local label = GameConfig.ItemStats[item.Stat].Label
				totals[label] = (totals[label] or 0) + Formulas.itemPower(item, inventory[id] or 1)
			end
		end
		local parts = {}
		for label, value in pairs(totals) do
			table.insert(parts, `+{Format.pct(value)} {label}`)
		end
		table.sort(parts)
		slotsBonus.Text = table.concat(parts, ", ")
		for i, slot in ipairs(slotButtons) do
			local id = equippedList[i]
			local item = id and Items.ById[id]
			slot.Button.Visible = i <= slots
			slot.Button.Text = if item then item.Icon else "+"
			slot.Button.TextColor3 = if item then C.White else C.TextMuted
			slot.Stroke.Color = if item then Theme.rarityColor(item.Rarity) else C.StrokeSoft
		end
	end

	function screen.Render()
		if not window.IsOpen() then
			return
		end
		local inventory = State.get("Inventory") or {}
		local discovered = State.get("Discovered") or {}
		local equippedList = State.get("Equipped") or {}
		local favorites = State.get("Favorites") or {}
		local list = {}
		for id, count in pairs(inventory) do
			local item = Items.ById[id]
			if item and count > 0 then
				local matches = (rarityFilter == 0 or item.RarityIndex == rarityFilter)
					and (search == "" or string.find(string.lower(item.Name), search, 1, true) ~= nil or string.find(item.Id, search, 1, true) ~= nil)
				if matches then
					table.insert(list, { Item = item, Count = count, Power = Formulas.itemPower(item, count), Found = discovered[id] or 0 })
				end
			end
		end
		table.sort(list, function(a, b)
			if sortMode == "power" and a.Power ~= b.Power then
				return a.Power > b.Power
			elseif sortMode == "new" and a.Found ~= b.Found then
				return a.Found > b.Found
			elseif sortMode == "count" and a.Count ~= b.Count then
				return a.Count > b.Count
			end
			if a.Item.RarityIndex ~= b.Item.RarityIndex then
				return a.Item.RarityIndex > b.Item.RarityIndex
			end
			return a.Item.Order < b.Item.Order
		end)
		local visible = {}
		for index, entry in ipairs(list) do
			local id = entry.Item.Id
			local card = cards[id]
			if not card then
				card = ItemCard.new({
					Parent = grid,
					OnClick = function(c)
						selectedId = c.State.Id
						screen.Render()
					end,
				})
				cards[id] = card
			end
			visible[id] = true
			card.Instance.Visible = true
			card.Instance.LayoutOrder = index
			card:Set({
				Id = id,
				Count = entry.Count,
				Equipped = table.find(equippedList, id) ~= nil,
				Favorite = favorites[id] == true,
				Selected = id == selectedId,
			})
		end
		for id, card in pairs(cards) do
			if not visible[id] then
				card.Instance.Visible = false
			end
		end
		empty.Visible = #list == 0
		empty.Text = if next(inventory) == nil then "No items yet — open crates to find some!" else "No items match your filters."
		renderDetail()
		renderEquipBar()
	end

	local pending = false
	State.subscribe({ "Inventory", "Equipped", "Favorites", "Derived", "Discovered" }, function()
		if pending or not window.IsOpen() then
			return
		end
		pending = true
		task.delay(0.1, function()
			pending = false
			screen.Render()
		end)
	end)
	window.Opened.Event:Connect(screen.Render)

	function screen.OnOpen(itemId: string?)
		if itemId then
			selectedId = itemId
		end
	end
	return screen
end

return Inventory
