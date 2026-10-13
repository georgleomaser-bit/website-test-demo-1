-- =====================================================================
--  AKYTEX TYCOON – Die ersten 10 Minuten mit Tiko (Client/Modules/Tutorial)
--  Besitzer: WP9 (Fortschritt, Tutorial, Sozial, Bestenlisten). Vertrag: DESIGN.md §B2 (Ablauf 0:04–9:30, Funnel
--  3–17, jeder Schritt überspringbar, „Tutorial überspringen“ gibt dieselben Belohnungen, KEIN Robux-Angebot),
--  §0.5 (Tiko = geskripteter Hologramm-Roboter, keine KI, keine Anlageberatung), §B8.6 (Übungsaktie ACAD),
--  §B11.9 (Favoriten-Abfrage 1× je Konto, Benachrichtigungs-Opt-in frühestens nach Schritt 17), §C7.5.
--
--  Öffentliche API (§C7.5):
--    Tutorial.Step(): number       aktueller Schritt (0 = noch nicht entschieden, 3–17 aktiv, 18 = fertig)
--    Tutorial.IsActive(): boolean  läuft das Tutorial gerade? (WelcomeBack wartet darauf)
--  Zusätzlich: Tutorial.Init(ctx), Tutorial.Start(), Tutorial.Tick() (1 s aus Main.client)
--
--  Schritt-Nummern = Funnel-Schritte (§B2). Der Client meldet nur FlyInDone (3), FavoritePrompted (16), Done/Skipped
--  über "TutorialFlag"; die übrigen Funnel-Schritte schreiben die Server-Besitzer (Bauen, Kassieren, Trade, Lektion …).
--  Fortschritt liegt serverseitig in Flags.TutStep (RewardTutorial) -> nach einem Neustart geht es dort weiter.
--  Anfragen: TutorialFlag, RewardTutorial, TowerBuild, TowerCollect, TowerTransfer, TowerRoom, TowerHire,
--  TowerEfficiency, CarSpawn, RewardLogin.  Module: Terminal, Academy, Vehicles, WelcomeBack, Social, Sfx, Effects.
-- =====================================================================

