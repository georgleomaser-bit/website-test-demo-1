-- =====================================================================
--  AKYTEX TYCOON – Shop-Fenster, Angebots-Karte, Chat-Tags (Client/Modules/Shop)
--  Besitzer: WP10 (Monetarisierung, Shop, CR-Konto). Vertrag: DESIGN.md §C7.5 (Shop.Open, Shop.ShowOffer), §C7.3
--  (Fenster "Shop"), §B14 (Pässe, Produkte, Abo, ehrliche Wirkungstexte, "Zusammen x4", Paket-Erkennung, Live-Preise),
--  §B14.4 + Muss-Regel 17 (max. 1 Angebot je Sitzung, nie während Terminal/Order-Ticket/Tutorial/Willkommen-Bericht/
--  Crash-Rally-Warnung/Admin-Abuse; Knöpfe "Ansehen"/"Details"/"Preis anzeigen", nie Kaufdruck).
--
--  Der Server entscheidet alles (Preise, Besitz, Policy, Gewährung). Dieses Modul zeigt nur den State
--  (Passes, Club, Boosts, Offers, RandomAllowed, TradingAllowed, Starter, Credits, Tower) und schickt Absichten:
--  ShopQuote {Key} (Bau-Gutschein-Angebot, 10 min), ShopPrecheck {Key, UserId?} (vor jedem Roblox-Kaufdialog),
--  ShopClubClaim {} (Club-Tagesgabe). Live-Preise kommen IMMER aus dem Marktplatz (UI.FetchPrice), Id 0 = "Bald verfügbar".
--  Kopf-Banner: "Kurse kann man nicht kaufen – alles Spielgeld". Vor jedem Kauf: "Details" mit der exakten Wirkung.
--  Look: AKYTEX-Glas (Surface2-Karten, 1-px-Rahmen, Akzent nur als Streifen/Rahmen), Robux-Knopf = Premium-Verlauf.
--
--  Öffentliche API (§C7.5):
--    Shop.Open(tab?)        tab ∈ "Start" | "Passes" | "Boosts" | "Credits" | "Season" | "Club" (+ Aliase wie "Starter")
--                           oder ein Artikel-Schlüssel (öffnet dessen Details)
--    Shop.ShowOffer(key)    ruhige Angebots-Karte (Knöpfe "Ansehen" / "Später"); normalerweise vom State "Offers" ausgelöst
--    Shop.Init(ctx) · Shop.Start()
--  Chat-Tags [VIP]/[Club] (TextChatService.OnIncomingMessage, nur Anzeige) aus den Player-Attributen Vip/Club.
-- =====================================================================

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent:WaitForChild("UI"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Lang = require(Shared:WaitForChild("Lang"))
local Format = require(Shared:WaitForChild("Format"))
local AssetSlot = require(Shared:WaitForChild("AssetSlot"))

local Shop = {}

local Theme = UI.Theme
local player = Players.LocalPlayer
local SHOP: any = Config.Shop
local SUB: any = SHOP.Subscription or {}
local WHITE = Color3.new(1, 1, 1)

-- ---------------------------------------------------------------------
-- KONSTANTEN
-- ---------------------------------------------------------------------
local WINDOW_W, WINDOW_H = 900, 640
local SHEET_H = 600
local CARD_W, CARD_H = 200, 206
local DETAIL_TEXT = 17
local TICK_MAX = 36000 -- Countdown-Schleife höchstens so viele Sekunden je Öffnung
local OFFER_AUTO_HIDE = 25 -- Angebots-Karte verschwindet von selbst
local OFFER_CHECK_GAP = 2 -- so oft prüft der Client, ob gerade ein ruhiger Moment ist
local RENDER_DELAY = 0.25 -- State-Änderungen bündeln
local MAX_GIFT_TARGETS = 9
local MARKET_EVENT_HOLD = 300 -- nach Warnung/Lauf eines Markt-Events so lange kein Angebot
local MARKET_EVENT_TAIL = 60 -- nach dem Ende eines Markt-Events noch so lange ruhig bleiben

local TABS = { "Start", "Passes", "Boosts", "Credits", "Season", "Club" }
local TAB_LANG: { [string]: string } = {
	Start = "shop.tab.start",
	Passes = "shop.tab.passes",
	Boosts = "shop.tab.boosts",
	Credits = "shop.tab.credits",
	Season = "shop.tab.season",
	Club = "shop.tab.club",
}
local TAB_ALIASES: { [string]: string } = {
	Featured = "Start",
	Home = "Start",
	Pass = "Passes",
	GamePasses = "Passes",
	Robux = "Passes",
	Boost = "Boosts",
	Vouchers = "Credits",
	CR = "Credits",
	Build = "Credits",
	SeasonPass = "Season",
	Subscription = "Club",
}
local INCOME_PASSES = { "Income2x", "Income3x", "TycoonBundle" }
local KIND_COLORS: { [string]: Color3 } = {
	Pass = Theme.Accent,
	Boost = Theme.Up,
	Parade = Theme.Gold,
	Voucher = Theme.Up,
	Express = Theme.Cyan,
	Fireworks = Theme.Pink,
	Starter = Theme.Warn,
	Season = Theme.Purple,
	Tiers = Theme.Purple,
	Gift = Theme.Pink,
	Subscription = Theme.Cosmic2,
}

-- ---------------------------------------------------------------------
-- ZUSTAND
-- ---------------------------------------------------------------------
type Dynamic = { Label: TextLabel, Fn: () -> string }
type QuoteInfo = { Key: string, Credits: number, Until: number }

local ctx: any = nil
local window: any = nil
local tabs: any = nil
local body: Frame? = nil
local builtLang = ""
local currentTab = "Start"
local pendingTab: string? = nil
local pendingDetail: string? = nil
local renderQueued = false
local tickToken = 0
local dynamics: { Dynamic } = {}
local detailDynamics: { Dynamic } = {}
local livePrices: { [string]: number } = {}
local subPrice: string? = nil
local subPriceStarted = false
local subPriceDone = false -- Anfrage beendet (ohne Anzeigepreis -> "Preis anzeigen", der Roblox-Dialog zeigt ihn)
local pending = false
local shopSeenSent = false

-- Detail-Dialog
local detailFrame: Frame? = nil
local detailTitle: TextLabel? = nil
local detailAccent: Frame? = nil
local detailList: ScrollingFrame? = nil
local detailButtons: Frame? = nil
local detailKey: string? = nil
local giftChoice: number? = nil
local quote: QuoteInfo? = nil
local quoteLoading = false
local quoteFailed: string? = nil -- nach einer abgelehnten Angebots-Anfrage nicht automatisch erneut fragen

-- Angebote
local offerCard: Frame? = nil
local offerToken = 0
local lastOfferId = 0
local marketBusyUntil = 0

-- =====================================================================
-- 1) HELFER
-- =====================================================================
local function lang(): "de" | "en"
	local ok, value = pcall(function()
		return ctx.Lang_()
	end)
	return if ok and value == "de" then "de" else "en"
end

local function T(key: string, ...: any): string
	return Lang.T(lang(), key, ...)
end

local function pick(pair: any): string
	return if type(pair) == "table" then Lang.Pick(lang(), pair) else tostring(pair or "")
end

local function state(): { [string]: any }
	return if ctx and type(ctx.State) == "table" then ctx.State else {}
end

local function offers(): { [string]: any }
	local value = state().Offers
	return if type(value) == "table" then value else {}
end

local function num(value: any, default: number): number
	return if type(value) == "number"
			and value == value
			and value ~= math.huge
			and value ~= -math.huge
		then value
		else default
end

local function credits(n: number): string
	return Format.Credits(num(n, 0), lang())
end

local function duration(seconds: number): string
	return Format.Duration(math.max(0, num(seconds, 0)), lang())
end

local function mult(x: number): string
	return Format.Mult(num(x, 1), lang())
end

local function int(n: number): string
	return Format.Int(num(n, 0), lang())
end

local function clockNow(): number
	local clock = ctx and ctx.Clock
	if clock and type(clock.Now) == "function" then
		local ok, value = pcall(clock.Now)
		if ok and type(value) == "number" then
			return value
		end
	end
	return workspace:GetServerTimeNow()
