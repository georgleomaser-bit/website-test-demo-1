-- =====================================================================
--  AKYTEX TYCOON – Bestenlisten & Wochen-Liga (Client/Modules/Boards)
--  Besitzer: WP9 (Fortschritt, Tutorial, Sozial, Bestenlisten). Vertrag: DESIGN.md §B11.1 (6 Bestenlisten, Ansicht
--  Global / Freunde / Server, Liga nach Skill-Score statt Kontogröße, absolute Liga-Stufen, Admin-Fenster ausgenommen),
--  §B11.5 (kein öffentliches Verlust-Zeigen), §C7.3 (Fenster "Boards"), §C7.5 (Boards.Open(board?)).
--
--  Öffentliche API (§C7.5):  Boards.Open(board?)   Fenster öffnen, optional direkt auf einer Liste ("League" …)
--  Zusätzlich: Boards.Init(ctx), Boards.Start()
--  Anfragen: BoardsGet { Board, Scope } (1/s, Server antwortet aus dem Cache).  State: "League" (eigene Stufe).
--  Avatare über rbxthumb:// (keine Web-Anfrage vom Client nötig).
-- =====================================================================

local UI = require(script.Parent:WaitForChild("UI"))

local Boards = {}

local Theme = UI.Theme

local WINDOW_W, WINDOW_H = 680, 620
local CACHE_SECONDS = 30 -- gleiche Liste/Ansicht höchstens so oft neu anfragen
local REQUEST_GAP = 1.05 -- Server-Rate 1/s
local SCOPES = { "Global", "Friends", "Server" }
local MEDALS = { Theme.Gold, Color3.fromRGB(192, 199, 212), Color3.fromRGB(205, 127, 50) }

local ctx: any = nil
local window: any = nil
local boardSeg: any = nil
local scopeSeg: any = nil
local board = "League"
local scope = "Global"
local ui: { [string]: any } = {}
local cache: { [string]: { At: number, Reply: any } } = {}
local lastRequestAt = 0
local loadingKey: string? = nil
local token = 0

-- ---------------------------------------------------------------------
-- 1) HELFER
-- ---------------------------------------------------------------------
local function T(key: string, ...: any): string
	return ctx.T(key, ...)
end

local function num(v: any, default: number): number
	return if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then v else default
end

local function boardList(): { any }
	local p = ctx.Config.Progression
	local list = type(p) == "table" and p.Boards and p.Boards.List or nil
	return if type(list) == "table" then list else {}
end

local function isBoard(key: any): boolean
	for _, def in ipairs(boardList()) do
		if def.Key == key then
			return true
		end
	end
	return false
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

local function tierName(key: any): string
	if type(key) ~= "string" or key == "" then
		key = "None"
	end
	return T("prog.tier." .. key)
end

-- ---------------------------------------------------------------------
-- 2) ZEILEN
-- ---------------------------------------------------------------------
local function row(parent: Instance, order: number, entry: { [string]: any }, mine: boolean)
	local card = UI.RowCard(parent, order, 52)
	if mine then
		card.BackgroundColor3 = Theme.AccentDeep
	end
	local rank = math.floor(num(entry.Rank, order))
	UI.Label({
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.fromOffset(44, 52),
		Text = "#" .. tostring(rank),
		Face = "MonoBold",
		TextColor3 = MEDALS[rank] or Theme.Text2,
		MaxText = 18,
		Parent = card,
	})
	local userId = math.floor(num(entry.UserId, 0))
	local avatar = UI.Create("ImageLabel", {
		Position = UDim2.fromOffset(56, 6),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = Theme.Bg2,
		Image = if userId > 0 then string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48", userId) else "",
		Parent = card,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }), UI.Stroke(MEDALS[rank] or Theme.Border, 1) })
	avatar.ScaleType = Enum.ScaleType.Crop
	UI.Label({
		Position = UDim2.fromOffset(106, 0),
		Size = UDim2.new(1, -290, 1, 0),
		Text = tostring(entry.Name or ""),
		Face = "BodyBold",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = if mine then Theme.Text else Theme.Text,
		MaxText = 17,
		Parent = card,
	})
	UI.Label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 0),
		Size = UDim2.fromOffset(170, 52),
		Text = tostring(entry.Text or ""),
		Face = "Mono",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Gold,
		MaxText = 16,
		Parent = card,
	})
end

local function renderReply(reply: any)
	if not window then
		return
	end
	clear(ui.List)
	local rows = type(reply) == "table" and type(reply.Rows) == "table" and reply.Rows or {}
	local myId = ctx.Player.UserId
	if #rows == 0 then
		text(ui.List, {
			Size = UDim2.new(1, 0, 0, 40),
			LayoutOrder = 1,
			Text = T("soc.board.empty"),
			MaxText = 16,
			TextColor3 = Theme.Muted,
		})
	end
	for i, entry in ipairs(rows) do
		if type(entry) == "table" then
			row(ui.List, i, entry, entry.UserId == myId)
		end
	end
	local me = type(reply) == "table" and type(reply.Me) == "table" and reply.Me or {}
	local rankText = if type(me.Rank) == "number" then T("soc.board.rank", me.Rank) else T("soc.board.noRank")
	ui.Me.Text = T("soc.board.you", tostring(me.Text or "—")) .. "  ·  " .. rankText
