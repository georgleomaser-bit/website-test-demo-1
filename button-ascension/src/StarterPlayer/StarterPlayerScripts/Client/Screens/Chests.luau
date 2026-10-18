--[[
	Chests (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Screens/Chests
	Depends on: ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format,Formulas,Loot,Config/*},
	            Client/{State,ClientNet,ItemCard,Screens/ChestOpening}

	Crate shop: pick a crate on the left; the right panel shows its price,
	owned count, live drop odds (including your Luck), pity progress and every
	item in its pool (undiscovered ones stay hidden). Opening calls the
	server, which rolls everything; the result is then animated by ChestOpening.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIFolder = ReplicatedStorage:WaitForChild("UI")
local UI = require(UIFolder.UIKit)
local Theme = require(UIFolder.Theme)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Loot = require(Shared.Loot)
local Config = Shared.Config
local Chests = require(Config.Chests)
local Items = require(Config.Items)
local Rarities = require(Config.Rarities)
local GameConfig = require(Config.GameConfig)

local Client = script.Parent.Parent
local State = require(Client.State)
local ClientNet = require(Client.ClientNet)
local ChestOpening = require(script.Parent.ChestOpening)

local C = Theme.Colors
local F = Theme.Fonts

local ChestsScreen = {}

function ChestsScreen.new(ctx)
	local window = UI.window({
		Name = "Chests",
		Title = "Crates",
		Subtitle = "Every roll happens on the server. Luck shifts the odds toward rarer items.",
		Icon = "🎁",
		Parent = ctx.Layers.Windows,
	})
	local screen: { [string]: any } = { Window = window }
	local body = window.Body
	local selected = "starter"
	local busy = false

	local listFrame = UI.scroll({
		Name = "CrateList",
		Size = UDim2.new(0, 300, 1, 0),
		List = { Dir = "Y", Pad = 8 },
		Padding = { 2, 8, 2, 2 },
		Parent = body,
	})
	local detail = UI.panel({
		Name = "Detail",
		Size = UDim2.new(1, -316, 1, 0),
		Position = UDim2.fromOffset(316, 0),
		BackgroundColor3 = C.PanelLight,
		Parent = body,
	})
	local detailScroll = UI.scroll({
		Size = UDim2.fromScale(1, 1),
		List = { Dir = "Y", Pad = 10 },
		Padding = 16,
		Parent = detail,
	})

	local crateCards = {}
	for index, chestId in ipairs(Chests.Order) do
		local chest = Chests.ById[chestId]
		local card = UI.new("TextButton", {
			Name = chestId,
			Size = UDim2.new(1, 0, 0, 76),
			BackgroundColor3 = C.PanelLight,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = index,
			Selectable = true,
			Corner = Theme.Radius.Medium,
			Parent = listFrame,
		})
		local stroke = UI.stroke(card, { Color = C.StrokeSoft, Thickness = 1.5 })
		UI.label({ Text = chest.Icon, TextSize = 34, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(64, 76), Parent = card })
		UI.label({ Text = chest.Name, Font = F.Heading, TextSize = 17, TextColor3 = chest.Color, Size = UDim2.new(1, -72, 0, 22), Position = UDim2.fromOffset(64, 12), Parent = card })
		local sub = UI.label({ Text = "", TextSize = 13, TextColor3 = C.TextDim, RichText = true, Size = UDim2.new(1, -72, 0, 18), Position = UDim2.fromOffset(64, 38), Parent = card })
		local owned = UI.label({
			Text = "",
			Font = F.Heading,
			TextSize = 13,
			TextColor3 = C.White,
			TextXAlignment = Enum.TextXAlignment.Center,
			BackgroundColor3 = C.Accent,
			BackgroundTransparency = 0,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(24, 22),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 8),
			Visible = false,
			Corner = Theme.Radius.Pill,
			Padding = { X = 6 },
			Parent = card,
		})
		card.Activated:Connect(function()
			selected = chestId
			screen.Refresh()
		end)
		crateCards[chestId] = { Card = card, Stroke = stroke, Sub = sub, Owned = owned }
	end

	-- Detail panel content (rebuilt when the selection changes; cheap: one crate).
	local detailItems: { Instance } = {}
	local buyButtons: { { Button: TextButton, Cost: number, Currency: string } } = {}
	local function clearDetail()
		table.clear(buyButtons)
		for _, inst in ipairs(detailItems) do
			inst:Destroy()
		end
		table.clear(detailItems)
	end
	local function add(inst: Instance)
		table.insert(detailItems, inst)
		return inst
	end

	local function openChest(chestId: string, count: number, mode: string)
		if busy then
			return
		end
		local chest = Chests.ById[chestId]
		-- Gems are slow to earn, so spending them is confirmed (Sparks crates are bought quickly).
		if mode == "buy" and chest.Currency == "Gems" then
			local stats = State.stats()
			local price = Formulas.chestPrice(chest, if stats then stats.chestDiscount else 0) * count
			local ok = UI.confirm({
				Title = `Buy {count}× {chest.Name}?`,
				Message = `This spends 💎 {Format.commas(price)} Gems.`,
				ConfirmText = "Buy",
			})
			if not ok then
				return
			end
		end
		busy = true
		local result = ClientNet.action("OpenChest", { Id = chestId, Amount = count, Mode = mode })
		busy = false
		if not result.ok then
			ctx.Notifications.error(result.err)
			return
		end
		ChestOpening.play(ctx, chest, result.Results or {}, function()
			-- "Open again" with the same settings.
			openChest(chestId, count, mode)
		end)
	end
	screen.OpenChest = openChest

	local function buildDetail()
		clearDetail()
		local chest = Chests.ById[selected]
		local data = State.view()
		local stats = State.stats()
		local luck = if stats then stats.luck else 0
		local discount = if stats then stats.chestDiscount else 0
		local unlocked = Formulas.chestUnlocked(chest, data)
		local owned = (State.get("Chests") or {})[chest.Id] or 0
		local order = 0
		local function nextOrder()
			order += 1
			return order
		end

		add(UI.label({
			Text = `{chest.Icon}  {chest.Name}`,
			Font = F.Heading,
			TextSize = 24,
			TextColor3 = chest.Color,
			Size = UDim2.new(1, 0, 0, 30),
			LayoutOrder = nextOrder(),
			Parent = detailScroll,
		}))
		add(UI.label({
			Text = chest.Description,
			TextColor3 = C.TextDim,
			TextSize = 14,
			TextWrapped = true,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = nextOrder(),
			Parent = detailScroll,
		}))

		if not unlocked then
			local stage = GameConfig.Stages[chest.Stage]
			add(UI.label({
				Text = `🔒 Unlocks at stage {stage.Name} ({stage.Rebirths} Ascension{if stage.Rebirths == 1 then "" else "s"}).`,
				Font = F.Bold,
				TextColor3 = C.Warning,
				TextSize = 15,
				Size = UDim2.new(1, 0, 0, 22),
				LayoutOrder = nextOrder(),
				Parent = detailScroll,
			}))
		else
			local price = Formulas.chestPrice(chest, discount)
			local icon = Theme.currencyIcon(chest.Currency)
			local balance = State.currency(chest.Currency)
			local buyRow = add(UI.frame({ Size = UDim2.new(1, 0, 0, 46), LayoutOrder = nextOrder(), List = { Dir = "X", Pad = 8 }, Parent = detailScroll }))
			for i, n in ipairs(Chests.OpenAmounts) do
				local cost = price * n
				local buyButton = UI.button({
					Text = `Buy ×{n}  {icon} {Format.short(cost)}`,
					Variant = "gold",
					Size = UDim2.new(1 / #Chests.OpenAmounts, -6, 1, 0),
					LayoutOrder = i,
					TextSize = 14,
					Disabled = balance < cost,
					OnClick = function()
						openChest(chest.Id, n, "buy")
					end,
					Parent = buyRow,
				})
				table.insert(buyButtons, { Button = buyButton, Cost = cost, Currency = chest.Currency })
			end
			local ownRow = add(UI.frame({ Size = UDim2.new(1, 0, 0, 40), LayoutOrder = nextOrder(), List = { Dir = "X", Pad = 8 }, Parent = detailScroll }))
			for i, n in ipairs(Chests.OpenAmounts) do
				UI.button({
					Text = `Open owned ×{n}`,
					Variant = "primary",
					Size = UDim2.new(1 / #Chests.OpenAmounts, -6, 1, 0),
					LayoutOrder = i,
					TextSize = 14,
					Disabled = owned < n,
					OnClick = function()
						openChest(chest.Id, n, "owned")
					end,
					Parent = ownRow,
				})
			end
			add(UI.label({
				Text = `You own {owned} · Balance {icon} {Format.short(balance)}` .. (if discount > 0 then ` · {Format.pct(discount)} discount` else ""),
				TextColor3 = C.TextDim,
				TextSize = 13,
				Size = UDim2.new(1, 0, 0, 18),
				LayoutOrder = nextOrder(),
				Parent = detailScroll,
			}))
		end

		-- Odds
		add(UI.label({
			Text = `Drop odds  ·  Luck +{Format.pct(luck)}`,
			Font = F.Heading,
			TextSize = 16,
			Size = UDim2.new(1, 0, 0, 22),
			LayoutOrder = nextOrder(),
			Parent = detailScroll,
		}))
		for _, entry in ipairs(Loot.effectiveWeights(chest, luck)) do
			local row = add(UI.frame({ Size = UDim2.new(1, 0, 0, 20), LayoutOrder = nextOrder(), Parent = detailScroll }))
			UI.label({ Text = entry.Rarity, Font = F.Bold, TextSize = 14, TextColor3 = Theme.rarityColor(entry.Rarity), Size = UDim2.new(0, 110, 1, 0), Parent = row })
			local bar = UI.progress({ Size = UDim2.new(1, -200, 0, 8), Position = UDim2.new(0, 110, 0.5, -4), Color = Theme.rarityColor(entry.Rarity), Parent = row })
			bar.Fill.Size = UDim2.fromScale(math.clamp(entry.Chance ^ 0.5, 0.02, 1), 1)
			UI.label({
				Text = Format.pct(entry.Chance, if entry.Chance < 0.01 then 3 else 1),
				Font = F.Bold,
				TextSize = 13,
				TextColor3 = C.TextDim,
				TextXAlignment = Enum.TextXAlignment.Right,
				Size = UDim2.new(0, 80, 1, 0),
				Position = UDim2.new(1, -80, 0, 0),
				Parent = row,
			})
		end

		-- Pity
		local pityState = (State.get("Pity") or {})[chest.Id] or {}
		local pityMult = if stats then stats.pityMultiplier else 1
		for _, rarityId in ipairs(Rarities.Order) do
			local threshold = Formulas.pityThreshold(chest, rarityId, pityMult)
			if threshold then
				local progressValue = pityState[rarityId] or 0
				local row = add(UI.frame({ Size = UDim2.new(1, 0, 0, 34), LayoutOrder = nextOrder(), Parent = detailScroll }))
				UI.label({
					Text = `Pity: guaranteed {rarityId}+ within {threshold} opens`,
					TextSize = 13,
					TextColor3 = C.TextDim,
					Size = UDim2.new(1, 0, 0, 16),
					Parent = row,
				})
				local bar = UI.progress({ Size = UDim2.new(1, 0, 0, 10), Position = UDim2.fromOffset(0, 20), Color = Theme.rarityColor(rarityId), Parent = row })
				bar.Set(progressValue / threshold, "")
			end
		end

		-- Pool preview
		add(UI.label({ Text = "Possible items", Font = F.Heading, TextSize = 16, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = nextOrder(), Parent = detailScroll }))
		local grid = add(UI.frame({
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = nextOrder(),
			Grid = { Cell = UDim2.fromOffset(52, 52), Pad = UDim2.fromOffset(6, 6) },
			Parent = detailScroll,
		}))
		local discovered = State.get("Discovered") or {}
		local pool = Items.PoolByChest[chest.Id] or {}
		local index = 0
		for _, rarityId in ipairs(Rarities.Order) do
			for _, itemId in ipairs(pool[rarityId] or {}) do
				index += 1
				local item = Items.ById[itemId]
				local known = discovered[itemId] ~= nil
				local tile = UI.label({
					Text = if known then item.Icon else "?",
					TextSize = 26,
					TextColor3 = if known then C.White else C.TextMuted,
					TextXAlignment = Enum.TextXAlignment.Center,
					BackgroundColor3 = if known then Theme.darken(Theme.rarityGlow(rarityId), 0.4) else C.BackgroundAlt,
					BackgroundTransparency = 0,
					LayoutOrder = index,
					Corner = Theme.Radius.Small,
					Stroke = { Color = if known then Theme.rarityColor(rarityId) else C.StrokeSoft, Thickness = 1.5 },
					Parent = grid,
				})
				UI.attachTooltip(tile, function()
					if known then
						return `<b>{item.Icon} {item.Name}</b> ({item.Rarity})\n{Formulas.describeItemBonus(item, 1)}`
					end
					return if rarityId == "Secret" then "A secret item hides in this crate…" else `Undiscovered {rarityId} item`
				end)
			end
		end
	end

	function screen.Refresh()
		if not window.IsOpen() then
			return
		end
		local data = State.view()
		local stats = State.stats()
		local owned = State.get("Chests") or {}
		for chestId, entry in pairs(crateCards) do
			local chest = Chests.ById[chestId]
			local unlocked = Formulas.chestUnlocked(chest, data)
			local price = Formulas.chestPrice(chest, if stats then stats.chestDiscount else 0)
			entry.Sub.Text = if unlocked
				then `{Theme.currencyIcon(chest.Currency)} {Format.short(price)}`
				else `🔒 {GameConfig.Stages[chest.Stage].Name}`
			entry.Card.BackgroundTransparency = if unlocked then 0 else 0.45
			entry.Stroke.Color = if chestId == selected then chest.Color else C.StrokeSoft
			entry.Stroke.Thickness = if chestId == selected then 2.5 else 1.5
			local n = owned[chestId] or 0
			entry.Owned.Visible = n > 0
			entry.Owned.Text = tostring(n)
		end
		buildDetail()
	end

	-- Balance changes constantly while pressing: only update button states for it.
	local function updateAffordability()
		for _, entry in ipairs(buyButtons) do
			UI.setEnabled(entry.Button, State.currency(entry.Currency) >= entry.Cost)
		end
	end
	local pending, pendingCurrency = false, false
	State.subscribe("Currencies", function()
		if pendingCurrency or not window.IsOpen() then
			return
		end
		pendingCurrency = true
		task.delay(0.2, function()
			pendingCurrency = false
			updateAffordability()
		end)
	end)
	State.subscribe({ "Chests", "Pity", "Discovered", "Derived", "Progress" }, function()
		if pending or not window.IsOpen() then
			return
		end
		pending = true
		task.delay(0.25, function()
			pending = false
			screen.Refresh()
		end)
	end)
	window.Opened.Event:Connect(screen.Refresh)

	function screen.OnOpen(chestId: string?)
		if chestId and Chests.ById[chestId] then
			selected = chestId
		end
	end
	return screen
end

return ChestsScreen
