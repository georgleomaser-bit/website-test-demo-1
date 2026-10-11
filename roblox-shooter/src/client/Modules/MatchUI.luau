-- =====================================================================
--  CLUTCH CLASH – Match-Oberfläche (Client/Modules/MatchUI)
--  Besitzer: WP5 (Match-UI). Vertrag: DESIGN.md B5, B6.6, B14.2, B14.3, B14.6, C7.2 (Hooks "Match:<Kind>"), C8.
--
--  MATCH GEFUNDEN! + Kartenwahl (3 Karten + Zufall) · Intro "BLAZE vs FROST" mit Gegner-Loadouts ·
--  Countdown 3-2-1-POP · Timer + Punkt-Pips (FFA: eigene Punkte/Führung) · Zonen-Balken (Overtime/Sudden Death) ·
--  Banner (Runde gewonnen/verloren, CLUTCH!, ACE!, FLAWLESS!, COMEBACK!, MATCH POINT, SUDDEN DEATH, CLUTCH-Bonus-XP) ·
--  Killfeed oben rechts (max. 5 Zeilen, je 5 s, eigene gelb, Bots grau, Abzeichen Serie/Kopfgeld/Meisterschaft/
--  Krone/DOUBLE…) · Todes-Rückblick links · Ergebnis-Bildschirm (füllende Balken XP → Coins → Meisterschaft → Pass →
--  Quests, GG/Loben/REMATCH/NOCHMAL SPIELEN/Lobby, Auto-Requeue, Starter-Karte nur bei Offer) · AFK-Warnung ·
--  Bereit/Loadout in Prep · ArenaReady an den Server · Roblox-Spielerliste + Reset im Match aus.
--  Finisher bei jedem Elim über CombatFX.Pop (auch für Crown-Zuschauer).
--
--  Öffentliche API: MatchUI.InMatch(): boolean, MatchUI.Init(ctx), MatchUI.Start()
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent:WaitForChild("UI"))

local MatchUI = {}

local player = Players.LocalPlayer
local ctx: any = nil
local ProgressMath: any = nil

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local GRAY = Color3.fromRGB(190, 190, 198)
local REFRESH = 0.1
local KILLFEED_MAX = 5
local KILLFEED_SECONDS = 5
local BANNER_SECONDS = 2.4
local ARENA_WAIT = 4
local FACE = "rbxasset://textures/face.png"
local BANNER_POP = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

type RosterEntry = {
	Slot: number,
	Id: number,
	Name: string,
	Team: number,
	IsBot: boolean,
	Level: number,
	Title: string,
	Finisher: string,
}

-- Match-Zustand (nur Anzeige; der Server ist Autorität)
local match: any = nil
local roster: { [number]: RosterEntry } = {}
local foundData: any = nil
local myVote = 0
local ready = false
local reportedKiller = false
local autoRequeue = false
local resultsUntil = 0
local lastCountdown = 0
local unbinds: { () -> () } = {}

-- UI-Teile
local root: Frame? = nil
local topBar: Frame? = nil
local timerLabel: TextLabel? = nil
local roundLabel: TextLabel? = nil
local leftName: TextLabel? = nil
local rightName: TextLabel? = nil
local leftPips: Frame? = nil
local rightPips: Frame? = nil
local zoneBar: any = nil
local bannerLabel: TextLabel? = nil
local bannerScale: UIScale? = nil
local subBanner: TextLabel? = nil
local bannerUntil = 0
local countdownLabel: TextLabel? = nil
local countdownScale: UIScale? = nil
local noticeLabel: TextLabel? = nil
local noticeUntil = 0
local killfeed: Frame? = nil
local killRows: { { Frame: Frame, Until: number } } = {}
local recapPanel: Frame? = nil
local voteOverlay: Frame? = nil
local voteTitle: TextLabel? = nil
local voteTimer: TextLabel? = nil
local voteCards: Frame? = nil
local voteCountLabels: { TextLabel } = {}
local voteButtons: { any } = {}
local introOverlay: Frame? = nil
local prepBar: Frame? = nil
local readyButton: any = nil
local afkOverlay: Frame? = nil
local resultsFrame: Frame? = nil
local rematchButton: any = nil
local resultsTimer: TextLabel? = nil
local taintBadge: TextLabel? = nil
local loadingLabel: TextLabel? = nil

-- ---------------------------------------------------------------------
-- 1) HELFER
-- ---------------------------------------------------------------------
local function T(key: string, ...: any): string
	return if ctx then ctx.T(key, ...) else key
end

local function pick(t: any): string
	if type(t) ~= "table" then
		return tostring(t or "")
	end
	return ctx.Lang.Pick(ctx.Lang_(), t)
end

local function module(name: string): any
	return ctx and ctx.Modules and ctx.Modules[name]
end

local function sfx(role: string, opts: any?)
	local s = module("Sfx")
	if s and type(s.Play) == "function" then
		pcall(s.Play, role, nil, opts)
	end
end

local function confetti(amount: number)
	local effects = module("Effects")
	if effects and type(effects.Confetti) == "function" then
		pcall(effects.Confetti, amount)
	end
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function request(action: string, arg: any?)
	task.spawn(function()
		ctx.Request(action, arg)
	end)
end

local function setText(label: TextLabel?, text: string)
	if label and label.Text ~= text then
		label.Text = text
	end
end

local function escape(text: string): string
	local out = string.gsub(text, "&", "&amp;")
	out = string.gsub(out, "<", "&lt;")
	out = string.gsub(out, ">", "&gt;")
	out = string.gsub(out, '"', "&quot;")
	return out
end

local function hex(c: Color3): string
	return string.format("#%02x%02x%02x", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

local function isFfa(): boolean
	return match ~= nil and match.Mode == "FFA"
end

local function teamColor(team: number): Color3
	local colors = ctx.Config.Colors
	if isFfa() then
		return UI.Theme.Pink
	end
	return if team == 2 then colors.TeamB else colors.TeamA
end

local function teamName(team: number): string
	return T(if team == 2 then "match.teamB" else "match.teamA")
end

local function modeName(key: string?): string
	local modes = ctx.Config.Modes
	local def = key and modes and modes.Modes and modes.Modes[key]
	return if def then pick(def.Name) else tostring(key or "")
end

local function mutatorName(key: string?): string?
	local modes = ctx.Config.Modes
	local def = key and modes and modes.Mutators and modes.Mutators[key]
	return if def then pick(def.Name) else nil
end

local function mapName(key: string?): string
	local maps = ctx.Config.Maps and ctx.Config.Maps.Maps
	local def = key and maps and maps[key]
	return if def then pick(def.Name) else tostring(key or "?")
end

local function weaponShort(key: string?): string
	local def = key and ctx.Config.Weapon and ctx.Config.Weapon(key)
	if def then
		return tostring(def.Short or pick(def.Name))
	end
	return tostring(key or "?")
end

local function weaponName(key: string?): string
	local def = key and ctx.Config.Weapon and ctx.Config.Weapon(key)
	return if def then pick(def.Name) else tostring(key or "?")
end

local function titleText(title: string?): string
	if not title or title == "" then
		return ""
	end
	local cosmetics = ctx.Config.Cosmetics
	local def = cosmetics and type(cosmetics.Titles) == "table" and cosmetics.Titles[title]
	return if def and type(def.Name) == "table" then pick(def.Name) else title
end

local function finisherName(id: string?): string
	local cosmetics = ctx.Config.Cosmetics
	local def = id and cosmetics and type(cosmetics.Finishers) == "table" and cosmetics.Finishers[id]
	return if def and type(def.Name) == "table" then pick(def.Name) else tostring(id or "")
end

local function nameOf(id: number?): (string, boolean)
	if id == nil then
		return "?", false
	end
	local entry = roster[id]
	if entry then
		return entry.Name, entry.IsBot
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.UserId == id then
			return p.DisplayName, false
		end
	end
	return "?", id < -1000
end

local function formatTime(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function setCoreGui(on: boolean)
	task.spawn(function()
		for _ = 1, 10 do
			local ok = pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, on)
			end)
			if ok then
				break
			end
			task.wait(0.5)
		end
	end)
	-- Reset-Knopf im Match aus (mit Wiederholung bis Erfolg, B5)
	task.spawn(function()
		for _ = 1, 20 do
			local ok = pcall(function()
				StarterGui:SetCore("ResetButtonCallback", on)
			end)
			if ok then
				break
			end
			task.wait(0.5)
		end
	end)
end

local function label(props: { [string]: any }): TextLabel
	return UI.Label(props)
end

