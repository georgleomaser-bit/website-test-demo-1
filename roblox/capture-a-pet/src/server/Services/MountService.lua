-- Riding: pick any of your animals as a mount. It carries you around faster depending on
-- its rarity and wild aura, and its aura glows around you while you ride.

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Formulas = require(Shared.Formulas)
local Animals = require(Shared.Config.Animals)
local AnimalModel = require(Shared.AnimalModel)

local MountService = {}

local S
local mounts = {} -- [player] = { Model, Uid, OriginalHip }
local mountFolder
local MAX_RIDE_HEIGHT = 6

function MountService.Init(services)
	S = services
	mountFolder = Instance.new("Folder")
	mountFolder.Name = "Mounts"
	mountFolder.Parent = Workspace
end

function MountService.speedMult(player: Player): number
	local data = S.DataService.get(player)
	if not data or data.Mount == "" or not mounts[player] then
		return 1
	end
	local record = S.PlayerService.findAnimal(player, data.Mount)
	if not record then
		return 1
	end
	return Formulas.mountMult(record)
end

local function detach(player: Player)
	local m = mounts[player]
	if not m then
		return
	end
	mounts[player] = nil
	if m.Model then
		m.Model:Destroy()
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and m.OriginalHip and m.Humanoid == humanoid then
		humanoid.HipHeight = m.OriginalHip
	end
	if player.Parent then
		player:SetAttribute("MountHeight", nil)
		player:SetAttribute("Mounted", nil)
	end
end

local function attach(player: Player)
	detach(player)
	local data = S.DataService.get(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not data or data.Mount == "" or not humanoid or not hrp then
		return
	end
	local record = S.PlayerService.findAnimal(player, data.Mount)
	if not record or not Animals.ById[record.Species] then
		data.Mount = ""
		return
	end
	-- carrying something while mounting would mess up the weld offsets
	if S.CarryService.isCarrying(player) then
		S.CarryService.drop(player, "dropped")
	end
	local model = AnimalModel.build(record.Species, { Mutation = record.Mutation, Aura = record.Aura })
	local body = model:FindFirstChild("Body")
	local rideHeight = body and (body.Position.Y + body.Size.Y / 2) or model:GetExtentsSize().Y * 0.6
	if rideHeight > MAX_RIDE_HEIGHT then
		model:ScaleTo(model:GetScale() * MAX_RIDE_HEIGHT / rideHeight)
		rideHeight = MAX_RIDE_HEIGHT
	end
	local hip = humanoid.HipHeight
	-- the character will rise by rideHeight once HipHeight changes, so the animal is welded
	-- that much lower; after the rise its feet touch the ground
	local ground = hrp.Size.Y / 2 + hip + rideHeight
	model:PivotTo(hrp.CFrame * CFrame.new(0, -ground, 0.5))
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
	-- lift the character onto the animal's back, then weld so the animal stays on the ground
	humanoid.HipHeight = hip + rideHeight
	model:PivotTo(hrp.CFrame * CFrame.new(0, -ground, 0.5))
	local w = Instance.new("WeldConstraint")
	w.Part0 = hrp
	w.Part1 = root
	w.Parent = root
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
		end
	end
	model.Parent = mountFolder
	mounts[player] = { Model = model, Uid = record.Uid, OriginalHip = hip, Humanoid = humanoid }
	player:SetAttribute("MountHeight", rideHeight)
	player:SetAttribute("Mounted", true)
end

function MountService.mount(player: Player, uid: string): (boolean, string?)
	local data = S.DataService.get(player)
	local rt = S.PlayerService.get(player)
	local record = S.PlayerService.findAnimal(player, uid)
	if not record then
		return false, "Animal not found"
	end
	if rt.InTransit[uid] then
		return false, "This animal is being stolen!"
	end
	data.Mount = uid
	attach(player)
	S.PlotService.refresh(player)
	S.PlayerService.markState(player)
	return true, "Riding " .. record.Species .. " (x" .. string.format("%.2f", Formulas.mountMult(record)) .. " speed)"
end

function MountService.dismount(player: Player)
	local data = S.DataService.get(player)
	if data then
		data.Mount = ""
	end
	detach(player)
	if S.PlotService.plot(player) then
		S.PlotService.refresh(player)
	end
	S.PlayerService.markState(player)
end

function MountService.Start()
	S.DataService.onLoaded(function(player)
		player.CharacterAdded:Connect(function(character)
			mounts[player] = nil
			character:WaitForChild("HumanoidRootPart", 10)
			character:WaitForChild("Humanoid", 10)
			task.wait(0.5)
			if player.Parent and player.Character == character then
				attach(player)
			end
		end)
		if player.Character then
			task.delay(1, attach, player)
		end
	end)
	S.DataService.onReleasing(function(player)
		detach(player)
	end)
	S.Router.register("Mount", function(player, uid)
		if uid == nil or uid == "" then
			MountService.dismount(player)
			return true, "Dismounted"
		end
		if type(uid) ~= "string" then
			return false
		end
		return MountService.mount(player, uid)
	end)
end

return MountService
