-- Geld & Fortschritt: Einkommen, Schlüpfen (Meteor -> Alien), Aufladen (Level), Einsammeln,
-- Verkaufen, Schritte/Speed, Rebirth, Tagesbonus, Index, Leaderstats und Daten an den Client.
-- Verteilt außerdem die Anfragen vom Client (Remotes.Request) – auch für Geschenke, Glücksrad,
-- Tagesaufgaben (RewardService), Gadgets (GadgetService) und Laufbänder (TreadmillService) –
-- und zählt Fortschritt für die Aufgaben.

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
-- true = Spielstand fertig eingerichtet (Pässe geprüft, Offline-Zeit verrechnet, Base angezeigt).
-- Vorher laufen weder Einkommen/Schlüpfen noch Käufe/Diebstähle.
local readyPlayers: { [Player]: boolean } = {}
local requestLimiter = Util.RateLimiter(8, 1)

-- Selten geänderte Teile des States (Index, Pässe, Statistik) nur bei Änderung mitschicken.
-- Der Client behält die alten Werte, wenn ein Feld fehlt. Ab und zu trotzdem alles (Sicherheitsnetz).
local FULL_STATE_INTERVAL = 20
local sentIndexCount: { [Player]: number } = {}
local sentPasses: { [Player]: string } = {}
local sentStats: { [Player]: string } = {}
local fullStateAt: { [Player]: number } = {}

local DELIVER_TIME = 0.9 -- so lange fliegt ein gekaufter Meteor in die Base (Client-Effekt)
local ULTRA_ANNOUNCE_RARITY = 5 -- ab Legendary wird ein Ultra-Alien allen angesagt
local REVEAL_RARITY = Config.RarityIndex.Epic or 4 -- ab Epic: große Schlüpf-Karte beim Besitzer
local LUCKY_PASS_MULT = 2 -- Gamepass "2x Glück": Selten/Ultra beim Schlüpfen doppelt so wahrscheinlich
local MAX_COIL_BONUS = 1 + (Config.SpeedCoilBonus or 0.3) -- Speed Coil: +30% (auch über MaxWalkSpeed)
local TIER_RANK = { Normal = 1, Selten = 2, Ultra = 3 }
-- "Alle Eier sofort schlüpfen": höchstens so viele Schlüpf-Explosionen an alle (sonst ruckelt es bei allen)
local HATCH_ALL_BURSTS = 3

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

-- Fortschritt für die Tagesaufgaben (RewardService) – ein Fehler dort darf Geld/Schlüpfen nie stoppen
local function track(player: Player, kind: string, amount: number)
	local rewards = Services.RewardService
	if rewards then
		local ok, err = pcall(rewards.Track, player, kind, amount)
		if not ok then
			warn("[EconomyService] RewardService.Track(" .. kind .. ") fehlgeschlagen: " .. tostring(err))
		end
	end
end

function EconomyService.MarkDirty(player: Player?)
	if player then
		dirty[player] = true
	end
end

-- Ist der Spielstand fertig geladen und eingerichtet? (für Käufe, Diebstähle, Einkommen)
function EconomyService.IsReady(player: Player): boolean
	return readyPlayers[player] == true
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

-- Tempo aus den Schritten (ohne Gadgets, ohne Tragen) – wird im HUD angezeigt
function EconomyService.GetSpeed(player: Player): number
	local data = Services.DataService.Get(player)
	local steps = data and data.Steps or 0
	return math.min(Config.MaxWalkSpeed, Config.StepsSpeed(steps))
end

-- Speed Coil (GadgetService): Faktor 1 .. 1.3, solange sie ausgerüstet ist
local function gadgetSpeedBonus(player: Player): number
	local gadgets = Services.GadgetService
	if not gadgets or type(gadgets.SpeedBonus) ~= "function" then
		return 1
	end
	local ok, bonus = pcall(gadgets.SpeedBonus, player)
	local factor = ok and tonumber(bonus) or 1
	if factor ~= factor then
		return 1
	end
	return math.clamp(factor, 1, MAX_COIL_BONUS)
end

