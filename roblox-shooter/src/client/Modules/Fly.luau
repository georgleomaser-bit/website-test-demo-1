-- =====================================================================
--  CLUTCH CLASH – Fliegen / Schweben (Client/Modules/Fly)
--  Besitzer: WP7 (Sicherheit, Admin, Live-Balance). Basis: Meteor-Heist-Fly (REUSE §1.4, COPY).
--  Nur wenn der Server es erlaubt (Attribut CanFly, nur der Besitzer hat es). Taste G (Config.Client.Keys.Fly).
--  WASD/Stick = Richtung (folgt der Kamera, auch hoch/runter), Leertaste = hoch, Strg/C = runter, Shift = schneller.
--  Beim Losfliegen meldet der Client SetPower{CanFly} an den Server -> im Match wird es "TAINTED" (B25.2).
--  Der Anti-Cheat nimmt Admins aus (AntiCheatService).
--
--  Öffentliche API (C7.4):
--    Fly.Toggle()
--    Fly.IsFlying(): boolean
--    Fly.Init(ctx) / Fly.Start()
-- =====================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Fly = {}

local player = Players.LocalPlayer
local ctx: any = nil

local DEFAULT_SPEED = 70
local BOOST = 2 -- Shift = doppelt so schnell

local flying = false
local flyParts: { Instance } = {}
local flyConnection: RBXScriptConnection? = nil

local function T(key: string, ...: any): string
	if ctx and type(ctx.T) == "function" then
		return ctx.T(key, ...)
	end
	return key
end

local function toast(text: string, kind: string)
	if ctx and type(ctx.Toast) == "function" then
		ctx.Toast(text, kind)
	end
end

local function flySpeed(): number
	local security = ctx and ctx.Config and ctx.Config.Security
	local powers = security and security.Powers
	local speed = powers and tonumber(powers.FlySpeed)
	return if speed and speed > 0 then speed else DEFAULT_SPEED
end

local function keyDown(...: Enum.KeyCode): boolean
	for _, key in ipairs({ ... }) do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

local function stopFlying()
	flying = false
	if flyConnection then
		flyConnection:Disconnect()
		flyConnection = nil
	end
	for _, inst in ipairs(flyParts) do
		inst:Destroy()
	end
	flyParts = {}
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
end

local function startFlying()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart or not rootPart:IsA("BasePart") or humanoid.Health <= 0 then
		return
	end
	if rootPart.Anchored then
		return -- eingefroren / im Tresor
	end
	local root: BasePart = rootPart
	flying = true
	local attachment = Instance.new("Attachment")
	attachment.Name = "CC_FlyAttachment"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "CC_FlyVelocity"
	velocity.Attachment0 = attachment
	velocity.MaxForce = 1e7
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VectorVelocity = Vector3.zero
	velocity.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Name = "CC_FlyAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxTorque = 1e7
	align.Responsiveness = 40
	align.CFrame = root.CFrame.Rotation
	align.Parent = root
	flyParts = { attachment, velocity, align }
	humanoid.PlatformStand = true

	local speed = flySpeed()
	flyConnection = RunService.PreRender:Connect(function()
		local camera = workspace.CurrentCamera
		if not camera or not root.Parent or humanoid.Health <= 0 or root.Anchored then
			stopFlying()
			return
		end
		local look = camera.CFrame.LookVector
		local move = humanoid.MoveDirection -- Tastatur, Gamepad und Handy-Stick
		local direction = Vector3.zero
		if move.Magnitude > 0.05 then
			local flatLook = Vector3.new(look.X, 0, look.Z)
			local forwardAmount = if flatLook.Magnitude > 0.01 then move:Dot(flatLook.Unit) else 0
			direction = move + Vector3.new(0, look.Y * math.max(forwardAmount, 0) * 1.5, 0)
		end
		local boost = 1
		if not UserInputService:GetFocusedTextBox() then
			if keyDown(Enum.KeyCode.Space, Enum.KeyCode.ButtonA) then
				direction += Vector3.new(0, 1, 0)
			end
			if keyDown(Enum.KeyCode.LeftControl, Enum.KeyCode.C, Enum.KeyCode.ButtonB) then
				direction -= Vector3.new(0, 1, 0)
			end
			if keyDown(Enum.KeyCode.LeftShift) then
				boost = BOOST
			end
		end
		velocity.VectorVelocity = if direction.Magnitude > 0.01 then direction.Unit * speed * boost else Vector3.zero
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.01 then
			align.CFrame = CFrame.lookAt(Vector3.zero, flat)
		end
	end)

	-- Server erfährt es (Taint im Match); Antwort egal
	local remotes = ctx and ctx.Remotes
	local admin = remotes and remotes.Admin
	if admin and admin:IsA("RemoteFunction") then
		task.spawn(function()
			pcall(function()
				admin:InvokeServer("SetPower", { Name = "CanFly", Value = true })
			end)
		end)
	end
end

function Fly.IsFlying(): boolean
	return flying
end

function Fly.Toggle()
	if flying then
		stopFlying()
		toast(T("admin.flyOff"), "Info")
	elseif player:GetAttribute("CanFly") == true and player:GetAttribute("IsAdmin") == true then
		startFlying()
		if flying then
			toast(T("admin.flyOn"), "Success")
		end
	end
end

local function keyCodes(): { Enum.KeyCode }
	local out: { Enum.KeyCode } = {}
	local keys = ctx and ctx.Config and ctx.Config.Client and ctx.Config.Client.Keys
	local names = if keys and type(keys.Fly) == "table" then keys.Fly else { "G" }
	for _, name in ipairs(names) do
		local ok, code = pcall(function()
			return (Enum.KeyCode :: any)[name]
		end)
		if ok and typeof(code) == "EnumItem" then
			table.insert(out, code :: any)
		end
	end
	return out
end

function Fly.Init(context: any)
	ctx = context
end

function Fly.Start()
	local controls = ctx and ctx.Modules and ctx.Modules.Controls
	local bound = false
	if controls and type(controls.Bind) == "function" then
		bound = pcall(controls.Bind, "Fly", function(state: string)
			if state == "Begin" then
				Fly.Toggle()
			end
		end)
	end
	if not bound then
		local codes = keyCodes()
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed or UserInputService:GetFocusedTextBox() then
				return
			end
			if table.find(codes, input.KeyCode) then
				Fly.Toggle()
			end
		end)
	end
	player.CharacterAdded:Connect(function()
		if flying then
			stopFlying()
		end
	end)
	player:GetAttributeChangedSignal("CanFly"):Connect(function()
		if player:GetAttribute("CanFly") ~= true and flying then
			stopFlying()
		end
	end)
	local hooks = ctx and ctx.Hooks
	if hooks and type(hooks.On) == "function" then
		hooks.On("LocalPopped", function()
			if flying then
				stopFlying()
			end
		end)
	end
end

return Fly
