-- Shop: multiplier upgrades up to x1000 (buy 1 / 10 / max), Glow Bait, Rebirth and the
-- Robux tab with game passes and products.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Format = require(Shared.Format)
local Upgrades = require(Shared.Config.Upgrades)
local Monetization = require(Shared.Config.Monetization)
local Game = require(Shared.Config.Game)

local Kit = require(script.Parent.Kit)
local Windows = require(script.Parent.Windows)
local Feed = require(script.Parent.Feed)
local State = require(script.Parent.Parent.State)

local ShopWindow = {}

local window
local pages = {}
local tabButtons = {}
local upgradeRows = {}
local rebirthRefs = {}
local baitRefs = {}
local robuxScroll

local TAB_COLORS = {
	Upgrades = Kit.Colors.Green,
	Items = Kit.Colors.Orange,
	Rebirth = Kit.Colors.Pink,
	Robux = Kit.Colors.Blue,
}
local TAB_ORDER = { "Upgrades", "Items", "Rebirth", "Robux" }

local function act(name, ...)
	local ok, msg = State.action(name, ...)
	if msg then
		Feed.notify(msg, ok and "success" or "error")
	end
	return ok
end

local function showTab(name: string)
	for tab, page in pairs(pages) do
		page.Visible = tab == name
		tabButtons[tab].setColor(tab == name and TAB_COLORS[tab] or Kit.Colors.Gray)
	end
end

local function row(parent, height: number, order: number)
	local frame = Kit.panel({
		Size = UDim2.new(1, -12, 0, height),
		Color = Kit.Colors.PanelLight,
		Order = order,
		Radius = 12,
		StrokeThickness = 2.5,
		Parent = parent,
	})
	return frame
end

local function buildUpgrades(page)
	local scroll = Windows.scroll(page, UDim2.fromScale(1, 1), UDim2.new())
	Kit.list(scroll, 8)
	for order, def in ipairs(Upgrades.List) do
		local frame = row(scroll, 86, order)
		local title = Kit.label({ Text = def.Name, Size = UDim2.new(0.5, 0, 0, 30), Position = UDim2.fromOffset(12, 6), XAlign = Enum.TextXAlignment.Left, Parent = frame })
		local info = Kit.label({ Text = "", Size = UDim2.new(0.5, 0, 0, 24), Position = UDim2.fromOffset(12, 36), XAlign = Enum.TextXAlignment.Left, Color = Color3.fromRGB(200, 205, 230), Parent = frame })
		local cost = Kit.label({ Text = "", Size = UDim2.new(0.5, 0, 0, 20), Position = UDim2.fromOffset(12, 60), XAlign = Enum.TextXAlignment.Left, Color = Kit.Colors.Money, Parent = frame })
		local buttons = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.48, 0, 0, 50), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Parent = frame })
		Kit.list(buttons, 8, true, Enum.HorizontalAlignment.Right)
		local amounts = def.MaxLevel > 20 and { { "x1", 1 }, { "x10", 10 }, { "MAX", 1000 } } or { { "Buy", 1 } }
		for i, a in ipairs(amounts) do
			Kit.button({ Text = a[1], Size = UDim2.fromOffset(78, 46), Order = i, Color = i == 3 and Kit.Colors.Yellow or Kit.Colors.Green, Parent = buttons }, function()
				act("BuyUpgrade", def.Id, a[2])
			end)
		end
		upgradeRows[def.Id] = { Title = title, Info = info, Cost = cost }
	end
end

local function buildItems(page)
	Kit.list(page, 10)
	local frame = row(page, 110, 1)
	Kit.label({ Text = "🪔 Glow Bait", Size = UDim2.new(0.6, 0, 0, 34), Position = UDim2.fromOffset(12, 8), XAlign = Enum.TextXAlignment.Left, Parent = frame })
	Kit.label({ Text = "Throw it (key 1 or G) to lure guards away from their nest for a few seconds.", Size = UDim2.new(0.6, 0, 0, 40), Position = UDim2.fromOffset(12, 44), XAlign = Enum.TextXAlignment.Left, Color = Color3.fromRGB(200, 205, 230), Parent = frame })
	baitRefs.Price = Kit.label({ Text = "", Size = UDim2.new(0.6, 0, 0, 20), Position = UDim2.fromOffset(12, 86), XAlign = Enum.TextXAlignment.Left, Color = Kit.Colors.Money, Parent = frame })
	local buttons = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.38, 0, 0, 50), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Parent = frame })
	Kit.list(buttons, 8, true, Enum.HorizontalAlignment.Right)
	Kit.button({ Text = "x1", Size = UDim2.fromOffset(78, 46), Order = 1, Parent = buttons }, function()
		act("BuyBait", 1)
	end)
	Kit.button({ Text = "x5", Size = UDim2.fromOffset(78, 46), Order = 2, Parent = buttons }, function()
		act("BuyBait", 5)
	end)

	local tips = row(page, 150, 2)
	Kit.label({
		Text = "How to play\n• Train on your treadmills to get faster\n• Run down the lane and capture animals (hold E)\n• Steal eggs from guarded nests and run home\n• Animals in your pen make cash every second",
		Size = UDim2.new(1, -24, 1, -16),
		Position = UDim2.fromOffset(12, 8),
		XAlign = Enum.TextXAlignment.Left,
		YAlign = Enum.TextYAlignment.Top,
		Parent = tips,
	})
