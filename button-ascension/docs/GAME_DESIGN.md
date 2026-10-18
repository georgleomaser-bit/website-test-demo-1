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

## Items (74)

* Every crate has 11 items (3 Common, 2 Uncommon, 2 Rare, 1 Epic,
  1 Legendary, 1 Mythic, 1 Secret). The Prism Cache has 8 items, Rare or
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
  crate tier factor × the Gem multiplier. Items from the Gem-priced Prism
  Cache use a sell factor of 0.1 instead, so buying caches and selling the
  drops always loses Gems. Even fully maxed, a cache resells for at most
  about 36 of its 120 Gems. Favourite items cannot be sold. The
  *auto-sell duplicates* setting sells repeat drops up to a chosen rarity the
  moment they drop.
* **Collection Book:** +1% Sparks per discovered item. Milestones at 5, 10,
  20, 30, 40, 50, 60 and all 74 discoveries give Gems, Skill Points, crates
  and Prisms.

## Skill tree (30 nodes, permanent)

| Branch | Direction | Highlights |
|---|---|---|
| Core | centre | Awakening: +10% Sparks |
| Strength | up | Click power +15%/+25% per rank, combo cap and window, streak bursts, Titan Grip ×1.5, **Button Crusher ×2** |
| Fortune | right | Luck, bonus items, crate discount, golden chance, Pity Breaker, **Fortune's Favorite +75% luck** |
| Wealth | down | Sparks %, passive %, Gems %, offline earnings, extra auto-presses, **Golden Economy ×1.75** |
| Precision | left | Crit chance and multiplier, **Supercritical** |
| Special | diagonals | Equip slots, XP, Prism yield, orb frequency/rewards. Each needs either of two neighbouring branches. |

The four branch capstones (Button Crusher, Fortune's Favorite, Golden
Economy, Supercritical) are the end of each branch. A respec costs 100 Gems
and refunds every point.

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
