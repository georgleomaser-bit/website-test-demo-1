--[[
	Meldungen (Toasts), große Texte in der Mitte, Fenster-Hinweise,
	Bildschirm-Blitz und Konfetti.
]]

local Debris = game:GetService("Debris")

local Ui = require(script.Parent.Ui)

local Popups = {}

Popups.Root = nil :: Frame?

local toastHolder: Frame
local centerHolder: Frame
local toasts: { Frame } = {}

local STYLE_COLORS = {
	info = Color3.fromRGB(0, 120, 215),
	success = Color3.fromRGB(0, 160, 60),
	error = Color3.fromRGB(200, 40, 40),
	gold = Color3.fromRGB(220, 160, 0),
	event = Color3.fromRGB(140, 60, 220),
}

function Popups.Init(root: Frame)
	Popups.Root = root
	toastHolder = Ui.Frame(root, {
		Name = "Toasts",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 250),
		Size = UDim2.fromOffset(380, 400),
		BackgroundTransparency = 1,
		ZIndex = 40,
	})
	local layout = Ui.List(toastHolder, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	centerHolder = Ui.Frame(root, {
		Name = "Center",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 45,
	})
end

local counter = 0
function Popups.Toast(text: string, style: string?)
	counter += 1
	local color = STYLE_COLORS[style or "info"] or STYLE_COLORS.info
	local frame = Ui.Frame(toastHolder, {
		LayoutOrder = counter,
		Size = UDim2.fromOffset(380, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = color,
		BackgroundTransparency = 0.05,
		ZIndex = 41,
	})
	Ui.Corner(frame, 8)
	Ui.Stroke(frame, 2, Color3.new(0, 0, 0), 0.4)
	Ui.Padding(frame, 8)
	local label = Ui.Label(frame, text, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0.4,
		ZIndex = 42,
	})
	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = frame
	Ui.Tween(scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
	table.insert(toasts, frame)
	while #toasts > 5 do
		local old = table.remove(toasts, 1)
		if old then
			old:Destroy()
		end
	end
	task.delay(4.5, function()
		if not frame.Parent then
			return
		end
		Ui.Tween(frame, 0.4, { BackgroundTransparency = 1 })
		Ui.Tween(label, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
		task.wait(0.45)
		local index = table.find(toasts, frame)
		if index then
			table.remove(toasts, index)
		end
		frame:Destroy()
	end)
end

-- Großer Text in der Mitte, der nach oben schwebt (z. B. "+$1.2M")
function Popups.Big(text: string, color: Color3?, subText: string?)
	local holder = Ui.Frame(centerHolder, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(700, 130),
		BackgroundTransparency = 1,
		ZIndex = 46,
	})
	local label = Ui.Label(holder, text, {
		Size = UDim2.new(1, 0, 0, 80),
		TextSize = 64,
		TextColor3 = color or Ui.Colors.Gold,
		TextStrokeTransparency = 0,
		ZIndex = 47,
	})
	local sub
	if subText then
		sub = Ui.Label(holder, subText, {
			Size = UDim2.new(1, 0, 0, 40),
			Position = UDim2.fromOffset(0, 80),
			TextSize = 32,
			TextStrokeTransparency = 0,
			ZIndex = 47,
		})
	end
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = holder
	Ui.Tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(1.6, function()
		Ui.Tween(holder, 0.8, { Position = UDim2.fromScale(0.5, 0.3) })
		Ui.Tween(label, 0.8, { TextTransparency = 1, TextStrokeTransparency = 1 })
		if sub then
			Ui.Tween(sub, 0.8, { TextTransparency = 1, TextStrokeTransparency = 1 })
		end
	end)
	Debris:AddItem(holder, 2.6)
end

function Popups.Flash(color: Color3, strength: number?)
	local flash = Ui.Frame(centerHolder, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = 1 - (strength or 0.6),
		ZIndex = 44,
	})
	Ui.Tween(flash, 0.9, { BackgroundTransparency = 1 })
	Debris:AddItem(flash, 1)
end

function Popups.Confetti(amount: number?)
	local colors = { Ui.Colors.Red, Ui.Colors.Yellow, Ui.Colors.Green, Ui.Colors.Blue, Ui.Colors.Pink, Ui.Colors.Orange }
	local rng = Random.new()
	for _ = 1, amount or 40 do
		local piece = Ui.Frame(centerHolder, {
			Size = UDim2.fromOffset(rng:NextInteger(8, 14), rng:NextInteger(12, 20)),
			Position = UDim2.new(rng:NextNumber(0.1, 0.9), 0, -0.05, 0),
			Rotation = rng:NextNumber(0, 360),
			BackgroundColor3 = colors[rng:NextInteger(1, #colors)],
			ZIndex = 48,
		})
		local time = rng:NextNumber(1.4, 2.4)
		Ui.Tween(piece, time, {
			Position = UDim2.new(piece.Position.X.Scale + rng:NextNumber(-0.15, 0.15), 0, 1.05, 0),
			Rotation = piece.Rotation + rng:NextNumber(-360, 360),
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(piece, time + 0.1)
	end
end

-- Fenster mit Text und einem Knopf (z. B. Offline-Geld)
function Popups.Modal(title: string, body: string, buttonText: string, color: Color3, onClose: (() -> ())?)
	local overlay = Ui.Frame(centerHolder, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		ZIndex = 50,
		Active = true,
	})
	local box = Ui.Frame(overlay, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(520, 300),
		BackgroundColor3 = Ui.Colors.Panel,
		ZIndex = 51,
	})
	Ui.Corner(box, 14)
	Ui.Stroke(box, 3, color, 0)
	local bar = Ui.Frame(box, { Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = color, ZIndex = 52 })
	Ui.Corner(bar, 14)
	Ui.Frame(bar, { Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -14), BackgroundColor3 = color, ZIndex = 52 })
	Ui.Label(bar, title, { Size = UDim2.fromScale(1, 1), TextSize = 30, TextStrokeTransparency = 0.3, ZIndex = 53 })
	Ui.Label(box, body, {
		Size = UDim2.new(1, -40, 0, 140),
		Position = UDim2.fromOffset(20, 66),
		TextSize = 24,
		ZIndex = 52,
	})
	local scale = Instance.new("UIScale")
	scale.Scale = 0.7
	scale.Parent = box
	Ui.Tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	local button = Ui.Button(box, buttonText, Ui.Colors.Green, {
		Size = UDim2.fromOffset(240, 56),
		Position = UDim2.new(0.5, -120, 1, -72),
		TextSize = 28,
		ZIndex = 53,
	}, function()
		overlay:Destroy()
		if onClose then
			onClose()
		end
	end)
	Ui.Stroke(button, 3, Color3.new(0, 0, 0), 0.3)
	return overlay
end

return Popups
