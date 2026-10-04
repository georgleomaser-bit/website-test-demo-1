-- =====================================================================
--  BELOHNUNGS-FENSTER: 🎁 Geschenke, 🎡 Glücksrad, 📜 Tagesaufgaben
--  Gewürfelt und gutgeschrieben wird NUR auf dem Server. Hier wird angezeigt und angefragt
--  ("ClaimGift", "Spin", "ClaimQuest", "RerollQuest"). Countdowns laufen lokal weiter – ohne dass
--  der Server jede Sekunde senden muss: FreeSpinIn gilt ab der Ankunft des States (ctx.StateTime),
--  die Geschenke kommen nur bei Änderung und zählen ab GiftsAt (Serverzeit).
--  Das Glücksrad holt kurz Schwung (dreht ein Stück zurück), läuft realistisch aus, rollt einen
--  Hauch über das Ziel hinaus und pendelt zurück – genau auf das Feld, das der Server gewürfelt hat.
--  Der Zeiger schnippt an jedem Feld und wackelt gedämpft nach (Feder), die Lämpchen blinken
--  passend zum Tempo.
-- =====================================================================

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent:WaitForChild("UI"))

local Rewards = {}

local player = Players.LocalPlayer
local ctx: any = nil
local Theme = UI.Theme
local GRAY = Theme.Gray
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local giftWin: UI.Window
local wheelWin: UI.Window
local questWin: UI.Window

-- Sekunden seit der Ankunft des letzten States (dessen Countdowns gelten ab dann)
local function sinceState(): number
	local t = ctx and ctx.StateTime
	if type(t) ~= "number" then
		return 0
	end
	return math.max(0, os.clock() - t)
end

-- Sekunden, seit die Geschenk-Countdowns (ReadyIn) gelten. Der Server schickt die Geschenke nur bei
-- Änderung – deshalb zählen sie ab GiftsAt (Serverzeit), nicht ab dem letzten State.
local function sinceGifts(state: any): number
	local at = type(state) == "table" and tonumber(state.GiftsAt)
	if at then
		return math.max(0, workspace:GetServerTimeNow() - at)
	end
	return sinceState()
end

-- "👟 2x Schritte" + Icon "👟" -> Icon nicht doppelt
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

-- ---------------------------------------------------------------------
-- ZUSAMMENFASSUNG (für die Badges im HUD und die Fenster)
-- ---------------------------------------------------------------------
export type Summary = {
	GiftsReady: number, -- abholbereite Geschenke
	NextGiftIn: number?, -- Sekunden bis zum nächsten (nil = keins mehr)
	Spins: number, -- gekaufte/gewonnene Drehs
	HasWheel: boolean, -- liefert der Server Glücksrad-Daten?
	FreeReady: boolean, -- Gratis-Dreh bereit
	FreeIn: number, -- Sekunden bis zum Gratis-Dreh
	QuestsReady: number, -- geschafft, aber nicht abgeholt
}

function Rewards.Summary(state: any): Summary
	local elapsed = sinceState()
	local giftElapsed = sinceGifts(state)
	local giftsReady = 0
	local nextGift: number? = nil
	local quests = 0
	if type(state) == "table" then
		if type(state.Gifts) == "table" then
			for _, gift in ipairs(state.Gifts) do
				if type(gift) == "table" and gift.Claimed ~= true then
					local left = (tonumber(gift.ReadyIn) or 0) - giftElapsed
					if left <= 0 then
						giftsReady += 1
					elseif nextGift == nil or left < nextGift then
						nextGift = left
					end
				end
			end
		end
		if type(state.Quests) == "table" then
			for _, quest in ipairs(state.Quests) do
				if
					type(quest) == "table"
					and quest.Claimed ~= true
					and (tonumber(quest.Progress) or 0) >= (tonumber(quest.Goal) or math.huge)
				then
					quests += 1
				end
			end
		end
	end
	local hasWheel = type(state) == "table" and state.FreeSpinIn ~= nil
	local freeIn = if hasWheel then math.max(0, (tonumber(state.FreeSpinIn) or 0) - elapsed) else 0
	return {
		GiftsReady = giftsReady,
		NextGiftIn = nextGift,
		Spins = math.max(0, math.floor(if type(state) == "table" then tonumber(state.Spins) or 0 else 0)),
		HasWheel = hasWheel,
		FreeReady = hasWheel and freeIn <= 0,
		FreeIn = freeIn,
		QuestsReady = quests,
	}
end

