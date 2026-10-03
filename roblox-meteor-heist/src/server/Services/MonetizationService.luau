-- Robux-Einnahmen: Gamepasses + Developer Products.
-- ProcessReceipt ist doppelt abgesichert: jeder Kauf wird im Spielstand vermerkt,
-- damit niemand etwas doppelt bekommt und niemand leer ausgeht.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))

local MonetizationService = {}
local Services

local owned: { [Player]: { [string]: boolean } } = {}
local loading: { [Player]: boolean } = {}
local adminGranted: { [Player]: { [string]: boolean } } = {} -- vom Admin geschenkte Pässe (nur diese Sitzung)

local MAX_RECEIPTS = 60

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
	end
	Services.EconomyService.MarkDirty(player)
end

-- -------------------------------------------------------------------
-- PRODUKTE GUTSCHREIBEN
-- -------------------------------------------------------------------
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
	elseif product.Type == "Speed" then
		local data = Services.DataService.Get(player)
		if not data then
			return false
		end
		data.SpeedLevel = math.min(Config.MaxSpeedLevel, data.SpeedLevel + product.Levels)
		Economy.ApplySpeed(player)
		Economy.MarkDirty(player)
		Economy.Notify(player, "🏃 +" .. product.Levels .. " Speed-Level!", "Success")
		return true
	elseif product.Type == "Meteor" then
		local def = Services.MeteorService.RandomOfRarity(product.Rarity)
		if not def then
			return false
		end
		local entry = { Id = def.Id, Mut = "Normal", Lv = 1 }
		if Economy.GiveMeteor(player, entry) then
			Economy.Notify(player, "🌟 " .. def.Name .. " ist in deiner Base!", "Success")
		else
			-- Base voll -> Wert als Cash, damit der Kauf nie verloren geht
			local value = math.floor(Config.MeteorValue(entry))
			Economy.AddCash(player, value)
			Economy.Notify(
				player,
				"Base voll – du bekommst " .. Util.FormatCash(value) .. " statt " .. def.Name,
				"Info"
			)
		end
		Economy.Effect(player, "Confetti", 2)
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

	local ok, granted = pcall(grantProduct, player, product)
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
	end)
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
		loading[player] = nil
		adminGranted[player] = nil
	end)
end

return MonetizationService
