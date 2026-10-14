-- =====================================================================
--  AKYTEX TYCOON – Fahren: Motoren, Lenkung, Boost, Drift, Tacho (Client/Modules/Vehicles)
--  Besitzer: WP7 (Stadt, Grafik, Fahrzeuge). Vertrag: DESIGN.md §B12.1 (VehicleSeat + HingeConstraint-Motoren, Servo-
--  Lenkung, Federung; Netzwerk-Besitzer = Fahrer; Boost Shift/Touch +25 % für 3 s, 8 s Abklingzeit; Handbremse Leertaste
--  senkt die Hinterrad-Reibung auf 0,3 = Drift; Klassen-Höchsttempo), §C7.2 (Hooks "Vehicle:Enter"/"Vehicle:Exit"),
--  §C7.5 (Vehicles.Current), §A4 (Motor-Ton = Sfx-Loop "Engine", Tonhöhe nach Tempo), §A7 #10 (Fahrt zum Autobahnring).
--
--  Der Server hat das Auto gebaut (VehicleModels.Rig) und gibt dem Fahrer den Netzwerk-Besitz: dieses Modul setzt nur
--  lokale Constraint-Werte (Motor-Drehzahl/-Moment, Servo-Winkel, Anpressdruck, Reibung). Der Server prüft 5×/s das
--  Tempo (1,3 × Klassen-Deckel). Eingaben: VehicleSeat.ThrottleFloat/SteerFloat (Roblox-Steuerung: WASD, Stick, Touch),
--  Aktionen "Boost"/"Handbrake" über Controls (Tasten, Gamepad, Touch-Knöpfe), Aussteigen = Springen bzw. "Interact" (E).
--  Fremde Einsteige-Prompts werden lokal ausgeblendet (nur der Besitzer sieht "Einsteigen").
--
--  Öffentliche API (§C7.5):
--    Vehicles.Current(): Model?             Auto, in dem man gerade fährt
--  Zusätzlich: Vehicles.Waypoint(target?: Vector3) (Navi-Strahl, z. B. zum Autobahnring), Vehicles.BoostState(): (aktiv, Rest)
--    Vehicles.Frame(dt) · Vehicles.Init(ctx) · Vehicles.Start()
-- =====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = require(script.Parent:WaitForChild("UI"))
local VehicleModels = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("VehicleModels")) :: any
local AssetSlot = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AssetSlot"))

local Vehicles = {}

local player = Players.LocalPlayer
local Theme = UI.Theme

type Drive = {
	Model: Model,
	Key: string,
	Seat: VehicleSeat,
	Chassis: BasePart,
	Motors: { [string]: HingeConstraint },
	Steer: { [string]: HingeConstraint },
	Wheels: { [string]: BasePart },
	Downforce: VectorForce?,
	Cap: number,
	Accel: number,
	Radius: number,
	Mass: number,
	BaseTorque: number,
	FlipTime: number,
	Engine: any?,
	Pitch: number, -- Motor-Rezept: Tonhöhen-Faktor (Config SoundId = eigener Klang -> 1)
	Tails: { BasePart },
	Smoke: { ParticleEmitter },
	Flames: { ParticleEmitter },
	Braking: boolean?,
	TestLeft: number?,
}

local ctx: any = nil
local VC: any = {}
local drive: Drive? = nil
local humanoidConn: RBXScriptConnection? = nil
local boostUntil = 0
local cooldownUntil = 0
local handbrake = false
local rearFriction = 1.5
local baseFov: number? = nil

-- Eigene Motor-Rezepte (§B14.1 Λ-1 „eigenes Motor-Rezept“): gleiche Schleife, eigene Tonhöhe/Klangfarbe.
-- Ein eingetragenes Config.Vehicles.Cars[].SoundId ersetzt die Schleife ganz (ASSET-LISTE 5.1).
local ENGINE_RECIPES: { [string]: { Pitch: number, EqLow: number, EqMid: number, EqHigh: number, Vol: number } } = {
	Lam1 = { Pitch = 1.3, EqLow = 6, EqMid = -2, EqHigh = 5, Vol = 1.25 }, -- hoher Turbinen-Ton mit Bass-Fundament
}