-- ---------------------------------------------------------------------
-- 2) AUFBAU
-- ---------------------------------------------------------------------
local function buildTopBar(parent: Frame)
	local theme = UI.Theme
	local bar = UI.Create("Frame", {
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(520, 100),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 20,
		Parent = parent,
	})
	local center = UI.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(120, 54),
		BackgroundColor3 = theme.PanelDark,
		BackgroundTransparency = 0.1,
		ZIndex = 20,
		Parent = bar,
	}, { UI.Corner(12), UI.Stroke(BLACK, 3) })
	timerLabel = label({
		Size = UDim2.fromScale(1, 1),
		Text = "0:00",
		Font = UI.Fonts.Number,
		MaxText = 34,
		Outline = 2,
		ZIndex = 21,
		Parent = center,
	})
	local function side(isLeft: boolean): (TextLabel, Frame)
		local holder = UI.Create("Frame", {
			AnchorPoint = Vector2.new(if isLeft then 1 else 0, 0),
			Position = UDim2.new(0.5, if isLeft then -66 else 66, 0, 0),
			Size = UDim2.fromOffset(190, 54),
			BackgroundColor3 = theme.PanelDark,
			BackgroundTransparency = 0.25,
			ZIndex = 20,
			Parent = bar,
		}, { UI.Corner(12), UI.Stroke(BLACK, 3) })
		local name = label({
			Position = UDim2.fromOffset(8, 2),
			Size = UDim2.new(1, -16, 0, 26),
			Text = "",
			MaxText = 22,
			Outline = 3,
			TextXAlignment = if isLeft then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left,
			ZIndex = 21,
			Parent = holder,
		})
		local pips = UI.Create("Frame", {
			Position = UDim2.fromOffset(8, 30),
			Size = UDim2.new(1, -16, 0, 18),
			BackgroundTransparency = 1,
			ZIndex = 21,
			Parent = holder,
		}, {
			UI.Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = if isLeft then Enum.HorizontalAlignment.Right else Enum.HorizontalAlignment.Left,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		return name, pips
	end
	leftName, leftPips = side(true)
	rightName, rightPips = side(false)
	roundLabel = label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 58),
		Size = UDim2.fromOffset(300, 22),
		Text = "",
		MaxText = 18,
		Outline = 2,
		ZIndex = 21,
		Parent = bar,
	})
	zoneBar = UI.Bar({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 82),
		Size = UDim2.fromOffset(320, 22),
		Color = theme.Yellow,
		MaxText = 14,
		Parent = bar,
	})
	zoneBar.Frame.Visible = false
	zoneBar.Frame.ZIndex = 21
	topBar = bar
end

local function buildBanners(parent: Frame)
	bannerLabel = label({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.new(1, -40, 0, 80),
		Text = "",
		Font = UI.Fonts.Banner,
		MaxText = 64,
		Outline = 5,
		Visible = false,
		ZIndex = 25,
		Parent = parent,
	})
	bannerScale = UI.Create("UIScale", { Parent = bannerLabel })
	subBanner = label({
		Name = "SubBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.3, 44),
		Size = UDim2.new(1, -40, 0, 44),
		Text = "",
		Font = UI.Fonts.Pop,
		MaxText = 40,
		Outline = 4,
		TextColor3 = UI.Theme.Yellow,
		Visible = false,
		ZIndex = 25,
		Parent = parent,
	})
	countdownLabel = label({
		Name = "Countdown",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(300, 140),
		Text = "",
		Font = UI.Fonts.Banner,
		MaxText = 120,
		Outline = 6,
		TextColor3 = UI.Theme.Yellow,
		Visible = false,
		ZIndex = 26,
		Parent = parent,
	})
	countdownScale = UI.Create("UIScale", { Parent = countdownLabel })
	noticeLabel = label({
		Name = "Notice",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0, 0, 0, 112),
		Size = UDim2.fromOffset(420, 30),
		Text = "",
		MaxText = 22,
		Outline = 3,
		TextColor3 = UI.Theme.Red,
		Visible = false,
		ZIndex = 25,
		Parent = parent,
	})
	noticeLabel.Position = UDim2.new(0.5, 0, 0, 112)
	loadingLabel = label({
		Name = "Loading",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(400, 50),
		Text = "",
		MaxText = 30,
		Outline = 3,
		Visible = false,
		ZIndex = 25,
		Parent = parent,
	})
	taintBadge = label({
		Name = "Tainted",
		Position = UDim2.fromOffset(12, 120),
		Size = UDim2.fromOffset(260, 30),
		Text = T("match.taintedBadge"),
		BackgroundColor3 = UI.Theme.Red,
		BackgroundTransparency = 0,
		MaxText = 18,
		Outline = 2,
		Visible = false,
		ZIndex = 25,
		Parent = parent,
	})
	UI.Corner(8).Parent = taintBadge
end

local function buildKillfeed(parent: Frame)
	killfeed = UI.Create("Frame", {
		Name = "Killfeed",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 60),
		Size = UDim2.fromOffset(440, 5 * 32),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = parent,
	}, {
		UI.Create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 4),
		}),
	})
end

local function buildPrep(parent: Frame)
	local theme = UI.Theme
	local bar = UI.Create("Frame", {
		Name = "PrepBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.fromOffset(440, 64),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 24,
		Parent = parent,
	})
	readyButton = UI.Button({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(210, 58),
		Text = T("match.ready"),
		Color = theme.Green,
		MaxText = 22,
		ZIndex = 24,
		Parent = bar,
	}, function()
		if not ready and match and match.Phase == "Prep" then
			ready = true
			readyButton.SetText(T("match.readyDone"))
			request("Ready")
		end
	end)
	UI.Button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(210, 58),
		Text = T("match.loadout"),
		Color = theme.Blue,
		MaxText = 22,
		ZIndex = 24,
		Parent = bar,
	}, function()
		ctx.Windows.Open("Locker")
	end)
	prepBar = bar
end

local function buildAfk(parent: Frame)
	local frame = UI.Create("Frame", {
		Name = "Afk",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromOffset(560, 110),
		BackgroundColor3 = UI.Theme.Red,
		BackgroundTransparency = 0.1,
		Visible = false,
		ZIndex = 45,
		Parent = parent,
	}, { UI.Corner(16), UI.Stroke(BLACK, 4) })
	label({
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(1, -20, 0, 46),
		Text = T("match.afk.title"),
		Font = UI.Fonts.Banner,
		MaxText = 38,
		Outline = 4,
		ZIndex = 46,
		Parent = frame,
	})
	label({
		Position = UDim2.fromOffset(10, 54),
		Size = UDim2.new(1, -20, 0, 46),
		Text = T("match.afkWarn"),
		MaxText = 20,
		Outline = 2,
		TextWrapped = true,
		ZIndex = 46,
		Parent = frame,
	})
	afkOverlay = frame
end

local function overlayFrame(name: string, parent: Frame, size: Vector2, z: number): Frame
	return UI.Create("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = UI.Theme.Panel,
		Visible = false,
		ZIndex = z,
		Parent = parent,
	}, {
		UI.Corner(20),
		UI.Stroke(BLACK, 4),
		UI.Gradient(UI.Theme.Panel:Lerp(WHITE, 0.12), UI.Theme.PanelDark),
	})
end

local function buildVote(parent: Frame)
	local frame = overlayFrame("Vote", parent, Vector2.new(760, 380), 30)
	voteTitle = label({
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -32, 0, 56),
		Text = T("match.found"),
		Font = UI.Fonts.Banner,
		MaxText = 48,
		Outline = 4,
		TextColor3 = UI.Theme.Yellow,
		ZIndex = 31,
		Parent = frame,
	})
	voteTimer = label({
		Position = UDim2.fromOffset(16, 66),
		Size = UDim2.new(1, -32, 0, 28),
		Text = "",
		MaxText = 20,
		Outline = 2,
		ZIndex = 31,
		Parent = frame,
	})
	voteCards = UI.Create("Frame", {
		Position = UDim2.fromOffset(16, 104),
		Size = UDim2.new(1, -32, 1, -120),
		BackgroundTransparency = 1,
		ZIndex = 31,
		Parent = frame,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	voteOverlay = frame
end

local function buildResults(parent: Frame)
	local frame = overlayFrame("Results", parent, Vector2.new(720, 560), 50)
	resultsFrame = frame
end

local function buildRecap(parent: Frame)
	local frame = UI.Create("Frame", {
		Name = "Recap",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.55, 0),
		Size = UDim2.fromOffset(300, 420),
		BackgroundColor3 = UI.Theme.PanelDark,
		BackgroundTransparency = 0.12,
		Visible = false,
		ZIndex = 28,
		Parent = parent,
	}, { UI.Corner(14), UI.Stroke(BLACK, 3) })
	recapPanel = frame
end

-- ---------------------------------------------------------------------
-- 3) ANZEIGE-TEILE
-- ---------------------------------------------------------------------
local function showBanner(text: string, color: Color3?, sub: string?, seconds: number?)
	local b = bannerLabel
	if not b then
		return
	end
	b.Text = text
	b.TextColor3 = color or WHITE
	b.Visible = true
	if bannerScale then
		bannerScale.Scale = 0.4
		TweenService:Create(bannerScale, BANNER_POP, { Scale = 1 }):Play()
	end
	if subBanner then
		subBanner.Text = sub or ""
		subBanner.Visible = sub ~= nil and sub ~= ""
	end
	bannerUntil = os.clock() + (seconds or BANNER_SECONDS)
