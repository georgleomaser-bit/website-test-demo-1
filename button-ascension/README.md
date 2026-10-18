# Button Ascension — a complete Roblox incremental clicker

*Press the button. Open the crates. Ascend.*

**Button Ascension** is a complete Roblox game written in Luau and inspired by
the mechanics of the Steam game *Click the Button*. You press a big central
button to earn currency, open crates for collectible items, buy upgrades,
unlock a skill tree and ascend for permanent bonuses. It also comes with a
secure Admin Panel. All branding, item names, icons and UI are original.

| | |
|---|---|
| **Engine** | Roblox (Luau, modern APIs — no deprecated `wait`/`spawn`/`delay`) |
| **Project format** | [Rojo 7](https://rojo.space) project + a ready-to-open place file |
| **Scripts** | 1 Script, 2 LocalScripts, 84 ModuleScripts (≈20,500 lines of game code) |
| **Content** | 74 items in 7 crates · 7 rarities · 10 upgrades in 3 tiers · 9 Prism perks · 30-node skill tree · 5 stages · 34 achievements · 10 daily-quest types + 10-step starter path · 7-day login calendar · 5 server events · bonus orbs · 3 global leaderboards |
| **Admin** | Owner / Admin / Moderator roles, 8-tab panel, 34 commands, audit log, confirmations, rate limits |
| **Verification** | luau-lsp type check (Roblox API definitions) clean · 94 automated tests on a headless Roblox simulation (gameplay, exploits, persistence, admin security, UI, multiplayer) |

---

## Quick start

### Option A — open the place file (fastest)

1. Open **`build/ButtonAscension.rbxlx`** in Roblox Studio (*File → Open from File*).
2. *File → Game Settings → Security* → turn on **Enable Studio Access to API Services**.
   This is needed so progress is saved in Studio. Without it the game still runs, but
   you get a clearly labelled temporary session that is never saved.
3. Press **Play**. You are automatically the **Owner** admin if the place
   belongs to you, or while the place is still unpublished (Studio only).
   Press **F2** or the **🛡️ Admin** button.

### Option B — Rojo (recommended for development)

```sh
rojo serve default.project.json     # then "Connect" in the Rojo Studio plugin
# or build a fresh place file:
rojo build default.project.json -o build/ButtonAscension.rbxlx
```

### Option C — copy and paste into an empty place

Follow [`docs/SETUP.md`](docs/SETUP.md). It lists every folder and script with
its exact name, type and location.

To publish: *File → Publish to Roblox*, enable API services for the live game,
and add your staff's UserIds to `ServerScriptService/Admin/AdminConfig`
(see [`docs/ADMIN.md`](docs/ADMIN.md)).

---

## What's in the game

* **Pressing.** The big animated button squashes, sends out shockwaves, sparks
  and sounds, and shows floating reward numbers. It also has combos, a combo
  meter, critical presses, streak bursts every 50 presses, rare **golden
  presses** and timed **Frenzy** boosts. It works with mouse, touch and
  controller (R2/L2).
* **Economy.** There are three currencies:
  * ⚡ **Sparks**, earned by pressing and spent in the Shop and on crates
  * 💎 **Gems**, from quests, achievements and selling items, spent on the Prism Cache and on skill respecs
  * 🔷 **Prisms**, the ascension currency, spent on permanent perks
* **Upgrades.** There are 10 upgrades in 3 tiers: click power, generator
  (passive income), amplifier (multiplier), crit chance, crit power,
  Auto-Presser, luck, bonus-drop chance, golden chance and XP. Each shows its
  current and next effect, can be bought ×1, ×10 or MAX, and costs more at
  every level.
* **Crates.** There are 7 crate tiers, with prices in Sparks or Gems. Opening
  is animated: the crate shakes, the glow hints at the rarity, then a burst
  and light rays lead into card reveals. Rarities are Common, Uncommon, Rare,
  Epic, Legendary, Mythic and **Secret**. Luck shifts the odds, which are shown
  for every crate. Legendary and Mythic **pity** guarantees a drop. Crates can
  give bonus drops, duplicates can be auto-sold, and NEW discoveries are
  announced.
* **Inventory and collection.** The inventory is a stacked, pooled grid with
  search, a rarity filter and 4 sorts. You can equip items (3–8 slots), use
  Equip Best, favourite items, sell one, sell extras, sell all, or sell
  duplicates. Extra copies make an equipped item up to twice as strong. The
  **Collection Book** shows silhouettes for undiscovered items, gives +1%
  Sparks per discovery and has 8 claimable milestones.
* **Skill tree.** A pannable canvas holds 30 connected nodes in 5 branches:
  Strength, Fortune, Wealth, Precision and Special. Nodes have prerequisites,
  multi-rank costs, tooltips and pulsing "available" states, plus unlock
  animations and a Gem respec.
* **Ascension (rebirth).** When you ascend you get Prisms and a permanent ×0.5
  Sparks per ascension. Ascending also unlocks new **stages**, which change the
  button's colour and bring new crates. The ascension screen lists exactly
  what is reset and what is kept (see below).
* **Long-term progression.**
  * Levels and XP: Skill Points every level and a crate every 5 levels.
  * Daily quests, plus a bonus for finishing them all.
  * A guided 10-step starter path.
  * A 7-day login calendar.
  * 34 achievements and 25 tracked statistics.
  * Offline earnings.
  * Global leaderboards (OrderedDataStore) and a live board for your server.
* **Multiplayer.** Every player has their own data. The 3D giant button pulses
  with the whole server's presses per second. Mythic and Secret drops are
  announced to the server. Admins can start server events.

### What ascension resets and keeps

| Reset | Kept |
|---|---|
| Sparks. You restart with your *Head Start* perk amount. | Gems, Prisms, all Ascension (Prism) perks |
| Every Shop upgrade level. Auto-Presser is kept if you own *Loyal Robots*. | Skill tree, Skill Points, level and XP |
| "Sparks earned this run" and your current combo | Inventory, equipped items, favourites and the Collection Book |
| | Owned crates and pity progress |
| | Achievements, quests, login streak, statistics and settings |

---

## Documentation

| Document | Contents |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Architecture, the full Explorer hierarchy, data flow, remotes, security model and design decisions |
| [`docs/SCRIPTS.md`](docs/SCRIPTS.md) | Every script: file, type, exact Explorer location, dependencies and purpose |
| [`docs/SETUP.md`](docs/SETUP.md) | Step-by-step setup: place file, Rojo, or manual copy-and-paste, plus publishing |
| [`docs/ADMIN.md`](docs/ADMIN.md) | Roles and permissions, adding admins and finding UserIds, the panel, commands, audit logs, safeguards |
| [`docs/GAME_DESIGN.md`](docs/GAME_DESIGN.md) | Economy and balance (with simulation results), crates and odds, pity, skills, quests, data schema |
| [`docs/TESTING.md`](docs/TESTING.md) | Automated test suite, the full manual testing checklist and results |
| [`tests/README.md`](tests/README.md) | How the headless Roblox test harness works and how to run it |

## Project layout

```
button-ascension/
├── default.project.json        Rojo project (maps src/ to the Roblox services)
├── build/ButtonAscension.rbxlx Ready-to-open place file built from src/
├── src/
│   ├── ReplicatedStorage/      Shared config, formulas, remotes, UI kit (client + server)
│   ├── ServerScriptService/    Main script, core, gameplay services, admin system
│   ├── ServerStorage/          Admin Panel client (only cloned to authorised staff)
│   └── StarterPlayer/          Client entry point, HUD, screens, input, effects
├── tests/                      Headless Roblox simulation + 94 tests (Lune)
└── docs/                       Documentation
```

## Status and known limitations

The game is feature-complete against the original specification. Every
system listed above is implemented, connected to the UI and covered by
automated tests.

These limitations are honest constraints, not unfinished work:

* **No Roblox Studio was available while building this.** Everything was
  verified with the Roblox type definitions (luau-lsp), a Rojo build and a
  headless Roblox simulation that checks every UI property against the
  official API database. Pixel-level layout, real rendering and real
  DataStore/MessagingService servers can only be confirmed in Studio. Use the
  manual checklist in [`docs/TESTING.md`](docs/TESTING.md) for that.
* **Audio.** Sound effects use sound files that ship with the Roblox client
  (`rbxasset://sounds/...`). Roblox includes no background music, so the music
  setting is ready but `Config/Sounds.Music.Id` is empty until you add a track
  you own.
* **Icons.** Items and UI use emoji glyphs instead of uploaded images, so
  nothing has to be uploaded. You can swap them for image assets later.
* **Game-wide announcements** use MessagingService. Only Owners have the
  permission by default, and Roblox applies its own MessagingService rate
  limits. Server events and normal announcements affect only the current
  server, and are labelled that way.
* **Offline admin edits** cover currencies, items and crates, plus read-only
  inspection. They are applied only when no live session holds the player's
  data lock. Other progression tools need the player online.
* **Saving is never guaranteed.** Saves are retried with backoff, session-locked
  and done at shutdown. If Roblox's data services fail completely, the failure
  is logged and shown to admins. Players whose data cannot be loaded are asked
  to rejoin, so they never play on empty data that could overwrite their real
  progress.
