-- Geld & Fortschritt: Einkommen, Aufladen (Level), Einsammeln, Verkaufen,
-- Speed Farm, Rebirth, Tagesbonus, Index, Leaderstats und Daten an den Client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))

local EconomyService = {}
local Services

local dirty: { [Player]: boolean } = {}
local requestLimiter = Util.RateLimiter(8, 1)

-- -------------------------------------------------------------------
-- NACHRICHTEN
-- -------------------------------------------------------------------
function EconomyService.Notify(player: Player?, text: string, kind: string?)
	if player and player.Parent then
		Remotes.Notify:FireClient(player, text, kind or "Info")
	end
end

function EconomyService.NotifyAll(text: string, kind: string?)
	Remotes.Notify:FireAllClients(text, kind or "Info")
end

function EconomyService.Effect(player: Player?, name: string, strength: number?)
	if player and player.Parent then
		Remotes.Effect:FireClient(player, name, strength or 1)
	end
end

function EconomyService.MarkDirty(player: Player?)
	if player then
		dirty[player] = true
	end
end

-- -------------------------------------------------------------------
-- RECHNEN
-- -------------------------------------------------------------------
function EconomyService.IndexCount(data): number
	local count = 0
	for id in pairs(data.Index) do
		if Config.MeteorsById[id] then
			count += 1
		end
	end
	return count
end

function EconomyService.GetMultiplier(player: Player): number
	local data = Services.DataService.Get(player)
	if not data then
		return 1
	end
	local Monetization = Services.MonetizationService
	local mult = 1 + data.Rebirths * Config.RebirthMultPerLevel
	if Monetization.HasPass(player, "DoubleCash") then
		mult *= 2
	end
	local bonus = 1 + EconomyService.IndexCount(data) * Config.IndexBonusPerMeteor
	if Monetization.HasPass(player, "VIP") then
		bonus += Config.VIPBonus
	end
	if player.MembershipType == Enum.MembershipType.Premium then
		bonus += Config.PremiumBonus
	end
	return mult * bonus
end

function EconomyService.GetIncome(player: Player): number
	local data = Services.DataService.Get(player)
	if not data then
		return 0
	end
	local plot = Services.PlotService.GetPlot(player)
	local base = 0
	for key, entry in pairs(data.Meteors) do
		local slot = tonumber(key)
		if not (plot and slot and Services.CarryService.IsSlotBeingStolen(plot, slot)) then
			base += Config.MeteorIncome(entry)
		end
	end
	return base * EconomyService.GetMultiplier(player)
end

function EconomyService.GetSpeed(player: Player): number
	local data = Services.DataService.Get(player)
	local speed = Config.NormalWalkSpeed
	if data then
		speed += data.SpeedLevel * Config.SpeedPerLevel
	end
	if Services.MonetizationService.HasPass(player, "SpeedBoots") then
		speed += Config.SpeedBootsBonus
	end
	return speed
end

function EconomyService.ApplySpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local speed = EconomyService.GetSpeed(player)
	if Services.CarryService.IsCarrying(player) then
		speed = math.max(8, speed * Config.CarrySpeedFactor)
	end
	humanoid.WalkSpeed = speed
end

-- -------------------------------------------------------------------
-- GELD
-- -------------------------------------------------------------------
function EconomyService.AddCash(player: Player, amount: number)
	local data = Services.DataService.Get(player)
	if not data or amount ~= amount then
		return
	end
	data.Cash = math.max(0, data.Cash + amount)
	if amount > 0 then
		data.TotalEarned += amount
	end
	dirty[player] = true
end

function EconomyService.Collect(player: Player)
	local data = Services.DataService.Get(player)
	if not data or data.Pending < 1 then
		return
	end
	local amount = math.floor(data.Pending)
	data.Pending -= amount
	EconomyService.AddCash(player, amount)
	EconomyService.Effect(player, "Collect", amount)
	local plot = Services.PlotService.GetPlot(player)
	if plot then
		plot.CollectLabel.Text = "💰 " .. Util.FormatCash(data.Pending)
	end
end

