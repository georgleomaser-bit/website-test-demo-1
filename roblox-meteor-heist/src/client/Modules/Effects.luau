-- =====================================================================
--  EFFEKTE vom Server (Remote "Effect": name, strength, data)
--   "Steps"    -> fliegende "+X 👟"-Zahl über deinem Charakter (federt, Farbverlauf, kippelt)
--   "Collect"  -> großes "+$X" in der Bildschirmmitte + Münzen fliegen von dir zum Geld-Zähler
--   "Deliver"  -> Geister-Meteor fliegt im Bogen vom Laufband in die Base, mit Funkenschweif
--                 (kommt er fast senkrecht von oben, z.B. Egg Rush: fällt er beschleunigt herunter),
--                 beim Aufprall: Staub-Puff + Druckwelle
--   "Hatch"    -> Funken-Explosion + Lichtblitz + Schalen-Splitter + Druckwelle, wenn ein Alien schlüpft
--                 (das Alien selbst ploppt in WorldFX mit Overshoot herein)
--   "HatchReveal" -> große Karte in der Bildschirmmitte (Ultra / ab Epic) mit Strahlenkranz + Konfetti,
--                    sonst bzw. beim Tragen kleine Karte oben rechts
--   "Shake" (weich und dezent), "Confetti" (fliegt aus zwei Kanonen hoch, fällt mit Schwerkraft,
--   dreht und flattert), "Alarm" wie bisher
--  Dazu: Rebirth-Bildschirmblitz (Effects.RebirthFlash, vom HUD aufgerufen).
--  Dazu: 🧊 Eingefroren-Anzeige, solange der eigene HumanoidRootPart verankert ist (Falle/Admin).
--  Alles läuft lokal (nichts davon wird an andere Spieler geschickt).
-- =====================================================================

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent:WaitForChild("UI"))
local WorldFX = require(script.Parent:WaitForChild("WorldFX"))

local Effects = {}

local player = Players.LocalPlayer
local ctx: any = nil
local fxFolder: Folder? = nil
local overlay: ScreenGui? = nil -- eigene Ebene für Münzen, Konfetti, Blitze (ohne UI-Skalierung)
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
	Gradient: UIGradient,
	Active: boolean,
	Age: number,
	X: number,
	Y: number,
	Tilt: number,
}

