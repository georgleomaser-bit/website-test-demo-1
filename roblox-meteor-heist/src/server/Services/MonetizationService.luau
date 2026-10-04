-- Robux-Einnahmen: Gamepasses + Developer Products.
-- ProcessReceipt ist doppelt abgesichert: jeder Kauf wird im Spielstand vermerkt,
-- damit niemand etwas doppelt bekommt und niemand leer ausgeht.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))

local MonetizationService = {}
local Services

local owned: { [Player]: { [string]: boolean } } = {}
local loading: { [Player]: boolean } = {}
local adminGranted: { [Player]: { [string]: boolean } } = {} -- vom Admin geschenkte Pässe (nur diese Sitzung)
local randomRestricted: { [Player]: boolean } = {} -- Länder-Regel: keine bezahlten Zufalls-Gegenstände
local processing: { [string]: boolean } = {} -- Käufe, die gerade gutgeschrieben werden (gegen Doppel-Aufrufe)

local MAX_RECEIPTS = 60

-- ⭐ Starter-Paket: Werte in Config.StarterPack (der Shop-Text liest dieselben Werte)
-- Cash max(100K, 15 Min Einkommen), 3 Drehs, zufälliges Legendary-Ei, Speed Coil
local STARTER = Config.StarterPack or {}
local STARTER_MIN_CASH = tonumber(STARTER.MinCash) or 100000
local STARTER_INCOME_SECONDS = tonumber(STARTER.IncomeSeconds) or 900
local STARTER_SPINS = tonumber(STARTER.Spins) or 3
local STARTER_EGG_RARITY = tostring(STARTER.EggRarity or "Legendary")
local STARTER_GADGET = tostring(STARTER.Gadget or "SpeedCoil")
local STARTER_GADGET_FALLBACK_PRICE = 25000 -- Coil schon besessen -> ihr Preis als Cash (falls nicht in Config.Gadgets)
-- Länder ohne bezahlte Zufalls-Gegenstände: statt der Drehs +50% Cash, festes statt zufälliges Ei
local STARTER_RESTRICTED_CASH_MULT = tonumber(STARTER.RestrictedCashMult) or 1.5
-- 🐣 Sofort schlüpfen ohne Eier in der Base: Ersatz-Cash, damit der Kauf nicht verpufft
local INSTANT_HATCH_FALLBACK_SECONDS = 300
local INSTANT_HATCH_FALLBACK_MIN = 5000

function MonetizationService.HasPass(player: Player, key: string): boolean
	local passes = owned[player]
	local gifts = adminGranted[player]
	return (passes ~= nil and passes[key] == true) or (gifts ~= nil and gifts[key] == true)
end

function MonetizationService.LoadPasses(player: Player)
	if owned[player] then
		return
	end
	if loading[player] then
		while loading[player] and player.Parent do
			task.wait(0.1)
		end
		return
	end
	loading[player] = true
	local result = {}
	for _, pass in ipairs(Config.GamePasses) do
		if pass.Id ~= 0 then
			for attempt = 1, 3 do
				local ok, has =
					pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
				if ok then
					result[pass.Key] = has
					break
				end
				task.wait(attempt)
			end
		end
	end
	loading[player] = nil
	if not player.Parent then
		return
	end
	owned[player] = result
	if result.VIP then
		player:SetAttribute("VIP", true)
	end
end

-- Admin kann Pässe für Tests verschenken (nicht gespeichert)
function MonetizationService.GrantPassSession(player: Player, key: string)
	adminGranted[player] = adminGranted[player] or {}
	adminGranted[player][key] = true
	if key == "VIP" then
		player:SetAttribute("VIP", true)
	end
	MonetizationService.OnPassChanged(player)
end

