-- =====================================================================
--  AKYTEX TYCOON – Quests, Starter-Linie, Login-Kalender, Codes, Erfolge, Firmen-Album (Client/Modules/Quests)
--  Besitzer: WP9 (Fortschritt, Tutorial, Sozial, Bestenlisten). Vertrag: DESIGN.md §B9.7 (3 Tages- + 3 Wochenquests,
--  1 Gratis-Neuwürfeln je Tag mit offener Anzeige, Starter-Linie „Vom Azubi zum Millionär“, Aufhol-Quest), §B9.8
--  (60 Erfolge, Firmen-Album 43 Karten + IPO-Seite), §B9.9 (Login-Kalender deterministisch – nie Rad, 28er-Spur,
--  Serien-Schutz, kein bezahlter Retter), §C7.3 (Fenster "Quests").
--
--  Öffentliche API: keine Pflicht-API. Zusätzlich: Quests.Init(ctx), Quests.Start(), Quests.Tick() (1 s: Countdowns,
--  HUD-Badge), Quests.Open(tab?), Quests.Claimable(): number (abholbare Belohnungen, für HUD/Tutorial).
--  Anfragen: RewardQuest { Id }, RewardReroll { Id }, RewardLogin {}, RewardCode { Code }.  State: Quests, Login, Prog.
--  Belohnungen sind Spielgeld/Kosmetik (CR, Deko, Lack, Saison-XP) – nie Robux, nie Zufall.
-- =====================================================================

local UI = require(script.Parent:WaitForChild("UI"))

local Quests = {}

local Theme = UI.Theme

local WINDOW_W, WINDOW_H = 680, 620
local CODE_MAX = 20

local ctx: any = nil
local window: any = nil
local segmented: any = nil
local tab = "daily"
local pages: { [string]: Frame } = {}
local ui: { [string]: any } = {}
local badge: Frame? = nil
local busy = false
local sigs: { [string]: string } = {}

-- ---------------------------------------------------------------------
-- 1) HELFER
-- ---------------------------------------------------------------------
local function T(key: string, ...: any): string
	return ctx.T(key, ...)
end

local function lang(): string
	return ctx.Lang_()
end

local function call(name: string, fnName: string, ...: any): (boolean, any)
	local modules = ctx and ctx.Modules
	local m = modules and modules[name]
	local fn = m and m[fnName]
	if type(fn) ~= "function" then
		return false, nil
	end
	return pcall(fn, ...)
end

local function num(v: any, default: number): number
	return if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then v else default
end

local function stateOf(key: string): { [string]: any }
	local s = ctx.State[key]
	return if type(s) == "table" then s else {}
end

local function pcfg(): any
	local p = ctx.Config.Progression
	return if type(p) == "table" then p else {}
end

local function fmt(fnName: string, ...: any): string
	local fn = ctx.Format[fnName]
	if type(fn) ~= "function" then
		return tostring((...))
	end
	local ok, value = pcall(fn, ...)
	return if ok then value else tostring((...))
end

local function now(): number
	local ok, value = pcall(ctx.Clock.Now)
	return if ok and type(value) == "number" then value else os.time()
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	props.Parent = parent
	if props.TextXAlignment == nil then
		props.TextXAlignment = Enum.TextXAlignment.Left
	end
	return UI.Label(props)
end

local function clear(frame: Instance)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function listFrame(parent: Instance, order: number): Frame
	return UI.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	}, { UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }) })
end

local function newPage(key: string, order: number): Frame
	local page: Frame = UI.Create("Frame", {
		Name = "Page_" .. key,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Visible = false,
		Parent = window.Content,
	}, { UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }) })
	pages[key] = page
	return page
end

local function showTab(key: string)
	tab = key
	for name, page in pairs(pages) do
		page.Visible = name == key
	end
end

