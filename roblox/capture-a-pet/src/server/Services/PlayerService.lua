-- Runtime state per player, multiplier context, state replication and shared grant helpers
-- (cash, speed, animals, rewards). Other services go through here to change player data.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Format)
local Game = require(Shared.Config.Game)
local Animals = require(Shared.Config.Animals)
local Rewards = require(Shared.Config.Rewards)

local PlayerService = {}

local S -- services
local runtime = {} -- [player] = runtime table
local rng = Random.new()

PlayerService.ServerLuckUntil = 0

function PlayerService.Init(services)
	S = services
end

function PlayerService.get(player: Player)
	return runtime[player]
end

function PlayerService.data(player: Player)
	return S.DataService.get(player)
end

function PlayerService.ctx(player: Player)
	local rt = runtime[player]
	local data = S.DataService.get(player)
	if not rt or not data then
		return nil
	end
	return {
		Data = data,
		Passes = rt.Passes,
		Friends = rt.Friends,
		ServerLuckUntil = PlayerService.ServerLuckUntil,
		Now = os.time(),
	}
end

function PlayerService.markState(player: Player)
	local rt = runtime[player]
	if rt then
		rt.StateDirty = true
	end
end

function PlayerService.markStats(player: Player)
	local rt = runtime[player]
	if rt then
		rt.StatsDirty = true
	end
end

function PlayerService.notify(player: Player, text: string, kind: string?)
	Remotes.Notify:FireClient(player, text, kind or "info")
end

-- Big centered announcement for everyone. `parts` is a list of { Text, Color? } lines segments.
function PlayerService.announce(lines)
	Remotes.Announce:FireAllClients(lines)
end

function PlayerService.effect(player: Player?, name: string, payload)
	if player then
		Remotes.Effect:FireClient(player, name, payload)
	else
		Remotes.Effect:FireAllClients(name, payload)
	end
end

local function updateLeaderstats(player: Player, data)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		return
	end
	local speed = stats:FindFirstChild("Speed")
	local cash = stats:FindFirstChild("Cash")
	local rebirths = stats:FindFirstChild("Rebirths")
	if speed then
		speed.Value = data.Speed
	end
	if cash then
		cash.Value = data.Cash
	end
	if rebirths then
		rebirths.Value = data.Rebirths
	end
end

function PlayerService.buildState(player: Player)
	local ctx = PlayerService.ctx(player)
	if not ctx then
		return nil
	end
	local rt = runtime[player]
	local data = ctx.Data
	local passes = table.clone(rt.Passes)
	local carry = rt.Carry
	return {
		Data = data,
		Derived = {
			Now = os.time(),
			TrainingMult = Formulas.trainingMult(ctx),
			CashMult = Formulas.cashMult(ctx),
			LuckMult = Formulas.luckMult(ctx),
			HatchMult = Formulas.hatchMult(ctx),
			Income = PlayerService.income(player),
			PenSlots = Formulas.penSlots(ctx),
			Incubators = Formulas.incubators(ctx),
			MaxBait = Formulas.maxBait(ctx),
			RebirthCost = Formulas.rebirthCost(data.Rebirths),
			FriendBoost = Formulas.friendBoost(ctx),
			ServerLuckUntil = PlayerService.ServerLuckUntil,
			Passes = passes,
			Plot = rt.Plot,
			IsAdmin = rt.IsAdmin,
			BaitPrice = PlayerService.baitPrice(player),
			SessionStart = rt.SessionStart,
			PlaytimeClaimed = rt.PlaytimeClaimed,
			LockedUntil = rt.LockedUntil,
			LockCooldownUntil = rt.LockCooldownUntil,
			Carrying = carry and { Kind = carry.Kind, Name = carry.DisplayName, Aura = carry.Aura or 1 } or nil,
			LairOpenUntil = S.LairService and S.LairService.openUntil() or 0,
			LairNextOpen = S.LairService and S.LairService.nextOpen() or 0,
		},
	}
