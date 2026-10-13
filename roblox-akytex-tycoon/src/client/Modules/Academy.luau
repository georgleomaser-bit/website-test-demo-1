-- =====================================================================
--  AKYTEX TYCOON – Akademie: Lektionen, Lizenz & Prüfungen, Know-how, Ruf (Client/Modules/Academy)
--  Besitzer: WP9 (Fortschritt, Tutorial, Sozial, Bestenlisten). Vertrag: DESIGN.md §B9.1–§B9.4 (Trader-XP, Lizenzen +
--  Prüfungen, Know-how, Ruf), Akademie (16 Lektionen à 3–5 Karten + 2–3 Fragen, Quiz serverseitig geprüft), §B2
--  (Tutorial-Lektion 1), §0.5 (Tiko/Akademie = Lernen mit Spielgeld, keine Anlageberatung), §C7.3 (Fenster "Academy").
--
--  Öffentliche API:  Academy.OpenLesson(id)   Fenster öffnen und Lektion id sofort starten (Tutorial-Schritt 13)
--  Zusätzlich: Academy.Init(ctx), Academy.Start(), Academy.Refresh()
--  Anfragen: ProgLesson { Id, Answers }, ProgExam { Licence }, ProgKnowHow { Node }, ProgKnowHowReset {}.  State: "Prog".
--  Die richtigen Antworten kennt nur der Server – der Client zeigt Karten, sammelt Antworten und zeigt das Ergebnis.
-- =====================================================================

local TweenService = game:GetService("TweenService")

local UI = require(script.Parent:WaitForChild("UI"))

local Academy = {}

local Theme = UI.Theme

local WINDOW_W, WINDOW_H = 680, 620
local PLAYER_H = 380
local FADE_IN = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local HALF_STAR = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.501, 0.78),
	NumberSequenceKeypoint.new(1, 0.78),
})

local ctx: any = nil
local window: any = nil
local segmented: any = nil
local tab = "lessons"
local pages: { [string]: Frame } = {}
local ui: { [string]: any } = {}
local lesson: { [string]: any }? = nil
local busy = false
local pendingLesson: string? = nil

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

local function prog(): { [string]: any }
	local p = ctx.State.Prog
	return if type(p) == "table" then p else {}
end

local function pcfg(): any
	local p = ctx.Config.Progression
	return if type(p) == "table" then p else {}
end

local function sfx(role: string)
	call("Sfx", "Play", role)
end

local function fmt(fnName: string, ...: any): string
	local fn = ctx.Format[fnName]
	if type(fn) ~= "function" then
		return tostring((...))
	end
	local ok, value = pcall(fn, ...)
	return if ok then value else tostring((...))
end

local function licenceDef(idx: number): any
	local list = pcfg().Licences
	return if type(list) == "table" then list[idx] else nil
end

local function licenceName(idx: number): string
	local def = licenceDef(idx)
	if type(def) == "table" and type(def.Name) == "table" then
		return ctx.Lang.Pick(lang(), def.Name)
	end
	return tostring(idx)
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	props.Parent = parent
	if props.TextXAlignment == nil then
		props.TextXAlignment = Enum.TextXAlignment.Left
	end
	return UI.Label(props)
end

local function paragraph(parent: Instance, order: number, height: number, value: string, color: Color3?): TextLabel
	return text(parent, {
		Size = UDim2.new(1, 0, 0, height),
		LayoutOrder = order,
		Text = value,
		Face = "Body",
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = color or Theme.Text2,
		MaxText = 14,
	})
end

local function clear(frame: Instance)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function newPage(key: string, order: number): Frame
	local page: Frame = UI.Create("Frame", {
		Name = "Page_" .. key,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Visible = false,
		Parent = window.Content,
	}, { UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }) })
	pages[key] = page
	return page
end

local function showTab(key: string)
	tab = key
	for name, page in pairs(pages) do
		page.Visible = name == key
	end
end