function MonetizationService.OnPassChanged(player: Player)
	Services.EconomyService.ApplySpeed(player)
	local plot = Services.PlotService.GetPlot(player)
	if plot then
		Services.PlotService.UpdateSlotColors(plot)
		Services.PlotService.UpdateHatchTimes(plot) -- "2x Schlüpfen" -> Countdown neu berechnen
	end
	Services.EconomyService.MarkDirty(player)
end

-- Darf dieser Spieler KEINE bezahlten Zufalls-Gegenstände bekommen? (Roblox-Länder-Regel)
-- Im Zweifel (Abfrage klappt nicht) = ja, eingeschränkt. Ergebnis wird pro Sitzung gemerkt.
local function paidRandomRestricted(player: Player): boolean
	local cached = randomRestricted[player]
	if cached ~= nil then
		return cached
	end
	local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
	local restricted = not (ok and type(info) == "table" and info.ArePaidRandomItemsRestricted == false)
	if ok and player.Parent then
		randomRestricted[player] = restricted
	end
	return restricted
end

-- -------------------------------------------------------------------
-- PRODUKTE GUTSCHREIBEN
-- -------------------------------------------------------------------
-- Gadget schenken (ohne Cash). Gibt false zurück, wenn der Spieler es schon besitzt.
local function grantGadget(player: Player, data, id: string): boolean
	if type(data.Gadgets) ~= "table" then
		data.Gadgets = {}
	end
	if data.Gadgets[id] == true then
		return false
	end
	local gadgets = Services.GadgetService
	if gadgets then
		-- speichert + gibt das Werkzeug sofort in den Rucksack
		local ok, err = pcall(gadgets.Give, player, id)
		if not ok then
			warn("[Monetization] Gadget schenken fehlgeschlagen: " .. tostring(err))
		end
	end
	data.Gadgets[id] = true -- sicher gespeichert (Tool kommt spätestens beim nächsten Spawn)
	return true
end

local function grantStarterPack(player: Player): boolean
	local Economy = Services.EconomyService
	local data = Services.DataService.Get(player)
	if not data then
		return false
	end
	local restricted = paidRandomRestricted(player) -- kann kurz warten (meist schon gemerkt)
	if Services.DataService.Get(player) ~= data then
		return false -- während des Wartens gegangen -> Roblox versucht es beim nächsten Beitritt erneut
	end
	if data.StarterBought then
		warn(
			"[Monetization] Starter-Paket doppelt gekauft von " .. player.Name .. " – Inhalt trotzdem gutgeschrieben"
		)
	end
	local parts = {}
	local cash = math.max(STARTER_MIN_CASH, Economy.GetIncome(player) * STARTER_INCOME_SECONDS)
	if restricted then
		cash *= STARTER_RESTRICTED_CASH_MULT
	else
		Services.RewardService.AddSpins(player, STARTER_SPINS)
	end
	-- 🌀 Speed Coil (schon besessen -> ihr Preis als Cash)
	local def = Config.GadgetsById[STARTER_GADGET]
	local gadgetName = def and (tostring(def.Icon or "🌀") .. " " .. tostring(def.Name)) or "🌀 Speed Coil"
	if grantGadget(player, data, STARTER_GADGET) then
		table.insert(parts, gadgetName)
	else
		cash += def and def.Price or STARTER_GADGET_FALLBACK_PRICE
	end
	cash = math.floor(cash)
	Economy.AddCash(player, cash)
	table.insert(parts, 1, "💰 " .. Util.FormatCash(cash))
	if not restricted then
		table.insert(parts, 2, "🎡 " .. STARTER_SPINS .. " Drehs")
	end
	local _, eggText =
		Services.RewardService.GiveEgg(player, STARTER_EGG_RARITY, { Fixed = restricted, FullValue = true })
	data.StarterBought = true

	Economy.Notify(player, "⭐ STARTER-PAKET: " .. table.concat(parts, ", ") .. " – danke!", "Success")
	Economy.Notify(player, eggText, "Success")
	Economy.Effect(player, "Confetti", 3)
	Economy.NotifyAll("⭐ " .. player.DisplayName .. " hat sich das Starter-Paket geholt!", "Event")
	return true
