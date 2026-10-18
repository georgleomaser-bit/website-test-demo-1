# Testing

Testing has two layers:

1. **Automated:** 163 tests that run the real game scripts in a headless
   Roblox simulation, plus static type checking. They run without Roblox
   Studio, in under a minute.
2. **Manual:** a checklist for things that need the real engine (rendering,
   real DataStores/MessagingService, real devices).

## Automated verification

| Check | Command | Result |
|---|---|---|
| Static type check against the Roblox API definitions (luau-lsp 1.70, `globalTypes.d.luau`) | `luau-lsp analyze --definitions=globalTypes.d.luau --sourcemap=sourcemap.json src` | **0 errors, 0 warnings** |
| Every file compiles (luau-compile) | `luau-compile --text <file>` | **all 100 scripts compile** |
| Rojo build | `rojo build default.project.json -o build/ButtonAscension.rbxlx` | **builds**; 1 Script, 2 LocalScripts, 97 ModuleScripts, 11 Folders |
| Headless game tests (Lune 0.10.4) | `lune run tests/run.luau` | **163 passed, 0 failed** |

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

#### Suite: admin
**Access**
- delivers the admin panel only to staff
- makes the place creator Owner in live servers and nobody else
- rejects every request from a normal player, however it is forged
- rejects malformed and duplicate requests from staff
**Group-owned places**
- asks Roblox once when several players join together and still finds the owner
- retries a failed group lookup instead of locking the owner out
**Roles and permissions**
- gives Owner, Admin and Moderator different powers
- protects staff of equal or higher rank from punitive actions
**Economy, items and progression tools**
- adds, removes and sets currency through core validation
- grants and removes items and crates, and runs test drops without changing odds
- grants upgrades, skills, ascensions, levels and skill points
**Confirmation of destructive actions**
- requires a single-use token from the same admin before resetting
- keeps a confirmation bound to the player it was issued for
- resets a chosen progression scope only after confirmation
- never takes away Robux purchases in a full reset
**Player management**
- freezes, unfreezes, teleports, respawns and kicks with a reason
**Command bar**
- parses commands, resolves players safely and validates arguments
**Safeguards**
- rate limits punitive actions and records everything in the audit log
- edits offline players only when the role allows it and no session holds the data
**Announcements and events**
- filters announcements, labels the scope and delivers game-wide ones to other servers
- starts and stops server events that change player stats

#### Suite: client
**Interface**
- boots without errors, hides the loading screen and presses through the big button
- opens and closes every screen from the navigation rail
- buys an upgrade from the shop
- opens a crate and plays the reveal
- equips an item from the inventory
- builds the skill tree up as skills are unlocked
- saves settings changed in the settings screen
**Devices**
- uses the compact layout on a phone with touch input
- presses the button with a controller trigger
- presses with the E key on a keyboard, so you can press while running
**Bottom HUD, obby and tutorial**
- puts the HUD at the bottom with only the quest card at the side, and keeps the world visible
- moves you to your obby checkpoint and back with the dock buttons
- shows the tutorial for new players, follows real progress and can be skipped and replayed
**Admin panel client**
- boots for an Owner and runs a command from the command bar

#### Suite: fusion
**Item catalogue**
- has two Secret items per crate and Golden/Rainbow versions of every item
**Fusing**
- turns three copies into the next variant, up to Rainbow
- protects favourites and gives the fused item the equipped copies' slot
- rejects forged and malformed fuse requests
**Variant drops**
- drops Golden and Rainbow items at their natural rates and never auto-sells them
**Rainbow Chest**
- grants exactly one Rainbow Epic-or-better item per receipt
- always rolls Rainbow, Epic or better, with a real Secret chance
**Saving**
- keeps variant items, equipped variants and variant discoveries when sanitising
**Fusing in the interface**
- fuses from the inventory detail panel and shows the variant on its card

#### Suite: fuzz
**Fuzzing**
- survives random payloads on every player action without throwing or granting anything
- survives random admin payloads from staff and outsiders

