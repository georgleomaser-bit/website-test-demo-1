-- Client-only visuals: running on treadmills, riding pose, rainbow animals, floating
-- "+$477M" income popups, hiding prompts that aren't for you, the hatch reveal,
-- screen flashes and the VIP chat tag.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")
local TextChatService = game:GetService("TextChatService")
local Debris = game:GetService("Debris")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Format)
local Animals = require(Shared.Config.Animals)
local Game = require(Shared.Config.Game)

local Kit = require(script.Parent.UI.Kit)
local Windows = require(script.Parent.UI.Windows)
local Feed = require(script.Parent.UI.Feed)
local Preview = require(script.Parent.UI.Preview)

local Effects = {}

local player = Players.LocalPlayer
local runTrack, sitTrack
local flash

local function sound(id: string, volume: number?)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.5
	s.Parent = SoundService
	SoundService:PlayLocalSound(s)
	Debris:AddItem(s, 5)
end

local function animationFrom(character: Model, folderName: string): Animation?
	local animate = character:FindFirstChild("Animate")
	local folder = animate and animate:FindFirstChild(folderName)
	return folder and folder:FindFirstChildOfClass("Animation")
end

local function loadTrack(character: Model, folderName: string, priority: Enum.AnimationPriority)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local animation = animationFrom(character, folderName)
	if not animator or not animation then
		return nil
	end
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok then
		return nil
	end
	track.Looped = true
	track.Priority = priority
	return track
end

local function onCharacter(character: Model)
	runTrack = nil
	sitTrack = nil
	character:WaitForChild("Humanoid", 10)
	task.wait(1)
	runTrack = loadTrack(character, "run", Enum.AnimationPriority.Action)
	sitTrack = loadTrack(character, "sit", Enum.AnimationPriority.Action2)
end

local function updateTracks()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local onTreadmill = player:GetAttribute("Treadmill") ~= nil
	local idle = humanoid.MoveDirection.Magnitude < 0.1
	if runTrack then
		if onTreadmill and idle and not runTrack.IsPlaying then
			runTrack:Play(0.15)
			runTrack:AdjustSpeed(1.4)
		elseif (not onTreadmill or not idle) and runTrack.IsPlaying then
			runTrack:Stop(0.15)
		end
	end
	if sitTrack then
		local mounted = player:GetAttribute("Mounted") == true
		if mounted and not sitTrack.IsPlaying then
			sitTrack:Play(0.2)
		elseif not mounted and sitTrack.IsPlaying then
			sitTrack:Stop(0.2)
		end
	end
end

-- belt stripes of your own treadmills scroll while you train
local stripeOffset = 0
local function animateBelts(dt: number)
	local plotIndex = player:GetAttribute("Plot")
	local tier = player:GetAttribute("Treadmill")
	if not plotIndex or tier == nil then
		return
	end
	local map = Workspace:FindFirstChild("Map")
	local plot = map and map:FindFirstChild("Plots") and map.Plots:FindFirstChild("Plot" .. plotIndex)
	local tm = plot and plot:FindFirstChild("Treadmills") and plot.Treadmills:FindFirstChild("Treadmill" .. tier)
	if not tm then
		return
	end
	local belt = tm:FindFirstChild("Belt")
	if not belt then
		return
	end
	stripeOffset = (stripeOffset + dt * 12) % 2
	local i = 0
	for _, stripe in ipairs(tm:GetChildren()) do
		if stripe.Name == "Stripe" then
			local z = -4.5 + i * 2 + stripeOffset
			if z > 5.5 then
				z -= 12
			end
			stripe.CFrame = belt.CFrame * CFrame.new(0, 0.27, z)
			i += 1
		end
	end
end

local hue = 0
local function animateRainbow(dt: number)
	hue = (hue + dt * 0.25) % 1
	for _, model in ipairs(CollectionService:GetTagged("RainbowAnimal")) do
		local i = 0
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") and p.Name ~= "Root" and p.Name ~= "Eye" and p.Name ~= "EyeWhite" then
				i += 1
				p.Color = Color3.fromHSV((hue + i * 0.03) % 1, 0.7, 1)
			end
		end
	end
end

