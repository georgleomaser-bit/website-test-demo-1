--!strict
-- =====================================================================
--  CLUTCH CLASH – Gemeinsame Typen (Shared/Types)
--  Besitzer: WP1 (Core & Plattform). Vertrag: DESIGN.md C4 – alle Pakete
--  annotieren damit: local Types = require(Shared:WaitForChild("Types"))
--  Öffentliche API: nur Typen (export type …), zur Laufzeit eine leere Tabelle.
--  Nichts hier ändern, ohne den Vertrag in DESIGN.md mitzuändern!
-- =====================================================================

export type Lang = "de" | "en"
export type SlotName = "Primary" | "Secondary" | "Melee" | "Utility"
export type Loadout = { Primary: string, Secondary: string, Melee: string, Utility: string }
export type NotifyKind = "Info" | "Success" | "Error" | "Event" | "Alarm" | "Announce"
export type Reply = { Ok: boolean, Message: string?, [string]: any }
export type Grant = {
	Coins: number?, Gems: number?, Keys: number?, Shards: number?,
	Weapons: { string }?, Cosmetics: { string }?, FreeWeaponPicks: number?,
	PassPremium: boolean?, PassTiers: number?, XpBoostSeconds: number?,
}
export type Currency = "Coins" | "Gems" | "Keys" | "Shards"
export type WeaponKind = "Hitscan" | "Projectile" | "Melee" | "Throwable" | "Consumable"
export type ProjectileDef = {
	Speed: number, Gravity: number, Lifetime: number, Radius: number, SplashMax: number, SplashMin: number,
	Direct: number?, Bounces: number?, Restitution: number?, Fuse: number?, SelfMult: number, PopOnLand: boolean?,
}
export type MeleeDef = {
	Range: number, Cone: number, Windup: number?, Knockback: Vector3?, AirJump: boolean?,
	Block: { Mult: number, Cone: number, Max: number, Cooldown: number, MoveMult: number }?,
}
export type WeaponDef = {
	Id: number, Key: string, Slot: SlotName, Kind: WeaponKind, Name: { de: string, en: string }, Short: string,
	Damage: number, MinMult: number, HeadMult: number, FireMode: "Auto" | "Semi" | "Burst" | "Single",
	Interval: number, BurstCount: number?, BurstInterval: number?, Pellets: number, Mag: number, Reload: number,
	Equip: number, SpreadHip: number, SpreadAds: number, SpreadMove: number, SpreadAir: number,
	BloomPerShot: number, BloomMax: number, FalloffStart: number, FalloffEnd: number, Range: number,
	AdsZoom: number, AdsTime: number, MoveMult: number, AdsMoveMult: number,
	RecoilPitch: number, RecoilYaw: number, RecoilRecover: number,
	Projectile: ProjectileDef?, Melee: MeleeDef?,
	Heal: { Amount: number, Duration: number, UseTime: number }?, Smoke: { Radius: number, Duration: number }?,
	Charges: number?, Cooldown: number?, Price: number, Free: boolean, AdminOnly: boolean?,
	Model: string, Sound: string, Enabled: boolean,
}
export type CombatantKind = "Player" | "Bot" | "Dummy"
export type AmmoState = { Mag: number, ReloadUntil: number, Charges: number, CooldownUntil: number, BurstLeft: number }
export type Combatant = {
	Id: number, -- UserId (>0 live; -1..-999 Studio) | Bot -1001 abwärts | Puppe -5001 abwärts
	Kind: CombatantKind, Player: Player?, Name: string,
	Model: Model, Root: BasePart, Head: BasePart, Humanoid: Humanoid?,
	Ctx: string, Team: number, Slot: number, -- Roster-Slot 1..32 im Kontext (u8 in Buffern)
	Hp: number, MaxHp: number, Alive: boolean, ShieldUntil: number,
	Loadout: Loadout, Equipped: SlotName, EquipReadyAt: number, Ammo: { [SlotName]: AmmoState },
	Ads: boolean, AdsSince: number, Blocking: boolean, BlockUntil: number, BlockCooldownUntil: number,
	HealUntil: number, Salt: number, LastShotId: number, LastShotT: number, ShotTimes: { number },
	LastDamagerId: number?, LastDamageAt: number, Difficulty: string?, IsAdmin: boolean,
}
export type NavGraph = { Nodes: { { P: Vector3, Cover: boolean } }, Edges: { { number } } }
export type Arena = {
	Slot: number, Key: string, BuildId: number, Model: Model, Origin: CFrame,
	Spawns: { A: { CFrame }, B: { CFrame }, FFA: { CFrame } }, Zone: Vector3, ZoneRadius: number,
	KillY: number, Vault: CFrame, Nav: NavGraph, MapParams: RaycastParams,
}
export type ContextRules = {
	DamageMult: number, HeadOnly: boolean, HeadRadiusMult: number, IntervalMult: number, ReloadMult: number,
	SpeedMult: number, GravityLift: number, AllowedSlots: { [SlotName]: boolean }?, ForcedLoadout: Loadout?,
	RandomLoadout: boolean, Regen: boolean, UtilityMode: "Charges" | "Cooldown", FriendlyFire: boolean,
	IgnoreOwnership: boolean, -- Range/Practice/LuckyLoadout: jede Waffe erlaubt
}
export type ContextInfo = {
	Ctx: string, Arena: Arena, Rules: ContextRules, Recipients: () -> { Player }, MatchId: number?,
}
export type DamageInfo = { WeaponKey: string, Head: boolean, Kind: "Hitscan" | "Splash" | "Melee" | "Void" | "Admin" | "Fallback", Dist: number, From: Vector3 }
export type ElimInfo = { WeaponKey: string, Head: boolean, Kind: string, KillerId: number?, Assists: { number }, Pos: Vector3,
	KillerSliding: boolean?, Melee: boolean?, Splash: boolean?, Void: boolean? }
