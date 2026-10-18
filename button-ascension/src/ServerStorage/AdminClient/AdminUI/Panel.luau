--[[
	Panel (ModuleScript)
	Location: ServerStorage/AdminClient/AdminUI/Panel
	Depends on: AdminUI/Widgets, AdminUI/AdminNet, AdminUI/CommandBar, AdminUI/Tabs/*,
	            ReplicatedStorage/Shared/Signal, ReplicatedStorage/UI/SoundPlayer

	Builds the admin panel shell: floating toggle button, window with role
	badge, sidebar with the eight tabs, command bar + console, in-panel
	toasts, F2 / gamepad / "/admin" chat shortcuts and the refresh loop.
	Tabs are built lazily the first time they are opened and only the visible
	tab refreshes.
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Signal"))
local SoundPlayer = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("SoundPlayer"))

local Widgets = require(script.Parent.Widgets)
local AdminNet = require(script.Parent.AdminNet)
local CommandBar = require(script.Parent.CommandBar)
local TabModules = script.Parent:WaitForChild("Tabs")

local UI = Widgets.UI
local Theme = Widgets.Theme
local P = Widgets.P
local F = Theme.Fonts

local Panel = {}

local TABS = {
	{ Id = "Dashboard", Name = "Dashboard", Icon = "📊", Any = { "panel.open" } },
	{ Id = "Players", Name = "Players", Icon = "👥", Any = { "players.view" } },
	{ Id = "Economy", Name = "Economy", Icon = "💰", Any = { "economy.grant", "economy.reset" } },
	{ Id = "Items", Name = "Items", Icon = "🎁", Any = { "items.grant", "items.test", "players.inspect" } },
	{ Id = "Progression", Name = "Progression", Icon = "📈", Any = { "progression.grant", "progression.reset" } },
	{ Id = "Server", Name = "Server", Icon = "🖥️", Any = { "server.announce", "server.events", "server.stats" } },
	{ Id = "Logs", Name = "Audit Logs", Icon = "📜", Any = { "logs.view" } },
	{ Id = "Settings", Name = "Settings", Icon = "⚙️", Any = {} },
}

local function makeContext(gui: ScreenGui, hello)
	local permissions = {}
	for _, p in ipairs(hello.Permissions or {}) do
		permissions[p] = true
	end
	local ctx = {
		Gui = gui,
		Hello = hello,
		Net = AdminNet,
		W = Widgets,
		UI = UI,
		P = P,
		Target = { Query = nil, Label = "" },
		TargetChanged = Signal.new(),
		Players = {},
		PlayersUpdated = Signal.new(),
		LogPushed = Signal.new(),
		Prefs = { ToastSounds = true, Compact = false, AutoRefresh = true },
		PrefsChanged = Signal.new(),
	}
	function ctx.has(permission: string): boolean
		return permissions["*"] == true or permissions[permission] == true
	end
	function ctx.setTarget(query: any, label: string?, source: any?)
		ctx.Target = { Query = query, Label = label or "" }
		ctx.TargetChanged:Fire(source)
	end
	function ctx.refreshPlayers()
		local action = if ctx.has("players.view") then "players.list" else "dashboard"
		local response = AdminNet.request(action)
		if response.ok and type(response.data) == "table" and type(response.data.Players) == "table" then
			ctx.Players = response.data.Players
			ctx.PlayersUpdated:Fire()
		end
		return ctx.Players
	end
	return ctx
end

function Panel.build(gui: ScreenGui, hello)
	local ctx = makeContext(gui, hello)
	local roleColor = if typeof(hello.RoleColor) == "Color3" then hello.RoleColor else P.Accent

	-- Floating layer: toggle button + toasts (scaled to the screen) ------------------
	-- Above the window (ZIndex 10) so the toggle and toasts stay reachable; transparent frames do not block clicks.
	local floating = UI.frame({ Name = "Floating", ZIndex = 15, Parent = gui })
	local inset = GuiService:GetGuiInset()

	-- The button keeps its own press-animation UIScale, so layout scaling lives on a holder.
	local toggleHolder = UI.frame({
		Name = "AdminToggleHolder",
		Size = UDim2.fromOffset(112, 34),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, inset.Y + 10),
		ZIndex = 6,
		Parent = floating,
	})
	local toggle = Widgets.button({
		Name = "AdminToggle",
		Text = "🛡️ Admin",
		Variant = "adminPrimary",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
		Tooltip = `Admin panel ({hello.PanelKey or "F2"})`,
		Parent = toggleHolder,
	})

	local toasts = UI.frame({
		Name = "Toasts",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, inset.Y + 54),
		Size = UDim2.fromOffset(330, 400),
		ZIndex = 80,
		List = { Pad = 6, HA = "Right" },
		Parent = floating,
	})

	-- Scale each right-anchored element on its own: a UIScale on the full-screen
	-- frame would scale from the top-left corner and push them off-screen.
	local floatScales = {}
	for _, element in ipairs({ toggleHolder, toasts }) do
		local s = Instance.new("UIScale")
		s.Parent = element
		table.insert(floatScales, s)
	end
	local function rescaleFloating()
		local v = UI.viewport()
		local scale = math.clamp(math.min(v.X / 1280, v.Y / 720), 0.75, 1.2)
		for _, s in ipairs(floatScales) do
			s.Scale = scale
		end
	end
	rescaleFloating()
	UI.onViewportChanged(rescaleFloating)

	local toastCount = 0
	function ctx.toast(text: string, kind: string?)
		toastCount += 1
		local color = if kind == "error" then P.Danger elseif kind == "warn" then P.Warning else P.Accent
		local firstLine = string.match(text, "^[^\n]*") or text
		local card = UI.new("Frame", {
			Name = "Toast",
			Size = UDim2.fromOffset(320, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = P.Panel,
			LayoutOrder = toastCount,
			ZIndex = 81,
			Corner = 10,
			Stroke = { Color = color, Thickness = 1.5 },
			Padding = { 12, 12, 9, 9 },
			Parent = toasts,
		})
		UI.new("Frame", {
			Size = UDim2.new(0, 3, 1, 0),
			Position = UDim2.fromOffset(-8, 0),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = 82,
			Corner = 2,
			Parent = card,
		})
		Widgets.label({
			Text = firstLine,
			TextWrapped = true,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 16),
			TextSize = 14,
			TextColor3 = P.Text,
			ZIndex = 82,
			Parent = card,
		})
		local scale = Instance.new("UIScale")
		scale.Scale = 0.9
		scale.Parent = card
		UI.tween(scale, { Scale = 1 }, Theme.Motion.Pop)
		if ctx.Prefs.ToastSounds then
			SoundPlayer.play(if kind == "error" then "Error" else "Purchase", { Volume = 0.6 })
		end
		task.delay(4, function()
			if card.Parent then
				local t = UI.tween(scale, { Scale = 0.85 }, Theme.Motion.Fast)
				if t then
					t.Completed:Wait()
				end
				card:Destroy()
			end
		end)
		local cards = {}
		for _, child in ipairs(toasts:GetChildren()) do
			if child:IsA("Frame") then
				table.insert(cards, child)
			end
		end
		if #cards > 5 then
			table.sort(cards, function(a, b)
				return a.LayoutOrder < b.LayoutOrder
			end)
			cards[1]:Destroy()
		end
	end

	-- Window ------------------------------------------------------------------------------------
	local window = UI.window({
		Parent = gui,
		Name = "AdminWindow",
		Title = "Admin Panel",
		Subtitle = "Click a Button · staff tools · every action is validated and logged by the server",
		Icon = "🛡️",
		Size = Vector2.new(1140, 700),
		CompactSize = Vector2.new(940, 590),
		Palette = P,
		Accent = P.Accent,
	})
	ctx.Window = window
	UI.setVariant(window.CloseButton, "adminGhost")

	local badge = UI.label({
		Name = "RoleBadge",
		Text = "ADMIN • " .. string.upper(tostring(hello.Role)),
		Font = F.Heading,
		TextSize = 13,
		TextColor3 = roleColor,
		TextXAlignment = Enum.TextXAlignment.Center,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 28),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -52, 0, 6),
		BackgroundColor3 = Theme.darken(roleColor, 0.78),
		BackgroundTransparency = 0,
		ZIndex = 13,
		Corner = Theme.Radius.Pill,
		Padding = { X = 14 },
		Parent = window.Header,
	})
	UI.stroke(badge, { Color = roleColor, Thickness = 1.5 })

	local body = window.Body
	local sidebar = UI.new("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, 178, 1, 0),
		BackgroundColor3 = P.Background,
		ZIndex = 12,
		Corner = 12,
		Stroke = { Color = P.Stroke, Transparency = 0.4 },
		Padding = 8,
		Parent = body,
	})
	local tabList = UI.frame({ Name = "TabList", Size = UDim2.new(1, 0, 1, -48), ZIndex = 12, List = { Pad = 6 }, Parent = sidebar })
	local sideInfo = Widgets.dim({
		Name = "Info",
		Text = `{hello.Role} · server {Widgets.shortId(hello.JobId)}`,
		TextSize = 11,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.new(0, 0, 1, -40),
		ZIndex = 12,
		Parent = sidebar,
	})

	local main = UI.frame({ Name = "Main", Position = UDim2.fromOffset(190, 0), Size = UDim2.new(1, -190, 1, 0), ZIndex = 12, Parent = body })
	local commandBar = CommandBar.new(ctx, main)
	ctx.Console = commandBar
	function ctx.log(text: string, kind: string?)
		commandBar.Log(text, kind)
	end
	local content = UI.frame({ Name = "Content", Position = UDim2.fromOffset(0, 160), Size = UDim2.new(1, 0, 1, -160), ZIndex = 12, Parent = main })

	AdminNet.setReporter(function(response, label)
		local prefix = if label then label .. ": " else ""
		if response.cancelled then
			ctx.log(prefix .. "cancelled.", "warn")
			return
		end
		if response.ok then
			local message = response.message or "Done."
			ctx.log(prefix .. message, "ok")
			ctx.toast("✔ " .. message, "ok")
		else
			local message = response.err or "Failed."
			ctx.log(prefix .. message, "error")
			ctx.toast("✖ " .. message, "error")
		end
	end)

	-- Tabs ------------------------------------------------------------------------------------------
	local tabButtons: { [string]: TextButton } = {}
	local tabs: { [string]: any } = {}
	local containers: { [string]: Frame } = {}
	local current: string? = nil
	local compact = false

	local function allowed(def): boolean
		if #def.Any == 0 then
			return true
		end
		for _, permission in ipairs(def.Any) do
			if ctx.has(permission) then
				return true
			end
		end
		return false
	end

	local function tabText(def): string
		return if compact then def.Icon else def.Icon .. "  " .. def.Name
	end

	local function ensureTab(id: string)
		if tabs[id] then
			return tabs[id]
		end
		local container = UI.frame({ Name = id, Visible = false, ZIndex = 12, Parent = content })
		containers[id] = container
		local module = TabModules:FindFirstChild(id)
		local ok, result = pcall(function()
			return require(module)(ctx, container)
		end)
		if not ok then
			warn("[AdminPanel] Tab " .. id .. " failed to build: " .. tostring(result))
			Widgets.label({ Text = "This tab failed to load: " .. tostring(result), TextColor3 = P.Danger, TextWrapped = true, Size = UDim2.new(1, 0, 0, 60), Parent = container })
			result = {}
		end
		tabs[id] = result
		return result
	end

	function ctx.switchTab(id: string, ...: any)
		if current == id and tabs[id] then
			if tabs[id].OnShow then
				task.spawn(tabs[id].OnShow, ...)
			end
			return
		end
		if current then
			if containers[current] then
				containers[current].Visible = false
			end
			if tabs[current] and tabs[current].OnHide then
				task.spawn(tabs[current].OnHide)
			end
		end
		current = id
		for tabId, button in pairs(tabButtons) do
			UI.setVariant(button, if tabId == id then "adminPrimary" else "adminGhost")
		end
		local tab = ensureTab(id)
		containers[id].Visible = true
		tab.Elapsed = 0
		if tab.OnShow then
			task.spawn(tab.OnShow, ...)
		end
	end

	for index, def in ipairs(TABS) do
		if allowed(def) then
			local button = Widgets.button({
				Name = def.Id,
				Text = tabText(def),
				Size = UDim2.new(1, 0, 0, 40),
				TextXAlignment = Enum.TextXAlignment.Left,
				Padding = { X = 12 },
				LayoutOrder = index,
				Variant = "adminGhost",
				ZIndex = 13,
				OnClick = function()
					ctx.switchTab(def.Id)
				end,
				Parent = tabList,
			})
			tabButtons[def.Id] = button
		end
	end

	local function applyCompact()
		compact = window.Root:GetAttribute("Compact") == true or ctx.Prefs.Compact
		local sideWidth = if compact then 58 else 178
		sidebar.Size = UDim2.new(0, sideWidth, 1, 0)
		sideInfo.Visible = not compact
		main.Position = UDim2.fromOffset(sideWidth + 12, 0)
		main.Size = UDim2.new(1, -(sideWidth + 12), 1, 0)
		commandBar.SetCompact(compact)
		local top = if compact then 120 else 160
		content.Position = UDim2.fromOffset(0, top)
		content.Size = UDim2.new(1, 0, 1, -top)
		for _, def in ipairs(TABS) do
			local button = tabButtons[def.Id]
			if button then
				button.Text = tabText(def)
				button.TextXAlignment = if compact then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
			end
		end
	end
	window.Root:GetAttributeChangedSignal("Compact"):Connect(applyCompact)
	ctx.PrefsChanged:Connect(applyCompact)
	applyCompact()

	-- Open / close ----------------------------------------------------------------------------------
	local function setOpen(open: boolean)
		if open then
			window.Open()
		else
			task.spawn(window.Close)
		end
	end
	function ctx.IsOpen(): boolean
		return window.IsOpen()
	end

	toggle.Activated:Connect(function()
		setOpen(not window.IsOpen())
	end)

	window.Opened.Event:Connect(function()
		UI.setText(toggle, "Close", "🛡️")
		if not current then
			ctx.switchTab("Dashboard")
		elseif tabs[current] and tabs[current].OnShow then
			task.spawn(tabs[current].OnShow)
		end
		ContextActionService:BindActionAtPriority("AdminPanelBack", function(_, state)
			if state == Enum.UserInputState.Begin then
				setOpen(false)
			end
			return Enum.ContextActionResult.Sink
		end, false, 3000, Enum.KeyCode.ButtonB)
	end)
	window.Closed.Event:Connect(function()
		UI.setText(toggle, "Admin", "🛡️")
		Widgets.closePopup()
		ContextActionService:UnbindAction("AdminPanelBack")
	end)

	local panelKey = Enum.KeyCode.F2
	local okKey, key = pcall(function()
		return (Enum.KeyCode :: any)[hello.PanelKey or "F2"]
	end)
	if okKey and typeof(key) == "EnumItem" then
		panelKey = key
	end
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == panelKey then
			setOpen(not window.IsOpen())
		end
	end)

	-- "/admin ..." in chat. TextChatCommands only trigger with TextChatService chat; with
	-- legacy chat the command simply never fires and the panel's command bar still works.
	pcall(function()
		local command = Instance.new("TextChatCommand")
		command.Name = "AdminPanelCommand"
		command.PrimaryAlias = "/admin"
		command.Triggered:Connect(function(_source, text)
			task.spawn(function()
				ctx.log("> " .. text .. "   (from chat)", "command")
				AdminNet.command(text)
			end)
		end)
		command.Parent = TextChatService:FindFirstChild("TextChatCommands") or TextChatService
	end)

	-- Live pushes ------------------------------------------------------------------------------------
	AdminNet.onPush(function(kind, payload)
		if kind == "log" and type(payload) == "table" then
			ctx.LogPushed:Fire(payload)
		end
	end)

	-- Refresh loop: only the visible tab, only while the panel is open. -------------------------------
	task.spawn(function()
		while gui.Parent do
			task.wait(1)
			local tab = current and tabs[current]
			if tab and window.IsOpen() then
				if tab.Tick then
					task.spawn(tab.Tick)
				end
				if tab.AutoRefresh and tab.Refresh and ctx.Prefs.AutoRefresh then
					tab.Elapsed = (tab.Elapsed or 0) + 1
					if tab.Elapsed >= tab.AutoRefresh and not tab.Refreshing then
						tab.Elapsed = 0
						tab.Refreshing = true
						task.spawn(function()
							pcall(tab.Refresh)
							tab.Refreshing = false
						end)
					end
				end
			end
		end
	end)

	ctx.log(`Signed in as {hello.Role} (rank {hello.Rank}). {#(hello.Commands or {})} commands available.`, "ok")
	ctx.toast(`Admin panel ready — press {hello.PanelKey or "F2"} or tap 🛡️ Admin.`, "ok")
	return ctx
end

return Panel
