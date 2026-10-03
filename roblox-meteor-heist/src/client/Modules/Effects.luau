-- =====================================================================
--  EFFEKTE vom Server (Remote "Effect": name, strength, data)
--   "Steps"    -> fliegende "+X 👟"-Zahl über deinem Charakter (wie im Speed-Simulator)
--   "Collect"  -> großes "+$X" in der Bildschirmmitte
--   "Deliver"  -> Geister-Meteor fliegt im Bogen vom Laufband in die Base
--   "Hatch"    -> Funken-Explosion + Lichtblitz, wenn ein Alien schlüpft
--   "Shake", "Confetti", "Alarm" wie bisher
--  Alles läuft lokal (nichts davon wird an andere Spieler geschickt).
-- =====================================================================

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent:WaitForChild("UI"))

local Effects = {}

local player = Players.LocalPlayer
local ctx: any = nil
local fxFolder: Folder? = nil
local hidden = false -- Foto-Modus: fliegende Zahlen aus

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

-- ---------------------------------------------------------------------
-- FLIEGENDE SCHRITTE-ZAHLEN (fester Vorrat von 12, wird wiederverwendet)
-- ---------------------------------------------------------------------
type FlyNumber = {
	Gui: BillboardGui,
	Label: TextLabel,
	Stroke: UIStroke,
	Scale: UIScale,
	Active: boolean,
	Age: number,
	X: number,
	Y: number,
}

local FLY_COUNT = 12
local FLY_LIFE = 1.1
local FLY_RISE = 3.6
local FLY_COLORS = { Color3.fromRGB(255, 225, 40), Color3.fromRGB(70, 190, 255) }
local flyPool: { FlyNumber } = {}
local flyNext = 1
local flyColor = 1

local function buildFlyPool()
	local playerGui = player:WaitForChild("PlayerGui")
	for _ = 1, FLY_COUNT do
		local gui: BillboardGui = UI.Create("BillboardGui", {
			Name = "StepsPopup",
			Size = UDim2.fromOffset(260, 64),
			AlwaysOnTop = true,
			LightInfluence = 0,
			MaxDistance = 300,
			ResetOnSpawn = false,
			Enabled = false,
			Parent = playerGui,
		})
		local stroke: UIStroke = UI.Create("UIStroke", { Thickness = 3, Color = BLACK })
		local scale: UIScale = UI.Create("UIScale", { Scale = 1 })
		local labelObj: TextLabel = UI.Create("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Enum.Font.FredokaOne,
			TextScaled = true,
			Text = "",
			TextColor3 = FLY_COLORS[1],
			Parent = gui,
		}, { stroke, scale })
		table.insert(flyPool, {
			Gui = gui,
			Label = labelObj,
			Stroke = stroke,
			Scale = scale,
			Active = false,
			Age = 0,
			X = 0,
			Y = 0,
		})
	end
end

local function showSteps(amount: number)
	if hidden or #flyPool == 0 then
		return
	end
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end
	-- freien Platz suchen, sonst die älteste Zahl wiederverwenden
	local item: FlyNumber? = nil
	for _ = 1, FLY_COUNT do
		local candidate = flyPool[flyNext]
		flyNext = flyNext % FLY_COUNT + 1
		if not candidate.Active then
			item = candidate
			break
		end
	end
	if not item then
		local oldest = flyPool[1]
		for _, candidate in ipairs(flyPool) do
			if candidate.Age > oldest.Age then
				oldest = candidate
			end
		end
		item = oldest
	end
	local fly = item :: FlyNumber
	flyColor = flyColor % #FLY_COLORS + 1
	fly.Active = true
	fly.Age = 0
	fly.X = (math.random() - 0.5) * 5
	fly.Y = 1.2 + math.random() * 1.6
	fly.Label.Text = "+" .. UI.FormatSteps(amount, ctx.Util.FormatNumber) .. " 👟"
	fly.Label.TextColor3 = FLY_COLORS[flyColor]
	fly.Label.TextTransparency = 0
	fly.Stroke.Transparency = 0
	fly.Scale.Scale = 0.3
	fly.Gui.Adornee = rootPart
	fly.Gui.StudsOffset = Vector3.new(fly.X, fly.Y, 0)
	fly.Gui.Enabled = true
end

