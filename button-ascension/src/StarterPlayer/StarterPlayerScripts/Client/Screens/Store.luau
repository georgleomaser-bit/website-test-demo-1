--[[
	Store (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Screens/Store
	Depends on: ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format,RobuxSale,
	            Config/GamePasses,Config/DevProducts}, Client/State

	The Robux store: game passes (buy once, keep forever) and developer
	products (Gem packs, a timed Sparks boost, a crate bundle). Buttons only
	open Roblox's purchase prompt; the server grants everything
	(GamePassService / ProductService). Prices come from Roblox
	(GetProductInfo); until they load, the suggested price is shown with "~".

	Items whose Roblox ID is still 0 in the config are hidden in live games and
	shown as "Not set up" in Studio, so the owner can see what is missing.
	Each item is prompted as a game pass or a developer product depending on
	how it is really sold (Shared/RobuxSale); items Roblox reports as not for
	sale say so instead of opening a prompt that would fail.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UIFolder = ReplicatedStorage:WaitForChild("UI")
local UI = require(UIFolder.UIKit)
local Theme = require(UIFolder.Theme)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local GamePasses = require(Shared.Config.GamePasses)
local DevProducts = require(Shared.Config.DevProducts)
local Chests = require(Shared.Config.Chests)
local RobuxSale = require(Shared.RobuxSale)

local Client = script.Parent.Parent
local State = require(Client.State)

local C = Theme.Colors
local F = Theme.Fonts

local CARD = UDim2.fromOffset(272, 194)

local Store = {}

-- "Epic 70% · Legendary 24% · …" for a Robux crate (before Luck).
local function crateOdds(chestId: string): string
	local chest = Chests.RobuxById[chestId]
	if not chest then
		return ""
	end
	local total = 0
	for _, weight in pairs(chest.Weights) do
		total += weight
	end
	local parts = {}
	for _, rarityId in ipairs({ "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }) do
		local weight = chest.Weights[rarityId]
		if weight then
			table.insert(parts, `{rarityId} {Format.pct(weight / total, if weight / total < 0.1 then 1 else 0)}`)
		end
	end
	local variants = ""
	if chest.ForceVariant then
		variants = " Always Rainbow (×6 power)."
	elseif chest.VariantChances then
		variants = ` Golden {Format.pct(chest.VariantChances.golden or 0, 1)} · Rainbow {Format.pct(chest.VariantChances.rainbow or 0, 1)}.`
	end
	return table.concat(parts, " · ") .. "." .. variants .. " Items from crates you have unlocked."
end

function Store.new(ctx)
	local window = UI.window({
		Name = "Store",
		Title = "Store",
		Subtitle = "Game passes and boosts for Robux. Every purchase goes through Roblox.",
		Icon = "💰",
		Parent = ctx.Layers.Windows,
	})
	local screen: { [string]: any } = { Window = window }
	local isStudio = RunService:IsStudio()
	-- Keyed "<kind>:<id>" (the same number can be a pass and an unrelated product).
	local prices: { [string]: number } = {}
	local notForSale: { [string]: boolean } = {}
	local fetching: { [string]: boolean } = {}

	-- Opens Roblox's prompt for however the entry is really sold.
	local function prompt(entry)
		local kind, id = RobuxSale.of(entry)
		if kind == "pass" then
			MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, id)
		elseif kind == "product" then
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, id)
		end
	end

	local list = UI.scroll({
		Name = "List",
		List = { Dir = "Y", Pad = 10 },
		Padding = { 2, 8, 2, 2 },
		Parent = window.Body,
	})

	local function sectionTitle(order: number, text: string, sub: string)
		local frame = UI.frame({ Size = UDim2.new(1, 0, 0, 42), LayoutOrder = order, Parent = list })
		UI.label({ Text = text, Font = F.Heading, TextSize = 18, Size = UDim2.new(1, 0, 0, 22), Parent = frame })
		UI.label({ Text = sub, TextSize = 13, TextColor3 = C.TextDim, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 22), Parent = frame })
	end

	local function grid(order: number): Frame
		return UI.frame({
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			Grid = { Cell = CARD, Pad = UDim2.fromOffset(10, 10) },
			Parent = list,
		})
	end

	local function emptyLabel(order: number, text: string): TextLabel
		return UI.label({
			Text = text,
			TextColor3 = C.TextMuted,
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = order,
			Visible = false,
			Parent = list,
		})
	end

	local function card(parent: Frame, order: number, spec): { [string]: any }
		local panel = UI.panel({
			Name = spec.Key,
			BackgroundColor3 = C.PanelLight,
			LayoutOrder = order,
			Padding = 12,
			Parent = parent,
		})
		local stroke = UI.stroke(panel, { Color = spec.Color, Thickness = 1.5, Transparency = 0.2 })
		UI.label({ Text = spec.Icon, TextSize = 34, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(44, 44), Parent = panel })
		UI.label({
			Text = spec.Name,
			Font = F.Heading,
			TextSize = 17,
			TextColor3 = spec.Color,
			Size = UDim2.new(1, -96, 0, 22),
			Position = UDim2.fromOffset(52, 0),
			Parent = panel,
		})
		if spec.Op then
			UI.label({
				Text = "OP",
				Font = F.Heading,
				TextSize = 12,
				TextColor3 = C.White,
				TextXAlignment = Enum.TextXAlignment.Center,
				BackgroundColor3 = C.Accent,
				BackgroundTransparency = 0,
				Corner = Theme.Radius.Pill,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 2),
				Size = UDim2.fromOffset(34, 18),
				Parent = panel,
			})
		end
		local effect = UI.label({
			Text = spec.Effect,
			Font = F.Bold,
			TextSize = 13,
			TextColor3 = C.Accent2,
			TextWrapped = true,
			Size = UDim2.new(1, -52, 0, 20),
			Position = UDim2.fromOffset(52, 22),
			Parent = panel,
		})
		local note = UI.label({
			Text = spec.Description,
			TextSize = 12,
			TextColor3 = C.TextDim,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, 0, 0, 62),
			Position = UDim2.fromOffset(0, 50),
			Parent = panel,
		})
		local button = UI.button({
			Name = "Buy",
			Text = "",
			Variant = "gold",
			TextSize = 14,
			Size = UDim2.new(1, 0, 0, 34),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			OnClick = spec.OnBuy,
			Parent = panel,
		})
		return { Panel = panel, Stroke = stroke, Button = button, Effect = effect, Note = note }
	end

	local function saleKey(entry): string?
		local kind, id = RobuxSale.of(entry)
		return if kind then `{kind}:{id}` else nil
	end

	local function priceText(entry, suggested: number): string
		local key = saleKey(entry)
		local price = key and prices[key]
		return if price then `R$ {Format.commas(price)}` else `~R$ {Format.commas(suggested)}`
	end

	local function isNotForSale(entry): boolean
		local key = saleKey(entry)
		return key ~= nil and notForSale[key] == true
	end

	-- Asks Roblox for real prices once per item (failures keep the suggested price).
	local function fetchPrices()
		local function fetch(entry)
			local kind, id = RobuxSale.of(entry)
			local key = saleKey(entry)
			if not kind or not key or prices[key] or fetching[key] then
				return
			end
			fetching[key] = true
			local infoType = if kind == "pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
			task.spawn(function()
				local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, infoType)
				if ok and type(info) == "table" then
					if type(info.PriceInRobux) == "number" and info.PriceInRobux > 0 then
						prices[key] = info.PriceInRobux
					end
					notForSale[key] = info.IsForSale == false
					screen.Refresh()
				else
					-- Try again next time the store opens.
					fetching[key] = nil
				end
			end)
		end
		for _, pass in ipairs(GamePasses.List) do
			fetch(pass)
		end
		for _, product in ipairs(DevProducts.List) do
			fetch(product)
		end
	end

	local function productNote(product): string
		local kind = RobuxSale.of(product)
		if kind == "pass" then
			return "One-time purchase: each player can buy this once."
		elseif product.Crate then
			return crateOdds(product.Crate)
		elseif product.Boost then
			return `Stacks: every purchase adds {math.floor(product.Boost.Seconds / 60)} more minutes of play.`
		elseif product.Crates and not product.Gems and not product.Sparks then
			return "Picks the most valuable Spark crate your stage has unlocked."
		elseif product.Sparks and not product.Gems then
			return "Spend them on upgrades and crates."
		end
		return "Gems buy Prism Caches and skill respecs."
	end

	-- Game passes ------------------------------------------------------------------------------
	sectionTitle(1, "🎟️ Game Passes", "Buy once, keep forever. Stack them for even more power.")
	local passGrid = grid(2)
	local passEmpty = emptyLabel(3, "No passes available yet.")
	local passCards = {}
	for index, pass in ipairs(GamePasses.List) do
		passCards[pass.Key] = card(passGrid, index, {
			Key = pass.Key,
			Name = pass.Name,
			Icon = pass.Icon,
			Color = pass.Color,
			Op = pass.Op,
			Effect = pass.EffectText,
			Description = pass.Description,
			OnBuy = function()
				if GamePasses.isConfigured(pass) and not GamePasses.owns(State.get("Passes"), pass.Key) and not isNotForSale(pass) then
					prompt(pass)
				end
			end,
		})
	end

	-- Developer products -------------------------------------------------------------------------
	sectionTitle(4, "⚡ Sparks, Gems & Boosts", "Boost time only runs while you play.")
	local productGrid = grid(5)
	local productEmpty = emptyLabel(6, "No products available yet.")
	local productCards = {}
	for index, product in ipairs(DevProducts.List) do
		productCards[product.Key] = card(productGrid, index, {
			Key = product.Key,
			Name = product.Name,
			Icon = product.Icon,
			Color = product.Color,
			Effect = product.Description,
			Op = product.Op,
			Description = productNote(product),
			OnBuy = function()
				local owned = (State.get("PassRewards") or {})[product.Key] == true and RobuxSale.of(product) == "pass"
				if DevProducts.isConfigured(product) and not owned and not isNotForSale(product) then
					prompt(product)
				end
			end,
		})
	end

	UI.label({
		Text = "Purchases are processed by Roblox. Passes are re-checked by the server every time you join.",
		TextSize = 12,
		TextColor3 = C.TextMuted,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 32),
		LayoutOrder = 7,
		Parent = list,
	})

	function screen.Refresh()
		if not window.IsOpen() then
			return
		end
		local owned = State.get("Passes")
		local shownPasses = 0
		for _, pass in ipairs(GamePasses.List) do
			local entry = passCards[pass.Key]
			local configured = GamePasses.isConfigured(pass)
			entry.Panel.Visible = configured or isStudio
			if entry.Panel.Visible then
				shownPasses += 1
			end
			if GamePasses.owns(owned, pass.Key) then
				UI.setText(entry.Button, "✓ Owned")
				UI.setVariant(entry.Button, "success")
				UI.setEnabled(entry.Button, false)
				entry.Stroke.Thickness = 3
				entry.Stroke.Color = C.Gold
			elseif not configured then
				UI.setText(entry.Button, "Not set up (GamePassId missing)")
				UI.setVariant(entry.Button, "ghost")
				UI.setEnabled(entry.Button, false)
			elseif isNotForSale(pass) then
				UI.setText(entry.Button, "Not for sale yet")
				UI.setVariant(entry.Button, "ghost")
				UI.setEnabled(entry.Button, false)
			else
				UI.setText(entry.Button, `Buy · {priceText(pass, pass.SuggestedPrice)}`)
				UI.setVariant(entry.Button, "gold")
				UI.setEnabled(entry.Button, true)
			end
		end
		passEmpty.Visible = shownPasses == 0

		local derived = State.get("Derived")
		local now = workspace:GetServerTimeNow()
		local shownProducts = 0
		for _, product in ipairs(DevProducts.List) do
			local entry = productCards[product.Key]
			local configured = DevProducts.isConfigured(product)
			entry.Panel.Visible = configured or isStudio
			if entry.Panel.Visible then
				shownProducts += 1
			end
			local endsAt = derived and derived.BoostEndsAt and derived.BoostEndsAt[product.Key]
			entry.Effect.Text = if type(endsAt) == "number" and endsAt > now
				then `{product.Description} · active {Format.clock(endsAt - now)}`
				else product.Description
			entry.Note.Text = productNote(product)
			local rewarded = (State.get("PassRewards") or {})[product.Key] == true and RobuxSale.of(product) == "pass"
			if rewarded then
				UI.setText(entry.Button, "✓ Owned")
				UI.setVariant(entry.Button, "success")
				UI.setEnabled(entry.Button, false)
			elseif configured and isNotForSale(product) then
				UI.setText(entry.Button, "Not for sale yet")
				UI.setVariant(entry.Button, "ghost")
				UI.setEnabled(entry.Button, false)
			elseif configured then
				UI.setText(entry.Button, `Buy · {priceText(product, product.SuggestedPrice)}`)
				UI.setVariant(entry.Button, "gold")
				UI.setEnabled(entry.Button, true)
			else
				UI.setText(entry.Button, "Not set up (ProductId missing)")
				UI.setVariant(entry.Button, "ghost")
				UI.setEnabled(entry.Button, false)
			end
		end
		productEmpty.Visible = shownProducts == 0
	end

	State.subscribe({ "Passes", "Boosts", "PassRewards", "Derived" }, screen.Refresh)
	local openCount = 0
	window.Opened.Event:Connect(function()
		openCount += 1
		local thisOpen = openCount
		fetchPrices()
		screen.Refresh()
		-- Keep boost timers ticking while the store is open (one loop per opening).
		task.spawn(function()
			while window.IsOpen() and thisOpen == openCount do
				task.wait(1)
				screen.Refresh()
			end
		end)
	end)
	return screen
end

return Store