end

local function callModule(name: string, fnName: string, ...: any): (boolean, any)
	local modules = ctx and ctx.Modules
	local module = modules and modules[name]
	local fn = module and module[fnName]
	if type(fn) ~= "function" then
		return false, nil
	end
	return pcall(fn, ...)
end

local function sfx(role: string)
	callModule("Sfx", "Play", role)
end

local function toast(text: string, kind: string?)
	if ctx and type(ctx.Toast) == "function" then
		ctx.Toast(text, kind)
	end
end

local function hasPass(key: string): boolean
	local passes = state().Passes
	return type(passes) == "table" and passes[key] == true
end

local function isClub(): boolean
	return state().Club == true
end

local function tradingAllowed(): boolean
	return state().TradingAllowed == true
end

local function passFactor(): number
	return 1 + (if hasPass("Income2x") then 1 else 0) + (if hasPass("Income3x") then 2 else 0)
end

local function towerMult(key: string, default: number): number
	local tower = Config.Tower
	local values = type(tower) == "table" and tower.Mult or nil
	local value = type(values) == "table" and values[key] or nil
	if type(value) == "number" and value >= 1 then
		return value
	end
	local fixed = SHOP.Fixed
	return num(type(fixed) == "table" and fixed[key] or nil, default)
end

local function isPremiumMember(): boolean
	local ok, result = pcall(function(): boolean
		return player.MembershipType == Enum.MembershipType.Premium
	end)
	return ok and result == true
end

local function fixedFactor(): number
	local factor = 1
	if hasPass("VIP") then
		factor *= towerMult("Vip", 1.10)
	end
	if isClub() then
		factor *= towerMult("Club", 1.15)
	end
	if isPremiumMember() then
		factor *= towerMult("Premium", 1.10)
	end
	return factor
end

-- Artikel + Art ("Pass" | "Product" | "Subscription")
local function itemOf(key: string): (any, string?)
	if type(key) ~= "string" then
		return nil, nil
	end
	local pass = SHOP.PassesByKey[key]
	if pass then
		return pass, "Pass"
	end
	local product = SHOP.ProductsByKey[key]
	if product then
		return product, "Product"
	end
	if key == SUB.Key then
		return SUB, "Subscription"
	end
	return nil, nil
end

local function kindKey(entry: any, kind: string): string
	if kind == "Product" and type(entry.Kind) == "string" then
		return entry.Kind
	end
	return kind
end

local function accentFor(entry: any, kind: string): Color3
	return KIND_COLORS[kindKey(entry, kind)] or Theme.Accent
end

local function configured(entry: any, kind: string): boolean
	if kind == "Subscription" then
		return type(entry.Id) == "string" and entry.Id ~= ""
	end
	return type(entry.Id) == "number" and entry.Id > 0
end

local function isDisabled(key: string): boolean
	local live = offers().Disabled
	if type(live) == "table" and live[key] == true then
		return true
	end
	return type(SHOP.Disabled) == "table" and SHOP.Disabled[key] == true
end

local function tabOf(key: string): string
	local entry, kind = itemOf(key)
	if kind == "Pass" then
		return "Passes"
	elseif kind == "Subscription" then
		return "Club"
	elseif kind == "Product" then
		local k = entry.Kind
		if k == "Voucher" or k == "Express" then
			return "Credits"
		elseif k == "Season" or k == "Tiers" then
			return "Season"
		elseif k == "Starter" then
			return "Start"
		end
		return "Boosts"
	end
	return "Start"
end

-- erster Satz einer Beschreibung (Karten zeigen nur den Kern, die Details alles)
local function firstSentence(text: string): string
	local sentence = string.match(text, "^(.-[%.!])%s")
	return sentence or text
end

local function addDynamic(list: { Dynamic }, label: TextLabel, fn: () -> string)
	table.insert(list, { Label = label, Fn = fn })
	local ok, text = pcall(fn)
	if ok and type(text) == "string" then
		label.Text = text
	end
end

local function updateDynamics(list: { Dynamic })
	for _, entry in ipairs(list) do
		if entry.Label.Parent ~= nil then
			local ok, text = pcall(entry.Fn)
			if ok and type(text) == "string" and entry.Label.Text ~= text then
				entry.Label.Text = text
			end
		end
	end
end

local function clearChildren(frame: Instance)
	for _, child in ipairs(frame:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") and not child:IsA("UIGridLayout") then
			child:Destroy()
		end
	end
end

-- Restzeit des stärksten persönlichen Boosts (Spielsekunden, seit dem letzten State heruntergezählt)
local function boostInfo(): (string?, number, number)
	local boosts = state().Boosts
	if type(boosts) ~= "table" then
		return nil, 0, 0
	end
	local elapsed = math.max(0, os.clock() - num(ctx and ctx.StateTime, os.clock()))
	local x5 = math.max(0, num(boosts.X5, 0) - elapsed)
	local x2 = num(boosts.X2, 0)
	if x5 > 0 then
		return "x5", x5, x2
	end
	x2 = math.max(0, x2 - elapsed)
	if x2 > 0 then
		return "x2", x2, 0
	end
	return nil, 0, 0
end

local function paradeLeft(): number
	return math.max(0, num(offers().Parade, 0) - clockNow())
end

-- Ende der aktuellen Saison (Unix): Config.Season inkl. Rolling-Regel
local function seasonEnd(): number?
	local season = Config.Season
	local list = type(season) == "table" and season.Seasons or nil
	if type(list) ~= "table" or #list == 0 then
		return nil
	end
	local id = SHOP.SeasonIdAt(season, clockNow())
	local last = list[#list]
	for _, entry in ipairs(list) do
		if type(entry) == "table" and entry.Id == id then
			return SHOP.ParseUtc(entry.EndUtc)
		end
	end
	local lastEnd = SHOP.ParseUtc(last.EndUtc)
	local rolling = season.Rolling
	if lastEnd and type(rolling) == "table" and type(last.Id) == "number" then
		local length = num(rolling.LengthDays, 28) * 86400
		return lastEnd + (id - last.Id) * length
	end
	return lastEnd
end

local function nextUtcMidnight(): number
	return (math.floor(clockNow() / 86400) + 1) * 86400
end

-- =====================================================================
-- 2) LIVE-PREISE (immer vom Marktplatz, nie hart kodiert)
-- =====================================================================
local function fetchSubscriptionPrice()
	if subPriceStarted or type(SUB.Id) ~= "string" or SUB.Id == "" then
		return
	end
	subPriceStarted = true
	task.spawn(function()
		local ok, info = pcall(MarketplaceService.GetSubscriptionProductInfoAsync, MarketplaceService, SUB.Id)
		if ok and type(info) == "table" and type(info.DisplayPrice) == "string" and info.DisplayPrice ~= "" then
			subPrice = info.DisplayPrice
		end
		subPriceDone = true
	end)
end

-- Preis-Text in ein Label schreiben (asynchron); Label weg -> nichts
local function setPrice(label: TextLabel, entry: any, kind: string)
	if not configured(entry, kind) then
		label.Text = T("shop.notSetUp")
		return
	end
	if kind == "Subscription" then
		fetchSubscriptionPrice()
		if subPrice then
			label.Text = T("shop.priceMonth", subPrice)
		else
			label.Text = if subPriceDone then T("shop.showPrice") else T("shop.loadingPrice")
			if not subPriceDone then
				-- nach der Antwort einmal nachtragen (Label kann inzwischen weg sein)
				task.delay(3, function()
					if label.Parent ~= nil and (subPrice or subPriceDone) then
						label.Text = if subPrice then T("shop.priceMonth", subPrice) else T("shop.showPrice")
					end
				end)
			end
		end
		return
	end
	local cached = livePrices[entry.Key]
	if cached then
		label.Text = T("shop.price", int(cached))
		return
	end
	label.Text = T("shop.loadingPrice")
	local infoType = if kind == "Pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
	UI.FetchPrice(entry.Id, infoType, function(price: number?)
		if price then
			livePrices[entry.Key] = price
		end
		if label.Parent ~= nil then
			label.Text = if price then T("shop.price", int(price)) else T("shop.notSetUp")
		end
	end)
end

-- Einzelpreise der Paket-Teile laden (für den echten Rabatt aus Live-Preisen)
local function prefetchBundle(bundle: any)
	if type(bundle) ~= "table" or type(bundle.Includes) ~= "table" then
		return
	end
	local keys = table.clone(bundle.Includes)
	table.insert(keys, bundle.Key)
	for _, key in ipairs(keys) do
		local pass = SHOP.PassesByKey[key]
		if pass and configured(pass, "Pass") and livePrices[key] == nil then
			UI.FetchPrice(pass.Id, Enum.InfoType.GamePass, function(price: number?)
				if price then
					livePrices[key] = price
				end
			end)
		end
	end
end

local function bundleSaveText(bundle: any): string?
	local price = livePrices[bundle.Key]
	if not price then
		return nil
	end
	local single = 0
	for _, key in ipairs(bundle.Includes) do
		local part = livePrices[key]
		if not part then
			return nil
		end
		single += part
	end
	local pct = SHOP.BundleDiscountPct(bundle.Key, single, price)
	if pct <= 0 then
		return nil -- kein echter Rabatt -> keine Rabatt-Zeile (keine Fake-Rabatte)
	end
	return T("shop.bundleSave", int(single), int(price), pct)
end

local function partNames(keys: { string }): string
	local names: { string } = {}
	for _, key in ipairs(keys) do
		local part = SHOP.PassesByKey[key]
		table.insert(names, if part then pick(part.Name) else key)
	end
	return table.concat(names, ", ")
end

local function bundleParts(bundle: any): ({ string }, { string })
	local ownedParts, missing = {}, {}
	for _, key in ipairs(bundle.Includes or {}) do
		if hasPass(key) then
			table.insert(ownedParts, key)
		else
			table.insert(missing, key)
		end
	end
	return ownedParts, missing
end

-- =====================================================================
-- 3) KAUF (Vorprüfung am Server, dann der Roblox-Kaufdialog)
-- =====================================================================
local function closeDetail()
	detailKey = nil
	quote = nil
	giftChoice = nil
	table.clear(detailDynamics)
	if detailFrame then
		detailFrame.Visible = false
	end
