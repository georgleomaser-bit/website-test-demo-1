-- =====================================================================
--  AKYTEX TYCOON – Willkommen-zurück-Bericht + „Zukunfts-Ich“ (Client/Modules/WelcomeBack)
--  Besitzer: WP8 (Turm-Optik, Interiors, Lifestyle). Vertrag: DESIGN.md §B1 (Rückkehrer: Glas-Sheet, 2 s Vorher/
--  Nachher-Kamera auf den eigenen Tower über zwei ViewportFrames; Tower offline +X CR, Dividenden +Y AKY, ausgeführte
--  Orders, Bots, fertige Bauten, Auto-Transfers; großer Knopf EINSAMMELN mit rollendem Zähler; vor dem Gehen das
--  „Zukunfts-Ich“-Panel: „In 8 h verdient dein Tower ≈ … · deine Orders schützen dich · Etage 21 fertig in 41 min“),
--  §B4.6 (Offline-Ertrag, Auszahlung über die Willkommen-Karte – der Server bucht schon beim Beitritt), §C7.3
--  (Fenster "WelcomeBack"), Muss-Regel 17 (kein Angebot während des Berichts – das Fenster ist dabei offen).
--
--  Quellen: State.Tower.Offline (TowerService: Seconds, Away, Rate, Cap, Amount, Built?, Transfer?) und
--  State.Life.Welcome (LifestyleService aus OrderService.CatchUpReport: Fills, Dividends, Alerts, Bots).
--  Ehrlich: Die CR sind beim Öffnen bereits gutgeschrieben – EINSAMMELN zeigt nur den Zähler-Effekt.
--  „Zukunfts-Ich“: Karte unten beim Öffnen des Roblox-Menüs (GuiService.MenuOpened = man geht gleich) und per Knopf.
--
--  Öffentliche API (§C7.5):
--    WelcomeBack.Show(report)        report = { Offline?, Catchup? } (fehlende Teile aus dem State)
--  Ergänzungen: WelcomeBack.ShowFuture() · WelcomeBack.Tick() (von TowerView 1×/s) · Init(ctx) · Start()
-- =====================================================================

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent:WaitForChild("UI"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local TowerModels = require(Shared:WaitForChild("TowerModels"))
local TowerMath = require(Shared:WaitForChild("TowerMath"))

local WelcomeBack = {}

local Theme = UI.Theme

local WINDOW_W, WINDOW_H = 700, 620
local SHOW_DELAY = 3 -- Sekunden nach dem ersten State (HUD/Splash zuerst)
local WAIT_MAX = 90 -- so lange wird auf ein freies Fenster/Tutorial-Ende gewartet
local FUTURE_HOURS = 8
local FUTURE_GAP = 300 -- Zukunfts-Ich höchstens alle 5 min automatisch
local FUTURE_STAY = 9
local CAMERA_INFO = TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local PROTECTIVE: { [string]: boolean } = { STP = true, TP = true, OCO = true, TRL = true }

local ctx: any = nil
local window: any = nil
local shown = false
local pendingSince: number? = nil
local report: { [string]: any } = {}
local collectAmount = 0
local future: Frame? = nil
local futureLabel: TextLabel? = nil
local futureToken = 0
local futureAt = -math.huge
local builtLang = ""
local filledSig = "" -- Inhalt des zuletzt gebauten Berichts (nur bei echter Änderung neu bauen)

-- ---------------------------------------------------------------------
-- HELFER
-- ---------------------------------------------------------------------
local function call(name: string, fnName: string, ...: any): (boolean, any)
	local modules = ctx and ctx.Modules
	local m = modules and modules[name]
	local fn = m and m[fnName]
	if type(fn) ~= "function" then
		return false, nil
	end
	return pcall(fn, ...)
end

local function T(key: string, ...: any): string
	return ctx.T(key, ...)
end

local function lang(): string
	return ctx.Lang_()
end

local function num(v: any, default: number): number
	return if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then v else default
end

local function credits(n: number): string
	local ok, text = pcall(ctx.Format.Credits, n, lang())
	return if ok then text else tostring(math.floor(n))
end

local function aky(cents: number): string
	local ok, text = pcall(ctx.Format.Aky, cents, lang(), true)
	return if ok then text else tostring(math.floor(cents / 100))
end

local function duration(seconds: number): string
	local ok, text = pcall(ctx.Format.Duration, math.max(0, seconds), lang())
	return if ok then text else tostring(math.floor(seconds))
end

local function pct(fraction: number): string
	local ok, text = pcall(ctx.Format.Pct, fraction, lang(), 1, true)
	return if ok then text else string.format("%+.1f %%", fraction * 100)
end

local function tower(): { [string]: any }
	local t = ctx.State.Tower
	return if type(t) == "table" then t else {}
end

local function botName(preset: string): string
	local trading = ctx.Config.Trading
	local bots = if type(trading) == "table" then trading.Bots else nil
	local entry = if type(bots) == "table" then bots[preset] else nil
	if type(entry) == "table" and type(entry.Name) == "table" then
		return ctx.Lang.Pick(lang(), entry.Name)
	end
	return preset
end

local function reportOf(): ({ [string]: any }, { [string]: any })
	local offline = report.Offline
	if type(offline) ~= "table" then
		local t = tower()
		offline = if type(t.Offline) == "table" then t.Offline else {}
	end
	local catchup = report.Catchup
	if type(catchup) ~= "table" then
		local life = ctx.State.Life
		catchup = if type(life) == "table" and type(life.Welcome) == "table" then life.Welcome else {}
	end
	return offline :: { [string]: any }, catchup :: { [string]: any }
end

local function hasNews(): boolean
	local offline, catchup = reportOf()
	return num(offline.Amount, 0) > 0
		or num(offline.Built, 0) > 0
		or num(offline.Transfer, 0) > 0
		or num(catchup.Fills, 0) > 0
		or num(catchup.Dividends, 0) > 0
		or (type(catchup.Bots) == "table" and #catchup.Bots > 0)
end

-- Bericht-Inhalt als Text: der Tower-State ändert sich laufend (Tresor), der Bericht nur selten
local function reportSig(): string
	local offline, catchup = reportOf()
	local bots = if type(catchup.Bots) == "table" then #catchup.Bots else 0
	return table.concat({
		tostring(num(offline.Amount, 0)),
		tostring(num(offline.Built, 0)),
		tostring(num(offline.Transfer, 0)),
		tostring(num(catchup.Fills, 0)),
		tostring(num(catchup.Dividends, 0)),
		tostring(num(catchup.Alerts, 0)),
		tostring(bots),
		tostring(math.floor(num(tower().Floors, 0))),
		lang(),
	}, "|")
end

-- ---------------------------------------------------------------------
-- VORHER/NACHHER (zwei ViewportFrames mit vereinfachtem Tower, Kamera fährt 2 s)
-- ---------------------------------------------------------------------
local function viewport(parent: Instance, order: number, caption: string, floors: number, highlight: number?): Frame
	local t = tower()
	local stage = TowerModels.StageOf(floors)
	local holder = UI.Card({ Size = UDim2.fromOffset(318, 230), LayoutOrder = order, Parent = parent })
	UI.Label({
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 0, 22),
		Text = caption,
		Face = "Display",
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 15,
		Parent = holder,
	})
	local vp: ViewportFrame = UI.Create("ViewportFrame", {
		Position = UDim2.fromOffset(8, 32),
		Size = UDim2.new(1, -16, 1, -40),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0,
		Ambient = Color3.fromRGB(150, 165, 190),
		LightColor = Color3.fromRGB(255, 244, 220),
		LightDirection = Vector3.new(-0.5, -1, -0.4),
		Parent = holder,
	}, { UI.Corner(10) })
	local world = Instance.new("WorldModel")
	world.Parent = vp
	local specs = TowerModels.Preview(
		stage,
		floors,
		tostring(t.Skin or "GlassBlue"),
		tostring(t.Neon or "Accent"),
		tostring(t.Crown or "")
	)
	for _, spec in ipairs(specs) do
		local part = TowerModels.Instantiate(spec, CFrame.identity, world)
		if highlight and spec.Attr and spec.Attr.Floor == highlight then
			part.Color = Color3.new(1, 1, 1)
		end
	end
	local height = math.max(24, floors * TowerModels.FloorHeight() + 30)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	local distance = height * 1.25 + 40
	local target = Vector3.new(0, height * 0.45, 0)
	camera.CFrame = CFrame.lookAt(Vector3.new(distance * 0.7, height * 0.55, -distance * 0.7), target)
	camera.Parent = vp
	vp.CurrentCamera = camera
	local endCF = CFrame.lookAt(Vector3.new(distance * 0.9, height * 0.6, -distance * 0.35), target)
	TweenService:Create(camera, CAMERA_INFO, { CFrame = endCF }):Play()
	return holder
end

-- ---------------------------------------------------------------------
-- ZUKUNFTS-ICH (Karte unten, nicht modal)
-- ---------------------------------------------------------------------
local function futureText(): string
	local t = tower()
	local inc = ctx.State.Income
	local steady = if type(inc) == "table" then num(inc.Steady, 0) else 0
	local towerCfg = ctx.Config.Tower
	local offlineCfg = if type(towerCfg) == "table" and type(towerCfg.Offline) == "table" then towerCfg.Offline else {}
	local last = if type(t.Offline) == "table" then t.Offline else {}
	local rate = num(last.Rate, num(offlineCfg.Rate, 0.5))
	local cap = num(last.Cap, num(offlineCfg.CapHours, 8) * 3600)
	local seconds = math.min(FUTURE_HOURS * 3600, cap)
	local amount = TowerMath.Offline(steady, seconds, rate, cap)
	local parts: { string } = { T("tui.future.income", math.floor(seconds / 3600 + 0.5), credits(amount)) }
	local depot = ctx.State.Depot
	local protective = 0
	if type(depot) == "table" and type(depot.Orders) == "table" then
		for _, order in ipairs(depot.Orders) do
			if type(order) == "table" and PROTECTIVE[order.Type] then
				protective += 1
			end
		end
	end
	table.insert(parts, if protective > 0 then T("tui.future.orders", protective) else T("tui.future.noOrders"))
	local build = t.Build
	if type(build) == "table" and build.Floor ~= nil then
		local remaining = math.max(0, num(build.Until, 0) - workspace:GetServerTimeNow())
		table.insert(parts, T("tui.future.build", build.Floor, duration(remaining)))
	end
	return table.concat(parts, "  ·  ")
end

local function buildFuture()
	local frame: Frame = UI.Panel({
		Name = "FutureSelf",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 40),
		Size = UDim2.fromOffset(640, 92),
		Visible = false,
		ZIndex = 45,
		Parent = ctx.Gui,
	})
	UI.Create("UIStroke", { Color = Theme.Purple, Thickness = 1, Transparency = 0.3, Parent = frame })
	UI.Label({
		Name = "Title",
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -70, 0, 24),
		Text = UI.Upper(T("tui.future.title")),
		Face = "Display",
		TextColor3 = Theme.Purple,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 16,
		ZIndex = 46,
		Parent = frame,
	})
	futureLabel = UI.Label({
		Position = UDim2.fromOffset(16, 36),
		Size = UDim2.new(1, -32, 0, 46),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		TextColor3 = Theme.Text,
		MaxText = 16,
		ZIndex = 46,
		Parent = frame,
	})
	UI.Button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 6),
		Size = UDim2.fromOffset(32, 32),
		Text = "✕",
		Variant = "Ghost",
		ZIndex = 46,
		Parent = frame,
	}, function()
		futureToken += 1
		frame.Visible = false
	end)
	future = frame
