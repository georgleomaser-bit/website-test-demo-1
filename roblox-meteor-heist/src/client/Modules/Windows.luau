-- =====================================================================
--  FENSTER: Shop (Reiter Gamepässe / Boosts / Gadgets), Laufbänder, Rebirth, Tagesbonus, Alien-Index
--  Jedes Fenster wird EINMAL gebaut; Refresh(state) schreibt nur die Werte neu.
--  Andere Module (z.B. Rewards) melden ihre Fenster mit Windows.Register an.
-- =====================================================================

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent:WaitForChild("UI"))

local Windows = {}

local player = Players.LocalPlayer
local ctx: any = nil
local Theme = UI.Theme

local TAB_POP_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local list: { [string]: UI.Window } = {}
local refreshers: { [string]: (state: any) -> () } = {}

local GRAY = Theme.Gray
local TIER_COLORS: { [string]: Color3 } = {
	Normal = Color3.fromRGB(235, 235, 235),
	Selten = Color3.fromRGB(80, 200, 255),
	Ultra = Color3.fromRGB(255, 80, 230),
}

-- "👟 2x Schritte" + Icon "👟" -> nicht doppelt anzeigen
local function displayName(item: any): string
	local name = tostring(item.Name or item.Key or "?")
	local icon = item.Icon
	if type(icon) == "string" and icon ~= "" and not name:find(icon, 1, true) then
		return icon .. " " .. name
	end
	return name
end

local function percentText(value: number): string
	if math.abs(value - math.floor(value + 0.5)) < 0.05 then
		return tostring(math.floor(value + 0.5))
	end
	return string.format("%.1f", value)
end

-- Alle kaufbaren (spawnbaren) Meteore einer Seltenheit
local function meteorsOfRarity(rarityName: string): { any }
	local result = {}
	for _, def in ipairs(ctx.Config.Meteors) do
		if def.Rarity == rarityName and def.Spawnable ~= false then
			table.insert(result, def)
		end
	end
	return result
end

-- Gehört dir das Laufband? (State.Treadmills = Liste gekaufter Ids, gratis = immer)
local function ownsTreadmill(state: any, def: any): boolean
	if (tonumber(def.Price) or 0) <= 0 then
		return true
	end
	local owned = state and state.Treadmills
	return type(owned) == "table" and table.find(owned, def.Id) ~= nil
end

-- Bestes gekauftes Laufband (für Schritte-Paket-Anzeige)
local function bestTreadmill(state: any): any
	local best = nil
	local treadmills = ctx.Config.Treadmills
	if type(treadmills) == "table" then
		for _, def in ipairs(treadmills) do
			if ownsTreadmill(state, def) then
				best = def
			end
		end
	end
	return best
end

-- ---------------------------------------------------------------------
-- SHOP (Reiter: ⭐ Gamepässe / 💎 Boosts / 🛠️ Gadgets)
-- ---------------------------------------------------------------------
type PassCard = { Pass: any, Button: UI.Button, Price: number? }
type ProductCard = { Product: any, Info: TextLabel?, Button: UI.Button, Price: number? }
type GadgetCard = { Gadget: any, Button: UI.Button, Stroke: UIStroke, Card: Frame }

local passCards: { PassCard } = {}
local productCards: { ProductCard } = {}
local gadgetCards: { GadgetCard } = {}
local shopPages: { [string]: Frame } = {}
local shopTabButtons: { [string]: UI.Button } = {}
local shopTab = "Passes"

local SHOP_TABS = {
	{ Id = "Passes", Text = "⭐ Gamepässe", Color = Theme.Gold },
	{ Id = "Boosts", Text = "💎 Boosts", Color = Theme.Blue },
	{ Id = "Gadgets", Text = "🛠️ Gadgets", Color = Theme.Orange },
}

-- Starter-Paket: Werte aus Config.StarterPack (der MonetizationService liest dieselben).
-- Wo Zufalls-Käufe verboten sind, gibt es statt Drehs + Zufalls-Ei mehr Cash + ein festes Ei.
local function starterValues(): (number, number, number, number, string, string)
	local starter = ctx.Config.StarterPack or {}
	return tonumber(starter.MinCash) or 100000,
		tonumber(starter.IncomeSeconds) or 900,
		tonumber(starter.Spins) or 3,
		tonumber(starter.RestrictedCashMult) or 1.5,
		tostring(starter.EggRarity or "Legendary"),
		tostring(starter.Gadget or "SpeedCoil")
end

-- Zufalls-Käufe (Chancen werden angezeigt, nur wo erlaubt)
local function isRandomProduct(product: any): boolean
	return product.Type == "Meteor" or product.Type == "Spins"
end

local function hatchOddsText(meteorId: string): string
	local Aliens = ctx.Aliens
	local options = Aliens.ByMeteor[meteorId]
	if type(options) ~= "table" or #options == 0 then
		return ""
	end
	local total = 0
	for _, option in ipairs(options) do
		total += option.Weight
	end
	local parts = {}
	for _, option in ipairs(options) do
		local def = Aliens.ById[option.Id]
		local pct = if total > 0 then option.Weight / total * 100 else 0
		table.insert(parts, percentText(pct) .. "% " .. (def and def.Tier or "?"))
	end
	return "🐣 Schlüpft: " .. table.concat(parts, " • ") .. " (Glück & 🍀-Pass: besser)"
end

