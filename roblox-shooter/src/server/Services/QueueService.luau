-- =====================================================================
--  CLUTCH CLASH – Warteschlangen, Pads, Herausforderer-Linie (Server/Services/QueueService)
--  Besitzer: WP5 (Match & Warteschlangen). Vertrag: DESIGN.md C5.5, B3 (ein Pool pro Modus), B4 (Krone, FFA-Drop-in), B10.1.
--
--  Prinzip (B3.1): Pro Modus GENAU eine virtuelle Schlange. Pads und PLAY-Menü sind nur Eingänge.
--    Eintrag = 1..TeamSize Spieler, die ins selbe Team müssen (Pad-Hälfte). Gegenüberliegende Hälften desselben
--    Pads sind als Gegner fest gekoppelt (Freunde-Duell).
--  Matcher 2 Hz pro Modus: (1) volle Pads sofort · (2) Menschen kombinieren (älteste zuerst; Eingabegruppe in den
--    ersten 6 s; MMR ±200, +50 alle 3 s; Neulings-Schutz <5 / <15 Matches) · (3) nach BotFillSeconds (8 s, Studio 2 s,
--    3 s mit Rookie) oder "Bots jetzt" (frühestens 3 s): Rest mit Bots · (4) kein Slot/kein Bot-Budget -> halten (Timer pausiert).
--  Pad-Scan 4 Hz über HRP-Positionen (kein Touched); Pad-Zustand nur als Attribute (nur bei Änderung).
--  Krone (B4): Herausforderer-Linie (6 Kreise oder PLAY), König bleibt, Bot nach 15 s Leerlauf, Solo-Herausforderer
--    nach 8 s gegen Normal-Bot, Serie, Krone am Kopf, Königs-Tafel (rbxthumb), Lobby-Ansage bei Serie 3/5/10.
--
--  Öffentliche API (C5.5):
--    QueueService.Join(p, modeKey, source?: { Pad: number?, Side: ("A" | "B")? }): (boolean, string?)
--    QueueService.Leave(p)
--    QueueService.StateOf(p): { Mode, Since, BotAt, Searching }?
--    QueueService.Searching(modeKey): number
--    QueueService.FillNow(p): boolean
--    QueueService.CrownJoin(p): (boolean, string?)
--    QueueService.CrownLeave(p)
--    QueueService.CrownKing(): Player?
--    QueueService.ForceFillPads()                       -- Admin
--  Zusätzlich (intern, WP5): QueueService.LockPads(userId, seconds) · QueueService.CrownMatchEnded(...)
--  Request-Aktionen (C9): QueueJoin, QueueLeave, FillBots, CrownJoin, CrownLeave (+ GoRange: PLAY → Training-Teleport).
--  State-Schlüssel: "Queue" { Mode?, Since?, BotAt?, Searching?, Held?, CanFill?, Counts, Crown, LockedUntil? }.
-- =====================================================================

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Lang = require(Shared:WaitForChild("Lang"))
local Types = require(Shared:WaitForChild("Types"))
local Scheduler = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Scheduler"))

local QueueService = {}
local Services: any = nil

type Reply = Types.Reply

local MODES: any = Config.Modes
local Q: any = MODES.Queue or {}
local MCFG: any = MODES.Match or {}
local ERROR_LOG_EVERY = 10
local PAD_REACH = 16 -- grober Vorfilter: HRP so nah an der Pad-Mitte, bevor Sitze geprüft werden
local CROWN_PIT_REACH = 45 -- König weiter weg von der Grube (ohne Match) = Krone abgegeben
local MAX_CREATES_PER_TICK = 4
local NOTIFY_GAP = 8
local PRACTICE_PROMPT_TAG = "CCPracticePrompt"
local BOOTH_ATTEMPTS = 40

-- ---------------------------------------------------------------------
-- 1) ZUSTAND
-- ---------------------------------------------------------------------
type QEntry = {
	Id: number,
	Mode: string,
	Players: { Player },
	Since: number,
	Pad: number?,
	Side: string?,
	FillNow: boolean,
	HeldSince: number?,
	HeldTotal: number,
	HoldReason: string?,
	PrevHold: string?, -- Grund aus dem letzten Matcher-Takt (Meldung nur bei Wechsel)
}

type PlayerInfo = { Mmr: number, Matches: number, Rookie: boolean, Input: string }

type Pad = { Id: number, Mode: string, Part: BasePart, Center: Vector3, SeatsA: { Vector3 }, SeatsB: { Vector3 } }

type LineEntry = { Player: Player, Since: number, ViaCircle: boolean }

local queues: { [string]: { QEntry } } = {}
local entryOf: { [Player]: QEntry } = {}
local padEntries: { [string]: QEntry } = {}
local infoOf: { [Player]: PlayerInfo } = {}
local lastInput: { [Player]: string } = {}
local voteWatch: { [Player]: { Pad: number, Side: string, OffSince: number? } } = {}
local offSince: { [Player]: number } = {}
local lockedUntil: { [number]: number } = {} -- UserId -> Server-Zeit (Pad-Sperre nach Verlassen)
local notifyAt: { [Player]: { [string]: number } } = {}
local stateSig: { [Player]: string } = {}
local rangeAt: { [Player]: number } = {}
local promptAt: { [Player]: number } = {}
local rejoinGrace: { [Player]: number } = {}
local nextEntryId = 0

local pads: { Pad } = {}
local padAttrCache: { [number]: { [string]: any } } = {}
local crownCircles: { Vector3 } = {}
local crownLine: { LineEntry } = {}
local crownKing: Player? = nil
local crownStreak = 0
local crownIdleSince = 0
local crownMatchId: number? = nil
local crownBoardGui: SurfaceGui? = nil
local boothsBuilt = false
local boothAttempts = 0
local lastErrorAt: { [string]: number } = {}
local lastCounts = ""

local function now(): number
	return workspace:GetServerTimeNow()
end

local function logError(key: string, err: any)
	local t = os.clock()
	if (lastErrorAt[key] or -math.huge) + ERROR_LOG_EVERY <= t then
		lastErrorAt[key] = t
		warn("[QueueService] " .. key .. ": " .. tostring(err))
	end
end

local function call(service: string, fn: string, ...: any): (boolean, any, any)
	local s = Services and Services[service]
	local f = s and s[fn]
	if type(f) ~= "function" then
		return false, nil, nil
	end
	local ok, a, b = pcall(f, ...)
	if not ok then
		logError(service .. "." .. fn, a)
		return false, nil, nil
	end
	return true, a, b
end

local function modeDef(key: any): any
	return if type(key) == "string" and type(MODES.Modes) == "table" then MODES.Modes[key] else nil
end

local function langOf(p: Player): Types.Lang
	local ok, lang = call("PlayerStateService", "LangOf", p)
	if ok and (lang == "de" or lang == "en") then
		return lang
	end
	return Lang.For(p)
end

local function text(p: Player, key: string, ...: any): string
	return Lang.T(langOf(p), key, ...)
end

local function notify(p: Player, key: string, args: { any }?, kind: Types.NotifyKind?)
	call("PlayerStateService", "Notify", p, key, args, kind)
end

-- Gleiche Meldung höchstens alle NOTIFY_GAP Sekunden (z. B. Pad-Sperre beim Draufstehen)
local function notifyThrottled(p: Player, key: string, args: { any }?, kind: Types.NotifyKind?)
	local list = notifyAt[p]
	if not list then
		list = {}
		notifyAt[p] = list
	end
	local t = os.clock()
	if (list[key] or -math.huge) + NOTIFY_GAP <= t then
		list[key] = t
		notify(p, key, args, kind)
	end
