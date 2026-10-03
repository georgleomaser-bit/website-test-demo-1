# ☄️ METEOR HEIST – Schritt-für-Schritt-Anleitung

Dein eigenes Roblox-Spiel mit der Grundbasis von „Steal an Egg“, aber eigenem Thema:

> **Meteore krachen in den Krater → du kaufst sie → trägst sie in deine Base → sie bringen Geld →
> du klaust bei anderen → die anderen bonken dich → Rebirth → immer bessere Meteore.**

---

## 📦 Was alles drin ist

| Bereich | Inhalt |
|---|---|
| **Kern-Loop** | Meteore schlagen im Krater ein (meistens kleine, selten riesige), kaufen mit **E**, in die Base tragen, Geld am grünen Pad einsammeln |
| **Klauen** | Bei fremden Basen **E** halten → Meteor tragen → in deine Base rennen |
| **Verteidigen** | **Bonk-Schläger** (Klick): getroffene Diebe verlieren die Beute. Rotes **Lock-Pad** sperrt deine Base für 60 s |
| **Twist 1: Aufladen** | Meteore in deiner Base leveln auf (Lv 1 → 20, ca. 3 h). Große, geladene Meteore sind Gold wert, auch zum Klauen |
| **Twist 2: Meteoritenschauer** | Alle 8 Minuten: 60 s lang **keine Locks**, 3x Glück, viel mehr Meteore → Chaos |
| **Fallenlassen** | Wer mit einem *gekauften* Meteor gebonkt wird, lässt ihn fallen → **gratis für alle** |
| **Speed Farm** | 60 Speed-Level für Cash (immer teurer). Schneller = zuerst am Meteor und entkommt beim Klauen |
| **Lange Progression** | 27 Meteore, 9 Seltenheiten (Common → Secret), Preise bis in die Billionen, Celestial/Divine/Secret erst nach Rebirth kaufbar |
| **Index** | Alle Meteore sammeln, jeder neue Typ gibt dauerhaft **+2 % Einkommen** |
| **Rebirth** | +50 % Einkommen für immer, schaltet neue Seltenheiten frei (Speed + Index bleiben) |
| **Tagesbonus** | Mit Streak bis Tag 7 |
| **Offline-Einkommen** | 25 % für bis zu 3 h |
| **Geld-Einnahmen** | 6 Gamepasses + 8 Developer Products + Premium-Bonus |
| **Admin-Panel** | Nur für deine UserId: Meteore spawnen, Meteorregen, Geld/Rebirths/Speed setzen, Pässe schenken, Glück-Events und Schauer (auch auf ALLEN Servern), Nachrichten, Kick/Bann/Entbannen, Reset, Teleport |
| **Technik** | Sicheres Speichern mit Session-Lock (keine Duplikate, kein Datenverlust), Käufe doppelt abgesichert, alles serverseitig geprüft (Exploiter können nichts schummeln), globale Top-10-Bestenliste |

Die **komplette Map baut sich automatisch** per Code. Du musst in Studio nichts zusammenbauen.

---

## 🚀 SCHRITT 1 – Spiel in Roblox Studio öffnen

1. Installiere **Roblox Studio**: https://create.roblox.com → „Start Creating“.
2. Lade die Datei **`MeteorHeist.rbxlx`** aus diesem Ordner herunter
   (auf GitHub: Datei anklicken → Download-Button „Download raw file“).
3. Öffne Roblox Studio → **File → Open from File…** → `MeteorHeist.rbxlx` wählen.

## 👑 SCHRITT 2 – Admin-Panel NUR für dich freischalten

1. Öffne dein Roblox-Profil im Browser. In der Adresszeile steht z. B.
   `https://www.roblox.com/users/123456789/profile`. Die Zahl **123456789** ist deine **UserId**.
2. In Studio links im **Explorer**: `ReplicatedStorage → Shared → Config` doppelklicken.
3. Ganz oben ändern:
   ```lua
   Config.AdminUserIds = {
       123456789, -- deine UserId
   }
   ```
