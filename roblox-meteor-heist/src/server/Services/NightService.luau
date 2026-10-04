-- NACHT: Tag-Nacht-Zyklus (Config.Night) mit Blutmond, Sternschnuppen-Eiern und leuchtenden Kisten.
--   • Nach Config.Night.DayLength Sekunden Tag kommt Config.Night.NightLength Sekunden Nacht.
--   • Licht/Himmel blendet GraphicsService.SetNight weich um.
--   • Nachts: Nacht-Eier in den Nestern (MeteorService.RandomOfRarity), Sternschnuppen-Eier fallen
--     aufs Nester-Feld (MeteorService.SpawnSkyEgg), mehr Kreaturen (FieldService), leuchtende Kisten.
--   • Kiste öffnen (E halten, serverseitig geprüft): Geld oder 1 Glücksrad-Dreh.
--   • BLUTMOND (Chance Config.Night.BloodMoonChance): roter Himmel, Glück x BloodMoonLuck
--     (MeteorService.GetLuck), dazu das Blutmond-Ei (BloodMoonOnly).
-- Attribute an ReplicatedStorage (für den Client): IsNight, BloodMoon, NightUntil, NextNightAt.
--
-- ÖFFENTLICHE API (auch über MeteorService.StartNight / MeteorService.EndNight erreichbar):
--   NightService.StartNight(bloodMoon: boolean?, seconds: number?)  -- Nacht sofort (läuft eine: verlängern)
--   NightService.EndNight()                                         -- sofort Tag
--   NightService.IsNight(): boolean, NightService.IsBloodMoon(): boolean

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local MeteorFactory = require(script.Parent:WaitForChild("MeteorFactory"))

local NightService = {}
local Services

local NIGHT = Config.Night or {}
local DAY_LENGTH = tonumber(NIGHT.DayLength) or 600
local NIGHT_LENGTH = tonumber(NIGHT.NightLength) or 180
local FADE_TIME = tonumber(NIGHT.FadeTime) or 10

local CRATE_SIZE = Vector3.new(3, 2.6, 3)
local CRATE_COLOR = Color3.fromRGB(150, 100, 55)
local CRATE_GLOW = Color3.fromRGB(255, 215, 90)
local CRATE_GLOW_BLOOD = Color3.fromRGB(255, 70, 70)
local CRATE_REACH = 10 -- Prompt-Reichweite
local CRATE_REACH_EXTRA = 5 -- Spielraum beim Server (Ping)

local rng = Random.new()
local isNight = false
local bloodMoon = false
local nightUntil = 0
local nextNightAt = 0
local nextStarAt = 0
local nextCrateAt = 0
local crateFolder: Folder? = nil
type Crate = { Model: Model, Box: BasePart, Expires: number, Claimed: boolean }
local crates: { Crate } = {}
local openLimiter = Util.RateLimiter(3, 1)

local function now(): number
	return workspace:GetServerTimeNow()
end

local function publish()
	ReplicatedStorage:SetAttribute("IsNight", isNight)
	ReplicatedStorage:SetAttribute("BloodMoon", bloodMoon)
	ReplicatedStorage:SetAttribute("NightUntil", nightUntil)
	ReplicatedStorage:SetAttribute("NextNightAt", nextNightAt)
end

function NightService.IsNight(): boolean
	return isNight
end

function NightService.IsBloodMoon(): boolean
	return isNight and bloodMoon
end

-- -------------------------------------------------------------------
-- LEUCHTENDE KISTEN
-- -------------------------------------------------------------------
local function removeCrate(crate: Crate)
	local index = table.find(crates, crate)
	if index then
		table.remove(crates, index)
	end
	crate.Model:Destroy()
end

local function clearCrates()
	for i = #crates, 1, -1 do
		removeCrate(crates[i])
	end
end

local function aliveRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return root
end