end

local function markDirty(p: Player)
	call("PlayerStateService", "MarkDirty", p, "Queue")
end

local function matchOf(p: Player): number?
	local ok, id = call("MatchService", "MatchOf", p)
	return if ok and type(id) == "number" then id else nil
end

local function rootOf(p: Player): BasePart?
	local char = p.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function isStudio(): boolean
	return RunService:IsStudio()
end

-- ---------------------------------------------------------------------
-- 2) SPIELER-INFOS (MMR, Matches, Rookie, Eingabegruppe)
-- ---------------------------------------------------------------------
local function inputGroup(kind: string?): string
	return if kind == "Touch" or kind == "Gamepad" then "Pad" else "KBM"
end

local function refreshInfo(p: Player): PlayerInfo
	local okM, mmr = call("ProgressionService", "Mmr", p)
	local okC, matches = call("ProgressionService", "MatchesPlayed", p)
	local okR, rookie = call("ProgressionService", "IsRookie", p)
	local count = if okC and type(matches) == "number" then matches else 0
	local info: PlayerInfo = {
		Mmr = if okM and type(mmr) == "number" then mmr else 1000,
		Matches = count,
		Rookie = if okR and type(rookie) == "boolean" then rookie else count < 3,
		Input = inputGroup(lastInput[p]),
	}
	infoOf[p] = info
	return info
end

local function infoFor(p: Player): PlayerInfo
	return infoOf[p] or refreshInfo(p)
end

type Aggregate = { Mmr: number, New: boolean, Veteran: boolean, Rookie: boolean, Input: string }

local function aggregate(entry: QEntry): Aggregate
	local sum, n = 0, 0
	local new, veteran, rookie = false, false, false
	local input: string? = nil
	for _, p in ipairs(entry.Players) do
		local info = infoFor(p)
		sum += info.Mmr
		n += 1
		if info.Matches < (Q.NewPlayerMatches or 5) then
			new = true
		end
		if info.Matches >= (Q.NewPlayerPool or 15) then
			veteran = true
		end
		if info.Rookie then
			rookie = true
		end
		if input == nil then
			input = info.Input
		elseif input ~= info.Input then
			input = "Mixed"
		end
	end
	return {
		Mmr = if n > 0 then sum / n else 1000,
		New = new,
		Veteran = veteran,
		Rookie = rookie,
		Input = input or "KBM",
	}
end

-- Reine Regel (B3.1): dürfen zwei Einträge im selben Match landen?
function QueueService._Compatible(a: Aggregate, b: Aggregate, waited: number, cfg: any): boolean
	if (a.New and b.Veteran) or (b.New and a.Veteran) then
		return false
	end
	if waited < (cfg.InputMatchSeconds or 6) and a.Input ~= b.Input and a.Input ~= "Mixed" and b.Input ~= "Mixed" then
		return false
	end
	local window = (cfg.MmrWindow or 200)
		+ (cfg.MmrWiden or 50) * math.floor(waited / math.max(0.1, cfg.MmrWidenEvery or 3))
	return math.abs(a.Mmr - b.Mmr) <= window
end

-- ---------------------------------------------------------------------
-- 3) EINTRÄGE
-- ---------------------------------------------------------------------
local function capacityOf(modeKey: string, side: string?): number
	local def = modeDef(modeKey)
	if not def then
		return 0
	end
	if def.Ruleset == "Respawn" then
		return if side == "B" then 0 else (def.MaxPlayers or 8)
	end
	return def.TeamSize or 1
end

local function padKey(padId: number, side: string): string
	return tostring(padId) .. ":" .. side
end

local function fillSeconds(rookie: boolean): number
	local base = Q.BotFillSeconds or 8
	if isStudio() then
		base = math.min(base, (Config.Studio and Config.Studio.BotFillSeconds) or 2)
	end
	if rookie then
		base = math.min(base, Q.RookieFillSeconds or 3)
	end
	return base
end

local function botAtOf(entry: QEntry, rookie: boolean?): number
	local held = entry.HeldTotal
	if entry.HeldSince then
		held += now() - entry.HeldSince -- Bot-Timer pausiert, solange gehalten wird
	end
	local isRookie = if rookie == nil then aggregate(entry).Rookie else rookie
	return entry.Since + fillSeconds(isRookie) + held
end

local function removeEntry(entry: QEntry)
	local list = queues[entry.Mode]
	if list then
		local idx = table.find(list, entry)
		if idx then
			table.remove(list, idx)
		end
	end
	if entry.Pad and entry.Side then
		local key = padKey(entry.Pad, entry.Side)
		if padEntries[key] == entry then
			padEntries[key] = nil
		end
	end
	for _, p in ipairs(entry.Players) do
		if entryOf[p] == entry then
			entryOf[p] = nil
		end
	end
end

-- Spieler aus seinem Eintrag nehmen (Rest bleibt in der Schlange)
local function detach(p: Player)
	local entry = entryOf[p]
	if not entry then
		return
	end
	entryOf[p] = nil
	offSince[p] = nil
	local idx = table.find(entry.Players, p)
	if idx then
		table.remove(entry.Players, idx)
	end
	if #entry.Players == 0 then
		removeEntry(entry)
	end
	markDirty(p)
end

function QueueService.Searching(modeKey: string): number
	local n = 0
	for _, entry in ipairs(queues[modeKey] or {}) do
		n += #entry.Players
	end
	return n
end

function QueueService.StateOf(p: Player): { Mode: string, Since: number, BotAt: number?, Searching: number }?
	local entry = entryOf[p]
	if not entry then
		return nil
	end
	return {
		Mode = entry.Mode,
		Since = entry.Since,
		BotAt = botAtOf(entry),
		Searching = QueueService.Searching(entry.Mode),
	}
end

function QueueService.LockPads(userId: number, seconds: number)
	if type(userId) == "number" and Util.IsFinite(seconds) then
		lockedUntil[userId] = now() + math.max(0, seconds)
	end
end

local function lockLeft(p: Player): number
	local untilT = lockedUntil[p.UserId]
	if not untilT then
		return 0
	end
	local left = untilT - now()
	if left <= 0 then
		lockedUntil[p.UserId] = nil
		return 0
	end
	return left
end

-- ---------------------------------------------------------------------
-- 4) KRONE – Hilfen (Linie, König, Tafel)
-- ---------------------------------------------------------------------
local function lineIndex(p: Player): number?
	for i, item in ipairs(crownLine) do
		if item.Player == p then
			return i
		end
	end
	return nil
end

local function removeFromLine(p: Player): boolean
	local idx = lineIndex(p)
	if idx then
		table.remove(crownLine, idx)
		markDirty(p)
		return true
	end
	return false
end

-- Königs-Tafel: LobbyBuilder baut die SurfaceGui "KingBoard" (Avatar, Name, Streak); fehlt sie, bauen wir eine eigene
local boardEmptyText: string? = nil

-- AKYTEX-Farben (docs/STYLE-AKYTEX.md) – der Server hat kein UI.Theme, daher dieselben Hex-Werte lokal
local AKY_BG = Color3.fromRGB(11, 15, 23) -- AKYTEX-Farbe Bg #0b0f17
local AKY_SURFACE2 = Color3.fromRGB(26, 33, 48) -- AKYTEX-Farbe Surface2 #1a2130
local AKY_TEXT = Color3.fromRGB(230, 236, 245) -- AKYTEX-Farbe Text #e6ecf5
local AKY_TEXT2 = Color3.fromRGB(170, 180, 195) -- AKYTEX-Farbe Text2 #aab4c3
local AKY_WARN = Color3.fromRGB(234, 179, 8) -- AKYTEX-Farbe Warn #eab308 (Gold/Krone)

