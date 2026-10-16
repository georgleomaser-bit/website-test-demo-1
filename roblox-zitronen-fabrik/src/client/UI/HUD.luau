--[[
	Das HUD: Geld oben in der Mitte, Menü-Knöpfe links, Event-Anzeige,
	"Zur Fabrik" und tägliche Belohnung unten.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Ui)
local Windows = require(script.Parent.Windows)
local Popups = require(script.Parent.Popups)
local MiscWindows = require(script.Parent.MiscWindows)

local HUD = {}

local player = Players.LocalPlayer

local root: Frame
local rootScale: UIScale
local cashLabel: TextLabel
local incomeLabel: TextLabel
local investorChip: TextLabel
local fruitChip: TextLabel
local multChip: TextLabel
local eventBanner: Frame
local eventLabel: TextLabel
local dailyButton: TextButton
local adminButton: TextButton
local badges: { [string]: Frame } = {}
local shownCash = 0

local function updateScale()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local vp = camera.ViewportSize
	local s = math.clamp(math.min(vp.X / 1150, vp.Y / 650), 0.55, 1.25)
	rootScale.Scale = s
	root.Size = UDim2.fromScale(1 / s, 1 / s)
end

local function menuButton(parent: Instance, order: number, emoji: string, text: string, color: Color3, windowName: string): TextButton
	local button = Ui.Button(parent, "", color, {
		Name = windowName .. "Button",
		LayoutOrder = order,
		Size = UDim2.fromOffset(86, 74),
		ZIndex = 5,
	}, function()
		Windows.Toggle(windowName)
	end)
	Ui.Stroke(button, 3, Color3.new(0, 0, 0), 0.25)
	Ui.Label(button, emoji, { Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 2), TextSize = 36, ZIndex = 6 })
	Ui.Label(button, text, { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 1, -26), TextSize = 17, TextStrokeTransparency = 0.3, ZIndex = 6 })
	local badge = Ui.Frame(button, {
		Name = "Badge",
		Size = UDim2.fromOffset(24, 24),
		Position = UDim2.new(1, -16, 0, -8),
		BackgroundColor3 = Ui.Colors.Red,
		Visible = false,
		ZIndex = 7,
	})
	Ui.Corner(badge, 12)
	Ui.Stroke(badge, 2, Color3.new(1, 1, 1), 0)
	Ui.Label(badge, "!", { Size = UDim2.fromScale(1, 1), TextSize = 20, ZIndex = 8 })
	badges[windowName] = badge
	return button
end

function HUD.Create(): Frame
	local gui = Instance.new("ScreenGui")
	gui.Name = "ZitronenHUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	root = Ui.Frame(gui, { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	rootScale = Instance.new("UIScale")
	rootScale.Parent = root
	updateScale()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end

	Windows.Root = root
	Popups.Init(root)

	-- Geld
	local cashPanel = Ui.Frame(root, {
		Name = "Cash",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(340, 86),
		BackgroundTransparency = 0.25,
		ZIndex = 2,
	})
	Ui.Corner(cashPanel, 12)
	Ui.Stroke(cashPanel, 2, Color3.new(0, 0, 0), 0.4)
	cashLabel = Ui.Label(cashPanel, "$0", {
		Size = UDim2.new(1, -10, 0, 52),
		Position = UDim2.fromOffset(5, 2),
		TextSize = 48,
		TextColor3 = Ui.Colors.Cash,
		TextStrokeTransparency = 0,
		ZIndex = 3,
	})
	incomeLabel = Ui.Label(cashPanel, "+$0/s", {
		Size = UDim2.new(1, -10, 0, 26),
		Position = UDim2.fromOffset(5, 54),
		TextSize = 22,
		ZIndex = 3,
	})

	-- Infos unter dem Geld
	local chips = Ui.Frame(root, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 98),
		Size = UDim2.fromOffset(520, 30),
		BackgroundTransparency = 1,
		ZIndex = 2,
	})
	local chipLayout = Ui.List(chips, 8, true)
	chipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local function chip(order: number, color: Color3): TextLabel
		local label = Ui.Label(chips, "", {
			LayoutOrder = order,
			Size = UDim2.fromOffset(0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 0.25,
			BackgroundColor3 = color,
			TextSize = 20,
			TextStrokeTransparency = 0.3,
			ZIndex = 3,
		})
		Ui.Corner(label, 15)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 12)
		pad.PaddingRight = UDim.new(0, 12)
		pad.Parent = label
		return label
	end
	investorChip = chip(1, Ui.Colors.Purple)
	fruitChip = chip(2, Color3.fromRGB(180, 140, 0))
	multChip = chip(3, Ui.Colors.Blue)

	-- Event-Anzeige
	eventBanner = Ui.Frame(root, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 136),
		Size = UDim2.fromOffset(460, 44),
		BackgroundColor3 = Ui.Colors.Purple,
		Visible = false,
		ZIndex = 2,
	})
	Ui.Corner(eventBanner, 12)
	Ui.Stroke(eventBanner, 3, Color3.fromRGB(255, 230, 90), 0)
	eventLabel = Ui.Label(eventBanner, "", { Size = UDim2.fromScale(1, 1), TextSize = 26, TextStrokeTransparency = 0.2, ZIndex = 3 })

	-- Menü links
	local menu = Ui.Frame(root, {
		Name = "Menu",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(86, 600),
		BackgroundTransparency = 1,
		ZIndex = 4,
	})
	local menuLayout = Ui.List(menu, 8)
	menuLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	menuButton(menu, 1, "🏭", "Fabrik", Ui.Colors.Green, "Factory")
	menuButton(menu, 2, "⬆️", "Upgrades", Ui.Colors.Blue, "Upgrades")
	menuButton(menu, 3, "🛸", "Rebirth", Ui.Colors.Purple, "Rebirth")
	menuButton(menu, 4, "🌀", "Evolution", Ui.Colors.Pink, "Evolution")
	if MiscWindows.ShopEnabled() then
		menuButton(menu, 5, "🛒", "Shop", Ui.Colors.Orange, "Shop")
	end
	menuButton(menu, 6, "⚙️", "Optionen", Ui.Colors.Grey, "Settings")
	adminButton = menuButton(menu, 7, "🛠️", "Test", Ui.Colors.Red, "Admin")
	adminButton.Visible = false

	-- Unten
	local action = Remotes.Get("Action")
	local home = Ui.Button(root, "🏠 Zur Fabrik", Ui.Colors.Blue, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0.5, -8, 1, -12),
		Size = UDim2.fromOffset(200, 50),
		TextSize = 24,
		ZIndex = 4,
	}, function()
		action:FireServer("TeleportHome")
	end)
	Ui.Stroke(home, 3, Color3.new(0, 0, 0), 0.25)
	dailyButton = Ui.Button(root, "🎁 Belohnung!", Ui.Colors.Gold, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.5, 8, 1, -12),
		Size = UDim2.fromOffset(200, 50),
		TextSize = 24,
		ZIndex = 4,
		Visible = false,
	}, function()
		HUD.ShowDaily()
	end)
	Ui.Stroke(dailyButton, 3, Color3.new(0, 0, 0), 0.25)

	return root