end

local function showNotice(text: string, seconds: number)
	local n = noticeLabel
	if not n then
		return
	end
	n.Text = text
	n.Visible = true
	noticeUntil = os.clock() + seconds
end

local function rebuildPips(holder: Frame?, wins: number, total: number, color: Color3)
	if not holder then
		return
	end
	local pips = {}
	for _, child in ipairs(holder:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(pips, child)
		end
	end
	if #pips ~= total then
		for _, pip in ipairs(pips) do
			pip:Destroy()
		end
		pips = {}
		for i = 1, total do
			local pip = UI.Create("Frame", {
				Name = "Pip" .. i,
				LayoutOrder = i,
				Size = UDim2.fromOffset(16, 16),
				BackgroundColor3 = UI.Theme.PanelDark,
				ZIndex = 22,
				Parent = holder,
			}, { UI.Corner(8), UI.Stroke(BLACK, 2), UI.Create("UIScale", {}) })
			table.insert(pips, pip)
		end
	end
	for i, pip in ipairs(pips) do
		local filled = i <= wins
		local target = if filled then color else UI.Theme.PanelDark
		if pip.BackgroundColor3 ~= target then
			pip.BackgroundColor3 = target
			local scale = pip:FindFirstChildOfClass("UIScale")
			if scale and filled then
				UI.Pulse(scale, 0.6)
			end
		end
	end
end

local function refreshTopBar()
	if not match or not topBar then
		return
	end
	if isFfa() then
		local scores = match.Scores or {}
		local mine = scores[match.MyId] or 0
		local best, bestId = -1, nil
		for id, value in pairs(scores) do
			if value > best then
				best, bestId = value, id
			end
		end
		setText(leftName, T("match.ffa.me", mine))
		local leader = if bestId then (nameOf(bestId)) else "—"
		setText(rightName, T("match.ffa.leader", leader, math.max(0, best)))
		if leftName then
			leftName.TextColor3 = UI.Theme.Yellow
		end
		if rightName then
			rightName.TextColor3 = WHITE
		end
		local goal = (ctx.Config.Modes and ctx.Config.Modes.Modes.FFA.ScoreToWin) or 25
		rebuildPips(leftPips, 0, 0, WHITE)
		rebuildPips(rightPips, 0, 0, WHITE)
		setText(roundLabel, T("match.ffa.goal", goal))
		return
	end
	local my = match.MyTeam
	local other = if my == 2 then 1 else 2
	local score = match.Score or { 0, 0 }
	setText(leftName, teamName(my))
	setText(rightName, teamName(other))
	if leftName then
		leftName.TextColor3 = teamColor(my)
	end
	if rightName then
		rightName.TextColor3 = teamColor(other)
	end
	local rtw = match.RoundsToWin or 4
	rebuildPips(leftPips, score[my] or 0, rtw, teamColor(my))
	rebuildPips(rightPips, score[other] or 0, rtw, teamColor(other))
end

local function hideTransient()
	for _, frame in ipairs({ voteOverlay, introOverlay, prepBar, afkOverlay, recapPanel }) do
		if frame then
			frame.Visible = false
		end
	end
	if loadingLabel then
		loadingLabel.Visible = false
	end
end

-- ---------------------------------------------------------------------
-- 4) KARTENWAHL
-- ---------------------------------------------------------------------
local function refreshVoteCounts(counts: { number }?)
	for i, labelObj in ipairs(voteCountLabels) do
		local n = if counts then tonumber(counts[i]) or 0 else 0
		setText(labelObj, T("match.vote.count", n))
	end
	for i, button in ipairs(voteButtons) do
		button.SetColor(if i == myVote then UI.Theme.Yellow else UI.Theme.Blue)
	end
end

local function onFound(data: any)
	foundData = data
	myVote = 0
	hideTransient()
	if resultsFrame then
		resultsFrame.Visible = false
	end
	local overlay = voteOverlay
	local cards = voteCards
	if not overlay or not cards then
		return
	end
	for _, child in ipairs(cards:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	table.clear(voteCountLabels)
	table.clear(voteButtons)
	local sub = modeName(data.Mode)
	local mut = mutatorName(data.Mutator)
	if mut then
		sub ..= " · " .. mut
	end
	setText(voteTitle, T("match.found"))
	sfx("Go")
	local options = if type(data.VoteOptions) == "table" then data.VoteOptions else {}
	if #options == 0 then
		setText(voteTimer, sub)
		overlay.Visible = true
		overlay.Size = UDim2.fromOffset(560, 120)
		task.delay(1.6, function()
			if foundData == data and overlay.Visible then
				overlay.Visible = false
				if loadingLabel and match == nil then
					loadingLabel.Text = T("match.loading")
					loadingLabel.Visible = true
				end
			end
		end)
		return
	end
	overlay.Size = UDim2.fromOffset(760, 380)
	local entries = {}
	for i, opt in ipairs(options) do
		table.insert(entries, {
			Index = i,
			Title = mapName(opt.Map),
			Sub = T("match.mood." .. tostring(opt.Mood)),
		})
	end
	table.insert(entries, { Index = 4, Title = T("match.vote.random"), Sub = "?" })
	for order, entry in ipairs(entries) do
		local card = UI.Card({
			LayoutOrder = order,
			Size = UDim2.fromOffset(166, 240),
			BackgroundColor3 = UI.Theme.PanelLight,
			ZIndex = 32,
			Parent = cards,
		})
		label({
			Position = UDim2.fromOffset(8, 12),
			Size = UDim2.new(1, -16, 0, 26),
			Text = UI.Upper(entry.Sub),
			MaxText = 18,
			Outline = 2,
			TextColor3 = UI.Theme.Yellow,
			ZIndex = 33,
			Parent = card,
		})
		label({
			Position = UDim2.fromOffset(8, 42),
			Size = UDim2.new(1, -16, 0, 60),
			Text = entry.Title,
			MaxText = 26,
			Outline = 3,
			TextWrapped = true,
			ZIndex = 33,
			Parent = card,
		})
		local count = label({
			Position = UDim2.fromOffset(8, 110),
			Size = UDim2.new(1, -16, 0, 30),
			Text = T("match.vote.count", 0),
			MaxText = 20,
			Outline = 2,
			ZIndex = 33,
			Parent = card,
		})
		voteCountLabels[entry.Index] = count
		local button = UI.Button({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -12),
			Size = UDim2.new(1, -24, 0, 56),
			Text = T("match.vote.pick"),
			Color = UI.Theme.Blue,
			MaxText = 20,
			ZIndex = 34,
			Parent = card,
		}, function()
			myVote = entry.Index
			refreshVoteCounts(nil)
			request("VoteMap", entry.Index)
		end)
		voteButtons[entry.Index] = button
	end
	setText(voteTimer, sub)
	overlay.Visible = true
	refreshVoteCounts({ 0, 0, 0, 0 })
end

-- ---------------------------------------------------------------------
-- 5) START / INTRO / PREP / LIVE
-- ---------------------------------------------------------------------
local function sendArenaReady(slot: number, buildId: number, matchId: number)
	task.spawn(function()
		if slot ~= 0 then
			local deadline = os.clock() + ARENA_WAIT
			while os.clock() < deadline do
				local arenas = workspace:FindFirstChild("Arenas")
				local folder = arenas and arenas:FindFirstChild("Slot_" .. tostring(slot))
				local map = folder and folder:FindFirstChild("Map")
				if map and tonumber(map:GetAttribute("BuildId")) == buildId then
					break
				end
				task.wait(0.1)
			end
		end
		if match and match.Id == matchId then
			ctx.RequestFull("ArenaReady", buildId, true)
		end
	end)
end

