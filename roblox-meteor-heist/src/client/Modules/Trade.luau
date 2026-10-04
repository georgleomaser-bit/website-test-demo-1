-- =====================================================================
--  🤝 HANDEL (Client): Fenster mit Spieler-Liste + Einstellungen, Handelsfenster (beide Seiten),
--  Anfrage-Popup (20 s) und ein Prompt "Handeln" am Charakter der anderen Spieler (nur lokal).
--  Geprüft und getauscht wird NUR auf dem Server (TradeService). Hier wird nur angezeigt/angefragt.
--  Animationen (nur Optik): neue Sachen im Angebot ploppen auf, "Bereit" und der Countdown pulsieren,
--  beim fertigen Tausch fliegen die Karten (deine weg, seine/ihre zu dir) + Stempel "HANDEL FERTIG!".
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent:WaitForChild("UI"))

local Trade = {}

local player = Players.LocalPlayer
local ctx: any = nil
local Theme = UI.Theme
local BLACK = Color3.new(0, 0, 0)

local PROMPT_NAME = "TradePrompt"
local POP_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PULSE_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
local FLY_TIME = 0.75
local FLY_INFO = TweenInfo.new(FLY_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FADE_INFO =
	TweenInfo.new(FLY_TIME * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, FLY_TIME * 0.4)
local STAMP_IN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local STAMP_OUT = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.3)
local MAX_FLY = 12

local tradeRemote: RemoteFunction
local win: UI.Window
local listPage: Frame
local tradePage: Frame
local playerList: Frame
local blockButton: UI.Button
local waitLabel: TextLabel
local titleLabel: TextLabel
local statusLabel: TextLabel
local yourItems: Frame
local theirItems: Frame
local yourCash: TextLabel
local theirCash: TextLabel
local yourReady: TextLabel
local theirReady: TextLabel
local theirTitle: TextLabel
local cashBox: TextBox
local readyButton: UI.Button
local inventoryGrid: Frame
local inventoryTitle: TextLabel

local current: any = nil -- aktuelle Handels-Ansicht vom Server (nil = kein Handel)
local shownKeys: { [string]: { [string]: boolean } } = { You = {}, Them = {} } -- für das Aufploppen
local lastCountdown = -1
local lastReady: { [string]: boolean } = { You = false, Them = false }
local fxGui: ScreenGui? = nil
local playDone: () -> ()
local blockedRequests = false
local waitUntil = 0 -- os.clock(), ab dann darf man handeln
local closingByServer = false

-- Anfrage-Popup
type PendingRequest = { From: number, Name: string, Expires: number, Total: number }
local requests: { PendingRequest } = {}
local popup: Frame
local popupLabel: TextLabel
local popupBar: UI.Bar

-- ---------------------------------------------------------------------
-- SERVER
-- ---------------------------------------------------------------------
local function call(action: string, arg: any?, quiet: boolean?): (boolean, any)
	local ok, result = pcall(function()
		return tradeRemote:InvokeServer(action, arg)
	end)
	if not ok or type(result) ~= "table" then
		if not quiet then
			UI.Toast("📡 Keine Antwort vom Server – nochmal versuchen!", "Error")
		end
		return false, nil
	end
	if not quiet and type(result.Message) == "string" and result.Message ~= "" then
		UI.Toast(result.Message, if result.Ok then "Success" else "Error")
	end
	return result.Ok == true, result
end

-- ---------------------------------------------------------------------
-- KARTEN (ein Alien/Ei)
-- ---------------------------------------------------------------------
local function rarityColor(name: string): Color3
	local rarity = ctx.Config.RaritiesByName[name]
	return rarity and rarity.Color or Color3.new(1, 1, 1)
end

local function detailText(info: any): string
	if info.Egg then
		return "🥚 Ei"
	end
	local mut = ctx.Config.MutationsByName[info.Mut]
	local mutText = if mut and info.Mut ~= "Normal" then (mut.Icon or "") .. info.Mut .. " " else ""
	return mutText .. "Lv " .. tostring(info.Lv)
end

local function clearCards(parent: Instance)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- Kurzes Aufploppen (UIScale von klein auf 1 mit Überschwingen)
local function popIn(gui: GuiObject, from: number)
	local scale = Instance.new("UIScale")
	scale.Scale = from
	scale.Parent = gui
	TweenService:Create(scale, POP_INFO, { Scale = 1 }):Play()
end

