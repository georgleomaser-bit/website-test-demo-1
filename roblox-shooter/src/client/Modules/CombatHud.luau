-- =====================================================================
--  CLUTCH CLASH – Kampf-HUD (Client/Modules/CombatHud)
--  Besitzer: WP10 (Client-Hülle). Vertrag: DESIGN.md C7.4, B14.1 (Juice-Tabelle), B14.4, B15.3,
--  docs/SKILL-WUENSCHE.md (Kopfschuss-Ding, Kill-Bestätigung, Treffer-Stopp, knackige Marker).
--
--  Fadenkreuz (4 Stile: Kreuz, Punkt, Kreis, T; Farbe/Größe/Lücke/Punkt aus den Einstellungen,
--  Streuung öffnet es), Leben (Herzschlag-Vignette < 30 HP), Munition (wackelt rot bei 0 + Nachlade-
--  Hinweis passend zum Gerät), Slot-Leiste, Hitmarker (vorläufig sofort, Server-Bestätigung ersetzt
--  ihn; Kopf = großes gelbes X + "HEADSHOT!" + Ding, Pop = rotes X + Kill-Jingle + Treffer-Stopp +
--  FOV-Punch), Schadenszahlen (stapeln pro Ziel 0.6 s), Richtungspfeile + rote Rand-Blende,
--  Kill-Banner + DOUBLE!/TRIPLE!/QUAD!/ACE!, Gegner-Umrisse über den Highlights-Verteiler.
--  Alles ist vorgebaut/gepoolt; UI-Werte werden nur bei Änderung geschrieben.
--
--  Öffentliche API (C7.4):
--    CombatHud.Show(on)  CombatHud.SetHp(hp, max)  CombatHud.SetAmmo(mag, max, reloading, reloadProgress?)
--    CombatHud.SetSpread(deg)  CombatHud.Hitmarker(region, killed, provisional?)
--    CombatHud.DamageNumber(pos, amount, head)  CombatHud.Hurt(fromPos, amount)  CombatHud.KillBanner(name)
--    CombatHud.SetSlots(loadout, equipped, charges)
--  Zusätzlich: CombatHud.MakePreview(parent): Frame (Fadenkreuz-Vorschau fürs Einstellungen-Fenster),
--    CombatHud.Frame(dt), CombatHud.Tick(), CombatHud.Init(ctx), CombatHud.Start()
--  Hört selbst: Hooks "Combat:Hit/Hurt/Heal/Armed/Disarmed", "Match:Start/Elim/AntiCamp/Left/Closed",
--    "Equip", "LocalPopped", "LocalRevived", "Settings", "Input". Feuert "Hitmarker"(region, killed).
-- =====================================================================

local CollectionService = game:GetService("CollectionService")
local HapticService = game:GetService("HapticService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent:WaitForChild("UI"))

local CombatHud = {}

local player = Players.LocalPlayer
local Theme = UI.Theme
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local RED = Color3.fromRGB(255, 50, 60)
local YELLOW = Color3.fromRGB(255, 225, 40)
local HIDDEN_CF = CFrame.new(0, -4000, 0)
local TRIANGLE = "rbxasset://textures/triangle.png"

-- Zeiten (Config.Client.Hud überschreibt)
local HUD = {
	HitmarkerBody = 0.12,
	HitmarkerHead = 0.22,
	HitmarkerKill = 0.4,
	DamageStack = 0.6,
	DamageLife = 0.85,
	HurtArrow = 1.2,
	LowHp = 30,
	LowAmmo = 0.25,
	MultiKillWindow = 4,
	KillBanner = 1.6,
	HitStopKill = 0.07, -- Treffer-Stopp beim Pop (Marker hält, Sounds geduckt, Mini-Ruck)
	HitStopHead = 0.04,
	FovPunch = 3, -- FOV +3 beim Pop (B14.1)
}

local ctx: any = nil
local combatGui: ScreenGui? = nil
local hudRoot: Frame? = nil -- Panels in ctx.Gui (Leben, Munition, Slots)
local shown = false
local popped = false

-- ---------------------------------------------------------------------
-- HILFEN
-- ---------------------------------------------------------------------
local function T(key: string, ...: any): string
	if ctx and type(ctx.T) == "function" then
		return ctx.T(key, ...)
	end
	return key
end

-- Schlüssel eines anderen Pakets (z. B. combat.popped von WP3), sonst eigener ui.-Ersatz
local function TOr(key: string, fallback: string, ...: any): string
	local lang = ctx and ctx.Lang
	if lang and type(lang.Has) == "function" then
		local ok, has = pcall(lang.Has, key)
		if ok and has then
			return T(key, ...)
		end
	end
	return T(fallback, ...)
end

local function settings(): { [string]: any }
	local module = ctx and ctx.Modules and ctx.Modules.Settings
	if module and type(module.Get) == "function" then
		local ok, value = pcall(module.Get)
		if ok and type(value) == "table" then
			return value
		end
	end
	local config = ctx and ctx.Config
	return config and config.Client and config.Client.DefaultSettings or {}
end

local function sfx(role: string, pos: Vector3?, opts: any?)
	local module = ctx and ctx.Modules and ctx.Modules.Sfx
	if module and type(module.Play) == "function" then
		pcall(module.Play, role, pos, opts)
	end
end

local function module(name: string): any
	return ctx and ctx.Modules and ctx.Modules[name]
end

local function inputKind(): string
	local controls = module("Controls")
	if controls and type(controls.Input) == "function" then
		local ok, kind = pcall(controls.Input)
		if ok and type(kind) == "string" then
			return kind
		end
	end
	return "KBM"
end

local function frame(props: { [string]: any }, children: { Instance }?): Frame
	local base: { [string]: any } = { BorderSizePixel = 0, BackgroundColor3 = WHITE }
	for key, value in pairs(props) do
		base[key] = value
	end
	return UI.Create("Frame", base, children)
end

local function outline(parent: Instance, thickness: number?)
	UI.Create("UIStroke", {
		Thickness = thickness or 1,
		Color = BLACK,
		Transparency = 0.25,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

-- ---------------------------------------------------------------------
-- FADENKREUZ (auch als Vorschau im Einstellungen-Fenster)
-- ---------------------------------------------------------------------
type Crosshair = {
	Root: Frame,
	Top: Frame,
	Bottom: Frame,
	Left: Frame,
	Right: Frame,
	Dot: Frame,
	Ring: Frame,
	RingStroke: UIStroke,
	Key: string,
}

local THICK = 2

local function buildCrosshair(parent: Instance, z: number): Crosshair
	local rootFrame = frame({
		Name = "Crosshair",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		ZIndex = z,
		Parent = parent,
	})
	local function bar(name: string): Frame
		local f = frame({ Name = name, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = z, Parent = rootFrame })
		outline(f)
		return f
	end
	local dot = frame({
		Name = "Dot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(THICK + 1, THICK + 1),
		ZIndex = z,
		Parent = rootFrame,
	})
	UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = dot })
	outline(dot)
	local ring = frame({
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = z,
		Parent = rootFrame,
	})
	UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = ring })
	local ringStroke: UIStroke = UI.Create("UIStroke", { Thickness = THICK, Color = WHITE, Parent = ring })
	return {
		Root = rootFrame,
		Top = bar("Top"),
		Bottom = bar("Bottom"),
		Left = bar("Left"),
		Right = bar("Right"),
		Dot = dot,
		Ring = ring,
		RingStroke = ringStroke,
		Key = "",
	}
