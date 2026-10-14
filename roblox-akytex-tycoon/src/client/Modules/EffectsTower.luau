-- =====================================================================
--  AKYTEX TYCOON – Tower-Effekte: Bau, Stufen-Morph, Gewinn-Röhre, Sammeln, Kran (Client/Modules/EffectsTower)
--  Besitzer: WP8 (Turm-Optik, Interiors, Lifestyle). Vertrag: DESIGN.md §C7.4 (Effekte BuildDone, StageUp,
--  TransferTube, Collect, Crane – Daten {Plot, Floor, Stage, Amount}), §A7 #1 (Etage gebaut: Kran hebt die Platte
--  2,5 s, Kamera-Orbit (überspringbar, bei ReducedFx sofort), Fenster leuchten auf, „+14 CR/s“ fliegt), §A7 #2
--  (Stufen-Morph 2,5 s: alte Teile faden, neue erscheinen, Krone leuchtet, Konfetti-Beams), §A7 #5 (Gewinn-
--  Transfer: leuchtende Röhre fliegt von der Börse zum eigenen Tower, CR-Zähler rollt), §B3 (Kran-Abbau 1,5 s
--  beim Verlassen), §0.3 Punkt 6 (Konfetti nur für Meilensteine – hier: Stufen-Morph).
--
--  Ein Effekt = ein Besitzer: die fünf Namen registriert NUR dieses Modul (Effects.Register in Init). Server
--  schickt sie über PlayerStateService.Effect/EffectAll; Main.client feuert danach Hook "Effect:<Name>".
--  Kein eigener Render-Loop: TowerView.Frame ruft EffectsTower.Step(dt) (Muss-Regel 2, ein PreRender-Loop).
--
--  Öffentliche API:
--    Effekte (Registry §C7.4): "BuildDone", "StageUp", "TransferTube", "Collect", "Crane"
--    EffectsTower.Step(dt)                     von TowerView.Frame
--    EffectsTower.OnTowerModel(plot, model)    von TowerView: neue Hülle eingehängt (Morph-Einblendung)
--    EffectsTower.Teardown(plot)               von TowerView: Plot frei geworden (Kran-Abbau-Staub)
--    EffectsTower.Init(ctx), EffectsTower.Start()
-- =====================================================================

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent:WaitForChild("UI"))
local TowerModels = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("TowerModels"))

local EffectsTower = {}

local Theme = UI.Theme
local player = Players.LocalPlayer

local ORBIT_SECONDS = 2.5
local LIFT_SECONDS = 2.5
local TUBE_SECONDS = 1.6
local MORPH_WINDOW = 4 -- Sekunden nach "StageUp", in denen eine neue Hülle eingeblendet wird
local REVEAL_SECONDS = 1.6
local VIEW_RANGE = 900
local EXCHANGE_FALLBACK = Vector3.new(0, 72, -190) -- §A5: Börsensaal (0, 0, −190), Höhe 70
local FLASH_INFO = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLOAT_INFO = TweenInfo.new(1.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

type Lift = { Plot: number, Part: BasePart, From: CFrame, To: CFrame, Start: number, Seconds: number }
type Reveal = {
	Plot: number,
	Model: Model,
	Start: number,
	Floors: { { Floor: number, Parts: { BasePart } } },
	Done: number,
}
type Tube = { Ball: BasePart, From: Vector3, Mid: Vector3, To: Vector3, Start: number, Amount: number }
type Beam = { Part: BasePart, From: CFrame, Start: number, Seconds: number, Height: number }

local ctx: any = nil
local fxFolder: Folder? = nil
local lifts: { Lift } = {}
local reveals: { Reveal } = {}
local tubes: { Tube } = {}
local beams: { Beam } = {}
local morphUntil: { [number]: number } = {}
local orbit: { Start: number, Center: Vector3, Radius: number, Height: number, Conn: RBXScriptConnection?, Saved: Enum.CameraType }? =
	nil

-- ---------------------------------------------------------------------
-- 1) HELFER
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

local function num(v: any, default: number): number
	return if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then v else default
end

