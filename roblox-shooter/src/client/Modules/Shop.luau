-- =====================================================================
--  CLUTCH CLASH – Shop-Fenster (Client/Modules/Shop)
--  Besitzer: WP9 (Wirtschaft, Monetarisierung, Kosmetik). Vertrag: DESIGN.md B21.1, B20, B22, B23, C7.4.
--  Tabs: Waffen (Münzen, "Gratis testen") · Täglich im Rampenlicht (6 Items −20 %, Timer) · Katalog ·
--  Kisten (Gem-Öffnung nur wenn erlaubt, mit Schlüssel immer) · Splitter · Gems & Pässe (Robux).
--  Kopf-Banner "ALLE WAFFEN ERSPIELBAR – KEIN PAY-TO-WIN". Vor JEDEM Kauf: "Details & Quoten".
--  Angezeigte Preise/Quoten kommen aus derselben Config wie der Server (Shop.PriceOf, Shared/Odds).
--  Außerdem: Kisten-Automat in der Lobby lokal verstecken, solange Zufallsitems nicht erlaubt sind;
--  VIP-Tür lokal öffnen (Player-Attribut "Vip").
--  Look: docs/STYLE-AKYTEX.md – Karten Surface2 mit 1-px-Rahmen, Seltenheit nur als Akzent (Rahmen + Streifen),
--  aktive Reiter Accent, Kaufen = Up (grün), Robux/Premium = Warn-Verlauf, Werte grün/rot.
--
--  Öffentliche API (C7.4):
--    Shop.Open(tab?)                        "Weapons" | "Featured" | "Catalog" | "Crates" | "Shards" | "Robux"
--    Shop.BuildStarterCard(parent): GuiObject?   Starter-Angebot (Ergebnis-Bildschirm, großer "Später"-Knopf)
-- =====================================================================

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Lang = require(Shared:WaitForChild("Lang"))
local Util = require(Shared:WaitForChild("Util"))
local Odds = require(Shared:WaitForChild("Odds"))

local Shop = {}
local ctx: any = nil
local UI: any = nil

local SHOP: any = Config.Shop
local COSMETICS: any = Config.Cosmetics
local TABS = { "Weapons", "Featured", "Catalog", "Crates", "Shards", "Robux" }
-- andere Namen, die Pakete/Prompts benutzen (z. B. Progress: Shop.Open("Pass"))
local TAB_ALIASES: { [string]: string } =
	{ Pass = "Robux", Passes = "Robux", Gems = "Robux", Crate = "Crates", Weapon = "Weapons", Spotlight = "Featured" }
local TAB_KEYS: { [string]: { string } } = {
	Weapons = { "Coins", "Weapons", "FreeWeaponPicks" },
	Featured = { "Featured", "Cosmetics", "Gems" },
	Catalog = { "Cosmetics", "Coins", "Gems", "Season" },
	Crates = { "Crates", "Keys", "Gems", "RandomAllowed" },
	Shards = { "Shards", "Cosmetics" },
	Robux = { "Passes", "Offer", "Boosts", "Pass" },
}
local CURRENCY_ICON: { [string]: string } = { Coins = "💰", Gems = "💎", Keys = "🔑", Shards = "🧩" }
local KIND_ORDER = { "Wrap", "Skin", "Charm", "Finisher", "Tracer" }
local KIND_ICON: { [string]: string } =
	{ Wrap = "🎨", Skin = "🔫", Charm = "🧸", Finisher = "✨", Tracer = "〰️" }
local SLOT_ORDER: { [string]: number } = { Primary = 1, Secondary = 2, Melee = 3, Utility = 4 }
local FIND_TRIES = 40 -- Lobby-Objekte (Kisten-Automat, VIP-Tür) so oft suchen (alle 3 s)
local TICKER_MAX = 36000 -- Rampenlicht-Timer: höchstens so viele Sekunden-Schritte pro Öffnung

local win: any = nil
local body: Frame? = nil
local dialog: Frame? = nil
local dialogList: ScrollingFrame? = nil
local dialogButtons: Frame? = nil
local dialogTitle: TextLabel? = nil
local dialogAccent: Frame? = nil
local tabButtons: { [string]: any } = {}
local currencyLabels: { [string]: TextLabel } = {}
local currentTab = "Weapons"
local pending = false
local renderQueued = false
local tickerToken = 0
local crateMachine: Instance? = nil
local crateMachineParent: Instance? = nil
local vipDoor: BasePart? = nil

-- =====================================================================
-- 1) HELFER
-- =====================================================================
local function lang(): "de" | "en"
	local ok, value = pcall(function()
		return ctx.Lang_()
	end)
	return if ok and value == "de" then "de" else "en"
end

local function t(key: string, ...: any): string
	return Lang.T(lang(), key, ...)
end

local function state(): { [string]: any }
	return if ctx and type(ctx.State) == "table" then ctx.State else {}
end

local function num(n: any): string
	return Util.FormatNumber(tonumber(n) or 0)
end

local function balance(currency: string): number
	return tonumber(state()[currency]) or 0
end

local function rarityColor(rarity: any): Color3
	local colors = Config.Colors and Config.Colors.Rarity
	return colors and colors[rarity] or UI.Theme.Gray
end

local function pick(name: any): string
	return if type(name) == "table" then Lang.Pick(lang(), name) else tostring(name)
end

local function seasonId(): number
	local season = state().Season
	if type(season) == "table" and type(season.Id) == "number" then
		return season.Id
	end
	return SHOP.SeasonIdAt(Config.Season and Config.Season.Seasons, os.time())
end

local function ownsCosmetic(id: string): boolean
	local cos = state().Cosmetics
	return type(cos) == "table" and type(cos.Owned) == "table" and cos.Owned[id] == true
end

local function ownsWeapon(key: string, def: any): boolean
	if def and def.Free then
		return true
	end
	local weapons = state().Weapons
	return type(weapons) == "table" and type(weapons.Owned) == "table" and weapons.Owned[key] == true
