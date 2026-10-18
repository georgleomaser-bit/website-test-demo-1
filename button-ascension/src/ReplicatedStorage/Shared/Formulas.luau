--[[
	Formulas (ModuleScript)
	Location: ReplicatedStorage/Shared/Formulas
	Depends on: Shared/Config/*, Shared/Format

	Every game formula lives here so the server (authoritative) and the client
	(previews only) can never disagree. The server computes the real values;
	the client uses the same functions to show "current -> next" previews.

	computeStats(data, ctx) folds upgrades, ascension perks, skills, equipped
	items, rebirths, stage, collection, server events and personal boosts into
	a flat Stats table.
]]

local Config = script.Parent.Config
local GameConfig = require(Config.GameConfig)
local Upgrades = require(Config.Upgrades)
local Ascension = require(Config.Ascension)
local Skills = require(Config.Skills)
local Items = require(Config.Items)
local Format = require(script.Parent.Format)

export type Stats = {
	clickBase: number,
	clickMultiplier: number,
	sparksMultiplier: number,
	clickValue: number,
	critChance: number,
	critMultiplier: number,
	comboCap: number,
	comboWindow: number,
	comboStep: number,
	goldenChance: number,
	autoRate: number,
	passivePerSec: number,
	luck: number,
	chestBonus: number,
	xpMultiplier: number,
	gemMultiplier: number,
	equipSlots: number,
	offlineRate: number,
	offlineMaxSeconds: number,
	chestDiscount: number,
	prismMultiplier: number,
	pityMultiplier: number,
	orbIntervalMultiplier: number,
	orbRewardMultiplier: number,
	streakMultiplier: number,
	startSparks: number,
	keepAuto: boolean,
	stage: number,
	rebirthMultiplier: number,
	collectionMultiplier: number,
	discovered: number,
	frenzyMultiplier: number,
}

export type Context = {
	Events: { string }?,
	FrenzyMultiplier: number?,
}

local Formulas = {}

local ADD_STATS = {
	"clickFlat",
	"clickPct",
	"sparksPct",
	"critChance",
	"critPower",
	"luck",
	"chestBonus",
	"goldenPct",
	"autoRate",
	"passiveFlat",
	"passivePct",
	"xpPct",
	"gemsPct",
	"comboCap",
	"comboWindow",
	"streakPct",
	"equipSlots",
	"offlineHours",
	"offlineRate",
	"chestDiscount",
	"prismPct",
	"pityReduction",
	"orbRate",
	"orbPct",
	"startSparks",
	"keepAuto",
}

local MULT_STATS = { "clickMult", "sparksMult", "goldenMult", "xpMult", "passiveMult" }
local IS_MULT = {}
for _, k in ipairs(MULT_STATS) do
	IS_MULT[k] = true
end

Formulas.AddStats = ADD_STATS
Formulas.MultStats = MULT_STATS

function Formulas.newModifiers()
	local m = { add = {}, mult = {} }
	for _, k in ipairs(ADD_STATS) do
		m.add[k] = 0
	end
	for _, k in ipairs(MULT_STATS) do
		m.mult[k] = 1
	end
	return m
end

local function apply(m, stat: string, mode: string?, value: number)
	if mode == "mult" or (mode == nil and IS_MULT[stat]) then
		m.mult[stat] = (m.mult[stat] or 1) * value
	else
		m.add[stat] = (m.add[stat] or 0) + value
	end
end

-- Copies beyond the first boost an equipped item's power.
function Formulas.copyBonus(count: number): number
	local eq = GameConfig.Equip
	return math.min(eq.MaxCopyBonus, eq.CopyBonusPerExtra * math.max(0, count - 1))
end

function Formulas.itemPower(item, count: number): number
	return item.Bonus * (1 + Formulas.copyBonus(count))
end

function Formulas.describeItemBonus(item, count: number?): string
	local statDef = GameConfig.ItemStats[item.Stat]
	local value = Formulas.itemPower(item, count or 1)
	return "+" .. Format.pct(value, if value < 0.1 then 1 else 0) .. " " .. statDef.Label
end

function Formulas.discoveredCount(data): number
	local n = 0
	for id in pairs(data.Discovered or {}) do
		if Items.ById[id] then
			n += 1
		end
	end
	return n
end

function Formulas.skillRanks(data): number
	local n = 0
	for id, rank in pairs(data.Skills or {}) do
		if Skills.ById[id] then
			n += rank
		end
	end
	return n
end

function Formulas.skillPointsSpent(data): number
	local n = 0
	for id, rank in pairs(data.Skills or {}) do
		local def = Skills.ById[id]
		if def then
			n += Skills.totalCost(def, rank)
		end
	end
	return n
end

function Formulas.stageFor(rebirths: number)
	local best = GameConfig.Stages[1]
	for _, stage in ipairs(GameConfig.Stages) do
		if rebirths >= stage.Rebirths then
			best = stage
		end
	end
	return best
end

function Formulas.nextStage(rebirths: number)
	for _, stage in ipairs(GameConfig.Stages) do
		if stage.Rebirths > rebirths then
			return stage
		end
	end
	return nil
end

-- Collects every modifier from the player's data and the context.
function Formulas.collect(data, ctx: Context?)
	local m = Formulas.newModifiers()

	for id, level in pairs(data.Upgrades or {}) do
		local def = Upgrades.ById[id]
		if def and level > 0 then
			apply(m, def.Stat, def.Mode, def.Value(level))
		end
	end

	for id, level in pairs(data.Ascension or {}) do
		local def = Ascension.ById[id]
		if def and level > 0 then
			apply(m, def.Stat, def.Mode, def.Value(level))
		end
	end
	local nightOwl = (data.Ascension or {}).night_owl or 0
	m.add.offlineRate += nightOwl * Ascension.OfflineRatePerNightOwl

	for id, rank in pairs(data.Skills or {}) do
		local def = Skills.ById[id]
		if def and rank > 0 then
			for _, effect in ipairs(def.Effects) do
				if effect.Mult then
					apply(m, effect.Stat, "mult", effect.Mult ^ rank)
				else
					apply(m, effect.Stat, "add", (effect.Add or 0) * rank)
				end
			end
		end
	end

	local inventory = data.Inventory or {}
	local seen = {}
	for _, itemId in ipairs(data.Equipped or {}) do
		local item = Items.ById[itemId]
		local count = inventory[itemId] or 0
		if item and count > 0 and not seen[itemId] then
			seen[itemId] = true
			local statDef = GameConfig.ItemStats[item.Stat]
			apply(m, statDef.Stat, "add", Formulas.itemPower(item, count))
		end
	end

	if ctx and ctx.Events then
		for _, eventId in ipairs(ctx.Events) do
			local def = GameConfig.Events.Definitions[eventId]
			if def then
				for stat, value in pairs(def.Effects) do
					apply(m, stat, nil, value)
				end
			end
		end
	end

	return m
end

function Formulas.computeStats(data, ctx: Context?): Stats
	local m = Formulas.collect(data, ctx)
	local a, x = m.add, m.mult
	local click = GameConfig.Click
	local rebirths = data.Rebirths or 0

	local stage = Formulas.stageFor(rebirths)
	local rebirthMultiplier = 1 + GameConfig.Rebirth.MultiplierPerRebirth * rebirths
	local discovered = Formulas.discoveredCount(data)
	local collectionMultiplier = 1 + GameConfig.Collection.SparksBonusPerItem * discovered
	local frenzy = if ctx and ctx.FrenzyMultiplier then ctx.FrenzyMultiplier else 1

	local sparksMultiplier = (1 + a.sparksPct)
		* x.sparksMult
		* rebirthMultiplier
		* stage.Multiplier
		* collectionMultiplier
		* frenzy
	local clickBase = 1 + a.clickFlat
	local clickMultiplier = (1 + a.clickPct) * x.clickMult
	local clickValue = clickBase * clickMultiplier * sparksMultiplier

	local offline = GameConfig.Offline
	local stats: Stats = {
		clickBase = clickBase,
		clickMultiplier = clickMultiplier,
		sparksMultiplier = sparksMultiplier,
		clickValue = math.min(clickValue, GameConfig.CurrencyCap),
		critChance = math.min(click.MaxCritChance, click.BaseCritChance + a.critChance),
		critMultiplier = click.BaseCritMultiplier + a.critPower,
		comboCap = click.BaseComboCap + a.comboCap,
		comboWindow = click.ComboWindow + a.comboWindow,
		comboStep = click.ComboStep,
		goldenChance = math.min(click.MaxGoldenChance, click.BaseGoldenChance * (1 + a.goldenPct) * x.goldenMult),
		autoRate = math.min(GameConfig.AutoClick.MaxRate, a.autoRate),
		passivePerSec = math.min(a.passiveFlat * (1 + a.passivePct) * x.passiveMult * sparksMultiplier, GameConfig.CurrencyCap),
		luck = a.luck,
		chestBonus = math.min(0.75, a.chestBonus),
		xpMultiplier = (1 + a.xpPct) * x.xpMult,
		gemMultiplier = 1 + a.gemsPct,
		equipSlots = math.min(GameConfig.Equip.MaxSlots, GameConfig.Equip.BaseSlots + a.equipSlots),
		offlineRate = math.min(1, offline.BaseRate + a.offlineRate),
		offlineMaxSeconds = (offline.BaseMaxHours + a.offlineHours) * 3600,
		chestDiscount = math.min(0.6, a.chestDiscount),
		prismMultiplier = 1 + a.prismPct,
		pityMultiplier = math.max(0.5, 1 - a.pityReduction),
		orbIntervalMultiplier = 1 / (1 + a.orbRate),
		orbRewardMultiplier = 1 + a.orbPct,
		streakMultiplier = 1 + a.streakPct,
		startSparks = a.startSparks,
		keepAuto = a.keepAuto > 0,
		stage = stage.Id,
		rebirthMultiplier = rebirthMultiplier,
		collectionMultiplier = collectionMultiplier,
		discovered = discovered,
		frenzyMultiplier = frenzy,
	}
	return stats
end

-- Combo multiplier for a given combo count.
function Formulas.comboMultiplier(stats: Stats, combo: number): number
	return 1 + stats.comboStep * math.min(combo, stats.comboCap)
end

-- Upgrades -------------------------------------------------------------------

function Formulas.upgradeLevelCost(def, level: number): number
	return math.ceil(def.BaseCost * def.Growth ^ level)
end

-- Total cost to buy `count` levels starting at `level`.
function Formulas.upgradeCost(def, level: number, count: number): number
	local total = 0
	for i = 0, count - 1 do
		total += Formulas.upgradeLevelCost(def, level + i)
	end
	return total
end

-- How many levels (up to the max level) can be bought with `money`.
function Formulas.maxAffordable(def, level: number, money: number): (number, number)
	local count, total = 0, 0
	local remaining = math.min(def.MaxLevel - level, 1000)
	for i = 0, remaining - 1 do
		local cost = Formulas.upgradeLevelCost(def, level + i)
		if total + cost > money then
			break
		end
		total += cost
		count += 1
	end
	return count, total
end

function Formulas.requirementMet(requirement, data): boolean
	if not requirement then
		return true
	end
	if requirement.Level and (data.Level or 1) < requirement.Level then
		return false
	end
	if requirement.Rebirths and (data.Rebirths or 0) < requirement.Rebirths then
		return false
	end
	return true
end

function Formulas.requirementText(requirement): string
	if not requirement then
		return ""
	end
	if requirement.Rebirths then
		return "Requires " .. requirement.Rebirths .. " Ascension" .. (if requirement.Rebirths == 1 then "" else "s")
	end
	if requirement.Level then
		return "Requires level " .. requirement.Level
	end
	return ""
end

function Formulas.upgradeUnlocked(def, data): boolean
	local tier = Upgrades.Tiers[def.Tier]
	return Formulas.requirementMet(tier and tier.Requirement, data)
end

function Formulas.ascensionCost(def, level: number): number
	return math.ceil(def.BaseCost * def.Growth ^ level)
end

-- Levels and XP ----------------------------------------------------------------

-- XP needed to advance from `level` to `level + 1`.
function Formulas.xpForLevel(level: number): number
	local cfg = GameConfig.Levels
	return math.floor(cfg.BaseXP * level ^ cfg.Exponent)
end

-- Skill points granted for reaching `level`.
function Formulas.skillPointsForLevel(level: number): number
	local cfg = GameConfig.Levels
	local sp = cfg.SkillPointsPerLevel
	if level % cfg.BonusSkillPointEvery == 0 then
		sp += 1
	end
	return sp
end

-- Ascension ----------------------------------------------------------------------

function Formulas.rebirthRequirement(rebirths: number): number
	local cfg = GameConfig.Rebirth
	return cfg.BaseRequirement * cfg.RequirementGrowth ^ rebirths
end

function Formulas.rebirthPrisms(sparksThisRun: number, rebirths: number, prismMultiplier: number): number
	local cfg = GameConfig.Rebirth
	local requirement = Formulas.rebirthRequirement(rebirths)
	if sparksThisRun < requirement then
		return 0
	end
	local excess = math.min(cfg.MaxExcessFactor, sparksThisRun / requirement)
	local base = cfg.BasePrisms + cfg.PrismsPerRebirth * rebirths
	return math.max(1, math.floor(base * excess ^ cfg.ExcessExponent * prismMultiplier))
end

-- Crates ---------------------------------------------------------------------------

-- Discounts apply to Sparks crates only (Gem crates must not become cheaper than their resale).
function Formulas.chestPrice(chest, discount: number): number
	local d = if chest.Currency == "Sparks" then math.min(0.6, discount) else 0
	return math.ceil(chest.Price * (1 - d))
end

-- Bonus-drop chance for a crate (Sparks crates only, for the same reason).
function Formulas.chestBonusChance(chest, chestBonus: number): number
	return if chest.Currency == "Sparks" then chestBonus else 0
end

function Formulas.chestUnlocked(chest, data): boolean
	return Formulas.stageFor(data.Rebirths or 0).Id >= chest.Stage
end

function Formulas.pityThreshold(chest, rarityId: string, pityMultiplier: number): number?
	local base = chest.Pity and chest.Pity[rarityId]
	if not base then
		return nil
	end
	return math.max(1, math.floor(base * pityMultiplier + 0.5))
end

-- Daily quest target for a template.
function Formulas.questTarget(template, rebirths: number, clickValue: number): number
	if template.ClickScaled then
		return math.max(100, math.ceil(template.Base * math.max(1, clickValue)))
	end
	local scale = 1 + (template.ScalePerRebirth or 0) * math.min(rebirths, 20)
	local target = math.ceil(template.Base * scale)
	if template.Max then
		target = math.min(template.Max, target)
	end
	return target
end

-- Sum of sell value for a set of copies.
function Formulas.sellValue(item, count: number, gemMultiplier: number): number
	return math.floor(item.SellValue * count * gemMultiplier)
end

return Formulas
