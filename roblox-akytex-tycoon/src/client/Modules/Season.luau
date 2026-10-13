-- =====================================================================
--  AKYTEX TYCOON – Skyline-Pass (Client/Modules/Season)
--  Besitzer: WP9 (Fortschritt, Tutorial, Sozial, Bestenlisten). Vertrag: DESIGN.md §B9.9 (4 Wochen, 50 Stufen à
--  1.000 Saison-XP, Gratis-Spur 25 / Premium-Spur 50, Premium rückwirkend, ehrlicher Countdown bis Saisonende, nie AKY/
--  XP/KH/Ruf), §0.4 (gekaufte Stufen zahlen nur Kosmetik), §0.8/§B2 (kein Angebot im Tutorial), §C7.3 (Fenster "Season").
--
--  Öffentliche API: keine Pflicht-API. Zusätzlich: Season.Init(ctx), Season.Start(), Season.Tick() (1 s Countdown),
--  Season.Open().   Anfragen: RewardSeason { Tier, Track }.   State: "Season".
--  Premium-Kauf läuft nur über den Shop (Shop.Open("Season")); dieser Knopf ist im Tutorial ausgeblendet.
-- =====================================================================

local UI = require(script.Parent:WaitForChild("UI"))

local Season = {}

local Theme = UI.Theme

local WINDOW_W, WINDOW_H = 700, 620
local ROW_H = 64

local ctx: any = nil
local window: any = nil
local ui: { [string]: any } = {}
local rows: { [number]: any } = {}
local builtFor = ""
local busy = false

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

local function season(): { [string]: any }
	local s = ctx.State.Season
	return if type(s) == "table" then s else {}
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

-- Spur-Definition der aktuellen Saison (Rolling nutzt die Spuren der letzten festen Saison)
local function seasonDef(): any
	local cfg = ctx.Config.Season
	local list = type(cfg) == "table" and cfg.Seasons or nil
	if type(list) ~= "table" then
		return nil
	end
	local index = math.floor(num(season().SeasonIndex, 0))
	return list[index] or list[#list]
end

local function rewardAt(def: any, track: string, tier: number): any
	local list = if track == "Premium" then def.Premium else def.Free
	if type(list) ~= "table" then
		return nil
	end
	for _, reward in ipairs(list) do
		if type(reward) == "table" and reward.Tier == tier then
			return reward
		end
	end
	return nil
end

-- Beschreibung wie im Quest-Fenster (eine Quelle: Quests.DescribeReward), Rückfall auf die Feldnamen
local function describe(reward: any): string
	local ok, value = call("Quests", "DescribeReward", reward)
	if ok and type(value) == "string" then
		return value
	end
	local parts: { string } = {}
	for field in pairs(reward) do
		if field ~= "Tier" then
			table.insert(parts, tostring(field))
		end
	end
	table.sort(parts)
	return table.concat(parts, " · ")
end

local function earnedOnly(reward: any): boolean
	local cfg = ctx.Config.Season
	local fields = type(cfg) == "table" and cfg.EarnedOnlyFields or {}
	for field in pairs(fields) do
		if reward[field] ~= nil then
			return true
		end
	end
	return false
end

local function tutorialActive(): boolean
	local ok, active = call("Tutorial", "IsActive")
	return ok and active == true
end

local function claim(tier: number, track: string)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		ctx.RequestFull("RewardSeason", { Tier = tier, Track = track })
		busy = false
	end)
end

-- ---------------------------------------------------------------------
-- 2) FENSTER
-- ---------------------------------------------------------------------
local function trackCell(row: Frame, track: string, tier: number, reward: any): any
	local isPremium = track == "Premium"
	local cell = UI.Create("Frame", {
		Name = track,
		Position = if isPremium then UDim2.new(0.5, 30, 0, 6) else UDim2.new(0, 64, 0, 6),
		Size = UDim2.new(0.5, -40, 1, -12),
		BackgroundColor3 = if isPremium then Theme.Cosmic2 else Theme.Surface,
		BackgroundTransparency = if isPremium then 0.82 else 0.4,
		Parent = row,
	}, { UI.Corner(8) })
	if not reward then
		UI.Label({
			Size = UDim2.fromScale(1, 1),
			Text = "–",
			TextColor3 = Theme.Muted,
			MaxText = 14,
			Parent = cell,
		})
		return nil
	end
	local label = UI.Label({
		Position = UDim2.fromOffset(8, 4),
		Size = UDim2.new(1, -112, 1, -8),
		Text = describe(reward),
		Face = "Body",
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 13,
		Parent = cell,
	})
	local button = UI.Button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(96, 36),
		Text = T("prog.btn.claim"),
		Variant = "Muted",
		MaxText = 14,
		Parent = cell,
	}, function()
		claim(tier, track)
	end)
	return { Label = label, Button = button, Reward = reward, EarnedOnly = earnedOnly(reward) }
