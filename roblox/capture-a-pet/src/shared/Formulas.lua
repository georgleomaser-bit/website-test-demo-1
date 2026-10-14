-- All multiplier math in one place. The server uses it to grant rewards and the client
-- uses the exact same functions to display "x17" style numbers, so they always match.
--
-- ctx = {
--   Data = player save data,
--   Passes = { [passKey] = true },
--   Friends = number of friends in the server,
--   ServerLuckUntil = os.time() when the server luck boost ends,
--   Now = os.time(),
-- }

local Shared = script.Parent
local Game = require(Shared.Config.Game)
local Animals = require(Shared.Config.Animals)
local Upgrades = require(Shared.Config.Upgrades)
local Treadmills = require(Shared.Config.Treadmills)
local Monetization = require(Shared.Config.Monetization)

local Formulas = {}

local function upgradeFactor(ctx, id: string): number
	local def = Upgrades.ById[id]
	local level = ctx.Data.Upgrades[id] or 0
	return def.Factor(level)
end

local function boostActive(ctx, boost: string): boolean
	local untilTime = ctx.Data.Boosts[boost]
	return untilTime ~= nil and untilTime > ctx.Now
end

function Formulas.boostSecondsLeft(ctx, boost: string): number
	local untilTime = ctx.Data.Boosts[boost]
	if not untilTime then
		return 0
	end
	return math.max(0, untilTime - ctx.Now)
end

function Formulas.friendBoost(ctx): number
	return math.min(Game.FriendBoostMax, (ctx.Friends or 0) * Game.FriendBoostPerFriend)
end

function Formulas.rebirthMult(ctx): number
	return 1 + ctx.Data.Rebirths * Game.RebirthMultPerLevel
end

function Formulas.indexBonus(ctx): number
	local count = 0
	for _ in pairs(ctx.Data.Index) do
		count += 1
	end
	return 1 + count * Game.IndexCashBonusPerSpecies
end

function Formulas.trainingMult(ctx): number
	local m = upgradeFactor(ctx, "Training") * Formulas.rebirthMult(ctx) * (1 + Formulas.friendBoost(ctx))
	if ctx.Passes.DoubleTraining then
		m *= 2
	end
	if ctx.Passes.VIP then
		m *= 1.5
	end
	if boostActive(ctx, "Training") then
		m *= 2
	end
	return m
end

function Formulas.cashMult(ctx): number
	local m = upgradeFactor(ctx, "Cash") * Formulas.rebirthMult(ctx) * Formulas.indexBonus(ctx)
		* (1 + Formulas.friendBoost(ctx))
	if ctx.Passes.DoubleCash then
		m *= 2
	end
	if ctx.Passes.VIP then
		m *= 1.5
	end
	if boostActive(ctx, "Cash") then
		m *= 2
	end
	return m
end

function Formulas.luckMult(ctx): number
	local m = upgradeFactor(ctx, "Luck")
	if ctx.Passes.Lucky then
		m *= 2
	end
	if boostActive(ctx, "Luck") then
		m *= 2
	end
	if (ctx.ServerLuckUntil or 0) > ctx.Now then
		m *= 2
	end
	return m
end

function Formulas.hatchMult(ctx): number
	local m = upgradeFactor(ctx, "Hatch")
	if ctx.Passes.FastHatch then
		m *= Game.FastHatchPassMult
	end
	return m
end

function Formulas.penSlots(ctx): number
	local fromRebirths = math.min(Game.RebirthMaxBonusSlots, math.floor(ctx.Data.Rebirths / Game.RebirthPenSlotEvery))
	local slots = Game.StartingPenSlots + upgradeFactor(ctx, "PenSlots") + fromRebirths
	if ctx.Passes.VIP then
		slots += 2
	end
	return math.min(slots, 36)
end

function Formulas.incubators(ctx): number
	local n = Game.StartingIncubators + upgradeFactor(ctx, "Incubators")
	if ctx.Passes.VIP then
		n += 1
	end
	return n
end

function Formulas.maxBait(ctx): number
	return ctx.Passes.BaitBag and 99 or 30
end

-- Best treadmill gain the player can use (VIP treadmill counts).
function Formulas.bestTreadmillGain(ctx): number
	local best = Treadmills[math.clamp(ctx.Data.Treadmill, 1, #Treadmills)].Gain
	if ctx.Passes.VIP then
		best *= Treadmills.VIPGainFactor
	end
	return best
end

function Formulas.treadmillGain(ctx, tier: number): number
	if tier == 0 then -- VIP treadmill
		return Formulas.bestTreadmillGain(ctx) * Formulas.trainingMult(ctx)
	end
	return Treadmills[tier].Gain * Formulas.trainingMult(ctx)
end

-- Base income of one animal record before player multipliers.
function Formulas.animalBaseIncome(animal): number
	local def = Animals.ById[animal.Species]
	if not def then
		return 0
	end
	local avgWeight = (def.Weight[1] + def.Weight[2]) / 2
	local weightFactor = animal.Weight / avgWeight
	local mutation = Game.Mutations[animal.Mutation or 1] or Game.Mutations[1]
	local aura = Game.Auras[animal.Aura or 1] or Game.Auras[1]
	return def.Income * weightFactor * mutation.IncomeMult * aura.IncomeMult
end

function Formulas.animalIncome(ctx, animal): number
	return Formulas.animalBaseIncome(animal) * Formulas.cashMult(ctx)
end

function Formulas.totalIncome(ctx): number
	local total = 0
	for _, animal in ipairs(ctx.Data.Animals) do
		if animal.InPen then
			total += Formulas.animalIncome(ctx, animal)
		end
	end
	return total
end

function Formulas.mountMult(animal): number
	local def = Animals.ById[animal.Species]
	if not def then
		return 1
	end
	local aura = Game.Auras[animal.Aura or 1] or Game.Auras[1]
	return Game.MountSpeed[def.Rarity] * aura.MountMult
end

function Formulas.walkSpeed(speedStat: number, mountMult: number, slowMode: boolean, carryFactor: number): number
	if slowMode then
		return Game.SlowModeWalkSpeed
	end
	local ws = Game.BaseWalkSpeed + Game.WalkSpeedPerDecade * math.log10(1 + math.max(0, speedStat))
	ws = ws * mountMult * carryFactor
	return math.clamp(ws, 10, Game.MaxWalkSpeed)
end

function Formulas.rebirthCost(rebirths: number): number
	return Game.RebirthBaseCost * Game.RebirthCostGrowth ^ rebirths
end

-- Relative amounts used by rewards, tasks and cash packs.
function Formulas.cashForSeconds(ctx, seconds: number, minimum: number): number
	return math.max(minimum, math.floor(Formulas.totalIncome(ctx) * seconds))
end

function Formulas.speedForSeconds(ctx, seconds: number, minimum: number): number
	return math.max(minimum, math.floor(Formulas.bestTreadmillGain(ctx) * Formulas.trainingMult(ctx) * seconds))
end

-- Products / passes lookups the UI needs.
Formulas.Monetization = Monetization

return Formulas
