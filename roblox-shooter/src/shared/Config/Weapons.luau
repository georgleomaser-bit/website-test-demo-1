--!strict
-- =====================================================================
--  CLUTCH CLASH – Waffen (Shared/Config/Weapons) -> Config.Weapons
--  Besitzer: WP3 (Kampf Server & Treffer-Mathematik). Vertrag: DESIGN.md B11.2–B11.7, C4 (WeaponDef), C15.
--  Alle Zahlen sind Startwerte aus DESIGN.md und 1:1 änderbar (ohne Code).
--  Live-Balance (Admin-Panel) darf NUR die Felder aus BalanceFields ändern – innerhalb der Grenzen.
--  ACHTUNG: wird an alle Clients repliziert -> keine Geheimnisse.
--
--  Abschnitte:
--    1) Helfer (Standardwerte, Rückstoß-Muster)
--    2) Primärwaffen (Ids 1–6)        3) Sekundärwaffen (7–9)
--    4) Nahkampf (10–12)              5) Utility (13–15)
--    6) Admin-Waffen (101–104, nur Besitzer, nie im Shop)
--    7) Start-Loadout + Live-Balance-Felder
--    8) Validate(Config): { string }
--
--  Felder je Waffe = Types.WeaponDef (C4). Ergänzungen von WP3 (Besitzer-Wunsch docs/SKILL-WUENSCHE.md,
--  nicht im Typ, optional – fehlen sie, verhält sich die Waffe wie in B11 beschrieben):
--    FirstShotMult    Streuung des ERSTEN Schusses einer Kette × Wert (Antippen lohnt sich). Server rechnet mit.
--    RecoilPattern    feste, LERNBARE Rückstoß-Folge: { { P, Y }, … } pro Schuss in der Kette.
--                     P = Faktor auf RecoilPitch, Y = Seitenkick in Vielfachen von RecoilYaw (−1..1, + = rechts).
--                     Nach dem letzten Eintrag geht es ab RecoilLoopFrom weiter. Ohne Muster: zufälliger Seitenkick (B11.1).
--    RecoilLoopFrom   Index, ab dem das Muster wiederholt wird (Standard 1)
--    AdsSettleSpread  Streuung, solange das Zielfernrohr noch nicht voll ist (Longshot "2.0 bis Fernrohr voll").
--    MobileSpread     true = Waffe ist fürs Springen/Rutschen gebaut (Schrot, Rakete): kein Rutsch-Aufschlag
--                     (Config.Player.Slide.SpreadAdd) und SpreadAir 0. Alle anderen streuen in Luft/Rutschen mehr.
--  Helfer zum Rechnen: Shared/Spread (Spread.Recoil, Spread.FirstShot).
-- =====================================================================

local Weapons = {}

type Def = { [string]: any }

-- ---------------------------------------------------------------------
-- 1) HELFER
-- ---------------------------------------------------------------------
-- Felder, die nicht jede Waffe braucht (Nahkampf/Utility haben z. B. keinen Spread)
local DEFAULTS: Def = {
	Kind = "Hitscan",
	FireMode = "Semi",
	Pellets = 1,
	Damage = 0,
	MinMult = 1,
	HeadMult = 1,
	Interval = 0.5,
	Mag = 1,
	Reload = 1,
	Equip = 0.3,
	SpreadHip = 0,
	SpreadAds = 0,
	SpreadMove = 0,
	SpreadAir = 0,
	BloomPerShot = 0,
	BloomMax = 0,
	FalloffStart = 0,
	FalloffEnd = 1,
	Range = 20,
	AdsZoom = 1,
	AdsTime = 0.15,
	MoveMult = 1,
	AdsMoveMult = 1,
	RecoilPitch = 0,
	RecoilYaw = 0,
	RecoilRecover = 0.3,
	Price = 0,
	Free = false,
	Enabled = true,
}

-- Waffe aus Standardwerten + eigenen Feldern; Model = Key (Rezept in WeaponModels, WP4)
local function weapon(fields: Def): Def
	local def: Def = table.clone(DEFAULTS)
	for key, value in pairs(fields) do
		def[key] = value
	end
	if def.Model == nil then
		def.Model = def.Key
	end
	return def
end

-- ---------------------------------------------------------------------
-- 2) PRIMÄRWAFFEN (B11.2)
-- ---------------------------------------------------------------------
local PopRifle = weapon({
	Id = 1,
	Key = "PopRifle",
	Slot = "Primary",
	Kind = "Hitscan",
	Name = { de = "Pop-Gewehr", en = "Pop Rifle" },
	Short = "RIFLE",
	FireMode = "Auto",
	Damage = 15,
	MinMult = 0.67,
	HeadMult = 1.5,
	Interval = 0.10,
	Mag = 30,
	Reload = 2.0,
	Equip = 0.40,
	SpreadHip = 2.0,
	SpreadAds = 0.5,
	SpreadMove = 1.0,
	SpreadAir = 3,
	BloomPerShot = 0.15,
	BloomMax = 1.5,
	FalloffStart = 60,
	FalloffEnd = 180,
	Range = 500,
	AdsZoom = 1.3,
	AdsTime = 0.18,
	MoveMult = 1.00,
	AdsMoveMult = 0.75,
	RecoilPitch = 0.32,
	RecoilYaw = 0.12,
	RecoilRecover = 0.35,
	-- Muster: 4 Schüsse gerade hoch, dann leicht rechts, dann links (lernbar wie ein "7")
	FirstShotMult = 0.5,
	RecoilPattern = {
		{ 1.0, 0 },
		{ 1.0, 0 },
		{ 1.1, 0.2 },
		{ 1.1, 0.1 },
		{ 1.2, 0.6 },
		{ 1.1, 0.8 },
		{ 1.0, 0.6 },
		{ 0.9, -0.4 },
		{ 0.9, -0.8 },
		{ 0.9, -1.0 },
		{ 0.8, -0.6 },
		{ 0.8, 0.4 },
		{ 0.8, 0.8 },
		{ 0.8, 0.2 },
	},
	RecoilLoopFrom = 8,
	Price = 0,
	Free = true,
	Sound = "RifleShot",
})

