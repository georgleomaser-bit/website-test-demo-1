--[[
	Alle Käufe mit Geld: Knöpfe in der Fabrik (Linien, Manager, Maschinen, Deko),
	Level im Fabrik-Menü und Geld-Upgrades im Upgrade-Menü.
	Der Server prüft alles – der Client darf nur fragen.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local Core = require(script.Parent.Core)
local PlotService = require(script.Parent.PlotService)
local ProductionService = require(script.Parent.ProductionService)
local PlotBuilder = require(script.Parent.Parent.World.PlotBuilder)

local ShopService = {}

local function padPosition(session, padId: string): Vector3?
	local plot = session.Plot
	local pad = plot and plot.Buttons:FindFirstChild(padId)
	local part = pad and pad:FindFirstChild("Pad") :: BasePart?
	return part and part.Position or nil
end

local function notEnough(session, cost: number, key: string)
	-- Nicht bei jedem Schritt auf dem Knopf meckern
	local now = os.clock()
	session.ErrorCooldown = session.ErrorCooldown or {}
	if (session.ErrorCooldown[key] or 0) > now then
		return
	end
	session.ErrorCooldown[key] = now + 2.5
	Core.NotEnough(session, cost)
end

local function purchased(session, text: string, position: Vector3?)
	Core.Notify(session.Player, text, "success")
	Core.Effect(session.Player, "Purchase", position)
end

--------------------------------------------------------------------------
-- Knöpfe
--------------------------------------------------------------------------
local function buyUnlock(session, laneIndex: number, padId: string)
	local profile = session.Profile
	local laneCfg = Config.Lanes[laneIndex]
	local lane = profile.Lanes[laneIndex]
	if not laneCfg or lane.Level > 0 then
		return
	end
	if laneIndex > 1 and profile.Lanes[laneIndex - 1].Level <= 0 then
		return
	end
	local cost = Economy.LevelCost(laneCfg, 0, 1, session.Stats.Discount)
	local position = padPosition(session, padId)
	if not Core.TrySpend(session, cost) then
		notEnough(session, cost, padId)
		return
	end
	lane.Level = 1
	PlotService.BuildLane(session, laneIndex)
	Core.RecomputeStats(session)
	PlotService.RefreshPads(session)
	purchased(session, laneCfg.Emoji .. " " .. laneCfg.Name .. " gebaut!", position)
	if laneIndex == 1 and profile.Stats.Rebirths == 0 and profile.Evolution == 0 then
		Core.Notify(session.Player, "Drück den ROTEN KNOPF neben dem Band, um Zitronen zu pressen! 🔴", "info")
	end
end

local function buyManager(session, laneIndex: number, padId: string)
	local profile = session.Profile
	local laneCfg = Config.Lanes[laneIndex]
	local lane = profile.Lanes[laneIndex]
	if not laneCfg or lane.Level <= 0 or lane.Manager then
		return
	end
	local cost = Economy.ManagerCost(laneCfg, session.Stats)
	local position = padPosition(session, padId)
	if not Core.TrySpend(session, cost) then
		notEnough(session, cost, padId)
		return
	end
	lane.Manager = true
	local rt = session.Lanes[laneIndex]
	if not rt.Running then
		rt.Running = true
		rt.CycleStart = workspace:GetServerTimeNow()
	end
	PlotService.SpawnManager(session, laneIndex)
	Core.RecomputeStats(session)
	PlotService.RefreshPads(session)
	purchased(session, "🤖 " .. laneCfg.Manager.Name .. " arbeitet jetzt für dich!", position)
end

local function buyUpgrader(session, laneIndex: number, upgraderIndex: number, padId: string)
	local profile = session.Profile
	local laneCfg = Config.Lanes[laneIndex]
	local lane = profile.Lanes[laneIndex]
	if not laneCfg or lane.Level <= 0 or lane.Upgraders + 1 ~= upgraderIndex then
		return
	end
	local info = laneCfg.Upgraders[upgraderIndex]
	if not info then
		return
	end
	local cost = Economy.UpgraderCost(laneCfg, upgraderIndex, session.Stats)
	local position = padPosition(session, padId)
	if not Core.TrySpend(session, cost) then
		notEnough(session, cost, padId)
		return
	end
	lane.Upgraders = upgraderIndex
	PlotBuilder.BuildUpgrader(session.Plot, laneIndex, upgraderIndex)
	Core.RecomputeStats(session)
	PlotService.RefreshPads(session)
	purchased(session, "⚙️ " .. info.Name .. " gebaut! " .. laneCfg.Name .. " bringt ×" .. info.Mult, position)
end

local function buyDecor(session, decorIndex: number, padId: string)
	local profile = session.Profile
	if profile.Decor + 1 ~= decorIndex then
		return
	end
	local info = Config.Decor[decorIndex]
	if not info then
		return
	end
	local position = padPosition(session, padId)
	if not Core.TrySpend(session, info.Cost) then
		notEnough(session, info.Cost, padId)
		return
	end
	profile.Decor = decorIndex
	PlotBuilder.BuildDecor(session.Plot, decorIndex)
	Core.RecomputeStats(session)
	PlotService.RefreshPads(session)
	purchased(session, info.Emoji .. " " .. info.Name .. " gebaut! Alles bringt +" .. math.floor(Config.DecorBonus * 100 + 0.5) .. " %", position)
end

function ShopService.BuyPad(session, padId: string)
	local kind, a, b = string.match(padId, "^(%a+)_(%d+)_?(%d*)$")
	local first = tonumber(a)
	if not kind or not first then
		return
	end
	if kind == "unlock" then
		buyUnlock(session, first, padId)
	elseif kind == "manager" then
		buyManager(session, first, padId)
	elseif kind == "upgrader" then
		local second = tonumber(b)
		if second then
			buyUpgrader(session, first, second, padId)
		end
	elseif kind == "decor" then
		buyDecor(session, first, padId)
	end
end

--------------------------------------------------------------------------
-- Level kaufen (Fabrik-Menü)
--------------------------------------------------------------------------
function ShopService.BuyLevels(session, laneIndex: any, mode: any)
	if type(laneIndex) ~= "number" then
		return
	end
	laneIndex = math.floor(laneIndex)
	local laneCfg = Config.Lanes[laneIndex]
	if not laneCfg then
		return
	end
	local profile = session.Profile
	local lane = profile.Lanes[laneIndex]
	if lane.Level <= 0 then
		Core.Notify(session.Player, "Schalte die Linie zuerst am Knopf in deiner Fabrik frei!", "error")
		return
	end
	if lane.Level >= Config.MaxLevel then
		Core.Notify(session.Player, "Maximales Level erreicht! 🏆", "info")
		return
	end
	local discount = session.Stats.Discount
	local amount
	if mode == "max" then
		amount = Economy.MaxAffordable(laneCfg, lane.Level, profile.Cash, discount)
		if amount <= 0 then
			notEnough(session, Economy.LevelCost(laneCfg, lane.Level, 1, discount), "level" .. laneIndex)
			return
		end
	elseif mode == 1 or mode == 10 or mode == 100 then
		amount = math.min(mode, Config.MaxLevel - lane.Level)
	else
		return
	end
	local cost = Economy.LevelCost(laneCfg, lane.Level, amount, discount)
	if not Core.TrySpend(session, cost) then
		notEnough(session, cost, "level" .. laneIndex)
		return
	end
	local before = lane.Level
	lane.Level += amount
	Core.RecomputeStats(session)
	Core.Effect(session.Player, "LevelUp", { Lane = laneIndex, Level = lane.Level })
	-- Meilenstein erreicht?
	for _, m in ipairs(Config.Milestones) do
		if before < m.Level and lane.Level >= m.Level then
			local what = m.Speed and ("läuft " .. m.Speed .. "× so schnell") or ("bringt " .. (m.Revenue or 1) .. "× so viel")
			Core.Notify(session.Player, "🏁 Meilenstein Level " .. m.Level .. "! " .. laneCfg.Name .. " " .. what .. "!", "gold")
			Core.Effect(session.Player, "Milestone", { Lane = laneIndex, Level = m.Level })
		end
	end
end

--------------------------------------------------------------------------
-- Geld-Upgrades (Upgrade-Menü)
--------------------------------------------------------------------------
local function buyUpgrade(session, id: string, quiet: boolean?): boolean
	local info = Config.CashUpgradeById[id]
	local profile = session.Profile
	if not info or profile.Upgrades[id] then
		return false
	end
	if not Core.TrySpend(session, info.Cost) then
		if not quiet then
			notEnough(session, info.Cost, "upgrade")
		end
		return false
	end
	profile.Upgrades[id] = true
	if not quiet then
		Core.Notify(session.Player, info.Emoji .. " " .. info.Name .. ": " .. info.Description .. "!", "success")
		Core.Effect(session.Player, "Purchase")
	end
	return true
end

function ShopService.BuyUpgrade(session, id: any)
	if type(id) ~= "string" then
		return
	end
	if buyUpgrade(session, id, false) then
		Core.RecomputeStats(session)
	end
end

function ShopService.BuyAllUpgrades(session)
	local count = 0
	for _, info in ipairs(Config.CashUpgrades) do
		if not session.Profile.Upgrades[info.Id] and Core.CanAfford(session, info.Cost) then
			if buyUpgrade(session, info.Id, true) then
				count += 1
			end
		end
	end
	if count > 0 then
		Core.RecomputeStats(session)
		Core.Notify(session.Player, count .. " Upgrades gekauft! 🌟", "success")
		Core.Effect(session.Player, "Purchase")
	else
		Core.Notify(session.Player, "Du kannst dir gerade kein Upgrade leisten.", "error")
	end
end

function ShopService.Init()
	PlotService.PadHandler = ShopService.BuyPad
	Core.RegisterAction("BuyLevels", ShopService.BuyLevels)
	Core.RegisterAction("BuyUpgrade", ShopService.BuyUpgrade)
	Core.RegisterAction("BuyAllUpgrades", ShopService.BuyAllUpgrades)
end

ShopService.Format = Format
ShopService.ProductionService = ProductionService

return ShopService
