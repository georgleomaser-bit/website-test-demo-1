-- Admin panel backend. Only the experience owner (or group owner) and Game.AdminUserIds
-- can use it; every request is checked here on the server.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Animals = require(Shared.Config.Animals)
local Upgrades = require(Shared.Config.Upgrades)
local Monetization = require(Shared.Config.Monetization)
local Zones = require(Shared.Config.Zones)
local Game = require(Shared.Config.Game)
local EggModel = require(Shared.EggModel)
local Format = require(Shared.Format)

local AdminService = {}

local S

function AdminService.Init(services)
	S = services
end

local function isAdmin(player: Player): boolean
	local rt = S.PlayerService.get(player)
	return rt ~= nil and rt.IsAdmin == true
end

local function target(userId): Player?
	if type(userId) ~= "number" then
		return nil
	end
	local player = Players:GetPlayerByUserId(userId)
	if player and S.DataService.isLoaded(player) then
		return player
	end
	return nil
end

local function num(v, min: number, max: number): number?
	if type(v) ~= "number" or v ~= v then
		return nil
	end
	return math.clamp(v, min, max)
end

local actions = {}

actions.GiveCash = function(_admin, userId, amount)
	local p = target(userId)
	amount = num(amount, -1e300, 1e300)
	if not p or not amount then
		return false, "Bad target or amount"
	end
	S.PlayerService.addCash(p, amount)
	return true, "Gave $" .. Format.number(amount) .. " to " .. p.Name
end

actions.GiveSpeed = function(_admin, userId, amount)
	local p = target(userId)
	amount = num(amount, -1e300, 1e300)
	if not p or not amount then
		return false, "Bad target or amount"
	end
	S.PlayerService.addSpeed(p, amount)
	return true, "Gave " .. Format.number(amount) .. " Speed to " .. p.Name
end

actions.SetUpgrade = function(_admin, userId, id, level)
	local p = target(userId)
	local def = type(id) == "string" and Upgrades.ById[id]
	if not p or not def then
		return false, "Bad target or upgrade"
	end
	level = num(level, 0, def.MaxLevel)
	if not level then
		return false, "Bad level"
	end
	S.DataService.get(p).Upgrades[id] = math.floor(level)
	S.ShopService.fillPen(p)
	S.PlotService.refreshEggs(p)
	S.PlotService.refreshTreadmills(p)
	S.PlayerService.markState(p)
	return true, def.Name .. " set to level " .. math.floor(level)
end

actions.SetRebirths = function(_admin, userId, amount)
	local p = target(userId)
	amount = num(amount, 0, 1e6)
	if not p or not amount then
		return false, "Bad target or amount"
	end
	S.DataService.get(p).Rebirths = math.floor(amount)
	S.ShopService.fillPen(p)
	S.PlayerService.markState(p)
	return true, "Rebirths set"
end