-- Lektion des Tages: deterministisch je UTC-Tag (für alle gleich)
local function lessonOfDay(): string?
	local list = pcfg().Academy and pcfg().Academy.Lessons
	if type(list) ~= "table" or #list == 0 then
		return nil
	end
	local ok, day = pcall(ctx.Util.UtcDay)
	local index = (if ok and type(day) == "number" then day else 0) % #list + 1
	return list[index].Id
end

-- ---------------------------------------------------------------------
-- 2) LEKTIONEN: Liste + Spieler (Karten -> Fragen -> Ergebnis)
-- ---------------------------------------------------------------------
local function lessonDef(id: string): any
	local map = pcfg().LessonById
	return if type(map) == "table" then map[id] else nil
end

local renderPlayer: () -> ()
local refreshLessons: () -> ()

local function showPlayer(on: boolean)
	ui.LessonList.Visible = not on
	ui.Player.Visible = on
	if on then
		ui.Player.BackgroundTransparency = 0.4
		TweenService:Create(ui.Player, FADE_IN, { BackgroundTransparency = 0 }):Play()
	end
	window.Content.CanvasPosition = Vector2.zero
end

local function startLesson(id: string)
	local def = lessonDef(id)
	if not def then
		return
	end
	lesson = {
		Id = id,
		Def = def,
		Mode = "cards",
		Card = 1,
		CardAt = os.clock(),
		Q = 1,
		Answers = {},
		Reply = nil,
	}
	showPlayer(true)
	renderPlayer()
	task.delay(num(pcfg().Academy and pcfg().Academy.MinCardSeconds, 2), renderPlayer)
end

local function closeLesson()
	lesson = nil
	showPlayer(false)
	refreshLessons()
end

local function submit()
	local current = lesson
	if not current or busy then
		return
	end
	busy = true
	current.Mode = "sending"
	renderPlayer()
	task.spawn(function()
		local answers = table.clone(current.Answers)
		local reply = ctx.RequestFull("ProgLesson", { Id = current.Id, Answers = answers })
		busy = false
		if lesson ~= current then
			return
		end
		current.Reply = reply
		current.Mode = "result"
		if reply.Ok then
			sfx(if reply.Perfect then "Achievement" else "Profit")
		end
		renderPlayer()
	end)
end

local function nextCard()
	local current = lesson
	if not current then
		return
	end
	local minSeconds = num(pcfg().Academy and pcfg().Academy.MinCardSeconds, 2)
	if current.Mode == "cards" then
		if os.clock() - current.CardAt < minSeconds then
			return
		end
		if current.Card < current.Def.Cards then
			current.Card += 1
			current.CardAt = os.clock()
			task.delay(minSeconds, renderPlayer)
		else
			current.Mode = "quiz"
			current.Q = 1
		end
		sfx("UIClick")
		renderPlayer()
	elseif current.Mode == "result" then
		closeLesson()
	end
end

local function prevCard()
	local current = lesson
	if not current then
		return
	end
	if current.Mode == "cards" then
		if current.Card > 1 then
			current.Card -= 1
			current.CardAt = os.clock() - 60 -- schon gelesen: sofort weiter erlaubt
		else
			closeLesson()
			return
		end
	elseif current.Mode == "quiz" then
		if current.Q > 1 then
			current.Q -= 1
			current.Answers[current.Q] = nil
		else
			current.Mode = "cards"
			current.Card = current.Def.Cards
			current.CardAt = os.clock() - 60
		end
	elseif current.Mode == "result" then
		startLesson(current.Id)
		return
	end
	renderPlayer()
end

local function answer(option: number)
	local current = lesson
	if not current or current.Mode ~= "quiz" then
		return
	end
	current.Answers[current.Q] = option
	sfx("UIClick")
	if current.Q < #current.Def.Quiz then
		current.Q += 1
		renderPlayer()
	else
		submit()
	end
end