local function buildOwnBoard(board: BasePart): SurfaceGui
	local surface = Instance.new("SurfaceGui")
	surface.Name = "KingBoard"
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 30
	surface.LightInfluence = 0
	-- dunkle Glas-Tafel mit 1-px-Warn-Rahmen (Krone = Gold-Akzent)
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = AKY_BG
	panel.BackgroundTransparency = 0.12
	panel.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = panel
	local frameStroke = Instance.new("UIStroke")
	frameStroke.Color = AKY_WARN
	frameStroke.Thickness = 1
	frameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	frameStroke.Parent = panel
	panel.Parent = surface
	local function boardLabel(name: string, y: number, h: number, font: Enum.Font, color: Color3): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(if name == "Title" then 0.05 else 0.39, y)
		label.Size = UDim2.fromScale(if name == "Title" then 0.9 else 0.56, h)
		label.Font = font
		label.TextScaled = true
		label.TextColor3 = color
		label.TextXAlignment = if name == "Title" then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
		label.Text = ""
		label.ZIndex = 2
		label.Parent = surface
		return label
	end
	-- Titel Michroma, Name BuilderSansBold, Serie in Warn (AKYTEX: keine dicke Kontur)
	boardLabel("Title", 0.06, 0.18, Enum.Font.Michroma, AKY_TEXT).Text = "👑 KÖNIG · KING"
	boardLabel("Name", 0.34, 0.26, Enum.Font.BuilderSansBold, AKY_TEXT)
	boardLabel("Streak", 0.64, 0.2, Enum.Font.BuilderSansBold, AKY_WARN)
	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.BackgroundColor3 = AKY_SURFACE2
	avatar.Position = UDim2.fromScale(0.05, 0.3)
	avatar.Size = UDim2.fromScale(0.3, 0.62)
	avatar.ScaleType = Enum.ScaleType.Fit
	avatar.ZIndex = 2
	local avatarCorner = Instance.new("UICorner")
	avatarCorner.CornerRadius = UDim.new(0, 12)
	avatarCorner.Parent = avatar
	local avatarStroke = Instance.new("UIStroke")
	avatarStroke.Color = AKY_TEXT2
	avatarStroke.Transparency = 0.6
	avatarStroke.Thickness = 1
	avatarStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	avatarStroke.Parent = avatar
	avatar.Parent = surface
	surface.Parent = board
	return surface
end

local function updateCrownBoard()
	local ok, board = call("LobbyBuilder", "CrownBoard")
	if not ok or typeof(board) ~= "Instance" or not board:IsA("BasePart") then
		return
	end
	local gui = board:FindFirstChild("KingBoard")
	if not gui or not gui:IsA("SurfaceGui") then
		gui = crownBoardGui or buildOwnBoard(board)
		crownBoardGui = gui :: SurfaceGui
	end
	local avatar = gui:FindFirstChild("Avatar")
	local name = gui:FindFirstChild("Name")
	local streak = gui:FindFirstChild("Streak")
	if name and name:IsA("TextLabel") and boardEmptyText == nil then
		boardEmptyText = if name.Text ~= "" then name.Text else "—"
	end
	local king = crownKing
	if avatar and avatar:IsA("ImageLabel") then
		avatar.Image = if king and king.UserId > 0
			then ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(king.UserId)
			elseif king then "rbxasset://textures/face.png"
			else ""
	end
	if name and name:IsA("TextLabel") then
		name.Text = if king then king.DisplayName else (boardEmptyText or "—")
	end
	if streak and streak:IsA("TextLabel") then
		streak.Text = if king then ("SERIE · STREAK: %d"):format(crownStreak) else ""
	end
end

local function setKing(p: Player?)
	local old = crownKing
	if old and old ~= p then
		old:SetAttribute("CrownStreak", nil)
		if old.Character then
			call("CharacterService", "SetHeadProp", old.Character, nil)
		end
		markDirty(old)
	end
	crownKing = p
	crownStreak = 0
	crownIdleSince = now()
	if p then
		p:SetAttribute("CrownStreak", 0)
		if p.Character then
			call("CharacterService", "SetHeadProp", p.Character, "Crown")
		end
		markDirty(p)
	end
	updateCrownBoard()
end

local function crownPitCenter(): Vector3?
	local ok, arena = call("ArenaService", "Crown")
	if ok and type(arena) == "table" and typeof(arena.Origin) == "CFrame" then
		return arena.Origin.Position
	end
	local origin = Config.Maps and Config.Maps.CrownOrigin
	return if typeof(origin) == "Vector3" then origin else nil
end

local function edgeCFrame(): CFrame
	local x = MCFG.CrownEdgeX or 60
	local z = if math.random() < 0.5 then -(MCFG.CrownEdgeZ or 16) else (MCFG.CrownEdgeZ or 16)
	return CFrame.lookAt(Vector3.new(x, MCFG.ArenaLobbyY or 3, z), Vector3.new(x - 10, MCFG.ArenaLobbyY or 3, z))
end

local function freeCircle(): Vector3?
	for _, circle in ipairs(crownCircles) do
		local taken = false
		for _, item in ipairs(crownLine) do
			local root = rootOf(item.Player)
			if root then
				local d = Vector3.new(root.Position.X - circle.X, 0, root.Position.Z - circle.Z)
				if d.Magnitude <= (Q.SeatRadius or 2.2) then
					taken = true
					break
				end
			end
		end
		if not taken then
			return circle
		end
	end
	return nil
end

-- ---------------------------------------------------------------------
-- 5) BEITRETEN / VERLASSEN
-- ---------------------------------------------------------------------
local function serverLockedFor(p: Player): boolean
	local okL, locked = call("AdminService", "IsServerLocked")
	if not okL or locked ~= true then
		return false
	end
	local okA, admin = call("AdminService", "IsAdmin", p)
	return not (okA and admin == true)
end

function QueueService.Leave(p: Player)
	detach(p)
	voteWatch[p] = nil
	removeFromLine(p)
end

function QueueService.Join(
	p: Player,
	modeKey: string,
	source: { Pad: number?, Side: ("A" | "B")? }?
): (boolean, string?)
	local def = modeDef(modeKey)
	if not def or def.Queue ~= true then
		return false, text(p, "match.unknownMode")
	end
	local okReady, ready = call("PlayerStateService", "IsReady", p)
	if not okReady or ready ~= true then
		return false, text(p, "core.loading")
	end
	if matchOf(p) ~= nil then
		return false, text(p, "match.inMatch")
	end
	local locked = lockLeft(p)
	if locked > 0 then
		return false, text(p, "match.padLocked", math.ceil(locked))
	end
	if serverLockedFor(p) then
		return false, text(p, "match.serverLocked")
	end
	local padId = source and source.Pad
	local side = source and source.Side
	if padId ~= nil and (type(padId) ~= "number" or (side ~= "A" and side ~= "B")) then
		return false, text(p, "core.invalid")
	end
	-- schon drin?
	local current = entryOf[p]
	if current and current.Mode == modeKey and current.Pad == padId and current.Side == side then
		return true, nil
	end
	-- höchstens eine Schlange: Krone und alte Schlange verlassen
	if p == crownKing then
		QueueService.CrownLeave(p)
	end
	removeFromLine(p)
	detach(p)
	refreshInfo(p)

	-- FFA: laufendes Match mit Platz? -> sofort einsteigen (B4 Drop-in)
	if def.Ruleset == "Respawn" then
		local okDrop, dropped = call("MatchService", "DropIn", p)
		if okDrop and dropped == true then
			return true, text(p, "match.droppedIn")
		end
	end

	local list = queues[modeKey]
	if not list then
		list = {}
		queues[modeKey] = list
	end
	local t = now()
	if padId and side then
		local key = padKey(padId, side)
		local entry = padEntries[key]
		if entry and entry.Mode == modeKey then
			if #entry.Players >= capacityOf(modeKey, side) then
				return false, text(p, "match.padFull")
			end
			table.insert(entry.Players, p)
			entryOf[p] = entry
			markDirty(p)
			return true, nil
		end
	end
	if #list >= (Q.MaxEntries or 64) then
		return false, text(p, "match.queueFull")
	end
	nextEntryId += 1
	local entry: QEntry = {
		Id = nextEntryId,
		Mode = modeKey,
		Players = { p },
		Since = t,
		Pad = padId,
		Side = side,
		FillNow = false,
		HeldSince = nil,
		HeldTotal = 0,
		HoldReason = nil,
		PrevHold = nil,
	}
	table.insert(list, entry)
	entryOf[p] = entry
	if padId and side then
		padEntries[padKey(padId, side)] = entry
	end
	markDirty(p)
	return true, nil
