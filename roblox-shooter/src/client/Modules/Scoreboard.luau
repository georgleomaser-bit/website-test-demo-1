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
--  Stil: docs/STYLE-AKYTEX.md – Glas-Fenster, Zeilen als Karten (Surface2, 1-px-Rahmen), Team-Streifen links
--  (eigenes Team Accent, Gegner Down), eigene Zeile mit Akzent-Rahmen, Zahlen in Titillium Web, Bots Muted.
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

-- Team-Akzent aus Sicht des Spielers (AKYTEX): eigenes Team Accent, Gegner Down; FFA: ich Accent, andere Muted
local function teamColor(team: number): Color3
	local theme = UI.Theme
	if matchMode == "FFA" then
		return if team == myTeam then theme.Accent else theme.Muted
	end
	return if team == myTeam then theme.Accent else theme.Down
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
	local theme = UI.Theme
	-- Glas-Fenster (AKYTEX): Surface, 1-px-Rahmen, Ecke 16, Titel Michroma mit Akzent-Unterstrich
	local frame = UI.Create("Frame", {
		Name = "Scoreboard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromOffset(640, 440),
		BackgroundColor3 = theme.Surface,
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 40,
		Parent = gui,
	}, { UI.Corner(16), UI.Stroke(nil, 1) })
	titleLabel = UI.Label({
		Position = UDim2.fromOffset(20, 14),
		Size = UDim2.new(1, -40, 0, 24),
		Text = T("match.scoreboard.title"),
		Font = UI.Fonts.Heading,
		MaxText = 20,
		TextColor3 = theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 41,
		Parent = frame,
	})
	UI.Create("Frame", {
		Name = "Underline",
		Position = UDim2.fromOffset(20, 42),
		Size = UDim2.fromOffset(28, 2),
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		ZIndex = 41,
		Parent = frame,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	-- Spaltenköpfe (leise, Muted)
	local head = UI.Create("Frame", {
		Position = UDim2.fromOffset(16, 52),
		Size = UDim2.new(1, -32, 0, 18),
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
			Position = UDim2.new(col[2], 8, 0, 0),
			Size = UDim2.fromScale(col[3], 1),
			Text = T(col[1]),
			Font = UI.Fonts.Main,
			MaxText = 12,
			TextColor3 = theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 41,
			Parent = head,
		})
	end
	UI.Create("Frame", {
		Name = "Divider",
		Position = UDim2.fromOffset(16, 74),
		Size = UDim2.new(1, -32, 0, 1),
		BackgroundColor3 = theme.Border,
		BorderSizePixel = 0,
		ZIndex = 41,
		Parent = frame,
	})
	local list = UI.Create("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(16, 82),
		Size = UDim2.new(1, -24, 1, -96),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = theme.Muted,
		ScrollBarImageTransparency = 0.3,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 41,
		Parent = frame,
	}, {
		UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }),
	})
	listFrame = list
	root = frame

	-- Touch: kleiner Glas-Knopf oben links (nur im Match sichtbar)
	local button = UI.Create("TextButton", {
		Name = "ScoreboardButton",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(12, 70),
		Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = theme.Surface,
		BackgroundTransparency = 0.12,
		AutoButtonColor = false,
		Text = "☰",
		TextScaled = true,
		Font = UI.Fonts.Main,
		TextColor3 = theme.Text,
		Visible = false,
		ZIndex = 30,
		Parent = ctx.TouchGui or gui,
	}, {
		UI.Corner(12),
		UI.Stroke(nil, 1),
		UI.Create("UIPadding", {
			PaddingTop = UDim.new(0, 12),
			PaddingBottom = UDim.new(0, 12),
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 12),
		}),
	})
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
	local theme = UI.Theme
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
		-- Zeile = Karte (Surface2, 1-px-Rahmen); eigene Zeile mit Akzent-Rahmen, Team-Streifen links
		local row = UI.Create("Frame", {
			Name = "Row" .. i,
			LayoutOrder = i,
			Size = UDim2.new(1, -8, 0, ROW_H),
			BackgroundColor3 = if mine then theme.Hover else theme.Surface2,
			BorderSizePixel = 0,
			ZIndex = 42,
			Parent = list,
		}, { UI.Corner(10), UI.Stroke(if mine then theme.Accent else nil, 1) })
		UI.Create("Frame", {
			Name = "Stripe",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.new(0, 3, 1, -16),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = 43,
			Parent = row,
		}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		local p = playerById(id)
		UI.Create("ImageLabel", {
			Position = UDim2.fromOffset(8, 5),
			Size = UDim2.fromOffset(ROW_H - 10, ROW_H - 10),
			BackgroundColor3 = theme.Bg2,
			Image = if p
					and id > 0
					and not r.IsBot
				then ("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48"):format(id)
				else FACE,
			ZIndex = 43,
			Parent = row,
		}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		local nameText = r.Name
		if r.IsBot then
			nameText = T("match.scoreboard.bot") .. " " .. nameText
		elseif r.Level > 0 then
			nameText = ("[%d] %s"):format(r.Level, nameText)
		end
		local title = titleText(r.Title)
		UI.Label({
			Position = UDim2.new(0.06, 14, 0, if title ~= "" then 4 else 2),
			Size = UDim2.new(0.42, -6, 0, if title ~= "" then 22 else ROW_H - 4),
			Text = nameText,
			Font = UI.Fonts.Main,
			MaxText = 18,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if r.IsBot then theme.Muted elseif mine then theme.Accent else theme.Text,
			ZIndex = 43,
			Parent = row,
		})
		if title ~= "" then
			UI.Label({
				Position = UDim2.new(0.06, 14, 0, 26),
				Size = UDim2.new(0.42, -6, 0, 15),
				Text = title,
				Font = UI.Fonts.Body,
				MaxText = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = theme.Text2,
				ZIndex = 43,
				Parent = row,
			})
		end
		local kda = ("%d / %d / %d"):format(r.K, r.D, r.A)
		if r.Score ~= nil then
			kda = ("%d  ·  %s"):format(r.Score, kda)
		end
		UI.Label({
			Position = UDim2.new(0.5, 8, 0, 0),
			Size = UDim2.fromScale(0.16, 1),
			Text = kda,
			Font = UI.Fonts.Number,
			MaxText = 17,
			TextColor3 = theme.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 43,
			Parent = row,
		})
		UI.Label({
			Position = UDim2.new(0.66, 8, 0, 0),
			Size = UDim2.fromScale(0.12, 1),
			Text = tostring(math.floor(r.Dmg + 0.5)),
			Font = UI.Fonts.Number,
			MaxText = 17,
			TextColor3 = theme.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 43,
			Parent = row,
		})
		local ping = UI.Label({
			Name = "Ping",
			Position = UDim2.new(0.78, 8, 0, 0),
			Size = UDim2.fromScale(0.1, 1),
			Text = if r.IsBot then "BOT" else "–",
			Font = UI.Fonts.Number,
			MaxText = 15,
			TextColor3 = theme.Text2,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 43,
			Parent = row,
		})
		ping:SetAttribute("UserId", id)
		-- Loben (nach dem Match) / Melden (Menschen, nicht man selbst)
		if not r.IsBot and not mine and p then
			if matchOver and not commended then
				UI.Button({
					Name = "Commend",
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -48, 0.5, 0),
					Size = UDim2.fromOffset(38, 32),
					Text = "👍",
					Variant = "Success",
					Corner = 10,
					MaxText = 16,
					ZIndex = 44,
					Parent = row,
				}, function()
					if commended then
						return
					end
					commended = true
					request("Commend", id)
					dirty = true
				end)
			end
			if not reported[id] then
				UI.Button({
					Name = "Report",
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -6, 0.5, 0),
					Size = UDim2.fromOffset(38, 32),
					Text = "⚑",
					Variant = "Ghost",
					Corner = 10,
					MaxText = 16,
					ZIndex = 44,
					Parent = row,
				}, function()
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
