--[[
	Skills (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Screens/Skills
	Depends on: ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format,Formulas,Config/*},
	            Client/{State,ClientNet}

	Visual skill tree on a pannable canvas. Nodes are connected to their
	prerequisites and show four states:
	  locked     (dim)            prerequisites not met
	  available  (pulsing ring)   prerequisites met, can be bought
	  unlocked   (filled colour)  at least one rank
	  maxed      (gold ring)      all ranks bought
	Selecting a node shows details and the unlock button. The server checks
	prerequisites and costs again before anything is unlocked.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UIFolder = ReplicatedStorage:WaitForChild("UI")
local UI = require(UIFolder.UIKit)
local Theme = require(UIFolder.Theme)
local Effects = require(UIFolder.Effects)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Config = Shared.Config
local Skills = require(Config.Skills)
local GameConfig = require(Config.GameConfig)

local Client = script.Parent.Parent
local State = require(Client.State)
local ClientNet = require(Client.ClientNet)

local C = Theme.Colors
local F = Theme.Fonts

local SkillsScreen = {}

local CELL = 118
local NODE = 74
local MARGIN = 70

local STAT_LABELS = {
	clickPct = "Click Power",
	sparksPct = "Sparks",
	luck = "Luck",
	critChance = "Crit Chance",
	critPower = "Crit Multiplier",
	chestBonus = "Bonus item chance",
	goldenPct = "Golden chance",
	passivePct = "Passive income",
	gemsPct = "Gems",
	xpPct = "XP",
	prismPct = "Prisms",
	comboCap = "Combo cap",
	comboWindow = "Combo window",
	streakPct = "Streak bursts",
	equipSlots = "Equip slots",
	offlineHours = "Offline hours",
	offlineRate = "Offline rate",
	autoRate = "Auto presses/s",
	chestDiscount = "Crate discount",
	pityReduction = "Pity speed",
	orbRate = "Orb frequency",
	orbPct = "Orb rewards",
}

local function effectText(node, rank: number): string
	local parts = {}
	for _, e in ipairs(node.Effects) do
		local label = STAT_LABELS[e.Stat] or e.Stat
		if e.Mult then
			table.insert(parts, `{label} {Format.mult(e.Mult ^ math.max(rank, 1))}`)
		elseif e.Stat == "comboCap" or e.Stat == "equipSlots" or e.Stat == "offlineHours" or e.Stat == "autoRate" then
			table.insert(parts, `+{(e.Add or 0) * math.max(rank, 1)} {label}`)
		elseif e.Stat == "comboWindow" then
			table.insert(parts, `+{Format.short((e.Add or 0) * math.max(rank, 1), true)}s {label}`)
		elseif e.Stat == "critPower" then
			table.insert(parts, `+{(e.Add or 0) * math.max(rank, 1)}× {label}`)
		else
			table.insert(parts, `+{Format.pct((e.Add or 0) * math.max(rank, 1))} {label}`)
		end
	end
	return table.concat(parts, ", ")
end

function SkillsScreen.new(ctx)
	local window = UI.window({
		Name = "Skills",
		Title = "Skill Tree",
		Subtitle = "Spend Skill Points from levelling up. Skills are permanent.",
		Icon = "🌳",
		Parent = ctx.Layers.Windows,
	})
	local screen: { [string]: any } = { Window = window }
	local body = window.Body
	local selectedId = "core"

	-- Canvas -----------------------------------------------------------------------------------
	local minX, maxX, minY, maxY = 0, 0, 0, 0
	for _, node in ipairs(Skills.List) do
		minX, maxX = math.min(minX, node.X), math.max(maxX, node.X)
		minY, maxY = math.min(minY, node.Y), math.max(maxY, node.Y)
	end
	local canvasW = (maxX - minX) * CELL + MARGIN * 2
	local canvasH = (maxY - minY) * CELL + MARGIN * 2

	local view = UI.new("ScrollingFrame", {
		Name = "Tree",
		Size = UDim2.new(1, -320, 1, 0),
		BackgroundColor3 = C.BackgroundAlt,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(canvasW, canvasH),
		ScrollingDirection = Enum.ScrollingDirection.XY,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = C.Stroke,
		Corner = Theme.Radius.Medium,
		Stroke = { Color = C.StrokeSoft },
		Parent = body,
	})
	local function nodePosition(node): Vector2
		return Vector2.new((node.X - minX) * CELL + MARGIN, (node.Y - minY) * CELL + MARGIN)
	end

	local lines = {}
	local function connect(fromId: string, toId: string, optional: boolean)
		local a = nodePosition(Skills.ById[fromId])
		local b = nodePosition(Skills.ById[toId])
		local delta = b - a
		local line = UI.new("Frame", {
			Name = fromId .. "_" .. toId,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2),
			Size = UDim2.fromOffset(delta.Magnitude, if optional then 3 else 5),
			Rotation = math.deg(math.atan2(delta.Y, delta.X)),
			BackgroundColor3 = C.StrokeSoft,
			BackgroundTransparency = if optional then 0.35 else 0,
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = view,
		})
		table.insert(lines, { Line = line, From = fromId, To = toId })
	end
	for _, node in ipairs(Skills.List) do
		for _, req in ipairs(node.Requires) do
			connect(req, node.Id, false)
		end
		for _, req in ipairs(node.RequiresAny) do
			connect(req, node.Id, true)
		end
	end

	local nodes = {}
	for _, node in ipairs(Skills.List) do
		local pos = nodePosition(node)
		local branch = Skills.Branches[node.Branch]
		local button = UI.new("TextButton", {
			Name = node.Id,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(pos.X, pos.Y),
			Size = UDim2.fromOffset(NODE, NODE),
			BackgroundColor3 = C.Panel,
			AutoButtonColor = false,
			Text = node.Icon,
			TextSize = 30,
			TextColor3 = C.White,
			ZIndex = 3,
			Selectable = true,
			Corner = Theme.Radius.Pill,
			Parent = view,
		})
		local stroke = UI.stroke(button, { Color = branch.Color, Thickness = 3 })
		local scale = Instance.new("UIScale")
		scale.Parent = button
		local rank = UI.label({
			Name = "Rank",
			Text = "",
			Font = F.Heading,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Center,
			BackgroundColor3 = C.Background,
			BackgroundTransparency = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.fromOffset(40, 18),
			ZIndex = 4,
			Corner = Theme.Radius.Pill,
			Stroke = { Color = branch.Color, Thickness = 1 },
			Parent = button,
		})
		local name = UI.label({
			Name = "NodeName",
			Text = node.Name,
			Font = F.Bold,
			TextSize = 12,
			TextColor3 = C.TextDim,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(pos.X, pos.Y + NODE / 2 + 12),
			Size = UDim2.fromOffset(CELL - 6, 16),
			ZIndex = 3,
			Parent = view,
		})
		button.Activated:Connect(function()
			selectedId = node.Id
			screen.Refresh()
		end)
		button.SelectionGained:Connect(function()
			selectedId = node.Id
			screen.Refresh()
		end)
		UI.attachTooltip(button, function()
			local owned = (State.get("Skills") or {})[node.Id] or 0
			return `<b>{node.Icon} {node.Name}</b>  {owned}/{node.MaxRank}\n{node.Description}`
		end)
		nodes[node.Id] = { Node = node, Button = button, Stroke = stroke, Rank = rank, Name = name, Scale = scale, Branch = branch }
	end

	-- Detail panel -------------------------------------------------------------------------------
	local detail = UI.panel({
		Name = "Detail",
		Size = UDim2.new(0, 310, 1, 0),
		Position = UDim2.new(1, -310, 0, 0),
		BackgroundColor3 = C.PanelLight,
		Padding = 16,
		Parent = body,
	})
	local spLabel = UI.label({ Text = "", Font = F.Heading, TextSize = 18, TextColor3 = C.Success, Size = UDim2.new(1, 0, 0, 24), Parent = detail })
	local dIcon = UI.label({ Text = "", TextSize = 44, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 34), Parent = detail })
	local dName = UI.label({ Text = "", Font = F.Heading, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 92), Parent = detail })
	local dBranch = UI.label({ Text = "", Font = F.Bold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 116), Parent = detail })
	local dDesc = UI.label({ Text = "", TextSize = 14, TextColor3 = C.TextDim, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 140), Parent = detail })
	local dEffect = UI.label({ Text = "", Font = F.Bold, TextSize = 14, TextColor3 = C.Accent2, TextWrapped = true, RichText = true, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 184), Parent = detail })
	local dReq = UI.label({ Text = "", TextSize = 13, TextColor3 = C.TextMuted, TextWrapped = true, RichText = true, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 228), Parent = detail })
	local unlock = UI.button({
		Text = "Unlock",
		Variant = "success",
		Size = UDim2.new(1, 0, 0, 46),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -50),
		Sound = "Unlock",
		OnClick = function()
			local id = selectedId
			local result = ClientNet.once("skill", "UnlockSkill", { Id = id })
			if not result then
				return
			end
			if result.ok then
				local entry = nodes[id]
				entry.Scale.Scale = 1.35
				UI.tween(entry.Scale, { Scale = 1 }, Theme.Motion.Pop)
				local fx = ctx.Layers.Fx
				local center = entry.Button.AbsolutePosition + entry.Button.AbsoluteSize / 2 - fx.AbsolutePosition
				Effects.burst(fx, center, entry.Branch.Color, 18, 140)
				Effects.ring(fx, center, entry.Branch.Color, 200)
			else
				ctx.Notifications.error(result.err)
			end
		end,
		Parent = detail,
	})
	UI.button({
		Text = `Reset skills (💎 {GameConfig.Skills.RespecGemCost})`,
		Variant = "ghost",
		Size = UDim2.new(1, 0, 0, 40),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		TextSize = 14,
		OnClick = function()
			local ok = UI.confirm({
				Title = "Reset the skill tree?",
				Message = `All spent Skill Points are refunded. This costs 💎 {GameConfig.Skills.RespecGemCost} Gems.`,
				ConfirmText = "Reset",
				Danger = true,
			})
			if ok then
				local result = ClientNet.once("respec", "ResetSkills")
				if result then
					ctx.Notifications.result(result, "Skill tree reset.")
				end
			end
		end,
		Parent = detail,
	})

	-- Rendering ----------------------------------------------------------------------------------
	local pulse = 0
	RunService.RenderStepped:Connect(function(dt)
		if not window.IsOpen() or Theme.ReducedMotion then
			return
		end
		pulse += dt
		local t = (math.sin(pulse * 4) + 1) / 2
		for _, entry in pairs(nodes) do
			if entry.Available then
				entry.Stroke.Transparency = t * 0.6
			end
		end
	end)

	function screen.Refresh()
		if not window.IsOpen() then
			return
		end
		local owned = State.get("Skills") or {}
		local sp = State.progress().SkillPoints
		spLabel.Text = `🌳 {sp} Skill Point{if sp == 1 then "" else "s"}  ·  {Formulas.skillPointsSpent(State.view())} spent`
		for id, entry in pairs(nodes) do
			local node = entry.Node
			local rank = owned[id] or 0
			local met = Skills.prerequisitesMet(node, owned)
			local maxed = rank >= node.MaxRank
			local affordable = Skills.costFor(node, rank) <= sp
			entry.Available = met and not maxed and affordable
			entry.Rank.Text = `{rank}/{node.MaxRank}`
			if maxed then
				entry.Button.BackgroundColor3 = Theme.darken(entry.Branch.Color, 0.35)
				entry.Stroke.Color = C.Gold
				entry.Stroke.Transparency = 0
				entry.Button.TextTransparency = 0
			elseif rank > 0 then
				entry.Button.BackgroundColor3 = Theme.darken(entry.Branch.Color, 0.5)
				entry.Stroke.Color = entry.Branch.Color
				entry.Stroke.Transparency = 0
				entry.Button.TextTransparency = 0
			elseif met then
				entry.Button.BackgroundColor3 = C.PanelLight
				entry.Stroke.Color = entry.Branch.Color
				entry.Stroke.Transparency = if entry.Available then entry.Stroke.Transparency else 0.4
				entry.Button.TextTransparency = 0.1
			else
				entry.Button.BackgroundColor3 = C.Panel
				entry.Stroke.Color = C.StrokeSoft
				entry.Stroke.Transparency = 0
				entry.Button.TextTransparency = 0.6
			end
			entry.Name.TextColor3 = if rank > 0 then entry.Branch.Color else C.TextMuted
			entry.Button.Size = if id == selectedId then UDim2.fromOffset(NODE + 10, NODE + 10) else UDim2.fromOffset(NODE, NODE)
		end
		for _, line in ipairs(lines) do
			local active = (owned[line.From] or 0) > 0 and (owned[line.To] or 0) > 0
			local reachable = (owned[line.From] or 0) > 0
			line.Line.BackgroundColor3 = if active
				then Skills.Branches[Skills.ById[line.To].Branch].Color
				elseif reachable then C.Stroke
				else C.StrokeSoft
		end

		local node = Skills.ById[selectedId]
		local branch = Skills.Branches[node.Branch]
		local rank = owned[node.Id] or 0
		dIcon.Text = node.Icon
		dName.Text = node.Name
		dBranch.Text = `{branch.Name} · Rank {rank}/{node.MaxRank}`
		dBranch.TextColor3 = branch.Color
		dDesc.Text = node.Description
		if rank >= node.MaxRank then
			dEffect.Text = "Now: " .. effectText(node, rank)
		elseif rank > 0 then
			dEffect.Text = `Now: {effectText(node, rank)}\n<font color="#9A96B8">Next:</font> {effectText(node, rank + 1)}`
		else
			dEffect.Text = "Unlock: " .. effectText(node, 1)
		end
		local reqParts = {}
		for _, req in ipairs(node.Requires) do
			local done = (owned[req] or 0) > 0
			table.insert(reqParts, (if done then "✓ " else "✗ ") .. Skills.ById[req].Name)
		end
		if #node.RequiresAny > 0 then
			local names = {}
			for _, req in ipairs(node.RequiresAny) do
				table.insert(names, Skills.ById[req].Name)
			end
			local any = false
			for _, req in ipairs(node.RequiresAny) do
				if (owned[req] or 0) > 0 then
					any = true
				end
			end
			table.insert(reqParts, (if any then "✓ " else "✗ ") .. "one of: " .. table.concat(names, " / "))
		end
		dReq.Text = if #reqParts > 0 then "Requires " .. table.concat(reqParts, ", ") else "No requirements"
		if rank >= node.MaxRank then
			UI.setText(unlock, "Maxed ✓")
			UI.setEnabled(unlock, false)
		else
			local cost = Skills.costFor(node, rank)
			local met = Skills.prerequisitesMet(node, owned)
			UI.setText(unlock, if met then `Unlock · {cost} SP` else "Locked 🔒")
			UI.setEnabled(unlock, met and sp >= cost)
		end
	end

	State.subscribe({ "Skills", "Progress" }, function()
		screen.Refresh()
	end)
	window.Opened.Event:Connect(function()
		screen.Refresh()
		local core = nodePosition(Skills.ById.core)
		local size = view.AbsoluteWindowSize
		view.CanvasPosition = Vector2.new(math.max(0, core.X - size.X / 2), math.max(0, core.Y - size.Y / 2))
	end)
	return screen
end

return SkillsScreen
