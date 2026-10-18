--[[
	Widgets (ModuleScript)
	Location: ServerStorage/AdminClient/AdminUI/Widgets
	Depends on: ReplicatedStorage/UI/UIKit, ReplicatedStorage/UI/Theme, ReplicatedStorage/Shared/Config/Rarities

	Admin-styled building blocks on top of UIKit: the same components and
	motion as the player UI, re-skinned with Theme.Admin (near-black teal,
	neon green, magenta) so staff tools are unmistakable.

	Registers extra UIKit button variants at load:
	  adminPrimary, adminSecondary, adminGhost, adminDanger, adminMagenta, adminWarn
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local UIFolder = ReplicatedStorage:WaitForChild("UI")
local UI = require(UIFolder:WaitForChild("UIKit"))
local Theme = require(UIFolder:WaitForChild("Theme"))
local Rarities = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Rarities"))

local P = Theme.Admin
local F = Theme.Fonts

local W = {}
W.P = P
W.UI = UI
W.Theme = Theme

UI.Variants.adminPrimary = { Bg = P.Accent, Text = Color3.fromRGB(3, 26, 19), Stroke = Theme.lighten(P.Accent, 0.35) }
UI.Variants.adminSecondary = { Bg = P.PanelLighter, Text = P.Text, Stroke = P.Stroke }
UI.Variants.adminGhost = { Bg = P.PanelLight, Text = P.TextDim, Stroke = P.Stroke }
UI.Variants.adminDanger = { Bg = Color3.fromRGB(176, 28, 52), Text = Color3.new(1, 1, 1), Stroke = P.Danger }
UI.Variants.adminMagenta = { Bg = Color3.fromRGB(170, 26, 136), Text = Color3.new(1, 1, 1), Stroke = P.Accent2 }
UI.Variants.adminWarn = { Bg = Color3.fromRGB(196, 136, 26), Text = Color3.fromRGB(30, 18, 0), Stroke = P.Warning }

W.Result = {
	success = P.Accent,
	denied = P.Danger,
	invalid = P.Warning,
	error = P.Danger,
	rate_limited = P.Warning,
	confirm_required = P.Accent2,
	duplicate = P.TextDim,
}

-- Text ---------------------------------------------------------------------------------

function W.label(props: { [string]: any }?): TextLabel
	return UI.label(UI.merge({ TextColor3 = P.Text, TextSize = 14 }, props))
end

function W.dim(props: { [string]: any }?): TextLabel
	return UI.label(UI.merge({ TextColor3 = P.TextDim, TextSize = 13, Font = F.Body }, props))
end

function W.heading(props: { [string]: any }?): TextLabel
	return UI.label(UI.merge({ TextColor3 = P.Text, TextSize = 16, Font = F.Heading, Size = UDim2.new(1, 0, 0, 22) }, props))
end

-- Buttons ---------------------------------------------------------------------------------

function W.button(props: { [string]: any }): TextButton
	local p = table.clone(props)
	p.Variant = p.Variant or "adminSecondary"
	p.TextSize = p.TextSize or 14
	p.Size = p.Size or UDim2.fromOffset(120, 32)
	return UI.button(p)
end

-- Disables a control the role lacks permission for (the server enforces this anyway).
function W.gate(button: TextButton, allowed: boolean, permission: string)
	if not allowed then
		UI.setEnabled(button, false)
		UI.attachTooltip(button, "Your role lacks the permission <b>" .. permission .. "</b>.")
	end
end

-- Inputs ----------------------------------------------------------------------------------

--[[ props: Placeholder, Text, OnSubmit(text), OnChanged(text), MaxLength + TextBox props ]]
function W.textbox(props: { [string]: any }): TextBox
	local onSubmit, onChanged, maxLength = props.OnSubmit, props.OnChanged, props.MaxLength
	local clean = {}
	for k, v in pairs(props) do
		if k ~= "OnSubmit" and k ~= "OnChanged" and k ~= "MaxLength" and k ~= "Placeholder" then
			clean[k] = v
		end
	end
	local box: TextBox = UI.new(
		"TextBox",
		UI.merge({
			BackgroundColor3 = P.Background,
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			Font = F.Medium,
			TextSize = 14,
			TextColor3 = P.Text,
			PlaceholderColor3 = Theme.darken(P.TextDim, 0.25),
			PlaceholderText = props.Placeholder or "",
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Size = UDim2.new(1, 0, 0, 32),
			Corner = 8,
			Padding = { X = 10 },
		}, clean)
	)
	local stroke = UI.stroke(box, { Color = P.Stroke })
	box.Focused:Connect(function()
		UI.tween(stroke, { Color = P.Accent }, Theme.Motion.Fast)
	end)
	box.FocusLost:Connect(function(enterPressed)
		UI.tween(stroke, { Color = P.Stroke }, Theme.Motion.Fast)
		if enterPressed and onSubmit then
			onSubmit(box.Text)
		end
	end)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		if maxLength and #box.Text > maxLength then
			box.Text = string.sub(box.Text, 1, maxLength)
			return
		end
		if onChanged then
			onChanged(box.Text)
		end
	end)
	return box
end

local SUFFIX = { k = 1e3, m = 1e6, b = 1e9, t = 1e12, qa = 1e15, qi = 1e18 }

-- Parses 1500, 1,500, 2.5k, 3m, 1b, 4t, 1e6. Returns nil when not a number.
function W.parseNumber(text: string?): number?
	if type(text) ~= "string" then
		return nil
	end
	local s = string.lower((string.gsub(text, "[,%s]", "")))
	if s == "" then
		return nil
	end
	local direct = tonumber(s)
	if direct then
		return if direct == direct and direct ~= math.huge and direct ~= -math.huge then direct else nil
	end
	local num, suffix = string.match(s, "^(%-?[%d%.]+)(%a+)$")
	if num and SUFFIX[suffix] then
		local n = tonumber(num)
		if n then
			return n * SUFFIX[suffix]
		end
	end
	return nil
end

-- Layout ----------------------------------------------------------------------------------

function W.scroll(parent: Instance, props: { [string]: any }?): ScrollingFrame
	local scroll = UI.scroll(UI.merge({
		ScrollBarImageColor3 = P.Stroke,
		Parent = parent,
	}, props))
	UI.list(scroll, { Pad = 10 })
	UI.padding(scroll, { 2, 10, 2, 12 })
	return scroll
end

-- A titled card that grows with its content. Returns the section frame;
-- add children with increasing LayoutOrder (the title uses 0).
function W.section(parent: Instance, title: string, order: number?, subtitle: string?): Frame
	local section = UI.new("Frame", {
		Name = "Section",
		BackgroundColor3 = P.PanelLight,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order or 0,
		Corner = 12,
		Stroke = { Color = P.Stroke, Transparency = 0.35 },
		Padding = 12,
		List = { Pad = 8 },
		Parent = parent,
	})
	local header = UI.frame({ Name = "Title", Size = UDim2.new(1, 0, 0, if subtitle then 38 else 22), LayoutOrder = 0, Parent = section })
	W.heading({ Text = title, Parent = header })
	if subtitle then
		W.dim({ Text = subtitle, Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 18), TextWrapped = true, Parent = header })
	end
	return section
