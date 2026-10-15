-- Always-visible HUD laid out like the reference: currency bottom left with the
-- multiplier, boost timers above it, Shop/Index buttons and Slow Mode on the left,
-- more buttons on the right, a hotbar at the bottom and event/carry info at the top.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Format = require(Shared.Format)
local Game = require(Shared.Config.Game)
local Rewards = require(Shared.Config.Rewards)

local Kit = require(script.Parent.Kit)
local Windows = require(script.Parent.Windows)
local Feed = require(script.Parent.Feed)
local State = require(script.Parent.Parent.State)

local HUD = {}

local player = Players.LocalPlayer
local refs = {}

local function sideButton(parent, order: number, text: string, color: Color3, onClick)
	return Kit.button({
		Text = text,
		Color = color,
		Size = UDim2.fromOffset(150, 50),
		Order = order,
		Parent = parent,
		MaxTextSize = 26,
	}, onClick)
end

local function iconButton(parent, order: number, icon: string, caption: string, color: Color3, onClick)
	local b = Kit.button({
		Text = icon,
		Color = color,
		Size = UDim2.fromOffset(56, 56),
		Order = order,
		Radius = 16,
		Parent = parent,
		MaxTextSize = 30,
	}, onClick)
	Kit.label({
		Text = caption,
		Size = UDim2.new(1, 16, 0, 18),
		Position = UDim2.new(0.5, 0, 1, 2),
		Anchor = Vector2.new(0.5, 0),
		Z = 5,
		Parent = b.Holder,
	})
	return b
end

local function throwBait()
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local target
	if UserInputService.MouseEnabled and not UserInputService.TouchEnabled then
		local mouse = player:GetMouse()
		target = mouse.Hit and mouse.Hit.Position
	end
	if not target then
		target = hrp.Position + hrp.CFrame.LookVector * 40
	end
	local ok, msg = State.action("ThrowBait", target)
	if msg then
		Feed.notify(msg, ok and "success" or "error")
	end
end

local function toggleMount()
	if not State.ready() then
		return
	end
	if State.Data.Mount ~= "" then
		local ok, msg = State.action("Mount", "")
		if msg then
			Feed.notify(msg, ok and "info" or "error")
		end
	else
		-- ride the fastest animal you own
		local Formulas = require(Shared.Formulas)
		local best, bestMult = nil, 0
		for _, a in ipairs(State.Data.Animals) do
			local m = Formulas.mountMult(a)
			if m > bestMult then
				best, bestMult = a, m
			end
		end
		if not best then
			Feed.notify("Capture an animal first!", "error")
			return
		end
		local ok, msg = State.action("Mount", best.Uid)
		if msg then
			Feed.notify(msg, ok and "success" or "error")
		end
	end
end

local function hotbarSlot(parent, order: number, key: string, icon: string, caption: string, onClick)
	local slot = Kit.new("TextButton", {
		Name = "Slot" .. order,
		AutoButtonColor = true,
		BackgroundColor3 = Color3.fromRGB(30, 30, 40),
		BackgroundTransparency = 0.35,
		Size = UDim2.fromOffset(70, 70),
		LayoutOrder = order,
		Text = "",
		Parent = parent,
	})
	Kit.corner(slot, 10)
	Kit.stroke(slot, 2, Color3.fromRGB(10, 10, 15), Enum.ApplyStrokeMode.Border)
	Kit.label({ Text = icon, Size = UDim2.new(1, 0, 0.62, 0), Position = UDim2.fromScale(0, 0.05), Stroke = false, Parent = slot })
	local cap = Kit.label({ Name = "Caption", Text = caption, Size = UDim2.new(1, -4, 0.3, 0), Position = UDim2.new(0, 2, 0.68, 0), Parent = slot })
	Kit.label({ Text = key, Size = UDim2.fromOffset(16, 16), Position = UDim2.fromOffset(4, 2), XAlign = Enum.TextXAlignment.Left, Parent = slot })
	slot.Activated:Connect(function()
		Kit.playClick()
		onClick()
	end)
	return slot, cap
end

