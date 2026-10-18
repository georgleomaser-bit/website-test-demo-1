--[[
	DataSchema (ModuleScript)
	Location: ServerScriptService/Core/DataSchema
	Depends on: ReplicatedStorage/Shared/Config/*

	Defines the persisted player data format, its version, migrations from
	older versions, and sanitisation of loaded data.

	sanitize() rebuilds the data from scratch using only known keys, valid
	types and clamped ranges, so corrupted or tampered values can never reach
	the game. Item ids that no longer exist in the config are moved to
	LegacyInventory instead of being deleted, and are restored automatically
	if the item returns.

	Version history
	  1  Pre-release format: Inventory was an array of item ids (one entry per
	     copy) and Settings had a single "Volume" value.
	  2  Current format: Inventory is a map itemId -> count; Settings has
	     separate Music and SFX volumes, plus newer settings. Later additions
	     that need no migration (missing sections start empty): Passes (owned
	     game passes, a cache re-checked on every join), Boosts (seconds left
	     on bought timed boosts), Receipts (processed purchase IDs), Obby
	     (obstacle course progress) and Tutorial (first-time tutorial; data
	     saved before the tutorial existed counts as already finished).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GameConfig = require(Config.GameConfig)
local Items = require(Config.Items)
local Chests = require(Config.Chests)
local Upgrades = require(Config.Upgrades)
local Ascension = require(Config.Ascension)
local Skills = require(Config.Skills)
local Achievements = require(Config.Achievements)
local Quests = require(Config.Quests)
local Rewards = require(Config.Rewards)
local GamePasses = require(Config.GamePasses)
local DevProducts = require(Config.DevProducts)
local Obby = require(Config.Obby)
local Tutorial = require(Config.Tutorial)

local DataSchema = {}

DataSchema.CURRENT_VERSION = 2

DataSchema.StatKeys = {
	"TotalClicks",
	"AutoClicks",
	"LifetimeSparks",
	"SparksThisRun",
	"BestRunSparks",
	"ChestsOpened",
	"TotalCrits",
	"HighestCombo",
	"GoldenClicks",
	"UpgradesPurchased",
	"LegendariesFound",
	"MythicsFound",
	"SecretsFound",
	"ItemsSold",
	"QuestsCompleted",
	"OrbsCollected",
	"PlayTime",
	"GemsEarned",
	"PrismsEarned",
	"BestDailyStreak",
	"StreakBursts",
	"OfflineEarned",
}

-- Top-level sections replicated to the owning client (see SyncService).
DataSchema.Sections = {
	"Currencies",
	"Progress",
	"Upgrades",
	"Ascension",
	"Skills",
	"Inventory",
	"Favorites",
	"Equipped",
	"Discovered",
	"Chests",
	"Pity",
	"Stats",
	"Achievements",
	"CollectionClaimed",
	"Quests",
	"Daily",
	"Settings",
	"Passes",
	"Boosts",
	"Obby",
	"Tutorial",
}

local function defaultSettings()
	local settings = {}
	for key, def in pairs(GameConfig.Settings) do
		settings[key] = def.Default
	end
	return settings
end

function DataSchema.default()
	local stats = {}
	for _, key in ipairs(DataSchema.StatKeys) do
		stats[key] = 0
	end
	return {
		Version = DataSchema.CURRENT_VERSION,
		Currencies = { Sparks = 0, Gems = 0, Prisms = 0 },
		Level = 1,
		XP = 0,
		SkillPoints = 0,
		Rebirths = 0,
		Upgrades = {},
		Ascension = {},
		Skills = {},
		Inventory = {},
		LegacyInventory = {},
		Favorites = {},
		Equipped = {},
		Discovered = {},
		Chests = {},
		Pity = {},
		Stats = stats,
		Achievements = {},
		CollectionClaimed = {},
		Quests = {
			Day = -1,
			Daily = {},
			BonusClaimed = false,
			StarterIndex = 1,
			StarterProgress = 0,
		},
		Daily = { LastClaimDay = -1, Streak = 0 },
		Settings = defaultSettings(),
		-- [passKey] = true for owned game passes (written only by GamePassService).
		Passes = {},
		-- [productKey] = seconds left on a bought timed boost.
		Boosts = {},
		-- Purchase IDs of processed developer-product receipts (oldest first, bounded).
		Receipts = {},
		-- Obstacle course progress (written only by ObbyService).
		Obby = { Stage = 0, Best = 0, Completions = 0, Checkpoints = 0 },
		-- First-time tutorial (written only by TutorialService). Base holds the
		-- counters at the moment the current step started.
		Tutorial = { Step = 1, Done = false, Skipped = false, Rewarded = false, GaveCrate = false, Base = 0 },
		Meta = { Created = os.time(), LastSave = 0, LastSeen = 0, Sessions = 0 },
	}
end

-- Migrations ------------------------------------------------------------------
-- MIGRATIONS[n] upgrades data from version n to version n + 1.
local MIGRATIONS = {}

MIGRATIONS[1] = function(data)
	-- Inventory array of ids -> map of counts.
	if type(data.Inventory) == "table" and #data.Inventory > 0 then
		local counts = {}
		for _, id in ipairs(data.Inventory) do
			if type(id) == "string" then
				counts[id] = (counts[id] or 0) + 1
			end
		end
		data.Inventory = counts
	end
	-- Single volume -> separate music and sound effect volumes.
	if type(data.Settings) == "table" and type(data.Settings.Volume) == "number" then
		data.Settings.Music = data.Settings.Volume
		data.Settings.SFX = data.Settings.Volume
		data.Settings.Volume = nil
	end
	data.Version = 2
	return data
end

-- Returns migrated data and whether any migration ran. Data from a NEWER
-- version than this server knows is returned untouched with ok = false so
-- the caller can refuse to overwrite it.
function DataSchema.migrate(data): (any, boolean, boolean)
	if type(data) ~= "table" then
		return data, true, false
	end
	local version = if type(data.Version) == "number" then data.Version else 1
	if version > DataSchema.CURRENT_VERSION then
		return data, false, false
	end
	local migrated = false
	while version < DataSchema.CURRENT_VERSION do
		local step = MIGRATIONS[version]
		assert(step, "Missing migration from version " .. version)
		data = step(data)
		version = data.Version
		migrated = true
	end
	return data, true, migrated
end

-- Sanitisation ---------------------------------------------------------------------

local function isFinite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function num(value, min, max, default)
	if not isFinite(value) then
		return default
	end
	return math.clamp(value, min, max)
end

local function int(value, min, max, default)
	if not isFinite(value) then
		return default
	end
	return math.clamp(math.floor(value), min, max)
end

local function tbl(value)
	return if type(value) == "table" then value else {}
end

function DataSchema.sanitize(raw)
	local issues = {}
	local d = DataSchema.default()
	if type(raw) ~= "table" then
		table.insert(issues, "data was not a table; using defaults")
		return d, issues
	end

	local cap = GameConfig.CurrencyCap
	local currencies = tbl(raw.Currencies)
	for _, currency in ipairs(GameConfig.CurrencyOrder) do
		d.Currencies[currency] = num(currencies[currency], 0, cap, 0)
	end

	d.Level = int(raw.Level, 1, GameConfig.Levels.MaxLevel, 1)
	d.XP = num(raw.XP, 0, cap, 0)
	d.SkillPoints = int(raw.SkillPoints, 0, 1e9, 0)
	d.Rebirths = int(raw.Rebirths, 0, 1e6, 0)

	for id, level in pairs(tbl(raw.Upgrades)) do
		local def = Upgrades.ById[id]
		if def then
			local v = int(level, 0, def.MaxLevel, 0)
			if v > 0 then
				d.Upgrades[id] = v
			end
		else
			table.insert(issues, "dropped unknown upgrade " .. tostring(id))
		end
	end

	for id, level in pairs(tbl(raw.Ascension)) do
		local def = Ascension.ById[id]
		if def then
			local v = int(level, 0, def.MaxLevel, 0)
			if v > 0 then
				d.Ascension[id] = v
			end
		else
			table.insert(issues, "dropped unknown ascension upgrade " .. tostring(id))
		end
	end

	for id, rank in pairs(tbl(raw.Skills)) do
		local def = Skills.ById[id]
		if def then
			local v = int(rank, 0, def.MaxRank, 0)
			if v > 0 then
				d.Skills[id] = v
			end
		else
			table.insert(issues, "dropped unknown skill " .. tostring(id))
		end
	end

	local maxStack = GameConfig.Inventory.MaxStack
	-- Items that were legacy before but exist again are restored first.
	for id, count in pairs(tbl(raw.LegacyInventory)) do
		if type(id) == "string" and #id <= 64 then
			local c = int(count, 0, maxStack, 0)
			if c > 0 then
				if Items.ById[id] then
					d.Inventory[id] = math.min(maxStack, (d.Inventory[id] or 0) + c)
				else
					d.LegacyInventory[id] = c
				end
			end
		end
	end
	for id, count in pairs(tbl(raw.Inventory)) do
		if type(id) == "string" and #id <= 64 then
			local c = int(count, 0, maxStack, 0)
			if c > 0 then
				if Items.ById[id] then
					d.Inventory[id] = math.min(maxStack, (d.Inventory[id] or 0) + c)
				else
					d.LegacyInventory[id] = math.min(maxStack, (d.LegacyInventory[id] or 0) + c)
					table.insert(issues, "moved unknown item to legacy inventory " .. id)
				end
			end
		end
	end

	for id, fav in pairs(tbl(raw.Favorites)) do
		if fav == true and d.Inventory[id] then
			d.Favorites[id] = true
		end
	end

	local seen = {}
	for _, id in ipairs(tbl(raw.Equipped)) do
		if type(id) == "string" and d.Inventory[id] and not seen[id] and #d.Equipped < GameConfig.Equip.MaxSlots then
			seen[id] = true
			table.insert(d.Equipped, id)
		end
	end

	for id, t in pairs(tbl(raw.Discovered)) do
		if Items.ById[id] then
			d.Discovered[id] = num(t, 0, 1e12, os.time())
		end
	end
	-- Anything owned is discovered by definition.
	for id in pairs(d.Inventory) do
		if not d.Discovered[id] then
			d.Discovered[id] = os.time()
		end
	end

	for id, count in pairs(tbl(raw.Chests)) do
		if Chests.ById[id] then
			local c = int(count, 0, 1e9, 0)
			if c > 0 then
				d.Chests[id] = c
			end
		end
	end

	for id, pity in pairs(tbl(raw.Pity)) do
		local chest = Chests.ById[id]
		if chest and type(pity) == "table" then
			local entry = {}
			for rarityId in pairs(chest.Pity) do
				entry[rarityId] = int(pity[rarityId], 0, 1e6, 0)
			end
			d.Pity[id] = entry
		end
	end

	local stats = tbl(raw.Stats)
	for _, key in ipairs(DataSchema.StatKeys) do
		d.Stats[key] = num(stats[key], 0, cap, 0)
	end

	for id, t in pairs(tbl(raw.Achievements)) do
		if Achievements.ById[id] then
			d.Achievements[id] = num(t, 0, 1e12, os.time())
		end
	end

	for id, claimed in pairs(tbl(raw.CollectionClaimed)) do
		if claimed == true and Rewards.CollectionById[id] then
			d.CollectionClaimed[id] = true
		end
	end

	local quests = tbl(raw.Quests)
	d.Quests.Day = int(quests.Day, -1, 1e7, -1)
	d.Quests.BonusClaimed = quests.BonusClaimed == true
	d.Quests.StarterIndex = int(quests.StarterIndex, 1, #Quests.Starter + 1, 1)
	d.Quests.StarterProgress = num(quests.StarterProgress, 0, cap, 0)
	local dailyOk = type(quests.Daily) == "table" and #quests.Daily <= Quests.DailyCount
	if dailyOk then
		for _, q in ipairs(quests.Daily) do
			if type(q) ~= "table" or not Quests.DailyById[q.Id] then
				dailyOk = false
				break
			end
			table.insert(d.Quests.Daily, {
				Id = q.Id,
				Target = num(q.Target, 1, cap, 1),
				Progress = num(q.Progress, 0, cap, 0),
				Claimed = q.Claimed == true,
			})
		end
	end
	if not dailyOk then
		-- Regenerated by QuestService for the current day.
		d.Quests.Day = -1
		d.Quests.Daily = {}
		d.Quests.BonusClaimed = false
		table.insert(issues, "reset malformed daily quests")
	end

	local daily = tbl(raw.Daily)
	d.Daily.LastClaimDay = int(daily.LastClaimDay, -1, 1e7, -1)
	d.Daily.Streak = int(daily.Streak, 0, 1e6, 0)

	local settings = tbl(raw.Settings)
	for key, def in pairs(GameConfig.Settings) do
		local value = settings[key]
		if type(def.Default) == "boolean" then
			d.Settings[key] = if type(value) == "boolean" then value else def.Default
		elseif type(def.Default) == "number" then
			d.Settings[key] = num(value, def.Min, def.Max, def.Default)
		end
	end

	for key, owned in pairs(tbl(raw.Passes)) do
		if owned == true and GamePasses.ByKey[key] then
			d.Passes[key] = true
		end
	end

	for key, left in pairs(tbl(raw.Boosts)) do
		local product = DevProducts.ByKey[key]
		if product and product.Boost then
			local seconds = num(left, 0, DevProducts.MaxBoostSeconds, 0)
			if seconds > 0 then
				d.Boosts[key] = seconds
			end
		end
	end

	local receipts = tbl(raw.Receipts)
	local first = math.max(1, #receipts - DevProducts.ReceiptHistory + 1)
	for i = first, #receipts do
		local id = receipts[i]
		if type(id) == "string" and #id > 0 and #id <= 100 then
			table.insert(d.Receipts, id)
		end
	end

	local meta = tbl(raw.Meta)
	d.Meta.Created = num(meta.Created, 0, 1e12, os.time())
	d.Meta.LastSave = num(meta.LastSave, 0, 1e12, 0)
	d.Meta.LastSeen = num(meta.LastSeen, 0, 1e12, 0)
	d.Meta.Sessions = int(meta.Sessions, 0, 1e9, 0)

	return d, issues
end

return DataSchema