local BuzzSMG = weapon({
	Id = 2,
	Key = "BuzzSMG",
	Slot = "Primary",
	Kind = "Hitscan",
	Name = { de = "Summ-MP", en = "Buzz SMG" },
	Short = "SMG",
	FireMode = "Auto",
	Damage = 11,
	MinMult = 0.55,
	HeadMult = 1.4,
	Interval = 0.065,
	Mag = 35,
	Reload = 1.8,
	Equip = 0.30,
	SpreadHip = 2.6,
	SpreadAds = 1.5,
	SpreadMove = 0.6,
	SpreadAir = 2,
	BloomPerShot = 0.12,
	BloomMax = 1.2,
	FalloffStart = 25,
	FalloffEnd = 80,
	Range = 300,
	AdsZoom = 1.15,
	AdsTime = 0.14,
	MoveMult = 1.05,
	AdsMoveMult = 0.85,
	RecoilPitch = 0.22,
	RecoilYaw = 0.18,
	RecoilRecover = 0.3,
	-- Muster: zittert seitlich hin und her (Zickzack), wenig Steigung
	FirstShotMult = 0.75,
	RecoilPattern = {
		{ 1.0, 0 },
		{ 1.0, 0.5 },
		{ 1.0, -0.5 },
		{ 1.1, 0.8 },
		{ 1.1, -0.8 },
		{ 1.0, 1.0 },
		{ 0.9, -1.0 },
		{ 0.9, 0.6 },
		{ 0.9, -0.6 },
		{ 0.8, 0.3 },
	},
	RecoilLoopFrom = 4,
	Price = 600,
	Sound = "SmgShot",
})

local BurstBlaster = weapon({
	Id = 3,
	Key = "BurstBlaster",
	Slot = "Primary",
	Kind = "Hitscan",
	Name = { de = "Salven-Blaster", en = "Burst Blaster" },
	Short = "BURST",
	FireMode = "Burst",
	Damage = 19,
	MinMult = 0.68,
	HeadMult = 1.5,
	Interval = 0.32, -- Pause nach jeder Salve
	BurstCount = 3,
	BurstInterval = 0.07,
	Mag = 24,
	Reload = 2.2,
	Equip = 0.45,
	SpreadHip = 1.8,
	SpreadAds = 0.35,
	SpreadMove = 0.8,
	SpreadAir = 3,
	BloomPerShot = 0.10,
	BloomMax = 0.6,
	FalloffStart = 70,
	FalloffEnd = 200,
	Range = 600,
	AdsZoom = 1.5,
	AdsTime = 0.20,
	MoveMult = 0.97,
	AdsMoveMult = 0.70,
	RecoilPitch = 0.45,
	RecoilYaw = 0.10,
	RecoilRecover = 0.4,
	-- Muster pro Salve: hoch, hoch-rechts, hoch-links (die Kette reißt in der Salven-Pause nicht)
	FirstShotMult = 0.6,
	RecoilPattern = {
		{ 1.0, 0 },
		{ 1.0, 0.6 },
		{ 1.0, -0.6 },
	},
	RecoilLoopFrom = 1,
	Price = 1200,
	Sound = "RifleShot",
})

local Scatter = weapon({
	Id = 4,
	Key = "Scatter",
	Slot = "Primary",
	Kind = "Hitscan",
	Name = { de = "Streuer", en = "Scatter" },
	Short = "SCATTER",
	FireMode = "Semi",
	Damage = 12, -- je Schrot
	Pellets = 8,
	MinMult = 0.25,
	HeadMult = 1.5,
	Interval = 0.85,
	Mag = 6,
	Reload = 2.4,
	Equip = 0.50,
	SpreadHip = 6.0, -- Kegel
	SpreadAds = 4.5,
	FalloffStart = 10,
	FalloffEnd = 32,
	Range = 120,
	AdsZoom = 1.15,
	AdsTime = 0.16,
	MoveMult = 1.00,
	AdsMoveMult = 0.80,
	RecoilPitch = 3.0,
	RecoilYaw = 0.5,
	RecoilRecover = 0.5,
	RecoilPattern = { { 1.0, 0.3 } }, -- immer gleich: kräftig hoch, leicht rechts
	MobileSpread = true, -- Schrot ist für Rutschen/Springen gebaut
	Price = 600,
	Sound = "ShotgunShot",
})

