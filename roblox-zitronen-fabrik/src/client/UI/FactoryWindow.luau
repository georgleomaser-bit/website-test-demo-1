--[[
	🏭 Fabrik-Menü: alle Linien mit Level kaufen (×1/×10/×100/MAX),
	Zyklus-Fortschritt, Meilensteine und "Pressen"-Knopf.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local State = require(script.Parent.Parent.State)
local Ui = require(script.Parent.Ui)
local Windows = require(script.Parent.Windows)

local FactoryWindow = {}

local MODES = { 1, 10, 100, "max" }

function FactoryWindow.Create()
	local window = Windows.Create("Factory", "🏭 Deine Fabrik", Ui.Colors.Green, Vector2.new(700, 520))
	local content = window.Content
	local action = Remotes.Get("Action")

	-- Kaufmenge
	local modeBar = Ui.Frame(content, { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, ZIndex = 11 })
	Ui.Label(modeBar, "Kaufmenge:", { Size = UDim2.fromOffset(120, 40), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 22, ZIndex = 12 })
	local modeButtons = {}
	for i, mode in ipairs(MODES) do
		local text = mode == "max" and "MAX" or ("×" .. mode)
		modeButtons[i] = Ui.Button(modeBar, text, Ui.Colors.Grey, {
			Size = UDim2.fromOffset(80, 34),
			Position = UDim2.fromOffset(120 + (i - 1) * 88, 3),
			TextSize = 22,
			ZIndex = 12,
		}, function()
			State.BuyMode = mode
			if window.Refresh then
				window.Refresh()
			end
		end)
	end
	local startAll = Ui.Button(modeBar, "▶ Alle pressen", Ui.Colors.Red, {
		Size = UDim2.fromOffset(150, 34),
		Position = UDim2.new(1, -160, 0, 3),
		TextSize = 20,
		ZIndex = 12,
	}, function()
		action:FireServer("StartAll")
	end)

	local list = Windows.ScrollList(content, {
		Size = UDim2.new(1, 0, 1, -48),
		Position = UDim2.fromOffset(0, 48),
	})

	local rows = {}
	for i, laneCfg in ipairs(Config.Lanes) do
		local row = Ui.Frame(list, {
			Name = "Lane" .. i,
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 108),
			BackgroundColor3 = i % 2 == 0 and Ui.Colors.RowAlt or Ui.Colors.Row,
			ZIndex = 11,
		})
		Ui.Corner(row, 10)
		local icon = Ui.Frame(row, {
			Size = UDim2.fromOffset(70, 70),
			Position = UDim2.fromOffset(10, 19),
			BackgroundColor3 = laneCfg.Color,
			ZIndex = 12,
		})
		Ui.Corner(icon, 10)
		Ui.Stroke(icon, 2, Color3.new(0, 0, 0), 0.3)
		Ui.Label(icon, laneCfg.Emoji, { Size = UDim2.fromScale(1, 1), TextSize = 44, ZIndex = 13 })
		local name = Ui.Label(row, laneCfg.Name, {
			Size = UDim2.new(1, -270, 0, 26),
			Position = UDim2.fromOffset(92, 6),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 24,
			ZIndex = 12,
		})
		local info = Ui.Label(row, "", {
			Size = UDim2.new(1, -270, 0, 20),
			Position = UDim2.fromOffset(92, 32),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Ui.Colors.SubText,
			TextSize = 18,
			ZIndex = 12,
		})
		local cycleBar, cycleFill, cycleText = Ui.ProgressBar(row, {
			Size = UDim2.new(1, -270, 0, 22),
			Position = UDim2.fromOffset(92, 56),
			ZIndex = 12,
		}, laneCfg.Color)
		cycleFill.ZIndex = 13
		cycleText.ZIndex = 14
		local msBar, msFill, msText = Ui.ProgressBar(row, {
			Size = UDim2.new(1, -270, 0, 18),
			Position = UDim2.fromOffset(92, 82),
			ZIndex = 12,
		}, Ui.Colors.Gold)
		msFill.ZIndex = 13
		msText.ZIndex = 14
		msText.TextSize = 14
		local buy = Ui.Button(row, "", Ui.Colors.Green, {
			Size = UDim2.fromOffset(160, 58),
			Position = UDim2.new(1, -170, 0, 8),
			TextSize = 20,
			ZIndex = 12,
		}, function()
			action:FireServer("BuyLevels", i, State.BuyMode)
		end)
		local press = Ui.Button(row, "▶ Pressen", Ui.Colors.Red, {
			Size = UDim2.fromOffset(160, 32),
			Position = UDim2.new(1, -170, 0, 70),
			TextSize = 19,
			ZIndex = 12,
		}, function()
			action:FireServer("StartLane", i)
		end)
		local locked = Ui.Label(row, "", {
			Size = UDim2.new(1, -100, 0, 50),
			Position = UDim2.fromOffset(92, 40),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Ui.Colors.SubText,
			TextSize = 19,
			ZIndex = 12,
			Visible = false,
		})
		rows[i] = {
			Name = name,
			Info = info,
			CycleBar = cycleBar,
			CycleFill = cycleFill,
			CycleText = cycleText,
			MsBar = msBar,
			MsFill = msFill,
			MsText = msText,
			Buy = buy,
			Press = press,
			Locked = locked,
		}
	end

	local function laneState(i: number)
		local plot = State.Plot()
		local states = plot and plot:FindFirstChild("LaneState")
		return states and states:FindFirstChild("Lane" .. i)
	end

	window.Refresh = function()
		local data = State.Data
		if not data then
			return
		end
		for i, button in ipairs(modeButtons) do
			button.BackgroundColor3 = MODES[i] == State.BuyMode and Ui.Colors.Blue or Ui.Colors.Grey
		end
		local cash = State.Cash()
		local discount = data.Stats.Discount
		local anyManual = false
		for i, laneCfg in ipairs(Config.Lanes) do
			local row = rows[i]
			local lane = data.Profile.Lanes[i]
			local stats = data.Stats.Lanes[i]
			local unlocked = lane.Level > 0
			row.Info.Visible = unlocked
			row.CycleBar.Visible = unlocked
			row.MsBar.Visible = unlocked
			row.Buy.Visible = unlocked
			row.Press.Visible = unlocked
			row.Locked.Visible = not unlocked
			if not unlocked then
				local prevOk = i == 1 or data.Profile.Lanes[i - 1].Level > 0
				local cost = Economy.LevelCost(laneCfg, 0, 1, discount)
				row.Locked.Text = prevOk and ("🔒 Freischalten am grünen Knopf vorne in deiner Fabrik – " .. Format.Cash(cost))
					or "🔒 Schalte zuerst die Linie davor frei."
				row.Name.Text = laneCfg.Name
			else
				row.Name.Text = laneCfg.Name .. "  ·  Lv " .. Format.Int(lane.Level)
				local managerText = lane.Manager and ("🤖 " .. laneCfg.Manager.Name) or "✋ ohne Manager – selbst pressen!"
				row.Info.Text = Format.Cash(stats.IncomePerSec) .. "/s  ·  " .. managerText
				if not lane.Manager then
					anyManual = true
				end
				-- Kaufen
				local amount = Economy.ResolveBuyAmount(laneCfg, lane.Level, cash, discount, State.BuyMode)
				if amount <= 0 then
					row.Buy.Text = "MAX LEVEL"
					row.Buy.BackgroundColor3 = Ui.Colors.Gold
				else
					local cost = Economy.LevelCost(laneCfg, lane.Level, amount, discount)
					row.Buy.Text = "Kaufen ×" .. amount .. "\n" .. Format.Cash(cost)
					row.Buy.BackgroundColor3 = cash >= cost and Ui.Colors.Green or Ui.Colors.Grey
				end
				-- Meilenstein
				local nextMs = Economy.NextMilestone(lane.Level)
				if nextMs then
					local prev = Economy.PreviousMilestoneLevel(lane.Level)
					Ui.SetProgress(row.MsFill, (lane.Level - prev) / (nextMs.Level - prev))
					local what = nextMs.Speed and (nextMs.Speed .. "× Tempo") or ((nextMs.Revenue or 1) .. "× Geld")
					row.MsText.Text = "Meilenstein Lv " .. nextMs.Level .. ": " .. what
				else
					Ui.SetProgress(row.MsFill, 1)
					row.MsText.Text = "Alle Meilensteine geschafft! 🏆"
				end
				row.Press.Text = lane.Manager and "🤖 Automatisch" or "▶ Pressen"
				row.Press.BackgroundColor3 = lane.Manager and Ui.Colors.Grey or Ui.Colors.Red
				row.Press.Active = not lane.Manager
			end
		end
		startAll.Visible = anyManual
	end

	window.Update = function()
		local data = State.Data
		if not data then
			return
		end
		local now = workspace:GetServerTimeNow()
		for i = 1, #Config.Lanes do
			local lane = data.Profile.Lanes[i]
			if lane.Level > 0 then
				local row = rows[i]
				local state = laneState(i)
				local progress = 0
				local cycle = data.Stats.Lanes[i].CycleTime
				if state and state:GetAttribute("Running") then
					local start = state:GetAttribute("CycleStart") or now
					local t = state:GetAttribute("CycleTime") or cycle
					if t > 0 then
						local elapsed = now - start
						progress = lane.Manager and ((elapsed % t) / t) or math.clamp(elapsed / t, 0, 1)
					end
				end
				if cycle < 0.3 and lane.Manager then
					progress = 1
				end
				Ui.SetProgress(row.CycleFill, progress)
				row.CycleText.Text = Format.Cash(data.Stats.Lanes[i].Revenue) .. " pro " .. Format.Cycle(cycle)
			end
		end
	end

	return window
end

return FactoryWindow