end

local function crosshairColor(name: any): Color3
	local config = ctx and ctx.Config
	local colors = config and config.Client and config.Client.CrosshairColors
	local color = type(colors) == "table" and colors[name] or nil
	return if typeof(color) == "Color3" then color else WHITE
end

-- Stil 1 Kreuz, 2 Punkt, 3 Kreis, 4 T; spreadPx öffnet die Lücke (nur bei Änderung neu schreiben)
local function applyCrosshair(c: Crosshair, cfg: any, spreadPx: number)
	local style = math.clamp(math.floor(tonumber(cfg and cfg.Style) or 1), 1, 4)
	local size = math.clamp(tonumber(cfg and cfg.Size) or 8, 4, 16)
	local gap = math.clamp(tonumber(cfg and cfg.Gap) or 4, 0, 10) + spreadPx
	local dotOn = cfg == nil or cfg.Dot ~= false
	local colorName = cfg and cfg.Color or "White"
	local key = ("%d|%d|%.1f|%s|%s"):format(style, math.floor(size), gap, tostring(dotOn), tostring(colorName))
	if key == c.Key then
		return
	end
	c.Key = key
	local color = crosshairColor(colorName)
	local bars = style == 1 or style == 4
	c.Top.Visible = style == 1
	c.Bottom.Visible = bars
	c.Left.Visible = bars
	c.Right.Visible = bars
	c.Ring.Visible = style == 3
	c.Dot.Visible = style == 2 or dotOn
	local offset = gap + size / 2
	c.Top.Size = UDim2.fromOffset(THICK, size)
	c.Bottom.Size = UDim2.fromOffset(THICK, size)
	c.Left.Size = UDim2.fromOffset(size, THICK)
	c.Right.Size = UDim2.fromOffset(size, THICK)
	c.Top.Position = UDim2.fromOffset(0, -offset)
	c.Bottom.Position = UDim2.fromOffset(0, offset)
	c.Left.Position = UDim2.fromOffset(-offset, 0)
	c.Right.Position = UDim2.fromOffset(offset, 0)
	local ringSize = math.max(8, (gap + size / 2) * 2)
	c.Ring.Size = UDim2.fromOffset(ringSize, ringSize)
	local dotSize = if style == 2 then THICK + 3 else THICK + 1
	c.Dot.Size = UDim2.fromOffset(dotSize, dotSize)
	for _, f in ipairs({ c.Top, c.Bottom, c.Left, c.Right, c.Dot }) do
		f.BackgroundColor3 = color
	end
	c.RingStroke.Color = color
end

local crosshair: Crosshair? = nil
local previews: { Crosshair } = {}
local spreadDeg = 0
local spreadPx = 0

local function spreadToPixels(deg: number): number
	local camera = workspace.CurrentCamera
	if not camera or deg <= 0 then
		return 0
	end
	local fov = math.rad(math.clamp(camera.FieldOfView, 1, 120))
	local px = math.tan(math.rad(math.min(deg, 30))) / math.tan(fov / 2) * (camera.ViewportSize.Y / 2)
	return math.clamp(px, 0, 120)
end

local function refreshCrosshair()
	local cfg = settings().Crosshair
	if crosshair then
		applyCrosshair(crosshair, cfg, spreadPx)
	end
	for _, preview in ipairs(previews) do
		if preview.Root.Parent then
			applyCrosshair(preview, cfg, 0)
		end
	end
end

-- ---------------------------------------------------------------------
-- HITMARKER (vier schräge Balken um die Mitte)
-- ---------------------------------------------------------------------
type Marker =
	{ Holder: Frame, Scale: UIScale, Bars: { Frame }, Age: number, Life: number, Hold: number, Active: boolean }
local marker: Marker? = nil
local headshotLabel: TextLabel? = nil
local headshotScale: UIScale? = nil
local headshotUntil = 0

local function buildMarker(parent: Instance)
	local holder = frame({
		Name = "Hitmarker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(44, 44),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 6,
		Parent = parent,
	})
	local scale: UIScale = UI.Create("UIScale", { Parent = holder })
	local bars: { Frame } = {}
	for i, dir in ipairs({ Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) }) do
		local b = frame({
			Name = "Bar" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, dir.X * 11, 0.5, dir.Y * 11),
			Size = UDim2.fromOffset(3, 12),
			Rotation = if dir.X * dir.Y > 0 then -45 else 45,
			ZIndex = 6,
			Parent = holder,
		})
		outline(b)
		table.insert(bars, b)
	end
	marker = { Holder = holder, Scale = scale, Bars = bars, Age = 0, Life = 0.1, Hold = 0, Active = false }
	headshotLabel = UI.Label({
		Name = "Headshot",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 34),
		Size = UDim2.fromOffset(260, 40),
		Text = "",
		Font = UI.Fonts.Pop,
		TextColor3 = YELLOW,
		MaxText = 36,
		Outline = 3,
		Visible = false,
		ZIndex = 7,
		Parent = parent,
	})
	headshotScale = UI.Create("UIScale", { Parent = headshotLabel })
end

local function showMarker(color: Color3, length: number, thickness: number, life: number, hold: number, alpha: number)
	local m = marker
	if not m then
		return
	end
	m.Active = true
	m.Age = 0
	m.Life = life
	m.Hold = hold
	m.Scale.Scale = 1.55
	m.Holder.Rotation = math.random(-6, 6) -- jeder Treffer etwas anders = knackiger
	m.Holder.Visible = true
	for _, b in ipairs(m.Bars) do
		b.BackgroundColor3 = color
		b.Size = UDim2.fromOffset(thickness, length)
		b.BackgroundTransparency = alpha
	end
end

local function stepMarker(dt: number)
	local m = marker
	if m and m.Active then
		if m.Hold > 0 then
			m.Hold -= dt -- Treffer-Stopp: Marker friert kurz in voller Größe ein
			return
		end
		m.Age += dt
		local t = m.Age / m.Life
		if t >= 1 then
			m.Active = false
			m.Holder.Visible = false
			return
		end
		m.Scale.Scale = 1 + 0.55 * math.max(0, 1 - m.Age / 0.06)
		if t > 0.55 then
			local fade = (t - 0.55) / 0.45
			for _, b in ipairs(m.Bars) do
				b.BackgroundTransparency = math.max(b.BackgroundTransparency, fade)
			end
		end
	end
	local label = headshotLabel
	if label and label.Visible then
		local now = os.clock()
		if now >= headshotUntil then
			label.Visible = false
		elseif headshotScale then
			headshotScale.Scale = math.max(1, headshotScale.Scale - dt * 4)
		end
	end
end

-- ---------------------------------------------------------------------
-- FOV-PUNCH + TREFFER-STOPP (nach der FpsCamera, ohne deren FOV zu verfälschen)
-- ---------------------------------------------------------------------
local FOV_BIND = "ClutchClashFovPunch"
local punchAmount = 0
local punchTime = 0
local punchLeft = 0
local punchBound = false
local lastWrittenFov: number? = nil
local lastBaseFov: number? = nil