local function reduced(): boolean
	local ok, settings = call("Settings", "Get")
	return ok and type(settings) == "table" and settings.ReducedFx == true
end

local function hidden(): boolean
	local ok, value = call("Effects", "IsHidden")
	return ok and value == true
end

local function sfx(role: string, pos: Vector3?)
	call("Sfx", "Play", role, pos)
end

local function credits(n: number): string
	local ok, text = pcall(ctx.Format.Credits, n, ctx.Lang_())
	return if ok then text else tostring(math.floor(n))
end

local function payload(data: any): (number?, { [string]: any })
	if type(data) ~= "table" then
		return nil, {}
	end
	local plot = data.Plot
	return if type(plot) == "number" and plot >= 1 then plot else nil, data
end

local function isMine(data: { [string]: any }): boolean
	return data.UserId == player.UserId
end

local function topCFrame(plot: number): CFrame?
	local ok, cf = call("TowerView", "TopCFrame", plot)
	return if ok and typeof(cf) == "CFrame" then cf else nil
end

local function cameraPos(): Vector3
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.Position else Vector3.zero
end

local function inView(pos: Vector3): boolean
	return (pos - cameraPos()).Magnitude <= VIEW_RANGE
end

local function localPart(props: { [string]: any }): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		(part :: any)[key] = value
	end
	part.Parent = fxFolder
	return part
end

-- schwebender Text über einem Punkt („+14 CR/s“)
local function floatText(position: Vector3, text: string, color: Color3)
	local anchor = localPart({ Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, CFrame = CFrame.new(position) })
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(260, 60)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 1200
	local label = UI.Label({
		Size = UDim2.fromScale(1, 1),
		Text = text,
		Face = "Display",
		TextColor3 = color,
		MaxText = 40,
		Outline = 1,
		Parent = billboard,
	})
	billboard.Parent = anchor
	TweenService:Create(billboard, FLOAT_INFO, { StudsOffset = Vector3.new(0, 10, 0) }):Play()
	local fade = TweenService:Create(
		label,
		TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.6),
		{ TextTransparency = 1 }
	)
	fade.Completed:Once(function()
		anchor:Destroy()
	end)
	fade:Play()
end

-- ---------------------------------------------------------------------
-- 2) KAMERA-ORBIT (eigener Bau, überspringbar, nicht bei ReducedFx/offenem Fenster/Auto)
-- ---------------------------------------------------------------------
local function endOrbit()
	local o = orbit
	if not o then
		return
	end
	orbit = nil
	if o.Conn then
		o.Conn:Disconnect()
	end
	call("WorldLook", "SetCinematic", false)
	local camera = workspace.CurrentCamera
	if camera and camera.CameraType == Enum.CameraType.Scriptable then
		camera.CameraType = o.Saved
	end
end

local function canOrbit(): boolean
	if reduced() or hidden() then
		return false
	end
	local camera = workspace.CurrentCamera
	if not camera or camera.CameraType ~= Enum.CameraType.Custom then
		return false
	end
	if ctx.Windows and ctx.Windows.IsOpen() then
		return false
	end
	local okVehicle, vehicle = call("Vehicles", "Current")
	return not (okVehicle and vehicle ~= nil)
end

local function startOrbit(plot: number)
	if orbit or not canOrbit() then
		return
	end
	local top = topCFrame(plot)
	local camera = workspace.CurrentCamera
	if not top or not camera then
		return
	end
	local o = {
		Start = os.clock(),
		Center = top.Position + Vector3.new(0, 6, 0),
		Radius = 70,
		Height = 22,
		Conn = nil :: RBXScriptConnection?,
		Saved = camera.CameraType,
	}
	camera.CameraType = Enum.CameraType.Scriptable
	call("WorldLook", "SetCinematic", true, o.Radius) -- Tower scharf, Stadt dahinter weich (High/Ultra)
	o.Conn = UserInputService.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if
			kind == Enum.UserInputType.MouseButton1
			or kind == Enum.UserInputType.Touch
			or kind == Enum.UserInputType.Keyboard
			or kind == Enum.UserInputType.Gamepad1
		then
			endOrbit()
		end
	end)
	orbit = o
