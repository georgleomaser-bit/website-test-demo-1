--[[
	Skills (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Screens/Skills
	Depends on: ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format,Formulas,Config/*},
	            Client/{State,ClientNet}

	Visual skill tree on a pannable, zoomable canvas that builds itself up as
	skills are bought (Config/Skills.visibility):
	  visible  core, owned nodes and nodes whose prerequisites are met
	  teaser   the next ring, shown only as a dim "?" silhouette
	  hidden   everything further out (nodes and connector lines)
	The canvas only spans the revealed part of the tree, so it grows as the
	tree grows. Newly revealed nodes pop in and their connector lines draw
	outward; a respec collapses the tree again (instant with Reduced motion).

	Visible nodes show four states:
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
-- Space kept around the revealed nodes when sizing the canvas.
local PAD = 80
local MIN_ZOOM, MAX_ZOOM = 0.45, 1.4

local STAT_LABELS = {
	clickPct = "Click Power",
	clickMult = "Click Power",
	sparksPct = "Sparks",
	sparksMult = "Sparks",
	luck = "Luck",
	critChance = "Crit Chance",
	critPower = "Crit Multiplier",
	chestBonus = "Bonus item chance",
	goldenPct = "Golden chance",
	goldenMult = "Golden chance",
	passivePct = "Passive income",
	passiveMult = "Passive income",
	gemsPct = "Gems",
	xpPct = "XP",
	xpMult = "XP",
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
		Subtitle = "Spend Skill Points from levelling up. The tree grows as you unlock it.",
		Icon = "🌳",
		Parent = ctx.Layers.Windows,
	})
	local screen: { [string]: any } = { Window = window }
	local body = window.Body
	local selectedId = "core"

	-- Canvas -----------------------------------------------------------------------------------
	-- Nodes live on `content` (the whole tree, in tree coordinates). The scrolling
	-- canvas only covers the revealed bounds, and `zoomScale` scales the content.
	local minX, maxX, minY, maxY = 0, 0, 0, 0
	for _, node in ipairs(Skills.List) do
		minX, maxX = math.min(minX, node.X), math.max(maxX, node.X)
		minY, maxY = math.min(minY, node.Y), math.max(maxY, node.Y)
	end
	local treeW = (maxX - minX) * CELL + MARGIN * 2
	local treeH = (maxY - minY) * CELL + MARGIN * 2

	local view = UI.new("ScrollingFrame", {
		Name = "Tree",
		Size = UDim2.new(1, -320, 1, 0),
		BackgroundColor3 = C.BackgroundAlt,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(treeW, treeH),
		ScrollingDirection = Enum.ScrollingDirection.XY,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = C.Stroke,
		Corner = Theme.Radius.Medium,
		Stroke = { Color = C.StrokeSoft },
		Parent = body,
	})
	local content = UI.frame({
		Name = "Content",
		Size = UDim2.fromOffset(treeW, treeH),
		Parent = view,
	})
	local zoomScale = Instance.new("UIScale")
	zoomScale.Scale = if UI.isCompact() then 0.8 else 1
	zoomScale.Parent = content
	-- Converts the window's own UIScale out of absolute (screen) sizes.
	local probe = UI.frame({ Name = "ScaleProbe", Size = UDim2.fromOffset(100, 100), Visible = false, Parent = body })

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
			Visible = false,
			ZIndex = 1,
			Parent = content,
		})
		table.insert(lines, { Line = line, From = fromId, To = toId, A = a, B = b, Optional = optional, Shown = nil })
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
			Visible = false,
			ZIndex = 3,
			Selectable = true,
			Corner = Theme.Radius.Pill,
			Parent = content,
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
			Visible = false,
			ZIndex = 3,
			Parent = content,
		})
		button.Activated:Connect(function()
			selectedId = node.Id
			screen.Refresh()
		end)
		button.SelectionGained:Connect(function()
			selectedId = node.Id
			screen.Refresh()
		end)
		local entry = { Node = node, Button = button, Stroke = stroke, Rank = rank, Name = name, Scale = scale, Branch = branch, Shown = nil }
		UI.attachTooltip(button, function()
			if entry.Shown == "teaser" then
				return "<b>❔ Undiscovered skill</b>\nUnlock a connected skill to reveal it."
			end
			local owned = (State.get("Skills") or {})[node.Id] or 0
			return `<b>{node.Icon} {node.Name}</b>  {owned}/{node.MaxRank}\n{node.Description}`
		end)
		nodes[node.Id] = entry
	end

	-- Zoom and canvas bounds -----------------------------------------------------------------------
	local bounds = { X0 = 0, Y0 = 0, X1 = treeW, Y1 = treeH }
	local contentOffset = Vector2.zero

	local function windowScale(): number
		local s = probe.AbsoluteSize.X / 100
		return if s > 0.01 then s else 1
	end
	local function windowLocalSize(): Vector2
		return view.AbsoluteWindowSize / windowScale()
	end

	-- Sizes the canvas to the revealed bounds at the current zoom, keeping what is on screen
	-- in place (the content moves inside the canvas, so the canvas position follows it).
	local function layoutCanvas()
		local z = zoomScale.Scale
		local win = windowLocalSize()
		local w = (bounds.X1 - bounds.X0) * z
		local h = (bounds.Y1 - bounds.Y0) * z
		local centerX = math.max(0, (win.X - w) / 2)
		local centerY = math.max(0, (win.Y - h) / 2)
		local offset = Vector2.new(centerX - bounds.X0 * z, centerY - bounds.Y0 * z)
		local shift = offset - contentOffset
		contentOffset = offset
		content.Position = UDim2.fromOffset(offset.X, offset.Y)
		view.CanvasSize = UDim2.fromOffset(math.max(w, 1), math.max(h, 1))
		local maxScroll = Vector2.new(math.max(0, w - win.X), math.max(0, h - win.Y))
		local target = view.CanvasPosition + shift
		view.CanvasPosition = Vector2.new(math.clamp(target.X, 0, maxScroll.X), math.clamp(target.Y, 0, maxScroll.Y))
	end

	-- Scrolls so that a point of the tree (tree coordinates) is centred in the view.
	local function centerOn(point: Vector2)
		local z = zoomScale.Scale
		local win = windowLocalSize()
		local canvas = Vector2.new(view.CanvasSize.X.Offset, view.CanvasSize.Y.Offset)
		local target = contentOffset + point * z - win / 2
		local maxScroll = Vector2.new(math.max(0, canvas.X - win.X), math.max(0, canvas.Y - win.Y))
		view.CanvasPosition = Vector2.new(math.clamp(target.X, 0, maxScroll.X), math.clamp(target.Y, 0, maxScroll.Y))
	end

	local function viewCenter(): Vector2
		local win = windowLocalSize()
		return (view.CanvasPosition + win / 2 - contentOffset) / zoomScale.Scale
	end

	local function setZoom(z: number)
		local keep = viewCenter()
		zoomScale.Scale = math.clamp(z, MIN_ZOOM, MAX_ZOOM)
		layoutCanvas()
		centerOn(keep)
	end

	local zoomBar = UI.frame({
		Name = "Zoom",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -330, 0, 8),
		Size = UDim2.fromOffset(3 * 38 + 2 * 6, 38),
		List = { Dir = "X", Pad = 6 },
		ZIndex = 20,
		Parent = body,
	})
	local function zoomButton(text: string, order: number, onClick: () -> ())
		UI.button({
			Text = text,
			Variant = "ghost",
			Size = UDim2.fromOffset(38, 38),
			TextSize = 18,
			LayoutOrder = order,
			ZIndex = 21,
			OnClick = onClick,
			Parent = zoomBar,
		})
	end
	zoomButton("−", 1, function()
		setZoom(zoomScale.Scale / 1.2)
	end)
	zoomButton("+", 2, function()
		setZoom(zoomScale.Scale * 1.2)
	end)
	zoomButton("⤢", 3, function()
		-- Fit the revealed part of the tree into the view.
		local win = windowLocalSize()
		local w, h = bounds.X1 - bounds.X0, bounds.Y1 - bounds.Y0
		zoomScale.Scale = math.clamp(math.min(win.X / w, win.Y / h), MIN_ZOOM, MAX_ZOOM)
		layoutCanvas()
		centerOn(Vector2.new((bounds.X0 + bounds.X1) / 2, (bounds.Y0 + bounds.Y1) / 2))
	end)

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
	local discoverLabel = UI.label({ Name = "Discover", Text = "", TextSize = 12, TextColor3 = C.TextMuted, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 24), Parent = detail })
	local dIcon = UI.label({ Text = "", TextSize = 44, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 42), Parent = detail })
	local dName = UI.label({ Text = "", Font = F.Heading, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 100), Parent = detail })
	local dBranch = UI.label({ Text = "", Font = F.Bold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 124), Parent = detail })
	local dDesc = UI.label({ Text = "", TextSize = 14, TextColor3 = C.TextDim, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 148), Parent = detail })
	local dEffect = UI.label({ Text = "", Font = F.Bold, TextSize = 14, TextColor3 = C.Accent2, TextWrapped = true, RichText = true, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 192), Parent = detail })
	local dReq = UI.label({ Text = "", TextSize = 13, TextColor3 = C.TextMuted, TextWrapped = true, RichText = true, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 236), Parent = detail })
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
				Message = `All spent Skill Points are refunded and the tree folds back to the core. This costs 💎 {GameConfig.Skills.RespecGemCost} Gems.`,
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

	-- Reveal animation ---------------------------------------------------------------------------
	-- Applies a node's visibility state; animates when `animate` and the state changed.
	local function showNode(entry, state: string, animate: boolean, delay: number)
		local previous = entry.Shown
		if previous == state then
			return
		end
		entry.Shown = state
		local button, name = entry.Button, entry.Name
		if state == "hidden" then
			name.Visible = false
			if animate and previous ~= nil and not Theme.ReducedMotion then
				local t = UI.tween(entry.Scale, { Scale = 0 }, Theme.Motion.Fast)
				if t then
					t.Completed:Connect(function()
						if entry.Shown == "hidden" then
							button.Visible = false
						end
					end)
					return
				end
			end
			button.Visible = false
			return
		end
		local teaser = state == "teaser"
		button.Visible = true
		button.Text = if teaser then "?" else entry.Node.Icon
		button.Selectable = true
		entry.Rank.Visible = not teaser
		name.Visible = not teaser
		if not animate or previous == nil or Theme.ReducedMotion then
			entry.Scale.Scale = 1
			return
		end
		-- Pop in, slightly staggered by distance from the core so the tree "grows".
		entry.Scale.Scale = if previous == "hidden" then 0 else 0.6
		task.delay(delay, function()
			if entry.Shown == state then
				UI.tween(entry.Scale, { Scale = 1 }, Theme.Motion.Pop)
			end
		end)
	end

	local function showLine(line, shown: boolean, animate: boolean, delay: number)
		if line.Shown == shown then
			return
		end
		local first = line.Shown == nil
		line.Shown = shown
		local frame = line.Line
		if not shown then
			frame.Visible = false
			return
		end
		frame.Visible = true
		local full = (line.B - line.A).Magnitude
		local thickness = if line.Optional then 3 else 5
		local mid = (line.A + line.B) / 2
		if not animate or first or Theme.ReducedMotion then
			frame.Position = UDim2.fromOffset(mid.X, mid.Y)
			frame.Size = UDim2.fromOffset(full, thickness)
			return
		end
		-- Draw outward from the parent: the line's centre and length grow together.
		frame.Position = UDim2.fromOffset(line.A.X, line.A.Y)
		frame.Size = UDim2.fromOffset(0, thickness)
		task.delay(delay, function()
			if line.Shown then
				UI.tween(frame, { Position = UDim2.fromOffset(mid.X, mid.Y), Size = UDim2.fromOffset(full, thickness) }, Theme.Motion.Slow)
			end
		end)
	end

	-- Rendering ----------------------------------------------------------------------------------
	local pulse = 0
	RunService.RenderStepped:Connect(function(dt)
		if not window.IsOpen() or Theme.ReducedMotion then
			return
		end
		pulse += dt
		local t = (math.sin(pulse * 4) + 1) / 2
		for _, entry in pairs(nodes) do
			if entry.Available and entry.Shown == "visible" then
				entry.Stroke.Transparency = t * 0.6
			end
		end
	end)

	local everShown = false
	function screen.Refresh()
		if not window.IsOpen() then
			return
		end
		local owned = State.get("Skills") or {}
		local sp = State.progress().SkillPoints
		local vis = Skills.visibility(owned)
		local animate = everShown
		everShown = true

		-- Reveal / collapse ------------------------------------------------------------------
		local ownedCount, undiscovered = 0, 0
		local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
		for id, entry in pairs(nodes) do
			local state = vis[id]
			if (owned[id] or 0) > 0 then
				ownedCount += 1
			end
			if state ~= "visible" then
				undiscovered += 1
			end
			if state ~= "hidden" then
				local pos = nodePosition(entry.Node)
				x0, y0 = math.min(x0, pos.X), math.min(y0, pos.Y)
				x1, y1 = math.max(x1, pos.X), math.max(y1, pos.Y)
			end
			local distance = math.abs(entry.Node.X) + math.abs(entry.Node.Y)
			showNode(entry, state, animate, math.min(0.4, distance * 0.04))
		end
		for _, line in ipairs(lines) do
			-- Lines start at a visible node and end at a visible node or a teaser.
			local shown = vis[line.From] == "visible" and vis[line.To] ~= "hidden"
			showLine(line, shown, animate, 0.05)
		end
		if vis[selectedId] == "hidden" then
			selectedId = "core"
		end
		local newBounds = { X0 = x0 - PAD, Y0 = y0 - PAD, X1 = x1 + PAD, Y1 = y1 + PAD + 20 }
		if newBounds.X0 ~= bounds.X0 or newBounds.Y0 ~= bounds.Y0 or newBounds.X1 ~= bounds.X1 or newBounds.Y1 ~= bounds.Y1 then
			bounds = newBounds
			layoutCanvas()
		end

		spLabel.Text = `🌳 {sp} Skill Point{if sp == 1 then "" else "s"}  ·  {Formulas.skillPointsSpent(State.view())} spent`
		discoverLabel.Text = `{ownedCount} / {#Skills.List} skills unlocked` .. (if undiscovered > 0 then `  ·  {undiscovered} still to discover` else "  ·  tree complete!")

		-- Node states ------------------------------------------------------------------------
		for id, entry in pairs(nodes) do
			local node = entry.Node
			local rank = owned[id] or 0
			local met = Skills.prerequisitesMet(node, owned)
			local maxed = rank >= node.MaxRank
			local affordable = Skills.costFor(node, rank) <= sp
			entry.Available = met and not maxed and affordable
			entry.Rank.Text = `{rank}/{node.MaxRank}`
			if entry.Shown == "teaser" then
				entry.Button.BackgroundColor3 = C.Panel
				entry.Stroke.Color = C.StrokeSoft
				entry.Stroke.Transparency = 0.5
				entry.Button.TextTransparency = 0.45
			elseif maxed then
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
			local reachable = (owned[line.From] or 0) > 0 and vis[line.To] == "visible"
			line.Line.BackgroundColor3 = if active
				then Skills.Branches[Skills.ById[line.To].Branch].Color
				elseif reachable then C.Stroke
				else C.StrokeSoft
			line.Line.BackgroundTransparency = if vis[line.To] == "teaser" then 0.55 elseif line.Optional then 0.35 else 0
		end

		-- Detail panel ------------------------------------------------------------------------
		local node = Skills.ById[selectedId]
		local branch = Skills.Branches[node.Branch]
		local rank = owned[node.Id] or 0
		if vis[node.Id] == "teaser" then
			-- Undiscovered: no name, effect or cost; only which visible skills lead to it.
			dIcon.Text = "❔"
			dName.Text = "Undiscovered skill"
			dBranch.Text = `{branch.Name} branch`
			dBranch.TextColor3 = branch.Color
			dDesc.Text = "Unlock a connected skill to reveal what this one does."
			dEffect.Text = ""
			local names = {}
			for _, req in ipairs(Skills.prerequisiteIds(node)) do
				if vis[req] == "visible" then
					table.insert(names, Skills.ById[req].Name)
				end
			end
			dReq.Text = if #names > 0 then "Connected to " .. table.concat(names, ", ") else ""
			UI.setText(unlock, "Undiscovered ❔")
			UI.setEnabled(unlock, false)
			return
		end
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
			local any = false
			for _, req in ipairs(node.RequiresAny) do
				-- Only name the options the player can already see.
				table.insert(names, if vis[req] == "visible" then Skills.ById[req].Name else "???")
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
		layoutCanvas()
		centerOn(nodePosition(Skills.ById[selectedId]))
	end)
	return screen
end

return SkillsScreen
