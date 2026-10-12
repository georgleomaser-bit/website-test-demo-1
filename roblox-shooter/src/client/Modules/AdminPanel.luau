-- =====================================================================
--  CLUTCH CLASH – Admin-Panel (Client/Modules/AdminPanel)
--  Besitzer: WP7 (Sicherheit, Admin, Live-Balance). Vertrag: DESIGN.md B25.1/B25.3, C7.3/C7.4, docs/ADMIN-WUENSCHE.md.
--  MH-Gerüst (REUSE §1.4): Fenster 720×600, Reiter, gemeinsames Ziel-Feld (me/all/others/Name/Präfix/UserId),
--  Statuszeile, needsConfirm (2. Klick ≤ 5 s), Schieberegler (senden beim Loslassen), Listen, Zuschauen (Taste X).
--  Look (docs/STYLE-AKYTEX.md): schlankes Dashboard – Glas-Fenster, links eine Seitenleiste mit den Reitern
--  (aktiver Reiter = Surface2 + Akzent-Strich), oben Ziel-Feld + Status-Pill, Kennzahl-Kacheln, Karten-Zeilen,
--  Knöpfe nur in den AKYTEX-Varianten (Primary/Secondary/Danger/Success/Ghost/Premium), keine dicken Konturen.
--  Wird nur gebaut, wenn der Server dich als Admin markiert (Attribut IsAdmin). JEDE Aktion prüft der Server erneut.
--  Öffnen: Taste P (Config.Client.Keys.AdminPanel) oder rechter HUD-Knopf (Order 99). Fenster-Name "Admin".
--  9 Reiter: Spieler · Kräfte · Waffen & Items · Match & Server · Events · Balance · Statistik · Moderation · Debug.
--
--  Öffentliche API (C7.4):
--    AdminPanel.Toggle()
--    AdminPanel.Init(ctx) / AdminPanel.Start()
-- =====================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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
local SIDEBAR_W = 160 -- Breite der Reiter-Leiste links
local TOP = 66 -- erste Zeile unter dem Fenster-Kopf (Kopf 58 + 8)
local GAP = 12
local STATUS_POP_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TAB_FADE_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local HOVER_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local WHITE = Color3.new(1, 1, 1)

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
		if
			not child:IsA("UIListLayout")
			and not child:IsA("UIGridLayout")
			and not child:IsA("UIPadding")
			and not child:IsA("UICorner")
			and not child:IsA("UIStroke")
		then
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
-- BAUSTEINE (MH-Gerüst im AKYTEX-Look)
-- ---------------------------------------------------------------------
local function listFrame(parent: Instance, order: number): Frame
	return UI.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	}, {
		UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }),
	})
end

-- Ausgabe-Konsole (Listen, Infos): dunkle Karte, erscheint erst mit Inhalt
local function outputBox(parent: Instance, order: number): Frame
	local box: Frame = UI.Create("Frame", {
		Name = "Output",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Bg2,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Visible = false,
		Parent = parent,
	}, {
		UI.Corner(10),
		UI.Stroke(nil, 1),
		UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3) }),
		UI.Create("UIPadding", {
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 12),
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 10),
		}),
	})
	return box
end

local function textLine(parent: Instance, text: string, order: number, color: Color3?): TextLabel
	local label = UI.Label({
		Size = UDim2.new(1, 0, 0, 20),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = text,
		Font = UI.Fonts.Body,
		TextScaled = false,
		TextSize = 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color or Theme.Text,
		LayoutOrder = order,
		Parent = parent,
	})
	return label
end

