--[[
	GameConfig (ModuleScript)
	Location: ReplicatedStorage/Shared/Config/GameConfig

	Central balance and tuning values that are shared between server and client.
	The server is always authoritative: the client only reads these values to
	render previews and timers. Changing a value here changes it everywhere.

	Nothing in this file is secret. Admin roles and permissions live in
	ServerScriptService/Admin/AdminConfig, which never replicates to clients.
]]

local GameConfig = {}

GameConfig.GameName = "Click a Button"
GameConfig.Version = "1.0.0"

-- Currencies ---------------------------------------------------------------
GameConfig.Currencies = {
	Sparks = {
		Id = "Sparks",
		Name = "Sparks",
		Icon = "⚡",
		Color = Color3.fromRGB(255, 214, 74),
		Order = 1,
		Description = "Earned by pressing the button. Spent on upgrades and crates.",
	},
	Gems = {
		Id = "Gems",
		Name = "Gems",
		Icon = "💎",
		Color = Color3.fromRGB(77, 225, 255),
		Order = 2,
		Description = "Earned from quests, achievements, golden presses and selling items.",
	},
	Prisms = {
		Id = "Prisms",
		Name = "Prisms",
		Icon = "🔷",
		Color = Color3.fromRGB(196, 125, 255),
		Order = 3,
		Description = "Ascension currency. Earned by ascending and spent on permanent upgrades.",
	},
}
GameConfig.CurrencyOrder = { "Sparks", "Gems", "Prisms" }
-- Hard cap to keep numbers finite and JSON-safe in DataStores.
GameConfig.CurrencyCap = 1e300

-- Clicking -----------------------------------------------------------------
GameConfig.Click = {
	-- Server-side click rate limiting (token bucket). Humans rarely exceed ~15 CPS.
	MaxClicksPerSecond = 20,
	BurstCapacity = 30,
	-- When a client keeps sending more than this many clicks per second, it is flagged.
	SuspiciousClicksPerSecond = 35,

	BaseCritChance = 0.02,
	MaxCritChance = 0.75,
	BaseCritMultiplier = 3,

	-- Combo: consecutive presses within ComboWindow seconds stack the combo.
	ComboWindow = 1.0,
	ComboStep = 0.01, -- +1% value per combo stack
	BaseComboCap = 100, -- stacks beyond the cap still count toward streaks
	HardComboLimit = 1000000,

	-- Streak: every StreakEvery consecutive presses awards a burst.
	StreakEvery = 50,
	StreakBurstClicks = 20, -- burst = click value * this * streak multiplier

	-- Golden presses: rare bonus rewards on manual presses.
	BaseGoldenChance = 0.004,
	MaxGoldenChance = 0.05,

	XPPerClick = 1,
	AutoClickXPFactor = 0.5,
}

-- Golden press rewards (weighted).
GameConfig.GoldenRewards = {
	{ Type = "Sparks", Weight = 50, Clicks = 150 },
	{ Type = "Gems", Weight = 30, Min = 2, Max = 6 },
	{ Type = "Chest", Weight = 15 },
	{ Type = "Frenzy", Weight = 5, Duration = 15, Multiplier = 3 },
}

-- Bonus orbs that float onto the screen for the player to tap.
GameConfig.Orbs = {
	Enabled = true,
	MinInterval = 70,
	MaxInterval = 140,
	Lifetime = 9,
	ClaimGrace = 1.5, -- extra seconds to tolerate network latency
	Rewards = {
		{ Type = "Sparks", Weight = 45, IncomeSeconds = 60, MinClicks = 120 },
		{ Type = "Gems", Weight = 25, Min = 3, Max = 8 },
		{ Type = "Chest", Weight = 15 },
		{ Type = "Frenzy", Weight = 15, Duration = 20, Multiplier = 3 },
	},
}

-- Levels and XP --------------------------------------------------------------
GameConfig.Levels = {
	BaseXP = 40,
	Exponent = 1.55,
	MaxLevel = 1000,
	SkillPointsPerLevel = 1,
	BonusSkillPointEvery = 5, -- every 5th level gives an extra skill point
	ChestEvery = 5, -- every 5th level gives a crate
	ChestXP = 6, -- XP per crate opened, multiplied by crate tier
}

