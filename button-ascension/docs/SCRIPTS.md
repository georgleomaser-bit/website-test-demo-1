# Script reference

Every script in the project, with its exact name, type, Explorer location
and dependencies. In the repository, a script lives at
`src/<Explorer location>.luau` (`.server.luau` for Scripts and `.client.luau`
for LocalScripts). Rojo maps the files to these names automatically. If you
copy them by hand, follow [`SETUP.md`](SETUP.md).

* **Script** — runs on the server (only `ServerScriptService/Main`).
* **LocalScript** — runs on a client: `StarterPlayerScripts/ClientMain` for
  everyone, and `ServerStorage/AdminClient/AdminPanel`, which runs only after
  the server clones it into a staff member's `PlayerGui`.
* **ModuleScript** — a library required by other scripts. Every module
  returns a table and has no side effects until its owner calls it.

"Depends on" lists what each script requires. Every referenced module exists
in this table, and the type checker plus the test harness confirm that every
require resolves.

| Explorer location | File | Type | Depends on | Purpose |
|---|---|---|---|---|
| `ReplicatedStorage/Shared/Config/Achievements` | `Achievements.luau` | ModuleScript | — | Achievements unlock automatically when a tracked statistic reaches its target. |
| `ReplicatedStorage/Shared/Config/Ascension` | `Ascension.luau` | ModuleScript | — | Permanent upgrades bought with Prisms (earned by ascending). |
| `ReplicatedStorage/Shared/Config/Chests` | `Chests.luau` | ModuleScript | — | Crate tiers. |
| `ReplicatedStorage/Shared/Config/GameConfig` | `GameConfig.luau` | ModuleScript | — | Central balance and tuning values that are shared between server and client. |
| `ReplicatedStorage/Shared/Config/Items` | `Items.luau` | ModuleScript | Config/Rarities, Config/Chests, Config/GameConfig | Every collectible in the game. |
| `ReplicatedStorage/Shared/Config/Quests` | `Quests.luau` | ModuleScript | — | Two kinds of quests: * Daily quests: DailyCount quests are drawn from the Daily pool each UTC day (deterministically per player). |
| `ReplicatedStorage/Shared/Config/Rarities` | `Rarities.luau` | ModuleScript | — | Rarity tiers in ascending order. |
| `ReplicatedStorage/Shared/Config/Rewards` | `Rewards.luau` | ModuleScript | — | Daily login rewards and collection-book milestones. |
| `ReplicatedStorage/Shared/Config/Skills` | `Skills.luau` | ModuleScript | — | The skill tree. |
| `ReplicatedStorage/Shared/Config/Sounds` | `Sounds.luau` | ModuleScript | — | All sound effects in one place. |
| `ReplicatedStorage/Shared/Config/Upgrades` | `Upgrades.luau` | ModuleScript | — | Shop upgrades bought with Sparks. |
| `ReplicatedStorage/Shared/Format` | `Format.luau` | ModuleScript | — | Number and time formatting used by every UI and by server messages. |
| `ReplicatedStorage/Shared/Formulas` | `Formulas.luau` | ModuleScript | Shared/Config/*, Shared/Format | Every game formula lives here so the server (authoritative) and the client (previews only) can never disagree. |
| `ReplicatedStorage/Shared/Loot` | `Loot.luau` | ModuleScript | Shared/Config/Rarities, Shared/Config/Items | Pure crate-roll maths. |
| `ReplicatedStorage/Shared/Remotes` | `Remotes.luau` | ModuleScript | — | Single source of truth for every RemoteEvent / RemoteFunction. |
| `ReplicatedStorage/Shared/Signal` | `Signal.luau` | ModuleScript | — | Minimal Lua signal. |
| `ReplicatedStorage/Shared/Util` | `Util.luau` | ModuleScript | — | Small pure helpers shared by server and client. |
| `ReplicatedStorage/UI/Effects` | `Effects.luau` | ModuleScript | UI/Theme | 2D juice for the interface: particle bursts, floating numbers, shockwave rings, screen shake and flashes. |
| `ReplicatedStorage/UI/SoundPlayer` | `SoundPlayer.luau` | ModuleScript | Shared/Config/Sounds | Client-side sound effects and music. |
| `ReplicatedStorage/UI/Theme` | `Theme.luau` | ModuleScript | Shared/Config/GameConfig, Shared/Config/Rarities | Design tokens for the whole interface: colours, typography, radii and motion. |
| `ReplicatedStorage/UI/UIKit` | `UIKit.luau` | ModuleScript | UI/Theme, UI/SoundPlayer | Declarative helpers and themed components used by every screen of the player UI and by the admin panel. |
| `ServerScriptService/Admin/AdminActions` | `AdminActions.luau` | ModuleScript | Admin/AdminConfig, Admin/AdminPermissions, Admin/AuditLog, Core/DataOps, Core/DataSchema, Shared/Config/*, Shared/Formulas, Shared/Format, gameplay services (through ctx.Services) | Every admin operation declared as data (permission, rate-limit category, target rules, validation, execution, offline variant). |
| `ServerScriptService/Admin/AdminCommands` | `AdminCommands.luau` | ModuleScript | Admin/AdminActions, Admin/AdminPermissions | Parses command-bar text into an admin action + arguments. |
| `ServerScriptService/Admin/AdminConfig` | `AdminConfig.luau` | ModuleScript | — | Server-only allowlist of staff UserIds, role definitions, permissions, limits and rate limits (documented in-file). |
| `ServerScriptService/Admin/AdminPermissions` | `AdminPermissions.luau` | ModuleScript | Admin/AdminConfig | Resolves a player's staff role from SERVER-SIDE data only (UserId allowlist, place creator, group owner, Studio test list) and answers permission… |
| `ServerScriptService/Admin/AdminService` | `AdminService.luau` | ModuleScript | Admin/AdminConfig, Admin/AdminPermissions, Admin/AdminActions, Admin/AdminCommands, Admin/AuditLog, Admin/PlayerResolver, Core/RateLimiter, Core/Guard, Shared/Remotes, ServerStorage/AdminClient, DataService, SecurityService, Net | The ONLY entry point for admin requests (RemoteFunction "Admin"). |
| `ServerScriptService/Admin/AuditLog` | `AuditLog.luau` | ModuleScript | Admin/AdminConfig | Records every admin request: who (UserId, name, role), what (action and sanitised parameters), whom (target UserId/name), when (unix time), and… |
| `ServerScriptService/Admin/PlayerResolver` | `PlayerResolver.luau` | ModuleScript | — | Safely turns admin input into exactly one online player. |
| `ServerScriptService/Core/DataOps` | `DataOps.luau` | ModuleScript | ReplicatedStorage/Shared/Config/* | Pure, non-yielding mutations of a player data table. |
| `ServerScriptService/Core/DataSchema` | `DataSchema.luau` | ModuleScript | ReplicatedStorage/Shared/Config/* | Defines the persisted player data format, its version, migrations from older versions, and sanitisation of loaded data. |
| `ServerScriptService/Core/Guard` | `Guard.luau` | ModuleScript | — | Validation helpers for values that arrive from clients. |
| `ServerScriptService/Core/Net` | `Net.luau` | ModuleScript | Shared/Remotes, Core/Guard, Core/RateLimiter | Server networking hub. |
| `ServerScriptService/Core/RateLimiter` | `RateLimiter.luau` | ModuleScript | — | Token-bucket rate limiter keyed by any value (usually a UserId or a "UserId:action" string). |
| `ServerScriptService/Main` | `Main.server.luau` | Script | ServerScriptService/Core/*, ServerScriptService/Services/*, ServerScriptService/Admin/AdminService, ReplicatedStorage/Shared/Remotes | Server entry point. |
| `ServerScriptService/Services/AchievementService` | `AchievementService.luau` | ModuleScript | Shared/Config/Achievements, Shared/Formulas, EconomyService, SyncService, Net | Unlocks achievements when tracked values reach their targets and grants their rewards. |
| `ServerScriptService/Services/ChestService` | `ChestService.luau` | ModuleScript | Shared/Loot, Shared/Formulas, Shared/Config/{Chests,Items,Rarities,GameConfig}, Core/DataOps, Core/Net, Core/Guard, EconomyService, StatsService, SyncService, QuestService, AchievementService | Crate purchasing and opening. |
| `ServerScriptService/Services/ClickService` | `ClickService.luau` | ModuleScript | Shared/Config/GameConfig, Shared/Config/Chests, Shared/Formulas, Shared/Util, Core/RateLimiter, Core/DataOps, StatsService, EconomyService, QuestService, AchievementService, SecurityService, SyncService, WorldService, Net | Server-authoritative pressing. |
| `ServerScriptService/Services/DataService` | `DataService.luau` | ModuleScript | Core/DataSchema, Shared/Util, Shared/Signal, Shared/Config/GameConfig | Loads, saves and protects player data in DataStoreService. |
| `ServerScriptService/Services/EconomyService` | `EconomyService.luau` | ModuleScript | Core/DataOps, Shared/Formulas, Shared/Config/*, StatsService, SyncService, QuestService, AchievementService, Net | The only place currencies, XP and generic rewards are granted or spent. |
| `ServerScriptService/Services/EventService` | `EventService.luau` | ModuleScript | Shared/Config/GameConfig, Shared/Remotes, StatsService, Net | Server-wide boost events (Spark Surge, Lucky Hour, ...). |
| `ServerScriptService/Services/InventoryService` | `InventoryService.luau` | ModuleScript | Shared/Config/{Items,GameConfig}, Shared/Formulas, Core/DataOps, Core/Net, Core/Guard, EconomyService, StatsService, SyncService, QuestService | Equip / unequip / favourite / sell. |
| `ServerScriptService/Services/LeaderboardService` | `LeaderboardService.luau` | ModuleScript | Shared/Config/GameConfig, Shared/Format, Core/Net, DataService | * leaderstats for the Roblox player list (Ascensions, Sparks). |
| `ServerScriptService/Services/OrbService` | `OrbService.luau` | ModuleScript | Shared/Config/{GameConfig,Chests}, Shared/Util, Core/Net, Core/Guard, Core/DataOps, EconomyService, StatsService, SyncService, QuestService | Bonus orbs: every 70–140 seconds (shorter with Orb Magnet) the server offers a player an orb that floats onto their screen for a few seconds. |
| `ServerScriptService/Services/ProgressionService` | `ProgressionService.luau` | ModuleScript | Shared/Config/{Skills,Ascension,Rewards,Items,GameConfig}, Shared/Formulas, Shared/Util, Core/Net, Core/Guard, EconomyService, StatsService, SyncService, QuestService, AchievementService, ClickService, DataService | Long-term progression: * Skill tree UnlockSkill { Id }, ResetSkills {} * Ascension Rebirth {}, BuyAscension { Id } * Collection ClaimCollection {… |
| `ServerScriptService/Services/QuestService` | `QuestService.luau` | ModuleScript | Shared/Config/Quests, Shared/Formulas, Shared/Util, EconomyService, StatsService, SyncService, AchievementService, Net | Daily quests (new set every UTC day, deterministic per player) and the Starter Path tutorial chain. |
| `ServerScriptService/Services/SecurityService` | `SecurityService.luau` | ModuleScript | — | Records suspicious client behaviour (malformed remote calls, unknown actions, click floods, unauthorised admin requests). |
| `ServerScriptService/Services/SettingsService` | `SettingsService.luau` | ModuleScript | Shared/Config/GameConfig, Core/Net, Core/Guard, SyncService | Persists player preferences (volumes, reduced motion, UI scale, ...). |
| `ServerScriptService/Services/StatsService` | `StatsService.luau` | ModuleScript | Shared/Formulas, DataService, SyncService, EventService | Caches each player's computed Stats (see Shared/Formulas.computeStats) and recomputes them only when something relevant changes (Invalidate). |
| `ServerScriptService/Services/SyncService` | `SyncService.luau` | ModuleScript | Shared/Remotes, StatsService | Replicates a player's OWN data to their client. |
| `ServerScriptService/Services/UpgradeService` | `UpgradeService.luau` | ModuleScript | Shared/Config/Upgrades, Shared/Formulas, Core/Net, Core/Guard, EconomyService, StatsService, SyncService, QuestService, AchievementService | Shop upgrades bought with Sparks. |
| `ServerScriptService/Services/WorldService` | `WorldService.luau` | ModuleScript | Shared/Remotes, Shared/Format, Shared/Config/GameConfig, ClickService | Builds the 3D lobby at runtime if Workspace has no model named "Arena": a dark neon plaza with a giant button, a spawn pad, pillars and a sign. |
| `ServerStorage/AdminClient/AdminPanel` | `AdminPanel.client.luau` | LocalScript | AdminUI/AdminNet, AdminUI/Panel (and through them ReplicatedStorage/UI/*, ReplicatedStorage/Shared/*) | Asks the server who we are ("hello"), then builds the panel with exactly the tabs and controls that role may use. |
| `ServerStorage/AdminClient/AdminUI/AdminNet` | `AdminNet.luau` | ModuleScript | ReplicatedStorage/Shared/Remotes, ReplicatedStorage/UI/UIKit, ReplicatedStorage/UI/Theme | Client wrapper around the "Admin" RemoteFunction. |
| `ServerStorage/AdminClient/AdminUI/CommandBar` | `CommandBar.luau` | ModuleScript | AdminUI/Widgets, AdminUI/AdminNet | Searchable command bar with console output. |
| `ServerStorage/AdminClient/AdminUI/LogRow` | `LogRow.luau` | ModuleScript | AdminUI/Widgets | Renders audit-log and security-flag entries as two-line rows. |
| `ServerStorage/AdminClient/AdminUI/Panel` | `Panel.luau` | ModuleScript | AdminUI/Widgets, AdminUI/AdminNet, AdminUI/CommandBar, AdminUI/Tabs/*, ReplicatedStorage/Shared/Signal, ReplicatedStorage/UI/SoundPlayer | Builds the admin panel shell: floating toggle button, window with role badge, sidebar with the eight tabs, command bar + console, in-panel toasts,… |
| `ServerStorage/AdminClient/AdminUI/Tabs/Dashboard` | `Dashboard.luau` | ModuleScript | AdminUI/Widgets, AdminUI/LogRow, ReplicatedStorage/Shared/Format, ReplicatedStorage/Shared/Config/GameConfig | Server health at a glance: players, uptime, presses, memory, physics, heartbeat, DataStore status, events, security flags, recent admin actions. |
| `ServerStorage/AdminClient/AdminUI/Tabs/Economy` | `Economy.luau` | ModuleScript | AdminUI/Widgets, AdminUI/TargetPicker, ReplicatedStorage/Shared/Format, ReplicatedStorage/Shared/Config/GameConfig | Amounts typed here are parsed for convenience (1.5k, 2m, 1e6); the server re-validates every amount against the role's limit. |
| `ServerStorage/AdminClient/AdminUI/Tabs/Items` | `Items.luau` | ModuleScript | AdminUI/Widgets, AdminUI/TargetPicker, ReplicatedStorage/Shared/Format, ReplicatedStorage/Shared/Config/{Items,Chests,Rarities} | Grant/remove items and crates, inspect inventories, and test crate odds. |
| `ServerStorage/AdminClient/AdminUI/Tabs/Logs` | `Logs.luau` | ModuleScript | AdminUI/Widgets, AdminUI/LogRow | Three views: this server's audit log (live), security flags (suspicious client requests) and the persisted audit log of every server for a UTC day. |
| `ServerStorage/AdminClient/AdminUI/Tabs/Players` | `Players.luau` | ModuleScript | AdminUI/Widgets, ReplicatedStorage/Shared/Format, ReplicatedStorage/Shared/Config/{Upgrades,Skills,Chests} | Searchable list of online players; selecting one shows their progression, inventory summary, statistics and moderation actions. |
| `ServerStorage/AdminClient/AdminUI/Tabs/Progression` | `Progression.luau` | ModuleScript | AdminUI/Widgets, AdminUI/TargetPicker, ReplicatedStorage/Shared/Config/{Upgrades,Skills} |  |
| `ServerStorage/AdminClient/AdminUI/Tabs/Server` | `Server.luau` | ModuleScript | AdminUI/Widgets, ReplicatedStorage/Shared/Format, ReplicatedStorage/Shared/Config/GameConfig | Announcements are filtered by Roblox text filtering on the server. |
| `ServerStorage/AdminClient/AdminUI/Tabs/Settings` | `Settings.luau` | ModuleScript | AdminUI/Widgets, ReplicatedStorage/Shared/Format | Shows the staff member's role, rank, permissions and limits, plus local panel preferences. |
| `ServerStorage/AdminClient/AdminUI/TargetPicker` | `TargetPicker.luau` | ModuleScript | AdminUI/Widgets | "Target" row used by the Economy, Items and Progression tabs. |
| `ServerStorage/AdminClient/AdminUI/Widgets` | `Widgets.luau` | ModuleScript | ReplicatedStorage/UI/UIKit, ReplicatedStorage/UI/Theme, ReplicatedStorage/Shared/Config/Rarities | Admin-styled building blocks on top of UIKit: the same components and motion as the player UI, re-skinned with Theme.Admin (near-black teal, neon… |
| `StarterPlayer/StarterPlayerScripts/Client/BigButton` | `BigButton.luau` | ModuleScript | ReplicatedStorage/UI/{UIKit,Theme,Effects,SoundPlayer}, ReplicatedStorage/Shared/{Format, Config/GameConfig}, Client/ClientNet | The large central button. |
| `StarterPlayer/StarterPlayerScripts/Client/ClientNet` | `ClientNet.luau` | ModuleScript | ReplicatedStorage/Shared/Remotes | Thin wrapper around the remotes. |
| `StarterPlayer/StarterPlayerScripts/Client/Hud` | `Hud.luau` | ModuleScript | ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format,Formulas,Util,Config/*}, Client/{State,ClientNet,ScreenManager,BigButton} | Always-visible interface: * Top bar: Sparks (per press / per second), Gems, Prisms, level + XP. |
| `StarterPlayer/StarterPlayerScripts/Client/InputController` | `InputController.luau` | ModuleScript | Client/ScreenManager | Controller support on top of Roblox's built-in GUI selection: R2 / L2 press the big button (when no window is open) Y jump to the navigation rail… |
| `StarterPlayer/StarterPlayerScripts/Client/ItemCard` | `ItemCard.luau` | ModuleScript | ReplicatedStorage/UI/{UIKit,Theme}, ReplicatedStorage/Shared/Config/{Items,Rarities} | Reusable item tile with rarity border, glow, icon, name and badges (count, equipped, favourite, new). |
| `StarterPlayer/StarterPlayerScripts/Client/Notifications` | `Notifications.luau` | ModuleScript | ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format, Config/*} | Toasts (top-right stack), banners (centre-top queue) and announcements. |
| `StarterPlayer/StarterPlayerScripts/Client/Orbs` | `Orbs.luau` | ModuleScript | ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format, Config/Chests}, Client/{ClientNet, Notifications} | Renders bonus orbs offered by the server (OrbSpawn) and claims them. |
| `StarterPlayer/StarterPlayerScripts/Client/ScreenManager` | `ScreenManager.luau` | ModuleScript | ReplicatedStorage/Shared/Signal | Keeps track of the full-screen windows (Shop, Crates, Inventory, ...). |
| `StarterPlayer/StarterPlayerScripts/Client/Screens/Ascend` | `Ascend.luau` | ModuleScript | ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format,Formulas,Config/*}, Client/{State,ClientNet} | Ascension (rebirth): shows progress toward the requirement, the Prisms you would receive, the permanent multiplier and the next stage, plus an… |
| `StarterPlayer/StarterPlayerScripts/Client/Screens/ChestOpening` | `ChestOpening.luau` | ModuleScript | ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format,Formulas,Config/*}, Client/ItemCard | Cinematic reveal of results the server has ALREADY applied: anticipation shake (glow shifts toward the best rarity) → flash + light rays → item… |
| `StarterPlayer/StarterPlayerScripts/Client/Screens/Chests` | `Chests.luau` | ModuleScript | ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format,Formulas,Loot,Config/*}, Client/{State,ClientNet,ItemCard,Screens/ChestOpening} | Crate shop: pick a crate on the left; the right panel shows its price, owned count, live drop odds (including your Luck), pity progress and every… |
| `StarterPlayer/StarterPlayerScripts/Client/Screens/Collection` | `Collection.luau` | ModuleScript | ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format,Formulas,Config/*}, Client/{State,ClientNet,ItemCard} | The collection book: every item in the game grouped by crate. |
| `StarterPlayer/StarterPlayerScripts/Client/Screens/Inventory` | `Inventory.luau` | ModuleScript | ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format,Formulas,Config/*}, Client/{State,ClientNet,ItemCard} | Owned items as a searchable, filterable, sortable grid. |
| `StarterPlayer/StarterPlayerScripts/Client/Screens/Quests` | `Quests.luau` | ModuleScript | ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format,Formulas,Util,Config/*}, Client/{State,ClientNet} | Four tabs: Daily three quests per UTC day + a bonus for finishing all of them Starter the guided starter path Login the 7-day login calendar… |
| `StarterPlayer/StarterPlayerScripts/Client/Screens/Settings` | `Settings.luau` | ModuleScript | ReplicatedStorage/UI/*, ReplicatedStorage/Shared/Config/{GameConfig,Rarities}, Client/{State,ClientNet} | Player preferences, saved with the player's data. |
| `StarterPlayer/StarterPlayerScripts/Client/Screens/Shop` | `Shop.luau` | ModuleScript | ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format,Formulas,Config/Upgrades}, Client/{State,ClientNet} | Upgrade shop grouped into tiers. |
| `StarterPlayer/StarterPlayerScripts/Client/Screens/Skills` | `Skills.luau` | ModuleScript | ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format,Formulas,Config/*}, Client/{State,ClientNet} | Visual skill tree on a pannable canvas. |
| `StarterPlayer/StarterPlayerScripts/Client/Screens/Stats` | `Stats.luau` | ModuleScript | ReplicatedStorage/UI/*, ReplicatedStorage/Shared/{Format,Formulas,Util,Config/*}, Client/{State,ClientNet} | Personal statistics and leaderboards (global boards from OrderedDataStores, refreshed by the server every couple of minutes, plus a live board for… |
| `StarterPlayer/StarterPlayerScripts/Client/State` | `State.luau` | ModuleScript | (none) | Read-only client mirror of the player's own data, filled by StateSync from the server. |
| `StarterPlayer/StarterPlayerScripts/Client/WorldFx` | `WorldFx.luau` | ModuleScript | ReplicatedStorage/Shared/{Formulas, Config/GameConfig}, Client/State | Local-only effects on the 3D giant button in Workspace.Arena: * it dips every time you press, * its glow follows the whole server's presses per… |
| `StarterPlayer/StarterPlayerScripts/ClientMain` | `ClientMain.client.luau` | LocalScript | StarterPlayerScripts/Client/* (State, ClientNet, Hud, ScreenManager, Notifications, Orbs, InputController, WorldFx, Screens/*), ReplicatedStorage/UI/*, ReplicatedStorage/Shared/* | Client entry point. |

## Entry points

| Runs on | Entry | Starts |
|---|---|---|
| Server | `ServerScriptService/Main` (Script) | All services in a fixed order (see [`ARCHITECTURE.md`](ARCHITECTURE.md)) |
| Every client | `StarterPlayer/StarterPlayerScripts/ClientMain` (LocalScript) | HUD, screens, notifications, orbs, input, world effects |
| Staff clients only | `PlayerGui/AdminPanelGui/AdminPanel` (LocalScript cloned from `ServerStorage/AdminClient`) | Admin panel, command bar, `/admin` chat command |