end

function QueueService.FillNow(p: Player): boolean
	local entry = entryOf[p]
	if not entry then
		return false
	end
	if now() - entry.Since < (Q.FillNowAfter or 3) then
		return false
	end
	entry.FillNow = true
	return true
end

function QueueService.ForceFillPads()
	for _, list in pairs(queues) do
		for _, entry in ipairs(list) do
			entry.FillNow = true
		end
	end
end

function QueueService.CrownKing(): Player?
	local king = crownKing
	if king and king.Parent ~= Players then
		return nil
	end
	return king
end

function QueueService.CrownJoin(p: Player): (boolean, string?)
	return QueueService._CrownJoin(p, false)
end

function QueueService._CrownJoin(p: Player, viaCircle: boolean): (boolean, string?)
	local okReady, ready = call("PlayerStateService", "IsReady", p)
	if not okReady or ready ~= true then
		return false, text(p, "core.loading")
	end
	if matchOf(p) ~= nil then
		return false, text(p, "match.inMatch")
	end
	if p == crownKing then
		return false, text(p, "match.crownAlreadyKing")
	end
	if lineIndex(p) then
		return true, nil
	end
	if serverLockedFor(p) then
		return false, text(p, "match.serverLocked")
	end
	if #crownLine >= (Q.CrownLine or 6) then
		return false, text(p, "match.crownFull")
	end
	detach(p)
	local item: LineEntry = { Player = p, Since = now(), ViaCircle = viaCircle }
	table.insert(crownLine, item)
	if not viaCircle then
		-- PLAY -> "Krone herausfordern": auf einen freien Kreis der Herausforderer-Linie
		local circle = freeCircle()
		if circle then
			call("CharacterService", "Teleport", p, CFrame.new(circle + Vector3.new(0, 3, 0)))
			item.ViaCircle = true
		end
	end
	markDirty(p)
	notify(p, "match.crownJoined", { #crownLine }, "Info")
	return true, nil
end

function QueueService.CrownLeave(p: Player)
	if p == crownKing then
		local inMatch = matchOf(p) ~= nil
		setKing(nil)
		notify(p, "match.crownLeft", nil, "Info")
		if not inMatch then
			-- aus der Grube heraus an den Rand
			call("CharacterService", "Teleport", p, edgeCFrame())
			rejoinGrace[p] = now() + (Q.CrownRejoinGrace or 3)
		end
		return
	end
	removeFromLine(p)
end

-- MatchService meldet das Ende eines Kronen-Duells
function QueueService.CrownMatchEnded(
	id: number,
	winner: Player?,
	losers: { Player },
	winnerTeam: number,
	oldKing: Player?
)
	if crownMatchId == id then
		crownMatchId = nil
	end
	local t = now()
	crownIdleSince = t
	for _, p in ipairs(losers or {}) do
		rejoinGrace[p] = t + (Q.CrownRejoinGrace or 3)
	end
	if winnerTeam == 0 then
		-- Unentschieden/abgebrochen: König bleibt König
		updateCrownBoard()
		return
	end
	if winner and winner.Parent == Players then
		if winner == crownKing then
			crownStreak += 1
			winner:SetAttribute("CrownStreak", crownStreak)
			notify(winner, "match.crownDefended", { crownStreak }, "Success")
			local announce = Config.Progression and Config.Progression.Crown and Config.Progression.Crown.Announce
			if type(announce) ~= "table" then
				announce = { 3, 5, 10 }
			end
			if table.find(announce, crownStreak) then
				call("CommunityService", "Announce", "match.crownStreak", { winner.DisplayName, crownStreak }, nil)
			end
			updateCrownBoard()
		else
			setKing(winner)
			notify(winner, "match.crownKing", nil, "Success")
		end
		markDirty(winner)
	elseif oldKing and oldKing == crownKing then
		-- König hat gegen einen Bot verloren
		setKing(nil)
	else
		updateCrownBoard()
	end
end

-- ---------------------------------------------------------------------
-- 6) MATCHER (2 Hz)
-- ---------------------------------------------------------------------
type Unit = { A: QEntry, B: QEntry? }

local function hold(entries: { QEntry }, reason: string)
	local t = now()
	for _, entry in ipairs(entries) do
		if not entry.HeldSince then
			entry.HeldSince = t
		end
		if entry.HoldReason ~= reason then
			local changed = entry.PrevHold ~= reason
			entry.HoldReason = reason
			if changed then
				for _, p in ipairs(entry.Players) do
					notifyThrottled(p, if reason == "Bots" then "match.botsBusy" else "match.arenasFull", nil, "Info")
				end
			end
		end
	end
end

-- Zu Beginn jedes Matcher-Durchlaufs: gehaltene Zeit gutschreiben (Bot-Timer pausiert nur, solange
-- wirklich gehalten wird); hold() setzt den Zustand im selben Takt wieder, wenn es weiter klemmt.
local function releaseHolds(list: { QEntry })
	local t = now()
	for _, entry in ipairs(list) do
		if entry.HeldSince then
			entry.HeldTotal += t - entry.HeldSince
			entry.HeldSince = nil
		end
		entry.PrevHold = entry.HoldReason
		entry.HoldReason = nil
	end
end

local function playersOf(entries: { QEntry }): { Player }
	local list: { Player } = {}
	for _, entry in ipairs(entries) do
		for _, p in ipairs(entry.Players) do
			table.insert(list, p)
		end
	end
	return list
end

-- Match bauen (Bots füllt MatchService.Create bis zur Teamgröße auf)
local function tryCreate(modeKey: string, teams: { { QEntry } }, botsNeeded: number): boolean
	local all: { QEntry } = {}
	for _, list in ipairs(teams) do
		for _, entry in ipairs(list) do
			table.insert(all, entry)
		end
	end
	local okHost, canHost = call("MatchService", "CanHost", modeKey)
	if not okHost or canHost ~= true then
		hold(all, "Arenas")
		return false
	end
	if botsNeeded > 0 then
		local okBudget, budget = call("BotService", "Budget")
		local maxPerMatch = Config.Server.MaxBotsPerMatch or 7
		if not okBudget or type(budget) ~= "number" or budget < botsNeeded or botsNeeded > maxPerMatch then
			hold(all, "Bots")
			return false
		end
	end
	local specTeams: { { any } } = {}
	for i, list in ipairs(teams) do
		specTeams[i] = playersOf(list)
	end
	-- Pad-Spieler merken: wer in der Kartenwahl das Pad verlässt, fliegt raus (B5)
	local watch: { [Player]: { Pad: number, Side: string } } = {}
	for _, entry in ipairs(all) do
		if entry.Pad and entry.Side then
			for _, p in ipairs(entry.Players) do
				watch[p] = { Pad = entry.Pad, Side = entry.Side }
			end
		end
	end
	local waits: { number } = {}
	for _, entry in ipairs(all) do
		table.insert(waits, now() - entry.Since)
	end
	local okCreate, id = call("MatchService", "Create", { Mode = modeKey, Teams = specTeams })
	if not okCreate or type(id) ~= "number" then
		hold(all, "Arenas")
		return false
	end
	for _, entry in ipairs(all) do
		removeEntry(entry)
		for _, p in ipairs(entry.Players) do
			offSince[p] = nil
			markDirty(p)
		end
	end
	for p, w in pairs(watch) do
		voteWatch[p] = { Pad = w.Pad, Side = w.Side, OffSince = nil }
	end
	for _, waited in ipairs(waits) do
		call("BalanceService", "Stat", "QueueTime", modeKey, math.floor(waited + 0.5))
	end
	return true
end

local function buildUnits(list: { QEntry }): { Unit }
	local units: { Unit } = {}
	local used: { [QEntry]: boolean } = {}
	for _, entry in ipairs(list) do
		if not used[entry] then
			used[entry] = true
			local partner: QEntry? = nil
			if entry.Pad and entry.Side then
				local other = padEntries[padKey(entry.Pad, if entry.Side == "A" then "B" else "A")]
				if other and other.Mode == entry.Mode and not used[other] then
					partner = other
					used[other] = true
				end
			end
			if partner then
				-- Pad-Hälfte A immer Team 1 der Einheit
				if entry.Side == "A" then
					table.insert(units, { A = entry, B = partner })
				else
					table.insert(units, { A = partner, B = entry })
				end
			else
				table.insert(units, { A = entry, B = nil })
			end
		end
	end
	return units
end

local function fillDue(entries: { QEntry }, anchor: QEntry, t: number): boolean
	local rookie = false
	for _, entry in ipairs(entries) do
		if entry.FillNow then
			return true
		end
		if aggregate(entry).Rookie then
			rookie = true
		end
	end
	if anchor.HeldSince then
		return false -- Timer pausiert
	end
	return t >= botAtOf(anchor, rookie)
end

local function compatibleWith(group: { QEntry }, candidate: { QEntry }, t: number): boolean
	for _, c in ipairs(candidate) do
		local ca = aggregate(c)
		for _, g in ipairs(group) do
			local waited = t - math.min(c.Since, g.Since)
			if not QueueService._Compatible(ca, aggregate(g), waited, Q) then
				return false
			end
		end
	end
	return true
end

-- Reine Team-Bildung (testbar): ab einem Anker-Eintrag (älteste zuerst) passende Einheiten auf zwei Teams
-- der Größe n verteilen. Einheit = { A = Eintrag, B = gekoppelter Gegner (andere Pad-Hälfte)? }.
-- compatible(group, members) entscheidet über die Regeln (Eingabegruppe, MMR, Neulings-Schutz).
function QueueService._FormTeams(
	units: { any },
	anchor: any,
	n: number,
	compatible: ({ any }, { any }) -> boolean
): ({ any }, { any }, { any }, number, number)
	local t1: { any } = { anchor.A }
	local t2: { any } = if anchor.B then { anchor.B } else {}
	local group: { any } = if anchor.B then { anchor.A, anchor.B } else { anchor.A }
	local n1 = #anchor.A.Players
	local n2 = if anchor.B then #anchor.B.Players else 0
	for _, u in ipairs(units) do
		if n1 >= n and n2 >= n then
			break
		end
		if u ~= anchor then
			local members = if u.B then { u.A, u.B } else { u.A }
			if compatible(group, members) then
				local a1 = #u.A.Players
				local b1 = if u.B then #u.B.Players else 0
				local placed = false
				if n1 + a1 <= n and n2 + b1 <= n then
					table.insert(t1, u.A)
					if u.B then
						table.insert(t2, u.B)
					end
					n1 += a1
					n2 += b1
					placed = true
				elseif n2 + a1 <= n and n1 + b1 <= n then
					table.insert(t2, u.A)
					if u.B then
						table.insert(t1, u.B)
					end
					n2 += a1
					n1 += b1
					placed = true
				end
				if placed then
					for _, m in ipairs(members) do
						table.insert(group, m)
					end
				end
			end
		end
	end
	return t1, t2, group, n1, n2
end

-- Ein Durchlauf für einen Duell-Modus; true = ein Match wurde gebaut
local function matchDuel(modeKey: string, def: any, t: number): boolean
	local list = queues[modeKey]
	if not list or #list == 0 then
		return false
	end
	table.sort(list, function(a, b)
		return a.Since < b.Since
	end)
	releaseHolds(list)
	local n = def.TeamSize or 1
	-- (1) volle Pads -> sofort
	for _, pad in ipairs(pads) do
		if pad.Mode == modeKey then
			local a = padEntries[padKey(pad.Id, "A")]
			local b = padEntries[padKey(pad.Id, "B")]
			if a and b and #a.Players == n and #b.Players == n then
				if tryCreate(modeKey, { { a }, { b } }, 0) then
					return true
				end
			end
		end
	end
	-- (2) Menschen kombinieren, (3) Bot-Füllung
	local units = buildUnits(list)
	local function compatible(group: { QEntry }, members: { QEntry }): boolean
		return compatibleWith(group, members, t)
	end
	for _, anchor in ipairs(units) do
		local t1, t2, group, n1, n2 = QueueService._FormTeams(units, anchor, n, compatible)
		if n1 == n and n2 == n then
			if tryCreate(modeKey, { t1, t2 }, 0) then
				return true
			end
		elseif fillDue(group, anchor.A, t) then
			-- Team 2 darf leer sein (nur Bots), Team 1 hat immer den ältesten Eintrag
			if tryCreate(modeKey, { t1, t2 }, (n - n1) + (n - n2)) then
				return true
			end
		end
	end
	return false
end

local function matchFfa(modeKey: string, def: any, t: number): boolean
	local list = queues[modeKey]
	if not list or #list == 0 then
		return false
	end
	table.sort(list, function(a, b)
		return a.Since < b.Since
	end)
	releaseHolds(list)
	local maxPlayers = def.MaxPlayers or 8
	local anchor = list[1]
	local group: { QEntry } = { anchor }
	local count = #anchor.Players
	for i = 2, #list do
		local entry = list[i]
		if count + #entry.Players <= maxPlayers and compatibleWith(group, { entry }, t) then
			table.insert(group, entry)
			count += #entry.Players
		end
	end
	local padFull = false
	for _, entry in ipairs(group) do
		if entry.Pad and #entry.Players >= maxPlayers then
			padFull = true
		end
	end
	if count >= maxPlayers or padFull then
		return tryCreate(modeKey, { group }, 0)
	end
	if fillDue(group, anchor, t) then
		return tryCreate(modeKey, { group }, math.max(0, (def.FillTo or 6) - count))
	end
	return false
end

-- ---------------------------------------------------------------------
-- 7) KRONEN-TAKT
-- ---------------------------------------------------------------------
local function crownBotDifficulty(): string
	local tiers = Config.Bots and Config.Bots.CrownTiers
	if type(tiers) == "table" then
		for _, tier in ipairs(tiers) do
			if type(tier) == "table" and type(tier.MaxStreak) == "number" and crownStreak <= tier.MaxStreak then
				return tier.Diff
			end
		end
	end
	return if crownStreak >= 6 then "Insane" elseif crownStreak >= 3 then "Hard" else "Normal"