end

local function prompt(reply: { [string]: any })
	local id = reply.Id
	local ok, err = pcall(function()
		if reply.Kind == "Pass" and type(id) == "number" then
			MarketplaceService:PromptGamePassPurchase(player, id)
		elseif reply.Kind == "Subscription" and type(id) == "string" then
			MarketplaceService:PromptSubscriptionPurchase(player, id)
		elseif type(id) == "number" then
			MarketplaceService:PromptProductPurchase(player, id)
		end
	end)
	if not ok then
		warn("[Shop] Kaufdialog: " .. tostring(err))
		toast(T("core.error"), "Error")
	end
end

local function purchase(key: string, userId: number?)
	if pending then
		return
	end
	pending = true
	task.spawn(function()
		local arg: { [string]: any } = { Key = key }
		if userId then
			arg.UserId = userId
		end
		local ok, reply = pcall(function()
			return ctx.RequestFull("ShopPrecheck", arg, true)
		end)
		pending = false
		if not ok or type(reply) ~= "table" then
			toast(T("core.noAnswer"), "Error")
			return
		end
		if not reply.Ok then
			toast(
				if type(reply.Message) == "string" and reply.Message ~= "" then reply.Message else T("core.error"),
				"Error"
			)
			return
		end
		sfx("UIClick")
		prompt(reply)
	end)
end

local renderDetail: () -> () -- vorwärts deklariert
local openDetail: (key: string) -> () -- vorwärts deklariert

local function requestQuote(key: string)
	if quoteLoading then
		return
	end
	quoteLoading = true
	task.spawn(function()
		local ok, reply = pcall(function()
			return ctx.RequestFull("ShopQuote", { Key = key }, true)
		end)
		quoteLoading = false
		if detailKey ~= key then
			return
		end
		if
			ok
			and type(reply) == "table"
			and reply.Ok
			and type(reply.Credits) == "number"
			and type(reply.Until) == "number"
		then
			quote = { Key = key, Credits = reply.Credits, Until = reply.Until }
			quoteFailed = nil
		else
			quoteFailed = key
			if ok and type(reply) == "table" and type(reply.Message) == "string" and reply.Message ~= "" then
				toast(reply.Message, "Error")
			end
		end
		renderDetail()
	end)
end

local function claimClub()
	if pending then
		return
	end
	pending = true
	task.spawn(function()
		local ok, reply = pcall(function()
			return ctx.RequestFull("ShopClubClaim", {}, true)
		end)
		pending = false
		if not ok or type(reply) ~= "table" then
			toast(T("core.noAnswer"), "Error")
			return
		end
		if type(reply.Message) == "string" and reply.Message ~= "" then
			toast(reply.Message, if reply.Ok then "Success" else "Error")
		end
		if reply.Ok then
			callModule("Hud", "PulseCredits", reply.Credits)
		end
	end)
end

-- =====================================================================
-- 4) BAUSTEINE (Karten, Abschnitte, Hinweise)
-- =====================================================================
local function section(parent: Instance, text: string, order: number, color: Color3?)
	UI.Section(parent, text, order, color)
end

local function note(parent: Instance, text: string, order: number, color: Color3?): TextLabel
	return UI.Create("TextLabel", {
		Name = "Note",
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		FontFace = UI.Faces.Body,
		TextSize = 15,
		TextColor3 = color or Theme.Text2,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = text,
		LayoutOrder = order,
		Parent = parent,
	})
end

local function grid(parent: Instance, order: number): Frame
	return UI.Grid(parent, order, CARD_W, CARD_H)
end

-- runde Plakette mit Glyphe (Code-Grafik; ImageId ≠ 0 -> Bild aus dem Asset-Platz)
local function iconBadge(parent: Instance, entry: any, color: Color3, size: number, position: UDim2): Frame
	local badge: Frame = UI.Create("Frame", {
		Name = "Icon",
		Position = position,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = WHITE, -- der Verlauf liefert die Farbe (UIGradient multipliziert)
		BorderSizePixel = 0,
		Parent = parent,
	}, {
		UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		UI.Gradient(color:Lerp(WHITE, 0.18), color:Lerp(Theme.Bg, 0.45), 120),
		UI.Create("UIStroke", { Color = color:Lerp(WHITE, 0.35), Thickness = 1, Transparency = 0.35 }),
	})
	-- Hybrid-Asset-Platz (§C14.3): ImageId ≠ 0 -> Bild, sonst (oder bei Fehler) Code-Grafik
	local image = AssetSlot.Image(num(entry.ImageId, 0), "")
	if image ~= "" then
		UI.Create("ImageLabel", {
			Size = UDim2.fromScale(0.72, 0.72),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			Image = image,
			Parent = badge,
		})
	else
		UI.Label({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.74, 0.5),
			Text = tostring(entry.Icon or "Λ"),
			Face = "Display",
			TextColor3 = WHITE,
			MaxText = math.floor(size * 0.45),
			Parent = badge,
		})
	end
	return badge
end

type CardOpts = {
	Lines: { { Text: string?, Fn: (() -> string)?, Color: Color3? } }?,
	Highlight: boolean?,
	Status: string?,
}

