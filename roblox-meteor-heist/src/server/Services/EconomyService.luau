-- Geld & Fortschritt: Einkommen, Schlüpfen (Meteor -> Alien), Aufladen (Level), Einsammeln,
-- Verkaufen, Schritte/Speed, Rebirth, Tagesbonus, Index, Leaderstats und Daten an den Client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))
local Aliens = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Aliens"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local MeteorFactory = require(script.Parent:WaitForChild("MeteorFactory"))

local EconomyService = {}
local Services

local dirty: { [Player]: boolean } = {}
local requestLimiter = Util.RateLimiter(8, 1)

local DELIVER_TIME = 0.9 -- so lange fliegt ein gekaufter Meteor in die Base (Client-Effekt)
local ULTRA_ANNOUNCE_RARITY = 5 -- ab Legendary wird ein Ultra-Alien allen angesagt

-- -------------------------------------------------------------------
-- NACHRICHTEN & EFFEKTE
-- -------------------------------------------------------------------
function EconomyService.Notify(player: Player?, text: string, kind: string?)
	if player and player.Parent then
		Remotes.Notify:FireClient(player, text, kind or "Info")
	end
end

function EconomyService.NotifyAll(text: string, kind: string?)
	Remotes.Notify:FireAllClients(text, kind or "Info")
end

-- Effekt für einen Spieler: name, strength, data (optional, z.B. Positionen)
function EconomyService.Effect(player: Player?, name: string, strength: number?, data: any?)
	if player and player.Parent then
		Remotes.Effect:FireClient(player, name, strength or 1, data)
	end
end

-- Effekt für alle Spieler (z.B. "Deliver", "Hatch")
function EconomyService.EffectAll(name: string, strength: number?, data: any?)
	Remotes.Effect:FireAllClients(name, strength or 1, data)
end

function EconomyService.MarkDirty(player: Player?)
	if player then
		dirty[player] = true
	end
end

-- -------------------------------------------------------------------
-- RECHNEN
-- -------------------------------------------------------------------
-- Anzahl entdeckter Aliens (nur gültige Alien-Ids zählen)
function EconomyService.IndexCount(data): number
	local count = 0
	for id in pairs(data.Index) do
		if Aliens.ById[id] then
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
	local bonus = 1 + EconomyService.IndexCount(data) * Config.IndexBonusPerAlien
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

-- Schritte-Multiplikator: 2x mit Gamepass "2x Schritte", +25% pro Rebirth
function EconomyService.GetStepsMult(player: Player): number
	local data = Services.DataService.Get(player)
	local rebirths = data and data.Rebirths or 0
	local pass = Services.MonetizationService.HasPass(player, "SpeedBoots") and 2 or 1
	return pass * (1 + Config.StepsPerRebirth * rebirths)
end

function EconomyService.GetSpeed(player: Player): number
	local data = Services.DataService.Get(player)
	local steps = data and data.Steps or 0
	return math.min(Config.MaxWalkSpeed, Config.StepsSpeed(steps))
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
	if humanoid.WalkSpeed ~= speed then
		humanoid.WalkSpeed = speed
	end
end

-- Schritte gutschreiben (Laufband, Produkte, Admin). Passt die Laufgeschwindigkeit an.
function EconomyService.AddSteps(player: Player, amount: number)
	local data = Services.DataService.Get(player)
	if not data or amount ~= amount or amount == math.huge then
		return
	end
	local before = Config.StepsSpeed(data.Steps)
	data.Steps = math.clamp(data.Steps + amount, 0, 1e30)
	if Config.StepsSpeed(data.Steps) ~= before then
		EconomyService.ApplySpeed(player)
	end
	dirty[player] = true
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
		Services.PlotService.SetCollectText(plot, data.Pending)
	end
end

-- Neues Alien im Index? (silent = keine Einzel-Nachricht, z.B. beim Laden)
function EconomyService.Discover(player: Player, alienId: string?, silent: boolean?): boolean
	local data = Services.DataService.Get(player)
	local alien = alienId and Aliens.ById[alienId]
	if not data or not alien or data.Index[alien.Id] then
		return false
	end
	data.Index[alien.Id] = true
	if not silent then
		EconomyService.Notify(
			player,
			"📖 NEU im Index: "
				.. alien.Name
				.. "! (+"
				.. math.floor(Config.IndexBonusPerAlien * 100 + 0.5)
				.. "% Einkommen)",
			"Success"
		)
	end
	dirty[player] = true
	return true
