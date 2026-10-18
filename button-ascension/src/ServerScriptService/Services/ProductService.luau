--[[
	ProductService (ModuleScript)
	Location: ServerScriptService/Services/ProductService
	Depends on: Shared/Config/{DevProducts,GamePasses,Chests}, Shared/RobuxSale, Shared/Formulas, Shared/Format,
	            Core/DataOps, DataService, EconomyService, StatsService, SyncService,
	            ChestService (Robux crates), Net

	Developer products (repeatable Robux purchases) through
	MarketplaceService.ProcessReceipt, plus the countdown of bought timed boosts,
	one-time rewards of game passes (GrantPassReward) and the check with Roblox
	whether each configured ID is a pass or a product (ResolveSales).

	Roblox keeps retrying a receipt until it is answered with PurchaseGranted
	(also after the player rejoins), so ProcessReceipt follows these rules:
	  * Unknown product, player not in this server, data not loaded yet, or a
	    session that cannot save (temporary, lock lost, leaving)
	    → NotProcessedYet; Roblox asks again later.
	  * Every receipt's PurchaseId is stored in the player's data (the newest
	    DevProducts.ReceiptHistory). A receipt already in that list is never
	    granted a second time.
	  * The reward is saved right away and PurchaseGranted is returned only
	    after that save succeeded. If it fails, NotProcessedYet; on the retry
	    the stored PurchaseId prevents a second grant and the save runs again.
	The client can only open Roblox's purchase prompt; nothing it sends can
	grant a product.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DevProducts = require(Shared.Config.DevProducts)
local GamePasses = require(Shared.Config.GamePasses)
local Chests = require(Shared.Config.Chests)
local RobuxSale = require(Shared.RobuxSale)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)
local DataOps = require(script.Parent.Parent.Core.DataOps)

local ProductService = { Name = "ProductService" }

local SAVE_WAIT_SECONDS = 30

function ProductService:Init(services)
	self.Services = services
end

function ProductService:Start()
	MarketplaceService.ProcessReceipt = function(receipt)
		return self:ProcessReceipt(receipt)
	end
	task.spawn(self.ResolveSales, self)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(1)
			local now = os.clock()
			self:_tickBoosts(now - last)
			last = now
		end
	end)
end

-- Boosts --------------------------------------------------------------------------------

-- Bought boosts only count down while their owner is in a server.
function ProductService:_tickBoosts(dt: number)
	for _, profile in pairs(self.Services.DataService.Profiles) do
		local boosts = profile.Data.Boosts
		if next(boosts) then
			for key, left in pairs(boosts) do
				local remaining = left - dt
				if remaining > 0 then
					boosts[key] = remaining
				else
					boosts[key] = nil
					self.Services.StatsService:Invalidate(profile)
					self.Services.SyncService:MarkDirty(profile, "Boosts")
					local product = DevProducts.ByKey[key]
					self.Services.Net.notify(profile.Player, "Toast", {
						Text = `{if product then product.Name else "Boost"} has ended.`,
						Icon = if product then product.Icon else "⏱️",
					})
				end
			end
		end
	end
end

-- Granting --------------------------------------------------------------------------------

-- The most valuable Sparks crate this player has unlocked.
function ProductService:BestCrate(data)
	local best = nil
	for _, chest in ipairs(Chests.List) do
		if chest.Currency == "Sparks" and Formulas.chestUnlocked(chest, data) and (best == nil or chest.Price > best.Price) then
			best = chest
		end
	end
	return best
end

-- Applies every reward of a product. Returns a short description for the toast.
function ProductService:Grant(profile, product): string
	local data = profile.Data
	local services = self.Services
	local parts = {}
	if product.Sparks then
		-- Exactly what the name says: no multipliers, and it does not count toward
		-- quests or the ascension run total.
		DataOps.addCurrency(data, "Sparks", product.Sparks)
		services.SyncService:MarkDirty(profile, "Currencies")
		table.insert(parts, `+{Format.commas(product.Sparks)} Sparks`)
	end
	if product.Gems then
		services.EconomyService:Add(profile, "Gems", product.Gems, "robux")
		table.insert(parts, `+{Format.commas(product.Gems)} Gems`)
	end
	if product.Boost then
		local before = data.Boosts[product.Key] or 0
		local total = math.min(DevProducts.MaxBoostSeconds, before + product.Boost.Seconds)
		data.Boosts[product.Key] = total
		services.StatsService:Invalidate(profile)
		services.SyncService:MarkDirty(profile, "Boosts")
		table.insert(parts, `{product.Name} active for {Format.clock(total)}`)
	end
	if product.Crates then
		local chest = self:BestCrate(data)
		if chest then
			DataOps.addChest(data, chest.Id, product.Crates)
			services.SyncService:MarkDirty(profile, "Chests")
			table.insert(parts, `+{product.Crates} {chest.Name}`)
		end
	end
	if product.Crate then
		-- Rolled and applied on the server; the client only plays the animation.
		local results = services.ChestService:OpenRobuxCrate(profile, product.Crate)
		services.Net.notify(profile.Player, "CrateOpened", { Chest = product.Crate, Results = results })
		local first = results[1]
		table.insert(parts, if first then `{product.Name}: {first.Rarity}` else product.Name)
	end
	return if #parts > 0 then table.concat(parts, ", ") else product.Description
end

