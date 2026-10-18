--[[
	Effects (ModuleScript)
	Location: ReplicatedStorage/UI/Effects
	Depends on: UI/Theme

	2D juice for the interface: particle bursts, floating numbers, shockwave
	rings, screen shake and flashes. Particles are pooled frames (Roblox
	ParticleEmitters only work in 3D). Every effect respects Reduced Motion.
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local Effects = {}

local rng = Random.new()
local particlePool: { Frame } = {}
local floaterPool: { TextLabel } = {}
local MAX_POOL = 120

local function takeParticle(): Frame
	local p = table.remove(particlePool)
	if p then
		return p
	end
	local frame = Instance.new("Frame")
	frame.Name = "Particle"
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 2)
	corner.Parent = frame
	return frame
end

local function releaseParticle(p: Frame)
	p.Parent = nil
	if #particlePool < MAX_POOL then
		table.insert(particlePool, p)
	else
		p:Destroy()
	end
end

-- Burst of square sparks flying outward from a point (offset pixels in parent space).
function Effects.burst(parent: GuiObject, position: Vector2, color: Color3, count: number?, spread: number?)
	if Theme.ReducedMotion then
		return
	end
	local n = count or 10
	for _ = 1, n do
		local p = takeParticle()
		local size = rng:NextInteger(5, 11)
		p.Size = UDim2.fromOffset(size, size)
		p.Position = UDim2.fromOffset(position.X, position.Y)
		p.Rotation = rng:NextInteger(0, 90)
		p.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), rng:NextNumber(0, 0.4))
		p.BackgroundTransparency = 0
		p.ZIndex = 40
		p.Parent = parent
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(50, spread or 140)
		local target = position + Vector2.new(math.cos(angle), math.sin(angle)) * distance
		local duration = rng:NextNumber(0.35, 0.7)
		local tween = TweenService:Create(p, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(target.X, target.Y),
			Rotation = p.Rotation + rng:NextInteger(90, 270),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(2, 2),
		})
		tween.Completed:Connect(function()
			releaseParticle(p)
		end)
		tween:Play()
	end
end

-- Expanding ring centred on a point.
function Effects.ring(parent: GuiObject, position: Vector2, color: Color3, size: number?)
	if Theme.ReducedMotion then
		return
	end
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromOffset(position.X, position.Y)
	ring.Size = UDim2.fromOffset(40, 40)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 35
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 4
	stroke.Parent = ring
	ring.Parent = parent
	local final = size or 320
	local info = TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	TweenService:Create(ring, info, { Size = UDim2.fromOffset(final, final) }):Play()
	local fade = TweenService:Create(stroke, info, { Transparency = 1, Thickness = 1 })
	fade.Completed:Connect(function()
		ring:Destroy()
	end)
	fade:Play()
end

local function takeFloater(): TextLabel
	local f = table.remove(floaterPool)
	if f then
		return f
	end
	local label = Instance.new("TextLabel")
	label.Name = "Floater"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Size = UDim2.fromOffset(240, 40)
	label.Font = Theme.Fonts.Heading
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.35
	label.RichText = false
	return label
end

local function releaseFloater(f: TextLabel)
	f.Parent = nil
	if #floaterPool < MAX_POOL then
		table.insert(floaterPool, f)
	else
		f:Destroy()
	end
end

-- Floating text that rises and fades. opts: { Size, Rise, Duration, Font }
function Effects.floatText(parent: GuiObject, position: Vector2, text: string, color: Color3, opts: { [string]: any }?)
	local o = opts or {}
	local label = takeFloater()
	label.Text = text
	label.TextColor3 = color
	label.TextSize = o.Size or 26
	label.Font = o.Font or Theme.Fonts.Heading
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0.35
	label.Rotation = if Theme.ReducedMotion then 0 else rng:NextNumber(-6, 6)
	label.Position = UDim2.fromOffset(position.X, position.Y)
	label.ZIndex = 45
	label.Parent = parent
	local rise = o.Rise or 90
	local duration = o.Duration or 0.9
	local goal = {
		Position = UDim2.fromOffset(position.X + rng:NextNumber(-20, 20), position.Y - rise),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}
	local tween = TweenService:Create(label, TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), goal)
	tween.Completed:Connect(function()
		releaseFloater(label)
	end)
	tween:Play()
end

-- Shakes a GuiObject around its current position.
local shaking: { [GuiObject]: boolean } = {}
function Effects.shake(target: GuiObject, intensity: number?, duration: number?)
	if Theme.ReducedMotion or shaking[target] then
		return
	end
	shaking[target] = true
	local origin = target.Position
	local amount = intensity or 6
	local stop = os.clock() + (duration or 0.18)
	task.spawn(function()
		while os.clock() < stop do
			target.Position = origin + UDim2.fromOffset(rng:NextNumber(-amount, amount), rng:NextNumber(-amount, amount))
			task.wait(1 / 60)
		end
		target.Position = origin
		shaking[target] = nil
	end)
end

-- Full-screen colour flash inside parent.
function Effects.flash(parent: GuiObject, color: Color3, strength: number?)
	if Theme.ReducedMotion then
		return
	end
	local frame = Instance.new("Frame")
	frame.Name = "Flash"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 1 - (strength or 0.35)
	frame.BorderSizePixel = 0
	frame.ZIndex = 60
	frame.Parent = parent
	local tween = TweenService:Create(frame, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
	tween.Completed:Connect(function()
		frame:Destroy()
	end)
	tween:Play()
end

-- Slowly rotating light rays behind a reveal.
function Effects.rays(parent: GuiObject, color: Color3, size: number): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Rays"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(size, size)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 2
	for i = 0, 5 do
		local ray = Instance.new("Frame")
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.new(0, size * 0.12, 1, 0)
		ray.Rotation = i * 30
		ray.BackgroundColor3 = color
		ray.BorderSizePixel = 0
		ray.ZIndex = 2
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = ray
		ray.Parent = holder
	end
	holder.Parent = parent
	if not Theme.ReducedMotion then
		task.spawn(function()
			while holder.Parent do
				holder.Rotation = (holder.Rotation + 0.4) % 360
				task.wait(1 / 60)
			end
		end)
	end
	return holder
end

return Effects