local function buildLessonPage(page: Frame)
	ui.LessonList = UI.Create("Frame", {
		Name = "List",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = page,
	}, { UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }) })
	ui.LessonRows = {}
	local order = 0
	local lastSeries = 0
	for _, def in ipairs(pcfg().Academy and pcfg().Academy.Lessons or {}) do
		if def.Series ~= lastSeries then
			lastSeries = def.Series
			order += 1
			UI.Section(
				ui.LessonList,
				T("prog.lbl.series", def.Series, T("prog.series." .. def.Series)),
				order,
				Theme.Cyan
			)
		end
		order += 1
		local card = UI.RowCard(ui.LessonList, order, 56)
		local title = UI.Label({
			Position = UDim2.fromOffset(14, 6),
			Size = UDim2.new(1, -230, 0, 24),
			Text = T("prog.les." .. def.Id .. ".t"),
			Face = "BodyBold",
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxText = 17,
			Parent = card,
		})
		local status = UI.Label({
			Position = UDim2.fromOffset(14, 30),
			Size = UDim2.new(1, -230, 0, 18),
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxText = 13,
			Parent = card,
		})
		local actions = UI.RowActions(card, 200)
		local id = def.Id
		local button = UI.Button({
			Size = UDim2.fromOffset(130, 40),
			Text = T("prog.btn.start"),
			Variant = "Primary",
			Parent = actions,
		}, function()
			startLesson(id)
		end)
		ui.LessonRows[id] = { Title = title, Status = status, Button = button, Def = def }
	end
	order += 1
	ui.Disclaimer = paragraph(ui.LessonList, order, 22, T("prog.lbl.disclaimer"), Theme.Muted)

	-- Spieler
	local player: Frame = UI.Card({
		Name = "Player",
		Size = UDim2.new(1, 0, 0, PLAYER_H),
		LayoutOrder = 2,
		Visible = false,
		Parent = page,
	})
	ui.Player = player
	ui.PTitle = UI.Label({
		Position = UDim2.fromOffset(18, 14),
		Size = UDim2.new(1, -150, 0, 26),
		Text = "",
		Face = "Display",
		TextColor3 = Theme.Cyan,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 18,
		Parent = player,
	})
	ui.PStep = UI.Label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 16),
		Size = UDim2.fromOffset(120, 22),
		Text = "",
		Face = "Mono",
		TextColor3 = Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxText = 14,
		Parent = player,
	})
	ui.PBar = UI.Bar({
		Position = UDim2.fromOffset(18, 48),
		Size = UDim2.new(1, -36, 0, 8),
		Color = Theme.Cyan,
		Parent = player,
	})
	ui.PBody = UI.Label({
		Position = UDim2.fromOffset(18, 70),
		Size = UDim2.new(1, -36, 0, 96),
		Text = "",
		Face = "Body",
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		MaxText = 22,
		Parent = player,
	})
	ui.POptions = UI.Create("Frame", {
		Position = UDim2.fromOffset(18, 172),
		Size = UDim2.new(1, -36, 0, 140),
		BackgroundTransparency = 1,
		Parent = player,
	}, { UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }) })
	ui.POptionButtons = {}
	for i = 1, 4 do
		local index = i
		ui.POptionButtons[i] = UI.Button({
			Size = UDim2.new(1, 0, 0, 40),
			Text = "",
			Variant = "Secondary",
			LayoutOrder = i,
			MaxText = 16,
			Parent = ui.POptions,
		}, function()
			answer(index)
		end)
	end
	local footer = UI.Create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 18, 1, -14),
		Size = UDim2.new(1, -36, 0, 44),
		BackgroundTransparency = 1,
		Parent = player,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
	})
	ui.PBack = UI.Button({
		Size = UDim2.fromOffset(150, 44),
		Text = T("prog.btn.back"),
		Variant = "Secondary",
		LayoutOrder = 1,
		Parent = footer,
	}, prevCard)
	ui.PNext = UI.Button({
		Size = UDim2.fromOffset(170, 44),
		Text = T("prog.btn.next"),
		Variant = "Primary",
		LayoutOrder = 2,
		Parent = footer,
	}, nextCard)
end

