-- =====================================================================
--  ☄️ METEOR-RUN (Client)
--   • Run-HUD oben: ⏱️ Timer, 🚩 Checkpoint x/y, 🏆 Bestzeit (nur während eines Runs)
--   • rotierende Balken: jeder Client dreht sie selbst (Attribute vom Server, Winkel aus der
--     Serverzeit -> alle sehen dieselbe Stellung), mit lokaler Kollision
--   • Warnkreise + fallender Meteor + Einschlag für "RunImpact"
--   • Checkpoint-Funken + Ton, Ziel-Konfetti, roter Blitz beim Zurücksetzen
--   • Knopf "☄️ Run" in der rechten Leiste -> Request "GoRun"
--  Der Server schickt den Zustand als Spieler-Attribute (RunActive, RunStart, RunCP, RunBest,
--  RunCooldownUntil) und Effekte über Remotes.Effect ("RunImpact", "RunCheckpoint", ...).
-- =====================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent:WaitForChild("UI"))

local MeteorRun = {}

local player = Players.LocalPlayer
local ctx: any = nil
local Theme = UI.Theme
local BLACK = Color3.new(0, 0, 0)

local TAU = 2 * math.pi
local ANIM_RANGE = 420 -- weiter weg dreht sich nichts (spart Rechenzeit)
local IMPACT_POOL = 8 -- so viele Warnkreise gleichzeitig
local IMPACT_FALL_HEIGHT = 70 -- von hier fällt der Meteor in den Warnkreis
local IMPACT_WARN = 1 -- Sekunden (wie beim Server)
local FINISH_SHOW_TIME = 5 -- so lange bleibt die Zielzeit im HUD stehen
local PING_SOUND = "rbxasset://sounds/electronicpingshort.wav"

local HUD_POP_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local HUD_HIDE_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FLASH_INFO = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local CHECKPOINT_COLOR = Color3.fromRGB(80, 200, 255)
local CHECKPOINT_DONE_COLOR = Color3.fromRGB(90, 255, 120)
local WARN_COLOR = Color3.fromRGB(255, 40, 40)

-- 41.27 -> "0:41.3"
local function formatRunTime(seconds: number): string
	local tenths = math.floor(math.max(0, seconds) * 10 + 0.5)
	return string.format("%d:%04.1f", tenths // 600, (tenths % 600) / 10)
end

local function localPart(props: { [string]: any }): Part
	local base: { [string]: any } = {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	return UI.Create("Part", base)
end

-- ---------------------------------------------------------------------
-- HUD
-- ---------------------------------------------------------------------
local hudFrame: Frame
local hudScale: UIScale
local timerLabel: TextLabel
local cpLabel: TextLabel
local bestLabel: TextLabel
local subLabel: TextLabel
local flashFrame: Frame
local flashTween: Tween
local hudShown = false
local hudToken = 0
local lastTimerKey = -1
local checkpointCount = 4
local finishedText: string? = nil
local finishedUntil = 0

local function buildHud()
	hudFrame = UI.Create("Frame", {
		Name = "MeteorRunHud",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 54), -- unter den Bannern (Schauer, Egg Rush)
		Size = UDim2.fromOffset(420, 66),
		BackgroundColor3 = Theme.PanelDark,
		BackgroundTransparency = 0.1,
		Visible = false,
		ZIndex = 6,
		Parent = ctx.Gui,
	}, {
		UI.Corner(16),
		UI.Stroke(BLACK, 3),
		UI.Create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.fromRGB(255, 170, 120), Color3.fromRGB(150, 110, 255)),
			Transparency = NumberSequence.new(0.55),
		}),
	})
	hudScale = UI.Create("UIScale", { Scale = 0, Parent = hudFrame })
	timerLabel = UI.Label({
		Position = UDim2.fromOffset(12, 4),
		Size = UDim2.new(0.44, -12, 0, 38),
		Text = "⏱️ 0:00.0",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Yellow,
		MaxText = 32,
		Outline = 3,
		ZIndex = 7,
		Parent = hudFrame,
	})
	cpLabel = UI.Label({
		Position = UDim2.new(0.44, 0, 0, 8),
		Size = UDim2.new(0.24, 0, 0, 30),
		Text = "🚩 0/4",
		TextColor3 = Color3.fromRGB(140, 230, 255),
		MaxText = 24,
		Outline = 2,
		ZIndex = 7,
		Parent = hudFrame,
	})
	bestLabel = UI.Label({
		Position = UDim2.new(0.68, 0, 0, 8),
		Size = UDim2.new(0.32, -12, 0, 30),
		Text = "🏆 –",
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Color3.fromRGB(255, 230, 120),
		MaxText = 24,
		Outline = 2,
		ZIndex = 7,
		Parent = hudFrame,
	})
	subLabel = UI.Label({
		Position = UDim2.fromOffset(12, 42),
		Size = UDim2.new(1, -24, 0, 20),
		Text = "",
		TextColor3 = Theme.SubText,
		MaxText = 16,
		Outline = 2,
		ZIndex = 7,
		Parent = hudFrame,
	})
	-- roter Blitz beim Zurücksetzen (Lava, Runterfallen, Einschlag)
	flashFrame = UI.Create("Frame", {
		Name = "MeteorRunFlash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 60, 30),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = ctx.Gui,
	})
	flashTween = TweenService:Create(flashFrame, FLASH_INFO, { BackgroundTransparency = 1 })
