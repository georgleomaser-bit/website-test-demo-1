# Architecture

This document explains how Button Ascension is put together: the Explorer
hierarchy, which code runs where, how data flows between server and client,
and how security is enforced.

## Principles

1. **The server is authoritative.** Clients only send *intent*: "press",
   "buy upgrade X ×10", "open crate Y". Prices, rewards, drop chances, crits,
   combos, item generation, skill costs and admin permissions are all
   computed and validated on the server. Nothing a client sends is trusted.
2. **One source of truth for balance.** All numbers live in
   `ReplicatedStorage/Shared/Config/*`. All maths lives in
   `Shared/Formulas` and `Shared/Loot`. The server uses them to compute the
   real values; the client uses the *same* functions only to draw previews
   such as "Lv 12 → 13" or crate odds, so the two can never disagree.
3. **No circular requires.** Services never `require` each other. `Main`
   loads every service into a shared `services` table, calls `Init(services)`
   on each (wiring and action registration), then `Start()` (loops) in a
   fixed order.
4. **Pure data operations.** Every write to player data goes through
   `Core/DataOps` (clamped, non-yielding). The same functions power online
   gameplay and the lock-checked offline admin edits inside `UpdateAsync`.
5. **The UI is built in code.** `StarterGui` is empty on purpose. The
   interface is created by `ClientMain` and the screen modules. This keeps
   every element in version control, adapts it to any screen size, and lets
   the test harness check every property against the Roblox API.

## Explorer hierarchy

Script types: **Script** runs on the server, **LocalScript** runs on the
client, and **ModuleScript** is required by other scripts.

