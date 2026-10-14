-- Bind-steal: hold E on an animal in someone else's pen to bind it to you. An alarm goes
-- off for the owner and you have to lead the animal back to your own base. If the owner
-- reaches you first, the animal goes back. Its weight, mutation and wild aura stay with it.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Animals = require(Shared.Config.Animals)
local AnimalModel = require(Shared.AnimalModel)
local Remotes = require(Shared.Remotes)

local StealService = {}

local S
local transits = {} -- [thief] = { Owner, Uid, StartedAt, Species }

function StealService.Init(services)
	S = services
end

local function hrpOf(player: Player): BasePart?
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	return hrp
end

local function finishTransit(thief: Player)
	local t = transits[thief]
	transits[thief] = nil
	if not t then
		return nil
	end
	local ownerRt = S.PlayerService.get(t.Owner)
	if ownerRt then
		ownerRt.InTransit[t.Uid] = nil
	end
	if t.Owner.Parent then
		S.PlotService.refresh(t.Owner)
		S.PlayerService.markState(t.Owner)
	end
	return t
end

function StealService.tryStart(thief: Player, owner: Player, uid: string)
	local function deny(text)
		S.PlayerService.notify(thief, text, "error")
	end
	if thief == owner or not owner.Parent then
		return
	end
	if not S.DataService.isLoaded(thief) or not S.DataService.isLoaded(owner) then
		return
	end
	if S.CarryService.isCarrying(thief) then
		return deny("You are already carrying something!")
	end
	local ownerRt = S.PlayerService.get(owner)
	if not ownerRt then
		return
	end
	local now = os.time()
	if ownerRt.LockedUntil > now then
		return deny(owner.DisplayName .. "'s base is locked!")
	end
	if now - ownerRt.JoinedAt < Game.NewPlayerProtectionSeconds then
		return deny(owner.DisplayName .. " just joined and is protected for a moment.")
	end
	local record = S.PlayerService.findAnimal(owner, uid)
	if not record or not record.InPen or ownerRt.InTransit[uid] then
		return
	end
	if now - (record.PlacedAt or 0) < Game.NewAnimalProtectionSeconds then
		return deny("This animal just arrived and is protected for " .. (Game.NewAnimalProtectionSeconds - (now - record.PlacedAt)) .. "s.")
	end
	if not S.PlayerService.canReceiveAnimal(thief) then
		return deny("Your storage is full!")
	end
	local thiefHrp = hrpOf(thief)
	local plot = S.PlotService.plot(owner)
	if not thiefHrp or not plot or not S.PlotService.isInside(owner, thiefHrp.Position) then
		return
	end

	ownerRt.InTransit[uid] = true
	transits[thief] = { Owner = owner, Uid = uid, StartedAt = os.clock(), Species = record.Species }
	S.PlotService.refresh(owner)

	local def = Animals.ById[record.Species]
	local model = AnimalModel.build(record.Species, { Mutation = record.Mutation, Aura = record.Aura })
	local started = S.CarryService.start(thief, {
		Kind = "Stolen",
		Model = model,
		DisplayName = def.Id,
		OnDeliver = function(p)
			local t = transits[p]
			if not t or not t.Owner.Parent then
				return true
			end
			local current = S.PlayerService.findAnimal(t.Owner, t.Uid)
			if not current then
				finishTransit(p)
				return true
			end
			finishTransit(p)
			local removed = S.PlayerService.removeAnimal(t.Owner, t.Uid)
			if not removed then
				return true
			end
			local given = S.PlayerService.giveAnimal(p, {
				Species = removed.Species,
				Weight = removed.Weight,
				Mutation = removed.Mutation,
				Aura = removed.Aura,
			})
			if not given then
				-- should not happen (checked before), but never lose the animal
				table.insert(S.DataService.get(t.Owner).Animals, removed)
				S.PlotService.refresh(t.Owner)
				return true
			end
			S.DataService.get(p).Stats.Stolen += 1
			S.ShopService.fillPen(t.Owner)
			S.PlayerService.notify(p, "You stole " .. t.Owner.DisplayName .. "'s " .. def.Id .. "!", "rare")
			S.PlayerService.notify(t.Owner, p.DisplayName .. " stole your " .. def.Id .. "! Lock your base next time.", "error")
			Remotes.Alarm:FireClient(t.Owner, { Kind = "Lost", Thief = p.DisplayName, Species = def.Id })
			if def.Rarity >= 5 then
				S.PlayerService.announce({
					{ { Text = p.DisplayName, Color = "#4FB4FF" }, { Text = " stole a " }, { Text = Game.Rarities[def.Rarity].Name:upper() .. " " .. def.Id, Color = S.PlotService.rarityHex(def.Rarity) }, { Text = " from " }, { Text = t.Owner.DisplayName, Color = "#FF6B6B" } },
				})
			end
			return true
		end,
		OnDrop = function(p, reason)
			local t = finishTransit(p)
			if not t then
				return
			end
			if t.Owner.Parent then
				if reason == "stopped" then
					S.PlayerService.notify(t.Owner, "You stopped " .. p.DisplayName .. " and got your " .. def.Id .. " back!", "success")
				else
					S.PlayerService.notify(t.Owner, "Your " .. def.Id .. " is back in your pen.", "info")
				end
				Remotes.Alarm:FireClient(t.Owner, { Kind = "Safe", Species = def.Id })
			end
			if p.Parent then
				if reason == "stopped" then
					S.PlayerService.notify(p, t.Owner.DisplayName .. " caught you! The " .. def.Id .. " ran home.", "error")
				elseif reason == "timeout" then
					S.PlayerService.notify(p, "The bind broke! The " .. def.Id .. " ran home.", "error")
				elseif reason == "ownerleft" then
					S.PlayerService.notify(p, "The owner left, the " .. def.Id .. " went with them.", "info")
				end
			end
		end,
	})
	if not started then
		finishTransit(thief)
		return
	end
	S.PlayerService.notify(thief, "Bring the " .. def.Id .. " to your base before " .. owner.DisplayName .. " catches you!", "info")
	Remotes.Alarm:FireClient(owner, { Kind = "Robbed", Thief = thief.DisplayName, Species = def.Id, ThiefUserId = thief.UserId })
end

function StealService.Start()
	task.spawn(function()
		while true do
			task.wait(0.2)
			for thief, t in pairs(transits) do
				local thiefHrp = hrpOf(thief)
				local ownerHrp = t.Owner.Parent and hrpOf(t.Owner)
				if thiefHrp and ownerHrp and (thiefHrp.Position - ownerHrp.Position).Magnitude <= Game.StealStopDistance then
					S.CarryService.drop(thief, "stopped")
				elseif os.clock() - t.StartedAt > Game.StealMaxSeconds then
					S.CarryService.drop(thief, "timeout")
				end
			end
		end
	end)

	S.DataService.onReleasing(function(player)
		for thief, t in pairs(transits) do
			if t.Owner == player then
				S.CarryService.drop(thief, "ownerleft")
			end
		end
		if transits[player] then
			S.CarryService.drop(player, "left")
		end
	end)
end

return StealService