function EconomyService.Discover(player: Player, meteorId: string)
	local data = Services.DataService.Get(player)
	if data and Config.MeteorsById[meteorId] and not data.Index[meteorId] then
		data.Index[meteorId] = true
		local def = Config.MeteorsById[meteorId]
		EconomyService.Notify(
			player,
			"📖 NEU im Index: "
				.. def.Name
				.. "! (+"
				.. math.floor(Config.IndexBonusPerMeteor * 100)
				.. "% Einkommen)",
			"Success"
		)
		dirty[player] = true
	end
end

-- Meteor direkt in die Base legen (Admin, Produkte). Gibt true zurück, wenn Platz war.
function EconomyService.GiveMeteor(player: Player, entry): boolean
	local data = Services.DataService.Get(player)
	local plot = Services.PlotService.GetPlot(player)
	local slot = Services.PlotService.FreeSlot(player)
	if not data or not plot or not slot or not Config.MeteorsById[entry.Id] then
		return false
	end
	data.Meteors[tostring(slot)] = {
		Id = entry.Id,
		Mut = Config.MutationsByName[entry.Mut] and entry.Mut or "Normal",
		Lv = math.clamp(math.floor(entry.Lv or 1), 1, Config.MaxLevel),
		Xp = 0,
	}
	EconomyService.Discover(player, entry.Id)
	Services.PlotService.RenderSlot(plot, slot)
	dirty[player] = true
	return true
end

function EconomyService.Sell(player: Player, plot, slot: number)
	if plot.Owner ~= player then
		return
	end
	local data = Services.DataService.Get(player)
	local key = tostring(slot)
	local entry = data and data.Meteors[key]
	if not entry or Services.CarryService.IsSlotBeingStolen(plot, slot) then
		return
	end
	local value = math.floor(Config.MeteorValue(entry) * Config.SellRatio)
	data.Meteors[key] = nil
	EconomyService.AddCash(player, value)
	Services.PlotService.RenderSlot(plot, slot)
	EconomyService.Notify(player, "Verkauft für " .. Util.FormatCash(value), "Success")
end

-- -------------------------------------------------------------------
-- SPEED FARM / REBIRTH / DAILY
-- -------------------------------------------------------------------
function EconomyService.BuySpeed(player: Player, amount: number): (boolean, string)
	local data = Services.DataService.Get(player)
	if not data then
		return false, "Lädt noch..."
	end
	amount = math.clamp(math.floor(amount), 1, Config.MaxSpeedLevel)
	local bought = 0
	while bought < amount and data.SpeedLevel < Config.MaxSpeedLevel do
		local cost = Config.SpeedCost(data.SpeedLevel)
		if data.Cash < cost then
			break
		end
		data.Cash -= cost
		data.SpeedLevel += 1
		bought += 1
	end
	dirty[player] = true
	if bought == 0 then
		if data.SpeedLevel >= Config.MaxSpeedLevel then
			return false, "Maximales Speed-Level erreicht!"
		end
		return false, "Nicht genug Cash! (" .. Util.FormatCash(Config.SpeedCost(data.SpeedLevel)) .. ")"
	end
	EconomyService.ApplySpeed(player)
	return true, "🏃 +" .. bought .. " Speed! (Level " .. data.SpeedLevel .. ")"
end

function EconomyService.Rebirth(player: Player): (boolean, string)
	local data = Services.DataService.Get(player)
	if not data then
		return false, "Lädt noch..."
	end
	if Services.CarryService.IsCarrying(player) then
		return false, "Bring erst deinen Meteor nach Hause!"
	end
	local cost = Config.RebirthCost(data.Rebirths)
	if data.Cash < cost then
		return false, "Du brauchst " .. Util.FormatCash(cost) .. " für den Rebirth!"
	end
	local plot = Services.PlotService.GetPlot(player)
	if plot then
		Services.CarryService.CancelStealsFromPlot(plot, "cancelled")
	end
	data.Rebirths += 1
	data.Cash = Config.StartCash
	data.Pending = 0
	data.Meteors = {}
	if plot then
		Services.PlotService.RenderAll(plot)
	end
	dirty[player] = true
	EconomyService.NotifyAll("🔥 " .. player.DisplayName .. " hat Rebirth " .. data.Rebirths .. " erreicht!", "Event")
	EconomyService.Effect(player, "Confetti", 2)
	return true, "Rebirth! Jetzt " .. Util.FormatNumber(EconomyService.GetMultiplier(player) * 100) .. "% Einkommen"
