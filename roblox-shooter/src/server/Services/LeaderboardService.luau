-- =====================================================================
--  CLUTCH CLASH – Globale Bestenlisten (Server/Services/LeaderboardService)
--  Besitzer: WP8 (Fortschritt). Vertrag: DESIGN.md C5.8 + B16.9 + C14, MH-Muster (REUSE §9) mit Fixes §14.3 #10.
--
--  Öffentliche API (C5.8):
--    LeaderboardService.Submit(p)   Werte des Spielers zum Schreiben vormerken (frühestens alle 300 s, nur geänderte)
--  6 Tafeln (Config.Progression.Leaderboards): Wins (PvP-Siege) · Elims (PvP-Pops) · BestStreak · TotalXP ·
--  WeeklyWins (Store mit ISO-Woche) · CrownBest. OrderedDataStores "CC_LB_<Name>_v1" bzw. "CC_LB_WeeklyWins_<IsoWeek>",
--  Key = UserId, Wert ganzzahlig 0..9e15. Schreiben: geänderte Werte, frühestens alle 300 s pro Spieler und beim
--  Verlassen (DataService.OnProfileReleasing). Tainted-/Bot-Matches rufen Submit nie auf (ProgressionService).
--  Lesen: Top 10 je Tafel alle 300 s, 0.5 s versetzt. Anzeige: SurfaceGui auf LobbyBuilder.Boards() mit
--  rbxthumb-Avataren, Namens-Cache max. 200. Neue #1 (Spieler in diesem Server) -> Lobby-Ansage.
--  Studio ohne Speichern (NoSave) / Test-Spieler (UserId ≤ 0): kein Schreiben.
-- =====================================================================

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Types = require(Shared:WaitForChild("Types"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local LeaderboardService = {}
local Services: any = nil

local P = Config.Progression
local TECH = Config.Tech
local PREFIX = if type(TECH.BoardPrefix) == "string" then TECH.BoardPrefix else "CC_LB_"
local WRITE_EVERY = math.max(60, tonumber(TECH.BoardWriteSeconds) or 300)
local READ_EVERY = WRITE_EVERY
local READ_STAGGER = 0.5
local ROWS = math.clamp(tonumber(P.BoardRows) or 10, 1, 10)
local NAME_CACHE_MAX = math.max(20, tonumber(P.BoardNameCache) or 200)
local MAX_VALUE = 9e15
local FIRST_READ_DELAY = 8
local LOG_GAP = 30

-- Titel in Michroma (breit, technisch) – ohne Emojis, kurz und GROSS (STYLE-AKYTEX)
local BOARD_TITLES: { [string]: string } = {
	Wins = "SIEGE · WINS",
	Elims = "POPS · ELIMS",
	BestStreak = "BESTE SERIE · BEST STREAK",
	TotalXP = "GESAMT-XP · TOTAL XP",
	WeeklyWins = "SIEGE DIESE WOCHE · WEEKLY WINS",
	CrownBest = "KRONEN-SERIE · CROWN STREAK",
}
local EMPTY_TEXT = "Noch keine Einträge – sei der Erste!\nNo entries yet – be the first!"

-- AKYTEX-Farben (Server hat kein UI.Theme -> dieselben Hex-Werte als Konstanten, docs/STYLE-AKYTEX.md)
local AKY_BG = Color3.fromRGB(11, 15, 23) -- AKYTEX-Farbe Bg #0b0f17
local AKY_SURFACE2 = Color3.fromRGB(26, 33, 48) -- AKYTEX-Farbe Surface2 #1a2130
local AKY_BORDER = Color3.fromRGB(31, 41, 55) -- AKYTEX-Farbe Border #1f2937
local AKY_TEXT = Color3.fromRGB(230, 236, 245) -- AKYTEX-Farbe Text #e6ecf5
local AKY_TEXT2 = Color3.fromRGB(170, 180, 195) -- AKYTEX-Farbe Text2 #aab4c3
local AKY_MUTED = Color3.fromRGB(125, 136, 154) -- AKYTEX-Farbe Muted #7d889a
local AKY_ACCENT = Color3.fromRGB(79, 140, 255) -- AKYTEX-Farbe Accent #4f8cff
local AKY_UP = Color3.fromRGB(34, 197, 94) -- AKYTEX-Farbe Up #22c55e
local AKY_WARN = Color3.fromRGB(234, 179, 8) -- AKYTEX-Farbe Warn #eab308 (Gold/Platz 1)
local FONT_TITLE = Enum.Font.Michroma
local FONT_TEXT = Enum.Font.BuilderSansBold
local FONT_NUMBER = Enum.Font.TitilliumWeb
-- Platz 1–3: Gold (Warn), Silber (Text2), Bronze – nur als Akzent (Rang-Zahl + Streifen)
local RANK_COLORS = {
	AKY_WARN,
	AKY_TEXT2,
	Color3.fromRGB(205, 127, 50),
}

type Row = { UserId: number, Value: number }
type BoardUi = {
	Gui: SurfaceGui,
	Rows: { { Frame: Frame, Rank: TextLabel, Avatar: ImageLabel, Name: TextLabel, Value: TextLabel } },
	Empty: TextLabel,
}

-- Pro-Spieler-Tabellen (alle bei PlayerRemoving geleert)
local lastWritten: { [Player]: { [string]: number } } = {} -- Store-Name -> zuletzt geschriebener Wert
local lastWriteAt: { [Player]: number } = {}
local pending: { [Player]: boolean } = {}
local writing: { [Player]: boolean } = {}

local stores: { [string]: OrderedDataStore } = {}
local boardUis: { [string]: BoardUi } = {}
local topUser: { [string]: number } = {}
local lastRows: { [string]: string } = {}
local nameCache: { [number]: string } = {}
local nameOrder: { number } = {}
local lastLogAt: { [string]: number } = {}
local readRunning = false
local readDisabled = false
local NO_API_HINTS = { "studio", "publish", "api services", "403" }

-- ---------------------------------------------------------------------
-- 0) HELFER
-- ---------------------------------------------------------------------
local function logError(where: string, err: any)
	local now = os.clock()
	if (lastLogAt[where] or -math.huge) + LOG_GAP <= now then
		lastLogAt[where] = now
		warn("[LeaderboardService] " .. where .. ": " .. tostring(err))
	end
end

local function num(v: any): number
	if Util.IsFinite(v) then
		return v
	end
	return 0
end

local function try(service: string, fnName: string, ...: any): (boolean, any)
	local s = Services and Services[service]
	local fn = s and s[fnName]
	if type(fn) ~= "function" then
		return false, nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		logError(service .. "." .. fnName, result)
		return false, nil
	end
	return true, result
end

local function storeName(board: string): string
	if board == "WeeklyWins" then
		return PREFIX .. "WeeklyWins_" .. tostring(Util.IsoWeek())
	end
	return PREFIX .. board .. "_v1"
end

local function storeFor(name: string): OrderedDataStore?
	local store = stores[name]
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	if not ok then
		logError("GetOrderedDataStore", result)
		return nil
	end
	-- alte Wochen-Stores vergessen (Speicher bleibt klein)
	for key in pairs(stores) do
		if string.find(key, "WeeklyWins_", 1, true) and key ~= name and string.find(name, "WeeklyWins_", 1, true) then
			stores[key] = nil
		end
	end
	stores[name] = result
	return result
end

-- Tafelwert aus dem Spielstand (ganzzahlig, geklemmt)
local function valueOf(data: Types.PlayerData, board: string): number
	local stats = if type(data.Stats) == "table" then data.Stats else {}
	local v = 0
	if board == "Wins" then
		v = num(stats.PvpWins)
	elseif board == "Elims" then
		v = num(stats.PvpElims)
	elseif board == "BestStreak" then
		v = num(stats.BestStreak)
	elseif board == "TotalXP" then
		v = num(data.TotalXP)
	elseif board == "WeeklyWins" then
		v = if stats.WeeklyWinsWeek == Util.IsoWeek() then num(stats.WeeklyWins) else 0
	elseif board == "CrownBest" then
		v = num(stats.CrownBest)
	end
	return math.floor(math.clamp(v, 0, MAX_VALUE))
end

local function canWrite(p: Player): boolean
	if p.UserId <= 0 then
		return false
	end
	local ok, noSave = try("DataService", "IsNoSave", p)
	return not (ok and noSave == true)
end

-- ---------------------------------------------------------------------
-- 1) SCHREIBEN (nur geänderte Werte)
-- ---------------------------------------------------------------------
local function collectChanges(p: Player, data: Types.PlayerData): { { Store: string, Value: number } }
	local changes = {}
	local written = lastWritten[p] or {}
	for _, board in ipairs(P.Leaderboards) do
		local name = storeName(board)
		local value = valueOf(data, board)
		if value > 0 and written[name] ~= value then
			table.insert(changes, { Store = name, Value = value })
		end
	end
	return changes
