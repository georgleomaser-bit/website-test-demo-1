-- =====================================================================
--  CLUTCH CLASH – Lobby-HUD (Client/Modules/Hud)
--  Besitzer: WP10 (Client-Hülle). Basis: Meteor-Heist-Hud (REUSE §1.4: squareButton, squareBar,
--  AddRightButton, Badges nur bei Änderung, Refresh/Tick-Trennung). Vertrag: DESIGN.md C7.4, B3.3.
--
--  AKYTEX-Look (docs/STYLE-AKYTEX.md): Glas-Karte unten links (auf Touch oben links) mit Level, XP-Balken
--  (Accent) und 🪙 Coins, 💎 Gems, 🔑 Schlüssel (flüssig zählend, große Zahlen in Builder Sans ExtraBold).
--  Unten Mitte: großer PLAY-Knopf (Primär/Accent, Titel in Michroma; öffnet das Fenster "Play" von WP5).
--  Rechts: quadratische Menü-Knöpfe (Sekundär + feiner Farbstreifen) in 2 Spalten (AddRightButton).
--  Oben rechts (immer, wenn eingeschaltet): FPS + Ping (Einstellung "Ping/FPS zeigen").
--  Auf Touch rutscht die Anzeige nach oben (unten links liegt der Lauf-Stick); Wechsel live.
--
--  Öffentliche API (C7.4):
--    Hud.AddRightButton(icon, captionKey, color, order, onClick): UI.Button   captionKey = Lang-Schlüssel
--    Hud.SetVisible(on)
--  Zusätzlich: Hud.CoinAnchor(): Vector2? (Ziel für den Münzflug), Hud.PulseCoins(amount?),
--    Hud.Refresh(state), Hud.Tick(), Hud.Init(ctx), Hud.Start()
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stats = game:GetService("Stats")

local UI = require(script.Parent:WaitForChild("UI"))

local Hud = {}

local Theme = UI.Theme
local player = Players.LocalPlayer

local SQUARE = 82 -- quadratische Menü-Knöpfe (auch auf dem Handy ≥ 44 px nach Skalierung)
local SQUARE_GAP = 10
local PLAY_WIDTH = 300
local PLAY_HEIGHT = 84
local STATS_W = 300
local STATS_H = 122

local ctx: any = nil
local root: Frame? = nil -- alles Lobby-HUD (für SetVisible)
local stats: Frame? = nil
local rightBar: Frame? = nil
local playButton: UI.Button? = nil
local netLabel: TextLabel? = nil
local coinLabel: TextLabel? = nil
local coinScale: UIScale? = nil
local coinCounter: UI.Counter? = nil
local gemCounter: UI.Counter? = nil
local keyCounter: UI.Counter? = nil
local levelLabel: TextLabel? = nil
local xpLabel: TextLabel? = nil
local xpBar: UI.Bar? = nil
local progressMath: any = nil

local forcedVisible = true
local inCombat = false
local inMatchWorld = false
local lastLevelKey = ""
local rightButtons: { { Button: UI.Button, Key: string, Icon: string } } = {}
local usedOrders: { [number]: boolean } = {}

-- ---------------------------------------------------------------------
-- HILFEN
-- ---------------------------------------------------------------------
local function T(key: string, ...: any): string
	if ctx and type(ctx.T) == "function" then
		return ctx.T(key, ...)
	end
	return key
end

local function inputKind(): string
	local controls = ctx and ctx.Modules and ctx.Modules.Controls
	if controls and type(controls.Input) == "function" then
		local ok, kind = pcall(controls.Input)
		if ok and type(kind) == "string" then
			return kind
		end
	end
	return "KBM"
end

local function format(n: number): string
	local util = ctx and ctx.Util
	if util and type(util.FormatNumber) == "function" then
		return util.FormatNumber(n)
	end
	return tostring(math.floor(n))
end

local function setting(key: string): any
	local module = ctx and ctx.Modules and ctx.Modules.Settings
	if module and type(module.Get) == "function" then
		local ok, settings = pcall(module.Get)
		if ok and type(settings) == "table" then
			return settings[key]
		end
	end
	return nil
