# Testing

Testing has two layers:

1. **Automated:** 94 tests that run the real game scripts in a headless
   Roblox simulation, plus static type checking. They run without Roblox
   Studio, in under a minute.
2. **Manual:** a checklist for things that need the real engine (rendering,
   real DataStores/MessagingService, real devices).

## Automated verification

| Check | Command | Result |
|---|---|---|
| Static type check against the Roblox API definitions (luau-lsp 1.70, `globalTypes.d.luau`) | `luau-lsp analyze --definitions=globalTypes.d.luau --sourcemap=sourcemap.json src` | **0 errors, 0 warnings** |
| Every file compiles (luau-compile) | `luau-compile --text <file>` | **all 87 scripts compile** |
| Rojo build | `rojo build default.project.json -o build/ButtonAscension.rbxlx` | **builds**; 1 Script, 2 LocalScripts, 84 ModuleScripts, 11 Folders |
| Headless game tests (Lune 0.10.4) | `lune run tests/run.luau` | **94 passed, 0 failed** |

### How the headless tests work

`tests/harness` rebuilds the Rojo project as mock Roblox instances and runs
the **real** `Main` Script, `ClientMain` LocalScript and every ModuleScript.
Several simulated players each get their own client world. It uses virtual
time, so minutes of gameplay take seconds.

* Every property write is checked against the official Roblox API reflection
  database. A misspelled property, a wrong type or a read-only write fails
  the test.
* Remotes follow Roblox's serialisation rules.
* DataStores, MessagingService and TextService are in-memory, can fail on
  demand, and are shared between simulated servers. This makes session-lock
  conflicts testable.
* Tests can call server remotes directly with arbitrary arguments, exactly as
  an exploiter would.

Details: [`tests/README.md`](../tests/README.md).

### Test list

