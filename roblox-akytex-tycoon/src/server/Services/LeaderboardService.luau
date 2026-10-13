-- =====================================================================
--  AKYTEX TYCOON – Bestenlisten, Wochen-Liga, Hall of Fame, IPO-Wand (Server/Services/LeaderboardService)
--  Besitzer: WP9 (Fortschritt, Tutorial, Sozial, Bestenlisten). Vertrag: DESIGN.md §C5.8, §C9 (BoardsGet), §B11.1
--  (6 Bestenlisten, Liga nach Skill-Score, absolute Stufen, Hall of Fame), §B9.6 (Ticker 24 h auf der IPO-Wand +
--  "Hall of IPOs"), §A7 #12 (goldene Statuen), REUSE §3.15 (CC-LeaderboardService ADAPT: Schreib-/Lese-Takt,
--  nur geänderte Werte, begrenzter Namens-Cache, Schreiben beim Verlassen, NoSave/TestPlayer nie).
--
--  Öffentliche API (§C5.8):
--    LeaderboardService.Submit(p)                       Werte vormerken (Schreiben ≥ 300 s Abstand, nur bei Änderung)
--    LeaderboardService.Top(board, n): { { UserId, Name, Value } }   Cache (Lesen alle 300 s)
--  Ergänzung: LeaderboardService.AddIpo(p, ticker)       IPO-Wand + Hall of IPOs (DataStore, alle Server)
--  Request-Handler: BoardsGet { Board, Scope = "Global" | "Friends" | "Server" } (1/s, aus Cache).
--  OrderedDataStores Config.Tech.BoardPrefix .. Store .. "_v1" bzw. .. "_" .. IsoWeek; Werte ganzzahlig 0 … 9e15
--  (Kodierung Shared/ProgressMath.Board*). Studio ohne API / NoSave / UserId ≤ 0: kein Schreiben (Lesen versucht).
-- =====================================================================

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Types = require(Shared:WaitForChild("Types"))
local Lang = require(Shared:WaitForChild("Lang"))
local Format = require(Shared:WaitForChild("Format"))
local ProgressMath = require(Shared:WaitForChild("ProgressMath"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local LeaderboardService = {}
local Services: any = nil

type Reply = Types.Reply
type Row = { UserId: number, Value: number }
type BoardDef = { Key: string, Store: string, Weekly: boolean, Kind: string, Title: string }

local PCFG: any = Config.Progression
local BCFG: any = PCFG.Boards
local TECH: any = Config.Tech
local PREFIX = if type(TECH.BoardPrefix) == "string" then TECH.BoardPrefix else "AT_LB_"
local WRITE_EVERY = math.max(60, tonumber(TECH.BoardWriteSeconds) or 300)
local READ_EVERY = WRITE_EVERY
local ROWS = math.clamp(tonumber(BCFG.Rows) or 10, 1, 10)
local CACHE_TOP = math.clamp(tonumber(BCFG.CacheTop) or 100, ROWS, 100)
local NAME_CACHE_MAX = math.max(20, tonumber(BCFG.NameCache) or 200)
local MAX_VALUE = 9e15
local FIRST_READ_DELAY = 8
local LOG_GAP = 30
local BOARD_RETRY = 10
local BOARD_RETRY_MAX = 60
local FRIENDS_TTL = 600
local FRIENDS_MAX = 200
local IPO_WALL_ROWS = 6
local IPO_HALL_ROWS = 12
local NO_API_HINTS = { "studio", "publish", "api services", "403" }

-- AKYTEX-Farben (Server hat kein UI.Theme -> Config.Colors, Spiegel von UI.Theme)
local C = Config.Colors
local GOLD = C.Gold
local RANK_COLORS = { C.Gold, C.Text2, Color3.fromRGB(205, 127, 50) }
local FACE_DISPLAY = Font.new("rbxasset://fonts/families/BuilderExtended.json", Enum.FontWeight.Bold)
local FACE_MONO = Font.new("rbxasset://fonts/families/BuilderMono.json", Enum.FontWeight.Regular)
local FACE_BODY = Font.fromEnum(Enum.Font.BuilderSansBold)

local BOARDS: { BoardDef } = BCFG.List
local boardByKey: { [string]: BoardDef } = {}
for _, def in ipairs(BOARDS) do
	boardByKey[def.Key] = def
end

-- Pro-Spieler-Tabellen (alle bei PlayerRemoving geleert, Schreib-Threads laufen zu Ende)
local lastWritten: { [Player]: { [string]: number } } = {}
local lastValues: { [Player]: { [string]: number } } = {}
local lastWriteAt: { [Player]: number } = {}
local pending: { [Player]: boolean } = {}
local writing: { [Player]: boolean } = {}
local friendsOf: { [Player]: { At: number, Ids: { [number]: string } } } = {}

local stores: { [string]: OrderedDataStore } = {}
local cache: { [string]: { Row } } = {}
local boardUis: { [string]: any } = {}
local topUser: { [string]: number } = {}
local lastRows: { [string]: string } = {}
local nameCache: { [number]: string } = {}
local nameOrder: { number } = {}
local lastLogAt: { [string]: number } = {}
local readRunning = false
local readDisabled = false
local hallWeek = -1
local hallBusy = false
local hallFolder: Folder? = nil
local ipoHall: { { T: string, N: string, U: number, At: number } } = {}
local ipoUi: any = nil
local hallUi: any = nil
local globalStore: DataStore? = nil
local globalFailed = false

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

local function finite(n: any): boolean
	return Util.IsFinite(n)
end

local function num(v: any, default: number): number
	return if Util.IsFinite(v) then v else default
end

local function call(name: string, fnName: string, ...: any): (boolean, ...any)
	local svc = Services and Services[name]
	local fn = svc and svc[fnName]
	if type(fn) ~= "function" then
		return false
	end
	local results = table.pack(pcall(fn, ...))
	if not results[1] then
		logError(name .. "." .. fnName, results[2])
		return false
	end
	return true, table.unpack(results, 2, results.n)
end

local function dataOf(p: Player): { [string]: any }?
	local ok, data = call("DataService", "Get", p)
	if ok and type(data) == "table" then
		return data
	end
	return nil
end

local function langOf(p: Player): Types.Lang
	local ok, lang = call("PlayerStateService", "LangOf", p)
	if ok and (lang == "de" or lang == "en") then
		return lang
	end
	return "en"
end

local function fail(p: Player, key: string): Reply
	return { Ok = false, Message = Lang.T(langOf(p), key) }
end

local function storeName(def: BoardDef, week: number?): string
	if def.Weekly then
		return PREFIX .. def.Store .. "_" .. tostring(week or Util.IsoWeek())
	end
	return PREFIX .. def.Store .. "_v1"
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
	local count = 0
	for _ in pairs(stores) do
		count += 1
	end
	if count > 24 then
		table.clear(stores)
	end
	stores[name] = result
	return result
end

local function noApi(err: any): boolean
	local message = string.lower(tostring(err))
	for _, hint in ipairs(NO_API_HINTS) do
		if string.find(message, hint, 1, true) then
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------------
-- 1) WERTE (§B11.1) – ganzzahlig, 0 = nicht schreiben
-- ---------------------------------------------------------------------
local function leagueStats(p: Player): any
	local ok, stats = call("OrderService", "LeagueStats", p)
	return if ok and type(stats) == "table" then stats else nil
end

local function valueOf(p: Player, data: { [string]: any }, def: BoardDef): number
	local key = def.Key
	local value = 0
	if key == "Wealth" then
		local ok, wealth = call("ProgressionService", "Wealth", p)
		value = if ok and finite(wealth) and wealth > 0 then ProgressMath.BoardLog(wealth) else 0
	elseif key == "League" or key == "Return" then
		local stats = leagueStats(p)
		-- nur qualifiziert (≥ 20 zählende Trades, ≥ 6 Tage), nie getaintet (Admin-Gaben, Besitzer)
		if stats and stats.Qualified == true and stats.Tainted ~= true then
			value = if key == "League"
				then ProgressMath.BoardLeague(stats.SkillScore, stats.AvgDailyBp)
				else ProgressMath.BoardReturn(stats.AvgDailyBp)
		end
	elseif key == "Skyline" then
		local okIpo, ipos = call("ProgressionService", "IpoCount", p)
		local okFloors, floors = call("TowerService", "Floors", p)
		local ipoCount = if okIpo and finite(ipos) then ipos else 0
		local floorCount = if okFloors and finite(floors) then floors else 0
		value = if ipoCount + floorCount > 0 then ProgressMath.BoardSkyline(ipoCount, floorCount) else 0
	elseif key == "Firm" then
		local prog = data.Prog
		local prestige = if type(prog) == "table" then prog.Prestige else nil
		local firm = if type(prestige) == "table" then num(prestige.Firmenwert, 0) else 0
		value = if firm > 0 then ProgressMath.BoardLog(firm) else 0
	elseif key == "Respekt" then
		local social = data.Social
		if type(social) == "table" and social.RespektWeek == Util.IsoWeek() then
			value = math.max(0, math.floor(num(social.RespektGot, 0)))
		end
	end
	return math.floor(math.clamp(value, 0, MAX_VALUE))
end

local function canWrite(p: Player): boolean
	if p.UserId <= 0 then
		return false
	end
	local ok, noSave = call("DataService", "IsNoSave", p)
	return not (ok and noSave == true)
end

-- ---------------------------------------------------------------------
-- 2) SCHREIBEN (nur geänderte Werte)
-- ---------------------------------------------------------------------
local function collect(p: Player, data: { [string]: any }): { { Store: string, Value: number } }
	local changes = {}
	local written = lastWritten[p] or {}
	local values = lastValues[p] or {}
	lastValues[p] = values
	for _, def in ipairs(BOARDS) do
		local name = storeName(def)
		local value = valueOf(p, data, def)
		if value > 0 then
			values[name] = value
		end
		local final = values[name] or 0
		if final > 0 and written[name] ~= final then
			table.insert(changes, { Store = name, Value = final })
		end
	end
	return changes
