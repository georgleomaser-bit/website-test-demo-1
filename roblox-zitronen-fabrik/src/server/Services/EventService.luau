--[[
	Server-Events alle paar Minuten: Turbo-Zeit, Geldregen, Zitronen-Regen.
	Der aktuelle Event steht als Attribute am Workspace (für die Anzeige).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local Core = require(script.Parent.Core)
local Build = require(script.Parent.Parent.World.Build)

local EventService = {}

local pickupsFolder: Folder
local lobbyCenter = Vector3.new(0, 1, 0)
local active: any = nil
local lastId: string? = nil
local rng = Random.new()

local function recomputeAll()
	for _, session in pairs(Core.Sessions) do
		if session.Loaded then
			Core.RecomputeStats(session)
		end
	end
end

local function spawnPickup(position: Vector3)
	local part = Build.Egg(pickupsFolder, "GoldenLemon", Vector3.new(2.4, 1.8, 1.8), CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), Color3.fromRGB(255, 215, 0), Enum.Material.Neon)
	part.CanCollide = false
	part.CanQuery = false
	Build.Sparkles(part, Color3.fromRGB(255, 230, 90), 6)
	local taken = false
	part.Touched:Connect(function(hit: BasePart)
		if taken then
			return
		end
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		local session = player and Core.Get(player)
		if not session or not session.Loaded then
			return
		end
		taken = true
		local stats = session.Stats or Economy.ComputeStats(session.Profile, Core.Context(session))
		local amount = math.max(Config.Events.PickupMin, stats.TotalIncome * Config.Events.PickupSeconds)
		Core.AddEarnings(session, amount)
		session.Profile.Stats.Pickups += 1
		Core.Effect(session.Player, "Pickup", { Amount = amount, Position = part.Position })
		part:Destroy()
	end)
end

local function spawnPickups()
	-- In jeder bewohnten Fabrik ein paar goldene Zitronen …
	local plots = workspace:FindFirstChild("World") and workspace.World:FindFirstChild("Plots")
	if plots then
		for _, plot in ipairs(plots:GetChildren()) do
			if plot:GetAttribute("OwnerId") ~= 0 then
				local origin = plot:GetAttribute("Origin") :: CFrame
				for _ = 1, Config.Events.PickupsPerPlot do
					-- zwischen den Linien (auf den Gehwegen)
					local lane = rng:NextInteger(1, #Config.Lanes)
					local x = Config.LaneX(lane) + (rng:NextNumber() < 0.5 and -12.5 or 12.5)
					local z = rng:NextNumber(-60, 75)
					spawnPickup((origin * CFrame.new(x, 2.5, z)).Position)
				end
			end
		end
	end
	-- … und auf dem Platz
	for _ = 1, Config.Events.PickupsLobby do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(30, Config.Layout.PlazaRadius - 20)
		spawnPickup(lobbyCenter + Vector3.new(math.cos(a) * r, 2.5, math.sin(a) * r))
	end
end

function EventService.Stop()
	if not active then
		return
	end
	active = nil
	Core.EventIncome = 1
	Core.EventSpeed = 1
	workspace:SetAttribute("EventId", "")
	workspace:SetAttribute("EventEnds", 0)
	pickupsFolder:ClearAllChildren()
	recomputeAll()
	Core.NotifyAll("Das Event ist vorbei. Bis zum nächsten Mal! 👋", "info")
end

function EventService.Begin(id: string?)
	if active then
		EventService.Stop()
	end
	local list = Config.Events.List
	local event = list[1]
	local found = false
	if id then
		for _, e in ipairs(list) do
			if e.Id == id then
				event = e
				found = true
			end
		end
	end
	if not found then
		for _ = 1, 10 do
			event = list[rng:NextInteger(1, #list)]
			if event.Id ~= lastId then
				break
			end
		end
	end
	lastId = event.Id
	active = event
	local ends = workspace:GetServerTimeNow() + event.Duration
	workspace:SetAttribute("EventId", event.Id)
	workspace:SetAttribute("EventName", event.Name)
	workspace:SetAttribute("EventEmoji", event.Emoji)
	workspace:SetAttribute("EventDescription", event.Description)
	workspace:SetAttribute("EventEnds", ends)
	Core.EventIncome = event.Income or 1
	Core.EventSpeed = event.Speed or 1
	recomputeAll()
	if event.Pickups then
		spawnPickups()
	end
	Core.NotifyAll(event.Emoji .. " " .. event.Name .. "! " .. event.Description, "event")
	Core.EffectAll("Event", { Id = event.Id, Name = event.Name, Emoji = event.Emoji })

	local thisEvent = event
	task.delay(event.Duration, function()
		if active == thisEvent then
			EventService.Stop()
		end
	end)
end

function EventService.Init(world: Instance)
	local folder = world:FindFirstChild("Pickups")
	if not folder then
		local created = Instance.new("Folder")
		created.Name = "Pickups"
		created.Parent = world
		folder = created
	end
	pickupsFolder = folder :: Folder
	workspace:SetAttribute("EventId", "")
	workspace:SetAttribute("EventEnds", 0)
end

function EventService.Start()
	task.spawn(function()
		while true do
			task.wait(rng:NextNumber(Config.Events.MinInterval, Config.Events.MaxInterval))
			if #Players:GetPlayers() > 0 and not active then
				Core.NotifyAll("⏰ In 10 Sekunden startet ein Event!", "event")
				task.wait(10)
				if not active then
					EventService.Begin(nil)
				end
			end
		end
	end)
end

EventService.Format = Format

return EventService