-- ---------------------------------------------------------------------
-- 🎁 SPIELZEIT-GESCHENKE
-- ---------------------------------------------------------------------
type GiftCard = {
	Card: Frame,
	Stroke: UIStroke,
	Title: TextLabel,
	Sub: TextLabel,
	Button: UI.Button,
}

local giftCards: { GiftCard } = {}
local giftInfo: TextLabel

local function buildGifts()
	giftWin = UI.Window("🎁 GESCHENKE", 540, 560, Theme.Purple)
	local content = giftWin.Content
	giftInfo = UI.Label({
		Size = UDim2.new(1, 0, 0, 30),
		Text = "🎁 Spiel weiter – alle paar Minuten gibt's ein Geschenk!",
		TextColor3 = Theme.Yellow,
		LayoutOrder = 1,
		MaxText = 20,
		Outline = 2,
		Parent = content,
	})
	local gifts = ctx.Config.PlaytimeGifts
	if type(gifts) ~= "table" then
		gifts = {}
	end
	for i, gift in ipairs(gifts) do
		local card = UI.Card({ Size = UDim2.new(1, 0, 0, 66), LayoutOrder = 10 + i, Parent = content })
		local stroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
		local minutesBox = UI.Create("Frame", {
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.fromOffset(50, 50),
			BackgroundColor3 = Theme.PanelDark,
			Parent = card,
		}, { UI.Corner(10), UI.Stroke(BLACK, 2) })
		UI.Label({
			Position = UDim2.fromOffset(2, 4),
			Size = UDim2.new(1, -4, 0, 26),
			Text = tostring(gift.Icon or "🎁"),
			MaxText = 24,
			Parent = minutesBox,
		})
		UI.Label({
			Position = UDim2.new(0, 2, 1, -20),
			Size = UDim2.new(1, -4, 0, 16),
			Text = tostring(gift.Minutes or "?") .. " Min",
			TextColor3 = Theme.Yellow,
			MaxText = 13,
			Outline = 1,
			Parent = minutesBox,
		})
		local title = UI.Label({
			Position = UDim2.fromOffset(68, 7),
			Size = UDim2.new(1, -228, 0, 30),
			Text = displayName(gift),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxText = 22,
			Outline = 2,
			Parent = card,
		})
		local sub = UI.Label({
			Position = UDim2.fromOffset(68, 38),
			Size = UDim2.new(1, -228, 0, 20),
			Text = "",
			Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.SubText,
			MaxText = 14,
			Parent = card,
		})
		local button = UI.Button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(140, 46),
			Text = "...",
			Color = GRAY,
			MaxText = 20,
			Parent = card,
		}, function()
			ctx.Request("ClaimGift", i)
		end)
		giftCards[i] = { Card = card, Stroke = stroke, Title = title, Sub = sub, Button = button }
	end
end

function Rewards.RefreshGifts(state: any)
	if not state then
		return
	end
	local list = if type(state.Gifts) == "table" then state.Gifts else {}
	local elapsed = sinceGifts(state)
	local playSeconds: number? = nil
	for i, card in ipairs(giftCards) do
		local gift = list[i]
		card.Card.Visible = type(gift) == "table"
		if type(gift) == "table" then
			local text = if type(gift.Text) == "string" and gift.Text ~= "" then gift.Text else card.Title.Text
			if card.Title.Text ~= text then
				card.Title.Text = text
			end
			local minutes = tonumber(gift.Minutes) or 0
			local left = math.max(0, (tonumber(gift.ReadyIn) or 0) - elapsed)
			if left > 0 and playSeconds == nil then
				playSeconds = minutes * 60 - left
			end
			local subText, buttonText, color, gold
			if gift.Claimed == true then
				subText, buttonText, color, gold = "✅ Abgeholt", "✅", GRAY, false
			elseif left <= 0 then
				subText, buttonText, color, gold = "🎁 Bereit – hol es dir!", "🎁 Abholen", Theme.Green, true
			else
				subText = "nach " .. minutes .. " Min. Spielzeit heute"
				buttonText, color, gold = "⏳ " .. ctx.Util.FormatTime(math.ceil(left)), GRAY, false
			end
			if card.Sub.Text ~= subText then
				card.Sub.Text = subText
			end
			card.Button.SetText(buttonText)
			card.Button.SetColor(color)
			local strokeColor = if gold then Theme.Gold else BLACK
			if card.Stroke.Color ~= strokeColor then
				card.Stroke.Color = strokeColor
				card.Stroke.Thickness = if gold then 4 else 2
			end
			card.Card.BackgroundTransparency = if gift.Claimed == true then 0.4 else 0
		end
	end
	local info
	if #list == 0 then
		info = "🎁 Geschenke werden geladen..."
	elseif playSeconds then
		info = "⏱️ Spielzeit heute: "
			.. ctx.Util.FormatTime(math.max(0, playSeconds))
			.. "  •  bleib dran für mehr! 🎁"
	else
		info = "🏆 Alle Geschenke von heute freigeschaltet – morgen gibt's neue!"
	end
	if giftInfo.Text ~= info then
		giftInfo.Text = info
	end
