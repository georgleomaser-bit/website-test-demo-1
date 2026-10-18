--[[
	Economy tab (ModuleScript)
	Location: ServerStorage/AdminClient/AdminUI/Tabs/Economy
	Depends on: AdminUI/Widgets, AdminUI/TargetPicker, ReplicatedStorage/Shared/Format,
	            ReplicatedStorage/Shared/Config/GameConfig
	Server actions: economy.add, economy.remove, economy.set, economy.reward,
	                economy.reset (destructive, server-issued confirmation), players.inspect

	Amounts typed here are parsed for convenience (1.5k, 2m, 1e6); the server
	re-validates every amount against the role's limit.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared:WaitForChild("Format"))
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))

local Widgets = require(script.Parent.Parent.Widgets)
local TargetPicker = require(script.Parent.Parent.TargetPicker)

local UI = Widgets.UI
local P = Widgets.P

local TEST_REWARDS = {
	{ Id = "gems_pack", Text = "💎 500 Gems" },
	{ Id = "crate_bundle", Text = "📦 Crate bundle" },
	{ Id = "frenzy", Text = "🔥 Frenzy ×3 (60 s)" },
	{ Id = "orb", Text = "🔮 Spawn bonus orb" },
	{ Id = "level_up", Text = "📈 Next level" },
}