local FLY_COUNT = 12
local FLY_LIFE = 1.15
local FLY_RISE = 3.6
-- Farbverläufe (oben hell -> unten kräftig), abwechselnd Gold und Himmelblau
local FLY_COLORS = {
	ColorSequence.new(Color3.fromRGB(255, 250, 170), Color3.fromRGB(255, 150, 20)),
	ColorSequence.new(Color3.fromRGB(190, 245, 255), Color3.fromRGB(40, 120, 255)),
}
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
		local gradient: UIGradient = UI.Create("UIGradient", { Rotation = 90, Color = FLY_COLORS[1] })
		local labelObj: TextLabel = UI.Create("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Enum.Font.FredokaOne,
			TextScaled = true,
			Text = "",
			TextColor3 = WHITE, -- Farbe kommt aus dem Verlauf
			Parent = gui,
		}, { stroke, scale, gradient })
		table.insert(flyPool, {
			Gui = gui,
			Label = labelObj,
			Stroke = stroke,
			Scale = scale,
			Gradient = gradient,
			Active = false,
			Age = 0,
			X = 0,
			Y = 0,
			Tilt = 0,
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
	fly.Tilt = (math.random() - 0.5) * 30
	fly.Label.Text = "+" .. UI.FormatSteps(amount, ctx.Util.FormatNumber) .. " 👟"
	fly.Gradient.Color = FLY_COLORS[flyColor]
	fly.Label.Rotation = fly.Tilt
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
				-- federnder Bounce: aus 0.3 schnell über die Endgröße hinaus, gedämpft zurück
				local age = fly.Age
				local decay = math.exp(-age * 9)
				fly.Scale.Scale = 1 - 0.7 * decay * math.cos(age * 26)
				-- kippelt am Anfang hin und her und richtet sich dann auf
				fly.Label.Rotation = fly.Tilt * math.exp(-age * 5) * math.cos(age * 18)
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
-- MÜNZEN fliegen von dir zum Geld-Zähler (fester Vorrat, nur Tweens)
-- ---------------------------------------------------------------------
type Coin = { Label: TextLabel, Busy: boolean }

local COIN_COUNT = 16
local COIN_OUT_INFO = TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local coinPool: { Coin } = {}

local function buildCoins()
	local gui = overlay
	if not gui then
		return
	end
	for _ = 1, COIN_COUNT do
		local coinLabel: TextLabel = UI.Create("TextLabel", {
			Name = "Coin",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(34, 34),
			BackgroundTransparency = 1,
			Text = "🪙",
			TextScaled = true,
			Font = Enum.Font.FredokaOne,
			Visible = false,
			ZIndex = 30,
			Parent = gui,
		})
		table.insert(coinPool, { Label = coinLabel, Busy = false })
	end
end

local function flyCoins(amount: number)
	local gui = overlay
	local camera = workspace.CurrentCamera
	local hud = ctx.Hud
	if not gui or hidden or not camera or #coinPool == 0 or not hud or not hud.CashAnchor then
		return
	end
	local target: Vector2? = hud.CashAnchor()
	if not target then
		return
	end
	local goal = UDim2.fromOffset(target.X, target.Y)
	local size = gui.AbsoluteSize
	local start = Vector2.new(size.X / 2, size.Y * 0.55)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local point, onScreen = camera:WorldToScreenPoint(root.Position)
		if onScreen then
			start = Vector2.new(point.X, point.Y)
		end
	end
	local count = math.clamp(math.floor(3 + math.log10(math.max(amount, 1)) * 1.5), 4, 12)
	local launched = 0
	for _, coin in ipairs(coinPool) do
		if launched >= count then
			break
		end
		if not coin.Busy then
			launched += 1
			coin.Busy = true
			local coinLabel = coin.Label
			-- erst in alle Richtungen aufspritzen, dann im Bogen zum Zähler saugen
			local angle = math.random() * math.pi * 2
			local spread = 40 + math.random() * 70
			local midX = start.X + math.cos(angle) * spread
			local midY = start.Y + math.sin(angle) * spread * 0.7 - 30
			coinLabel.Position = UDim2.fromOffset(start.X, start.Y)
			coinLabel.Size = UDim2.fromOffset(14, 14)
			coinLabel.Rotation = math.random(-40, 40)
			coinLabel.Visible = true
			local out = TweenService:Create(coinLabel, COIN_OUT_INFO, {
				Position = UDim2.fromOffset(midX, midY),
				Size = UDim2.fromOffset(34, 34),
				Rotation = coinLabel.Rotation + math.random(-120, 120),
			})
			local delay = launched * 0.04
			out.Completed:Once(function()
				local flyInfo = TweenInfo.new(
					0.4 + math.random() * 0.15,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.In,
					0,
					false,
					delay
				)
				local fly = TweenService:Create(coinLabel, flyInfo, {
					Position = goal,
					Size = UDim2.fromOffset(20, 20),
					Rotation = 0,
				})
				fly.Completed:Once(function()
					coinLabel.Visible = false
					coin.Busy = false
					if not hidden then
						hud.PulseCash(0.06) -- jede Münze lässt den Zähler kurz zucken
					end
				end)
				fly:Play()
			end)
			out:Play()
		end
	end
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

-- Druckwelle: flacher leuchtender Ring am Boden, wächst und verblasst
local function ring(position: Vector3, color: Color3, size: number, time: number)
	local folder = fxFolder
	local camera = workspace.CurrentCamera
	if not folder or (camera and (camera.CFrame.Position - position).Magnitude > BURST_RANGE) then
		return
	end
	local cf = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2) -- Zylinder-Achse senkrecht
	local wave = localPart({
		Name = "Shockwave",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, 1, 1),
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = 0.25,
		CFrame = cf,
		Parent = folder,
	})
	local info = TweenInfo.new(time, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	TweenService:Create(wave, info, { Size = Vector3.new(0.05, size, size), Transparency = 1 }):Play()
	Debris:AddItem(wave, time + 0.05)
end

-- Staub-Puff (weiche graue Wolke) beim Aufprall
local function puff(position: Vector3, color: Color3, amount: number)
	local folder = fxFolder
	local camera = workspace.CurrentCamera
	if not folder or (camera and (camera.CFrame.Position - position).Magnitude > BURST_RANGE) then
		return
	end
	local holder = localPart({
		Name = "Puff",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
		CFrame = CFrame.new(position),
		Parent = folder,
	})
	local smoke: ParticleEmitter = UI.Create("ParticleEmitter", {
		Color = ColorSequence.new(color:Lerp(WHITE, 0.6), Color3.fromRGB(150, 145, 140)),
		LightEmission = 0.2,
		LightInfluence = 0.6,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8),
			NumberSequenceKeypoint.new(0.4, 2.2),
			NumberSequenceKeypoint.new(1, 3),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(6, 12),
		SpreadAngle = Vector2.new(80, 10),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, 3, 0),
		Drag = 5,
		RotSpeed = NumberRange.new(-60, 60),
		Rotation = NumberRange.new(0, 360),
		Rate = 0,
		Parent = holder,
	})
	smoke:Emit(math.clamp(math.floor(amount), 1, 30))
	Debris:AddItem(holder, 1.2)