end

local function hasPass(key: string): boolean
	local passes = state().Passes
	return type(passes) == "table" and passes[key] == true
end

local function randomAllowed(): boolean?
	local ok, value = pcall(UI.RandomItemsAllowed)
	if ok then
		return value
	end
	local raw = state().RandomAllowed
	return if type(raw) == "boolean" then raw else nil
end

local function decimalSep(): string
	return if lang() == "de" then "," else "."
end

local function percent(hundredths: number): string
	return Odds.FormatPercent(hundredths, decimalSep()) .. " %"
end

local function changedHas(changed: any, key: string): boolean
	if type(changed) ~= "table" then
		return true
	end
	return changed[key] == true or table.find(changed, key) ~= nil
end

local function clear(frame: Instance)
	for _, child in ipairs(frame:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

-- Anfrage an den Server; Doppelklick-Schutz bis zur Antwort (MH-Fix §14.1 #4)
local function request(action: string, arg: any, onOk: ((any) -> ())?)
	if pending then
		return
	end
	pending = true
	task.spawn(function()
		local ok, reply = pcall(ctx.RequestFull, action, arg, true) -- silent: Meldung zeigen wir selbst
		pending = false
		if not ok or type(reply) ~= "table" then
			ctx.Toast(t("shop.noAnswer"), "Error")
			return
		end
		if type(reply.Message) == "string" and reply.Message ~= "" then
			ctx.Toast(reply.Message, if reply.Ok then "Success" else "Error")
		end
		if reply.Ok and onOk then
			onOk(reply)
		end
	end)
end

local function modules(): { [string]: any }
	return if ctx and type(ctx.Modules) == "table" then ctx.Modules else {}
end

-- Karte (Surface2, Ecke 12, 1-px-Rahmen); accent = Seltenheit/Premium nur als Rahmen + Streifen oben
local function accentCard(props: { [string]: any }, accent: Color3?): Frame
	local frame = UI.Card(props)
	if accent then
		local stroke = frame:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = accent
			stroke.Transparency = 0.45
		end
		UI.Create("Frame", {
			Name = "Stripe",
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -28, 0, 3),
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
			Parent = frame,
		}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	end
	return frame
end

-- Schlanke Pill (Chip): Surface2 + Rahmen, kleiner Punkt in der Akzentfarbe
local function pill(parent: Instance, textValue: string, order: number, width: number, dot: Color3?): TextLabel
	local frame = UI.Create("Frame", {
		Size = UDim2.fromOffset(width, 30),
		BackgroundColor3 = UI.Theme.Surface2,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Parent = parent,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }), UI.Stroke(nil, 1) })
	if dot then
		UI.Create("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 12, 0.5, 0),
			Size = UDim2.fromOffset(8, 8),
			BackgroundColor3 = dot,
			BorderSizePixel = 0,
			Parent = frame,
		}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	end
	return UI.Label({
		Position = UDim2.fromOffset(if dot then 26 else 12, 4),
		Size = UDim2.new(1, if dot then -36 else -24, 1, -8),
		Text = textValue,
		Font = UI.Fonts.Main,
		TextColor3 = UI.Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 16,
		Parent = frame,
	})
end

-- =====================================================================
-- 2) "DETAILS & QUOTEN" – Dialog vor jedem Kauf
-- =====================================================================
-- Variant: "Success" (Kaufen, Standard) | "Primary" | "Premium" (Robux) | "Secondary"
type DialogButton = { Text: string, Variant: string?, OnClick: (() -> ())?, Enabled: boolean? }
type DialogSpec = { Title: string, Color: Color3?, Lines: { string }, Crate: any?, Buttons: { DialogButton } }

local function hideDialog()
	if dialog then
		dialog.Visible = false
	end
end

local function addLine(parent: Instance, textValue: string, order: number, color: Color3?, height: number?)
	UI.Label({
		Size = UDim2.new(1, -8, 0, height or 26),
		Text = textValue,
		Font = UI.Fonts.Body,
		TextColor3 = color or UI.Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		MaxText = 17,
		LayoutOrder = order,
		Parent = parent,
	})
end

local function addOdds(parent: Instance, crateDef: any, startOrder: number): number
	local order = startOrder
	addLine(parent, t("shop.odds.byRarity"), order, UI.Theme.Text2)
	order += 1
	for _, row in ipairs(Odds.RarityTable(crateDef, false)) do
		addLine(
			parent,
			("%s (%d): %s"):format(t("item.rarity." .. row.Rarity), row.Count, percent(row.Hundredths)),
			order,
			rarityColor(row.Rarity)
		)
		order += 1
	end
	addLine(parent, t("shop.odds.items"), order, UI.Theme.Text2)
	order += 1
	local total = 0
	for _, row in ipairs(Odds.Table(crateDef)) do
		local def = COSMETICS.ById[row.Id]
		local name = if def then pick(def.Name) else row.Id
		local kind = if def then t("item.kind." .. def.Kind) else ""
		addLine(parent, ("%s – %s: %s"):format(name, kind, percent(row.Hundredths)), order, rarityColor(row.Rarity))
		total += row.Hundredths
		order += 1
	end
	addLine(parent, t("shop.odds.sum", percent(total)), order, UI.Theme.Up)
	order += 1
	local pityAfter = tonumber(crateDef.PityAfter) or 29
	addLine(parent, t("shop.odds.pityRule", pityAfter, pityAfter + 1), order, UI.Theme.Warn, 46)
	order += 1
	for _, row in ipairs(Odds.PityTable(crateDef)) do
		local def = COSMETICS.ById[row.Id]
		addLine(
			parent,
			("  %s: %s"):format(if def then pick(def.Name) else row.Id, percent(row.Hundredths)),
			order,
			rarityColor(row.Rarity)
		)
		order += 1
	end
	addLine(
		parent,
		t(
			"shop.odds.dupes",
			SHOP.DupeShards.Common,
			SHOP.DupeShards.Rare,
			SHOP.DupeShards.Epic,
			SHOP.DupeShards.Legendary,
			SHOP.DupeShards.Mythic
		),
		order,
		UI.Theme.Text2,
		46
	)
	return order + 1