-- Kurzes Pulsieren (einmal groß und zurück)
local function pulse(gui: GuiObject)
	local scale = gui:FindFirstChild("PulseScale")
	if not scale then
		local created = Instance.new("UIScale")
		created.Name = "PulseScale"
		created.Parent = gui
		scale = created
	end
	if scale and scale:IsA("UIScale") then
		scale.Scale = 1
		TweenService:Create(scale, PULSE_INFO, { Scale = 1.15 }):Play()
	end
end

local function makeCard(parent: Instance, info: any, order: number, onClick: (() -> ())?): Frame
	local card = UI.Card({
		Name = "Item",
		LayoutOrder = order,
		BackgroundColor3 = if info.Offered then Theme.PanelDark else Theme.PanelLight,
		Parent = parent,
	})
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = rarityColor(info.Rarity)
		stroke.Thickness = 3
	end
	UI.Label({
		Position = UDim2.fromScale(0.05, 0.04),
		Size = UDim2.fromScale(0.9, 0.36),
		Text = info.Name,
		TextColor3 = rarityColor(info.Rarity),
		MaxText = 16,
		Outline = 2,
		Parent = card,
	})
	UI.Label({
		Position = UDim2.fromScale(0.05, 0.4),
		Size = UDim2.fromScale(0.9, 0.28),
		Text = detailText(info),
		TextColor3 = Theme.SubText,
		MaxText = 13,
		Parent = card,
	})
	UI.Label({
		Position = UDim2.fromScale(0.05, 0.68),
		Size = UDim2.fromScale(0.9, 0.28),
		Text = if info.Offered then "✔ im Angebot" else ctx.Util.FormatCash(info.Income) .. "/s",
		TextColor3 = if info.Offered then Theme.Yellow else Theme.Cash,
		MaxText = 13,
		Parent = card,
	})
	if onClick then
		local button = UI.Create("TextButton", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 5,
			Parent = card,
		}) :: TextButton
		button.Activated:Connect(onClick)
	end
	return card
end

-- ---------------------------------------------------------------------
-- HANDELSFENSTER FÜLLEN
-- ---------------------------------------------------------------------
local function fillSide(grid: Frame, offer: any, mine: boolean)
	clearCards(grid)
	local side = if mine then "You" else "Them"
	local before = shownKeys[side]
	local now: { [string]: boolean } = {}
	for i, info in ipairs(offer.Items or {}) do
		local card = makeCard(
			grid,
			info,
			i,
			if mine
				then function()
					call("Remove", info.Key, true)
				end
				else nil
		)
		local key = tostring(info.Key)
		now[key] = true
		if not before[key] then
			popIn(card, 0.3) -- neu im Angebot
		end
	end
	shownKeys[side] = now
end

local function readyText(label: TextLabel, ready: boolean, side: string)
	label.Text = if ready then "✅ BEREIT" else "⏳ wartet"
	label.TextColor3 = if ready then Theme.Green else Theme.SubText
	if ready and not lastReady[side] then
		pulse(label)
	end
	lastReady[side] = ready
end

local function updateStatus()
	if not current then
		return
	end
	local endsAt = current.EndsAt
	if type(endsAt) == "number" then
		local left = math.max(0, math.ceil(endsAt - workspace:GetServerTimeNow()))
		statusLabel.Text = "🔁 Tausch in " .. left .. "..."
		statusLabel.TextColor3 = Theme.Yellow
		if left ~= lastCountdown then
			lastCountdown = left
			pulse(statusLabel)
		end
		return
	end
	lastCountdown = -1
	if current.You.Ready then
		statusLabel.Text = "Warte auf " .. current.Other.Name .. "..."
		statusLabel.TextColor3 = Theme.SubText
	else
		statusLabel.Text = "Biete etwas an und drück Bereit!"
		statusLabel.TextColor3 = Theme.SubText
	end
end