end

local function showHud(show: boolean)
	if hudShown == show then
		return
	end
	hudShown = show
	hudToken += 1
	local token = hudToken
	if show then
		hudFrame.Visible = true
		hudScale.Scale = 0.5
		TweenService:Create(hudScale, HUD_POP_INFO, { Scale = 1 }):Play()
	else
		local tween = TweenService:Create(hudScale, HUD_HIDE_INFO, { Scale = 0 })
		tween.Completed:Connect(function()
			if hudToken == token then
				hudFrame.Visible = false
			end
		end)
		tween:Play()
	end
end

local function setText(label: TextLabel, text: string)
	if label.Text ~= text then
		label.Text = text
	end
end

-- Attribute -> HUD (Checkpoint, Bestzeit, Abklingzeit); der Timer läuft in stepHud
local function refreshHud()
	local active = player:GetAttribute("RunActive") == true
	local cp = tonumber(player:GetAttribute("RunCP")) or 0
	local best = tonumber(player:GetAttribute("RunBest")) or 0
	setText(cpLabel, ("🚩 %d/%d"):format(cp, checkpointCount))
	setText(bestLabel, if best > 0 then "🏆 " .. formatRunTime(best) else "🏆 –")
	lastTimerKey = -1
	showHud(active or os.clock() < finishedUntil)
end

local function subText(now: number): string
	local cooldown = tonumber(player:GetAttribute("RunCooldownUntil")) or 0
	if cooldown > now then
		return "⏳ Nächste Belohnung in " .. ctx.Util.FormatTime(math.ceil(cooldown - now))
	end
	return "🥚 Im Ziel wartet ein Gratis-Ei!"
end

local function stepHud()
	if not hudShown then
		return
	end
	local now = workspace:GetServerTimeNow()
	local active = player:GetAttribute("RunActive") == true
	local start = tonumber(player:GetAttribute("RunStart")) or 0
	local key: number
	if active and start > 0 then
		key = math.floor((now - start) * 10)
	elseif active then
		key = -2
	else
		key = -3
	end
	if key == lastTimerKey then
		return
	end
	lastTimerKey = key
	if key >= 0 then
		timerLabel.Text = "⏱️ " .. formatRunTime(now - start)
		timerLabel.TextColor3 = Theme.Yellow
	elseif key == -2 then
		timerLabel.Text = "☄️ BEREIT – los!"
		timerLabel.TextColor3 = Theme.Green
	else
		timerLabel.Text = finishedText or "🏁"
		timerLabel.TextColor3 = Theme.Gold
		if os.clock() >= finishedUntil then
			showHud(false)
		end
	end
	setText(subLabel, subText(now))
end

-- ---------------------------------------------------------------------
-- ROTIERENDE BALKEN + SCHWEBENDES BELOHNUNGS-EI
-- ---------------------------------------------------------------------
type Spinner = { Pivot: CFrame, Offset: CFrame, Axis: Vector3, Speed: number, T0: number }

local animParts: { BasePart } = {} -- für workspace:BulkMoveTo (Tabellen werden wiederverwendet)
local animCFrames: { CFrame } = {}
local spinners: { Spinner } = {}
local eggPart: BasePart? = nil
local eggBase = CFrame.new()
local animCenter = Vector3.zero
local animRadius = 0