-- Artikel-Karte im Raster: Plakette, Art-Chip, Name, bis zu 2 Zeilen, Preis, Knopf "Details"
local function itemCard(parent: Instance, order: number, key: string, opts: CardOpts?): Frame?
	local entry, kind = itemOf(key)
	if entry == nil or kind == nil then
		return nil
	end
	local options: CardOpts = opts or {}
	local color = accentFor(entry, kind)
	local frame = UI.Card({ Size = UDim2.fromOffset(CARD_W, CARD_H), LayoutOrder = order, Parent = parent })
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke and options.Highlight then
		stroke.Color = color
		stroke.Transparency = 0.35
	end
	UI.Create("Frame", {
		Name = "Stripe",
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -28, 0, 3),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = frame,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	iconBadge(frame, entry, color, 40, UDim2.fromOffset(12, 14))
	UI.Chip(frame, T("item.kind." .. kindKey(entry, kind)), color, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 16),
	})
	if options.Status then
		UI.Chip(frame, options.Status, Theme.Up, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 40),
		})
	end
	UI.Label({
		Name = "Title",
		Position = UDim2.fromOffset(12, 62),
		Size = UDim2.new(1, -24, 0, 36),
		Text = pick(entry.Name),
		Font = UI.Fonts.Main,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		MaxText = 17,
		Parent = frame,
	})
	local lines = options.Lines or { { Text = firstSentence(pick(entry.Desc)) } }
	for i, line in ipairs(lines) do
		if i > 2 then
			break
		end
		local label = UI.Label({
			Name = "Line" .. i,
			Position = UDim2.fromOffset(12, 98 + (i - 1) * 22),
			Size = UDim2.new(1, -24, 0, 21),
			Text = line.Text or "",
			Font = if line.Color then UI.Fonts.Main else UI.Fonts.Body,
			TextColor3 = line.Color or Theme.Text2,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			MaxText = 13,
			Parent = frame,
		})
		if line.Fn then
			addDynamic(dynamics, label, line.Fn)
		end
	end
	local price = UI.Label({
		Name = "Price",
		Position = UDim2.fromOffset(12, 142),
		Size = UDim2.new(1, -24, 0, 16),
		Text = "",
		Face = "MonoBold",
		TextColor3 = Theme.Warn,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 13,
		Parent = frame,
	})
	setPrice(price, entry, kind)
	UI.Button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -20, 0, 32),
		Text = T("shop.details"),
		Variant = if isDisabled(key) then "Muted" else "Secondary",
		MaxText = 15,
		Corner = 10,
		Parent = frame,
	}, function()
		openDetail(key)
	end)
	-- sanftes Anheben beim Darüberfahren (nur Rahmen, kein Layout-Sprung)
	if stroke then
		local rest = stroke.Transparency
		frame.MouseEnter:Connect(function()
			TweenService:Create(stroke, TweenInfo.new(0.12), { Color = color, Transparency = 0.25 }):Play()
		end)
		frame.MouseLeave:Connect(function()
			TweenService:Create(stroke, TweenInfo.new(0.12), {
				Color = if options.Highlight then color else Theme.Border,
				Transparency = rest,
			}):Play()
		end)
	end
	return frame
end

-- breite Info-Karte (Hinweise wie "x2 + x3 zusammen = x4", aktive Vorteile). Rückgabe: Inhalts-Frame (Liste).
local function infoCard(parent: Instance, order: number, title: string?, lines: { string }, color: Color3): Frame
	local frame = UI.Card({
		Size = UDim2.new(1, -4, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = parent,
	})
	UI.Create("Frame", {
		Name = "Bar",
		Position = UDim2.fromOffset(8, 10),
		Size = UDim2.new(0, 3, 1, -20),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = frame,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local content: Frame = UI.Create("Frame", {
		Name = "Content",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = frame,
	}, {
		UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }),
		UI.Create("UIPadding", {
			PaddingLeft = UDim.new(0, 22),
			PaddingRight = UDim.new(0, 14),
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 10),
		}),
	})
	if title and title ~= "" then
		local titleLabel = note(content, title, 1, Theme.Text)
		titleLabel.FontFace = UI.Faces.BodyBold
		titleLabel.TextSize = 16
	end
	for i, line in ipairs(lines) do
		note(content, line, i + 1, Theme.Text2)
	end
	return content
end

-- =====================================================================
-- 5) REITER
-- =====================================================================
local Builders: { [string]: (root: Frame) -> () } = {}

local function activeLines(): { string }
	local lines: { string } = {}
	local factor = passFactor()
	if factor > 1 then
		table.insert(lines, T("shop.active.passFactor", mult(factor)))
	end
	local fixed = fixedFactor()
	if fixed > 1.0001 then
		table.insert(lines, T("shop.active.fixed", mult(fixed)))
	end
	if isClub() then
		table.insert(lines, T("shop.active.club"))
	end
	local which, left = boostInfo()
	if which then
		table.insert(lines, T("shop.boost.active", which, duration(left)))
	end
	if paradeLeft() > 0 then
		table.insert(lines, T("shop.parade.active", duration(paradeLeft())))
	end
	if #lines == 0 then
		table.insert(lines, T("shop.active.none"))
	end
	return lines
end

Builders.Start = function(root: Frame)
	section(root, T("shop.section.active"), 1, Theme.Up)
	local active = infoCard(root, 2, nil, {}, Theme.Up)
	local activeLabel = note(active, "", 1, Theme.Text)
	addDynamic(dynamics, activeLabel, function(): string
		return table.concat(activeLines(), "\n")
	end)
	section(root, T("shop.section.recommended"), 3, Theme.Warn)
	local cards = grid(root, 4)
	local order = 0
	local starter = state().Starter
	local bought = type(starter) == "table" and starter.Bought == true
	order += 1
	itemCard(cards, order, "Starter", {
		Highlight = not bought,
		Status = if bought then T("shop.owned") else nil,
	})
	local bundle = SHOP.PassesByKey.TycoonBundle
	if bundle then
		prefetchBundle(bundle)
		local _, missing = bundleParts(bundle)
		if #missing > 0 then
			order += 1
			itemCard(cards, order, "TycoonBundle", {
				Lines = {
					{ Text = T("shop.bundleParts", partNames(bundle.Includes)) },
					{
						Fn = function(): string
							return bundleSaveText(bundle) or T("shop.together4")
						end,
						Color = Theme.Up,
					},
				},
			})
		end
	end
	if offers().SeasonPremium ~= true then
		order += 1
		itemCard(cards, order, "SeasonPremium")
	end
	if isClub() or offers().ClubEligible == true then
		order += 1
		itemCard(cards, order, SUB.Key, { Status = if isClub() then T("shop.active") else nil })
	end
	note(root, T("shop.premiumBonus"), 5, Theme.Muted)
end

Builders.Passes = function(root: Frame)
	section(root, T("shop.section.income"), 1, Theme.Accent)
	infoCard(root, 2, T("shop.together4"), { T("shop.togetherNote") }, Theme.Accent)
	local income = grid(root, 3)
	local bundle = SHOP.PassesByKey.TycoonBundle
	prefetchBundle(bundle)
	for i, key in ipairs(INCOME_PASSES) do
		local status = if hasPass(key) then T("shop.owned") else nil
		if key == "TycoonBundle" and bundle then
			local ownedParts, missing = bundleParts(bundle)
			local lines: { { Text: string?, Fn: (() -> string)?, Color: Color3? } } = {}
			if hasPass("TycoonBundle") then
				lines = { { Text = T("shop.bundleParts", partNames(bundle.Includes)) } }
			elseif #missing == 0 then
				lines = { { Text = T("shop.bundleAllOwned"), Color = Theme.Muted } }
			elseif #ownedParts > 0 then
				lines = {
					{ Text = T("shop.bundleOwnedParts", partNames(ownedParts)) },
					{ Text = T("shop.bundleSingles", partNames(missing)), Color = Theme.Warn },
				}
			else
				lines = {
					{ Text = T("shop.bundleParts", partNames(bundle.Includes)) },
					{
						Fn = function(): string
							return bundleSaveText(bundle) or T("shop.robuxNote")
						end,
						Color = Theme.Up,
					},
				}
			end
			itemCard(income, i, key, { Lines = lines, Status = status })
		else
			itemCard(income, i, key, {
				Lines = {
					{ Text = firstSentence(pick(SHOP.PassesByKey[key].Desc)) },
					{ Text = T("shop.together4"), Color = Theme.Accent },
				},
				Status = status,
			})
		end
	end
	section(root, T("shop.section.passes"), 4, Theme.Accent)
	local others = grid(root, 5)
	local order = 0
	for _, pass in ipairs(SHOP.GamePasses) do
		if not table.find(INCOME_PASSES, pass.Key) then
			order += 1
			itemCard(others, order, pass.Key, { Status = if hasPass(pass.Key) then T("shop.owned") else nil })
		end
	end
	note(root, T("shop.firewall"), 6, Theme.Muted)
