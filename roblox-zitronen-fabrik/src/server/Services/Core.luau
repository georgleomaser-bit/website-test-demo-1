--[[
	Kern des Servers: Spieler-Sitzungen, Geld, Werte-Berechnung,
	Synchronisation zum Client und Aktionen vom Client.
	Alle anderen Services benutzen diese Funktionen.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Core = {}

Core.Sessions = {} :: { [Player]: any }
Core.EventIncome = 1
Core.EventSpeed = 1

local actions: { [string]: (any, ...any) -> () } = {}
local syncRemote: RemoteEvent
local notifyRemote: RemoteEvent
local effectRemote: RemoteEvent

--------------------------------------------------------------------------
-- Sitzungen
--------------------------------------------------------------------------
function Core.Get(player: Player)
	return Core.Sessions[player]
end

function Core.CreateSession(player: Player)
	local lanes = {}
	for i = 1, #Config.Lanes do
		lanes[i] = { Running = false, CycleStart = 0, CycleTime = Config.Lanes[i].CycleTime, Revenue = 0 }
	end
	local session = {
		Player = player,
		Profile = Economy.NewProfile(),
		Loaded = false,
		CanSave = false,
		Plot = nil :: Model?,
		Lanes = lanes,
		Stats = nil,
		Passes = { DoubleCash = false, Turbo = false },
		Dirty = true,
		CashDirty = true,
		IncomeBuckets = table.create(10, 0),
		IncomeBucketIndex = 1,
		Income = 0,
		ActionBudget = 30,
		SewerProgress = {},
		SewerSolved = false,
		JoinedAt = os.time(),
	}
	Core.Sessions[player] = session
	return session
end

function Core.RemoveSession(player: Player)
	Core.Sessions[player] = nil
end

--------------------------------------------------------------------------
-- Nachrichten & Effekte
--------------------------------------------------------------------------
function Core.Notify(player: Player, text: string, style: string?)
	notifyRemote:FireClient(player, text, style or "info")
end

function Core.NotifyAll(text: string, style: string?)
	notifyRemote:FireAllClients(text, style or "info")
end

function Core.Effect(player: Player, kind: string, data: any?)
	effectRemote:FireClient(player, kind, data)
end

function Core.EffectAll(kind: string, data: any?)
	effectRemote:FireAllClients(kind, data)
end

--------------------------------------------------------------------------
-- Geld
--------------------------------------------------------------------------
-- Verdientes Geld (zählt für Investoren und Bestenliste).
-- fromProduction = true nur für Verkäufe (fließt in die "pro Sekunde"-Anzeige)
function Core.AddEarnings(session, amount: number, fromProduction: boolean?)
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return
	end
	if amount == math.huge then
		amount = 1e300
	end
	local profile = session.Profile
	profile.Cash = math.min(profile.Cash + amount, 1e300)
	profile.EvoEarnings = math.min(profile.EvoEarnings + amount, 1e300)
	profile.AllTimeEarnings = math.min(profile.AllTimeEarnings + amount, 1e300)
	if fromProduction then
		local idx = session.IncomeBucketIndex
		session.IncomeBuckets[idx] += amount
	end
	session.CashDirty = true
end

-- Gutschrift rückgängig machen (z. B. wenn ein Robux-Kauf nicht gespeichert werden konnte)
function Core.RevertEarnings(session, amount: number)
	local profile = session.Profile
	profile.Cash = math.max(0, profile.Cash - amount)
	profile.EvoEarnings = math.max(0, profile.EvoEarnings - amount)
	profile.AllTimeEarnings = math.max(0, profile.AllTimeEarnings - amount)
	session.CashDirty = true
end

function Core.CanAfford(session, cost: number): boolean
	return type(cost) == "number" and cost == cost and cost >= 0 and session.Profile.Cash >= cost * (1 - 1e-12)
end

function Core.TrySpend(session, cost: number): boolean
	if not Core.CanAfford(session, cost) then
		return false
	end
	session.Profile.Cash = math.max(0, session.Profile.Cash - cost)
	session.CashDirty = true
	return true
end

function Core.NotEnough(session, cost: number)
	Core.Notify(session.Player, "Nicht genug Geld! Dir fehlen " .. Format.Cash(cost - session.Profile.Cash), "error")
	Core.Effect(session.Player, "Error")
end

--------------------------------------------------------------------------
-- Werte berechnen & Linien-Zustand schreiben
--------------------------------------------------------------------------
function Core.Context(session)
	return {
		EventIncome = Core.EventIncome,
		EventSpeed = Core.EventSpeed,
		DoubleCash = session.Passes.DoubleCash,
		TurboPass = session.Passes.Turbo,
	}
end

function Core.WriteLaneState(session, index: number)
	local plot = session.Plot
	if not plot then
		return
	end
	local state = plot.LaneState:FindFirstChild("Lane" .. index)
	if not state then
		return
	end
	local lane = session.Profile.Lanes[index]
	local rt = session.Lanes[index]
	state:SetAttribute("Unlocked", lane.Level > 0)
	state:SetAttribute("Level", lane.Level)
	state:SetAttribute("Manager", lane.Manager)
	state:SetAttribute("Upgraders", lane.Upgraders)
	state:SetAttribute("CycleTime", rt.CycleTime)
	state:SetAttribute("Revenue", rt.Revenue)
	state:SetAttribute("CycleStart", rt.CycleStart)
	state:SetAttribute("Running", rt.Running)
end

-- Rechnet alle Multiplikatoren neu. Laufende Zyklen behalten ihren Fortschritt.
function Core.RecomputeStats(session)
	local profile = session.Profile
	local stats = Economy.ComputeStats(profile, Core.Context(session))
	session.Stats = stats
	local now = workspace:GetServerTimeNow()
	for i, laneStats in ipairs(stats.Lanes) do
		local rt = session.Lanes[i]
		local newTime = laneStats.CycleTime
		if rt.Running and rt.CycleTime > 0 and math.abs(rt.CycleTime - newTime) > 1e-9 then
			local progress = math.clamp((now - rt.CycleStart) / rt.CycleTime, 0, 1)
			rt.CycleStart = now - progress * newTime
		end
		rt.CycleTime = newTime
		rt.Revenue = laneStats.Revenue
		Core.WriteLaneState(session, i)
	end
	if session.Plot then
		session.Plot:SetAttribute("Fruit", profile.Evolution + 1)
		session.Plot:SetAttribute("Decor", profile.Decor)
	end
	Core.MarkDirty(session)
end

function Core.MarkDirty(session)
	session.Dirty = true
	session.CashDirty = true
end

--------------------------------------------------------------------------
-- Leaderstats (Spielerliste oben rechts)
--------------------------------------------------------------------------
function Core.CreateLeaderstats(player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local cash = Instance.new("StringValue")
	cash.Name = "💵 Geld"
	cash.Value = "$0"
	cash.Parent = folder
	local investors = Instance.new("StringValue")
	investors.Name = "🛸 Investoren"
	investors.Value = "0"
	investors.Parent = folder
	folder.Parent = player
end

local function updateLeaderstats(session)
	local folder = session.Player:FindFirstChild("leaderstats")
	if not folder then
		return
	end
	local cash = folder:FindFirstChild("💵 Geld") :: StringValue?
	local investors = folder:FindFirstChild("🛸 Investoren") :: StringValue?
	if cash then
		cash.Value = Format.Cash(session.Profile.Cash)
	end
	if investors then
		investors.Value = Format.Number(session.Profile.Investors)
	end
end

--------------------------------------------------------------------------
-- Synchronisation zum Client
--------------------------------------------------------------------------
local function isAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	return table.find(Config.AdminUserIds, player.UserId) ~= nil
end
Core.IsAdmin = isAdmin

-- Weitere Services können Infos in den Sync hängen (z. B. tägliche Belohnung)
Core.SyncExtras = {} :: { (any, any) -> () }

function Core.BuildSyncPayload(session)
	local profile = session.Profile
	local stats = session.Stats or Economy.ComputeStats(profile, Core.Context(session))
	local laneStats = {}
	for i, ls in ipairs(stats.Lanes) do
		laneStats[i] = {
			Revenue = ls.Revenue,
			CycleTime = ls.CycleTime,
			IncomePerSec = ls.IncomePerSec,
			UpgradeMult = ls.UpgradeMult,
		}
	end
	local payload = {
		Profile = {
			Investors = profile.Investors,
			InvestorsSpent = profile.InvestorsSpent,
			Evolution = profile.Evolution,
			Powers = profile.Powers,
			Lanes = profile.Lanes,
			Upgrades = profile.Upgrades,
			Decor = profile.Decor,
			Secrets = profile.Secrets,
			Daily = profile.Daily,
			Settings = profile.Settings,
			Stats = profile.Stats,
			AllTimeEarnings = profile.AllTimeEarnings,
			ObbyLast = profile.ObbyLast,
		},
		Stats = {
			Global = stats.Global,
			PerInvestor = stats.PerInvestor,
			InvestorMult = stats.InvestorMult,
			DecorMult = stats.DecorMult,
			EvoIncome = stats.EvoIncome,
			EvoSpeed = stats.EvoSpeed,
			AllMult = stats.AllMult,
			Speed = stats.Speed,
			GoldenChance = stats.GoldenChance,
			Discount = stats.Discount,
			BuildDiscount = stats.BuildDiscount,
			AutoIncome = stats.AutoIncome,
			TotalIncome = stats.TotalIncome,
			Lanes = laneStats,
		},
		PlotIndex = session.Plot and session.Plot:GetAttribute("Index") or 0,
		Passes = session.Passes,
		CanSave = session.CanSave,
		IsAdmin = isAdmin(session.Player),
		ServerTime = os.time(),
	}
	for _, extra in ipairs(Core.SyncExtras) do
		extra(session, payload)
	end
	return payload
end

function Core.SyncNow(session)
	session.Dirty = false
	syncRemote:FireClient(session.Player, Core.BuildSyncPayload(session))
end

--------------------------------------------------------------------------
-- Aktionen vom Client
--------------------------------------------------------------------------
function Core.RegisterAction(name: string, handler: (any, ...any) -> ())
	actions[name] = handler
end

--------------------------------------------------------------------------
-- Init & Schleifen
--------------------------------------------------------------------------
function Core.Init()
	syncRemote = Remotes.Get("Sync")
	notifyRemote = Remotes.Get("Notify")
	effectRemote = Remotes.Get("Effect")

	Remotes.Get("Action").OnServerEvent:Connect(function(player: Player, action: any, ...)
		local session = Core.Sessions[player]
		if not session or not session.Loaded or type(action) ~= "string" then
			return
		end
		if session.ActionBudget <= 0 then
			return
		end
		session.ActionBudget -= 1
		local handler = actions[action]
		if handler then
			local ok, err = pcall(handler, session, ...)
			if not ok then
				warn("[ZitronenFabrik] Aktion " .. action .. " fehlgeschlagen: " .. tostring(err))
			end
		end
	end)
end

function Core.Start()
	-- Geld & Sync regelmäßig an die Clients schicken
	local syncTimer = 0
	local secondTimer = 0
	RunService.Heartbeat:Connect(function(dt)
		syncTimer += dt
		secondTimer += dt
		if syncTimer >= 0.15 then
			syncTimer = 0
			for player, session in pairs(Core.Sessions) do
				if session.Loaded then
					if session.CashDirty then
						session.CashDirty = false
						player:SetAttribute("Cash", session.Profile.Cash)
						player:SetAttribute("EvoEarnings", session.Profile.EvoEarnings)
						player:SetAttribute("Investors", session.Profile.Investors)
					end
					if session.Dirty then
						Core.SyncNow(session)
					end
				end
			end
		end
		if secondTimer >= 1 then
			secondTimer -= 1
			for player, session in pairs(Core.Sessions) do
				session.ActionBudget = 30
				if session.Loaded then
					session.Profile.Stats.PlayTime += 1
					-- Einkommen der letzten 10 Sekunden
					local sum = 0
					for _, v in ipairs(session.IncomeBuckets) do
						sum += v
					end
					session.Income = sum / #session.IncomeBuckets
					session.IncomeBucketIndex = session.IncomeBucketIndex % #session.IncomeBuckets + 1
					session.IncomeBuckets[session.IncomeBucketIndex] = 0
					local auto = session.Stats and session.Stats.AutoIncome or 0
					player:SetAttribute("Income", math.max(session.Income, auto))
					updateLeaderstats(session)
				end
			end
		end
	end)
end

Core.Players = Players

return Core
