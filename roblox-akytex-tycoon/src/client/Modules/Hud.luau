-- =====================================================================
--  AKYTEX TYCOON – HUD (Client/Modules/Hud)
--  Besitzer: WP2 (Client-Plattform & UI-Kit). Vertrag: DESIGN.md §C7.5, §D WP2 (HUD), §B4.6 (Tresor-Ring),
--  §B5.2 (Multiplikator-Chip + Aufschlüsselung), §B1/§B2 (Pillen), §B7.1 (TRADE). Basis: CC-Hud (REUSE §1.4 ADAPT).
--
--  Aufbau (AKYTEX-Glas, alles über dem einen Root unter ctx.Gui):
--    · Ticker-Leiste oben (Einstellung "TickerBar"): Laufband aller Kurse aus Hook "Quotes" (UI.Ticker)
--    · Pillen oben Mitte: Glocke (immer), Welt-Event, Termine, Boost, ADMIN-ABUSE, Tresor voll – max. 4
--    · Stats-Karte oben links: CR-Zähler (rollt), AKY-Depotwert-Chip, Vermögen; Multiplikator-Chip „x7,4“ ->
--      Aufschlüsselungs-Sheet aus State.Income.Parts (jede Quelle mit Wert, Herkunft und Restzeit)
--    · Tresor-Ring neben der Karte: Füllstand (32 Segmente, zwischen State-Updates mit Income.PerSec hochgerechnet),
--      voll = glüht rot; Tippen = Request "TowerCollect" (Server prüft Abstand ≤ 70 Studs)
--    · großer TRADE-Knopf unten Mitte (öffnet das Terminal)
--    · rechte Knöpfe Tower/Shop/Quests/Akademie/Garage/Social/Bestenlisten/Einstellungen (Admin 99 fügt AdminPanel an)
--    · FPS/Ping/Speicher oben rechts (Einstellung "ShowNet")
--  Tasten T/B/N/J (Controls-Aktionen Terminal/Tower/Shop/Quests) öffnen die Fenster, falls deren Modul die Taste
--  nicht selbst behandelt (Rückfall ohne Doppel-Umschalten).
--
--  Öffentliche API (§C7.5):
--    Hud.AddRightButton(icon, captionKey, color, order, onClick): UI.Button
--                                          Standard-Slots: Tower 10, Shop 20, Quests 30, Academy 40, Garage 50,
--                                          Social 60, Boards 70, Settings 80 – gleiche Order oder gleiches Icon
--                                          übernimmt den Slot (kein doppelter Knopf). Admin = 99 (AdminPanel).
--    Hud.SetVisible(on)
--    Hud.SetPill(key, text?, untilUnix?)   key ∈ Bell, WorldEvent, Earnings, Boost, AdminAbuse, Vault; text nil = weg.
--                                          "%s" im Text = Restzeit (sonst angehängt). Eigene Pillen haben Vorrang
--                                          vor den automatischen des HUD.
--    Hud.CreditsAnchor(): Vector2?          Bildschirmpunkt des CR-Zählers (Ziel für den CR-Flug)
--    Hud.PulseCredits(amount?)
--  Zusätzlich: Hud.RightButton(key): UI.Button? (Badges setzen), Hud.Refresh(state), Hud.Tick(), Hud.Init(ctx), Hud.Start()
-- =====================================================================

local Players = game:GetService("Players")
local Stats = game:GetService("Stats")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent:WaitForChild("UI"))

local Hud = {}

local Theme = UI.Theme
local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)

local SQUARE = 82 -- quadratische Menü-Knöpfe (PC/Controller)
local SQUARE_TOUCH = 74
local SQUARE_GAP = 10
local TRADE_W = 300
local TRADE_H = 88
local STATS_W = 304
local STATS_H = 118
local RING_SIZE = 104
local PILL_ORDER = { "AdminAbuse", "Vault", "Boost", "Bell", "WorldEvent", "Earnings" }
local PILL_COLORS: { [string]: Color3 } = {
	AdminAbuse = Theme.Down,
	Vault = Theme.Warn,
	Boost = Theme.Up,
	Bell = Theme.Gold,
	WorldEvent = Theme.Accent,
	Earnings = Theme.Purple,
}
local PILL_KEYS: { [string]: boolean } = {
	Bell = true,
	WorldEvent = true,
	Earnings = true,
	Boost = true,
	AdminAbuse = true,
	Vault = true,
}
-- Standard-Knöpfe rechts: Fenster (frozen Namen §C7.3)
local RIGHT_BUTTONS = {
	{ Key = "Tower", Icon = "🏙️", Caption = "ui.btn.tower", Color = Theme.Accent, Order = 10 },
	{ Key = "Shop", Icon = "🛍️", Caption = "ui.btn.shop", Color = Theme.Warn, Order = 20 },
	{ Key = "Quests", Icon = "📋", Caption = "ui.btn.quests", Color = Theme.Up, Order = 30 },
	{ Key = "Academy", Icon = "🎓", Caption = "ui.btn.academy", Color = Theme.Cyan, Order = 40 },
	{ Key = "Garage", Icon = "🚗", Caption = "ui.btn.garage", Color = Theme.Purple, Order = 50 },
	{ Key = "Social", Icon = "🤝", Caption = "ui.btn.social", Color = Theme.Pink, Order = 60 },
	{ Key = "Boards", Icon = "🏆", Caption = "ui.btn.boards", Color = Theme.Gold, Order = 70 },
	{ Key = "Settings", Icon = "⚙️", Caption = "ui.btn.settings", Color = Theme.Muted, Order = 80 },
}
-- Controls-Aktion -> Fenster (Rückfall-Tasten)
local HOTKEY_WINDOWS = { Terminal = "Terminal", Tower = "Tower", Shop = "Shop", Quests = "Quests" }
-- Multiplikator-Gruppen in Anzeigereihenfolge (Types.MultPart.Group)
local MULT_GROUPS = { "Perm", "Trader", "Pass", "Fixed", "Timed" }
local SOURCE_COLORS: { [string]: Color3 } = {
	Earned = Theme.Accent,
	Skill = Theme.Up,
	Bought = Theme.Warn,
	Event = Theme.Purple,
}
local RING_PULSE_INFO = TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

type Pill = { Text: string, Until: number? }
type DefaultSlot = { Order: number, Icon: string, Button: UI.Button, Adopted: boolean, Handler: () -> () }
type PillUi = { Frame: Frame, Dot: Frame, Label: TextLabel }

