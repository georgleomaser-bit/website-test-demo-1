# Robux store: game passes and developer products

## Kurzanleitung (Deutsch)

1. Spiel veröffentlichen (**Datei → Bei Roblox veröffentlichen**).
2. **Game Passes** anlegen: create.roblox.com → **Creations** → dein Spiel →
   **Monetization → Passes → Create a Pass**. Bild hochladen (fertige Bilder
   liegen in `branding/passes/`), Name und Beschreibung aus der Tabelle unten
   eintragen, speichern. Dann im Pass unter **Sales** „Item for Sale“
   einschalten und den Preis setzen.
3. **Developer Products** anlegen: **Monetization → Developer Products →
   Create a Developer Product**. Name, Beschreibung und Preis aus der Tabelle
   unten eintragen.
4. Die **ID** jedes Passes und Produkts kopieren und in Studio eintragen:
   * Passes: `ReplicatedStorage/Shared/Config/GamePasses` → `GamePassId = 123456789,`
   * Produkte: `ReplicatedStorage/Shared/Config/DevProducts` → `ProductId = 123456789,`
5. Erneut veröffentlichen. Fertig: Der **💰 Store** im Spiel zeigt alles an.
   Solange eine ID `0` ist, ist der Artikel im Live-Spiel unsichtbar und tut
   nichts. In Studio wird er als „Not set up“ angezeigt.

In Studio sind Käufe Testkäufe ohne echte Robux. Ein in Studio „gekaufter“
Pass gilt nur für diese Sitzung. Developer Products werden in Studio nur
vergeben, wenn **Studio-Zugriff auf API-Dienste** eingeschaltet ist, weil der
Kauf zuerst gespeichert werden muss.

## Game passes (buy once, keep forever)

| Pass | Effect | Suggested price | Config key |
|---|---|---|---|
| 🤖 Auto Clicker | +5 auto presses per second, on top of the upgrade limit | 99 R$ | `auto_clicker` |
| 🚀 OP Auto Clicker | +15 auto presses per second (+20 with Auto Clicker) | 349 R$ | `op_auto_clicker` |
| ⚡ 2× Sparks | ×2 Sparks (presses, auto presses, passive income) | 199 R$ | `double_sparks` |
| 🌟 3× Sparks | ×3 Sparks; with 2× Sparks ×6 | 799 R$ | `triple_sparks` |
| 💎 2× Gems | ×2 Gems from quests, achievements, golden presses, orbs and selling | 149 R$ | `double_gems` |
| 🍀 Lucky Pass | +50% Luck | 249 R$ | `lucky` |
| 🎰 Super Luck | +150% Luck; with Lucky Pass +200% | 599 R$ | `super_luck` |
| 📦 Fast Crates | No opening animation, open up to 20 crates at once | 499 R$ | `fast_crates` |
| 👑 VIP | ×1.25 Sparks, ×1.25 Gems, ×1.25 XP | 399 R$ | `vip` |

All multipliers stack multiplicatively. With every pass, Sparks are ×7.5,
Gems ×2.5, Luck +200% and auto presses +20 per second.

**How ownership works (server only):**

* When a player's data loads, `GamePassService` asks Roblox
  (`MarketplaceService:UserOwnsGamePassAsync`, up to 3 tries) about every
  configured pass and stores the answer in the player's data (`Passes`).
* If Roblox can't answer, the stored answer is kept, so an outage neither
  removes a pass nor grants one. A refunded pass disappears on the next
  successful check.
* When a purchase finishes, Roblox fires `PromptGamePassPurchaseFinished`
  on the server, and the pass is granted and saved immediately.
* There is no remote for purchases. The client can only open Roblox's
  prompt, so nothing an exploiter sends can grant anything.
* Effects are computed in `Shared/Formulas`, so the Store, the HUD and the
  server always show the same numbers. Passes without an ID never count.

## Developer products (buy any time)