local function stepFlyNumbers(dt: number)
	for _, fly in ipairs(flyPool) do
		if fly.Active then
			fly.Age += dt
			local t = fly.Age / FLY_LIFE
			if t >= 1 or not fly.Gui.Adornee or not fly.Gui.Adornee.Parent then
				fly.Active = false
				fly.Gui.Enabled = false
			else
				local rise = 1 - (1 - t) * (1 - t) -- schnell hoch, dann langsamer
				fly.Gui.StudsOffset = Vector3.new(fly.X, fly.Y + rise * FLY_RISE, 0)
				local scale = 1
				if t < 0.12 then
					scale = 0.3 + (t / 0.12) * 1.05
				elseif t < 0.26 then
					scale = 1.35 - ((t - 0.12) / 0.14) * 0.35
				end
				fly.Scale.Scale = scale
				local fade = if t > 0.6 then (t - 0.6) / 0.4 else 0
				fly.Label.TextTransparency = fade
				fly.Stroke.Transparency = fade
			end
		end
	end
end

-- ---------------------------------------------------------------------
-- GELD-POPUP "+$X"
-- ---------------------------------------------------------------------
local POPUP_POP_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POPUP_RISE_INFO = TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POPUP_FADE_INFO = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.75)
local MAX_POPUPS = 3
local popupCount = 0

local function cashPopup(amount: number)
	local gui = UI.Root
	if not gui or popupCount >= MAX_POPUPS then
		return
	end
	popupCount += 1
	local scale: UIScale = UI.Create("UIScale", { Scale = 0.4 })
	local stroke: UIStroke = UI.Create("UIStroke", { Thickness = 4, Color = BLACK })
	local popup: TextLabel = UI.Create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, (math.random() - 0.5) * 120, 0.44, 0),
		Size = UDim2.fromOffset(460, 70),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextScaled = true,
		Text = "+" .. ctx.Util.FormatCash(amount),
		TextColor3 = UI.Theme.Cash,
		ZIndex = 15,
		Parent = gui,
	}, { scale, stroke })
	TweenService:Create(scale, POPUP_POP_INFO, { Scale = 1 }):Play()
	TweenService:Create(popup, POPUP_RISE_INFO, { Position = popup.Position - UDim2.fromScale(0, 0.14) }):Play()
	TweenService:Create(popup, POPUP_FADE_INFO, { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, POPUP_FADE_INFO, { Transparency = 1 }):Play()
	task.delay(1.3, function()
		popupCount -= 1
		popup:Destroy()
	end)
end

-- ---------------------------------------------------------------------
-- FUNKEN-EXPLOSION (Schlüpfen, Landung eines Lieferflugs)
-- ---------------------------------------------------------------------
local BURST_RANGE = 450 -- weiter weg sieht man es eh nicht -> nichts tun
local FLASH_INFO = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SHELL_INFO = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

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

local function makeEmitter(color: Color3, parent: Instance, big: boolean): ParticleEmitter
	return UI.Create("ParticleEmitter", {
		Color = ColorSequence.new(color, WHITE),
		LightEmission = 1,
		LightInfluence = 0,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, big and 1.4 or 0.8),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.7, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(0.5, big and 1.2 or 0.7),
		Speed = NumberRange.new(big and 16 or 8, big and 34 or 16),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -28, 0),
		Drag = 2,
		RotSpeed = NumberRange.new(-220, 220),
		Rate = 0,
		Parent = parent,
	})
end

local function burst(position: Vector3, color: Color3, amount: number, flash: boolean)
	local folder = fxFolder
	local camera = workspace.CurrentCamera
	if not folder or (camera and (camera.CFrame.Position - position).Magnitude > BURST_RANGE) then
		return
	end
	local holder = localPart({
		Name = "Burst",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
		CFrame = CFrame.new(position),
		Parent = folder,
	})
	local emitter = makeEmitter(color, holder, flash)
	emitter:Emit(math.clamp(math.floor(amount), 1, 120))
	if flash then
		local light: PointLight = UI.Create("PointLight", {
			Color = color,
			Range = 26,
			Brightness = 8,
			Shadows = false,
			Parent = holder,
		})
		TweenService:Create(light, FLASH_INFO, { Brightness = 0, Range = 6 }):Play()
		-- Leuchtende Kugel, die sich ausdehnt und verblasst (Lichtblitz)
		local shell = localPart({
			Name = "Flash",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1, 1, 1),
			Material = Enum.Material.Neon,
			Color = color,
			Transparency = 0.2,
			CFrame = CFrame.new(position),
			Parent = folder,
		})
		TweenService:Create(shell, SHELL_INFO, { Size = Vector3.new(13, 13, 13), Transparency = 1 }):Play()
		Debris:AddItem(shell, 0.5)
	end
	Debris:AddItem(holder, 2)