4. Speichern mit **Strg + S**.

> Im Studio-Test ist jeder Tester Admin (zum Ausprobieren). Im echten Spiel **nur** die IDs in der Liste.
> Das wird auf dem Server geprüft, Hacker können das Panel also nicht benutzen.

## ▶️ SCHRITT 3 – Testen

1. Oben auf **Play** (F5) klicken.
2. Du spawnst in deiner Base. Lauf in den Krater, drück **E** an einem Meteor, renn zurück in deine Base.
3. Lauf über das **grüne Pad**, um Geld einzusammeln. Das **rote Pad** sperrt deine Base.
4. Admin-Panel: Taste **P** oder Button **🛠️ Admin** links.
5. Mehrere Spieler testen: **Test → Clients and Servers → 2 Players → Start**, dann kannst du dich selbst beklauen.

## 🌍 SCHRITT 4 – Veröffentlichen

1. **File → Publish to Roblox** → neues Spiel erstellen, Namen eingeben (z. B. „☄️ Meteor Heist“).
2. **Home → Game Settings → Security** → **„Enable Studio Access to API Services“** = AN → Save.
   (Erst dann speichert das Spiel auch beim Testen in Studio.)
3. **Spieler pro Server auf 8 setzen** (es gibt genau 8 Basen):
   Game Settings → **Places** → beim Place auf **⋯ → Edit** → **Max Players = 8** → Save.
   (Alternativ: Creator Dashboard → dein Spiel → Places → Place → Einstellungen.)
4. Game Settings → **Permissions** → Playability: **Public** (wenn du bereit bist).
5. Nach Änderungen immer wieder **File → Publish to Roblox** (Alt + P).

## 💰 SCHRITT 5 – Geld verdienen (Robux)

### Gamepasses anlegen
1. https://create.roblox.com/dashboard/creations → dein Spiel → **Monetization → Passes → Create a Pass**.
2. Bild hochladen, Name, dann **Sale → Item for Sale = AN**, Preis setzen.
3. Die **Pass-ID** kopieren (steht in der URL oder unter „Copy Asset ID“).
4. In `Config` bei `Config.GamePasses` die passende `Id = 0` durch deine ID ersetzen.

### Developer Products anlegen (beliebig oft kaufbar = Haupteinnahme!)
1. Dein Spiel → **Monetization → Developer Products → Create**.
2. Name, Preis, Bild → speichern → **Product-ID** kopieren.
3. In `Config.Products` die `Id = 0` ersetzen.

### Preisempfehlungen (bewährt bei Spielen dieser Art)

| Gamepass | Preis | | Product | Preis |
|---|---|---|---|---|
| 💰 2x Cash | 399 R$ | | 💵 Cash S | 25 R$ |
| 👑 VIP | 249 R$ | | 💰 Cash M | 99 R$ |
| ☄️ +5 Plätze | 199 R$ | | 🏦 Cash XL | 399 R$ |
| 🤖 Auto Collect | 149 R$ | | 🍀 2x Server-Glück | 79 R$ |
| ⚡ 2x Aufladen | 299 R$ | | 🌠 Meteoritenschauer | 49 R$ |
| 👟 Speed Boots | 99 R$ | | 🏃 +10 Speed | 39 R$ |
| | | | 🌟 Legendary Meteor | 149 R$ |
| | | | 🔮 Mythic Meteor | 449 R$ |

**Warum das zieht:** Server-Glück und Meteoritenschauer werden **allen im Server angekündigt**
(„Max hat 2x Glück für ALLE gekauft!“). Das macht andere neugierig und sie kaufen auch.
Cash-Pakete skalieren mit dem Einkommen, bleiben also auch für Profis interessant.

**Premium Payouts:** Roblox zahlt dir automatisch Robux, wenn Premium-Mitglieder dein Spiel spielen.
Premium-Spieler bekommen im Spiel +10 % (Anreiz, länger zu bleiben).