#### Suite: gameplay
**New player**
- gets default data, leaderstats, daily quests and a full snapshot
**Pressing**
- awards server-computed Sparks, XP and stats and ignores forged arguments
- caps instant click floods with the token bucket and flags them
- bursts a streak only every 50 chained presses, even once the combo is capped
- ignores presses before the profile has loaded
**Upgrades**
- rejects purchases without funds, unknown ids, bad amounts and locked tiers
- charges the server price and raises the level; MAX buys as many as affordable
**Crates**
- validates crate id, amount, mode, stage lock and funds
- rolls on the server, applies the items and ignores forged rarities
- guarantees a Legendary or better when pity is reached
- auto-sells duplicates up to the chosen rarity when enabled
**Inventory**
- equips only owned items within the slot limit and sells safely
- makes extra copies strengthen an equipped item
**Skill tree**
- enforces skill points and prerequisites
**Ascension**
- refuses early, then resets only the run and keeps permanent progress
- keeps Auto-Presser with Loyal Robots and grants Head Start sparks
**Quests, achievements and daily rewards**
- tracks the starter path and pays rewards once
- pays a daily quest only when complete and only once
- unlocks achievements automatically from stats
- lets the daily login reward be claimed once per UTC day
**Bonus orbs**
- only accepts the orb the server offered, once
**Settings and request validation**
- validates every setting and rejects unknown actions
- rate limits action spam

#### Suite: harness_selftest
**Instances**
- reports Roblox-style errors for invalid members, types and classes
- returns reflection defaults and computes GUI geometry
- fires Changed, property, attribute, child and Destroying signals
- clones deep trees with attributes and remaps internal references
- detects cyclic requires
**Scheduler**
- orders task.delay / task.wait / task.defer in virtual time
- lets tests yield: task.wait inside a test advances virtual time
- WaitForChild yields until the child appears or the timeout elapses
- records uncaught errors from script threads
- completes tweens and fires Completed
**DataStores**
- cancels UpdateAsync when the transform returns nil
- injects failures and rejects unstorable values
- shares one backend between two servers and serves ordered stores
**Network**
- round-trips remotes with Roblox serialisation rules
- replicates server changes and lets tests act as exploiters
- only replicates a PlayerGui to its owner and starts LocalScripts placed there
- delivers MessagingService messages between servers
- filters text and runs BindToClose on shutdown

#### Suite: moderation
**Staff roles given in the game**
- lets the Owner make a player Moderator, who can then kick, freeze and ban
- applies roles in every server within seconds, and takes them away again
- lets only Owners hand out roles, never Owner itself, and never changes config roles
- works for the session only in Studio without API access
- supports the command bar
**Bans**
- bans across servers, keeps the player out and mirrors the ban to Roblox
- limits Moderators to 7 days and protects equal or higher staff
- lets players back in when a ban expires
- bans offline players by #UserId or exact username
- keeps enforcing its own list when Roblox's Ban API fails, and refuses forged requests
**Moderation tab**
- lets an Owner give a role and ban a player from the admin panel
- shows Moderators the ban tools but not the staff tools

#### Suite: monetization
**Game passes**
- loads owned passes on join and applies them on the server
- adds auto clicker passes on top of the upgrade cap and stacks the OP passes
- grants a pass the moment Roblox reports the purchase and keeps it for the session
- keeps the last saved ownership when Roblox can't answer, and drops refunded passes
- does nothing for passes that are not set up yet
- can't be granted by anything a client sends
**Developer products**
- grants a product once, saves it first and ignores repeated receipts
- waits (NotProcessedYet) when the buyer is not here, unknown, or their data is not loaded
- never grants in a temporary session that can't save
- does not confirm a purchase whose save failed and grants it only once on the retry
- runs Sparks Rush only while playing, stacks its time and lets it expire
**Robux crates**
- opens a Robux crate on purchase with its guaranteed rarity, once per receipt
- always meets the rarity floor and only uses items from unlocked crates
- can't be opened through the normal crate action
- plays the opening animation on the buyer's screen
- defines every crate sound with a bundled fallback and sane volumes
**Store screen**
- lists passes and products and opens Roblox's purchase prompts
- hides passes and products that are not set up in live games

#### Suite: multiplayer
**Multiplayer**
- keeps each player's data isolated
- runs 8 players with full collections and auto-presses for 3 minutes
- shares server activity with every client

#### Suite: obby
**Obby course**
- builds 14 checkpoints and a finish next to the plaza
- counts checkpoints in order and pays each one once per run
- ignores teleports and impossibly fast runs and flags them
- sends you back to your checkpoint from kill bricks and the void, but only counts the living
- saves progress and puts you back on your checkpoint after rejoining
- finishes a run, pays the finish rewards, resets the run and returns you to the plaza
- only teleports to your own checkpoint or the plaza
- keeps auto-pressing while you run the course

