# Click a Button — a complete Roblox incremental clicker

*Press the button. Open the crates. Ascend.*

**Click a Button** is a complete Roblox game written in Luau and inspired by
the mechanics of the Steam game *Click the Button*. You press the button to
earn currency, open crates for collectible items, fuse them into Golden and
Rainbow versions, buy upgrades, grow a skill tree, run an obby while your
auto clicker keeps earning, and ascend for permanent bonuses. It comes with a
secure Admin Panel (staff roles and bans) and a Robux store with game passes
and developer products. All branding, item names, icons and UI are original.

Internally (folder, file and DataStore names) the project is still called
`ButtonAscension`; players only ever see **Click a Button**. The store-page
description, icon and thumbnails are in [`branding/`](branding/STORE_PAGE.md).

| | |
|---|---|
| **Engine** | Roblox (Luau, modern APIs — no deprecated `wait`/`spawn`/`delay`) |
| **Project format** | [Rojo 7](https://rojo.space) project + a ready-to-open place file |
| **Scripts** | 1 Script, 2 LocalScripts, 98 ModuleScripts (≈26,000 lines of game code) |
| **Content** | 81 items in 7 crates · 7 rarities · Golden and Rainbow variants with fusing · 10 upgrades in 3 tiers · 9 Prism perks · 65-node skill tree that reveals itself as you buy · 5 stages · 15-stage obby · 37 achievements · 10 daily-quest types + 10-step starter path · 7-step tutorial · 7-day login calendar · 5 server events · bonus orbs · 3 global leaderboards |
| **Robux** | 9 game passes (Auto Clicker, OP Auto Clicker, 2×/3× Sparks, 2× Gems, Lucky, Super Luck, Fast Crates, VIP) · 9 developer products (Gem packs, Sparks Rush, Crate Bundle, OP / Mega OP / Ultra OP crates, Rainbow Chest). Live: OP CLICKER and 9 Sparks/Gems/boost items from the owner's Creator Hub; the rest are ready and appear once their IDs are set, see [`docs/MONETIZATION.md`](docs/MONETIZATION.md) |
| **Admin** | Owner / Admin / Moderator roles, Owners hand out Moderator/Admin in the game, bans across all servers (also via Roblox's Ban API), 9-tab panel, 41 commands, audit log, confirmations, rate limits |
| **Verification** | luau-lsp type check (Roblox API definitions) clean · 169 automated tests on a headless Roblox simulation (gameplay, obby, fusing, Robux purchases, exploits, persistence, moderation, admin security, UI, multiplayer) |

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

To publish: *File → Publish to Roblox* and enable API services. Then:

* give people roles in the game (Admin Panel → Moderation tab, see
  [`docs/ADMIN.md`](docs/ADMIN.md)),
* create the game passes and developer products and paste their IDs (German
  quick start at the top of [`docs/MONETIZATION.md`](docs/MONETIZATION.md)),
* set the name, description, icon and thumbnails from
  [`branding/STORE_PAGE.md`](branding/STORE_PAGE.md).

---

## What's in the game

* **Pressing, anywhere.** You run around the 3D world; the PRESS button sits at
  the bottom right (above the jump button on phones) and also works with **E**
  and the controller triggers. It squashes, sends out shockwaves, sparks and
  sounds, and shows floating reward numbers. It has combos, critical presses,
  streak bursts every 50 presses, rare **golden presses** and timed **Frenzy**
  boosts. Auto presses keep earning while you do anything else.
* **Interface.** Everything sits in a dock at the bottom of the screen
  (currencies, level, obby progress, boosts, menu); the quest card stays on the
  right. A 7-step **tutorial** walks new players through pressing, upgrades,
  crates, equipping, quests and the obby, and can be replayed from Settings.
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
  announced. Each crate has two Secret items, and any drop can come out
  **Golden** (1.5%) or **Rainbow** (0.15%). Openings have layered sounds with
  extra fanfares for rare drops.
* **Fusing.** 3 copies of an item fuse into 1 **Golden** (×2.5 power), 3 Golden
  into 1 **Rainbow** (×6 power, animated rainbow border). A fused item always
  sells for exactly what its three inputs would.
* **Inventory and collection.** The inventory is a stacked, pooled grid with
  search, a rarity filter and 4 sorts. You can equip items (3–8 slots), use
  Equip Best, favourite items, sell one, sell extras, sell all, or sell
  duplicates. Extra copies make an equipped item up to twice as strong. The
  **Collection Book** shows silhouettes for undiscovered items, gives +1%
  Sparks per discovery and has 8 claimable milestones.
* **Skill tree.** 65 connected nodes in 5 branches (Strength, Fortune, Wealth,
  Precision and Special). The tree **builds itself up as you buy**: you only see
  what you can buy now, the next ring as "?" silhouettes, and new nodes grow out
  with an animation. Nodes have prerequisites, multi-rank costs and tooltips;
  the canvas pans and zooms, and a Gem respec folds it back.
* **Obby.** A 15-stage neon obstacle course next to the plaza with moving and
  spinning platforms, 14 checkpoints and a finish. Checkpoints and first clears
  pay Sparks and Gems; the server checks order and travel time, so teleporting
  earns nothing. Your checkpoint is saved.
* **Robux store.** Game passes and developer products, including OP crates for
  99/199/299 R$ with guaranteed Epic/Legendary/Mythic drops and a Rainbow Chest.
  Every purchase is granted only by the server and confirmed to Roblox only
  after it has been saved.
* **Ascension (rebirth).** When you ascend you get Prisms and a permanent ×0.5
  Sparks per ascension. Ascending also unlocks new **stages**, which change the
  button's colour and bring new crates. The ascension screen lists exactly
  what is reset and what is kept (see below).
* **Long-term progression.**
  * Levels and XP: Skill Points every level and a crate every 5 levels.
  * Daily quests, plus a bonus for finishing them all.
  * A guided 10-step starter path.
  * A 7-day login calendar.
  * 37 achievements and tracked statistics.
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
| | Obby progress and everything bought with Robux |

---

## Documentation

| Document | Contents |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Architecture, the full Explorer hierarchy, data flow, remotes, security model and design decisions |
| [`docs/SCRIPTS.md`](docs/SCRIPTS.md) | Every script: file, type, exact Explorer location, dependencies and purpose |
| [`docs/SETUP.md`](docs/SETUP.md) | Step-by-step setup: place file, Rojo, or manual copy-and-paste, plus publishing |
| [`docs/ADMIN.md`](docs/ADMIN.md) | Roles and permissions, giving roles in the game, banning, adding admins in code, the panel, commands, audit logs, safeguards |
| [`docs/MONETIZATION.md`](docs/MONETIZATION.md) | Game passes and developer products: what they do, suggested prices, how to create them and paste the IDs (German quick start) |
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
├── tests/                      Headless Roblox simulation + 169 tests (Lune)
├── branding/                   Store-page description, icon, thumbnails, pass icons (+ sources)
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
* **Phone notches.** The HUD keeps clear of the Roblox top bar (GUI inset), but
  does not yet read the device safe area. On phones with a notch or rounded
  corners in landscape, the edges of the bottom dock can sit slightly under the
  notch. Check this on a real device.
* **Obby feel.** The course, rewards and anti-cheat are tested headless, but
  jump distances and the moving platforms' physics can only be judged by
  playing. All gaps are 8 studs or less; play it through once in Studio.
* **Robux items** do nothing until you create the passes and products in the
  Creator Hub and paste their IDs into `Config/GamePasses` and
  `Config/DevProducts`. In Studio, unconfigured items are shown as "Not set up";
  in live games they are hidden.
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