end

local function buildRebirth(page)
	local frame = row(page, 300, 1)
	frame.Size = UDim2.new(1, -12, 1, -8)
	Kit.label({ Text = "🔁 REBIRTH", Size = UDim2.new(1, 0, 0, 50), Position = UDim2.fromOffset(0, 10), Color = Kit.Colors.Pink, StrokeThickness = 4, Parent = frame })
	rebirthRefs.Info = Kit.label({ Text = "", Size = UDim2.new(1, -40, 0, 120), Position = UDim2.fromOffset(20, 70), Parent = frame })
	rebirthRefs.Cost = Kit.label({ Text = "", Size = UDim2.new(1, -40, 0, 36), Position = UDim2.fromOffset(20, 196), Color = Kit.Colors.Money, Parent = frame })
	rebirthRefs.Button = Kit.button({ Text = "REBIRTH", Size = UDim2.fromOffset(220, 60), Position = UDim2.new(0.5, 0, 1, -20), Anchor = Vector2.new(0.5, 1), Color = Kit.Colors.Pink, Parent = frame }, function()
		act("Rebirth")
	end)
end

local function buildRobux(page)
	local scroll = Windows.scroll(page, UDim2.fromScale(1, 1), UDim2.new())
	Kit.new("UIGridLayout", {
		CellSize = UDim2.new(0.5, -10, 0, 150),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})
	local order = 0
	for _, pass in ipairs(Monetization.GamePasses) do
		order += 1
		local card = Kit.panel({ Color = Kit.Colors.PurpleDark, Order = order, Parent = scroll })
		Kit.gradient(card, Color3.fromRGB(255, 255, 255), Color3.fromRGB(180, 160, 230))
		Kit.label({ Text = pass.Name, Size = UDim2.new(1, -16, 0, 32), Position = UDim2.fromOffset(8, 6), Color = Kit.Colors.Yellow, Parent = card })
		Kit.label({ Text = pass.Description, Size = UDim2.new(1, -16, 0, 56), Position = UDim2.fromOffset(8, 40), Parent = card })
		local b = Kit.button({ Name = "Buy_" .. pass.Key, Text = "R$ " .. pass.Price, Size = UDim2.new(1, -24, 0, 40), Position = UDim2.new(0.5, 0, 1, -10), Anchor = Vector2.new(0.5, 1), Color = Kit.Colors.Green, Parent = card }, function()
			State.action("BuyPass", pass.Key)
		end)
		card:SetAttribute("PassKey", pass.Key)
		card:SetAttribute("Owned", false)
		b.Holder:SetAttribute("PassKey", pass.Key)
	end
	for _, product in ipairs(Monetization.Products) do
		order += 1
		local card = Kit.panel({ Color = Kit.Colors.BlueDark, Order = order, Parent = scroll })
		Kit.gradient(card, Color3.fromRGB(255, 255, 255), Color3.fromRGB(160, 190, 240))
		Kit.label({ Text = product.Name, Size = UDim2.new(1, -16, 0, 32), Position = UDim2.fromOffset(8, 6), Color = Kit.Colors.Yellow, Parent = card })
		local desc = product.Kind == "Cash" and ("Cash worth " .. Format.time(product.IncomeSeconds) .. " of your income")
			or product.Kind == "Boost" and "Double for 15 minutes"
			or product.Kind == "ServerLuck" and "x2 luck for EVERYONE in the server"
			or product.Kind == "Bait" and "Lure guards away from their nests"
			or "All eggs in your nests are ready right away"
		Kit.label({ Text = desc, Size = UDim2.new(1, -16, 0, 56), Position = UDim2.fromOffset(8, 40), Parent = card })
		Kit.button({ Text = "R$ " .. product.Price, Size = UDim2.new(1, -24, 0, 40), Position = UDim2.new(0.5, 0, 1, -10), Anchor = Vector2.new(0.5, 1), Color = Kit.Colors.Green, Parent = card }, function()
			State.action("BuyProduct", product.Key)
		end)
	end
	robuxScroll = scroll
