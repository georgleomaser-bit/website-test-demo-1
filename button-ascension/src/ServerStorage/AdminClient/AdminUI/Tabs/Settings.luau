--[[
	Settings tab (ModuleScript)
	Location: ServerStorage/AdminClient/AdminUI/Tabs/Settings
	Depends on: AdminUI/Widgets, ReplicatedStorage/Shared/Format
	Server actions: none (uses the "hello" response received at startup)

	Shows the staff member's role, rank, permissions and limits, plus local
	panel preferences. Preferences live in memory for this session only.
	Roles and permissions are configured on the server in
	ServerScriptService/Admin/AdminConfig and can never be changed from here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))

local Widgets = require(script.Parent.Parent.Widgets)

local UI = Widgets.UI
local P = Widgets.P
local F = Widgets.Theme.Fonts

local LIMIT_LABELS = {
	{ "MaxCurrency", "Currency per action" },
	{ "MaxItems", "Items per action" },
	{ "MaxChests", "Crates per action" },
	{ "MaxRebirths", "Ascensions per action" },
	{ "MaxLevels", "Levels per action" },
	{ "MaxSkillPoints", "Skill points per action" },
}

return function(ctx, container: Frame)
	local scroll = Widgets.scroll(container)
	local hello = ctx.Hello
	local roleColor = if typeof(hello.RoleColor) == "Color3" then hello.RoleColor else P.Accent

	local roleSection = Widgets.section(scroll, "Your role", 1)
	Widgets.label({
		Text = `{hello.Role} · rank {hello.Rank}`,
		Font = F.Heading,
		TextSize = 22,
		TextColor3 = roleColor,
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = 1,
		Parent = roleSection,
	})
	Widgets.dim({
		Text = "Punitive actions (kick, freeze, removals, resets) cannot target staff of equal or higher rank.",
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = roleSection,
	})

	local permSection = Widgets.section(scroll, "Permissions", 2)
	local permFrame = UI.frame({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = permSection })
	local permLayout = UI.list(permFrame, { Dir = "X", Pad = 6 })
	permLayout.Wraps = true
	local permissions = table.clone(hello.Permissions or {})
	table.sort(permissions)
	for index, permission in ipairs(permissions) do
		Widgets.tag(permFrame, if permission == "*" then "* (all permissions)" else permission, P.Accent, index)
	end

	local limitSection = Widgets.section(scroll, "Limits", 3, "Enforced by the server for every request, including commands.")
	local limits = hello.Limits or {}
	for index, def in ipairs(LIMIT_LABELS) do
		local row = UI.frame({ Size = UDim2.new(1, 0, 0, 18), LayoutOrder = index, Parent = limitSection })
		Widgets.dim({ Text = def[2], Size = UDim2.new(0.5, 0, 1, 0), Parent = row })
		Widgets.label({ Text = Format.short(limits[def[1]] or 0), Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.fromScale(0.5, 0), Parent = row })
	end

	local serverSection = Widgets.section(scroll, "Session", 4)
	Widgets.dim({
		Text = table.concat({
			`Panel key: {hello.PanelKey or "F2"}  ·  chat: /admin <command>  ·  gamepad: select the 🛡️ Admin button, B closes`,
			`Server: {Widgets.shortId(hello.JobId)}{if hello.IsStudio then "  ·  Roblox Studio test session" else ""}`,
			`Game-wide announcements: {if hello.CrossServer then "enabled in AdminConfig" else "disabled"}`,
			`Commands available to you: {#(hello.Commands or {})}`,
		}, "\n"),
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = serverSection,
	})

	local prefSection = Widgets.section(scroll, "Panel preferences", 5, "Stored for this session only.")
	local function prefRow(order: number, label: string, key: string)
		local row = Widgets.row(prefSection, order, 30)
		Widgets.label({ Text = label, Size = UDim2.new(1, -70, 0, 30), LayoutOrder = 1, Parent = row })
		UI.toggle({
			Value = ctx.Prefs[key],
			LayoutOrder = 2,
			OnChange = function(value)
				ctx.Prefs[key] = value
				ctx.PrefsChanged:Fire(key)
			end,
			Parent = row,
		})
	end
	prefRow(1, "Toast sounds", "ToastSounds")
	prefRow(2, "Compact layout (icon-only sidebar, denser rows)", "Compact")
	prefRow(3, "Auto-refresh dashboard, players and events", "AutoRefresh")

	local noteSection = Widgets.section(scroll, "Where roles come from", 6)
	Widgets.dim({
		Text = "Staff roles are assigned on the server in ServerScriptService/Admin/AdminConfig using Roblox UserIds. "
			.. "This panel only shows what the server allows; every request is re-checked server-side, so hiding or "
			.. "changing anything here cannot grant extra access. Ask the game owner to change your role.",
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = noteSection,
	})

	return {}
end
