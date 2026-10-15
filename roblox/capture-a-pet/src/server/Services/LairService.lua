-- Dragon Lair: a timed event. Every few minutes the lair portal in the hub opens and the
-- lair fills with rare eggs guarded by a dragon. Steal eggs and bring them to your nest!

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Animals = require(Shared.Config.Animals)
local Map = require(Shared.Config.Map)
local AnimalModel = require(Shared.AnimalModel)

local LairService = {}

local S
local rng = Random.new()
local openUntil = 0
local nextOpen = 0
local pads = {} -- [index] = { CFrame, Model, Egg, RespawnAt }
local dragon = nil
local touchDebounce = {}

function LairService.Init(services)
	S = services
end

function LairService.openUntil(): number
	return openUntil
end

function LairService.nextOpen(): number
	return nextOpen
end

function LairService.isOpen(): boolean
	return os.time() < openUntil
end

local function rollEgg()
	local zone = ({ 1, 1, 1, 1, 2, 2, 2, 3, 3, 4 })[rng:NextInteger(1, 10)]
	local luck = S.PlayerService.ServerLuckUntil > os.time() and 2 or 1
	local rarity = Animals.rollEggRarity(Animals.LairEggWeight, luck, rng)
	local def = Animals.pickSpecies(zone, rarity, rng)
	return { Species = def.Id, Rarity = def.Rarity, Zone = zone, Mutation = S.PlayerService.rollMutation(1), Source = "Lair" }
end

local function spawnPadEgg(index: number, egg)
	local pad = pads[index]
	if not pad or pad.Model then
		return
	end
	egg = egg or rollEgg()
	pad.Egg = egg
	pad.Model = S.NestService.placeEgg(egg, pad.CFrame, function(player, model)
		if pad.Model ~= model or not LairService.isOpen() then
			return
		end
		local picked = S.NestService.carryEgg(player, egg, function()
			-- dropped or caught: the egg returns to its pad while the lair is open
			if LairService.isOpen() then
				spawnPadEgg(index, egg)
			end
		end)
		if picked then
			model:Destroy()
			pad.Model = nil
			pad.RespawnAt = os.clock() + Game.LairEggRespawnSeconds
			pad.Egg = nil
		end
	end)
end

local function setPortal(open: boolean)
	local world = S.WorldBuilder.World
	world.LairPortal.Transparency = open and 0.15 or 0.75
	world.LairPortal.Color = open and Color3.fromRGB(255, 90, 30) or Color3.fromRGB(90, 60, 60)
end

function LairService.open(duration: number?)
	local now = os.time()
	openUntil = now + (duration or Game.LairOpenSeconds)
	nextOpen = openUntil + Game.LairEverySeconds
	setPortal(true)
	for index in ipairs(pads) do
		spawnPadEgg(index)
	end
	if not dragon then
		local model = AnimalModel.build("Volcano Dragon", { Aura = 5 })
		local tag = Instance.new("BillboardGui")
		tag.Size = UDim2.fromOffset(200, 40)
		tag.StudsOffsetWorldSpace = Vector3.new(0, (model:GetAttribute("Height") or 12) + 3, 0)
		tag.MaxDistance = 200
		tag.Adornee = model.PrimaryPart
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = "Lair Dragon"
		label.TextColor3 = Color3.fromRGB(255, 120, 60)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2.5
		stroke.Parent = label
		label.Parent = tag
		tag.Parent = model.PrimaryPart
		dragon = S.NestService.addGuard(model, S.WorldBuilder.World.Lair.Center, Game.LairDragonSpeed, {
			AggroRadius = 75,
			Leash = 200,
			CatchDistance = 12,
		})
	end
	S.PlayerService.announce({
		{ { Text = "The Dragon Lair has opened!", Color = "#FF8A3D" } },
		{ { Text = "Steal eggs and bring them back to your nest!" } },
	})
	for _, player in ipairs(Players:GetPlayers()) do
		S.PlayerService.markState(player)
	end
end

function LairService.close()
	openUntil = 0
	setPortal(false)
	for _, pad in ipairs(pads) do
		if pad.Model then
			pad.Model:Destroy()
			pad.Model = nil
		end
		pad.Egg = nil
	end
	if dragon then
		S.NestService.removeGuard(dragon)
		dragon = nil
	end
	-- send everyone in the lair back to the hub
	local lair = S.WorldBuilder.World.Lair
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - lair.Center).Magnitude < lair.Size then
			S.CarryService.noteTeleport(player)
			character:PivotTo(CFrame.new(Map.Hub.Spawn + Vector3.new(rng:NextNumber(-8, 8), 2, rng:NextNumber(-8, 8))))
		end
	end
	S.PlayerService.announce({ { { Text = "The Dragon Lair has closed.", Color = "#FF8A3D" } } })
	for _, player in ipairs(Players:GetPlayers()) do
		S.PlayerService.markState(player)
	end
end

function LairService.Start()
	local world = S.WorldBuilder.World
	for i, cf in ipairs(world.Lair.Pads) do
		pads[i] = { CFrame = cf * CFrame.new(0, 0.1, 0) }
	end
	setPortal(false)
	nextOpen = os.time() + 240

	local function teleport(player: Player, cf: CFrame)
		local now = os.clock()
		if touchDebounce[player] and now - touchDebounce[player] < 2 then
			return
		end
		touchDebounce[player] = now
		S.CarryService.noteTeleport(player)
		player.Character:PivotTo(cf)
	end

	world.LairPortal.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end
		if LairService.isOpen() then
			teleport(player, world.Lair.Spawn)
		else
			local now = os.clock()
			if not touchDebounce[player] or now - touchDebounce[player] > 3 then
				touchDebounce[player] = now
				S.PlayerService.notify(player, "The Dragon Lair is closed. It opens soon!", "info")
			end
		end
	end)
	world.Lair.Exit.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if player then
			teleport(player, CFrame.new(Map.Hub.Spawn + Vector3.new(0, 0, 20)) * CFrame.Angles(0, math.pi, 0))
		end
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.time()
			if openUntil > 0 and now >= openUntil then
				LairService.close()
			elseif openUntil == 0 and now >= nextOpen and #Players:GetPlayers() > 0 then
				LairService.open()
			end
			if LairService.isOpen() then
				for index, pad in ipairs(pads) do
					if not pad.Model and pad.RespawnAt and os.clock() >= pad.RespawnAt then
						pad.RespawnAt = nil
						spawnPadEgg(index)
					end
				end
				world.LairPortalLabel.Text = "DRAGON LAIR\nOPEN " .. (openUntil - now) .. "s"
			else
				local left = math.max(0, nextOpen - now)
				world.LairPortalLabel.Text = string.format("DRAGON LAIR\nopens in %d:%02d", math.floor(left / 60), left % 60)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		touchDebounce[player] = nil
	end)
end

return LairService
