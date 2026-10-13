-- =====================================================================
--  AKYTEX TYCOON – Börsengang (Vorschau + Zeremonie), Vorstand-Baum, Titel + die Fortschritts-Effekte
--  (Client/Modules/Prestige)
--  Besitzer: WP9 (Fortschritt, Tutorial, Sozial, Bestenlisten). Vertrag: DESIGN.md §B9.6 (Börsengang, Vorschau ab
--  Stufe 7, Zeremonie an der Glocke oder „Aus der Ferne läuten“ mit Kinoszene, Vorstand nur Turm/Lifestyle), §B9.5
--  (Titel), §A7 #8/#9/#11, §C7.3 (Fenster "Prestige"), §C7.4 (Effekte IpoCeremony, LicenceUp, TitleUp, QuestDone,
--  Achievement – Besitzer dieses Modul), §C7.5.
--
--  Öffentliche API (§C7.5):
--    Prestige.OpenPreview()        Fenster "Prestige" auf dem Börsengang-Tab, Vorschau wird geladen (TowerUI-Einstieg)
--  Zusätzlich: Prestige.Init(ctx), Prestige.Start(), Prestige.Tick() (1 s, Token-Ablauf)
--  Anfragen: ProgIpoPreview, ProgIpo, ProgPerk, ProgRespec, ProgTitle.   State: "Prog".
--  ReducedFx (Einstellung) kürzt jede Zeremonie (keine Kamerafahrt, kein Wackeln, weniger Konfetti).
-- =====================================================================

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent:WaitForChild("UI"))

local Prestige = {}

local Theme = UI.Theme
local player = Players.LocalPlayer

local WINDOW_W, WINDOW_H = 660, 620
local TOKEN_SECONDS = 60
local CARD_IN = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CARD_OUT = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FADE = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local CAMERA_IN = TweenInfo.new(1.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local GOLD_SEQ = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 226, 120)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(250, 204, 21)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 130, 20)),
})

local ctx: any = nil
local window: any = nil
local tab = "ipo"
local segmented: any = nil
local pages: { [string]: Frame } = {}
local fxLayer: Frame? = nil
local ui: { [string]: any } = {}
local preview: { [string]: any }? = nil
local previewAt = 0
local busy = false
local ceremonyBusy = false
local achQueue: { any } = {}
local achBusy = false

-- ---------------------------------------------------------------------
-- 1) HELFER
-- ---------------------------------------------------------------------
local function T(key: string, ...: any): string
	return ctx.T(key, ...)
end

local function lang(): string
	return ctx.Lang_()
end

local function call(name: string, fnName: string, ...: any): (boolean, any)
	local modules = ctx and ctx.Modules
	local m = modules and modules[name]
	local fn = m and m[fnName]
	if type(fn) ~= "function" then
		return false, nil
	end
	return pcall(fn, ...)
end

local function num(v: any, default: number): number
	return if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then v else default
end

local function prog(): { [string]: any }
	local p = ctx.State.Prog
	return if type(p) == "table" then p else {}
end

local function pcfg(): any
	local p = ctx.Config.Progression
	return if type(p) == "table" then p else {}
end

local function reducedFx(): boolean
	local ok, settings = call("Settings", "Get")
	return ok and type(settings) == "table" and settings.ReducedFx == true
end

local function sfx(role: string)
	call("Sfx", "Play", role)
end

local function credits(n: number): string
	local ok, text = pcall(ctx.Format.Credits, n, lang())
	return if ok then text else tostring(math.floor(n))
end

local function duration(seconds: number): string
	local ok, text = pcall(ctx.Format.Duration, math.max(0, seconds), lang())
	return if ok then text else tostring(math.floor(seconds))
end

local function titleName(key: string): string
	local def = pcfg().TitleByKey and pcfg().TitleByKey[key]
	if type(def) == "table" and type(def.Name) == "table" then
		return ctx.Lang.Pick(lang(), def.Name)
	end
	return key
