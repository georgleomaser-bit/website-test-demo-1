--[[
	Shop (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Screens/Shop
	Depends on: ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format,Formulas,Config/Upgrades},
	            Client/{State,ClientNet}

	Upgrade shop grouped into tiers. Each card shows the current level, the
	effect now and after buying, and the cost for the selected amount
	(×1, ×10 or MAX). Purchases are sent as intent only; the server computes
	the real price and applies the upgrade.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIFolder = ReplicatedStorage:WaitForChild("UI")
local UI = require(UIFolder.UIKit)
local Theme = require(UIFolder.Theme)
local Effects = require(UIFolder.Effects)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Upgrades = require(Shared.Config.Upgrades)

local Client = script.Parent.Parent
local State = require(Client.State)
local ClientNet = require(Client.ClientNet)

local C = Theme.Colors
local F = Theme.Fonts

local Shop = {}

function Shop.new(ctx)
	local window = UI.window({
		Name = "Shop",
		Title = "Upgrade Shop",
		Subtitle = "Upgrades are paid with Sparks and reset when you ascend.",
		Icon = "🛒",
		Parent = ctx.Layers.Windows,
	})
	local screen: { [string]: any } = { Window = window }
	local body = window.Body
	local amount: any = 1

	local toolbar = UI.frame({ Name = "Toolbar", Size = UDim2.new(1, 0, 0, 40), Parent = body })
	local balance = UI.label({
		Text = "",
		Font = F.Heading,
		TextSize = 18,
		TextColor3 = C.Sparks,
		Size = UDim2.new(0.5, 0, 1, 0),
		Parent = toolbar,
	})
	UI.segmented({
		Options = { { Id = 1, Text = "×1" }, { Id = 10, Text = "×10" }, { Id = "max", Text = "MAX" } },
		Value = 1,
		ButtonWidth = 64,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		OnChange = function(id)
			amount = id
			screen.Refresh()
		end,
		Parent = toolbar,
	})

	local list = UI.scroll({
		Name = "List",
		Size = UDim2.new(1, 0, 1, -50),
		Position = UDim2.fromOffset(0, 50),
		List = { Dir = "Y", Pad = 8 },
		Padding = { 2, 8, 2, 8 },
		Parent = body,
	})

	local headers = {}
	local cards = {}
	local order = 0
	for _, tier in ipairs(Upgrades.Tiers) do
		order += 1
		headers[tier.Tier] = UI.label({
			Name = "Tier" .. tier.Tier,
			Text = tier.Name,
			Font = F.Heading,
			TextSize = 16,
			TextColor3 = C.TextDim,
			Size = UDim2.new(1, 0, 0, 28),
			LayoutOrder = order * 100,
			Parent = list,
		})
		for _, def in ipairs(Upgrades.List) do
			if def.Tier == tier.Tier then
				order += 1
				local card = UI.panel({
					Name = def.Id,
					Size = UDim2.new(1, 0, 0, 88),
					BackgroundColor3 = C.PanelLight,
					LayoutOrder = order * 100,
					Parent = list,
				})
				local cardScale = Instance.new("UIScale")
				cardScale.Parent = card
				UI.label({
					Text = def.Icon,
					TextSize = 32,
					TextXAlignment = Enum.TextXAlignment.Center,
					Size = UDim2.fromOffset(64, 88),
					Parent = card,
				})
				local name = UI.label({
					Text = def.Name,
					Font = F.Heading,
					TextSize = 18,
					Size = UDim2.new(1, -250, 0, 22),
					Position = UDim2.fromOffset(64, 10),
					Parent = card,
				})
				local level = UI.label({
					Text = "",
					Font = F.Bold,
					TextSize = 13,
					TextColor3 = C.TextMuted,
					TextXAlignment = Enum.TextXAlignment.Right,
					Size = UDim2.fromOffset(120, 22),
					Position = UDim2.new(1, -306, 0, 10),
					Parent = card,
				})
				UI.label({
					Text = def.Description,
					TextSize = 13,
					TextColor3 = C.TextDim,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Size = UDim2.new(1, -250, 0, 18),
					Position = UDim2.fromOffset(64, 34),
					Parent = card,
				})
				local effect = UI.label({
					Text = "",
					Font = F.Bold,
					TextSize = 14,
					TextColor3 = C.Accent2,
					RichText = true,
					Size = UDim2.new(1, -250, 0, 20),
					Position = UDim2.fromOffset(64, 56),
					Parent = card,
				})
				local buy = UI.button({
					Text = "",
					Variant = "gold",
					Size = UDim2.fromOffset(160, 52),
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -16, 0.5, 0),
					TextSize = 17,
					Sound = "Purchase",
					OnClick = function(button)
						local result = ClientNet.once("upgrade:" .. def.Id, "BuyUpgrade", { Id = def.Id, Amount = amount })
						if not result then
							return
						end
						if result.ok then
							cardScale.Scale = 1.03
							UI.tween(cardScale, { Scale = 1 }, Theme.Motion.Pop)
							local fx = ctx.Layers.Fx
							local center = button.AbsolutePosition + button.AbsoluteSize / 2 - fx.AbsolutePosition
							Effects.burst(fx, center, C.Gold, 10, 90)
							Effects.floatText(fx, center + Vector2.new(0, -30), `Lv {result.Level}`, C.Gold, { Size = 22, Rise = 50 })
						else
							ctx.Notifications.error(result.err)
						end
					end,
					Parent = card,
				})
				UI.attachTooltip(card, function()
					local data = State.view()
					local lvl = data.Upgrades[def.Id] or 0
					return `<b>{def.Icon} {def.Name}</b>\n{def.Description}\nLevel {lvl}/{def.MaxLevel}\nCost growth ×{def.Growth} per level`
				end)
				cards[def.Id] = { Def = def, Card = card, Level = level, Effect = effect, Buy = buy, Name = name }
			end
		end
	end

	local pending = false
	function screen.Refresh()
		if not window.IsOpen() then
			return
		end
		local data = State.view()
		local sparks = State.currency("Sparks")
		balance.Text = "⚡ " .. Format.short(sparks)
		for tierIndex, header in pairs(headers) do
			local tier = Upgrades.Tiers[tierIndex]
			local unlocked = Formulas.requirementMet(tier.Requirement, data)
			header.Text = if unlocked then tier.Name else `🔒 {tier.Name} — {Formulas.requirementText(tier.Requirement)}`
		end
		for _, entry in pairs(cards) do
			local def = entry.Def
			local lvl = data.Upgrades[def.Id] or 0
			local unlocked = Formulas.upgradeUnlocked(def, data)
			entry.Level.Text = `Lv {lvl} / {def.MaxLevel}`
			entry.Card.BackgroundTransparency = if unlocked then 0 else 0.5
			if lvl >= def.MaxLevel then
				entry.Effect.Text = `Effect: {Format.display(def.Display, def.Value(lvl))}  ·  <font color="#FFCD40">MAXED</font>`
				UI.setText(entry.Buy, "MAX")
				UI.setEnabled(entry.Buy, false)
			else
				local count, cost
				if amount == "max" then
					count, cost = Formulas.maxAffordable(def, lvl, sparks)
					if count == 0 then
						count, cost = 1, Formulas.upgradeLevelCost(def, lvl)
					end
				else
					count = math.min(amount, def.MaxLevel - lvl)
					cost = Formulas.upgradeCost(def, lvl, count)
				end
				local now = Format.display(def.Display, def.Value(lvl))
				local nextValue = Format.display(def.Display, def.Value(lvl + count))
				entry.Effect.Text = `{now}  →  <font color="#4DE1FF"><b>{nextValue}</b></font>`
					.. (if count > 1 then `  <font color="#9A96B8">(+{count} levels)</font>` else "")
				UI.setText(entry.Buy, Format.short(cost), "⚡")
				UI.setEnabled(entry.Buy, unlocked and sparks >= cost)
			end
		end
	end

	local function schedule()
		if pending then
			return
		end
		pending = true
		task.delay(0.1, function()
			pending = false
			screen.Refresh()
		end)
	end
	State.subscribe({ "Currencies", "Upgrades", "Progress" }, schedule)

	window.Opened.Event:Connect(screen.Refresh)
	return screen
end

return Shop