end

function PlayerService.income(player: Player): number
	local ctx = PlayerService.ctx(player)
	local rt = runtime[player]
	if not ctx then
		return 0
	end
	local total = 0
	for _, animal in ipairs(ctx.Data.Animals) do
		if animal.InPen and not rt.InTransit[animal.Uid] then
			total += Formulas.animalIncome(ctx, animal)
		end
	end
	return total
end

function PlayerService.baitPrice(player: Player): number
	local ctx = PlayerService.ctx(player)
	if not ctx then
		return Rewards.BaitPriceMin
	end
	return Formulas.cashForSeconds(ctx, Rewards.BaitPriceIncomeSeconds, Rewards.BaitPriceMin)
end

function PlayerService.addCash(player: Player, amount: number, earned: boolean?)
	local data = S.DataService.get(player)
	if not data or amount ~= amount or amount == math.huge then
		return
	end
	data.Cash = math.max(0, data.Cash + amount)
	if amount > 0 then
		data.Stats.TotalCash += amount
		if earned then
			S.RewardService.progress(player, "EarnCash", amount)
		end
	end
	PlayerService.markStats(player)
end

function PlayerService.spendCash(player: Player, amount: number): boolean
	local data = S.DataService.get(player)
	if not data or amount ~= amount or amount < 0 or data.Cash < amount then
		return false
	end
	data.Cash -= amount
	PlayerService.markStats(player)
	return true
end

function PlayerService.addSpeed(player: Player, amount: number)
	local data = S.DataService.get(player)
	if not data or amount ~= amount or amount == math.huge then
		return
	end
	data.Speed = math.max(0, data.Speed + amount)
	if amount > 0 then
		data.Stats.TotalSpeed += amount
		S.RewardService.progress(player, "Train", amount)
	end
	PlayerService.markStats(player)
end

function PlayerService.addBait(player: Player, amount: number)
	local data = S.DataService.get(player)
	local ctx = PlayerService.ctx(player)
	if not data or not ctx then
		return
	end
	data.Bait = math.clamp(data.Bait + amount, 0, Formulas.maxBait(ctx))
	PlayerService.markState(player)
end

function PlayerService.addBoost(player: Player, boost: string, seconds: number)
	local data = S.DataService.get(player)
	if not data then
		return
	end
	local now = os.time()
	local current = data.Boosts[boost] or 0
	data.Boosts[boost] = math.max(current, now) + seconds
	PlayerService.markState(player)
end

function PlayerService.rollMutation(luck: number): number
	-- luck helps a little with mutations too (square root so it stays rare)
	local factor = math.sqrt(math.max(1, luck))
	for index = #Game.Mutations, 2, -1 do
		if rng:NextNumber() < Game.Mutations[index].Chance * factor then
			return index
		end
	end
	return 1
end

function PlayerService.rollWeight(def): number
	local w = def.Weight[1] + (def.Weight[2] - def.Weight[1]) * rng:NextNumber() ^ 1.6
	return math.floor(w * 10 + 0.5) / 10
end

function PlayerService.penCount(player: Player): number
	local data = S.DataService.get(player)
	local count = 0
	for _, animal in ipairs(data.Animals) do
		if animal.InPen then
			count += 1
		end
	end
	return count
end

function PlayerService.findAnimal(player: Player, uid: string)
	local data = S.DataService.get(player)
	if not data then
		return nil, nil
	end
	for index, animal in ipairs(data.Animals) do
		if animal.Uid == uid then
			return animal, index
		end
	end
	return nil, nil
end

function PlayerService.canReceiveAnimal(player: Player): boolean
	local data = S.DataService.get(player)
	return data ~= nil and #data.Animals < Game.MaxStorage + 36
end

