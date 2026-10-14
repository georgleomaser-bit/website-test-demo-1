-- Tasks (daily login streak, daily tasks, expedition), playtime Gifts and Codes windows.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Format = require(Shared.Format)
local Rewards = require(Shared.Config.Rewards)
local Zones = require(Shared.Config.Zones)

local Kit = require(script.Parent.Kit)
local Windows = require(script.Parent.Windows)
local Feed = require(script.Parent.Feed)
local State = require(script.Parent.Parent.State)

local RewardWindows = {}

local function act(name, ...)
	local ok, msg = State.action(name, ...)
	if msg then
		Feed.notify(msg, ok and "success" or "error")
	end
	return ok
end

local function describe(reward): string
	if reward.Type == "Cash" then
		return "💵 Cash"
	elseif reward.Type == "Speed" then
		return "⚡ Speed"
	elseif reward.Type == "Bait" then
		return "🪔 " .. reward.Amount .. " Bait"
	elseif reward.Type == "Boost" then
		return "x2 " .. reward.Boost .. " " .. Format.time(reward.Seconds)
	elseif reward.Type == "Animal" then
		return "🐾 " .. reward.Id
	end
	return "?"
end

local function describeList(list): string
	local parts = {}
	for _, r in ipairs(list) do
		table.insert(parts, describe(r))
	end
	return table.concat(parts, " + ")
end

-- Tasks ------------------------------------------------------------------------------------
local tasksRefs = {}

local function refreshTasks()
	if not State.ready() or not tasksRefs.List then
		return
	end
	local data = State.Data
	local now = State.now()
	-- daily login
	local hours = (now - data.Daily.Last) / 3600
	local canDaily = data.Daily.Last == 0 or hours >= Rewards.DailyClaimCooldownHours
	local nextDay = ((data.Daily.Last == 0 or hours > Rewards.DailyStreakResetHours) and 1 or data.Daily.Streak + 1)
	local index = ((nextDay - 1) % #Rewards.Daily) + 1
	tasksRefs.DailyText.Text = string.format("Daily Reward · Day %d\n<font size=\"16\">%s</font>", nextDay, describeList(Rewards.Daily[index]))
	if canDaily then
		tasksRefs.DailyButton.setText("CLAIM!")
		tasksRefs.DailyButton.setColor(Kit.Colors.Yellow)
	else
		tasksRefs.DailyButton.setText(Format.time((Rewards.DailyClaimCooldownHours - hours) * 3600))
		tasksRefs.DailyButton.setColor(Kit.Colors.Gray)
	end
	-- tasks
	for i, row in ipairs(tasksRefs.Rows) do
		local t = data.Tasks.List[i]
		row.Frame.Visible = t ~= nil
		if t then
			row.Text.Text = t.Text
			local p = math.clamp(t.Progress / math.max(1, t.Goal), 0, 1)
			row.Fill.Size = UDim2.new(p, 0, 1, 0)
			row.Count.Text = Format.number(t.Progress) .. " / " .. Format.number(t.Goal)
			if t.Claimed then
				row.Button.setText("✔")
				row.Button.setColor(Kit.Colors.Gray)
			elseif p >= 1 then
				row.Button.setText("CLAIM")
				row.Button.setColor(Kit.Colors.Yellow)
			else
				row.Button.setText(describe(Rewards.TaskReward[1]))
				row.Button.setColor(Kit.Colors.Gray)
			end
		end
	end
	-- expedition
	local exp = data.Expedition
	local parts = {}
	for i, zone in ipairs(Zones) do
		local done = exp.Zones[i]
		table.insert(parts, string.format('<font color="%s">%s %s</font>', done and "#7CFF6B" or "#9A9AB0", done and "✔" or "○", zone.Name))
	end
	tasksRefs.Expedition.Text = string.format("🧭 Expedition %d: bring a wild egg home from every zone\n%s\n<font size=\"16\">Reward: %s</font>",
		exp.Level + 1, table.concat(parts, "   "), describeList(Rewards.Expedition(exp.Level + 1)))
end

local function buildTasks()
	local window = Windows.create("Tasks", "Tasks", Vector2.new(680, 500), Kit.Colors.Purple)
	local content = window.Content
	Kit.list(content, 10)
	local daily = Kit.panel({ Size = UDim2.new(1, 0, 0, 80), Color = Kit.Colors.PanelLight, Order = 1, Parent = content })
	tasksRefs.DailyText = Kit.label({ Text = "", Size = UDim2.new(1, -190, 1, -10), Position = UDim2.fromOffset(12, 5), XAlign = Enum.TextXAlignment.Left, Parent = daily })
	tasksRefs.DailyButton = Kit.button({ Text = "CLAIM!", Size = UDim2.fromOffset(160, 54), Position = UDim2.new(1, -12, 0.5, 0), Anchor = Vector2.new(1, 0.5), Color = Kit.Colors.Yellow, Parent = daily }, function()
		act("ClaimDaily")
	end)

	tasksRefs.List = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 3 * 74), LayoutOrder = 2, Parent = content })
	Kit.list(tasksRefs.List, 8)
	tasksRefs.Rows = {}
	for i = 1, Rewards.TasksPerDay do
		local frame = Kit.panel({ Size = UDim2.new(1, 0, 0, 66), Color = Kit.Colors.PanelLight, Order = i, Parent = tasksRefs.List })
		local text = Kit.label({ Text = "", Size = UDim2.new(1, -200, 0, 28), Position = UDim2.fromOffset(12, 4), XAlign = Enum.TextXAlignment.Left, Parent = frame })
		local bar = Kit.panel({ Size = UDim2.new(1, -200, 0, 22), Position = UDim2.fromOffset(12, 36), Color = Kit.Colors.PanelDark, Radius = 11, StrokeThickness = 2, Parent = frame })
		local fill = Kit.new("Frame", { BackgroundColor3 = Kit.Colors.Purple, Size = UDim2.new(0, 0, 1, 0), Parent = bar })
		Kit.corner(fill, 11)
		local count = Kit.label({ Text = "", Size = UDim2.new(1, 0, 1, 0), Z = 3, Parent = bar })
		local index = i
		local button = Kit.button({ Text = "", Size = UDim2.fromOffset(160, 50), Position = UDim2.new(1, -12, 0.5, 0), Anchor = Vector2.new(1, 0.5), Color = Kit.Colors.Gray, Parent = frame }, function()
			act("ClaimTask", index)
		end)
		tasksRefs.Rows[i] = { Frame = frame, Text = text, Fill = fill, Count = count, Button = button }
	end

	local exp = Kit.panel({ Size = UDim2.new(1, 0, 0, 110), Color = Color3.fromRGB(40, 70, 60), Order = 3, Parent = content })
	tasksRefs.Expedition = Kit.label({ Text = "", Size = UDim2.new(1, -24, 1, -12), Position = UDim2.fromOffset(12, 6), XAlign = Enum.TextXAlignment.Left, Parent = exp })

	window.OnOpen = refreshTasks
	State.Changed:Connect(refreshTasks)
	State.StatsChanged:Connect(function()
		if Windows.isOpen("Tasks") then
			refreshTasks()
		end
	end)