end

Builders.Boosts = function(root: Frame)
	section(root, T("shop.section.boosts"), 1, Theme.Up)
	local status = note(root, "", 2, Theme.Text2)
	addDynamic(dynamics, status, function(): string
		local which, left, stored = boostInfo()
		if which == "x5" and stored > 0 then
			return T("shop.boost.active", which, duration(left)) .. " · " .. T("shop.boost.paused", duration(stored))
		elseif which then
			return T("shop.boost.active", which, duration(left))
		end
		return T("shop.boost.none")
	end)
	local personal = grid(root, 3)
	for i, key in ipairs({ "Boost2x30", "Boost2x120", "Boost5x10", "GiftBoost" }) do
		itemCard(personal, i, key)
	end
	section(root, T("shop.section.server"), 4, Theme.Gold)
	local server = grid(root, 5)
	itemCard(server, 1, "BullParade", {
		Lines = {
			{ Text = firstSentence(pick(SHOP.ProductsByKey.BullParade.Desc)) },
			{
				Fn = function(): string
					local left = paradeLeft()
					return if left > 0 then T("shop.parade.active", duration(left)) else ""
				end,
				Color = Theme.Gold,
			},
		},
	})
	itemCard(server, 2, "Fireworks")
end

Builders.Credits = function(root: Frame)
	section(root, T("shop.section.vouchers"), 1, Theme.Up)
	note(root, T("shop.onlyCr") .. " · " .. T("shop.quoteHint"), 2, Theme.Text2)
	local vouchers = grid(root, 3)
	for i, key in ipairs({ "CreditsS", "CreditsM", "CreditsL", "CreditsXL" }) do
		itemCard(vouchers, i, key, {
			Lines = {
				{ Text = firstSentence(pick(SHOP.ProductsByKey[key].Desc)) },
				{
					Fn = function(): string
						local preview = offers().Preview
						local value = if type(preview) == "table" then preview[key] else nil
						return T("shop.voucherPreview", credits(num(value, 0)))
					end,
					Color = Theme.Up,
				},
			},
		})
	end
	section(root, T("shop.section.express"), 4, Theme.Cyan)
	local build = note(root, "", 5, Theme.Text2)
	addDynamic(dynamics, build, function(): string
		local tower = state().Tower
		local info = type(tower) == "table" and tower.Build or nil
		if type(info) == "table" and info.Floor ~= nil then
			return T("shop.express.build", duration(num(info.Until, 0) - clockNow()))
		end
		local tokens = type(tower) == "table" and type(tower.Tokens) == "table" and tower.Tokens.Express or 0
		return T("shop.express.token", num(tokens, 0))
	end)
	local express = grid(root, 6)
	for i, key in ipairs({ "ExpressS", "ExpressM", "ExpressL" }) do
		itemCard(express, i, key)
	end
end

Builders.Season = function(root: Frame)
	section(root, T("shop.section.season"), 1, Theme.Purple)
	local ends = note(root, "", 2, Theme.Text2)
	addDynamic(dynamics, ends, function(): string
		local untilT = seasonEnd()
		local prefix = if offers().SeasonPremium == true then T("shop.season.premiumActive") .. " · " else ""
		return prefix .. (if untilT then T("shop.season.ends", duration(untilT - clockNow())) else "")
	end)
	local cards = grid(root, 3)
	itemCard(cards, 1, "SeasonPremium", {
		Status = if offers().SeasonPremium == true then T("shop.season.premiumActive") else nil,
		Highlight = offers().SeasonPremium ~= true,
	})
	itemCard(cards, 2, "SeasonTier1")
	itemCard(cards, 3, "SeasonTier10")
	note(root, T("shop.firewall"), 4, Theme.Muted)
end

Builders.Club = function(root: Frame)
	section(root, T("shop.section.club"), 1, Theme.Cosmic2)
	-- Vorteile einzeln auflisten: getrennt an ", " (Dezimal-Kommas wie "×1,15" haben kein Leerzeichen dahinter)
	local benefits: { string } = {}
	local text = pick(SUB.Desc)
	local start = 1
	for _ = 1, 24 do
		local cut = string.find(text, ", ", start, true)
		local part = string.sub(text, start, if cut then cut - 1 else #text)
		if part ~= "" then
			table.insert(benefits, "• " .. part)
		end
		if not cut then
			break
		end
		start = cut + 2
	end
	infoCard(root, 2, pick(SUB.Name), benefits, Theme.Cosmic2)
	if isClub() then
		local claim = note(root, "", 3, Theme.Up)
		addDynamic(dynamics, claim, function(): string
			local o = offers()
			if num(o.ClubClaimDay, 0) == num(o.Today, -1) then
				return T("shop.club.claimed", duration(nextUtcMidnight() - clockNow()))
			end
			local preview = o.Preview
			local value = if type(preview) == "table" then preview[SUB.DailyVoucher] else nil
			return T("shop.club.claimReady", credits(num(value, 0)))
		end)
		local row = UI.Row(root, 4, 44)
		UI.Button({
			Size = UDim2.fromOffset(240, 40),
			Text = T("shop.club.claim"),
			Variant = "Success",
			MaxText = 16,
			Parent = row,
		}, claimClub)
		note(root, T("shop.club.member"), 5, Theme.Muted)
	elseif offers().ClubEligible == true then
		local cards = grid(root, 3)
		itemCard(cards, 1, SUB.Key, { Highlight = true })
	else
		note(root, T("shop.restricted"), 3, Theme.Muted)
	end
end

local function render()
	local root = body
	if not root or not window or not window.IsOpen then
		return
	end
	table.clear(dynamics)
	clearChildren(root)
	local builder = Builders[currentTab] or Builders.Start
	local ok, err = pcall(builder, root)
	if not ok then
		warn("[Shop] Reiter " .. currentTab .. ": " .. tostring(err))
	end
end

local function queueRender()
	if renderQueued then
		return
	end
	renderQueued = true
	task.delay(RENDER_DELAY, function()
		renderQueued = false
		render()
		if detailKey then
			renderDetail()
		end
	end)
end

-- =====================================================================
-- 6) DETAILS (exakte Wirkung vor jedem Kauf)
-- =====================================================================
local function detailLine(text: string, order: number, color: Color3?, bold: boolean?): TextLabel
	local list = detailList :: ScrollingFrame
	return UI.Create("TextLabel", {
		Name = "Line",
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		FontFace = if bold then UI.Faces.BodyBold else UI.Faces.Body,
		TextSize = DETAIL_TEXT,
		TextColor3 = color or Theme.Text2,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = text,
		LayoutOrder = order,
		ZIndex = 32,
		Parent = list,
	})
end

local function detailButton(
	text: string,
	variant: string,
	order: number,
	width: number,
	onClick: () -> (),
	enabled: boolean?
)
	local buttons = detailButtons :: Frame
	local on = enabled ~= false
	local button = UI.Button({
		Size = UDim2.fromOffset(width, 44),
		Text = text,
		Variant = if on then variant else "Muted",
		MaxText = 16,
		LayoutOrder = order,
		ZIndex = 32,
		Parent = buttons,
	}, function()
		if on then
			onClick()
		end
	end)
	return button
end