end

-- Horizontal row of controls.
function W.row(parent: Instance, order: number?, height: number?, pad: number?): Frame
	return UI.frame({
		Name = "Row",
		Size = UDim2.new(1, 0, 0, height or 32),
		LayoutOrder = order or 0,
		List = { Dir = "X", Pad = pad or 8, VA = "Center" },
		Parent = parent,
	})
end

-- Small label for a row, fixed width.
function W.rowLabel(parent: Instance, text: string, width: number?, order: number?): TextLabel
	return W.dim({ Text = text, Size = UDim2.fromOffset(width or 90, 32), LayoutOrder = order or 0, Parent = parent })
end

-- Removes every GuiObject child (keeps layouts, padding, corners, strokes).
function W.clear(frame: Instance)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- Metric card: title, big value, small subtitle.
function W.card(parent: Instance, title: string, order: number?)
	local frame = UI.new("Frame", {
		Name = "Card",
		BackgroundColor3 = P.PanelLight,
		BorderSizePixel = 0,
		LayoutOrder = order or 0,
		Corner = 12,
		Stroke = { Color = P.Stroke, Transparency = 0.35 },
		Padding = { 12, 12, 10, 10 },
		Parent = parent,
	})
	UI.gradient(frame, {
		Color = ColorSequence.new(Theme.lighten(P.PanelLight, 0.05), P.PanelLight),
		Rotation = 90,
	})
	W.dim({ Text = string.upper(title), TextSize = 11, Font = F.Bold, Size = UDim2.new(1, 0, 0, 14), Parent = frame })
	local value = W.label({
		Name = "Value",
		Text = "—",
		Font = F.Heading,
		TextSize = 22,
		Size = UDim2.new(1, 0, 0, 28),
		Position = UDim2.fromOffset(0, 16),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = frame,
	})
	local sub = W.dim({
		Name = "Sub",
		Text = "",
		TextSize = 12,
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.fromOffset(0, 44),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = frame,
	})
	return { Frame = frame, Value = value, Sub = sub }