local ctx: any = nil
local root: Frame? = nil
local tickerBar: Frame? = nil
local ticker: UI.Ticker? = nil
local pillHolder: Frame? = nil
local stats: Frame? = nil
local rightBar: Frame? = nil
local rightGrid: UIGridLayout? = nil
local tradeButton: UI.Button? = nil
local netLabel: TextLabel? = nil
local crLabel: TextLabel? = nil
local crScale: UIScale? = nil
local crCounter: UI.Counter? = nil
local akyCounter: UI.Counter? = nil
local wealthLabel: TextLabel? = nil
local multButton: TextButton? = nil
local multLabel: TextLabel? = nil
local multScale: UIScale? = nil
local vaultFrame: Frame? = nil
local vaultTicks: { Frame } = {}
local vaultCounter: UI.Counter? = nil
local vaultCaption: TextLabel? = nil
local vaultGlow: UIStroke? = nil
local vaultPulse: Tween? = nil

local forcedVisible = true
local rightButtons: { { Button: UI.Button, Key: string, Caption: string } } = {}
local rightByKey: { [string]: UI.Button } = {}
local defaultSlots: { DefaultSlot } = {}
local usedOrders: { [number]: boolean } = {}
local manualPills: { [string]: Pill? } = {}
local autoPills: { [string]: Pill? } = {}
local pillUi: { [string]: PillUi } = {}
local lastQuotes: any = nil
local tickerClock = 0
local instrumentCache: { [number]: any } = {}
local instrumentScanned = false
local lastMult = 1
local lastMultPop = 0
local firstCredits = true
local firstNav = true
local vaultBase = 0
local vaultCap = 0
local vaultClock = os.clock()
local vaultShownTicks = -1
local vaultShownColor: Color3? = nil
local vaultFull = false
local boostBase: { [string]: number } = {}
local boostClock = os.clock()
local multSheet: any = nil
local multSheetKey = ""
local multCountdowns: { { Label: TextLabel, Until: number } } = {}
local lastTopOffset = -1

-- ---------------------------------------------------------------------
-- HILFEN
-- ---------------------------------------------------------------------
local function T(key: string, ...: any): string
	if ctx and type(ctx.T) == "function" then
		return ctx.T(key, ...)
	end
	return key
end

local function lang(): string
	if ctx and type(ctx.Lang_) == "function" then
		local ok, value = pcall(ctx.Lang_)
		if ok and (value == "de" or value == "en") then
			return value
		end
	end
	return "en"
end

local function hasKey(key: string): boolean
	local L = ctx and ctx.Lang
	if L and type(L.Has) == "function" then
		local ok, has = pcall(L.Has, key)
		return ok and has == true
	end
	return false
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function setting(key: string): any
	local module = ctx and ctx.Modules and ctx.Modules.Settings
	if module and type(module.Get) == "function" then
		local ok, settings = pcall(module.Get)
		if ok and type(settings) == "table" then
			return settings[key]
		end
	end
	local config = ctx and ctx.Config
	local defaults = config and config.Client and config.Client.DefaultSettings
	return defaults and defaults[key]
end

local function hudCfg(key: string, fallback: number): number
	local config = ctx and ctx.Config
	local hud = config and config.Client and config.Client.Hud
	local value = hud and hud[key]
	if type(value) == "number" and value == value then
		return value
	end
	return fallback
end

local function moduleCall(name: string, fnName: string, ...: any): (boolean, any, any)
	local module = ctx and ctx.Modules and ctx.Modules[name]
	local fn = module and module[fnName]
	if type(fn) ~= "function" then
		return false, nil, nil
	end
	return pcall(fn, ...)
end

local function formatCall(fnName: string, ...: any): string?
	local format = ctx and ctx.Format
	local fn = format and format[fnName]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, text = pcall(fn, ...)
	if ok and type(text) == "string" then
		return text
	end
	return nil
end

local function fallbackNumber(n: number): string
	local util = ctx and ctx.Util
	if util and type(util.FormatNumber) == "function" then
		local ok, text = pcall(util.FormatNumber, n)
		if ok and type(text) == "string" then
			return text
		end
	end
	return tostring(math.floor(n))
end

-- CR: kurz (1,25 Mio.) oder lang (1.250.000) je Einstellung "NumberStyle"
local function formatCredits(n: number): string
	if setting("NumberStyle") == "long" and math.abs(n) < 9e15 then
		return formatCall("Int", math.floor(n + 0.5), lang()) or fallbackNumber(n)
	end
	return formatCall("Credits", math.floor(n + 0.5), lang()) or fallbackNumber(n)
end

local function formatAky(cents: number): string
	return formatCall("Aky", math.floor(cents + 0.5), lang(), true) or (fallbackNumber(cents / 100) .. " AKY")
end

local function formatMult(x: number): string
	return formatCall("Mult", x, lang()) or ("x" .. UI.FormatMult(x))
end

local function formatDuration(seconds: number): string
	return formatCall("Duration", math.max(0, seconds), lang())
		or string.format("%d:%02d", math.floor(math.max(0, seconds) / 60), math.floor(math.max(0, seconds)) % 60)
end

-- additiver Anteil "+0,1" (Perm-Gruppe)
local function formatAdd(v: number): string
	local text = formatCall("Mult", math.abs(v), lang()) or UI.FormatMult(math.abs(v))
	text = string.gsub(text, "^x", "")
	return (if v < 0 then "-" else "+") .. text
end

local function inputKind(): string
	local ok, kind = moduleCall("Controls", "Input")
	if ok and type(kind) == "string" then
		return kind
	end
	return "KBM"
end