-- Kiste öffnen: alles serverseitig geprüft (Nacht, Reichweite, lebendig, nicht eingefroren, Spam)
local function openCrate(player: Player, crate: Crate)
	if crate.Claimed or not crate.Model.Parent or not openLimiter.Check(player) then
		return
	end
	local Economy = Services.EconomyService
	if not Economy.IsReady(player) then
		return
	end
	local root = aliveRoot(player)
	if not root or root.Anchored then
		return
	end
	if (root.Position - crate.Box.Position).Magnitude > CRATE_REACH + CRATE_REACH_EXTRA then
		Economy.Notify(player, "Zu weit weg!", "Error")
		return
	end
	-- Position kommt vom Client: wer gerade unmöglich weit "gesprungen" ist (Teleport-Exploit), öffnet nichts
	local carry = Services.CarryService
	if carry and carry.MoveStatus(player) ~= "ok" then
		Economy.Notify(player, "⏳ Kurz warten und nochmal versuchen!", "Error")
		return
	end
	crate.Claimed = true
	local position = crate.Box.Position
	removeCrate(crate)

	local gotSpin = false
	if rng:NextNumber() < (tonumber(NIGHT.CrateSpinChance) or 0.25) and Services.RewardService then
		gotSpin = Services.RewardService.AddSpins(player, 1)
	end
	if gotSpin then
		Economy.Notify(player, "📦 Kiste: 1 Glücksrad-Dreh!", "Success")
	else
		local seconds = tonumber(NIGHT.CrateCashSeconds) or 120
		local amount = math.floor(math.max(tonumber(NIGHT.CrateCashMin) or 1000, Economy.GetIncome(player) * seconds))
		Economy.AddCash(player, amount)
		Economy.Effect(player, "Collect", amount)
		Economy.Notify(player, "📦 Kiste: +" .. Util.FormatCash(amount), "Success")
	end
	Remotes.Effect:FireAllClients("NightCrate", 0, { Position = position, Spin = gotSpin })
end

local function spawnCrate()
	if not crateFolder or #crates >= (tonumber(NIGHT.MaxCrates) or 6) then
		return
	end
	local spot = Services.MeteorService.FindMeadowSpot(CRATE_SIZE.X)
	if not spot then
		return
	end
	local glow = if bloodMoon then CRATE_GLOW_BLOOD else CRATE_GLOW
	local model = Instance.new("Model")
	model.Name = "NightCrate"
	local box = Instance.new("Part")
	box.Name = "Box"
	box.Size = CRATE_SIZE
	box.CFrame = CFrame.new(spot + Vector3.new(0, CRATE_SIZE.Y / 2, 0))
		* CFrame.Angles(0, rng:NextNumber() * math.pi, 0)
	box.Material = Enum.Material.WoodPlanks
	box.Color = CRATE_COLOR
	box.Anchored = true
	box.CanCollide = false
	box.CanTouch = false
	box.Parent = model
	-- leuchtendes Band um den Deckel
	local band = Instance.new("Part")
	band.Name = "Glow"
	band.Size = Vector3.new(CRATE_SIZE.X + 0.2, 0.5, CRATE_SIZE.Z + 0.2)
	band.CFrame = box.CFrame * CFrame.new(0, CRATE_SIZE.Y / 2 - 0.5, 0)
	band.Material = Enum.Material.Neon
	band.Color = glow
	band.Anchored = true
	band.CanCollide = false
	band.CanQuery = false
	band.CanTouch = false
	band.CastShadow = false
	band.Parent = model
	local light = Instance.new("PointLight")
	light.Color = glow
	light.Range = 14
	light.Brightness = 2
	light.Shadows = false
	light.Parent = band
	model.PrimaryPart = box
	model:SetAttribute("NightCrate", true)

	local crate: Crate = {
		Model = model,
		Box = box,
		Expires = os.clock() + (tonumber(NIGHT.CrateLifetime) or 60),
		Claimed = false,
	}
	local prompt = MeteorFactory.AddPrompt(
		box,
		"CratePrompt",
		"Öffnen",
		"Leuchtende Kiste",
		tonumber(NIGHT.CrateHold) or 0.6,
		Enum.KeyCode.E,
		CRATE_REACH
	)
	prompt:SetAttribute("ClientMaxDistance", CRATE_REACH)
	MeteorFactory.OnHeldTrigger(prompt, function(player)
		openCrate(player, crate)
	end)
	table.insert(crates, crate)
	model.Parent = crateFolder