#**Suite: admin
##**Suite: Access
- delivers the admin panel only to staff
- makes the place creator Owner in live servers and nobody else
- rejects every request from a normal player, however it is forged
- rejects malformed and duplicate requests from staff
##**Suite: Roles and permissions
- gives Owner, Admin and Moderator different powers
- protects staff of equal or higher rank from punitive actions
##**Suite: Economy, items and progression tools
- adds, removes and sets currency through core validation
- grants and removes items and crates, and runs test drops without changing odds
- grants upgrades, skills, ascensions, levels and skill points
##**Suite: Confirmation of destructive actions
- requires a single-use token from the same admin before resetting
- resets a chosen progression scope only after confirmation
##**Suite: Player management
- freezes, unfreezes, teleports, respawns and kicks with a reason
##**Suite: Command bar
- parses commands, resolves players safely and validates arguments
##**Suite: Safeguards
- rate limits punitive actions and records everything in the audit log
- edits offline players only when the role allows it and no session holds the data
##**Suite: Announcements and events
- filters announcements, labels the scope and delivers game-wide ones to other servers
- starts and stops server events that change player stats
#**Suite: client
##**Suite: Interface
- boots without errors, hides the loading screen and presses through the big button
- opens and closes every screen from the navigation rail
- buys an upgrade from the shop
- opens a crate and plays the reveal
- equips an item from the inventory
- saves settings changed in the settings screen
##**Suite: Devices
- uses the compact layout on a phone with touch input
- presses the button with a controller trigger
##**Suite: Admin panel client
- boots for an Owner and runs a command from the command bar
#**Suite: gameplay
##**Suite: New player
- gets default data, leaderstats, daily quests and a full snapshot
##**Suite: Pressing
- awards server-computed Sparks, XP and stats and ignores forged arguments
- caps instant click floods with the token bucket and flags them
- ignores presses before the profile has loaded
##**Suite: Upgrades
- rejects purchases without funds, unknown ids, bad amounts and locked tiers
- charges the server price and raises the level; MAX buys as many as affordable
##**Suite: Crates
- validates crate id, amount, mode, stage lock and funds
- rolls on the server, applies the items and ignores forged rarities
- guarantees a Legendary or better when pity is reached
- auto-sells duplicates up to the chosen rarity when enabled
##**Suite: Inventory
- equips only owned items within the slot limit and sells safely
- makes extra copies strengthen an equipped item
##**Suite: Skill tree
- enforces skill points and prerequisites
##**Suite: Ascension
- refuses early, then resets only the run and keeps permanent progress
- keeps Auto-Presser with Loyal Robots and grants Head Start sparks
##**Suite: Quests, achievements and daily rewards
- tracks the starter path and pays rewards once
- pays a daily quest only when complete and only once
- unlocks achievements automatically from stats
- lets the daily login reward be claimed once per UTC day
##**Suite: Bonus orbs
- only accepts the orb the server offered, once
##**Suite: Settings and request validation
- validates every setting and rejects unknown actions
- rate limits action spam
#**Suite: harness_selftest
##**Suite: Instances
- reports Roblox-style errors for invalid members, types and classes
- returns reflection defaults and computes GUI geometry
- fires Changed, property, attribute, child and Destroying signals
- clones deep trees with attributes and remaps internal references
- detects cyclic requires
##**Suite: Scheduler
- orders task.delay / task.wait / task.defer in virtual time
- lets tests yield: task.wait inside a test advances virtual time
- WaitForChild yields until the child appears or the timeout elapses
- records uncaught errors from script threads
- completes tweens and fires Completed
##**Suite: DataStores
- cancels UpdateAsync when the transform returns nil
- injects failures and rejects unstorable values
- shares one backend between two servers and serves ordered stores
##**Suite: Network
- round-trips remotes with Roblox serialisation rules
- replicates server changes and lets tests act as exploiters
- only replicates a PlayerGui to its owner and starts LocalScripts placed there
- delivers MessagingService messages between servers
- filters text and runs BindToClose on shutdown
#**Suite: multiplayer
##**Suite: Multiplayer
- keeps each player's data isolated
- runs 8 players with full collections and auto-presses for 3 minutes
- shares server activity with every client
#**Suite: persistence
##**Suite: Saving
- saves on leave, releases the lock and restores the data in another server
- autosaves while playing and keeps the session lock fresh
- saves every player when the server shuts down
##**Suite: DataStore failures
- retries transient failures while loading
- kicks instead of playing on empty data when loading keeps failing
- retries failed saves and reports them
- uses a clearly labelled temporary profile in Studio without API access and never writes
##**Suite: Session locking
- refuses a second server while the first holds a fresh lock
- waits for the other server to finish saving, then loads the newest data
- takes over a stale lock left behind by a crashed server
- stops saving and removes the player if another server took the lock
##**Suite: Schema and validation
- migrates version 1 data to the current schema
- sanitises tampered or corrupted values
- refuses to touch data written by a newer game version
- refuses to overwrite an unreadable record
##**Suite: Offline earnings
- grants a capped share of passive income for time away
#**Suite: shared_config
##**Suite: Configuration
- loads every config module
- gives every weighted rarity of every crate a non-empty item pool
- keeps skill prerequisites, upgrades, achievements and quests consistent
##**Suite: Loot
- normalises effective weights for any luck value
- matches expected odds over 20,000 simulated openings per crate
- guarantees Legendary or better when the pity threshold is reached
##**Suite: Formulas and Format
- computes finite stats for fresh and heavily progressed players
- computes stats from the server's default player data
- formats numbers like the UI expects


### Bugs found and fixed by these tests during development

* **Shutdown.** `BindToClose` could return while saves started by
  `PlayerRemoving` were still running, so a shutdown could cut a save short.
  `DataService` now waits for in-flight releases.
* **Confirmation tokens.** A *different* admin trying someone's confirmation
  token invalidated it for its owner. The token is now kept and the attempt
  is logged as denied.
* **Admin panel layout.** A `UIScale` on a full-screen frame scaled from the
  top-left corner and would push the Admin button off-screen on large
  displays. Scaling now happens per anchored element. This one was found in
  review, because the harness doesn't simulate layout.

## Manual checklist (Roblox Studio)

**How to run:**

* Use **Local Server, 4 players** for multiplayer and role checks. In Studio,
  Player1 is Owner, Player2 Admin, Player3 Moderator and Player4 a normal
  player.
* Use **Play** for solo checks.
* Enable *Studio Access to API Services* for the persistence checks.

