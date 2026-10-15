-- Admin panel (only shown to admins; the server checks every request again).
-- Pick a player and an animal on the left, then use the actions on the right.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Animals = require(Shared.Config.Animals)
local Upgrades = require(Shared.Config.Upgrades)
local Monetization = require(Shared.Config.Monetization)
local Game = require(Shared.Config.Game)

local Kit = require(script.Parent.Kit)
local Windows = require(script.Parent.Windows)
local Feed = require(script.Parent.Feed)
local State = require(script.Parent.Parent.State)

local AdminWindow = {}

local targetUserId = Players.LocalPlayer.UserId
local species = Animals.List[#Animals.List].Id
local mutation = 1
local aura = 1
local upgradeId = "Cash"
local playerList
local speciesLabel
local targetLabel

local function admin(action, ...)
	local ok, msg = State.action("Admin", action, ...)
	Feed.notify(msg or (ok and "Done" or "Failed"), ok and "success" or "error")
end

local function box(parent, placeholder: string, width: number, order: number)
	local b = Kit.new("TextBox", {
		Size = UDim2.fromOffset(width, 38),
		BackgroundColor3 = Kit.Colors.PanelDark,
		PlaceholderText = placeholder,
		PlaceholderColor3 = Color3.fromRGB(150, 150, 170),
		Text = "",
		TextColor3 = Kit.Colors.White,
		Font = Kit.Font,
		TextSize = 18,
		ClearTextOnFocus = false,
		LayoutOrder = order,
		Parent = parent,
	})
	Kit.corner(b, 8)
	Kit.stroke(b, 2, nil, Enum.ApplyStrokeMode.Border)
	return b
end

local function parseNumber(text: string): number?
	text = text:gsub("[%s,]", ""):upper()
	local suffixes = { K = 1e3, M = 1e6, B = 1e9, T = 1e12, QA = 1e15, QI = 1e18 }
	local num, suffix = text:match("^(-?[%d%.]+)(%a*)$")
	local n = tonumber(num or "")
	if not n then
		return nil
	end
	if suffix and suffix ~= "" then
		local m = suffixes[suffix]
		if not m then
			return nil
		end
		n *= m
	end
	return n
end

local function row(parent, order: number, title: string)
	local frame = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -10, 0, 42), LayoutOrder = order, Parent = parent })
	Kit.list(frame, 6, true)
	Kit.label({ Text = title, Size = UDim2.fromOffset(110, 38), XAlign = Enum.TextXAlignment.Left, Order = 0, Parent = frame, MaxTextSize = 18 })
	return frame
end

local function small(parent, text: string, order: number, color: Color3?, onClick)
	return Kit.button({ Text = text, Size = UDim2.fromOffset(text:len() > 6 and 120 or 80, 36), Order = order, Color = color or Kit.Colors.Blue, Parent = parent, MaxTextSize = 18 }, onClick)
end