-- Empfänger-Auswahl für den Geschenk-Boost (nur andere Spieler im Server)
local function giftPicker(order: number): number
	local list = detailList :: ScrollingFrame
	local others: { Player } = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and #others < MAX_GIFT_TARGETS then
			table.insert(others, other)
		end
	end
	if #others == 0 then
		detailLine(T("shop.gift.none"), order, Theme.Muted)
		return order + 1
	end
	detailLine(T("shop.gift.pick"), order, Theme.Text, true)
	local holder: Frame = UI.Create("Frame", {
		Name = "Recipients",
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order + 1,
		ZIndex = 32,
		Parent = list,
	}, {
		UI.Create("UIGridLayout", {
			CellSize = UDim2.fromOffset(190, 38),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for i, other in ipairs(others) do
		local selected = giftChoice == other.UserId
		UI.Button({
			Text = other.DisplayName,
			Variant = if selected then "Primary" else "Secondary",
			MaxText = 15,
			LayoutOrder = i,
			ZIndex = 33,
			Parent = holder,
		}, function()
			giftChoice = other.UserId
			renderDetail()
		end)
	end
	if giftChoice then
		local target = Players:GetPlayerByUserId(giftChoice)
		if target then
			detailLine(T("shop.gift.selected", target.DisplayName), order + 2, Theme.Pink, true)
		else
			giftChoice = nil
		end
	end
	return order + 3
end

renderDetail = function()
	local key = detailKey
	local frame, list, buttons = detailFrame, detailList, detailButtons
	if not key or not frame or not list or not buttons then
		return
	end
	local entry, kind = itemOf(key)
	if entry == nil or kind == nil then
		closeDetail()
		return
	end
	table.clear(detailDynamics)
	clearChildren(list)
	clearChildren(buttons)
	local color = accentFor(entry, kind)
	if detailTitle then
		detailTitle.Text = UI.Upper(T("shop.details") .. " · " .. pick(entry.Name))
	end
	if detailAccent then
		detailAccent.BackgroundColor3 = color
	end
	local productKind = kindKey(entry, kind)
	-- Studio: auch ohne Id durch die Server-Vorprüfung (Policy-/Geschenk-Tests), danach Hinweis "Kauf simulieren"
	local purchasable = (configured(entry, kind) or RunService:IsStudio()) and not isDisabled(key)
	local owned = (kind == "Pass" and hasPass(key)) or (kind == "Subscription" and isClub())
	local order = 1
	detailLine(T("item.kind." .. productKind), order, color, true)
	order += 1
	detailLine(T("shop.effectHeader"), order, Theme.Text, true)
	order += 1
	detailLine(pick(entry.Desc), order, Theme.Text)
	order += 1

	-- besondere Zeilen je Art
	if key == "Income2x" or key == "Income3x" then
		detailLine(T("shop.together4"), order, Theme.Accent, true)
		detailLine(T("shop.togetherNote"), order + 1, Theme.Text2)
		order += 2
	end
	local extraButtons: { { Text: string, Variant: string, Fn: () -> () } } = {}
	if kind == "Pass" and type(entry.Includes) == "table" then
		local ownedParts, missing = bundleParts(entry)
		detailLine(T("shop.bundleParts", partNames(entry.Includes)), order, Theme.Text2)
		order += 1
		local saveLabel = detailLine("", order, Theme.Up, true)
		addDynamic(detailDynamics, saveLabel, function(): string
			return bundleSaveText(entry) or ""
		end)
		order += 1
		if not hasPass(key) and #missing == 0 then
			detailLine(T("shop.bundleAllOwned"), order, Theme.Muted, true)
			purchasable = false
			order += 1
		elseif not hasPass(key) and #ownedParts > 0 then
			detailLine(T("shop.bundleOwnedParts", partNames(ownedParts)), order, Theme.Warn, true)
			detailLine(T("shop.bundleSingles", partNames(missing)), order + 1, Theme.Warn)
			order += 2
			for _, part in ipairs(missing) do
				local partEntry = SHOP.PassesByKey[part]
				if partEntry then
					table.insert(extraButtons, {
						Text = pick(partEntry.Name),
						Variant = "Secondary",
						Fn = function()
							openDetail(part)
						end,
					})
				end
			end
		end
	elseif kind == "Pass" and hasPass(key) then
		local bundle = SHOP.PassesByKey.TycoonBundle
		if bundle and type(bundle.Includes) == "table" and table.find(bundle.Includes, key) and hasPass(bundle.Key) then
			detailLine(T("shop.passInBundle"), order, Theme.Up, true)
			order += 1
		end
	end
	if productKind == "Voucher" then
		if quote and quote.Key == key then
			local q = quote :: QuoteInfo
			detailLine(T("shop.quoteLine", credits(q.Credits)), order, Theme.Up, true)
			local valid = detailLine("", order + 1, Theme.Text2)
			addDynamic(detailDynamics, valid, function(): string
				local left = q.Until - clockNow()
				return if left > 0 then T("shop.quoteValid", duration(left)) else T("shop.quoteExpired")
			end)
			order += 2
			if q.Until <= clockNow() then
				table.insert(extraButtons, {
					Text = T("shop.recalc"),
					Variant = "Secondary",
					Fn = function()
						quote = nil
						requestQuote(key)
					end,
				})
			end
		elseif quoteFailed == key then
			detailLine(T("shop.quoteExpired"), order, Theme.Muted)
			order += 1
			table.insert(extraButtons, {
				Text = T("shop.recalc"),
				Variant = "Secondary",
				Fn = function()
					quoteFailed = nil
					requestQuote(key)
				end,
			})
		else
			detailLine(T("shop.quoteLoading"), order, Theme.Muted)
			order += 1
			if not quoteLoading then
				requestQuote(key)
			end
		end
		detailLine(T("shop.quoteHint"), order, Theme.Text2)
		detailLine(T("shop.onlyCr"), order + 1, Theme.Up)
		order += 2
	elseif productKind == "Express" then
		local seconds = num(entry.Express, 0)
		local info = detailLine("", order, Theme.Cyan, true)
		addDynamic(detailDynamics, info, function(): string
			local tower = state().Tower
			local build = type(tower) == "table" and tower.Build or nil
			if type(build) == "table" and build.Floor ~= nil then
				local left = num(build.Until, 0) - clockNow()
				local effect = if left <= seconds
					then T("shop.express.finish")
					else T("shop.express.shorten", duration(seconds))
				return T("shop.express.build", duration(left)) .. " " .. effect
			end
			local tokens = type(tower) == "table" and type(tower.Tokens) == "table" and tower.Tokens.Express or 0
			return T("shop.express.token", num(tokens, 0))
		end)
		order += 1
	elseif productKind == "Starter" then
		local starter = state().Starter
		if type(starter) == "table" and starter.Bought == true then
			local preview = offers().Preview
			local value = if type(preview) == "table" then num(preview.CreditsM, 0) else 0
			detailLine(T("shop.starter.bought", credits(value * 2)), order, Theme.Warn, true)
			order += 1
		end
	elseif productKind == "Season" then
		if offers().SeasonPremium == true then
			detailLine(T("shop.season.premiumActive"), order, Theme.Up, true)
			purchasable = false
			order += 1
		end
	elseif productKind == "Parade" then
		local info = detailLine("", order, Theme.Gold, true)
		addDynamic(detailDynamics, info, function(): string
			local left = paradeLeft()
			return if left > 0 then T("shop.parade.active", duration(left)) else ""
		end)
		order += 1
	elseif productKind == "Gift" then
		detailLine(T("shop.gift.rule"), order, Theme.Text2)
		order += 1
		if not tradingAllowed() then
			detailLine(T("shop.giftBlocked"), order, Theme.Down, true)
			purchasable = false
			order += 1
		else
			order = giftPicker(order)
			if giftChoice == nil then
				purchasable = false
			end
		end
	elseif kind == "Subscription" then
		if isClub() then
			detailLine(T("shop.club.member"), order, Theme.Up, true)
			order += 1
		elseif offers().ClubEligible ~= true then
			detailLine(T("shop.restricted"), order, Theme.Muted, true)
			purchasable = false
			order += 1
		end
	end

	detailLine(T("shop.firewall"), order, Theme.Muted)
	order += 1
	local priceLabel = detailLine("", order, Theme.Warn, true)
	setPrice(priceLabel, entry, kind)
	order += 1
	if not configured(entry, kind) then
		detailLine(T("shop.notSetUp"), order, Theme.Muted)
		order += 1
	elseif isDisabled(key) then
		detailLine(T("shop.disabled"), order, Theme.Muted)
		order += 1
	end
	detailLine(T("shop.robuxNote"), order, Theme.Muted)
	list.CanvasPosition = Vector2.zero

	-- Knöpfe: ruhig, ehrlich ("Weiter zum Kauf" erst nach den Details, nie "JETZT KAUFEN")
	local buttonOrder = 1
	if kind == "Subscription" and isClub() then
		detailButton(T("shop.club.claim"), "Success", buttonOrder, 220, claimClub)
		buttonOrder += 1
	elseif owned then
		detailButton(T("shop.owned"), "Muted", buttonOrder, 200, function() end, false)
		buttonOrder += 1
	else
		detailButton(T("shop.continue"), "Premium", buttonOrder, 230, function()
			purchase(key, if productKind == "Gift" then giftChoice else nil)
		end, purchasable)
		buttonOrder += 1
	end
	for _, extra in ipairs(extraButtons) do
		if buttonOrder > 4 then
			break
		end
		detailButton(extra.Text, extra.Variant, buttonOrder, 170, extra.Fn)
		buttonOrder += 1
	end
	detailButton(T("shop.close"), "Secondary", 99, 140, closeDetail)
end

openDetail = function(key: string)
	if not detailFrame then
		return
	end
	if detailKey ~= key then
		quote = nil
		quoteFailed = nil
		giftChoice = nil
	end
	detailKey = key;
	(detailFrame :: Frame).Visible = true
	renderDetail()
end

local function buildDetail(panel: Frame)
	local frame: Frame = UI.Create("Frame", {
		Name = "Details",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.02,
		Visible = false,
		Active = true,
		ZIndex = 30,
		Parent = panel,
	}, { UI.Corner(16), UI.Stroke(nil, 1) })
	detailTitle = UI.Label({
		Position = UDim2.fromOffset(20, 14),
		Size = UDim2.new(1, -80, 0, 26),
		Text = "",
		Face = "Display",
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 19,
		ZIndex = 31,
		Parent = frame,
	})
	detailAccent = UI.Create("Frame", {
		Name = "Accent",
		Position = UDim2.fromOffset(20, 44),
		Size = UDim2.fromOffset(28, 2),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		ZIndex = 31,
		Parent = frame,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	UI.Button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(36, 36),
		Text = "✕",
		Variant = "Ghost",
		MaxText = 18,
		Corner = 10,
		ZIndex = 32,
		Parent = frame,
	}, closeDetail)
	detailList = UI.Create("ScrollingFrame", {
		Position = UDim2.fromOffset(20, 58),
		Size = UDim2.new(1, -40, 1, -132),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Muted,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 31,
		Parent = frame,
	}, {
		UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }),
		UI.Create("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }),
	})
	detailButtons = UI.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -32, 0, 56),
		BackgroundTransparency = 1,
		ZIndex = 31,
		Parent = frame,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 10),
		}),
	})
	detailFrame = frame
