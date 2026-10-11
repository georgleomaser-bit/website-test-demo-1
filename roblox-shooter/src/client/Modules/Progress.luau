-- =====================================================================
--  CLUTCH CLASH – Fortschritts-Fenster: Quests, Clutch Pass, Täglich (Login, Glücksrad, Geschenke,
--  Codes, Einladen), Statistik + Gratis-Waffen-Wahl, Level-Up-Karte (Client/Modules/Progress)
--  Besitzer: WP8 (Fortschritt). Vertrag: DESIGN.md C7.3/C7.4 + B16 + B21.2 + B24.
--
--  Öffentliche API (C7.4):
--    Progress.Open(tab: "Quests" | "Pass" | "Daily" | "Stats")
--    Progress.Init(ctx) / Progress.Start()
--  Fenster (ctx.Windows): "Quests", "Pass", "Daily" (C7.3) + zusätzlich "Stats" (Statistik/Erfolge/Waffen-Wahl).
--  Liest nur ctx.State (Level, XP, XPNext, Stats, Quests, Login, Daily, Pass, Season, Achievements, Honor,
--  Mastery, FreeWeaponPicks) und schickt Requests (ClaimQuest, RerollQuest, ClaimLogin, SpinWheel, ClaimGift,
--  ClaimPass, ClaimLevelPick, RedeemCode). Der Server prüft alles; das UI schreibt nur bei Wertänderung.
--  Hooks: "State", "Effect:LevelUp" (Belohnungskarte; Blitz/Konfetti macht WP10-Effects).
--  Freund-Toast (Effect "Friend") zeigt WP10-Effects; der Einladen-Knopf sitzt im Fenster "Täglich".
-- =====================================================================

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")

local ProgressMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ProgressMath"))

local Progress = {}

local ctx: any = nil
local UI: any = nil
local Config: any = nil
local P: any = nil

local WINDOW_W, WINDOW_H = 660, 580
local MY_KEYS = {
	"Level",
	"XP",
	"XPNext",
	"Stats",
	"Quests",
	"Login",
	"Daily",
	"Pass",
	"Season",
	"Achievements",
	"Honor",
	"Mastery",
	"FreeWeaponPicks",
	"Weapons",
	"OwnedWeapons",
}
local TABS = { "Quests", "Pass", "Daily", "Stats" }
local TAB_ICONS = { Quests = "📜", Pass = "🎟️", Daily = "🎁", Stats = "📊" }
local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }
local LEVEL_CARD_TIME = 4.5

type View = { Win: any, Refresh: () -> (), Tick: (() -> ())? }
local views: { [string]: View } = {}
local hudButtons: { [string]: any } = {}
local hudBadges: { [string]: any } = {}
local levelCard: Frame? = nil
local levelCardToken = 0
local tickAcc = 0

-- ---------------------------------------------------------------------
-- 0) HELFER
-- ---------------------------------------------------------------------
local function T(key: string, ...: any): string
	return ctx.T(key, ...)
end

local function num(v: any, default: number): number
	if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then
		return v
	end
	return default
end

local function state(key: string): any
	local value = ctx.State[key]
	return if type(value) == "table" then value else nil
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function formatTime(seconds: number): string
	return ctx.Util.FormatTime(math.max(0, seconds))
end

local function fmt(n: number): string
	return ctx.Util.FormatNumber(n)
end

local function pick(t: any): string
	if type(t) == "table" then
		return ctx.Lang.Pick(ctx.Lang_(), t)
	end
	return tostring(t)
end

local function cosmeticName(id: string): string
	local cosmetics = Config.Cosmetics
	local def = cosmetics and cosmetics.ById and cosmetics.ById[id]
	if type(def) == "table" and type(def.Name) == "table" then
		return pick(def.Name)
	end
	return id
end

local function describe(reward: any): string
	return ProgressMath.DescribeReward(reward, T, cosmeticName)
end

local function weaponName(key: string): string
	local def = Config.Weapon(key)
	if def and type(def.Name) == "table" then
		return pick(def.Name)
	end
	return key
end

local function setText(label: TextLabel, text: string)
	if label.Text ~= text then
		label.Text = text
	end
end

local function setVisible(inst: GuiObject, on: boolean)
	if inst.Visible ~= on then
		inst.Visible = on
	end
end

local function request(action: string, arg: any?): any
	local ok, result = pcall(ctx.Request, action, arg)
	if ok then
		return result
	end
	return nil
end

local function percent(part: number, total: number): string
	if total <= 0 then
		return "–"
	end
	return ("%d %%"):format(math.floor(part / total * 100 + 0.5))
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	props.Parent = parent
	if props.TextXAlignment == nil then
		props.TextXAlignment = Enum.TextXAlignment.Left
	end
	if props.Outline == nil then
		props.Outline = 2
	end
	return UI.Label(props)
end

local function activeSeasonConfig(): any
	local season = state("Season")
	local list = Config.Season and Config.Season.Seasons
	if type(list) ~= "table" then
		return nil
	end
	local id = season and season.Id
	for _, s in ipairs(list) do
		if s.Id == id then
			return s
		end
	end
	return ProgressMath.PickSeason(list, os.time())
end

-- ---------------------------------------------------------------------
-- 1) GERÜST: Fenster mit Reiter-Zeile
-- ---------------------------------------------------------------------
local function tabRow(win: any, current: string)
	local row = UI.Row(win.Content, 0, 48)
	for i, name in ipairs(TABS) do
		local selected = name == current
		UI.Button({
			Size = UDim2.new(0.25, -6, 1, -4),
			LayoutOrder = i,
			Parent = row,
			Text = TAB_ICONS[name] .. " " .. T("prog.ui.tab" .. name),
			Color = if selected then UI.Theme.Yellow else UI.Theme.Blue,
			MaxText = 20,
		}, function()
			if not selected then
				Progress.Open(name)
			end
		end)
	end
