-- =====================================================================
--  CLUTCH CLASH – Scoreboard im Match (Client/Modules/Scoreboard)
--  Besitzer: WP5 (Match-UI). Vertrag: DESIGN.md B14.7, C7.4.
--
--  Tab halten / View (Gamepad) / Knopf (Touch): pro Team Avatar, Name, Level-Abzeichen, Titel, K/D/A,
--  Schaden, Ping (Player-Attribut "PingMs", vom Server alle 2 s), [BOT]. Knöpfe Loben 👍 (nach dem Match,
--  Request "Commend") und Melden ⚑ (Request "Report", 1× pro Spieler und Match).
--  Datenquelle: Roster aus Match:Start, live K/D/A aus Match:Elim, Schaden aus den Stats-Schnappschüssen
--  in Match:RoundEnd / Match:End (Server-Werte gewinnen). Außerhalb eines Matches unsichtbar.
--
--  Öffentliche API: Scoreboard.Show(on), Scoreboard.Toggle(), Scoreboard.IsOpen(), Scoreboard.Init(ctx), Scoreboard.Start()
-- =====================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local UI = require(script.Parent:WaitForChild("UI"))

local Scoreboard = {}

local player = Players.LocalPlayer
local ctx: any = nil

local ROW_H = 46
local REFRESH = 0.5
local FACE = "rbxasset://textures/face.png"

type Row = {
	Id: number,
	Name: string,
	Team: number,
	IsBot: boolean,
	Level: number,
	Title: string,
	K: number,
	D: number,
	A: number,
	Dmg: number,
	Score: number?,
}

local rows: { [number]: Row } = {}
local order: { number } = {}
local inMatch = false
local matchOver = false
local matchMode: string? = nil
local myTeam = 0
local myId = player.UserId
local reported: { [number]: boolean } = {}
local commended = false
local open = false
local holding = false
local root: Frame? = nil
local listFrame: Frame? = nil
local titleLabel: TextLabel? = nil
local touchButton: TextButton? = nil
local accum = 0
local dirty = true
local currentMatchId: any = nil

local function T(key: string, ...: any): string
	return if ctx then ctx.T(key, ...) else key
end

local function teamColor(team: number): Color3
	local colors = ctx and ctx.Config and ctx.Config.Colors
	if matchMode == "FFA" then
		return UI.Theme.Pink
	end
	if colors then
		return if team == 2 then colors.TeamB else colors.TeamA
	end
	return if team == 2 then UI.Theme.Cyan else UI.Theme.Orange
end

local function titleText(title: string): string
	if title == "" then
		return ""
	end
	local cosmetics = ctx and ctx.Config and ctx.Config.Cosmetics
	local def = cosmetics and type(cosmetics.Titles) == "table" and cosmetics.Titles[title]
	if def and type(def.Name) == "table" then
		return ctx.Lang.Pick(ctx.Lang_(), def.Name)
	end
	return title
end

local function playerById(id: number): Player?
	if id == 0 then
		return nil
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.UserId == id then
			return p
		end
	end
	return nil
end