end

local function licenceName(idx: number): string
	local list = pcfg().Licences
	local def = type(list) == "table" and list[idx] or nil
	if type(def) == "table" and type(def.Name) == "table" then
		return ctx.Lang.Pick(lang(), def.Name)
	end
	return tostring(idx)
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	props.Parent = parent
	if props.TextXAlignment == nil then
		props.TextXAlignment = Enum.TextXAlignment.Left
	end
	return UI.Label(props)
end

-- ---------------------------------------------------------------------
-- 2) EFFEKTE (§C7.4) – eigene Ebene über der Oberfläche, gibt keine Eingaben weg
-- ---------------------------------------------------------------------
local function layer(): Frame
	local existing = fxLayer
	if existing and existing.Parent then
		return existing
	end
	local frame: Frame = UI.Create("Frame", {
		Name = "PrestigeFX",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 60,
		Active = false,
		Parent = ctx.Gui,
	})
	fxLayer = frame
	return frame
end

-- zentrierte Karte: Titel, Untertitel, Zeilen; gold = Lizenz/Titel-Look
local function showCard(params: { [string]: any })
	local root = layer()
	local width = params.Width or 420
	local height = params.Height or 190
	local card: Frame = UI.Create("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = params.Position or UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = if params.Gold then Color3.new(1, 1, 1) else Theme.Surface,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		ZIndex = 61,
		Parent = root,
	}, { UI.Corner(18), UI.Stroke(if params.Gold then Theme.Gold else Theme.Border, 2) })
	if params.Gold then
		UI.Create("UIGradient", { Color = GOLD_SEQ, Rotation = 25, Parent = card })
	end
	local scale: UIScale = UI.Create("UIScale", { Scale = 0.82, Parent = card })
	local ink = if params.Gold then Theme.Bg else Theme.Text
	UI.Label({
		Name = "Kicker",
		Position = UDim2.fromOffset(20, 14),
		Size = UDim2.new(1, -40, 0, 20),
		Text = UI.Upper(params.Kicker or ""),
		Face = "Display",
		TextColor3 = if params.Gold then Theme.Bg2 else Theme.Accent,
		MaxText = 14,
		ZIndex = 62,
		Parent = card,
	})
	UI.Label({
		Name = "Title",
		Position = UDim2.fromOffset(20, 38),
		Size = UDim2.new(1, -40, 0, 50),
		Text = params.Title or "",
		Face = "Display",
		TextColor3 = ink,
		MaxText = 38,
		ZIndex = 62,
		Parent = card,
	})
	local lines = params.Lines or {}
	for i, line in ipairs(lines) do
		UI.Label({
			Name = "Line" .. i,
			Position = UDim2.fromOffset(20, 92 + (i - 1) * 26),
			Size = UDim2.new(1, -40, 0, 22),
			Text = line,
			Face = "BodyBold",
			TextColor3 = if params.Gold then Theme.Bg2 else Theme.Text2,
			MaxText = 18,
			ZIndex = 62,
			Parent = card,
		})
	end
	if params.Stamp then
		local stamp: TextLabel = UI.Label({
			Name = "Stamp",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -54, 0, 54),
			Size = UDim2.fromOffset(78, 78),
			Text = "✓",
			Face = "Display",
			TextColor3 = Theme.Up,
			BackgroundTransparency = 0.2,
			BackgroundColor3 = Color3.new(1, 1, 1),
			Rotation = -40,
			MaxText = 54,
			ZIndex = 63,
			Parent = card,
		})
		UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = stamp })
		UI.Create("UIStroke", { Color = Theme.Up, Thickness = 3, Parent = stamp })
		local stampScale: UIScale = UI.Create("UIScale", { Scale = 2.4, Parent = stamp })
		task.delay(0.35, function()
			TweenService:Create(stampScale, CARD_IN, { Scale = 1 }):Play()
			TweenService:Create(stamp, CARD_IN, { Rotation = -12 }):Play()
		end)
	end
	TweenService:Create(scale, CARD_IN, { Scale = 1 }):Play()
	local hold = if reducedFx() then 2.2 else (params.Hold or 3.4)
	task.delay(hold, function()
		if card.Parent then
			TweenService:Create(scale, CARD_OUT, { Scale = 0.9 }):Play()
			TweenService:Create(card, CARD_OUT, { BackgroundTransparency = 1 }):Play()
			task.delay(0.24, function()
				card:Destroy()
			end)
		end
	end)