end

-- ---------------------------------------------------------------------
-- 🎡 GLÜCKSRAD
-- Das Rad besteht aus schmalen, gedrehten Streifen ("Speichen") pro Feld – nur normale Frames,
-- keine Bilder, keine CanvasGroup. Beim Drehen wird nur die Rotation des Rotors getweent.
-- ---------------------------------------------------------------------
local WHEEL_RADIUS = 140
local SPOKES_PER_SEGMENT = 12
local SPIN_TIME = 4.4
local SPIN_TURNS = 5
local SPIN_INFO = TweenInfo.new(SPIN_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local WINDUP_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SETTLE_INFO = TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local WIN_POP_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 2, true)
local WINDUP_ANGLE = 9 -- so weit holt das Rad vor dem Drehen Schwung (Grad zurück)
local OVERSHOOT = 0.14 -- rollt so viel (Anteil eines Felds) übers Ziel und pendelt zurück
local POINTER_KICK = 26 -- so weit schnippt der Zeiger höchstens, wenn ein Feld vorbeisaust
local POINTER_STIFFNESS = 700 -- Feder des Zeigers (höher = schneller zurück)
local POINTER_DAMPING = 13 -- Dämpfung (niedriger = wackelt länger nach)
local POINTER_STEP = 1 / 240 -- Rechenschritt der Zeiger-Feder (stabil bei jeder Bildrate)
local LIGHT_COUNT = 16
local LIGHT_ON = Color3.fromRGB(255, 245, 160)
local LIGHT_OFF = Color3.fromRGB(255, 120, 40)

local wheelRotor: Frame
local wheelPointer: TextLabel
local segmentIconScales: { UIScale } = {}
local segmentTexts: { TextLabel } = {}
local rimLights: { Frame } = {}
local spinInfo: TextLabel
local spinButton: UI.Button
local productRow: Frame
local spinning = false
local lightsFlipped = false

local function wheelPrizes(): { any }
	local list = ctx.Config.WheelPrizes
	return if type(list) == "table" then list else {}
end

local function segmentCount(): number
	return math.max(1, #wheelPrizes())
end

local function circle(props: { [string]: any }): Frame
	local frame: Frame = UI.Create("Frame", props)
	UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = frame })
	return frame
end

-- Eine Speiche: Halter (2r hoch, um die Radmitte gedreht), obere Hälfte farbig:
-- innen schmal, außen breit (so bleiben die Feldgrenzen auch zur Mitte hin sauber)
local function addSpoke(parent: Frame, angle: number, color: Color3, inner: number, outer: number, z: number)
	local r = WHEEL_RADIUS
	local holder = UI.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(outer, r * 2),
		BackgroundTransparency = 1,
		Rotation = angle,
		ZIndex = z,
		Parent = parent,
	})
	UI.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(outer, math.floor(r / 2) + 1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = z,
		Parent = holder,
	})
	UI.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, math.floor(r / 2)),
		Size = UDim2.fromOffset(inner, math.ceil(r / 2)),
		BackgroundColor3 = color:Lerp(BLACK, 0.12),
		BorderSizePixel = 0,
		ZIndex = z,
		Parent = holder,
	})
end

local function setLights(flip: boolean)
	lightsFlipped = flip
	for i, dot in ipairs(rimLights) do
		local on = (i % 2 == 0) ~= flip
		dot.BackgroundColor3 = if on then LIGHT_ON else LIGHT_OFF
	end
end

