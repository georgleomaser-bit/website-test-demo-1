-- =====================================================================
--  METEOR HEIST – Client (alles, was der Spieler sieht)
--  HUD, Shop, Speed Farm, Rebirth, Daily, Index, Admin-Panel, Effekte.
--  Die gesamte Oberfläche wird per Code gebaut – du musst nichts in Studio zusammenklicken.
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local Remotes = {
	Notify = RemotesFolder:WaitForChild("Notify") :: RemoteEvent,
	State = RemotesFolder:WaitForChild("State") :: RemoteEvent,
	Effect = RemotesFolder:WaitForChild("Effect") :: RemoteEvent,
	Request = RemotesFolder:WaitForChild("Request") :: RemoteFunction,
	Admin = RemotesFolder:WaitForChild("Admin") :: RemoteFunction,
}

local state = nil -- letzte Daten vom Server

-- ---------------------------------------------------------------------
-- STIL
-- ---------------------------------------------------------------------
local THEME = {
	Panel = Color3.fromRGB(24, 20, 38),
	PanelLight = Color3.fromRGB(40, 34, 62),
	Accent = Color3.fromRGB(255, 160, 50),
	Green = Color3.fromRGB(70, 210, 100),
	Red = Color3.fromRGB(230, 70, 70),
	Blue = Color3.fromRGB(70, 150, 255),
	Purple = Color3.fromRGB(160, 90, 255),
	Gray = Color3.fromRGB(90, 90, 105),
	Text = Color3.new(1, 1, 1),
	SubText = Color3.fromRGB(190, 185, 210),
}

local function create(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	for k, v in pairs(props or {}) do
		if k == "Parent" then
			parent = v
		else
			(inst :: any)[k] = v
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	inst.Parent = parent
	return inst
end

local function corner(radius: number?)
	return create("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

local function stroke(color: Color3?, thickness: number?)
	return create("UIStroke", {
		Color = color or THEME.Accent,
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function textStroke()
	return create("UIStroke", { Thickness = 2, Color = Color3.new(0, 0, 0), Transparency = 0.2 })
end

local function label(props)
	local base = {
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextColor3 = THEME.Text,
		TextScaled = true,
		Text = "",
	}
	for k, v in pairs(props) do
		if k ~= "MaxText" then
			base[k] = v
		end
	end
	local l = create("TextLabel", base, { create("UITextSizeConstraint", { MaxTextSize = props.MaxText or 28 }) })
	return l
end

local function button(props, onClick: () -> ())
	local color = props.Color or THEME.Accent
	local base = {
		BackgroundColor3 = color,
		AutoButtonColor = true,
		Font = Enum.Font.FredokaOne,
		TextColor3 = THEME.Text,
		TextScaled = true,
		Text = "",
	}
	for k, v in pairs(props) do
		if k ~= "Color" and k ~= "MaxText" then
			base[k] = v
		end
	end
	local b = create("TextButton", base, {
		corner(10),
		create("UITextSizeConstraint", { MaxTextSize = props.MaxText or 22 }),
		textStroke(),
		create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
	})
	local busy = false
	b.Activated:Connect(function()
		if busy then
			return
		end
		busy = true
		task.spawn(function()
			local ok, err = pcall(onClick)
			if not ok then
				warn(err)
			end
			busy = false
		end)
	end)
	return b
end

local function textBox(props)
	local base = {
		BackgroundColor3 = THEME.PanelLight,
		Font = Enum.Font.GothamBold,
		TextColor3 = THEME.Text,
		PlaceholderColor3 = THEME.SubText,
		TextScaled = true,
		ClearTextOnFocus = false,
		Text = "",
	}
	for k, v in pairs(props) do
		base[k] = v
	end
	return create("TextBox", base, {
		corner(8),
		create("UITextSizeConstraint", { MaxTextSize = 18 }),
		create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
	})
end

-- ---------------------------------------------------------------------
-- GRUNDGERÜST
-- ---------------------------------------------------------------------
local gui = create("ScreenGui", {
	Name = "MeteorHeistUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = false,
	Parent = player:WaitForChild("PlayerGui"),
})
local uiScale = create("UIScale", { Parent = gui })
local function updateScale()
	local camera = workspace.CurrentCamera
	if camera then
		local size = camera.ViewportSize
		uiScale.Scale = math.clamp(math.min(size.X / 1280, size.Y / 760), 0.55, 1.15)
	end
end
updateScale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end

-- Oben: Cash + Einkommen
local topBar = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.new(0, 360, 0, 86),
	BackgroundColor3 = THEME.Panel,
	BackgroundTransparency = 0.15,
	Parent = gui,
}, { corner(16), stroke() })
local cashLabel = label({
	Position = UDim2.new(0, 10, 0, 4),
	Size = UDim2.new(1, -20, 0, 42),
	Text = "$0",
	TextColor3 = Color3.fromRGB(255, 225, 90),
	MaxText = 40,
	Parent = topBar,
})
textStroke().Parent = cashLabel
local incomeLabel = label({
	Position = UDim2.new(0, 10, 0, 44),
	Size = UDim2.new(1, -20, 0, 20),
	Text = "+$0/s",
	TextColor3 = THEME.Green,
	MaxText = 20,
	Parent = topBar,
})
local infoLabel = label({
	Position = UDim2.new(0, 10, 0, 64),
	Size = UDim2.new(1, -20, 0, 18),
	Text = "",
	TextColor3 = THEME.SubText,
	Font = Enum.Font.GothamBold,
	MaxText = 14,
	Parent = topBar,
})

-- Event-Banner
local eventBanner = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 100),
	Size = UDim2.new(0, 420, 0, 34),
	BackgroundColor3 = Color3.fromRGB(120, 40, 20),
	BackgroundTransparency = 0.1,
	Visible = false,
	Parent = gui,
}, { corner(10), stroke(Color3.fromRGB(255, 120, 40)) })
local eventLabel = label({ Size = UDim2.fromScale(1, 1), Text = "", MaxText = 20, Parent = eventBanner })
local nextShowerLabel = label({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 100),
	Size = UDim2.new(0, 300, 0, 20),
	Text = "",
	TextColor3 = THEME.SubText,
	Font = Enum.Font.GothamBold,
	MaxText = 14,
	Parent = gui,
})