-- ---------------------------------------------------------------------
-- RECHTE KNÖPFE
-- ---------------------------------------------------------------------
-- Quadratischer Knopf (AKYTEX): Sekundär-Fläche, Emoji oben, kurzes Wort in GROSSBUCHSTABEN darunter,
-- unten ein feiner Streifen in der Farbe des Bereichs (Akzent, keine Vollfläche)
local function squareButton(
	parent: Instance,
	icon: string,
	caption: string,
	color: Color3,
	order: number,
	onClick: () -> ()
): UI.Button
	local button = UI.Button({
		Size = UDim2.fromOffset(SQUARE, SQUARE),
		Text = icon,
		Sub = UI.Upper(caption),
		Variant = "Secondary",
		LayoutOrder = order,
		MaxText = 32,
		SubMax = 12,
		Corner = 12,
		Parent = parent,
	}, onClick)
	UI.Create("Frame", {
		Name = "Accent",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -5),
		Size = UDim2.new(0, 22, 0, 3),
		BackgroundColor3 = if typeof(color) == "Color3" then color else Theme.Accent,
		BorderSizePixel = 0,
		ZIndex = button.Button.ZIndex + 1,
		Parent = button.Button,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	return button
end

-- Standard-Slot übernehmen: gleiche Order oder gleiches Icon wie ein Standard-Knopf -> kein zweiter Knopf
local function adoptSlot(icon: string, key: string, color: Color3, order: number, onClick: () -> ()): UI.Button?
	for _, slot in ipairs(defaultSlots) do
		if not slot.Adopted and (slot.Order == order or slot.Icon == icon) then
			slot.Adopted = true
			slot.Handler = onClick
			slot.Button.SetText(icon)
			slot.Button.SetSub(UI.Upper(T(key)))
			local accent = slot.Button.Button:FindFirstChild("Accent")
			if accent and accent:IsA("Frame") and typeof(color) == "Color3" then
				accent.BackgroundColor3 = color
			end
			for _, entry in ipairs(rightButtons) do
				if entry.Button == slot.Button then
					entry.Caption = key
					entry.Key = key
				end
			end
			return slot.Button
		end
	end
	return nil
end

function Hud.AddRightButton(
	icon: string,
	captionKey: string,
	color: Color3,
	order: number,
	onClick: () -> ()
): UI.Button
	local bar = rightBar
	assert(bar, "Hud.Init zuerst aufrufen")
	local key = if type(captionKey) == "string" then captionKey else ""
	local wanted = if type(order) == "number" then math.floor(order) else 50
	local adopted = adoptSlot(tostring(icon), key, color, wanted, onClick)
	if adopted then
		return adopted
	end
	-- eindeutige LayoutOrder (gleiche Nummer -> dahinter einsortieren)
	local layoutOrder = wanted
	local guard = 0
	while usedOrders[layoutOrder] and guard < 1000 do
		layoutOrder += 1
		guard += 1
	end
	usedOrders[layoutOrder] = true
	local button = squareButton(bar, tostring(icon), T(key), color, layoutOrder, function()
		local ok, err = pcall(onClick)
		if not ok then
			warn("[Hud] Knopf " .. key .. ": " .. tostring(err))
		end
	end)
	table.insert(rightButtons, { Button = button, Key = key, Caption = key })
	return button
end

function Hud.RightButton(key: string): UI.Button?
	return rightByKey[key]
end

local function toggleWindow(name: string)
	local windows = ctx and ctx.Windows
	if windows and type(windows.Toggle) == "function" then
		windows.Toggle(name)
	end
end

local function openTerminal()
	local windows = ctx and ctx.Windows
	if windows and type(windows.IsOpen) == "function" and windows.IsOpen("Terminal") then
		windows.Close("Terminal")
		return
	end
	local ok = moduleCall("Terminal", "Open")
	if not ok and windows then
		windows.Open("Terminal")
	end
end

-- ---------------------------------------------------------------------
-- AUFBAU
-- ---------------------------------------------------------------------
local function buildTicker(parent: Frame)
	local height = hudCfg("TickerHeight", 28)
	local bar: Frame = UI.Create("Frame", {
		Name = "TickerBar",
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = Theme.Bg2,
		BackgroundTransparency = 0.22,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 2,
		Parent = parent,
	})
	UI.Create("Frame", {
		Name = "Line",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Theme.Border,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = bar,
	})
	local inner: Frame = UI.Create("Frame", {
		Name = "Inner",
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -20, 1, -1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = bar,
	})
	tickerBar = bar
	ticker = UI.Ticker(inner)
end

local function buildPills(parent: Frame)
	pillHolder = UI.Create("Frame", {
		Name = "Pills",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(0, hudCfg("PillHeight", 30)),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = parent,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
	})
end

local function pillFor(key: string): PillUi
	local existing = pillUi[key]
	if existing then
		return existing
	end
	local height = hudCfg("PillHeight", 30)
	local frame: Frame = UI.Create("Frame", {
		Name = key,
		Size = UDim2.fromOffset(0, height),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Visible = false,
		LayoutOrder = table.find(PILL_ORDER, key) or 99,
		ZIndex = 3,
		Parent = pillHolder,
	}, {
		UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		UI.Create("UIStroke", {
			Color = PILL_COLORS[key] or Theme.Border,
			Transparency = 0.55,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		UI.Create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 14) }),
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
	})
	local dot: Frame = UI.Create("Frame", {
		Name = "Dot",
		Size = UDim2.fromOffset(7, 7),
		BackgroundColor3 = PILL_COLORS[key] or Theme.Accent,
		BorderSizePixel = 0,
		LayoutOrder = 1,
		ZIndex = 3,
		Parent = frame,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local label: TextLabel = UI.Create("TextLabel", {
		Name = "Text",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		FontFace = UI.Faces.BodyBold,
		TextSize = 14,
		TextColor3 = Theme.Text,
		Text = "",
		LayoutOrder = 2,
		ZIndex = 3,
		Parent = frame,
	})
	local ui: PillUi = { Frame = frame, Dot = dot, Label = label }
	pillUi[key] = ui
	return ui
end

local function buildStats(parent: Frame)
	local frame = UI.Panel({
		Name = "Stats",
		Size = UDim2.fromOffset(STATS_W, STATS_H),
		Position = UDim2.fromOffset(12, 40),
		ZIndex = 2,
		Parent = parent,
	})
	stats = frame
	UI.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		Parent = frame,
	})
	-- Zeile 1: CR (groß, rollend) – grüner Sechskant-Chip
	local crIcon = UI.CurrencyIcon(frame, "CR", 24)
	crIcon.Position = UDim2.fromOffset(0, 7)
	local cr = UI.Label({
		Name = "Credits",
		Position = UDim2.fromOffset(32, 0),
		Size = UDim2.new(1, -104, 0, 38),
		Text = "0",
		Face = "Display",
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 30,
		ZIndex = 3,
		Parent = frame,
	})
	crScale = UI.Create("UIScale", { Parent = cr })
	crLabel = cr
	crCounter = UI.Counter(cr, formatCredits)
	-- Multiplikator-Chip oben rechts („x7,4“, Tippen -> Aufschlüsselung)
	local chip: TextButton = UI.Create("TextButton", {
		Name = "Multiplier",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 6),
		Size = UDim2.fromOffset(66, 26),
		BackgroundColor3 = Theme.Accent,
		BackgroundTransparency = 0.78,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 3,
		Parent = frame,
	}, {
		UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		UI.Create("UIStroke", {
			Color = Theme.Accent,
			Transparency = 0.3,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})
	multScale = UI.Create("UIScale", { Parent = chip })
	multLabel = UI.Label({
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		Text = "x1",
		Face = "MonoBold",
		TextColor3 = WHITE,
		MaxText = 15,
		ZIndex = 4,
		Parent = chip,
	})
	multButton = chip
	-- Zeile 2: AKY-Depotwert (blaue Münze)
	local akyIcon = UI.CurrencyIcon(frame, "AKY", 16)
	akyIcon.Position = UDim2.fromOffset(4, 48)
	local aky = UI.Label({
		Name = "Depot",
		Position = UDim2.fromOffset(28, 44),
		Size = UDim2.new(1, -28, 0, 24),
		Text = "",
		Face = "Mono",
		TextColor3 = Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 17,
		ZIndex = 3,
		Parent = frame,
	})
	akyCounter = UI.Counter(aky, function(value: number): string
		return formatAky(value)
	end)
	-- Zeile 3: Vermögen (Leaderstat des Servers)
	wealthLabel = UI.Label({
		Name = "Wealth",
		Position = UDim2.fromOffset(0, 74),
		Size = UDim2.new(1, 0, 0, 20),
		Text = "",
		Face = "Body",
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 14,
		ZIndex = 3,
		Parent = frame,
	})
end

local function buildVault(parent: Frame)
	local frame: Frame = UI.Create("Frame", {
		Name = "Vault",
		Size = UDim2.fromOffset(RING_SIZE, RING_SIZE),
		Position = UDim2.fromOffset(12 + STATS_W + 10, 40),
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = parent,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	vaultGlow = UI.Create("UIStroke", {
		Color = Theme.Border,
		Thickness = 1,
		Transparency = 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = frame,
	})
	vaultFrame = frame
	-- 32 Segmente im Kreis (gedrehte Striche außerhalb jeder Clip-Fläche)
	local count = math.clamp(math.floor(hudCfg("VaultRingTicks", 32)), 8, 64)
	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2 - math.pi / 2
		local tick: Frame = UI.Create("Frame", {
			Name = "Tick",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + math.cos(angle) * 0.42, 0.5 + math.sin(angle) * 0.42),
			Size = UDim2.new(0.03, 0, 0.1, 0),
			Rotation = math.deg(angle) + 90,
			BackgroundColor3 = Theme.Border,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = frame,
		}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		table.insert(vaultTicks, tick)
	end
	local amount = UI.Label({
		Name = "Amount",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromScale(0.64, 0.24),
		Text = "0",
		Face = "MonoBold",
		TextColor3 = Theme.Text,
		MaxText = 18,
		ZIndex = 4,
		Parent = frame,
	})
	vaultCounter = UI.Counter(amount, function(value: number): string
		local text = formatCall("Compact", math.floor(value + 0.5), lang())
		return text or fallbackNumber(value)
	end)
	vaultCaption = UI.Label({
		Name = "Caption",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.6),
		Size = UDim2.fromScale(0.6, 0.13),
		Text = UI.Upper(T("ui.hud.vault")),
		Face = "Body",
		TextColor3 = Theme.Muted,
		MaxText = 11,
		ZIndex = 4,
		Parent = frame,
	})
	local hit: TextButton = UI.Create("TextButton", {
		Name = "Collect",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 5,
		Parent = frame,
	})
	local busy = false
	hit.Activated:Connect(function()
		if busy then
			return
		end
		busy = true
		local sfx = ctx.Modules and ctx.Modules.Sfx
		if sfx and type(sfx.Play) == "function" then
			pcall(sfx.Play, "UIClick")
		end
		task.spawn(function()
			ctx.Request("TowerCollect", {})
			busy = false
		end)
	end)
end

local function buildTrade(parent: Frame)
	local trade = UI.Button({
		Name = "Trade",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(TRADE_W, TRADE_H),
		Text = T("ui.trade"),
		Sub = T("ui.tradeSub"),
		Variant = "Primary",
		Face = "Display",
		MaxText = 32,
		SubMax = 13,
		Corner = 14,
		Parent = parent,
	}, openTerminal)
	tradeButton = trade
end

local function buildRight(parent: Frame)
	local bar: Frame = UI.Create("Frame", {
		Name = "RightButtons",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(SQUARE * 2 + SQUARE_GAP, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = parent,
	})
	rightGrid = UI.Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(SQUARE, SQUARE),
		CellPadding = UDim2.fromOffset(SQUARE_GAP, SQUARE_GAP),
		FillDirection = Enum.FillDirection.Horizontal,
		FillDirectionMaxCells = 2,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = bar,
	})
	rightBar = bar
	-- Standard-Knöpfe als übernehmbare Slots (andere Pakete können sie per AddRightButton neu belegen)
	for _, spec in ipairs(RIGHT_BUTTONS) do
		local windowName = spec.Key
		local slot: DefaultSlot
		usedOrders[spec.Order] = true
		local button = squareButton(bar, spec.Icon, T(spec.Caption), spec.Color, spec.Order, function()
			local handler = slot.Handler
			local ok, err = pcall(handler)
			if not ok then
				warn("[Hud] Knopf " .. windowName .. ": " .. tostring(err))
			end
		end)
		slot = {
			Order = spec.Order,
			Icon = spec.Icon,
			Button = button,
			Adopted = false,
			Handler = function()
				toggleWindow(windowName)
			end,
		}
		table.insert(defaultSlots, slot)
		table.insert(rightButtons, { Button = button, Key = spec.Caption, Caption = spec.Caption })
		rightByKey[windowName] = button
	end
end

local function buildNet()
	netLabel = UI.Label({
		Name = "NetStats",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 34),
		Size = UDim2.fromOffset(240, 18),
		Text = "",
		Face = "Mono",
		TextColor3 = Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxText = 14,
		Outline = 1,
		Visible = false,
		ZIndex = 8,
		Parent = ctx.Gui,
	})