-- ---------------------------------------------------------------------
-- Aufbau
-- ---------------------------------------------------------------------
local function build()
	local gui = ctx.Gui
	local frame = UI.Create("Frame", {
		Name = "Scoreboard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromOffset(640, 440),
		BackgroundColor3 = UI.Theme.PanelDark,
		BackgroundTransparency = 0.1,
		Visible = false,
		ZIndex = 40,
		Parent = gui,
	}, { UI.Corner(16), UI.Stroke(UI.Theme.Black, 3) })
	titleLabel = UI.Label({
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 0, 34),
		Text = T("match.scoreboard.title"),
		MaxText = 26,
		Outline = 3,
		ZIndex = 41,
		Parent = frame,
	})
	-- Spaltenköpfe
	local head = UI.Create("Frame", {
		Position = UDim2.fromOffset(12, 42),
		Size = UDim2.new(1, -24, 0, 22),
		BackgroundTransparency = 1,
		ZIndex = 41,
		Parent = frame,
	})
	local columns = {
		{ "match.scoreboard.name", 0.06, 0.4 },
		{ "match.scoreboard.kda", 0.5, 0.16 },
		{ "match.scoreboard.damage", 0.66, 0.12 },
		{ "match.scoreboard.ping", 0.78, 0.1 },
	}
	for _, col in ipairs(columns) do
		UI.Label({
			Position = UDim2.fromScale(col[2], 0),
			Size = UDim2.fromScale(col[3], 1),
			Text = T(col[1]),
			MaxText = 14,
			Outline = 2,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 41,
			Parent = head,
		})
	end
	local list = UI.Create("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(12, 68),
		Size = UDim2.new(1, -24, 1, -80),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 41,
		Parent = frame,
	}, {
		UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }),
	})
	listFrame = list
	root = frame

	-- Touch: kleiner Knopf oben links (nur im Match sichtbar)
	local button = UI.Create("TextButton", {
		Name = "ScoreboardButton",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(12, 70),
		Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = UI.Theme.PanelDark,
		Text = "☰",
		TextScaled = true,
		Font = UI.Font,
		TextColor3 = Color3.new(1, 1, 1),
		Visible = false,
		ZIndex = 30,
		Parent = ctx.TouchGui or gui,
	}, { UI.Corner(12), UI.Stroke(UI.Theme.Black, 2) })
	button.Activated:Connect(function()
		Scoreboard.Toggle()
	end)
	touchButton = button
end

local function sortedIds(): { number }
	local ids: { number } = {}
	for id in pairs(rows) do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local ra, rb = rows[a], rows[b]
		if ra.Team ~= rb.Team then
			-- eigenes Team zuerst
			if ra.Team == myTeam then
				return true
			elseif rb.Team == myTeam then
				return false
			end
			return ra.Team < rb.Team
		end
		local sa = (ra.Score or 0) * 1000 + ra.K * 10 + ra.A
		local sb = (rb.Score or 0) * 1000 + rb.K * 10 + rb.A
		if sa ~= sb then
			return sa > sb
		end
		return a < b
	end)
	return ids
end

local function request(action: string, arg: any)
	task.spawn(function()
		if ctx then
			ctx.Request(action, arg)
		end
	end)
end

