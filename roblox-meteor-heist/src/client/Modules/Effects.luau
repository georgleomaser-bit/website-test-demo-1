-- =====================================================================
--  EFFEKTE vom Server (Remote "Effect": name, strength, data)
--   "Steps"    -> fliegende "+X 👟"-Zahl über deinem Charakter (wie im Speed-Simulator)
--   "Collect"  -> großes "+$X" in der Bildschirmmitte
--   "Deliver"  -> Geister-Meteor fliegt im Bogen vom Laufband in die Base
--                 (kommt er fast senkrecht von oben, z.B. Egg Rush: fällt er beschleunigt herunter)
--   "Hatch"    -> Funken-Explosion + Lichtblitz, wenn ein Alien schlüpft
--   "HatchReveal" -> große Karte in der Bildschirmmitte (Ultra / ab Epic) + Konfetti,
--                    sonst bzw. beim Tragen kleine Karte oben rechts
--   "Shake", "Confetti", "Alarm" wie bisher
--  Dazu: 🧊 Eingefroren-Anzeige, solange der eigene HumanoidRootPart verankert ist (Falle/Admin).
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
-- Viele Explosionen auf einmal (z.B. mehrere Eier schlüpfen gleichzeitig): höchstens MAX_FLASHES
-- Lichtblitze pro FLASH_WINDOW Sekunden, darüber nur noch halb so viele Funken
local FLASH_WINDOW = 0.25
local MAX_FLASHES = 3
local flashWindowStart = 0
local flashCount = 0

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
	if flash then
		local t = os.clock()
		if t - flashWindowStart > FLASH_WINDOW then
			flashWindowStart = t
			flashCount = 0
		end
		flashCount += 1
		if flashCount > MAX_FLASHES then
			flash = false
			amount *= 0.5
		end
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
	Fall: boolean, -- fast senkrecht von oben: beschleunigt fallen statt Bogen
}

local DELIVER_TIME = 0.9 -- gleich lang wie die Fall-Zeit auf dem Server
local MAX_FLIGHTS = 32 -- Egg Rush: viele Eier fallen fast gleichzeitig
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
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude
	local fall = from.Y - to.Y > flat * 2
	table.insert(flights, {
		Part = part,
		From = from,
		To = to,
		Height = if fall then 0 else math.clamp((to - from).Magnitude * 0.35, 8, 45),
		Age = 0,
		Color = tail,
		Fall = fall,
	})
end

local function stepFlights(dt: number)
	for i = #flights, 1, -1 do
		local flight = flights[i]
		flight.Age += dt
		local t = math.min(1, flight.Age / DELIVER_TIME)
		-- Bogen: weich anfahren und abbremsen. Fall: immer schneller (wie Schwerkraft)
		local e = if flight.Fall then t * t else t * t * (3 - 2 * t)
		local pos = flight.From:Lerp(flight.To, e) + Vector3.new(0, flight.Height * 4 * e * (1 - e), 0)
		flight.Part.CFrame = CFrame.Angles(flight.Age * 6, flight.Age * 4, 0) + pos
		if t >= 1 then
			flight.Part:Destroy()
			flights[i] = flights[#flights]
			flights[#flights] = nil
			burst(flight.To, flight.Color, if flight.Fall then 22 else 14, false)
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
-- HATCH REVEAL: große Karte in der Mitte (Name in Seltenheits-Farbe, Stufe, Mutation)
-- Eine Karte wird einmal gebaut und wiederverwendet; mehrere hintereinander warten kurz.
-- Groß + Konfetti nur für Besonderes (Ultra oder ab Epic). "Selten"-Aliens aus kleinen Eiern und
-- alles, während du Beute trägst, kommt als kleine Karte oben rechts (verdeckt nicht die Mitte).
-- ---------------------------------------------------------------------
local REVEAL_POP_INFO = TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local REVEAL_OUT_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local REVEAL_SPIN_INFO = TweenInfo.new(6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
local REVEAL_TIME = 3.2
local MINI_REVEAL_TIME = 1.8
local MINI_REVEAL_SCALE = 0.45
local MAX_REVEAL_QUEUE = 4
-- Ersatz-Symbole (Config.Mutations -> Icon hat Vorrang; gleiche Symbole wie an Aliens und Meteoren)
local MUTATION_ICONS: { [string]: string } = {
	Gold = "🪙",
	Diamond = "💎",
	Cosmic = "🌌",
	Frost = "❄️",
	Lava = "🔥",
	Rainbow = "🌈",
}

type RevealUI = {
	Holder: Frame,
	Scale: UIScale,
	Rays: Frame,
	RayTween: Tween?,
	Card: Frame,
	CardGradient: UIGradient,
	Title: TextLabel,
	Face: Frame,
	FaceStroke: UIStroke,
	Eyes: { Frame },
	Name: TextLabel,
	Info: TextLabel,
	Mutation: TextLabel,
	MutationGradient: UIGradient,
	Income: TextLabel,
}

local reveal: RevealUI? = nil
local revealQueue: { any } = {}
local revealBusy = false
local revealSkip = false

local function rainbowSequence(): ColorSequence
	local keys = {}
	for i = 0, 6 do
		table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 0.85, 1)))
	end
	return ColorSequence.new(keys)
