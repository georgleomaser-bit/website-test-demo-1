--[[
	LeaderboardService (ModuleScript)
	Location: ServerScriptService/Services/LeaderboardService
	Depends on: Shared/Config/GameConfig, Shared/Format, Core/Net, DataService

	* leaderstats for the Roblox player list (Ascensions, Sparks).
	* Global leaderboards in OrderedDataStores (lifetime Sparks, presses,
	  ascensions), written periodically and cached; failures are logged and
	  the last good cache is kept.
	* A live "this server" board computed from loaded profiles.

	OrderedDataStores only hold integers, so lifetime Sparks are stored as
	floor(log10(value + 1) * 1e6) and decoded for display.

	Action: GetLeaderboards {}
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Format = require(Shared.Format)
local Net = require(script.Parent.Parent.Core.Net)

local CONFIG = GameConfig.Leaderboards

local LeaderboardService = {
	Name = "LeaderboardService",
	Cache = {} :: { [string]: { any } },
	UpdatedAt = 0,
	Available = false,
}

local stores: { [string]: OrderedDataStore } = {}
local nameCache: { [number]: string } = {}

local function encode(kind: string, value: number): number
	if kind == "log" then
		return math.floor(math.log10(math.max(0, value) + 1) * 1e6)
	end
	return math.floor(math.clamp(value, 0, 2 ^ 52))
end

local function decode(kind: string, value: number): number
	if kind == "log" then
		return 10 ^ (value / 1e6) - 1
	end
	return value
end

local function statValue(profile, stat: string): number
	if stat == "Rebirths" then
		return profile.Data.Rebirths
	end
	return profile.Data.Stats[stat] or 0
end

function LeaderboardService:Init(services)
	self.Services = services
	Net.registerAction("GetLeaderboards", {
		Rate = { Capacity = 3, Refill = 0.3 },
		Handler = function(profile)
			return Net.ok({
				Global = self.Cache,
				Server = self:ServerBoard(),
				UpdatedAt = self.UpdatedAt,
				Available = self.Available,
				Me = profile.UserId,
			})
		end,
	})
end

function LeaderboardService:Start()
	task.spawn(function()
		while true do
			task.wait(1)
			for _, profile in pairs(self.Services.DataService.Profiles) do
				self:_updateLeaderstats(profile)
			end
		end
	end)

	if not CONFIG.Enabled then
		return
	end
	local ok = pcall(function()
		for _, board in ipairs(CONFIG.Boards) do
			stores[board.Id] = DataStoreService:GetOrderedDataStore(CONFIG.StorePrefix .. board.Id)
		end
	end)
	self.Available = ok and self.Services.DataService:IsPersistent()
	if not self.Available then
		return
	end
	task.spawn(function()
		task.wait(15)
		while true do
			self:_publish()
			self:_refresh()
			task.wait(math.max(CONFIG.UpdateInterval, CONFIG.RefreshInterval))
		end
	end)
end

function LeaderboardService:OnProfileLoaded(profile)
	local player = profile.Player
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Ascensions"
	rebirths.Parent = folder
	local sparks = Instance.new("StringValue")
	sparks.Name = "Sparks"
	sparks.Parent = folder
	folder.Parent = player
	nameCache[player.UserId] = player.Name
	self:_updateLeaderstats(profile)
end

function LeaderboardService:OnProfileReleasing(profile)
	if self.Available and not profile.Temporary then
		task.spawn(function()
			self:_publishProfile(profile)
		end)
	end
end

function LeaderboardService:_updateLeaderstats(profile)
	local folder = profile.Player:FindFirstChild("leaderstats")
	if not folder then
		return
	end
	local rebirths = folder:FindFirstChild("Ascensions")
	local sparks = folder:FindFirstChild("Sparks")
	if rebirths and rebirths.Value ~= profile.Data.Rebirths then
		rebirths.Value = profile.Data.Rebirths
	end
	local text = Format.short(profile.Data.Currencies.Sparks)
	if sparks and sparks.Value ~= text then
		sparks.Value = text
	end
end

function LeaderboardService:_publishProfile(profile)
	for _, board in ipairs(CONFIG.Boards) do
		local store = stores[board.Id]
		local value = encode(board.Encode, statValue(profile, board.Stat))
		if store and value > 0 then
			local ok, err = pcall(function()
				store:SetAsync(tostring(profile.UserId), value)
			end)
			if not ok then
				warn(`[Leaderboards] Could not publish {board.Id} for {profile.UserId}: {err}`)
			end
		end
	end
end

function LeaderboardService:_publish()
	for _, profile in pairs(self.Services.DataService.Profiles) do
		if not profile.Temporary then
			self:_publishProfile(profile)
			task.wait(0.2)
		end
	end
end

local function resolveName(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(name) == "string" then
		nameCache[userId] = name
		return name
	end
	return "Player " .. tostring(userId)
end

function LeaderboardService:_refresh()
	for _, board in ipairs(CONFIG.Boards) do
		local store = stores[board.Id]
		local ok, pages = pcall(function()
			return store:GetSortedAsync(false, CONFIG.TopCount)
		end)
		if ok and pages then
			local entries = {}
			local okPage, page = pcall(function()
				return pages:GetCurrentPage()
			end)
			if okPage then
				for rank, entry in ipairs(page) do
					local userId = tonumber(entry.key)
					if userId then
						table.insert(entries, {
							Rank = rank,
							UserId = userId,
							Name = resolveName(userId),
							Value = decode(board.Encode, entry.value),
						})
					end
				end
				self.Cache[board.Id] = entries
			end
		else
			warn(`[Leaderboards] Could not refresh {board.Id}: {pages}`)
		end
	end
	self.UpdatedAt = os.time()
end

-- Live ranking of players in this server.
function LeaderboardService:ServerBoard()
	local out = {}
	for _, profile in pairs(self.Services.DataService.Profiles) do
		table.insert(out, {
			UserId = profile.UserId,
			Name = profile.Player.Name,
			DisplayName = profile.Player.DisplayName,
			LifetimeSparks = profile.Data.Stats.LifetimeSparks,
			TotalClicks = profile.Data.Stats.TotalClicks,
			Rebirths = profile.Data.Rebirths,
		})
	end
	table.sort(out, function(a, b)
		return a.LifetimeSparks > b.LifetimeSparks
	end)
	return out
end

return LeaderboardService