end

local function confetti(amount: number)
	if reducedFx() then
		amount = math.min(amount, 0.4)
	end
	call("Effects", "Confetti", amount)
end

-- "LicenceUp" {Licence, Key, Basis, BauKurs, Admin?} – Stempel in der Akademie-Karte, goldene Lizenzkarte
local function onLicenceUp(_strength: number, data: any)
	if type(data) ~= "table" then
		return
	end
	local idx = math.floor(num(data.Licence, 1))
	local akyOk, basisText = pcall(ctx.Format.Aky, num(data.Basis, 0), lang(), true)
	showCard({
		Gold = true,
		Stamp = true,
		Kicker = T("prog.licence"),
		Title = licenceName(idx),
		Lines = {
			T("prog.lbl.basis", if akyOk then basisText else tostring(data.Basis)),
			T("prog.lbl.bauKurs", credits(num(data.BauKurs, 0))),
		},
		Hold = 4,
	})
	sfx("RallyFanfare")
	if data.Admin ~= true then
		confetti(0.8)
	end
end

-- "TitleUp" {Title, Fanfare} – goldener Kopftitel, eigene Fanfare für Meilenstein-Titel
local function onTitleUp(_strength: number, data: any)
	if type(data) ~= "table" or type(data.Title) ~= "string" then
		return
	end
	showCard({
		Gold = true,
		Kicker = T("prog.tab.titles"),
		Title = titleName(data.Title),
		Lines = {},
		Height = 110,
		Position = UDim2.fromScale(0.5, 0.24),
		Hold = 3,
	})
	if data.Fanfare then
		sfx("RallyFanfare")
		confetti(1)
	else
		sfx("LevelUp")
	end
end

-- "QuestDone" {Id} – Text kommt als Notify (eine Meldung, ein Weg); hier nur Puls am Quests-Knopf + Klang
local function onQuestDone(_strength: number, _data: any)
	sfx("Profit")
	local ok, button = call("Hud", "RightButton", "Quests")
	if ok and type(button) == "table" and button.Frame then
		local scale = button.Frame:FindFirstChildOfClass("UIScale")
		if not scale then
			scale = UI.Create("UIScale", { Parent = button.Frame })
		end
		UI.Pulse(scale :: UIScale, 0.12)
	end
end

local function playAchievement(entry: any)
	achBusy = true
	local root = layer()
	local card: Frame = UI.Create("Frame", {
		Name = "Achievement",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 360, 0, 150),
		Size = UDim2.fromOffset(330, 70),
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0.04,
		ZIndex = 61,
		Parent = root,
	}, { UI.Corner(14), UI.Stroke(Theme.Gold, 1.5) })
	UI.Label({
		Position = UDim2.fromOffset(12, 11),
		Size = UDim2.fromOffset(48, 48),
		Text = "🏆",
		MaxText = 34,
		ZIndex = 62,
		Parent = card,
	})
	UI.Label({
		Position = UDim2.fromOffset(70, 10),
		Size = UDim2.new(1, -82, 0, 18),
		Text = UI.Upper(T("prog.tab.ach")),
		Face = "Display",
		TextColor3 = Theme.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 12,
		ZIndex = 62,
		Parent = card,
	})
	UI.Label({
		Position = UDim2.fromOffset(70, 30),
		Size = UDim2.new(1, -82, 0, 28),
		Text = if type(entry.Name) == "table" then ctx.Lang.Pick(lang(), entry.Name) else tostring(entry.Id),
		Face = "BodyBold",
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 20,
		ZIndex = 62,
		Parent = card,
	})
	sfx("Achievement")
	TweenService:Create(card, CARD_IN, { Position = UDim2.new(1, -16, 0, 150) }):Play()
	task.delay(if reducedFx() then 2.2 else 3.6, function()
		TweenService:Create(card, CARD_OUT, { Position = UDim2.new(1, 360, 0, 150) }):Play()
		task.delay(0.25, function()
			card:Destroy()
			achBusy = false
			local nextEntry = table.remove(achQueue, 1)
			if nextEntry then
				playAchievement(nextEntry)
			end
		end)
	end)