end

function WelcomeBack.ShowFuture()
	if not future then
		buildFuture()
	end
	local frame = future
	local label = futureLabel
	if not frame or not label then
		return
	end
	local title = frame:FindFirstChild("Title") :: TextLabel?
	if title then
		title.Text = UI.Upper(T("tui.future.title"))
	end
	label.Text = futureText()
	futureAt = os.clock()
	futureToken += 1
	local token = futureToken
	frame.Visible = true
	frame.Position = UDim2.new(0.5, 0, 1, 40)
	TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 1, -110),
	}):Play()
	task.delay(FUTURE_STAY, function()
		if futureToken == token and frame.Parent then
			local out =
				TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = UDim2.new(0.5, 0, 1, 40),
				})
			out.Completed:Once(function()
				if futureToken == token then
					frame.Visible = false
				end
			end)
			out:Play()
		end
	end)
end

-- ---------------------------------------------------------------------
-- FENSTER
-- ---------------------------------------------------------------------
local function line(parent: Instance, order: number, icon: string, value: string, color: Color3?)
	local row = UI.RowCard(parent, order, 40)
	UI.Label({
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -24, 1, 0),
		Text = icon .. "  " .. value,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = color or Theme.Text,
		MaxText = 16,
		Parent = row,
	})
end

local function fillWindow()
	if not window then
		return
	end
	local content = window.Content
	for _, child in ipairs(content:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	filledSig = reportSig()
	local offline, catchup = reportOf()
	local t = tower()
	local floors = math.floor(num(t.Floors, 0))
	local built = math.floor(num(offline.Built, 0))
	UI.Label({
		Size = UDim2.new(1, 0, 0, 24),
		Text = T("tui.welcome.away", duration(num(offline.Away, num(offline.Seconds, 0)))),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Text2,
		MaxText = 16,
		LayoutOrder = 1,
		Parent = content,
	})
	-- Vorher / Nachher
	local views = UI.Row(content, 2, 232)
	local before = math.max(0, floors - (if built > 0 then 1 else 0))
	viewport(views, 1, T("tui.welcome.before"), before, nil)
	viewport(views, 2, T("tui.welcome.after"), floors, if built > 0 then built else nil)
	-- Zeilen
	local order = 3
	local amount = num(offline.Amount, 0)
	if amount > 0 then
		line(
			content,
			order,
			"🏙️",
			T(
				"tui.welcome.offline",
				credits(amount),
				math.floor(num(offline.Rate, 0.5) * 100 + 0.5),
				duration(num(offline.Seconds, 0))
			),
			UI.UpColor()
		)
		order += 1
	end
	if num(catchup.Dividends, 0) > 0 then
		line(content, order, "💠", T("tui.welcome.dividends", aky(num(catchup.Dividends, 0))), Theme.Accent)
		order += 1
	end
	if num(catchup.Fills, 0) > 0 then
		line(content, order, "📈", T("tui.welcome.fills", math.floor(num(catchup.Fills, 0))))
		order += 1
	end
	if num(catchup.Alerts, 0) > 0 then
		line(content, order, "🔔", T("tui.welcome.alerts", math.floor(num(catchup.Alerts, 0))))
		order += 1
	end
	if type(catchup.Bots) == "table" then
		for i, bot in ipairs(catchup.Bots) do
			if i > 4 then
				break
			end
			if type(bot) == "table" then
				local value = num(bot.Pct, 0)
				line(
					content,
					order,
					"🤖",
					T("tui.welcome.bot", botName(tostring(bot.Preset)), pct(value)),
					UI.TrendColor(value)
				)
				order += 1
			end
		end
	end
	if built > 0 then
		line(content, order, "🏗️", T("tui.welcome.built", built), Theme.Gold)
		order += 1
	end
	local transfer = num(offline.Transfer, 0)
	if transfer > 0 then
		line(content, order, "🔁", T("tui.welcome.transfer", credits(transfer)), UI.UpColor())
		order += 1
	end
	if order == 3 then
		line(content, order, "✨", T("tui.welcome.quiet"))
		order += 1
	end
	collectAmount = amount + transfer
	-- EINSAMMELN mit rollendem Zähler (bereits gutgeschrieben – ehrlich beschriftet)
	local collectRow = UI.Row(content, 50, 56)
	local total: TextLabel = UI.Label({
		Name = "Total",
		Size = UDim2.fromOffset(230, 52),
		Text = "",
		Face = "Mono",
		TextColor3 = UI.UpColor(),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 28,
		LayoutOrder = 1,
		Parent = collectRow,
	})
	UI.Create("UIScale", { Parent = total })
	local counter = UI.Counter(total, function(value: number): string
		return "+" .. credits(math.floor(value + 0.5))
	end)
	UI.SetCounter(counter, collectAmount) -- rollt von 0 hoch (UI.Frame bewegt den Zähler)
	UI.Button({
		Size = UDim2.fromOffset(260, 52),
		Text = UI.Upper(T("tui.welcome.collect")),
		Variant = "Success",
		MaxText = 20,
		LayoutOrder = 2,
		Parent = collectRow,
	}, function()
		if collectAmount > 0 then
			call("Effects", "Play", "CoinFly", collectAmount)
			call("Hud", "PulseCredits", collectAmount)
		end
		if ctx.Windows then
			ctx.Windows.Close("WelcomeBack")
		end
	end)
	UI.Label({
		Size = UDim2.new(1, 0, 0, 20),
		Text = T("tui.welcome.credited"),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Muted,
		MaxText = 13,
		TextWrapped = true,
		LayoutOrder = 51,
		Parent = content,
	})
	-- Zukunfts-Ich als letzte Zeile
	local futureCard = UI.Card({ Size = UDim2.new(1, 0, 0, 70), LayoutOrder = 60, Parent = content })
	UI.Label({
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 0, 20),
		Text = UI.Upper(T("tui.future.title")),
		Face = "Display",
		TextColor3 = Theme.Purple,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 14,
		Parent = futureCard,
	})
	UI.Label({
		Position = UDim2.fromOffset(12, 28),
		Size = UDim2.new(1, -24, 0, 36),
		Text = futureText(),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		MaxText = 14,
		Parent = futureCard,
	})