-- Adds an animal to the player's collection. Goes into the pen if there is room.
-- fields: { Species, Weight?, Mutation?, Aura? }
function PlayerService.giveAnimal(player: Player, fields)
	local data = S.DataService.get(player)
	local ctx = PlayerService.ctx(player)
	local def = Animals.ById[fields.Species]
	if not data or not ctx or not def then
		return nil
	end
	if not PlayerService.canReceiveAnimal(player) then
		PlayerService.notify(player, "Your storage is full! Sell some animals.", "error")
		return nil
	end
	local record = {
		Uid = "a" .. data.NextUid,
		Species = def.Id,
		Weight = fields.Weight or PlayerService.rollWeight(def),
		Mutation = fields.Mutation or 1,
		Aura = fields.Aura or 1,
		InPen = PlayerService.penCount(player) < Formulas.penSlots(ctx),
		PlacedAt = os.time(),
	}
	data.NextUid += 1
	table.insert(data.Animals, record)
	if not data.Index[def.Id] then
		data.Index[def.Id] = true
		PlayerService.notify(player, "NEW! " .. def.Id .. " added to your Index", "rare")
	end
	if not record.InPen then
		PlayerService.notify(player, def.Id .. " went to storage (pen full)", "info")
	end
	S.PlotService.refresh(player)
	PlayerService.markState(player)
	return record
end

function PlayerService.removeAnimal(player: Player, uid: string)
	local data = S.DataService.get(player)
	local _, index = PlayerService.findAnimal(player, uid)
	if not index then
		return nil
	end
	local record = table.remove(data.Animals, index)
	if data.Mount == uid then
		data.Mount = ""
		S.MountService.dismount(player)
	end
	S.PlotService.refresh(player)
	PlayerService.markState(player)
	return record
end

local function describeReward(player: Player, reward): string?
	local ctx = PlayerService.ctx(player)
	if reward.Type == "Cash" then
		local amount = Formulas.cashForSeconds(ctx, reward.IncomeSeconds, reward.Min)
		PlayerService.addCash(player, amount)
		return "$" .. Format.number(amount)
	elseif reward.Type == "Speed" then
		local amount = Formulas.speedForSeconds(ctx, reward.TrainSeconds, reward.Min)
		PlayerService.addSpeed(player, amount)
		return Format.number(amount) .. " Speed"
	elseif reward.Type == "Bait" then
		PlayerService.addBait(player, reward.Amount)
		return reward.Amount .. " Glow Bait"
	elseif reward.Type == "Boost" then
		PlayerService.addBoost(player, reward.Boost, reward.Seconds)
		return "x2 " .. reward.Boost .. " (" .. Format.time(reward.Seconds) .. ")"
	elseif reward.Type == "Animal" then
		local record = PlayerService.giveAnimal(player, { Species = reward.Id, Aura = reward.Aura })
		if record then
			return reward.Id
		end
	end
	return nil
end

function PlayerService.grantRewards(player: Player, rewards, title: string?)
	local parts = {}
	for _, reward in ipairs(rewards) do
		local text = describeReward(player, reward)
		if text then
			table.insert(parts, text)
		end
	end
	PlayerService.markState(player)
	if title and #parts > 0 then
		PlayerService.notify(player, title .. ": " .. table.concat(parts, ", "), "reward")
	end
	return parts
end