end

-- yieldet (SetAsync); immer in eigenem Thread aufrufen
local function writeChanges(p: Player, userId: number, changes: { { Store: string, Value: number } })
	for _, change in ipairs(changes) do
		local store = storeFor(change.Store)
		if store then
			local ok, err = pcall(function()
				store:SetAsync(tostring(userId), change.Value)
			end)
			if ok then
				local written = lastWritten[p]
				if written then
					written[change.Store] = change.Value
				end
			else
				logError("SetAsync " .. change.Store, err)
			end
		end
	end
end

local function writePlayer(p: Player, force: boolean)
	if writing[p] or not canWrite(p) then
		return
	end
	local now = os.clock()
	if not force and now - (lastWriteAt[p] or -math.huge) < WRITE_EVERY then
		return
	end
	local ok, data = try("DataService", "Get", p)
	if not ok or type(data) ~= "table" then
		return
	end
	lastWritten[p] = lastWritten[p] or {}
	local changes = collectChanges(p, data)
	pending[p] = nil
	if #changes == 0 then
		return
	end
	lastWriteAt[p] = now
	writing[p] = true
	local userId = p.UserId
	task.spawn(function()
		writeChanges(p, userId, changes)
		writing[p] = nil
	end)
end

function LeaderboardService.Submit(p: Player)
	if typeof(p) ~= "Instance" or not p:IsA("Player") or p.Parent ~= Players then
		return
	end
	pending[p] = true
	writePlayer(p, false)