-- Anzeigename eines Belohnungs-Teils aus den Config-Tabellen der Besitzer-WPs (wie RewardService)
local function itemName(kind: string, key: string): string
	local config = ctx.Config
	local function pick(entry: any): string?
		if type(entry) == "table" and type(entry.Name) == "table" then
			return ctx.Lang.Pick(lang(), entry.Name)
		end
		return nil
	end
	local function find(list: any): any
		if type(list) == "table" then
			for _, entry in ipairs(list) do
				if type(entry) == "table" and entry.Key == key then
					return entry
				end
			end
		end
		return nil
	end
	if kind == "Decor" then
		local decor = config.Decor
		return pick(decor and decor.ByKey and decor.ByKey[key]) or key
	elseif kind == "Car" then
		return pick(find(config.Vehicles and config.Vehicles.Cars)) or key
	elseif kind == "Watch" then
		return pick(find(config.Lifestyle and config.Lifestyle.Watches)) or key
	elseif kind == "Accessory" then
		return pick(find(config.Lifestyle and config.Lifestyle.Accessories)) or key
	elseif kind == "Title" then
		return pick(pcfg().TitleByKey and pcfg().TitleByKey[key]) or key
	end
	local tower = config.Tower
	return pick(find(tower and tower.Skins))
		or pick(find(tower and tower.Neon))
		or pick(find(config.Vehicles and config.Vehicles.Paints))
		or key
end

-- Belohnung (Config-Format) -> lesbarer Text; Einkommens-CR als „n min Einkommen“ (Betrag rechnet der Server)
function Quests.DescribeReward(reward: any): string
	if type(reward) ~= "table" then
		return ""
	end
	local parts: { string } = {}
	if type(reward.Credits) == "table" then
		table.insert(parts, T("prog.rw.income", math.floor(num(reward.Credits.Minutes, 0))))
	elseif type(reward.Credits) == "number" then
		table.insert(parts, T("prog.rw.credits", fmt("Credits", reward.Credits, lang())))
	end
	if type(reward.Decor) == "table" then
		for key in pairs(reward.Decor) do
			if type(key) == "string" then
				table.insert(parts, T("prog.rw.decor", itemName("Decor", key)))
			end
		end
	end
	for _, entry in ipairs({
		{ "Cosmetics", "Cosmetic", "prog.rw.cosmetic" },
		{ "Watches", "Watch", "prog.rw.watch" },
		{ "Cars", "Car", "prog.rw.car" },
		{ "Accessories", "Accessory", "prog.rw.accessory" },
	}) do
		local list = reward[entry[1]]
		if type(list) == "table" then
			for _, key in ipairs(list) do
				if type(key) == "string" then
					table.insert(parts, T(entry[3], itemName(entry[2], key)))
				end
			end
		end
	end
	if num(reward.BoostX2, 0) > 0 then
		table.insert(parts, T("prog.rw.boost", fmt("Duration", reward.BoostX2, lang())))
	end
	if num(reward.InstantTokens, 0) > 0 then
		table.insert(parts, T("prog.rw.instant", math.floor(reward.InstantTokens)))
	end
	if num(reward.SeasonXp, 0) > 0 then
		table.insert(parts, T("prog.rw.seasonXp", math.floor(reward.SeasonXp)))
	end
	if type(reward.Title) == "string" and reward.Title ~= "" then
		table.insert(parts, T("prog.rw.title", itemName("Title", reward.Title)))
	end
	return table.concat(parts, T("prog.rw.sep"))
end

-- Fortschritt lesbar: Fahr-Ziele in km, sonst ganze Zahlen
local function progressText(kind: string?, p: number, goal: number): string
	if kind == "Drive" then
		local function km(v: number): string
			local value = string.format("%.1f", math.floor(v / 100 + 0.5) / 10)
			return if lang() == "de" then (string.gsub(value, "%.", ",")) else value
		end
		return T("prog.lbl.progress", km(p), km(goal)) .. " km"
	end
	return T("prog.lbl.progress", fmt("Int", math.floor(p), lang()), fmt("Int", math.floor(goal), lang()))
end

-- Abholbare Belohnungen (HUD-Badge)
function Quests.Claimable(): number
	local quests = stateOf("Quests")
	local count = 0
	for _, listKey in ipairs({ "Daily", "Weekly" }) do
		local list = quests[listKey]
		if type(list) == "table" then
			for _, q in ipairs(list) do
				if type(q) == "table" and q.Done and not q.Claimed then
					count += 1
				end
			end
		end
	end
	if type(quests.Starter) == "table" and quests.Starter.Done then
		count += 1
	end
	if type(quests.Comeback) == "table" and quests.Comeback.Done and not quests.Comeback.Claimed then
		count += 1
	end
	if stateOf("Login").Claimable == true then
		count += 1
	end
	return count
end

local function claim(id: string)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		ctx.RequestFull("RewardQuest", { Id = id })
		busy = false
	end)
end

local function reroll(id: string)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		ctx.RequestFull("RewardReroll", { Id = id })
		busy = false
	end)
end