local function render()
	local view = current
	listPage.Visible = view == nil
	tradePage.Visible = view ~= nil
	if not view then
		return
	end
	local util = ctx.Util
	titleLabel.Text = "🤝 Handel mit " .. view.Other.Name
	theirTitle.Text = view.Other.Name .. " gibt"
	fillSide(yourItems, view.You, true)
	fillSide(theirItems, view.Them, false)
	yourCash.Text = "💵 " .. util.FormatCash(view.You.Cash or 0)
	theirCash.Text = "💵 " .. util.FormatCash(view.Them.Cash or 0)
	readyText(yourReady, view.You.Ready == true, "You")
	readyText(theirReady, view.Them.Ready == true, "Them")
	readyButton.SetText(if view.You.Ready then "↩️ Nicht bereit" else "✅ Bereit")
	readyButton.SetColor(if view.You.Ready then Theme.Gray else Theme.Green)
	local inventory = view.Inventory or {}
	inventoryTitle.Text = ("Deine Base (%d) – klick zum Anbieten"):format(#inventory)
	clearCards(inventoryGrid)
	for i, info in ipairs(inventory) do
		makeCard(inventoryGrid, info, i, function()
			call(if info.Offered then "Remove" else "Add", info.Key, info.Offered == true)
		end)
	end
	updateStatus()
end

-- ---------------------------------------------------------------------
-- SPIELER-LISTE
-- ---------------------------------------------------------------------
local function sendRequest(userId: number)
	call("Send", userId)
end

local function refreshPlayers()
	clearCards(playerList)
	local others = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			table.insert(others, other)
		end
	end
	table.sort(others, function(a, b)
		return a.DisplayName < b.DisplayName
	end)
	if #others == 0 then
		UI.Label({
			Size = UDim2.new(1, 0, 0, 36),
			Text = "Keine anderen Spieler hier.",
			TextColor3 = Theme.SubText,
			MaxText = 18,
			Parent = playerList,
		})
	end
	for i, other in ipairs(others) do
		local row = UI.Card({ Size = UDim2.new(1, 0, 0, 48), LayoutOrder = i, Parent = playerList })
		UI.Label({
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(1, -150, 1, -12),
			Text = other.DisplayName,
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxText = 20,
			Outline = 2,
			Parent = row,
		})
		local userId = other.UserId
		UI.Button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.fromOffset(130, 38),
			Text = "🤝 Handeln",
			Color = Theme.Cyan,
			MaxText = 18,
			Parent = row,
		}, function()
			sendRequest(userId)
		end)
	end
	local left = math.ceil(waitUntil - os.clock())
	waitLabel.Visible = left > 0
	waitLabel.Text = "⏳ Handeln geht in " .. ctx.Util.FormatTime(math.max(0, left))
	blockButton.SetText(if blockedRequests then "🚫 Anfragen: AUS" else "✅ Anfragen: AN")
	blockButton.SetColor(if blockedRequests then Theme.Red else Theme.Green)
end

-- ---------------------------------------------------------------------
-- FENSTER BAUEN
-- ---------------------------------------------------------------------
local function sideCard(parent: Instance, x: number, title: string): (Frame, TextLabel, TextLabel, TextLabel)
	local card = UI.Card({
		Position = UDim2.new(x, if x > 0 then 4 else 0, 0, 0),
		Size = UDim2.new(0.5, -4, 1, 0),
		BackgroundColor3 = Theme.PanelDark,
		Parent = parent,
	})
	local titleText = UI.Label({
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(0.6, -10, 0, 26),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Yellow,
		MaxText = 20,
		Outline = 2,
		Parent = card,
	})
	local ready = UI.Label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 4),
		Size = UDim2.new(0.4, -10, 0, 26),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxText = 16,
		Outline = 2,
		Parent = card,
	})
	local grid: Frame = UI.Create("Frame", {
		Position = UDim2.fromOffset(8, 34),
		Size = UDim2.new(1, -16, 1, -70),
		BackgroundTransparency = 1,
		Parent = card,
	}, {
		UI.Create("UIGridLayout", {
			CellSize = UDim2.new(1 / 3, -5, 0.5, -4),
			CellPadding = UDim2.fromOffset(6, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local cash = UI.Label({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -4),
		Size = UDim2.new(1, -20, 0, 28),
		Text = "💵 $0",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Cash,
		MaxText = 20,
		Outline = 2,
		Parent = card,
	})
	return grid, cash, ready, titleText
end

local function buildListPage(content: Instance)
	listPage = UI.Create("Frame", {
		Name = "List",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = content,
	}, {
		UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
	})
	UI.Section(listPage, "Spieler", 1)
	waitLabel = UI.Label({
		Size = UDim2.new(1, 0, 0, 26),
		Text = "",
		TextColor3 = Theme.Orange,
		LayoutOrder = 2,
		MaxText = 18,
		Visible = false,
		Parent = listPage,
	})
	playerList = UI.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = listPage,
	}, {
		UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }),
	})
	UI.Section(listPage, "Einstellungen", 4)
	local row = UI.Row(listPage, 5, 44)
	blockButton = UI.Button(
		{ Size = UDim2.fromOffset(220, 40), Text = "", Color = Theme.Green, MaxText = 18, Parent = row },
		function()
			local ok, result = call("Block", not blockedRequests)
			if ok and result then
				blockedRequests = result.Blocked == true
			end
			refreshPlayers()
		end
	)
	UI.Label({
		Size = UDim2.new(1, -230, 1, 0),
		Text = "Tipp: [T] bei einem Spieler",
		TextColor3 = Theme.SubText,
		MaxText = 16,
		Parent = row,
	})