-- "Je 33%: Solar Flare, Aurora Crystal, Titan Boulder"
local function meteorOddsShort(rarityName: string): string
	local defs = meteorsOfRarity(rarityName)
	if #defs == 0 then
		return ""
	end
	local names = {}
	for _, def in ipairs(defs) do
		table.insert(names, def.Name)
	end
	return ("Je %s%%: %s"):format(percentText(100 / #defs), table.concat(names, ", "))
end

-- Roblox-Regel "Paid Random Items": Chancen VOR dem Kauf anzeigen
local function oddsText(rarityName: string): string
	local defs = meteorsOfRarity(rarityName)
	if #defs == 0 then
		return ""
	end
	return "🎲 " .. meteorOddsShort(rarityName) .. "\n" .. hatchOddsText(defs[1].Id)
end

-- Glücksrad-Chancen kurz: "🎲 💵26% 👟18% ..."
local function wheelOddsShort(): string
	local prizes = ctx.Config.WheelPrizes
	if type(prizes) ~= "table" or #prizes == 0 then
		return ""
	end
	local total = 0
	for _, prize in ipairs(prizes) do
		total += math.max(0, tonumber(prize.Weight) or 0)
	end
	local parts = {}
	for _, prize in ipairs(prizes) do
		local pct = if total > 0 then math.max(0, tonumber(prize.Weight) or 0) / total * 100 else 0
		table.insert(parts, tostring(prize.Icon or "?") .. percentText(pct) .. "%")
	end
	return "🎲 Chancen: " .. table.concat(parts, " ")
end

local function productInfoText(product: any, state: any): string
	local Util = ctx.Util
	local kind = product.Type
	local income = state and tonumber(state.Income) or 0
	if kind == "Cash" then
		local amount = math.max(tonumber(product.Min) or 0, income * 60 * (tonumber(product.Minutes) or 0))
		return ("%s Min. Einkommen  ≈ %s"):format(tostring(product.Minutes or 0), Util.FormatCash(amount))
	elseif kind == "Steps" then
		local mult = state and tonumber(state.StepsMult) or 1
		local best = bestTreadmill(state)
		local rate = best and tonumber(best.Rate) or 1
		local minutes = tonumber(product.Minutes) or 10
		local amount = math.max(tonumber(product.Min) or 0, rate * 2 * 60 * minutes * mult)
		return ("%s Min. bestes Laufband  ≈ +%s 👟"):format(tostring(minutes), Util.FormatNumber(amount))
	elseif kind == "ServerLuck" then
		return ("🍀 %sx Glück für ALLE, %s Min."):format(
			tostring(product.Mult or 2),
			tostring(product.Minutes or 15)
		)
	elseif kind == "Shower" then
		return "🌠 Sofort für alle: zwei Spuren voller Meteore, 3x Glück, keine Locks!"
	elseif kind == "Meteor" then
		return oddsText(product.Rarity)
	elseif kind == "StarterPack" then
		local minCash, incomeSeconds, spins, restrictedMult, eggRarity, gadgetId = starterValues()
		local cash = math.max(minCash, income * incomeSeconds)
		local coil = ctx.Config.GadgetsById and ctx.Config.GadgetsById[gadgetId]
		local coilText = if coil then (tostring(coil.Icon) .. " " .. tostring(coil.Name)) else "🌀 Speed Coil"
		if UI.RandomItemsAllowed() == true then
			return ("NUR 1x: 💰 ≈%s + 🎡 %d Drehs + 🌟 %s-Ei + %s\n🎲 Ei: %s"):format(
				Util.FormatCash(cash),
				spins,
				eggRarity,
				coilText,
				meteorOddsShort(eggRarity)
			)
		end
		local eggs = ctx.Config.MeteorsByRarity and ctx.Config.MeteorsByRarity[eggRarity]
		local egg = eggs and eggs[1]
		return ("NUR 1x: 💰 ≈%s + 🌟 %s + %s"):format(
			Util.FormatCash(cash * restrictedMult),
			if egg then tostring(egg.Name) else eggRarity .. "-Ei",
			coilText
		)
	elseif kind == "Spins" then
		local amount = math.max(1, math.floor(tonumber(product.Amount) or 1))
		return ("🎡 +%d %s fürs Glücksrad\n%s"):format(
			amount,
			if amount == 1 then "Dreh" else "Drehs",
			wheelOddsShort()
		)
	elseif kind == "InstantHatch" then
		return "🐣 Alle Eier in deiner Base schlüpfen SOFORT!"
	elseif kind == "Shield" then
		return ("🛡️ %s Min. kann niemand bei dir klauen – sogar im Schauer!"):format(
			tostring(product.Minutes or 10)
		)
	elseif kind == "EggRush" then
		return ("🥚 %s Gratis-Eier regnen für ALLE auf die Map!"):format(tostring(ctx.Config.EggRushCount or 25))
	end
	return ""
end

local function ownsGadget(state: any, id: string): boolean
	local owned = state and state.Gadgets
	return type(owned) == "table" and table.find(owned, id) ~= nil
end

-- ⭐ STARTER-PAKET: nur einmal! Ein Developer Product kann der Server nicht auf einen Kauf begrenzen
-- (bezahlt ist bezahlt, er muss liefern). Deshalb bleibt der Kauf-Knopf nach dem Klick gesperrt,
-- bis Roblox "abgebrochen" meldet oder der Server "gekauft" (State StarterBought).
local STARTER_LOCK_SAFETY = 30 -- Sekunden: spätestens dann ist der Knopf wieder frei (z.B. ohne Antwort)
local starterPendingUntil = 0

function Windows.StarterPending(): boolean
	return os.clock() < starterPendingUntil
end

function Windows.BuyStarter()
	local product = ctx.Config.ProductsByKey and ctx.Config.ProductsByKey.StarterPack
	local state = ctx.State
	if not product or product.Id == 0 or (state and state.StarterBought == true) or Windows.StarterPending() then
		return
	end
	starterPendingUntil = os.clock() + STARTER_LOCK_SAFETY
	Windows.RefreshShop(state)
	ctx.Hud.Refresh(state)
	MarketplaceService:PromptProductPurchase(player, product.Id)
end

function Windows.RefreshShop(state: any)
	for _, entry in ipairs(passCards) do
		local pass = entry.Pass
		local owned = state and state.Passes and state.Passes[pass.Key] == true
		if owned then
			entry.Button.SetText("✅ Besitzt du")
			entry.Button.SetColor(GRAY)
		elseif pass.Id == 0 then
			entry.Button.SetText("Bald verfügbar")
			entry.Button.SetColor(GRAY)
		else
			entry.Button.SetText(if entry.Price then ("R$ " .. entry.Price) else "Kaufen")
			entry.Button.SetColor(Theme.Green)
		end
	end
	for _, entry in ipairs(productCards) do
		local product = entry.Product
		if entry.Info then
			local text = productInfoText(product, state)
			if entry.Info.Text ~= text then
				entry.Info.Text = text
			end
		end
		if product.Id == 0 then
			entry.Button.SetText("Bald verfügbar")
			entry.Button.SetColor(GRAY)
		elseif product.Type == "StarterPack" and state and state.StarterBought == true then
			entry.Button.SetText("✅ Gekauft")
			entry.Button.SetColor(GRAY)
		elseif product.Type == "StarterPack" and Windows.StarterPending() then
			entry.Button.SetText("⏳ Kauf läuft...")
			entry.Button.SetColor(GRAY)
		else
			entry.Button.SetText(if entry.Price then ("R$ " .. entry.Price) else "Kaufen")
			entry.Button.SetColor(if product.Type == "StarterPack" then Theme.Gold else Theme.Blue)
		end
	end
	local cash = state and tonumber(state.Cash) or 0
	for _, entry in ipairs(gadgetCards) do
		local gadget = entry.Gadget
		local price = tonumber(gadget.Price) or 0
		local owned = ownsGadget(state, gadget.Id)
		if owned then
			entry.Button.SetText("✅ Besitzt du")
			entry.Button.SetColor(GRAY)
		else
			entry.Button.SetText("💵 " .. ctx.Util.FormatCash(price))
			entry.Button.SetColor(if cash >= price then Theme.Green else GRAY)
		end
		local strokeColor = if owned then Theme.Gold else Color3.new(0, 0, 0)
		if entry.Stroke.Color ~= strokeColor then
			entry.Stroke.Color = strokeColor
			entry.Stroke.Thickness = if owned then 4 else 2
		end
	end
end

local function selectShopTab(id: string)
	if not shopPages[id] then
		id = "Passes"
	end
	local changed = shopTab ~= id
	shopTab = id
	for pageId, page in pairs(shopPages) do
		page.Visible = pageId == id
		-- neuer Reiter: Inhalt ploppt kurz auf (federnd)
		local scale = page:FindFirstChildOfClass("UIScale")
		if changed and pageId == id and scale then
			scale.Scale = 0.94
			TweenService:Create(scale, TAB_POP_INFO, { Scale = 1 }):Play()
		end
	end
	for _, tab in ipairs(SHOP_TABS) do
		local button = shopTabButtons[tab.Id]
		if button then
			button.SetColor(if tab.Id == id then tab.Color else GRAY)
		end
	end
	local win = list.Shop
	if win then
		win.Content.CanvasPosition = Vector2.zero
	end
end

local function newShopPage(id: string, order: number, parent: Instance): Frame
	local page = UI.Create("Frame", {
		Name = id,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Visible = false,
		Parent = parent,
	}, {
		UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
		UI.Create("UIScale", { Scale = 1 }),
	})
	shopPages[id] = page
	return page
end

local function buildPassPage(page: Frame)
	UI.Section(page, "⭐ Gamepässe (gehören dir für immer)", 1)
	local passGrid = UI.Grid(page, 2, 280, 136)
	for i, pass in ipairs(ctx.Config.GamePasses) do
		local card = UI.Card({ LayoutOrder = i, Parent = passGrid })
		UI.Label({
			Position = UDim2.fromOffset(10, 6),
			Size = UDim2.new(1, -20, 0, 30),
			Text = displayName(pass),
			MaxText = 22,
			Outline = 2,
			Parent = card,
		})
		UI.Label({
			Position = UDim2.fromOffset(10, 38),
			Size = UDim2.new(1, -20, 0, 40),
			Text = tostring(pass.Description or ""),
			Font = Enum.Font.GothamBold,
			TextColor3 = Theme.SubText,
			TextWrapped = true,
			MaxText = 14,
			Parent = card,
		})
		local buy = UI.Button({
			Position = UDim2.new(0, 10, 1, -48),
			Size = UDim2.new(1, -20, 0, 38),
			Text = "...",
			Color = Theme.Green,
			MaxText = 20,
			Parent = card,
		}, function()
			local state = ctx.State
			if pass.Id ~= 0 and not (state and state.Passes and state.Passes[pass.Key]) then
				MarketplaceService:PromptGamePassPurchase(player, pass.Id)
			end
		end)
		local entry: PassCard = { Pass = pass, Button = buy, Price = nil }
		table.insert(passCards, entry)
		UI.FetchPrice(pass.Id, Enum.InfoType.GamePass, function(price)
			entry.Price = price
			Windows.RefreshShop(ctx.State)
		end)
	end
end

local function buildBoostPage(page: Frame)
	UI.Section(page, "💎 Boosts & Pakete", 1)
	local productGrid = UI.Grid(page, 2, 280, 156)
	local randomCards: { Frame } = {}
	for i, product in ipairs(ctx.Config.Products) do
		local isRandom = isRandomProduct(product)
		local starter = product.Type == "StarterPack"
		local card = UI.Card({
			-- Starter-Paket ganz vorne
			LayoutOrder = if starter then 0 else i,
			Visible = not isRandom, -- erst zeigen, wenn die Länder-Regel geprüft ist
			Parent = productGrid,
		})
		if starter then
			local stroke = card:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = Theme.Gold
				stroke.Thickness = 4
			end
		end
		UI.Label({
			Position = UDim2.fromOffset(10, 6),
			Size = UDim2.new(1, -20, 0, 30),
			Text = displayName(product),
			TextWrapped = true,
			MaxText = 19,
			Outline = 2,
			Parent = card,
		})
		local info = UI.Label({
			Position = UDim2.fromOffset(10, 38),
			Size = UDim2.new(1, -20, 0, 62),
			Text = productInfoText(product, nil),
			Font = Enum.Font.GothamBold,
			TextColor3 = Theme.SubText,
			TextWrapped = true,
			MaxText = if isRandom or starter then 12 else 14,
			Parent = card,
		})
		if isRandom then
			table.insert(randomCards, card)
		end
		local buy = UI.Button({
			Position = UDim2.new(0, 10, 1, -46),
			Size = UDim2.new(1, -20, 0, 36),
			Text = "...",
			Color = if starter then Theme.Gold else Theme.Blue,
			MaxText = 20,
			Parent = card,
		}, function()
			if starter then
				Windows.BuyStarter() -- nur einmal kaufbar (mit Sperre gegen Doppelkauf)
				return
			end
			if product.Id ~= 0 then
				MarketplaceService:PromptProductPurchase(player, product.Id)
			end
		end)
		local entry: ProductCard = { Product = product, Info = info, Button = buy, Price = nil }
		table.insert(productCards, entry)
		UI.FetchPrice(product.Id, Enum.InfoType.Product, function(price)
			entry.Price = price
			Windows.RefreshShop(ctx.State)
		end)
	end
	-- Zufalls-Käufe nur zeigen, wo sie erlaubt sind (im Zweifel/bei Fehler: nicht zeigen)
	UI.WhenRandomItemsKnown(function(allowed)
		for _, card in ipairs(randomCards) do
			card.Visible = allowed
		end
		Windows.RefreshShop(ctx.State) -- Starter-Paket-Text hängt davon ab
	end)
end

local function buildGadgetPage(page: Frame)
	UI.Section(page, "🛠️ Gadgets – mit 💵 Cash, gehören dir für immer!", 1)
	UI.Label({
		Size = UDim2.new(1, 0, 0, 36),
		Text = "Liegen nach jedem Spawn in deinem Rucksack – auch nach Rebirth. Super-Bonk macht deinen Schläger stärker.",
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.SubText,
		TextWrapped = true,
		LayoutOrder = 2,
		MaxText = 14,
		Parent = page,
	})
	local grid = UI.Grid(page, 3, 280, 176)
	local gadgets = ctx.Config.Gadgets
	if type(gadgets) ~= "table" then
		gadgets = {}
	end
	for i, gadget in ipairs(gadgets) do
		local card = UI.Card({ LayoutOrder = i, Parent = grid })
		local stroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
		UI.Label({
			Position = UDim2.fromOffset(10, 6),
			Size = UDim2.new(1, -20, 0, 32),
			Text = displayName(gadget),
			MaxText = 22,
			Outline = 2,
			Parent = card,
		})
		UI.Label({
			Position = UDim2.fromOffset(10, 40),
			Size = UDim2.new(1, -20, 0, 76),
			Text = tostring(gadget.Description or ""),
			Font = Enum.Font.GothamBold,
			TextColor3 = Theme.SubText,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			MaxText = 14,
			Parent = card,
		})
		local button = UI.Button({
			Position = UDim2.new(0, 10, 1, -48),
			Size = UDim2.new(1, -20, 0, 38),
			Text = "...",
			Color = Theme.Green,
			MaxText = 20,
			Parent = card,
		}, function()
			if ownsGadget(ctx.State, gadget.Id) then
				return
			end
			ctx.Request("BuyGadget", gadget.Id)
		end)
		table.insert(gadgetCards, { Gadget = gadget, Button = button, Stroke = stroke, Card = card })
	end
end

local function buildShop()
	local win = UI.Window("🛒 SHOP", 620, 560, Theme.Red)
	list.Shop = win
	-- Reiter fest über dem Inhalt (scrollen nicht mit weg)
	local tabBar = UI.Create("Frame", {
		Name = "Tabs",
		Position = UDim2.fromOffset(12, 68),
		Size = UDim2.new(1, -24, 0, 46),
		BackgroundTransparency = 1,
		Parent = win.Panel,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
	})
	win.Content.Position = UDim2.fromOffset(12, 122)
	win.Content.Size = UDim2.new(1, -24, 1, -134)
	for i, tab in ipairs(SHOP_TABS) do
		shopTabButtons[tab.Id] = UI.Button({
			Size = UDim2.new(1 / #SHOP_TABS, -4, 1, 0),
			Text = tab.Text,
			Color = GRAY,
			LayoutOrder = i,
			MaxText = 20,
			Parent = tabBar,
		}, function()
			selectShopTab(tab.Id)
		end)
	end
	buildPassPage(newShopPage("Passes", 1, win.Content))
	buildBoostPage(newShopPage("Boosts", 2, win.Content))
	buildGadgetPage(newShopPage("Gadgets", 3, win.Content))
	selectShopTab(shopTab)
end

-- ---------------------------------------------------------------------
-- LAUFBÄNDER
-- ---------------------------------------------------------------------
type TreadmillRow = {
	Def: any,
	Card: Frame,
	Stroke: UIStroke,
	Rate: TextLabel,
	Buy: UI.Button,
}

local treadmillRows: { TreadmillRow } = {}
local treadmillInfo: TextLabel
local treadmillSpeed: TextLabel
local treadmillBar: UI.Bar
local bootsButton: UI.Button? = nil

local function rainbowGradient(): UIGradient
	local keys = {}
	for i = 0, 6 do
		table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 0.85, 1)))
	end
	return UI.Create("UIGradient", { Rotation = 45, Color = ColorSequence.new(keys) })