local Longshot = weapon({
	Id = 5,
	Key = "Longshot",
	Slot = "Primary",
	Kind = "Hitscan",
	Name = { de = "Fernschuss", en = "Longshot" },
	Short = "LONGSHOT",
	FireMode = "Single", -- Bolzen
	Damage = 55,
	MinMult = 1.0, -- kein Abfall
	HeadMult = 2.5,
	Interval = 1.30,
	Mag = 5,
	Reload = 2.6,
	Equip = 0.60,
	SpreadHip = 7.0,
	SpreadAds = 0,
	SpreadMove = 1.5, -- nur über Config.Combat.MovingSpeed (ADS-Gehen 8.8 bleibt präzise)
	SpreadAir = 4, -- Sprung-Scope ist Glück, kein Skill (SKILL-WUENSCHE: Springen = mehr Streuung)
	AdsSettleSpread = 2.0, -- bis das Fernrohr voll ist (Quickscope möglich, aber nicht perfekt)
	FalloffStart = 500, -- "kein" Abfall (MinMult 1.0)
	FalloffEnd = 1500,
	Range = 1500,
	AdsZoom = 4.0,
	AdsTime = 0.32,
	MoveMult = 0.92,
	AdsMoveMult = 0.55,
	RecoilPitch = 4.5,
	RecoilYaw = 0.3,
	RecoilRecover = 0.6,
	RecoilPattern = { { 1.0, -0.3 } },
	Price = 2000,
	Sound = "SniperShot",
})

local PopRocket = weapon({
	Id = 6,
	Key = "PopRocket",
	Slot = "Primary",
	Kind = "Projectile",
	Name = { de = "Plopp-Rakete", en = "Pop Rocket" },
	Short = "ROCKET",
	FireMode = "Semi",
	Damage = 70, -- Direkttreffer (= Projectile.Direct)
	Interval = 0.90,
	Mag = 2,
	Reload = 2.4,
	Equip = 0.60,
	SpreadHip = 0.5,
	SpreadAds = 0.2,
	FalloffStart = 0,
	FalloffEnd = 1,
	Range = 480,
	AdsZoom = 1.2,
	AdsTime = 0.20,
	MoveMult = 0.90,
	AdsMoveMult = 0.75,
	RecoilPitch = 2.5,
	RecoilYaw = 0.2,
	RecoilRecover = 0.5,
	MobileSpread = true, -- Raketensprung + Schuss aus der Luft ist gewollte Technik
	Projectile = {
		Speed = 120,
		Gravity = 0,
		Lifetime = 4,
		Radius = 11, -- Splash-Radius
		SplashMax = 60,
		SplashMin = 15,
		Direct = 70,
		SelfMult = 0.4, -- Raketensprung kostet 40 %
	},
	Price = 2500,
	Sound = "RocketLaunch",
})

-- ---------------------------------------------------------------------
-- 3) SEKUNDÄRWAFFEN (B11.3)
--    Nicht in der Tabelle (WP3-Startwerte): AdsTime, AdsMoveMult, Bloom (Pistolen).
-- ---------------------------------------------------------------------
local PipPistol = weapon({
	Id = 7,
	Key = "PipPistol",
	Slot = "Secondary",
	Kind = "Hitscan",
	Name = { de = "Pieps-Pistole", en = "Pip Pistol" },
	Short = "PISTOL",
	FireMode = "Semi",
	Damage = 22,
	MinMult = 0.64,
	HeadMult = 1.6,
	Interval = 0.15,
	Mag = 12,
	Reload = 1.4,
	Equip = 0.25,
	SpreadHip = 1.2,
	SpreadAds = 0.35,
	SpreadMove = 0.6,
	SpreadAir = 2,
	BloomPerShot = 0.10,
	BloomMax = 0.8,
	FalloffStart = 40,
	FalloffEnd = 110,
	Range = 400,
	AdsZoom = 1.25,
	AdsTime = 0.15,
	MoveMult = 1.03,
	AdsMoveMult = 0.85,
	RecoilPitch = 1.0,
	RecoilYaw = 0.2,
	RecoilRecover = 0.25,
	FirstShotMult = 0.6,
	RecoilPattern = { { 1.0, 0 }, { 1.0, 0.5 }, { 1.0, -0.5 } },
	Price = 0,
	Free = true,
	Sound = "PistolShot",
})

local HandCannon = weapon({
	Id = 8,
	Key = "HandCannon",
	Slot = "Secondary",
	Kind = "Hitscan",
	Name = { de = "Hand-Kanone", en = "Hand Cannon" },
	Short = "CANNON",
	FireMode = "Semi",
	Damage = 42,
	MinMult = 0.67,
	HeadMult = 1.75,
	Interval = 0.45,
	Mag = 6,
	Reload = 2.3,
	Equip = 0.35,
	SpreadHip = 1.2,
	SpreadAds = 0.2,
	SpreadMove = 0.8,
	SpreadAir = 2.5,
	BloomPerShot = 0.25,
	BloomMax = 1.0,
	FalloffStart = 50,
	FalloffEnd = 140,
	Range = 450,
	AdsZoom = 1.3,
	AdsTime = 0.18,
	MoveMult = 1.00,
	AdsMoveMult = 0.80,
	RecoilPitch = 3.2,
	RecoilYaw = 0.6,
	RecoilRecover = 0.4,
	FirstShotMult = 0.5,
	RecoilPattern = { { 1.0, 0.5 }, { 1.0, -0.5 } },
	Price = 1200,
	Sound = "CannonShot",
})