-- Text auf dem Feld (Beträge wachsen mit deinem Einkommen – gleiche Rechnung wie der Server)
local function prizeAmountText(prize: any, state: any): string
	local Util = ctx.Util
	local kind = tostring(prize.Type or "Cash")
	if kind == "Cash" then
		local income = state and tonumber(state.Income) or 0
		return Util.FormatCash(math.max(tonumber(prize.Min) or 0, income * (tonumber(prize.Seconds) or 60)))
	elseif kind == "Steps" then
		local mult = state and tonumber(state.StepsMult) or 1
		local best = ctx.Config.BestTreadmill and ctx.Config.BestTreadmill(state and state.Treadmills)
		local rate = best and tonumber(best.Rate) or 1
		local perSecond = rate / (tonumber(ctx.Config.TreadmillTick) or 0.5) * mult
		return Util.FormatNumber(math.max(tonumber(prize.Min) or 0, perSecond * (tonumber(prize.Seconds) or 60)))
	elseif kind == "Spins" then
		local amount = math.max(1, math.floor(tonumber(prize.Amount) or 1))
		return amount .. (if amount == 1 then " Dreh" else " Drehs")
	elseif kind == "Egg" then
		return tostring(prize.Name or (tostring(prize.Rarity) .. "-Ei"))
	end
	return tostring(prize.Name or "?")
end

local function buildOddsText(): string
	local prizes = wheelPrizes()
	local total = 0
	for _, prize in ipairs(prizes) do
		total += math.max(0, tonumber(prize.Weight) or 0)
	end
	local parts = {}
	for _, prize in ipairs(prizes) do
		local pct = if total > 0 then math.max(0, tonumber(prize.Weight) or 0) / total * 100 else 0
		table.insert(parts, displayName(prize) .. " " .. percentText(pct) .. "%")
	end
	return "🎲 Chancen: "
		.. table.concat(parts, " • ")
		.. "\n🥚 Ei = zufälliges Ei dieser Seltenheit (fliegt in deine Base)"
end

