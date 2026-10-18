--[[
	Moderation tab (ModuleScript)
	Location: ServerStorage/AdminClient/AdminUI/Tabs/Moderation
	Depends on: AdminUI/Widgets, AdminUI/TargetPicker
	Server actions: players.ban, players.unban, players.bans,
	                staff.list, staff.setRole, staff.removeRole

	Bans work in every server and also for players who are offline (#UserId or
	their exact Roblox username). Owners can hand out the Moderator and Admin
	roles here. Everything is checked again on the server: the ban length limit
	of the role, rank protection, and that roles from AdminConfig cannot be
	changed. This tab only hides what the role cannot use.
]]

local Widgets = require(script.Parent.Parent.Widgets)
local TargetPicker = require(script.Parent.Parent.TargetPicker)

local UI = Widgets.UI
local P = Widgets.P
local F = Widgets.Theme.Fonts

local LENGTHS = {
	{ Id = "1h", Text = "1 hour", Days = 1 / 24 },
	{ Id = "1d", Text = "1 day", Days = 1 },
	{ Id = "7d", Text = "7 days", Days = 7 },
	{ Id = "30d", Text = "30 days", Days = 30 },
	{ Id = "perm", Text = "Permanent", Days = math.huge },
}

return function(ctx, container: Frame)
	local scroll = Widgets.scroll(container)
	local canBan = ctx.has("players.ban")
	local canStaff = ctx.has("staff.manage")
	local maxDays = ctx.Hello.MaxBanDays or 0 -- 0 = no limit
	local persistent = ctx.Hello.ModerationPersistent ~= false
	local tab: { [string]: any } = {}

	if not persistent then
		local note = Widgets.section(scroll, "⚠ Studio test session", 0)
		Widgets.dim({
			Text = "Roblox data services are not available here (enable Studio Access to API Services). Bans and roles only last until this session ends.",
			TextColor3 = P.Warning,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 1,
			Parent = note,
		})
	end

	local function targetBox(parent: Instance, order: number): TextBox
		local row = Widgets.row(parent, order, 34)
		Widgets.rowLabel(row, "Player", 70, 1)
		return Widgets.textbox({
			Placeholder = "name, @username or #UserId (also offline)",
			Size = UDim2.fromOffset(300, 32),
			LayoutOrder = 2,
			MaxLength = 50,
			Parent = row,
		})
	end

	-- Ban ------------------------------------------------------------------------------------------
	local banTarget: TextBox? = nil
	local banList: Frame? = nil

	if canBan then
		local limitText = if maxDays == 0 then "Your role can ban for any length, including permanently." else `Your role can ban for up to {maxDays} days.`
		local banSection = Widgets.section(scroll, "Ban a player", 1, "Bans apply in every server and keep the player out until they end. " .. limitText)
		banTarget = targetBox(banSection, 1)

		local options = {}
		for _, length in ipairs(LENGTHS) do
			if maxDays == 0 or length.Days <= maxDays then
				table.insert(options, { Id = length.Id, Text = length.Text, Color = if length.Id == "perm" then P.Danger else nil })
			end
		end
		local lengthRow = Widgets.row(banSection, 2, 30)
		Widgets.rowLabel(lengthRow, "Length", 70, 1)
		local chipsHolder = UI.frame({ Size = UDim2.new(1, -80, 0, 30), LayoutOrder = 2, Parent = lengthRow })
		local length = Widgets.chips({ Parent = chipsHolder, Options = options, Value = "1d", Height = 30 })

		local reasonRow = Widgets.row(banSection, 3, 34)
		Widgets.rowLabel(reasonRow, "Reason", 70, 1)
		local reason = Widgets.textbox({
			Placeholder = "Shown to the player (filtered by Roblox)",
			Size = UDim2.new(1, -80, 0, 32),
			LayoutOrder = 2,
			MaxLength = 200,
			Parent = reasonRow,
		})

		Widgets.button({
			Text = "🚫 Ban",
			Variant = "adminDanger",
			Size = UDim2.fromOffset(140, 34),
			LayoutOrder = 4,
			OnClick = function()
				local query = TargetPicker.queryFromText((banTarget :: TextBox).Text)
				local text = string.gsub(reason.Text, "^%s*(.-)%s*$", "%1")
				if not query then
					ctx.toast("Enter a player first.", "error")
					return
				end
				if text == "" then
					ctx.toast("A ban reason is required.", "error")
					return
				end
				local response = ctx.Net.run("players.ban", { Target = query, Duration = length.Get(), Reason = text }, { Label = "Ban", ConfirmTitle = "Ban player" })
				if response.ok then
					reason.Text = ""
					task.spawn(tab.RefreshBans)
					task.delay(0.5, ctx.refreshPlayers)
				end
			end,
			Parent = banSection,
		})

		local listSection = Widgets.section(scroll, "Active bans", 2)
		local refreshRow = Widgets.row(listSection, 1, 30)
		Widgets.button({
			Text = "↻ Refresh",
			Variant = "adminGhost",
			Size = UDim2.fromOffset(110, 28),
			LayoutOrder = 1,
			OnClick = function()
				tab.RefreshBans()
			end,
			Parent = refreshRow,
		})
		banList = UI.frame({
			Name = "Bans",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			List = { Pad = 6 },
			Parent = listSection,
		})
	end

	function tab.RefreshBans()
		if not banList then
			return
		end
		local response = ctx.Net.request("players.bans")
		local list = banList :: Frame
		Widgets.clear(list)
		if not response.ok then
			Widgets.dim({ Text = response.err or "Could not load bans.", TextColor3 = P.Danger, Size = UDim2.new(1, 0, 0, 20), Parent = list })
			return
		end
		local bans = if type(response.data) == "table" then response.data.Bans or {} else {}
		if #bans == 0 then
			Widgets.dim({ Text = "Nobody is banned.", Size = UDim2.new(1, 0, 0, 20), Parent = list })
			return
		end
		for index, ban in ipairs(bans) do
			local row = UI.new("Frame", {
				Name = "Ban",
				Size = UDim2.new(1, 0, 0, 52),
				BackgroundColor3 = P.Background,
				LayoutOrder = index,
				Corner = 10,
				Stroke = { Color = P.Danger, Transparency = 0.6 },
				Parent = list,
			})
			local length = if ban.Until == 0 then "permanent" else "until " .. os.date("!%Y-%m-%d %H:%M", ban.Until) .. " UTC"
			Widgets.label({
				Text = `{ban.Name}  ·  {length}`,
				Font = F.Bold,
				Size = UDim2.new(1, -130, 0, 20),
				Position = UDim2.fromOffset(12, 6),
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = row,
			})
			Widgets.dim({
				Text = `by {ban.ByName}: {ban.Reason}`,
				TextSize = 12,
				Size = UDim2.new(1, -130, 0, 18),
				Position = UDim2.fromOffset(12, 28),
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = row,
			})
			Widgets.button({
				Text = "Unban",
				Variant = "adminSecondary",
				Size = UDim2.fromOffset(100, 30),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				OnClick = function()
					local response2 = ctx.Net.run("players.unban", { Target = "#" .. tostring(ban.UserId) }, { Label = "Unban" })
					if response2.ok then
						tab.RefreshBans()
					end
				end,
				Parent = row,
			})
		end
	end

	-- Staff roles ------------------------------------------------------------------------------------
	local staffList: Frame? = nil
	local staffTarget: TextBox? = nil

	if canStaff then
		local staffSection = Widgets.section(
			scroll,
			"Staff roles",
			3,
			"Owners can make players Moderator or Admin in every server. Roles from AdminConfig or place ownership cannot be changed here."
		)
		Widgets.dim({
			Text = "Moderator: kick, freeze, teleport, ban (limited length).   Admin: also currencies, items, events and longer bans.",
			TextSize = 12,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 1,
			Parent = staffSection,
		})
		staffTarget = targetBox(staffSection, 2)
		local roleRow = Widgets.row(staffSection, 3, 30)
		Widgets.rowLabel(roleRow, "Role", 70, 1)
		local roleHolder = UI.frame({ Size = UDim2.new(1, -80, 0, 30), LayoutOrder = 2, Parent = roleRow })
		local roleOptions = {}
		for _, role in ipairs({ "Moderator", "Admin" }) do
			table.insert(roleOptions, { Id = role, Text = if role == "Moderator" then "🛡️ Moderator" else "⭐ Admin" })
		end
		local roleChips = Widgets.chips({ Parent = roleHolder, Options = roleOptions, Value = "Moderator", Height = 30 })

		local buttons = Widgets.row(staffSection, 4, 34)
		Widgets.button({
			Text = "Give role",
			Variant = "adminPrimary",
			Size = UDim2.fromOffset(140, 34),
			LayoutOrder = 1,
			OnClick = function()
				local query = TargetPicker.queryFromText((staffTarget :: TextBox).Text)
				if not query then
					ctx.toast("Enter a player first.", "error")
					return
				end
				local response = ctx.Net.run("staff.setRole", { Target = query, Role = roleChips.Get() }, { Label = "Staff role", ConfirmTitle = "Give staff role" })
				if response.ok then
					task.spawn(tab.RefreshStaff)
				end
			end,
			Parent = buttons,
		})
		Widgets.button({
			Text = "Remove role",
			Variant = "adminDanger",
			Size = UDim2.fromOffset(140, 34),
			LayoutOrder = 2,
			OnClick = function()
				local query = TargetPicker.queryFromText((staffTarget :: TextBox).Text)
				if not query then
					ctx.toast("Enter a player first.", "error")
					return
				end
				local response = ctx.Net.run("staff.removeRole", { Target = query }, { Label = "Staff role" })
				if response.ok then
					task.spawn(tab.RefreshStaff)
				end
			end,
			Parent = buttons,
		})

		staffList = UI.frame({
			Name = "Staff",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 5,
			List = { Pad = 6 },
			Parent = staffSection,
		})
	end

	function tab.RefreshStaff()
		if not staffList then
			return
		end
		local response = ctx.Net.request("staff.list")
		local list = staffList :: Frame
		Widgets.clear(list)
		if not response.ok then
			Widgets.dim({ Text = response.err or "Could not load staff.", TextColor3 = P.Danger, Size = UDim2.new(1, 0, 0, 20), Parent = list })
			return
		end
		local staff = if type(response.data) == "table" then response.data.Staff or {} else {}
		if #staff == 0 then
			Widgets.dim({ Text = "Nobody has a role given in the game yet.", Size = UDim2.new(1, 0, 0, 20), Parent = list })
			return
		end
		for index, entry in ipairs(staff) do
			local row = UI.new("Frame", {
				Name = "StaffEntry",
				Size = UDim2.new(1, 0, 0, 44),
				BackgroundColor3 = P.Background,
				LayoutOrder = index,
				Corner = 10,
				Stroke = { Color = if entry.Role == "Admin" then P.Accent else P.Accent2, Transparency = 0.6 },
				Parent = list,
			})
			Widgets.label({
				Text = `{if entry.Role == "Admin" then "⭐" else "🛡️"} {entry.Role} · {entry.Name}`,
				Font = F.Bold,
				Size = UDim2.new(1, -130, 0, 20),
				Position = UDim2.fromOffset(12, 4),
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = row,
			})
			Widgets.dim({
				Text = `#{entry.UserId} · given by {entry.ByName}`,
				TextSize = 12,
				Size = UDim2.new(1, -130, 0, 16),
				Position = UDim2.fromOffset(12, 24),
				Parent = row,
			})
			Widgets.button({
				Text = "Remove",
				Variant = "adminSecondary",
				Size = UDim2.fromOffset(100, 30),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				OnClick = function()
					local response2 = ctx.Net.run("staff.removeRole", { Target = "#" .. tostring(entry.UserId) }, { Label = "Staff role" })
					if response2.ok then
						tab.RefreshStaff()
					end
				end,
				Parent = row,
			})
		end
	end

	-- Opened from the Players tab with a player already chosen.
	function tab.OnShow(userId: number?, mode: string?)
		if userId then
			local box = if mode == "staff" then staffTarget else banTarget
			if box then
				box.Text = "#" .. tostring(userId)
			end
		end
		tab.RefreshBans()
		tab.RefreshStaff()
	end

	return tab
end