local function redraw()
	local list = listFrame
	if not list then
		return
	end
	dirty = false
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	order = sortedIds()
	for i, id in ipairs(order) do
		local r = rows[id]
		local color = teamColor(r.Team)
		local mine = id == myId
		local row = UI.Create("Frame", {
			Name = "Row" .. i,
			LayoutOrder = i,
			Size = UDim2.new(1, -8, 0, ROW_H),
			BackgroundColor3 = if mine then UI.Theme.Yellow:Lerp(color, 0.35) else color:Lerp(UI.Theme.PanelDark, 0.45),
			ZIndex = 42,
			Parent = list,
		}, { UI.Corner(10), UI.Stroke(UI.Theme.Black, 2) })
		local p = playerById(id)
		UI.Create("ImageLabel", {
			Position = UDim2.fromOffset(4, 3),
			Size = UDim2.fromOffset(ROW_H - 6, ROW_H - 6),
			BackgroundColor3 = UI.Theme.PanelLight,
			Image = if p
					and id > 0
					and not r.IsBot
				then ("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48"):format(id)
				else FACE,
			ZIndex = 43,
			Parent = row,
		}, { UI.Corner(20) })
		local nameText = r.Name
		if r.IsBot then
			nameText = T("match.scoreboard.bot") .. " " .. nameText
		elseif r.Level > 0 then
			nameText = ("[%d] %s"):format(r.Level, nameText)
		end
		local title = titleText(r.Title)
		UI.Label({
			Position = UDim2.new(0.06, 8, 0, 2),
			Size = UDim2.new(0.42, 0, 0, if title ~= "" then 24 else ROW_H - 4),
			Text = nameText,
			MaxText = 20,
			Outline = 2,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if r.IsBot then Color3.fromRGB(200, 200, 205) else Color3.new(1, 1, 1),
			ZIndex = 43,
			Parent = row,
		})
		if title ~= "" then
			UI.Label({
				Position = UDim2.new(0.06, 8, 0, 25),
				Size = UDim2.new(0.42, 0, 0, 17),
				Text = title,
				MaxText = 13,
				Outline = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = UI.Theme.SubText,
				ZIndex = 43,
				Parent = row,
			})
		end
		local kda = ("%d / %d / %d"):format(r.K, r.D, r.A)
		if r.Score ~= nil then
			kda = ("%d  ·  %s"):format(r.Score, kda)
		end
		UI.Label({
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromScale(0.16, 1),
			Text = kda,
			Font = UI.Fonts.Number,
			MaxText = 18,
			Outline = 2,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 43,
			Parent = row,
		})
		UI.Label({
			Position = UDim2.fromScale(0.66, 0),
			Size = UDim2.fromScale(0.12, 1),
			Text = tostring(math.floor(r.Dmg + 0.5)),
			Font = UI.Fonts.Number,
			MaxText = 18,
			Outline = 2,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 43,
			Parent = row,
		})
		local ping = UI.Label({
			Name = "Ping",
			Position = UDim2.fromScale(0.78, 0),
			Size = UDim2.fromScale(0.1, 1),
			Text = if r.IsBot then "BOT" else "–",
			Font = UI.Fonts.Number,
			MaxText = 16,
			Outline = 2,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 43,
			Parent = row,
		})
		ping:SetAttribute("UserId", id)
		-- Loben (nach dem Match) / Melden (Menschen, nicht man selbst)
		if not r.IsBot and not mine and p then
			if matchOver and not commended then
				local commend = UI.Create("TextButton", {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -46, 0.5, 0),
					Size = UDim2.fromOffset(38, 34),
					BackgroundColor3 = UI.Theme.Green,
					Text = "👍",
					TextScaled = true,
					Font = UI.Font,
					ZIndex = 44,
					Parent = row,
				}, { UI.Corner(8), UI.Stroke(UI.Theme.Black, 2) })
				commend.Activated:Connect(function()
					if commended then
						return
					end
					commended = true
					request("Commend", id)
					dirty = true
				end)
			end
			if not reported[id] then
				local report = UI.Create("TextButton", {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -4, 0.5, 0),
					Size = UDim2.fromOffset(38, 34),
					BackgroundColor3 = UI.Theme.Red,
					Text = "⚑",
					TextScaled = true,
					Font = UI.Font,
					TextColor3 = Color3.new(1, 1, 1),
					ZIndex = 44,
					Parent = row,
				}, { UI.Corner(8), UI.Stroke(UI.Theme.Black, 2) })
				report.Activated:Connect(function()
					if reported[id] then
						return
					end
					reported[id] = true
					request("Report", { UserId = id, Reason = "Other" })
					dirty = true
				end)
			end
		end
	end
end

local function refreshPings()
	local list = listFrame
	if not list then
		return
	end
	for _, row in ipairs(list:GetChildren()) do
		local ping = row:FindFirstChild("Ping")
		if ping and ping:IsA("TextLabel") then
			local id = tonumber(ping:GetAttribute("UserId")) or 0
			local p = playerById(id)
			if p then
				local ms = tonumber(p:GetAttribute("PingMs"))
				local text = if ms then tostring(math.floor(ms + 0.5)) else "–"
				if ping.Text ~= text then
					ping.Text = text
				end
			end
		end
	end
end

function Scoreboard.Show(on: boolean)
	open = on and inMatch
	local frame = root
	if frame then
		frame.Visible = open
	end
	if open then
		if titleLabel then
			local key = if matchOver then "match.scoreboard.final" else "match.scoreboard.title"
			titleLabel.Text = T(key)
		end
		redraw()
		refreshPings()
	end
end

function Scoreboard.Toggle()
	Scoreboard.Show(not open)
end

function Scoreboard.IsOpen(): boolean
	return open
end

-- ---------------------------------------------------------------------
-- Daten
-- ---------------------------------------------------------------------
local function applySnapshot(stats: any)
	if type(stats) ~= "table" then
		return
	end
	for key, value in pairs(stats) do
		local id = tonumber(key)
		local r = id and rows[id]
		if r and type(value) == "table" then
			r.K = tonumber(value.K) or r.K
			r.D = tonumber(value.D) or r.D
			r.A = tonumber(value.A) or r.A
			r.Dmg = tonumber(value.Dmg) or r.Dmg
		end
	end
	dirty = true