end

local function buildReveal(): RevealUI?
	local gui = UI.Root
	if not gui then
		return nil
	end
	local holder: Frame = UI.Create("Frame", {
		Name = "HatchReveal",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(440, 290),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 30,
		Parent = gui,
	})
	local scale: UIScale = UI.Create("UIScale", { Scale = 0, Parent = holder })
	-- Strahlen hinter der Karte (drehen sich langsam)
	local rays: Frame = UI.Create("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(560, 560),
		BackgroundTransparency = 1,
		ZIndex = 30,
		Parent = holder,
	})
	for i = 0, 5 do
		UI.Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 46, 1, 0),
			Rotation = i * 30,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.72,
			BorderSizePixel = 0,
			ZIndex = 30,
			Parent = rays,
		})
	end
	local cardGradient: UIGradient = UI.Create("UIGradient", { Rotation = 90 })
	local card: Frame = UI.Create("Frame", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		ZIndex = 31,
		Parent = holder,
	}, { UI.Corner(22), UI.Stroke(BLACK, 4), cardGradient })
	local closeButton: TextButton = UI.Create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 40,
		Parent = card,
	})
	closeButton.Activated:Connect(function()
		revealSkip = true
	end)
	local title = UI.Label({
		Position = UDim2.fromOffset(14, 10),
		Size = UDim2.new(1, -28, 0, 40),
		Text = "🐣 GESCHLÜPFT!",
		TextColor3 = UI.Theme.Yellow,
		MaxText = 34,
		Outline = 3,
		ZIndex = 32,
		Parent = card,
	})
	-- Gesicht des Aliens (Kreis in seiner Farbe + Augen)
	local faceStroke = UI.Stroke(BLACK, 4)
	local face: Frame = UI.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.fromOffset(92, 92),
		BackgroundColor3 = WHITE,
		ZIndex = 32,
		Parent = card,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }), faceStroke })
	local eyes: { Frame } = {}
	for _ = 1, 4 do
		local eye: Frame = UI.Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(22, 22),
			BackgroundColor3 = WHITE,
			Visible = false,
			ZIndex = 33,
			Parent = face,
		}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }), UI.Stroke(BLACK, 2) })
		UI.Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.58, 0.58),
			Size = UDim2.fromScale(0.45, 0.45),
			BackgroundColor3 = BLACK,
			ZIndex = 34,
			Parent = eye,
		}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		table.insert(eyes, eye)
	end
	local nameLabel = UI.Label({
		Position = UDim2.fromOffset(14, 152),
		Size = UDim2.new(1, -28, 0, 44),
		Text = "",
		MaxText = 38,
		Outline = 3,
		ZIndex = 32,
		Parent = card,
	})
	local info = UI.Label({
		Position = UDim2.fromOffset(14, 196),
		Size = UDim2.new(1, -28, 0, 26),
		Text = "",
		MaxText = 22,
		Outline = 2,
		ZIndex = 32,
		Parent = card,
	})
	local mutationGradient: UIGradient = UI.Create("UIGradient", { Color = rainbowSequence(), Enabled = false })
	local mutation = UI.Label({
		Position = UDim2.fromOffset(14, 222),
		Size = UDim2.new(0.5, -18, 0, 26),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxText = 20,
		Outline = 2,
		ZIndex = 32,
		Parent = card,
	})
	mutationGradient.Parent = mutation
	local income = UI.Label({
		Position = UDim2.new(0.5, 4, 0, 222),
		Size = UDim2.new(0.5, -18, 0, 26),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UI.Theme.Cash,
		MaxText = 20,
		Outline = 2,
		ZIndex = 32,
		Parent = card,
	})
	UI.Label({
		Position = UDim2.new(0, 14, 1, -30),
		Size = UDim2.new(1, -28, 0, 20),
		Text = "Klick zum Schließen",
		Font = Enum.Font.GothamBold,
		TextColor3 = UI.Theme.SubText,
		MaxText = 13,
		ZIndex = 32,
		Parent = card,
	})
	return {
		Holder = holder,
		Scale = scale,
		Rays = rays,
		RayTween = nil,
		Card = card,
		CardGradient = cardGradient,
		Title = title,
		Face = face,
		FaceStroke = faceStroke,
		Eyes = eyes,
		Name = nameLabel,
		Info = info,
		Mutation = mutation,
		MutationGradient = mutationGradient,
		Income = income,
	}