end

local dailyModalOpen = false
function HUD.ShowDaily()
	local data = State.Data
	if not data or not data.Daily or not data.Daily.Available or dailyModalOpen then
		return
	end
	dailyModalOpen = true
	local daily = data.Daily
	local days = {}
	for d = 1, #Config.Daily.Minutes do
		table.insert(days, (d == daily.Streak and "👉" or "") .. "Tag " .. d .. (d < daily.Streak and " ✓" or ""))
	end
	Popups.Modal(
		"🎁 Tägliche Belohnung",
		"Tag " .. daily.Streak .. " deiner Serie!\n+" .. Format.Cash(daily.Reward) .. "\n\n" .. table.concat(days, "  ·  "),
		"Abholen!",
		Ui.Colors.Gold,
		function()
			dailyModalOpen = false
			Remotes.Get("Action"):FireServer("ClaimDaily")
		end
	)
end

local function updateBadges(data)
	local view = State.ProfileView()
	if not view then
		return
	end
	local cash = State.Cash()
	-- Upgrades: etwas bezahlbar?
	local upgradeReady = false
	for _, info in ipairs(Config.CashUpgrades) do
		if not data.Profile.Upgrades[info.Id] then
			upgradeReady = cash >= info.Cost
			break
		end
	end
	badges.Upgrades.Visible = upgradeReady
	-- Rebirth: lohnt es sich? (mindestens so viele neue wie man hat)
	local claim = Economy.ClaimableInvestors(view)
	badges.Rebirth.Visible = claim >= math.max(Config.Rebirth.MinInvestors, data.Profile.Investors)
	badges.Evolution.Visible = Economy.CanEvolve(view)
	-- Fabrik: eine Linie ohne Manager wartet aufs Drücken
	local factoryReady = false
	local discount = data.Stats.Discount
	for i, laneCfg in ipairs(Config.Lanes) do
		local lane = data.Profile.Lanes[i]
		if lane.Level > 0 and lane.Level < Config.MaxLevel and cash >= Economy.LevelCost(laneCfg, lane.Level, 1, discount) then
			factoryReady = true
		end
	end
	badges.Factory.Visible = factoryReady
end

function HUD.Start()
	local badgeTimer = 0
	local dailyAutoShown = false
	RunService.RenderStepped:Connect(function(dt)
		local data = State.Data
		-- Geld (zählt weich hoch)
		local cash = State.Cash()
		if math.abs(cash - shownCash) <= math.max(0.01, cash * 0.001) then
			shownCash = cash
		else
			shownCash += (cash - shownCash) * math.min(1, dt * 12)
		end
		cashLabel.Text = Format.Cash(shownCash)
		incomeLabel.Text = "+" .. Format.Cash(State.Income()) .. " pro Sekunde"

		-- Event
		local eventId = workspace:GetAttribute("EventId")
		local ends = workspace:GetAttribute("EventEnds") or 0
		local left = ends - workspace:GetServerTimeNow()
		if eventId and eventId ~= "" and left > 0 then
			eventBanner.Visible = true
			eventLabel.Text = (workspace:GetAttribute("EventEmoji") or "") .. " " .. (workspace:GetAttribute("EventName") or "") .. "  " .. Format.Time(left)
		else
			eventBanner.Visible = false
		end

		if not data then
			return
		end
		badgeTimer += dt
		if badgeTimer >= 0.5 then
			badgeTimer = 0
			local p = data.Profile
			investorChip.Text = "🛸 " .. Format.Number(p.Investors) .. "  (+" .. Format.Percent(data.Stats.InvestorMult - 1) .. ")"
			local fruit = Config.Fruits[p.Evolution + 1]
			fruitChip.Text = fruit.Emoji .. " " .. fruit.Name
			multChip.Text = "Gesamt ×" .. Format.Number(data.Stats.Global)
			adminButton.Visible = data.IsAdmin == true
			local dailyReady = data.Daily and data.Daily.Available
			dailyButton.Visible = dailyReady == true
			if dailyReady and not dailyAutoShown then
				dailyAutoShown = true
				task.delay(3, HUD.ShowDaily)
			end
			updateBadges(data)
		end
	end)
end

return HUD