end

-- =====================================================================
-- 7) FENSTER
-- =====================================================================
local function isCompact(): boolean
	local gui = ctx and ctx.Gui
	if not gui then
		return false
	end
	local width = gui.AbsoluteSize.X / UI.ScaleOf(gui)
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	return width < WINDOW_W + 40 or (touchOnly and width < 1100)
end

local function startTicker()
	tickToken += 1
	local token = tickToken
	task.spawn(function()
		for _ = 1, TICK_MAX do
			if token ~= tickToken or not window or not window.IsOpen then
				return
			end
			updateDynamics(dynamics)
			if detailKey then
				updateDynamics(detailDynamics)
			end
			task.wait(1)
		end
	end)
end

local function makeTabs()
	if not window then
		return
	end
	if tabs and tabs.Frame then
		tabs.Frame:Destroy()
	end
	local options = {}
	for _, key in ipairs(TABS) do
		table.insert(options, { Key = key, Text = T(TAB_LANG[key]) })
	end
	tabs = UI.Segmented(window.Content, options, function(key: string)
		currentTab = key
		closeDetail()
		render()
	end)
	tabs.Frame.LayoutOrder = 2
end

local function destroyWindow()
	if window then
		if window.IsOpen then
			UI.CloseWindow(window)
		end
		window.Group:Destroy()
	end
	window = nil
	tabs = nil
	body = nil
	detailFrame = nil
	detailList = nil
	detailButtons = nil
	detailTitle = nil
	detailAccent = nil
	table.clear(dynamics)
	table.clear(detailDynamics)
end

local function ensureWindow()
	if window and builtLang == lang() then
		return
	end
	destroyWindow()
	window = if isCompact()
		then UI.Sheet(T("shop.title"), SHEET_H)
		else UI.Window(T("shop.title"), WINDOW_W, WINDOW_H, Theme.Accent)
	builtLang = lang()
	-- Kopf-Banner: "Kurse kann man nicht kaufen – alles Spielgeld"
	local banner = UI.Card({
		Name = "Banner",
		Size = UDim2.new(1, -4, 0, 70),
		BackgroundColor3 = Theme.Bg2,
		LayoutOrder = 1,
		Parent = window.Content,
	})
	UI.Gradient(Theme.Surface2, Theme.Bg2, 0).Parent = banner
	UI.Create("Frame", {
		Name = "Bar",
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(0, 3, 1, -20),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Parent = banner,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	UI.Label({
		Name = "Logo",
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.fromOffset(46, 46),
		Text = "Λ",
		Face = "Display",
		TextColor3 = Theme.LogoRing,
		MaxText = 34,
		Parent = banner,
	})
	UI.Label({
		Name = "Title",
		Position = UDim2.fromOffset(72, 10),
		Size = UDim2.new(1, -88, 0, 26),
		Text = UI.Upper(T("shop.banner")),
		Face = "Display",
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 18,
		Parent = banner,
	})
	UI.Label({
		Name = "Sub",
		Position = UDim2.fromOffset(72, 38),
		Size = UDim2.new(1, -88, 0, 22),
		Text = T("shop.bannerSub"),
		Font = UI.Fonts.Body,
		TextColor3 = Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		MaxText = 14,
		Parent = banner,
	})
	makeTabs()
	body = UI.Create("Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = window.Content,
	}, { UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10) }) })
	buildDetail(window.Panel)
end

local function openWindow()
	ensureWindow()
	if not window then
		return
	end
	if pendingTab then
		currentTab = pendingTab
		pendingTab = nil
	end
	if tabs then
		tabs.Set(currentTab, true)
	end
	closeDetail()
	UI.OpenWindow(window)
	render()
	startTicker()
	if pendingDetail then
		local key = pendingDetail
		pendingDetail = nil
		openDetail(key)
	end
	if not shopSeenSent then
		shopSeenSent = true
		task.spawn(function()
			pcall(function()
				ctx.RequestFull("TutorialFlag", { Flag = "ShopSeen" }, true)
			end)
		end)
	end
end

local function closeWindow()
	closeDetail()
	tickToken += 1
	if window and window.IsOpen then
		UI.CloseWindow(window)
	end
end

-- Tab-Name, Alias oder Artikel-Schlüssel -> Reiter (+ Details)
function Shop.Open(tab: string?)
	if not ctx then
		return
	end
	if type(tab) == "string" then
		local alias = TAB_ALIASES[tab]
		if table.find(TABS, tab) then
			pendingTab = tab
		elseif alias then
			pendingTab = alias
		elseif itemOf(tab) ~= nil then
			pendingTab = tabOf(tab)
			pendingDetail = tab
		end
	end
	if window and window.IsOpen then
		-- schon offen: direkt umschalten
		if pendingTab then
			currentTab = pendingTab
			pendingTab = nil
			if tabs then
				tabs.Set(currentTab, true)
			end
			render()
		end
		if pendingDetail then
			local key = pendingDetail
			pendingDetail = nil
			openDetail(key)
		end
		return
	end
	ctx.Windows.Open("Shop")
end

-- =====================================================================
-- 8) ANGEBOTS-KARTE (max. 1 je Sitzung, ruhig, nie über Terminal/Tutorial/Warnung)
-- =====================================================================
local function hideOffer()
	offerToken += 1
	local card = offerCard
	offerCard = nil
	if card and card.Parent then
		local tween = TweenService:Create(card, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = card.Position + UDim2.fromOffset(0, 24),
		})
		tween.Completed:Once(function()
			card:Destroy()
		end)
		tween:Play()
	end