renderPlayer = function()
	local current = lesson
	if not window or not current or not ui.Player then
		return
	end
	local def = current.Def
	local id = current.Id
	ui.PTitle.Text = T("prog.les." .. id .. ".t")
	local totalSteps = def.Cards + #def.Quiz
	local minSeconds = num(pcfg().Academy and pcfg().Academy.MinCardSeconds, 2)
	for _, button in ipairs(ui.POptionButtons) do
		button.Frame.Visible = false
	end
	if current.Mode == "cards" then
		ui.PStep.Text = T("prog.lbl.card", current.Card, def.Cards)
		ui.PBody.Text = T("prog.les." .. id .. ".c" .. current.Card)
		ui.PBody.TextColor3 = Theme.Text
		UI.SetBar(ui.PBar, (current.Card - 1) / totalSteps)
		local ready = os.clock() - current.CardAt >= minSeconds
		ui.PNext.Frame.Visible = true
		ui.PNext.SetText(T("prog.btn.next"))
		ui.PNext.SetVariant(if ready then "Primary" else "Muted")
		ui.PBack.SetText(T("prog.btn.back"))
		ui.PBack.Frame.Visible = true
	elseif current.Mode == "quiz" or current.Mode == "sending" then
		local q = current.Q
		ui.PStep.Text = T("prog.lbl.question", q, #def.Quiz)
		ui.PBody.Text = T("prog.les." .. id .. ".q" .. q)
		ui.PBody.TextColor3 = Theme.Text
		UI.SetBar(ui.PBar, (def.Cards + q - 1) / totalSteps)
		local options = math.min(def.Quiz[q] or 3, #ui.POptionButtons)
		for i = 1, options do
			local button = ui.POptionButtons[i]
			button.Frame.Visible = true
			button.SetText(T("prog.les." .. id .. ".q" .. q .. ".a" .. i))
			button.SetVariant(if current.Mode == "sending" then "Muted" else "Secondary")
		end
		ui.PNext.Frame.Visible = false
		ui.PBack.SetText(T("prog.btn.back"))
		ui.PBack.Frame.Visible = current.Mode == "quiz"
	else
		local reply = current.Reply or {}
		UI.SetBar(ui.PBar, 1)
		ui.PStep.Text = ""
		local correct = math.floor(num(reply.Correct, 0))
		local total = math.floor(num(reply.Total, #def.Quiz))
		if reply.Ok then
			ui.PBody.Text = T(
				if reply.Perfect then "prog.lessonPerfect" else "prog.lessonDone",
				correct,
				total,
				math.floor(num(reply.Xp, 0))
			)
			ui.PBody.TextColor3 = if reply.Perfect then Theme.Gold else Theme.Up
		else
			ui.PBody.Text = if type(reply.Message) == "string" and reply.Message ~= ""
				then reply.Message
				else T("prog.lessonFail", correct, total)
			ui.PBody.TextColor3 = Theme.Warn
		end
		ui.PBack.SetText(T("prog.btn.again"))
		ui.PBack.Frame.Visible = true
		ui.PNext.Frame.Visible = true
		ui.PNext.SetText(T("prog.btn.back"))
		ui.PNext.SetVariant("Primary")
	end
end

refreshLessons = function()
	if not ui.LessonRows then
		return
	end
	local done = prog().Lessons
	done = if type(done) == "table" then done else {}
	local daily = lessonOfDay()
	for id, row in pairs(ui.LessonRows) do
		local state = done[id]
		local label = if state == 2
			then T("prog.lbl.lessonPerfect")
			elseif state ~= nil then T("prog.lbl.lessonDone")
			else T("prog.lbl.lessonOpen")
		if id == daily then
			label ..= "  ·  " .. T("prog.lbl.lessonOfDay")
		end
		row.Status.Text = label
		row.Status.TextColor3 = if state == 2 then Theme.Gold elseif state ~= nil then Theme.Up else Theme.Muted
		row.Button.SetText(if state ~= nil then T("prog.btn.again") else T("prog.btn.start"))
		row.Button.SetVariant(if state ~= nil then "Secondary" else "Primary")
	end
end

-- ---------------------------------------------------------------------
-- 3) LIZENZ & PRÜFUNG
-- ---------------------------------------------------------------------
local function buildLicencePage(page: Frame)
	ui.Level = text(page, { Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 1, Face = "Display", MaxText = 20 })
	ui.LevelBar = UI.Bar({ Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 2, Color = Theme.Accent, Parent = page })
	ui.Mult = text(page, { Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 3, MaxText = 14, TextColor3 = Theme.Gold })
	UI.Section(page, T("prog.lbl.current"), 4, Theme.Gold)
	local current = UI.Card({ Size = UDim2.new(1, 0, 0, 112), LayoutOrder = 5, Parent = page })
	UI.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
		PaddingTop = UDim.new(0, 10),
		Parent = current,
	})
	UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = current })
	ui.CurName =
		text(current, { Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 1, Face = "Display", TextColor3 = Theme.Gold })
	ui.CurBasis = text(current, { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 2, Face = "Mono", MaxText = 15 })
	ui.CurKurs = text(current, { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 3, Face = "Mono", MaxText = 15 })
	ui.CurBonus = text(current, { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 4, Face = "Mono", MaxText = 15 })
	ui.Factor = text(page, { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 6, MaxText = 14, TextColor3 = Theme.Text2 })
	UI.Section(page, T("prog.lbl.next"), 7, Theme.Accent)
	ui.NextName = text(page, { Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 8, Face = "Display", MaxText = 18 })
	ui.NextBar = UI.Bar({ Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 9, Color = Theme.Gold, Parent = page })
	UI.Section(page, T("prog.lbl.tasks"), 10, Theme.Cyan)
	ui.Tasks = UI.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 11,
		Parent = page,
	}, { UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }) })
	ui.TaskSig = ""
	local row = UI.Row(page, 12, 46)
	ui.ExamButton = UI.Button({
		Size = UDim2.fromOffset(240, 44),
		Text = T("prog.btn.exam"),
		Variant = "Premium",
		Parent = row,
	}, function()
		if busy then
			return
		end
		local idx = math.floor(num(prog().Licence, 1)) + 1
		busy = true
		task.spawn(function()
			ctx.RequestFull("ProgExam", { Licence = idx })
			busy = false
			Academy.Refresh()
		end)
	end)
