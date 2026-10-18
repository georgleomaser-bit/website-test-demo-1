# Game design and balance

Every number on this page comes from `ReplicatedStorage/Shared/Config/*`.
Change the config and the whole game follows: server logic, client
previews, odds displays and tests.

## Core loop

```
press the button ──► Sparks + XP ──► Shop upgrades ──► more Sparks per press / second
        │                               │
        ▼                               ▼
 golden presses, orbs,           crates (Sparks / Gems) ──► items ──► equip bonuses,
 quests, achievements                                       collection bonus, Gems from duplicates
        │
        ▼
 level ups ──► Skill Points ──► skill tree (permanent)
        │
        ▼
 enough Sparks this run ──► ASCEND ──► Prisms + permanent ×0.5 per ascension ──► Prism perks,
                                       new stage (new crate, button colour, stage multiplier)
```

## Pressing

| Mechanic | Value (GameConfig.Click) |
|---|---|
| Base press | 1 Spark × all multipliers |
| Server rate limit | 20 presses/s sustained, burst 30 (excess is dropped, floods over 35/s are flagged) |
| Combo | Presses within 1.0 s keep the combo going; +1% value per stack up to the combo cap (100, raised by skills and perks). The combo keeps counting past the cap for streaks. |
| Streak burst | Every 50 consecutive presses: click value × 20 × streak multiplier × √(combo/50) |
| Critical press | 2% base chance (cap 75%), ×3 base multiplier (raised by Overload and skills) |
| Golden press | 0.4% base chance (cap 5%). Pays one of: Sparks (150 presses' worth, 50%), Gems 2–6 (30%), a crate (15%), Frenzy ×3 for 15 s (5%). |
| Auto-presses | Auto-Presser (0.5/s per level, max 15/s including skills). They can crit, earn half XP, and don't combo. |
| Passive income | Spark Generator: 1.5 × level × 1.06^level per second × multipliers |
| Offline earnings | 25% of passive income for up to 2 h while away (more with Night Shift / Night Owl). Needs ≥ 2 min away and is calculated from the last save. |
| Bonus orbs | Every 70–140 s an orb floats onscreen for 9 s. Rewards: 60 s of income or 120 presses' worth (45%), 3–8 Gems (25%), a crate (15%), Frenzy ×3 for 20 s (15%). |

### Stat formula

```
sparksMultiplier = (1 + Σ sparks%) × Π sparks× (Amplifier, Eternal Power, skills, events)
                 × (1 + 0.5 × ascensions) × stage multiplier × (1 + 1% × discovered items) × Frenzy
clickValue       = (1 + Σ flat click) × (1 + Σ click%) × Π click× × sparksMultiplier
passivePerSec    = generatorFlat × (1 + Σ passive%) × sparksMultiplier
```

## Currencies

| Currency | Earned from | Spent on | Reset on ascension? |
|---|---|---|---|
| ⚡ Sparks | Presses, auto-presses, passive, golden presses, orbs, streaks, offline | Shop upgrades, Sparks crates | **Yes** (start with Head Start) |
| 💎 Gems | Quests, achievements, daily rewards, selling items, golden presses, orbs | Prism Cache, skill respec | No |
| 🔷 Prisms | Ascending, collection milestones | Ascension perks | No |

## Shop upgrades (reset on ascension)

The cost of the next level is `BaseCost × Growth^level`. Buy ×1, ×10 or MAX.

| Upgrade | Tier | Effect per level | Base cost | Growth | Max |
|---|---|---|---|---|---|
| 👆 Reinforced Switch | 1 | Adds base power to every press. Power per level doubles every 25 levels. | ⚡ 15 | ×1.15 | 500 |
| 🔋 Spark Generator | 1 | Produces Sparks every second, even while you rest. | ⚡ 60 | ×1.16 | 300 |
| 📢 Amplifier | 1 | Multiplies ALL Sparks you earn by ×1.1 per level. | ⚡ 400 | ×1.6 | 60 |
| 🎯 Precision Sensor | 1 | +1% critical press chance per level. | ⚡ 200 | ×1.45 | 40 |
| 🤖 Auto-Presser | 2 | +0.5 automatic presses per second per level. | ⚡ 1.5K | ×2 | 20 |
| 🍀 Fortune Coil | 2 | +4% Luck per level. | ⚡ 800 | ×1.5 | 50 |
| 💥 Overload Capacitor | 2 | +0.25× critical press multiplier per level. | ⚡ 5K | ×1.7 | 20 |
| 🧭 Treasure Sense | 3 | +1.5% chance per level for a crate to drop a bonus item. | ⚡ 500K | ×1.6 | 30 |
| 🌟 Lucky Star | 3 | +10% golden press chance per level. | ⚡ 300K | ×1.55 | 30 |
| 📘 Scholar's Lens | 3 | +10% XP from every source per level. | ⚡ 200K | ×1.5 | 40 |

Tier II unlocks at **level 8**, Tier III after the **first ascension**.

## Ascension (rebirth)

| | |
|---|---|
| Requirement | Sparks earned **this run** ≥ 3M × 6^ascensions (3M, 18M, 108M, 648M, 3.9B, 23B, …) |
| Prisms | ⌊(3 + ascensions) × min(50, earned ÷ requirement)^0.35 × Prism multiplier⌋, at least 1. Overshooting the requirement pays more. |
| Permanent bonus | +50% Sparks per ascension (additive) |
| Resets | Sparks (you restart with the Head Start amount), all Shop upgrade levels (Auto-Presser kept with Loyal Robots), Sparks earned this run, combo |
| Keeps | Gems, Prisms, Prism perks, skill tree and Skill Points, level and XP, inventory, equipped items, favourites, Collection Book, owned crates, pity counters, achievements, quests, login streak, statistics, settings |

### Stages

| Stage | Ascensions | Sparks × | Unlocks |
|---|---|---|---|
| Neon Core | 0 | 1 | Spark Crate, Neon Crate, Prism Cache |
| Plasma Vault | 1 | 1.25 | Plasma Crate |
| Void Expanse | 3 | 1.6 | Void Crate |
| Celestial Spire | 6 | 2.2 | Celestial Crate |
| Singularity | 10 | 3.2 | Singularity Core |

Each stage also recolours the button, both the HUD button and your local
view of the 3D giant button.

### Prism perks (permanent)

| Perk | Effect | Base cost | Growth | Max |
|---|---|---|---|---|
| ♾️ Eternal Power | +25% Sparks from every source per level | 🔷 2 | ×1.3 | 100 |
| 🏁 Head Start | Begin every run with 500 × 8^(level−1) Sparks | 🔷 3 | ×2 | 8 |
| 🤖 Loyal Robots | Keep Auto-Presser levels when you ascend | 🔷 12 | — | 1 |
| 🍀 Prismatic Luck | +10% Luck per level | 🔷 3 | ×1.5 | 20 |
| 🎒 Deep Pockets | +1 equip slot per level | 🔷 10 | ×3 | 3 |
| 🔷 Prism Refinery | +10% Prisms per ascension per level | 🔷 4 | ×1.45 | 25 |
| 🏷️ Crate Broker | −3% Spark crate prices per level | 🔷 5 | ×1.6 | 10 |
| 🦉 Night Owl | +1 h offline earnings and +5% offline rate per level | 🔷 4 | ×1.7 | 6 |
| 🔥 Combo Mastery | +20 combo cap per level | 🔷 6 | ×2 | 5 |

### Balance simulation

A simulated player pressing 7 times per second, buying the best upgrade
greedily and spending every Prism on Eternal Power (no items and only a few
skills) reaches each ascension after:

| Run | 1 | 2–7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 |
|---|---|---|---|---|---|---|---|---|---|
| Time | ~7 min | 3–7 min each | ~11 min | ~20 min | ~37 min | ~44 min | ~1 h 20 | ~2 h 15 | ~4 h 20 |

The early game is fast and the later runs need real progression: items,
skills, Prism perks and crates. Real players are slower at first (they read
the UI) and faster later (the simulation ignores item bonuses and most of the
skill tree). Pace is controlled by `GameConfig.Rebirth.BaseRequirement` and
`RequirementGrowth`.

## Levels and XP

* XP for the next level is `⌊40 × level^1.55⌋`: 40 at level 1, 1,419 at
  level 10, 17,197 at level 50.
* XP comes from presses (1 each, auto-presses 0.5), crates (6 × crate tier)
  and quests. It is multiplied by the XP bonuses.
* Every level gives 1 Skill Point, and every 5th level gives +1 extra Skill
  Point and the best Sparks crate for your stage. The maximum level is 1,000.

## Crates and drops

| Crate | Price | Unlocks at | Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret | Pity |
|---|---|---|---|---|---|---|---|---|---|---|
| 📦 Spark Crate | ⚡ 250 | Neon Core (0) | 62% | 25% | 9% | 3% | 0.8% | 0.18% | 0.02% | Legendary 80, Mythic 500 |
| 🎁 Neon Crate | ⚡ 8K | Neon Core (0) | 55% | 27% | 11.5% | 4.6% | 1.5% | 0.36% | 0.04% | Legendary 70, Mythic 450 |
| 🧰 Plasma Crate | ⚡ 1.5M | Plasma Vault (1) | 50% | 28% | 13.5% | 6% | 2% | 0.45% | 0.05% | Legendary 65, Mythic 400 |
| 🗃️ Void Crate | ⚡ 60M | Void Expanse (3) | 46% | 29% | 15% | 7% | 2.4% | 0.58% | 0.07% | Legendary 60, Mythic 380 |
| 🌠 Celestial Crate | ⚡ 15B | Celestial Spire (6) | 42% | 30% | 16.5% | 8% | 2.7% | 0.7% | 0.1% | Legendary 55, Mythic 350 |
| 🌌 Singularity Core | ⚡ 8T | Singularity (10) | 38% | 31% | 18% | 9% | 3% | 0.85% | 0.15% | Legendary 50, Mythic 320 |
| 💠 Prism Cache | 💎 120 | Neon Core (0) | — | — | 60% | 28% | 9.5% | 2.3% | 0.2% | Legendary 25, Mythic 150 |

* **Luck** multiplies each rarity's weight by (1 + luck)^power. The powers
  are Common 0, Uncommon 0.2, Rare 0.5, Epic 0.8, Legendary 1, Mythic 1.1,
  Secret 0.6, and the weights are then normalised. In a Spark Crate, +100%
  luck turns Legendary 0.8% → 1.45% and Mythic 0.18% → 0.35%. The crate
  screen always shows the odds *with your current luck*.
* **Pity:** each crate counts openings since your last Legendary-or-better
  (and Mythic-or-better) drop. The opening that reaches the threshold is
  guaranteed that rarity or better. The *Pity Breaker* skill lowers the
  thresholds by 10% per rank. Bonus drops never use or advance pity.
* **Bonus drops** (Treasure Sense and skills) roll an extra item with the
  same odds.
* **Gem crates** (the Prism Cache) get no crate discount and no bonus drops;
  those bonuses apply to Spark crates only.
* **Every roll happens on the server** with `Random.new()`. The client
  receives only the results, after they have been applied.

## Items (81)

* Every crate has 12 items (3 Common, 2 Uncommon, 2 Rare, 1 Epic,
  1 Legendary, 1 Mythic, 2 Secret). The Prism Cache has 9 items, Rare or
  better.
* **Equip bonus** = rarity base (Common 2% … Legendary 30%, Mythic 60%,
  Secret 150%) × crate tier factor (1, 1.5, 2.5, 4, 6.5, 10; Prism Cache 3)
  × stat factor. The stat factors are Sparks 1, click 1.5, luck 0.6,
  crit 0.12, passive 2, XP 1.5, Gems 1 and golden 1.
* **Copies:** each extra copy adds +10% to an equipped item's power, up to
  +100% (11 copies).
* **Equip slots:** 3 base. Collector's Satchel adds up to +2 and Deep
  Pockets up to +3; the maximum is 8.
* **Selling** pays Gems: the rarity value (Common 1 … Secret 3,000) × the
  crate tier factor × the Gem multiplier (capped at ×50). Items from the
  Gem-priced Prism Cache use a sell factor of 0.1 instead and ignore Gem
  boosts, so buying caches and selling the drops always loses Gems: even with
  every pass, Rainbow Gem items and every bonus maxed, a cache resells for at
  most about 10 of its 120 Gems. Favourite items cannot be sold. The
  *auto-sell duplicates* setting sells repeat drops up to a chosen rarity the
  moment they drop (never Golden or Rainbow copies).
* **Collection Book:** +1% Sparks per discovered item. Milestones at 5, 10,
  20, 30, 40, 50, 60 and all 81 discoveries give Gems, Skill Points, crates
  and Prisms. Golden and Rainbow versions are tracked (shown in the item
  tooltip) but don't count as extra entries.

### Golden and Rainbow variants, fusing

| Variant | Equip power | Sells for | Natural drop chance | Made by fusing |
|---|---|---|---|---|
| Normal | ×1 | ×1 | — | — |
| ✦ Golden | ×2.5 | ×3 | 1.5% of every crate roll | 3 Normal copies |
| ✦ Rainbow | ×6 | ×9 | 0.15% of every crate roll | 3 Golden copies |

* Every item exists in all three versions (ids `<item>:golden` and
  `<item>:rainbow`). Each version stacks, equips and gets the copies bonus on
  its own.
* **Fuse** (Inventory → item → "✨ Fuse 3 → Golden/Rainbow", or "Fuse all"):
  the server checks the copies, removes 3 per result and adds one of the next
  version. Favourites must be unfavourited first. If the equipped copies are
  used up, the fused item takes their slot.
* A fused item sells for exactly what its three inputs sell for together, so
  fusing never creates Gems (tested for every item and many Gem multipliers).
* Variant rolls are independent of rarity and never change pity; bonus drops
  can be variants too. Robux OP crates have better variant odds, and the
  Rainbow Chest always gives a Rainbow item.
* Fusing counts towards the `ItemsFused` stat and the achievements Fusion
  Novice (1), Fusion Master (25) and Over the Rainbow (get any Rainbow item).

## Skill tree (65 nodes, permanent)

| Branch | Direction | Nodes | Highlights |
|---|---|---|---|
| Core | centre | 1 | Awakening: +10% Sparks |
| Strength | up | 14 | Click power %, combo cap and window, streak bursts, Titan Grip ×1.5, **Button Crusher ×2**; outer ring: Iron Knuckles, Overdrive ×1.25, Unbreakable ×1.5, **Earthshaker ×2.5** |
| Fortune | right | 13 | Luck, bonus items, crate discount, golden chance, pity, **Fortune's Favorite +75% luck**; outer ring: Jackpot Aura, **Lady Luck** (+30% luck, golden ×1.5) |
| Wealth | down | 13 | Sparks %, passive %, Gems %, offline earnings, auto-presses, **Golden Economy ×1.75**; outer ring: Power Plant, Spark Vault ×1.25, **Infinite Economy** (Sparks ×2, passive ×1.5) |
| Precision | left | 12 | Crit chance and multiplier, **Supercritical**; outer ring: Deadeye, Executioner, **Singularity Strike** (+3× crit multiplier) |
| Special | diagonals | 12 | Four bridges between neighbouring branches next to the core (each needs both neighbours), equip slots, XP (×1.25 per rank further out), Prism yield, orbs, Golden Hoard |

Each main branch ends in a capstone and, further out, an ascended capstone
(`_cap2`). Buying every rank of every node costs 472 Skill Points (single
ranks cost 1 to 12), so the outer ring is a long-term goal across many
ascensions. A respec costs 100 Gems and refunds every point.

**The tree builds itself up as you buy it** (`Skills.visibility`):

* *Visible:* the core, every owned node, and every node whose prerequisites
  are met. These show their name, effect, rank and cost.
* *Teaser:* the next ring, i.e. nodes connected to a visible node. They show
  only as a dim "?" with no name, effect or cost.
* *Hidden:* everything further out, including connector lines.

A new player sees the core and four "?" neighbours. Unlocking a node pops its
neighbours in, and their connector lines draw outward from it. The scrollable
canvas only covers the revealed part, so it grows with the tree. Zoom buttons
(−, +, fit) help on bigger trees. A respec folds the tree back to the core.
With Reduced motion, everything changes instantly. The server still checks
prerequisites and costs for every unlock.

## Quests, achievements and rewards

* **Daily quests:** three per UTC day, chosen per player from 10 types:
  * press, crits, crates, upgrades, combo, golden presses
  * orbs, items sold, Sparks earned, minutes played

  Targets scale with ascensions; the Sparks target scales with your click
  value. Each quest pays Gems or crates, and claiming all three adds a bonus
  of 40 Gems and a Prism Cache.
* **Starter path:** 10 guided steps:
  1. press 25 times
  2. buy an upgrade
  3. open a crate
  4. equip an item
  5. reach level 5
  6. unlock a skill
  7. reach a 50 combo
  8. tap an orb
  9. earn 1M Sparks in a run
  10. ascend

  Each step has a reward. The current step is always shown on the HUD.
* **Achievements:** 34, covering presses, lifetime Sparks, crates,
  discoveries, Legendary/Mythic/Secret finds, crits, combos, golden presses,
  ascensions, upgrades, Skill Points, level, quests and orbs. They unlock
  automatically and pay Gems, Skill Points and crates.
* **Daily login:** a 7-day cycle (15 Gems → … → 100 Gems + 2 SP + Prism
  Cache). Claim once per UTC day; missing a day resets the streak.

## Server events

| Event | Effect | Default length |
|---|---|---|
| ⚡ Spark Surge | All Sparks ×2 | 10 min |
| 🍀 Lucky Hour | +100% Luck | 15 min |
| 🌟 Golden Rush | Golden presses ×4 | 10 min |
| 🎯 Critical Frenzy | +25% Crit Chance | 10 min |
| 📘 Knowledge Storm | XP ×2 | 15 min |

Admins start and stop events. An automatic 5-minute event also starts every
30 minutes when none is running.

## Leaderboards

The global boards are **Lifetime Sparks**, **Total Presses** and
**Ascensions**. They are stored in OrderedDataStores. Lifetime Sparks are
stored as `⌊log10(x+1) × 10^6⌋` because those stores only hold integers.
Each server publishes every ~2.5 minutes and when a player leaves, and
refreshes the top 25 every 2 minutes. A live board for the current server is
always available. The Roblox player list shows **Ascensions** and **Sparks**
(leaderstats).

## Interface (HUD)

There is no full-screen "clicker mode": the 3D world stays visible and the
character can walk, jump and run the obby while pressing. The HUD sits at
the bottom of the screen (`Client/Hud`):

* **Dock** (bottom centre), rows from the bottom: the menu (Shop, Crates,
  Items, Skills, Book, Quests, Ascend, Stats, Store, Settings, with badges);
  Sparks, Gems, Prisms, level/XP and ascension progress (opens Ascend);
  obby progress with **▶** (go to your checkpoint) and **🏠** (back to the
  plaza) plus the live chips (crit, luck, auto presses and what they earn per
  second, total multiplier); boost timers; the "not saving" warning.
* **PRESS button** (bottom right) with the combo meter and the income per
  press / per second. On touch screens it sits above Roblox's jump button.
  Keyboard **E** and controller **R2/L2** press too, so pressing works while
  running.
* **Quest card** (right side) — the only element not at the bottom. On
  phones it hides behind the 📋 toggle under the Roblox top bar.
* Windows open over the world as before and dim it while open.

## Obby

A 15-stage obstacle course starts at the gate on the east edge of the plaza
(`Services/ObbyService`, numbers in `Config/Obby`). Auto-presses and passive
income keep earning while you run it, which is what makes Auto-Presser
upgrades (and the Auto Clicker passes) worth it here.

| # | Stage | Obstacle |
|---|---|---|
| 1 | First Steps | 4 easy jumps |
| 2 | Stairway | 5 rising platforms |
| 3 | Hot Floor | walkway with 3 kill strips to jump |
| 4 | Tightrope | two 1.6-stud beams |
| 5 | Ferry | moving platform over a 26-stud gap |
| 6 | Spinner | rotating kill bar |
| 7 | Zigzag | alternating side platforms |
| 8 | Ladder | 16-stud truss climb |
| 9 | Elevators | two lifts (+10 and +8 studs) |
| 10 | Islands | six 3.5-stud islands |
| 11 | Double Spin | two spinners turning opposite ways |
| 12 | Leap of Faith | three 8-stud jumps |
| 13 | Needle | four 1.4-stud beams |
| 14 | Lava Ferry | moving platform over lava |
| 15 | Summit | climb to the golden finish |

* **Checkpoints** (cyan pads; cleared ones turn green for you, the next one
  pulses). Kill bricks and falling 30 studs below your checkpoint put you back
  on it, and so does respawning mid-run, also after rejoining.
* **Rewards** (server only): each checkpoint in a run pays base press value ×
  25 × stage number in Sparks; the first time a stage is ever cleared +5 💎
  (+25 💎 on stages 5, 10, 15). Finishing pays base press value × 600 Sparks
  and +10 💎 (+100 💎 the first time; +50 / 100 / 250 / 500 💎 at 5 / 10 / 25 /
  50 completions), resets the run and returns you to the plaza.
* **Anti-cheat:** the server samples positions every 0.1 s instead of
  trusting messages. Checkpoints count only in order and while alive, and
  only if the segment took at least distance / 45 studs per second (and ≥ 2
  s). A jump of more than 40 studs between samples that the server did not
  cause is flagged and freezes progress for 4 s. The ▶ / 🏠 buttons can only
  move you to your own saved checkpoint or the plaza.
* **Saved:** current stage, best stage, completions and total checkpoints.

## Tutorial

New players get a short guided tutorial (`Config/Tutorial`,
`Services/TutorialService`, `Client/Tutorial`): a coach card at the top, an
arrow and a glowing ring on the right HUD element.

1. Press the button 10 times.
2. Buy your first upgrade in the Shop.
3. Open a crate (the starter quest gives a free one).
4. Equip an item.
5. Open the quests.
6. Reach obby checkpoint 1.
7. Learn about Auto-Presser upgrades (Got it!).

Steps complete only when the server sees the real result (counters such as
presses or crates opened grow from the moment the step starts; auto-presses
do not count as pressing). The client can only send "I looked at it" for the
two look-at steps while they are active, "skip" and "replay". Finishing pays
50 💎 once. Skipping is saved; Settings → Tutorial → Replay starts it again.
Players whose data was saved before the tutorial existed never see it.

## Robux store (game passes and developer products)

Optional purchases, opened from **💰 Store** in the bottom menu. Full
setup and the security rules are in [`MONETIZATION.md`](MONETIZATION.md).

* **Game passes** (buy once): Auto Clicker (+5 auto presses/s, beyond the
  upgrade cap), OP Auto Clicker (+15/s), 2× Sparks, 3× Sparks (×6 together),
  2× Gems, Lucky Pass (+50% Luck), Super Luck (+150% Luck), Fast Crates (no
  animation, open ×20) and VIP (×1.25 Sparks, Gems and XP). All multipliers
  stack.
* **Developer products** (repeatable): Gem packs (100 / 550 / 1,200), Sparks
  Rush (×3 Sparks for 15 minutes of play time, stackable), a Crate Bundle (5
  of the best unlocked Spark crate) and three OP crates for 99 / 199 / 299 R$
  with a guaranteed Epic / Legendary / Mythic or better, plus the Rainbow Chest
  (a guaranteed Rainbow item, Epic or better). These items come from the
  crates the player has already unlocked.
* Ownership and rewards are decided on the server only. Items without a
  Roblox ID in the config do nothing and are hidden in live games.
* Crate openings use layered, pitch-shifted built-in sounds: ticks that speed
  up and rise, a whoosh and boom on the burst, a chime per card that climbs
  in pitch, and a fanfare that grows with the best rarity (Epic, Legendary,
  Mythic/Secret with an extra flash). Every crate sound has a `Custom` slot
  in `Config/Sounds` for Creator Store audio.