end

-- Augen gleichmäßig nebeneinander (1-4)
local function placeEyes(ui: RevealUI, count: number)
	count = math.clamp(math.floor(count), 1, 4)
	for i, eye in ipairs(ui.Eyes) do
		eye.Visible = i <= count
		if i <= count then
			local x = if count == 1 then 0.5 else 0.22 + (i - 1) * (0.56 / (count - 1))
			eye.Position = UDim2.fromScale(x, 0.42)
			local size = if count == 1 then 34 elseif count == 2 then 24 else 18
			eye.Size = UDim2.fromOffset(size, size)
		end
	end
end

local function fillReveal(ui: RevealUI, data: any): boolean
	local Config = ctx.Config
	local def = ctx.Aliens.ById[data.AlienId]
	if not def then
		return false
	end
	local rarity = Config.RaritiesByName[def.Rarity]
	local rarityColor: Color3 = if rarity then rarity.Color else WHITE
	local tierColors = ctx.Aliens.TierColors or {}
	local tierColor: Color3 = tierColors[def.Tier] or WHITE
	local look = def.Look or {}
	local mut = Config.MutationsByName[data.Mut]
	local ultra = def.Tier == "Ultra"
	ui.Title.Text = if ultra
		then "🌟 ULTRA GESCHLÜPFT! 🌟"
		elseif def.Tier == "Selten" then "✨ SELTEN GESCHLÜPFT!"
		else "🐣 GESCHLÜPFT!"
	ui.CardGradient.Color = ColorSequence.new(rarityColor:Lerp(BLACK, 0.35), UI.Theme.PanelDark)
	ui.Face.BackgroundColor3 = if typeof(look.Color) == "Color3" then look.Color else rarityColor
	ui.FaceStroke.Color = if typeof(look.Accent) == "Color3" then look.Accent else BLACK
	placeEyes(ui, tonumber(look.Eyes) or 2)
	ui.Name.Text = tostring(def.Name)
	ui.Name.TextColor3 = rarityColor
	ui.Info.Text = tostring(def.Tier) .. "  •  " .. tostring(def.Rarity)
	ui.Info.TextColor3 = tierColor
	local mutName = if mut and mut.Name ~= "Normal" then mut.Name else nil
	if mutName and mut then
		local icon = if type(mut.Icon) == "string" and mut.Icon ~= "" then mut.Icon else MUTATION_ICONS[mutName]
		ui.Mutation.Text = (icon or "✨") .. " " .. mutName .. " x" .. UI.FormatMult(mut.Mult)
		ui.Mutation.TextColor3 = if mut.Rainbow == true then WHITE else (mut.Color or WHITE)
		ui.MutationGradient.Enabled = mut.Rainbow == true
	else
		ui.Mutation.Text = "Normal"
		ui.Mutation.TextColor3 = UI.Theme.SubText
		ui.MutationGradient.Enabled = false
	end
	-- Einkommen auf Level 1 (gleiche Rechnung wie Config.MeteorIncome)
	local meteor = Config.MeteorsById[def.Meteor]
	local perSecond = (if meteor then tonumber(meteor.Income) or 0 else 0)
		* (tonumber(def.IncomeMult) or 1)
		* (if mut then tonumber(mut.Mult) or 1 else 1)
	ui.Income.Text = "💵 +" .. ctx.Util.FormatCash(perSecond) .. "/s"
	for _, ray in ipairs(ui.Rays:GetChildren()) do
		if ray:IsA("Frame") then
			ray.BackgroundColor3 = if ultra then UI.Theme.Yellow else rarityColor:Lerp(WHITE, 0.4)
		end
	end
	return true