end

local function writeTick()
	for _, p in ipairs(Players:GetPlayers()) do
		-- vorgemerkt oder Intervall abgelaufen (dann nur, wenn sich etwas geändert hat)
		if pending[p] or os.clock() - (lastWriteAt[p] or 0) >= WRITE_EVERY then
			writePlayer(p, false)
		end
	end
end

-- Beim Verlassen: letzter Stand sofort (eigener Thread, der Release wartet nicht darauf)
local function onReleasing(p: Player, data: Types.PlayerData)
	if not canWrite(p) or type(data) ~= "table" then
		return
	end
	local changes = collectChanges(p, data)
	if #changes > 0 then
		local userId = p.UserId
		task.spawn(writeChanges, p, userId, changes)
	end
end

-- ---------------------------------------------------------------------
-- 2) TAFELN BAUEN (SurfaceGui im AKYTEX-Look: dunkle Glas-Tafel, 1-px-Rahmen, Titel Michroma,
--    Zeilen Surface2/Bg im Wechsel, Werte grün, Platz 1–3 mit Gold/Silber/Bronze-Akzent)
-- ---------------------------------------------------------------------
local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		(inst :: any)[key] = value
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- 1-px-Rahmen (AKYTEX: UIStroke Thickness 1, ApplyStrokeMode Border)
local function border(parent: Instance, color: Color3, transparency: number?)
	make("UIStroke", {
		Thickness = 1.5,
		Color = color,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function buildBoard(board: string, part: BasePart)
	local old = part:FindFirstChild("CC_Board")
	if old then
		old:Destroy()
	end
	local faceName = part:GetAttribute("BoardFace")
	local face = Enum.NormalId.Front
	if type(faceName) == "string" then
		local okFace, parsed = pcall(function()
			return (Enum.NormalId :: any)[faceName]
		end)
		if okFace and typeof(parsed) == "EnumItem" then
			face = parsed
		end
	end
	local gui: SurfaceGui = make("SurfaceGui", {
		Name = "CC_Board",
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 30,
		LightInfluence = 0,
		MaxDistance = 300,
		ResetOnSpawn = false,
		Adornee = part,
	})
	-- Glas-Tafel: Bg, leicht durchsichtig, Ecke 16, feiner Rahmen
	local root: Frame = make("Frame", {
		Name = "Panel",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = AKY_BG,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 16) }, root)
	border(root, AKY_BORDER)
	make("UIPadding", {
		PaddingLeft = UDim.new(0.04, 0),
		PaddingRight = UDim.new(0.04, 0),
		PaddingTop = UDim.new(0.03, 0),
		PaddingBottom = UDim.new(0.03, 0),
	}, root)
	make("TextLabel", {
		Name = "Title",
		Size = UDim2.fromScale(1, 0.11),
		BackgroundTransparency = 1,
		Font = FONT_TITLE,
		Text = BOARD_TITLES[board] or string.upper(board),
		TextColor3 = AKY_TEXT,
		TextScaled = true,
	}, root)
	-- Akzent-Unterstrich unter dem Titel
	local underline: Frame = make("Frame", {
		Name = "TitleLine",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.125),
		Size = UDim2.fromScale(0.22, 0.008),
		BackgroundColor3 = AKY_ACCENT,
		BorderSizePixel = 0,
	}, root)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, underline)
	local list: Frame = make("Frame", {
		Position = UDim2.fromScale(0, 0.16),
		Size = UDim2.fromScale(1, 0.84),
		BackgroundTransparency = 1,
	}, root)
	make("UIListLayout", { Padding = UDim.new(0.008, 0), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local rows = {}
	for i = 1, ROWS do
		local accent = RANK_COLORS[i]
		local frame: Frame = make("Frame", {
			Name = "Row" .. i,
			LayoutOrder = i,
			Size = UDim2.fromScale(1, 1 / ROWS - 0.009),
			BackgroundColor3 = if i % 2 == 0 then AKY_BG else AKY_SURFACE2,
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			Visible = false,
		}, list)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, frame)
		if accent then
			-- Platz 1–3: schmaler Rang-Streifen links + feiner Rahmen in der Rang-Farbe
			local stripe: Frame = make("Frame", {
				Name = "Stripe",
				Position = UDim2.new(0, 0, 0.18, 0),
				Size = UDim2.new(0, 4, 0.64, 0),
				BackgroundColor3 = accent,
				BorderSizePixel = 0,
			}, frame)
			make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, stripe)
			border(frame, accent, 0.55)
		end
		local rank: TextLabel = make("TextLabel", {
			Position = UDim2.fromScale(0.02, 0.1),
			Size = UDim2.fromScale(0.09, 0.8),
			BackgroundTransparency = 1,
			Font = FONT_NUMBER,
			Text = "#" .. i,
			TextScaled = true,
			TextColor3 = accent or AKY_MUTED,
		}, frame)
		local avatar: ImageLabel = make("ImageLabel", {
			Position = UDim2.fromScale(0.12, 0.1),
			Size = UDim2.fromScale(0.08, 0.8),
			BackgroundColor3 = AKY_SURFACE2,
			BackgroundTransparency = 0,
			ScaleType = Enum.ScaleType.Fit,
			Image = "",
		}, frame)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, avatar)
		local name: TextLabel = make("TextLabel", {
			Position = UDim2.fromScale(0.22, 0.12),
			Size = UDim2.fromScale(0.5, 0.76),
			BackgroundTransparency = 1,
			Font = FONT_TEXT,
			Text = "",
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = AKY_TEXT,
		}, frame)
		local value: TextLabel = make("TextLabel", {
			Position = UDim2.fromScale(0.73, 0.1),
			Size = UDim2.fromScale(0.25, 0.8),
			BackgroundTransparency = 1,
			Font = FONT_NUMBER,
			Text = "",
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = AKY_UP,
		}, frame)
		rows[i] = { Frame = frame, Rank = rank, Avatar = avatar, Name = name, Value = value }
	end
	local empty: TextLabel = make("TextLabel", {
		Position = UDim2.fromScale(0.05, 0.42),
		Size = UDim2.fromScale(0.9, 0.18),
		BackgroundTransparency = 1,
		Font = FONT_TEXT,
		Text = EMPTY_TEXT,
		TextScaled = true,
		TextColor3 = AKY_TEXT2,
	}, root)
	gui.Parent = part
	boardUis[board] = { Gui = gui, Rows = rows, Empty = empty }