end

-- Gifts ------------------------------------------------------------------------------------
local giftButtons = {}

local function refreshGifts()
	if not State.ready() then
		return
	end
	local d = State.Derived
	local elapsed = State.now() - d.SessionStart
	for i, gift in ipairs(Rewards.Playtime) do
		local b = giftButtons[i]
		if b then
			local claimed = d.PlaytimeClaimed[tostring(i)]
			local left = gift.Minutes * 60 - elapsed
			if claimed then
				b.setText("✔ Claimed")
				b.setColor(Kit.Colors.Gray)
			elseif left <= 0 then
				b.setText("🎁 CLAIM!\n" .. describe(gift.Reward))
				b.setColor(Kit.Colors.Yellow)
			else
				b.setText(Format.time(left) .. "\n" .. describe(gift.Reward))
				b.setColor(Kit.Colors.Purple)
			end
		end
	end
end

local function buildGifts()
	local window = Windows.create("Gifts", "Free Gifts", Vector2.new(640, 440), Kit.Colors.Yellow)
	local content = window.Content
	Kit.new("UIGridLayout", { CellSize = UDim2.fromOffset(190, 110), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = content })
	for i in ipairs(Rewards.Playtime) do
		local holder = Kit.new("Frame", { BackgroundTransparency = 1, LayoutOrder = i, Parent = content })
		giftButtons[i] = Kit.button({ Text = "", Size = UDim2.new(1, 0, 1, -6), Color = Kit.Colors.Purple, Parent = holder, MaxTextSize = 24 }, function()
			act("ClaimPlaytime", i)
		end)
	end
	window.OnOpen = refreshGifts
	State.Changed:Connect(refreshGifts)
	task.spawn(function()
		while true do
			task.wait(1)
			if Windows.isOpen("Gifts") then
				refreshGifts()
			end
			if Windows.isOpen("Tasks") then
				refreshTasks()
			end
		end
	end)
end

-- Codes ------------------------------------------------------------------------------------
local function buildCodes()
	local window = Windows.create("Codes", "Codes", Vector2.new(460, 250), Kit.Colors.White)
	local content = window.Content
	local box = Kit.new("TextBox", {
		Size = UDim2.new(1, -20, 0, 54),
		Position = UDim2.fromOffset(10, 20),
		BackgroundColor3 = Kit.Colors.PanelDark,
		PlaceholderText = "Enter code...",
		PlaceholderColor3 = Color3.fromRGB(150, 150, 170),
		Text = "",
		TextColor3 = Kit.Colors.White,
		Font = Kit.Font,
		TextScaled = true,
		ClearTextOnFocus = false,
		Parent = content,
	})
	Kit.corner(box, 12)
	Kit.stroke(box, 3, nil, Enum.ApplyStrokeMode.Border)
	Kit.padding(box, 8)
	Kit.button({ Text = "Redeem", Size = UDim2.fromOffset(200, 54), Position = UDim2.new(0.5, 0, 0, 100), Anchor = Vector2.new(0.5, 0), Parent = content }, function()
		if act("RedeemCode", box.Text) then
			box.Text = ""
		end
	end)
end

function RewardWindows.init()
	buildTasks()
	buildGifts()
	buildCodes()
end

return RewardWindows
