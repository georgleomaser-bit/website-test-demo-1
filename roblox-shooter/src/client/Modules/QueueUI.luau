-- =====================================================================
--  CLUTCH CLASH – PLAY-Menü, Warteschlangen-Anzeige, Pad-Schilder (Client/Modules/QueueUI)
--  Besitzer: WP5 (Match-UI). Vertrag: DESIGN.md C7.3 (Fenster "Play"), C7.4 (QueueUI.OpenPlay), B3.2, B3.3.
--
--  - Fenster "Play": Duell 1v1/2v2/3v3/4v4, Mutator des Tages, FFA-Brawl, Krone herausfordern, Training (Teleport),
--    Gegen Bots üben (Schwierigkeit wählen). Jeder Eintrag zeigt "N suchen" (State.Queue.Counts).
--    Auswahl = Request("QueueJoin", { Mode, Input }) (Eingabegruppe fürs Matchmaking, B3.1).
--  - Such-Leiste unten Mitte: Modus, "N suchen", "BOT KOMMT IN 6", "Arenen voll …", Knöpfe BOTS JETZT / Abbrechen;
--    Krone: Platz in der Herausforderer-Linie bzw. "Du bist König".
--  - Pad-Schilder: lokalisierte BillboardGui je Pad aus den Pad-Attributen (Mode, NeedA/B, CountA/B, BotAt,
--    Searching, Phase) + halbtransparente Hologramm-Bots auf freien Sitzen, solange ein Bot-Timer läuft.
--  - Bot-Duell-Kabine: Server-Prompts (Tag "CCPracticePrompt") werden hier lokalisiert.
--
--  Stil: docs/STYLE-AKYTEX.md – Modus-Karten als Sekundär-Knöpfe mit farbigem Akzent-Streifen (Pad-Farbe),
--  Such-Leiste als Glas-Pill, Pad-Schilder als dunkle Glas-Tafeln (Titel Michroma, Text Builder Sans).
--
--  Öffentliche API (C7.4): QueueUI.OpenPlay()   (+ QueueUI.Init(ctx), QueueUI.Start())
-- =====================================================================

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local UI = require(script.Parent:WaitForChild("UI"))

local QueueUI = {}

local player = Players.LocalPlayer
local ctx: any = nil

local REFRESH = 0.25 -- Anzeige 4 Hz
local PAD_SCAN_EVERY = 3
local PAD_SCAN_TRIES = 12
local GHOST_POOL = 16
local BILLBOARD_DISTANCE = 140
local PRACTICE_PROMPT_TAG = "CCPracticePrompt"
local DIFFICULTIES = { "Rookie", "Easy", "Normal", "Hard", "Insane" }
local DUEL_MODES = { "Duel1", "Duel2", "Duel3", "Duel4" }

type PadView = {
	Part: BasePart,
	Gui: BillboardGui,
	Title: TextLabel,
	Counts: TextLabel,
	Status: TextLabel,
	Searching: TextLabel,
}

local window: any = nil
local modeButtons: { [string]: any } = {}
local cancelRow: Frame? = nil
local mutatorButton: any = nil
local statusBar: Frame? = nil
local statusTitle: TextLabel? = nil
local statusLine: TextLabel? = nil
local botsNowButton: any = nil
local padViews: { PadView } = {}
local padFolder: Folder? = nil
local ghostPool: { Model } = {}
local ghostFolder: Folder? = nil
local padScanTries = 0
local padScanAt = 0
local accum = 0
local inMatch = false

local function T(key: string, ...: any): string
	return if ctx then ctx.T(key, ...) else key
end

local function pick(t: any): string
	if type(t) ~= "table" then
		return tostring(t or "")
	end
	return ctx.Lang.Pick(ctx.Lang_(), t)
end

local function modesCfg(): any
	return ctx.Config.Modes or {}
end

local function modeName(key: string): string
	local def = modesCfg().Modes and modesCfg().Modes[key]
	return if def then pick(def.Name) else key
end

local function queueState(): any
	local state = ctx.State and ctx.State.Queue
	return if type(state) == "table" then state else {}
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function request(action: string, arg: any?, after: ((any) -> ())?)
	task.spawn(function()
		local result = ctx.Request(action, arg)
		if after then
			after(result)
		end
	end)