-- Trage-Hinweis unten
local carryLabel = label({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -110),
	Size = UDim2.new(0, 520, 0, 40),
	Text = "🏃 BRING DEN METEOR IN DEINE BASE!",
	TextColor3 = Color3.fromRGB(255, 220, 80),
	Visible = false,
	MaxText = 30,
	Parent = gui,
})
textStroke().Parent = carryLabel

-- Benachrichtigungen
local toastHolder = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 142),
	Size = UDim2.new(0, 460, 0, 300),
	BackgroundTransparency = 1,
	Parent = gui,
}, {
	create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
	}),
})
local toastCount = 0
local TOAST_COLORS = {
	Info = Color3.fromRGB(45, 40, 70),
	Success = Color3.fromRGB(30, 110, 55),
	Error = Color3.fromRGB(140, 35, 35),
	Event = Color3.fromRGB(150, 70, 10),
	Alarm = Color3.fromRGB(200, 20, 20),
	Announce = Color3.fromRGB(40, 60, 160),
}

local function toast(text: string, kind: string?)
	toastCount += 1
	local frame = create("Frame", {
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundColor3 = TOAST_COLORS[kind or "Info"] or TOAST_COLORS.Info,
		BackgroundTransparency = 0.05,
		LayoutOrder = toastCount,
		Parent = toastHolder,
	}, { corner(10) })
	local l = label({
		Position = UDim2.new(0, 10, 0, 0),
		Size = UDim2.new(1, -20, 1, 0),
		Text = text,
		MaxText = 18,
		Parent = frame,
	})
	textStroke().Parent = l
	local children = {}
	for _, child in ipairs(toastHolder:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(children, child)
		end
	end
	if #children > 5 then
		table.sort(children, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		children[1]:Destroy()
	end
	task.delay(kind == "Announce" and 8 or 4, function()
		if frame.Parent then
			TweenService:Create(frame, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			task.wait(0.45)
			frame:Destroy()
		end
	end)
end

-- ---------------------------------------------------------------------
-- FENSTER (immer nur eins offen)
-- ---------------------------------------------------------------------
local windows = {}
local function makeWindow(title: string, width: number, height: number)
	local frame = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.new(0, width, 0, height),
		BackgroundColor3 = THEME.Panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		ZIndex = 5,
		Parent = gui,
	}, { corner(18), stroke() })
	label({
		Position = UDim2.new(0, 16, 0, 8),
		Size = UDim2.new(1, -70, 0, 40),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = THEME.Accent,
		MaxText = 32,
		Parent = frame,
	})
	button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.new(0, 38, 0, 38),
		Text = "X",
		Color = THEME.Red,
		Parent = frame,
	}, function()
		frame.Visible = false
	end)
	local content = create("ScrollingFrame", {
		Position = UDim2.new(0, 12, 0, 56),
		Size = UDim2.new(1, -24, 1, -68),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		Parent = frame,
	}, {
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
		create("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }),
	})
	table.insert(windows, frame)
	return frame, content
end

local function openWindow(frame: Frame)
	local wasOpen = frame.Visible
	for _, w in ipairs(windows) do
		w.Visible = false
	end
	frame.Visible = not wasOpen
end

local function section(parent: Instance, text: string, order: number)
	return label({
		Size = UDim2.new(1, 0, 0, 26),
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = THEME.Accent,
		LayoutOrder = order,
		MaxText = 22,
		Parent = parent,
	})
end

local function row(parent: Instance, order: number, height: number?)
	return create("Frame", {
		Size = UDim2.new(1, 0, 0, height or 40),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	})
end

local function grid(parent: Instance, order: number, cellX: number, cellY: number)
	return create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	}, {
		create("UIGridLayout", {
			CellSize = UDim2.new(0, cellX, 0, cellY),
			CellPadding = UDim2.new(0, 6, 0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
end

local function request(action: string, arg: any?)
	local ok, result = pcall(function()
		return Remotes.Request:InvokeServer(action, arg)
	end)
	if ok and type(result) == "table" then
		if result.Message and result.Message ~= "" then
			toast(result.Message, result.Ok and "Success" or "Error")
		end
		return result.Ok
	end
	return false
end

-- ---------------------------------------------------------------------
-- SHOP
-- ---------------------------------------------------------------------
local priceCache = {}
local function fetchPrice(id: number, infoType: Enum.InfoType, target: TextButton, prefix: string)
	if id == 0 then
		target.Text = "Bald verfügbar"
		target.BackgroundColor3 = THEME.Gray
		return
	end
	task.spawn(function()
		local price = priceCache[id]
		if not price then
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, infoType)
			price = ok and info and info.PriceInRobux or nil
			priceCache[id] = price
		end
		if target.Parent then
			target.Text = prefix .. (price and ("R$ " .. price) or "Kaufen")
		end
	end)
end

local shopWindow, shopContent = makeWindow("🛒 SHOP", 560, 470)
local passButtons = {}
section(shopContent, "⭐ Gamepasses (für immer)", 1)
local passGrid = grid(shopContent, 2, 255, 120)
for i, pass in ipairs(Config.GamePasses) do
	local card = create("Frame", {
		BackgroundColor3 = THEME.PanelLight,
		LayoutOrder = i,
		Parent = passGrid,
	}, { corner(12) })
	label({
		Position = UDim2.new(0, 8, 0, 6),
		Size = UDim2.new(1, -16, 0, 26),
		Text = pass.Icon .. " " .. pass.Name,
		Parent = card,
		MaxText = 22,
	})
	label({
		Position = UDim2.new(0, 8, 0, 32),
		Size = UDim2.new(1, -16, 0, 34),
		Text = pass.Description,
		Font = Enum.Font.Gotham,
		TextColor3 = THEME.SubText,
		TextWrapped = true,
		MaxText = 14,
		Parent = card,
	})
	local buy = button({
		Position = UDim2.new(0, 8, 1, -42),
		Size = UDim2.new(1, -16, 0, 34),
		Text = "...",
		Color = THEME.Green,
		Parent = card,
	}, function()
		if pass.Id ~= 0 and not (state and state.Passes[pass.Key]) then
			MarketplaceService:PromptGamePassPurchase(player, pass.Id)
		end
	end)
	passButtons[pass.Key] = buy
	fetchPrice(pass.Id, Enum.InfoType.GamePass, buy, "")
end

section(shopContent, "💎 Boosts & Pakete", 3)
local productGrid = grid(shopContent, 4, 255, 84)
for i, product in ipairs(Config.Products) do
	local card = create("Frame", {
		BackgroundColor3 = THEME.PanelLight,
		LayoutOrder = i,
		Parent = productGrid,
	}, { corner(12) })
	label({
		Position = UDim2.new(0, 8, 0, 6),
		Size = UDim2.new(1, -16, 0, 30),
		Text = product.Icon .. " " .. product.Name,
		Parent = card,
		MaxText = 18,
		TextWrapped = true,
	})
	local buy = button({
		Position = UDim2.new(0, 8, 1, -40),
		Size = UDim2.new(1, -16, 0, 32),
		Text = "...",
		Color = THEME.Blue,
		Parent = card,
	}, function()
		if product.Id ~= 0 then
			MarketplaceService:PromptProductPurchase(player, product.Id)
		end
	end)
	fetchPrice(product.Id, Enum.InfoType.Product, buy, "")
end

-- ---------------------------------------------------------------------
-- SPEED FARM
-- ---------------------------------------------------------------------
local speedWindow, speedContent = makeWindow("🏃 SPEED FARM", 460, 380)
local speedInfo =
	label({ Size = UDim2.new(1, 0, 0, 34), Text = "", LayoutOrder = 1, MaxText = 24, Parent = speedContent })
local speedCost = label({
	Size = UDim2.new(1, 0, 0, 24),
	Text = "",
	LayoutOrder = 2,
	TextColor3 = Color3.fromRGB(255, 225, 90),
	MaxText = 20,
	Parent = speedContent,
})
label({
	Size = UDim2.new(1, 0, 0, 40),
	Text = "Schneller = Meteore zuerst schnappen und mit Beute entkommen! Speed bleibt bei Rebirth.",
	Font = Enum.Font.Gotham,
	TextColor3 = THEME.SubText,
	TextWrapped = true,
	LayoutOrder = 3,
	MaxText = 15,
	Parent = speedContent,
})
local speedRow = row(speedContent, 4, 50)
for i, amount in ipairs({ 1, 5, 10, Config.MaxSpeedLevel }) do
	button({
		Size = UDim2.new(0.25, -5, 1, 0),
		Text = amount == Config.MaxSpeedLevel and "MAX" or ("+" .. amount),
		Color = THEME.Green,
		LayoutOrder = i,
		Parent = speedRow,
	}, function()
		request("BuySpeed", amount)
	end)
end
local speedProduct = Config.ProductsByKey.Speed10
local speedBoots = Config.GamePassesByKey.SpeedBoots
local speedRobuxRow = row(speedContent, 5, 46)
if speedProduct then
	local b = button(
		{ Size = UDim2.new(0.5, -3, 1, 0), Text = "...", Color = THEME.Blue, LayoutOrder = 1, Parent = speedRobuxRow },
		function()
			if speedProduct.Id ~= 0 then
				MarketplaceService:PromptProductPurchase(player, speedProduct.Id)
			end
		end
	)
	fetchPrice(speedProduct.Id, Enum.InfoType.Product, b, "+10 Level ")
end
if speedBoots then
	local b = button(
		{ Size = UDim2.new(0.5, -3, 1, 0), Text = "...", Color = THEME.Purple, LayoutOrder = 2, Parent = speedRobuxRow },
		function()
			if speedBoots.Id ~= 0 then
				MarketplaceService:PromptGamePassPurchase(player, speedBoots.Id)
			end
		end
	)
	fetchPrice(speedBoots.Id, Enum.InfoType.GamePass, b, "👟 Boots ")
end

-- ---------------------------------------------------------------------
-- REBIRTH
-- ---------------------------------------------------------------------
local rebirthWindow, rebirthContent = makeWindow("🔥 REBIRTH", 460, 400)
local rebirthInfo =
	label({ Size = UDim2.new(1, 0, 0, 30), Text = "", LayoutOrder = 1, MaxText = 22, Parent = rebirthContent })
local progressBack = create("Frame", {
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundColor3 = THEME.PanelLight,
	LayoutOrder = 2,
	Parent = rebirthContent,
}, { corner(10) })
local progressFill = create("Frame", {
	Size = UDim2.new(0, 0, 1, 0),
	BackgroundColor3 = THEME.Accent,
	Parent = progressBack,
}, { corner(10) })
local progressText = label({ Size = UDim2.fromScale(1, 1), Text = "", MaxText = 18, ZIndex = 2, Parent = progressBack })
textStroke().Parent = progressText
local rebirthDetail = label({
	Size = UDim2.new(1, 0, 0, 110),
	Text = "",
	Font = Enum.Font.GothamBold,
	TextColor3 = THEME.SubText,
	TextWrapped = true,
	LayoutOrder = 3,
	MaxText = 16,
	Parent = rebirthContent,
})
button({
	Size = UDim2.new(1, 0, 0, 50),
	Text = "🔥 REBIRTH!",
	Color = THEME.Red,
	LayoutOrder = 4,
	Parent = rebirthContent,
}, function()
	request("Rebirth")
end)

-- ---------------------------------------------------------------------
-- DAILY
-- ---------------------------------------------------------------------
local dailyWindow, dailyContent = makeWindow("🎁 TAGESBONUS", 400, 260)
local dailyInfo = label({
	Size = UDim2.new(1, 0, 0, 60),
	Text = "",
	LayoutOrder = 1,
	TextWrapped = true,
	MaxText = 20,
	Parent = dailyContent,
})
local dailyButton = button(
	{ Size = UDim2.new(1, 0, 0, 54), Text = "Abholen", Color = THEME.Green, LayoutOrder = 2, Parent = dailyContent },
	function()
		request("Daily")
	end
)

-- ---------------------------------------------------------------------
-- INDEX
-- ---------------------------------------------------------------------
local indexWindow, indexContent = makeWindow("📖 METEOR-INDEX", 600, 480)
local indexHeader =
	label({ Size = UDim2.new(1, 0, 0, 30), Text = "", LayoutOrder = 1, MaxText = 20, Parent = indexContent })
local indexGrid = grid(indexContent, 2, 132, 70)
local indexCards = {}
for i, def in ipairs(Config.Meteors) do
	local rarity = Config.RaritiesByName[def.Rarity]
	local card = create(
		"Frame",
		{ BackgroundColor3 = THEME.PanelLight, LayoutOrder = i, Parent = indexGrid },
		{ corner(10) }
	)
	local dot = create("Frame", {
		Position = UDim2.new(0, 6, 0.5, -14),
		Size = UDim2.new(0, 28, 0, 28),
		BackgroundColor3 = def.Color,
		Parent = card,
	}, { corner(14) })
	local nameL = label({
		Position = UDim2.new(0, 40, 0, 6),
		Size = UDim2.new(1, -46, 0, 34),
		Text = def.Name,
		TextWrapped = true,
		MaxText = 14,
		Parent = card,
	})
	local rarL = label({
		Position = UDim2.new(0, 40, 0, 42),
		Size = UDim2.new(1, -46, 0, 20),
		Text = def.Rarity,
		TextColor3 = rarity.Color,
		MaxText = 12,
		Parent = card,
	})
	indexCards[def.Id] = { Card = card, Dot = dot, Name = nameL, Rarity = rarL, Def = def }
end

-- ---------------------------------------------------------------------
-- LINKE BUTTON-LEISTE
-- ---------------------------------------------------------------------
local sideBar = create("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 10, 0.5, 0),
	Size = UDim2.new(0, 120, 0, 420),
	BackgroundTransparency = 1,
	Parent = gui,
}, { create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }) })