-- ---------------------------------------------------------------------
-- 2) QUEST-KARTE (Tages-/Wochen-/Aufhol-Quest)
-- ---------------------------------------------------------------------
local function questCard(parent: Instance, order: number, q: { [string]: any }, allowReroll: boolean, kicker: string?)
	local card = UI.RowCard(parent, order, 92)
	local done = q.Done == true
	local claimed = q.Claimed == true
	if kicker then
		UI.Label({
			Position = UDim2.fromOffset(14, 4),
			Size = UDim2.new(1, -200, 0, 16),
			Text = UI.Upper(kicker),
			TextColor3 = Theme.Warn,
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxText = 12,
			Parent = card,
		})
	end
	UI.Label({
		Position = UDim2.fromOffset(14, if kicker then 20 else 8),
		Size = UDim2.new(1, -200, 0, 24),
		Text = tostring(q.Text or ""),
		Face = "BodyBold",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = if claimed then Theme.Muted else Theme.Text,
		MaxText = 16,
		Parent = card,
	})
	local goal = math.max(1, num(q.Goal, 1))
	local p = math.min(num(q.P, 0), goal)
	local bar = UI.Bar({
		Position = UDim2.fromOffset(14, 48),
		Size = UDim2.new(1, -200, 0, 16),
		Color = if done then Theme.Up else Theme.Accent,
		MaxText = 12,
		Parent = card,
	})
	UI.SetBar(bar, p / goal, progressText(q.Kind, p, goal))
	local xp = math.floor(num(q.Xp, 0))
	local credits = fmt("Credits", num(q.Credits, 0), lang())
	UI.Label({
		Position = UDim2.fromOffset(14, 68),
		Size = UDim2.new(1, -200, 0, 18),
		Text = if xp > 0
			then T("prog.lbl.rewardXp", credits, math.floor(num(q.SeasonXp, 0)), xp)
			else T("prog.lbl.reward", credits, math.floor(num(q.SeasonXp, 0))),
		Face = "Mono",
		TextColor3 = Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 13,
		Parent = card,
	})
	local actions = UI.RowActions(card, 180)
	local id = tostring(q.Id)
	if allowReroll and not done and not claimed then
		UI.Button({
			Size = UDim2.fromOffset(44, 40),
			Text = "↻",
			Variant = "Ghost",
			LayoutOrder = 1,
			Parent = actions,
		}, function()
			reroll(id)
		end)
	end
	UI.Button({
		Size = UDim2.fromOffset(120, 40),
		Text = if claimed then T("prog.btn.claimed") elseif done then T("prog.btn.claim") else T("prog.btn.locked"),
		Variant = if claimed then "Muted" elseif done then "Success" else "Secondary",
		LayoutOrder = 2,
		Parent = actions,
	}, function()
		if done and not claimed then
			claim(id)
		end
	end)
end

-- ---------------------------------------------------------------------
-- 3) SEITEN: Heute · Woche · Starter
-- ---------------------------------------------------------------------
local function buildDaily(page: Frame)
	ui.DayTimer = text(page, { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 1, Face = "Mono", MaxText = 15 })
	ui.RerollHint =
		text(page, { Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 2, MaxText = 13, TextColor3 = Theme.Muted })
	ui.DailyList = listFrame(page, 3)
end

local function refreshDaily()
	local quests = stateOf("Quests")
	ui.DayTimer.Text = T("prog.lbl.resetIn", fmt("Duration", num(quests.DayEndsAt, 0) - now(), lang()))
	ui.RerollHint.Text = if quests.Rerolled then "" else T("prog.lbl.rerollHint")
	local parts = { lang(), tostring(quests.Rerolled) }
	local daily = type(quests.Daily) == "table" and quests.Daily or {}
	for _, q in ipairs(daily) do
		table.insert(parts, table.concat({ q.Id, q.P, tostring(q.Done), tostring(q.Claimed), q.Credits, q.Text }, ":"))
	end
	local comeback = quests.Comeback
	if type(comeback) == "table" then
		table.insert(parts, table.concat({ "C", comeback.P, tostring(comeback.Done), comeback.Credits }, ":"))
	end
	local sig = table.concat(parts, "|")
	if sigs.Daily == sig then
		return
	end
	sigs.Daily = sig
	clear(ui.DailyList)
	local order = 0
	if type(comeback) == "table" then
		order += 1
		questCard(ui.DailyList, order, comeback, false, T("prog.lbl.comeback"))
	end
	for _, q in ipairs(daily) do
		order += 1
		questCard(ui.DailyList, order, q, not quests.Rerolled, nil)
	end