end

-- Coloured pill tag.
function W.tag(parent: Instance, text: string, color: Color3, order: number?): TextLabel
	local tag = UI.label({
		Text = text,
		Font = F.Bold,
		TextSize = 11,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Center,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 18),
		BackgroundColor3 = Theme.darken(color, 0.75),
		BackgroundTransparency = 0,
		LayoutOrder = order or 0,
		Corner = Theme.Radius.Pill,
		Padding = { X = 8 },
		Parent = parent,
	})
	UI.stroke(tag, { Color = color, Transparency = 0.4 })
	return tag
end

--[[
	Chip row (single choice).
	props: Parent, Options = { { Id, Text, Color? } }, Value, OnChange(id), Order, Height, Width
	Returns { Frame, Set(id), Get(), Buttons }
]]
function W.chips(props: { [string]: any })
	local frame = UI.frame({
		Name = "Chips",
		Size = UDim2.new(1, 0, 0, props.Height or 28),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = props.Order or 0,
		Parent = props.Parent,
	})
	local layout = UI.list(frame, { Dir = "X", Pad = 6, VA = "Center" })
	layout.Wraps = true
	local control = { Frame = frame, Buttons = {} }
	local current = props.Value
	local function render()
		for id, button in pairs(control.Buttons) do
			UI.setVariant(button, if id == current then "adminPrimary" else "adminGhost")
		end
	end
	for index, option in ipairs(props.Options) do
		local button = W.button({
			Text = option.Text,
			Size = UDim2.fromOffset(props.Width or 0, props.Height or 28),
			AutomaticSize = if props.Width then Enum.AutomaticSize.None else Enum.AutomaticSize.X,
			Padding = { X = 10 },
			TextSize = 13,
			LayoutOrder = index,
			Variant = "adminGhost",
			OnClick = function()
				current = option.Id
				render()
				if props.OnChange then
					props.OnChange(option.Id)
				end
			end,
			Parent = frame,
		})
		if option.Color then
			button.TextColor3 = option.Color
		end
		control.Buttons[option.Id] = button
	end
	function control.Set(id)
		current = id
		render()
	end
	function control.Get()
		return current
	end
	render()
	return control
end

-- Popups -------------------------------------------------------------------------------------

local openPopup: Frame? = nil

function W.closePopup()
	if openPopup then
		openPopup:Destroy()
		openPopup = nil
	end
end