end

local function buildTradePage(content: Instance)
	tradePage = UI.Create("Frame", {
		Name = "Trade",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Visible = false,
		Parent = content,
	}, {
		UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
	})
	titleLabel = UI.Section(tradePage, "🤝 Handel", 1)
	statusLabel = UI.Label({
		Size = UDim2.new(1, 0, 0, 24),
		Text = "",
		TextColor3 = Theme.SubText,
		LayoutOrder = 2,
		MaxText = 18,
		Parent = tradePage,
	})
	local sides: Frame = UI.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 230),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = tradePage,
	})
	yourItems, yourCash, yourReady = sideCard(sides, 0, "Du gibst")
	theirItems, theirCash, theirReady, theirTitle = sideCard(sides, 0.5, "Er/Sie gibt")

	local row = UI.Row(tradePage, 4, 44)
	cashBox = UI.TextBox({
		Size = UDim2.fromOffset(140, 40),
		PlaceholderText = "Cash z.B. 5000",
		Parent = row,
	})
	UI.Button(
		{ Size = UDim2.fromOffset(100, 40), Text = "💵 Setzen", Color = Theme.Cash, MaxText = 17, Parent = row },
		function()
			local amount = tonumber((cashBox.Text:gsub("[^%d]", "")))
			call("Cash", amount or 0)
		end
	)
	readyButton = UI.Button({
		Size = UDim2.fromOffset(150, 40),
		Text = "✅ Bereit",
		Color = Theme.Green,
		MaxText = 18,
		Parent = row,
	}, function()
		if current then
			call("Ready", not current.You.Ready)
		end
	end)
	UI.Button(
		{ Size = UDim2.fromOffset(110, 40), Text = "❌ Abbruch", Color = Theme.Red, MaxText = 17, Parent = row },
		function()
			call("Cancel", nil, true)
		end
	)

	inventoryTitle = UI.Section(tradePage, "Deine Base", 5)
	inventoryGrid = UI.Grid(tradePage, 6, 130, 72)
end

local function buildPopup()
	popup = UI.Create("Frame", {
		Name = "TradeRequest",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 96),
		Size = UDim2.fromOffset(340, 116),
		BackgroundColor3 = Theme.Panel,
		Visible = false,
		ZIndex = 20,
		Parent = ctx.Gui,
	}, { UI.Corner(16), UI.Stroke(BLACK, 3) })
	popupLabel = UI.Label({
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 0, 30),
		Text = "",
		MaxText = 22,
		Outline = 2,
		ZIndex = 21,
		Parent = popup,
	})
	popupBar = UI.Bar({
		Position = UDim2.fromOffset(12, 42),
		Size = UDim2.new(1, -24, 0, 14),
		Color = Theme.Cyan,
		Parent = popup,
	})
	local function answer(accept: boolean)
		local request = requests[1]
		if not request then
			return
		end
		table.remove(requests, 1)
		call("Answer", { From = request.From, Accept = accept }, not accept)
	end
	UI.Button({
		Position = UDim2.new(0, 12, 1, -50),
		Size = UDim2.new(0.5, -18, 0, 40),
		Text = "✔ Ja",
		Color = Theme.Green,
		MaxText = 20,
		ZIndex = 21,
		Parent = popup,
	}, function()
		answer(true)
	end)
	UI.Button({
		Position = UDim2.new(0.5, 6, 1, -50),
		Size = UDim2.new(0.5, -18, 0, 40),
		Text = "✖ Nein",
		Color = Theme.Red,
		MaxText = 20,
		ZIndex = 21,
		Parent = popup,
	}, function()
		answer(false)
	end)
end