```
game
├── Workspace  — Arena (Model) — built at runtime by WorldService
├── Players
├── Lighting  — Atmosphere, Bloom, ColorCorrection — added at runtime by WorldService
├── ReplicatedStorage
│   ├── Remotes  (Folder, created at runtime by Remotes.init: RemoteEvents Click, ClickResult, StateSync, Notify, OrbSpawn, AdminPush; RemoteFunctions Action, Admin)
│   ├── ServerState  (Folder, created at runtime; attributes ServerCPS, ServerPresses, Players, Event_<id>)
│   ├── Shared  (Folder)
│   │   ├── Config  (Folder)
│   │   │   ├── Achievements  (ModuleScript)
│   │   │   ├── Ascension  (ModuleScript)
│   │   │   ├── Chests  (ModuleScript)
│   │   │   ├── GameConfig  (ModuleScript)
│   │   │   ├── Items  (ModuleScript)
│   │   │   ├── Quests  (ModuleScript)
│   │   │   ├── Rarities  (ModuleScript)
│   │   │   ├── Rewards  (ModuleScript)
│   │   │   ├── Skills  (ModuleScript)
│   │   │   ├── Sounds  (ModuleScript)
│   │   │   └── Upgrades  (ModuleScript)
│   │   ├── Format  (ModuleScript)
│   │   ├── Formulas  (ModuleScript)
│   │   ├── Loot  (ModuleScript)
│   │   ├── Remotes  (ModuleScript)
│   │   ├── Signal  (ModuleScript)
│   │   └── Util  (ModuleScript)
│   └── UI  (Folder)
│       ├── Effects  (ModuleScript)
│       ├── SoundPlayer  (ModuleScript)
│       ├── Theme  (ModuleScript)
│       └── UIKit  (ModuleScript)
├── ServerScriptService
│   ├── Admin  (Folder)
│   │   ├── AdminActions  (ModuleScript)
│   │   ├── AdminCommands  (ModuleScript)
│   │   ├── AdminConfig  (ModuleScript)
│   │   ├── AdminPermissions  (ModuleScript)
│   │   ├── AdminService  (ModuleScript)
│   │   ├── AuditLog  (ModuleScript)
│   │   └── PlayerResolver  (ModuleScript)
│   ├── Core  (Folder)
│   │   ├── DataOps  (ModuleScript)
│   │   ├── DataSchema  (ModuleScript)
│   │   ├── Guard  (ModuleScript)
│   │   ├── Net  (ModuleScript)
│   │   └── RateLimiter  (ModuleScript)
│   ├── Services  (Folder)
│   │   ├── AchievementService  (ModuleScript)
│   │   ├── ChestService  (ModuleScript)
│   │   ├── ClickService  (ModuleScript)
│   │   ├── DataService  (ModuleScript)
│   │   ├── EconomyService  (ModuleScript)
│   │   ├── EventService  (ModuleScript)
│   │   ├── InventoryService  (ModuleScript)
│   │   ├── LeaderboardService  (ModuleScript)
│   │   ├── OrbService  (ModuleScript)
│   │   ├── ProgressionService  (ModuleScript)
│   │   ├── QuestService  (ModuleScript)
│   │   ├── SecurityService  (ModuleScript)
│   │   ├── SettingsService  (ModuleScript)
│   │   ├── StatsService  (ModuleScript)
│   │   ├── SyncService  (ModuleScript)
│   │   ├── UpgradeService  (ModuleScript)
│   │   └── WorldService  (ModuleScript)
│   └── Main  (Script)
├── ServerStorage
│   └── AdminClient  (Folder)
│       ├── AdminUI  (Folder)
│       │   ├── Tabs  (Folder)
│       │   │   ├── Dashboard  (ModuleScript)
│       │   │   ├── Economy  (ModuleScript)
│       │   │   ├── Items  (ModuleScript)
│       │   │   ├── Logs  (ModuleScript)
│       │   │   ├── Players  (ModuleScript)
│       │   │   ├── Progression  (ModuleScript)
│       │   │   ├── Server  (ModuleScript)
│       │   │   └── Settings  (ModuleScript)
│       │   ├── AdminNet  (ModuleScript)
│       │   ├── CommandBar  (ModuleScript)
│       │   ├── LogRow  (ModuleScript)
│       │   ├── Panel  (ModuleScript)
│       │   ├── TargetPicker  (ModuleScript)
│       │   └── Widgets  (ModuleScript)
│       └── AdminPanel  (LocalScript)
├── StarterGui  — (empty on purpose — the UI is built by ClientMain)
├── StarterPlayer
│   └── StarterPlayerScripts  (StarterPlayerScripts)
│       ├── Client  (Folder)
│       │   ├── Screens  (Folder)
│       │   │   ├── Ascend  (ModuleScript)
│       │   │   ├── ChestOpening  (ModuleScript)
│       │   │   ├── Chests  (ModuleScript)
│       │   │   ├── Collection  (ModuleScript)
│       │   │   ├── Inventory  (ModuleScript)
│       │   │   ├── Quests  (ModuleScript)
│       │   │   ├── Settings  (ModuleScript)
│       │   │   ├── Shop  (ModuleScript)
│       │   │   ├── Skills  (ModuleScript)
│       │   │   └── Stats  (ModuleScript)
│       │   ├── BigButton  (ModuleScript)
│       │   ├── ClientNet  (ModuleScript)
│       │   ├── Hud  (ModuleScript)
│       │   ├── InputController  (ModuleScript)
│       │   ├── ItemCard  (ModuleScript)
│       │   ├── Notifications  (ModuleScript)
│       │   ├── Orbs  (ModuleScript)
│       │   ├── ScreenManager  (ModuleScript)
│       │   ├── State  (ModuleScript)
│       │   └── WorldFx  (ModuleScript)
│       └── ClientMain  (LocalScript)
└── SoundService  — ButtonAscensionSounds (Folder) — created by SoundPlayer on each client
```

### Changes compared to the suggested hierarchy

| Suggested | Implemented | Why |
|---|---|---|
| UI screens in `StarterGui` | Built at runtime by `StarterPlayerScripts/ClientMain` and `Client/Screens/*` | One code base for all screen sizes, no hand-placed UI to keep in sync, every property checked automatically in tests |
| Admin Panel in `StarterGui` | `ServerStorage/AdminClient`, cloned **only** into authorised staff's PlayerGui by `AdminService` | Normal players never receive the admin client code. Security still comes from the server checks, not from hiding UI. |
| RemoteEvents/Functions placed by hand | Created by `Shared/Remotes.init()` when the server starts | One list of remotes; clients wait for them, so nothing can be missing or misspelled |
| UI kit inside the client folder | `ReplicatedStorage/UI` | Shared by the player UI and the admin panel (same design language) |
| World objects placed by hand | `WorldService` builds the neon arena, giant button, spawn and lighting if `Workspace.Arena` is missing | The place works out of the box. Add your own Model named `Arena` and it is left untouched. |

