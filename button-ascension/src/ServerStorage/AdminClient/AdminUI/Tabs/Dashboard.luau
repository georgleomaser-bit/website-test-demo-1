--[[
	Dashboard tab (ModuleScript)
	Location: ServerStorage/AdminClient/AdminUI/Tabs/Dashboard
	Depends on: AdminUI/Widgets, AdminUI/LogRow, ReplicatedStorage/Shared/Format,
	            ReplicatedStorage/Shared/Config/GameConfig
	Server actions: dashboard (read-only, refreshed every 5 s while visible)

	Server health at a glance: players, uptime, presses, memory, physics,
	heartbeat, DataStore status, events, security flags, recent admin actions.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))

local Widgets = require(script.Parent.Parent.Widgets)
local LogRow = require(script.Parent.Parent.LogRow)

local UI = Widgets.UI
local P = Widgets.P

return function(ctx, container: Frame)
	local scroll = Widgets.scroll(container)

	local grid = UI.frame({ Name = "Cards", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = scroll })
	UI.grid(grid, { Cell = UDim2.new(0.25, -8, 0, 76), Pad = UDim2.fromOffset(10, 10) })

	local cards = {
		players = Widgets.card(grid, "Players online", 1),
		uptime = Widgets.card(grid, "Uptime", 2),
		presses = Widgets.card(grid, "Server presses", 3),
		memory = Widgets.card(grid, "Memory", 4),
		physics = Widgets.card(grid, "Physics", 5),
		heartbeat = Widgets.card(grid, "Heartbeat", 6),
		data = Widgets.card(grid, "Data saving", 7),
		security = Widgets.card(grid, "Security flags", 8),
	}

	local eventsSection = Widgets.section(scroll, "Active events", 2)
	local eventsText = Widgets.dim({ Text = "Loading…", TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = eventsSection })

	local dataSection = Widgets.section(scroll, "DataStore status", 3)
	local dataText = Widgets.dim({ Text = "", TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = dataSection })

	local split = UI.frame({ Name = "Split", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4, List = { Dir = "X", Pad = 10 }, Parent = scroll })
	local function half(title: string, order: number)
		local holder = UI.frame({ Size = UDim2.new(0.5, -5, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, List = { Pad = 0 }, Parent = split })
		local section = Widgets.section(holder, title, 1)
		local list = UI.frame({ Name = "List", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, List = { Pad = 4 }, Parent = section })
		return list
	end
	local logsList = half("Recent admin actions", 1)
	local securityList = half("Recent security flags", 2)

	local logRows, securityRows = {}, {}
	local function fill(list: Frame, rows: { Frame }, entries: { any }, filler, emptyText: string)
		for i, entry in ipairs(entries) do
			local row = rows[i]
			if not row then
				row = LogRow.create(list, ctx.Prefs.Compact)
				rows[i] = row
			end
			row.LayoutOrder = i
			row.Visible = true
			filler(row, entry)
		end
		for i = #entries + 1, #rows do
			rows[i].Visible = false
		end
		local empty = list:FindFirstChild("Empty")
		if #entries == 0 and not empty then
			Widgets.dim({ Name = "Empty", Text = emptyText, LayoutOrder = 999, Parent = list })
		elseif #entries > 0 and empty then
			empty:Destroy()
		end
	end

	local lastEvents = {}
	local function renderEvents()
		local lines = {}
		local now = workspace:GetServerTimeNow()
		for _, id in ipairs(GameConfig.Events.Order) do
			local info = lastEvents[id]
			local def = GameConfig.Events.Definitions[id]
			if info and def then
				table.insert(lines, `{def.Icon} {def.Name} — {Format.clock(info.EndsAt - now)} left (started by {info.StartedBy})`)
			end
		end
		eventsText.Text = if #lines > 0 then table.concat(lines, "\n") else "No boost events are running in this server."
	end

	local tab = { AutoRefresh = 5 }

	function tab.Refresh()
		local response = ctx.Net.request("dashboard")
		if not response.ok or type(response.data) ~= "table" then
			cards.players.Value.Text = "—"
			cards.players.Sub.Text = response.err or "Could not load."
			return
		end
		local d = response.data
		cards.players.Value.Text = `{#d.Players} / {d.MaxPlayers}`
		local loaded = 0
		for _, p in ipairs(d.Players) do
			if p.Loaded then
				loaded += 1
			end
		end
		cards.players.Sub.Text = `{loaded} loaded`
		ctx.Players = d.Players
		ctx.PlayersUpdated:Fire()
		cards.uptime.Value.Text = Format.time(d.Uptime)
		cards.uptime.Sub.Text = `place v{d.PlaceVersion}`
		cards.presses.Value.Text = Format.commas(d.ServerPresses)
		cards.presses.Sub.Text = `{d.ServerCPS} presses/s`
		cards.memory.Value.Text = `{math.floor(d.MemoryMb)} MB`
		cards.memory.Sub.Text = "total server memory"
		cards.physics.Value.Text = `{math.floor(d.PhysicsFps)} FPS`
		cards.physics.Sub.Text = "real physics rate"
		cards.heartbeat.Value.Text = string.format("%.1f ms", d.HeartbeatMs or 0)
		cards.heartbeat.Sub.Text = "heartbeat time"
		local data = d.Data or {}
		cards.data.Value.Text = if data.Mode == "persistent" then "Enabled" else "Temporary"
		cards.data.Value.TextColor3 = if data.Mode == "persistent" then P.Accent else P.Warning
		cards.data.Sub.Text = `{data.Saves or 0} saves · {data.SaveFailures or 0} failed`
		cards.security.Value.Text = Format.commas(d.SecurityFlags or 0)
		cards.security.Value.TextColor3 = if (d.SecurityFlags or 0) > 0 then P.Warning else P.Text
		cards.security.Sub.Text = "suspicious requests"

		dataText.Text = `Mode: {data.Mode or "?"}  ·  loads {data.Loads or 0} (failed {data.LoadFailures or 0})  ·  `
			.. `saves {data.Saves or 0} (failed {data.SaveFailures or 0})  ·  lock conflicts {data.LockConflicts or 0}\n`
			.. `Last error: {data.LastError or "none"}\n`
			.. `Audit logs persisted: {if d.AuditPersist then "yes" else "no (memory only)"}`

		lastEvents = d.Events or {}
		renderEvents()
		fill(logsList, logRows, d.RecentLogs or {}, LogRow.fillAudit, if ctx.has("logs.view") then "No admin actions yet." else "Requires logs.view.")
		fill(securityList, securityRows, d.RecentSecurity or {}, LogRow.fillSecurity, "No security flags. 👍")
	end

	function tab.Tick()
		renderEvents()
	end

	function tab.OnShow()
		tab.Refresh()
	end

	return tab
end