end

local function buildTreadmills()
	local win = UI.Window("🏃 LAUFBÄNDER", 580, 540, Theme.Blue)
	list.Treadmills = win
	local content = win.Content

	treadmillInfo = UI.Label({
		Size = UDim2.new(1, 0, 0, 34),
		Text = "👟 0 Schritte  •  🏃 Tempo 16",
		TextColor3 = Theme.Yellow,
		LayoutOrder = 1,
		MaxText = 26,
		Outline = 2,
		Parent = content,
	})
	treadmillSpeed = UI.Label({
		Size = UDim2.new(1, 0, 0, 22),
		Text = "",
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.SubText,
		LayoutOrder = 2,
		MaxText = 16,
		Parent = content,
	})
	treadmillBar = UI.Bar({ LayoutOrder = 3, Color = Theme.Cyan, MaxText = 16, Parent = content })
	UI.Button({
		Size = UDim2.new(1, 0, 0, 54),
		Text = "🏃 Zu den Laufbändern!",
		Color = Theme.Green,
		LayoutOrder = 4,
		MaxText = 26,
		Parent = content,
	}, function()
		if ctx.Request("Treadmills") then
			UI.CloseWindow(win)
		end
	end)
	UI.Label({
		Size = UDim2.new(1, 0, 0, 36),
		Text = "Laufband kaufen, drauf laufen = Schritte sammeln = schneller rennen! Bessere Laufbänder geben viel mehr Schritte.",
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.SubText,
		TextWrapped = true,
		LayoutOrder = 5,
		MaxText = 14,
		Parent = content,
	})

	local defs = ctx.Config.Treadmills
	if type(defs) ~= "table" then
		defs = {}
	end
	for i, def in ipairs(defs) do
		local color: Color3 = if typeof(def.Color) == "Color3" then def.Color else Theme.Gray
		local card = UI.Card({ Size = UDim2.new(1, 0, 0, 66), LayoutOrder = 10 + i, Parent = content })
		local stroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
		local swatch = UI.Create("Frame", {
			Position = UDim2.fromOffset(10, 9),
			Size = UDim2.fromOffset(48, 48),
			BackgroundColor3 = if def.Id == "Regenbogen" then Color3.new(1, 1, 1) else color,
			Parent = card,
		}, { UI.Corner(10), UI.Stroke(Color3.new(0, 0, 0), 3) })
		if def.Id == "Regenbogen" or def.Rainbow == true then
			rainbowGradient().Parent = swatch
		end
		UI.Label({
			Position = UDim2.fromOffset(70, 6),
			Size = UDim2.new(1, -230, 0, 30),
			Text = tostring(def.Name or def.Id),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.45),
			MaxText = 22,
			Outline = 2,
			Parent = card,
		})
		local rate = UI.Label({
			Position = UDim2.fromOffset(70, 36),
			Size = UDim2.new(1, -230, 0, 22),
			Text = "",
			Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.Yellow,
			MaxText = 15,
			Parent = card,
		})
		local buy = UI.Button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(150, 44),
			Text = "...",
			Color = GRAY,
			MaxText = 18,
			Parent = card,
		}, function()
			if not ownsTreadmill(ctx.State, def) then
				ctx.Request("BuyTreadmill", def.Id)
			end
		end)
		table.insert(treadmillRows, { Def = def, Card = card, Stroke = stroke, Rate = rate, Buy = buy })
	end

	UI.Section(content, "💎 Schneller farmen", 100)
	local robuxRow = UI.Row(content, 101, 50)
	local boots = ctx.Config.GamePassesByKey and ctx.Config.GamePassesByKey.SpeedBoots
	local stepsProduct = ctx.Config.ProductsByKey and ctx.Config.ProductsByKey.Speed10
	if boots then
		local b = UI.Button({
			Size = UDim2.new(0.5, -3, 1, 0),
			Text = displayName(boots),
			Color = Theme.Purple,
			LayoutOrder = 1,
			MaxText = 18,
			Parent = robuxRow,
		}, function()
			if boots.Id ~= 0 then
				MarketplaceService:PromptGamePassPurchase(player, boots.Id)
			end
		end)
		bootsButton = b
		UI.FetchPrice(boots.Id, Enum.InfoType.GamePass, function(price)
			if boots.Id == 0 then
				b.SetText(displayName(boots) .. " (bald)")
				b.SetColor(GRAY)
			elseif price then
				b.SetText(displayName(boots) .. "  R$ " .. price)
			end
		end)
	end
	if stepsProduct then
		local b = UI.Button({
			Size = UDim2.new(0.5, -3, 1, 0),
			Text = displayName(stepsProduct),
			Color = Theme.Blue,
			LayoutOrder = 2,
			MaxText = 18,
			Parent = robuxRow,
		}, function()
			if stepsProduct.Id ~= 0 then
				MarketplaceService:PromptProductPurchase(player, stepsProduct.Id)
			end
		end)
		UI.FetchPrice(stepsProduct.Id, Enum.InfoType.Product, function(price)
			if stepsProduct.Id == 0 then
				b.SetText(displayName(stepsProduct) .. " (bald)")
				b.SetColor(GRAY)
			elseif price then
				b.SetText(displayName(stepsProduct) .. "  R$ " .. price)
			end
		end)
	end