local function popup(adornee: BasePart, text: string, height: number)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 50)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	gui.Adornee = adornee
	local label = Kit.label({ Text = text, Color = Kit.Colors.Money, StrokeThickness = 3, Parent = gui })
	gui.Parent = adornee
	Kit.tween(gui, 1.4, { StudsOffsetWorldSpace = Vector3.new(0, height + 6, 0) })
	task.delay(0.9, function()
		Kit.tween(label, 0.5, { TextTransparency = 1 })
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			Kit.tween(stroke, 0.5, { Transparency = 1 })
		end
	end)
	Debris:AddItem(gui, 1.5)
end

local POPUP_SECONDS = 3
local function incomePopups()
	local plotIndex = player:GetAttribute("Plot")
	local map = Workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	if not plots then
		return
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	for _, plot in ipairs(plots:GetChildren()) do
		local pen = plot:FindFirstChild("PenAnimals")
		local mine = plot.Name == ("Plot" .. tostring(plotIndex))
		-- your own base always, other bases only while you stand in them
		if pen and (mine or (hrp and (plot:GetPivot().Position - hrp.Position).Magnitude < 100)) then
			for _, model in ipairs(pen:GetChildren()) do
				local income = model:GetAttribute("Income")
				local root = model.PrimaryPart
				if income and income > 0 and root then
					task.delay(math.random() * POPUP_SECONDS, function()
						if root.Parent then
							popup(root, "+$" .. Format.number(income * POPUP_SECONDS), (model:GetAttribute("Height") or 6) + 1)
						end
					end)
				end
			end
		end
	end
end

-- Prompts for other players' bases (buy, lock, hatch) and your own steal prompts are hidden.
local function filterPrompts()
	local myId = player.UserId
	local plotIndex = player:GetAttribute("Plot")
	local map = Workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	if not plots or not plotIndex then
		return -- no base yet: don't touch anything, or our own prompts would be switched off
	end
	for _, plot in ipairs(plots:GetChildren()) do
		local mine = plot.Name == ("Plot" .. tostring(plotIndex))
		for _, prompt in ipairs(plot:GetDescendants()) do
			if prompt:IsA("ProximityPrompt") then
				if prompt.Name == "StealPrompt" then
					local model = prompt:FindFirstAncestorOfClass("Model")
					if model and model:GetAttribute("OwnerUserId") == myId then
						prompt.Enabled = false
					end
				elseif prompt.Name == "LockPrompt" then
					-- the server never changes this one, so set it both ways
					prompt.Enabled = mine
				elseif prompt.Name == "BuyPrompt" or prompt.Name == "HatchPrompt" then
					if not mine then
						prompt.Enabled = false
					end
				end
			end
		end
	end
end

local function screenFlash(color: Color3, strength: number?)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = 1 - (strength or 0.5)
	Kit.tween(flash, 0.6, { BackgroundTransparency = 1 })
end

-- Hatch reveal ------------------------------------------------------------------------------
local reveal
local function buildReveal()
	local screen = Windows.screen()
	reveal = Kit.new("Frame", {
		Name = "HatchReveal",
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.4,
		Size = UDim2.new(1, 0, 1, 80),
		Position = UDim2.fromOffset(0, -60),
		Visible = false,
		ZIndex = 80,
		Parent = screen,
	})
	local vp = Preview.new(reveal, UDim2.fromOffset(380, 380), UDim2.new(0.5, -190, 0.5, -230), 81)
	vp.Name = "Viewport"
	Kit.label({ Name = "Title", Text = "", Size = UDim2.fromOffset(700, 56), Position = UDim2.new(0.5, -350, 0.5, 150), Z = 82, StrokeThickness = 4, Parent = reveal })
	Kit.label({ Name = "Sub", Text = "", Size = UDim2.fromOffset(700, 34), Position = UDim2.new(0.5, -350, 0.5, 206), Z = 82, Parent = reveal })
end

