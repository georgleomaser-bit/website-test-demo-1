-- Eier-Raub – Client
-- HUD, Benachrichtigungen, Durchsagen, Admin-Panel und Animationen
-- (laufendes Band, brütende Eier, Regenbogen, Farbverläufe).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("EierRaub"):WaitForChild("Config"))
local remotes = ReplicatedStorage:WaitForChild("EierRaubRemotes")
local notifyEvent = remotes:WaitForChild("Notify")
local announceEvent = remotes:WaitForChild("Announce")
local effectEvent = remotes:WaitForChild("Effect")
local adminFunction = remotes:WaitForChild("Admin")
local map = workspace:WaitForChild("EierRaubMap")
local eggsFolder = map:WaitForChild("Eggs")

local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local DARK = Color3.fromRGB(28, 26, 40)
local PANEL = Color3.fromRGB(40, 37, 58)
local ACCENT = Color3.fromRGB(255, 196, 60)
local GREEN = Color3.fromRGB(90, 230, 120)
local RED = Color3.fromRGB(255, 90, 90)

---------------------------------------------------------------------
-- UI-Helfer
---------------------------------------------------------------------
local function create(class: string, props, children: { Instance }?)
	local inst = Instance.new(class)
	local parent = props.Parent
	props.Parent = nil
	for k, v in props do
		inst[k] = v
	end
	for _, child in children or {} do
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
		Color = color or Color3.fromRGB(0, 0, 0),
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function padding(px: number)
	return create("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	})
end

local function label(props)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or FONT
	props.TextColor3 = props.TextColor3 or WHITE
	props.TextScaled = props.TextScaled ~= false
	return create("TextLabel", props)
end

local function button(props, onClick)
	props.Font = props.Font or FONT
	props.TextColor3 = props.TextColor3 or WHITE
	props.BackgroundColor3 = props.BackgroundColor3 or Color3.fromRGB(85, 120, 255)
	props.AutoButtonColor = true
	props.TextScaled = true
	local b = create("TextButton", props, { corner(10), stroke(Color3.fromRGB(0, 0, 0), 1.5), padding(4) })
	b.Activated:Connect(onClick)
	return b
end

local gui = create("ScreenGui", {
	Name = "EierRaubHUD",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

---------------------------------------------------------------------
-- Sounds
---------------------------------------------------------------------
local SOUNDS = {
	cash = { "rbxasset://sounds/electronicpingshort.wav", 0.5, 1.3 },
	buy = { "rbxasset://sounds/electronicpingshort.wav", 0.6, 1 },
	success = { "rbxasset://sounds/electronicpingshort.wav", 0.7, 1.6 },
	hatch = { "rbxasset://sounds/electronicpingshort.wav", 0.8, 2 },
	steal = { "rbxasset://sounds/swordlunge.wav", 0.6, 1.2 },
	hit = { "rbxasset://sounds/swordslash.wav", 0.7, 0.8 },
	lock = { "rbxasset://sounds/electronicpingshort.wav", 0.6, 0.7 },
	alarm = { "rbxasset://sounds/electronicpingshort.wav", 0.9, 0.5 },
	error = { "rbxasset://sounds/electronicpingshort.wav", 0.5, 0.4 },
}

local function playSound(name: string)
	local def = SOUNDS[name]
	if not def then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = def[1]
	s.Volume = def[2]
	s.PlaybackSpeed = def[3]
	s.Parent = SoundService
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(5, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

---------------------------------------------------------------------
-- HUD: Geld, Einkommen, Events
---------------------------------------------------------------------
local moneyCard = create("Frame", {
	Name = "Geld",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(280, 66),
	BackgroundColor3 = DARK,
	BackgroundTransparency = 0.15,
	Parent = gui,
}, { corner(16), stroke(ACCENT, 2.5) })
create("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(70, 60, 110), Color3.fromRGB(30, 28, 45)),
	Rotation = 90,
	Parent = moneyCard,
})
local moneyLabel = label({
	Text = "$0",
	TextColor3 = ACCENT,
	Size = UDim2.new(1, -20, 0, 38),
	Position = UDim2.fromOffset(10, 4),
	Parent = moneyCard,
})
create("UIStroke", { Thickness = 2, Color = Color3.fromRGB(80, 45, 0), Parent = moneyLabel })
local incomeLabel = label({
	Text = "+$0/s",
	TextColor3 = GREEN,
	Size = UDim2.new(1, -20, 0, 20),
	Position = UDim2.fromOffset(10, 42),
	Parent = moneyCard,
})

local eventBar = create("Frame", {
	Name = "Events",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 80),
	Size = UDim2.fromOffset(420, 28),
	BackgroundTransparency = 1,
	Parent = gui,
}, {
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
	}),
})