local function refreshPlayers()
	if not playerList then
		return
	end
	for _, child in ipairs(playerList:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for i, p in ipairs(Players:GetPlayers()) do
		Kit.button({ Text = p.DisplayName, Size = UDim2.new(1, -8, 0, 34), Order = i, Color = p.UserId == targetUserId and Kit.Colors.Green or Kit.Colors.Gray, Parent = playerList, MaxTextSize = 18 }, function()
			targetUserId = p.UserId
			targetLabel.Text = "Target: " .. p.DisplayName
			refreshPlayers()
		end)
	end
end

function AdminWindow.init()
	local window = Windows.create("Admin", "Admin Panel", Vector2.new(900, 520), Kit.Colors.Yellow)
	local content = window.Content

	-- left: players and animals
	local left = Kit.panel({ Size = UDim2.new(0, 230, 1, 0), Color = Kit.Colors.PanelDark, Parent = content })
	targetLabel = Kit.label({ Text = "Target: " .. Players.LocalPlayer.DisplayName, Size = UDim2.new(1, -10, 0, 26), Position = UDim2.fromOffset(5, 4), Parent = left })
	playerList = Windows.scroll(left, UDim2.new(1, -6, 0, 150), UDim2.fromOffset(3, 32))
	Kit.list(playerList, 4)
	speciesLabel = Kit.label({ Text = "Animal: " .. species, Size = UDim2.new(1, -10, 0, 26), Position = UDim2.fromOffset(5, 188), Parent = left })
	local speciesList = Windows.scroll(left, UDim2.new(1, -6, 1, -222), UDim2.fromOffset(3, 218))
	Kit.list(speciesList, 4)
	for i, def in ipairs(Animals.List) do
		local b = Kit.new("TextButton", {
			Size = UDim2.new(1, -8, 0, 28),
			BackgroundColor3 = Game.Rarities[def.Rarity].Color,
			Text = def.Id,
			Font = Kit.Font,
			TextSize = 16,
			TextColor3 = Color3.new(1, 1, 1),
			LayoutOrder = i,
			Parent = speciesList,
		})
		Kit.corner(b, 6)
		Kit.new("UIStroke", { Thickness = 1.5, Parent = b })
		b.Activated:Connect(function()
			species = def.Id
			speciesLabel.Text = "Animal: " .. def.Id
		end)
	end

	-- right: actions
	local right = Windows.scroll(content, UDim2.new(1, -240, 1, 0), UDim2.fromOffset(240, 0))
	Kit.list(right, 6)
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	local r = row(right, nextOrder(), "Cash")
	local cashBox = box(r, "e.g. 1.5B", 160, 1)
	small(r, "Give", 2, Kit.Colors.Green, function()
		local n = parseNumber(cashBox.Text)
		if n then
			admin("GiveCash", targetUserId, n)
		end
	end)

	r = row(right, nextOrder(), "Speed")
	local speedBox = box(r, "e.g. 10B", 160, 1)
	small(r, "Give", 2, Kit.Colors.Green, function()
		local n = parseNumber(speedBox.Text)
		if n then
			admin("GiveSpeed", targetUserId, n)
		end
	end)

	r = row(right, nextOrder(), "Animal")
	local mutLabel
	mutLabel = small(r, "Normal", 1, Kit.Colors.Gray, function()
		mutation = mutation % #Game.Mutations + 1
		mutLabel.setText(Game.Mutations[mutation].Name)
	end)
	local auraLabel
	auraLabel = small(r, "No aura", 2, Kit.Colors.Gray, function()
		aura = aura % #Game.Auras + 1
		auraLabel.setText(aura == 1 and "No aura" or Game.Auras[aura].Name)
	end)
	small(r, "Give", 3, Kit.Colors.Green, function()
		admin("GiveAnimal", targetUserId, species, mutation, aura)
	end)

	r = row(right, nextOrder(), "Spawn")
	small(r, "Spawn Egg", 1, Kit.Colors.Orange, function()
		admin("SpawnEgg", species)
	end)
	small(r, "Spawn Animal", 2, Kit.Colors.Orange, function()
		admin("SpawnAnimal", species)
	end)

	r = row(right, nextOrder(), "Upgrade")
	local upLabel
	upLabel = small(r, upgradeId, 1, Kit.Colors.Gray, function()
		local idx = 1
		for i, def in ipairs(Upgrades.List) do
			if def.Id == upgradeId then
				idx = i
			end
		end
		upgradeId = Upgrades.List[idx % #Upgrades.List + 1].Id
		upLabel.setText(upgradeId)
	end)
	local levelBox = box(r, "level", 90, 2)
	small(r, "Set", 3, Kit.Colors.Green, function()
		local n = tonumber(levelBox.Text)
		if n then
			admin("SetUpgrade", targetUserId, upgradeId, n)
		end
	end)

	r = row(right, nextOrder(), "Rebirths")
	local rbBox = box(r, "amount", 90, 1)
	small(r, "Set", 2, Kit.Colors.Green, function()
		local n = tonumber(rbBox.Text)
		if n then
			admin("SetRebirths", targetUserId, n)
		end
	end)
	small(r, "+10 Bait", 3, Kit.Colors.Blue, function()
		admin("GiveBait", targetUserId, 10)
	end)

	r = row(right, nextOrder(), "Boosts")
	for i, boost in ipairs(Game.BoostTypes) do
		small(r, "x2 " .. boost, i, Kit.Colors.Purple, function()
			admin("Boost", targetUserId, boost, 15)
		end)
	end

	r = row(right, nextOrder(), "Passes")
	for i, pass in ipairs(Monetization.GamePasses) do
		if i == 4 then
			r = row(right, nextOrder(), "")
		end
		small(r, pass.Key, i, Kit.Colors.Pink, function()
			local owned = State.ready() and targetUserId == Players.LocalPlayer.UserId and State.Derived.Passes[pass.Key]
			admin("SetPass", targetUserId, pass.Key, not owned)
		end)
	end

	r = row(right, nextOrder(), "Events")
	small(r, "Open Lair", 1, Kit.Colors.Orange, function()
		admin("OpenLair")
	end)
	small(r, "Close Lair", 2, Kit.Colors.Gray, function()
		admin("CloseLair")
	end)
	small(r, "Server Luck", 3, Kit.Colors.Green, function()
		admin("ServerLuck", 10)
	end)

	r = row(right, nextOrder(), "Message")
	local msgBox = box(r, "message to everyone", 330, 1)
	small(r, "Send", 2, Kit.Colors.Green, function()
		if msgBox.Text ~= "" then
			admin("Broadcast", msgBox.Text)
			msgBox.Text = ""
		end
	end)

	r = row(right, nextOrder(), "Player")
	small(r, "Teleport", 1, Kit.Colors.Blue, function()
		admin("TeleportTo", targetUserId)
	end)
	small(r, "Kick", 2, Kit.Colors.Red, function()
		admin("Kick", targetUserId, "Kicked by an admin")
	end)
	local armed = false
	local reset
	reset = small(r, "Reset Data", 3, Kit.Colors.RedDark, function()
		if not armed then
			armed = true
			reset.setText("Sure?")
			task.delay(3, function()
				armed = false
				reset.setText("Reset Data")
			end)
			return
		end
		armed = false
		reset.setText("Reset Data")
		admin("ResetData", targetUserId)
	end)

	window.OnOpen = refreshPlayers
	Players.PlayerAdded:Connect(refreshPlayers)
	Players.PlayerRemoving:Connect(function()
		task.defer(refreshPlayers)
	end)
	-- F2 opens the panel for admins
	game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.F2 and State.ready() and State.Derived.IsAdmin then
			Windows.open("Admin")
		end
	end)
end

return AdminWindow
