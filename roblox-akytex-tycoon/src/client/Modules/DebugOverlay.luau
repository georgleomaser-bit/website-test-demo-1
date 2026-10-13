-- =====================================================================
--  AKYTEX TYCOON – Debug-Anzeige F8 (Client/Modules/DebugOverlay)
--  Besitzer: WP11 (Admin, Events, Anti-Cheat). Vertrag: DESIGN.md §C16 (DebugOverlay-Werte), §B15.2 (Tab Debug),
--  REUSE §1.4 (CC-DebugOverlay ADAPT: Glas-Karte, Abfrage 1×/s nur solange sichtbar, Scheduler-Statistik + teuerste
--  Takte, Speicher, FPS/Ping, Ersatz-Farben falls das UI-Kit fehlt – REUSE §7 #38; Arena/Bots/Projektile ersetzt).
--  Nur für den Besitzer (Modul lädt nur bei IsAdmin; der Server prüft "ServerInfo" trotzdem erneut).
--  Zeigt (§C16): Markt-Tick-ms, Frames/s, Teilezahl (Server: Stadt + Tower), Live-Monitore, Scheduler-Top-5,
--  Speicher (Server + Client), Ping – dazu Quotes/s, Frame-Größe, Bus-Status, Tower, offene Pickups, Grafikstufe.
--  Look: Glas-Karte (Surface, 1-px-Rahmen, Ecke 12), Titel Michroma + Akzent-Strich, Werte BuilderMono/RobotoMono.
--
--  Öffentliche API (§C7.5):
--    DebugOverlay.Toggle()
--    DebugOverlay.Init(ctx) / DebugOverlay.Start()
-- =====================================================================

local Players = game:GetService("Players")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")

local DebugOverlay = {}

local player = Players.LocalPlayer
local ctx: any = nil

local POLL_SECONDS = 1
-- AKYTEX-Farben als Ersatz, falls das UI-Kit fehlt (sonst UI.Theme)
local FALLBACK_THEME = {
	Surface = Color3.fromRGB(18, 24, 36),
	Border = Color3.fromRGB(31, 41, 55),
	Text = Color3.fromRGB(230, 236, 245),
	Text2 = Color3.fromRGB(170, 180, 195),
	Accent = Color3.fromRGB(79, 140, 255),
	Up = Color3.fromRGB(34, 197, 94),
	Warn = Color3.fromRGB(234, 179, 8),
	Down = Color3.fromRGB(239, 68, 68),
}

local visible = false
local hiddenByPhoto = false
local frame: Frame? = nil
local lines: TextLabel? = nil
local titleLabel: TextLabel? = nil
local statusDot: Frame? = nil
local pollToken = 0
local lastInfo: { [string]: any }? = nil
local lastAt = 0

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

local function formatTime(seconds: number): string
	local util = ctx and ctx.Util
	if util and type(util.FormatTime) == "function" then
		local ok, text = pcall(util.FormatTime, seconds)
		if ok and type(text) == "string" then
			return text
		end
	end
	return ("%ds"):format(math.floor(seconds))
end

local function theme(): { [string]: Color3 }
	local ui = ctx and ctx.UI
	local t = ui and ui.Theme
	return if type(t) == "table" then t else FALLBACK_THEME
end

local function color(key: string): Color3
	local th = theme()
	local value = th[key]
	return if typeof(value) == "Color3" then value else (FALLBACK_THEME :: any)[key]
end

local function build()
	if frame then
		return
	end
	local parent = ctx and ctx.Gui
	if typeof(parent) ~= "Instance" then
		return
	end
	local box = Instance.new("Frame")
	box.Name = "AT_DebugOverlay"
	box.Position = UDim2.fromOffset(12, 140)
	box.Size = UDim2.fromOffset(440, 0)
	box.AutomaticSize = Enum.AutomaticSize.Y
	box.BackgroundColor3 = color("Surface")
	box.BackgroundTransparency = 0.1
	box.BorderSizePixel = 0
	box.ZIndex = 50
	box.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = box
	local stroke = Instance.new("UIStroke")
	stroke.Color = color("Border")
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = box
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.Parent = box
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = box
	local head = Instance.new("Frame")
	head.Name = "Head"
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, 0, 0, 18)
	head.LayoutOrder = 1
	head.ZIndex = 51
	head.Parent = box
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -20, 1, 0)
	title.Font = Enum.Font.Michroma
	title.TextSize = 13
	title.TextColor3 = color("Text")
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = T("admin.dbgTitle")
	title.ZIndex = 51
	title.Parent = head
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(1, 0.5)
	dot.Position = UDim2.new(1, 0, 0.5, 0)
	dot.Size = UDim2.fromOffset(8, 8)
	dot.BackgroundColor3 = color("Up")
	dot.BorderSizePixel = 0
	dot.ZIndex = 51
	dot.Parent = head
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(0.5, 0)
	dotCorner.Parent = dot
	local underline = Instance.new("Frame")
	underline.Name = "Underline"
	underline.Size = UDim2.fromOffset(24, 2)
	underline.BackgroundColor3 = color("Accent")
	underline.BorderSizePixel = 0
	underline.LayoutOrder = 2
	underline.ZIndex = 51
	underline.Parent = box
	local label = Instance.new("TextLabel")
	label.Name = "Lines"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Font = Enum.Font.RobotoMono
	label.TextSize = 13
	label.LineHeight = 1.1
	label.TextColor3 = color("Text2")
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.RichText = false
	label.Text = ""
	label.LayoutOrder = 3
	label.ZIndex = 51
	label.Parent = box
	box.Parent = parent
	frame = box
	lines = label
	titleLabel = title
	statusDot = dot
