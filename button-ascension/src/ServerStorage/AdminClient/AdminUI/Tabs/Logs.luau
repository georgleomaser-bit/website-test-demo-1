--[[
	Audit Logs tab (ModuleScript)
	Location: ServerStorage/AdminClient/AdminUI/Tabs/Logs
	Depends on: AdminUI/Widgets, AdminUI/LogRow
	Server actions: logs.recent { Filter, Result, Limit }, logs.security, logs.persisted { Day }
	Push: AdminPush "log" appends new entries live while the audit view is shown.

	Three views: this server's audit log (live), security flags (suspicious
	client requests) and the persisted audit log of every server for a UTC day.
]]

local Widgets = require(script.Parent.Parent.Widgets)
local LogRow = require(script.Parent.Parent.LogRow)

local UI = Widgets.UI
local P = Widgets.P

local MAX_ROWS = 300

local RESULTS = {
	{ Id = "all", Text = "All" },
	{ Id = "success", Text = "Success", Color = Widgets.Result.success },
	{ Id = "denied", Text = "Denied", Color = Widgets.Result.denied },
	{ Id = "invalid", Text = "Invalid", Color = Widgets.Result.invalid },
	{ Id = "error", Text = "Error", Color = Widgets.Result.error },
	{ Id = "rate_limited", Text = "Rate limited", Color = Widgets.Result.rate_limited },
	{ Id = "confirm_required", Text = "Confirm", Color = Widgets.Result.confirm_required },
	{ Id = "duplicate", Text = "Duplicate", Color = Widgets.Result.duplicate },
}

