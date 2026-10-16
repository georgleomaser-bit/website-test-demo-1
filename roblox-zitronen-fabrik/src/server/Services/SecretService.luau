--[[
	Lobby & Geheimnisse:
	- Zorp der Alien (öffnet Rebirth-Menü, nimmt den UFO-Schlüssel)
	- Evolution-Portal
	- Goldene Zitrone oben auf dem Obby-Baum (1× pro Tag)
	- Kanalisation mit Hebel-Rätsel → Tresor → UFO-Schlüssel
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local Core = require(script.Parent.Core)
local NPC = require(script.Parent.Parent.World.NPC)
local Build = require(script.Parent.Parent.World.Build)

local SecretService = {}

local world: Instance
local leverOrder: { string } = {}
local zorpModel: Model? = nil

local LEVER_RGB = {
	Rot = Color3.fromRGB(255, 40, 40),
	Blau = Color3.fromRGB(40, 90, 255),
	["Grün"] = Color3.fromRGB(40, 220, 60),
	Gelb = Color3.fromRGB(255, 230, 40),
}

local function sessionFor(player: Player)
	local session = Core.Get(player)
	if session and session.Loaded then
		return session
	end
	return nil
end

local function teleport(player: Player, cf: CFrame)
	local character = player.Character
	if character and character:FindFirstChild("HumanoidRootPart") then
		character:PivotTo(cf)
	end
end

--------------------------------------------------------------------------
-- Zorp & Portal
--------------------------------------------------------------------------
local function onZorp(player: Player)
	local session = sessionFor(player)
	if not session then
		return
	end
	local secrets = session.Profile.Secrets
	if secrets.UfoKey and not secrets.UfoKeyDelivered then
		secrets.UfoKeyDelivered = true
		Core.RecomputeStats(session)
		Core.Notify(player, "Zorp: \"MEIN UFO-SCHLÜSSEL! Danke, Erdling! Deine Investoren sind ab jetzt 50 % stärker!\" 🛸", "gold")
		Core.Effect(player, "UfoKey")
		Core.NotifyAll("👽 " .. player.DisplayName .. " hat Zorps UFO-Schlüssel gefunden!", "gold")
		if zorpModel then
			NPC.PlayOnce(zorpModel, "cheer")
		end
	elseif zorpModel then
		NPC.PlayOnce(zorpModel, "wave")
	end
	Core.Effect(player, "OpenWindow", "Rebirth")
end

local function onPortal(player: Player)
	if sessionFor(player) then
		Core.Effect(player, "OpenWindow", "Evolution")
	end
end

--------------------------------------------------------------------------
-- Obby: goldene Zitrone
--------------------------------------------------------------------------
local function onGoldenLemon(player: Player)
	local session = sessionFor(player)
	if not session then
		return
	end
	local profile = session.Profile
	local now = os.time()
	local waitLeft = profile.ObbyLast + Config.Secrets.ObbyCooldown - now
	if waitLeft > 0 then
		Core.Notify(player, "Die goldene Zitrone wächst noch nach… wieder da in " .. Format.Time(waitLeft) .. " ⏳", "info")
		return
	end
	local stats = session.Stats or Economy.ComputeStats(profile, Core.Context(session))
	local amount = Economy.IncomeReward(stats, Config.Secrets.ObbyRewardMinutes, Config.Secrets.ObbyRewardMin)
	profile.ObbyLast = now
	Core.AddEarnings(session, amount)
	Core.MarkDirty(session)
	Core.Notify(player, "🍋✨ GOLDENE ZITRONE! +" .. Format.Cash(amount), "gold")
	Core.Effect(player, "Reward", { Amount = amount, Title = "Goldene Zitrone!" })
end

--------------------------------------------------------------------------
-- Kanalisation
--------------------------------------------------------------------------
local function arrivalCFrame(): CFrame?
	local sewer = world:FindFirstChild("Sewer")
	local start = sewer and sewer:FindFirstChild("Start")
	local arrival = start and start:FindFirstChild("Arrival") :: BasePart?
	return arrival and (arrival.CFrame + Vector3.new(0, 3, 0)) or nil
end

local function manholeExitCFrame(): CFrame?
	local lobby = world:FindFirstChild("Lobby")
	local manhole = lobby and lobby:FindFirstChild("Manhole")
	local cover = manhole and manhole:FindFirstChild("Cover") :: BasePart?
	return cover and (cover.CFrame * CFrame.new(0, 4, 6)) or nil
end

local function onLever(player: Player, color: string)
	local session = sessionFor(player)
	if not session then
		return
	end
	if session.SewerSolved then
		Core.Notify(player, "Der Tresor ist schon offen! 🔓", "info")
		return
	end
	local progress = session.SewerProgress
	table.insert(progress, color)
	local index = #progress
	if leverOrder[index] ~= color then
		table.clear(progress)
		Core.Effect(player, "Lever", { Color = color, Correct = false })
		Core.Notify(player, "*KLONK* Falsche Reihenfolge… alle Hebel springen zurück.", "error")
		return
	end
	Core.Effect(player, "Lever", { Color = color, Correct = true, Step = index })
	if index >= #leverOrder then
		session.SewerSolved = true
		table.clear(progress)
		Core.Effect(player, "VaultOpen")
		Core.Notify(player, "🔓 Irgendwo hat sich eine schwere Tür geöffnet…", "gold")
	end
end

local function onKey(player: Player)
	local session = sessionFor(player)
	if not session then
		return
	end
	local secrets = session.Profile.Secrets
	if secrets.UfoKey or secrets.UfoKeyDelivered then
		Core.Notify(player, "Du hast den UFO-Schlüssel schon gefunden! 🛸", "info")
		return
	end
	if not session.SewerSolved then
		Core.Notify(player, "Der Tresor ist verschlossen. 🔒", "error")
		return
	end
	secrets.UfoKey = true
	Core.MarkDirty(session)
	Core.Effect(player, "Reward", { Amount = 0, Title = "UFO-Schlüssel gefunden!" })
	Core.Notify(player, "🛸 Du hast einen UFO-Schlüssel gefunden! Bring ihn zu Zorp dem Alien auf dem Platz!", "gold")
end

local function shuffle(list: { string }): { string }
	local copy = table.clone(list)
	local rng = Random.new()
	for i = #copy, 2, -1 do
		local j = rng:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

--------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------
local function connectPrompt(parent: Instance?, name: string, handler: (Player) -> ())
	if not parent then
		return
	end
	local prompt = parent:FindFirstChild(name, true)
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Triggered:Connect(handler)
	else
		warn("[ZitronenFabrik] Prompt fehlt: " .. name)
	end
end

function SecretService.Init(worldRoot: Instance)
	world = worldRoot
	local lobby = world:WaitForChild("Lobby")
	local sewer = world:WaitForChild("Sewer")

	connectPrompt(lobby:FindFirstChild("Zorp"), "ZorpPrompt", onZorp)
	connectPrompt(lobby:FindFirstChild("Portal"), "PortalPrompt", onPortal)
	connectPrompt(lobby:FindFirstChild("ObbyTree"), "GoldenPrompt", onGoldenLemon)
	connectPrompt(lobby:FindFirstChild("Manhole"), "ManholePrompt", function(player)
		local cf = arrivalCFrame()
		if cf and sessionFor(player) then
			teleport(player, cf)
			Core.Notify(player, "🕳️ Willkommen in der Kanalisation… Die Ratten flüstern eine Farbfolge.", "info")
		end
	end)
	connectPrompt(sewer, "ExitPrompt", function(player)
		local cf = manholeExitCFrame()
		if cf then
			teleport(player, cf)
		end
	end)
	connectPrompt(sewer, "KeyPrompt", onKey)

	-- Hebel-Reihenfolge für diesen Server würfeln und aufs Wandbild malen
	leverOrder = shuffle(Config.Secrets.LeverColors)
	local mural = sewer:FindFirstChild("Mural")
	local gui = mural and mural:FindFirstChild("MuralGui")
	if gui then
		for k, colorName in ipairs(leverOrder) do
			local square = gui:FindFirstChild("Color" .. k) :: Frame?
			if square then
				square.BackgroundColor3 = LEVER_RGB[colorName] or Color3.new(1, 1, 1)
			end
		end
	end
	local levers = sewer:FindFirstChild("Levers")
	if levers then
		for _, lever in ipairs(levers:GetChildren()) do
			local color = lever:GetAttribute("Color")
			local prompt = lever:FindFirstChild("LeverPrompt", true)
			if prompt and prompt:IsA("ProximityPrompt") and type(color) == "string" then
				prompt.Triggered:Connect(function(player)
					onLever(player, color)
				end)
			end
		end
	end

	-- Zorp der Alien
	local spot = lobby:FindFirstChild("Zorp") and lobby.Zorp:FindFirstChild("ZorpSpot") :: BasePart?
	if spot then
		local center = Vector3.new(0, spot.Position.Y, 0)
		local groundCF = CFrame.lookAt(spot.Position - Vector3.new(0, 0.5, 0), center - Vector3.new(0, 0.5, 0))
		task.spawn(function()
			zorpModel = NPC.Create(lobby.Zorp, "Zorp", {
				CFrame = groundCF,
				Skin = Color3.fromRGB(110, 220, 90),
				Shirt = Color3.fromRGB(120, 60, 200),
				Pants = Color3.fromRGB(60, 30, 110),
				Hat = "Alien",
				Title = "🛸 Rebirth & Alien-Investoren",
				NameColor = Color3.fromRGB(140, 255, 120),
			})
		end)
	end
end

SecretService.Build = Build

return SecretService