end

local DAY = 24 * 3600

function EconomyService.DailyStatus(data): (boolean, number)
	local elapsed = os.time() - data.Daily.Last
	return elapsed >= DAY, math.max(0, DAY - elapsed)
end

function EconomyService.ClaimDaily(player: Player): (boolean, string)
	local data = Services.DataService.Get(player)
	if not data then
		return false, "Lädt noch..."
	end
	local ready, remaining = EconomyService.DailyStatus(data)
	if not ready then
		return false, "Nächster Bonus in " .. Util.FormatTime(remaining)
	end
	local elapsed = os.time() - data.Daily.Last
	if data.Daily.Last > 0 and elapsed < DAY * 2 then
		data.Daily.Streak += 1
	else
		data.Daily.Streak = 1
	end
	data.Daily.Last = os.time()
	local reward = math.max(
		Config.DailyRewardMinCash,
		EconomyService.GetIncome(player) * Config.DailyRewardIncomeSeconds
	) * math.min(data.Daily.Streak, 7)
	reward = math.floor(reward)
	EconomyService.AddCash(player, reward)
	EconomyService.Effect(player, "Confetti", 1)
	return true, "🎁 Tag " .. data.Daily.Streak .. ": +" .. Util.FormatCash(reward)
end

-- -------------------------------------------------------------------
-- DATEN AN DEN CLIENT
-- -------------------------------------------------------------------
local function buildState(player: Player)
	local data = Services.DataService.Get(player)
	if not data then
		return nil
	end
	local plot = Services.PlotService.GetPlot(player)
	local dailyReady, dailyIn = EconomyService.DailyStatus(data)
	local passes = {}
	for _, pass in ipairs(Config.GamePasses) do
		passes[pass.Key] = Services.MonetizationService.HasPass(player, pass.Key)
	end
	local index = {}
	for id in pairs(data.Index) do
		table.insert(index, id)
	end
	return {
		Cash = data.Cash,
		Pending = data.Pending,
		Income = EconomyService.GetIncome(player),
		Multiplier = EconomyService.GetMultiplier(player),
		Rebirths = data.Rebirths,
		RebirthCost = Config.RebirthCost(data.Rebirths),
		SpeedLevel = data.SpeedLevel,
		Speed = EconomyService.GetSpeed(player),
		Slots = Services.PlotService.SlotCount(player),
		UsedSlots = Services.PlotService.UsedSlots(player),
		DailyReady = dailyReady,
		DailyIn = dailyIn,
		Streak = data.Daily.Streak,
		Index = index,
		Passes = passes,
		Carrying = Services.CarryService.IsCarrying(player),
		HasPlot = plot ~= nil,
		Stats = data.Stats,
		TotalEarned = data.TotalEarned,
	}
end

local function updateLeaderstats(player: Player)
	local data = Services.DataService.Get(player)
	local stats = player:FindFirstChild("leaderstats")
	if not data or not stats then
		return
	end
	local cash = stats:FindFirstChild("Cash") :: StringValue?
	local rebirths = stats:FindFirstChild("Rebirths") :: IntValue?
	if cash then
		cash.Value = Util.FormatCash(data.Cash)
	end
	if rebirths then
		rebirths.Value = data.Rebirths
	end
end

local function flush(player: Player)
	local state = buildState(player)
	if state then
		Remotes.State:FireClient(player, state)
		updateLeaderstats(player)
	end
end