end

local function buildWeekly(page: Frame)
	ui.WeekTimer = text(page, { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 1, Face = "Mono", MaxText = 15 })
	ui.WeeklyList = listFrame(page, 2)
end

local function refreshWeekly()
	local quests = stateOf("Quests")
	ui.WeekTimer.Text = T("prog.lbl.weekIn", fmt("Duration", num(quests.WeekEndsAt, 0) - now(), lang()))
	local weekly = type(quests.Weekly) == "table" and quests.Weekly or {}
	local parts = { lang() }
	for _, q in ipairs(weekly) do
		table.insert(parts, table.concat({ q.Id, q.P, tostring(q.Done), tostring(q.Claimed), q.Credits, q.Text }, ":"))
	end
	local sig = table.concat(parts, "|")
	if sigs.Weekly == sig then
		return
	end
	sigs.Weekly = sig
	clear(ui.WeeklyList)
	for i, q in ipairs(weekly) do
		questCard(ui.WeeklyList, i, q, false, nil)
	end
end

local function buildStarter(page: Frame)
	ui.StarterTitle = text(page, {
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = 1,
		Face = "Display",
		MaxText = 18,
		TextColor3 = Theme.Gold,
	})
	ui.StarterStep = text(page, { Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 2, Face = "Mono", MaxText = 14 })
	local card = UI.Card({ Size = UDim2.new(1, 0, 0, 170), LayoutOrder = 3, Parent = page })
	ui.StarterCard = card
	ui.StarterText = UI.Label({
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.new(1, -32, 0, 28),
		Text = "",
		Face = "BodyBold",
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 19,
		Parent = card,
	})
	ui.StarterTiko = UI.Label({
		Position = UDim2.fromOffset(16, 42),
		Size = UDim2.new(1, -32, 0, 22),
		Text = "",
		Face = "Body",
		TextColor3 = Theme.Cyan,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 15,
		Parent = card,
	})
	ui.StarterBar = UI.Bar({
		Position = UDim2.fromOffset(16, 74),
		Size = UDim2.new(1, -32, 0, 20),
		Color = Theme.Gold,
		Parent = card,
	})
	ui.StarterReward = UI.Label({
		Position = UDim2.fromOffset(16, 102),
		Size = UDim2.new(1, -200, 0, 22),
		Text = "",
		Face = "Mono",
		TextColor3 = Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 14,
		Parent = card,
	})
	ui.StarterButton = UI.Button({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -12),
		Size = UDim2.fromOffset(160, 44),
		Text = T("prog.btn.claim"),
		Variant = "Success",
		Parent = card,
	}, function()
		local starter = stateOf("Quests").Starter
		if type(starter) == "table" and starter.Done then
			claim(tostring(starter.Id))
		end
	end)
	ui.StarterAll = text(page, {
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 4,
		MaxText = 15,
		TextColor3 = Theme.Up,
		Visible = false,
	})
end

local function refreshStarter()
	local starter = stateOf("Quests").Starter
	ui.StarterTitle.Text = T("prog.starterTitle")
	if type(starter) ~= "table" then
		ui.StarterCard.Visible = false
		ui.StarterStep.Text = ""
		ui.StarterAll.Visible = true
		ui.StarterAll.Text = T("prog.starterAll")
		return
	end
	ui.StarterCard.Visible = true
	ui.StarterAll.Visible = false
	local id = tostring(starter.Id)
	ui.StarterStep.Text =
		T("prog.lbl.starterStep", math.floor(num(starter.Index, 1)), math.floor(num(starter.Total, 20)))
	local goal = math.max(1, num(starter.Goal, 1))
	local goalText = if starter.Kind == "Drive"
		then fmt("Int", math.floor(goal / 1000 + 0.5), lang())
		else fmt("Int", goal, lang())
	ui.StarterText.Text = T("prog.st." .. id, goalText)
	ui.StarterTiko.Text = "Tiko: " .. T("prog.st." .. id .. ".tiko")
	local p = math.min(num(starter.P, 0), goal)
	UI.SetBar(ui.StarterBar, p / goal, progressText(starter.Kind, p, goal))
	local reward = T("prog.rw.credits", fmt("Credits", num(starter.Credits, 0), lang()))
	if type(starter.Title) == "string" and starter.Title ~= "" then
		reward ..= T("prog.rw.sep") .. T("prog.rw.title", itemName("Title", starter.Title))
	end
	ui.StarterReward.Text = reward
	ui.StarterButton.SetText(if starter.Done then T("prog.btn.claim") else T("prog.btn.locked"))
	ui.StarterButton.SetVariant(if starter.Done then "Success" else "Muted")