end

local function renderStatic()
	ui.Info.Text = T("soc.board.info." .. board)
	local league = ctx.State.League
	league = if type(league) == "table" then league else {}
	local isLeague = board == "League" or board == "Return"
	ui.Tiers.Visible = isLeague
	ui.Tier.Visible = isLeague
	ui.Admin.Visible = isLeague
	if isLeague then
		ui.Tiers.Text = T("soc.board.tiers")
		ui.Tier.Text = T("soc.board.tier", tierName(league.Tier), math.floor(num(league.SkillScore, 0)))
		ui.Admin.Text = T("soc.board.adminWindow")
	end
end

local function load(force: boolean?)
	if not window then
		return
	end
	renderStatic()
	local key = board .. "|" .. scope
	local hit = cache[key]
	if hit and not force and os.clock() - hit.At < CACHE_SECONDS then
		renderReply(hit.Reply)
		return
	end
	if loadingKey == key then
		return
	end
	loadingKey = key
	token += 1
	local mine = token
	ui.Me.Text = T("soc.board.loading")
	task.spawn(function()
		local wait = REQUEST_GAP - (os.clock() - lastRequestAt)
		if wait > 0 then
			task.wait(wait)
		end
		lastRequestAt = os.clock()
		local reply = ctx.RequestFull("BoardsGet", { Board = board, Scope = scope }, true)
		if loadingKey == key then
			loadingKey = nil
		end
		if reply.Ok then
			cache[key] = { At = os.clock(), Reply = reply }
		end
		if mine == token and board .. "|" .. scope == key then
			renderReply(if reply.Ok then reply else hit and hit.Reply or {})
		end
	end)
end

-- ---------------------------------------------------------------------
-- 3) FENSTER
-- ---------------------------------------------------------------------
local function buildWindow()
	window = UI.Window(T("soc.win.boards"), WINDOW_W, WINDOW_H, Theme.Gold)
	local content = window.Content
	local options = {}
	for _, def in ipairs(boardList()) do
		table.insert(options, { Key = def.Key, Text = T("soc.board." .. def.Key) })
	end
	boardSeg = UI.Segmented(content, options, function(key: string)
		board = key
		load(false)
	end)
	boardSeg.Frame.LayoutOrder = 1
	local scopeOptions = {}
	for _, key in ipairs(SCOPES) do
		table.insert(scopeOptions, { Key = key, Text = T("soc.scope." .. key) })
	end
	scopeSeg = UI.Segmented(content, scopeOptions, function(key: string)
		scope = key
		load(false)
	end)
	scopeSeg.Frame.LayoutOrder = 2
	ui.Info = text(content, {
		Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = 3,
		Face = "Body",
		TextWrapped = true,
		MaxText = 13,
		TextColor3 = Theme.Text2,
	})
	ui.Tiers = text(content, { Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 4, Face = "Mono", MaxText = 13 })
	ui.Tier = text(content, {
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 5,
		Face = "BodyBold",
		MaxText = 15,
		TextColor3 = Theme.Gold,
	})
	ui.Admin = text(content, { Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 6, MaxText = 12, TextColor3 = Theme.Muted })
	local meRow = UI.Row(content, 7, 40)
	ui.Me = text(meRow, { Size = UDim2.new(1, -60, 1, 0), Face = "BodyBold", MaxText = 15, LayoutOrder = 1 })
	UI.Button(
		{ Size = UDim2.fromOffset(44, 38), Text = "↻", Variant = "Ghost", LayoutOrder = 2, Parent = meRow },
		function()
			load(true)
		end
	)
	ui.List = UI.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 8,
		Parent = content,
	}, { UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }) })
end

local function openWindow()
	if not window then
		buildWindow()
	end
	boardSeg.Set(board, true)
	scopeSeg.Set(scope, true)
	UI.OpenWindow(window)
	load(false)
end

local function closeWindow()
	if window and window.IsOpen then
		UI.CloseWindow(window)
	end
end

function Boards.Open(which: string?)
	if which ~= nil and isBoard(which) then
		board = which :: string
	end
	ctx.Windows.Open("Boards")
end

function Boards.Init(context: any)
	ctx = context
	ctx.Windows.Register("Boards", openWindow, closeWindow)
end

function Boards.Start()
	ctx.Hooks.On("State", function(_state: any, changed: any)
		if type(changed) == "table" and changed.League and window and window.IsOpen then
			renderStatic()
		end
	end)
	ctx.Hooks.On("Settings", function()
		table.clear(cache) -- Werte-Texte sind serverseitig lokalisiert
	end)
end

return Boards
