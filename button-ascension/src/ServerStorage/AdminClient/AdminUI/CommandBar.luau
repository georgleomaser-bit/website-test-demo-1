--[[
	CommandBar (ModuleScript)
	Location: ServerStorage/AdminClient/AdminUI/CommandBar
	Depends on: AdminUI/Widgets, AdminUI/AdminNet

	Searchable command bar with console output.
	  * Enter runs the line on the server (parsing happens server-side).
	  * Up / Down walk through history, Tab completes the highlighted suggestion.
	  * Suggestions come from the commands the server says this role may use.
	  * Output: commands in magenta, results in green, errors in red.
]]

local UserInputService = game:GetService("UserInputService")

local Widgets = require(script.Parent.Widgets)
local AdminNet = require(script.Parent.AdminNet)

local UI = Widgets.UI
local P = Widgets.P
local F = Widgets.Theme.Fonts

local MAX_LINES = 200
local MAX_SUGGESTIONS = 6

local CommandBar = {}

function CommandBar.new(ctx, parent: Instance)
	local root = UI.frame({ Name = "CommandBar", Size = UDim2.new(1, 0, 0, 150), ZIndex = 20, Parent = parent })

	local inputRow = UI.new("Frame", {
		Name = "Input",
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundColor3 = P.Background,
		ZIndex = 20,
		Corner = 10,
		Stroke = { Color = P.Accent, Transparency = 0.45 },
		Parent = root,
	})
	Widgets.label({
		Text = "›",
		Font = F.Heading,
		TextSize = 22,
		TextColor3 = P.Accent,
		Size = UDim2.fromOffset(26, 38),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 21,
		Parent = inputRow,
	})
	local box: TextBox = UI.new("TextBox", {
		Name = "Command",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(26, 0),
		Size = UDim2.new(1, -120, 1, 0),
		ClearTextOnFocus = false,
		Font = F.Mono,
		TextSize = 14,
		TextColor3 = P.Text,
		PlaceholderText = "Type a command — e.g. givecash me 1k  ·  help",
		PlaceholderColor3 = Widgets.Theme.darken(P.TextDim, 0.25),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		ZIndex = 21,
		Parent = inputRow,
	})
	local run = Widgets.button({
		Text = "Run",
		Variant = "adminPrimary",
		Size = UDim2.fromOffset(80, 30),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		ZIndex = 21,
		Parent = inputRow,
	})

	local console = UI.scroll({
		Name = "Console",
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 1, -46),
		BackgroundColor3 = P.Background,
		BackgroundTransparency = 0,
		ScrollBarImageColor3 = P.Stroke,
		ZIndex = 20,
		Corner = 10,
		Stroke = { Color = P.Stroke, Transparency = 0.4 },
		Padding = { 10, 10, 6, 6 },
		List = { Pad = 2 },
		Parent = root,
	})

	local suggestionsFrame = UI.new("Frame", {
		Name = "Suggestions",
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, -90, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = P.Panel,
		Visible = false,
		ZIndex = 30,
		Corner = 10,
		Stroke = { Color = P.Accent, Transparency = 0.3 },
		Padding = 4,
		List = { Pad = 2 },
		Parent = root,
	})

	local bar = { Frame = root, Box = box }
	local lineCount = 0
	local history: { string } = {}
	local historyIndex = 0
	local suggestions: { any } = {}
	local highlighted = 1

	function bar.Log(text: string, kind: string?)
		local color = P.TextDim
		if kind == "ok" then
			color = P.Accent
		elseif kind == "error" then
			color = P.Danger
		elseif kind == "command" then
			color = P.Accent2
		elseif kind == "warn" then
			color = P.Warning
		end
		lineCount += 1
		UI.label({
			Name = "Line",
			Text = text,
			Font = F.Mono,
			TextSize = 13,
			TextColor3 = color,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 16),
			LayoutOrder = lineCount,
			ZIndex = 21,
			Parent = console,
		})
		local lines = {}
		for _, child in ipairs(console:GetChildren()) do
			if child:IsA("TextLabel") then
				table.insert(lines, child)
			end
		end
		if #lines > MAX_LINES then
			table.sort(lines, function(a, b)
				return a.LayoutOrder < b.LayoutOrder
			end)
			for i = 1, #lines - MAX_LINES do
				lines[i]:Destroy()
			end
		end
		task.defer(function()
			console.CanvasPosition = Vector2.new(0, math.max(0, console.AbsoluteCanvasSize.Y - console.AbsoluteWindowSize.Y))
		end)
	end

	local function commandWord(text: string): (string, boolean)
		local s = string.gsub(text, "^%s*", "")
		s = string.gsub(s, "^/admin%s*", "")
		s = string.gsub(s, "^[/;:]", "")
		local word = string.match(s, "^(%S*)") or ""
		local hasSpace = string.find(s, "%s") ~= nil
		return string.lower(word), hasSpace
	end

	local function renderSuggestions()
		for _, child in ipairs(suggestionsFrame:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		suggestionsFrame.Visible = #suggestions > 0 and box:IsFocused()
		for index, cmd in ipairs(suggestions) do
			local row = UI.new("TextButton", {
				Name = "Suggestion",
				Size = UDim2.new(1, 0, 0, 34),
				BackgroundColor3 = P.PanelLighter,
				BackgroundTransparency = if index == highlighted then 0 else 1,
				AutoButtonColor = false,
				Text = "",
				LayoutOrder = index,
				ZIndex = 31,
				Corner = 6,
				Parent = suggestionsFrame,
			})
			Widgets.label({
				Text = cmd.Usage,
				Font = F.Mono,
				TextSize = 13,
				TextColor3 = P.Accent,
				Size = UDim2.new(1, -12, 0, 16),
				Position = UDim2.fromOffset(8, 2),
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 32,
				Parent = row,
			})
			Widgets.dim({
				Text = cmd.Description,
				TextSize = 12,
				Size = UDim2.new(1, -12, 0, 14),
				Position = UDim2.fromOffset(8, 18),
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 32,
				Parent = row,
			})
			row.Activated:Connect(function()
				box.Text = cmd.Name .. " "
				box:CaptureFocus()
				box.CursorPosition = #box.Text + 1
			end)
		end
	end

	local function updateSuggestions()
		local word, hasSpace = commandWord(box.Text)
		table.clear(suggestions)
		highlighted = 1
		if word ~= "" or box.Text == "" then
			for _, cmd in ipairs(ctx.Hello.Commands or {}) do
				local name = string.lower(cmd.Name)
				local matches = if hasSpace then name == word else string.sub(name, 1, #word) == word
				if matches then
					table.insert(suggestions, cmd)
					if #suggestions >= MAX_SUGGESTIONS then
						break
					end
				end
			end
		end
		if box.Text == "" then
			table.clear(suggestions)
		end
		renderSuggestions()
	end

	local function submit()
		local text = string.gsub(box.Text, "^%s*(.-)%s*$", "%1")
		if text == "" then
			return
		end
		box.Text = ""
		table.insert(history, text)
		if #history > 50 then
			table.remove(history, 1)
		end
		historyIndex = #history + 1
		bar.Log("> " .. text, "command")
		task.spawn(AdminNet.command, text)
	end
	bar.Submit = submit

	box:GetPropertyChangedSignal("Text"):Connect(function()
		if string.find(box.Text, "\t", 1, true) then
			box.Text = string.gsub(box.Text, "\t", "")
			return
		end
		if #box.Text > 300 then
			box.Text = string.sub(box.Text, 1, 300)
			return
		end
		updateSuggestions()
	end)
	box.Focused:Connect(updateSuggestions)
	box.FocusLost:Connect(function(enterPressed)
		task.delay(0.15, function()
			if not box:IsFocused() then
				suggestionsFrame.Visible = false
			end
		end)
		if enterPressed then
			submit()
			-- Keep typing on keyboards; on touch devices let the keyboard close.
			if not UserInputService.TouchEnabled then
				box:CaptureFocus()
			end
		end
	end)
	run.Activated:Connect(submit)

	UserInputService.InputBegan:Connect(function(input)
		if UserInputService:GetFocusedTextBox() ~= box then
			return
		end
		if input.KeyCode == Enum.KeyCode.Up then
			if #history > 0 then
				historyIndex = math.max(1, historyIndex - 1)
				box.Text = history[historyIndex]
				box.CursorPosition = #box.Text + 1
			end
		elseif input.KeyCode == Enum.KeyCode.Down then
			if historyIndex < #history then
				historyIndex += 1
				box.Text = history[historyIndex]
			else
				historyIndex = #history + 1
				box.Text = ""
			end
			box.CursorPosition = #box.Text + 1
		elseif input.KeyCode == Enum.KeyCode.Tab then
			local cmd = suggestions[highlighted]
			if cmd then
				local _, hasSpace = commandWord(box.Text)
				if not hasSpace then
					box.Text = cmd.Name .. " "
					box.CursorPosition = #box.Text + 1
				end
			end
		end
	end)

	function bar.SetCompact(compact: boolean)
		root.Size = UDim2.new(1, 0, 0, if compact then 112 else 150)
	end

	bar.Log("Admin console ready. Type help for commands. Results of panel actions appear here too.", "info")
	return bar
end

return CommandBar