end

-- Legt einen Meteor in einen Slot. Mit fromPosition fliegt er sichtbar dorthin (Client-Effekt)
-- und erscheint erst nach der Flugzeit. entry.Alien gesetzt + gültig -> schon geschlüpft.
function EconomyService.DeliverMeteor(player: Player, plot, slot: number, entry, fromPosition: Vector3?)
	local data = Services.DataService.Get(player)
	if not data or not Config.MeteorsById[entry.Id] then
		return nil
	end
	local key = tostring(slot)
	local newEntry = {
		Id = entry.Id,
		Mut = Config.MutationsByName[entry.Mut] and entry.Mut or "Normal",
		Lv = math.clamp(math.floor(tonumber(entry.Lv) or 1), 1, Config.MaxLevel),
		Xp = 0,
		Hatch = Config.HatchTime(entry.Id),
		Alien = nil :: string?,
	}
	if entry.Alien ~= nil and Aliens.ById[entry.Alien] then
		newEntry.Alien = entry.Alien
		newEntry.Hatch = 0
	end
	data.Meteors[key] = newEntry
	dirty[player] = true
	if newEntry.Alien then
		EconomyService.Discover(player, newEntry.Alien)
	end

	if fromPosition then
		local top = Services.PlotService.SlotTopCFrame(plot, slot).Position
		local to = top + Vector3.new(0, MeteorFactory.GetSize(newEntry) / 2, 0)
		EconomyService.EffectAll("Deliver", 0, {
			From = fromPosition,
			To = to,
			MeteorId = newEntry.Id,
			Mut = newEntry.Mut,
		})
		task.delay(DELIVER_TIME, function()
			-- nur anzeigen, wenn der Eintrag noch derselbe ist (nicht verkauft, Rebirth, verlassen ...)
			local current = Services.DataService.Get(player)
			if plot.Owner == player and current and current.Meteors[key] == newEntry then
				Services.PlotService.RenderSlot(plot, slot)
			end
		end)
	else
		Services.PlotService.RenderSlot(plot, slot)
	end
	return newEntry
end

-- Meteor direkt in die Base legen (Admin, Produkte). Gibt true zurück, wenn Platz war.
-- fly = true -> fliegt vom Himmel in den Slot
function EconomyService.GiveMeteor(player: Player, entry, fly: boolean?): boolean
	local plot = Services.PlotService.GetPlot(player)
	local slot = Services.PlotService.FreeSlot(player)
	if not plot or not slot or not Config.MeteorsById[entry.Id] then
		return false
	end
	local from = nil
	if fly then
		local top = Services.PlotService.SlotTopCFrame(plot, slot).Position
		from = top + Vector3.new(math.random(-40, 40), 180, math.random(-40, 40))
	end
	return EconomyService.DeliverMeteor(player, plot, slot, entry, from) ~= nil
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
	EconomyService.Notify(player, "💰 Verkauft für " .. Util.FormatCash(value), "Success")
end

-- -------------------------------------------------------------------
-- SCHLÜPFEN
-- -------------------------------------------------------------------
-- Meteor in Slot schlüpft jetzt -> Alien würfeln, Index, Effekt, neu anzeigen
function EconomyService.Hatch(player: Player, plot, slot: number, entry, luck: number?)
	local alienId = Aliens.Roll(entry.Id, luck or Services.MeteorService.GetLuck())
	entry.Alien = alienId
	entry.Hatch = 0
	entry.Lv = math.max(1, tonumber(entry.Lv) or 1)
	entry.Xp = 0
	dirty[player] = true

	local alien = Aliens.ById[alienId]
	local def = Config.MeteorsById[entry.Id]
	local position = Services.PlotService.SlotTopCFrame(plot, slot).Position + Vector3.new(0, 2, 0)
	Services.PlotService.RenderSlot(plot, slot)
	EconomyService.EffectAll("Hatch", 0, { Position = position, Rarity = def and def.Rarity or "Common" })

	local name = alien and alien.Name or alienId
	local tier = alien and alien.Tier or "Normal"
	local tierText = tier == "Ultra" and "🌟 ULTRA " or (tier == "Selten" and "✨ Selten: " or "")
	EconomyService.Notify(player, "🐣 Geschlüpft: " .. tierText .. name .. "!", "Success")
	if tier ~= "Normal" then
		EconomyService.Effect(player, "Confetti", tier == "Ultra" and 2 or 1)
	end
	if tier == "Ultra" and def and Config.RarityIndex[def.Rarity] >= ULTRA_ANNOUNCE_RARITY then
		EconomyService.NotifyAll(
			"🌟 " .. player.DisplayName .. " hat ein ULTRA " .. name .. " ausgebrütet!",
			"Event"
		)
	end
	EconomyService.Discover(player, alienId)