local AvatarEditorService = game:GetService("AvatarEditorService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent:WaitForChild("UI"))

local Tutorial = {}

local Theme = UI.Theme
local player = Players.LocalPlayer

local FIRST_STEP = 3
local LAST_STEP = 17
local DONE_STEP = 18
local CARD_W, CARD_H = 384, 192
local MINI_W, MINI_H = 300, 92
local TYPE_STEP = 0.022 -- Sekunden je Schriftzeichen (Schreibmaschine)
local MAX_GRAPHEMES = 240
local CHAIN_GAP = 1.2 -- verkettetes Bauen (Etagen 2–5): Abstand zwischen zwei Aufträgen
local CLAIM_GAP = 0.6 -- RewardTutorial höchstens so oft (Server-Rate 2/s)
local WAYPOINT_RENEW = 80 -- Wegpunkt läuft nach 90 s ab -> rechtzeitig erneuern
local START_WAIT = 12 -- so lange auf den Plot warten, sonst Anflug überspringen
local ENTRANCE_RADIUS = 45
local SELL_HINT_AFTER = 20 -- Übungs-Trade: nach so vielen Sekunden „Verkaufen“-Satz
local LICENCE_HOLD = 7 -- Lizenz-Zeremonie: so lange bleibt der Glückwunsch stehen (dann automatisch weiter)
local TIKO_OFFSET = CFrame.new(3.6, 2.4, -5)
local TIKO_TWEEN = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local CARD_IN = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CARD_MOVE = TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local PULSE_INFO = TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

local ctx: any = nil
local step = 0
local active = false
local decided = false
local decideSince = 0
local phase = 1
local phaseAt = 0
local busy = false
local chain = false
local lastChainAt = 0
local vaultMax = 0
local collectedOk = false
local transferOk = false
local flyDone = false
local favoriteDone = false
local finished = false
local waypointAt = 0
local claimWanted = 0
local claimSent = 0
local lastClaimAt = 0
local renderSig = ""
local typeToken = 0

local card: { [string]: any } = {}
local tikoRoot: BasePart? = nil
local tikoModel: Model? = nil
local tikoBob = false
local hologram: Model? = nil
local flyTween: Tween? = nil
local flyConn: RBXScriptConnection? = nil
local flyHint: TextLabel? = nil
local pulseTween: Tween? = nil

-- vorwärts deklariert (gegenseitige Aufrufe)
local evaluate: () -> ()
local render: () -> ()

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

local function stateOf(key: string): { [string]: any }
	local s = ctx.State[key]
	return if type(s) == "table" then s else {}
end

local function cfg(): { [string]: any }
	local p = ctx.Config.Progression
	local t = type(p) == "table" and p.Tutorial or nil
	return if type(t) == "table" then t else {}
end

local function reducedFx(): boolean
	local ok, settings = call("Settings", "Get")
	return ok and type(settings) == "table" and settings.ReducedFx == true
end

local function sfx(role: string)
	call("Sfx", "Play", role)
end

local function floors(): number
	return math.floor(num(stateOf("Tower").Floors, 0))
end

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function seated(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.SeatPart ~= nil
end

-- Mitte des eigenen Plots (TowerView bevorzugt, sonst Config.City.Plots: R 420, 18° + (Id − 1) · 36°)
local function plotCenter(): Vector3?
	local id = stateOf("Plot").Id
	if type(id) ~= "number" or id < 1 then
		return nil
	end
	local ok, info = call("TowerView", "PlotInfo", id)
	if ok and type(info) == "table" and typeof(info.Pivot) == "CFrame" then
		return (info.Pivot :: CFrame).Position
	end
	local city = ctx.Config.City
	local plots = type(city) == "table" and city.Plots or nil
	local radius = num(plots and plots.Radius, 420)
	local angle = math.rad(num(plots and plots.StartAngle, 18) + (id - 1) * num(plots and plots.Step, 36))
	return Vector3.new(radius * math.cos(angle), 0, radius * math.sin(angle))
end

local function exchangeCenter(): Vector3
	local city = ctx.Config.City
	local zones = type(city) == "table" and city.Zones or nil
	local exchange = type(zones) == "table" and zones.Exchange or nil
	local center = if type(exchange) == "table" and typeof(exchange.Center) == "Vector3"
		then exchange.Center
		else Vector3.new(0, 0, -190)
	return center
end

-- Eingang des Börsensaals: Vorderseite zur Plaza (+Z)
local function exchangeEntrance(): Vector3
	local city = ctx.Config.City
	local zones = type(city) == "table" and city.Zones or nil
	local exchange = type(zones) == "table" and zones.Exchange or nil
	local depth = num(type(exchange) == "table" and exchange.Depth or nil, 140)
	return exchangeCenter() + Vector3.new(0, 0, depth / 2)
end

local function nearExchange(): boolean
	local root = rootPart()
	if not root then
		return false
	end
	local pos = Vector3.new(root.Position.X, 0, root.Position.Z)
	local center = exchangeCenter()
	local entrance = exchangeEntrance()
	return (pos - Vector3.new(center.X, 0, center.Z)).Magnitude <= num(cfg().ExchangeRadius, 70)
		or (pos - Vector3.new(entrance.X, 0, entrance.Z)).Magnitude <= ENTRANCE_RADIUS
end

local function floorHasStaff(index: number): boolean
	local list = stateOf("Tower").List
	local floor = type(list) == "table" and list[index] or nil
	return type(floor) == "table" and type(floor.S) == "table" and next(floor.S) ~= nil
end

local function floorRoom(index: number): string?
	local list = stateOf("Tower").List
	local floor = type(list) == "table" and list[index] or nil
	return if type(floor) == "table" and type(floor.R) == "string" then floor.R else nil
end

local function roomName(key: string): string
	local tower = ctx.Config.Tower
	local rooms = type(tower) == "table" and tower.Rooms or nil
	if type(rooms) == "table" then
		for _, def in ipairs(rooms) do
			if type(def) == "table" and def.Key == key and type(def.Name) == "table" then
				return ctx.Lang.Pick(lang(), def.Name)
			end
		end
	end
	return key
end

-- Anfrage ohne Doppelklick; onOk läuft nur bei Erfolg, danach wird der Schritt neu bewertet
local function request(action: string, arg: any, onOk: ((any) -> ())?, onFail: ((any) -> ())?)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local reply = ctx.RequestFull(action, arg)
		busy = false
		if reply.Ok then
			if onOk then
				onOk(reply)
			end
		elseif onFail then
			onFail(reply)
		end
		evaluate()
	end)
end

-- Schritt-Belohnung (RewardTutorial vergibt alles ≤ Schritt einmalig; höchstens alle 0,6 s eine Anfrage)
local function flushClaim()
	if claimWanted <= claimSent or os.clock() - lastClaimAt < CLAIM_GAP then
		return
	end
	local wanted = claimWanted
	claimSent = wanted
	lastClaimAt = os.clock()
	task.spawn(function()
		local reply = ctx.RequestFull("RewardTutorial", { Step = wanted }, false)
		if not reply.Ok and claimSent == wanted then
			claimSent = wanted - 1 -- später erneut versuchen (z. B. Profil lädt noch)
		end
	end)
end

local function queueClaim(n: number)
	if n > claimWanted then
		claimWanted = n
	end
	flushClaim()
end

local function sendFlag(flag: string)
	task.spawn(function()
		ctx.RequestFull("TutorialFlag", { Flag = flag }, true)
	end)
end

-- ---------------------------------------------------------------------
-- 2) TIKO IN DER WELT (Hologramm-Roboter aus Parts, nur lokal) + Plot-Hologramm
-- ---------------------------------------------------------------------
local function worldPart(props: { [string]: any }, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Anchored = props.Anchored == true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Shape = props.Shape or Enum.PartType.Block
	part.Size = props.Size
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Color = props.Color or Theme.Text
	part.Transparency = props.Transparency or 0
	part.Name = props.Name or "Part"
	part.CFrame = props.CFrame or CFrame.new()
	part.Parent = parent
	return part
end

local function buildTiko(at: CFrame)
	local model = Instance.new("Model")
	model.Name = "AT_Tiko"
	local root = worldPart({
		Name = "Body",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.2, 2.2, 2.2),
		Material = Enum.Material.Glass,
		Color = Theme.Cyan,
		Transparency = 0.18,
		Anchored = true,
		CFrame = at,
	}, model)
	local parts: { BasePart } = {
		worldPart({
			Name = "Visor",
			Size = Vector3.new(1.55, 0.7, 0.3),
			Material = Enum.Material.Glass,
			Color = Theme.Bg,
			CFrame = at * CFrame.new(0, 0.18, -0.98),
		}, model),
		worldPart({
			Name = "EyeL",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.28, 0.28, 0.28),
			Material = Enum.Material.Neon,
			Color = Theme.LogoLetters,
			CFrame = at * CFrame.new(-0.34, 0.2, -1.16),
		}, model),
		worldPart({
			Name = "EyeR",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.28, 0.28, 0.28),
			Material = Enum.Material.Neon,
			Color = Theme.LogoLetters,
			CFrame = at * CFrame.new(0.34, 0.2, -1.16),
		}, model),
		worldPart({
			Name = "Antenna",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.7, 0.12, 0.12),
			Material = Enum.Material.Metal,
			Color = Theme.Text2,
			CFrame = at * CFrame.new(0, 1.38, 0) * CFrame.Angles(0, 0, math.pi / 2),
		}, model),
		worldPart({
			Name = "Tip",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.34, 0.34, 0.34),
			Material = Enum.Material.Neon,
			Color = Theme.Accent,
			CFrame = at * CFrame.new(0, 1.8, 0),
		}, model),
		worldPart({
			Name = "Ring",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.12, 2.8, 2.8),
			Material = Enum.Material.Neon,
			Color = Theme.Cyan,
			Transparency = 0.55,
			CFrame = at * CFrame.new(0, -1.55, 0) * CFrame.Angles(0, 0, math.pi / 2),
		}, model),
	}
	for _, part in ipairs(parts) do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = root
	end
	local light = Instance.new("PointLight")
	light.Color = Theme.Cyan
	light.Range = 10
	light.Brightness = 1.4
	light.Parent = parts[5]
	model.PrimaryPart = root
	model.Parent = workspace
	tikoModel = model
	tikoRoot = root