-- Beim Tragen: Config.CarrySpeedFactor, seltene (schwere) Beute noch langsamer (Config.HeavyCarry),
-- mit Gamepass "Volle Speed beim Tragen" gar kein Abzug
local function carryFactor(player: Player): number
	if Services.MonetizationService.HasPass(player, "CarryFast") then
		return 1
	end
	local factor = Config.CarrySpeedFactor
	local heavy = Config.HeavyFactor(Services.CarryService.CarriedEntry(player))
	if heavy then
		factor = math.min(factor, heavy)
	end
	return factor
end

-- Speed-Pad im Nester-Feld (FieldService setzt das Attribut "SpeedPadUntil" = Serverzeit): Faktor 1 .. 1.5
local function padSpeedBonus(player: Player): number
	local untilTime = tonumber(player:GetAttribute("SpeedPadUntil")) or 0
	if untilTime <= workspace:GetServerTimeNow() then
		return 1
	end
	return 1 + math.clamp(tonumber(Config.SpeedPads and Config.SpeedPads.Boost) or 0, 0, 1)
end

-- Echte Laufgeschwindigkeit: Schritte-Tempo x Speed Coil (Deckel MaxWalkSpeed * 1.3)
-- x Speed-Pad (Deckel Config.SpeedPads.MaxSpeed), beim Tragen langsamer
function EconomyService.GetWalkSpeed(player: Player, carrying: boolean): number
	local speed = EconomyService.GetSpeed(player)
	local bonus = gadgetSpeedBonus(player)
	if bonus > 1 then
		speed = math.min(speed * bonus, Config.MaxWalkSpeed * MAX_COIL_BONUS)
	end
	local pad = padSpeedBonus(player)
	if pad > 1 then
		local cap = tonumber(Config.SpeedPads and Config.SpeedPads.MaxSpeed) or 120
		speed = math.max(speed, math.min(speed * pad, cap))
	end
	if carrying then
		speed = math.max(8, speed * carryFactor(player))
	end
	return speed
end

-- Admin-Speed-Regler (Attribut AdminSpeed, nur für echte Admins): ersetzt das normale Tempo
local function adminSpeed(player: Player): number?
	local value = tonumber(player:GetAttribute("AdminSpeed"))
	if not value or value ~= value then
		return nil
	end
	local admin = Services.AdminService
	if not admin or not admin.IsAdmin(player) then
		return nil
	end
	local powers = Config.AdminPowers or {}
	return math.clamp(value, tonumber(powers.MinSpeed) or 8, tonumber(powers.MaxSpeed) or 250)
end

function EconomyService.ApplySpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local speed = adminSpeed(player) or EconomyService.GetWalkSpeed(player, Services.CarryService.IsCarrying(player))
	if humanoid.WalkSpeed ~= speed then
		humanoid.WalkSpeed = speed
	end
end

-- Schritte gutschreiben (Laufband, Produkte, Belohnungen). Passt die Laufgeschwindigkeit an.
-- (Die Tagesaufgabe "Lauf X Schritte" zählt der TreadmillService – gekaufte Schritte zählen nicht.)
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
	track(player, "Collect", amount)
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
	-- Neuer Index-Stand -> vielleicht ein besserer Schläger (CarryService tauscht ihn aus)
	local carry = Services.CarryService
	if carry and carry.CheckBat then
		task.defer(carry.CheckBat, player)
	end
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
-- Glück beim Schlüpfen: Server-Glück/Schauer (baseLuck) x2 mit Gamepass "2x Glück"
function EconomyService.HatchLuck(player: Player, baseLuck: number?): number
	local luck = baseLuck or Services.MeteorService.GetLuck()
	if Services.MonetizationService.HasPass(player, "Lucky") then
		luck *= LUCKY_PASS_MULT
	end
	return luck
end

-- Wertung fürs "beste" Alien (Seltenheit vor Stufe)
local function alienScore(def, tier: string): number
	return (def and Config.RarityIndex[def.Rarity] or 0) * 10 + (TIER_RANK[tier] or 1)
end

-- Stelle der Schlüpf-Explosion über einem Slot
local function hatchPosition(plot, slot: number): Vector3
	return Services.PlotService.SlotTopCFrame(plot, slot).Position + Vector3.new(0, 2, 0)
end