end

-- Schalen-Splitter: kleine Stücke fliegen mit Schwerkraft und Drehung weg (fester Vorrat,
-- eine Schleife, eine BulkMoveTo-Liste – keine neuen Teile pro Schlüpfen)
type Shard = {
	Part: BasePart,
	Active: boolean,
	Pos: Vector3,
	Vel: Vector3,
	Spin: Vector3,
	Age: number,
	Life: number,
}

local SHARD_COUNT = 40
local SHARD_GRAVITY = Vector3.new(0, -60, 0)
local shards: { Shard } = {}
local shardNext = 1
local shardsAlive = 0
local shardParts: { BasePart } = {}
local shardCFrames: { CFrame } = {}
local HIDDEN_CF = CFrame.new(0, -5000, 0)

local function buildShards()
	local folder = fxFolder
	if not folder then
		return
	end
	for _ = 1, SHARD_COUNT do
		local part: BasePart = localPart({
			Name = "Shard",
			Size = Vector3.new(0.5, 0.15, 0.4),
			Material = Enum.Material.Slate,
			CFrame = HIDDEN_CF,
			Parent = folder,
		})
		table.insert(shards, {
			Part = part,
			Active = false,
			Pos = Vector3.zero,
			Vel = Vector3.zero,
			Spin = Vector3.zero,
			Age = 0,
			Life = 1,
		})
	end
end

local function spawnShards(position: Vector3, color: Color3, amount: number, scale: number)
	if #shards == 0 then
		return
	end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - position).Magnitude > BURST_RANGE * 0.5 then
		return -- weit weg sieht man die kleinen Splitter nicht
	end
	for _ = 1, amount do
		local shard = shards[shardNext]
		shardNext = shardNext % SHARD_COUNT + 1
		if not shard.Active then
			shardsAlive += 1
		end
		shard.Active = true
		shard.Age = 0
		shard.Life = 0.8 + math.random() * 0.6
		local angle = math.random() * math.pi * 2
		local out = 8 + math.random() * 14
		shard.Pos = position + Vector3.new(0, 0.5 * scale, 0)
		shard.Vel = Vector3.new(math.cos(angle) * out, 14 + math.random() * 16, math.sin(angle) * out)
		shard.Spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 22
		local part = shard.Part
		local size = (0.3 + math.random() * 0.4) * scale
		part.Size = Vector3.new(size, size * 0.3, size * 0.8)
		part.Color = color:Lerp(Color3.fromRGB(120, 110, 100), math.random() * 0.5)
		part.Transparency = 0
	end
end

local function stepShards(dt: number)
	table.clear(shardParts)
	table.clear(shardCFrames)
	local count = 0
	for _, shard in ipairs(shards) do
		if shard.Active then
			shard.Age += dt
			count += 1
			shardParts[count] = shard.Part
			if shard.Age >= shard.Life then
				shard.Active = false
				shardsAlive -= 1
				shardCFrames[count] = HIDDEN_CF
			else
				shard.Vel += SHARD_GRAVITY * dt
				local pos = shard.Pos + shard.Vel * dt
				shard.Pos = pos
				local a = shard.Age
				local spin = shard.Spin
				shardCFrames[count] = CFrame.new(pos) * CFrame.fromEulerAnglesXYZ(spin.X * a, spin.Y * a, spin.Z * a)
				local fade = shard.Age / shard.Life
				if fade > 0.6 then
					shard.Part.Transparency = (fade - 0.6) / 0.4
				end
			end
		end
	end
	if count > 0 then
		workspace:BulkMoveTo(shardParts, shardCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- ---------------------------------------------------------------------
-- WACKELN (eine gemeinsame Stärke, nimmt weich ab). Bewusst dezent: weiches Rauschen statt
-- Zufallssprüngen, gedämpfte Stärke und eine Obergrenze (niemandem soll schlecht werden).
-- ---------------------------------------------------------------------
local SHAKE_TIME = 0.4
local SHAKE_SCALE = 0.55 -- Server-Stärke -> Studs Kamera-Versatz
local SHAKE_MAX = 1.2
local SHAKE_FREQ = 18 -- wie schnell das Rauschen läuft
local shakeStrength = 0
local shakeClock = 0
local shakeLeft = 0
local shakeHumanoid: Humanoid? = nil

local function shake(strength: number)
	if type(strength) ~= "number" or strength ~= strength or strength <= 0 then
		return
	end
	strength = math.min(strength * SHAKE_SCALE, SHAKE_MAX)
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
	local fade = shakeLeft / SHAKE_TIME
	local power = shakeStrength * fade * fade
	shakeClock += dt * SHAKE_FREQ
	humanoid.CameraOffset = Vector3.new(math.noise(shakeClock, 0.5), math.noise(0.5, shakeClock), 0) * power
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
	Size: number,
}

