--[[
	Progression tab (ModuleScript)
	Location: ServerStorage/AdminClient/AdminUI/Tabs/Progression
	Depends on: AdminUI/Widgets, AdminUI/TargetPicker, ReplicatedStorage/Shared/Config/{Upgrades,Skills}
	Server actions: progression.setUpgrade, progression.unlockSkill, progression.resetSkills (confirm),
	                progression.grantRebirth, progression.grantLevels, progression.grantSkillPoints,
	                progression.reset (confirm; scope "all" also requires typing the player's name),
	                players.inspect (to show current levels)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local Upgrades = require(Config:WaitForChild("Upgrades"))
local Skills = require(Config:WaitForChild("Skills"))

local Widgets = require(script.Parent.Parent.Widgets)
local TargetPicker = require(script.Parent.Parent.TargetPicker)

local P = Widgets.P
local F = Widgets.Theme.Fonts

local RESET_SCOPES = {
	{ Id = "upgrades", Text = "Upgrades" },
	{ Id = "skills", Text = "Skills (refund)" },
	{ Id = "ascension", Text = "Ascensions" },
	{ Id = "inventory", Text = "Inventory" },
	{ Id = "collection", Text = "Collection" },
	{ Id = "quests", Text = "Quests" },
	{ Id = "stats", Text = "Stats" },
	{ Id = "level", Text = "Level" },
	{ Id = "all", Text = "EVERYTHING", Color = P.Danger },
}

return function(ctx, container: Frame)
	local scroll = Widgets.scroll(container)
	local canGrant = ctx.has("progression.grant")
	local canReset = ctx.has("progression.reset")
	local limits = ctx.Hello.Limits or {}

	local function target(): any
		local query = ctx.Target.Query
		if query == nil then
			ctx.toast("Select a target player first.", "error")
		end
		return query
	end

	local function wholeNumber(box: TextBox, fallback: number?, min: number): number?
		if box.Text == "" and fallback then
			return fallback
		end
		local n = Widgets.parseNumber(box.Text)
		if not n or n ~= math.floor(n) or n < min then
			ctx.toast(`Enter a whole number of at least {min}.`, "error")
			return nil
		end
		return n
	end

	local targetSection = Widgets.section(scroll, "Target", 1)
	TargetPicker.new(ctx, targetSection, 1)
	local loadButton = Widgets.button({ Text = "↻ Load current values", Size = UDim2.fromOffset(190, 30), LayoutOrder = 2, Parent = targetSection })
	Widgets.gate(loadButton, ctx.has("players.inspect"), "players.inspect")
	local summary = Widgets.dim({ Text = "", LayoutOrder = 3, Parent = targetSection })

	-- Upgrades -----------------------------------------------------------------------------------
	local upgradeSection = Widgets.section(scroll, "Shop upgrade levels", 2, "Sets an exact level (0 removes the upgrade).")
	local levelBoxes: { [string]: TextBox } = {}
	for index, def in ipairs(Upgrades.List) do
		local row = Widgets.row(upgradeSection, index, 32)
		Widgets.label({ Text = `{def.Icon} {def.Name}`, Font = F.Bold, Size = UDim2.new(1, -330, 0, 30), LayoutOrder = 1, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row })
		Widgets.dim({ Text = `max {def.MaxLevel}`, Size = UDim2.fromOffset(70, 30), LayoutOrder = 2, Parent = row })
		local box = Widgets.textbox({ Placeholder = "level", Size = UDim2.fromOffset(90, 30), LayoutOrder = 3, MaxLength = 6, Parent = row })
		levelBoxes[def.Id] = box
		local set = Widgets.button({
			Text = "Set",
			Size = UDim2.fromOffset(80, 30),
			LayoutOrder = 4,
			OnClick = function()
				local t = target()
				local level = wholeNumber(box, nil, 0)
				if t ~= nil and level then
					ctx.Net.run("progression.setUpgrade", { Target = t, Upgrade = def.Id, Level = level }, { Label = def.Name })
				end
			end,
			Parent = row,
		})
		Widgets.gate(set, canGrant, "progression.grant")
	end

	-- Skills -------------------------------------------------------------------------------------
	local skillSection = Widgets.section(scroll, "Skills", 3, "Unlocks a node at max rank for testing (prerequisites are skipped).")
	local skillRow = Widgets.row(skillSection, 1, 34)
	local skillOptions = {}
	for _, node in ipairs(Skills.List) do
		local branch = Skills.Branches[node.Branch]
		table.insert(skillOptions, { Text = `{node.Icon} {node.Name}  ({node.Branch})`, Value = node.Id, Color = branch and branch.Color })
	end
	local first = Skills.List[1]
	local skillDropdown = Widgets.dropdown({ Parent = skillRow, Order = 1, Width = 260, Options = skillOptions, Value = first.Id, Text = `{first.Icon} {first.Name}` })
	local unlock = Widgets.button({
		Text = "Unlock",
		Variant = "adminPrimary",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(100, 32),
		OnClick = function()
			local t = target()
			if t ~= nil then
				ctx.Net.run("progression.unlockSkill", { Target = t, Skill = skillDropdown.Get() }, { Label = "Unlock skill" })
			end
		end,
		Parent = skillRow,
	})
	local unlockAll = Widgets.button({
		Text = "Unlock all",
		LayoutOrder = 3,
		Size = UDim2.fromOffset(110, 32),
		OnClick = function()
			local t = target()
			if t ~= nil then
				ctx.Net.run("progression.unlockSkill", { Target = t, Skill = "all" }, { Label = "Unlock all skills" })
			end
		end,
		Parent = skillRow,
	})
	local resetSkills = Widgets.button({
		Text = "Reset skills",
		Variant = "adminDanger",
		LayoutOrder = 4,
		Size = UDim2.fromOffset(120, 32),
		OnClick = function()
			local t = target()
			if t ~= nil then
				ctx.Net.run("progression.resetSkills", { Target = t }, { Label = "Reset skills" })
			end
		end,
		Parent = skillRow,
	})
	Widgets.gate(unlock, canGrant, "progression.grant")
	Widgets.gate(unlockAll, canGrant, "progression.grant")
	Widgets.gate(resetSkills, canReset, "progression.reset")

	-- Grants ---------------------------------------------------------------------------------------
	local grantSection = Widgets.section(scroll, "Grant progression", 4, `Role limits: {limits.MaxRebirths or 0} ascensions, {limits.MaxLevels or 0} levels, {limits.MaxSkillPoints or 0} skill points per action.`)
	local function grantRow(order: number, label: string, action: string, key: string, placeholder: string)
		local row = Widgets.row(grantSection, order, 34)
		Widgets.rowLabel(row, label, 140, 1)
		local box = Widgets.textbox({ Placeholder = placeholder, Size = UDim2.fromOffset(100, 32), LayoutOrder = 2, MaxLength = 8, Parent = row })
		local button = Widgets.button({
			Text = "Grant",
			Variant = "adminPrimary",
			Size = UDim2.fromOffset(100, 32),
			LayoutOrder = 3,
			OnClick = function()
				local t = target()
				local n = wholeNumber(box, if key == "Amount" then nil else 1, 1)
				if t ~= nil and n then
					ctx.Net.run(action, { Target = t, [key] = n }, { Label = label })
				end
			end,
			Parent = row,
		})
		Widgets.gate(button, canGrant, "progression.grant")
	end
	grantRow(1, "🔷 Ascensions", "progression.grantRebirth", "Count", "1")
	grantRow(2, "📈 Levels", "progression.grantLevels", "Count", "1")
	grantRow(3, "🌳 Skill points", "progression.grantSkillPoints", "Amount", "amount")
	Widgets.dim({ Text = "Granting an ascension resets that player's current run exactly like a normal ascension.", TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4, Parent = grantSection })

	-- Reset ------------------------------------------------------------------------------------------
	local resetSection = Widgets.section(scroll, "Reset progress", 5, "Destructive. The server issues a single-use confirmation; EVERYTHING also requires typing the player's name.")
	local scopeChips = Widgets.chips({ Parent = resetSection, Options = RESET_SCOPES, Value = "upgrades", Order = 1, Height = 28 })
	local resetButton = Widgets.button({
		Text = "⚠ Reset selected progress",
		Variant = "adminDanger",
		Size = UDim2.fromOffset(230, 34),
		LayoutOrder = 2,
		OnClick = function()
			local t = target()
			if t == nil then
				return
			end
			local scope = scopeChips.Get()
			local requireText = nil
			if scope == "all" then
				local label = ctx.Target.Label or ""
				local name = string.match(label, "@([%w_]+)") or (string.gsub(label, "^%s*(.-)%s*$", "%1"))
				if name == "" then
					name = tostring(t)
				end
				requireText = name
			end
			ctx.Net.run("progression.reset", { Target = t, Scope = scope }, { Label = "Reset progress", RequireText = requireText })
		end,
		Parent = resetSection,
	})
	Widgets.gate(resetButton, canReset, "progression.reset")

	-- Load current values ------------------------------------------------------------------------------
	local function load()
		local t = ctx.Target.Query
		if t == nil or not ctx.has("players.inspect") then
			return
		end
		local response = ctx.Net.request("players.inspect", { Target = t })
		if ctx.Target.Query ~= t then
			return
		end
		if not response.ok or type(response.data) ~= "table" then
			summary.Text = response.err or "Could not load."
			summary.TextColor3 = P.Warning
			return
		end
		local data = response.data
		for id, box in pairs(levelBoxes) do
			box.Text = tostring((data.Upgrades or {})[id] or 0)
		end
		local ranks = 0
		for _, rank in pairs(data.Skills or {}) do
			ranks += rank
		end
		summary.Text = `Level {data.Level} · {data.SkillPoints or 0} skill points · {ranks} skill ranks · {data.Rebirths or 0} ascensions`
		summary.TextColor3 = P.TextDim
	end
	loadButton.Activated:Connect(function()
		if not loadButton:GetAttribute("Disabled") then
			load()
		end
	end)

	local version = 0
	ctx.TargetChanged:Connect(function()
		version += 1
		local mine = version
		if container.Visible and type(ctx.Target.Query) == "number" then
			task.delay(0.4, function()
				if mine == version then
					load()
				end
			end)
		end
	end)

	local tab = {}
	function tab.OnShow()
		if type(ctx.Target.Query) == "number" then
			load()
		end
	end
	return tab
end