end

local function inputKind(): string
	local controls = ctx.Modules and ctx.Modules.Controls
	if controls and type(controls.Input) == "function" then
		local ok, kind = pcall(controls.Input)
		if ok and type(kind) == "string" then
			return kind
		end
	end
	return "KBM"
end

local function joinMode(mode: string)
	request("QueueJoin", { Mode = mode, Input = inputKind() }, function(result)
		if result ~= nil then
			ctx.Windows.Close("Play")
		end
	end)
end

-- ---------------------------------------------------------------------
-- 1) PLAY-FENSTER
-- ---------------------------------------------------------------------
local function searchingText(mode: string): string
	local counts = queueState().Counts
	local n = if type(counts) == "table" then tonumber(counts[mode]) or 0 else 0
	return T("match.searching", n)
end

local function mutatorKey(): string?
	local key = ctx.State and ctx.State.Mutator
	return if type(key) == "string" then key else nil
end

local function refreshWindow()
	if not window then
		return
	end
	for mode, button in pairs(modeButtons) do
		if mode == "Crown" then
			local crown = queueState().Crown
			local king = type(crown) == "table" and crown.King or ""
			button.SetSub(if king ~= "" then T("match.play.kingIs", king) else T("match.play.noKing"))
		elseif mode ~= "Training" then
			button.SetSub(searchingText(mode))
		end
	end
	if mutatorButton then
		local key = mutatorKey()
		local def = key and modesCfg().Mutators and modesCfg().Mutators[key]
		mutatorButton.SetText(if def then pick(def.Name) else modeName("Mutator"))
	end
	local row = cancelRow
	if row then
		local q = queueState()
		local crown = q.Crown
		row.Visible = q.Mode ~= nil or (type(crown) == "table" and (tonumber(crown.Line) or 0) > 0)
	end
end