end

local function showDialog(spec: DialogSpec)
	local frame, list, buttons, title = dialog, dialogList, dialogButtons, dialogTitle
	if not (frame and list and buttons and title) then
		return
	end
	title.Text = UI.Upper(t("shop.oddsTitle") .. " · " .. spec.Title)
	local accent = dialogAccent
	if accent then
		accent.BackgroundColor3 = spec.Color or UI.Theme.Accent
	end
	clear(list)
	clear(buttons)
	local order = 1
	for _, line in ipairs(spec.Lines) do
		addLine(list, line, order, UI.Theme.Text2, 28)
		order += 1
	end
	if spec.Crate then
		addOdds(list, spec.Crate, order)
	end
	list.CanvasPosition = Vector2.zero
	for i, button in ipairs(spec.Buttons) do
		local enabled = button.Enabled ~= false
		UI.Button({
			Size = UDim2.fromOffset(200, 46),
			Text = button.Text,
			Variant = if enabled then (button.Variant or "Success") else "Muted",
			MaxText = 17,
			LayoutOrder = i,
			Parent = buttons,
		}, function()
			if enabled and button.OnClick then
				hideDialog()
				button.OnClick()
			end
		end)
	end
	UI.Button({
		Size = UDim2.fromOffset(150, 46),
		Text = t("shop.cancel"),
		Variant = "Secondary",
		MaxText = 17,
		LayoutOrder = 99,
		Parent = buttons,
	}, hideDialog)
	frame.Visible = true
end

local function buildDialog(panel: Frame)
	-- Detail-Dialog über dem Fenster-Inhalt: Bg-Glas, Ecke 16, 1-px-Rahmen, Titel Michroma + Akzentstrich
	local frame = UI.Create("Frame", {
		Name = "Details",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UI.Theme.Bg,
		BackgroundTransparency = 0.03,
		Visible = false,
		Active = true,
		ZIndex = 30,
		Parent = panel,
	}, { UI.Corner(16), UI.Stroke(nil, 1) })
	dialogTitle = UI.Label({
		Position = UDim2.fromOffset(20, 14),
		Size = UDim2.new(1, -40, 0, 28),
		Text = "",
		Font = UI.Fonts.Heading,
		TextColor3 = UI.Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 20,
		Parent = frame,
	})
	dialogAccent = UI.Create("Frame", {
		Name = "Accent",
		Position = UDim2.fromOffset(20, 46),
		Size = UDim2.fromOffset(28, 2),
		BackgroundColor3 = UI.Theme.Accent,
		BorderSizePixel = 0,
		Parent = frame,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	dialogList = UI.Create("ScrollingFrame", {
		Position = UDim2.fromOffset(20, 58),
		Size = UDim2.new(1, -40, 1, -132),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = UI.Theme.Muted,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = frame,
	}, { UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }) })
	dialogButtons = UI.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -32, 0, 56),
		BackgroundTransparency = 1,
		Parent = frame,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 10),
		}),
	})
	dialog = frame
end

-- =====================================================================
-- 3) KARTEN
-- =====================================================================
-- Karte im Raster: Titel (Text), bis zu 3 Zeilen (Text2; lineColors färbt einzelne Zeilen grün/rot),
-- Knopf unten (Variante). accent = Seltenheit/Premium nur als Rahmen + Streifen.
local function card(
	parent: Instance,
	order: number,
	titleText: string,
	accent: Color3?,
	lines: { string },
	buttonText: string,
	buttonVariant: string,
	onClick: () -> (),
	enabled: boolean?,
	lineColors: { [number]: Color3 }?
): (Frame, { TextLabel })
	local frame = accentCard({ Size = UDim2.fromOffset(180, 156), LayoutOrder = order, Parent = parent }, accent)
	local lineLabels: { TextLabel } = {}
	UI.Label({
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.new(1, -24, 0, 24),
		Text = titleText,
		Font = UI.Fonts.Main,
		TextColor3 = UI.Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		MaxText = 17,
		Parent = frame,
	})
	for i, line in ipairs(lines) do
		if i > 3 then
			break
		end
		table.insert(
			lineLabels,
			UI.Label({
				Position = UDim2.fromOffset(12, 36 + (i - 1) * 20),
				Size = UDim2.new(1, -24, 0, 19),
				Text = line,
				Font = if lineColors and lineColors[i] then UI.Fonts.Main else UI.Fonts.Body,
				TextColor3 = lineColors and lineColors[i] or UI.Theme.Text2,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				MaxText = 14,
				Parent = frame,
			})
		)
	end
	local on = enabled ~= false
	UI.Button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -20, 0, 38),
		Text = buttonText,
		Variant = if on then buttonVariant else "Muted",
		MaxText = 15,
		Corner = 10,
		Parent = frame,
	}, function()
		if on then
			onClick()
		end
	end)
	return frame, lineLabels
end

local function grid(parent: Instance, order: number): Frame
	return UI.Grid(parent, order, 180, 156)
end

-- =====================================================================
-- 4) KOSMETIK-KAUF (Katalog, Rampenlicht, Splitter)
-- =====================================================================
local function cosmeticLines(def: any): { string }
	local lines = { t("item.kind." .. def.Kind) .. " · " .. t("item.rarity." .. tostring(def.Rarity)) }
	if def.Kind == "Skin" and type(def.Weapon) == "string" then
		local weapon = Config.Weapon(def.Weapon)
		table.insert(lines, t("shop.forWeapon", if weapon then pick(weapon.Name) else def.Weapon))
	elseif def.Kind == "Wrap" or def.Kind == "Charm" then
		table.insert(lines, t("shop.anyWeapon"))
	end
	if def.Anim then
		table.insert(lines, t("shop.animated"))
	end
	return lines
