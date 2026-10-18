--[[
	Ascend (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Screens/Ascend
	Depends on: ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format,Formulas,Config/*},
	            Client/{State,ClientNet}

	Ascension (rebirth): shows progress toward the requirement, the Prisms
	you would receive, the permanent multiplier and the next stage, plus an
	explicit list of what resets and what is kept. Ascending always asks for
	confirmation. The right side is the Prism shop (permanent perks).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIFolder = ReplicatedStorage:WaitForChild("UI")
local UI = require(UIFolder.UIKit)
local Theme = require(UIFolder.Theme)
local Effects = require(UIFolder.Effects)
local SoundPlayer = require(UIFolder.SoundPlayer)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Config = Shared.Config
local Ascension = require(Config.Ascension)
local GameConfig = require(Config.GameConfig)

local Client = script.Parent.Parent
local State = require(Client.State)
local ClientNet = require(Client.ClientNet)

local C = Theme.Colors
local F = Theme.Fonts

local AscendScreen = {}

AscendScreen.Resets = {
	"Sparks (you start with your Head Start bonus)",
	"All Shop upgrade levels (Auto-Presser kept with Loyal Robots)",
	"Sparks earned this run and your current combo",
}
AscendScreen.Keeps = {
	"Gems, Prisms and Ascension perks",
	"Skill tree, Skill Points, level and XP",
	"Inventory, equipped items, favourites and collection",
	"Owned crates and pity progress",
	"Achievements, quests, login streak, statistics and settings",
}

function AscendScreen.new(ctx)
	local window = UI.window({
		Name = "Ascend",
		Title = "Ascension",
		Subtitle = "Reset your run for Prisms, a permanent Sparks multiplier and new stages.",
		Icon = "🔷",
		Accent = C.Prisms,
		Parent = ctx.Layers.Windows,
	})
	local screen: { [string]: any } = { Window = window }
	local body = window.Body

	local left = UI.panel({ Name = "Info", Size = UDim2.new(0.5, -8, 1, 0), BackgroundColor3 = C.PanelLight, Padding = 16, Parent = body })
	local title = UI.label({ Text = "", Font = F.Heading, TextSize = 22, Size = UDim2.new(1, 0, 0, 28), Parent = left })
	local bar = UI.progress({ Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 36), Color = C.Prisms, TextSize = 13, Parent = left })
	local gain = UI.label({ Text = "", Font = F.Heading, TextSize = 18, TextColor3 = C.Prisms, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 62), Parent = left })
	local mult = UI.label({ Text = "", TextSize = 14, TextColor3 = C.TextDim, RichText = true, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 88), Parent = left })
	local stageLabel = UI.label({ Text = "", TextSize = 14, TextColor3 = C.TextDim, TextWrapped = true, RichText = true, Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 110), Parent = left })

	-- Scrollable so the lists never collide with the button on small screens.
	local lists = UI.scroll({
		Name = "Lists",
		Size = UDim2.new(1, 0, 1, -214),
		Position = UDim2.fromOffset(0, 150),
		List = { Dir = "Y", Pad = 3 },
		Parent = left,
	})
	local order = 0
	local function list(titleText: string, entries: { string }, color: Color3)
		order += 1
		UI.label({ Text = titleText, Font = F.Heading, TextSize = 15, TextColor3 = color, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = order, Parent = lists })
		for _, text in ipairs(entries) do
			order += 1
			UI.label({
				Text = "•  " .. text,
				TextSize = 13,
				TextColor3 = C.TextDim,
				TextWrapped = true,
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, -8, 0, 18),
				LayoutOrder = order,
				Parent = lists,
			})
		end
	end
	list("Resets", AscendScreen.Resets, C.Danger)
	list("You keep", AscendScreen.Keeps, C.Success)

	local ascend = UI.button({
		Text = "Ascend",
		Icon = "🔷",
		Variant = "violet",
		Size = UDim2.new(1, 0, 0, 52),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		TextSize = 20,
		OnClick = function()
			local data = State.view()
			local stats = State.stats()
			local prisms = Formulas.rebirthPrisms(data.Stats.SparksThisRun or 0, data.Rebirths, if stats then stats.prismMultiplier else 1)
			local ok = UI.confirm({
				Title = `Ascend for +{prisms} Prisms?`,
				Message = "Your Sparks and Shop upgrades reset. Gems, items, skills, level and all permanent progress are kept.",
				ConfirmText = "Ascend",
			})
			if not ok then
				return
			end
			local result = ClientNet.once("rebirth", "Rebirth")
			if not result then
				return
			end
			if result.ok then
				SoundPlayer.play("LevelUp")
				Effects.flash(ctx.Layers.Fx, C.Prisms, 0.6)
				local v = UI.viewport()
				Effects.burst(ctx.Layers.Fx, v / 2, C.Prisms, 40, 420)
				Effects.ring(ctx.Layers.Fx, v / 2, C.Prisms, 900)
				ctx.Notifications.banner({
					Kicker = `ASCENSION {result.Rebirths}`,
					Title = `+{result.Prisms} 🔷 Prisms`,
					Text = `Permanent Sparks ×{1 + GameConfig.Rebirth.MultiplierPerRebirth * result.Rebirths} from ascensions.`,
					Color = C.Prisms,
					Duration = 4,
				})
			else
				ctx.Notifications.error(result.err)
			end
		end,
		Parent = left,
	})

	-- Prism shop -------------------------------------------------------------------------------
	local right = UI.frame({ Size = UDim2.new(0.5, -8, 1, 0), Position = UDim2.new(0.5, 8, 0, 0), Parent = body })
	local prismLabel = UI.label({ Text = "", Font = F.Heading, TextSize = 18, TextColor3 = C.Prisms, Size = UDim2.new(1, 0, 0, 24), Parent = right })
	local shop = UI.scroll({ Size = UDim2.new(1, 0, 1, -32), Position = UDim2.fromOffset(0, 32), List = { Dir = "Y", Pad = 8 }, Padding = { 2, 8, 2, 2 }, Parent = right })
	local perkCards = {}
	for index, def in ipairs(Ascension.List) do
		local card = UI.panel({ Name = def.Id, Size = UDim2.new(1, 0, 0, 74), BackgroundColor3 = C.PanelLight, LayoutOrder = index, Parent = shop })
		UI.label({ Text = def.Icon, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(48, 74), Parent = card })
		UI.label({ Text = def.Name, Font = F.Heading, TextSize = 15, Size = UDim2.new(1, -170, 0, 20), Position = UDim2.fromOffset(48, 8), Parent = card })
		UI.label({ Text = def.Description, TextSize = 12, TextColor3 = C.TextDim, TextWrapped = true, Size = UDim2.new(1, -170, 0, 28), Position = UDim2.fromOffset(48, 28), Parent = card })
		local level = UI.label({ Text = "", Font = F.Bold, TextSize = 12, TextColor3 = C.Accent2, RichText = true, Size = UDim2.new(1, -170, 0, 16), Position = UDim2.fromOffset(48, 54), Parent = card })
		local buy = UI.button({
			Text = "",
			Variant = "violet",
			Size = UDim2.fromOffset(108, 44),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			TextSize = 15,
			Sound = "Purchase",
			OnClick = function()
				local result = ClientNet.once("perk:" .. def.Id, "BuyAscension", { Id = def.Id })
				if result and not result.ok then
					ctx.Notifications.error(result.err)
				end
			end,
			Parent = card,
		})
		perkCards[def.Id] = { Def = def, Level = level, Buy = buy }
	end

	function screen.Refresh()
		if not window.IsOpen() then
			return
		end
		local data = State.view()
		local stats = State.stats()
		local requirement = Formulas.rebirthRequirement(data.Rebirths)
		local run = data.Stats.SparksThisRun or 0
		local prisms = Formulas.rebirthPrisms(run, data.Rebirths, if stats then stats.prismMultiplier else 1)
		title.Text = `Ascension #{data.Rebirths + 1}`
		bar.Set(run / requirement, `{Format.short(run)} / {Format.short(requirement)} Sparks this run`)
		gain.Text = if prisms > 0 then `You will gain +{prisms} 🔷 Prisms` else `Earn {Format.short(requirement - run)} more Sparks this run`
		local perRebirth = GameConfig.Rebirth.MultiplierPerRebirth
		mult.Text = `Permanent Sparks multiplier: {Format.mult(1 + perRebirth * data.Rebirths)} → <font color="#C47DFF"><b>{Format.mult(1 + perRebirth * (data.Rebirths + 1))}</b></font>`
		local current = Formulas.stageFor(data.Rebirths)
		local nextStage = Formulas.nextStage(data.Rebirths)
		stageLabel.Text = `Stage: <b>{current.Name}</b>`
			.. (if nextStage then ` · next: <b>{nextStage.Name}</b> at {nextStage.Rebirths} ascensions (×{nextStage.Multiplier} Sparks, new crate)` else " · all stages unlocked")
		UI.setEnabled(ascend, prisms > 0)

		local balance = State.currency("Prisms")
		prismLabel.Text = `🔷 {Format.short(balance)} Prisms`
		for id, entry in pairs(perkCards) do
			local def = entry.Def
			local lvl = data.Ascension[id] or 0
			if lvl >= def.MaxLevel then
				entry.Level.Text = `Lv {lvl}/{def.MaxLevel} · {Format.display(def.Display, def.Value(lvl))} · MAX`
				UI.setText(entry.Buy, "MAX")
				UI.setEnabled(entry.Buy, false)
			else
				local cost = Formulas.ascensionCost(def, lvl)
				entry.Level.Text = `Lv {lvl}/{def.MaxLevel} · {Format.display(def.Display, def.Value(lvl))} → <b>{Format.display(def.Display, def.Value(lvl + 1))}</b>`
				UI.setText(entry.Buy, Format.short(cost), "🔷")
				UI.setEnabled(entry.Buy, balance >= cost)
			end
		end
	end

	local pending = false
	State.subscribe({ "Stats", "Currencies", "Ascension", "Progress", "Derived" }, function()
		if pending or not window.IsOpen() then
			return
		end
		pending = true
		task.delay(0.2, function()
			pending = false
			screen.Refresh()
		end)
	end)
	window.Opened.Event:Connect(screen.Refresh)
	return screen
end

return AscendScreen