end

-- Quadratischer Knopf (AKYTEX): Sekundär-Fläche, Emoji oben, kurzes Wort in GROSSBUCHSTABEN darunter,
-- unten ein feiner Streifen in der Farbe des Pakets (Akzent, keine Vollfläche)
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
		MaxText = 34,
		SubMax = 13,
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

-- Leiste mit quadratischen Knöpfen in 2 Spalten (MH)
local function squareBar(
	parent: Instance,
	name: string,
	anchor: Vector2,
	position: UDim2,
	align: Enum.HorizontalAlignment
): Frame
	return UI.Create("Frame", {
		Name = name,
		AnchorPoint = anchor,
		Position = position,
		Size = UDim2.fromOffset(SQUARE * 2 + SQUARE_GAP, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = parent,
	}, {
		UI.Create("UIGridLayout", {
			CellSize = UDim2.fromOffset(SQUARE, SQUARE),
			CellPadding = UDim2.fromOffset(SQUARE_GAP, SQUARE_GAP),
			FillDirection = Enum.FillDirection.Horizontal,
			FillDirectionMaxCells = 2,
			HorizontalAlignment = align,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICH: Knöpfe rechts
-- ---------------------------------------------------------------------
function Hud.AddRightButton(
	icon: string,
	captionKey: string,
	color: Color3,
	order: number,
	onClick: () -> ()
): UI.Button
	local bar = rightBar
	assert(bar, "Hud.Init zuerst aufrufen")
	-- eindeutige LayoutOrder (gleiche Nummer -> dahinter einsortieren)
	local layoutOrder = if type(order) == "number" then math.floor(order) else 50
	local guard = 0
	while usedOrders[layoutOrder] and guard < 1000 do
		layoutOrder += 1
		guard += 1
	end
	usedOrders[layoutOrder] = true
	local key = if type(captionKey) == "string" then captionKey else ""
	local button = squareButton(bar, icon, T(key), color, layoutOrder, function()
		local ok, err = pcall(onClick)
		if not ok then
			warn("[Hud] Knopf " .. key .. ": " .. tostring(err))
		end
	end)
	table.insert(rightButtons, { Button = button, Key = key, Icon = icon })
	return button
end

local function relabel()
	for _, entry in ipairs(rightButtons) do
		entry.Button.SetSub(UI.Upper(T(entry.Key)))
	end
	local play = playButton
	if play then
		play.SetText(T("ui.play"))
		play.SetSub(T("ui.playSub"))
	end
	lastLevelKey = "" -- Level-Text neu schreiben
end

-- ---------------------------------------------------------------------
-- AUFBAU
-- ---------------------------------------------------------------------
local function buildStats(parent: Frame)
	-- Glas-Karte (Surface, leicht durchsichtig, 1-px-Rahmen)
	local frame = UI.Panel({
		Name = "Stats",
		Size = UDim2.fromOffset(STATS_W, STATS_H),
		Parent = parent,
	})
	stats = frame
	UI.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		Parent = frame,
	})
	-- Level (Michroma) + XP-Text rechts, darunter der dünne XP-Balken (Accent)
	levelLabel = UI.Label({
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(0.4, 0, 0, 20),
		Text = "LV 1",
		Font = UI.Fonts.Heading,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 15,
		Parent = frame,
	})
	xpBar = UI.Bar({
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 8),
		Color = Theme.Accent,
		MaxText = 1,
		Parent = frame,
	})
	if xpBar then
		xpBar.Text.Visible = false -- 8 px sind zu dünn für Text: der steht rechts darüber
	end
	xpLabel = UI.Label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 2),
		Size = UDim2.new(0.6, 0, 0, 16),
		Text = "",
		Font = UI.Fonts.Main,
		TextColor3 = Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxText = 13,
		Parent = frame,
	})
	-- Währungen: Coins groß, Gems + Schlüssel klein nebeneinander
	local function currency(position: UDim2, size: UDim2, font: Enum.Font, maxText: number): TextLabel
		return UI.Label({
			Position = position,
			Size = size,
			Text = "",
			Font = font,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.Text,
			MaxText = maxText,
			Parent = frame,
		})
	end
	local coins = currency(UDim2.fromOffset(0, 42), UDim2.new(1, 0, 0, 34), UI.Fonts.Strong, 30)
	coinScale = UI.Create("UIScale", { Parent = coins })
	coinLabel = coins
	local gems = currency(UDim2.fromOffset(0, 80), UDim2.new(0.5, -4, 0, 22), UI.Fonts.Main, 18)
	local keys = currency(UDim2.new(0.5, 4, 0, 80), UDim2.new(0.5, -4, 0, 22), UI.Fonts.Main, 18)
	gems.TextColor3 = Theme.Text2
	keys.TextColor3 = Theme.Text2
	coinCounter = UI.Counter(coins, function(value: number): string
		return "🪙 " .. format(value)
	end)
	gemCounter = UI.Counter(gems, function(value: number): string
		return "💎 " .. format(value)
	end)
	keyCounter = UI.Counter(keys, function(value: number): string
		return "🔑 " .. format(value)
	end)