local function onStart(data: any)
	local newMatch = match == nil or match.Id ~= data.MatchId
	if newMatch then
		match = {
			Id = data.MatchId,
			Mode = data.Mode,
			Mutator = data.Mutator,
			MyTeam = tonumber(data.MyTeam) or 1,
			MyId = tonumber(data.MyId) or player.UserId,
			RoundsToWin = tonumber(data.RoundsToWin) or 4,
			Score = { 0, 0 },
			Scores = {},
			Phase = "Load",
			EndsAt = 0,
			Tutorial = data.Tutorial == true,
			Tainted = data.Tainted == true,
		}
		table.clear(roster)
		reportedKiller = false
		for _, row in ipairs(killRows) do
			row.Frame:Destroy()
		end
		table.clear(killRows)
		hideTransient()
		if resultsFrame then
			resultsFrame.Visible = false
		end
		setCoreGui(false)
		if loadingLabel then
			loadingLabel.Text = T("match.loading")
			loadingLabel.Visible = true
		end
		sendArenaReady(tonumber(data.Slot) or 0, tonumber(data.BuildId) or 0, data.MatchId)
	end
	if type(data.Roster) == "table" then
		for _, entry in ipairs(data.Roster) do
			local id = tonumber(entry.Id)
			if id and id ~= 0 then
				roster[id] = {
					Slot = tonumber(entry.Slot) or 0,
					Id = id,
					Name = tostring(entry.Name or "?"),
					Team = tonumber(entry.Team) or 0,
					IsBot = entry.IsBot == true,
					Level = tonumber(entry.Level) or 0,
					Title = tostring(entry.Title or ""),
					Finisher = tostring(entry.Finisher or ""),
				}
			end
		end
	end
	if voteOverlay then
		voteOverlay.Visible = false
	end
	if topBar then
		topBar.Visible = true
	end
	if taintBadge then
		taintBadge.Visible = match.Tainted
	end
	refreshTopBar()
end

local function rosterBySlot(slot: number): RosterEntry?
	for _, entry in pairs(roster) do
		if entry.Slot == slot then
			return entry
		end
	end
	return nil
end

local function onIntro(data: any)
	if not match then
		return
	end
	match.Phase = "Intro"
	match.EndsAt = tonumber(data.EndsAt) or serverNow() + 2
	if data.Tainted == true then
		match.Tainted = true
		if taintBadge then
			taintBadge.Visible = true
		end
	end
	if loadingLabel then
		loadingLabel.Visible = false
	end
	local parent = root
	if not parent then
		return
	end
	if introOverlay then
		introOverlay:Destroy()
	end
	local frame = overlayFrame("Intro", parent, Vector2.new(780, 330), 30)
	frame.BackgroundTransparency = 0.05
	introOverlay = frame
	local my = match.MyTeam
	local ffa = isFfa()
	local title = if ffa
		then modeName(match.Mode)
		else ("%s  %s  %s"):format(teamName(my), T("match.intro.vs"), teamName(if my == 2 then 1 else 2))
	label({
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -32, 0, 60),
		Text = title,
		Font = UI.Fonts.Banner,
		MaxText = 52,
		Outline = 4,
		TextColor3 = UI.Theme.Yellow,
		ZIndex = 31,
		Parent = frame,
	})
	local function column(entries: { RosterEntry }, x: number, align: Enum.TextXAlignment, loadouts: { [number]: any })
		local y = 76
		for _, entry in ipairs(entries) do
			if y > 300 then
				break
			end
			local name = if entry.IsBot then T("match.scoreboard.bot") .. " " .. entry.Name else entry.Name
			if not entry.IsBot and entry.Level > 0 then
				name = ("[%d] %s"):format(entry.Level, name)
			end
			local line = name
			local titleStr = titleText(entry.Title)
			if titleStr ~= "" then
				line ..= "  · " .. titleStr
			end
			label({
				Position = UDim2.new(x, 12, 0, y),
				Size = UDim2.new(0.5, -24, 0, 26),
				Text = line,
				MaxText = 20,
				Outline = 2,
				TextXAlignment = align,
				TextColor3 = teamColor(entry.Team),
				ZIndex = 31,
				Parent = frame,
			})
			local extra = ""
			local lo = loadouts[entry.Slot]
			if lo then
				extra = ("%s · %s · %s · %s"):format(weaponShort(lo.P), weaponShort(lo.S), weaponShort(lo.M), weaponShort(lo.U))
			elseif entry.Finisher ~= "" then
				extra = T("match.intro.finisher", finisherName(entry.Finisher))
			end
			label({
				Position = UDim2.new(x, 12, 0, y + 26),
				Size = UDim2.new(0.5, -24, 0, 20),
				Text = extra,
				Font = UI.Fonts.Number,
				MaxText = 15,
				Outline = 1,
				TextXAlignment = align,
				TextColor3 = UI.Theme.SubText,
				ZIndex = 31,
				Parent = frame,
			})
			y += 52
		end
	end
	local loadouts: { [number]: any } = {}
	if type(data.Enemies) == "table" then
		for _, enemy in ipairs(data.Enemies) do
			local slot = tonumber(enemy.Slot)
			if slot then
				loadouts[slot] = enemy
			end
		end
	end
	local mine, theirs = {}, {}
	for _, entry in pairs(roster) do
		if entry.Team == my then
			table.insert(mine, entry)
		else
			table.insert(theirs, entry)
		end
	end
	table.sort(mine, function(a, b)
		return a.Slot < b.Slot
	end)
	table.sort(theirs, function(a, b)
		return a.Slot < b.Slot
	end)
	column(mine, 0, Enum.TextXAlignment.Left, {})
	column(theirs, 0.5, Enum.TextXAlignment.Right, loadouts)
	if match.Tainted then
		label({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.fromOffset(320, 26),
			Text = T("match.taintedBadge"),
			MaxText = 18,
			Outline = 2,
			TextColor3 = UI.Theme.Red,
			ZIndex = 31,
			Parent = frame,
		})
	end
	frame.Visible = true
	sfx("Countdown")
end

local function bindPrepControls()
	for _, unbind in ipairs(unbinds) do
		pcall(unbind)
	end
	table.clear(unbinds)
	local controls = module("Controls")
	if not controls or type(controls.Bind) ~= "function" then
		return
	end
	table.insert(
		unbinds,
		controls.Bind("Ready", function(state)
			if state == "Begin" and match and match.Phase == "Prep" and not ready then
				ready = true
				if readyButton then
					readyButton.SetText(T("match.readyDone"))
				end
				request("Ready")
			end
		end, 2)
	)
	table.insert(
		unbinds,
		controls.Bind("Loadout", function(state)
			if state == "Begin" and match and (match.Phase == "Prep" or match.Phase == "RoundEnd") then
				ctx.Windows.Open("Locker")
			end
		end, 2)
	)
end

local function onPrep(data: any)
	if not match then
		return
	end
	match.Phase = "Prep"
	match.EndsAt = tonumber(data.EndsAt) or serverNow() + 3
	match.Round = tonumber(data.Round) or 1
	if type(data.Score) == "table" then
		match.Score = { tonumber(data.Score[1]) or 0, tonumber(data.Score[2]) or 0 }
	end
	if data.Tainted == true and not match.Tainted then
		match.Tainted = true
		if taintBadge then
			taintBadge.Visible = true
		end
	end
	ready = false
	lastCountdown = 0
	if introOverlay then
		introOverlay.Visible = false
	end
	if loadingLabel then
		loadingLabel.Visible = false
	end
	if recapPanel then
		recapPanel.Visible = false
	end
	if zoneBar then
		zoneBar.Frame.Visible = false
	end
	if readyButton then
		readyButton.SetText(T("match.ready"))
	end
	if prepBar then
		prepBar.Visible = true
	end
	setText(roundLabel, T("match.round", match.Round))
	refreshTopBar()
	if data.SuddenDeath == true then
		showBanner(T("match.suddenDeath"), UI.Theme.Red, T("match.suddenDeathSub"), 3)
	elseif data.MatchPoint == true then
		showBanner(T("match.round", match.Round), WHITE, T("match.matchPoint"), 2)
	else
		showBanner(T("match.round", match.Round), WHITE, nil, 1.6)
	end
end

local function onLive(data: any)
	if not match then
		return
	end
	match.Phase = "Live"
	match.EndsAt = tonumber(data.EndsAt) or serverNow() + 60
	if prepBar then
		prepBar.Visible = false
	end
	if introOverlay then
		introOverlay.Visible = false
	end
	if loadingLabel then
		loadingLabel.Visible = false
	end
	local cd = countdownLabel
	if cd then
		cd.Text = T("match.go")
		cd.Visible = true
		if countdownScale then
			countdownScale.Scale = 1.8
			TweenService:Create(countdownScale, BANNER_POP, { Scale = 1 }):Play()
		end
		task.delay(0.8, function()
			if cd.Text == T("match.go") then
				cd.Visible = false
			end
		end)
	end
	sfx("Go")