local MiniScatter = weapon({
	Id = 9,
	Key = "MiniScatter",
	Slot = "Secondary",
	Kind = "Hitscan",
	Name = { de = "Mini-Streuer", en = "Mini Scatter" },
	Short = "MINI",
	FireMode = "Semi",
	Damage = 12, -- je Schrot
	Pellets = 6,
	MinMult = 0.25,
	HeadMult = 1.4,
	Interval = 0.25,
	Mag = 2,
	Reload = 1.9,
	Equip = 0.30,
	SpreadHip = 7.5, -- Kegel
	SpreadAds = 6.5,
	FalloffStart = 8,
	FalloffEnd = 24,
	Range = 80,
	AdsZoom = 1.1,
	AdsTime = 0.14,
	MoveMult = 1.03,
	AdsMoveMult = 0.85,
	RecoilPitch = 3.5,
	RecoilYaw = 0.8,
	RecoilRecover = 0.4,
	RecoilPattern = { { 1.0, 0.4 }, { 1.0, -0.4 } },
	MobileSpread = true,
	Price = 600,
	Sound = "ShotgunShot",
})

-- ---------------------------------------------------------------------
-- 4) NAHKAMPF (B11.4) – kein Kopf-Bonus; Server prüft Reichweite + Kegel + Sichtlinie
--    Knockback = Vector3.new(horizontal, hoch, 0) in Studs/s
-- ---------------------------------------------------------------------
local BoxingGloves = weapon({
	Id = 10,
	Key = "BoxingGloves",
	Slot = "Melee",
	Kind = "Melee",
	Name = { de = "Boxhandschuhe", en = "Boxing Gloves" },
	Short = "GLOVES",
	FireMode = "Semi",
	Damage = 35,
	Interval = 0.40,
	Equip = 0.25,
	Range = 6.5,
	MoveMult = 1.15,
	AdsMoveMult = 1.15,
	Melee = { Range = 6.5, Cone = 70, AirJump = true }, -- Doppelsprung solange ausgerüstet
	Price = 0,
	Free = true,
	Sound = "MeleeSwing",
})

local BonkHammer = weapon({
	Id = 11,
	Key = "BonkHammer",
	Slot = "Melee",
	Kind = "Melee",
	Name = { de = "Bonk-Hammer", en = "Bonk Hammer" },
	Short = "HAMMER",
	FireMode = "Semi",
	Damage = 70,
	Interval = 0.90,
	Equip = 0.35,
	Range = 7,
	MoveMult = 1.05,
	AdsMoveMult = 1.05,
	Melee = { Range = 7, Cone = 80, Windup = 0.35, Knockback = Vector3.new(55, 30, 0) },
	Price = 1500,
	Sound = "MeleeSwing",
})

local LaserSword = weapon({
	Id = 12,
	Key = "LaserSword",
	Slot = "Melee",
	Kind = "Melee",
	Name = { de = "Laserschwert", en = "Laser Sword" },
	Short = "SWORD",
	FireMode = "Semi",
	Damage = 45,
	Interval = 0.55,
	Equip = 0.30,
	Range = 8,
	MoveMult = 1.10,
	AdsMoveMult = 0.65,
	Melee = {
		Range = 8,
		Cone = 70,
		-- ADS halten = Blocken: Schaden von vorn ×0.4, max. 1.5 s, danach 3 s Abklingzeit, Tempo ×0.65
		Block = { Mult = 0.4, Cone = 75, Max = 1.5, Cooldown = 3, MoveMult = 0.65 },
	},
	Price = 1200,
	Sound = "MeleeSwing",
})

-- ---------------------------------------------------------------------
-- 5) UTILITY (B11.5) – Duelle: Ladungen pro Runde, FFA: Abklingzeit
--    Wurf: Tippen = Projectile.Speed (70), 0.5 s halten = Config.Combat.ThrowChargedSpeed (90)
-- ---------------------------------------------------------------------
local PopGrenade = weapon({
	Id = 13,
	Key = "PopGrenade",
	Slot = "Utility",
	Kind = "Throwable",
	Name = { de = "Plopp-Granate", en = "Pop Grenade" },
	Short = "GRENADE",
	Damage = 95,
	Interval = 0.6,
	Equip = 0.20,
	Range = 300,
	Projectile = {
		Speed = 70,
		Gravity = 90,
		Lifetime = 2.0,
		Radius = 13,
		SplashMax = 95,
		SplashMin = 10,
		Bounces = 2,
		Restitution = 0.35,
		Fuse = 2.0, -- ab Wurf
		SelfMult = 0.5,
	},
	Charges = 1,
	Cooldown = 14,
	Price = 0,
	Free = true,
	Sound = "MeleeSwing",
})

