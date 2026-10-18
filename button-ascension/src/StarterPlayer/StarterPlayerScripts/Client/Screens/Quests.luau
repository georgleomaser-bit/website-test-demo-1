--[[
	Quests (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Screens/Quests
	Depends on: ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format,Formulas,Util,Config/*},
	            Client/{State,ClientNet}

	Four tabs:
	  Daily       three quests per UTC day + a bonus for finishing all of them
	  Starter     the guided starter path
	  Login       the 7-day login calendar (streak resets if a day is missed)
	  Achievements every achievement with progress toward it
	All claims are validated by the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIFolder = ReplicatedStorage:WaitForChild("UI")
local UI = require(UIFolder.UIKit)
local Theme = require(UIFolder.Theme)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Util = require(Shared.Util)
local Config = Shared.Config
local Quests = require(Config.Quests)
local Rewards = require(Config.Rewards)
local Achievements = require(Config.Achievements)

local Client = script.Parent.Parent
local State = require(Client.State)
local ClientNet = require(Client.ClientNet)

local C = Theme.Colors
local F = Theme.Fonts

local QuestsScreen = {}

local function achievementValue(stat: string): number
	local view = State.view()
	if stat == "Rebirths" then
		return view.Rebirths
	elseif stat == "Level" then
		return view.Level
	elseif stat == "ItemsDiscovered" then
		return Formulas.discoveredCount(view)
	elseif stat == "SkillRanks" then
		return Formulas.skillPointsSpent(view)
	end
	return view.Stats[stat] or 0
end

function QuestsScreen.new(ctx)
	local window = UI.window({
		Name = "Quests",
		Title = "Quests & Rewards",
		Subtitle = "Daily quests reset at 00:00 UTC.",
		Icon = "📜",
		Parent = ctx.Layers.Windows,
	})
	local screen: { [string]: any } = { Window = window }
	local body = window.Body
	local describe = ctx.Notifications.describeReward
	local tab = "Daily"

	local pages = {}
	local function page(name: string)
		local frame = UI.scroll({
			Name = name,
			Size = UDim2.new(1, 0, 1, -50),
			Position = UDim2.fromOffset(0, 50),
			List = { Dir = "Y", Pad = 10 },
			Padding = { 2, 8, 2, 8 },
			Visible = false,
			Parent = body,
		})
		pages[name] = frame
		return frame
	end

	UI.segmented({
		Options = {
			{ Id = "Daily", Text = "📜 Daily" },
			{ Id = "Starter", Text = "🎯 Starter" },
			{ Id = "Login", Text = "📅 Login" },
			{ Id = "Achievements", Text = "🏆 Achievements" },
		},
		Value = "Daily",
		ButtonWidth = 150,
		OnChange = function(id)
			tab = id
			screen.Refresh()
		end,
		Parent = body,
	})

	local function claimButton(parent: Instance, onClick: () -> ())
		return UI.button({
			Text = "Claim",
			Variant = "success",
			Size = UDim2.fromOffset(110, 40),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Sound = "Purchase",
			OnClick = onClick,
			Parent = parent,
		})
	end

	-- Daily -------------------------------------------------------------------------------------
	local daily = page("Daily")
	local resetLabel = UI.label({ Text = "", TextSize = 14, TextColor3 = C.TextDim, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 0, Parent = daily })
	local dailyCards = {}
	for i = 1, Quests.DailyCount do
		local card = UI.panel({ Size = UDim2.new(1, 0, 0, 88), BackgroundColor3 = C.PanelLight, LayoutOrder = i, Parent = daily })
		local title = UI.label({ Text = "", Font = F.Heading, TextSize = 17, Size = UDim2.new(1, -150, 0, 22), Position = UDim2.fromOffset(16, 10), Parent = card })
		local reward = UI.label({ Text = "", TextSize = 13, TextColor3 = C.TextDim, Size = UDim2.new(1, -150, 0, 18), Position = UDim2.fromOffset(16, 34), Parent = card })
		local bar = UI.progress({ Size = UDim2.new(1, -160, 0, 14), Position = UDim2.fromOffset(16, 60), Color = C.Success, Parent = card })
		local claim = claimButton(card, function()
			local result = ClientNet.once("quest" .. i, "ClaimQuest", { Index = i })
			if result then
				ctx.Notifications.result(result, "Quest complete!")
			end
		end)
		dailyCards[i] = { Card = card, Title = title, Reward = reward, Bar = bar, Claim = claim }
	end
	local bonusCard = UI.panel({ Size = UDim2.new(1, 0, 0, 70), BackgroundColor3 = Theme.darken(C.Gold, 0.82), LayoutOrder = 10, Stroke = { Color = Theme.darken(C.Gold, 0.4) }, Parent = daily })
	UI.label({ Text = "⭐ Daily bonus — claim all three quests", Font = F.Heading, TextSize = 16, Size = UDim2.new(1, -150, 0, 22), Position = UDim2.fromOffset(16, 12), Parent = bonusCard })
	UI.label({ Text = describe(Quests.DailyBonus), TextSize = 13, TextColor3 = C.TextDim, Size = UDim2.new(1, -150, 0, 18), Position = UDim2.fromOffset(16, 38), Parent = bonusCard })
	local bonusClaim = claimButton(bonusCard, function()
		local result = ClientNet.once("questbonus", "ClaimQuestBonus")
		if result then
			ctx.Notifications.result(result, "Daily bonus claimed!")
		end
	end)

	-- Starter -------------------------------------------------------------------------------------
	local starter = page("Starter")
	local starterRows = {}
	for index, step in ipairs(Quests.Starter) do
		local row = UI.panel({ Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = C.PanelLight, LayoutOrder = index, Parent = starter })
		local status = UI.label({ Text = "", TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(52, 64), Parent = row })
		UI.label({ Text = step.Text, Font = F.Bold, TextSize = 15, Size = UDim2.new(1, -200, 0, 20), Position = UDim2.fromOffset(52, 10), Parent = row })
		UI.label({ Text = describe(step.Reward), TextSize = 13, TextColor3 = C.TextDim, Size = UDim2.new(1, -200, 0, 18), Position = UDim2.fromOffset(52, 34), Parent = row })
		local claim = claimButton(row, function()
			local result = ClientNet.once("starter", "ClaimStarter")
			if result then
				ctx.Notifications.result(result, "Step complete!")
			end
		end)
		local progressLabel = UI.label({
			Text = "",
			Font = F.Bold,
			TextSize = 13,
			TextColor3 = C.TextDim,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -16, 0.5, 0),
			Size = UDim2.fromOffset(120, 20),
			Parent = row,
		})
		starterRows[index] = { Row = row, Status = status, Claim = claim, Progress = progressLabel }
	end

	-- Login calendar ---------------------------------------------------------------------------------
	local login = page("Login")
	local streakLabel = UI.label({ Text = "", Font = F.Heading, TextSize = 18, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 0, Parent = login })
	local calendar = UI.frame({
		Size = UDim2.new(1, 0, 0, 170),
		LayoutOrder = 1,
		List = { Dir = "X", Pad = 8, HA = "Center" },
		Parent = login,
	})
	local dayCards = {}
	for i, entry in ipairs(Rewards.Daily) do
		local card = UI.panel({ Size = UDim2.new(1 / #Rewards.Daily, -8, 1, 0), BackgroundColor3 = C.PanelLight, LayoutOrder = i, Padding = 8, Parent = calendar })
		UI.label({ Text = `Day {entry.Day}`, Font = F.Heading, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 20), Parent = card })
		UI.label({
			Text = if i == #Rewards.Daily then "🏆" else "🎁",
			TextSize = 34,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 44),
			Position = UDim2.fromOffset(0, 22),
			Parent = card,
		})
		UI.label({
			Text = entry.Text,
			TextSize = 12,
			TextColor3 = C.TextDim,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, 0, 0, 60),
			Position = UDim2.fromOffset(0, 70),
			Parent = card,
		})
		local stateLabel = UI.label({ Text = "", Font = F.Bold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 16), AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Parent = card })
		dayCards[i] = { Card = card, State = stateLabel }
	end
	local loginClaim = UI.button({
		Text = "Claim today's reward",
		Variant = "gold",
		Size = UDim2.fromOffset(260, 46),
		LayoutOrder = 2,
		Sound = "Purchase",
		OnClick = function()
			local result = ClientNet.once("daily", "ClaimDaily")
			if result then
				ctx.Notifications.result(result, `Day {result.Day or "?"} reward claimed!`)
			end
		end,
		Parent = login,
	})
	local loginInfo = UI.label({ Text = "", TextSize = 13, TextColor3 = C.TextDim, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 3, Parent = login })

	-- Achievements -------------------------------------------------------------------------------------
	local achievementsPage = page("Achievements")
	local achSummary = UI.label({ Text = "", Font = F.Heading, TextSize = 16, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 0, Parent = achievementsPage })
	local achRows = {}
	for index, def in ipairs(Achievements.List) do
		local row = UI.panel({ Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = C.PanelLight, LayoutOrder = index, Parent = achievementsPage })
		UI.label({ Text = def.Icon, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(52, 62), Parent = row })
		local name = UI.label({ Text = def.Name, Font = F.Heading, TextSize = 15, Size = UDim2.new(0.45, -52, 0, 20), Position = UDim2.fromOffset(52, 10), Parent = row })
		UI.label({ Text = def.Description, TextSize = 12, TextColor3 = C.TextDim, Size = UDim2.new(0.45, -52, 0, 16), Position = UDim2.fromOffset(52, 33), Parent = row })
		local bar = UI.progress({ Size = UDim2.new(0.3, 0, 0, 12), Position = UDim2.new(0.45, 10, 0.5, -6), Color = C.Gold, Parent = row })
		UI.label({
			Text = describe(def.Reward),
			TextSize = 12,
			TextColor3 = C.TextDim,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.new(0.25, -24, 0, 40),
			Parent = row,
		})
		achRows[def.Id] = { Row = row, Name = name, Bar = bar, Def = def }
	end

	function screen.Refresh()
		if not window.IsOpen() then
			return
		end
		for name, frame in pairs(pages) do
			frame.Visible = name == tab
		end
		local quests = State.get("Quests") or { Daily = {} }
		local now = Util.serverTime()

		if tab == "Daily" then
			resetLabel.Text = `New quests in {Format.time(Util.secondsUntilNextDay(now))}`
			local allClaimed = #quests.Daily > 0
			for i, entry in ipairs(dailyCards) do
				local q = quests.Daily[i]
				entry.Card.Visible = q ~= nil
				if q then
					local def = Quests.DailyById[q.Id]
					entry.Title.Text = string.format(def.Text, Format.short(q.Target))
					entry.Reward.Text = "Reward: " .. describe(def.Reward)
					entry.Bar.Set(q.Progress / q.Target, `{Format.short(q.Progress)} / {Format.short(q.Target)}`)
					local done = q.Progress >= q.Target
					UI.setText(entry.Claim, if q.Claimed then "Claimed ✓" else "Claim")
					UI.setEnabled(entry.Claim, done and not q.Claimed)
					if not q.Claimed then
						allClaimed = false
					end
				end
			end
			UI.setText(bonusClaim, if quests.BonusClaimed then "Claimed ✓" else "Claim")
			UI.setEnabled(bonusClaim, allClaimed and not quests.BonusClaimed)
		elseif tab == "Starter" then
			local current = quests.StarterIndex or 1
			for index, entry in ipairs(starterRows) do
				local step = Quests.Starter[index]
				local done = index < current
				local isCurrent = index == current
				entry.Status.Text = if done then "✅" elseif isCurrent then "▶" else "🔒"
				entry.Row.BackgroundColor3 = if isCurrent then Theme.darken(C.Accent2, 0.8) else C.PanelLight
				local ready = isCurrent and (quests.StarterProgress or 0) >= step.Target
				entry.Claim.Visible = ready
				entry.Progress.Visible = isCurrent and not ready
				entry.Progress.Text = if isCurrent then `{Format.short(quests.StarterProgress or 0)} / {Format.short(step.Target)}` else ""
			end
		elseif tab == "Login" then
			local daily = State.get("Daily") or { LastClaimDay = -1, Streak = 0 }
			local today = Util.dayNumber(now)
			local claimedToday = daily.LastClaimDay == today
			local streakAlive = daily.LastClaimDay >= today - 1
			local streak = if streakAlive then daily.Streak else 0
			local nextDay = if claimedToday then ((streak - 1) % #Rewards.Daily) + 1 else (streak % #Rewards.Daily) + 1
			streakLabel.Text = `🔥 Login streak: {streak} day{if streak == 1 then "" else "s"}`
			for i, entry in ipairs(dayCards) do
				local isNext = i == nextDay
				local past = if claimedToday then i <= nextDay else i < nextDay
				entry.State.Text = if past and not (isNext and not claimedToday) then "✓ Claimed" elseif isNext then "Today" else ""
				entry.State.TextColor3 = if isNext then C.Gold else C.Success
				entry.Card.BackgroundColor3 = if isNext and not claimedToday then Theme.darken(C.Gold, 0.78) else C.PanelLight
			end
			UI.setEnabled(loginClaim, not claimedToday)
			UI.setText(loginClaim, if claimedToday then "Come back tomorrow" else "Claim today's reward")
			loginInfo.Text = if claimedToday
				then `Next reward in {Format.time(Util.secondsUntilNextDay(now))}. Missing a day resets the streak.`
				else "Claim once per UTC day. Missing a day resets the streak."
		elseif tab == "Achievements" then
			local unlocked = State.get("Achievements") or {}
			local count = 0
			for id, entry in pairs(achRows) do
				local def = entry.Def
				local done = unlocked[id] ~= nil
				if done then
					count += 1
				end
				local value = achievementValue(def.Stat)
				entry.Bar.Set(if done then 1 else value / def.Target, if done then "Unlocked ✓" else `{Format.short(value)} / {Format.short(def.Target)}`)
				entry.Name.TextColor3 = if done then C.Gold else C.Text
				entry.Row.LayoutOrder = (if done then 1000 else 0) + def.Order
			end
			achSummary.Text = `{count} / {#Achievements.List} achievements unlocked`
		end
	end

	State.subscribe({ "Quests", "Daily", "Achievements", "Stats", "Progress" }, function()
		screen.Refresh()
	end)
	window.Opened.Event:Connect(screen.Refresh)
	task.spawn(function()
		while true do
			task.wait(1)
			if window.IsOpen() and (tab == "Daily" or tab == "Login") then
				screen.Refresh()
			end
		end
	end)

	function screen.OnOpen(tabId: string?)
		if tabId and pages[tabId] then
			tab = tabId
		end
	end
	return screen
end

return QuestsScreen
