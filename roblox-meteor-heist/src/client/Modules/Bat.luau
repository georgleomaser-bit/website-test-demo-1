-- =====================================================================
--  SCHLÄGER (lokal): Ausholen und Zuschlagen über Tool.Grip, kurzes Taumeln nach einem Treffer
--   • Schwung: Grip wird lokal getweent (ausholen -> zuschlagen -> zurück). Andere Spieler sehen die
--     "Slash"-Animation, die der Server über das Standard-Animate-Skript startet.
--   • Getroffen (Effekt "Bonked" vom Server): kurz umfallen (PlatformStand) und wieder aufstehen.
--     Niemand stirbt davon. Den Rückstoß selbst macht der Server.
--  Ob ein Schlag trifft, entscheidet NUR der Server (Reichweite, Abklingzeit, Blickrichtung ...).
-- =====================================================================

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Bat = {}

local player = Players.LocalPlayer
local ctx: any = nil

-- Gleiche Ruhe-Haltung wie beim Server (CarryService BAT_REST_GRIP); positive Winkel = nach vorne
local GRIP_POS = CFrame.new(0, -0.4, 0)
local REST = GRIP_POS * CFrame.Angles(math.rad(-15), 0, 0)
local WINDUP = GRIP_POS * CFrame.Angles(math.rad(-70), 0, 0)
local STRIKE = GRIP_POS * CFrame.Angles(math.rad(85), 0, 0)
local WINDUP_INFO = TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local STRIKE_INFO = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local RETURN_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SWING_SOUND = "rbxasset://sounds/swordslash.wav"
local TUMBLE_SPIN = 7 -- Drehung beim Umfallen (rad/s)

local swinging = false
local lastSwing = 0
local swingSound: Sound? = nil
local stunToken = 0
local hooked: { [Tool]: boolean } = {}

-- Abklingzeit wie beim Server (Super-Bonk-Boost macht schneller)
local function cooldownFor(tool: Tool): number
	local Config = ctx.Config
	local bat = Config.BatsById and Config.BatsById[tool:GetAttribute("Bat")]
	local cooldown = bat and tonumber(bat.Cooldown) or 0.8
	local gadgets = ctx.State and ctx.State.Gadgets
	if type(gadgets) == "table" and table.find(gadgets, "SuperBonk") then
		cooldown *= tonumber(Config.SuperBonkCooldownMult) or 1
	end
	return cooldown
end

local function swing(tool: Tool)
	local now = os.clock()
	if swinging or now - lastSwing < cooldownFor(tool) then
		return
	end
	lastSwing = now
	swinging = true
	local sound = swingSound
	if sound then
		sound.PlaybackSpeed = 0.9 + math.random() * 0.2
		sound:Play()
	end
	local windup = TweenService:Create(tool, WINDUP_INFO, { Grip = WINDUP })
	windup:Play()
	windup.Completed:Wait()
	local strike = TweenService:Create(tool, STRIKE_INFO, { Grip = STRIKE })
	strike:Play()
	strike.Completed:Wait()
	local back = TweenService:Create(tool, RETURN_INFO, { Grip = REST })
	back:Play()
	back.Completed:Wait()
	swinging = false
end

local function hookTool(tool: Instance)
	if not tool:IsA("Tool") or tool:GetAttribute("Bat") == nil or hooked[tool] then
		return
	end
	hooked[tool] = true
	tool.Activated:Connect(function()
		task.spawn(swing, tool)
	end)
	tool.Destroying:Connect(function()
		hooked[tool] = nil
	end)
end

local function watchContainer(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		hookTool(child)
	end
	container.ChildAdded:Connect(hookTool)
end

-- Getroffen: kurz umfallen und in Flugrichtung kippen, danach wieder aufstehen
function Bat.Bonked(data: any)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end
	if humanoid.PlatformStand and stunToken == 0 then
		return -- schon PlatformStand von etwas anderem (z.B. Fliegen) -> nicht stören
	end
	local seconds = math.clamp(tonumber(type(data) == "table" and data.Time) or 0.9, 0.2, 2)
	local dir = if type(data) == "table" and typeof(data.Dir) == "Vector3" then data.Dir else -root.CFrame.LookVector
	stunToken += 1
	local token = stunToken
	humanoid.PlatformStand = true
	root.AssemblyAngularVelocity = Vector3.yAxis:Cross(dir) * TUMBLE_SPIN
	task.delay(seconds, function()
		if token ~= stunToken then
			return
		end
		stunToken = 0
		if humanoid.Parent and humanoid.Health > 0 then
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

function Bat.Init(context: any)
	ctx = context
	local sound = Instance.new("Sound")
	sound.Name = "BatSwing"
	sound.SoundId = SWING_SOUND
	sound.Volume = 0.6
	sound.Parent = SoundService
	swingSound = sound
	local backpack = player:WaitForChild("Backpack", 10)
	if backpack then
		watchContainer(backpack)
	end
	local function onCharacter(character: Model)
		stunToken = 0
		watchContainer(character)
		local newBackpack = player:FindFirstChildOfClass("Backpack")
		if newBackpack and newBackpack ~= backpack then
			backpack = newBackpack
			watchContainer(newBackpack)
		end
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

return Bat