end

-- yieldet (SetAsync); immer im eigenen Thread
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
	local data = dataOf(p)
	if not data then
		return
	end
	lastWritten[p] = lastWritten[p] or {}
	local changes = collect(p, data)
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
		if pending[p] or os.clock() - (lastWriteAt[p] or 0) >= WRITE_EVERY then
			writePlayer(p, false)
		end
	end
end

-- Beim Verlassen: letzter Stand (eigener Thread; Werte aus dem Cache, falls andere Dienste schon aufgeräumt haben)
local function onReleasing(p: Player, data: { [string]: any })
	if not canWrite(p) or type(data) ~= "table" then
		return
	end
	lastWritten[p] = lastWritten[p] or {}
	local changes = collect(p, data)
	if #changes > 0 then
		task.spawn(writeChanges, p, p.UserId, changes)
	end
end

-- ---------------------------------------------------------------------
-- 3) NAMEN (Cache ≤ 200)
-- ---------------------------------------------------------------------
local function cachedName(userId: number): string?
	local inServer = Players:GetPlayerByUserId(userId)
	if inServer then
		return inServer.DisplayName
	end
	return nameCache[userId]
end

local function rememberName(userId: number, name: string)
	if nameCache[userId] == nil then
		table.insert(nameOrder, userId)
	end
	nameCache[userId] = name
	while #nameOrder > NAME_CACHE_MAX do
		local oldest = table.remove(nameOrder, 1)
		if oldest then
			nameCache[oldest] = nil
		end
	end