local function onProfileLoaded(player: Player, data)
	-- Leaderboard in der Spielerliste
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local cash = Instance.new("StringValue")
	cash.Name = "Cash"
	cash.Parent = stats
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = stats
	stats.Parent = player

	-- alte Spielstände reparieren (gelöschte Meteor-Typen entfernen, Slots kappen)
	for key, entry in pairs(data.Meteors) do
		local slot = tonumber(key)
		if not slot or not Config.MeteorsById[entry.Id] or slot < 1 or slot > 15 then
			data.Meteors[key] = nil
		else
			entry.Lv = math.clamp(math.floor(entry.Lv or 1), 1, Config.MaxLevel)
			entry.Xp = entry.Xp or 0
			entry.Mut = Config.MutationsByName[entry.Mut] and entry.Mut or "Normal"
			data.Index[entry.Id] = true
		end
	end

	-- Warten bis die Gamepasses geprüft sind (für Slots / Multiplikator)
	Services.MonetizationService.LoadPasses(player)

	-- Offline-Einkommen
	if data.LastOnline > 0 then
		local offline = math.clamp(os.time() - data.LastOnline, 0, Config.OfflineMaxSeconds)
		local earned = math.floor(EconomyService.GetIncome(player) * offline * Config.OfflineIncomeRate)
		if earned > 0 then
			data.Pending += earned
			task.delay(3, function()
				EconomyService.Notify(
					player,
					"🌙 Offline verdient: " .. Util.FormatCash(earned) .. " – hol es am Collect-Pad!",
					"Success"
				)
			end)
		end
	end
	data.LastOnline = os.time()

	local plot = Services.PlotService.GetPlot(player)
	if plot then
		Services.PlotService.RenderAll(plot)
	end
	EconomyService.ApplySpeed(player)
	flush(player)

	local dailyReady = EconomyService.DailyStatus(data)
	if dailyReady then
		task.delay(5, function()
			EconomyService.Notify(player, "🎁 Dein Tagesbonus wartet! Klick auf 'Daily'.", "Info")
		end)
	end
end

function EconomyService.Init(services)
	Services = services
end

function EconomyService.Start()
	Services.DataService.OnProfileLoaded(onProfileLoaded)

	Remotes.Request.OnServerInvoke = function(player: Player, action: any, arg: any)
		if not requestLimiter.Check(player) then
			return { Ok = false, Message = "Langsam!" }
		end
		if type(action) ~= "string" then
			return { Ok = false }
		end
		local ok, message = false, "Unbekannt"
		if action == "Rebirth" then
			ok, message = EconomyService.Rebirth(player)
		elseif action == "BuySpeed" then
			local amount = type(arg) == "number" and arg or 1
			ok, message = EconomyService.BuySpeed(player, amount)
		elseif action == "Daily" then
			ok, message = EconomyService.ClaimDaily(player)
		elseif action == "Collect" then
			EconomyService.Collect(player)
			ok, message = true, ""
		elseif action == "Home" then
			Services.PlotService.TeleportHome(player)
			ok, message = true, ""
		end
		dirty[player] = true
		return { Ok = ok, Message = message }
	end

	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
		requestLimiter.Clear(player)
	end)

	-- Einkommen + Aufladen jede Sekunde
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in ipairs(Players:GetPlayers()) do
				local data = Services.DataService.Get(player)
				local plot = Services.PlotService.GetPlot(player)
				if data and plot then
					local chargeSpeed = Services.MonetizationService.HasPass(player, "FastCharge") and 2 or 1
					for key, entry in pairs(data.Meteors) do
						local slot = tonumber(key)
						if
							slot
							and entry.Lv < Config.MaxLevel
							and not Services.CarryService.IsSlotBeingStolen(plot, slot)
						then
							entry.Xp += chargeSpeed
							if entry.Xp >= Config.ChargeTime(entry.Lv) then
								entry.Xp = 0
								entry.Lv += 1
								Services.PlotService.RefreshSlot(plot, slot)
							end
						end
					end
					data.Pending += EconomyService.GetIncome(player)
					if Services.MonetizationService.HasPass(player, "AutoCollect") then
						local amount = math.floor(data.Pending)
						data.Pending -= amount
						EconomyService.AddCash(player, amount)
					end
					plot.CollectLabel.Text = "💰 " .. Util.FormatCash(data.Pending)
					dirty[player] = true
				end
			end
		end
	end)

	-- Gesammelte Änderungen max. 5x pro Sekunde an die Clients schicken
	task.spawn(function()
		while true do
			task.wait(0.2)
			for player in pairs(dirty) do
				dirty[player] = nil
				if player.Parent then
					flush(player)
				end
			end
		end
	end)
end

return EconomyService