-- Tacho
local hud: Frame? = nil
local speedLabel: TextLabel? = nil
local boostFill: Frame? = nil
local boostLabel: TextLabel? = nil
local hintLabel: TextLabel? = nil

-- Navi
local waypointFolder: Folder? = nil
local waypointTarget: Vector3? = nil
local waypointUntil = 0
local waypointA: Attachment? = nil

local HIDDEN_PROMPTS_MAX = 64
local hiddenPrompts: { [ProximityPrompt]: RBXScriptConnection } = {}
local hiddenCount = 0

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

local function reducedFx(): boolean
	local ok, settings = call("Settings", "Get")
	return ok and type(settings) == "table" and settings.ReducedFx == true
end

local function physical(density: number, friction: number): PhysicalProperties
	return PhysicalProperties.new(density, friction, 0, (VC.Physics and VC.Physics.FrictionWeight) or 4, 1)
end

-- ---------------------------------------------------------------------
-- 1) TACHO (UI-Kit-Look: dunkles Glas, BuilderMono)
-- ---------------------------------------------------------------------
local function buildHud()
	local gui = ctx.Gui
	local frame: Frame = UI.Create("Frame", {
		Name = "Speedometer",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.fromOffset(220, 74),
		BackgroundColor3 = Theme.Surface,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Visible = false,
		Parent = gui,
	}, { UI.Corner(14), UI.Stroke(nil, 1) })
	speedLabel = UI.Label({
		Name = "Speed",
		Position = UDim2.fromOffset(14, 6),
		Size = UDim2.new(0.62, -14, 0, 40),
		Face = "MonoBold",
		Text = "0",
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 38,
		Parent = frame,
	})
	UI.Label({
		Name = "Unit",
		Position = UDim2.new(0.62, 0, 0, 16),
		Size = UDim2.new(0.38, -14, 0, 22),
		Text = ctx.T("car.speedUnit"),
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxText = 16,
		Parent = frame,
	})
	local barBack: Frame = UI.Create("Frame", {
		Name = "Boost",
		Position = UDim2.new(0, 14, 1, -24),
		Size = UDim2.new(1, -28, 0, 8),
		BackgroundColor3 = Theme.Bg2,
		BorderSizePixel = 0,
		Parent = frame,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	boostFill = UI.Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Parent = barBack,
	}, { UI.Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	boostLabel = UI.Label({
		Name = "BoostText",
		Position = UDim2.new(0, 14, 1, -40),
		Size = UDim2.new(0.5, -14, 0, 14),
		Text = ctx.T("car.boostReady"),
		TextColor3 = Theme.Text2,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 12,
		Parent = frame,
	})
	hintLabel = UI.Label({
		Name = "Hint",
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.new(0.5, -14, 0, 14),
		Text = "",
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxText = 12,
		Parent = frame,
	})
	hud = frame
end

local function setHudVisible(on: boolean)
	local frame = hud
	if not frame then
		return
	end
	frame.Visible = on
	if on and hintLabel then
		local okInput, kind = call("Controls", "Input")
		hintLabel.Text = if okInput and kind == "Touch" then ctx.T("car.exitHintTouch") else ctx.T("car.exitHint")
		hintLabel.TextColor3 = Theme.Muted
	end
end

-- ---------------------------------------------------------------------
-- 2) EINSTEIGEN / AUSSTEIGEN
-- ---------------------------------------------------------------------
local function carModelOf(seat: Instance?): Model?
	if not seat or not seat:IsA("VehicleSeat") then
		return nil
	end
	local model = seat.Parent
	if model and model:IsA("Model") and model:GetAttribute("Car") ~= nil then
		return model
	end
	return nil
end

local function collect(model: Model, prefix: string, class: string): { [string]: any }
	local out: { [string]: any } = {}
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA(class) and string.sub(inst.Name, 1, #prefix) == prefix then
			out[string.sub(inst.Name, #prefix + 1)] = inst
		end
	end
	return out
end

-- Lokale Fahr-Effekte (nur beim Fahrer, im Partikel-Budget): Drift-Rauch an den Hinterrädern, Boost-Flammen am Auspuff
local function particleBudget(): number
	local ok, value = call("Quality", "Budget", "Particles")
	return if ok and type(value) == "number" then math.clamp(value, 0, 1) else 0.6
end

local function addEmitter(parent: BasePart, offset: Vector3, kind: string): ParticleEmitter
	local attachment = Instance.new("Attachment")
	attachment.Name = "AT_Fx" .. kind
	attachment.Position = offset
	attachment.Parent = parent
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "AT_" .. kind
	emitter.Enabled = false
	emitter.LockedToPart = false
	if kind == "Smoke" then
		emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
		emitter.Color = ColorSequence.new(Color3.fromRGB(200, 206, 216))
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 5) })
		emitter.Lifetime = NumberRange.new(0.7, 1.2)
		emitter.Speed = NumberRange.new(2, 5)
		emitter.SpreadAngle = Vector2.new(40, 40)
		emitter.Rate = 0
		emitter.EmissionDirection = Enum.NormalId.Top
	else
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(Theme.Accent, Theme.Cosmic3)
		emitter.LightEmission = 1
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0.1) })
		emitter.Lifetime = NumberRange.new(0.15, 0.3)
		emitter.Speed = NumberRange.new(14, 22)
		emitter.SpreadAngle = Vector2.new(8, 8)
		emitter.Rate = 0
		emitter.EmissionDirection = Enum.NormalId.Back
	end
	emitter.Parent = attachment
	return emitter
