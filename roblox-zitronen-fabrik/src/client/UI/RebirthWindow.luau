--[[
	🛸 Zorps Menü: Rebirth gegen Alien-Investoren und Alien-Kräfte kaufen.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Ui)
local Windows = require(script.Parent.Windows)

local RebirthWindow = {}

function RebirthWindow.Create()
	local window = Windows.Create("Rebirth", "🛸 Zorp – Rebirth", Ui.Colors.Purple, Vector2.new(640, 520))
	local content = window.Content
	local action = Remotes.Get("Action")

	-- Reiter
	local tabBar = Ui.Frame(content, { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, ZIndex = 11 })
	local pages = {}
	local tabs = {}
	local function showTab(name: string)
		for key, page in pairs(pages) do
			page.Visible = key == name
		end
		for key, tab in pairs(tabs) do
			tab.BackgroundColor3 = key == name and Ui.Colors.Purple or Ui.Colors.Grey
		end
	end
	tabs.Rebirth = Ui.Button(tabBar, "🛸 Rebirth", Ui.Colors.Purple, { Size = UDim2.new(0.5, -4, 1, 0), TextSize = 22, ZIndex = 12 }, function()
		showTab("Rebirth")
	end)
	tabs.Powers = Ui.Button(tabBar, "👽 Alien-Kräfte", Ui.Colors.Grey, {
		Size = UDim2.new(0.5, -4, 1, 0),
		Position = UDim2.new(0.5, 4, 0, 0),
		TextSize = 22,
		ZIndex = 12,
	}, function()
		showTab("Powers")
	end)

	----------------------------------------------------------------------
	-- Seite: Rebirth
	----------------------------------------------------------------------
	local rebirthPage = Ui.Frame(content, {
		Size = UDim2.new(1, 0, 1, -50),
		Position = UDim2.fromOffset(0, 50),
		BackgroundTransparency = 1,
		ZIndex = 11,
	})
	pages.Rebirth = rebirthPage
	local investorsLabel = Ui.Label(rebirthPage, "", { Size = UDim2.new(1, 0, 0, 40), TextSize = 34, TextColor3 = Color3.fromRGB(170, 255, 140), ZIndex = 12 })
	local bonusLabel = Ui.Label(rebirthPage, "", { Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 42), TextSize = 21, TextColor3 = Ui.Colors.SubText, ZIndex = 12 })
	local claimLabel = Ui.Label(rebirthPage, "", { Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 80), TextSize = 28, TextColor3 = Ui.Colors.Gold, ZIndex = 12 })
	local afterLabel = Ui.Label(rebirthPage, "", { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 116), TextSize = 20, ZIndex = 12 })
	local _, nextFill, nextText = Ui.ProgressBar(rebirthPage, {
		Size = UDim2.new(1, -40, 0, 26),
		Position = UDim2.fromOffset(20, 150),
		ZIndex = 12,
	}, Ui.Colors.Purple)
	nextFill.ZIndex = 13
	nextText.ZIndex = 14
	local keyLabel = Ui.Label(rebirthPage, "", { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 184), TextSize = 19, TextColor3 = Color3.fromRGB(150, 255, 150), ZIndex = 12 })
	Ui.Label(rebirthPage, "Rebirth setzt deine Fabrik, dein Geld und deine Upgrades zurück.\nDie Alien-Investoren bleiben für immer und machen alles schneller reich! 🚀", {
		Size = UDim2.new(1, -20, 0, 54),
		Position = UDim2.fromOffset(10, 214),
		TextSize = 19,
		TextColor3 = Ui.Colors.SubText,
		ZIndex = 12,
	})
	local confirmUntil = 0
	local rebirthButton
	rebirthButton = Ui.Button(rebirthPage, "", Ui.Colors.Purple, {
		Size = UDim2.new(1, -120, 0, 70),
		Position = UDim2.fromOffset(60, 290),
		TextSize = 30,
		ZIndex = 12,
	}, function()
		if os.clock() < confirmUntil then
			confirmUntil = 0
			action:FireServer("Rebirth")
		else
			confirmUntil = os.clock() + 3
		end
		if window.Refresh then
			window.Refresh()
		end
	end)
	Ui.Stroke(rebirthButton, 3, Color3.new(0, 0, 0), 0.3)

	----------------------------------------------------------------------
	-- Seite: Alien-Kräfte
	----------------------------------------------------------------------
	local powersPage = Ui.Frame(content, {
		Size = UDim2.new(1, 0, 1, -50),
		Position = UDim2.fromOffset(0, 50),
		BackgroundTransparency = 1,
		ZIndex = 11,
		Visible = false,
	})
	pages.Powers = powersPage
	local powerInfo = Ui.Label(powersPage, "", {
		Size = UDim2.new(1, 0, 0, 40),
		TextSize = 18,
		TextColor3 = Ui.Colors.SubText,
		ZIndex = 12,
	})
	local powerList = Windows.ScrollList(powersPage, {
		Size = UDim2.new(1, 0, 1, -46),
		Position = UDim2.fromOffset(0, 46),
	})
	local powerRows = {}
	for k, power in ipairs(Config.Powers) do
		local row = Ui.Frame(powerList, {
			LayoutOrder = k,
			Size = UDim2.new(1, 0, 0, 62),
			BackgroundColor3 = k % 2 == 0 and Ui.Colors.RowAlt or Ui.Colors.Row,
			ZIndex = 11,
		})
		Ui.Corner(row, 10)
		Ui.Label(row, power.Emoji, { Size = UDim2.fromOffset(54, 54), Position = UDim2.fromOffset(6, 4), TextSize = 34, ZIndex = 12 })
		local name = Ui.Label(row, power.Name, {
			Size = UDim2.new(1, -240, 0, 26),
			Position = UDim2.fromOffset(64, 4),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 22,
			ZIndex = 12,
		})
		Ui.Label(row, power.Description, {
			Size = UDim2.new(1, -240, 0, 24),
			Position = UDim2.fromOffset(64, 32),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Ui.Colors.SubText,
			TextSize = 18,
			ZIndex = 12,
		})
		local buy = Ui.Button(row, "", Ui.Colors.Purple, {
			Size = UDim2.fromOffset(160, 46),
			Position = UDim2.new(1, -168, 0, 8),
			TextSize = 19,
			ZIndex = 12,
		}, function()
			action:FireServer("BuyPower", power.Id)
		end)
		powerRows[k] = { Name = name, Buy = buy }
	end

	window.OnOpen = function()
		showTab("Rebirth")
		confirmUntil = 0
	end

	window.Refresh = function()
		local data = State.Data
		local view = State.ProfileView()
		if not data or not view then
			return
		end
		local p = data.Profile
		local s = data.Stats
		investorsLabel.Text = "🛸 " .. Format.Number(p.Investors) .. " Alien-Investoren"
		bonusLabel.Text = "Bonus: +" .. Format.Percent(s.InvestorMult - 1) .. " auf alles  (" .. Format.Percent(s.PerInvestor) .. " pro Investor)"
		local claim = Economy.ClaimableInvestors(view)
		claimLabel.Text = claim > 0 and ("Rebirth bringt dir: +" .. Format.Number(claim) .. " Investoren") or "Noch keine neuen Investoren…"
		local after = 1 + (p.Investors + claim) * s.PerInvestor
		afterLabel.Text = claim > 0 and ("Danach: +" .. Format.Percent(after - 1) .. " Bonus (statt +" .. Format.Percent(s.InvestorMult - 1) .. ")") or ""
		local totalNow = p.Investors + p.InvestorsSpent + claim
		local needFrom = Economy.EarningsForInvestors(totalNow)
		local needTo = Economy.EarningsForInvestors(totalNow + 1)
		local earned = State.EvoEarnings()
		Ui.SetProgress(nextFill, (earned - needFrom) / math.max(1, needTo - needFrom))
		nextText.Text = "Nächster Investor: " .. Format.Cash(earned) .. " / " .. Format.Cash(needTo) .. " verdient"
		if p.Secrets.UfoKeyDelivered then
			keyLabel.Text = "✅ UFO-Schlüssel abgegeben: Investoren sind 50 % stärker!"
		elseif p.Secrets.UfoKey then
			keyLabel.Text = "🔑 Du hast Zorps UFO-Schlüssel! Rede mit Zorp auf dem Platz."
		else
			keyLabel.Text = "Gerücht: Zorp hat seinen UFO-Schlüssel in der Kanalisation verloren… 🕳️"
		end
		if claim < Config.Rebirth.MinInvestors then
			rebirthButton.Text = "🛸 Rebirth (noch nicht möglich)"
			rebirthButton.BackgroundColor3 = Ui.Colors.Grey
		elseif os.clock() < confirmUntil then
			rebirthButton.Text = "Wirklich? Nochmal klicken! ⚠️"
			rebirthButton.BackgroundColor3 = Ui.Colors.Red
		else
			rebirthButton.Text = "🛸 REBIRTH  (+" .. Format.Number(claim) .. " Investoren)"
			rebirthButton.BackgroundColor3 = Ui.Colors.Purple
		end

		powerInfo.Text = "Kräfte kosten Investoren. Ausgegebene Investoren geben keinen Bonus mehr – wähle klug!\nDu hast: 🛸 " .. Format.Number(p.Investors)
		for k, power in ipairs(Config.Powers) do
			local row = powerRows[k]
			local level = Economy.PowerLevel(view, power.Id)
			row.Name.Text = power.Name .. "  ·  Stufe " .. level .. "/" .. power.Max
			if level >= power.Max then
				row.Buy.Text = "MAX ✓"
				row.Buy.BackgroundColor3 = Ui.Colors.Gold
			else
				local cost = Economy.PowerCost(power, level)
				row.Buy.Text = "🛸 " .. Format.Number(cost)
				row.Buy.BackgroundColor3 = p.Investors >= cost and Ui.Colors.Purple or Ui.Colors.Grey
			end
		end
	end

	return window
end

return RebirthWindow