end

-- Kleinste Schrittzahl, ab der das Tempo um 1 steigt (nil = schon maximal)
local function nextSpeedSteps(steps: number): number?
	local Config = ctx.Config
	if type(Config.StepsSpeed) ~= "function" then
		return nil
	end
	local current = Config.StepsSpeed(steps)
	local maxSpeed = tonumber(Config.MaxWalkSpeed) or 80
	if current >= maxSpeed then
		return nil
	end
	-- Erst verdoppeln, bis das Tempo steigt, dann eingrenzen (klappt für jede steigende Formel)
	local low = steps
	local high = math.max(steps * 2, steps + 10)
	local guard = 0
	while Config.StepsSpeed(high) <= current and guard < 200 do
		high *= 2
		guard += 1
	end
	if Config.StepsSpeed(high) <= current then
		return nil
	end
	for _ = 1, 60 do
		local mid = math.floor((low + high) / 2)
		if mid <= low then
			break
		end
		if Config.StepsSpeed(mid) > current then
			high = mid
		else
			low = mid
		end
	end
	return high
end

function Windows.RefreshTreadmills(state: any)
	if not state then
		return
	end
	local Util = ctx.Util
	local steps = tonumber(state.Steps) or 0
	local mult = tonumber(state.StepsMult) or 1
	local maxSpeed = tonumber(ctx.Config.MaxWalkSpeed) or 80
	treadmillInfo.Text = ("👟 %s Schritte  •  🏃 Tempo %s/%s"):format(
		Util.FormatNumber(steps),
		tostring(math.floor(tonumber(state.Speed) or 16)),
		tostring(maxSpeed)
	)
	local nextSteps = nextSpeedSteps(steps)
	treadmillSpeed.Text = if nextSteps
		then ("Nächstes +1 Tempo bei %s 👟  •  Bonus x%s"):format(
			Util.FormatNumber(nextSteps),
			UI.FormatMult(mult)
		)
		else ("🚀 Maximales Tempo erreicht!  •  Bonus x%s"):format(UI.FormatMult(mult))

	-- Sparen fürs nächste Laufband (Cash / Preis)
	local cash = tonumber(state.Cash) or 0
	local nextDef = nil
	for _, row in ipairs(treadmillRows) do
		if not ownsTreadmill(state, row.Def) then
			nextDef = row.Def
			break
		end
	end
	if nextDef then
		local price = math.max(1, tonumber(nextDef.Price) or 1)
		UI.SetBar(
			treadmillBar,
			cash / price,
			("Nächstes: %s  %s / %s"):format(tostring(nextDef.Name), Util.FormatCash(cash), Util.FormatCash(price))
		)
	else
		UI.SetBar(treadmillBar, 1, "Alle Laufbänder gekauft!")
	end

	for _, row in ipairs(treadmillRows) do
		local def = row.Def
		local price = tonumber(def.Price) or 0
		local owned = ownsTreadmill(state, def)
		local rateText = ("+%s 👟 alle 0,5 s"):format(
			UI.FormatSteps((tonumber(def.Rate) or 0) * mult, Util.FormatNumber)
		)
		if row.Rate.Text ~= rateText then
			row.Rate.Text = rateText
		end
		local strokeColor = Color3.new(0, 0, 0)
		if state.BestTreadmill == def.Id then
			row.Buy.SetText("Dein bestes")
			row.Buy.SetColor(Theme.Gold)
			strokeColor = Theme.Gold
		elseif owned then
			row.Buy.SetText("Gekauft")
			row.Buy.SetColor(GRAY)
		elseif def == nextDef then
			row.Buy.SetText(Util.FormatCash(price))
			row.Buy.SetColor(if cash >= price then Theme.Green else GRAY)
		else
			row.Buy.SetText("🔒 " .. Util.FormatCash(price))
			row.Buy.SetColor(GRAY)
		end
		if row.Stroke.Color ~= strokeColor then
			row.Stroke.Color = strokeColor
			row.Stroke.Thickness = if strokeColor == Theme.Gold then 4 else 2
		end
		local transparency = if owned then 0 else 0.3
		if row.Card.BackgroundTransparency ~= transparency then
			row.Card.BackgroundTransparency = transparency
		end
	end

	if bootsButton then
		local owned = state.Passes and state.Passes.SpeedBoots == true
		bootsButton.Frame.Visible = not owned
	end