end

local function newWindow(name: string, titleKey: string, color: Color3): any
	local win = UI.Window(T(titleKey), WINDOW_W, WINDOW_H, color)
	tabRow(win, name)
	return win
end

-- Quest-/Belohnungs-Karte mit Text, Balken und Knopf rechts
type QuestCard = {
	Frame: Frame,
	Title: TextLabel,
	Reward: TextLabel,
	Bar: any,
	Claim: any,
	Reroll: any?,
}

local function questCard(
	parent: Instance,
	order: number,
	withReroll: boolean,
	onClaim: () -> (),
	onReroll: (() -> ())?
): QuestCard
	local frame = UI.Card({ Size = UDim2.new(1, -6, 0, 92), LayoutOrder = order, Parent = parent })
	local title = label(frame, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -200, 0, 28), MaxText = 22 })
	local reward = label(frame, {
		Position = UDim2.fromOffset(12, 34),
		Size = UDim2.new(1, -200, 0, 20),
		MaxText = 16,
		TextColor3 = UI.Theme.Yellow,
	})
	local bar = UI.Bar({
		Position = UDim2.fromOffset(12, 58),
		Size = UDim2.new(1, -200, 0, 24),
		Parent = frame,
		Color = UI.Theme.Green,
	})
	local claim = UI.Button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(170, 52),
		Parent = frame,
		Text = T("prog.ui.claim"),
		Color = UI.Theme.Green,
		MaxText = 20,
	}, onClaim)
	local reroll = nil
	if withReroll and onReroll then
		reroll = UI.Button({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(170, 52),
			Parent = frame,
			Text = T("prog.ui.reroll"),
			Color = UI.Theme.Purple,
			MaxText = 18,
			SubMax = 14,
		}, onReroll)
	end
	return { Frame = frame, Title = title, Reward = reward, Bar = bar, Claim = claim, Reroll = reroll }
end

-- Zustand einer Quest-Karte setzen (P/Goal/Claimed)
local function showQuest(
	card: QuestCard,
	text: string,
	rewardText: string,
	p: number,
	goal: number,
	claimed: boolean,
	rerollText: string?
)
	setText(card.Title, text)
	setText(card.Reward, rewardText)
	UI.SetBar(card.Bar, if goal > 0 then p / goal else 0, ("%s / %s"):format(fmt(math.floor(p)), fmt(goal)))
	local done = p >= goal
	if claimed then
		card.Claim.SetText("✓ " .. T("prog.ui.claimed"))
		card.Claim.SetColor(UI.Theme.Gray)
	else
		card.Claim.SetText(T("prog.ui.claim"))
		card.Claim.SetColor(UI.Theme.Green)
	end
	setVisible(card.Claim.Frame, claimed or done or card.Reroll == nil)
	if card.Reroll then
		setVisible(card.Reroll.Frame, not claimed and not done)
		if rerollText then
			card.Reroll.SetSub(rerollText)
		end
	end
end

-- ---------------------------------------------------------------------
-- 2) QUESTS (Anfänger-Kette, 3 täglich, 5 wöchentlich)
-- ---------------------------------------------------------------------
local function buildQuests(): View
	local win = newWindow("Quests", "prog.ui.questsTitle", UI.Theme.Orange)
	local content = win.Content
	local dayTimer = label(content, { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 1, MaxText = 16 })

	UI.Section(content, T("prog.ui.beginner"), 2, UI.Theme.Cyan)
	local beginnerCard = questCard(content, 3, false, function()
		local quests = state("Quests")
		local id = quests and quests.Beginner and quests.Beginner.Id
		if type(id) == "string" and id ~= "" then
			request("ClaimQuest", id)
		end
	end)

	UI.Section(content, T("prog.ui.daily"), 10)
	local dailyCards: { QuestCard } = {}
	for i = 1, 3 do
		dailyCards[i] = questCard(content, 10 + i, true, function()
			local quests = state("Quests")
			local q = quests and quests.Daily and quests.Daily[i]
			if q then
				request("ClaimQuest", q.Id)
			end
		end, function()
			request("RerollQuest", i)
		end)
	end
	local dailyBonus = label(content, { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 20, MaxText = 16 })

	local weeklyHeader = UI.Section(content, T("prog.ui.weekly"), 30)
	local weeklyCards: { QuestCard } = {}
	for i = 1, 8 do
		weeklyCards[i] = questCard(content, 30 + i, false, function()
			local quests = state("Quests")
			local q = quests and quests.Weekly and quests.Weekly[i]
			if q then
				request("ClaimQuest", q.Id)
			end
		end)
	end
	local chest = label(content, { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 50, MaxText = 16 })

	local function tick()
		local quests = state("Quests")
		if quests then
			setText(dayTimer, T("prog.ui.dayReset", formatTime(num(quests.DayEndsAt, 0) - serverNow())))
			setText(
				weeklyHeader,
				T("prog.ui.weekly")
					.. "  ·  "
					.. T("prog.ui.weekReset", formatTime(num(quests.WeekEndsAt, 0) - serverNow()))
			)
		end
	end

	local function refresh()
		local quests = state("Quests")
		if not quests then
			return
		end
		-- Anfänger
		local b = quests.Beginner
		local beginnerDone = type(b) ~= "table" or b.Done == true
		setVisible(beginnerCard.Frame, not beginnerDone)
		if not beginnerDone then
			local reward: { [string]: any } = { Coins = b.Coins }
			if num(b.FreePick, 0) > 0 then
				reward.FreePick = b.FreePick
			end
			showQuest(
				beginnerCard,
				("%d/%d · %s"):format(num(b.Step, 1), num(b.Total, 10), T("prog.q." .. tostring(b.Id), num(b.Goal, 1))),
				describe(reward),
				num(b.P, 0),
				num(b.Goal, 1),
				false
			)
		end
		-- Täglich
		local dailyCfg = P.Quests.DailyRewards
		local rerolls = num(quests.Rerolls, 0)
		local rerollText = if rerolls > 0
			then T("prog.ui.rerollFree", rerolls)
			else T("prog.r.coins", num(quests.RerollCoins, 100))
		for i, card in ipairs(dailyCards) do
			local q = quests.Daily and quests.Daily[i]
			setVisible(card.Frame, q ~= nil)
			if q then
				local reward = dailyCfg[q.Tier or "Easy"] or dailyCfg.Easy
				showQuest(
					card,
					T("prog.tier." .. tostring(q.Tier or "Easy")) .. " · " .. T("prog.q." .. q.Id, q.Goal),
					describe({ Coins = reward.Coins, PassXp = reward.PassXp }),
					num(q.P, 0),
					num(q.Goal, 1),
					q.Claimed == true,
					rerollText
				)
			end
		end
		setText(
			dailyBonus,
			if quests.DailyBonus then "✓ " .. T("prog.ui.dailyBonusDone") else T("prog.ui.dailyBonus")
		)
		-- Wöchentlich
		local weeklyCfg = P.Quests.WeeklyReward
		for i, card in ipairs(weeklyCards) do
			local q = quests.Weekly and quests.Weekly[i]
			setVisible(card.Frame, q ~= nil)
			if q then
				showQuest(
					card,
					T("prog.q." .. q.Id, q.Goal),
					describe({ Coins = weeklyCfg.Coins, PassXp = weeklyCfg.PassXp }),
					num(q.P, 0),
					num(q.Goal, 1),
					q.Claimed == true
				)
			end
		end
		setText(
			chest,
			if quests.WeeklyChest
				then "✓ " .. T("prog.ui.chestDone")
				else T("prog.ui.chest", describe(P.Quests.WeeklyChest))
		)
		tick()
	end
	return { Win = win, Refresh = refresh, Tick = tick }
