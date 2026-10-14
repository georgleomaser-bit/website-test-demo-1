-- Your animals (pen / storage, ride, sell) and your nests with hatching eggs.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Format = require(Shared.Format)
local Animals = require(Shared.Config.Animals)
local Game = require(Shared.Config.Game)
local Formulas = require(Shared.Formulas)
local EggModel = require(Shared.EggModel)

local Kit = require(script.Parent.Kit)
local Windows = require(script.Parent.Windows)
local Feed = require(script.Parent.Feed)
local Preview = require(script.Parent.Preview)
local State = require(script.Parent.Parent.State)

local PetsWindow = {}

local MAX_PREVIEW_TILES = 30

local window
local tab = "Animals"
local pages = {}
local tabButtons = {}
local grid
local header
local detail = {}
local selectedUid = nil
local nestList

local function act(name, ...)
	local ok, msg = State.action(name, ...)
	if msg then
		Feed.notify(msg, ok and "success" or "error")
	end
	return ok
end

local function incomeOf(animal): number
	-- matches the server: base income times the cash multiplier the server sent
	return Formulas.animalBaseIncome(animal) * State.Derived.CashMult
end

local function findAnimal(uid)
	for _, a in ipairs(State.Data.Animals) do
		if a.Uid == uid then
			return a
		end
	end
	return nil
end

local function showDetail()
	local a = selectedUid and findAnimal(selectedUid)
	detail.Panel.Visible = a ~= nil
	if not a then
		return
	end
	local def = Animals.ById[a.Species]
	local mutation = Game.Mutations[a.Mutation or 1]
	local aura = Game.Auras[a.Aura or 1]
	Preview.showAnimal(detail.Viewport, a.Species, { Mutation = a.Mutation, Aura = a.Aura })
	local name = ((a.Mutation or 1) > 1 and (mutation.Name .. " ") or "") .. def.Id
	detail.Name.Text = string.format('<font color="%s">%s</font>', def.Rarity == 7 and "#FFFFFF" or Kit.hex(Game.Rarities[def.Rarity].Color), name)
	detail.Info.Text = string.format(
		"%s · %skg\n<font color=\"#7CFF6B\">$%s/s</font>\nAura: <font color=\"%s\">%s</font>\nRide speed: x%.2f",
		Game.Rarities[def.Rarity].Name, Format.number(a.Weight), Format.number(incomeOf(a)), Kit.hex(aura.Color), aura.Name, Formulas.mountMult(a))
	detail.Pen.setText(a.InPen and "Store" or "Put in Pen")
	detail.Ride.setText(State.Data.Mount == a.Uid and "Get off" or "Ride")
	detail.Sell.setText("Sell $" .. Format.number(incomeOf(a) * Game.SellFraction))
end