end

-- ---------------------------------------------------------------------
-- REBIRTH
-- ---------------------------------------------------------------------
local rebirthInfo: TextLabel
local rebirthBar: UI.Bar
local rebirthDetail: TextLabel

local function buildRebirth()
	local win = UI.Window("🔥 REBIRTH", 500, 450, Theme.Orange)
	list.Rebirth = win
	local content = win.Content
	rebirthInfo = UI.Label({
		Size = UDim2.new(1, 0, 0, 32),
		Text = "",
		LayoutOrder = 1,
		MaxText = 24,
		Outline = 2,
		Parent = content,
	})
	rebirthBar = UI.Bar({ Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 2, Color = Theme.Orange, Parent = content })
	rebirthDetail = UI.Label({
		Size = UDim2.new(1, 0, 0, 150),
		Text = "",
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.SubText,
		TextWrapped = true,
		LayoutOrder = 3,
		MaxText = 16,
		Parent = content,
	})
	UI.Button({
		Size = UDim2.new(1, 0, 0, 58),
		Text = "🔥 REBIRTH!",
		Color = Theme.Red,
		LayoutOrder = 4,
		MaxText = 30,
		Parent = content,
	}, function()
		ctx.Request("Rebirth")
	end)
end

local function nextUnlock(rebirths: number): string?
	for _, rarity in ipairs(ctx.Config.Rarities) do
		if not rarity.AdminOnly and (rarity.RequiredRebirths or 0) == rebirths + 1 then
			return rarity.Name
		end
	end
	return nil
