--[[
	TargetPicker (ModuleScript)
	Location: ServerStorage/AdminClient/AdminUI/TargetPicker
	Depends on: AdminUI/Widgets

	"Target" row used by the Economy, Items and Progression tabs. Every picker
	shares ctx.Target, so selecting a player once (here or in the Players tab)
	selects them everywhere.

	Accepted input (resolved on the SERVER, which rejects ambiguous names):
	  name or display-name prefix, @username, #UserId (also works for offline
	  tools when the role allows it), or "me".
]]

local Widgets = require(script.Parent.Widgets)

local P = Widgets.P

local TargetPicker = {}

-- Converts typed text into the value sent to the server.
function TargetPicker.queryFromText(text: string): any
	local trimmed = string.gsub(text, "^%s*(.-)%s*$", "%1")
	if trimmed == "" then
		return nil
	end
	if string.match(trimmed, "^%d+$") then
		return "#" .. trimmed
	end
	return trimmed
end

function TargetPicker.new(ctx, parent: Instance, order: number?)
	local row = Widgets.row(parent, order, 34)
	Widgets.rowLabel(row, "Target", 70, 1)
	local syncing = false
	local box = Widgets.textbox({
		Placeholder = "name, @username, #UserId or me",
		Size = UDim2.fromOffset(250, 32),
		LayoutOrder = 2,
		MaxLength = 50,
		Text = ctx.Target.Label or "",
		Parent = row,
	})
	local status = Widgets.dim({
		Text = "",
		Size = UDim2.new(1, -470, 0, 32),
		LayoutOrder = 4,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})

	local online = Widgets.button({
		Text = "Online ▾",
		Size = UDim2.fromOffset(110, 32),
		LayoutOrder = 3,
		Variant = "adminSecondary",
		Parent = row,
	})

	local function describe()
		local target = ctx.Target
		if target.Query == nil then
			status.Text = "No player selected."
			status.TextColor3 = P.TextDim
		elseif type(target.Query) == "number" then
			status.Text = "✔ " .. (target.Label or "") .. "  #" .. tostring(target.Query)
			status.TextColor3 = P.Accent
		else
			status.Text = "Resolved by the server when you run an action."
			status.TextColor3 = P.TextDim
		end
	end

	online.Activated:Connect(function()
		local players = ctx.refreshPlayers()
		local options = {}
		for _, p in ipairs(players) do
			local label = if p.DisplayName ~= p.Name then `{p.DisplayName} (@{p.Name})` else "@" .. p.Name
			if p.StaffRole then
				label ..= "  [" .. p.StaffRole .. "]"
			end
			table.insert(options, { Text = label, Value = p.UserId, Color = if p.StaffRole then P.Accent2 else nil })
		end
		Widgets.popupList(online, options, function(userId)
			for _, p in ipairs(players) do
				if p.UserId == userId then
					local label = if p.DisplayName ~= p.Name then `{p.DisplayName} (@{p.Name})` else "@" .. p.Name
					ctx.setTarget(userId, label)
				end
			end
		end, 280)
	end)

	box:GetPropertyChangedSignal("Text"):Connect(function()
		if syncing then
			return
		end
		ctx.setTarget(TargetPicker.queryFromText(box.Text), box.Text, box)
	end)

	ctx.TargetChanged:Connect(function(source)
		if source ~= box then
			syncing = true
			box.Text = ctx.Target.Label or ""
			syncing = false
		end
		describe()
	end)
	describe()

	return {
		Frame = row,
		Box = box,
		Get = function()
			return ctx.Target.Query
		end,
	}
end

return TargetPicker