end

local function openCosmeticDetails(id: string, currencies: { string }, featured: boolean)
	local def = COSMETICS.ById[id]
	if def == nil then
		return
	end
	local lines = cosmeticLines(def)
	table.insert(lines, t("item.source." .. tostring(def.Source)))
	table.insert(lines, t("shop.cosmeticOnly"))
	local buttons: { DialogButton } = {}
	local owned = ownsCosmetic(id)
	for _, currency in ipairs(currencies) do
		local price = SHOP.PriceOf(COSMETICS, id, currency, seasonId(), featured and currency == "Gems")
		if price then
			table.insert(buttons, {
				Text = ("%s %s %s"):format(t("shop.buy"), num(price), CURRENCY_ICON[currency]),
				Variant = "Success",
				Enabled = not owned and balance(currency) >= price,
				OnClick = function()
					request("BuyItem", { Id = id, Currency = currency, Featured = featured or nil })
				end,
			})
		end
	end
	if owned then
		table.insert(lines, t("shop.ownedLine"))
	end
	showDialog({ Title = pick(def.Name), Color = rarityColor(def.Rarity), Lines = lines, Buttons = buttons })
end

local function cosmeticCard(parent: Instance, order: number, id: string, currencies: { string }, featured: boolean)
	local def = COSMETICS.ById[id]
	if def == nil then
		return
	end
	local owned = ownsCosmetic(id)
	local priceText = ""
	local affordable = false
	for _, currency in ipairs(currencies) do
		local price = SHOP.PriceOf(COSMETICS, id, currency, seasonId(), featured and currency == "Gems")
		if price then
			local base = if featured and currency == "Gems"
				then SHOP.PriceOf(COSMETICS, id, currency, seasonId(), false)
				else nil
			local part = if base and base ~= price
				then ("%s→%s %s"):format(num(base), num(price), CURRENCY_ICON[currency])
				else ("%s %s"):format(num(price), CURRENCY_ICON[currency])
			priceText = if priceText == "" then part else priceText .. " / " .. part
			affordable = affordable or balance(currency) >= price
		end
	end
	local lines =
		{ (KIND_ICON[def.Kind] or "") .. " " .. t("item.kind." .. def.Kind), t("item.rarity." .. tostring(def.Rarity)) }
	table.insert(lines, if owned then "✓ " .. t("shop.ownedLine") else priceText)
	-- Werte grün/rot: besessen bzw. leistbar = Up, zu teuer = Down; Seltenheit als Zeilen-Akzent
	local colors = {
		[2] = rarityColor(def.Rarity),
		[3] = if owned or affordable then UI.Theme.Up else UI.Theme.Down,
	}
	card(parent, order, pick(def.Name), rarityColor(def.Rarity), lines, t("shop.details"), "Secondary", function()
		openCosmeticDetails(id, currencies, featured)
	end, true, colors)
end

local function sortedCosmetics(filter: (id: string, def: any) -> boolean): { string }
	local list: { string } = {}
	for id, def in pairs(COSMETICS.ById) do
		if filter(id, def) then
			table.insert(list, id)
		end
	end
	table.sort(list, function(a, b)
		local da, db = COSMETICS.ById[a], COSMETICS.ById[b]
		local ra = COSMETICS.RarityRank[da.Rarity] or 0
		local rb = COSMETICS.RarityRank[db.Rarity] or 0
		if ra ~= rb then
			return ra < rb
		end
		return a < b
	end)
	return list
end

-- =====================================================================
-- 5) TABS
-- =====================================================================
local Builders: { [string]: (Frame) -> () } = {}

-- "Gratis testen": erst in den Schießstand teleportieren (QueueService "GoRange"), dann das Training-Fenster
-- (Waffenwahl der Range) öffnen. Früher öffnete der Knopf nur das Fenster in der Lobby (Läufe gehen nur in der Range).
local function tryInRange()
	request("GoRange", nil, function()
		ctx.Windows.Close("Shop")
		local training = modules().Training
		if training and type(training.Open) == "function" then
			task.delay(0.6, function()
				pcall(training.Open)
			end)
		else
			ctx.Toast(t("shop.tryHint"), "Info")
		end
	end)
end

