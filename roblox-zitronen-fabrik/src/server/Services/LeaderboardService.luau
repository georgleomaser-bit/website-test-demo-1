--[[
	Globale Bestenliste "Reichste Fabriken" auf dem Platz (OrderedDataStore).
	Gespeichert wird log10(Gesamt-Einnahmen) * 1000, weil die Zahlen riesig werden.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Core = require(script.Parent.Core)

local LeaderboardService = {}

local store: OrderedDataStore? = nil
local board: Instance? = nil
local nameCache: { [number]: string } = {}

local function encode(amount: number): number
	if amount <= 1 then
		return 0
	end
	return math.floor(math.log10(amount) * 1000)
end

local function decode(value: number): number
	return 10 ^ (value / 1000)
end

local function nameOf(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and name then
		nameCache[userId] = name
		return name
	end
	return "Spieler " .. userId
end

local function pushScores()
	if not store then
		return
	end
	for player, session in pairs(Core.Sessions) do
		if session.Loaded and session.CanSave and session.Profile.AllTimeEarnings > 0 then
			pcall(function()
				(store :: OrderedDataStore):SetAsync(tostring(player.UserId), encode(session.Profile.AllTimeEarnings))
			end)
		end
	end
end

local function showRows(rows: { { Name: string, Amount: number } })
	if not board then
		return
	end
	local gui = board:FindFirstChild("BoardGui")
	local list = gui and gui:FindFirstChild("List")
	if not list then
		return
	end
	for i = 1, 10 do
		local label = list:FindFirstChild("Row" .. i) :: TextLabel?
		if label then
			local row = rows[i]
			label.Text = row and string.format("  %d.  %s   –   %s", i, row.Name, Format.Cash(row.Amount)) or ("  " .. i .. ".  ---")
		end
	end
end

local function refreshBoard()
	if store then
		local ok, pages = pcall(function()
			return (store :: OrderedDataStore):GetSortedAsync(false, 10)
		end)
		if ok and pages then
			local rows = {}
			for _, entry in ipairs(pages:GetCurrentPage()) do
				local userId = tonumber(entry.key)
				if userId then
					table.insert(rows, { Name = nameOf(userId), Amount = decode(entry.value) })
				end
			end
			showRows(rows)
			return
		end
	end
	-- Ohne DataStore (z. B. in Studio): Spieler auf diesem Server anzeigen
	local rows = {}
	for player, session in pairs(Core.Sessions) do
		if session.Loaded then
			table.insert(rows, { Name = player.DisplayName, Amount = session.Profile.AllTimeEarnings })
		end
	end
	table.sort(rows, function(a, b)
		return a.Amount > b.Amount
	end)
	showRows(rows)
end

function LeaderboardService.Init(world: Instance)
	local lobby = world:WaitForChild("Lobby")
	local model = lobby:FindFirstChild("Leaderboard")
	board = model and model:FindFirstChild("Board")
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(Config.LeaderboardStoreName)
	end)
	if ok then
		store = result
	end
end

function LeaderboardService.Start()
	task.spawn(function()
		task.wait(5)
		while true do
			pushScores()
			refreshBoard()
			task.wait(90)
		end
	end)
end

return LeaderboardService