end

-- 🛡️ Base-Schild: sperrt die eigene Base, auch im Meteoritenschauer (läuft schon eins -> länger).
-- Beim Verlassen setzt der PlotService das Schild zurück.
local function grantShield(player: Player, product): boolean
	local plot = Services.PlotService.GetPlot(player)
	if not plot then
		return false -- keine Base auf diesem Server -> Roblox versucht es später erneut
	end
	local minutes = math.max(1, tonumber(product.Minutes) or 10)
	Services.PlotService.AddShield(plot, minutes * 60)
	local Economy = Services.EconomyService
	Economy.Notify(
		player,
		"🛡️ Base-Schild aktiv: " .. minutes .. " Min sicher – sogar im Meteoritenschauer!",
		"Success"
	)
	Economy.Effect(player, "Confetti", 1.5)
	return true
end

local function grantProduct(player: Player, product): boolean
	local Economy = Services.EconomyService
	if product.Type == "Cash" then
		local amount = math.max(product.Min, Economy.GetIncome(player) * 60 * product.Minutes)
		amount = math.floor(amount)
		Economy.AddCash(player, amount)
		Economy.Notify(player, "💰 +" .. Util.FormatCash(amount) .. " – danke für deinen Kauf!", "Success")
		Economy.Effect(player, "Confetti", 1.5)
		return true
	elseif product.Type == "ServerLuck" then
		Services.MeteorService.AddServerLuck(product.Mult, product.Minutes * 60)
		Economy.NotifyAll(
			"🍀 "
				.. player.DisplayName
				.. " hat "
				.. product.Mult
				.. "x Glück für ALLE gekauft! ("
				.. product.Minutes
				.. " Min)",
			"Event"
		)
		return true
	elseif product.Type == "Shower" then
		Services.MeteorService.StartShower()
		Economy.NotifyAll("🌠 " .. player.DisplayName .. " hat einen Meteoritenschauer gestartet!", "Event")
		return true
	elseif product.Type == "Steps" then
		local data = Services.DataService.Get(player)
		if not data then
			return false
		end
		-- so viele Schritte wie "Minutes" Minuten auf dem besten gekauften Laufband
		local best = Config.BestTreadmill(data.Treadmills)
		local ticksPerMinute = 60 / Config.TreadmillTick
		local amount = (best and best.Rate or 1) * ticksPerMinute * product.Minutes * Economy.GetStepsMult(player)
		amount = math.floor(math.max(product.Min, amount))
		Economy.AddSteps(player, amount)
		Economy.Effect(player, "Steps", amount)
		Economy.Notify(
			player,
			"👟 +" .. Util.FormatNumber(amount) .. " Schritte – danke für deinen Kauf!",
			"Success"
		)
		Economy.Effect(player, "Confetti", 1.5)
		return true
	elseif product.Type == "Meteor" then
		-- Base voll -> voller Wert als Cash, damit der Kauf nie verloren geht (macht GiveEgg)
		local ok, text = Services.RewardService.GiveEgg(player, product.Rarity, { FullValue = true })
		if not ok then
			return false
		end
		Economy.Notify(player, text .. " 🐣", "Success")
		Economy.Effect(player, "Confetti", 2)
		return true
	elseif product.Type == "StarterPack" then
		return grantStarterPack(player)
	elseif product.Type == "Spins" then
		local amount = math.max(1, math.floor(tonumber(product.Amount) or 1))
		if not Services.RewardService.AddSpins(player, amount) then
			return false
		end
		Economy.Notify(player, "🎡 +" .. amount .. " Glücksrad-Drehs – viel Glück!", "Success")
		Economy.Effect(player, "Confetti", 1.5)
		return true
	elseif product.Type == "InstantHatch" then
		if Economy.HatchAll(player) == 0 then
			-- keine Eier in der Base -> Ersatz-Cash statt eines verpufften Kaufs
			local amount = math.floor(
				math.max(INSTANT_HATCH_FALLBACK_MIN, Economy.GetIncome(player) * INSTANT_HATCH_FALLBACK_SECONDS)
			)
			Economy.AddCash(player, amount)
			Economy.Notify(
				player,
				"🐣 Keine Eier in deiner Base – du bekommst " .. Util.FormatCash(amount) .. " als Ersatz!",
				"Info"
			)
		end
		Economy.Effect(player, "Confetti", 2)
		return true
	elseif product.Type == "Shield" then
		return grantShield(player, product)
	elseif product.Type == "EggRush" then
		local meteors = Services.MeteorService
		if type(meteors.StartEggRush) ~= "function" then
			warn("[Monetization] MeteorService.StartEggRush fehlt – Egg Rush kann nicht starten")
			return false
		end
		meteors.StartEggRush()
		Economy.NotifyAll(
			"🥚 " .. player.DisplayName .. " hat einen EGG RUSH gestartet! Schnell sammeln! 🏃",
			"Event"
		)
		return true
	end
	warn("[Monetization] Unbekannter Produkt-Typ: " .. tostring(product.Type))
	return false