Builders.Weapons = function(root)
	local list = Config.Weapons and Config.Weapons.List
	if type(list) ~= "table" or #list == 0 then
		addLine(root, t("shop.noWeapons"), 1)
		return
	end
	local weapons = {}
	for _, def in ipairs(list) do
		if type(def) == "table" and not def.AdminOnly then
			table.insert(weapons, def)
		end
	end
	table.sort(weapons, function(a, b)
		local sa, sb = SLOT_ORDER[a.Slot] or 9, SLOT_ORDER[b.Slot] or 9
		if sa ~= sb then
			return sa < sb
		end
		return (a.Id or 0) < (b.Id or 0)
	end)
	-- Gratis-Waffen-Wahl: State-Schlüssel "FreeWeaponPicks" (WP8), sonst Weapons.FreePicks (WP9)
	local freePicks = tonumber(state().FreeWeaponPicks)
	if freePicks == nil then
		local weaponsState = state().Weapons
		freePicks = if type(weaponsState) == "table" then tonumber(weaponsState.FreePicks) or 0 else 0
	end
	if freePicks > 0 then
		addLine(root, t("shop.freePicks", freePicks), 1, UI.Theme.Up)
	end
	local g = grid(root, 2)
	for i, def in ipairs(weapons) do
		local owned = ownsWeapon(def.Key, def)
		local lines = { t("shop.slot." .. tostring(def.Slot)) }
		if def.Enabled == false then
			table.insert(lines, t("shop.weaponOff"))
		end
		local priceLine = if def.Free
			then t("shop.free")
			elseif owned then "✓ " .. t("shop.ownedLine")
			else ("%s 💰"):format(num(def.Price))
		table.insert(lines, priceLine)
		-- grün = besessen/gratis/leistbar, rot = zu teuer (letzte Zeile) bzw. per Not-Aus gesperrt
		local affordable = balance("Coins") >= (tonumber(def.Price) or math.huge)
		local colors: { [number]: Color3 } = {
			[#lines] = if def.Free or owned or affordable then UI.Theme.Up else UI.Theme.Down,
		}
		if def.Enabled == false then
			colors[2] = UI.Theme.Down
		end
		card(g, i, pick(def.Name), nil, lines, t("shop.details"), "Secondary", function()
			local buttons: { DialogButton } = {}
			if not owned then
				table.insert(buttons, {
					Text = ("%s %s 💰"):format(t("shop.buy"), num(def.Price)),
					Variant = "Success",
					Enabled = affordable,
					OnClick = function()
						request("BuyWeapon", def.Key)
					end,
				})
				if freePicks > 0 then
					table.insert(buttons, {
						Text = t("shop.pickFree"),
						Variant = "Primary",
						OnClick = function()
							request("ClaimLevelPick", def.Key)
						end,
					})
				end
			end
			-- "Gratis testen" (B21.1): in den Schießstand (Range) und dort das Training-Fenster öffnen
			table.insert(buttons, {
				Text = t("shop.tryFree"),
				Variant = "Secondary",
				OnClick = tryInRange,
			})
			local detail = {
				t("shop.slot." .. tostring(def.Slot)),
				t("shop.weaponStats", tonumber(def.Damage) or 0, tonumber(def.Mag) or 0),
				t("shop.noP2WShort"),
			}
			showDialog({ Title = pick(def.Name), Lines = detail, Buttons = buttons })
		end, true, colors)
	end
end

local function updateTicker(label: TextLabel, endsAt: number)
	tickerToken += 1
	local token = tickerToken
	task.spawn(function()
		for _ = 1, TICKER_MAX do
			if token ~= tickerToken or not (win and win.IsOpen) or label.Parent == nil then
				return
			end
			local left = math.max(0, endsAt - workspace:GetServerTimeNow())
			label.Text = t("shop.featuredTimer", Util.FormatTime(math.floor(left)))
			task.wait(1)
		end
	end)
end

Builders.Featured = function(root)
	local featured = state().Featured
	if type(featured) ~= "table" or type(featured.Ids) ~= "table" then
		addLine(root, t("core.loading"), 1)
		return
	end
	local timerRow = UI.Row(root, 1, 32)
	local timer = pill(timerRow, "", 1, 300, UI.Theme.Warn)
	updateTicker(timer, tonumber(featured.EndsAt) or 0)
	local g = grid(root, 2)
	for i, id in ipairs(featured.Ids) do
		cosmeticCard(g, i, id, { "Gems" }, true)
	end
end

Builders.Catalog = function(root)
	local season = seasonId()
	local order = 1
	for _, kind in ipairs(KIND_ORDER) do
		local ids = sortedCosmetics(function(id, def)
			return def.Kind == kind
				and (
					SHOP.PriceOf(COSMETICS, id, "Gems", season, false) ~= nil
					or SHOP.PriceOf(COSMETICS, id, "Coins", season, false) ~= nil
				)
		end)
		if #ids > 0 then
			UI.Section(root, t("item.kinds." .. kind), order)
			order += 1
			local g = grid(root, order)
			order += 1
			for i, id in ipairs(ids) do
				cosmeticCard(g, i, id, { "Coins", "Gems" }, false)
			end
		end
	end
end

local function openCrate(use: string)
	request("OpenCrate", { Crate = "S1", Use = use }, function(reply)
		local reveal = modules().CrateReveal
		if reply.Result and reveal and type(reveal.Play) == "function" then
			reveal.Play(reply.Result)
		end
	end)
end

Builders.Crates = function(root)
	local crateDef = SHOP.Crates.S1
	local crates = state().Crates
	local pity = if type(crates) == "table" then tonumber(crates.Pity) or 0 else 0
	local pityAfter = tonumber(crateDef.PityAfter) or 29
	local allowed = randomAllowed()
	UI.Section(root, pick(crateDef.Name), 1)
	local left = pityAfter + 1 - pity
	local infoRow = UI.Row(root, 2, 32)
	pill(infoRow, if left <= 1 then t("shop.pityNext") else t("shop.pityLeft", left), 1, 300, UI.Theme.Warn)
	pill(
		infoRow,
		t("shop.keysHave", balance("Keys")),
		2,
		220,
		if balance("Keys") >= 1 then UI.Theme.Up else UI.Theme.Down
	)
	local row = UI.Row(root, 4, 54)
	local keys = balance("Keys")
	UI.Button({
		Size = UDim2.fromOffset(220, 48),
		Text = t("shop.oddsTitle"),
		Variant = "Secondary",
		LayoutOrder = 1,
		Parent = row,
	}, function()
		showDialog({ Title = pick(crateDef.Name), Lines = { t("shop.crateIntro") }, Crate = crateDef, Buttons = {} })
	end)
	UI.Button({
		Size = UDim2.fromOffset(240, 48),
		Text = t("shop.openKey"),
		Variant = if keys >= 1 then "Primary" else "Muted",
		LayoutOrder = 2,
		Parent = row,
	}, function()
		showDialog({
			Title = pick(crateDef.Name),
			Lines = { t("shop.crateIntro") },
			Crate = crateDef,
			Buttons = {
				{
					Text = t("shop.openKey"),
					Variant = "Primary",
					Enabled = keys >= 1,
					OnClick = function()
						openCrate("Key")
					end,
				},
			},
		})
	end)
	if allowed == true then -- Gem-Öffnung nur, wenn bezahlte Zufallsitems erlaubt sind (B20.2)
		local price = tonumber(crateDef.GemPrice) or 120
		UI.Button({
			Size = UDim2.fromOffset(240, 48),
			Text = t("shop.openGems", price),
			Variant = if balance("Gems") >= price then "Primary" else "Muted",
			LayoutOrder = 3,
			Parent = row,
		}, function()
			showDialog({
				Title = pick(crateDef.Name),
				Lines = { t("shop.crateIntro") },
				Crate = crateDef,
				Buttons = {
					{
						Text = t("shop.openGems", price),
						Variant = "Primary",
						Enabled = balance("Gems") >= price,
						OnClick = function()
							openCrate("Gems")
						end,
					},
				},
			})
		end)
	elseif allowed == false then
		addLine(root, t("shop.restricted") .. " – " .. t("shop.keysStillOk"), 5, UI.Theme.Text2)
	end
	addLine(root, t("shop.crateSingle"), 6, UI.Theme.Muted)
	local g = grid(root, 7)
	for i, item in ipairs(crateDef.Items) do
		local def = COSMETICS.ById[item.Id]
		if def then
			local lines = { t("item.kind." .. def.Kind), percent(item.Weight) }
			if ownsCosmetic(item.Id) then
				table.insert(lines, "✓ " .. t("shop.ownedLine"))
			end
			card(g, i, pick(def.Name), rarityColor(item.Rarity), lines, t("shop.details"), "Secondary", function()
				openCosmeticDetails(item.Id, { "Gems" }, false)
			end, true, { [2] = rarityColor(item.Rarity), [3] = UI.Theme.Up })
		end
	end
end

Builders.Shards = function(root)
	local shardRow = UI.Row(root, 1, 32)
	pill(shardRow, t("shop.shardsHave", balance("Shards")), 1, 260, UI.Theme.Accent)
	addLine(root, t("shop.shardsIntro"), 2, UI.Theme.Text2, 40)
	local g = grid(root, 3)
	local items = table.clone(SHOP.Crates.S1.Items)
	table.sort(items, function(a, b)
		local ra = COSMETICS.RarityRank[a.Rarity] or 0
		local rb = COSMETICS.RarityRank[b.Rarity] or 0
		if ra ~= rb then
			return ra < rb
		end
		return a.Id < b.Id
	end)
	for i, item in ipairs(items) do
		cosmeticCard(g, i, item.Id, { "Shards" }, false)
	end
end

-- Robux-Produkte: Beschreibung aus dem Grant
local function productLines(product: any): { string }
	local lines: { string } = {}
	local grant = product.Grant or {}
	local offer = state().Offer
	local firstUsed = type(offer) == "table"
		and type(offer.FirstPack) == "table"
		and offer.FirstPack[product.Key] == true
	if type(grant.Gems) == "number" then
		table.insert(lines, ("+%s 💎"):format(num(grant.Gems)))
		if product.FirstBonus and not firstUsed then
			table.insert(lines, t("shop.firstX2"))
		end
	end
	if grant.PassPremium then
		table.insert(lines, t("shop.desc.premium"))
	end
	if type(grant.PassTiers) == "number" then
		table.insert(lines, t("shop.desc.tiers", grant.PassTiers))
	end
	if type(grant.XpBoostSeconds) == "number" then
		table.insert(lines, t("shop.desc.xpBoost", Util.FormatTime(grant.XpBoostSeconds)))
	end
	if product.PartyBoost then
		table.insert(lines, t("shop.desc.party"))
	end
	if product.Supporter then
		table.insert(lines, t("shop.desc.support"))
	end
	if type(grant.Cosmetics) == "table" then
		for _, id in ipairs(grant.Cosmetics) do
			local def = COSMETICS.ById[id]
			if def then
				table.insert(lines, "+ " .. pick(def.Name) .. " (" .. t("item.kind." .. def.Kind) .. ")")
			end
		end
	end
	if product.Once then
		table.insert(lines, t("shop.desc.once", tonumber(product.Fallback and product.Fallback.Gems) or 0))
	elseif product.PerSeason then
		table.insert(lines, t("shop.desc.perSeason", tonumber(SHOP.PassOwnedGems) or 500))
	elseif product.Kind == "Tiers" then
		table.insert(lines, t("shop.desc.tierRest", tonumber(SHOP.TierGemFallback) or 40))
	end
	table.insert(lines, t("shop.noP2WShort"))
	return lines
end

local function robuxButtonText(entry: any, livePrice: number?): string
	if (tonumber(entry.Id) or 0) <= 0 then
		return t("shop.notSetUp")
	end
	return ("%s R$ %s"):format(t("shop.buy"), num(livePrice or entry.Price))
end

local function promptRobux(entry: any, isPass: boolean)
	local id = tonumber(entry.Id) or 0
	if id <= 0 then
		ctx.Toast(t("shop.notSetUp"), "Info")
		return
	end
	local player = ctx.Player or Players.LocalPlayer
	local ok, err = pcall(function()
		if isPass then
			MarketplaceService:PromptGamePassPurchase(player, id)
		else
			MarketplaceService:PromptProductPurchase(player, id)
		end
	end)
	if not ok then
		warn("[Shop] Kauf-Dialog: " .. tostring(err))
	end
end

local function robuxCard(parent: Instance, order: number, entry: any, isPass: boolean)
	local lines = if isPass then { pick(entry.Desc) } else productLines(entry)
	local owned = isPass and hasPass(entry.Key)
	local ready = (tonumber(entry.Id) or 0) > 0
	local livePrice: number? = nil
	local priceLine = if owned
		then t("shop.ownedLine")
		elseif ready then ("R$ %s"):format(num(entry.Price))
		else t("shop.notSetUp")
	local _, labels = card(
		parent,
		order,
		(entry.Icon or "") .. " " .. pick(entry.Name),
		UI.Theme.Warn, -- Premium/Robux = Warn-Akzent
		{ lines[1] or "", priceLine },
		t("shop.details"),
		if ready then "Secondary" else "Muted",
		function()
			local buttons: { DialogButton } = {}
			if not owned then
				table.insert(buttons, {
					Text = robuxButtonText(entry, livePrice),
					Variant = "Premium",
					Enabled = ready,
					OnClick = function()
						promptRobux(entry, isPass)
					end,
				})
			end
			showDialog({ Title = pick(entry.Name), Color = UI.Theme.Warn, Lines = lines, Buttons = buttons })
		end,
		true,
		{ [2] = if owned then UI.Theme.Up elseif ready then UI.Theme.Warn else UI.Theme.Muted }
	)
	-- echter Preis aus Roblox (falls der Besitzer ihn im Dashboard geändert hat)
	if ready and not owned then
		local priceLabel = labels[2]
		UI.FetchPrice(
			entry.Id,
			if isPass then Enum.InfoType.GamePass else Enum.InfoType.Product,
			function(price: number?)
				if price then
					livePrice = price
					if priceLabel and priceLabel.Parent then
						priceLabel.Text = ("R$ %s"):format(num(price))
					end
				end
			end
		)
	end
end

local function starterVisible(): boolean
	local offer = state().Offer
	if type(offer) ~= "table" or offer.Starter == true then
		return false
	end
	-- StarterUntil ist os.time() des Servers -> mit der Server-Zeit vergleichen (nicht mit der Geräte-Uhr)
	return (tonumber(offer.StarterUntil) or 0) > workspace:GetServerTimeNow()
end

Builders.Robux = function(root)
	local order = 1
	local function section(key: string)
		UI.Section(root, t(key), order)
		order += 1
	end
	local function products(kinds: { [string]: boolean })
		local g = grid(root, order)
		order += 1
		local i = 0
		for _, product in ipairs(SHOP.Products) do
			if kinds[product.Kind] then
				i += 1
				robuxCard(g, i, product, false)
			end
		end
	end
	if starterVisible() then
		section("shop.section.starter")
		local holder = UI.Create(
			"Frame",
			{ Size = UDim2.new(1, 0, 0, 230), BackgroundTransparency = 1, LayoutOrder = order, Parent = root }
		)
		order += 1
		Shop.BuildStarterCard(holder)
	end
	section("shop.section.gems")
	products({ Gems = true })
	section("shop.section.pass")
	products({ Pass = true, Tiers = true })
	section("shop.section.boosts")
	products({ Boost = true, Party = true })
	section("shop.section.passes")
	local g = grid(root, order)
	order += 1
	for i, pass in ipairs(SHOP.GamePasses) do
		robuxCard(g, i, pass, true)
	end
	section("shop.section.support")
	products({ Support = true })
end

-- =====================================================================
-- 6) FENSTER
-- =====================================================================
local function setCurrencies()
	for currency, label in pairs(currencyLabels) do
		local textValue = ("%s %s"):format(CURRENCY_ICON[currency], num(balance(currency)))
		if label.Text ~= textValue then
			label.Text = textValue
		end
	end
