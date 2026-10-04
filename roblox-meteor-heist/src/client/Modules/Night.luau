-- =====================================================================
--  NACHT + GLÜCKS-ZÄHLER (alles lokal beim Client)
--   • Banner oben (in der Leiste vom Hud): "🌙 NACHT 2:31" bzw. "🔴 BLUTMOND 2:31 • 2x Glück",
--     kurz vorher "🌙 Nacht in 0:45"
--   • Glücks-Zähler: dezente Leiste bei Schritte/Geld (füllt sich, bis wieder ein Legendary+ kommt)
--   • Sternschnuppen am Himmel (nur Deko), Sternschnuppen-Eier funkeln, leuchtende Kisten wippen
--   • Kiste geöffnet (Effekt "NightCrate" vom Server): Funken-Explosion
--  Liest nur Attribute an ReplicatedStorage: IsNight, BloodMoon, NightUntil, NextNightAt,
--  PityCount, PityFull, PityMult.
-- =====================================================================

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent:WaitForChild("UI"))

local Night = {}

local ctx: any = nil
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local NIGHT_COLOR = Color3.fromRGB(70, 80, 200)
local BLOOD_COLOR = Color3.fromRGB(210, 30, 40)
local STAR_COLOR = Color3.fromRGB(255, 240, 170)
local CRATE_GLOW = Color3.fromRGB(255, 215, 90)

local SHOW_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local HIDE_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local SOON = 90 -- so viele Sekunden vorher zeigt der Countdown "Nacht in ..."
local SKY_STAR_GAP = { 1.5, 4 } -- Deko-Sternschnuppen am Himmel: alle 1,5-4 s
local SKY_STAR_TIME = 1.1
local CRATE_BOB = 0.4 -- Kisten wippen so viele Studs auf und ab
local CRATE_RANGE = 160 -- Kisten nur in Kameranähe animieren

type Pill = { Frame: Frame, Label: TextLabel, Gradient: UIGradient, Scale: UIScale, Shown: boolean, Token: number }

local nightPill: Pill
local soonPill: Pill
local pityBar: any
local fxFolder: Folder? = nil
local nextSkyStar = 0
type CrateAnim = { Model: Model, Parts: { BasePart }, Base: { CFrame }, Phase: number }
local crateAnims: { CrateAnim } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

-- ---------------------------------------------------------------------
-- BANNER
-- ---------------------------------------------------------------------
local function makePill(parent: Instance, name: string, width: number, height: number, order: number): Pill
	local frame: Frame = UI.Create("Frame", {
		Name = name,
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = WHITE,
		Visible = false,
		LayoutOrder = order,
		ZIndex = 5,
		Parent = parent,
	}, { UI.Corner(14), UI.Stroke(BLACK, 3) })
	local gradient: UIGradient =
		UI.Create("UIGradient", { Rotation = 90, Color = UI.ButtonSequence(NIGHT_COLOR), Parent = frame })
	local scale: UIScale = UI.Create("UIScale", { Scale = 0, Parent = frame })
	local label = UI.Label({
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 1, -8),
		MaxText = 22,
		Outline = 2,
		ZIndex = 6,
		Parent = frame,
	})
	return { Frame = frame, Label = label, Gradient = gradient, Scale = scale, Shown = false, Token = 0 }
end

local function showPill(pill: Pill, show: boolean)
	if pill.Shown == show then
		return
	end
	pill.Shown = show
	pill.Token += 1
	local token = pill.Token
	if show then
		pill.Frame.Visible = true
		pill.Scale.Scale = 0.4
		TweenService:Create(pill.Scale, SHOW_INFO, { Scale = 1 }):Play()
	else
		local hide = TweenService:Create(pill.Scale, HIDE_INFO, { Scale = 0 })
		hide.Completed:Connect(function()
			if pill.Token == token then
				pill.Frame.Visible = false
			end
		end)
		hide:Play()
	end
end

local function setText(label: TextLabel, text: string)
	if label.Text ~= text then
		label.Text = text
	end
end

local function buildUI()
	local top = ctx.Hud.TopBar and ctx.Hud.TopBar()
	local parent = top or ctx.Gui
	nightPill = makePill(parent, "NightBanner", 360, 42, 0)
	soonPill = makePill(parent, "NightSoon", 220, 30, 5)
	-- Glücks-Zähler: kleine Leiste bei Schritte/Geld (Handy: oben links unter der Anzeige)
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	pityBar = UI.Bar({
		Size = UDim2.fromOffset(200, 22),
		Position = if touchOnly then UDim2.fromOffset(14, 166) else UDim2.new(0, 18, 1, -196),
		Color = UI.Theme.Green,
		MaxText = 14,
		Parent = ctx.Gui,
	})
	pityBar.Frame.Name = "LuckBar"
	pityBar.Frame.BackgroundTransparency = 0.25