local function updatePopup()
	local now = os.clock()
	for i = #requests, 1, -1 do
		if requests[i].Expires <= now then
			table.remove(requests, i)
		end
	end
	local request = requests[1]
	popup.Visible = request ~= nil and current == nil
	if request then
		popupLabel.Text = "🤝 " .. request.Name .. " will handeln!"
		UI.SetBar(popupBar, (request.Expires - now) / request.Total, "")
	end
end

-- ---------------------------------------------------------------------
-- PROMPT "HANDELN" AM CHARAKTER (nur bei mir sichtbar)
-- ---------------------------------------------------------------------
local function setPromptsEnabled()
	for _, other in ipairs(Players:GetPlayers()) do
		local character = other ~= player and other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local prompt = root and root:FindFirstChild(PROMPT_NAME)
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = current == nil
		end
	end
end

local function addPrompt(other: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or root:FindFirstChild(PROMPT_NAME) or other.Parent == nil then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ActionText = "Handeln"
	prompt.ObjectText = other.DisplayName
	prompt.KeyboardKeyCode = Enum.KeyCode.T
	prompt.GamepadKeyCode = Enum.KeyCode.DPadUp
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Enabled = current == nil
	prompt.Parent = root
	local userId = other.UserId
	prompt.Triggered:Connect(function()
		sendRequest(userId)
	end)
end

local function watchPlayer(other: Player)
	if other == player then
		return
	end
	other.CharacterAdded:Connect(function(character)
		addPrompt(other, character)
	end)
	if other.Character then
		task.spawn(addPrompt, other, other.Character)
	end
end

-- ---------------------------------------------------------------------
-- TAUSCH FERTIG: Karten fliegen, Stempel
-- ---------------------------------------------------------------------
local function flyCard(card: GuiObject, target: Vector2, spin: number)
	local gui = fxGui
	if not gui then
		return
	end
	local group = Instance.new("CanvasGroup")
	group.BackgroundTransparency = 1
	group.Position = UDim2.fromOffset(card.AbsolutePosition.X, card.AbsolutePosition.Y)
	group.Size = UDim2.fromOffset(card.AbsoluteSize.X, card.AbsoluteSize.Y)
	group.AnchorPoint = Vector2.zero
	local copy = card:Clone()
	copy.Position = UDim2.fromScale(0, 0)
	copy.Size = UDim2.fromScale(1, 1)
	copy.AnchorPoint = Vector2.zero
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("UIScale") then
			d:Destroy()
		end
	end
	copy.Parent = group
	group.Parent = gui
	TweenService:Create(group, FLY_INFO, {
		Position = UDim2.fromOffset(target.X - card.AbsoluteSize.X / 2, target.Y - card.AbsoluteSize.Y / 2),
		Rotation = spin,
		Size = UDim2.fromOffset(card.AbsoluteSize.X * 0.4, card.AbsoluteSize.Y * 0.4),
	}):Play()
	TweenService:Create(group, FADE_INFO, { GroupTransparency = 1 }):Play()
	task.delay(FLY_TIME + 0.1, function()
		group:Destroy()
	end)
end

local function stamp()
	local gui = fxGui
	if not gui then
		return
	end
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.42)
	label.Size = UDim2.fromOffset(520, 110)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "🤝 HANDEL FERTIG!"
	label.TextColor3 = Theme.Green
	label.Rotation = -12
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 5
	stroke.Color = Color3.fromRGB(20, 60, 20)
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Scale = 2.4
	scale.Parent = label
	label.Parent = gui
	TweenService:Create(scale, STAMP_IN, { Scale = 1 }):Play()
	TweenService:Create(label, STAMP_IN, { Rotation = -6 }):Play()
	TweenService:Create(label, STAMP_OUT, { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, STAMP_OUT, { Transparency = 1 }):Play()
	task.delay(1.8, function()
		label:Destroy()
	end)
	if ctx.Effects and ctx.Effects.Shake then
		ctx.Effects.Shake(0.25)
	end
end

playDone = function()
	local gui = fxGui
	if not gui or not win.IsOpen or (ctx.Effects.IsHidden and ctx.Effects.IsHidden()) then
		return
	end
	local screen = gui.AbsoluteSize
	local count = 0
	-- seine/ihre Karten fliegen zu dir (unten), deine fliegen nach oben weg
	for _, child in ipairs(theirItems:GetChildren()) do
		if child:IsA("GuiObject") and count < MAX_FLY then
			count += 1
			flyCard(child, Vector2.new(screen.X * 0.5, screen.Y * 0.95), math.random(-25, 25))
		end
	end
	for _, child in ipairs(yourItems:GetChildren()) do
		if child:IsA("GuiObject") and count < MAX_FLY then
			count += 1
			flyCard(child, Vector2.new(screen.X * 0.5, -40), math.random(-25, 25))
		end
	end
	stamp()
end

-- ---------------------------------------------------------------------
-- EREIGNISSE VOM SERVER
-- ---------------------------------------------------------------------
local function onEvent(kind: any, data: any)
	if kind == "Request" and type(data) == "table" then
		for i = #requests, 1, -1 do
			if requests[i].From == data.From then
				table.remove(requests, i)
			end
		end
		local total = math.max(1, tonumber(data.Timeout) or 20)
		table.insert(requests, {
			From = data.From,
			Name = tostring(data.Name),
			Expires = os.clock() + total,
			Total = total,
		})
		updatePopup()
	elseif kind == "RequestGone" and type(data) == "table" then
		for i = #requests, 1, -1 do
			if requests[i].From == data.From then
				table.remove(requests, i)
			end
		end
		updatePopup()
	elseif kind == "Update" and type(data) == "table" then
		local first = current == nil
		current = data
		render()
		setPromptsEnabled()
		if first then
			table.clear(requests)
			updatePopup()
			cashBox.Text = ""
			UI.OpenWindow(win)
		end
	elseif kind == "Closed" then
		if type(data) == "table" and data.Done == true and current then
			playDone() -- vor dem Schließen: Karten-Positionen stehen noch
		end
		current = nil
		table.clear(shownKeys.You)
		table.clear(shownKeys.Them)
		lastReady.You, lastReady.Them = false, false
		render()
		setPromptsEnabled()
		local text = type(data) == "table" and data.Text
		if type(text) == "string" and text ~= "" then
			UI.Toast(text, if data.Done then "Success" else "Error")
		end
		if win.IsOpen then
			closingByServer = true
			UI.CloseWindow(win)
			closingByServer = false
		end
		refreshPlayers()
	end
end

function Trade.Init(context: any)
	ctx = context
	tradeRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Trade") :: RemoteFunction
	local tradeEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TradeEvent") :: RemoteEvent

	win = UI.Window("🤝 HANDEL", 620, 500, Theme.Cyan)
	local overlay = Instance.new("ScreenGui")
	overlay.Name = "MeteorHeistTradeFX"
	overlay.ResetOnSpawn = false
	overlay.IgnoreGuiInset = false
	overlay.DisplayOrder = 6
	overlay.Parent = player:WaitForChild("PlayerGui")
	fxGui = overlay
	buildListPage(win.Content)
	buildTradePage(win.Content)
	buildPopup()
	ctx.Windows.Register("Trade", win)
	win.OnOpen = function()
		if not current then
			local ok, result = call("Status", nil, true)
			if ok and result then
				blockedRequests = result.Blocked == true
				waitUntil = os.clock() + (tonumber(result.Wait) or 0)
				if type(result.Trade) == "table" then
					current = result.Trade
					render()
				end
			end
			refreshPlayers()
		end
	end
	-- Fenster zu (✖ oder anderes Fenster) während eines Handels = abbrechen
	win.Group:GetPropertyChangedSignal("Visible"):Connect(function()
		if not win.Group.Visible and not win.IsOpen and current and not closingByServer then
			call("Cancel", nil, true)
		end
	end)
	ctx.Hud.AddRightButton("🤝", "Handel", Theme.Cyan, 9, function()
		ctx.Windows.Toggle("Trade")
	end)

	tradeEvent.OnClientEvent:Connect(onEvent)
	for _, other in ipairs(Players:GetPlayers()) do
		watchPlayer(other)
	end
	Players.PlayerAdded:Connect(function(other)
		watchPlayer(other)
		if win.IsOpen and not current then
			refreshPlayers()
		end
	end)
	Players.PlayerRemoving:Connect(function(other)
		task.defer(function()
			if win.IsOpen and not current then
				refreshPlayers()
			end
		end)
		for i = #requests, 1, -1 do
			if requests[i].From == other.UserId then
				table.remove(requests, i)
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			local ok, err = pcall(function()
				updatePopup()
				if current then
					updateStatus()
				end
			end)
			if not ok then
				warn("[Trade] " .. tostring(err))
			end
		end
	end)
end

return Trade
