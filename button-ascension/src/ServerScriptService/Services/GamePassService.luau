--[[
	GamePassService (ModuleScript)
	Location: ServerScriptService/Services/GamePassService
	Depends on: Shared/Config/{GamePasses,DevProducts}, Shared/RobuxSale, DataService,
	            StatsService, SyncService, ProductService, Net

	Robux game passes. Ownership is decided on the server only:
	  * When a player's data loads, MarketplaceService:UserOwnsGamePassAsync is
	    asked about every configured pass (with retries). If Roblox can't
	    answer, the last saved answer in data.Passes is kept, so an outage
	    neither takes a pass away nor hands one out.
	  * When Roblox reports a finished purchase on the server
	    (PromptGamePassPurchaseFinished with wasPurchased = true), the pass is
	    granted at once and saved.
	There is no remote for passes: the client can only open Roblox's purchase
	prompt, so nothing a client sends can grant a pass. The effects live in
	Shared/Formulas (computeStats reads data.Passes).

	Developer-product rewards can also be sold as a one-time game pass
	(Config/DevProducts with GamePassId). Owning such a pass grants its reward
	once per player through ProductService:GrantPassReward. Whether an ID is a
	pass at all is confirmed with Roblox first (Shared/RobuxSale).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GamePasses = require(Shared:WaitForChild("Config"):WaitForChild("GamePasses"))
local DevProducts = require(Shared.Config:WaitForChild("DevProducts"))
local RobuxSale = require(Shared:WaitForChild("RobuxSale"))

local GamePassService = { Name = "GamePassService" }

local CHECK_ATTEMPTS = 3
-- How long ownership checks wait for ProductService to confirm the sale kinds.
local RESOLVE_WAIT_SECONDS = 15

function GamePassService:Init(services)
	self.Services = services
end

function GamePassService:Start()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		if wasPurchased == true and typeof(player) == "Instance" and player:IsA("Player") then
			self:_onPurchased(player, passId)
		end
	end)
end

function GamePassService:OnProfileLoaded(profile)
	profile.Runtime.PassesBought = {}
	task.spawn(self.Refresh, self, profile)
end

-- true / false, or nil when Roblox could not answer.
function GamePassService:_owns(userId: number, passId: number): boolean?
	for attempt = 1, CHECK_ATTEMPTS do
		local ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, userId, passId)
		if ok then
			return result == true
		end
		warn(`[GamePassService] Ownership check {attempt} for {userId} / pass {passId} failed: {result}`)
		if attempt < CHECK_ATTEMPTS then
			task.wait(attempt * 2)
		end
	end
	return nil
end

function GamePassService:_isActive(profile): boolean
	return self.Services.DataService:GetProfile(profile.Player) == profile
end

function GamePassService:_changed(profile)
	self.Services.StatsService:Invalidate(profile)
	self.Services.SyncService:MarkDirty(profile, "Passes")
end

-- Re-checks every configured pass with Roblox and updates the stored answers.
function GamePassService:Refresh(profile)
	local deadline = os.clock() + RESOLVE_WAIT_SECONDS
	while not RobuxSale.isResolved() and os.clock() < deadline do
		task.wait(0.2)
	end
	local data = profile.Data
	local boughtNow = profile.Runtime.PassesBought or {}
	local gained = {}
	local changed = false
	for _, pass in ipairs(GamePasses.List) do
		-- Passes sold as developer products are kept by ProcessReceipt, not checked here.
		local kind, passId = RobuxSale.of(pass)
		if kind == "pass" then
			local owns = self:_owns(profile.UserId, passId)
			-- A purchase finished while we were asking: Roblox's answer may predate it.
			if owns == false and boughtNow[pass.Key] then
				owns = nil
			end
			if owns ~= nil and (data.Passes[pass.Key] == true) ~= owns then
				data.Passes[pass.Key] = if owns then true else nil
				changed = true
				if owns then
					table.insert(gained, pass)
				end
			end
		end
	end
	if changed and self:_isActive(profile) then
		self:_changed(profile)
		for _, pass in ipairs(gained) do
			self.Services.Net.notify(profile.Player, "Pass", { Key = pass.Key })
		end
	end
	-- One-time rewards sold as game passes (Gems, Sparks, boosts, bundles).
	for _, product in ipairs(DevProducts.List) do
		local kind, passId = RobuxSale.of(product)
		if kind == "pass" and not data.PassRewards[product.Key] and self:_owns(profile.UserId, passId) == true then
			if self:_isActive(profile) then
				self.Services.ProductService:GrantPassReward(profile, product)
			end
		end
	end
end

function GamePassService:_onPurchased(player: Player, passId: any)
	local reward = DevProducts.byGamePassId(passId)
	if reward then
		local DataService = self.Services.DataService
		local profile = DataService:GetProfile(player) or DataService:WaitForProfile(player, 60)
		if profile then
			self.Services.ProductService:GrantPassReward(profile, reward)
		end
		return
	end
	local pass = GamePasses.byGamePassId(passId)
	if not pass then
		warn(`[GamePassService] Purchase of unknown or unconfigured pass {tostring(passId)} by {player.UserId}`)
		return
	end
	local DataService = self.Services.DataService
	local profile = DataService:GetProfile(player) or DataService:WaitForProfile(player, 60)
	if not profile then
		return
	end
	profile.Runtime.PassesBought = profile.Runtime.PassesBought or {}
	profile.Runtime.PassesBought[pass.Key] = true
	if profile.Data.Passes[pass.Key] == true then
		return
	end
	profile.Data.Passes[pass.Key] = true
	self:_changed(profile)
	self.Services.Net.notify(player, "Pass", { Key = pass.Key })
	task.spawn(DataService.SaveNow, DataService, profile)
end

-- Owned and configured pass keys, for admin inspection and diagnostics.
function GamePassService:OwnedList(profile): { string }
	local list = {}
	for _, pass in ipairs(GamePasses.List) do
		if GamePasses.owns(profile.Data.Passes, pass.Key) then
			table.insert(list, pass.Key)
		end
	end
	return list
end

return GamePassService