end

local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- Roblox versucht es später erneut
	end
	local data = Services.DataService.Get(player)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local product = Config.ProductsById[receipt.ProductId]
	if not product then
		warn(
			"[Monetization] Unbekannte ProductId "
				.. tostring(receipt.ProductId)
				.. " – in Config.Products eintragen!"
		)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- Schon gutgeschrieben? (z.B. nach Server-Absturz)
	if table.find(data.Receipts, receipt.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	-- Wird gerade gutgeschrieben (Gutschrift kann kurz warten, z.B. Länder-Regel beim Starter-Paket)
	if processing[receipt.PurchaseId] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	processing[receipt.PurchaseId] = true
	local ok, granted = pcall(grantProduct, player, product)
	processing[receipt.PurchaseId] = nil
	if Services.DataService.Get(player) ~= data then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- Spieler ist inzwischen gegangen
	end
	if not ok or not granted then
		warn("[Monetization] Gutschrift fehlgeschlagen: " .. tostring(granted))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(data.Receipts, receipt.PurchaseId)
	while #data.Receipts > MAX_RECEIPTS do
		table.remove(data.Receipts, 1)
	end
	data.Stats.RobuxSpent += receipt.CurrencySpent or 0

	-- Sofort speichern, damit der Kauf sicher verbucht ist
	if Services.DataService.Save(player) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	-- Speichern ging nicht: Kauf ist im Spielstand vermerkt, beim nächsten Versuch wird
	-- er als "schon gutgeschrieben" erkannt und nicht doppelt vergeben.
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function MonetizationService.Init(services)
	Services = services
end

function MonetizationService.Start()
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, purchased)
		if not purchased then
			return
		end
		for _, pass in ipairs(Config.GamePasses) do
			if pass.Id == gamePassId then
				owned[player] = owned[player] or {}
				owned[player][pass.Key] = true
				if pass.Key == "VIP" then
					player:SetAttribute("VIP", true)
				end
				MonetizationService.OnPassChanged(player)
				Services.EconomyService.Notify(player, "🎉 " .. pass.Name .. " freigeschaltet! Danke!", "Success")
				Services.EconomyService.NotifyAll(
					"⭐ " .. player.DisplayName .. " hat " .. pass.Name .. " gekauft!",
					"Event"
				)
				Services.EconomyService.Effect(player, "Confetti", 2)
			end
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		task.spawn(MonetizationService.LoadPasses, player)
		task.spawn(paidRandomRestricted, player) -- vorab merken, damit das Starter-Paket nicht warten muss
	end)
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
		loading[player] = nil
		adminGranted[player] = nil
		randomRestricted[player] = nil
	end)
end

return MonetizationService
