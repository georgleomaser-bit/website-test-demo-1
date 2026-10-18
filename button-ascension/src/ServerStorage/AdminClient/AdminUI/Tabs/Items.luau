--[[
	Items tab (ModuleScript)
	Location: ServerStorage/AdminClient/AdminUI/Tabs/Items
	Depends on: AdminUI/Widgets, AdminUI/TargetPicker, ReplicatedStorage/Shared/Format,
	            ReplicatedStorage/Shared/Config/{Items,Chests,Rarities}
	Server actions: items.grant, items.remove, chests.grant, players.inspect,
	                items.simulate (no data changes), items.forceRoll (test drop)

	Grant/remove items and crates, inspect inventories, and test crate odds.
	Drop-rate tests run the production roll function on the server with a
	private pity state, so real odds for players are never changed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Format = require(Shared:WaitForChild("Format"))
local Items = require(Config:WaitForChild("Items"))
local Chests = require(Config:WaitForChild("Chests"))
local Rarities = require(Config:WaitForChild("Rarities"))

local Widgets = require(script.Parent.Parent.Widgets)
local TargetPicker = require(script.Parent.Parent.TargetPicker)

local UI = Widgets.UI
local P = Widgets.P
local F = Widgets.Theme.Fonts

local function chestOptions()
	local options = {}
	for _, id in ipairs(Chests.Order) do
		local chest = Chests.ById[id]
		table.insert(options, { Text = `{chest.Icon} {chest.Name}  ({id})`, Value = id, Color = chest.Color })
	end
	return options
end

local function chestLabel(id: string): string
	local chest = Chests.ById[id]
	return if chest then `{chest.Icon} {chest.Name}` else id
end

return function(ctx, container: Frame)
	local scroll = Widgets.scroll(container)
	local canGrant = ctx.has("items.grant")
	local canTest = ctx.has("items.test")
	local limits = ctx.Hello.Limits or {}

	local function target(): any
		local query = ctx.Target.Query
		if query == nil then
			ctx.toast("Select a target player first.", "error")
		end
		return query
	end

	local function count(box: TextBox, fallback: number): number?
		if box.Text == "" then
			return fallback
		end
		local n = Widgets.parseNumber(box.Text)
		if not n or n < 1 or n ~= math.floor(n) then
			ctx.toast("Amount must be a whole number of at least 1.", "error")
			return nil
		end
		return n
	end

	-- Target ------------------------------------------------------------------------------
	local targetSection = Widgets.section(scroll, "Target", 1)
	TargetPicker.new(ctx, targetSection, 1)

	-- Item grants -----------------------------------------------------------------------------
	local itemSection = Widgets.section(scroll, "Grant or remove items", 2, `Limit per action: {limits.MaxItems or 0} copies.`)
	local search = Widgets.textbox({ Placeholder = "🔍 Search items by name or id", LayoutOrder = 1, Parent = itemSection })
	local rarityOptions = { { Id = "All", Text = "All" } }
	for _, rarityId in ipairs(Rarities.Order) do
		table.insert(rarityOptions, { Id = rarityId, Text = rarityId, Color = Rarities.ById[rarityId].Color })
	end
	local rarityFilter = "All"
	local itemRows: { [string]: TextButton } = {}
	local selectedItem: string? = nil
	local selectedLabel: TextLabel

	local function renderItems()
		local q = string.lower(search.Text)
		for _, item in ipairs(Items.List) do
			local row = itemRows[item.Id]
			local visible = (rarityFilter == "All" or item.Rarity == rarityFilter)
				and (q == "" or string.find(string.lower(item.Name), q, 1, true) ~= nil or string.find(item.Id, q, 1, true) ~= nil)
			row.Visible = visible
			local stroke = row:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if item.Id == selectedItem then P.Accent else P.Stroke
				stroke.Transparency = if item.Id == selectedItem then 0 else 0.6
			end
		end
	end

	Widgets.chips({
		Parent = itemSection,
		Options = rarityOptions,
		Value = "All",
		Order = 2,
		Height = 26,
		OnChange = function(id)
			rarityFilter = id
			renderItems()
		end,
	})

	local itemList = UI.scroll({
		Name = "ItemList",
		Size = UDim2.new(1, 0, 0, 220),
		LayoutOrder = 3,
		BackgroundColor3 = P.Background,
		BackgroundTransparency = 0,
		ScrollBarImageColor3 = P.Stroke,
		Corner = 10,
		Padding = 6,
		List = { Pad = 4 },
		Parent = itemSection,
	})
	for index, item in ipairs(Items.List) do
		local color = Widgets.rarityColor(item.Rarity)
		local row = UI.new("TextButton", {
			Name = item.Id,
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundColor3 = P.PanelLight,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = index,
			Corner = 8,
			Stroke = { Color = P.Stroke, Transparency = 0.6 },
			Parent = itemList,
		})
		Widgets.label({ Text = item.Icon, TextSize = 22, Size = UDim2.fromOffset(34, 40), TextXAlignment = Enum.TextXAlignment.Center, Parent = row })
		Widgets.label({ Text = item.Name, Font = F.Bold, TextColor3 = color, Size = UDim2.new(1, -50, 0, 18), Position = UDim2.fromOffset(40, 3), TextTruncate = Enum.TextTruncate.AtEnd, Parent = row })
		Widgets.dim({ Text = `{item.Id} · {item.Rarity} · {chestLabel(item.Chest)}`, TextSize = 12, Size = UDim2.new(1, -50, 0, 16), Position = UDim2.fromOffset(40, 21), TextTruncate = Enum.TextTruncate.AtEnd, Parent = row })
		row.Activated:Connect(function()
			selectedItem = item.Id
			selectedLabel.Text = `Selected: {item.Icon} {item.Name} ({item.Id})`
			selectedLabel.TextColor3 = color
			renderItems()
		end)
		itemRows[item.Id] = row
	end
	search:GetPropertyChangedSignal("Text"):Connect(renderItems)

	selectedLabel = Widgets.label({ Text = "Selected: none", LayoutOrder = 4, TextColor3 = P.TextDim, Parent = itemSection })
	local grantRow = Widgets.row(itemSection, 5, 34)
	Widgets.rowLabel(grantRow, "Amount", 70, 1)
	local itemAmount = Widgets.textbox({ Placeholder = "1", Size = UDim2.fromOffset(90, 32), LayoutOrder = 2, MaxLength = 10, Parent = grantRow })
	local grantItem = Widgets.button({
		Text = "＋ Grant item",
		Variant = "adminPrimary",
		LayoutOrder = 3,
		OnClick = function()
			local t = target()
			local n = count(itemAmount, 1)
			if not selectedItem then
				ctx.toast("Pick an item from the list.", "error")
				return
			end
			if t ~= nil and n then
				ctx.Net.run("items.grant", { Target = t, Item = selectedItem, Amount = n }, { Label = "Grant item" })
			end
		end,
		Parent = grantRow,
	})
	local removeItem = Widgets.button({
		Text = "－ Remove item",
		Variant = "adminSecondary",
		LayoutOrder = 4,
		OnClick = function()
			local t = target()
			local n = count(itemAmount, 1)
			if not selectedItem then
				ctx.toast("Pick an item from the list.", "error")
				return
			end
			if t ~= nil and n then
				ctx.Net.run("items.remove", { Target = t, Item = selectedItem, Amount = n }, { Label = "Remove item" })
			end
		end,
		Parent = grantRow,
	})
	Widgets.gate(grantItem, canGrant, "items.grant")
	Widgets.gate(removeItem, canGrant, "items.grant")

	-- Crates -----------------------------------------------------------------------------------------
	local crateSection = Widgets.section(scroll, "Grant crates", 3, `Limit per action: {limits.MaxChests or 0} crates.`)
	local crateRow = Widgets.row(crateSection, 1, 34)
	local crateDropdown = Widgets.dropdown({ Parent = crateRow, Order = 1, Width = 240, Options = chestOptions, Value = "starter", Text = chestLabel("starter") })
	local crateAmount = Widgets.textbox({ Placeholder = "1", Size = UDim2.fromOffset(80, 32), LayoutOrder = 2, MaxLength = 10, Parent = crateRow })
	local grantCrate = Widgets.button({
		Text = "📦 Grant crates",
		Variant = "adminPrimary",
		Size = UDim2.fromOffset(140, 32),
		LayoutOrder = 3,
		OnClick = function()
			local t = target()
			local n = count(crateAmount, 1)
			if t ~= nil and n then
				ctx.Net.run("chests.grant", { Target = t, Chest = crateDropdown.Get(), Amount = n }, { Label = "Grant crates" })
			end
		end,
		Parent = crateRow,
	})
	Widgets.gate(grantCrate, canGrant, "items.grant")

	-- Inventory inspection -------------------------------------------------------------------------
	local inventorySection = Widgets.section(scroll, "Inventory", 4)
	local inventoryButton = Widgets.button({ Text = "🎒 Inspect inventory", Variant = "adminMagenta", Size = UDim2.fromOffset(180, 32), LayoutOrder = 1, Parent = inventorySection })
	Widgets.gate(inventoryButton, ctx.has("players.inspect"), "players.inspect")
	local inventorySummary = Widgets.dim({ Text = "", LayoutOrder = 2, Parent = inventorySection })
	local inventoryList = UI.frame({ Name = "Inventory", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, Parent = inventorySection })
	UI.grid(inventoryList, { Cell = UDim2.new(0.5, -4, 0, 26), Pad = UDim2.fromOffset(8, 4) })

	local function inspectInventory()
		local t = target()
		if t == nil then
			return
		end
		Widgets.clear(inventoryList)
		inventorySummary.Text = "Loading…"
		local response = ctx.Net.request("players.inspect", { Target = t })
		if not response.ok or type(response.data) ~= "table" then
			inventorySummary.Text = response.err or "Could not load inventory."
			inventorySummary.TextColor3 = P.Danger
			return
		end
		local data = response.data
		local items = data.Inventory or {}
		local copies = 0
		for index, entry in ipairs(items) do
			copies += entry.Count
			local item = Items.ById[entry.Id]
			Widgets.label({
				Text = `{if item then item.Icon else "?"} {entry.Name} ×{Format.commas(entry.Count)}{if entry.Equipped then "  ✔ equipped" else ""}`,
				TextColor3 = Widgets.rarityColor(entry.Rarity),
				TextSize = 13,
				TextTruncate = Enum.TextTruncate.AtEnd,
				LayoutOrder = index,
				Parent = inventoryList,
			})
		end
		local who = if data.Online == false then `#{data.UserId} (offline)` else `{data.DisplayName} (@{data.Name})`
		inventorySummary.Text = `{who}: {#items} unique items, {Format.commas(copies)} copies.`
		inventorySummary.TextColor3 = P.TextDim
	end
	inventoryButton.Activated:Connect(function()
		if not inventoryButton:GetAttribute("Disabled") then
			inspectInventory()
		end
	end)

	-- Drop-rate testing --------------------------------------------------------------------------
	local testSection = Widgets.section(scroll, "Test drop rates", 5, "Runs the real roll function on the server with a private pity state. No player data changes.")
	local testRow = Widgets.row(testSection, 1, 34)
	local testCrate = Widgets.dropdown({ Parent = testRow, Order = 1, Width = 240, Options = chestOptions, Value = "starter", Text = chestLabel("starter") })
	local countChips = Widgets.chips({
		Parent = testRow,
		Options = { { Id = 1000, Text = "1,000" }, { Id = 10000, Text = "10,000" }, { Id = 100000, Text = "100,000" } },
		Value = 10000,
		Order = 2,
		Height = 30,
		Width = 80,
	})
	countChips.Frame.Size = UDim2.fromOffset(260, 30)
	countChips.Frame.AutomaticSize = Enum.AutomaticSize.None

	local optionsRow = Widgets.row(testSection, 2, 34)
	Widgets.rowLabel(optionsRow, "Luck bonus", 80, 1)
	local luckBox = Widgets.textbox({ Placeholder = "0 (1 = +100%)", Size = UDim2.fromOffset(130, 32), LayoutOrder = 2, MaxLength = 6, Parent = optionsRow })
	Widgets.rowLabel(optionsRow, "Pity", 40, 3)
	local pityOn = false
	UI.toggle({
		Value = false,
		LayoutOrder = 4,
		OnChange = function(value)
			pityOn = value
		end,
		Parent = optionsRow,
	})
	local runTest = Widgets.button({ Text = "▶ Run simulation", Variant = "adminPrimary", Size = UDim2.fromOffset(160, 32), LayoutOrder = 5, Parent = optionsRow })
	Widgets.gate(runTest, canTest, "items.test")

	local resultsFrame = UI.frame({ Name = "Results", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, List = { Pad = 2 }, Parent = testSection })

	local function header(parent: Instance, cells: { string }, color: Color3?, order: number, bold: boolean?)
		local row = UI.frame({ Size = UDim2.new(1, 0, 0, 22), LayoutOrder = order, Parent = parent })
		local widths = { 0.31, 0.23, 0.23, 0.23 }
		local x = 0
		for i, text in ipairs(cells) do
			Widgets.label({
				Text = text,
				Font = if bold then F.Heading else F.Medium,
				TextSize = 13,
				TextColor3 = if i == 1 and color then color else (if bold then P.TextDim else P.Text),
				Size = UDim2.new(widths[i], 0, 1, 0),
				Position = UDim2.fromScale(x, 0),
				TextXAlignment = if i == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
				Parent = row,
			})
			x += widths[i]
		end
	end

	runTest.Activated:Connect(function()
		if runTest:GetAttribute("Disabled") then
			return
		end
		local luck = if luckBox.Text == "" then 0 else tonumber(luckBox.Text)
		if luck == nil or luck < 0 or luck > 10 then
			ctx.toast("Luck must be a number from 0 to 10.", "error")
			return
		end
		Widgets.clear(resultsFrame)
		Widgets.dim({ Text = "Simulating…", LayoutOrder = 1, Parent = resultsFrame })
		local response = ctx.Net.run("items.simulate", { Chest = testCrate.Get(), Count = countChips.Get(), Luck = luck, Pity = pityOn }, { Label = "Simulation", Silent = true })
		Widgets.clear(resultsFrame)
		if not response.ok or type(response.data) ~= "table" then
			Widgets.label({ Text = response.err or "Simulation failed.", TextColor3 = P.Danger, LayoutOrder = 1, Parent = resultsFrame })
			ctx.log("Simulation: " .. tostring(response.err), "error")
			return
		end
		local data = response.data
		header(resultsFrame, { "Rarity", "Drops", "Observed", "Expected" }, nil, 1, true)
		local order = 2
		for _, rarityId in ipairs(Rarities.Order) do
			local expected = data.Expected and data.Expected[rarityId]
			if expected then
				local drops = (data.Counts and data.Counts[rarityId]) or 0
				header(resultsFrame, {
					rarityId,
					Format.commas(drops),
					Format.pct(drops / math.max(1, data.Count), 2),
					Format.pct(expected, 2),
				}, Widgets.rarityColor(rarityId), order)
				order += 1
			end
		end
		Widgets.dim({ Text = `{Format.commas(data.Count)} × {chestLabel(data.Chest)} · No player data changed.`, LayoutOrder = order, Parent = resultsFrame })
		ctx.log(response.message or "Simulation complete.", "ok")
	end)

	-- Forced-rarity test drop ----------------------------------------------------------------------
	local forceSection = Widgets.section(scroll, "Forced-rarity test drop", 6, "Gives the target one item of the chosen rarity from the crate's pool. Logged as a test; real odds are unchanged.")
	local forceRow = Widgets.row(forceSection, 1, 34)
	local forceCrate = Widgets.dropdown({ Parent = forceRow, Order = 1, Width = 240, Options = chestOptions, Value = "starter", Text = chestLabel("starter") })
	local forceRarity = Widgets.dropdown({
		Parent = forceRow,
		Order = 2,
		Width = 160,
		Value = "Legendary",
		Text = "Legendary",
		Options = function()
			local options = {}
			local chest = Chests.ById[forceCrate.Get()]
			for _, rarityId in ipairs(Rarities.Order) do
				if chest and chest.Weights[rarityId] then
					table.insert(options, { Text = rarityId, Value = rarityId, Color = Rarities.ById[rarityId].Color })
				end
			end
			return options
		end,
	})
	local forceButton = Widgets.button({
		Text = "🎲 Give test drop",
		Variant = "adminMagenta",
		Size = UDim2.fromOffset(160, 32),
		LayoutOrder = 3,
		OnClick = function()
			local t = target()
			if t ~= nil then
				ctx.Net.run("items.forceRoll", { Target = t, Chest = forceCrate.Get(), Rarity = forceRarity.Get() }, { Label = "Test drop" })
			end
		end,
		Parent = forceRow,
	})
	Widgets.gate(forceButton, canTest, "items.test")

	renderItems()

	local tab = {}
	function tab.OnShow(mode: string?)
		if mode == "inspect" then
			inspectInventory()
			task.defer(function()
				scroll.CanvasPosition = Vector2.new(0, math.max(0, inventorySection.AbsolutePosition.Y - scroll.AbsolutePosition.Y + scroll.CanvasPosition.Y - 10))
			end)
		end
	end
	return tab
end