end

local function stepOrbit()
	local o = orbit
	local camera = workspace.CurrentCamera
	if not o or not camera then
		return
	end
	local alpha = (os.clock() - o.Start) / ORBIT_SECONDS
	if alpha >= 1 or camera.CameraType ~= Enum.CameraType.Scriptable then
		endOrbit()
		return
	end
	local ease = 1 - (1 - alpha) ^ 3
	local angle = math.rad(-35 + ease * 110)
	local position = o.Center + Vector3.new(math.cos(angle) * o.Radius, o.Height - ease * 6, math.sin(angle) * o.Radius)
	camera.CFrame = CFrame.lookAt(position, o.Center)
end

-- ---------------------------------------------------------------------
-- 3) EFFEKT "Crane" – Kran erscheint, hebt die Platte (Bau gestartet)
-- ---------------------------------------------------------------------
local function onCrane(_strength: number, data: any)
	local plot, d = payload(data)
	if not plot or hidden() then
		return
	end
	local floor = math.max(1, math.floor(num(d.Floor, 1)))
	local seconds = num(d.Seconds, 3)
	call("TowerView", "ShowCrane", plot, floor, seconds)
	local ok, info = call("TowerView", "PlotInfo", plot)
	if not ok or type(info) ~= "table" then
		return
	end
	local pivot: CFrame = info.Pivot
	if not inView(pivot.Position) then
		return
	end
	if isMine(d) then
		sfx("Construct", pivot.Position)
	end
	-- nur kurze Szenen (≤ 6 s) zeigen die Platte am Haken – lange Bauten zeigen den Kran mit Restzeit
	if seconds > 6 or reduced() then
		return
	end
	local stage = math.max(1, math.floor(num(d.Stage, info.Stage)))
	local w = TowerModels.Footprint(stage, floor)
	local fh = TowerModels.FloorHeight()
	local target = pivot * CFrame.new(0, (floor - 1) * fh + 0.5, 0)
	local slab = localPart({
		Name = "LiftSlab",
		Size = Vector3.new(w, 1, w),
		Color = Color3.fromRGB(42, 51, 66),
		Material = Enum.Material.Concrete,
		CFrame = target * CFrame.new(0, 26, 0),
	})
	local glow = Instance.new("SelectionBox")
	glow.Adornee = slab
	glow.Color3 = Theme.Warn
	glow.LineThickness = 0.08
	glow.SurfaceTransparency = 1
	glow.Parent = slab
	table.insert(lifts, {
		Plot = plot,
		Part = slab,
		From = target * CFrame.new(0, 26, 0),
		To = target,
		Start = os.clock(),
		Seconds = math.clamp(math.min(seconds - 0.4, LIFT_SECONDS), 0.8, LIFT_SECONDS),
	})
end

local function stepLifts()
	local t = os.clock()
	for i = #lifts, 1, -1 do
		local lift = lifts[i]
		local alpha = math.clamp((t - lift.Start) / lift.Seconds, 0, 1)
		if lift.Part.Parent == nil then
			table.remove(lifts, i)
			continue
		end
		local ease = 1 - (1 - alpha) ^ 2
		lift.Part.CFrame = lift.From:Lerp(lift.To, ease)
		local ok, hook = call("TowerView", "CraneHook", lift.Plot)
		if ok and typeof(hook) == "Instance" and hook:IsA("BasePart") then
			hook.CFrame = CFrame.new(Vector3.new(hook.Position.X, lift.Part.Position.Y + 4, hook.Position.Z))
		end
		if alpha >= 1 and t - lift.Start > lift.Seconds + 1.2 then
			lift.Part:Destroy()
			table.remove(lifts, i)
		end
	end
end

local function dropLift(plot: number)
	for i = #lifts, 1, -1 do
		if lifts[i].Plot == plot then
			local part = lifts[i].Part
			TweenService:Create(part, TweenInfo.new(0.4), { Transparency = 1 }):Play()
			task.delay(0.45, function()
				part:Destroy()
			end)
			table.remove(lifts, i)
		end
	end