local function buildWheel()
	local r = WHEEL_RADIUS
	local wheelHeight = r * 2 + 44
	wheelWin = UI.Window("🎡 GLÜCKSRAD", 560, wheelHeight + 330, Color3.fromRGB(255, 120, 200))
	local content = wheelWin.Content
	local prizes = wheelPrizes()
	local count = segmentCount()
	local segAngle = 360 / count

	-- Das Rad sitzt FEST über dem scrollbaren Inhalt: gedrehte Teile würden von einem
	-- ScrollingFrame nicht abgeschnitten und beim Scrollen über die Kopfzeile ragen.
	local holder = UI.Create("Frame", {
		Name = "WheelHolder",
		Position = UDim2.fromOffset(12, 66),
		Size = UDim2.new(1, -24, 0, wheelHeight),
		BackgroundTransparency = 1,
		Parent = wheelWin.Panel,
	})
	content.Position = UDim2.fromOffset(12, 66 + wheelHeight + 6)
	content.Size = UDim2.new(1, -24, 1, -(66 + wheelHeight + 6 + 12))
	-- Rand: schwarz außen, goldener Ring mit Lämpchen
	circle({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, r + 26),
		Size = UDim2.fromOffset(r * 2 + 30, r * 2 + 30),
		BackgroundColor3 = BLACK,
		ZIndex = 1,
		Parent = holder,
	})
	local gold = circle({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, r + 26),
		Size = UDim2.fromOffset(r * 2 + 22, r * 2 + 22),
		BackgroundColor3 = WHITE,
		ZIndex = 2,
		Parent = holder,
	})
	UI.Create("UIGradient", {
		Rotation = 45,
		Color = ColorSequence.new(Color3.fromRGB(255, 230, 110), Color3.fromRGB(220, 140, 20)),
		Parent = gold,
	})
	for i = 1, LIGHT_COUNT do
		local angle = math.rad((i - 1) * 360 / LIGHT_COUNT)
		local dot = circle({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.sin(angle) * (r + 5.5), 0.5, -math.cos(angle) * (r + 5.5)),
			Size = UDim2.fromOffset(8, 8),
			BackgroundColor3 = LIGHT_ON,
			ZIndex = 3,
			Parent = gold,
		})
		table.insert(rimLights, dot)
	end
	setLights(false)

	-- Rotor: dreht sich, alles darin dreht mit
	wheelRotor = circle({
		Name = "Rotor",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, r + 26),
		Size = UDim2.fromOffset(r * 2, r * 2),
		BackgroundColor3 = Theme.PanelDark,
		ZIndex = 4,
		Parent = holder,
	})
	local spokeStep = segAngle / SPOKES_PER_SEGMENT
	-- Speichenbreite: deckt außen den Abstand zur nächsten Speiche (+1 px Überlappung)
	local outerWidth = math.ceil(2 * r * math.sin(math.rad(spokeStep / 2))) + 2
	local innerWidth = math.ceil(r * math.sin(math.rad(spokeStep / 2))) + 2
	for i = 1, count do
		local prize = prizes[i] or {}
		local color: Color3 = if typeof(prize.Color) == "Color3" then prize.Color else Color3.fromHSV(i / count, 0.7, 1)
		local first = (i - 1) * segAngle - segAngle / 2
		for k = 0, SPOKES_PER_SEGMENT - 1 do
			addSpoke(wheelRotor, first + (k + 0.5) * spokeStep, color, innerWidth, outerWidth, 5)
		end
	end
	-- Trennlinien zwischen den Feldern
	for i = 1, count do
		addSpoke(wheelRotor, (i - 1) * segAngle - segAngle / 2, BLACK, 3, 4, 6)
	end
	-- Beschriftung: Icon außen, Betrag in der Mitte des Felds (entlang des Radius)
	for i = 1, count do
		local prize = prizes[i] or {}
		local mid = (i - 1) * segAngle
		local rad = math.rad(mid)
		local textRotation = if mid > 180 then mid + 90 else mid - 90
		local iconScale: UIScale = UI.Create("UIScale")
		local icon = UI.Label({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.sin(rad) * r * 0.79, 0.5, -math.cos(rad) * r * 0.79),
			Size = UDim2.fromOffset(40, 40),
			Text = tostring(prize.Icon or "🎁"),
			Rotation = mid,
			MaxText = 32,
			ZIndex = 8,
			Parent = wheelRotor,
		})
		iconScale.Parent = icon
		local text = UI.Label({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.sin(rad) * r * 0.45, 0.5, -math.cos(rad) * r * 0.45),
			Size = UDim2.fromOffset(math.floor(r * 0.42), 22),
			Text = tostring(prize.Name or "?"),
			Rotation = textRotation,
			MaxText = 16,
			Outline = 2,
			ZIndex = 8,
			Parent = wheelRotor,
		})
		segmentIconScales[i] = iconScale
		segmentTexts[i] = text
	end
	-- dünner schwarzer Rand über den Speichen-Enden
	local rim = circle({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, r + 26),
		Size = UDim2.fromOffset(r * 2, r * 2),
		BackgroundTransparency = 1,
		ZIndex = 9,
		Parent = holder,
	})
	UI.Stroke(BLACK, 3).Parent = rim
	-- Nabe (dreht nicht mit – sie ist rund)
	local hub = circle({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, r + 26),
		Size = UDim2.fromOffset(62, 62),
		BackgroundColor3 = WHITE,
		ZIndex = 10,
		Parent = holder,
	})
	UI.Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(255, 235, 120), Color3.fromRGB(230, 150, 20)),
		Parent = hub,
	})
	UI.Stroke(BLACK, 3).Parent = hub
	UI.Label({ Size = UDim2.fromScale(1, 1), Text = "🎡", MaxText = 34, ZIndex = 11, Parent = hub })
	-- Zeiger oben
	wheelPointer = UI.Label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(46, 46),
		Text = "🔻",
		MaxText = 44,
		ZIndex = 12,
		Parent = holder,
	})

	spinInfo = UI.Label({
		Size = UDim2.new(1, 0, 0, 30),
		Text = "",
		TextColor3 = Theme.Yellow,
		LayoutOrder = 2,
		MaxText = 20,
		Outline = 2,
		Parent = content,
	})
	spinButton = UI.Button({
		Size = UDim2.new(1, 0, 0, 60),
		Text = "🎡 DREHEN!",
		Color = Theme.Orange,
		LayoutOrder = 3,
		MaxText = 30,
		Parent = content,
	}, function()
		Rewards.Spin()
	end)

	-- Drehs kaufen (Zufalls-Käufe: nur wo erlaubt, Chancen stehen darunter)
	productRow = UI.Row(content, 4, 48)
	productRow.Visible = false
	local Config = ctx.Config
	for order, key in ipairs({ "Spin1", "Spin10" }) do
		local product = Config.ProductsByKey and Config.ProductsByKey[key]
		if product then
			local button = UI.Button({
				Size = UDim2.new(0.5, -3, 1, 0),
				Text = displayName(product),
				Color = Theme.Purple,
				LayoutOrder = order,
				MaxText = 17,
				Parent = productRow,
			}, function()
				if product.Id ~= 0 then
					MarketplaceService:PromptProductPurchase(player, product.Id)
				end
			end)
			UI.FetchPrice(product.Id, Enum.InfoType.Product, function(price)
				if product.Id == 0 then
					button.SetText(displayName(product) .. " (bald)")
					button.SetColor(GRAY)
				elseif price then
					button.SetText(displayName(product) .. "  R$ " .. price)
				end
			end)
		end
	end
	UI.WhenRandomItemsKnown(function(allowed)
		productRow.Visible = allowed
	end)

	UI.Label({
		Size = UDim2.new(1, 0, 0, 58),
		Text = buildOddsText(),
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.SubText,
		TextWrapped = true,
		LayoutOrder = 5,
		MaxText = 13,
		Parent = content,
	})