return function(ctx, container: Frame)
	local mode = "audit"
	local resultFilter = "all"
	local entries: { any } = {}
	local rows: { Frame } = {}

	local controls = UI.frame({ Name = "Controls", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, List = { Pad = 6 }, Parent = container })
	local topRow = Widgets.row(controls, 1, 32)
	local modeChips
	local search = Widgets.textbox({ Placeholder = "🔍 Filter by admin, action, target, UserId…", Size = UDim2.new(1, -500, 0, 32), LayoutOrder = 2, MaxLength = 60, Parent = topRow })
	local dayBox = Widgets.textbox({ Text = Widgets.today(), Size = UDim2.fromOffset(110, 32), LayoutOrder = 3, MaxLength = 10, Parent = topRow })
	local loadDay = Widgets.button({ Text = "Load day", Size = UDim2.fromOffset(100, 32), LayoutOrder = 4, Variant = "adminMagenta", Parent = topRow })
	Widgets.gate(loadDay, ctx.has("logs.persisted"), "logs.persisted")
	local refresh = Widgets.button({ Text = "↻", Size = UDim2.fromOffset(40, 32), LayoutOrder = 5, Parent = topRow })

	local resultChips = Widgets.chips({
		Parent = controls,
		Options = RESULTS,
		Value = "all",
		Order = 2,
		Height = 26,
		OnChange = function(id)
			resultFilter = id
			ctx.refreshLogs()
		end,
	})
	local status = Widgets.dim({ Text = "", TextSize = 12, LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 16), Parent = controls })

	local list = UI.scroll({
		Name = "Entries",
		Position = UDim2.fromOffset(0, 110),
		Size = UDim2.new(1, 0, 1, -110),
		ScrollBarImageColor3 = P.Stroke,
		List = { Pad = 4 },
		Padding = { 0, 8, 0, 4 },
		Parent = container,
	})
	-- Keep the list just below the controls even when the chip row wraps.
	-- The top row has a fixed 32 px height, which gives the current UI scale.
	local function placeList()
		local scale = topRow.AbsoluteSize.Y / 32
		if scale <= 0 then
			return
		end
		local height = math.ceil(controls.AbsoluteSize.Y / scale) + 8
		list.Position = UDim2.fromOffset(0, height)
		list.Size = UDim2.new(1, 0, 1, -height)
	end
	controls:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeList)
	topRow:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeList)

	local function render()
		local filler = if mode == "security" then LogRow.fillSecurity else LogRow.fillAudit
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
	end

	local function setEntries(list_: { any }, text: string)
		entries = {}
		for i = 1, math.min(MAX_ROWS, #list_) do
			entries[i] = list_[i]
		end
		status.Text = text
		render()
	end

	function ctx.refreshLogs()
		if mode == "security" then
			local response = ctx.Net.request("logs.security")
			if response.ok and type(response.data) == "table" then
				setEntries(response.data.Entries or {}, `Security flags in this server (newest first): {#(response.data.Entries or {})}`)
			else
				status.Text = response.err or "Could not load security flags."
			end
			return
		end
		local response = ctx.Net.request("logs.recent", { Filter = search.Text, Result = resultFilter, Limit = MAX_ROWS })
		if response.ok and type(response.data) == "table" then
			setEntries(response.data.Entries or {}, `Audit log of this server (newest first, live): {#(response.data.Entries or {})} entries`)
		else
			status.Text = response.err or "Could not load the audit log."
		end
	end

	modeChips = Widgets.chips({
		Parent = topRow,
		Options = { { Id = "audit", Text = "📜 Audit" }, { Id = "security", Text = "🚩 Security" } },
		Value = "audit",
		Order = 1,
		Height = 32,
		Width = 100,
		OnChange = function(id)
			mode = id
			resultChips.Frame.Visible = id == "audit"
			for _, row in ipairs(rows) do
				row:Destroy()
			end
			rows = {}
			ctx.refreshLogs()
		end,
	})
	modeChips.Frame.Size = UDim2.fromOffset(212, 32)
	modeChips.Frame.AutomaticSize = Enum.AutomaticSize.None

	local searchVersion = 0
	search:GetPropertyChangedSignal("Text"):Connect(function()
		searchVersion += 1
		local mine = searchVersion
		task.delay(0.4, function()
			if mine == searchVersion and mode == "audit" then
				ctx.refreshLogs()
			end
		end)
	end)
	refresh.Activated:Connect(function()
		ctx.refreshLogs()
	end)
	loadDay.Activated:Connect(function()
		if loadDay:GetAttribute("Disabled") then
			return
		end
		local day = string.gsub(dayBox.Text, "%s", "")
		if not string.match(day, "^%d%d%d%d%-%d%d%-%d%d$") then
			ctx.toast("Use the format YYYY-MM-DD.", "error")
			return
		end
		local response = ctx.Net.request("logs.persisted", { Day = day })
		if response.ok and type(response.data) == "table" then
			mode = "persisted"
			modeChips.Set(nil)
			resultChips.Frame.Visible = false
			for _, row in ipairs(rows) do
				row:Destroy()
			end
			rows = {}
			setEntries(response.data.Entries or {}, `Persisted audit log for {day} (all servers, newest first): {#(response.data.Entries or {})} entries — press Audit to return to live view.`)
			ctx.log(response.message or "Loaded persisted logs.", "ok")
		else
			ctx.toast(response.err or "Could not load persisted logs.", "error")
		end
	end)

	local function matches(entry): boolean
		if resultFilter ~= "all" and entry.Result ~= resultFilter then
			return false
		end
		local needle = string.lower(search.Text)
		if needle == "" then
			return true
		end
		local hay = string.lower(table.concat({
			tostring(entry.Action),
			tostring(entry.AdminName),
			tostring(entry.TargetName),
			tostring(entry.Params),
			tostring(entry.Message),
			tostring(entry.AdminId),
			tostring(entry.TargetId),
		}, " "))
		return string.find(hay, needle, 1, true) ~= nil
	end

	ctx.LogPushed:Connect(function(entry)
		if mode ~= "audit" or not matches(entry) then
			return
		end
		table.insert(entries, 1, entry)
		if #entries > MAX_ROWS then
			table.remove(entries)
		end
		if container.Visible then
			render()
		end
	end)

	local tab = {}
	function tab.OnShow()
		ctx.refreshLogs()
	end
	return tab
end