end

local function clientFps(): number
	local fps = ctx and ctx.Fps
	return if type(fps) == "number" and fps == fps then fps else 60
end

local function render()
	if not lines then
		return
	end
	local out: { string } = {}
	if titleLabel then
		titleLabel.Text = T("admin.dbgTitle")
	end
	local info = lastInfo
	if info then
		table.insert(out, T("admin.dbgHeartbeat", tonumber(info.HeartbeatMs) or 0, tonumber(info.HeartbeatMaxMs) or 0))
		table.insert(
			out,
			T(
				"admin.dbgMarket",
				tonumber(info.MarketTickMs) or 0,
				tonumber(info.Instruments) or 0,
				tonumber(info.FrameBytes) or 0,
				T(if info.BusOk then "admin.on" else "admin.off")
			)
		)
		if type(info.Jobs) == "table" then
			for _, job in ipairs(info.Jobs) do
				if type(job) == "table" then
					table.insert(
						out,
						("  %-22s %5.2f / %5.2f ms"):format(
							string.sub(tostring(job.Name), 1, 22),
							tonumber(job.AvgMs) or 0,
							tonumber(job.MaxMs) or 0
						)
					)
				end
			end
		end
		table.insert(
			out,
			T(
				"admin.dbgCounts",
				tonumber(info.Players) or 0,
				tonumber(info.Towers) or 0,
				tonumber(info.Parts) or 0,
				tonumber(info.Pickups) or 0
			)
		)
		table.insert(out, T("admin.dbgMem", tonumber(info.MemoryMb) or 0, formatTime(tonumber(info.Uptime) or 0)))
	else
		table.insert(out, T("core.loading"))
	end
	-- Client-Seite
	local live, guis, monitors = 0, 0, 0
	local monitorModule = module("Monitors")
	if monitorModule and type(monitorModule.Count) == "function" then
		local ok, a, b, c = pcall(monitorModule.Count)
		if ok then
			live, guis, monitors = tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
		end
	end
	table.insert(out, T("admin.dbgMonitors", live, monitors, guis))
	local okMem, clientMem = pcall(function()
		return Stats:GetTotalMemoryUsageMb()
	end)
	local tier = "?"
	local quality = module("Quality")
	if quality and type(quality.Tier) == "function" then
		local ok, value = pcall(quality.Tier)
		if ok and type(value) == "string" then
			tier = value
		end
	end
	table.insert(
		out,
		T(
			"admin.dbgClient",
			math.floor(clientFps() + 0.5),
			tonumber(player:GetAttribute("PingMs")) or 0,
			if okMem and type(clientMem) == "number" then math.floor(clientMem) else 0,
			tier
		)
	)
	lines.Text = table.concat(out, "\n")
	local dot = statusDot
	if dot then
		local stale = os.clock() - lastAt > POLL_SECONDS * 3
		local heavy = info ~= nil and (tonumber(info.HeartbeatMs) or 0) > 3
		dot.BackgroundColor3 = if stale then color("Down") elseif heavy then color("Warn") else color("Up")
	end
end

local function poll(token: number)
	-- Abfrage-Schleife nur solange sichtbar; endet sofort bei Ausblenden (Token)
	while visible and token == pollToken do
		local remotes = ctx and ctx.Remotes
		local admin = remotes and remotes.Admin
		if admin and admin:IsA("RemoteFunction") then
			local ok, result = pcall(function()
				return admin:InvokeServer("ServerInfo", {})
			end)
			if ok and type(result) == "table" and result.Ok and type(result.Data) == "table" then
				lastInfo = result.Data
				lastAt = os.clock()
			end
		end
		if not visible or token ~= pollToken then
			break
		end
		render()
		task.wait(POLL_SECONDS)
	end
end

local function applyVisible()
	build()
	if frame then
		frame.Visible = visible and not hiddenByPhoto
	end
end

function DebugOverlay.Toggle()
	if player:GetAttribute("IsAdmin") ~= true then
		return
	end
	visible = not visible
	pollToken += 1
	applyVisible()
	if visible then
		render()
		task.spawn(poll, pollToken)
	end
end

function DebugOverlay.Init(context: any)
	ctx = context
end

function DebugOverlay.Start()
	local controls = module("Controls")
	local bound = false
	if controls and type(controls.Bind) == "function" then
		bound = pcall(controls.Bind, "Debug", function(state: string)
			if state == "Begin" then
				DebugOverlay.Toggle()
			end
		end)
	end
	if not bound then
		local key = Enum.KeyCode.F8
		local keys = ctx and ctx.Config and ctx.Config.Client and ctx.Config.Client.Keys
		if keys and type(keys.Debug) == "table" and type(keys.Debug[1]) == "string" then
			local ok, code = pcall(function()
				return (Enum.KeyCode :: any)[keys.Debug[1]]
			end)
			if ok and typeof(code) == "EnumItem" then
				key = code :: any
			end
		end
		UserInputService.InputBegan:Connect(function(input, processed)
			-- F8 wird nie von Roblox-Menüs "verbraucht"; andere Tasten nur, wenn kein Textfeld/Menü sie nimmt
			if input.KeyCode ~= key or UserInputService:GetFocusedTextBox() then
				return
			end
			if processed and key ~= Enum.KeyCode.F8 then
				return
			end
			DebugOverlay.Toggle()
		end)
	end
	local hooks = ctx and ctx.Hooks
	if hooks and type(hooks.On) == "function" then
		hooks.On("PhotoMode", function(on: any)
			hiddenByPhoto = on == true
			applyVisible()
		end)
	end
end

return DebugOverlay