local function addSpinner(bar: BasePart)
	local pivot = bar:GetAttribute("SpinPivot")
	local axis = bar:GetAttribute("SpinAxis")
	local speed = tonumber(bar:GetAttribute("SpinSpeed"))
	local t0 = tonumber(bar:GetAttribute("SpinT0"))
	if typeof(pivot) ~= "CFrame" or typeof(axis) ~= "Vector3" or not speed or not t0 then
		return
	end
	local unitAxis = if axis.Magnitude > 0 then axis.Unit else Vector3.yAxis
	table.insert(spinners, {
		Pivot = pivot,
		Offset = pivot:ToObjectSpace(bar.CFrame), -- Stellung zur Zeit T0 (so steht er auf dem Server)
		Axis = unitAxis,
		Speed = speed,
		T0 = t0,
	})
	table.insert(animParts, bar)
	table.insert(animCFrames, bar.CFrame)
	-- Drehung auch für die Physik: wer getroffen wird, wird mitgeschoben (nur lokal)
	bar.AssemblyAngularVelocity = pivot:VectorToWorldSpace(unitAxis) * speed
end

local function setupWorld(runFolder: Instance)
	checkpointCount = tonumber(runFolder:GetAttribute("CheckpointCount")) or checkpointCount
	local spinnerFolder = runFolder:WaitForChild("Spinners", 30)
	if spinnerFolder then
		for _, child in ipairs(spinnerFolder:GetChildren()) do
			if child:IsA("BasePart") then
				addSpinner(child)
			end
		end
	end
	local deco = runFolder:WaitForChild("Deco", 30)
	local egg = deco and deco:FindFirstChild("RewardEgg")
	if egg and egg:IsA("BasePart") then
		eggPart = egg
		eggBase = egg.CFrame
		table.insert(animParts, egg)
		table.insert(animCFrames, egg.CFrame)
	end
	-- grobe Vorab-Prüfung: Kreis um alles, was sich bewegt
	if #animParts > 0 then
		local sum = Vector3.zero
		for _, p in ipairs(animParts) do
			sum += p.Position
		end
		animCenter = sum / #animParts
		for _, p in ipairs(animParts) do
			animRadius = math.max(animRadius, (p.Position - animCenter).Magnitude)
		end
	end
	refreshHud()
end

local function stepSpinners()
	local count = #animParts
	if count == 0 then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera or (camera.CFrame.Position - animCenter).Magnitude > animRadius + ANIM_RANGE then
		return
	end
	local now = workspace:GetServerTimeNow()
	for i, spin in ipairs(spinners) do
		animCFrames[i] = spin.Pivot
			* CFrame.fromAxisAngle(spin.Axis, ((now - spin.T0) * spin.Speed) % TAU)
			* spin.Offset
	end
	if eggPart then
		animCFrames[count] = eggBase * CFrame.new(0, math.sin(now * 2) * 0.4, 0) * CFrame.Angles(0, now * 1.2, 0)
	end
	workspace:BulkMoveTo(animParts, animCFrames, Enum.BulkMoveMode.FireCFrameChanged)
end

-- ---------------------------------------------------------------------
-- WARNKREISE + EINSCHLÄGE
-- ---------------------------------------------------------------------
type Impact = {
	Disc: Part,
	Ring: Part,
	Rock: Part,
	Active: boolean,
	At: number,
	Position: Vector3,
	Radius: number,
}

local fxFolder: Folder
local impacts: { Impact } = {}
local activeImpacts = 0
local DISC_ROTATION = CFrame.Angles(0, 0, math.rad(90))
local HIDDEN = CFrame.new(0, -500, 0)

local function buildImpactPool()
	for _ = 1, IMPACT_POOL do
		local disc = localPart({
			Name = "RunWarn",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.12, 2, 2),
			Material = Enum.Material.Neon,
			Color = WARN_COLOR,
			Transparency = 1,
			CFrame = HIDDEN,
			Parent = fxFolder,
		})
		local ring = localPart({
			Name = "RunWarnRing",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.08, 2, 2),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 220, 60),
			Transparency = 1,
			CFrame = HIDDEN,
			Parent = fxFolder,
		})
		local rock = localPart({
			Name = "RunMeteor",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(3.4, 3.4, 3.4),
			Material = Enum.Material.CrackedLava,
			Color = Color3.fromRGB(255, 110, 40),
			Transparency = 1,
			CFrame = HIDDEN,
			Parent = fxFolder,
		})
		UI.Create("Trail", {
			Attachment0 = UI.Create("Attachment", { Position = Vector3.new(0, 1.2, 0), Parent = rock }),
			Attachment1 = UI.Create("Attachment", { Position = Vector3.new(0, -1.2, 0), Parent = rock }),
			Color = ColorSequence.new(Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 60, 20)),
			Transparency = NumberSequence.new(0.1, 1),
			Lifetime = 0.25,
			LightEmission = 1,
			Parent = rock,
		})
		table.insert(impacts, {
			Disc = disc,
			Ring = ring,
			Rock = rock,
			Active = false,
			At = 0,
			Position = Vector3.zero,
			Radius = 6,
		})
	end