## Runtime flow

### Server start (`ServerScriptService/Main`)

1. `Remotes.init()` creates `ReplicatedStorage/Remotes` and `ReplicatedStorage/ServerState`.
2. Every service module is required into `services`, in this order:
   `SecurityService, DataService, EventService, StatsService, SyncService,
   EconomyService, QuestService, AchievementService, ClickService,
   UpgradeService, ChestService, InventoryService, ProgressionService,
   OrbService, SettingsService, LeaderboardService, WorldService, AdminService`.
3. `Net.init` binds the `Action` RemoteFunction to the action router.
4. `Init(services)` runs on each service. Services register their actions here.
5. `Start()` runs on each service. This begins the loops, player hooks and world building.

### Player join

```
PlayerAdded
 └─ DataService: UpdateAsync claims the session lock → migrate → sanitise
     ├─ on success: profile created → every service's OnProfileLoaded(profile)
     │   (stats, quests, offline earnings, orbs, leaderstats, …)
     │   → SyncService:SendFull(profile)  → client State becomes Ready
     ├─ fresh lock held by another live server: wait and retry, then kick with an explanation
     └─ DataStore unavailable: kick in live servers (protects real data);
         labelled temporary profile in Studio
AdminService (in parallel): role from server config → clone the admin panel into PlayerGui
```

### A press

```
Client BigButton → Click:FireServer()   (no arguments are trusted)
Server ClickService:
  token bucket (20/s, burst 30) → combo/crit/streak/golden rolls → EconomyService:AddSparks
  → XP / quests / achievements → ClickResult:FireClient(result)
Client: floating number, crit/streak/golden effects; the HUD reads the synced balance
```

### An action (buy, open, equip, claim, …)

```
Client ClientNet.action("BuyUpgrade", { Id, Amount }) → Action:InvokeServer
Server Net router: action name check → payload type check → global + per-action
  rate limit → profile loaded? → handler (pcall) → Net.ok({...}) / Net.fail("message")
Handler validates every field with Core/Guard, computes the price from config,
  spends via EconomyService, mutates via DataOps, invalidates stats, marks sync dirty.
```

### State replication (`SyncService`)

* The client keeps a read-only mirror of the player's **own** data (`Client/State`).
* Services mark sections dirty, for example `Currencies`, `Inventory`, `Derived`.
  Every 0.15 s the dirty sections go out in one `StateSync` patch.
* `Derived` holds the computed stats from `StatsService`. They are recomputed
  only after a relevant change, such as upgrades, skills, items, events or Frenzy.
* Server-wide state (active events, server presses/s) is replicated through
  attributes on `ReplicatedStorage/ServerState`.

## Remotes

| Remote | Type | Direction | Purpose / validation |
|---|---|---|---|
| `Click` | RemoteEvent | client → server | A press. Arguments are ignored. Token bucket, flood detection. |
| `ClickResult` | RemoteEvent | server → client | Server-computed press result, or aggregated auto/passive income. |
| `StateSync` | RemoteEvent | server → client | `"full"` snapshot or `"patch"` of the player's own data. |
| `Notify` | RemoteEvent | server → client | Toasts, level ups, discoveries, achievements, announcements, events, offline earnings. |
| `OrbSpawn` | RemoteEvent | server → client | A bonus orb the player may claim. The server remembers the only valid id. |
| `AdminPush` | RemoteEvent | server → admins | Live audit-log entries. Sent only to staff with `logs.view`. |
| `Action` | RemoteFunction | client → server | Every player action. Name and payload checks, rate limits, `pcall`. |
| `Admin` | RemoteFunction | client → server | Every admin request. See the 10-step pipeline in [`ADMIN.md`](ADMIN.md). |

The server never calls `InvokeClient`.

### Player actions

