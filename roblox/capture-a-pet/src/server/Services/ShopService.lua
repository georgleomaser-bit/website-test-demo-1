-- Cash spending and collection management: treadmills, upgrades (x1, x10, max), rebirth,
-- glow bait, placing animals in the pen, selling, and the slow mode setting.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Treadmills = require(Shared.Config.Treadmills)
local Upgrades = require(Shared.Config.Upgrades)
local Game = require(Shared.Config.Game)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)

local ShopService = {}

local S

function ShopService.Init(services)
	S = services
end

function ShopService.buyTreadmill(player: Player, tier: number): (boolean, string?)
	local data = S.DataService.get(player)
	local def = Treadmills[tier]
	if not data or not def then
		return false, "Unknown treadmill"
	end
	if tier <= data.Treadmill then
		return false, "You already own this treadmill"
	end
	if tier ~= data.Treadmill + 1 then
		return false, "Buy the " .. Treadmills[data.Treadmill + 1].Name .. " Treadmill first"
	end
	if not S.PlayerService.spendCash(player, def.Cost) then
		return false, "You need $" .. Format.number(def.Cost)
	end
	data.Treadmill = tier
	S.PlotService.refreshTreadmills(player)
	S.PlayerService.markState(player)
	S.PlayerService.notify(player, def.Name .. " Treadmill unlocked!", "success")
	return true
end

function ShopService.buyUpgrade(player: Player, id: string, amount: number): (boolean, string?)
	local data = S.DataService.get(player)
	local def = Upgrades.ById[id]
	if not data or not def then
		return false, "Unknown upgrade"
	end
	local level = data.Upgrades[id] or 0
	if level >= def.MaxLevel then
		return false, "Maxed out!"
	end
	local wanted = math.clamp(math.floor(amount), 1, def.MaxLevel)
	local bought, total = Upgrades.bulk(def, level, data.Cash, wanted)
	if bought == 0 then
		return false, "You need $" .. Format.number(Upgrades.cost(def, level))
	end
	if not S.PlayerService.spendCash(player, total) then
		return false, "Not enough cash"
	end
	data.Upgrades[id] = level + bought
	if id == "PenSlots" then
		ShopService.fillPen(player)
	elseif id == "Incubators" then
		S.PlotService.refreshEggs(player)
	elseif id == "Training" then
		S.PlotService.refreshTreadmills(player)
	end
	S.PlayerService.markState(player)
	return true, def.Name .. " " .. Format.multiplier(def.Factor(level + bought))
end

function ShopService.rebirth(player: Player): (boolean, string?)
	local data = S.DataService.get(player)
	if not data then
		return false
	end
	local cost = Formulas.rebirthCost(data.Rebirths)
	if data.Cash < cost then
		return false, "You need $" .. Format.number(cost) .. " to rebirth"
	end
	data.Cash = 0
	data.Speed = 0
	data.Treadmill = 1
	data.Rebirths += 1
	ShopService.fillPen(player)
	S.PlotService.refreshTreadmills(player)
	S.PlayerService.markState(player)
	S.PlayerService.notify(player, "REBIRTH " .. data.Rebirths .. "! Cash and Training are now x" .. Format.number(1 + data.Rebirths * Game.RebirthMultPerLevel), "rare")
	if data.Rebirths % 5 == 0 then
		S.PlayerService.announce({
			{ { Text = player.DisplayName, Color = "#4FB4FF" }, { Text = " reached " }, { Text = "REBIRTH " .. data.Rebirths .. "!", Color = "#FFD84A" } },
		})
	end
	return true
end

function ShopService.buyBait(player: Player, amount: number): (boolean, string?)
	local data = S.DataService.get(player)
	local ctx = S.PlayerService.ctx(player)
	if not data or not ctx then
		return false
	end
	amount = math.clamp(math.floor(amount), 1, 10)
	local space = Formulas.maxBait(ctx) - data.Bait
	if space <= 0 then
		return false, "Your bait bag is full"
	end
	amount = math.min(amount, space)
	local price = S.PlayerService.baitPrice(player) * amount
	if not S.PlayerService.spendCash(player, price) then
		return false, "You need $" .. Format.number(price)
	end
	S.PlayerService.addBait(player, amount)
	return true, "+" .. amount .. " Glow Bait"
end

