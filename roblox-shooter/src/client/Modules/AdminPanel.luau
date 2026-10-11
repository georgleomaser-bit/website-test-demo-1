-- =====================================================================
--  CLUTCH CLASH – Admin-Panel (Client/Modules/AdminPanel)
--  Besitzer: WP7 (Sicherheit, Admin, Live-Balance). Vertrag: DESIGN.md B25.1/B25.3, C7.3/C7.4, docs/ADMIN-WUENSCHE.md.
--  MH-Gerüst (REUSE §1.4): Fenster 720×600, Reiter, gemeinsames Ziel-Feld (me/all/others/Name/Präfix/UserId),
--  Statuszeile, needsConfirm (2. Klick ≤ 5 s), Schieberegler (senden beim Loslassen), Listen, Zuschauen (Taste X).
--  Wird nur gebaut, wenn der Server dich als Admin markiert (Attribut IsAdmin). JEDE Aktion prüft der Server erneut.
--  Öffnen: Taste P (Config.Client.Keys.AdminPanel) oder rechter HUD-Knopf (Order 99). Fenster-Name "Admin".
--  9 Reiter: Spieler · Kräfte · Waffen & Items · Match & Server · Events · Balance · Statistik · Moderation · Debug.
--
--  Öffentliche API (C7.4):
--    AdminPanel.Toggle()
--    AdminPanel.Init(ctx) / AdminPanel.Start()
-- =====================================================================

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local AdminPanel = {}

local player = Players.LocalPlayer
local ctx: any = nil
local UI: any = nil
local Theme: any = nil

local WINDOW_NAME = "Admin"
local CONFIRM_TIME = 5 -- Sekunden: so lange gilt der erste Klick einer gefährlichen Aktion
local MAX_LINES = 80
local STATUS_POP_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TAB_POP_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BLACK = Color3.new(0, 0, 0)

local BOOL_POWERS = {
	{ Name = "AdminAimbot", Key = "admin.pAimbot" },
	{ Name = "AdminSilentAim", Key = "admin.pSilentAim" },
	{ Name = "AdminTriggerbot", Key = "admin.pTriggerbot" },
	{ Name = "AdminESP", Key = "admin.pESP" },
	{ Name = "CanFly", Key = "admin.pFly" },
	{ Name = "AdminNoclip", Key = "admin.pNoclip" },
	{ Name = "AdminGod", Key = "admin.pGod" },
	{ Name = "AdminInvisible", Key = "admin.pInvisible" },
	{ Name = "AdminInfAmmo", Key = "admin.pInfAmmo" },
	{ Name = "AdminNoReload", Key = "admin.pNoReload" },
	{ Name = "AdminOneShot", Key = "admin.pOneShot" },
}

local built = false
local win: any = nil
local spectating: Player? = nil

-- ---------------------------------------------------------------------
-- KLEINE HELFER
-- ---------------------------------------------------------------------
local function T(key: string, ...: any): string
	if ctx and type(ctx.T) == "function" then
		return ctx.T(key, ...)
	end
	return key
end

local function module(name: string): any
	local modules = ctx and ctx.Modules
	return if type(modules) == "table" then modules[name] else nil
end

local function tryModule(name: string, fnName: string, ...: any): boolean
	local m = module(name)
	local fn = if type(m) == "table" then m[fnName] else nil
	if type(fn) ~= "function" then
		return false
	end
	return (pcall(fn, ...))
end

local function sortedKeys(t: any): { string }
	local out: { string } = {}
	if type(t) == "table" then
		for key in pairs(t) do
			if type(key) == "string" then
				table.insert(out, key)
			end
		end
	end
	table.sort(out)
	return out
end

local function weaponDefs(): { any }
	local weapons = ctx and ctx.Config and ctx.Config.Weapons
	local list = weapons and weapons.List
	return if type(list) == "table" then list else {}
end

local function weaponName(def: any): string
	local lang = if ctx and type(ctx.Lang_) == "function" then ctx.Lang_() else "de"
	if type(def) == "table" and type(def.Name) == "table" then
		return tostring(def.Name[lang] or def.Name.de or def.Key)
	end
	return tostring(if type(def) == "table" then def.Key else "?")
end

local function clearChildren(parent: Instance)
	for _, child in ipairs(parent:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIGridLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function fmtTime(t: any): string
	if type(t) ~= "number" or t <= 0 then
		return "-"
	end
	return os.date("%d.%m. %H:%M", math.floor(t)) :: string
end

-- ---------------------------------------------------------------------
-- ZUSCHAUEN (Client, Taste X beendet)
-- ---------------------------------------------------------------------
local function stopSpectate()
	if not spectating then
		return
	end
	spectating = nil
	if not tryModule("Spectate", "Stop") then
		local camera = workspace.CurrentCamera
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if camera and humanoid then
			camera.CameraSubject = humanoid
		end
	end
	if ctx and type(ctx.Toast) == "function" then
		ctx.Toast(T("admin.spectateStop"), "Info")
	end
end

local function spectate(target: Player?)
	if not target or target == player or not target.Character then
		return false
	end
	local character: Model = target.Character
	spectating = target
	if not tryModule("Spectate", "Start", { character }) then
		local camera = workspace.CurrentCamera
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if camera and humanoid then
			camera.CameraSubject = humanoid
		end
	end
	if ctx and type(ctx.Toast) == "function" then
		ctx.Toast(T("admin.spectating", target.DisplayName), "Info")
	end
	return true
end

local function findPlayer(text: string): Player?
	local lower = string.lower(text)
	local id = tonumber(text)
	for _, p in ipairs(Players:GetPlayers()) do
		if (id and p.UserId == id) or string.lower(p.Name) == lower or string.lower(p.DisplayName) == lower then
			return p
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if string.sub(string.lower(p.Name), 1, #lower) == lower then
			return p
		end
	end
	return nil
end

-- ---------------------------------------------------------------------
-- BAUSTEINE (MH-Gerüst)
-- ---------------------------------------------------------------------
local function listFrame(parent: Instance, order: number): Frame
	return UI.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	}, {
		UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }),
	})
end

local function textLine(parent: Instance, text: string, order: number, color: Color3?): TextLabel
	local label = UI.Label({
		Size = UDim2.new(1, 0, 0, 22),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = text,
		TextScaled = false,
		TextSize = 16,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color or Theme.Text,
		LayoutOrder = order,
		Outline = 1.5,
		Parent = parent,
	})
	return label
end

