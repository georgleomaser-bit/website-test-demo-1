-- =====================================================================
--  ADMIN-PANEL (wird nur gebaut, wenn der Server dich als Admin markiert;
--  JEDE Aktion wird zusätzlich auf dem Server geprüft – Exploiter haben keine Chance)
--  Öffnen: Knopf "Admin" rechts oder Taste P
--  Reiter: Spawnen / Events / Spieler / Kräfte / Server
--  Das Ziel-Feld oben (me / all / others / Name / UserId) gilt für alle Reiter.
--  Gefährliche Aktionen brauchen einen zweiten Klick.
-- =====================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent:WaitForChild("UI"))

local AdminPanel = {}

local Theme = UI.Theme
local built = false
local player = Players.LocalPlayer
local STATUS_POP_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TAB_POP_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CONFIRM_TIME = 5 -- Sekunden: so lange gilt der erste Klick einer gefährlichen Aktion
local SPECTATE_KEY = Enum.KeyCode.X

local TABS = {
	{ Id = "Spawn", Text = "Spawnen", Color = Theme.Orange },
	{ Id = "Events", Text = "Events", Color = Theme.Purple },
	{ Id = "Players", Text = "Spieler", Color = Theme.Blue },
	{ Id = "Powers", Text = "Kräfte", Color = Theme.Green },
	{ Id = "Server", Text = "Server", Color = Theme.Red },
}

local function darker(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

local function rainbowSequence(): ColorSequence
	local keys = {}
	for k = 0, 6 do
		table.insert(keys, ColorSequenceKeypoint.new(k / 6, Color3.fromHSV(k / 6, 0.8, 1)))
	end
	return ColorSequence.new(keys)
end

local function clearChildren(parent: Instance, className: string)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA(className) then
			child:Destroy()
		end
	end
end

-- Einfache Liste (Frame, wächst mit dem Inhalt)
local function listFrame(parent: Instance, order: number): Frame
	return UI.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	}, {
		UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }),
	})
end

type Slider = { Set: (value: number) -> (), Get: () -> number }

-- Schieberegler: Wert wird beim Loslassen geschickt (spart Anfragen)
local function slider(
	parent: Instance,
	order: number,
	title: string,
	min: number,
	max: number,
	default: number,
	onRelease: (number) -> ()
): Slider
	local row = UI.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	UI.Label({
		Size = UDim2.new(0.24, 0, 1, 0),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 18,
		Outline = 2,
		Parent = row,
	})
	local track: TextButton = UI.Create("TextButton", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.26, 0, 0.5, 0),
		Size = UDim2.new(0.56, 0, 0, 18),
		BackgroundColor3 = Theme.PanelDark,
		AutoButtonColor = false,
		Text = "",
		Parent = row,
	}, { UI.Corner(9), UI.Stroke(Color3.new(0, 0, 0), 2) })
	local fill: Frame = UI.Create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Green,
		Parent = track,
	}, { UI.Corner(9) })
	local knob: Frame = UI.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 2,
		Parent = track,
	}, { UI.Corner(13), UI.Stroke(Color3.new(0, 0, 0), 3) })
	local valueLabel = UI.Label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0.16, 0, 1, 0),
		Text = "",
		MaxText = 20,
		Outline = 2,
		Parent = row,
	})
	local value = default
	local function show()
		local ratio = math.clamp((value - min) / math.max(1, max - min), 0, 1)
		fill.Size = UDim2.fromScale(ratio, 1)
		knob.Position = UDim2.fromScale(ratio, 0.5)
		valueLabel.Text = tostring(value)
	end
	local function setFromX(x: number)
		local width = math.max(1, track.AbsoluteSize.X)
		local ratio = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		value = math.floor(min + ratio * (max - min) + 0.5)
		show()
	end
	local dragging = false
	track.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		local kind = input.UserInputType
		if dragging and (kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local kind = input.UserInputType
		if dragging and (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) then
			dragging = false
			task.spawn(onRelease, value)
		end
	end)
	show()
	return {
		Set = function(newValue: number)
			value = math.clamp(math.floor(newValue + 0.5), min, max)
			show()
		end,
		Get = function(): number
			return value
		end,
	}
end