end

local function hideImpact(impact: Impact)
	impact.Active = false
	activeImpacts -= 1
	impact.Disc.Transparency = 1
	impact.Ring.Transparency = 1
	impact.Rock.Transparency = 1
	impact.Disc.CFrame = HIDDEN
	impact.Ring.CFrame = HIDDEN
	impact.Rock.CFrame = HIDDEN
end

local function startImpact(data: any)
	if type(data) ~= "table" or typeof(data.Position) ~= "Vector3" then
		return
	end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - data.Position).Magnitude > ANIM_RANGE + 100 then
		return -- viel zu weit weg
	end
	-- freien Platz im Pool nehmen, sonst den ältesten
	local slot: Impact? = nil
	for _, impact in ipairs(impacts) do
		if not impact.Active then
			slot = impact
			break
		end
		if not slot or impact.At < slot.At then
			slot = impact
		end
	end
	if not slot then
		return
	end
	if slot.Active then
		hideImpact(slot)
	end
	slot.Active = true
	activeImpacts += 1
	slot.At = tonumber(data.At) or (workspace:GetServerTimeNow() + IMPACT_WARN)
	slot.Position = data.Position
	slot.Radius = tonumber(data.Radius) or 6
	local diameter = slot.Radius * 2
	slot.Ring.Size = Vector3.new(0.08, diameter, diameter)
	slot.Ring.CFrame = CFrame.new(data.Position + Vector3.new(0, 0.06, 0)) * DISC_ROTATION
	slot.Ring.Transparency = 0.2
	slot.Rock.Transparency = 0
end

local function stepImpacts()
	if activeImpacts <= 0 then
		return
	end
	local now = workspace:GetServerTimeNow()
	for _, impact in ipairs(impacts) do
		if impact.Active then
			local left = impact.At - now
			if left <= 0 then
				hideImpact(impact)
				local position = impact.Position
				ctx.Effects.Play("Hatch", 0, { Position = position + Vector3.new(0, 1, 0), Rarity = "Mythic" })
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") and (root.Position - position).Magnitude < impact.Radius * 3 then
					ctx.Effects.Play("Shake", 0.7)
				end
			else
				local progress = math.clamp(1 - left / IMPACT_WARN, 0, 1)
				local diameter = impact.Radius * 2 * (0.25 + 0.75 * progress)
				impact.Disc.Size = Vector3.new(0.12, diameter, diameter)
				impact.Disc.CFrame = CFrame.new(impact.Position + Vector3.new(0, 0.08, 0)) * DISC_ROTATION
				impact.Disc.Transparency = 0.25 + 0.25 * math.abs(math.sin(progress * math.pi * 4))
				local fall = (1 - progress) * (1 - progress)
				impact.Rock.CFrame =
					CFrame.new(impact.Position + Vector3.new(fall * 18, 1.7 + fall * IMPACT_FALL_HEIGHT, 0))
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- CHECKPOINT-, START-, ZIEL- UND RESET-EFFEKTE
-- ---------------------------------------------------------------------
local sparkHolder: Part
local sparkEmitter: ParticleEmitter
local pingSound: Sound
local checkpointPads: { [number]: BasePart } = {}

local function buildEffects()
	sparkHolder = localPart({
		Name = "RunSparks",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
		CFrame = HIDDEN,
		Parent = fxFolder,
	})
	sparkEmitter = UI.Create("ParticleEmitter", {
		Color = ColorSequence.new(CHECKPOINT_COLOR, CHECKPOINT_DONE_COLOR),
		LightEmission = 1,
		LightInfluence = 0,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0, 1),
		Lifetime = NumberRange.new(0.6, 1.1),
		Speed = NumberRange.new(14, 28),
		SpreadAngle = Vector2.new(60, 60),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -30, 0),
		Drag = 1.5,
		Rate = 0,
		Parent = sparkHolder,
	})
	-- Sound direkt im Ordner (nicht in einem Part) = überall gleich laut
	pingSound = UI.Create("Sound", { SoundId = PING_SOUND, Volume = 0.6, Parent = fxFolder })