end

local function render()
	local root = body
	if not root or not win then
		return
	end
	hideDialog()
	tickerToken += 1
	clear(root)
	-- aktiver Reiter = Accent (Primär), die anderen Sekundär
	for name, button in pairs(tabButtons) do
		button.SetVariant(if name == currentTab then "Primary" else "Secondary")
	end
	setCurrencies()
	local builder = Builders[currentTab]
	if builder then
		local ok, err = pcall(builder, root)
		if not ok then
			warn("[Shop] Tab " .. currentTab .. ": " .. tostring(err))
		end
	end
end

local function ensureWindow()
	if win then
		return
	end
	win = UI.Window(t("shop.title"), 820, 560, UI.Theme.Accent)
	local content = win.Content
	-- Kopf-Banner als schlanke Pill mit grünem Punkt (B21.1: "ALLE WAFFEN ERSPIELBAR – KEIN PAY-TO-WIN")
	local bannerRow = UI.Row(content, 1, 32)
	pill(bannerRow, t("shop.noP2W"), 1, 520, UI.Theme.Up)
	-- Guthaben als Chips (Zahl in Titillium Web)
	local currencyRow = UI.Row(content, 2, 32)
	for i, currency in ipairs({ "Coins", "Gems", "Keys", "Shards" }) do
		local chip = pill(currencyRow, "", i, 150, nil)
		chip.Font = UI.Fonts.Number
		currencyLabels[currency] = chip
	end
	local tabRow = UI.Row(content, 3, 46)
	for i, name in ipairs(TABS) do
		tabButtons[name] = UI.Button({
			Size = UDim2.fromOffset(122, 42),
			Text = t("shop.tab." .. name),
			Variant = "Secondary",
			MaxText = 15,
			Corner = 10,
			LayoutOrder = i,
			Parent = tabRow,
		}, function()
			if currentTab ~= name then
				currentTab = name
				render()
			end
		end)
	end
	body = UI.Create("Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 4,
		Parent = content,
	}, { UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }) })
	buildDialog(win.Panel)