local function eventChip(name: string, color: Color3)
	return label({
		Name = name,
		Size = UDim2.fromOffset(130, 26),
		BackgroundTransparency = 0.1,
		BackgroundColor3 = color,
		Visible = false,
		Parent = eventBar,
	})
end
local luckChip = eventChip("Glueck", Color3.fromRGB(60, 170, 80))
local incomeChip = eventChip("Geld", Color3.fromRGB(200, 150, 30))
local hatchChip = eventChip("Brut", Color3.fromRGB(200, 90, 160))
for _, chip in { luckChip, incomeChip, hatchChip } do
	corner(13).Parent = chip
	padding(3).Parent = chip
end

local leaderstats = player:WaitForChild("leaderstats")
local geld = leaderstats:WaitForChild("Geld") :: NumberValue
local shownMoney = geld.Value
local function refreshMoney()
	local target = geld.Value
	local start = shownMoney
	local t0 = os.clock()
	task.spawn(function()
		while os.clock() - t0 < 0.35 do
			local a = (os.clock() - t0) / 0.35
			shownMoney = start + (target - start) * a
			moneyLabel.Text = Config.formatMoney(shownMoney)
			task.wait()
		end
		shownMoney = target
		moneyLabel.Text = Config.formatMoney(target)
	end)
end
geld.Changed:Connect(refreshMoney)
moneyLabel.Text = Config.formatMoney(geld.Value)

local function refreshIncome()
	incomeLabel.Text = "+" .. Config.formatMoney(player:GetAttribute("Income") or 0) .. "/s"
end
player:GetAttributeChangedSignal("Income"):Connect(refreshIncome)
refreshIncome()

---------------------------------------------------------------------
-- Tragen-Banner
---------------------------------------------------------------------
local carryBanner = label({
	Name = "Tragen",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -110),
	Size = UDim2.fromOffset(460, 46),
	BackgroundTransparency = 0.1,
	BackgroundColor3 = Color3.fromRGB(220, 60, 60),
	Text = "",
	Visible = false,
	Parent = gui,
})
corner(14).Parent = carryBanner
stroke(Color3.fromRGB(80, 0, 0), 2.5).Parent = carryBanner
padding(6).Parent = carryBanner

local function refreshCarry()
	local name = player:GetAttribute("Carrying")
	carryBanner.Visible = name ~= nil
	if name then
		carryBanner.Text = "🏃 Du trägst " .. name .. " – ab in deine Basis!"
	end
end
player:GetAttributeChangedSignal("Carrying"):Connect(refreshCarry)
refreshCarry()

---------------------------------------------------------------------
-- Benachrichtigungen
---------------------------------------------------------------------
local notifyList = create("Frame", {
	Name = "Meldungen",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -12, 1, -12),
	Size = UDim2.fromOffset(360, 320),
	BackgroundTransparency = 1,
	Parent = gui,
}, {
	create("UIListLayout", {
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
	}),
})