**Auszahlung in echtes Geld (DevEx):** ab 13 Jahren, verifizierte E-Mail + ID, Mindestbetrag laut
Roblox (aktuell 30.000 verdiente Robux). Infos: https://create.roblox.com/dashboard/devex

## 📈 SCHRITT 6 – Spieler bekommen

Die Technik ist für sehr viele Spieler gebaut (siehe unten), aber **ob 100.000 Leute kommen, hängt am
Marketing und am Roblox-Algorithmus**. Das kann niemand garantieren. Was am meisten hilft:

1. **Icon + Thumbnails**: knallig, ein riesiger glühender Meteor, ein Spieler der flüchtet. Titel mit Emoji: `☄️ Meteor Heist`.
2. **Erste 5 Minuten** entscheiden. Das Spiel gibt sofort Geld und erste Meteore, perfekt dafür.
3. **Updates jede Woche** (neue Meteore/Events) → „UPDATE 🔥“ im Titel. Schreib mir einfach, was rein soll.
4. **TikTok/YouTube Shorts**: „Ich habe einen SECRET Meteor geklaut 😱“ Clips.
5. **Roblox-Werbung** (Ads Manager): mit kleinem Budget testen, sobald die Spielzeit pro Spieler gut ist.
6. **Codes & Events** am Wochenende (Admin-Panel → Glück auf ALLEN Servern).

## 🛠️ Admin-Panel – was kann es?

| Bereich | Funktion |
|---|---|
| 🎯 Ziel | `me`, `all`, `others`, (Teil vom) Spielernamen oder UserId. „Spieler laden“ zeigt alle im Server |
| ☄️ Spawnen | Jeden Meteor + Mutation wählen → **Im Krater** (fällt mit Ankündigung), **Vor mir**, **Gratis vor mir**, **In Ziel-Base** (inkl. Level) |
| 🌧️ Meteorregen | 10-40 Meteore einer Seltenheit regnen herab |
| 💰 Werte | Cash geben/setzen, Rebirths setzen, Speed-Level setzen, Gamepässe schenken (bis Server-Wechsel) |
| 🎉 Events | X-fach Glück für Y Minuten, Meteoritenschauer, Nachricht an alle. Mit 🌍 **auf ALLEN Servern gleichzeitig** |
| 🛡️ Moderation | Kick, Bann (Tage oder für immer, gilt fürs ganze Spiel), Entbannen per UserId, Base leeren, Spielstand zurücksetzen, Teleport zu/holen, Krater leeren. Bann/Reset brauchen einen zweiten Klick |

## ⚙️ Balancing – alles in `Config`

Alles steht kommentiert in `ReplicatedStorage → Shared → Config`:
- **Neuen Meteor** hinzufügen: eine Zeile in `Config.Meteors` kopieren, neue `Id` vergeben.
- Spawnchancen: `Config.Rarities` (Weight). Preise/Einkommen pro Meteor.
- Schauer-Takt, Lock-Dauer, Speed-Kosten, Rebirth-Kosten, Aufladezeit …
- ⚠️ **`DataStoreName` nie ändern**, sonst sind alle Spielstände weg.

---

## 🔄 Updates mit mir (Claude) machen

Schreib mir einfach in diesem Chat, was du willst (z. B. „neues Event“, „neue Meteore“, „Fehler XY“).
Ich ändere den Code und lade ihn hier ins GitHub-Repo hoch. Danach gibt es 3 Wege:

**A) Am einfachsten:** neue `MeteorHeist.rbxlx` herunterladen und öffnen → `Config` (deine IDs) kurz
prüfen → Publish. Das klappt, weil alles im Spiel per Code gebaut ist. Wenn du in Studio selbst
Sachen gebaut hast, nimm Weg B oder C.

