--[[
	Spieler kommen und gehen: Fabrik zuweisen, Spielstand laden, aufbauen,
	Offline-Geld geben – und beim Verlassen speichern und aufräumen.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Core = require(script.Parent.Core)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local ProductionService = require(script.Parent.ProductionService)
local RewardService = require(script.Parent.RewardService)
local MonetizationService = require(script.Parent.MonetizationService)

local PlayerService = {}

local SETTINGS = { Music = true, Sfx = true, OtherItems = true, Guide = true }

local function onCharacter(session, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root then
		return
	end
	humanoid.WalkSpeed = Config.WalkSpeed
	task.wait(0.15)
	if character.Parent and session.Plot then
		PlotService.TeleportHome(session)
	end
end

local function onPlayerAdded(player: Player)
	local session = Core.CreateSession(player)
	Core.CreateLeaderstats(player)
	local plot = PlotService.Assign(session)

	player.CharacterAdded:Connect(function(character)
		onCharacter(session, character)
	end)
	if player.Character then
		task.spawn(onCharacter, session, player.Character)
	end

	local profile, canSave = DataService.Load(player)
	if not player.Parent then
		PlotService.Release(session)
		Core.RemoveSession(player)
		return
	end
	session.Profile = profile
	session.CanSave = canSave

	MonetizationService.LoadPasses(session)
	ProductionService.InitLanes(session)
	-- Erst bauen (setzt die Linien-Attribute zurück), dann Werte schreiben
	PlotService.BuildFromProfile(session)
	Core.RecomputeStats(session)
	PlotService.RefreshPads(session)
	session.Loaded = true
	RewardService.GrantOffline(session)
	Core.SyncNow(session)

	if not plot then
		Core.Notify(player, "Alle Fabriken sind belegt – du kannst dich trotzdem umsehen!", "error")
	end
	if not canSave then
		Core.Notify(player, "⚠️ Speichern ist aus. In Studio: Game Settings → Security → API-Zugriff einschalten.", "error")
	end
	local isNew = profile.Stats.PlayTime < 5 and profile.Lanes[1].Level == 0 and profile.Stats.Rebirths == 0
	if isNew then
		Core.Notify(player, "🍋 Willkommen! Papa hat dir $1 geschenkt. Lauf auf den grünen Knopf und bau deinen Zitronen-Stand!", "gold")
	else
		Core.Notify(player, "🍋 Willkommen zurück in deiner Zitronen-Fabrik!", "info")
	end
	PlotService.TeleportHome(session)
end

-- Eine frei gewordene Fabrik an jemanden ohne Fabrik geben
local function assignWaitingPlayers()
	for _, waiting in pairs(Core.Sessions) do
		if waiting.Loaded and not waiting.Plot and waiting.Player.Parent then
			if not PlotService.Assign(waiting) then
				return
			end
			ProductionService.InitLanes(waiting)
			PlotService.BuildFromProfile(waiting)
			Core.RecomputeStats(waiting)
			PlotService.RefreshPads(waiting)
			PlotService.TeleportHome(waiting)
			Core.Notify(waiting.Player, "🍋 Eine Fabrik ist frei geworden – sie gehört jetzt dir!", "gold")
		end
	end
end

local function onPlayerRemoving(player: Player)
	local session = Core.Get(player)
	if not session then
		return
	end
	Core.RemoveSession(player)
	-- Fabrik sofort freigeben (Speichern braucht nur das Profil)
	PlotService.Release(session)
	assignWaitingPlayers()
	if session.Loaded then
		DataService.SaveOnLeave(session)
	end
end

function PlayerService.Init()
	Core.RegisterAction("TeleportHome", function(session)
		PlotService.TeleportHome(session)
	end)
	Core.RegisterAction("SetSetting", function(session, key, value)
		if type(key) == "string" and SETTINGS[key] and type(value) == "boolean" then
			session.Profile.Settings[key] = value
			Core.MarkDirty(session)
		end
	end)
end

function PlayerService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
end

return PlayerService