-- Farbiger Akzent-Streifen links im Knopf (Pad-/Modus-Farbe nur als Akzent, AKYTEX)
local function accentStrip(button: any, color: Color3)
	local btn = button.Button
	UI.Create("Frame", {
		Name = "Accent",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.new(0, 3, 1, -24),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = btn.ZIndex + 2,
		Parent = btn,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
end

local function modeButton(
	parent: Instance,
	order: number,
	text: string,
	sub: string,
	color: Color3,
	onClick: () -> ()
): any
	local button = UI.Button({
		LayoutOrder = order,
		Parent = parent,
		Size = UDim2.fromOffset(132, 78),
		Text = text,
		Sub = sub,
		Variant = "Secondary",
		MaxText = 18,
		SubMax = 13,
	}, onClick)
	accentStrip(button, color)
	return button
end

local function closePlayIfOk(result: any)
	if result ~= nil then
		ctx.Windows.Close("Play")
	end
end

local function buildWindow()
	local theme = UI.Theme
	window = UI.Window(T("match.play.title"), 620, 580, theme.Accent)
	local content = window.Content

	UI.Section(content, T("match.play.duels"), 1, theme.Accent)
	local duels = UI.Grid(content, 2, 132, 78)
	local duelColors = { theme.Up, theme.Accent, theme.Purple, theme.Down } -- Pad-Farben P1–P7 (B3.2)
	for i, mode in ipairs(DUEL_MODES) do
		modeButtons[mode] = modeButton(duels, i, modeName(mode), searchingText(mode), duelColors[i], function()
			joinMode(mode)
		end)
	end

	UI.Section(content, T("match.play.special"), 3, theme.Accent)
	local special = UI.Grid(content, 4, 132, 78)
	mutatorButton = modeButton(special, 1, modeName("Mutator"), searchingText("Mutator"), theme.Warn, function()
		joinMode("Mutator")
	end)
	modeButtons.Mutator = mutatorButton
	modeButtons.FFA = modeButton(special, 2, modeName("FFA"), searchingText("FFA"), theme.Pink, function()
		joinMode("FFA")
	end)
	modeButtons.Crown = modeButton(special, 3, T("match.play.crown"), T("match.play.noKing"), theme.Gold, function()
		request("CrownJoin", nil, closePlayIfOk)
	end)
	modeButtons.Training = modeButton(
		special,
		4,
		T("match.play.training"),
		T("match.play.trainingSub"),
		theme.Cyan,
		function()
			request("GoRange", nil, closePlayIfOk)
		end
	)

	UI.Section(content, T("match.play.practice"), 5, theme.Accent)
	local bots = UI.Grid(content, 6, 104, 52)
	local diffColors = { theme.Up, theme.Up, theme.Accent, theme.Orange, theme.Down }
	for i, diff in ipairs(DIFFICULTIES) do
		local button = UI.Button({
			LayoutOrder = i,
			Parent = bots,
			Size = UDim2.fromOffset(104, 52),
			Text = T("bot.diff." .. diff),
			Variant = "Secondary",
			MaxText = 16,
		}, function()
			request("PracticeStart", diff, closePlayIfOk)
		end)
		accentStrip(button, diffColors[i])
	end

	local row = UI.Row(content, 7, 54)
	UI.Button({
		Parent = row,
		Size = UDim2.fromOffset(260, 48),
		Text = T("match.queue.cancel"),
		Variant = "Danger",
		MaxText = 18,
	}, function()
		request("QueueLeave")
		request("CrownLeave")
	end)
	cancelRow = row
	refreshWindow()

	ctx.Windows.Register("Play", function()
		refreshWindow()
		UI.OpenWindow(window)
	end, function()
		UI.CloseWindow(window)
	end)
end

function QueueUI.OpenPlay()
	if inMatch then
		return
	end
	ctx.Windows.Open("Play")
end

-- ---------------------------------------------------------------------
-- 2) SUCH-LEISTE (unten Mitte)
-- ---------------------------------------------------------------------
local function buildStatusBar()
	local theme = UI.Theme
	-- Glas-Pill unten Mitte: Modus + "N suchen · BOT KOMMT IN 6", rechts BOTS JETZT (Primär) und ✕ (Ghost)
	local bar = UI.Create("Frame", {
		Name = "QueueStatus",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.fromOffset(520, 68),
		BackgroundColor3 = theme.Surface,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 12,
		Parent = ctx.Gui,
	}, { UI.Corner(16), UI.Stroke(nil, 1) })
	-- Akzent-Punkt = "Suche läuft"
	UI.Create("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0, 22),
		Size = UDim2.fromOffset(8, 8),
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		ZIndex = 13,
		Parent = bar,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	statusTitle = UI.Label({
		Position = UDim2.fromOffset(32, 8),
		Size = UDim2.new(1, -236, 0, 28),
		Text = "",
		Font = UI.Fonts.Main,
		MaxText = 20,
		TextColor3 = theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 13,
		Parent = bar,
	})
	statusLine = UI.Label({
		Position = UDim2.fromOffset(32, 38),
		Size = UDim2.new(1, -236, 0, 20),
		Text = "",
		Font = UI.Fonts.Main,
		MaxText = 15,
		TextColor3 = theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 13,
		Parent = bar,
	})
	botsNowButton = UI.Button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -64, 0.5, 0),
		Size = UDim2.fromOffset(140, 46),
		Text = T("match.queue.botsNow"),
		Variant = "Primary",
		MaxText = 16,
		ZIndex = 13,
		Parent = bar,
	}, function()
		request("FillBots")
	end)
	UI.Button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(46, 46),
		Text = "✕",
		Variant = "Ghost",
		MaxText = 18,
		ZIndex = 13,
		Parent = bar,
	}, function()
		local q = queueState()
		local crown = q.Crown
		if q.Mode then
			request("QueueLeave")
		elseif type(crown) == "table" and (crown.IsKing or (tonumber(crown.Line) or 0) > 0) then
			request("CrownLeave")
		end
	end)
	statusBar = bar
end

local function setText(label: TextLabel?, text: string)
	if label and label.Text ~= text then
		label.Text = text
	end
end