end

-- Jede Sekunde (und bei Attribut-Änderung): Banner + Glücks-Leiste
local function refresh()
	local Util = ctx.Util
	local t = now()
	local isNight = ReplicatedStorage:GetAttribute("IsNight") == true
	local blood = isNight and ReplicatedStorage:GetAttribute("BloodMoon") == true
	local nightUntil = tonumber(ReplicatedStorage:GetAttribute("NightUntil")) or 0
	local nextNight = tonumber(ReplicatedStorage:GetAttribute("NextNightAt")) or 0

	if isNight then
		local left = Util.FormatTime(nightUntil - t)
		if blood then
			local luck = ctx.Config.Night and ctx.Config.Night.BloodMoonLuck or 2
			setText(nightPill.Label, "🔴 BLUTMOND " .. left .. " • " .. UI.FormatMult(luck) .. "x Glück")
		else
			setText(nightPill.Label, "🌙 NACHT " .. left .. " • Sternschnuppen")
		end
		nightPill.Gradient.Color = UI.ButtonSequence(if blood then BLOOD_COLOR else NIGHT_COLOR)
	end
	showPill(nightPill, isNight)
	local soon = not isNight and nextNight > t and nextNight - t <= SOON
	if soon then
		setText(soonPill.Label, "🌙 Nacht in " .. Util.FormatTime(nextNight - t))
	end
	showPill(soonPill, soon)

	local count = tonumber(ReplicatedStorage:GetAttribute("PityCount")) or 0
	local full = math.max(1, tonumber(ReplicatedStorage:GetAttribute("PityFull")) or 160)
	local mult = tonumber(ReplicatedStorage:GetAttribute("PityMult")) or 1
	UI.SetBar(pityBar, count / full, "🍀 Glück x" .. UI.FormatMult(mult))
end

-- ---------------------------------------------------------------------
-- WELT-EFFEKTE
-- ---------------------------------------------------------------------
local function localPart(props: { [string]: any }): BasePart
	props.Anchored = true
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	props.CastShadow = false
	return UI.Create("Part", props)
end

-- Funkelnde Sterne an einem Teil (nur lokal)
local function addStarEmitter(parent: BasePart, color: Color3, rate: number, size: number): ParticleEmitter
	return UI.Create("ParticleEmitter", {
		Name = "NightStars",
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(WHITE, color),
		LightEmission = 1,
		LightInfluence = 0,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0, 0.7),
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 2, 0),
		Rate = rate,
		Parent = parent,
	})
end