end

local function removeTiko()
	local model = tikoModel
	tikoModel = nil
	tikoRoot = nil
	if model then
		model:Destroy()
	end
end

-- 1×/s: Tiko schwebt rechts vor dem Spieler und schaut ihn an (im Auto/während des Anflugs unsichtbar)
local function moveTiko()
	local root = rootPart()
	if not active or flyTween ~= nil or not root or seated() then
		removeTiko()
		return
	end
	tikoBob = not tikoBob
	local base = root.CFrame * TIKO_OFFSET
	local pos = base.Position + Vector3.new(0, if tikoBob then 0.35 else -0.15, 0)
	local target = CFrame.lookAt(pos, root.Position + Vector3.new(0, 1.5, 0))
	local body = tikoRoot
	if not body or not body.Parent then
		buildTiko(target)
		return
	end
	if (body.Position - pos).Magnitude > 60 then
		body.CFrame = target
		return
	end
	TweenService:Create(body, TIKO_TWEEN, { CFrame = target }):Play()
end

local function showHologram()
	if hologram and hologram.Parent then
		return
	end
	local center = plotCenter()
	if not center then
		return
	end
	local model = Instance.new("Model")
	model.Name = "AT_TutorialHologram"
	worldPart({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 46, 46),
		Material = Enum.Material.Neon,
		Color = Theme.Gold,
		Transparency = 0.7,
		Anchored = true,
		CFrame = CFrame.new(center + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.pi / 2),
	}, model)
	local anchor = worldPart({
		Name = "Label",
		Size = Vector3.new(1, 1, 1),
		Transparency = 1,
		Anchored = true,
		CFrame = CFrame.new(center + Vector3.new(0, 18, 0)),
	}, model)
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromOffset(420, 64)
	board.AlwaysOnTop = true
	board.LightInfluence = 0
	board.MaxDistance = 900
	board.Parent = anchor
	local label = UI.Label({
		Size = UDim2.fromScale(1, 1),
		Text = UI.Upper(T("tut.hologram")),
		Face = "Display",
		TextColor3 = Theme.Gold,
		MaxText = 30,
		Outline = 1,
		Parent = board,
	})
	label.TextStrokeTransparency = 1
	model.Parent = workspace
	hologram = model
end

local function hideHologram()
	local model = hologram
	hologram = nil
	if model then
		model:Destroy()
	end
end

-- ---------------------------------------------------------------------
-- 3) KAMERA-ANFLUG (Schritt 3): Skyline -> Plaza -> eigener Plot, jede Eingabe überspringt
-- ---------------------------------------------------------------------
local function endFlyIn()
	local conn = flyConn
	flyConn = nil
	if conn then
		conn:Disconnect()
	end
	local tween = flyTween
	flyTween = nil
	if tween then
		tween:Cancel()
	end
	local hint = flyHint
	flyHint = nil
	if hint then
		hint:Destroy()
	end
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
	if not flyDone then
		flyDone = true
		sendFlag("FlyInDone")
	end
	if active then
		evaluate()
	end
end

