--[[
	Settings (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Screens/Settings
	Depends on: ReplicatedStorage/UI/*, ReplicatedStorage/Shared/Config/{GameConfig,Rarities},
	            Client/{State,ClientNet}

	Player preferences, saved with the player's data. Changes apply locally
	right away and are sent to the server (debounced); the server validates
	every key and value.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIFolder = ReplicatedStorage:WaitForChild("UI")
local UI = require(UIFolder.UIKit)
local Theme = require(UIFolder.Theme)
local SoundPlayer = require(UIFolder.SoundPlayer)
local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local GameConfig = require(Config.GameConfig)
local Rarities = require(Config.Rarities)

local Client = script.Parent.Parent
local State = require(Client.State)
local ClientNet = require(Client.ClientNet)

local C = Theme.Colors
local F = Theme.Fonts

local SettingsScreen = {}

function SettingsScreen.new(ctx)
	local window = UI.window({
		Name = "Settings",
		Title = "Settings",
		Subtitle = "Saved with your progress.",
		Icon = "⚙️",
		Size = Vector2.new(760, 600),
		Parent = ctx.Layers.Windows,
	})
	local screen: { [string]: any } = { Window = window }
	local list = UI.scroll({ Size = UDim2.fromScale(1, 1), List = { Dir = "Y", Pad = 8 }, Padding = { 2, 10, 2, 8 }, Parent = window.Body })
	local controls = {}
	local pendingSend: { [string]: any } = {}
	local order = 0

	local function send(key: string, value: any)
		local isNew = pendingSend[key] == nil
		pendingSend[key] = value
		-- Apply locally at once (the server copy arrives with the next sync).
		local settings = State.get("Settings")
		if settings then
			settings[key] = value
		end
		ctx.ApplySettings()
		if isNew then
			task.delay(0.4, function()
				local v = pendingSend[key]
				pendingSend[key] = nil
				local result = ClientNet.action("UpdateSettings", { Key = key, Value = v })
				if not result.ok then
					ctx.Notifications.error(result.err)
				end
			end)
		end
	end

	local function row(label: string, hint: string?): Frame
		order += 1
		local frame = UI.panel({ Size = UDim2.new(1, 0, 0, if hint then 62 else 50), BackgroundColor3 = C.PanelLight, LayoutOrder = order, Parent = list })
		UI.label({ Text = label, Font = F.Bold, TextSize = 16, Size = UDim2.new(0.5, 0, 0, 22), Position = UDim2.fromOffset(16, if hint then 9 else 14), Parent = frame })
		if hint then
			UI.label({ Text = hint, TextSize = 12, TextColor3 = C.TextMuted, TextWrapped = true, Size = UDim2.new(0.55, 0, 0, 26), Position = UDim2.fromOffset(16, 31), Parent = frame })
		end
		return frame
	end

	local function sliderRow(key: string, label: string, hint: string?, format: (number) -> string, step: number)
		local def = GameConfig.Settings[key]
		local frame = row(label, hint)
		controls[key] = UI.slider({
			Min = def.Min,
			Max = def.Max,
			Step = step,
			Value = def.Default,
			Width = 300,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Format = format,
			OnChange = function(v)
				send(key, v)
			end,
			Parent = frame,
		})
	end

	local function toggleRow(key: string, label: string, hint: string?)
		local frame = row(label, hint)
		controls[key] = UI.toggle({
			Value = GameConfig.Settings[key].Default,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -16, 0.5, 0),
			OnChange = function(v)
				send(key, v)
			end,
			Parent = frame,
		})
	end

	local function percent(v: number): string
		return tostring(math.floor(v * 100 + 0.5)) .. "%"
	end

	sliderRow(
		"Music",
		"Music volume",
		if SoundPlayer.hasMusic() then nil else "No music track is configured (see Config/Sounds).",
		percent,
		0.05
	)
	sliderRow("SFX", "Sound effects", nil, percent, 0.05)
	sliderRow("UIScale", "Interface size", "Scales the whole interface.", function(v)
		return string.format("%.2f×", v)
	end, 0.05)
	sliderRow("BackgroundDim", "Background dim", "Darkens the world behind the interface.", percent, 0.05)
	toggleRow("ReducedMotion", "Reduced motion", "Turns off shaking, particles and most animations.")
	toggleRow("ScreenShake", "Screen shake on crits")
	toggleRow("FloatingNumbers", "Floating reward numbers")
	toggleRow("ConfirmRareSales", "Confirm selling Epic or better")

	local autoFrame = row("Auto-sell duplicates", "Duplicates up to this rarity are sold for Gems the moment you open them.")
	local autoOptions = { { Id = 0, Text = "Off" } }
	for i = 1, GameConfig.Inventory.AutoSellMaxIndex do
		table.insert(autoOptions, { Id = i, Text = Rarities.Order[i] })
	end
	controls.AutoSell = UI.segmented({
		Options = autoOptions,
		Value = 0,
		ButtonWidth = 84,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		OnChange = function(id)
			send("AutoSell", id)
		end,
		Parent = autoFrame,
	})

	order += 1
	local info = UI.panel({ Size = UDim2.new(1, 0, 0, 120), BackgroundColor3 = C.BackgroundAlt, LayoutOrder = order, Padding = 14, Parent = list })
	local dataLabel = UI.label({ Text = "", Font = F.Bold, TextSize = 14, Size = UDim2.new(1, 0, 0, 20), Parent = info })
	UI.label({
		Text = "Controls — Mouse/touch: press the big button and tap menus. Controller: R2/L2 press, Y jumps to the menu, D-pad moves, A selects, B closes windows.",
		TextSize = 13,
		TextColor3 = C.TextDim,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 50),
		Position = UDim2.fromOffset(0, 26),
		Parent = info,
	})
	UI.label({
		Text = `{GameConfig.GameName} v{GameConfig.Version}`,
		TextSize = 12,
		TextColor3 = C.TextMuted,
		Size = UDim2.new(1, 0, 0, 16),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Parent = info,
	})

	function screen.Refresh()
		local settings = State.get("Settings") or {}
		for key, control in pairs(controls) do
			local value = settings[key]
			if value ~= nil and pendingSend[key] == nil then
				control.Set(value)
			end
		end
		local derived = State.get("Derived")
		if derived and derived.Persistent == false then
			dataLabel.Text = "⚠ Saving is disabled in this session — progress will not be kept."
			dataLabel.TextColor3 = C.Warning
		else
			dataLabel.Text = "✓ Progress saves automatically every minute and when you leave."
			dataLabel.TextColor3 = C.Success
		end
	end

	State.subscribe({ "Settings", "Derived" }, function()
		if window.IsOpen() then
			screen.Refresh()
		end
	end)
	window.Opened.Event:Connect(screen.Refresh)
	return screen
end

return SettingsScreen