end

-- -------------------------------------------------------------------
-- REBIRTH / DAILY
-- -------------------------------------------------------------------
function EconomyService.Rebirth(player: Player): (boolean, string)
	local data = Services.DataService.Get(player)
	if not data then
		return false, "Lädt noch..."
	end
	if Services.CarryService.IsCarrying(player) then
		return false, "Bring erst deine Beute nach Hause! 🏃"
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
		Services.PlotService.SetCollectText(plot, 0)
	end
	dirty[player] = true
	EconomyService.NotifyAll("🔥 " .. player.DisplayName .. " hat Rebirth " .. data.Rebirths .. " erreicht!", "Event")
	EconomyService.Effect(player, "Confetti", 2)
	return true,
		"🔥 Rebirth! Jetzt "
			.. Util.FormatNumber(EconomyService.GetMultiplier(player) * 100)
			.. "% Einkommen und x"
			.. Util.FormatNumber(EconomyService.GetStepsMult(player))
			.. " Schritte"
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
		return false, "⏰ Nächster Bonus in " .. Util.FormatTime(remaining)
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
		if Aliens.ById[id] then
			table.insert(index, id)
		end
	end
	local best = Config.BestTreadmill(data.Steps)
	return {
		Cash = data.Cash,
		Pending = data.Pending,
		Income = EconomyService.GetIncome(player),
		Multiplier = EconomyService.GetMultiplier(player),
		Rebirths = data.Rebirths,
		RebirthCost = Config.RebirthCost(data.Rebirths),
		Steps = data.Steps,
		StepsMult = EconomyService.GetStepsMult(player),
		Speed = EconomyService.GetSpeed(player),
		BestTreadmill = best and best.Id or nil,
		Slots = Services.PlotService.SlotCount(player),
		UsedSlots = Services.PlotService.UsedSlots(player),
		DailyReady = dailyReady,
		DailyIn = dailyIn,
		Streak = data.Daily.Streak,
		Index = index,
		IndexBonus = #index * Config.IndexBonusPerAlien,
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
		local text = Util.FormatCash(data.Cash)
		if cash.Value ~= text then
			cash.Value = text
		end
	end
	if rebirths and rebirths.Value ~= data.Rebirths then
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

	-- Spielstand reparieren (gelöschte Meteor-Typen entfernen, Slots kappen, Felder prüfen)
	local maxSlots = Services.PlotService.MaxSlots
	for key, entry in pairs(data.Meteors) do
		local slot = tonumber(key)
		if not slot or not Config.MeteorsById[entry.Id] or slot < 1 or slot > maxSlots or slot % 1 ~= 0 then
			data.Meteors[key] = nil
		else
			entry.Lv = math.clamp(math.floor(tonumber(entry.Lv) or 1), 1, Config.MaxLevel)
			entry.Xp = tonumber(entry.Xp) or 0
			entry.Mut = Config.MutationsByName[entry.Mut] and entry.Mut or "Normal"
			entry.Hatch = math.max(0, tonumber(entry.Hatch) or 0)
			if entry.Alien ~= nil then
				data.Index[entry.Alien] = true
			end
		end
	end

	-- Warten bis die Gamepasses geprüft sind (für Slots / Multiplikator / Schlüpf-Tempo)
	Services.MonetizationService.LoadPasses(player)
	if not player.Parent then
		return
	end

	-- Offline: Schlüpfzeit vergeht auch ohne dich
	local offline = data.LastOnline > 0 and math.max(0, os.time() - data.LastOnline) or 0
	local hatchedOffline = 0
	if offline > 0 then
		local speed = Services.PlotService.HatchSpeed(player)
		for _, entry in pairs(data.Meteors) do
			if entry.Alien == nil then
				entry.Hatch = math.max(0, entry.Hatch - offline * speed)
				if entry.Hatch <= 0 then
					entry.Alien = Aliens.Roll(entry.Id, 1)
					entry.Hatch = 0
					entry.Xp = 0
					EconomyService.Discover(player, entry.Alien, true)
					hatchedOffline += 1
				end
			end
		end
	end

	-- Offline-Einkommen
	if data.LastOnline > 0 then
		local seconds = math.clamp(offline, 0, Config.OfflineMaxSeconds)
		local earned = math.floor(EconomyService.GetIncome(player) * seconds * Config.OfflineIncomeRate)
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
	if hatchedOffline > 0 then
		task.delay(4, function()
			EconomyService.Notify(
				player,
				"🐣 Während du weg warst, "
					.. (hatchedOffline == 1 and "ist 1 Alien" or ("sind " .. hatchedOffline .. " Aliens"))
					.. " geschlüpft!",
				"Success"
			)
		end)
	end
	data.LastOnline = os.time()

	local plot = Services.PlotService.GetPlot(player)
	if plot then
		Services.PlotService.RenderAll(plot)
		Services.PlotService.SetCollectText(plot, data.Pending)
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

-- Etwa jede Sekunde: Schlüpfen, Aufladen (Level) und Einkommen für einen Spieler.
-- dt = echte vergangene Zeit -> der Schlüpf-Countdown beim Client (HatchAt) bleibt genau.
local function tickPlayer(player: Player, data, plot, dt: number)
	local Monetization = Services.MonetizationService
	local speed = (Monetization.HasPass(player, "FastCharge") and 2 or 1) * dt
	local luck = nil
	for key, entry in pairs(data.Meteors) do
		local slot = tonumber(key)
		if slot and not Services.CarryService.IsSlotBeingStolen(plot, slot) then
			if entry.Alien == nil then
				entry.Hatch -= speed
				if entry.Hatch <= 0 then
					luck = luck or Services.MeteorService.GetLuck()
					EconomyService.Hatch(player, plot, slot, entry, luck)
				end
			elseif entry.Lv < Config.MaxLevel then
				entry.Xp += speed
				if entry.Xp >= Config.ChargeTime(entry.Lv) then
					entry.Xp = 0
					entry.Lv += 1
					Services.PlotService.RefreshSlot(plot, slot)
				end
			end
		end
	end
	data.Pending += EconomyService.GetIncome(player) * dt
	if Monetization.HasPass(player, "AutoCollect") then
		local amount = math.floor(data.Pending)
		data.Pending -= amount
		EconomyService.AddCash(player, amount)
	end
	Services.PlotService.SetCollectText(plot, data.Pending)
	dirty[player] = true
end

function EconomyService.Init(services)
	Services = services
end

function EconomyService.Start()
	Services.DataService.OnProfileLoaded(onProfileLoaded)

	Remotes.Request.OnServerInvoke = function(player: Player, action: any, _arg: any)
		if not requestLimiter.Check(player) then
			return { Ok = false, Message = "Langsam! 🐢" }
		end
		if type(action) ~= "string" then
			return { Ok = false, Message = "Unbekannt" }
		end
		local ok, message = false, "Unbekannt"
		if action == "Rebirth" then
			ok, message = EconomyService.Rebirth(player)
		elseif action == "Daily" then
			ok, message = EconomyService.ClaimDaily(player)
		elseif action == "Collect" then
			EconomyService.Collect(player)
			ok, message = true, ""
		elseif action == "Home" then
			if Services.CarryService.IsCarrying(player) then
				ok, message = false, "Mit Beute musst du laufen! 🏃"
			else
				Services.PlotService.TeleportHome(player)
				ok, message = true, ""
			end
		elseif action == "Treadmills" then
			if Services.CarryService.IsCarrying(player) then
				ok, message = false, "Mit Beute musst du laufen! 🏃"
			elseif Services.PlotService.TeleportToTreadmills(player) then
				ok, message = true, "🏃 Ab aufs Laufband!"
			else
				ok, message = false, "Kein Charakter"
			end
		end
		dirty[player] = true
		return { Ok = ok, Message = message }
	end

	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
		requestLimiter.Clear(player)
	end)

	-- Schlüpfen + Einkommen + Aufladen jede Sekunde
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(1)
			local clock = os.clock()
			local dt = math.clamp(clock - last, 0, 5) -- nach einem Hänger nicht zu viel auf einmal
			last = clock
			for _, player in ipairs(Players:GetPlayers()) do
				local data = Services.DataService.Get(player)
				local plot = Services.PlotService.GetPlot(player)
				if data and plot then
					local ok, err = pcall(tickPlayer, player, data, plot, dt)
					if not ok then
						warn("[EconomyService] Tick-Fehler bei " .. player.Name .. ": " .. tostring(err))
					end
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