end

-- "Achievement" {Id}
local function onAchievement(_strength: number, data: any)
	if type(data) ~= "table" or type(data.Id) ~= "string" then
		return
	end
	local byId = pcfg().AchievementById
	local entry = if type(byId) == "table" then byId[data.Id] else nil
	if not entry then
		return
	end
	if achBusy then
		if #achQueue < 8 then
			table.insert(achQueue, entry)
		end
		return
	end
	playAchievement(entry)
end

-- Position der Börsenglocke (Anker-Part der Stadt, sonst Börsensaal-Mitte aus Config.City)
local function bellPosition(): Vector3
	local anchor = workspace:FindFirstChild("Anchor_Bell", true)
	if anchor and anchor:IsA("BasePart") then
		return anchor.Position
	end
	local city = ctx.Config.City
	local zones = type(city) == "table" and city.Zones or nil
	local exchange = zones and zones.Exchange
	if exchange and typeof(exchange.Center) == "Vector3" then
		return exchange.Center + Vector3.new(0, 8, 0)
	end
	return Vector3.new(0, 8, -190)
end

local function nearBell(): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - bellPosition()).Magnitude <= 40
end

-- Kinoszene: Kamera fährt zur Glocke und zurück (überspringbar mit jeder Eingabe)
local function cinema(seconds: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local bell = bellPosition()
	local oldType = camera.CameraType
	camera.CameraType = Enum.CameraType.Scriptable
	local goal = CFrame.lookAt(bell + Vector3.new(14, 9, 26), bell)
	local tween = TweenService:Create(camera, CAMERA_IN, { CFrame = goal })
	tween:Play()
	local finished = false
	local connection: RBXScriptConnection? = nil
	local function restore()
		if finished then
			return
		end
		finished = true
		tween:Cancel()
		if connection then
			connection:Disconnect()
		end
		camera.CameraType = if oldType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else oldType
	end
	connection = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		local kind = input.UserInputType
		if
			kind == Enum.UserInputType.MouseButton1
			or kind == Enum.UserInputType.Touch
			or kind == Enum.UserInputType.Keyboard
		then
			restore()
		end
	end)
	task.delay(seconds, restore)
end

