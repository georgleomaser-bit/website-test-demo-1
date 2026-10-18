--[[
	LogRow (ModuleScript)
	Location: ServerStorage/AdminClient/AdminUI/LogRow
	Depends on: AdminUI/Widgets

	Renders audit-log and security-flag entries as two-line rows. Used by the
	Dashboard and Audit Logs tabs. Rows can be re-filled in place (reuse).
]]

local Widgets = require(script.Parent.Widgets)

local UI = Widgets.UI
local P = Widgets.P
local F = Widgets.Theme.Fonts

local LogRow = {}

function LogRow.create(parent: Instance, compact: boolean?): Frame
	local height = if compact then 36 else 44
	local row = UI.new("Frame", {
		Name = "LogRow",
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = P.Background,
		BackgroundTransparency = 0.2,
		Corner = 8,
		Parent = parent,
	})
	UI.label({
		Name = "Top",
		Font = F.Mono,
		TextSize = if compact then 12 else 13,
		TextColor3 = P.Text,
		RichText = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -110, 0, 18),
		Position = UDim2.fromOffset(10, if compact then 2 else 4),
		Parent = row,
	})
	UI.label({
		Name = "Bottom",
		Font = Widgets.Theme.Fonts.Body,
		TextSize = 12,
		TextColor3 = P.TextDim,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -20, 0, 16),
		Position = UDim2.fromOffset(10, if compact then 18 else 23),
		Parent = row,
	})
	local result = UI.label({
		Name = "Result",
		Font = F.Bold,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromOffset(96, 18),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, if compact then 2 else 4),
		BackgroundTransparency = 0,
		BackgroundColor3 = P.PanelLight,
		Corner = 999,
		Parent = row,
	})
	UI.stroke(result, { Color = P.Stroke, Transparency = 0.3 })
	return row
end

local function escape(text: any): string
	local s = tostring(text or "")
	s = string.gsub(s, "&", "&amp;")
	s = string.gsub(s, "<", "&lt;")
	s = string.gsub(s, ">", "&gt;")
	return s
end

local function hex(color: Color3): string
	return color:ToHex()
end

-- Fills a row with an audit entry.
function LogRow.fillAudit(row: Frame, entry)
	local top = row:FindFirstChild("Top") :: TextLabel
	local bottom = row:FindFirstChild("Bottom") :: TextLabel
	local result = row:FindFirstChild("Result") :: TextLabel
	local color = Widgets.Result[entry.Result] or P.TextDim
	local target = if entry.TargetName then "  → " .. escape(entry.TargetName) else ""
	top.Text = `<font color="#{hex(P.TextDim)}">{Widgets.clock(entry.Time)}</font>  <b>{escape(entry.AdminName or "?")}</b>`
		.. ` <font color="#{hex(P.Accent2)}">[{escape(entry.Role or "None")}]</font>  {escape(entry.Action)}{target}`
	local details = {}
	if entry.Params and entry.Params ~= "" then
		table.insert(details, entry.Params)
	end
	if entry.Message and entry.Message ~= "" then
		table.insert(details, entry.Message)
	end
	bottom.Text = table.concat(details, "  ·  ")
	result.Text = string.upper((string.gsub(tostring(entry.Result or "?"), "_", " ")))
	result.TextColor3 = color
	local stroke = result:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
	end
end

-- Fills a row with a security flag ({ Time, UserId, Name, Reason, Detail, Count }).
function LogRow.fillSecurity(row: Frame, entry)
	local top = row:FindFirstChild("Top") :: TextLabel
	local bottom = row:FindFirstChild("Bottom") :: TextLabel
	local result = row:FindFirstChild("Result") :: TextLabel
	top.Text = `<font color="#{hex(P.TextDim)}">{Widgets.clock(entry.Time)}</font>  <b>{escape(entry.Name or "?")}</b> #{escape(entry.UserId)}  {escape(entry.Reason)}`
	bottom.Text = `{entry.Detail or ""}  ·  seen {entry.Count or 1}×`
	result.Text = "FLAG"
	result.TextColor3 = P.Warning
	local stroke = result:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = P.Warning
	end
end

return LogRow
