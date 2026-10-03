-- =====================================================================
--  FLIEGEN / SCHWEBEN (Taste G) – nur wenn der Server es erlaubt (Attribut CanFly)
--  WASD/Stick = Richtung (folgt der Kamera, auch hoch/runter), Leertaste = hoch, Shift = runter
-- =====================================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Fly = {}

local player = Players.LocalPlayer
local FLY_SPEED = 70

local toast: (string, string?) -> () = function(_text: string, _kind: string?) end
local flying = false
local flyParts: { Instance } = {}
local flyConnection: RBXScriptConnection? = nil

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
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	flying = true
	local attachment = Instance.new("Attachment")
	attachment.Name = "FlyAttachment"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.MaxForce = 1e7
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VectorVelocity = Vector3.zero
	velocity.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxTorque = 1e7
	align.Responsiveness = 40
	align.CFrame = root.CFrame.Rotation
	align.Parent = root
	flyParts = { attachment, velocity, align }
	humanoid.PlatformStand = true

	flyConnection = RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		if not camera or not root.Parent or humanoid.Health <= 0 then
			stopFlying()
			return
		end
		local look = camera.CFrame.LookVector
		local move = humanoid.MoveDirection -- funktioniert mit Tastatur, Gamepad und Handy-Stick
		local direction = Vector3.zero
		if move.Magnitude > 0.05 then
			local flatLook = Vector3.new(look.X, 0, look.Z)
			local forwardAmount = if flatLook.Magnitude > 0.01 then move:Dot(flatLook.Unit) else 0
			direction = move + Vector3.new(0, look.Y * math.max(forwardAmount, 0) * 1.5, 0)
		end
		if not UserInputService:GetFocusedTextBox() then
			if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
				direction += Vector3.new(0, 1, 0)
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.Q) then
				direction -= Vector3.new(0, 1, 0)
			end
		end
		velocity.VectorVelocity = if direction.Magnitude > 0.01 then direction.Unit * FLY_SPEED else Vector3.zero
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.01 then
			align.CFrame = CFrame.lookAt(Vector3.zero, flat)
		end
	end)
end

function Fly.Toggle()
	if flying then
		stopFlying()
		toast("🕊️ Fliegen aus", "Info")
	elseif player:GetAttribute("CanFly") == true then
		startFlying()
		if flying then
			toast("🕊️ Fliegen an! Leertaste = hoch, Shift = runter, G = aus", "Success")
		end
	end
end

function Fly.Init(toastFunction: (string, string?) -> ())
	toast = toastFunction
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.G then
			Fly.Toggle()
		end
	end)
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
end

return Fly