local function refreshStatus()
	local bar = statusBar
	if not bar then
		return
	end
	local q = queueState()
	local crown = q.Crown
	local line = if type(crown) == "table" then tonumber(crown.Line) or 0 else 0
	local isKing = type(crown) == "table" and crown.IsKing == true
	local visible = not inMatch and (q.Mode ~= nil or line > 0 or isKing)
	if bar.Visible ~= visible then
		bar.Visible = visible
	end
	if not visible then
		return
	end
	local t = serverNow()
	if q.Mode then
		setText(statusTitle, T("match.queue.status", modeName(q.Mode)))
		local parts = { T("match.searching", tonumber(q.Searching) or 0) }
		if q.Held == "Arenas" then
			table.insert(parts, T("match.arenasFull"))
		elseif q.Held == "Bots" then
			table.insert(parts, T("match.botsBusy"))
		elseif type(q.BotAt) == "number" then
			local left = math.max(0, math.ceil(q.BotAt - t))
			table.insert(parts, if left > 0 then T("match.botIn", left) else T("match.queue.forming"))
		end
		setText(statusLine, table.concat(parts, "  ·  "))
		local canFill = type(q.FillAt) == "number" and t >= q.FillAt
		local botSoon = type(q.BotAt) == "number" and q.BotAt - t > 0.5
		if botsNowButton then
			botsNowButton.Frame.Visible = canFill and botSoon and q.Held == nil
		end
	elseif isKing then
		setText(statusTitle, T("match.queue.king"))
		setText(statusLine, T("match.queue.kingStreak", tonumber(crown.Streak) or 0))
		if botsNowButton then
			botsNowButton.Frame.Visible = false
		end
	else
		setText(statusTitle, T("match.queue.crownLine", line, tonumber(crown.LineSize) or line))
		local king = tostring(crown.King or "")
		setText(statusLine, if king ~= "" then T("match.play.kingIs", king) else T("match.play.noKing"))
		if botsNowButton then
			botsNowButton.Frame.Visible = false
		end
	end
end

-- ---------------------------------------------------------------------
-- 3) PAD-SCHILDER + HOLOGRAMM-BOTS
-- ---------------------------------------------------------------------
local function makeLabel(
	parent: Instance,
	y: number,
	h: number,
	maxText: number,
	color: Color3?,
	font: Enum.Font?
): TextLabel
	return UI.Label({
		Position = UDim2.new(0, 10, y, 0),
		Size = UDim2.new(1, -20, h, 0),
		Text = "",
		Font = font or UI.Fonts.Main,
		MaxText = maxText,
		TextColor3 = color or UI.Theme.Text,
		ZIndex = 2,
		Parent = parent,
	})
end

local function addPad(part: BasePart)
	for _, view in ipairs(padViews) do
		if view.Part == part then
			return
		end
	end
	local folder = padFolder
	if not folder then
		return
	end
	local theme = UI.Theme
	local gui = UI.Create("BillboardGui", {
		Name = "Pad" .. tostring(part:GetAttribute("PadId")),
		Adornee = part,
		Size = UDim2.fromOffset(260, 112),
		StudsOffsetWorldSpace = Vector3.new(0, 7, 0),
		MaxDistance = BILLBOARD_DISTANCE,
		LightInfluence = 0,
		AlwaysOnTop = false,
		ResetOnSpawn = false,
		Parent = folder,
	})
	-- dunkle Glas-Tafel mit 1-px-Akzent-Rahmen (Welt-Texte, AKYTEX): Titel Michroma, Zahlen Titillium
	local panel = UI.Create("Frame", {
		Name = "Panel",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = theme.Bg,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Parent = gui,
	}, { UI.Corner(14), UI.Stroke(theme.Accent, 1) })
	table.insert(padViews, {
		Part = part,
		Gui = gui,
		Title = makeLabel(panel, 0.07, 0.24, 20, theme.Text, UI.Fonts.Heading),
		Counts = makeLabel(panel, 0.33, 0.24, 22, theme.Text, UI.Fonts.Number),
		Status = makeLabel(panel, 0.58, 0.2, 16, theme.Accent),
		Searching = makeLabel(panel, 0.79, 0.15, 13, theme.Text2),
	})
end

local function scanPads()
	local found = 0
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("BasePart") and inst:GetAttribute("PadId") ~= nil and inst:GetAttribute("Mode") ~= nil then
			addPad(inst)
			found += 1
		end
	end
	return found
end