end

local function refreshTasks(p: { [string]: any })
	local tasks = type(p.ExamTasks) == "table" and p.ExamTasks or {}
	local parts = { lang(), tostring(p.Licence) }
	for _, task in ipairs(tasks) do
		table.insert(parts, tostring(task.Key) .. tostring(task.Done))
	end
	local sig = table.concat(parts, ",")
	if sig == ui.TaskSig then
		return
	end
	ui.TaskSig = sig
	clear(ui.Tasks)
	if #tasks == 0 then
		paragraph(ui.Tasks, 1, 22, T("prog.lbl.noExam"), Theme.Muted)
		return
	end
	for i, task in ipairs(tasks) do
		local card = UI.RowCard(ui.Tasks, i, 58)
		local key = tostring(task.Key)
		UI.Label({
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.fromOffset(28, 58),
			Text = if task.Done then "✓" else "○",
			TextColor3 = if task.Done then Theme.Up else Theme.Muted,
			MaxText = 22,
			Parent = card,
		})
		UI.Label({
			Position = UDim2.fromOffset(46, 6),
			Size = UDim2.new(1, -60, 0, 24),
			Text = T("prog.exam." .. key),
			Face = "BodyBold",
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if task.Done then Theme.Up else Theme.Text,
			MaxText = 16,
			Parent = card,
		})
		UI.Label({
			Position = UDim2.fromOffset(46, 30),
			Size = UDim2.new(1, -60, 0, 22),
			Text = T("prog.exam." .. key .. ".d"),
			Face = "Body",
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.Text2,
			MaxText = 13,
			Parent = card,
		})
	end
end

