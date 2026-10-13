-- =====================================================================
--  AKYTEX TYCOON – Admin-Panel (Client/Modules/AdminPanel)
--  Besitzer: WP11 (Admin, Events, Anti-Cheat). Vertrag: DESIGN.md §B15.1 (HUD-Knopf Order 99 + Taste P, Fenster
--  720 × 600, 5-s-Bestätigung globaler Aktionen), §B15.2 (11 Tabs), §B15.3 (Admin-Abuse-Katalog, 21 Events), §C7.3
--  (Fenster "Admin"), §C7.5 (AdminPanel.Toggle). Basis: CLUTCH-CLASH-AdminPanel (REUSE §1.4 ADAPT): Rahmen mit
--  Seitenleiste, gemeinsames Ziel-Feld (me/all/others/Name/Präfix/UserId), Status-Pill, needsConfirm, Schieberegler
--  (senden beim Loslassen), Listen, Zuschauen (Taste X). Bausteine aus dem UI-Kit (UI.Chip/StatTile/RowCard/RowActions/
--  Slider/Cycler/NavItem, REUSE §4.10). Look: AKYTEX-Dashboard (Glas, Akzent-Strich, Kennzahl-Kacheln).
--  Wird nur gebaut, wenn der Server dich als Admin markiert (Attribut IsAdmin). JEDE Aktion prüft der Server erneut.
--
--  Tabs: Dashboard · Spieler · Markt · Events · Geld & Items · Kräfte · Welt · Live-Ops · Statistik · Moderation · Debug
--
--  Öffentliche API (§C7.5):
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
local MAX_LINES = 90
local SIDEBAR_W = 160
local TOP = 66 -- erste Zeile unter dem Fenster-Kopf (Kopf 58 + 8)
local GAP = 12
local STATUS_POP_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TAB_FADE_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local built = false
local win: any = nil
local spectating: Player? = nil
local worldPreview: string? = nil

-- ---------------------------------------------------------------------
-- KLEINE HELFER
-- ---------------------------------------------------------------------
local function T(key: string, ...: any): string
	if ctx and type(ctx.T) == "function" then
		return ctx.T(key, ...)
	end
	return key
end

local function lang(): string
	if ctx and type(ctx.Lang_) == "function" then
		return ctx.Lang_()
	end
	return "de"
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

local function num(value: any, default: number): number
	return if type(value) == "number"
			and value == value
			and value ~= math.huge
			and value ~= -math.huge
		then value
		else default
end

local function pick(pair: any, fallback: string): string
	if type(pair) == "table" then
		return tostring(pair[lang()] or pair.de or fallback)
	end
	return if type(pair) == "string" then pair else fallback
end

local function keysOf(list: any): { string }
	local out: { string } = {}
	if type(list) == "table" then
		for _, entry in ipairs(list) do
			if type(entry) == "table" and type(entry.Key) == "string" then
				table.insert(out, entry.Key)
			end
		end
	end
	return out
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

local function fmtCredits(n: any): string
	local format = ctx and ctx.Format
	if format and type(format.Credits) == "function" then
		local ok, text = pcall(format.Credits, num(n, 0), lang())
		if ok then
			return text
		end
	end
	return tostring(n)
end

local function fmtAky(cents: any): string
	local format = ctx and ctx.Format
	if format and type(format.Aky) == "function" then
		local ok, text = pcall(format.Aky, num(cents, 0), lang(), true)
		if ok then
			return text
		end
	end
	return tostring(math.floor(num(cents, 0) / 100)) .. " AKY"
end

local function fmtDuration(seconds: number): string
	local format = ctx and ctx.Format
	if format and type(format.Duration) == "function" then
		local ok, text = pcall(format.Duration, math.max(0, seconds), lang())
		if ok then
			return text
		end
	end
	return ("%ds"):format(math.floor(seconds))
end

local function confirmSeconds(): number
	local security = ctx and ctx.Config and ctx.Config.Security
	return num(security and security.ConfirmSeconds, 5)
end

-- Instrument aus Ticker oder Id (Config.Companies)
local function resolveInstrument(text: string): number?
	local id = tonumber(text)
	if id and id % 1 == 0 then
		return id
	end
	local companies = ctx and ctx.Config and ctx.Config.Companies
	local list = companies and companies.Instruments
	if type(list) == "table" then
		local upper = string.upper(text)
		for _, inst in ipairs(list) do
			if type(inst) == "table" and inst.Ticker == upper then
				return inst.Id
			end
		end
	end
	return nil
end

local function tickerOf(i: any): string
	local companies = ctx and ctx.Config and ctx.Config.Companies
	local byId = companies and companies.ById
	local entry = byId and byId[i]
	if type(entry) == "table" and type(entry.Ticker) == "string" then
		return entry.Ticker
	end
	return tostring(i or "?")
end

-- ---------------------------------------------------------------------
-- ZUSCHAUEN (Client, Taste X beendet)
-- ---------------------------------------------------------------------
local function stopSpectate()
	if not spectating then
		return
	end
	spectating = nil
	local camera = workspace.CurrentCamera
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if camera and humanoid then
		camera.CameraSubject = humanoid
	end
	tryModule("Controls", "SetContext", "World")
	if ctx and type(ctx.Toast) == "function" then
		ctx.Toast(T("admin.spectateStop"), "Info")
	end
end