-- Sternschnuppen-Ei am Boden: funkelt + kleines Licht
local function onGroundEgg(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	local function decorate()
		if inst:GetAttribute("ShootingStar") ~= true or inst:FindFirstChild("NightStars") then
			return
		end
		addStarEmitter(inst, STAR_COLOR, 8, math.clamp(inst.Size.X * 0.15, 0.3, 0.8))
		if not inst:FindFirstChildOfClass("PointLight") then
			UI.Create(
				"PointLight",
				{ Color = STAR_COLOR, Range = 10, Brightness = 1.5, Shadows = false, Parent = inst }
			)
		end
	end
	decorate()
	inst:GetAttributeChangedSignal("ShootingStar"):Connect(decorate)
end

-- Leuchtende Kiste: Funkeln + Wippen (lokal)
local function onCrate(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	task.defer(function()
		local parts: { BasePart } = {}
		local base: { CFrame } = {}
		for _, child in ipairs(inst:GetChildren()) do
			if child:IsA("BasePart") then
				table.insert(parts, child)
				table.insert(base, child.CFrame)
			end
		end
		local glow = inst:FindFirstChild("Glow")
		if glow and glow:IsA("BasePart") then
			addStarEmitter(glow, glow.Color, 6, 0.5)
		end
		if #parts > 0 then
			table.insert(crateAnims, { Model = inst, Parts = parts, Base = base, Phase = math.random() * math.pi * 2 })
		end
	end)
end

local function stepCrates(t: number)
	local camera = workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position
	for i = #crateAnims, 1, -1 do
		local anim = crateAnims[i]
		if not anim.Model.Parent then
			table.remove(crateAnims, i)
		elseif camPos and (anim.Base[1].Position - camPos).Magnitude < CRATE_RANGE then
			local offset = CFrame.new(0, (math.sin(t * 2 + anim.Phase) + 1) * CRATE_BOB, 0)
			for k, part in ipairs(anim.Parts) do
				part.CFrame = offset * anim.Base[k]
			end
		end
	end
end

-- Deko-Sternschnuppe: leuchtender Punkt mit Schweif fliegt hoch über der Kamera schräg durchs Bild
local function skyStar()
	local folder = fxFolder
	local camera = workspace.CurrentCamera
	if not folder or not camera then
		return
	end
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local side = Vector3.new(-flat.Z, 0, flat.X)
	local center = camera.CFrame.Position + flat * math.random(250, 400) + Vector3.new(0, math.random(140, 220), 0)
	local dir = (side * (if math.random() < 0.5 then 1 else -1) + Vector3.new(0, -0.35, 0)).Unit
	local from = center - dir * 120
	local to = center + dir * 120
	local head = localPart({
		Name = "SkyStar",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2, 2, 2),
		Material = Enum.Material.Neon,
		Color = STAR_COLOR,
		CFrame = CFrame.new(from),
		Parent = folder,
	})
	local a0 = UI.Create("Attachment", { Position = Vector3.new(0, 0.8, 0), Parent = head })
	local a1 = UI.Create("Attachment", { Position = Vector3.new(0, -0.8, 0), Parent = head })
	UI.Create("Trail", {
		Attachment0 = a0,
		Attachment1 = a1,
		Color = ColorSequence.new(WHITE, STAR_COLOR),
		Transparency = NumberSequence.new(0, 1),
		Lifetime = 0.5,
		LightEmission = 1,
		FaceCamera = true,
		Parent = head,
	})
	local info = TweenInfo.new(SKY_STAR_TIME, Enum.EasingStyle.Linear)
	TweenService:Create(head, info, { CFrame = CFrame.new(to), Transparency = 1 }):Play()
	Debris:AddItem(head, SKY_STAR_TIME + 0.6)
end

-- Kiste geöffnet: Funken in Kistenfarbe (bzw. bunt bei Glücksrad-Dreh)
local function crateBurst(data: any)
	local folder = fxFolder
	if not folder or type(data) ~= "table" or typeof(data.Position) ~= "Vector3" then
		return
	end
	local holder = localPart({
		Name = "CrateBurst",
		Size = Vector3.new(1, 1, 1),
		Transparency = 1,
		CFrame = CFrame.new(data.Position),
		Parent = folder,
	})
	local emitter = addStarEmitter(holder, if data.Spin then UI.Theme.Pink else CRATE_GLOW, 0, 0.9)
	emitter.Speed = NumberRange.new(8, 16)
	emitter.Acceleration = Vector3.new(0, -12, 0)
	emitter:Emit(30)
	Debris:AddItem(holder, 2)
end

-- ---------------------------------------------------------------------
-- START
-- ---------------------------------------------------------------------
local function watch(map: Instance, name: string, onChild: (Instance) -> ())
	task.spawn(function()
		local folder = map:WaitForChild(name, 60)
		if not folder then
			return
		end
		for _, child in ipairs(folder:GetChildren()) do
			onChild(child)
		end
		folder.ChildAdded:Connect(onChild)
	end)
end

function Night.Init(context: any)
	ctx = context
	buildUI()
	fxFolder = UI.Create("Folder", { Name = "MeteorHeistNightFX", Parent = workspace })
	for _, name in ipairs({ "IsNight", "BloodMoon", "NightUntil", "NextNightAt", "PityCount", "PityMult" }) do
		ReplicatedStorage:GetAttributeChangedSignal(name):Connect(refresh)
	end
	ctx.Remotes.Effect.OnClientEvent:Connect(function(name, _strength, data)
		if name == "NightCrate" then
			crateBurst(data)
		end
	end)
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		if #crateAnims > 0 then
			stepCrates(t)
		end
		if ReplicatedStorage:GetAttribute("IsNight") == true and t >= nextSkyStar then
			nextSkyStar = t + SKY_STAR_GAP[1] + math.random() * (SKY_STAR_GAP[2] - SKY_STAR_GAP[1])
			skyStar()
		end
	end)
	task.spawn(function()
		while true do
			local ok, err = pcall(refresh)
			if not ok then
				warn("[Night] " .. tostring(err))
			end
			task.wait(1)
		end
	end)
	task.spawn(function()
		local map = workspace:WaitForChild("MeteorHeistMap", 120)
		if map then
			watch(map, "GroundMeteors", onGroundEgg)
			watch(map, "NightCrates", onCrate)
		end
	end)
end

return Night
