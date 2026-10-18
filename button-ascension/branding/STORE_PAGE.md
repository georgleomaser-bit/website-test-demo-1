# Click a Button: Roblox store page

Everything for the experience page on Roblox: name, description, icon and
thumbnails. The game's interface is in English, so the English description is
the main one; a German version follows.

## Name

```
Click a Button
```

## Description (English, main)

```
Press the big neon button, earn Sparks and turn a single click into an empire! 🔴

⚡ PRESS: crits, combos, streaks and auto clickers that keep earning while you play
🎁 OPEN CRATES: 81 items, 7 rarities from Common to Secret, with pity
✨ FUSE: combine 3 copies into Golden, then into Rainbow items
🏃 OBBY: 15 stages with checkpoints and rewards, while you keep earning
🌳 SKILL TREE: 65 skills that reveal themselves as you unlock them
🔷 ASCEND: rebirth for Prisms and permanent perks, unlock 5 stages
📜 EVERY DAY: quests, login rewards, achievements and leaderboards
💰 STORE: Auto Clicker, OP passes and OP crates

New here? A short tutorial shows you everything.
Plays on PC, phone, tablet and controller. Progress is saved automatically.

Can you find all 81 items, including the Secret ones? 👀
```

## Beschreibung (Deutsch)

```
Drück den großen Neon-Button, sammle Sparks und mach aus einem Klick ein Imperium! 🔴

⚡ DRÜCKEN: Crits, Combos, Streaks und Auto-Klicker, die beim Spielen weiterverdienen
🎁 KISTEN: 81 Items, 7 Seltenheiten von Common bis Secret, mit Pity
✨ FUSEN: 3 gleiche Items werden zu Golden, dann zu Rainbow
🏃 OBBY: 15 Stufen mit Checkpoints und Belohnungen, während du weiterverdienst
🌳 SKILL-BAUM: 65 Skills, die sich beim Freischalten nach und nach zeigen
🔷 AUFSTIEG: Rebirth für Prismen und dauerhafte Boni, 5 Stufen freischalten
📜 JEDEN TAG: Quests, Login-Belohnungen, Erfolge und Ranglisten
💰 STORE: Auto-Klicker, OP-Pässe und OP-Kisten

Neu hier? Ein kurzes Tutorial zeigt dir alles.
Spielbar auf PC, Handy, Tablet und Controller. Dein Fortschritt wird automatisch gespeichert.

Findest du alle 81 Items, auch die geheimen? 👀
```

Both versions are under Roblox's 1,000-character limit.

## Images

| File | Size | Use |
|---|---|---|
| [`icon.png`](icon.png) | 512 × 512 | Experience icon |
| [`thumbnail.png`](thumbnail.png) | 1920 × 1080 | Thumbnail 1 (main banner) |
| [`thumbnail-crates.png`](thumbnail-crates.png) | 1920 × 1080 | Thumbnail 2 (crates and rarities) |

The drop rates on thumbnail 2 are the real Spark Crate odds from
`src/ReplicatedStorage/Shared/Config/Chests.luau`. If you change the odds,
update `src/thumbnail-crates.html` and render the images again.

## Uploading

1. Publish the place first (**File → Publish to Roblox**).
2. In Roblox Studio open **Home → Game Settings → Basic Info**.
3. Paste the name and the description.
4. Under **Game Icon**, upload `icon.png`. Under **Thumbnails**, upload
   `thumbnail.png` first, then `thumbnail-crates.png`.
5. Click **Save**. New images are moderated by Roblox and can take a few
   minutes to show up.

You can also change all of this later in the Creator Hub
(create.roblox.com → Creations → your experience).

## Editing the images

The images are drawn as SVG inside the HTML files in `src/` and rendered to
PNG with Playwright and Chromium:

```sh
cd button-ascension
NODE_PATH=$(npm root -g) node branding/src/render.mjs
```
