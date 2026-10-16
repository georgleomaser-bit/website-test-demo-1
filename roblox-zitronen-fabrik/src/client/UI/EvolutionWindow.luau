--[[
	🌀 Frucht-Evolution (das lila Portal auf dem Platz).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Ui)
local Windows = require(script.Parent.Windows)

local EvolutionWindow = {}

function EvolutionWindow.Create()
	local window = Windows.Create("Evolution", "🌀 Frucht-Evolution", Ui.Colors.Pink, Vector2.new(600, 480))
	local content = window.Content
	local action = Remotes.Get("Action")

	local fruits = Ui.Label(content, "", { Size = UDim2.new(1, 0, 0, 80), TextSize = 56, ZIndex = 12 })
	local names = Ui.Label(content, "", { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 80), TextSize = 24, ZIndex = 12 })
	local _, fill, progressText = Ui.ProgressBar(content, {
		Size = UDim2.new(1, -40, 0, 30),
		Position = UDim2.fromOffset(20, 124),
		ZIndex = 12,
	}, Ui.Colors.Pink)
	fill.ZIndex = 13
	progressText.ZIndex = 14
	local reward = Ui.Label(content, "", {
		Size = UDim2.new(1, -20, 0, 56),
		Position = UDim2.fromOffset(10, 166),
		TextSize = 22,
		TextColor3 = Ui.Colors.Gold,
		ZIndex = 12,
	})
	Ui.Label(content, "⚠️ Achtung: Die Evolution setzt ALLES zurück – auch Investoren und Alien-Kräfte!\nAlle Früchte auf deinen Bändern verwandeln sich in die neue Frucht.", {
		Size = UDim2.new(1, -20, 0, 56),
		Position = UDim2.fromOffset(10, 226),
		TextSize = 18,
		TextColor3 = Ui.Colors.SubText,
		ZIndex = 12,
	})
	local confirmUntil = 0
	local button
	button = Ui.Button(content, "", Ui.Colors.Pink, {
		Size = UDim2.new(1, -120, 0, 66),
		Position = UDim2.fromOffset(60, 300),
		TextSize = 28,
		ZIndex = 12,
	}, function()
		if os.clock() < confirmUntil then
			confirmUntil = 0
			action:FireServer("Evolve")
		else
			confirmUntil = os.clock() + 3
		end
		if window.Refresh then
			window.Refresh()
		end
	end)
	Ui.Stroke(button, 3, Color3.new(0, 0, 0), 0.3)

	window.OnOpen = function()
		confirmUntil = 0
	end

	window.Refresh = function()
		local data = State.Data
		local view = State.ProfileView()
		if not data or not view then
			return
		end
		local tier = data.Profile.Evolution
		local current = Config.Fruits[tier + 1]
		local nextFruit = Config.Fruits[tier + 2]
		if not nextFruit then
			fruits.Text = current.Emoji
			names.Text = "Du hast die " .. current.Name .. "! Du bist ein Zitronen-Gott. 🌌"
			Ui.SetProgress(fill, 1)
			progressText.Text = "MAXIMUM"
			reward.Text = "Alles ×" .. Format.Number(data.Stats.EvoIncome) .. " Geld und ×" .. Format.Number(data.Stats.EvoSpeed) .. " Tempo"
			button.Text = "✓ Fertig entwickelt"
			button.BackgroundColor3 = Ui.Colors.Gold
			return
		end
		fruits.Text = current.Emoji .. "  ➜  " .. nextFruit.Emoji
		names.Text = current.Name .. "  ➜  " .. nextFruit.Name
		local need = Economy.EvolutionRequirement(tier)
		local have = Economy.EvolutionProgress(view)
		Ui.SetProgress(fill, have / need)
		progressText.Text = "Investoren insgesamt: " .. Format.Number(have) .. " / " .. Format.Number(need)
		reward.Text = "Belohnung für immer: ×" .. Config.Evolution.IncomeMult .. " Geld und ×" .. Config.Evolution.SpeedMult .. " Tempo\n(jetzt: ×" .. Format.Number(data.Stats.EvoIncome) .. " Geld, ×" .. Format.Number(data.Stats.EvoSpeed) .. " Tempo)"
		if have < need then
			button.Text = "🌀 Noch nicht bereit"
			button.BackgroundColor3 = Ui.Colors.Grey
		elseif os.clock() < confirmUntil then
			button.Text = "Wirklich ALLES zurücksetzen? ⚠️"
			button.BackgroundColor3 = Ui.Colors.Red
		else
			button.Text = "🌀 EVOLUTION ZUR " .. string.upper(nextFruit.Name)
			button.BackgroundColor3 = Ui.Colors.Pink
		end
	end

	return window
end

return EvolutionWindow