end

function Windows.RefreshRebirth(state: any)
	if not state then
		return
	end
	local Util = ctx.Util
	local Config = ctx.Config
	local cash = tonumber(state.Cash) or 0
	local cost = math.max(1, tonumber(state.RebirthCost) or 1)
	local rebirths = tonumber(state.Rebirths) or 0
	rebirthInfo.Text = "🔥 Rebirths: " .. rebirths
	UI.SetBar(rebirthBar, cash / cost, Util.FormatCash(cash) .. " / " .. Util.FormatCash(cost))
	local unlock = nextUnlock(rebirths)
	local detail = (
		"Belohnung:\n• +%d%% Einkommen für immer\n• +%d%% Schritte auf jedem Laufband%s\n\n"
		.. "Du verlierst: Cash, Meteore + Aliens.\nDu behältst: Schritte, Laufbänder, Gadgets, Index, Gamepasses."
	):format(
		math.floor((tonumber(Config.RebirthMultPerLevel) or 0) * 100 + 0.5),
		math.floor((tonumber(Config.StepsPerRebirth) or 0.25) * 100 + 0.5),
		if unlock then ("\n• 🔓 " .. unlock .. "-Meteore kaufbar!") else ""
	)
	if rebirthDetail.Text ~= detail then
		rebirthDetail.Text = detail
	end
end

-- ---------------------------------------------------------------------
-- TAGESBONUS
-- ---------------------------------------------------------------------
local dailyInfo: TextLabel
local dailyButton: UI.Button