local function refreshLicence()
	local p = prog()
	local level = math.floor(num(p.Level, 1))
	local xp = num(p.Xp, 0)
	ui.Level.Text = T("prog.level", level)
	local maxLevel = num(pcfg().MaxLevel, 100)
	if level >= maxLevel then
		UI.SetBar(ui.LevelBar, 1, T("prog.xp", fmt("Int", xp, lang())))
	else
		UI.SetBar(
			ui.LevelBar,
			num(p.LevelProgress, 0),
			T("prog.lbl.xpNext", fmt("Int", xp, lang()), fmt("Int", num(p.NextLevelXp, 0), lang()))
		)
	end
	local mult = num(p.XpMult, 1)
	ui.Mult.Text = if p.PowerHour == true
		then T("prog.powerHour")
		elseif mult > 1 then T("prog.xpMult", (string.gsub(fmt("Mult", mult, lang()), "^x", "")))
		else ""
	local idx = math.floor(num(p.Licence, 1))
	local def = licenceDef(idx) or {}
	ui.CurName.Text = licenceName(idx)
	ui.CurBasis.Text = T("prog.lbl.basis", fmt("Aky", num(def.Basis, 0), lang()))
	ui.CurKurs.Text = T("prog.lbl.bauKurs", fmt("Int", num(def.BauKurs, 0), lang()))
	ui.CurBonus.Text = T("prog.lbl.towerBonus", fmt("Pct", num(def.TowerBonus, 0), lang(), 0, true))
	local factor = type(p.Factor) == "table" and p.Factor or {}
	local function mult2(v: any): string
		return (string.gsub(fmt("Mult", num(v, 1), lang()), "^x", ""))
	end
	ui.Factor.Text = T("prog.lbl.factor", mult2(factor.Total), mult2(factor.Licence), mult2(factor.Ruf))
	local maxIdx = #(pcfg().Licences or {})
	if idx >= maxIdx then
		ui.NextName.Text = T("prog.lbl.max")
		UI.SetBar(ui.NextBar, 1, "")
		ui.ExamButton.Frame.Visible = false
		refreshTasks({ Licence = idx, ExamTasks = {} })
		return
	end
	ui.NextName.Text = licenceName(idx + 1)
	local need = num(p.NextLicenceXp, 0)
	UI.SetBar(
		ui.NextBar,
		if need > 0 then xp / need else 1,
		T("prog.lbl.xpNext", fmt("Int", math.min(xp, need), lang()), fmt("Int", need, lang()))
	)
	refreshTasks(p)
	local tasksDone = true
	for _, task in ipairs(type(p.ExamTasks) == "table" and p.ExamTasks or {}) do
		if not task.Done then
			tasksDone = false
		end
	end
	ui.ExamButton.Frame.Visible = true
	ui.ExamButton.SetVariant(if xp >= need and tasksDone then "Premium" else "Muted")
end

-- ---------------------------------------------------------------------
-- 4) KNOW-HOW (Trading-Werkzeuge, nie Robux)
-- ---------------------------------------------------------------------
local function nodeRequirement(def: any, level: number): number
	if type(def.LevelLicence) == "table" and def.LevelLicence[level + 1] then
		return def.LevelLicence[level + 1]
	end
	return num(def.Licence, 1)
end

