--[[
	GamePassService (ModuleScript)
	Location: ServerScriptService/Services/GamePassService
	Depends on: Shared/Config/GamePasses, DataService, StatsService, SyncService, Net

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
]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GamePasses = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GamePasses"))

local GamePassService = { Name = "GamePassService" }

local CHECK_ATTEMPTS = 3

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
	local data = profile.Data
	local boughtNow = profile.Runtime.PassesBought or {}
	local gained = {}
	local changed = false
	for _, pass in ipairs(GamePasses.List) do
		if GamePasses.isConfigured(pass) then
			local owns = self:_owns(profile.UserId, pass.GamePassId)
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
end

function GamePassService:_onPurchased(player: Player, passId: any)
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