local function stepPunch(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	punchLeft -= dt
	local current = camera.FieldOfView
	-- Hat jemand (FpsCamera) seit unserem letzten Schreiben das FOV gesetzt? Dann ist das die neue Basis.
	local base = if lastWrittenFov
			and math.abs(current - lastWrittenFov) < 1e-3
			and lastBaseFov
		then lastBaseFov
		else current
	if punchLeft <= 0 then
		camera.FieldOfView = base
		lastWrittenFov, lastBaseFov = nil, nil
		if punchBound then
			punchBound = false
			RunService:UnbindFromRenderStep(FOV_BIND)
		end
		return
	end
	local t = 1 - punchLeft / punchTime
	local curve = if t < 0.2 then t / 0.2 else 1 - (t - 0.2) / 0.8 -- schnell rein, weich raus
	local value = math.clamp(base + punchAmount * curve, 1, 120)
	camera.FieldOfView = value
	lastWrittenFov, lastBaseFov = value, base
end

local function fovPunch(amount: number, duration: number)
	local mult = tonumber(settings().Shake)
	if mult then
		amount *= math.clamp(mult, 0, 1)
	end
	if amount <= 0.05 then
		return
	end
	punchAmount = amount
	punchTime = duration
	punchLeft = duration
	if not punchBound then
		punchBound = true
		RunService:BindToRenderStep(FOV_BIND, Enum.RenderPriority.Camera.Value + 5, stepPunch)
	end
end

local function hitStop(seconds: number, duck: number)
	local m = marker
	if m and m.Active then
		m.Hold = math.max(m.Hold, seconds)
	end
	local sfxModule = module("Sfx")
	if sfxModule and type(sfxModule.Duck) == "function" then
		pcall(sfxModule.Duck, duck, seconds + 0.05)
	end
	local camera = module("FpsCamera")
	local mult = tonumber(settings().Shake) or 1
	if camera and type(camera.Shake) == "function" and mult > 0 then
		pcall(camera.Shake, 0.18 * mult, seconds + 0.03)
	end
end

local function rumble(strength: number, seconds: number)
	if inputKind() ~= "Gamepad" then
		return
	end
	local ok = pcall(function()
		if HapticService:IsMotorSupported(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small) then
			HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, strength)
		end
	end)
	if ok then
		task.delay(seconds, function()
			pcall(function()
				HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, 0)
			end)
		end)
	end
end

-- ---------------------------------------------------------------------
-- KILL-BANNER + MEHRFACH-POPS
-- ---------------------------------------------------------------------
local bannerLabel: TextLabel? = nil
local bannerScale: UIScale? = nil
local bannerUntil = 0
local multiLabel: TextLabel? = nil
local multiScale: UIScale? = nil
local multiUntil = 0
local killTimes: { number } = {}
local MULTI_KEYS = { "", "ui.multi2", "ui.multi3", "ui.multi4", "ui.multi5" }
local BANNER_POP = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function buildBanners(parent: Instance)
	bannerLabel = UI.Label({
		Name = "KillBanner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.66),
		Size = UDim2.fromOffset(560, 52),
		Text = "",
		Font = UI.Fonts.Pop,
		TextColor3 = WHITE,
		MaxText = 46,
		Outline = 4,
		Visible = false,
		ZIndex = 8,
		Parent = parent,
	})
	bannerScale = UI.Create("UIScale", { Parent = bannerLabel })
	multiLabel = UI.Label({
		Name = "MultiKill",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.6),
		Size = UDim2.fromOffset(420, 60),
		Text = "",
		Font = UI.Fonts.Banner,
		TextColor3 = YELLOW,
		MaxText = 56,
		Outline = 4,
		Visible = false,
		ZIndex = 8,
		Parent = parent,
	})
	multiScale = UI.Create("UIScale", { Parent = multiLabel })
end

local function countKill(): number
	local now = os.clock()
	local window = HUD.MultiKillWindow
	local kept: { number } = {}
	for _, t in ipairs(killTimes) do
		if now - t <= window then
			table.insert(kept, t)
		end
	end
	table.insert(kept, now)
	while #kept > 5 do
		table.remove(kept, 1)
	end
	killTimes = kept
	return #kept
end