end

-- ---------------------------------------------------------------------
-- 4) LOGIN-KALENDER + CODES
-- ---------------------------------------------------------------------
local function buildLogin(page: Frame)
	ui.LoginInfo =
		text(page, { Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 1, MaxText = 13, TextColor3 = Theme.Muted })
	local stats = UI.Row(page, 2, 26)
	ui.LoginStreak = text(stats, { Size = UDim2.new(0.25, -6, 1, 0), Face = "Mono", MaxText = 14, LayoutOrder = 1 })
	ui.LoginBest = text(stats, { Size = UDim2.new(0.25, -6, 1, 0), Face = "Mono", MaxText = 14, LayoutOrder = 2 })
	ui.LoginFreeze = text(stats, { Size = UDim2.new(0.25, -6, 1, 0), Face = "Mono", MaxText = 14, LayoutOrder = 3 })
	ui.LoginTrack = text(stats, { Size = UDim2.new(0.25, -6, 1, 0), Face = "Mono", MaxText = 14, LayoutOrder = 4 })
	local grid = UI.Grid(page, 3, 86, 110)
	ui.LoginTiles = {}
	local cycle = ctx.Config.Rewards and ctx.Config.Rewards.Login and ctx.Config.Rewards.Login.Cycle or {}
	for i, reward in ipairs(cycle) do
		local tile = UI.Card({ LayoutOrder = i, Parent = grid })
		local day = UI.Label({
			Position = UDim2.fromOffset(6, 6),
			Size = UDim2.new(1, -12, 0, 20),
			Text = T("prog.lbl.day", i),
			Face = "Display",
			MaxText = 14,
			Parent = tile,
		})
		local body = UI.Label({
			Position = UDim2.fromOffset(6, 30),
			Size = UDim2.new(1, -12, 1, -36),
			Text = "",
			Face = "Body",
			TextWrapped = true,
			TextColor3 = Theme.Text2,
			TextYAlignment = Enum.TextYAlignment.Top,
			MaxText = 12,
			Parent = tile,
		})
		local stroke = tile:FindFirstChildOfClass("UIStroke")
		ui.LoginTiles[i] = { Tile = tile, Day = day, Body = body, Stroke = stroke, Reward = reward }
	end
	ui.LoginTrackInfo = text(page, {
		Size = UDim2.new(1, 0, 0, 40),
		LayoutOrder = 4,
		Face = "Body",
		TextWrapped = true,
		MaxText = 13,
		TextColor3 = Theme.Text2,
	})
	ui.LoginReset =
		text(page, { Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 5, MaxText = 13, TextColor3 = Theme.Warn })
	local row = UI.Row(page, 6, 46)
	ui.LoginButton = UI.Button({
		Size = UDim2.fromOffset(220, 44),
		Text = T("prog.btn.claim"),
		Variant = "Success",
		Parent = row,
	}, function()
		if busy or stateOf("Login").Claimable ~= true then
			return
		end
		busy = true
		task.spawn(function()
			ctx.RequestFull("RewardLogin", {})
			busy = false
		end)
	end)
	ui.LoginNext = text(row, { Size = UDim2.new(1, -240, 1, 0), Face = "Mono", MaxText = 14, TextColor3 = Theme.Text2 })
	UI.Section(page, T("prog.btn.redeem"), 7, Theme.Purple)
	local codeRow = UI.Row(page, 8, 46)
	ui.Code = UI.TextBox({
		Size = UDim2.new(1, -170, 1, 0),
		PlaceholderText = T("prog.lbl.codePlaceholder"),
		Text = "",
		Parent = codeRow,
	})
	ui.Code:GetPropertyChangedSignal("Text"):Connect(function()
		local raw = ui.Code.Text
		local clean = string.sub(string.gsub(raw, "[^%w_]", ""), 1, CODE_MAX)
		if clean ~= raw then
			ui.Code.Text = clean
		end
	end)
	UI.Button({
		Size = UDim2.fromOffset(150, 44),
		Text = T("prog.btn.redeem"),
		Variant = "Primary",
		Parent = codeRow,
	}, function()
		local code = ui.Code.Text
		if busy or #code < 1 then
			return
		end
		busy = true
		task.spawn(function()
			local reply = ctx.RequestFull("RewardCode", { Code = code })
			busy = false
			if reply.Ok then
				ui.Code.Text = ""
			end
		end)
	end)