return function(ctx, container: Frame)
	local scroll = Widgets.scroll(container)
	local canGrant = ctx.has("economy.grant")
	local limits = ctx.Hello.Limits or {}

	local targetSection = Widgets.section(scroll, "Target", 1, "Changes apply to this player. Offline players (#UserId) need the offline.write permission.")
	TargetPicker.new(ctx, targetSection, 1)
	local balances = Widgets.dim({ Text = "", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 18), Parent = targetSection })

	local function refreshBalances()
		local query = ctx.Target.Query
		if query == nil or not ctx.has("players.inspect") then
			balances.Text = ""
			return
		end
		local response = ctx.Net.request("players.inspect", { Target = query })
		if ctx.Target.Query ~= query then
			return
		end
		if response.ok and type(response.data) == "table" and response.data.Currencies then
			local c = response.data.Currencies
			balances.Text = `Current balances — ⚡ {Format.short(c.Sparks)}   💎 {Format.short(c.Gems)}   🔷 {Format.short(c.Prisms)}`
			balances.TextColor3 = P.TextDim
		else
			balances.Text = response.err or ""
			balances.TextColor3 = P.Warning
		end
	end

	local currencySection = Widgets.section(scroll, "Currency", 2, `Your role's limit per action: {Format.short(limits.MaxCurrency or 0)}`)
	local currencyOptions = {}
	for _, id in ipairs(GameConfig.CurrencyOrder) do
		local def = GameConfig.Currencies[id]
		table.insert(currencyOptions, { Id = id, Text = def.Icon .. " " .. def.Name, Color = def.Color })
	end
	local currency = Widgets.chips({ Parent = currencySection, Options = currencyOptions, Value = "Sparks", Order = 1, Height = 30 })

	local amountRow = Widgets.row(currencySection, 2, 34)
	Widgets.rowLabel(amountRow, "Amount", 70, 1)
	local amountBox = Widgets.textbox({ Placeholder = "e.g. 1500, 2.5k, 3m, 1e9", Size = UDim2.fromOffset(220, 32), LayoutOrder = 2, MaxLength = 30, Parent = amountRow })
	local preview = Widgets.dim({ Text = "", Size = UDim2.fromOffset(200, 32), LayoutOrder = 3, Parent = amountRow })
	amountBox:GetPropertyChangedSignal("Text"):Connect(function()
		local n = Widgets.parseNumber(amountBox.Text)
		if amountBox.Text == "" then
			preview.Text = ""
		elseif n then
			preview.Text = "= " .. Format.commas(n)
			preview.TextColor3 = if n > (limits.MaxCurrency or 0) then P.Warning else P.TextDim
		else
			preview.Text = "not a number"
			preview.TextColor3 = P.Danger
		end
	end)

	local function amount(): number?
		local n = Widgets.parseNumber(amountBox.Text)
		if not n then
			ctx.toast("Enter a valid amount.", "error")
			return nil
		end
		return math.floor(n)
	end

	local function target(): any
		local query = ctx.Target.Query
		if query == nil then
			ctx.toast("Select a target player first.", "error")
		end
		return query
	end

	local function runEconomy(action: string, label: string, currencyOverride: string?)
		local t = target()
		local n = amount()
		if t == nil or n == nil then
			return
		end
		ctx.Net.run(action, { Target = t, Currency = currencyOverride or currency.Get(), Amount = n }, { Label = label })
		refreshBalances()
	end

	local buttons = Widgets.row(currencySection, 3, 36)
	local add = Widgets.button({ Text = "＋ Add", Variant = "adminPrimary", LayoutOrder = 1, OnClick = function()
		runEconomy("economy.add", "Add currency")
	end, Parent = buttons })
	local remove = Widgets.button({ Text = "－ Remove", Variant = "adminSecondary", LayoutOrder = 2, OnClick = function()
		runEconomy("economy.remove", "Remove currency")
	end, Parent = buttons })
	local set = Widgets.button({ Text = "＝ Set exactly", Variant = "adminSecondary", LayoutOrder = 3, OnClick = function()
		runEconomy("economy.set", "Set currency")
	end, Parent = buttons })
	local prisms = Widgets.button({ Text = "🔷 Grant Prisms", Variant = "adminMagenta", Size = UDim2.fromOffset(150, 32), LayoutOrder = 4, OnClick = function()
		runEconomy("economy.add", "Grant Prisms", "Prisms")
	end, Parent = buttons })
	for _, button in ipairs({ add, remove, set, prisms }) do
		Widgets.gate(button, canGrant, "economy.grant")
	end

	local rewards = Widgets.section(scroll, "Test rewards & bonuses", 3, "Fixed test grants for checking reward flows. They do not count toward leaderboards.")
	local rewardRow = UI.frame({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = rewards })
	local rewardLayout = UI.list(rewardRow, { Dir = "X", Pad = 6 })
	rewardLayout.Wraps = true
	for index, reward in ipairs(TEST_REWARDS) do
		local button = Widgets.button({
			Text = reward.Text,
			Size = UDim2.fromOffset(0, 32),
			AutomaticSize = Enum.AutomaticSize.X,
			Padding = { X = 12 },
			LayoutOrder = index,
			OnClick = function()
				local t = target()
				if t ~= nil then
					ctx.Net.run("economy.reward", { Target = t, Reward = reward.Id }, { Label = "Test reward" })
					refreshBalances()
				end
			end,
			Parent = rewardRow,
		})
		Widgets.gate(button, canGrant, "economy.grant")
	end

	local danger = Widgets.section(scroll, "Danger zone", 4, "Resetting currencies sets Sparks, Gems and Prisms to 0. The server asks for confirmation.")
	local reset = Widgets.button({
		Text = "⚠ Reset all currencies",
		Variant = "adminDanger",
		Size = UDim2.fromOffset(220, 34),
		LayoutOrder = 1,
		OnClick = function()
			local t = target()
			if t ~= nil then
				ctx.Net.run("economy.reset", { Target = t }, { Label = "Reset currencies" })
				refreshBalances()
			end
		end,
		Parent = danger,
	})
	Widgets.gate(reset, ctx.has("economy.reset"), "economy.reset")

	-- Only players picked from the list refresh automatically (typed names are
	-- resolved by the server when an action runs), debounced to one request.
	local version = 0
	ctx.TargetChanged:Connect(function()
		version += 1
		local mine = version
		if container.Visible and type(ctx.Target.Query) == "number" then
			task.delay(0.4, function()
				if mine == version then
					refreshBalances()
				end
			end)
		end
	end)

	local tab = {}
	function tab.OnShow()
		refreshBalances()
	end
	return tab
end