end

-- ein ruhiger Moment? (kein Fenster/Terminal/Order-Ticket, kein Tutorial, keine Markt-Warnung, kein Admin-Abuse)
local function calmMoment(): boolean
	if UI.IsAnyWindowOpen() then
		return false
	end
	local okTerminal, terminalOpen = callModule("Terminal", "IsOpen")
	if okTerminal and terminalOpen == true then
		return false
	end
	local okTutorial, tutorialActive = callModule("Tutorial", "IsActive")
	if okTutorial and tutorialActive == true then
		return false
	end
	local event = state().Event
	if type(event) == "table" and event.AdminAbuse == true then
		return false
	end
	local market = state().Market
	if type(market) == "table" and market.AdminWindow == true then
		return false
	end
	return os.clock() >= marketBusyUntil
end

function Shop.ShowOffer(key: string)
	if not ctx or not ctx.Gui then
		return
	end
	local entry, kind = itemOf(key)
	if entry == nil or kind == nil then
		return
	end
	hideOffer()
	offerToken += 1
	local token = offerToken
	local color = accentFor(entry, kind)
	local card = UI.Panel({
		Name = "ShopOffer",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -124),
		Size = UDim2.fromOffset(440, 150),
		ZIndex = 20,
		Parent = ctx.Gui,
	})
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
		stroke.Transparency = 0.4
	end
	iconBadge(card, entry, color, 52, UDim2.fromOffset(16, 18))
	UI.Chip(card, T("shop.offer.tip"), color, { Position = UDim2.fromOffset(82, 16) })
	UI.Label({
		Position = UDim2.fromOffset(82, 42),
		Size = UDim2.new(1, -98, 0, 26),
		Text = pick(entry.Name),
		Face = "Display",
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 18,
		ZIndex = 21,
		Parent = card,
	})
	UI.Label({
		Position = UDim2.fromOffset(82, 70),
		Size = UDim2.new(1, -98, 0, 20),
		Text = T("shop.offer.lead"),
		Font = UI.Fonts.Body,
		TextColor3 = Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		MaxText = 14,
		ZIndex = 21,
		Parent = card,
	})
	local row: Frame = UI.Create("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -12),
		Size = UDim2.new(1, -96, 0, 36),
		BackgroundTransparency = 1,
		ZIndex = 21,
		Parent = card,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
	})
	UI.Button({
		Size = UDim2.fromOffset(130, 36),
		Text = T("shop.view"),
		Variant = "Primary",
		MaxText = 15,
		LayoutOrder = 1,
		ZIndex = 22,
		Parent = row,
	}, function()
		hideOffer()
		Shop.Open(key)
	end)
	UI.Button({
		Size = UDim2.fromOffset(110, 36),
		Text = T("shop.later"),
		Variant = "Ghost",
		MaxText = 15,
		LayoutOrder = 2,
		ZIndex = 22,
		Parent = row,
	}, hideOffer)
	-- sanft von unten herein (iOS-artig), nach einer Weile von selbst weg
	local rest = card.Position
	card.Position = rest + UDim2.fromOffset(0, 24)
	TweenService
		:Create(card, TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = rest })
		:Play()
	offerCard = card
	task.delay(OFFER_AUTO_HIDE, function()
		if offerToken == token then
			hideOffer()
		end
	end)
end

-- Server hat ein Angebot freigegeben (State "Offers") -> auf einen ruhigen Moment warten, sonst entfällt es
local function maybeOffer()
	local o = offers()
	local id = num(o.Id, 0)
	local key = o.Pending
	if id <= lastOfferId or type(key) ~= "string" or key == "" then
		return
	end
	lastOfferId = id
	task.spawn(function()
		local waited = 0
		local limit = math.max(10, num(SHOP.OfferClientWait, 120))
		while waited <= limit do
			if calmMoment() then
				Shop.ShowOffer(key)
				return
			end
			task.wait(OFFER_CHECK_GAP)
			waited += OFFER_CHECK_GAP
		end
	end)
end

-- =====================================================================
-- 9) CHAT-TAGS [VIP] / [Club] (nur Anzeige auf diesem Gerät, aus den Player-Attributen)
-- =====================================================================
local function tag(text: string, color: Color3): string
	return ('<font color="%s">[%s]</font>'):format(UI.ColorHex(color), text)
end

local function installChatTags()
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		return
	end
	TextChatService.OnIncomingMessage = function(message: TextChatMessage): TextChatMessageProperties?
		local source = message.TextSource
		if not source then
			return nil -- System-/Spielnachrichten bleiben, wie sie sind
		end
		local sender = Players:GetPlayerByUserId(source.UserId)
		if not sender then
			return nil
		end
		local parts: { string } = {}
		if sender:GetAttribute("Vip") == true then
			table.insert(parts, tag(T("shop.chat.vip"), Theme.Gold))
		end
		if sender:GetAttribute("Club") == true then
			table.insert(parts, tag(T("shop.chat.club"), Theme.Cosmic3))
		end
		if #parts == 0 then
			return nil
		end
		local props = Instance.new("TextChatMessageProperties")
		props.PrefixText = table.concat(parts, " ") .. " " .. message.PrefixText
		return props
	end
end

-- =====================================================================
-- 10) INIT / START
-- =====================================================================
-- State-Schlüssel, die den Aufbau eines Reiters ändern (Zahlen wie Boost-Restzeit/Baustelle laufen über die
-- 1-s-Aktualisierung, häufige Schlüssel wie Credits/Tower lösen bewusst keinen Neuaufbau aus)
local RELEVANT: { string } = {
	"Passes",
	"Club",
	"Boosts",
	"Offers",
	"Starter",
	"TradingAllowed",
	"RandomAllowed",
}

function Shop.Init(context: any)
	ctx = context
	ctx.Windows.Register("Shop", openWindow, closeWindow)
	ctx.Hooks.On("State", function(_state: { [string]: any }, changed: { [any]: any })
		if type(changed) ~= "table" then
			return
		end
		if changed.Offers then
			maybeOffer()
		end
		if window and window.IsOpen then
			for _, key in ipairs(RELEVANT) do
				if changed[key] then
					queueRender()
					break
				end
			end
		end
	end)
	ctx.Hooks.On("Settings", function()
		if builtLang ~= "" and builtLang ~= lang() then
			local wasOpen = window ~= nil and window.IsOpen
			if wasOpen then
				ctx.Windows.Close("Shop")
			end
			destroyWindow()
			builtLang = ""
			if wasOpen then
				Shop.Open(currentTab)
			end
		end
	end)
	-- Markt-Warnung/Crash/Rally: in dieser Zeit kein Angebot (Muss-Regel 17)
	ctx.Hooks.On("Market:Event", function(data: any)
		if type(data) ~= "table" then
			return
		end
		if data.Phase == "Warn" or data.Phase == "Run" then
			marketBusyUntil = math.max(marketBusyUntil, os.clock() + MARKET_EVENT_HOLD)
			hideOffer()
		elseif data.Phase == "End" then
			marketBusyUntil = os.clock() + MARKET_EVENT_TAIL
		end
	end)
	ctx.Hooks.On("WindowOpened", function(name: string)
		if name ~= "Shop" then
			hideOffer() -- Terminal/Willkommen-Bericht/… haben Vorrang
		end
	end)
end

function Shop.Start()
	-- Kauf abgeschlossen -> Details schließen (die Gutschrift meldet der Server)
	MarketplaceService.PromptProductPurchaseFinished:Connect(
		function(userId: number, _productId: number, purchased: boolean)
			if purchased and userId == player.UserId then
				closeDetail()
			end
		end
	)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(who: Player, _passId: number, purchased: boolean)
		if purchased and who == player then
			closeDetail()
		end
	end)
	local ok, err = pcall(installChatTags)
	if not ok then
		warn("[Shop] Chat-Tags: " .. tostring(err))
	end
	-- schon vorhandener State (z. B. nach Modul-Neustart)
	maybeOffer()
end

return Shop