local function isAdmin(player: Player): boolean
	if table.find(Game.AdminUserIds, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		if player.UserId == game.CreatorId then
			return true
		end
	elseif game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(function()
			return player:GetRankInGroup(game.CreatorId)
		end)
		if ok and rank == 255 then
			return true
		end
	end
	-- local Studio test (Play Solo) has CreatorId 0
	if game:GetService("RunService"):IsStudio() then
		return true
	end
	return false
end

local function refreshFriends()
	local list = Players:GetPlayers()
	for _, player in ipairs(list) do
		local rt = runtime[player]
		if rt then
			local count = 0
			for _, other in ipairs(list) do
				if other ~= player then
					local known = rt.FriendCache[other.UserId]
					if known == nil then
						local ok, result = pcall(function()
							return player:IsFriendsWith(other.UserId)
						end)
						known = ok and result or false
						rt.FriendCache[other.UserId] = known
					end
					if known then
						count += 1
					end
				end
			end
			if rt.Friends ~= count then
				rt.Friends = count
				PlayerService.markState(player)
			end
		end
	end
end

function PlayerService.Start()
	S.DataService.onLoaded(function(player, data)
		local rt = {
			Passes = {},
			Friends = 0,
			FriendCache = {},
			SessionStart = os.time(),
			JoinedAt = os.time(),
			PlaytimeClaimed = {},
			InTransit = {},
			LockedUntil = 0,
			LockCooldownUntil = 0,
			StateDirty = true,
			StatsDirty = true,
			IsAdmin = isAdmin(player),
		}
		runtime[player] = rt

		local stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		for _, name in ipairs({ "Speed", "Cash", "Rebirths" }) do
			local v = Instance.new("NumberValue")
			v.Name = name
			v.Parent = stats
		end
		stats.Parent = player
		updateLeaderstats(player, data)

		-- offline earnings: 20% of income for up to 8 hours
		local services = S
		task.defer(function()
			services.MonetizationService.loadPasses(player)
			services.PlotService.assign(player)
			services.RewardService.onJoin(player)
			if data.LastOnline > 0 then
				local away = math.clamp(os.time() - data.LastOnline, 0, 8 * 3600)
				if away > 120 then
					local earned = math.floor(PlayerService.income(player) * away * 0.2)
					if earned > 0 then
						PlayerService.addCash(player, earned)
						PlayerService.notify(player, "While you were away your animals earned $" .. Format.number(earned) .. "!", "reward")
					end
				end
			end
			player:SetAttribute("Loaded", true)
			PlayerService.markState(player)
		end)
		task.spawn(refreshFriends)
	end)

	S.DataService.onReleasing(function(player)
		-- deferred so the other services' release callbacks can still read the runtime
		task.defer(function()
			runtime[player] = nil
		end)
	end)

	Players.PlayerRemoving:Connect(function()
		task.defer(refreshFriends)
	end)

	-- replication loop
	task.spawn(function()
		while true do
			task.wait(0.2)
			for player, rt in pairs(runtime) do
				local data = S.DataService.get(player)
				if data then
					if rt.StateDirty then
						rt.StateDirty = false
						rt.StatsDirty = false
						local state = PlayerService.buildState(player)
						if state then
							Remotes.State:FireClient(player, state)
						end
						updateLeaderstats(player, data)
						S.PlotService.refreshIncome(player)
					elseif rt.StatsDirty then
						rt.StatsDirty = false
						Remotes.Stats:FireClient(player, { Speed = data.Speed, Cash = data.Cash, Tasks = data.Tasks.List })
						updateLeaderstats(player, data)
					end
				end
			end
		end
	end)

	-- income loop
	task.spawn(function()
		while true do
			task.wait(Game.IncomeTickSeconds)
			for player in pairs(runtime) do
				local income = PlayerService.income(player)
				if income > 0 then
					PlayerService.addCash(player, income * Game.IncomeTickSeconds, true)
				end
				local data = S.DataService.get(player)
				if data then
					data.Stats.Playtime += Game.IncomeTickSeconds
				end
			end
		end
	end)

	-- refresh multipliers once a second while a timed boost runs out etc.
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.time()
			for player in pairs(runtime) do
				local data = S.DataService.get(player)
				if data then
					for boost, untilTime in pairs(data.Boosts) do
						if untilTime <= now and untilTime > now - 6 then
							PlayerService.markState(player)
						end
						if untilTime < now - 3600 then
							data.Boosts[boost] = nil
						end
					end
				end
			end
		end
	end)
end

return PlayerService