end

local function openWindow()
	if not window then
		window = UI.Window(T("tui.welcome.title"), WINDOW_W, WINDOW_H, Theme.Up)
		builtLang = lang()
	elseif builtLang ~= lang() then
		window.TitleLabel.Text = UI.Upper(T("tui.welcome.title"))
		builtLang = lang()
	end
	fillWindow()
	UI.OpenWindow(window)
	call("Sfx", "Play", "Achievement")
end

local function closeWindow()
	if window and window.IsOpen then
		UI.CloseWindow(window)
	end
end

function WelcomeBack.Show(data: any)
	if type(data) == "table" then
		if type(data.Offline) == "table" then
			report.Offline = data.Offline
		end
		if type(data.Catchup) == "table" then
			report.Catchup = data.Catchup
		end
	end
	shown = true
	pendingSince = nil
	if ctx.Windows then
		ctx.Windows.Open("WelcomeBack")
	end
end

-- 1×/s (TowerView): verzögert öffnen, wenn kein anderes Fenster/Tutorial stört
function WelcomeBack.Tick()
	if window and window.IsOpen then
		return
	end
	local since = pendingSince
	if shown or not since then
		return
	end
	local waited = os.clock() - since
	if waited < SHOW_DELAY then
		return
	end
	if waited > WAIT_MAX then
		pendingSince = nil
		return
	end
	local okTut, active = call("Tutorial", "IsActive")
	if okTut and active == true then
		return
	end
	if ctx.Windows and ctx.Windows.IsOpen() then
		return
	end
	if hasNews() then
		WelcomeBack.Show(nil)
	end
end

function WelcomeBack.Init(context: any)
	ctx = context
	ctx.Windows.Register("WelcomeBack", openWindow, closeWindow)
	ctx.Hooks.On("State", function(state: { [string]: any }, changed: { [any]: any })
		if shown then
			if window and window.IsOpen and (changed.Life or changed.Tower) and reportSig() ~= filledSig then
				fillWindow() -- Abgleich kam später an (Bots/Orders) -> Bericht ergänzen
			end
			return
		end
		if (changed.Tower or changed.Life) and pendingSince == nil then
			local t = state.Tower
			if type(t) == "table" and type(t.Offline) == "table" then
				pendingSince = os.clock()
			end
		end
	end)
end

function WelcomeBack.Start()
	-- „Zukunfts-Ich“, sobald das Roblox-Menü aufgeht (man verlässt das Spiel gleich)
	GuiService.MenuOpened:Connect(function()
		if os.clock() - futureAt >= FUTURE_GAP and type(ctx.State.Tower) == "table" then
			WelcomeBack.ShowFuture()
		end
	end)
end

return WelcomeBack