end

-- ---------------------------------------------------------------------
-- 4) EFFEKT "BuildDone" – Fenster leuchten auf, „+X CR/s“, Kamera-Orbit (eigener Bau)
-- ---------------------------------------------------------------------
local function flashFloor(plot: number, floor: number)
	local ok, bands = call("TowerView", "NeonBands", plot)
	if not ok or type(bands) ~= "table" then
		return
	end
	for _, part in ipairs(bands) do
		if part:GetAttribute("Floor") == floor and part.Parent then
			local color = part.Color
			part.Color = Color3.new(1, 1, 1)
			part.Material = Enum.Material.Neon
			TweenService:Create(part, FLASH_INFO, { Color = color }):Play()
		end
	end
end

local function onBuildDone(_strength: number, data: any)
	local plot, d = payload(data)
	if not plot or hidden() then
		return
	end
	dropLift(plot)
	local floor = math.max(1, math.floor(num(d.Floor, 1)))
	flashFloor(plot, floor)
	local top = topCFrame(plot)
	if not top or not inView(top.Position) then
		return
	end
	if isMine(d) then
		local amount = num(d.Amount, 0)
		if amount > 0 then
			floatText(top.Position + Vector3.new(0, 8, 0), T("tui.fx.perSec", credits(amount)), UI.UpColor())
		end
		sfx("Construct", top.Position)
		call("Hud", "PulseCredits", amount)
		startOrbit(plot)
	else
		call("Effects", "Burst", top.Position + Vector3.new(0, 4, 0), Theme.Accent, 12, false)
	end
end

-- ---------------------------------------------------------------------
-- 5) EFFEKT "StageUp" – Morph: alte Hülle blendet aus (TowerView), neue erscheint von unten nach oben
-- ---------------------------------------------------------------------
local function startReveal(plot: number, model: Model)
	local floors: { [number]: { BasePart } } = {}
	local maxFloor = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local f = num(d:GetAttribute("Floor"), -1)
			local key = if f >= 1 then f else 999 -- Säulen/Krone/Plot zuletzt
			floors[key] = floors[key] or {}
			table.insert(floors[key], d)
			if f > maxFloor then
				maxFloor = f
			end
			d.LocalTransparencyModifier = 1
		end
	end
	local ordered: { { Floor: number, Parts: { BasePart } } } = {}
	for f, parts in pairs(floors) do
		table.insert(ordered, { Floor = f, Parts = parts })
	end
	table.sort(ordered, function(a, b)
		return a.Floor < b.Floor
	end)
	table.insert(reveals, { Plot = plot, Model = model, Start = os.clock(), Floors = ordered, Done = 0 })
end

local function stepReveals()
	local t = os.clock()
	for i = #reveals, 1, -1 do
		local reveal = reveals[i]
		local count = #reveal.Floors
		local alpha = math.clamp((t - reveal.Start) / REVEAL_SECONDS, 0, 1)
		local target = math.ceil(alpha * count)
		while reveal.Done < target do
			reveal.Done += 1
			for _, part in ipairs(reveal.Floors[reveal.Done].Parts) do
				if part.Parent then
					part.LocalTransparencyModifier = 0
				end
			end
		end
		if reveal.Done >= count or reveal.Model.Parent == nil then
			for _, entry in ipairs(reveal.Floors) do
				for _, part in ipairs(entry.Parts) do
					part.LocalTransparencyModifier = 0
				end
			end
			table.remove(reveals, i)
		end
	end
end

-- Konfetti-Beams: leuchtende Säulen schießen aus dem Dach
local function launchBeams(top: CFrame, color: Color3)
	for i = 1, 6 do
		local a = (i - 1) / 6 * math.pi * 2
		local from = top * CFrame.new(math.cos(a) * 9, 2, math.sin(a) * 9)
		local part = localPart({
			Name = "StageBeam",
			Size = Vector3.new(0.8, 2, 0.8),
			Color = if i % 2 == 0 then Theme.Gold else color,
			Material = Enum.Material.Neon,
			CFrame = from,
		})
		table.insert(
			beams,
			{ Part = part, From = from, Start = os.clock() + i * 0.05, Seconds = 1.5, Height = 70 + i * 6 }
		)
	end