end

local function startCrown(teamA: { any }, teamB: { any }, requeueFront: { LineEntry }): boolean
	local okCreate, id = call("MatchService", "Create", { Mode = "Crown", Teams = { teamA, teamB } })
	if okCreate and type(id) == "number" then
		crownMatchId = id
		return true
	end
	-- zurück an den Anfang der Linie
	for i = #requeueFront, 1, -1 do
		table.insert(crownLine, 1, requeueFront[i])
	end
	for _, item in ipairs(requeueFront) do
		notifyThrottled(item.Player, "match.botsBusy", nil, "Info")
	end
	return false
end

local function tickCrown(t: number)
	-- Linie aufräumen
	for i = #crownLine, 1, -1 do
		local p = crownLine[i].Player
		if p.Parent ~= Players or matchOf(p) ~= nil then
			table.remove(crownLine, i)
			markDirty(p)
		end
	end
	local king = crownKing
	if king and king.Parent ~= Players then
		setKing(nil)
		king = nil
	end
	if crownMatchId then
		local okInfo, info = call("MatchService", "Info", crownMatchId)
		if okInfo and info ~= nil then
			return
		end
		crownMatchId = nil
	end
	if king then
		-- König hat die Grube verlassen (z. B. Reset in der Lobby) -> Krone abgegeben
		local center = crownPitCenter()
		local root = rootOf(king)
		if matchOf(king) == nil and (not root or (center and (root.Position - center).Magnitude > CROWN_PIT_REACH)) then
			setKing(nil)
			notify(king, "match.crownLeft", nil, "Info")
			king = nil
		end
	end
	if king then
		if matchOf(king) ~= nil then
			return
		end
		if #crownLine > 0 then
			local item = table.remove(crownLine, 1) :: LineEntry
			startCrown({ king }, { item.Player }, { item })
		elseif t - crownIdleSince >= (Q.CrownIdleBot or 15) then
			if not startCrown({ king }, { { Bot = true, Difficulty = crownBotDifficulty() } }, {}) then
				crownIdleSince = t - (Q.CrownIdleBot or 15) + 3 -- in 3 s erneut versuchen
			end
		end
	else
		if #crownLine >= 2 then
			local a = table.remove(crownLine, 1) :: LineEntry
			local b = table.remove(crownLine, 1) :: LineEntry
			startCrown({ a.Player }, { b.Player }, { a, b })
		elseif #crownLine == 1 and t - crownLine[1].Since >= (Q.CrownSoloWait or 8) then
			local a = table.remove(crownLine, 1) :: LineEntry
			if not startCrown({ a.Player }, { { Bot = true, Difficulty = "Normal" } }, { a }) then
				a.Since = t - (Q.CrownSoloWait or 8) + 3
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- 8) STATE ("Queue") – nur bei Änderung als dirty markieren
-- ---------------------------------------------------------------------
local function counts(): { [string]: number }
	local out: { [string]: number } = {}
	for _, key in ipairs(MODES.Order or {}) do
		out[key] = QueueService.Searching(key)
	end
	out.Crown = #crownLine
	return out