The **Auto** column shows which items the automated suite already covers;
the manual pass confirms them in the real engine.

### Gameplay

| ✓ | Check | Expected | Auto |
|---|---|---|---|
| ☐ | New player joins | Loading screen fades; HUD shows ⚡0, 💎0, 🔷0, Lv 1; the starter path says *Press the button 25 times*; leaderstats show Ascensions 0 | ✅ |
| ☐ | Press the button with the mouse | The button squashes, a ring and sparks appear, a click sound plays, a floating "+1" shows, and the combo meter fills | ✅ (logic) |
| ☐ | Press repeatedly for 50+ presses | Combo multiplier rises (×1.5 at 50); streak burst banner at 50 | ✅ |
| ☐ | Crit / golden press | Gold "CRIT!" number, screen shake (setting), golden toast with reward | ✅ (logic) |
| ☐ | Buy upgrades ×1 / ×10 / MAX | Cost and "current → next" preview are correct; balance drops; level rises; the button shows the new per-press value | ✅ |
| ☐ | Tier II locked until level 8, Tier III until first ascension | Locked header with requirement, buy disabled; the server rejects it too | ✅ |
| ☐ | Buy and open crates ×1/×5/×10 | Shake → burst → cards; NEW, PITY and BONUS badges; inventory updated; odds panel matches config | ✅ |
| ☐ | Locked crate (Plasma at 0 ascensions) | Shows 🔒 stage requirement; the server refuses | ✅ |
| ☐ | Pity | After 79 non-Legendary Spark Crates, the 80th is Legendary+ (set with `/admin`, or watch the pity bar) | ✅ |
| ☐ | Inventory: search, rarity filter, sorts | Grid updates instantly; empty-state messages | ✅ (UI) |
| ☐ | Equip / unequip / Equip best / slot limit | Bonuses appear in the equipped bar; a 4th item is refused with 3 slots | ✅ |
| ☐ | Favourite → sell blocked; sell 1 / extras / all; Sell duplicates | Gems added; favourites never sold; Epic+ asks to confirm | ✅ |
| ☐ | Collection book | Silhouettes for undiscovered items; counters per crate; milestone claim once | ✅ (logic) |
| ☐ | Skill tree | Locked/available (pulsing)/unlocked/maxed states; prerequisites enforced; unlock animation; respec costs 100 Gems and refunds | ✅ |
| ☐ | Ascend | Disabled until the requirement; the confirm dialog lists the Prisms; afterwards Sparks and upgrades reset, everything else kept; stage banner; Plasma Crate unlocked | ✅ |
| ☐ | Prism perks | Buying raises the level; Head Start applies on the next ascension; Loyal Robots keeps Auto-Presser | ✅ |
| ☐ | Daily quests / bonus / starter path | Progress bars move; claim only when complete; the bonus needs all three | ✅ |
| ☐ | Achievements | *First Steps* unlocks at 100 presses with a banner and Gems | ✅ |
| ☐ | Daily login | Claim once; "Come back tomorrow"; the streak shows | ✅ |
| ☐ | Bonus orb | Appears within ~30–60 s, bobs, can be tapped once, then shows a reward toast | ✅ |
| ☐ | Offline earnings | Rejoin after ≥ 2 min with a Generator: *Welcome back* banner | ✅ |
| ☐ | Settings | Volumes, UI scale, background dim, reduced motion (no shake or particles), floating numbers, auto-sell; the values survive a rejoin | ✅ (save) |

### Persistence

| ✓ | Check | Expected | Auto |
|---|---|---|---|
| ☐ | Save and rejoin | Stop and Play again: currencies, items, skills, quests and settings are restored | ✅ |
| ☐ | Autosave | Wait 60 s and close Studio abruptly: at most ~1 minute is lost | ✅ |
| ☐ | API services disabled | Yellow "Not saving" badge plus a warning toast; nothing written | ✅ |
| ☐ | DataStore errors | Transient errors are retried; persistent load errors kick with a "rejoin" message instead of loading empty data | ✅ |
| ☐ | Two servers, one player | The second session waits; it is refused with a clear message while the first holds the lock; it takes over a stale lock | ✅ |
| ☐ | Lock stolen | The server that lost the lock stops saving and removes the player | ✅ |
| ☐ | Migration / invalid data | v1 records migrate; tampered values are clamped; unknown items are kept in LegacyInventory; newer-version data is not touched | ✅ |
| ☐ | Shutdown | Stopping the server saves every player (BindToClose waits up to 25 s) | ✅ |