-- "IpoCeremony" {Ticker, UserId, Name, Count, Stars, Crown}
local function onIpo(_strength: number, data: any)
	if type(data) ~= "table" or type(data.Ticker) ~= "string" then
		return
	end
	if data.UserId ~= player.UserId then
		-- Server-Banner für alle anderen (der Text ist das einzige Signal)
		UI.Toast(T("prog.ipoBanner", tostring(data.Name or "?"), data.Ticker), "Announce")
		return
	end
	if ceremonyBusy then
		return
	end
	ceremonyBusy = true
	local reduced = reducedFx()
	local root = layer()
	local shade: Frame = UI.Create("Frame", {
		Name = "IpoShade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 61,
		Parent = root,
	})
	TweenService:Create(shade, FADE, { BackgroundTransparency = 0.45 }):Play()
	local bell: TextLabel = UI.Label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.16),
		Size = UDim2.fromOffset(120, 120),
		Text = "🔔",
		MaxText = 96,
		ZIndex = 62,
		Parent = shade,
	})
	local tickerLabel: TextLabel = UI.Label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.new(0.8, 0, 0, 120),
		Text = data.Ticker,
		Face = "Display",
		TextColor3 = Theme.Gold,
		MaxText = 110,
		MaxVisibleGraphemes = 0,
		ZIndex = 62,
		Parent = shade,
	})
	UI.TextStroke(1).Parent = tickerLabel
	UI.Label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.56),
		Size = UDim2.new(0.8, 0, 0, 34),
		Text = T("prog.ipoYou", data.Ticker),
		Face = "BodyBold",
		TextColor3 = Theme.Text,
		MaxText = 26,
		ZIndex = 62,
		Parent = shade,
	})
	local crown = if type(data.Crown) == "string" and data.Crown ~= "" then T("prog.crown." .. data.Crown) else ""
	UI.Label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.63),
		Size = UDim2.new(0.8, 0, 0, 28),
		Text = T("prog.lbl.ipoStars", math.floor(num(data.Stars, 0)))
			.. (if crown ~= "" then "  ·  " .. crown else ""),
		Face = "Mono",
		TextColor3 = Theme.Gold,
		MaxText = 22,
		ZIndex = 62,
		Parent = shade,
	})
	sfx("MarketBell")
	-- Glocke schwingt (4×), Ticker erscheint Buchstabe für Buchstabe
	local swings = if reduced then 1 else 4
	task.spawn(function()
		for i = 1, swings do
			local angle = if i % 2 == 1 then 18 else -18
			TweenService:Create(bell, TweenInfo.new(0.22, Enum.EasingStyle.Sine), { Rotation = angle }):Play()
			task.wait(0.24)
		end
		TweenService:Create(bell, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Rotation = 0 }):Play()
	end)
	task.spawn(function()
		for i = 1, #data.Ticker do
			tickerLabel.MaxVisibleGraphemes = i
			sfx("TickerTick")
			task.wait(if reduced then 0.05 else 0.22)
		end
		tickerLabel.MaxVisibleGraphemes = -1
	end)
	confetti(2)
	if not reduced and not nearBell() then
		cinema(4.5)
	end
	task.delay(if reduced then 3 else 6, function()
		TweenService:Create(shade, FADE, { BackgroundTransparency = 1 }):Play()
		for _, child in ipairs(shade:GetDescendants()) do
			if child:IsA("TextLabel") then
				TweenService:Create(child, FADE, { TextTransparency = 1 }):Play()
			end
		end
		task.delay(0.4, function()
			shade:Destroy()
			ceremonyBusy = false
		end)
	end)
end

-- ---------------------------------------------------------------------
-- 3) FENSTER "Prestige": Börsengang · Vorstand · Titel
-- ---------------------------------------------------------------------
local function newPage(key: string, order: number): Frame
	local page: Frame = UI.Create("Frame", {
		Name = "Page_" .. key,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Visible = false,
		Parent = window.Content,
	}, {
		UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
	})
	pages[key] = page
	return page
end

local function showTab(key: string)
	tab = key
	for name, page in pairs(pages) do
		page.Visible = name == key
	end
end

local function requestPreview()
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local reply = ctx.RequestFull("ProgIpoPreview", {}, false)
		busy = false
		if reply.Ok then
			preview = reply
			previewAt = os.clock()
			if ui.Ticker and (ui.Ticker.Text == "" or ui.Ticker.Text == nil) and type(reply.Suggest) == "string" then
				ui.Ticker.Text = reply.Suggest
			end
		end
		Prestige.Refresh()
	end)
end

