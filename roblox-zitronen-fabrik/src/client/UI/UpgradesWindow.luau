--[[
	⬆️ Upgrade-Menü: Geld-Upgrades (×3 für eine Linie, ×3 für alles,
	stärkere Investoren). Zeigt die nächsten günstigsten.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Ui)
local Windows = require(script.Parent.Windows)

local UpgradesWindow = {}

local SHOWN = 20

function UpgradesWindow.Create()
	local window = Windows.Create("Upgrades", "⬆️ Upgrades", Ui.Colors.Blue, Vector2.new(640, 500))
	local content = window.Content
	local action = Remotes.Get("Action")

	local top = Ui.Frame(content, { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, ZIndex = 11 })
	local counter = Ui.Label(top, "", {
		Size = UDim2.new(1, -200, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 22,
		ZIndex = 12,
	})
	Ui.Button(top, "🌟 Alle kaufen", Ui.Colors.Green, {
		Size = UDim2.fromOffset(180, 36),
		Position = UDim2.new(1, -184, 0, 2),
		TextSize = 22,
		ZIndex = 12,
	}, function()
		action:FireServer("BuyAllUpgrades")
	end)

	local list = Windows.ScrollList(content, {
		Size = UDim2.new(1, 0, 1, -48),
		Position = UDim2.fromOffset(0, 48),
	})

	local rows = {}
	for k = 1, SHOWN do
		local row = Ui.Frame(list, {
			LayoutOrder = k,
			Size = UDim2.new(1, 0, 0, 64),
			BackgroundColor3 = k % 2 == 0 and Ui.Colors.RowAlt or Ui.Colors.Row,
			ZIndex = 11,
			Visible = false,
		})
		Ui.Corner(row, 10)
		local icon = Ui.Label(row, "", { Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(6, 4), TextSize = 36, ZIndex = 12 })
		local name = Ui.Label(row, "", {
			Size = UDim2.new(1, -250, 0, 28),
			Position = UDim2.fromOffset(68, 4),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 22,
			ZIndex = 12,
		})
		local desc = Ui.Label(row, "", {
			Size = UDim2.new(1, -250, 0, 24),
			Position = UDim2.fromOffset(68, 32),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Ui.Colors.SubText,
			TextSize = 18,
			ZIndex = 12,
		})
		local entry = { Row = row, Icon = icon, Name = name, Desc = desc, Id = nil :: string? }
		entry.Buy = Ui.Button(row, "", Ui.Colors.Green, {
			Size = UDim2.fromOffset(160, 48),
			Position = UDim2.new(1, -168, 0, 8),
			TextSize = 22,
			ZIndex = 12,
		}, function()
			if entry.Id then
				action:FireServer("BuyUpgrade", entry.Id)
			end
		end)
		rows[k] = entry
	end
	local done = Ui.Label(list, "Du hast ALLE Upgrades gekauft! 🏆 Zeit für einen Rebirth bei Zorp.", {
		LayoutOrder = SHOWN + 1,
		Size = UDim2.new(1, 0, 0, 60),
		TextSize = 22,
		Visible = false,
		ZIndex = 12,
	})

	window.Refresh = function()
		local data = State.Data
		if not data then
			return
		end
		local cash = State.Cash()
		local owned = 0
		local k = 0
		for _, info in ipairs(Config.CashUpgrades) do
			if data.Profile.Upgrades[info.Id] then
				owned += 1
			elseif k < SHOWN then
				k += 1
				local entry = rows[k]
				entry.Id = info.Id
				entry.Row.Visible = true
				entry.Icon.Text = info.Emoji
				entry.Name.Text = info.Name
				entry.Desc.Text = info.Description
				entry.Buy.Text = Format.Cash(info.Cost)
				entry.Buy.BackgroundColor3 = cash >= info.Cost and Ui.Colors.Green or Ui.Colors.Grey
			end
		end
		for j = k + 1, SHOWN do
			rows[j].Row.Visible = false
			rows[j].Id = nil
		end
		done.Visible = k == 0
		counter.Text = owned .. " von " .. #Config.CashUpgrades .. " Upgrades gekauft"
	end

	return window
end

return UpgradesWindow