end

local function openPlay()
	local windows = ctx.Windows
	if windows and type(windows.IsOpen) == "function" and windows.IsOpen("Play") then
		windows.Close("Play")
		return
	end
	local queue = ctx.Modules.QueueUI
	if queue and type(queue.OpenPlay) == "function" then
		local ok, err = pcall(queue.OpenPlay)
		if ok then
			return
		end
		warn("[Hud] QueueUI.OpenPlay: " .. tostring(err))
	end
	if windows and type(windows.Open) == "function" then
		windows.Open("Play")
	end
end

local function buildPlay(parent: Frame)
	local play = UI.Button({
		Name = "Play",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(PLAY_WIDTH, PLAY_HEIGHT),
		Text = T("ui.play"),
		Sub = T("ui.playSub"),
		Variant = "Primary",
		MaxText = 34,
		SubMax = 14,
		Corner = 14,
		Parent = parent,
	}, openPlay)
	play.Label.Font = UI.Fonts.Heading -- PLAY = Logo-Schrift (sparsam, kurz, GROSS)
	playButton = play
end

local function buildNet()
	netLabel = UI.Label({
		Name = "NetStats",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 4),
		Size = UDim2.fromOffset(220, 20),
		Text = "",
		Font = UI.Fonts.Number,
		TextColor3 = Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxText = 16,
		Outline = 1,
		Visible = false,
		ZIndex = 8,
		Parent = ctx.Gui,
	})
end

-- Touch: Anzeige oben links (unten links liegt der Stick), sonst unten links über dem Rand
local function layout()
	local frame = stats
	if not frame then
		return
	end
	if inputKind() == "Touch" then
		frame.AnchorPoint = Vector2.new(0, 0)
		frame.Position = UDim2.fromOffset(12, 8)
	else
		frame.AnchorPoint = Vector2.new(0, 1)
		frame.Position = UDim2.new(0, 16, 1, -14)
	end
end

local function applyVisible()
	local frame = root
	if frame then
		local visible = forcedVisible and not inCombat and not inMatchWorld
		if frame.Visible ~= visible then
			frame.Visible = visible
		end
	end
end

-- ---------------------------------------------------------------------
-- DATEN
-- ---------------------------------------------------------------------
local function xpNeeded(level: number): number?
	if progressMath and type(progressMath.XpToNext) == "function" then
		local ok, value = pcall(progressMath.XpToNext, level)
		if ok and type(value) == "number" then
			return value
		end
	end
	return nil
end