end

local function stateFor(p: Player): { [string]: any }
	local state: { [string]: any } = { Counts = counts() }
	local entry = entryOf[p]
	if entry then
		state.Mode = entry.Mode
		state.Since = entry.Since
		state.BotAt = botAtOf(entry)
		state.Searching = QueueService.Searching(entry.Mode)
		state.Held = entry.HoldReason
		state.CanFill = now() - entry.Since >= (Q.FillNowAfter or 3)
		state.FillAt = entry.Since + (Q.FillNowAfter or 3)
		state.Pad = entry.Pad
		state.Mates = #entry.Players
	end
	local king = QueueService.CrownKing()
	state.Crown = {
		Line = lineIndex(p) or 0,
		LineSize = #crownLine,
		King = if king then king.DisplayName else "",
		KingId = if king then king.UserId else 0,
		Streak = if king then crownStreak else 0,
		IsKing = king == p,
	}
	local locked = lockLeft(p)
	if locked > 0 then
		state.LockedUntil = now() + locked
	end
	return state
end

local function signature(state: { [string]: any }): string
	local crown = state.Crown
	return table.concat({
		tostring(state.Mode),
		tostring(state.Since),
		tostring(state.BotAt and math.floor(state.BotAt * 2)),
		tostring(state.Searching),
		tostring(state.Held),
		tostring(state.CanFill),
		tostring(state.Mates),
		tostring(crown.Line),
		tostring(crown.LineSize),
		crown.King,
		tostring(crown.Streak),
		tostring(state.LockedUntil and math.floor(state.LockedUntil)),
	}, "|")
end

local function refreshStates()
	local c = counts()
	local parts = {}
	for _, key in ipairs(MODES.Order or {}) do
		table.insert(parts, tostring(c[key]))
	end
	table.insert(parts, tostring(c.Crown))
	local countSig = table.concat(parts, ",")
	local countsChanged = countSig ~= lastCounts
	lastCounts = countSig
	for _, p in ipairs(Players:GetPlayers()) do
		local sig = signature(stateFor(p))
		if countsChanged or sig ~= stateSig[p] then
			stateSig[p] = sig
			markDirty(p)
		end
	end
end

local function matcherTick(_dt: number)
	local t = now()
	local created = 0
	for _, modeKey in ipairs(MODES.Order or {}) do
		local def = modeDef(modeKey)
		if def and def.Queue then
			local ok, err = pcall(function()
				while created < MAX_CREATES_PER_TICK do
					local made = if def.Ruleset == "Respawn"
						then matchFfa(modeKey, def, t)
						else matchDuel(modeKey, def, t)
					if not made then
						break
					end
					created += 1
				end
			end)
			if not ok then
				logError("Matcher " .. modeKey, err)
			end
		end
	end
	local okCrown, errCrown = pcall(tickCrown, t)
	if not okCrown then
		logError("Krone", errCrown)
	end
	-- abgelaufene Pad-Sperren entfernen (Tabelle bleibt klein)
	for userId, untilT in pairs(lockedUntil) do
		if untilT <= t then
			lockedUntil[userId] = nil
		end
	end
	refreshStates()
end

-- ---------------------------------------------------------------------
-- 9) PAD-SCAN (4 Hz) + Pad-Attribute + Kronen-Kreise
-- ---------------------------------------------------------------------
local function loadPads()
	if #pads > 0 then
		return
	end
	local ok, list = call("LobbyBuilder", "Pads")
	if not ok or type(list) ~= "table" then
		return
	end
	for _, pad in ipairs(list) do
		local part = if type(pad) == "table" then pad.Part else nil
		if
			type(pad) == "table"
			and type(pad.Id) == "number"
			and modeDef(pad.Mode)
			and typeof(part) == "Instance"
			and part:IsA("BasePart")
		then
			local basePart = part :: BasePart
			table.insert(pads, {
				Id = pad.Id,
				Mode = pad.Mode,
				Part = basePart,
				Center = if typeof(pad.Center) == "Vector3" then pad.Center else basePart.Position,
				SeatsA = if type(pad.SeatsA) == "table" then pad.SeatsA else {},
				SeatsB = if type(pad.SeatsB) == "table" then pad.SeatsB else {},
			})
		end
	end
	local okLine, circles = call("LobbyBuilder", "CrownLine")
	if okLine and type(circles) == "table" then
		for _, v in ipairs(circles) do
			if typeof(v) == "Vector3" then
				table.insert(crownCircles, v)
			end
		end
	end
