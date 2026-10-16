--[[
	Verteilt Fabriken an Spieler und baut darauf alles nach dem Spielstand auf:
	Linien, Maschinen-Bögen, Manager-NPCs, Deko und die Kauf-Knöpfe.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local Core = require(script.Parent.Core)
local WorldFolder = script.Parent.Parent.World
local PlotBuilder = require(WorldFolder.PlotBuilder)
local NPC = require(WorldFolder.NPC)

local L = Config.Layout

local PlotService = {}

-- Werden von anderen Services gesetzt
PlotService.PadHandler = nil :: ((any, string) -> ())?
PlotService.PressHandler = nil :: ((any, number) -> ())?

local plotsFolder: Folder

function PlotService.Init(world: Instance)
	plotsFolder = world:WaitForChild("Plots") :: Folder
end

function PlotService.GetPlots(): { Model }
	local list = {}
	for i = 1, Config.MaxPlots do
		local plot = plotsFolder:FindFirstChild("Plot" .. i)
		if plot then
			table.insert(list, plot)
		end
	end
	return list
end

function PlotService.Assign(session): Model?
	for _, plot in ipairs(PlotService.GetPlots()) do
		if plot:GetAttribute("OwnerId") == 0 then
			local player = session.Player
			PlotBuilder.SetOwner(plot, player.UserId, player.DisplayName)
			session.Plot = plot
			return plot
		end
	end
	return nil
end

function PlotService.Release(session)
	local plot = session.Plot
	if not plot then
		return
	end
	PlotBuilder.Clear(plot)
	PlotBuilder.SetOwner(plot, 0, "")
	plot:SetAttribute("Fruit", 1)
	session.Plot = nil
end

--------------------------------------------------------------------------
-- Teleport
--------------------------------------------------------------------------
function PlotService.SpawnCFrame(session): CFrame?
	local plot = session.Plot
	local spawnPart = plot and plot:FindFirstChild("Spawn") :: BasePart?
	return spawnPart and spawnPart.CFrame or nil
end

function PlotService.TeleportHome(session)
	local cf = PlotService.SpawnCFrame(session)
	local character = session.Player.Character
	if cf and character and character:FindFirstChild("HumanoidRootPart") then
		character:PivotTo(cf + Vector3.new(0, 2, 0))
	end
end

--------------------------------------------------------------------------
-- Linien & Manager
--------------------------------------------------------------------------
local function ownerSession(plot: Model, player: Player)
	local session = Core.Get(player)
	if session and session.Loaded and session.Plot == plot then
		return session
	end
	return nil
end

local function connectPanel(plot: Model, lane: Model, laneIndex: number)
	local panel = lane:FindFirstChild("Panel")
	local button = panel and panel:FindFirstChild("PressButton")
	if not button then
		return
	end
	local function press(player: Player)
		local session = ownerSession(plot, player)
		if not session then
			Core.Notify(player, "Das ist nicht deine Fabrik!", "error")
			return
		end
		if PlotService.PressHandler then
			PlotService.PressHandler(session, laneIndex)
		end
	end
	local click = button:FindFirstChildOfClass("ClickDetector")
	if click then
		click.MouseClick:Connect(press)
	end
	local prompt = button:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Triggered:Connect(press)
	end
end

function PlotService.BuildLane(session, laneIndex: number)
	local plot = session.Plot
	if not plot then
		return
	end
	local lane = PlotBuilder.BuildLane(plot, laneIndex)
	if lane and not lane:GetAttribute("Connected") then
		lane:SetAttribute("Connected", true)
		connectPanel(plot, lane, laneIndex)
	end
end

function PlotService.SpawnManager(session, laneIndex: number)
	local plot = session.Plot
	if not plot then
		return
	end
	local folder = plot:FindFirstChild("Managers")
	for _, existing in ipairs(folder:GetChildren()) do
		if existing:GetAttribute("Lane") == laneIndex then
			return
		end
	end
	local laneCfg = Config.Lanes[laneIndex]
	local cf = PlotBuilder.LaneCFrame(plot:GetAttribute("Origin"), laneIndex) * CFrame.new(12.4, 0, L.PanelOffset.Z) * CFrame.Angles(0, math.rad(90), 0)
	task.spawn(function()
		local npc = NPC.Create(folder, laneCfg.Manager.Name, {
			CFrame = cf,
			Shirt = laneCfg.Manager.Shirt,
			Pants = Color3.fromRGB(40, 60, 120),
			Hat = laneCfg.Manager.Hat,
			Title = "Manager · " .. laneCfg.Name,
		})
		npc:SetAttribute("Lane", laneIndex)
		-- Falls in der Zwischenzeit Rebirth gemacht oder die Fabrik verlassen wurde
		if session.Plot ~= plot or not session.Profile.Lanes[laneIndex].Manager then
			npc:Destroy()
		end
	end)
end

--------------------------------------------------------------------------
-- Kauf-Knöpfe
--------------------------------------------------------------------------
function PlotService.DesiredPads(session)
	local profile = session.Profile
	local stats = session.Stats or Economy.ComputeStats(profile, Core.Context(session))
	local list = {}
	for i, laneCfg in ipairs(Config.Lanes) do
		local lane = profile.Lanes[i]
		local x = Config.LaneX(i)
		if lane.Level == 0 then
			if i == 1 or profile.Lanes[i - 1].Level > 0 then
				list["unlock_" .. i] = {
					Pos = Vector3.new(x, 0, L.UnlockPadZ),
					Title = laneCfg.Emoji .. " " .. laneCfg.Name,
					Cost = Economy.LevelCost(laneCfg, 0, 1, stats.Discount),
					Kind = "unlock",
					Lane = i,
				}
			end
		else
			if not lane.Manager then
				list["manager_" .. i] = {
					Pos = L.ManagerPadOffset + Vector3.new(x, 0, 0),
					Title = "🤖 Manager",
					Cost = Economy.ManagerCost(laneCfg, stats),
					Kind = "manager",
					Lane = i,
				}
			end
			local nextIndex = lane.Upgraders + 1
			local info = laneCfg.Upgraders[nextIndex]
			if info then
				list["upgrader_" .. i .. "_" .. nextIndex] = {
					Pos = Vector3.new(x + L.UpgraderPadX, 0, L.UpgraderZ[nextIndex]),
					Title = "⚙️ " .. info.Name .. " ×" .. info.Mult,
					Cost = Economy.UpgraderCost(laneCfg, nextIndex, stats),
					Kind = "upgrader",
					Lane = i,
				}
			end
		end
	end
	if profile.Lanes[1].Level > 0 and profile.Decor < #Config.Decor then
		local nextDecor = profile.Decor + 1
		local d = Config.Decor[nextDecor]
		list["decor_" .. nextDecor] = {
			Pos = L.DecorPadPos,
			Title = d.Emoji .. " " .. d.Name .. " (+" .. math.floor(Config.DecorBonus * 100 + 0.5) .. "%)",
			Cost = d.Cost,
			Kind = "decor",
			Lane = 0,
		}
	end
	return list
end

local function connectPad(plot: Model, pad: Model, padId: string)
	local part = pad:FindFirstChild("Pad") :: BasePart?
	if not part then
		return
	end
	part.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end
		local humanoid = (character :: Instance):FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end
		local session = Core.Get(player)
		if not session or not session.Loaded then
			return
		end
		if session.Plot ~= plot then
			local now = os.clock()
			if (session.ForeignPadWarn or 0) < now then
				session.ForeignPadWarn = now + 3
				Core.Notify(player, "Das ist nicht deine Fabrik! Deine hat dein Namensschild.", "error")
			end
			return
		end
		local now = os.clock()
		if (session.PadCooldown or 0) > now then
			return
		end
		session.PadCooldown = now + 0.4
		if PlotService.PadHandler then
			PlotService.PadHandler(session, padId)
		end
	end)
end

function PlotService.RefreshPads(session)
	local plot = session.Plot
	if not plot then
		return
	end
	local buttons = plot:FindFirstChild("Buttons")
	local desired = PlotService.DesiredPads(session)
	for _, pad in ipairs(buttons:GetChildren()) do
		if not desired[pad.Name] then
			pad:Destroy()
		end
	end
	for padId, info in pairs(desired) do
		local pad = buttons:FindFirstChild(padId)
		if not pad then
			pad = PlotBuilder.CreatePad(plot, padId, info.Pos, info.Title, info.Cost, info.Kind, info.Lane)
			connectPad(plot, pad, padId)
		end
		pad:SetAttribute("Cost", info.Cost)
		local part = pad:FindFirstChild("Pad")
		local label = part and part:FindFirstChild("Label")
		local price = label and label:FindFirstChild("Price") :: TextLabel?
		if price then
			price.Text = Format.Cash(info.Cost)
		end
	end
end

--------------------------------------------------------------------------
-- Alles nach Spielstand aufbauen
--------------------------------------------------------------------------
function PlotService.BuildFromProfile(session)
	local plot = session.Plot
	if not plot then
		return
	end
	PlotBuilder.Clear(plot)
	local profile = session.Profile
	for i = 1, #Config.Lanes do
		local lane = profile.Lanes[i]
		if lane.Level > 0 then
			PlotService.BuildLane(session, i)
			for j = 1, lane.Upgraders do
				PlotBuilder.BuildUpgrader(plot, i, j)
			end
			if lane.Manager then
				PlotService.SpawnManager(session, i)
			end
		end
	end
	for k = 1, profile.Decor do
		PlotBuilder.BuildDecor(plot, k)
	end
	plot:SetAttribute("Fruit", profile.Evolution + 1)
	plot:SetAttribute("Decor", profile.Decor)
	PlotService.RefreshPads(session)
end

return PlotService