end

local function refreshLogin()
	local login = stateOf("Login")
	local rewards = ctx.Config.Rewards and ctx.Config.Rewards.Login or {}
	ui.LoginInfo.Text = T("prog.loginInfo")
	ui.LoginStreak.Text = T("prog.lbl.streak", math.floor(num(login.Streak, 0)))
	ui.LoginBest.Text = T("prog.lbl.best", math.floor(num(login.Best, 0)))
	ui.LoginFreeze.Text = T("prog.lbl.freeze", math.floor(num(login.Freeze, 0)))
	ui.LoginTrack.Text = T("prog.lbl.track", math.floor(num(login.Track, 0)))
	local nextDay = math.floor(num(login.NextDay, 1))
	local cycle = math.floor(num(login.NextCycle, 1))
	local claimable = login.Claimable == true
	for i, tile in ipairs(ui.LoginTiles) do
		local reward = tile.Reward
		if i == #ui.LoginTiles and cycle >= 2 and type(reward.Repeat) == "table" then
			reward = reward.Repeat
		end
		tile.Body.Text = Quests.DescribeReward(reward)
		local isNext = i == nextDay
		local past = i < nextDay
		tile.Day.Text = if isNext and claimable then T("prog.lbl.today") else T("prog.lbl.day", i)
		tile.Day.TextColor3 = if isNext then Theme.Up elseif past then Theme.Muted else Theme.Text
		if tile.Stroke then
			tile.Stroke.Color = if isNext then Theme.Up else Theme.Border
			tile.Stroke.Thickness = if isNext then 2 else 1
		end
		tile.Tile.BackgroundTransparency = if past then 0.4 else 0
	end
	local track = {}
	for _, milestone in ipairs(rewards.Track or {}) do
		table.insert(track, T("prog.lbl.day", milestone.Day) .. ": " .. Quests.DescribeReward(milestone))
	end
	ui.LoginTrackInfo.Text = table.concat(track, "  ·  ")
	ui.LoginReset.Text = if login.WillReset then T("prog.loginWillReset") else ""
	ui.LoginButton.SetText(if claimable then T("prog.btn.claim") else T("prog.btn.claimed"))
	ui.LoginButton.SetVariant(if claimable then "Success" else "Muted")
	ui.LoginNext.Text = if claimable
		then ""
		else T("prog.lbl.resetIn", fmt("Duration", num(login.NextAt, 0) - now(), lang()))
end

-- ---------------------------------------------------------------------
-- 5) ERFOLGE (60, 6 Kategorien) + FIRMEN-ALBUM
-- ---------------------------------------------------------------------
local function buildAchievements(page: Frame)
	ui.AchCount = text(page, { Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1, Face = "BodyBold", MaxText = 16 })
	ui.AchRows = {}
	local order = 1
	local cats = pcfg().AchievementCats or {}
	for _, cat in ipairs(cats) do
		order += 1
		UI.Section(page, T("prog.achCat." .. cat), order, Theme.Gold)
		for _, def in ipairs(pcfg().Achievements or {}) do
			if def.Cat == cat then
				order += 1
				local card = UI.RowCard(page, order, 58)
				local mark = UI.Label({
					Position = UDim2.fromOffset(10, 0),
					Size = UDim2.fromOffset(30, 58),
					Text = "○",
					TextColor3 = Theme.Muted,
					MaxText = 22,
					Parent = card,
				})
				local name = UI.Label({
					Position = UDim2.fromOffset(46, 6),
					Size = UDim2.new(1, -200, 0, 24),
					Text = ctx.Lang.Pick(lang(), def.Name),
					Face = "BodyBold",
					TextXAlignment = Enum.TextXAlignment.Left,
					MaxText = 16,
					Parent = card,
				})
				local goalText = fmt("Int", def.Goal, lang())
				local desc = UI.Label({
					Position = UDim2.fromOffset(46, 30),
					Size = UDim2.new(1, -200, 0, 20),
					Text = T("prog.ach.stat." .. def.Stat, goalText),
					Face = "Body",
					TextColor3 = Theme.Text2,
					TextXAlignment = Enum.TextXAlignment.Left,
					MaxText = 13,
					Parent = card,
				})
				local bar = UI.Bar({
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -12, 0.5, 0),
					Size = UDim2.fromOffset(140, 18),
					Color = Theme.Gold,
					MaxText = 12,
					Parent = card,
				})
				ui.AchRows[def.Id] = { Def = def, Mark = mark, Name = name, Desc = desc, Bar = bar }
			end
		end
	end