local DELIVER_TIME = 0.9 -- gleich lang wie die Fall-Zeit auf dem Server
local MAX_FLIGHTS = 32 -- Egg Rush: viele Eier fallen fast gleichzeitig
local flights: { Flight } = {}

local function addSparks(part: BasePart, size: number, color: Color3)
	UI.Create("ParticleEmitter", {
		Name = "Sparks",
		Color = ColorSequence.new(WHITE, color),
		LightEmission = 1,
		LightInfluence = 0,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, math.clamp(size * 0.14, 0.15, 0.6)),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new(0, 1),
		Lifetime = NumberRange.new(0.3, 0.6),
		Speed = NumberRange.new(1, 4),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -18, 0),
		Drag = 1.5,
		Rate = 70,
		Parent = part,
	})
end

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
	addSparks(part, size, tail)
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
		Size = size,
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
			-- Geist unsichtbar machen, Schweif + Funken noch ausklingen lassen, dann weg
			local part = flight.Part
			part.Transparency = 1
			local sparks = part:FindFirstChild("Sparks")
			if sparks and sparks:IsA("ParticleEmitter") then
				sparks.Enabled = false
			end
			Debris:AddItem(part, 0.7)
			flights[i] = flights[#flights]
			flights[#flights] = nil
			local ground = flight.To - Vector3.new(0, flight.Size * 0.45, 0)
			burst(flight.To, flight.Color, if flight.Fall then 22 else 14, false)
			puff(ground, flight.Color, 10 + flight.Size * 2)
			ring(ground, flight.Color, 6 + flight.Size * 3, 0.45)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and (root.Position - flight.To).Magnitude < 25 then
				shake(0.2) -- ganz nah: kurzes, leichtes Rumpeln
			end
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
	-- Schale platzt: Splitter fliegen weg, Druckwelle am Boden
	spawnShards(data.Position, color, 6 + math.min(index, 8), math.clamp(0.8 + index * 0.08, 0.8, 1.6))
	ring(data.Position - Vector3.new(0, 1, 0), color, 12 + index * 1.5, 0.55)
	-- Alien ploppt in WorldFX mit Overshoot herein
	WorldFX.NoteHatch(data.Position)
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
local MAX_CONFETTI = 140
local CONFETTI_GRAVITY = 1500 -- Pixel/s² (Konfetti ist leicht: fällt danach langsamer, siehe unten)
local confettiAlive = 0

-- Ein Stück Konfetti: der Halter fliegt gleichmäßig zur Seite, das Stück darin steigt (Quad Out)
-- und fällt (Quad In) – zusammen eine echte Wurfparabel. Dazu Drehen und Flattern (Breite pendelt).
local function confettiPiece(gui: ScreenGui, x: number, y: number, vx: number, vy: number, color: Color3)
	local screen = gui.AbsoluteSize
	local tUp = vy / CONFETTI_GRAVITY
	local peak = y - vy * vy / (2 * CONFETTI_GRAVITY)
	local fallDistance = screen.Y + 30 - peak
	local tDown = math.sqrt(2 * fallDistance / CONFETTI_GRAVITY) * 1.9 -- Luftwiderstand: langsamer fallen
	local life = tUp + tDown
	local width, height = math.random(8, 14), math.random(10, 16)
	local holder: Frame = UI.Create("Frame", {
		Size = UDim2.fromOffset(0, 0),
		Position = UDim2.fromOffset(x, y),
		BackgroundTransparency = 1,
		ZIndex = 25,
		Parent = gui,
	})
	local piece: Frame = UI.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Rotation = math.random(0, 360),
		ZIndex = 25,
		Parent = holder,
	})
	if math.random() < 0.35 then
		UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = piece }) -- runde Plättchen
	end
	-- seitlich: am Anfang schnell, dann vom Luftwiderstand gebremst
	TweenService:Create(
		holder,
		TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(x + vx * 0.9, y) }
	):Play()
	TweenService
		:Create(
			piece,
			TweenInfo.new(life, Enum.EasingStyle.Linear),
			{ Rotation = piece.Rotation + math.random(-720, 720) }
		)
		:Play()
	-- Flattern: Breite pendelt (sieht aus wie ein Blättchen, das sich dreht)
	TweenService:Create(
		piece,
		TweenInfo.new(0.18 + math.random() * 0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Size = UDim2.fromOffset(math.max(2, width * 0.15), height) }
	):Play()
	local up = TweenService:Create(
		piece,
		TweenInfo.new(tUp, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(0, peak - y) }
	)
	up.Completed:Once(function()
		local down = TweenService:Create(
			piece,
			TweenInfo.new(tDown, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.fromOffset(0, screen.Y + 30 - y) }
		)
		down.Completed:Once(function()
			confettiAlive -= 1
			holder:Destroy()
		end)
		down:Play()
	end)
	up:Play()