end

function Rewards.RefreshWheel(state: any)
	if not state then
		return
	end
	for i, prize in ipairs(wheelPrizes()) do
		local label = segmentTexts[i]
		if label then
			local text = prizeAmountText(prize, state)
			if label.Text ~= text then
				label.Text = text
			end
		end
	end
	local summary = Rewards.Summary(state)
	local info
	if not summary.HasWheel then
		info = "🎡 Glücksrad wird geladen..."
	elseif summary.FreeReady then
		info = "🎡 Drehs: " .. summary.Spins .. "   •   🆓 Gratis-Dreh BEREIT!"
	else
		info = "🎡 Drehs: " .. summary.Spins .. "   •   🆓 Gratis-Dreh in " .. ctx.Util.FormatTime(summary.FreeIn)
	end
	if spinInfo.Text ~= info then
		spinInfo.Text = info
	end
	if spinning then
		spinButton.SetText("🎡 Dreht...")
		spinButton.SetColor(GRAY)
	elseif summary.FreeReady then
		spinButton.SetText("🆓 GRATIS DREHEN!")
		spinButton.SetColor(Theme.Green)
	elseif summary.Spins > 0 then
		spinButton.SetText("🎡 DREHEN!  (" .. summary.Spins .. ")")
		spinButton.SetColor(Theme.Orange)
	else
		spinButton.SetText("⏳ Keine Drehs")
		spinButton.SetColor(GRAY)
	end
end

-- Dreht den Rotor auf das Feld "segment" (1 = oben, im Uhrzeigersinn): Schwung holen, auslaufen,
-- leicht drüberrollen, zurückpendeln. Wartet, bis das Rad steht.
local function spinTo(segment: number)
	local count = segmentCount()
	local segAngle = 360 / count
	local start = wheelRotor.Rotation % 360
	wheelRotor.Rotation = start
	-- Der Zeiger oben zeigt auf den Rad-Winkel -Rotation -> Feld i steht oben bei -(i-1)*segAngle
	local target = (360 - (segment - 1) * segAngle) % 360 + (math.random() - 0.5) * segAngle * 0.5
	local final = start + 360 * SPIN_TURNS + (target - start) % 360
	local lastIndex = math.floor((start + segAngle / 2) / segAngle)
	local lastRotation = start
	local pointerAngle, pointerVelocity = 0, 0
	local pointerClock = 0
	local lightClock = 0
	local connection = RunService.RenderStepped:Connect(function(dt: number)
		local rotation = wheelRotor.Rotation
		local speed = if dt > 0 then math.abs(rotation - lastRotation) / dt else 0 -- Grad/s
		lastRotation = rotation
		-- Zeiger schnippt bei jedem vorbeisausenden Feld (je schneller, desto weiter)
		local index = math.floor((rotation + segAngle / 2) / segAngle)
		if index ~= lastIndex then
			lastIndex = index
			local kick = POINTER_KICK * math.clamp(speed / 500, 0.35, 1)
			pointerAngle = math.min(pointerAngle, -kick)
			pointerVelocity = math.min(pointerVelocity, 0)
		end
		-- Feder zurück in die Mitte (gedämpftes Nachwackeln), in kleinen festen Schritten
		pointerClock += math.min(dt, 0.1)
		while pointerClock >= POINTER_STEP do
			pointerClock -= POINTER_STEP
			local accel = -POINTER_STIFFNESS * pointerAngle - POINTER_DAMPING * pointerVelocity
			pointerVelocity += accel * POINTER_STEP
			pointerAngle += pointerVelocity * POINTER_STEP
		end
		wheelPointer.Rotation = math.clamp(pointerAngle, -POINTER_KICK - 6, 10)
		-- Lämpchen blinken schnell, solange das Rad schnell ist, und werden mit ihm langsamer
		lightClock += dt
		local interval = math.clamp(18 / math.max(speed, 1), 0.06, 0.35)
		if lightClock >= interval then
			lightClock = 0
			setLights(not lightsFlipped)
		end
	end)
	-- 1) Schwung holen
	local windup = TweenService:Create(wheelRotor, WINDUP_INFO, { Rotation = start - WINDUP_ANGLE })
	windup:Play()
	windup.Completed:Wait()
	-- 2) auslaufen (etwas über das Ziel hinaus) 3) zurückpendeln
	local over = final + segAngle * OVERSHOOT
	local tween = TweenService:Create(wheelRotor, SPIN_INFO, { Rotation = over })
	tween:Play()
	tween.Completed:Wait()
	local settle = TweenService:Create(wheelRotor, SETTLE_INFO, { Rotation = final })
	settle:Play()
	settle.Completed:Wait()
	-- Zeiger noch kurz auspendeln lassen
	task.wait(0.25)
	connection:Disconnect()
	wheelRotor.Rotation = final % 360
	wheelPointer.Rotation = 0
	setLights(false)