end

-- Große Karte (Mitte, Konfetti) oder kleine (oben rechts)?
local function revealIsBig(data: any): boolean
	local state = ctx.State
	if state and state.Carrying == true then
		return false -- beim Wegrennen mit Beute nicht die Bildschirmmitte zudecken
	end
	local def = ctx.Aliens.ById[data.AlienId]
	if not def then
		return false
	end
	if def.Tier == "Ultra" then
		return true
	end
	local Config = ctx.Config
	return (Config.RarityIndex[def.Rarity] or 0) >= (Config.RarityIndex.Epic or 4)
end

local function showNextReveal()
	if revealBusy then
		return
	end
	revealBusy = true
	while #revealQueue > 0 do
		local data = table.remove(revealQueue, 1)
		local ui = reveal or buildReveal()
		reveal = ui
		if ui and not hidden and fillReveal(ui, data) then
			local big = revealIsBig(data)
			revealSkip = false
			ui.Holder.AnchorPoint = if big then Vector2.new(0.5, 0.5) else Vector2.new(1, 0)
			ui.Holder.Position = if big then UDim2.fromScale(0.5, 0.45) else UDim2.new(1, -14, 0, 56)
			ui.Rays.Visible = big
			ui.Holder.Visible = true
			ui.Scale.Scale = 0.2
			ui.Rays.Rotation = 0
			local rayTween = TweenService:Create(ui.Rays, REVEAL_SPIN_INFO, { Rotation = 360 })
			ui.RayTween = rayTween
			rayTween:Play()
			TweenService:Create(ui.Scale, REVEAL_POP_INFO, { Scale = if big then 1 else MINI_REVEAL_SCALE }):Play()
			if big then
				confetti(1.6)
				shake(0.35)
			end
			local showTime = if big then REVEAL_TIME else MINI_REVEAL_TIME
			local shown = 0
			while shown < showTime and not revealSkip and not hidden do
				shown += task.wait(0.1)
			end
			local out = TweenService:Create(ui.Scale, REVEAL_OUT_INFO, { Scale = 0 })
			out:Play()
			out.Completed:Wait()
			rayTween:Cancel()
			ui.RayTween = nil
			ui.Holder.Visible = false
		end
	end
	revealBusy = false
end