local function playReveal(record)
	local def = Animals.ById[record.Species]
	if not def then
		return
	end
	local vp = reveal:FindFirstChild("Viewport")
	local title = reveal:FindFirstChild("Title")
	local sub = reveal:FindFirstChild("Sub")
	reveal.Visible = true
	title.Text = ""
	sub.Text = ""
	local egg = Preview.showEgg(vp, def.Id, def.Rarity)
	-- shake the egg
	local start = os.clock()
	while os.clock() - start < 1.3 do
		local t = os.clock() - start
		local amount = 0.08 + t * 0.25
		egg:PivotTo(CFrame.Angles(0, 0, math.sin(t * 40) * amount))
		task.wait()
	end
	screenFlash(Color3.new(1, 1, 1), 0.9)
	sound("rbxasset://sounds/electronicpingshort.wav", 0.8)
	Preview.showAnimal(vp, def.Id, { Mutation = record.Mutation, Aura = record.Aura })
	local mutation = (record.Mutation or 1) > 1 and (Game.Mutations[record.Mutation].Name .. " ") or ""
	local color = def.Rarity == 7 and "#FFFFFF" or Kit.hex(Game.Rarities[def.Rarity].Color)
	title.Text = string.format('<font color="%s">%s%s</font>', color, mutation, def.Id)
	local aura = Game.Auras[record.Aura or 1]
	sub.Text = string.format("%s · %skg%s", Game.Rarities[def.Rarity].Name, Format.number(record.Weight),
		(record.Aura or 1) > 1 and string.format(' · <font color="%s">%s aura</font>', Kit.hex(aura.Color), aura.Name) or "")
	task.wait(3)
	reveal.Visible = false
end

local revealQueue = {}
local revealing = false
local function queueReveal(record)
	table.insert(revealQueue, record)
	if revealing then
		return
	end
	revealing = true
	task.spawn(function()
		while #revealQueue > 0 do
			local r = table.remove(revealQueue, 1)
			pcall(playReveal, r)
		end
		revealing = false
	end)
end

-- Thief highlight while your animal is being stolen
local thiefHighlight
local function onAlarm(info)
	Feed.alarm(info)
	if thiefHighlight then
		thiefHighlight:Destroy()
		thiefHighlight = nil
	end
	if info.Kind == "Robbed" and info.ThiefUserId then
		local thief = Players:GetPlayerByUserId(info.ThiefUserId)
		if thief and thief.Character then
			thiefHighlight = Instance.new("Highlight")
			thiefHighlight.FillColor = Color3.fromRGB(255, 40, 60)
			thiefHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
			thiefHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			thiefHighlight.Adornee = thief.Character
			thiefHighlight.Parent = thief.Character
			Debris:AddItem(thiefHighlight, 90)
		end
	end
end

function Effects.init()
	local screen = Windows.screen()
	flash = Kit.new("Frame", {
		Name = "Flash",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 80),
		Position = UDim2.fromOffset(0, -60),
		ZIndex = 90,
		Active = false,
		Parent = screen,
	})
	buildReveal()

	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)

	RunService.RenderStepped:Connect(function(dt)
		updateTracks()
		animateBelts(dt)
		animateRainbow(dt)
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			filterPrompts()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(POPUP_SECONDS)
			incomePopups()
		end
	end)

	Remotes.Notify.OnClientEvent:Connect(function(text, kind)
		Feed.notify(text, kind)
	end)
	Remotes.Announce.OnClientEvent:Connect(function(lines)
		Feed.announce(lines)
		sound("rbxasset://sounds/electronicpingshort.wav", 0.4)
	end)
	Remotes.Alarm.OnClientEvent:Connect(onAlarm)
	Remotes.Hatched.OnClientEvent:Connect(queueReveal)
	Remotes.Effect.OnClientEvent:Connect(function(name, payload)
		if name == "Caught" then
			screenFlash(Color3.fromRGB(255, 40, 40), 0.55)
			sound("rbxasset://sounds/uuhhh.mp3", 0.6)
		elseif name == "AuraUp" then
			local aura = Game.Auras[payload.Aura]
			if aura then
				screenFlash(aura.Color, 0.45)
				sound("rbxasset://sounds/electronicpingshort.wav", 0.7)
			end
		elseif name == "Captured" then
			screenFlash(Color3.fromRGB(120, 255, 120), 0.3)
		elseif name == "Expedition" then
			screenFlash(Color3.fromRGB(255, 220, 90), 0.5)
			Feed.announce({ { { Text = "EXPEDITION " .. tostring(payload.Level) .. " COMPLETE!", Color = "#FFD84A" } } })
		end
	end)

	-- [VIP] chat tag
	pcall(function()
		TextChatService.OnIncomingMessage = function(message)
			local props = Instance.new("TextChatMessageProperties")
			local source = message.TextSource
			local sender = source and Players:GetPlayerByUserId(source.UserId)
			if sender and sender:GetAttribute("VIP") then
				props.PrefixText = '<font color="#FFD84A">[VIP]</font> ' .. message.PrefixText
			end
			return props
		end
	end)
end

return Effects