end

local function refreshAchievements()
	local p = stateOf("Prog")
	local done = type(p.Ach) == "table" and p.Ach or {}
	local stats = type(p.AchProgress) == "table" and p.AchProgress or {}
	local total, count = 0, 0
	for id, row in pairs(ui.AchRows) do
		total += 1
		local def = row.Def
		local isDone = done[id] ~= nil and done[id] ~= false
		if isDone then
			count += 1
		end
		local goal = math.max(1, num(def.Goal, 1))
		local value = math.min(num(stats[def.Stat], 0), goal)
		row.Mark.Text = if isDone then "✓" else "○"
		row.Mark.TextColor3 = if isDone then Theme.Gold else Theme.Muted
		row.Name.TextColor3 = if isDone then Theme.Gold else Theme.Text
		row.Name.Text = ctx.Lang.Pick(lang(), def.Name)
		row.Desc.Text = T("prog.ach.stat." .. def.Stat, fmt("Int", goal, lang()))
		UI.SetBar(
			row.Bar,
			if isDone then 1 else value / goal,
			if isDone then "✓" else fmt("Int", math.floor(value), lang()) .. " / " .. fmt("Int", goal, lang())
		)
	end
	ui.AchCount.Text = T("prog.lbl.achCount", count, total)
end

local function buildAlbum(page: Frame)
	ui.AlbumCount = text(page, { Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1, Face = "BodyBold", MaxText = 16 })
	ui.AlbumTiles = {}
	local companies = ctx.Config.Companies or {}
	local byId = companies.ById or {}
	local sectors = companies.Sectors or {}
	local cards = pcfg().Album and pcfg().Album.Cards or {}
	local order = 1
	local placed: { [number]: boolean } = {}
	local function addSection(title: string, color: Color3, ids: { number })
		if #ids == 0 then
			return
		end
		order += 1
		UI.Section(page, title, order, color)
		order += 1
		local grid = UI.Grid(page, order, 92, 54)
		for i, id in ipairs(ids) do
			placed[id] = true
			local inst = byId[id]
			local tile = UI.Card({ LayoutOrder = i, Parent = grid })
			local ticker = UI.Label({
				Position = UDim2.fromOffset(6, 6),
				Size = UDim2.new(1, -12, 0, 22),
				Text = if type(inst) == "table" then tostring(inst.Ticker) else tostring(id),
				Face = "MonoBold",
				MaxText = 16,
				Parent = tile,
			})
			local name = UI.Label({
				Position = UDim2.fromOffset(6, 30),
				Size = UDim2.new(1, -12, 0, 16),
				Text = if type(inst) == "table" and type(inst.Name) == "string" then inst.Name else "",
				TextColor3 = Theme.Muted,
				MaxText = 11,
				Parent = tile,
			})
			ui.AlbumTiles[id] = { Tile = tile, Ticker = ticker, Name = name, Color = color }
		end
	end
	for _, sector in ipairs(sectors) do
		local ids: { number } = {}
		for _, id in ipairs(cards) do
			local inst = byId[id]
			if type(inst) == "table" and inst.Sector == sector.Key then
				table.insert(ids, id)
			end
		end
		addSection(ctx.Lang.Pick(lang(), sector.Name), sector.Color or Theme.Accent, ids)
	end
	local rest: { number } = {}
	for _, id in ipairs(cards) do
		if not placed[id] then
			table.insert(rest, id)
		end
	end
	addSection("ETF", Theme.Cyan, rest)
	order += 1
	UI.Section(page, T("prog.lbl.albumIpo"), order, Theme.Gold)
	order += 1
	ui.AlbumIpo = text(page, {
		Size = UDim2.new(1, 0, 0, 40),
		LayoutOrder = order,
		Face = "Mono",
		TextWrapped = true,
		MaxText = 14,
		TextColor3 = Theme.Gold,
	})
end