function CombatHud.KillBanner(name: string)
	local label = bannerLabel
	if not label then
		return
	end
	local text = TOr("combat.popped", "ui.popped", string.sub(tostring(name or "?"), 1, 32))
	label.Text = text
	label.TextColor3 = WHITE
	label.Visible = true
	bannerUntil = os.clock() + HUD.KillBanner
	if bannerScale then
		bannerScale.Scale = 0.5
		TweenService:Create(bannerScale, BANNER_POP, { Scale = 1 }):Play()
	end
	local n = countKill()
	local pitch = 1 + 0.12 * (n - 1) -- Tonhöhe steigt bei Mehrfach-Pops
	sfx("Kill", nil, { Speed = pitch })
	if n >= 2 and multiLabel then
		multiLabel.Text = T(MULTI_KEYS[math.min(n, #MULTI_KEYS)])
		multiLabel.Visible = true
		multiUntil = os.clock() + HUD.KillBanner + 0.3
		if multiScale then
			multiScale.Scale = 1.8
			TweenService:Create(multiScale, BANNER_POP, { Scale = 1 }):Play()
		end
		local effects = module("Effects")
		if n >= 3 and effects and type(effects.Confetti) == "function" then
			pcall(effects.Confetti, 0.5 + 0.25 * n)
		end
	end
end

local function stepBanners()
	local now = os.clock()
	if bannerLabel and bannerLabel.Visible and now >= bannerUntil then
		bannerLabel.Visible = false
	end
	if multiLabel and multiLabel.Visible and now >= multiUntil then
		multiLabel.Visible = false
	end
end

-- ---------------------------------------------------------------------
-- HITMARKER (öffentlich)
-- ---------------------------------------------------------------------
function CombatHud.Hitmarker(region: string, killed: boolean, provisional: boolean?)
	if not shown then
		return
	end
	if provisional then
		-- vorläufig (sofort beim Schuss): klein, halbdurchsichtig, nie als Kill
		showMarker(WHITE, 9, 2, 0.1, 0, 0.45)
		return
	end
	local head = region == "Head"
	if killed then
		showMarker(RED, 15, 4, HUD.HitmarkerKill, 0, 0)
		hitStop(HUD.HitStopKill, 0.55)
		fovPunch(HUD.FovPunch, 0.32)
		rumble(0.9, 0.08)
	elseif head then
		showMarker(YELLOW, 14, 4, HUD.HitmarkerHead, 0, 0)
		hitStop(HUD.HitStopHead, 0.35)
		rumble(0.7, 0.05)
	else
		showMarker(WHITE, 11, 3, HUD.HitmarkerBody, 0, 0)
		rumble(0.5, 0.04)
	end
	if head then
		sfx("Headshot")
		local label = headshotLabel
		if label then
			label.Text = T("ui.headshot")
			label.Visible = true
			headshotUntil = os.clock() + 0.7
			if headshotScale then
				headshotScale.Scale = 1.6
			end
		end
	elseif not killed then
		sfx("Hitmarker")
	end
	ctx.Hooks.Fire("Hitmarker", region, killed == true)
end

-- ---------------------------------------------------------------------
-- SCHADENSZAHLEN (24 BillboardGuis im Vorrat, stapeln pro Ziel)
-- ---------------------------------------------------------------------
type DamageEntry = {
	Gui: BillboardGui,
	Label: TextLabel,
	Scale: UIScale,
	Attachment: Attachment,
	Active: boolean,
	Age: number,
	Total: number,
	Head: boolean,
	Key: string,
	Base: Vector3,
	Drift: number,
	LastAdd: number,
}
local damagePool: { DamageEntry } = {}
local damageAnchor: Part? = nil

local function buildDamagePool(size: number)
	local folder = Instance.new("Folder")
	folder.Name = "ClutchClashDamageNumbers"
	folder.Parent = player:WaitForChild("PlayerGui")
	local anchorPart = Instance.new("Part")
	anchorPart.Name = "ClutchClashDamageAnchor"
	anchorPart.Anchored = true
	anchorPart.CanCollide = false
	anchorPart.CanQuery = false
	anchorPart.CanTouch = false
	anchorPart.CastShadow = false
	anchorPart.Transparency = 1
	anchorPart.Size = Vector3.new(0.2, 0.2, 0.2)
	anchorPart.CFrame = CFrame.new()
	anchorPart.Parent = workspace
	damageAnchor = anchorPart
	for i = 1, size do
		local attachment = Instance.new("Attachment")
		attachment.Name = "Dmg" .. i
		attachment.WorldPosition = HIDDEN_CF.Position
		attachment.Parent = anchorPart
		local gui = Instance.new("BillboardGui")
		gui.Name = "Damage" .. i
		gui.Adornee = attachment
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.MaxDistance = 600
		gui.Size = UDim2.fromOffset(150, 56)
		gui.ResetOnSpawn = false
		gui.Enabled = false
		gui.Parent = folder
		local label = UI.Label({
			Size = UDim2.fromScale(1, 1),
			Text = "",
			Font = UI.Fonts.Pop,
			MaxText = 44,
			Outline = 3,
			Parent = gui,
		})
		local scale: UIScale = UI.Create("UIScale", { Parent = label })
		table.insert(damagePool, {
			Gui = gui,
			Label = label,
			Scale = scale,
			Attachment = attachment,
			Active = false,
			Age = 0,
			Total = 0,
			Head = false,
			Key = "",
			Base = Vector3.zero,
			Drift = 0,
			LastAdd = 0,
		})
	end
end

local photoHidden = false -- Foto-Modus (Hook "PhotoMode"): keine Zahlen über den Köpfen

local function showDamage(key: string, pos: Vector3, amount: number, head: boolean)
	if photoHidden or settings().DamageNumbers == false or #damagePool == 0 then
		return
	end
	local now = os.clock()
	local entry: DamageEntry? = nil
	-- gleiches Ziel innerhalb von 0.6 s: Zahl stapelt sich
	for _, e in ipairs(damagePool) do
		if e.Active and e.Key == key and now - e.LastAdd <= HUD.DamageStack then
			entry = e
			break
		end
	end
	if not entry then
		local oldest: DamageEntry? = nil
		for _, e in ipairs(damagePool) do
			if not e.Active then
				entry = e
				break
			end
			if not oldest or e.LastAdd < oldest.LastAdd then
				oldest = e
			end
		end
		entry = entry or oldest
		if not entry then
			return
		end
		entry.Total = 0
		entry.Head = false
		entry.Drift = (math.random() - 0.5) * 1.2
	end
	local e = entry :: DamageEntry
	e.Active = true
	e.Key = key
	e.Age = 0
	e.LastAdd = now
	e.Total += math.max(0, math.floor(amount + 0.5))
	e.Head = e.Head or head
	e.Base = pos
	e.Label.Text = if e.Head then tostring(e.Total) .. "!" else tostring(e.Total)
	e.Label.TextColor3 = if e.Head then YELLOW else WHITE
	e.Label.TextTransparency = 0
	e.Scale.Scale = if head then 1.9 else 1.5
	e.Gui.Enabled = true
	e.Attachment.WorldPosition = pos
end

function CombatHud.DamageNumber(pos: Vector3, amount: number, head: boolean)
	if typeof(pos) ~= "Vector3" or type(amount) ~= "number" or amount ~= amount then
		return
	end
	-- öffentliche Variante ohne Ziel-Id: stapelt nach Nähe (≈ gleiches Ziel)
	local key = ("p%d_%d_%d"):format(math.floor(pos.X / 4), math.floor(pos.Y / 4), math.floor(pos.Z / 4))
	showDamage(key, pos, amount, head == true)
end

local function stepDamage(dt: number)
	local life = HUD.DamageLife
	for _, e in ipairs(damagePool) do
		if e.Active then
			e.Age += dt
			local t = e.Age / life
			if t >= 1 then
				e.Active = false
				e.Gui.Enabled = false
			else
				e.Scale.Scale = math.max(1, e.Scale.Scale - dt * 6)
				e.Attachment.WorldPosition = e.Base + Vector3.new(e.Drift * t, 1.2 + 2.2 * t, 0)
				if t > 0.6 then
					e.Label.TextTransparency = (t - 0.6) / 0.4
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- SCHADEN ERHALTEN: Richtungspfeile + rote Rand-Blende + Herzschlag
-- ---------------------------------------------------------------------
type Arrow = { Image: ImageLabel, From: Vector3, Age: number, Active: boolean }
local arrows: { Arrow } = {}
local arrowNext = 1
local edgeFrames: { Frame } = {}
local hurtFlash = 0
local hpNow = 100
local hpMax = 100
local heartClock = 0

local function buildHurt(parent: Instance)
	for i = 1, 4 do
		local image: ImageLabel = UI.Create("ImageLabel", {
			Name = "HurtArrow" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(30, 40),
			BackgroundTransparency = 1,
			Image = TRIANGLE,
			ImageColor3 = RED,
			Visible = false,
			ZIndex = 5,
			Parent = parent,
		})
		table.insert(arrows, { Image = image, From = Vector3.zero, Age = 0, Active = false })
	end
	-- Rand-Verlauf: vier Kanten, außen rot, innen durchsichtig (Frame + UIGradient)
	local edges = {
		{
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.fromScale(0, 0),
			Size = UDim2.fromScale(1, 0.22),
			Rot = 90,
		},
		{
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0.22),
			Rot = -90,
		},
		{ AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(0.16, 1), Rot = 0 },
		{
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromScale(0.16, 1),
			Rot = 180,
		},
	}
	for i, spec in ipairs(edges) do
		local f = frame({
			Name = "HurtEdge" .. i,
			AnchorPoint = spec.AnchorPoint,
			Position = spec.Position,
			Size = spec.Size,
			BackgroundColor3 = Color3.fromRGB(255, 20, 30),
			BackgroundTransparency = 1,
			ZIndex = 1,
			Parent = parent,
		})
		UI.Create("UIGradient", {
			Rotation = spec.Rot,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = f,
		})
		table.insert(edgeFrames, f)
	end
end

function CombatHud.Hurt(fromPos: Vector3, amount: number)
	if typeof(fromPos) == "Vector3" and #arrows > 0 then
		local arrow = arrows[arrowNext]
		arrowNext = arrowNext % #arrows + 1
		arrow.From = fromPos
		arrow.Age = 0
		arrow.Active = true
		arrow.Image.Visible = shown
	end
	local strength = math.clamp((tonumber(amount) or 10) / 40, 0.25, 1)
	hurtFlash = math.max(hurtFlash, strength)
	if hpNow <= HUD.LowHp then
		sfx("Hurt")
	end
	local effects = module("Effects")
	if effects and type(effects.Shake) == "function" then
		pcall(effects.Shake, 0.25 * strength)
	end
end

local function stepHurt(dt: number)
	local camera = workspace.CurrentCamera
	local gui = combatGui
	for _, arrow in ipairs(arrows) do
		if arrow.Active then
			arrow.Age += dt
			if arrow.Age >= HUD.HurtArrow or not camera or not gui then
				arrow.Active = false
				arrow.Image.Visible = false
			else
				local rel = camera.CFrame:PointToObjectSpace(arrow.From)
				local angle = math.atan2(rel.X, -rel.Z) -- 0 = vorne (oben auf dem Schirm)
				local size = gui.AbsoluteSize
				local radius = math.min(size.X, size.Y) * 0.2
				arrow.Image.Position =
					UDim2.fromOffset(size.X / 2 + math.sin(angle) * radius, size.Y / 2 - math.cos(angle) * radius)
				arrow.Image.Rotation = math.deg(angle)
				arrow.Image.ImageTransparency = math.clamp((arrow.Age / HUD.HurtArrow - 0.5) * 2, 0, 1)
				arrow.Image.Visible = shown
			end
		end
	end
	-- Blende: Treffer-Blitz + Herzschlag unter 30 HP
	hurtFlash = math.max(0, hurtFlash - dt * 2.2)
	local low = shown and not popped and hpNow > 0 and hpNow <= HUD.LowHp
	local beat = 0
	if low then
		heartClock += dt
		local danger = 1 - hpNow / math.max(1, HUD.LowHp)
		beat = (0.25 + 0.3 * danger) * (0.5 + 0.5 * math.sin(heartClock * (6 + 4 * danger)))
	end
	local alpha = math.max(hurtFlash * 0.75, beat)
	local transparency = if shown then 1 - alpha else 1
	for _, f in ipairs(edgeFrames) do
		if math.abs(f.BackgroundTransparency - transparency) > 0.01 then
			f.BackgroundTransparency = transparency
		end
	end
end

-- ---------------------------------------------------------------------
-- PANELS: Leben, Munition, Slots (in ctx.Gui, skaliert)
-- ---------------------------------------------------------------------
local hpPanel: Frame? = nil
local hpText: TextLabel? = nil
local hpFill: Frame? = nil
local ammoPanel: Frame? = nil
local ammoText: TextLabel? = nil
local ammoMaxText: TextLabel? = nil
local reloadBack: Frame? = nil
local reloadFill: Frame? = nil
local reloadHint: TextLabel? = nil
local slotPanel: Frame? = nil
local slotCells: { { Frame: Frame, Name: TextLabel, Key: TextLabel, Charges: TextLabel, Stroke: UIStroke, Scale: UIScale } } =
	{}
local lastHpKey = ""
local lastAmmoKey = ""
local lastSlotsKey = ""
local ammoMag = 0
local ammoShake = 0
local slotLoadout: { [string]: string } = {}
local slotCharges: { [string]: number } = {}
local slotEquipped = "Primary"
local SLOT_NAMES = { "Primary", "Secondary", "Melee", "Utility" }

local function buildPanels(parent: Frame)
	-- Leben unten links
	local hp = frame({
		Name = "Health",
		Size = UDim2.fromOffset(260, 64),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	hpText = UI.Label({
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(150, 40),
		Text = "❤ 100",
		Font = UI.Fonts.Number,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 36,
		Outline = 3,
		Parent = hp,
	})
	local back = frame({
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.fromOffset(240, 14),
		BackgroundColor3 = Color3.fromRGB(30, 30, 40),
		BackgroundTransparency = 0.25,
		Parent = hp,
	})
	UI.Create("UICorner", { CornerRadius = UDim.new(0, 7), Parent = back })
	UI.Create("UIStroke", { Thickness = 2, Color = BLACK, Parent = back })
	hpFill = frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Green,
		Parent = back,
	})
	UI.Create("UICorner", { CornerRadius = UDim.new(0, 7), Parent = hpFill })
	hpPanel = hp

	-- Munition unten rechts
	local ammo = frame({
		Name = "Ammo",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -18, 1, -12),
		Size = UDim2.fromOffset(240, 90),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	ammoText = UI.Label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -78, 0, 0),
		Size = UDim2.fromOffset(150, 52),
		Text = "",
		Font = UI.Fonts.Number,
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxText = 50,
		Outline = 3,
		Parent = ammo,
	})
	ammoMaxText = UI.Label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 18),
		Size = UDim2.fromOffset(76, 30),
		Text = "",
		Font = UI.Fonts.Number,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(220, 225, 235),
		MaxText = 26,
		Outline = 2,
		Parent = ammo,
	})
	local rBack = frame({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 56),
		Size = UDim2.fromOffset(200, 8),
		BackgroundColor3 = Color3.fromRGB(30, 30, 40),
		BackgroundTransparency = 0.25,
		Visible = false,
		Parent = ammo,
	})
	UI.Create("UICorner", { CornerRadius = UDim.new(0, 4), Parent = rBack })
	reloadFill = frame({ Size = UDim2.fromScale(0, 1), BackgroundColor3 = YELLOW, Parent = rBack })
	UI.Create("UICorner", { CornerRadius = UDim.new(0, 4), Parent = reloadFill })
	reloadBack = rBack
	reloadHint = UI.Label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 64),
		Size = UDim2.fromOffset(240, 26),
		Text = "",
		TextColor3 = RED,
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxText = 22,
		Outline = 2,
		Visible = false,
		Parent = ammo,
	})
	ammoPanel = ammo

	-- Slot-Leiste unten Mitte (auf Touch übernimmt TouchControls die Leiste zum Antippen)
	local slots = frame({
		Name = "Slots",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(4 * 92 + 3 * 8, 64),
		BackgroundTransparency = 1,
		Parent = parent,
	}, {
		UI.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for i = 1, 4 do
		local cell = frame({
			Name = "Slot" .. i,
			Size = UDim2.fromOffset(92, 56),
			BackgroundColor3 = Color3.fromRGB(25, 28, 45),
			BackgroundTransparency = 0.35,
			LayoutOrder = i,
			Parent = slots,
		})
		UI.Create("UICorner", { CornerRadius = UDim.new(0, 10), Parent = cell })
		local stroke: UIStroke = UI.Create("UIStroke", { Thickness = 2, Color = BLACK, Parent = cell })
		local scale: UIScale = UI.Create("UIScale", { Parent = cell })
		local key = UI.Label({
			Position = UDim2.fromOffset(6, 2),
			Size = UDim2.fromOffset(20, 18),
			Text = tostring(i),
			Font = UI.Fonts.Number,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color3.fromRGB(200, 205, 220),
			MaxText = 16,
			Outline = 1.5,
			Parent = cell,
		})
		local name = UI.Label({
			Position = UDim2.fromOffset(4, 18),
			Size = UDim2.new(1, -8, 0, 32),
			Text = "",
			MaxText = 22,
			Outline = 2,
			Parent = cell,
		})
		local charges = UI.Label({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 2),
			Size = UDim2.fromOffset(40, 18),
			Text = "",
			Font = UI.Fonts.Number,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = YELLOW,
			MaxText = 16,
			Outline = 1.5,
			Parent = cell,
		})
		table.insert(
			slotCells,
			{ Frame = cell, Name = name, Key = key, Charges = charges, Stroke = stroke, Scale = scale }
		)
	end
	slotPanel = slots
end

-- Geräte-Layout: Touch -> Leben/Munition oben (unten liegen Stick und Feuerknopf), keine Slot-Leiste
local function layoutPanels()
	local touch = inputKind() == "Touch"
	local hp, ammo, slots = hpPanel, ammoPanel, slotPanel
	if hp then
		hp.AnchorPoint = if touch then Vector2.new(0, 0) else Vector2.new(0, 1)
		hp.Position = if touch then UDim2.fromOffset(16, 8) else UDim2.new(0, 18, 1, -16)
	end
	if ammo then
		ammo.Visible = not touch -- Touch: Munition steht am FEUER-Knopf
	end
	if slots then
		slots.Visible = not touch
	end
	-- Tasten-Hinweise in der Slot-Leiste je Gerät
	local keyTexts = if inputKind() == "Gamepad" then { "Y", "Y", "LB", "RB" } else { "1", "2", "3", "4" }
	for i, cell in ipairs(slotCells) do
		cell.Key.Text = keyTexts[i]
	end
	lastAmmoKey = ""
end

function CombatHud.SetHp(hp: number, max: number)
	if type(hp) ~= "number" or hp ~= hp then
		return
	end
	hpMax = if type(max) == "number" and max > 0 then max else hpMax
	hpNow = math.clamp(hp, 0, hpMax)
	local shownHp = math.ceil(hpNow)
	local key = shownHp .. "/" .. hpMax
	if key == lastHpKey then
		return
	end
	lastHpKey = key
	local ratio = hpNow / hpMax
	if hpText then
		hpText.Text = "❤ " .. tostring(shownHp)
		hpText.TextColor3 = if hpNow <= HUD.LowHp then RED else WHITE
	end
	local fill = hpFill
	if fill then
		fill.Size = UDim2.fromScale(ratio, 1)
		fill.BackgroundColor3 = if ratio > 0.6 then Theme.Green elseif ratio > 0.3 then Theme.Yellow else RED
	end
end

local function reloadKeyText(): string
	local kind = inputKind()
	if kind == "Gamepad" then
		return "X"
	elseif kind == "Touch" then
		return T("ui.touch.reload")
	end
	local config = ctx and ctx.Config
	local keys = config and config.Client and config.Client.Keys
	local list = keys and keys.Reload
	return if type(list) == "table" and type(list[1]) == "string" then list[1] else "R"
end

function CombatHud.SetAmmo(mag: number, max: number, reloading: boolean, reloadProgress: number?)
	if type(mag) ~= "number" or type(max) ~= "number" then
		return
	end
	local touch = module("TouchControls")
	if touch and type(touch.SetAmmo) == "function" then
		pcall(touch.SetAmmo, mag, max, reloading, reloadProgress)
	end
	local m = math.max(0, math.floor(mag))
	local mx = math.max(0, math.floor(max))
	local progress = if reloading and type(reloadProgress) == "number"
		then math.clamp(reloadProgress, 0, 1)
		else if reloading then 0 else -1
	local key = ("%d/%d/%s/%d"):format(m, mx, tostring(reloading), math.floor(progress * 50))
	if key == lastAmmoKey then
		return
	end
	lastAmmoKey = key
	-- wenig Munition: doppelter Tick pro Schuss
	if mx > 0 and m < ammoMag and m > 0 and m / mx <= HUD.LowAmmo and not reloading then
		sfx("LowAmmo")
	end
	if m == 0 and ammoMag > 0 and not reloading then
		ammoShake = 0.45
	end
	ammoMag = m
	local unlimited = mx <= 0 -- Nahkampf/Utility ohne Magazin
	if ammoText then
		ammoText.Text = if unlimited then "∞" else tostring(m)
		ammoText.TextColor3 = if unlimited
			then WHITE
			elseif m == 0 then RED
			elseif m / mx <= HUD.LowAmmo then Theme.Orange
			else WHITE
	end
	if ammoMaxText then
		ammoMaxText.Text = if unlimited then "" else "/ " .. tostring(mx)
	end
	local back = reloadBack
	if back then
		back.Visible = reloading
		if reloadFill and reloading then
			reloadFill.Size = UDim2.fromScale(math.max(0, progress), 1)
		end
	end
	local hint = reloadHint
	if hint then
		local show = not unlimited and not reloading and m == 0
		hint.Visible = show
		if show then
			hint.Text = T("ui.reloadHint", reloadKeyText())
		end
	end
end

function CombatHud.SetSpread(deg: number)
	if type(deg) ~= "number" or deg ~= deg then
		return
	end
	spreadDeg = math.max(0, deg)
	local px = math.floor(spreadToPixels(spreadDeg) * 2 + 0.5) / 2
	if px ~= spreadPx then
		spreadPx = px
		refreshCrosshair()
	end
end

local function weaponShort(key: string?): string
	if type(key) ~= "string" or key == "" then
		return "–"
	end
	local config = ctx and ctx.Config
	if config and type(config.Weapon) == "function" then
		local ok, def = pcall(config.Weapon, key)
		if ok and type(def) == "table" then
			if type(def.Short) == "string" and def.Short ~= "" then
				return def.Short
			end
			if type(def.Name) == "table" then
				local okName, text = pcall(ctx.Lang.Pick, ctx.Lang_(), def.Name)
				if okName and type(text) == "string" then
					return text
				end
			end
		end
	end
	return key
end

function CombatHud.SetSlots(loadout: { [string]: string }, equipped: string, charges: { [string]: number })
	if type(loadout) == "table" then
		slotLoadout = loadout
	end
	if type(equipped) == "string" then
		slotEquipped = equipped
	end
	if type(charges) == "table" then
		slotCharges = charges
	end
	local parts: { string } = {}
	for _, name in ipairs(SLOT_NAMES) do
		table.insert(parts, tostring(slotLoadout[name]) .. ":" .. tostring(slotCharges[name]))
	end
	local key = table.concat(parts, ",") .. "|" .. slotEquipped
	if key ~= lastSlotsKey then
		lastSlotsKey = key
		for i, name in ipairs(SLOT_NAMES) do
			local cell = slotCells[i]
			if cell then
				local weapon = slotLoadout[name]
				cell.Name.Text = weaponShort(weapon)
				local charge = slotCharges[name]
				cell.Charges.Text = if type(charge) == "number" and name == "Utility" then "x" .. charge else ""
				local active = name == slotEquipped
				cell.Stroke.Color = if active then YELLOW else BLACK
				cell.Stroke.Thickness = if active then 3 else 2
				cell.Frame.BackgroundTransparency = if active then 0.1 else 0.45
				cell.Scale.Scale = if active then 1.08 else 1
			end
		end
	end
	local touch = module("TouchControls")
	if touch and type(touch.SetSlots) == "function" then
		pcall(touch.SetSlots, slotLoadout, slotEquipped, slotCharges)
	end
end

-- ---------------------------------------------------------------------
-- SICHTBARKEIT
-- ---------------------------------------------------------------------
local function applyShown()
	local visible = shown and not popped
	if combatGui then
		combatGui.Enabled = shown
	end
	if crosshair then
		crosshair.Root.Visible = visible
	end
	if hudRoot then
		hudRoot.Visible = visible
	end
	if not shown then
		for _, arrow in ipairs(arrows) do
			arrow.Active = false
			arrow.Image.Visible = false
		end
	end
end

function CombatHud.Show(on: boolean)
	shown = on == true
	applyShown()
end

-- ---------------------------------------------------------------------
-- GEGNER-UMRISSE (Highlights, Occluded, nur Umriss, Farbe aus den Einstellungen)
-- ---------------------------------------------------------------------
local myId = player.UserId
local myTeam = 0
local myCtx: string? = nil
local matchMode: string? = nil
local roster: { [number]: { Name: string, Team: number, IsBot: boolean } } = {}
local enemyHandles: { [number]: any } = {}
local modelCache: { [number]: Model } = {}
local armedMap: Instance? = nil -- Map des Kontexts aus "Armed" (für Puppen ohne Tag)
local lastScan = 0
local SCAN_GAP = 5

local function enemyColor(): Color3
	local config = ctx and ctx.Config
	local colors = config and config.Colors and config.Colors.Enemy
	local name = settings().EnemyColor
	local color = type(colors) == "table" and colors[name] or nil
	return if typeof(color) == "Color3" then color else RED
end

-- Combatant-Modell zu einer Id (Spieler, Bot mit Tag "Bot", Puppe) – gecacht, Suche gedrosselt
local function scanModels()
	local now = os.clock()
	if now - lastScan < SCAN_GAP then
		return
	end
	lastScan = now
	for _, tag in ipairs({ "Bot", "Dummy", "Combatant" }) do
		for _, inst in ipairs(CollectionService:GetTagged(tag)) do
			local id = inst:GetAttribute("CombatantId")
			if inst:IsA("Model") and type(id) == "number" then
				modelCache[id] = inst
			end
		end
	end
	-- Range-Puppen ohne Tag: in der Map des Kontexts suchen (begrenzt, höchstens alle 5 s)
	local map = armedMap
	if map and map.Parent then
		local checked = 0
		for _, inst in ipairs(map:GetDescendants()) do
			checked += 1
			if checked > 4000 then
				break
			end
			if inst:IsA("Model") then
				local id = inst:GetAttribute("CombatantId")
				if type(id) == "number" then
					modelCache[id] = inst
				end
			end
		end
	end
end

local function modelOf(id: number): Model?
	local cached = modelCache[id]
	if cached and cached.Parent and cached:GetAttribute("CombatantId") == id then
		return cached
	end
	modelCache[id] = nil
	local target = Players:GetPlayerByUserId(id)
	if target and target.Character then
		modelCache[id] = target.Character
		return target.Character
	end
	scanModels()
	local found = modelCache[id]
	if found and found.Parent then
		return found
	end
	return nil
end

local function nameOf(id: number): string
	local entry = roster[id]
	if entry then
		return entry.Name
	end
	local target = Players:GetPlayerByUserId(id)
	if target then
		return target.DisplayName
	end
	local model = modelOf(id)
	if model then
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.DisplayName ~= "" then
			return humanoid.DisplayName
		end
		return model.Name
	end
	return "?"
end

local function releaseEnemies()
	local highlights = module("Highlights")
	if highlights and type(highlights.ReleaseOwner) == "function" then
		pcall(highlights.ReleaseOwner, "Enemy")
	end
	table.clear(enemyHandles)
end

local function isEnemy(id: number): boolean
	if id == myId then
		return false
	end
	local entry = roster[id]
	if not entry then
		return false
	end
	return matchMode == "FFA" or entry.Team ~= myTeam
end

local function refreshEnemies()
	local highlights = module("Highlights")
	if not highlights or type(highlights.Acquire) ~= "function" then
		return
	end
	if not myCtx or string.sub(myCtx, 1, 1) ~= "M" then
		if next(enemyHandles) then
			releaseEnemies()
		end
		return
	end
	local color = enemyColor()
	for id in pairs(roster) do
		local handle = enemyHandles[id]
		local model = if isEnemy(id) then modelOf(id) else nil
		local alive = model ~= nil and model:GetAttribute("Alive") ~= false
		if model and alive then
			local ok, newHandle = pcall(highlights.Acquire, "Enemy", model, {
				Outline = color,
				FillTransparency = 1,
				Depth = Enum.HighlightDepthMode.Occluded,
			})
			enemyHandles[id] = if ok then newHandle else nil
		elseif handle then
			pcall(highlights.Release, handle)
			enemyHandles[id] = nil
		end
	end
	for id, handle in pairs(enemyHandles) do
		if not roster[id] then
			pcall(highlights.Release, handle)
			enemyHandles[id] = nil
		end
	end
end

-- ---------------------------------------------------------------------
-- SERVER-EREIGNISSE
-- ---------------------------------------------------------------------
local function targetPos(id: number, head: boolean): Vector3?
	local model = modelOf(id)
	if not model then
		return nil
	end
	local part = model:FindFirstChild(if head then "Head" else "HumanoidRootPart")
	if part and part:IsA("BasePart") then
		return part.Position + Vector3.new(0, if head then 1.2 else 1.4, 0)
	end
	local ok, pivot = pcall(model.GetPivot, model)
	return if ok then pivot.Position + Vector3.new(0, 2.5, 0) else nil
end

local function onHit(data: any)
	if type(data) ~= "table" then
		return
	end
	local head = data.H == true
	local killed = data.K == true
	CombatHud.Hitmarker(if head then "Head" else "Body", killed, false)
	local id = tonumber(data.T)
	local damage = tonumber(data.D) or 0
	if id then
		local pos = targetPos(id, head)
		if pos then
			showDamage("t" .. tostring(id), pos, damage, head)
			local fx = module("CombatFX")
			if head and fx and type(fx.Impact) == "function" then
				pcall(fx.Impact, pos - Vector3.new(0, 1, 0), nil, "Head") -- Sterne am Ziel (B14.1)
			end
		end
		if killed then
			CombatHud.KillBanner(nameOf(id))
		end
	end
end

local function onHurt(data: any)
	if type(data) ~= "table" then
		return
	end
	if type(data.Hp) == "number" then
		CombatHud.SetHp(data.Hp, hpMax)
	end
	local from = data.F
	if typeof(from) == "Vector3" then
		CombatHud.Hurt(from, tonumber(data.D) or 0)
	else
		hurtFlash = math.max(hurtFlash, 0.5)
	end
end

local function onArmed(info: any)
	if type(info) ~= "table" then
		return
	end
	myId = tonumber(info.Id) or player.UserId
	myTeam = tonumber(info.Team) or myTeam
	myCtx = if type(info.Ctx) == "string" then info.Ctx else nil
	armedMap = if typeof(info.Map) == "Instance" then info.Map else nil
	lastScan = 0
	popped = false
	table.clear(killTimes)
	local config = ctx.Config
	local maxHp = config and config.Player and tonumber(config.Player.MaxHp) or 100
	lastHpKey = ""
	CombatHud.SetHp(maxHp, maxHp)
	if type(info.Loadout) == "table" then
		local charges: { [string]: number } = {}
		if type(info.Ammo) == "table" then
			for slot, ammo in pairs(info.Ammo) do
				if type(slot) == "string" and type(ammo) == "table" and type(ammo.Charges) == "number" then
					charges[slot] = ammo.Charges
				end
			end
		end
		CombatHud.SetSlots(info.Loadout, "Primary", charges)
	end
	CombatHud.Show(true)
	refreshEnemies()
end

local function onMatchStart(data: any)
	if type(data) ~= "table" then
		return
	end
	table.clear(roster)
	myTeam = tonumber(data.MyTeam) or myTeam
	matchMode = if type(data.Mode) == "string" then data.Mode else nil
	if type(data.Roster) == "table" then
		local count = 0
		for _, entry in ipairs(data.Roster) do
			count += 1
			if count > 32 then
				break
			end
			if type(entry) == "table" and type(entry.Id) == "number" then
				roster[entry.Id] = {
					Name = string.sub(tostring(entry.Name or "?"), 1, 32),
					Team = tonumber(entry.Team) or 0,
					IsBot = entry.IsBot == true,
				}
			end
		end
	end
	refreshEnemies()
end

-- ---------------------------------------------------------------------
-- VORSCHAU (Einstellungen-Fenster)
-- ---------------------------------------------------------------------
function CombatHud.MakePreview(parent: GuiObject): Frame
	local holder = frame({
		Name = "CrosshairPreview",
		Size = UDim2.new(1, 0, 0, 90),
		BackgroundColor3 = Color3.fromRGB(70, 90, 110),
		Parent = parent,
	})
	UI.Create("UICorner", { CornerRadius = UDim.new(0, 12), Parent = holder })
	UI.Create("UIStroke", { Thickness = 2, Color = BLACK, Parent = holder })
	UI.Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(140, 190, 230), Color3.fromRGB(90, 120, 90)),
		Parent = holder,
	})
	local c = buildCrosshair(holder, 3)
	table.insert(previews, c)
	-- aufgeräumte Vorschauen aus der Liste nehmen
	for i = #previews, 1, -1 do
		if previews[i].Root.Parent == nil then
			table.remove(previews, i)
		end
	end
	applyCrosshair(c, settings().Crosshair, 0)
	return holder