end

local function stepBeams()
	local t = os.clock()
	for i = #beams, 1, -1 do
		local beam = beams[i]
		local alpha = math.clamp((t - beam.Start) / beam.Seconds, 0, 1)
		if beam.Part.Parent == nil or alpha >= 1 then
			beam.Part:Destroy()
			table.remove(beams, i)
		else
			local height = math.max(2, beam.Height * (1 - (1 - alpha) ^ 3))
			beam.Part.Size = Vector3.new(0.8, height, 0.8)
			beam.Part.CFrame = beam.From * CFrame.new(0, height / 2, 0)
			beam.Part.Transparency = alpha ^ 2
		end
	end
end

local function stageName(stage: number): string
	local tower = ctx.Config.Tower
	local list = if type(tower) == "table" then tower.Stages else nil
	local entry = if type(list) == "table" then list[stage] else nil
	if type(entry) == "table" and type(entry.Name) == "table" then
		return ctx.Lang.Pick(ctx.Lang_(), entry.Name)
	end
	return tostring(stage)
end

local function onStageUp(_strength: number, data: any)
	local plot, d = payload(data)
	if not plot or hidden() then
		return
	end
	morphUntil[plot] = os.clock() + MORPH_WINDOW
	local top = topCFrame(plot)
	local stage = math.max(1, math.floor(num(d.Stage, 1)))
	if top and inView(top.Position) and not reduced() then
		launchBeams(top, Theme.Accent)
	end
	if isMine(d) then
		call("Effects", "Confetti", 1.5)
		call("Effects", "Flash", Theme.Gold, T("tui.fx.stage", stage, stageName(stage)))
		sfx("LevelUp")
		sfx("RallyFanfare")
	end
end

-- ---------------------------------------------------------------------
-- 6) EFFEKT "TransferTube" – leuchtende Röhre von der Börse zum eigenen Tower
-- ---------------------------------------------------------------------
local function exchangePosition(): Vector3
	local city = ctx.Config.City
	local zones = if type(city) == "table" then city.Zones else nil
	local exchange = if type(zones) == "table" then zones.Exchange else nil
	if type(exchange) == "table" then
		local c = exchange.Center
		if typeof(c) == "Vector3" then
			return c + Vector3.new(0, 70, 0)
		elseif type(c) == "table" and type(c[1]) == "number" then
			return Vector3.new(c[1], num(c[2], 0) + 70, num(c[3], -190))
		end
	end
	return EXCHANGE_FALLBACK
end

local function onTransferTube(_strength: number, data: any)
	local plot, d = payload(data)
	local amount = num(d.Amount, 0)
	if not plot or not isMine(d) then
		return
	end
	local top = topCFrame(plot)
	if not top or reduced() or hidden() then
		call("Effects", "Play", "CoinFly", math.max(1, amount))
		call("Hud", "PulseCredits", amount)
		return
	end
	local from = exchangePosition()
	local to = top.Position + Vector3.new(0, 6, 0)
	local mid = (from + to) / 2 + Vector3.new(0, math.max(60, (from - to).Magnitude * 0.25), 0)
	local ball = localPart({
		Name = "TransferTube",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3, 3, 3),
		Color = Theme.Up,
		Material = Enum.Material.Neon,
		CFrame = CFrame.new(from),
	})
	local light = Instance.new("PointLight")
	light.Color = Theme.Up
	light.Range = 18
	light.Brightness = 3
	light.Parent = ball
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 1, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -1, 0)
	a1.Parent = ball
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.9
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(Theme.Up, Theme.Accent)
	trail.Transparency = NumberSequence.new(0, 1)
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Parent = ball
	table.insert(tubes, { Ball = ball, From = from, Mid = mid, To = to, Start = os.clock(), Amount = amount })
	sfx("Whoosh")
end