--[[
	One-time reward of a product sold as a game pass. Granted at most once per
	player (data.PassRewards), whether the pass was bought just now or the
	ownership check on join finds it. Returns true when it was granted now.
]]
function ProductService:GrantPassReward(profile, product): boolean
	local data = profile.Data
	if data.PassRewards[product.Key] then
		return false
	end
	-- Recorded before anything can yield, so two callers can never both grant it.
	data.PassRewards[product.Key] = true
	local summary = self:Grant(profile, product)
	self.Services.SyncService:MarkDirty(profile, "PassRewards")
	if not product.Crate then
		self.Services.Net.notify(profile.Player, "Reward", { Title = `{product.Icon} {product.Name}`, Text = summary })
	end
	task.spawn(self.Services.DataService.SaveNow, self.Services.DataService, profile)
	return true
end

-- Sale kinds ---------------------------------------------------------------------------------

local function nameOf(id: number, infoType: Enum.InfoType): string?
	local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, infoType)
	if ok and type(info) == "table" and type(info.Name) == "string" then
		return info.Name
	end
	return nil
end

--[[
	For entries with a HubName, asks Roblox whether the configured ID is a game
	pass or a developer product (matching the name, so an unrelated item with
	the same number never counts) and publishes the answer (Shared/RobuxSale).
	If Roblox can't tell, the config decides.
]]
function ProductService:ResolveSales()
	local entries = {}
	for _, pass in ipairs(GamePasses.List) do
		table.insert(entries, pass)
	end
	for _, product in ipairs(DevProducts.List) do
		table.insert(entries, product)
	end
	for _, entry in ipairs(entries) do
		local kind, id = RobuxSale.configured(entry)
		if kind and entry.HubName then
			local resolved = nil
			if nameOf(id, Enum.InfoType.GamePass) == entry.HubName then
				resolved = "pass"
			elseif nameOf(id, Enum.InfoType.Product) == entry.HubName then
				resolved = "product"
			end
			if resolved == nil then
				warn(`[ProductService] Could not confirm "{entry.HubName}" ({id}) with Roblox; selling it as a {kind}.`)
			elseif resolved ~= kind then
				warn(`[ProductService] "{entry.HubName}" ({id}) is a {resolved} on Roblox, not a {kind}; selling it as a {resolved}.`)
			end
			RobuxSale.publish(entry, resolved or kind, id)
		elseif kind then
			RobuxSale.publish(entry, kind, id)
		end
	end
	RobuxSale.markResolved()
end

-- Saves now and reports whether the save (with the latest data) succeeded.
function ProductService:_save(profile): boolean
	-- A queued save merges new requests; wait for it so this one really runs.
	local deadline = os.clock() + SAVE_WAIT_SECONDS
	while profile.SaveQueued and os.clock() < deadline do
		task.wait(0.1)
	end
	if profile.SaveQueued then
		return false
	end
	return self.Services.DataService:SaveNow(profile)
end

local function canSave(profile): boolean
	return not (profile.Temporary or profile.LockLost or profile.Releasing or profile.Released)
end

function ProductService:ProcessReceipt(receipt): Enum.ProductPurchaseDecision
	local notYet = Enum.ProductPurchaseDecision.NotProcessedYet
	local granted = Enum.ProductPurchaseDecision.PurchaseGranted
	if type(receipt) ~= "table" then
		return notYet
	end
	local purchaseId = receipt.PurchaseId
	local product = DevProducts.byProductId(receipt.ProductId)
	-- An effect pass sold as a developer product: bought once, kept forever.
	local pass = if product then nil else GamePasses.byProductId(receipt.ProductId)
	if not (product or pass) or type(purchaseId) ~= "string" or purchaseId == "" or #purchaseId > 100 then
		warn(`[ProductService] Receipt for unknown or unconfigured product {tostring(receipt.ProductId)}; leaving it for later.`)
		return notYet
	end
	if type(receipt.PlayerId) ~= "number" then
		return notYet
	end
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return notYet
	end
	local DataService = self.Services.DataService
	local profile = DataService:GetProfile(player) or DataService:WaitForProfile(player, 20)
	if not profile or not canSave(profile) then
		return notYet
	end

	local data = profile.Data
	if table.find(data.Receipts, purchaseId) then
		-- Granted on an earlier attempt; make sure that grant is saved.
		return if self:_save(profile) then granted else notYet
	end

	-- No yields between the check above and recording the ID, so a receipt
	-- delivered twice at the same time is still granted once.
	if product then
		local summary = self:Grant(profile, product)
		if not product.Crate then
			self.Services.Net.notify(player, "Reward", { Title = `{product.Icon} {product.Name}`, Text = summary })
		end
	elseif not data.Passes[pass.Key] then
		data.Passes[pass.Key] = true
		self.Services.StatsService:Invalidate(profile)
		self.Services.SyncService:MarkDirty(profile, "Passes")
		self.Services.Net.notify(player, "Pass", { Key = pass.Key })
	end
	table.insert(data.Receipts, purchaseId)
	while #data.Receipts > DevProducts.ReceiptHistory do
		table.remove(data.Receipts, 1)
	end

	if self:_save(profile) then
		return granted
	end
	warn(`[ProductService] Could not save purchase {purchaseId} for {player.UserId} yet; Roblox will retry.`)
	return notYet
end

return ProductService