-- Passive and auto clicking ------------------------------------------------------
GameConfig.Passive = {
	TickInterval = 1,
}
GameConfig.AutoClick = {
	TickInterval = 0.25,
	MaxRate = 15, -- auto presses per second (hard cap)
}

-- Offline earnings (passive income while away).
GameConfig.Offline = {
	Enabled = true,
	BaseRate = 0.25, -- 25% of passive income
	BaseMaxHours = 2,
	MinSeconds = 120,
}

-- Equipping ------------------------------------------------------------------------
GameConfig.Equip = {
	BaseSlots = 3,
	MaxSlots = 8,
	CopyBonusPerExtra = 0.1, -- each extra copy adds +10% to an equipped item's power
	MaxCopyBonus = 1.0, -- up to +100%
}

-- Item stat multipliers: how strongly an item's rarity bonus maps to each stat.
GameConfig.ItemStats = {
	sparks = { Stat = "sparksPct", Factor = 1.0, Label = "Sparks" },
	click = { Stat = "clickPct", Factor = 1.5, Label = "Click Power" },
	luck = { Stat = "luck", Factor = 0.6, Label = "Luck" },
	crit = { Stat = "critChance", Factor = 0.12, Label = "Crit Chance" },
	passive = { Stat = "passivePct", Factor = 2.0, Label = "Passive Income" },
	xp = { Stat = "xpPct", Factor = 1.5, Label = "XP Gain" },
	gems = { Stat = "gemsPct", Factor = 1.0, Label = "Gem Gain" },
	golden = { Stat = "goldenPct", Factor = 1.0, Label = "Golden Chance" },
}

-- Collection -----------------------------------------------------------------------
GameConfig.Collection = {
	SparksBonusPerItem = 0.01, -- +1% Sparks per discovered item (multiplicative group)
}

-- Inventory --------------------------------------------------------------------
GameConfig.Inventory = {
	MaxStack = 1000000000,
	-- Auto-sell setting values: 0 = off, otherwise sells duplicates up to this rarity index.
	AutoSellMaxIndex = 3,
}

-- Skill tree respec.
GameConfig.Skills = {
	RespecGemCost = 100,
}

-- Rebirth ("Ascension") -----------------------------------------------------------
GameConfig.Rebirth = {
	BaseRequirement = 3e6, -- Sparks earned this run required for the first ascension
	RequirementGrowth = 6, -- requirement multiplier per ascension
	BasePrisms = 3,
	PrismsPerRebirth = 1,
	ExcessExponent = 0.35, -- bonus prisms for overshooting the requirement
	MaxExcessFactor = 50,
	MultiplierPerRebirth = 0.5, -- permanent +50% Sparks per ascension (additive)
	ConfirmRequired = true,
}

-- Progression stages unlocked by ascending.
GameConfig.Stages = {
	{
		Id = 1,
		Name = "Neon Core",
		Rebirths = 0,
		Multiplier = 1,
		Accent = Color3.fromRGB(255, 61, 110),
		AccentDark = Color3.fromRGB(150, 20, 70),
		Description = "Where every button legend begins.",
	},
	{
		Id = 2,
		Name = "Plasma Vault",
		Rebirths = 1,
		Multiplier = 1.25,
		Accent = Color3.fromRGB(255, 140, 50),
		AccentDark = Color3.fromRGB(150, 60, 10),
		Description = "Superheated presses. Unlocks the Plasma Crate.",
	},
	{
		Id = 3,
		Name = "Void Expanse",
		Rebirths = 3,
		Multiplier = 1.6,
		Accent = Color3.fromRGB(140, 90, 255),
		AccentDark = Color3.fromRGB(60, 30, 150),
		Description = "The button echoes into nothing. Unlocks the Void Crate.",
	},
	{
		Id = 4,
		Name = "Celestial Spire",
		Rebirths = 6,
		Multiplier = 2.2,
		Accent = Color3.fromRGB(70, 200, 255),
		AccentDark = Color3.fromRGB(20, 90, 160),
		Description = "Presses that move the stars. Unlocks the Celestial Crate.",
	},
	{
		Id = 5,
		Name = "Singularity",
		Rebirths = 10,
		Multiplier = 3.2,
		Accent = Color3.fromRGB(255, 255, 255),
		AccentDark = Color3.fromRGB(120, 120, 140),
		Description = "Everything collapses into one button. Unlocks the Singularity Core.",
	},
}