end

-- ---------------------------------------------------------------------
-- LAYOUT (Ticker an/aus, Touch/PC, Pillen) – Toasts rutschen unter Ticker + Pillen
-- ---------------------------------------------------------------------
local function anyPillVisible(): boolean
	for _, ui in pairs(pillUi) do
		if ui.Frame.Visible then
			return true
		end
	end
	return false
end

local function layout()
	local tickerOn = tickerBar ~= nil and (tickerBar :: Frame).Visible
	local top = if tickerOn then hudCfg("TickerHeight", 28) else 0
	local holder = pillHolder
	if holder then
		holder.Position = UDim2.new(0.5, 0, 0, top + 6)
	end
	local statsTop = top + 8
	local frame = stats
	if frame then
		frame.Position = UDim2.fromOffset(12, statsTop)
	end
	local vault = vaultFrame
	if vault then
		vault.Position = UDim2.fromOffset(12 + STATS_W + 10, statsTop + math.floor((STATS_H - RING_SIZE) / 2))
	end
	local net = netLabel
	if net then
		net.Position = UDim2.new(1, -12, 0, top + 6)
	end
	-- rechte Knöpfe: Touch 3 Spalten oben rechts (unten rechts liegt der Sprungknopf), sonst 2 Spalten Mitte rechts
	local bar, grid = rightBar, rightGrid
	if bar and grid then
		if inputKind() == "Touch" then
			grid.CellSize = UDim2.fromOffset(SQUARE_TOUCH, SQUARE_TOUCH)
			grid.FillDirectionMaxCells = 3
			bar.Size = UDim2.fromOffset(SQUARE_TOUCH * 3 + SQUARE_GAP * 2, 0)
			bar.AnchorPoint = Vector2.new(1, 0)
			bar.Position = UDim2.new(1, -12, 0, top + 30)
		else
			grid.CellSize = UDim2.fromOffset(SQUARE, SQUARE)
			grid.FillDirectionMaxCells = 2
			bar.Size = UDim2.fromOffset(SQUARE * 2 + SQUARE_GAP, 0)
			bar.AnchorPoint = Vector2.new(1, 0.5)
			bar.Position = UDim2.new(1, -14, 0.5, 0)
		end
	end
	local toastTop = top + 6 + (if anyPillVisible() then hudCfg("PillHeight", 30) + 8 else 8)
	if toastTop ~= lastTopOffset then
		lastTopOffset = toastTop
		UI.SetToastTop(toastTop)
	end
