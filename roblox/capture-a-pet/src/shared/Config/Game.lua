-- General balancing knobs. Everything gameplay-related that is a plain number lives here
-- so it can be tuned without touching the systems.

local Game = {}

Game.MaxPlayersPerServer = 6 -- must match the number of plots (set the same value in Game Settings)

-- Movement --------------------------------------------------------------------------------
-- WalkSpeed grows with the log of the Speed stat so huge numbers (10.9B) stay controllable.
Game.BaseWalkSpeed = 16
Game.WalkSpeedPerDecade = 9 -- +9 WalkSpeed for every x10 Speed
Game.MaxWalkSpeed = 260
Game.SlowModeWalkSpeed = 24
Game.CarrySpeedFactor = 0.8 -- carrying an animal or egg slows you down a bit
Game.StealCarrySpeedFactor = 0.7 -- carrying a stolen animal slows you more
Game.BaseJumpPower = 50

-- Training ---------------------------------------------------------------------------------
Game.TrainTickSeconds = 0.25

-- Income -----------------------------------------------------------------------------------
Game.IncomeTickSeconds = 1
Game.StartingPenSlots = 8
Game.MaxStorage = 250 -- animals that are not placed in the pen
Game.SellFraction = 30 -- selling an animal pays this many seconds of its income

-- Taming -----------------------------------------------------------------------------------
Game.WildAnimalsPerZone = 9
Game.WildRespawnSeconds = 6
Game.WildLifetimeSeconds = 240 -- a wild animal nobody tames despawns after this
Game.TameHoldSeconds = { 0.4, 0.6, 0.9, 1.3, 1.8, 2.4, 3.0 } -- indexed by rarity

-- Guards, nests and wild eggs ---------------------------------------------------------------
Game.NestsPerZone = 2
Game.EggRespawnSeconds = 20
Game.GuardAggroRadius = 55
Game.GuardLeashRadius = 260 -- guard gives up when the thief gets this far from the nest
Game.GuardMaxChaseSeconds = 40
Game.GuardCatchDistance = 6
Game.GuardStunSeconds = 1.5
Game.BaitDurationSeconds = 7
Game.BaitRadius = 90
Game.BaitThrowRange = 70
Game.BaitCooldownSeconds = 1

-- Escaping with an egg while a guard chases you upgrades the egg's wild aura.
-- Aura index 1 = none. The aura multiplies income and mount speed of the hatched animal.
Game.Auras = {
	{ Name = "None", ChaseSeconds = 0, IncomeMult = 1, MountMult = 1, Color = Color3.fromRGB(255, 255, 255) },
	{ Name = "Glow", ChaseSeconds = 4, IncomeMult = 1.5, MountMult = 1.05, Color = Color3.fromRGB(120, 255, 140) },
	{ Name = "Blaze", ChaseSeconds = 9, IncomeMult = 2.5, MountMult = 1.1, Color = Color3.fromRGB(255, 140, 40) },
	{ Name = "Storm", ChaseSeconds = 16, IncomeMult = 4, MountMult = 1.18, Color = Color3.fromRGB(80, 170, 255) },
	{ Name = "Void", ChaseSeconds = 25, IncomeMult = 7, MountMult = 1.28, Color = Color3.fromRGB(190, 70, 255) },
	{ Name = "Celestial", ChaseSeconds = 36, IncomeMult = 12, MountMult = 1.4, Color = Color3.fromRGB(255, 240, 120) },
}

-- Mutations roll on every wild spawn and hatch.
Game.Mutations = {
	{ Name = "Normal", Chance = 1, IncomeMult = 1 },
	{ Name = "Golden", Chance = 1 / 40, IncomeMult = 3, Color = Color3.fromRGB(255, 205, 60) },
	{ Name = "Diamond", Chance = 1 / 250, IncomeMult = 8, Color = Color3.fromRGB(120, 230, 255) },
	{ Name = "Rainbow", Chance = 1 / 1500, IncomeMult = 25 },
}

Game.Rarities = {
	{ Name = "Common", Color = Color3.fromRGB(200, 200, 200) },
	{ Name = "Uncommon", Color = Color3.fromRGB(90, 220, 90) },
	{ Name = "Rare", Color = Color3.fromRGB(70, 150, 255) },
	{ Name = "Epic", Color = Color3.fromRGB(180, 80, 255) },
	{ Name = "Legendary", Color = Color3.fromRGB(255, 170, 30) },
	{ Name = "Mythic", Color = Color3.fromRGB(255, 60, 90) },
	{ Name = "Secret", Color = Color3.fromRGB(20, 20, 20) },
}

-- Mount speed per rarity (multiplies WalkSpeed while riding).
Game.MountSpeed = { 1.08, 1.15, 1.25, 1.38, 1.55, 1.75, 2.0 }

-- Hatching ---------------------------------------------------------------------------------
Game.StartingIncubators = 2
Game.FastHatchPassMult = 3

-- Stealing ---------------------------------------------------------------------------------
Game.StealHoldSeconds = 2.5
Game.StealStopDistance = 8 -- owner within this distance of the thief takes the animal back
Game.StealMaxSeconds = 90 -- the bind breaks after this long
Game.NewAnimalProtectionSeconds = 90 -- freshly placed animals can't be stolen right away
Game.BaseLockSeconds = 60
Game.BaseLockSecondsVIP = 90
Game.BaseLockCooldownSeconds = 60 -- after the lock ends, before it can be used again
Game.NewPlayerProtectionSeconds = 180 -- your base can't be robbed during your first minutes in a server

-- Rebirth ----------------------------------------------------------------------------------
Game.RebirthBaseCost = 2.5e6
Game.RebirthCostGrowth = 6
Game.RebirthMultPerLevel = 0.5 -- +x0.5 cash and training per rebirth
Game.RebirthPenSlotEvery = 2 -- +1 pen slot every 2 rebirths
Game.RebirthMaxBonusSlots = 10

-- Social -----------------------------------------------------------------------------------
Game.FriendBoostPerFriend = 0.1
Game.FriendBoostMax = 0.5

-- Boost potions: x2 for their duration.
Game.BoostTypes = { "Training", "Cash", "Luck" }

-- Index: every discovered species gives this much extra cash.
Game.IndexCashBonusPerSpecies = 0.02

-- Eggs ---------------------------------------------------------------------------------------
-- Eggs of this rarity or higher glow with a colored aura ring; more common eggs don't.
Game.EggAuraMinRarity = 3

-- Dragon Lair event --------------------------------------------------------------------------
Game.LairEverySeconds = 12 * 60 -- time between openings
Game.LairOpenSeconds = 3 * 60 -- how long it stays open
Game.LairEggCount = 14
Game.LairEggRespawnSeconds = 8
Game.LairDragonSpeed = 70
Game.LairCenter = Vector3.new(700, 0, -300)

-- Admins -------------------------------------------------------------------------------------
-- The owner of the experience (or of its group) is always an admin. Add more UserIds here.
Game.AdminUserIds = {}

-- Saving -----------------------------------------------------------------------------------
Game.AutosaveSeconds = 60
Game.DataStoreName = "CaptureAPet_v1"

return Game