export type RecapHit = { W: string, D: number, H: boolean, Dist: number, T: number }
export type RecapData = { KillerId: number?, KillerName: string, KillerHp: number, WeaponKey: string, Taken: { RecapHit }, DealtToKiller: number, DealtHits: number, DealtHeads: number }
export type BotRequest = { Bot: true, Difficulty: string }
export type MatchSpec = {
	Mode: string, Teams: { { Player | BotRequest } }, Map: string?, Mood: string?, Mutator: string?,
	Tutorial: boolean?, RematchOf: number?, AdminStarted: boolean?,
}
export type PlayerResult = {
	Team: number, Won: boolean, Draw: boolean, Left: boolean, AfkRemoved: boolean, RoundsWon: number, Elims: number,
	PvpElims: number, Headshots: number, MeleeElims: number, Assists: number, Damage: number, Deaths: number,
	Mvp: boolean, Flawless: number, Clutches: number, Aces: number, OvertimeCaps: number, CrownDefences: number,
	CrownVsHuman: number, BountyClaimed: number, WeaponKills: { [string]: number }, WeaponUsed: { [string]: boolean },
	ShotsFired: number, ShotsHit: number, Comeback: boolean,
}
export type MatchResult = {
	MatchId: number, Mode: string, Map: string, Winner: number, Draw: boolean, Tainted: boolean,
	VsBots: boolean, Practice: boolean, Tutorial: boolean, Duration: number, PerPlayer: { [Player]: PlayerResult },
}
export type MapPart = {
	Shape: "Block" | "Wedge" | "Cylinder" | "Ball" | "CornerWedge", Pos: Vector3, Size: Vector3,
	Rot: Vector3?, -- Grad (X,Y,Z)
	HighEnd: number?, -- Wedge: z-Wert des hohen Endes (lokal)
	Color: string | Color3, Material: string?, Transparency: number?, CanCollide: boolean?,
	Center: boolean?, Mirror: boolean?, Tag: string?, Text: string?, -- Text = SurfaceGui-Buchstabe
	Barrier: boolean?, -- unsichtbare ArenaBarrier
}
export type MapLayout = {
	Key: string, Size: Vector3, WallHeight: number, Parts: { MapPart },
	SpawnsA: { Vector3 }, FFA: { Vector3 }?, Zone: Vector3, ZoneRadius: number?,
	CoverNodes: { Vector3 }, CustomBounds: { Min: Vector3, Max: Vector3 }?, KillY: number?,
}
export type PlayerData = { [string]: any } -- Schema siehe C13

-- Reines Typ-Modul: zur Laufzeit gibt es nichts zu holen
return {}