### Admin panel

| ✓ | Check | Expected | Auto |
|---|---|---|---|
| ☐ | Authorised access | Owner, Admin and Moderator see 🛡️ Admin and F2 opens the panel; the role badge matches | ✅ |
| ☐ | Unauthorised access | Player4 has no button, F2 does nothing, and there is no `AdminPanelGui` in their PlayerGui | ✅ |
| ☐ | Direct remote exploit | The snippet in [`SETUP.md`](SETUP.md) prints `false Not authorized.`; the attempt shows under Audit Logs (denied) and in the security flags | ✅ |
| ☐ | Role differences | Moderator: no economy, items or progression. Admin: no progression reset or game-wide announce. Owner: everything. | ✅ |
| ☐ | Limits | Admin cannot add more than 1e15; Owner can | ✅ |
| ☐ | Rank protection | Admin cannot kick or freeze the Owner; Moderator cannot freeze the Admin | ✅ |
| ☐ | Currency add/remove/set | Target's HUD updates immediately; negative or NaN amounts rejected | ✅ |
| ☐ | Item and crate grants, inventory inspection | Item appears with a discovery toast; inspect lists counts | ✅ |
| ☐ | Drop-rate test | 10,000 simulated rolls close to expected; no player data changes | ✅ |
| ☐ | Player management | Teleport to / bring, freeze (can't move or jump) / unfreeze, respawn, kick with reason | ✅ |
| ☐ | Destructive confirmation | Reset currencies or progress opens a red dialog; nothing changes until confirmed; *all* requires typing the name | ✅ |
| ☐ | Command bar | `help`, `givecash Player4 1k`, ambiguous names rejected, bad numbers rejected, history with ↑/↓, Tab to complete | ✅ (server) |
| ☐ | `/admin` in chat | Runs the command for staff; for normal players it is just an ordinary chat message with no effect | ✅ |
| ☐ | Audit logs | Entries show admin, target, params and result; live updates; search and filters | ✅ |
| ☐ | Rate limits | Spamming freeze shows "rate limited" | ✅ |
| ☐ | Announcements | Server-wide banner labelled "this server"; game-wide (Owner) reaches other servers | ✅ |
| ☐ | Events | Start Spark Surge: every player's banner and timer, presses ×2; stop ends it | ✅ |

### Compatibility

| ✓ | Check | Expected | Auto |
|---|---|---|---|
| ☐ | Desktop 1920×1080 and 1280×720 | HUD clusters anchored to the edges, nothing overlaps, windows centred and scaled | ☐ manual |
| ☐ | Phone (Studio *Device* emulator, e.g. iPhone 14, landscape) | Compact layout: icon-only rail, side cards behind 📋, windows use the compact size; touch presses work | ✅ (logic) / ☐ visual |
| ☐ | Tablet | Normal layout scaled down | ☐ manual |
| ☐ | Controller | R2/L2 press; Y jumps to the menu; D-pad navigates; A selects; B closes windows; the panel is reachable | ✅ (press) / ☐ navigation |
| ☐ | Multiplayer | Several players press at the same time; the giant 3D button glows with server activity; Mythic drops announced to everyone | ✅ |
| ☐ | Performance | 8 players with full collections and auto-presses: no hitches; Dashboard memory and FPS stable | ✅ (sim) |
| ☐ | Large inventory | All 74 items with ×1000 copies: grid renders, filters and sorting instant | ✅ |

### Results of this build

* All automated checks above pass (94/94 tests, a clean type check, Rojo
  builds).
* The manual Studio checklist has **not** been run as part of this
  delivery; no Roblox Studio was available in the build environment. The
  items marked ✅ are covered by the headless simulation. Items marked
  ☐ manual (visual layout on real devices, controller navigation feel)
  should be confirmed once in Studio before publishing.
