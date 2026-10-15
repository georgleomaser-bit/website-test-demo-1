-- Upgrades bought with Cash. The four multiplier upgrades go up to x1000 (999 levels).
-- Cost of the next level = BaseCost * Growth ^ level.

local Upgrades = {
	{
		Id = "Cash",
		Name = "Cash Multiplier",
		Description = "More cash from every animal",
		MaxLevel = 999,
		BaseCost = 150,
		Growth = 1.032,
		-- factor at a level, shown in the shop as the real effective value
		Factor = function(level: number): number
			return 1 + level
		end,
	},
	{
		Id = "Training",
		Name = "Training Multiplier",
		Description = "More Speed per treadmill tick",
		MaxLevel = 999,
		BaseCost = 120,
		Growth = 1.032,
		Factor = function(level: number): number
			return 1 + level
		end,
	},
	{
		Id = "Luck",
		Name = "Luck Multiplier",
		Description = "Rarer animals on the lane and from eggs",
		MaxLevel = 999,
		BaseCost = 500,
		Growth = 1.034,
		Factor = function(level: number): number
			return 1 + level
		end,
	},
	{
		Id = "Hatch",
		Name = "Hatch Speed",
		Description = "Eggs hatch faster",
		MaxLevel = 999,
		BaseCost = 400,
		Growth = 1.033,
		Factor = function(level: number): number
			return 1 + level
		end,
	},
	{
		Id = "PenSlots",
		Name = "Pen Slots",
		Description = "+1 animal in your pen",
		MaxLevel = 10,
		BaseCost = 2500,
		Growth = 9,
		Factor = function(level: number): number
			return level
		end,
	},
	{
		Id = "Incubators",
		Name = "Incubators",
		Description = "+1 egg hatching at once",
		MaxLevel = 3,
		BaseCost = 20000,
		Growth = 40,
		Factor = function(level: number): number
			return level
		end,
	},
}

local byId = {}
for _, def in ipairs(Upgrades) do
	byId[def.Id] = def
end

local module = {
	List = Upgrades,
	ById = byId,
}

function module.cost(def, level: number): number
	return math.floor(def.BaseCost * def.Growth ^ level)
end

-- Total cost and number of levels affordable when buying up to `wanted` levels.
function module.bulk(def, level: number, cash: number, wanted: number): (number, number)
	local total = 0
	local bought = 0
	while bought < wanted and level + bought < def.MaxLevel do
		local nextCost = module.cost(def, level + bought)
		if total + nextCost > cash then
			break
		end
		total += nextCost
		bought += 1
	end
	return bought, total
end

return module