local function ring()
	local p = preview
	if busy or not p or not p.Eligible or os.clock() - previewAt > TOKEN_SECONDS then
		if p and os.clock() - previewAt > TOKEN_SECONDS then
			requestPreview()
		end
		return
	end
	local ticker = string.upper(ui.Ticker and ui.Ticker.Text or "")
	busy = true
	task.spawn(function()
		local reply = ctx.RequestFull("ProgIpo", { Ticker = ticker, Token = p.Token })
		busy = false
		if reply.Ok then
			preview = nil
			ui.Ticker.Text = ""
			ctx.Windows.Close("Prestige")
		end
		Prestige.Refresh()
	end)
end

local function buildIpoPage(page: Frame)
	ui.Stats = text(page, { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 1, MaxText = 16, TextColor3 = Theme.Text2 })
	local card = UI.Card({ Size = UDim2.new(1, 0, 0, 176), LayoutOrder = 2, Parent = page })
	UI.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
		PaddingTop = UDim.new(0, 10),
		Parent = card,
	})
	UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = card })
	ui.Lines = {}
	for i = 1, 5 do
		ui.Lines[i] = text(card, {
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = i,
			Face = if i == 1 then "Display" else "BodyBold",
			MaxText = if i == 1 then 20 else 16,
			TextColor3 = if i == 1 then Theme.Gold else Theme.Text,
		})
	end
	ui.Status = text(card, { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 6, MaxText = 15 })
	UI.Section(page, T("prog.lbl.keeps"), 3, Theme.Up)
	text(page, {
		Size = UDim2.new(1, 0, 0, 54),
		LayoutOrder = 4,
		Text = T("prog.lbl.ipoKeeps"),
		TextWrapped = true,
		MaxText = 14,
		TextColor3 = Theme.Text2,
		Font = UI.Fonts.Body,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	UI.Section(page, T("prog.lbl.resets"), 5, Theme.Warn)
	text(page, {
		Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = 6,
		Text = T("prog.lbl.ipoResets"),
		TextWrapped = true,
		MaxText = 14,
		TextColor3 = Theme.Text2,
		Font = UI.Fonts.Body,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local row = UI.Row(page, 7, 46)
	ui.Ticker = UI.TextBox({
		Size = UDim2.new(0, 170, 1, 0),
		PlaceholderText = T("prog.lbl.ticker"),
		Text = "",
		Font = UI.Fonts.Main,
		Parent = row,
	})
	UI.Create("UITextSizeConstraint", { MaxTextSize = 22, Parent = ui.Ticker })
	ui.Ticker:GetPropertyChangedSignal("Text"):Connect(function()
		local raw = ui.Ticker.Text
		local clean = string.sub(string.gsub(string.upper(raw), "[^A-Z]", ""), 1, 4)
		if clean ~= raw then
			ui.Ticker.Text = clean
		end
	end)
	ui.PreviewButton = UI.Button({
		Size = UDim2.fromOffset(150, 44),
		Text = T("prog.btn.preview"),
		Variant = "Secondary",
		Parent = row,
	}, requestPreview)
	ui.RingButton = UI.Button({
		Size = UDim2.fromOffset(190, 44),
		Text = T("prog.btn.ring"),
		Variant = "Muted",
		Parent = row,
	}, ring)
	text(page, {
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = 8,
		Text = T("prog.perk.info"),
		TextWrapped = true,
		MaxText = 13,
		TextColor3 = Theme.Muted,
		Font = UI.Fonts.Body,
	})
end

local function buildBoardPage(page: Frame)
	ui.StarsLabel = text(page, { Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1, MaxText = 17, Face = "BodyBold" })
	ui.PerkRows = {}
	for i, def in ipairs(pcfg().Prestige and pcfg().Prestige.Perks or {}) do
		local card = UI.RowCard(page, 10 + i, 74)
		UI.Label({
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -200, 0, 24),
			Text = T("prog.perk." .. def.Key),
			Face = "BodyBold",
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxText = 18,
			Parent = card,
		})
		UI.Label({
			Position = UDim2.fromOffset(14, 34),
			Size = UDim2.new(1, -200, 0, 32),
			Text = T("prog.perk." .. def.Key .. ".d"),
			TextWrapped = true,
			Font = UI.Fonts.Body,
			TextColor3 = Theme.Text2,
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxText = 13,
			Parent = card,
		})
		local actions = UI.RowActions(card, 170)
		local level = UI.Label({
			Size = UDim2.fromOffset(80, 30),
			Text = "",
			Face = "Mono",
			TextColor3 = Theme.Gold,
			MaxText = 15,
			LayoutOrder = 1,
			Parent = actions,
		})
		local key = def.Key
		local button = UI.Button({
			Size = UDim2.fromOffset(76, 40),
			Text = "+ ★",
			Variant = "Premium",
			LayoutOrder = 2,
			Parent = actions,
		}, function()
			ctx.Request("ProgPerk", { Branch = key })
		end)
		ui.PerkRows[key] = { Level = level, Button = button, Max = def.Max }
	end
	local row = UI.Row(page, 50, 44)
	ui.RespecLabel = text(row, { Size = UDim2.new(1, -200, 1, 0), MaxText = 15, TextColor3 = Theme.Text2 })
	UI.Button(
		{ Size = UDim2.fromOffset(180, 42), Text = T("prog.btn.reset"), Variant = "Secondary", Parent = row },
		function()
			ctx.Request("ProgRespec", {})
		end
	)
end

local function buildTitlePage(page: Frame)
	ui.TitleList = UI.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = page,
	}, { UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }) })
	ui.TitleSig = ""