| Action | Payload | Service |
|---|---|---|
| `BuyUpgrade` | `{ Id, Amount = 1 \| 10 \| "max" }` | UpgradeService |
| `OpenChest` | `{ Id, Amount = 1..10, Mode = "owned" \| "buy" }` | ChestService |
| `Equip`, `Unequip`, `EquipBest`, `Favorite`, `Sell`, `SellDuplicates` | `{ Id }`, `{ Id, State }`, `{ Id, Amount }`, `{ MaxRarity }` | InventoryService |
| `UnlockSkill`, `ResetSkills` | `{ Id }`, `{}` | ProgressionService |
| `Rebirth`, `BuyAscension` | `{}`, `{ Id }` | ProgressionService |
| `ClaimCollection`, `ClaimDaily` | `{ Id }`, `{}` | ProgressionService |
| `ClaimQuest`, `ClaimQuestBonus`, `ClaimStarter` | `{ Index }`, `{}`, `{}` | QuestService |
| `ClaimOrb` | `{ Id }` | OrbService |
| `UpdateSettings`, `RequestState` | `{ Key, Value }`, `{}` | SettingsService |
| `GetLeaderboards` | `{}` | LeaderboardService |

## Security model

| Threat | Defence |
|---|---|
| Forged prices, rewards, odds, balances, item ids | The client never sends them. Ids are looked up in config tables, amounts are range-checked integers, and everything else is computed on the server. |
| Auto-clickers / remote spam | `Click` token bucket (20/s, burst 30) plus flood flagging. Per-action and global per-player action rate limits. |
| Malformed payloads (wrong types, huge strings, NaN, extra fields) | `Core/Guard` checks each field the handler actually reads. Unknown actions are flagged by `SecurityService`. |
| Handler errors | Every handler runs in `pcall`, and the client gets a generic error. Loops are per-service and never affected by a single remote call. |
| Calling the admin remote as a normal player | The role comes from server-side config only. The request is rejected, logged (throttled) and flagged. |
| Admin abuse / mistakes | Per-role permissions and limits, rank protection, confirmation tokens for destructive actions, rate limits, duplicate-request rejection, full audit log. |
| Two servers writing the same player | Session lock in the data record. Saves verify ownership, and a lost lock stops saving and removes the player. |
| Corrupted or tampered stored data | `DataSchema.sanitize` rebuilds data from known keys with clamped values. Unknown items are preserved in `LegacyInventory`. |
| Exposing private info | `AdminConfig` lives in ServerScriptService (never replicated). Clients only receive their own data. The admin client is delivered only to staff. |
| Unfiltered text | Announcements and kick reasons go through `TextService` filtering. If filtering fails, the announcement is not sent. |

## Data model (schema version 2)

```
Version, Currencies{Sparks,Gems,Prisms}, Level, XP, SkillPoints, Rebirths,
Upgrades{id→level}, Ascension{id→level}, Skills{id→rank},
Inventory{itemId→count}, LegacyInventory{id→count}, Favorites{id→true}, Equipped[itemId],
Discovered{itemId→unixTime}, Chests{chestId→count}, Pity{chestId→{Legendary,Mythic}},
Stats{TotalClicks, AutoClicks, LifetimeSparks, SparksThisRun, BestRunSparks, ChestsOpened,
      TotalCrits, HighestCombo, GoldenClicks, UpgradesPurchased, LegendariesFound,
      MythicsFound, SecretsFound, ItemsSold, QuestsCompleted, OrbsCollected, PlayTime,
      GemsEarned, PrismsEarned, BestDailyStreak, StreakBursts, OfflineEarned},
Achievements{id→unixTime}, CollectionClaimed{id→true},
Quests{Day, Daily[{Id,Target,Progress,Claimed}], BonusClaimed, StarterIndex, StarterProgress},
Daily{LastClaimDay, Streak}, Settings{Music,SFX,UIScale,ReducedMotion,ScreenShake,
      FloatingNumbers,ConfirmRareSales,AutoSell,BackgroundDim},
Meta{Created, LastSave, LastSeen, Sessions}
```

Stored as `{ Schema, Data, Lock = { JobId, PlaceId, Time } | nil, UpdatedAt }`
under the key `Player_<UserId>` in the DataStore `ButtonAscension_PlayerData`.
Migration from schema 1 (the pre-release format) is in `Core/DataSchema`. To
add a version, write `MIGRATIONS[2]`, bump `CURRENT_VERSION`, and extend
`sanitize`.

Other stores:

* `ButtonAscension_AdminAudit`: one key per UTC day, `Audit_YYYY-MM-DD`.
* `ButtonAscension_LB_<board>`: OrderedDataStores for the leaderboards.
