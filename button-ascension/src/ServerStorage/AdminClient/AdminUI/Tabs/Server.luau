--[[
	Server tab (ModuleScript)
	Location: ServerStorage/AdminClient/AdminUI/Tabs/Server
	Depends on: AdminUI/Widgets, ReplicatedStorage/Shared/Format, ReplicatedStorage/Shared/Config/GameConfig
	Server actions: server.announce, server.eventStart, server.eventStop, server.stats, dashboard

	Announcements are filtered by Roblox text filtering on the server.
	"Server-wide" reaches only this server. "Game-wide" uses MessagingService
	and is only offered when the role has server.announce.global and the game
	owner enabled cross-server announcements.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))

local Widgets = require(script.Parent.Parent.Widgets)

local UI = Widgets.UI
local P = Widgets.P
local F = Widgets.Theme.Fonts

local EVENTS = GameConfig.Events

return function(ctx, container: Frame)
	local scroll = Widgets.scroll(container)
	local globalAllowed = ctx.has("server.announce.global") and ctx.Hello.CrossServer == true

	-- Announcements ------------------------------------------------------------------------------
	local announceSection = Widgets.section(scroll, "Announcement", 1, "Shown to players as a banner. Text is filtered by Roblox before it is displayed.")
	local message = Widgets.textbox({
		Placeholder = "Message (max 200 characters)",
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = 1,
		MaxLength = 200,
		Parent = announceSection,
	})
	local counter = Widgets.dim({ Text = "0 / 200", TextSize = 12, LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 14), TextXAlignment = Enum.TextXAlignment.Right, Parent = announceSection })
	message:GetPropertyChangedSignal("Text"):Connect(function()
		counter.Text = `{#message.Text} / 200`
	end)

	local scopeOptions = { { Id = "server", Text = "📣 Server-wide (this server only)" } }
	if globalAllowed then
		table.insert(scopeOptions, { Id = "global", Text = "🌐 Game-wide (all servers)", Color = P.Accent2 })
	end
	local scope = Widgets.chips({ Parent = announceSection, Options = scopeOptions, Value = "server", Order = 3, Height = 30 })
	if not globalAllowed then
		Widgets.dim({
			Text = if ctx.has("server.announce.global")
				then "Game-wide announcements are disabled in AdminConfig.CrossServerAnnouncements."
				else "Game-wide announcements need the server.announce.global permission (Owner by default).",
			TextSize = 12,
			TextWrapped = true,
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 4,
			Parent = announceSection,
		})
	end
	local send = Widgets.button({
		Text = "📣 Send announcement",
		Variant = "adminPrimary",
		Size = UDim2.fromOffset(200, 34),
		LayoutOrder = 5,
		OnClick = function()
			local text = string.gsub(message.Text, "^%s*(.-)%s*$", "%1")
			if text == "" then
				ctx.toast("Write a message first.", "error")
				return
			end
			local chosen = scope.Get()
			if chosen == "global" then
				local ok = UI.confirm({
					Title = "Send to every server?",
					Message = "This game-wide announcement will appear in all running servers of the game.",
					ConfirmText = "Send game-wide",
					Palette = P,
				})
				if not ok then
					return
				end
			end
			local response = ctx.Net.run("server.announce", { Message = text, Scope = chosen }, { Label = "Announcement" })
			if response.ok then
				message.Text = ""
			end
		end,
		Parent = announceSection,
	})
	Widgets.gate(send, ctx.has("server.announce"), "server.announce")

	-- Events ---------------------------------------------------------------------------------------
	local eventsSection = Widgets.section(scroll, "Boost events (this server)", 2, `Duration in seconds ({EVENTS.MinDuration}–{EVENTS.MaxDuration}).`)
	local canEvents = ctx.has("server.events")
	local active: { [string]: any } = {}
	local statusLabels: { [string]: TextLabel } = {}

	for index, id in ipairs(EVENTS.Order) do
		local def = EVENTS.Definitions[id]
		local row = UI.new("Frame", {
			Name = id,
			Size = UDim2.new(1, 0, 0, 56),
			BackgroundColor3 = P.Background,
			LayoutOrder = index,
			Corner = 10,
			Stroke = { Color = def.Color, Transparency = 0.6 },
			Parent = eventsSection,
		})
		Widgets.label({ Text = def.Icon, TextSize = 24, Size = UDim2.fromOffset(44, 56), TextXAlignment = Enum.TextXAlignment.Center, Parent = row })
		Widgets.label({ Text = def.Name, Font = F.Bold, TextColor3 = def.Color, Size = UDim2.new(1, -420, 0, 20), Position = UDim2.fromOffset(46, 8), Parent = row })
		Widgets.dim({ Text = def.Description, TextSize = 12, Size = UDim2.new(1, -420, 0, 16), Position = UDim2.fromOffset(46, 30), TextTruncate = Enum.TextTruncate.AtEnd, Parent = row })
		statusLabels[id] = Widgets.dim({
			Text = "Inactive",
			TextSize = 12,
			Size = UDim2.fromOffset(110, 56),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -296, 0, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = row,
		})
		local duration = Widgets.textbox({
			Text = tostring(def.DefaultDuration),
			Size = UDim2.fromOffset(80, 30),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -204, 0.5, 0),
			MaxLength = 6,
			Parent = row,
		})
		local start = Widgets.button({
			Text = "Start",
			Variant = "adminPrimary",
			Size = UDim2.fromOffset(90, 30),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -108, 0.5, 0),
			OnClick = function()
				local seconds = tonumber(duration.Text)
				if not seconds then
					ctx.toast("Duration must be a number of seconds.", "error")
					return
				end
				ctx.Net.run("server.eventStart", { Event = id, Duration = math.floor(seconds) }, { Label = def.Name })
				ctx.refreshEvents()
			end,
			Parent = row,
		})
		local stop = Widgets.button({
			Text = "Stop",
			Variant = "adminSecondary",
			Size = UDim2.fromOffset(90, 30),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			OnClick = function()
				ctx.Net.run("server.eventStop", { Event = id }, { Label = def.Name })
				ctx.refreshEvents()
			end,
			Parent = row,
		})
		Widgets.gate(start, canEvents, "server.events")
		Widgets.gate(stop, canEvents, "server.events")
	end

	local function renderEvents()
		local now = workspace:GetServerTimeNow()
		for id, label in pairs(statusLabels) do
			local info = active[id]
			if info and info.EndsAt > now then
				label.Text = "● " .. Format.clock(info.EndsAt - now) .. " left"
				label.TextColor3 = P.Accent
			else
				label.Text = "Inactive"
				label.TextColor3 = P.TextDim
			end
		end
	end

	function ctx.refreshEvents()
		local response = ctx.Net.request("dashboard")
		if response.ok and type(response.data) == "table" then
			active = response.data.Events or {}
			renderEvents()
		end
	end

	-- Server stats -------------------------------------------------------------------------------------
	local statsSection = Widgets.section(scroll, "Server statistics", 3)
	local statsText = Widgets.dim({ Text = "Press refresh to load.", TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = statsSection })
	local refreshStats = Widgets.button({
		Text = "↻ Refresh statistics",
		Size = UDim2.fromOffset(180, 30),
		LayoutOrder = 2,
		OnClick = function()
			local response = ctx.Net.request("server.stats")
			if not response.ok or type(response.data) ~= "table" then
				statsText.Text = response.err or "Could not load statistics."
				statsText.TextColor3 = P.Danger
				return
			end
			local d = response.data
			local data = d.Data or {}
			statsText.TextColor3 = P.TextDim
			statsText.Text = table.concat({
				response.message or "",
				`Players: {#(d.Players or {})} / {d.MaxPlayers}   ·   Presses: {Format.commas(d.ServerPresses)} ({d.ServerCPS}/s)`,
				`Memory: {math.floor(d.MemoryMb or 0)} MB   ·   Physics: {math.floor(d.PhysicsFps or 0)} FPS   ·   Heartbeat: {string.format("%.1f", d.HeartbeatMs or 0)} ms`,
				`Data: {data.Mode} · {data.Saves or 0} saves · {data.SaveFailures or 0} failed saves · {data.LoadFailures or 0} failed loads`,
				`Server: {Widgets.shortId(d.JobId)} · place version {d.PlaceVersion}`,
			}, "\n")
		end,
		Parent = statsSection,
	})
	Widgets.gate(refreshStats, ctx.has("server.stats"), "server.stats")

	local tab = { AutoRefresh = 5 }
	function tab.Refresh()
		ctx.refreshEvents()
	end
	function tab.Tick()
		renderEvents()
	end
	function tab.OnShow()
		ctx.refreshEvents()
	end
	return tab
end