end

local function buildDriveFx(d: Drive)
	for key, wheel in pairs(d.Wheels) do
		if string.sub(key, 1, 1) == "R" then
			table.insert(d.Smoke, addEmitter(wheel, Vector3.new(0, -d.Radius * 0.8, 0), "Smoke"))
		end
	end
	for _, name in ipairs({ "ExhaustL", "ExhaustR" }) do
		local pipe = d.Model:FindFirstChild(name)
		if pipe and pipe:IsA("BasePart") then
			table.insert(d.Flames, addEmitter(pipe, Vector3.zero, "Flame"))
		end
	end
	for _, inst in ipairs(d.Model:GetDescendants()) do
		if inst:IsA("BasePart") and inst:GetAttribute("Light") == "Tail" then
			table.insert(d.Tails, inst)
		end
	end
end

local function clearDriveFx(d: Drive)
	for _, list in ipairs({ d.Smoke, d.Flames }) do
		for _, emitter in ipairs(list) do
			local holder = emitter.Parent
			if holder then
				holder:Destroy()
			end
		end
		table.clear(list)
	end
	for _, tail in ipairs(d.Tails) do
		if tail.Parent then
			tail.Color = Color3.fromRGB(239, 48, 56)
		end
	end
end

-- Bremslicht hell, Drift-Rauch, Boost-Flammen (jeden Frame; nur Werte ändern, wenn sie sich ändern)
local function stepDriveFx(d: Drive, speed: number, braking: boolean, boosting: boolean)
	if braking ~= d.Braking then
		d.Braking = braking
		local color = if braking then Color3.fromRGB(255, 72, 80) else Color3.fromRGB(176, 28, 36)
		for _, tail in ipairs(d.Tails) do
			if tail.Parent then
				tail.Color = color
			end
		end
	end
	local fx = particleBudget()
	local reduced = reducedFx()
	local smokeRate = if handbrake and speed > 14 and not reduced then 60 * fx else 0
	for _, emitter in ipairs(d.Smoke) do
		if emitter.Rate ~= smokeRate then
			emitter.Rate = smokeRate
			emitter.Enabled = smokeRate > 0
		end
	end
	local flameRate = if boosting and not reduced then 90 * fx else 0
	for _, emitter in ipairs(d.Flames) do
		if emitter.Rate ~= flameRate then
			emitter.Rate = flameRate
			emitter.Enabled = flameRate > 0
		end
	end
end

local function stopDrive()
	local d = drive
	if not d then
		return
	end
	clearDriveFx(d)
	-- Handbremse beim Aussteigen gehalten: Hinterrad-Reibung zurücksetzen (sonst driftet das Auto beim
	-- nächsten Einsteigen dauerhaft – die "End"-Eingabe kommt erst, wenn drive schon nil ist)
	if handbrake then
		for key, wheel in pairs(d.Wheels) do
			if string.sub(key, 1, 1) == "R" and wheel.Parent then
				wheel.CustomPhysicalProperties = physical((VC.Physics and VC.Physics.WheelDensity) or 0.9, rearFriction)
			end
		end
	end
	drive = nil
	handbrake = false
	if d.Engine then
		pcall(d.Engine.Stop)
	end
	-- Motoren entspannen (Besitz geht an den Server)
	for _, motor in pairs(d.Motors) do
		motor.AngularVelocity = 0
	end
	if d.Downforce then
		d.Downforce.Force = Vector3.zero
	end
	setHudVisible(false)
	local camera = workspace.CurrentCamera
	if camera and baseFov then
		camera.FieldOfView = baseFov
	end
	ctx.Hooks.Fire("Vehicle:Exit", d.Model)