end

-- Konfetti-Kanonen links und rechts unten schießen schräg nach oben zur Mitte
local function confetti(amount: number)
	local gui = overlay
	if not gui or hidden then
		return
	end
	local colors = { UI.Theme.Yellow, UI.Theme.Green, UI.Theme.Blue, UI.Theme.Purple, UI.Theme.Red, UI.Theme.Pink }
	local count = math.floor(32 * math.clamp(tonumber(amount) or 1, 0.3, 3))
	count = math.min(count, MAX_CONFETTI - confettiAlive)
	local screen = gui.AbsoluteSize
	if screen.Y < 10 then
		return
	end
	for i = 1, count do
		confettiAlive += 1
		local left = i % 2 == 0
		local x = if left then screen.X * 0.04 else screen.X * 0.96
		local y = screen.Y + 10
		-- Gipfel zwischen 35 % und 85 % der Bildschirmhöhe
		local rise = screen.Y * (0.35 + math.random() * 0.5)
		local vy = math.sqrt(2 * CONFETTI_GRAVITY * rise)
		local vx = (screen.X * (0.12 + math.random() * 0.4)) * (if left then 1 else -1)
		confettiPiece(gui, x, y, vx, vy, colors[math.random(1, #colors)])
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
local REVEAL_SPIN2_INFO = TweenInfo.new(9, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
local REVEAL_PULSE_INFO = TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local REVEAL_TILT_INFO = TweenInfo.new(0.6, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
local RAY_COUNT = 12 -- Strahlen im äußeren Kranz (der innere hat halb so viele, dreht andersrum)
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
	Rays2: Frame,
	RayScale: UIScale,
	Glow: Frame,
	RayTweens: { Tween },
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
	-- Strahlenkranz hinter der Karte: zwei Kränze drehen gegeneinander und pulsieren,
	-- jeder Strahl läuft zu den Spitzen hin weich aus (Verlauf), dazu ein weicher Schein in der Mitte
	local rayScale: UIScale = UI.Create("UIScale", { Scale = 1 })
	local glow: Frame = UI.Create("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(470, 470),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.55,
		ZIndex = 30,
		Parent = holder,
	}, {
		UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		UI.Create("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	local rays: Frame = UI.Create("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(620, 620),
		BackgroundTransparency = 1,
		ZIndex = 30,
		Parent = holder,
	}, { rayScale })
	local rays2: Frame = UI.Create("Frame", {
		Name = "Rays2",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(500, 500),
		BackgroundTransparency = 1,
		ZIndex = 30,
		Parent = holder,
	})
	local rayFade = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.55),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(0.7, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	local function addRay(parent: Frame, rotation: number, width: number, transparency: number)
		UI.Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, width, 1, 0),
			Rotation = rotation,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = transparency,
			BorderSizePixel = 0,
			ZIndex = 30,
			Parent = parent,
		}, { UI.Create("UIGradient", { Rotation = 90, Transparency = rayFade }) })
	end
	-- Ein Strahl geht durch die Mitte (= 2 Strahlen) -> RAY_COUNT / 2 Frames je Kranz
	for i = 0, RAY_COUNT / 2 - 1 do
		addRay(rays, i * (360 / RAY_COUNT), if i % 2 == 0 then 54 else 30, 0.45)
	end
	for i = 0, RAY_COUNT / 4 - 1 do
		addRay(rays2, i * (720 / RAY_COUNT) + 15, 22, 0.55)
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
		Rays2 = rays2,
		RayScale = rayScale,
		Glow = glow,
		RayTweens = {},
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
	local rayColor = if ultra then UI.Theme.Yellow else rarityColor:Lerp(WHITE, 0.4)
	for _, layer in ipairs({ ui.Rays, ui.Rays2 }) do
		for _, ray in ipairs(layer:GetChildren()) do
			if ray:IsA("Frame") then
				ray.BackgroundColor3 = rayColor
			end
		end
	end
	ui.Glow.BackgroundColor3 = rayColor
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
			ui.Rays2.Visible = big
			ui.Glow.Visible = big
			ui.Holder.Visible = true
			ui.Scale.Scale = 0.2
			ui.Rays.Rotation = 0
			ui.Rays2.Rotation = 0
			ui.RayScale.Scale = 1
			ui.Holder.Rotation = if big then -8 else 0
			if big then
				-- Strahlen nur bei der großen Karte (die kleine oben rechts bleibt ruhig)
				local tweens = {
					TweenService:Create(ui.Rays, REVEAL_SPIN_INFO, { Rotation = 360 }),
					TweenService:Create(ui.Rays2, REVEAL_SPIN2_INFO, { Rotation = -360 }),
					TweenService:Create(ui.RayScale, REVEAL_PULSE_INFO, { Scale = 1.12 }),
				}
				for _, tween in ipairs(tweens) do
					tween:Play()
				end
				ui.RayTweens = tweens
				TweenService:Create(ui.Holder, REVEAL_TILT_INFO, { Rotation = 0 }):Play()
			end
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
			for _, tween in ipairs(ui.RayTweens) do
				tween:Cancel()
			end
			ui.RayTweens = {}
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
-- 🔥 REBIRTH: Bildschirm blitzt hell auf, großer Schriftzug ploppt, Konfetti
-- ---------------------------------------------------------------------
local REBIRTH_FLASH_INFO = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local REBIRTH_POP_INFO = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local REBIRTH_OUT_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.1)
local rebirthBusy = false

function Effects.RebirthFlash()
	local gui = overlay
	if not gui or hidden or rebirthBusy then
		return
	end
	rebirthBusy = true
	local flash: Frame = UI.Create("Frame", {
		Name = "RebirthFlash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0,
		ZIndex = 40,
		Parent = gui,
	}, {
		-- Mitte weiß, Ränder feurig orange
		UI.Create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, UI.Theme.Orange),
				ColorSequenceKeypoint.new(0.5, WHITE),
				ColorSequenceKeypoint.new(1, UI.Theme.Orange),
			}),
		}),
	})
	local textScale: UIScale = UI.Create("UIScale", { Scale = 0.3 })
	local text = UI.Label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(620, 110),
		Text = "🔥 REBIRTH! 🔥",
		TextColor3 = UI.Theme.Yellow,
		MaxText = 90,
		Outline = 5,
		ZIndex = 41,
		Parent = gui,
	})
	textScale.Parent = text
	text.Rotation = -6
	TweenService:Create(flash, REBIRTH_FLASH_INFO, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(textScale, REBIRTH_POP_INFO, { Scale = 1 }):Play()
	TweenService:Create(text, REVEAL_TILT_INFO, { Rotation = 0 }):Play()
	local stroke = text:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, REBIRTH_OUT_INFO, { Transparency = 1 }):Play()
	end
	local out = TweenService:Create(text, REBIRTH_OUT_INFO, { TextTransparency = 1 })
	out.Completed:Once(function()
		flash:Destroy()
		text:Destroy()
		rebirthBusy = false
	end)
	out:Play()
	confetti(2.5)
	shake(0.6)
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
			flyCoins(amount)
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
	if overlay then
		overlay.Enabled = not value
	end
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
	-- Eigene Ebene über der Oberfläche (ohne deren UIScale -> Pixel = Bildschirm-Pixel)
	overlay = UI.Create("ScreenGui", {
		Name = "MeteorHeistFX",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
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
	buildCoins()
	buildShards()
	RunService.RenderStepped:Connect(function(dt: number)
		stepFlyNumbers(dt)
		if #flights > 0 then
			stepFlights(dt)
		end
		if shardsAlive > 0 then
			stepShards(dt)
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