function AdminPanel.Build(ctx: any)
	if built then
		return
	end
	built = true
	local Config = ctx.Config
	local Util = ctx.Util
	local Aliens = ctx.Aliens
	local Remotes = ctx.Remotes
	local powers = Config.AdminPowers or {}

	local win = UI.Window("ADMIN-PANEL", 720, 600, Theme.Red)

	-- -----------------------------------------------------------------
	-- Kopfzeile: Reiter + Ziel-Feld + Statuszeile (scrollen nicht mit)
	-- -----------------------------------------------------------------
	local tabBar = UI.Create("Frame", {
		Name = "Tabs",
		Position = UDim2.fromOffset(12, 68),
		Size = UDim2.new(1, -24, 0, 42),
		BackgroundTransparency = 1,
		Parent = win.Panel,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
	})
	local topRow = UI.Create("Frame", {
		Name = "TargetRow",
		Position = UDim2.fromOffset(12, 116),
		Size = UDim2.new(1, -24, 0, 34),
		BackgroundTransparency = 1,
		Parent = win.Panel,
	})
	local targetBox = UI.TextBox({
		Size = UDim2.new(0.3, 0, 1, 0),
		Text = "me",
		PlaceholderText = "Ziel: me / all / Name",
		Parent = topRow,
	})
	local status = UI.Label({
		Position = UDim2.new(0.31, 0, 0, 0),
		Size = UDim2.new(0.69, 0, 1, 0),
		Text = "Bereit. Ziel links: me / all / others / Name / UserId",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.SubText,
		Font = Enum.Font.GothamBold,
		MaxText = 16,
		Parent = topRow,
	})
	win.Content.Position = UDim2.fromOffset(12, 158)
	win.Content.Size = UDim2.new(1, -24, 1, -170)

	local statusScale: UIScale = UI.Create("UIScale", { Scale = 1, Parent = status })
	local function setStatus(text: string, color: Color3)
		status.Text = text
		status.TextColor3 = color
		statusScale.Scale = 1.1
		TweenService:Create(statusScale, STATUS_POP_INFO, { Scale = 1 }):Play()
	end

	local function admin(action: string, args: { [string]: any }?): any
		local ok, result = pcall(function()
			return Remotes.Admin:InvokeServer(action, args or {})
		end)
		if ok and type(result) == "table" then
			setStatus(
				(if result.Ok then "OK: " else "Fehler: ") .. tostring(result.Message),
				if result.Ok then Theme.Cash else Theme.Red
			)
			return result
		end
		setStatus("Keine Antwort vom Server", Theme.Red)
		return nil
	end

	-- Gefährliche Aktion: erst beim zweiten Klick (innerhalb von CONFIRM_TIME Sekunden) ausführen
	local confirmKey: string? = nil
	local confirmAt = 0
	local function needsConfirm(key: string, label: string): boolean
		local now = os.clock()
		if confirmKey ~= key or now - confirmAt > CONFIRM_TIME then
			confirmKey = key
			confirmAt = now
			setStatus("Nochmal klicken zum Bestätigen: " .. label, Theme.Orange)
			return true
		end
		confirmKey = nil
		return false
	end

	local function target(): string
		return targetBox.Text
	end

	-- Reiter-Seiten
	local pages: { [string]: Frame } = {}
	local tabButtons: { [string]: UI.Button } = {}
	local currentTab = "Spawn"
	local onTabOpen: { [string]: () -> () } = {}
	local function selectTab(id: string)
		currentTab = id
		for pageId, page in pairs(pages) do
			page.Visible = pageId == id
			local scale = page:FindFirstChildOfClass("UIScale")
			if pageId == id and scale then
				scale.Scale = 0.95
				TweenService:Create(scale, TAB_POP_INFO, { Scale = 1 }):Play()
			end
		end
		for _, tab in ipairs(TABS) do
			local button = tabButtons[tab.Id]
			if button then
				button.SetColor(if tab.Id == id then tab.Color else Theme.Gray)
			end
		end
		win.Content.CanvasPosition = Vector2.zero
		local hook = onTabOpen[id]
		if hook then
			task.spawn(hook)
		end
	end
	for i, tab in ipairs(TABS) do
		pages[tab.Id] = UI.Create("Frame", {
			Name = tab.Id,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = i,
			Visible = false,
			Parent = win.Content,
		}, {
			UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
			UI.Create("UIScale", { Scale = 1 }),
		})
		tabButtons[tab.Id] = UI.Button({
			Size = UDim2.new(1 / #TABS, -5, 1, 0),
			Text = tab.Text,
			Color = Theme.Gray,
			LayoutOrder = i,
			MaxText = 18,
			Parent = tabBar,
		}, function()
			selectTab(tab.Id)
		end)
	end

	-- Kleiner Knopf-Helfer für Raster
	local function gridButtons(parent: Instance, order: number, cellX: number, list: { { any } })
		local grid = UI.Grid(parent, order, cellX, 40)
		for i, info in ipairs(list) do
			UI.Button({
				Text = info[1],
				Color = info[2],
				LayoutOrder = i,
				MaxText = 14,
				Wrap = true,
				StrokeSize = 2,
				Parent = grid,
			}, info[3])
		end
		return grid
	end

	-- Ein/Aus-Knopf (Text + Farbe wechseln)
	local function toggleButton(
		parent: Instance,
		order: number,
		size: UDim2,
		offText: string,
		onText: string,
		onColor: Color3,
		onChange: (boolean) -> ()
	): (UI.Button, (boolean) -> ())
		local state = false
		local button: UI.Button
		local function show(value: boolean)
			state = value
			button.SetText(if value then onText else offText)
			button.SetColor(if value then onColor else Theme.Gray)
		end
		button = UI.Button({
			Size = size,
			Text = offText,
			Color = Theme.Gray,
			LayoutOrder = order,
			MaxText = 16,
			Parent = parent,
		}, function()
			show(not state)
			onChange(state)
		end)
		return button, show
	end

	-- =================================================================
	-- REITER: SPAWNEN
	-- =================================================================
	local spawnPage = pages.Spawn
	UI.Section(spawnPage, "Meteor / Alien spawnen", 10)
	local selectedMeteor = Config.Meteors[1] and Config.Meteors[1].Id or ""
	local selectedMutation = "Normal"
	local selectedAlien: string? = nil
	local selectedLabel = UI.Label({
		Size = UDim2.new(1, 0, 0, 24),
		Text = "",
		LayoutOrder = 11,
		MaxText = 18,
		Outline = 2,
		Parent = spawnPage,
	})
	local alienGrid: Frame
	local function updateSelected()
		local def = Config.MeteorsById[selectedMeteor]
		if not def then
			selectedLabel.Text = "Kein Meteor ausgewählt"
			return
		end
		local rarity = Config.RaritiesByName[def.Rarity]
		local alien = selectedAlien and Aliens.ById[selectedAlien]
		selectedLabel.Text = ("%s %s (%s)%s"):format(
			selectedMutation,
			def.Name,
			def.Rarity,
			if alien then ("  ->  " .. alien.Name .. " [" .. alien.Tier .. "]") else ""
		)
		selectedLabel.TextColor3 = if rarity then rarity.Color else Theme.Text
	end
	-- Alien-Varianten des gewählten Meteors (Aliens.ByMeteor)
	local function rebuildAliens()
		clearChildren(alienGrid, "Frame")
		local options = Aliens.ByMeteor[selectedMeteor] or {}
		selectedAlien = options[1] and options[1].Id or nil
		for i, option in ipairs(options) do
			local def = Aliens.ById[option.Id]
			if def then
				UI.Button({
					Text = def.Name .. " (" .. def.Tier .. ")",
					Color = if def.Tier == "Ultra"
						then Theme.Pink
						elseif def.Tier == "Selten" then Theme.Blue
						else Theme.PanelLight,
					LayoutOrder = i,
					MaxText = 13,
					Wrap = true,
					StrokeSize = 2,
					Parent = alienGrid,
				}, function()
					selectedAlien = def.Id
					updateSelected()
				end)
			end
		end
		updateSelected()
	end
	local meteorGrid = UI.Grid(spawnPage, 12, 124, 40)
	for i, def in ipairs(Config.Meteors) do
		local rarity = Config.RaritiesByName[def.Rarity]
		local rarityColor: Color3 = if rarity then rarity.Color else Theme.Gray
		UI.Button({
			Text = def.Name,
			Color = darker(rarityColor, 0.35),
			LayoutOrder = i,
			MaxText = 13,
			Wrap = true,
			StrokeSize = 2,
			Parent = meteorGrid,
		}, function()
			selectedMeteor = def.Id
			rebuildAliens()
		end)
	end
	UI.Label({
		Size = UDim2.new(1, 0, 0, 22),
		Text = "Alien-Variante:",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.SubText,
		LayoutOrder = 13,
		MaxText = 16,
		Parent = spawnPage,
	})
	alienGrid = UI.Grid(spawnPage, 14, 200, 40)
	local mutGrid = UI.Grid(spawnPage, 15, 124, 38)
	for i, mut in ipairs(Config.Mutations) do
		local mutButton = UI.Button({
			Text = mut.Name .. " x" .. mut.Mult,
			Color = darker(mut.Color or Theme.Gray, 0.25),
			LayoutOrder = i,
			MaxText = 15,
			Parent = mutGrid,
		}, function()
			selectedMutation = mut.Name
			updateSelected()
		end)
		if mut.Rainbow == true then
			mutButton.Label.TextColor3 = Color3.new(1, 1, 1)
			UI.Create("UIGradient", { Color = rainbowSequence(), Parent = mutButton.Label })
		end
	end
	rebuildAliens()
	local countRow = UI.Row(spawnPage, 16, 38)
	local countBox = UI.TextBox({
		Size = UDim2.new(0.5, -3, 1, 0),
		PlaceholderText = "Anzahl Eier (1-25)",
		Text = "1",
		LayoutOrder = 1,
		Parent = countRow,
	})
	local levelBox = UI.TextBox({
		Size = UDim2.new(0.5, -3, 1, 0),
		PlaceholderText = "Level (1-" .. tostring(Config.MaxLevel) .. ")",
		Text = "1",
		LayoutOrder = 2,
		Parent = countRow,
	})
	gridButtons(spawnPage, 17, 214, {
		{
			"Alien in Ziel-Base (geschlüpft)",
			Theme.Purple,
			function()
				admin("SpawnAlien", {
					MeteorId = selectedMeteor,
					AlienId = selectedAlien,
					Mutation = selectedMutation,
					Level = levelBox.Text,
					Where = "Base",
					Target = target(),
				})
			end,
		},
		{
			"Alien als Ei vor mir",
			Theme.Green,
			function()
				admin("SpawnAlien", {
					MeteorId = selectedMeteor,
					AlienId = selectedAlien,
					Mutation = selectedMutation,
					Level = levelBox.Text,
					Where = "Ground",
				})
			end,
		},
		{
			"Ei in Ziel-Base",
			Theme.Purple,
			function()
				admin("GiveMeteor", {
					MeteorId = selectedMeteor,
					Mutation = selectedMutation,
					Level = levelBox.Text,
					Target = target(),
				})
			end,
		},
		{
			"Ei zur Parade",
			Theme.Orange,
			function()
				admin(
					"SpawnMeteor",
					{ MeteorId = selectedMeteor, Mutation = selectedMutation, Count = countBox.Text, Where = "Parade" }
				)
			end,
		},
		{
			"Ei vor mir",
			Theme.Orange,
			function()
				admin(
					"SpawnMeteor",
					{ MeteorId = selectedMeteor, Mutation = selectedMutation, Count = countBox.Text, Where = "Me" }
				)
			end,
		},
		{
			"Gratis-Ei in Gratis-Zone",
			Theme.Green,
			function()
				admin("SpawnMeteor", {
					MeteorId = selectedMeteor,
					Mutation = selectedMutation,
					Count = countBox.Text,
					Where = "Free",
					Free = true,
				})
			end,
		},
	})

	-- Admin-Meteore
	UI.Section(spawnPage, "Admin-Meteore", 30, Color3.fromRGB(255, 80, 80))
	local adminMeteors = {}
	for _, def in ipairs(Config.Meteors) do
		if def.Rarity == "Admin" then
			table.insert(adminMeteors, def)
		end
	end
	for i, def in ipairs(adminMeteors) do
		local card = UI.Card({ Size = UDim2.new(1, 0, 0, 52), LayoutOrder = 30 + i, Parent = spawnPage })
		local nameColor: Color3 = if typeof(def.Color) == "Color3" then def.Color else Color3.fromRGB(255, 40, 40)
		local nameLabel = UI.Label({
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(0.38, -12, 1, -12),
			Text = tostring(def.Name),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = nameColor:Lerp(Color3.new(1, 1, 1), 0.3),
			MaxText = 20,
			Outline = 2,
			Parent = card,
		})
		if def.Effects and def.Effects.Rainbow then
			nameLabel.TextColor3 = Color3.new(1, 1, 1)
			UI.Create("UIGradient", { Color = rainbowSequence(), Parent = nameLabel })
		end
		UI.Button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(0.69, -4, 0.5, 0),
			Size = UDim2.new(0.31, -6, 0, 38),
			Text = "Gratis in die Mitte",
			Color = Theme.Green,
			MaxText = 16,
			Parent = card,
		}, function()
			admin("SpawnAdminMeteor", { MeteorId = def.Id, Where = "Free" })
		end)
		UI.Button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.new(0.31, -6, 0, 38),
			Text = "In meine Base",
			Color = Theme.Purple,
			MaxText = 16,
			Parent = card,
		}, function()
			admin("SpawnAdminMeteor", { MeteorId = def.Id, Where = "Base" })
		end)
	end
	local adminRainRow = UI.Row(spawnPage, 50, 44)
	local adminRainBox = UI.TextBox({
		Size = UDim2.new(0.3, -3, 1, 0),
		PlaceholderText = "Anzahl (1-8)",
		Text = "4",
		LayoutOrder = 1,
		Parent = adminRainRow,
	})
	UI.Button({
		Size = UDim2.new(0.7, -3, 1, 0),
		Text = "Admin-Meteor-Regen",
		Color = Color3.fromRGB(220, 40, 60),
		LayoutOrder = 2,
		MaxText = 20,
		Parent = adminRainRow,
	}, function()
		local count = math.clamp(math.floor(tonumber(adminRainBox.Text) or 4), 1, 8)
		adminRainBox.Text = tostring(count)
		admin("AdminRain", { Count = count })
	end)

	-- Eierregen in der Parade
	UI.Section(spawnPage, "Eierregen in der Parade", 60)
	local rainGrid = UI.Grid(spawnPage, 61, 100, 38)
	UI.Button({ Text = "Zufall", Color = Theme.Gray, LayoutOrder = 0, MaxText = 15, Parent = rainGrid }, function()
		admin("MeteorRain", { Count = if countBox.Text ~= "1" then countBox.Text else 15 })
	end)
	for i, rarity in ipairs(Config.Rarities) do
		if not rarity.AdminOnly then
			UI.Button({
				Text = rarity.Name,
				Color = darker(rarity.Color, 0.3),
				LayoutOrder = i,
				MaxText = 14,
				Parent = rainGrid,
			}, function()
				admin(
					"MeteorRain",
					{ Rarity = rarity.Name, Count = if countBox.Text ~= "1" then countBox.Text else 10 }
				)
			end)
		end
	end

	-- =================================================================
	-- REITER: EVENTS
	-- =================================================================
	local eventPage = pages.Events
	local globalToggle = false
	local globalRow = UI.Row(eventPage, 1, 40)
	toggleButton(
		globalRow,
		1,
		UDim2.new(1, 0, 1, 0),
		"Nur dieser Server (klicken für ALLE Server)",
		"ALLE Server",
		Theme.Purple,
		function(value)
			globalToggle = value
		end
	)
	UI.Section(eventPage, "Nacht", 10)
	gridButtons(eventPage, 11, 214, {
		{
			"Nacht starten",
			Color3.fromRGB(60, 70, 160),
			function()
				admin("Night", { Mode = "Night", Global = globalToggle })
			end,
		},
		{
			"Blutmond starten",
			Color3.fromRGB(190, 30, 40),
			function()
				admin("Night", { Mode = "BloodMoon", Global = globalToggle })
			end,
		},
		{
			"Nacht beenden",
			Theme.Gray,
			function()
				admin("Night", { Mode = "End", Global = globalToggle })
			end,
		},
	})
	UI.Section(eventPage, "Parade & Eier", 20)
	local eventRow = UI.Row(eventPage, 21, 38)
	local multBox = UI.TextBox({
		Size = UDim2.new(0.33, -4, 1, 0),
		PlaceholderText = "Glück x",
		Text = "2",
		LayoutOrder = 1,
		Parent = eventRow,
	})
	local minutesBox = UI.TextBox({
		Size = UDim2.new(0.33, -4, 1, 0),
		PlaceholderText = "Minuten",
		Text = "10",
		LayoutOrder = 2,
		Parent = eventRow,
	})
	local bossBox = UI.TextBox({
		Size = UDim2.new(0.33, -4, 1, 0),
		PlaceholderText = "Bosse (1-10)",
		Text = tostring(powers.BossParadeCount or 4),
		LayoutOrder = 3,
		Parent = eventRow,
	})
	gridButtons(eventPage, 22, 214, {
		{
			"Glück starten",
			Theme.Green,
			function()
				admin("ServerLuck", { Mult = multBox.Text, Minutes = minutesBox.Text, Global = globalToggle })
			end,
		},
		{
			"Meteoritenschauer",
			Theme.Orange,
			function()
				admin("StartShower", { Seconds = (tonumber(minutesBox.Text) or 1) * 60, Global = globalToggle })
			end,
		},
		{
			"Egg Rush",
			Color3.fromRGB(230, 170, 20),
			function()
				admin("EggRush", { Global = globalToggle })
			end,
		},
		{
			"Boss-Parade",
			Theme.Pink,
			function()
				admin("BossParade", { Count = bossBox.Text, Global = globalToggle })
			end,
		},
	})
	UI.Section(eventPage, "Ansage", 30)
	local announceRow = UI.Row(eventPage, 31, 42)
	local announceBox = UI.TextBox({
		Size = UDim2.new(0.7, -3, 1, 0),
		PlaceholderText = "Nachricht an alle...",
		LayoutOrder = 1,
		Parent = announceRow,
	})
	UI.Button({
		Size = UDim2.new(0.3, -3, 1, 0),
		Text = "Senden",
		Color = Theme.Blue,
		LayoutOrder = 2,
		MaxText = 18,
		Parent = announceRow,
	}, function()
		admin("Announce", { Text = announceBox.Text, Global = globalToggle })
	end)
	UI.Section(eventPage, "Spaß", 40)
	gridButtons(eventPage, 41, 214, {
		{
			"Alle Eier sofort schlüpfen",
			Theme.Green,
			function()
				admin("HatchAllServer")
			end,
		},
		{
			"Konfetti-Regen für alle",
			Theme.Pink,
			function()
				admin("ConfettiAll")
			end,
		},
		{
			"Alle zur Mitte",
			Theme.Blue,
			function()
				if needsConfirm("TeleportAllCenter", "Alle zur Mitte") then
					return
				end
				admin("TeleportAllCenter")
			end,
		},
		{
			"ADMIN ABUSE",
			Color3.fromRGB(220, 40, 130),
			function()
				admin("AdminAbuse", { Global = globalToggle })
			end,
		},
		{
			"Mond-Schwerkraft",
			Theme.Purple,
			function()
				admin("Gravity", { Moon = true, Global = globalToggle })
			end,
		},
		{
			"Normale Schwerkraft",
			Theme.Gray,
			function()
				admin("Gravity", { Moon = false, Global = globalToggle })
			end,
		},
	})

	-- =================================================================
	-- REITER: SPIELER
	-- =================================================================
	local playerPage = pages.Players
	local spectate: (target: Player?) -> () -- (unten bei den Kräften)
	UI.Section(playerPage, "Spieler auf dem Server", 10)
	local playerList = listFrame(playerPage, 12)
	local function refreshPlayers()
		local result = admin("GetPlayers")
		clearChildren(playerList, "Frame")
		if not result or type(result.Data) ~= "table" then
			return
		end
		for i, info in ipairs(result.Data) do
			local card = UI.Card({ Size = UDim2.new(1, 0, 0, 54), LayoutOrder = i, Parent = playerList })
			UI.Label({
				Position = UDim2.fromOffset(10, 4),
				Size = UDim2.new(0.34, -10, 0, 26),
				Text = tostring(info.DisplayName) .. (if info.IsAdmin then " (Admin)" else ""),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxText = 18,
				Outline = 2,
				Parent = card,
			})
			UI.Label({
				Position = UDim2.fromOffset(10, 30),
				Size = UDim2.new(0.34, -10, 0, 18),
				Text = "@" .. tostring(info.Name) .. "  " .. tostring(info.UserId),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Theme.SubText,
				Font = Enum.Font.GothamBold,
				MaxText = 13,
				Parent = card,
			})
			UI.Label({
				Position = UDim2.new(0.34, 0, 0, 6),
				Size = UDim2.new(0.4, -6, 1, -12),
				Text = ("%s  •  %d Rebirths  •  %d Aliens\nSpielzeit %s  •  Ping %s"):format(
					Util.FormatCash(tonumber(info.Cash) or 0),
					tonumber(info.Rebirths) or 0,
					tonumber(info.Index) or 0,
					Util.FormatTime(tonumber(info.PlayTime) or 0),
					if tonumber(info.Ping) then (tostring(info.Ping) .. " ms") else "?"
				),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Theme.SubText,
				Font = Enum.Font.GothamBold,
				TextWrapped = true,
				MaxText = 14,
				Parent = card,
			})
			UI.Button({
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(0.87, -4, 0.5, 0),
				Size = UDim2.new(0.12, -4, 0, 38),
				Text = "Ziel",
				Color = Theme.Blue,
				MaxText = 15,
				Parent = card,
			}, function()
				targetBox.Text = tostring(info.Name)
				setStatus("Ziel: " .. tostring(info.DisplayName), Theme.Cash)
			end)
			UI.Button({
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.new(0.13, -4, 0, 38),
				Text = "Zusehen",
				Color = Theme.Purple,
				MaxText = 15,
				Parent = card,
			}, function()
				spectate(Players:GetPlayerByUserId(tonumber(info.UserId) or 0))
			end)
		end
	end
	UI.Button({
		Size = UDim2.new(1, 0, 0, 40),
		Text = "Spielerliste aktualisieren",
		Color = Theme.Blue,
		LayoutOrder = 11,
		MaxText = 18,
		Parent = playerPage,
	}, refreshPlayers)
	onTabOpen.Players = refreshPlayers

	UI.Section(playerPage, "Geld & Werte (Ziel)", 20)
	local amountBox = UI.TextBox({
		Size = UDim2.new(1, 0, 0, 38),
		PlaceholderText = "Betrag (z.B. 1000000)",
		LayoutOrder = 21,
		Parent = playerPage,
	})
	gridButtons(playerPage, 22, 160, {
		{
			"+ Cash",
			Theme.Green,
			function()
				admin("GiveCash", { Target = target(), Amount = amountBox.Text })
			end,
		},
		{
			"Cash setzen",
			Theme.Green,
			function()
				admin("SetCash", { Target = target(), Amount = amountBox.Text })
			end,
		},
		{
			"Rebirths setzen",
			Theme.Red,
			function()
				admin("SetRebirths", { Target = target(), Amount = amountBox.Text })
			end,
		},
		{
			"Schritte setzen",
			Theme.Blue,
			function()
				admin("SetSteps", { Target = target(), Amount = amountBox.Text })
			end,
		},
	})

	-- Geschenke: an das Ziel oder an ALLE
	UI.Section(playerPage, "Geschenke", 30)
	local giftAll = false
	local giftRow = UI.Row(playerPage, 31, 40)
	toggleButton(
		giftRow,
		1,
		UDim2.new(1, 0, 1, 0),
		"Empfänger: Ziel (klicken für ALLE)",
		"Empfänger: ALLE",
		Theme.Gold,
		function(value)
			giftAll = value
		end
	)
	local function giftTarget(): string
		return if giftAll then "all" else target()
	end
	local giftCountRow = UI.Row(playerPage, 32, 40)
	local spinBox = UI.TextBox({
		Size = UDim2.new(0.3, -3, 1, 0),
		PlaceholderText = "Drehs (1-1000)",
		Text = "5",
		LayoutOrder = 1,
		Parent = giftCountRow,
	})
	UI.Button({
		Size = UDim2.new(0.35, -3, 1, 0),
		Text = "Drehs schenken",
		Color = Color3.fromRGB(255, 110, 190),
		LayoutOrder = 2,
		MaxText = 16,
		Parent = giftCountRow,
	}, function()
		local amount = math.clamp(math.floor(tonumber(spinBox.Text) or 5), 1, 1000)
		spinBox.Text = tostring(amount)
		admin("GiveSpins", { Target = giftTarget(), Amount = amount })
	end)
	UI.Button({
		Size = UDim2.new(0.35, -3, 1, 0),
		Text = "Cash schenken (Betrag oben)",
		Color = Theme.Green,
		LayoutOrder = 3,
		MaxText = 16,
		Parent = giftCountRow,
	}, function()
		admin("GiveCash", { Target = giftTarget(), Amount = amountBox.Text })
	end)
	UI.Label({
		Size = UDim2.new(1, 0, 0, 20),
		Text = "Ei einer Seltenheit:",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.SubText,
		LayoutOrder = 33,
		MaxText = 15,
		Parent = playerPage,
	})
	local eggGrid = UI.Grid(playerPage, 34, 100, 36)
	for i, rarity in ipairs(Config.Rarities) do
		UI.Button({
			Text = rarity.Name,
			Color = darker(rarity.Color, 0.3),
			LayoutOrder = i,
			MaxText = 14,
			StrokeSize = 2,
			Parent = eggGrid,
		}, function()
			admin("GiveEgg", { Target = giftTarget(), Rarity = rarity.Name })
		end)
	end
	UI.Label({
		Size = UDim2.new(1, 0, 0, 20),
		Text = "Gadget (für immer) und Gamepass (bis Server-Wechsel):",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.SubText,
		LayoutOrder = 35,
		MaxText = 15,
		Parent = playerPage,
	})
	local giftGrid = UI.Grid(playerPage, 36, 160, 40)
	local order = 0
	for _, gadget in ipairs(Config.Gadgets or {}) do
		order += 1
		UI.Button({
			Text = tostring(gadget.Name),
			Color = Theme.Orange,
			LayoutOrder = order,
			MaxText = 14,
			Wrap = true,
			StrokeSize = 2,
			Parent = giftGrid,
		}, function()
			admin("GiveGadget", { Target = giftTarget(), GadgetId = gadget.Id })
		end)
	end
	for _, pass in ipairs(Config.GamePasses) do
		order += 1
		UI.Button({
			Text = tostring(pass.Name),
			Color = Theme.PanelLight,
			LayoutOrder = order,
			MaxText = 13,
			Wrap = true,
			StrokeSize = 2,
			Parent = giftGrid,
		}, function()
			admin("GivePass", { Target = giftTarget(), PassKey = pass.Key })
		end)
	end

	-- Moderation
	UI.Section(playerPage, "Moderation (Ziel)", 40)
	local modRow = UI.Row(playerPage, 41, 38)
	local reasonBox = UI.TextBox({
		Size = UDim2.new(0.7, -3, 1, 0),
		PlaceholderText = "Grund / Warnungstext",
		LayoutOrder = 1,
		Parent = modRow,
	})
	local daysBox = UI.TextBox({
		Size = UDim2.new(0.3, -3, 1, 0),
		PlaceholderText = "Tage (0=immer)",
		LayoutOrder = 2,
		Parent = modRow,
	})
	local modActions = {
		{ "Warnung zeigen", "Warn", Theme.Orange, false },
		{ "Kick", "Kick", Theme.Red, false },
		{ "Bann", "Ban", Theme.Red, true },
		{ "Entbannen (UserId)", "Unban", Theme.Green, false },
		{ "Base leeren", "ClearBase", Theme.Orange, true },
		{ "Daten Reset", "ResetData", Theme.Red, true },
		{ "TP zu Ziel", "TeleportTo", Theme.Blue, false },
		{ "Ziel holen", "Bring", Theme.Blue, false },
		{ "Boden leeren", "ClearGround", Theme.Gray, false },
	}
	local modList = {}
	for _, info in ipairs(modActions) do
		table.insert(modList, {
			info[1],
			info[3],
			function()
				local action = info[2]
				if info[4] and needsConfirm(action, info[1]) then
					return
				end
				admin(action, {
					Target = target(),
					Reason = reasonBox.Text,
					Text = reasonBox.Text,
					Days = daysBox.Text,
				})
			end,
		})
	end
	gridButtons(playerPage, 42, 160, modList)
	UI.Section(playerPage, "Spaß mit dem Ziel", 50)
	gridButtons(playerPage, 51, 160, {
		{
			"Einfrieren",
			Color3.fromRGB(80, 170, 220),
			function()
				admin("Freeze", { Target = target(), Enabled = true })
			end,
		},
		{
			"Auftauen",
			Theme.Orange,
			function()
				admin("Freeze", { Target = target(), Enabled = false })
			end,
		},
		{
			"RIESIG",
			Theme.Green,
			function()
				admin("Size", { Target = target(), Scale = 3 })
			end,
		},
		{
			"MINI",
			Theme.Green,
			function()
				admin("Size", { Target = target(), Scale = 0.5 })
			end,
		},
		{
			"Normal groß",
			Theme.Gray,
			function()
				admin("Size", { Target = target(), Scale = 1 })
			end,
		},
		{
			"Unsichtbar",
			Color3.fromRGB(110, 110, 140),
			function()
				admin("Invisible", { Target = target(), Enabled = true })
			end,
		},
		{
			"Sichtbar",
			Theme.Gray,
			function()
				admin("Invisible", { Target = target(), Enabled = false })
			end,
		},
	})

	-- =================================================================
	-- REITER: KRÄFTE (nur für dich selbst)
	-- =================================================================
	local powerPage = pages.Powers
	UI.Section(powerPage, "Kräfte (nur für dich)", 10)
	local powerRow = UI.Row(powerPage, 11, 44)
	UI.Button({
		Size = UDim2.new(1 / 3, -4, 1, 0),
		Text = "Fliegen (G)",
		Color = Theme.Blue,
		LayoutOrder = 1,
		MaxText = 16,
		Parent = powerRow,
	}, function()
		ctx.Fly.Toggle()
	end)
	local _, showGod = toggleButton(
		powerRow,
		2,
		UDim2.new(1 / 3, -4, 1, 0),
		"Gott-Modus: aus",
		"Gott-Modus: AN",
		Theme.Gold,
		function(value)
			admin("SetPower", { Power = "God", Enabled = value })
		end
	)
	local _, showNoclip = toggleButton(
		powerRow,
		3,
		UDim2.new(1 / 3, -4, 1, 0),
		"Noclip: aus",
		"Noclip: AN",
		Theme.Green,
		function(value)
			admin("SetPower", { Power = "Noclip", Enabled = value })
		end
	)
	-- Anzeige folgt dem echten Zustand vom Server
	player:GetAttributeChangedSignal("AdminGod"):Connect(function()
		showGod(player:GetAttribute("AdminGod") == true)
	end)
	player:GetAttributeChangedSignal("AdminNoclip"):Connect(function()
		showNoclip(player:GetAttribute("AdminNoclip") == true)
	end)
	UI.Label({
		Size = UDim2.new(1, 0, 0, 36),
		Text = "Gott-Modus: dich kann niemand schlagen, aus deiner Base kann niemand klauen, Fallen wirken nicht.",
		TextColor3 = Theme.SubText,
		Font = Enum.Font.GothamBold,
		TextWrapped = true,
		LayoutOrder = 12,
		MaxText = 14,
		Parent = powerPage,
	})
	local speedSlider = slider(powerPage, 20, "Tempo", powers.MinSpeed or 8, powers.MaxSpeed or 250, 16, function(value)
		admin("SetSpeed", { Value = value })
	end)
	local jumpSlider = slider(
		powerPage,
		21,
		"Sprung",
		powers.MinJump or 20,
		powers.MaxJump or 300,
		powers.DefaultJump or 50,
		function(value)
			admin("SetJump", { Value = value })
		end
	)
	gridButtons(powerPage, 22, 214, {
		{
			"Tempo normal",
			Theme.Gray,
			function()
				speedSlider.Set(16)
				admin("SetSpeed", { Value = 0 })
			end,
		},
		{
			"Sprung normal",
			Theme.Gray,
			function()
				jumpSlider.Set(powers.DefaultJump or 50)
				admin("SetJump", { Value = 0 })
			end,
		},
	})

	-- Zuschauen (nur Kamera, lokal)
	UI.Section(powerPage, "Zuschauen", 30)
	UI.Label({
		Size = UDim2.new(1, 0, 0, 22),
		Text = 'Im Reiter Spieler auf "Zusehen" klicken. Taste X beendet.',
		TextColor3 = Theme.SubText,
		Font = Enum.Font.GothamBold,
		LayoutOrder = 31,
		MaxText = 14,
		Parent = powerPage,
	})
	local spectateHint = UI.Label({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.fromOffset(460, 40),
		BackgroundTransparency = 0.25,
		BackgroundColor3 = Theme.PanelDark,
		Text = "",
		Visible = false,
		MaxText = 20,
		Outline = 2,
		ZIndex = 15,
		Parent = ctx.Gui,
	})
	UI.Corner(10).Parent = spectateHint
	local spectating: Player? = nil
	local spectateConns: { RBXScriptConnection } = {}
	local function stopSpectate()
		for _, conn in ipairs(spectateConns) do
			conn:Disconnect()
		end
		table.clear(spectateConns)
		local wasSpectating = spectating ~= nil
		spectating = nil
		spectateHint.Visible = false
		local camera = workspace.CurrentCamera
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if camera and humanoid and wasSpectating then
			camera.CameraSubject = humanoid
		end
	end
	spectate = function(targetPlayer: Player?)
		stopSpectate()
		if not targetPlayer or targetPlayer == player then
			setStatus("Spieler nicht gefunden", Theme.Red)
			return
		end
		local function follow()
			local camera = workspace.CurrentCamera
			local humanoid = targetPlayer.Character and targetPlayer.Character:FindFirstChildOfClass("Humanoid")
			if camera and humanoid then
				camera.CameraSubject = humanoid
			end
		end
		spectating = targetPlayer
		follow()
		table.insert(
			spectateConns,
			targetPlayer.CharacterAdded:Connect(function(character)
				character:WaitForChild("Humanoid", 10)
				if spectating == targetPlayer then
					follow()
				end
			end)
		)
		table.insert(
			spectateConns,
			Players.PlayerRemoving:Connect(function(leaving)
				if leaving == targetPlayer then
					stopSpectate()
				end
			end)
		)
		spectateHint.Text = "Zuschauen: " .. targetPlayer.DisplayName .. "  –  Taste X beendet"
		spectateHint.Visible = true
		UI.CloseWindow(win)
	end
	UI.Button({
		Size = UDim2.new(1, 0, 0, 40),
		Text = "Zuschauen beenden",
		Color = Theme.Gray,
		LayoutOrder = 32,
		MaxText = 16,
		Parent = powerPage,
	}, stopSpectate)

	-- Foto-Modus (für Thumbnails)
	UI.Section(powerPage, "Foto-Modus", 40)
	gridButtons(powerPage, 41, 160, {
		{
			"UI aus/an (H)",
			Theme.Blue,
			function()
				ctx.PhotoMode.Toggle()
			end,
		},
		{
			"Showcase-Reihe",
			Theme.Purple,
			function()
				admin("Showcase")
			end,
		},
		{
			"Foto-Base",
			Theme.Green,
			function()
				admin("PhotoBase")
			end,
		},
		{
			"Foto aufräumen",
			Theme.Gray,
			function()
				admin("PhotoClear")
			end,
		},
	})

	-- =================================================================
	-- REITER: SERVER
	-- =================================================================
	local serverPage = pages.Server
	UI.Section(serverPage, "Server-Info", 10)
	local infoCard = UI.Card({ Size = UDim2.new(1, 0, 0, 104), LayoutOrder = 11, Parent = serverPage })
	local infoLabel = UI.Label({
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 1, -16),
		Text = "...",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Font = Enum.Font.GothamBold,
		MaxText = 17,
		Parent = infoCard,
	})
	local showLocked: (boolean) -> ()
	local function refreshInfo()
		local result = admin("ServerInfo")
		local data = result and result.Data
		if type(data) ~= "table" then
			return
		end
		local events = if type(data.Events) == "table" and #data.Events > 0
			then table.concat(data.Events, ", ")
			else "keine"
		infoLabel.Text = ("Spieler: %d / %d\nLaufzeit: %s\nEvents: %s\nPing (Schnitt): %s   •   Server: %s"):format(
			tonumber(data.Players) or 0,
			tonumber(data.MaxPlayers) or 0,
			Util.FormatTime(tonumber(data.Uptime) or 0),
			events,
			if tonumber(data.Ping) then (tostring(data.Ping) .. " ms") else "?",
			if data.Locked then "GESPERRT" else "offen"
		)
		showLocked(data.Locked == true)
	end
	UI.Button({
		Size = UDim2.new(1, 0, 0, 40),
		Text = "Aktualisieren",
		Color = Theme.Blue,
		LayoutOrder = 12,
		MaxText = 16,
		Parent = serverPage,
	}, refreshInfo)
	onTabOpen.Server = refreshInfo

	UI.Section(serverPage, "Zugang", 20)
	local accessRow = UI.Row(serverPage, 21, 44)
	local lockButton: UI.Button
	local locked = false
	showLocked = function(value: boolean)
		locked = value
		lockButton.SetText(if value then "Server entsperren" else "Server sperren")
		lockButton.SetColor(if value then Theme.Green else Theme.Orange)
	end
	lockButton = UI.Button({
		Size = UDim2.new(0.5, -3, 1, 0),
		Text = "Server sperren",
		Color = Theme.Orange,
		LayoutOrder = 1,
		MaxText = 16,
		Parent = accessRow,
	}, function()
		if not locked and needsConfirm("LockServer", "Server sperren") then
			return
		end
		local result = admin("LockServer", { Enabled = not locked })
		if result and result.Ok then
			showLocked(not locked)
		end
	end)
	UI.Button({
		Size = UDim2.new(0.5, -3, 1, 0),
		Text = "Alle kicken (außer Admins)",
		Color = Theme.Red,
		LayoutOrder = 2,
		MaxText = 16,
		Parent = accessRow,
	}, function()
		if needsConfirm("KickAll", "Alle kicken") then
			return
		end
		admin("KickAll", { Reason = reasonBox.Text })
	end)

	UI.Section(serverPage, "Banns", 30)
	local banList = listFrame(serverPage, 33)
	local function showBans(result: any)
		clearChildren(banList, "Frame")
		if not result or type(result.Data) ~= "table" then
			return
		end
		for i, info in ipairs(result.Data) do
			local card = UI.Card({ Size = UDim2.new(1, 0, 0, 48), LayoutOrder = i, Parent = banList })
			local days = tonumber(info.Days) or 0
			UI.Label({
				Position = UDim2.fromOffset(10, 4),
				Size = UDim2.new(0.72, -10, 1, -8),
				Text = ("%s (%s) – %s\n%s  •  %s"):format(
					tostring(info.Name),
					tostring(info.UserId),
					if info.Active then "gebannt" else "nicht (mehr) gebannt",
					if days > 0 then (("%.1f Tage"):format(days)) else "für immer",
					tostring(info.Reason or "")
				),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				Font = Enum.Font.GothamBold,
				MaxText = 14,
				Parent = card,
			})
			if info.Active then
				UI.Button({
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -8, 0.5, 0),
					Size = UDim2.new(0.25, -8, 0, 36),
					Text = "Entbannen",
					Color = Theme.Green,
					MaxText = 15,
					Parent = card,
				}, function()
					local unban = admin("Unban", { Target = tostring(info.UserId) })
					if unban and unban.Ok then
						showBans(admin("BanList"))
					end
				end)
			end
		end
	end
	local banRow = UI.Row(serverPage, 31, 42)
	UI.Button({
		Size = UDim2.new(0.5, -3, 1, 0),
		Text = "Banns dieser Sitzung",
		Color = Theme.Blue,
		LayoutOrder = 1,
		MaxText = 16,
		Parent = banRow,
	}, function()
		showBans(admin("BanList"))
	end)
	UI.Button({
		Size = UDim2.new(0.5, -3, 1, 0),
		Text = "Bann-Verlauf vom Ziel (UserId)",
		Color = Theme.Purple,
		LayoutOrder = 2,
		MaxText = 16,
		Parent = banRow,
	}, function()
		showBans(admin("BanHistory", { Target = target() }))
	end)

	-- =================================================================
	-- NOCLIP (lokal, nur solange der Server AdminNoclip gesetzt hat)
	-- Der Humanoid steht weiter auf dem Boden (er sucht ihn per Strahl), läuft aber durch Wände.
	-- =================================================================
	local noclipParts: { [BasePart]: boolean } = {}
	local noclipConn: RBXScriptConnection? = nil
	local function restoreCollisions()
		for part in pairs(noclipParts) do
			if part.Parent then
				part.CanCollide = true
			end
		end
		table.clear(noclipParts)
	end
	local function updateNoclip()
		local enabled = player:GetAttribute("AdminNoclip") == true
		if enabled and not noclipConn then
			noclipConn = RunService.Stepped:Connect(function()
				local character = player.Character
				if not character then
					return
				end
				for _, part in ipairs(character:GetDescendants()) do
					if part:IsA("BasePart") and part.CanCollide then
						noclipParts[part] = true
						part.CanCollide = false
					end
				end
			end)
		elseif not enabled and noclipConn then
			noclipConn:Disconnect()
			noclipConn = nil
			restoreCollisions()
		end
	end
	player:GetAttributeChangedSignal("AdminNoclip"):Connect(updateNoclip)
	updateNoclip()

	-- Öffnen: Knopf rechts + Taste P, Zuschauen beenden: Taste X
	ctx.Hud.AddRightButton("🛠️", "Admin", Theme.Red, 99, function()
		UI.ToggleWindow(win)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.P then
			UI.ToggleWindow(win)
		elseif input.KeyCode == SPECTATE_KEY and spectating then
			stopSpectate()
		end
	end)
	selectTab(currentTab)
	ctx.Toast("Admin-Panel: Taste P  •  Fliegen: G  •  Foto: H", "Info")
end

return AdminPanel