local SmokeBomb = weapon({
	Id = 14,
	Key = "SmokeBomb",
	Slot = "Utility",
	Kind = "Throwable",
	Name = { de = "Rauchbombe", en = "Smoke Bomb" },
	Short = "SMOKE",
	Interval = 0.6,
	Equip = 0.20,
	Range = 300,
	Projectile = {
		Speed = 70,
		Gravity = 90,
		Lifetime = 2.0,
		Radius = 13,
		SplashMax = 0,
		SplashMin = 0,
		Bounces = 0,
		Fuse = 2.0, -- spätestens nach 2.0 s
		SelfMult = 0,
		PopOnLand = true, -- platzt bei der ersten Landung
	},
	Smoke = { Radius = 13, Duration = 9 }, -- blockiert Bot-Sicht und Zielhilfe (nicht Kugeln)
	Charges = 1,
	Cooldown = 18,
	Price = 600,
	Sound = "MeleeSwing",
})

local MedFizz = weapon({
	Id = 15,
	Key = "MedFizz",
	Slot = "Utility",
	Kind = "Consumable",
	Name = { de = "Heil-Limo", en = "Med Fizz" },
	Short = "FIZZ",
	Interval = 0.8,
	Equip = 0.20,
	Range = 0,
	-- 0.8 s trinken (kein Schießen), dann +50 HP über 2.5 s (+5 alle 0.25 s), Abbruch bei Schaden
	Heal = { Amount = 50, Duration = 2.5, UseTime = 0.8 },
	Charges = 1,
	Cooldown = 20,
	Price = 1200,
	Sound = "Heal",
})

-- ---------------------------------------------------------------------
-- 6) ADMIN-WAFFEN (B11.7) – nur Besitzer, in den Primary-Slot, taint das Match
--    Sonderverhalten in WeaponService/ProjectileService, Zahlen in Config.Combat.Admin
-- ---------------------------------------------------------------------
local OrbitalLaser = weapon({
	Id = 101,
	Key = "OrbitalLaser",
	Slot = "Primary",
	Kind = "Hitscan",
	Name = { de = "Orbital-Laser", en = "Orbital Laser" },
	Short = "ORBITAL",
	FireMode = "Single",
	Damage = 999,
	Interval = 2.0, -- Cooldown 2 s
	Mag = 1,
	Reload = 0.3,
	Equip = 0.30,
	Range = 1000, -- Markier-Strahl
	FalloffStart = 500,
	FalloffEnd = 1500,
	AdsZoom = 1.5,
	AdsTime = 0.2,
	RecoilPitch = 1,
	AdminOnly = true,
	Sound = "Explosion",
})

local RocketMinigun = weapon({
	Id = 102,
	Key = "RocketMinigun",
	Slot = "Primary",
	Kind = "Projectile",
	Name = { de = "Raketen-Minigun", en = "Rocket Minigun" },
	Short = "MINIGUN",
	FireMode = "Auto",
	Damage = 40,
	Interval = 0.10, -- nach 0.4 s Anlauf (Client)
	Mag = 100,
	Reload = 3,
	Equip = 0.40,
	SpreadHip = 2.5,
	SpreadAds = 1.5,
	Range = 480,
	AdsZoom = 1.1,
	AdsTime = 0.2,
	MoveMult = 0.85,
	AdsMoveMult = 0.7,
	RecoilPitch = 0.4,
	RecoilYaw = 0.3,
	Projectile = {
		Speed = 120,
		Gravity = 0,
		Lifetime = 4,
		Radius = 8,
		SplashMax = 40,
		SplashMin = 10,
		Direct = 40,
		SelfMult = 0,
	},
	AdminOnly = true,
	Sound = "RocketLaunch",
})

local BlackHoleCannon = weapon({
	Id = 103,
	Key = "BlackHoleCannon",
	Slot = "Primary",
	Kind = "Projectile",
	Name = { de = "Schwarzes-Loch-Kanone", en = "Black Hole Cannon" },
	Short = "BLACKHOLE",
	FireMode = "Single",
	Damage = 150, -- Implosion
	Interval = 1.5,
	Mag = 4,
	Reload = 2.5,
	Equip = 0.50,
	SpreadHip = 0.5,
	SpreadAds = 0.2,
	Range = 400,
	AdsZoom = 1.2,
	AdsTime = 0.2,
	MoveMult = 0.9,
	AdsMoveMult = 0.75,
	RecoilPitch = 2,
	Projectile = {
		Speed = 40,
		Gravity = 0,
		Lifetime = 6,
		Radius = 18, -- Wirbel-Schadensradius (Zug bis 25: Config.Combat.Admin.VortexPullRadius)
		SplashMax = 150,
		SplashMin = 150,
		SelfMult = 0,
	},
	AdminOnly = true,
	Sound = "Explosion",
})

local LightningRifle = weapon({
	Id = 104,
	Key = "LightningRifle",
	Slot = "Primary",
	Kind = "Hitscan",
	Name = { de = "Blitz-Gewehr", en = "Lightning Rifle" },
	Short = "LIGHTNING",
	FireMode = "Semi",
	Damage = 80, -- je Ziel, springt auf bis zu 4 weitere Ziele ≤ 20 Studs
	Interval = 0.5,
	Mag = 10,
	Reload = 2,
	Equip = 0.40,
	SpreadHip = 1.0,
	SpreadAds = 0.2,
	FalloffStart = 500,
	FalloffEnd = 1500,
	Range = 500,
	AdsZoom = 1.3,
	AdsTime = 0.2,
	RecoilPitch = 1.2,
	RecoilYaw = 0.3,
	AdminOnly = true,
	Sound = "RifleShot",
})