local function startFlyIn()
	local camera = workspace.CurrentCamera
	local center = plotCenter()
	if not camera or not center then
		endFlyIn()
		return
	end
	showHologram()
	local flat = Vector3.new(center.X, 0, center.Z)
	local dir = if flat.Magnitude > 1 then flat.Unit else Vector3.new(1, 0, 0)
	local startPos = -dir * 380 + Vector3.new(0, 240, 0) -- hoch über der Plaza, gegenüber dem Plot
	local endPos = center - dir * 95 + Vector3.new(0, 46, 0) -- zwischen Plaza und Plot, Blick auf das Grundstück
	local seconds = num(cfg().FlyInSeconds, 4)
	if reducedFx() then
		seconds = math.min(seconds, 1.5)
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(startPos, Vector3.new(0, 20, 0))
	local tween = TweenService:Create(
		camera,
		TweenInfo.new(seconds, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut),
		{ CFrame = CFrame.lookAt(endPos, center + Vector3.new(0, 8, 0)) }
	)
	flyTween = tween
	flyHint = UI.Label({
		Name = "TutorialFlyHint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(360, 26),
		Text = T("tut.flyHint"),
		TextColor3 = Theme.Text2,
		MaxText = 18,
		Outline = 1,
		ZIndex = 45,
		Parent = ctx.Gui,
	})
	flyConn = UserInputService.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if
			kind == Enum.UserInputType.Keyboard
			or kind == Enum.UserInputType.MouseButton1
			or kind == Enum.UserInputType.Touch
			or kind == Enum.UserInputType.Gamepad1
		then
			endFlyIn()
		end
	end)
	tween.Completed:Once(function(playback: Enum.PlaybackState)
		if playback == Enum.PlaybackState.Completed and flyTween == tween then
			task.delay(0.6, function()
				if flyTween == tween then
					endFlyIn()
				end
			end)
		end
	end)
	tween:Play()
end

-- ---------------------------------------------------------------------
-- 4) TIKO-KARTE (Glas-Karte links, Schreibmaschine; bei offenem Fenster kompakt)
-- ---------------------------------------------------------------------
local function compact(): boolean
	local windows = ctx.Windows
	return windows ~= nil and type(windows.IsOpen) == "function" and windows.IsOpen() == true
end

local function typeText(label: TextLabel, text: string)
	typeToken += 1
	local token = typeToken
	label.Text = text
	local count = math.min(utf8.len(text) or #text, MAX_GRAPHEMES)
	if reducedFx() or count <= 0 then
		label.MaxVisibleGraphemes = -1
		return
	end
	label.MaxVisibleGraphemes = 0
	task.spawn(function()
		for i = 1, count do
			if typeToken ~= token or not label.Parent then
				return
			end
			label.MaxVisibleGraphemes = i
			task.wait(TYPE_STEP)
		end
		if typeToken == token then
			label.MaxVisibleGraphemes = -1
		end
	end)
end

local function buildCard()
	local panel = UI.Panel({
		Name = "TikoCard",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		ZIndex = 40,
		Visible = false,
		Parent = ctx.Gui,
	})
	local scale = UI.Create("UIScale", { Scale = 1, Parent = panel })
	-- Avatar: runder Glas-Kopf mit Visier und zwei Augen
	local avatar = UI.Create("Frame", {
		Name = "Avatar",
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.fromOffset(48, 48),
		BackgroundColor3 = Theme.Cyan,
		BackgroundTransparency = 0.2,
		ZIndex = 41,
		Parent = panel,
	}, {
		UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		UI.Stroke(Theme.Cyan, 2),
	})
	local visor = UI.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(34, 16),
		BackgroundColor3 = Theme.Bg,
		ZIndex = 42,
		Parent = avatar,
	}, { UI.Corner(8) })
	for i = 1, 2 do
		UI.Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, if i == 1 then -7 else 7, 0.5, 0),
			Size = UDim2.fromOffset(6, 6),
			BackgroundColor3 = Theme.LogoLetters,
			ZIndex = 43,
			Parent = visor,
		}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	end
	local name = UI.Label({
		Name = "Name",
		Position = UDim2.fromOffset(72, 14),
		Size = UDim2.new(1, -190, 0, 24),
		Text = UI.Upper(T("tut.title")),
		Face = "Display",
		TextColor3 = Theme.Cyan,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 18,
		ZIndex = 41,
		Parent = panel,
	})
	local tag = UI.Label({
		Name = "Tag",
		Position = UDim2.fromOffset(72, 38),
		Size = UDim2.new(1, -190, 0, 18),
		Text = T("tut.tag"),
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 13,
		ZIndex = 41,
		Parent = panel,
	})
	local counter = UI.Label({
		Name = "Counter",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(60, 20),
		Text = "",
		Face = "Mono",
		TextColor3 = Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxText = 14,
		ZIndex = 41,
		Parent = panel,
	})
	local skipAll = UI.Button({
		Name = "SkipAll",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 36),
		Size = UDim2.fromOffset(150, 24),
		Text = T("tut.skip"),
		Variant = "Ghost",
		MaxText = 12,
		ZIndex = 41,
		Parent = panel,
	}, function()
		Tutorial._SkipAll()
	end)
	local text = UI.Label({
		Name = "Text",
		Position = UDim2.fromOffset(14, 70),
		Size = UDim2.new(1, -28, 0, 58),
		Text = "",
		Face = "Body",
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		MaxText = 17,
		ZIndex = 41,
		Parent = panel,
	})
	local row = UI.Create("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -12),
		Size = UDim2.new(1, -28, 0, 44),
		BackgroundTransparency = 1,
		ZIndex = 41,
		Parent = panel,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	})
	local action = UI.Button({
		Name = "Action",
		Size = UDim2.new(1, -118, 1, 0),
		Text = "",
		Variant = "Primary",
		MaxText = 18,
		LayoutOrder = 1,
		ZIndex = 42,
		Parent = row,
	}, function()
		Tutorial._Action()
	end)
	local actionScale = UI.Create("UIScale", { Scale = 1, Parent = action.Frame })
	local skipStep = UI.Button({
		Name = "SkipStep",
		Size = UDim2.fromOffset(110, 40),
		Text = T("tut.skipStep"),
		Variant = "Secondary",
		MaxText = 15,
		LayoutOrder = 2,
		ZIndex = 42,
		Parent = row,
	}, function()
		Tutorial._SkipStep()
	end)
	-- Abteilungs-Wahl (Schritt 9): drei Karten, Trading-Desk empfohlen
	local choices = UI.Create("Frame", {
		Name = "Choices",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -62),
		Size = UDim2.new(1, -28, 0, 50),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 41,
		Parent = panel,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
	})
	local choiceButtons: { [string]: any } = {}
	local list = cfg().RoomChoices
	if type(list) == "table" then
		for i, key in ipairs(list) do
			if type(key) == "string" then
				local recommended = key == cfg().Recommended
				choiceButtons[key] = UI.Button({
					Name = "Room_" .. key,
					Size = UDim2.new(1 / 3, -4, 1, 0),
					Text = roomName(key),
					Sub = if recommended then T("tut.room.recommended") else nil,
					Variant = if recommended then "Success" else "Secondary",
					MaxText = 15,
					LayoutOrder = i,
					ZIndex = 42,
					Parent = choices,
				}, function()
					Tutorial._ChooseRoom(key)
				end)
			end
		end
	end
	card = {
		Panel = panel,
		Scale = scale,
		Name = name,
		Tag = tag,
		Counter = counter,
		SkipAll = skipAll,
		Text = text,
		Row = row,
		Action = action,
		ActionScale = actionScale,
		SkipStep = skipStep,
		Choices = choices,
		ChoiceButtons = choiceButtons,
		Compact = false,
	}