end

-- ---------------------------------------------------------------------
-- WACKELN (eine gemeinsame Stärke, nimmt ab)
-- ---------------------------------------------------------------------
local SHAKE_TIME = 0.35
local shakeStrength = 0
local shakeLeft = 0
local shakeHumanoid: Humanoid? = nil

local function shake(strength: number)
	if type(strength) ~= "number" or strength ~= strength or strength <= 0 then
		return
	end
	strength = math.min(strength, 3)
	local current = if shakeLeft > 0 then shakeStrength * (shakeLeft / SHAKE_TIME) else 0
	if strength >= current then
		shakeStrength = strength
		shakeLeft = SHAKE_TIME
	end
end

local function stepShake(dt: number)
	if shakeLeft <= 0 then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= shakeHumanoid and shakeHumanoid and shakeHumanoid.Parent then
		shakeHumanoid.CameraOffset = Vector3.zero
	end
	shakeHumanoid = humanoid
	shakeLeft -= dt
	if not humanoid then
		return
	end
	if shakeLeft <= 0 then
		humanoid.CameraOffset = Vector3.zero
		return
	end
	local power = shakeStrength * (shakeLeft / SHAKE_TIME)
	humanoid.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * power
end

-- ---------------------------------------------------------------------
-- LIEFERFLUG: Geister-Meteor fliegt im Bogen vom Laufband in den Slot
-- ---------------------------------------------------------------------
type Flight = {
	Part: BasePart,
	From: Vector3,
	To: Vector3,
	Height: number,
	Age: number,
	Color: Color3,
}

local DELIVER_TIME = 0.9
local MAX_FLIGHTS = 12
local flights: { Flight } = {}

local function addTrail(part: BasePart, size: number, color: Color3, tail: Color3)
	local a0: Attachment = UI.Create("Attachment", { Position = Vector3.new(0, size * 0.35, 0), Parent = part })
	local a1: Attachment = UI.Create("Attachment", { Position = Vector3.new(0, -size * 0.35, 0), Parent = part })
	UI.Create("Trail", {
		Attachment0 = a0,
		Attachment1 = a1,
		Color = ColorSequence.new(color, tail),
		Transparency = NumberSequence.new(0.15, 1),
		Lifetime = 0.35,
		LightEmission = 1,
		FaceCamera = true,
		Parent = part,
	})
end

local function deliver(data: any)
	local folder = fxFolder
	if not folder or type(data) ~= "table" or #flights >= MAX_FLIGHTS then
		return
	end
	local from, to = data.From, data.To
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then
		return
	end
	local camera = workspace.CurrentCamera
	if camera then
		local camPos = camera.CFrame.Position
		if (camPos - from).Magnitude > BURST_RANGE and (camPos - to).Magnitude > BURST_RANGE then
			return
		end
	end
	local Config = ctx.Config
	local def = Config.MeteorsById[data.MeteorId]
	local rarity = def and Config.RaritiesByName[def.Rarity]
	local mut = Config.MutationsByName[data.Mut]
	local size = math.clamp(rarity and rarity.Size or 2.5, 1, 10)
	local color: Color3 = def and def.Color or WHITE
	if mut and mut.Color then
		color = mut.Color
	end
	local tail: Color3 = rarity and rarity.Color or WHITE
	local part = localPart({
		Name = "DeliverGhost",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(size, size, size),
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = 0.3,
		CFrame = CFrame.new(from),
		Parent = folder,
	})
	addTrail(part, size, color, tail)
	table.insert(flights, {
		Part = part,
		From = from,
		To = to,
		Height = math.clamp((to - from).Magnitude * 0.35, 8, 45),
		Age = 0,
		Color = tail,
	})
end