--[[
	Floating list under an anchor (rendered in the UIKit overlay so scrolling
	containers never clip it). options: { { Text, Value, Color? } }
]]
function W.popupList(anchor: GuiObject, options: { any }, onPick: (any) -> (), width: number?)
	W.closePopup()
	local overlay = UI.overlay()
	local root = UI.frame({ Name = "AdminPopup", ZIndex = 120, Parent = overlay })
	openPopup = root
	UI.new("TextButton", {
		Name = "Catcher",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		ZIndex = 120,
		Activated = function()
			W.closePopup()
		end,
		Parent = root,
	})
	local absPos = anchor.AbsolutePosition
	local absSize = anchor.AbsoluteSize
	local viewport = UI.viewport()
	local rowHeight = 30
	local height = math.min(#options * (rowHeight + 2) + 10, 260)
	local w = math.max(width or absSize.X, 160)
	local y = absPos.Y + absSize.Y + 4
	if y + height > viewport.Y - 8 then
		y = math.max(8, absPos.Y - height - 4)
	end
	local x = math.clamp(absPos.X, 8, math.max(8, viewport.X - w - 8))
	local list = UI.scroll({
		Name = "List",
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, height),
		BackgroundColor3 = P.Panel,
		BackgroundTransparency = 0,
		ScrollBarImageColor3 = P.Stroke,
		ZIndex = 121,
		Corner = 10,
		Stroke = { Color = P.Accent, Transparency = 0.4 },
		Padding = 5,
		List = { Pad = 2 },
		Parent = root,
	})
	if #options == 0 then
		W.dim({ Text = "Nothing to show.", Size = UDim2.new(1, 0, 0, rowHeight), ZIndex = 122, Parent = list })
	end
	local first: GuiObject? = nil
	for index, option in ipairs(options) do
		local row = UI.new("TextButton", {
			Name = "Option",
			Size = UDim2.new(1, 0, 0, rowHeight),
			BackgroundColor3 = P.PanelLight,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = option.Text,
			TextColor3 = option.Color or P.Text,
			Font = F.Medium,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			LayoutOrder = index,
			ZIndex = 122,
			Corner = 6,
			Padding = { X = 8 },
			Parent = list,
		})
		row.MouseEnter:Connect(function()
			row.BackgroundTransparency = 0
		end)
		row.MouseLeave:Connect(function()
			row.BackgroundTransparency = 1
		end)
		row.SelectionGained:Connect(function()
			row.BackgroundTransparency = 0
		end)
		row.SelectionLost:Connect(function()
			row.BackgroundTransparency = 1
		end)
		row.Activated:Connect(function()
			W.closePopup()
			onPick(option.Value)
		end)
		first = first or row
	end
	if UserInputService.GamepadEnabled and first then
		game:GetService("GuiService").SelectedObject = first
	end
end

--[[
	Dropdown button.
	props: Parent, Order, Width, Placeholder, Options (list or function -> list of { Text, Value, Color? }),
	       Value, Text, OnChange(value)
	Returns { Button, Set(value, text), Get() }
]]
function W.dropdown(props: { [string]: any })
	local current = props.Value
	local dropdown = {}
	local button = W.button({
		Text = (props.Text or props.Placeholder or "Select…") .. "  ▾",
		Size = UDim2.fromOffset(props.Width or 200, props.Height or 32),
		LayoutOrder = props.Order,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Padding = { X = 10 },
		Variant = "adminSecondary",
		Parent = props.Parent,
	})
	dropdown.Button = button
	local function options()
		local list = props.Options
		if type(list) == "function" then
			return list()
		end
		return list
	end
	function dropdown.Set(value, text: string?)
		current = value
		if text then
			button.Text = text .. "  ▾"
		end
	end
	function dropdown.Get()
		return current
	end
	button.Activated:Connect(function()
		W.popupList(button, options(), function(value)
			local label = nil
			for _, option in ipairs(options()) do
				if option.Value == value then
					label = option.Text
				end
			end
			dropdown.Set(value, label)
			if props.OnChange then
				props.OnChange(value)
			end
		end, props.PopupWidth)
	end)
	return dropdown
end

-- Misc ------------------------------------------------------------------------------------------

function W.rarityColor(rarityId: string?): Color3
	local r = rarityId and Rarities.ById[rarityId]
	return if r then r.Color else P.TextDim
end

function W.clock(unix: number?): string
	if type(unix) ~= "number" then
		return "--:--:--"
	end
	local t = os.date("!*t", math.floor(unix))
	return string.format("%02d:%02d:%02d", t.hour, t.min, t.sec)
end

-- Today's UTC date as YYYY-MM-DD (based on the synced server clock).
function W.today(): string
	local t = os.date("!*t", math.floor(workspace:GetServerTimeNow()))
	return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
end

function W.shortId(id: string?): string
	if type(id) ~= "string" or id == "" then
		return "(Studio)"
	end
	return string.sub(id, 1, 8) .. "…"
end

return W