-- Server-wide boost events (started by admins or the automatic scheduler).
GameConfig.Events = {
	Definitions = {
		spark_surge = {
			Id = "spark_surge",
			Name = "Spark Surge",
			Icon = "⚡",
			Description = "All Sparks ×2",
			Color = Color3.fromRGB(255, 214, 74),
			Effects = { sparksMult = 2 },
			DefaultDuration = 600,
		},
		lucky_hour = {
			Id = "lucky_hour",
			Name = "Lucky Hour",
			Icon = "🍀",
			Description = "+100% Luck on every crate",
			Color = Color3.fromRGB(74, 222, 128),
			Effects = { luck = 1.0 },
			DefaultDuration = 900,
		},
		golden_rush = {
			Id = "golden_rush",
			Name = "Golden Rush",
			Icon = "🌟",
			Description = "Golden presses ×4 more often",
			Color = Color3.fromRGB(255, 190, 40),
			Effects = { goldenMult = 4 },
			DefaultDuration = 600,
		},
		crit_frenzy = {
			Id = "crit_frenzy",
			Name = "Critical Frenzy",
			Icon = "🎯",
			Description = "+25% Crit Chance",
			Color = Color3.fromRGB(255, 80, 80),
			Effects = { critChance = 0.25 },
			DefaultDuration = 600,
		},
		knowledge_storm = {
			Id = "knowledge_storm",
			Name = "Knowledge Storm",
			Icon = "📘",
			Description = "XP ×2",
			Color = Color3.fromRGB(90, 160, 255),
			Effects = { xpMult = 2 },
			DefaultDuration = 900,
		},
	},
	Order = { "spark_surge", "lucky_hour", "golden_rush", "crit_frenzy", "knowledge_storm" },
	MaxDuration = 3 * 3600,
	MinDuration = 30,
	-- Automatic events keep servers lively without an admin present.
	AutoSchedule = {
		Enabled = true,
		Interval = 1800,
		Duration = 300,
		Pool = { "spark_surge", "lucky_hour", "golden_rush", "crit_frenzy", "knowledge_storm" },
	},
}

-- Persistence --------------------------------------------------------------------
GameConfig.Data = {
	StoreName = "ButtonAscension_PlayerData",
	KeyPrefix = "Player_",
	AutosaveInterval = 60,
	-- A session lock older than this is considered abandoned (crashed server) and may be taken over.
	LockStaleSeconds = 150,
	LoadAttempts = 8, -- retries for DataStore errors while loading
	-- While another server holds a fresh lock, loading retries every LockedRetryDelay
	-- seconds until the lock is released or becomes stale (LockStaleSeconds + 15 s).
	LockedRetryDelay = 4,
	SaveAttempts = 4,
	-- In live servers, players whose data cannot be loaded safely are kicked instead of
	-- playing on default data (which could later overwrite their real progress).
	KickOnLoadFailure = true,
	ShutdownTimeout = 25,
}

GameConfig.Leaderboards = {
	Enabled = true,
	UpdateInterval = 150,
	RefreshInterval = 120,
	TopCount = 25,
	Boards = {
		{ Id = "LifetimeSparks", Name = "Lifetime Sparks", Icon = "⚡", Stat = "LifetimeSparks", Encode = "log" },
		{ Id = "TotalClicks", Name = "Total Presses", Icon = "👆", Stat = "TotalClicks", Encode = "int" },
		{ Id = "Rebirths", Name = "Ascensions", Icon = "🔷", Stat = "Rebirths", Encode = "int" },
	},
	StorePrefix = "ButtonAscension_LB_",
}

GameConfig.Sync = {
	Interval = 0.15,
}

-- Client-side defaults for settings. The server validates every change.
GameConfig.Settings = {
	Music = { Default = 0.4, Min = 0, Max = 1 },
	SFX = { Default = 0.7, Min = 0, Max = 1 },
	UIScale = { Default = 1, Min = 0.7, Max = 1.3 },
	ReducedMotion = { Default = false },
	ScreenShake = { Default = true },
	FloatingNumbers = { Default = true },
	ConfirmRareSales = { Default = true },
	AutoSell = { Default = 0, Min = 0, Max = 3 },
	BackgroundDim = { Default = 0.35, Min = 0, Max = 0.8 },
}

return GameConfig
