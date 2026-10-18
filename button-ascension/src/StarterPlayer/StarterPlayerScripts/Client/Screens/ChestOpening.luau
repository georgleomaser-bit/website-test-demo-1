--[[
	ChestOpening (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Screens/ChestOpening
	Depends on: ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format,Formulas,Config/*},
	            Client/ItemCard

	Cinematic reveal of results the server has ALREADY applied:
	  anticipation shake (glow shifts toward the best rarity) → flash + light
	  rays → item cards pop in one by one with NEW / PITY / BONUS badges.
	Click or press anywhere to skip ahead. Reduced Motion shows results at once.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local UIFolder = ReplicatedStorage:WaitForChild("UI")
local UI = require(UIFolder.UIKit)
local Theme = require(UIFolder.Theme)
local Effects = require(UIFolder.Effects)
local SoundPlayer = require(UIFolder.SoundPlayer)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Config = Shared.Config
local Items = require(Config.Items)
local Rarities = require(Config.Rarities)

local ItemCard = require(script.Parent.Parent.ItemCard)

local C = Theme.Colors
local F = Theme.Fonts

local ChestOpening = {}

local active = false

local function bestResult(results)
	local best = results[1]
	for _, r in ipairs(results) do
		if Rarities.index(r.Rarity) > Rarities.index(best.Rarity) then
			best = r
		end
	end
	return best
end

-- Waits up to `seconds`, returning early when the player skips.
local function skippableWait(state, seconds: number)
	local stop = os.clock() + seconds
	while os.clock() < stop and not state.Skip do
		task.wait()
	end
end

function ChestOpening.play(ctx, chest, results, onAgain: (() -> ())?)
	if active or #results == 0 then
		return
	end
	active = true
	local state = { Skip = false }
	local best = bestResult(results)
	local bestColor = Theme.rarityColor(best.Rarity)

	local root = UI.new("TextButton", {
		Name = "ChestOpening",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.05,
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
		ZIndex = 80,
		Parent = ctx.Layers.Overlay,
	})
	root.Activated:Connect(function()
		state.Skip = true
	end)
	local stage = UI.frame({
		Name = "Stage",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(900, 620),
		ZIndex = 81,
		Scale = UI.fitScale(900, 620, 0.96, 0.92),
		Parent = root,
	})

	-- Anticipation -------------------------------------------------------------------
	local glow = UI.new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(220, 220),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.85,
		ZIndex = 82,
		Corner = Theme.Radius.Pill,
		Parent = stage,
	})
	local glowStroke = UI.stroke(glow, { Color = C.White, Thickness = 6, Transparency = 0.3 })
	local crate = UI.label({
		Name = "Crate",
		Text = chest.Icon,
		TextSize = 120,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(200, 200),
		ZIndex = 83,
		Parent = stage,
	})
	local caption = UI.label({
		Text = `Opening {#results > 1 and (#results .. " items from ") or ""}{chest.Name}…`,
		Font = F.Heading,
		TextSize = 22,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromScale(0, 0.72),
		ZIndex = 83,
		Parent = stage,
	})

	if not Theme.ReducedMotion then
		local steps = 14
		for i = 1, steps do
			if state.Skip then
				break
			end
			local t = i / steps
			local amount = 2 + t * 12
			crate.Rotation = (if i % 2 == 0 then 1 else -1) * amount
			crate.Position = UDim2.new(0.5, (math.random() - 0.5) * amount, 0.45, (math.random() - 0.5) * amount)
			-- The glow drifts from white toward the colour of the best drop.
			local color = C.White:Lerp(bestColor, t)
			glow.BackgroundColor3 = color
			glowStroke.Color = color
			glow.Size = UDim2.fromOffset(220 + t * 80, 220 + t * 80)
			if i % 3 == 0 then
				SoundPlayer.play("ChestShake", { Pitch = 0.7 + t * 0.6 })
			end
			skippableWait(state, 0.07)
		end
	end
	crate.Rotation = 0

	-- Burst -----------------------------------------------------------------------------
	SoundPlayer.play("ChestBurst")
	-- Effects draw above the opening layers (ZIndex 80-88).
	Effects.flash(root, bestColor, 0.5, 90)
	local center = Vector2.new(450, 280)
	Effects.burst(stage, center, bestColor, 30, 360, 90)
	Effects.ring(stage, center, bestColor, 700, 89)
	crate.Visible = false
	glow.Visible = false
	caption.Visible = false
	local rays = Effects.rays(stage, bestColor, 760)
	rays.Position = UDim2.fromScale(0.5, 0.45)
	rays.ZIndex = 81

	-- Reveal ----------------------------------------------------------------------------
	local single = #results == 1
	-- Bonus drops can push a 10× opening past 14 results; smaller cards keep them in three rows.
	local dense = #results > 14
	local cardSize = if single then UDim2.fromOffset(220, 256) elseif dense then UDim2.fromOffset(80, 94) else UDim2.fromOffset(112, 130)
	local holder = UI.frame({
		Name = "Cards",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, if single then 0.4 else 0.42),
		Size = UDim2.fromOffset(860, if single then 270 elseif dense then 330 else 290),
		ZIndex = 84,
		Grid = { Cell = cardSize, Pad = UDim2.fromOffset(10, 12), HA = "Center" },
		Parent = stage,
	})
	local grid = holder:FindFirstChildOfClass("UIGridLayout")
	if grid then
		grid.VerticalAlignment = Enum.VerticalAlignment.Center
	end

	local newCount, soldGems = 0, 0
	for index, result in ipairs(results) do
		local item = Items.ById[result.Item]
		if item then
			local card = ItemCard.new({ Parent = holder, LayoutOrder = index, Size = cardSize })
			card:Set({ Id = item.Id, Count = result.Count, New = result.New })
			card.Instance.ZIndex = 85
			if single then
				card.Icon.TextSize = 96
				card.Name.TextSize = 20
			elseif dense then
				card.Icon.TextSize = 30
				card.Name.TextSize = 10
			end
			if result.New then
				newCount += 1
			end
			if result.AutoSold then
				soldGems += result.AutoSold
			end
			local tag = if result.Pity then "PITY" elseif result.Bonus then "BONUS" elseif result.Test then "TEST" else nil
			if tag then
				UI.label({
					Text = tag,
					Font = F.Heading,
					TextSize = 11,
					TextColor3 = C.Background,
					TextXAlignment = Enum.TextXAlignment.Center,
					BackgroundColor3 = if tag == "PITY" then C.Gold else C.Accent2,
					BackgroundTransparency = 0,
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, 6),
					Size = UDim2.fromOffset(52, 16),
					ZIndex = 88,
					Corner = Theme.Radius.Pill,
					Parent = card.Instance,
				})
			end
			UI.attachTooltip(card.Instance, function()
				return `<b>{item.Icon} {item.Name}</b> ({item.Rarity})\n{Formulas.describeItemBonus(item, result.Count or 1)}\n{item.Description}`
			end)
			if not Theme.ReducedMotion and not state.Skip then
				card.Scale.Scale = 0
				UI.tween(card.Scale, { Scale = 1 }, Theme.Motion.Pop, true)
				local rarityIndex = Rarities.index(item.Rarity)
				SoundPlayer.play("Reveal", { Pitch = 0.8 + rarityIndex * 0.1 })
				if rarityIndex >= 5 then
					local pos = card.Instance.AbsolutePosition + card.Instance.AbsoluteSize / 2 - stage.AbsolutePosition
					Effects.burst(stage, pos / math.max(0.01, (stage:FindFirstChildOfClass("UIScale") :: UIScale).Scale), Theme.rarityColor(item.Rarity), 16, 160, 90)
				end
				skippableWait(state, if single then 0.2 else 0.12)
			end
		end
	end

	-- Summary ---------------------------------------------------------------------------
	local bestItem = Items.ById[best.Item]
	local headline = if single and bestItem then `{bestItem.Rarity} · {bestItem.Name}` else `{#results} items · best: {best.Rarity}`
	UI.label({
		Text = headline,
		Font = F.Heading,
		TextSize = 28,
		TextColor3 = bestColor,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromScale(0, 0.74),
		ZIndex = 86,
		Parent = stage,
	})
	local details = {}
	if newCount > 0 then
		table.insert(details, `✨ {newCount} new discover{if newCount == 1 then "y" else "ies"}!`)
	end
	if soldGems > 0 then
		table.insert(details, `Auto-sold duplicates for 💎 {Format.short(soldGems)}`)
	end
	if single and bestItem then
		table.insert(details, Formulas.describeItemBonus(bestItem, best.Count or 1) .. " when equipped")
	end
	UI.label({
		Text = table.concat(details, "   ·   "),
		TextColor3 = C.TextDim,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromScale(0, 0.8),
		ZIndex = 86,
		Parent = stage,
	})

	local done = false
	local function close()
		if done then
			return
		end
		done = true
		active = false
		root:Destroy()
	end
	local buttons = UI.frame({
		Size = UDim2.fromOffset(420, 50),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.87),
		ZIndex = 86,
		List = { Dir = "X", Pad = 12, HA = "Center" },
		Parent = stage,
	})
	local closeButton = UI.button({
		Text = "Continue",
		Variant = "secondary",
		Size = UDim2.fromOffset(180, 46),
		LayoutOrder = 2,
		ZIndex = 87,
		OnClick = close,
		Parent = buttons,
	})
	if onAgain then
		UI.button({
			Text = "Open again",
			Variant = "gold",
			Size = UDim2.fromOffset(180, 46),
			LayoutOrder = 1,
			ZIndex = 87,
			OnClick = function()
				close()
				onAgain()
			end,
			Parent = buttons,
		})
	end
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = closeButton
	end
end

function ChestOpening.isActive(): boolean
	return active
end

return ChestOpening