end

local function setPulse(on: boolean)
	local tween = pulseTween
	if on and not tween and card.ActionScale then
		card.ActionScale.Scale = 1
		local newTween = TweenService:Create(card.ActionScale, PULSE_INFO, { Scale = 1.06 })
		pulseTween = newTween
		newTween:Play()
	elseif not on and tween then
		tween:Cancel()
		pulseTween = nil
		card.ActionScale.Scale = 1
	end
end

local function layoutCard()
	local panel: Frame? = card.Panel
	if not panel then
		return
	end
	local small = compact()
	if small == card.Compact then
		return
	end
	card.Compact = small
	TweenService:Create(panel, CARD_MOVE, {
		Size = if small then UDim2.fromOffset(MINI_W, MINI_H) else UDim2.fromOffset(CARD_W, CARD_H),
		Position = if small then UDim2.new(0, 16, 0.32, 0) else UDim2.new(0, 16, 0.5, 0),
	}):Play()
	card.Tag.Visible = not small
	card.SkipAll.Frame.Visible = not small
	card.Row.Visible = not small
	card.Text.Position = if small then UDim2.fromOffset(72, 40) else UDim2.fromOffset(14, 70)
	card.Text.Size = if small then UDim2.new(1, -86, 0, 44) else UDim2.new(1, -28, 0, 58)
	renderSig = ""
end

local function showCard(on: boolean)
	local panel: Frame? = card.Panel
	if not panel then
		return
	end
	if on and not panel.Visible then
		panel.Visible = true
		card.Scale.Scale = 0.85
		TweenService:Create(card.Scale, CARD_IN, { Scale = 1 }):Play()
	elseif not on and panel.Visible then
		panel.Visible = false
		setPulse(false)
	end
end

-- ---------------------------------------------------------------------
-- 5) SCHRITTE: Texte, Knopf, Erledigt-Prüfung
-- ---------------------------------------------------------------------
type View = { Lines: { string }, Button: string?, Choices: boolean? }