end

-- yieldet
local function fetchName(userId: number): string
	local known = cachedName(userId)
	if known then
		return known
	end
	if userId <= 0 then
		return "Player" .. tostring(-userId)
	end
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(result) == "string" then
		rememberName(userId, result)
		return result
	end
	return "#" .. tostring(userId)
end

-- ---------------------------------------------------------------------
-- 4) ANZEIGE-FORMAT (eine Sprache auf Welt-Tafeln: neutrale Kurzform)
-- ---------------------------------------------------------------------
local function display(def: BoardDef, value: number, lang: Types.Lang): string
	if def.Kind == "Log" then
		local ok, text = pcall(Format.Compact, ProgressMath.BoardLogDecode(value), lang)
		return "≈ " .. (if ok then text else tostring(math.floor(ProgressMath.BoardLogDecode(value))))
	elseif def.Kind == "League" then
		return Lang.T(lang, "soc.board.skill", math.floor(value / 10000))
	elseif def.Kind == "Return" then
		local bp = value - 1000000
		local ok, text = pcall(Format.Pct, bp / 10000, lang, 2, true)
		return if ok then text else string.format("%+.2f %%", bp / 100)
	end
	local ok, text = pcall(Format.Int, value, lang)
	return if ok then text else tostring(value)
end

-- ---------------------------------------------------------------------
-- 5) WELT-TAFELN (SurfaceGui im AKYTEX-Look auf CityService.BoardPart)
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

local function border(parent: Instance, color: Color3, transparency: number?)
	make("UIStroke", {
		Thickness = 1.5,
		Color = color,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function panel(part: BasePart, name: string): (SurfaceGui, Frame)
	local old = part:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local gui: SurfaceGui = make("SurfaceGui", {
		Name = name,
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 30,
		LightInfluence = 0,
		Brightness = 1.6,
		MaxDistance = 300,
		ResetOnSpawn = false,
		Adornee = part,
	})
	local root: Frame = make("Frame", {
		Name = "Panel",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Bg,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 16) }, root)
	border(root, C.Border)
	make("UIPadding", {
		PaddingLeft = UDim.new(0.04, 0),
		PaddingRight = UDim.new(0.04, 0),
		PaddingTop = UDim.new(0.03, 0),
		PaddingBottom = UDim.new(0.03, 0),
	}, root)
	return gui, root
end

local function title(root: Frame, text: string, heightScale: number, color: Color3?)
	make("TextLabel", {
		Name = "Title",
		Size = UDim2.fromScale(1, heightScale),
		BackgroundTransparency = 1,
		FontFace = FACE_DISPLAY,
		Text = text,
		TextColor3 = C.Text,
		TextScaled = true,
	}, root)
	local underline: Frame = make("Frame", {
		Name = "TitleLine",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, heightScale + 0.012),
		Size = UDim2.fromScale(0.22, 0.008),
		BackgroundColor3 = color or C.Accent,
		BorderSizePixel = 0,
	}, root)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, underline)
end