function HUD.init()
	local screen = Windows.screen()

	-- bottom left: boosts + speed + cash ------------------------------------------------
	local stats = Kit.new("Frame", {
		Name = "Stats",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(420, 190),
		Position = UDim2.new(0, 12, 1, -12),
		AnchorPoint = Vector2.new(0, 1),
		Parent = screen,
	})
	local statsLayout = Kit.list(stats, 0)
	statsLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	refs.Boosts = Kit.label({ Name = "Boosts", Text = "", Size = UDim2.new(1, 0, 0, 78), XAlign = Enum.TextXAlignment.Left, YAlign = Enum.TextYAlignment.Bottom, Order = 1, Parent = stats, TextSize = 22 })
	refs.Boosts.TextScaled = false
	refs.Speed = Kit.label({ Name = "Speed", Text = "⚡ 0", Size = UDim2.new(1, 0, 0, 44), XAlign = Enum.TextXAlignment.Left, Color = Color3.fromRGB(255, 236, 120), Order = 2, StrokeThickness = 3.5, Parent = stats })
	refs.Cash = Kit.label({ Name = "Cash", Text = "💵 $0", Size = UDim2.new(1, 0, 0, 48), XAlign = Enum.TextXAlignment.Left, Color = Kit.Colors.Money, Order = 3, StrokeThickness = 3.5, Parent = stats })
	refs.Friend = Kit.label({ Name = "Friend", Text = "", Size = UDim2.new(1, 0, 0, 22), XAlign = Enum.TextXAlignment.Left, Color = Color3.fromRGB(255, 255, 255), Order = 4, Parent = stats })

	-- left buttons -----------------------------------------------------------------------
	local left = Kit.new("Frame", {
		Name = "LeftButtons",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(160, 300),
		Position = UDim2.new(0, 12, 0.5, -40),
		AnchorPoint = Vector2.new(0, 0.5),
		Parent = screen,
	})
	Kit.list(left, 12)
	sideButton(left, 1, "🛒 Shop", Kit.Colors.Green, function()
		Windows.open("Shop")
	end)
	sideButton(left, 2, "📖 Index", Kit.Colors.Blue, function()
		Windows.open("Index")
	end)
	sideButton(left, 3, "🐾 Pets", Kit.Colors.Orange, function()
		Windows.open("Pets")
	end)
	-- slow mode switch
	local slow = Kit.new("TextButton", {
		Name = "SlowMode",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(160, 36),
		Text = "",
		LayoutOrder = 4,
		Parent = left,
	})
	local track = Kit.panel({ Size = UDim2.fromOffset(60, 30), Position = UDim2.fromOffset(0, 3), Color = Kit.Colors.Gray, Radius = 15, Parent = slow })
	local knob = Kit.panel({ Size = UDim2.fromOffset(24, 24), Position = UDim2.fromOffset(3, 3), Color = Kit.Colors.White, Radius = 12, StrokeThickness = 2, Parent = track })
	Kit.label({ Text = "Slow Mode", Size = UDim2.new(1, -66, 1, 0), Position = UDim2.fromOffset(66, 0), XAlign = Enum.TextXAlignment.Left, Parent = slow, MaxTextSize = 22 })
	refs.SlowTrack = track
	refs.SlowKnob = knob
	slow.Activated:Connect(function()
		Kit.playClick()
		if State.ready() then
			State.action("SetSlowMode", not State.Data.SlowMode)
		end
	end)

	-- right buttons ----------------------------------------------------------------------
	-- one column of square icon buttons on the right edge, like the reference
	local right = Kit.new("Frame", {
		Name = "RightButtons",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(56, 560),
		Position = UDim2.new(1, -14, 0.5, 10),
		AnchorPoint = Vector2.new(1, 0.5),
		Parent = screen,
	})
	local rightLayout = Kit.list(right, 26)
	rightLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	iconButton(right, 1, "🥚", "Nests", Kit.Colors.Yellow, function()
		Windows.show("Pets")
		local pets = Windows.get("Pets")
		if pets and pets.showTab then
			pets.showTab("Nests")
		end
	end)
	iconButton(right, 2, "📋", "Tasks", Kit.Colors.Purple, function()
		Windows.open("Tasks")
	end)
	refs.RebirthButton = iconButton(right, 3, "🔁", "Rebirth", Kit.Colors.Pink, function()
		Windows.show("Shop")
		local shop = Windows.get("Shop")
		if shop and shop.showTab then
			shop.showTab("Rebirth")
		end
	end)
	refs.GiftButton = iconButton(right, 4, "🎁", "Gifts", Kit.Colors.Red, function()
		Windows.open("Gifts")
	end)
	iconButton(right, 5, "💎", "Robux", Kit.Colors.Blue, function()
		Windows.show("Shop")
		local shop = Windows.get("Shop")
		if shop and shop.showTab then
			shop.showTab("Robux")
		end
	end)
	iconButton(right, 6, "🔑", "Codes", Kit.Colors.Gray, function()
		Windows.open("Codes")
	end)
	refs.AdminButton = iconButton(right, 7, "🛠", "Admin", Color3.fromRGB(60, 60, 70), function()
		Windows.open("Admin")
	end)
	refs.AdminButton.Holder.Visible = false

	-- top: event + carrying info ---------------------------------------------------------
	refs.Lair = Kit.label({
		Name = "Lair",
		Text = "",
		Size = UDim2.fromOffset(460, 30),
		Position = UDim2.new(0.5, 0, 0, 8),
		Anchor = Vector2.new(0.5, 0),
		Color = Color3.fromRGB(255, 150, 70),
		Parent = screen,
	})
	refs.Carry = Kit.panel({
		Name = "Carry",
		Size = UDim2.fromOffset(440, 58),
		Position = UDim2.new(0.5, 0, 0, 68),
		Anchor = Vector2.new(0.5, 0),
		Color = Kit.Colors.Panel,
		Transparency = 0.15,
		Visible = false,
		Parent = screen,
	})
	refs.CarryText = Kit.label({ Text = "", Size = UDim2.new(1, -20, 1, -8), Position = UDim2.fromOffset(10, 4), Parent = refs.Carry })
	refs.Expedition = Kit.label({
		Name = "Expedition",
		Text = "",
		Size = UDim2.fromOffset(300, 22),
		Position = UDim2.new(0.5, 0, 0, 40),
		Anchor = Vector2.new(0.5, 0),
		Parent = screen,
	})

	-- hotbar -----------------------------------------------------------------------------
	local hotbar = Kit.new("Frame", {
		Name = "Hotbar",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(4 * 78, 74),
		Position = UDim2.new(0.5, 0, 1, -10),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = screen,
	})
	Kit.list(hotbar, 8, true, Enum.HorizontalAlignment.Center)
	local _, baitCap = hotbarSlot(hotbar, 1, "1", "🪔", "Bait", throwBait)
	local _, rideCap = hotbarSlot(hotbar, 2, "2", "🐎", "Ride", toggleMount)
	hotbarSlot(hotbar, 3, "3", "⬇️", "Drop", function()
		local ok, msg = State.action("Drop")
		if not ok and msg then
			Feed.notify(msg, "error")
		end
	end)
	local _, lockCap = hotbarSlot(hotbar, 4, "4", "🔒", "Lock", function()
		local ok, msg = State.action("LockBase")
		if not ok and msg then
			Feed.notify(msg, "error")
		end
	end)
	refs.BaitCap = baitCap
	refs.RideCap = rideCap
	refs.LockCap = lockCap

	-- keyboard shortcuts
	ContextActionService:BindAction("CAP_Hotbar", function(_, inputState, input)
		if inputState ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if UserInputService:GetFocusedTextBox() then
			return Enum.ContextActionResult.Pass
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.One or key == Enum.KeyCode.G then
			throwBait()
		elseif key == Enum.KeyCode.Two or key == Enum.KeyCode.R then
			toggleMount()
		elseif key == Enum.KeyCode.Three or key == Enum.KeyCode.Q then
			State.action("Drop")
		elseif key == Enum.KeyCode.Four then
			State.action("LockBase")
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.G, Enum.KeyCode.R, Enum.KeyCode.Q)

	-- the default backpack hotbar would overlap ours
	pcall(function()
		game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)

	State.StatsChanged:Connect(HUD.refreshStats)
	State.Changed:Connect(HUD.refresh)
	task.spawn(function()
		while true do
			task.wait(1)
			HUD.tick()
		end
	end)