local function buildDaily()
	local win = UI.Window("🎁 TAGESBONUS", 440, 300, Theme.Purple)
	list.Daily = win
	local content = win.Content
	dailyInfo = UI.Label({
		Size = UDim2.new(1, 0, 0, 70),
		Text = "",
		LayoutOrder = 1,
		TextWrapped = true,
		MaxText = 22,
		Outline = 2,
		Parent = content,
	})
	dailyButton = UI.Button({
		Size = UDim2.new(1, 0, 0, 62),
		Text = "🎁 ABHOLEN",
		Color = Theme.Green,
		LayoutOrder = 2,
		MaxText = 30,
		Parent = content,
	}, function()
		ctx.Request("Daily")
	end)
end

function Windows.RefreshDaily(state: any)
	if not state then
		return
	end
	local streak = tonumber(state.Streak) or 0
	if state.DailyReady then
		dailyInfo.Text = "Dein Bonus ist bereit! 🔥 Streak: " .. streak .. " Tag(e)"
		dailyButton.SetText("🎁 ABHOLEN")
		dailyButton.SetColor(Theme.Green)
	else
		dailyInfo.Text = "Komm morgen wieder! 🔥 Streak: " .. streak .. " Tag(e)"
		dailyButton.SetText("⏳ " .. ctx.Util.FormatTime(tonumber(state.DailyIn) or 0))
		dailyButton.SetColor(GRAY)
	end
end

-- ---------------------------------------------------------------------
-- ALIEN-INDEX
-- ---------------------------------------------------------------------
type IndexCard = {
	Def: any,
	Card: Frame,
	Dot: Frame,
	DotStroke: UIStroke,
	Question: TextLabel,
	Name: TextLabel,
}
type IndexGroup = { Title: string, Header: TextLabel, Cards: { IndexCard }, Color: Color3 }

local indexHeader: TextLabel
local indexBar: UI.Bar
local batLabel: TextLabel
local indexGroups: { IndexGroup } = {}
local indexSignature = ""
local SPECIAL_TITLE = "👑 Admin & Spezial (Bonus)"

-- Aliens, die normale Spieler nie selbst ausbrüten können: aus Admin-Meteoren oder aus Meteoren,
-- die nie in die Parade kommen (z.B. Omega). Zählen als Bonus, nicht zum "X/Y"-Ziel.
local function isSpecialAlien(def: any): boolean
	local Config = ctx.Config
	local rarity = Config.RaritiesByName and Config.RaritiesByName[def.Rarity]
	if rarity and rarity.AdminOnly then
		return true
	end
	local meteor = Config.MeteorsById and Config.MeteorsById[def.Meteor]
	return meteor ~= nil and meteor.Spawnable == false
end

local function buildIndex()
	local win = UI.Window("👽 ALIEN-INDEX", 680, 560, Theme.Green)
	list.Index = win
	local content = win.Content
	indexHeader = UI.Label({
		Size = UDim2.new(1, 0, 0, 32),
		Text = "",
		LayoutOrder = 1,
		MaxText = 22,
		Outline = 2,
		Parent = content,
	})
	indexBar = UI.Bar({ LayoutOrder = 2, Color = Theme.Green, MaxText = 16, Parent = content })
	-- Schläger-Stufe: mehr entdeckte Aliens = besserer Schläger
	batLabel = UI.Label({
		Size = UDim2.new(1, 0, 0, 24),
		Text = "",
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.SubText,
		LayoutOrder = 3,
		MaxText = 16,
		Parent = content,
	})

	-- Aliens nach Seltenheit sortieren (Reihenfolge wie Config.Rarities),
	-- Admin- und Spezial-Aliens zum Schluss in einer eigenen Bonus-Gruppe
	local byRarity: { [string]: { any } } = {}
	local special: { any } = {}
	for _, def in ipairs(ctx.Aliens.List) do
		if isSpecialAlien(def) then
			table.insert(special, def)
		else
			local group = byRarity[def.Rarity]
			if not group then
				group = {}
				byRarity[def.Rarity] = group
			end
			table.insert(group, def)
		end
	end
	local sections: { { Title: string, Color: Color3, Defs: { any } } } = {}
	for _, rarity in ipairs(ctx.Config.Rarities) do
		local defs = byRarity[rarity.Name]
		if defs and #defs > 0 then
			table.insert(sections, { Title = rarity.Name, Color = rarity.Color, Defs = defs })
		end
	end
	if #special > 0 then
		local adminRarity = ctx.Config.RaritiesByName and ctx.Config.RaritiesByName.Admin
		local color: Color3 = if adminRarity then adminRarity.Color else Theme.Red
		table.insert(sections, { Title = SPECIAL_TITLE, Color = color, Defs = special })
	end
	local order = 10
	for _, section in ipairs(sections) do
		local defs = section.Defs
		order += 1
		local header = UI.Section(content, section.Title, order, section.Color)
		order += 1
		local gridFrame = UI.Grid(content, order, 148, 74)
		local group: IndexGroup = { Title = section.Title, Header = header, Cards = {}, Color = section.Color }
		for i, def in ipairs(defs) do
			local look = def.Look or {}
			local card = UI.Card({ LayoutOrder = i, Parent = gridFrame })
			local dotStroke = UI.Stroke(look.Accent or Color3.new(1, 1, 1), 3)
			local dot = UI.Create("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 8, 0.5, 0),
				Size = UDim2.fromOffset(38, 38),
				BackgroundColor3 = look.Color or section.Color,
				Parent = card,
			}, { UI.Corner(19), dotStroke })
			local question = UI.Label({
				Size = UDim2.fromScale(1, 1),
				Text = "?",
				MaxText = 24,
				Outline = 2,
				Visible = false,
				Parent = dot,
			})
			local nameLabel = UI.Label({
				Position = UDim2.fromOffset(52, 6),
				Size = UDim2.new(1, -58, 0, 40),
				Text = "???",
				TextWrapped = true,
				MaxText = 15,
				Outline = 2,
				Parent = card,
			})
			UI.Label({
				Position = UDim2.fromOffset(52, 48),
				Size = UDim2.new(1, -58, 0, 18),
				Text = tostring(def.Tier),
				TextColor3 = TIER_COLORS[def.Tier] or Theme.SubText,
				MaxText = 13,
				Outline = 1,
				Parent = card,
			})
			table.insert(group.Cards, {
				Def = def,
				Card = card,
				Dot = dot,
				DotStroke = dotStroke,
				Question = question,
				Name = nameLabel,
			})
		end
		table.insert(indexGroups, group)
	end
