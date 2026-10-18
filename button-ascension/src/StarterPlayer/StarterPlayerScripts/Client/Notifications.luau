--[[
	Notifications (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Notifications
	Depends on: ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format, Config/*}

	Toasts (top-right stack), banners (centre-top queue) and announcements.
	Handles every "Notify" kind sent by the server (see ServerScriptService/Core/Net).
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIFolder = ReplicatedStorage:WaitForChild("UI")
local UI = require(UIFolder.UIKit)
local Theme = require(UIFolder.Theme)
local Effects = require(UIFolder.Effects)
local SoundPlayer = require(UIFolder.SoundPlayer)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Config = Shared.Config
local Items = require(Config.Items)
local Chests = require(Config.Chests)
local Achievements = require(Config.Achievements)
local GameConfig = require(Config.GameConfig)
local GamePasses = require(Config.GamePasses)

local C = Theme.Colors
local F = Theme.Fonts

local Notifications = {}

local toastList: Frame
local bannerHolder: Frame
local bannerQueue = {}
local bannerBusy = false
local layer: Frame
local context: any = nil

function Notifications.describeReward(reward): string
	if type(reward) ~= "table" then
		return ""
	end
	local parts = {}
	if reward.Sparks then
		table.insert(parts, "⚡ " .. Format.short(reward.Sparks))
	end
	if reward.Gems then
		table.insert(parts, "💎 " .. Format.short(reward.Gems))
	end
	if reward.Prisms then
		table.insert(parts, "🔷 " .. Format.short(reward.Prisms))
	end
	if reward.SkillPoints then
		table.insert(parts, `🌳 {reward.SkillPoints} SP`)
	end
	if reward.Chests then
		for _, id in ipairs(Chests.Order) do
			local n = reward.Chests[id]
			if n then
				table.insert(parts, `{Chests.ById[id].Icon} {n}× {Chests.ById[id].Name}`)
			end
		end
	end
	if reward.XP then
		table.insert(parts, "📈 " .. Format.short(reward.XP) .. " XP")
	end
	return table.concat(parts, "   ")
end

function Notifications.init(ctx)
	context = ctx
	layer = ctx.Layers.Notifications
	local inset = GuiService:GetGuiInset()
	toastList = UI.frame({
		Name = "Toasts",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, inset.Y + 70),
		Size = UDim2.fromOffset(330, 400),
		List = { Dir = "Y", Pad = 8, HA = "Right" },
		Scale = 1,
		Parent = layer,
	})
	bannerHolder = UI.frame({
		Name = "Banners",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, inset.Y + 100),
		Size = UDim2.fromOffset(560, 130),
		Scale = 1,
		Parent = layer,
	})
	local function rescale()
		local v = UI.viewport()
		local s = math.clamp(math.min(v.X / 1280, v.Y / 720), 0.6, 1.2) * Theme.UserScale
		for _, holder in ipairs({ toastList, bannerHolder }) do
			local scale = holder:FindFirstChildOfClass("UIScale")
			if scale then
				scale.Scale = s
			end
		end
	end
	rescale()
	UI.onViewportChanged(rescale)
	Notifications.rescale = rescale
end

-- Toasts ----------------------------------------------------------------------------------

function Notifications.toast(text: string, opts: { Icon: string?, Color: Color3?, Duration: number? }?)
	local o = opts or {}
	local color = o.Color or C.Accent2
	local holder = UI.frame({ Name = "Toast", Size = UDim2.fromOffset(330, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = toastList })
	local card = UI.new("Frame", {
		Name = "Card",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromOffset(360, 0),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.04,
		Corner = Theme.Radius.Medium,
		Stroke = { Color = Theme.darken(color, 0.3), Thickness = 1.5 },
		Padding = { 14, 12, 10, 10 },
		Parent = holder,
	})
	UI.new("Frame", {
		Name = "Accent",
		Size = UDim2.new(0, 4, 1, -12),
		Position = UDim2.fromOffset(-8, 6),
		BackgroundColor3 = color,
		Corner = Theme.Radius.Pill,
		Parent = card,
	})
	UI.label({
		Text = (if o.Icon then o.Icon .. "  " else "") .. text,
		TextWrapped = true,
		RichText = true,
		TextSize = 15,
		Font = F.Medium,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 20),
		Parent = card,
	})
	if Theme.ReducedMotion then
		card.Position = UDim2.fromOffset(0, 0)
	else
		UI.tween(card, { Position = UDim2.fromOffset(0, 0) }, Theme.Motion.Normal)
	end
	task.delay(o.Duration or 3.6, function()
		local t = UI.tween(card, { Position = UDim2.fromOffset(360, 0) }, Theme.Motion.Normal)
		if t then
			t.Completed:Wait()
		end
		holder:Destroy()
	end)
	local toasts = toastList:GetChildren()
	local count = 0
	for _, child in ipairs(toasts) do
		if child:IsA("Frame") then
			count += 1
		end
	end
	if count > 5 then
		for _, child in ipairs(toasts) do
			if child:IsA("Frame") and child ~= holder then
				child:Destroy()
				break
			end
		end
	end
end

function Notifications.error(text: string?)
	SoundPlayer.play("Error")
	Notifications.toast(text or "Something went wrong.", { Icon = "⚠️", Color = C.Danger })
end

-- Shows the error of a failed action result, or an optional success message.
function Notifications.result(result, successText: string?)
	if not result then
		return
	end
	if result.ok then
		if successText then
			SoundPlayer.play("Purchase")
			local rewardText = if result.Reward then "  " .. Notifications.describeReward(result.Reward) else ""
			Notifications.toast(successText .. rewardText, { Icon = "✅", Color = C.Success })
		end
	else
		Notifications.error(result.err)
	end
end

-- Banners -----------------------------------------------------------------------------------

local function showNextBanner()
	if bannerBusy then
		return
	end
	local spec = table.remove(bannerQueue, 1)
	if not spec then
		return
	end
	bannerBusy = true
	local color = spec.Color or C.Accent
	local card = UI.new("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -40),
		Size = UDim2.fromOffset(spec.Width or 520, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.02,
		Corner = Theme.Radius.Large,
		Stroke = { Color = color, Thickness = 2 },
		Padding = { 20, 20, 14, 14 },
		List = { Dir = "Y", Pad = 4, HA = "Center" },
		Parent = bannerHolder,
	})
	UI.gradient(card, { Color = ColorSequence.new(Theme.darken(color, 0.72), C.Panel), Rotation = 90 })
	if spec.Kicker then
		UI.label({ Text = spec.Kicker, Font = F.Bold, TextSize = 13, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 1, Parent = card })
	end
	UI.label({
		Text = spec.Title,
		Font = F.Heading,
		TextSize = spec.TitleSize or 26,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 2,
		Parent = card,
	})
	if spec.Text and spec.Text ~= "" then
		UI.label({
			Text = spec.Text,
			TextColor3 = C.TextDim,
			TextSize = 16,
			TextWrapped = true,
			RichText = spec.RichText == true,
			TextXAlignment = Enum.TextXAlignment.Center,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 20),
			LayoutOrder = 3,
			Parent = card,
		})
	end
	if spec.Sound then
		SoundPlayer.play(spec.Sound)
	end
	if spec.Flash then
		Effects.flash(layer, color, 0.18)
	end
	if Theme.ReducedMotion then
		card.Position = UDim2.new(0.5, 0, 0, 0)
	else
		UI.tween(card, { Position = UDim2.new(0.5, 0, 0, 0) }, Theme.Motion.Pop)
	end
	task.delay(spec.Duration or 3.5, function()
		local t = UI.tween(card, { Position = UDim2.new(0.5, 0, 0, -220) }, Theme.Motion.Normal)
		if t then
			t.Completed:Wait()
		end
		card:Destroy()
		bannerBusy = false
		showNextBanner()
	end)
end

function Notifications.banner(spec)
	table.insert(bannerQueue, spec)
	-- Announcements jump the queue so staff messages are never delayed.
	if spec.Priority then
		table.remove(bannerQueue)
		table.insert(bannerQueue, 1, spec)
	end
	showNextBanner()
end

-- Special notifications ------------------------------------------------------------------------

function Notifications.golden(golden)
	local text
	if golden.Type == "Sparks" then
		text = `+{Format.short(golden.Amount)} Sparks`
	elseif golden.Type == "Gems" then
		text = `+{Format.short(golden.Amount)} Gems`
	elseif golden.Type == "Chest" then
		local chest = Chests.ById[golden.Chest]
		text = if chest then `+1 {chest.Name}` else "A crate"
	elseif golden.Type == "Frenzy" then
		text = `Frenzy! All Sparks ×{golden.Multiplier} for {golden.Duration}s`
	end
	Notifications.toast(`<b>GOLDEN PRESS!</b> {text or ""}`, { Icon = "🌟", Color = C.Gold, Duration = 4 })
end

local HANDLERS = {}

HANDLERS.Toast = function(data)
	Notifications.toast(data.Text or "", { Icon = data.Icon, Color = data.Color })
end

HANDLERS.Error = function(data)
	Notifications.error(data.Text)
end

HANDLERS.Warning = function(data)
	SoundPlayer.play("Error")
	Notifications.toast(data.Text or "", { Icon = "⚠️", Color = C.Warning, Duration = 7 })
end

HANDLERS.LevelUp = function(data)
	local parts = {}
	if data.SkillPoints and data.SkillPoints > 0 then
		table.insert(parts, `+{data.SkillPoints} Skill Point{if data.SkillPoints == 1 then "" else "s"}`)
	end
	for id, n in pairs(data.Chests or {}) do
		local chest = Chests.ById[id]
		if chest then
			table.insert(parts, `+{n} {chest.Name}`)
		end
	end
	Notifications.banner({
		Kicker = "LEVEL UP",
		Title = `Level {data.Level}`,
		Text = table.concat(parts, "  ·  "),
		Color = C.Accent3,
		Sound = "LevelUp",
		Duration = 2.6,
		Width = 380,
	})
end

HANDLERS.Discovery = function(data)
	local item = Items.ById[data.Item]
	if item then
		local hex = Theme.rarityColor(item.Rarity):ToHex()
		Notifications.toast(`New discovery: {item.Icon} <font color="#{hex}"><b>{item.Name}</b></font> ({item.Rarity})`, {
			Icon = "📖",
			Color = Theme.rarityColor(item.Rarity),
		})
	end
end

HANDLERS.Achievement = function(data)
	local def = Achievements.ById[data.Id]
	if def then
		Notifications.banner({
			Kicker = "ACHIEVEMENT UNLOCKED",
			Title = `{def.Icon} {def.Name}`,
			Text = Notifications.describeReward(data.Reward),
			Color = C.Gold,
			Sound = "Unlock",
			Duration = 3.4,
		})
	end
end

HANDLERS.Announcement = function(data)
	local global = data.Scope == "global"
	Notifications.banner({
		Kicker = if global then "🌐 GAME-WIDE ANNOUNCEMENT" else "📢 SERVER ANNOUNCEMENT (this server)",
		Title = data.Text or "",
		TitleSize = 21,
		Text = `— {data.From or "Staff"}`,
		Color = if global then C.Accent3 else C.Accent2,
		Sound = "Announcement",
		Duration = 8,
		Width = 600,
		Priority = true,
		Flash = true,
	})
end

HANDLERS.Event = function(data)
	local def = GameConfig.Events.Definitions[data.Id]
	if not def then
		return
	end
	if data.Started then
		local seconds = (data.EndsAt or 0) - workspace:GetServerTimeNow()
		Notifications.banner({
			Kicker = "SERVER EVENT",
			Title = `{def.Icon} {def.Name}`,
			Text = `{def.Description} for {Format.time(seconds)} in this server!`,
			Color = def.Color,
			Sound = "Unlock",
			Duration = 4,
			Flash = true,
		})
	else
		Notifications.toast(`{def.Icon} {def.Name} has ended.`, { Color = def.Color })
	end
end

HANDLERS.Reward = function(data)
	SoundPlayer.play("Purchase")
	Notifications.toast(`<b>{data.Title or "Reward"}</b>: {data.Text or ""}`, { Icon = "🎁", Color = C.Success })
end

HANDLERS.Pass = function(data)
	local pass = GamePasses.ByKey[data.Key]
	if pass then
		Notifications.banner({
			Kicker = "GAME PASS UNLOCKED",
			Title = `{pass.Icon} {pass.Name}`,
			Text = pass.EffectText,
			Color = pass.Color,
			Sound = "Unlock",
			Duration = 5,
			Flash = true,
		})
	end
end

-- A Robux crate the server already opened and applied: play the opening for it
-- (after any opening that is still on screen).
HANDLERS.CrateOpened = function(data)
	local chest = Chests.RobuxById[data.Chest]
	if not chest or type(data.Results) ~= "table" or #data.Results == 0 then
		return
	end
	task.spawn(function()
		local ChestOpening = require(script.Parent.Screens.ChestOpening)
		local deadline = os.clock() + 60
		while ChestOpening.isActive() and os.clock() < deadline do
			task.wait(0.25)
		end
		ChestOpening.play(context, chest, data.Results)
	end)
end

HANDLERS.Stage = function(data)
	local stage = GameConfig.Stages[data.Stage]
	if stage then
		Notifications.banner({
			Kicker = "NEW STAGE UNLOCKED",
			Title = stage.Name,
			Text = stage.Description,
			Color = stage.Accent,
			Sound = "LevelUp",
			Duration = 5,
			Flash = true,
		})
	end
end

HANDLERS.Offline = function(data)
	Notifications.banner({
		Kicker = "WELCOME BACK",
		Title = `+{Format.short(data.Amount)} Sparks`,
		Text = `Your generators kept running for {Format.time(data.Seconds)} while you were away.`,
		Color = C.Sparks,
		Sound = "Purchase",
		Duration = 5,
	})
end

HANDLERS.Rare = function(data)
	local item = Items.ById[data.Item]
	if item then
		local hex = Theme.rarityColor(item.Rarity):ToHex()
		Notifications.toast(`<b>{data.Player}</b> found {item.Icon} <font color="#{hex}"><b>{item.Name}</b></font> ({item.Rarity})!`, {
			Icon = "🌟",
			Color = Theme.rarityColor(item.Rarity),
			Duration = 5,
		})
	end
end

function Notifications.handle(kind: string, data: any)
	local handler = HANDLERS[kind]
	if handler and type(data) == "table" then
		handler(data)
	end
end

return Notifications
