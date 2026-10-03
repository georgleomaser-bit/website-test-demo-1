-- =====================================================================
--  ADMIN-PANEL (wird nur gebaut, wenn der Server dich als Admin markiert;
--  JEDE Aktion wird zusätzlich auf dem Server geprüft – Exploiter haben keine Chance)
--  Öffnen: Knopf "🛠️ Admin" rechts oder Taste P
-- =====================================================================

local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent:WaitForChild("UI"))

local AdminPanel = {}

local Theme = UI.Theme
local built = false

local function darker(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

function AdminPanel.Build(ctx: any)
	if built then
		return
	end
	built = true
	local Config = ctx.Config
	local Util = ctx.Util
	local Remotes = ctx.Remotes

	local win = UI.Window("🛠️ ADMIN-PANEL", 700, 580, Theme.Red)
	local content = win.Content
	local status = UI.Label({
		Size = UDim2.new(1, 0, 0, 26),
		Text = "Bereit.",
		TextColor3 = Theme.SubText,
		Font = Enum.Font.GothamBold,
		LayoutOrder = 0,
		MaxText = 16,
		Parent = content,
	})

	local function admin(action: string, args: { [string]: any }?): any
		local ok, result = pcall(function()
			return Remotes.Admin:InvokeServer(action, args or {})
		end)
		if ok and type(result) == "table" then
			status.Text = (if result.Ok then "✅ " else "❌ ") .. tostring(result.Message)
			status.TextColor3 = if result.Ok then Theme.Cash else Theme.Red
			return result
		end
		status.Text = "❌ Keine Antwort vom Server"
		status.TextColor3 = Theme.Red
		return nil
	end

	-- -----------------------------------------------------------------
	-- Ziel-Spieler
	-- -----------------------------------------------------------------
	UI.Section(content, "🎯 Ziel-Spieler (me / all / others / Name / UserId)", 100)
	local targetRow = UI.Row(content, 200, 40)
	local targetBox = UI.TextBox({
		Size = UDim2.new(0.55, 0, 1, 0),
		Text = "me",
		PlaceholderText = "me",
		LayoutOrder = 1,
		Parent = targetRow,
	})
	local playerList: ScrollingFrame = UI.Create("ScrollingFrame", {
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundTransparency = 1,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.X,
		LayoutOrder = 300,
		Parent = content,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
		UI.Create("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3) }),
	})
	local function refreshPlayers()
		local result = admin("GetPlayers")
		for _, child in ipairs(playerList:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		if result and type(result.Data) == "table" then
			for _, info in ipairs(result.Data) do
				UI.Button({
					Size = UDim2.fromOffset(160, 38),
					Text = tostring(info.DisplayName) .. " (" .. Util.FormatCash(tonumber(info.Cash) or 0) .. ")",
					Color = Theme.PanelLight,
					MaxText = 14,
					StrokeSize = 2,
					Parent = playerList,
				}, function()
					targetBox.Text = tostring(info.Name)
				end)
			end
		end
	end
	UI.Button({
		Size = UDim2.new(0.42, 0, 1, 0),
		Text = "🔄 Spieler laden",
		Color = Theme.Blue,
		LayoutOrder = 2,
		MaxText = 18,
		Parent = targetRow,
	}, refreshPlayers)

	-- -----------------------------------------------------------------
	-- 👑 ADMIN-METEORE (die krassesten – spawnen nie von allein)
	-- -----------------------------------------------------------------
	UI.Section(content, "👑 Admin-Meteore (die krassesten!)", 400, Color3.fromRGB(255, 80, 80))
	local adminMeteors = {}
	for _, def in ipairs(Config.Meteors) do
		if def.Rarity == "Admin" then
			table.insert(adminMeteors, def)
		end
	end
	if #adminMeteors == 0 then
		UI.Label({
			Size = UDim2.new(1, 0, 0, 24),
			Text = "(Noch keine Admin-Meteore in der Config)",
			Font = Enum.Font.GothamBold,
			TextColor3 = Theme.SubText,
			LayoutOrder = 500,
			MaxText = 15,
			Parent = content,
		})
	end
	for i, def in ipairs(adminMeteors) do
		local card = UI.Card({ Size = UDim2.new(1, 0, 0, 56), LayoutOrder = 500 + i, Parent = content })
		local nameColor: Color3 = if typeof(def.Color) == "Color3" then def.Color else Color3.fromRGB(255, 40, 40)
		local nameLabel = UI.Label({
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(0.38, -12, 1, -12),
			Text = "👑 " .. tostring(def.Name),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = nameColor:Lerp(Color3.new(1, 1, 1), 0.3),
			MaxText = 20,
			Outline = 2,
			Parent = card,
		})
		if def.Effects and def.Effects.Rainbow then
			nameLabel.TextColor3 = Color3.new(1, 1, 1)
			local keys = {}
			for k = 0, 6 do
				table.insert(keys, ColorSequenceKeypoint.new(k / 6, Color3.fromHSV(k / 6, 0.8, 1)))
			end
			UI.Create("UIGradient", { Color = ColorSequence.new(keys), Parent = nameLabel })
		end
		UI.Button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(0.69, -4, 0.5, 0),
			Size = UDim2.new(0.31, -6, 0, 40),
			Text = "🎁 Gratis in die Mitte",
			Color = Theme.Green,
			MaxText = 16,
			Parent = card,
		}, function()
			admin("SpawnAdminMeteor", { MeteorId = def.Id, Where = "Free" })
		end)
		UI.Button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.new(0.31, -6, 0, 40),
			Text = "🏠 In meine Base",
			Color = Theme.Purple,
			MaxText = 16,
			Parent = card,
		}, function()
			admin("SpawnAdminMeteor", { MeteorId = def.Id, Where = "Base" })
		end)
	end
	local adminRainRow = UI.Row(content, 600, 46)
	local adminRainBox = UI.TextBox({
		Size = UDim2.new(0.3, -3, 1, 0),
		PlaceholderText = "Anzahl (1-8)",
		Text = "4",
		LayoutOrder = 1,
		Parent = adminRainRow,
	})
	UI.Button({
		Size = UDim2.new(0.7, -3, 1, 0),
		Text = "👑 Admin-Meteor-Regen",
		Color = Color3.fromRGB(220, 40, 60),
		LayoutOrder = 2,
		MaxText = 22,
		Parent = adminRainRow,
	}, function()
		local count = math.clamp(math.floor(tonumber(adminRainBox.Text) or 4), 1, 8)
		adminRainBox.Text = tostring(count)
		admin("AdminRain", { Count = count })
	end)

	-- -----------------------------------------------------------------
	-- Meteor spawnen / geben
	-- -----------------------------------------------------------------
	UI.Section(content, "☄️ Meteor spawnen / geben", 700)
	local selectedMeteor = Config.Meteors[1] and Config.Meteors[1].Id or ""
	local selectedMutation = "Normal"
	local selectedLabel = UI.Label({
		Size = UDim2.new(1, 0, 0, 24),
		Text = "",
		LayoutOrder = 800,
		MaxText = 18,
		Outline = 2,
		Parent = content,
	})
	local function updateSelected()
		local def = Config.MeteorsById[selectedMeteor]
		if not def then
			selectedLabel.Text = "Kein Meteor ausgewählt"
			return
		end
		local rarity = Config.RaritiesByName[def.Rarity]
		selectedLabel.Text = "Ausgewählt: " .. selectedMutation .. " " .. def.Name .. " (" .. def.Rarity .. ")"
		selectedLabel.TextColor3 = if rarity then rarity.Color else Theme.Text
	end
	local meteorGrid = UI.Grid(content, 900, 120, 42)
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
			updateSelected()
		end)
	end
	local mutRow = UI.Row(content, 1000, 38)
	for i, mut in ipairs(Config.Mutations) do
		UI.Button({
			Size = UDim2.new(1 / #Config.Mutations, -5, 1, 0),
			Text = mut.Name .. " x" .. mut.Mult,
			Color = darker(mut.Color or Theme.Gray, 0.25),
			LayoutOrder = i,
			MaxText = 16,
			Parent = mutRow,
		}, function()
			selectedMutation = mut.Name
			updateSelected()
		end)
	end
	updateSelected()
	local countRow = UI.Row(content, 1100, 38)
	local countBox = UI.TextBox({
		Size = UDim2.new(0.5, -3, 1, 0),
		PlaceholderText = "Anzahl (1-25)",
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
	local spawnRow = UI.Row(content, 1200, 44)
	local spawnActions = {
		{ "Aufs Förderband", Theme.Orange, { Where = "Belt" } },
		{ "Vor mir", Theme.Orange, { Where = "Me" } },
		{ "Gratis vor mir", Theme.Green, { Where = "Me", Free = true } },
		{ "🎁 Gratis-Zone", Theme.Green, { Where = "Free", Free = true } },
	}
	for i, info in ipairs(spawnActions) do
		UI.Button({
			Size = UDim2.new(0.2, -5, 1, 0),
			Text = info[1],
			Color = info[2],
			LayoutOrder = i,
			MaxText = 16,
			Parent = spawnRow,
		}, function()
			local extra = info[3]
			admin("SpawnMeteor", {
				MeteorId = selectedMeteor,
				Mutation = selectedMutation,
				Count = countBox.Text,
				Where = extra.Where,
				Free = extra.Free == true,
			})
		end)
	end
	UI.Button({
		Size = UDim2.new(0.2, -5, 1, 0),
		Text = "In Ziel-Base",
		Color = Theme.Purple,
		LayoutOrder = 5,
		MaxText = 16,
		Parent = spawnRow,
	}, function()
		admin("GiveMeteor", {
			MeteorId = selectedMeteor,
			Mutation = selectedMutation,
			Level = levelBox.Text,
			Target = targetBox.Text,
		})
	end)

	-- -----------------------------------------------------------------
	-- Meteorregen
	-- -----------------------------------------------------------------
	UI.Section(content, "🌧️ Meteorregen (Seltenheit wählen)", 1300)
	local rainGrid = UI.Grid(content, 1400, 100, 38)
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

	-- -----------------------------------------------------------------
	-- Geld & Werte
	-- -----------------------------------------------------------------
	UI.Section(content, "💰 Geld & Werte (für Ziel-Spieler)", 1500)
	local amountBox = UI.TextBox({
		Size = UDim2.new(1, 0, 0, 38),
		PlaceholderText = "Betrag (z.B. 1000000)",
		LayoutOrder = 1600,
		Parent = content,
	})
	local moneyRow = UI.Row(content, 1700, 44)
	local moneyActions = {
		{ "+ Cash", Theme.Green, "GiveCash" },
		{ "Cash setzen", Theme.Green, "SetCash" },
		{ "Rebirths setzen", Theme.Red, "SetRebirths" },
		{ "👟 Schritte setzen", Theme.Blue, "SetSteps" },
	}
	for i, info in ipairs(moneyActions) do
		UI.Button({
			Size = UDim2.new(0.25, -5, 1, 0),
			Text = info[1],
			Color = info[2],
			LayoutOrder = i,
			MaxText = 15,
			Parent = moneyRow,
		}, function()
			admin(info[3], { Target = targetBox.Text, Amount = amountBox.Text })
		end)
	end
	local passGridAdmin = UI.Grid(content, 1800, 120, 40)
	for i, pass in ipairs(Config.GamePasses) do
		local passName = tostring(pass.Name)
		if type(pass.Icon) == "string" and not passName:find(pass.Icon, 1, true) then
			passName = pass.Icon .. " " .. passName
		end
		UI.Button({
			Text = passName,
			Color = Theme.PanelLight,
			LayoutOrder = i,
			MaxText = 13,
			Wrap = true,
			StrokeSize = 2,
			Parent = passGridAdmin,
		}, function()
			admin("GivePass", { Target = targetBox.Text, PassKey = pass.Key })
		end)
	end

	-- -----------------------------------------------------------------
	-- Events
	-- -----------------------------------------------------------------
	UI.Section(content, "🎉 Events", 1900)
	local globalToggle = false
	local eventRow1 = UI.Row(content, 2000, 38)
	local multBox = UI.TextBox({
		Size = UDim2.new(0.33, -4, 1, 0),
		PlaceholderText = "Glück x",
		Text = "2",
		LayoutOrder = 1,
		Parent = eventRow1,
	})
	local minutesBox = UI.TextBox({
		Size = UDim2.new(0.33, -4, 1, 0),
		PlaceholderText = "Minuten",
		Text = "10",
		LayoutOrder = 2,
		Parent = eventRow1,
	})
	local globalButton: UI.Button
	globalButton = UI.Button({
		Size = UDim2.new(0.33, -4, 1, 0),
		Text = "Nur dieser Server",
		Color = Theme.Gray,
		LayoutOrder = 3,
		MaxText = 14,
		Parent = eventRow1,
	}, function()
		globalToggle = not globalToggle
		globalButton.SetText(if globalToggle then "🌍 ALLE Server" else "Nur dieser Server")
		globalButton.SetColor(if globalToggle then Theme.Purple else Theme.Gray)
	end)
	local eventRow2 = UI.Row(content, 2100, 44)
	UI.Button({
		Size = UDim2.new(0.5, -3, 1, 0),
		Text = "🍀 Glück starten",
		Color = Theme.Green,
		LayoutOrder = 1,
		MaxText = 18,
		Parent = eventRow2,
	}, function()
		admin("ServerLuck", { Mult = multBox.Text, Minutes = minutesBox.Text, Global = globalToggle })
	end)
	UI.Button({
		Size = UDim2.new(0.5, -3, 1, 0),
		Text = "🌠 Meteoritenschauer",
		Color = Theme.Orange,
		LayoutOrder = 2,
		MaxText = 18,
		Parent = eventRow2,
	}, function()
		admin("StartShower", { Seconds = (tonumber(minutesBox.Text) or 1) * 60, Global = globalToggle })
	end)
	local announceRow = UI.Row(content, 2200, 42)
	local announceBox = UI.TextBox({
		Size = UDim2.new(0.7, -3, 1, 0),
		PlaceholderText = "Nachricht an alle...",
		LayoutOrder = 1,
		Parent = announceRow,
	})
	UI.Button({
		Size = UDim2.new(0.3, -3, 1, 0),
		Text = "📢 Senden",
		Color = Theme.Blue,
		LayoutOrder = 2,
		MaxText = 18,
		Parent = announceRow,
	}, function()
		admin("Announce", { Text = announceBox.Text, Global = globalToggle })
	end)

	-- -----------------------------------------------------------------
	-- Moderation
	-- -----------------------------------------------------------------
	UI.Section(content, "🛡️ Moderation (Ziel oben)", 2300)
	local modRow = UI.Row(content, 2400, 38)
	local reasonBox =
		UI.TextBox({ Size = UDim2.new(0.7, -3, 1, 0), PlaceholderText = "Grund", LayoutOrder = 1, Parent = modRow })
	local daysBox = UI.TextBox({
		Size = UDim2.new(0.3, -3, 1, 0),
		PlaceholderText = "Tage (0=immer)",
		LayoutOrder = 2,
		Parent = modRow,
	})
	local modGrid = UI.Grid(content, 2500, 152, 40)
	local modActions = {
		{ "👢 Kick", "Kick", Theme.Red },
		{ "🔨 Bann", "Ban", Theme.Red },
		{ "♻️ Entbannen (UserId)", "Unban", Theme.Green },
		{ "🧹 Base leeren", "ClearBase", Theme.Orange },
		{ "💣 Daten Reset", "ResetData", Theme.Red },
		{ "➡️ TP zu Ziel", "TeleportTo", Theme.Blue },
		{ "⬅️ Ziel holen", "Bring", Theme.Blue },
		{ "🧽 Boden leeren", "ClearGround", Theme.Gray },
	}
	local confirmPending: string? = nil
	for i, info in ipairs(modActions) do
		UI.Button({ Text = info[1], Color = info[3], LayoutOrder = i, MaxText = 14, Parent = modGrid }, function()
			local action = info[2]
			-- gefährliche Aktionen brauchen einen zweiten Klick
			if (action == "Ban" or action == "ResetData") and confirmPending ~= action then
				confirmPending = action
				status.Text = "⚠️ Nochmal klicken zum Bestätigen: " .. info[1]
				status.TextColor3 = Theme.Orange
				return
			end
			confirmPending = nil
			admin(action, { Target = targetBox.Text, Reason = reasonBox.Text, Days = daysBox.Text })
		end)
	end

	-- -----------------------------------------------------------------
	-- Admin Abuse
	-- -----------------------------------------------------------------
	UI.Section(content, "😈 Admin Abuse", 2600)
	local abuseGrid = UI.Grid(content, 2700, 152, 42)
	local abuseActions = {
		{
			"🕊️ Fliegen an/aus (G)",
			Theme.Blue,
			function()
				ctx.Fly.Toggle()
			end,
		},
		{
			"🎉 ADMIN ABUSE EVENT",
			Color3.fromRGB(220, 40, 130),
			function()
				admin("AdminAbuse", { Global = globalToggle })
			end,
		},
		{
			"🌙 Mond-Schwerkraft",
			Theme.Purple,
			function()
				admin("Gravity", { Moon = true, Global = globalToggle })
			end,
		},
		{
			"🌍 Normale Schwerkraft",
			Theme.Gray,
			function()
				admin("Gravity", { Moon = false, Global = globalToggle })
			end,
		},
		{
			"🧊 Ziel einfrieren",
			Color3.fromRGB(80, 170, 220),
			function()
				admin("Freeze", { Target = targetBox.Text, Enabled = true })
			end,
		},
		{
			"🔥 Ziel auftauen",
			Theme.Orange,
			function()
				admin("Freeze", { Target = targetBox.Text, Enabled = false })
			end,
		},
		{
			"📏 Ziel RIESIG",
			Theme.Green,
			function()
				admin("Size", { Target = targetBox.Text, Scale = 3 })
			end,
		},
		{
			"🐜 Ziel MINI",
			Theme.Green,
			function()
				admin("Size", { Target = targetBox.Text, Scale = 0.5 })
			end,
		},
		{
			"📐 Ziel normal groß",
			Theme.Gray,
			function()
				admin("Size", { Target = targetBox.Text, Scale = 1 })
			end,
		},
		{
			"👻 Ziel unsichtbar",
			Color3.fromRGB(110, 110, 140),
			function()
				admin("Invisible", { Target = targetBox.Text, Enabled = true })
			end,
		},
		{
			"👀 Ziel sichtbar",
			Theme.Gray,
			function()
				admin("Invisible", { Target = targetBox.Text, Enabled = false })
			end,
		},
	}
	for i, info in ipairs(abuseActions) do
		UI.Button({ Text = info[1], Color = info[2], LayoutOrder = i, MaxText = 14, Parent = abuseGrid }, info[3])
	end

	-- -----------------------------------------------------------------
	-- Foto-Modus (für Thumbnails)
	-- -----------------------------------------------------------------
	UI.Section(content, "📸 Foto-Modus", 2800)
	local photoGrid = UI.Grid(content, 2900, 152, 42)
	local photoActions = {
		{
			"📸 UI aus/an (Taste H)",
			Theme.Blue,
			function()
				ctx.PhotoMode.Toggle()
			end,
		},
		{
			"✨ Showcase-Reihe",
			Theme.Purple,
			function()
				admin("Showcase")
			end,
		},
		{
			"🏠 Foto-Base (Aliens)",
			Theme.Green,
			function()
				admin("PhotoBase")
			end,
		},
		{
			"🧹 Foto aufräumen",
			Theme.Gray,
			function()
				admin("PhotoClear")
			end,
		},
	}
	for i, info in ipairs(photoActions) do
		UI.Button({ Text = info[1], Color = info[2], LayoutOrder = i, MaxText = 14, Parent = photoGrid }, info[3])
	end

	-- Öffnen: Knopf rechts + Taste P
	ctx.Hud.AddRightButton("🛠️", "Admin", Theme.Red, 4, function()
		UI.ToggleWindow(win)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.P and not UserInputService:GetFocusedTextBox() then
			UI.ToggleWindow(win)
		end
	end)
	ctx.Toast("🛠️ Admin-Panel: Taste P • Fliegen: Taste G • Foto: Taste H", "Info")
end

return AdminPanel