end

function Windows.RefreshIndex(state: any)
	if not state then
		return
	end
	local index = if type(state.Index) == "table" then state.Index else {}
	local bats = ctx.Config.BatsById or {}
	local bat, nextBat = bats[state.Bat], bats[state.NextBat]
	local batText = if bat then ("Dein Schläger: " .. tostring(bat.Name)) else ""
	if nextBat then
		batText ..= ("  •  %s ab %d Aliens"):format(tostring(nextBat.Name), tonumber(nextBat.IndexRequired) or 0)
	elseif bat then
		batText ..= "  •  bester Schläger!"
	end
	if batLabel.Text ~= batText then
		batLabel.Text = batText
	end
	-- Nur neu zeichnen, wenn sich etwas geändert hat
	local signature = #index .. ":" .. tostring(index[#index])
	if signature == indexSignature then
		return
	end
	indexSignature = signature
	local found: { [string]: boolean } = {}
	local count = 0 -- alle entdeckten (jedes gibt Einkommens-Bonus)
	local normalFound, normalTotal, specialFound = 0, 0, 0
	for _, id in ipairs(index) do
		local def = ctx.Aliens.ById[id]
		if def and not found[id] then
			found[id] = true
			count += 1
			if isSpecialAlien(def) then
				specialFound += 1
			else
				normalFound += 1
			end
		end
	end
	for _, def in ipairs(ctx.Aliens.List) do
		if not isSpecialAlien(def) then
			normalTotal += 1
		end
	end
	local bonusPer = tonumber(ctx.Config.IndexBonusPerAlien) or 0.01
	local headerText = ("👽 Entdeckt: %d/%d  •  +%s%% Einkommen"):format(
		normalFound,
		normalTotal,
		percentText(count * bonusPer * 100)
	)
	if specialFound > 0 then
		headerText ..= ("  •  👑 +%d Spezial"):format(specialFound)
	end
	indexHeader.Text = headerText
	UI.SetBar(
		indexBar,
		if normalTotal > 0 then normalFound / normalTotal else 0,
		("%d / %d Aliens"):format(normalFound, normalTotal)
	)
	for _, group in ipairs(indexGroups) do
		local groupFound = 0
		for _, card in ipairs(group.Cards) do
			local def = card.Def
			local look = def.Look or {}
			if found[def.Id] then
				groupFound += 1
				card.Name.Text = tostring(def.Name)
				card.Dot.BackgroundColor3 = look.Color or group.Color
				card.DotStroke.Color = look.Accent or Color3.new(1, 1, 1)
				card.Question.Visible = false
				card.Card.BackgroundTransparency = 0
			else
				card.Name.Text = "???"
				card.Dot.BackgroundColor3 = Color3.new(0, 0, 0)
				card.DotStroke.Color = Color3.fromRGB(70, 70, 80)
				card.Question.Visible = true
				card.Card.BackgroundTransparency = 0.45
			end
		end
		group.Header.Text = ("%s  (%d/%d)"):format(group.Title, groupFound, #group.Cards)
	end
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICH
-- ---------------------------------------------------------------------
function Windows.Get(name: string): UI.Window?
	return list[name]
end

function Windows.Toggle(name: string)
	local win = list[name]
	if win then
		UI.ToggleWindow(win)
	end
end

function Windows.Open(name: string)
	local win = list[name]
	if win then
		UI.OpenWindow(win)
	end
end

-- Shop auf einem bestimmten Reiter öffnen ("Passes", "Boosts", "Gadgets")
function Windows.OpenShop(tab: string?)
	if tab then
		selectShopTab(tab)
	end
	Windows.Open("Shop")
end

-- Fenster aus anderen Modulen anmelden (z.B. Geschenke, Glücksrad, Aufgaben):
-- Toggle/Open per Name, beim Öffnen und bei neuen Daten wird refresh(state) aufgerufen.
function Windows.Register(name: string, win: UI.Window, refresh: ((state: any) -> ())?)
	list[name] = win
	if refresh then
		refreshers[name] = refresh
		win.OnOpen = function()
			if ctx.State then
				refresh(ctx.State)
			end
		end
	end
end

-- Neue Daten vom Server: nur OFFENE Fenster neu beschreiben (geschlossene beim Öffnen)
function Windows.Refresh(state: any)
	if not state then
		return
	end
	for name, win in pairs(list) do
		local refresh = refreshers[name]
		if refresh and win.IsOpen then
			refresh(state)
		end
	end
end

function Windows.Init(context: any)
	ctx = context
	buildShop()
	buildTreadmills()
	buildRebirth()
	buildDaily()
	buildIndex()
	-- Fenstername -> Aktualisieren (beim Öffnen einmal mit den neuesten Daten füllen)
	local own: { [string]: (state: any) -> () } = {
		Shop = Windows.RefreshShop,
		Treadmills = Windows.RefreshTreadmills,
		Rebirth = Windows.RefreshRebirth,
		Daily = Windows.RefreshDaily,
		Index = Windows.RefreshIndex,
	}
	for name, refresh in pairs(own) do
		local win = list[name]
		if win then
			Windows.Register(name, win, refresh)
		end
	end
	Windows.RefreshShop(nil)

	-- ⭐ Starter-Paket: abgebrochen -> Knopf wieder frei. Gekauft -> bleibt gesperrt, bis der Server
	-- "gekauft" meldet (danach verschwindet der Knopf ganz)
	local starter = ctx.Config.ProductsByKey and ctx.Config.ProductsByKey.StarterPack
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		if userId ~= player.UserId or not starter or productId ~= starter.Id then
			return
		end
		if not purchased then
			starterPendingUntil = 0
		end
		Windows.RefreshShop(ctx.State)
		if ctx.State then
			ctx.Hud.Refresh(ctx.State)
		end
	end)
end

return Windows