local function stepFlights(dt: number)
	for i = #flights, 1, -1 do
		local flight = flights[i]
		flight.Age += dt
		local t = math.min(1, flight.Age / DELIVER_TIME)
		local e = t * t * (3 - 2 * t) -- weich anfahren und abbremsen
		local pos = flight.From:Lerp(flight.To, e) + Vector3.new(0, flight.Height * 4 * e * (1 - e), 0)
		flight.Part.CFrame = CFrame.Angles(flight.Age * 6, flight.Age * 4, 0) + pos
		if t >= 1 then
			flight.Part:Destroy()
			flights[i] = flights[#flights]
			flights[#flights] = nil
			burst(flight.To, flight.Color, 14, false)
		end
	end
end

-- ---------------------------------------------------------------------
-- SCHLÜPFEN
-- ---------------------------------------------------------------------
local function hatch(data: any)
	if type(data) ~= "table" or typeof(data.Position) ~= "Vector3" then
		return
	end
	local Config = ctx.Config
	local rarity = Config.RaritiesByName[data.Rarity]
	local index = Config.RarityIndex[data.Rarity] or 1
	local color: Color3 = rarity and rarity.Color or WHITE
	burst(data.Position, color, 24 + index * 7, true)
	-- Ganz nah dran? Kurz wackeln
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if rootPart and (rootPart.Position - data.Position).Magnitude < 40 then
		shake(0.25 + index * 0.04)
	end
end

-- ---------------------------------------------------------------------
-- KONFETTI + ALARM
-- ---------------------------------------------------------------------
local MAX_CONFETTI = 120
local confettiAlive = 0

local function confetti(amount: number)
	local gui = UI.Root
	if not gui then
		return
	end
	local colors = { UI.Theme.Yellow, UI.Theme.Green, UI.Theme.Blue, UI.Theme.Purple, UI.Theme.Red, UI.Theme.Pink }
	local count = math.floor(28 * math.clamp(tonumber(amount) or 1, 0.3, 3))
	count = math.min(count, MAX_CONFETTI - confettiAlive)
	for _ = 1, count do
		confettiAlive += 1
		local startX = math.random()
		local piece: Frame = UI.Create("Frame", {
			Size = UDim2.fromOffset(math.random(7, 13), math.random(7, 13)),
			Position = UDim2.new(startX, 0, 0, -20),
			BackgroundColor3 = colors[math.random(1, #colors)],
			BorderSizePixel = 0,
			Rotation = math.random(0, 360),
			ZIndex = 25,
			Parent = gui,
		})
		local tween = TweenService:Create(
			piece,
			TweenInfo.new(math.random(16, 30) / 10, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{
				Position = UDim2.new(startX + (math.random() - 0.5) * 0.25, 0, 1, 20),
				Rotation = piece.Rotation + math.random(-400, 400),
			}
		)
		tween.Completed:Connect(function()
			confettiAlive -= 1
			piece:Destroy()
		end)
		tween:Play()
	end
end

local alarmFrame: Frame? = nil
local ALARM_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local alarmRunning = false

local function alarm()
	local frame = alarmFrame
	if not frame or alarmRunning then
		return
	end
	alarmRunning = true
	for _ = 1, 3 do
		frame.BackgroundTransparency = 0.55
		TweenService:Create(frame, ALARM_INFO, { BackgroundTransparency = 1 }):Play()
		task.wait(0.35)
	end
	alarmRunning = false
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICH
-- ---------------------------------------------------------------------
function Effects.Play(name: any, strength: any, data: any)
	if type(name) ~= "string" then
		return
	end
	local amount = tonumber(strength) or 0
	if name == "Steps" then
		if amount > 0 then
			showSteps(amount)
			if ctx.Hooks.OnSteps then
				ctx.Hooks.OnSteps(amount)
			end
		end
	elseif name == "Collect" then
		if amount > 0 then
			cashPopup(amount)
			if ctx.Hooks.OnCash then
				ctx.Hooks.OnCash(amount)
			end
		end
	elseif name == "Deliver" then
		deliver(data)
	elseif name == "Hatch" then
		hatch(data)
	elseif name == "Shake" then
		shake(amount)
	elseif name == "Confetti" then
		confetti(amount)
	elseif name == "Alarm" then
		task.spawn(alarm)
	end
end

-- Foto-Modus: fliegende Zahlen ausblenden
function Effects.SetHidden(value: boolean)
	hidden = value
	if value then
		for _, fly in ipairs(flyPool) do
			fly.Active = false
			fly.Gui.Enabled = false
		end
	end
end

function Effects.Init(context: any)
	ctx = context
	fxFolder = UI.Create("Folder", { Name = "MeteorHeistClientFX", Parent = workspace })
	alarmFrame = UI.Create("Frame", {
		Name = "Alarm",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 0,
		Parent = UI.Root,
	})
	buildFlyPool()
	RunService.RenderStepped:Connect(function(dt: number)
		stepFlyNumbers(dt)
		if #flights > 0 then
			stepFlights(dt)
		end
		stepShake(dt)
	end)
	-- Neuer Charakter: Wackeln zurücksetzen
	player.CharacterAdded:Connect(function()
		shakeLeft = 0
		shakeHumanoid = nil
	end)
end

return Effects