local function refreshAlbum()
	local p = stateOf("Prog")
	local album = type(p.Album) == "table" and p.Album or {}
	local cfgAlbum = pcfg().Album or {}
	local owned = 0
	local total = 0
	for id, tile in pairs(ui.AlbumTiles) do
		total += 1
		local has = album[tostring(id)] == true
		if has then
			owned += 1
		end
		tile.Tile.BackgroundColor3 = if has then tile.Color else Theme.Surface2
		tile.Tile.BackgroundTransparency = if has then 0.55 else 0
		tile.Ticker.TextColor3 = if has then Theme.Text else Theme.Muted
	end
	ui.AlbumCount.Text = T("prog.lbl.albumCount", owned, total, math.floor(num(p.AlbumSets, 0)))
	local ipos: { string } = {}
	local byId = ctx.Config.Companies and ctx.Config.Companies.ById or {}
	for key in pairs(album) do
		local id = tonumber(key)
		if id and id >= num(cfgAlbum.IpoFrom, 100) and id <= num(cfgAlbum.IpoTo, 139) then
			local inst = byId[id]
			table.insert(ipos, if type(inst) == "table" then tostring(inst.Ticker) else tostring(id))
		end
	end
	table.sort(ipos)
	ui.AlbumIpo.Text = if #ipos > 0 then table.concat(ipos, " · ") else "—"
end

-- ---------------------------------------------------------------------
-- 6) FENSTER + HUD-BADGE
-- ---------------------------------------------------------------------
local function refreshBadge()
	if not badge then
		local ok, button = call("Hud", "RightButton", "Quests")
		if ok and type(button) == "table" and button.Button then
			badge = UI.Badge(button, "")
		end
	end
	local b = badge
	if b then
		local count = Quests.Claimable()
		UI.SetBadge(b, if count > 0 then tostring(count) else nil, Theme.Up, count > 0)
	end
end

function Quests.Refresh()
	refreshBadge()
	if not window or not window.IsOpen then
		return
	end
	if tab == "daily" then
		refreshDaily()
	elseif tab == "weekly" then
		refreshWeekly()
	elseif tab == "starter" then
		refreshStarter()
	elseif tab == "login" then
		refreshLogin()
	elseif tab == "ach" then
		refreshAchievements()
	elseif tab == "album" then
		refreshAlbum()
	end
end

local function buildWindow()
	window = UI.Window(T("prog.win.quests"), WINDOW_W, WINDOW_H, Theme.Up)
	segmented = UI.Segmented(window.Content, {
		{ Key = "daily", Text = T("prog.tab.daily") },
		{ Key = "weekly", Text = T("prog.tab.weekly") },
		{ Key = "starter", Text = T("prog.tab.starter") },
		{ Key = "login", Text = T("prog.tab.login") },
		{ Key = "ach", Text = T("prog.tab.ach") },
		{ Key = "album", Text = T("prog.tab.album") },
	}, function(key: string)
		showTab(key)
		Quests.Refresh()
	end)
	segmented.Frame.LayoutOrder = 0
	buildDaily(newPage("daily", 1))
	buildWeekly(newPage("weekly", 2))
	buildStarter(newPage("starter", 3))
	buildLogin(newPage("login", 4))
	buildAchievements(newPage("ach", 5))
	buildAlbum(newPage("album", 6))
	showTab(tab)
end

local function openWindow()
	if not window then
		buildWindow()
	end
	-- Abholbares zuerst zeigen (Login vor Quests)
	if stateOf("Login").Claimable == true and tab == "daily" then
		tab = "login"
	end
	segmented.Set(tab, true)
	showTab(tab)
	UI.OpenWindow(window)
	Quests.Refresh()
end

local function closeWindow()
	if window and window.IsOpen then
		UI.CloseWindow(window)
	end
end

function Quests.Open(which: string?)
	if
		type(which) == "string" and (which == "daily" or which == "weekly" or which == "starter" or which == "login")
	then
		tab = which
	end
	ctx.Windows.Open("Quests")
end

function Quests.Tick()
	refreshBadge()
	if window and window.IsOpen and (tab == "daily" or tab == "weekly" or tab == "login") then
		Quests.Refresh()
	end
end

function Quests.Init(context: any)
	ctx = context
	ctx.Windows.Register("Quests", openWindow, closeWindow)
end

function Quests.Start()
	ctx.Hooks.On("State", function(_state: any, changed: any)
		if type(changed) ~= "table" then
			return
		end
		if changed.Quests or changed.Login or changed.Prog then
			Quests.Refresh()
		end
	end)
	ctx.Hooks.On("Settings", function()
		table.clear(sigs)
		Quests.Refresh()
	end)
end

return Quests