| Product | Reward | Suggested price | Config key |
|---|---|---|---|
| 💎 Pouch of Gems | +100 Gems | 49 R$ | `gems_small` |
| 💎 Sack of Gems | +550 Gems | 199 R$ | `gems_medium` |
| 💠 Vault of Gems | +1,200 Gems | 399 R$ | `gems_large` |
| 🔥 Sparks Rush | ×3 Sparks for 15 minutes of play; each purchase adds 15 minutes (max 24 h stored) | 99 R$ | `sparks_rush` |
| 🎁 Crate Bundle | 5 of the best Spark crate the player has unlocked | 149 R$ | `crate_bundle` |
| 🔥 OP Crate | Opens at once: Epic or better (Epic 70%, Legendary 24%, Mythic 5.5%, Secret 0.5%) | 99 R$ | `op_crate` |
| 💥 Mega OP Crate | Legendary or better (Legendary 80%, Mythic 18%, Secret 2%) | 199 R$ | `mega_op_crate` |
| 🌌 Ultra OP Crate | Mythic or better (Mythic 92%, Secret 8%) | 299 R$ | `ultra_op_crate` |

* **Sparks Rush** time only runs while the player is in a game, and
  stacking adds time. The HUD and the Store show the time left. Quest targets
  and offline earnings ignore the boost (base stats).
* **OP crates** are not normal crates. They are in `Config/Chests` →
  `RobuxList`, outside `Chests.List`, so they can never be opened with
  Sparks or Gems, stored as owned crates, or affect pity. The odds above are
  before Luck; Luck (including the Luck passes) shifts them upward. The item
  is drawn from the combined pools of every crate the player has already
  unlocked. Nobody gets items from a stage they haven't reached, and the
  item is a normal collectible (it can be sold, equipped and counts for the
  Collection Book). The server rolls with its own `Random`, adds the item to
  the inventory, saves, and then tells the client to play the usual opening
  animation (purely cosmetic).

**`ProcessReceipt` rules** (`ProductService`):

1. Unknown or unconfigured product, buyer not in this server, data not loaded
   within 20 s, or a session that can't save (temporary Studio data, lost
   session lock, leaving) → `NotProcessedYet`. Roblox retries later, also
   after a rejoin.
2. Each receipt's `PurchaseId` is stored in the player's data (the newest
   100). A receipt already in that list is never granted again.
3. The reward is applied, the purchase ID recorded and the data saved
   (`DataService:SaveNow`). `PurchaseGranted` is returned **only after the
   save succeeded**; otherwise `NotProcessedYet`, and on the retry the stored
   ID prevents a second grant while the save is attempted again.

Saving can still fail if Roblox's DataStores are down; in that case the
purchase stays unconfirmed and Roblox keeps retrying. Nothing is ever
reported as saved when it wasn't.

## Economy notes

* Robux → Gems (Gem packs, selling OP crate items) is intended.
  Gems → more Gems is not. The economy test owns every pass and maxes every
  bonus, and still finds that a Prism Cache (120 Gems) resells for at most
  about 94 Gems.
* Passes stack with everything else, including server events and Frenzy.
  Leaderboards therefore favour pass owners, as in most Roblox games.

## Files

| File | Role |
|---|---|
| `ReplicatedStorage/Shared/Config/GamePasses` | Pass list, effects, prices, IDs |
| `ReplicatedStorage/Shared/Config/DevProducts` | Product list, rewards, prices, IDs |
| `ReplicatedStorage/Shared/Config/Chests` (`RobuxList`) | OP crate odds |
| `ServerScriptService/Services/GamePassService` | Ownership checks and purchase events |
| `ServerScriptService/Services/ProductService` | `ProcessReceipt`, boost timers |
| `ServerScriptService/Services/ChestService` (`OpenRobuxCrate`) | OP crate rolls |
| `StarterPlayerScripts/Client/Screens/Store` | The 💰 Store window |
| `tests/specs/monetization.spec.luau` | Automated tests |
| `branding/passes/` | 512 × 512 images for the passes and OP crates |