#### Suite: persistence
**Saving**
- saves on leave, releases the lock and restores the data in another server
- autosaves while playing and keeps the session lock fresh
- saves every player when the server shuts down
**DataStore failures**
- retries transient failures while loading
- kicks instead of playing on empty data when loading keeps failing
- retries failed saves and reports them
- uses a clearly labelled temporary profile in Studio without API access and never writes
**Session locking**
- refuses a second server while the first holds a fresh lock
- waits for the other server to finish saving, then loads the newest data
- takes over a stale lock left behind by a crashed server
- keeps waiting while a crashed server's lock ages and takes over once it is stale
- stops saving and removes the player if another server took the lock
- never writes over data another server saved and released after taking over
**Schema and validation**
- migrates version 1 data to the current schema
- sanitises tampered or corrupted values
- refuses to touch data written by a newer game version
- refuses to overwrite an unreadable record
**Offline earnings**
- grants a capped share of passive income for time away

#### Suite: shared_config
**Configuration**
- loads every config module
- gives every weighted rarity of every crate a non-empty item pool
- keeps skill prerequisites, upgrades, achievements and quests consistent
**Skill tree**
- is a large, well-formed tree that can be bought from the core outward
- reveals the tree step by step as nodes are bought
**Loot**
- normalises effective weights for any luck value
- matches expected odds over 20,000 simulated openings per crate
- guarantees Legendary or better when the pity threshold is reached
**Economy invariants**
- never lets a Gem-priced crate be resold for more Gems than it costs, even fully maxed
- never creates Gems by fusing: a fused item is worth exactly its inputs
**Formulas and Format**
- computes finite stats for fresh and heavily progressed players
- computes stats from the server's default player data
- formats numbers like the UI expects

#### Suite: tutorial
**Tutorial**
- walks a new player through every step from real actions and pays the reward once
- only accepts 'seen' for the active look-at step and never for real-action steps
- saves a skip and keeps it after rejoining
- does not start for players saved before the tutorial existed

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

### Found in an independent code review and fixed

A separate review pass read the whole codebase looking for exploits and
edge cases. Each fix that can be simulated has a regression test that fails
on the old code.

* **Gem loop (economy).** Prism Cache drops resold for more Gems than the
  cache cost, and Gem crates got Spark-crate discounts and bonus drops.
  Gem-crate items now sell at a 10% factor, and discounts and bonus drops
  apply to Spark crates only. A test maxes every bonus and checks that
  resale stays below the price (worst case: 36 of 120 Gems).
* **Session lock wait.** A second server gave up after about 30 seconds,
  long before a crashed server's lock goes stale (150 s), and kicked the
  player. Loading now waits until the lock is stale (plus 15 s) and then
  takes it over.
* **Overlapping saves.** Autosave, a manual save and the leave/shutdown save
  could run at the same time, and a save after release could re-lock the
  record. Saves are now serialised and coalesced. Nothing is written after
  release, and a missing lock during any save (including the final one)
  counts as lost, so newer data saved by another server is never overwritten.
* **Confirmations followed names.** A confirmed admin action re-resolved the
  target by name, so it could hit someone else who joined with a matching
  name. The token now stores the resolved UserId.
* **Ascension grants.** `progression.grantRebirth` wipes a player's run but
  needed no confirmation and ignored rank protection. It is now both
  Destructive (confirmation) and Punitive (rank protection).
* **Streak bursts at the combo cap.** Once the combo reached its hard limit,
  every press triggered a streak burst. Streaks now use their own unclamped
  counter.
* **Daily quest targets.** Targets were scaled with event/Frenzy-boosted
  stats if a boost was running at reset. They now use base stats.
* **Group-owned places.** Concurrent joins raced the group-owner lookup, and
  a failed lookup was cached as "not staff". Callers now wait for the one
  lookup in flight. Failures are retried, never cached, and the panel is
  delivered once the lookup succeeds.
* **Security log flooding.** One player could fill the 300-entry flag buffer
  and push out everyone else's flags. Repeats of the same reason within 30
  seconds now update one entry.
* **UI fixes (found by reading the layout code).**
  * The navigation rail now always fits below the Roblox top bar.
  * The UI Scale setting can no longer push windows or the HUD off-screen.
  * The Inventory details panel scrolls instead of overlapping its buttons.
  * Equip slots share the row width when 8 are unlocked.
  * Large crate openings use smaller cards.
  * Opening effects draw above the reveal.
  * Segmented controls are sized correctly.
  * The loading screen blocks input.
  * The interface-size slider applies on release.
  * A window reopened during its close animation stays open.
  * The daily badge and timers use the server clock.
  * The crate screen no longer rebuilds on every XP gain.

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
| ☐ | Settings | Volumes, UI scale (applies on release), reduced motion (no shake or particles), floating numbers, auto-sell, Tutorial → Replay; the values survive a rejoin | ✅ (save) |
| ☐ | Fusing | 3 copies → "✨ Fuse 3 → Golden" in the item panel, burst and chime; 3 Golden → Rainbow with an animated rainbow border; favourites must be unfavourited first | ✅ |
| ☐ | Skill tree reveal | A fresh player sees the core and "?" teasers; buying a node grows its neighbours with lines; respec folds the tree back | ✅ |

