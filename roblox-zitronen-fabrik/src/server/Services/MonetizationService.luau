--[[
	Gamepässe und Dev-Produkte. Solange in Config die IDs 0 sind, ist alles aus.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local Core = require(script.Parent.Core)
local DataService = require(script.Parent.DataService)

local MonetizationService = {}

local function passKeyById(id: number): string?
	for key, pass in pairs(Config.GamePasses) do
		if pass.Id ~= 0 and pass.Id == id then
			return key
		end
	end
	return nil
end

local function productById(id: number)
	for key, product in pairs(Config.DevProducts) do
		if product.Id ~= 0 and product.Id == id then
			return key, product
		end
	end
	return nil, nil
end

function MonetizationService.LoadPasses(session)
	local player = session.Player
	for key, pass in pairs(Config.GamePasses) do
		if pass.Id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
			end)
			session.Passes[key] = ok and owns == true
		end
	end
end

function MonetizationService.Init()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		if not purchased then
			return
		end
		local key = passKeyById(passId)
		local session = Core.Get(player)
		if key and session then
			session.Passes[key] = true
			Core.RecomputeStats(session)
			local pass = Config.GamePasses[key]
			Core.Notify(player, "Danke! " .. pass.Emoji .. " " .. pass.Name .. " ist aktiv!", "gold")
			Core.Effect(player, "Purchase")
		end
	end)

	MarketplaceService.ProcessReceipt = function(receipt)
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		local session = player and Core.Get(player)
		-- Ohne funktionierendes Speichern lieber später nochmal (Roblox fragt erneut)
		if not session or not session.Loaded or not session.CanSave then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local receipts = session.Profile.Receipts
		if table.find(receipts, receipt.PurchaseId) then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		local key, product = productById(receipt.ProductId)
		if not key or not product then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local stats = session.Stats or Economy.ComputeStats(session.Profile, Core.Context(session))
		local amount = Economy.IncomeReward(stats, product.Minutes, 1000)
		Core.AddEarnings(session, amount)
		table.insert(receipts, receipt.PurchaseId)
		while #receipts > 50 do
			table.remove(receipts, 1)
		end
		-- Erst wenn der Kauf gespeichert ist, bestätigen wir ihn
		if not DataService.Save(session) then
			Core.RevertEarnings(session, amount)
			local index = table.find(receipts, receipt.PurchaseId)
			if index then
				table.remove(receipts, index)
			end
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		Core.Notify(session.Player, "Danke! " .. product.Emoji .. " +" .. Format.Cash(amount), "gold")
		Core.Effect(session.Player, "Reward", { Amount = amount, Title = product.Name })
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
end

return MonetizationService
