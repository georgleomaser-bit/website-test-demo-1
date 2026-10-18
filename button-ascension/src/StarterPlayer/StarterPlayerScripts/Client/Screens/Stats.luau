--[[
	Stats (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Screens/Stats
	Depends on: ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format,Formulas,Util,Config/*},
	            Client/{State,ClientNet}

	Personal statistics and leaderboards (global boards from OrderedDataStores,
	refreshed by the server every couple of minutes, plus a live board for the
	current server).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIFolder = ReplicatedStorage:WaitForChild("UI")
local UI = require(UIFolder.UIKit)
local Theme = require(UIFolder.Theme)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Util = require(Shared.Util)
local Config = Shared.Config
local GameConfig = require(Config.GameConfig)
local Items = require(Config.Items)

local Client = script.Parent.Parent
local State = require(Client.State)
local ClientNet = require(Client.ClientNet)

local C = Theme.Colors
local F = Theme.Fonts

local StatsScreen = {}

local TILES = {
	{ "Total presses", function(v, s)
		return Format.commas(s.TotalClicks)
	end },
	{ "Auto presses", function(v, s)
		return Format.commas(s.AutoClicks)
	end },
	{ "Lifetime Sparks", function(v, s)
		return Format.short(s.LifetimeSparks)
	end },
	{ "Sparks this run", function(v, s)
		return Format.short(s.SparksThisRun)
	end },
	{ "Best run", function(v, s)
		return Format.short(s.BestRunSparks)
	end },
	{ "Ascensions", function(v)
		return tostring(v.Rebirths)
	end },
	{ "Level", function(v)
		return tostring(v.Level)
	end },
	{ "Crates opened", function(v, s)
		return Format.commas(s.ChestsOpened)
	end },
	{ "Items discovered", function(v)
		return `{Formulas.discoveredCount(v)} / {Items.Count}`
	end },
	{ "Legendary+ found", function(v, s)
		return Format.commas(s.LegendariesFound)
	end },
	{ "Mythic+ found", function(v, s)
		return Format.commas(s.MythicsFound)
	end },
	{ "Secrets found", function(v, s)
		return Format.commas(s.SecretsFound)
	end },
	{ "Critical presses", function(v, s)
		return Format.commas(s.TotalCrits)
	end },
	{ "Highest combo", function(v, s)
		return Format.commas(s.HighestCombo)
	end },
	{ "Streak bursts", function(v, s)
		return Format.commas(s.StreakBursts)
	end },
	{ "Golden presses", function(v, s)
		return Format.commas(s.GoldenClicks)
	end },
	{ "Upgrades bought", function(v, s)
		return Format.commas(s.UpgradesPurchased)
	end },
	{ "Items sold", function(v, s)
		return Format.commas(s.ItemsSold)
	end },
	{ "Quests completed", function(v, s)
		return Format.commas(s.QuestsCompleted)
	end },
	{ "Orbs collected", function(v, s)
		return Format.commas(s.OrbsCollected)
	end },
	{ "Gems earned", function(v, s)
		return Format.short(s.GemsEarned)
	end },
	{ "Prisms earned", function(v, s)
		return Format.short(s.PrismsEarned)
	end },
	{ "Offline earnings", function(v, s)
		return Format.short(s.OfflineEarned)
	end },
	{ "Best login streak", function(v, s)
		return Format.commas(s.BestDailyStreak)
	end },
	{ "Time played", function(v, s)
		return Format.time(s.PlayTime)
	end },
}

function StatsScreen.new(ctx)
	local window = UI.window({
		Name = "Stats",
		Title = "Statistics & Leaderboards",
		Subtitle = "Global boards update every few minutes.",
		Icon = "🏆",
		Parent = ctx.Layers.Windows,
	})
	local screen: { [string]: any } = { Window = window }
	local body = window.Body
	local tab = "Stats"
	local board = GameConfig.Leaderboards.Boards[1].Id
	local scope = "Global"
	local cache = nil
	local lastFetch = 0

	UI.segmented({
		Options = { { Id = "Stats", Text = "📊 My stats" }, { Id = "Boards", Text = "🏆 Leaderboards" } },
		Value = "Stats",
		ButtonWidth = 170,
		OnChange = function(id)
			tab = id
			screen.Refresh()
		end,
		Parent = body,
	})

	local statsPage = UI.scroll({
		Size = UDim2.new(1, 0, 1, -50),
		Position = UDim2.fromOffset(0, 50),
		Grid = { Cell = UDim2.fromOffset(206, 70), Pad = UDim2.fromOffset(10, 10) },
		Padding = { 2, 8, 2, 8 },
		Parent = body,
	})
	local tiles = {}
	for index, spec in ipairs(TILES) do
		local tile = UI.panel({ Size = UDim2.fromOffset(206, 70), BackgroundColor3 = C.PanelLight, LayoutOrder = index, Padding = 12, Parent = statsPage })
		UI.label({ Text = spec[1], TextSize = 13, TextColor3 = C.TextDim, Size = UDim2.new(1, 0, 0, 16), Parent = tile })
		local value = UI.label({ Text = "", Font = F.Heading, TextSize = 21, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 20), Parent = tile })
		tiles[index] = { Value = value, Fn = spec[2] }
	end

	local boardsPage = UI.frame({ Size = UDim2.new(1, 0, 1, -50), Position = UDim2.fromOffset(0, 50), Visible = false, Parent = body })
	local boardOptions = {}
	for _, b in ipairs(GameConfig.Leaderboards.Boards) do
		table.insert(boardOptions, { Id = b.Id, Text = `{b.Icon} {b.Name}` })
	end
	UI.segmented({
		Options = boardOptions,
		Value = board,
		ButtonWidth = 150,
		OnChange = function(id)
			board = id
			screen.Refresh()
		end,
		Parent = boardsPage,
	})
	UI.segmented({
		Options = { { Id = "Global", Text = "🌐 Global" }, { Id = "Server", Text = "🖥️ Server" } },
		Value = "Global",
		ButtonWidth = 100,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		OnChange = function(id)
			scope = id
			screen.Refresh()
		end,
		Parent = boardsPage,
	})
	local status = UI.label({ Text = "", TextSize = 13, TextColor3 = C.TextDim, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 42), Parent = boardsPage })
	local rowsFrame = UI.scroll({ Size = UDim2.new(1, 0, 1, -70), Position = UDim2.fromOffset(0, 66), List = { Dir = "Y", Pad = 4 }, Padding = { 2, 8, 2, 2 }, Parent = boardsPage })
	local rows = {}

	local function row(i: number)
		local r = rows[i]
		if r then
			return r
		end
		local frame = UI.panel({ Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = C.PanelLight, LayoutOrder = i, Parent = rowsFrame })
		local rank = UI.label({ Text = "", Font = F.Heading, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(56, 40), Parent = frame })
		local name = UI.label({ Text = "", Font = F.Bold, TextSize = 15, Size = UDim2.new(1, -240, 1, 0), Position = UDim2.fromOffset(56, 0), Parent = frame })
		local value = UI.label({
			Text = "",
			Font = F.Heading,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 0),
			Size = UDim2.fromOffset(170, 40),
			Parent = frame,
		})
		r = { Frame = frame, Rank = rank, Name = name, Value = value }
		rows[i] = r
		return r
	end

	local function fetch(force: boolean)
		if not force and cache and os.clock() - lastFetch < 30 then
			return
		end
		lastFetch = os.clock()
		local result = ClientNet.action("GetLeaderboards")
		if result.ok then
			cache = result
		end
	end

	local function formatValue(boardId: string, value: number): string
		if boardId == "LifetimeSparks" then
			return "⚡ " .. Format.short(value)
		end
		return Format.commas(value)
	end

	function screen.Refresh()
		if not window.IsOpen() then
			return
		end
		statsPage.Visible = tab == "Stats"
		boardsPage.Visible = tab == "Boards"
		if tab == "Stats" then
			local view = State.view()
			for _, tile in ipairs(tiles) do
				tile.Value.Text = tile.Fn(view, view.Stats)
			end
			return
		end
		local entries = {}
		if cache then
			if scope == "Global" then
				entries = (cache.Global or {})[board] or {}
				status.Text = if cache.Available
					then (if #entries > 0 then `Updated {Format.time(math.max(0, Util.serverTime() - (cache.UpdatedAt or Util.serverTime())))} ago` else "No entries yet — the board refreshes every few minutes.")
					else "Global leaderboards are unavailable in this session (DataStores disabled)."
			else
				local stat = if board == "LifetimeSparks" then "LifetimeSparks" elseif board == "TotalClicks" then "TotalClicks" else "Rebirths"
				for _, e in ipairs(cache.Server or {}) do
					table.insert(entries, { UserId = e.UserId, Name = e.DisplayName or e.Name, Value = e[stat] or 0 })
				end
				table.sort(entries, function(a, b)
					return a.Value > b.Value
				end)
				for i, e in ipairs(entries) do
					e.Rank = i
				end
				status.Text = `{#entries} player(s) in this server`
			end
		else
			status.Text = "Loading…"
		end
		local me = Players.LocalPlayer.UserId
		for i, e in ipairs(entries) do
			local r = row(i)
			r.Frame.Visible = true
			r.Rank.Text = if e.Rank == 1 then "🥇" elseif e.Rank == 2 then "🥈" elseif e.Rank == 3 then "🥉" else "#" .. tostring(e.Rank)
			r.Name.Text = e.Name or ("Player " .. tostring(e.UserId))
			r.Value.Text = formatValue(board, e.Value or 0)
			r.Frame.BackgroundColor3 = if e.UserId == me then Theme.darken(C.Accent2, 0.75) else C.PanelLight
		end
		for i = #entries + 1, #rows do
			rows[i].Frame.Visible = false
		end
	end

	window.Opened.Event:Connect(function()
		screen.Refresh()
		task.spawn(function()
			fetch(false)
			screen.Refresh()
		end)
	end)
	State.subscribe({ "Stats", "Progress", "Discovered" }, function()
		if tab == "Stats" then
			screen.Refresh()
		end
	end)
	return screen
end

return StatsScreen