end

local function startDrive(model: Model, seat: VehicleSeat)
	stopDrive()
	local key = model:GetAttribute("Car")
	local chassis = model:FindFirstChild("Chassis")
	if type(key) ~= "string" or not chassis or not chassis:IsA("BasePart") then
		return
	end
	local car = VC.Car and VC.Car(key) or nil
	local classInfo = car and VC.ClassInfo and VC.ClassInfo[car.Class] or nil
	local downforce = chassis:FindFirstChild("Downforce")
	local cap = model:GetAttribute("Cap")
	local mass = model:GetAttribute("Mass")
	local torque = model:GetAttribute("BaseTorque")
	local radius = model:GetAttribute("WheelR")
	drive = {
		Model = model,
		Key = key,
		Seat = seat,
		Chassis = chassis,
		Motors = collect(model, "Motor_", "HingeConstraint"),
		Steer = collect(model, "Steer_", "HingeConstraint"),
		Wheels = collect(model, "Wheel_", "BasePart"),
		Downforce = if downforce and downforce:IsA("VectorForce") then downforce else nil,
		Cap = if type(cap) == "number" then cap else 60,
		Accel = if classInfo then classInfo.Accel else 30,
		Radius = if type(radius) == "number" then radius else 1.3,
		Mass = if type(mass) == "number" then mass else chassis.AssemblyMass,
		BaseTorque = if type(torque) == "number" then torque else 20000,
		FlipTime = 0,
		Engine = nil,
		Pitch = 1,
		Tails = {},
		Smoke = {},
		Flames = {},
		Braking = nil,
		TestLeft = nil,
	}
	buildDriveFx(drive :: Drive)
	local ok, handle = call("Sfx", "Loop", "Engine", chassis)
	if ok and handle then
		local d = drive :: Drive
		d.Engine = handle
		local sound = if type(handle) == "table" then handle.Sound else nil
		local custom = car and AssetSlot.SoundId(car.SoundId) or nil
		local recipe = car and ENGINE_RECIPES[car.Recipe or key] or nil
		if typeof(sound) == "Instance" and sound:IsA("Sound") then
			if custom then
				-- eigener Motor-Klang aus der Config (nahtlose Schleife) in Originaltonhöhe: SetSpeed rechnet mit der
				-- Grundtonhöhe der Rezept-Schleife – die hier herausrechnen
				d.Pitch = 1 / math.max(0.1, sound.PlaybackSpeed)
				sound.SoundId = custom
				sound:Play() -- neue Quelle sicher starten (die Schleife lief schon mit dem Rezept-Klang)
				local eq = sound:FindFirstChildOfClass("EqualizerSoundEffect")
				if eq then
					eq:Destroy() -- eigener Klang bleibt unverfärbt
				end
			elseif recipe then
				d.Pitch = recipe.Pitch
				local eq = sound:FindFirstChildOfClass("EqualizerSoundEffect") or Instance.new("EqualizerSoundEffect")
				eq.LowGain = recipe.EqLow
				eq.MidGain = recipe.EqMid
				eq.HighGain = recipe.EqHigh
				eq.Parent = sound
				pcall(handle.SetVolume, recipe.Vol)
			end
		end
	end
	local camera = workspace.CurrentCamera
	if camera then
		baseFov = camera.FieldOfView
	end
	setHudVisible(true)
	ctx.Hooks.Fire("Vehicle:Enter", model)
end

local function onSeatChanged(humanoid: Humanoid)
	local seat = humanoid.SeatPart
	local model = carModelOf(seat)
	if model and model:GetAttribute("Owner") == player.UserId and seat and seat:IsA("VehicleSeat") then
		startDrive(model, seat)
	else
		stopDrive()
	end