Weapons.List = {
	PopRifle,
	BuzzSMG,
	BurstBlaster,
	Scatter,
	Longshot,
	PopRocket,
	PipPistol,
	HandCannon,
	MiniScatter,
	BoxingGloves,
	BonkHammer,
	LaserSword,
	PopGrenade,
	SmokeBomb,
	MedFizz,
	OrbitalLaser,
	RocketMinigun,
	BlackHoleCannon,
	LightningRifle,
}

-- ---------------------------------------------------------------------
-- 7) START-LOADOUT + LIVE-BALANCE-FELDER (C15)
-- ---------------------------------------------------------------------
Weapons.DefaultLoadout =
	{ Primary = "PopRifle", Secondary = "PipPistol", Melee = "BoxingGloves", Utility = "PopGrenade" }

-- Nur diese Felder darf das Admin-Panel live ändern – geklemmt auf {min, max}
Weapons.BalanceFields = {
	Damage = { 1, 200 },
	MinMult = { 0.1, 1 },
	HeadMult = { 1, 4 },
	Interval = { 0.04, 3 },
	Mag = { 1, 100 },
	Reload = { 0.3, 6 },
	Equip = { 0.1, 2 },
	SpreadHip = { 0, 15 },
	SpreadAds = { 0, 10 },
	FalloffStart = { 0, 500 },
	FalloffEnd = { 1, 1500 },
	Range = { 20, 1500 },
	MoveMult = { 0.6, 1.3 },
	["Projectile.SplashMax"] = { 0, 300 },
	["Projectile.Radius"] = { 2, 25 },
	["Melee.Range"] = { 3, 12 },
}

-- ---------------------------------------------------------------------
-- 8) PRÜFEN (leere Liste = alles ok)
-- ---------------------------------------------------------------------
local SLOTS = { Primary = true, Secondary = true, Melee = true, Utility = true }
local KINDS = { Hitscan = true, Projectile = true, Melee = true, Throwable = true, Consumable = true }
local FIRE_MODES = { Auto = true, Semi = true, Burst = true, Single = true }
-- Balance-Felder, die nur Fernkampfwaffen (Hitscan/Projectile) sinnvoll nutzen
local RANGED_ONLY = {
	MinMult = true,
	HeadMult = true,
	Mag = true,
	Reload = true,
	SpreadHip = true,
	SpreadAds = true,
	FalloffStart = true,
	FalloffEnd = true,
	Range = true,
}