end

local function rebuildTitles()
	local p = prog()
	local owned = type(p.Titles) == "table" and p.Titles or {}
	local sig = table.concat(owned, ",") .. "|" .. tostring(p.Title) .. "|" .. lang()
	if sig == ui.TitleSig then
		return
	end
	ui.TitleSig = sig
	for _, child in ipairs(ui.TitleList:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local list = { "" }
	for _, key in ipairs(owned) do
		table.insert(list, key)
	end
	for i, key in ipairs(list) do
		local card = UI.RowCard(ui.TitleList, i, 48)
		UI.Label({
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -150, 1, 0),
			Text = if key == "" then T("prog.lbl.titleNone") else titleName(key),
			Face = "BodyBold",
			TextColor3 = if key == "" then Theme.Muted else Theme.Gold,
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxText = 18,
			Parent = card,
		})
		local active = p.Title == key
		local actions = UI.RowActions(card, 130)
		UI.Button({
			Size = UDim2.fromOffset(120, 36),
			Text = if active then T("prog.btn.selected") else T("prog.btn.select"),
			Variant = if active then "Muted" else "Secondary",
			Parent = actions,
		}, function()
			if prog().Title ~= key then
				ctx.Request("ProgTitle", { Id = key })
			end
		end)
	end
end

function Prestige.Refresh()
	if not window then
		return
	end
	local p = prog()
	ui.Stats.Text = T("prog.lbl.ipos", math.floor(num(p.Ipos, 0)))
		.. "  ·  "
		.. T("prog.lbl.stars", math.floor(num(p.Stars, 0)), math.floor(num(p.StarsTotal, 0)))
		.. "  ·  "
		.. T("prog.lbl.firm", credits(num(p.Firm, 0)))
	local pv = preview
	if pv then
		ui.Lines[1].Text = T("prog.lbl.ipoStars", math.floor(num(pv.Stars, 0)))
		ui.Lines[2].Text = T("prog.lbl.ipoFirm", credits(num(pv.Firm, 0)))
		local permOk, permText = pcall(ctx.Format.Mult, num(pv.Perm, 0.25), lang())
		ui.Lines[3].Text = T(
			"prog.lbl.ipoPerm",
			if permOk then string.gsub(permText, "^x", "") else "0,25",
			math.floor(num(pv.Next, 1))
		)
		ui.Lines[4].Text = if type(pv.Crown) == "string" and pv.Crown ~= ""
			then T("prog.lbl.ipoCrown", T("prog.crown." .. pv.Crown))
			else ""
		ui.Lines[5].Text = T("prog.lbl.ipoEstimate", duration(num(pv.EstimateSeconds, 0)))
		local expired = os.clock() - previewAt > TOKEN_SECONDS
		if pv.Eligible and not expired then
			ui.Status.Text = T("prog.lbl.ipoReady")
			ui.Status.TextColor3 = Theme.Up
			ui.RingButton.SetVariant("Premium")
		else
			ui.Status.Text = if expired then T("prog.ipoToken") else tostring(pv.Reason or "")
			ui.Status.TextColor3 = if expired then Theme.Warn else Theme.Down
			ui.RingButton.SetVariant("Muted")
		end
	else
		for i, line in ipairs(ui.Lines) do
			line.Text = if i == 1 then T("prog.btn.preview") .. " …" else ""
		end
		ui.Status.Text = ""
		ui.RingButton.SetVariant("Muted")
	end
	-- Vorstand
	local free = math.floor(num(p.Stars, 0))
	ui.StarsLabel.Text = T("prog.lbl.stars", free, math.floor(num(p.StarsTotal, 0)))
	local perks = type(p.Perks) == "table" and p.Perks or {}
	for key, row in pairs(ui.PerkRows) do
		local level = math.floor(num(perks[key], 0))
		row.Level.Text = T("prog.lbl.perkLevel", level, row.Max)
		row.Button.SetVariant(if level < row.Max and free > 0 then "Premium" else "Muted")
	end
	ui.RespecLabel.Text = if p.RespecFree then T("prog.lbl.respecFree") else T("prog.lbl.respecCost")
	rebuildTitles()