local function sideButton(text: string, color: Color3, order: number, onClick)
	return button(
		{ Size = UDim2.new(1, 0, 0, 48), Text = text, Color = color, LayoutOrder = order, Parent = sideBar },
		onClick
	)
end
sideButton("🛒 Shop", THEME.Green, 1, function()
	openWindow(shopWindow)
end)
sideButton("🏃 Speed", THEME.Blue, 2, function()
	openWindow(speedWindow)
end)
sideButton("🔥 Rebirth", THEME.Red, 3, function()
	openWindow(rebirthWindow)
end)
local dailySide = sideButton("🎁 Daily", THEME.Purple, 4, function()
	openWindow(dailyWindow)
end)
sideButton("📖 Index", THEME.Accent, 5, function()
	openWindow(indexWindow)
end)
sideButton("🏠 Home", THEME.Gray, 6, function()
	request("Home")
end)

-- ---------------------------------------------------------------------
-- ANZEIGE AKTUALISIEREN
-- ---------------------------------------------------------------------
local function nextUnlock(rebirths: number): string?
	for _, rarity in ipairs(Config.Rarities) do
		if (rarity.RequiredRebirths or 0) == rebirths + 1 then
			return rarity.Name
		end
	end
	return nil
end

local function refresh()
	if not state then
		return
	end
	cashLabel.Text = Util.FormatCash(state.Cash)
	incomeLabel.Text = ("+%s/s  •  %s%% Bonus"):format(
		Util.FormatCash(state.Income),
		Util.FormatNumber(state.Multiplier * 100)
	)
	infoLabel.Text = ("☄️ %d/%d   🏃 %d   🔥 %d   📖 %d/%d"):format(
		state.UsedSlots,
		state.Slots,
		state.Speed,
		state.Rebirths,
		#state.Index,
		#Config.Meteors
	)
	carryLabel.Visible = state.Carrying

	-- Speed
	if state.SpeedLevel >= Config.MaxSpeedLevel then
		speedInfo.Text = "Speed-Level MAX (" .. state.Speed .. " Tempo)"
		speedCost.Text = "Du bist maximal schnell! 🚀"
	else
		speedInfo.Text = ("Speed-Level %d/%d  •  Tempo %d"):format(
			state.SpeedLevel,
			Config.MaxSpeedLevel,
			state.Speed
		)
		speedCost.Text = "Nächstes Level: " .. Util.FormatCash(Config.SpeedCost(state.SpeedLevel))
	end

	-- Rebirth
	local ratio = math.clamp(state.Cash / state.RebirthCost, 0, 1)
	progressFill.Size = UDim2.new(ratio, 0, 1, 0)
	progressText.Text = Util.FormatCash(state.Cash) .. " / " .. Util.FormatCash(state.RebirthCost)
	rebirthInfo.Text = "Rebirths: " .. state.Rebirths
	local unlock = nextUnlock(state.Rebirths)
	rebirthDetail.Text = ("Belohnung: +%d%% Einkommen für immer%s\n\nDu verlierst: Cash + Meteore.\nDu behältst: Speed, Index, Gamepasses."):format(
		math.floor(Config.RebirthMultPerLevel * 100),
		unlock and ("\n🔓 Schaltet " .. unlock .. "-Meteore frei!") or ""
	)

	-- Daily
	if state.DailyReady then
		dailyInfo.Text = "Dein Bonus ist bereit! Streak: " .. state.Streak .. " Tag(e)"
		dailyButton.Text = "🎁 ABHOLEN"
		dailyButton.BackgroundColor3 = THEME.Green
		dailySide.Text = "🎁 Daily ❗"
	else
		dailyInfo.Text = "Komm morgen wieder! Streak: " .. state.Streak .. " Tag(e)"
		dailyButton.Text = "⏳ " .. Util.FormatTime(state.DailyIn)
		dailyButton.BackgroundColor3 = THEME.Gray
		dailySide.Text = "🎁 Daily"
	end

	-- Shop: gekaufte Pässe markieren
	for key, b in pairs(passButtons) do
		if state.Passes[key] then
			b.Text = "✅ Besitzt du"
			b.BackgroundColor3 = THEME.Gray
		end
	end

	-- Index
	local found = {}
	for _, id in ipairs(state.Index) do
		found[id] = true
	end
	indexHeader.Text = ("Entdeckt: %d/%d  •  +%d%% Einkommen"):format(
		#state.Index,
		#Config.Meteors,
		math.floor(#state.Index * Config.IndexBonusPerMeteor * 100)
	)
	for id, card in pairs(indexCards) do
		if found[id] then
			card.Name.Text = card.Def.Name
			card.Dot.BackgroundColor3 = card.Def.Color
			card.Card.BackgroundTransparency = 0
		else
			card.Name.Text = "???"
			card.Dot.BackgroundColor3 = Color3.new(0, 0, 0)
			card.Card.BackgroundTransparency = 0.5
		end
	end
end

Remotes.State.OnClientEvent:Connect(function(newState)
	state = newState
	refresh()
end)
Remotes.Notify.OnClientEvent:Connect(toast)

-- Event-Banner + Schauer-Stimmung
local colorCorrection = create("ColorCorrectionEffect", { Name = "ShowerTint", Enabled = false, Parent = Lighting })
task.spawn(function()
	while true do
		local now = workspace:GetServerTimeNow()
		local showerUntil = ReplicatedStorage:GetAttribute("ShowerUntil") or 0
		local luckUntil = ReplicatedStorage:GetAttribute("LuckUntil") or 0
		local luckMult = ReplicatedStorage:GetAttribute("LuckMult") or 1
		local nextShower = ReplicatedStorage:GetAttribute("NextShowerAt") or 0
		local parts = {}
		if showerUntil > now then
			table.insert(parts, "🌠 METEORITENSCHAUER " .. Util.FormatTime(showerUntil - now) .. " • KEINE LOCKS")
		end
		if luckUntil > now and luckMult > 1 then
			table.insert(parts, "🍀 " .. luckMult .. "x GLÜCK " .. Util.FormatTime(luckUntil - now))
		end
		eventBanner.Visible = #parts > 0
		eventLabel.Text = table.concat(parts, "   ")
		nextShowerLabel.Visible = #parts == 0 and nextShower > now
		nextShowerLabel.Text = "🌠 Nächster Meteoritenschauer in " .. Util.FormatTime(nextShower - now)
		colorCorrection.Enabled = showerUntil > now
		colorCorrection.TintColor = Color3.fromRGB(255, 200, 170)
		colorCorrection.Saturation = 0.2
		if state and not state.DailyReady then
			state.DailyIn = math.max(0, state.DailyIn - 1)
			if state.DailyIn == 0 then
				state.DailyReady = true
			end
			refresh()
		end
		task.wait(1)
	end
end)

-- ---------------------------------------------------------------------
-- PROMPTS: "Klauen" nur bei fremden Basen, "Verkaufen" nur in der eigenen
-- ---------------------------------------------------------------------
local plotsFolder = workspace:WaitForChild("MeteorHeistMap"):WaitForChild("Plots")
local trackedPrompts: { [ProximityPrompt]: boolean } = {}

local function updatePrompt(prompt: ProximityPrompt)
	local plotModel = prompt:FindFirstAncestorWhichIsA("Model")
	if not plotModel then
		return
	end
	local ownerId = plotModel:GetAttribute("OwnerUserId")
	local isMine = ownerId == player.UserId
	if prompt.Name == "SellPrompt" then
		prompt.Enabled = isMine
	elseif prompt.Name == "StealPrompt" then
		local locked = (plotModel:GetAttribute("LockedUntil") or 0) > workspace:GetServerTimeNow()
		prompt.Enabled = not isMine and not locked
	end
end

local function track(inst: Instance)
	if inst:IsA("ProximityPrompt") and (inst.Name == "SellPrompt" or inst.Name == "StealPrompt") then
		trackedPrompts[inst] = true
		updatePrompt(inst)
		inst.AncestryChanged:Connect(function(_, parent)
			if not parent then
				trackedPrompts[inst] = nil
			end
		end)
	end
end
for _, inst in ipairs(plotsFolder:GetDescendants()) do
	track(inst)
end
plotsFolder.DescendantAdded:Connect(track)
task.spawn(function()
	while true do
		task.wait(0.3)
		for prompt in pairs(trackedPrompts) do
			if prompt.Parent then
				updatePrompt(prompt)
			else
				trackedPrompts[prompt] = nil
			end
		end
	end
end)

-- ---------------------------------------------------------------------
-- EFFEKTE
-- ---------------------------------------------------------------------
local function shake(strength: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if t > 0.35 or not humanoid.Parent then
			humanoid.CameraOffset = Vector3.zero
			connection:Disconnect()
			return
		end
		local power = strength * (1 - t / 0.35)
		humanoid.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * power
	end)
end

local function confetti(amount: number)
	local colors = { THEME.Accent, THEME.Green, THEME.Blue, THEME.Purple, THEME.Red }
	for _ = 1, math.floor(25 * math.clamp(amount, 0.3, 3)) do
		local piece = create("Frame", {
			Size = UDim2.new(0, math.random(6, 12), 0, math.random(6, 12)),
			Position = UDim2.new(math.random(), 0, 0, -20),
			BackgroundColor3 = colors[math.random(1, #colors)],
			BorderSizePixel = 0,
			Rotation = math.random(0, 360),
			ZIndex = 20,
			Parent = gui,
		})
		local tween = TweenService:Create(
			piece,
			TweenInfo.new(math.random(15, 30) / 10, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{
				Position = UDim2.new(piece.Position.X.Scale + (math.random() - 0.5) * 0.2, 0, 1, 20),
				Rotation = piece.Rotation + math.random(-360, 360),
			}
		)
		tween:Play()
		tween.Completed:Connect(function()
			piece:Destroy()
		end)
	end
end

local function cashPopup(amount: number)
	local popup = label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.new(0, 300, 0, 50),
		Text = "+" .. Util.FormatCash(amount),
		TextColor3 = Color3.fromRGB(255, 225, 90),
		MaxText = 44,
		ZIndex = 15,
		Parent = gui,
	})
	textStroke().Parent = popup
	TweenService:Create(popup, TweenInfo.new(1.2, Enum.EasingStyle.Quad), {
		Position = UDim2.fromScale(0.5, 0.3),
		TextTransparency = 1,
	}):Play()
	task.delay(1.25, function()
		popup:Destroy()
	end)
end

local alarmFrame = create("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(255, 0, 0),
	BackgroundTransparency = 1,
	ZIndex = 1,
	Parent = gui,
})
local function alarm()
	for _ = 1, 3 do
		alarmFrame.BackgroundTransparency = 0.6
		TweenService:Create(alarmFrame, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		task.wait(0.35)
	end
end

Remotes.Effect.OnClientEvent:Connect(function(name: string, strength: number)
	if name == "Shake" then
		shake(strength)
	elseif name == "Confetti" then
		confetti(strength)
	elseif name == "Collect" then
		cashPopup(strength)
	elseif name == "Alarm" then
		task.spawn(alarm)
	end
end)

-- =====================================================================
-- ADMIN-PANEL (wird nur angezeigt, wenn der Server dich als Admin markiert;
-- jede Aktion wird zusätzlich auf dem Server geprüft)
-- =====================================================================
local function buildAdminPanel()
	local adminWindow, content = makeWindow("🛠️ ADMIN-PANEL", 640, 560)
	local status = label({
		Size = UDim2.new(1, 0, 0, 26),
		Text = "Bereit.",
		TextColor3 = THEME.SubText,
		Font = Enum.Font.GothamBold,
		LayoutOrder = 0,
		MaxText = 16,
		Parent = content,
	})

	local function admin(action: string, args: { [string]: any }?)
		local ok, result = pcall(function()
			return Remotes.Admin:InvokeServer(action, args or {})
		end)
		if ok and type(result) == "table" then
			status.Text = (result.Ok and "✅ " or "❌ ") .. tostring(result.Message)
			status.TextColor3 = result.Ok and THEME.Green or THEME.Red
			return result
		end
		status.Text = "❌ Keine Antwort vom Server"
		status.TextColor3 = THEME.Red
		return nil
	end

	-- Ziel
	section(content, "🎯 Ziel-Spieler (me / all / others / Name / UserId)", 1)
	local targetRow = row(content, 2, 40)
	local targetBox = textBox({
		Size = UDim2.new(0.55, 0, 1, 0),
		Text = "me",
		PlaceholderText = "me",
		LayoutOrder = 1,
		Parent = targetRow,
	})
	local playerList = create("ScrollingFrame", {
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollingDirection = Enum.ScrollingDirection.X,
		LayoutOrder = 3,
		Parent = content,
	}, {
		create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }),
	})
	local function refreshPlayers()
		local result = admin("GetPlayers")
		for _, child in ipairs(playerList:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		if result and result.Data then
			for _, info in ipairs(result.Data) do
				button({
					Size = UDim2.new(0, 150, 0, 36),
					Text = info.DisplayName .. " (" .. Util.FormatCash(info.Cash) .. ")",
					Color = THEME.PanelLight,
					MaxText = 14,
					Parent = playerList,
				}, function()
					targetBox.Text = info.Name
				end)
			end
		end
	end
	button({
		Size = UDim2.new(0.42, 0, 1, 0),
		Text = "🔄 Spieler laden",
		Color = THEME.Blue,
		LayoutOrder = 2,
		Parent = targetRow,
	}, refreshPlayers)

	-- Meteor-Auswahl
	section(content, "☄️ Meteor spawnen / geben", 4)
	local selectedMeteor = Config.Meteors[1].Id
	local selectedMutation = "Normal"
	local selectedLabel = label({
		Size = UDim2.new(1, 0, 0, 24),
		Text = "",
		LayoutOrder = 5,
		MaxText = 18,
		Parent = content,
	})
	local function updateSelected()
		local def = Config.MeteorsById[selectedMeteor]
		selectedLabel.Text = "Ausgewählt: " .. selectedMutation .. " " .. def.Name .. " (" .. def.Rarity .. ")"
		selectedLabel.TextColor3 = Config.RaritiesByName[def.Rarity].Color
	end
	local meteorGrid = grid(content, 6, 112, 40)
	for i, def in ipairs(Config.Meteors) do
		local b = button({
			Text = def.Name,
			Color = Config.RaritiesByName[def.Rarity].Color:Lerp(Color3.new(0, 0, 0), 0.45),
			LayoutOrder = i,
			MaxText = 13,
			Parent = meteorGrid,
		}, function()
			selectedMeteor = def.Id
			updateSelected()
		end)
		b.TextWrapped = true
	end
	local mutRow = row(content, 7, 36)
	for i, mut in ipairs(Config.Mutations) do
		button({
			Size = UDim2.new(0.25, -5, 1, 0),
			Text = mut.Name .. " x" .. mut.Mult,
			Color = (mut.Color or THEME.Gray):Lerp(Color3.new(0, 0, 0), 0.35),
			LayoutOrder = i,
			Parent = mutRow,
		}, function()
			selectedMutation = mut.Name
			updateSelected()
		end)
	end
	updateSelected()
	local countRow = row(content, 8, 36)
	local countBox = textBox({
		Size = UDim2.new(0.5, -3, 1, 0),
		PlaceholderText = "Anzahl (1-25)",
		Text = "1",
		LayoutOrder = 1,
		Parent = countRow,
	})
	local levelBox = textBox({
		Size = UDim2.new(0.5, -3, 1, 0),
		PlaceholderText = "Level (1-" .. Config.MaxLevel .. ")",
		Text = "1",
		LayoutOrder = 2,
		Parent = countRow,
	})
	local spawnRow = row(content, 9, 42)
	button({
		Size = UDim2.new(0.25, -5, 1, 0),
		Text = "Im Krater",
		Color = THEME.Accent,
		LayoutOrder = 1,
		Parent = spawnRow,
	}, function()
		admin(
			"SpawnMeteor",
			{ MeteorId = selectedMeteor, Mutation = selectedMutation, Count = countBox.Text, Where = "Crater" }
		)
	end)
	button(
		{ Size = UDim2.new(0.25, -5, 1, 0), Text = "Vor mir", Color = THEME.Accent, LayoutOrder = 2, Parent = spawnRow },
		function()
			admin(
				"SpawnMeteor",
				{ MeteorId = selectedMeteor, Mutation = selectedMutation, Count = countBox.Text, Where = "Me" }
			)
		end
	)
	button({
		Size = UDim2.new(0.25, -5, 1, 0),
		Text = "Gratis vor mir",
		Color = THEME.Green,
		LayoutOrder = 3,
		Parent = spawnRow,
	}, function()
		admin("SpawnMeteor", {
			MeteorId = selectedMeteor,
			Mutation = selectedMutation,
			Count = countBox.Text,
			Where = "Me",
			Free = true,
		})
	end)
	button({
		Size = UDim2.new(0.25, -5, 1, 0),
		Text = "In Ziel-Base",
		Color = THEME.Purple,
		LayoutOrder = 4,
		Parent = spawnRow,
	}, function()
		admin("GiveMeteor", {
			MeteorId = selectedMeteor,
			Mutation = selectedMutation,
			Level = levelBox.Text,
			Target = targetBox.Text,
		})
	end)

	-- Meteorregen
	section(content, "🌧️ Meteorregen (Seltenheit wählen)", 10)
	local rainGrid = grid(content, 11, 92, 36)
	button({ Text = "Zufall", Color = THEME.Gray, LayoutOrder = 0, Parent = rainGrid }, function()
		admin("MeteorRain", { Count = countBox.Text ~= "1" and countBox.Text or 15 })
	end)
	for i, rarity in ipairs(Config.Rarities) do
		button({
			Text = rarity.Name,
			Color = rarity.Color:Lerp(Color3.new(0, 0, 0), 0.4),
			LayoutOrder = i,
			MaxText = 14,
			Parent = rainGrid,
		}, function()
			admin("MeteorRain", { Rarity = rarity.Name, Count = countBox.Text ~= "1" and countBox.Text or 10 })
		end)
	end

	-- Geld & Werte
	section(content, "💰 Geld & Werte (für Ziel-Spieler)", 12)
	local amountBox = textBox({
		Size = UDim2.new(1, 0, 0, 36),
		PlaceholderText = "Betrag (z.B. 1000000)",
		LayoutOrder = 13,
		Parent = content,
	})
	local moneyRow = row(content, 14, 40)
	button(
		{ Size = UDim2.new(0.25, -5, 1, 0), Text = "+ Cash", Color = THEME.Green, LayoutOrder = 1, Parent = moneyRow },
		function()
			admin("GiveCash", { Target = targetBox.Text, Amount = amountBox.Text })
		end
	)
	button({
		Size = UDim2.new(0.25, -5, 1, 0),
		Text = "Cash setzen",
		Color = THEME.Green,
		LayoutOrder = 2,
		Parent = moneyRow,
	}, function()
		admin("SetCash", { Target = targetBox.Text, Amount = amountBox.Text })
	end)
	button({
		Size = UDim2.new(0.25, -5, 1, 0),
		Text = "Rebirths setzen",
		Color = THEME.Red,
		LayoutOrder = 3,
		Parent = moneyRow,
	}, function()
		admin("SetRebirths", { Target = targetBox.Text, Amount = amountBox.Text })
	end)
	button({
		Size = UDim2.new(0.25, -5, 1, 0),
		Text = "Speed-Lvl setzen",
		Color = THEME.Blue,
		LayoutOrder = 4,
		Parent = moneyRow,
	}, function()
		admin("SetSpeed", { Target = targetBox.Text, Amount = amountBox.Text })
	end)
	local passGridAdmin = grid(content, 15, 112, 36)
	for i, pass in ipairs(Config.GamePasses) do
		button({
			Text = pass.Icon .. " " .. pass.Name,
			Color = THEME.PanelLight,
			LayoutOrder = i,
			MaxText = 13,
			Parent = passGridAdmin,
		}, function()
			admin("GivePass", { Target = targetBox.Text, PassKey = pass.Key })
		end)
	end

	-- Events
	section(content, "🎉 Events", 16)
	local globalToggle = false
	local eventRow1 = row(content, 17, 36)
	local multBox = textBox({
		Size = UDim2.new(0.33, -4, 1, 0),
		PlaceholderText = "Glück x",
		Text = "2",
		LayoutOrder = 1,
		Parent = eventRow1,
	})
	local minutesBox = textBox({
		Size = UDim2.new(0.33, -4, 1, 0),
		PlaceholderText = "Minuten",
		Text = "10",
		LayoutOrder = 2,
		Parent = eventRow1,
	})
	local globalButton
	globalButton = button({
		Size = UDim2.new(0.33, -4, 1, 0),
		Text = "Nur dieser Server",
		Color = THEME.Gray,
		LayoutOrder = 3,
		MaxText = 14,
		Parent = eventRow1,
	}, function()
		globalToggle = not globalToggle
		globalButton.Text = globalToggle and "🌍 ALLE Server" or "Nur dieser Server"
		globalButton.BackgroundColor3 = globalToggle and THEME.Purple or THEME.Gray
	end)
	local eventRow2 = row(content, 18, 40)
	button({
		Size = UDim2.new(0.5, -3, 1, 0),
		Text = "🍀 Glück starten",
		Color = THEME.Green,
		LayoutOrder = 1,
		Parent = eventRow2,
	}, function()
		admin("ServerLuck", { Mult = multBox.Text, Minutes = minutesBox.Text, Global = globalToggle })
	end)
	button({
		Size = UDim2.new(0.5, -3, 1, 0),
		Text = "🌠 Meteoritenschauer",
		Color = THEME.Accent,
		LayoutOrder = 2,
		Parent = eventRow2,
	}, function()
		admin("StartShower", { Seconds = (tonumber(minutesBox.Text) or 1) * 60, Global = globalToggle })
	end)
	local announceRow = row(content, 19, 40)
	local announceBox = textBox({
		Size = UDim2.new(0.7, -3, 1, 0),
		PlaceholderText = "Nachricht an alle...",
		LayoutOrder = 1,
		Parent = announceRow,
	})
	button({
		Size = UDim2.new(0.3, -3, 1, 0),
		Text = "📢 Senden",
		Color = THEME.Blue,
		LayoutOrder = 2,
		Parent = announceRow,
	}, function()
		admin("Announce", { Text = announceBox.Text, Global = globalToggle })
	end)

	-- Moderation
	section(content, "🛡️ Moderation (Ziel oben)", 20)
	local modRow = row(content, 21, 36)
	local reasonBox =
		textBox({ Size = UDim2.new(0.7, -3, 1, 0), PlaceholderText = "Grund", LayoutOrder = 1, Parent = modRow })
	local daysBox = textBox({
		Size = UDim2.new(0.3, -3, 1, 0),
		PlaceholderText = "Tage (0=immer)",
		LayoutOrder = 2,
		Parent = modRow,
	})
	local modGrid = grid(content, 22, 146, 38)
	local modActions = {
		{ "👢 Kick", "Kick", THEME.Red },
		{ "🔨 Bann", "Ban", THEME.Red },
		{ "♻️ Entbannen (UserId)", "Unban", THEME.Green },
		{ "🧹 Base leeren", "ClearBase", THEME.Accent },
		{ "💣 Daten Reset", "ResetData", THEME.Red },
		{ "➡️ TP zu Ziel", "TeleportTo", THEME.Blue },
		{ "⬅️ Ziel holen", "Bring", THEME.Blue },
		{ "🧽 Krater leeren", "ClearGround", THEME.Gray },
	}
	local confirmPending: string? = nil
	for i, info in ipairs(modActions) do
		button({ Text = info[1], Color = info[3], LayoutOrder = i, MaxText = 14, Parent = modGrid }, function()
			local action = info[2]
			-- gefährliche Aktionen brauchen einen zweiten Klick
			if (action == "Ban" or action == "ResetData") and confirmPending ~= action then
				confirmPending = action
				status.Text = "⚠️ Nochmal klicken zum Bestätigen: " .. info[1]
				status.TextColor3 = THEME.Accent
				return
			end
			confirmPending = nil
			admin(action, { Target = targetBox.Text, Reason = reasonBox.Text, Days = daysBox.Text })
		end)
	end

	sideButton("🛠️ Admin", Color3.fromRGB(200, 40, 40), 7, function()
		openWindow(adminWindow)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.P then
			openWindow(adminWindow)
		end
	end)
	toast("🛠️ Admin-Panel aktiv – Taste P oder Button links", "Info")
end

local adminBuilt = false
local function checkAdmin()
	if player:GetAttribute("IsAdmin") == true and not adminBuilt then
		adminBuilt = true
		buildAdminPanel()
	end
end
player:GetAttributeChangedSignal("IsAdmin"):Connect(checkAdmin)
checkAdmin()

toast("☄️ Willkommen bei " .. Config.GameName .. "! Kauf Meteore im Krater und bring sie in deine Base!", "Event")
