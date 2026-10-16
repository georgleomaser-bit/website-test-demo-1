--[[
	Kleinere Fenster: 🛒 Shop, ⚙️ Optionen (mit Statistik), 🛠️ Test-Menü.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local State = require(script.Parent.Parent.State)
local Sound = require(script.Parent.Parent.Sound)
local Ui = require(script.Parent.Ui)
local Windows = require(script.Parent.Windows)

local MiscWindows = {}

function MiscWindows.ShopEnabled(): boolean
	for _, pass in pairs(Config.GamePasses) do
		if pass.Id ~= 0 then
			return true
		end
	end
	for _, product in pairs(Config.DevProducts) do
		if product.Id ~= 0 then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------
-- Shop
--------------------------------------------------------------------------
function MiscWindows.CreateShop()
	local window = Windows.Create("Shop", "🛒 Shop", Ui.Colors.Orange, Vector2.new(560, 440))
	local list = Windows.ScrollList(window.Content, { Size = UDim2.fromScale(1, 1) })
	local passButtons = {}
	local order = 0

	local function addRow(emoji: string, title: string, desc: string, buttonText: string, onClick: () -> ())
		order += 1
		local row = Ui.Frame(list, {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 70),
			BackgroundColor3 = order % 2 == 0 and Ui.Colors.RowAlt or Ui.Colors.Row,
			ZIndex = 11,
		})
		Ui.Corner(row, 10)
		Ui.Label(row, emoji, { Size = UDim2.fromOffset(60, 60), Position = UDim2.fromOffset(6, 5), TextSize = 40, ZIndex = 12 })
		Ui.Label(row, title, {
			Size = UDim2.new(1, -230, 0, 28),
			Position = UDim2.fromOffset(70, 6),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 23,
			ZIndex = 12,
		})
		Ui.Label(row, desc, {
			Size = UDim2.new(1, -230, 0, 26),
			Position = UDim2.fromOffset(70, 36),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Ui.Colors.SubText,
			TextSize = 18,
			ZIndex = 12,
		})
		return Ui.Button(row, buttonText, Ui.Colors.Green, {
			Size = UDim2.fromOffset(140, 48),
			Position = UDim2.new(1, -148, 0, 11),
			TextSize = 22,
			ZIndex = 12,
		}, onClick)
	end

	for key, pass in pairs(Config.GamePasses) do
		if pass.Id ~= 0 then
			passButtons[key] = addRow(pass.Emoji, pass.Name, pass.Description, "Kaufen", function()
				MarketplaceService:PromptGamePassPurchase(State.Player, pass.Id)
			end)
		end
	end
	for _, product in pairs(Config.DevProducts) do
		if product.Id ~= 0 then
			addRow(product.Emoji, product.Name, product.Description, "Kaufen", function()
				MarketplaceService:PromptProductPurchase(State.Player, product.Id)
			end)
		end
	end

	window.Refresh = function()
		local data = State.Data
		if not data then
			return
		end
		for key, button in pairs(passButtons) do
			local owned = data.Passes[key] == true
			button.Text = owned and "Gekauft ✓" or "Kaufen"
			button.BackgroundColor3 = owned and Ui.Colors.Grey or Ui.Colors.Green
			button.Active = not owned
		end
	end
	return window
end

--------------------------------------------------------------------------
-- Optionen
--------------------------------------------------------------------------
function MiscWindows.CreateSettings()
	local window = Windows.Create("Settings", "⚙️ Optionen", Ui.Colors.Grey, Vector2.new(560, 500))
	local action = Remotes.Get("Action")
	local list = Windows.ScrollList(window.Content, { Size = UDim2.fromScale(1, 1) })
	local built = false
	local stats

	local function build()
		built = true
		local entries = {
			{ Key = "Sfx", Text = "🔊 Sound-Effekte" },
			{ Key = "Music", Text = "🎵 Musik" },
			{ Key = "OtherItems", Text = "🍋 Früchte bei anderen Fabriken zeigen" },
			{ Key = "Guide", Text = "➡️ Pfeil zum nächsten Knopf" },
		}
		for i, entry in ipairs(entries) do
			local row = Ui.Toggle(list, entry.Text, State.Setting(entry.Key), function(value)
				action:FireServer("SetSetting", entry.Key, value)
				if State.Data then
					State.Data.Profile.Settings[entry.Key] = value
				end
				if entry.Key == "Music" then
					Sound.UpdateMusic()
				end
			end)
			row.LayoutOrder = i
			row.ZIndex = 11
		end
		stats = Ui.Label(list, "", {
			LayoutOrder = 10,
			Size = UDim2.new(1, 0, 0, 230),
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 12,
		})
	end

	window.OnOpen = function()
		if not built and State.Data then
			build()
		end
	end

	window.Refresh = function()
		local data = State.Data
		if not data or not stats then
			return
		end
		local s = data.Profile.Stats
		local fruit = Config.Fruits[data.Profile.Evolution + 1]
		stats.Text = table.concat({
			"📊 STATISTIK",
			"⏱️ Spielzeit: " .. Format.Time(s.PlayTime),
			"💰 Insgesamt verdient: " .. Format.Cash(data.Profile.AllTimeEarnings),
			"🛸 Rebirths: " .. Format.Int(s.Rebirths) .. "   🌀 Evolutionen: " .. Format.Int(s.Evolutions),
			"🔴 Knopf gedrückt: " .. Format.Int(s.Presses) .. "×",
			"✨ Goldene Zitronen: " .. Format.Int(s.Golden) .. "   🍋 Eingesammelt: " .. Format.Int(s.Pickups),
			"Frucht: " .. fruit.Emoji .. " " .. fruit.Name,
			data.CanSave and "💾 Speichern: aktiv" or "⚠️ Speichern: AUS (Studio: API-Zugriff einschalten)",
		}, "\n")
	end
	return window
end

--------------------------------------------------------------------------
-- Test-Menü (nur für dich als Entwickler)
--------------------------------------------------------------------------
function MiscWindows.CreateAdmin()
	local window = Windows.Create("Admin", "🛠️ Test-Menü", Ui.Colors.Red, Vector2.new(460, 430))
	local action = Remotes.Get("Action")
	local list = Windows.ScrollList(window.Content, { Size = UDim2.fromScale(1, 1) })
	local commands = {
		{ "cash", "💵 Viel Geld (×1000)", Ui.Colors.Green },
		{ "investors", "🛸 Investoren (×10)", Ui.Colors.Purple },
		{ "event", "🎉 Event starten", Ui.Colors.Orange },
		{ "daily", "🎁 Belohnungen zurücksetzen", Ui.Colors.Blue },
		{ "reset", "🗑️ Spielstand zurücksetzen", Ui.Colors.Red },
	}
	for i, cmd in ipairs(commands) do
		local button = Ui.Button(list, cmd[2], cmd[3], { LayoutOrder = i, Size = UDim2.new(1, 0, 0, 52), TextSize = 24, ZIndex = 12 }, function()
			action:FireServer("Admin", cmd[1])
		end)
		button.ZIndex = 12
	end
	Ui.Label(list, "Nur in Roblox Studio oder für den Spiel-Ersteller sichtbar.", {
		LayoutOrder = 99,
		Size = UDim2.new(1, 0, 0, 40),
		TextSize = 17,
		TextColor3 = Ui.Colors.SubText,
		ZIndex = 12,
	})
	return window
end

return MiscWindows