local function buildKhPage(page: Frame)
	ui.KhHeader = text(page, { Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 1, Face = "BodyBold", MaxText = 17 })
	ui.KhRows = {}
	for i, def in ipairs(pcfg().KnowHow and pcfg().KnowHow.Nodes or {}) do
		local card = UI.RowCard(page, 10 + i, 72)
		UI.Label({
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -230, 0, 24),
			Text = T("prog.kh." .. def.Key),
			Face = "BodyBold",
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxText = 17,
			Parent = card,
		})
		local desc = UI.Label({
			Position = UDim2.fromOffset(14, 34),
			Size = UDim2.new(1, -230, 0, 30),
			Text = T("prog.kh." .. def.Key .. ".d"),
			Face = "Body",
			TextWrapped = true,
			TextColor3 = Theme.Text2,
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxText = 13,
			Parent = card,
		})
		local actions = UI.RowActions(card, 210)
		local info = UI.Label({
			Size = UDim2.fromOffset(120, 40),
			Text = "",
			Face = "Mono",
			TextColor3 = Theme.Cyan,
			TextXAlignment = Enum.TextXAlignment.Right,
			MaxText = 14,
			LayoutOrder = 1,
			Parent = actions,
		})
		local key = def.Key
		local button = UI.Button({
			Size = UDim2.fromOffset(70, 40),
			Text = "+",
			Variant = "Primary",
			LayoutOrder = 2,
			Parent = actions,
		}, function()
			ctx.Request("ProgKnowHow", { Node = key })
		end)
		ui.KhRows[key] = { Def = def, Info = info, Button = button, Desc = desc }
	end
	local row = UI.Row(page, 60, 44)
	ui.KhReset = text(row, { Size = UDim2.new(1, -200, 1, 0), MaxText = 14, TextColor3 = Theme.Text2 })
	UI.Button(
		{ Size = UDim2.fromOffset(180, 42), Text = T("prog.btn.reset"), Variant = "Secondary", Parent = row },
		function()
			ctx.Request("ProgKnowHowReset", {})
		end
	)
end

local function refreshKh()
	local p = prog()
	local free = math.floor(num(p.KH, 0))
	ui.KhHeader.Text = T("prog.lbl.kh", free, math.floor(num(p.KHTotal, 0)))
	local levels = type(p.KnowHow) == "table" and p.KnowHow or {}
	local licence = math.floor(num(p.Licence, 1))
	for key, row in pairs(ui.KhRows) do
		local def = row.Def
		local level = math.floor(num(levels[key], 0))
		local max = math.floor(num(def.Max, 1))
		local cost = math.floor(num(def.Cost, 1))
		local need = nodeRequirement(def, level)
		if level >= max then
			row.Info.Text = T("prog.lbl.levelFree", level, max)
			row.Button.SetVariant("Muted")
		elseif licence < need then
			row.Info.Text = T("prog.lbl.levelFree", level, max)
			row.Desc.Text = T("prog.khLocked", licenceName(need))
			row.Button.SetVariant("Muted")
		else
			row.Info.Text = T("prog.lbl.levelFree", level, max) .. "\n" .. T("prog.lbl.cost", cost)
			row.Desc.Text = T("prog.kh." .. key .. ".d")
			row.Button.SetVariant(if free >= cost then "Primary" else "Muted")
		end
	end
	ui.KhReset.Text = if p.KHResetFree then T("prog.lbl.khResetFree") else T("prog.lbl.khResetUsed")
end

-- ---------------------------------------------------------------------
-- 5) RUF (5 Sterne mit Halben = Stufe 0–10)
-- ---------------------------------------------------------------------
local function buildRufPage(page: Frame)
	local starsRow = UI.Row(page, 1, 56)
	ui.Stars = {}
	for i = 1, 5 do
		local star = UI.Label({
			Size = UDim2.fromOffset(48, 48),
			Text = "★",
			TextColor3 = Theme.Gold,
			MaxText = 44,
			LayoutOrder = i,
			Parent = starsRow,
		})
		ui.Stars[i] = { Label = star, Gradient = UI.Create("UIGradient", { Parent = star }) }
	end
	ui.RufLevel = text(starsRow, {
		Size = UDim2.fromOffset(160, 48),
		LayoutOrder = 6,
		Face = "Display",
		MaxText = 20,
		TextColor3 = Theme.Gold,
	})
	ui.RufPts = text(page, { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 2, Face = "Mono", MaxText = 15 })
	ui.RufToday = text(page, { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 3, Face = "Mono", MaxText = 15 })
	ui.RufFloor = text(page, { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 4, MaxText = 14, TextColor3 = Theme.Text2 })
	ui.RufFactor = text(page, { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 5, MaxText = 14, TextColor3 = Theme.Up })
	UI.Divider(page, 6)
	paragraph(page, 7, 40, T("prog.ruf.info"))
	paragraph(page, 8, 40, T("prog.ruf.decay"))