end

local function celebrate(segment: number)
	local scale = segmentIconScales[segment]
	if scale then
		scale.Scale = 1
		TweenService:Create(scale, WIN_POP_INFO, { Scale = 1.7 }):Play()
	end
	-- Lämpchen blinken zur Feier ein paar Mal schnell
	task.spawn(function()
		for _ = 1, 8 do
			setLights(not lightsFlipped)
			task.wait(0.09)
		end
		setLights(false)
	end)
end

function Rewards.Spin()
	if spinning then
		return
	end
	spinning = true
	Rewards.RefreshWheel(ctx.State)
	-- Geld/Schritte erst nach dem Drehen hochzählen lassen (sonst verrät die Anzeige den Gewinn)
	ctx.Hud.HoldCounters(true)
	local ok, result = ctx.RequestFull("Spin", nil, true)
	local message = if type(result) == "table" and type(result.Message) == "string" then result.Message else ""
	local segment = if type(result) == "table" then tonumber(result.Segment) else nil
	if ok and segment then
		local index = math.clamp(math.floor(segment), 1, segmentCount())
		local done, err = pcall(spinTo, index)
		if not done then
			warn("[Rewards] Glücksrad: " .. tostring(err))
		end
		celebrate(index)
	end
	ctx.Hud.HoldCounters(false)
	spinning = false
	if ok then
		ctx.Toast(if message ~= "" then message else "🎡 Gewonnen!", "Success")
		ctx.Effects.Play("Confetti", 1.5)
	else
		ctx.Toast(if message ~= "" then message else "🎡 Drehen hat nicht geklappt – nochmal!", "Error")
	end
	Rewards.RefreshWheel(ctx.State)
end

-- ---------------------------------------------------------------------
-- 📜 TAGESAUFGABEN
-- ---------------------------------------------------------------------
type QuestCard = {
	Card: Frame,
	Stroke: UIStroke,
	Title: TextLabel,
	Bar: UI.Bar,
	Reward: TextLabel,
	Button: UI.Button,
	Reroll: UI.Button, -- 🔄 einmal am Tag tauschen
}

local questCards: { QuestCard } = {}
local questHeader: TextLabel
local questEmpty: TextLabel

local function ensureQuestCard(i: number): QuestCard
	local existing = questCards[i]
	if existing then
		return existing
	end
	local card = UI.Card({ Size = UDim2.new(1, 0, 0, 128), LayoutOrder = 10 + i, Parent = questWin.Content })
	local stroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
	local title = UI.Label({
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 0, 30),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 22,
		Outline = 2,
		Parent = card,
	})
	local bar = UI.Bar({
		Position = UDim2.fromOffset(12, 44),
		Size = UDim2.new(1, -24, 0, 28),
		Color = Theme.Cyan,
		MaxText = 16,
		Parent = card,
	})
	local reward = UI.Label({
		Position = UDim2.new(0, 12, 1, -46),
		Size = UDim2.new(1, -246, 0, 36),
		Text = "",
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Cash,
		TextWrapped = true,
		MaxText = 15,
		Parent = card,
	})
	local button = UI.Button({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -10, 1, -8),
		Size = UDim2.fromOffset(160, 42),
		Text = "...",
		Color = GRAY,
		MaxText = 18,
		Parent = card,
	}, function()
		ctx.Request("ClaimQuest", i)
	end)
	-- 🔄 Tauschen (einmal am Tag, z.B. wenn keine anderen Spieler zum Bonken da sind)
	local reroll = UI.Button({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -178, 1, -8),
		Size = UDim2.fromOffset(50, 42),
		Text = "🔄",
		Color = Theme.Purple,
		MaxText = 22,
		Visible = false,
		Parent = card,
	}, function()
		ctx.Request("RerollQuest", i)
	end)
	local entry: QuestCard = {
		Card = card,
		Stroke = stroke,
		Title = title,
		Bar = bar,
		Reward = reward,
		Button = button,
		Reroll = reroll,
	}
	questCards[i] = entry
	return entry