end

local function buildWindow()
	window = UI.Window(T("prog.win.prestige"), WINDOW_W, WINDOW_H, Theme.Gold)
	segmented = UI.Segmented(window.Content, {
		{ Key = "ipo", Text = T("prog.tab.ipo") },
		{ Key = "board", Text = T("prog.tab.board") },
		{ Key = "titles", Text = T("prog.tab.titles") },
	}, function(key: string)
		showTab(key)
		if key == "ipo" and not preview then
			requestPreview()
		end
		Prestige.Refresh()
	end)
	segmented.Frame.LayoutOrder = 0
	buildIpoPage(newPage("ipo", 1))
	buildBoardPage(newPage("board", 2))
	buildTitlePage(newPage("titles", 3))
	showTab(tab)
end

local function openWindow()
	if not window then
		buildWindow()
	end
	segmented.Set(tab, true)
	showTab(tab)
	UI.OpenWindow(window)
	Prestige.Refresh()
	if tab == "ipo" and (not preview or os.clock() - previewAt > TOKEN_SECONDS) then
		requestPreview()
	end
end

local function closeWindow()
	if window and window.IsOpen then
		UI.CloseWindow(window)
	end
end

function Prestige.OpenPreview()
	tab = "ipo"
	preview = nil
	ctx.Windows.Open("Prestige")
end

function Prestige.Tick()
	if window and window.IsOpen and tab == "ipo" and preview then
		Prestige.Refresh()
	end
end

function Prestige.Init(context: any)
	ctx = context
	local effects = ctx.Modules.Effects
	if effects and type(effects.Register) == "function" then
		effects.Register("IpoCeremony", onIpo)
		effects.Register("LicenceUp", onLicenceUp)
		effects.Register("TitleUp", onTitleUp)
		effects.Register("QuestDone", onQuestDone)
		effects.Register("Achievement", onAchievement)
	end
	ctx.Windows.Register("Prestige", openWindow, closeWindow)
end

function Prestige.Start()
	ctx.Hooks.On("State", function(_state: any, changed: any)
		if type(changed) == "table" and changed.Prog and window and window.IsOpen then
			Prestige.Refresh()
		end
	end)
	ctx.Hooks.On("Settings", function()
		if window then
			ui.TitleSig = ""
		end
	end)
end

return Prestige