end

-- ---------------------------------------------------------------------
-- 3) LESEN + ANZEIGEN (Top 10, Namens-Cache ≤ 200)
-- ---------------------------------------------------------------------
local function nameOf(userId: number): string
	local inServer = Players:GetPlayerByUserId(userId)
	if inServer then
		return inServer.DisplayName
	end
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local name = if ok and type(result) == "string" then result else ("#" .. tostring(userId))
	if ok then
		nameCache[userId] = name
		table.insert(nameOrder, userId)
		while #nameOrder > NAME_CACHE_MAX do
			local oldest = table.remove(nameOrder, 1)
			if oldest then
				nameCache[oldest] = nil
			end
		end
	end
	return name
end

local function readBoard(board: string): { Row }?
	local store = storeFor(storeName(board))
	if not store then
		return nil
	end
	local ok, result = pcall(function()
		local pages = store:GetSortedAsync(false, ROWS)
		return pages:GetCurrentPage()
	end)
	if not ok or type(result) ~= "table" then
		-- Studio ohne API-Zugriff: einmal melden, dann für diese Sitzung nicht mehr lesen
		local message = string.lower(tostring(result))
		for _, hint in ipairs(NO_API_HINTS) do
			if string.find(message, hint, 1, true) then
				readDisabled = true
				warn("[LeaderboardService] Kein DataStore-Zugriff (Studio?) – Bestenlisten bleiben leer")
				return nil
			end
		end
		logError("GetSortedAsync " .. board, result)
		return nil
	end
	local rows: { Row } = {}
	for _, entry in ipairs(result) do
		local userId = tonumber(entry.key)
		if userId and Util.IsFinite(entry.value) and #rows < ROWS then
			table.insert(rows, { UserId = userId, Value = entry.value })
		end
	end
	return rows
