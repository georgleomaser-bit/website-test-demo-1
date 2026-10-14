-- Messages on screen: toasts, big server announcements (top center, outlined cartoon text
-- like "Ben spawned a RARE EGG!") and the red steal alarm.

local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local Kit = require(script.Parent.Kit)
local Windows = require(script.Parent.Windows)

local Feed = {}

local toastHolder
local announceHolder
local alarmFrame
local alarmSound

local KIND_COLORS = {
	info = Color3.fromRGB(255, 255, 255),
	success = Color3.fromRGB(120, 255, 110),
	error = Color3.fromRGB(255, 110, 110),
	reward = Color3.fromRGB(255, 220, 80),
	rare = Color3.fromRGB(230, 130, 255),
}

local function escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

function Feed.init()
	local screen = Windows.screen()
	toastHolder = Kit.new("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(520, 300),
		Position = UDim2.new(0.5, 0, 1, -150),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = 50,
		Parent = screen,
	})
	local layout = Kit.list(toastHolder, 4, false, Enum.HorizontalAlignment.Center)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom

	announceHolder = Kit.new("Frame", {
		Name = "Announcements",
		BackgroundTransparency = 1,
		Size = UDim2.new(0.9, 0, 0, 260),
		Position = UDim2.new(0.5, 0, 0, 70),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 50,
		Parent = screen,
	})
	Kit.list(announceHolder, 2, false, Enum.HorizontalAlignment.Center)

	alarmFrame = Kit.panel({
		Name = "Alarm",
		Size = UDim2.fromOffset(560, 64),
		Position = UDim2.new(0.5, 0, 0, 14),
		Anchor = Vector2.new(0.5, 0),
		Color = Kit.Colors.Red,
		Visible = false,
		Z = 60,
		Parent = screen,
	})
	Kit.label({ Name = "Text", Text = "", Size = UDim2.new(1, -20, 1, -10), Position = UDim2.fromOffset(10, 5), Z = 61, Parent = alarmFrame })
	alarmSound = Instance.new("Sound")
	alarmSound.SoundId = "rbxasset://sounds/action_falling.mp3"
	alarmSound.Volume = 0.6
	alarmSound.Parent = SoundService
end

function Feed.notify(text: string, kind: string?)
	if not toastHolder then
		return
	end
	local color = KIND_COLORS[kind or "info"] or KIND_COLORS.info
	local label = Kit.label({
		Text = escape(text),
		Color = color,
		Size = UDim2.new(1, 0, 0, 34),
		Z = 51,
		StrokeThickness = 2.5,
		Parent = toastHolder,
	})
	label.TextTransparency = 1
	Kit.tween(label, 0.15, { TextTransparency = 0 })
	-- keep the stack short
	local labels = {}
	for _, child in ipairs(toastHolder:GetChildren()) do
		if child:IsA("TextLabel") then
			table.insert(labels, child)
		end
	end
	if #labels > 5 then
		labels[1]:Destroy()
	end
	task.delay(3.5, function()
		if label.Parent then
			Kit.tween(label, 0.4, { TextTransparency = 1 })
			Debris:AddItem(label, 0.45)
		end
	end)
end

-- lines = { { {Text, Color?, Verified?}, ... }, ... }
function Feed.announce(lines)
	if not announceHolder then
		return
	end
	for _, segments in ipairs(lines) do
		local parts = {}
		for _, seg in ipairs(segments) do
			local text = escape(seg.Text or "")
			if seg.Color then
				text = string.format('<font color="%s">%s</font>', seg.Color, text)
			end
			if seg.Verified then
				text ..= ' <font color="#4FB4FF">✔</font>'
			end
			table.insert(parts, text)
		end
		local label = Kit.label({
			Text = table.concat(parts),
			Size = UDim2.new(1, 0, 0, 46),
			StrokeThickness = 3.5,
			Z = 51,
			Parent = announceHolder,
		})
		local scale = Kit.new("UIScale", { Scale = 0.3, Parent = label })
		Kit.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		task.delay(6, function()
			if label.Parent then
				Kit.tween(label, 0.5, { TextTransparency = 1 })
				local stroke = label:FindFirstChildOfClass("UIStroke")
				if stroke then
					Kit.tween(stroke, 0.5, { Transparency = 1 })
				end
				Debris:AddItem(label, 0.55)
			end
		end)
	end
	local count = 0
	for _, child in ipairs(announceHolder:GetChildren()) do
		if child:IsA("TextLabel") then
			count += 1
		end
	end
	while count > 5 do
		for _, child in ipairs(announceHolder:GetChildren()) do
			if child:IsA("TextLabel") then
				child:Destroy()
				count -= 1
				break
			end
		end
	end
end

function Feed.alarm(info)
	if not alarmFrame then
		return
	end
	local text = alarmFrame:FindFirstChild("Text")
	if info.Kind == "Robbed" then
		text.Text = "🚨 " .. escape(info.Thief) .. " is stealing your " .. escape(info.Species) .. "! Catch them! 🚨"
		alarmFrame.BackgroundColor3 = Kit.Colors.Red
		alarmFrame.Visible = true
		SoundService:PlayLocalSound(alarmSound)
		local token = {}
		Feed._alarmToken = token
		task.spawn(function()
			local on = true
			while Feed._alarmToken == token and alarmFrame.Visible do
				on = not on
				alarmFrame.BackgroundColor3 = on and Kit.Colors.Red or Kit.Colors.RedDark
				task.wait(0.35)
			end
		end)
		task.delay(20, function()
			if Feed._alarmToken == token then
				alarmFrame.Visible = false
			end
		end)
	else
		Feed._alarmToken = nil
		alarmFrame.Visible = false
	end
end

return Feed