end

local function onOvertime(data: any)
	if not match then
		return
	end
	if match.Phase ~= "Live" or not match.SdZone then
		match.EndsAt = tonumber(data.EndsAt) or match.EndsAt
	end
	match.Phase = "Overtime"
	if zoneBar then
		zoneBar.Frame.Visible = true
		UI.SetBar(zoneBar, 0, T("match.zone.empty"))
	end
	showBanner(T("match.overtime"), UI.Theme.Yellow, nil, 2.5)
	sfx("Countdown")
end

local function onZone(data: any)
	if not match or not zoneBar then
		return
	end
	zoneBar.Frame.Visible = true
	local team = tonumber(data.Team) or 0
	local progress = tonumber(data.Progress) or 0
	local text
	if data.Contested == true then
		text = T("match.zone.contested")
	elseif team == 0 then
		text = T("match.zone.empty")
	else
		text = T("match.zone.hold", teamName(team))
	end
	zoneBar.Fill.BackgroundColor3 = WHITE
	local gradient = zoneBar.Fill:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = UI.ButtonSequence(if team == 0 then UI.Theme.Gray else teamColor(team))
	end
	UI.SetBar(zoneBar, progress, text)
end

-- ---------------------------------------------------------------------
-- 6) KILLFEED + FINISHER
-- ---------------------------------------------------------------------
local MULTI_KEYS = { [2] = "match.double", [3] = "match.triple", [4] = "match.quad" }

local function coloredName(id: number?): string
	local name, isBot = nameOf(id)
	local text = escape(name)
	if isBot then
		return ('<font color="%s">%s %s</font>'):format(hex(GRAY), escape(T("match.scoreboard.bot")), text)
	end
	local entry = id and roster[id]
	local color = if entry then teamColor(entry.Team) else WHITE
	if match and id == match.MyId then
		color = UI.Theme.Yellow
	end
	return ('<font color="%s">%s</font>'):format(hex(color), text)
end

local function addKillRow(data: any)
	local feed = killfeed
	if not feed then
		return
	end
	local k, v = tonumber(data.K), tonumber(data.V)
	local parts = {}
	local fl = if type(data.Fl) == "table" then data.Fl else {}
	if k then
		local badges = ""
		if fl.Crown then
			badges ..= "👑"
		end
		if tonumber(fl.Streak) then
			badges ..= "🔥" .. tostring(fl.Streak)
		end
		if tonumber(fl.Bounty) then
			badges ..= "🪙"
		end
		if tonumber(fl.Mastery) then
			badges ..= "★" .. tostring(fl.Mastery)
		end
		table.insert(parts, badges .. coloredName(k))
	end
	local weapon = escape(weaponShort(data.W))
	if fl.Void then
		weapon = "↓ " .. weapon
	end
	if data.H == true then
		weapon ..= ' <font color="#ffd23f">★</font>'
	end
	table.insert(parts, ("[%s]"):format(weapon))
	table.insert(parts, coloredName(v))
	if type(data.A) == "table" and #data.A > 0 then
		local assist = tonumber(data.A[1])
		if assist and assist ~= k then
			table.insert(parts, "+ " .. coloredName(assist))
		end
	end
	local multi = tonumber(fl.Multi)
	if multi and MULTI_KEYS[math.min(multi, 4)] then
		table.insert(parts, ('<font color="#ffd23f">%s</font>'):format(escape(T(MULTI_KEYS[math.min(multi, 4)]))))
	end
	local mine = match and (k == match.MyId or v == match.MyId)
	local row = UI.Create("Frame", {
		Name = "Kill",
		Size = UDim2.fromOffset(440, 28),
		BackgroundColor3 = if mine then UI.Theme.Yellow:Lerp(BLACK, 0.55) else BLACK,
		BackgroundTransparency = if mine then 0.25 else 0.55,
		LayoutOrder = -math.floor(os.clock() * 100),
		ZIndex = 22,
		Parent = feed,
	}, { UI.Corner(8) })
	label({
		Position = UDim2.fromOffset(8, 2),
		Size = UDim2.new(1, -16, 1, -4),
		Text = table.concat(parts, "  "),
		RichText = true,
		MaxText = 18,
		Outline = 2,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 23,
		Parent = row,
	})
	table.insert(killRows, { Frame = row, Until = os.clock() + KILLFEED_SECONDS })
	while #killRows > KILLFEED_MAX do
		local old = table.remove(killRows, 1)
		if old then
			old.Frame:Destroy()
		end
	end
end

local function onElim(data: any)
	-- Finisher an der letzten Position (auch für Crown-Zuschauer)
	local fx = module("CombatFX")
	if fx and type(fx.Pop) == "function" and typeof(data.P) == "Vector3" then
		local color = if typeof(data.C) == "Color3" then data.C else UI.Theme.Yellow
		pcall(fx.Pop, data.P, tostring(data.Fin or "F_Confetti"), color)
	end
	if not match then
		return
	end
	addKillRow(data)
end

-- ---------------------------------------------------------------------
-- 7) TODES-RÜCKBLICK
-- ---------------------------------------------------------------------
local function onRecap(data: any)
	local panel = recapPanel
	if not panel or not match then
		return
	end
	for _, child in ipairs(panel:GetChildren()) do
		if not child:IsA("UICorner") and not child:IsA("UIStroke") then
			child:Destroy()
		end
	end
	local killerId = tonumber(data.KillerId)
	local killerEntry = killerId and roster[killerId]
	local isBot = killerEntry ~= nil and killerEntry.IsBot or (killerId ~= nil and killerId < -1000)
	UI.Create("ImageLabel", {
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = UI.Theme.PanelLight,
		Image = if killerId and killerId > 0 and not isBot
			then ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(killerId)
			else FACE,
		ZIndex = 29,
		Parent = panel,
	}, { UI.Corner(32), UI.Stroke(BLACK, 2) })
	local killerName = tostring(data.KillerName or (nameOf(killerId)))
	label({
		Position = UDim2.fromOffset(82, 10),
		Size = UDim2.new(1, -92, 0, 22),
		Text = T("match.recap.title"),
		MaxText = 14,
		Outline = 2,
		TextColor3 = UI.Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 29,
		Parent = panel,
	})
	label({
		Position = UDim2.fromOffset(82, 30),
		Size = UDim2.new(1, -92, 0, 28),
		Text = if isBot then T("match.scoreboard.bot") .. " " .. killerName else killerName,
		MaxText = 22,
		Outline = 3,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 29,
		Parent = panel,
	})
	local subline = weaponName(data.WeaponKey)
	if killerEntry and titleText(killerEntry.Title) ~= "" then
		subline = titleText(killerEntry.Title) .. " · " .. subline
	end
	label({
		Position = UDim2.fromOffset(82, 58),
		Size = UDim2.new(1, -92, 0, 18),
		Text = subline,
		MaxText = 14,
		Outline = 1,
		TextColor3 = UI.Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 29,
		Parent = panel,
	})
	label({
		Position = UDim2.fromOffset(10, 82),
		Size = UDim2.new(1, -20, 0, 30),
		Text = T("combat.hpLeft", math.max(0, math.floor((tonumber(data.KillerHp) or 0) + 0.5))),
		Font = UI.Fonts.Banner,
		MaxText = 26,
		Outline = 3,
		TextColor3 = UI.Theme.Red,
		ZIndex = 29,
		Parent = panel,
	})
	local list = UI.Create("Frame", {
		Position = UDim2.fromOffset(10, 116),
		Size = UDim2.new(1, -20, 0, 200),
		BackgroundTransparency = 1,
		ZIndex = 29,
		Parent = panel,
	}, { UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }) })
	local taken = if type(data.Taken) == "table" then data.Taken else {}
	local shown = 0
	for i = #taken, 1, -1 do
		local hit = taken[i]
		if shown >= 12 or type(hit) ~= "table" then
			break
		end
		shown += 1
		local text = ("%s  −%d  %s  %dm"):format(
			weaponShort(hit.W),
			math.floor((tonumber(hit.D) or 0) + 0.5),
			if hit.H == true then T("match.recap.head") else "",
			math.floor((tonumber(hit.Dist) or 0) + 0.5)
		)
		label({
			LayoutOrder = shown,
			Size = UDim2.new(1, 0, 0, 15),
			Text = text,
			Font = UI.Fonts.Number,
			MaxText = 13,
			Outline = 1,
			TextColor3 = if hit.H == true then UI.Theme.Yellow else WHITE,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 29,
			Parent = list,
		})
	end
	label({
		Position = UDim2.fromOffset(10, 322),
		Size = UDim2.new(1, -20, 0, 40),
		Text = T(
			"combat.dealt",
			math.floor((tonumber(data.DealtToKiller) or 0) + 0.5),
			tonumber(data.DealtHits) or 0,
			tonumber(data.DealtHeads) or 0
		),
		MaxText = 15,
		Outline = 2,
		TextWrapped = true,
		ZIndex = 29,
		Parent = panel,
	})
	if killerId and killerId > 0 and not isBot and not reportedKiller then
		local reportButton: any = nil
		reportButton = UI.Button({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.fromOffset(160, 40),
			Text = T("match.recap.report"),
			Color = UI.Theme.Red,
			MaxText = 18,
			ZIndex = 30,
			Parent = panel,
		}, function()
			if reportedKiller then
				return
			end
			reportedKiller = true
			reportButton.SetText(T("match.recap.reported"))
			request("Report", { UserId = killerId, Reason = "Other" })
		end)
	end
	panel.Visible = true
