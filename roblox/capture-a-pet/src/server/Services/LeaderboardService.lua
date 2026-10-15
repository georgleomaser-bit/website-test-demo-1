-- Global top 10 boards in the hub (Cash and Speed). Values are stored as log10 so even
-- quadrillions fit into an OrderedDataStore integer.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Format = require(Shared.Format)

local LeaderboardService = {}

local S
local stores = {}
local UPDATE_SECONDS = 120
local nameCache = {}

function LeaderboardService.Init(services)
	S = services
	pcall(function()
		stores.Cash = DataStoreService:GetOrderedDataStore("TopCash_v1")
		stores.Speed = DataStoreService:GetOrderedDataStore("TopSpeed_v1")
	end)
end

local function encode(value: number): number
	return math.floor(math.log10(math.max(0, value) + 1) * 1e6)
end

local function decode(stored: number): number
	return 10 ^ (stored / 1e6) - 1
end

local function nameOf(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	name = ok and name or ("Player " .. userId)
	nameCache[userId] = name
	return name
end

local function renderBoard(list: Frame, rows, prefix: string)
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("TextLabel") and child.Name == "Row" then
			child:Destroy()
		end
	end
	for rank, row in ipairs(rows) do
		local label = Instance.new("TextLabel")
		label.Name = "Row"
		label.LayoutOrder = rank
		label.Size = UDim2.new(1, 0, 0, 48)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		local color = rank == 1 and "#FFD84A" or rank == 2 and "#D9D9D9" or rank == 3 and "#E39B5B" or "#FFFFFF"
		label.RichText = true
		label.Text = string.format('  <font color="%s">#%d</font>  %s  <font color="#7CFF6B">%s%s</font>', color, rank, row.Name, prefix, Format.number(row.Value))
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Parent = list
	end
end

local function refresh()
	local boards = S.WorldBuilder.World.Boards
	for key, store in pairs(stores) do
		local ok, pages = pcall(function()
			return store:GetSortedAsync(false, 10)
		end)
		if ok and pages then
			local rows = {}
			for _, entry in ipairs(pages:GetCurrentPage()) do
				local userId = tonumber(string.match(entry.key, "%d+"))
				if userId then
					table.insert(rows, { Name = nameOf(userId), Value = decode(entry.value) })
				end
			end
			renderBoard(boards[key], rows, key == "Cash" and "$" or "")
		end
	end
end

local function submit(player: Player)
	local data = S.DataService.get(player)
	if not data then
		return
	end
	local key = "U" .. player.UserId
	if stores.Cash then
		pcall(function()
			stores.Cash:SetAsync(key, encode(data.Stats.TotalCash))
		end)
	end
	if stores.Speed then
		pcall(function()
			stores.Speed:SetAsync(key, encode(data.Stats.TotalSpeed))
		end)
	end
end

function LeaderboardService.Start()
	if not stores.Cash then
		return
	end
	task.spawn(function()
		task.wait(10)
		while true do
			for _, player in ipairs(Players:GetPlayers()) do
				submit(player)
			end
			refresh()
			task.wait(UPDATE_SECONDS)
		end
	end)
	S.DataService.onReleasing(function(player)
		task.spawn(submit, player)
	end)
end

return LeaderboardService