end

function ShopWindow.refresh()
	if not State.ready() or not window then
		return
	end
	local data = State.Data
	local d = State.Derived
	for _, def in ipairs(Upgrades.List) do
		local r = upgradeRows[def.Id]
		local level = data.Upgrades[def.Id] or 0
		local factor = def.Factor(level)
		if def.MaxLevel > 20 then
			r.Title.Text = string.format("%s <font color=\"#FFE45C\">%s</font>", def.Name, Format.multiplier(factor))
			r.Info.Text = string.format("%s · Level %d/%d", def.Description, level, def.MaxLevel)
		else
			r.Title.Text = string.format("%s <font color=\"#FFE45C\">+%d</font>", def.Name, factor)
			r.Info.Text = string.format("%s · %d/%d", def.Description, level, def.MaxLevel)
		end
		if level >= def.MaxLevel then
			r.Cost.Text = "MAXED!"
		else
			local cost = Upgrades.cost(def, level)
			local color = data.Cash >= cost and "#7CFF6B" or "#FF7B7B"
			r.Cost.Text = string.format('Next: <font color="%s">$%s</font>', color, Format.number(cost))
		end
	end
	baitRefs.Price.Text = string.format("$%s each · You have %d/%d", Format.number(d.BaitPrice), data.Bait, d.MaxBait)
	local nextMult = 1 + (data.Rebirths + 1) * Game.RebirthMultPerLevel
	rebirthRefs.Info.Text = string.format(
		"Rebirths: <font color=\"#FFE45C\">%d</font>\nRebirth resets your Cash, Speed and treadmills.\nYou keep all animals and upgrades.\nCash & Training: <font color=\"#7CFF6B\">x%s → x%s</font>",
		data.Rebirths, Format.number(1 + data.Rebirths * Game.RebirthMultPerLevel), Format.number(nextMult))
	local can = data.Cash >= d.RebirthCost
	rebirthRefs.Cost.Text = string.format('Cost: <font color="%s">$%s</font>', can and "#7CFF6B" or "#FF7B7B", Format.number(d.RebirthCost))
	rebirthRefs.Button.setColor(can and Kit.Colors.Pink or Kit.Colors.Gray)
	-- owned passes
	local scroll = robuxScroll
	if scroll then
		for _, card in ipairs(scroll:GetChildren()) do
			local key = card:GetAttribute("PassKey")
			if key then
				local owned = d.Passes[key] == true
				for _, b in ipairs(card:GetChildren()) do
					if b:GetAttribute("PassKey") then
						local face = b:FindFirstChild("Face")
						local label = face and face:FindFirstChild("Label")
						if label then
							label.Text = owned and "OWNED ✔" or ("R$ " .. Monetization.PassByKey[key].Price)
						end
					end
				end
			end
		end
	end
end

function ShopWindow.init()
	window = Windows.create("Shop", "Shop", Vector2.new(720, 500), Kit.Colors.Green)
	local content = window.Content
	local tabs = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 50), Parent = content })
	Kit.list(tabs, 8, true)
	for i, name in ipairs(TAB_ORDER) do
		tabButtons[name] = Kit.button({ Text = name, Size = UDim2.fromOffset(150, 44), Order = i, Color = TAB_COLORS[name], Parent = tabs }, function()
			showTab(name)
		end)
		local page = Kit.new("Frame", { Name = name, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -60), Position = UDim2.fromOffset(0, 60), Visible = false, Parent = content })
		pages[name] = page
	end
	buildUpgrades(pages.Upgrades)
	buildItems(pages.Items)
	buildRebirth(pages.Rebirth)
	buildRobux(pages.Robux)
	showTab("Upgrades")
	window.showTab = showTab
	window.OnOpen = ShopWindow.refresh
	State.Changed:Connect(ShopWindow.refresh)
	State.StatsChanged:Connect(function()
		if Windows.isOpen("Shop") then
			ShopWindow.refresh()
		end
	end)
end

return ShopWindow