local function showLines(out: Frame, lines: { string })
	clearChildren(out)
	for i, line in ipairs(lines) do
		if i > MAX_LINES then
			textLine(out, ("… +%d"):format(#lines - MAX_LINES), i, Theme.SubText)
			break
		end
		textLine(out, line, i)
	end
end

local function button(parent: Instance, text: string, color: Color3, size: UDim2, onClick: () -> ()): any
	return UI.Button({ Size = size, Text = text, Color = color, MaxText = 16, Parent = parent }, onClick)
end

local function textBox(parent: Instance, placeholder: string, size: UDim2, default: string?): TextBox
	return UI.TextBox({
		Size = size,
		Text = default or "",
		PlaceholderText = placeholder,
		Font = UI.Font,
		Parent = parent,
	})
end

type Slider = { Set: (value: number) -> (), Get: () -> number }

-- Schieberegler: Wert wird beim Loslassen geschickt (spart Anfragen)
local function slider(
	parent: Instance,
	order: number,
	title: string,
	min: number,
	max: number,
	default: number,
	onRelease: (number) -> ()
): Slider
	local row = UI.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	UI.Label({
		Size = UDim2.new(0.24, 0, 1, 0),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 18,
		Outline = 2,
		Parent = row,
	})
	local track: TextButton = UI.Create("TextButton", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.26, 0, 0.5, 0),
		Size = UDim2.new(0.56, 0, 0, 18),
		BackgroundColor3 = Theme.PanelDark,
		AutoButtonColor = false,
		Text = "",
		Parent = row,
	}, { UI.Corner(9), UI.Stroke(BLACK, 3) })
	local fill: Frame = UI.Create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Green,
		Parent = track,
	}, { UI.Corner(9) })
	local knob: Frame = UI.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 2,
		Parent = track,
	}, { UI.Corner(13), UI.Stroke(BLACK, 3) })
	local valueLabel = UI.Label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0.16, 0, 1, 0),
		Text = "",
		MaxText = 20,
		Outline = 2,
		Parent = row,
	})
	local value = default
	local function show()
		local ratio = math.clamp((value - min) / math.max(1, max - min), 0, 1)
		fill.Size = UDim2.fromScale(ratio, 1)
		knob.Position = UDim2.fromScale(ratio, 0.5)
		valueLabel.Text = tostring(value)
	end
	local function setFromX(x: number)
		local width = math.max(1, track.AbsoluteSize.X)
		local ratio = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		value = math.floor(min + ratio * (max - min) + 0.5)
		show()
	end
	local dragging = false
	track.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		local kind = input.UserInputType
		if dragging and (kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local kind = input.UserInputType
		if dragging and (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) then
			dragging = false
			task.spawn(onRelease, value)
		end
	end)
	show()
	return {
		Set = function(newValue: number)
			value = math.clamp(math.floor(newValue + 0.5), min, max)
			show()
		end,
		Get = function(): number
			return value
		end,
	}
end

type Cycler = { Get: () -> string?, Set: (value: string?) -> (), OnChange: ((string?) -> ())? }