-- Meteor in Slot schlüpft jetzt -> Alien würfeln, Index, Effekt, neu anzeigen. Gibt die Alien-Id zurück.
-- quiet = keine Einzel-Nachrichten/-Karten/-Explosionen (z.B. "Alle Eier sofort schlüpfen" meldet gesammelt)
function EconomyService.Hatch(player: Player, plot, slot: number, entry, luck: number?, quiet: boolean?): string
	local alienId = Aliens.Roll(entry.Id, EconomyService.HatchLuck(player, luck))
	entry.Alien = alienId
	entry.Hatch = 0
	entry.Lv = math.max(1, tonumber(entry.Lv) or 1)
	entry.Xp = 0
	dirty[player] = true

	local alien = Aliens.ById[alienId]
	local def = Config.MeteorsById[entry.Id]
	Services.PlotService.RenderSlot(plot, slot)
	if not quiet then
		EconomyService.EffectAll(
			"Hatch",
			0,
			{ Position = hatchPosition(plot, slot), Rarity = def and def.Rarity or "Common" }
		)
	end

	local name = alien and alien.Name or alienId
	local tier = alien and alien.Tier or "Normal"
	if not quiet then
		local tierText = tier == "Ultra" and "🌟 ULTRA " or (tier == "Selten" and "✨ Selten: " or "")
		EconomyService.Notify(player, "🐣 Geschlüpft: " .. tierText .. name .. "!", "Success")
		-- Große Karte in der Bildschirmmitte (mit Konfetti) ab Epic oder bei Selten/Ultra
		if tier ~= "Normal" or (def and (Config.RarityIndex[def.Rarity] or 0) >= REVEAL_RARITY) then
			EconomyService.Effect(player, "HatchReveal", 0, { AlienId = alienId, Mut = entry.Mut })
		end
	end
	if tier == "Ultra" and def and Config.RarityIndex[def.Rarity] >= ULTRA_ANNOUNCE_RARITY then
		EconomyService.NotifyAll(
			"🌟 " .. player.DisplayName .. " hat ein ULTRA " .. name .. " ausgebrütet!",
			"Event"
		)
	end
	EconomyService.Discover(player, alienId, quiet)
	track(player, "Hatch", 1)
	return alienId
end