function Hud.Refresh(state: { [string]: any })
	if type(state) ~= "table" then
		return
	end
	if coinCounter and type(state.Coins) == "number" then
		UI.SetCounter(coinCounter, state.Coins)
	end
	if gemCounter and type(state.Gems) == "number" then
		UI.SetCounter(gemCounter, state.Gems)
	end
	if keyCounter and type(state.Keys) == "number" then
		UI.SetCounter(keyCounter, state.Keys)
	end
	local level = tonumber(state.Level) or 1
	local xp = tonumber(state.XP) or 0
	local nextXp = tonumber(state.XPNext) or xpNeeded(level) or 0
	local key = level .. "|" .. xp .. "|" .. nextXp
	if key ~= lastLevelKey then
		lastLevelKey = key
		if levelLabel then
			levelLabel.Text = T("ui.levelShort", math.floor(level))
		end
		local bar = xpBar
		local text = if nextXp > 0 then format(xp) .. " / " .. format(nextXp) .. " XP" else "MAX"
		if bar then
			UI.SetBar(bar, if nextXp > 0 then xp / nextXp else 1, text)
		end
		if xpLabel then
			xpLabel.Text = text
		end
	end
end

-- Jede Sekunde: FPS/Ping (nur wenn eingeschaltet)
function Hud.Tick()
	local label = netLabel
	if not label then
		return
	end
	local show = setting("ShowNet") == true
	if label.Visible ~= show then
		label.Visible = show
	end
	if not show then
		return
	end
	local ping = player:GetAttribute("PingMs")
	if type(ping) ~= "number" then
		local ok, value = pcall(function()
			return player:GetNetworkPing() * 1000
		end)
		ping = if ok then value else nil
	end
	local memory = 0
	local okMem, mb = pcall(function()
		return Stats:GetTotalMemoryUsageMb()
	end)
	if okMem and type(mb) == "number" then
		memory = mb
	end
	local fps = 0
	local settingsModule = ctx.Modules.Settings
	if settingsModule and type(settingsModule.Fps) == "function" then
		local okFps, value = pcall(settingsModule.Fps)
		fps = if okFps and type(value) == "number" then value else 0
	end
	label.Text = T("ui.netStats", math.floor(fps + 0.5), math.floor((tonumber(ping) or 0) + 0.5), math.floor(memory))
end

function Hud.SetVisible(on: boolean)
	forcedVisible = on == true
	applyVisible()
end

-- Bildschirmpunkt des Coin-Zählers (für den Münzflug; Overlay ohne UIScale = echte Pixel)
function Hud.CoinAnchor(): Vector2?
	local label = coinLabel
	if not label or not label.Visible or not root or not root.Visible then
		return nil
	end
	local pos = label.AbsolutePosition
	local size = label.AbsoluteSize
	return Vector2.new(pos.X + math.min(size.X, 40) * 0.5, pos.Y + size.Y * 0.5)
end

function Hud.PulseCoins(amount: number?)
	local scale = coinScale
	if scale then
		UI.Pulse(scale, amount or 0.12)
	end
end

function Hud.Init(context: any)
	ctx = context
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local pm = shared and shared:FindFirstChild("ProgressMath")
	if pm and pm:IsA("ModuleScript") then
		local ok, result = pcall(require, pm)
		progressMath = if ok then result else nil
	end
	local frame: Frame = UI.Create("Frame", {
		Name = "LobbyHud",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = ctx.Gui,
	})
	root = frame
	buildStats(frame)
	buildPlay(frame)
	rightBar =
		squareBar(frame, "RightButtons", Vector2.new(1, 0.5), UDim2.new(1, -14, 0.5, 0), Enum.HorizontalAlignment.Right)
	buildNet()
	layout()

	local hooks = ctx.Hooks
	hooks.On("State", function(state)
		Hud.Refresh(state)
	end)
	hooks.On("Input", layout)
	hooks.On("Settings", relabel)
	hooks.On("Armed", function()
		inCombat = true
		applyVisible()
	end)
	hooks.On("Disarmed", function()
		inCombat = false
		applyVisible()
	end)
	hooks.On("World", function(world)
		inMatchWorld = world == "Match" or world == "Crown"
		if world == "Lobby" then
			inMatchWorld = false
		end
		applyVisible()
	end)
end

function Hud.Start()
	if ctx and type(ctx.State) == "table" then
		Hud.Refresh(ctx.State)
	end
end

return Hud