end

local function onStart(data: any)
	if type(data) ~= "table" then
		return
	end
	local newMatch = not inMatch or data.MatchId ~= currentMatchId
	currentMatchId = data.MatchId
	inMatch = true
	matchMode = data.Mode
	myTeam = tonumber(data.MyTeam) or 0
	myId = tonumber(data.MyId) or player.UserId
	if newMatch then
		table.clear(rows)
		table.clear(reported)
		commended = false
		matchOver = false
	end
	if type(data.Roster) == "table" then
		local seen: { [number]: boolean } = {}
		for _, entry in ipairs(data.Roster) do
			local id = tonumber(entry.Id)
			if id and id ~= 0 then
				seen[id] = true
				local old = rows[id]
				rows[id] = {
					Id = id,
					Name = tostring(entry.Name or "?"),
					Team = tonumber(entry.Team) or 0,
					IsBot = entry.IsBot == true,
					Level = tonumber(entry.Level) or 0,
					Title = tostring(entry.Title or ""),
					K = if old then old.K else 0,
					D = if old then old.D else 0,
					A = if old then old.A else 0,
					Dmg = if old then old.Dmg else 0,
					Score = if old then old.Score else nil,
				}
			end
		end
		for id in pairs(rows) do
			if not seen[id] then
				rows[id] = nil
			end
		end
	end
	local button = touchButton
	if button then
		local controls = ctx.Modules.Controls
		button.Visible = controls ~= nil and type(controls.Input) == "function" and controls.Input() == "Touch"
	end
	dirty = true
end

local function onElim(data: any)
	if type(data) ~= "table" or not inMatch then
		return
	end
	local k, v = tonumber(data.K), tonumber(data.V)
	if k and rows[k] and k ~= v then
		rows[k].K += 1
	end
	if v and rows[v] then
		rows[v].D += 1
	end
	if type(data.A) == "table" then
		for _, a in ipairs(data.A) do
			local id = tonumber(a)
			if id and rows[id] and id ~= k then
				rows[id].A += 1
			end
		end
	end
	dirty = true
end

local function onClosed()
	inMatch = false
	matchOver = false
	table.clear(rows)
	Scoreboard.Show(false)
	if touchButton then
		touchButton.Visible = false
	end
end

local function step(dt: number)
	if not open then
		return
	end
	accum += dt
	if accum < REFRESH then
		return
	end
	accum = 0
	if dirty then
		redraw()
	end
	refreshPings()
end

function Scoreboard.Init(context: any)
	ctx = context
	build()
end

function Scoreboard.Start()
	local hooks = ctx.Hooks
	hooks.On("Match:Start", onStart)
	hooks.On("Match:Elim", onElim)
	hooks.On("Match:RoundEnd", function(data)
		if type(data) == "table" then
			applySnapshot(data.Stats)
		end
	end)
	hooks.On("Match:Score", function(data)
		if type(data) ~= "table" or type(data.Scores) ~= "table" then
			return
		end
		for key, value in pairs(data.Scores) do
			local id = tonumber(key)
			if id and rows[id] then
				rows[id].Score = tonumber(value) or 0
			end
		end
		dirty = true
	end)
	hooks.On("Match:End", function(data)
		matchOver = true
		if type(data) == "table" then
			applySnapshot(data.Stats)
		end
	end)
	hooks.On("Match:Left", function(data)
		local id = type(data) == "table" and tonumber(data.Id) or nil
		if id and rows[id] then
			rows[id] = nil
			dirty = true
		end
	end)
	hooks.On("Match:Closed", onClosed)
	hooks.On("Input", function(kind)
		if touchButton then
			touchButton.Visible = inMatch and kind == "Touch"
		end
	end)
	local controls = ctx.Modules.Controls
	if controls and type(controls.Bind) == "function" then
		controls.Bind("Scoreboard", function(state)
			if state == "Begin" then
				holding = true
				Scoreboard.Show(true)
			elseif state == "End" and holding then
				holding = false
				Scoreboard.Show(false)
			end
		end)
	end
	RunService.Heartbeat:Connect(step)
end

return Scoreboard