local function viewOf(n: number): View
	local tower = stateOf("Tower")
	if n == 4 then
		return { Lines = { "tut.s.welcome" }, Button = "tut.btn.build" }
	elseif n == 5 then
		return { Lines = { "tut.s.floor1", "tut.s.collect" }, Button = "tut.btn.collect" }
	elseif n == 6 then
		if stateOf("Depot").Tutorial == "Running" then
			if os.clock() - phaseAt >= SELL_HINT_AFTER then
				return { Lines = { "tut.s.sell" }, Button = "tut.btn.terminal" }
			end
			return { Lines = { "tut.s.tradeHint", "tut.s.protect" }, Button = "tut.btn.terminal" }
		end
		return { Lines = { "tut.s.trade" }, Button = "tut.btn.trade" }
	elseif n == 7 then
		return { Lines = { "tut.s.transfer" }, Button = "tut.btn.transfer" }
	elseif n == 8 then
		local lines = { if num(tower.Stage, 1) >= 3 then "tut.s.loft" else "tut.s.floors" }
		local nextInfo = type(tower.Next) == "table" and tower.Next or {}
		local cost = num(nextInfo.Cost, 0)
		if
			cost > 0
			and num(ctx.State.Credits, 0) < cost
			and type(tower.Build) == "table"
			and tower.Build.Floor == nil
		then
			table.insert(lines, "tut.waitingMoney")
		end
		return { Lines = lines, Button = "tut.btn.build" }
	elseif n == 9 then
		if phase == 1 then
			return { Lines = { "tut.s.room" }, Choices = true }
		end
		return { Lines = { "tut.s.staff" }, Button = "tut.btn.hire" }
	elseif n == 10 then
		return { Lines = { "tut.s.janitor" }, Button = "tut.btn.janitor" }
	elseif n == 11 then
		return { Lines = { "tut.s.live" }, Button = "tut.btn.terminal" }
	elseif n == 12 then
		if phase == 1 then
			return { Lines = { "tut.s.quests" }, Button = "tut.btn.quests" }
		elseif phase == 2 then
			return { Lines = { "tut.s.car" }, Button = "tut.btn.car" }
		end
		return { Lines = { "tut.s.drive" } }
	elseif n == 13 then
		return { Lines = { "tut.s.lesson" }, Button = "tut.btn.lesson" }
	elseif n == 14 then
		if phase == 2 then
			return { Lines = { "tut.s.licenceDone" }, Button = "tut.next" }
		end
		return { Lines = { "tut.s.licence" } }
	elseif n == 15 then
		return { Lines = { "tut.s.eff" }, Button = "tut.btn.eff" }
	elseif n == 16 then
		return { Lines = { "tut.s.future" }, Button = "tut.next" }
	elseif n == 17 then
		if phase == 1 then
			return { Lines = { "tut.s.login" }, Button = "tut.btn.login" }
		end
		return { Lines = { "tut.s.done" }, Button = "tut.btn.done" }
	end
	return { Lines = {} }
end

local function isDone(n: number): boolean
	local tower = stateOf("Tower")
	local flags = stateOf("Flags")
	if n == 3 then
		return flyDone or flags.FlyInDone == true
	elseif n == 4 then
		return floors() >= 1
	elseif n == 5 then
		local vault = num(tower.Vault, 0)
		return collectedOk or (vaultMax >= 1 and vault <= vaultMax * 0.5)
	elseif n == 6 then
		return stateOf("Depot").Tutorial == "Done" or flags.TutorialTrade == true
	elseif n == 7 then
		return transferOk
	elseif n == 8 then
		return floors() >= math.floor(num(cfg().StageFloors, 5))
	elseif n == 9 then
		return floorHasStaff(2)
	elseif n == 10 then
		return tower.Janitor == true
	elseif n == 11 then
		return flags.FirstLiveTrade == true
	elseif n == 12 then
		return phase >= 3 and nearExchange()
	elseif n == 13 then
		local lessons = stateOf("Prog").Lessons
		return type(lessons) == "table" and lessons.L01 ~= nil
	elseif n == 14 then
		return phase == 2 and os.clock() - phaseAt >= LICENCE_HOLD
	elseif n == 15 then
		return num(tower.Eff, 0) >= 1
	elseif n == 16 then
		return favoriteDone or flags.FavoritePrompted == true
	end
	return false -- 17 endet nur über den Knopf
end

local function setPhase(p: number)
	phase = p
	phaseAt = os.clock()
	renderSig = ""
end

-- Betreten eines Schritts: Zähler zurücksetzen, Einstiegs-Aktionen
local function enter(n: number)
	step = n
	setPhase(1)
	chain = false
	collectedOk = false
	transferOk = false
	if n == 3 then
		showCard(false)
		startFlyIn()
		return
	end
	if n >= 5 then
		hideHologram()
	elseif n == 4 then
		showHologram()
	end
	if n == 5 then
		vaultMax = num(stateOf("Tower").Vault, 0)
	elseif n == 6 and stateOf("Depot").Tutorial == "Running" then
		setPhase(2)
	elseif n == 9 then
		-- Etage 2 hat schon eine gewählte Abteilung (nicht das Standard-Büro) -> gleich zum Personal
		local tower = ctx.Config.Tower
		local default = if type(tower) == "table" and type(tower.DefaultRoom) == "string"
			then tower.DefaultRoom
			else "Office"
		local room = floorRoom(2)
		if room and room ~= default then
			setPhase(2)
		end
	elseif n == 12 and nearExchange() then
		setPhase(3)
	elseif n == 14 then
		queueClaim(14) -- die Schritt-XP bringen die 300 XP für Azubi II
	elseif n == 16 then
		call("WelcomeBack", "ShowFuture")
	elseif n == 17 then
		if stateOf("Login").Claimable ~= true then
			setPhase(2)
		end
	end
	sfx("Notify")
	showCard(true)
end