local function seatOffsets(mode: string, part: BasePart): { { Side: string, Offset: Vector3 } }
	local list = {}
	local def = modesCfg().Modes and modesCfg().Modes[mode]
	if not def then
		return list
	end
	local top = part.Size.Y / 2 + 2.6
	if def.Ruleset == "Respawn" then
		local n = def.MaxPlayers or 8
		for i = 1, n do
			local angle = (i - 1) / n * math.pi * 2
			table.insert(list, { Side = "A", Offset = Vector3.new(math.cos(angle) * 4, top, math.sin(angle) * 4) })
		end
		return list
	end
	local size = def.TeamSize or 1
	local zs = if size == 1
		then { 0 }
		elseif size == 2 then { -2, 2 }
		elseif size == 3 then { -3.5, 0, 3.5 }
		else { -4.5, -1.5, 1.5, 4.5 }
	for _, side in ipairs({ "A", "B" }) do
		local x = if side == "A" then -5 else 5
		for i = 1, math.min(size, #zs) do
			table.insert(list, { Side = side, Offset = Vector3.new(x, top, zs[i]) })
		end
	end
	return list
end

local function newGhost(): Model
	local model = Instance.new("Model")
	model.Name = "QueueGhost"
	local function part(name: string, shape: Enum.PartType, size: Vector3, offset: Vector3): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Size = size
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = UI.Theme.Accent -- Hologramm in der Akzentfarbe
		p.Transparency = 0.65
		p:SetAttribute("Offset", offset)
		p.Parent = model
		return p
	end
	local body = part("Body", Enum.PartType.Block, Vector3.new(1.8, 2.4, 1), Vector3.new(0, 0, 0))
	part("Head", Enum.PartType.Ball, Vector3.new(1.4, 1.4, 1.4), Vector3.new(0, 1.95, 0))
	part("Base", Enum.PartType.Cylinder, Vector3.new(0.2, 2.6, 2.6), Vector3.new(0, -1.5, 0))
	model.PrimaryPart = body
	return model
end

local function placeGhost(ghost: Model, cf: CFrame)
	for _, p in ipairs(ghost:GetChildren()) do
		if p:IsA("BasePart") then
			local offset = p:GetAttribute("Offset")
			local o = if typeof(offset) == "Vector3" then offset else Vector3.zero
			local rot = if p.Name == "Base" then CFrame.Angles(0, 0, math.rad(90)) else CFrame.identity
			p.CFrame = cf * CFrame.new(o) * rot
		end
	end
end

local function occupied(world: Vector3): boolean
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local d = Vector3.new(root.Position.X - world.X, 0, root.Position.Z - world.Z)
			if d.Magnitude <= 2.4 and math.abs(root.Position.Y - world.Y) < 6 then
				return true
			end
		end
	end
	return false
end

local function refreshPads()
	local t = serverNow()
	local ghostIndex = 0
	local folder = ghostFolder
	for _, view in ipairs(padViews) do
		local part = view.Part
		if part.Parent then
			local mode = tostring(part:GetAttribute("Mode") or "")
			local phase = tostring(part:GetAttribute("Phase") or "Idle")
			local countA = tonumber(part:GetAttribute("CountA")) or 0
			local countB = tonumber(part:GetAttribute("CountB")) or 0
			local needA = tonumber(part:GetAttribute("NeedA")) or 0
			local needB = tonumber(part:GetAttribute("NeedB")) or 0
			local botAt = tonumber(part:GetAttribute("BotAt")) or 0
			local searching = tonumber(part:GetAttribute("Searching")) or 0
			local def = modesCfg().Modes and modesCfg().Modes[mode]
			local ffa = def ~= nil and def.Ruleset == "Respawn"
			setText(view.Title, UI.Upper(modeName(mode)))
			if ffa then
				setText(view.Counts, ("%d / %d"):format(countA, countA + needA))
			else
				setText(
					view.Counts,
					("%d/%d  %s  %d/%d"):format(countA, countA + needA, T("match.pad.vs"), countB, countB + needB)
				)
			end
			local status
			if phase == "Vote" then
				status = T("match.pad.vote")
			elseif phase == "Full" then
				status = T("match.pad.full")
			elseif phase == "Held" then
				status = T("match.arenasFull")
			elseif phase == "Waiting" then
				local left = math.ceil(botAt - t)
				status = if botAt > 0 and left > 0 then T("match.botIn", left) else T("match.queue.forming")
			else
				status = T("match.pad.idle")
			end
			setText(view.Status, status)
			local theme = UI.Theme
			local statusColor = if phase == "Full" or phase == "Vote"
				then theme.Up
				elseif phase == "Held" then theme.Warn
				elseif phase == "Waiting" then theme.Accent
				else theme.Text2
			if view.Status.TextColor3 ~= statusColor then
				view.Status.TextColor3 = statusColor
			end
			setText(view.Searching, T("match.searching", searching))
			-- Hologramm-Bots auf freien Sitzen, solange ein Bot-Timer läuft (nicht während man selbst im Match ist)
			if folder and phase == "Waiting" and botAt > 0 and not inMatch then
				for _, seat in ipairs(seatOffsets(mode, part)) do
					local cf = part.CFrame * CFrame.new(seat.Offset)
					local need = if seat.Side == "A" then needA else needB
					if need > 0 and not occupied(cf.Position) and ghostIndex < GHOST_POOL then
						ghostIndex += 1
						local ghost = ghostPool[ghostIndex]
						if not ghost then
							ghost = newGhost()
							ghostPool[ghostIndex] = ghost
						end
						placeGhost(ghost, CFrame.new(cf.Position))
						if ghost.Parent ~= folder then
							ghost.Parent = folder
						end
					end
				end
			end
		end
	end
	for i = ghostIndex + 1, #ghostPool do
		local ghost = ghostPool[i]
		if ghost.Parent ~= nil then
			ghost.Parent = nil
		end
	end
end

-- ---------------------------------------------------------------------
-- 4) BOT-DUELL-KABINE (Prompts lokalisieren)
-- ---------------------------------------------------------------------
local function localizePrompt(inst: Instance)
	if not inst:IsA("ProximityPrompt") then
		return
	end
	local diff = inst:GetAttribute("PracticeDifficulty")
	if type(diff) ~= "string" then
		return
	end
	inst.ActionText = T("match.practice.action")
	inst.ObjectText = T("match.practice.object", T("bot.diff." .. diff))