**B) Nur einzelne Skripte ersetzen:** Ich sage dir, welche Datei sich geändert hat (z. B.
`src/server/Services/MeteorService.luau`). In Studio das gleichnamige Skript öffnen, alles markieren,
den neuen Inhalt von GitHub reinkopieren, Publish.

**C) Profi-Weg mit Live-Sync (Rojo):** Code von GitHub landet automatisch in Studio.
1. In Studio: **Toolbox → Plugins** → „Rojo“ installieren.
2. Auf dem PC [Rokit](https://github.com/rojo-rbx/rokit) installieren, dann im Terminal `rokit add rojo-rbx/rojo`.
3. Repo klonen: `git clone <dein Repo-Link>` → in den Ordner `roblox-meteor-heist` wechseln → `rojo serve`.
4. In Studio im Rojo-Plugin auf **Connect** klicken.
5. Bei jedem Update von mir: `git pull` → Studio übernimmt die Änderung sofort → Publish.

### „Kann ich dich direkt mit Roblox Studio verbinden?“
Aus diesem Cloud-Chat kann ich dein Studio nicht direkt fernsteuern. Ich schreibe den Code, und Weg C
(Rojo) bringt ihn live in dein Studio. Wenn du **Claude Code** oder **Claude Desktop auf deinem PC**
installierst, gibt es den offiziellen **Roblox Studio MCP Server** von Roblox. Damit kann Claude
Studio direkt steuern (Objekte bauen, Skripte einfügen, testen).

---

## 🧯 Fehlerbehebung

| Problem | Lösung |
|---|---|
| Spielstand wird in Studio nicht gespeichert | Schritt 4.2: „Enable Studio Access to API Services“ einschalten (Spiel muss veröffentlicht sein) |
| Admin-Panel fehlt im echten Spiel | UserId in `Config.AdminUserIds` falsch, nochmal prüfen und neu publishen |
| Shop zeigt „Bald verfügbar“ | Die ID in `Config` ist noch `0` |
| „Server voll – keine Base frei“ | Max Players auf 8 stellen (Schritt 4.3) |
| Rote Fehler im **Output**-Fenster | Text kopieren und mir hier schicken, ich fixe es |
| Kauf kam nicht an | Roblox wiederholt den Kauf automatisch, bis er verbucht ist. Nichts geht verloren |

---

## 🧠 Technik: warum das für sehr viele Spieler funktioniert

- Roblox startet **automatisch so viele Server wie nötig** (je 8 Spieler). 100.000 Spieler ≈ 12.500 Server;
  das skaliert Roblox selbst.
- **Speichern** nutzt pro Spieler nur ca. 1 Schreibzugriff alle 90 Sekunden, weit unter Roblox' Limits.
  Session-Lock verhindert Duplikate beim Server-Wechsel, `BindToClose` speichert beim Herunterfahren.
- **Käufe** werden im Spielstand protokolliert → nie doppelt, nie verloren.
- **Anti-Cheat:** Der Client zeigt nur an. Kaufen, Klauen, Geld, Admin werden alle auf dem Server geprüft
  (Distanz, Geld, Besitz, Lock, Spam-Bremse).
- **Performance:** wenige einfache Parts, Updates gebündelt (max. 5x/s pro Spieler), Map wird einmal gebaut.

## 📁 Dateien

```
roblox-meteor-heist/
├── MeteorHeist.rbxlx          ← diese Datei in Studio öffnen
├── ANLEITUNG.md               ← du bist hier
├── default.project.json       ← für Rojo (Weg C)
└── src/
    ├── shared/   (ReplicatedStorage.Shared)
    │   ├── Config.luau        ← ALLE Einstellungen
    │   └── Util.luau
    ├── server/   (ServerScriptService.Server)
    │   ├── Main.server.luau
    │   └── Services/          Data, Plot, Meteor, Carry, Economy, Monetization, Admin, Leaderboard …
    └── client/   (StarterPlayerScripts.Client)
        └── Main.client.luau   ← gesamte Oberfläche
```