actions.GiveAnimal = function(_admin, userId, species, mutation, aura)
	local p = target(userId)
	if not p or type(species) ~= "string" or not Animals.ById[species] then
		return false, "Bad target or animal"
	end
	local record = S.PlayerService.giveAnimal(p, {
		Species = species,
		Mutation = num(mutation, 1, #Game.Mutations) and math.floor(mutation) or 1,
		Aura = num(aura, 1, #Game.Auras) and math.floor(aura) or 1,
	})
	return record ~= nil, record and ("Gave " .. species .. " to " .. p.Name) or "Storage full"
end

actions.GiveBait = function(_admin, userId, amount)
	local p = target(userId)
	amount = num(amount, -1000, 1000)
	if not p or not amount then
		return false
	end
	local data = S.DataService.get(p)
	data.Bait = math.max(0, data.Bait + math.floor(amount))
	S.PlayerService.markState(p)
	return true, "Bait given"
end

actions.Boost = function(_admin, userId, boost, minutes)
	local p = target(userId)
	minutes = num(minutes, 1, 10000)
	if not p or not minutes or not table.find(Game.BoostTypes, boost) then
		return false
	end
	S.PlayerService.addBoost(p, boost, minutes * 60)
	return true, "x2 " .. boost .. " for " .. minutes .. " min"
end

actions.SetPass = function(_admin, userId, key, owned)
	local p = target(userId)
	if not p or type(key) ~= "string" or not Monetization.PassByKey[key] then
		return false
	end
	S.MonetizationService.setPass(p, key, owned == true)
	return true, key .. (owned and " given" or " removed")
end

actions.SpawnEgg = function(admin, species)
	local def = type(species) == "string" and Animals.ById[species]
	if not def then
		return false, "Unknown animal"
	end
	-- put the egg into the first nest of the animal's zone
	for _, nest in ipairs(S.NestService.nests()) do
		if nest.Zone == def.Zone and not nest.Taken then
			S.NestService.refillNest(nest, {
				Species = def.Id,
				Rarity = def.Rarity,
				Zone = def.Zone,
				Mutation = 1,
				Source = "Lane",
			})
			local zone = Zones[def.Zone]
			S.PlayerService.announce({
				{ { Text = admin.DisplayName, Color = "#4FB4FF", Verified = true }, { Text = " spawned a " }, { Text = "RARE EGG!", Color = "#FFD84A" } },
				{ { Text = EggModel.displayName(def.Id, def.Rarity), Color = S.PlotService.rarityHex(def.Rarity) }, { Text = " spawned in " }, { Text = zone.Name, Color = "#" .. zone.Accent:ToHex() } },
			})
			return true, "Egg spawned"
		end
	end
	return false, "All nests in that zone are busy"
end

actions.SpawnAnimal = function(admin, species)
	local def = type(species) == "string" and Animals.ById[species]
	if not def then
		return false, "Unknown animal"
	end
	S.WildService.spawn(def.Zone, def.Id, admin)
	if def.Rarity < 5 then
		local zone = Zones[def.Zone]
		S.PlayerService.announce({
			{ { Text = admin.DisplayName, Color = "#4FB4FF", Verified = true }, { Text = " spawned a " }, { Text = def.Id:upper() .. "!", Color = S.PlotService.rarityHex(def.Rarity) } },
			{ { Text = "in " }, { Text = zone.Name, Color = "#" .. zone.Accent:ToHex() } },
		})
	end
	return true, "Spawned " .. def.Id
end

actions.OpenLair = function()
	S.LairService.open()
	return true, "Dragon Lair opened"
end

actions.CloseLair = function()
	if not S.LairService.isOpen() then
		return false, "Lair is not open"
	end
	S.LairService.close()
	return true, "Dragon Lair closed"
end

actions.ServerLuck = function(admin, minutes)
	minutes = num(minutes, 1, 600)
	if not minutes then
		return false
	end
	S.PlayerService.ServerLuckUntil = math.max(S.PlayerService.ServerLuckUntil, os.time()) + minutes * 60
	S.PlayerService.announce({
		{ { Text = admin.DisplayName, Color = "#4FB4FF", Verified = true }, { Text = " activated " }, { Text = "x2 SERVER LUCK!", Color = "#7CFF6B" } },
	})
	for _, p in ipairs(Players:GetPlayers()) do
		S.PlayerService.markState(p)
	end
	return true, "Server luck on"
end

actions.Broadcast = function(admin, text)
	if type(text) ~= "string" or #text == 0 then
		return false, "Empty message"
	end
	text = string.sub(text, 1, 120)
	local ok, filtered = pcall(function()
		local result = game:GetService("TextService"):FilterStringAsync(text, admin.UserId)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		return false, "Message could not be filtered"
	end
	S.PlayerService.announce({
		{ { Text = admin.DisplayName, Color = "#4FB4FF", Verified = true }, { Text = " " .. filtered } },
	})
	return true, "Sent"
end

actions.Kick = function(admin, userId, reason)
	local p = Players:GetPlayerByUserId(type(userId) == "number" and userId or 0)
	if not p or p == admin then
		return false, "Bad target"
	end
	p:Kick(type(reason) == "string" and string.sub(reason, 1, 100) or "Kicked by an admin")
	return true, "Kicked " .. p.Name
end

actions.TeleportTo = function(admin, userId)
	local p = Players:GetPlayerByUserId(type(userId) == "number" and userId or 0)
	local from = admin.Character
	local to = p and p.Character
	if not from or not to or not to.PrimaryPart then
		return false
	end
	S.CarryService.noteTeleport(admin)
	from:PivotTo(to:GetPivot() * CFrame.new(0, 0, 6))
	return true
end

actions.ResetData = function(_admin, userId)
	local p = target(userId)
	if not p then
		return false, "Bad target"
	end
	S.CarryService.drop(p, "dropped")
	S.MountService.dismount(p)
	S.DataService.reset(p)
	S.RewardService.onJoin(p)
	S.PlotService.refresh(p)
	S.PlotService.refreshEggs(p)
	S.PlotService.refreshTreadmills(p)
	S.PlayerService.markState(p)
	return true, "Data reset for " .. p.Name
end

function AdminService.Start()
	S.Router.register("Admin", function(player, action, ...)
		if not isAdmin(player) then
			return false, "Not an admin"
		end
		local fn = type(action) == "string" and actions[action]
		if not fn then
			return false, "Unknown admin action"
		end
		return fn(player, ...)
	end)
end

return AdminService
