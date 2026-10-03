-- =====================================================================
--  FENSTER: Shop, Laufbänder, Rebirth, Tagesbonus, Alien-Index
--  Jedes Fenster wird EINMAL gebaut; Refresh(state) schreibt nur die Werte neu.
-- =====================================================================

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")

local UI = require(script.Parent:WaitForChild("UI"))

local Windows = {}

local player = Players.LocalPlayer
local ctx: any = nil
local Theme = UI.Theme

local list: { [string]: UI.Window } = {}

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

-- Bestes freigeschaltetes Laufband (für Schritte-Paket-Anzeige)
local function bestTreadmill(steps: number): any
	local best = nil
	local treadmills = ctx.Config.Treadmills
	if type(treadmills) == "table" then
		for _, def in ipairs(treadmills) do
			if steps >= (tonumber(def.Required) or 0) then
				best = def
			end
		end
	end
	return best
end

-- ---------------------------------------------------------------------
-- SHOP
-- ---------------------------------------------------------------------
type PassCard = { Pass: any, Button: UI.Button, Price: number? }
type ProductCard = { Product: any, Info: TextLabel? }

local passCards: { PassCard } = {}
local productCards: { ProductCard } = {}

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
	return "🐣 Schlüpft: " .. table.concat(parts, " • ") .. " (Glück-Events: besser)"
end

-- Roblox-Regel "Paid Random Items": Chancen VOR dem Kauf anzeigen
local function oddsText(rarityName: string): string
	local defs = meteorsOfRarity(rarityName)
	if #defs == 0 then
		return ""
	end
	local names = {}
	for _, def in ipairs(defs) do
		table.insert(names, def.Name)
	end
	local chance = percentText(100 / #defs)
	return ("🎲 Je %s%%: %s\n%s"):format(chance, table.concat(names, ", "), hatchOddsText(defs[1].Id))
end

local function productInfoText(product: any, state: any): string
	local Util = ctx.Util
	local kind = product.Type
	if kind == "Cash" then
		local income = state and tonumber(state.Income) or 0
		local amount = math.max(tonumber(product.Min) or 0, income * 60 * (tonumber(product.Minutes) or 0))
		return ("%s Min. Einkommen  ≈ %s"):format(tostring(product.Minutes or 0), Util.FormatCash(amount))
	elseif kind == "Steps" then
		local steps = state and tonumber(state.Steps) or 0
		local mult = state and tonumber(state.StepsMult) or 1
		local best = bestTreadmill(steps)
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
		return "🌠 Sofort mehr + bessere Meteore für alle!"
	end
	return ""
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
		if entry.Info then
			local text = productInfoText(entry.Product, state)
			if entry.Info.Text ~= text then
				entry.Info.Text = text
			end
		end
	end
end

local function buildShop()
	local win = UI.Window("🛒 SHOP", 620, 520, Theme.Red)
	list.Shop = win
	local content = win.Content

	UI.Section(content, "⭐ Gamepasses (für immer)", 1)
	local passGrid = UI.Grid(content, 2, 280, 136)
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

	UI.Section(content, "💎 Boosts & Pakete", 3)
	local productGrid = UI.Grid(content, 4, 280, 150)
	local randomCards: { Frame } = {}
	for i, product in ipairs(ctx.Config.Products) do
		local isRandom = product.Type == "Meteor"
		local card = UI.Card({
			LayoutOrder = i,
			Visible = not isRandom, -- erst zeigen, wenn die Länder-Regel geprüft ist
			Parent = productGrid,
		})
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
			Size = UDim2.new(1, -20, 0, 56),
			Text = if isRandom then oddsText(product.Rarity) else productInfoText(product, nil),
			Font = Enum.Font.GothamBold,
			TextColor3 = Theme.SubText,
			TextWrapped = true,
			MaxText = if isRandom then 12 else 14,
			Parent = card,
		})
		if isRandom then
			table.insert(randomCards, card)
		end
		table.insert(productCards, { Product = product, Info = if isRandom then nil else info })
		local buy = UI.Button({
			Position = UDim2.new(0, 10, 1, -46),
			Size = UDim2.new(1, -20, 0, 36),
			Text = "...",
			Color = Theme.Blue,
			MaxText = 20,
			Parent = card,
		}, function()
			if product.Id ~= 0 then
				MarketplaceService:PromptProductPurchase(player, product.Id)
			end
		end)
		UI.FetchPrice(product.Id, Enum.InfoType.Product, function(price)
			if product.Id == 0 then
				buy.SetText("Bald verfügbar")
				buy.SetColor(GRAY)
			else
				buy.SetText(if price then ("R$ " .. price) else "Kaufen")
			end
		end)
	end
	-- Zufalls-Käufe nur zeigen, wo sie erlaubt sind (im Zweifel/bei Fehler: nicht zeigen)
	task.spawn(function()
		local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
		local allowed = ok and type(info) == "table" and info.ArePaidRandomItemsRestricted == false
		for _, card in ipairs(randomCards) do
			card.Visible = allowed
		end
	end)
end