local function stepTubes()
	local t = os.clock()
	for i = #tubes, 1, -1 do
		local tube = tubes[i]
		local alpha = math.clamp((t - tube.Start) / TUBE_SECONDS, 0, 1)
		local ease = alpha * alpha * (3 - 2 * alpha)
		local a = tube.From:Lerp(tube.Mid, ease)
		local b = tube.Mid:Lerp(tube.To, ease)
		if tube.Ball.Parent then
			tube.Ball.CFrame = CFrame.new(a:Lerp(b, ease))
		end
		if alpha >= 1 then
			table.remove(tubes, i)
			local ball = tube.Ball
			call("Effects", "Burst", tube.To, Theme.Up, 16, true)
			call("Effects", "Play", "CoinFly", math.max(1, tube.Amount))
			call("Hud", "PulseCredits", tube.Amount)
			if tube.Amount > 0 then
				floatText(tube.To + Vector3.new(0, 4, 0), T("tui.fx.credits", credits(tube.Amount)), UI.UpColor())
			end
			task.delay(0.9, function()
				ball:Destroy()
			end)
			ball.Transparency = 1
		end
	end
end

-- ---------------------------------------------------------------------
-- 7) EFFEKT "Collect" – Tresor geleert (Kassen-Tor, HUD, Hausmeister, Auto-Kassierer)
-- ---------------------------------------------------------------------
local function onCollect(strength: number, data: any)
	local plot, d = payload(data)
	if not plot or not isMine(d) then
		return
	end
	local amount = num(d.Amount, 0)
	local ok, model = call("TowerView", "TowerModel", plot)
	local vault: BasePart? = nil
	if ok and typeof(model) == "Instance" then
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") and part:GetAttribute("Vault") == true then
				vault = part
				break
			end
		end
	end
	if vault then
		call(
			"Effects",
			"Burst",
			vault.Position + Vector3.new(0, 2, 0),
			Theme.Gold,
			if strength < 1 then 8 else 18,
			false
		)
	end
	call("Effects", "Play", "CoinFly", math.max(1, amount))
	call("Hud", "PulseCredits", amount)
end

-- ---------------------------------------------------------------------
-- 8) VON TOWERVIEW: neue Hülle (Morph) / Plot frei (Abbau)
-- ---------------------------------------------------------------------
function EffectsTower.OnTowerModel(plot: number, model: Model)
	local untilT = morphUntil[plot]
	if not untilT or os.clock() > untilT or reduced() then
		return
	end
	morphUntil[plot] = nil
	startReveal(plot, model)
end

function EffectsTower.Teardown(plot: number)
	local ok, info = call("TowerView", "PlotInfo", plot)
	if not ok or type(info) ~= "table" or hidden() then
		return
	end
	local pivot: CFrame = info.Pivot
	if not inView(pivot.Position) then
		return
	end
	for i = 1, 4 do
		local a = (i - 1) / 4 * math.pi * 2
		call("Effects", "Puff", (pivot * CFrame.new(math.cos(a) * 18, 2, math.sin(a) * 18)).Position, Theme.Muted, 6)
	end
	sfx("Construct", pivot.Position)
end

function EffectsTower.Step(_dt: number)
	if #lifts > 0 then
		stepLifts()
	end
	if #reveals > 0 then
		stepReveals()
	end
	if #beams > 0 then
		stepBeams()
	end
	if #tubes > 0 then
		stepTubes()
	end
	if orbit then
		stepOrbit()
	end
end

function EffectsTower.Init(context: any)
	ctx = context
	local folder = Instance.new("Folder")
	folder.Name = "AkyTowerFX"
	folder.Parent = workspace
	fxFolder = folder
	local effects = ctx.Modules.Effects
	if not effects or type(effects.Register) ~= "function" then
		warn("[EffectsTower] Effects-Registry fehlt – Tower-Effekte aus")
		return
	end
	effects.Register("BuildDone", onBuildDone)
	effects.Register("StageUp", onStageUp)
	effects.Register("TransferTube", onTransferTube)
	effects.Register("Collect", onCollect)
	effects.Register("Crane", onCrane)
	player.CharacterAdded:Connect(function()
		endOrbit()
	end)
end

function EffectsTower.Start() end

return EffectsTower