end

local function applyVisible()
	local frame = root
	if frame and frame.Visible ~= forcedVisible then
		frame.Visible = forcedVisible
	end
end

local function relabel()
	for _, entry in ipairs(rightButtons) do
		entry.Button.SetSub(UI.Upper(T(entry.Caption)))
	end
	local trade = tradeButton
	if trade then
		trade.SetText(T("ui.trade"))
		trade.SetSub(T("ui.tradeSub"))
	end
	if vaultCaption then
		vaultCaption.Text = UI.Upper(T("ui.hud.vault"))
	end
	if crCounter then
		UI.RedrawCounter(crCounter)
	end
	if akyCounter then
		UI.RedrawCounter(akyCounter)
	end
	if vaultCounter then
		UI.RedrawCounter(vaultCounter)
	end
	multSheetKey = "" -- Sheet beim nächsten Öffnen neu bauen
end

-- ---------------------------------------------------------------------
-- PILLEN
-- ---------------------------------------------------------------------
local function pillText(pill: Pill): string
	local text = pill.Text
	local untilT = pill.Until
	if untilT then
		local left = formatDuration(untilT - serverNow())
		if string.find(text, "%s", 1, true) then
			local ok, formatted = pcall(string.format, text, left)
			return if ok then formatted else text
		end
		return text .. " · " .. left
	end
	return text
end

local function renderPills()
	local maxPills = math.clamp(math.floor(hudCfg("MaxPills", 4)), 1, 6)
	if inputKind() == "Touch" then
		maxPills = math.min(maxPills, 2) -- Handy: oben ist wenig Platz zwischen Karte und Knöpfen
	end
	local shown = 0
	local now = serverNow()
	for _, key in ipairs(PILL_ORDER) do
		local pill = manualPills[key]
		if pill and pill.Until and pill.Until <= now then
			manualPills[key] = nil -- abgelaufen
			pill = nil
		end
		pill = pill or autoPills[key]
		if pill and pill.Until and pill.Until <= now then
			pill = nil
		end
		local visible = pill ~= nil and shown < maxPills
		if visible and pill then
			shown += 1
			local ui = pillFor(key)
			local text = pillText(pill)
			if ui.Label.Text ~= text then
				ui.Label.Text = text
			end
			if not ui.Frame.Visible then
				ui.Frame.Visible = true
			end
		else
			local ui = pillUi[key]
			if ui and ui.Frame.Visible then
				ui.Frame.Visible = false
			end
		end
	end
	layout()
end

function Hud.SetPill(key: string, text: string?, untilUnix: number?)
	if type(key) ~= "string" or not PILL_KEYS[key] then
		warn("[Hud] Unbekannter Pillen-Schlüssel: " .. tostring(key))
		return
	end
	if type(text) ~= "string" or text == "" then
		manualPills[key] = nil
	else
		local untilT = if type(untilUnix) == "number" and untilUnix == untilUnix then untilUnix else nil
		manualPills[key] = { Text = string.sub(text, 1, 120), Until = untilT }
	end
	renderPills()
end

-- Anzeigename eines Welt-Events (ui.event.<Kind>, sonst allgemein)
local function eventName(kind: any): string
	if type(kind) == "string" and kind ~= "" and hasKey("ui.event." .. kind) then
		return T("ui.event." .. kind)
	end
	return T("ui.event.generic")
end