end

local function buildRows()
	local def = seasonDef()
	local key = if def then tostring(def.Id) .. ":" .. lang() else ""
	if key == builtFor then
		return
	end
	builtFor = key
	for _, row in pairs(rows) do
		row.Frame:Destroy()
	end
	table.clear(rows)
	if not def then
		return
	end
	local tiers = math.floor(num(def.Tiers, 50))
	for tier = 1, tiers do
		local frame = UI.RowCard(ui.List, tier, ROW_H)
		local number = UI.Label({
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.fromOffset(48, ROW_H),
			Text = tostring(tier),
			Face = "Display",
			MaxText = 20,
			Parent = frame,
		})
		rows[tier] = {
			Frame = frame,
			Number = number,
			Free = trackCell(frame, "Free", tier, rewardAt(def, "Free", tier)),
			Premium = trackCell(frame, "Premium", tier, rewardAt(def, "Premium", tier)),
		}
	end
end

local function buildWindow()
	window = UI.Window(T("prog.win.season"), WINDOW_W, WINDOW_H, Theme.Purple)
	local content = window.Content
	ui.Name = text(content, {
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 1,
		Face = "Display",
		MaxText = 22,
		TextColor3 = Theme.Purple,
	})
	ui.Ends = text(content, { Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 2, Face = "Mono", MaxText = 14 })
	ui.Tier = text(content, { Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 3, Face = "BodyBold", MaxText = 16 })
	ui.Bar = UI.Bar({ Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 4, Color = Theme.Purple, Parent = content })
	ui.Play = text(content, { Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 5, MaxText = 13, TextColor3 = Theme.Text2 })
	ui.Info = text(content, {
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = 6,
		Face = "Body",
		TextWrapped = true,
		MaxText = 13,
		TextColor3 = Theme.Muted,
	})
	local row = UI.Row(content, 7, 46)
	ui.PremiumLabel = text(row, { Size = UDim2.new(1, -230, 1, 0), MaxText = 15, Face = "BodyBold" })
	ui.PremiumButton = UI.Button({
		Size = UDim2.fromOffset(210, 44),
		Text = T("prog.btn.premium"),
		Variant = "Premium",
		Parent = row,
	}, function()
		ctx.Windows.Close("Season")
		local ok = call("Shop", "Open", "Season")
		if not ok then
			ctx.Windows.Open("Shop")
		end
	end)
	local header = UI.Row(content, 8, 24)
	text(header, {
		Size = UDim2.new(0.5, 0, 1, 0),
		Text = "   " .. T("prog.lbl.free"),
		MaxText = 14,
		TextColor3 = Theme.Text2,
		LayoutOrder = 1,
	})
	text(header, {
		Size = UDim2.new(0.5, -8, 1, 0),
		Text = T("prog.lbl.premium"),
		MaxText = 14,
		TextColor3 = Theme.Cosmic3,
		LayoutOrder = 2,
	})
	ui.List = UI.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 9,
		Parent = content,
	}, { UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }) })
	ui.Empty = text(content, {
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 10,
		MaxText = 16,
		TextColor3 = Theme.Muted,
		Visible = false,
	})
end

local function refreshCell(cell: any, tier: number, reached: number, earned: number, claimed: any, locked: boolean)
	if not cell then
		return
	end
	local key = tostring(tier)
	local isClaimed = type(claimed) == "table" and claimed[key] == true
	local reachedTier = tier <= reached
	local boughtOnly = reachedTier and tier > earned and cell.EarnedOnly
	if isClaimed then
		cell.Button.SetText(T("prog.btn.claimed"))
		cell.Button.SetVariant("Muted")
	elseif locked or not reachedTier or boughtOnly then
		cell.Button.SetText(T("prog.btn.locked"))
		cell.Button.SetVariant("Muted")
	else
		cell.Button.SetText(T("prog.btn.claim"))
		cell.Button.SetVariant("Success")
	end
	cell.Label.TextColor3 = if isClaimed then Theme.Muted else Theme.Text