local function showLines(out: Frame, lines: { string })
	clearChildren(out)
	for i, line in ipairs(lines) do
		if i > MAX_LINES then
			textLine(out, ("… +%d"):format(#lines - MAX_LINES), i, Theme.Muted)
			break
		end
		textLine(out, line, i, Theme.Text2)
	end
	out.Visible = #lines > 0
end

-- Knopf in einer AKYTEX-Variante: "Primary" | "Secondary" | "Danger" | "Success" | "Ghost" | "Premium"
local function button(parent: Instance, text: string, variant: string, size: UDim2, onClick: () -> ()): any
	return UI.Button(
		{ Size = size, Text = text, Variant = variant, MaxText = 15, Corner = 10, Parent = parent },
		onClick
	)
end

local function textBox(parent: Instance, placeholder: string, size: UDim2, default: string?): TextBox
	return UI.TextBox({
		Size = size,
		Text = default or "",
		PlaceholderText = placeholder,
		Font = UI.Fonts.Body,
		Parent = parent,
	})
end

-- Kleine Pill (voll rund), z. B. "BESITZER" im Fenster-Kopf oder "ADMIN" in einer Spieler-Zeile
local function chip(parent: Instance, text: string, color: Color3, props: { [string]: any }?): Frame
	local frame: Frame = UI.Create("Frame", {
		Name = "Chip",
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = color,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		Parent = parent,
	}, {
		UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		UI.Stroke(color, 1),
		UI.Create("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }),
	})
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0.45
	end
	UI.Create("TextLabel", {
		Name = "Text",
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Font = UI.Fonts.Main,
		TextSize = 12,
		TextColor3 = color:Lerp(WHITE, 0.25),
		Text = text,
		Parent = frame,
	})
	if props then
		for key, value in pairs(props) do
			(frame :: any)[key] = value
		end
	end
	return frame
end

-- Kennzahl-Kachel (Dashboard): kleine Überschrift (Muted) + große Zahl (Strong)
local function statTile(parent: Instance, caption: string, order: number): TextLabel
	local card = UI.Card({ Size = UDim2.fromScale(1, 1), LayoutOrder = order, Parent = parent })
	UI.Label({
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 0, 16),
		Text = caption,
		Font = UI.Fonts.Main,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 13,
		Parent = card,
	})
	return UI.Label({
		Name = "Value",
		Position = UDim2.fromOffset(12, 26),
		Size = UDim2.new(1, -24, 0, 28),
		Text = "–",
		Font = UI.Fonts.Strong,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 24,
		Parent = card,
	})
end

-- Zeilen-Karte (Spieler, Matches): Surface2, Ecke 10, 1-px-Rahmen, Hover = Hover-Fläche
local function rowCard(parent: Instance, order: number, height: number): Frame
	local card: Frame = UI.Create("Frame", {
		Name = "Row",
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = Theme.Surface2,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Parent = parent,
	}, { UI.Corner(10), UI.Stroke(nil, 1) })
	card.MouseEnter:Connect(function()
		TweenService:Create(card, HOVER_INFO, { BackgroundColor3 = Theme.Hover }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(card, HOVER_INFO, { BackgroundColor3 = Theme.Surface2 }):Play()
	end)
	return card
end

-- Knopf-Spalte rechts in einer Zeilen-Karte
local function rowActions(card: Frame, width: number): Frame
	return UI.Create("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.new(0, width, 1, -12),
		BackgroundTransparency = 1,
		Parent = card,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
	})
end

type Slider = { Set: (value: number) -> (), Get: () -> number }

-- Schieberegler: Wert wird beim Loslassen geschickt (spart Anfragen). Schiene Bg2 + Rahmen, Füllung Accent,
-- weißer Knopf; die ganze Zeile ist Greif-Fläche (Handy).
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
		Size = UDim2.new(0.26, 0, 1, 0),
		Text = title,
		Font = UI.Fonts.Main,
		TextColor3 = Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 15,
		Parent = row,
	})
	local track: TextButton = UI.Create("TextButton", {
		Name = "Track",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.28, 0, 0.5, 0),
		Size = UDim2.new(0.56, 0, 0, 32),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Parent = row,
	})
	local rail: Frame = UI.Create("Frame", {
		Name = "Rail",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = Theme.Bg2,
		BorderSizePixel = 0,
		Parent = track,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }), UI.Stroke(nil, 1) })
	local fill: Frame = UI.Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Parent = rail,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local knob: Frame = UI.Create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = track,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }), UI.Stroke(Theme.Accent, 2) })
	local valueLabel = UI.Label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0.14, 0, 1, 0),
		Text = "",
		Font = UI.Fonts.Number,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxText = 20,
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
		local width = math.max(1, rail.AbsoluteSize.X)
		local ratio = math.clamp((x - rail.AbsolutePosition.X) / width, 0, 1)
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
	btn = button(parent, label(), "Secondary", size, function()
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

type NavItem = { Button: TextButton, SetActive: (on: boolean) -> () }

-- Reiter in der Seitenleiste: transparent, Hover-Fläche; aktiv = Surface2 + Akzent-Strich links + heller Text
local function navItem(parent: Instance, text: string, order: number, onClick: () -> ()): NavItem
	local active = false
	local btn: TextButton = UI.Create("TextButton", {
		Name = "Tab",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Theme.Hover,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Parent = parent,
	}, { UI.Corner(10) })
	local bar: Frame = UI.Create("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(3, 18),
		BackgroundColor3 = Theme.Accent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = btn,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local label = UI.Label({
		Name = "Label",
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -20, 1, 0),
		Text = text,
		Font = UI.Fonts.Main,
		TextColor3 = Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 15,
		Parent = btn,
	})
	local function paint(hover: boolean)
		local goal = if active
			then { BackgroundColor3 = Theme.Surface2, BackgroundTransparency = 0 }
			elseif hover then { BackgroundColor3 = Theme.Hover, BackgroundTransparency = 0.2 }
			else { BackgroundColor3 = Theme.Hover, BackgroundTransparency = 1 }
		TweenService:Create(btn, HOVER_INFO, goal):Play()
		TweenService:Create(bar, HOVER_INFO, { BackgroundTransparency = if active then 0 else 1 }):Play()
		label.TextColor3 = if active then Theme.Text else Theme.Text2
	end
	btn.MouseEnter:Connect(function()
		paint(true)
	end)
	btn.MouseLeave:Connect(function()
		paint(false)
	end)
	btn.Activated:Connect(onClick)
	return {
		Button = btn,
		SetActive = function(on: boolean)
			active = on
			paint(false)
		end,
	}
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

	win = UI.Window(T("admin.title"), 720, 600, Theme.Accent)
	local panel: Frame = win.Panel

	-- Fenster-Kopf: Rollen-Chips rechts neben dem Titel (vor dem ✕)
	local header = panel:FindFirstChild("Header")
	if header then
		local chips = UI.Create("Frame", {
			Name = "Chips",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -60, 0, 18),
			Size = UDim2.fromOffset(220, 22),
			BackgroundTransparency = 1,
			Parent = header,
		}, {
			UI.Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 6),
			}),
		})
		chip(chips, T("admin.badgeOwner"), Theme.Warn, { LayoutOrder = 1 })
		local studio = RunService:IsStudio()
		chip(
			chips,
			T(if studio then "admin.badgeStudio" else "admin.badgeLive"),
			if studio then Theme.Accent else Theme.Up,
			{ LayoutOrder = 2 }
		)
	end

	-- Seitenleiste mit den Reitern (scrollt nicht mit)
	local sidebar = UI.Create("Frame", {
		Name = "Sidebar",
		Position = UDim2.fromOffset(GAP, TOP),
		Size = UDim2.new(0, SIDEBAR_W, 1, -(TOP + GAP)),
		BackgroundColor3 = Theme.Bg2,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Parent = panel,
	}, { UI.Corner(12), UI.Stroke(nil, 1) })
	local tabBar = UI.Create("Frame", {
		Name = "Tabs",
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -16, 1, -48),
		BackgroundTransparency = 1,
		Parent = sidebar,
	}, {
		UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }),
	})
	UI.Label({
		Name = "Note",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -10),
		Size = UDim2.new(1, -24, 0, 28),
		Text = T("admin.serverChecks"),
		Font = UI.Fonts.Body,
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 12,
		Parent = sidebar,
	})

	-- Rechte Spalte: Ziel-Feld + Status-Pill, darunter der Inhalt
	local left = GAP + SIDEBAR_W + GAP
	local topRow = UI.Create("Frame", {
		Name = "TargetRow",
		Position = UDim2.fromOffset(left, TOP),
		Size = UDim2.new(1, -(left + GAP), 0, 36),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	local targetBox = textBox(topRow, T("admin.targetHint"), UDim2.new(0.34, 0, 1, 0), "me")
	local statusPill = UI.Create("Frame", {
		Name = "Status",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.66, -8, 1, 0),
		BackgroundColor3 = Theme.Surface2,
		BorderSizePixel = 0,
		Parent = topRow,
	}, { UI.Corner(10), UI.Stroke(nil, 1) })
	local statusDot = UI.Create("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(8, 8),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Parent = statusPill,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local status = UI.Label({
		Name = "Text",
		Position = UDim2.fromOffset(28, 0),
		Size = UDim2.new(1, -38, 1, 0),
		Text = T("admin.ready"),
		Font = UI.Fonts.Body,
		TextColor3 = Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		MaxText = 14,
		Parent = statusPill,
	})
	win.Content.Position = UDim2.fromOffset(left, TOP + 36 + 10)
	win.Content.Size = UDim2.new(1, -(left + 4), 1, -(TOP + 46 + GAP))

	local statusScale: UIScale = UI.Create("UIScale", { Scale = 1, Parent = statusPill })
	local function setStatus(text: string, color: Color3)
		status.Text = text
		status.TextColor3 = if color == Theme.Text2 then Theme.Text2 else Theme.Text
		statusDot.BackgroundColor3 = color
		statusScale.Scale = 1.03
		TweenService:Create(statusScale, STATUS_POP_INFO, { Scale = 1 }):Play()
	end

	local function admin(action: string, args: { [string]: any }?): any
		local remote = remotes.Admin
		if not remote or not remote:IsA("RemoteFunction") then
			setStatus(T("core.noAnswer"), Theme.Down)
			return nil
		end
		local ok, result = pcall(function()
			return remote:InvokeServer(action, args or {})
		end)
		if ok and type(result) == "table" then
			local message = tostring(result.Message or "")
			setStatus(
				if result.Ok then T("admin.ok", message) else T("admin.fail", message),
				if result.Ok then Theme.Up else Theme.Down
			)
			return result
		end
		setStatus(T("core.noAnswer"), Theme.Down)
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
			setStatus(T("admin.confirm", label), Theme.Warn)
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
		{ Id = "Players", Key = "admin.tabPlayers" },
		{ Id = "Powers", Key = "admin.tabPowers" },
		{ Id = "Weapons", Key = "admin.tabWeapons" },
		{ Id = "Match", Key = "admin.tabMatch" },
		{ Id = "Events", Key = "admin.tabEvents" },
		{ Id = "Balance", Key = "admin.tabBalance" },
		{ Id = "Stats", Key = "admin.tabStats" },
		{ Id = "Mod", Key = "admin.tabMod" },
		{ Id = "Debug", Key = "admin.tabDebug" },
	}
	local pages: { [string]: Frame } = {}
	local tabButtons: { [string]: NavItem } = {}
	local onTabOpen: { [string]: () -> () } = {}
	local currentTab = "Players"
	local function selectTab(id: string)
		currentTab = id
		for pageId, page in pairs(pages) do
			page.Visible = pageId == id
			local scale = page:FindFirstChildOfClass("UIScale")
			if pageId == id and scale then
				scale.Scale = 0.98
				TweenService:Create(scale, TAB_FADE_INFO, { Scale = 1 }):Play()
			end
		end
		for _, tab in ipairs(TABS) do
			local b = tabButtons[tab.Id]
			if b then
				b.SetActive(tab.Id == id)
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
		tabButtons[tab.Id] = navItem(tabBar, T(tab.Key), i, function()
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
		-- Kennzahlen (Dashboard-Kacheln) aus derselben GetPlayers-Antwort
		local tiles = UI.Create("Frame", {
			Name = "Tiles",
			Size = UDim2.new(1, 0, 0, 64),
			BackgroundTransparency = 1,
			LayoutOrder = 0,
			Parent = page,
		}, {
			UI.Create("UIGridLayout", {
				CellSize = UDim2.new(0.25, -8, 1, 0),
				CellPadding = UDim2.fromOffset(10, 0),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local kpiPlayers = statTile(tiles, T("admin.kpiPlayers"), 1)
		local kpiPing = statTile(tiles, T("admin.kpiPing"), 2)
		local kpiMatch = statTile(tiles, T("admin.kpiInMatch"), 3)
		local kpiSus = statTile(tiles, T("admin.kpiSuspicion"), 4)

		UI.Section(page, T("admin.secPlayers"), 1)
		local listRow = UI.Row(page, 2, 40)
		local playerList = listFrame(page, 3)
		local function refresh()
			local result = admin("GetPlayers")
			if not result or not result.Ok or type(result.Data) ~= "table" then
				return
			end
			clearChildren(playerList)
			local count, pingSum, inMatch, maxSus = 0, 0, 0, 0
			for i, info in ipairs(result.Data) do
				if type(info) == "table" then
					count += 1
					pingSum += tonumber(info.PingMs) or 0
					if (tonumber(info.MatchId) or 0) > 0 then
						inMatch += 1
					end
					local sus = tonumber(info.Suspicion) or 0
					maxSus = math.max(maxSus, sus)
					local card = rowCard(playerList, i, 50)
					local nameRow = UI.Create("Frame", {
						Position = UDim2.fromOffset(14, 6),
						Size = UDim2.new(1, -220, 0, 20),
						BackgroundTransparency = 1,
						Parent = card,
					}, {
						UI.Create("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							VerticalAlignment = Enum.VerticalAlignment.Center,
							SortOrder = Enum.SortOrder.LayoutOrder,
							Padding = UDim.new(0, 8),
						}),
					})
					UI.Create("TextLabel", {
						Size = UDim2.fromScale(0, 1),
						AutomaticSize = Enum.AutomaticSize.X,
						BackgroundTransparency = 1,
						Font = UI.Fonts.Main,
						TextSize = 16,
						TextColor3 = Theme.Text,
						Text = tostring(info.DisplayName),
						LayoutOrder = 1,
						Parent = nameRow,
					})
					if info.IsAdmin then
						chip(nameRow, "ADMIN", Theme.Accent, { LayoutOrder = 2, Size = UDim2.fromOffset(0, 18) })
					end
					UI.Label({
						Position = UDim2.fromOffset(14, 27),
						Size = UDim2.new(1, -220, 0, 16),
						Text = T(
							"admin.playerMeta",
							tostring(info.UserId),
							tonumber(info.Level) or 1,
							tonumber(info.PingMs) or 0,
							tonumber(info.MatchId) or 0,
							tostring(info.Suspicion or 0)
						),
						Font = UI.Fonts.Body,
						TextColor3 = if sus >= 60 then Theme.Down elseif sus >= 25 then Theme.Warn else Theme.Text2,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
						MaxText = 13,
						Parent = card,
					})
					local actions = rowActions(card, 196)
					button(actions, T("admin.setTarget"), "Secondary", UDim2.new(0, 90, 1, 0), function()
						targetBox.Text = tostring(info.Name)
						setStatus(T("admin.targetSet", tostring(info.Name)), Theme.Up)
					end)
					button(actions, T("admin.view"), "Ghost", UDim2.new(0, 90, 1, 0), function()
						spectate(findPlayer(tostring(info.Name)))
					end)
				end
			end
			kpiPlayers.Text = tostring(count)
			kpiPing.Text = if count > 0 then ("%d ms"):format(math.floor(pingSum / count + 0.5)) else "–"
			kpiMatch.Text = tostring(inMatch)
			kpiSus.Text = tostring(math.floor(maxSus + 0.5))
			kpiSus.TextColor3 = if maxSus >= 60 then Theme.Down elseif maxSus >= 25 then Theme.Warn else Theme.Text
		end
		button(listRow, T("admin.refresh"), "Secondary", part(0.3), refresh)
		onTabOpen.Players = refresh

		UI.Section(page, T("admin.secActions"), 4)
		local reasonRow = UI.Row(page, 5, 36)
		local reasonBox = textBox(reasonRow, T("admin.reasonHint"), FULL)
		local grid = UI.Grid(page, 6, 155, 40)
		local function act(key: string, variant: string, fn: () -> ())
			button(grid, T(key), variant, UDim2.fromScale(1, 1), fn)
		end
		act("admin.kick", "Danger", function()
			if needsConfirm("Kick" .. target(), T("admin.kick")) then
				return
			end
			admin("Kick", { Target = target(), Reason = reasonBox.Text })
		end)
		act("admin.warn", "Primary", function()
			admin("Warn", { Target = target(), Text = reasonBox.Text })
		end)
		act("admin.freeze", "Secondary", function()
			admin("Freeze", { Target = target(), On = true })
		end)
		act("admin.unfreeze", "Secondary", function()
			admin("Freeze", { Target = target(), On = false })
		end)
		act("admin.bring", "Secondary", function()
			admin("Bring", { Target = target() })
		end)
		act("admin.goto", "Secondary", function()
			admin("Goto", { Target = target() })
		end)
		act("admin.pop", "Danger", function()
			if needsConfirm("Pop" .. target(), T("admin.pop")) then
				return
			end
			admin("Pop", { Target = target() })
		end)
		act("admin.heal", "Success", function()
			admin("Heal", { Target = target() })
		end)
		act("admin.spectate", "Ghost", function()
			local p = findPlayer(target())
			if not spectate(p) then
				setStatus(T("admin.noTarget"), Theme.Down)
			end
		end)

		UI.Section(page, T("admin.secBan"), 7)
		local banGrid = UI.Grid(page, 8, 114, 40)
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
			button(banGrid, T("admin.banFor", duration), "Danger", UDim2.fromScale(1, 1), function()
				local label = T("admin.banFor", duration)
				if needsConfirm("Ban" .. duration .. target() .. userIdBox.Text, label) then
					return
				end
				admin("Ban", banArgs(duration))
			end)
		end
		button(idRow, T("admin.unban"), "Success", part(0.24), function()
			if needsConfirm("Unban" .. userIdBox.Text, T("admin.unban")) then
				return
			end
			admin("Unban", { UserId = tonumber(userIdBox.Text) })
		end)
		button(idRow, T("admin.banListBtn"), "Secondary", part(0.24), function()
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
		button(idRow, T("admin.banHistoryBtn"), "Secondary", part(0.24), function()
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
		button(giveRow, T("admin.give"), "Success", part(0.24), function()
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
		button(xpRow, T("admin.giveXp"), "Success", part(0.25), function()
			admin("GiveXp", { Target = target(), Amount = tonumber(xpBox.Text) })
		end)
		local levelBox = textBox(xpRow, T("admin.level"), part(0.25))
		button(xpRow, T("admin.setLevel"), "Primary", part(0.25), function()
			admin("SetLevel", { Target = target(), Level = tonumber(levelBox.Text) })
		end)

		UI.Section(page, T("admin.secData"), 13)
		local dataRow = UI.Row(page, 14, 40)
		button(dataRow, T("admin.playerData"), "Secondary", part(0.2), function()
			local result = admin("PlayerData", { Target = target() })
			if result and result.Ok and type(result.Data) == "table" then
				local lines: { string } = {}
				for _, key in ipairs(sortedKeys(result.Data)) do
					table.insert(lines, ("%s: %s"):format(key, tostring(result.Data[key])))
				end
				showLines(out, lines)
			end
		end)
		button(dataRow, T("admin.receiptsBtn"), "Secondary", part(0.18), function()
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
		button(dataRow, T("admin.regrant"), "Primary", part(0.18), function()
			if needsConfirm("Regrant" .. productBox.Text, T("admin.regrant")) then
				return
			end
			admin("Regrant", { Target = target(), ProductKey = productBox.Text })
		end)
		button(dataRow, T("admin.resetData"), "Danger", part(0.22), function()
			if needsConfirm("Reset" .. target(), T("admin.resetData")) then
				return
			end
			admin("ResetData", { Target = target(), Confirm = true })
		end)
		out = outputBox(page, 20)
	end

	-- =================================================================
	-- REITER KRÄFTE (eigene Attribute)
	-- =================================================================
	do
		local page = pages.Powers
		textLine(page, T("admin.powersHint"), 1, Theme.Warn)
		local grid = UI.Grid(page, 2, 155, 40)
		for i, info in ipairs(BOOL_POWERS) do
			local b: any = nil
			local function refresh()
				local on = player:GetAttribute(info.Name) == true
				b.SetText(("%s: %s"):format(T(info.Key), T(if on then "admin.on" else "admin.off")))
				b.SetVariant(if on then "Primary" else "Secondary")
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
		button(toolRow, T("admin.flyNow"), "Secondary", part(0.33), function()
			if not tryModule("Fly", "Toggle") then
				setStatus(T("admin.moduleMissing", "Fly"), Theme.Down)
			end
		end)
		button(toolRow, T("admin.photo"), "Secondary", part(0.33), function()
			if not tryModule("PhotoMode", "Toggle") then
				setStatus(T("admin.moduleMissing", "PhotoMode"), Theme.Down)
			end
		end)
		button(toolRow, T("admin.debugOverlay"), "Secondary", part(0.34), function()
			tryModule("DebugOverlay", "Toggle")
		end)
	end

	-- =================================================================
	-- REITER WAFFEN & ITEMS
	-- =================================================================
	do
		local page = pages.Weapons
		UI.Section(page, T("admin.secAdminWeapons"), 1)
		local adminGrid = UI.Grid(page, 2, 155, 40)
		local normalDefs: { any } = {}
		for _, def in ipairs(weaponDefs()) do
			if type(def) == "table" and def.AdminOnly == true then
				button(adminGrid, "⚡ " .. weaponName(def), "Premium", UDim2.fromScale(1, 1), function()
					admin("AdminWeapon", { Id = def.Id })
				end)
			elseif type(def) == "table" and type(def.Key) == "string" then
				table.insert(normalDefs, def)
			end
		end
		UI.Section(page, T("admin.secGiveWeapons"), 3)
		local grid = UI.Grid(page, 4, 116, 40)
		for _, def in ipairs(normalDefs) do
			button(grid, weaponName(def), "Secondary", UDim2.fromScale(1, 1), function()
				admin("Give", { Target = target(), Grant = { Weapons = { def.Key } } })
			end)
		end
		local row = UI.Row(page, 5, 40)
		button(row, T("admin.giveAll"), "Success", part(0.3), function()
			if needsConfirm("GiveAll" .. target(), T("admin.giveAll")) then
				return
			end
			admin("GiveAll", { Target = target() })
		end)
		local cosmeticBox = textBox(row, T("admin.cosmeticHint"), part(0.45))
		button(row, T("admin.give"), "Success", part(0.25), function()
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
				textLine(matchList, T("admin.noMatches"), 1, Theme.Muted)
			end
			for i, m in ipairs(result.Data) do
				if type(m) == "table" then
					local card = rowCard(matchList, i, 50)
					local score = if type(m.Score) == "table" then table.concat(m.Score, " : ") else "-"
					local who = if type(m.Players) == "table" then table.concat(m.Players, ", ") else ""
					UI.Label({
						Position = UDim2.fromOffset(14, 6),
						Size = UDim2.new(1, -150, 0, 20),
						Text = ("#%s  %s · %s · %s  %s"):format(
							tostring(m.MatchId),
							tostring(m.Mode),
							tostring(m.Map),
							tostring(m.Phase),
							score
						),
						Font = UI.Fonts.Main,
						TextColor3 = Theme.Text,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
						MaxText = 15,
						Parent = card,
					})
					UI.Label({
						Position = UDim2.fromOffset(14, 27),
						Size = UDim2.new(1, -150, 0, 16),
						Text = ("%s +%d Bots"):format(who, tonumber(m.Bots) or 0),
						Font = UI.Fonts.Body,
						TextColor3 = Theme.Text2,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
						MaxText = 13,
						Parent = card,
					})
					local actions = rowActions(card, 130)
					if m.Tainted then
						chip(actions, "TAINTED", Theme.Down, { LayoutOrder = 0 })
					end
					button(actions, T("admin.endMatch"), "Danger", UDim2.new(0, 96, 1, 0), function()
						if needsConfirm("End" .. tostring(m.MatchId), T("admin.endMatch")) then
							return
						end
						admin("EndMatch", { MatchId = m.MatchId })
						task.delay(0.5, refreshMatches)
					end)
				end
			end
		end
		button(listRow, T("admin.refresh"), "Secondary", part(0.3), refreshMatches)
		onTabOpen.Match = refreshMatches

		UI.Section(page, T("admin.secStart"), 4)
		local grid = UI.Grid(page, 5, 240, 40)
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
		button(startRow, T("admin.startMatch"), "Primary", part(0.35), function()
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
		local serverGrid = UI.Grid(page, 8, 155, 40)
		button(serverGrid, T("admin.spawnBot"), "Secondary", UDim2.fromScale(1, 1), function()
			admin("SpawnBot", { Difficulty = diffCycler.Get() })
		end)
		button(serverGrid, T("admin.fillPads"), "Secondary", UDim2.fromScale(1, 1), function()
			admin("FillPads")
		end)
		button(serverGrid, T("admin.lock"), "Danger", UDim2.fromScale(1, 1), function()
			admin("LockServer", { On = true })
		end)
		button(serverGrid, T("admin.unlock"), "Success", UDim2.fromScale(1, 1), function()
			admin("LockServer", { On = false })
		end)
		local reasonRow = UI.Row(page, 9, 40)
		local reasonBox = textBox(reasonRow, T("admin.reasonHint"), part(0.5))
		button(reasonRow, T("admin.kickAll"), "Danger", part(0.25), function()
			if needsConfirm("KickAll", T("admin.kickAll")) then
				return
			end
			admin("KickAll", { Reason = reasonBox.Text })
		end)
		button(reasonRow, T("admin.serverInfo"), "Secondary", part(0.25), function()
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
		out = outputBox(page, 10)
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
		button(announceRow, T("admin.announce"), "Primary", part(0.5), function()
			admin("Announce", { Text = announceBox.Text, Global = false })
		end)
		button(announceRow, T("admin.announceGlobal"), "Premium", part(0.5), function()
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
			coinsBtn.SetVariant(if coins2 then "Primary" else "Secondary")
			xpBtn.SetText(("2x XP: %s"):format(T(if xp2 then "admin.on" else "admin.off")))
			xpBtn.SetVariant(if xp2 then "Primary" else "Secondary")
		end
		coinsBtn = button(abuseRow, "2x Coins", "Primary", part(0.25), function()
			coins2 = not coins2
			refreshBoost()
		end)
		xpBtn = button(abuseRow, "2x XP", "Primary", part(0.25), function()
			xp2 = not xp2
			refreshBoost()
		end)
		refreshBoost()
		button(abuseRow, T("admin.abuseStartBtn"), "Primary", part(0.25), function()
			admin("AdminAbuse", { Minutes = minutesSlider.Get(), Coins2 = coins2, Xp2 = xp2, Global = false })
		end)
		button(abuseRow, T("admin.global"), "Premium", part(0.25), function()
			if needsConfirm("AbuseGlobal", T("admin.abuse")) then
				return
			end
			admin("AdminAbuse", { Minutes = minutesSlider.Get(), Coins2 = coins2, Xp2 = xp2, Global = true })
		end)

		UI.Section(page, T("admin.secMutator"), 7)
		local mutRow = UI.Row(page, 8, 40)
		local mutators = Config.Modes and Config.Modes.Mutators or {}
		local mutCycler = cycler(mutRow, T("admin.mutator"), sortedKeys(mutators), part(0.4), "-")
		button(mutRow, T("admin.setBtn"), "Primary", part(0.2), function()
			admin("Mutator", { Key = mutCycler.Get(), Global = false })
		end)
		button(mutRow, T("admin.global"), "Premium", part(0.2), function()
			if needsConfirm("MutatorGlobal", T("admin.mutator")) then
				return
			end
			admin("Mutator", { Key = mutCycler.Get(), Global = true })
		end)
		button(mutRow, T("admin.off"), "Ghost", part(0.2), function()
			admin("Mutator", { Key = nil, Global = false })
		end)

		UI.Section(page, T("admin.secFun"), 9)
		local funRow = UI.Row(page, 10, 40)
		button(funRow, T("admin.confettiBtn"), "Secondary", part(0.33), function()
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
		button(funRow, T("admin.gravityNormal"), "Secondary", part(0.33), function()
			gravitySlider.Set(gravity.Max)
			admin("LobbyGravity", { Value = gravity.Max })
		end)
		local lookRow = UI.Row(page, 12, 40)
		local moods = Config.Maps and Config.Maps.Moods or {}
		local moodCycler = cycler(lookRow, T("admin.mood"), sortedKeys(moods), part(0.6))
		button(lookRow, T("admin.lookBtn"), "Primary", part(0.4), function()
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
			Font = UI.Fonts.Body,
			TextColor3 = Theme.Text2,
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxText = 15,
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
		local currentLabel = textLine(page, "", 3, Theme.Warn)
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
		local loadBtn = button(headRow, T("admin.loadBalance"), "Secondary", part(0.3), load)
		loadBtn.Frame.LayoutOrder = 1
		onTabOpen.Balance = load
		local setRow = UI.Row(page, 4, 40)
		local valueBox = textBox(setRow, T("admin.value"), part(0.4))
		button(setRow, T("admin.setField"), "Primary", part(0.6), function()
			admin(
				"SetField",
				{ Weapon = weaponCycler.Get(), Field = fieldCycler.Get(), Value = tonumber(valueBox.Text) }
			)
			load()
		end)
		local actRow = UI.Row(page, 5, 40)
		button(actRow, T("admin.save"), "Success", part(0.28), function()
			if needsConfirm("SaveBalance", T("admin.save")) then
				return
			end
			admin("SaveBalance")
			load()
		end)
		button(actRow, T("admin.resetWeapon"), "Secondary", part(0.26), function()
			admin("ResetWeapon", { Weapon = weaponCycler.Get() })
			load()
		end)
		button(actRow, T("admin.kill"), "Danger", part(0.23), function()
			local weapon = weaponCycler.Get()
			if needsConfirm("Kill" .. tostring(weapon), T("admin.kill")) then
				return
			end
			admin("SetEnabled", { Weapon = weapon, On = false })
			load()
		end)
		button(actRow, T("admin.enable"), "Success", part(0.23), function()
			admin("SetEnabled", { Weapon = weaponCycler.Get(), On = true })
			load()
		end)
		local revertRow = UI.Row(page, 6, 40)
		local versionBox = textBox(revertRow, T("admin.versionHint"), part(0.4))
		button(revertRow, T("admin.revert"), "Primary", part(0.6), function()
			if needsConfirm("Revert" .. versionBox.Text, T("admin.revert")) then
				return
			end
			admin("Revert", { Version = tonumber(versionBox.Text) })
			load()
		end)
		out = outputBox(page, 7)
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
			setStatus(T("core.loading"), Theme.Text2)
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
		button(row, T("admin.days1"), "Secondary", part(0.5), function()
			load(1)
		end)
		button(row, T("admin.days7"), "Secondary", part(0.5), function()
			load(7)
		end)
		out = outputBox(page, 2)
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
				textLine(list, T("admin.nothing"), 1, Theme.Muted)
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
					button(actions, T("admin.view"), "Ghost", part(0.14), function()
						spectate(if userId then Players:GetPlayerByUserId(userId) else nil)
					end)
					for _, duration in ipairs({ "1d", "7d", "perm" }) do
						button(actions, T("admin.banFor", duration), "Danger", part(0.18), function()
							if needsConfirm("ModBan" .. tostring(userId) .. duration, T("admin.banFor", duration)) then
								return
							end
							admin("Ban", { UserId = userId, Duration = duration, Reason = T("admin.modReason") })
						end)
					end
					button(actions, T("admin.dismiss"), "Ghost", part(0.32), function()
						admin("DismissFlag", { Id = e.Id })
						load(mode)
					end)
				end
			end
		end
		button(row, T("admin.flagsBtn"), "Secondary", part(0.5), function()
			load("Flags")
		end)
		button(row, T("admin.reportsBtn"), "Secondary", part(0.5), function()
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
		button(buyRow, T("admin.simPurchase"), "Primary", part(0.4), function()
			admin("SimulatePurchase", { ProductKey = productCycler.Get() })
		end)
		local policyRow = UI.Row(page, 3, 40)
		button(policyRow, T("admin.policyAllowedBtn"), "Secondary", part(0.34), function()
			admin("SimulatePolicy", { Allowed = true })
		end)
		button(policyRow, T("admin.policyRestrictedBtn"), "Secondary", part(0.33), function()
			admin("SimulatePolicy", { Allowed = false })
		end)
		button(policyRow, T("admin.policyAutoBtn"), "Ghost", part(0.33), function()
			admin("SimulatePolicy", {})
		end)
		UI.Section(page, T("admin.secTools"), 4)
		local toolRow = UI.Row(page, 5, 40)
		button(toolRow, T("admin.skipDay"), "Secondary", part(0.5), function()
			admin("SkipDay")
		end)
		button(toolRow, T("admin.unlockAll"), "Secondary", part(0.5), function()
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
				b.SetVariant(if on then "Primary" else "Secondary")
			end
			b = button(flagRow, T(info.Label), "Secondary", part(0.333), function()
				local on = workspace:GetAttribute("Debug" .. info.Key) == true
				admin("SetDebug", { [info.Key] = not on })
			end)
			workspace:GetAttributeChangedSignal("Debug" .. info.Key):Connect(refresh)
			refresh()
		end
		local lastRow = UI.Row(page, 7, 40)
		button(lastRow, T("admin.selfTest"), "Primary", part(0.5), function()
			admin("RunSelfTest")
		end)
		button(lastRow, T("admin.debugOverlay"), "Secondary", part(0.5), function()
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
		pcall(hud.AddRightButton, "🛠️", "admin.button", Theme.Down, 99, AdminPanel.Toggle)
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