-- Puts storage animals into free pen slots, best income first.
function ShopService.fillPen(player: Player)
	local data = S.DataService.get(player)
	local ctx = S.PlayerService.ctx(player)
	if not data or not ctx then
		return
	end
	local slots = Formulas.penSlots(ctx)
	local inPen = S.PlayerService.penCount(player)
	-- too many in the pen (e.g. VIP expired)? move the weakest out
	if inPen > slots then
		local placed = {}
		for _, a in ipairs(data.Animals) do
			if a.InPen then
				table.insert(placed, a)
			end
		end
		table.sort(placed, function(a, b)
			return Formulas.animalBaseIncome(a) < Formulas.animalBaseIncome(b)
		end)
		for i = 1, inPen - slots do
			placed[i].InPen = false
		end
	elseif inPen < slots then
		local stored = {}
		for _, a in ipairs(data.Animals) do
			if not a.InPen then
				table.insert(stored, a)
			end
		end
		table.sort(stored, function(a, b)
			return Formulas.animalBaseIncome(a) > Formulas.animalBaseIncome(b)
		end)
		for i = 1, math.min(#stored, slots - inPen) do
			stored[i].InPen = true
			stored[i].PlacedAt = os.time()
		end
	end
	S.PlotService.refresh(player)
	S.PlayerService.markState(player)
end

-- Fills the pen with the highest income animals overall.
function ShopService.equipBest(player: Player): (boolean, string?)
	local data = S.DataService.get(player)
	local ctx = S.PlayerService.ctx(player)
	local rt = S.PlayerService.get(player)
	local slots = Formulas.penSlots(ctx)
	local list = {}
	for _, a in ipairs(data.Animals) do
		if not rt.InTransit[a.Uid] then
			table.insert(list, a)
		end
	end
	table.sort(list, function(a, b)
		return Formulas.animalBaseIncome(a) > Formulas.animalBaseIncome(b)
	end)
	for i, a in ipairs(list) do
		local wasInPen = a.InPen
		a.InPen = i <= slots
		if a.InPen and not wasInPen then
			a.PlacedAt = os.time()
		end
	end
	S.PlotService.refresh(player)
	S.PlayerService.markState(player)
	return true, "Best animals placed!"
end

function ShopService.togglePen(player: Player, uid: string): (boolean, string?)
	local record = S.PlayerService.findAnimal(player, uid)
	local ctx = S.PlayerService.ctx(player)
	local rt = S.PlayerService.get(player)
	if not record then
		return false, "Animal not found"
	end
	if rt.InTransit[uid] then
		return false, "This animal is being stolen!"
	end
	if record.InPen then
		record.InPen = false
	else
		if S.PlayerService.penCount(player) >= Formulas.penSlots(ctx) then
			return false, "Your pen is full! Upgrade Pen Slots."
		end
		record.InPen = true
		record.PlacedAt = os.time()
	end
	S.PlotService.refresh(player)
	S.PlayerService.markState(player)
	return true
end

function ShopService.sell(player: Player, uids): (boolean, string?)
	local ctx = S.PlayerService.ctx(player)
	local rt = S.PlayerService.get(player)
	if type(uids) ~= "table" then
		uids = { uids }
	end
	local total = 0
	local count = 0
	for i, uid in ipairs(uids) do
		if i > 300 then
			break
		end
		if type(uid) == "string" and not rt.InTransit[uid] then
			local record = S.PlayerService.findAnimal(player, uid)
			if record then
				total += Formulas.animalIncome(ctx, record) * Game.SellFraction
				S.PlayerService.removeAnimal(player, uid)
				count += 1
			end
		end
	end
	if count == 0 then
		return false, "Nothing sold"
	end
	S.PlayerService.addCash(player, total)
	ShopService.fillPen(player)
	return true, "Sold " .. count .. " for $" .. Format.number(total)
end

function ShopService.Start()
	local Router = S.Router
	Router.register("BuyTreadmill", function(player, tier)
		if type(tier) ~= "number" then
			return false
		end
		return ShopService.buyTreadmill(player, math.floor(tier))
	end)
	Router.register("BuyUpgrade", function(player, id, amount)
		if type(id) ~= "string" or type(amount) ~= "number" or amount ~= amount then
			return false
		end
		return ShopService.buyUpgrade(player, id, amount)
	end)
	Router.register("Rebirth", function(player)
		return ShopService.rebirth(player)
	end)
	Router.register("BuyBait", function(player, amount)
		if type(amount) ~= "number" or amount ~= amount then
			return false
		end
		return ShopService.buyBait(player, amount)
	end)
	Router.register("EquipBest", function(player)
		return ShopService.equipBest(player)
	end)
	Router.register("TogglePen", function(player, uid)
		if type(uid) ~= "string" then
			return false
		end
		return ShopService.togglePen(player, uid)
	end)
	Router.register("Sell", function(player, uids)
		return ShopService.sell(player, uids)
	end)
	Router.register("SetSlowMode", function(player, enabled)
		local data = S.DataService.get(player)
		data.SlowMode = enabled == true
		S.PlayerService.markState(player)
		return true
	end)
end

return ShopService