end

local function showBoard(board: string, rows: { Row })
	local ui = boardUis[board]
	if not ui then
		return
	end
	-- nur neu zeichnen, wenn sich etwas geändert hat
	local parts = {}
	for _, row in ipairs(rows) do
		table.insert(parts, row.UserId .. ":" .. row.Value)
	end
	local signature = table.concat(parts, ",")
	if lastRows[board] == signature then
		return
	end
	lastRows[board] = signature
	ui.Empty.Visible = #rows == 0
	for i, rowUi in ipairs(ui.Rows) do
		local row = rows[i]
		if row then
			rowUi.Name.Text = nameOf(row.UserId)
			rowUi.Value.Text = Util.FormatNumber(row.Value)
			rowUi.Avatar.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48"):format(row.UserId)
			rowUi.Frame.Visible = true
		else
			rowUi.Frame.Visible = false
		end
	end
end

local function announceTop(board: string, rows: { Row })
	local first = rows[1]
	if not first then
		return
	end
	local before = topUser[board]
	topUser[board] = first.UserId
	if before ~= nil and before ~= first.UserId then
		local holder = Players:GetPlayerByUserId(first.UserId)
		if holder then
			try("CommunityService", "Announce", "prog.announceTop." .. board, { holder.DisplayName })
		end
	end
end

local function readAll()
	if readRunning or readDisabled then
		return
	end
	readRunning = true
	task.spawn(function()
		for _, board in ipairs(P.Leaderboards) do
			local rows = if readDisabled then nil else readBoard(board)
			if rows then
				local ok, err = pcall(function()
					showBoard(board, rows)
					announceTop(board, rows)
				end)
				if not ok then
					logError("Tafel " .. board, err)
				end
			end
			task.wait(READ_STAGGER)
		end
		readRunning = false
	end)
end

local function buildBoards()
	local ok, boards = try("LobbyBuilder", "Boards")
	if not ok or type(boards) ~= "table" then
		warn("[LeaderboardService] LobbyBuilder.Boards fehlt – Tafeln werden nicht angezeigt")
		return
	end
	for _, board in ipairs(P.Leaderboards) do
		local part = boards[board]
		if typeof(part) == "Instance" and part:IsA("BasePart") then
			local built, err = pcall(buildBoard, board, part)
			if not built then
				logError("Tafel bauen " .. board, err)
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- 4) INIT / START
-- ---------------------------------------------------------------------
local function onPlayerRemoving(p: Player)
	pending[p] = nil
	lastWriteAt[p] = nil
	-- lastWritten/writing bleiben, bis ein laufender Schreib-Thread fertig ist
	task.delay(30, function()
		if p.Parent ~= Players then
			lastWritten[p] = nil
			writing[p] = nil
		end
	end)
end

function LeaderboardService.Init(services: any)
	Services = services
end

function LeaderboardService.Start()
	buildBoards()
	try("DataService", "OnProfileReleasing", onReleasing)
	try("DataService", "OnProfileLoaded", function(p: Player, _data: Types.PlayerData)
		lastWritten[p] = lastWritten[p] or {}
		lastWriteAt[p] = os.clock() - WRITE_EVERY + 10 -- erster Abgleich nach ~10 s
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	Scheduler.Every("LeaderboardWrite", 0.2, writeTick)
	Scheduler.Every("LeaderboardRead", 1 / READ_EVERY, readAll)
	task.delay(FIRST_READ_DELAY, readAll)
end

return LeaderboardService