local notifyCount = 0
local function addNotification(text: string, color: Color3?)
	notifyCount += 1
	local item = create("Frame", {
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.12,
		LayoutOrder = notifyCount,
		Parent = notifyList,
	}, { corner(12), stroke(color or WHITE, 2) })
	label({
		Text = text,
		TextColor3 = color or WHITE,
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.fromOffset(8, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = item,
	})
	local items = {}
	for _, c in notifyList:GetChildren() do
		if c:IsA("Frame") then
			table.insert(items, c)
		end
	end
	table.sort(items, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #items > 5 do
		table.remove(items, 1):Destroy()
	end
	task.delay(4, function()
		if item.Parent then
			TweenService:Create(item, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			for _, d in item:GetDescendants() do
				if d:IsA("TextLabel") then
					TweenService:Create(d, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
				elseif d:IsA("UIStroke") then
					TweenService:Create(d, TweenInfo.new(0.4), { Transparency = 1 }):Play()
				end
			end
			task.wait(0.45)
			item:Destroy()
		end
	end)
end

notifyEvent.OnClientEvent:Connect(addNotification)
effectEvent.OnClientEvent:Connect(playSound)

---------------------------------------------------------------------
-- Große Durchsage
---------------------------------------------------------------------
local announceFrame = create("Frame", {
	Name = "Durchsage",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 118),
	Size = UDim2.fromOffset(620, 74),
	BackgroundColor3 = Color3.fromRGB(255, 196, 60),
	Visible = false,
	Parent = gui,
}, { corner(18), stroke(Color3.fromRGB(90, 50, 0), 3) })
create("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 140, 50)),
	Rotation = 90,
	Parent = announceFrame,
})
local announceFrom = label({
	Text = "",
	TextColor3 = Color3.fromRGB(90, 45, 0),
	Size = UDim2.new(1, -24, 0, 20),
	Position = UDim2.fromOffset(12, 4),
	Parent = announceFrame,
})
local announceText = label({
	Text = "",
	Size = UDim2.new(1, -24, 0, 42),
	Position = UDim2.fromOffset(12, 26),
	Parent = announceFrame,
})
create("UIStroke", { Thickness = 2, Color = Color3.fromRGB(90, 45, 0), Parent = announceText })

local announceToken = 0
announceEvent.OnClientEvent:Connect(function(text: string, from: string?)
	announceToken += 1
	local token = announceToken
	announceFrom.Text = "📢 " .. (from or "Server")
	announceText.Text = text
	announceFrame.Visible = true
	announceFrame.Size = UDim2.fromOffset(0, 74)
	TweenService:Create(announceFrame, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(620, 74) }):Play()
	playSound("alarm")
	task.delay(5, function()
		if token == announceToken then
			announceFrame.Visible = false
		end
	end)
end)

---------------------------------------------------------------------
-- Eigene Basis markieren (nur für dich sichtbar)
---------------------------------------------------------------------
local baseMarker: BillboardGui? = nil
local function refreshBaseMarker()
	if baseMarker then
		baseMarker:Destroy()
		baseMarker = nil
	end
	local index = player:GetAttribute("BaseIndex")
	if not index then
		return
	end
	local base = map:WaitForChild("Bases"):WaitForChild("Basis" .. index, 10)
	local sign = base and base:WaitForChild("Schild", 10)
	if not sign then
		return
	end
	baseMarker = create("BillboardGui", {
		Name = "DeineBasis",
		Size = UDim2.fromOffset(200, 50),
		StudsOffset = Vector3.new(0, 6, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Parent = sign,
	})
	local tag = label({
		Text = "🏠 DEINE BASIS",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0.15,
		BackgroundColor3 = Color3.fromRGB(60, 170, 80),
		Parent = baseMarker,
	})
	corner(14).Parent = tag
	stroke(WHITE, 2).Parent = tag
end
player:GetAttributeChangedSignal("BaseIndex"):Connect(refreshBaseMarker)
task.spawn(refreshBaseMarker)

---------------------------------------------------------------------
-- Prompts nur für die richtigen Spieler zeigen
-- "owner": nur Besitzer (Verkaufen), "others": alle außer Besitzer (Klauen)
---------------------------------------------------------------------
local function applyAudience(prompt: ProximityPrompt)
	local audience = prompt:GetAttribute("Audience")
	local egg = prompt.Parent
	if not egg then
		return
	end
	local ownerId = egg:GetAttribute("OwnerId") or 0
	if audience == "owner" then
		prompt.Enabled = ownerId == player.UserId
	elseif audience == "others" then
		prompt.Enabled = ownerId ~= player.UserId
	end
end

local rainbowEggs = {}
local hatchingEggs = {}

local function trackEgg(egg: Instance)
	if not egg:IsA("BasePart") then
		return
	end
	local function refreshPrompts()
		for _, c in egg:GetChildren() do
			if c:IsA("ProximityPrompt") then
				applyAudience(c)
			end
		end
	end
	local function refreshFlags()
		rainbowEggs[egg] = egg:GetAttribute("Rainbow") == true or nil
		local mesh = egg:FindFirstChildOfClass("SpecialMesh")
		if egg:GetAttribute("Hatching") == true and mesh then
			hatchingEggs[egg] = mesh
		else
			hatchingEggs[egg] = nil
			if mesh then
				mesh.Scale = Vector3.one
			end
		end
	end
	egg:GetAttributeChangedSignal("OwnerId"):Connect(refreshPrompts)
	egg:GetAttributeChangedSignal("Rainbow"):Connect(refreshFlags)
	egg:GetAttributeChangedSignal("Hatching"):Connect(refreshFlags)
	egg.ChildAdded:Connect(function(c)
		if c:IsA("ProximityPrompt") then
			applyAudience(c)
		elseif c:IsA("SpecialMesh") then
			refreshFlags()
		end
	end)
	egg.AncestryChanged:Connect(function(_, parent)
		if not parent then
			rainbowEggs[egg] = nil
			hatchingEggs[egg] = nil
		end
	end)
	refreshPrompts()
	refreshFlags()
end

eggsFolder.ChildAdded:Connect(trackEgg)
for _, egg in eggsFolder:GetChildren() do
	trackEgg(egg)
end

---------------------------------------------------------------------
-- Animationen
---------------------------------------------------------------------
local slatFolder = map:WaitForChild("Laufband"):WaitForChild("Lamellen")
local slats = {}
local function collectSlats()
	table.clear(slats)
	for _, s in slatFolder:GetChildren() do
		if s:IsA("BasePart") then
			table.insert(slats, s)
		end
	end
end
slatFolder.ChildAdded:Connect(collectSlats)
collectSlats()

local gradients = {}
local function trackGradient(g: Instance)
	if g:IsA("UIGradient") and g:GetAttribute("Animated") then
		gradients[g] = true
	end
end
map.DescendantAdded:Connect(trackGradient)
for _, d in map:GetDescendants() do
	trackGradient(d)
end
map.DescendantRemoving:Connect(function(d)
	gradients[d] = nil
end)

RunService.RenderStepped:Connect(function()
	local t = os.clock()

	-- Laufband
	local start = slatFolder:GetAttribute("Start") or 0
	local length = slatFolder:GetAttribute("Length") or 1
	local spacing = slatFolder:GetAttribute("Spacing") or 6
	local speed = slatFolder:GetAttribute("Speed") or 7
	local shift = (t * speed) % spacing
	for _, s in slats do
		local x = start + ((s:GetAttribute("Index") or 0) * spacing + shift) % length
		s.CFrame = CFrame.new(x, s.Position.Y, s.Position.Z)
	end

	-- Regenbogen
	local hue = (t * 0.25) % 1
	for egg in rainbowEggs do
		egg.Color = Color3.fromHSV(hue, 0.75, 1)
	end

	-- Brütende Eier wackeln/pulsieren
	for egg, mesh in hatchingEggs do
		local seed = egg.Position.X * 0.37 + egg.Position.Z * 0.11
		local pulse = math.sin(t * 6 + seed)
		local wobble = math.max(0, math.sin(t * 1.3 + seed)) ^ 8
		mesh.Scale = Vector3.new(1 - pulse * 0.025 + wobble * 0.08, 1 + pulse * 0.04 - wobble * 0.06, 1 - pulse * 0.025 + wobble * 0.08)
	end

	-- Farbverläufe wandern
	for g in gradients do
		g.Offset = Vector2.new(math.sin(t * 1.5) * 0.4, 0)
	end
end)

---------------------------------------------------------------------
-- Event-Anzeige (Glück, Geld, Brut)
---------------------------------------------------------------------
local function fmtRemaining(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

task.spawn(function()
	while true do
		local now = workspace:GetServerTimeNow()
		local luck = map:GetAttribute("Luck") or 1
		local income = map:GetAttribute("IncomeMult") or 1
		local hatch = map:GetAttribute("HatchMult") or 1
		luckChip.Visible = luck > 1
		luckChip.Text = "🍀 Glück x" .. luck .. "  " .. fmtRemaining((map:GetAttribute("LuckEnds") or 0) - now)
		incomeChip.Visible = income > 1
		incomeChip.Text = "💰 Geld x" .. income .. "  " .. fmtRemaining((map:GetAttribute("IncomeEnds") or 0) - now)
		hatchChip.Visible = hatch > 1
		hatchChip.Text = "🐣 Brut x" .. hatch .. "  " .. fmtRemaining((map:GetAttribute("HatchEnds") or 0) - now)
		task.wait(0.5)
	end
end)

---------------------------------------------------------------------
-- Anleitung
---------------------------------------------------------------------
task.delay(2, function()
	addNotification("🥚 Kauf Eier am Laufband – sie laufen zu deiner Basis.", ACCENT)
	task.wait(1.2)
	addNotification("🐣 Eier müssen erst ausbrüten – dann schlüpft ein Tier und bringt Geld!", Color3.fromRGB(255, 235, 180))
	task.wait(1.2)
	addNotification("💰 Tritt auf die grünen Kassen, um Geld einzusammeln.", GREEN)
	task.wait(1.2)
	addNotification("🦹 Klau Eier & Tiere bei anderen – sperr deine Basis mit dem roten Knopf!", RED)
end)

---------------------------------------------------------------------
-- ADMIN-PANEL
---------------------------------------------------------------------
local adminBuilt = false

local function buildAdminPanel()
	if adminBuilt then
		return
	end
	adminBuilt = true

	local selectedPlayer: number? = player.UserId
	local selectedEgg = Config.Eggs[1].id
	local selectedMut = ""
	local spawnHatched = false

	local openButton = button({
		Name = "AdminKnopf",
		Text = "🛠️ Admin",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(110, 40),
		BackgroundColor3 = Color3.fromRGB(210, 60, 60),
		Parent = gui,
	}, function() end)

	local panel = create("Frame", {
		Name = "AdminPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(640, 440),
		BackgroundColor3 = DARK,
		Visible = false,
		Active = true,
		Parent = gui,
	}, { corner(18), stroke(Color3.fromRGB(210, 60, 60), 3) })
	create("UISizeConstraint", { MaxSize = Vector2.new(640, 440), Parent = panel })
	create("UIScale", { Name = "Skalierung", Parent = panel })

	-- Kopfzeile
	local header = create("Frame", {
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = Color3.fromRGB(210, 60, 60),
		Parent = panel,
	}, { corner(18) })
	create("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(230, 80, 80), Color3.fromRGB(160, 40, 70)),
		Parent = header,
	})
	label({
		Text = "🛠️ ADMIN-PANEL",
		Size = UDim2.new(1, -120, 1, -12),
		Position = UDim2.fromOffset(16, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})
	button({
		Text = "✕",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(36, 32),
		BackgroundColor3 = Color3.fromRGB(60, 20, 30),
		Parent = header,
	}, function()
		panel.Visible = false
	end)

	-- Statuszeile
	local statusLabel = label({
		Text = "Bereit.",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -6),
		Size = UDim2.new(1, -24, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(200, 200, 220),
		Parent = panel,
	})

	-- Tabs
	local tabBar = create("Frame", {
		Position = UDim2.fromOffset(12, 54),
		Size = UDim2.new(1, -24, 0, 34),
		BackgroundTransparency = 1,
		Parent = panel,
	}, {
		create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }),
	})
	local pages = {}
	local tabButtons = {}

	local function page(name: string)
		local p = create("ScrollingFrame", {
			Name = name,
			Position = UDim2.fromOffset(12, 96),
			Size = UDim2.new(1, -24, 1, -130),
			BackgroundColor3 = PANEL,
			ScrollBarThickness = 6,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			Visible = false,
			Parent = panel,
		}, {
			corner(12),
			padding(10),
			create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		pages[name] = p
		return p
	end

	local function showPage(name: string)
		for n, p in pages do
			p.Visible = n == name
		end
		for n, b in tabButtons do
			b.BackgroundColor3 = n == name and Color3.fromRGB(255, 160, 50) or Color3.fromRGB(70, 66, 100)
		end
	end

	local function tab(name: string, text: string)
		tabButtons[name] = button({
			Text = text,
			Size = UDim2.fromOffset(146, 34),
			BackgroundColor3 = Color3.fromRGB(70, 66, 100),
			Parent = tabBar,
		}, function()
			showPage(name)
		end)
	end

	local order = 0
	local function row(parent: Instance, height: number?)
		order += 1
		return create("Frame", {
			Size = UDim2.new(1, -8, 0, height or 36),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = parent,
		}, {
			create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 6),
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),
		})
	end

	local function heading(parent: Instance, text: string)
		order += 1
		label({
			Text = text,
			Size = UDim2.new(1, -8, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = ACCENT,
			LayoutOrder = order,
			Parent = parent,
		})
	end

	local function textBox(parent: Instance, placeholder: string, width: number, default: string?)
		return create("TextBox", {
			PlaceholderText = placeholder,
			Text = default or "",
			Size = UDim2.fromOffset(width, 32),
			BackgroundColor3 = Color3.fromRGB(25, 24, 36),
			TextColor3 = WHITE,
			PlaceholderColor3 = Color3.fromRGB(130, 130, 150),
			Font = FONT,
			TextScaled = true,
			ClearTextOnFocus = false,
			Parent = parent,
		}, { corner(8), padding(4) })
	end

	local function run(action: string, args)
		statusLabel.Text = "⏳ " .. action .. " …"
		statusLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
		local ok, success, message, data = pcall(function()
			return adminFunction:InvokeServer(action, args or {})
		end)
		if not ok then
			statusLabel.Text = "❌ Fehler: " .. tostring(success)
			statusLabel.TextColor3 = RED
			return nil
		end
		statusLabel.Text = (success and "✅ " or "❌ ") .. tostring(message or "")
		statusLabel.TextColor3 = success and GREEN or RED
		return success and data or nil
	end

	local function act(action: string, args)
		task.spawn(run, action, args)
	end

	---------------- Spieler ----------------
	local playersPage = page("Spieler")
	tab("Spieler", "👥 Spieler")

	local selectedLabel
	heading(playersPage, "Spieler auswählen")
	order += 1
	local playerList = create("Frame", {
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = playersPage,
	}, {
		create("UIGridLayout", { CellSize = UDim2.fromOffset(190, 52), CellPadding = UDim2.fromOffset(6, 6) }),
	})
	selectedLabel = label({
		Text = "Ausgewählt: –",
		Size = UDim2.new(1, -8, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = order + 1,
		Parent = playersPage,
	})
	order += 1

	local function refreshPlayers()
		local data = run("getState", {})
		if not data then
			return
		end
		for _, c in playerList:GetChildren() do
			if c:IsA("TextButton") then
				c:Destroy()
			end
		end
		local found = false
		for _, info in data.players do
			local isSelected = info.userId == selectedPlayer
			found = found or isSelected
			local b = button({
				Text = string.format(
					"%s\n%s · %d Eier%s",
					info.displayName,
					Config.formatMoney(info.money),
					info.eggs,
					info.locked and " · 🔒" or ""
				),
				BackgroundColor3 = isSelected and Color3.fromRGB(255, 160, 50) or Color3.fromRGB(70, 66, 100),
				Parent = playerList,
			}, function()
				selectedPlayer = info.userId
				refreshPlayers()
			end)
			b.TextXAlignment = Enum.TextXAlignment.Left
			if isSelected then
				selectedLabel.Text = "Ausgewählt: " .. info.displayName .. " (@" .. info.name .. ", Basis " .. info.base .. ")"
			end
		end
		if not found then
			selectedPlayer = nil
			selectedLabel.Text = "Ausgewählt: –"
		end
	end

	local r = row(playersPage)
	button(
		{ Text = "🔄 Aktualisieren", Size = UDim2.fromOffset(150, 32), BackgroundColor3 = Color3.fromRGB(70, 110, 200), Parent = r },
		function()
			task.spawn(refreshPlayers)
		end
	)

	heading(playersPage, "Geld")
	r = row(playersPage)
	local amountBox = textBox(r, "Betrag, z. B. 1000000", 200, "1000")
	button({ Text = "➕ Geben", Size = UDim2.fromOffset(110, 32), BackgroundColor3 = Color3.fromRGB(60, 170, 80), Parent = r }, function()
		act("giveMoney", { target = selectedPlayer, amount = tonumber(amountBox.Text) })
		task.delay(0.3, refreshPlayers)
	end)
	button(
		{ Text = "✏️ Setzen", Size = UDim2.fromOffset(110, 32), BackgroundColor3 = Color3.fromRGB(200, 150, 30), Parent = r },
		function()
			act("setMoney", { target = selectedPlayer, amount = tonumber(amountBox.Text) })
			task.delay(0.3, refreshPlayers)
		end
	)

	heading(playersPage, "Basis")
	r = row(playersPage)
	button({ Text = "🔒 Sperren (5 Min)", Size = UDim2.fromOffset(170, 32), Parent = r }, function()
		act("lockBase", { target = selectedPlayer, lock = true, seconds = 300 })
	end)
	button({ Text = "🔓 Entsperren", Size = UDim2.fromOffset(140, 32), Parent = r }, function()
		act("lockBase", { target = selectedPlayer, lock = false })
	end)
	button(
		{ Text = "🐣 Alle schlüpfen", Size = UDim2.fromOffset(160, 32), BackgroundColor3 = Color3.fromRGB(200, 90, 160), Parent = r },
		function()
			act("hatchAll", { target = selectedPlayer })
		end
	)
	r = row(playersPage)
	button(
		{ Text = "🧹 Basis leeren", Size = UDim2.fromOffset(150, 32), BackgroundColor3 = Color3.fromRGB(170, 70, 50), Parent = r },
		function()
			act("clearBase", { target = selectedPlayer })
		end
	)
	button({
		Text = "♻️ Spielstand zurücksetzen",
		Size = UDim2.fromOffset(230, 32),
		BackgroundColor3 = Color3.fromRGB(150, 40, 40),
		Parent = r,
	}, function()
		act("resetData", { target = selectedPlayer })
	end)

	heading(playersPage, "Bewegung & Moderation")
	r = row(playersPage)
	button({ Text = "📍 Hinteleportieren", Size = UDim2.fromOffset(170, 32), Parent = r }, function()
		act("teleportTo", { target = selectedPlayer })
	end)
	button({ Text = "🧲 Herholen", Size = UDim2.fromOffset(120, 32), Parent = r }, function()
		act("bring", { target = selectedPlayer })
	end)
	button(
		{ Text = "👢 Kicken", Size = UDim2.fromOffset(110, 32), BackgroundColor3 = Color3.fromRGB(150, 40, 40), Parent = r },
		function()
			act("kick", { target = selectedPlayer })
			task.delay(0.5, refreshPlayers)
		end
	)
	r = row(playersPage)
	local speedBox = textBox(r, "Tempo (16 = normal)", 170, "16")
	button({ Text = "🏃 Tempo setzen", Size = UDim2.fromOffset(150, 32), Parent = r }, function()
		act("speed", { target = selectedPlayer, value = tonumber(speedBox.Text) })
	end)

	---------------- Eier ----------------
	local eggsPage = page("Eier")
	tab("Eier", "🥚 Eier")

	heading(eggsPage, "Ei auswählen")
	order += 1
	local eggGrid = create("Frame", {
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = eggsPage,
	}, {
		create(
			"UIGridLayout",
			{ CellSize = UDim2.fromOffset(140, 46), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }
		),
	})
	local eggButtons = {}
	local function refreshEggButtons()
		for id, b in eggButtons do
			local outline = b:FindFirstChildOfClass("UIStroke")
			if outline then
				outline.Color = id == selectedEgg and ACCENT or Color3.new(0, 0, 0)
				outline.Thickness = id == selectedEgg and 3 or 1.5
			end
		end
	end
	for i, def in Config.Eggs do
		local rar = Config.Rarities[def.rarity]
		local b = button({
			Text = def.name .. "\n" .. rar.name,
			BackgroundColor3 = rar.color:Lerp(Color3.new(0, 0, 0), 0.45),
			LayoutOrder = i,
			Parent = eggGrid,
		}, function()
			selectedEgg = def.id
			refreshEggButtons()
		end)
		eggButtons[def.id] = b
	end
	refreshEggButtons()

	heading(eggsPage, "Mutation")
	r = row(eggsPage)
	local mutButtons = {}
	local function refreshMutButtons()
		for id, b in mutButtons do
			b.BackgroundColor3 = id == selectedMut and Color3.fromRGB(255, 160, 50) or Color3.fromRGB(70, 66, 100)
		end
	end
	mutButtons[""] = button({ Text = "Keine/Zufall", Size = UDim2.fromOffset(120, 32), Parent = r }, function()
		selectedMut = ""
		refreshMutButtons()
	end)
	for _, m in Config.Mutations do
		mutButtons[m.id] = button({ Text = m.name .. " x" .. m.mult, Size = UDim2.fromOffset(130, 32), Parent = r }, function()
			selectedMut = m.id
			refreshMutButtons()
		end)
	end
	refreshMutButtons()

	r = row(eggsPage)
	local hatchedToggle
	hatchedToggle = button(
		{ Text = "🥚 Als Ei", Size = UDim2.fromOffset(170, 32), BackgroundColor3 = Color3.fromRGB(70, 66, 100), Parent = r },
		function()
			spawnHatched = not spawnHatched
			hatchedToggle.Text = spawnHatched and "🐣 Schon geschlüpft" or "🥚 Als Ei"
		end
	)

	heading(eggsPage, "Spawnen")
	r = row(eggsPage)
	button(
		{ Text = "➡️ Aufs Laufband", Size = UDim2.fromOffset(170, 32), BackgroundColor3 = Color3.fromRGB(60, 170, 80), Parent = r },
		function()
			act("spawnEgg", { id = selectedEgg, mut = selectedMut, where = "conveyor" })
		end
	)
	button({
		Text = "🏠 In Basis des Spielers",
		Size = UDim2.fromOffset(210, 32),
		BackgroundColor3 = Color3.fromRGB(60, 140, 200),
		Parent = r,
	}, function()
		act("spawnEgg", { id = selectedEgg, mut = selectedMut, where = "base", target = selectedPlayer, hatched = spawnHatched })
	end)
	r = row(eggsPage)
	button(
		{ Text = "🧹 Laufband leeren", Size = UDim2.fromOffset(170, 32), BackgroundColor3 = Color3.fromRGB(170, 70, 50), Parent = r },
		function()
			act("clearConveyor", {})
		end
	)
	button({
		Text = "🐣 ALLE Eier schlüpfen",
		Size = UDim2.fromOffset(210, 32),
		BackgroundColor3 = Color3.fromRGB(200, 90, 160),
		Parent = r,
	}, function()
		act("hatchAll", { all = true })
	end)

	---------------- Events ----------------
	local eventsPage = page("Events")
	tab("Events", "🎉 Events")

	heading(eventsPage, "Dauer (Minuten) für Events")
	r = row(eventsPage)
	local minutesBox = textBox(r, "Minuten", 100, "5")
	local function minutes()
		return tonumber(minutesBox.Text) or 5
	end

	heading(eventsPage, "🍀 Glück (seltenere Eier & Mutationen)")
	r = row(eventsPage)
	for _, mult in { 2, 5, 10, 25 } do
		button(
			{ Text = "x" .. mult, Size = UDim2.fromOffset(80, 32), BackgroundColor3 = Color3.fromRGB(60, 170, 80), Parent = r },
			function()
				act("luck", { mult = mult, minutes = minutes() })
			end
		)
	end
	button({ Text = "Aus", Size = UDim2.fromOffset(70, 32), BackgroundColor3 = Color3.fromRGB(90, 90, 110), Parent = r }, function()
		act("luck", { mult = 1, minutes = 0 })
	end)

	heading(eventsPage, "💰 Geld-Boost")
	r = row(eventsPage)
	for _, mult in { 2, 3, 5, 10 } do
		button(
			{ Text = "x" .. mult, Size = UDim2.fromOffset(80, 32), BackgroundColor3 = Color3.fromRGB(200, 150, 30), Parent = r },
			function()
				act("incomeBoost", { mult = mult, minutes = minutes() })
			end
		)
	end
	button({ Text = "Aus", Size = UDim2.fromOffset(70, 32), BackgroundColor3 = Color3.fromRGB(90, 90, 110), Parent = r }, function()
		act("incomeBoost", { mult = 1, minutes = 0 })
	end)

	heading(eventsPage, "🐣 Schneller brüten")
	r = row(eventsPage)
	for _, mult in { 2, 5, 10 } do
		button(
			{ Text = "x" .. mult, Size = UDim2.fromOffset(80, 32), BackgroundColor3 = Color3.fromRGB(200, 90, 160), Parent = r },
			function()
				act("hatchBoost", { mult = mult, minutes = minutes() })
			end
		)
	end
	button({ Text = "Aus", Size = UDim2.fromOffset(70, 32), BackgroundColor3 = Color3.fromRGB(90, 90, 110), Parent = r }, function()
		act("hatchBoost", { mult = 1, minutes = 0 })
	end)

	heading(eventsPage, "🌧️ Eierregen")
	r = row(eventsPage)
	button({ Text = "10 Eier", Size = UDim2.fromOffset(100, 32), Parent = r }, function()
		act("eggRain", { count = 10, luck = 10 })
	end)
	button({ Text = "25 Eier (Glück x50)", Size = UDim2.fromOffset(190, 32), Parent = r }, function()
		act("eggRain", { count = 25, luck = 50 })
	end)

	heading(eventsPage, "⏱️ Laufband-Tempo (Sekunden pro Ei)")
	r = row(eventsPage)
	for _, interval in { 0.5, 1, 2.5, 5 } do
		button({ Text = interval .. " s", Size = UDim2.fromOffset(80, 32), Parent = r }, function()
			act("spawnRate", { interval = interval })
		end)
	end

	---------------- Durchsage ----------------
	local announcePage = page("Durchsage")
	tab("Durchsage", "📢 Durchsage")
	heading(announcePage, "Nachricht an alle Spieler")
	r = row(announcePage, 40)
	local announceBox = textBox(r, "Text eingeben …", 400)
	button(
		{ Text = "📢 Senden", Size = UDim2.fromOffset(120, 32), BackgroundColor3 = Color3.fromRGB(210, 60, 60), Parent = r },
		function()
			act("announce", { text = announceBox.Text })
			announceBox.Text = ""
		end
	)
	label({
		Text = "Texte laufen durch den Roblox-Textfilter.",
		Size = UDim2.new(1, -8, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(170, 170, 190),
		LayoutOrder = 99,
		Parent = announcePage,
	})

	showPage("Spieler")

	-- Auf kleinen Bildschirmen verkleinern
	local camera = workspace.CurrentCamera
	local function rescale()
		local vp = camera.ViewportSize
		local scale = math.min(1, (vp.X - 20) / 640, (vp.Y - 20) / 440)
		panel:FindFirstChild("Skalierung").Scale = math.max(scale, 0.5)
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	rescale()

	local function toggle()
		panel.Visible = not panel.Visible
		if panel.Visible then
			task.spawn(refreshPlayers)
		end
	end
	openButton.Activated:Connect(toggle)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.P then
			toggle()
		end
	end)
end

local function checkAdmin()
	if player:GetAttribute("IsAdmin") then
		buildAdminPanel()
	end
end
player:GetAttributeChangedSignal("IsAdmin"):Connect(checkAdmin)
checkAdmin()