-- Alle Eier in der Base schlüpfen sofort (Produkt "🐣 Alle Eier sofort schlüpfen").
-- Eine Sammel-Nachricht + große Karte fürs beste Alien statt vieler Einzel-Nachrichten.
-- Gibt die Anzahl der geschlüpften Aliens zurück (0 = keine Eier in der Base).
function EconomyService.HatchAll(player: Player): number
	local data = Services.DataService.Get(player)
	local plot = Services.PlotService.GetPlot(player)
	if not data or not plot then
		return 0
	end
	local luck = Services.MeteorService.GetLuck()
	local indexBefore = EconomyService.IndexCount(data)
	local count = 0
	local bestId, bestMut, bestScore = nil, nil, -1
	local bursts: { { Position: Vector3, Rarity: string, Score: number } } = {}
	for key, entry in pairs(data.Meteors) do
		local slot = tonumber(key)
		if slot and entry.Alien == nil and not Services.CarryService.IsSlotBeingStolen(plot, slot) then
			local alienId = EconomyService.Hatch(player, plot, slot, entry, luck, true)
			count += 1
			local alien = Aliens.ById[alienId]
			local def = Config.MeteorsById[entry.Id]
			local score = alienScore(def, alien and alien.Tier or "Normal")
			if score > bestScore then
				bestId, bestMut, bestScore = alienId, entry.Mut, score
			end
			table.insert(bursts, {
				Position = hatchPosition(plot, slot),
				Rarity = def and def.Rarity or "Common",
				Score = score,
			})
		end
	end
	-- Nur die besten paar Explosionen an alle schicken (18 auf einmal = Ruckeln bei jedem Spieler)
	table.sort(bursts, function(a, b)
		return a.Score > b.Score
	end)
	for i = 1, math.min(HATCH_ALL_BURSTS, #bursts) do
		EconomyService.EffectAll("Hatch", 0, { Position = bursts[i].Position, Rarity = bursts[i].Rarity })
	end
	if count > 0 then
		local discovered = EconomyService.IndexCount(data) - indexBefore
		EconomyService.Notify(
			player,
			"🐣 "
				.. (count == 1 and "1 Alien ist" or (count .. " Aliens sind"))
				.. " geschlüpft!"
				.. (discovered > 0 and (" 📖 " .. discovered .. " neu im Index!") or ""),
			"Success"
		)
		if bestId then
			EconomyService.Effect(player, "HatchReveal", 0, { AlienId = bestId, Mut = bestMut })
		end
	end
	return count
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
-- Besessene Gadgets als Liste von Ids (Reihenfolge wie in Config.Gadgets)
local function ownedGadgets(data): { string }
	local list = {}
	local gadgets = data.Gadgets
	if type(gadgets) == "table" then
		for _, def in ipairs(Config.Gadgets) do
			if gadgets[def.Id] == true then
				table.insert(list, def.Id)
			end
		end
	end
	return list
end

local function buildState(player: Player)
	local data = Services.DataService.Get(player)
	if not data then
		return nil
	end
	local plot = Services.PlotService.GetPlot(player)
	local dailyReady, dailyIn = EconomyService.DailyStatus(data)
	local indexCount = EconomyService.IndexCount(data)
	local best = Config.BestTreadmill(data.Treadmills)
	local bat, nextBat = Config.BestBat(indexCount)
	local treadmills = {}
	for _, def in ipairs(Config.Treadmills) do
		if Config.OwnsTreadmill(data.Treadmills, def.Id) then
			table.insert(treadmills, def.Id)
		end
	end
	local state = {
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
		Treadmills = treadmills, -- gekaufte Laufbänder (Ids)
		Bat = bat and bat.Id or nil, -- bester freigeschalteter Schläger
		NextBat = nextBat and nextBat.Id or nil,
		IndexCount = indexCount,
		Slots = Services.PlotService.SlotCount(player),
		UsedSlots = Services.PlotService.UsedSlots(player),
		DailyReady = dailyReady,
		DailyIn = dailyIn,
		Streak = data.Daily.Streak,
		IndexBonus = indexCount * Config.IndexBonusPerAlien,
		Carrying = Services.CarryService.IsCarrying(player),
		HasPlot = plot ~= nil,
		TotalEarned = data.TotalEarned,
		Gadgets = ownedGadgets(data),
		StarterBought = data.StarterBought == true,
		BaseFloors = tonumber(data.BaseFloors) or 1, -- 🏠 gekaufte Stockwerke
		BaseLook = tonumber(data.BaseLook) or 1, -- 🏠 Base-Look-Stufe
	}
	-- Selten geänderte Teile nur bei Änderung (oder alle FULL_STATE_INTERVAL Sekunden alles)
	local clock = os.clock()
	local full = clock - (fullStateAt[player] or -math.huge) >= FULL_STATE_INTERVAL
	if full then
		fullStateAt[player] = clock
	end

	-- 🎁 Geschenke, 🎡 Glücksrad (Spins, FreeSpinIn), 📜 Aufgaben – ein Fehler dort darf den State nie stoppen.
	-- (Geschenke/Aufgaben schickt der RewardService auch nur bei Änderung bzw. wenn full = true.)
	local rewards = Services.RewardService
	if rewards then
		local ok, err = pcall(rewards.FillState, player, data, state, full)
		if not ok then
			warn("[EconomyService] Belohnungs-Daten fehlgeschlagen: " .. tostring(err))
		end
	end

	-- Index, Pässe und Statistik nur bei Änderung (oder wenn full = true)
	if full or sentIndexCount[player] ~= indexCount then
		-- Der Index wächst nur (Reset leert ihn) -> die Anzahl reicht als Änderungs-Merkmal
		sentIndexCount[player] = indexCount
		local index = {}
		for id in pairs(data.Index) do
			if Aliens.ById[id] then
				table.insert(index, id)
			end
		end
		state.Index = index
	end
	local passKey = ""
	for _, pass in ipairs(Config.GamePasses) do
		passKey ..= Services.MonetizationService.HasPass(player, pass.Key) and "1" or "0"
	end
	if full or sentPasses[player] ~= passKey then
		sentPasses[player] = passKey
		local passes = {}
		for _, pass in ipairs(Config.GamePasses) do
			passes[pass.Key] = Services.MonetizationService.HasPass(player, pass.Key)
		end
		state.Passes = passes
	end
	local stats = data.Stats
	local statsKey = ("%s|%s|%s|%s"):format(
		tostring(stats.Stolen),
		tostring(stats.Robbed),
		tostring(stats.Bought),
		tostring(stats.RobuxSpent)
	)
	if full or sentStats[player] ~= statsKey then
		sentStats[player] = statsKey
		state.Stats = stats
	end
	return state
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

	-- Zeitpunkt des letzten Besuchs VOR dem Warten merken (ein Auto-Save setzt LastOnline neu)
	local lastOnline = data.LastOnline

	-- Warten bis die Gamepasses geprüft sind (für Slots / Multiplikator / Schlüpf-Tempo).
	-- Bis "ready" gesetzt ist, laufen weder Einkommen noch Schlüpfen, Käufe oder Diebstähle.
	Services.MonetizationService.LoadPasses(player)
	if not player.Parent then
		return
	end

	-- Offline: Schlüpfzeit vergeht auch ohne dich
	local offline = lastOnline > 0 and math.max(0, os.time() - lastOnline) or 0
	local hatchedOffline = 0
	if offline > 0 then
		local speed = Services.PlotService.HatchSpeed(player)
		local luck = EconomyService.HatchLuck(player, 1) -- ohne Server-Glück, aber mit "2x Glück"-Pass
		for _, entry in pairs(data.Meteors) do
			if entry.Alien == nil then
				entry.Hatch = math.max(0, entry.Hatch - offline * speed)
				if entry.Hatch <= 0 then
					entry.Alien = Aliens.Roll(entry.Id, luck)
					entry.Hatch = 0
					entry.Xp = 0
					EconomyService.Discover(player, entry.Alien, true)
					hatchedOffline += 1
				end
			end
		end
	end

	-- Offline-Einkommen
	if lastOnline > 0 then
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
		track(player, "Hatch", hatchedOffline)
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
	readyPlayers[player] = true
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
		if amount > 0 then
			track(player, "Collect", amount) -- Auto Collect zählt fürs "Sammle $X ein"
		end
	end
	Services.PlotService.SetCollectText(plot, data.Pending)
	dirty[player] = true
end

-- Eingefroren (Falle / Admin-Freeze = HumanoidRootPart verankert)? Dann kein Teleport (Home, Laufbänder)
local function isFrozen(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and root:IsA("BasePart") and root.Anchored
end

-- Gadget mit Cash kaufen (GadgetService prüft Cash, zieht ab, gibt das Tool)
local function buyGadget(player: Player, id: any): (boolean, string)
	local gadgets = Services.GadgetService
	if type(id) ~= "string" or #id > 40 then
		return false, "Unbekanntes Gadget"
	end
	if not gadgets or type(gadgets.Buy) ~= "function" then
		return false, "🛠️ Gadgets kommen bald!"
	end
	local ok, success, message = pcall(gadgets.Buy, player, id)
	if not ok then
		warn("[EconomyService] Gadget-Kauf fehlgeschlagen: " .. tostring(success))
		return false, "Kauf fehlgeschlagen – versuch es nochmal"
	end
	return success == true, type(message) == "string" and message or ""
end

function EconomyService.Init(services)
	Services = services
end

function EconomyService.Start()
	Services.DataService.OnProfileLoaded(onProfileLoaded)

	-- Anfragen vom Client. Antwort: { Ok, Message, ...Extras } (z.B. Segment beim Glücksrad)
	Remotes.Request.OnServerInvoke = function(player: Player, action: any, arg: any)
		if not requestLimiter.Check(player) then
			return { Ok = false, Message = "Langsam! 🐢" }
		end
		if type(action) ~= "string" then
			return { Ok = false, Message = "Unbekannt" }
		end
		if not readyPlayers[player] then
			return { Ok = false, Message = "Lädt noch... ⏳" }
		end
		local ok, message = false, "Unbekannt"
		local extra: { [string]: any }? = nil
		local rewards = Services.RewardService
		local rewardAction = action == "ClaimGift"
			or action == "Spin"
			or action == "ClaimQuest"
			or action == "RerollQuest"
		if rewardAction and not rewards then
			ok, message = false, "🎁 Belohnungen kommen bald!"
		elseif action == "ClaimGift" then
			ok, message = rewards.ClaimGift(player, arg)
		elseif action == "Spin" then
			ok, message, extra = rewards.Spin(player)
		elseif action == "ClaimQuest" then
			ok, message = rewards.ClaimQuest(player, arg)
		elseif action == "RerollQuest" then
			ok, message = rewards.RerollQuest(player, arg)
		elseif action == "BuyGadget" then
			ok, message = buyGadget(player, arg)
		elseif action == "BuyTreadmill" then
			local treadmill = Services.TreadmillService
			if treadmill and treadmill.Buy then
				local called, success, text = pcall(treadmill.Buy, player, arg)
				if called then
					ok, message = success == true, type(text) == "string" and text or ""
				else
					warn("[EconomyService] Laufband-Kauf fehlgeschlagen: " .. tostring(success))
					ok, message = false, "Kauf fehlgeschlagen – versuch es nochmal"
				end
			else
				ok, message = false, "Laufbänder kommen bald!"
			end
		elseif action == "BuyFloor" then
			ok, message = Services.PlotService.BuyFloor(player)
		elseif action == "BuyBaseLook" then
			ok, message = Services.PlotService.BuyBaseLook(player)
		elseif action == "Rebirth" then
			ok, message = EconomyService.Rebirth(player)
		elseif action == "Daily" then
			ok, message = EconomyService.ClaimDaily(player)
		elseif action == "Collect" then
			-- nur in der eigenen Base (sonst wäre es ein Gratis-"Auto Collect" von überall)
			local plot = Services.PlotService.GetPlot(player)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if plot and root and Services.PlotService.IsInside(plot, root.Position) then
				EconomyService.Collect(player)
				ok, message = true, ""
			else
				ok, message = false, "🏠 Einsammeln geht nur in deiner Base!"
			end
		elseif action == "Home" then
			if Services.CarryService.IsCarrying(player) then
				ok, message = false, "Mit Beute musst du laufen! 🏃"
			elseif isFrozen(player) then
				ok, message = false, "🧊 Du bist eingefroren!"
			else
				Services.PlotService.TeleportHome(player)
				ok, message = true, ""
			end
		elseif action == "Treadmills" then
			if Services.CarryService.IsCarrying(player) then
				ok, message = false, "Mit Beute musst du laufen! 🏃"
			elseif isFrozen(player) then
				ok, message = false, "🧊 Du bist eingefroren!"
			elseif Services.PlotService.TeleportToTreadmills(player) then
				ok, message = true, "🏃 Ab aufs Laufband!"
			else
				ok, message = false, "Kein Charakter"
			end
		elseif action == "GoRun" then
			-- ☄️ Meteor-Run: zum Start-Tor (RunService prüft Tragen, Einfrieren, Charakter)
			local run = Services.RunService
			if run then
				ok, message = run.Teleport(player)
			else
				ok, message = false, "☄️ Der Meteor-Run kommt bald!"
			end
		end
		dirty[player] = true
		local response: { [string]: any } = { Ok = ok, Message = message }
		if extra then
			for key, value in pairs(extra) do
				if response[key] == nil then
					response[key] = value
				end
			end
		end
		return response
	end

	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
		readyPlayers[player] = nil
		sentIndexCount[player] = nil
		sentPasses[player] = nil
		sentStats[player] = nil
		fullStateAt[player] = nil
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
				if data and plot and readyPlayers[player] then
					local ok, err = pcall(tickPlayer, player, data, plot, dt)
					if not ok then
						warn("[EconomyService] Tick-Fehler bei " .. player.Name .. ": " .. tostring(err))
					end
				end
			end
		end
	end)

	-- Gesammelte Änderungen max. 5x pro Sekunde an die Clients schicken.
	-- Erst eine Liste machen: flush -> RewardService.FillState kann MarkDirty aufrufen (z.B. neue
	-- Tagesaufgaben um Mitternacht) – neue Einträge während pairs(dirty) wären nicht erlaubt.
	local flushList: { Player } = {}
	task.spawn(function()
		while true do
			task.wait(0.2)
			table.clear(flushList)
			for player in pairs(dirty) do
				table.insert(flushList, player)
			end
			table.clear(dirty)
			for _, player in ipairs(flushList) do
				if player.Parent then
					local ok, err = pcall(flush, player)
					if not ok then
						warn("[EconomyService] State-Fehler bei " .. player.Name .. ": " .. tostring(err))
					end
				end
			end
		end
	end)
end

return EconomyService