end

local function onCharacter(character: Model)
	if humanoidConn then
		humanoidConn:Disconnect()
		humanoidConn = nil
	end
	stopDrive()
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoidConn = humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
		onSeatChanged(humanoid)
	end)
	onSeatChanged(humanoid)
end

local function exitCar()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and drive then
		humanoid.Sit = false
		humanoid.Jump = true
	end
end

-- fremde "Einsteigen"-Prompts lokal ausblenden
local function considerPrompt(inst: Instance)
	if not inst:IsA("ProximityPrompt") or inst:GetAttribute("Action") ~= "CarEnter" then
		return
	end
	if inst:GetAttribute("Owner") == player.UserId or hiddenPrompts[inst] or hiddenCount >= HIDDEN_PROMPTS_MAX then
		return
	end
	inst.Enabled = false
	hiddenCount += 1
	hiddenPrompts[inst] = inst:GetPropertyChangedSignal("Enabled"):Connect(function()
		if inst.Enabled then
			inst.Enabled = false -- Server schaltet beim Aussteigen wieder an -> lokal aus lassen
		end
	end)
end

local function forgetPrompt(inst: Instance)
	local conn = if inst:IsA("ProximityPrompt") then hiddenPrompts[inst] else nil
	if conn then
		conn:Disconnect()
		hiddenPrompts[inst :: ProximityPrompt] = nil
		hiddenCount -= 1
	end
end

-- ---------------------------------------------------------------------
-- 3) FAHREN (jeder Frame, nur mit Netzwerk-Besitz wirksam)
-- ---------------------------------------------------------------------
local function setRearFriction(friction: number)
	local d = drive
	if not d then
		return
	end
	for key, wheel in pairs(d.Wheels) do
		if string.sub(key, 1, 1) == "R" and wheel.Parent then
			local density = (VC.Physics and VC.Physics.WheelDensity) or 0.9
			wheel.CustomPhysicalProperties = physical(density, friction)
		end
	end
end

local function flipIfNeeded(d: Drive, dt: number)
	local up = d.Chassis.CFrame.UpVector
	if up.Y < 0.25 then
		d.FlipTime += dt
	else
		d.FlipTime = 0
	end
	local limit = (VC.Physics and VC.Physics.FlipSeconds) or 2
	if d.FlipTime >= limit then
		d.FlipTime = 0
		local pos = d.Chassis.Position
		local look = d.Chassis.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.1 then
			flat = Vector3.new(0, 0, -1)
		end
		local target = CFrame.lookAt(pos + Vector3.new(0, 4, 0), pos + Vector3.new(0, 4, 0) + flat)
		local okPivot = pcall(function()
			d.Model:PivotTo(target * d.Chassis.CFrame:ToObjectSpace(d.Model:GetPivot()))
			d.Chassis.AssemblyLinearVelocity = Vector3.zero
			d.Chassis.AssemblyAngularVelocity = Vector3.zero
		end)
		if okPivot then
			ctx.Toast(ctx.T("car.flipped"), "Info")
		end
	end
end

