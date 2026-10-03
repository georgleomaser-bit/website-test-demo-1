-- Globale Bestenliste (alle Server): Top 10 "Meistes Geld verdient" am Spawn-Platz.
-- Die Tafel steht an PlotService.LeaderboardCFrame (Vorderseite zeigt zur Platzmitte).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))

local LeaderboardService = {}
local Services

local UPDATE_INTERVAL = 300 -- alle 5 Minuten (schont DataStore-Limits)
local MAX_VALUE = 9e18

local store: OrderedDataStore? = nil
local rowsFrame: Frame

local function buildBoard()
	local board = Instance.new("Part")
	board.Name = "Leaderboard"
	board.Anchored = true
	board.Size = Vector3.new(36, 24, 1)
	board.CFrame = Services.PlotService.LeaderboardCFrame
	board.Color = Color3.fromRGB(25, 20, 35)
	board.Material = Enum.Material.SmoothPlastic
	board.CanTouch = false
	board.Parent = Services.PlotService.MapFolder or workspace

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front -- LookVector der CFrame zeigt zur Platzmitte
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 25
	gui.LightInfluence = 0
	gui.Parent = board

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0.14, 0)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 190, 60)
	title.Text = "🏆 TOP 10 – MEISTES GELD 🏆"
	title.Parent = gui

	rowsFrame = Instance.new("Frame")
	rowsFrame.BackgroundTransparency = 1
	rowsFrame.Position = UDim2.new(0.05, 0, 0.16, 0)
	rowsFrame.Size = UDim2.new(0.9, 0, 0.82, 0)
	rowsFrame.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = rowsFrame
end

local function setRows(rows: { { Name: string, Value: number } })
	for _, child in ipairs(rowsFrame:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	if #rows == 0 then
		rows = { { Name = "Noch keine Einträge – sei der Erste!", Value = -1 } }
	end
	for i, row in ipairs(rows) do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0.1, 0)
		label.LayoutOrder = i
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = i == 1 and Color3.fromRGB(255, 215, 0)
			or i == 2 and Color3.fromRGB(220, 220, 230)
			or i == 3 and Color3.fromRGB(230, 150, 90)
			or Color3.new(1, 1, 1)
		label.Text = row.Value >= 0 and (("#%d  %s  –  %s"):format(i, row.Name, Util.FormatCash(row.Value)))
			or row.Name
		label.Parent = rowsFrame
	end
end

local function savePlayer(player: Player)
	local data = Services.DataService.Get(player)
	if not store or not data then
		return
	end
	local value = math.floor(math.clamp(data.TotalEarned, 0, MAX_VALUE))
	pcall(function()
		(store :: OrderedDataStore):SetAsync(tostring(player.UserId), value)
	end)
end

local nameCache: { [number]: string } = {}
local function nameFor(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	nameCache[userId] = ok and name or ("User " .. userId)
	return nameCache[userId]
end

local function refresh()
	if not store then
		return
	end
	local ok, pages = pcall(function()
		return (store :: OrderedDataStore):GetSortedAsync(false, 10)
	end)
	if not ok then
		return
	end
	local rows = {}
	for _, item in ipairs(pages:GetCurrentPage()) do
		local userId = tonumber(item.key)
		if userId then
			table.insert(rows, { Name = nameFor(userId), Value = item.value })
		end
	end
	setRows(rows)
end

function LeaderboardService.Init(services)
	Services = services
	pcall(function()
		store = DataStoreService:GetOrderedDataStore(Config.LeaderboardStoreName)
	end)
	buildBoard()
	setRows({})
end

function LeaderboardService.Start()
	Services.DataService.OnProfileReleasing(function(player)
		task.spawn(savePlayer, player)
	end)
	task.spawn(function()
		task.wait(10)
		while true do
			for _, player in ipairs(Players:GetPlayers()) do
				savePlayer(player)
				task.wait(0.5)
			end
			refresh()
			task.wait(UPDATE_INTERVAL)
		end
	end)
end

return LeaderboardService