end

local function ping(pitch: number)
	pingSound.PlaybackSpeed = pitch
	pingSound.TimePosition = 0
	pingSound:Play()
end

local function sparks(position: Vector3, amount: number)
	sparkHolder.CFrame = CFrame.new(position)
	sparkEmitter:Emit(amount)
end

-- Erreichte Checkpoints leuchten lokal grün
local function colorPads()
	local active = player:GetAttribute("RunActive") == true
	local cp = if active then tonumber(player:GetAttribute("RunCP")) or 0 else 0
	for index, pad in pairs(checkpointPads) do
		local color = if index <= cp then CHECKPOINT_DONE_COLOR else CHECKPOINT_COLOR
		if pad.Color ~= color then
			pad.Color = color
		end
	end
end

local function onEffect(name: any, strength: any, data: any)
	if name == "RunImpact" then
		startImpact(data)
	elseif name == "RunCheckpoint" then
		local position = type(data) == "table" and typeof(data.Position) == "Vector3" and data.Position or nil
		if position then
			sparks(position, 60)
		end
		ping(1.2)
		UI.Pulse(hudScale, 0.12)
		local time = type(data) == "table" and tonumber(data.Time)
		ctx.Toast(
			"🚩 Checkpoint "
				.. tostring(tonumber(strength) or 0)
				.. "/"
				.. checkpointCount
				.. (if time then "  ⏱️ " .. formatRunTime(time) else ""),
			"Success"
		)
	elseif name == "RunStart" then
		ping(1.5)
		UI.Pulse(hudScale, 0.15)
	elseif name == "RunReset" then
		ping(0.6)
		flashFrame.BackgroundTransparency = 0.55
		flashTween:Play()
		ctx.Effects.Play("Shake", 0.5)
	elseif name == "RunFinish" then
		local info = if type(data) == "table" then data else {}
		local time = tonumber(info.Time) or tonumber(strength) or 0
		finishedText = "🏁 " .. formatRunTime(time) .. (if info.NewBest == true then "  🏆 NEU!" else "")
		finishedUntil = os.clock() + FINISH_SHOW_TIME
		ping(1.8)
		task.delay(0.15, ping, 2.2)
		ctx.Effects.Play("Confetti", if info.Reward == true then 2.5 else 1.2)
		local egg = eggPart
		if egg then
			ctx.Effects.Play("Hatch", 0, { Position = egg.Position, Rarity = "Legendary" })
			sparks(egg.Position, 80)
		end
		refreshHud()
		task.delay(FINISH_SHOW_TIME + 0.1, refreshHud)
	end
end

-- ---------------------------------------------------------------------
-- START
-- ---------------------------------------------------------------------
function MeteorRun.Start(context: any)
	ctx = context
	buildHud()
	fxFolder = UI.Create("Folder", { Name = "MeteorRunClientFX", Parent = workspace })
	buildImpactPool()
	buildEffects()

	-- Knopf rechts (gleicher Stil wie die anderen): zum Start-Tor
	ctx.Hud.AddRightButton("☄️", "Run", Theme.Orange, 7, function()
		ctx.Request("GoRun")
	end)

	for _, attribute in ipairs({ "RunActive", "RunStart", "RunCP", "RunBest", "RunCooldownUntil" }) do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			refreshHud()
			colorPads()
		end)
	end
	ctx.Remotes.Effect.OnClientEvent:Connect(onEffect)

	RunService.RenderStepped:Connect(function()
		stepSpinners()
		stepImpacts()
		stepHud()
	end)

	-- Welt-Teile kommen vom Server (Map wird beim Serverstart gebaut)
	task.spawn(function()
		local map = workspace:WaitForChild("MeteorHeistMap", 120)
		local runFolder = map and map:WaitForChild("MeteorRun", 60)
		if not runFolder then
			warn("[MeteorRun] Strecke nicht gefunden – Run-Animationen aus")
			return
		end
		local pads = runFolder:WaitForChild("Checkpoints", 30)
		if pads then
			for _, pad in ipairs(pads:GetChildren()) do
				local index = pad:GetAttribute("CheckpointIndex")
				if pad:IsA("BasePart") and type(index) == "number" then
					checkpointPads[index] = pad
				end
			end
		end
		setupWorld(runFolder)
		colorPads()
	end)
	refreshHud()
end

return MeteorRun