local function cleanup()
	active = false
	setPulse(false)
	if flyTween or flyConn then
		endFlyIn()
	end
	removeTiko()
	hideHologram()
	call("Vehicles", "Waypoint", nil)
	local panel = card.Panel
	if panel then
		panel:Destroy()
	end
	card = {}
end

local function advance()
	queueClaim(step)
	if step >= LAST_STEP then
		return
	end
	enter(step + 1)
end

-- ---------------------------------------------------------------------
-- 6) AKTIONEN (Knöpfe der Karte)
-- ---------------------------------------------------------------------
local function finish()
	if finished then
		return
	end
	finished = true
	claimWanted = math.max(claimWanted, LAST_STEP)
	lastClaimAt = 0 -- letzte Belohnung sofort anfragen (nicht drosseln)
	flushClaim()
	sendFlag("Done")
	step = DONE_STEP
	cleanup()
	sfx("Achievement")
	if not reducedFx() then
		call("Effects", "Confetti", 1)
	end
	-- positiver Moment nach Schritt 17: einmal das Benachrichtigungs-Opt-in anbieten (§B11.9)
	task.delay(3, function()
		call("Social", "PromptNotify")
	end)
end

function Tutorial._Action()
	if not active or busy then
		return
	end
	local n = step
	if n == 4 then
		request("TowerBuild", {})
	elseif n == 5 then
		request("TowerCollect", {}, function()
			collectedOk = true
		end)
	elseif n == 6 then
		call("Terminal", "OpenPractice")
		if phase == 1 then
			setPhase(2)
		end
	elseif n == 7 then
		request("TowerTransfer", {}, function()
			transferOk = true
		end)
	elseif n == 8 then
		chain = true
		lastChainAt = os.clock()
		request("TowerBuild", {})
	elseif n == 9 and phase == 2 then
		request("TowerHire", { Floor = 2, Staff = tostring(cfg().FirstStaff or "Intern") })
	elseif n == 10 then
		request("TowerHire", { Floor = 0, Staff = "Janitor" })
	elseif n == 11 then
		local inst = math.floor(num(cfg().SuggestInst, 40))
		local ok = call("Terminal", "OpenAt", inst)
		if not ok then
			ctx.Windows.Open("Terminal")
		end
	elseif n == 12 then
		if phase == 1 then
			ctx.Windows.Open("Quests")
			setPhase(2)
		elseif phase == 2 then
			local entrance = exchangeEntrance()
			local function toExchange()
				setPhase(3)
				waypointAt = os.clock()
				call("Vehicles", "Waypoint", entrance)
			end
			request("CarSpawn", { Key = "LamCity" }, toExchange, toExchange)
		end
	elseif n == 13 then
		local ok = call("Academy", "OpenLesson", "L01")
		if not ok then
			ctx.Windows.Open("Academy")
		end
	elseif n == 14 then
		if phase == 2 then
			advance()
		end
	elseif n == 15 then
		request("TowerEfficiency", {})
	elseif n == 16 then
		-- Favoriten-Abfrage genau einmal je Konto (Flags.FavoritePrompted), pcall – Studio/alte Clients dürfen scheitern
		if stateOf("Flags").FavoritePrompted ~= true then
			pcall(function()
				AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
			end)
			sendFlag("FavoritePrompted")
		end
		favoriteDone = true
	elseif n == 17 then
		if phase == 1 then
			request("RewardLogin", {}, function()
				setPhase(2)
			end, function()
				setPhase(2)
			end)
		else
			finish()
			return
		end
	end
	evaluate()
end

function Tutorial._ChooseRoom(key: string)
	if not active or step ~= 9 or phase ~= 1 or busy then
		return
	end
	if floorRoom(2) == key then
		setPhase(2)
		render()
		return
	end
	request("TowerRoom", { Floor = 2, Room = key }, function()
		setPhase(2)
	end)
end

function Tutorial._SkipStep()
	if not active or busy then
		return
	end
	if step >= LAST_STEP then
		finish()
		return
	end
	-- Unterphasen gelten als ein Schritt: überspringen = ganzer Schritt
	advance()
	evaluate()
end

function Tutorial._SkipAll()
	if not active then
		return
	end
	finished = true
	step = DONE_STEP
	cleanup()
	task.spawn(function()
		ctx.RequestFull("RewardTutorial", { Step = math.floor(num(cfg().SkipStep, 99)) }, false)
		ctx.RequestFull("TutorialFlag", { Flag = "Skipped" }, true)
	end)
	UI.Toast(T("tut.skipped"), "Info")
end

-- ---------------------------------------------------------------------
-- 7) BEWERTEN + ZEICHNEN
-- ---------------------------------------------------------------------
evaluate = function()
	if not active then
		return
	end
	-- Schritt 14: Lizenz erreicht -> Glückwunsch-Phase
	if step == 14 and phase == 1 and num(stateOf("Prog").Licence, 1) >= 2 then
		setPhase(2)
	end
	-- Schritt 6: Übung läuft -> Hinweis-Phase
	if step == 6 and phase == 1 and stateOf("Depot").Tutorial == "Running" then
		setPhase(2)
	end
	local guard = 0
	while active and step >= FIRST_STEP and step < LAST_STEP and isDone(step) and guard < 20 do
		guard += 1
		advance()
	end
	if active then
		render()
	end