local function isNum(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isRanged(def: Def): boolean
	return def.Kind == "Hitscan" or def.Kind == "Projectile"
end

-- WeaponModels (WP4) erst beim Prüfen laden (Config darf beim Start nichts Fremdes brauchen)
local function recipeCheck(): ((string) -> boolean)?
	local ok, result = pcall(function()
		local shared = script.Parent and script.Parent.Parent
		local module = shared and shared:FindFirstChild("WeaponModels")
		if module and module:IsA("ModuleScript") then
			return (require :: any)(module)
		end
		return nil
	end)
	if ok and type(result) == "table" and type(result.HasRecipe) == "function" then
		return function(key: string): boolean
			local okHas, has = pcall(result.HasRecipe, key)
			return okHas and has == true
		end
	end
	return nil
end

local function checkWeapon(errors: { string }, index: number, def: Def, hasRecipe: ((string) -> boolean)?)
	local path = ("Config.Weapons.List[%d]"):format(index)
	if type(def.Key) == "string" then
		path = "Config.Weapons." .. def.Key
	end
	local function add(text: string)
		table.insert(errors, path .. text)
	end
	local function num(field: string, value: any, min: number, max: number?)
		if not isNum(value) then
			add("." .. field .. ": Zahl erwartet")
		elseif value < min or (max ~= nil and value > max) then
			add(
				("." .. field .. ": %s außerhalb [%s, %s]"):format(
					tostring(value),
					tostring(min),
					tostring(max or "∞")
				)
			)
		end
	end

	if not isNum(def.Id) or def.Id % 1 ~= 0 or def.Id < 1 or def.Id > 255 then
		add(".Id: ganze Zahl 1..255 erwartet (u8)")
	end
	if not SLOTS[def.Slot] then
		add(".Slot: Primary/Secondary/Melee/Utility erwartet")
	end
	if not KINDS[def.Kind] then
		add(".Kind: unbekannt (" .. tostring(def.Kind) .. ")")
	end
	if not FIRE_MODES[def.FireMode] then
		add(".FireMode: Auto/Semi/Burst/Single erwartet")
	end
	if type(def.Name) ~= "table" or type(def.Name.de) ~= "string" or type(def.Name.en) ~= "string" then
		add(".Name: { de, en } erwartet")
	end
	if type(def.Short) ~= "string" or def.Short == "" then
		add(".Short: Text erwartet")
	end
	if type(def.Model) ~= "string" or def.Model == "" then
		add(".Model: Text erwartet")
	elseif hasRecipe and not hasRecipe(def.Model) then
		add(".Model: kein Rezept in WeaponModels (" .. def.Model .. ")")
	end
	if type(def.Sound) ~= "string" then
		add(".Sound: Text erwartet")
	end
	if type(def.Enabled) ~= "boolean" or type(def.Free) ~= "boolean" then
		add(".Enabled/.Free: boolean erwartet")
	end
	if not isNum(def.Pellets) or def.Pellets < 1 or def.Pellets % 1 ~= 0 or def.Pellets > 32 then
		add(".Pellets: ganze Zahl >= 1 (max. 32) erwartet")
	end
	num("Price", def.Price, 0)
	if def.AdminOnly and def.Price ~= 0 then
		add(".Price: Admin-Waffen sind nie im Shop (Preis 0)")
	end

	-- Live-Balance-Felder: vorhandene Zahlen müssen in den Grenzen liegen
	for field, bounds in pairs(Weapons.BalanceFields) do
		local value: any = def[field]
		local dot = string.find(field, ".", 1, true)
		if dot then
			local nested = def[string.sub(field, 1, dot - 1)]
			value = if type(nested) == "table" then nested[string.sub(field, dot + 1)] else nil
		end
		local relevant = value ~= nil and not def.AdminOnly -- Admin-Waffen werden nicht live balanciert
		if relevant and not dot then
			if RANGED_ONLY[field] then
				relevant = isRanged(def)
			elseif field == "Damage" then
				relevant = isRanged(def) or def.Kind == "Melee" or (isNum(value) and value > 0)
			end
		end
		if relevant then
			num(field, value, bounds[1], bounds[2])
		end
	end

	-- weitere Zahlen (keine Balance-Felder)
	num("SpreadMove", def.SpreadMove, 0, 30)
	num("SpreadAir", def.SpreadAir, 0, 30)
	num("BloomPerShot", def.BloomPerShot, 0, 10)
	num("BloomMax", def.BloomMax, 0, 30)
	num("AdsZoom", def.AdsZoom, 1, 10)
	num("AdsTime", def.AdsTime, 0, 2)
	num("AdsMoveMult", def.AdsMoveMult, 0.3, 1.5)
	num("RecoilPitch", def.RecoilPitch, 0, 20)
	num("RecoilYaw", def.RecoilYaw, 0, 10)
	num("RecoilRecover", def.RecoilRecover, 0, 5)
	num("Interval", def.Interval, 0.04, 3)
	num("Equip", def.Equip, 0, 2)
	if isRanged(def) then
		if isNum(def.FalloffStart) and isNum(def.FalloffEnd) and def.FalloffEnd < def.FalloffStart then
			add(".FalloffEnd: muss >= FalloffStart sein")
		end
	end
	if def.FireMode == "Burst" then
		num("BurstCount", def.BurstCount, 2, 10)
		num("BurstInterval", def.BurstInterval, 0.02, 1)
	end
	if def.FirstShotMult ~= nil then
		num("FirstShotMult", def.FirstShotMult, 0, 1)
	end
	if def.AdsSettleSpread ~= nil then
		num("AdsSettleSpread", def.AdsSettleSpread, 0, 15)
	end
	if def.RecoilPattern ~= nil then
		local pattern = def.RecoilPattern
		if type(pattern) ~= "table" or #pattern == 0 or #pattern > 64 then
			add(".RecoilPattern: Liste mit 1..64 Einträgen { P, Y } erwartet")
		else
			for i, step in ipairs(pattern) do
				if type(step) ~= "table" or not isNum(step[1]) or not isNum(step[2]) or math.abs(step[2]) > 1.5 then
					add((".RecoilPattern[%d]: { P (Zahl), Y (−1.5..1.5) } erwartet"):format(i))
				end
			end
			if def.RecoilLoopFrom ~= nil then
				num("RecoilLoopFrom", def.RecoilLoopFrom, 1, #pattern)
			end
		end
	end

	-- Art-spezifische Teile
	local proj = def.Projectile
	if def.Kind == "Projectile" or def.Kind == "Throwable" then
		if type(proj) ~= "table" then
			add(".Projectile: Tabelle erwartet (Kind " .. tostring(def.Kind) .. ")")
		else
			num("Projectile.Speed", proj.Speed, 1, 1000)
			num("Projectile.Gravity", proj.Gravity, 0, 500)
			num("Projectile.Lifetime", proj.Lifetime, 0.1, 20)
			num("Projectile.Radius", proj.Radius, 0, 50)
			num("Projectile.SplashMax", proj.SplashMax, 0, 1000)
			num("Projectile.SplashMin", proj.SplashMin, 0, 1000)
			num("Projectile.SelfMult", proj.SelfMult, 0, 1)
			if proj.Direct ~= nil then
				num("Projectile.Direct", proj.Direct, 0, 1000)
			end
			if proj.Bounces ~= nil then
				num("Projectile.Bounces", proj.Bounces, 0, 10)
			end
			if proj.Restitution ~= nil then
				num("Projectile.Restitution", proj.Restitution, 0, 1)
			end
			if proj.Fuse ~= nil then
				num("Projectile.Fuse", proj.Fuse, 0.05, 20)
			end
		end
	elseif proj ~= nil then
		add(".Projectile: nur bei Kind Projectile/Throwable")
	end
	if def.Kind == "Melee" then
		local melee = def.Melee
		if type(melee) ~= "table" then
			add(".Melee: Tabelle erwartet")
		else
			num("Melee.Range", melee.Range, 1, 30)
			num("Melee.Cone", melee.Cone, 1, 360)
			if melee.Windup ~= nil then
				num("Melee.Windup", melee.Windup, 0, 2)
			end
			if melee.Knockback ~= nil and typeof(melee.Knockback) ~= "Vector3" then
				add(".Melee.Knockback: Vector3 erwartet")
			end
			if melee.Block ~= nil then
				local block = melee.Block
				if type(block) ~= "table" then
					add(".Melee.Block: Tabelle erwartet")
				else
					num("Melee.Block.Mult", block.Mult, 0, 1)
					num("Melee.Block.Cone", block.Cone, 1, 180)
					num("Melee.Block.Max", block.Max, 0.1, 10)
					num("Melee.Block.Cooldown", block.Cooldown, 0, 30)
					num("Melee.Block.MoveMult", block.MoveMult, 0.1, 1.5)
				end
			end
		end
	end
	if def.Kind == "Consumable" then
		local heal = def.Heal
		if type(heal) ~= "table" then
			add(".Heal: Tabelle erwartet")
		else
			num("Heal.Amount", heal.Amount, 1, 500)
			num("Heal.Duration", heal.Duration, 0.25, 30)
			num("Heal.UseTime", heal.UseTime, 0, 10)
		end
	end
	if def.Smoke ~= nil then
		num("Smoke.Radius", def.Smoke.Radius, 1, 50)
		num("Smoke.Duration", def.Smoke.Duration, 0.5, 60)
	end
	if def.Slot == "Utility" then
		num("Charges", def.Charges, 1, 10)
		num("Cooldown", def.Cooldown, 0, 120)
	end
	if def.AdminOnly then
		if def.Slot ~= "Primary" then
			add(".Slot: Admin-Waffen gehören in den Primary-Slot")
		end
		if def.Id < 101 or def.Id > 104 then
			add(".Id: Admin-Waffen haben Ids 101–104")
		end
		if def.Free then
			add(".Free: Admin-Waffen sind nie gratis für andere")
		end
	end
end

function Weapons.Validate(_config: any): { string }
	local errors: { string } = {}
	local list = Weapons.List
	if type(list) ~= "table" or #list == 0 then
		table.insert(errors, "Config.Weapons.List: Liste erwartet")
		return errors
	end
	local hasRecipe = recipeCheck()
	local ids: { [number]: string } = {}
	local keys: { [string]: boolean } = {}
	local byKey: { [string]: Def } = {}
	for index, def in ipairs(list) do
		if type(def) ~= "table" then
			table.insert(errors, ("Config.Weapons.List[%d]: Tabelle erwartet"):format(index))
			continue
		end
		if type(def.Key) ~= "string" or def.Key == "" then
			table.insert(errors, ("Config.Weapons.List[%d].Key: Text erwartet"):format(index))
		elseif keys[def.Key] then
			table.insert(errors, "Config.Weapons." .. def.Key .. ": Key doppelt")
		else
			keys[def.Key] = true
			byKey[def.Key] = def
		end
		if isNum(def.Id) then
			if ids[def.Id] then
				table.insert(errors, ("Config.Weapons.List[%d].Id: %d doppelt (%s)"):format(index, def.Id, ids[def.Id]))
			else
				ids[def.Id] = tostring(def.Key)
			end
		end
		checkWeapon(errors, index, def, hasRecipe)
	end

	-- Start-Loadout: existiert, passender Slot, gratis
	local default = Weapons.DefaultLoadout
	if type(default) ~= "table" then
		table.insert(errors, "Config.Weapons.DefaultLoadout: Tabelle erwartet")
	else
		for _, slot in ipairs({ "Primary", "Secondary", "Melee", "Utility" }) do
			local key = default[slot]
			local def = if type(key) == "string" then byKey[key] else nil
			if not def then
				table.insert(errors, "Config.Weapons.DefaultLoadout." .. slot .. ": unbekannte Waffe " .. tostring(key))
			elseif def.Slot ~= slot then
				table.insert(
					errors,
					"Config.Weapons.DefaultLoadout." .. slot .. ": Waffe gehört in Slot " .. tostring(def.Slot)
				)
			elseif not def.Free then
				table.insert(errors, "Config.Weapons.DefaultLoadout." .. slot .. ": muss gratis sein (Free = true)")
			end
		end
	end

	-- Balance-Grenzen selbst
	for field, bounds in pairs(Weapons.BalanceFields) do
		if type(bounds) ~= "table" or not isNum(bounds[1]) or not isNum(bounds[2]) or bounds[1] > bounds[2] then
			table.insert(errors, "Config.Weapons.BalanceFields." .. tostring(field) .. ": {min, max} erwartet")
		end
	end
	return errors
end

return Weapons