end

-- ---------------------------------------------------------------------
-- FRAME / TICK / START
-- ---------------------------------------------------------------------
function CombatHud.Frame(dt: number)
	stepMarker(dt)
	stepDamage(dt)
	stepHurt(dt)
	stepBanners()
	if ammoShake > 0 and ammoText then
		ammoShake = math.max(0, ammoShake - dt)
		local offset = if ammoShake > 0 then math.sin(ammoShake * 70) * 6 * (ammoShake / 0.45) else 0
		ammoText.Position = UDim2.new(1, -78 + offset, 0, 0)
	end
end

function CombatHud.Tick()
	if shown then
		refreshEnemies()
	end
end

function CombatHud.Init(context: any)
	ctx = context
	local config = ctx.Config
	local hudConfig = config and config.Client and config.Client.Hud
	if type(hudConfig) == "table" then
		for key, value in pairs(hudConfig) do
			if type(value) == "number" and HUD[key] ~= nil then
				HUD[key] = value
			end
		end
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "ClutchClashCombat"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- Fadenkreuz exakt in der Bildmitte
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 0
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	combatGui = gui
	buildHurt(gui)
	crosshair = buildCrosshair(gui, 4)
	buildMarker(gui)
	buildBanners(gui)

	local panels: Frame = frame({
		Name = "CombatHud",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = ctx.Gui,
	})
	hudRoot = panels
	buildPanels(panels)
	local pools = config and config.Client and config.Client.Pools
	local damageSize = pools and tonumber(pools.DamageNumbers) or 24
	buildDamagePool(math.clamp(math.floor(damageSize), 4, 64))
	layoutPanels()
	refreshCrosshair()

	local hooks = ctx.Hooks
	hooks.On("Combat:Hit", onHit)
	hooks.On("Combat:Hurt", onHurt)
	hooks.On("Combat:Heal", function(data)
		if type(data) == "table" and type(data.Hp) == "number" then
			CombatHud.SetHp(data.Hp, hpMax)
		end
	end)
	hooks.On("Armed", onArmed)
	hooks.On("Disarmed", function()
		myCtx = nil
		armedMap = nil
		popped = false
		releaseEnemies()
		CombatHud.Show(false)
	end)
	hooks.On("Match:Start", onMatchStart)
	hooks.On("Match:Elim", function(data)
		local victim = type(data) == "table" and tonumber(data.V) or nil
		if victim and enemyHandles[victim] then
			local highlights = module("Highlights")
			if highlights then
				pcall(highlights.Release, enemyHandles[victim])
			end
			enemyHandles[victim] = nil
		end
	end)
	hooks.On("Match:Prep", refreshEnemies)
	hooks.On("Match:Live", refreshEnemies)
	hooks.On("Match:AntiCamp", function()
		local highlights = module("Highlights")
		local combat = config and config.Combat
		local seconds = combat and combat.AntiCamp and tonumber(combat.AntiCamp.Show) or 1
		if highlights and type(highlights.Pulse) == "function" then
			pcall(highlights.Pulse, "Enemy", seconds)
		end
	end)
	hooks.On("Match:Left", function(data)
		local id = type(data) == "table" and tonumber(data.Id) or nil
		if id then
			roster[id] = nil
			refreshEnemies()
		end
	end)
	hooks.On("Match:Closed", function()
		table.clear(roster)
		matchMode = nil
		releaseEnemies()
	end)
	hooks.On("Equip", function(slot)
		local name = if type(slot) == "number" then SLOT_NAMES[slot] else slot
		if type(name) == "string" then
			CombatHud.SetSlots(slotLoadout, name, slotCharges)
		end
	end)
	hooks.On("LocalPopped", function()
		popped = true
		applyShown()
	end)
	hooks.On("LocalRevived", function()
		popped = false
		applyShown()
		refreshEnemies()
	end)
	hooks.On("Settings", function()
		refreshCrosshair()
		local color = enemyColor()
		local highlights = module("Highlights")
		if highlights and type(highlights.Update) == "function" then
			for _, handle in pairs(enemyHandles) do
				pcall(highlights.Update, handle, { Outline = color, FillTransparency = 1 })
			end
		end
	end)
	hooks.On("Input", layoutPanels)
	hooks.On("PhotoMode", function(on)
		photoHidden = on == true
		if photoHidden then
			for _, e in ipairs(damagePool) do
				e.Active = false
				e.Gui.Enabled = false
			end
		end
	end)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			spreadPx = -1
			CombatHud.SetSpread(spreadDeg)
		end)
	end
end

function CombatHud.Start()
	applyShown()
	if damageAnchor and damageAnchor.Parent == nil then
		damageAnchor.Parent = workspace
	end
end

return CombatHud