end

render = function()
	if not active or not card.Panel or step <= FIRST_STEP then
		return
	end
	layoutCard()
	local view = viewOf(step)
	local parts: { string } = {}
	for _, key in ipairs(view.Lines) do
		table.insert(parts, T(key))
	end
	local text = table.concat(parts, " ")
	local sig = table.concat({ tostring(step), tostring(phase), text, tostring(view.Button), lang() }, "|")
	card.Counter.Text = string.format("%d/%d", step, LAST_STEP)
	if sig == renderSig then
		return
	end
	renderSig = sig
	typeText(card.Text, text)
	card.Name.Text = UI.Upper(T("tut.title"))
	card.Tag.Text = T("tut.tag")
	card.SkipAll.SetText(T("tut.skip"))
	card.SkipStep.SetText(if step >= LAST_STEP then T("tut.btn.done") else T("tut.skipStep"))
	local button = view.Button
	card.Action.Frame.Visible = button ~= nil
	if button then
		card.Action.SetText(T(button))
	end
	card.Choices.Visible = view.Choices == true and not card.Compact
	setPulse(button ~= nil and not card.Compact)
end

-- Entscheidung beim ersten vollständigen State: läuft das Tutorial, und ab welchem Schritt?
local function decide()
	local state = ctx.State
	if decided or type(state.Flags) ~= "table" or type(state.Tower) ~= "table" then
		return
	end
	local flags = state.Flags
	if flags.Done == true or flags.Skipped == true or flags.Tutorial == true then
		decided = true
		step = DONE_STEP
		return
	end
	local plot = stateOf("Plot").Id
	if type(plot) ~= "number" and os.clock() - decideSince < START_WAIT then
		return -- Plot noch nicht zugeteilt: kurz warten (Anflug braucht ihn)
	end
	decided = true
	local resume = math.floor(num(flags.TutStep, 0)) + 1
	local first = if flags.FlyInDone == true then FIRST_STEP + 1 else FIRST_STEP
	local start = math.max(first, resume)
	if start > LAST_STEP then
		step = DONE_STEP
		sendFlag("Done")
		return
	end
	flyDone = flags.FlyInDone == true
	favoriteDone = flags.FavoritePrompted == true
	claimSent = math.floor(num(flags.TutStep, 0))
	claimWanted = claimSent
	active = true
	buildCard()
	if start == FIRST_STEP and type(plot) ~= "number" then
		flyDone = true -- ohne Plot kein Anflug
		sendFlag("FlyInDone")
		start = FIRST_STEP + 1
	end
	enter(start)
	evaluate()
end

-- ---------------------------------------------------------------------
-- 8) ÖFFENTLICHE API
-- ---------------------------------------------------------------------
function Tutorial.Step(): number
	return step
end

function Tutorial.IsActive(): boolean
	return active and step >= FIRST_STEP and step <= LAST_STEP
end

function Tutorial.Tick()
	if not decided then
		decide()
		return
	end
	if not active then
		return
	end
	flushClaim()
	moveTiko()
	-- verkettetes Bauen der Etagen 2–5 (§B2 2:00–2:40)
	if step == 8 and chain and not busy and os.clock() - lastChainAt >= CHAIN_GAP then
		local tower = stateOf("Tower")
		local build = type(tower.Build) == "table" and tower.Build or {}
		local nextInfo = type(tower.Next) == "table" and tower.Next or {}
		local enough = num(ctx.State.Credits, 0) >= num(nextInfo.Cost, math.huge)
		if build.Floor == nil and nextInfo.Locked == nil and enough then
			lastChainAt = os.clock()
			busy = true
			task.spawn(function()
				ctx.RequestFull("TowerBuild", {}, true)
				busy = false
				evaluate()
			end)
		end
	end
	-- Fahrt zum Börsensaal: Wegpunkt erneuern, solange wir unterwegs sind
	if step == 12 and phase == 3 and os.clock() - waypointAt >= WAYPOINT_RENEW then
		waypointAt = os.clock()
		call("Vehicles", "Waypoint", exchangeEntrance())
	end
	if step == 5 then
		vaultMax = math.max(vaultMax, num(stateOf("Tower").Vault, 0))
	end
	evaluate()
end

function Tutorial.Init(context: any)
	ctx = context
end

function Tutorial.Start()
	decideSince = os.clock()
	ctx.Hooks.On("State", function(_state: any, changed: any)
		if not decided then
			decide()
			return
		end
		if not active or type(changed) ~= "table" then
			return
		end
		if changed.Tower or changed.Depot or changed.Prog or changed.Flags or changed.Login or changed.Credits then
			if step == 5 then
				vaultMax = math.max(vaultMax, num(stateOf("Tower").Vault, 0))
			end
			evaluate()
		end
	end)
	ctx.Hooks.On("WindowOpened", function()
		if active then
			render()
		end
	end)
	ctx.Hooks.On("WindowClosed", function()
		if active then
			render()
		end
	end)
	ctx.Hooks.On("Settings", function()
		renderSig = ""
		if active then
			render()
		end
	end)
	player.CharacterAdded:Connect(function()
		if active then
			removeTiko()
		end
	end)
end

return Tutorial