-- Knopf, der beim Klicken durch eine Liste schaltet ("Modus: Duel1")
local function cycler(parent: Instance, title: string, options: { string }, size: UDim2, emptyLabel: string?): Cycler
	local list: { string } = table.clone(options)
	if emptyLabel then
		table.insert(list, 1, "")
	end
	local index = 1
	local state: Cycler = {
		Get = function(): string?
			return nil
		end,
		Set = function(_v: string?) end,
		OnChange = nil,
	}
	local btn: any = nil
	local function label(): string
		local value = list[index]
		if value == nil or value == "" then
			return ("%s: %s"):format(title, emptyLabel or "-")
		end
		return ("%s: %s"):format(title, value)
	end
	btn = button(parent, label(), Theme.Purple, size, function()
		if #list == 0 then
			return
		end
		index = (index % #list) + 1
		btn.SetText(label())
		if state.OnChange then
			task.spawn(state.OnChange, state.Get())
		end
	end)
	state.Get = function(): string?
		local value = list[index]
		if value == nil or value == "" then
			return nil
		end
		return value
	end
	state.Set = function(value: string?)
		local found = table.find(list, value or "")
		if found then
			index = found
			btn.SetText(label())
		end
	end
	return state
end

-- =====================================================================
-- AUFBAU
-- =====================================================================
local function build()
	if built then
		return
	end
	built = true
	local Config = ctx.Config or {}
	local remotes = ctx.Remotes or {}

	win = UI.Window(T("admin.title"), 720, 600, Theme.Red)

	-- Kopf: Reiter (2 Reihen) + Ziel-Feld + Statuszeile (scrollen nicht mit)
	local tabBar = UI.Create("Frame", {
		Name = "Tabs",
		Position = UDim2.fromOffset(12, 66),
		Size = UDim2.new(1, -24, 0, 76),
		BackgroundTransparency = 1,
		Parent = win.Panel,
	}, {
		UI.Create("UIGridLayout", {
			CellSize = UDim2.new(0.2, -5, 0, 34),
			CellPadding = UDim2.fromOffset(5, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local topRow = UI.Create("Frame", {
		Name = "TargetRow",
		Position = UDim2.fromOffset(12, 148),
		Size = UDim2.new(1, -24, 0, 34),
		BackgroundTransparency = 1,
		Parent = win.Panel,
	})
	local targetBox = textBox(topRow, T("admin.targetHint"), UDim2.new(0.3, 0, 1, 0), "me")
	local status = UI.Label({
		Position = UDim2.new(0.31, 0, 0, 0),
		Size = UDim2.new(0.69, 0, 1, 0),
		Text = T("admin.ready"),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.SubText,
		MaxText = 17,
		Outline = 2,
		Parent = topRow,
	})
	win.Content.Position = UDim2.fromOffset(12, 190)
	win.Content.Size = UDim2.new(1, -24, 1, -202)

	local statusScale: UIScale = UI.Create("UIScale", { Scale = 1, Parent = status })
	local function setStatus(text: string, color: Color3)
		status.Text = text
		status.TextColor3 = color
		statusScale.Scale = 1.1
		TweenService:Create(statusScale, STATUS_POP_INFO, { Scale = 1 }):Play()
	end

	local function admin(action: string, args: { [string]: any }?): any
		local remote = remotes.Admin
		if not remote or not remote:IsA("RemoteFunction") then
			setStatus(T("core.noAnswer"), Theme.Red)
			return nil
		end
		local ok, result = pcall(function()
			return remote:InvokeServer(action, args or {})
		end)
		if ok and type(result) == "table" then
			local message = tostring(result.Message or "")
			setStatus(
				if result.Ok then T("admin.ok", message) else T("admin.fail", message),
				if result.Ok then Theme.Cash else Theme.Red
			)
			return result
		end
		setStatus(T("core.noAnswer"), Theme.Red)
		return nil
	end

	-- Gefährliche Aktion: erst beim zweiten Klick (innerhalb von CONFIRM_TIME Sekunden) ausführen
	local confirmKey: string? = nil
	local confirmAt = 0
	local function needsConfirm(key: string, label: string): boolean
		local now = os.clock()
		if confirmKey ~= key or now - confirmAt > CONFIRM_TIME then
			confirmKey = key
			confirmAt = now
			setStatus(T("admin.confirm", label), Theme.Orange)
			return true
		end
		confirmKey = nil
		return false
	end

	local function target(): string
		return targetBox.Text
	end

	-- Reiter-Seiten
	local TABS = {
		{ Id = "Players", Key = "admin.tabPlayers", Color = Theme.Blue },
		{ Id = "Powers", Key = "admin.tabPowers", Color = Theme.Green },
		{ Id = "Weapons", Key = "admin.tabWeapons", Color = Theme.Orange },
		{ Id = "Match", Key = "admin.tabMatch", Color = Theme.Purple },
		{ Id = "Events", Key = "admin.tabEvents", Color = Theme.Pink },
		{ Id = "Balance", Key = "admin.tabBalance", Color = Theme.Gold },
		{ Id = "Stats", Key = "admin.tabStats", Color = Theme.Cyan },
		{ Id = "Mod", Key = "admin.tabMod", Color = Theme.Red },
		{ Id = "Debug", Key = "admin.tabDebug", Color = Theme.Gray:Lerp(Theme.Blue, 0.4) },
	}
	local pages: { [string]: Frame } = {}
	local tabButtons: { [string]: any } = {}
	local onTabOpen: { [string]: () -> () } = {}
	local currentTab = "Players"
	local function selectTab(id: string)
		currentTab = id
		for pageId, page in pairs(pages) do
			page.Visible = pageId == id
			local scale = page:FindFirstChildOfClass("UIScale")
			if pageId == id and scale then
				scale.Scale = 0.95
				TweenService:Create(scale, TAB_POP_INFO, { Scale = 1 }):Play()
			end
		end
		for _, tab in ipairs(TABS) do
			local b = tabButtons[tab.Id]
			if b then
				b.SetColor(if tab.Id == id then tab.Color else Theme.Gray)
			end
		end
		win.Content.CanvasPosition = Vector2.zero
		local hook = onTabOpen[id]
		if hook then
			task.spawn(hook)
		end
	end
	for i, tab in ipairs(TABS) do
		pages[tab.Id] = UI.Create("Frame", {
			Name = tab.Id,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = i,
			Visible = false,
			Parent = win.Content,
		}, {
			UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
			UI.Create("UIScale", { Scale = 1 }),
		})
		tabButtons[tab.Id] = UI.Button({
			Size = UDim2.fromScale(1, 1),
			Text = T(tab.Key),
			Color = Theme.Gray,
			LayoutOrder = i,
			MaxText = 15,
			Parent = tabBar,
		}, function()
			selectTab(tab.Id)
		end)
	end

	local FULL = UDim2.new(1, 0, 1, 0)
	local function part(scale: number): UDim2
		return UDim2.new(scale, -6, 1, 0)
	end

	-- =================================================================
	-- REITER SPIELER
	-- =================================================================
	do
		local page = pages.Players
		UI.Section(page, T("admin.secPlayers"), 1)
		local listRow = UI.Row(page, 2, 40)
		local playerList = listFrame(page, 3)
		local function refresh()
			local result = admin("GetPlayers")
			if not result or not result.Ok or type(result.Data) ~= "table" then
				return
			end
			clearChildren(playerList)
			for i, info in ipairs(result.Data) do
				if type(info) == "table" then
					local row = UI.Row(playerList, i, 36)
					local text = T(
						"admin.playerRow",
						tostring(info.DisplayName),
						tostring(info.UserId),
						tonumber(info.Level) or 1,
						tonumber(info.PingMs) or 0,
						tonumber(info.MatchId) or 0,
						tonumber(info.Suspicion) or 0
					)
					UI.Label({
						Size = UDim2.new(0.64, 0, 1, 0),
						Text = (if info.IsAdmin then "🛠️ " else "") .. text,
						TextXAlignment = Enum.TextXAlignment.Left,
						MaxText = 16,
						Outline = 2,
						Parent = row,
					})
					button(row, T("admin.setTarget"), Theme.Blue, UDim2.new(0.17, 0, 1, 0), function()
						targetBox.Text = tostring(info.Name)
						setStatus(T("admin.targetSet", tostring(info.Name)), Theme.Cash)
					end)
					button(row, "👁", Theme.Purple, UDim2.new(0.15, 0, 1, 0), function()
						spectate(findPlayer(tostring(info.Name)))
					end)
				end
			end
		end
		button(listRow, T("admin.refresh"), Theme.Blue, part(0.3), refresh)
		onTabOpen.Players = refresh

		UI.Section(page, T("admin.secActions"), 4)
		local reasonRow = UI.Row(page, 5, 36)
		local reasonBox = textBox(reasonRow, T("admin.reasonHint"), FULL)
		local grid = UI.Grid(page, 6, 160, 40)
		local function act(key: string, color: Color3, fn: () -> ())
			button(grid, T(key), color, UDim2.fromScale(1, 1), fn)
		end
		act("admin.kick", Theme.Red, function()
			if needsConfirm("Kick" .. target(), T("admin.kick")) then
				return
			end
			admin("Kick", { Target = target(), Reason = reasonBox.Text })
		end)
		act("admin.warn", Theme.Orange, function()
			admin("Warn", { Target = target(), Text = reasonBox.Text })
		end)
		act("admin.freeze", Theme.Cyan, function()
			admin("Freeze", { Target = target(), On = true })
		end)
		act("admin.unfreeze", Theme.Blue, function()
			admin("Freeze", { Target = target(), On = false })
		end)
		act("admin.bring", Theme.Purple, function()
			admin("Bring", { Target = target() })
		end)
		act("admin.goto", Theme.Purple, function()
			admin("Goto", { Target = target() })
		end)
		act("admin.pop", Theme.Red, function()
			if needsConfirm("Pop" .. target(), T("admin.pop")) then
				return
			end
			admin("Pop", { Target = target() })
		end)
		act("admin.heal", Theme.Green, function()
			admin("Heal", { Target = target() })
		end)
		act("admin.spectate", Theme.Gray, function()
			local p = findPlayer(target())
			if not spectate(p) then
				setStatus(T("admin.noTarget"), Theme.Red)
			end
		end)

		UI.Section(page, T("admin.secBan"), 7)
		local banGrid = UI.Grid(page, 8, 120, 40)
		local idRow = UI.Row(page, 9, 40)
		local userIdBox = textBox(idRow, T("admin.userIdHint"), part(0.28))
		local out: Frame
		local function banArgs(duration: string): { [string]: any }
			local id = tonumber(userIdBox.Text)
			if id then
				return { UserId = id, Duration = duration, Reason = reasonBox.Text }
			end
			return { Target = target(), Duration = duration, Reason = reasonBox.Text }
		end
		for _, duration in ipairs({ "1h", "1d", "7d", "30d", "perm" }) do
			button(banGrid, T("admin.banFor", duration), Theme.Red, UDim2.fromScale(1, 1), function()
				local label = T("admin.banFor", duration)
				if needsConfirm("Ban" .. duration .. target() .. userIdBox.Text, label) then
					return
				end
				admin("Ban", banArgs(duration))
			end)
		end
		button(idRow, T("admin.unban"), Theme.Green, part(0.24), function()
			if needsConfirm("Unban" .. userIdBox.Text, T("admin.unban")) then
				return
			end
			admin("Unban", { UserId = tonumber(userIdBox.Text) })
		end)
		button(idRow, T("admin.banListBtn"), Theme.Blue, part(0.24), function()
			local result = admin("BanList")
			if result and result.Ok and type(result.Data) == "table" then
				local lines: { string } = {}
				for _, e in ipairs(result.Data) do
					if type(e) == "table" then
						table.insert(
							lines,
							T(
								"admin.banLine",
								tostring(e.Name),
								tostring(e.UserId),
								fmtTime(e.T),
								tostring(e.Duration),
								tostring(e.Reason),
								if e.Active then "" else " ✔"
							)
						)
					end
				end
				showLines(out, lines)
			end
		end)
		button(idRow, T("admin.banHistoryBtn"), Theme.Blue, part(0.24), function()
			local result = admin("BanHistory", { UserId = tonumber(userIdBox.Text) })
			if result and result.Ok and type(result.Data) == "table" then
				local lines: { string } = {}
				for _, e in ipairs(result.Data) do
					if type(e) == "table" then
						table.insert(
							lines,
							("%s · %s · %ss · %s"):format(
								if e.Ban then "BAN" else "UNBAN",
								tostring(e.StartTime),
								tostring(e.Duration),
								tostring(e.DisplayReason)
							)
						)
					end
				end
				showLines(out, lines)
			end
		end)

		UI.Section(page, T("admin.secGive"), 10)
		local giveRow = UI.Row(page, 11, 40)
		local coinsBox = textBox(giveRow, T("admin.coins"), part(0.19))
		local gemsBox = textBox(giveRow, T("admin.gems"), part(0.19))
		local keysBox = textBox(giveRow, T("admin.keys"), part(0.19))
		local shardsBox = textBox(giveRow, T("admin.shards"), part(0.19))
		button(giveRow, T("admin.give"), Theme.Green, part(0.24), function()
			admin("Give", {
				Target = target(),
				Grant = {
					Coins = tonumber(coinsBox.Text),
					Gems = tonumber(gemsBox.Text),
					Keys = tonumber(keysBox.Text),
					Shards = tonumber(shardsBox.Text),
				},
			})
		end)
		local xpRow = UI.Row(page, 12, 40)
		local xpBox = textBox(xpRow, T("admin.amount"), part(0.25))
		button(xpRow, T("admin.giveXp"), Theme.Green, part(0.25), function()
			admin("GiveXp", { Target = target(), Amount = tonumber(xpBox.Text) })
		end)
		local levelBox = textBox(xpRow, T("admin.level"), part(0.25))
		button(xpRow, T("admin.setLevel"), Theme.Orange, part(0.25), function()
			admin("SetLevel", { Target = target(), Level = tonumber(levelBox.Text) })
		end)

		UI.Section(page, T("admin.secData"), 13)
		local dataRow = UI.Row(page, 14, 40)
		button(dataRow, T("admin.playerData"), Theme.Blue, part(0.2), function()
			local result = admin("PlayerData", { Target = target() })
			if result and result.Ok and type(result.Data) == "table" then
				local lines: { string } = {}
				for _, key in ipairs(sortedKeys(result.Data)) do
					table.insert(lines, ("%s: %s"):format(key, tostring(result.Data[key])))
				end
				showLines(out, lines)
			end
		end)
		button(dataRow, T("admin.receiptsBtn"), Theme.Blue, part(0.18), function()
			local result = admin("Receipts", { Target = target() })
			if result and result.Ok and type(result.Data) == "table" then
				local lines: { string } = {}
				for _, r in ipairs(result.Data) do
					if type(r) == "table" then
						table.insert(lines, ("%s · %s"):format(tostring(r.Id), fmtTime(r.T)))
					end
				end
				showLines(out, lines)
			end
		end)
		local productBox = textBox(dataRow, T("admin.productHint"), part(0.22))
		button(dataRow, T("admin.regrant"), Theme.Orange, part(0.18), function()
			if needsConfirm("Regrant" .. productBox.Text, T("admin.regrant")) then
				return
			end
			admin("Regrant", { Target = target(), ProductKey = productBox.Text })
		end)
		button(dataRow, T("admin.resetData"), Theme.Red, part(0.22), function()
			if needsConfirm("Reset" .. target(), T("admin.resetData")) then
				return
			end
			admin("ResetData", { Target = target(), Confirm = true })
		end)
		out = listFrame(page, 20)
	end

	-- =================================================================
	-- REITER KRÄFTE (eigene Attribute)
	-- =================================================================
	do
		local page = pages.Powers
		textLine(page, T("admin.powersHint"), 1, Theme.Yellow)
		local grid = UI.Grid(page, 2, 160, 40)
		for i, info in ipairs(BOOL_POWERS) do
			local b: any = nil
			local function refresh()
				local on = player:GetAttribute(info.Name) == true
				b.SetText(("%s: %s"):format(T(info.Key), T(if on then "admin.on" else "admin.off")))
				b.SetColor(if on then Theme.Green else Theme.Gray)
			end
			b = UI.Button(
				{ Size = UDim2.fromScale(1, 1), Text = T(info.Key), MaxText = 15, LayoutOrder = i, Parent = grid },
				function()
					local on = player:GetAttribute(info.Name) == true
					admin("SetPower", { Name = info.Name, Value = not on })
				end
			)
			player:GetAttributeChangedSignal(info.Name):Connect(refresh)
			refresh()
		end
		local powers = Config.Security and Config.Security.Powers or {}
		local speed = powers.Speed or { Min = 16, Max = 150 }
		local jump = powers.Jump or { Min = 7.2, Max = 100 }
		local rapid = powers.RapidFire or { Min = 1, Max = 5 }
		local function sendNumber(name: string, minValue: number)
			return function(value: number)
				admin("SetPower", { Name = name, Value = if value <= minValue then nil else value })
			end
		end
		local speedMin = math.floor(speed.Min)
		local jumpMin = math.floor(jump.Min)
		local rapidMin = math.floor(rapid.Min)
		local speedSlider = slider(
			page,
			3,
			T("admin.pSpeed"),
			speedMin,
			math.floor(speed.Max),
			tonumber(player:GetAttribute("AdminSpeed")) or speedMin,
			sendNumber("AdminSpeed", speedMin)
		)
		local jumpSlider = slider(
			page,
			4,
			T("admin.pJump"),
			jumpMin,
			math.floor(jump.Max),
			tonumber(player:GetAttribute("AdminJump")) or jumpMin,
			sendNumber("AdminJump", jumpMin)
		)
		local rapidSlider = slider(
			page,
			5,
			T("admin.pRapid"),
			rapidMin,
			math.floor(rapid.Max),
			tonumber(player:GetAttribute("AdminRapidFire")) or rapidMin,
			sendNumber("AdminRapidFire", rapidMin)
		)
		player:GetAttributeChangedSignal("AdminSpeed"):Connect(function()
			speedSlider.Set(tonumber(player:GetAttribute("AdminSpeed")) or speedMin)
		end)
		player:GetAttributeChangedSignal("AdminJump"):Connect(function()
			jumpSlider.Set(tonumber(player:GetAttribute("AdminJump")) or jumpMin)
		end)
		player:GetAttributeChangedSignal("AdminRapidFire"):Connect(function()
			rapidSlider.Set(tonumber(player:GetAttribute("AdminRapidFire")) or rapidMin)
		end)
		local toolRow = UI.Row(page, 6, 40)
		button(toolRow, T("admin.flyNow"), Theme.Cyan, part(0.33), function()
			if not tryModule("Fly", "Toggle") then
				setStatus(T("admin.moduleMissing", "Fly"), Theme.Red)
			end
		end)
		button(toolRow, T("admin.photo"), Theme.Pink, part(0.33), function()
			if not tryModule("PhotoMode", "Toggle") then
				setStatus(T("admin.moduleMissing", "PhotoMode"), Theme.Red)
			end
		end)
		button(toolRow, T("admin.debugOverlay"), Theme.Gray, part(0.34), function()
			tryModule("DebugOverlay", "Toggle")
		end)
	end

	-- =================================================================
	-- REITER WAFFEN & ITEMS
	-- =================================================================
	do
		local page = pages.Weapons
		UI.Section(page, T("admin.secAdminWeapons"), 1)
		local adminGrid = UI.Grid(page, 2, 160, 40)
		local normalDefs: { any } = {}
		for _, def in ipairs(weaponDefs()) do
			if type(def) == "table" and def.AdminOnly == true then
				button(adminGrid, "⚡ " .. weaponName(def), Theme.Red, UDim2.fromScale(1, 1), function()
					admin("AdminWeapon", { Id = def.Id })
				end)
			elseif type(def) == "table" and type(def.Key) == "string" then
				table.insert(normalDefs, def)
			end
		end
		UI.Section(page, T("admin.secGiveWeapons"), 3)
		local grid = UI.Grid(page, 4, 130, 40)
		for _, def in ipairs(normalDefs) do
			button(grid, weaponName(def), Theme.Orange, UDim2.fromScale(1, 1), function()
				admin("Give", { Target = target(), Grant = { Weapons = { def.Key } } })
			end)
		end
		local row = UI.Row(page, 5, 40)
		button(row, T("admin.giveAll"), Theme.Green, part(0.3), function()
			if needsConfirm("GiveAll" .. target(), T("admin.giveAll")) then
				return
			end
			admin("GiveAll", { Target = target() })
		end)
		local cosmeticBox = textBox(row, T("admin.cosmeticHint"), part(0.45))
		button(row, T("admin.give"), Theme.Green, part(0.25), function()
			admin("Give", { Target = target(), Grant = { Cosmetics = { cosmeticBox.Text } } })
		end)
	end

	-- =================================================================
	-- REITER MATCH & SERVER
	-- =================================================================
	do
		local page = pages.Match
		local out: Frame
		UI.Section(page, T("admin.secMatches"), 1)
		local listRow = UI.Row(page, 2, 40)
		local matchList = listFrame(page, 3)
		local function refreshMatches()
			local result = admin("Matches")
			if not result or not result.Ok or type(result.Data) ~= "table" then
				return
			end
			clearChildren(matchList)
			if #result.Data == 0 then
				textLine(matchList, T("admin.noMatches"), 1, Theme.SubText)
			end
			for i, m in ipairs(result.Data) do
				if type(m) == "table" then
					local row = UI.Row(matchList, i, 36)
					local score = if type(m.Score) == "table" then table.concat(m.Score, ":") else "-"
					local who = if type(m.Players) == "table" then table.concat(m.Players, ", ") else ""
					UI.Label({
						Size = UDim2.new(0.76, 0, 1, 0),
						Text = ("#%s %s · %s · %s · %s · %s +%d🤖%s"):format(
							tostring(m.MatchId),
							tostring(m.Mode),
							tostring(m.Map),
							tostring(m.Phase),
							score,
							who,
							tonumber(m.Bots) or 0,
							if m.Tainted then " · TAINTED" else ""
						),
						TextXAlignment = Enum.TextXAlignment.Left,
						MaxText = 15,
						Outline = 2,
						Parent = row,
					})
					button(row, T("admin.endMatch"), Theme.Red, UDim2.new(0.22, 0, 1, 0), function()
						if needsConfirm("End" .. tostring(m.MatchId), T("admin.endMatch")) then
							return
						end
						admin("EndMatch", { MatchId = m.MatchId })
						task.delay(0.5, refreshMatches)
					end)
				end
			end
		end
		button(listRow, T("admin.refresh"), Theme.Blue, part(0.3), refreshMatches)
		onTabOpen.Match = refreshMatches

		UI.Section(page, T("admin.secStart"), 4)
		local grid = UI.Grid(page, 5, 210, 40)
		local modes = Config.Modes and Config.Modes.Modes or {}
		local maps = Config.Maps and Config.Maps.Maps or {}
		local moods = Config.Maps and Config.Maps.Moods or {}
		local mutators = Config.Modes and Config.Modes.Mutators or {}
		local difficulties = Config.Bots and Config.Bots.Order or sortedKeys(Config.Bots and Config.Bots.Difficulties)
		local modeList = sortedKeys(modes)
		local modeCycler = cycler(grid, T("admin.mode"), modeList, UDim2.fromScale(1, 1))
		local mapCycler = cycler(grid, T("admin.map"), sortedKeys(maps), UDim2.fromScale(1, 1), T("admin.random"))
		local moodCycler = cycler(grid, T("admin.mood"), sortedKeys(moods), UDim2.fromScale(1, 1), T("admin.random"))
		local mutCycler = cycler(grid, T("admin.mutator"), sortedKeys(mutators), UDim2.fromScale(1, 1), "-")
		local diffCycler = cycler(grid, T("admin.difficulty"), difficulties, UDim2.fromScale(1, 1))
		diffCycler.Set("Normal")
		local botCycler =
			cycler(grid, T("admin.bots"), { "0", "1", "2", "3", "4", "5", "6", "7" }, UDim2.fromScale(1, 1), "auto")
		local startRow = UI.Row(page, 6, 40)
		local idsBox = textBox(startRow, T("admin.userIdsHint"), part(0.65))
		button(startRow, T("admin.startMatch"), Theme.Green, part(0.35), function()
			admin("StartMatch", {
				Mode = modeCycler.Get(),
				Map = mapCycler.Get(),
				Mood = moodCycler.Get(),
				Mutator = mutCycler.Get(),
				UserIds = idsBox.Text,
				BotDifficulty = diffCycler.Get(),
				Bots = tonumber(botCycler.Get() or ""),
			})
			task.delay(1, refreshMatches)
		end)

		UI.Section(page, T("admin.secServer"), 7)
		local serverGrid = UI.Grid(page, 8, 160, 40)
		button(serverGrid, T("admin.spawnBot"), Theme.Orange, UDim2.fromScale(1, 1), function()
			admin("SpawnBot", { Difficulty = diffCycler.Get() })
		end)
		button(serverGrid, T("admin.fillPads"), Theme.Orange, UDim2.fromScale(1, 1), function()
			admin("FillPads")
		end)
		button(serverGrid, T("admin.lock"), Theme.Red, UDim2.fromScale(1, 1), function()
			admin("LockServer", { On = true })
		end)
		button(serverGrid, T("admin.unlock"), Theme.Green, UDim2.fromScale(1, 1), function()
			admin("LockServer", { On = false })
		end)
		local reasonRow = UI.Row(page, 9, 40)
		local reasonBox = textBox(reasonRow, T("admin.reasonHint"), part(0.5))
		button(reasonRow, T("admin.kickAll"), Theme.Red, part(0.25), function()
			if needsConfirm("KickAll", T("admin.kickAll")) then
				return
			end
			admin("KickAll", { Reason = reasonBox.Text })
		end)
		button(reasonRow, T("admin.serverInfo"), Theme.Blue, part(0.25), function()
			local result = admin("ServerInfo")
			if result and result.Ok and type(result.Data) == "table" then
				local d = result.Data
				local lines: { string } = {
					T(
						"admin.infoPlayers",
						tonumber(d.Players) or 0,
						tonumber(d.MaxPlayers) or 0,
						tonumber(d.Bots) or 0
					),
					T("admin.infoLoad", tonumber(d.HeartbeatMs) or 0, tonumber(d.HeartbeatMaxMs) or 0),
					T(
						"admin.infoMisc",
						tonumber(d.Projectiles) or 0,
						tonumber(d.MemoryMb) or 0,
						tonumber(d.Uptime) or 0
					),
					T("admin.infoVersion", tostring(d.Version), tostring(d.JobId), tonumber(d.Balance) or 0),
				}
				if type(d.Slots) == "table" then
					for _, s in ipairs(d.Slots) do
						if type(s) == "table" then
							table.insert(
								lines,
								("  Slot %s: %s %s"):format(
									tostring(s.Slot),
									tostring(s.State),
									tostring(s.MapKey or "")
								)
							)
						end
					end
				end
				if d.Locked then
					table.insert(lines, T("admin.locked"))
				end
				showLines(out, lines)
			end
		end)
		out = listFrame(page, 10)
	end

	-- =================================================================
	-- REITER EVENTS
	-- =================================================================
	do
		local page = pages.Events
		local security = Config.Security or {}
		UI.Section(page, T("admin.secAnnounce"), 1)
		local textRow = UI.Row(page, 2, 40)
		local announceBox = textBox(textRow, T("admin.announceHint", security.AnnounceMax or 200), FULL)
		local announceRow = UI.Row(page, 3, 40)
		button(announceRow, T("admin.announce"), Theme.Blue, part(0.5), function()
			admin("Announce", { Text = announceBox.Text, Global = false })
		end)
		button(announceRow, T("admin.announceGlobal"), Theme.Purple, part(0.5), function()
			if needsConfirm("AnnounceGlobal", T("admin.announceGlobal")) then
				return
			end
			admin("Announce", { Text = announceBox.Text, Global = true })
		end)

		UI.Section(page, T("admin.secAbuse"), 4)
		local minutesSlider = slider(
			page,
			5,
			T("admin.minutes"),
			1,
			security.AdminAbuseMaxMinutes or 60,
			5,
			function() end
		)
		local abuseRow = UI.Row(page, 6, 40)
		local coins2, xp2 = true, true
		local coinsBtn: any = nil
		local xpBtn: any = nil
		local function refreshBoost()
			coinsBtn.SetText(("2x Coins: %s"):format(T(if coins2 then "admin.on" else "admin.off")))
			coinsBtn.SetColor(if coins2 then Theme.Gold else Theme.Gray)
			xpBtn.SetText(("2x XP: %s"):format(T(if xp2 then "admin.on" else "admin.off")))
			xpBtn.SetColor(if xp2 then Theme.Cyan else Theme.Gray)
		end
		coinsBtn = button(abuseRow, "2x Coins", Theme.Gold, part(0.25), function()
			coins2 = not coins2
			refreshBoost()
		end)
		xpBtn = button(abuseRow, "2x XP", Theme.Cyan, part(0.25), function()
			xp2 = not xp2
			refreshBoost()
		end)
		refreshBoost()
		button(abuseRow, T("admin.abuseStartBtn"), Theme.Green, part(0.25), function()
			admin("AdminAbuse", { Minutes = minutesSlider.Get(), Coins2 = coins2, Xp2 = xp2, Global = false })
		end)
		button(abuseRow, T("admin.global"), Theme.Purple, part(0.25), function()
			if needsConfirm("AbuseGlobal", T("admin.abuse")) then
				return
			end
			admin("AdminAbuse", { Minutes = minutesSlider.Get(), Coins2 = coins2, Xp2 = xp2, Global = true })
		end)

		UI.Section(page, T("admin.secMutator"), 7)
		local mutRow = UI.Row(page, 8, 40)
		local mutators = Config.Modes and Config.Modes.Mutators or {}
		local mutCycler = cycler(mutRow, T("admin.mutator"), sortedKeys(mutators), part(0.4), "-")
		button(mutRow, T("admin.setBtn"), Theme.Green, part(0.2), function()
			admin("Mutator", { Key = mutCycler.Get(), Global = false })
		end)
		button(mutRow, T("admin.global"), Theme.Purple, part(0.2), function()
			if needsConfirm("MutatorGlobal", T("admin.mutator")) then
				return
			end
			admin("Mutator", { Key = mutCycler.Get(), Global = true })
		end)
		button(mutRow, T("admin.off"), Theme.Gray, part(0.2), function()
			admin("Mutator", { Key = nil, Global = false })
		end)

		UI.Section(page, T("admin.secFun"), 9)
		local funRow = UI.Row(page, 10, 40)
		button(funRow, T("admin.confettiBtn"), Theme.Pink, part(0.33), function()
			admin("Confetti")
		end)
		local gravity = security.LobbyGravity or { Min = 50, Max = 196.2 }
		local gravitySlider = slider(
			page,
			11,
			T("admin.gravityBtn"),
			math.floor(gravity.Min),
			math.floor(gravity.Max),
			math.floor(gravity.Max),
			function(value: number)
				admin("LobbyGravity", { Value = if value >= math.floor(gravity.Max) then gravity.Max else value })
			end
		)
		button(funRow, T("admin.gravityNormal"), Theme.Blue, part(0.33), function()
			gravitySlider.Set(gravity.Max)
			admin("LobbyGravity", { Value = gravity.Max })
		end)
		local lookRow = UI.Row(page, 12, 40)
		local moods = Config.Maps and Config.Maps.Moods or {}
		local moodCycler = cycler(lookRow, T("admin.mood"), sortedKeys(moods), part(0.6))
		button(lookRow, T("admin.lookBtn"), Theme.Gold, part(0.4), function()
			admin("LobbyLook", { Mood = moodCycler.Get() })
		end)
	end

	-- =================================================================
	-- REITER BALANCE (Live)
	-- =================================================================
	do
		local page = pages.Balance
		local out: Frame
		local balanceData: any = nil
		local headRow = UI.Row(page, 1, 40)
		local infoLabel = UI.Label({
			Size = UDim2.new(0.7, -6, 1, 0),
			Text = T("admin.balanceHint"),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxText = 16,
			Outline = 2,
			LayoutOrder = 2,
			Parent = headRow,
		})
		local keys: { string } = {}
		for _, def in ipairs(weaponDefs()) do
			if type(def) == "table" and type(def.Key) == "string" then
				table.insert(keys, def.Key)
			end
		end
		local fields = sortedKeys(Config.Weapons and Config.Weapons.BalanceFields)
		local pickRow = UI.Row(page, 2, 40)
		local weaponCycler = cycler(pickRow, T("admin.weapon"), keys, part(0.5))
		local fieldCycler = cycler(pickRow, T("admin.field"), fields, part(0.5))
		local currentLabel = textLine(page, "", 3, Theme.Yellow)
		local function showCurrent()
			local weapon, field = weaponCycler.Get(), fieldCycler.Get()
			if not weapon or not field then
				currentLabel.Text = ""
				return
			end
			local bounds = Config.Weapons and Config.Weapons.BalanceFields and Config.Weapons.BalanceFields[field]
			local base: any = "?"
			local now: any = "-"
			if balanceData then
				local d = balanceData.Defaults and balanceData.Defaults[weapon]
				base = if d and d[field] ~= nil then d[field] else "-"
				local o = balanceData.Overrides and balanceData.Overrides[weapon]
				now = if o and o[field] ~= nil then o[field] else base
			end
			currentLabel.Text = T(
				"admin.fieldInfo",
				tostring(base),
				tostring(now),
				tostring(bounds and bounds[1] or "?"),
				tostring(bounds and bounds[2] or "?")
			)
		end
		weaponCycler.OnChange = function()
			showCurrent()
		end
		fieldCycler.OnChange = function()
			showCurrent()
		end
		local function load()
			local result = admin("GetBalance")
			if not result or not result.Ok or type(result.Data) ~= "table" then
				return
			end
			balanceData = result.Data
			infoLabel.Text = T(
				"admin.balanceInfo",
				tonumber(balanceData.Version) or 0,
				if balanceData.Preview then T("admin.previewOn") else ""
			)
			local lines: { string } = {}
			for _, weapon in ipairs(sortedKeys(balanceData.Overrides)) do
				local parts: { string } = {}
				for _, field in ipairs(sortedKeys(balanceData.Overrides[weapon])) do
					table.insert(parts, ("%s=%s"):format(field, tostring(balanceData.Overrides[weapon][field])))
				end
				table.insert(lines, ("%s: %s"):format(weapon, table.concat(parts, ", ")))
			end
			for _, weapon in ipairs(sortedKeys(balanceData.Disabled)) do
				table.insert(lines, T("admin.offLine", weapon))
			end
			if type(balanceData.History) == "table" then
				table.insert(lines, T("admin.history"))
				for _, h in ipairs(balanceData.History) do
					if type(h) == "table" then
						table.insert(
							lines,
							T(
								"admin.historyLine",
								tonumber(h.Version) or 0,
								fmtTime(h.T),
								tostring(h.ByName),
								tonumber(h.Changes) or 0,
								tonumber(h.Off) or 0
							)
						)
					end
				end
			end
			showLines(out, lines)
			showCurrent()
		end
		local loadBtn = button(headRow, T("admin.loadBalance"), Theme.Blue, part(0.3), load)
		loadBtn.Frame.LayoutOrder = 1
		onTabOpen.Balance = load
		local setRow = UI.Row(page, 4, 40)
		local valueBox = textBox(setRow, T("admin.value"), part(0.4))
		button(setRow, T("admin.setField"), Theme.Orange, part(0.6), function()
			admin(
				"SetField",
				{ Weapon = weaponCycler.Get(), Field = fieldCycler.Get(), Value = tonumber(valueBox.Text) }
			)
			load()
		end)
		local actRow = UI.Row(page, 5, 40)
		button(actRow, T("admin.save"), Theme.Green, part(0.28), function()
			if needsConfirm("SaveBalance", T("admin.save")) then
				return
			end
			admin("SaveBalance")
			load()
		end)
		button(actRow, T("admin.resetWeapon"), Theme.Blue, part(0.26), function()
			admin("ResetWeapon", { Weapon = weaponCycler.Get() })
			load()
		end)
		button(actRow, T("admin.kill"), Theme.Red, part(0.23), function()
			local weapon = weaponCycler.Get()
			if needsConfirm("Kill" .. tostring(weapon), T("admin.kill")) then
				return
			end
			admin("SetEnabled", { Weapon = weapon, On = false })
			load()
		end)
		button(actRow, T("admin.enable"), Theme.Green, part(0.23), function()
			admin("SetEnabled", { Weapon = weaponCycler.Get(), On = true })
			load()
		end)
		local revertRow = UI.Row(page, 6, 40)
		local versionBox = textBox(revertRow, T("admin.versionHint"), part(0.4))
		button(revertRow, T("admin.revert"), Theme.Orange, part(0.6), function()
			if needsConfirm("Revert" .. versionBox.Text, T("admin.revert")) then
				return
			end
			admin("Revert", { Version = tonumber(versionBox.Text) })
			load()
		end)
		out = listFrame(page, 7)
		showCurrent()
	end

	-- =================================================================
	-- REITER STATISTIK
	-- =================================================================
	do
		local page = pages.Stats
		local out: Frame
		local row = UI.Row(page, 1, 40)
		local function load(days: number)
			setStatus(T("core.loading"), Theme.SubText)
			local result = admin("GetStats", { Days = days })
			if not result or not result.Ok or type(result.Data) ~= "table" then
				return
			end
			local d = result.Data
			local lines: { string } = {
				T(
					"admin.statsHead",
					tonumber(d.Days) or days,
					math.floor(tonumber(d.Matches) or 0),
					tonumber(d.BotPct) or 0,
					tonumber(d.AvgQueue) or 0
				),
			}
			if type(d.Weapons) == "table" then
				for _, w in ipairs(d.Weapons) do
					if type(w) == "table" then
						table.insert(
							lines,
							T(
								"admin.statsWeapon",
								tostring(w.Key),
								math.floor(tonumber(w.Picks) or 0),
								tonumber(w.PickPct) or 0,
								math.floor(tonumber(w.Pops) or 0),
								tonumber(w.PopsPerMatch) or 0,
								tonumber(w.WinPct) or 0,
								tonumber(w.HeadPct) or 0,
								tonumber(w.AccuracyPct) or 0
							) .. (if w.BuffFirst then "  ⬆ " .. T("admin.buffFirst") else "")
						)
					end
				end
			end
			local function listLine(title: string, list: any)
				if type(list) ~= "table" or #list == 0 then
					return
				end
				local parts: { string } = {}
				for _, e in ipairs(list) do
					if type(e) == "table" then
						table.insert(parts, ("%s %d"):format(tostring(e.Key), tonumber(e.Picks) or 0))
					end
				end
				table.insert(lines, title .. ": " .. table.concat(parts, " · "))
			end
			listLine(T("admin.statsMaps"), d.Maps)
			listLine(T("admin.statsModes"), d.Modes)
			if type(d.Queue) == "table" then
				for _, q in ipairs(d.Queue) do
					if type(q) == "table" then
						table.insert(lines, T("admin.statsQueue", tostring(q.Mode), tonumber(q.Seconds) or 0))
					end
				end
			end
			showLines(out, lines)
		end
		button(row, T("admin.days1"), Theme.Cyan, part(0.5), function()
			load(1)
		end)
		button(row, T("admin.days7"), Theme.Blue, part(0.5), function()
			load(7)
		end)
		out = listFrame(page, 2)
	end

	-- =================================================================
	-- REITER MODERATION
	-- =================================================================
	do
		local page = pages.Mod
		local row = UI.Row(page, 1, 40)
		local list = listFrame(page, 2)
		local mode = "Flags"
		local function load(kind: string)
			mode = kind
			local result = admin(kind)
			if not result or not result.Ok or type(result.Data) ~= "table" then
				return
			end
			clearChildren(list)
			if #result.Data == 0 then
				textLine(list, T("admin.nothing"), 1, Theme.SubText)
			end
			for i, e in ipairs(result.Data) do
				if i > 60 then
					break
				end
				if type(e) == "table" then
					local text
					if kind == "Flags" then
						local reasons = if type(e.Reasons) == "table" then table.concat(e.Reasons, ", ") else ""
						text = T(
							"admin.flagLine",
							tostring(e.Name),
							tostring(e.UserId),
							tonumber(e.Score) or 0,
							reasons,
							fmtTime(e.T)
						)
					else
						text = T(
							"admin.reportLine",
							tostring(e.FromName),
							tostring(e.Name),
							tostring(e.Reason),
							type(e.Snapshot) == "table" and tostring(e.Snapshot.HeadPct) or "?",
							type(e.Snapshot) == "table" and tostring(e.Snapshot.Accuracy) or "?",
							fmtTime(e.T)
						)
					end
					local card = UI.Card({
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						LayoutOrder = i,
						Parent = list,
					})
					UI.Create(
						"UIListLayout",
						{ SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = card }
					)
					UI.Create("UIPadding", {
						PaddingLeft = UDim.new(0, 6),
						PaddingRight = UDim.new(0, 6),
						PaddingTop = UDim.new(0, 4),
						PaddingBottom = UDim.new(0, 4),
						Parent = card,
					})
					textLine(card, text, 1)
					local actions = UI.Row(card, 2, 34)
					local userId = tonumber(e.UserId)
					button(actions, "👁", Theme.Purple, part(0.14), function()
						spectate(if userId then Players:GetPlayerByUserId(userId) else nil)
					end)
					for _, duration in ipairs({ "1d", "7d", "perm" }) do
						button(actions, T("admin.banFor", duration), Theme.Red, part(0.18), function()
							if needsConfirm("ModBan" .. tostring(userId) .. duration, T("admin.banFor", duration)) then
								return
							end
							admin("Ban", { UserId = userId, Duration = duration, Reason = T("admin.modReason") })
						end)
					end
					button(actions, T("admin.dismiss"), Theme.Gray, part(0.32), function()
						admin("DismissFlag", { Id = e.Id })
						load(mode)
					end)
				end
			end
		end
		button(row, T("admin.flagsBtn"), Theme.Red, part(0.5), function()
			load("Flags")
		end)
		button(row, T("admin.reportsBtn"), Theme.Orange, part(0.5), function()
			load("Reports")
		end)
	end

	-- =================================================================
	-- REITER DEBUG
	-- =================================================================
	do
		local page = pages.Debug
		local products: { string } = {}
		local shop = Config.Shop
		if shop and type(shop.Products) == "table" then
			for _, product in ipairs(shop.Products) do
				if type(product) == "table" and type(product.Key) == "string" then
					table.insert(products, product.Key)
				end
			end
		end
		UI.Section(page, T("admin.secShopTest"), 1)
		local buyRow = UI.Row(page, 2, 40)
		local productCycler = cycler(buyRow, T("admin.product"), products, part(0.6))
		button(buyRow, T("admin.simPurchase"), Theme.Green, part(0.4), function()
			admin("SimulatePurchase", { ProductKey = productCycler.Get() })
		end)
		local policyRow = UI.Row(page, 3, 40)
		button(policyRow, T("admin.policyAllowedBtn"), Theme.Green, part(0.34), function()
			admin("SimulatePolicy", { Allowed = true })
		end)
		button(policyRow, T("admin.policyRestrictedBtn"), Theme.Red, part(0.33), function()
			admin("SimulatePolicy", { Allowed = false })
		end)
		button(policyRow, T("admin.policyAutoBtn"), Theme.Gray, part(0.33), function()
			admin("SimulatePolicy", {})
		end)
		UI.Section(page, T("admin.secTools"), 4)
		local toolRow = UI.Row(page, 5, 40)
		button(toolRow, T("admin.skipDay"), Theme.Orange, part(0.5), function()
			admin("SkipDay")
		end)
		button(toolRow, T("admin.unlockAll"), Theme.Purple, part(0.5), function()
			if needsConfirm("UnlockAll", T("admin.unlockAll")) then
				return
			end
			admin("UnlockAll")
		end)
		local flagRow = UI.Row(page, 6, 40)
		local flags = {
			{ Key = "ShowHitboxes", Label = "admin.hitboxes" },
			{ Key = "LogRejects", Label = "admin.rejects" },
			{ Key = "BotPaths", Label = "admin.botPaths" },
		}
		for _, info in ipairs(flags) do
			local b: any = nil
			local function refresh()
				local on = workspace:GetAttribute("Debug" .. info.Key) == true
				b.SetText(("%s: %s"):format(T(info.Label), T(if on then "admin.on" else "admin.off")))
				b.SetColor(if on then Theme.Green else Theme.Gray)
			end
			b = button(flagRow, T(info.Label), Theme.Gray, part(0.333), function()
				local on = workspace:GetAttribute("Debug" .. info.Key) == true
				admin("SetDebug", { [info.Key] = not on })
			end)
			workspace:GetAttributeChangedSignal("Debug" .. info.Key):Connect(refresh)
			refresh()
		end
		local lastRow = UI.Row(page, 7, 40)
		button(lastRow, T("admin.selfTest"), Theme.Blue, part(0.5), function()
			admin("RunSelfTest")
		end)
		button(lastRow, T("admin.debugOverlay"), Theme.Gray, part(0.5), function()
			tryModule("DebugOverlay", "Toggle")
		end)
	end

	selectTab(currentTab)
	-- Beim Öffnen den aktuellen Reiter auffrischen
	win.OnOpen = function()
		local hook = onTabOpen[currentTab]
		if hook then
			task.spawn(hook)
		end
	end
end

-- =====================================================================
-- ÖFFENTLICHE API + LEBENSZYKLUS
-- =====================================================================
local function openWindow()
	if player:GetAttribute("IsAdmin") ~= true then
		return
	end
	build()
	if win and not win.IsOpen then
		UI.OpenWindow(win) -- ruft win.OnOpen selbst auf (aktueller Reiter wird aufgefrischt)
	end
end

local function closeWindow()
	if win and win.IsOpen then
		UI.CloseWindow(win)
	end
end

function AdminPanel.Toggle()
	local windows = ctx and ctx.Windows
	if windows and type(windows.IsOpen) == "function" and type(windows.Open) == "function" then
		if windows.IsOpen(WINDOW_NAME) then
			windows.Close(WINDOW_NAME)
		else
			windows.Open(WINDOW_NAME)
		end
		return
	end
	if win and win.IsOpen then
		closeWindow()
	else
		openWindow()
	end
end

function AdminPanel.Init(context: any)
	ctx = context
	UI = ctx.UI or require(script.Parent:WaitForChild("UI"))
	Theme = UI.Theme
	local windows = ctx.Windows
	if windows and type(windows.Register) == "function" then
		windows.Register(WINDOW_NAME, openWindow, closeWindow)
	end
end

function AdminPanel.Start()
	if player:GetAttribute("IsAdmin") ~= true then
		return
	end
	-- Rechter HUD-Knopf (Order 99)
	local hud = module("Hud")
	if hud and type(hud.AddRightButton) == "function" then
		pcall(hud.AddRightButton, "🛠️", "admin.button", Theme.Red, 99, AdminPanel.Toggle)
	end
	-- Taste P (über Controls, sonst direkt)
	local controls = module("Controls")
	local bound = false
	if controls and type(controls.Bind) == "function" then
		bound = pcall(controls.Bind, "AdminPanel", function(state: string)
			if state == "Begin" then
				AdminPanel.Toggle()
			end
		end)
	end
	local keys = ctx.Config and ctx.Config.Client and ctx.Config.Client.Keys or {}
	local function codeOf(list: any, fallback: Enum.KeyCode): Enum.KeyCode
		if type(list) == "table" and type(list[1]) == "string" then
			local ok, code = pcall(function()
				return (Enum.KeyCode :: any)[list[1]]
			end)
			if ok and typeof(code) == "EnumItem" then
				return code :: any
			end
		end
		return fallback
	end
	local panelKey = codeOf(keys.AdminPanel, Enum.KeyCode.P)
	local spectateKey = codeOf(keys.Spectate, Enum.KeyCode.X)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if not bound and input.KeyCode == panelKey then
			AdminPanel.Toggle()
		elseif input.KeyCode == spectateKey and spectating then
			stopSpectate()
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		if p == spectating then
			stopSpectate()
		end
	end)
end

return AdminPanel