local function buildBoard(def: BoardDef, part: BasePart)
	local gui, root = panel(part, "AT_Board")
	title(root, def.Title, 0.1)
	local list: Frame = make("Frame", {
		Position = UDim2.fromScale(0, 0.15),
		Size = UDim2.fromScale(1, 0.85),
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
			BackgroundColor3 = if i % 2 == 0 then C.Bg else C.Surface2,
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			Visible = false,
		}, list)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, frame)
		if accent then
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
			FontFace = FACE_MONO,
			Text = "#" .. i,
			TextScaled = true,
			TextColor3 = accent or C.Muted,
		}, frame)
		local avatar: ImageLabel = make("ImageLabel", {
			Position = UDim2.fromScale(0.12, 0.1),
			Size = UDim2.fromScale(0.08, 0.8),
			BackgroundColor3 = C.Surface2,
			ScaleType = Enum.ScaleType.Fit,
			Image = "",
		}, frame)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, avatar)
		make("UIAspectRatioConstraint", { AspectRatio = 1 }, avatar)
		local name: TextLabel = make("TextLabel", {
			Position = UDim2.fromScale(0.22, 0.12),
			Size = UDim2.fromScale(0.46, 0.76),
			BackgroundTransparency = 1,
			FontFace = FACE_BODY,
			Text = "",
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = C.Text,
		}, frame)
		local value: TextLabel = make("TextLabel", {
			Position = UDim2.fromScale(0.69, 0.1),
			Size = UDim2.fromScale(0.29, 0.8),
			BackgroundTransparency = 1,
			FontFace = FACE_MONO,
			Text = "",
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = C.Up,
		}, frame)
		rows[i] = { Frame = frame, Rank = rank, Avatar = avatar, Name = name, Value = value }
	end
	local empty: TextLabel = make("TextLabel", {
		Position = UDim2.fromScale(0.05, 0.42),
		Size = UDim2.fromScale(0.9, 0.18),
		BackgroundTransparency = 1,
		FontFace = FACE_BODY,
		Text = Lang.T("de", "soc.board.empty") .. "\n" .. Lang.T("en", "soc.board.empty"),
		TextScaled = true,
		TextColor3 = C.Text2,
	}, root)
	gui.Parent = part
	boardUis[def.Key] = { Gui = gui, Rows = rows, Empty = empty }
end

local function showBoard(def: BoardDef, rows: { Row })
	local ui = boardUis[def.Key]
	if not ui then
		return
	end
	local parts = {}
	for i = 1, math.min(#rows, ROWS) do
		table.insert(parts, rows[i].UserId .. ":" .. rows[i].Value)
	end
	local signature = table.concat(parts, ",")
	if lastRows[def.Key] == signature then
		return
	end
	lastRows[def.Key] = signature
	ui.Empty.Visible = #rows == 0
	for i, rowUi in ipairs(ui.Rows) do
		local row = rows[i]
		if row then
			rowUi.Name.Text = cachedName(row.UserId) or ("#" .. tostring(row.UserId))
			rowUi.Value.Text = display(def, row.Value, "en")
			rowUi.Avatar.Image = if row.UserId > 0
				then ("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48"):format(row.UserId)
				else ""
			rowUi.Frame.Visible = true
		else
			rowUi.Frame.Visible = false
		end
	end
end

local function boardName(def: BoardDef): { de: string, en: string }
	return { de = Lang.T("de", "soc.board." .. def.Key), en = Lang.T("en", "soc.board." .. def.Key) }
end

-- neue #1 (Spieler in diesem Server) -> Ansage
local function announceTop(def: BoardDef, rows: { Row })
	local first = rows[1]
	if not first then
		return
	end
	local before = topUser[def.Key]
	topUser[def.Key] = first.UserId
	if before ~= nil and before ~= first.UserId then
		local holder = Players:GetPlayerByUserId(first.UserId)
		if holder then
			call("CommunityService", "Announce", "soc.newTop", { holder.DisplayName, boardName(def) })
		end
	end
end

-- ---------------------------------------------------------------------
-- 6) LESEN (Top 100 je Tafel alle 300 s, 0,5 s versetzt)
-- ---------------------------------------------------------------------
local function readStore(name: string, n: number): { Row }?
	local store = storeFor(name)
	if not store then
		return nil
	end
	local ok, result = pcall(function()
		local pages = store:GetSortedAsync(false, n)
		return pages:GetCurrentPage()
	end)
	if not ok or type(result) ~= "table" then
		if noApi(result) then
			readDisabled = true
			warn("[LeaderboardService] Kein DataStore-Zugriff (Studio?) – Bestenlisten bleiben leer")
			return nil
		end
		logError("GetSortedAsync " .. name, result)
		return nil
	end
	local rows: { Row } = {}
	for _, entry in ipairs(result) do
		local userId = tonumber(entry.key)
		if userId and finite(entry.value) and #rows < n then
			table.insert(rows, { UserId = userId, Value = entry.value })
		end
	end
	return rows
end

local refreshHall: () -> ()
local refreshIpoHall: () -> ()