local function hatchReveal(data: any)
	if type(data) ~= "table" or type(data.AlienId) ~= "string" then
		return
	end
	if #revealQueue >= MAX_REVEAL_QUEUE then
		table.remove(revealQueue, 1) -- die älteste wartende Karte fällt weg
	end
	table.insert(revealQueue, data)
	task.spawn(showNextReveal)
end

-- ---------------------------------------------------------------------
-- 🧊 EINGEFROREN (Falle / Admin-Freeze): HumanoidRootPart ist verankert
-- ---------------------------------------------------------------------
local FROZEN_FADE_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local frozenFrame: Frame? = nil
local frozenLabel: TextLabel? = nil
local frozenConnection: RBXScriptConnection? = nil
local frozenShown = false

local function setFrozen(on: boolean)
	local frame = frozenFrame
	local label = frozenLabel
	if not frame or not label or on == frozenShown then
		return
	end
	frozenShown = on
	if on then
		frame.Visible = true
		frame.BackgroundTransparency = 1
		label.TextTransparency = 1
		TweenService:Create(frame, FROZEN_FADE_INFO, { BackgroundTransparency = 0.72 }):Play()
		TweenService:Create(label, FROZEN_FADE_INFO, { TextTransparency = 0 }):Play()
	else
		local fade = TweenService:Create(frame, FROZEN_FADE_INFO, { BackgroundTransparency = 1 })
		TweenService:Create(label, FROZEN_FADE_INFO, { TextTransparency = 1 }):Play()
		fade.Completed:Connect(function()
			if not frozenShown then
				frame.Visible = false
			end
		end)
		fade:Play()
	end
end

local function watchFrozen(character: Model)
	if frozenConnection then
		frozenConnection:Disconnect()
		frozenConnection = nil
	end
	setFrozen(false)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") or player.Character ~= character then
		return
	end
	frozenConnection = root:GetPropertyChangedSignal("Anchored"):Connect(function()
		setFrozen(root.Anchored)
	end)
	setFrozen(root.Anchored)
end

local function buildFrozen()
	local gui = UI.Root
	if not gui then
		return
	end
	local frame: Frame = UI.Create("Frame", {
		Name = "Frozen",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(150, 220, 255),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 1,
		Parent = gui,
	})
	-- Eis-Rand: innen durchsichtig, außen hellblau
	UI.Create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.25, 0.85),
			NumberSequenceKeypoint.new(0.75, 0.85),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Parent = frame,
	})
	frozenLabel = UI.Label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(520, 60),
		Text = "🧊 EINGEFROREN! 🧊",
		TextColor3 = Color3.fromRGB(200, 240, 255),
		TextTransparency = 1,
		MaxText = 46,
		Outline = 3,
		ZIndex = 2,
		Parent = frame,
	})
	frozenFrame = frame
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
	elseif name == "HatchReveal" then
		hatchReveal(data)
	elseif name == "Shake" then
		shake(amount)
	elseif name == "Confetti" then
		confetti(amount)
	elseif name == "Alarm" then
		task.spawn(alarm)
	end
end

-- Foto-Modus: fliegende Zahlen + große Karten ausblenden
function Effects.SetHidden(value: boolean)
	hidden = value
	if value then
		for _, fly in ipairs(flyPool) do
			fly.Active = false
			fly.Gui.Enabled = false
		end
		table.clear(revealQueue)
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
	buildFrozen()
	RunService.RenderStepped:Connect(function(dt: number)
		stepFlyNumbers(dt)
		if #flights > 0 then
			stepFlights(dt)
		end
		stepShake(dt)
	end)
	-- Neuer Charakter: Wackeln zurücksetzen, Eingefroren-Anzeige neu verbinden
	player.CharacterAdded:Connect(function(character)
		shakeLeft = 0
		shakeHumanoid = nil
		watchFrozen(character)
	end)
	if player.Character then
		task.spawn(watchFrozen, player.Character)
	end
end

return Effects