end

local function refreshRuf()
	local p = prog()
	local level = math.clamp(math.floor(num(p.Ruf, 0)), 0, 10)
	for i, star in ipairs(ui.Stars) do
		local full = level >= i * 2
		local half = not full and level >= i * 2 - 1
		star.Gradient.Enabled = half
		star.Gradient.Transparency = HALF_STAR
		star.Label.TextTransparency = if full or half then 0 else 0.78
	end
	ui.RufLevel.Text = T("prog.lbl.rufLevel", level)
	ui.RufPts.Text = T("prog.lbl.rufPts", math.floor(num(p.RufPts, 0)), math.floor(num(p.RufNext, 0)))
	local cap = num(pcfg().Ruf and pcfg().Ruf.DailyCap, 20)
	ui.RufToday.Text = T("prog.lbl.rufToday", math.floor(num(p.RufToday, 0)), cap)
	local floorLevel = 0
	local licence = math.floor(num(p.Licence, 1))
	for _, entry in ipairs(pcfg().Ruf and pcfg().Ruf.Floors or {}) do
		if licence >= num(entry.Licence, math.huge) then
			floorLevel = math.max(floorLevel, num(entry.Level, 0))
		end
	end
	ui.RufFloor.Text = T("prog.lbl.rufFloor", floorLevel)
	local factor = type(p.Factor) == "table" and p.Factor or {}
	ui.RufFactor.Text = T("prog.lbl.rufFactor", (string.gsub(fmt("Mult", num(factor.Ruf, 1), lang()), "^x", "")))
end

-- ---------------------------------------------------------------------
-- 6) FENSTER
-- ---------------------------------------------------------------------
function Academy.Refresh()
	if not window then
		return
	end
	refreshLessons()
	refreshLicence()
	refreshKh()
	refreshRuf()
	if lesson then
		renderPlayer()
	end
end

local function buildWindow()
	window = UI.Window(T("prog.win.academy"), WINDOW_W, WINDOW_H, Theme.Cyan)
	segmented = UI.Segmented(window.Content, {
		{ Key = "lessons", Text = T("prog.tab.lessons") },
		{ Key = "licence", Text = T("prog.tab.licence") },
		{ Key = "kh", Text = T("prog.tab.kh") },
		{ Key = "ruf", Text = T("prog.tab.ruf") },
	}, function(key: string)
		showTab(key)
		Academy.Refresh()
	end)
	segmented.Frame.LayoutOrder = 0
	buildLessonPage(newPage("lessons", 1))
	buildLicencePage(newPage("licence", 2))
	buildKhPage(newPage("kh", 3))
	buildRufPage(newPage("ruf", 4))
	showTab(tab)
end

local function openWindow()
	if not window then
		buildWindow()
	end
	segmented.Set(tab, true)
	showTab(tab)
	UI.OpenWindow(window)
	local wanted = pendingLesson
	pendingLesson = nil
	if wanted then
		startLesson(wanted)
	elseif not lesson then
		showPlayer(false)
	end
	Academy.Refresh()
end

local function closeWindow()
	if window and window.IsOpen then
		UI.CloseWindow(window)
	end
end

function Academy.OpenLesson(id: string)
	if type(id) ~= "string" or not lessonDef(id) then
		return
	end
	tab = "lessons"
	pendingLesson = id
	if window and window.IsOpen then
		segmented.Set(tab, true)
		showTab(tab)
		pendingLesson = nil
		startLesson(id)
		return
	end
	ctx.Windows.Open("Academy")
end

function Academy.Init(context: any)
	ctx = context
	ctx.Windows.Register("Academy", openWindow, closeWindow)
end

function Academy.Start()
	ctx.Hooks.On("State", function(_state: any, changed: any)
		if type(changed) == "table" and changed.Prog and window and window.IsOpen then
			Academy.Refresh()
		end
	end)
	ctx.Hooks.On("Settings", function()
		if window then
			ui.TaskSig = ""
		end
	end)
end

return Academy