end

function HUD.refreshStats()
	if not State.ready() then
		return
	end
	local d = State.Derived
	refs.Speed.Text = string.format("⚡ %s <font size=\"30\">(%s)</font>", Format.number(State.Data.Speed, true), Format.multiplier(d.TrainingMult))
	refs.Cash.Text = string.format("💵 $%s", Format.number(State.Data.Cash, true))
end

function HUD.refresh()
	if not State.ready() then
		return
	end
	local data = State.Data
	local d = State.Derived
	HUD.refreshStats()
	refs.AdminButton.Holder.Visible = d.IsAdmin == true
	refs.BaitCap.Text = "x" .. data.Bait
	refs.RideCap.Text = data.Mount ~= "" and "Get off" or "Ride"
	local on = data.SlowMode
	refs.SlowTrack.BackgroundColor3 = on and Kit.Colors.Green or Kit.Colors.Gray
	Kit.tween(refs.SlowKnob, 0.12, { Position = on and UDim2.fromOffset(33, 3) or UDim2.fromOffset(3, 3) })
	local carry = d.Carrying
	refs.Carry.Visible = carry ~= nil
	if carry then
		local aura = Game.Auras[carry.Aura or 1]
		local auraText = (carry.Aura or 1) > 1 and string.format(' · <font color="%s">%s aura</font>', Kit.hex(aura.Color), aura.Name) or ""
		local verb = carry.Kind == "Stolen" and "Stealing" or "Carrying"
		refs.CarryText.Text = string.format("%s %s%s\n<font size=\"16\">Run back to your base! (Q to drop)</font>", verb, carry.Name or "", auraText)
	end
	local exp = data.Expedition
	local dots = {}
	for i = 1, 4 do
		table.insert(dots, exp.Zones[i] and '<font color="#7CFF6B">●</font>' or '<font color="#777777">●</font>')
	end
	refs.Expedition.Text = "Expedition " .. (exp.Level + 1) .. "  " .. table.concat(dots, " ")
	HUD.tick()