local function buildAnimals()
	for _, child in ipairs(grid:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local list = table.clone(State.Data.Animals)
	table.sort(list, function(x, y)
		return Formulas.animalBaseIncome(x) > Formulas.animalBaseIncome(y)
	end)
	for order, a in ipairs(list) do
		local def = Animals.ById[a.Species]
		if def then
			local tile = Kit.new("TextButton", {
				Name = a.Uid,
				AutoButtonColor = true,
				BackgroundColor3 = Game.Rarities[def.Rarity].Color,
				LayoutOrder = order,
				Text = "",
				Parent = grid,
			})
			Kit.corner(tile, 10)
			Kit.stroke(tile, a.Uid == selectedUid and 4 or 2.5, a.Uid == selectedUid and Kit.Colors.Yellow or nil, Enum.ApplyStrokeMode.Border)
			Kit.gradient(tile, Color3.new(1, 1, 1), Color3.fromRGB(160, 160, 160))
			if order <= MAX_PREVIEW_TILES then
				local vp = Preview.new(tile, UDim2.new(1, -8, 1, -32), UDim2.fromOffset(4, 4), 23)
				Preview.showAnimal(vp, a.Species, { Mutation = a.Mutation }, false, true)
			else
				Kit.label({ Text = def.Id, Size = UDim2.new(1, -8, 1, -32), Position = UDim2.fromOffset(4, 4), Z = 23, Parent = tile })
			end
			Kit.label({ Text = "$" .. Format.number(incomeOf(a)) .. "/s", Size = UDim2.new(1, -6, 0, 18), Position = UDim2.new(0, 3, 1, -24), Color = Kit.Colors.Money, Z = 24, Parent = tile })
			if a.InPen then
				Kit.label({ Text = "✔", Size = UDim2.fromOffset(20, 20), Position = UDim2.fromOffset(4, 2), Color = Kit.Colors.Green, Z = 25, Parent = tile })
			end
			if State.Data.Mount == a.Uid then
				Kit.label({ Text = "🐎", Size = UDim2.fromOffset(22, 22), Position = UDim2.new(1, -24, 0, 2), Stroke = false, Z = 25, Parent = tile })
			end
			tile.Activated:Connect(function()
				Kit.playClick()
				selectedUid = a.Uid
				buildAnimals()
				showDetail()
			end)
		end
	end
	local d = State.Derived
	local inPen = 0
	for _, a in ipairs(State.Data.Animals) do
		if a.InPen then
			inPen += 1
		end
	end
	header.Text = string.format("Pen %d/%d · Animals %d/%d · Income <font color=\"#7CFF6B\">$%s/s</font>", inPen, d.PenSlots, #State.Data.Animals, Game.MaxStorage + 36, Format.number(d.Income))
	showDetail()
end

local function buildNests()
	for _, child in ipairs(nestList:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local slots = State.Derived.Incubators
	local now = State.now()
	for i = 1, slots do
		local egg = State.Data.Eggs[i]
		local row = Kit.panel({ Size = UDim2.new(1, -12, 0, 90), Color = Kit.Colors.PanelLight, Order = i, Parent = nestList })
		local vp = Preview.new(row, UDim2.fromOffset(80, 80), UDim2.fromOffset(6, 5))
		if type(egg) == "table" then
			Preview.showEgg(vp, egg.Species, egg.Rarity)
			local aura = Game.Auras[egg.Aura or 1]
			local left = egg.ReadyAt - now
			Kit.label({
				Text = string.format('<font color="%s">%s</font>%s\n%s',
					egg.Rarity == 7 and "#FFFFFF" or Kit.hex(Game.Rarities[egg.Rarity].Color), EggModel.displayName(egg.Species, egg.Rarity),
					(egg.Aura or 1) > 1 and string.format(' <font color="%s">[%s]</font>', Kit.hex(aura.Color), aura.Name) or "",
					left > 0 and ("Hatches in " .. Format.time(left)) or '<font color="#7CFF6B">Ready!</font>'),
				Size = UDim2.new(1, -260, 1, -10),
				Position = UDim2.fromOffset(96, 5),
				XAlign = Enum.TextXAlignment.Left,
				Parent = row,
			})
			Kit.button({ Text = left > 0 and "Wait" or "HATCH!", Size = UDim2.fromOffset(140, 54), Position = UDim2.new(1, -12, 0.5, 0), Anchor = Vector2.new(1, 0.5), Color = left > 0 and Kit.Colors.Gray or Kit.Colors.Yellow, Parent = row }, function()
				act("Hatch", i)
			end)
		else
			Kit.label({ Text = "Empty nest — steal an egg from a guarded nest on the lane!", Size = UDim2.new(1, -110, 1, -10), Position = UDim2.fromOffset(96, 5), XAlign = Enum.TextXAlignment.Left, Color = Color3.fromRGB(190, 195, 220), Parent = row })
		end
	end
end

local function showTab(name: string)
	tab = name
	for n, page in pairs(pages) do
		page.Visible = n == name
		tabButtons[n].setColor(n == name and Kit.Colors.Orange or Kit.Colors.Gray)
	end
	if not State.ready() then
		return
	end
	if name == "Animals" then
		buildAnimals()
	else
		buildNests()
	end
end

function PetsWindow.init()
	window = Windows.create("Pets", "My Animals", Vector2.new(820, 500), Kit.Colors.Orange)
	local content = window.Content
	local tabs = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 50), Parent = content })
	Kit.list(tabs, 8, true)
	for i, name in ipairs({ "Animals", "Nests" }) do
		tabButtons[name] = Kit.button({ Text = name, Size = UDim2.fromOffset(150, 44), Order = i, Parent = tabs }, function()
			showTab(name)
		end)
		pages[name] = Kit.new("Frame", { Name = name, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -58), Position = UDim2.fromOffset(0, 58), Parent = content })
	end

	-- animals page
	local animals = pages.Animals
	header = Kit.label({ Text = "", Size = UDim2.new(1, -280, 0, 26), XAlign = Enum.TextXAlignment.Left, Parent = animals })
	Kit.button({ Text = "Equip Best", Size = UDim2.fromOffset(150, 40), Position = UDim2.new(1, -270, 0, -48), Anchor = Vector2.new(1, 0), Color = Kit.Colors.Blue, Parent = animals }, function()
		act("EquipBest")
	end)
	local gridPanel = Kit.panel({ Size = UDim2.new(1, -270, 1, -34), Position = UDim2.fromOffset(0, 32), Color = Kit.Colors.PanelDark, Parent = animals })
	grid = Windows.scroll(gridPanel, UDim2.new(1, -8, 1, -8), UDim2.fromOffset(4, 4))
	Kit.new("UIGridLayout", { CellSize = UDim2.fromOffset(92, 100), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })

	local panel = Kit.panel({ Size = UDim2.new(0, 258, 1, 0), Position = UDim2.new(1, 0, 0, 0), Anchor = Vector2.new(1, 0), Color = Kit.Colors.PanelDark, Parent = animals })
	detail.Panel = panel
	detail.Viewport = Preview.new(panel, UDim2.new(1, -16, 0, 140), UDim2.fromOffset(8, 6))
	detail.Name = Kit.label({ Text = "", Size = UDim2.new(1, -16, 0, 28), Position = UDim2.fromOffset(8, 146), Parent = panel })
	detail.Info = Kit.label({ Text = "", Size = UDim2.new(1, -16, 0, 84), Position = UDim2.fromOffset(8, 176), Parent = panel })
	local function selected()
		return selectedUid
	end
	detail.Pen = Kit.button({ Text = "Put in Pen", Size = UDim2.new(1, -24, 0, 40), Position = UDim2.fromOffset(12, 268), Color = Kit.Colors.Green, Parent = panel }, function()
		if selected() then
			act("TogglePen", selected())
		end
	end)
	detail.Ride = Kit.button({ Text = "Ride", Size = UDim2.new(1, -24, 0, 40), Position = UDim2.fromOffset(12, 316), Color = Kit.Colors.Blue, Parent = panel }, function()
		local a = selected() and findAnimal(selected())
		if a then
			act("Mount", State.Data.Mount == a.Uid and "" or a.Uid)
		end
	end)
	detail.Sell = Kit.button({ Text = "Sell", Size = UDim2.new(1, -24, 0, 40), Position = UDim2.fromOffset(12, 364), Color = Kit.Colors.Red, Parent = panel }, function()
		if selected() then
			local uid = selected()
			selectedUid = nil
			act("Sell", { uid })
		end
	end)

	-- nests page
	nestList = Windows.scroll(pages.Nests, UDim2.fromScale(1, 1), UDim2.new())
	Kit.list(nestList, 8)

	window.OnOpen = function()
		showTab(tab)
	end
	State.Changed:Connect(function()
		if Windows.isOpen("Pets") then
			showTab(tab)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if Windows.isOpen("Pets") and tab == "Nests" and State.ready() then
				buildNests()
			end
		end
	end)
end

return PetsWindow