end

function Season.Refresh()
	if not window or not window.IsOpen then
		return
	end
	local s = season()
	local def = seasonDef()
	if s.Ended == true or num(s.Id, 0) <= 0 or not def then
		ui.Name.Text = T("prog.win.season")
		ui.Ends.Text = T("prog.season.ended")
		ui.Tier.Text = ""
		ui.Play.Text = ""
		ui.Info.Text = T("prog.season.info")
		ui.PremiumButton.Frame.Visible = false
		ui.PremiumLabel.Text = ""
		ui.List.Visible = false
		return
	end
	ui.List.Visible = true
	buildRows()
	local name = if type(s.Name) == "table" then ctx.Lang.Pick(lang(), s.Name) else nil
	ui.Name.Text = name or T("prog.season.rolling", math.floor(num(s.Id, 1)))
	ui.Ends.Text = T("prog.season.endsIn", fmt("Duration", num(s.EndsAt, 0) - now(), lang()))
	local tiers = math.floor(num(s.Tiers, num(def.Tiers, 50)))
	local tierXp = math.max(1, num(s.TierXp, num(def.TierXp, 1000)))
	local tier = math.floor(num(s.Tier, 0))
	local earned = math.floor(num(s.EarnedTier, tier))
	local xp = num(s.Xp, 0)
	ui.Tier.Text = T("prog.lbl.seasonTier", tier, tiers)
	if tier >= tiers then
		UI.SetBar(ui.Bar, 1, T("prog.lbl.seasonXp", fmt("Int", xp, lang()), fmt("Int", tiers * tierXp, lang())))
	else
		local inTier = xp - tier * tierXp
		UI.SetBar(
			ui.Bar,
			inTier / tierXp,
			T("prog.lbl.seasonXp", fmt("Int", math.max(0, inTier), lang()), fmt("Int", tierXp, lang()))
		)
	end
	local playMinutes = math.floor(num(s.PlayToday, 0)) -- Server zählt Minuten
	ui.Play.Text = T("prog.lbl.playToday", math.min(playMinutes, 60))
	ui.Info.Text = T("prog.season.info")
	local premium = s.Premium == true
	ui.PremiumLabel.Text = if premium then T("prog.lbl.premiumActive") else ""
	ui.PremiumLabel.TextColor3 = Theme.Cosmic3
	-- kein Kauf-Knopf während des Tutorials (§B2: kein Robux-Angebot in der ersten Sitzung)
	ui.PremiumButton.Frame.Visible = not premium and not tutorialActive()
	for t, row in pairs(rows) do
		row.Number.TextColor3 = if t <= tier then Theme.Purple else Theme.Muted
		refreshCell(row.Free, t, tier, earned, s.ClaimedFree, false)
		refreshCell(row.Premium, t, tier, earned, s.ClaimedPremium, not premium)
	end
end

local function openWindow()
	if not window then
		buildWindow()
	end
	UI.OpenWindow(window)
	Season.Refresh()
	-- zur ersten abholbaren Stufe scrollen
	local s = season()
	local target = math.max(1, math.floor(num(s.Tier, 0)) - 1)
	local row = rows[target]
	if row and row.Frame then
		task.defer(function()
			if window and window.IsOpen and row.Frame.Parent then
				local offset = row.Frame.AbsolutePosition.Y - window.Content.AbsolutePosition.Y
				window.Content.CanvasPosition =
					Vector2.new(0, math.max(0, offset + window.Content.CanvasPosition.Y - 8))
			end
		end)
	end
end

local function closeWindow()
	if window and window.IsOpen then
		UI.CloseWindow(window)
	end
end

function Season.Open()
	ctx.Windows.Open("Season")
end

function Season.Tick()
	if window and window.IsOpen then
		local s = season()
		if num(s.EndsAt, 0) > 0 then
			ui.Ends.Text = T("prog.season.endsIn", fmt("Duration", num(s.EndsAt, 0) - now(), lang()))
		end
	end
end

function Season.Init(context: any)
	ctx = context
	ctx.Windows.Register("Season", openWindow, closeWindow)
end

function Season.Start()
	ctx.Hooks.On("State", function(_state: any, changed: any)
		if type(changed) == "table" and changed.Season then
			Season.Refresh()
		end
	end)
	ctx.Hooks.On("Settings", function()
		builtFor = ""
		Season.Refresh()
	end)
end

return Season