end

-- ---------------------------------------------------------------------
-- 8) RUNDEN-ENDE
-- ---------------------------------------------------------------------
local BANNER_KEYS = {
	Clutch = "match.clutch",
	Ace = "match.ace",
	Flawless = "match.flawless",
	Comeback = "match.comeback",
	MatchPoint = "match.matchPoint",
	SuddenDeath = "match.suddenDeath",
}

local function onRoundEnd(data: any)
	if not match then
		return
	end
	match.Phase = "RoundEnd"
	if type(data.Score) == "table" then
		match.Score = { tonumber(data.Score[1]) or 0, tonumber(data.Score[2]) or 0 }
	end
	if zoneBar then
		zoneBar.Frame.Visible = false
	end
	refreshTopBar()
	local winner = tonumber(data.Winner) or 0
	local title, color
	if winner == 0 then
		title, color = T("match.roundDraw"), WHITE
	elseif winner == match.MyTeam then
		title, color = T("match.roundWon"), teamColor(winner)
		sfx("Win")
	else
		title, color = T("match.roundLost"), teamColor(winner)
		sfx("Lose")
	end
	local subs = {}
	if type(data.Reason) == "string" then
		table.insert(subs, T("match.reason." .. data.Reason))
	end
	local flags: { [string]: boolean } = {}
	if type(data.Banners) == "table" then
		for _, key in ipairs(data.Banners) do
			flags[key] = true
			if BANNER_KEYS[key] then
				table.insert(subs, T(BANNER_KEYS[key]))
			end
		end
	end
	-- Skill-Momente: CLUTCH-/ACE-Bonus für mich
	local clutch = data.Clutch
	if type(clutch) == "table" and tonumber(clutch.Id) == match.MyId then
		local xp = tonumber(clutch.Xp) or 0
		showNotice(T("match.clutchYou", tonumber(clutch.Vs) or 2) .. (if xp > 0 then "  " .. T("match.bonusXp", xp) else ""), 3)
		confetti(1.5)
	elseif type(clutch) == "table" then
		local name = nameOf(tonumber(clutch.Id))
		showNotice(T("match.clutchBy", name, tonumber(clutch.Vs) or 2), 3)
	end
	local ace = data.Ace
	if type(ace) == "table" and tonumber(ace.Id) == match.MyId then
		local xp = tonumber(ace.Xp) or 0
		showNotice(T("match.aceYou") .. (if xp > 0 then "  " .. T("match.bonusXp", xp) else ""), 3)
		confetti(1.2)
	end
	if flags.Flawless and winner == match.MyTeam then
		confetti(0.8)
	end
	local mvp = tonumber(data.Mvp)
	if mvp then
		table.insert(subs, T("match.mvp", (nameOf(mvp))))
	end
	showBanner(title, color, table.concat(subs, "  ·  "), 2.4)
end

local function onScore(data: any)
	if not match or type(data.Scores) ~= "table" then
		return
	end
	local scores = {}
	for key, value in pairs(data.Scores) do
		local id = tonumber(key)
		if id then
			scores[id] = tonumber(value) or 0
		end
	end
	match.Scores = scores
	if tonumber(data.EndsAt) then
		match.EndsAt = tonumber(data.EndsAt)
	end
	refreshTopBar()
end

-- ---------------------------------------------------------------------
-- 9) ERGEBNIS
-- ---------------------------------------------------------------------
local function seasonInfo(): any
	local state = ctx.State and ctx.State.Season
	if type(state) == "table" and tonumber(state.TierXp) then
		return state
	end
	local seasons = ctx.Config.Season and ctx.Config.Season.Seasons
	return if type(seasons) == "table" then seasons[1] else nil
end

local function describeReward(reward: any): string
	if type(reward) ~= "table" then
		return ""
	end
	if ProgressMath and type(ProgressMath.DescribeReward) == "function" then
		local ok, text = pcall(ProgressMath.DescribeReward, reward, ctx.T)
		if ok and type(text) == "string" then
			return text
		end
	end
	local parts = {}
	for key, value in pairs(reward) do
		table.insert(parts, ("%s %s"):format(tostring(value), tostring(key)))
	end
	return table.concat(parts, " + ")
end

local function nextRewards(season: any, tier: number): (string, string)
	if type(season) ~= "table" then
		return "", ""
	end
	local free, prem = "", ""
	local maxTier = tonumber(season.Tiers) or 30
	for t = tier + 1, maxTier do
		local key = tostring(t)
		if free == "" and type(season.Free) == "table" and season.Free[key] then
			free = describeReward(season.Free[key])
		end
		if prem == "" and type(season.Premium) == "table" and season.Premium[key] then
			prem = describeReward(season.Premium[key])
		end
		if free ~= "" and prem ~= "" then
			break
		end
	end
	return free, prem
end

local function coinsHint(): string?
	local coins = tonumber(ctx.State and ctx.State.Coins) or 0
	local weapons = ctx.State and ctx.State.Weapons
	local owned = if type(weapons) == "table" and type(weapons.Owned) == "table" then weapons.Owned else {}
	local list = ctx.Config.Weapons and ctx.Config.Weapons.List
	if type(list) ~= "table" then
		return nil
	end
	local best: any = nil
	for _, base in ipairs(list) do
		local def = ctx.Config.Weapon(base.Key) or base
		if
			def.Enabled ~= false
			and not def.AdminOnly
			and not def.Free
			and not owned[def.Key]
			and (tonumber(def.Price) or 0) > coins
		then
			if best == nil or def.Price < best.Price then
				best = def
			end
		end
	end
	if best then
		return T("match.result.toWeapon", best.Price - coins, pick(best.Name))
	end
	return nil
end

local function resultsBar(parent: Frame, y: number, title: string, color: Color3): any
	label({
		Position = UDim2.fromOffset(20, y),
		Size = UDim2.fromOffset(160, 26),
		Text = title,
		MaxText = 18,
		Outline = 2,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 52,
		Parent = parent,
	})
	local bar = UI.Bar({
		Position = UDim2.fromOffset(184, y),
		Size = UDim2.new(1, -204, 0, 26),
		Color = color,
		MaxText = 15,
		Parent = parent,
	})
	bar.Frame.ZIndex = 52
	bar.Fill.ZIndex = 53
	bar.Text.ZIndex = 54
	return bar
end