### Obby, interface and tutorial

| ✓ | Check | Expected | Auto |
|---|---|---|---|
| ☐ | Bottom dock | Currencies, level, obby chip, boosts and menu at the bottom; quest card on the right; PRESS bottom right; the world is not darkened | ✅ (layout) / ☐ visual |
| ☐ | Press while moving | E (keyboard), the PRESS button and R2 press while the character walks; auto presses keep earning | ✅ |
| ☐ | Run the obby | All 15 stages are jumpable; movers and spinners carry you; kill bricks and falls return you to your checkpoint; pads turn green | ✅ (rules) / ☐ feel |
| ☐ | Obby rewards and anti-cheat | Sparks per checkpoint, Gems for first clears and the finish; skipping a checkpoint or teleporting gives nothing and shows up in security flags | ✅ |
| ☐ | Rejoin mid-course | You spawn at your saved checkpoint; ▶ and 🏠 in the dock move you to your checkpoint or the plaza | ✅ |
| ☐ | Tutorial | A new player gets the coach card and gold arrow; each step completes only when done; skip is saved; replay from Settings; 50 Gems once | ✅ |

### Robux store (needs the IDs from MONETIZATION.md)

| ✓ | Check | Expected | Auto |
|---|---|---|---|
| ☐ | Store screen | 💰 Store lists passes and products with prices; owned passes show OWNED; unconfigured items say "Not set up" in Studio | ✅ |
| ☐ | Buy a pass (Studio test purchase) | Effect applies at once (e.g. Auto Clicker +5/s) and stays after rejoining | ✅ (mock) |
| ☐ | Buy a product | Gems arrive once; a Robux crate plays the opening with the guaranteed rarity; Sparks Rush timer shows in the dock | ✅ (mock) |
| ☐ | Crate sounds | Rising ticks, burst, rising chimes; extra fanfare for Epic+, bigger for Legendary+, flash for Mythic/Secret | ☐ listen |

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
| ☐ | Give a role in the game | Owner → Moderation tab → Give role (Moderator) → confirm: the player gets the panel at once, in every server; Remove role takes it away | ✅ |
| ☐ | Ban | Moderator bans for 1 day with a reason: the player is removed and kicked on every rejoin with the reason and end date; Unban lets them back; Moderators cannot pick longer than 7 days or ban staff | ✅ |
| ☐ | Ban an offline player | Ban by exact username or #UserId; they are kicked when they join | ✅ |

### Compatibility

| ✓ | Check | Expected | Auto |
|---|---|---|---|
| ☐ | Desktop 1920×1080 and 1280×720 | HUD clusters anchored to the edges, nothing overlaps, windows centred and scaled | ☐ manual |
| ☐ | Phone (Studio *Device* emulator, e.g. iPhone 14, landscape) | Compact dock with icon-only menu, quest card behind 📋, PRESS above the jump button, windows use the compact size; touch presses work | ✅ (logic) / ☐ visual |
| ☐ | Tablet | Normal layout scaled down | ☐ manual |
| ☐ | Controller | R2/L2 press; Y jumps to the menu; D-pad navigates; A selects; B closes windows; the panel is reachable | ✅ (press) / ☐ navigation |
| ☐ | Multiplayer | Several players press at the same time; the giant 3D button glows with server activity; Mythic drops announced to everyone | ✅ |
| ☐ | Performance | 8 players with full collections and auto-presses: no hitches; Dashboard memory and FPS stable | ✅ (sim) |
| ☐ | Large inventory | All 81 items with ×1000 copies: grid renders, filters and sorting instant | ✅ |

### Results of this build

* All automated checks above pass (163/163 tests, a clean type check, Rojo
  builds).
* The manual Studio checklist has **not** been run as part of this
  delivery; no Roblox Studio was available in the build environment. The
  items marked ✅ are covered by the headless simulation. Items marked
  ☐ manual (visual layout on real devices, controller navigation feel)
  should be confirmed once in Studio before publishing.