local function updateDrive(d: Drive, dt: number)
	if not d.Model.Parent or not d.Chassis.Parent then
		stopDrive()
		return
	end
	local physics = VC.Physics or {}
	local boostCfg = VC.Boost or { Mult = 1.25, Seconds = 3, Cooldown = 8 }
	local t = os.clock()
	local boosting = t < boostUntil
	local throttle = d.Seat.ThrottleFloat
	local steer = d.Seat.SteerFloat
	local velocity = d.Chassis.AssemblyLinearVelocity
	local forward = velocity:Dot(d.Chassis.CFrame.LookVector)
	local speed = math.abs(forward)
	local mult = if boosting then boostCfg.Mult else 1
	local cap = d.Cap * mult
	local sign = VehicleModels.WHEEL_SIGN
	local r = math.max(0.5, d.Radius)
	local target = 0
	local torque = d.BaseTorque * (physics.CoastTorque or 0.08)
	local accel = d.Accel * mult / r
	if throttle > 0.05 then
		if forward < -2 then
			target, torque, accel = 0, d.BaseTorque * (physics.BrakeFactor or 2.2), 400 -- Bremsen aus dem Rückwärtsgang
		else
			target = cap * throttle
			torque = d.BaseTorque * mult
		end
	elseif throttle < -0.05 then
		if forward > 2 then
			target, torque, accel = 0, d.BaseTorque * (physics.BrakeFactor or 2.2), 400 -- Bremsen
		else
			target = -d.Cap * (physics.ReverseFactor or 0.35) * -throttle
			torque = d.BaseTorque
		end
	else
		target = forward -- rollen lassen
	end
	for key, motor in pairs(d.Motors) do
		local rear = string.sub(key, 1, 1) == "R"
		if handbrake and rear then
			motor.AngularVelocity = 0
			motor.MotorMaxTorque = d.BaseTorque * (physics.BrakeFactor or 2.2)
			motor.MotorMaxAcceleration = 400
		else
			motor.AngularVelocity = sign * target / r
			motor.MotorMaxTorque = torque
			motor.MotorMaxAcceleration = accel
		end
	end
	-- Lenkung: weniger Einschlag bei hohem Tempo; positiver Winkel lenkt nach links
	local maxSteer = (physics.SteerMax or 34)
		+ ((physics.SteerMin or 9) - (physics.SteerMax or 34)) * math.clamp(speed / d.Cap, 0, 1)
	for _, servo in pairs(d.Steer) do
		servo.TargetAngle = -steer * maxSteer
	end
	-- Anpressdruck
	if d.Downforce then
		local factor = math.clamp(speed / d.Cap, 0, 1.3)
		d.Downforce.Force =
			Vector3.new(0, -(physics.Downforce or 0.6) * d.Mass * workspace.Gravity * factor * factor, 0)
	end
	flipIfNeeded(d, dt)
	local braking = handbrake or (throttle < -0.05 and forward > 2) or (throttle > 0.05 and forward < -2)
	stepDriveFx(d, speed, braking, boosting)
	-- Ton, Kamera, Tacho
	if d.Engine then
		pcall(d.Engine.SetSpeed, d.Pitch * (0.7 + 0.9 * math.clamp(speed / d.Cap, 0, 1.3)))
	end
	local camera = workspace.CurrentCamera
	if camera and baseFov and not reducedFx() then
		local goal = baseFov + 8 * math.clamp(speed / d.Cap, 0, 1) + (if boosting then 4 else 0)
		camera.FieldOfView += (goal - camera.FieldOfView) * math.clamp(dt * 4, 0, 1)
	end
	if speedLabel then
		-- km/h ≈ Studs/s (1 Stud ≈ 0,28 m)
		speedLabel.Text = tostring(math.floor(speed + 0.5))
	end
	-- Probefahrt: Restzeit statt Aussteige-Hinweis
	local testUntil = d.Model:GetAttribute("TestUntil")
	if hintLabel and type(testUntil) == "number" then
		local left = math.max(0, math.ceil(testUntil - workspace:GetServerTimeNow()))
		if left ~= d.TestLeft then
			d.TestLeft = left
			hintLabel.Text = ctx.T("car.testLeft", ("%d:%02d"):format(left // 60, left % 60))
			hintLabel.TextColor3 = if left <= 10 then Theme.Warn else Theme.Cosmic3
		end
	elseif d.TestLeft ~= nil then
		d.TestLeft = nil
		setHudVisible(true) -- gekauft während der Probefahrt: normaler Hinweis zurück
		if hintLabel then
			hintLabel.TextColor3 = Theme.Muted
		end
	end
	if boostFill and boostLabel then
		local ready = t >= cooldownUntil
		local ratio = if boosting
			then (boostUntil - t) / boostCfg.Seconds
			elseif ready then 1
			else 1 - (cooldownUntil - t) / math.max(0.1, boostCfg.Cooldown - boostCfg.Seconds)
		boostFill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
		boostFill.BackgroundColor3 = if boosting then Theme.Cosmic2 elseif ready then Theme.Accent else Theme.Muted
		boostLabel.Text = if ready then ctx.T("car.boostReady") else ctx.T("car.boost")
	end
end

-- ---------------------------------------------------------------------
-- 4) NAVI-STRAHL (z. B. nach der Enthüllung zum Autobahnring)
-- ---------------------------------------------------------------------
local function clearWaypoint()
	waypointTarget = nil
	if waypointFolder then
		waypointFolder:Destroy()
	end
	waypointFolder = nil
	waypointA = nil
end

function Vehicles.Waypoint(target: Vector3?)
	clearWaypoint()
	if typeof(target) ~= "Vector3" then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "AT_Waypoint"
	local pillar = Instance.new("Part")
	pillar.Name = "Pillar"
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanQuery = false
	pillar.CanTouch = false
	pillar.CastShadow = false
	pillar.Material = Enum.Material.Neon
	pillar.Color = Theme.Accent
	pillar.Transparency = 0.35
	pillar.Size = Vector3.new(2, 80, 2)
	pillar.CFrame = CFrame.new(target + Vector3.new(0, 40, 0))
	pillar.Parent = folder
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -38, 0)
	a1.Parent = pillar
	local holder = Instance.new("Part")
	holder.Name = "From"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.5, 0.5, 0.5)
	holder.Parent = folder
	local a0 = Instance.new("Attachment")
	a0.Parent = holder
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 1.4
	beam.Width1 = 1.4
	beam.Texture = "rbxasset://textures/gradient.png"
	beam.TextureSpeed = 2
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Color = ColorSequence.new(Theme.Accent, Theme.Cosmic2)
	beam.Parent = holder
	folder.Parent = workspace
	waypointFolder = folder
	waypointTarget = target
	waypointUntil = os.clock() + 90
	waypointA = a0