-- ---------------------------------------------------------------------
-- LAUFBÄNDER
-- ---------------------------------------------------------------------
type TreadmillRow = {
	Def: any,
	Card: Frame,
	Stroke: UIStroke,
	Rate: TextLabel,
	Status: TextLabel,
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
		Text = "Drauf laufen = Schritte 👟 sammeln = schneller rennen! Mehr Schritte schalten bessere Laufbänder frei.",
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
		local status = UI.Label({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(150, 40),
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Right,
			MaxText = 18,
			Outline = 2,
			Parent = card,
		})
		table.insert(treadmillRows, { Def = def, Card = card, Stroke = stroke, Rate = rate, Status = status })
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

	-- Fortschritt bis zum nächsten Laufband
	local previous = 0
	local nextDef = nil
	for _, row in ipairs(treadmillRows) do
		local required = tonumber(row.Def.Required) or 0
		if steps >= required then
			previous = required
		elseif not nextDef then
			nextDef = row.Def
		end
	end
	if nextDef then
		local required = tonumber(nextDef.Required) or 1
		UI.SetBar(
			treadmillBar,
			(steps - previous) / math.max(1, required - previous),
			("🔓 %s: %s / %s 👟"):format(
				tostring(nextDef.Name),
				Util.FormatNumber(steps),
				Util.FormatNumber(required)
			)
		)
	else
		UI.SetBar(treadmillBar, 1, "🌈 Alle Laufbänder freigeschaltet!")
	end

	for _, row in ipairs(treadmillRows) do
		local def = row.Def
		local required = tonumber(def.Required) or 0
		local rateText = ("+%s 👟 alle 0,5 s"):format(
			UI.FormatSteps((tonumber(def.Rate) or 0) * mult, Util.FormatNumber)
		)
		if row.Rate.Text ~= rateText then
			row.Rate.Text = rateText
		end
		local statusText, statusColor, strokeColor
		if state.BestTreadmill == def.Id then
			statusText, statusColor, strokeColor = "⭐ Dein bestes", Theme.Yellow, Theme.Gold
		elseif steps >= required then
			statusText, statusColor, strokeColor = "✅ Frei", Theme.Cash, Color3.new(0, 0, 0)
		else
			statusText = "🔒 " .. Util.FormatNumber(required) .. " 👟"
			statusColor, strokeColor = Color3.fromRGB(255, 130, 130), Color3.new(0, 0, 0)
		end
		if row.Status.Text ~= statusText then
			row.Status.Text = statusText
			row.Status.TextColor3 = statusColor
			row.Stroke.Color = strokeColor
			row.Stroke.Thickness = if strokeColor == Theme.Gold then 4 else 2
			row.Card.BackgroundTransparency = if steps >= required then 0 else 0.35
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
		.. "Du verlierst: Cash, Meteore + Aliens.\nDu behältst: Schritte 👟, Index, Gamepasses."
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
type IndexGroup = { Rarity: string, Header: TextLabel, Cards: { IndexCard }, Color: Color3 }

local indexHeader: TextLabel
local indexBar: UI.Bar
local indexGroups: { IndexGroup } = {}
local indexSignature = ""

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

	-- Aliens nach Seltenheit sortieren (Reihenfolge wie Config.Rarities)
	local byRarity: { [string]: { any } } = {}
	for _, def in ipairs(ctx.Aliens.List) do
		local group = byRarity[def.Rarity]
		if not group then
			group = {}
			byRarity[def.Rarity] = group
		end
		table.insert(group, def)
	end
	local order = 10
	for _, rarity in ipairs(ctx.Config.Rarities) do
		local defs = byRarity[rarity.Name]
		if defs and #defs > 0 then
			order += 1
			local header = UI.Section(content, rarity.Name, order, rarity.Color)
			order += 1
			local gridFrame = UI.Grid(content, order, 148, 74)
			local group: IndexGroup = { Rarity = rarity.Name, Header = header, Cards = {}, Color = rarity.Color }
			for i, def in ipairs(defs) do
				local look = def.Look or {}
				local card = UI.Card({ LayoutOrder = i, Parent = gridFrame })
				local dotStroke = UI.Stroke(look.Accent or Color3.new(1, 1, 1), 3)
				local dot = UI.Create("Frame", {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, 8, 0.5, 0),
					Size = UDim2.fromOffset(38, 38),
					BackgroundColor3 = look.Color or rarity.Color,
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
end

function Windows.RefreshIndex(state: any)
	if not state then
		return
	end
	local index = if type(state.Index) == "table" then state.Index else {}
	-- Nur neu zeichnen, wenn sich etwas geändert hat
	local signature = #index .. ":" .. tostring(index[#index])
	if signature == indexSignature then
		return
	end
	indexSignature = signature
	local found: { [string]: boolean } = {}
	local count = 0
	for _, id in ipairs(index) do
		if ctx.Aliens.ById[id] and not found[id] then
			found[id] = true
			count += 1
		end
	end
	local total = #ctx.Aliens.List
	local bonusPer = tonumber(ctx.Config.IndexBonusPerAlien) or 0.01
	indexHeader.Text = ("👽 Entdeckt: %d/%d  •  +%s%% Einkommen"):format(
		count,
		total,
		percentText(count * bonusPer * 100)
	)
	UI.SetBar(indexBar, if total > 0 then count / total else 0, ("%d / %d Aliens"):format(count, total))
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
		group.Header.Text = ("%s  (%d/%d)"):format(group.Rarity, groupFound, #group.Cards)
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

function Windows.Refresh(state: any)
	if not state then
		return
	end
	Windows.RefreshShop(state)
	Windows.RefreshTreadmills(state)
	Windows.RefreshRebirth(state)
	Windows.RefreshDaily(state)
	Windows.RefreshIndex(state)
end

function Windows.Init(context: any)
	ctx = context
	buildShop()
	buildTreadmills()
	buildRebirth()
	buildDaily()
	buildIndex()
	Windows.RefreshShop(nil)
end

return Windows