end

-- ---------------------------------------------------------------------
-- 3) CLUTCH PASS (30 Stufen, Gratis + Premium, rückwirkend)
-- ---------------------------------------------------------------------
local function premiumProductId(): number
	local products = Config.Shop and Config.Shop.Products
	if type(products) == "table" then
		for _, product in ipairs(products) do
			if product.Key == "PassPremium" then
				return num(product.Id, 0)
			end
		end
	end
	return 0
end

local function buyPremium()
	local id = premiumProductId()
	if id > 0 then
		local ok, err = pcall(function()
			MarketplaceService:PromptProductPurchase(ctx.Player, id)
		end)
		if not ok then
			warn("[Progress] Pass-Kauf: " .. tostring(err))
		end
		return
	end
	local shop = ctx.Modules.Shop
	if shop and type(shop.Open) == "function" then
		pcall(shop.Open, "Pass")
	else
		ctx.Toast(T("prog.ui.notSetUp"), "Info")
	end
end

local function buildPass(): View
	local win = newWindow("Pass", "prog.ui.passTitle", UI.Theme.Pink)
	local content = win.Content
	local seasonLabel =
		label(content, { Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 1, MaxText = 22, TextColor3 = UI.Theme.Cyan })
	local endsLabel = label(content, { Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 2, MaxText = 16 })
	local bar = UI.Bar({ Size = UDim2.new(1, -6, 0, 30), LayoutOrder = 3, Parent = content, Color = UI.Theme.Pink })
	local premiumRow = UI.Row(content, 4, 56)
	local premiumButton = UI.Button({
		Size = UDim2.new(1, -6, 1, -4),
		Parent = premiumRow,
		Text = T("prog.ui.passBuy"),
		Color = UI.Theme.Gold,
		MaxText = 22,
	}, buyPremium)
	local note =
		label(content, { Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 5, MaxText = 14, TextColor3 = UI.Theme.SubText })
	note.Text = T("prog.ui.passNote")

	type TierRow = { Frame: Frame, Tier: TextLabel, Free: any, Prem: any }
	local rows: { TierRow } = {}
	local built = 0

	local function claim(tier: number, track: string)
		request("ClaimPass", { Tier = tier, Track = track })
	end

	local function ensureRows(count: number)
		-- Zeilen nur einmal bauen (max. 100 Stufen)
		for tier = built + 1, math.min(count, 100) do
			local frame = UI.Card({ Size = UDim2.new(1, -6, 0, 62), LayoutOrder = 10 + tier, Parent = content })
			local tierLabel = label(frame, {
				Position = UDim2.fromOffset(8, 0),
				Size = UDim2.new(0, 80, 1, 0),
				Text = T("prog.ui.tier", tier),
				MaxText = 18,
				TextXAlignment = Enum.TextXAlignment.Center,
			})
			local free = UI.Button({
				Position = UDim2.new(0, 94, 0.5, -26),
				Size = UDim2.new(0.5, -60, 0, 52),
				Parent = frame,
				Text = "",
				Sub = "",
				Color = UI.Theme.Blue,
				MaxText = 16,
				SubMax = 13,
			}, function()
				claim(tier, "Free")
			end)
			local prem = UI.Button({
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -8, 0.5, -26),
				Size = UDim2.new(0.5, -60, 0, 52),
				Parent = frame,
				Text = "",
				Sub = "",
				Color = UI.Theme.Purple,
				MaxText = 16,
				SubMax = 13,
			}, function()
				claim(tier, "Premium")
			end)
			rows[tier] = { Frame = frame, Tier = tierLabel, Free = free, Prem = prem }
			built = tier
		end
	end

	local function showCell(
		button: any,
		reward: any,
		reached: boolean,
		claimed: boolean,
		locked: boolean,
		tier: number,
		baseColor: Color3
	)
		if type(reward) ~= "table" then
			setVisible(button.Frame, false)
			return
		end
		setVisible(button.Frame, true)
		button.SetText(describe(reward))
		if claimed then
			button.SetSub("✓ " .. T("prog.ui.claimed"))
			button.SetColor(UI.Theme.Gray)
		elseif locked then
			button.SetSub("🔒 " .. T("prog.ui.premium"))
			button.SetColor(baseColor:Lerp(UI.Theme.Gray, 0.5))
		elseif reached then
			button.SetSub(T("prog.ui.claim") .. "!")
			button.SetColor(UI.Theme.Green)
		else
			button.SetSub(T("prog.ui.tier", tier))
			button.SetColor(baseColor)
		end
	end

	local function tick()
		local season = state("Season")
		if season then
			setText(endsLabel, T("prog.ui.seasonEnds", formatTime(num(season.EndsAt, 0) - serverNow())))
		end
	end

	local function refresh()
		local season = state("Season")
		local pass = state("Pass")
		local cfg = activeSeasonConfig()
		if not season or not pass or not cfg then
			return
		end
		setText(seasonLabel, pick(season.Name))
		local tiers = num(season.Tiers, 30)
		local tierXp = math.max(1, num(season.TierXp, 3000))
		local tier = num(pass.Tier, 0)
		local xp = num(pass.XP, 0)
		local inTier = if tier >= tiers then tierXp else xp - tier * tierXp
		UI.SetBar(bar, inTier / tierXp, T("prog.ui.passBar", tier, tiers, fmt(math.floor(inTier)), fmt(tierXp)))
		setVisible(premiumRow, not pass.Premium)
		premiumButton.SetText(T("prog.ui.passBuy"))
		ensureRows(tiers)
		for i = 1, built do
			local row = rows[i]
			local active = i <= tiers
			setVisible(row.Frame, active)
			if active then
				local key = tostring(i)
				local reached = tier >= i
				local freeRewards = cfg.Free or {}
				local premRewards = cfg.Premium or {}
				showCell(
					row.Free,
					freeRewards[key],
					reached,
					pass.Free and pass.Free[key] == true,
					false,
					i,
					UI.Theme.Blue
				)
				showCell(
					row.Prem,
					premRewards[key],
					reached,
					pass.Prem and pass.Prem[key] == true,
					not pass.Premium,
					i,
					UI.Theme.Purple
				)
				row.Tier.TextColor3 = if reached then UI.Theme.Yellow else UI.Theme.Text
			end
		end
		tick()
	end
	return { Win = win, Refresh = refresh, Tick = tick }