local function spectate(target: Player?): boolean
	if not target or target == player or not target.Character then
		return false
	end
	local humanoid = target.Character:FindFirstChildOfClass("Humanoid")
	local camera = workspace.CurrentCamera
	if not humanoid or not camera then
		return false
	end
	spectating = target
	camera.CameraSubject = humanoid
	tryModule("Controls", "SetContext", "Spectate")
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
-- BAUSTEINE
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
	return UI.Create("Frame", {
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
end

local function textLine(parent: Instance, text: string, order: number, color: Color3?): TextLabel
	return UI.Label({
		Size = UDim2.new(1, 0, 0, 20),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = text,
		Font = UI.Fonts.Body,
		TextScaled = false,
		TextSize = 15,
		TextWrapped = true,
		RichText = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color or Theme.Text,
		LayoutOrder = order,
		Parent = parent,
	})
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
	local EV = Config.Events or {}
	local LIMITS = EV.AdminLimits or {}

	win = UI.Window(T("admin.title"), 720, 600, Theme.Accent)
	local panel: Frame = win.Panel

	-- Fenster-Kopf: Rollen-Chips rechts neben dem Titel (vor dem ✕)
	local header = panel:FindFirstChild("Header")
	if header then
		local chips = UI.Create("Frame", {
			Name = "Chips",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -60, 0, 18),
			Size = UDim2.fromOffset(240, 22),
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
		UI.Chip(chips, T("admin.badgeOwner"), Theme.Warn, { LayoutOrder = 1 })
		local studio = RunService:IsStudio()
		UI.Chip(
			chips,
			T(if studio then "admin.badgeStudio" else "admin.badgeLive"),
			if studio then Theme.Accent else Theme.Up,
			{ LayoutOrder = 2 }
		)
	end

	-- Seitenleiste mit den 11 Reitern
	local sidebar = UI.Create("Frame", {
		Name = "Sidebar",
		Position = UDim2.fromOffset(GAP, TOP),
		Size = UDim2.new(0, SIDEBAR_W, 1, -(TOP + GAP)),
		BackgroundColor3 = Theme.Bg2,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Parent = panel,
	}, { UI.Corner(12), UI.Stroke(nil, 1) })
	local tabBar = UI.Create("ScrollingFrame", {
		Name = "Tabs",
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -16, 1, -16),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Theme.Border,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = sidebar,
	}, {
		UI.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }),
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

	-- Gefährliche/globale Aktion: erst beim zweiten Klick (innerhalb von 5 s) ausführen
	local confirmKey: string? = nil
	local confirmAt = 0
	local function needsConfirm(key: string, label: string): boolean
		local now = os.clock()
		if confirmKey ~= key or now - confirmAt > confirmSeconds() then
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

	-- Reiter-Seiten (§B15.2)
	local TABS = {
		{ Id = "Dashboard", Key = "admin.tabDashboard" },
		{ Id = "Players", Key = "admin.tabPlayers" },
		{ Id = "Market", Key = "admin.tabMarket" },
		{ Id = "Events", Key = "admin.tabEvents" },
		{ Id = "Give", Key = "admin.tabGive" },
		{ Id = "Powers", Key = "admin.tabPowers" },
		{ Id = "World", Key = "admin.tabWorld" },
		{ Id = "Live", Key = "admin.tabLive" },
		{ Id = "Stats", Key = "admin.tabStats" },
		{ Id = "Mod", Key = "admin.tabMod" },
		{ Id = "Debug", Key = "admin.tabDebug" },
	}
	local pages: { [string]: Frame } = {}
	local tabButtons: { [string]: any } = {}
	local onTabOpen: { [string]: () -> () } = {}
	local currentTab = "Dashboard"
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
		tabButtons[tab.Id] = UI.NavItem(tabBar, T(tab.Key), i, function()
			selectTab(tab.Id)
		end)
	end

	local FULL = UDim2.new(1, 0, 1, 0)
	local function part(scale: number): UDim2
		return UDim2.new(scale, -6, 1, 0)
	end
	local function tiles(parent: Instance, order: number): Frame
		return UI.Create("Frame", {
			Name = "Tiles",
			Size = UDim2.new(1, 0, 0, 64),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Parent = parent,
		}, {
			UI.Create("UIGridLayout", {
				CellSize = UDim2.new(0.25, -8, 1, 0),
				CellPadding = UDim2.fromOffset(10, 0),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
	end
	local function toggleButton(
		parent: Instance,
		labelKey: string,
		size: UDim2,
		get: () -> boolean,
		set: (boolean) -> ()
	): any
		local b: any = nil
		local function refresh()
			local on = get()
			b.SetText(("%s: %s"):format(T(labelKey), T(if on then "admin.on" else "admin.off")))
			b.SetVariant(if on then "Primary" else "Secondary")
		end
		b = button(parent, T(labelKey), "Secondary", size, function()
			set(not get())
			task.delay(0.3, refresh)
		end)
		refresh()
		return { Button = b, Refresh = refresh }
	end

	-- =================================================================
	-- 1) DASHBOARD
	-- =================================================================
	do
		local page = pages.Dashboard
		local row = tiles(page, 1)
		local kpiPlayers = UI.StatTile(row, T("admin.kpiPlayers"), 1)
		local kpiGlobal = UI.StatTile(row, T("admin.kpiGlobal"), 2)
		local kpiRegime = UI.StatTile(row, T("admin.kpiRegime"), 3)
		local kpiBus = UI.StatTile(row, T("admin.kpiBus"), 4)
		local localBanner = UI.Create("Frame", {
			Name = "LocalMarket",
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
			LayoutOrder = 2,
			Visible = false,
			Parent = page,
		})
		UI.Chip(localBanner, T("core.localMarket"), Theme.Warn, { LayoutOrder = 1 })
		UI.Section(page, T("admin.secActiveEvents"), 3)
		local eventRow = UI.Create("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = 4,
			Parent = page,
		}, {
			UI.Create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Wraps = true,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 6),
			}),
		})
		UI.Section(page, T("admin.secServer"), 5)
		local actRow = UI.Row(page, 6, 40)
		local out: Frame
		local function refresh()
			local result = admin("Dashboard")
			if not result or not result.Ok or type(result.Data) ~= "table" then
				return
			end
			local d = result.Data
			kpiPlayers.Text = ("%d / %d"):format(num(d.Players, 0), num(d.MaxPlayers, 0))
			kpiGlobal.Text = ("%d · %d"):format(num(d.GlobalPlayers, 0), num(d.Servers, 0))
			local market = if type(d.Market) == "table" then d.Market else {}
			kpiRegime.Text = ("%.2f"):format(num(market.Regime, 1))
			kpiBus.Text = T(if market.BusOk then "admin.busOk" else "admin.busDown")
			kpiBus.TextColor3 = if market.BusOk then Theme.Up else Theme.Down
			localBanner.Visible = d.LocalMarket == true
			clearChildren(eventRow)
			local kinds = if type(d.Events) == "table" then d.Events else {}
			if #kinds == 0 then
				UI.Chip(eventRow, T("admin.noEvents"), Theme.Muted, { LayoutOrder = 1 })
			end
			for i, kind in ipairs(kinds) do
				UI.Chip(
					eventRow,
					tostring(kind),
					if d.AdminAbuse then Theme.Down else Theme.Accent,
					{ LayoutOrder = i }
				)
			end
			local lines: { string } = {
				T("admin.infoLoad", num(d.HeartbeatMs, 0), num(d.HeartbeatMaxMs, 0)),
				T("admin.infoMarket", num(market.TickMs, 0), num(market.Instruments, 0), num(market.Events, 0)),
				T("admin.infoMisc", num(d.MemoryMb, 0), fmtDuration(num(d.Uptime, 0))),
				T("admin.infoVersion", tostring(d.Version), tostring(d.JobId), num(d.LiveVersion, 0)),
			}
			if type(d.Jobs) == "table" then
				for _, job in ipairs(d.Jobs) do
					if type(job) == "table" then
						table.insert(
							lines,
							("  %s · Ø %.2f ms · max %.2f ms"):format(
								tostring(job.Name),
								num(job.AvgMs, 0),
								num(job.MaxMs, 0)
							)
						)
					end
				end
			end
			if d.Locked then
				table.insert(lines, T("admin.locked"))
			end
			if type(d.Maintenance) == "string" and d.Maintenance ~= "" then
				table.insert(lines, T("admin.maintenanceOn", d.Maintenance))
			end
			if d.AdminAbuse then
				table.insert(lines, T("evt.adminWindow"))
			end
			showLines(out, lines)
		end
		button(actRow, T("admin.refresh"), "Secondary", part(0.25), refresh)
		button(actRow, T("admin.lock"), "Danger", part(0.25), function()
			if needsConfirm("Lock", T("admin.lock")) then
				return
			end
			admin("LockServer", { On = true })
		end)
		button(actRow, T("admin.unlock"), "Success", part(0.25), function()
			admin("LockServer", { On = false })
		end)
		button(actRow, T("admin.debugOverlay"), "Ghost", part(0.25), function()
			tryModule("DebugOverlay", "Toggle")
		end)
		out = outputBox(page, 7)
		onTabOpen.Dashboard = refresh
	end

	-- =================================================================
	-- 2) SPIELER
	-- =================================================================
	do
		local page = pages.Players
		local row = tiles(page, 0)
		local kpiPlayers = UI.StatTile(row, T("admin.kpiPlayers"), 1)
		local kpiPing = UI.StatTile(row, T("admin.kpiPing"), 2)
		local kpiSus = UI.StatTile(row, T("admin.kpiSuspicion"), 3)
		local kpiFrozen = UI.StatTile(row, T("admin.kpiFrozen"), 4)

		UI.Section(page, T("admin.secPlayers"), 1)
		local listRow = UI.Row(page, 2, 40)
		local playerList = listFrame(page, 3)
		local function refresh()
			local result = admin("GetPlayers")
			if not result or not result.Ok or type(result.Data) ~= "table" then
				return
			end
			clearChildren(playerList)
			local count, pingSum, maxSus, frozen = 0, 0, 0, 0
			for i, info in ipairs(result.Data) do
				if type(info) == "table" then
					count += 1
					pingSum += num(info.PingMs, 0)
					local sus = num(info.Suspicion, 0)
					maxSus = math.max(maxSus, sus)
					if info.Frozen then
						frozen += 1
					end
					local card = UI.RowCard(playerList, i, 50)
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
						UI.Chip(nameRow, "ADMIN", Theme.Accent, { LayoutOrder = 2, Size = UDim2.fromOffset(0, 18) })
					end
					if info.Frozen then
						UI.Chip(
							nameRow,
							T("admin.frozenChip"),
							Theme.Warn,
							{ LayoutOrder = 3, Size = UDim2.fromOffset(0, 18) }
						)
					end
					UI.Label({
						Position = UDim2.fromOffset(14, 27),
						Size = UDim2.new(1, -220, 0, 16),
						Text = T(
							"admin.playerMeta",
							tostring(info.UserId),
							num(info.Licence, 1),
							num(info.Floors, 0),
							num(info.PingMs, 0),
							tostring(info.Suspicion or 0),
							num(info.Minutes, 0)
						),
						Font = UI.Fonts.Body,
						TextColor3 = if sus >= 60 then Theme.Down elseif sus >= 25 then Theme.Warn else Theme.Text2,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
						MaxText = 13,
						Parent = card,
					})
					local actions = UI.RowActions(card, 196)
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
			kpiSus.Text = tostring(math.floor(maxSus + 0.5))
			kpiSus.TextColor3 = if maxSus >= 60 then Theme.Down elseif maxSus >= 25 then Theme.Warn else Theme.Text
			kpiFrozen.Text = tostring(frozen)
		end
		button(listRow, T("admin.refresh"), "Secondary", part(0.3), refresh)
		onTabOpen.Players = refresh

		UI.Section(page, T("admin.secActions"), 4)
		local reasonRow = UI.Row(page, 5, 36)
		local reasonBox = textBox(reasonRow, T("admin.reasonHint"), FULL)
		local grid = UI.Grid(page, 6, 122, 40)
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
		act("admin.visit", "Secondary", function()
			admin("Visit", { Target = target() })
		end)
		act("admin.spectate", "Ghost", function()
			if not spectate(findPlayer(target())) then
				setStatus(T("admin.noTarget"), Theme.Down)
			end
		end)

		UI.Section(page, T("admin.secBan"), 7)
		local banGrid = UI.Grid(page, 8, 96, 40)
		local privateRow = UI.Row(page, 9, 36)
		local privateBox = textBox(privateRow, T("admin.privateHint"), FULL)
		local idRow = UI.Row(page, 10, 40)
		local userIdBox = textBox(idRow, T("admin.userIdHint"), part(0.28))
		local out: Frame
		local function banArgs(duration: string): { [string]: any }
			local id = tonumber(userIdBox.Text)
			local args: { [string]: any } = { Duration = duration, Reason = reasonBox.Text, Private = privateBox.Text }
			if id then
				args.UserId = id
			else
				args.Target = target()
			end
			return args
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

		UI.Section(page, T("admin.secData"), 11)
		local dataRow = UI.Row(page, 12, 40)
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
						table.insert(lines, ("%s · %s %s"):format(tostring(r.Id), fmtTime(r.T), tostring(r.Key or "")))
					end
				end
				showLines(out, lines)
			end
		end)
		local productKeys: { string } = {}
		for _, list in ipairs({ Config.Shop and Config.Shop.Products, Config.Shop and Config.Shop.GamePasses }) do
			for _, key in ipairs(keysOf(list)) do
				table.insert(productKeys, key)
			end
		end
		local productCycler = UI.Cycler(dataRow, T("admin.product"), productKeys, part(0.24))
		button(dataRow, T("admin.regrant"), "Primary", part(0.18), function()
			local key = productCycler.Get()
			if needsConfirm("Regrant" .. tostring(key) .. target(), T("admin.regrant")) then
				return
			end
			admin("Regrant", { Target = target(), ProductKey = key })
		end)
		button(dataRow, T("admin.resetData"), "Danger", part(0.2), function()
			if needsConfirm("Reset" .. target(), T("admin.resetData")) then
				return
			end
			admin("ResetData", { Target = target(), Confirm = true })
		end)
		out = outputBox(page, 20)
	end

	-- =================================================================
	-- 3) MARKT (nur MarketService.Admin, immer global; Admin-Fenster = Liga-Taint)
	-- =================================================================
	do
		local page = pages.Market
		local strengthRange = LIMITS.MarketStrength or { 5, 50 }
		local rampRange = LIMITS.Ramp or { 30, 300 }
		local decayRange = LIMITS.DecayMinutes or { 5, 60 }
		local haltRange = LIMITS.HaltSeconds or { 10, 600 }
		local volRange = LIMITS.Vol or { 0.5, 3 }
		local volMinutes = LIMITS.VolMinutes or { 5, 30 }
		textLine(page, T("admin.marketHint"), 0, Theme.Warn)

		UI.Section(page, T("admin.secScope"), 1)
		local scopeRow = UI.Row(page, 2, 40)
		local scopeCycler = UI.Cycler(scopeRow, T("admin.scope"), { "All", "Sector", "Inst" }, part(0.34))
		local sectorKeys: { string } = {}
		local sectors = Config.Companies and Config.Companies.Sectors
		if type(sectors) == "table" then
			for _, s in ipairs(sectors) do
				if type(s) == "table" and type(s.Key) == "string" then
					table.insert(sectorKeys, s.Key)
				end
			end
		end
		local sectorCycler = UI.Cycler(scopeRow, T("admin.sector"), sectorKeys, part(0.3))
		local instBox = textBox(scopeRow, T("admin.instHint"), part(0.36))
		local function scopeArgs(): { [string]: any }?
			local scope = scopeCycler.Get() or "All"
			if scope == "Sector" then
				return { Scope = "Sector", Target = sectorCycler.Get() }
			elseif scope == "Inst" then
				local id = resolveInstrument(instBox.Text)
				if not id then
					setStatus(T("admin.badTarget"), Theme.Down)
					return nil
				end
				return { Scope = "Inst", Target = id }
			end
			return { Scope = "All" }
		end

		UI.Section(page, T("admin.secMove"), 3)
		local strength = UI.Slider(page, 4, T("admin.strength"), strengthRange[1], strengthRange[2], 15, function() end)
		local ramp = UI.Slider(page, 5, T("admin.ramp"), rampRange[1], rampRange[2], 60, function() end)
		local decay = UI.Slider(page, 6, T("admin.decay"), decayRange[1], decayRange[2], 15, function() end)
		local moveRow = UI.Row(page, 7, 40)
		local crashWarn = false -- Vorwarnung (Config.Events.AdminLimits.CrashWarnSeconds) nur für Mega-Crash
		toggleButton(moveRow, "admin.crashWarn", part(0.25), function()
			return crashWarn
		end, function(v)
			crashWarn = v
		end)
		local function market(kind: string, extra: { [string]: any }, labelKey: string)
			if needsConfirm("Market" .. kind, T(labelKey)) then
				return
			end
			local args = extra
			args.Kind = kind
			admin("Market", args)
		end
		button(moveRow, T("admin.ev.MegaRally"), "Success", part(0.25), function()
			local args = scopeArgs()
			if not args then
				return
			end
			args.Strength, args.Ramp, args.Decay = strength.Get(), ramp.Get(), decay.Get()
			market("MegaRally", args, "admin.ev.MegaRally")
		end)
		button(moveRow, T("admin.ev.MegaCrash"), "Danger", part(0.25), function()
			local args = scopeArgs()
			if not args then
				return
			end
			args.Strength, args.Ramp, args.Decay, args.Warn = strength.Get(), ramp.Get(), decay.Get(), crashWarn
			market("MegaCrash", args, "admin.ev.MegaCrash")
		end)
		button(moveRow, T("admin.ev.Normalize"), "Secondary", part(0.25), function()
			market("Normalize", {}, "admin.ev.Normalize")
		end)
		local companyRow = UI.Row(page, 8, 40)
		local companyBox = textBox(companyRow, T("admin.instHint"), part(0.34))
		button(companyRow, T("admin.ev.Pump"), "Success", part(0.33), function()
			local id = resolveInstrument(companyBox.Text)
			if not id then
				setStatus(T("admin.badTarget"), Theme.Down)
				return
			end
			market(
				"Pump",
				{ Target = id, Strength = strength.Get(), Ramp = ramp.Get(), Decay = decay.Get() },
				"admin.ev.Pump"
			)
		end)
		button(companyRow, T("admin.ev.Dump"), "Danger", part(0.33), function()
			local id = resolveInstrument(companyBox.Text)
			if not id then
				setStatus(T("admin.badTarget"), Theme.Down)
				return
			end
			market(
				"Dump",
				{ Target = id, Strength = strength.Get(), Ramp = ramp.Get(), Decay = decay.Get() },
				"admin.ev.Dump"
			)
		end)

		UI.Section(page, T("admin.ev.News"), 9)
		local maxChars = num(LIMITS.NewsChars, 80)
		local deRow = UI.Row(page, 10, 36)
		local newsDe = textBox(deRow, T("admin.newsDeHint", maxChars), FULL)
		local enRow = UI.Row(page, 11, 36)
		local newsEn = textBox(enRow, T("admin.newsEnHint", maxChars), FULL)
		local band = UI.Slider(page, 12, T("admin.band"), 1, 4, 2, function() end)
		local newsRow = UI.Row(page, 13, 40)
		local up = true
		toggleButton(newsRow, "admin.newsUp", part(0.3), function()
			return up
		end, function(v)
			up = v
		end)
		button(newsRow, T("admin.newsSend"), "Premium", part(0.7), function()
			local args = scopeArgs()
			if not args or args.Scope == "All" then
				setStatus(T("admin.newsScope"), Theme.Down)
				return
			end
			args.Band = band.Get()
			args.Dir = if up then 1 else -1
			args.Text = { de = newsDe.Text, en = if newsEn.Text ~= "" then newsEn.Text else newsDe.Text }
			market("News", args, "admin.ev.News")
		end)

		UI.Section(page, T("admin.secHalt"), 14)
		local haltSlider = UI.Slider(page, 15, T("admin.seconds"), haltRange[1], haltRange[2], 60, function() end)
		local haltRow = UI.Row(page, 16, 40)
		button(haltRow, T("admin.ev.Halt"), "Danger", part(0.5), function()
			local args = scopeArgs()
			if not args then
				return
			end
			if args.Scope == "Sector" then
				args = { Scope = "All" }
			end
			args.Seconds = haltSlider.Get()
			market("Halt", args, "admin.ev.Halt")
		end)
		button(haltRow, T("admin.ev.Resume"), "Success", part(0.5), function()
			admin("Market", { Kind = "Resume", Scope = "All" })
		end)

		UI.Section(page, T("admin.secIpoVol"), 17)
		local ipoRow = UI.Row(page, 18, 40)
		local pipeline = Config.Market and Config.Market.IpoPipeline
		local ipoIds: { string } = {}
		if pipeline and type(pipeline.Season) == "table" then
			for _, ids in pairs(pipeline.Season) do
				if type(ids) == "table" then
					for _, id in ipairs(ids) do
						table.insert(ipoIds, ("%s (%d)"):format(tickerOf(id), id))
					end
				end
			end
		end
		table.sort(ipoIds)
		local ipoCycler = UI.Cycler(ipoRow, T("admin.ipo"), ipoIds, part(0.6))
		button(ipoRow, T("admin.ev.Ipo"), "Premium", part(0.4), function()
			local value = ipoCycler.Get()
			local id = if value then tonumber(string.match(value, "%((%d+)%)")) else nil
			if not id then
				setStatus(T("admin.badTarget"), Theme.Down)
				return
			end
			market("Ipo", { Target = id }, "admin.ev.Ipo")
		end)
		local volSlider = UI.Slider(
			page,
			19,
			T("admin.volTenths"),
			math.floor(volRange[1] * 10),
			math.floor(volRange[2] * 10),
			15,
			function() end
		)
		local volMin = UI.Slider(
			page,
			20,
			T("admin.minutes"),
			volMinutes[1],
			volMinutes[2],
			volMinutes[1],
			function() end
		)
		local volRow = UI.Row(page, 21, 40)
		button(volRow, T("admin.ev.Vol"), "Primary", part(0.5), function()
			market("Vol", { Strength = volSlider.Get() / 10, Minutes = volMin.Get() }, "admin.ev.Vol")
		end)

		UI.Section(page, T("admin.secMarketLog"), 22)
		local logRow = UI.Row(page, 23, 40)
		local out: Frame
		local function loadLog()
			local result = admin("MarketLog")
			if not result or not result.Ok or type(result.Data) ~= "table" then
				return
			end
			local d = result.Data
			local lines: { string } = {}
			if d.LocalMarket then
				table.insert(lines, T("core.localMarket"))
			end
			if d.Blocked then
				table.insert(lines, T("admin.tradeBlocked"))
			end
			local tick = num(d.Tick, 0)
			local epoch = num(ctx.Clock and ctx.Clock.EPOCH, 0)
			if type(d.Windows) == "table" then
				for _, w in ipairs(d.Windows) do
					if type(w) == "table" then
						table.insert(
							lines,
							T(
								"admin.windowLine",
								fmtTime(num(w[1], 0) + epoch),
								fmtTime(num(w[2], 0) + epoch),
								if num(w[2], 0) >= tick then "●" else ""
							)
						)
					end
				end
			end
			if type(d.News) == "table" then
				for _, n in ipairs(d.News) do
					if type(n) == "table" then
						local text = if type(n.Text) == "table" then pick(n.Text, "") else T(tostring(n.Key or ""))
						table.insert(
							lines,
							("%s · %s · %s %s"):format(
								fmtTime(num(n.T, 0) + epoch),
								tostring(n.Kind),
								if n.I then tickerOf(n.I) elseif n.Sector then tostring(n.Sector) else "",
								string.sub(text, 1, 80)
							)
						)
					end
				end
			end
			if #lines == 0 then
				table.insert(lines, T("admin.nothing"))
			end
			showLines(out, lines)
		end
		button(logRow, T("admin.refresh"), "Secondary", part(0.3), loadLog)
		out = outputBox(page, 24)
		onTabOpen.Market = loadLog
	end

	-- =================================================================
	-- 4) EVENTS (Ansage, Admin-Abuse-Katalog Nicht-Markt, Samstags-Show, Kalender)
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
		local scopeRow = UI.Row(page, 5, 40)
		local global = false
		toggleButton(scopeRow, "admin.allServers", part(0.5), function()
			return global
		end, function(v)
			global = v
		end)
		textLine(page, T("admin.abuseHint"), 6, Theme.Muted)
		local rainRange = LIMITS.MoneyRain and LIMITS.MoneyRain.Seconds or { 60, 300 }
		local goldenMinutes = LIMITS.GoldenHour and LIMITS.GoldenHour.Minutes or { 5, 60 }
		local xpMinutes = LIMITS.XpRush and LIMITS.XpRush.Minutes or { 15, 60 }
		local bossRange = LIMITS.Boss and LIMITS.Boss.Seconds or { 60, 300 }
		local rainSlider = UI.Slider(page, 7, T("admin.rainSeconds"), rainRange[1], rainRange[2], 120, function() end)
		local goldenSlider = UI.Slider(
			page,
			8,
			T("admin.goldenMinutes"),
			goldenMinutes[1],
			goldenMinutes[2],
			15,
			function() end
		)
		local xpSlider = UI.Slider(page, 9, T("admin.xpMinutes"), xpMinutes[1], xpMinutes[2], 30, function() end)
		local bossSlider = UI.Slider(page, 10, T("admin.bossSeconds"), bossRange[1], bossRange[2], 120, function() end)
		local multRow = UI.Row(page, 11, 40)
		local goldenMult = UI.Cycler(multRow, T("admin.goldenMult"), { "×2", "×3" }, part(0.4))
		local grid = UI.Grid(page, 12, 122, 40)
		local function abuse(kind: string, args: { [string]: any }?)
			local label = T("admin.ev." .. kind)
			if (global or kind == "SaturdayShow") and needsConfirm("Abuse" .. kind, label) then
				return
			end
			admin("Abuse", { Event = kind, Args = args or {}, Global = global })
		end
		button(grid, T("admin.ev.MoneyRain"), "Success", UDim2.fromScale(1, 1), function()
			abuse("MoneyRain", { Seconds = rainSlider.Get() })
		end)
		button(grid, T("admin.ev.GoldenHour"), "Premium", UDim2.fromScale(1, 1), function()
			abuse("GoldenHour", { Mult = if goldenMult.Get() == "×3" then 3 else 2, Minutes = goldenSlider.Get() })
		end)
		button(grid, T("admin.ev.XpRush"), "Primary", UDim2.fromScale(1, 1), function()
			abuse("XpRush", { Minutes = xpSlider.Get() })
		end)
		button(grid, T("admin.ev.BuildBoom"), "Secondary", UDim2.fromScale(1, 1), function()
			abuse("BuildBoom", nil)
		end)
		button(grid, T("admin.ev.Lightshow"), "Secondary", UDim2.fromScale(1, 1), function()
			abuse("Lightshow", nil)
		end)
		button(grid, T("admin.ev.Fireworks"), "Secondary", UDim2.fromScale(1, 1), function()
			abuse("Fireworks", nil)
		end)
		button(grid, T("admin.ev.Confetti"), "Secondary", UDim2.fromScale(1, 1), function()
			abuse("Confetti", nil)
		end)
		button(grid, T("admin.ev.BellShow"), "Secondary", UDim2.fromScale(1, 1), function()
			abuse("BellShow", nil)
		end)
		button(grid, T("admin.ev.Boss"), "Primary", UDim2.fromScale(1, 1), function()
			abuse("Boss", { Seconds = bossSlider.Get() })
		end)
		button(grid, T("admin.ev.AllToHall"), "Secondary", UDim2.fromScale(1, 1), function()
			if needsConfirm("AllToHall", T("admin.ev.AllToHall")) then
				return
			end
			admin("Abuse", { Event = "AllToHall", Args = {}, Global = false })
		end)
		button(grid, T("admin.ev.SaturdayShow"), "Premium", UDim2.fromScale(1, 1), function()
			abuse("SaturdayShow", nil)
		end)
		local stopRow = UI.Row(page, 13, 40)
		local stopCycler = UI.Cycler(
			stopRow,
			T("admin.stopKind"),
			{ "GoldenHour", "XpRush", "MoneyRain", "Boss", "Bear", "GoldenBull", "Fireworks", "Lightshow" },
			part(0.6)
		)
		button(stopRow, T("admin.stop"), "Danger", part(0.4), function()
			admin("AbuseStop", { Event = stopCycler.Get() })
		end)
		for i, entry in ipairs(EV.Catalogue or {}) do
			if type(entry) == "table" and type(entry.Key) == "string" and not entry.Market then
				textLine(
					page,
					("· %s – %s"):format(T("admin.ev." .. entry.Key), T("admin.evHint." .. entry.Key)),
					13 + i,
					Theme.Muted
				)
			end
		end

		UI.Section(page, T("admin.secCalendar"), 40)
		local calRow = UI.Row(page, 41, 40)
		local out: Frame
		local function loadCalendar()
			local clock = ctx.Clock
			if not clock or type(clock.NextBerlin) ~= "function" then
				return
			end
			local now = clock.Now()
			local rows: { { At: number, Text: string } } = {}
			local function add(entry: any, label: string)
				if type(entry) ~= "table" or type(entry.HH) ~= "number" or type(entry.MM) ~= "number" then
					return
				end
				local ok, at = pcall(clock.NextBerlin, entry.Dow, entry.HH, entry.MM, now)
				if ok and type(at) == "number" then
					table.insert(rows, {
						At = at,
						Text = T("admin.calLine", fmtTime(at), label, fmtDuration(at - now)),
					})
				end
			end
			-- Markt-Termine (WP3) und Nicht-Markt-Termine (WP11); gleicher Key (z. B. AutoShow) nur einmal
			local seen: { [string]: boolean } = {}
			for _, list in ipairs({ EV.Weekly or {}, Config.Market and Config.Market.Weekly or {} }) do
				for _, entry in ipairs(list) do
					local key = if type(entry) == "table" then tostring(entry.Key) else ""
					if key ~= "" and not seen[key] then
						seen[key] = true
						add(entry, T("admin.cal." .. key))
					end
				end
			end
			table.sort(rows, function(a, b)
				return a.At < b.At
			end)
			local lines: { string } = {}
			for _, r in ipairs(rows) do
				table.insert(lines, r.Text)
			end
			showLines(out, lines)
		end
		button(calRow, T("admin.refresh"), "Secondary", part(0.3), loadCalendar)
		out = outputBox(page, 42)
		onTabOpen.Events = loadCalendar
	end

	-- =================================================================
	-- 5) GELD & ITEMS (Turm-Seite; AKY/Lizenz taint die Liga-Woche des Empfängers)
	-- =================================================================
	do
		local page = pages.Give
		textLine(page, T("admin.giveHint"), 0, Theme.Warn)
		UI.Section(page, T("admin.secMoney"), 1)
		local crRow = UI.Row(page, 2, 40)
		local crBox = textBox(crRow, T("admin.creditsHint"), part(0.5))
		button(crRow, T("admin.giveCredits"), "Success", part(0.5), function()
			local amount = tonumber(crBox.Text)
			if target() == "all" and needsConfirm("GiveCR", T("admin.giveCredits")) then
				return
			end
			admin("Give", { Target = target(), Grant = { Credits = amount } })
		end)
		local akyRow = UI.Row(page, 3, 40)
		local akyBox = textBox(akyRow, T("admin.akyHint"), part(0.5))
		button(akyRow, T("admin.giveAky"), "Primary", part(0.5), function()
			if needsConfirm("GiveAky" .. target(), T("admin.giveAky")) then
				return
			end
			admin("GiveAky", { Target = target(), Aky = tonumber(akyBox.Text) })
		end)
		UI.Section(page, T("admin.secProgress"), 4)
		local licRow = UI.Row(page, 5, 40)
		local licences: { string } = {}
		local licenceList = Config.Progression and Config.Progression.Licences or {}
		for i, def in ipairs(licenceList) do
			table.insert(licences, ("%d · %s"):format(i, pick(def.Name, tostring(def.Key))))
		end
		local licCycler = UI.Cycler(licRow, T("admin.licence"), licences, part(0.6))
		button(licRow, T("admin.setLicence"), "Primary", part(0.4), function()
			local value = licCycler.Get()
			local idx = if value then tonumber(string.match(value, "^(%d+)")) else nil
			if needsConfirm("Licence" .. tostring(idx) .. target(), T("admin.setLicence")) then
				return
			end
			admin("SetLicence", { Target = target(), Licence = idx })
		end)
		local floorRow = UI.Row(page, 6, 40)
		local floorBox = textBox(floorRow, T("admin.floorsHint"), part(0.5))
		button(floorRow, T("admin.setFloors"), "Primary", part(0.5), function()
			if needsConfirm("Floors" .. target(), T("admin.setFloors")) then
				return
			end
			admin("SetFloors", { Target = target(), Floors = tonumber(floorBox.Text) })
		end)
		UI.Section(page, T("admin.secItems"), 7)
		local itemRow = UI.Row(page, 8, 40)
		local kindCycler = UI.Cycler(
			itemRow,
			T("admin.itemKind"),
			{ "Cars", "Watches", "Accessories", "Decor", "Cosmetics", "Titles" },
			part(0.34)
		)
		local itemBox = textBox(itemRow, T("admin.itemKeyHint"), part(0.36))
		button(itemRow, T("admin.give"), "Success", part(0.3), function()
			local kind = kindCycler.Get() or "Cars"
			local key = itemBox.Text
			local grant: { [string]: any } = {}
			if kind == "Decor" then
				grant.Decor = { [key] = 1 }
			else
				grant[kind] = { key }
			end
			admin("Give", { Target = target(), Grant = grant })
		end)
		local allGrid = UI.Grid(page, 9, 122, 40)
		for _, kind in ipairs({ "Cars", "Watches", "Accessories", "Decor" }) do
			button(allGrid, T("admin.giveAll" .. kind), "Secondary", UDim2.fromScale(1, 1), function()
				if needsConfirm("GiveAll" .. kind .. target(), T("admin.giveAll" .. kind)) then
					return
				end
				admin("GiveAllItems", { Target = target(), Kind = kind })
			end)
		end
		UI.Section(page, T("admin.secTokens"), 10)
		local tokenRow = UI.Row(page, 11, 40)
		local tokenKind = UI.Cycler(
			tokenRow,
			T("admin.tokenKind"),
			{ "SeasonTiers", "SeasonXp", "BoostX2", "BoostX5", "ExpressTokens", "InstantTokens" },
			part(0.4)
		)
		local tokenBox = textBox(tokenRow, T("admin.amount"), part(0.3))
		button(tokenRow, T("admin.give"), "Success", part(0.3), function()
			local kind = tokenKind.Get() or "SeasonTiers"
			admin("Give", { Target = target(), Grant = { [kind] = tonumber(tokenBox.Text) } })
		end)
	end

	-- =================================================================
	-- 6) KRÄFTE (eigene Attribute; der Server ehrt sie nur bei IsAdmin)
	-- =================================================================
	do
		local page = pages.Powers
		textLine(page, T("admin.powersHint"), 1, Theme.Warn)
		local grid = UI.Grid(page, 2, 166, 40)
		for _, info in ipairs({
			{ Name = "CanFly", Key = "admin.pFly", Default = true },
			{ Name = "AdminNoclip", Key = "admin.pNoclip", Default = false },
			{ Name = "AdminInvisible", Key = "admin.pInvisible", Default = false },
			{ Name = "AdminESP", Key = "admin.pESP", Default = false },
		}) do
			local b: any = nil
			local function refresh()
				local value = player:GetAttribute(info.Name)
				local on = value == true or (info.Default and value == nil)
				b.SetText(("%s: %s"):format(T(info.Key), T(if on then "admin.on" else "admin.off")))
				b.SetVariant(if on then "Primary" else "Secondary")
			end
			b = UI.Button({ Size = UDim2.fromScale(1, 1), Text = T(info.Key), MaxText = 15, Parent = grid }, function()
				local value = player:GetAttribute(info.Name)
				local on = value == true or (info.Default and value == nil)
				admin("SetPower", { Name = info.Name, Value = not on })
			end)
			player:GetAttributeChangedSignal(info.Name):Connect(refresh)
			refresh()
		end
		local powers = Config.Security and Config.Security.Powers or {}
		local speed = powers.Speed or { Min = 16, Max = 150 }
		local jump = powers.Jump or { Min = 7.2, Max = 100 }
		local speedMin = math.floor(speed.Min)
		local jumpMin = math.floor(jump.Min)
		local speedSlider = UI.Slider(
			page,
			3,
			T("admin.pSpeed"),
			speedMin,
			math.floor(speed.Max),
			num(player:GetAttribute("AdminSpeed"), speedMin),
			function(value: number)
				admin("SetPower", { Name = "AdminSpeed", Value = if value <= speedMin then nil else value })
			end
		)
		local jumpSlider = UI.Slider(
			page,
			4,
			T("admin.pJump"),
			jumpMin,
			math.floor(jump.Max),
			num(player:GetAttribute("AdminJump"), jumpMin),
			function(value: number)
				admin("SetPower", { Name = "AdminJump", Value = if value <= jumpMin then nil else value })
			end
		)
		player:GetAttributeChangedSignal("AdminSpeed"):Connect(function()
			speedSlider.Set(num(player:GetAttribute("AdminSpeed"), speedMin))
		end)
		player:GetAttributeChangedSignal("AdminJump"):Connect(function()
			jumpSlider.Set(num(player:GetAttribute("AdminJump"), jumpMin))
		end)
		local toolGrid = UI.Grid(page, 5, 166, 40)
		button(toolGrid, T("admin.flyNow"), "Secondary", UDim2.fromScale(1, 1), function()
			if not tryModule("Fly", "Toggle") then
				setStatus(T("admin.moduleMissing", "Fly"), Theme.Down)
			end
		end)
		button(toolGrid, T("admin.photo"), "Secondary", UDim2.fromScale(1, 1), function()
			if not tryModule("PhotoMode", "Toggle") then
				setStatus(T("admin.moduleMissing", "PhotoMode"), Theme.Down)
			end
		end)
		button(toolGrid, T("admin.showCam"), "Premium", UDim2.fromScale(1, 1), function()
			if not tryModule("AdminTools", "ToggleShowCam") then
				setStatus(T("admin.moduleMissing", "AdminTools"), Theme.Down)
			end
		end)
		button(toolGrid, T("admin.debugOverlay"), "Secondary", UDim2.fromScale(1, 1), function()
			tryModule("DebugOverlay", "Toggle")
		end)
		button(toolGrid, T("admin.visit"), "Secondary", UDim2.fromScale(1, 1), function()
			admin("Visit", { Target = target() })
		end)
		button(toolGrid, T("admin.spectate"), "Ghost", UDim2.fromScale(1, 1), function()
			if not spectate(findPlayer(target())) then
				setStatus(T("admin.noTarget"), Theme.Down)
			end
		end)
	end

	-- =================================================================
	-- 7) WELT (Vorschau nur lokal; Welt-Event jetzt starten = nur dieser Server)
	-- =================================================================
	do
		local page = pages.World
		UI.Section(page, T("admin.secLook"), 1)
		local lookRow = UI.Row(page, 2, 40)
		local lookCycler = UI.Cycler(
			lookRow,
			T("admin.look"),
			{ "Day", "Night", "Clear", "Clouds", "Storm", "Golden", "Crash", "Rally" },
			part(0.5),
			T("admin.auto")
		)
		button(lookRow, T("admin.apply"), "Primary", part(0.25), function()
			worldPreview = lookCycler.Get()
			if not tryModule("WorldLook", "SetOverride", worldPreview) then
				setStatus(T("admin.moduleMissing", "WorldLook"), Theme.Down)
			else
				setStatus(T("admin.lookSet", worldPreview or T("admin.auto")), Theme.Up)
			end
		end)
		button(lookRow, T("admin.auto"), "Ghost", part(0.25), function()
			worldPreview = nil
			lookCycler.Set(nil)
			tryModule("WorldLook", "SetOverride", nil)
			setStatus(T("admin.lookSet", T("admin.auto")), Theme.Up)
		end)
		UI.Slider(page, 3, T("admin.traffic"), 0, 200, 100, function(value: number)
			if tryModule("CityLife", "SetDensity", value / 100) then
				setStatus(T("admin.trafficSet", value), Theme.Up)
			end
		end)
		UI.Section(page, T("admin.secWorldEvents"), 4)
		local grid = UI.Grid(page, 5, 122, 40)
		for _, kind in ipairs({ "Truck", "Drones", "BuildBoom", "Press", "BellMoment", "SkyShow", "Bear", "GoldenBull" }) do
			button(grid, T("admin.world." .. kind), "Secondary", UDim2.fromScale(1, 1), function()
				admin("WorldEvent", { Event = kind })
			end)
		end
		textLine(page, T("admin.worldHint"), 6, Theme.Muted)
	end

	-- =================================================================
	-- 8) LIVE-OPS (AT_Live_v1, geprüft + geklemmt, Notschalter)
	-- =================================================================
	do
		local page = pages.Live
		local headRow = UI.Row(page, 1, 40)
		local info = UI.Label({
			Size = UDim2.new(0.7, -6, 1, 0),
			Text = T("admin.liveHint"),
			Font = UI.Fonts.Body,
			TextColor3 = Theme.Text2,
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxText = 14,
			LayoutOrder = 2,
			Parent = headRow,
		})
		local list = listFrame(page, 3)
		local function load()
			local result = admin("LiveGet")
			if not result or not result.Ok or type(result.Data) ~= "table" then
				return
			end
			local d = result.Data
			info.Text =
				T("admin.liveInfo", num(d.Version, 0), fmtTime(d.At), if d.Local then T("admin.liveLocalOnly") else "")
			clearChildren(list)
			local current = if type(d.Current) == "table" then d.Current else {}
			for i, spec in ipairs(if type(d.Specs) == "table" then d.Specs else {}) do
				if
					type(spec) == "table"
					and type(spec.Path) == "string"
					and not string.find(spec.Path, "*", 1, true)
				then
					local card = UI.RowCard(list, i, 46)
					local value = current[spec.Path]
					local shown = if value == nil
						then T("admin.liveDefault")
						elseif type(value) == "table" then table.concat(value :: any, ",")
						else tostring(value)
					local range = if spec.Type == "number"
						then ("%s … %s"):format(tostring(spec.Min), tostring(spec.Max))
						elseif spec.Type == "list" then table.concat(
							if type(spec.Options) == "table" then spec.Options else {},
							","
						)
						else spec.Type
					UI.Label({
						Position = UDim2.fromOffset(12, 4),
						Size = UDim2.new(0.55, -12, 0, 20),
						Text = spec.Path,
						Font = UI.Fonts.Main,
						TextColor3 = Theme.Text,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
						MaxText = 14,
						Parent = card,
					})
					UI.Label({
						Position = UDim2.fromOffset(12, 24),
						Size = UDim2.new(0.55, -12, 0, 16),
						Text = ("%s · %s"):format(shown, range),
						Font = UI.Fonts.Body,
						TextColor3 = if value == nil then Theme.Muted else Theme.Accent,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
						MaxText = 12,
						Parent = card,
					})
					local actions = UI.RowActions(card, 230)
					if spec.Type == "boolean" then
						button(actions, T("admin.on"), "Primary", UDim2.new(0, 70, 1, 0), function()
							admin("LiveSet", { Path = spec.Path, Value = true })
							task.delay(0.3, load)
						end)
						button(actions, T("admin.off"), "Secondary", UDim2.new(0, 70, 1, 0), function()
							admin("LiveSet", { Path = spec.Path, Value = false })
							task.delay(0.3, load)
						end)
					else
						local box = UI.TextBox({
							Size = UDim2.new(0, 110, 1, 0),
							PlaceholderText = T("admin.value"),
							Text = "",
							Font = UI.Fonts.Body,
							Parent = actions,
						})
						button(actions, T("admin.setBtn"), "Primary", UDim2.new(0, 60, 1, 0), function()
							local raw = box.Text
							local valueToSend: any
							if spec.Type == "list" then
								local items: { string } = {}
								for item in string.gmatch(raw, "[^,%s]+") do
									table.insert(items, item)
								end
								valueToSend = items
							else
								valueToSend = tonumber(raw)
							end
							if valueToSend == nil then
								setStatus(T("core.invalid"), Theme.Down)
								return
							end
							if needsConfirm("Live" .. spec.Path, spec.Path) then
								return
							end
							admin("LiveSet", { Path = spec.Path, Value = valueToSend })
							task.delay(0.3, load)
						end)
					end
					button(actions, "↺", "Ghost", UDim2.new(0, 40, 1, 0), function()
						admin("LiveSet", { Path = spec.Path, Clear = true })
						task.delay(0.3, load)
					end)
				end
			end
		end
		local loadBtn = button(headRow, T("admin.refresh"), "Secondary", part(0.3), load)
		loadBtn.Frame.LayoutOrder = 1
		onTabOpen.Live = load

		UI.Section(page, T("admin.secEmergency"), 10)
		local productRow = UI.Row(page, 11, 40)
		local productCycler: any = nil
		local shopKeys: { string } = {}
		for _, l in ipairs({ Config.Shop and Config.Shop.Products, Config.Shop and Config.Shop.GamePasses }) do
			for _, key in ipairs(keysOf(l)) do
				table.insert(shopKeys, key)
			end
		end
		productCycler = UI.Cycler(productRow, T("admin.product"), shopKeys, part(0.4))
		button(productRow, T("admin.productOff"), "Danger", part(0.3), function()
			local key = productCycler.Get()
			if not key or needsConfirm("ProductOff" .. key, T("admin.productOff")) then
				return
			end
			admin("LiveSet", { Path = "Shop.Disabled." .. key, Value = true })
		end)
		button(productRow, T("admin.productOn"), "Success", part(0.3), function()
			local key = productCycler.Get()
			if key then
				admin("LiveSet", { Path = "Shop.Disabled." .. key, Clear = true })
			end
		end)
		local boostRow = UI.Row(page, 12, 40)
		button(boostRow, T("admin.boostPause"), "Danger", part(0.5), function()
			if needsConfirm("BoostPause", T("admin.boostPause")) then
				return
			end
			admin("LiveSet", { Path = "Events.BoostPause", Value = true })
		end)
		button(boostRow, T("admin.boostResume"), "Success", part(0.5), function()
			admin("LiveSet", { Path = "Events.BoostPause", Clear = true })
		end)
		local bannerRow = UI.Row(page, 13, 40)
		local bannerBox = textBox(bannerRow, T("admin.bannerHint"), part(0.5))
		button(bannerRow, T("admin.bannerSet"), "Premium", part(0.25), function()
			if needsConfirm("Banner", T("admin.bannerSet")) then
				return
			end
			admin("LiveBanner", { Text = bannerBox.Text })
		end)
		button(bannerRow, T("admin.bannerOff"), "Ghost", part(0.25), function()
			admin("LiveBanner", { Text = "" })
		end)
		UI.Section(page, T("admin.secCodes"), 14)
		local codeRow = UI.Row(page, 15, 40)
		local codeBox = textBox(codeRow, T("admin.codeHint"), part(0.3))
		local codeCredits = textBox(codeRow, T("admin.creditsHint"), part(0.25))
		local codeExpires = textBox(codeRow, T("admin.expiresHint"), part(0.25))
		button(codeRow, T("admin.setBtn"), "Primary", part(0.2), function()
			local code = string.upper(codeBox.Text)
			local credits = tonumber(codeCredits.Text)
			if code == "" or not credits then
				setStatus(T("core.invalid"), Theme.Down)
				return
			end
			local value: { [string]: any } = { Grant = { Credits = math.floor(credits) } }
			if codeExpires.Text ~= "" then
				value.Expires = codeExpires.Text
			end
			if needsConfirm("Code" .. code, code) then
				return
			end
			admin("LiveSet", { Path = "Rewards.Codes." .. code, Value = value })
		end)
	end

	-- =================================================================
	-- 9) STATISTIK
	-- =================================================================
	do
		local page = pages.Stats
		local row = tiles(page, 1)
		local kpiOnline = UI.StatTile(row, T("admin.kpiOnline"), 1)
		local kpiGlobal = UI.StatTile(row, T("admin.kpiGlobal"), 2)
		local kpiFills = UI.StatTile(row, T("admin.kpiFills"), 3)
		local kpiAudit = UI.StatTile(row, T("admin.kpiAudit"), 4)
		local actRow = UI.Row(page, 2, 40)
		local out: Frame
		local function load()
			setStatus(T("core.loading"), Theme.Text2)
			local result = admin("Stats")
			if not result or not result.Ok or type(result.Data) ~= "table" then
				return
			end
			local d = result.Data
			kpiOnline.Text = tostring(num(d.Online, 0))
			kpiGlobal.Text = ("%d · %d"):format(num(d.GlobalPlayers, 0), num(d.Servers, 0))
			kpiFills.Text = tostring(num(d.FillsPerMin, 0))
			local audit = if type(d.Audit) == "table" then d.Audit else {}
			kpiAudit.Text = ("%d / %d"):format(num(audit.Failed, 0), num(audit.Checked, 0))
			kpiAudit.TextColor3 = if num(audit.Failed, 0) > 0 then Theme.Down else Theme.Text
			local lines: { string } = {
				T("admin.statsMoney", fmtCredits(d.Credits), fmtAky(d.AkyCents)),
			}
			local today = if type(d.Today) == "table" then d.Today else {}
			local yesterday = if type(d.Yesterday) == "table" then d.Yesterday else {}
			table.insert(
				lines,
				T(
					"admin.statsPurchases",
					num(today.Count, 0),
					num(today.Robux, 0),
					num(yesterday.Count, 0),
					num(yesterday.Robux, 0)
				)
			)
			if d.Local then
				table.insert(lines, T("admin.statsLocal"))
			end
			if type(d.Traded) == "table" and #d.Traded > 0 then
				local parts: { string } = {}
				for _, e in ipairs(d.Traded) do
					if type(e) == "table" then
						table.insert(parts, ("%s ×%d"):format(tickerOf(e.I), num(e.N, 0)))
					end
				end
				table.insert(lines, T("admin.statsTraded", table.concat(parts, " · ")))
			end
			local ac = if type(d.AntiCheat) == "table" then d.AntiCheat else {}
			table.insert(
				lines,
				T("admin.statsAc", num(ac.Tracked, 0), num(ac.Flags, 0), num(ac.Reports, 0), num(ac.Kicks, 0))
			)
			local ev = if type(d.Events) == "table" then d.Events else {}
			table.insert(
				lines,
				T("admin.statsEvents", num(ev.Started, 0), num(ev.Pickups, 0), num(ev.Rejected, 0), num(ev.BearWins, 0))
			)
			if type(d.Suspicious) == "table" then
				for _, s in ipairs(d.Suspicious) do
					if type(s) == "table" then
						table.insert(
							lines,
							T("admin.statsSuspicious", tostring(s.Name), tostring(s.UserId), num(s.Score, 0))
						)
					end
				end
			end
			table.insert(lines, T("admin.statsSinks"))
			showLines(out, lines)
		end
		button(actRow, T("admin.refresh"), "Secondary", part(0.3), load)
		out = outputBox(page, 3)
		onTabOpen.Stats = load
	end

	-- =================================================================
	-- 10) MODERATION (Flags, Meldungen, Bann-Log, Admin-Log)
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
				if i > 80 then
					break
				end
				if type(e) ~= "table" then
					continue
				end
				if kind == "AdminLog" then
					textLine(
						list,
						T(
							"admin.logLine",
							fmtTime(e.T),
							tostring(e.Name),
							tostring(e.Action),
							if e.Ok then "✔" else "✖",
							tostring(e.Msg or "")
						),
						i,
						if e.Ok then Theme.Text2 else Theme.Warn
					)
					continue
				end
				if kind == "BanList" then
					textLine(
						list,
						T(
							"admin.banLine",
							tostring(e.Name),
							tostring(e.UserId),
							fmtTime(e.T),
							tostring(e.Duration),
							tostring(e.Reason),
							if e.Active then "" else " ✔"
						),
						i,
						Theme.Text2
					)
					continue
				end
				local text
				if kind == "Flags" then
					local reasons = if type(e.Reasons) == "table" then table.concat(e.Reasons, ", ") else ""
					text = T(
						"admin.flagLine",
						tostring(e.Name),
						tostring(e.UserId),
						num(e.Score, 0),
						reasons,
						fmtTime(e.T)
					)
				else
					local snap = if type(e.Snapshot) == "table" then e.Snapshot else {}
					text = T(
						"admin.reportLine",
						tostring(e.FromName),
						tostring(e.Name),
						T("admin.reason." .. tostring(e.Reason)),
						tostring(snap.Score or "?"),
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
		button(row, T("admin.flagsBtn"), "Secondary", part(0.25), function()
			load("Flags")
		end)
		button(row, T("admin.reportsBtn"), "Secondary", part(0.25), function()
			load("Reports")
		end)
		button(row, T("admin.banListBtn"), "Secondary", part(0.25), function()
			load("BanList")
		end)
		button(row, T("admin.adminLogBtn"), "Secondary", part(0.25), function()
			load("AdminLog")
		end)
		onTabOpen.Mod = function()
			load(mode)
		end
	end

	-- =================================================================
	-- 11) DEBUG
	-- =================================================================
	do
		local page = pages.Debug
		local products: { string } = keysOf(Config.Shop and Config.Shop.Products)
		for _, key in ipairs(keysOf(Config.Shop and Config.Shop.GamePasses)) do
			table.insert(products, key)
		end
		UI.Section(page, T("admin.secShopTest"), 1)
		local buyRow = UI.Row(page, 2, 40)
		local productCycler = UI.Cycler(buyRow, T("admin.product"), products, part(0.6))
		button(buyRow, T("admin.simPurchase"), "Primary", part(0.4), function()
			admin("SimulatePurchase", { ProductKey = productCycler.Get() })
		end)
		local policyRow = UI.Row(page, 3, 40)
		local fieldCycler =
			UI.Cycler(policyRow, T("admin.policyField"), { "Random", "Trading", "Subscription" }, part(0.31))
		button(policyRow, T("admin.policyAllowedBtn"), "Secondary", part(0.23), function()
			admin("SimulatePolicy", { Field = fieldCycler.Get(), Allowed = true })
		end)
		button(policyRow, T("admin.policyRestrictedBtn"), "Secondary", part(0.23), function()
			admin("SimulatePolicy", { Field = fieldCycler.Get(), Allowed = false })
		end)
		button(policyRow, T("admin.policyAutoBtn"), "Ghost", part(0.23), function()
			admin("SimulatePolicy", { Field = fieldCycler.Get() })
		end)
		UI.Section(page, T("admin.secTools"), 4)
		local toolRow = UI.Row(page, 5, 40)
		button(toolRow, T("admin.skipDay"), "Secondary", part(0.33), function()
			admin("SkipDay")
		end)
		button(toolRow, T("admin.selfTestBtn"), "Primary", part(0.33), function()
			admin("RunSelfTest")
		end)
		button(toolRow, T("admin.debugOverlay"), "Secondary", part(0.34), function()
			tryModule("DebugOverlay", "Toggle")
		end)
		local flagRow = UI.Row(page, 6, 40)
		for _, info in ipairs({
			{ Key = "LogRejects", Label = "admin.dbgRejects" },
			{ Key = "ForceRestricted", Label = "admin.dbgRestricted" },
			{ Key = "ShowTriggers", Label = "admin.dbgTriggers" },
		}) do
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
		local probeRow = UI.Row(page, 7, 40)
		button(probeRow, T("admin.crashProbe"), "Danger", part(0.5), function()
			-- Crash-Freitag-Probe (lokal): Bär auf diesem Server + roter Himmel nur bei dir, kein Markteinfluss
			local result = admin("WorldEvent", { Event = "Bear", Probe = true })
			if result and result.Ok then
				tryModule("WorldLook", "SetOverride", "Crash")
				task.delay(20, function()
					if worldPreview == nil then
						tryModule("WorldLook", "SetOverride", nil)
					end
				end)
			end
		end)
		button(probeRow, T("admin.rallyProbe"), "Success", part(0.5), function()
			local result = admin("WorldEvent", { Event = "GoldenBull" })
			if result and result.Ok then
				tryModule("WorldLook", "SetOverride", "Rally")
				task.delay(20, function()
					if worldPreview == nil then
						tryModule("WorldLook", "SetOverride", nil)
					end
				end)
			end
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
	-- Taste P (über Controls, sonst direkt) + X beendet das Zuschauen
	local controls = module("Controls")
	local bound = false
	if controls and type(controls.Bind) == "function" then
		bound = pcall(controls.Bind, "AdminPanel", function(state: string)
			if state == "Begin" then
				AdminPanel.Toggle()
			end
		end)
		pcall(controls.Bind, "Spectate", function(state: string)
			if state == "Begin" and spectating then
				stopSpectate()
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
		elseif not bound and input.KeyCode == spectateKey and spectating then
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