end

function HUD.tick()
	if not State.ready() then
		return
	end
	local data = State.Data
	local d = State.Derived
	local now = State.now()
	local lines = {}
	local names = { Training = "X2 Speed", Cash = "X2 Cash", Luck = "X2 Luck" }
	for _, boost in ipairs(Game.BoostTypes) do
		local left = (data.Boosts[boost] or 0) - now
		if left > 0 then
			table.insert(lines, string.format('<font color="#7CFF6B">%s (%s)</font>', names[boost], Format.time(left)))
		end
	end
	if d.ServerLuckUntil > now then
		table.insert(lines, string.format('<font color="#7CFFEA">Server Luck x2 (%s)</font>', Format.time(d.ServerLuckUntil - now)))
	end
	refs.Friend.Text = string.format("Friend Boost: +%d%%", math.floor(d.FriendBoost * 100 + 0.5))
	refs.Boosts.Text = table.concat(lines, "\n")

	if d.LairOpenUntil > now then
		refs.Lair.Text = "🐉 DRAGON LAIR OPEN! " .. Format.time(d.LairOpenUntil - now) .. " (portal at the end of the hub)"
	elseif d.LairNextOpen > now then
		refs.Lair.Text = "🐉 Dragon Lair opens in " .. Format.time(d.LairNextOpen - now)
	else
		refs.Lair.Text = ""
	end

	-- playtime gift countdown on the button
	local elapsed = now - d.SessionStart
	local nextText = "Gifts"
	local ready = false
	for i, gift in ipairs(Rewards.Playtime) do
		if not d.PlaytimeClaimed[tostring(i)] then
			local left = gift.Minutes * 60 - elapsed
			if left <= 0 then
				ready = true
				nextText = "CLAIM!"
			else
				nextText = Format.time(left)
			end
			break
		end
	end
	local caption = refs.GiftButton.Holder:FindFirstChild("Label")
	if caption then
		caption.Text = nextText
		caption.TextColor3 = ready and Kit.Colors.Yellow or Kit.Colors.White
	end

	if d.LockedUntil > now then
		refs.LockCap.Text = (d.LockedUntil - now) .. "s"
	elseif d.LockCooldownUntil > now then
		refs.LockCap.Text = "⏳" .. (d.LockCooldownUntil - now)
	else
		refs.LockCap.Text = "Lock"
	end
	local canRebirth = data.Cash >= d.RebirthCost
	local rb = refs.RebirthButton.Holder:FindFirstChild("Label")
	if rb then
		rb.TextColor3 = canRebirth and Kit.Colors.Yellow or Kit.Colors.White
		rb.Text = canRebirth and "REBIRTH!" or "Rebirth"
	end
end

return HUD