end

-- ---------------------------------------------------------------------
-- 4) TÄGLICH (Login-Kalender, Glücksrad mit Quoten, Spielzeit-Geschenke, erster Sieg, Codes, Einladen)
-- ---------------------------------------------------------------------
local function invite()
	local ok, canInvite = pcall(function()
		return SocialService:CanSendGameInviteAsync(ctx.Player)
	end)
	if ok and canInvite then
		pcall(function()
			SocialService:PromptGameInvite(ctx.Player)
		end)
	else
		ctx.Toast(T("prog.ui.inviteNo"), "Info")
	end
end

local function buildDaily(): View
	local win = newWindow("Daily", "prog.ui.dailyTitle", UI.Theme.Green)
	local content = win.Content
	local reset = label(content, { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 1, MaxText = 16 })

	-- Login-Kalender
	UI.Section(content, T("prog.ui.login"), 2)
	local calendar = UI.Grid(content, 3, 82, 96)
	local calCells: { { Frame: Frame, Day: TextLabel, Reward: TextLabel } } = {}
	for day, reward in ipairs(P.Login.Calendar) do
		local cell = UI.Card({ LayoutOrder = day, Parent = calendar })
		local dayLabel = label(cell, {
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.new(1, -8, 0, 24),
			Text = T("prog.ui.day", day),
			MaxText = 18,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local rewardLabel = label(cell, {
			Position = UDim2.fromOffset(4, 30),
			Size = UDim2.new(1, -8, 1, -34),
			Text = describe(reward),
			MaxText = 14,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = UI.Theme.Yellow,
		})
		calCells[day] = { Frame = cell, Day = dayLabel, Reward = rewardLabel }
	end
	local loginRow = UI.Row(content, 4, 56)
	local loginButton = UI.Button({
		Size = UDim2.new(0.5, -6, 1, -4),
		Parent = loginRow,
		Text = T("prog.ui.loginClaim"),
		Color = UI.Theme.Green,
		MaxText = 20,
	}, function()
		request("ClaimLogin")
	end)
	local streakLabel = label(loginRow, { Size = UDim2.new(0.5, -6, 1, 0), MaxText = 16 })

	-- Glücksrad
	UI.Section(content, T("prog.ui.wheel"), 10)
	local wheelRow = UI.Row(content, 11, 56)
	local wheelResult = label(content, {
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 12,
		MaxText = 22,
		TextColor3 = UI.Theme.Yellow,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local wheelScale = UI.Create("UIScale", { Parent = wheelResult })
	local odds = UI.Card({
		Size = UDim2.new(1, -6, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 13,
		Parent = content,
		Visible = false,
	})
	-- Gratis-Dreh (keine bezahlten Drehs, B16.4); Ergebnis kommt vom Server
	local spinButton = UI.Button({
		Size = UDim2.new(0.5, -6, 1, -4),
		Parent = wheelRow,
		Text = T("prog.ui.spin"),
		Sub = "",
		Color = UI.Theme.Orange,
		MaxText = 20,
		SubMax = 14,
	}, function()
		local result = request("SpinWheel")
		if type(result) == "table" and type(result.Reward) == "table" then
			wheelResult.Text = "🎉 " .. describe(result.Reward)
			wheelScale.Scale = 0.6
			TweenService
				:Create(wheelScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
				:Play()
		end
	end)
	-- Quoten sind vor dem Drehen sichtbar ("Details", Summe 100 %)
	UI.Button({
		Size = UDim2.new(0.5, -6, 1, -4),
		Parent = wheelRow,
		Text = T("prog.ui.odds"),
		Color = UI.Theme.Blue,
		MaxText = 18,
	}, function()
		odds.Visible = not odds.Visible
	end)
	UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = odds })
	UI.Create(
		"UIPadding",
		{ PaddingLeft = UDim.new(0, 10), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), Parent = odds }
	)
	local total = 0
	for _, prize in ipairs(P.Wheel.Prizes) do
		total += num(prize.W, 0)
	end
	for i, prize in ipairs(P.Wheel.Prizes) do
		label(odds, {
			Size = UDim2.new(1, -10, 0, 20),
			LayoutOrder = i,
			MaxText = 15,
			Text = ("%s – %s"):format(describe(prize), percent(num(prize.W, 0), total)),
		})
	end
	label(odds, { Size = UDim2.new(1, -10, 0, 20), LayoutOrder = 99, MaxText = 14, Text = T("prog.ui.oddsNote") })

	-- Spielzeit-Geschenke
	UI.Section(content, T("prog.ui.gifts"), 20)
	local giftGrid = UI.Grid(content, 21, 145, 104)
	type GiftCell = { Button: any, Minutes: number, Sub: string, Color: Color3? }
	local giftCells: { GiftCell } = {}
	for i, minutes in ipairs(P.Playtime.Minutes) do
		local index = i
		local button = UI.Button({
			LayoutOrder = i,
			Parent = giftGrid,
			Size = UDim2.fromScale(1, 1),
			Text = describe(P.Playtime.Rewards[i]),
			Sub = T("prog.ui.minutes", minutes),
			Color = UI.Theme.Blue,
			MaxText = 16,
			SubMax = 14,
			Wrap = true,
		}, function()
			request("ClaimGift", index)
		end)
		giftCells[i] = { Button = button, Minutes = minutes, Sub = "", Color = nil }
	end

	-- Erster Sieg, Codes, Einladen
	local firstWin = label(content, { Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 30, MaxText = 18 })
	UI.Section(content, T("prog.ui.code"), 31)
	local codeRow = UI.Row(content, 32, 50)
	local codeBox =
		UI.TextBox({ Size = UDim2.new(0.6, -6, 1, -6), PlaceholderText = T("prog.ui.codeHint"), Parent = codeRow })
	UI.Button({
		Size = UDim2.new(0.4, -6, 1, -4),
		Parent = codeRow,
		Text = T("prog.ui.redeem"),
		Color = UI.Theme.Purple,
		MaxText = 18,
	}, function()
		local code = codeBox.Text
		if #code > 0 and #code <= 28 then
			local result = request("RedeemCode", code)
			if type(result) == "table" then
				codeBox.Text = ""
			end
		end
	end)
	local inviteRow = UI.Row(content, 40, 52)
	UI.Button({
		Size = UDim2.new(1, -6, 1, -4),
		Parent = inviteRow,
		Text = "👋 " .. T("prog.ui.invite"),
		Color = UI.Theme.Cyan,
		MaxText = 18,
	}, invite)

	local function tick()
		local daily = state("Daily")
		local login = state("Login")
		if daily then
			local text = T("prog.ui.dayReset", formatTime(num(daily.DayEndsAt, 0) - serverNow()))
			if login and not login.CanClaim then
				local nextReward = P.Login.Calendar[num(login.NextDay, 1)]
				text ..= "  ·  " .. T("prog.ui.tomorrow", describe(nextReward))
			end
			setText(reset, text)
			-- Spielzeit läuft lokal weiter (Server schickt sie nur alle 30 s)
			local played = num(daily.PlaySec, 0) + math.max(0, serverNow() - num(daily.PlayAt, serverNow()))
			local gifts = daily.Gifts or {}
			for i, cell in ipairs(giftCells) do
				local needed = cell.Minutes * 60
				local sub, color
				if gifts[tostring(i)] then
					sub, color = "✓ " .. T("prog.ui.claimed"), UI.Theme.Gray
				elseif played >= needed then
					sub, color = T("prog.ui.claim") .. "!", UI.Theme.Green
				else
					sub, color = formatTime(needed - played), UI.Theme.Blue
				end
				-- nur bei Änderung schreiben
				if cell.Sub ~= sub then
					cell.Sub = sub
					cell.Button.SetSub(sub)
				end
				if cell.Color ~= color then
					cell.Color = color
					cell.Button.SetColor(color)
				end
			end
		end
	end

	local function refresh()
		local login = state("Login")
		local daily = state("Daily")
		if login then
			local calDay = num(login.CalDay, 0)
			local nextDay = num(login.NextDay, 1)
			for day, cell in ipairs(calCells) do
				local claimedDay = (not login.CanClaim and day <= calDay) or (login.CanClaim and day < nextDay)
				local isNext = login.CanClaim and day == nextDay
				cell.Frame.BackgroundColor3 = if isNext
					then UI.Theme.Yellow:Lerp(UI.Theme.PanelLight, 0.4)
					elseif claimedDay then UI.Theme.Green:Lerp(UI.Theme.PanelLight, 0.5)
					else UI.Theme.PanelLight
				setText(cell.Day, (if claimedDay then "✓ " else "") .. T("prog.ui.day", day))
			end
			setVisible(loginButton.Frame, login.CanClaim == true)
			setText(streakLabel, T("prog.ui.streak", num(login.Streak, 0), num(login.Best, 0)))
		end
		if daily then
			local spins = num(daily.SpinsLeft, 0)
			spinButton.SetSub(T("prog.ui.spinsLeft", spins))
			spinButton.SetColor(if spins > 0 then UI.Theme.Orange else UI.Theme.Gray)
			setText(
				firstWin,
				if daily.FirstWinDone
					then "✓ " .. T("prog.ui.firstWinDone")
					else T("prog.ui.firstWin", P.FirstWin.Xp, P.FirstWin.Coins)
			)
		end
		tick()
	end
	return { Win = win, Refresh = refresh, Tick = tick }
end

-- ---------------------------------------------------------------------
-- 5) STATISTIK (Skill sichtbar machen), Erfolge, Gratis-Waffen-Wahl
-- ---------------------------------------------------------------------
local function ownedWeapons(): { [string]: boolean }
	-- WP9-State: "Weapons" = { Owned = {...} } oder "OwnedWeapons" = {...} (beides wird akzeptiert)
	local weapons = state("Weapons")
	if weapons and type(weapons.Owned) == "table" then
		return weapons.Owned
	end
	local owned = state("OwnedWeapons") or state("Owned")
	return owned or {}
end

local function buildStats(): View
	local win = newWindow("Stats", "prog.ui.statsTitle", UI.Theme.Cyan)
	local content = win.Content

	-- Gratis-Waffen-Wahl
	local pickHeader = UI.Section(content, T("prog.ui.pickTitle"), 1, UI.Theme.Gold)
	local pickGrid = UI.Grid(content, 2, 150, 56)
	local pickButtons: { [string]: any } = {}
	local list = Config.Weapons and Config.Weapons.List or {}
	for i, def in ipairs(list) do
		if not def.AdminOnly and def.Free ~= true then
			local key = def.Key
			pickButtons[key] = UI.Button({
				LayoutOrder = i,
				Parent = pickGrid,
				Size = UDim2.fromScale(1, 1),
				Text = pick(def.Name),
				Color = UI.Theme.Gold,
				MaxText = 16,
			}, function()
				request("ClaimLevelPick", key)
			end)
		end
	end

	UI.Section(content, T("prog.ui.overview"), 10)
	local overview = UI.Grid(content, 11, 196, 64)
	local tileKeys = {
		"Level",
		"KD",
		"Accuracy",
		"Headshot",
		"Elims",
		"Wins",
		"PvpWins",
		"BestStreak",
		"Matches",
		"CrownBest",
		"Honor",
		"Flick",
	}
	local tiles: { [string]: { Frame: Frame, Value: TextLabel } } = {}
	for i, key in ipairs(tileKeys) do
		local card = UI.Card({ LayoutOrder = i, Parent = overview })
		label(card, {
			Position = UDim2.fromOffset(8, 4),
			Size = UDim2.new(1, -16, 0, 22),
			Text = T("prog.stat." .. key),
			MaxText = 15,
			TextColor3 = UI.Theme.SubText,
		})
		local value = label(card, { Position = UDim2.fromOffset(8, 26), Size = UDim2.new(1, -16, 0, 32), MaxText = 24 })
		tiles[key] = { Frame = card, Value = value }
	end

	UI.Section(content, T("prog.ui.weapons"), 20)
	local weaponHeader = UI.Row(content, 21, 24)
	for i, key in ipairs({ "colWeapon", "colTier", "colPops", "colAccuracy", "colHeadshot" }) do
		label(weaponHeader, {
			Size = UDim2.new(if i == 1 then 0.32 else 0.16, -6, 1, 0),
			LayoutOrder = i,
			Text = T("prog.ui." .. key),
			MaxText = 14,
			TextColor3 = UI.Theme.SubText,
		})
	end
	type WeaponRow = { Frame: Frame, Cells: { TextLabel } }
	local weaponRows: { WeaponRow } = {}
	for i = 1, #list do
		local row = UI.Row(content, 21 + i, 28)
		local cells = {}
		for c = 1, 5 do
			cells[c] =
				label(row, { Size = UDim2.new(if c == 1 then 0.32 else 0.16, -6, 1, 0), LayoutOrder = c, MaxText = 16 })
		end
		row.Visible = false
		weaponRows[i] = { Frame = row, Cells = cells }
	end

	UI.Section(content, T("prog.ui.achievements"), 200)
	type AchRow = { Card: any, Id: string }
	local achRows: { AchRow } = {}
	local ids = {}
	for id, def in pairs(P.Achievements) do
		table.insert(ids, { Id = id, Order = num(def.Order, 99) })
	end
	table.sort(ids, function(a, b)
		return a.Order < b.Order
	end)
	for i, entry in ipairs(ids) do
		local card = questCard(content, 200 + i, false, function() end)
		setVisible(card.Claim.Frame, false)
		achRows[i] = { Card = card, Id = entry.Id }
	end
	local ranked = label(content, {
		Size = UDim2.new(1, 0, 0, 40),
		LayoutOrder = 300,
		MaxText = 14,
		TextWrapped = true,
		TextColor3 = UI.Theme.SubText,
	})
	ranked.Text = T("prog.ui.rankedSoon")

	local function refresh()
		local stats = state("Stats") or {}
		local honor = state("Honor") or {}
		-- Waffen-Wahl
		local picks = num(ctx.State.FreeWeaponPicks, 0)
		setVisible(pickHeader, picks > 0)
		setVisible(pickGrid, picks > 0)
		if picks > 0 then
			setText(pickHeader, T("prog.ui.pickTitle") .. (if picks > 1 then (" ×%d"):format(picks) else ""))
			local owned = ownedWeapons()
			for key, button in pairs(pickButtons) do
				setVisible(button.Frame, owned[key] ~= true)
			end
		end
		-- Übersicht
		local deaths = num(stats.Deaths, 0)
		local elims = num(stats.Elims, 0)
		local values: { [string]: string } = {
			Level = tostring(num(ctx.State.Level, 1)),
			KD = if deaths > 0 then ("%.2f"):format(elims / deaths) else fmt(elims),
			Accuracy = percent(num(stats.ShotsHit, 0), num(stats.ShotsFired, 0)),
			Headshot = percent(num(stats.Headshots, 0), elims),
			Wins = fmt(num(stats.Wins, 0)),
			PvpWins = fmt(num(stats.PvpWins, 0)),
			BestStreak = fmt(num(stats.BestStreak, 0)),
			Matches = fmt(num(stats.Matches, 0)),
			CrownBest = fmt(num(stats.CrownBest, 0)),
			Honor = ("%s 👍"):format(fmt(num(honor.Commends, 0)))
				.. (if num(honor.Badge, 0) > 0 then " " .. string.rep("🏅", num(honor.Badge, 0)) else ""),
			Flick = if num(stats.FlickBest, 0) > 0 then fmt(num(stats.FlickBest, 0)) else "–",
			Elims = fmt(elims),
		}
		for key, tile in pairs(tiles) do
			setText(tile.Value, values[key] or "–")
		end
		-- pro Waffe (nach Pops sortiert)
		local mastery = state("Mastery") or {}
		local entries = {}
		for key, entry in pairs(mastery) do
			if type(entry) == "table" and Config.Weapon(key) then
				table.insert(entries, { Key = key, E = entry })
			end
		end
		table.sort(entries, function(a, b)
			return num(a.E.K, 0) > num(b.E.K, 0)
		end)
		for i, row in ipairs(weaponRows) do
			local item = entries[i]
			setVisible(row.Frame, item ~= nil)
			if item then
				local e = item.E
				local tier = ProgressMath.MasteryTier(num(e.K, 0))
				local goal = ProgressMath.MasteryGoal(tier)
				setText(row.Cells[1], weaponName(item.Key))
				setText(
					row.Cells[2],
					(if tier > 0 then ROMAN[tier] else "–")
						.. (if goal then (" (%d/%d)"):format(math.floor(num(e.K, 0)), goal) else " ★")
				)
				setText(row.Cells[3], fmt(num(e.Pops, 0)))
				setText(row.Cells[4], percent(num(e.Hits, 0), num(e.Shots, 0)))
				setText(row.Cells[5], percent(num(e.HeadPops, 0), num(e.Pops, 0)))
			end
		end
		-- Erfolge
		local achievements = state("Achievements") or {}
		for _, row in ipairs(achRows) do
			local def = P.Achievements[row.Id]
			local a = achievements[row.Id] or {}
			showQuest(
				row.Card,
				(if a.Done then "🏆 " else "") .. pick(def.Name) .. " – " .. pick(def.Desc),
				describe(def.Reward),
				if a.Done then num(def.Goal, 1) else num(a.P, 0),
				num(def.Goal, 1),
				a.Done == true
			)
			setVisible(row.Card.Claim.Frame, false)
		end
	end
	return { Win = win, Refresh = refresh }
end

-- ---------------------------------------------------------------------
-- 6) ÖFFNEN, HUD-ABZEICHEN, LEVEL-UP-KARTE
-- ---------------------------------------------------------------------
local BUILDERS: { [string]: () -> View } = {
	Quests = buildQuests,
	Pass = buildPass,
	Daily = buildDaily,
	Stats = buildStats,
}

local function viewOf(name: string): View?
	local view = views[name]
	if view then
		return view
	end
	local builder = BUILDERS[name]
	if not builder then
		return nil
	end
	local ok, result = pcall(builder)
	if not ok then
		warn("[Progress] Fenster " .. name .. " bauen: " .. tostring(result))
		return nil
	end
	views[name] = result
	return result
end

local function refreshView(view: View)
	local ok, err = pcall(view.Refresh)
	if not ok then
		warn("[Progress] Aktualisieren: " .. tostring(err))
	end
end

-- Wird von ctx.Windows.Open(name) aufgerufen (registriert in Init)
local function openWindow(name: string)
	local view = viewOf(name)
	if not view then
		return
	end
	refreshView(view)
	UI.OpenWindow(view.Win)
end

function Progress.Open(tab: string) -- "Quests" | "Pass" | "Daily" | "Stats"
	local name = if BUILDERS[tab] then tab else "Quests"
	if ctx and ctx.Windows then
		ctx.Windows.Open(name)
	end
end

local function claimableQuests(): number
	local quests = state("Quests")
	if not quests then
		return 0
	end
	local count = 0
	for _, listName in ipairs({ "Daily", "Weekly" }) do
		for _, q in ipairs(quests[listName] or {}) do
			if not q.Claimed and num(q.P, 0) >= num(q.Goal, 1) then
				count += 1
			end
		end
	end
	local b = quests.Beginner
	if type(b) == "table" and not b.Done and num(b.P, 0) >= num(b.Goal, 1) then
		count += 1
	end
	return count
end

local function claimablePass(): number
	local pass = state("Pass")
	local cfg = activeSeasonConfig()
	if not pass or not cfg then
		return 0
	end
	local count = 0
	for tier = 1, num(pass.Tier, 0) do
		local key = tostring(tier)
		if cfg.Free and cfg.Free[key] and not (pass.Free and pass.Free[key]) then
			count += 1
		end
		if pass.Premium and cfg.Premium and cfg.Premium[key] and not (pass.Prem and pass.Prem[key]) then
			count += 1
		end
	end
	return count
end

local function claimableDaily(): number
	local count = 0
	local login = state("Login")
	if login and login.CanClaim then
		count += 1
	end
	local daily = state("Daily")
	if daily then
		count += math.max(0, num(daily.SpinsLeft, 0))
		local played = num(daily.PlaySec, 0) + math.max(0, serverNow() - num(daily.PlayAt, serverNow()))
		for i, minutes in ipairs(P.Playtime.Minutes) do
			if played >= minutes * 60 and not (daily.Gifts and daily.Gifts[tostring(i)]) then
				count += 1
			end
		end
	end
	return count
end

local function refreshBadges()
	local counts = {
		Quests = claimableQuests(),
		Pass = claimablePass(),
		Daily = claimableDaily(),
		Stats = num(ctx.State.FreeWeaponPicks, 0),
	}
	for name, badge in pairs(hudBadges) do
		local n = counts[name] or 0
		UI.SetBadge(badge, if n > 0 then tostring(n) else nil)
	end
end

local function addHudButtons()
	local hud = ctx.Modules.Hud
	if not hud or type(hud.AddRightButton) ~= "function" then
		return
	end
	local specs = {
		{ Name = "Quests", Icon = "📜", Key = "prog.hud.quests", Color = UI.Theme.Orange, Order = 30 },
		{ Name = "Daily", Icon = "🎁", Key = "prog.hud.daily", Color = UI.Theme.Green, Order = 31 },
		{ Name = "Pass", Icon = "🎟️", Key = "prog.hud.pass", Color = UI.Theme.Pink, Order = 32 },
		{ Name = "Stats", Icon = "📊", Key = "prog.hud.stats", Color = UI.Theme.Cyan, Order = 33 },
	}
	for _, spec in ipairs(specs) do
		local ok, button = pcall(hud.AddRightButton, spec.Icon, spec.Key, spec.Color, spec.Order, function()
			Progress.Open(spec.Name)
		end)
		if ok and type(button) == "table" and button.Frame then
			hudButtons[spec.Name] = button
			local okBadge, badge = pcall(UI.Badge, button, nil)
			if okBadge and badge then
				hudBadges[spec.Name] = badge
			end
		end
	end
end

-- Level-Up-Karte (oben Mitte, 4.5 s): Level, Belohnungen, Hinweis auf Gratis-Waffen-Wahl
local function showLevelCard(data: any)
	if type(data) ~= "table" or not ctx.Gui then
		return
	end
	local card = levelCard
	if not card then
		local frame = UI.Card({
			Name = "LevelUpCard",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 110),
			Size = UDim2.fromOffset(420, 120),
			BackgroundColor3 = UI.Theme.PanelDark,
			Visible = false,
			ZIndex = 50,
			Parent = ctx.Gui,
		})
		UI.Create("UIScale", { Name = "Scale", Parent = frame })
		label(frame, {
			Name = "Title",
			Position = UDim2.fromOffset(12, 8),
			Size = UDim2.new(1, -24, 0, 44),
			MaxText = 40,
			Outline = 3,
			ZIndex = 51,
			TextColor3 = UI.Theme.Yellow,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		label(frame, {
			Name = "Rewards",
			Position = UDim2.fromOffset(12, 54),
			Size = UDim2.new(1, -24, 0, 28),
			MaxText = 20,
			ZIndex = 51,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		label(frame, {
			Name = "Pick",
			Position = UDim2.fromOffset(12, 84),
			Size = UDim2.new(1, -24, 0, 26),
			MaxText = 18,
			ZIndex = 51,
			TextColor3 = UI.Theme.Cash,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		levelCard = frame
		card = frame
	end
	local frame = card :: Frame
	local title = frame:FindFirstChild("Title") :: TextLabel
	local rewards = frame:FindFirstChild("Rewards") :: TextLabel
	local pickLabel = frame:FindFirstChild("Pick") :: TextLabel
	local scale = frame:FindFirstChild("Scale") :: UIScale
	title.Text = T("prog.ui.levelUp", num(data.Level, 1))
	rewards.Text = describe(data.Rewards)
	local picks = if type(data.Rewards) == "table" then num(data.Rewards.FreeWeaponPicks, 0) else 0
	pickLabel.Text = if picks > 0 then T("prog.freePick") else ""
	frame.Visible = true
	scale.Scale = 0.5
	TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	levelCardToken += 1
	local token = levelCardToken
	task.delay(LEVEL_CARD_TIME, function()
		if levelCardToken == token and levelCard then
			levelCard.Visible = false
		end
	end)
end

local function onState(_state: any, changed: any)
	if type(changed) ~= "table" then
		return
	end
	local mine = changed.Full == true
	if not mine then
		for _, key in ipairs(MY_KEYS) do
			if changed[key] then
				mine = true
				break
			end
		end
	end
	if not mine then
		return
	end
	refreshBadges()
	for name, view in pairs(views) do
		if ctx.Windows.IsOpen(name) then
			refreshView(view)
		end
	end
end

-- 1-s-Takt nur für Countdown-Texte offener Fenster (und Abzeichen der Spielzeit-Geschenke)
local function onHeartbeat(dt: number)
	tickAcc += dt
	if tickAcc < 1 then
		return
	end
	tickAcc = 0
	for name, view in pairs(views) do
		if view.Tick and ctx.Windows.IsOpen(name) then
			local ok, err = pcall(view.Tick)
			if not ok then
				warn("[Progress] Takt: " .. tostring(err))
			end
		end
	end
	refreshBadges()
end

-- ---------------------------------------------------------------------
-- 7) INIT / START
-- ---------------------------------------------------------------------
function Progress.Init(context: any)
	ctx = context
	UI = ctx.UI
	Config = ctx.Config
	P = Config.Progression
	for _, name in ipairs(TABS) do
		ctx.Windows.Register(name, function()
			openWindow(name)
		end)
	end
end

function Progress.Start()
	addHudButtons()
	ctx.Hooks.On("State", onState)
	ctx.Hooks.On("Effect:LevelUp", function(_strength: number, data: any)
		showLevelCard(data)
	end)
	RunService.Heartbeat:Connect(onHeartbeat)
	refreshBadges()
	-- Spieler, der den Client neu lädt: offene Gratis-Waffen-Wahl erwähnen
	if Players.LocalPlayer and num(ctx.State.FreeWeaponPicks, 0) > 0 then
		ctx.Toast(T("prog.freePick"), "Event")
	end
end

return Progress