-- automatische Pillen aus dem State (Glocke, Boost, Welt-Event, ADMIN-ABUSE, Tresor voll)
local function computeAutoPills()
	local state = ctx and ctx.State or {}
	local now = serverNow()
	-- Glocke: nächster Börsentag-Beginn (alle Server gleich, Clock)
	local clock = ctx and ctx.Clock
	local dayTicks = if clock and type(clock.DAY_TICKS) == "number" then clock.DAY_TICKS else 1200
	local tick = math.floor(now)
	if clock and type(clock.Tick) == "function" then
		local ok, value = pcall(clock.Tick)
		if ok and type(value) == "number" then
			tick = value
		end
	end
	local toBell = dayTicks - (tick % dayTicks)
	local depot = state.Depot
	local transferWaiting = type(depot) == "table" and depot.TransferReady == false
	autoPills.Bell = {
		Text = if transferWaiting then T("ui.pill.bellTransfer") else T("ui.pill.bell"),
		Until = now + toBell,
	}
	-- Boost: stärkster aktiver persönlicher Boost (x5 > x2 > Bulle), Restzeit seit dem letzten State
	local elapsed = os.clock() - boostClock
	local function boostLeft(kind: string): number
		return math.max(0, (boostBase[kind] or 0) - elapsed)
	end
	local x5, x2, bull = boostLeft("X5"), boostLeft("X2"), boostLeft("Bull")
	if x5 > 0 then
		autoPills.Boost = { Text = T("ui.pill.boost", "x5"), Until = now + x5 }
	elseif x2 > 0 then
		autoPills.Boost = { Text = T("ui.pill.boost", "x2"), Until = now + x2 }
	elseif bull > 0 then
		autoPills.Boost = { Text = T("ui.pill.boostBull"), Until = now + bull }
	else
		autoPills.Boost = nil
	end
	-- ADMIN-ABUSE (Fenster zählt nicht für die Liga)
	local event = state.Event
	local market = state.Market
	local abuse = (type(event) == "table" and event.AdminAbuse == true)
		or (type(market) == "table" and market.AdminWindow == true)
	autoPills.AdminAbuse = if abuse then { Text = T("ui.pill.adminAbuse"), Until = nil } else nil
	-- Welt-Event: läuft gerade eins -> Restzeit, sonst das nächste
	local worldPill: Pill? = nil
	if type(event) == "table" then
		local active = event.Active
		if type(active) == "table" then
			for _, entry in ipairs(active) do
				if type(entry) == "table" and type(entry.Until) == "number" and entry.Until > now then
					worldPill = { Text = T("ui.pill.eventLive", eventName(entry.Kind)), Until = entry.Until }
					break
				end
			end
		end
		local nextEvent = event.Next
		if not worldPill and type(nextEvent) == "table" and type(nextEvent.At) == "number" and nextEvent.At > now then
			worldPill = { Text = T("ui.pill.eventNext", eventName(nextEvent.Kind)), Until = nextEvent.At }
		end
	end
	autoPills.WorldEvent = worldPill
	-- Tresor voll
	autoPills.Vault = if vaultFull then { Text = T("ui.pill.vaultFull"), Until = nil } else nil
end

-- ---------------------------------------------------------------------
-- TRESOR-RING
-- ---------------------------------------------------------------------
local function setVaultRing(ratio: number)
	local count = #vaultTicks
	if count == 0 then
		return
	end
	local lit = math.clamp(math.floor(ratio * count + 0.5), 0, count)
	if ratio > 0 and lit == 0 then
		lit = 1
	end
	local warnAt = hudCfg("VaultWarn", 0.85)
	local color = if ratio >= 0.999 then Theme.Down elseif ratio >= warnAt then Theme.Warn else Theme.Accent
	if lit == vaultShownTicks and color == vaultShownColor then
		return
	end
	vaultShownTicks, vaultShownColor = lit, color
	for i, tick in ipairs(vaultTicks) do
		local want = if i <= lit then color else Theme.Border
		if tick.BackgroundColor3 ~= want then
			tick.BackgroundColor3 = want
		end
	end
end

local function setVaultFull(full: boolean)
	if full == vaultFull then
		return
	end
	vaultFull = full
	local glow = vaultGlow
	if not glow then
		return
	end
	if vaultPulse then
		vaultPulse:Cancel()
		vaultPulse = nil
	end
	if full then
		glow.Color = Theme.Down
		glow.Thickness = 2
		glow.Transparency = 0
		local pulse = TweenService:Create(glow, RING_PULSE_INFO, { Transparency = 0.7 })
		vaultPulse = pulse
		pulse:Play()
	else
		glow.Color = Theme.Border
		glow.Thickness = 1
		glow.Transparency = 0
	end
end

local function updateVault()
	local income = ctx and ctx.State and ctx.State.Income
	local perSec = if type(income) == "table" and type(income.PerSec) == "number" then income.PerSec else 0
	local predicted = vaultBase
	if vaultCap > 0 and perSec > 0 then
		predicted = math.min(vaultCap, vaultBase + perSec * math.max(0, os.clock() - vaultClock))
	end
	if vaultCounter then
		UI.SetCounter(vaultCounter, predicted)
	end
	local ratio = if vaultCap > 0 then math.clamp(predicted / vaultCap, 0, 1) else 0
	setVaultRing(ratio)
	setVaultFull(vaultCap > 0 and ratio >= 0.999)
end

-- ---------------------------------------------------------------------
-- MULTIPLIKATOR-AUFSCHLÜSSELUNG (Sheet): jede Quelle mit Wert, Herkunft und Restzeit (§B5.2, Abnahme 4)
-- ---------------------------------------------------------------------
local function partName(key: string): string
	local langKey = "ui.mult.key." .. key
	if hasKey(langKey) then
		return T(langKey)
	end
	return key
end

local function buildMultSheet()
	local sheet = multSheet
	if not sheet then
		return
	end
	local content: ScrollingFrame = sheet.Content
	for _, child in ipairs(content:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	table.clear(multCountdowns)
	sheet.TitleLabel.Text = UI.Upper(T("ui.mult.title"))
	local income = ctx.State and ctx.State.Income
	local mult = if type(income) == "table" and type(income.Mult) == "number" then income.Mult else 1
	local perSec = if type(income) == "table" and type(income.PerSec) == "number" then income.PerSec else 0
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	-- Kopf: Gesamt-Multiplikator + Einkommen
	local head = UI.Card({ Size = UDim2.new(1, 0, 0, 70), LayoutOrder = nextOrder(), Parent = content })
	UI.Label({
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(0.5, 0, 0, 18),
		Text = T("ui.mult.total"),
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 14,
		Parent = head,
	})
	UI.Label({
		Position = UDim2.fromOffset(14, 26),
		Size = UDim2.new(0.5, 0, 0, 36),
		Text = formatMult(mult),
		Face = "Display",
		TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 32,
		Parent = head,
	})
	UI.Label({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.new(0.5, -14, 0, 22),
		Text = T("ui.mult.income", formatCredits(perSec)),
		Face = "Mono",
		TextColor3 = Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxText = 16,
		Parent = head,
	})
	-- Quellen je Gruppe
	local parts = if type(income) == "table" and type(income.Parts) == "table" then income.Parts else {}
	local any = false
	for _, group in ipairs(MULT_GROUPS) do
		local inGroup: { any } = {}
		for _, part in ipairs(parts) do
			if type(part) == "table" and part.Group == group and type(part.Value) == "number" then
				table.insert(inGroup, part)
			end
		end
		if #inGroup > 0 then
			any = true
			UI.Section(content, T("ui.mult.group." .. group), nextOrder(), Theme.Accent)
			for _, part in ipairs(inGroup) do
				local card = UI.RowCard(content, nextOrder(), 48)
				UI.Label({
					Position = UDim2.fromOffset(14, 0),
					Size = UDim2.new(0.45, -14, 1, 0),
					Text = partName(tostring(part.Key or "?")),
					TextColor3 = Theme.Text,
					TextXAlignment = Enum.TextXAlignment.Left,
					MaxText = 15,
					Parent = card,
				})
				local source = tostring(part.Source or "Earned")
				local chip = UI.Chip(card, UI.Upper(T("ui.mult.src." .. source)), SOURCE_COLORS[source] or Theme.Muted)
				chip.AnchorPoint = Vector2.new(0, 0.5)
				chip.Position = UDim2.new(0.45, 0, 0.5, 0)
				local value = if group == "Perm" then formatAdd(part.Value) else formatMult(part.Value)
				UI.Label({
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -14, 0, 6),
					Size = UDim2.new(0.25, 0, 0, 20),
					Text = value,
					Face = "MonoBold",
					TextColor3 = if part.Source == "Bought" then Theme.Warn else Theme.Text,
					TextXAlignment = Enum.TextXAlignment.Right,
					MaxText = 16,
					Parent = card,
				})
				local untilT = part.Until
				local left = UI.Label({
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -14, 0, 26),
					Size = UDim2.new(0.3, 0, 0, 16),
					Text = if type(untilT) == "number"
						then T("ui.mult.left", formatDuration(untilT - serverNow()))
						else "",
					Face = "Mono",
					TextColor3 = Theme.Muted,
					TextXAlignment = Enum.TextXAlignment.Right,
					MaxText = 12,
					Parent = card,
				})
				if type(untilT) == "number" then
					table.insert(multCountdowns, { Label = left, Until = untilT })
				end
			end
		end
	end
	if not any then
		UI.Label({
			Size = UDim2.new(1, 0, 0, 40),
			Text = T("ui.mult.empty"),
			Face = "Body",
			TextColor3 = Theme.Text2,
			TextWrapped = true,
			MaxText = 15,
			LayoutOrder = nextOrder(),
			Parent = content,
		})
	end
	-- ehrlicher Hinweis (Firewall §0.4): Multiplikatoren wirken nur auf Turm-Einkommen
	UI.Label({
		Size = UDim2.new(1, 0, 0, 44),
		Text = T("ui.mult.note"),
		Face = "Body",
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 13,
		LayoutOrder = nextOrder(),
		Parent = content,
	})