end

-- -------------------------------------------------------------------
-- NACHT STARTEN / BEENDEN
-- -------------------------------------------------------------------
-- Zahl für Texte: 2 -> "2", 1.5 -> "1.5"
local function multText(value: any): string
	local n = tonumber(value) or 2
	return if n == math.floor(n) then tostring(n) else string.format("%.1f", n)
end

function NightService.StartNight(blood: boolean?, seconds: number?)
	local t = now()
	local length = math.clamp(tonumber(seconds) or NIGHT_LENGTH, 10, 3600)
	local wasNight = isNight
	local wasBlood = bloodMoon
	isNight = true
	bloodMoon = blood == true or (wasNight and bloodMoon)
	nightUntil = math.max(if wasNight then nightUntil else 0, t + length)
	nextNightAt = nightUntil + DAY_LENGTH
	if not wasNight then
		nextStarAt = t + 3
		nextCrateAt = t + 4
	end
	publish()
	Services.GraphicsService.SetNight(true, bloodMoon, FADE_TIME)
	local Economy = Services.EconomyService
	if bloodMoon and not wasBlood then
		Economy.NotifyAll("🔴 BLUTMOND! " .. multText(NIGHT.BloodMoonLuck) .. "x Glück bis zum Morgen.", "Event")
	elseif not wasNight then
		Economy.NotifyAll("🌙 Nacht: Sternschnuppen, Kisten – und mehr Monster!", "Event")
	end
end

function NightService.EndNight()
	if not isNight then
		return
	end
	local t = now()
	isNight = false
	bloodMoon = false
	nightUntil = t
	nextNightAt = t + DAY_LENGTH
	clearCrates()
	publish()
	Services.GraphicsService.SetNight(false, false, FADE_TIME)
	Services.EconomyService.NotifyAll("☀️ Die Sonne geht auf.", "Info")
end

-- Jede Sekunde: Zyklus, Sternschnuppen, Kisten
local function step()
	local t = now()
	if not isNight then
		if t >= nextNightAt then
			if #Players:GetPlayers() == 0 then
				nextNightAt = t + 30 -- niemand da: Nacht verschieben
				publish()
			else
				NightService.StartNight(rng:NextNumber() < (tonumber(NIGHT.BloodMoonChance) or 0.2))
			end
		end
		return
	end
	if t >= nightUntil then
		NightService.EndNight()
		return
	end
	-- alte Kisten weg
	local clock = os.clock()
	for i = #crates, 1, -1 do
		local crate = crates[i]
		if not crate.Claimed and clock > crate.Expires then
			removeCrate(crate)
		end
	end
	if #Players:GetPlayers() == 0 then
		return
	end
	if t >= nextStarAt then
		local interval = NIGHT.StarInterval or { 5, 9 }
		nextStarAt = t + rng:NextNumber(tonumber(interval[1]) or 5, tonumber(interval[2]) or 9)
		Services.MeteorService.SpawnSkyEgg({
			Luck = tonumber(NIGHT.StarLuck) or 2,
			Lifetime = tonumber(NIGHT.StarLifetime) or 45,
		})
	end
	if t >= nextCrateAt then
		nextCrateAt = t + (tonumber(NIGHT.CrateInterval) or 12)
		spawnCrate()
	end
end

function NightService.Init(services)
	Services = services
	local map = Services.PlotService.MapFolder or workspace
	local existing = map:FindFirstChild("NightCrates")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "NightCrates" -- Name wird vom Client gesucht!
	folder.Parent = map
	crateFolder = folder
end

function NightService.Start()
	nextNightAt = now() + DAY_LENGTH
	publish()
	Players.PlayerRemoving:Connect(function(player)
		openLimiter.Clear(player)
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(step)
			if not ok then
				warn("[NightService] Fehler: " .. tostring(err))
			end
		end
	end)
end

return NightService