end

local function onSeat(pos: Vector3, seat: Vector3): boolean
	local flat = Vector3.new(pos.X - seat.X, 0, pos.Z - seat.Z)
	return flat.Magnitude <= (Q.SeatRadius or 2.2) and math.abs(pos.Y - seat.Y) < (Q.SeatHeight or 5)
end

local function setPadAttr(pad: Pad, key: string, value: any)
	local cache = padAttrCache[pad.Id]
	if not cache then
		cache = {}
		padAttrCache[pad.Id] = cache
	end
	if cache[key] ~= value then
		cache[key] = value
		pad.Part:SetAttribute(key, value)
	end
end

local function refreshPadAttributes()
	for _, pad in ipairs(pads) do
		local a = padEntries[padKey(pad.Id, "A")]
		local b = padEntries[padKey(pad.Id, "B")]
		local capA, capB = capacityOf(pad.Mode, "A"), capacityOf(pad.Mode, "B")
		local countA = if a then #a.Players else 0
		local countB = if b then #b.Players else 0
		local botAt = 0
		local held = false
		for _, entry in ipairs({ a, b }) do
			if entry then
				local at = botAtOf(entry)
				if botAt == 0 or at < botAt then
					botAt = at
				end
				if entry.HeldSince then
					held = true
				end
			end
		end
		local voting = false
		for _, w in pairs(voteWatch) do
			if w.Pad == pad.Id then
				voting = true
				break
			end
		end
		local phase = "Idle"
		if voting then
			phase = "Vote"
		elseif held then
			phase = "Held"
		elseif countA >= capA and countB >= capB and countA + countB > 0 then
			phase = "Full"
		elseif countA + countB > 0 then
			phase = "Waiting"
		end
		setPadAttr(pad, "Mode", pad.Mode)
		setPadAttr(pad, "PadId", pad.Id)
		setPadAttr(pad, "NeedA", math.max(0, capA - countA))
		setPadAttr(pad, "NeedB", math.max(0, capB - countB))
		setPadAttr(pad, "CountA", countA)
		setPadAttr(pad, "CountB", countB)
		setPadAttr(pad, "BotAt", math.floor(botAt * 10 + 0.5) / 10)
		setPadAttr(pad, "Searching", QueueService.Searching(pad.Mode))
		setPadAttr(pad, "Phase", phase)
	end
end

local function buildBooths()
	if boothsBuilt or boothAttempts >= BOOTH_ATTEMPTS then
		return
	end
	boothAttempts += 1
	local ok, booths = call("LobbyBuilder", "BotBooth")
	if not ok or type(booths) ~= "table" or #booths == 0 then
		return
	end
	boothsBuilt = true
	for _, booth in ipairs(booths) do
		if type(booth) == "table" and typeof(booth.Pos) == "Vector3" and type(booth.Difficulty) == "string" then
			-- Attachment im Terrain = Prompt ohne eigenes Bauteil (Text lokalisiert der Client, QueueUI)
			local attachment = Instance.new("Attachment")
			attachment.Name = "PracticeBooth_" .. booth.Difficulty
			attachment.WorldPosition = booth.Pos + Vector3.new(0, 2.5, 0)
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "PracticePrompt"
			prompt.ActionText = "Start"
			prompt.ObjectText = booth.Difficulty
			prompt.HoldDuration = 0.25
			prompt.MaxActivationDistance = 8
			prompt.RequiresLineOfSight = false
			prompt:SetAttribute("PracticeDifficulty", booth.Difficulty)
			prompt.Parent = attachment
			CollectionService:AddTag(prompt, PRACTICE_PROMPT_TAG)
			attachment.Parent = workspace.Terrain
		end
	end
end