local function readAll()
	if readRunning then
		return
	end
	readRunning = true
	task.spawn(function()
		if not readDisabled then
			for _, def in ipairs(BOARDS) do
				local rows = if readDisabled then nil else readStore(storeName(def), CACHE_TOP)
				if rows then
					cache[def.Key] = rows
					for i = 1, math.min(#rows, ROWS) do
						fetchName(rows[i].UserId)
					end
					local ok, err = pcall(function()
						showBoard(def, rows)
						announceTop(def, rows)
					end)
					if not ok then
						logError("Tafel " .. def.Key, err)
					end
				end
				task.wait(BCFG.ReadStagger or 0.5)
			end
		end
		local okHall, errHall = pcall(refreshHall)
		if not okHall then
			logError("Hall of Fame", errHall)
		end
		local okIpo, errIpo = pcall(refreshIpoHall)
		if not okIpo then
			logError("IPO-Wand", errIpo)
		end
		readRunning = false
	end)
end

function LeaderboardService.Top(board: string, n: number): { { UserId: number, Name: string, Value: number } }
	local rows = cache[board]
	local out = {}
	if type(rows) ~= "table" then
		return out
	end
	local count = math.clamp(math.floor(num(n, ROWS)), 0, #rows)
	for i = 1, count do
		local row = rows[i]
		table.insert(out, {
			UserId = row.UserId,
			Name = cachedName(row.UserId) or ("#" .. tostring(row.UserId)),
			Value = row.Value,
		})
	end
	return out
end

-- ---------------------------------------------------------------------
-- 7) HALL OF FAME (Liga-Top-3 der Vorwoche als goldene Statuen, §B11.1/§A7 #12)
-- ---------------------------------------------------------------------
local function goldify(model: Model)
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.Material = Enum.Material.Metal
			inst.Color = GOLD
			inst.Anchored = true
			inst.CanCollide = false
			inst.CanQuery = false
			inst.CanTouch = false
			inst.CastShadow = true
			if inst:IsA("MeshPart") then
				pcall(function()
					(inst :: MeshPart).TextureID = ""
				end)
			end
		elseif inst:IsA("SpecialMesh") then
			inst.TextureId = ""
		elseif
			inst:IsA("Clothing")
			or inst:IsA("ShirtGraphic")
			or inst:IsA("SurfaceAppearance")
			or inst:IsA("BaseScript")
			or inst:IsA("Sound")
		then
			inst:Destroy()
		elseif inst:IsA("Humanoid") then
			inst.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			inst.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end
	end
end

-- Part-Puppe (Studio/negative UserId/Fehler): schlichte Figur aus Blöcken
local function puppet(): Model
	local model = Instance.new("Model")
	model.Name = "Statue"
	local function block(name: string, size: Vector3, offset: Vector3, shape: Enum.PartType?)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = CFrame.new(offset)
		if shape then
			part.Shape = shape
		end
		part.Parent = model
		return part
	end
	local torso = block("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0))
	block("Head", Vector3.new(1.3, 1.3, 1.3), Vector3.new(0, 4.7, 0), Enum.PartType.Ball)
	block("LeftArm", Vector3.new(0.9, 2, 0.9), Vector3.new(-1.5, 3, 0))
	block("RightArm", Vector3.new(0.9, 2, 0.9), Vector3.new(1.5, 3.4, 0))
	block("LeftLeg", Vector3.new(0.95, 2, 0.95), Vector3.new(-0.5, 1, 0))
	block("RightLeg", Vector3.new(0.95, 2, 0.95), Vector3.new(0.5, 1, 0))
	model.PrimaryPart = torso
	return model
end

-- yieldet (CreateHumanoidModelFromUserIdAsync)
local function statueFor(userId: number): Model
	if userId > 0 then
		local ok, result = pcall(function()
			local players: any = Players
			local method = players.CreateHumanoidModelFromUserIdAsync
			if type(method) == "function" then
				return method(players, userId)
			end
			return players:CreateHumanoidModelFromUserId(userId)
		end)
		if ok and typeof(result) == "Instance" and result:IsA("Model") then
			return result
		end
		logError("CreateHumanoidModelFromUserIdAsync", result)
	end
	return puppet()
end

local function placeOn(model: Model, top: BasePart)
	pcall(function()
		model:ScaleTo(1.15)
	end)
	local bbox, size = model:GetBoundingBox()
	local pivot = model:GetPivot()
	local offsetY = pivot.Position.Y - (bbox.Position.Y - size.Y / 2)
	local surface = top.Position + Vector3.new(0, top.Size.Y / 2, 0)
	local look = top.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	local at = surface + Vector3.new(0, offsetY, 0)
	model:PivotTo(CFrame.lookAt(at, at + flat.Unit))
end

local function buildHallPlaque(part: BasePart)
	local gui, root = panel(part, "AT_HallOfFame")
	title(root, "HALL OF FAME", 0.2, GOLD)
	local list: Frame = make("Frame", {
		Position = UDim2.fromScale(0, 0.3),
		Size = UDim2.fromScale(1, 0.7),
		BackgroundTransparency = 1,
	}, root)
	make("UIListLayout", { Padding = UDim.new(0.02, 0), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local lines = {}
	for i = 1, 3 do
		lines[i] = make("TextLabel", {
			LayoutOrder = i,
			Size = UDim2.fromScale(1, 0.3),
			BackgroundTransparency = 1,
			FontFace = FACE_BODY,
			Text = "",
			TextScaled = true,
			TextColor3 = RANK_COLORS[i],
		}, list)
	end
	gui.Parent = part
	hallUi = { Lines = lines }
end

refreshHall = function()
	local week = Util.IsoWeek(os.time() - 7 * 86400)
	if week == hallWeek or hallBusy then
		return
	end
	local def = boardByKey[BCFG.HallOfFame.Board or "League"]
	if not def then
		return
	end
	hallBusy = true
	local rows = if readDisabled then {} else (readStore(storeName(def, week), BCFG.HallOfFame.Count) or {})
	hallWeek = week
	local okPlaque, plaque = call("CityService", "BoardPart", "HallOfFame")
	if okPlaque and typeof(plaque) == "Instance" and plaque:IsA("BasePart") and not hallUi then
		buildHallPlaque(plaque)
	end
	local folder = hallFolder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "AT_HallOfFame"
		folder.Parent = workspace
		hallFolder = folder
	end
	for _, child in ipairs((folder :: Folder):GetChildren()) do
		child:Destroy()
	end
	for i = 1, BCFG.HallOfFame.Count do
		local okTop, top = call("CityService", "BoardPart", "Hall" .. i)
		local row = rows[i]
		local line = hallUi and hallUi.Lines[i]
		if row then
			local name = fetchName(row.UserId)
			if line then
				line.Text = ("%d. %s · %s"):format(i, name, display(def, row.Value, "en"))
			end
			if okTop and typeof(top) == "Instance" and top:IsA("BasePart") then
				local model = statueFor(row.UserId)
				goldify(model)
				model.Name = "Statue" .. i
				pcall(function()
					model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
				end)
				placeOn(model, top)
				model.Parent = folder
			end
		elseif line then
			line.Text = ("%d. —"):format(i)
		end
	end
	hallBusy = false
end

-- ---------------------------------------------------------------------
-- 8) IPO-WAND + HALL OF IPOs (DataStore Config.Tech.GlobalStore, alle Server)
-- ---------------------------------------------------------------------
local function gStore(): DataStore?
	if globalStore or globalFailed then
		return globalStore
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(TECH.GlobalStore or "AT_Global")
	end)
	if ok then
		globalStore = result
	else
		globalFailed = true
		logError("GetDataStore", result)
	end
	return globalStore
end

local function buildIpoWall(part: BasePart)
	local gui, root = panel(part, "AT_IpoWall")
	root.BackgroundColor3 = C.Bg2
	title(root, "IPO-WAND · IPO WALL", 0.14, C.Cosmic2)
	local fresh: Frame = make("Frame", {
		Name = "Fresh",
		Position = UDim2.fromScale(0, 0.2),
		Size = UDim2.fromScale(0.58, 0.8),
		BackgroundTransparency = 1,
	}, root)
	make("UIGridLayout", {
		CellSize = UDim2.fromScale(0.48, 0.3),
		CellPadding = UDim2.fromScale(0.03, 0.03),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, fresh)
	local tiles = {}
	for i = 1, IPO_WALL_ROWS do
		local tile: Frame = make("Frame", {
			LayoutOrder = i,
			BackgroundColor3 = C.Surface2,
			BackgroundTransparency = 0.1,
			Visible = false,
		}, fresh)
		make("UICorner", { CornerRadius = UDim.new(0, 12) }, tile)
		border(tile, C.Cosmic2, 0.3)
		local ticker: TextLabel = make("TextLabel", {
			Size = UDim2.fromScale(1, 0.62),
			BackgroundTransparency = 1,
			FontFace = FACE_DISPLAY,
			Text = "",
			TextScaled = true,
			TextColor3 = GOLD,
		}, tile)
		local owner: TextLabel = make("TextLabel", {
			Position = UDim2.fromScale(0, 0.62),
			Size = UDim2.fromScale(1, 0.34),
			BackgroundTransparency = 1,
			FontFace = FACE_BODY,
			Text = "",
			TextScaled = true,
			TextColor3 = C.Text2,
		}, tile)
		tiles[i] = { Frame = tile, Ticker = ticker, Owner = owner }
	end
	local hall: Frame = make("Frame", {
		Name = "Hall",
		Position = UDim2.fromScale(0.62, 0.2),
		Size = UDim2.fromScale(0.38, 0.8),
		BackgroundTransparency = 1,
	}, root)
	make("TextLabel", {
		Size = UDim2.fromScale(1, 0.1),
		BackgroundTransparency = 1,
		FontFace = FACE_DISPLAY,
		Text = "HALL OF IPOs",
		TextScaled = true,
		TextColor3 = C.Text,
	}, hall)
	local list: Frame = make("Frame", {
		Position = UDim2.fromScale(0, 0.12),
		Size = UDim2.fromScale(1, 0.88),
		BackgroundTransparency = 1,
	}, hall)
	make("UIListLayout", { Padding = UDim.new(0.005, 0), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local lines = {}
	for i = 1, IPO_HALL_ROWS do
		lines[i] = make("TextLabel", {
			LayoutOrder = i,
			Size = UDim2.fromScale(1, 1 / IPO_HALL_ROWS - 0.006),
			BackgroundTransparency = 1,
			FontFace = FACE_MONO,
			Text = "",
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = C.Text2,
		}, list)
	end
	gui.Parent = part
	ipoUi = { Tiles = tiles, Lines = lines }
end

local function showIpoHall()
	if not ipoUi then
		return
	end
	local now = os.time()
	local wallSeconds = (PCFG.Prestige.WallHours or 24) * 3600
	local slot = 0
	for _, entry in ipairs(ipoHall) do
		if now - entry.At <= wallSeconds and slot < IPO_WALL_ROWS then
			slot += 1
			local tile = ipoUi.Tiles[slot]
			tile.Ticker.Text = entry.T
			tile.Owner.Text = entry.N
			tile.Frame.Visible = true
		end
	end
	for i = slot + 1, IPO_WALL_ROWS do
		ipoUi.Tiles[i].Frame.Visible = false
	end
	for i, line in ipairs(ipoUi.Lines) do
		local entry = ipoHall[i]
		line.Text = if entry then ("%s  %s"):format(entry.T, entry.N) else ""
	end
end

local function cleanHall(list: any): { { T: string, N: string, U: number, At: number } }
	local out = {}
	if type(list) ~= "table" then
		return out
	end
	for _, entry in ipairs(list) do
		if
			type(entry) == "table"
			and type(entry.T) == "string"
			and string.match(entry.T, "^%u%u%u%u?$")
			and type(entry.N) == "string"
			and finite(entry.At)
			and #out < PCFG.Prestige.HallKeep
		then
			table.insert(
				out,
				{ T = entry.T, N = string.sub(entry.N, 1, 30), U = math.floor(num(entry.U, 0)), At = entry.At }
			)
		end
	end
	return out
end

refreshIpoHall = function()
	local ds = gStore()
	if ds and not readDisabled then
		local ok, result = pcall(function()
			return ds:GetAsync(BCFG.IpoStoreKey)
		end)
		if ok then
			local remote = cleanHall(result)
			-- lokale (noch nicht gelesene) Einträge behalten
			local seen: { [string]: boolean } = {}
			for _, entry in ipairs(remote) do
				seen[entry.T .. ":" .. entry.At] = true
			end
			for _, entry in ipairs(ipoHall) do
				if not seen[entry.T .. ":" .. entry.At] then
					table.insert(remote, entry)
				end
			end
			table.sort(remote, function(a, b)
				return a.At > b.At
			end)
			while #remote > PCFG.Prestige.HallKeep do
				table.remove(remote)
			end
			ipoHall = remote
		elseif noApi(result) then
			readDisabled = true
		else
			logError("GetAsync IpoHall", result)
		end
	end
	showIpoHall()
end

function LeaderboardService.AddIpo(p: Player, ticker: string)
	if typeof(p) ~= "Instance" or not p:IsA("Player") or type(ticker) ~= "string" then
		return
	end
	if not string.match(ticker, "^%u%u%u%u?$") then
		return
	end
	local entry = { T = ticker, N = string.sub(p.DisplayName, 1, 30), U = p.UserId, At = os.time() }
	table.insert(ipoHall, 1, entry)
	while #ipoHall > PCFG.Prestige.HallKeep do
		table.remove(ipoHall)
	end
	showIpoHall()
	if p.UserId <= 0 then
		return -- Studio-Testspieler: nur lokal
	end
	local ds = gStore()
	if not ds then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			ds:UpdateAsync(BCFG.IpoStoreKey, function(old: any)
				local list = cleanHall(old)
				table.insert(list, 1, entry)
				while #list > PCFG.Prestige.HallKeep do
					table.remove(list)
				end
				return list
			end)
		end)
		if not ok then
			logError("UpdateAsync IpoHall", err)
		end
	end)
end

-- ---------------------------------------------------------------------
-- 9) BoardsGet (§C9: aus Cache; "Freunde" = Freunde im Top-100-Cache + Freunde im Server)
-- ---------------------------------------------------------------------
-- yieldet (GetFriendsAsync), 10 min je Spieler gecacht, höchstens 200 Freunde
local function friendIds(p: Player): { [number]: string }
	local cached = friendsOf[p]
	if cached and os.clock() - cached.At < FRIENDS_TTL then
		return cached.Ids
	end
	local ids: { [number]: string } = {}
	if p.UserId > 0 then
		local ok, err = pcall(function()
			local pages = Players:GetFriendsAsync(p.UserId)
			local count = 0
			local guard = 0
			while guard < 8 do
				guard += 1
				for _, friend in ipairs(pages:GetCurrentPage()) do
					if count < FRIENDS_MAX and type(friend.Id) == "number" then
						ids[friend.Id] = friend.DisplayName or friend.Username or ("#" .. friend.Id)
						count += 1
					end
				end
				if pages.IsFinished or count >= FRIENDS_MAX then
					break
				end
				pages:AdvanceToNextPageAsync()
			end
		end)
		if not ok then
			logError("GetFriendsAsync", err)
		end
	end
	if p.Parent == Players then
		friendsOf[p] = { At = os.clock(), Ids = ids }
	end
	return ids
end

local function liveRow(other: Player, def: BoardDef): Row?
	local data = dataOf(other)
	if not data then
		return nil
	end
	local value = valueOf(other, data, def)
	if value <= 0 then
		return nil
	end
	return { UserId = other.UserId, Value = value }
end

local function handleBoards(p: Player, arg: any): Reply
	if type(arg) ~= "table" or type(arg.Board) ~= "string" or type(arg.Scope) ~= "string" then
		return fail(p, "core.invalid")
	end
	for key in pairs(arg) do
		if key ~= "Board" and key ~= "Scope" then
			return fail(p, "core.invalid")
		end
	end
	local def = boardByKey[arg.Board]
	if not def or (arg.Scope ~= "Global" and arg.Scope ~= "Friends" and arg.Scope ~= "Server") then
		return fail(p, "core.invalid")
	end
	local rows: { Row } = {}
	local names: { [number]: string } = {}
	if arg.Scope == "Global" then
		for i, row in ipairs(cache[def.Key] or {}) do
			if i > ROWS then
				break
			end
			table.insert(rows, row)
		end
	elseif arg.Scope == "Server" then
		for _, other in ipairs(Players:GetPlayers()) do
			local row = liveRow(other, def)
			if row then
				table.insert(rows, row)
			end
		end
	else
		local friends = friendIds(p)
		local seen: { [number]: boolean } = {}
		for _, row in ipairs(cache[def.Key] or {}) do
			if friends[row.UserId] or row.UserId == p.UserId then
				table.insert(rows, row)
				seen[row.UserId] = true
				names[row.UserId] = friends[row.UserId]
			end
		end
		for _, other in ipairs(Players:GetPlayers()) do
			if (friends[other.UserId] or other == p) and not seen[other.UserId] then
				local row = liveRow(other, def)
				if row then
					table.insert(rows, row)
				end
			end
		end
	end
	table.sort(rows, function(a, b)
		return a.Value > b.Value
	end)
	local lang = langOf(p)
	local out = {}
	local myRank: number? = nil
	for i, row in ipairs(rows) do
		if row.UserId == p.UserId then
			myRank = i
		end
		if i <= ROWS then
			table.insert(out, {
				Rank = i,
				UserId = row.UserId,
				Name = names[row.UserId] or cachedName(row.UserId) or ("#" .. tostring(row.UserId)),
				Value = row.Value,
				Text = display(def, row.Value, lang),
			})
		end
	end
	local data = dataOf(p)
	local mine = if data then valueOf(p, data, def) else 0
	if not myRank and arg.Scope == "Global" then
		for i, row in ipairs(cache[def.Key] or {}) do
			if row.UserId == p.UserId then
				myRank = i
				break
			end
		end
	end
	return {
		Ok = true,
		Board = def.Key,
		Scope = arg.Scope,
		Kind = def.Kind,
		Rows = out,
		Me = { Rank = myRank or false, Value = mine, Text = if mine > 0 then display(def, mine, lang) else "—" },
	}
end

-- ---------------------------------------------------------------------
-- 10) INIT / START
-- ---------------------------------------------------------------------
local function buildWorld(): boolean
	local missing = false
	for _, def in ipairs(BOARDS) do
		if not boardUis[def.Key] then
			local ok, part = call("CityService", "BoardPart", def.Key)
			if ok and typeof(part) == "Instance" and part:IsA("BasePart") then
				local built, err = pcall(buildBoard, def, part)
				if not built then
					logError("Tafel bauen " .. def.Key, err)
				else
					lastRows[def.Key] = nil
					if cache[def.Key] then
						showBoard(def, cache[def.Key])
					end
				end
			else
				missing = true
			end
		end
	end
	if not ipoUi then
		local ok, part = call("CityService", "BoardPart", "IpoWall")
		if ok and typeof(part) == "Instance" and part:IsA("BasePart") then
			local built, err = pcall(buildIpoWall, part)
			if built then
				showIpoHall()
			else
				logError("IPO-Wand bauen", err)
			end
		else
			missing = true
		end
	end
	return not missing
end

local function onPlayerRemoving(p: Player)
	pending[p] = nil
	lastWriteAt[p] = nil
	friendsOf[p] = nil
	-- lastWritten/lastValues/writing bleiben, bis ein laufender Schreib-Thread fertig ist
	task.delay(30, function()
		if p.Parent ~= Players then
			lastWritten[p] = nil
			lastValues[p] = nil
			writing[p] = nil
		end
	end)
end

function LeaderboardService.Init(services: any)
	Services = services
	local pss = services.PlayerStateService
	if pss then
		pss.Handle("BoardsGet", handleBoards, { Rate = 1, Per = 1 })
	else
		warn("[LeaderboardService] PlayerStateService fehlt – BoardsGet nicht registriert")
	end
end

function LeaderboardService.Start()
	call("DataService", "OnProfileReleasing", onReleasing)
	call("DataService", "OnProfileLoaded", function(p: Player, _data: any)
		lastWritten[p] = lastWritten[p] or {}
		lastWriteAt[p] = os.clock() - WRITE_EVERY + 15 -- erster Abgleich nach ~15 s
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	Scheduler.Every("LeaderboardWrite", 0.2, writeTick)
	Scheduler.Every("LeaderboardRead", 1 / READ_EVERY, readAll)
	-- Tafeln bauen, sobald die Stadt die Board-Flächen hat (Priority-Teile; begrenzte Wiederholungen über den Scheduler)
	local attempts = 0
	local stopBuild: (() -> ())? = nil
	stopBuild = Scheduler.Every("LeaderboardBuild", 1 / BOARD_RETRY, function()
		attempts += 1
		local ok, done = pcall(buildWorld)
		if not ok then
			logError("Tafeln bauen", done)
		end
		if (ok and done) or attempts >= BOARD_RETRY_MAX then
			local stop = stopBuild
			stopBuild = nil
			if stop then
				stop()
			end
		end
	end)
	task.delay(FIRST_READ_DELAY, readAll)
end

return LeaderboardService