end

local function updateWaypoint()
	local target = waypointTarget
	if not target then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or os.clock() > waypointUntil then
		if os.clock() > waypointUntil then
			clearWaypoint()
		end
		return
	end
	local holder = waypointA and waypointA.Parent
	if holder and holder:IsA("BasePart") then
		holder.CFrame = CFrame.new(root.Position + Vector3.new(0, 2, 0))
	end
	if (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(target.X, 0, target.Z)).Magnitude < 40 then
		clearWaypoint()
	end
end

-- ---------------------------------------------------------------------
-- ÖFFENTLICHE API
-- ---------------------------------------------------------------------
function Vehicles.Current(): Model?
	local d = drive
	return if d then d.Model else nil
end

function Vehicles.BoostState(): (boolean, number)
	local t = os.clock()
	return t < boostUntil, math.max(0, cooldownUntil - t)
end

function Vehicles.Frame(dt: number)
	local d = drive
	if d then
		local ok, err = pcall(updateDrive, d, dt)
		if not ok then
			warn("[Vehicles] " .. tostring(err))
		end
	end
	updateWaypoint()
end

function Vehicles.Init(context: any)
	ctx = context
	VC = ctx.Config.Vehicles or {}
	local physics = VC.Physics or {}
	rearFriction = physics.RearFriction or 1.5
	buildHud()
	local controls = ctx.Modules.Controls
	if controls and type(controls.Bind) == "function" then
		controls.Bind("Boost", function(state: string)
			if state ~= "Begin" or not drive then
				return
			end
			local t = os.clock()
			if t < cooldownUntil then
				return
			end
			local boost = VC.Boost or { Seconds = 3, Cooldown = 8 }
			boostUntil = t + boost.Seconds
			cooldownUntil = t + boost.Cooldown
			call("Sfx", "Play", "Whoosh")
		end)
		controls.Bind("Handbrake", function(state: string)
			if not drive then
				handbrake = false
				return
			end
			if state == "Begin" then
				handbrake = true
				setRearFriction((VC.DriftFriction or 0.3))
			elseif state == "End" then
				handbrake = false
				setRearFriction(rearFriction)
			end
		end)
		controls.Bind("Interact", function(state: string)
			if state == "Begin" and drive then
				exitCar()
			end
		end)
	end
	ctx.Hooks.On("Settings", function()
		setHudVisible(drive ~= nil)
	end)
end

function Vehicles.Start()
	player.CharacterAdded:Connect(function(character: Model)
		task.spawn(onCharacter, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	workspace.DescendantAdded:Connect(considerPrompt)
	workspace.DescendantRemoving:Connect(forgetPrompt)
	task.spawn(function()
		local carFolder = workspace:FindFirstChild("AkytexCars")
		if carFolder then
			for _, inst in ipairs(carFolder:GetDescendants()) do
				considerPrompt(inst)
			end
		end
	end)
end

return Vehicles