end

local function relabelAll()
	for _, inst in ipairs(CollectionService:GetTagged(PRACTICE_PROMPT_TAG)) do
		localizePrompt(inst)
	end
end

-- ---------------------------------------------------------------------
-- 5) INIT / START
-- ---------------------------------------------------------------------
local function step(dt: number)
	accum += dt
	if accum < REFRESH then
		return
	end
	accum = 0
	refreshStatus()
	if #padViews == 0 or padScanTries < PAD_SCAN_TRIES then
		local now = os.clock()
		if now >= padScanAt and padScanTries < PAD_SCAN_TRIES then
			padScanAt = now + PAD_SCAN_EVERY
			padScanTries += 1
			if scanPads() >= 9 then
				padScanTries = PAD_SCAN_TRIES -- alle 9 Pads gefunden
			end
		end
	end
	refreshPads()
end

function QueueUI.Init(context: any)
	ctx = context
	local playerGui = player:WaitForChild("PlayerGui")
	local folder = Instance.new("Folder")
	folder.Name = "ClutchClashPads"
	folder.Parent = playerGui
	padFolder = folder
	local ghosts = Instance.new("Folder")
	ghosts.Name = "ClutchClashQueueGhosts"
	ghosts.Parent = workspace
	ghostFolder = ghosts
	buildWindow()
	buildStatusBar()
end

function QueueUI.Start()
	local hooks = ctx.Hooks
	hooks.On("State", function(_state, changed)
		if type(changed) ~= "table" then
			return
		end
		if changed.Queue or changed.Mutator or changed.Full then
			refreshWindow()
			refreshStatus()
		end
		if changed.Settings then
			relabelAll()
		end
	end)
	hooks.On("Effect:Mutator", function()
		refreshWindow()
	end)
	hooks.On("Settings", relabelAll)
	hooks.On("Match:Found", function()
		inMatch = true
		ctx.Windows.Close("Play")
		refreshStatus()
	end)
	hooks.On("Match:Start", function()
		inMatch = true
		ctx.Windows.Close("Play")
		refreshStatus()
	end)
	hooks.On("Match:Closed", function()
		inMatch = false
		refreshStatus()
	end)
	CollectionService:GetInstanceAddedSignal(PRACTICE_PROMPT_TAG):Connect(localizePrompt)
	relabelAll()
	RunService.Heartbeat:Connect(step)
end

return QueueUI
