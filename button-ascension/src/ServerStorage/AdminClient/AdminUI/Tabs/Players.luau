--[[
	Players tab (ModuleScript)
	Location: ServerStorage/AdminClient/AdminUI/Tabs/Players
	Depends on: AdminUI/Widgets, ReplicatedStorage/Shared/Format, ReplicatedStorage/Shared/Config/{Upgrades,Skills,Chests}
	Server actions: players.list, players.inspect, players.teleportTo, players.bring,
	                players.freeze, players.unfreeze, players.respawn, players.kick
	                (Ban and staff-role buttons open the Moderation tab)

	Searchable list of online players; selecting one shows their progression,
	inventory summary, statistics and moderation actions. Offline players can
	be looked up by UserId when the role has offline.read.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Format = require(Shared:WaitForChild("Format"))
local Upgrades = require(Config:WaitForChild("Upgrades"))
local Chests = require(Config:WaitForChild("Chests"))

local Widgets = require(script.Parent.Parent.Widgets)

local UI = Widgets.UI
local P = Widgets.P
local F = Widgets.Theme.Fonts

local STAT_ROWS = {
	{ "TotalClicks", "Presses" },
	{ "AutoClicks", "Auto presses" },
	{ "LifetimeSparks", "Lifetime Sparks" },
	{ "SparksThisRun", "Sparks this run" },
	{ "ChestsOpened", "Crates opened" },
	{ "HighestCombo", "Highest combo" },
	{ "TotalCrits", "Critical presses" },
	{ "GoldenClicks", "Golden presses" },
	{ "UpgradesPurchased", "Upgrade levels bought" },
	{ "ItemsSold", "Items sold" },
	{ "QuestsCompleted", "Quests completed" },
	{ "OrbsCollected", "Orbs collected" },
	{ "PlayTime", "Play time" },
}

return function(ctx, container: Frame)
	local left = UI.frame({ Name = "Left", Size = UDim2.new(0.38, -6, 1, 0), Parent = container })
	local right = UI.new("Frame", {
		Name = "Right",
		Position = UDim2.new(0.38, 6, 0, 0),
		Size = UDim2.new(0.62, -6, 1, 0),
		BackgroundColor3 = P.PanelLight,
		Corner = 12,
		Stroke = { Color = P.Stroke, Transparency = 0.4 },
		Parent = container,
	})

	local search = Widgets.textbox({ Placeholder = "🔍 Search name, display name or UserId", Size = UDim2.new(1, 0, 0, 32), Parent = left })
	local listHeight = if ctx.has("offline.read") then -86 else -40
	local list = UI.scroll({
		Name = "PlayerList",
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 1, listHeight),
		ScrollBarImageColor3 = P.Stroke,
		List = { Pad = 4 },
		Padding = { 0, 6, 0, 0 },
		Parent = left,
	})

	if ctx.has("offline.read") then
		local offline = UI.frame({ Name = "Offline", Position = UDim2.new(0, 0, 1, -38), Size = UDim2.new(1, 0, 0, 34), List = { Dir = "X", Pad = 6, VA = "Center" }, Parent = left })
		local idBox = Widgets.textbox({ Placeholder = "Offline UserId", Size = UDim2.new(1, -116, 0, 32), LayoutOrder = 1, MaxLength = 20, Parent = offline })
		Widgets.button({
			Text = "Look up",
			Size = UDim2.fromOffset(110, 32),
			LayoutOrder = 2,
			Variant = "adminMagenta",
			OnClick = function()
				local digits = string.match(idBox.Text, "^%s*#?(%d+)%s*$")
				if not digits then
					ctx.toast("Enter a numeric UserId.", "error")
					return
				end
				ctx.showDetails("#" .. digits)
			end,
			Parent = offline,
		})
	end

	local details = UI.scroll({
		Name = "Details",
		Size = UDim2.fromScale(1, 1),
		ScrollBarImageColor3 = P.Stroke,
		List = { Pad = 10 },
		Padding = 14,
		Parent = right,
	})

	local rows: { [number]: TextButton } = {}
	local selected: any = nil
	local lastInspect: any = nil

	local function matches(p, query: string): boolean
		if query == "" then
			return true
		end
		local q = string.lower(query)
		return string.find(string.lower(p.Name), q, 1, true) ~= nil
			or string.find(string.lower(p.DisplayName), q, 1, true) ~= nil
			or string.find(tostring(p.UserId), q, 1, true) ~= nil
	end

	local function renderList()
		local seen = {}
		for index, p in ipairs(ctx.Players) do
			seen[p.UserId] = true
			local row = rows[p.UserId]
			if not row then
				row = UI.new("TextButton", {
					Name = "Player",
					Size = UDim2.new(1, 0, 0, 52),
					BackgroundColor3 = P.PanelLight,
					AutoButtonColor = false,
					Text = "",
					Corner = 10,
					Stroke = { Color = P.Stroke, Transparency = 0.5 },
					Parent = list,
				})
				Widgets.label({ Name = "Display", Font = F.Bold, Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(10, 6), TextTruncate = Enum.TextTruncate.AtEnd, Parent = row })
				Widgets.dim({ Name = "Sub", Size = UDim2.new(1, -16, 0, 16), Position = UDim2.fromOffset(10, 28), TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row })
				row.Activated:Connect(function()
					ctx.showDetails(p.UserId)
				end)
				row.MouseEnter:Connect(function()
					row.BackgroundColor3 = P.PanelLighter
				end)
				row.MouseLeave:Connect(function()
					row.BackgroundColor3 = P.PanelLight
				end)
				rows[p.UserId] = row
			end
			row.LayoutOrder = index
			local display = row:FindFirstChild("Display") :: TextLabel
			local sub = row:FindFirstChild("Sub") :: TextLabel
			local tags = {}
			if p.StaffRole then
				table.insert(tags, "★ " .. p.StaffRole)
			end
			if p.Frozen then
				table.insert(tags, "❄ Frozen")
			end
			if not p.Loaded then
				table.insert(tags, "loading…")
			end
			display.Text = p.DisplayName .. (if #tags > 0 then "   " .. table.concat(tags, "  ") else "")
			display.TextColor3 = if p.StaffRole then P.Accent2 else P.Text
			sub.Text = `@{p.Name} · #{p.UserId} · Lv {p.Level} · {Format.short(p.Sparks)} ⚡ · {p.Rebirths} asc.`
			row.Visible = matches(p, search.Text)
			local stroke = row:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if selected == p.UserId then P.Accent else P.Stroke
				stroke.Transparency = if selected == p.UserId then 0 else 0.5
			end
		end
		for userId, row in pairs(rows) do
			if not seen[userId] then
				row:Destroy()
				rows[userId] = nil
			end
		end
	end

	search:GetPropertyChangedSignal("Text"):Connect(renderList)
	ctx.PlayersUpdated:Connect(renderList)

	local function kv(parent: Instance, key: string, value: string, order: number)
		local row = UI.frame({ Size = UDim2.new(1, 0, 0, 18), LayoutOrder = order, Parent = parent })
		Widgets.dim({ Text = key, Size = UDim2.new(0.45, 0, 1, 0), TextSize = 13, Parent = row })
		Widgets.label({ Text = value, Size = UDim2.new(0.55, 0, 1, 0), Position = UDim2.fromScale(0.45, 0), TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row })
	end

	local function actionButton(parent: Instance, text: string, variant: string, permission: string, order: number, fn: () -> ())
		local button = Widgets.button({ Text = text, Variant = variant, Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, Padding = { X = 12 }, LayoutOrder = order, OnClick = fn, Parent = parent })
		Widgets.gate(button, ctx.has(permission), permission)
		return button
	end

	local function render(data)
		Widgets.clear(details)
		if not data then
			Widgets.dim({ Text = "Select a player on the left to inspect them.", Size = UDim2.new(1, 0, 0, 24), Parent = details })
			return
		end
		local online = data.Online ~= false
		local header = UI.frame({ Size = UDim2.new(1, 0, 0, 50), LayoutOrder = 1, Parent = details })
		Widgets.label({
			Text = if online then data.DisplayName else "Offline player",
			Font = F.Heading,
			TextSize = 22,
			Size = UDim2.new(1, 0, 0, 26),
			Parent = header,
		})
		Widgets.dim({
			Text = if online then `@{data.Name} · UserId {data.UserId} · in session {data.SessionMinutes} min` else `UserId {data.UserId} · last seen {if data.LastSeen and data.LastSeen > 0 then Format.time(workspace:GetServerTimeNow() - data.LastSeen) .. " ago" else "unknown"}`,
			Size = UDim2.new(1, 0, 0, 18),
			Position = UDim2.fromOffset(0, 28),
			Parent = header,
		})
		local tagRow = UI.frame({ Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 2, List = { Dir = "X", Pad = 6, VA = "Center" }, Parent = details })
		if data.StaffRole then
			Widgets.tag(tagRow, "STAFF · " .. string.upper(data.StaffRole), P.Accent2, 1)
		end
		if data.Frozen then
			Widgets.tag(tagRow, "FROZEN", Color3.fromRGB(120, 200, 255), 2)
		end
		if data.Temporary then
			Widgets.tag(tagRow, "NOT SAVING (temporary data)", P.Warning, 3)
		end
		if not online then
			Widgets.tag(tagRow, "OFFLINE · read-only view", P.TextDim, 4)
		end
		if type(data.Passes) == "table" and #data.Passes > 0 then
			Widgets.tag(tagRow, "PASSES · " .. string.upper(table.concat(data.Passes, ", ")), P.Accent, 5)
		end

		if online then
			local actions = UI.frame({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, Parent = details })
			local layout = UI.list(actions, { Dir = "X", Pad = 6 })
			layout.Wraps = true
			local userId = data.UserId
			local label = `{data.DisplayName} (@{data.Name})`
			actionButton(actions, "📍 Teleport to", "adminSecondary", "players.teleport", 1, function()
				ctx.Net.run("players.teleportTo", { Target = userId }, { Label = "Teleport" })
			end)
			actionButton(actions, "🧲 Bring", "adminSecondary", "players.teleport", 2, function()
				ctx.Net.run("players.bring", { Target = userId }, { Label = "Bring" })
			end)
			actionButton(actions, if data.Frozen then "🔥 Unfreeze" else "❄ Freeze", "adminSecondary", "players.freeze", 3, function()
				ctx.Net.run(if data.Frozen then "players.unfreeze" else "players.freeze", { Target = userId }, { Label = "Freeze" })
				ctx.showDetails(userId)
			end)
			actionButton(actions, "♻ Respawn", "adminSecondary", "players.respawn", 4, function()
				ctx.Net.run("players.respawn", { Target = userId }, { Label = "Respawn" })
			end)
			actionButton(actions, "🎒 Inspect inventory", "adminMagenta", "players.inspect", 5, function()
				ctx.setTarget(userId, label)
				ctx.switchTab("Items", "inspect")
			end)
			actionButton(actions, "🎯 Select as target", "adminGhost", "players.view", 6, function()
				ctx.setTarget(userId, label)
				ctx.toast("Target set to " .. label, "ok")
			end)
			actionButton(actions, "⛔ Kick", "adminDanger", "players.kick", 7, function()
				local reason = UI.prompt({
					Title = "Kick " .. data.DisplayName,
					Message = "The reason is shown to the player (filtered by Roblox) and stored in the audit log.",
					Placeholder = "Reason (required)",
					MaxLength = 200,
					ConfirmText = "Kick",
					Danger = true,
					Palette = P,
				})
				if reason and string.match(reason, "%S") then
					ctx.Net.run("players.kick", { Target = userId, Reason = reason }, { Label = "Kick" })
					task.wait(0.5)
					ctx.refreshPlayers()
				elseif reason then
					ctx.toast("A kick reason is required.", "error")
				end
			end)
		end
		if data.UserId then
			local modActions = UI.frame({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, Parent = details })
			local modLayout = UI.list(modActions, { Dir = "X", Pad = 6 })
			modLayout.Wraps = true
			local targetId = data.UserId
			actionButton(modActions, "🚫 Ban…", "adminDanger", "players.ban", 1, function()
				ctx.switchTab("Moderation", targetId, "ban")
			end)
			if ctx.has("staff.manage") then
				actionButton(modActions, "🛡️ Staff role…", "adminMagenta", "staff.manage", 2, function()
					ctx.switchTab("Moderation", targetId, "staff")
				end)
			end
		end

		local progress = Widgets.section(details, "Currencies & progression", 4)
		local c = data.Currencies or {}
		kv(progress, "⚡ Sparks", Format.short(c.Sparks) .. "  (" .. Format.commas(c.Sparks) .. ")", 1)
		kv(progress, "💎 Gems", Format.commas(c.Gems), 2)
		kv(progress, "🔷 Prisms", Format.commas(c.Prisms), 3)
		kv(progress, "Level", `{data.Level}` .. (if data.XP then `  ({Format.short(data.XP)} XP)` else ""), 4)
		kv(progress, "Skill points", tostring(data.SkillPoints or 0), 5)
		kv(progress, "Ascensions", `{data.Rebirths or 0}` .. (if data.Stage then ` · {data.Stage}` else ""), 6)
		kv(progress, "Items discovered", tostring(data.Discovered or 0), 7)
		if data.Achievements then
			kv(progress, "Achievements", tostring(data.Achievements), 8)
		end
		if data.Derived then
			local derived = data.Derived
			kv(progress, "Per press", Format.short(derived.ClickValue), 9)
			kv(progress, "Passive", Format.short(derived.PassivePerSec) .. "/s", 10)
			kv(progress, "Crit chance", Format.pct(derived.CritChance, 1), 11)
			kv(progress, "Luck", "+" .. Format.pct(derived.Luck), 12)
			kv(progress, "Auto presses", string.format("%.1f/s", derived.AutoRate or 0), 13)
		end

		local upgrades = Widgets.section(details, "Upgrades", 5)
		local upgradeParts = {}
		for _, def in ipairs(Upgrades.List) do
			local level = (data.Upgrades or {})[def.Id]
			if level then
				table.insert(upgradeParts, `{def.Icon} {def.Name} {level}`)
			end
		end
		Widgets.dim({ Text = if #upgradeParts > 0 then table.concat(upgradeParts, "   ") else "No upgrades this run.", TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = upgrades })
		local skillRanks, skillNodes = 0, 0
		for _, rank in pairs(data.Skills or {}) do
			skillRanks += rank
			skillNodes += 1
		end
		Widgets.dim({ Text = `Skills: {skillNodes} nodes, {skillRanks} ranks`, LayoutOrder = 2, Parent = upgrades })

		local inventory = Widgets.section(details, "Inventory", 6)
		local items = data.Inventory or {}
		local copies = 0
		for _, entry in ipairs(items) do
			copies += entry.Count
		end
		Widgets.dim({ Text = `{#items} unique items · {Format.commas(copies)} copies · equipped: {#(data.Equipped or {})}`, LayoutOrder = 1, Parent = inventory })
		for i = 1, math.min(10, #items) do
			local entry = items[i]
			Widgets.label({
				Text = `{if entry.Equipped then "✔ " else ""}{entry.Name} ×{entry.Count}`,
				TextColor3 = Widgets.rarityColor(entry.Rarity),
				TextSize = 13,
				Size = UDim2.new(1, 0, 0, 16),
				LayoutOrder = 1 + i,
				Parent = inventory,
			})
		end
		if #items > 10 then
			Widgets.dim({ Text = `…and {#items - 10} more (see Items tab).`, LayoutOrder = 20, Parent = inventory })
		end
		local crateParts = {}
		for _, chestId in ipairs(Chests.Order) do
			local n = (data.Chests or {})[chestId]
			if n then
				table.insert(crateParts, `{Chests.ById[chestId].Icon} {Chests.ById[chestId].Name} ×{n}`)
			end
		end
		Widgets.dim({ Text = "Crates: " .. (if #crateParts > 0 then table.concat(crateParts, "   ") else "none"), TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 30, Parent = inventory })

		local stats = Widgets.section(details, "Statistics", 7)
		for i, rowDef in ipairs(STAT_ROWS) do
			local value = (data.Stats or {})[rowDef[1]] or 0
			kv(stats, rowDef[2], if rowDef[1] == "PlayTime" then Format.time(value) else Format.short(value), i)
		end

		if data.Security then
			local security = Widgets.section(details, "Security flags", 8)
			local parts = {}
			for reason, count in pairs(data.Security) do
				table.insert(parts, `{reason} ×{count}`)
			end
			table.sort(parts)
			Widgets.dim({ Text = if #parts > 0 then table.concat(parts, "   ") else "None.", TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = security })
		end
	end

	function ctx.showDetails(target: any)
		selected = target
		renderList()
		Widgets.clear(details)
		Widgets.dim({ Text = "Loading…", Size = UDim2.new(1, 0, 0, 24), Parent = details })
		local response = ctx.Net.request("players.inspect", { Target = target })
		if selected ~= target then
			return
		end
		if response.ok and type(response.data) == "table" then
			lastInspect = response.data
			render(response.data)
			if response.message and type(target) == "string" then
				ctx.log("Inspect: " .. response.message, "ok")
			end
		else
			lastInspect = nil
			Widgets.clear(details)
			Widgets.label({ Text = response.err or "Could not load player.", TextColor3 = P.Danger, TextWrapped = true, Size = UDim2.new(1, 0, 0, 40), Parent = details })
		end
	end

	render(nil)

	local tab = { AutoRefresh = 8 }
	function tab.Refresh()
		ctx.refreshPlayers()
	end
	function tab.OnShow()
		ctx.refreshPlayers()
		if not ctx.has("players.inspect") then
			Widgets.clear(details)
			Widgets.dim({ Text = "Your role can list players but not inspect them.", Size = UDim2.new(1, 0, 0, 24), Parent = details })
		elseif lastInspect and selected then
			render(lastInspect)
		end
	end
	return tab
end