local function padScan(_dt: number)
	loadPads()
	buildBooths()
	local t = now()
	-- wer sitzt wo?
	local seatOf: { [Player]: { Pad: Pad, Side: string } } = {}
	local onCircle: { [Player]: boolean } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local root = rootOf(p)
		local id = matchOf(p)
		if root and (id == nil or voteWatch[p]) then
			local pos = root.Position
			for _, pad in ipairs(pads) do
				local flat = Vector3.new(pos.X - pad.Center.X, 0, pos.Z - pad.Center.Z)
				if flat.Magnitude <= PAD_REACH then
					for _, side in ipairs({ "A", "B" }) do
						local seats = if side == "A" then pad.SeatsA else pad.SeatsB
						for _, seat in ipairs(seats) do
							if typeof(seat) == "Vector3" and onSeat(pos, seat) then
								seatOf[p] = { Pad = pad, Side = side }
								break
							end
						end
						if seatOf[p] then
							break
						end
					end
				end
				if seatOf[p] then
					break
				end
			end
			if id == nil then
				for _, circle in ipairs(crownCircles) do
					if onSeat(pos, circle) then
						onCircle[p] = true
						break
					end
				end
			end
		end
	end

	-- Kartenwahl: Pad verlassen = raus, Bot ersetzt (B5)
	for p, w in pairs(voteWatch) do
		local id = matchOf(p)
		local okPhase, phase = false, nil
		if id then
			okPhase, phase = call("MatchService", "Phase", id)
		end
		if not id or not okPhase or phase ~= "Vote" then
			voteWatch[p] = nil
		else
			local s = seatOf[p]
			if s and s.Pad.Id == w.Pad and s.Side == w.Side then
				w.OffSince = nil
			else
				w.OffSince = w.OffSince or t
				if t - (w.OffSince :: number) >= (Q.SeatLeaveSeconds or 1.5) then
					voteWatch[p] = nil
					call("MatchService", "Leave", p, "LeftPad")
				end
			end
		end
	end

	-- Hinsetzen = Schlange betreten
	for p, s in pairs(seatOf) do
		if not voteWatch[p] and matchOf(p) == nil then
			local entry = entryOf[p]
			if entry and entry.Pad == s.Pad.Id and entry.Side == s.Side then
				offSince[p] = nil
			elseif lockLeft(p) > 0 then
				notifyThrottled(p, "match.padLocked", { math.ceil(lockLeft(p)) }, "Error")
			else
				local okReady, ready = call("PlayerStateService", "IsReady", p)
				if okReady and ready == true then
					local okJoin, reason = QueueService.Join(p, s.Pad.Mode, { Pad = s.Pad.Id, Side = s.Side :: any })
					if not okJoin and reason then
						notifyThrottled(p, "match.padNope", { reason }, "Error")
					end
				end
			end
		end
	end

	-- Volles Pad -> sofort matchen (nicht erst im nächsten Matcher-Takt; "erster Schuss ≤ 15 s")
	for _, pad in ipairs(pads) do
		local def = modeDef(pad.Mode)
		local a = padEntries[padKey(pad.Id, "A")]
		if def and a then
			local b = padEntries[padKey(pad.Id, "B")]
			local full = #a.Players >= capacityOf(pad.Mode, "A")
				and (capacityOf(pad.Mode, "B") == 0 or (b ~= nil and #b.Players >= capacityOf(pad.Mode, "B")))
			if full then
				local ok, err = pcall(function()
					if def.Ruleset == "Respawn" then
						matchFfa(pad.Mode, def, t)
					else
						matchDuel(pad.Mode, def, t)
					end
				end)
				if not ok then
					logError("Pad-Match", err)
				end
			end
		end
	end

	-- Aufstehen > 1.5 s = Schlange verlassen
	for p, entry in pairs(entryOf) do
		if entry.Pad then
			local s = seatOf[p]
			if s and s.Pad.Id == entry.Pad and s.Side == entry.Side then
				offSince[p] = nil
			else
				offSince[p] = offSince[p] or t
				if t - offSince[p] >= (Q.SeatLeaveSeconds or 1.5) then
					detach(p)
				end
			end
		end
	end

	-- Kronen-Kreise: draufstellen = Herausforderer-Linie, runter > 1.5 s = raus
	for p in pairs(onCircle) do
		if p ~= crownKing and not lineIndex(p) and t >= (rejoinGrace[p] or 0) and not entryOf[p] then
			local okReady, ready = call("PlayerStateService", "IsReady", p)
			if okReady and ready == true then
				local okJoin, reason = QueueService._CrownJoin(p, true)
				if not okJoin and reason then
					notifyThrottled(p, "match.padNope", { reason }, "Error")
				end
			end
		end
	end
	for _, item in ipairs(table.clone(crownLine)) do
		local p = item.Player
		if item.ViaCircle then
			if onCircle[p] then
				offSince[p] = nil
			elseif not entryOf[p] then
				offSince[p] = offSince[p] or t
				if t - offSince[p] >= (Q.SeatLeaveSeconds or 1.5) then
					offSince[p] = nil
					removeFromLine(p)
				end
			end
		end
	end
	refreshPadAttributes()
end

-- ---------------------------------------------------------------------
-- 10) REQUEST-AKTIONEN (C9)
-- ---------------------------------------------------------------------
local function reply(_p: Player, ok: boolean, message: string?): Reply
	return { Ok = ok, Message = message }
end

local function handleQueueJoin(p: Player, arg: any): Reply
	local modeKey: any = arg
	if type(arg) == "table" then
		-- Erweiterung: { Mode, Input } – Eingabegruppe für das Matchmaking (B3.1)
		modeKey = arg.Mode
		local input = arg.Input
		if input == "KBM" or input == "Gamepad" or input == "Touch" then
			lastInput[p] = input
		end
	end
	if type(modeKey) ~= "string" or #modeKey > 24 then
		return reply(p, false, text(p, "core.invalid"))
	end
	if modeKey == "Crown" then
		local ok, msg = QueueService.CrownJoin(p)
		return reply(p, ok, msg)
	end
	local ok, msg = QueueService.Join(p, modeKey, nil)
	if ok and msg == nil then
		local def = modeDef(modeKey)
		msg = text(p, "match.queued", if def then Lang.Pick(langOf(p), def.Name) else modeKey)
	end
	return reply(p, ok, msg)
end

local function handleQueueLeave(p: Player, _arg: any): Reply
	local had = entryOf[p] ~= nil or lineIndex(p) ~= nil
	QueueService.Leave(p)
	return reply(p, true, if had then text(p, "match.queueLeft") else nil)
end

local function handleFillBots(p: Player, _arg: any): Reply
	local entry = entryOf[p]
	if not entry then
		return reply(p, false, text(p, "match.notQueued"))
	end
	if QueueService.FillNow(p) then
		return reply(p, true, nil)
	end
	local left = math.ceil((Q.FillNowAfter or 3) - (now() - entry.Since))
	return reply(p, false, text(p, "match.fillTooEarly", math.max(1, left)))
end

local function handleCrownJoin(p: Player, _arg: any): Reply
	local ok, msg = QueueService.CrownJoin(p)
	return reply(p, ok, msg)
end

local function handleCrownLeave(p: Player, _arg: any): Reply
	QueueService.CrownLeave(p)
	return reply(p, true, nil)
end

-- PLAY -> "Training": Teleport an die Schusslinie der Range
local function handleGoRange(p: Player, _arg: any): Reply
	if matchOf(p) ~= nil then
		return reply(p, false, text(p, "match.inMatch"))
	end
	local t = os.clock()
	if (rangeAt[p] or -math.huge) + (Q.RangeTeleportCooldown or 2) > t then
		return reply(p, false, nil)
	end
	rangeAt[p] = t
	local ok, cf, size = call("LobbyBuilder", "RangeZone")
	if not ok or typeof(cf) ~= "CFrame" or typeof(size) ~= "Vector3" then
		return reply(p, false, text(p, "core.error"))
	end
	QueueService.Leave(p)
	if p == crownKing then
		QueueService.CrownLeave(p)
	end
	-- östlicher Rand der Range-Zone (Schusslinie), Blick nach −X (B2)
	local center = cf.Position
	local pos = Vector3.new(center.X + size.X / 2 - 3, (MCFG.ArenaLobbyY or 3), center.Z)
	call("CharacterService", "Teleport", p, CFrame.lookAt(pos, pos - Vector3.xAxis))
	return reply(p, true, nil)
end

local function onPromptTriggered(prompt: ProximityPrompt, p: Player)
	local difficulty = prompt:GetAttribute("PracticeDifficulty")
	if type(difficulty) ~= "string" or not CollectionService:HasTag(prompt, PRACTICE_PROMPT_TAG) then
		return
	end
	local t = os.clock()
	if (promptAt[p] or -math.huge) + 1 > t then
		return
	end
	promptAt[p] = t
	local okReady, ready = call("PlayerStateService", "IsReady", p)
	if not okReady or ready ~= true then
		return
	end
	QueueService.Leave(p)
	local ok, started, key = call("MatchService", "_StartPractice", p, difficulty, false)
	if ok and started ~= true and type(key) == "string" then
		notify(p, key, nil, "Error")
	end
end

-- ---------------------------------------------------------------------
-- 11) INIT / START
-- ---------------------------------------------------------------------
local function onPlayerRemoving(p: Player)
	QueueService.Leave(p)
	if p == crownKing then
		setKing(nil)
	end
	entryOf[p] = nil
	infoOf[p] = nil
	lastInput[p] = nil
	voteWatch[p] = nil
	offSince[p] = nil
	notifyAt[p] = nil
	stateSig[p] = nil
	rangeAt[p] = nil
	promptAt[p] = nil
	rejoinGrace[p] = nil
end

local function onCharacterAdded(p: Player, char: Model)
	-- König mit neuer Figur: Krone wieder aufsetzen (Abgabe prüft der Kronen-Takt)
	if p == crownKing then
		task.defer(function()
			if crownKing == p and p.Character == char then
				call("CharacterService", "SetHeadProp", char, "Crown")
			end
		end)
	end
end

local function onPlayerAdded(p: Player)
	p.CharacterAdded:Connect(function(char)
		onCharacterAdded(p, char)
	end)
end

function QueueService.Init(services: any)
	Services = services
	local pss = Services.PlayerStateService
	if pss then
		pss.Handle("QueueJoin", handleQueueJoin)
		pss.Handle("QueueLeave", handleQueueLeave)
		pss.Handle("FillBots", handleFillBots, { Rate = 1, Per = 3 })
		pss.Handle("CrownJoin", handleCrownJoin)
		pss.Handle("CrownLeave", handleCrownLeave)
		pss.Handle("GoRange", handleGoRange, { Rate = 1, Per = 2 })
		pss.Provide("Queue", stateFor)
	else
		warn("[QueueService] PlayerStateService fehlt – keine Warteschlangen-Anfragen möglich")
	end
end

function QueueService.Start()
	crownIdleSince = now()
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, p)
	end
	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)
	Scheduler.Every("PadScan", Q.PadScanHz or 4, padScan)
	Scheduler.Every("Matcher", Q.MatcherHz or 2, matcherTick)
	task.defer(function()
		loadPads()
		updateCrownBoard()
	end)
end

return QueueService