local function onEnd(data: any)
	if not match then
		return
	end
	match.Phase = "MatchEnd"
	hideTransient()
	if zoneBar then
		zoneBar.Frame.Visible = false
	end
	local frame = resultsFrame
	if not frame then
		return
	end
	for _, child in ipairs(frame:GetChildren()) do
		if not child:IsA("UICorner") and not child:IsA("UIStroke") and not child:IsA("UIGradient") then
			child:Destroy()
		end
	end
	local me = if type(data.Me) == "table" then data.Me else {}
	local stats = if type(me.Stats) == "table" then me.Stats else {}
	local winner = tonumber(data.Winner) or 0
	local draw = data.Draw == true
	local won = not draw and winner == match.MyTeam
	local titleText_, color
	if draw then
		titleText_, color = T("match.result.draw"), WHITE
	elseif won then
		titleText_, color = T("match.result.win"), UI.Theme.Yellow
	elseif isFfa() then
		local mine = match.Scores[match.MyId] or 0
		local place = 1
		for id, value in pairs(match.Scores) do
			if id ~= match.MyId and value > mine then
				place += 1
			end
		end
		titleText_, color = T("match.result.place", place), WHITE
	else
		titleText_, color = T("match.result.loss"), UI.Theme.Red
	end
	if won then
		sfx("Win")
		confetti(2)
	elseif not draw then
		sfx("Lose")
	end
	label({
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -32, 0, 64),
		Text = titleText_,
		Font = UI.Fonts.Banner,
		MaxText = 56,
		Outline = 5,
		TextColor3 = color,
		ZIndex = 51,
		Parent = frame,
	})
	if data.Tainted == true then
		label({
			Position = UDim2.fromOffset(16, 70),
			Size = UDim2.new(1, -32, 0, 20),
			Text = T("match.taintedBadge"),
			MaxText = 15,
			Outline = 2,
			TextColor3 = UI.Theme.Red,
			ZIndex = 51,
			Parent = frame,
		})
	end
	-- MVP + Werte
	local acc = math.floor((tonumber(stats.Acc) or 0) * 100 + 0.5)
	local statLine = ("%s  %d/%d/%d   ·   %s  %d   ·   %s  %d%%"):format(
		T("match.result.kda"),
		tonumber(stats.K) or 0,
		tonumber(stats.D) or 0,
		tonumber(stats.A) or 0,
		T("match.result.damage"),
		tonumber(stats.Dmg) or 0,
		T("match.result.accuracy"),
		acc
	)
	if me.Mvp == true then
		statLine = "⭐ " .. T("match.result.mvp") .. "   ·   " .. statLine
	end
	label({
		Position = UDim2.fromOffset(16, 94),
		Size = UDim2.new(1, -32, 0, 28),
		Text = statLine,
		MaxText = 18,
		Outline = 2,
		ZIndex = 51,
		Parent = frame,
	})
	-- Balken: XP -> Coins -> Meisterschaft -> Pass (nacheinander)
	local xpBar = resultsBar(frame, 132, T("match.result.xp"), UI.Theme.Cyan)
	local coinBar = resultsBar(frame, 166, T("match.result.coins"), UI.Theme.Gold)
	local masteryBar = resultsBar(frame, 200, T("match.result.mastery", weaponShort(me.MasteryWeapon)), UI.Theme.Purple)
	local passBar = resultsBar(frame, 234, T("match.result.pass"), UI.Theme.Pink)
	local xpNext = tonumber(me.XpNext) or 0
	local xpIn = tonumber(me.XpInLevel) or 0
	local level = tonumber(me.Level) or 1
	local season = seasonInfo()
	local tierXp = if season then tonumber(season.TierXp) or 3000 else 3000
	local passAfter = tonumber(me.PassXpAfter) or 0
	local passBefore = tonumber(me.PassXpBefore) or passAfter
	local tier = math.floor(passAfter / tierXp)
	local masteryAfter = tonumber(me.MasteryAfter) or 0
	local masteryBefore = tonumber(me.MasteryBefore) or masteryAfter
	local masteryRatio, masteryText = 0, ("+%d"):format(math.max(0, masteryAfter - masteryBefore))
	if ProgressMath and type(ProgressMath.MasteryTier) == "function" then
		local okT, tierNow = pcall(ProgressMath.MasteryTier, masteryAfter)
		local okG, goal = pcall(ProgressMath.MasteryGoal, if okT then tierNow else 0)
		if okT and okG and type(goal) == "number" and goal > 0 then
			masteryRatio = math.clamp(masteryAfter / goal, 0, 1)
			masteryText = ("%s %d · %d/%d"):format(T("match.result.tier"), tierNow, masteryAfter, goal)
		elseif okT then
			masteryRatio = 1
			masteryText = ("%s %d"):format(T("match.result.tier"), tierNow)
		end
	end
	local steps = {
		function()
			UI.SetBar(
				xpBar,
				if xpNext > 0 then xpIn / xpNext else 1,
				("+%d XP  ·  Lv %d"):format(tonumber(me.XpGain) or 0, level)
			)
		end,
		function()
			UI.SetBar(coinBar, 1, ("+%d"):format(tonumber(me.Coins) or 0))
			local hud = module("Hud")
			if hud and type(hud.PulseCoins) == "function" and (tonumber(me.Coins) or 0) > 0 then
				pcall(hud.PulseCoins, tonumber(me.Coins))
			end
		end,
		function()
			UI.SetBar(masteryBar, masteryRatio, masteryText)
		end,
		function()
			UI.SetBar(
				passBar,
				(passAfter % tierXp) / tierXp,
				("%s %d  ·  +%d"):format(T("match.result.tier"), tier, math.max(0, passAfter - passBefore))
			)
		end,
	}
	for i, fn in ipairs(steps) do
		task.delay(0.35 + (i - 1) * 0.55, function()
			if match and match.Phase == "MatchEnd" then
				fn()
			end
		end)
	end
	-- nächste Pass-Belohnungen (Premium mit Schloss, B23.5)
	local free, prem = nextRewards(season, tier)
	local passState = ctx.State and ctx.State.Pass
	local premium = type(passState) == "table" and passState.Premium == true
	local passLine = ""
	if free ~= "" then
		passLine = T("match.result.free", free)
	end
	if prem ~= "" then
		passLine ..= (if passLine ~= "" then "   ·   " else "") .. T("match.result.premium", prem) .. (if premium then "" else " 🔒")
	end
	label({
		Position = UDim2.fromOffset(20, 262),
		Size = UDim2.new(1, -40, 0, 20),
		Text = passLine,
		MaxText = 14,
		Outline = 1,
		TextColor3 = UI.Theme.SubText,
		ZIndex = 51,
		Parent = frame,
	})
	-- Quest-Häkchen
	local questLines = {}
	if type(me.QuestTicks) == "table" then
		for i, q in ipairs(me.QuestTicks) do
			if i > 3 then
				break
			end
			local goal = tonumber(q.Goal) or 1
			local p = tonumber(q.P) or 0
			local mark = if p >= goal then "✅" else "▶"
			table.insert(questLines, ("%s %s  %d/%d"):format(mark, T("prog.q." .. tostring(q.Id), goal), math.min(p, goal), goal))
		end
	end
	label({
		Position = UDim2.fromOffset(20, 286),
		Size = UDim2.new(1, -40, 0, 60),
		Text = table.concat(questLines, "\n"),
		MaxText = 15,
		Outline = 1,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 51,
		Parent = frame,
	})
	-- Hinweise "Nur noch 40 XP bis Level 12!" / "120 Coins bis Fernschuss"
	local hints = {}
	if xpNext > 0 then
		table.insert(hints, T("match.result.toLevel", math.max(0, xpNext - xpIn), level + 1))
	end
	local coinText = coinsHint()
	if coinText then
		table.insert(hints, coinText)
	end
	label({
		Position = UDim2.fromOffset(20, 348),
		Size = UDim2.new(1, -40, 0, 24),
		Text = table.concat(hints, "   ·   "),
		MaxText = 16,
		Outline = 2,
		TextColor3 = UI.Theme.Yellow,
		ZIndex = 51,
		Parent = frame,
	})
	-- Knöpfe
	local row = UI.Create("Frame", {
		Position = UDim2.fromOffset(16, 382),
		Size = UDim2.new(1, -32, 0, 60),
		BackgroundTransparency = 1,
		ZIndex = 51,
		Parent = frame,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local mode = match.Mode
	local ggButton: any = nil
	ggButton = UI.Button({
		LayoutOrder = 1,
		Size = UDim2.fromOffset(100, 54),
		Text = T("match.result.gg"),
		Color = UI.Theme.Green,
		MaxText = 22,
		ZIndex = 52,
		Parent = row,
	}, function()
		ggButton.SetText("GG ✓")
		request("PressGG")
	end)
	UI.Button({
		LayoutOrder = 2,
		Size = UDim2.fromOffset(110, 54),
		Text = T("match.result.commend"),
		Color = UI.Theme.Cyan,
		MaxText = 20,
		ZIndex = 52,
		Parent = row,
	}, function()
		local board = module("Scoreboard")
		if board and type(board.Show) == "function" then
			pcall(board.Show, true)
		end
	end)
	rematchButton = nil
	if data.Rematch ~= false then
		rematchButton = UI.Button({
			LayoutOrder = 3,
			Size = UDim2.fromOffset(150, 54),
			Text = T("match.result.rematch", 0, 1),
			Color = UI.Theme.Orange,
			MaxText = 20,
			ZIndex = 52,
			Parent = row,
		}, function()
			request("Rematch")
		end)
	end
	if mode ~= "Crown" and mode ~= "Practice" then
		UI.Button({
			LayoutOrder = 4,
			Size = UDim2.fromOffset(150, 54),
			Text = T("match.result.again"),
			Color = UI.Theme.Yellow,
			MaxText = 18,
			ZIndex = 52,
			Parent = row,
		}, function()
			ctx.Request("LeaveMatch")
			local controls = module("Controls")
			local input = if controls and type(controls.Input) == "function" then controls.Input() else "KBM"
			ctx.Request("QueueJoin", { Mode = mode, Input = input })
		end)
	end
	UI.Button({
		LayoutOrder = 5,
		Size = UDim2.fromOffset(110, 54),
		Text = T("match.result.lobby"),
		Color = UI.Theme.Red,
		MaxText = 20,
		ZIndex = 52,
		Parent = row,
	}, function()
		request("LeaveMatch")
	end)
	-- Auto-Requeue-Haken
	local settings = ctx.State and ctx.State.Settings
	if type(settings) == "table" and type(settings.AutoRequeue) == "boolean" and not MatchUI._AutoTouched then
		autoRequeue = settings.AutoRequeue
	end
	local autoButton: any = nil
	local function autoText(): string
		return T("match.result.autoRequeue") .. ": " .. T(if autoRequeue then "match.on" else "match.off")
	end
	if mode ~= "Crown" and mode ~= "Practice" then
		autoButton = UI.Button({
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 16, 1, -12),
			Size = UDim2.fromOffset(300, 40),
			Text = autoText(),
			Color = if autoRequeue then UI.Theme.Green else UI.Theme.Gray,
			MaxText = 16,
			ZIndex = 52,
			Parent = frame,
		}, function()
			autoRequeue = not autoRequeue
			MatchUI._AutoTouched = true
			autoButton.SetText(autoText())
			autoButton.SetColor(if autoRequeue then UI.Theme.Green else UI.Theme.Gray)
			request("AutoRequeue", autoRequeue)
		end)
	end
	resultsTimer = label({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(300, 30),
		Text = "",
		MaxText = 16,
		Outline = 2,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 52,
		Parent = frame,
	})
	local matchCfg = ctx.Config.Modes and ctx.Config.Modes.Match or {}
	resultsUntil = os.clock() + (if mode == "Crown" then matchCfg.CrownResults or 4 else matchCfg.Results or 10)
	frame.Visible = true
	-- Starter-Karte NUR wenn der Server ein Angebot mitschickt (B23)
	if type(data.Offer) == "string" and data.Offer ~= "" then
		local shop = module("Shop")
		if shop and type(shop.BuildStarterCard) == "function" then
			local ok, card = pcall(shop.BuildStarterCard, frame)
			if ok and typeof(card) == "Instance" and card:IsA("GuiObject") then
				card.AnchorPoint = Vector2.new(0.5, 0.5)
				card.Position = UDim2.fromScale(0.5, 0.5)
				card.ZIndex = 60
				for _, d in ipairs(card:GetDescendants()) do
					if d:IsA("GuiObject") then
						d.ZIndex = math.max(d.ZIndex, 60) + 1
					end
				end
				UI.Button({
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 1, 8),
					Size = UDim2.fromOffset(220, 48),
					Text = T("match.result.later"),
					Color = UI.Theme.Gray,
					MaxText = 22,
					ZIndex = 62,
					Parent = card,
				}, function()
					card:Destroy()
				end)
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- 10) TAKT + ABSCHLUSS
-- ---------------------------------------------------------------------
local function onClosed()
	match = nil
	foundData = nil
	table.clear(roster)
	hideTransient()
	for _, frame in ipairs({ topBar, resultsFrame }) do
		if frame then
			frame.Visible = false
		end
	end
	for _, labelObj in ipairs({ bannerLabel, subBanner, countdownLabel, noticeLabel, taintBadge }) do
		if labelObj then
			labelObj.Visible = false
		end
	end
	for _, row in ipairs(killRows) do
		row.Frame:Destroy()
	end
	table.clear(killRows)
	setCoreGui(true)