end

local function openWindow()
	ensureWindow()
	render()
	UI.OpenWindow(win)
end

local function closeWindow()
	hideDialog()
	tickerToken += 1
end

function Shop.Open(tab: string?)
	local wanted = if type(tab) == "string" then TAB_ALIASES[tab] or tab else nil
	if wanted and table.find(TABS, wanted) then
		currentTab = wanted
	end
	if ctx.Windows.IsOpen("Shop") then
		render()
	else
		ctx.Windows.Open("Shop")
	end
end

-- Starter-Angebot (B23.2): einmal im Ergebnis des ersten echten Siegs, danach 72 h im Shop
function Shop.BuildStarterCard(parent: GuiObject): GuiObject?
	local product = SHOP.ProductsByKey.StarterPack
	local offer = state().Offer
	if product == nil or (type(offer) == "table" and offer.Starter == true) then
		return nil
	end
	-- Premium-Karte: Surface2 mit Warn-Akzent (Rahmen + Streifen), Titel Michroma, Kaufen = Premium-Verlauf
	local frame = accentCard({
		Name = "StarterCard",
		Size = UDim2.fromOffset(420, 220),
		Parent = parent,
	}, UI.Theme.Warn)
	UI.Label({
		Position = UDim2.fromOffset(16, 14),
		Size = UDim2.new(1, -32, 0, 26),
		Text = UI.Upper(pick(product.Name)),
		Font = UI.Fonts.Heading,
		TextColor3 = UI.Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 20,
		Parent = frame,
	})
	local lines = productLines(product)
	for i = 1, math.min(4, #lines) do
		UI.Label({
			Position = UDim2.fromOffset(16, 46 + (i - 1) * 22),
			Size = UDim2.new(1, -32, 0, 22),
			Text = lines[i],
			Font = if i == 1 then UI.Fonts.Main else UI.Fonts.Body,
			TextColor3 = if i == 1 then UI.Theme.Up else UI.Theme.Text2,
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxText = 16,
			Parent = frame,
		})
	end
	local ready = (tonumber(product.Id) or 0) > 0
	UI.Button({
		Position = UDim2.new(0, 12, 1, -58),
		Size = UDim2.new(0.5, -18, 0, 46),
		Text = robuxButtonText(product, nil),
		Variant = if ready then "Premium" else "Muted",
		MaxText = 17,
		Parent = frame,
	}, function()
		promptRobux(product, false)
	end)
	-- großer "Später"-Knopf (B23.2)
	UI.Button({
		Position = UDim2.new(0.5, 6, 1, -58),
		Size = UDim2.new(0.5, -18, 0, 46),
		Text = t("shop.later"),
		Variant = "Secondary",
		MaxText = 20,
		Parent = frame,
	}, function()
		frame:Destroy()
	end)
	return frame
end

-- =====================================================================
-- 7) LOBBY: Kisten-Automat (lokal verstecken) & VIP-Tür (lokal öffnen)
-- =====================================================================
local function updateCrateMachine()
	local machine = crateMachine
	if machine == nil then
		return
	end
	if randomAllowed() == true then
		if machine.Parent == nil and crateMachineParent and crateMachineParent.Parent then
			machine.Parent = crateMachineParent
		end
	elseif machine.Parent ~= nil then
		crateMachineParent = machine.Parent
		machine.Parent = nil -- nur lokal: andere Spieler sehen ihn weiter (falls erlaubt)
	end