end

local function incomeKey(): string
	local income = ctx.State and ctx.State.Income
	if type(income) ~= "table" then
		return "none|" .. lang()
	end
	local parts = {}
	if type(income.Parts) == "table" then
		for _, part in ipairs(income.Parts) do
			if type(part) == "table" then
				table.insert(
					parts,
					tostring(part.Key) .. "=" .. tostring(part.Value) .. "/" .. tostring(part.Until or "")
				)
			end
		end
	end
	return tostring(income.Mult) .. "|" .. tostring(income.PerSec) .. "|" .. table.concat(parts, ",") .. "|" .. lang()
end

local function openMultSheet()
	if not multSheet then
		multSheet = UI.Sheet(T("ui.mult.title"), 460)
	end
	local sheet = multSheet
	if sheet.IsOpen then
		UI.CloseWindow(sheet)
		return
	end
	local key = incomeKey()
	if key ~= multSheetKey then
		multSheetKey = key
		buildMultSheet()
	end
	UI.OpenWindow(sheet)
end

-- ---------------------------------------------------------------------
-- LAUFBAND: Kurse aus dem letzten Frame (Hook "Quotes"), Firmenkürzel aus MarketClient/Config.Companies
-- ---------------------------------------------------------------------
local function scanCompanies()
	if instrumentScanned then
		return
	end
	instrumentScanned = true
	local companies = ctx.Config and ctx.Config.Companies
	if type(companies) ~= "table" then
		return
	end
	local function take(list: any)
		if type(list) ~= "table" then
			return
		end
		for _, inst in pairs(list) do
			if type(inst) == "table" and type(inst.Id) == "number" and type(inst.Ticker) == "string" then
				instrumentCache[inst.Id] = inst
			end
		end
	end
	take(companies)
	take(companies.Instruments)
	take(companies.List)
	take(companies.Etfs)
end

local function instrumentOf(id: number): any
	local cached = instrumentCache[id]
	if cached then
		return cached
	end
	local ok, inst = moduleCall("MarketClient", "Instrument", id)
	if ok and type(inst) == "table" and type(inst.Ticker) == "string" then
		instrumentCache[id] = inst
		return inst
	end
	scanCompanies()
	return instrumentCache[id]
end

-- Veränderung seit Tagesbeginn als Anteil (MarketClient.Quote; Cent-Angabe wird umgerechnet)
local function changeOf(id: number, close: number): number?
	local ok, _, change = moduleCall("MarketClient", "Quote", id)
	if not ok or type(change) ~= "number" or change ~= change then
		return nil
	end
	if math.abs(change) > 1 then
		local open = close - change
		if open <= 0 then
			return nil
		end
		return change / open
	end
	return change
end

local function refreshTicker()
	local bar, band = tickerBar, ticker
	if not bar or not band then
		return
	end
	local wanted = setting("TickerBar") ~= false
	local frame = lastQuotes
	local rows: { any } = {}
	if wanted and type(frame) == "table" and type(frame.Rows) == "table" then
		for _, row in ipairs(frame.Rows) do
			if type(row) == "table" and type(row.Id) == "number" and type(row.Close) == "number" then
				local inst = instrumentOf(row.Id)
				if inst and inst.Set ~= "Tutorial" then
					table.insert(rows, {
						Ticker = inst.Ticker,
						Price = row.Close,
						Change = changeOf(row.Id, row.Close),
					})
				end
			end
		end
	end
	local visible = wanted and #rows > 0
	if bar.Visible ~= visible then
		bar.Visible = visible
		layout()
	end
	if visible then
		band.SetRows(rows)
	end
end

-- ---------------------------------------------------------------------
-- DATEN
-- ---------------------------------------------------------------------
function Hud.Refresh(state: { [string]: any })
	if type(state) ~= "table" then
		return
	end
	if crCounter and type(state.Credits) == "number" then
		UI.SetCounter(crCounter, state.Credits, firstCredits)
		firstCredits = false
	end
	local depot = state.Depot
	if akyCounter and type(depot) == "table" and type(depot.Nav) == "number" then
		UI.SetCounter(akyCounter, depot.Nav, firstNav)
		firstNav = false
	end
	local income = state.Income
	if type(income) == "table" and type(income.Mult) == "number" and income.Mult == income.Mult then
		local text = formatMult(income.Mult)
		local label = multLabel
		if label and label.Text ~= text then
			label.Text = text
		end
		-- Chip ploppt, wenn der Multiplikator steigt (Kauf/Effizienz sofort sichtbar, §0.8 Punkt 3)
		local now = os.clock()
		if income.Mult > lastMult + 1e-6 and multScale and now - lastMultPop >= hudCfg("MultPopGap", 0.6) then
			lastMultPop = now
			UI.Pulse(multScale :: UIScale, 0.18)
		end
		lastMult = income.Mult
		if multSheet and multSheet.IsOpen then
			local key = incomeKey()
			if key ~= multSheetKey then
				multSheetKey = key
				buildMultSheet()
			end
		end
	end