end

local accum = 0
local function step(dt: number)
	accum += dt
	if accum < REFRESH then
		return
	end
	accum = 0
	local clock = os.clock()
	if bannerLabel and bannerLabel.Visible and clock >= bannerUntil then
		bannerLabel.Visible = false
		if subBanner then
			subBanner.Visible = false
		end
	end
	if noticeLabel and noticeLabel.Visible and clock >= noticeUntil then
		noticeLabel.Visible = false
	end
	for i = #killRows, 1, -1 do
		if clock >= killRows[i].Until then
			killRows[i].Frame:Destroy()
			table.remove(killRows, i)
		end
	end
	-- Kartenwahl-Countdown
	if voteOverlay and voteOverlay.Visible and foundData and tonumber(foundData.VoteEnds) then
		local left = math.max(0, math.ceil(foundData.VoteEnds - serverNow()))
		local sub = modeName(foundData.Mode)
		local mut = mutatorName(foundData.Mutator)
		if mut then
			sub ..= " · " .. mut
		end
		setText(voteTimer, ("%s  ·  %s"):format(sub, T("match.vote.timer", left)))
	end
	if not match then
		return
	end
	local now = serverNow()
	local left = math.max(0, (match.EndsAt or 0) - now)
	if match.Phase == "Live" or match.Phase == "Overtime" or match.Phase == "Prep" or match.Phase == "Intro" then
		setText(timerLabel, formatTime(left))
		if timerLabel then
			timerLabel.TextColor3 = if match.Phase == "Overtime" or (match.Phase == "Live" and left <= 10)
				then UI.Theme.Red
				else WHITE
		end
	end
	-- 3-2-1 in den letzten Prep-Sekunden
	local cd = countdownLabel
	if match.Phase == "Prep" and cd then
		local n = math.ceil(left)
		if n >= 1 and n <= 3 then
			if n ~= lastCountdown then
				lastCountdown = n
				cd.Text = tostring(n)
				cd.Visible = true
				if countdownScale then
					countdownScale.Scale = 1.6
					TweenService:Create(countdownScale, BANNER_POP, { Scale = 1 }):Play()
				end
				sfx("Countdown")
			end
		elseif cd.Visible and cd.Text ~= T("match.go") then
			cd.Visible = false
		end
	end
	if match.Phase == "MatchEnd" and resultsTimer then
		setText(resultsTimer, T("match.result.backIn", math.max(0, math.ceil(resultsUntil - clock))))
	end
end

function MatchUI.InMatch(): boolean
	return match ~= nil
end

MatchUI._AutoTouched = false

function MatchUI.Init(context: any)
	ctx = context
	local progressModule = ReplicatedStorage:WaitForChild("Shared"):FindFirstChild("ProgressMath")
	if progressModule and progressModule:IsA("ModuleScript") then
		local ok, result = pcall(require, progressModule)
		if ok and type(result) == "table" then
			ProgressMath = result
		end
	end
	local frame = UI.Create("Frame", {
		Name = "MatchUI",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = ctx.Gui,
	})
	root = frame
	buildTopBar(frame)
	buildBanners(frame)
	buildKillfeed(frame)
	buildPrep(frame)
	buildAfk(frame)
	buildVote(frame)
	buildRecap(frame)
	buildResults(frame)
end

function MatchUI.Start()
	local hooks = ctx.Hooks
	hooks.On("Match:Found", onFound)
	hooks.On("Match:Vote", function(data)
		if type(data) == "table" then
			refreshVoteCounts(data.Counts)
		end
	end)
	hooks.On("Match:Start", onStart)
	hooks.On("Match:Intro", onIntro)
	hooks.On("Match:Prep", onPrep)
	hooks.On("Match:Live", onLive)
	hooks.On("Match:Overtime", onOvertime)
	hooks.On("Match:Zone", onZone)
	hooks.On("Match:AntiCamp", function()
		if match then
			showNotice(T("match.antiCamp"), 1.5)
		end
	end)
	hooks.On("Match:Elim", onElim)
	hooks.On("Match:Recap", onRecap)
	hooks.On("Match:RoundEnd", onRoundEnd)
	hooks.On("Match:Score", onScore)
	hooks.On("Match:End", onEnd)
	hooks.On("Match:Rematch", function(data)
		if rematchButton and type(data) == "table" then
			rematchButton.SetText(T("match.result.rematch", tonumber(data.Votes) or 0, tonumber(data.Needed) or 1))
		end
	end)
	hooks.On("Match:Afk", function(data)
		if afkOverlay and type(data) == "table" then
			afkOverlay.Visible = data.Warn == true
			if data.Warn == true then
				sfx("UIError")
			end
		end
	end)
	hooks.On("Match:Closed", onClosed)
	hooks.On("LocalRevived", function()
		if recapPanel then
			recapPanel.Visible = false
		end
	end)
	bindPrepControls()
	RunService.Heartbeat:Connect(step)
end

return MatchUI
