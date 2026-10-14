-- Carrying things home: tamed animals walk behind you, eggs are held above your head and
-- stolen animals are led on a glowing bind. Delivering happens automatically when you
-- enter your own base. Carried models are welded to the character so they move smoothly.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Game = require(Shared.Config.Game)

local CarryService = {}

local S
local carrying = {} -- [player] = item
local carriedFolder
local lastPos = {} -- [player] = last checked position (anti-teleport)

function CarryService.Init(services)
	S = services
	carriedFolder = Instance.new("Folder")
	carriedFolder.Name = "Carried"
	carriedFolder.Parent = Workspace
end

function CarryService.get(player: Player)
	return carrying[player]
end

function CarryService.isCarrying(player: Player): boolean
	return carrying[player] ~= nil
end

function CarryService.speedFactor(player: Player): number
	local item = carrying[player]
	if not item then
		return 1
	end
	if item.Kind == "Stolen" then
		return Game.StealCarrySpeedFactor
	end
	return Game.CarrySpeedFactor
end

local function weldTo(model: Model, hrp: BasePart, cf: CFrame)
	model:PivotTo(cf)
	local root = model.PrimaryPart
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			if p ~= root then
				local w = Instance.new("WeldConstraint")
				w.Part0 = root
				w.Part1 = p
				w.Parent = p
			end
		end
	end
	local w = Instance.new("WeldConstraint")
	w.Name = "CarryWeld"
	w.Part0 = hrp
	w.Part1 = root
	w.Parent = root
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
		end
	end
end

local function groundOffset(character: Model, hrp: BasePart): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hip = humanoid and humanoid.HipHeight or 2
	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R6 then
		hip = 2
	end
	return hrp.Size.Y / 2 + hip
end

local function attach(player: Player, item): boolean
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end
	local model = item.Model
	local ground = groundOffset(character, hrp :: BasePart)
	-- if the player rides a mount, the character stands higher
	local mountHeight = player:GetAttribute("MountHeight") or 0
	if item.Kind == "Egg" then
		-- held up high like a glowing lantern
		local cf = hrp.CFrame * CFrame.new(0, 2.8, 0)
		weldTo(model, hrp :: BasePart, cf)
		local light = Instance.new("PointLight")
		light.Range = 14
		light.Brightness = 3
		light.Color = item.GlowColor or Color3.fromRGB(255, 220, 160)
		light.Parent = model.PrimaryPart
		local attachment = Instance.new("Attachment")
		attachment.Position = Vector3.new(0, 1.5, 0)
		attachment.Parent = model.PrimaryPart
		local rays = Instance.new("ParticleEmitter")
		rays.Name = "Rays"
		rays.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		rays.Color = ColorSequence.new(item.GlowColor or Color3.fromRGB(255, 230, 170))
		rays.LightEmission = 1
		rays.Size = NumberSequence.new(1.2, 0)
		rays.Lifetime = NumberRange.new(0.5, 0.9)
		rays.Rate = 25
		rays.Speed = NumberRange.new(4, 7)
		rays.SpreadAngle = Vector2.new(180, 180)
		rays.Parent = attachment
	else
		local size = model:GetExtentsSize()
		local back = 2 + size.Z / 2
		-- HipHeight already includes the mount, so `ground` reaches the floor either way
		local cf = hrp.CFrame * CFrame.new(0, -ground, back + (mountHeight > 0 and 4 or 0))
		weldTo(model, hrp :: BasePart, cf)
		if item.Kind == "Stolen" then
			-- glowing bind between thief and animal
			local a0 = Instance.new("Attachment")
			a0.Parent = hrp
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, size.Y * 0.5, -size.Z * 0.4)
			a1.Parent = model.PrimaryPart
			local beam = Instance.new("Beam")
			beam.Name = "Bind"
			beam.Attachment0 = a0
			beam.Attachment1 = a1
			beam.Color = ColorSequence.new(Color3.fromRGB(255, 60, 90))
			beam.LightEmission = 1
			beam.Width0 = 0.4
			beam.Width1 = 0.4
			beam.FaceCamera = true
			beam.Parent = model.PrimaryPart
			item.BindAttachment = a0
		end
	end
	model.Parent = carriedFolder
	return true
end

-- item = { Kind, Model, DisplayName, OnDeliver(player) -> boolean, OnDrop(player, reason) }
function CarryService.start(player: Player, item): boolean
	if carrying[player] then
		return false
	end
	if not attach(player, item) then
		item.Model:Destroy()
		return false
	end
	item.StartedAt = os.clock()
	carrying[player] = item
	player:SetAttribute("Carrying", item.Kind)
	S.PlayerService.markState(player)
	return true
end

local function cleanup(player: Player, item)
	carrying[player] = nil
	if item.BindAttachment then
		item.BindAttachment:Destroy()
	end
	if item.Model then
		item.Model:Destroy()
	end
	if player.Parent then
		player:SetAttribute("Carrying", nil)
		S.PlayerService.markState(player)
	end
end

-- Ends carrying without delivering. reason: "dropped", "caught", "died", "left", "stopped", "timeout"
function CarryService.drop(player: Player, reason: string)
	local item = carrying[player]
	if not item then
		return
	end
	cleanup(player, item)
	if item.OnDrop then
		local ok, err = pcall(item.OnDrop, player, reason)
		if not ok then
			warn("[CarryService] OnDrop error", err)
		end
	end
end

-- Call right before teleporting a player who may be carrying something (portals).
function CarryService.noteTeleport(player: Player)
	lastPos[player] = nil
end

-- Notifies at most every few seconds (delivery attempts run 5 times a second).
function CarryService.failNotify(player: Player, item, text: string)
	local now = os.clock()
	if not item.LastFail or now - item.LastFail > 4 then
		item.LastFail = now
		S.PlayerService.notify(player, text, "error")
	end
end

-- Finishes carrying successfully (called when delivered).
function CarryService.finish(player: Player)
	local item = carrying[player]
	if item then
		cleanup(player, item)
	end
end

function CarryService.Start()
	local function hookCharacter(player: Player, character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.Died:Connect(function()
				CarryService.drop(player, "died")
			end)
		end
		character.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				CarryService.drop(player, "died")
			end
		end)
	end
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			hookCharacter(player, character)
		end)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			hookCharacter(player, player.Character)
		end
		player.CharacterAdded:Connect(function(character)
			hookCharacter(player, character)
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		CarryService.drop(player, "left")
	end)

	S.Router.register("Drop", function(player)
		if not carrying[player] then
			return false, "You are not carrying anything"
		end
		CarryService.drop(player, "dropped")
		return true
	end)

	-- delivery + simple anti-teleport check
	task.spawn(function()
		while true do
			task.wait(0.2)
			for player, item in pairs(carrying) do
				local character = player.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				if hrp then
					local pos = hrp.Position
					local prev = lastPos[player]
					lastPos[player] = pos
					if prev and (pos - prev).Magnitude > (Game.MaxWalkSpeed * 0.2 * 2.5 + 20) then
						CarryService.drop(player, "dropped")
						S.PlayerService.notify(player, "You moved too fast and dropped it!", "error")
					elseif S.PlotService.isInside(player, pos) and item.OnDeliver then
						local ok, delivered = pcall(item.OnDeliver, player)
						if not ok then
							warn("[CarryService] OnDeliver error", delivered)
						elseif delivered then
							CarryService.finish(player)
						end
					end
				end
			end
			for player in pairs(lastPos) do
				if not carrying[player] then
					lastPos[player] = nil
				end
			end
		end
	end)
end

return CarryService