end

local function onState(state: any, changed: any)
	if type(state) ~= "table" then
		return
	end
	Hud.Refresh(state)
	local all = type(changed) ~= "table"
	if all or changed.Tower or changed.Income then
		local tower = state.Tower
		if type(tower) == "table" then
			vaultBase = if type(tower.Vault) == "number" then tower.Vault else vaultBase
			vaultCap = if type(tower.VaultCap) == "number" then tower.VaultCap else vaultCap
			vaultClock = os.clock()
		end
		updateVault()
	end
	if all or changed.Boosts then
		local boosts = state.Boosts
		table.clear(boostBase)
		if type(boosts) == "table" then
			for _, kind in ipairs({ "X2", "X5", "Bull" }) do
				local value = boosts[kind]
				if type(value) == "number" and value == value and value > 0 then
					boostBase[kind] = value
				end
			end
		end
		boostClock = os.clock()
	end
	if all or changed.Boosts or changed.Event or changed.Market or changed.Depot then
		computeAutoPills()
		renderPills()
	end
end

-- Jede Sekunde: Tresor-Hochrechnung, Pillen-Countdowns, Laufband, Vermögen, FPS/Ping
function Hud.Tick()
	updateVault()
	computeAutoPills()
	renderPills()
	tickerClock += 1
	if tickerClock >= hudCfg("TickerRefresh", 1) then
		tickerClock = 0
		refreshTicker()
	end
	-- Vermögen aus dem Leaderstat des Servers (StringValue schon formatiert, IntValue/NumberValue -> Format)
	local label = wealthLabel
	if label then
		local leaderstats = player:FindFirstChild("leaderstats")
		local value = leaderstats and leaderstats:FindFirstChild("Vermögen")
		local text = ""
		if value and value:IsA("StringValue") then
			text = T("ui.hud.wealth", value.Value)
		elseif value and (value:IsA("IntValue") or value:IsA("NumberValue")) then
			text = T("ui.hud.wealth", formatCredits((value :: any).Value))
		end
		if label.Text ~= text then
			label.Text = text
		end
	end
	-- Restzeiten im offenen Multiplikator-Sheet
	if multSheet and multSheet.IsOpen then
		local now = serverNow()
		for _, entry in ipairs(multCountdowns) do
			local text = T("ui.mult.left", formatDuration(entry.Until - now))
			if entry.Label.Text ~= text then
				entry.Label.Text = text
			end
		end
	end
	-- FPS / Ping / Speicher
	local net = netLabel
	if not net then
		return
	end
	local show = setting("ShowNet") == true
	if net.Visible ~= show then
		net.Visible = show
	end
	if not show then
		return
	end
	local ping = player:GetAttribute("PingMs")
	if type(ping) ~= "number" then
		local ok, value = pcall(function()
			return player:GetNetworkPing() * 1000
		end)
		ping = if ok then value else 0
	end
	local memory = 0
	local okMem, mb = pcall(function()
		return Stats:GetTotalMemoryUsageMb()
	end)
	if okMem and type(mb) == "number" then
		memory = mb
	end
	local fps = if type(ctx.Fps) == "number" then ctx.Fps else 0
	net.Text = T("ui.netStats", math.floor(fps + 0.5), math.floor((tonumber(ping) or 0) + 0.5), math.floor(memory))
end

function Hud.SetVisible(on: boolean)
	forcedVisible = on == true
	applyVisible()
end

-- Bildschirmpunkt des CR-Zählers (für den CR-Flug; Effekt-Ebene hat dieselben Bildschirm-Pixel)
function Hud.CreditsAnchor(): Vector2?
	local label = crLabel
	local frame = root
	if not label or not frame or not frame.Visible then
		return nil
	end
	local pos = label.AbsolutePosition
	local size = label.AbsoluteSize
	return Vector2.new(pos.X + math.min(size.X, 40) * 0.5, pos.Y + size.Y * 0.5)
end

function Hud.PulseCredits(amount: number?)
	local scale = crScale
	if scale then
		UI.Pulse(scale, amount or 0.12)
	end
end

-- Rückfall-Tasten: Fenster nur umschalten, wenn kein anderes Modul auf dieselbe Taste reagiert hat
local function bindHotkeys()
	local controls = ctx.Modules and ctx.Modules.Controls
	if not controls or type(controls.Bind) ~= "function" then
		return
	end
	for action, windowName in pairs(HOTKEY_WINDOWS) do
		controls.Bind(action, function(state)
			if state ~= "Begin" then
				return
			end
			local windows = ctx.Windows
			if not windows or type(windows.IsOpen) ~= "function" then
				return
			end
			local before = windows.IsOpen(windowName)
			task.defer(function()
				if windows.IsOpen(windowName) == before then
					if windowName == "Terminal" then
						openTerminal()
					else
						windows.Toggle(windowName)
					end
				end
			end)
		end, -50)
	end
end

function Hud.Init(context: any)
	ctx = context
	local frame: Frame = UI.Create("Frame", {
		Name = "Hud",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = ctx.Gui,
	})
	root = frame
	buildTicker(frame)
	buildPills(frame)
	buildStats(frame)
	buildVault(frame)
	buildTrade(frame)
	buildRight(frame)
	buildNet()
	local chip = multButton
	if chip then
		chip.Activated:Connect(function()
			local sfx = ctx.Modules and ctx.Modules.Sfx
			if sfx and type(sfx.Play) == "function" then
				pcall(sfx.Play, "UIClick")
			end
			openMultSheet()
		end)
	end
	layout()

	local hooks = ctx.Hooks
	hooks.On("State", onState)
	hooks.On("Input", layout)
	hooks.On("Settings", function()
		relabel()
		refreshTicker()
		layout()
	end)
	hooks.On("Quotes", function(quoteFrame)
		local first = lastQuotes == nil
		lastQuotes = quoteFrame
		if first then
			refreshTicker()
		end
	end)
	bindHotkeys()
end

function Hud.Start()
	if ctx and type(ctx.State) == "table" then
		onState(ctx.State, nil)
	end
	computeAutoPills()
	renderPills()
end

return Hud