end

local function updateVipDoor()
	local door = vipDoor
	if door == nil then
		return
	end
	local player = ctx.Player or Players.LocalPlayer
	local vip = player:GetAttribute("Vip") == true
	door.CanCollide = not vip
	door.Transparency = if vip then 0.6 else 0
end

local function findLobbyObjects()
	task.spawn(function()
		for _ = 1, FIND_TRIES do
			if crateMachine == nil then
				local found = workspace:FindFirstChild("CrateMachine", true)
				if found then
					crateMachine = found
					crateMachineParent = found.Parent
					updateCrateMachine()
				end
			end
			if vipDoor == nil then
				local door = workspace:FindFirstChild("VipDoor", true)
				if door and door:IsA("BasePart") then
					vipDoor = door
					updateVipDoor()
				end
			end
			if crateMachine and vipDoor then
				return
			end
			task.wait(3)
		end
	end)
end

-- =====================================================================
-- 8) INIT / START
-- =====================================================================
local function onState(_state: any, changed: any)
	if changedHas(changed, "RandomAllowed") then
		updateCrateMachine()
	end
	if not (win and win.IsOpen) then
		return
	end
	setCurrencies()
	local keys = TAB_KEYS[currentTab] or {}
	local relevant = false
	for _, key in ipairs(keys) do
		if changedHas(changed, key) then
			relevant = true
			break
		end
	end
	if relevant and not renderQueued and not (dialog and dialog.Visible) then
		renderQueued = true
		task.delay(0.2, function()
			renderQueued = false
			if win and win.IsOpen and not (dialog and dialog.Visible) then
				render()
			end
		end)
	end
end

function Shop.Init(c: any)
	ctx = c
	UI = c.UI
end

function Shop.Start()
	ctx.Windows.Register("Shop", openWindow, closeWindow)
	local hud = modules().Hud
	if hud and type(hud.AddRightButton) == "function" then
		pcall(hud.AddRightButton, "🛒", "shop.hud.shop", UI.Theme.Accent, 20, function()
			ctx.Windows.Open("Shop")
		end)
	end
	local hooks = ctx.Hooks
	hooks.On("State", onState)
	hooks.On("Effect:CrateFound", function(_strength: number, data: any)
		if type(data) == "table" and randomAllowed() == true and type(data.Name) == "string" then
			local def = COSMETICS.ById[data.ItemId]
			ctx.Toast(
				t("shop.crateFoundItem", data.Name, if def then pick(def.Name) else tostring(data.Rarity)),
				"Event"
			)
		end
	end)
	hooks.On("Effect:PartyBoost", function()
		if win and win.IsOpen and currentTab == "Robux" then
			render()
		end
	end)
	local player = ctx.Player or Players.LocalPlayer
	player:GetAttributeChangedSignal("Vip"):Connect(updateVipDoor)
	pcall(UI.WhenRandomItemsKnown, function()
		updateCrateMachine()
		if win and win.IsOpen and currentTab == "Crates" then
			render()
		end
	end)
	findLobbyObjects()
	-- Kisten-Automat & Co.: Prompt mit Window = "Shop" und Tab = "<Tab>" öffnet direkt diesen Tab
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local tab = prompt:GetAttribute("Tab")
		if prompt:GetAttribute("Window") == "Shop" and type(tab) == "string" then
			Shop.Open(tab)
		end
	end)
end

return Shop