end

local function buildQuests()
	questWin = UI.Window("📜 TAGESAUFGABEN", 540, 540, Theme.Cyan)
	local content = questWin.Content
	questHeader = UI.Label({
		Size = UDim2.new(1, 0, 0, 30),
		Text = "",
		TextColor3 = Theme.Yellow,
		LayoutOrder = 1,
		MaxText = 20,
		Outline = 2,
		Parent = content,
	})
	questEmpty = UI.Label({
		Size = UDim2.new(1, 0, 0, 40),
		Text = "📜 Aufgaben werden geladen...",
		Font = Enum.Font.GothamBold,
		TextColor3 = Theme.SubText,
		LayoutOrder = 2,
		MaxText = 16,
		Parent = content,
	})
	for i = 1, 3 do
		ensureQuestCard(i).Card.Visible = false
	end
end

-- Sekunden bis Mitternacht UTC (dann gibt es neue Aufgaben)
local function secondsToNewDay(): number
	return 86400 - os.time() % 86400
end

function Rewards.RefreshQuests(state: any)
	if not state then
		return
	end
	local Util = ctx.Util
	local list = if type(state.Quests) == "table" then state.Quests else {}
	local canReroll = state.QuestReroll == true
	local header = "⏰ Neue Aufgaben in "
		.. Util.FormatTime(secondsToNewDay())
		.. "  •  Belohnung: 💵 + 🎡"
		.. (if canReroll then "  •  🔄 1x tauschen" else "")
	if questHeader.Text ~= header then
		questHeader.Text = header
	end
	questEmpty.Visible = #list == 0
	for i, quest in ipairs(list) do
		local card = ensureQuestCard(i)
		card.Card.Visible = type(quest) == "table"
		if type(quest) == "table" then
			local goal = math.max(1, tonumber(quest.Goal) or 1)
			local progress = math.clamp(tonumber(quest.Progress) or 0, 0, goal)
			local done = progress >= goal
			local claimed = quest.Claimed == true
			local title = (if claimed then "✅ " else "") .. tostring(quest.Text or "???")
			if card.Title.Text ~= title then
				card.Title.Text = title
			end
			-- "Sammle $X ein" mit $, alles andere als Zahl
			local format = if quest.Kind == "Collect" then Util.FormatCash else Util.FormatNumber
			UI.SetBar(card.Bar, progress / goal, format(progress) .. " / " .. format(goal))
			local reward = "🎁 " .. tostring(quest.RewardText or "")
			if card.Reward.Text ~= reward then
				card.Reward.Text = reward
			end
			if claimed then
				card.Button.SetText("✅ Abgeholt")
				card.Button.SetColor(GRAY)
			elseif done then
				card.Button.SetText("🎁 Abholen!")
				card.Button.SetColor(Theme.Green)
			else
				card.Button.SetText("⏳ " .. math.floor(progress / goal * 100) .. "%")
				card.Button.SetColor(GRAY)
			end
			local showReroll = canReroll and not done and not claimed
			if card.Reroll.Frame.Visible ~= showReroll then
				card.Reroll.Frame.Visible = showReroll
			end
			local gold = done and not claimed
			local strokeColor = if gold then Theme.Gold else BLACK
			if card.Stroke.Color ~= strokeColor then
				card.Stroke.Color = strokeColor
				card.Stroke.Thickness = if gold then 4 else 2
			end
			card.Card.BackgroundTransparency = if claimed then 0.4 else 0
		end
	end
	for i = #list + 1, #questCards do
		questCards[i].Card.Visible = false
	end
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICH
-- ---------------------------------------------------------------------
-- Jede Sekunde (Countdowns in offenen Fenstern)
function Rewards.Tick()
	local state = ctx and ctx.State
	if not state then
		return
	end
	if giftWin.IsOpen then
		Rewards.RefreshGifts(state)
	end
	if wheelWin.IsOpen then
		Rewards.RefreshWheel(state)
	end
	if questWin.IsOpen then
		Rewards.RefreshQuests(state)
	end
end

function Rewards.Init(context: any)
	ctx = context
	buildGifts()
	buildWheel()
	buildQuests()
	ctx.Windows.Register("Gifts", giftWin, Rewards.RefreshGifts)
	ctx.Windows.Register("Wheel", wheelWin, Rewards.RefreshWheel)
	ctx.Windows.Register("Quests", questWin, Rewards.RefreshQuests)
end

return Rewards
