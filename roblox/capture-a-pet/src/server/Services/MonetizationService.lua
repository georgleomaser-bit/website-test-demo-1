-- Game passes and developer products. Purchases are granted exactly once: every receipt id
-- is stored in the player's save and the save is written before Roblox is told the
-- purchase went through.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Monetization = require(Shared.Config.Monetization)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)

local MonetizationService = {}

local S
local MAX_RECEIPTS = 60

function MonetizationService.Init(services)
	S = services
end

local function applyPass(player: Player, key: string)
	local rt = S.PlayerService.get(player)
	if not rt or rt.Passes[key] then
		return
	end
	rt.Passes[key] = true
	if key == "VIP" then
		player:SetAttribute("VIP", true)
		S.PlotService.refreshEggs(player)
		S.ShopService.fillPen(player)
	elseif key == "BaitBag" then
		S.RewardService.onJoin(player)
	end
	S.PlotService.refreshTreadmills(player)
	S.PlayerService.markState(player)
end
MonetizationService.applyPass = applyPass

-- Admin / testing helper.
function MonetizationService.setPass(player: Player, key: string, owned: boolean)
	local rt = S.PlayerService.get(player)
	if not rt then
		return
	end
	if owned then
		applyPass(player, key)
	else
		rt.Passes[key] = nil
		if key == "VIP" then
			player:SetAttribute("VIP", nil)
			S.ShopService.fillPen(player)
			S.PlotService.refreshEggs(player)
		end
		S.PlotService.refreshTreadmills(player)
		S.PlayerService.markState(player)
	end
end

function MonetizationService.loadPasses(player: Player)
	for _, pass in ipairs(Monetization.GamePasses) do
		if pass.Id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
			end)
			if ok and owns then
				applyPass(player, pass.Key)
			end
		end
	end
end

function MonetizationService.promptPass(player: Player, key: string)
	local pass = Monetization.PassByKey[key]
	if not pass or pass.Id == 0 then
		S.PlayerService.notify(player, (pass and pass.Name or key) .. " is coming soon!", "info")
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, pass.Id)
end

function MonetizationService.promptProduct(player: Player, key: string)
	local product = Monetization.ProductByKey[key]
	if not product or product.Id == 0 then
		S.PlayerService.notify(player, (product and product.Name or key) .. " is coming soon!", "info")
		return
	end
	MarketplaceService:PromptProductPurchase(player, product.Id)
end

-- Returns true when the product was granted.
local function grantProduct(player: Player, product): boolean
	local ctx = S.PlayerService.ctx(player)
	if product.Kind == "Cash" then
		local amount = Formulas.cashForSeconds(ctx, product.IncomeSeconds, product.Min)
		S.PlayerService.addCash(player, amount)
		S.PlayerService.notify(player, "+$" .. Format.number(amount) .. "! Thanks for your support!", "reward")
	elseif product.Kind == "Boost" then
		S.PlayerService.addBoost(player, product.Boost, product.Seconds)
		S.PlayerService.notify(player, product.Name .. " activated!", "reward")
	elseif product.Kind == "ServerLuck" then
		local now = os.time()
		S.PlayerService.ServerLuckUntil = math.max(S.PlayerService.ServerLuckUntil, now) + product.Seconds
		S.PlayerService.announce({
			{ { Text = player.DisplayName, Color = "#4FB4FF" }, { Text = " activated " }, { Text = "x2 SERVER LUCK!", Color = "#7CFF6B" } },
		})
		for _, other in ipairs(Players:GetPlayers()) do
			S.PlayerService.markState(other)
		end
	elseif product.Kind == "Bait" then
		local data = S.DataService.get(player)
		-- purchases ignore the bag limit so nothing paid for is ever lost
		data.Bait += product.Amount
		S.PlayerService.markState(player)
		S.PlayerService.notify(player, "+" .. product.Amount .. " Glow Bait!", "reward")
	elseif product.Kind == "InstantHatch" then
		local count = S.PlotService.hatchAllNow(player)
		S.PlayerService.notify(player, count > 0 and "Your eggs are ready to hatch!" or "Your nests were empty, here is some cash instead!", "reward")
		if count == 0 then
			S.PlayerService.addCash(player, Formulas.cashForSeconds(ctx, 600, 5000))
		end
	else
		return false
	end
	return true
end

function MonetizationService.Start()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local pass = Monetization.PassById[passId]
		if pass then
			applyPass(player, pass.Key)
			S.PlayerService.notify(player, pass.Name .. " unlocked! Thank you!", "reward")
		end
	end)

	MarketplaceService.ProcessReceipt = function(receipt)
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		-- wait a little for data to load if the purchase came in right at join
		local waited = 0
		while not S.DataService.isLoaded(player) and waited < 15 and player.Parent do
			task.wait(0.5)
			waited += 0.5
		end
		local data = S.DataService.get(player)
		if not data then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if table.find(data.Receipts, receipt.PurchaseId) then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		local product = Monetization.ProductById[receipt.ProductId]
		if not product then
			warn("[Monetization] unknown product id", receipt.ProductId)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local ok, granted = pcall(grantProduct, player, product)
		if not ok or not granted then
			warn("[Monetization] grant failed", granted)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		table.insert(data.Receipts, receipt.PurchaseId)
		while #data.Receipts > MAX_RECEIPTS do
			table.remove(data.Receipts, 1)
		end
		if not S.DataService.saveNow(player) then
			-- keep the grant in memory; Roblox retries later and the receipt id prevents a double grant
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	S.Router.register("BuyPass", function(player, key)
		if type(key) ~= "string" then
			return false
		end
		MonetizationService.promptPass(player, key)
		return true
	end)
	S.Router.register("BuyProduct", function(player, key)
		if type(key) ~= "string" then
			return false
		end
		MonetizationService.promptProduct(player, key)
		return true
	end)
end

return MonetizationService
